# 04_02: Бізнес-Логіка та Сервіси

## 🎯 Мета

Зафіксувати повний реєстр бізнес-логіки Rails-моноліту як Єдине Джерело Істини (SSOT). Документ описує всі **Service Objects** та **Sidekiq Workers**: їхні вхідні дані, відповідальність та вихідні ефекти. Слугує картою поточних сервісів для запобігання дублювання логіки під час розробки нових фіч і REST API (04_03).

## ✅ Статус

* **Поточний TRL:** TRL 8 (System Qualified / Mainnet Ready).
* **Обґрунтування:** Всі заглушки (dClimate, Puro.earth) замінено на бойові Web3/HTTP інтеграції. Бізнес-логіка пройшла параноїдальний AI-аудит: повністю усунуто пастки `Network-in-Transaction`, витоки пам'яті (OOM) та ризики подвійної витрати (Double-Spend). Воркери ідемпотентні та fault-tolerant. **Примітка:** Chainlink dispatch має dev/test stub-режим (ENV-gated: при відсутності `CHAINLINK_FUNCTIONS_ROUTER` генерується локальний request ID); production вимагає `CHAINLINK_FUNCTIONS_ROUTER` та `CHAINLINK_SUBSCRIPTION_ID`.
* **Пов'язані модулі:** Схема БД — `04_01_Database_Schema`. Proof of Growth — `05_02_Proof_of_Growth_Pipeline`. Апаратне шифрування — `03_05_Hardware_AES256`.

---

## 🏗️ 1. Архітектурні Засади

### Базові класи

| Компонент | Файл | Призначення |
|-----------|------|-------------|
| `ApplicationService` | `app/services/application_service.rb` | Базовий клас для всіх сервісів. Надає `.call(...)` → `new(...).perform` template. |
| `ApplicationWeb3Worker` | `app/workers/application_web3_worker.rb` | Базовий **модуль** (не клас) для всіх блокчейн-воркерів. Включає: RPC rate limiter (50 rps), уніфіковану обробку помилок (HTTPX/Net timeouts), partition-pruned lookups: `find_telemetry_log_with_pruning(id, created_at_iso)` та `find_blockchain_tx_with_pruning(id, created_at_iso)` — обидва додають `created_at` у `WHERE` для уникнення Global Partition Scan по RANGE-партиціонованих таблицях. |
| `Web3CircuitBreaker` | `app/workers/concerns/web3_circuit_breaker.rb` | **[NEW]** ActiveSupport Concern із 3-state Circuit Breaker (`:closed` → `:open` → `:half_open`). `FAILURE_THRESHOLD=5` послідовних помилок → `OPEN_TIMEOUT=300с` (5 хв) fail-fast. Стан зберігається в `Rails.cache` (Solid Cache) — працює між Sidekiq-процесами та серверами. Розпізнає transient errors: `HTTPX::TimeoutError`, `Net::ReadTimeout`, `Errno::ECONNREFUSED`, `Web3::HttpClient::RequestError` + wrapped custom errors (`transient_cause?` перевіряє `Exception#cause` рекурсивно). Prometheus metric: `CIRCUIT_BREAKER_REJECTIONS`. Raises `CircuitOpenError` при відкритому circuit. Інтегровано в `IotexVerificationWorker`, `ChainlinkDispatchWorker`. |
| `CoapEncryption` | `app/workers/concerns/coap_encryption.rb` | Concern для downlink-воркерів. AES-256-CBC шифрування з випадковим IV, нульовий padding. Формат: `[IV:16][Ciphertext:N×16]`. |

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
| **Вхід** | `binary_batch` (сирий бінарний батч), `gateway_id` (Integer, опціонально — `nil` якщо шлюз невідомий) |
| **Що робить** | Розрізає бінарний батч на 21-байтні чанки (`[DID:4][RSSI:1][Payload:16]`). Калібрує сенсорні дані, обчислює Z-значення атрактора Лоренца, записує `TelemetryLog`. Детектує `firmware_mismatch`. Маршрутизує "нульовий" пакет Королеви до `GatewayTelemetryWorker`. |
| **Зовнішні виклики** | `SilkenNet::Attractor.calculate_z`, `AlertDispatchService.analyze_and_trigger!`, `IotexVerificationWorker.perform_async`, `StreamrBroadcastWorker.perform_async`, `GatewayTelemetryWorker.perform_async` |
| **Вихід / Side Effects** | Створює `TelemetryLog` записи. Оновлює `tree.latest_voltage_mv`, `tree.health_streak`. Нараховує `wallet.balance` (growth_points). Позначає `tree.firmware_update_status = :fw_pending` при mismatch. |

