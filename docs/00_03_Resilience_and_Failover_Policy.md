# 00_03: Resilience and Failover Policy

## 🎯 Мета

Зафіксувати єдину політику резервування та відмовостійкості для двох найкритичніших ризик-векторів Gaia 2.0:

1. **Queen Gateway як Single Point of Failure** — фізичний шлюз між LoRa-мережею Солдатів і Akash/Rails.
2. **12-ланковий Web3-конвеєр як Lego Tower of Doom** — будь-яка зовнішня мережа (IoTeX, Streamr, Chainlink, Hadron, KlimaDAO, ...) може mute/cap/break.

Документ описує `Fallback / Retry / Buffer policy` для кожної ланки та механізм продовжувати Proof-of-Growth (`docs/05_02`) навіть при тимчасовій відсутності окремих мостів.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — політика затверджена, **6 з 10 Implementation Anchors ✅ Реалізовано** (Web3CircuitBreaker, Multi-RPC fallback, Queen self-telemetry, CoAP retry, Chainlink router probe, Manual review terminal state — див. §3). Залишаються 🟡: Queen-to-Queen Backhaul Mesh, Helium Queen-side LoRaWAN (ARCH.34), Ingress Proxy (INF.4/INF.6), Conductor L2 (HW.27, formerly "Sergeant"). Production-rollout — Phase 2 (`00_06`).
- **Пов'язані модулі:**
  - 8-рівнева архітектура + конвеєр → [`00_02_System_Architecture_and_12_Chain_Pipeline`](00_02_System_Architecture_and_12_Chain_Pipeline)
  - Hardware Queen → [`02_05_Queen_Hardware_and_Starlink`](02_05_Queen_Hardware_and_Starlink)
  - Prowadinij firmware → [`03_02_Queen_Gateway_Firmware`](03_02_Queen_Gateway_Firmware)
  - Multichain → [`05_01_Multichain_Architecture`](05_01_Multichain_Architecture)
  - Proof-of-Growth pipeline → [`05_02_Proof_of_Growth_Pipeline`](05_02_Proof_of_Growth_Pipeline)
  - Akash деплой → [`06_02_Akash_Network_Integration`](06_02_Akash_Network_Integration)
  - Циркул-брейкер concern → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services) `Web3CircuitBreaker`

---

## 🛑 Блокери

- **ARCH.26** (TDMA Sync Windows + CAD) — без них Queen-to-Queen Backhaul fallback неможливий для Soldier'ів за межами Queen RX, документується відкрито у [`00_08`](00_08_Action_Plan_Tracker).
- **INF.4 / INF.6** — Ingress Proxy / CoAP Proxy перед Rails — критично для буферизації uplink при недоступності backend pods на Akash.
- **HW.27** (Conductor L2, formerly "Sergeant") — повноцінний failover на L2 cluster heads потребує Conductor вузлів (Hub Trees, TRL 1, концепція).
- **ARCH.35** (Queen Flash Ring Buffer) — без SPI NOR Flash overflow tier, CIFO 50-slot RAM cache переповнюється за ~30 хв при 100 Soldiers/Queen × 1 пакет/год → дані стираються. SPI flash чип (W25Q32, ~$0.50) знімає це обмеження.
- **ARCH.34** (Queen-side LoRaWAN Helium fallback) — без LoRaWAN MAC stack на Queen, L3 Helium резерв архітектурно неможливий. Soldier-side `helium_compat_emit` (попередній план) відкинуто через flash/RAM constraints STM32WLE5JC + Soldier не повинен знати про uplink topology.

---

## 1. ☂️ Queen Gateway Failover Protocol

### 1.1 Чому це SPOF

У поточній архітектурі Queen — **єдиний always-on listener** і єдина точка виходу через Starlink/LTE для свого LoRa-кластера. Якщо Queen втрачає живлення, фізично знищена, втратила Starlink-зв'язок або переходить у `state: faulty` AASM — весь кластер (50–200 Soldier'ів) залишається без uplink.

### 1.2 Чотири рівні резервування

