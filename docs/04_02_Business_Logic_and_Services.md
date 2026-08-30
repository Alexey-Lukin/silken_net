# 04_02: Бізнес-Логіка та Сервіси

## 🎯 Мета

Зафіксувати повний реєстр бізнес-логіки Rails-моноліту як Єдине Джерело Істини (SSOT). Документ описує всі **Service Objects** та **Sidekiq Workers**: їхні вхідні дані, відповідальність та вихідні ефекти. Слугує картою поточних сервісів для запобігання дублювання логіки під час розробки нових фіч і REST API (04_03).

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — System Qualified / Mainnet Ready.
- **Обґрунтування:** Всі заглушки (dClimate, Puro.earth) замінено на бойові Web3/HTTP інтеграції. Бізнес-логіка пройшла параноїдальний AI-аудит: повністю усунуто пастки `Network-in-Transaction`, витоки пам'яті (OOM) та ризики подвійної витрати (Double-Spend). Воркери fault-tolerant; money-path idempotency **шарова** — status guards / pessimistic lock (concurrent) + [ARCH.45] durable intent-marker + in-flight guard на on-chain↔DB crash-window (§4 / §10 / §11). **Примітка:** Chainlink dispatch демоутнуто до local correlation-marker **[ARCH.53]** — on-chain `sendRequest` вилучено (DON-callback unwired; LINK-cost без відповіді); мінт іде PATH 2 tokenomics, callback-endpoint live для майбутнього PATH 1.
- **Відкрите:** Planned-сервіси (Forester Guild → E.20, Cross-Registry → ARCH.5, Federated Learning → E.52) → [`00_07`](00_07_Action_Plan_Tracker); §13b doc↔code синхронність — enforced `model_doc_sync`-гейтом ([`00_06 §3`](00_06_SSOT_Documentation_Standard)), не ручний моніторинг.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | Схема БД (моделі під сервісами) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof-of-Growth пайплайн (порядок сервісів) |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Апаратне шифрування, HKDF ключі |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (Planned services: E.20 / ARCH.5 / E.52) |

### Конвенція впорядкування розділів

1. **Spine** (§1–§9): Service Objects, згруповані за **доменом відповідальності** (Telemetry → AI/Analytics → Polygon → Verification → Contracts → Emergency → Hardware/Security → Finance Oracles). Усередині домену — за порядком виконання у Proof-of-Growth pipeline (раніше зустрічається у потоці → раніше у документі).
2. **Multi-chain rails** (§10): сервіси для не-Polygon мереж (Solana, Celo, Ethereum L1, Filecoin, Streamr, The Graph, dClimate, Klima, Hadron) — окремою секцією, бо вони побудовані по тому ж API-патерну (`Web3::RpcConnectionPool` + `Eth::Contract` / `Web3::HttpClient`).
3. **Workers Registry** (§11): з групуванням за **чергами Sidekiq** у строгому порядку дренування (uplink → … → low), а не за доменом. Це навмисне — спрощує діагностику hot path.
4. **Call Chains, External Deps, Planned, Math/Security** (§12–кінець): horizontal cross-cuts і RFC-секції.

> **Anti-pattern, якого уникаємо:** змішувати порядок «домен» та «черга» в одній секції. Якщо сервіс і воркер живуть в одному домені — сервіс описаний у §1–§10, воркер — у §11, поєднані cross-reference у `Тригер` / `Сервіси`.

---

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Архітектурні Засади](#-1-архітектурні-засади) — базові класи, Web3 utility layer
- [2. Домен: Телеметрія (Telemetry)](#-2-домен-телеметрія-telemetry) — `TelemetryUnpackerService`, `AlertDispatchService`
- [3. Домен: AI та Аналітика (AI & Analytics)](#-3-домен-ai-та-аналітика-ai--analytics) — Insights, Attractor, SeedDerivation, GeoUtils, Entropy, Chronicle
- [4. Домен: Блокчейн — Polygon (Primary Chain)](#-4-домен-блокчейн--polygon-primary-chain) — Minting, Burning, Audit, Rollback, Puro.earth, Etherisc
- [5. Домен: Верифікація та Ідентичність (Verification & Identity)](#-5-домен-верифікація-та-ідентичність-verification--identity) — IoTeX, peaq, Chainlink, Ed25519
- [6. Домен: NaaS Контракти (Contract Management)](#-6-домен-naas-контракти-contract-management) — Contract health/termination
- [7. Домен: Надзвичайне Реагування (Emergency Response)](#-7-домен-надзвичайне-реагування-emergency-response) — `EmergencyResponseService`
- [8. Домен: Апаратне Забезпечення та Безпека (Hardware, IoT & Security)](#-8-домен-апаратне-забезпечення-та-безпека-hardware-iot--security) — HardwareKey, OTA HMAC, OtaPackager, **WeakKeyDetector**, **Web3NetworkGuard**, **EncryptionKeyGuard**
- [9. Домен: Фінансові Оракули (Finance Oracles)](#-9-домен-фінансові-оракули-finance-oracles) — порожній: курсу протокол не тримає
- [10. Домен: Мультичейн — Паралельні Рейки (Multi-chain)](#-10-домен-мультичейн--паралельні-рейки-multi-chain) — Solana, Celo, Klima, Hadron, Ethereum L1, Filecoin, Streamr, The Graph, dClimate, Treasury
- [11. Реєстр Воркерів (Workers Registry)](#-11-реєстр-воркерів-workers-registry) — групування за чергами
- [12. Карта Ланцюгів Викликів (Call Chains)](#-12-карта-ланцюгів-викликів-call-chains)
- [13. Зовнішні API Залежності](#-13-зовнішні-api-залежності)
- [13b. SSOT Drift Register (Doc ↔ Code Sync)](#-13b-ssot-drift-register-doc--code-sync)
- [Forester Guild — Proof-of-Physical-Work (design-RFC, маркетплейс ⚫ won't-do)](#-forester-guild--proof-of-physical-work-design-rfc-маркетплейс--wont-do)
- [Planned: Cross-Registry API (Міністерство Закордонних Справ)](#-planned-cross-registry-api-міністерство-закордонних-справ)
- [Planned: Federated Learning Loop (Міністерство Освіти)](#-planned-federated-learning-loop-міністерство-освіти)
- [Додаткові Матеріали](#додаткові-матеріали) — math, security principles, RSpec coverage
<!-- TOC:AUTO:END -->

---

## 🏗️ 1. Архітектурні Засади

### Базові класи

| Компонент | Файл | Призначення |
|-----------|------|-------------|
| `ApplicationService` | `app/services/application_service.rb` | Базовий клас для всіх сервісів. Надає `.call(...)` → `new(...).perform` template. |
| `ApplicationWeb3Worker` | `app/workers/application_web3_worker.rb` | Базовий **модуль** (не клас) для всіх блокчейн-воркерів. Включає: RPC rate limiter (50 rps), уніфіковану обробку помилок (HTTPX/Net timeouts), partition-pruned lookups: `find_telemetry_log_with_pruning(id, created_at_iso)` та `find_blockchain_tx_with_pruning(id, created_at_iso)` — обидва додають `created_at` у `WHERE` для уникнення Global Partition Scan по RANGE-партиціонованих таблицях. |
| `Web3CircuitBreaker` | `app/workers/concerns/web3_circuit_breaker.rb` | **[NEW]** ActiveSupport Concern із 3-state Circuit Breaker (`:closed` → `:open` → `:half_open`). `FAILURE_THRESHOLD=5` послідовних помилок → `OPEN_TIMEOUT=300с` (5 хв) fail-fast. Стан зберігається в `Rails.cache` (Solid Cache) — працює між Sidekiq-процесами та серверами. Розпізнає transient errors: `HTTPX::TimeoutError`, `Net::ReadTimeout`, `Errno::ECONNREFUSED`, `Web3::HttpClient::RequestError` + wrapped custom errors (`transient_cause?` перевіряє `Exception#cause` рекурсивно). Prometheus metric: `CIRCUIT_BREAKER_REJECTIONS`. Raises `CircuitOpenError` при відкритому circuit → **fail-fast**, далі Sidekiq native retry (власний backoff). **Свідомо БЕЗ `perform_in`-self-reschedule** (той плодив би нові job'и, втрачав retry-лічильник і давав thundering-herd при масовому open). Інтегровано в `IotexVerificationWorker` (`"iotex_w3bstream"`), `ChainlinkDispatchWorker` (`"chainlink_functions"`), `MintCarbonCoinWorker` (`"polygon_rpc"`), `SolanaMicroRewardWorker` (`"solana_spl"`), `CeloRewardWorker` (`"celo_cusd"`). |
| `CoapEncryption` | `app/workers/concerns/coap_encryption.rb` | Concern для downlink-воркерів. AES-256-CBC шифрування з випадковим IV, нульовий padding. **[FW.20]** Перед шифруванням автоматично огортає payload у TIME_SYNC envelope: `[0x9C: 1 byte][timestamp_be: 4 bytes (big-endian uint32)]`. Формат після шифрування: `[IV:16][Ciphertext:N×16]` де Ciphertext = зашифровано(`[0x9C][ts:4][original_payload]`). Soldier розпаковує конверт після дешифровки і коригує свій RTC. |

### Web3 Utility Layer

| Утиліта | Призначення |
|---------|-------------|
| `Web3::HttpClient` | Централізований HTTP-клієнт (HTTPX) для всіх зовнішніх API. Thread-safe persistent sessions, таймаути per-service, lazy JSON parsing. |
| `Web3::RpcConnectionPool` | Thread-safe кешування `Eth::Client` / `Web3::ResilientClient` per-thread. Зменшує TCP/TLS handshakes у Sidekiq-потоках. Підтримує fallback cascade через `fallback_env_keys`. |
| `Web3::ResilientClient` | Обгортка навколо `Eth::Client` з автоматичним fallback cascade (Primary→Secondary→Public) та Circuit Breaker: `MAX_FAILURES=3` послідовних збоїв → провайдер вимикається на `CIRCUIT_OPEN_DURATION=60s`. Розпізнає `Net::ReadTimeout`, `Errno::ECONNREFUSED`, HTTP 429. Thread-safe (Mutex). Метод `provider_health` для Prometheus-моніторингу. 🔴 **[ARCH.84] Звіт читає ЧИСТИЙ предикат `provider_reachable?`, і це інваріант, а не стиль:** доти він кликав мутуючий `provider_available?`, який при вичерпаному cooldown обнуляє лічильник, знімає `@circuit_opened_at` і переписує gauge — тобто **відкриття панелі здоровʼя напів-відкривало справжні circuit breaker`и**, а два оператори, що дивляться одночасно, міняли маршрутизацію RPC самим фактом перегляду. Розділено на пару: чистий `provider_reachable?` (звіт) ⊥ мутуючий `provider_available?` (лише диспетчер `available_urls`, бо саме він має право випробувати провайдера). ⚠️ **Дзеркало того самого дефекту жило в `Web3::HttpClient#circuit_status`** — методі, чий власний коментар каже «для моніторингу / Prometheus»; вилікувано тією ж парою. Носії — по одному приклад-піну на клас, обидва mutation-verified (звіт, що кличе мутуючий предикат, червонить поіменно). |
| `Web3::OracleSigner` | **[SEC.17]** One-Home «яка РОЛЬ якою парою ключів підписує». `for(role)` → підписант; ролі `:minter :slasher :celo :puro :klima :etherisc :anchor`, невідома → `ArgumentError`. Сьогодні кожна резолвиться в `LocalEnvSigner` над plaintext deploy-ENV; pre-mainnet GCP-KMS міграція ([`06_04 §5.5`](06_04_Secrets_Checklist)) міняє бекенд ТУТ і на жодному call-site. ⛔ **ENV-імена мусять лишатись ЛІТЕРАЛЬНИМИ `ENV.fetch("…")`, по одному на роль:** `spec/deploy/env_fetch_declaration_spec.rb` [INF.12] сканує `app/**` саме на цю форму й рахує SET-DIFF — табличний lookup випав би зі скану, і гейт пройшов би ЗЕЛЕНИМ, ВТРАТИВШИ змінну. |
| `Web3::LocalEnvSigner` | **[SEC.17]** Дефолтний бекенд підписання: `Eth::Key` з deploy-ENV — рівно те, що money-сервіси робили інлайном. `#address` · `#transact(client, …)` · `#static_call(client, …)`; kwargs проходять НАСКРІЗЬ недоторканими. 🔴 Клієнт — ПАРАМЕТР кожного виклику, ніколи не стан: `RpcConnectionPool` є per-thread кешем, тож підписант, що тримав би клієнта, дублював би той кеш. 🔴 `#address` віддає `Eth::Address` ВЕРБАТИМ — значення інтерполюється в Kredis-ключ `lock:web3:oracle:<addr>`, точку серіалізації nonce'ів [ARCH.47]; будь-яка нормалізація ПЕРЕСУВАЄ ключ і два процеси беруть різні локи на одну адресу. Blank-ключ → `ArgumentError`, бо `Eth::Key.new(priv: nil)` НЕ падає, а тихо генерує ВИПАДКОВУ пару. |
| `Web3::FeePolicy` | **[ARCH.62]** One-Home EIP-1559 fee. Накладається на МІСЦІ НАРОДЖЕННЯ клієнта (`RpcConnectionPool#build_client`), тож кожен клієнт дерева народжується вже з політикою, а не за памʼяттю автора нового money-сайту. Мережа деривується СТАТИЧНО з `rpc_url_env_key` (`network_for`) — ні RPC, ні `chain_id` не потрібні. 🔴 **Проблема була не в тому, що стелі бракувало — вона СТОЯЛА, і обрав її гем:** `eth 0.5.17` присвоює fee у власному конструкторі (42.69 / 1.01 Gwei, позначені в ньому ж `# Do not use.`) і ціни з ноди не питає ніколи, а присвоєння в усьому `app/` існувало рівно одне — на L1. ⚠️ **Напрямок ризику інверсний до інтуїції:** `maxFee` — не стеля витрат, а підлога готовності майнитись (платиться `baseFee+priority`, `maxFee` лише обмежує), тож занизьке число не економить, а лишає tx у вічному `:sent` → `MintingRollbackService` → `manual_review`. 🔒 Ethereum несе успадковані 100/2 Gwei; Polygon/Celo дефолту в коді НЕ мають — політика не вигадує величини, а гучно мовчить (⚖️ [`00_07`](00_07_Action_Plan_Tracker) ARCH.62). Обидва числа мережі задаються РАЗОМ: cap без priority лишив би tip 1.01 Gwei, тобто «полагоджено» на вигляд і невключабельно насправді. ⛔ Ціни в мережі НЕ питає — гем це вміє (`eth_gas_price` / `eth_max_priority_fee_per_gas` / `eth_fee_history` існують справжніми методами через `Api::COMMANDS`), і динамічний варіант зняв би присуд про число, але формат відповідей на money-path не вгадується без живої ноди. |
| `Web3::WeiConverter` | `BigDecimal`-based конвертація `amount → wei` (ERC-20). Запобігає Float-похибкам у фінансових операціях. |

---

## 🌡️ 2. Домен: Телеметрія (Telemetry)

### `TelemetryUnpackerService`

| | |
|---|---|
| **Файл** | `app/services/telemetry_unpacker_service.rb` |
| **Вхід** | `binary_batch` (сирий бінарний батч), `gateway_id` (Integer, опціонально — `nil` якщо шлюз невідомий), `received_at:` (kwarg, default `nil` — **[ARCH.41]** момент ПРИЙОМУ пакета з job-аргументів воркера; він єдиний у тракті не рухається між Sidekiq-спробами, тож саме з нього береться доба cold-derive (`derivation_epoch_day`). `nil` ⇒ «прийом = зараз» — легально лише для bench/HIL/спек, що кличуть сервіс напряму), `gateway_attested:` (kwarg, default `false` — **[L1 QATT]** батч пройшов Ed25519-верифікацію Королеви у `UnpackTelemetryWorker`; протягується у `telemetry_logs.gateway_attested` кожного рядка в `commit_telemetry` — обидва шляхи, ECB і CCM) |
| **Що робить** | Розрізає бінарний батч на 21-байтні чанки (`[DID:4][RSSI:1][Payload:16]`). Калібрує сенсорні дані, обчислює Z-значення атрактора Лоренца, записує `TelemetryLog`. Детектує `firmware_mismatch`. **[ARCH.54]** DID=0 у батчі — retired: дропається з логом на ОБОХ шляхах (ECB і CCM; пульс Королеви їде QATT-v2 конвертом — [`03_02 §7`](03_02_Queen_Gateway_Firmware)). **[E.63]** β більше НЕ збурюється метаболізмом — `growth_points` декодується з wire `(status_byte & 0x1F) * 2` (формула на пристрої, [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor)); `metabolism_s`/`voltage_mv` ще передаються у `calculate_z_from_state`, але на Z не впливають. Метаболічний DCI — `check_metabolic_divergence!`: структурна band-звірка (ECB) + **точна stateless гілка** `Attractor.expected_homeostasis_gp(ema)`==wire-GP (CCM rev2.1, контракт «wire = вхід GP»; observational до bench-калібрування; деталі [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor)). **[FW.8]** `check_z_divergence!` використовує `tree.effective_lorenz_thresholds` (3-tier: cluster override → tree_family → global). **[FW.57 F2]** Z + `anomaly_ceiling` (DCI) беруть **raw** wire-temp (`lorenz_temperature`), не calibrated `temperature_c` (та — physical/display: fire-threshold, UI); інакше `temperature_offset_c≠0` хаотично розсинхронив би server_z↔device_z (5°C → ~16u). **[SEC.11]** Per-tree Lorenz state dispatch: для кожного дерева читає попередній `TelemetryLog.lorenz_state_x/y/z` (warm continuation, mirror RTC DR16-DR18); якщо tail відсутній (cold start після VBAT loss або перший uplink) — деривує `(x₀,y₀,z₀)` з `hardware_keys.binary_lorenz_seed` через `SilkenNet::SeedDerivation.initial_state(K_seed, epoch_day)` і ставить `cold_start_flag = true`. Persist'ить нові `lorenz_state_*` після обчислення Z. Raise `MissingLorenzSeedError` якщо дерево не має provisioned `K_seed` (hard cutover — production guarantee). **[SEC.10]** Frame Counter anti-replay для panic packets — детектує panic через `status_byte & PANIC_FLAG_BIT (0x80)`, читає `panic_frame_counter` BE з `pad_data[2..3]`, виконує SETNX через `Rails.cache.write(unless_exist: true)` з ключем `silken:panic:nonce:{hex_did}:{counter}` і TTL 25 годин. При replay — early return ДО `commit_telemetry` (TelemetryLog не створюється, AlertDispatchService не викликається), Prometheus `silkennet_panic_replay_rejected_total` increment. Counter==0 (legacy firmware) пропускає перевірку. Поза-panic пакети (більшість трафіку) перевірку не платять. **[FW.2 wire-rev2]** (дзеркало SSOT — [`03_05 §2.1`](03_05_Hardware_Symmetric_Crypto_and_Security)) Паралельний **31-байтний** CCM-парсер `process_ccm_chunk` (wire-rev2.1; `[DID:4][RSSI:1][gossip:1][FC:3 BE][ciphertext:14][MIC:8]` — Queen-сліпий-кур'єр префіксить лише RSSI; білдер запису — `firmware/queen/rx_route.h`) — feature-flagged через `ENV["TELEMETRY_CCM_ENABLED"]=true` (default off → 21B ECB path без змін). На активному прапорі: (a) AES-128-CCM decrypt + MIC verify через `Cryptography::LoraCcm.decrypt(...)` (8-byte AAD=DID‖gossip‖FC24, 12-byte nonce=DID‖FC32‖4×0x00 — gossip у нонс НЕ входить, 8-byte tag, per-DID `HardwareKey#binary_key`); MIC fail → `TELEMETRY_CCM_MIC_FAIL_TOTAL` + early return; (b) per-DID Frame Counter SETNX через `silken:ccm:fc:{did}:{fc}` TTL=25h, replay → `TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL`; (c) sensor payload unpack `n c C n C C n C C n` (…+ device_z BE [FW.31 Gate D], diag [FW.18b/FW.42/fc_degraded], vpd_index [HW.32-резерв], **ema_delta_t_s** [E.63 (г) — транзієнт, живить точну metabolic-гілку]); (d) mesh_ctrl `[ttl:4 \| fw_epoch_nibble:4]` — повна `firmware_version_id` reconstruction потребує OTA epoch config (deferred); (e) Queen sentinel (DID=0) на CCM-шляху дропається (Queen self-telemetry → dedicated CoAP-канал, фліп-гейт [`00_07`](00_07_Action_Plan_Tracker) FW.2); panic їде тим самим CCM-потоком — FC-нонс замінює SEC.10 Redis-лічильник. Успіх → `TELEMETRY_CCM_DECRYPT_OK_TOTAL` + standard `commit_telemetry` pipeline. Firmware-side integration authored 2026-07-03 (обидва call-sites за `FW2_CCM_ENABLED`, WL-true двофазний CRYP-флоу); лишився bench silicon-confirm. |
| **Зовнішні виклики** | `SilkenNet::Attractor.calculate_z_from_state(x_prev, y_prev, z_prev, temp, acoustic, metabolism_s, voltage_mv)`, `SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)` (cold-start + ARCH.41 fallback), `AlertDispatchService.analyze_and_trigger!`, `IotexVerificationWorker.perform_async`, `StreamrBroadcastWorker.perform_async`, `GatewayTelemetryWorker.perform_async`, `TimeSyncDownlinkWorker.perform_async` (ARCH.41) |
| **Вихід / Side Effects** | Створює `TelemetryLog` записи (з `lorenz_state_x/y/z` + `cold_start_flag` [SEC.11] + `time_unsynced_fallback` [ARCH.41]). Оновлює `tree.latest_voltage_mv`. ⛔ [ARCH.84, 2026-08-16] `tree.health_streak` більше не пишеться — писач `update_health_streak!` знято разом з усією anti-flapping-петлею (`UPDATE trees` на КОЖЕН chunk, поверх `mark_seen!` того ж рядка, row-lock до кінця транзакції). Нараховує `wallet.balance` (growth_points). ⚠️ **Mismatch прошивки лише СПОСТЕРІГАЄТЬСЯ — стану НЕ міняє** (виправлено 2026-08-16; доти тут стояло «Позначає `tree.firmware_update_status = :fw_pending`», знято присудом `ARCH.85` ще 2026-08-14): `check_firmware_mismatch!` пише лог і виходить, бо тракт не біг жодного разу й перший прогін стався б одразу в полі — а ретрансміту в цього стану немає ([`FW.63`](00_07_Action_Plan_Tracker)). |
| **[ARCH.41] VBAT-loss DCI fallback** | `check_z_divergence!` при warm-start categorical mismatch пробує 3 epoch_day кандидати (today, today−1, `FIRMWARE_RTC_DEFAULT_EPOCH_DAY=10_957` — exact civil-days, дім значення [`03_04 §2.1`](03_04_mruby_Lorenz_Attractor)). Для кожного: деривує `(x₀,y₀,z₀) = SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)`, обчислює Z через `Attractor.calculate_z_from_state`. Якщо будь-який кандидат дає категоричний збіг з device — `TelemetryLog#time_unsynced_fallback = true`, `TimeSyncDownlinkWorker.perform_async(cluster_id)` (push-нога воркера у CGNAT не долітає [FW.60] — фактичний sync їде конвертом КОЖНОЇ poll-відповіді Королеви: `[0x9C][ts:4]` → Queen RTC оновлення → LoRa beacon → Soldier sync). fraud_metric НЕ інкрементується. Cold-start пакети (cold_start_flag=true) recovery не потребують. [ARCH.41-B] Явний wire-sentinel `acoustic_events=0xFE` обробляється ДО DCI: `apply_time_uncertain_sentinel!` нейтралізує acoustic→0 (дзеркало прошивки — Лоренц на обох сторонах рахується з 0), ставить `time_unsynced_fallback` + enqueue worker одразу. |

### `AlertDispatchService`

| | |
|---|---|
| **Файл** | `app/services/alert_dispatch_service.rb` |
| **Вхід** | `TelemetryLog` (через `.analyze_and_trigger!`) або `Tree` + `target_date` (через `.create_fraud_alert!` — сигнатуру звужено з «будь-який рядок», бо та ширина впускала прозу в локалізовану рамку) |
| **Що робить** | Аналізує телеметрію за напрямками: софт-збій прошивки (**[SLASH-1 P0]** `bio_status_vm_error?` (wire status=3 = `BIO_STATUS_VM_ERROR`) → `firmware_fault`, аналіз ПРОДОВЖУЄТЬСЯ — сенсорна половина кадру виміряна до mruby; раніше хибно читався «вандалізмом» → `vandalism_breach` → positive-A slash жертви OTA-бага), пожежа (thermal: `temperature_c ≥ fire_limit`), пилка (**[SLASH-1]** `panic? \|\| bio_status_anomaly?` БЕЗ термального порога → `chainsaw_detected`; `panic?` — реальна пилка: TinyML panic-TX несе status=homeostasis + PANIC_FLAG, тож сам `bio_status_anomaly?` її не бачить; до спліту конфлатилось у `fire_detected` → FIRMS бачив «ясне небо» → тавро rejected_fraud на жертві вирубки), посуха/атрактор. Термальний сигнал має пріоритет (горіння+пиляння упереміш = спершу пожежна відповідь). «Втрата живлення» (`voltage_mv < 100`) скипається на panic-кадрах (вони свідомо несуть vcap=0 — legacy-parity обох panic-збирачів). Адаптивні пороги (з кластера/породи дерева). Redis-фільтр тиші (5 хвилин per `tree_id:alert_type`). **[SEC.10]** Per-DID rate limiting для critical alerts: `MAX_ALERTS_PER_DID_PER_WINDOW=5` critical alerts за `DID_RATE_LIMIT_WINDOW=1.minute` — захист від replay/injection атак (forged panic packets). Time-bucketed cache key `"ews_did_rate:#{tree.did}:#{time_bucket}"`, TTL = 2 хвилини. Перевищення → warn log + silent drop. |
| **Зовнішні виклики** | `EmergencyResponseService.call`. `AlertNotificationWorker` більше **не** викликається явно — `EwsAlert.after_create_commit :dispatch_notifications!` ставить job у чергу безпечно після commit транзакції (A-1 Transactional Outbox). |
| **Вихід** | Створює `EwsAlert`. Інвалідує `oracle_expected_yield_24h` кеш при critical severity. Повертає `nil` (всі дії через side effects). |

---

## 🧠 3. Домен: AI та Аналітика (AI & Analytics)

### `InsightGeneratorService`

| | |
|---|---|
| **Файл** | `app/services/insight_generator_service.rb` |
| **Вхід** | `date` (Date, default: вчора UTC) |
| **Що робить** | Добова агрегація телеметрії → `AiInsight`. Включає: AI Fraud Guard (відхилення sap_flow/temp від кластерного базлайну > 30%), ML-модель (`silken_forest.marshal` + SHA256 integrity check) або евристика stress_index. Денормалізує `tree.latest_stress_index`. ⛔ **Телеметрії НЕ чистить** — рядковий `cleanup_old_logs!` (`delete_all` старших 7 днів із гардом на `oracle_status`) зрізано присудом ⚖️ [`ARCH.59`](00_07_Action_Plan_Tracker) 2026-08-21: ретеншн сирої телеметрії робить ВИКЛЮЧНО дроп партицій, бо другий механізм зникнення рядків зробив би `TelemetryArchiveBatch.retention_expired` неоднозначним. Дім дозволу — [`04_01 §3`](04_01_Data_Models_and_Entities) `DOC.8`; фактичний ретеншн сьогодні **нульовий** (дропу ще не збудовано, [`ARCH.70`](00_07_Action_Plan_Tracker)). |
| **Публічні методи** | `call(date)` / `perform` (сумісність). `cluster_baselines → Hash<cluster_id, baselines>` — один SQL, потрібен `InsightGeneratorOrchestratorWorker`. `process_cluster_batch(cluster_ids) → Integer` — обробка чанку кластерів для `GenerateClusterInsightWorker`. |
| **Зовнішні виклики** | `AlertDispatchService.create_fraud_alert!` |
| **Вихід** | `{ processed_count: Integer, date: Date }`. Створює `AiInsight` per tree та per cluster. |

> 🔴 **[ARCH.84] Вердикт за добу дістає КОЖНЕ активне дерево, а не лише те, що слало телеметрію.** Доти `process_cluster_trees` робив `next unless stats`, тож денормалізований `trees.latest_stress_index` лишався стояти з попереднього прогону НАЗАВЖДИ — «понеділковий 0.42 на вівторковій темряві». Це та сама підміна виміру, лише постаріла, і саме її уникає дзеркальний `Cluster#recalculate_health_index!` ([`04_01 §3`](04_01_Data_Models_and_Entities)). Тепер мовчазне дерево дістає **явний `nil`**. ⚠️ **Дір було ДВІ, і друга не закривається циклом:** обидва шляхи (синхронний `#perform` і шардований `#process_cluster_batch`) обходять лише кластери з даними (`cluster_baselines.keys`), тож кластер, що замовк ЦІЛКОМ, не відвідується взагалі — його трактує `InsightGeneratorService.reset_stress_outside(cluster_ids)`, один set-based `UPDATE` (дім один, викликачів два: сам сервіс і `InsightGeneratorOrchestratorWorker`). Механізм і межі — [`04_01 §2`](04_01_Data_Models_and_Entities).
>
> 🔴 **[ARCH.84] Навчальний набір моделі стресу — ЛИШЕ деревні рядки, і дім множини — `AiInsight.stress_training_set`.** Тренер (`lib/tasks/ai_train.rake`) будує вектор фіч із `average_temperature` + `reasoning[avg_vcap|avg_z|max_acoustic]`, яких КЛАСТЕРНИЙ рядок не має взагалі — він агрегат. Доти вибірка йшла `daily_health_summary.where.not(stress_index: nil)` без фільтра типу, і кожен кластерний рядок заходив у набір як **`[0.0, 0.0, 0.0, 0.0]`** (0 °C, 0 мВ, z=0, нуль акустики) з міткою від кластерного середнього — виміряно рантаймом; на трьох деревах це чверть набору. ⚠️ Напрямок несучий: на здоровому лісі мітка `0`, тобто модель училась би, що нульові покази — норма, і мовчазний сенсор класифікувався б здоровим. ⊕ Фільтр живе СКОУПОМ, а не рядком у rake, саме тому, що rake-таска спеки не має — носій інакше не існував би ([`04_01 §7`](04_01_Data_Models_and_Entities) `AiInsight`).
>
> 🔴 **[ARCH.84] Кластерний агрегат НАЗИВАЄ свою популяцію.** `aggregate_cluster!` пише не голе середнє, а середнє **плюс підставу**: `reasoning.measured_trees` (`.distinct` по деревах) і `reasoning.total_trees` (живий `COUNT` по `trees.active`) — дім контракту [`04_01 §7`](04_01_Data_Models_and_Entities) `AiInsight`. Доти єдиним носієм цієї різниці була проза `summary`, тож усі три машинні читачі (комерційний `backing_asset.cluster_health` · Celo-виплата · IPFS-доказ) не відрізняли кластер, виміряний на пʼяту частину, від виміряного повністю. ⚠️ Множина середнього — **`trees.active`**, як у `DailyHealthRouter` і `BlockchainBurningService#calculate_damage_ratio`: доти цей писач був ЄДИНИМ із чотирьох читачів доби, хто брав `cluster.trees` цілком, тобто пускав інсайт мертвого дерева в середнє живого лісу.
>
> 🔴 **Писачів стресу ТРИ, усі обходять колбеки — тож броадкаст мапи в кожному ЯВНИЙ.** `update_column` (вимір · занулення мовчазного) і `update_all` (`reset_stress_outside`) не пускають `after_update_commit` узагалі, а колір маркера тримає саме `latest_stress_index` — отже без явного виклику чесний колір не доїжджав би до відкритого дашборда ЖОДНОГО разу ([`04_01 §2`](04_01_Data_Models_and_Entities), друга половина пари). ⚠️ Обхід колбеків тут свідомий (hot path, знаменник ~10¹² — [`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap)), тож повертати звичайний `update!` не треба; треба **не забути броадкаст, додаючи ЧЕТВЕРТОГО писача**. ⚠️ І кожен із трьох стріляє лише на РЕАЛЬНІЙ зміні (`stress_changed` · `where.not(latest_stress_index: nil)` · гард на вже-порожнє): безумовний броадкаст на нічному проході — не марнотратство, а DoS на власний дашборд. У масовій гілці набір ще й звужено `.geolocated` (бо `broadcast_map_update` сам гейтується координатами), а колонка синхронізується **в памʼяті**, не `reload`-ом: `update_all` щойно поставив одну колонку у ВІДОМЕ значення, тож перечитування рядка додало б по SELECT-у на дерево — N+1 рівно на тому шляху, заради ефективності якого set-based `UPDATE` тут і стоїть. ⚠️ Пін на цю синхронізацію окремий і потрібен: без неї броадкаст поїде з учорашнім числом, тобто мертвий колір із живим сокетом. Носій — по приклад-піну на писача (`spec/services/insight_generator_service_spec.rb`), кожен mutation-verified окремо.

> 🧱 **Система REGION-AGNOSTIC за дизайном, і це присуд, а не збіг.** Фрод і стрес рахуються від добових середніх ВЛАСНОГО кластера (`cluster_baselines` — `AVG` по `cluster_id`), тож «тропічний проти бореального» не є дефектом цього шару: базлайн приходить із того самого лісу, що й вимір. ⛔ **Не додавати region-колонку в `ai_insights`** і **не чіпати `data_region`** — та колонка про GDPR-residency даних, а не про клімат; сплутати їх означає завести другий дім чужого рішення. ⚠️ **Єдиний абсолютний climate-вхід, що лишається, — ML-фіча `average_temperature`** у векторі вище: модель, натренована на одному біомі, зміщена в іншому. Евристика цієї вади вже НЕ має (ambient-temp член прибрано E.64), а лік для моделі — cluster-relative deviation, дзеркало sap; він не потребує ЖОДНИХ regional даних і дозріває разом із retrain-подією ([`00_07`](00_07_Action_Plan_Tracker) E.52).
>
> **🌫️ VPD weather-confounder gate [✅ implemented · inert/calibration-pending — HW.32]:** Щоб не штрафувати за погоду (де-ризик [`05_05 §6/§7`](05_05_Slashing_and_Risk_Policy)), `stress_index` мав дисконтуватись, коли пригнічений метаболізм пояснюється **погодою**, а не хворобою: насичене повітря (дощ/туман → **низький VPD**) дає нульову транспіраційну тягу → сік природно падає на здоровому дереві. 🔴 **Інертність тут СТРУКТУРНА, не «до калібрування»:** гейтові потрібні ДВА входи — погода І метаболічне відхилення, — а другого немає взагалі (`sap_flow` писача не мав і знятий), тож дисконтувати лише за вологим днем означало б **вибачати посуху погодою** без жодного підтвердження з дерева. Сигнатура зведена до `apply_weather_confounder(stress_index, _avg_vpd)` і повертає вхід незміненим. ⚠️ Чому гейт лишено, а акустичний терм — ні: **напрямок**. Цей тільки ЗНИЖУЄ, тож його мовчання нічого не вигадує; терм, що стрес ПІДВИЩУВАВ, мовчати безпечно не вміє. 🔓 Тригер оживлення — поява метаболічного виміру на рівні дерева ([E.63] `delta_t`), не VPD-калібрування. `avg_vpd` плюмиться через `prefetch_tree_stats` (`AVG(vpd)`) і пишеться у `reasoning`. Калібрування — ТІЛЬКИ через ENV `VPD_CONFOUNDER_LOW_KPA` + `VPD_CONFOUNDER_MAX_DISCOUNT` (default unset → no-op; **жодного вгаданого kPa-порогу в slashing-шляху**). **Три залежності перед активацією (свідомо НЕ хардкодимо вгадані пороги у slashing — це суперечило б де-ризику):** (1) ML-модель `silken_forest.marshal` не має VPD-фічі → **retrain** з `[temp, vcap, Z, sap_dev, acoustic, vpd]` (heuristic-only до того); (2) 🔴 `calculate_stress_index_heuristic` прямих термів БІЛЬШЕ НЕ МАЄ — обидва (sap + acoustic) зняті 2026-08-16, підстава й умова повернення — [`05_05 §7`](05_05_Slashing_and_Risk_Policy); евристика має стелю **0.6 < 0.83**, тобто нею слешинг недосяжний. **[E.64] conformance** — прибрано degenerate `avg_z>2`/weather-`temp` confound-члени, Z-anomaly bounded (не auto-1.0, «Z alone never slashes»), **[SLASH-1 P0]** `vm_error` (status 3) → **0.0** (софт-збій ≠ біо-стрес; старий `≥3 → 1.0` робив кластерний OTA-баг max-стресом = тригер слешу + damage-sizing разом; ops-сигнал живе у `firmware_fault`-алерті); (3) пороги «низький VPD» (kPa) + величина знижки — з **ground-truth калібрування** [`05_05 §8`](05_05_Slashing_and_Risk_Policy). Firmware VPD — `HW.32`/[`03_01`](03_01_Firmware_Lifecycle_and_DMA) (ще не шле → `vpd` nil → gate inert). **Активувати лише після (firmware VPD + ML-retrain + калібрування).**

### `SilkenNet::Attractor`

| | |
|---|---|
| **Файл** | `app/services/silken_net/attractor.rb` |
| **Вхід** | `(x_prev, y_prev, z_prev)` (Float×3, ∈ ℝ — попередня точка фазового простору або K_seed-derived cold start), `temp` (Float °C), `acoustic` (Integer events), `delta_t_s` (Integer с, default: `BASELINE_DELTA_T_S=60`), `vcap_mv` (Integer мВ, default: `NOMINAL_VCAP_MV=3300`) |
| **Що робить** | Обчислює Z-значення атрактора Лоренца. σ=10, ρ=28, β=8/3 (base). 250 ітерацій, timestep=0.01. **[FIX FW.7]** `Float` (IEEE 754 double) — ідентично firmware mruby для Dual Computation Integrity. BigDecimal замінено на Float: різна математика давала розбіжність Z на десятки одиниць після 250 ітерацій хаотичної системи. Clamp: σ∈[5,30], ρ∈[10,50]. **[E.63]** β = `BASE_BETA` фіксований — `perturb_beta` ВИДАЛЕНО (метаболізм перенесено у `growth_points` напряму, не через β; присуд 00_07 E.63). `calculate_z_from_state` приймає `delta_t_s`/`vcap_mv` лише для сумісності — на Z вони не впливають. **[SEC.11]** Sole entry-point — `calculate_z_from_state(x_prev, y_prev, z_prev, …)`. Legacy `calculate_z(seed, …)` видалено (hard cutover). DID не є входом — `(x_prev, y_prev, z_prev)` приходять з попереднього `TelemetryLog.lorenz_state_*` (warm) або з `SeedDerivation.initial_state(K_seed, epoch_day)` (cold). |
| **Вихід** | `calculate_z_from_state → [z_rounded, x_final, y_final, z_final]` (Float×4). `homeostatic? → Boolean`. `generate_trajectory(x₀, y₀, z₀, …) → Array<Float>` (плаский масив x,y,z × 250 для Three.js). |
| **Константи** | β = `BASE_BETA = 8/3` (фікс, [E.63] — β більше НЕ збурюється). `growth_points` formula живе на пристрої ([`03_04 §4.3`](03_04_mruby_Lorenz_Attractor), метаболічна `m(delta_t)`); backend лише декодує wire `(byte & 0x1F) * 2`. `BASELINE_DELTA_T_S`/`NOMINAL_VCAP_MV` лишаються default-аргументами сигнатур (на Z не впливають) |
| **Примітка** | `generate_trajectory`: перший триплет (індекс 0–2) — початкова точка `(x₀, y₀, z₀)` до інтеграції; інтеграція Лоренца починається з індексу 3 (`i=3` → крок 1). |

### `SilkenNet::SeedDerivation` 🔐 [SEC.11]

| | |
|---|---|
| **Файл** | `app/services/silken_net/seed_derivation.rb` |
| **Вхід** | `derive_seed(device_uid, master_key: nil)` — DID/UID пристрою (позиційний String) + опційний master key (SEC.3 DI); `initial_state(seed_bytes, epoch_day = current_epoch_day)` — 32-байтний `K_seed` + UTC epoch day (`Time.now.utc.to_i / 86_400`) |
| **Що робить** | Криптографічна основа для `(x₀, y₀, z₀)` атрактора Лоренца. **`derive_seed`:** виводить per-device `K_seed = HKDF-SHA256(master_key, salt="silken-lorenz-v1", info="silken-lorenz-seed\|<DID>", len=32)`; ikm = `master_key:` параметр (фабрична `Session` несе його від `MasterKeySource` — SEC.3 DI) або ENV-fallback `PROVISIONING_MASTER_KEY`. Викликається при provisioning з `HardwareKeyService#provision`. Повертає 64-символьний HEX (upper) щоб лягло у ту саму колонку, що й `aes_key_hex`. **`initial_state`:** обчислює `digest = HMAC-SHA256(K_seed, "init\|" + epoch_day_be8)`; розпаковує в `(x₀, y₀, z₀) ∈ [-1, +1]³` через `signed_unit_float` (8 байт → big-endian uint64 → `(n - UINT64_HALF) / UINT64_HALF`). Daily `epoch_day` rotation дає forward secrecy ≤ 24 год. Hard cutover: raise `SecurityError` без master key (no SecureRandom fallback ANYWHERE — навіть у dev/test, які pin-ять ключ у `spec/rails_helper.rb`). |
| **Вихід** | `derive_seed → 64-char HEX String (upper)`; `initial_state → [x0, y0, z0]` (Float×3) |
| **Алгоритм та парність** | OpenSSL HKDF-SHA256 (RFC 5869) + HMAC-SHA256. Host-parity test `firmware/test/test_seed_derivation.c` валідує OpenSSL ↔ `silken_sha256.h` (pure-C) байт-ідентичність на детермінованих векторах + 100-case fuzz. Backend ↔ firmware деривують `(x₀, y₀, z₀)` byte-identical для тієї самої пари `(K_seed, epoch_day)`. |
| **Викликається з** | `HardwareKeyService#provision` (provisioning), `TelemetryUnpackerService` (cold-start dispatch) |
| **Зовнішні виклики** | `OpenSSL::KDF.hkdf`, `OpenSSL::HMAC.digest("SHA256", …)` |
| **Безпека** | `K_seed` ніколи не залишає Ruby-процес у відкритому вигляді (in-process derivation: master key приходить параметром від фабричної `Session` (SEC.3 DI) або з `ENV["PROVISIONING_MASTER_KEY"]` — в обох випадках без серіалізації). DID використовується лише як `info`-string у HKDF (namespace separator) — криптографічно безпечно. Cross-ref: [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning) Lorenz K_seed Derivation, [`03_04 §3` Крок 1](03_04_mruby_Lorenz_Attractor#крок-1-походження-початкових-координат-x₀-y₀-z₀-sec11). |

### `SilkenNet::GeoUtils`

| | |
|---|---|
| **Файл** | `app/services/silken_net/geo_utils.rb` |
| **Вхід** | `lat1, lng1, lat2, lng2` (Float, WGS-84) |
| **Що робить** | Haversine distance calculation між двома GPS-точками. |
| **Вихід** | `haversine_distance_m → Float` (метри). |

### `SilkenNet::EntropyCalculatorService`

| | |
|---|---|
| **Файл** | `app/services/silken_net/entropy_calculator_service.rb` |
| **Вхід** | `z_values` (Array\<Float>) — масив Z-значень атрактора Лоренца з кластера |
| **Що робить** | Обчислює нормалізовану ентропію Шеннона для розподілу Z-значень. Фіксоване бінування по діапазону [2.0, 45.0] (homeostasis zone Лоренца). 20 бінів, ширина ~2.15. Мінімум 30 точок даних для статистичної значущості. Здоровий ліс: diverse Z → entropy ≈ 0.75-0.95. Стрес: homogeneous Z → entropy < 0.5. **[Lorenz de-risk]** інтерпретація Z-розподіл → здоров'я лісу — недоведена гіпотеза ([`05_05 §7–8`](05_05_Slashing_and_Risk_Policy)); сигнал, не вердикт. |
| **Чому Z-value, а не HRNG seed** | `chaos_seed` (HRNG) НЕ передається у 21-байтному LoRa-пакеті (03_01, Phase 2). Backend використовує z_value як проксі. Див. ЧДТУ task #12 (00_02 §1.2). |
| **Математика** | `H = -Σ p(x) × log₂(p(x))`, `H_norm = H / log₂(NUM_BINS)` ∈ [0.0, 1.0] |
| **Вихід** | `Float` (0.0-1.0) або `nil` (недостатньо даних). |

### `SilkenNet::LorenzValidationService` [Lorenz de-risk]

| | |
|---|---|
| **Файл** | `app/services/silken_net/lorenz_validation_service.rb` |
| **Вхід** | парні `(telemetry, ground_truth)`-спостереження (передаються аргументом — **pure / read-only**, без DB-доступу й slashing-side-effects) |
| **Що робить** | Ground-truth validation harness для гіпотези «Lorenz Z ↔ здоров'я дерева» ([`05_05 §8`](05_05_Slashing_and_Risk_Policy) — ⚠️ парний реф на медакадемію тут стояв помилково: харнес про Z↔health, а не про токсикологію; партнер аналізу — ЧНУ, [`00_02 §1.1`](00_02_Academic_Integration_and_IP)): Spearman-кореляція `stress_index` ↔ занепад + `z_incremental_over_sap` (чи Z додає predictive value **понад** прямі sap-сигнали). Push-button аналіз для ЧНУ після збору парних даних — поки гіпотеза недоведена (сигнал, не вердикт). |
| **Вихід** | `report` (Hash кореляцій/інкрементів). Чиста функція. |

### `TreeChronicleService`

| | |
|---|---|
| **Файл** | `app/services/tree_chronicle_service.rb` |
| **Вхід** | `tree:` (Tree AR instance), `page:` (Integer, default: 1), `per_page:` (Integer, 1–100, default: 20) |
| **Що робить** | Агрегує «цифровий життєпис» дерева з 4 джерел: `AiInsight` (homeostasis / stress / fraud), `EwsAlert` (alert + recovery при resolved), `MaintenanceRecord`, `BlockchainTransaction` (status: confirmed). Об'єднує всі записи у єдиний масив `Entry` (Data.define), сортує за датою DESC, пагінує вручну через `Pagy::Offset` (без додаткових DB-запитів на весь масив). Ліміти: 50 insights, 30 alerts, 20 maintenance, 20 blockchain. Не потребує нових таблиць. |
| **Зовнішні виклики** | `TreeChronicle::TextFormatter` — генерує i18n-ready текстові шаблони |
| **Вихід** | `{ entries: Array<TreeChronicleService::Entry>, pagy: Pagy::Offset }`. Entry fields: `date, event_type, icon, title, description, severity, source_type, source_id`. |
| **Масштабування** | Кожна модель має індекси на `created_at + tree_id`. `per_page` обмежено 100. |

> 🔴 **Хроніка й `EwsAlert` говорять РІЗНИМИ словниками severity — і перекладати їх треба тут, на межі, де видно обидва.** Хроніка веде власний (`stable`/`info`/`warning`/`critical`), модель — інший (`low`/`medium`/`critical`). Доти сервіс вливав чуже значення сирим `to_sym`, і `:medium` не збігався з жодною гілкою → діставав ту саму дефолтну зелень, що й `:stable`: **тривога середньої тяжкості малювалась як «усе гаразд»**. Дім перекладу — явна тотальна мапа в сервісі (`ALERT_SEVERITY_TO_CHRONICLE` + `fetch` без зеленого дефолту), НЕ CSS-хелпер у компоненті: той знає лише ОДИН словник, тому фізично не може помітити, що прийшло чуже слово. Сторожа — спека, що ітерує реальні `EwsAlert.severities.keys`, тож нове значення enum'а її червонить. Узагальнення: **щойно два доми діляться назвою осі, але не її значеннями, мовчазний фолбек перетворює неспівпадіння на «нормальний» стан.**
>
> ⊕ **А для гілки `stress` severity вирішує не словник, а ПОРІГ — сирий `stress_index >= 0.8`, і це свідомо НЕ slash-поріг.** Сам slash-поріг (`AiInsight.slash_stress_threshold`) вживається в [`05_05 §3`](05_05_Slashing_and_Risk_Policy), а як DAO-параметр живе в реєстрі GOV.1 ([`05_06`](05_06_Governance_and_DAO)); тутешні `0.8` належать ширшій insurance/UI-шкалі, яку `AiInsight` тримає окремо від slash-осі свідомо ([`00_07`](00_07_Action_Plan_Tracker) SLASH-1 — spread `0.8`↔`0.83`). 🔴 **Тому дротувати цей поріг на DAO-значення було б дефектом, а не фіксом:** голос governance про РОЗМІР спалення почав би перефарбовувати картку дерева. Дзеркальний сайт тієї самої шкали — маркер мапи ([`04_04`](04_04_Phlex_UI_and_Tailwind), щабель `0.4`/`0.8`); обидва живуть сирими літералами, і саме тому вони названі тут — щоб наступний читач не прийняв їх за забутий хардкод slash-порога. ⊕ **І порогів у цій картці ДВА, з РІЗНИМИ предметами:** `0.3` вирішує, чи подія взагалі ПОТРАПИТЬ у хроніку, `0.8` — лише її `severity` всередині вже показаної. Тому нижній щабель мапи (`0.4`) дзеркалом `0.3` **не є**: там обидва пороги фарбують той самий маркер, тут перший керує видимістю, другий — тоном, і розходження `0.3`↔`0.4` легальне за побудовою, а не drift.

### `TreeChronicle::TextFormatter`

| | |
|---|---|
| **Файл** | `app/services/tree_chronicle/text_formatter.rb` |
| **Вхід** | Модельні об'єкти (AiInsight, EwsAlert, MaintenanceRecord, BlockchainTransaction) |
| **Що робить** | Централізує всі текстові шаблони хроніки. Методи: `homeostasis_title/description`, `stress_title/description`, `fraud_title/description`, `alert_icon/title/description`, `recovery_title/description`, `maintenance_title/description`, `blockchain_title/description` (ім'я несе НАПРЯМОК-агностичну назву свідомо — [ARCH.101]). |
| **i18n** | ✅ **Локалізовано ЦІЛКОМ (4 локалі), 2026-08-17.** Шаблони живуть у `trees.chronicle.templates.*` під єдиною scope-константою `TEMPLATE_SCOPE`; мітки доменних enum'ів беруться з ВЛАСНИХ домів і тут не дублюються — `alerts.types.<type>` через `ALERT_TYPE_SCOPE` (реюзає й `Alerts::Row`), `MaintenanceRecord.action_type_label`, `BlockchainTransaction.token_type_label` (той деривує ім'я з `ERC20(name, symbol)`, тож хроніка називає монету так, як контракт). 🔴 **Дві форми, куплені саме тут:** напрямок (спалено ⊥ намінтовано) — ДВА окремі ключі, а не булевий параметр (в іншій мові дієслово стоїть в іншому місці речення), а тривалість інциденту — **plural-БЛОК** (`count:`), бо `"day".pluralize(n)` давав англійське `-s` у кожній мові. Іконки лишаються Ruby-мапою `ALERT_ICONS` (гліфи locale-інваріантні; у YAML parity-гейт вимагав би 4 однакові копії кожного емодзі). Fail-open збережено (сире значення / `⚠`), тож повноту проти enum'а тримає **спека**, а не CI: `i18n-tasks` звіряє локаль з локаллю, ніколи з моделлю ([`04_04 §12.14`](04_04_Phlex_UI_and_Tailwind)). ⚠️ Хроніка будується в РЕНДЕР-ЧАС і не персиститься — локаль тут завжди локаль ГЛЯДАЧА; кешувати ці рядки поза запитом не можна. |
| **Вихід** | Рядки (String). |

---

## 🔗 4. Домен: Блокчейн — Polygon (Primary Chain)

### `BlockchainMintingService`

| | |
|---|---|
| **Файл** | `app/services/blockchain_minting_service.rb` |
| **Інтерфейс** | Два методи: `.call(id: Integer, telemetry_log: nil)` — одиночний мінтинг; `.call_batch(ids: Array<Integer>, telemetry_log: nil)` — пакетний мінтинг |
| **Вхід** | `.call`: `id` (Integer); `.call_batch`: `ids` (Array\<Integer>); `telemetry_log:` (опціонально, для oracle-driven flow) |
| **Що робить** | Пакетна емісія SCC/SFC на Polygon через `mint` або `batchMint`. Guard clauses: oracle-гілка `verified_by_iotex?` + `oracle_status_fulfilled?` (enum method) — Path 1; KYC-гейт = `wallet.kyc_approved_for_minting?` [KYC.1] — усі шляхи. **[BLOCKER-11 / S6.12]** Guards `verified_by_iotex?` + `oracle_status_fulfilled?` активні **лише** при `telemetry_log:` (oracle-driven flow Path 1). У tokenomics-flow Path 2 (`TokenomicsEvaluatorWorker → EvaluateTreeBatchWorker → wallet.lock_and_mint! → process_batch → call_batch(ids)` без `telemetry_log:`) ці перевірки **свідомо пропускаються** — `growth_points` вже зараховані через `Wallet#credit!` після AES-256-CBC decrypt + `valid_sensor_data?` у `TelemetryUnpackerService` (per-packet integrity perimeter). `wallet.kyc_approved_for_minting?` [KYC.1] — **єдиний обов'язковий guard для всіх шляхів** (статус БЕНЕФІЦІАРА адреси: власна → власний `hadron_kyc_status`, custodial → успадковує `organizations.hadron_kyc_status`). Non-approved → **per-tx SKIP (S2), НЕ raise**: гаманець виключається з батчу, tx лишається `:pending` (чекає KYC-верифікації), `locked_points` не звільняються, решта батчу мінтиться. Spec coverage: `spec/services/blockchain_minting_service_spec.rb` → context "tokenomics flow without telemetry_log [S6.12]". Cross-ref: [`05_02`](05_02_Proof_of_Growth_Pipeline#усі-шляхи-до-walletlock_and_mint-guard-inventory-doc7) — усі шляхи до `lock_and_mint!` (Guard Inventory, DOC.7). Dynamic Tax 2% при carbon_coin + недофінансований страховий пул (→ DAO Treasury) — **[DOC-T.89]** обидві половини умови питає One-Home предикат `taxing?(token_type)`, мемоїзований per-instance (два call-site'и — `build_batch_arrays` і `tax_rate:` архів-групування — інакше розійшлись би на межі 15-хв кеша балансу казни; дім умови — розділ Dynamic Tax у [`05_03`](05_03_Tokenomics_SCC_and_SFC)). `Kredis.lock(expires_in: MINT_LOCK_TTL)` проти race conditions. 🔴 **[ARCH.106] Тут доти стояло «120s покриває worst-case ≈ ~130s» — речення, що суперечить собі в межах дужки**, і воно ж було третім домом того числа (код · пін спеки · цей рядок). Лок авто-релізний, тож TTL, менший за найдовший легальний прохід (dry-run + binary-search до 6 рівнів + fallback individual mints ≈ 130 с), відпускав підписанта, поки холдер ще працює — тобто повертав double-mint, заради якого його й підіймали з 30 с. Число тепер **константа, що перекриває розрахунок**, і пінується двома прикладами: на ідентичність та окремо на ВЕЛИЧИНУ проти задокументованих 130 с. `transact` (fire-and-forget). Prometheus metric `SCC_MINTED_TOTAL`. **[ARCH.62]** per-token inert circuit-break: `mint_circuit_broken?(token_type)` читає Kredis `mint:circuit_broken:<token>` (ставить `Treasury::MonitorService` при volume-аномалії за `:mint_circuit_breaker_enabled`, default off); tripped → HOLD цього token'а у `:pending` (re-runnable наступним циклом, **НЕ** escalate — чистий never-broadcast tx не осиротюється); fail-open на Redis-збої (money liveness > optional stop-loss). **[B-05]** `insurance_pool_requires_funding?` — on-chain `balanceOf` через `Web3::Erc20Reader`: `INSURANCE_POOL_THRESHOLD = 100_000 SCC`; кеш 15 хв (ключ `dao_treasury_balance_wei` — **[One-Home]** спільний з `Insurance::ReserveGate` → 1 RPC/вікно на обидві фічі); timeout 10 сек; failsafe → `false` при збої RPC ([E.46]: не штрафуємо мінтинг під час деградації — false-negative безпечніший за постійний 2%). **[INF.22]** Перед мінтом перевіряється баланс MATIC oracle-гаманця (`get_balance`): поріг `oracle_min_balance_matic` (SystemParameter, default 0.05, governance-aware, 24h cache) — недостатній баланс → raise зупиняє весь батч до поповнення. **[DRY-RUN GUARD]** Перед кожним `batchMint` виконується `eth_call` симуляція (`batch_dry_run_reverts?`) — zero-gas виконання на поточному блоці. Якщо симуляція повертає EVM revert (ознаки: `"revert"`, `"execution reverted"`, `"out of gas"`), активується **Binary Search Poisoned Record Isolation** (Divide & Conquer): замість наївного fallback на N×`mint()`, алгоритм розбиває батч навпіл і тестує кожну половину через `eth_call` dry-run. "Чисті" половини відправляються через `batchMint`, "отруйні" — далі діляться рекурсивно до `MIN_BINARY_SEARCH_SIZE=4` або `MAX_BINARY_SEARCH_DEPTH=6`. Результат: для типового сценарію (1-2 отруйних з 100) ~14 `eth_call` + 2-3 `batchMint` замість 100 `mint()`. `POISONED_RATIO_THRESHOLD=0.3` — при >30% отруйних binary search неефективний → fallback на індивідуальні mints. `send_clean_batch` відправляє чисті підбатчі через `batchMint` з fallback на `mint_individual` при збої transact. Мережеві помилки (RPC timeout) не рахуються як revert — оптимістичний фолбек на `transact`. **[E.60 Фаза 1б]** transact-цикл іде **per-archive_batch-підгрупою** («один on-chain виклик = один root»): `mint`/`batchMint` 4-арг (+`bytes32 archiveRoot`, симетрично SCC/SFC — один ABI); батчі будує `Mrv::TelemetryArchiveBatchService` у `process_token_group` ПІСЛЯ KYC/SEC.13/circuit-фільтрів, ПОЗА Kredis-локом; bisect/clean/individual — У МЕЖАХ підгрупи, всі несуть її root (N:1). Rescue живе ПЕР-ПІДГРУПОЮ (збій пізньої групи не чіпає вже-`:sent` ранню; safe_fail re-raise'иться ПІСЛЯ проходу всіх груп → retry перемінчує лише failed); **dispatchable-фільтр** виключає `:sent`/`:manual_review` tx ПЕРЕД флипом у `:processing` (double-mint guard на retry). Семантика — One-Home [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline). |
| **Зовнішні виклики** | Polygon RPC (`ALCHEMY_POLYGON_RPC_URL`), `Web3::RpcConnectionPool`, `Web3::WeiConverter`, `BlockchainConfirmationWorker.perform_in` |
| **Вихід** | `tx_hash` (String). Оновлює `BlockchainTransaction.status = :sent`. Turbo Stream broadcast балансу гаманця. |

### `BlockchainBurningService`

| | |
|---|---|
| **Файл** | `app/services/blockchain_burning_service.rb` |
| **Вхід** | `organization_id`, `naas_contract_id`, `source_tree:` (опц.), `contractual:` (опц.), `target_date:` (опц. Date — прокидається з `ContractHealthCheckService` через `BurnCarbonTokensWorker`; nil → `AiInsight.reporting_date` [ARCH.100]), **`stress_threshold:` · `slash_gamma:` · `penalty_factor_max:`** (опц. — право ПОДІЇ, не право ВИКОНАННЯ [E.67]) |
| **One-Home права вироку** | `BlockchainBurningService.frozen_verdict_law(stress_threshold:)` — ЄДИНИЙ писач знімка: читає `slash_gamma`/`slash_penalty_factor_max` із `SystemParameter` у мить рішення й віддає хеш зі СТРІНГОВИМИ ключами. 🔴 Підстава не косметична: між рішенням і виконанням лежить черга, тож DAO-голосування в цьому вікні судило б подію законом, ухваленим ПІСЛЯ неї. `nil` у будь-якому полі → сервіс падає назад на поточні значення (шлях ре-enqueue старих джоб) |
| **Що робить** | Slashing Protocol. Розраховує `damage_ratio` через `AiInsight` (частка дерев зі `stress_index ≥ effective_stress_threshold` — **той самий поріг, що ТРИГЕРИВ** слеш у health-check, і саме той, а не перечитаний DAO-live у момент виконання: [SLASH-1, 2026-08-25] тригер ФІКСУЄ поріг і передає його kwarg'ом `stress_threshold:` поруч із `target_date`. Доти ARCH.46 звів обидві половини вироку на одну ДОБУ, лишивши їм два різні МОМЕНТИ читання, тож голос governance чи межа 24-год TTL між диспатчем і виконанням розводили тригер із розміром — напрямок асиметричний: поріг ЗНИЖЕНО у вікні → burn більший за підставу, на якій тригер спрацював. `nil` → сервіс читає DAO-live сам, бо tree-death/dClimate/contractual розміру з вибірки не питають; GOV.1). **[ARCH.46]** genuine no-data (нема AiInsight за `target_date`) → `:frozen` (freeze, НЕ breach/burn), а не worst-case 100%; `target_date` прокинутий від health-check (без перерахунку доби у свій момент → інакше інша доба → хибне 100%); `contractual`-форфейтура — виняток (повне погоджене вилучення). Викликає `slashUpTo(investor_address, amount_wei, contextHash)` на Polygon ([SLASH.2] atomic clamp; pre-read `balanceOf` → `escalate_evasion!` на порожньому балансі). Маркує `NaasContract.status = :breached`. **[ARCH.45]** durable intent-marker (`BlockchainTransaction` `:pending`→`:sent`, `sourceable:` contract) ПЕРЕД on-chain slash + `unsettled_within(2h; :manual_review — age-unbounded)` guard ПІСЛЯ positive-A gate (`:sent` → не re-slash; `:pending` → старий intent у `:failed`) — закриває double-burn crash-window. **[ARCH.53 TOCTOU]** guard-читання і transact-вікно серіалізує per-contract non-blocking **`Kredis.lock`-claim** (`slash:claim:{id}`, TTL 2min; Redis SET NX + UUID-токен + Lua-CAS-release — безумовний delete після TTL-експірі знімав би чужий claim; конфлікт → `Kredis::LockTimeout` поза step-3 rescue → чистий Sidekiq-retry, який бачить інтент переможця) — дві істинно-конкурентні екзекуції більше не проходять guard одночасно. Відкинуті субстрати: партиційний partial-UNIQUE неможливий (`PARTITION BY RANGE(created_at)` вимагає partition-key в unique); `Rails.cache` = SolidCache у prod — `unless_exist` там НЕ атомарний для неіснуючого рядка (`SELECT FOR UPDATE` не лочить відсутнє → обидва конкуренти acquire); `unique_for` = Enterprise-шим (DOC-R.10, дозакупити перед mainnet — позначено коментарем на воркері). **[SLASH-1 gap-D]** freeze піднімає `EwsAlert(:field_audit)` (не `:system_fault`); `comms_no_ack?`/`critical_unmaintained?` виключають `:field_audit` → freeze більше не самонакручує `penalty_factor`. **[ARCH.57]** кожен вердикт → audit-ланцюг організації (`slash_verdict_burn` з damage/slash-ratio + contractual-vs-positive-A · `slash_verdict_frozen` з reason · `slash_verdict_evasion`; **chain-only** — fraud-attribution/DID/пороги не пінити на публічний IPFS; ПРИЧИНА вироку, рух коштів докладає MRV.1). Prometheus: `SCC_SLASHED_TOTAL` + `SLASH_ATTEMPTS/SUCCESS_TOTAL` (success-rate SLO). |
| **Зовнішні виклики** | Polygon RPC, `BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash, created_at_iso)` ([ARCH.52] created_at прокинуто для partition-prune), `EwsAlert.create!` (при помилці) |
| **Вихід** | `:slashed` / `:frozen` (positive-A gate АБО no-data magnitude [ARCH.46], no burn) / `nil` (no-op або healthy-data 0-damage). Створює `BlockchainTransaction` intent (audit, `:pending`→`:sent`); **[ARCH.48]** rescue розрізняє: `LockTimeout`→intent `:failed`, контракт `:active`, retry re-slash; помилка `transact` (broadcast невідомий)→`escalate_to_review!` (`:manual_review`, in-flight guard блокує blind re-slash проти double-burn); крах після broadcast (`:sent`)→`:breached`. `:breached` ≡ slash-broadcast. Можливі outcome: `:slashed`/`:frozen`/`:manual_review`/`nil`. |

### `ChainAuditService`

| | |
|---|---|
| **Файл** | `app/services/chain_audit_service.rb` |
| **Вхід** | — (no args) |
| **Що робить** | Аудит on-chain: порівнює суму підтверджених SCC у Postgres з `totalSupply` смарт-контракту на Polygon. Кеш 5 хвилин. Timeout 10 сек на RPC. |
| **Вихід** | `ChainAuditService::Result` (Struct): `{ db_total, chain_total, delta, critical: Boolean, checked_at }`. |

### `MintingRollbackService`

| | |
|---|---|
| **Файл** | `app/services/minting_rollback_service.rb` |
| **Вхід** | `telemetry_log_id:`, `created_at_iso:` або `transactions:` (AR relation) |
| **Що робить** | **[DOUBLE-SPEND GUARD]** Rollback при вичерпанні всіх Sidekiq-ретраїв у `MintCarbonCoinWorker`. Логіка вирішення: (1) `tx_hash` відсутній → безпечний rollback (транзакція не покинула бекенд): розблоковує `locked_balance`, маркує `status = :failed`; (2) `tx_hash` існує → перевіряє стан on-chain через RPC: а) receipt підтверджено → `tx.confirm!` (НЕ rollback); б) receipt null (pending) → `escalate_to_review!` (кошти залишаються заблокованими); в) RPC timeout → `escalate_to_review!`. Multichain: EVM-мережі використовують `eth_getTransactionReceipt`; Solana — `getTransaction` через прямий HTTP-запит. **[BUGFIX 2026-05-18 envelope-aware]** `fetch_evm_transaction_receipt` делегує до спільного **[ARCH.50]** `Web3::EvmReceiptClassifier.classify(envelope)` (One-Home tri-state classifier — той самий дім, що й `CeloConfirmationWorker`; витягнутий із колишнього приватного `classify_evm_receipt` заради DRY), який приймає або wrapped JSON-RPC відповідь (`{"id":…, "result": {"status":"0x1"}}`, реальний eth gem 0.5.x) або flat shape (`{"status":"0x1"}`, легасі-фікстура). Раніше код читав `receipt["status"]` напряму на envelope-формі, де статус живе під `result.status`, тому ВСЯ продакшн-телеметрія класифікувалась як `:reverted` → safe rollback розблоковував кошти навіть для confirmed on-chain mint'ів (точно та double-spend дірка, яку сервіс мав закривати). Тепер: `nil`/`{}` envelope → `:pending`; `result` null/empty → `:pending`; `status` ∈ {"0x1", "0x01", 1} → `:confirmed`; `status == nil` → `:pending`; інше → `:reverted`. **[E.49]** Per-chain fallback cascade: для Polygon — `fallback: "https://polygon-rpc.com"` + `fallback_env_keys: ["INFURA_POLYGON_RPC_URL"]`; для Celo — `fallback: Celo::CommunityRewardService::DEFAULT_RPC_URL` + `fallback_env_keys: Celo::CommunityRewardService::RPC_FALLBACK_ENV_KEYS` (раніше fallback для Celo вказував на polygon-rpc.com — баг виправлено). |
| **Вихід** | `nil`. Side effects: `wallet.release_locked_funds!` + `tx.update!(status: :failed)` (при safe rollback); або `tx.escalate_to_review!(reason)` (при manual_review). **[ARCH.67]** Трансляції балансу сервіс НЕ робить сам — її несе `after_update_commit :broadcast_status_change` на `BlockchainTransaction`, який файрить і на сирий `update!` вище (`status_failed?` → `wallet.broadcast_balance_update`). Власний виклик тут дублював би її, а успадкований Turbo-дефолт `broadcast_update` ще й кидав `MissingTemplate`, обриваючи `txs.each` → див. [`04_04 §8.1`](04_04_Phlex_UI_and_Tailwind). |

### `PuroEarth::PassportService`

| | |
|---|---|
| **Файл** | `app/services/puro_earth/passport_service.rb` |
| **Вхід** | `payload` (Hash: `tree_did`, `biomass_yield_kg`, `extraction_date`, `gps_coordinates`, `lifetime_telemetry_hash`) |
| **Що робить** | **[MAINNET READY]** Anchors a cryptographic proof of a Biomass Passport onto Polygon for Puro.earth D-MRV (Digital Measurement, Reporting and Verification) / CORC generation. 1) Витягує поля payload у фіксованому алфавітному порядку через `extract_canonical_fields` — рекурсивний обхід хешу з явним ABI-типізуванням (`"string"`, `"uint256"`). Float/BigDecimal масштабуються на `ABI_DECIMAL_SCALE = 10^18` і перетворюються в `uint256` для збереження точності. 2) Кодує поля через `Eth::Abi.encode(types, values)` — бінарне кодування, визначене специфікацією EVM, крос-платформне та мово-незалежне (усуває артефакти Ruby JSON: float-форматування, unicode-екранування, порядок ключів). 3) Обчислює SHA-256 від ABI-кодованого бінарного blob. 4) Викликає `anchorPassport(treeDid, bytes32(payloadHash))` на D-MRV Registry смарт-контракті Polygon через `Web3::RpcConnectionPool` + `Eth::Contract`. Підпис через dedicated `ORACLE_PURO_PRIVATE_KEY` (activation-gated; легасі спільний ключ retired — INF.22). **[ARCH.49]** `transact` обгорнуто у `Kredis.lock("lock:web3:oracle:#{addr}")` (per-address nonce-serialization — після dedicated-спліту lock серіалізує лише Puro-конкуренцію; `LockTimeout` re-raise крізь `anchor!` перед `StandardError` → чистий Sidekiq-retry, не `AnchoringError`). Метод `deep_sort_keys` збережено для зворотної сумісності. |
| **Зовнішні виклики** | Polygon RPC (`ALCHEMY_POLYGON_RPC_URL`), `PURO_EARTH_REGISTRY_CONTRACT_ADDRESS` (D-MRV Registry), `ORACLE_PURO_PRIVATE_KEY` |
| **Вихід** | `tx_hash` (String, `"0x..."`). Raises `PuroEarth::PassportService::AnchoringError` on RPC failure, insufficient gas, or contract revert. |

### `PuroEarth::RegistryApiService`

| | |
|---|---|
| **Файл** | `app/services/puro_earth/registry_api_service.rb` |
| **Вхід** | `payload` (Hash: той самий D-MRV passport payload), `tx_hash:` (String: on-chain anchoring TX hash) |
| **Що робить** | **[MAINNET READY]** Submits Biomass Passport data to the Puro.earth REST API for CORC (CO₂ Removal Certificate) issuance. Constructs D-MRV submission body including passport data, on-chain proof (`tx_hash`, `network: "polygon"`, `contract` address), and source metadata (`source: "silkennet"`, `methodology: "biochar-corc"`). Uses `Web3::HttpClient` (HTTPX) for HTTP POST to `/v1/dmrv/submissions`. Bearer token auth from Rails credentials (`credentials.puro_earth.api_key`) or ENV fallback (`PURO_EARTH_API_KEY`). Parses response for `corc_ref` or `submission_id`. |
| **Зовнішні виклики** | Puro.earth REST API (`PURO_EARTH_API_URL`, default: `https://api.puro.earth`), `PURO_EARTH_API_KEY` або `Rails.credentials.puro_earth.api_key` |
| **Вихід** | `corc_ref` (String, e.g., `"CORC-2026-XXXXXXXX"`). Raises `PuroEarth::RegistryApiService::SubmissionError` on API failure, auth error, or missing CORC reference. |

### `Etherisc::ClaimService`

| | |
|---|---|
| **Файл** | `app/services/etherisc/claim_service.rb` |
| **Вхід** | `insurance` (ParametricInsurance AR instance) |
| **Що робить** | Oracle-mode виплата через Etherisc DIP на Polygon. Викликає `triggerClaim(policyId)`. Виплата в USDC з децентралізованого пулу (усуває інфляційний тиск на SCC). **[ARCH.45]** `triggerClaim` НЕ idempotent на нашому боці → `InsurancePayoutWorker` ескалює orphaned `:pending` recovery-tx у `manual_review` (не сліпий re-claim) проти double-pay; точніша on-chain DIP claim-status звірка — майбутнє (`getClaim` ABI). **[ARCH.49]** `transact` обгорнуто у спільний `Kredis.lock("lock:web3:oracle:#{addr}")` (nonce-serialization base-EOA; `LockTimeout` пробрасується для Sidekiq-retry — нема StandardError-перехопу). |
| **Зовнішні виклики** | Polygon RPC, `ETHERISC_DIP_CONTRACT_ADDRESS` |
| **Вихід** | `tx_hash` (String). |

---

## 🛡️ 5. Домен: Верифікація та Ідентичність (Verification & Identity)

### `Gdpr::DataExportService` [SEC.18 — DSAR Art.15/20]

| | |
|---|---|
| **Файл** | `app/services/gdpr/data_export_service.rb` |
| **Вхід** | `user` (User AR instance — субʼєкт запиту) |
| **Що робить** | Збирає структурований машиночитний зліпок User-owned персональних даних за PII-реєстром ([`04_01 §11`](04_01_Data_Models_and_Entities)): рядок users · sessions (слід входу) · audit_logs де субʼєкт є актором · maintenance_records авторства з МЕТАДАНИМИ фото (байти блобів не вбудовуються — оригінали доступні штатним авторизованим шляхом). Креденшели (password_digest · otp_secret · recovery_codes) свідомо поза віддачею — DSAR віддає дані ПРО особу, не секрети автентифікації. Schema-parity приклад у власній спеці червонить нову PII-колонку users, доки вона не дістане рішення про експорт |
| **Виклик** | `GET /account_security/data_export` (JSON-attachment), **двері — секція «Ваші дані» на сторінці безпеки акаунту** (`AccountSecurity::Show#render_data_export_section`). ⚠️ Маршрут жив із 2026-08-20 при НУЛІ посилань у `app/views/` — тобто субʼєкт міг дістатись лише прямим URL; двері задротовано 2026-08-21, бо «сервіс відвантажено» ⊥ «людина може ним скористатись» є різними твердженнями саме на комплаєнс-поверхні (Art.12 self-service не вимагає, але від нього залежить, скільки місячного строку зʼїдає ручна робота). 🔴 Контрол — `a`, а НЕ `button_to`: екшен ідемпотентний GET, і форма оголосила б мутацію, якої немає; пін стереже саме цю вісь, бо правило UI.7 дає природний мотив «полагодити» посилання у форму. Процедура й годинник → [`gdpr_runbook.md`](protocols/legal/gdpr_runbook.md) |
| **Вихід** | `Hash` (format_version + секції); контролер віддає `send_data` файлом |

### `Gdpr::AnonymizeUserService` [SEC.18 — erasure Art.17, безсуперечна половина]

| | |
|---|---|
| **Файл** | `app/services/gdpr/anonymize_user_service.rb` |
| **Вхід** | `user` (субʼєкт) · `actor:` (ініціатор; дефолт — сам субʼєкт) |
| **Що робить** | Атомарно: синхронний `AuditLog.create!` ПЕРЕД мутаціями (слід незворотного акту без жодного PII в metadata) → `sessions.destroy_all` → tombstone users-рядка (email → `erased-{id}@anonymized.invalid`, решта PII → nil, digest/OTP зняті). Після цього вхід неможливий за побудовою — анонімізація Є ефективним offboarding-ом без окремого механізму деактивації. 🔒 Стелі оголошені в докблоці й у [`04_01 §11`](04_01_Data_Models_and_Entities): audit_logs (ip/user_agent у chain_payload — псевдонімізація вимагає ⚖️ про форму) і maintenance_records (Evidence Protocol) свідомо НЕ чіпаються; спека пінить, що ланцюг переживає анонімізацію цілим |
| **Виклик** | ✅ **Self-service з 2026-08-21** (⚖️ founder): `DELETE /account_security/erase` → `AccountSecurityController#erase_account`, запобіжник — **step-up на пароль** (той самий зразок, що `toggle_mfa` disable). Плюс оператор через консоль. 🔴 **Гард fail-CLOSED, і розходження з `toggle_mfa` НАВМИСНЕ:** там відсутність пароля step-up МИНАЄ (дія оборотна, вимагати доказу нічим), тут — **відмова**, бо акт незворотний. Дискримінатор — ОБОРОТНІСТЬ дії, ніколи «однаковий вигляд коду»: обидві форми різняться одним символом, тож наступний прохід спокушається «уніфікувати» їх як дубль. ⚠️ Акаунта без `password_digest` у дереві не буває за побудовою (валідація безумовна, а `AnonymizeUserService` тим самим записом ставить tombstone-пошту), тож обидві гілки без пароля — недосяжні запобіжники, а не покриття наявного стану. Людський DSAR-шлях лишається загальним, не «для таких акаунтів» — [`gdpr_runbook.md`](protocols/legal/gdpr_runbook.md) §2 (строк Art.12(3), ідентифікація, реєстр запитів) |
| **Вихід** | `user` (анонімізований) |

### `Web3::TransactionErrorClassifier` [SEC.18 — DPIA захід M6, друга стеля]

| | |
|---|---|
| **Файл** | `app/services/web3/transaction_error_classifier.rb` |
| **Вхід** | `message` — сирий `BlockchainTransaction#error_message` (або `nil`) |
| **Що робить** | Мапить вільний текст у **скінченну множину кодів** і НІКОЛИ не повертає фрагмент входу. Порожньо → `:none`; впізнане → код із `RULES`; **усе інше → `:unknown`**. Єдиний споживач — `BlockchainTransaction#record_money_audit_trail`, який кладе КОД у `AuditLog.metadata[:error]`, тобто в рядок, що їде в **незворотний публічний IPFS-пін** (`Filecoin::ArchiveService`). Потреба не гіпотетична: `error_message` заповнюється `e.message` довільного винятку — чужим RPC-тілом, URL із креденшелом, текстом Kredis. **Порядок правил несучий:** `broadcast_ambiguous` стоїть ПЕРШИМ, бо це double-spend-лімбо (кошти заблоковані, стан на ланцюгу невідомий), і сплутати його з простим `evm_revert` означало б занизити тяжкість найдорожчого стану money-path. |
| **Вихід** | `Symbol` — рівно один із `RULES` ∪ `{:none, :unknown}` |
| **⚖️ Чому класифікація, а не truncate/redaction** | Присуд 2026-08-27 (делеговано founder'ом). Дискримінатор — **напрямок дефолту на незворотній поверхні**: `truncate` ріже довжину, не природу (і він там уже стояв); redaction за патернами **fail-OPEN за побудовою** — що не збіглося з патерном, те їде; класифікація єдина **fail-CLOSED**. Прецеденти тієї ж форми: `Web3::EvmReceiptClassifier` (невідомий status → `:reverted`) і `InsurancePayoutWorker` (`message_key` від машинного символу замість готового англійського речення чужого сервісу). 🔴 Звужено на **ПИСАЧІ**, не на межі піна: пін мусить бути ВІРНОЮ копією аудит-рядка, інакше він перестає бути доказом. Повний текст лишається в `blockchain_transactions.error_message` під retention/erasure — діагностику переадресовано, не втрачено. ⚠️ Стеля: код каже «якого РОДУ відмова», ніколи «що саме сталось». Дім переліку ключів піна — [`04_01 §11`](04_01_Data_Models_and_Entities) |

### `Iotex::W3bstreamVerificationService`

| | |
|---|---|
| **Файл** | `app/services/iotex/w3bstream_verification_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | Відправляє телеметрію до IoTeX W3bstream для генерації ZK-proof. Payload: `device_id`, `peaq_did`, `hardware_signature`, `chaotic_data` (z_value, temp, acoustic, voltage, bio_status). **[BLOCKER-06]** `hardware_signature` = Ed25519-підпис payload'у; seed = `HardwareKeyService.derive_iotex_seed(tree.did)` (HKDF з master — **не** `binary_key`: post-ARCH.42 Tree AES=16B недосить для Ed25519) над `message = "#{tree.did}:#{log.id_value}:#{log.created_at.to_i}"`. **Чесно:** seed деривує backend (master-holder) → підпис доводить **цілісність pipeline + DID-binding**, а НЕ криптопоходження «саме цей STM32» (custodial). Device-bound origin = true-DePIN ladder ([`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)). **[S6.13] Fallback-режим:** при відсутності `HardwareKey` (legacy/dev, TRL ≤ 5) сервіс інкрементує `silkennet_w3bstream_signature_fallback_total{reason}` counter. У production OR `WEB3_STRICT_MODE=true` fallback **fail-closed** — raise `VerificationError` без виклику W3bstream (SHA256-хеш доступний будь-кому хто знає `tree.did`, тому не еквівалентний Ed25519). У dev/test без strict-mode — warn-log + SHA256 fallback (для лабораторних benches без provisioned ключів). Шлях відновлення продакшн-deploy після alert: `POST /provisioning/register` для дерева, що тригернуло fallback. **[BLOCKER-07]** Валідація формату `zk_proof_ref` через regex: `/\A[0-9a-zA-Z\-_]{8,128}\z/` — захист від injection довільних рядків. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `iotex_w3bstream_url/verify` |
| **Вихід** | `zk_proof_ref` (String — `proof_id` або `receipt_id`). Raises `VerificationError` при помилці. |

### `Peaq::DidRegistryService`

| | |
|---|---|
| **Файл** | `app/services/peaq/did_registry_service.rb` |
| **Вхід** | `tree` (Tree AR instance) |
| **Що робить** | Генерує peaq DID: `did:peaq:0x{SHA256[tree.did:tree.id:created_at][0:40]}`. **[BLOCKER-08]** `peaq_signing_key` обов'язковий (W3C DID Core compliance). Підписує DID-документ Ed25519 та додає `proof: { type: "Ed25519Signature2020", verification_method, signature, public_key }` до payload. Raises `RegistrationError` при відсутності `peaq_signing_key`. |
| **Зовнішні виклики** | `Ed25519Crypto::SigningService.sign`, `Web3::HttpClient.post` → `peaq_node_url/did/register` |
| **Вихід** | `did_string` (String, напр. `did:peaq:0x8a9b...`). Raises `RegistrationError`. |

#### S6.14 — Key Rotation Policy for `peaq_signing_key`

`peaq_signing_key` — Ed25519 seed (32 bytes hex) що зберігається в Rails encrypted credentials. Використовується виключно в `Peaq::DidRegistryService` для підпису W3C DID-документів при реєстрації дерев на peaq network. Компрометація цього ключа дозволяє зловмиснику реєструвати фейкові DIDs від імені платформи.

**1. Overlap Window (Dual-Key Grace Period)**

При ротації ключа необхідно забезпечити безперервність реєстрації:

1. Згенерувати новий Ed25519 keypair: `ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"`
2. В credentials зберігати ОБА ключі:
   - `peaq_signing_key` — новий ключ (використовується для всіх нових реєстрацій)
   - `peaq_signing_key_previous` — старий ключ (**rollback-safety**; код його НЕ читає — це ручний відкат, якщо новий ключ дав збій)
3. Нові реєстрації одразу підписуються новим `peaq_signing_key`; старі DID лишаються валідними самі по собі (Migration Strategy нижче). **72-годинне вікно** — час на безпечний відкат, а не «прийом обох ключів»: бекенд лише **підписує**, верифікацію peaq-підписів робить мережа peaq, не наш код
4. Після закінчення overlap window: видалити `peaq_signing_key_previous` з credentials

**2. Migration Strategy**

- Усі нові DID реєстрації під час overlap використовують **новий** ключ
- Існуючі DIDs зберігають оригінальні підписи (immutable on peaq chain)
- Повторна реєстрація **НЕ** потрібна — DID-документи є append-only на peaq
- Старі DID лишаються валідними бо кожне дерево має **власний імутабельний DID-документ** на peaq (його `#key-1` тримає pubkey саме тієї реєстрації) — **НЕ** через #key-N версіонування. ⚠️ **Код-стан:** `Peaq::DidRegistryService` емітить `verification_method = <tree_did>#key-1` (хардкод; для НОВИХ реєстрацій коректно — кожне дерево незалежне). Єдиний випадок, де знадобився б свіжий key-id (`#key-2`) — **повторна** реєстрація вже-існуючого DID новим ключем (recovery-крок [`06_04 §5.4`](06_04_Secrets_Checklist)), який наразі не автоматизований у коді

**3. Scheduled Rotation**

| Тригер | Інтервал |
|--------|----------|
| Планова ротація | Кожні **90 днів** |
| Зміна персоналу | Негайно (при звільненні/зміні ролі інженера з доступом до credentials) |
| Підозра на компрометацію | Негайно (див. Emergency Revocation Runbook у [`06_04 §5.4`](06_04_Secrets_Checklist)) |

**4. Credentials Layout (після ротації)**

```yaml
# config/credentials.yml.enc (decrypted view)
peaq_signing_key: "new_key_hex_64_chars"
peaq_signing_key_previous: "old_key_hex_64_chars"  # видалити через 72 години
peaq_node_url: "https://peaq-node.example.com"
```

> **Зв'язок:** Emergency Revocation Runbook → [`06_04 §5.4`](06_04_Secrets_Checklist)

### `Mrv::TelemetryLeaf` [ARCH.12/E.60]

| | |
|---|---|
| **Файл** | `app/services/mrv/telemetry_leaf.rb` |
| **Вхід** | `log` (TelemetryLog AR instance) |
| **Що робить** | Код-дім canonical leaf-формули Merkle-дерев (leaf-контент канонізовано у [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline)): будує **пінений** payload `{telemetry_log_id, device_uid = tree.did (attr_readonly — лист не «переїжджає»), z_value = BigDecimal#to_s("F") (plain fixed-point, НЕ scientific; NULL → JSON null — рядок ніколи не виключається з дерева), bio_status = сирий enum-integer (rename-proof), created_at = utc.iso8601(6)}` → `Filecoin::CidGenerator.cidv1`. `LEAF_VERSION = 1`: зміна формули = bump (historical-верифікація за версією). Споживачі: тижневий Eth-L1 `state_root` (ARCH.12 Фаза 1а), mint-lineage вікна (MRV.1), Polygon `archive_root` (E.60 Фаза 1б — `Mrv::TelemetryArchiveBatchService`). Golden-vector spec пінить CID. |
| **Зовнішні виклики** | — (pure; лише `Filecoin::CidGenerator`) |
| **Вихід** | `payload_for(log)` → Hash · `cid_for(log)` → CIDv1 String (`bafkrei…`) |

### `Mrv::LineageWindow` [MRV.1]

| | |
|---|---|
| **Файл** | `app/services/mrv/lineage_window.rb` |
| **Вхід** | `tx` (BlockchainTransaction з lineage-вікном) |
| **Що робить** | One-Home запиту «логи вікна tx»: tuple-діапазон `(from_at, from_id) < (created_at, id) <= (to_at, to_id)` по логах дерева гаманця — суміжні вікна не перетинаються і не лишають дір; порожнє вікно (from == to або to NULL) = нуль рядків. Юзають fail-open обчислення кореня при мінті (`Wallet#attach_lineage_root`) і lineage-bundle (аудиторський перерахунок). `root_for(tx)` = `MerkleTree.root` над leaf-CID'ами вікна (nil для порожнього). GRACE-лаг меж = `Mrv::WINDOW_GRACE` (One-Home константи, спільна з тижневим якорем). |
| **Зовнішні виклики** | — (pure AR-запит + `MerkleTree`/`Mrv::TelemetryLeaf`) |
| **Вихід** | `logs_for(tx)` → AR-relation (ordered) · `root_for(tx)` → 64-hex String \| nil |

### `Mrv::LineageReportService` [MRV.1/ARCH.12 — перший inclusion-proof-споживач]

| | |
|---|---|
| **Файл** | `app/services/mrv/lineage_report_service.rb` |
| **Вхід** | `organization:, from:, to:` |
| **Що робить** | ISO lineage-bundle `silken.mrv.lineage.v1` (founder-присуд 2026-07-19): для кожного confirmed-**мінту** організації (org-scoping через cluster-ланцюг, created_at = partition-pruning) — 🔴 **і слово «мінт» тут ФІЛЬТР, а не опис [ARCH.101]:** напрямок читається з колонки `direction` тим самим дискримінатором, що в `net_minted_supply` ([ARCH.95]; доти це була деривація через `BURN_SOURCEABLE_TYPE` + `IS DISTINCT FROM`, і вона за побудовою НЕ бачила ESG-погашення — те `sourceable` не має, тож ішло б у `credits:` емісією). Доти рядок відбирав лише за `token_type`+`status`, тож слеш-інтент (теж `carbon_coin`, теж `:confirmed`, сума ДОДАТНА) потрапляв у ключ `credits:` зовнішнього ISO 14064/Verra-бандла як виданий кредит; носій — пара «мінт лишається ⊥ спалення відпадає» у спеці сервісу, mutation-verified обабіч — вікно вимірів + canonical-payload'и листя + двоярусні inclusion-proof'и до якорених `state_root` (covering-lookup = найранішій confirmed v1-якір; tier2-шлях зі збережених `subtree_roots` O(#кластерів), tier1 = report-time перевибірка кластерного вікна) + референси якоря (etherscan). Чесні статуси — ЧОТИРИ [ARCH.70 ⚖️ 2026-08-29]: `anchored` / `pending_anchor` (лист новіший за останній якір) / `subroot_diverged` (субкорінь кластера в якорі ≠ перерахованому) / `unprovable_regrouped` (субкорінь збігся, а листа в складі немає). ⛔ Останні два називають НАСЛІДОК, не причину — див. стелю нижче. Failed-спроби успадковуються в наступний успішний кредит («чесна межа (г)»); covering-якорі й кластерні leaf-list'и мемоїзуються per-виклик (без мемо — O(листя × вікно)). Продюсер: rake `mrv:lineage_bundle[org_id,from,to]`. **Споживач пруфів = `scripts/verify_lineage_bundle.rb`** (pure Ruby, офлайн, без Rails/БД/мережі: leaf-CID recompute + did-binding + **mint-root sealed-кредитів** + tier1-субкорінь recompute + tier2 → state_root; JSON dup-key reject — двошарово: нативний `allow_duplicate_key: false` json≥2.20 + StrictHash-fallback для старших (C-парсер ≥2.20 дедуплікує ДО object_class); sealed/unsealed-лічильники з ⚠️ на unsealed; exit 1 на будь-який crypto-mismatch). **Trust-boundary задекларована в самому bundle** (анти-overclaim): issuer-asserted = amount/повнота набору/континуїтет вікон (backstop = AuditLog-ланцюг у leaf0); on-chain звірку кореня робить людина — tx мусить таргетити `anchor_contract`, адреса звіряється з НЕЗАЛЕЖНИМ джерелом, не з файлу. HTTP-ендпоінт deferred (YAGNI — реальний споживач офлайновий). |
| **Зовнішні виклики** | — (чисті AR-запити + `MerkleTree`/`Mrv::TelemetryLeaf`/`Mrv::LineageWindow`) |
| **Вихід** | Hash-bundle (серіалізовний у JSON) |

🔴 **Три стани під одним іменем — РОЗЧЕПЛЕНО ⚖️ 2026-08-29 [ARCH.70], але з оголошеною стелею.** Доти `unprovable_regrouped` віддавався і тоді, коли субкорінь кластера розійшовся з якорем, і тоді, коли листа немає в складі — тобто зовнішній аудитор діставав ПРИЧИНУ («дерево змінило кластер») там, де ми знаємо лише НАСЛІДОК. Тепер два факти: **`subroot_diverged`** (субкорінь у якорі ≠ перерахованому) ⊥ **`unprovable_regrouped`** (субкорінь збігся, листа в складі немає).

⛔ **ПРИЧИНУ розбіжності тракт НЕ ізолює, і це записано в коді поруч із гілкою.** `anchor_cluster_leaf_cids` рахує по ПОТОЧНІЙ приналежності дерев, тож субкорінь розходиться однаково від переїзду дерева В кластер, переїзду ГЕТЬ, дропу рядків ретеншном і від підміни payload'а. **Саме тому ім'я `mismatch` сусіда (`Mrv::TelemetryArchiveBatchService`) сюди НЕ взято**, хоч воно й напрошувалось: там воно означає integrity-провал, а тут причина буває цілком легітимною — позичене слово стверджувало б tamper без доказу. Офлайн-верифікатор рахує цей стан окремо і **не падає** на ньому з тієї ж підстави.

🔑 **Що потрібне для справжнього розчеплення** (і чого сьогодні немає): джерело, яке переживає переїзд дерева — напр. знімок складу кластера на момент якоря. Доки його немає, дискримінатор сиблінга (лічильник відновлених листів) сюди не портується.

### `Mrv::TelemetryArchiveBatchService` [E.60 Фаза 1б]

| | |
|---|---|
| **Файл** | `app/services/mrv/telemetry_archive_batch_service.rb` |
| **Вхід** | `txs` (одна token-група ПІСЛЯ KYC/SEC.13/circuit-фільтрів), `token_type:`, `tax_rate:` |
| **Що робить** | Групує диспатч у архів-підгрупи для transact-циклу («один batchMint = один root» фізично). Наявне членство (`archive_batch_id`) → реюз stored root; nil-група → union вікон (`Mrv::LineageWindow` 1:1, глобальний порядок `(created_at, id)`) → `MerkleTree.root` → **одна транзакція** {`create_or_find_by(archive_root, token_type)` + set-once bind усіх tx, звірений `member_count == txs.size`} (root-set ≡ bind-set — crash АБО **partial-bind race** (конкурент забрав частину tx) відкочує ВСЕ через Rollback; конкурентні build'и конвергують у той самий рядок) + первинний enqueue pin-воркера. Partial-bind → до двох проходів перечитування членства; друга гонка поспіль → `build_failed`. Windowless-диспатч → `ZERO_ROOT` БЕЗ рядка; збій → `build_failed`-слід (NULL-root, tx_ids, created_at-межі) БЕЗ біндингу + zero32 (fail-open). Advisory-assert: size-1 root ≠ `telemetry_merkle_root` → метрика `dispatch_drift`, мінт не блокує. Викликається ПОЗА oracle-локом (`BlockchainMintingService#process_token_group`). Семантика — One-Home [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline). |
| **Зовнішні виклики** | — (AR + `MerkleTree`/`Mrv::TelemetryLeaf`/`Mrv::LineageWindow`) |
| **Вихід** | масив `Group(root:, txs:, batch:)` |

### `Chainlink::OracleDispatchService`

| | |
|---|---|
| **Файл** | `app/services/chainlink/oracle_dispatch_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | **⚪ Demoted [ARCH.53]:** генерує local correlation-marker `chainlink-req-<hex>` + `oracle_status: "dispatched"` — БЕЗ RPC. Guard clause: `verified_by_iotex? == true`. On-chain `sendRequest` вилучено (DON-нога unwired — нема Functions JS-source / consumer / relayer; повертався tx_hash, а callback-lookup ключить requestId → не збіглись би; кожен запит = LINK-cost без відповіді). Маркер = dedup-ключ Solana [ARCH.51] + idempotency-guard dispatch/callback-шляхів; демоут-інваріант (жодного `Web3::RpcConnectionPool`) закріплено спеком. Вилучена on-chain машинерія (S6.15 `Web3::ChainlinkRouterVersion` ABI-registry + bytecode probe · BLOCKER-04/09 strict-raise + Router-параметри · ARCH.49 nonce-lock цього шляху) воскресає з git при замиканні PATH 1. |
| **Зовнішні виклики** | — (local-only) |
| **Вихід** | `request_id` (String). Оновлює `TelemetryLog.chainlink_request_id`, `oracle_status = "dispatched"`. |

### `Ed25519Crypto::SigningService`

| | |
|---|---|
| **Файл** | `app/services/ed25519_crypto/signing_service.rb` |
| **Вхід** | `seed_hex`, `message` або `public_key_hex`, `signature_hex` |
| **Що робить** | Ed25519 криптографія для non-EVM мереж (Solana, peaq). Генерація ключів, підпис, верифікація. Валідація hex-рядків на довжину (32/64 bytes). |
| **Вихід** | `generate_keypair → { seed_hex:, public_key_hex: }`. `sign → signature_hex (String)`. `verify → Boolean`. Raises `SigningError`. |

---

## 📜 6. Домен: NaaS Контракти (Contract Management)

### `DailyHealthRouter`

| | |
|---|---|
| **Файл** | `app/services/daily_health_router.rb` |
| **Вхід** | `cluster`, `target_date` |
| **Що робить** | **[SLASH-1]** One-Home спільного денного читання `AiInsight.daily_health_summary` за (cluster, активні дерева, дата) — споживають ОБИДВА денні шляхи: A (`ContractHealthCheckService`, slash-поріг 0.83) і B (`ParametricInsurance#evaluate_daily_health!`, insurance-поріг 0.8). `blackout?` (активні дерева Є, інсайтів немає) — спільне force-majeure-рішення «дерево замовкло» → Field Audit, НІКОЛИ авто-burn/payout ([`05_05 §6`](05_05_Slashing_and_Risk_Policy)). Пороги 0.83/0.8 свідомо per-consumer (РІЗНІ концепти — НЕ уніфікуємо, задокументований spread). |
| **Вихід** | `insights` (relation), `total_active_trees`, `blackout?`, `skipped?`, `critical_count(threshold)`. |

### `ContractHealthCheckService`

| | |
|---|---|
| **Файл** | `app/services/contract_health_check_service.rb` |
| **Вхід** | `naas_contract` (NaasContract), `target_date` (Date, default: `AiInsight.reporting_date` [ARCH.100]). ⚠️ Власний дефолт сервісу **недосяжний у проді** й лишається лише як контракт сигнатури: єдиний викликач — `NaasContract#check_cluster_health!`, і той завжди передає дату (свій дефолт — той самий вираз, тож розійтися вони не можуть). Виміряно мутацією 2026-08-13 |
| **Що робить** | Спільне денне читання — через `DailyHealthRouter` (DRY з insurance-шляхом B). Перевіряє здоров'я кластера: > 20% активних дерев зі `stress_index ≥ AiInsight.slash_stress_threshold` (DAO-live, GOV.1 — константа лише default-fallback) → `:degraded` → чокпоінт слешингу (cause-gate вирішує slash/freeze). Cluster-wide порожні AiInsight (`router.blackout?`) → `flag_data_blackout!` (**`EwsAlert(:field_audit)`** + Field Audit, force-majeure — no burn; gap-D). 🔴 **[⚖️ 2026-07-30] Малий кластер → `:insufficient_sample`, ніколи авто-burn:** при `N < 1/slash_fraction` (для дефолтних 0.2 це N ∈ {1..4}) добуток `N × f` менший за одиницю, тобто БУДЬ-ЯКЕ одне критичне дерево перетинає поріг — відсоток перестає бути статистичним твердженням. Тою ж дорогою, що blackout: `EwsAlert(:field_audit)`, гроші зупинено, присуд людський. Межа **деривується з порога**, не хардкодиться. ⚠️ Стосується ЛИШЕ статистичного шляху — `Tree#trigger_slashing_protocol` (deceased/removed) розміру не питає й не повинен: смерть це прямий факт, а не висновок із вибірки. ⊕ **І межа має ДРУГИЙ бік, який цей рядок доти не називав** ([SLASH-1] 2026-08-25): застереження виносить із-під правила `Tree#trigger_slashing_protocol`, але сусідній споживач ТОГО САМОГО роутера — `ParametricInsurance#evaluate_daily_health!` — вироджується ідентично й `insufficient_sample`-гілки НЕ має. Це присуд, не пропуск: там межу тримає dual-trigger (кандидат грошей не рухає), а не статистика. Дім обох боків — [`05_05 §7`](05_05_Slashing_and_Risk_Policy). Канон — [`05_05 §7`](05_05_Slashing_and_Risk_Policy). **[ARCH.46]** поріг = той самий, що сайзить damage у `BlockchainBurningService`; прокидає `target_date` у burn. |
| **Зовнішні виклики** | `BurnCarbonTokensWorker.perform_async(org, contract, nil, false, target_date)` (на `:degraded` — з `target_date` [ARCH.46]) |
| **Вихід** | Verdict-символ `:healthy`/`:degraded`/`:blackout`/`:skipped`. **НЕ** breach-ить тут (SLASH-1: breach асинхронний, лише на реальному positive-A слешингу в `BlockchainBurningService`). |

### `ContractTerminationService`

| | |
|---|---|
| **Файл** | `app/services/contract_termination_service.rb` |
| **Вхід** | `naas_contract` (NaasContract) |
| **Що робить** | Дострокове розірвання контракту за **Опцією 1 MSA** ([`msa_skeleton §B.6.3`](protocols/legal/msa_skeleton.md)): валідація `status_active?` та `min_days_before_exit`, cancel, опційна погоджена форфейтура. Розрахунку refund/fee НЕМАЄ — методи зняті [BIZ.22, ⚖️ 2026-08-30], redemption-механіка суперечила підписуваному документу (F5/F6). |
| **Зовнішні виклики** | `BurnCarbonTokensWorker.perform_async` (якщо `burn_accrued_points == true`) |
| **Вихід** | `{ burned: Boolean }`. |

---

## 🚨 7. Домен: Надзвичайне Реагування (Emergency Response)

### `EmergencyResponseService`

| | |
|---|---|
| **Файл** | `app/services/emergency_response_service.rb` |
| **Вхід** | `ews_alert` (EwsAlert AR instance) |
| **Що робить** | Виконує протокол фізичної відповіді за типом загрози — таблиця `PROTOCOLS` (дім значень; кожен крок несе `device_type` · `payload` · `duration` · **`relevance`**): `severe_drought` → water_valve 2 год, `fire_detected` → **fire_siren 1 год, ПОТІМ** water_valve 4 год. **[ARCH.75]** Порядок кроків = порядок видачі: обидві пожежні команди `high`, тож `by_priority` розводить їх за `created_at`, а Королева дренажує лише `QUEEN_POLL_MAX_PER_FLUSH`=3 накази за флаш — сирена мусить іти першою, інакше вона п'ята за чанками поливу (інверсія інваріанта моделі «сирена має витіснити полив»). **`relevance`** = вікно РЕЛЕВАНТНОСТІ (доки відповідь ще має сенс — фізика події), і воно ж стає `expires_at`; доставність — окреме питання, див. ⚠️ нижче. ⚖️ **Числа РАТИФІКОВАНО founder-ом 2026-08-20:** сирена 15 хв · пожежний полив 2 год · посушливий полив 6 год — перегляд при бенчі/залізі є зміною підписаного значення. Набір актуаторів береться одним відбором (+ `preload(:gateway)` окремим запитом, бо `deliverable?` читає шлюз кожного актуатора) і розкладається за типом у пам'яті; живість шлюза питається ОДНИМ домом — предикатом `Gateway#online?`, рукописного вікна тут більше немає. 🔴 **Фільтр придатності (`робочий стан пристрою` ∧ `живий шлюз`) стоїть у ПАМ'ЯТІ, а не у `WHERE`, і це несуче:** порожній результат мусить розрізняти «заліза цього роду в кластері немає» ⊥ «залізо є, але недосяжне» — різні дії людини, — а SQL-фільтр зливає їх в один порожній набір; пріоритизація за відстанню шлюза до дерева — сорт **у пам'яті** по квадрату відстані з `Float::INFINITY` для безкоординатних (дзеркало `ASC NULLS LAST`), **НЕ** `SilkenNet::GeoUtils` (той тут не викликається). Масове `insert_all` для ActuatorCommand. |
| **Зовнішні виклики** | (нема) — ⚠️ **[FW.60]** push-ногу `ActuatorCommandWorker.perform_async` знято (2026-07-13, останній live-enqueuer): `insert_all` обходить `dispatch_to_edge!`, але команди (`:issued`) вже видимі poll-тракту через scope `.pending` — Королева забирає їх сама (`Downlink::PendingQueueService`, CMD найпріоритетніший); push-ретраї в CGNAT-діру `fail!`'или б сирену ДО першого poll'а |
| **Вихід** | `nil`. Side effects: масово створює `ActuatorCommand` записи **АБО** — коли доставити нема чим — не створює жодного й пише `EwsAlert(:emergency_response_undeliverable, :critical)`. **Ключів чотири, і вони діляться на дві осі дедупу.** Відмова КОНКРЕТНОМУ пристрою (дедуп по парі `message_key`+`actuator_id`): `emergency_response_over_ceiling` (наказ понад `Actuator#max_active_duration_s`) · `emergency_response_too_slow` (каденс поллу довший за вікно релевантності). Не-дія цілого КРОКУ протоколу (дедуп по парі `message_key`+`device_type` — актуатора, на який можна послатись, може не існувати): `emergency_response_no_actuator` (заліза цього роду в кластері не встановлювали) · `emergency_response_all_unavailable` (встановлене є, але жодне не придатне; несе `installed` + дві НЕЗАЛЕЖНІ причини, `silent_gateway` і `out_of_service`, чия сума має право перевищити `installed` — пристрій у сервісі за мовчазним шлюзом є двома фактами, не половиною одного). Відмова **поактуаторна** й **покрокова**: сусід, що доставку витримує, свої накази отримує, а решта кроків протоколу не зачеплена. ⚠️ `device_type` їде в повідомлення СИРИМ токеном (ідентифікатор класу, як `%{endpoint}`) — людських назв типів пристроїв у дереві не існує, той самий сирий токен друкує `Actuators::Card` (борг [`I18N.1`](00_07_Action_Plan_Tracker), який накриє обидва сайти разом). |

> ⚠️ **Що з гепу диспетчеризації [ARCH.75] закрито, а що ні — happy-path вище описує НАМІР, і донедавна не описував поведінку.** Усі вади народились із зустрічі push-ерівського дизайну з poll-семантикою FW.60. ✅ **Закрито 2026-08-15** (⚖️ founder — форма присуду: «гучна відмова замість тихого невалідного рядка» + «TTL = вікно релевантності, доставність питається окремо»): **(1)** плаский TTL 15 хв проти каденсу поллу — тепер `expires_at` = `relevance` кроку (фізика події), а недосяжний каденс ловиться ЯВНО через `Downlink::PendingQueueService.reachable_within?`. 🔴 **Джерело каденсу — константа-дзеркало прошивки (`WORST_CASE_POLL_INTERVAL_S` ← `FLUSH_INTERVAL_MS`+джиттер), а НЕ `gateways.config_sleep_interval_s`:** ту колонку прошивка не читає взагалі й downlink'а для неї не існує, тож порівняння з нею було б виміром вигаданої величини — шлюзи, провіжінені на 300 і на 3600, флашать ОДНАКОВО. ⚖️ **Ратифікований наслідок (2026-08-15):** при годинному каденсі `fire_siren` (15 хв) недоставна ЗАВЖДИ — платформа каже це вголос, один раз на актуатор, замість імітувати відповідь; механізм, якого бракує, заведено окремо ([`00_07`](00_07_Action_Plan_Tracker) FW.64 — подієвий флаш при pending-CMD). Тобто фікс порядку черги **(2)** сьогодні спостережний лише під стабом каденсу, і це названо, а не сховано; **(2)** сирена перед поливом — порядок кроків `PROTOCOLS`; **(4)** різ за власною константою — стеля протоколу зведена в один дім `ActuatorCommand::MAX_DURATION_S`, а фізична стеля пристрою питається через `Actuator#can_sustain?` **ДО** запису, тож невалідних рядків більше не виникає взагалі. ✅ **(5) НЕ-ДІЯ стала гучною (2026-08-15) — і це була діра в самій тезі пункту.** Доти «гучна відмова» діяла лише там, де актуатор знайшовся: крок протоколу без жодного придатного пристрою мовчки пропускався (`by_device_type.fetch(k, [])` → `return if actuators.empty?`), а порожній набір на весь кластер давав рівно `Rails.logger.warn`. 🔴 **Гірша половина класу — часткове виконання, бо воно виглядає як УСПІХ:** кластер із клапаном, але без сирени, виконував пожежний протокол наполовину — полив їхав, евакуаційний сигнал не існував, і слід був невідрізнимий від повного успіху. ⚠️ Показово, що гейт `PROTOCOLS parity` у спеці збудували саме як ОБХІД цього мовчання («друкарська помилка в ключі дає НУЛЬ команд, НУЛЬ алертів і НУЛЬ логів»); він лишається корисним (ловить до деплою), але сам дефект тепер не тихий і в рантаймі. ⛔ **Лишається відкритим (3):** `duration_chunks` ріже 4 год на чотири накази, але вони **не серіалізуються** — видаються підряд і накладаються, тож обіцянка «`fire_detected` → water_valve 4 год» досі не виконується як безперервне вікно; ⚖️ 2026-08-20: питання (duty-cycle обходиться back-to-back чанками) ВІДКЛАДЕНО в залізний пакет — задається разом із вибором клапана/сирени в BOM ([`02_01`](02_01_Hardware_Architecture_and_BOM)), одним днем зі стелями сідів і віссю duration>relevance → [`00_07`](00_07_Action_Plan_Tracker) ARCH.75. 🔴 **Що варто знати про попередній стан, бо клас повторюваний:** `insert_all` обходить валідації, тож наказ понад стелю пристрою лягав у БД невалідним і далі не міг ні виконатись, ні померти (кожен AASM-перехід бився об `duration_within_safety_envelope`) — і наслідок був ПЕРЕВЕРНУТИЙ: аварійна відповідь працювала рівно доти, доки `max_active_duration_s` лишали НЕ оголошеним, тобто колонка безпеки й вимикала безпеку. Транспорт від такого рядка захищено окремо (force-fail у `Downlink::PendingQueueService`, §8), і той захист лишається — він про інший клас (рядок, що вже в БД). ⚠️ Сіди досі везуть плейсхолдери (клапан 300 с, сирена 120 с), які власному протоколу СУПЕРЕЧАТЬ — тепер це видно гучно, алертом, а не мовчки. ⚖️ 2026-08-20: `PROTOCOLS` = **target-контракт** — гучний розрив і Є свідомою поведінкою до вибору заліза; стелі задаються разом із BOM-вибором, не демо-числами.

---

## 🔧 8. Домен: Апаратне Забезпечення та Безпека (Hardware, IoT & Security)

### `HardwareKeyService`

| | |
|---|---|
| **Файл** | `app/services/hardware_key_service.rb` |
| **Вхід** | `.provision(device, master_key: nil)`, `.rotate(device_uid)` або `.derive_broadcast_key(cluster_id, master_key: nil)` |
| **Що робить** | **Provision** (post-ARCH.42 Variant B, 2026-05-23): атомарно деривує **AES ключ за device_type** — Tree → `derive_lora_key` (16 байт, info `"silken-aes-128-lora-key"`); Gateway → `derive_device_key` (32 байти, info `"silken-aes-256-device-key"`). **derive_broadcast_key** (FW.2 (в), 2026-07-03): cluster control-plane KEYB — 16 байт, salt `"cluster:<id>"` (домен K_ota), info `"silken-aes-128-broadcast-key"`; НЕ персиститься у `HardwareKey` (деривується on-demand на фабриці: Tree → KEYB-слот, Gateway → її KEYL — [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security)). Плюс `K_seed` для атрактора Лоренца (`SilkenNet::SeedDerivation.derive_seed`, 32 байти). Зберігає у `HardwareKey` (`aes_key_hex` conditional length + `lorenz_seed_hex` [SEC.11]). HKDF-only; ikm = `master_key:` параметр (фабрична `Session`, SEC.3 DI — прошивається наскрізь у всі derive-методи включно з `derive_seed`) або ENV-fallback `PROVISIONING_MASTER_KEY` (runtime: register API, `derive_iotex_seed`) — raise `SecurityError` без жодного (no SecureRandom fallback ANYWHERE; pre-prod hard cutover). **Rotate** (post-FW.17, 2026-06-11): Dual-Key Handshake — старий AES ключ → `previous_aes_key_hex`; **Tree** → Hash-Ratchet крок `Cryptography::KeyRatchet` + `key_version`++ + enqueue `KeyRotationDownlinkWorker` (0x9E; ключ НЕ летить ефіром — [`03_05 §3.8`](03_05_Hardware_Symmetric_Crypto_and_Security)), gated `FW17_RATCHET_DOWNLINK_ENABLED` (закрито → `RatchetGateClosedError`); [FW.60] доставка 0x9E = poll-derivation `Downlink::PendingQueueService` (Grace-вікно `previous_aes_key_hex ≠ NULL` = непідтверджена ротація) — той самий гейт, push-нога воркера у CGNAT не долітає; **Gateway** → випадковий новий ключ, доставка = re-provision (SEC.3). Legacy `sys/key_update` (слав ключ ефіром, без firmware-споживача) — видалено. Захист від подвійної ротації (`RotationPendingError`). |
| **Зовнішні виклики** | `OpenSSL::KDF.hkdf` (через `SilkenNet::SeedDerivation`), `KeyRotationDownlinkWorker.perform_async` (Tree, 0x9E dispatch), [ARCH.57] `record_audit_trail!` на кожен rotate (`hardware_key_rotated`, chain-only, БЕЗ key-матеріалу; org через `device.cluster` → без кластера = глобальний ланцюг) |
| **Вихід** | Provision: `HardwareKey` instance з обома секретами. Rotate: `new_hex_key` (String, **32 hex для Tree LoRa / 64 hex для Gateway CoAP** після ARCH.42). Raises `RotationPendingError`, `RatchetGateClosedError`, `SecurityError`. |
| **Порядок enqueue [ARCH.59]** | 🔴 **Enqueue `0x9E` їде ПІСЛЯ коміту БД-ротації, не в спільній транзакції.** Спільна транзакція відкочувала б ключ разом із версією — тобто в бік, якого тракт лікувати НЕ вміє: без `previous_aes_key_hex` Grace-декрипту нема за що вхопитись, вузол німіє, а Sidekiq бачив би job ще до коміту (phantom-job). Після коміту відмова падає в бік із НАЯВНИМ backstop'ом: Grace-вікно робить незавершену ротацію видимою для `Downlink::PendingQueueService#key_rotation_payload`, тож `0x9E` добере наступний poll Королеви; виняток не ковтається — повтор упреться в `RotationPendingError`, а не в подвійний advance. Той самий порядок і з тієї ж підстави — `Api::V1::ProvisioningController#register`. 🔑 **Напрямок відмови обирають за наявним backstop'ом, не за смаком.** |

### `OtaHmacKeyService` 🔐 [FW.23]

| | |
|---|---|
| **Файл** | `app/services/ota_hmac_key_service.rb` |
| **Вхід** | `cluster_id` (Integer або String) + опційний `master_key:` (SEC.3 DI) |
| **Що робить** | Per-cluster OTA HMAC ключ `K_ota` для аутентифікації bytecode на Soldier (dual-gate). Дериває `K_ota = HKDF-SHA256(master_key, salt="cluster:#{id}", info="silken-ota-hmac-v1", len=32)`; ikm = `master_key:` параметр (фабрична `Session`, SEC.3 DI) або ENV-fallback `PROVISIONING_MASTER_KEY` (runtime: `OtaPackagerService`). **Domain separation** від `HardwareKeyService` AES device-keys: info `"silken-aes-128-lora-key"` (Tree LoRa) та `"silken-aes-256-device-key"` (Gateway CoAP) — компрометація одного K-вектора не розкриває інших трьох. Слідує патерну SEC.11: raise `SecurityError` без master key (no SecureRandom fallback в production; dev/test pin-ять ключ у `spec/rails_helper.rb`). |
| **Зовнішні виклики** | `OpenSSL::KDF.hkdf` |
| **Публічні методи** | `.fetch_for(cluster_id, master_key: nil) → String` (64-символьний HEX, upper); `.fetch_binary_for(cluster_id, master_key: nil) → String` (32 binary bytes) — для прямого `OpenSSL::HMAC.digest` |
| **Вихід** | 64-символьний HEX або 32-байтна binary-string. |
| **Cross-ref** | [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning) — повний протокол OTA HMAC dual-gate. |

### `OtaPackagerService`

| | |
|---|---|
| **Файл** | `app/services/ota_packager_service.rb` |
| **Вхід** | `firmware` (BioContractFirmware або TinyMlModel), `chunk_size:` (default 512 bytes CoAP), `cluster_id:` (опціонально — Integer/String; вмикає HMAC trailer [FW.23]) |
| **Що робить** | Фрагментує `firmware.binary_payload` на чанки. Додає заголовок `[0x99][Index:uint16][Total:uint16]` + CRC16-CCITT per chunk. **[FW.23]** При `cluster_id:` — після bytecode-чанків емітує 4 trailer-чанки: 3 HMAC-печатки + 1 version envelope (детально нижче). |
| **[FW.8] `build_threshold_config_block(tree)`** | Клас-метод. Будує `CMD_SET_THRESHOLDS` (0x9A) OTA Config Block для передачі per-species Lorenz порогів на Soldier без перекомпіляції. Читає `tree.effective_lorenz_thresholds` → упаковує у 10-байтовий payload: `[z_min×100:int16_le][z_max×100:int16_le][z_opt×100:int16_le][species_id:uint8][config_version:uint8][crc16:uint16_le]`. Prefixed: `[CMD_SET_THRESHOLDS:1][len:uint16_le][payload]`. |
| **[FW.23] `compute_hmac_tag(bytecode, version_id, lora_total_chunks, cluster_id:)`** | Клас-метод. Обчислює HMAC-SHA256 по `bytecode \|\| version_id_be(4) \|\| lora_total_chunks_be(2)`. Anti-replay: `version_id` прив'язує тег до конкретної ревізії. Anti-truncation: `lora_total_chunks` в тезі — скидання будь-якого trailing-чанку детектується як HMAC mismatch на Soldier. Повертає 32-byte binary digest. |
| **[FW.23] `build_hmac_trailer_chunks(hmac_tag, lora_total_chunks, version_id)`** | Клас-метод. Емітує 4 LoRa-форматованих 16-байтових блоки: 3 печатки `[0x9B][seg_idx:2 BE][lora_total:2 BE][hmac_seg:11]` (сегмент 3 = 10 реальних байт + 1 NUL PAD) + 1 version envelope (seg 4) `[0x9B][0x0004][lora_total:2 BE][version_id:4 BE][PAD:7]`. `version_id` — вхід HMAC, без нього Soldier не перерахує печатку. Queen relay-ює їх stateless; Soldier збирає через `Parse_HMAC_Trailer_Chunk` → `OTA_Try_Finalize`. |
| **OTA Command Constants (SSOT)** | `CMD_OTA_BYTECODE=0x99` (mruby chunks), `CMD_SET_THRESHOLDS=0x9A` (FW.8 Lorenz Z), `CMD_HMAC_TRAILER=0x9B` (FW.23 OTA HMAC печатка + version), `CMD_TIME_SYNC=0x9C` (FW.20 RTC correction), `CMD_SET_AUDIO_THRESHOLDS=0x9D` (FW.18 TinyML confidence thresholds). Повна карта опкодів: [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA). |
| **HMAC Constants** | `HMAC_TAG_BYTES=32`, `HMAC_TRAILER_SEGMENTS=3`, `HMAC_VERSION_SEG_IDX=4`, `OTA_TRAILER_CHUNKS=4`, `HMAC_SEG_BYTES=11`, `HMAC_TRAILER_BLOCK=16` |
| **Вихід (без cluster_id)** | `{ manifest: { version, total_size, checksum, sha256, total_chunks }, packages: Enumerator<16-byte blocks> }` |
| **Вихід (з cluster_id)** | `{ manifest: { version, total_size, checksum, sha256, total_chunks, lora_total_chunks, total_packages, hmac_signed: true, hmac_cluster_id }, packages: Enumerator<bytecode_chunks + 4 trailer_chunks> }` — `total_packages = total_chunks + 4`; `OtaTransmissionWorker` ітерує по `packages` без змін у логіці pacing. |

### `Ota::DeploymentDispatcherService` 🔐 [SEC.20 Rails-half]

| | |
|---|---|
| **Файл** | `app/services/ota/deployment_dispatcher_service.rb` |
| **Вхід** | `firmware:` (BioContractFirmware), `organization:` (tenant-скоуп), `cluster_id:` (опц. — nil = усі кластери організації), `canary_percentage:` (1–100, default 100) |
| **Що робить** | Єдиний вхід deploy-кампанії (викликається з `FirmwaresController#deploy`). Спершу **oversized-гейт [FW.60]**: `manifest[:total_chunks]` (lazy — пакети не матеріалізуються) понад `QUEEN_MAX_BYTECODE_CHUNKS=16` → кампанія відхиляється ДО burn (Queen мовчки дропає `ch≥16`, збірка зависла б назавжди — [`03_02 §5`](03_02_Queen_Gateway_Firmware) Guard 3). Далі в одній транзакції: `lock` цільових кластерів → **anti-rollback guard** `firmware.id > clusters.ota_version_hiwater` (строго `>` — Rails-дзеркало Солдатового інваріанта Flash-KV 0x15, [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning); той самий `firmware.id` їде в seg-4 HMAC-трейлера) → canary-когорта **per-cluster** (перші `ceil(N × pct / 100)` за `id` — стабільна когорта) → **hiwater палиться при dispatch** лише кластерам із реальною когортою («фікс завжди НОВИЙ запис»; слот НЕ палиться кластеру без eligible-шлюзів) → **[FW.60] таргет персистується per-gateway**: `gateways.pending_firmware_id = firmware.id` когорті (атомарно з burn) — доставку тягне сама Королева (poll → OTA-hint → chunk-server `Downlink::PendingQueueService`), push-fan-out `OtaTransmissionWorker` superseded. Після commit — `firmware.deploy_globally!(percentage:)` (живить `latest_tree_firmware_id` → `check_firmware_mismatch!`). Eligible-фільтр = модельний скоуп `Gateway.ota_deployable` (`ip_address` present, state ∉ {maintenance, faulty, **updating**} — Queen має один глобальний OTA-буфер без campaign-id, конкурентна кампанія на шлюзі = битий образ в ефірі, [`03_02 §5`](03_02_Queen_Gateway_Firmware)). **Стелі (свідомі):** активація `deploy_globally!` глобальна навіть від per-cluster canary (per-cluster tracking = E.62, не реалізовано); інфра-збій після hiwater-burn лишає слот спаленим (безпечна сторона — частково-полетілу кампанію не відкотити; recovery = новий запис); TOCTOU-вікна воркера більше нема — `state=:updating` + `ota_started_at` ставить `Downlink::PendingQueueService` при видачі hint'а (ARCH.59-якір). |
| **Зовнішні виклики** | — (DB only) |
| **Вихід** | `Result` struct: `dispatched_gateways` (Integer), `skipped_clusters` (масив `SkippedCluster(id, name, reason)` з reason `"rollback"` \| `"no_gateways"` \| `"oversized_firmware"`), предикат `dispatched?` |
| **Cross-ref** | [`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning) (bump-інваріант + Rails-half), [`04_03 §5.7`](04_03_REST_API_v1_Reference) (HTTP-контракт), [`00_07` — SEC.20](00_07_Action_Plan_Tracker), [`00_07` — FW.60](00_07_Action_Plan_Tracker) (poll-тракт) |

### `Downlink::PendingQueueService` 📡 [FW.60]

| | |
|---|---|
| **Файл** | `app/services/downlink/pending_queue_service.rb` |
| **Вхід** | `.poll_reply(gateway:, query:)` та `.ota_chunk_reply(gateway:, query:)` — обидва з `CoapGate.handle_queen_pull` (демон-процес, [`06_01`](06_01_Deployment_Kamal_Terraform) coap) |
| **Що робить** | Rails-половина poll-після-флашу (LwM2M Queue-Mode, [`03_02 §4`](03_02_Queen_Gateway_Firmware) inbound-тракти): Королева питає `GET poll/<uid>?fw=<contract_id>` одразу після `send_success`. **Derivation без власної таблиці-черги**, пріоритет: **CMD** (`ActuatorCommand.pending` шлюза `.by_priority`; видача = повний success-lifecycle `dispatch!`→`may_activate?`-guarded `mark_active!`→`acknowledge!`→`ResetActuatorStateWorker.perform_in` — семантичний аналог push-успіху; ⚠️ **[FW.63]** втрату 2.05 **НЕ** покриває ніщо — poll-тракт прошивки ретрансміту не має, same-MID retry живе лише в uplink-PUT, тож загублена відповідь губить наказ назавжди, а слід каже `confirmed`; MID-кеш `CoapGate` закриває тільки дубльовану датаграму; протермінована/oversized команда → `fail!` гучно) → **0x9E ratchet** (gated тим самим `HardwareKeyService.ratchet_dispatch_enabled?`; derivable з Dual-Key Grace: tree-`HardwareKey` кластера з `previous_aes_key_hex ≠ NULL` = непідтверджена ротація → `build_rotate_key_block(key_version)`) → **OTA-hint** `[0x9F][firmware_id:4 BE][total:2 BE]` (якщо `gateways.pending_firmware_id` відстає від `fw=` запиту; при видачі ставить `state=:updating` + `ota_started_at` — ARCH.59-якір) → **time-only конверт** (32 Б — порожня черга; `[0x9C][ts:4]` вшивається `CoapEncryption` у КОЖНУ відповідь, тож будь-який poll = RTC-sync Королеви). **Chunk-server** (`ota/<uid>?v=&ch=`): stateless — Королева єдина знає свій bitmap і тягне відсутні чанки сама; пакети кешуються `Rails.cache` per (firmware, cluster) — той самий масив живить hint-total і чанки. **Спостережене підтвердження доставки**: `fw=` ≥ pending → `pending_firmware_id=nil` + `firmware_version` + `state=:idle` (RAM-стан Королеви = 0 після ребуту → повторний hint → безпечний idempotent re-fetch). Конверт = `coap_encrypt` (AES-256-CBC KEYC, Dual-Key Grace `binary_previous_key \|\| binary_key`); стеля `MAX_ENVELOPE_BYTES=560` = дзеркало firmware `CMD_DECRYPT_BUF_SIZE+16`. **[SEC.20] Turbo-прогрес кампанії** — живий producer `Firmwares::OtaProgressBar` (push-воркер superseded): hint → 0% TRANSMITTING, кожен chunk-fetch → `ch+1/total`, `fw=`-підтвердження → COMPLETE; `broadcast_replace_to "ota_channel_<uid>"`, підписники = [`04_04 §8`](04_04_Phlex_UI_and_Tailwind). |
| **Зовнішні виклики** | `Turbo::StreamsChannel.broadcast_replace_to` (OTA-прогрес) + DB + Rails.cache; викликається з coap-демона синхронно — свідома стеля single-loop'а на TRL-3 |
| **Вихід** | envelope-байти (`[IV:16][AES-256-CBC(KEYC)]`) або `nil` (нема KEYC / чужа-завершена OTA-версія / `ch` поза межами / **[FW.60] нема `PROVISIONING_MASTER_KEY`** — `ota_packages` ловить `SecurityError` (< `Exception`, інакше повз демон-rescue `StandardError` → crash-loop інтейку), OTA fail-closed: hint пропущено (poll усе одно віддає time-only), chunk → 4.04, інтейк живий) → `CoapGate` відповідає 2.05 Content або 4.04 |
| **Cross-ref** | [`03_02 §4`](03_02_Queen_Gateway_Firmware) (inbound-тракти + флоу), [`03_02 §5`](03_02_Queen_Gateway_Firmware) (OTA assembly), [`00_07` — FW.60](00_07_Action_Plan_Tracker) |

### `Security::WeakKeyDetector` 🔐 [SEC.9]

| | |
|---|---|
| **Файл** | `app/services/security/weak_key_detector.rb` |
| **Вхід** | `value` (String, nullable — типово вміст ENV-змінної), `hint:` (String, опц. — назва секрету для повідомлень) |
| **Що робить** | Виявляє слабкі / відомі test-vector master-секрети. Перевіряє три інтерпретації введеного значення (raw bytes, hex-decoded, base64-decoded — лише якщо round-trip lossless) проти чотирьох категорій патернів: **(1) Known test vectors** — FIPS-197 Appendix B (AES-128, той самий вектор, що мав firmware ключ в оригінальному BLOCKER), FIPS-197 C.1/C.2/C.3, NIST SP 800-38A F.5, RFC 3686 §6, RFC 4231 Test Cases 1/3/6/7, FIPS 198-1; перевіряє і exact match, і prefix match (≥8 байт overlap). **(2) Degenerate patterns** — all-zero, all-0xFF, single-byte repeat, strictly monotonic byte run (delta ±1). **(3) Placeholder substrings** (ASCII only) — `CHANGEME`, `PLACEHOLDER`, `TODO`, `your-master-…`, `replace-me`, `not-a-real-key`, `<…>` template artefacts тощо. **(4) Low-entropy heuristic** — повторюваний N-байтний блок або < 4 унікальних байтових значень (загальна евристика, виконується останньою). |
| **Зовнішні виклики** | — (in-memory). Залежить від `OpenSSL`, `Base64`. |
| **Публічні методи** | `.detect(value, hint:) → nil \| String` (повертає reason-string з опц. префіксом hint, якщо знайдено патерн); `.weak?(value, hint:) → Boolean` |
| **Тест coverage** | `spec/services/security/weak_key_detector_spec.rb` — 30+ examples, fuzz через RFC vectors, edge-cases для round-trip base64 та bytestring-encoding |
| **Інвокери** | `config/initializers/master_key_strength_check.rb` (boot-time guard, див. нижче) |
| **Cross-ref** | [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security), [`00_07` — SEC.9](00_07_Action_Plan_Tracker). Закриває оригінальний BLOCKER (firmware AES key перших 16 байт співпадали з FIPS-197 Appendix B). |

#### Boot-time master key guard (initializer)

| | |
|---|---|
| **Файл** | `config/initializers/master_key_strength_check.rb` |
| **Що робить** | У `Rails.env.production?` (включно з canopy) після `after_initialize` перевіряє `ENV["PROVISIONING_MASTER_KEY"]`: (1) blank → raise `SecurityError` з посиланням на `docs/03_06 §2`; (2) непустий, але `Security::WeakKeyDetector.detect` повертає reason → raise `SecurityError` з cause. У dev/test guard вимкнений (там зафіксований стабільний non-secret fixture у `spec/rails_helper.rb` — інакше весь suite не завантажиться). |
| **Bypass** | `SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK=1` — для one-off rescue-boot при флеші zaжатого кластера. Логується гучно, не може стати рутиною. |
| **Зв'язок з HKDF tree** | Captured-критично: master-ключ є коренем для **шести** info-strings (post-FW.2 (в)): `HardwareKeyService.derive_lora_key` (Tree session AES-128, info `"silken-aes-128-lora-key"`), `derive_broadcast_key` (cluster KEYB AES-128, info `"silken-aes-128-broadcast-key"`), `derive_device_key` (Gateway AES-256 CoAP, info `"silken-aes-256-device-key"`), `derive_iotex_seed` (IoTeX Ed25519-seed, info `"silken-ed25519-iotex-v1"`, domain-separation post-ARCH.42), `OtaHmacKeyService` (K_ota, info `silken-ota-hmac-v1`), `SilkenNet::SeedDerivation` (Lorenz `K_seed`, info `silken-lorenz-seed`). Компрометація master = каскадна компрометація всіх шести — тому guard працює fail-closed до запуску HTTP-сервера. |

### `Security::Web3NetworkGuard` 🔐

| | |
|---|---|
| **Файл** | `app/services/security/web3_network_guard.rb` |
| **Вхід** | `env` (Hash-подібний, типово `ENV`; інжектиться в тестах) |
| **Що робить** | Чистий content-judge небезпечної Web3-конфігурації (дзеркалить `WeakKeyDetector`). **A1 (chain identity)** — сканує `*_RPC_URL` (Ethereum/Polygon/Celo/Solana) на testnet-маркери (`amoy`/`mumbai`/`sepolia`/`goerli`/`holesky`/`devnet`…, alnum-boundary-anchored проти хибних збігів у API-ключі). Chain-id константи в коді немає, а live `eth_chainId` на boot свідомо НЕ робиться (boot почав би залежати від доступності RPC = гірший failure-mode). 🔑 **Який бік «неправильний» — оголошує САМ СЛОТ через `WEB3_CHAIN_ENV` ∈ `mainnet`/`testnet` (відсутнє → `mainnet`), і це ДРУГА вісь поруч із `signer_process:`, а не виняток** [OPS.37 — розщеплення токена `production`]. ⛔ **Не bypass:** кожне значення є ТВЕРДЖЕННЯМ, якому мусить відповідати проводка, і напрямки дзеркальні — `mainnet` відмовляє testnet-ендпоінту (реальна вартість на throwaway-чейні), `testnet` відмовляє mainnet-ендпоінту (стейджинг, здатний підписати справжню транзакцію). Отже хибно ОГОЛОШЕНИЙ слот падає так само гучно, як хибно ПРОВЕДЕНИЙ, а забутий прапор лягає на суворий бік. Нерозпізнане значення = власне порушення (мовчазний відкат до дефолту зробив би слот суворим із причини, якої оператор не бачить). Blank-RPC скіпається — окрім двох, чиї read-сайти передають явний `fallback:` у `RpcConnectionPool`, тобто порожня змінна тихо резолвиться у ЗАШИТИЙ ендпоінт, і ці два лежать на ПРОТИЛЕЖНИХ боках осі: `CELO_RPC_URL` → Alfajores **testnet** (E.49; порушення лише на `mainnet`, армується `ORACLE_CELO_PRIVATE_KEY`) ⊥ `ALCHEMY_POLYGON_RPC_URL` → зашитий **mainnet** `polygon-rpc.com` у `MintingRollbackService` (порушення лише на `testnet`, армується ключем мінтера — цю діру створила сама вісь, тож вона й закривається разом із нею). Обидва ключі живуть тільки на job-поверхні → web/coap чисті. **A2 (oracle keys)** — кожен підписант резолвить dedicated-ключ (`ENV.fetch` без fallback; легасі спільний `ORACLE_PRIVATE_KEY` retired — INF.22): відсутність MINTER/SLASHER → `KeyError` глибоко в Sidekiq-воркері → тихий DeadSet, тому presence-чек на boot; формат-чек (64 hex, опц. `0x`) покриває всю dedicated-сімку (MINTER/SLASHER/CELO/ETHERISC/PURO/KLIMA/ANCHOR); значення під retired-ім'ям = violation (zombie-config tripwire). **A3 (silent-address set)** — `SILENT_ADDRESS_ENVS` (`DAO_TREASURY_ADDRESS` + `CARBON/FOREST_COIN_CONTRACT_ADDRESS`): read-sites під rescue-парасольками для RPC-збоїв ковтають config-баг — mint-tax (E.46) тихо off і лог хибно «RPC degraded», `ChainAuditService` повертає хибне «delta 0, all clean» (db↔chain fraud-detector маскується), а `Insurance::ReserveGate` fail-closed, але маркує баг як transient `:eval_error` — тому presence (signer-процес) + формат `0x`+40hex чекаються на boot; значення у violation-текст не echo-иться (могло бути mispasted-секретом). **A4 (Solana signer set)** — `SOLANA_SIGNER_ENVS` (keypair · fee-payer pubkey · token-account · USDC-mint; E.61): stub-режиму нема, а batch-payout цикл ковтає per-wallet помилки БЕЗ escalation-шляху (акумульовані виплати форестерам мовчки не йдуть) → presence-чек у signer-процесі. |
| **Зовнішні виклики** | — (in-memory, без мережі за дизайном). |
| **Публічні методи** | `.violations(env = ENV, signer_process: true) → Array<String>` (порожній = безпечно) = сума чотирьох per-вісь методів (викликаються й окремо — цитати в 05_01/05_02/06_04 реферять їх за іменем): `chain_violations` `[chain]` (A1) · `oracle_violations` `[oracle-key]` (A2) · `address_violations` `[address]` (A3) · `solana_violations` `[solana]` (A4); + `.chain_env(env)` → нормалізоване оголошення слоту. 🔑 **Осей ДВІ, і вони різні за природою — тому друга живе в ENV, а не в сигнатурі.** `signer_process:` = властивість ПРОЦЕСУ, тож kwarg: скоупить лише **presence**-вимогу ключів до процесу-підписанта (Sidekiq); web/coap-контейнери свідомо бутяться без money-ключів (least-privilege: web/coap — ширша, інтернет-виставлена поверхня, тож signing-пʼятірка живе лише в Kamal `job`-ролі; ⚠️ і глобальний `env.secret` успадковують УСІ ролі, тому `deploy_secret_scan` інваріант B судить ще й його); формат/колізія/address перевіряються скрізь, де значення Є. `WEB3_CHAIN_ENV` = властивість КОНФІГУ, тож читається з `env` — сигнатура незмінна, і вісь інжектиться тим самим хешем, що решта. Скоупить вона лише A1. |
| **Тест coverage** | `spec/services/security/web3_network_guard_spec.rb` — testnet-RPC (Amoy/devnet), alnum-boundary false-positive, умовний Celo-unset (armed/unarmed/mainnet), missing/malformed/`0x` oracle-key, silent-address set (missing DAO_TREASURY/SCC · placeholder · no-echo), Solana-presence, `signer_process: false` scoping (keyless-clean · формат/колізія/testnet/address-формат і без ключів), **`WEB3_CHAIN_ENV`-контекст** (testnet-слот на testnet-ендпоінтах чистий · mainnet-ендпоінт на testnet-слоті = violation · регресійний пін старого правила при невизначеній осі · нормалізація регістру/пробілів · нерозпізнане значення · інвертований Celo · зашитий polygon-mainnet-fallback armed/unarmed · address-вісь НЕ послаблена). Класифікаційний пін guard-sets — `spec/deploy/web3_env_loudness_spec.rb` (INF.12 behavior-half: кожен web3-ENV deploy-поверхні ∈ guard-set ∪ documented-LOUD ∪ documented-SOFT; нове ім'я = RED до свідомої класифікації) |
| **Інвокери** | `config/initializers/web3_network_guard.rb` (boot-time guard, див. нижче) |
| **Cross-ref** | [`05_01 §5`](05_01_Multichain_Architecture) (RPC/ENV-конфіг), [`06_04`](06_04_Secrets_Checklist) (ORACLE-ключі), [`00_07` — E.47](00_07_Action_Plan_Tracker). Розширює runtime E.47 Solana-guard на boot-time + EVM. |

#### Boot-time Web3 network guard (initializer)

| | |
|---|---|
| **Файл** | `config/initializers/web3_network_guard.rb` |
| **Що робить** | У `Rails.env.production?`/canopy АБО `WEB3_STRICT_MODE=true` (той самий gate, що IoTeX/Hadron) після `after_initialize` викликає `Security::Web3NetworkGuard.violations(ENV, signer_process: Sidekiq.server?)`; будь-яке порушення → raise `SecurityError` fail-closed ДО прийому трафіку. 🔑 **Цей тригер — половина «загартований рантайм», і він свідомо НЕ отримав вісь середовища: стейджинг хоче його УВІМКНЕНИМ.** Питання «до якого чейну слот має право торкатись» — інша половина, оголошена в `WEB3_CHAIN_ENV` і присуджена всередині гарда (OPS.37). Читати `Rails.env` як відповідь на друге питання — та сама злитість, яку розщеплення й знімає. Повідомлення raise echo-їть усі ТРИ координати (`RAILS_ENV` · `WEB3_STRICT_MODE` · `WEB3_CHAIN_ENV`), бо `[chain]`-порушення без третьої нечитабельне — вона є половиною твердження. Presence-вимога ключів діє лише в signer-процесі (job) — відсутній ключ все одно падає гучно на job-boot, ДО DeadSet; web/coap бутяться keyless by design. У dev/test без strict-mode — вимкнений. Asset-build skip через `SECRET_KEY_BASE_DUMMY`. |
| **Bypass** | `SILKENNET_SKIP_WEB3_NETWORK_GUARD=1` — для one-off rescue-boot. Логується гучно, не може стати рутиною. |

### `Security::EncryptionKeyGuard` 🔐 [SEC.22]

| | |
|---|---|
| **Файл** | `app/services/security/encryption_key_guard.rb` |
| **Вхід** | `env` (Hash-подібний, типово `ENV`; інжектиться в тестах) |
| **Що робить** | Чистий content-judge ключів ActiveRecord Encryption (дзеркалить `WeakKeyDetector`/`Web3NetworkGuard`). Перевіряє три `ACTIVE_RECORD_ENCRYPTION_*` ENV (primary/deterministic/key_derivation_salt): blank → «not set», `< 32` символів → «too short», інакше `Security::WeakKeyDetector.detect` (known-vector/degenerate/placeholder). Ключі шифрують колонки `hardware_keys` (device AES/Lorenz-seed) та `users.otp_secret` (TOTP-seed). [SEC.22] Живуть у ENV, НЕ в `credentials.yml.enc` — інакше поглибили б runtime-залежність від `RAILS_MASTER_KEY`, яку SEC.22 розчиняє. Blank-ключ НЕ провалюється в plaintext: non-deterministic `encrypts` з nil-ключем raise-ить Configuration на першому encrypt/decrypt → провіженінг+telemetry-decrypt+MFA були б dead-on-first-use. |
| **Зовнішні виклики** | — (in-memory). |
| **Публічні методи** | `.violations(env = ENV) → Array<String>` (порожній = безпечно; префікс `[ar-encryption]`). |
| **Тест coverage** | `spec/services/security/encryption_key_guard_spec.rb` — clean env, missing/blank/too-short кожного ключа, WeakKeyDetector-reason surface, all-missing-at-once. |
| **Інвокери** | `config/initializers/active_record_encryption_keys_check.rb` (boot-time guard, див. нижче). |
| **Cross-ref** | [`06_04 §5.7`](06_04_Secrets_Checklist), [`00_07` — SEC.22](00_07_Action_Plan_Tracker). AR-encryption на `users.otp_secret` тримає TOTP-seed поза plaintext. |

#### Boot-time AR-encryption keys guard (initializer)

| | |
|---|---|
| **Файл** | `config/initializers/active_record_encryption_keys_check.rb` |
| **Що робить** | У `Rails.env.production?`/canopy після `after_initialize` викликає `Security::EncryptionKeyGuard.violations(ENV)`; будь-яке порушення → raise `SecurityError` fail-closed ДО прийому трафіку. **НЕ** process-scoped (на відміну від Web3NetworkGuard `signer_process:`): web (provisioning/m2m/MFA) і Sidekiq-воркери (telemetry-unpack/OTA/key-rotation) обидва декриптять AR-колонки — кожен процес, що бутить повний застосунок, потребує ключів (coap-демон лише enqueue-ить, але ключі вузькі per-column, не vault-key → uniform-перевірка простіша). У dev/test guard вимкнений (fixtures у `config/environments/{test,development}.rb`). Asset-build skip через `SECRET_KEY_BASE_DUMMY`. |
| **Bypass** | `SILKENNET_SKIP_AR_ENCRYPTION_KEYS_CHECK=1` — для one-off rescue-boot. Логується гучно, не може стати рутиною. |

### `SilkenNet::DidDerivation` [FW.54]

| | |
|---|---|
| **Файл** | `app/services/silken_net/did_derivation.rb` |
| **Що робить** | DID = f(96-біт UID) — Ruby-дзеркало firmware `did_derive.h` (murmur3-fmix32 ланцюгом по трьох словах STM32-UID; **біт-у-біт**, golden-вектори заморожені обабіч). `wire_did_from_uid_hex` парсить канонічний 24-hex UID-рядок (три %08X-слова у порядку регістрів). Два споживачі: фабричний провіженінг (SEC.3 — `TreeResolver`, host читає UID по SWD **ДО** прошивки → однопрохідне `Tree + HardwareKey + K_seed`) і польовий `ProvisioningController#register`. `DID==0` зарезервовано під Queen-Sentinel (нуль-хеш → SEED-константа). Колізію 32-біт ловить DB-unique на `trees.did` до поля. Канон механізму — [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA). |
| **Вихід** | DID-рядок (детермінований per-UID). |
| **Викликається з** | `FactoryFlashing::TreeResolver` / `FactoryFlashing::Session` (wrong-board guard) / `Api::V1::ProvisioningController#register` |

### `FactoryFlashing::*` — Factory Flashing Pipeline (SEC.3)

Internal-admin сервіси конвеєра прошивки/провіжинингу (Rake-driven, **поза** публічним REST API). **Цей реєстр — дім опису сервіс-об'єктів** (One-Home для «що робить кожен»). Security/threat-model контекст (2-Person Rule, гілки A/B, master-key handling) + impl/bench-статус — [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning); модель сесії — [`04_01` ProvisioningSession](04_01_Data_Models_and_Entities).

| Сервіс | Роль |
|--------|------|
| `FactoryFlashing::Session` | Orchestrator — `ActiveRecord::Base.transaction` (провіжен `HardwareKey` + audit з rollback разом); `PreflightError` для non-approved сесій; **[FW.54] wrong-board guard** — live-режим звіряє UID плати (preflight `-r32` → `UidReadout`) з `trees.silicon_uid_hex` ДО деривації/`-w32`, чужа плата → `WrongBoardError`; preflight-ключ тримається у `@master_key` і йде параметром у деривацію (SEC.3 DI); **[FW.2 (в)]** `cluster_broadcast_key` — деривує KEYB для ОБОХ типів і прокидає у `CommandBuilder` |
| `FactoryFlashing::TreeResolver` | [FW.54] one-pass UID→DID→Tree: create (`CLUSTER_ID`+`TREE_FAMILY_ID`) / re-flash (паспорт збігся) / bind (legacy) / DID-колізія → `CollisionError` (quarantine, [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA)); peaq НЕ enqueue'ить (offline-фабрика) |
| `FactoryFlashing::UidReadout` | [FW.54] толерантний парсер `-r32 0x1FFF7590`-виводу → три UID-слова / 24-hex (формат live-CLI = bench-confirm) |
| `FactoryFlashing::MasterKeySource` | Джерело master-ключа: `EnvAdapter` (з `Security::WeakKeyDetector`), `BitwardenAdapter` skeleton; fetched ключ живить HKDF через `Session` (не лише preflight-гейт) |
| `FactoryFlashing::CommandBuilder` | Емісія `STM32_Programmer_CLI` команд: `preflight_commands` (connect + UID-read, обидві гілки) + per гілка A/B (KEYL/LSED/KOTA/**KEYB** slots для Tree; **KEYL(=KEYB-значення)**/KEYC/EDSK для Gateway — FW.2 (в): до 2026-07-03 Gateway KEYL не писався взагалі → фабрична Королева цеглилась на boot; RDP level) |
| `FactoryFlashing::Executor` | Subprocess-запуск: dry-run за замовч.; `Open3.capture3` при `dry_run: false`, stop-on-first-fail |
| `FactoryFlashing::SecureElementProvisioner` | Гілка B skeleton: `atcab_*` slot-writes + config/data-zone lock (raw key bytes scrubbed; rename → SE050 у SE050-MIGRATION) |
| `FactoryFlashing::AuditTrail` | `AuditLog(action:"factory_flash")` chain-hashed + `MaintenanceRecord(:installation)` |

---

## 💰 9. Домен: Фінансові Оракули (Finance Oracles)

**Сервісів у цьому домені немає — протокол курсу SCC не тримає.** Цінового читача в дереві нуль: ні DEX-quoter'а, ні governance-параметра fallback-ціни. Система міряє **кількість** (SCC + growth_points), а вартість множить сам споживач — дім питання «1 SCC = $Y» = [`00_04 §3`](00_04_Nature_as_a_Service_Contracts), єдиний доларовий якір у каноні = сценарна крива [`02_06 §7.3`](02_06_Unit_Economics_and_BOM) (вхід payback-моделі, **не** курс).

⛔ **Перш ніж заводити сюди сервіс — перевір, що замовник ціни РЕАЛЬНИЙ.** Ціна дешева на вигляд (DEX-quoter read + кеш) і дорога наслідками: вона одразу тягне governance-ключ, fallback-число, політику кешу й мітку «оракул мовчить», а на юридичному боці — активний secondary-market price-discovery як Howey-фактор ([`protocols/legal/securities_review.md`](protocols/legal/securities_review.md) F9). Номер §9 лишається живою адресою (§10–§13 цитуються з коду за номером — не перенумеровувати).

---

## 🌐 10. Домен: Мультичейн — Паралельні Рейки (Multi-chain)

### `Solana::MintingService`

| | |
|---|---|
| **Файл** | `app/services/solana/minting_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | USDC мікро-винагороди на Solana. **[MAINNET READY]** Guard: `verified_by_iotex?` + `oracle_status_fulfilled?` (enum method). **[BLOCKER-1]** `verify_oracle_balance!` — перевіряє баланс SOL оракула через `getBalance` RPC; raises при `< MIN_ORACLE_BALANCE_LAMPORTS` (0.05 SOL = 50M lamports). Розраховує `reward_lamports = 10_000 + (growth_points × 100)`, де `growth_points` — stored value [FW.29-PACK] 0..62 (wire 5-bit × 2 backend upscale). Діапазон: 10_000–16_200 lamports (0.01–0.0162 USDC). 4-крокова транзакція: `getLatestBlockhash` → бінарний SPL Token Transfer Message (compact-u16 + account keys + Ed25519-header) → Ed25519 підпис через `Ed25519Crypto::SigningService` (hex-keypair з `SOLANA_WALLET_KEYPAIR`) → `sendTransaction` (base64). ATA отримувача резолюється динамічно через `getTokenAccountsByOwner` RPC. `SOLANA_WALLET_KEYPAIR` (mandatory), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS` — обов'язкові ENV. **[E.61] Batch-режим:** при ненульовому `solana_batch_threshold_usdc` (SystemParameter) `mint_micro_reward!` лише акумулює винагороду per-wallet у Kredis (виплату робить `Solana::BatchPayoutService`); `batch_payout!` шле один `transferChecked` (idx 12, валідує mint+decimals). Поріг 0 → per-event (backward-compat). **[ARCH.51]** per-event теж idempotent (дзеркало batch): sign-first durable `:pending` intent (`record_event_intent!`) ДО broadcast → `mark_as_sent!`; на retry — per-telemetry reconcile (`unsettled_event_tx` на `chainlink_request_id` + `signature_status`: `:confirmed`→skip, `:not_found`→`manual_review`, `:processing`→skip) замість сліпого re-pay. Закрив broadcast↔DB crash-window double-pay (раніше єдиний broadcast-ПОТІМ-record money-path). Scale-обґрунтування — [`05_01 §8`](05_01_Multichain_Architecture). **[INF.22]** RPC fallback cascade: `execute_rpc_call` пробує `SOLANA_RPC_URL` → `SOLANA_RPC_URL_FALLBACK_1/2` по черзі при `Web3::HttpClient::RequestError` (timeout/429/conn); per-service circuit-breaker "Solana" (3 збої/60с). Порожні fallback → single-RPC (skip-clean). Solana ≠ EVM → НЕ `Web3::ResilientClient` (той обгортає `Eth::Client`); durable-захист (intent+reconcile ARCH.45/51) означає, що вичерпаний каскад лише затримує. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → Solana RPC JSON API (`getLatestBlockhash`, `getTokenAccountsByOwner`, `sendTransaction`) |
| **Вихід** | `tx_signature` (String). Створює `BlockchainTransaction` зі статусом `:sent` (очікує `BlockchainConfirmationWorker`). |

### `Solana::BatchPayoutService` [E.61]

| | |
|---|---|
| **Файл** | `app/services/solana/batch_payout_service.rb` |
| **Вхід** | — (cron-driven через `SolanaBatchPayoutWorker`) |
| **Що робить** | Gas Optimizer для Solana мікро-винагород. Обходить акумульовані в Kredis гаманці (`solana_pending_payouts:<wallet_id>`) і виплачує тих, чия сума перетнула `solana_batch_threshold_usdc`, одним `transferChecked` ATA→ATA через `Solana::MintingService#batch_payout!`. Per-wallet `Kredis.lock`; ізоляція збоїв per-wallet; залишок зниклого гаманця скидається. Поріг 0 → no-op (власник виплат — per-event шлях). **[ARCH.45]** durable intent-marker (`:pending`→`:sent`, signature обчислено до broadcast) + `in_flight` guard: на наступному циклі `reconcile_in_flight` звіряє on-chain (`getSignatureStatuses`) замість сліпої повторної виплати; Kredis-settle **confirm-gated** (decrement лише після on-chain confirm, за сумою самої tx → concurrent надбавки виживають). Закриває double-pay crash-window. Scale-обґрунтування — [`05_01 §8`](05_01_Multichain_Architecture). |
| **Зовнішні виклики** | `Solana::MintingService#batch_payout!` → Solana RPC (`transferChecked`) |
| **Вихід** | — (side-effect: `BlockchainTransaction` `:sent` + Kredis decrement) |

### `Celo::CommunityRewardService`

| | |
|---|---|
| **Файл** | `app/services/celo/community_reward_service.rb` |
| **Вхід** | `cluster` (Cluster AR instance), `target_date` (Date) |
| **Що робить** | ReFi incentive: відправляє 5 cUSD організації якщо `stress_index <= 0.2` та немає fraud. ERC-20 `transfer` на Celo. **[SLASH-1, founder-ратифікація]** vm_error-день (софт-збій прошивки → `stress_index` 0.0) СВІДОМО reward-eligible: «не карати жертву» нашого бага, сенсорна половина кадру жива, емісія захищена per-frame (vm_error → 0 GP), vm_error-маскування домінується фейк-homeostasis (DCI/attest-домен); хронічний vm_error = ops-тріаж (`firmware_fault`), не reward-стеля (пін-spec «stays eligible on a vm_error day»). **[ARCH.50]** Money-path-hardened (4-й ARCH.45 сиблінг): durable `:pending` intent ПЕРЕД broadcast + dedup на ЛОГІЧНИЙ `reward_date` (НЕ `created_at`) ВСЕРЕДИНІ Kredis-lock (закрив детермінований daily double-pay #0 + crash-window #1 + TOCTOU #2) + 2-case rescue (deterministic RpcError→`fail!` re-payable БЕЗ shared-breaker count #4; ambiguous nonce→`:pending`; transient→re-raise) + chain-prefix lock (`lock:web3:celo:oracle:`) + dedicated `ORACLE_CELO_PRIVATE_KEY` (fallback base); reconcile через `CeloConfirmationWorker` (revert→re-payable #3). **[BLOCKER-1]** `verify_oracle_balance!` — перевіряє баланс CELO оракула через `get_balance`; raises при `< MIN_ORACLE_BALANCE_WEI` (0.05 CELO). **[E.49]** RPC fallback cascade: `Web3::RpcConnectionPool.client_for("CELO_RPC_URL", fallback: DEFAULT_RPC_URL, fallback_env_keys: RPC_FALLBACK_ENV_KEYS)` де `RPC_FALLBACK_ENV_KEYS = %w[CELO_RPC_URL_FALLBACK_1 CELO_RPC_URL_FALLBACK_2]`. При наявності щонайменше двох заповнених URL'ів повертається `Web3::ResilientClient` з circuit breaker (3 збої / 60с cooldown) — автоматичний failover при HTTP 429 / `Net::ReadTimeout` / `Errno::ECONNREFUSED`. Якщо fallback ENV порожні — поведінка без змін (одиночний `Eth::Client`). |
| **Зовнішні виклики** | Celo RPC (`CELO_RPC_URL` + опц. fallback ENVs), `Web3::RpcConnectionPool`, `Web3::WeiConverter` |
| **Вихід** | `tx_hash`/`nil`. **[ARCH.50]** Створює `:pending` `BlockchainTransaction` (`reward_date`-keyed, sourceable: cluster) ПЕРЕД broadcast; `mark_as_sent!` після; `CeloConfirmationWorker` дорезолвить `:confirmed`/`:reverted→:failed`(re-payable). |

### `KlimaDao::RetirementService`

| | |
|---|---|
| **Файл** | `app/services/klima_dao/retirement_service.rb` |
| **Вхід** | `wallet` (Wallet AR instance), **kwarg `scc:`** — величина в МОНЕТАХ SCC ([ARCH.95] ⚖️ 2026-08-25). Позиційний скаляр більше не приймається: саме та форма й дала змогу одному числу означати дві одиниці. Дім визначення одиниці — [`04_01 §6`](04_01_Data_Models_and_Entities) |
| **Що робить** | ESG carbon retirement через KlimaDAO на Polygon. Двокроковий: `approve(klima_address, amount_wei)` → `retire(amount_wei)`, де `amount_wei = scc × 10**18` (ERC-20 decimals ТОГО САМОГО SCC). Атомарний DB-блок: `esg_retired_balance += scc` — і НІЧОГО більше; балансові колонки не рухаються [ARCH.95 вісь 3]. Пише `BlockchainTransaction` із **`direction: :burn`** (вісь 2) і БЕЗ `sourceable` — погашення не є слешем. Raises `InsufficientBalanceError`, `InvalidTokenTypeError`. |
| **✅ ПРИСУД УХВАЛЕНО, гард знято** | [ARCH.95] ⚖️ 2026-08-25 (машина за делегуванням founder). Осей виявилось **чотири**, і четверта жила там, де пункт вважав закритим [ARCH.56]: гард `available_balance < amount` міряв «скільки БАЛІВ ще можна сконвертувати», а питання було «скільки МОНЕТ є». Дві протилежні поломки — гаманець, що сконвертував усе, дістав би відмову погасити наявні SCC; гаманець, що не мінтив, дістав би дозвіл спалити те, чого не має. Тепер запас читається з `blockchain_transactions.net_minted_supply(:carbon_coin)`, яка після осі (2) уже віднімає власні погашення (тому вдруге `esg_retired_balance` НЕ віднімають). Носій проти повернення на балову шкалу — пара дзеркальних пінів у спеці, мутація-перевірено. |
| **Зовнішні виклики** | Polygon RPC (2 транзакції: approve + retire) |
| **Вихід** | `nil`. Side effects: `wallet.esg_retired_balance` (МОНЕТИ) + `BlockchainTransaction(direction: :burn)`. ⛔ `balance`/`locked_balance` не чіпає — виняток із gross-визначення [`04_01 §6`](04_01_Data_Models_and_Entities) знято. |

🧾 **Доказова база офсет-сертифіката — вона ЗОВНІШНЯ, і саме тому додаткового архіву не будуємо** [BIZ.15, 2026-08-29]. Ланцюг доказу для регуляторного звіту повний і трилапий: (1) `retire(uint256)` виконується **на публічному Polygon**, тобто найсильніша ланка нам не належить і нами не редагується; (2) `BlockchainTransaction(direction: :burn)` несе `tx_hash` цієї транзакції плюс audit-trail — це наш ПОКАЖЧИК на зовнішній доказ, не сам доказ; (3) `wallet.esg_retired_balance` дає кумулятив у МОНЕТАХ, звідки tCO₂ рахується курсом ([`00_04 §3`](00_04_Nature_as_a_Service_Contracts) «Фінансові Константи»).

⛔ **Immutable-архів (Filecoin/IPFS) сюди НЕ додаємо, і це присуд, а не недоробка.** `Filecoin::ArchiveService` за побудовою архівує AI-інсайти (`analyzable_type: "Cluster"`), а копія нашого ж запису про ретайрмент не додала б жодного біта незалежності: доказ уже стоїть у ланцюзі, якого ми не контролюємо, тож IPFS-пін був би **другим дзеркалом того самого свідчення**, а не другим свідченням. 🔑 Те, що справді треба стерегти, — не наявність архіву, а щоб сертифікат посилався на `tx_hash`, а не на наш агрегат: агрегат ми пишемо самі, транзакцію — ні.

### `Polygon::HadronComplianceService`

| | |
|---|---|
| **Файл** | `app/services/polygon/hadron_compliance_service.rb` |
| **Вхід** | `wallet` (для `verify_investor!`) або `naas_contract` (для `register_asset!`) |
| **Що робить** | **KYC**: перевіряє `hadron_kyc_status` через Polygon Hadron Identity API. **RWA**: реєструє лісову ділянку як Real World Asset (ERC-3643). **[BLOCKER-04]** `WEB3_STRICT_MODE=true` → raises `ComplianceError` при відсутності `hadron_api_key` (вимкнення simulation mode у production). Без strict mode — simulation fallback для dev/test. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `HADRON_API_URL/identity/kyc/verify` або `HADRON_API_URL/assets/rwa/register` |
| **Вихід** | `verify_investor! → "approved"/"rejected"`. `register_asset! → asset_id (String)`. |

### `Treasury::MonitorService`

| | |
|---|---|
| **Файл** | `app/services/treasury/monitor_service.rb` |
| **Вхід** | — (no args) |
| **Що робить** | Централізований моніторинг газ-балансів **усіх живих Oracle-підписантів** per-wallet (`WALLETS`, один гаманець = один запис — INF.22 key-спліт): required-п'ятірка polygon/minter + polygon/slasher + solana/fee_payer + celo/rewards + ethereum/anchor, плюс **activation-gated aux** polygon/{etherisc,puro,klima} — відсутній ENV-ключ = запис пропускається (без gauge/алерту), інжект ключа = авто-моніторинг без код-зміни. **[INF.22]** Пороги читаються через `SystemParameter.current` (param_key per-wallet: `oracle_min_balance_{matic,matic_slasher,sol,celo,eth}` + aux `oracle_min_balance_matic_{etherisc,puro,klima}`, 24h-кеш — без DB-хіту на цикл) і governance-aware (оновлювані через `ProtocolParameters.sol` → `Governance::ParameterSyncWorker`); значення в коді = DEFAULT-fallback, не зафіксовані константи (MATIC/SOL/CELO 0.05, ETH 0.01 — weekly anchoring). Для EVM-мереж: `Eth::Key` → `client.get_balance`. Для Solana: `Web3::HttpClient.post` → `getBalance` RPC. `RPC_TIMEOUT = 10с` на кожен гаманець. Результат: масив Hash з `{ network, signer, currency, balance_raw, balance_human, ratio, status (:healthy/:critical/:error) }`. |
| **Зовнішні виклики** | `Web3::RpcConnectionPool.client_for` (Polygon, Celo, Ethereum), `Web3::HttpClient.post` (Solana RPC) |
| **Prometheus** | `ORACLE_BALANCE` (gauge per network+signer), `ORACLE_BALANCE_RATIO` (gauge per network+signer, < 1.0 = critical), `TREASURY_CHECK_ERRORS_TOTAL` (counter per network/signer/error_type) |
| **Side Effects** | `EwsAlert.create(:system_fault, :critical)` при balance < threshold — **дедуп'нутий по ПАРІ (мережа, підписант)** [ARCH.82]: без нього порожній гаманець давав рядок щоцикла, а крон ходить `*/15` при восьми підписантах (до 32 нових `active` critical на годину). Ключ саме пара, не `message_key`: гаманці порожніють незалежно, тож спільний ключ сховав би сім аварій із восьми. **[G1/G2]** Той самий 15-хв прохід семплить money-path gauges (`BLOCKCHAIN_MANUAL_REVIEW_DEPTH` / `LIMBO_LOCKED` / `CHAIN_AUDIT_DELTA`). **[ARCH.62]** `detect_mint_volume_anomaly!`: gauge `MINT_VOLUME_WINDOW_SCC` (rolling-1h per token_type, partition-pruned) vs `:mint_volume_hourly_max_scc` (inert 0=off; gauge живий завжди) → **dedup'нутий** `system_fault`-алерт (один активний на token_type) + per-token Kredis circuit-trip (`mint:circuit_broken:<token>`, TTL 1h) за `:mint_circuit_breaker_enabled`. 🔴 **[ARCH.82] Обидва роди алертів цей же прохід і ЗАКРИВАЄ** (`resolve_recovered_balance_alerts!` · `resolve_mint_volume_alert!`) — обовʼязково, бо рядок безкластерний і людського шляху до нього не існує (механіка + стелі → [`04_01 §7`](04_01_Data_Models_and_Entities)). Асиметрія, яку це прибрало, була ТУТ: circuit-trip має TTL і сам відпускається, а алерт про той самий сплеск не відпускався ніколи. Порядок у `perform` навмисний — спершу підняти нові, тоді зняти одужалі |
| **Вихід** | `Array<Hash>` — звіт per-wallet (required-п'ятірка + активовані aux) |

### `Treasury::MintBatchCollectorService`

| | |
|---|---|
| **Файл** | `app/services/treasury/mint_batch_collector_service.rb` |
| **Вхід** | — (no args) |
| **Що робить** | **[NEW]** Sidekiq-level агрегація pending `BlockchainTransaction` записів для оптимізації газу. Збирає `status: :pending, blockchain_network: "evm"`, групує за `token_type` (SCC/SFC), розділяє на urgent (старше `MAX_PENDING_AGE_MINUTES=30хв` — відправляє негайно) та standard (чекає `MIN_BATCH_SIZE=5`). Делегує `BlockchainMintingService.call_batch(ids)` пакетами по `OPTIMAL_BATCH_SIZE=100` (= `MAX_BATCH_SIZE`, контракт-cap; дім [`05_03`](05_03_Tokenomics_SCC_and_SFC)). Gas savings: `batchMint(100) ≈ 30-40%` дешевше ніж `100 × mint()`. Працює паралельно з `MintCarbonCoinWorker` (oracle-driven immediate). `MAX_TRANSACTIONS_PER_RUN = 1000`. |
| **Зовнішні виклики** | `BlockchainMintingService.call_batch` |
| **Вихід** | `nil`. Side effect: транзакції відправлені пакетами. |

### `Ethereum::StateAnchorService`

| | |
|---|---|
| **Файл** | `app/services/ethereum/state_anchor_service.rb` |
| **Вхід** | — (no args) |
| **Що робить** | Тижневий SHA-256 state root → Ethereum L1 з повним аудит-трейлом. **[BLOCKER-2]** Перед TX створює `EthereumAnchor` запис (status: `pending`) для crash recovery. **[BLOCKER-3]** Gas management: `DEFAULT_GAS_LIMIT=100_000` (перекривається `ETHEREUM_GAS_LIMIT`) — і ЛИШЕ він. ⊕ **[ARCH.62, 2026-08-28]** fee-константи звідси ЗНЯТО разом із присвоєнням: `ETHEREUM_MAX_FEE_GWEI`/`ETHEREUM_PRIORITY_FEE_GWEI` (100/2) читає тепер `Web3::FeePolicy`, яка накладається на МІСЦІ НАРОДЖЕННЯ клієнта (`RpcConnectionPool#build_client`) — див. рядок `Web3::FeePolicy` вище. `gas_limit` лишився тут свідомо: він властивість ЦЬОГО виклику (~45k на `storeStateRoot`), а не мережі. **[BLOCKER-4]** Inline guard: перевіряє ETH-баланс wallet (`DEFAULT_MIN_ANCHOR_BALANCE_ETH = 0.01 ETH`, governance-aware через `SystemParameter(:oracle_min_balance_eth)`) перед TX; при недостатньому балансі — `EthereumAnchor.status = failed` + raise. **[BLOCKER-6]** `generate_state_root` обгорнуто в `transaction(isolation: :repeatable_read)` (SNAPSHOT ISOLATION) і повертає `{ state_root, total_growth_points, total_scc_supply, total_sfc, active_tree_count, chain_hash, anchored_at }` — усі сім компонентів зберігаються в `EthereumAnchor` для незалежної верифікації через `EthereumAnchor#verify_state_root`. **[E.53/E.54/ARCH.97]** Formula: `SHA256("#{total_growth_points}\|#{total_sfc}\|#{active_tree_count}\|#{chain_hash}\|#{anchored_at.iso8601}\|#{total_scc_supply}")`. **[ARCH.97]** Перше поле — БАЛИ офчейн-леджера (доти стояло під іменем `total_scc`, тобто монети), останнє — чинний supply з One-Home `net_minted_supply`. `total_sfc` (sum of confirmed `forest_coin` `BlockchainTransaction.amount`) додано бо governance-токен впливає на quorum/voting power у DAO. `active_tree_count` (`Tree.active.count`) додано як метрика покриття екосистеми — різка зміна без audit events є сигналом маніпуляції. **[DOUBLE-ANCHOR GUARD]** Перед створенням нового state_root перевіряє `EthereumAnchor.in_flight` (status `:pending` або `:sent` за останній тиждень): якщо знайдено `:sent` — повертає його без re-send (TX може бути в мемпулі); якщо `:pending` — продовжує з тим самим state_root для crash-recovery. На `Net::ReadTimeout`/`Net::OpenTimeout`/`IOError` зберігає status `:pending` (TX may be in-flight) — наступний ретрай резюмує цей самий anchor. Після успішної TX — `anchor.update!(status: :sent, tx_hash:)` + enqueue `EthereumAnchorConfirmationWorker` (**[ARCH.66]** — поллер доводить `:sent`→`:confirmed`/`:failed`/`:manual_review`; дім lifecycle [`05_04 §5.1`](05_04_Ethereum_L1_State_Anchor)). **[ARCH.66 companion]** nonce персиститься у `ethereum_anchors.nonce` **перед** `transact` → resume ре-броадкастить same-nonce (не N+1); node-rejection `nonce too low`/`already known` на resume → `escalate_pending_ambiguous!`(`:manual_review`, tx_hash lost), не `:pending`-orphan. |
| **Зовнішні виклики** | Ethereum Mainnet RPC (`ALCHEMY_ETHEREUM_RPC_URL`), `StateRootAnchor` contract (`storeStateRoot(bytes32)`) |
| **Вихід** | `EthereumAnchor` (AR instance). Raises при недостатньому балансі, timeout або connection error. |

### `Filecoin::ArchiveService`

| | |
|---|---|
| **Файл** | `app/services/filecoin/archive_service.rb` |
| **Вхід** | `audit_log` (AuditLog AR instance) |
| **Що робить** | Архівує AuditLog до IPFS/Filecoin через Pinata API. Payload: chain_hash, metadata, добове зведення `AiInsight` кластерів організації. 🔒 **[SEC.18, DPIA M6] Вміст `metadata` має ОГОЛОШЕНУ стелю:** ключ поза `AuditLog::ARCHIVED_METADATA_KEYS` у пін не їде — `UndeclaredMetadataError`, бо запінене не відкликається. Відмова гучна свідомо: тихий стрип змінив би сам доказ, а `archive_requested_at` лишається, тож `FilecoinReconcileWorker` підбирає й стан видно в `FILECOIN_REPIN_TOTAL`. ⚠️ Судяться КЛЮЧІ, ніколи ЗНАЧЕННЯ — дім переліку [`04_01 §11`](04_01_Data_Models_and_Entities). 🔒 **Другий вільнотекстовий канал того самого піна закрито 2026-08-27 ІНШИМ ліком:** `telemetry_summary` не є `metadata`, тож під стелю вище не підпадає за побудовою — і `AiInsight#summary` знято з піна зовсім, бо інтерполював `cluster.name` (вільний рядок людини). Магнітуда, що жила лише в реченні, піднята в структуру (`reasoning.fraud_trees`); проза лишається в БД і на екрані. Ідемпотентний: `return if ipfs_cid.present?`. Клас-метод `self.pin_json!(content, name:, keyvalues:)` [E.60] = One-Home Pinata-виклик — юзають audit-шлях (цей сервіс) і `TelemetryArchiveBatchWorker` (телеметрія-батч-пін). ⚡ **[ARCH.57] Глобальний ланцюг НЕ несе зведення:** `audit_logs.organization_id` легально `nil` («подія платформи», [`04_01 §7`](04_01_Data_Models_and_Entities)), а `where(organization_id: nil)` — це `IS NULL`, тобто ФІЛЬТР, що ЗБІГАЄТЬСЯ з org-less кластерами, не порожня множина; тому `build_telemetry_summary` оголошує стан явно (`return nil`), а не покладається на те, що таких кластерів сьогодні нуль. Правило-дім те саме, що на policy-поверхнях — `ApplicationPolicy#no_acting_organization?` [UI.7]. Ціна саме тут: артефакт іде в IPFS **як доказ**. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `FILECOIN_PINNING_API_URL` (Pinata) |
| **Вихід** | `cid` (String). Оновлює `audit_log.ipfs_cid`. |

### `Filecoin::VerificationService`

| | |
|---|---|
| **Файл** | `app/services/filecoin/verification_service.rb` |
| **Вхід** | `audit_log` (AuditLog AR instance) |
| **Що робить** | Верифікує цілісність: завантажує JSON з IPFS за `ipfs_cid`, порівнює `chain_hash` з локальним. |
| **Зовнішні виклики** | `Web3::HttpClient.get` → `FILECOIN_GATEWAY_URL/{cid}` |
| **Вихід** | `{ verified: Boolean, cid:, chain_hash: }` або `{ verified: false, local_hash:, remote_hash: }`. |

### `Filecoin::CidGenerator`

| | |
|---|---|
| **Файл** | `app/services/filecoin/cid_generator.rb` |
| **Що робить** | Детермінований self-verifying **CIDv1** (multiformats: `raw 0x55` + `sha2-256` multihash) для довільного payload **без** звернення до IPFS-шлюзу — той самий вміст завжди дає той самий CID (`bafkrei…`), тож архів неможливо ex-post підмінити непомітно (верифікатор перераховує CID локально й порівнює з тим, що пінилося). Leaf-рівень E.60 ([`05_02`](05_02_Proof_of_Growth_Pipeline)). |
| **Зовнішні виклики** | — (in-memory: SHA-256 + multiformats) |
| **Вихід** | CIDv1-рядок (`"bafkrei…"`). |

### `Streamr::BroadcasterService`

| | |
|---|---|
| **Файл** | `app/services/streamr/broadcaster_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | Real-time broadcast телеметрії у Streamr P2P мережу. Payload: `tree_id`, `peaq_did`, `z_value`, `bio_status`, `alerts` (температура, акустика). Non-blocking, non-financial. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `brubeck.streamr.network/api/v1/streams/{stream_id}/data` |
| **Вихід** | `nil`. Raises `BroadcastError` (не критично — ловиться у воркері). |

### `TheGraph::QueryService`

| | |
|---|---|
| **Файл** | `app/services/the_graph/query_service.rb` |
| **Вхід** | — (no args, class instance methods) |
| **Що робить** | GraphQL запити до The Graph subgraph (Polygon). `fetch_total_carbon_minted` — сума `carbonMintEvents.amount`. `fetch_protocol_financials` — `totalMinted`, `totalBurned` (премії — off-chain USDC з БД, `NaasContract.total_insurance_premiums`, не subgraph). |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `the_graph_api_url` |
| **Вихід** | `fetch_total_carbon_minted → Integer`. `fetch_protocol_financials → { total_minted:, total_burned: }`. |

### `Dclimate::VerificationService`

| | |
|---|---|
| **Файл** | `app/services/dclimate/verification_service.rb` |
| **Вхід** | `alert` (EwsAlert AR instance) |
| **Що робить** | **[MAINNET READY]** Супутникова верифікація EWS-алертів через dClimate FIRMS API (NASA Near Real-Time Global Active Fire, VIIRS 375 м). HTTP GET до `DCLIMATE_BASE_URL/v4/geo/grid-history/{FIRMS_DATASET}` з координатами дерева та часовим вікном ±1 день. Інтерпретація: FRP ≥ 10 МВт + confidence ≥ 50% → `:fire_confirmed`; ясне небо без аномалій → `:clear_sky_no_fire`; cloud_cover > 70% або відсутні дані → `:obscured_by_clouds`. Підтримує обидва формати відповіді: `{"data": [...]}` (JSON array) та GeoJSON `{"features": [...]}`. VIIRS string confidence (`high/nominal/low`) конвертується у числові значення. Мережеві збої (`Web3::HttpClient::RequestError`) → безпечний fallback до `:obscured_by_clouds`. Авторизація Bearer через `Rails.credentials.dclimate.api_key`. `generate_dclimate_ref` несе для аудит-трейлу метадані супутника **і ВІКНО запиту** — 🔭 [ARCH.111] вибірка мусить бути В ЗАПИСІ, а не лише в коді: оголошена константа стереже наступного програміста, а аудиторові, який тримає в руках `rejected_fraud`, вона не каже нічого («вогню немає» — а за яку добу питали?). **[INS.1] Peril-gate (вхід):** сервіс адьюдикує ЛИШЕ `fire_detected`-алерти (FIRMS = fire-супутник). Не-пожежний вхід (посуха; також `chainsaw_detected` — [SLASH-1], не страховий) → `escalate_non_fire_to_field_audit!` (`satellite_status: :inconclusive` + Field-Audit note, БЕЗ FIRMS-запиту, НІКОЛИ `rejected_fraud`/slashing — fire-двигун не адьюдикує не-пожежу; Кат-C §5, реальний drought-оракул → [`00_07` INS.1](00_07_Action_Plan_Tracker)). **3 результати (лише fire) — severity-aware:** `fire_confirmed` → InsurancePayoutWorker; `clear_sky_no_fire` → BurnCarbonTokensWorker (Slashing за фрод); `obscured_by_clouds` — **гілкується за `EwsAlert#severity`** ([E.41] ✅ shipped 2026-07-03): для `:critical` → **`escalate_obscured_critical_fire!`** — негайний Field-Audit (`satellite_status: :inconclusive`, HOLD-ить InsurancePayoutWorker, людський/DAO-вердикт; дзеркало non-fire `escalate_non_fire_to_field_audit!`/INS.1) замість 48h orbital retry (life-safety — тривога вже пішла окремо, edge panic-TX + backend alert; ⛔ дрон-bounty як Резервний Оракул — **won't-do**, підстава в [`00_07`](00_07_Action_Plan_Tracker) E.20); для `:low`/`:medium` → raise `OrbitalLagError` (Sidekiq retry, 15 спроб ≈ 35.5 год, `sidekiq_retries_exhausted` → `satellite_status: :inconclusive` для DAO audit). Implementation gap закрито: обидві гілки ескалації створюють **справжній** `EwsAlert(:field_audit)` (cluster-scoped), а не лише міняють `satellite_status` — доти повістки не існувало, і «ескалація» тільки спиняла виплату. |
| **Зовнішні виклики** | `Web3::HttpClient.get` → dClimate FIRMS API (`DCLIMATE_BASE_URL`). `InsurancePayoutWorker.perform_async` або `BurnCarbonTokensWorker.perform_async`. |
| **Вихід** | `nil`. Side effects: оновлює `alert.satellite_status` та `alert.dclimate_ref`, тригерує воркери. |

> **[E.66] Toucan-prune:** `Toucan::BridgeService` + `ToucanBridgeWorker` + `Wallet#lock_for_toucan_bridge!`/`finalize_spend!`/`toucan_bridged_balance` видалено — flow був DEAD (0 enqueue-callerів), failure-path мав money-integrity діру (без `sidekiq_retries_exhausted`, несиметричний rollback, in-flight `locked > balance` вікно). SCC→TCO2 expansion воскресає з git при E.20-go — тоді ж обов'язкові симетричний rollback + інваріант `locked ≤ balance` (гейт зафіксовано в git-історії E.66).

---

## ⚙️ 11. Реєстр Воркерів (Workers Registry)

### Пріоритети черг (9 рівнів, строге дотримання)

| Черга | Порядок (Strict) | Призначення |
|-------|-----------------|-------------|
| `uplink` | 1 (найвищий) | Вхідна телеметрія |
| `alerts` | 2 | EWS тривоги, супутникова верифікація, **лист про critical-тривогу** (`AlertMailer`) |
| `critical` | 3 | Slashing, страхові виплати, реанімація екосистеми |
| `downlink` | 4 | OTA прошивки, команди актуаторів |
| `default` | 5 | Агрегація, перевірка контрактів, токеноміка, **усі ActiveJob-джоби** (Turbo-броадкасти · ActiveStorage · `PasswordMailer`) |
| `web3_critical` | 6 | Blockchain confirmation, мінтинг, IoTeX, Chainlink |
| `web3` | 7 | peaq DID, Celo, Solana, Puro.earth |
| `web3_low` | 8 | Ethereum L1, KlimaDAO, Hadron, Governance Parameter Sync |
| `low` | 9 (найнижчий) | Аудит, Filecoin, Streamr |

> **Примітка:** Sidekiq `:strict: true` дренує черги послідовно згори-донизу. Числа — порядок дренування, не ваги.

> ⚖️ **Чергу ActiveJob-джоби обираємо МИ, а не дефолт гема** [ARCH.60/ARCH.52, 2026-08-23]. Наші воркери оголошують чергу самі (`sidekiq_options queue:`), тож правило «не міняй чергу без обґрунтування» ([`CLAUDE.md §5`](../CLAUDE.md)) їх стереже. **ActiveJob-джоби приходять із гемів БЕЗ `queue_as`** — і тоді `ActiveJob::Base.default_queue_name` мовчки кладе їх у `default`(5), тобто позаду `downlink`(4). Вимір 2026-08-23 дав **чотирнадцять** ActiveJob-нащадків, і всі чотирнадцять сиділи там, жодного ми не обирали. 🔴 **Найдорожчий наслідок — розрив ланцюга на останньому кроці:** `AlertNotificationWorker` судить про критичність у `alerts`(2), фан-аут Telegram (`SingleNotificationWorker`) теж `alerts`(2), а **єдиний формальний лист** до `billing_email` падав у `default`(5) — за чанками OTA-кампанії. Тобто пріоритет несла ухвала, а не доставка. **Присуд — довговічний канал несе пріоритет своєї події, ефемерний ні:** `AlertMailer.deliver_later_queue_name = :alerts` (обсяг — одна відправка на алерт, не N на стейкхолдерів, тож тиску на `critical`(3) немає); `PasswordMailer` лишається `default` СВІДОМО (UX, не безпека — над слешинг не піднімаємо); Turbo-редрави лишаються `default` СВІДОМО (застарілий екран оборотний перезавантаженням, а підняття перемальовки над `downlink`(4) поставило б її попереду наказу актуатору). ⚠️ **Оголошена стеля:** це призначення, а не виживання під насиченням — при безперервному `uplink`(1) strict не дренує нічого нижчого, і лік того класу інший і вже ратифікований ([`06_08 §2.5`](06_08_Resilience_and_Failover_Policy) — виділений процес). Тут закрито реалістичніший випадок: backlog `downlink`. 🔑 **Але звірка з тією топологією дала СИЛЬНІШИЙ наслідок, ніж «впорядкували чергу» (свіп 2026-08-23):** money-path процес §2.5 бере саме `critical, web3_critical, web3, **alerts**`, тож переведення листа в `alerts` переносить його через МАЙБУТНЮ МЕЖУ ПРОЦЕСІВ — після flip'у він стає недосяжним для firehose взагалі, а не лише впорядкованим усередині одного процесу. ⚠️ Дзеркало того ж факту: `PasswordMailer` і Turbo-редрави лишаються на `default`, тобто після flip'у їдуть intake-процесом разом із firehose — це **прийнята ціна** присуду «ефемерний канал пріоритету не несе», а не недогляд. 🔑 Носій — `spec/quality/activejob_queue_declaration_spec.rb`: реєстр «клас → оголошена черга», де новий нащадок валить приклад, доки чергу не ОБЕРУТЬ; окрема вісь ловить найгостріший режим відмови — оголошену чергу, якої немає в `config/sidekiq.yml` (її не слухає жоден процес, тож джоби осідають у Redis назавжди й мовчки — саме туди веде наївне «дати пошті власну чергу `mailers`», бо це і є framework-дефолт `ActionMailer::Base`). ⊕ **Чесний негатив, вартий рядка:** три з чотирнадцяти — `SolidCable::TrimJob` (кличеться `perform_now` інлайн у listener-адаптері) · `SolidCache::ExpiryJob` (`expiry_method` за замовчуванням `:thread`) · `Sentry::SendEventJob` (нуль викликачів у гемі — Sentry шле власним пулом тредів) — **ActiveJob-пускача не мають узагалі**, тож їхнє «голодування» уявне; записано, щоб наступний прохід не лікував фантом.

> ⛔ **DOC.8 — Cleanup constraint (TelemetryLog):** рядкового cleanup-воркера над `telemetry_logs` **не існує, і це присуд** (⚖️ 2026-08-21, [`00_07`](00_07_Action_Plan_Tracker) ARCH.59) — ретеншн робить ВИКЛЮЧНО дроп місячних партицій; носій заборони — `spec/quality/telemetry_retention_home_spec.rb`. Повний розбір інваріанта, який при цьому змінив адресата (дроп партиції не вміє виключати `oracle_status = 'dispatched'`, тож питання стало ШИРИНОЮ вікна й переїхало до механізму дропу), — дім [`04_01 §11`](04_01_Data_Models_and_Entities). Cross-ref: [`04_01` — TelemetryLog model warning](04_01_Data_Models_and_Entities#telemetrylog--сирий-пакет-телеметрії).

> 🔴 **Конвенція reconcile/sweeper-воркерів: НУЛЬ дій ≠ нічого не сталося** [PERF.1, 2026-08-18]. Воркер, що ітерує кандидатів і рахує ФАКТИЧНІ дії (`escalated`/`re_armed`), мусить розрізняти ДВА різні світи: «дивитись не було на що» (порожня вибірка → `return`, тиша) ⊥ «дивились на N і жоден не подіяв» (reload-гард пропустив усю вибірку → `Rails.logger.info "Розглянуто N…"`). Друге — саме той стан, який оператор мусить бачити: він настає, коли підозрілих рядків НАЙБІЛЬШЕ, а форма `return unless <лічильник>.positive?` робить воркер повністю німим саме там. Рівень `info`, не `warn` — це спостереження про здоровий тракт, не інцидент. **Дискримінатор перед тим, як застосовувати правило до чергового воркера: чи має цей мовчун ІНШИЙ спостережний канал** — `HadronKycReverifyWorker` свідомо лишається без ліхтаря, бо безумовно б'є `HADRON_KYC_PENDING_DEPTH.set(depth)`, тож його тиша не є сліпотою. Носії — по два приклади на воркер (голос на нульовій дії ⊥ тиша на порожній вибірці).

> ⚠️ **DOC-R.10 — Sidekiq Pro shims active (Phase 7 deferred upgrade):** Кодова база викликає `Sidekiq::Batch`, `Sidekiq::Limiter`, `expires_in:`, але ліцензований гем `sidekiq-pro` поки що **не в Gemfile**. `config/initializers/sidekiq_pro.rb` надає no-op shim-и щоб тести й dev-середовище не падали — у production це означає що `on(:success)` колбеки **не спрацьовують**, rate-limiter `web3_rpc 50/sec` **не діє**, а `expires_in: 5.minutes` на uplink-задачах **не TTL-ить** stale jobs. Перед billion-tree запуском треба:
> 1. Додати `gem "sidekiq-pro", "~> 8.1"` (потребує license token у `BUNDLE_GEMS__CONTRIBSYS__COM`). 🔴 **Цей крок НЕ нейтральний — він озброює `expires_in`, і на uplink це ТИХА ВТРАТА БАЛІВ** [ARCH.59, виміряно 2026-08-21]. `UnpackTelemetryWorker` веде до `TelemetryUnpackerService` → `tree.wallet.credit!(weighted_points)`, тобто відкинутий пакет — це незараховані `growth_points`, а не «зекономлений CPU», як стверджує коментар над самою опцією. Гірше того, [Pro-документація](https://github.com/sidekiq/sidekiq/wiki/Pro-Expiring-Jobs) прямо каже, що протухла джоба **відкидається без виконання**, а в межах батчу **рахується як success** — тож ані retry, ані DeadSet, ані батч-колбек сліду не лишать (self-masking). **Перед покупкою ліцензії ухвали долю `expires_in` на обох uplink-воркерах окремим присудом**; на alerts-парі вісь уже знято семантичним гардом `status_active?` (картки нижче), тож там опція лишається декоративною, а не несучою.
> ⛔ **Форма «зробити шим `expires_in` чинним власним middleware» відкинута ще на плані** [ARCH.59, ⚖️ 2026-08-21]. Вона озброїла б ОБИДВА uplink-сайти однаково — тобто внесла б рівно той дефект, від якого лікує: присуди на них **протилежні за побудовою**. `UnpackTelemetryWorker` веде до `Wallet#credit!` (дроп = незараховані бали), а `GatewayTelemetryWorker` штампує `last_seen_at` (дроп = лік брехні, що сліпить dead-man switch). Спільного enforcement-шару в цієї опції бути не може.
> 
> ⚠️ **`unique_for` — платний апгрейд БЕЗ власника, а не тиха дірка** [ARCH.59]. Exactly-once на money-path тримають `with_lock` + status-гарди в переходах моделі, а не цей шим — сказано коментарем у `ethereum_anchor_confirmation_worker.rb`. Живий перелік деклараторів бери **рекурсивним** грепом по `app/workers/` (`sidekiq_options.*unique_for`): неглибокий не бачить `app/workers/governance/`.
> 2. Видалити shim і замість нього у `sidekiq_pro.rb` зробити `raise "sidekiq-pro required" unless defined?(Sidekiq::Pro)`. ⚠️ **Форма кроку покриває не все, що обіцяє:** шимляться лише `Sidekiq::Batch` і `Sidekiq::Limiter` (класи), а `expires_in` — **опція `sidekiq_options`**, тож шима для неї не існує й `raise ... unless defined?` її не бачить за побудовою. Шапка `sidekiq_pro.rb` перелічує її поруч із `Batch`, і саме це читається як «покрито».
> 🔴 **ПЕРИМЕТР «колбеки не спрацьовують» виміряно поіменно 2026-08-21 [ARCH.59], і він РОЗПАДАЄТЬСЯ НАВПІЛ — саме тому загальна фраза вище читалась як рівномірна деградація, якою вона не є.** Шапка `sidekiq_pro.rb` при цьому стверджує, що шими «просто делегують виконання без обмежень — вся бізнес-логіка залишається ідентичною, лише enforcement-механізми відключені»: для `Limiter` це правда (rate-limit і Є enforcement), для `Batch` — ні, бо колбек не enforcement, а гілка тракту. Двоє з п'яти споживачів мають НЕЗАЛЕЖНИЙ пускач і не постраждали: `MintCarbonCoinWorker` (батч-мінт однаково збирає `MintBatchCollectorWorker`, cron `*/5`) і `ClusterHealthCheckWorker` (власний cron `0 2 * * *`). Троє дублера НЕ мають:
> - **КЕНОЗИС-очищення сирої телеметрії ⛔ ЗНЯТО ⚖️ 2026-08-21** ([`00_07`](00_07_Action_Plan_Tracker) ARCH.59). Тут стояв рядковий `delete_all` по вікну 7 днів, чий єдиний продовий виклик жив у мертвому Batch-колбеці — тобто механізм був недосяжний, а покупка Pro-ліцензії озброїла б його МОВЧКИ, без окремого рішення. Ретеншн тепер має РІВНО ОДИН механізм — дроп місячних партицій ([`04_01 §11`](04_01_Data_Models_and_Entities); самого дропу ще немає — [`00_07`](00_07_Action_Plan_Tracker) ARCH.70), і другого свідомо не буде: він зробив би `TelemetryArchiveBatch.retention_expired` неоднозначним, тобто зіпсував би єдиний прилад, яким відрізняють ретеншн від підміни. Носій заборони — `spec/quality/telemetry_retention_home_spec.rb`.
> - **`MINT_ELIGIBLE_UNMINTED_DEPTH`** — детектор застрягання емісії [ARCH.94]. ✅ **Дім переїхав у `MintStallProbeWorker`** (cron `55 * * * *`) 2026-08-25, алерт `sn-alert-mint-stall-depth` дротовано. 🔴 **Тут доти стояло «перенести його НЕ можна», і підставу спростовано виміром — записуємо, бо саме вона тримала метрику порожньою.** Твердження було: обґрунтування ARCH.94 («після здорового циклу eligible-множина порожня ЗА ПОБУДОВОЮ») істинне рівно в момент завершення батчу, тож «чесність детектора куплена ціною його недосяжності». Три хиби: **(а)** вибір був не між колбеком і cron, а між НІЧИМ і cron — писача в проді не існувало, метрика стояла порожня від народження; **(б)** `on(:success)` означає «всі джоби завершились БЕЗ ПОМИЛОК», тож навіть із купленою ліцензією детектор мовчав би рівно в тому сценарії, заради якого існує — коли чанки емісії падають (детектор, що вимикається від власного предмета); **(в)** передумова не потребує миті завершення — `lock_and_mint!` піднімає `locked_balance` СИНХРОННО всередині `EvaluateTreeBatchWorker`, тож гаманець виходить із множини в мить обробки чанка, і зріз перед наступним циклом бачить залишок здорового проходу. Час зрізу через це несучий: зсув міняє ЗНАЧЕННЯ метрики, не лише її свіжість.
> - **`InsuranceOracleWorker`** fan-out [INS.1] — ✅ **дім переїхав у `ClusterHealthCheckWorker`** 2026-08-25. Fan-out був ЄДИНИМ enqueue-сайтом цього воркера в дереві, тобто «вмикання прапора його не оживить» — а це саме той момент, коли всі вважатимуть, що оживило. Ліком стало не нове розкладом, а перенесення ланки на споживача, який уже має власний cron (`0 2 * * *`, там же названий «defensive fallback») і вже якорить ту саму добу (`AiInsight.reporting_date` [ARCH.100]) — тож подвійний enqueue при живому Pro ідемпотентний із тієї ж підстави, що й health-recalc.
>
> ✅ **Отже сиріт у цьому периметрі більше НЕМАЄ** (2026-08-25): з трьох одну знято присудом, дві дістали незалежних пускачів. Клас лишається чинним як застереження на майбутнє — **кожен новий `batch.on(:success, …)` народжується мертвим**, тож ланка, яку туди вішають, мусить або мати власний cron, або не існувати.
>
> ⚠️ Сюїта до цієї осі сліпа за побудовою: `spec/callbacks/*` викликають `on_success` РУКАМИ, конструюючи шим-клас `Sidekiq::Batch::Status.new(…)` — перевірено реалізацію колбека, ніколи його ВИКЛИК. Той самий маскувальник, що вже одного разу тримав тут мертвий `sidekiq_retries_exhausted` під `retry: false`.
>
> 3. **[OSS — ліцензії НЕ потребує]** Розщепити Sidekiq на 4 процеси з queue-pinning (uplink окремо, web3_* окремо, critical/alerts/downlink окремо, default/low окремо) — single-process × 15 threads не витягне peak ~ N_trees / 3600 jobs/sec. Механізм рядовий (`sidekiq -q`, капсули), тож крок виконуваний сьогодні; чекає він не гема, а власного тригера — [`06_08 §2.5`](06_08_Resilience_and_Failover_Policy). ⚠️ **Периметр цього кроку РОЗХОДИТЬСЯ з домом рішення, і жоден із двох домів цього не позначав** (виміряно 2026-08-26): [`06_08 §2.5`](06_08_Resilience_and_Failover_Policy) приписує **два** процеси (money `critical, web3_critical, web3, alerts` ⊥ intake `uplink, downlink, default, …`), тут названо **чотири** з іншою розкладкою — `alerts` їде з `critical/downlink`, а не з money. Різниця не косметична: дім тримає `alerts` у money-процесі СВІДОМО, бо тією чергою їде єдиний формальний лист про critical-тривогу [ARCH.60], і в 4-процесній формі він знову опиняється за межами money-ізоляції. Яка розкладка чинна — ⚖️ у [`00_07`](00_07_Action_Plan_Tracker) ARCH.59; доти дім рішення = [`06_08 §2.5`](06_08_Resilience_and_Failover_Policy), а це число — його дзеркало, правити там.
> 4. Увімкнути `super_fetch` (zero job-loss на SIGKILL/OOM) для `uplink`, `web3_critical`, `critical`.
> 5. Увімкнути `reliable_push` у клієнті (захист enqueue-у від Redis failover).
> 6. ✅ **ЗАКРИТО 2026-08-25 — приписану форму спростовано виміром, номер лишається зайнятим** (на нього посилаються сусідні кроки). Тут стояло «збільшити Redis pool: `pool_size = concurrency + 5` (зараз буфер = 0)» — премісу купував Sidekiq ≤6, де пул був ОДИН на процес. У 8.1.7 їх **два**, і гем виводить обидва сам: капсульний = `:concurrency`, internal — окремий (heartbeat · `sidekiq-scheduler` · Web UI). Тобто буфер, заради якого просили `+5`, уже існує й стоїть окремо, а «буфер = 0» вимірювало не ту величину. Наш явний `size:` ішов через `.merge(@redis_config)` і перекривав **обидва**: прибивав капсульний до константи незалежно від `:concurrency` **і роздував internal**. 🔴 Приписана форма дефекту не лікувала, а пересувала: при `:concurrency` вищій за константу капсульний пул лишався **меншим за concurrency** — тобто `+5` зберігав саме те розчеплення, проти якого ставився, і найгостріше воно на кроці 3, який розщеплює процеси per-queue. Лік — **зняти `size:` із серверного блоку** (`config/initializers/sidekiq.rb`): стеля стала похідною, з'єднань на job-процес 30 → 25. Носій — `spec/initializers/sidekiq_spec.rb` (капсульний пул слідує `:concurrency` ⊥ internal дорівнює гемовому — другий пін порівнює з конфігом БЕЗ наших опцій, щоб не тримати число гема третім домом). ⚠️ Клієнтський `size:` лишається СВІДОМО й це не виняток із правила, а інший випадок: капсул у клієнтському процесі немає, тож вивести стелю Sidekiq'у нізвідки — вона = треди Puma + запас на Web UI (дзеркало `config/database.yml`, але БЕЗ `PUMA_MAX_IO_THREADS`: io-позначених шляхів нуль [ARCH.80], а Redis у нас managed, тож стеля з'єднань не безкоштовна).
>
> 🔴 **Перелік вище змішує ДВІ осі, і мовчання про це вже коштувало помилки на сусідній поверхні:** ліцензію потребують кроки **1 · 2 · 4 · 5** (без гема вони no-op або деструктивні — крок 2 сьогодні валив би boot, бо шим є єдиним джерелом `Sidekiq::Batch`/`Limiter`, які вантажаться на класовому рівні), тоді як **3 і 6** були чистою OSS-роботою. Отже «активація Pro» не є передумовою для двох кроків із шести, і читати перелік як однорідний блокер-пакет — хибно. ⊕ **Крок 6 закрито 2026-08-25, і залишок цієї осі — рівно один: крок 3**, який чекає не гема, а власного тригера ([`06_08 §2.5`](06_08_Resilience_and_Failover_Policy)).

> ✅ **DOC-R.11 — Cron / partition guardian:** `PartitionMaintenanceWorker` запускається `30 0 * * *` UTC (cron у `config/sidekiq.yml`), створює партиції на поточний + наступний місяць для **3 RANGE-таблиць**: `telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`. Phase 7 додав `Sentry.capture_exception` у `rescue` блок щоб тиха помилка партиціювання не призвела до `no partition of relation` PostgreSQL крешу 1-го числа місяця. Якщо додаєте нову RANGE-таблицю — внесіть її в `PartitionMaintenanceWorker::PARTITIONED_TABLES` І оновіть `spec/workers/partition_maintenance_worker_spec.rb` (очікуване число OK-ліній = `tables × 2 months`). ⊕ **[ARCH.70] Той самий прохід семплить РІСТ** (`silkennet_partitions` · `silkennet_partitioned_table_bytes` · штамп свіжості) **і ПОЛОМКУ** (`silkennet_partition_default_occupied` — непорожній DEFAULT-лист незворотно блокує створення партиції свого місяця; рунбук [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup)) — дім приладу тут, бо `PARTITIONED_TABLES` уже живе в цьому воркері, а факт глобальний (одна БД), тож семпл іде в job-процесі, а не на скрейпі. 🔴 Вимірювання свідомо стоїть у ВЛАСНОМУ `rescue` і не піднімається у критичний: зовнішній інкрементить P0-лічильник збоїв і re-raise'ить, тож виняток ПРИЛАДУ інакше давав би пейдж «партиція може бути відсутня» + Sidekiq-ретрай уже виконаного DDL. Пороги й підстави — [`06_03`](06_03_Prometheus_Observability) + `deploy/grafana/alerts/silkennet-alerts.yaml`.

---

### 📡 Uplink — Вхідна Телеметрія

#### `UnpackTelemetryWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `uplink` |
| **Retry** | 3; 🔴 **`expires_in` СВІДОМО відсутній** [ARCH.59, ⚖️ 2026-08-21] — цей воркер веде до `Wallet#credit!`, тож дроп протухлої джоби = незараховані `growth_points`, а Pro рахує такий дроп як success (сліду не лишається). Запобіжником була відсутність гема, і крок 1 DOC-R.10 зняв би її мовчки. Пін на відсутність — `spec/workers/unpack_telemetry_worker_spec.rb` |
| **Тригер** | CoAP daemon (`lib/daemons/`) при отриманні UDP-пакета |
| **Вхід** | `encoded_payload` (Base64), `sender_ip` (String), `gateway_uid` (String, опціонально), `received_at_iso` (String, опціонально — **[ARCH.41]** ISO-8601 момент прийому; обидва ПРОДОВІ enqueuer'и передають його явно, `nil` лишається легальним для bench/HIL) |
| **Сервіси** | `TelemetryUnpackerService.call` (+ kwarg'и `gateway_attested:` і `received_at:` — другий несе добу cold-derive, **[ARCH.41]**) |
| **Side Effects** | **[L1 QATT]** Детект підписаного конверта за residue довжини → Ed25519-verify проти `HardwareKey.ed25519_public_key_hex` **ДО** decrypt (wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)): invalid → drop + `attest_bad_signature`; nonce = **двофазний owner-маркер [ARCH.45]** — claim `SET NX <jid>` перед unpack, finalize `"done"` після успішного `TelemetryUnpackerService.call`; crash-retry (той самий jid) = resume, чужий jid/`done`/легасі → drop `attest_replay` (M2M-патерн + Solid-Cache fallback `QATT_NONCE_FALLBACK_TOTAL`, дзеркальний в обох фазах); signed-без-pubkey → L0 + `attest_no_pubkey`; валідний → strip конверта + `gateways.last_attested_at` + **[ARCH.54]** `enqueue_envelope_health` (пульс з підписаного health-блоку → `GatewayTelemetryWorker`; ct=0 heartbeat → unpack legально скипається). Далі AES-256-CBC дешифрування (Dual-Key) + Turbo Stream broadcast у `telemetry_feed` (org-скоуплений стрім, імʼя з дому `TurboStreams::Name`). ⚠️ Сирого `ActionCable.server.broadcast` тут БІЛЬШЕ НЕМА — знято UI.4 2026-07-27 разом з усім raw-ActionCable дерева (споживача не існувало; сторожа — `spec/security/no_raw_action_cable_spec.rb`). ⚠️ Тут як підстава стояло «`app/channels/` відсутній» — вона більше не чинна (`ApplicationCable::Connection` шипнуто SEC.25 Ф1 2026-07-28) і була слабкою вже тоді: `/cable` монтує сам движок. Заборона тримається на іншому — сире імʼя каналу не має поверхні авторизації взагалі |

#### `GatewayTelemetryWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `uplink` |
| **Retry** | 2, `expires_in: 5.minutes` — інертний на Sidekiq OSS (активується лише з Pro). ⚠️ Тут опція лишається СВІДОМО, на відміну від `UnpackTelemetryWorker` [ARCH.59, ⚖️ 2026-08-21]: `mark_seen!` штампує `last_seen_at = Time.current`, тобто затримана джоба «оживляє» шлюз заднім числом і сліпить dead-man switch — дроп тут ЛІКУЄ брехню, а не створює втрату |
| **Тригер** | **[ARCH.54]** `UnpackTelemetryWorker#enqueue_envelope_health` — пульс з ПІДПИСАНОГО health-блоку QATT-v2 (лише `:attested`-гілка; DID=0-sentinel retired — [`03_02 §7`](03_02_Queen_Gateway_Firmware)) |
| **Вхід** | `queen_uid` (String), `stats` (Hash: uptime_min, cifo_fill, lora_rx_drops, coap_fail_count, cellular_signal_csq — nil = «модем не відповів», flags) |
| **Сервіси** | Немає — пряма робота з `Gateway`, `GatewayTelemetryLog` |
| **Side Effects** | Створює `GatewayTelemetryLog` (voltage/temp — nullable до ADC-тракту). `mark_seen!` без voltage. `critical_fault?` (weak-CSQ / `coap_fail ≥ 10` / temp-плечі ❄️ ЗАМЕРЗАННЯ T<−20°C · 🔥 ПЕРЕГРІВ T>65°C — `format_health_message` дає специфічний текст алерту; temp-гілка **data-starved** до HW.16-hardware: v2-пульс температуру не несе, «Королева без ADC» ARCH.54) → `EwsAlert(system_fault)` з анти-спам guard'ом по cluster-level алертах кластера (`tree_id: nil` — **[SLASH-1]** стоячий tree-scoped `system_fault` (fraud / power-loss / hardware-decay, авто-резолвера нема) НЕ глушить новий gateway-fault; залишковий конфлат з cluster-level писарями (`Actuator`, slashing-failure) → типова декомпозиція кошика [`00_07`](00_07_Action_Plan_Tracker) SLASH-1) → (via `after_create_commit` Transactional Outbox) → `AlertNotificationWorker.perform_async`. |

#### `DeviceEventWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `uplink` |
| **Retry** | 2 |
| **Тригер** | **[SEC.21 L1]** CoAP-маршрут `PUT device/event/<uid>` (`CoapGate`) — Королева форвардить рідкісні uplink-події 0x57, які НЕ є станом (canary-trip); телеметрія їх не несе |
| **Вхід** | `encoded_payload` (Base64: підписаний L1-конверт `[ver:1][queen_unix_ts:4][count:1][records:N×7][sig:64]`, `record=[did:4][code:1][soldier_seq:2]`), `gateway_uid` (String) |
| **Сервіси** | `Ed25519Crypto::SigningService.verify`, `EwsAlert` |
| **Side Effects** | **L1 gateway-origin verify** (проти Королевиного `HardwareKey.ed25519_public_key_hex` — той самий registry, що QATT+M2M; msg=`SLKN-QEVT1`‖uid_len‖uid‖body) — **Rails LoRa-ключа НЕ торкається** (per-Tree KEYL ≠ cluster-ключ, яким Королева шифрувала; blind-forward давав key-mismatch fail-open). Невалідний підпис/чужий ключ → drop. Anti-replay = SHA256(sig) SETNX TTL 25h (Королевин sig монотонний — не Солдатів per-boot seq). Парс cleartext-records → per-record `EwsAlert(firmware_canary_trip, critical, tree:)` (uniqueness `[tree,type,status]` = один активний/дерево). Trust L1-observational ([`03_05 §2.2а`](03_05_Hardware_Symmetric_Crypto_and_Security)): подія НІКОЛИ не рухає money-path — лише ops-алерт (slash-виключення дзеркалять firmware_fault). Wire-дім `firmware/common/device_event.h §Шар 2`. |

#### `GatewayStalenessSweepWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 2 · cron `*/5 * * * *` |
| **Тригер** | Sidekiq-cron — **[ARCH.54 Шар 0]** dead-man switch Королеви ([`06_08 §1.3`](06_08_Resilience_and_Failover_Policy)) |
| **Вхід** | — |
| **Сервіси** | Немає — `Gateway.offline`/`online` скоупи + AASM |
| **Side Effects** | offline у робочих станах → `report_fault!` + критичний `EwsAlert(queen_offline)` (анти-спам по кластеру; skip: maintenance, `last_seen_at` nil); повернення в ефір → `recover!` + машинний auto-resolve ОБОХ comms-типів (`resolve_comms_alerts`: queen_offline + queen_uplink_lost — Helium-SOS без нього латчився вічно); attest-lapse (>24h без QATT-підпису при online) → warn+gauge; **[ARCH.59] залипла OTA — ТРИ предикати, і вони ловлять три різні поломки:** (1) `state=:updating` довше за `OTA_STUCK_MARGIN` = 24 год · (2) `:updating` без якоря `ota_started_at` (backstop проти стану, якого живий код не створює — умів лише мертвий `OtaTransmissionWorker`; межа по `updated_at`) · (3) **«затаргечений, але не анонсований»** — `pending_firmware_id IS NOT NULL` при стані НЕ-`updating` і застарілому якорі: кампанію записав диспетчер, а hint не пішов ЖОДНОГО разу. → `finish_update!` (**лише якщо `updating?`** — на ногу (3) він кинув би `AASM::InvalidTransition`, rescue проковтнув би його, і кампанія лишилась би висіти при «виконаному» проході) + зняття `pending_firmware_id`/якоря + `EwsAlert(system_fault, medium, message_key: queen_ota_stuck)`, дедуп по `uid`. **[ARCH.75] пʼята нога — недоставні накази:** `ActuatorCommand.pending` актуаторів `faulty`-Королеви → `fail!` + броадкаст бейджа, лічильник у лог-рядок (`cmd_reaped`). Метрики: `gateways_offline_total`, `gateways_faulty`, `gateway_attest_lapsed`. |
| **Стелі [ARCH.59]** | 🔴 Вихід — `finish_update!`, а НЕ `report_fault!`: `faulty` стоїть у тому ж списку виключень `Gateway.ota_deployable`, тож міняв би одну блокуючу причину на іншу. Кампанія знімається (повторний деплой ухвалює людина — «не автоматизувати мовчки»), версія прошивки НЕ чіпається, тож `idle` не стверджує успіху. ⚠️ Вікно 24 год виведене з каденсу (`QUEEN_OTA_FETCH_PER_FLUSH` = 4 чанки/флаш, флаш ≈ год, чанк 512 B → поточний образ ≈ 2 год), але **нижньої межі каденсу флашу не існує** (`cache_count > 0 \|\| ed25519_ready` — [`ARCH.75`](00_07_Action_Plan_Tracker)), тож це вікно ВІДМОВИ від кампанії, не обіцянка встигнути |
| **Стелі [ARCH.75]** | 🔴 **Пʼята нога існує тому, що спроєктований термінатор МЕРТВИЙ:** `sidekiq_retries_exhausted` в `ActuatorCommandWorker` ставить `failed`, але [`FW.60`](00_07_Action_Plan_Tracker) зняв push-тракт і живих enqueuer'ів того воркера **нуль** (єдиний `perform_async` у дереві — всередині коментаря), тож у проді хук не викликається жодного разу; зеленим його тримає сюїта, що смикає воркер руками. Живий poll-тракт матеріалізує кінець наказу лише в МОМЕНТ ВИДАЧІ, тобто коли Королева приходить — на тій, що не прийде, наказ лежав би `pending` вічно, а `live_pending` тримає 409 у контролері. ⚠️ Наказ від ЛЮДИНИ при цьому не має `expires_at` взагалі (писачів TTL рівно два — `EmergencyResponseService` і STOP safety-свіпа), тож `scope :expired` його не матчить НІКОЛИ. ⚖️ Дискримінатор — **подія, не час** (присуд founder 2026-08-17): часовий поріг завів би друге непідписане число поруч із тодішнім відкритим ⚖️ про `relevance` (числа ратифіковано 2026-08-20). Свіп по СТАНУ, а не гачок на `report_fault!`, бо шляхів у `faulty` два (ця нога і `HeliumSosWorker`). ⚠️ **Названа ціна:** Королева вміє повертатись (нога 2), тож наказ, поданий за хвилину до обриву, згорить — свідомий обмін проти «висить вічно й блокує канал»; протокольним наказам чесний строк дає власний `expires_at` |

#### `TreeStalenessSweepWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 2 · cron `*/5 * * * *` |
| **Тригер** | Sidekiq-cron — **[SILENCE-1]** dead-man switch Солдата ([`06_08 §1.3`](06_08_Resilience_and_Failover_Policy)) |
| **Вхід** | — |
| **Сервіси** | Немає — `Tree.silent(threshold)` + `EwsAlert.escalate_field_audit!(tree:)` |
| **Side Effects** | Аномальна тиша (active-дерево мовчить довше `SystemParameter :tree_silence_threshold_hours`; дефолт = `Tree::SILENCE_THRESHOLD` [transitional] до bench E.63 — [ARCH.99] дав числу один дім на воркер, скоуп і в'ю) → per-tree критичний `EwsAlert(:field_audit)` — свідомо НЕ новий alert-тип (blacklist-предикат `critical_unmaintained?` — [`05_05`](05_05_Slashing_and_Risk_Policy)); статус дерева НЕ чіпає (removed/deceased запускають slashing, dormant = людське рішення). Повернення в ефір → машинний `resolve!` (resolved_by NULL, gap-E). Метрики: `tree_silence_total`, `trees_silent`. |

#### `HeliumSosWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 2 |
| **Тригер** | `HeliumSosController` — **[ARCH.34 L3]** SOS-webhook Helium Console ([`06_08 §1.2`](06_08_Resilience_and_Failover_Policy)) |
| **Вхід** | `dev_eui` (String), `payload_b64` (12B SOS-кадр), `reported_at` |
| **Сервіси** | Немає — `Gateway` lookup по `helium_dev_eui` |
| **Side Effects** | 12B-parse + cross-check `queen_did`↔hex-uid (mismatch/unknown/malformed → drop з `helium_sos_received_total{outcome}`); валідний → `report_fault!` (крім maintenance) + ідемпотентний критичний `EwsAlert(queen_uplink_lost)`. |

---

### 📢 Alerts — Тривоги та Верифікація

#### `AlertNotificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 5, expires_in: 5 хвилин |
| **Тригер** | `EwsAlert.after_create_commit :dispatch_notifications!` (Transactional Outbox — єдиний тригер після PR #226) |
| **Вхід** | `ews_alert_id` (Integer) |
| **Сервіси** | — |
| **Side Effects** | Знаходить stakeholders організації через `.find_each(batch_size: 500)`, збирає args у масив → `Sidekiq::Client.push_bulk("class" => SingleNotificationWorker, "args" => bulk_args)` — один Redis round-trip замість N окремих `LPUSH`. ⚠️ **ActionCable-broadcast знято 2026-07-27** (UI.4): він ніс lat/lng для мапи патруля, а споживача не мав — і жоден Turbo-сиблінг цього payload'а не несе (мапа живиться `geospatial_matrix` від змін ДЕРЕВА). 🔴 Заразом полагоджено NPE: `cluster` у `EwsAlert` — `optional`, воркер енкʼюїться безумовно, тож безкластерний алерт валив `cluster.organization` → 5 ретраїв → morgue; тепер гард логує й виходить (адресата сповіщень для такого алерта не існує — у дерева `cluster` теж optional). 🔴 **[ARCH.78]** Підсумковий рядок каже «поставлено в чергу: N сповіщень», а не «розіслано»: воркер спостерігає лише енкʼю, доставки він не бачить узагалі. Попереднє формулювання було найпідступнішим із трьох брехливих логів інциденту — саме його читають ПЕРШИМ під час розбору, і воно стверджувало розсилку при трьох мертвих каналах. `notify_stakeholders` тому повертає розмір батчу. 🔴 **[E.33, 2026-08-21] Канал без ТРАНСПОРТУ більше не потрапляє в чергу взагалі.** Доти сюди безумовно летіла джоба `"push"` на кожного стейкхолдера, тоді як `DeliveryChannels.available?(:push)` віддає жорсткий `false` — тобто платформа сама оголошувала транспорт неіснуючим, а черга однаково несла `2 × N` джоб, половина яких була `logger.warn` без жодного I/O. Ціна не косметична: `alerts` дренується strict-пріоритетом ПОВНІСТЮ перед `critical`, тож холості джоби вдвічі відсували живі доставки. Відсів читає **ТОЙ САМИЙ One-Home предикат**, що екран налаштувань і boot-гард пошти (тепер у нього ЧОТИРИ споживачі), тож дротування FCM вмикає канал без правки воркера; перевірка всередині `SingleNotificationWorker` лишається backstop-ом (джоба могла лягти в чергу за живого каналу й виконатись після зняття токена). ⚠️ Порожній набір каналів має ВЛАСНИЙ голос: «жодного оперативного каналу — N стейкхолдерів не отримають тривогу поза дашбордом» ⊥ тиша, коли стейкхолдерів немає — два різні світи, і мовчання злило б їх в один. 🔴 **Гард на вході СЕМАНТИЧНИЙ, не часовий** [ARCH.59, 2026-08-21]: воркер виходить на `alert.status_active?` — `EwsAlert` при резолві не видаляється, тож затримана джоба інакше розсилала б **ВИРІШЕНУ** тривогу. Гард стоїть в ОБОХ воркерах свідомо, і це не дубль: батько судить раз на фан-аут, а дитина лежить у черзі вдвічі довше (`expires_in` 5 хв ⊥ 10 хв). ⚠️ **`expires_in` цієї осі НЕ закриває** — на Sidekiq OSS опція інертна, тож доти вісь була покрита НУЛЕМ, а не слабко. |

> 📮 **Mailer-шар (`app/mailers/`) — сюди ж, бо доставка йде чергою.** Два мейлери: `AlertMailer#critical_notification` (адресат — `organizations.billing_email`) і `PasswordMailer#reset_instructions` (адресат — конкретний `User`); обидва відправляються `deliver_later`, тобто **виконуються в Sidekiq**, а не в запиті. ⚠️ **Черги в них РІЗНІ, і це присуд, а не побічний ефект:** `AlertMailer` → `alerts`(2) (лист їде чергою рішення, що його породило), `PasswordMailer` → `default`(5) свідомо — розбір у ⚖️-блоці «Пріоритети черг» вище, носій `spec/quality/activejob_queue_declaration_spec.rb`. Наслідок несучий і неочевидний: ані cookie, ані сесії там немає, тож локаль отримувача береться з persisted-колонки, а обгортка `ApplicationMailer#in_locale_of` стоїть навколо `mail()` — механіка й пастки живуть у [`04_04 §12.8`](04_04_Phlex_UI_and_Tailwind), поля — в [`04_01`](04_01_Data_Models_and_Entities). ✅ **Каталог `app/mailers/` увійшов у периметр `model_doc_sync` 2026-08-14 [ARCH.60]** — доти це був цілий каталог продового коду поза УСІМА гейтами, і знайшов його `stan_audit`, а не гейт (сам по собі показник). Тепер новий мейлер, не згаданий у цьому реєстрі, червонить `docs_check`. ⚠️ Стеля та сама, що в сусідів по перевірці: гейт питає «чи згадано ІМʼЯ КЛАСУ де-небудь у документі», не «чи описано правильно» — рядок-заглушка його задовольнить.
>
> 📤 **Транспорт [ARCH.60, 2026-08-14] — ENV-керований SMTP, без вендор-SDK.** `production.rb` збирає `smtp_settings` із `SMTP_ADDRESS` · `SMTP_PORT` (587) · `SMTP_USER_NAME` · `SMTP_PASSWORD` · `SMTP_DOMAIN` (HELO, опційний) · `SMTP_AUTHENTICATION` (`plain`); відправник — `MAIL_FROM`, і його резолвить `Notifications::DeliveryChannels.configured_sender` (там же живе сентинел «не налаштовано»). Вендор лишається змінюваним трьома змінними: кожен ESP, який ми б обрали (Postmark / SES / Mailgun / SendGrid / Resend), говорить звичайним SMTP, тож гем провайдера не потрібен. `delivery_method` свідомо не переоголошено — прод уже дефолтиться в `:smtp` (зміряно), а `raise_delivery_errors` лишається дефолтним `true`, щоб відмова зʼєднання була впалою джобою, а не мовчазним no-op. **Імена ENV дзеркаляться в [`06_04 §2.1`](06_04_Secrets_Checklist).**
>
> 🔴 **Незаданий транспорт більше не деплоїться: `config/initializers/mail_transport_check.rb` ВІДМОВЛЯЄ продові в старті.** До нього незконфігурований деплой падав найтихішим із можливих способів — `deliver_later` енкʼюївся, контролер віддавав 200, а джоба билась об `localhost:25`, перемелювала 25 ретраїв за ~три тижні й помирала в dead-set: password-reset був мертвий end-to-end, а критична тривога не доходила ні до кого, без сигналу на жодній поверхні. **`Rails.logger.warn` тут був би ЧЕТВЕРТИМ самосвідченням у цьому ж тракті** — [`ARCH.78`](00_07_Action_Plan_Tracker) щойно зняв три; лог, якого ніхто не читає, і створив цей клас дефекту. Гард питає **той самий предикат**, що малює екран (`DeliveryChannels.available?(:email)`) — дві відповіді на «чи жива пошта» були б рівно тим дрейфом, що дозволив би платформі стартувати, вважаючи канал живим. Обхід — `SILKENNET_SKIP_MAIL_TRANSPORT_CHECK=1` (гучний WARN); `SECRET_KEY_BASE_DUMMY` (Dockerfile `assets:precompile`) пропускається, як у [SEC.22]. ⚠️ Гард стоїть у ланцюзі boot-гардів **перед** `master_key_strength_check` (за алфавітом файлів), тож на порожньому деплої оператор побачить поштову стіну першою — кожен гард піднімається окремо, лік одного відкриває наступний.

> **⚠️ Rate Limiting (Post-TRL 8):** При кластерах з 5000+ стейкхолдерів `push_bulk` створить 5000 `SingleNotificationWorker` джобів, кожен з яких робить HTTP-запит до FCM / Telegram Bot API. Це гарантовано призведе до HTTP 429 (Too Many Requests) від провайдерів. **Рішення:** Замість тисяч окремих воркерів, використовувати нативні Bulk API (SMS відкинуто ⚖️ [`ARCH.78`](00_07_Action_Plan_Tracker) 2026-08-20 — Twilio-ноги в цьому плані більше немає):
> - **FCM:** Multicast-повідомлення — до 500 device tokens за 1 HTTP-запит (`send_multicast` — ⚠️ legacy, вимкнено Google ~2024; будувати одразу на HTTP v1 `sendEachForMulticast`, [`00_07` ARCH.60](00_07_Action_Plan_Tracker))
> - **Батчинг:** `AlertNotificationWorker` має групувати recipients по каналу (`:push` / `:telegram`) та відправляти батчами по 500 (FCM), а не делегувати кожне повідомлення окремому воркеру; Telegram Bot API bulk-ендпоінта не має — там межа ~30 msg/s, тобто ліміт бере на себе черга (E.33).
>
> 🔴 **[E.33, 2026-08-21] Перший крок зроблено, і він виявився НЕ лімітером: найдешевше обмеження — не ставити в чергу канал, якого немає** (механіка — картка воркера вище). Це вимірна половина: вона ділить довжину черги надвоє СЬОГОДНІ й нічого не вгадує про масштаб.
>
> ⚠️ **Решта гейтована МАСШТАБОМ, а не «відсутністю адаптерів» — і саме тому не будується наперед.** Telegram opt-in через `users.telegram_chat_id`, тож у ефір іде лише той, хто його дав; при поточному флоті межа ~30 msg/s недосяжна. Три виміри, які знадобляться в день, коли вона стане досяжною: (1) `Sidekiq::Limiter` **шим уже має все, крім тіла** — API `window(name, limit, period)`, живий споживач (`WEB3_RPC_LIMITER`, 50/s) і `rescue OverLimit` у `ApplicationWeb3Worker`, — тож форма лімітера тут не проєктується з нуля, вона **чекає присуду про Sidekiq Ent** ([`00_07`](00_07_Action_Plan_Tracker) ARCH.59, крок 2 «шим → raise замість тихого no-op»); ⚠️ `wait:` шим приймає й мовчки відкидає. (2) `expires_in` у `sidekiq_options` обох notification-воркерів — **теж Pro-опція без гема**, тобто оголошений TTL не діє: застаріла тривога не протухає, вона доїжджає. (3) `Rails.cache` тут НЕ підходить під лічильник вікна — прод це Solid Cache, чий `increment` **не атомарний** (доказ уже стоїть у шапці `rack_attack.rb`, і саме тому Rack::Attack ходить у Redis, а не в Rails.cache).
>
> 🔬 **І окремий вимір про поведінку при 429, бо він контрінтуїтивний.** Telegram їде через `Web3::HttpClient` із `service_name: "Telegram"`, тобто ділить circuit breaker із Web3-трактом: 3 поспіль не-2xx → ключ відкривається на 60 с. Донор цієї форми — RPC із **каскадом провайдерів**, а в Bot API endpoint один, тож 429 перетворюється на повну відмову каналу на хвилину. ⚖️ Це **свідомо лишено як є**: грубий backoff у поєднанні з `retry: 5` (сумарно ~8 хв) доставляє більшість, а звуження breaker'а під один канал означало б правку класу, спільного з money-path. `parameters.retry_after`, який Telegram сам присилає, не читається ніде — це відомий і прийнятий борг, а не пропущений випадок.

#### `SingleNotificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 5, expires_in: 10 хвилин |
| **Тригер** | `AlertNotificationWorker` |
| **Вхід** | `user_id`, `ews_alert_id`, `channel` (`:telegram` · `:push`) |
| **Сервіси** | `Notifications::TelegramTransport` (єдиний живий не-поштовий — [`ARCH.60`](00_07_Action_Plan_Tracker)); FCM не задротований; SMS відкинуто ⚖️ [`ARCH.78`](00_07_Action_Plan_Tracker) 2026-08-20 (гілку знято разом із `users.phone_number` — застарілий `"sms"`-джоб гучно падає в unknown-гілку) |
| **Side Effects** | ⚠️ **[E.33, 2026-08-21] Канал без транспорту сюди більше не доїжджає** — його відсіює `AlertNotificationWorker` на вході в чергу (картка вище). Гілки нижче лишаються **backstop-ом, а не основним шляхом**: джоба могла лягти в чергу за живого каналу й виконатись уже після зняття токена, тож їхня чесність і далі несуча — просто зустріти їх тепер можна лише у вузькому вікні. **[ARCH.78]** Доки транспорту немає, Push-гілка пише `Rails.logger.warn` про **СТАН КАНАЛУ** («Канал не сконфігуровано — … НЕ доставлено»), а не про результат. Попередня редакція логувала «Надіслано»/«Доставлено» біля закоментованого клієнта — журнал, що стверджує дію, якої не сталося, на тракті пожежної та вандалізм-сирени; під час розбору інциденту він читався б як доказ доставки. `case channel` має гучний `else` (невідомий канал → `logger.error`): тиша тут невідрізненна від доставки. Носій класу — `spec/quality/no_self_attesting_logs_spec.rb` (пара «закоментований транспорт + лог із дієсловом-результатом» у `app/**`; форма-агрегатор і статус-у-БД поза його стелею — вона задекларована в шапці). 📨 **Telegram-гілка [ARCH.60]:** без `telegram_chat_id` — тихо (канал opt-in, як push із token); без токена — той самий чесний warn; інакше текст рендериться в **локалі отримувача** (`Notifications::RecipientLocale` — у Sidekiq `I18n.locale` завжди базова) і їде в `TelegramTransport.send_message`. Помилка HTTP свідомо НЕ ковтається: `RequestError` = Sidekiq-retry цієї ж атомарної доставки. 🔴 **Гард на вході СЕМАНТИЧНИЙ, не часовий** [ARCH.59, 2026-08-21]: воркер виходить на `alert.status_active?` — `EwsAlert` при резолві не видаляється, тож затримана джоба інакше розсилала б **ВИРІШЕНУ** тривогу. Гард стоїть в ОБОХ воркерах свідомо, і це не дубль: батько судить раз на фан-аут, а дитина лежить у черзі вдвічі довше (`expires_in` 5 хв ⊥ 10 хв). ⚠️ **`expires_in` цієї осі НЕ закриває** — на Sidekiq OSS опція інертна, тож доти вісь була покрита НУЛЕМ, а не слабко. |

#### `Notifications::DeliveryChannels` [UI.10]

Дім ОДНОГО питання: чи має платформа **транспорт** для каналу. Читають троє — екран налаштувань (`Notifications::Settings`, через контролер), boot-гард `mail_transport_check.rb` (відмовляє продові в старті на мертвій пошті) і, у міру дротування, сам notification-шар. 🔴 **Спільність предиката між екраном і гардом — не економія рядків, а інваріант:** розділені, вони дозволили б платформі стартувати, вважаючи канал живим, і водночас малювати його мертвим.

| Параметр | Значення |
|----------|----------|
| **Тип** | Модуль-оголошення (`module_function`), без стану й без І/О |
| **API** | `available?(channel)` → Boolean · `available` → Array\<Symbol\> · `configured_sender(env)` → String · `ALL` = `%i[email telegram push]` |
| **Пошта** | ДЕРИВУЄТЬСЯ з двох спостережуваних: відправник ≠ `from@example.com` (незмінений скаффолд) **і** `smtp_settings[:address]` ≠ `localhost` (дефолт `ActionMailer`, коли налаштувань не задавали). ✅ Обидва задротовані до ENV 2026-08-14 першою ногою [`ARCH.60`](00_07_Action_Plan_Tracker) — екран сказав правду без правки цього модуля, рівно як тут і обіцяно. ⚠️ Присвоєння `smtp_settings` замінює дефолтний хеш цілком, тож незаданий `SMTP_ADDRESS` дає `nil`, а не `localhost` (зміряно) — предикат ловить обидві форми |
| **Відправник** | `configured_sender` — дім резолву `MAIL_FROM`, бо тут же сентинел і предикат, що його читає; `ApplicationMailer.default from:` лише **читає** це. 🔴 Порожній ENV падає назад у сентинел, а НЕ в правдоподібну адресу: правдоподібний дефолт оголосив би канал живим при мертвому транспорті. ⚠️ Значення мусить лишатись **рядком** — `default from:` приймає й `Proc`, але тоді `sender_configured?` порівнював би `#<Proc…>` зі сентинелом і завжди казав би «налаштовано» |
| **Telegram** | ✅ ДЕРИВУЄТЬСЯ (друга нога [`ARCH.60`](00_07_Action_Plan_Tracker), 2026-08-20): `available?(:telegram)` — чиста диспетчеризація в `TelegramTransport.configured?`; сам предикат живе В ТРАНСПОРТІ, поруч з ENV-імʼям і форматом токена (картка нижче) |
| **Push** | **Оголошений** мертвим: адаптера в дереві немає, і конфіг-поверхні теж — імена ENV назве `ARCH.60`. ⚖️ **Присуд ухвалено 2026-08-21: push НЕ потрібен до появи мобільного клієнта** — email (BOOT-CRITICAL) і Telegram покривають сценарій, тож канал лишається оголошено-мертвим не через недоробку, а за рішенням; тригер адаптера тепер сама ПОДІЯ (поява клієнта), а не чийсь присуд, і форму клієнта вирішує [`00_07`](00_07_Action_Plan_Tracker) **ARCH.108** (виділено з `E.20` 2026-08-24; `E.20` тепер про фізичного виконавця, не про клієнта — реф резолвився й вів у ЧУЖИЙ предмет). SMS у `ALL` більше не існує — канал відкинуто ⚖️ [`ARCH.78`](00_07_Action_Plan_Tracker) 2026-08-20 |
| **Чому оголошення, а не дерівація** | Дефолтний `smtp_settings` Rails за ФОРМОЮ не відрізняється від справжнього ESP-конфіга (`localhost:25` — адреса заповнена), тож предикат «схоже, налаштовано» повертав би `true` на незайманому скаффолді — той самий напис без джерела, лише виведений |
| **Носій** | `spec/services/notifications/delivery_channels_spec.rb` — стереже обидва напрямки дрейфу: канал, оголошений живим при мертвому транспорті, і транспорт, який задротували, а екран далі мовчить |

#### `Notifications::TelegramTransport` [ARCH.60]

Перший живий не-поштовий канал (⚖️ founder 2026-08-20: MVP — єдиний канал крім пошти без вендор-акаунта; bot-token видає BotFather безкоштовно). Дім УСЬОГО телеграмного: ENV-імʼя, формат токена, предикат і відправка живуть разом — «чи працює канал» і «чим він вмикається» не сміють бути двома домами.

| Параметр | Значення |
|----------|----------|
| **Тип** | Модуль (`module_function`); HTTP — через спільний `Web3::HttpClient` (persistent HTTPX + circuit breaker, `service_name: "Telegram"`) |
| **API** | `configured?(env)` → Boolean · `send_message(chat_id:, text:)` → POST `api.telegram.org/bot<token>/sendMessage` |
| **Config-гейт** | `TELEGRAM_BOT_TOKEN`; предикат **форматний** (`\d+:[\w-]{30,}` — форма BotFather-токена), тож деплой-плейсхолдер `REQUIRED_SECRET_NOT_SET` читається як «вимкнено», а не як живий канал — та сама нога, що `sender_configured?`. Порожньо = канал чесно no-op, буту НЕ блокує (на відміну від пошти) |
| **Локаль** | Текст локалізує ВИКЛИКАЧ через `Notifications::RecipientLocale.for(user)` — спільний дім локалі отримувача для всіх Sidekiq-каналів (мейлерівський `supported_locale_for` тепер делегує туди ж); fail-safe до базової на NULL і на значенні поза каталогом |
| **Помилки** | Не-2xx / мережеві збої = `Web3::HttpClient::RequestError`, воркер їх НЕ ковтає → Sidekiq-retry (5) атомарної доставки |
| **Носій** | `spec/services/notifications/telegram_transport_spec.rb` + telegram-контекст у `single_notification_worker_spec` (мутації: знята локаль-обгортка / розслаблений формат / знятий bulk-рядок — кожна RED поіменно) |

#### `DclimateVerificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 15 (≈ 35.5 год — детермінований floor дефолтного Sidekiq-backoff) |
| **Тригер** | Sidekiq cron або ручний запуск при fire/drought EwsAlert |
| **Вхід** | `alert_id` (Integer) |
| **Сервіси** | `Dclimate::VerificationService.new(alert).perform` |
| **Side Effects** | При вичерпанні ретраїв: `alert.satellite_status = :inconclusive` (DAO audit). |

> **⚠️ Критична проблема орбітального вікна:** при `severity: :critical` чекати ~1.5 доби на прояснення хмар неприпустимо, тож воркер не має права піти в retry-sleep.
>
> ✅ **Закрито [E.41]:** `escalate_obscured_critical_fire!` — `satellite_status: :inconclusive` (HOLD виплати) **плюс окремий `EwsAlert(:field_audit)`**, тобто повістка для людини. Обидві половини несучі й розділені навмисно: `:inconclusive` — стан ГРОШЕЙ (його єдиний читач `InsurancePayoutWorker#awaiting_independent_confirmation?`), а кличе людину саме алерт. Доти тут стояв лише перший, і «ескалація» зупиняла виплату, не викликаючи нікого.
>
> ⛔ **Дрон-bounty як Резервний Оракул — won't-do, не «відкладено».** Підстава конституційна: у тому дизайні рейнджер виконує роботу, сам подає фотодоказ і отримує винагороду за зміст власного свідчення — платформа платила б свідкові за вирок. Незалежність дає правило «атестатор ≠ бенефіціар», а не маркетплейс. Дім присуду — [`00_07`](00_07_Action_Plan_Tracker) E.20.

---

#### `ClusterEntropyAnalyzerWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 3 |
| **Тригер** | `ClusterEntropySweepWorker` — погодинний оркестратор (`Cluster.find_each` → fan-out; cron `10 * * * *`) |
| **Вхід** | `cluster_id` (Integer) |
| **Сервіси** | `SilkenNet::EntropyCalculatorService.call(z_values)` |
| **Side Effects** | Оновлює `cluster.entropy_score` (денормалізація). При entropy < `CRITICAL_ENTROPY_THRESHOLD` (0.65) створює `EwsAlert` (type: `entropy_anomaly`, severity: `medium`). Redis silence filter: 1 год per cluster. Prometheus gauge: `silkennet_cluster_entropy_score`. Інвалідація кешу `oracle_expected_yield_24h`. |
| **Примітка** | Аналізує Z-значення за останні 24 години (partition-aware query). Мінімум 30 точок даних для статистичної значущості. Alignment: ЧДТУ task #12 (00_02 §1.2). Чому Z-value, а не HRNG seed: `chaos_seed` НЕ передається у 21-байтному пакеті (03_01, Phase 2). |

---

#### `ClusterEntropySweepWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 3 |
| **Тригер** | Sidekiq cron `10 * * * *` (`cluster_entropy_sweep`, щогодини) |
| **Вхід** | — |
| **Side Effects** | Fan-out: `Cluster.in_batches(of: BATCH_SIZE)` → `ClusterEntropyAnalyzerWorker.perform_bulk`. Замикає doc-ahead-of-code розрив [S6.20] — без оркестратора EWS-детектор ентропії ніколи не виконувався. |
| **[ARCH.59] Bulk** | **Один Redis round-trip на БАТЧ, не на кластер** (2026-08-16): доти `find_each` + `perform_async` давав RTT на кожен рядок. Стеля памʼяті лишилась там само, де її тримав `find_each` — розмір батчу той самий. ⚠️ Носій — пін із ДВОМА половинами (`spec/workers/cluster_entropy_sweep_worker_spec.rb`), бо самої лише `.with(повний набір)` замало: `.once` стереже саме кількість звертань, і кожну половину доведено власною мутацією. ⊕ Заразом негативний приклад перецілено на `perform_bulk` — лишившись на `perform_async`, він став би **вакуумним**: код більше не кличе той метод НІКОЛИ, тож пін був би зелений незалежно від поведінки. |

---

### 🚨 Critical — Фінансово Критичні Операції

#### `BurnCarbonTokensWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `critical` |
| **Retry** | 5 |
| **Тригер** | `ContractHealthCheckService`, `Dclimate::VerificationService` (fraud), `ContractTerminationService` |
| **Вхід** | `organization_id`, `naas_contract_id`, `tree_id` (опц.), `contractual` (опц., default false — early-exit форфейтура пропускає positive-A gate), `target_date` (опц. String ISO8601 — прокидається з `ContractHealthCheckService`, парситься назад у Date + forward у сервіс для damage за ту ж добу [ARCH.46]), **`verdict_params`** (опц. Hash — ЗАМОРОЖЕНЕ ПРАВО ПОДІЇ [E.67]: `stress_threshold` · `slash_gamma` · `penalty_factor_max`, знімок `BlockchainBurningService.frozen_verdict_law` у мить РІШЕННЯ). 🔴 Ключі РЯДКОВІ навмисно — Sidekiq `strict_args` не пропускає символи через JSON-межу, і символьний хеш упав би вже на enqueue |
| **Сервіси** | `BlockchainBurningService.call` (повертає `:slashed`/`:frozen`/`nil`; **[ARCH.45]** intent-marker + in-flight slash guard проти double-burn — деталі §4) |
| **Side Effects** | **Лише на `:slashed`:** `MaintenanceRecord` (decommissioning). На `:frozen` (positive-A gate АБО no-data magnitude [ARCH.46], SLASH-1 §3.2) — без надгробка (Field-Audit алерт уже піднято сервісом). ⚠️ Броадкастів воркер більше не має: `CONTRACT_SLASHED` слався в `contract_status_badge_{id}`, якого не рендерить жодна сторінка (UI.4, знято 2026-07-27). |

#### `InsurancePayoutWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `critical` |
| **Retry** | 10 |
| **Тригер** | **[INS.1 dual-trigger]** Daily-оракул (`InsuranceOracleWorker`) лише ОЗБРОЮЄ кандидата (`:triggered`), payout НЕ enqueue. Settlement (Trigger-2) — `Dclimate::VerificationService` (fire_confirmed → знаходить `:triggered`) + recovery sweep `InsurancePayoutRecoveryWorker` (cron `15,45 * * * *`) |
| **Вхід** | `insurance_id` (Integer) |
| **Сервіси** | `Etherisc::ClaimService.new(insurance).claim!` (при `uses_etherisc?`) або `BlockchainMintingService.call` |
| **Side Effects** | **[INS.1]** Майстер-прапор `:parametric_insurance_oracle_enabled` (kill-switch, default off → no-op). **Dual-trigger gate** `awaiting_independent_confirmation?(insurance)` — payout лише за НЕЗАЛЕЖНИМ verified-підтвердженням **ВЛАСНОГО перилу поліса**, без нього → hold (basis-risk guard, [`05_05 §6`](05_05_Slashing_and_Risk_Policy)). ⚖️ **Периметри двох половин гейта РІЗНІ, і це присуд, не недогляд** ([INS.1] 2026-08-25): ТРИМАЮТЬ усі перил-алерти кластера (HOLD оборотний), ПЛАТИТЬ лише verified власного типу (виплата необоротна) — доти обидві половини були широкими, тож поліс від посухи виплатився б за доказом пожежі, бо `:verified` пише єдиний fire-only сайт. Дім пари перил⟷алерт — `ParametricInsurance::PERIL_CONFIRMING_ALERT`; симетричне звуження ВІДКИНУТО — воно зняло б працюючий гард. `insurance.pay!`, `BlockchainConfirmationWorker.perform_in(30.seconds, ...)`. Prometheus `INSURANCE_PAYOUT_ATTEMPTS/SUCCESS_TOTAL` (success-rate SLO). **[ARCH.45]** recovery-шлях + orphaned `:pending` Etherisc → `manual_review` (не сліпий re-claim) проти double-pay. **[ARCH.51]** Internal-mint двійник: `BlockchainMintingService` виключає лише `:confirmed`, тож прямий `.call` ре-мінтив би recovered `:sent`/`:processing` orphan → guard «re-submit ЛИШЕ `:pending`, інакше `escalate_to_review!`» (mint фліпає `:pending`→`:processing` у власному lock ДО broadcast, тож лише `:pending` гарантовано не-мінчений). **[INS.2]** Перед Internal-mint (лише Internal, **не** Etherisc) `Insurance::ReserveGate.call(insurance, current_tx_id:)` накладає systemic stop-loss: aggregate 24h correlated-event cap + reserve-adequacy (30d Internal-mint vs `DAO_TREASURY`-баланс × ratio), обидва пороги inert-default (`SystemParameter` 0=off). Breach → HOLD `manual_review` + `system_fault`-алерт (не незабезпечений mint); transient RPC (`:eval_error`) → **raise** (Sidekiq-retry, не permanent park — recovery-крон тягне лише `:triggered`). Поточна tx виключена з суми (no double-count); reserve-читання через спільний `Web3::Erc20Reader`-cache. |

#### `InsurancePayoutRecoveryWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `critical` |
| **Retry** | 3 |
| **Тригер** | Sidekiq cron `15,45 * * * *` (`insurance_payout_recovery`, кожні 30 хв) |
| **Вхід** | — |
| **Side Effects** | Fan-out: `ParametricInsurance.status_triggered.find_each` → `InsurancePayoutWorker.perform_async(insurance.id)`. Страхувальна сітка для застряглих :triggered виплат (втрачений подієвий enqueue з Dclimate); re-enqueue безпечний — payout-воркер ідемпотентний (lock + status guard + double-spend) [S6.20]. |

#### `EcosystemHealingWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `critical` |
| **Retry** | 3 |
| **Тригер** | `MaintenanceRecord` `after_create_commit :trigger_ecosystem_healing!` — БЕЗУМОВНО, на кожен створений запис. ⚠️ Тут доти стояло «Після закриття `EwsAlert` через `MaintenanceRecord`»: причина й наслідок переставлені місцями — закриття тривоги є КРОКОМ 4 цього воркера, а не його пускачем, і алерту в записі може не бути взагалі (`belongs_to :ews_alert, optional: true`) |
| **Вхід** | `record_id` (Integer, MaintenanceRecord) |
| **Сервіси** | — |
| **Side Effects** | `actuator.mark_idle!` (при repair), `tree.decommission!` (при decommissioning), `alert.resolve!` — усі в одній транзакції, тож крах життєвого циклу відкочує й закриття тривоги. ⛔ **Двох дій воркер більше НЕ робить, і обидві заборони несучі.** (1) **`mark_seen!` знято** [ARCH.109, 2026-08-25]: крок був безумовний, на будь-якому `maintainable`, і писав `last_seen_at = NOW()` через `update_all` — тобто ЛЮДСЬКИЙ запис штампував МАШИННИЙ канал живості, з якого виводять вердикт `hardware_pulse_confirmed?` [UI.7], `Tree.silent` [SILENCE-1] і `fresh_signal?` [ARCH.99]. Ланцюг замикала одна людина двома кліками: подала форму → платформа проставила пульс → підтвердила «залізо відгукнулось». Дім правила — картка `mark_seen!` у [`04_01 §2`](04_01_Data_Models_and_Entities). (2) **`declare_deceased!` знято** [E.20, ⚖️ 2026-08-25]: смерть дерева, як і CORC-паспорт, тепер оголошує `MaintenanceRecord#attest!` — обидві незворотні ланки за ОДНИМ незалежним підписом ([`04_01 §7`](04_01_Data_Models_and_Entities), картка `attested_by_id`). |

---

### 📡 Downlink — Команди на Пристрої

#### `ActuatorCommandWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | 3 (include `CoapEncryption`) |
| **Тригер** | (нема — enqueue-мертвий з 2026-07-13; історично `EmergencyResponseService` mass-insert [останню push-ногу знято] + `dispatch_to_edge!`) |
| **Вхід** | `command_id` (Integer), `explicit_key` (hex, опціонально) |
| **Сервіси** | — |
| **Side Effects** | ⚠️ **[FW.60 superseded]**: воркер більше не enqueue'иться (`dispatch_to_edge!` push-ногу зняв — його швидкі ретраї в CGNAT-діру `fail!`'или команду ДО першого poll'а); доставку + повний success-lifecycle (`dispatch!`→`mark_active!`→`acknowledge!`→`ResetActuatorStateWorker`) веде `Downlink::PendingQueueService` при видачі в poll-відповідь. Живим лишається `broadcast_command_state_static` — і після UI.4 (2026-07-27) він **єдина** точка броадкасту статусу команди на весь тракт: його кличуть і poll-сервіс (успіх **і** обидва fail-шляхи), і `ResetActuatorStateWorker`. Історична механіка PUT: CoAP PUT до Queen gateway. **[ARCH.58]** Dispatch-guard `command.dispatch! if command.may_dispatch?` — Sidekiq-retry після втраченого CoAP-ACK не згорає на `AASM::InvalidTransition` (Queen дедуплікує re-PUT за model-UUID `idempotency_token` — CMD-дедуп ring-buffer у `queen/main.c`; HTTP-шар має ОКРЕМИЙ `Idempotency-Key`-заголовок — [`04_03 §5`](04_03_REST_API_v1_Reference)). При `sidekiq_retries_exhausted`: `command.fail!` + Turbo Stream broadcast помилки. |

#### `OtaTransmissionWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | false (самостійна retry-логіка) |
| **Тригер** | ⚠️ **ЖОДНОГО — enqueuer'ів у дереві НУЛЬ** (виміряно 2026-08-13, [ARCH.59](00_07_Action_Plan_Tracker)). Доти цей рядок називав `Ota::DeploymentDispatcherService` «єдиним enqueuer'ом» і суперечив сусідньому рядку Side Effects: диспетчер після [FW.60] лише пише `pending_firmware_id`, а `OtaTransmissionWorker` кличе хіба що його константу `CHUNK_SIZE`. Живим лишається self-scheduling `perform_in` між чанками — але тільки якщо воркер хтось запустить |
| **Вхід** | `queen_uid`, `firmware_type` (`mruby`/`firmware`/`tinyml`/`weights`), `record_id`, `chunk_index` (default 0), `retry_count` (default 0) |
| **Сервіси** | `OtaPackagerService.prepare(firmware, chunk_size: CHUNK_SIZE, cluster_id: gateway.cluster_id)` |
| **Side Effects** | ⚠️ **[FW.60 superseded]**: push-конвеєр більше не enqueue'иться — dispatcher пише `gateways.pending_firmware_id`, чанки тягне сама Королева (`GET ota/<uid>?v=&ch=` → chunk-server `Downlink::PendingQueueService`); видалити після bench. Канал/target Turbo-прогресу (`ota_channel_<uid>`/`ota_progress_<uid>`) повторно використані живим [SEC.20] producer'ом у `PendingQueueService` — прогрес-опис нижче історичний. Історична механіка: CoAP PUT до Queen (AES-256-CBC), pacing `perform_in(0.4.seconds, ...)` між чанками. **[FW.23]** Worker завжди форвардить `gateway.cluster_id` (колонка `NOT NULL` у `gateways`), тож `packages` Enumerator автоматично містить 3 HMAC trailer-чанки `[0x9B]` після bytecode; логіка pacing без змін. Queen relay-ює `[0x9B]`-чанки stateless; Soldier верифікує dual-gate перед FLASH write. `total_chunks` worker'а береться з `manifest[:total_packages]` (= bytecode + 3 trailer) і саме за цим лічильником Turbo Stream `OtaProgressBar` рахує процент та переводить шлюз у `:idle` — без фолбеку на `total_chunks` шлюз би "завершив" OTA за 3 чанки до отримання HMAC печатки. При `sidekiq_retries_exhausted`: `gateway.update!(state: :faulty)` — запобігає Gateway stuck у `:updating`. |

#### `ResetActuatorStateWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | 3 |
| **Тригер** | `Downlink::PendingQueueService#actuator_command_payload` → `ResetActuatorStateWorker.perform_in(duration_seconds, ...)` при видачі CMD у poll-відповідь. ⚠️ Раніше тут стояв `ActuatorCommandWorker` — той самий документ за 19 рядків вище ([FW.60 superseded]) уже казав, що цей воркер більше не enqueue'иться, тож рядок суперечив сусідньому |
| **Вхід** | `command_id` (Integer) |
| **Сервіси** | — |
| **Side Effects** | `actuator.mark_idle!`, `command.confirm!`. **[ARCH.58]** `mark_idle!` лише коли наказ ВОЛОДІЄ поточним вікном — тобто на актуаторі немає СТРОГО пізнішого `:acknowledged`: під poll-семантикою кілька наказів видаються підряд, кожен переозброює власний Reset, тож найстаріший таймер приходив першим і обривав вікно найновішого. Строгість порівняння несуча (при включному два накази з однаковою міткою вважали б одне одного пізнішими — не закрив би ЖОДЕН). Витіснений наказ усе одно закривається, просто без `mark_idle!`. Наказ у `:sent` свідомо НЕ фейлиться: він у `.pending`, тож наступна poll-видача його легально доакноледжить (мертвий шлюз — інша діагностика, ARCH.54). Turbo broadcast **делегується** в `ActuatorCommandWorker.broadcast_command_state_static` — до 2026-07-27 тут жила ДРУГА, незалежна реалізація того самого броадкасту (з іншим обчисленням organization), тож будь-яка правка форми мусила лягати у два місця. Тепер стрім (`[actuator, :commands]`), ціль (`command_status_frame_{id}`) і payload (клас 2, [`04_04 §8.1а`](04_04_Phlex_UI_and_Tailwind)) описані рівно один раз. Друга половина (кард актуатора) знята UI.4 того ж дня: цілила в `actuator_card_{id}`, а `Actuators::Card` рендерить `actuator_{id}`. |

#### `ActuatorSafetySweepWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | 2 · cron `12,42 * * * *` |
| **Тригер** | Sidekiq-cron — **[ARCH.58]** сторож загубленого сліду. Черга `downlink`(4), а НЕ `alerts`(2) як у сусідніх dead-man switch'ів — це доменна приналежність, НЕ механіка доставки: STOP їде не Sidekiq-чергою, а рядком БД, який синхронно віддає CoAP-демон при poll'і. Каденс 30 хв — прагматичний компроміс: **нижньої межі частоти флашу не існує** (таймерний гейтований `cache_count > 0 \|\| ed25519_ready` — мовчазна legacy-Королева не флашить ніколи), а на завантаженому кластері частіший прохід доставляв би STOP раніше |
| **Вхід** | — |
| **Сервіси** | Немає — `Actuator.active` + AASM |
| **Side Effects** | Актуатор числиться `active` довше за вікно **найновішої** своєї команди (`sent_at + duration_seconds + STUCK_MARGIN`) → (1) override-`STOP` у чергу, але ЛИШЕ коли живих pending немає (інакше `cancel_pending_for_actuator!` знищив би аварійні чанки поливу; «живі» = `.pending` МІНУС протерміновані — труп фейлиться аж при poll-видачі й інакше глушив би ногу назавжди); (2) загублені `:acknowledged`-накази → `fail!` з причиною (**НЕ** `confirm!`: виконання не доведене); (3) `deactivate!`; (4) критичний `EwsAlert(actuator_stuck)` з дедупом по `message_params ->> 'actuator_id'` (per-actuator, бо на кластері їх кілька — cluster-scoped guard глушив би сусідів). Машинного resolve НЕМА свідомо: фізичний стан пристрою невідомий. Метрика `actuator_stuck_recovered_total` — **counter без gauge-двійника**: sweep стан усуває, тож «скільки зараз залипло» читалось би вічним нулем. Rescue НА ЗАПИС — один проблемний актуатор не обриває прохід. ⚠️ **Стеля:** фізичного закриття не дає (актуаторної прошивки не існує — [`03_02 §6`](03_02_Queen_Gateway_Firmware), `CMD:STOP` = forward-контракт як і `duration_seconds`); клас «БД чиста, а фізики не було» (втрачена 2.05) НЕ ловить — дім [`00_07` FW.63](00_07_Action_Plan_Tracker). Реальна цінність сьогодні: розчакловує актуатор ДЕТЕРМІНОВАНО (до цього виходи були лише випадкові — акт ремонту через `EcosystemHealingWorker` або наступний EWS-інцидент, чий `insert_all` минає readiness-гейт; команда від людини не вміла, бо гине при створенні) + чесний слід у ARCH.57-ланцюзі. ⚠️ Друга стеля вужча, ніж здається: витіснений наказ закриває сам Reset (else-гілка), а якщо загублено ОБИДВА Reset'и — актуатор лишається `active` і прохід закриє обидва. Вічно висить лише комбінація «мій Reset загублено, чужий спрацював»: актуатор уже `idle`, а прохід сканує тільки `Actuator.active`. |

---

### ⚖️ Default — Агрегація та Токеноміка

> ⚠️ **SSOT Note:** `DailyAggregationWorker`, `InsightGeneratorOrchestratorWorker` та `GenerateClusterInsightWorker` використовують чергу `low`, а не `default`. Вони розміщені тут для збереження логічної групи "добовий цикл". Черга вказана коректно в таблицях. `ClusterHealthCheckWorker` та `PartitionMaintenanceWorker` використовують чергу `default` (коректно).

#### `DailyAggregationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3, unique_for: 24 години |
| **Тригер** | Sidekiq cron: щодня 01:00 UTC |
| **Вхід** | `date_string` (String ISO8601, опціонально — default вчора UTC) |
| **Сервіси** | `InsightGeneratorOrchestratorWorker.perform_async(target_date.to_s)` |
| **Side Effects** | → `InsightGeneratorOrchestratorWorker` (batch), який після успіху викликає `InsightBatchCallbacks#on_success` → `ClusterHealthCheckWorker`. При відсутності телеметрії: `EwsAlert` GLOBAL_BLACKOUT для кожного активного кластера — **тільки в будні дні** (`target_date.on_weekday?`); вихідні мовчки ігноруються. |

> **[S6.8] Weekend Telemetry Blackout — обґрунтування поведінки:**
>
> Система НЕ генерує GLOBAL_BLACKOUT алерти на вихідних (`Saturday`/`Sunday`). Це by design:
> 1. **Сезонні паттерни EBFC:** У зимовий період метаболізм дерев знижується, delta_t збільшується, і Soldier може не мати достатньо енергії для TX кожну годину. У вихідні дні зниження телеметрії — очікувана поведінка.
> 2. **False positive reduction:** Оператори (foresters) не на зміні у вихідні — масові false alarm алерти створюють "alert fatigue" і знижують довіру до EWS системи.
> 3. **Телеметрія НЕ втрачається:** Пакети від Soldiers/Queens продовжують надходити і обробляються через `UnpackTelemetryWorker` як зазвичай. Лише BLACKOUT-алерт (відсутність даних за весь день) не генерується.
> 4. **Агрегація продовжується:** Якщо дані ІСНУЮТЬ у вихідні — `InsightGeneratorOrchestratorWorker` запускається нормально. Пропускаються лише blackout-алерти.
>
> Код: `app/workers/daily_aggregation_worker.rb` — `if target_date.on_weekday?`

#### `InsightGeneratorOrchestratorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3, unique_for: 24 години |
| **Тригер** | `DailyAggregationWorker` (після перевірки наявності телеметрії) |
| **Вхід** | `date_string` (String ISO8601, опціонально — default вчора UTC) |
| **Що робить** | Визначає кластери з даними за день через `InsightGeneratorService#cluster_baselines` (один SQL-запит). Створює `Sidekiq::Batch`, реєструє `InsightBatchCallbacks`, розбиває кластери на чанки по `CLUSTER_BATCH_SIZE = 100` та enqueue `GenerateClusterInsightWorker` для кожного чанку. Ідемпотентність — на рівні child-воркерів (per-cluster delete+insert). |
| **Side Effects** | Sidekiq Pro Batch → N × `GenerateClusterInsightWorker`. Після успіху всіх чанків: `InsightBatchCallbacks#on_success`. |

#### `GenerateClusterInsightWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3 |
| **Тригер** | `InsightGeneratorOrchestratorWorker` (всередині `Sidekiq::Batch`) |
| **Вхід** | `cluster_ids` (Array<Integer>), `date_string` (String ISO8601) |
| **Що робить** | Викликає `InsightGeneratorService#process_cluster_batch(cluster_ids)` — обробляє чанк кластерів: per-cluster delete+insert `AiInsight`, fraud detection, ML-модель, денормалізація `latest_stress_index`. |
| **Side Effects** | Оновлення `AiInsight`. `AlertDispatchService.create_fraud_alert!` при виявленні фроду. |

#### `InsightBatchCallbacks` _(Sidekiq Batch Callback — not a Worker)_

| Параметр | Значення |
|----------|----------|
| **Файл** | `app/callbacks/insight_batch_callbacks.rb` |
| **Тип** | Sidekiq Pro Batch callback клас (не Worker; живе у `app/callbacks/`, не `app/workers/`) |
| **Тригер** | `InsightGeneratorOrchestratorWorker` (реєструє через `batch.on(:success, InsightBatchCallbacks, "date" => ...)`) |
| **`on_success`** | Спрацьовує тільки якщо **всі** `GenerateClusterInsightWorker` jobs завершились успішно. Запускає РІВНО одне: `ClusterHealthCheckWorker.perform_async(date_string)` — аудит NaaS-контрактів. ⛔ Рядкового cleanup тут БІЛЬШЕ НЕМАЄ (⚖️ 2026-08-21 — ретеншн робить лише дроп партицій, [`04_01 §11`](04_01_Data_Models_and_Entities)); ⛔ fan-out страхового оракула теж — він переїхав ВСЕРЕДИНУ `ClusterHealthCheckWorker` [ARCH.59, 2026-08-25], бо цей колбек у проді не виконується (DOC-R.10 вище), а той воркер має власний cron. Носій обох зняттів — негативні піни у `spec/callbacks/insight_batch_callbacks_spec.rb`. |

#### `ClusterHealthCheckWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | (1) `InsightBatchCallbacks#on_success` — після успішного завершення всіх `GenerateClusterInsightWorker` чанків (real-time після ≈01:00 UTC batch); (2) Sidekiq cron `0 2 * * *` (`cluster_health_arbitration` у `config/sidekiq.yml`) — захисний fallback, відпрацьовує навіть коли denний batch мав нуль кластерів з даними і callback не спрацював. |
| **Вхід** | `date_string` (String ISO8601, опціонально). Якщо `nil` — **уся ітерація бере ОДНУ добу**, `AiInsight.reporting_date` [ARCH.100]. ⚠️ Доти кожен кластер брав власну `local_yesterday`, і для поясів західніше UTC−2 нічний крон читав добу, якої агрегатор не писав: `health_index` затирався фальшивою 1.0, вердикт ставав `:blackout` (Field Audit + невиплачена Celo-винагорода) на здоровому лісі. |
| **Сервіси** | `contract.check_cluster_health!(target_date)` → `ContractHealthCheckService` (повертає verdict `:healthy`/`:degraded`/`:blackout`/`:insufficient_sample`/`:skipped`) |
| **Side Effects** | [SLASH-1] Гілкує за **verdict** (не за `status_breached?` — breach тепер асинхронний, лише на реальному positive-A слешингу): `:healthy` → `CeloRewardWorker.perform_async`; `:degraded`/`:blackout` → лог, **без винагороди** (деградований/blackout кластер на адъюдикації cause-gate). Enqueue burn на `:degraded` робить сам `ContractHealthCheckService`. Оновлює `cluster.health_index` — і [ARCH.84] **без інсайту за добу пише явний `NULL`** («не виміряно»), а не вигадану 1.0. ⛔ Форма сусіда `ClusterEntropyAnalyzerWorker` (`return if score.nil?` — ПРОПУСТИТИ запис) сюди НЕ переноситься: цю колонку переписує щонічний `Cluster.find_each`, тож пропуск лишав би вчорашнє число на сьогоднішній темряві. **⚠️ Double-trigger caveat:** callback + cron можуть викликати worker двічі на день для тих самих кластерів. Захист — на рівні `Celo::CommunityRewardService`: **[ARCH.50]** dedup на ЛОГІЧНИЙ `reward_date` ВСЕРЕДИНІ Kredis-lock (раніше dedup будувався по `created_at` ≠ audit-день → запит НЕ знаходив свій рядок → детермінований 10 cUSD/день double-pay; виправлено), див. §10. ⊕ **[INS.1 / ARCH.59, 2026-08-25] Останнім кроком — `enqueue_insurance_oracle(target_date)`:** per-cluster fan-out `InsuranceOracleWorker` по кластерах з активними страховками, за прапором `:parametric_insurance_oracle_enabled` (kill-switch, default off → no-op). Дім переїхав сюди з `InsightBatchCallbacks`, бо там він був єдиним enqueue-сайтом воркера, а той колбек у проді не виконується (DOC-R.10). Ланка нічого не додала до розкладу — вона успадкувала cron-дублера цього воркера, і ту саму добу, якою вище судився контракт (розходження дат тут дало б оракулові порожню вибірку, невідрізненну від «даних немає» [ARCH.100]). |

#### `InsuranceOracleWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | **[INS.1]** `ClusterHealthCheckWorker#enqueue_insurance_oracle` — per-cluster fan-out за прапором `:parametric_insurance_oracle_enabled`. 🔴 **Доти тригером був `InsightBatchCallbacks#on_success`, і це означало НУЛЬ досяжних enqueue** (Batch-колбек у проді не виконується, DOC-R.10) — тобто фліп kill-switch нікого не озброював. Переїзд [ARCH.59, 2026-08-25] дав ланці пускача з власним cron `0 2 * * *`. |
| **Вхід** | `cluster_id`, `date_string` (опц.) |
| **Сервіси** | `ParametricInsurance#evaluate_daily_health!` (Trigger-1 — **arm-кандидат**, НЕ payout) для кожної активної страховки кластера |
| **Side Effects** | Озброює `:triggered`-кандидатів + `EwsAlert(:field_audit)`; per-insurance-збій ізольований (`rescue` → log → next). Kill-switch re-check на вході. Per-cluster fan-out тримає планетарний масштаб (як `InsightGeneratorOrchestratorWorker`). |

#### `TokenomicsEvaluatorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3, unique_for: 60 хвилин |
| **Тригер** | Sidekiq cron: щогодини |
| **Вхід** | — |
| **Сервіси** | — |
| **Side Effects** | `Sidekiq::Batch` → `EvaluateTreeBatchWorker` по 1000 гаманців. Callback `TokenomicsBatchCallbacks#on_success`. |

#### `TokenomicsBatchCallbacks` _(Sidekiq Batch Callback — not a Worker)_

| Параметр | Значення |
|----------|-----------|
| **Файл** | `app/callbacks/tokenomics_batch_callbacks.rb` |
| **Тип** | Sidekiq Pro Batch callback клас (не Worker; живе у `app/callbacks/`) |
| **Тригер** | `TokenomicsEvaluatorWorker` (реєструє через `batch.on(:success, TokenomicsBatchCallbacks, ...)`) |
| **`on_success`** | Спрацьовує тільки якщо **всі** `EvaluateTreeBatchWorker` jobs завершились успішно. Запускає РІВНО одне: `MintCarbonCoinWorker.perform_async` (без аргументів — auto-discovery всіх pending BlockchainTransaction). ⛔ Семпл ARCH.94-детектора звідси ЗНЯТО [ARCH.59, 2026-08-25] — дім `MintStallProbeWorker` нижче; носій зняття — негативний пін у `spec/callbacks/tokenomics_batch_callbacks_spec.rb`. |

#### `MintStallProbeWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 1 — пропущений зріз не втрачає даних (наступний за годину), тож наполегливий ретрай купував би лише шум |
| **Тригер** | Sidekiq cron `55 * * * *` (`mint_stall_probe`) — **зріз ПЕРЕД наступним циклом емісії**, який стартує о `:00` |
| **Вхід** | — |
| **Сервіси** | — (читає One-Home предикат `TokenomicsEvaluatorWorker.eligible_wallets`) |
| **Side Effects** | `MINT_ELIGIBLE_UNMINTED_DEPTH.set(depth)` + `info`-рядок НАВІТЬ на нулі [PERF.1] — мовчазний прохід був би невідрізненний від приладу, який не біг, а на нулі метрика найцінніша. Нічого не мутує: це прилад, не гроші, тому `rescue StandardError` ковтає збій замість того, щоб валити розклад сусідів по черзі. |
| **Чому окремий воркер** | [ARCH.94 / ARCH.59] Семпл жив у `TokenomicsBatchCallbacks#on_success`, тобто в Batch-колбеці, який у проді не виконується — метрика стояла порожня від народження. Канон доти казав «перенести НЕ можна»; підставу спростовано (розбір — DOC-R.10 §11 вище). Ключове для будь-якої майбутньої правки: **час зрізу несучий** — `lock_and_mint!` виводить гаманець із eligible-множини синхронно в чанку, тож `:55` міряє залишок здорового годинного проходу; зсув часу змінить ЗНАЧЕННЯ метрики, не лише її свіжість. Алерт — `sn-alert-mint-stall-depth` ([`06_03 §2.8`](06_03_Prometheus_Observability)). |

#### `EvaluateTreeBatchWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | `TokenomicsEvaluatorWorker` (Sidekiq Pro Batch child) |
| **Вхід** | `wallet_ids` (Array\<Integer>), `cycle_id` (String UUID) |
| **Сервіси** | — |
| **Side Effects** | `wallet.lock_and_mint!(points, threshold)` при `available_balance >= 10_000` (NET — [ARCH.94]). → `MintCarbonCoinWorker` (implicit через lock_and_mint!). |

#### `PartitionMaintenanceWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | Sidekiq cron: щодня (рекомендовано 00:30 UTC, перед `DailyAggregationWorker`) |
| **Вхід** | — |
| **Сервіси** | — (пряма робота з `ActiveRecord::Base.connection`) |
| **Side Effects** | `CREATE TABLE IF NOT EXISTS ... PARTITION OF ...` для таблиць `telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`. Перевіряє та створює партиції для поточного та наступного місяця (формат: `{table}_y{YYYY}m{MM}`). DDL-операція ідемпотентна — повторний запуск безпечний. Phase 7 додав `Sentry.capture_exception` у `rescue` блок щоб тихий збій DDL не призвів до `no partition of relation` на 1-му числі наступного місяця. |

---

### 🔗 Web3 Critical — Часочутливий Блокчейн

#### `BlockchainConfirmationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 10, unique_for: 10 хвилин |
| **Тригер** | `BlockchainMintingService`, `BlockchainBurningService`, `InsurancePayoutWorker` |
| **Вхід** | `tx_hash` (String) |
| **Сервіси** | — |
| **Side Effects** | `eth_get_transaction_receipt` (Polygon RPC). При `0x1`: `tx.confirm!`. При revert: `tx.fail!` (**[M2]** для mint-tx звільняє `locked_balance` через AASM `fail`-hook — дискримінатор `locked_points`). Retry при pending (ще в мемпулі). **[MEMPOOL LIMBO GUARD]** `sidekiq_retries_exhausted` handler: при вичерпанні всіх 10 ретраїв (~15-20 хвилин поллінгу) делегує до `MintingRollbackService.call(transactions: BlockchainTransaction.where(tx_hash:, status: :sent))`. Запобігає зависанню транзакцій у статусі `:sent` з замороженим `locked_balance` після потрапляння job у Sidekiq Dead queue. |

#### `StuckSentTransactionSweeperWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 3, unique_for: 9 хвилин |
| **Тригер** | Cron `5,35 * * * *` (кожні 30 хв) |
| **Вхід** | — |
| **Side Effects** | **[ARCH.55]** Re-arm `BlockchainConfirmationWorker` для tx, що застрягли в `:sent` довше 15 хв (`sent_at < 15.minutes.ago`) — клас, який ConfirmationWorker-`retries_exhausted` не ловить: OOM/евікшн ПІД ЧАС поллінгу (pending-discovery дивиться лише pending/processing; `MintingRollbackService` — тільки з `retries_exhausted`). **Скоуп = `blockchain_network: "evm"` only** — ConfirmationWorker Polygon-специфічний; Solana/Celo `:sent` без фільтра летіли б у чужий поллер (15-20 хв змарнованого RPC + хибний `manual_review`; Solana/Celo мають власні reconcile-шляхи). Ключ на `sent_at` (broadcast-момент), НЕ `created_at` (reset-to-pending тримає старий). Дедуп по tx_hash з earliest created_at (partition-prune); safety-cap `BATCH_LIMIT` re-arm'ів за прохід. Покриває mint/burn/insurance (спільний ConfirmationWorker). Ідемпотентність дубля з живим поллером = AASM `confirm` (одноразовий; дубль → `InvalidTransition` → retry → no-op). **[ARCH.45 :processing-orphan, 2026-07-05]** Другий прохід `escalate_stuck_processing!`: stale `:processing` (updated_at > 15 хв — created_at труїть reset-to-pending) → `escalate_to_review!` (`:manual_review`): крах між `transact("mint")` і `mark_as_sent` = ambiguous (мінт міг landed, tx_hash невідомий) → політика ARCH.48/M6, НІКОЛИ blind re-mint; double-mint і так неможливий (mint-шляхи фільтрують `:pending`), закрито observability/locked-balance хвіст. |

#### `CeloRewardReconcileWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 3, unique_for: 25 хвилин (Enterprise-шим, зараз no-op) |
| **Тригер** | Cron `25,55 * * * *` (кожні 30 хв) |
| **Вхід** | — |
| **Side Effects** | **[ARCH.64]** Escalate Celo reward-intent, що застряг у `:pending` (celo/cusd, `created_at ∈ [7д…30хв]ago`) → `escalate_to_review!` (`:manual_review`). Клас, який sibling'и не ловлять: transient RPC-timeout лишає intent `:pending` + re-raise → Sidekiq-retry бачить `:pending` у `reward_already_sent?` → dedup-skip, job "success" (**self-masking**, DeadSet мовчить); `CeloConfirmationWorker` reconcile озброюється лише для `:sent`, `StuckSentTransactionSweeperWorker`/`MintBatchCollectorService` = evm-only → Celo `:pending` без tx_hash був непокритий → тиха недоплата cUSD. **Money-safe**: tx_hash невідомий → on-chain-доля ambiguous → людська звірка на Celo explorer, НІКОЛИ blind re-pay (dedup через `reward_already_sent?`-включає-`:manual_review` тримає re-pay). Partition-pruned reload (`find_with_partition_pruning`); safety-cap `BATCH_LIMIT=500` (oldest-first). Видимість — `silkennet_blockchain_manual_review_depth` gauge + `sn-alert-manual-review-depth` (P1). |

#### `MintCarbonCoinWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
| **Includes** | `Web3CircuitBreaker` — `with_circuit_breaker("polygon_rpc")` |
| **Тригер** | `OracleCallbacksController#create` (Chainlink DON webhook) або `TokenomicsEvaluatorWorker` (cron fallback) або `TokenomicsBatchCallbacks#on_success` |
| **Вхід** | `telemetry_log_id` (опціонально), `created_at_iso` (опціонально) |
| **Сервіси** | `BlockchainMintingService.call_batch` або `.call` |
| **Side Effects** | При вичерпанні ретраїв (`sidekiq_retries_exhausted`): з `telemetry_log_id` → таргетований `MintingRollbackService.call` (розблоковує `locked_balance`); БЕЗ аргументу (напр. `TokenomicsBatchCallbacks#on_success`) → глобальний sweep `BlockchainTransaction.where(status: [:pending, :processing]).limit(1000)` по ВСІХ гаманцях → `MintingRollbackService.call(transactions:)`. |
| **Idempotency** | `process_batch` повторно фільтрує `where(status: :pending)` отримані `batch_ids` ПЕРЕД `call_batch` — записи, що паралельний воркер уже перевів у `:processing`/`:sent` між pluck і викликом, тихо відкидаються (не доходять до RPC); порожній набір → достроковий вихід. Окремий шар ідемпотентності від Kredis-lock у сервісі. |

#### `IotexVerificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
| **Includes** | `Web3CircuitBreaker` — `with_circuit_breaker("iotex_w3bstream")` |
| **Тригер** | `TelemetryUnpackerService` (після `commit_telemetry`) |
| **Вхід** | `telemetry_log_id`, `created_at_iso` (ISO8601 6 decimals) |
| **Сервіси** | `Iotex::W3bstreamVerificationService.new(log).verify!` |
| **Side Effects** | `log.update!(verified_by_iotex: true, zk_proof_ref:)`. → `ChainlinkDispatchWorker.perform_async`. |


#### `IotexBackfillWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` · cron `7 * * * *` (`iotex_backfill`) |
| **Retry** | 1 — пропущений прохід не втрачає даних (наступний за годину), наполегливий ретрай купував би шум на тлі того самого зовнішнього збою |
| **Чому окремий воркер** | **[INF.22]** `IotexVerificationWorker` мав слід вичерпаних ретраїв, але спосіб відновлення був РУЧНИЙ re-enqueue — недосяжний рівно при sustained-outage. Клас «механізм ⟷ пускач»: механізм справний, слід справний, бракувало пускача; канон [`06_08 §2.2`](06_08_Resilience_and_Failover_Policy) крок 5 роками називав імʼя цього класу, якого не існувало |
| **Вхід** | — (свіп) |
| **Стелі** | `LOOKBACK_WINDOW` + `BATCH_LIMIT` — визначення ПРЕДМЕТА, не оптимізація: лог, незверифікований довше за вікно, є предметом ретеншену, а не recovery (прецедент `PERF.1` — «дешевший запит» не сміє міняти ВІДПОВІДЬ). Стеля проходу тримає `web3_critical` від заливання після довгого простою |
| **Side Effects** | `IotexVerificationWorker.perform_async(id_value, created_at.iso8601(6))` — ОБИДВІ координати обовʼязкові (`telemetry_logs` партиційований). Метрика `IOTEX_BACKFILL_REARMED_TOTAL` рахує ЛОГИ (`by:`), не проходи; у здоровому тракті нуль за побудовою → алерт `sn-alert-iotex-backfill-active`. ⚠️ НЕ money-блокер: PATH 2-мінт IoTeX не гейтить ([ARCH.53]), тож відстає ДОКАЗ походження, не емісія |
#### `ChainlinkDispatchWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
| **Includes** | `Web3CircuitBreaker` — `with_circuit_breaker("chainlink_functions")` |
| **Тригер** | `IotexVerificationWorker` |
| **Вхід** | `telemetry_log_id`, `created_at_iso` |
| **Сервіси** | `Chainlink::OracleDispatchService.new(log).dispatch!` |
| **Side Effects** | `log.update!(chainlink_request_id:, oracle_status: "dispatched")`. |

---

### 🌐 Web3 — Стандартні Мультичейн

#### `PeaqRegistrationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 5 |
| **Тригер** | При реєстрації нового дерева (API або скрипт) |
| **Вхід** | `tree_id` (Integer) |
| **Сервіси** | `Peaq::DidRegistryService.new(tree).register!` |
| **Side Effects** | `tree.update!(peaq_did:)`. Ідемпотентний guard. |

#### `CeloRewardWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 3 |
| **Includes** | `Web3CircuitBreaker` — `with_circuit_breaker("celo_cusd")` |
| **Тригер** | `ClusterHealthCheckWorker` (при healthy кластері) |
| **Вхід** | `cluster_id`, `target_date_string` |
| **Сервіси** | `Celo::CommunityRewardService.new(cluster, date).reward_community!` |

#### `SolanaMicroRewardWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 3 |
| **Includes** | `Web3CircuitBreaker` — `with_circuit_breaker("solana_spl")` |
| **Тригер** | `OracleCallbacksController#create` (Chainlink DON fulfillment callback, при `oracle_status == "fulfilled"`) |
| **Вхід** | `telemetry_log_id`, `created_at_iso` (опціонально) |
| **Сервіси** | `Solana::MintingService.new(log).mint_micro_reward!` |

#### `SolanaBatchPayoutWorker` [E.61]

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 3 |
| **Includes** | `Web3CircuitBreaker` — `with_circuit_breaker("solana_spl")`; `lock: :until_executed` |
| **Тригер** | Sidekiq cron `20 * * * *` (щогодини) |
| **Вхід** | — |
| **Сервіси** | `Solana::BatchPayoutService.call` → виплата накопиченого (поріг `solana_batch_threshold_usdc` > 0; **[ARCH.45]** in-flight reconcile + confirm-gated settle проти double-pay — деталі §10) |

#### `PuroEarthPassportWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 5 |
| **Тригер** | 🔴 **`MaintenanceRecord#attest!`** — САМ підпис другої пари очей (⚖️ founder 2026-08-24). ⚠️ Доти тригером був `EcosystemHealingWorker` безумовно, і це робило присуд «атестація перед CORC-заявкою» невиконуваним: атестатор мав рівно стільки часу, скільки живе джоба (`retry: 5` без власного `sidekiq_retry_in` = дефолтний бекоф Sidekiq ≈ 7–10 хв до DeadSet), тобто дедлайн, що селектує підпис не дивлячись. Healing-воркер тепер не ставить паспорт у чергу НІКОЛИ; гард «лише заатестоване» був би там мертвою гілкою (він біжить `after_create_commit`, коли підпис ще неможливий) |
| **Вхід** | `maintenance_record_id` (Integer) |
| **Ворота [E.20]** | `require_evidence!` ПЕРЕД Phase 1, ДВІ умови й два різні винятки: без фото → `MissingEvidence`, без незалежного підпису → `MissingAttestation` (raise, не тихий `return`). ⚠️ Порядок несучий: коли бракує обох, відповідь мусить бути про ФОТО, інакше оператор лагодить не те. ⊕ **Це ДРУГА лінія:** обидві умови вже гейтовані раніше (фото — валідацією на моделі, підпис — тим, що пускачем є `attest!`), тож фото-половина в проді майже недосяжна — вона стереже прямий enqueue з консолі та записи, старші за валідацію. ⛔ **Тип НЕ додається в `MaintenanceRecord#evidence_backed?`** — валідація там біжить на КОЖЕН `save` (форму `on: :create` відкинуто, [ARCH.91](00_07_Action_Plan_Tracker)), а обидва Puro-воркери роблять `update!` на вже-створеному записі; найгірше — `sidekiq_retries_exhausted` поллера кличе `escalate_biomass_passport!` усередині `rescue`, тож `RecordInvalid` полетів би незловленим і запис завис би в `:sent` назавжди з мертвим власним запобіжником. 🔴 Носій відмови обрано ВИМІРОМ: per-tree `EwsAlert(:field_audit)` тут зʼїдається — `TreeStalenessSweepWorker` закриває такі алерти для дерев поза `active`, а дерево вже `deceased`; cluster-level входить у `dark_cluster_ids` і осліпив би per-tree dead-man switch. Тому 5 ретраїв (фото ще можуть додати) → DeadSet + Sentry (`sn-alert-sidekiq-deadset`). ⚠️ Стеля: гейт стереже ОСТАННЮ ланку — `declare_deceased!` і звʼязаний `trigger_slashing_protocol` спрацювали раніше, в `EcosystemHealingWorker` ([`00_07`](00_07_Action_Plan_Tracker) E.20) |
| **Сервіси** | Phase 1: `PuroEarth::PassportService.new(payload).anchor!` (on-chain anchoring → Polygon D-MRV Registry, стан `:sent`). Phase 2: `PuroEarthConfirmationWorker` (receipt-полл). Phase 3 — ЛИШЕ після `:confirmed`: `PuroEarth::RegistryApiService.new(payload, tx_hash:).submit!` (REST API → Puro.earth CORC) |
| **Side Effects** | `record.update!(biomass_passport_tx_hash:, biomass_passport_status: :sent)`. `PuroEarthConfirmationWorker.perform_in(30.seconds, record.id)` при `:sent`. `record.update!(puro_earth_corc_ref:)` при `:confirmed` (Phase 3 non-blocking: REST-збій не скасовує on-chain anchoring). `:failed`/`:manual_review` — термінальні для оркестратора. ⚠️ Позначена стеля: stuck-`:sent` sweep відкладено до активації шляху ([`00_07`](00_07_Action_Plan_Tracker) PERF.1) |

#### `PuroEarthConfirmationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` (не money-path — кошти не заблоковані) |
| **Retry** | 10 (≈15-20 хв горизонт, дзеркало `BlockchainConfirmationWorker`; `unique_for: 10.minutes`) |
| **Тригер** | `PuroEarthPassportWorker` (Phase 2) — [PERF.1(д), 2026-08-20]: доти конфірмейшн-нога вела в `blockchain_transactions`, куди паспортний хеш не потрапляє ніколи |
| **Вхід** | `maintenance_record_id` (Integer) |
| **Сервіси** | `Web3::EvmReceiptClassifier.classify(receipt)` по `ALCHEMY_POLYGON_RPC_URL` (без reorg-depth gate — Polygon, не L1) |
| **Side Effects** | `:confirmed` → `confirm_biomass_passport!` + re-enqueue оркестратора (відкриває Phase 3). `:reverted` → `fail_biomass_passport!` (термінал; re-anchor = console). Pending → raise (retry). `retries_exhausted` → ФІНАЛЬНИЙ receipt re-check (прецедент ARCH.66: сліпий escalate записав би підтверджений анкер у `:manual_review`), лише все-ще-не-готовий/RPC-збій → `escalate_biomass_passport!` |

#### `MintBatchCollectorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 3 |
| **Lock** | `until_executed` |
| **Тригер** | Sidekiq cron: `*/5 * * * *` (кожні 5 хвилин) |
| **Вхід** | — |
| **Сервіси** | `Treasury::MintBatchCollectorService.call` |
| **Side Effects** | Збирає pending TX та відправляє через `BlockchainMintingService.call_batch`. Gas savings ~30-40%. |

---

### 💤 Web3 Low — Не Критичний Блокчейн

#### `EthereumAnchorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 5, unique_for: 7 днів |
| **Тригер** | Sidekiq cron: щопонеділка 03:00 UTC |
| **Вхід** | — |
| **Сервіси** | `Ethereum::StateAnchorService.new.anchor_to_l1!` |

#### `EthereumAnchorConfirmationWorker` [ARCH.66]

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 60, фіксований `sidekiq_retry_in { 180 }` (~3год горизонт — L1 slow-inclusion), unique_for: 3 год |
| **Тригер** | `perform_in(30s)` після `StateAnchorService` `:sent`; re-arm зі `StuckSentAnchorSweeperWorker` |
| **Вхід** | `anchor_id` |
| **Side Effects** | poll `eth_get_transaction_receipt` → `Web3::EvmReceiptClassifier` → `confirm!`/`mark_failed!`(+reverted-counter)/`:pending`-raise; **reorg-depth gate** (`ETHEREUM_ANCHOR_MIN_CONFIRMATIONS`=64). Exhausted → **фінальний receipt re-check** → confirm/fail, і лише все ще pending → `escalate_to_review!` (`:manual_review`; дзеркало `MintingRollbackService`). **Ніколи re-broadcast** (лише poll receipt; nonce персиститься перед broadcast — ARCH.66 companion). Дім — [`05_04 §5.1`](05_04_Ethereum_L1_State_Anchor) |

#### `StuckSentAnchorSweeperWorker` [ARCH.66]

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3, unique_for: 55 хв |
| **Тригер** | Sidekiq cron: щогодини :40 |
| **Вхід** | — |
| **Side Effects** | re-arm `EthereumAnchorConfirmationWorker` для `EthereumAnchor.stuck_sent` (`:sent` >6год; read-only re-poll, reload-guard, `BATCH_LIMIT`). Backstop для загиблого поллера (OOM) — сам поллер не встиг escalate |

#### `KlimaRetirementWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3 |
| **Тригер** | ⛔ **ЖОДНОГО — воркер має НУЛЬ enqueue-сайтів** (переміряно 2026-08-26; доти цей рядок казав «ручний запуск через API», і жодного retire-маршруту в `config/routes.rb` немає). Дзеркала стану — [`06_08 §2.2`](06_08_Resilience_and_Failover_Policy) і [`00_07`](00_07_Action_Plan_Tracker) ARCH.95, обидва називають рейку мертвою; дротування gated на перший B2B-запит на ретайрмент |
| **Вхід** | `wallet_id`, **`scc_amount`** — ⚠️ ім'я несе ОДИНИЦЮ свідомо [ARCH.95]: аргумент джоби позиційний, kwarg туди не дотягується, тож безіменний `amount` тут був носієм класу «два units в одному скалярі» |
| **Сервіси** | `KlimaDao::RetirementService.new(wallet, scc: scc_amount).retire_carbon!` — kwarg іменує ОДИНИЦЮ [ARCH.95] |

#### `HadronAssetRegistrationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 5 |
| **Тригер** | ⛔ **ЖОДНОГО — воркер має НУЛЬ enqueue-сайтів** (переміряно 2026-08-25, [`00_07`](00_07_Action_Plan_Tracker) BIZ.11; «при активації NaasContract» спростовано — подія `activate` такого enqueue не має, тригер був вигаданий). Пускач = майбутній `Hadron::TokenizeForestPlotService`, свідомо не будується до присудів UNI.16 + BIZ.22 |
| **Вхід** | `naas_contract_id` (Integer) |
| **Сервіси** | `Polygon::HadronComplianceService.new.register_asset!(naas_contract)` |

#### `HadronKycVerificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 5 |
| **Тригер** | [KYC.1] `after_commit` на біндингу/зміні `crypto_public_address` (Organization / Wallet) |
| **Вхід** | `subject_type` ("Wallet"/"Organization" — whitelist), `subject_id` |
| **Сервіси** | `Polygon::HadronComplianceService` → `verify_investor!` (wallet із власною адресою) / `verify_organization!` (custodial-бенефіціар) |
| **Side Effects** | Пише `hadron_kyc_status` (approved/rejected) на суб'єкті; custodial-wallet без власної адреси — skip (успадковує org-статус через `Wallet#kyc_approved_for_minting?`). Dev/no-key = simulate-approve; prod strict = реальний Hadron API. Канон-гейт: [`05_02` — Крок E](05_02_Proof_of_Growth_Pipeline). |

#### `HadronKycReverifyWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3, unique_for: 55 хвилин (Enterprise-шим, зараз no-op) |
| **Тригер** | Cron `50 * * * *` (щогодини) |
| **Вхід** | — |
| **Side Effects** | **[ARCH.65]** Re-enqueue `HadronKycVerificationWorker` для Wallet/Organization з `hadron_kyc_status="pending"` (з власною адресою, `updated_at > 1год`). Клас: `HadronKycVerificationWorker` (retry:5) НЕ має `sidekiq_retries_exhausted` + enqueue лише разово `after_commit` → Hadron API down усі 5 retry → Dead Set → KYC `"pending"` НАЗАВЖДИ → mint-gate `Wallet#kyc_approved_for_minting?` щоцикл тихо скіпає pending-tx бенефіціара. Idempotent auto-heal (повторний verify безпечний; скоуп лише `"pending"`, approved/rejected не чіпаємо); `BATCH_LIMIT=500` oldest-first проти thundering-herd на mass-recovery. Backlog-видимість — `silkennet_hadron_kyc_pending_depth` gauge. |

#### `TreasuryMonitorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3 |
| **Lock** | `until_executed` |
| **Тригер** | Sidekiq cron: `*/15 * * * *` (кожні 15 хвилин) |
| **Вхід** | — |
| **Сервіси** | `Treasury::MonitorService.call` |
| **Side Effects** | Оновлює Prometheus gauges (`ORACLE_BALANCE`, `ORACLE_BALANCE_RATIO`). Створює `EwsAlert` при критичних балансах. Логує `healthy/critical/error` counts. |

#### `Governance::ParameterSyncWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3, unique_for: 24 hours |
| **Тригер** | Sidekiq cron: `30 3 * * *` (щоденно 03:30 UTC) |
| **Вхід** | — |
| **Сервіси** | `Eth::Contract` (ProtocolParameters ABI) через `Web3::RpcConnectionPool` |
| **ENV** | `PROTOCOL_PARAMETERS_CONTRACT_ADDRESS`, `ALCHEMY_POLYGON_RPC_URL` |
| **Side Effects** | [GOV.1] Зчитує 8 економічних on-chain параметрів (tokenomics/minting/insurance + slashing/alerts) з `ProtocolParameters.sol`. Fixed-point conversion (uint256/1e18 → BigDecimal). Порівнює з `SystemParameter` і оновлює змінені (source: `"governance"`, updated_by: `User.oracle_executioner`, `min_value`/`max_value` bounds) — out-of-bounds відхиляється (лог + `silkennet_governance_param_rejected_total`). 8 Lorenz-ключів — DCI-tripwire: WARN на голос, НЕ синхронізуються (FW.7 — [`05_06 §7`](05_06_Governance_and_DAO)). Timeout 10s per RPC call. |

---

### 📦 Low — Аудит та Зберігання

#### `AuditLogWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3 |
| **Тригер** | MRV.1 money-переходи + [ARCH.57] `Auditable#record_audit_trail!` (привілейовані дії: контракт/актуатор/роль/параметр/ротація/slash-вердикти) |
| **Вхід** | `attrs` (Hash для `AuditLog.create!`) + позиційний `archive` (default `true`) |
| **Сервіси** | — |
| **Side Effects** | `AuditLog.create!`; при `archive=true` (лише MRV.1 money-tx) — виставляє outbox-маркер `archive_requested_at` (INF.22 крок 11) → `FilecoinArchiveWorker.perform_async(log.id)`. [ARCH.57] `archive=false` (default концерну) = **chain-only**: більшість викликів сьогодні НЕ архівуються — security/ops-метадані не пінити на публічний IPFS; прямий `create!` factory/console маркер не ставить → теж поза периметром. |

> **🔗 Chain Integrity Invariant (Concurrency Guard).** `chain_hash` будується як SHA-256(previous_chain_hash | chain_payload) — це створює сувору залежність від порядку. Без серіалізації паралельні Sidekiq-потоки можуть прочитати один і той самий `AuditLog.last` для організації і утворити форки ланцюга. **Mitigation у коді** (`app/models/audit_log.rb`, [auditable]):
> 1. Single-row insert (`AuditLog.create!`): `before_create :compute_chain_hash` бере `pg_advisory_xact_lock(827549841, organization_id)` (transaction-scoped). Lock автоматично знімається при COMMIT/ROLLBACK — не потрібно `lock_release`. Паралельні організації не блокують одна одну (lock keyed на `organization_id`).
> 2. Bulk insert (`AuditLog.bulk_record!(entries)`): групує entries за `organization_id`, бере той самий advisory lock per org, обчислює послідовно chain_hash для кожного row перед `insert_all`. Один SQL батч, одна транзакція, нульовий fork ризик.
> 3. Інтеграційна перевірка `AuditLog.verify_chain_integrity(org_id)` доступна для семантичного аудиту й Filecoin verification (`{ valid: false, broken_at: id }` при будь-якому дефекті).
>
> **Чому advisory lock, а не `SELECT ... FOR UPDATE` / `Kredis.lock`:** advisory locks PG безкоштовні (in-memory у PG), не вимагають реального рядка-предка (на стадії genesis рядка немає), не залежать від Redis (Kredis fallback на Solid Cache додає latency). Transaction-scoped семантика гарантує авто-релізу при ROLLBACK через Sidekiq retry.

#### `FilecoinArchiveWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 5 |
| **Тригер** | `AuditLogWorker` (лише `archive=true`-гілка — MRV.1 money-tx [ARCH.57]) |
| **Вхід** | `audit_log_id` (Integer) |
| **Сервіси** | `Filecoin::ArchiveService.new(audit_log).archive!` |
| **Side Effects** | [INF.22 крок 11] `sidekiq_retries_exhausted`-hook: вичерпаний archive (Pinata down 5×) інкрементить `FILECOIN_ARCHIVE_EXHAUSTED_TOTAL` — інакше тихо осідав у Dead Set → `ipfs_cid` NULL, sweep не бачить (self-masking клас ARCH.64/65). `FilecoinReconcileWorker` (:48) підбирає за outbox-маркером. |

#### `FilecoinReconcileWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3 |
| **Тригер** | Sidekiq cron: `48 4 * * *` (щодня 04:48 UTC, за 8хв після verification_sweep) |
| **Вхід** | — |
| **Сервіси** | re-enqueue `FilecoinArchiveWorker` |
| **Side Effects** | [INF.22 крок 11 — repair] Дренажить `AuditLog.pending_archive` (outbox-marked money/MRV без `ipfs_cid`; старші за `STALE_THRESHOLD=2h`, у вікні `LOOKBACK=30d`, oldest-first `BATCH_LIMIT=500`) → re-enqueue archive (ідемпотентно, БЕЗ reload-guard — нічого не пише сам). Інкрементить `FILECOIN_REPIN_TOTAL`; depth-gauge `FILECOIN_UNARCHIVED_DEPTH` семплить `Treasury::MonitorService` (15-хв — freshness проти restart-обнулення). Дзеркало ARCH.64/65. Канон: [`06_08 §2.2`](06_08_Resilience_and_Failover_Policy) крок 11. **[E.60 Фаза 1б] Друга нога:** re-enqueue `TelemetryArchiveBatchWorker` для `.reconcilable`-батчів (pending/build_failed > 2h) — backstop первинного enqueue + repair-шлях; терминали поза скоупом. |

#### `TelemetryArchiveBatchWorker` [E.60 Фаза 1б]

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 5 (БЕЗ `unique_for` — шим no-op, а справжній dedup-skip = self-masking «success» без піну; конкурентні копії безпечні через CAS-термінали моделі) |
| **Тригер** | первинний enqueue при створенні batch-row (`Mrv::TelemetryArchiveBatchService`) + `FilecoinReconcileWorker`-backstop |
| **Вхід** | `batch_id` (Integer) |
| **Сервіси** | `Mrv::TelemetryArchiveBatchService.union_logs` (rebuild З ВІКОН, ніколи зі стемп-фільтра) · `Filecoin::ArchiveService.pin_json!` (One-Home Pinata) |
| **Side Effects** | Rebuild → звірка кореня → стемп `telemetry_logs.{archive_root, merkle_leaf}` (raw-SQL VALUES-join, per-slice created_at-межі = partition-pruning, ідемпотентно) → пін артефакту → `mark_pinned!`. Розбіжність: живі логи → `mismatch` (алерт + runbook [`06_08 §4`](06_08_Resilience_and_Failover_Policy)); листя < leaf_count → `retention_expired`; без tx → `superseded`; `build_failed` → repair-спроба (незабрані tx: вдалась → `repair!` → `pending` → пін, root off-chain-only; неможлива → `abandon_repair!` → `superseded`). Read-back'и tx ЗАВЖДИ з `txs_created_from/to`-межами (partition-pruning). `sidekiq_retries_exhausted`-hook: метрика `reason=pin` + `error_message` (стеля: окремого pin_failed-стану нема). Артефакт-формат/семантика — [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline); офлайн-верифікатор = `scripts/verify_archive_bundle.rb`. |

#### `FilecoinVerificationSweepWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 2 |
| **Тригер** | Sidekiq cron: `40 4 * * *` (щодня 04:40 UTC) |
| **Вхід** | — |
| **Сервіси** | `Filecoin::VerificationService.new(audit_log).verify!` |
| **Side Effects** | [E.60] Озброєний content-CID guard: звіряє свіжо-заархівовані (24h) + random-вибірку старших архівів з IPFS. Mismatch → ERROR-лог + `FILECOIN_VERIFICATION_FAILURES_TOTAL{reason}`; gateway-флейк = unreachable (skip, без raise). Канон: [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline). |

#### `StreamrBroadcastWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3 |
| **Тригер** | `TelemetryUnpackerService` (паралельно) |
| **Вхід** | `telemetry_log_id`, `created_at_iso` |
| **Сервіси** | `Streamr::BroadcasterService.new(log).broadcast!` |
| **Side Effects** | Non-critical: при `BroadcastError` лише логує, не reraise. |
| **Prometheus** | `STREAMR_BROADCAST_FAILURES_TOTAL.increment` при `BroadcastError` — [E.50] |

---

## 🔄 12. Карта Ланцюгів Викликів (Call Chains)

### ⚡ Real-time Uplink (per CoAP packet)

```
CoAP UDP (port 5683)
  └─→ UnpackTelemetryWorker [uplink]
        ├─→ TelemetryUnpackerService
        │     ├─→ [SEC.11] resolve (x_prev, y_prev, z_prev):
        │     │     ├─ warm: prev TelemetryLog.lorenz_state_x/y/z
        │     │     └─ cold: SilkenNet::SeedDerivation.initial_state(K_seed, epoch_day)
        │     ├─→ SilkenNet::Attractor.calculate_z_from_state
        │     │     └─ persist log.lorenz_state_x/y/z + cold_start_flag
        │     ├─→ AlertDispatchService.analyze_and_trigger!
        │     │     └─→ EmergencyResponseService.call
        │     │           └─→ ActuatorCommandWorker [downlink]
        │     │                 └─→ ResetActuatorStateWorker [downlink]
        │     ├─→ IotexVerificationWorker [web3_critical]
        │     │     └─→ Iotex::W3bstreamVerificationService
        │     │           └─→ ChainlinkDispatchWorker [web3_critical]
        │     │                 └─→ Chainlink::OracleDispatchService
        │     │                       [Callback] → MintCarbonCoinWorker [web3_critical]
        │     │                                       └─→ BlockchainMintingService
        │     │                                             └─→ BlockchainConfirmationWorker [web3_critical]
        │     └─→ StreamrBroadcastWorker [low] (non-blocking)
        └─→ GatewayTelemetryWorker [uplink] (пульс з QATT-v2 header'а — ARCH.54; DID=0 retired)
              └─→ (AlertNotificationWorker [alerts] — через EwsAlert.after_create_commit при critical_fault)
```

### ⏰ Щоденний Цикл (01:00 UTC)

```
Sidekiq Cron 01:00 UTC
  └─→ DailyAggregationWorker [low]
        └─→ InsightGeneratorOrchestratorWorker [low]
              ├─→ InsightGeneratorService#cluster_baselines (1 SQL)
              └─→ Sidekiq::Batch → N × GenerateClusterInsightWorker [low]
                    └─→ InsightGeneratorService#process_cluster_batch
                          └─→ AlertDispatchService.create_fraud_alert! (при fraud)
                    [on_success] InsightBatchCallbacks
                          ├─→ ClusterHealthCheckWorker [default]
                          │     ├─→ ContractHealthCheckService
                          │     ├─→ CeloRewardWorker [web3] (якщо healthy)
                          │     │     └─→ Celo::CommunityRewardService
                          │     └─→ BurnCarbonTokensWorker [critical] (якщо breached)
                          │           └─→ BlockchainBurningService
                          │                 └─→ BlockchainConfirmationWorker [web3_critical]
                          │     └─→ InsuranceOracleWorker [default] ×N кластерів (за kill-switch)
                          │           └─→ ParametricInsurance#evaluate_daily_health! (Trigger-1)
                          └─→ (ретеншн сюди НЕ підвішений: лише дроп партицій, ARCH.59 ⚖️)
```

> ⚠️ **Гілка `InsuranceOracleWorker` висить під `ClusterHealthCheckWorker`, а НЕ під колбеком** — і саме тому вона жива: колбек у проді не виконується (DOC-R.10), а той воркер має власний cron `0 2 * * *`. Доти fan-out був єдиним enqueue-сайтом оракула, тобто фліп kill-switch нікого не озброював [ARCH.59, 2026-08-25].

### ⏰ Щогодинний Цикл (Tokenomics)

```
Sidekiq Cron (кожну годину)
  └─→ TokenomicsEvaluatorWorker [default]
        └─→ Sidekiq::Batch → EvaluateTreeBatchWorker [default] ×N
              └─→ wallet.lock_and_mint!
                    └─→ MintCarbonCoinWorker [web3_critical]
   (о :55, ОКРЕМИЙ cron — не колбек) MintStallProbeWorker [low]
        └─→ MINT_ELIGIBLE_UNMINTED_DEPTH.set — зріз залишку перед наступним циклом
                          └─→ BlockchainMintingService
                                └─→ BlockchainConfirmationWorker
```

### ⏰ Щотижневий Цикл (Monday 03:00 UTC)

```
Sidekiq Cron Monday 03:00 UTC
  └─→ EthereumAnchorWorker [web3_low]
        └─→ Ethereum::StateAnchorService
              → SHA256(scc_total + chain_hash + timestamp) → Ethereum L1
```

### ⏰ Щоденний Цикл Governance Sync (03:30 UTC)

```
Sidekiq Cron 03:30 UTC (щоденно)
  └─→ Governance::ParameterSyncWorker [web3_low]
        └─→ Eth::Contract (ProtocolParameters.sol) via Web3::RpcConnectionPool
              ├─→ isParameterSet(key) × 8 економічних + 8 DCI-tripwire (Timeout 10s per call)
              ├─→ getParameter(key) для встановлених параметрів
              ├─→ Fixed-point conversion (uint256 / 1e18 → BigDecimal)
              ├─→ bounds-clamp: out-of-bounds → reject + governance_param_rejected_total [GOV.1]
              └─→ SystemParameter.set(key, value, source: "governance", min/max bounds)
```

### ⏰ Цикл Казначейства (кожні 15 хвилин)

```
Sidekiq Cron */15 * * * *
  └─→ TreasuryMonitorWorker [web3_low]
        └─→ Treasury::MonitorService.call
              ├─→ Polygon: Eth::Client.get_balance (MATIC)
              ├─→ Solana: Web3::HttpClient.post → getBalance (SOL)
              ├─→ Celo: Eth::Client.get_balance (CELO)
              ├─→ Ethereum: Eth::Client.get_balance (ETH)
              ├─→ Prometheus gauges: ORACLE_BALANCE, ORACLE_BALANCE_RATIO
              └─→ EwsAlert.create (при balance < threshold)
```

### ⏰ Цикл Батч-Колектора (кожні 5 хвилин)

```
Sidekiq Cron */5 * * * *
  └─→ MintBatchCollectorWorker [web3]
        └─→ Treasury::MintBatchCollectorService.call
              ├─→ BlockchainTransaction.where(status: :pending, blockchain_network: "evm")
              ├─→ Group by token_type (SCC / SFC)
              ├─→ Partition: urgent (>30 min) vs standard (>=5 batch)
              └─→ BlockchainMintingService.call_batch(ids) ×N (per 100 batch)
```

### ⚡ Oracle Callback (Chainlink DON → Workers)

```
POST /api/v1/oracle_callbacks
  └─→ OracleCallbacksController#create
        ├─→ MintCarbonCoinWorker [web3_critical]  (при oracle_status == "fulfilled")
        │     └─→ BlockchainMintingService
        │           └─→ BlockchainConfirmationWorker [web3_critical]
        └─→ SolanaMicroRewardWorker [web3]        (паралельно, той самий callback)
              └─→ Solana::MintingService
```

### 🛰️ Страховий Ланцюг (EWS → DIP → Payout)

```
EwsAlert (fire_detected)
  └─→ DclimateVerificationWorker [alerts]
        └─→ Dclimate::VerificationService
              ├─→ fire_confirmed → InsurancePayoutWorker [critical]
              │     └─→ (Etherisc DIP) Etherisc::ClaimService → BlockchainConfirmationWorker
              │     └─→ (Internal) BlockchainMintingService → BlockchainConfirmationWorker
              └─→ clear_sky_no_fire → BurnCarbonTokensWorker [critical] (fraud slashing)
```

### 📦 Audit + Filecoin Ланцюг

```
Privileged action (money-tx / contract / actuator / role / param / rotate / verdict)
  └─→ AuditLogWorker [low] (attrs, archive)
        └─→ AuditLog.create!
              └─→ archive=true (ЛИШЕ MRV.1 money-tx) → FilecoinArchiveWorker [low]
              │        └─→ Filecoin::ArchiveService (IPFS CID)
              └─→ archive=false [ARCH.57] → chain-only (без IPFS-піна)
```

---

## 🌍 13. Зовнішні API Залежності

| Сервіс | Мережа/Протокол | ENV / Credential | Воркер/Сервіс |
|--------|----------------|-------------------|---------------|
| **Polygon RPC** (Alchemy) | EVM JSON-RPC | `ALCHEMY_POLYGON_RPC_URL` | BlockchainMintingService, BlockchainBurningService, ChainAuditService, KlimaDao |
| **Ethereum L1 RPC** | EVM JSON-RPC | `ALCHEMY_ETHEREUM_RPC_URL` | StateAnchorService |
| **Solana RPC** | JSON-RPC 2.0 | `SOLANA_RPC_URL` + опц. `SOLANA_RPC_URL_FALLBACK_1/2` (INF.22 cascade), `SOLANA_WALLET_KEYPAIR` (mandatory), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS` | Solana::MintingService |
| **Celo RPC** | EVM JSON-RPC | `CELO_RPC_URL` (primary) + опц. `CELO_RPC_URL_FALLBACK_1`, `CELO_RPC_URL_FALLBACK_2` (E.49 cascade через `Web3::ResilientClient`) | Celo::CommunityRewardService, MintingRollbackService |
| **IoTeX W3bstream** | HTTPS REST | `iotex_w3bstream_url`, `iotex_api_key` | Iotex::W3bstreamVerificationService |
| **peaq Network** | HTTPS REST | `peaq_node_url`, `peaq_signing_key` | Peaq::DidRegistryService |
| **Chainlink callback** | Webhook (HMAC-SHA256) | `CHAINLINK_HMAC_SECRET` (dispatch-секрети вилучено — ARCH.53) | Api::V1::OracleCallbacksController |
| **dClimate API** | HTTPS REST | `DCLIMATE_BASE_URL` (default: `https://api.dclimate.net`), `DCLIMATE_FIRMS_DATASET` (default: `firms_nrt_global-area_v2`), `Rails.credentials.dclimate.api_key` (Bearer) | Dclimate::VerificationService |
| **Streamr Network** | HTTPS REST | `streamr_stream_id`, `streamr_api_key` | Streamr::BroadcasterService |
| **Filecoin/IPFS** (Pinata) | HTTPS REST | `filecoin_api_key` / `FILECOIN_PINNING_API_URL` | Filecoin::ArchiveService, VerificationService |
| **The Graph** | GraphQL | `the_graph_api_url` | TheGraph::QueryService |
| **Polygon Hadron** | HTTPS REST | `hadron_api_key` / `HADRON_API_URL` | Polygon::HadronComplianceService |
| **Etherisc DIP** | On-chain (Polygon) | `ETHERISC_DIP_CONTRACT_ADDRESS` | Etherisc::ClaimService |
| **Puro.earth D-MRV Registry** | On-chain (Polygon) + HTTPS REST | `PURO_EARTH_REGISTRY_CONTRACT_ADDRESS`, `ORACLE_PURO_PRIVATE_KEY` (on-chain, activation-gated — INF.22); `PURO_EARTH_API_URL` (default: `https://api.puro.earth`), `Rails.credentials.puro_earth.api_key` або `PURO_EARTH_API_KEY` (REST) | PuroEarth::PassportService, PuroEarth::RegistryApiService |
| **KlimaDAO** | On-chain (Polygon) | `KLIMA_RETIREMENT_CONTRACT` | KlimaDao::RetirementService |
| **CoAP Gateway** | CoAP/UDP | `gateway.ip_address` (dynamic) | `Downlink::PendingQueueService` (poll-тракт). ⚠️ Доти тут стояли `ActuatorCommandWorker, OtaTransmissionWorker` — обидва push-ерні й БЕЗ жодного enqueue-виклику з часів [FW.60](00_07_Action_Plan_Tracker); знімаються post-bench |

---

## 🧭 13b. SSOT Drift Register (Doc ↔ Code Sync)

> **Принцип:** Цей документ — service-шар SSOT; `app/services/` / `app/workers/` — authoritative reality. Метод drift-resolution (код-ahead → онови док; doc-ahead → задача в [`00_07`](00_07_Action_Plan_Tracker)) + дзеркало data-шару (04_01 §12) — [`00_06 §3`](00_06_SSOT_Documentation_Standard). Колишній датований лог виправлень → git.

**Механічна частина — ✅ enforced by `scripts/model_doc_sync.rb`** (CI `docs.yml`): кожен `app/services/**` / `app/workers/**` клас згаданий у цьому реєстрі — зловив би сервіс, повністю відсутній у доку (як `FactoryFlashing::*`-пропуск, що цей гейт і закрив). Семантику (сигнатури/ENV/guard-clauses/queue-розміщення) скрипт НЕ перевіряє — ручний семантичний аудит ([`00_06 §3а`](00_06_SSOT_Documentation_Standard)).

**Відкриті drift-айтеми живуть у [`00_07`](00_07_Action_Plan_Tracker)** (One-Home для backlog — не датований лог у каноні): slashing — positive-A-guard + convex-формула + blackout ✅ (картки §6); відкрите → A-сет-розширення + `penalty_factor`-uplift-активація ([`00_07` — SLASH-1](00_07_Action_Plan_Tracker)).

> **«Planned» (Forester Guild / Cross-Registry / Federated Learning)** — design-RFC, у коді **відсутні** (Post-TRL 6/7, нормально — не code-drift, тому не у `model_doc_sync`).

---

## 🌲 Forester Guild — Proof-of-Physical-Work (design-RFC, маркетплейс ⚫ won't-do)

> **Нотатка N14 інтегрована (Сесія 3).** Відсутній модуль: хто фізично вкручує анкери, міняє обладнання, реагує на EWS-тривоги?

> ⚫ **МАРКЕТПЛЕЙС — WON'T-DO (⚖️ founder 2026-08-24). Підстава КОНСТИТУЦІЙНА, і саме тому вона не дозріває з попитом.**
> У дизайні нижче той самий рейнджер виконує роботу, **сам** подає фотодоказ і отримує USDC за зміст власного свідчення (друга пара очей — опційна, лише понад $100). Тобто платформа платила б **свідкові за вирок**, а [`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap) ставить її протилежно: «корумпований аудитор замінюється **самим деревом**». Маркетплейс не лікує самозвітування — він додає до нього фінансовий інтерес.
> ⛔ **Не відбудовувати як «воно ж спроєктоване».** Незалежність дає правило **«атестатор ≠ бенефіціар»**, а не біржа: її купують договором (сторонній аудитор, академічний партнер, ротація) на порядок дешевше. Розрізнення, ширше за цей блок: присуд, чия підстава — ДЕФЕКТ, помирає разом із фіксом; присуд, чия підстава — **конструкція**, не помирає нічим.
> ✅ **Що лишається живим і НЕ є предметом присуду:** роль `forester` (Модель A — лісник у складі організації), `MaintenanceRecord` як доказовий контур, і сама ПОТРЕБА фізичного виконавця ([`01_04 §5.5`](01_04_CODIT_and_Xylemointegration) робить візит раз на 5–7 років умовою довговічності катода). Дім відкритої роботи — [`00_07`](00_07_Action_Plan_Tracker) E.20.
> 📐 **Секція лишається як design-RFC** — вона документує розібрану механіку (матчинг, race-resolution, anti-Sybil) і підставу відмови; це дешевше, ніж відтворювати аналіз, якщо колись з'явиться незалежний оператор. Числа в ній — `calibration-pending` placeholder'и, і не були нічим іншим.

### Проблема

SilkenNet має бездоганну цифрову державу (фінанси, суди, екологія, ідентифікація). Але хто виконує **фізичну** роботу?

- Хто монтує нові анкери?
- Хто замінює батарею у Queen після зимового дефіциту?
- Хто виїжджає на місце при `EwsAlert` severity = critical?

Поточно: `MaintenanceRecord` — лише лог. Немає системи призначення задач, немає оплати, немає верифікації виконання.

### Архітектура Forester Guild

```
EwsAlert (critical/high severity)
        │
        ▼
ForestBountyService.create_bounty!(ews_alert)
        │ on-chain: SmartContract Bounty (USDC на Polygon)
        ▼
LocalRanger receives SingleNotificationWorker (Push/Telegram)
        │
        │ Ranger виїжджає → виконує роботу → GPS-позначка
        ▼
ForestBountyService.claim_bounty!(ranger_id, proof)
        │ proof: фото + GPS + timestamp (IPFS hash)
        ▼
MaintenanceRecord.create! (з proof_cid + bounty_tx_hash)
        │
        ▼
USDC transferred → Ranger wallet (Polygon)
        │
        ▼
FilecoinArchiveWorker → immutable proof archive
```

**Нові компоненти:**

| Компонент | Тип | Призначення |
|-----------|-----|------------|
| `ForestBountyService` | Service | Створення/закриття bounty задач для лісників |
| `ForestBountyWorker` | Worker (`alerts` queue) | Асинхронне створення on-chain bounty при EwsAlert |
| `ProofOfPhysicalWork` | Model | Зберігає: фото, GPS, timestamp, IPFS CID, ranger_id |
| `ForesterGuild` | Model | Реєстр верифікованих лісників з рейтингом |
| `BountySmartContract.sol` | Solidity | USDC bounty lock/release з time-based expiry |
| `OperatorBond` + `GuildSponsorship` | Model | **[BIZ.13]** Skin-in-game форестера: earned-bond з PoPhW + соціальна застава новачка established-членом. Slash-waterfall + sponsor-політика (DAO-gated) → [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy) |

> **Зв'язок зі slashing [BIZ.13].** PoPhW-винагороди (`ProofOfPhysicalWork`) живлять **operator-bond**, а `ForesterGuild`-реєстр + рейтинг вмикають **guild-sponsor** (поручительство) + reputation-scaling bond-розміру. Це дає форестеру skin-in-game, якого зараз НЕМАЄ (Кат-A slash б'є інвестора за провину оператора — порушення [`00_01 §6`](00_01_Vision_Mission_and_Roadmap) «не карати жертву»). Повна waterfall/sponsor-політика + failure-modes — [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy) (One-Home; DAO-ratify перед імплементацією).

**Інтеграція з існуючими моделями:**
- `MaintenanceRecord` отримує нові поля: `bounty_tx_hash`, `proof_cid`, `ranger_id`, `payout_amount_usdc`
- `EwsAlert` отримує: `bounty_id`, `bounty_status` (open/claimed/expired)

**Пріоритет:** Post-TRL 6. Не блокує прототип.

### Архітектурний дизайн: Task Assignment Algorithm 🤖 (E.20)

> **Cross-ref:** [`00_07` — E.20](00_07_Action_Plan_Tracker) (Forester Guild task-assignment + dClimate-fallback — одна вісь; окремий беклог-рядок був дублем, заархівовано).

Workflow вище показує **створення** bounty та **claim**, але **алгоритм матчингу ranger↔bounty** і пріоритезація не визначені. Без цього система деградує до first-come-first-served race (далекий ranger може вкрасти bounty у локального) або silent expiry (життєво-критична `EwsAlert :critical` залишається без виконавця, бо нікому не повідомили). Цей розділ закриває E.20 (Forester Guild task-assignment).

#### Етап 1 — Bounty Creation (з `EwsAlert`)

`ForestBountyService.create_bounty!(ews_alert, type:)` створює `Bounty` запис з полями:

| Поле | Тип | Призначення |
|------|-----|-------------|
| `ews_alert_id` | FK | Зв'язок з тригерною тривогою |
| `geo_location` | PostGIS POINT | Координати дерева/Queen (для distance scoring) |
| `severity` | enum | `:critical` (час життя 6 год) / `:high` (24 год) / `:medium` (72 год) / `:low` (7 днів) |
| `task_type` | enum | `:fire_response` / `:drone_verification` / `:hardware_replacement` / `:vandalism_inspection` / `:routine_maintenance` |
| `payout_usdc_cents` | bigint | Розмір винагороди (пов'язано з `severity` + `task_type` через `BountyPricingService`) |
| `required_skills` | array<enum> | `[:drone_pilot, :climbing, :electronics, :firefighting]` — capability bitmap |
| `required_certifications` | array<string> | `["EWS_RESPONSE_L1", "DRONE_FAA_PART107"]` (cross-ref `Forester#certifications`) |
| `expires_at` | timestamp | `created_at + severity_ttl(severity)` |
| `state` | AASM | `pending → assigned → in_progress → submitted → verified → paid` (або `expired/disputed`) |
| `assigned_ranger_id` | FK nullable | Заповнюється після матчингу (Етап 3) |
| `assignment_attempt` | int | Лічильник fallback-розширень радіусу (Етап 4) |

#### Етап 2 — Candidate Pool (фільтрація)

`BountyAssignmentService.candidates(bounty)` повертає ranked-list `Forester` записів, **відфільтрованих** за наступними hard constraints:

```
candidates = Forester.active
                     .verified                      # KYC через Hadron pipeline
                     .with_capabilities(bounty.required_skills)
                     .with_certifications(bounty.required_certifications)
                     .within_radius(bounty.geo_location, max_radius_km(bounty.severity))
                     .not_currently_busy            # ranger без open assigned bounty
                     .not_blacklisted_for(bounty.ews_alert.tree.cluster)
```

`max_radius_km(severity)` — escalation-friendly:

| Severity | Початковий радіус | Експонентне розширення (Етап 4) |
|----------|-------------------|----------------------------------|
| `:critical` | 25 км | 50 → 100 → unlimited (через 30 хв each) |
| `:high` | 50 км | 100 → 200 → unlimited (через 2 год each) |
| `:medium` | 100 км | 200 → unlimited (через 12 год each) |
| `:low` | 200 км | unlimited після 24 год |

#### Етап 3 — Scoring & Ranking (matching algorithm)

Кожен candidate отримує **composite score** ∈ [0, 1]:

```
score(ranger, bounty) =
    0.40 × distance_score(ranger.last_known_location, bounty.geo_location)
  + 0.25 × reputation_score(ranger.success_rate, ranger.completed_count)
  + 0.20 × responsiveness_score(ranger.median_ack_time_minutes)
  + 0.10 × specialization_match(ranger.preferred_task_types, bounty.task_type)
  + 0.05 × cluster_familiarity(ranger.cluster_history, bounty.ews_alert.tree.cluster)
```

де:

- `distance_score = max(0, 1 - distance_km / max_radius_km)` (haversine + PostGIS `ST_Distance_Sphere`)
- `reputation_score = success_rate × log10(completed_count + 1) / log10(101)` (Wilson score lower bound для bounty count < 30 — захист від "lucky beginner"-overweight)
- `responsiveness_score = exp(-median_ack_time_minutes / 30)` (швидкість реакції на попередні bounty notifications)
- `specialization_match = 1.0` якщо ranger робив >5 bounty цього task_type, 0.5 якщо 1-5, 0.0 якщо 0
- `cluster_familiarity = 1.0` якщо ranger робив >3 bounty у тому ж `Cluster`, 0.5 — у сусідньому, 0.0 — нове місце

Ваги (`0.40 / 0.25 / 0.20 / 0.10 / 0.05`) — стартові. 🔴 **Механізм їхньої настройки, названий тут, СЬОГОДНІ не існує, і в цій формі існувати не може — виміряно 2026-08-23.** Ключа `forester_assignment_weights` немає ніде (`app/` · `db/seeds.rb` · `PARAMETER_MAP` · `contracts/ProtocolParameters.sol` — нуль), і `spec/quality/system_parameter_delivery_spec.rb` червонів би на ньому за побудовою (`db/seeds.rb`: «ручка, якої ніхто не крутить, не «на майбутнє», а просто не існує»). Плюс форма: `ProtocolParameters.sol` це `mapping(bytes32 => uint256)` — **один скаляр на ключ**, тож вектор із пʼяти ваг у нього не лягає взагалі; DAO-налаштування ваг потребує іншої форми (пʼять окремих ключів ⊥ packed-uint ⊥ off-chain з on-chain хешем), і це частина ⚖️ [`00_07`](00_07_Action_Plan_Tracker) BIZ.13, а не деталь реалізації.

#### Етап 4 — Notification Cascade (escalation)

```
ForestBountyService.assign_and_notify!(bounty):
  candidates = BountyAssignmentService.candidates(bounty).rank_by_score
  top_n = candidates.first(N_for_severity(bounty.severity))
                                              # critical=1, high=3, medium=5, low=10

  if top_n.empty?
    bounty.escalate!                          # експонентне розширення радіусу
    ForestBountyExpansionWorker.perform_in(retry_delay(bounty), bounty.id)
    return
  end

  if bounty.severity == :critical
    # Single best ranger — exclusive lock на 10 хвилин
    bounty.assign_to!(top_n.first, exclusive_until: 10.minutes.from_now)
    SinglePushNotificationWorker.perform_async(top_n.first.id, bounty.id, :urgent)
  else
    # Top-N notification — first to claim wins
    bounty.offer_to!(top_n)                   # state: pending → offered
    top_n.each do |ranger|
      SinglePushNotificationWorker.perform_async(ranger.id, bounty.id, :standard)
    end
  end
```

**Escalation тригери (через `ForestBountyExpansionWorker`):**

| Подія | Дія |
|-------|-----|
| Top-1 critical не ack'нув за 10 хв | Розблокувати exclusive lock, escalate radius, повторно запустити assignment |
| Top-N standard ніхто не claim'ив за 30 хв | Escalate radius, повторно notify (з fresh top-N) |
| Bounty досягло `expires_at` | Залежно від severity: critical → Telegram/email-fallback на регіонального координатора + emergency dispatcher webhook (E.34); інші → fail з notification до `EwsAlert.user` |

#### Етап 5 — Conflict Resolution (race condition при concurrent claim)

При `severity ≠ :critical` Top-N rangers отримують одночасну notification → race на `claim_bounty!`. Pessimistic-lock на DB рівні:

```ruby
# ForestBountyService.claim_bounty!(bounty_id, ranger_id, gps_proof)
ActiveRecord::Base.transaction do
  bounty = Bounty.lock("FOR UPDATE NOWAIT").find(bounty_id)
  raise BountyAlreadyClaimedError if bounty.state != "offered"
  raise BountyExpiredError if bounty.expired?
  raise UnauthorizedClaimError unless bounty.offered_to?(ranger_id)

  bounty.assign_to!(ranger_id, exclusive_until: nil)
  bounty.start_in_progress!(gps_check_in: gps_proof)
end
```

`NOWAIT` гарантує: лузер race миттєво отримає `LockWaitTimeout` → конвертується у `BountyAlreadyClaimedError` з friendly UI message «Цю задачу щойно взяв інший ranger» (без блокування Sidekiq worker'а на DB lock).

#### Етап 6 — Verification & Payout

`ForestBountyService.verify_and_payout!(bounty)`:

1. **Submission validation:** `proof_cid` (IPFS) існує + GPS-точка у радіусі 100 м від `bounty.geo_location` + `submitted_at <= expires_at + 1.hour` grace
2. **EXIF/timestamp check:** Photo metadata не tampered (cross-ref `EXIF::ProofValidator` — окремий сервіс)
3. **Optional second-pair-of-eyes** (для `:critical` payouts > $100): manual review forester admin + PostgreSQL row-level lock
4. **On-chain payout:** `BlockchainTransaction(:pending)` → `PolygonUsdcTransferWorker` (queue: `web3`) → ranger wallet
5. **`MaintenanceRecord.create!(bounty_tx_hash:, proof_cid:, ranger_id:, payout_amount_usdc:)`** — закриває цикл (cross-ref існуюча `MaintenanceRecord` модель)
6. **`FilecoinArchiveWorker`** для immutable proof archive
7. **Reputation update:** `ranger.update!(success_rate: ..., completed_count: ..., median_ack_time_minutes: ...)` — feedback в Етап 3 scoring

#### Crash Recovery & Idempotency

| Сценарій | Recovery |
|----------|----------|
| Ranger не submit'нув до `expires_at + grace` | `BountyExpirationSweepWorker` (cron 5 хв) → state = expired → reputation penalty + re-assign до наступного top-N |
| Backend crash між `claim_bounty!` та `start_in_progress!` | Sidekiq retry → AASM ідемпотентний (re-applies same transition); Pessimistic lock не утримується між requests |
| Подвійний payout (race у Етапі 6) | `BlockchainTransaction(unique_constraint: bounty_id)` + `MintingRollbackService` гарантує single-shot payout (cross-ref §4.2.2 BlockchainMintingService) |
| Ranger підтримує kill switch (екстрена відмова) | `bounty.abandon!(ranger_id, reason)` → reputation penalty залежно від `severity` × `time_since_assigned` → re-assign до next top-N |

#### Anti-Gaming & Sybil Resistance

- **KYC через Hadron** (`Wallet#hadron_kyc_status == "approved"`) — обов'язкова попередня умова для `Forester#verified`
- **Geo-staking:** ranger ставить депозит (refundable USDC) пропорційний радіусу свого operating area; reputation penalty списується з depo, при exhaustion → `Forester#suspended`
- **Cluster blacklist:** `Cluster.exclude_forester!(ranger_id, reason)` — тривалий бан з конкретного кластера (наприклад, після проваленої verification або disputed proof)
- **Captcha-style on-site challenges (Post-TRL 7):** для drone_verification — система генерує специфічну фото-pose-check (наприклад, "сфотографуй конкретний QR на анкері + ваше обличчя"), щоб ускладнити proof-replay attacks

#### Інтеграція з dClimate Fallback (E.34)

При `EwsAlert :critical` + `:obscured_by_clouds` (супутник не може verify) — `ForestBountyService.create_bounty!(ews_alert, type: :drone_verification)` стає **Резервним Оракулом**: ranger летить з дроном, фотографує/знімає відео, IPFS upload → `EwsAlert.resolve_via_bounty!(bounty)` закриває тривогу швидше за наступний clear satellite pass (24-48 год).

#### 🏦 Економічний шар: Positive-A-Guard (✅ SLASH-1 фаза 1) · Operator-Bond · Guild-Sponsor (Planned — BIZ.13)

> **Статус: positive-A-guard ✅ збудовано (фаза 1); operator-bond/guild-sponsor — design-RFC, DAO-gated.** Політика — [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy) (positive-A-guard) + [`05_05 §3.1`](05_05_Slashing_and_Risk_Policy) (bond/sponsor). Тут — implementation-карта на наявних патернах. Економічні параметри = DAO (`ProtocolParameters`), не baseline-канон.

**Економічна модель A→B.** Сьогодні (**Модель A**) `Forester` = `User` у складі investor-`Organization` (вертикальна інтеграція) → org інтерналізує ризик власного оператора. Operator-bond вимагає **Моделі B**: `Forester` як first-class економічний актор (власний bond/reputation, привʼязаний до кластера, який доглядає — operator↔cluster assignment, якого зараз НЕМАЄ). Тож economic-шар будується РАЗОМ з guild-маркетплейсом (E.20), greenfield, не ретрофітом.

**Фаза 1 (✅ landed, Модель A і B) — Positive-A-Guard.** `BlockchainBurningService` перед `slash()` → `Slashing::CauseEvidence#positive_a?`; немає → `:frozen` + Field-Audit (дзеркало `flag_data_blackout!`), НЕ burn. Один guard на чокпоінті накриває всі 4 тригери. A-сет фази-1 свідомо КОНСЕРВАТИВНИЙ = лише tamper (`EwsAlert vandalism_breach`; **НЕ** `HardwareKey.tamper_detected_at` — колонки не існує; **[SLASH-1]** chainsaw тепер РОЗРІЗНИМИЙ окремим `chainsaw_detected`, але в A-сет НЕ входить до field-validation TinyML — клас synthetic placeholder [`03_03 §4.2`](03_03_TinyML_Acoustic_Inference); `critical_unmaintained?` заширокий → обидва на 👤 DAO-розширення). **[SLASH-1 P0] `vandalism_breach` не має автоматичного writer'а:** wire status=3 = `vm_error` (софт-збій → `firmware_fault`), справжня пилка = panic→`chainsaw_detected`; єдине живе джерело — ручна Field-Audit C→A ескалація ([`06_08 §4`](06_08_Resilience_and_Failover_Policy)) → до наповнення A-сету автоматичний необоротний slash не має живого тригера, все йде freeze/Field-Audit (ворота wired, чесно-порожні — [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy)). Супутнє: `ContractHealthCheckService` повертає verdict (не пре-breach); крон `ClusterHealthCheckWorker` гейтить Celo за verdict; `BurnCarbonTokensWorker` пише «надгробок» лише на `:slashed`; `ContractTerminationService`→`contractual: true`. Деталі — [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy).

**Фаза 2 (з guild-маркетплейсом) — нові моделі (дзеркало наявних патернів):**

| Модель | Reuse/дзеркало | Поля (ескіз) |
|--------|----------------|--------------|
| `OperatorBond` | симетрія `ParametricInsurance` (Кат-B↔A); escrow = `Wallet#lock_funds!`/`finalize_spend!` | `belongs_to forester, cluster`; AASM `active→partially_slashed→depleted/released`; `bonded_amount`, `source` (holdback/earned-PoPhW); `has_one blockchain_transaction` |
| `GuildSponsorship` | web-of-trust | `belongs_to sponsor, sponsored (Forester)`; `collateral_amount`; AASM `active→graduated/called`; per-sponsor cap |
| `Forester` (промоція ролі) | `ForesterGuild`-реєстр (§Нові компоненти) | `reputation` (=`reputation_score` §Task Assignment), `bond_balance`, certifications, operator-of-cluster |

**Waterfall** (після positive-A-guard підтвердив A): holdback (`forester_share`-escrow) → operator-bond → sponsor-bond → investor `locked_balance` (excess). **Уніфікація A/B:** `ParametricInsurance#evaluate_daily_health!` (B→payout) і slashing daily-health (A→bond-slash) — паралельні евалуатори; cause-route = розвилка A→bond-waterfall / B→payout / C→freeze (спільне денне читання реалізовано як `DailyHealthRouter` — [INS.1], DRY).

**DAO-параметри + передумови.** bond-sizing `max(BOND_FLOOR, k×expected_cluster_reward)`, holdback-%, sponsor-cap, reputation-scaling (`ProtocolParameters`/`SystemParameter`). ⚠️ **Жодного з цих чотирьох ключів у дереві немає** (перевірено 2026-08-23 по [`05_06 §7`](05_06_Governance_and_DAO) · `db/seeds.rb` · `PARAMETER_MAP` · `ProtocolParameters.sol`), а `BOND_FLOOR` записаний капслоком як константа, будучи словом — 0 збігів. 🔴 **І ширше, про ВСЮ цю секцію: пороги, радіуси, TTL, ваги та грошовий поріг `$100` ручного ревʼю — ВГАДАНІ, джерела не має жоден.** Це легально для design-RFC, але мусить бути сказано вголос, бо цей самий файл декларує протилежний принцип для живого коду (BME280-нога, HW.32) — «жодного вгаданого порогу в slashing-шляху», — а `$100` тут стоїть саме в payout-тракті. **Читати всі числа секції як `calibration-pending` placeholder'и** (форма — [`00_04 §3`](00_04_Nature_as_a_Service_Contracts)); при E.20-go кожне потребує підстави ДО коду. Передумови: operator↔cluster assignment (E.20) + forester-payout disbursement (зараз computed-only) + DAO-ратифікація. Tracked → [`00_07` BIZ.13/SLASH-1](00_07_Action_Plan_Tracker).

---

## 🌍 Planned: Cross-Registry API (Міністерство Закордонних Справ)

> **Нотатка N15 інтегрована (Сесія 3).** Як SCC-токен буде визнаний у "старому світі" — Verra, Gold Standard, ООН?

### Проблема

SilkenNet — ідеальна суверенна держава. Але вона ізольована. Корпоративний покупець карбон-кредитів не може використати SCC для звіту за стандартами:
- **Verra VCS** (найбільший реєстр добровільних вуглецевих кредитів)
- **Gold Standard** (фокус на SDGs)
- **UNFCCC CDM** (Кіотський протокол / Паризька угода)

### Архітектура Cross-Registry Export

```
AuditLog (щоденний snapshot)
        │
        ▼
CrossRegistryExportService.call(format: :verra)
        │ Перетворює Silken Net дані у стандарт реєстру
        ▼
Verra Registry XML / Gold Standard JSON / UNFCCC CDM format
        │
        ▼
FilecoinArchiveWorker → IPFS hash (незмінний архів)
        │
        ▼
VerraApiClient.submit_mrvr(xml_payload)  # MRV Report
        │ або ручний upload через portal
        ▼
Verra визнає SCC → Carbon Credit Certificate
```

**Нові компоненти:**

| Компонент | Тип | Призначення |
|-----------|-----|------------|
| `CrossRegistryExportService` | Service | Трансформація AuditLog у Verra/GS/UNFCCC формат |
| `Verra::ApiClient` | Service | HTTP-клієнт до Verra Registry API |
| `GoldStandard::ApiClient` | Service | HTTP-клієнт до Gold Standard API |
| `CrossRegistryExportWorker` | Worker (`web3_low` queue) | Щомісячний автоматичний export |

**MRV Report структура (Verra VCS):**
```json
{
  "project_id": "silken-net-cherkasy-forest",
  "monitoring_period": { "start": "2026-01-01", "end": "2026-03-31" },
  "trees_monitored": 5000,
  "biomass_growth_kg": 125000,
  "carbon_sequestered_tonnes": 62.5,
  "verification_method": "IoTeX_ZK_proof + peaq_DID + Ethereum_L1_anchor",
  "blockchain_proof": "0x...",
  "ipfs_archive": "bafybeig..."
}
```

✅ **Це НЕ greenfield — перший реальний registry-export уже відвантажено, і планована робота = формат-адаптери × N поверх доведеного патерну.** `PuroEarth::PassportService` + `PuroEarth::RegistryApiService` (обидва `[MAINNET READY]`, картки вище) уже проходять той самий ланцюг, який ця секція малює для Verra: трансформація → канонічний JSON → SHA-256 → on-chain anchor → IPFS → REST submit. Джерело те саме (`AuditLog` immutable-chain), формат-шар звітів (JSON/CSV/PDF) теж стоїть. Тобто `CrossRegistryExportService` — новий **адаптер формату**, а не новий тракт.

⛔ **Схему при цьому НЕ чіпати наперед.** Спокуса завести колонки `vintage` / `serial` / `methodology_id` передчасна з двох боків: перші дві деривуються з періоду `AuditLog`, а серійний номер реєстр **присвоює сам** (Verra зокрема). Доки методології немає, будь-які такі колонки — спекулятивна схема під формат, якого ще не обрано; monitoring-параметри диктує саме затверджений PDD. Гейт вибору реєстру — [`00_07`](00_07_Action_Plan_Tracker) BIZ.9 (методолог → PDD), виконання — [`00_07`](00_07_Action_Plan_Tracker) ARCH.5.

**Пріоритет:** Post-TRL 7. Критично для institutional sales. Не блокує прототип.

---

## 🧠 Planned: Federated Learning Loop (Міністерство Освіти)

> **Нотатка N16 інтегрована (Сесія 3).** Поточна TinyML-модель тренується вручну через Rake-таску. Вона статична.

### Проблема

`silken_forest.marshal` — поточна ML-модель для `InsightGeneratorService`. Вона:
- Тренується вручну командою `rake ai:train` (`lib/tasks/ai_train.rake`; неймспейс `ai`, не `ml` — доти тут стояла адреса, якої в дереві немає)
- Не оновлюється автоматично при появі нових підтверджених даних
- Не враховує сезонні зміни та нові патерни (нові шкідники, нові типи стресу)

### Архітектура Federated Learning Loop

```
Щомісячний тригер (FederatedLearningWorker, cron: 1st of month, 04:00 UTC)
        │
        ▼
Зібрати нові "чорні дані" за місяць:
  - MaintenanceRecord (підтверджені патрульними аномалії)
  - EwsAlert з resolution = "confirmed"
  - TelemetryLog з відомим ground truth
        │
        ▼
FederatedTrainingService.train(new_samples)
  - Завантажує поточний silken_forest.marshal
  - Донавчання на нових даних (incremental fit)
  - Генерує новий marshal файл
        │
        ▼
ModelValidationService.validate(new_model, test_set)
  - Точність на тестовій вибірці > поточна? → proceed
  - Якщо ні → discard, keep old model
        │
        ▼
ActiveStorage: зберегти новий marshal (server-side модель InsightGeneratorService)
AuditLogWorker → запис факту оновлення моделі
```

> ⚠️ **Межа конвеєрів:** `.marshal` (Rumale) — **server-side** модель `InsightGeneratorService`; на STM32 вона НЕ передається (заборонений формат — [`03_03 §11.1`](03_03_TinyML_Acoustic_Inference)). Device-модель TinyML (TFLite INT8, `TinyMlModel`) має окремий retrain/OTA-конвеєр: [`03_03 §11.3`](03_03_TinyML_Acoustic_Inference).

**Нові компоненти:**

| Компонент | Тип | Призначення |
|-----------|-----|------------|
| `FederatedLearningWorker` | Worker (`low` queue) | Щомісячний цикл перенавчання |
| `FederatedTrainingService` | Service | Incremental ML-тренування на нових підтверджених даних |
| `ModelValidationService` | Service | A/B тест нової моделі vs поточної на holdout set |
| `ModelAuditRecord` | Model | Лог кожного оновлення моделі (версія, точність, timestamp, deployer) |

**Безпека:**
- SHA256-хеш нового marshal файлу перевіряється перед активацією (дзеркало наявного integrity-check у `InsightGeneratorService`)
- ⚠️ **Але наявний integrity-check переїзду в ActiveStorage НЕ переживає, і дзеркалити його дослівно було б регресією** [E.52]. Сьогодні `MODEL_DIGEST_PATH` лежить **поруч** із `MODEL_PATH` у репо, тож захищає його git + ревʼю, а не криптографія: хто може перезаписати `.marshal`, той перезапише й `.sha256`. Щойно модель переїде в object storage (крок «зберегти новий marshal» вище), обидва файли опиняться за ОДНІЄЮ межею довіри, і co-located дайджест перестане свідчити про будь-що. Умова активації цього кроку — **підписаний або KMS-pinned дайджест**, чий ключ живе поза бакетом моделі.
- Rollback: якщо нова модель видає >5% false positives за тиждень → auto-revert до попередньої

**Пріоритет:** Post-TRL 7. Не блокує прототип.

---

## Додаткові Матеріали

### Математичні Модулі — Формальний Опис

#### `SilkenNet::Attractor` — Атрактор Лоренца

Система диференціальних рівнянь:

$$\begin{cases} \dot{x} = \sigma(y - x) \\ \dot{y} = x(\rho - z) - y \\ \dot{z} = xy - \beta z \end{cases}$$

Константи: σ = 10.0, ρ = 28.0, β = 8/3. Адаптивні параметри: акустика → σ (clamped 5–30), температура → ρ (clamped 10–50). **[E.63]** β лишається **фіксованим** (`perturb_beta` видалено — `delta_t_s`/`vcap_mv` на Z **не** впливають; метаболізм живить `growth_points` напряму, див. Attractor card вище). **[SEC.11]** Початкова точка `(x₀, y₀, z₀)` ∈ [-1, +1]³ деривується з per-device `K_seed` через `HMAC-SHA256(K_seed, "init|" || epoch_day_be)` (cold start) або читається з попереднього `TelemetryLog.lorenz_state_x/y/z` (warm continuation, mirror RTC DR16-DR18). DID **не** є входом атрактора — лише identifier (та `info`-string у HKDF при provisioning K_seed). 250 ітерацій × 0.01 timestep. **[FIX FW.7]** Float (IEEE 754 double) — байт-ідентично з firmware mruby для Dual Computation Integrity.

Використовується для ідентифікації стресу дерева через відхилення траєкторії z у фазовому просторі. Верифікується ZK-proof через IoTeX W3bstream.

---

### Принципи Безпеки

1. **Zero-Trust:** Кожен пакет шифрується hardware-bound AES ключем у `HardwareKey` (LoRa AES-128 для Tree↔Queen, CoAP AES-256 для Queen↔Rails — domain separation — [`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning)).
2. **Idempotency (шарова):** Фінансові воркери захищені від повторного виконання — status guards + pessimistic lock (concurrent) **+ [ARCH.45]** durable intent-marker + reconcile-guard на on-chain↔DB crash-window. Живі guard'и: `BlockchainTransaction.unsettled_within(window)` (burn 2h · Solana payout / insurance / Etherisc 7d; включає `:manual_review`) + `EthereumAnchor.in_flight` (anchor — DOUBLE-ANCHOR pattern) + `reconcile_in_flight` (Solana batch on-chain звірка). Політика: mint/anchor DOUBLE-ANCHOR; Solana batch / burn / Etherisc / insurance — reconcile/escalate замість сліпого повтору. **[ARCH.51]** flat `BlockchainTransaction.in_flight`-scope видалено як dead code (`unsettled_within` суворо потужніший — `:manual_review` + configurable window). **[ARCH.45→QATT]** Перший не-money різновид патерну: uplink QATT-nonce (`UnpackTelemetryWorker`) = двофазний owner-nonce у Redis (claim `jid` → finalize `"done"` після успішного unpack) — crash-retry = resume замість втрати атестованого батча; семантика [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security). **[ARCH.53]** Окрема shape — *enqueue-after-commit*: worker `update!(state)` ПОТІМ `Worker.perform_async`; краш між → guard `state?` на retry робить early-return → enqueue **загублено**. Фікс за залежністю downstream: **reorder** enqueue-перед-commit (коли downstream не залежить від state — Dclimate slash) · **smart-guard** re-enqueue на retry (downstream залежить — Iotex→Chainlink) · **recovery-cron** (малі таблиці — InsurancePayoutRecovery; НЕ firehose-scale без partial-index) · **idempotency-guard + enqueue-поза-guard** (PuroEarth). Таксономія → [`00_07`](00_07_Action_Plan_Tracker) ARCH.53.
3. **Resilience:** Система підтримує 10+ ретраїв для Web3 операцій та 3–5 для апаратних команд.
4. **Float Determinism:** Розрахунки Атрактора виконуються з Float (IEEE 754 double) ідентично firmware mruby для Dual Computation Integrity (BigDecimal вилучено — давав розбіжність Z після 250 ітерацій хаотичної системи).
5. **ZK-Proof Guard (Path 1):** на oracle-driven шляху (з `telemetry_log`) мінт гейтиться `verified_by_iotex?`; tokenomics-шлях (Path 2) мінтить **оптимістично** на накопичених growth_points БЕЗ цього gate (модель довіри: [`05_02`](05_02_Proof_of_Growth_Pipeline) + [`00_07`](00_07_Action_Plan_Tracker) ARCH.53; DOC.7 guard-inventory вище).
6. **Chainlink Guard (Path 1):** на тому ж шляху — `oracle_status_fulfilled?`; PATH 1 oracle-callback наразі unwired → мінт іде Path 2 ([`00_07`](00_07_Action_Plan_Tracker) ARCH.53). Anti-fraud усіх шляхів = ex-post clawback ([`05_05 §3.3`](05_05_Slashing_and_Risk_Policy)), не pre-mint-gate.
7. **Hadron KYC:** Інституційні інвестори мусять пройти KYC/KYB через Polygon Hadron (ERC-3643) перед отриманням RWA-токенів.
8. **L1 Finality:** Щотижневий state root на Ethereum Mainnet — незнищенний якір усієї економіки.
9. **Immutable Archive:** SHA-256 chain_hash per organization → Filecoin/IPFS (CID) — дані доступні навіть після знищення серверів.

### S3.1 — Guard Clause RSpec покриття (Виконано)

Guard clauses повністю покриті RSpec тестами. Тести верифікують:

| Сценарій | Spec файл | Тести |
|----------|-----------|-------|
| Oracle-driven: IoTeX guard | `spec/services/blockchain_minting_service_spec.rb` | (not verified, pending, dispatched, failed) |
| Oracle-driven: Chainlink guard | `spec/services/blockchain_minting_service_spec.rb` | (pending/dispatched = blocked) |
| Oracle-driven: successful flow | `spec/services/blockchain_minting_service_spec.rb` | (both guards pass → mint + audit trail) |
| Batch emission: bypass guards | `spec/services/blockchain_minting_service_spec.rb` | (no telemetry_log → no guards → mint) |
| Hadron KYC: always enforced | `spec/services/blockchain_minting_service_spec.rb` | (pending/rejected в обох flows, approved pass) |
| Prometheus guard interaction | `spec/services/blockchain_minting_service_spec.rb` | (metrics NOT incremented on guard rejection) |
| IoTeX worker guards | `spec/workers/iotex_verification_worker_spec.rb` | (already-verified skip, pipeline ordering, failure isolation) |
| Chainlink worker guards | `spec/workers/chainlink_dispatch_worker_spec.rb` | (idempotency, oracle_status tracking) |