### `AlertDispatchService`

| | |
|---|---|
| **Файл** | `app/services/alert_dispatch_service.rb` |
| **Вхід** | `TelemetryLog` (через `.analyze_and_trigger!`) або `Tree` + `message` (через `.create_fraud_alert!`) |
| **Що робить** | Аналізує телеметрію по 5 напрямках: вандалізм (tamper), пожежа/температура, сейсміка, посуха/атрактор, шкідники. Адаптивні пороги (з кластера/породи дерева). Redis-фільтр тиші (5 хвилин per `tree_id:alert_type`). |
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

### `SilkenNet::Attractor`

| | |
|---|---|
| **Файл** | `app/services/silken_net/attractor.rb` |
| **Вхід** | `seed` (Integer/DID), `temp` (Float °C), `acoustic` (Integer events) |
| **Що робить** | Обчислює Z-значення атрактора Лоренца. σ=10, ρ=28, β=8/3. 250 ітерацій, timestep=0.01. `BigDecimal(18)` для крос-платформної детермінованості. Clamp: σ∈[5,30], ρ∈[10,50]. |
| **Вихід** | `calculate_z → Float` (rounded 4). `homeostatic? → Boolean`. `generate_trajectory → Array<Float>` (плаский масив x,y,z × 250 для Three.js). |
| **Примітка** | `generate_trajectory`: перший триплет (індекс 0–2) — початковий seed-стан до інтеграції (`i=0,1,2` → x₀,y₀,z₀); інтеграція Лоренца починається з індексу 3 (`i=3` → крок 1). |

### `SilkenNet::GeoUtils`

| | |
|---|---|
| **Файл** | `app/services/silken_net/geo_utils.rb` |
| **Вхід** | `lat1, lng1, lat2, lng2` (Float, WGS-84) |
| **Що робить** | Haversine distance calculation між двома GPS-точками. |
| **Вихід** | `haversine_distance_m → Float` (метри). |

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
| **Що робить** | Пакетна емісія SCC/SFC на Polygon через `mint` або `batchMint`. Guard clauses: `verified_by_iotex?`, `oracle_status_fulfilled?` (enum method), `hadron_kyc_status == "approved"`. **[BLOCKER-11]** Guards активні лише при `telemetry_log` (oracle-driven flow); tokenomics flow працює без прямої прив'язки до log — growth_points вже верифіковані pipeline'ом. Dynamic Tax 2% при carbon_coin + недофінансований страховий пул (→ DAO Treasury). `Kredis.lock` проти race conditions. `transact` (fire-and-forget). Prometheus metric `SCC_MINTED_TOTAL`. **[B-05]** `insurance_pool_requires_funding?` — cached on-chain `balanceOf` oracle: `INSURANCE_POOL_THRESHOLD = 100_000 SCC`; кеш 15 хв (`dao_treasury_needs_funding`); timeout 10 сек; failsafe → `true` при збої RPC. **[DRY-RUN GUARD]** Перед кожним `batchMint` виконується `eth_call` симуляція (`batch_dry_run_reverts?`) — zero-gas виконання на поточному блоці. Якщо симуляція повертає EVM revert (ознаки: `"revert"`, `"execution reverted"`, `"out of gas"`), активується **Binary Search Poisoned Record Isolation** (Divide & Conquer): замість наївного fallback на N×`mint()`, алгоритм розбиває батч навпіл і тестує кожну половину через `eth_call` dry-run. "Чисті" половини відправляються через `batchMint`, "отруйні" — далі діляться рекурсивно до `MIN_BINARY_SEARCH_SIZE=4` або `MAX_BINARY_SEARCH_DEPTH=6`. Результат: для типового сценарію (1-2 отруйних з 100) ~14 `eth_call` + 2-3 `batchMint` замість 100 `mint()`. `POISONED_RATIO_THRESHOLD=0.3` — при >30% отруйних binary search неефективний → fallback на індивідуальні mints. `send_clean_batch` відправляє чисті підбатчі через `batchMint` з fallback на `mint_individual` при збої transact. Мережеві помилки (RPC timeout) не рахуються як revert — оптимістичний фолбек на `transact`. |
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
| **Що робить** | **[DOUBLE-SPEND GUARD]** Rollback при вичерпанні всіх Sidekiq-ретраїв у `MintCarbonCoinWorker`. Логіка вирішення: (1) `tx_hash` відсутній → безпечний rollback (транзакція не покинула бекенд): розблоковує `locked_balance`, маркує `status = :failed`; (2) `tx_hash` існує → перевіряє стан on-chain через RPC: а) receipt підтверджено → `tx.confirm!` (НЕ rollback); б) receipt null (pending) → `escalate_to_review!` (кошти залишаються заблокованими); в) RPC timeout → `escalate_to_review!`. Multichain: EVM-мережі (Polygon, Celo) використовують `eth_getTransactionReceipt`; Solana — `getTransaction` через прямий HTTP-запит. Fallback RPC cascade через `Web3::RpcConnectionPool` з `fallback_env_keys`. |
| **Вихід** | `nil`. Side effects: `wallet.release_locked_funds!` + `tx.update!(status: :failed)` + Turbo broadcast (при safe rollback); або `tx.escalate_to_review!(reason)` (при manual_review). |

