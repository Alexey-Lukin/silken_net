# 04_02: Бізнес-Логіка та Сервіси

## 🎯 Мета

Зафіксувати повний реєстр бізнес-логіки Rails-моноліту як Єдине Джерело Істини (SSOT). Документ описує всі **Service Objects** та **Sidekiq Workers**: їхні вхідні дані, відповідальність та вихідні ефекти. Слугує картою поточних сервісів для запобігання дублювання логіки під час розробки нових фіч і REST API (04_03).

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — System Qualified / Mainnet Ready.
- **Обґрунтування:** Всі заглушки (dClimate, Puro.earth) замінено на бойові Web3/HTTP інтеграції. Бізнес-логіка пройшла параноїдальний AI-аудит: повністю усунуто пастки `Network-in-Transaction`, витоки пам'яті (OOM) та ризики подвійної витрати (Double-Spend). Воркери ідемпотентні та fault-tolerant. **Примітка:** Chainlink dispatch має dev/test stub-режим (ENV-gated: при відсутності `CHAINLINK_FUNCTIONS_ROUTER` генерується локальний request ID); production вимагає `CHAINLINK_FUNCTIONS_ROUTER` та `CHAINLINK_SUBSCRIPTION_ID`.
- **Відкрите:** Drift Register моніторинг (§13b); Planned-сервіси (Forester Guild, Cross-Registry, Federated Learning) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) | Схема БД (моделі під сервісами) |
| [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) | Proof-of-Growth пайплайн (порядок сервісів) |
| [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) | Апаратне шифрування, HKDF ключі |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (Drift Register, Planned services) |

### Конвенція впорядкування розділів

