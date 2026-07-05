# INF.23 — Load / Throughput Harness

Емпіричний вимір стелі пайплайну **CoAP-intake → Sidekiq-drain → chain**.
Грунтує оцінку E.5 «~10k вузлів» (донедавна — *припущення, не вимір*).
Канон-цілі SLO: [`06_08 §2.4`](../../../docs/06_08_Resilience_and_Failover_Policy.md)
(intake ≥95% / mint ≥80%); топологія черг ARCH.52 — `06_08 §2.5`.

## ⚠️ Найважливіше: dev-число — НЕ стеля потужності

**Bottleneck-class inversion.** На dev пайплайн **compute/GVL-bound** (local PG
~30µs + localhost Redis + `async`-cable + memory-cache). На prod він
**network-IO-bound**: Cloud SQL через auth-proxy (~0.5-1ms) + **Upstash** Redis
(мережа) + **`solid_cable`** (Postgres INSERT) + **`solid_cache`** (Cloud SQL).
Один пакет = ~8-9 DB-RTT + 2N Redis-LPUSH. dev-число **завищує prod у 10-50×** і
**не переноситься множником**.

Тому dev-прогін = **(а) regression-детектор** (чи діф сповільнив) + **(б)
structural-детектор** (де lock / serialization / GVL). Абсолютна стеля
народжується **лише на staging з prod-адаптерами**. `LoadReport.banner` друкує
клас над кожним числом; `capacity_valid` = `true` тільки коли адаптери prod-like.

## Компоненти

| Файл | Роль |
|---|---|
| `telemetry_batch_factory.rb` | детермінований валідний вхід (CoAP + AES-256-CBC батчі) |
| `coap_flood.rb` | intake UDP-flood (pre-gen + persistent socket + offered/achieved + kernel-drop) |
| `provisioning.rb` | realistic кластер (M дерев + партиції + warm cross-partition історія) |
| `drain_bench.rb` | drain: **backlog**→μ, **arrival**→sustainable-λ; композитний done-signal |
| `lorenz_microbench.rb` | ізольований pure-compute GVL-knee |
| `load_report.rb` | sorted-array перцентилі + Little's Law + CoV-гейт + bottleneck-банер |

## Модель навантаження (звірено з firmware + canon)

- Queens = **N/100** (50-200 Soldiers/Queen, `02_05 §2.1`); records/s = **N/3600**
  (~1 пакет/Soldier/год, енергобюджет). CIFO **дедуплікує за DID** (latest-wins),
  тригер flush `≥45 entries` або `1h TTL`; **Flash Ring OFF** → mass-reconnect =
  тонкі батчі + backlog-loss, не fat-drain.
- **report-interval Soldier'а = головна свіп-вісь** (firmware TX-гейт не
  локалізований; тримається енергобюджетом).

| Фаза | N | Queens | baseline rec/s | burst rec/s | де впирається |
|---|---|---|---|---|---|
| Pilot | 100 | 1 | 0.03 | ~50 (1 fat) | ніде |
| Phase 2 | 10k | 100 | 2.8 | ~415 | single-process Lorenz-GVL drain |
| Phase 3 | 1M | 10k | 278 | 833-8333 | money-starvation (ARCH.52) + GVL + DB-pool |

**UDP-intake — НЕ вузьке місце.** Стеля — drain-CPU (Lorenz, GVL-bound) +
money-fanout starvation (strict-priority) + DB-pool (3 Postgres-DB).

## Сценарії (що гарнес має генерувати, щоб бути чесним)

- **S1 baseline** — sustained per-phase rate; свіп report-interval + Soldiers/Queen.
- **S2 reconnect-burst** — K Queens flush у 60-с вікні (Ring OFF = тонкі батчі).
- **S3 panic-storm** — пожежа: M кластерів panic → AlertDispatch inline + EwsAlert.
- **S4 fat-batch + poisoned** — 50-record батч + 1 malformed (binary-search isolation).
- **S5 OTA-wave** — downlink-fanout + uplink-echo конкуренція.
- **S6 money-starvation** — firehose ‖ mint/slash, single-process → starvation
  доведено; flip process-ізоляції → обидва SLO (пряма валідація ARCH.52 §2.5).

## Використання

```bash
bin/coap_load --microbench --iterations 2000            # GVL-knee (pure compute)
bin/coap_load --flood --host 127.0.0.1 --uid SNET-Q-... --rps 2000 --duration 10 --workers 4
bin/coap_load --drain  --trees 200 --batches 500 --history 90   # μ (потребує живий Sidekiq)
bin/coap_load --arrival --trees 200 --lambda 5 --batches 300    # sustainable-λ check
```

## Staging-runbook (👤 — де народжується справжнє число)

1. **Prod-адаптери**: `REDIS_URL`=Upstash, `solid_cable`, `solid_cache`, Cloud SQL —
   інакше `capacity_valid=false` (клас не збігається).
2. **Realistic стан**: `--history` для warm cross-partition `previous_lorenz_state`
   + поточна+прев місячні партиції.
3. **Живий Sidekiq** із **money-path у виділеному процесі** (ARCH.52) — інакше
   strict-serialization завищить cascade-drain.
4. **Kernel UDP counters** (Linux `nstat -az | grep -i Udp` `RcvbufErrors`) — гарнес
   читає їх, бо loopback ховає NIC-ring-drop, а demon ковтає Redis-fail (PERF-3).
5. **CoV ≤ 0.05** (`LoadReport.coefficient_of_variation`) перед екстраполяцією;
   decompose-by-stage (compute масштабується clock-ratio, DB/Redis — network-topology).

## Емпіричні знахідки (dev, structural)

- **GVL-стеля ПЛОСКА**: `--microbench` 1/5/15 тредів → ~42k iter/s однаково.
  Pure-Ruby Lorenz не масштабується за concurrency → горизонталь = **процеси**,
  не треди (підтверджує ARCH.52).
- Performance-борги, підсвічені «діставанням нутрощів» → `00_07 §06` (PERF-*):
  `previous_lorenz_state_for` cross-partition MergeAppend (per-packet), 3-Postgres-DB
  pool-tripling, listener Redis-enqueue-fail без метрики.
