# 06_08: Resilience and Failover Policy

## 🎯 Мета

Зафіксувати єдину політику резервування та відмовостійкості для двох найкритичніших ризик-векторів SilkenNet:

1. **Queen Gateway як Single Point of Failure** — фізичний шлюз між LoRa-мережею Солдатів і Akash/Rails.
2. **12-ланковий Web3-конвеєр як Lego Tower of Doom** — будь-яка зовнішня мережа (IoTeX, Streamr, Chainlink, Hadron, KlimaDAO, ...) може mute/cap/break.

Документ описує `Fallback / Retry / Buffer policy` для кожної ланки та механізм продовжувати Proof-of-Growth ([`05_02`](05_02_Proof_of_Growth_Pipeline)) навіть при тимчасовій відсутності окремих мостів.

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — політика затверджена; реалізовані якорі — §3 (circuit breaker, CoAP retry, QATT-v2 пульс + dead-man switch, manual_review, money-path idempotency [ARCH.45], Celo multi-RPC). **⚠️ Чесність-пас 2026-07-04:** попередня редакція ✅-ила механізми, яких у коді НЕМАЄ (backfill/buffer-list/gas-defer-пули, `Web3::ChainlinkRouterVersion` — видалений ARCH.53-демоутом) — вони перепозначені **🟡 target** інлайн у §2.2/§2.3 і зібрані в [`00_07` INF.22](00_07_Action_Plan_Tracker). Залишаються 🟡 (→ [`00_07`](00_07_Action_Plan_Tracker)): Q2Q Backhaul Mesh + Flash overflow tier (ARCH.35), Helium Queen-side LoRaWAN (ARCH.34-firmware), TDMA/CAD sync (ARCH.26), Conductor L2 (ARCH.1). Production-rollout — Phase 2 ([`00_03`](00_03_TRL_Matrix_HIL_and_Beyond)).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_00` — SSOT Index](00_00_SSOT_Index) | Системна карта (8 рівнів) + 12-chain → 05_02 |
| [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) | Hardware Queen + Q2Q mesh + Helium fallback |
| [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) | Прошивка Queen (CoAP retry, CIFO) |
| [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) | Мультичейн архітектура |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof-of-Growth pipeline; §Dynamic Tax — `insurance_pool` fallback economics |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | `Web3CircuitBreaker` concern; Celo multi-RPC fallback (E.49 — `RPC_FALLBACK_ENV_KEYS`) |
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
| **L3: Helium SOS-маяк Королеви (Queen-side)** | Queen формує валідний **LoRaWAN** frame (DevEUI/AppEUI/AppKey, FCntUp, OTAA). **Лише SOS, НЕ телеметрія кластера** (див. ⚠️ нижче): один малий пакет (📐 **wire-freeze 12 Б, One-Home:** `[queen_did:4 BE][vcap_mv:2 BE][error_code:1][uptime_min:u24 BE][flags:1][rsv:1]`; error-codes 1=starlink_down 2=lte_down 3=q2q_unreachable 4=buffer_pressure — дзеркало `HeliumSosWorker::ERROR_CODES`) → Helium hotspot (~15 км, SF12) → Helium LNS → HTTP Integration → Rails `POST /api/v1/telemetry/helium` (HMAC `X-Helium-Signature`, патерн oracle_callbacks). **Backend-half ✅ (2026-07-03, ARCH.34):** `HeliumSosController` → `HeliumSosWorker` (черга alerts; dev_eui↔`gateways.helium_dev_eui` + cross-check `queen_did` проти hex-uid) → `EwsAlert(queen_uplink_lost)` + `report_fault!` → ескалація L4 (виїзд лісника). Телеметрія Солдатів тим часом буферизується у SPI Flash Королеви (ARCH.35). **NB:** Soldier лишається на raw LoRa P2P (**AES-128**; wire за ерою: 16B ECB → 30B CCM rev2.1 — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); LoRaWAN stack живе ТІЛЬКИ на Queen. | Власний Starlink/LTE-M down + Q2Q backhaul недоступний | Tens of seconds | Queen firmware `queen_helium_lorawan_uplink()` (ARCH.34, planned); деталі — [`02_05 §6.1 Helium Fallback`](02_05_Queen_Hardware_and_Starlink) |
| **L4: Field Operator Pull (Forester app)** | Лісник з мобільним пристроєм підходить до фізичної Queen, підключається через BLE (Forester app) і вручну дренує CIFO буфер на 4G/Wi-Fi. | Manual escalation коли L1-L3 fail >24 год | Hours-Days | Forester mobile app (UI заплановано Phase 2) |

> **⚠️ Фізика Helium: L3 — це SOS-маяк, а НЕ телеметрійний backhaul.** Queen агрегує 50–200 Солдатів; навіть 50 × 21 байт = ~1050 байт. Максимальний application-payload LoRaWAN на **SF12** (потрібен для добивання до Helium-вишок на ~15 км) у EU868 — лише **~51 байт**. Пропхнути телеметрію кластера через Helium означало б фрагментацію на десятки uplink'ів, що (а) спалює батарею Королеви і (б) порушує Helium Fair Use / EU868 1% duty-cycle. Тому Helium несе **лише один SOS-кадр самої Королеви** («я втратила uplink»), а телеметрія Солдатів чекає у Flash Ring Buffer (L1 overflow tier, ARCH.35) до відновлення Starlink/Q2Q або приходу лісника (L4).

### 1.3 Queen Health Heartbeat → Rails [ARCH.54 ✅ 2026-07-03]

Пульс Королеви — **health-блок у ПІДПИСАНОМУ QATT-v2 конверті** кожного flush (8 Б: `uptime_min/cifo_fill/lora_rx_drops/coap_fail/csq/flags`; wire — [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security), розкладка One-Home `firmware/common/queen_attest.h`). Порожній CIFO → **empty-flush heartbeat** (конверт без записів). Стара DID=0-псевдотелеметрія ВБИТА ([`03_02 §7`](03_02_Queen_Gateway_Firmware) — вона брехала полями і ламала CCM-stride); `vcap_mv`/`starlink_rssi` з попередньої редакції — чесно ВІДСУТНІ (Королева без ADC-тракту; CSQ модема — є). Backend: `UnpackTelemetryWorker#enqueue_envelope_health` → `GatewayTelemetryWorker` → `GatewayTelemetryLog`.