1. **Spine** (§1–§9): Service Objects, згруповані за **доменом відповідальності** (Telemetry → AI/Analytics → Polygon → Verification → Contracts → Emergency → Hardware/Security → Finance Oracles). Усередині домену — за порядком виконання у Proof-of-Growth pipeline (раніше зустрічається у потоці → раніше у документі).
2. **Multi-chain rails** (§10): сервіси для не-Polygon мереж (Solana, Celo, Ethereum L1, Filecoin, Streamr, The Graph, dClimate, Toucan, Klima, Hadron) — окремою секцією, бо вони побудовані по тому ж API-патерну (`Web3::RpcConnectionPool` + `Eth::Contract` / `Web3::HttpClient`).
3. **Lore-layer** (§10b): Codex-сервіси — окремий шар, не на критичному шляху телеметрії.
4. **Workers Registry** (§11): з групуванням за **чергами Sidekiq** у строгому порядку дренування (uplink → … → low), а не за доменом. Це навмисне — спрощує діагностику hot path.
5. **Call Chains, External Deps, Planned, Math/Security** (§12–кінець): horizontal cross-cuts і RFC-секції.

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
- [8. Домен: Апаратне Забезпечення та Безпека (Hardware, IoT & Security)](#-8-домен-апаратне-забезпечення-та-безпека-hardware-iot--security) — HardwareKey, OTA HMAC, OtaPackager, **WeakKeyDetector**
- [9. Домен: Фінансові Оракули (Finance Oracles)](#-9-домен-фінансові-оракули-finance-oracles) — `PriceOracleService`
- [10. Домен: Мультичейн — Паралельні Рейки (Multi-chain)](#-10-домен-мультичейн--паралельні-рейки-multi-chain) — Solana, Celo, Klima, Hadron, Ethereum L1, Filecoin, Streamr, The Graph, dClimate, Toucan, Treasury
- [10b. Codex (Lore Layer) Сервіси](#-10b-codex-lore-layer-сервіси)
- [11. Реєстр Воркерів (Workers Registry)](#-11-реєстр-воркерів-workers-registry) — групування за чергами
- [12. Карта Ланцюгів Викликів (Call Chains)](#-12-карта-ланцюгів-викликів-call-chains)
- [13. Зовнішні API Залежності](#-13-зовнішні-api-залежності)
- [13b. SSOT Drift Register (Doc ↔ Code Sync)](#-13b-ssot-drift-register-doc--code-sync)
- [Planned: Forester Guild — Proof-of-Physical-Work (Міністерство Праці)](#-planned-forester-guild--proof-of-physical-work-міністерство-праці)
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
| `Web3::ResilientClient` | Обгортка навколо `Eth::Client` з автоматичним fallback cascade (Primary→Secondary→Public) та Circuit Breaker: `MAX_FAILURES=3` послідовних збоїв → провайдер вимикається на `CIRCUIT_OPEN_DURATION=60s`. Розпізнає `Net::ReadTimeout`, `Errno::ECONNREFUSED`, HTTP 429. Thread-safe (Mutex). Метод `provider_health` для Prometheus-моніторингу. |
| `Web3::WeiConverter` | `BigDecimal`-based конвертація `amount → wei` (ERC-20). Запобігає Float-похибкам у фінансових операціях. |

---

## 🌡️ 2. Домен: Телеметрія (Telemetry)

### `TelemetryUnpackerService`

| | |
|---|---|
| **Файл** | `app/services/telemetry_unpacker_service.rb` |
| **Вхід** | `binary_batch` (сирий бінарний батч), `gateway_id` (Integer, опціонально — `nil` якщо шлюз невідомий), `gateway_attested:` (kwarg, default `false` — **[L1 QATT]** батч пройшов Ed25519-верифікацію Королеви у `UnpackTelemetryWorker`; протягується у `telemetry_logs.gateway_attested` кожного рядка в `commit_telemetry` — обидва шляхи, ECB і CCM) |
| **Що робить** | Розрізає бінарний батч на 21-байтні чанки (`[DID:4][RSSI:1][Payload:16]`). Калібрує сенсорні дані, обчислює Z-значення атрактора Лоренца, записує `TelemetryLog`. Детектує `firmware_mismatch`. Маршрутизує "нульовий" пакет Королеви до `GatewayTelemetryWorker`. **[E.63]** β більше НЕ збурюється метаболізмом — `growth_points` декодується з wire `(status_byte & 0x1F) * 2` (формула на пристрої, [`03_04 §4.3`](03_04_mruby_Lorenz_Attractor)); `metabolism_s`/`voltage_mv` ще передаються у `calculate_z_from_state`, але на Z не впливають. **[FW.8]** `check_z_divergence!` використовує `tree.effective_lorenz_thresholds` (3-tier: cluster override → tree_family → global). **[SEC.11]** Per-tree Lorenz state dispatch: для кожного дерева читає попередній `TelemetryLog.lorenz_state_x/y/z` (warm continuation, mirror RTC DR16-DR18); якщо tail відсутній (cold start після VBAT loss або перший uplink) — деривує `(x₀,y₀,z₀)` з `hardware_keys.binary_lorenz_seed` через `SilkenNet::SeedDerivation.derive_initial_state(K_seed, epoch_day)` і ставить `cold_start_flag = true`. Persist'ить нові `lorenz_state_*` після обчислення Z. Raise `MissingLorenzSeedError` якщо дерево не має provisioned `K_seed` (hard cutover — production guarantee). **[SEC.10]** Frame Counter anti-replay для panic packets — детектує panic через `status_byte & PANIC_FLAG_BIT (0x80)`, читає `panic_frame_counter` BE з `pad_data[2..3]`, виконує SETNX через `Rails.cache.write(unless_exist: true)` з ключем `silken:panic:nonce:{hex_did}:{counter}` і TTL 25 годин. При replay — early return ДО `commit_telemetry` (TelemetryLog не створюється, AlertDispatchService не викликається), Prometheus `silkennet_panic_replay_rejected_total` increment. Counter==0 (legacy firmware) пропускає перевірку. Поза-panic пакети (більшість трафіку) перевірку не платять. **[FW.2 / ARCH.42 Variant B, 2026-05-24]** Паралельний 25-байтний CCM-парсер `process_ccm_chunk` (`[DID:4][RSSI:1][FrameCounter:4 BE][ciphertext:8][MIC:8]`) — feature-flagged через `ENV["TELEMETRY_CCM_ENABLED"]=true` (default off → 21B ECB path без змін). На активному прапорі: (a) AES-128-CCM decrypt + MIC verify через `Cryptography::LoraCcm.decrypt(key:, did_bytes:, frame_counter:, ciphertext:, mic:)` (8-byte AAD=DID‖FC, 12-byte nonce=AAD‖4×0x00, 8-byte tag); MIC fail → `TELEMETRY_CCM_MIC_FAIL_TOTAL` + early return; (b) per-DID Frame Counter SETNX через `silken:ccm:fc:{did}:{fc}` TTL=25h, replay → `TELEMETRY_CCM_FC_REPLAY_REJECTED_TOTAL`; (c) sensor payload unpack `n c C n C C` (Vcap BE, temp i8, acoustic u8, dt BE, status, mesh_ctrl); (d) mesh_ctrl розшифровується як `[ttl:4 \| fw_epoch_nibble:4]` — повна `firmware_version_id` reconstruction потребує OTA epoch config (deferred); (e) Queen sentinel (DID=0) на CCM-шляху не підтримується (Queen self-telemetry мігрує на CoAP self-channel). Успіх → `TELEMETRY_CCM_DECRYPT_OK_TOTAL` + standard `commit_telemetry` pipeline. Firmware-side CCM emit (Soldier `HAL_CRYPEx_AESCCM_Encrypt` + Queen decrypt) — окремий FW.2 subtask, потребує STM32 hardware bench. |
| **Зовнішні виклики** | `SilkenNet::Attractor.calculate_z_from_state(x_prev, y_prev, z_prev, temp, acoustic, metabolism_s, voltage_mv)`, `SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)` (cold-start + ARCH.41 fallback), `AlertDispatchService.analyze_and_trigger!`, `IotexVerificationWorker.perform_async`, `StreamrBroadcastWorker.perform_async`, `GatewayTelemetryWorker.perform_async`, `TimeSyncDownlinkWorker.perform_async` (ARCH.41) |
| **Вихід / Side Effects** | Створює `TelemetryLog` записи (з `lorenz_state_x/y/z` + `cold_start_flag` [SEC.11] + `time_unsynced_fallback` [ARCH.41]). Оновлює `tree.latest_voltage_mv`, `tree.health_streak`. Нараховує `wallet.balance` (growth_points). Позначає `tree.firmware_update_status = :fw_pending` при mismatch. |
| **[ARCH.41] VBAT-loss DCI fallback** | `check_z_divergence!` при warm-start categorical mismatch пробує 3 epoch_day кандидати (today, today−1, `FIRMWARE_RTC_DEFAULT_EPOCH_DAY=10_951`). Для кожного: деривує `(x₀,y₀,z₀) = SilkenNet::SeedDerivation.initial_state(seed_bytes, epoch_day)`, обчислює Z через `Attractor.calculate_z_from_state`. Якщо будь-який кандидат дає категоричний збіг з device — `TelemetryLog#time_unsynced_fallback = true`, `TimeSyncDownlinkWorker.perform_async(cluster_id)` (→ CoAP envelope-only downlink → Queen RTC оновлення → LoRa beacon → Soldier sync). fraud_metric НЕ інкрементується. Cold-start пакети (cold_start_flag=true) recovery не потребують. 9 spec examples. |

### `AlertDispatchService`

| | |
|---|---|
| **Файл** | `app/services/alert_dispatch_service.rb` |
| **Вхід** | `TelemetryLog` (через `.analyze_and_trigger!`) або `Tree` + `message` (через `.create_fraud_alert!`) |
| **Що робить** | Аналізує телеметрію по 5 напрямках: вандалізм (tamper), пожежа/температура, сейсміка, посуха/атрактор, шкідники. Адаптивні пороги (з кластера/породи дерева). Redis-фільтр тиші (5 хвилин per `tree_id:alert_type`). **[SEC.10]** Per-DID rate limiting для critical alerts: `MAX_ALERTS_PER_DID_PER_WINDOW=5` critical alerts за `DID_RATE_LIMIT_WINDOW=1.minute` — захист від replay/injection атак (forged panic packets). Time-bucketed cache key `"ews_did_rate:#{tree.did}:#{time_bucket}"`, TTL = 2 хвилини. Перевищення → warn log + silent drop. |
| **Зовнішні виклики** | `EmergencyResponseService.call`. `AlertNotificationWorker` більше **не** викликається явно — `EwsAlert.after_create_commit :dispatch_notifications!` ставить job у чергу безпечно після commit транзакції (A-1 Transactional Outbox). |
| **Вихід** | Створює `EwsAlert`. Інвалідує `oracle_expected_yield_24h` кеш при critical severity. Повертає `nil` (всі дії через side effects). |

---

## 🧠 3. Домен: AI та Аналітика (AI & Analytics)

### `InsightGeneratorService`

| | |
|---|---|
| **Файл** | `app/services/insight_generator_service.rb` |
| **Вхід** | `date` (Date, default: вчора UTC) |
| **Що робить** | Добова агрегація телеметрії → `AiInsight`. Включає: AI Fraud Guard (відхилення sap_flow/temp від кластерного базлайну > 30%), ML-модель (`silken_forest.marshal` + SHA256 integrity check) або евристика stress_index. Денормалізує `tree.latest_stress_index`. Очищує `TelemetryLog` старше 7 днів — **з виключенням** логів з `oracle_status='dispatched'` (очікують callback від Chainlink; видалення призвело б до `RecordNotFound` у `OracleCallbacksController` і 5 марних ретраїв без мінтингу токенів). |
| **Публічні методи** | `call(date)` / `perform` (сумісність). `cluster_baselines → Hash<cluster_id, baselines>` — один SQL, потрібен `InsightGeneratorOrchestratorWorker`. `process_cluster_batch(cluster_ids) → Integer` — обробка чанку кластерів для `GenerateClusterInsightWorker`. `cleanup_old_logs!` — клас-метод (викликається з `InsightBatchCallbacks`). |
| **Зовнішні виклики** | `AlertDispatchService.create_fraud_alert!` |
| **Вихід** | `{ processed_count: Integer, date: Date }`. Створює `AiInsight` per tree та per cluster. |

> **🌫️ VPD weather-confounder gate [✅ implemented · inert/calibration-pending — HW.32]:** Щоб не штрафувати за погоду (де-ризик [`05_05`](05_05_Slashing_and_Risk_Policy) §6/§7), `stress_index` дисконтується, коли низький `sap_flow` пояснюється **погодою**, а не хворобою: насичене повітря (дощ/туман → **низький VPD**) дає нульову транспіраційну тягу → сік природно падає на здоровому дереві. ✅ **Реалізовано** (`InsightGeneratorService`, наразі інертний no-op + 10 specs): після `calculate_stress_index` викликається `apply_weather_confounder(stress_index, avg_vpd, sap_deviation)` — **discount-only** (ніколи не підвищує stress; fraud=1.0 не чіпається), inert коли `avg_vpd` nil **АБО** калібрування відсутнє. `avg_vpd` плюмиться через `prefetch_tree_stats` (`AVG(vpd)`) і пишеться у `reasoning`. Калібрування — ТІЛЬКИ через ENV `VPD_CONFOUNDER_LOW_KPA` + `VPD_CONFOUNDER_MAX_DISCOUNT` (default unset → no-op; **жодного вгаданого kPa-порогу в slashing-шляху**). **Три залежності перед активацією (свідомо НЕ хардкодимо вгадані пороги у slashing — це суперечило б де-ризику):** (1) ML-модель `silken_forest.marshal` не має VPD-фічі → **retrain** з `[temp, vcap, Z, sap_dev, acoustic, vpd]` (heuristic-only до того); (2) ✅ `calculate_stress_index_heuristic` тепер **вмонтовує sap + acoustic/cavitation** (`sap_stress_contribution` + `acoustic_stress_contribution`, ENV-calibration-gated, беруться через max() не суму — [`05_05 §7`](05_05_Slashing_and_Risk_Policy)); **[E.64] conformance** — прибрано degenerate `avg_z>2`/weather-`temp` confound-члени, Z-anomaly bounded (не auto-1.0, «Z alone never slashes») — лишається ground-truth калібрування ваг; (3) пороги «низький VPD» (kPa) + величина знижки — з **ground-truth калібрування** [`05_05 §8`](05_05_Slashing_and_Risk_Policy). Firmware VPD — `HW.32`/[`03_01`](03_01_Firmware_Lifecycle_and_DMA) (ще не шле → `vpd` nil → gate inert). **Активувати лише після (firmware VPD + ML-retrain + калібрування).**

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
| **Вхід** | `derive_seed(device_uid)` — DID/UID пристрою (позиційний String); `initial_state(seed_bytes, epoch_day = current_epoch_day)` — 32-байтний `K_seed` + UTC epoch day (`Time.now.utc.to_i / 86_400`) |
| **Що робить** | Криптографічна основа для `(x₀, y₀, z₀)` атрактора Лоренца. **`derive_seed`:** виводить per-device `K_seed = HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed\|<DID>", len=32)`. Викликається при provisioning з `HardwareKeyService#provision`. Повертає 64-символьний HEX (upper) щоб лягло у ту саму колонку, що й `aes_key_hex`. **`initial_state`:** обчислює `digest = HMAC-SHA256(K_seed, "init\|" + epoch_day_be8)`; розпаковує в `(x₀, y₀, z₀) ∈ [-1, +1]³` через `signed_unit_float` (8 байт → big-endian uint64 → `(n - UINT64_HALF) / UINT64_HALF`). Daily `epoch_day` rotation дає forward secrecy ≤ 24 год. Hard cutover: raise `SecurityError` без `PROVISIONING_MASTER_KEY` (no SecureRandom fallback ANYWHERE — навіть у dev/test, які pin-ять ключ у `spec/rails_helper.rb`). |
| **Вихід** | `derive_seed → 64-char HEX String (upper)`; `initial_state → [x0, y0, z0]` (Float×3) |
| **Алгоритм та парність** | OpenSSL HKDF-SHA256 (RFC 5869) + HMAC-SHA256. Host-parity test `firmware/test/test_seed_derivation.c` валідує OpenSSL ↔ mbedTLS байт-ідентичність на детермінованих векторах + 100-case fuzz. Backend ↔ firmware деривують `(x₀, y₀, z₀)` byte-identical для тієї самої пари `(K_seed, epoch_day)`. |
| **Викликається з** | `HardwareKeyService#provision` (provisioning), `TelemetryUnpackerService` (cold-start dispatch) |
| **Зовнішні виклики** | `OpenSSL::KDF.hkdf`, `OpenSSL::HMAC.digest("SHA256", …)` |
| **Безпека** | `K_seed` ніколи не залишає Ruby-процес у відкритому вигляді (in-process derivation з `ENV["PROVISIONING_MASTER_KEY"]`). DID використовується лише як `info`-string у HKDF (namespace separator) — криптографічно безпечно. Cross-ref: [`03_05 §3.4в` Lorenz K_seed Derivation](03_05_Hardware_Symmetric_Crypto_and_Security#34в-lorenz-k_seed-derivation-sec11-), [`03_04 §3` Крок 1](03_04_mruby_Lorenz_Attractor#крок-1-походження-початкових-координат-x₀-y₀-z₀-sec11). |

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
| **Що робить** | Обчислює нормалізовану ентропію Шеннона для розподілу Z-значень. Фіксоване бінування по діапазону [2.0, 45.0] (homeostasis zone Лоренца). 20 бінів, ширина ~2.15. Мінімум 30 точок даних для статистичної значущості. Здоровий ліс: diverse Z → entropy ≈ 0.75-0.95. Стрес: homogeneous Z → entropy < 0.5. **[Lorenz de-risk]** інтерпретація Z-розподіл → здоров'я лісу — недоведена гіпотеза ([`05_05`](05_05_Slashing_and_Risk_Policy) §7–8); сигнал, не вердикт. |
| **Чому Z-value, а не HRNG seed** | `chaos_seed` (HRNG) НЕ передається у 21-байтному LoRa-пакеті (03_01, Phase 2). Backend використовує z_value як проксі. Див. ЧДТУ task #12 (08_02 §2). |
| **Математика** | `H = -Σ p(x) × log₂(p(x))`, `H_norm = H / log₂(NUM_BINS)` ∈ [0.0, 1.0] |
| **Вихід** | `Float` (0.0-1.0) або `nil` (недостатньо даних). |

### `TreeChronicleService`

| | |
|---|---|
| **Файл** | `app/services/tree_chronicle_service.rb` |
| **Вхід** | `tree:` (Tree AR instance), `page:` (Integer, default: 1), `per_page:` (Integer, 1–100, default: 20) |
| **Що робить** | Агрегує «цифровий життєпис» дерева з 4 джерел: `AiInsight` (homeostasis / stress / fraud), `EwsAlert` (alert + recovery при resolved), `MaintenanceRecord`, `BlockchainTransaction` (status: confirmed). Об'єднує всі записи у єдиний масив `Entry` (Data.define), сортує за датою DESC, пагінує вручну через `Pagy::Offset` (без додаткових DB-запитів на весь масив). Ліміти: 50 insights, 30 alerts, 20 maintenance, 20 blockchain. Не потребує нових таблиць. |
| **Зовнішні виклики** | `TreeChronicle::TextFormatter` — генерує i18n-ready текстові шаблони |
| **Вихід** | `{ entries: Array<TreeChronicleService::Entry>, pagy: Pagy::Offset }`. Entry fields: `date, event_type, icon, title, description, severity, source_type, source_id`. |
| **Масштабування** | Кожна модель має індекси на `created_at + tree_id`. `per_page` обмежено 100. |

### `TreeChronicle::TextFormatter`

| | |
|---|---|
| **Файл** | `app/services/tree_chronicle/text_formatter.rb` |
| **Вхід** | Модельні об'єкти (AiInsight, EwsAlert, MaintenanceRecord, BlockchainTransaction) |
| **Що робить** | Централізує всі текстові шаблони хроніки. Методи: `homeostasis_title/description`, `stress_title/description`, `fraud_title/description`, `alert_icon/title/description`, `recovery_title/description`, `maintenance_title/description`, `minting_title/description`. |
| **i18n** | Усі методи повертають рядки. При додаванні I18n достатньо замінити рядки на `I18n.t(...)` без зміни архітектури. |
| **Вихід** | Рядки (String). |

---

## 🔗 4. Домен: Блокчейн — Polygon (Primary Chain)

### `BlockchainMintingService`

| | |
|---|---|
| **Файл** | `app/services/blockchain_minting_service.rb` |
| **Інтерфейс** | Два методи: `.call(id: Integer, telemetry_log: nil)` — одиночний мінтинг; `.call_batch(ids: Array<Integer>, telemetry_log: nil)` — пакетний мінтинг |
| **Вхід** | `.call`: `id` (Integer); `.call_batch`: `ids` (Array\<Integer>); `telemetry_log:` (опціонально, для oracle-driven flow) |
| **Що робить** | Пакетна емісія SCC/SFC на Polygon через `mint` або `batchMint`. Guard clauses: `verified_by_iotex?`, `oracle_status_fulfilled?` (enum method), `hadron_kyc_status == "approved"`. **[BLOCKER-11 / S6.12]** Guards `verified_by_iotex?` + `oracle_status_fulfilled?` активні **лише** при `telemetry_log:` (oracle-driven flow Path 1). У tokenomics-flow Path 2 (`TokenomicsEvaluatorWorker → EvaluateTreeBatchWorker → wallet.lock_and_mint! → process_batch → call_batch(ids)` без `telemetry_log:`) ці перевірки **свідомо пропускаються** — `growth_points` вже зараховані через `Wallet#credit!` після AES-256-CBC decrypt + `valid_sensor_data?` у `TelemetryUnpackerService` (per-packet integrity perimeter). `hadron_kyc_status == "approved"` — **єдиний обов'язковий guard для всіх шляхів** (security perimeter проти non-compliant wallets). При `hadron_kyc_status != "approved"` — raise `Compliance Breach` без виклику `transact`; transaction залишається `:pending`, `locked_points` не звільняються (потребують admin-розблокування або повторної KYC). Spec coverage: `spec/services/blockchain_minting_service_spec.rb` → context "tokenomics flow without telemetry_log [S6.12]". Cross-ref: [05_02 Усі Шляхи до lock_and_mint! [DOC.7]](../docs/05_02_Proof_of_Growth_Pipeline#усі-шляхи-до-walletlock_and_mint-guard-inventory-doc7). Dynamic Tax 2% при carbon_coin + недофінансований страховий пул (→ DAO Treasury). `Kredis.lock(expires_in: 120.seconds)` проти race conditions (120s покриває worst-case: dry-run + binary search isolation до 6 рівнів ≈ ~130s). `transact` (fire-and-forget). Prometheus metric `SCC_MINTED_TOTAL`. **[B-05]** `insurance_pool_requires_funding?` — cached on-chain `balanceOf` oracle: `INSURANCE_POOL_THRESHOLD = 100_000 SCC`; кеш 15 хв (`dao_treasury_needs_funding`); timeout 10 сек; failsafe → `true` при збої RPC. **[DRY-RUN GUARD]** Перед кожним `batchMint` виконується `eth_call` симуляція (`batch_dry_run_reverts?`) — zero-gas виконання на поточному блоці. Якщо симуляція повертає EVM revert (ознаки: `"revert"`, `"execution reverted"`, `"out of gas"`), активується **Binary Search Poisoned Record Isolation** (Divide & Conquer): замість наївного fallback на N×`mint()`, алгоритм розбиває батч навпіл і тестує кожну половину через `eth_call` dry-run. "Чисті" половини відправляються через `batchMint`, "отруйні" — далі діляться рекурсивно до `MIN_BINARY_SEARCH_SIZE=4` або `MAX_BINARY_SEARCH_DEPTH=6`. Результат: для типового сценарію (1-2 отруйних з 100) ~14 `eth_call` + 2-3 `batchMint` замість 100 `mint()`. `POISONED_RATIO_THRESHOLD=0.3` — при >30% отруйних binary search неефективний → fallback на індивідуальні mints. `send_clean_batch` відправляє чисті підбатчі через `batchMint` з fallback на `mint_individual` при збої transact. Мережеві помилки (RPC timeout) не рахуються як revert — оптимістичний фолбек на `transact`. |
| **Зовнішні виклики** | Polygon RPC (`ALCHEMY_POLYGON_RPC_URL`), `Web3::RpcConnectionPool`, `Web3::WeiConverter`, `BlockchainConfirmationWorker.perform_in` |
| **Вихід** | `tx_hash` (String). Оновлює `BlockchainTransaction.status = :sent`. Turbo Stream broadcast балансу гаманця. |

### `BlockchainBurningService`

| | |
|---|---|
| **Файл** | `app/services/blockchain_burning_service.rb` |
| **Вхід** | `organization_id`, `naas_contract_id`, `source_tree:` (опціонально) |
| **Що робить** | Slashing Protocol. Розраховує `damage_ratio` через `AiInsight` (% критично стресованих дерев кластера). Викликає `slash(investor_address, amount_wei)` на Polygon. Маркує `NaasContract.status = :breached`. Prometheus metric `SCC_SLASHED_TOTAL`. |
| **Зовнішні виклики** | Polygon RPC, `BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)`, `EwsAlert.create!` (при помилці) |
| **Вихід** | `tx_hash` (String) або raise StandardError. Створює `BlockchainTransaction` (audit). |

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
| **Що робить** | **[DOUBLE-SPEND GUARD]** Rollback при вичерпанні всіх Sidekiq-ретраїв у `MintCarbonCoinWorker`. Логіка вирішення: (1) `tx_hash` відсутній → безпечний rollback (транзакція не покинула бекенд): розблоковує `locked_balance`, маркує `status = :failed`; (2) `tx_hash` існує → перевіряє стан on-chain через RPC: а) receipt підтверджено → `tx.confirm!` (НЕ rollback); б) receipt null (pending) → `escalate_to_review!` (кошти залишаються заблокованими); в) RPC timeout → `escalate_to_review!`. Multichain: EVM-мережі використовують `eth_getTransactionReceipt`; Solana — `getTransaction` через прямий HTTP-запит. **[BUGFIX 2026-05-18 envelope-aware]** `fetch_evm_transaction_receipt` делегує до `classify_evm_receipt(envelope)` — приватного хелпера, який приймає або wrapped JSON-RPC відповідь (`{"id":…, "result": {"status":"0x1"}}`, реальний eth gem 0.5.x) або flat shape (`{"status":"0x1"}`, легасі-фікстура). Раніше код читав `receipt["status"]` напряму на envelope-формі, де статус живе під `result.status`, тому ВСЯ продакшн-телеметрія класифікувалась як `:reverted` → safe rollback розблоковував кошти навіть для confirmed on-chain mint'ів (точно та double-spend дірка, яку сервіс мав закривати). Тепер: `nil`/`{}` envelope → `:pending`; `result` null/empty → `:pending`; `status` ∈ {"0x1", "0x01", 1} → `:confirmed`; `status == nil` → `:pending`; інше → `:reverted`. **[E.49]** Per-chain fallback cascade: для Polygon — `fallback: "https://polygon-rpc.com"` + `fallback_env_keys: ["INFURA_POLYGON_RPC_URL"]`; для Celo — `fallback: Celo::CommunityRewardService::DEFAULT_RPC_URL` + `fallback_env_keys: Celo::CommunityRewardService::RPC_FALLBACK_ENV_KEYS` (раніше fallback для Celo вказував на polygon-rpc.com — баг виправлено). |
| **Вихід** | `nil`. Side effects: `wallet.release_locked_funds!` + `tx.update!(status: :failed)` + Turbo broadcast (при safe rollback); або `tx.escalate_to_review!(reason)` (при manual_review). |

### `PuroEarth::PassportService`

| | |
|---|---|
| **Файл** | `app/services/puro_earth/passport_service.rb` |
| **Вхід** | `payload` (Hash: `tree_did`, `biomass_yield_kg`, `extraction_date`, `gps_coordinates`, `lifetime_telemetry_hash`) |
| **Що робить** | **[MAINNET READY]** Anchors a cryptographic proof of a Biomass Passport onto Polygon for Puro.earth D-MRV (Digital Measurement, Reporting and Verification) / CORC generation. 1) Витягує поля payload у фіксованому алфавітному порядку через `extract_canonical_fields` — рекурсивний обхід хешу з явним ABI-типізуванням (`"string"`, `"uint256"`). Float/BigDecimal масштабуються на `ABI_DECIMAL_SCALE = 10^18` і перетворюються в `uint256` для збереження точності. 2) Кодує поля через `Eth::Abi.encode(types, values)` — бінарне кодування, визначене специфікацією EVM, крос-платформне та мово-незалежне (усуває артефакти Ruby JSON: float-форматування, unicode-екранування, порядок ключів). 3) Обчислює SHA-256 від ABI-кодованого бінарного blob. 4) Викликає `anchorPassport(treeDid, bytes32(payloadHash))` на D-MRV Registry смарт-контракті Polygon через `Web3::RpcConnectionPool` + `Eth::Contract`. Підпис через `ORACLE_PRIVATE_KEY`. Метод `deep_sort_keys` збережено для зворотної сумісності. |
| **Зовнішні виклики** | Polygon RPC (`ALCHEMY_POLYGON_RPC_URL`), `PURO_EARTH_REGISTRY_CONTRACT_ADDRESS` (D-MRV Registry), `ORACLE_PRIVATE_KEY` |
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
| **Що робить** | Oracle-mode виплата через Etherisc DIP на Polygon. Викликає `triggerClaim(policyId)`. Виплата в USDC з децентралізованого пулу (усуває інфляційний тиск на SCC). |
| **Зовнішні виклики** | Polygon RPC, `ETHERISC_DIP_CONTRACT_ADDRESS` |
| **Вихід** | `tx_hash` (String). |

---

## 🛡️ 5. Домен: Верифікація та Ідентичність (Verification & Identity)

### `Iotex::W3bstreamVerificationService`

| | |
|---|---|
| **Файл** | `app/services/iotex/w3bstream_verification_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | Відправляє телеметрію до IoTeX W3bstream для генерації ZK-proof. Payload: `device_id`, `peaq_did`, `hardware_signature`, `chaotic_data` (z_value, temp, acoustic, voltage, bio_status). **[BLOCKER-06]** `hardware_signature` = Ed25519-підпис payload'у; seed = `HardwareKeyService.derive_iotex_seed(tree.did)` (HKDF з master — **не** `binary_key`: post-ARCH.42 Tree AES=16B недосить для Ed25519) над `message = "#{tree.did}:#{log.id_value}:#{log.created_at.to_i}"`. **Чесно:** seed деривує backend (master-holder) → підпис доводить **цілісність pipeline + DID-binding**, а НЕ криптопоходження «саме цей STM32» (custodial). Device-bound origin = true-DePIN ladder ([`05_02` — Trust-origin ladder](05_02_Proof_of_Growth_Pipeline)). **[S6.13] Fallback-режим:** при відсутності `HardwareKey` (legacy/dev, TRL ≤ 5) сервіс інкрементує `silkennet_w3bstream_signature_fallback_total{reason}` counter. У production OR `WEB3_STRICT_MODE=true` fallback **fail-closed** — raise `VerificationError` без виклику W3bstream (SHA256-хеш доступний будь-кому хто знає `tree.did`, тому не еквівалентний Ed25519). У dev/test без strict-mode — warn-log + SHA256 fallback (для лабораторних benches без provisioned ключів). Шлях відновлення продакшн-deploy після alert: `POST /api/v1/provisioning/register` для дерева, що тригернуло fallback. **[BLOCKER-07]** Валідація формату `zk_proof_ref` через regex: `/\A[0-9a-zA-Z\-_]{8,128}\z/` — захист від injection довільних рядків. |
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
   - `peaq_signing_key_previous` — старий ключ (валідний протягом overlap window)
3. Backend приймає підписи від обох ключів протягом **72-годинного overlap window**
4. Після закінчення overlap window: видалити `peaq_signing_key_previous` з credentials

**2. Migration Strategy**

- Усі нові DID реєстрації під час overlap використовують **новий** ключ
- Існуючі DIDs зберігають оригінальні підписи (immutable on peaq chain)
- Повторна реєстрація **НЕ** потрібна — DID-документи є append-only на peaq
- `verification_method` у proof вказує на конкретний ключ (`#key-1`, `#key-2`), тому старі proof залишаються валідними

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

### `Chainlink::OracleDispatchService`

| | |
|---|---|
| **Файл** | `app/services/chainlink/oracle_dispatch_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | Відправляє верифіковану телеметрію до Chainlink Functions DON. Guard clause: `verified_by_iotex? == true`. Payload: `peaq_did`, `lorenz_state` (σ,ρ,β,z), `zk_proof_ref`, `tree_did`, `created_at` (partition key). **[BLOCKER-09 / S6.15 ✅]** ABI делегований у `Web3::ChainlinkRouterVersion` registry (`app/services/web3/chainlink_router_version.rb`) — `VERSION_ORDER = [:v1]`, кожна версія тримає `:abi`, canonical `:signature` та pre-computed keccak256 `:selector` (v1 = `sendRequest(uint64,bytes,uint16,uint32,bytes32)` → `0x461d2762`). Перед on-chain dispatch виконується `pick_router_version`: (a) читає `CHAINLINK_ROUTER_VERSION` ENV (default `:v1`); (b) `eth_getCode(router_address)` + `selector_present_in_code?` — якщо активний selector відсутній у байт-коді Router'а, пробує `fallback_for(version)` (одна крок назад); (c) raises `DispatchError` якщо ні активна, ні fallback версія не підтверджена; (d) `CHAINLINK_ROUTER_BYTECODE_CHECK=false` вимикає probe для staging/RPC без `eth_getCode`. **Процес upgrade ABI:** додати новий запис у `REGISTRY` (наприклад `:v2`), додати `:v2` у `VERSION_ORDER` (наприкінці — chronological order), пере-обчислити selector через `Eth::Util.keccak256(canonical_signature)`, потім перемкнути `CHAINLINK_ROUTER_VERSION=v2` у Kamal/Akash env coordinated з deploy нового Router'а — попередня версія залишається як автоматичний fallback. **[BLOCKER-04]** `WEB3_STRICT_MODE=true` → raises `DispatchError` при відсутності credentials замість stub mode. |
| **Зовнішні виклики** | Polygon RPC → `FunctionsRouter.sendRequest` |
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

### `ContractHealthCheckService`

| | |
|---|---|
| **Файл** | `app/services/contract_health_check_service.rb` |
| **Вхід** | `naas_contract` (NaasContract), `target_date` (Date, default: `cluster.local_yesterday`) |
| **Що робить** | Перевіряє здоров'я кластера: якщо > 20% активних дерев мають `stress_index >= 0.83` → Slashing. Відсутність даних > 24 год = автоматичне порушення. |
| **Зовнішні виклики** | `BurnCarbonTokensWorker.perform_async` (при breach) |
| **Вихід** | `nil`. Side effect: `naas_contract.update!(status: :breached)`. |

### `ContractTerminationService`

| | |
|---|---|
| **Файл** | `app/services/contract_termination_service.rb` |
| **Вхід** | `naas_contract` (NaasContract) |
| **Що робить** | Дострокове розірвання контракту. Валідація: `status_active?` та `min_days_before_exit`. Розраховує `calculate_prorated_refund` та `calculate_early_exit_fee`. |
| **Зовнішні виклики** | `BurnCarbonTokensWorker.perform_async` (якщо `burn_accrued_points == true`) |
| **Вихід** | `{ refund: BigDecimal, fee: BigDecimal, burned: Boolean }`. |

---

## 🚨 7. Домен: Надзвичайне Реагування (Emergency Response)

### `EmergencyResponseService`

| | |
|---|---|
| **Файл** | `app/services/emergency_response_service.rb` |
| **Вхід** | `ews_alert` (EwsAlert AR instance) |
| **Що робить** | Визначає протокол фізичної відповіді за типом загрози: `severe_drought` → відкрити water_valve (2г), `fire_detected` → water_valve (4г) + fire_siren (1г), `insect_epidemic` → water_valve (1г), `seismic_anomaly` → seismic_beacon (30хв). Пріоритизує актуатори за відстанню до дерева (`SilkenNet::GeoUtils`). Масове `insert_all` для ActuatorCommand. |
| **Зовнішні виклики** | `ActuatorCommandWorker.perform_async` per command |
| **Вихід** | `nil`. Side effect: Масово створює `ActuatorCommand` записи. |

---

## 🔧 8. Домен: Апаратне Забезпечення та Безпека (Hardware, IoT & Security)

### `HardwareKeyService`

| | |
|---|---|
| **Файл** | `app/services/hardware_key_service.rb` |
| **Вхід** | `.provision(device)` або `.rotate(device_uid)` |
| **Що робить** | **Provision** (post-ARCH.42 Variant B, 2026-05-23): атомарно деривує **AES ключ за device_type** — Tree → `derive_lora_key` (16 байт, info `"silken-aes-128-lora-key"`); Gateway → `derive_device_key` (32 байти, info `"silken-aes-256-device-key"`). Плюс `K_seed` для атрактора Лоренца (`SilkenNet::SeedDerivation.derive_seed`, 32 байти). Зберігає у `HardwareKey` (`aes_key_hex` conditional length + `lorenz_seed_hex` [SEC.11]). HKDF-only — raise `SecurityError` без `PROVISIONING_MASTER_KEY` (no SecureRandom fallback ANYWHERE; pre-prod hard cutover). **Rotate**: Dual-Key Handshake — старий AES ключ → `previous_aes_key_hex`, генерує новий тієї самої довжини, відправляє Downlink `sys/key_update` шифрований старим ключем. Захист від подвійної ротації (`RotationPendingError`). |
| **Зовнішні виклики** | `OpenSSL::KDF.hkdf` (через `SilkenNet::SeedDerivation`), `ActuatorCommandWorker.perform_async` (для key update downlink) |
| **Вихід** | Provision: `HardwareKey` instance з обома секретами. Rotate: `new_hex_key` (String, **32 hex для Tree LoRa / 64 hex для Gateway CoAP** після ARCH.42). Raises `RotationPendingError`, `SecurityError`. |

### `OtaHmacKeyService` 🔐 [FW.23]

| | |
|---|---|
| **Файл** | `app/services/ota_hmac_key_service.rb` |
| **Вхід** | `cluster_id` (Integer або String) |
| **Що робить** | Per-cluster OTA HMAC ключ `K_ota` для аутентифікації bytecode на Soldier (dual-gate). Дериває `K_ota = HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="cluster:#{id}", info="silken-ota-hmac-v1", len=32)`. **Domain separation** від `HardwareKeyService` AES device-keys: info `"silken-aes-128-lora-key"` (Tree LoRa) та `"silken-aes-256-device-key"` (Gateway CoAP) — компрометація одного K-вектора не розкриває інших трьох. Слідує патерну SEC.11: raise `SecurityError` без `PROVISIONING_MASTER_KEY` (no SecureRandom fallback в production; dev/test pin-ять ключ у `spec/rails_helper.rb`). |
| **Зовнішні виклики** | `OpenSSL::KDF.hkdf` |
| **Публічні методи** | `.fetch_for(cluster_id) → String` (64-символьний HEX, upper); `.fetch_binary_for(cluster_id) → String` (32 binary bytes) — для прямого `OpenSSL::HMAC.digest` |
| **Вихід** | 64-символьний HEX або 32-байтна binary-string. |
| **Cross-ref** | [`03_05 §3.4б`](03_05_Hardware_Symmetric_Crypto_and_Security) — повний протокол OTA HMAC dual-gate. |

### `OtaPackagerService`

| | |
|---|---|
| **Файл** | `app/services/ota_packager_service.rb` |
| **Вхід** | `firmware` (BioContractFirmware або TinyMlModel), `chunk_size:` (default 512 bytes CoAP), `cluster_id:` (опціонально — Integer/String; вмикає HMAC trailer [FW.23]) |
| **Що робить** | Фрагментує `firmware.binary_payload` на чанки. Додає заголовок `[0x99][Index:uint16][Total:uint16]` + CRC16-CCITT per chunk. **[FW.23]** При `cluster_id:` — після bytecode-чанків емітує 3 HMAC trailer-чанки (детально нижче). |
| **[FW.8] `build_threshold_config_block(tree)`** | Клас-метод. Будує `CMD_SET_THRESHOLDS` (0x9A) OTA Config Block для передачі per-species Lorenz порогів на Soldier без перекомпіляції. Читає `tree.effective_lorenz_thresholds` → упаковує у 10-байтовий payload: `[z_min×100:int16_le][z_max×100:int16_le][z_opt×100:int16_le][species_id:uint8][config_version:uint8][crc16:uint16_le]`. Prefixed: `[CMD_SET_THRESHOLDS:1][len:uint16_le][payload]`. |
| **[FW.23] `compute_hmac_tag(bytecode, version_id, lora_total_chunks, cluster_id:)`** | Клас-метод. Обчислює HMAC-SHA256 по `bytecode \|\| version_id_be(4) \|\| lora_total_chunks_be(2)`. Anti-replay: `version_id` прив'язує тег до конкретної ревізії. Anti-truncation: `lora_total_chunks` в тезі — скидання будь-якого trailing-чанку детектується як HMAC mismatch на Soldier. Повертає 32-byte binary digest. |
| **[FW.23] `build_hmac_trailer_chunks(hmac_tag, lora_total_chunks)`** | Клас-метод. Розбиває 32-байтний тег на 3 LoRa-форматованих 16-байтових блоки: `[0x9B][seg_idx:2 BE][lora_total:2 BE][hmac_seg:11]`. Сегмент 3 має 10 реальних байт + 1 NUL PAD. Queen relay-ює їх stateless; Soldier збирає через `Parse_HMAC_Trailer_Chunk`. |
| **OTA Command Constants (SSOT)** | `CMD_OTA_BYTECODE=0x99` (mruby chunks), `CMD_SET_THRESHOLDS=0x9A` (FW.8 Lorenz Z), `CMD_HMAC_TRAILER=0x9B` (FW.23 OTA HMAC печатка), `CMD_TIME_SYNC=0x9C` (FW.20 RTC correction), `CMD_SET_AUDIO_THRESHOLDS=0x9D` (FW.18 TinyML confidence thresholds). Повна карта опкодів: [`03_01 §4.5а`](03_01_Firmware_Lifecycle_and_DMA). |
| **HMAC Constants** | `HMAC_TAG_BYTES=32`, `HMAC_TRAILER_SEGMENTS=3`, `HMAC_SEG_BYTES=11`, `HMAC_TRAILER_BLOCK=16` |
| **Вихід (без cluster_id)** | `{ manifest: { version, total_size, checksum, sha256, total_chunks }, packages: Enumerator<16-byte blocks> }` |
| **Вихід (з cluster_id)** | `{ manifest: { version, total_size, checksum, sha256, total_chunks, lora_total_chunks, total_packages, hmac_signed: true, hmac_cluster_id }, packages: Enumerator<bytecode_chunks + 3 trailer_chunks> }` — `total_packages = total_chunks + 3`; `OtaTransmissionWorker` ітерує по `packages` без змін у логіці pacing. |

### `Security::WeakKeyDetector` 🔐 [SEC.9]

| | |
|---|---|
| **Файл** | `app/services/security/weak_key_detector.rb` |
| **Вхід** | `value` (String, nullable — типово вміст ENV-змінної), `hint:` (String, опц. — назва секрету для повідомлень) |
| **Що робить** | Виявляє слабкі / відомі test-vector master-секрети. Перевіряє три інтерпретації введеного значення (raw bytes, hex-decoded, base64-decoded — лише якщо round-trip lossless) проти трьох категорій патернів: **(1) Known test vectors** — FIPS-197 Appendix B (AES-128, той самий вектор, що мав firmware ключ в оригінальному BLOCKER), FIPS-197 C.1/C.2/C.3, NIST SP 800-38A F.5, RFC 3686 §6, RFC 4231 Test Cases 1/3/6/7, FIPS 198-1; перевіряє і exact match, і prefix match (≥8 байт overlap). **(2) Degenerate patterns** — all-zero, all-0xFF, single-byte repeat, strictly monotonic byte run (delta ±1). **(3) Placeholder substrings** (ASCII only) — `CHANGEME`, `PLACEHOLDER`, `TODO`, `your-master-…`, `replace-me`, `not-a-real-key`, `<…>` template artefacts тощо. |
| **Зовнішні виклики** | — (in-memory). Залежить від `OpenSSL`, `Base64`. |
| **Публічні методи** | `.detect(value, hint:) → nil \| String` (повертає reason-string з опц. префіксом hint, якщо знайдено патерн); `.weak?(value, hint:) → Boolean` |
| **Тест coverage** | `spec/services/security/weak_key_detector_spec.rb` — 30+ examples, fuzz через RFC vectors, edge-cases для round-trip base64 та bytestring-encoding |
| **Інвокери** | `config/initializers/master_key_strength_check.rb` (boot-time guard, див. нижче) |
| **Cross-ref** | [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security), [`00_07` — SEC.9](00_07_Action_Plan_Tracker). Закриває оригінальний BLOCKER (firmware AES key перших 16 байт співпадали з FIPS-197 Appendix B). |

#### Boot-time master key guard (initializer)

| | |
|---|---|
| **Файл** | `config/initializers/master_key_strength_check.rb` |
| **Що робить** | У `Rails.env.production?` (включно з canopy) після `after_initialize` перевіряє `ENV["PROVISIONING_MASTER_KEY"]`: (1) blank → raise `SecurityError` з посиланням на `docs/03_05 §3.4а`; (2) непустий, але `Security::WeakKeyDetector.detect` повертає reason → raise `SecurityError` з cause. У dev/test guard вимкнений (там зафіксований стабільний non-secret fixture у `spec/rails_helper.rb` — інакше весь suite не завантажиться). |
| **Bypass** | `SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK=1` — для one-off rescue-boot при флеші zaжатого кластера. Логується гучно, не може стати рутиною. |
| **Зв'язок з HKDF tree** | Captured-критично: master-ключ є коренем для **чотирьох** info-strings (post-ARCH.42): `HardwareKeyService.derive_lora_key` (Tree AES-128 LoRa, info `"silken-aes-128-lora-key"`), `HardwareKeyService.derive_device_key` (Gateway AES-256 CoAP, info `"silken-aes-256-device-key"`), `OtaHmacKeyService` (K_ota, info `silken-ota-hmac-v1`), `SilkenNet::SeedDerivation` (Lorenz `K_seed`, info `silken-lorenz-seed`). Компрометація master = каскадна компрометація всіх чотирьох — тому guard працює fail-closed до запуску HTTP-сервера. |

---

## 💰 9. Домен: Фінансові Оракули (Finance Oracles)

### `PriceOracleService`

| | |
|---|---|
| **Файл** | `app/services/price_oracle_service.rb` |
| **Вхід** | — (class method) |
| **Що робить** | Отримує поточну ціну SCC/USDC з Uniswap V3 Quoter (Polygon). Кеш 5 хвилин. Timeout 15 сек. Fallback: $25.50 (Series A base price). Mock в dev/test. |
| **Зовнішні виклики** | Polygon RPC → `Quoter.quoteExactInputSingle` |
| **Вихід** | `current_scc_price → Float` (USD). |

---

## 🌐 10. Домен: Мультичейн — Паралельні Рейки (Multi-chain)

### `Solana::MintingService`

| | |
|---|---|
| **Файл** | `app/services/solana/minting_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | USDC мікро-винагороди на Solana. **[MAINNET READY]** Guard: `verified_by_iotex?` + `oracle_status_fulfilled?` (enum method). **[BLOCKER-1]** `verify_oracle_balance!` — перевіряє баланс SOL оракула через `getBalance` RPC; raises при `< MIN_ORACLE_BALANCE_LAMPORTS` (0.05 SOL = 50M lamports). Розраховує `reward_lamports = 10_000 + (growth_points × 100)`, де `growth_points` — stored value [FW.29-PACK] 0..62 (wire 5-bit × 2 backend upscale). Діапазон: 10_000–16_200 lamports (0.01–0.0162 USDC). 4-крокова транзакція: `getLatestBlockhash` → бінарний SPL Token Transfer Message (compact-u16 + account keys + Ed25519-header) → Ed25519 підпис через `Ed25519Crypto::SigningService` (hex-keypair з `SOLANA_WALLET_KEYPAIR`) → `sendTransaction` (base64). ATA отримувача резолюється динамічно через `getTokenAccountsByOwner` RPC. `SOLANA_WALLET_KEYPAIR` (mandatory), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS` — обов'язкові ENV. **[E.61] Batch-режим:** при ненульовому `solana_batch_threshold_usdc` (SystemParameter) `mint_micro_reward!` лише акумулює винагороду per-wallet у Kredis (виплату робить `Solana::BatchPayoutService`); `batch_payout!` шле один `transferChecked` (idx 12, валідує mint+decimals). Поріг 0 → per-event (backward-compat). Scale-обґрунтування — [`05_01 §8`](05_01_Multichain_Architecture). |
| **Зовнішні виклики** | `Web3::HttpClient.post` → Solana RPC JSON API (`getLatestBlockhash`, `getTokenAccountsByOwner`, `sendTransaction`) |
| **Вихід** | `tx_signature` (String). Створює `BlockchainTransaction` зі статусом `:sent` (очікує `BlockchainConfirmationWorker`). |

### `Solana::BatchPayoutService` [E.61]

| | |
|---|---|
| **Файл** | `app/services/solana/batch_payout_service.rb` |
| **Вхід** | — (cron-driven через `SolanaBatchPayoutWorker`) |
| **Що робить** | Gas Optimizer для Solana мікро-винагород. Обходить акумульовані в Kredis гаманці (`solana_pending_payouts:<wallet_id>`) і виплачує тих, чия сума перетнула `solana_batch_threshold_usdc`, одним `transferChecked` ATA→ATA через `Solana::MintingService#batch_payout!`. Per-wallet `Kredis.lock` + decrement-not-clear (concurrent incrby не губиться); ізоляція збоїв per-wallet; залишок зниклого гаманця скидається. Поріг 0 → no-op (власник виплат — per-event шлях). Scale-обґрунтування — [`05_01 §8`](05_01_Multichain_Architecture). |
| **Зовнішні виклики** | `Solana::MintingService#batch_payout!` → Solana RPC (`transferChecked`) |
| **Вихід** | — (side-effect: `BlockchainTransaction` `:sent` + Kredis decrement) |

### `Celo::CommunityRewardService`

| | |
|---|---|
| **Файл** | `app/services/celo/community_reward_service.rb` |
| **Вхід** | `cluster` (Cluster AR instance), `target_date` (Date) |
| **Що робить** | ReFi incentive: відправляє 5 cUSD організації якщо `stress_index <= 0.2` та немає fraud. ERC-20 `transfer` на Celo. `Kredis.lock` проти race conditions. **[BLOCKER-1]** `verify_oracle_balance!` — перевіряє баланс CELO оракула через `get_balance`; raises при `< MIN_ORACLE_BALANCE_WEI` (0.05 CELO). **[E.49]** RPC fallback cascade: `Web3::RpcConnectionPool.client_for("CELO_RPC_URL", fallback: DEFAULT_RPC_URL, fallback_env_keys: RPC_FALLBACK_ENV_KEYS)` де `RPC_FALLBACK_ENV_KEYS = %w[CELO_RPC_URL_FALLBACK_1 CELO_RPC_URL_FALLBACK_2]`. При наявності щонайменше двох заповнених URL'ів повертається `Web3::ResilientClient` з circuit breaker (3 збої / 60с cooldown) — автоматичний failover при HTTP 429 / `Net::ReadTimeout` / `Errno::ECONNREFUSED`. Якщо fallback ENV порожні — поведінка без змін (одиночний `Eth::Client`). |
| **Зовнішні виклики** | Celo RPC (`CELO_RPC_URL` + опц. fallback ENVs), `Web3::RpcConnectionPool`, `Web3::WeiConverter` |
| **Вихід** | `tx_hash` (String) або `nil`. Створює `BlockchainTransaction`. |

### `KlimaDao::RetirementService`

| | |
|---|---|
| **Файл** | `app/services/klima_dao/retirement_service.rb` |
| **Вхід** | `wallet` (Wallet AR instance), `amount_to_retire` (Numeric/String) |
| **Що робить** | ESG carbon retirement через KlimaDAO на Polygon. Двокроковий: `approve(klima_address, amount_wei)` → `retire(amount_wei)`. Атомарна DB-транзакція: `balance -= amount`, `esg_retired_balance += amount`. Raises `InsufficientBalanceError`, `InvalidTokenTypeError`. |
| **Зовнішні виклики** | Polygon RPC (2 транзакції: approve + retire) |
| **Вихід** | `nil`. Side effects: оновлює `wallet.balance`, `wallet.esg_retired_balance`. Створює `BlockchainTransaction`. |

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
| **Що робить** | **[NEW]** Централізований моніторинг балансів Oracle-гаманців на всіх 4 мережах: Polygon (MATIC, min 0.05), Solana (SOL, min 0.05 = 50M lamports), Celo (CELO, min 0.05), Ethereum (ETH, min 0.01 — weekly anchoring). Для EVM-мереж: `Eth::Key` → `client.get_balance`. Для Solana: `Web3::HttpClient.post` → `getBalance` RPC. `RPC_TIMEOUT = 10с` на кожну мережу. Результат: масив Hash з `{ network, currency, balance_raw, balance_human, ratio, status (:healthy/:critical/:error) }`. |
| **Зовнішні виклики** | `Web3::RpcConnectionPool.client_for` (Polygon, Celo, Ethereum), `Web3::HttpClient.post` (Solana RPC) |
| **Prometheus** | `ORACLE_BALANCE` (gauge per network), `ORACLE_BALANCE_RATIO` (gauge, < 1.0 = critical), `TREASURY_CHECK_ERRORS_TOTAL` (counter per network/error_type) |
| **Side Effects** | `EwsAlert.create(alert_type: :system_fault, severity: :critical)` при balance < threshold |
| **Вихід** | `Array<Hash>` — звіт по 4 мережах |

### `Treasury::MintBatchCollectorService`

| | |
|---|---|
| **Файл** | `app/services/treasury/mint_batch_collector_service.rb` |
| **Вхід** | — (no args) |
| **Що робить** | **[NEW]** Sidekiq-level агрегація pending `BlockchainTransaction` записів для оптимізації газу. Збирає `status: :pending, blockchain_network: "evm"`, групує за `token_type` (SCC/SFC), розділяє на urgent (старше `MAX_PENDING_AGE_MINUTES=30хв` — відправляє негайно) та standard (чекає `MIN_BATCH_SIZE=5`). Делегує `BlockchainMintingService.call_batch(ids)` пакетами по `OPTIMAL_BATCH_SIZE=100` (max `MAX_BATCH_SIZE=200`). Gas savings: `batchMint(100) ≈ 30-40%` дешевше ніж `100 × mint()`. Працює паралельно з `MintCarbonCoinWorker` (oracle-driven immediate). `MAX_TRANSACTIONS_PER_RUN = 1000`. |
| **Зовнішні виклики** | `BlockchainMintingService.call_batch` |
| **Вихід** | `nil`. Side effect: транзакції відправлені пакетами. |

### `Ethereum::StateAnchorService`

| | |
|---|---|
| **Файл** | `app/services/ethereum/state_anchor_service.rb` |
| **Вхід** | — (no args) |
| **Що робить** | Тижневий SHA-256 state root → Ethereum L1 з повним аудит-трейлом. **[BLOCKER-2]** Перед TX створює `EthereumAnchor` запис (status: `pending`) для crash recovery. **[BLOCKER-3]** Gas management: `DEFAULT_GAS_LIMIT=100_000`, `DEFAULT_MAX_FEE_GWEI=100`, `DEFAULT_PRIORITY_FEE_GWEI=2` — всі перекриваються ENV. **[BLOCKER-4]** Inline guard: перевіряє ETH-баланс wallet (`DEFAULT_MIN_ANCHOR_BALANCE_ETH = 0.01 ETH`, governance-aware через `SystemParameter(:oracle_min_balance_eth)`) перед TX; при недостатньому балансі — `EthereumAnchor.status = failed` + raise. **[BLOCKER-6]** `generate_state_root` обгорнуто в `transaction(isolation: :repeatable_read)` (SNAPSHOT ISOLATION) і повертає `{ state_root, total_scc, total_sfc, active_tree_count, chain_hash, anchored_at }` — усі шість компонентів зберігаються в `EthereumAnchor` для незалежної верифікації через `EthereumAnchor#verify_state_root`. **[E.53/E.54]** Formula: `SHA256("#{total_scc}\|#{total_sfc}\|#{active_tree_count}\|#{chain_hash}\|#{anchored_at.iso8601}")`. `total_sfc` (sum of confirmed `forest_coin` `BlockchainTransaction.amount`) додано бо governance-токен впливає на quorum/voting power у DAO. `active_tree_count` (`Tree.active.count`) додано як метрика покриття екосистеми — різка зміна без audit events є сигналом маніпуляції. **[DOUBLE-ANCHOR GUARD]** Перед створенням нового state_root перевіряє `EthereumAnchor.in_flight` (status `:pending` або `:sent` за останній тиждень): якщо знайдено `:sent` — повертає його без re-send (TX може бути в мемпулі); якщо `:pending` — продовжує з тим самим state_root для crash-recovery. На `Net::ReadTimeout`/`Net::OpenTimeout`/`IOError` зберігає status `:pending` (TX may be in-flight) — наступний ретрай резюмує цей самий anchor. Після успішної TX — `anchor.update!(status: :sent, tx_hash:)`. |
| **Зовнішні виклики** | Ethereum Mainnet RPC (`ALCHEMY_ETHEREUM_RPC_URL`), `StateRootAnchor` contract (`storeStateRoot(bytes32)`) |
| **Вихід** | `EthereumAnchor` (AR instance). Raises при недостатньому балансі, timeout або connection error. |

### `Filecoin::ArchiveService`

| | |
|---|---|
| **Файл** | `app/services/filecoin/archive_service.rb` |
| **Вхід** | `audit_log` (AuditLog AR instance) |
| **Що робить** | Архівує AuditLog до IPFS/Filecoin через Pinata API. Payload: chain_hash, metadata, добове зведення `AiInsight` кластерів організації. Ідемпотентний: `return if ipfs_cid.present?`. |
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
| **Що робить** | GraphQL запити до The Graph subgraph (Polygon). `fetch_total_carbon_minted` — сума `carbonMintEvents.amount`. `fetch_protocol_financials` — `totalMinted`, `totalBurned`, `totalPremiums`. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `the_graph_api_url` |
| **Вихід** | `fetch_total_carbon_minted → Integer`. `fetch_protocol_financials → { total_minted:, total_burned:, total_premiums: }`. |

### `Dclimate::VerificationService`

| | |
|---|---|
| **Файл** | `app/services/dclimate/verification_service.rb` |
| **Вхід** | `alert` (EwsAlert AR instance) |
| **Що робить** | **[MAINNET READY]** Супутникова верифікація EWS-алертів через dClimate FIRMS API (NASA Near Real-Time Global Active Fire, VIIRS 375 м). HTTP GET до `DCLIMATE_BASE_URL/v4/geo/grid-history/{FIRMS_DATASET}` з координатами дерева та часовим вікном ±1 день. Інтерпретація: FRP ≥ 10 МВт + confidence ≥ 50% → `:fire_confirmed`; ясне небо без аномалій → `:clear_sky_no_fire`; cloud_cover > 70% або відсутні дані → `:obscured_by_clouds`. Підтримує обидва формати відповіді: `{"data": [...]}` (JSON array) та GeoJSON `{"features": [...]}`. VIIRS string confidence (`high/nominal/low`) конвертується у числові значення. Мережеві збої (`Web3::HttpClient::RequestError`) → безпечний fallback до `:obscured_by_clouds`. Авторизація Bearer через `Rails.credentials.dclimate.api_key`. `generate_dclimate_ref` включає метадані супутника для аудит-трейлу. **3 результати — severity-aware:** `fire_confirmed` → InsurancePayoutWorker; `clear_sky_no_fire` → BurnCarbonTokensWorker (Slashing за фрод); `obscured_by_clouds` — **гілкується за `EwsAlert#severity`:** для `:critical` (`fire_detected` / `severe_drought`) → `ForestBountyService.create_bounty!(ews_alert, type: :drone_verification)` як **Forester Guild Fallback Oracle** (E.20/E.34 — див. §11 `DclimateVerificationWorker` + ["Planned: Forester Guild"](#-planned-forester-guild--proof-of-physical-work-міністерство-праці)) `[PLANNED — blocked by ForestBountyService, Post-TRL 6/7]`; для `:low`/`:medium` → raise `OrbitalLagError` (Sidekiq retry, 15 спроб ≈ 48+ год, `sidekiq_retries_exhausted` → `satellite_status: :inconclusive` для DAO audit). **⚠️ Implementation gap:** поточний `handle_obscured_by_clouds` (TRL 8 baseline) raise'ить `OrbitalLagError` для **всіх** severity-рівнів; severity-розгалуження приземлиться разом з імплементацією `ForestBountyService`. |
| **Зовнішні виклики** | `Web3::HttpClient.get` → dClimate FIRMS API (`DCLIMATE_BASE_URL`). `InsurancePayoutWorker.perform_async` або `BurnCarbonTokensWorker.perform_async`. |
| **Вихід** | `nil`. Side effects: оновлює `alert.satellite_status` та `alert.dclimate_ref`, тригерує воркери. |

### `Toucan::BridgeService`

| | |
|---|---|
| **Файл** | `app/services/toucan/bridge_service.rb` |
| **Вхід** | `blockchain_transaction_id` (Integer), `created_at_iso` (String, ISO 8601, опціонально) |
| **Що робить** | SCC → TCO2 bridge через Toucan Protocol на Polygon. `deposit(scc_address, amount_wei)` на ToucanCarbonBridge контракті. Використовує `BlockchainTransaction.find_with_partition_pruning` для partition-aware lookup. |
| **Зовнішні виклики** | Polygon RPC → `ToucanCarbonBridge.deposit` |
| **Вихід** | `tx_hash` (String). |

---

## 📖 10b. Codex (Lore Layer) Сервіси

Сервіси Lore-шару Gaia 2.0. Повна специфікація: **[`04_05`](04_05_Codex_Lore_Module)**.

### `Codex::NodeImportService`

| | |
|---|---|
| **Файл** | `app/services/codex/node_import_service.rb` |
| **Вхід** | `root:` (Pathname, default `Rails.root.join("db/seeds/codex")`), `logger:` (default `Rails.logger`) |
| **Що робить** | Idempotent UPSERT seed-корпусу: 4 `Codex::Realm` + 79 `Codex::Node` з YAML-файлів. Ключ — `slug`. Зберігає DAO-промотовані `seed_origin`. Помилки на одному файлі не зривають весь імпорт (per-file `transaction` + isolated rescue). |
| **Зовнішні виклики** | — (file I/O + DB) |
| **Вихід** | `Result` (Struct) з полями `realms_upserted`, `nodes_upserted`, `errors` + `success?` |
| **Інвокери** | `bin/rails codex:seed` (rake), `db/seeds.rb` (dev only) |

### `Codex::MarkdownRenderer`

| | |
|---|---|
| **Файл** | `app/services/codex/markdown_renderer.rb` |
| **Вхід** | `markdown` (String, nullable) |
| **Що робить** | Мінімальний markdown→HTML рендер з білим списком тегів (`p`, `h2..h4`, `ul/ol/li`, `strong`, `em`, `blockquote`, `code`, `pre`, `a`, `br`) і атрибутів (`href`, `rel`, `target`). `<script>` та інші теги стрипаються `Rails::HTML5::SafeListSanitizer`. URL-схеми `javascript:` / `data:` переписуються на `#` ще до санітайзера. Завжди повертає `html_safe`. |
| **Зовнішні виклики** | — (in-memory) |
| **Вихід** | `ActiveSupport::SafeBuffer` (html_safe) |
| **Інвокери** | `Codex::Show` Phlex компонент (для `context_md`/`cyber_meaning_md`/`lore_md`), `Codex::Comments::Item` (для `body_md`), `Codex::CommentBlueprint#body_html`. |

### `Codex::AttunementBroadcastWorker` (Phase 2)

| | |
|---|---|
| **Файл** | `app/workers/codex/attunement_broadcast_worker.rb` |
| **Черга** | `default` (#5) — ADR-CDX-4 (UI broadcasts ніколи не на hot path) |
| **Retry** | 3 |
| **Вхід** | `node_id` (Integer), `user_id` (Integer) |
| **Що робить** | Re-load Node (post-commit `attunement_count`) → `ActionCable.server.broadcast` на public `codex_node_<id>_attunements` (з лічильником) + private `codex_node_<id>_attunements_user_<uid>` (з `attuned: bool`). |
| **Інвокери** | `Codex::AttunementsController#create / #destroy` |
| **Тригер** | toggle attunement → live counter via Solid Cable |

### Phase 2 controllers (без окремого Service-шару — логіка тонка)

- `Api::V1::Codex::AttunementsController` — `find_or_initialize_by` + counter cache + worker enqueue. Idempotent toggle: re-POST оновлює `intensity`/`quote`, ніколи не дублює.
- `Api::V1::Codex::CommentsController` — `Idempotency-Key` обов'язковий для JSON writes (24h TTL у `Rails.cache`); inline `ActionCable.server.broadcast` на `codex_node_<id>_comments` з `Codex::CommentBlueprint`-серіалізацією.

### `Codex::FractionChangeService` (Phase 3)

| | |
|---|---|
| **Файл** | `app/services/codex/fraction_change_service.rb` |
| **Вхід** | `user:` (User), `node:` (Codex::Node), `now:` (Time, injectable for specs) |
| **Що робить** | Єдина точка мутації фракції. Two outcomes (success): **initial pick** — створює рядок з `chosen_at` = `last_changed_at` = now; **re-pick** — оновлює `codex_node_id` + `archetype_key` (денормалізація) + `last_changed_at`, `chosen_at` залишається immutable. Перед мутацією перевіряє cooldown (7 днів). Денормалізує `archetype_key` з Node і `house_color_token` з realm.accent_token. Enqueue `FractionAuditWorker` тільки після успішного save. |
| **Failure** (handled) | Cooldown active → `Result(success: false, errors: ["cooldown_active"], cooldown_until: ...)`. Lifecycle blocked → `Result(success: false, errors: ["node is not pickable"])`. Всі handled, не raise. |
| **Зовнішні виклики** | `Codex::FractionAuditWorker.perform_async` (transient enqueue failure не rollback'ить мутацію — audit є async by design) |
| **Вихід** | `Result` Struct (`success?`, `fraction`, `cooldown_until`, `previous_node_id`, `errors`) |
| **Інвокери** | `Api::V1::Codex::FractionsController#create` |

### `Codex::FractionAuditWorker` (Phase 3)

| | |
|---|---|
| **Файл** | `app/workers/codex/fraction_audit_worker.rb` |
| **Черга** | `default` (#5) — ADR-CDX-4 |
| **Retry** | 3 |
| **Вхід** | `user_id` (Integer), `fraction_id` (Integer), `previous_node_id` (Integer or nil) |
| **Що робить** | Записує `AuditLog(action: "codex.fraction.chosen", auditable: fraction, metadata: {codex_node_id, archetype_key, previous_node_id, changed_at})` через звичайний `create!` (immutable chain hash compute через before_create callback). |
| **No-op коли** | user не має `organization_id` (системні боти типу `oracle.executioner@system`); user/fraction не знайдено в DB. |
| **Інвокери** | `Codex::FractionChangeService` |

### `Codex::PairSelectorService` (Phase 4)

| | |
|---|---|
| **Файл** | `app/services/codex/pair_selector_service.rb` |
| **Вхід** | `user:`, `realm:` (default first ordered), `now:` (injectable clock) |
| **Що робить** | Pickable nodes у realm (lifecycle ∉ destroyed/extinct) → anchor через `ORDER BY RANDOM() LIMIT 8` + min `match_count` → opponent з Elo bucket ±200; fallback на будь-який інший вузол. Підписує `pair_seed = HMAC-SHA256(secret_key_base, "user_id|realm_id|ts|left_id|right_id")[0..64]`. Зберігає у Redis `codex:pair_seed:<seed>` TTL 5 хв з payload `"user_id|realm_id|left_id|right_id|ts"`. |
| **Failure** | `not enough nodes`, `no realm available`, unsaved user — handled через `Result(success: false, error: ...)`. |
| **Інвокери** | `MatchesController#new`, `MatchesController#create` (для next-pair after vote) |

### `Codex::VoteRecorderService` (Phase 4)

| | |
|---|---|
| **Файл** | `app/services/codex/vote_recorder_service.rb` |
| **Вхід** | `user:`, `pair_seed:`, `winner_slug:` (or nil for skip), `skip:` (Boolean) |
| **Що робить** | Атомарно DEL'ить Redis seed (replay-proof), створює `Codex::Match` + обчислює Elo deltas через `EloMath` (K=32, decay при `match_count > 30` на обох sides), enqueue `EloRecomputeWorker`. Skip → 0/0 deltas, але рядок все одно зберігається (для PairSelector avoidance heuristics). |
| **Failure** | `seed_invalid_or_consumed`, `seed_user_mismatch`, `winner_not_in_pair`, `nodes_missing`, validation — handled via Result struct. |
| **Інвокери** | `MatchesController#create` |

### `Codex::EloMath` (Phase 4 — pure module)

| | |
|---|---|
| **Файл** | `app/services/codex/elo_math.rb` |
| **API** | `EloMath.deltas(left_elo:, right_elo:, winner:, match_count_left:, match_count_right:)` → `[delta_left, delta_right]`. `EloMath.expected(left, right)` → win probability. |
| **Constants** | `K_BASE = 32`, `K_DECAY = 16`, `DECAY_THRESHOLD = 30`. K halves once both nodes pass the threshold (settled archetypes don't yo-yo). |

### `Codex::EloRecomputeWorker` (Phase 4)

| | |
|---|---|
| **Файл** | `app/workers/codex/elo_recompute_worker.rb` |
| **Черга** | `low` (#9) — ADR-CDX-4 (Battle never blocks Proof-of-Growth hot-path) |
| **Retry** | 3 |
| **Вхід** | `left_node_id`, `right_node_id`, `delta_left`, `delta_right` |
| **Що робить** | Pre-computed deltas передаються як args (не recompute у воркері — what the Arena UI showed at vote-time is what gets persisted). Атомарно `UPDATE codex_nodes SET attunement_elo = attunement_elo + ?, match_count = match_count + 1` для обох вузлів у транзакції. No SELECT-then-UPDATE race. |
| **Інвокери** | `Codex::VoteRecorderService` |

### `Codex::PresenceTracker` (Phase 5)

| | |
|---|---|
| **Файл** | `app/services/codex/presence_tracker.rb` |
| **API** | `.touch(user_id:, tree_id:)` / `.leave(user_id:, tree_id:)` / `.observers_for_tree(tree_id) → Array<Integer>` / `.observed?(tree_id) → Boolean` |
| **Storage** | Redis Set `codex:presence:tree:<tree_id>` of user_ids, TTL 10 min refreshed on every `touch`. |
| **Що робить** | Records "user U is currently observing tree T" so the Discovery hook in `TelemetryUnpackerService` can fan out probes only when someone is watching. Cheap `SMEMBERS`/`EXISTS` calls; rescues all Redis exceptions → `[]` / `false`. **Never blocks `uplink`.** |
| **Caller** | A future Stimulus heartbeat controller on `Tree::Show` (every 60 s while page is visible). |

### `Codex::DiscoveryEngine` (Phase 5 — pure rule evaluator)

| | |
|---|---|
| **Файл** | `app/services/codex/discovery_engine.rb` |
| **API** | `Codex::DiscoveryEngine.evaluate(user:, trigger_type:, payload: {})` → `Array<Codex::Node>` (nodes the user just unlocked) |
| **Reads** | `Codex::DiscoveryRule.cached_active_by_condition` (1-hour TTL, busted on rule mutation). |
| **Adapters** | Hash `ADAPTERS` keyed by `condition_type` symbol. **Phase 6 ships all 7**: `tree_observation_minutes` (Wallet→Tree→TelemetryLog count proxy, org-scoped), `match_count` (with optional `realm_slug` filter), `attunement_streak_days` (consecutive trailing days), `oracle_dispatched` (TelemetryLog `oracle_status IN (dispatched, fulfilled)`, org-scoped), `acoustic_class_count` (TelemetryLog `acoustic_events ≥ params['min_events']` proxy for high-class CMSIS-NN activity, org-scoped), `cluster_visited` (TelemetryLog from user's org's trees inside cluster matching `params['cluster_name']`), `firmware_version_seen` (TelemetryLog whose `BioContractFirmware.version` matches `params['version']`). All telemetry-joined adapters short-circuit when `user.organization_id.blank?`. |
| **Skips** | rules whose Node is already in this user's `Codex::Discovery`; unknown `condition_type` → debug log + skip; unsaved user → `[]`. |

### `Codex::DiscoveryProbeWorker` (Phase 5)

| | |
|---|---|
| **Файл** | `app/workers/codex/discovery_probe_worker.rb` |
| **Черга** | `default` (#5) — ADR-CDX-4 (Discovery is cosmetic; never blocks Proof-of-Growth) |
| **Retry** | 3 |
| **Вхід** | `user_id`, `trigger_type` (string), `payload` (hash with optional `trigger_ref_type` / `trigger_ref_id` / `tree_id`) |
| **Що робить** | Calls `Codex::DiscoveryEngine.evaluate`; for each unlocked Node, atomically `find_or_create_by(user_id:, codex_node_id:)`; broadcasts on `codex:discoveries:user:<user_id>` only when `previously_new_record?` → race-safe single broadcast across concurrent workers. Rescues `RecordNotUnique` / `RecordInvalid` from concurrent inserts. |
| **Інвокери** | `TelemetryUnpackerService.commit_telemetry` (presence-gated fan-out), `Codex::EloRecomputeWorker` (match_milestone — Phase 6 wire-up), `Codex::FractionChangeService` (fraction_choice — Phase 6 wire-up), `Codex::AttunementsController` (attunement_streak — Phase 6 wire-up). |

### `Codex::DiscoveryRuleImportService` (Phase 5)

| | |
|---|---|
| **Файл** | `app/services/codex/discovery_rule_import_service.rb` |
| **API** | `Codex::DiscoveryRuleImportService.call(path: SEED_PATH)` → `Result(created:, updated:, skipped:)` |
| **Що робить** | Idempotent UPSERT loader for `db/seeds/codex/discovery_rules.yml`. UPSERT key = `name`. Resolves `node_slug` to `Codex::Node` (skip + warn if missing — supports any seed-run order). Resolves `created_by_user_email` to `User`, falls back to `User.oracle_executioner` for system-owned seeds. |
| **Caller** | `db/seeds.rb` (after `Codex::NodeImportService`). |

### TelemetryUnpackerService Discovery hook (Phase 5)

The finalizer `commit_telemetry` ends with a fire-and-forget `enqueue_codex_discovery_probes(tree, log)` that:

1. `defined?(::Codex::PresenceTracker)` guard (graceful in Phase-1-only deploys).
2. `observers = Codex::PresenceTracker.observers_for_tree(tree.id)` — cheap Redis `SMEMBERS`.
3. `return if observers.empty?` — most packets fire **zero** Sidekiq jobs.
4. `observers.each { |uid| Codex::DiscoveryProbeWorker.perform_async(uid, "telemetry_observation", payload) }` with `payload` containing `tree_id`, `trigger_ref_type: "TelemetryLog"`, `trigger_ref_id: log.id_value`.
5. `rescue StandardError` → log warn → uplink finalisation continues. Discovery is cosmetic; Redis/Sidekiq hiccup must never abort the uplink batch.

### Phase 3 controller (FractionsController)

`Api::V1::Codex::FractionsController` — 3 ендпоінти, всі делегують до сервісу:
- `#create` — `Codex::FractionChangeService.call(user:, node:)`. Success → 201 + Blueprint. Cooldown → 429 + `cooldown_until`. Validation → 422.
- `#me` — рендерить `Codex::Fractions::Card` (HTML) або 204 (JSON, коли fraction nil).
- `#picker` — рендерить `Codex::Fractions::Picker` Turbo Frame для `?realm=<slug>`.

### `Api::V1::Codex::CitationsController` (Phase 6)

| | |
|---|---|
| **Файл** | `app/controllers/api/v1/codex/citations_controller.rb` |
| **POST** | `forester+` (Pundit `Codex::CitationPolicy#create?`). Required body: `codex_node_slug`, `citable_type`, `citable_id`. Optional: `note` (≤140). `Idempotency-Key` обов'язкова для JSON; replay returns the cached payload. DB-UNIQUE on `(codex_node_id, citable_type, citable_id, created_by_user_id)` is the second line of defence — duplicate → 422. |
| **DELETE** | own ≤ 24 h grace (`record.created_by_user_id == user.id && created_at >= 24.hours.ago`), admin+ bypass. |
| **Type whitelist** | `CITABLE_CLASS_MAP` lambda registry inside the controller — Brakeman-clean (no `safe_constantize` on user input). Bogus `citable_type` → 400. Allowed: `Tree`, `Cluster`, `AiInsight`, `EwsAlert`, `OracleVision` (falls back to `AiInsight` if `OracleVision` const missing), `NaasContract`. |
| **Broadcast** | `codex_citations:<Type>:<id>` envelope `{ op: "append" \| "remove", data \| id }`. Failure rescued — never rolls back the write. |

### `Api::V1::Codex::Admin::NodesController` (Phase 6)

| | |
|---|---|
| **Файл** | `app/controllers/api/v1/codex/admin/nodes_controller.rb` |
| **Policy** | `Codex::Admin::NodePolicy` — asymmetric: `index?`/`show?`/`update?` admin+, `create?`/`destroy?` super_admin only. |
| **Use-case** | DAO node curation: publish toggle (set `published_at`), geo correction (`latitude`/`longitude`/`geo_region`), copy fix (`title_*`/`subtitle_*`/`*_md`). New DAO entries get `seed_origin: :dao_proposal` server-side (immutable on update). |
| **External refs** | JSONB `external_refs` is passed through unmodified — `Codex::Node#external_refs_must_be_array_of_links` is the SSOT validator. |
| **Rails 8 enums** | `lifecycle_status` invalid value raises `ArgumentError`; controller rescues into 422 with the underlying message. |

### Phase 6 cross-domain Discovery probes

Three lore-aware operations now call `Codex::DiscoveryProbeWorker.perform_async` after the primary write commits. **All three are fail-open** — a Sidekiq enqueue hiccup never rolls back the user-facing operation.

| Caller | Trigger | Payload |
|---|---|---|
| `Codex::EloRecomputeWorker#perform` | `match_milestone` | `match_id`, `trigger_ref_type: "Codex::Match"`, `trigger_ref_id`. Resolves the most-recent Match referencing either node (delta-only `perform` doesn't carry `user_id`). |
| `Codex::FractionChangeService#enqueue_discovery_probe` | `fraction_choice` | `fraction_id`, `codex_node_id`, `previous_node_id`, `trigger_ref_type: "Codex::Fraction"`, `trigger_ref_id`. Initial pick → `previous_node_id: nil`. |
| `Api::V1::Codex::AttunementsController#enqueue_discovery_probe` | `attunement_streak` | `codex_node_id`, `trigger_ref_type: "Codex::Attunement"`, `trigger_ref_id`. Fired alongside `AttunementBroadcastWorker`. |

### `Codex::Citation` model helpers (Phase 6)

| Helper | Use |
|---|---|
| `Codex::Citation.for_target(target)` | per-page render — `where(citable_type: target.class.base_class.name, citable_id: target.id)`. |
| `Codex::Citation.bulk_for(targets)` | N+1-free table render — returns `Hash[[type, id]] = [citations…]` keyed for O(1) lookup; eager-loads `:node` once per type batch. Used by `Alerts::Index` etc. |
| `Codex::Citation#within_edit_grace?` | mirrors Comment 24 h grace; returns `false` when `created_at` is nil (unsaved). |

---

## ⚙️ 11. Реєстр Воркерів (Workers Registry)

### Пріоритети черг (9 рівнів, строге дотримання)

| Черга | Порядок (Strict) | Призначення |
|-------|-----------------|-------------|
| `uplink` | 1 (найвищий) | Вхідна телеметрія |
| `alerts` | 2 | EWS тривоги, супутникова верифікація |
| `critical` | 3 | Slashing, страхові виплати, реанімація екосистеми |
| `downlink` | 4 | OTA прошивки, команди актуаторів |
| `default` | 5 | Агрегація, перевірка контрактів, токеноміка |
| `web3_critical` | 6 | Blockchain confirmation, мінтинг, IoTeX, Chainlink |
| `web3` | 7 | peaq DID, Celo, Solana, Puro.earth |
| `web3_low` | 8 | Ethereum L1, KlimaDAO, Hadron, Governance Parameter Sync |
| `low` | 9 (найнижчий) | Аудит, Filecoin, Streamr |

> **Примітка:** Sidekiq `:strict: true` дренує черги послідовно згори-донизу. Числа — порядок дренування, не ваги.

> ⚠️ **DOC.8 — Cleanup constraint (TelemetryLog):** Будь-який cleanup-воркер на `telemetry_logs` **зобов'язаний** виключати `oracle_status = 'dispatched'`. Ці записи знаходяться в open Chainlink-callback flight; їх видалення зламає `OracleCallbacksController` (RecordNotFound + 5 retry без мінтингу). Канонічне виконання — `InsightGeneratorService.cleanup_old_logs!` (тригериться з `InsightBatchCallbacks` після успішного денного циклу). Не реалізуйте паралельні cleanup-job'и — викликайте сервіс. Cross-ref: [`04_01` — TelemetryLog model warning](04_01_Data_Models_and_Entities#telemetrylog--сирий-пакет-телеметрії).

> ⚠️ **DOC-R.10 — Sidekiq Pro shims active (Phase 7 deferred upgrade):** Кодова база викликає `Sidekiq::Batch`, `Sidekiq::Limiter`, `expires_in:`, але ліцензований гем `sidekiq-pro` поки що **не в Gemfile**. `config/initializers/sidekiq_pro.rb` надає no-op shim-и щоб тести й dev-середовище не падали — у production це означає що `on(:success)` колбеки **не спрацьовують**, rate-limiter `web3_rpc 50/sec` **не діє**, а `expires_in: 5.minutes` на uplink-задачах **не TTL-ить** stale jobs. Перед billion-tree запуском треба:
> 1. Додати `gem "sidekiq-pro", "~> 8.1"` (потребує license token у `BUNDLE_GEMS__CONTRIBSYS__COM`).
> 2. Видалити shim і замість нього у `sidekiq_pro.rb` зробити `raise "sidekiq-pro required" unless defined?(Sidekiq::Pro)`.
> 3. Розщепити Sidekiq на 4 процеси з queue-pinning (uplink окремо, web3_* окремо, critical/alerts/downlink окремо, default/low окремо) — single-process × 15 threads не витягне peak ~ N_trees / 3600 jobs/sec.
> 4. Увімкнути `super_fetch` (zero job-loss на SIGKILL/OOM) для `uplink`, `web3_critical`, `critical`.
> 5. Увімкнути `reliable_push` у клієнті (захист enqueue-у від Redis failover).
> 6. Збільшити Redis pool: `pool_size = concurrency + 5` (зараз буфер = 0).

> ✅ **DOC-R.11 — Cron / partition guardian:** `PartitionMaintenanceWorker` запускається `30 0 * * *` UTC (cron у `config/sidekiq.yml`), створює партиції на поточний + наступний місяць для **4 RANGE-таблиць**: `telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`, `codex_matches` (Phase 4 — Codex Battle Arena). Phase 7 додав `Sentry.capture_exception` у `rescue` блок щоб тиха помилка партиціювання не призвела до `no partition of relation` PostgreSQL крешу 1-го числа місяця. Якщо додаєте нову RANGE-таблицю — внесіть її в `PartitionMaintenanceWorker::PARTITIONED_TABLES` І оновіть `spec/workers/partition_maintenance_worker_spec.rb` (очікуване число OK-ліній = `tables × 2 months`).

---

### 📡 Uplink — Вхідна Телеметрія

#### `UnpackTelemetryWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `uplink` |
| **Retry** | 3, expires_in: 5 хвилин (Sidekiq Pro) |
| **Тригер** | CoAP daemon (`lib/daemons/`) при отриманні UDP-пакета |
| **Вхід** | `encoded_payload` (Base64), `sender_ip` (String), `gateway_uid` (String, опціонально) |
| **Сервіси** | `TelemetryUnpackerService.call` (+ `gateway_attested:` kwarg) |
| **Side Effects** | **[L1 QATT]** Детект підписаного конверта за residue довжини → Ed25519-verify проти `HardwareKey.ed25519_public_key_hex` **ДО** decrypt (wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)): invalid → drop + `attest_bad_signature`; replay (SHA256-sig nonce, M2M-патерн + Solid-Cache fallback `QATT_NONCE_FALLBACK_TOTAL`) → drop; signed-без-pubkey → L0 + `attest_no_pubkey`; валідний → strip конверта + `gateways.last_attested_at`. Далі AES-256-CBC дешифрування (Dual-Key), ActionCable raw hex broadcast, Turbo Stream broadcast `telemetry_feed` |

#### `GatewayTelemetryWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `uplink` |
| **Retry** | 2, expires_in: 5 хвилин |
| **Тригер** | `TelemetryUnpackerService` при DID=0x00000000 (Queen sentinel) |
| **Вхід** | `queen_uid` (String), `stats` (Hash: voltage_mv, temperature_c, cellular_signal_csq) |
| **Сервіси** | Немає — пряма робота з `Gateway`, `GatewayTelemetryLog` |
| **Side Effects** | Створює `GatewayTelemetryLog`. Перевіряє `critical_fault?` → `EwsAlert.create!` → (via `after_create_commit` Transactional Outbox) → `AlertNotificationWorker.perform_async`. |

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
| **Side Effects** | ActionCable broadcast до dashboard. Знаходить stakeholders організації через `.find_each(batch_size: 500)`, збирає args у масив → `Sidekiq::Client.push_bulk("class" => SingleNotificationWorker, "args" => bulk_args)` — один Redis round-trip замість N окремих `LPUSH`. |

> **⚠️ Rate Limiting (Post-TRL 8):** При кластерах з 5000+ стейкхолдерів `push_bulk` створить 5000 `SingleNotificationWorker` джобів, кожен з яких робить HTTP-запит до Twilio/FCM. Це гарантовано призведе до HTTP 429 (Too Many Requests) від провайдерів. **Рішення:** Замість тисяч окремих воркерів, використовувати нативні Bulk API:
> - **FCM:** Multicast-повідомлення — до 500 device tokens за 1 HTTP-запит (`send_multicast`)
> - **Twilio:** Notify Service — до 10,000 номерів за 1 API виклик (`create_notification`)
> - **Батчинг:** `AlertNotificationWorker` має групувати recipients по каналу (`:sms` / `:push`) та відправляти батчами по 500 (FCM) або 10,000 (Twilio), а не делегувати кожне повідомлення окремому воркеру.

#### `SingleNotificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 5, expires_in: 10 хвилин |
| **Тригер** | `AlertNotificationWorker` |
| **Вхід** | `user_id`, `ews_alert_id`, `channel` (`:sms` або `:push`) |
| **Сервіси** | — (Twilio/FCM стаби) |

#### `DclimateVerificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 15 (≈ 48+ годин орбітального вікна) |
| **Тригер** | Sidekiq cron або ручний запуск при fire/drought EwsAlert |
| **Вхід** | `alert_id` (Integer) |
| **Сервіси** | `Dclimate::VerificationService.new(alert).perform` |
| **Side Effects** | При вичерпанні ретраїв: `alert.satellite_status = :inconclusive` (DAO audit). |

> **⚠️ Критична проблема орбітального вікна (Post-TRL 8):** При `severity: :critical` (наприклад, `fire_detected`) чекати 48 годин на прояснення хмар неприпустимо. Якщо dClimate повертає `:obscured_by_clouds` для критичних тривог, воркер не повинен просто йти в retry-sleep.
>
> **Рішення — Forester Guild як Fallback Oracle (E.20):** При `severity: :critical` + `:obscured_by_clouds` → миттєво створити `ForestBountyService.create_bounty!(ews_alert, type: :drone_verification)`. Фізичний виліт рейнджера з дроном (Proof-of-Physical-Work) стає **Резервним Оракулом**, який закриває тривогу швидше за супутник. Пріоритет: Post-TRL 6 (E.20 в трекері).

---

#### `ClusterEntropyAnalyzerWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 3 |
| **Тригер** | Періодичний (рекомендовано: щогодини через Sidekiq cron) |
| **Вхід** | `cluster_id` (Integer) |
| **Сервіси** | `SilkenNet::EntropyCalculatorService.call(z_values)` |
| **Side Effects** | Оновлює `cluster.entropy_score` (денормалізація). При entropy < `CRITICAL_ENTROPY_THRESHOLD` (0.65) створює `EwsAlert` (type: `entropy_anomaly`, severity: `medium`). Redis silence filter: 1 год per cluster. Prometheus gauge: `silkennet_cluster_entropy_score`. Інвалідація кешу `oracle_expected_yield_24h`. |
| **Примітка** | Аналізує Z-значення за останні 24 години (partition-aware query). Мінімум 30 точок даних для статистичної значущості. Alignment: ЧДТУ task #12 (08_02 §2). Чому Z-value, а не HRNG seed: `chaos_seed` НЕ передається у 21-байтному пакеті (03_01, Phase 2). |

---

### 🚨 Critical — Фінансово Критичні Операції

#### `BurnCarbonTokensWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `critical` |
| **Retry** | 5 |
| **Тригер** | `ContractHealthCheckService`, `Dclimate::VerificationService` (fraud), `ContractTerminationService` |
| **Вхід** | `organization_id`, `naas_contract_id`, `tree_id` (опціонально) |
| **Сервіси** | `BlockchainBurningService.call` |
| **Side Effects** | Створює `MaintenanceRecord` (decommissioning). ActionCable + Turbo Stream broadcast. |

#### `InsurancePayoutWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `critical` |
| **Retry** | 10 |
| **Тригер** | `Dclimate::VerificationService` (fire_confirmed), cron при triggered insurances |
| **Вхід** | `insurance_id` (Integer) |
| **Сервіси** | `Etherisc::ClaimService.new(insurance).claim!` (при `uses_etherisc?`) або `BlockchainMintingService.call` |
| **Side Effects** | `insurance.pay!`, `BlockchainConfirmationWorker.perform_in(30.seconds, ...)`. Перевіряє супутниковий консенсус (Cosmic Eye guard). |

#### `EcosystemHealingWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `critical` |
| **Retry** | 3 |
| **Тригер** | Після закриття `EwsAlert` через `MaintenanceRecord` |
| **Вхід** | `record_id` (Integer, MaintenanceRecord) |
| **Сервіси** | — |
| **Side Effects** | `actuator.mark_idle!` (при repair), `tree.decommission!` (при decommissioning), `tree.declare_deceased!` + `PuroEarthPassportWorker.perform_async` (при biomass_extraction), `alert.resolve!`. |

---

### 📡 Downlink — Команди на Пристрої

#### `ActuatorCommandWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | 3 (include `CoapEncryption`) |
| **Тригер** | `EmergencyResponseService`, `HardwareKeyService` |
| **Вхід** | `command_id` (Integer), `explicit_key` (hex, опціонально) |
| **Сервіси** | — |
| **Side Effects** | CoAP PUT до Queen gateway. `actuator.mark_active!`, `command.acknowledge!`. Планує `ResetActuatorStateWorker.perform_in(duration_seconds, ...)`. При `sidekiq_retries_exhausted`: `command.fail!` + Turbo Stream broadcast помилки. |

#### `OtaTransmissionWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | false (самостійна retry-логіка) |
| **Тригер** | Ручний запуск через API або після OTA mismatch detection |
| **Вхід** | `queen_uid`, `firmware_type` (`mruby`/`firmware`/`tinyml`/`weights`), `record_id`, `chunk_index` (default 0), `retry_count` (default 0) |
| **Сервіси** | `OtaPackagerService.prepare(firmware, chunk_size: CHUNK_SIZE, cluster_id: gateway.cluster_id)` |
| **Side Effects** | CoAP PUT до Queen (AES-256-CBC). Pacing: `perform_in(0.4.seconds, ...)` між чанками. **[FW.23]** Worker завжди форвардить `gateway.cluster_id` (колонка `NOT NULL` у `gateways`), тож `packages` Enumerator автоматично містить 3 HMAC trailer-чанки `[0x9B]` після bytecode; логіка pacing без змін. Queen relay-ює `[0x9B]`-чанки stateless; Soldier верифікує dual-gate перед FLASH write. `total_chunks` worker'а береться з `manifest[:total_packages]` (= bytecode + 3 trailer) і саме за цим лічильником Turbo Stream `OtaProgressBar` рахує процент та переводить шлюз у `:idle` — без фолбеку на `total_chunks` шлюз би "завершив" OTA за 3 чанки до отримання HMAC печатки. При `sidekiq_retries_exhausted`: `gateway.update!(state: :faulty)` — запобігає Gateway stuck у `:updating`. |

#### `ResetActuatorStateWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | 3 |
| **Тригер** | `ActuatorCommandWorker.perform_in(duration_seconds, ...)` |
| **Вхід** | `command_id` (Integer) |
| **Сервіси** | — |
| **Side Effects** | `actuator.mark_idle!`, `command.confirm!`. Turbo Stream broadcast кард актуатора. |

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
> Код: `app/workers/daily_aggregation_worker.rb:45` — `if target_date.on_weekday?`

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
| **`on_success`** | Спрацьовує тільки якщо **всі** `GenerateClusterInsightWorker` jobs завершились успішно. Запускає: 1) `ClusterHealthCheckWorker.perform_async(date_string)` — аудит NaaS-контрактів; 2) `InsightGeneratorService.cleanup_old_logs!` — видаляє `TelemetryLog` старше 7 днів (крім `oracle_status='dispatched'`). |

#### `ClusterHealthCheckWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | (1) `InsightBatchCallbacks#on_success` — після успішного завершення всіх `GenerateClusterInsightWorker` чанків (real-time після ≈01:00 UTC batch); (2) Sidekiq cron `0 2 * * *` (`cluster_health_arbitration` у `config/sidekiq.yml`) — захисний fallback, відпрацьовує навіть коли denний batch мав нуль кластерів з даними і callback не спрацював. |
| **Вхід** | `date_string` (String ISO8601, опціонально). Якщо `nil` — кожен кластер бере `cluster.local_yesterday` (per-tenant timezone). |
| **Сервіси** | `contract.check_cluster_health!(target_date)` → `ContractHealthCheckService` |
| **Side Effects** | При healthy → `CeloRewardWorker.perform_async`. При breached → `ContractHealthCheckService` → `BurnCarbonTokensWorker.perform_async`. Оновлює `cluster.health_index`. **⚠️ Double-trigger caveat:** callback + cron можуть викликати worker двічі на день для тих самих кластерів — `recalculate_health_index!` ідемпотентний, але `CeloRewardWorker.perform_async` без advisory lock може відправити cUSD двічі. Захист — на рівні `Celo::CommunityRewardService` (Kredis.lock), див. §10. |

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
| **`on_success`** | Спрацьовує тільки якщо **всі** `EvaluateTreeBatchWorker` jobs завершились успішно. Запускає: `MintCarbonCoinWorker.perform_async` (без аргументів — auto-discovery всіх pending BlockchainTransaction). |

#### `EvaluateTreeBatchWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | `TokenomicsEvaluatorWorker` (Sidekiq Pro Batch child) |
| **Вхід** | `wallet_ids` (Array\<Integer>), `cycle_id` (String UUID) |
| **Сервіси** | — |
| **Side Effects** | `wallet.lock_and_mint!(points, threshold)` при `balance >= 10_000`. → `MintCarbonCoinWorker` (implicit через lock_and_mint!). |

#### `PartitionMaintenanceWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | Sidekiq cron: щодня (рекомендовано 00:30 UTC, перед `DailyAggregationWorker`) |
| **Вхід** | — |
| **Сервіси** | — (пряма робота з `ActiveRecord::Base.connection`) |
| **Side Effects** | `CREATE TABLE IF NOT EXISTS ... PARTITION OF ...` для таблиць `telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`, `codex_matches` (Codex Phase 4 Battle Arena — додано до `PARTITIONED_TABLES`). Перевіряє та створює партиції для поточного та наступного місяця (формат: `{table}_y{YYYY}m{MM}`). DDL-операція ідемпотентна — повторний запуск безпечний. Phase 7 додав `Sentry.capture_exception` у `rescue` блок щоб тихий збій DDL не призвів до `no partition of relation` на 1-му числі наступного місяця. |

---

### 🔗 Web3 Critical — Часочутливий Блокчейн

#### `BlockchainConfirmationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 10, unique_for: 10 хвилин |
| **Тригер** | `BlockchainMintingService`, `BlockchainBurningService`, `InsurancePayoutWorker`, `ToucanBridgeWorker` |
| **Вхід** | `tx_hash` (String) |
| **Сервіси** | — |
| **Side Effects** | `eth_get_transaction_receipt` (Polygon RPC). При `0x1`: `tx.confirm!`. При revert: `tx.fail!`. Retry при pending (ще в мемпулі). **[MEMPOOL LIMBO GUARD]** `sidekiq_retries_exhausted` handler: при вичерпанні всіх 10 ретраїв (~15-20 хвилин поллінгу) делегує до `MintingRollbackService.call(transactions: BlockchainTransaction.where(tx_hash:, status: :sent))`. Запобігає зависанню транзакцій у статусі `:sent` з замороженим `locked_balance` після потрапляння job у Sidekiq Dead queue. |

#### `MintCarbonCoinWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
| **Includes** | `Web3CircuitBreaker` — `with_circuit_breaker("polygon_rpc")` |
| **Тригер** | `OracleCallbacksController#create` (Chainlink DON webhook) або `TokenomicsEvaluatorWorker` (cron fallback) або `TokenomicsBatchCallbacks#on_success` |
| **Вхід** | `telemetry_log_id` (опціонально), `created_at_iso` (опціонально) |
| **Сервіси** | `BlockchainMintingService.call_batch` або `.call` |
| **Side Effects** | При вичерпанні ретраїв: `MintingRollbackService.call` (розблоковує `locked_balance`). |

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

#### `ToucanBridgeWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
| **Тригер** | Ручний запуск при bridging request |
| **Вхід** | `blockchain_transaction_id` (Integer), `created_at_iso` (String, ISO 8601, опціонально) |
| **Сервіси** | `find_blockchain_tx_with_pruning(blockchain_transaction_id, created_at_iso)`, `Toucan::BridgeService.call(blockchain_transaction_id, created_at_iso)` |
| **Side Effects** | `tx.mark_as_sent!`. `wallet.locked_balance -= locked_points`, `wallet.toucan_bridged_balance += locked_points`. `BlockchainConfirmationWorker.perform_in(30.seconds, ...)`. |

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
| **Сервіси** | `Solana::BatchPayoutService.call` → виплата накопиченого (поріг `solana_batch_threshold_usdc` > 0) |

#### `PuroEarthPassportWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 5 |
| **Тригер** | `EcosystemHealingWorker` при `biomass_extraction` |
| **Вхід** | `maintenance_record_id` (Integer) |
| **Сервіси** | Phase 1: `PuroEarth::PassportService.new(payload).anchor!` (on-chain anchoring → Polygon D-MRV Registry). Phase 2: `PuroEarth::RegistryApiService.new(payload, tx_hash:).submit!` (REST API → Puro.earth CORC) |
| **Side Effects** | `record.update!(biomass_passport_tx_hash: tx_hash)`. `record.update!(puro_earth_corc_ref: corc_ref)` (якщо REST API успішний). `BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)`. Phase 2 non-blocking: REST API failure не скасовує on-chain anchoring. |

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

#### `KlimaRetirementWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3 |
| **Тригер** | Ручний запуск через API (ESG reporting) |
| **Вхід** | `wallet_id`, `amount` |
| **Сервіси** | `KlimaDao::RetirementService.new(wallet, amount).retire_carbon!` |

#### `HadronAssetRegistrationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 5 |
| **Тригер** | При активації NaasContract |
| **Вхід** | `naas_contract_id` (Integer) |
| **Сервіси** | `Polygon::HadronComplianceService.new.register_asset!(naas_contract)` |

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
| **Side Effects** | Зчитує 13 on-chain параметрів (8 Lorenz + 3 tokenomics + 2 slashing) з `ProtocolParameters.sol`. Fixed-point conversion (uint256/1e18 → BigDecimal). Порівнює з `SystemParameter` і оновлює змінені (source: `"governance"`, updated_by: `User.oracle_executioner`). Timeout 10s per RPC call. |

---

### 📦 Low — Аудит та Зберігання

#### `AuditLogWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3 |
| **Тригер** | Різні контролери та сервіси (аудит фінансових дій) |
| **Вхід** | `attrs` (Hash для `AuditLog.create!`) |
| **Сервіси** | — |
| **Side Effects** | `AuditLog.create!` → `FilecoinArchiveWorker.perform_async(log.id)`. |

> **🔗 Chain Integrity Invariant (Concurrency Guard).** `chain_hash` будується як SHA-256(previous_chain_hash | chain_payload) — це створює сувору залежність від порядку. Без серіалізації паралельні Sidekiq-потоки можуть прочитати один і той самий `AuditLog.last` для організації і утворити форки ланцюга. **Mitigation у коді** (`app/models/audit_log.rb`, [auditable]):
> 1. Single-row insert (`AuditLog.create!`): `before_create :compute_chain_hash` бере `pg_advisory_xact_lock(827549841, organization_id)` (transaction-scoped). Lock автоматично знімається при COMMIT/ROLLBACK — не потрібно `lock_release`. Паралельні організації не блокують одна одну (lock keyed на `organization_id`).
> 2. Bulk insert (`AuditLog.bulk_record!(entries)`): групує entries за `organization_id`, бере той самий advisory lock per org, обчислює послідовно chain_hash для кожного row перед `insert_all`. Один SQL батч, одна транзакція, нульовий fork ризик.
> 3. Інтеграційна перевірка `AuditLog.verify_chain_integrity(org_id)` доступна для cool-down аудиту й Filecoin verification (`{ valid: false, broken_at: id }` при будь-якому дефекті).
>
> **Чому advisory lock, а не `SELECT ... FOR UPDATE` / `Kredis.lock`:** advisory locks PG безкоштовні (in-memory у PG), не вимагають реального рядка-предка (на стадії genesis рядка немає), не залежать від Redis (Kredis fallback на Solid Cache додає latency). Transaction-scoped семантика гарантує авто-релізу при ROLLBACK через Sidekiq retry.

#### `FilecoinArchiveWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 5 |
| **Тригер** | `AuditLogWorker` |
| **Вхід** | `audit_log_id` (Integer) |
| **Сервіси** | `Filecoin::ArchiveService.new(audit_log).archive!` |

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
        │     │     └─ cold: SilkenNet::SeedDerivation.derive_initial_state(K_seed, epoch_day)
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
        └─→ GatewayTelemetryWorker [uplink] (при DID=0x00)
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
                          └─→ InsightGeneratorService.cleanup_old_logs!
```

### ⏰ Щогодинний Цикл (Tokenomics)

```
Sidekiq Cron (кожну годину)
  └─→ TokenomicsEvaluatorWorker [default]
        └─→ Sidekiq::Batch → EvaluateTreeBatchWorker [default] ×N
              └─→ wallet.lock_and_mint!
                    └─→ MintCarbonCoinWorker [web3_critical]
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
              ├─→ isParameterSet(key) × 13 параметрів (Timeout 10s per call)
              ├─→ getParameter(key) для встановлених параметрів
              ├─→ Fixed-point conversion (uint256 / 1e18 → BigDecimal)
              └─→ SystemParameter.set(key, value, source: "governance")
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

### 🌉 Toucan Bridge Ланцюг

```
API request → ToucanBridgeWorker [web3_critical]
  └─→ Toucan::BridgeService (SCC → TCO2)
        └─→ BlockchainConfirmationWorker [web3_critical]
```

### 📦 Audit + Filecoin Ланцюг

```
Financial action
  └─→ AuditLogWorker [low]
        └─→ AuditLog.create!
              └─→ FilecoinArchiveWorker [low]
                    └─→ Filecoin::ArchiveService (IPFS CID)
```

---

## 🌍 13. Зовнішні API Залежності

| Сервіс | Мережа/Протокол | ENV / Credential | Воркер/Сервіс |
|--------|----------------|-------------------|---------------|
| **Polygon RPC** (Alchemy) | EVM JSON-RPC | `ALCHEMY_POLYGON_RPC_URL` | BlockchainMintingService, BlockchainBurningService, ChainAuditService, ChainlinkDispatchService, KlimaDao, ToucanBridgeService, PriceOracleService |
| **Ethereum L1 RPC** | EVM JSON-RPC | `ALCHEMY_ETHEREUM_RPC_URL` | StateAnchorService |
| **Solana RPC** | JSON-RPC 2.0 | `SOLANA_RPC_URL`, `SOLANA_WALLET_KEYPAIR` (mandatory), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS` | Solana::MintingService |
| **Celo RPC** | EVM JSON-RPC | `CELO_RPC_URL` (primary) + опц. `CELO_RPC_URL_FALLBACK_1`, `CELO_RPC_URL_FALLBACK_2` (E.49 cascade через `Web3::ResilientClient`) | Celo::CommunityRewardService, MintingRollbackService |
| **IoTeX W3bstream** | HTTPS REST | `iotex_w3bstream_url`, `iotex_api_key` | Iotex::W3bstreamVerificationService |
| **peaq Network** | HTTPS REST | `peaq_node_url`, `peaq_signing_key` | Peaq::DidRegistryService |
| **Chainlink Functions** | On-chain (Polygon) | `CHAINLINK_FUNCTIONS_ROUTER`, `CHAINLINK_SUBSCRIPTION_ID` | Chainlink::OracleDispatchService |
| **dClimate API** | HTTPS REST | `DCLIMATE_BASE_URL` (default: `https://api.dclimate.net`), `DCLIMATE_FIRMS_DATASET` (default: `firms_nrt_global-area_v2`), `Rails.credentials.dclimate.api_key` (Bearer) | Dclimate::VerificationService |
| **Streamr Network** | HTTPS REST | `streamr_stream_id`, `streamr_api_key` | Streamr::BroadcasterService |
| **Filecoin/IPFS** (Pinata) | HTTPS REST | `filecoin_api_key` / `FILECOIN_PINNING_API_URL` | Filecoin::ArchiveService, VerificationService |
| **The Graph** | GraphQL | `the_graph_api_url` | TheGraph::QueryService |
| **Polygon Hadron** | HTTPS REST | `hadron_api_key` / `HADRON_API_URL` | Polygon::HadronComplianceService |
| **Etherisc DIP** | On-chain (Polygon) | `ETHERISC_DIP_CONTRACT_ADDRESS` | Etherisc::ClaimService |
| **Puro.earth D-MRV Registry** | On-chain (Polygon) + HTTPS REST | `PURO_EARTH_REGISTRY_CONTRACT_ADDRESS`, `ORACLE_PRIVATE_KEY` (on-chain); `PURO_EARTH_API_URL` (default: `https://api.puro.earth`), `Rails.credentials.puro_earth.api_key` або `PURO_EARTH_API_KEY` (REST) | PuroEarth::PassportService, PuroEarth::RegistryApiService |
| **KlimaDAO** | On-chain (Polygon) | `KLIMA_RETIREMENT_CONTRACT` | KlimaDao::RetirementService |
| **Toucan Protocol** | On-chain (Polygon) | `TOUCAN_BRIDGE_CONTRACT_ADDRESS` | Toucan::BridgeService |
| **Uniswap V3 Quoter** | On-chain (Polygon) | `POLYGON_RPC_URL` | PriceOracleService |
| **CoAP Gateway** | CoAP/UDP | `gateway.ip_address` (dynamic) | ActuatorCommandWorker, OtaTransmissionWorker |

---

## 🧭 13b. SSOT Drift Register (Doc ↔ Code Sync)

> **Принцип:** Цей документ — SSOT. Тобто:
> - якщо **код випередив документ** — оновлюємо документ (тут, у [`04_02`](04_02_Business_Logic_and_Services)) щоб реальність відображалася;
> - якщо **документ випередив код** — створюємо/оновлюємо запис у [`00_07`](00_07_Action_Plan_Tracker) як невиконану задачу;
> - якщо **нема ні там, ні там** — приймаємо рішення (потрібне → реєструємо в [`00_07`](00_07_Action_Plan_Tracker); не потрібне → видаляємо плани з [`04_02`](04_02_Business_Logic_and_Services)).
>
> Цей реєстр фіксує **відомі divergence-точки** та їх статус. Періодичний аудит — кожен Cool-down цикл Shape Up ([`00_04`](00_04_Shape_Up_Operations_and_RnD_Clusters)).

| Дата | Зона | Тип drift | Що зроблено | Cross-ref |
|------|------|-----------|-------------|-----------|
| 2026-05-12 | `Security::WeakKeyDetector` + `master_key_strength_check.rb` initializer | Code ahead of doc (були в [`00_07`](00_07_Action_Plan_Tracker)/[`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security), але §8 04_02 їх не описувала) | Додано в §8 (renamed → "Hardware, IoT & Security") | [SEC.9](00_07_Action_Plan_Tracker), [`03_05 §3.1а`](03_05_Hardware_Symmetric_Crypto_and_Security) |
| 2026-05-12 | `Celo::CommunityRewardService` RPC fallback cascade | Code matched doc (E.49 синхронно виконано: код + 04_02 + .env.example + 00_07) | `RPC_FALLBACK_ENV_KEYS` додано, External API row оновлено | [E.49](00_07_Action_Plan_Tracker) |
| 2026-05-12 | `MintingRollbackService` (Celo branch) | Code bug + doc gap (fallback указував на polygon-rpc.com для Celo TX) | Виправлено per-chain dispatch; doc оновлено | [E.49](00_07_Action_Plan_Tracker) |
| 2026-05-12 | `MintBatchCollectorWorker` секція | Doc misplacement (queue `web3` був у "💤 Web3 Low") | Перенесено у "🌐 Web3 — Стандартні Мультичейн" | §11 |
| 2026-05-12 | `ClusterHealthCheckWorker` heading | Doc structure bug (таблиця без `####` заголовка) | Додано `#### ClusterHealthCheckWorker` | §11 |
| 2026-05-18 | `MintingRollbackService#fetch_evm_transaction_receipt` | **Code bug — double-spend hole.** Сервіс читав `receipt["status"]` напряму, тоді як eth gem 0.5.x повертає wrapped JSON-RPC envelope (`{"result":{"status":…}}`) → всі confirmed/pending транзакції класифікувались як `:reverted`, кошти розблоковувались поверх вже-надісланого on-chain mint'у. Spec фіксував саме хибну flat-форму, тож регрес не світився у CI. | Витягнуто `classify_evm_receipt(envelope)` — приймає обидві форми (production wrapped + legacy flat); додано 4 нові spec example у `describe "JSON-RPC envelope shape (real eth gem 0.5.x)"`; запис у §4 оновлено. | §4 MintingRollbackService; `spec/services/minting_rollback_service_spec.rb` |
| 2026-05-18 | `SilkenNet::SeedDerivation` API назви | Doc-ahead-of-code: doc посилався на `derive_initial_state`, `bytes_to_signed_unit_float`, keyword-args `derive_seed(device_uid:)` — у коді реально `initial_state`, `signed_unit_float`, позиційний `derive_seed(device_uid)`. | Назви, повернений тип (`derive_seed → 64-char HEX`) та сигнатура виправлені у §3; згадки у `Attractor` (cold-start) теж оновлено. | §3 SilkenNet::SeedDerivation / Attractor |
| 2026-05-18 | `Ethereum::StateAnchorService.generate_state_root` формула | Code ahead of doc (E.53 SFC supply + E.54 active_tree_count): код хешує 5 компонентів і обгорнутий у REPEATABLE READ, doc показував стару 3-компонентну формулу й не згадував double-anchor guard / pending-resume. | §10 переписано: повний 5-компонентний SHA-256, snapshot isolation, double-anchor guard, timeout-as-pending recovery; `EthereumAnchor#verify_state_root` зафіксовано як SSOT-метод верифікації. | §10 Ethereum::StateAnchorService |
| 2026-05-18 | `PartitionMaintenanceWorker::PARTITIONED_TABLES` | Code ahead of doc: код тримає 4 RANGE-таблиці (включно з `codex_matches` Phase 4), doc перераховував 3. | §11 оновлено: `codex_matches` додано до списку; згадано Sentry rescue. | §11 PartitionMaintenanceWorker (узгоджено з DOC-R.11) |
| 2026-05-18 | `OtaTransmissionWorker` cluster_id forwarding | **Code bug + doc drift — FW.23 HMAC trailer був ВИМКНЕНИЙ у проді.** Doc обіцяв `OtaPackagerService.prepare(firmware, cluster_id: cluster.id)`, але worker викликав `prepare(firmware_obj, chunk_size: CHUNK_SIZE)` без `cluster_id:`, тож `hmac_enabled?` повертав false → жодного `0x9B` трейлеру → Soldier dual-gate не мав HMAC печатки для верифікації → tampered/replayed OTA байткод проходив. `total_chunks` зчитувався з `manifest[:total_chunks]` (bytecode-only) замість `total_packages` (bytecode + 3 trailer), тож при міграції на signed-stream шлюз би переходив у `:idle` на 3 чанки раніше HMAC seal'у. | Worker передає `cluster_id: gateway.cluster_id` (NOT NULL у схемі) + читає `total_packages \|\| total_chunks`; spec має 2 нові examples у `describe "[FW.23] HMAC trailer cluster_id forwarding"`; doc оновлено. | `app/workers/ota_transmission_worker.rb`; `spec/workers/ota_transmission_worker_spec.rb`; §11 OtaTransmissionWorker |
| 2026-05-18 | `ClusterHealthCheckWorker` double-trigger → подвійна cUSD виплата | **Code bug** — `config/sidekiq.yml` має `cluster_health_arbitration` cron на 02:00 UTC, і ТА сама job ставиться через `InsightBatchCallbacks#on_success` після 01:00 батчу. Worker (`recalculate_health_index!`) ідемпотентний, але `CeloRewardWorker.perform_async(cluster_id, date)` без guard'у; `Celo::CommunityRewardService.reward_community!` тримав лише `Kredis.lock(lock:web3:oracle:<address>)` — це серіалізує усі Celo TX'и, не дедуплікує `(cluster, date)`. Здоровий кластер отримував 10 cUSD на день замість 5. | Додано `reward_already_sent?` guard у `Celo::CommunityRewardService` — перевіряє `BlockchainTransaction.where(sourceable: cluster, token_type: :cusd, status: [:sent, :confirmed, :processing], created_at: target_date.beginning_of_day...+1.day).exists?`; failed/manual_review TX'и НЕ блокують admin retry. Spec має 2 нові examples (skip on existing, retry on failed). Doc для `ClusterHealthCheckWorker` оновлено — обидва тригери задокументовані з посиланням на guard. | §11 `ClusterHealthCheckWorker`; `app/services/celo/community_reward_service.rb`; `spec/services/celo/community_reward_service_spec.rb` |
| 2026-05-29 | `ContractHealthCheckService` / `BlockchainBurningService` slashing path | **Doc-ahead + financial-safety — формула + blackout закрито 2026-05-29; de-correlation 2026-06-03.** [`05_05 §3`](05_05_Slashing_and_Risk_Policy) специфікує convex-формулу `damage_ratio^1.3 × min(penalty_factor,2.0)` + `cause_classification` gate. Стан коду: (1) `cause_classification` A/B/C-термін ще відсутній (🟡 open); (2) ✅ `BlockchainBurningService` тепер палить за **§3 convex-кривою** (`#calculate_slash_ratio`; GAMMA/PF_MAX через `SystemParameter`, clamp 0..1, 8 specs) — **не лінійно**; (3) ✅ `ContractHealthCheckService#flag_data_blackout!` — cluster-wide empty → Field Audit (force-majeure), no burn (10 specs); (4) ✅ cause-driven `penalty_factor` uplift із comms-loss **de-correlation** (`#calculate_penalty_factor`: no-ack/Streamr через `max()`, no-maintenance additive; **INERT** за `SystemParameter :slash_cause_uplift_enabled` до DAO-confirm). | **Частково закрито** (convex-формула + blackout-routing). Лишається: formal A/B/C `cause_classification` + **активація** uplift → DAO/founder-go (незворотна фін. логіка) + repeat-offence вага + tree-side `streamr_undelivered` сигнал-джерело. Принцип: [`05_05`](05_05_Slashing_and_Risk_Policy) §6/§7. tracked: [`00_07`](00_07_Action_Plan_Tracker) SLASH-1. | [`05_05`](05_05_Slashing_and_Risk_Policy) §3/§6; [`00_07`](00_07_Action_Plan_Tracker) SLASH-1; `contract_health_check_service.rb`, `blockchain_burning_service.rb` |
| — (відкрите) | `ClusterEntropyAnalyzerWorker` cron | Doc-only feature: §11 каже "Sidekiq cron, щогодини", але у `config/sidekiq.yml` запису немає, і жоден інший шлях не викликає воркер (єдина згадка поза тестами — коментар у `prometheus.rb`). Без cron `silkennet_cluster_entropy_score` gauge ніколи не оновлюється → entropy_anomaly алерти не спрацьовують. | Не виправлено цією зміною: воркер приймає `cluster_id` — для cron потрібен окремий orchestrator-воркер що проходить `Cluster.find_each` і фан-аутить через `perform_async`. Залишається на reviewer'а як окремий PR. | §11 `ClusterEntropyAnalyzerWorker` |
| — (відкрите) | `InsurancePayoutWorker` сweep cron | Doc-only feature: §11 каже "cron при triggered insurances", але у `config/sidekiq.yml` запису немає. Якщо `Dclimate::VerificationService` enqueue впав, або всі 10 retry вичерпались, страховка лишається у `:triggered` назавжди — кошти у DAO Treasury не доходять до постраждалої організації. | Не виправлено цією зміною: треба окремий sweep-worker, що бере `ParametricInsurance.status_triggered` і робить `perform_async(id)`. Залишається на reviewer'а як окремий PR. | §11 `InsurancePayoutWorker` |
| — (відкрите) | Forester Guild / Cross-Registry / Federated Learning | Doc-only "Planned" — в коді **відсутні**; статус нормальний (Post-TRL 6/7) | Зберігати як design RFC; не маркувати code drift | §"Planned" |

### Як додавати нові записи

1. Виявили divergence (наприклад, нову константу, новий guard clause, новий ENV у коді який не описаний тут) — додайте рядок у таблицю з датою.
2. Якщо drift вимагає коду — заведіть запис у [`00_07`](00_07_Action_Plan_Tracker) з тим самим UID (`E.NN` / `SEC.NN` / `S6.NN`) і посиланням сюди.
3. Drift register **не замінює** оновлення відповідної секції — обидва місця мають бути синхронізовані.

> **Anti-pattern:** "Тимчасово впишу у 04_02, а виправлю код пізніше". Якщо завдання потребує > 1 PR — заведіть [`00_07`](00_07_Action_Plan_Tracker) запис, не блюрте тут.

---

## 🌲 Planned: Forester Guild — Proof-of-Physical-Work (Міністерство Праці)

> **Нотатка N14 інтегрована (Сесія 3).** Відсутній модуль: хто фізично вкручує анкери, міняє обладнання, реагує на EWS-тривоги?

### Проблема

Gaia 2.0 має бездоганну цифрову державу (фінанси, суди, екологія, ідентифікація). Але хто виконує **фізичну** роботу?

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
LocalRanger receives SingleNotificationWorker (SMS/Telegram)
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

**Інтеграція з існуючими моделями:**
- `MaintenanceRecord` отримує нові поля: `bounty_tx_hash`, `proof_cid`, `ranger_id`, `payout_amount_usdc`
- `EwsAlert` отримує: `bounty_id`, `bounty_status` (open/claimed/expired)

**Пріоритет:** Post-TRL 6. Не блокує прототип.

### Архітектурний дизайн: Task Assignment Algorithm 🤖 (S6.10)

> **Cross-ref:** [`00_07` — S6.10](00_07_Action_Plan_Tracker), [`00_07` — E.20](00_07_Action_Plan_Tracker), [`00_07` — E.34](00_07_Action_Plan_Tracker) (dClimate fallback → Forester Guild).

Workflow вище показує **створення** bounty та **claim**, але **алгоритм матчингу ranger↔bounty** і пріоритезація не визначені. Без цього система деградує до first-come-first-served race (далекий ranger може вкрасти bounty у локального) або silent expiry (життєво-критична `EwsAlert :critical` залишається без виконавця, бо нікому не повідомили). Цей розділ закриває S6.10.

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

Ваги (`0.40 / 0.25 / 0.20 / 0.10 / 0.05`) — стартові, налаштовуються через `SystemParameter(:forester_assignment_weights, ...)` (динамічно через `BIZ.4` DAO Governance, не hardcoded).

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
| Bounty досягло `expires_at` | Залежно від severity: critical → SMS-fallback на регіонального координатора + emergency dispatcher webhook (E.34); інші → fail з notification до `EwsAlert.user` |

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

---

## 🌍 Planned: Cross-Registry API (Міністерство Закордонних Справ)

> **Нотатка N15 інтегрована (Сесія 3).** Як SCC-токен буде визнаний у "старому світі" — Verra, Gold Standard, ООН?

### Проблема

Gaia 2.0 — ідеальна суверенна держава. Але вона ізольована. Корпоративний покупець карбон-кредитів не може використати SCC для звіту за стандартами:
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

**Пріоритет:** Post-TRL 7. Критично для institutional sales. Не блокує прототип.

---

## 🧠 Planned: Federated Learning Loop (Міністерство Освіти)

> **Нотатка N16 інтегрована (Сесія 3).** Поточна TinyML-модель тренується вручну через Rake-таску. Вона статична.

### Проблема

`silken_forest.marshal` — поточна ML-модель для `InsightGeneratorService`. Вона:
- Тренується вручну командою `rake ml:train`
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
ActiveStorage: зберегти новий marshal як TinyMlModel.binary_payload
OtaTransmissionWorker → OTA broadcast нової моделі на STM32-вузли
AuditLogWorker → запис факту оновлення моделі
```

**Нові компоненти:**

| Компонент | Тип | Призначення |
|-----------|-----|------------|
| `FederatedLearningWorker` | Worker (`low` queue) | Щомісячний цикл перенавчання |
| `FederatedTrainingService` | Service | Incremental ML-тренування на нових підтверджених даних |
| `ModelValidationService` | Service | A/B тест нової моделі vs поточної на holdout set |
| `ModelAuditRecord` | Model | Лог кожного оновлення моделі (версія, точність, timestamp, deployer) |

**Безпека:**
- SHA256-хеш нового marshal файлу перевіряється перед OTA-розсилкою
- `TinyMlModel.checksum` порівнюється на Soldier після отримання OTA
- Rollback: якщо нова модель видає >5% false positives за тиждень → auto-revert до попередньої

**Пріоритет:** Post-TRL 7. Не блокує прототип.

---

## Додаткові Матеріали

### Математичні Модулі — Формальний Опис

#### `SilkenNet::Attractor` — Атрактор Лоренца

Система диференціальних рівнянь:

$$\begin{cases} \dot{x} = \sigma(y - x) \\ \dot{y} = x(\rho - z) - y \\ \dot{z} = xy - \beta z \end{cases}$$

Константи: σ = 10.0, ρ = 28.0, β = 8/3. Адаптивні параметри: акустика → σ (clamped 5–30), температура → ρ (clamped 10–50), `delta_t_s`/`vcap_mv` → β (clamped 2–4) [FW.5]. **[SEC.11]** Початкова точка `(x₀, y₀, z₀)` ∈ [-1, +1]³ деривується з per-device `K_seed` через `HMAC-SHA256(K_seed, "init|" || epoch_day_be)` (cold start) або читається з попереднього `TelemetryLog.lorenz_state_x/y/z` (warm continuation, mirror RTC DR16-DR18). DID **не** є входом атрактора — лише identifier (та `info`-string у HKDF при provisioning K_seed). 250 ітерацій × 0.01 timestep. **[FIX FW.7]** Float (IEEE 754 double) — байт-ідентично з firmware mruby для Dual Computation Integrity.

Використовується для ідентифікації стресу дерева через відхилення траєкторії z у фазовому просторі. Верифікується ZK-proof через IoTeX W3bstream.

---

### Принципи Безпеки

1. **Zero-Trust:** Кожен пакет шифрується hardware-bound AES ключем у `HardwareKey` (LoRa AES-128 для Tree↔Queen, CoAP AES-256 для Queen↔Rails — domain separation §3.4а у [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security)).
2. **Idempotency:** Всі фінансові воркери мають захист від повторного виконання (status guards / pessimistic lock).
3. **Resilience:** Система підтримує 10+ ретраїв для Web3 операцій та 3–5 для апаратних команд.
4. **Float Determinism:** Розрахунки Атрактора виконуються з Float (IEEE 754 double) ідентично firmware mruby для Dual Computation Integrity (BigDecimal вилучено — давав розбіжність Z після 250 ітерацій хаотичної системи).
5. **ZK-Proof Guard:** Мінтинг токенів неможливий без IoTeX W3bstream верифікації (`verified_by_iotex? == true`).
6. **Chainlink Guard:** Децентралізований оракул обов'язковий перед емісією — запобігає single-point-of-failure.
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