### `PuroEarth::PassportService`

| | |
|---|---|
| **Файл** | `app/services/puro_earth/passport_service.rb` |
| **Вхід** | `payload` (Hash: `tree_did`, `biomass_yield_kg`, `extraction_date`, `gps_coordinates`, `lifetime_telemetry_hash`) |
| **Що робить** | **[MAINNET READY]** Anchors a cryptographic proof of a Biomass Passport onto Polygon for Puro.earth D-MRV (Digital Measurement, Reporting and Verification) / CORC generation. 1) Витягує поля payload у фіксованому алфавітному порядку через `extract_canonical_fields` — рекурсивний обхід хешу з явним ABI-типізуванням (`"string"`, `"uint256"`). Float/BigDecimal масштабуються на `ABI_DECIMAL_SCALE = 10^18` і перетворюються в `uint256` для збереження точності. 2) Кодує поля через `Eth::Abi.encode(types, values)` — бінарне кодування, визначене специфікацією EVM, крос-платформне та мово-незалежне (усуває артефакти Ruby JSON: float-форматування, unicode-екранування, порядок ключів). 3) Обчислює SHA-256 від ABI-кодованого бінарного blob. 4) Викликає `anchorPassport(treeDid, bytes32(payloadHash))` на D-MRV Registry смарт-контракті Polygon через `Web3::RpcConnectionPool` + `Eth::Contract`. Підпис через `ORACLE_PRIVATE_KEY`. Метод `deep_sort_keys` збережено для зворотної сумісності. |
| **Зовнішні виклики** | Polygon RPC (`ALCHEMY_POLYGON_RPC_URL`), `PURO_EARTH_REGISTRY_CONTRACT_ADDRESS` (D-MRV Registry), `ORACLE_PRIVATE_KEY` |
| **Вихід** | `tx_hash` (String, `"0x..."`). Raises `PuroEarth::PassportService::AnchoringError` on RPC failure, insufficient gas, or contract revert. |

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
| **Що робить** | Відправляє телеметрію до IoTeX W3bstream для генерації ZK-proof. Payload: `device_id`, `peaq_did`, `hardware_signature`, `chaotic_data` (z_value, temp, acoustic, voltage, bio_status). **[BLOCKER-06]** `hardware_signature` = Ed25519-підпис payload'у через `Ed25519Crypto::SigningService.sign(hardware_key.binary_key, message)` де `message = "#{tree.did}:#{log.id_value}:#{log.created_at.to_i}"`. Доводить апаратне походження даних із конкретного STM32. Fallback: SHA256-хеш при відсутності HardwareKey (legacy/dev). **[BLOCKER-07]** Валідація формату `zk_proof_ref` через regex: `/\A[0-9a-zA-Z\-_]{8,128}\z/` — захист від injection довільних рядків. |
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

### `Chainlink::OracleDispatchService`