**Dead-man switch (первинний, Шар 0):** `GatewayStalenessSweepWorker` (cron */5 хв, черга alerts):

- `online?` = `last_seen_at >= (sleep_interval * 1.2).seconds.ago` (модель `Gateway`, [`04_01`](04_01_Data_Models_and_Entities))
- offline у робочому стані → AASM `report_fault!` + `EwsAlert(queen_offline)` (критичний, анти-спам по кластеру) → Forester Guild notify; повернення в ефір → `recover!` + auto-resolve алерту; attest-lapse спостереження (`last_attested_at` > 24h при online QATT-Королеві → метрика+warn). Grafana: `silkennet_gateways_faulty` P0-правило.

### 1.4 Dynamic Mesh Rerouting (Soldier-side)

Soldier'и **не знають**, що "їх" Queen впала. Вони продовжують TX. Але mesh-relay алгоритм (DEFAULT_TTL=3) природно прокидує пакет до сусідньої Queen, якщо вона у радіусі. Конкретно:

- Soldier емітує свій стандартний payload (DID + сенсори + TTL) — жодного `last_rssi_to_queen` Soldier **НЕ** передає (firmware: байт 4 = Vcap, [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); RSSI вимірює Queen при RX і додає його у Queen→backend 21-байт-фрейм ([`03_01 §8`](03_01_Firmware_Lifecycle_and_DMA)).
- Сусідній Soldier (Phase 4.5 RX window) ловить, помічає чужий пакет — якщо TTL > 0, релєює.
- Через 1–3 хопи пакет дотягується до сусідньої Queen у іншому кластері.
- Queen "B" — **"тупа труба" (dumb pipe):** вона НЕ читає і НЕ може прочитати, чий це пакет. Будь-яка Queen, що зловила валідний LoRa-фрейм Silken Net (за magic-байтом), просто загортає сирий зашифрований payload у CoAP і шле на бекенд. Бекенд розшифровує AES-блок, читає `DID` і визначає: «Soldier з кластера A передав через Queen B». Атрибуцію «через яку Queen» дає `queen_uid`, який Queen B ставить на **власну CoAP-обгортку** (вона знає свій UID), а НЕ читає з payload Солдата.

> **🔐 Корекція E2EE:** Попередня редакція стверджувала, що «Queen B читає чужий `queen_uid` у payload-метадаті». Це архітектурно неможливо: 21-байтовий пакет має у відкритому вигляді лише `DID` (4 байти) + `RSSI` (1), а 16-байтовий блок зашифрований **per-device AES-128** ключем ([`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)). Поля `queen_uid` у payload Солдата немає взагалі, і Queen B не має ключа Солдата з чужого кластера, щоб щось дешифрувати. Розшифрування — виключно на бекенді (Zero-Trust: Queen не є точкою plaintext).

> **Передумова:** Для надійності цього шляху необхідні TDMA Sync Windows (ARCH.26) + CAD (SX1262) — інакше mesh relay стохастичний. Це не блокує політику в принципі, але обмежує її TRL до 4-5 поки FW.20 / ARCH.26 не закриті. **Друга передумова (addressing):** opaque multi-hop relay потребує cleartext TTL/address-шару на LoRa-фреймі. Post-FW.2 (в) demux-половина вже вирішена (CCM AAD несе cleartext DID; двоключова модель [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security): session KEYL ізолює uplink — mesh-key для телеметрії НЕ вводиться, cluster-KEYB покриває лише control-plane), але TTL лишається у ciphertext → relay-декремент неможливий, mesh у CCM-еру мертвий (star-only, ухвала FW.2 (а)) — mesh-вісь [`00_07` — ARCH.43](00_07_Action_Plan_Tracker).

> **🔬 Open Research (академічна валідація надійності mesh):** формальна модель надійності flood-relay — **ланцюги Маркова** для TTL-маршрутизації + **теорія перколяції** (критичний поріг `q_c` фазового переходу, за яким мережа розпадається на ізольовані від Queen кластери) — математично обґрунтовує `PANIC_TTL=5`/`DEFAULT_TTL=3` і постачає `q_c` як науковий параметр тригера параметричного страхування ([`05_05`](05_05_Slashing_and_Risk_Policy) / [`07_01`](07_01_Nature_as_a_Service_Contracts)). Deliverable ЧНУ-ФОТІУС (Порубльов/Онищенко) — профіль у [`08_02 §1B`](08_02_Academic_Institutions_Registry); спільна Q1-публікація → [`08_01`](08_01_Joint_Publications_and_IP_Strategy).

---

## 2. 🪜 Web3 Chain Fallback Matrix (Anti-Lego Tower)

### 2.1 Загальна абстракція: Local Buffer + Circuit Breaker

Жодна Web3-операція (peaq registration, IoTeX verification, Hadron compliance, KlimaDAO retire, Filecoin pin, L1 anchor) не повинна виконуватись **синхронно** в hot path Rails. Всі вони — Sidekiq workers (retry 3–5 за критичністю); `Web3CircuitBreaker` concern включають RPC-обличчя (iotex/chainlink-callback/celo/solana/mint) — воркери без прямого transact-обличчя (peaq/streamr/klima/anchor/filecoin/treasury) свідомо без нього ([`04_02`](04_02_Business_Logic_and_Services)).

Політика resilience:

1. **Buffer-first.** Запис у `TelemetryLog` / `BlockchainTransaction` / `AuditLog` відбувається **до** першої спроби Web3-виклику. Стан AASM `pending` / `processing` / `sent` / `confirmed` / `failed` / `manual_review` (див. `BlockchainTransaction` partitioning + `find_with_partition_pruning`).
2. **Circuit Breaker.** При `FAILURE_THRESHOLD = 5` підряд помилках відповідного RPC — circuit `opens` на `OPEN_TIMEOUT = 300 s` (лічильник у **Rails.cache / Solid Cache** — durable крізь Redis-рестарт; `app/workers/concerns/web3_circuit_breaker.rb`). При відкритому circuit виклик **fail-fast** (`CircuitOpenError` → Sidekiq retry з backoff) — job не б'є мертвий RPC.
3. **Exponential backoff retry.** За межами circuit breaker — стандартний Sidekiq retry з jitter.
4. **Manual review terminal state.** Якщо `tx_hash` отримано, але стан невизначений (double-spend guard) — переходить у `manual_review` AASM, кошти заблоковані до ручної перевірки.
5. **Graceful degradation.** Pipeline продовжує працювати на кроках, які НЕ залежать від downed ланки. Залежні кроки чекають у `pending`.

### 2.2 Per-Chain Fallback Policy

| Крок | Залежна ланка | Тип ризику | Fallback | Що блокує далі |
|------|---------------|------------|----------|----------------|
| 2. Akash hosting | Akash | Provider eviction, oracle price spike, no bidders | Multi-provider deployment (`deploy.yaml` SDL з multiple providers); fallback на GCP via Kamal ([`06_01`](06_01_Deployment_Kamal_Terraform)) — `kamal redeploy --hosts canopy` **+ перемкнути upstream Ingress Anchor** (HAProxy/socat Akash→GCP, [`06_02`](06_02_Akash_Network_Integration) розділ «Ingress Anchor»). **Queens НЕ потрапляють у «чорну діру»:** CoAP йде на *статичний IP Ingress Anchor* (e2-small), де його приймає **демон прямо на анкорі** (PRIMARY — INF.17, 2026-07-04) → Akash-евікшн CoAP-інтейк взагалі НЕ зачіпає; при відмові самого демона fallback = `systemctl stop coap-daemon && systemctl start coap-relay` (socat → Akash `coap`-сервіс, який лишається задеплоєним idle). Endpoint Королев незмінний за будь-якого сценарію. ⚠️ DNS-рівень (зміна A-запису `api.silkennet.com`) як failover-механізм зараз НЕ працює на живій Королеві — firmware пінить CDNSGIP-резолв на весь boot, підхоплення лише post-reboot; fail-triggered re-resolve → [`00_07`](00_07_Action_Plan_Tracker) FW.58. | Цілий backend (всі 12 наступних кроків) — тому Akash redundancy P0. |
| 3. Streamr P2P | Streamr Network | Streamr API rate-limit / outage | Non-blocking publish (`StreamrBroadcastWorker`, `queue: low`, retry: 3). При остаточному фейлі — лог + `silkennet_streamr_broadcast_failures_total` (🟡 target: buffer-list undelivered-payload'ів не реалізовано — [`00_07` INF.22](00_07_Action_Plan_Tracker)). Власний P2P через ActionCable websockets залишається активним. | Нічого. Streamr — спостерігач, не gate. |
| 4. peaq DID | peaq Network | peaq RPC down, registration revert | `PeaqRegistrationWorker` retry 5×; якщо все ще fail — `tree.peaq_did` залишається `nil`, telemetry **буферизується** у `TelemetryLog` (`oracle_status_pending`). Коли peaq оживає — реєстрація йде наступними retry/enqueue. 🟡 target: авто-backfill після довгого простою + alert `peaq_long_outage` — не реалізовані (INF.22). **`did:local:fallback` ВИДАЛЕНО** (див. ⚠️ нижче). | PATH 1-верифікації (IoTeX). Живий PATH 2-мінт НЕ гейтиться IoTeX/peaq (ARCH.53 — guard = KYC), Solana/Celo не блокуються. |
| 5. IoTeX W3bstream | IoTeX | API zaspamlena, ZK-proof generation failed | `IotexVerificationWorker` (web3_critical, retry 5); стан `verified_by_iotex=false` буферизується у `TelemetryLog`. 🟡 target: `IotexBackfillWorker`-cron НЕ реалізований — сам воркер чесно коментує «recovery-крони нема»; recovery = ручний re-enqueue (INF.22). НЕ money-блокер: PATH 2-мінт IoTeX не гейтиться (ARCH.53). | PATH 1 latent-ланцюг. |
| 6. Chainlink (callback-only) | Chainlink DON | — (on-chain dispatch ВИЛУЧЕНО — ARCH.53-демоут) | `Chainlink::OracleDispatchService` = **local correlation-marker без RPC** (dedup-ключ Solana ARCH.51 + idempotency); callback-endpoint (`/api/v1/oracle_callbacks`, HMAC) живий для майбутнього PATH 1 / manual fulfillment. LINK-баланс НЕ моніториться (Treasury дивиться MATIC/SOL/CELO/ETH) — стане релевантним лише при замиканні PATH 1. | Нічого (dispatch більше не в Critical-Path — [`05_01 §8`](05_01_Multichain_Architecture)). |
| 7. Solana micro-rewards | Solana | RPC eviction, ATA missing, low SOL у gas wallet | Один RPC (`SOLANA_RPC_URL`); 🟡 target: fallback-каскад `SOLANA_RPC_URL_FALLBACK_*` НЕ реалізований (INF.22). Durable-захист інший: intent-marker + hourly reconcile (`BatchPayoutService`), `:not_found` on-chain → `manual_review` (ARCH.45/ARCH.51) — RPC-фейл не губить кошти, лише затримує. | Нічого (Solana — самодостатня rail). |
| 7. Celo ReFi | Celo | Forno RPC down, низький cUSD balance | Multi-RPC fallback (E.49 `RPC_FALLBACK_ENV_KEYS` = `CELO_RPC_URL_FALLBACK_1/2`, [`04_02`](04_02_Business_Logic_and_Services)) + dedicated signer ARCH.50. Якщо всі RPC down → Sidekiq-retry; durable-захист = intent-marker + reconcile (🟡 target буфер-list `celo_pending_payouts` не реалізовано — INF.22). | Нічого (Celo — самодостатня rail). |
| 8. Polygon + Hadron | Polygon EVM + Hadron compliance | Polygon RPC saturated, Hadron KYC service down | Polygon: `Web3::ResilientClient` circuit breaker + retry. Hadron: `hadron_kyc_status` — **персистентна колонка** wallet (НЕ кеш із TTL): уже-approved гаманці мінтяться і при лежачому Hadron; нові KYC чекають. `MintCarbonCoinWorker` retry 5× → `MintingRollbackService` → `manual_review` при невизначеному стані. | Крок 9 (The Graph) — оскільки graph індексує Polygon events. |
| 9. The Graph | The Graph hosted service | Subgraph health degraded, indexing lag >1 година | Read-side тільки: `TheGraph::QueryService` при фейлі raise `QueryError` (дашборд деградує). 🟡 target: direct-RPC `eth_getLogs` fallback НЕ реалізований (INF.22); mint flow не блокується. | Нічого (read-side). |
| 10. KlimaDAO | Polygon (KlimaDAO contracts) | Contract paused, approve revert | `KlimaRetirementWorker` (retry 3) існує, але **DEAD — 0 enqueue-сайтів** (узгоджено з [`06_02`](06_02_Akash_Network_Integration): активація = свідоме рішення). 🟡 target при активації: manual_review-хвіст + `ProtocolParameters`-toggle + ARCH.49 nonce-lock. | Нічого (retirement — окрема rail, не блокує emission). |
| 11. Filecoin/IPFS | Pinata / Web3.Storage | API limit, CID not pinned | `FilecoinArchiveWorker` retry 5×. **Джерело правди — НЕ локальний диск:** `AuditLog`-рядки з `chain_hash` уже персистяться у **PostgreSQL (managed Cloud SQL, поза Akash-подом)**, тож при недоступності Pinata нічого не втрачається. 🟡 target: `FilecoinReconcileWorker` (daily re-pin з БД) НЕ реалізований — re-pin поки ручний (INF.22). | Нічого (audit immutability — у durable Postgres, не на ефемерному диску). |
| 12. Ethereum L1 anchor | Ethereum mainnet | Gas spike, RPC down | `EthereumAnchorWorker` (cron `0 3 * * 1`, `unique_for: 7.days`): фейл тижня → Sidekiq retry; `detect_missed_anchor_weeks!` (gap > 8 днів → warn + `silkennet_anchor_missed_weeks_total`) робить пропуски видимими. 🟡 target: gas-price-гейт (`MAX_ANCHOR_GWEI`) з відкладеним пулом — НЕ реалізований (INF.22); анкор толерує multi-week gap by design. | Нічого (anchor — finality, не runtime). |

> **⚠️ Zero-Trust корекція: `did:local:fallback` для мінтингу видалено.** Минтити з локальним фейковим DID безглуздо й небезпечно: крок 5 (IoTeX W3bstream) генерує ZK-доказ, звіряючи підпис (наразі master-backed, не device-bound — true-DePIN ladder [`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)) із **зареєстрованим на-чейн peaq DID**. Без реального on-chain DID ZK-провера не знайде публічного ключа → `verified_by_iotex?` = `false` → guard clause мінтингу блокує його **в будь-якому разі**. Тобто local-DID не «розблоковує» мінт, а лише ризикує приписати вуглецеві кредити неперевіреному походженню. Правильно: телеметрія спокійно чекає у `pending`, а коли peaq оживає — DID дореєстровується і IoTeX дозаганяється. Краще зачекати на легітимний консенсус, ніж пропхати дані «костилем».

### 2.3 Worker Configuration (Sidekiq) — фактичний патерн

Реальна механіка (`app/workers/concerns/web3_circuit_breaker.rb` + воркери; чесність-пас 2026-07-04 — попередня редакція показувала неіснуючий шаблон із `sidekiq-unique-jobs`/`lock_timeout`/кастомним `sidekiq_retry_in`):

```ruby
class XxxWorker
  include Sidekiq::Worker
  include Web3CircuitBreaker          # RPC-обличчя: iotex/celo/solana/mint/chainlink-cb

  sidekiq_options queue: :web3, retry: 5   # 3–5 за критичністю; дефолтний Sidekiq-backoff

  def perform(...)
    with_circuit_breaker("polygon") do   # open ⇒ raise CircuitOpenError (fail-fast)
      # ... web3 call
    end
  rescue Web3CircuitBreaker::CircuitOpenError
    raise   # → Sidekiq retry set із стандартним exponential backoff
  end
end
```

- **Fail-fast, не busy-spin:** при відкритому circuit виклик миттєво `raise` → job іде у Sidekiq **retry set** (знімається з active) зі стандартним backoff — мертвий RPC не б'ється, черга не «пережовується». Унікальність там, де вона money-несуча, дає **Sidekiq Enterprise unique-shim** (`lock:` у batch-payout/treasury/collector) + durable intent-marker'и ARCH.45 — НЕ gem `sidekiq-unique-jobs`.
- 🟡 **target (INF.22):** reschedule-on-open через `perform_in(cooldown)` — точніше повернення «рівно в кінець cooldown» замість експоненційної сітки; цінно на високому ingest, зараз YAGNI (Sidekiq-backoff з головою на TRL-обсязі).

> **Чому НЕ `Sidekiq::Queue.new(:web3).pause`:** circuit breaker — **per-RPC** (Polygon / Solana / peaq…), а черги `web3`/`web3_critical` спільні для багатьох чейнів. Пауза всієї черги зупинила б і **здорові** чейни. Fail-fast-у-retry зберігає per-chain гранулярність. Чисту queue-pause можна застосувати лише якщо кожен чейн отримає окрему чергу (рефактор, Phase 2).

### 2.4 Resilience SLO

| Метрика | Target | Як вимірюється |
|---------|--------|----------------|
| Telemetry intake survival при Queen offline | ≥ 95% за 24 год | Queen self-telemetry CIFO fill + Helium fallback hit rate |
| Mint flow availability при single Web3-chain outage | ≥ 80% (degraded but functional) | Prometheus `silkennet_mint_success_total / silkennet_mint_attempts_total` over 1h windows |
| Recovery to full pipeline after multi-chain outage | < 4 год once external chains restore | Sidekiq retry-drain + reconcile-крони (ARCH.45); 🟡 target-виміри: backfill-воркери (IoTeX/Filecoin re-pin) не реалізовані — INF.22 |
| No data loss when all external chains down for ≤ 24 год | 100% — все буферизується | `TelemetryLog.count`, `BlockchainTransaction.where(state: :pending).count` зростання без втрат |

### 2.5 Money-path Queue Topology (ARCH.52 — anti-starvation at planetary scale)

**Проблема (planetary-обсяг, ~100 млрд дерев).** `config/sidekiq.yml` має `:strict: true` — у межах процесу черги дренажаться згори-вниз, нижча НІКОЛИ не випереджає вищу. Money-черги стоять НИЖЧЕ за intake: `uplink`(1) > `alerts`(2) > `critical`-slash(3) > … > `web3_critical`-mint(6) > `web3`(7). На planetary-обсязі `uplink` = вічний firehose телеметрії → під strict він дренажиться першим, а mint / slash / insurance / `BlockchainConfirmationWorker` **голодують** (money-throughput → 0; clawback-race на затриманому slash). Це НЕ priority-inversion — це коректний strict; money просто стоїть за intake. Перестановка черг лік не дає (підняти money над uplink = пожертвувати intake-SLO §2.4 ≥95%).

**Рішення — process-рівнева ізоляція (deploy-config, НЕ код).** Запускати **виділений money-path Sidekiq-процес** на черги `critical, web3_critical, web3, alerts` ФІЗИЧНО окремо від процесу intake (`uplink, downlink, default, …`). Кожен процес дренажить свій strict-ланцюг незалежно → firehose в `uplink` більше не може випередити mint/slash (детерміновано unstarvable thread-reservation). Обидва SLO §2.4 задоволені одночасно: intake-процес тримає intake ≥95%, money-процес тримає mint-availability ≥80%.

**Чому НЕ weighted-черги (drop `:strict`).** Weighted = probabilistic: під firehose не *гарантує* money-throughput І жертвує true critical-precedence (slash МУСИТЬ вигравати детерміновано). Strict + process-ізоляція > weighted на обох вимірах.

**Тригер flip'у (зараз НЕ потрібен — TRL-3, firehose ще немає).** Single-process baseline (`deploy.yml` job-role + Akash `count: 1`) коректний поки intake малий. Розділяти, коли: (а) `uplink`-backlog росте необмежено, АБО (б) mint-availability SLO (§2.4 `silkennet_mint_success_total / attempts`) пробиває ≥80%. Механізм flip'у = `sidekiq -q`-прапори per-процес у deploy-конфізі (reversible, без коду). ⚠️ Drift-ризик: список черг дублюється у deploy-місцях ([`06_02`](06_02_Akash_Network_Integration)). Розвиває §2.3 Phase-2 per-chain queue-split (та сама вісь — окремі процеси/черги).

### 2.6 Partition-prune scope (ARCH.52 — money-path hot-path queries)

`BlockchainTransaction` RANGE-партиційовано по `created_at` (композитний PK `(id, created_at)`). Запит без `created_at`-предиката → full-scan усіх партицій (O(P × log N)). Два РІЗНІ інструменти прунингу — за формою запиту:

- **Known-row lookup (id/tx_hash відомий) → `created_at`-вікно.** `BlockchainConfirmationWorker` несе `created_at_iso` (7 enqueue-сайтів прокидають) і фільтрує **LOWER-bound** `created_at >= earliest-1h`. ⚠️ Чому lower-bound, не симетричне ±1h: batchMint ділить ОДИН `tx_hash` на ≤100 рядків з РІЗНИМИ `created_at` (collector акумулює pending з широким span; reset-to-pending тримає старий `created_at`) → симетричне вікно виключило б рядки, новіші за earliest+1h → stuck `:sent`. Дзеркало `CeloConfirmationWorker` (ARCH.50).
- **Status-scan (множина невідома, може містити старі рядки) → partial index, НЕ `created_at`-вікно.** Pending-discovery (`Treasury::MintBatchCollectorService`, `MintCarbonCoinWorker`) НЕ може взяти `created_at` нижню межу: `MintCarbonCoinWorker` на RPC-error робить raw `update_all(:processing → :pending)` (зберігає старий `created_at`), а `MAX_PENDING_AGE_MINUTES` робить старі pending *urgent* (їх ТРЕБА знайти) → межа осиротила б stranded funds. Прунинг = **partial index** `index_blockchain_transactions_in_flight` `(status, created_at) WHERE status IN (0,1)` (pending+processing — крихітна частка all-time рядків) → full-scan стає index range-scan.
- **Свідомо НЕ прунимо (design):** slash `total_minted` sum (`BlockchainBurningService`) + anchor SFC-supply sum (`Ethereum::StateAnchorService`) = **all-time aggregates**, семантично unprunable (потребують усієї історії); long-term cost-opt = denormalized counter / on-chain `totalSupply` (як `ChainAuditService`), не partition-prune. `BlockchainMintingService#initialize` `where(id:)` вже index-served по PK leading-колонці `id` per-partition (partition-count = малий обмежений constant, НЕ O(all-history)).

---

## 3. 🧰 Реалізаційні Якорі (Implementation Anchors)

| Концепція | Файл / Сервіс | Статус |
|-----------|---------------|--------|
| Web3 circuit breaker (5 фейлів → 300 s open, Rails.cache, fail-fast) | `app/workers/concerns/web3_circuit_breaker.rb` ([`04_02`](04_02_Business_Logic_and_Services)) | ✅ Реалізовано |
| Multi-RPC fallback — **Celo** (`RPC_FALLBACK_ENV_KEYS`) | `Celo::CommunityRewardService` (E.49 in [`00_07`](00_07_Action_Plan_Tracker)) | ✅ Реалізовано (Solana/Polygon-каскади — 🟡 INF.22) |
| Queen-пульс: QATT-v2 health-блок + dead-man switch (DID=0-канал ВБИТИЙ — ARCH.54) | `enqueue_envelope_health` → `GatewayTelemetryWorker` · `GatewayStalenessSweepWorker` (§1.3) | ✅ Реалізовано |
| CoAP retry loop on Queen (`COAP_MAX_RETRIES`) | `firmware/queen/main.c`; host-tests `test_at_engine.c` (conversation-fail) + `test_fw51_*` (fail→retry→no-loss), FW.9 | ✅ Реалізовано |
| Manual review terminal state | `BlockchainTransaction` AASM | ✅ Реалізовано |
| Money-path crash-window idempotency (intent-marker + `in_flight` guard) | `BlockchainBurningService` / `Solana::BatchPayoutService` ([ARCH.45], [`04_02 §4/§10`](04_02_Business_Logic_and_Services)) | ✅ Реалізовано |
| Backfill/buffer-list/gas-defer механізми матриці §2.2 (IoTeX backfill · Filecoin re-pin · streamr/celo buffer · anchor gas-gate · Solana RPC-каскад · stuck-`:sent` mint re-arm) | — | 🟡 target-пакет [`00_07` INF.22](00_07_Action_Plan_Tracker) |
| Queen-to-Queen Backhaul Mesh | Concept у [`02_05`](02_05_Queen_Hardware_and_Starlink) | 🟡 Concept, planned Phase 2 |
| Helium fallback emit (Queen-side LoRaWAN) | Queen firmware `queen_helium_lorawan_uplink()` | 🟡 ARCH.34 firmware-half (backend ✅); Soldier-side відкинуто — Soldier не несе LoRaWAN MAC stack |
| Ingress Proxy (Rust/Go CoAP buffer, Series D) | ARCH.2 / E.5 | 🟡 far-horizon |
| Conductor L2 cluster heads (formerly "Sergeant") | [`00_08 §2.1`](00_08_Beyond_TRL9_Planetary_Roadmap) | 🟡 Concept (HW.27, TRL 1) |

---

