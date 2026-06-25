# 06_08: Resilience and Failover Policy

## 🎯 Мета

Зафіксувати єдину політику резервування та відмовостійкості для двох найкритичніших ризик-векторів SilkenNet:

1. **Queen Gateway як Single Point of Failure** — фізичний шлюз між LoRa-мережею Солдатів і Akash/Rails.
2. **12-ланковий Web3-конвеєр як Lego Tower of Doom** — будь-яка зовнішня мережа (IoTeX, Streamr, Chainlink, Hadron, KlimaDAO, ...) може mute/cap/break.

Документ описує `Fallback / Retry / Buffer policy` для кожної ланки та механізм продовжувати Proof-of-Growth ([`05_02`](05_02_Proof_of_Growth_Pipeline)) навіть при тимчасовій відсутності окремих мостів.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — політика затверджена, **7 з 11 Implementation Anchors ✅ Реалізовано** (Web3CircuitBreaker, Multi-RPC fallback, Queen self-telemetry, CoAP retry, Chainlink router probe, Manual review terminal state, Money-path crash-window idempotency [ARCH.45] — див. §3). Залишаються 🟡 (→ [`00_07`](00_07_Action_Plan_Tracker)): Queen-to-Queen Backhaul Mesh + Flash overflow tier (ARCH.35), Helium Queen-side LoRaWAN (ARCH.34), TDMA/CAD sync (ARCH.26), Ingress Proxy (INF.4/INF.6), Conductor L2 (ARCH.1, formerly "Sergeant"). Production-rollout — Phase 2 ([`00_03`](00_03_TRL_Matrix_HIL_and_Beyond)).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_00` — SSOT Index](00_00_SSOT_Index) | Системна карта (8 рівнів) + 12-chain → 05_02 |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Hardware Queen + Q2Q mesh + Helium fallback |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Прошивка Queen (CoAP retry, CIFO) |
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Мультичейн архітектура |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof-of-Growth pipeline; §Dynamic Tax — `insurance_pool` fallback economics |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `Web3CircuitBreaker` concern; multi-RPC fallback (E.49 — `RPC_FALLBACK_ENV_KEYS`) + Chainlink router probe (S6.15 — `Web3::ChainlinkRouterVersion`) |
| [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) | Multi-provider SDL, fallback GCP/Kamal |
| [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) | Метрики Resilience SLO |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): ARCH.26 TDMA/CAD, ARCH.34 Helium, ARCH.35 Flash, INF.4/INF.6 Ingress, ARCH.1 Conductor L2 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. ☂️ Queen Gateway Failover Protocol](#1--queen-gateway-failover-protocol)
- [2. 🪜 Web3 Chain Fallback Matrix (Anti-Lego Tower)](#2--web3-chain-fallback-matrix-anti-lego-tower)
- [3. 🧰 Реалізаційні Якорі (Implementation Anchors)](#3--реалізаційні-якорі-implementation-anchors)
<!-- TOC:AUTO:END -->

---

## 1. ☂️ Queen Gateway Failover Protocol

### 1.1 Чому це SPOF

У поточній архітектурі Queen — **єдиний always-on listener** і єдина точка виходу через Starlink/LTE для свого LoRa-кластера. Якщо Queen втрачає живлення, фізично знищена, втратила Starlink-зв'язок або переходить у `state: faulty` AASM — весь кластер (50–200 Soldier'ів) залишається без uplink.

### 1.2 Чотири рівні резервування

| Рівень | Механізм | Trigger | Latency | Реалізація |
|--------|----------|---------|---------|------------|
| **L1: Queen Local Buffer (Two-Tier)** | **Hot tier:** CIFO EdgeCache до 50 slots in-RAM (дедуплікація за DID + priority-aware eviction), flush на 1 год TTL або при ≥ 45 entries. **Overflow tier:** при `AT+CCOAPSEND` fail після N retry — drain CIFO у SPI NOR Flash Ring Buffer (W25Q32, 4 МБ; **sector-based** ring — 1024×4 KB сектори, 192 слоти×21 байт/сектор ≈ 197k слотів; NOR вимагає erase цілим сектором, тому ring обертається по секторах, не байтах — [`02_05 §2.1`](02_05_Queen_Hardware_and_Starlink); ARCH.35). Якщо Starlink/LTE недоступні — повторити flush експоненційно (1, 2, 4, 8, 16 хв cap = 60 хв). При відновленні uplink — спочатку drain Flash Ring Buffer (FIFO, через CIFO-refill), потім CIFO. | `AT+CCOAPSEND` timeout або UART fail | Seconds (RAM tier) / Hours-days (Flash tier) | `firmware/queen/main.c` CoAP retry loop (FW.9, `COAP_MAX_RETRIES`), host-tested: per-attempt conversation-fail (`test_at_engine.c`) + fail→retry→no-loss (`test_fw51_*`); Flash Ring Buffer — **драйвер ✅ host-tested** (`firmware/common/flash_ring.{h,c}`, NOR-мок + power-cut, at-least-once; Queen-глю gated `ARCH35_RING_ENABLED 0`); residual = W25Q32 розводка + bench (ARCH.35) |
| **L2: Queen-to-Queen LoRa Backhaul** | Сусідня Queen у радіусі 5–15 км (SF12 спред-фактор, **~0.25 кбіт/с / 250 bps на BW125** — не 6 кбіт/с; backhaul кластера ≈ десятки секунд, прийнятно для не-realtime) приймає `delegate_uplink_frame` від основної Queen. Якщо власний Starlink також впав — пересилає далі по LoRa-магістралі до Queen з активним uplink. | Local Starlink/LTE down >5 хв OR `coap_health = false` | Minutes | `Queen → Queen` через `RELAY_QUEEN` фрейм (DEFAULT_TTL=4); планується [`02_05`](02_05_Queen_Hardware_and_Starlink) (Q2Q Mesh) |
| **L3: Helium SOS-маяк Королеви (Queen-side)** | Queen формує валідний **LoRaWAN** frame (DevEUI/AppEUI/AppKey, FCntUp, OTAA). **Лише SOS, НЕ телеметрія кластера** (див. ⚠️ нижче): один малий пакет (~12 байт: `queen_did`, `vcap`, error-code) → Helium hotspot (~15 км, SF12) → Helium LNS → HTTP Integration → Rails `POST /api/v1/telemetry/helium` (HMAC). Бекенд створює `EwsAlert(queen_uplink_lost)` → ескалація L4 (виїзд лісника). Телеметрія Солдатів тим часом буферизується у SPI Flash Королеви (ARCH.35). **NB:** Soldier лишається на raw LoRa P2P (**AES-128**, 21-байт payload, post-ARCH.42); LoRaWAN stack живе ТІЛЬКИ на Queen. | Власний Starlink/LTE-M down + Q2Q backhaul недоступний | Tens of seconds | Queen firmware `queen_helium_lorawan_uplink()` (ARCH.34, planned); деталі — [`02_05 §6.1 Helium Fallback`](02_05_Queen_Hardware_and_Starlink) |
| **L4: Field Operator Pull (Forester app)** | Лісник з мобільним пристроєм підходить до фізичної Queen, підключається через BLE (Forester app) і вручну дренує CIFO буфер на 4G/Wi-Fi. | Manual escalation коли L1-L3 fail >24 год | Hours-Days | Forester mobile app (UI заплановано Phase 2) |

> **⚠️ Фізика Helium: L3 — це SOS-маяк, а НЕ телеметрійний backhaul.** Queen агрегує 50–200 Солдатів; навіть 50 × 21 байт = ~1050 байт. Максимальний application-payload LoRaWAN на **SF12** (потрібен для добивання до Helium-вишок на ~15 км) у EU868 — лише **~51 байт**. Пропхнути телеметрію кластера через Helium означало б фрагментацію на десятки uplink'ів, що (а) спалює батарею Королеви і (б) порушує Helium Fair Use / EU868 1% duty-cycle. Тому Helium несе **лише один SOS-кадр самої Королеви** («я втратила uplink»), а телеметрія Солдатів чекає у Flash Ring Buffer (L1 overflow tier, ARCH.35) до відновлення Starlink/Q2Q або приходу лісника (L4).

### 1.3 Queen Health Heartbeat → Rails

Сама Queen відправляє себе як `DID == 0x00000000` (Queen Sentinel, [`03_02 §7`](03_02_Queen_Gateway_Firmware)) з полями: `vcap_mv`, `uptime_s`, `cifo_fill`, `coap_retries_24h`, `last_starlink_rssi`. Backend записує у `GatewayTelemetryLog` і обчислює:

- `online?` = `last_seen_at >= (sleep_interval * 1.2).seconds.ago` (поточна модель `Gateway`, [`04_01`](04_01_Data_Models_and_Entities))
- Якщо `online?` стає `false` довше 10 хв → `Gateway.state` AASM `mark_faulty!` + dispatch `EwsAlert(type: queen_offline)` → Forester Guild notify (SMS/email).

### 1.4 Dynamic Mesh Rerouting (Soldier-side)

Soldier'и **не знають**, що "їх" Queen впала. Вони продовжують TX. Але mesh-relay алгоритм (DEFAULT_TTL=3) природно прокидує пакет до сусідньої Queen, якщо вона у радіусі. Конкретно:

- Soldier емітує свій стандартний payload (DID + сенсори + TTL) — жодного `last_rssi_to_queen` Soldier **НЕ** передає (firmware: байт 4 = Vcap, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); RSSI вимірює Queen при RX і додає його у Queen→backend 21-байт-фрейм ([`03_01 §8`](03_01_Firmware_Lifecycle_and_DMA)).
- Сусідній Soldier (Phase 4.5 RX window) ловить, помічає чужий пакет — якщо TTL > 0, релєює.
- Через 1–3 хопи пакет дотягується до сусідньої Queen у іншому кластері.
- Queen "B" — **"тупа труба" (dumb pipe):** вона НЕ читає і НЕ може прочитати, чий це пакет. Будь-яка Queen, що зловила валідний LoRa-фрейм Silken Net (за magic-байтом), просто загортає сирий зашифрований payload у CoAP і шле на бекенд. Бекенд розшифровує AES-блок, читає `DID` і визначає: «Soldier з кластера A передав через Queen B». Атрибуцію «через яку Queen» дає `queen_uid`, який Queen B ставить на **власну CoAP-обгортку** (вона знає свій UID), а НЕ читає з payload Солдата.

> **🔐 Корекція E2EE:** Попередня редакція стверджувала, що «Queen B читає чужий `queen_uid` у payload-метадаті». Це архітектурно неможливо: 21-байтовий пакет має у відкритому вигляді лише `DID` (4 байти) + `RSSI` (1), а 16-байтовий блок зашифрований **per-device AES-128** ключем ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)). Поля `queen_uid` у payload Солдата немає взагалі, і Queen B не має ключа Солдата з чужого кластера, щоб щось дешифрувати. Розшифрування — виключно на бекенді (Zero-Trust: Queen не є точкою plaintext).

> **Передумова:** Для надійності цього шляху необхідні TDMA Sync Windows (ARCH.26) + CAD (SX1262) — інакше mesh relay стохастичний. Це не блокує політику в принципі, але обмежує її TRL до 4-5 поки FW.20 / ARCH.26 не закриті. **Друга передумова (addressing):** opaque multi-hop relay + per-device demux потребують cleartext DID/address-шару на LoRa-фреймі (зараз DID лежить **усередині** per-device-шифроблоку — Soldier шле рівно 16 B) АБО shared mesh-key (заборонено per-device-ізоляцією [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)) — відкрите архітектурне питання [`00_07` — ARCH.43](00_07_Action_Plan_Tracker).

> **🔬 Open Research (академічна валідація надійності mesh):** формальна модель надійності flood-relay — **ланцюги Маркова** для TTL-маршрутизації + **теорія перколяції** (критичний поріг `q_c` фазового переходу, за яким мережа розпадається на ізольовані від Queen кластери) — математично обґрунтовує `PANIC_TTL=5`/`DEFAULT_TTL=3` і постачає `q_c` як науковий параметр тригера параметричного страхування ([`05_05`](05_05_Slashing_and_Risk_Policy) / [`07_01`](07_01_Nature_as_a_Service_Contracts)). Deliverable ЧНУ-ФОТІУС (Порубльов/Онищенко) — профіль у [`08_02 §1B`](08_02_Academic_Institutions_Registry); спільна Q1-публікація → [`08_01`](08_01_Joint_Publications_and_IP_Strategy).

---

## 2. 🪜 Web3 Chain Fallback Matrix (Anti-Lego Tower)

### 2.1 Загальна абстракція: Local Buffer + Circuit Breaker

Жодна Web3-операція (peaq registration, IoTeX verification, Chainlink dispatch, Hadron compliance, KlimaDAO retire, Filecoin pin, L1 anchor) не повинна виконуватись **синхронно** в hot path Rails. Вже сьогодні всі вони — Sidekiq workers з `retry: 5` та `Web3CircuitBreaker` concern ([`04_02`](04_02_Business_Logic_and_Services)).

Політика resilience:

1. **Buffer-first.** Запис у `TelemetryLog` / `BlockchainTransaction` / `AuditLog` відбувається **до** першої спроби Web3-виклику. Стан AASM `pending` / `processing` / `sent` / `confirmed` / `failed` / `manual_review` (див. `BlockchainTransaction` partitioning + `find_with_partition_pruning`).
2. **Circuit Breaker.** При 5+ підряд транзакторних помилках відповідного RPC — circuit `opens` на 60 секунд (lock-free counter у Kredis). Worker не пробує знову — повертає `Sidekiq::Retry` до cooldown.
3. **Exponential backoff retry.** За межами circuit breaker — стандартний Sidekiq retry з jitter.
4. **Manual review terminal state.** Якщо `tx_hash` отримано, але стан невизначений (double-spend guard) — переходить у `manual_review` AASM, кошти заблоковані до ручної перевірки.
5. **Graceful degradation.** Pipeline продовжує працювати на кроках, які НЕ залежать від downed ланки. Залежні кроки чекають у `pending`.

### 2.2 Per-Chain Fallback Policy

| Крок | Залежна ланка | Тип ризику | Fallback | Що блокує далі |
|------|---------------|------------|----------|----------------|
| 2. Akash hosting | Akash | Provider eviction, oracle price spike, no bidders | Multi-provider deployment (`deploy.yaml` SDL з multiple providers); fallback на GCP via Kamal ([`06_01`](06_01_Deployment_Kamal_Terraform)) — `kamal redeploy --hosts canopy` **+ перемкнути upstream Ingress Anchor** (HAProxy/socat Akash→GCP, [`06_02`](06_02_Akash_Network_Integration) розділ «Ingress Anchor»). **Queens НЕ потрапляють у «чорну діру»:** CoAP йде на *статичний IP Ingress Anchor* (e2-micro), а не на Akash прямо → endpoint Королев незмінний, перемикається лише backend за Anchor'ом (інакше — OTA `CMD_SET_BACKEND` як крайній засіб, [`06_02`](06_02_Akash_Network_Integration)). | Цілий backend (всі 12 наступних кроків) — тому Akash redundancy P0. |
| 3. Streamr P2P | Streamr Network | Streamr API rate-limit / outage | Non-blocking publish (`StreamrBroadcastWorker`, `queue: low`, retry: 3). При остаточному фейлі — payload потрапляє в `streamr_undelivered` Kredis list (TTL 24 год). Власний P2P через ActionCable websockets залишається активним. | Нічого. Streamr — спостерігач, не gate. |
| 4. peaq DID | peaq Network | peaq RPC down, registration revert | `PeaqRegistrationWorker` retry 5×; якщо все ще fail — `tree.peaq_did` залишається `nil`, telemetry **буферизується** у `TelemetryLog` (`oracle_status_pending`), мінтинг НЕ відбувається. Коли peaq оживає — `PeaqRegistrationWorker` дореєстровує DID, далі `IotexBackfillWorker` дозаганяє верифікацію → мінт. Після 7 днів простою — alert "peaq_long_outage" P1. **`did:local:fallback` ВИДАЛЕНО** (див. ⚠️ нижче). | Кроки 5–8 (IoTeX, Chainlink, mint). Solana/Celo не блокуються (вони можуть працювати з DID або з tree_uid напряму). |
| 5. IoTeX W3bstream | IoTeX | API zaspamlena, ZK-proof generation failed | `IotexVerificationWorker` retry 5×; стан `verified_by_iotex` залишається `false` → `MintCarbonCoinWorker` пропускає згідно guard clause. **Buffer:** telemetry зберігається в `TelemetryLog`, перезапускається кроком `IotexBackfillWorker` (cron `0 */2 * * *`) — пробує всі `verified_by_iotex: false AND created_at > 7d ago` повторно. | Крок 6 (Chainlink). |
| 6. Chainlink Functions | Chainlink DON | LINK token balance низький, gas spike, router contract version mismatch | `Web3::ChainlinkRouterVersion` runtime-probe + graceful fallback (`Chainlink::OracleDispatchService` [S6.15] вже реалізований); `WEB3_STRICT_MODE=false` локально → stub mode для тестів. Якщо LINK low — `Treasury::MonitorService` шле P1 alert "topup_LINK_oracle". | Кроки 8 (Polygon mint). Solana/Celo не блокуються — вони не йдуть через Chainlink. |
| 7. Solana micro-rewards | Solana | RPC eviction, ATA missing, low SOL у gas wallet | Multi-RPC fallback (з `.env.example`: `SOLANA_RPC_URL` + `SOLANA_RPC_URL_FALLBACK_1..3`). Якщо все fail → `SolanaMicroRewardWorker` move до `manual_review`; Celo продовжує самостійно. | Нічого (Solana — самодостатня rail). |
| 7. Celo ReFi | Celo | Forno RPC down, низький cUSD balance | Multi-RPC fallback (E.49 implementation `RPC_FALLBACK_ENV_KEYS`, [`04_02`](04_02_Business_Logic_and_Services)). Якщо forno + community RPCs all down → `CeloRewardWorker` запит резервується у `celo_pending_payouts` (Kredis list), drain коли RPC живий. | Нічого (Celo — самодостатня rail). |
| 8. Polygon + Hadron | Polygon EVM + Hadron compliance | Polygon RPC saturated, Hadron KYC service down | Polygon multi-RPC (Alchemy + Infura + own node); Hadron — якщо `hadron_kyc_status` cached `approved` для wallet → continue (cache TTL 24 год). Якщо cache miss + Hadron down → `MintCarbonCoinWorker.retry` (5×), потім `manual_review`. | Крок 9 (The Graph) — оскільки graph індексує Polygon events. |
| 9. The Graph | The Graph hosted service | Subgraph health degraded, indexing lag >1 година | Read-side тільки. Якщо subgraph lag → dashboard показує `last_indexed_block` warning, але mint flow не блокується. Альтернативи: own subgraph node (Akash deployment, P2) або direct Polygon RPC `eth_getLogs` (`TheGraph::QueryService` уже має fallback path). | Нічого (read-side). |
| 10. KlimaDAO | Polygon (KlimaDAO contracts) | Contract paused, approve revert | `KlimaRetirementWorker` retry 3× → `manual_review`. Параметризується через `ProtocolParameters.klima_retirement_enabled` (DAO-toggle). | Нічого (retirement — окрема rail, не блокує emission). |
| 11. Filecoin/IPFS | Pinata / Web3.Storage | API limit, CID not pinned | `FilecoinArchiveWorker` retry 5×. **Джерело правди — НЕ локальний диск:** `AuditLog`-рядки з `chain_hash` уже персистяться у **PostgreSQL (managed Cloud SQL, поза Akash-подом)**, тож при недоступності Pinata нічого не втрачається. `FilecoinReconcileWorker` (daily cron) **відновлює archive-payload з БД** і re-pin'ить, коли API живий. Якщо потрібен проміжний blob-буфер — **S3-сумісне сховище (Cloudflare R2 / Filecoin Station)**, НЕ container-local диск. | Нічого (audit immutability — у durable Postgres, не на ефемерному диску). |
| 12. Ethereum L1 anchor | Ethereum mainnet | Gas spike >300 gwei, RPC down | `EthereumAnchorWorker` (cron `0 3 * * 1`) перевіряє gas price; якщо >`MAX_ANCHOR_GWEI` ENV (default 100) — **відтерміновує** anchor у пул `pending_anchors` (Kredis sorted set за `state_root_hash`). Drain коли gas нормалізується або через manual force-flush. | Нічого (anchor — finality, не runtime). Multi-week gap toleration. |

> **⚠️ Zero-Trust корекція: `did:local:fallback` для мінтингу видалено.** Минтити з локальним фейковим DID безглуздо й небезпечно: крок 5 (IoTeX W3bstream) генерує ZK-доказ, звіряючи підпис (наразі master-backed, не device-bound — true-DePIN ladder [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)) із **зареєстрованим на-чейн peaq DID**. Без реального on-chain DID ZK-провера не знайде публічного ключа → `verified_by_iotex?` = `false` → guard clause мінтингу блокує його **в будь-якому разі**. Тобто local-DID не «розблоковує» мінт, а лише ризикує приписати вуглецеві кредити неперевіреному походженню. Правильно: телеметрія спокійно чекає у `pending`, а коли peaq оживає — DID дореєстровується і IoTeX дозаганяється. Краще зачекати на легітимний консенсус, ніж пропхати дані «костилем».

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
    # ⚠️ НЕ busy-bounce: переплановуємо на кінець cooldown, job ЛИШАЄ active set
    if circuit_breaker_open?
      return self.class.perform_in(circuit_cooldown_remaining + rand(5), *args)
    end
    # ... web3 call
  rescue *transient_errors => e
    record_failure!(e)
    raise
  end
end
```