| | |
|---|---|
| **Файл** | `app/services/chainlink/oracle_dispatch_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | Відправляє верифіковану телеметрію до Chainlink Functions DON. Guard clause: `verified_by_iotex? == true`. Payload: `peaq_did`, `lorenz_state` (σ,ρ,β,z), `zk_proof_ref`, `tree_did`, `created_at` (partition key). **[BLOCKER-09]** ABI оновлено до Functions Router v1: `sendRequest(subscriptionId, data, dataVersion, callbackGasLimit, donId)` — 5 параметрів (додано `CHAINLINK_DATA_VERSION`, `CHAINLINK_CALLBACK_GAS_LIMIT`, `CHAINLINK_DON_ID`). **[BLOCKER-04]** `WEB3_STRICT_MODE=true` → raises `DispatchError` при відсутності credentials замість stub mode. |
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

## 🔧 8. Домен: Апаратне Забезпечення (Hardware & IoT)

### `HardwareKeyService`

| | |
|---|---|
| **Файл** | `app/services/hardware_key_service.rb` |
| **Вхід** | `.provision(device)` або `.rotate(device_uid)` |
| **Що робить** | **Provision**: генерує новий 32-байтний AES-256 ключ, зберігає у `HardwareKey`. **Rotate**: Dual-Key Handshake — старий ключ → `previous_aes_key_hex`, генерує новий, відправляє Downlink `sys/key_update` шифрований старим ключем. Захист від подвійної ротації (`RotationPendingError`). |
| **Зовнішні виклики** | `ActuatorCommandWorker.perform_async` (для key update downlink) |
| **Вихід** | `new_hex_key` (String, 64 символи). Raises `RotationPendingError`. |

### `OtaPackagerService`

| | |
|---|---|
| **Файл** | `app/services/ota_packager_service.rb` |
| **Вхід** | `firmware` (BioContractFirmware або TinyMlModel), `chunk_size:` (default 512 bytes CoAP) |
| **Що робить** | Фрагментує `firmware.binary_payload` на чанки. Додає заголовок `[0x99][Index:uint16][Total:uint16]` + CRC16-CCITT per chunk. |
| **Вихід** | `{ manifest: { version, total_size, checksum, sha256, total_chunks }, packages: Enumerator }`. |

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
| **Що робить** | USDC мікро-винагороди на Solana. **[MAINNET READY]** Guard: `verified_by_iotex?` + `oracle_status_fulfilled?` (enum method). **[BLOCKER-1]** `verify_oracle_balance!` — перевіряє баланс SOL оракула через `getBalance` RPC; raises при `< MIN_ORACLE_BALANCE_LAMPORTS` (0.05 SOL = 50M lamports). Розраховує `reward_lamports = 10_000 + (growth_points × 100)`, де `growth_points` — 6-бітне поле телеметрії (0–63). Діапазон: 10_000–16_300 lamports (0.01–0.0163 USDC). 4-крокова транзакція: `getLatestBlockhash` → бінарний SPL Token Transfer Message (compact-u16 + account keys + Ed25519-header) → Ed25519 підпис через `Ed25519Crypto::SigningService` (hex-keypair з `SOLANA_WALLET_KEYPAIR`) → `sendTransaction` (base64). ATA отримувача резолюється динамічно через `getTokenAccountsByOwner` RPC. `SOLANA_WALLET_KEYPAIR` (mandatory), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS` — обов'язкові ENV. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → Solana RPC JSON API (`getLatestBlockhash`, `getTokenAccountsByOwner`, `sendTransaction`) |
| **Вихід** | `tx_signature` (String). Створює `BlockchainTransaction` зі статусом `:sent` (очікує `BlockchainConfirmationWorker`). |

### `Celo::CommunityRewardService`