| Рівень | Механізм | Trigger | Latency | Реалізація |
|--------|----------|---------|---------|------------|
| **L1: Queen Local Buffer (Two-Tier)** | **Hot tier:** CIFO EdgeCache до 50 slots in-RAM (дедуплікація за DID + priority-aware eviction), flush на 1 год TTL або при ≥ 45 entries. **Overflow tier:** при `AT+CCOAPSEND` fail після N retry — drain CIFO у SPI NOR Flash Ring Buffer (W25Q32, 4 МБ, ~190k слотів × 21 байт; ARCH.35). Якщо Starlink/LTE недоступні — повторити flush експоненційно (1, 2, 4, 8, 16 хв cap = 60 хв). При відновленні uplink — спочатку drain Flash Ring Buffer (FIFO), потім CIFO. | `AT+CCOAPSEND` timeout або UART fail | Seconds (RAM tier) / Hours-days (Flash tier) | `firmware/queen/main.c` CoAP retry (FW.9), 4 host-tests `test_coap_retry_constants`; Flash Ring Buffer — ARCH.35 planned |
| **L2: Queen-to-Queen LoRa Backhaul** | Сусідня Queen у радіусі 5–15 км (SF12 спред-фактор, ~6 кбіт/с) приймає `delegate_uplink_frame` від основної Queen. Якщо власний Starlink також впав — пересилає далі по LoRa-магістралі до Queen з активним uplink. | Local Starlink/LTE down >5 хв OR `coap_health = false` | Minutes | `Queen → Queen` через `RELAY_QUEEN` фрейм (DEFAULT_TTL=4); планується [`02_05 §Q2Q Mesh`](02_05_Queen_Hardware_and_Starlink) |
| **L3: Helium Network Fallback (Queen-side)** | Queen формує валідний **LoRaWAN** frame (DevEUI/AppEUI/AppKey, FCntUp counter, OTAA join state) і передає його у радіусі своєї антени (+22 dBm SF12). Будь-який Helium hotspot у радіусі ~15 км приймає frame через стандартний LoRaWAN MAC-stack → Helium LNS → HTTP Integration webhook → Rails `POST /api/v1/telemetry/helium` (HMAC-signed). **NB:** Soldier лишається на raw LoRa P2P (AES-256-ECB, 21-байт payload); LoRaWAN stack живе ТІЛЬКИ на Queen. | Власний Starlink/LTE-M down + Q2Q backhaul недоступний (всі сусідні Queen теж offline) | Tens of seconds | Queen firmware `queen_helium_lorawan_uplink()` (ARCH.34, planned); деталі — [`02_05 §6.1 Helium Fallback`](02_05_Queen_Hardware_and_Starlink) |
| **L4: Field Operator Pull (Forester app)** | Лісник з мобільним пристроєм підходить до фізичної Queen, підключається через BLE (Forester app) і вручну дренує CIFO буфер на 4G/Wi-Fi. | Manual escalation коли L1-L3 fail >24 год | Hours-Days | Forester mobile app (UI заплановано Phase 2) |

### 1.3 Queen Health Heartbeat → Rails

Сама Queen відправляє себе як `DID == 0x00000000` (Queen Sentinel, [`03_02 §Queen Self-Telemetry`](03_02_Queen_Gateway_Firmware)) з полями: `vcap_mv`, `uptime_s`, `cifo_fill`, `coap_retries_24h`, `last_starlink_rssi`. Backend записує у `GatewayTelemetryLog` і обчислює:

- `online?` = `last_seen_at >= (sleep_interval * 1.2).seconds.ago` (поточна модель `Gateway`, [`04_01`](04_01_Data_Models_and_Entities))
- Якщо `online?` стає `false` довше 10 хв → `Gateway.state` AASM `mark_faulty!` + dispatch `EwsAlert(type: queen_offline)` → Forester Guild notify (Slack/SMS).

### 1.4 Dynamic Mesh Rerouting (Soldier-side)

Soldier'и **не знають**, що "їх" Queen впала. Вони продовжують TX. Але mesh-relay алгоритм (DEFAULT_TTL=3) природно прокидує пакет до сусідньої Queen, якщо вона у радіусі. Конкретно:

- Soldier емітує payload з `last_rssi_to_queen` у Header byte.
- Сусідній Soldier (Phase 4.5 RX window) ловить, помічає чужий пакет — якщо TTL > 0, релєює.
- Через 1–3 хопи пакет дотягується до сусідньої Queen у іншому кластері.
- Queen "B" приймає pakет із чужим `queen_uid` у payload-метадаті, нормально дренує його у CoAP, Rails по `peaq_did` дерева знає до якого кластера прив'язати телеметрію.

> **Передумова:** Для надійності цього шляху необхідні TDMA Sync Windows (ARCH.26) + CAD (SX1262) — інакше mesh relay стохастичний. Це не блокує політику в принципі, але обмежує її TRL до 4-5 поки FW.20 / ARCH.26 не закриті.

---

## 2. 🪜 Web3 Chain Fallback Matrix (Anti-Lego Tower)

### 2.1 Загальна абстракція: Local Buffer + Circuit Breaker

Жодна Web3-операція (peaq registration, IoTeX verification, Chainlink dispatch, Hadron compliance, KlimaDAO retire, Filecoin pin, L1 anchor) не повинна виконуватись **синхронно** в hot path Rails. Вже сьогодні всі вони — Sidekiq workers з `retry: 5` та `Web3CircuitBreaker` concern ([`04_02 §Web3CircuitBreaker`](04_02_Business_Logic_and_Services)).

Політика resilience:

1. **Buffer-first.** Запис у `TelemetryLog` / `BlockchainTransaction` / `AuditLog` відбувається **до** першої спроби Web3-виклику. Стан AASM `pending` / `processing` / `sent` / `confirmed` / `failed` / `manual_review` (див. `BlockchainTransaction` partitioning + `find_with_partition_pruning`).
2. **Circuit Breaker.** При 5+ підряд транзакторних помилках відповідного RPC — circuit `opens` на 60 секунд (lock-free counter у Kredis). Worker не пробує знову — повертає `Sidekiq::Retry` до cooldown.
3. **Exponential backoff retry.** За межами circuit breaker — стандартний Sidekiq retry з jitter.
4. **Manual review terminal state.** Якщо `tx_hash` отримано, але стан невизначений (double-spend guard) — переходить у `manual_review` AASM, кошти заблоковані до ручної перевірки.
5. **Graceful degradation.** Pipeline продовжує працювати на кроках, які НЕ залежать від downed ланки. Залежні кроки чекають у `pending`.

### 2.2 Per-Chain Fallback Policy