> **⚠️ Thundering Herd корекція: не «бовтати» чергу при відкритому circuit.** Якщо при `circuit_breaker_open?` воркер робив `return circuit_open_skip` і одразу падав назад у retry, то при високому ingest сотні воркерів безперервно тягнуть job → перевіряють IF → бавнсять, створюючи CPU/Redis-навантаження на холосте «пережовування» черги (self-DDoS). **Фікс:** при відкритому circuit job **переплановується на `circuit_cooldown_remaining`** (`perform_in`), тобто ЛИШАЄ active set і повертається один раз — приблизно тоді, коли circuit, ймовірно, закриється. Probe-воркер (`Web3::ChainlinkRouterVersion` / легкий RPC-ping) робить один тестовий запит наприкінці cooldown і скидає лічильник при успіху.
>
> **Чому НЕ `Sidekiq::Queue.new(:web3).pause`:** circuit breaker — **per-RPC** (Polygon / Solana / peaq…), а черги `web3`/`web3_critical` спільні для багатьох чейнів. Пауза всієї черги зупинила б і **здорові** чейни. Reschedule-on-open зберігає per-chain гранулярність без busy-spin. Чисту queue-pause можна застосувати лише якщо кожен чейн отримає окрему чергу (рефактор, Phase 2).

### 2.4 Resilience SLO