| | |
|---|---|
| **Файл** | `app/services/celo/community_reward_service.rb` |
| **Вхід** | `cluster` (Cluster AR instance), `target_date` (Date) |
| **Що робить** | ReFi incentive: відправляє 5 cUSD організації якщо `stress_index <= 0.2` та немає fraud. ERC-20 `transfer` на Celo. `Kredis.lock` проти race conditions. **[BLOCKER-1]** `verify_oracle_balance!` — перевіряє баланс CELO оракула через `get_balance`; raises при `< MIN_ORACLE_BALANCE_WEI` (0.05 CELO). |
| **Зовнішні виклики** | Celo RPC (`CELO_RPC_URL`), `Web3::RpcConnectionPool`, `Web3::WeiConverter` |
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
| **Що робить** | Тижневий SHA-256 state root → Ethereum L1 з повним аудит-трейлом. **[BLOCKER-2]** Перед TX створює `EthereumAnchor` запис (status: `pending`) для crash recovery. **[BLOCKER-3]** Gas management: `DEFAULT_GAS_LIMIT=100_000`, `DEFAULT_MAX_FEE_GWEI=100`, `DEFAULT_PRIORITY_FEE_GWEI=2` — всі перекриваються ENV. **[BLOCKER-4]** Inline guard: перевіряє ETH-баланс wallet (`MIN_ANCHOR_BALANCE_WEI = 0.01 ETH`) перед TX; при недостатньому балансі — `EthereumAnchor.status = failed` + raise. **[BLOCKER-6]** `generate_state_root` повертає `{ state_root, total_scc, chain_hash, anchored_at }` — всі компоненти зберігаються в `EthereumAnchor` для незалежної верифікації методом `verify_state_root`. Formula: `SHA256("#{total_scc}\|#{chain_hash}\|#{anchored_at.iso8601}")`. Після успішної TX — `anchor.update!(status: :sent, tx_hash:)`. |
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
| **Що робить** | **[MAINNET READY]** Супутникова верифікація EWS-алертів через dClimate FIRMS API (NASA Near Real-Time Global Active Fire, VIIRS 375 м). HTTP GET до `DCLIMATE_BASE_URL/v4/geo/grid-history/{FIRMS_DATASET}` з координатами дерева та часовим вікном ±1 день. Інтерпретація: FRP ≥ 10 МВт + confidence ≥ 50% → `:fire_confirmed`; ясне небо без аномалій → `:clear_sky_no_fire`; cloud_cover > 70% або відсутні дані → `:obscured_by_clouds`. Підтримує обидва формати відповіді: `{"data": [...]}` (JSON array) та GeoJSON `{"features": [...]}`. VIIRS string confidence (`high/nominal/low`) конвертується у числові значення. Мережеві збої (`Web3::HttpClient::RequestError`) → безпечний fallback до `:obscured_by_clouds`. Авторизація Bearer через `Rails.credentials.dclimate.api_key`. `generate_dclimate_ref` включає метадані супутника для аудит-трейлу. 3 результати: `fire_confirmed` → InsurancePayoutWorker, `clear_sky_no_fire` → BurnCarbonTokensWorker (Slashing за фрод), `obscured_by_clouds` → raise `OrbitalLagError` (Sidekiq retry до 48 год). |
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
| `web3_low` | 8 | Ethereum L1, KlimaDAO, Hadron |
| `low` | 9 (найнижчий) | Аудит, Filecoin, Streamr |

> **Примітка:** Sidekiq `:strict: true` дренує черги послідовно згори-донизу. Числа — порядок дренування, не ваги.

---

### 📡 Uplink — Вхідна Телеметрія

#### `UnpackTelemetryWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `uplink` |
| **Retry** | 3, expires_in: 5 хвилин (Sidekiq Pro) |
| **Тригер** | CoAP daemon (`lib/daemons/`) при отриманні UDP-пакета |
| **Вхід** | `encoded_payload` (Base64), `sender_ip` (String), `gateway_uid` (String, опціонально) |
| **Сервіси** | `TelemetryUnpackerService.call` |
| **Side Effects** | AES-256-CBC дешифрування (Dual-Key), ActionCable raw hex broadcast, Turbo Stream broadcast `telemetry_feed` |

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
| **Сервіси** | `OtaPackagerService.prepare` |
| **Side Effects** | CoAP PUT до Queen (AES-256-CBC). Pacing: `perform_in(0.4.seconds, ...)` між чанками. Turbo Stream `OtaProgressBar`. При `sidekiq_retries_exhausted`: `gateway.update!(state: :faulty)` — запобігає Gateway stuck у `:updating`. |

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

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | `InsightBatchCallbacks#on_success` (після успішного завершення всіх `GenerateClusterInsightWorker` чанків) |
| **Вхід** | `date_string` (String ISO8601, опціонально) |
| **Сервіси** | `contract.check_cluster_health!(target_date)` → `ContractHealthCheckService` |
| **Side Effects** | При healthy → `CeloRewardWorker.perform_async`. При breached → `ContractHealthCheckService` → `BurnCarbonTokensWorker.perform_async`. Оновлює `cluster.health_index`. |

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
| **Side Effects** | `CREATE TABLE IF NOT EXISTS ... PARTITION OF ...` для таблиць `telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`. Перевіряє та створює партиції для поточного та наступного місяця (формат: `{table}_y{YYYY}m{MM}`). DDL-операція ідемпотентна — повторний запуск безпечний. |

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
| **Тригер** | `ClusterHealthCheckWorker` (при healthy кластері) |
| **Вхід** | `cluster_id`, `target_date_string` |
| **Сервіси** | `Celo::CommunityRewardService.new(cluster, date).reward_community!` |

