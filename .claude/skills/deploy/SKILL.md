---
name: deploy
description: "Use when deploying or operating silken_net infrastructure — Kamal/Terraform GCP, Akash decentralized cloud, secrets, observability (Grafana Alloy → Grafana Cloud), disaster-recovery, CI/CD, resilience/failover. This is Module 06 'The Matrix'. Routes to the 06_xx canon docs and the load-bearing infra invariants; does not restate them."
---

# Deploy & Infrastructure (Module 06 — The Matrix)

DevOps/Infra шар: Rails на **Akash** (децентралізовано, цензуростійко) +
**GCP** (Cloud SQL / Redis / failover). Деплой через **Kamal**, IaC через
**Terraform**, спостережуваність через **Grafana Alloy → Grafana Cloud**.

## Канон — читати ПЕРЕД зміною інфри/секретів/метрик

SSOT One-Home: цей skill лише **маршрутизує**; факти живуть у `docs/` + config-SSOT.
Не дублюй сюди значення/інвентар і **не хардкодь `file:line`** (дрейфує — стале вже за
комітом). Посилайся на стабільні якорі: канон-§ + імена символів/шляхів.

| Що треба | Канон-дім |
|---|---|
| Деплой **Kamal + Terraform GCP**, Canopy vs Production | `06_01` ← read-first для деплою |
| **Akash** SDL (`web` + `job` + `alloy`), multi-provider failover | `06_02` |
| **Observability** — метрики / Alloy → Grafana Cloud / alerting | `06_03` (реєстр метрик — `06_03 §2.8`) |
| **Секрети** — інвентар + checklist (GitHub / Kamal / Akash / Terraform) | `06_04` (canonical = `config/deploy.yml env.secret`) |
| **Puma 8** config + cluster hooks + runbook'и | `06_05` |
| **Disaster Recovery** / backup / RTO-RPO / master-key | `06_06` (config SSOT = `terraform/database.tf`) |
| **CI/CD** workflows + єдиний operations runbook-індекс | `06_07` |
| **Resilience** — Queen failover (4 рівні) + Per-Chain Fallback Matrix | `06_08` |

## Несучі інваріанти (не очевидні з коду)

Будь-хто, хто чіпає деплой, МУСИТЬ це знати:

- **Akash + GCP — failover, не «або-або».** Rails-ворклоад на Akash; GCP тримає
  Cloud SQL + є failover-ціллю (Redis — зовнішній **Upstash** Serverless TLS, не GCP). → `06_01` / `06_02`.
- **Cloud SQL Auth Proxy тунелює Postgres через outbound HTTPS** (Google Cloud API) —
  без публічного IP чи VPN. Запечений у Docker-образ; активується **лише** коли
  `CLOUD_SQL_INSTANCE_CONNECTION_NAME` заданий у ENV. → `06_02`.
- **Observability: Alloy → Grafana Cloud SaaS. Self-hosted Prometheus НЕ потрібен — за дизайном (OBS.1).**
  `/metrics` (`SilkenNet::Metrics::REGISTRY`) скрейпить Grafana Alloy sidecar (Akash SDL,
  `deploy/akash/config.alloy`) → `remote_write` → Grafana Cloud (storage + dashboards +
  alerting). Реєстр і кількість метрик — `06_03 §2.8` (regen з REGISTRY, **не хардкодь**).
- **Секрети One-Home:** канонічний дім — `config/deploy.yml env.secret`; повний
  інвентар + checklist — `06_04`. CI-гейт `verify-secrets`.
- **Akash SDL ENV — plaintext, видимий провайдеру.** Реальні ключі **ніколи** не в
  `deploy/akash/deploy.yaml`; інжектити через Akash Console / `env.secret`. → `06_02` / `06_04`.
- **Deploy/release ланцюг (2026-06-19).** Canopy = кожен push у `main` після CI (continuous);
  Production = GitHub Release, який тримає **release-please** (`Ops · Release`: semver+CHANGELOG із
  conventional commits → `release: published`); GHCR-mirror path-gated + пушить SLSA provenance+SBOM
  з образом (`gh attestation verify`). `verify-secrets` у Canopy **skip-clean** без секретів (Production
  лишається fail-loud). `main` захищено branch-protection (required `CI passed` + `Docs passed`,
  `enforce_admins=false` — owner пушить напряму). Деталі/діаграма — `06_07 §1`/`§2`.

## Карта коду / конфігів

| Шар | Шлях |
|---|---|
| Kamal deploy | `config/deploy.yml` · `config/deploy.canopy.yml` · `.kamal/secrets` |
| IaC (GCP) | `terraform/` (`compute.tf` · `database.tf` · `vpc.tf` · `iam.tf` · `main.tf`) |
| Akash | `deploy/akash/` (`deploy.yaml` SDL · `config.alloy` · `encode-alloy-config.sh`) |
| Observability | `config/initializers/prometheus.rb` (`SilkenNet::Metrics`) · `app/middleware/prometheus_collector.rb` · `deploy/akash/config.alloy` |
| Web-сервер | `config/puma.rb` |
| CI/CD | `.github/workflows/` (`deploy.yml` · `deploy-production.yml` · `mirror-ghcr.yml` · `release-please.yml` · `ci.yml` · `docs.yml` · `ssot_guard.yml`) |

## Gotchas (верифіковані, не з канону)

1. **jemalloc через `LD_PRELOAD`** у Docker-образі (`libjemalloc.so`) — менше пам'яті
   й латентності. Не прибирай без бенчмарку.
2. **`SENTRY_DSN` задається at deploy time** (`.kamal/secrets`); без нього Sentry
   інертний — нуль crash-репортів.
3. **Старт через Thruster** (`thrust ./bin/rails server`) за замовчуванням; overridable at runtime.

## Робочі правила

1. **Docs-first.** Прочитай `06_0N` (саме *чому* + поточний стан/TRL) перед зміною
   деплою, секрету чи метрики — кожен 06-док несе власний member-TRL у ✅ Статус.
2. **SSOT One-Home.** Правиш факт — правь у його домі (`06_04` секрети, `06_03 §2.8`
   метрики, `terraform/` config), не тут. Skill лишається тонким маршрутом.
3. **Гейти.** Після правок канону — `bin/rails docs:check_refs` зелений; робота над
   SSOT-доками 06_xx — через skill `ssot-maintenance`.