| Метрика | Target | Як вимірюється |
|---------|--------|----------------|
| Telemetry intake survival при Queen offline | ≥ 95% за 24 год | Queen self-telemetry CIFO fill + Helium fallback hit rate |
| Mint flow availability при single Web3-chain outage | ≥ 80% (degraded but functional) | Prometheus `silkennet_mint_success_total / silkennet_mint_attempts_total` over 1h windows |
| Recovery to full pipeline after multi-chain outage | < 4 год once external chains restore | Backfill workers drain rate (`IotexBackfillWorker`, `FilecoinReconcileWorker`) |
| No data loss when all external chains down for ≤ 24 год | 100% — все буферизується | `TelemetryLog.count`, `BlockchainTransaction.where(state: :pending).count` зростання без втрат |

---

## 3. 🧰 Реалізаційні Якорі (Implementation Anchors)

| Концепція | Файл / Сервіс | Статус |
|-----------|---------------|--------|
| Web3 circuit breaker | `app/workers/concerns/web3_circuit_breaker.rb` ([`04_02`](04_02_Business_Logic_and_Services)) | ✅ Реалізовано |
| Multi-RPC fallback (Polygon, Solana, Celo) | `RPC_FALLBACK_ENV_KEYS` constants | ✅ Реалізовано (E.49 in [`00_07`](00_07_Action_Plan_Tracker)) |
| Queen self-telemetry (`DID == 0x00000000`) | `GatewayTelemetryWorker` + `Gateway.mark_seen!` | ✅ Реалізовано |
| CoAP retry loop on Queen (`COAP_MAX_RETRIES`) | `firmware/queen/main.c`; host-tests `test_at_engine.c` (conversation-fail) + `test_fw51_*` (fail→retry→no-loss), FW.9 | ✅ Реалізовано |
| Chainlink router version probe | `Web3::ChainlinkRouterVersion` [S6.15] | ✅ Реалізовано |
| Manual review terminal state | `BlockchainTransaction` AASM | ✅ Реалізовано |
| Money-path crash-window idempotency (intent-marker + `in_flight` guard) | `BlockchainBurningService` / `Solana::BatchPayoutService` ([ARCH.45], [`04_02 §4/§10`](04_02_Business_Logic_and_Services)) | ✅ Реалізовано |
| Queen-to-Queen Backhaul Mesh | Concept у [`02_05`](02_05_Queen_Hardware_and_Starlink) | 🟡 Concept, planned Phase 2 |
| Helium fallback emit (Queen-side LoRaWAN) | Queen firmware `queen_helium_lorawan_uplink()` | 🟡 ARCH.34 planned (Soldier-side `helium_compat_emit` відкинуто — Soldier не несе LoRaWAN MAC stack) |
| Ingress Proxy (CoAP buffer) | INF.4 / INF.6 | 🟡 Planned (P1) |
| Conductor L2 cluster heads (formerly "Sergeant") | [`00_08 §2.1`](00_08_Beyond_TRL9_Planetary_Roadmap) | 🟡 Concept (HW.27, TRL 1) |

---