#### `SolanaMicroRewardWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 3 |
| **Тригер** | `OracleCallbacksController#create` (Chainlink DON fulfillment callback, при `oracle_status == "fulfilled"`) |
| **Вхід** | `telemetry_log_id`, `created_at_iso` (опціонально) |
| **Сервіси** | `Solana::MintingService.new(log).mint_micro_reward!` |

#### `PuroEarthPassportWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 5 |
| **Тригер** | `EcosystemHealingWorker` при `biomass_extraction` |
| **Вхід** | `maintenance_record_id` (Integer) |
| **Сервіси** | `PuroEarth::PassportService.new(payload).anchor!` (ABI-encoded canonical hash → SHA-256 → `anchorPassport(treeDid, bytes32)` на D-MRV Registry Polygon) |
| **Side Effects** | `record.update!(biomass_passport_tx_hash: tx_hash)`. `BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)`. |

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

---

## 🔄 12. Карта Ланцюгів Викликів (Call Chains)

### ⚡ Real-time Uplink (per CoAP packet)

```
CoAP UDP (port 5683)
  └─→ UnpackTelemetryWorker [uplink]
        ├─→ TelemetryUnpackerService
        │     ├─→ SilkenNet::Attractor.calculate_z
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
| **Celo RPC** | EVM JSON-RPC | `CELO_RPC_URL` | Celo::CommunityRewardService |
| **IoTeX W3bstream** | HTTPS REST | `iotex_w3bstream_url`, `iotex_api_key` | Iotex::W3bstreamVerificationService |
| **peaq Network** | HTTPS REST | `peaq_node_url`, `peaq_signing_key` | Peaq::DidRegistryService |
| **Chainlink Functions** | On-chain (Polygon) | `CHAINLINK_FUNCTIONS_ROUTER`, `CHAINLINK_SUBSCRIPTION_ID` | Chainlink::OracleDispatchService |
| **dClimate API** | HTTPS REST | `DCLIMATE_BASE_URL` (default: `https://api.dclimate.net`), `DCLIMATE_FIRMS_DATASET` (default: `firms_nrt_global-area_v2`), `Rails.credentials.dclimate.api_key` (Bearer) | Dclimate::VerificationService |
| **Streamr Network** | HTTPS REST | `streamr_stream_id`, `streamr_api_key` | Streamr::BroadcasterService |
| **Filecoin/IPFS** (Pinata) | HTTPS REST | `filecoin_api_key` / `FILECOIN_PINNING_API_URL` | Filecoin::ArchiveService, VerificationService |
| **The Graph** | GraphQL | `the_graph_api_url` | TheGraph::QueryService |
| **Polygon Hadron** | HTTPS REST | `hadron_api_key` / `HADRON_API_URL` | Polygon::HadronComplianceService |
| **Etherisc DIP** | On-chain (Polygon) | `ETHERISC_DIP_CONTRACT_ADDRESS` | Etherisc::ClaimService |
| **Puro.earth D-MRV Registry** | On-chain (Polygon) | `PURO_EARTH_REGISTRY_CONTRACT_ADDRESS`, `ORACLE_PRIVATE_KEY` | PuroEarth::PassportService |
| **KlimaDAO** | On-chain (Polygon) | `KLIMA_RETIREMENT_CONTRACT` | KlimaDao::RetirementService |
| **Toucan Protocol** | On-chain (Polygon) | `TOUCAN_BRIDGE_CONTRACT_ADDRESS` | Toucan::BridgeService |
| **Uniswap V3 Quoter** | On-chain (Polygon) | `POLYGON_RPC_URL` | PriceOracleService |
| **CoAP Gateway** | CoAP/UDP | `gateway.ip_address` (dynamic) | ActuatorCommandWorker, OtaTransmissionWorker |

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