| Крок | Залежна ланка | Тип ризику | Fallback | Що блокує далі |
|------|---------------|------------|----------|----------------|
| 2. Akash hosting | Akash | Provider eviction, oracle price spike, no bidders | Multi-provider deployment (`deploy.yaml` SDL з multiple providers); fallback на GCP via Kamal (`docs/06_01`) — single-command failover за допомогою `kamal redeploy --hosts canopy`. | Цілий backend (всі 12 наступних кроків) — тому Akash redundancy P0. |
| 3. Streamr P2P | Streamr Network | Streamr API rate-limit / outage | Non-blocking publish (`StreamrBroadcastWorker`, `queue: low`, retry: 3). При остаточному фейлі — payload потрапляє в `streamr_undelivered` Kredis list (TTL 24 год). Власний P2P через ActionCable websockets залишається активним. | Нічого. Streamr — спостерігач, не gate. |
| 4. peaq DID | peaq Network | peaq RPC down, registration revert | `PeaqRegistrationWorker` retry 5×; якщо все ще fail — `tree.peaq_did` залишається `nil`, `IotexVerificationWorker` пропускає telemetry log з `oracle_status_pending`. **Buffer:** до 7 днів дозволено мінтити з `did:local:fallback:0x{sha256(uid)[:40]}` (DAO-vote required в [`00_07`](00_07_GitHub_Projects_and_IaC_Automation) #governance). Після 7 днів — alert "peaq_long_outage" P1. | Кроки 5–8 (IoTeX, Chainlink, mint). Solana/Celo не блокуються (вони можуть працювати з DID або з tree_uid напряму). |
| 5. IoTeX W3bstream | IoTeX | API zaspamlena, ZK-proof generation failed | `IotexVerificationWorker` retry 5×; стан `verified_by_iotex` залишається `false` → `MintCarbonCoinWorker` пропускає згідно guard clause. **Buffer:** telemetry зберігається в `TelemetryLog`, перезапускається кроком `IotexBackfillWorker` (cron `0 */2 * * *`) — пробує всі `verified_by_iotex: false AND created_at > 7d ago` повторно. | Крок 6 (Chainlink). |
| 6. Chainlink Functions | Chainlink DON | LINK token balance низький, gas spike, router contract version mismatch | `Web3::ChainlinkRouterVersion` runtime-probe + graceful fallback (`Chainlink::OracleDispatchService` [S6.15] вже реалізований); `WEB3_STRICT_MODE=false` локально → stub mode для тестів. Якщо LINK low — `Treasury::MonitorService` шле P1 alert "topup_LINK_oracle". | Кроки 8 (Polygon mint). Solana/Celo не блокуються — вони не йдуть через Chainlink. |
| 7. Solana micro-rewards | Solana | RPC eviction, ATA missing, low SOL у gas wallet | Multi-RPC fallback (з `.env.example`: `SOLANA_RPC_URL` + `SOLANA_RPC_URL_FALLBACK_1..3`). Якщо все fail → `SolanaMicroRewardWorker` move до `manual_review`; Celo продовжує самостійно. | Нічого (Solana — самодостатня rail). |
| 7. Celo ReFi | Celo | Forno RPC down, низький cUSD balance | Multi-RPC fallback (`docs/04_02` §13b Drift Register, E.49 implementation `RPC_FALLBACK_ENV_KEYS`). Якщо forno + community RPCs all down → `CeloRewardWorker` запит резервується у `celo_pending_payouts` (Kredis list), drain коли RPC живий. | Нічого (Celo — самодостатня rail). |
| 8. Polygon + Hadron | Polygon EVM + Hadron compliance | Polygon RPC saturated, Hadron KYC service down | Polygon multi-RPC (Alchemy + Infura + own node); Hadron — якщо `hadron_kyc_status` cached `approved` для wallet → continue (cache TTL 24 год). Якщо cache miss + Hadron down → `MintCarbonCoinWorker.retry` (5×), потім `manual_review`. | Крок 9 (The Graph) — оскільки graph індексує Polygon events. |
| 9. The Graph | The Graph hosted service | Subgraph health degraded, indexing lag >1 година | Read-side тільки. Якщо subgraph lag → dashboard показує `last_indexed_block` warning, але mint flow не блокується. Альтернативи: own subgraph node (Akash deployment, P2) або direct Polygon RPC `eth_getLogs` (`TheGraph::QueryService` уже має fallback path). | Нічого (read-side). |
| 10. KlimaDAO | Polygon (KlimaDAO contracts) | Contract paused, approve revert | `KlimaRetirementWorker` retry 3× → `manual_review`. Параметризується через `ProtocolParameters.klima_retirement_enabled` (DAO-toggle). | Нічого (retirement — окрема rail, не блокує emission). |
| 11. Filecoin/IPFS | Pinata / Web3.Storage | API limit, CID not pinned | `FilecoinArchiveWorker` retry 5×; fallback на local `vendor/audit_archive/` (Akash persistent volume). Daily cron `FilecoinReconcileWorker` re-pinings local audit logs до Filecoin коли API живий. | Нічого (audit immutability збережена локально). |
| 12. Ethereum L1 anchor | Ethereum mainnet | Gas spike >300 gwei, RPC down | `EthereumAnchorWorker` (cron `0 3 * * 1`) перевіряє gas price; якщо >`MAX_ANCHOR_GWEI` ENV (default 100) — **відтерміновує** anchor у пул `pending_anchors` (Kredis sorted set за `state_root_hash`). Drain коли gas нормалізується або через manual force-flush. | Нічого (anchor — finality, не runtime). Multi-week gap toleration. |

### 2.3 Worker Configuration (Sidekiq)

Усі Web3-воркери дотримуються конвенцій:

```ruby
class XxxWorker
  include Sidekiq::Worker
  include Web3CircuitBreaker

  sidekiq_options queue: :web3,  # або :web3_critical для mint/anchor
                  retry: 5,
                  backtrace: true,
                  lock: :until_executed,  # via sidekiq-unique-jobs
                  lock_timeout: 30,
                  lock_ttl: 3600

  sidekiq_retry_in do |count, exception|
    base = 10
    base * (2 ** count) + rand(base)  # exponential + jitter
  end

  def perform(...)
    return circuit_open_skip if circuit_breaker_open?
    # ... web3 call
  rescue *transient_errors => e
    record_failure!(e)
    raise
  end
end
```

### 2.4 Resilience SLO

| Метрика | Target | Як вимірюється |
|---------|--------|----------------|
| Telemetry intake survival при Queen offline | ≥ 95% за 24 год | Queen self-telemetry CIFO fill + Helium fallback hit rate |
| Mint flow availability при single Web3-chain outage | ≥ 80% (degraded but functional) | Prometheus `silkennet_mint_success_total / silkennet_mint_attempt_total` over 1h windows |
| Recovery to full pipeline after multi-chain outage | < 4 год once external chains restore | Backfill workers drain rate (`IotexBackfillWorker`, `FilecoinReconcileWorker`) |
| No data loss when all external chains down for ≤ 24 год | 100% — все буферизується | `TelemetryLog.count`, `BlockchainTransaction.where(state: :pending).count` зростання без втрат |

---

## 3. 🧰 Реалізаційні Якорі (Implementation Anchors)

| Концепція | Файл / Сервіс | Статус |
|-----------|---------------|--------|
| Web3 circuit breaker | `app/workers/concerns/web3_circuit_breaker.rb` (`04_02 §Web3CircuitBreaker`) | ✅ Реалізовано (320L+ spec) |
| Multi-RPC fallback (Polygon, Solana, Celo) | `RPC_FALLBACK_ENV_KEYS` constants | ✅ Реалізовано (E.49 in `00_08`) |
| Queen self-telemetry (`DID == 0x00000000`) | `GatewayTelemetryWorker` + `Gateway.mark_seen!` | ✅ Реалізовано |
| CoAP retry constants on Queen | `firmware/queen/main.c` + 4 host tests (FW.9) | ✅ Реалізовано |
| Chainlink router version probe | `Web3::ChainlinkRouterVersion` [S6.15] | ✅ Реалізовано (17 examples spec) |
| Manual review terminal state | `BlockchainTransaction` AASM | ✅ Реалізовано |
| Queen-to-Queen Backhaul Mesh | Concept у [`02_05 §Q2Q`](02_05_Queen_Hardware_and_Starlink) | 🟡 Concept, planned Phase 2 |
| Helium fallback emit (Queen-side LoRaWAN) | Queen firmware `queen_helium_lorawan_uplink()` | 🟡 ARCH.34 planned (Soldier-side `helium_compat_emit` відкинуто — Soldier не несе LoRaWAN MAC stack) |
| Ingress Proxy (CoAP buffer) | INF.4 / INF.6 | 🟡 Planned (P1) |
| Conductor L2 cluster heads (formerly "Sergeant") | [`00_02 §Fractal Stack`](00_02_System_Architecture_and_12_Chain_Pipeline) | 🟡 Concept (HW.27, TRL 1) |

---

## 4. 🔗 Cross-ref

- `docs/00_08 INF.4 / INF.6 / ARCH.26 / HW.27 / ARCH.34 / ARCH.35` — open tasks для повної реалізації цієї політики (Helium Queen-side LoRaWAN та Flash Ring Buffer overflow tier).
- `docs/04_02 §13b Drift Register` — як приземлити цю SSOT policy у код (E.49 Celo cascade, S6.15 Chainlink router probe).
- `docs/05_02 §Dynamic Tax` — як cap `insurance_pool` підтримує fallback economics (slashing/insurance політика — [`00_01 §6`](00_01_Vision_Market_and_Slashing_Policy)).
- `docs/06_02 §Akash Deploy` — multi-provider SDL та fallback на GCP/Kamal.
- `docs/06_03 §Prometheus` — метрики, які живлять Resilience SLO.
