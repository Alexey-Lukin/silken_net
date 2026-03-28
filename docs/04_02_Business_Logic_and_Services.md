# 04_02: Business Logic and Services (Бізнес-Логіка та Сервіси)

## 🎯 Мета (Objective)

Зафіксувати повний реєстр бізнес-логіки Rails-моноліту як Єдине Джерело Істини (SSOT). Документ описує всі **Service Objects** та **Sidekiq Workers**: їхні вхідні дані, відповідальність та вихідні ефекти. Слугує картою поточних сервісів для запобігання дублювання логіки під час розробки нових фіч і REST API (04_03).

## ✅ Статус (Status)

* **Поточний TRL:** TRL 4 (Повна синхронізація кодової бази з Wiki — Reverse Shaping завершено).
* **Пов'язані модулі:** Схема БД — `04_01_Database_Schema`. Proof of Growth — `05_02_Proof_of_Growth_Pipeline`. Апаратне шифрування — `03_05_Hardware_AES256`.

## 🛑 Блокери (Blockers / Needs Action)

* ~~**`Solana::MintingService`**: Поточна реалізація використовує `simulateTransaction` (Devnet). Потрібна заміна на `sendTransaction` + реальний Ed25519-підпис перед Mainnet.~~ ✅ **Виправлено** у PR #222 (commit 7ac8b01): реалізовано повний бінарний flow `getLatestBlockhash → SPL Transfer Message → Ed25519 sign → sendTransaction`. Тепер Mainnet-ready.
* ~~**`Dclimate::VerificationService#query_dclimate_api`**: Заглушка (`OUTCOMES.sample`). Потрібна реальна HTTP-інтеграція з dClimate API.~~ ✅ **Виправлено** у PR #223 (commit 575ed53): реалізовано реальний HTTP-запит до NASA FIRMS через dClimate API з інтерпретацією FRP/confidence/cloud_cover та `OrbitalLagError` retry-логікою.
* ~~**`PuroEarthPassportWorker`**: `TODO` — заміна stub `tx_hash` на реальний `PuroEarth::PassportService`.~~ ✅ **Виправлено** у PR #224 (commit 669a0dc): реалізовано `PuroEarth::PassportService` — canonical JSON SHA-256 → `anchorPassport(treeDid, bytes32)` на D-MRV Registry смарт-контракті Polygon. `PuroEarthPassportWorker` включає `ApplicationWeb3Worker`, делегує до `PassportService#anchor!`, планує `BlockchainConfirmationWorker`.
* ~~**`InsurancePayoutWorker` + `BlockchainMintingService`**: Метод `insurance_pool_requires_funding?` повертає `true` хардкодом — потрібна on-chain інтеграція з балансом DAO Treasury.~~ ✅ **ВИРІШЕНО** у PR #225 (B-05 Fix): реалізовано cached on-chain oracle через `eth_call balanceOf` на SCC-контракті для адреси `DAO_TREASURY_ADDRESS`. Поріг: `INSURANCE_POOL_THRESHOLD = 100_000 SCC` (`INSURANCE_POOL_THRESHOLD_WEI = 100_000 × 10¹⁸`). Кеш: `Rails.cache.fetch("dao_treasury_needs_funding", expires_in: 15.minutes)` — 4 RPC-запити/годину замість тисяч. Timeout: 10 сек (`Timeout.timeout(10)`). Повертає `Integer` (без Float-похибок). Безпечний фолбек при збої RPC: повертає `true` (краще перефінансувати пул, ніж недофінансувати). Залучає мінімальний BALANCE_OF_ABI (тільки `balanceOf`).
* ~~**`DailyAggregationWorker` `unique_for`**: Поточне значення `6.hours` (з коду "як є"). Рекомендовано збільшити до `24.hours` щоб запобігти повторному запуску за одну добу при ручних тригерах.~~ ✅ **ВИРІШЕНО** у PR #225: `unique_for: 24.hours`
* ~~**`TokenomicsEvaluatorWorker` `unique_for`**: Поточне значення `30.minutes` (з коду). Рекомендовано `60.minutes` для точного захисту щогодинного cron-циклу.~~ ✅ **ВИРІШЕНО** у PR #225: `unique_for: 60.minutes`
* ~~**`EthereumAnchorWorker` `unique_for`**: Поточне значення `1.hour` (з коду). Рекомендовано `7.days` для захисту від дублювання щотижневого anchoring.~~ ✅ **ВИРІШЕНО** у PR #225: `unique_for: 7.days`
* 🔴 **P0 [`GatewayTelemetryWorker`] — Sidekiq job enqueued inside DB transaction:** `check_system_health` викликається всередині `ActiveRecord::Base.transaction`. Якщо транзакція відкочується ПІСЛЯ `AlertNotificationWorker.perform_async(alert.id)`, job вже знаходиться в Redis але `EwsAlert` запис не існує. Воркер знайде `nil` і впаде без будь-якого side effect. Виправлення: використати `after_commit` хук або enqueue job поза транзакцією.
* 🔴 **P0 [`EcosystemHealingWorker`] — Sidekiq job enqueued inside DB transaction:** `PuroEarthPassportWorker.perform_async(record.id)` викликається всередині `ActiveRecord::Base.transaction`. При відкаті транзакції (напр., `alert.resolve!` кидає) — job вже в черзі, але `MaintenanceRecord` може бути в некоректному стані. Виправлення: перенести `perform_async` за межі блоку транзакції.
* 🔴 **P0 [`ContractTerminationService`] — Sidekiq job enqueued inside DB transaction:** `BurnCarbonTokensWorker.perform_async(...)` викликається всередині `@contract.transaction`. При відкаті (DB constraint чи будь-яка помилка після `update!(status: :cancelled)`) контракт повертається до `:active`, але burn-job вже в Redis. `BurnCarbonTokensWorker` перевіряє лише `status_breached?` — для статусу `:active` guard не спрацює, і система виконає повний Slashing на активному контракті. **Фінансова катастрофа.**
* 🟠 **P1 [`ToucanBridgeWorker`] — Відсутній idempotency guard (Double-Spend Risk):** На відміну від `BurnCarbonTokensWorker` (`status_breached?`) та `InsurancePayoutWorker` (`status_triggered?`), `ToucanBridgeWorker` не має жодної перевірки стану на початку `perform`. Якщо `Toucan::BridgeService.call` (on-chain `deposit`) виконається успішно, але `tx.mark_as_sent!` впаде (DB error), Sidekiq перезапустить job і `deposit` відправить ті самі токени **вдруге**. Виправлення: додати `return if tx.status_sent? || tx.status_confirmed?` на початку `perform`.
* 🟠 **P1 [`AlertNotificationWorker`] — OOM при масштабуванні (`.each` замість `.find_each`):** `organization.users.where(role: [:admin, :forester]).each` завантажує всю колекцію в пам'ять. При організації з 10 000+ лісників — одночасне завантаження всіх об'єктів + синхронна постановка 20 000+ jobs в Redis. Виправлення: замінити `.each` на `.find_each`.
* 🟠 **P1 [`IotexVerificationWorker`] — Відсутній rescue для `ArgumentError`:** `Time.iso8601(created_at_iso)` кине `ArgumentError` при некоректному форматі рядка. На відміну від `ChainlinkDispatchWorker` (який явно перехоплює `ArgumentError`), `IotexVerificationWorker` пропускає цей сценарій — перманентна помилка триґерить всі 5 ретраїв даремно. Виправлення: додати `rescue ArgumentError` аналогічно до `ChainlinkDispatchWorker`.
* 🟠 **P1 [`InsightGeneratorService`] — Data-loss вікно при `delete_all` перед регенерацією:** Метод `perform` спочатку виконує `AiInsight.where(target_date: @date, ...).delete_all`, а потім регенерує дані. Якщо процес впаде між `delete_all` і завершенням регенерації (напр., OOM на великому кластері), інсайти за день втрачені безповоротно — а вихідна телеметрія очищується через 7 днів. Виправлення: використовувати `upsert_all` з `on_conflict` або транзакційний swap.
* 🟠 **P1 [`OtaTransmissionWorker`] — Orphaned Gateway state `:updating`:** Воркер використовує `retry: false`. Якщо процес впаде через нетворкову причину (SIGKILL, OOM) до `handle_chunk_failure`, шлюз залишається в стані `:updating` нескінченно — немає ні `sidekiq_retries_exhausted` хендлера, ні timeout-reset. Виправлення: додати `sidekiq_retries_exhausted` що скидає `gateway.update!(state: :faulty)`.
* 🟠 **P1 [`InsurancePayoutWorker`] — Orphaned tx при Etherisc flow (retry blocked by AASM guard):** Якщо `Etherisc::ClaimService.claim!` виконується успішно, але `tx.update!(status: :sent, tx_hash:)` падає, страховка вже переведена в стан `:paid` (через `insurance.pay!` всередині попередньої транзакції). Наступний ретрай натикається на `return unless insurance.status_triggered?` і блокується — `tx` залишається в статусі `:pending` назавжди без `BlockchainConfirmationWorker`.
* 🟠 **P1 [SSOT Gap] — `PartitionMaintenanceWorker` відсутній у Workers Registry:** Воркер існує в `app/workers/partition_maintenance_worker.rb` (відповідальний за автоматичне створення місячних партицій `telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`) але жодного разу не згаданий у реєстрі воркерів розділу 11.
* 🟠 **P1 [SSOT Gap] — Секція "Default — Агрегація та Токеноміка" некоректно групує `DailyAggregationWorker`:** `DailyAggregationWorker` насправді використовує чергу `low` (пріоритет 1), а не `default` (пріоритет 5). Секція-заголовок вводить в оману при визначенні пріоритетів.

---

## 🏗️ 1. Архітектурні Засади

### Базові класи

| Компонент | Файл | Призначення |
|-----------|------|-------------|
| `ApplicationService` | `app/services/application_service.rb` | Базовий клас для всіх сервісів. Надає `.call(...)` → `new(...).perform` template. |
| `ApplicationWeb3Worker` | `app/workers/application_web3_worker.rb` | Базовий **модуль** (не клас) для всіх блокчейн-воркерів. Включає: RPC rate limiter (50 rps), уніфіковану обробку помилок (HTTPX/Net timeouts), partition-pruned TelemetryLog lookup. |
| `CoapEncryption` | `app/workers/concerns/coap_encryption.rb` | Concern для downlink-воркерів. AES-256-CBC шифрування з випадковим IV, нульовий padding. Формат: `[IV:16][Ciphertext:N×16]`. |

### Web3 Utility Layer

| Утиліта | Призначення |
|---------|-------------|
| `Web3::HttpClient` | Централізований HTTP-клієнт (HTTPX) для всіх зовнішніх API. Thread-safe persistent sessions, таймаути per-service, lazy JSON parsing. |
| `Web3::RpcConnectionPool` | Thread-safe кешування `Eth::Client` інстансів per-thread. Зменшує TCP/TLS handshakes у Sidekiq-потоках. |
| `Web3::WeiConverter` | `BigDecimal`-based конвертація `amount → wei` (ERC-20). Запобігає Float-похибкам у фінансових операціях. |

---

## 🌡️ 2. Домен: Телеметрія (Telemetry)

### `TelemetryUnpackerService`

| | |
|---|---|
| **Файл** | `app/services/telemetry_unpacker_service.rb` |
| **Вхід** | `binary_batch` (сирий бінарний батч), `gateway_id` (Integer) |
| **Що робить** | Розрізає бінарний батч на 21-байтні чанки (`[DID:4][RSSI:1][Payload:16]`). Калібрує сенсорні дані, обчислює Z-значення атрактора Лоренца, записує `TelemetryLog`. Детектує `firmware_mismatch`. Маршрутизує "нульовий" пакет Королеви до `GatewayTelemetryWorker`. |
| **Зовнішні виклики** | `SilkenNet::Attractor.calculate_z`, `AlertDispatchService.analyze_and_trigger!`, `IotexVerificationWorker.perform_async`, `StreamrBroadcastWorker.perform_async`, `GatewayTelemetryWorker.perform_async` |
| **Вихід / Side Effects** | Створює `TelemetryLog` записи. Оновлює `tree.latest_voltage_mv`, `tree.health_streak`. Нараховує `wallet.balance` (growth_points). Позначає `tree.firmware_update_status = :fw_pending` при mismatch. |

### `AlertDispatchService`

| | |
|---|---|
| **Файл** | `app/services/alert_dispatch_service.rb` |
| **Вхід** | `TelemetryLog` (через `.analyze_and_trigger!`) або `Tree` + `message` (через `.create_fraud_alert!`) |
| **Що робить** | Аналізує телеметрію по 5 напрямках: вандалізм (tamper), пожежа/температура, сейсміка, посуха/атрактор, шкідники. Адаптивні пороги (з кластера/породи дерева). Redis-фільтр тиші (5 хвилин per `tree_id:alert_type`). |
| **Зовнішні виклики** | `EmergencyResponseService.call`, `AlertNotificationWorker.perform_async` |
| **Вихід** | Створює `EwsAlert`. Інвалідує `oracle_expected_yield_24h` кеш при critical severity. Повертає `nil` (всі дії через side effects). |

---

## 🧠 3. Домен: AI та Аналітика (AI & Analytics)

### `InsightGeneratorService`

| | |
|---|---|
| **Файл** | `app/services/insight_generator_service.rb` |
| **Вхід** | `date` (Date, default: вчора UTC) |
| **Що робить** | Добова агрегація телеметрії → `AiInsight`. Включає: AI Fraud Guard (відхилення sap_flow/temp від кластерного базлайну > 30%), ML-модель (`silken_forest.marshal` + SHA256 integrity check) або евристика stress_index. Денормалізує `tree.latest_stress_index`. Очищує `TelemetryLog` старше 7 днів. |
| **Зовнішні виклики** | `AlertDispatchService.create_fraud_alert!` |
| **Вихід** | `{ processed_count: Integer, date: Date }`. Створює `AiInsight` per tree та per cluster. |

### `SilkenNet::Attractor`

| | |
|---|---|
| **Файл** | `app/services/silken_net/attractor.rb` |
| **Вхід** | `seed` (Integer/DID), `temp` (Float °C), `acoustic` (Integer events) |
| **Що робить** | Обчислює Z-значення атрактора Лоренца. σ=10, ρ=28, β=8/3. 250 ітерацій, timestep=0.01. `BigDecimal(18)` для крос-платформної детермінованості. Clamp: σ∈[5,30], ρ∈[10,50]. |
| **Вихід** | `calculate_z → Float` (rounded 4). `homeostatic? → Boolean`. `generate_trajectory → Array<Float>` (плаский масив x,y,z × 250 для Three.js). |

### `SilkenNet::GeoUtils`

| | |
|---|---|
| **Файл** | `app/services/silken_net/geo_utils.rb` |
| **Вхід** | `lat1, lng1, lat2, lng2` (Float, WGS-84) |
| **Що робить** | Haversine distance calculation між двома GPS-точками. |
| **Вихід** | `haversine_distance_m → Float` (метри). |

---

## 🔗 4. Домен: Блокчейн — Polygon (Primary Chain)

### `BlockchainMintingService`

| | |
|---|---|
| **Файл** | `app/services/blockchain_minting_service.rb` |
| **Вхід** | `blockchain_transaction_ids` (Array\<Integer>), `telemetry_log:` (опціонально, для oracle-driven flow) |
| **Що робить** | Пакетна емісія SCC/SFC на Polygon через `mint` або `batchMint`. Guard clauses: `verified_by_iotex?`, `oracle_status == "fulfilled"`, `hadron_kyc_status == "approved"`. Dynamic Tax 2% при carbon_coin + недофінансований страховий пул (→ DAO Treasury). `Kredis.lock` проти race conditions. `transact` (fire-and-forget). Prometheus metric `SCC_MINTED_TOTAL`. **[B-05]** `insurance_pool_requires_funding?` — cached on-chain `balanceOf` oracle: `INSURANCE_POOL_THRESHOLD = 100_000 SCC`; кеш 15 хв (`dao_treasury_needs_funding`); timeout 10 сек; failsafe → `true` при збої RPC. |
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
| **Що робить** | Rollback при вичерпанні всіх Sidekiq-ретраїв у `MintCarbonCoinWorker`. Розблоковує `locked_balance` гаманця. Маркує `BlockchainTransaction.status = :failed`. |
| **Вихід** | `nil`. Side effect: `wallet.release_locked_funds!`, `tx.update!(status: :failed)`, Turbo broadcast. |

### `PuroEarth::PassportService`

| | |
|---|---|
| **Файл** | `app/services/puro_earth/passport_service.rb` |
| **Вхід** | `payload` (Hash: `tree_did`, `biomass_yield_kg`, `extraction_date`, `gps_coordinates`, `lifetime_telemetry_hash`) |
| **Що робить** | **[MAINNET READY]** Anchors a cryptographic proof of a Biomass Passport onto Polygon for Puro.earth D-MRV (Digital Measurement, Reporting and Verification) / CORC generation. 1) Serializes payload to canonical JSON (deep-sorted keys — `deep_sort_keys` — for deterministic ordering regardless of Hash insertion order). 2) Computes SHA-256 digest as tamper-proof fingerprint. 3) Calls `anchorPassport(treeDid, bytes32(payloadHash))` on the D-MRV Registry smart contract on Polygon via `Web3::RpcConnectionPool` + `Eth::Contract`. Signing via `ORACLE_PRIVATE_KEY`. Follows `Ethereum::StateAnchorService` (bytes32 anchoring) and `Etherisc::ClaimService` (Polygon transact fire-and-forget) patterns. |
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
| **Що робить** | Відправляє телеметрію до IoTeX W3bstream для генерації ZK-proof. Payload: `device_id`, `peaq_did`, `hardware_signature` (SHA256), `chaotic_data` (z_value, temp, acoustic, voltage, bio_status). |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `iotex_w3bstream_url/verify` |
| **Вихід** | `zk_proof_ref` (String — `proof_id` або `receipt_id`). Raises `VerificationError` при помилці. |

### `Peaq::DidRegistryService`

| | |
|---|---|
| **Файл** | `app/services/peaq/did_registry_service.rb` |
| **Вхід** | `tree` (Tree AR instance) |
| **Що робить** | Генерує peaq DID: `did:peaq:0x{SHA256[tree.did:tree.id:created_at][0:40]}`. Підписує DID-документ Ed25519 (якщо `peaq_signing_key` налаштовано). Відправляє реєстрацію до peaq node. |
| **Зовнішні виклики** | `Ed25519Crypto::SigningService.sign`, `Web3::HttpClient.post` → `peaq_node_url/did/register` |
| **Вихід** | `did_string` (String, напр. `did:peaq:0x8a9b...`). Raises `RegistrationError`. |

### `Chainlink::OracleDispatchService`

| | |
|---|---|
| **Файл** | `app/services/chainlink/oracle_dispatch_service.rb` |
| **Вхід** | `telemetry_log` (TelemetryLog AR instance) |
| **Що робить** | Відправляє верифіковану телеметрію до Chainlink Functions DON. Guard clause: `verified_by_iotex? == true`. Payload: `peaq_did`, `lorenz_state` (σ,ρ,β,z), `zk_proof_ref`, `tree_did`, `created_at` (partition key). Stub режим, якщо `CHAINLINK_FUNCTIONS_ROUTER` не налаштовано. |
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
| **Що робить** | USDC мікро-винагороди на Solana. **[MAINNET READY]** Guard: `verified_by_iotex?` + `oracle_status == "fulfilled"`. Розраховує `reward_lamports = 10_000 + (growth_points × 100)`, де `growth_points` — 6-бітне поле телеметрії (0–63). Діапазон: 10_000–16_300 lamports (0.01–0.0163 USDC). 4-крокова транзакція: `getLatestBlockhash` → бінарний SPL Token Transfer Message (compact-u16 + account keys + Ed25519-header) → Ed25519 підпис через `Ed25519Crypto::SigningService` (hex-keypair з `SOLANA_WALLET_KEYPAIR`) → `sendTransaction` (base64). ATA отримувача резолюється динамічно через `getTokenAccountsByOwner` RPC. `SOLANA_WALLET_KEYPAIR` (mandatory), `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS` — обов'язкові ENV. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → Solana RPC JSON API (`getLatestBlockhash`, `getTokenAccountsByOwner`, `sendTransaction`) |
| **Вихід** | `tx_signature` (String). Створює `BlockchainTransaction` зі статусом `:sent` (очікує `BlockchainConfirmationWorker`). |

### `Celo::CommunityRewardService`

| | |
|---|---|
| **Файл** | `app/services/celo/community_reward_service.rb` |
| **Вхід** | `cluster` (Cluster AR instance), `target_date` (Date) |
| **Що робить** | ReFi incentive: відправляє 5 cUSD організації якщо `stress_index <= 0.2` та немає fraud. ERC-20 `transfer` на Celo. `Kredis.lock` проти race conditions. |
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
| **Що робить** | **KYC**: перевіряє `hadron_kyc_status` через Polygon Hadron Identity API. **RWA**: реєструє лісову ділянку як Real World Asset (ERC-3643). Simulation mode якщо `HADRON_API_KEY` відсутній. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → `HADRON_API_URL/identity/kyc/verify` або `HADRON_API_URL/assets/rwa/register` |
| **Вихід** | `verify_investor! → "approved"/"rejected"`. `register_asset! → asset_id (String)`. |

### `Ethereum::StateAnchorService`

| | |
|---|---|
| **Файл** | `app/services/ethereum/state_anchor_service.rb` |
| **Вхід** | — (no args) |
| **Що робить** | Тижневий SHA-256 state root → Ethereum L1. `root = SHA256("#{total_scc}|#{latest_chain_hash}|#{timestamp}")`. `storeStateRoot(bytes32)` на смарт-контракті. 1 запис на тиждень (gas-efficient). |
| **Зовнішні виклики** | Ethereum Mainnet RPC (`ALCHEMY_ETHEREUM_RPC_URL`), `StateRootAnchor` contract |
| **Вихід** | `tx_hash` (String). Raises при timeout/connection error. |

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
| **Вхід** | `blockchain_transaction_id` (Integer) |
| **Що робить** | SCC → TCO2 bridge через Toucan Protocol на Polygon. `deposit(scc_address, amount_wei)` на ToucanCarbonBridge контракті. |
| **Зовнішні виклики** | Polygon RPC → `ToucanCarbonBridge.deposit` |
| **Вихід** | `tx_hash` (String). |

---

## ⚙️ 11. Реєстр Воркерів (Workers Registry)

### Пріоритети черг (9 рівнів, строге дотримання)

| Черга | Пріоритет | Призначення |
|-------|-----------|-------------|
| `uplink` | 9 (HIGHEST) | Вхідна телеметрія |
| `alerts` | 8 | EWS тривоги, супутникова верифікація |
| `critical` | 7 | Slashing, страхові виплати, реанімація екосистеми |
| `downlink` | 6 | OTA прошивки, команди актуаторів |
| `default` | 5 | Агрегація, перевірка контрактів, токеноміка |
| `web3_critical` | 4 | Blockchain confirmation, мінтинг, IoTeX, Chainlink |
| `web3` | 3 | peaq DID, Celo, Solana, Puro.earth |
| `web3_low` | 2 | Ethereum L1, KlimaDAO, Hadron |
| `low` | 1 | Аудит, Filecoin, Streamr |

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
| **Side Effects** | Створює `GatewayTelemetryLog`. Перевіряє `critical_fault?` → `AlertNotificationWorker.perform_async`. |

---

### 📢 Alerts — Тривоги та Верифікація

#### `AlertNotificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `alerts` |
| **Retry** | 5, expires_in: 5 хвилин |
| **Тригер** | `AlertDispatchService` (через `create_and_dispatch_alert!` та `create_fraud_alert!`), `GatewayTelemetryWorker` (при `critical_fault?`) |
| **Вхід** | `ews_alert_id` (Integer) |
| **Сервіси** | — |
| **Side Effects** | ActionCable broadcast до dashboard. Знаходить stakeholders організації → `SingleNotificationWorker.perform_async` per (user, channel). |

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
| **Side Effects** | CoAP PUT до Queen gateway. `actuator.mark_active!`, `command.acknowledge!`. Планує `ResetActuatorStateWorker.perform_in(duration_seconds, ...)`. |

#### `OtaTransmissionWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `downlink` |
| **Retry** | false (самостійна retry-логіка) |
| **Тригер** | Ручний запуск через API або після OTA mismatch detection |
| **Вхід** | `queen_uid`, `firmware_type` (`mruby`/`firmware`/`tinyml`/`weights`), `record_id`, `chunk_index` (default 0), `retry_count` (default 0) |
| **Сервіси** | `OtaPackagerService.prepare` |
| **Side Effects** | CoAP PUT до Queen (AES-256-CBC). Pacing: `perform_in(0.4.seconds, ...)` між чанками. Turbo Stream `OtaProgressBar`. |

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

> ⚠️ **SSOT Note:** `DailyAggregationWorker` нижче використовує чергу `low` (пріоритет 1), а не `default` (пріоритет 5). Він залишений у цій секції для збереження логічної групи "добовий цикл", але черга вказана коректно у відповідній таблиці.

#### `DailyAggregationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3, unique_for: 24 години |
| **Тригер** | Sidekiq cron: щодня 01:00 UTC |
| **Вхід** | `date_string` (String ISO8601, опціонально — default вчора UTC) |
| **Сервіси** | `InsightGeneratorService.call(target_date)` |
| **Side Effects** | → `ClusterHealthCheckWorker.perform_async(date)`. При відсутності даних: `EwsAlert` GLOBAL_BLACKOUT для кожного активного кластера. |

#### `ClusterHealthCheckWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3 |
| **Тригер** | `DailyAggregationWorker` (після успішної агрегації) |
| **Вхід** | `date_string` (String ISO8601, опціонально) |
| **Сервіси** | `contract.check_cluster_health!(target_date)` → `ContractHealthCheckService` |
| **Side Effects** | При healthy → `CeloRewardWorker.perform_async`. При breached → `BurnCarbonTokensWorker.perform_async`. Оновлює `cluster.health_index`. |

#### `TokenomicsEvaluatorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `default` |
| **Retry** | 3, unique_for: 60 хвилин |
| **Тригер** | Sidekiq cron: щогодини |
| **Вхід** | — |
| **Сервіси** | — |
| **Side Effects** | `Sidekiq::Batch` → `EvaluateTreeBatchWorker` по 1000 гаманців. Callback `TokenomicsBatchCallbacks#on_success`. |

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
| **Side Effects** | `eth_get_transaction_receipt` (Polygon RPC). При `0x1`: `tx.confirm!`. При revert: `tx.fail!`. Retry при pending (ще в мемпулі). |

#### `MintCarbonCoinWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
| **Тригер** | `TelemetryUnpackerService` (через Chainlink callback) або `TokenomicsEvaluatorWorker` (cron fallback) |
| **Вхід** | `telemetry_log_id` (опціонально), `created_at_iso` (опціонально) |
| **Сервіси** | `BlockchainMintingService.call_batch` або `.call` |
| **Side Effects** | При вичерпанні ретраїв: `MintingRollbackService.call` (розблоковує `locked_balance`). |

#### `IotexVerificationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
| **Тригер** | `TelemetryUnpackerService` (після `commit_telemetry`) |
| **Вхід** | `telemetry_log_id`, `created_at_iso` (ISO8601 6 decimals) |
| **Сервіси** | `Iotex::W3bstreamVerificationService.new(log).verify!` |
| **Side Effects** | `log.update!(verified_by_iotex: true, zk_proof_ref:)`. → `ChainlinkDispatchWorker.perform_async`. |

#### `ChainlinkDispatchWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_critical` |
| **Retry** | 5 |
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
| **Вхід** | `blockchain_transaction_id` (Integer) |
| **Сервіси** | `Toucan::BridgeService.call(blockchain_transaction_id)` |
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
| **Тригер** | `TelemetryUnpackerService` (паралельно з IoTeX) |
| **Вхід** | `telemetry_log_id`, `created_at_iso` (опціонально) |
| **Сервіси** | `Solana::MintingService.new(log).mint_micro_reward!` |

#### `PuroEarthPassportWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3` |
| **Retry** | 5 |
| **Тригер** | `EcosystemHealingWorker` при `biomass_extraction` |
| **Вхід** | `maintenance_record_id` (Integer) |
| **Сервіси** | `PuroEarth::PassportService.new(payload).anchor!` (canonical JSON SHA-256 → `anchorPassport(treeDid, bytes32)` на D-MRV Registry Polygon) |
| **Side Effects** | `record.update!(biomass_passport_tx_hash: tx_hash)`. `BlockchainConfirmationWorker.perform_in(30.seconds, tx_hash)`. |

---

### 💤 Web3 Low — Не Критичний Блокчейн

#### `EthereumAnchorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3, unique_for: 7 днів |
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
              └─→ AlertNotificationWorker [alerts] (при critical_fault)
```

### ⏰ Щоденний Цикл (01:00 UTC)

```
Sidekiq Cron 01:00 UTC
  └─→ DailyAggregationWorker [low]
        └─→ InsightGeneratorService
              ├─→ AlertDispatchService.create_fraud_alert! (при fraud)
              └─→ ClusterHealthCheckWorker [default]
                    ├─→ ContractHealthCheckService
                    ├─→ CeloRewardWorker [web3] (якщо healthy)
                    │     └─→ Celo::CommunityRewardService
                    └─→ BurnCarbonTokensWorker [critical] (якщо breached)
                          └─→ BlockchainBurningService
                                └─→ BlockchainConfirmationWorker [web3_critical]
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

> **Версія документа:** v1.1 · 2026-03-28 · Gaia 2.0 — Cycle 2 (Security & Reliability Audit).
> **Метод:** Пасивне сканування кодової бази "як є" (`app/services/` + `app/workers/`). Жодного рефакторингу.
> **Покриття:** 35 service objects (35 файлів), 31 Sidekiq workers + 2 concerns (base infrastructure).

---

## 🔴 14. Аудит Надійності (Security & Reliability Audit)

> **Методологія:** Глибокий параноїдальний аудит 33 воркерів та 35 сервісів за 5 векторами: Network-in-Transaction Trap, Idempotency Failures, Memory Black Holes, SSOT vs Reality, Orphaned States.
> **Дата:** 2026-03-28 · Principal Backend Architect audit.

---

### 🔴 P0 Blockers — Критичні Загрози

#### P0-1 · `GatewayTelemetryWorker` — Job enqueued inside DB transaction

| | |
|---|---|
| **Файл** | `app/workers/gateway_telemetry_worker.rb`, рядки 26–44 |
| **Вектор** | Network-in-Transaction Trap (variant: Sidekiq enqueue inside transaction) |
| **Опис** | Метод `check_system_health(gateway, log)` викликається **всередині** `ActiveRecord::Base.transaction`. Якщо всередині цього блоку будь-який рядок після `AlertNotificationWorker.perform_async(alert.id)` кине помилку і транзакція відкотиться — `EwsAlert` запис не збережеться в БД, але job вже знаходиться в Redis. Воркер запуститься, викличе `EwsAlert.find_by(id: ews_alert_id)` → отримає `nil` → поверне `nil` без жодного повідомлення патрульним. Фізична тривога (пожежа, посуха) може бути проігнорована. |
| **Код (спрощено)** | `ActiveRecord::Base.transaction { log = create!(...)  gateway.mark_seen!(...)  check_system_health(gateway, log) }` → `check_system_health` → `EwsAlert.create!` → `AlertNotificationWorker.perform_async(alert.id)` ← **тут** |
| **Виправлення** | Перенести `AlertNotificationWorker.perform_async` поза транзакцію (збирати alert.id після `transaction` блоку та enqueue після commit). Або використати `Rails.after_commit_action { AlertNotificationWorker.perform_async(alert.id) }`. |

#### P0-2 · `EcosystemHealingWorker` — Job enqueued inside DB transaction

| | |
|---|---|
| **Файл** | `app/workers/ecosystem_healing_worker.rb`, рядки 17–21 |
| **Вектор** | Network-in-Transaction Trap (variant: Sidekiq enqueue inside transaction) |
| **Опис** | `PuroEarthPassportWorker.perform_async(record.id)` викликається **всередині** `ActiveRecord::Base.transaction`. Якщо `alert.resolve!(...)` (наступний рядок у тому ж transaction блоці) кине виключення — транзакція відкочується, `tree.declare_deceased!` скасовується, але `PuroEarthPassportWorker` вже в Redis. Воркер запускається, знаходить дерево в живому стані, anchors Biomass Passport на мертве (по факту живе) дерево — фінансове підтвердження смерті дерева для Puro.earth буде хибним. |
| **Код (спрощено)** | `ActiveRecord::Base.transaction { target.declare_deceased!  PuroEarthPassportWorker.perform_async(record.id) ← тут  alert.resolve!(...) }` |
| **Виправлення** | Enqueue `PuroEarthPassportWorker` після transaction блоку. Патерн: `passport_record_id = nil; transaction { ...; passport_record_id = record.id }; PuroEarthPassportWorker.perform_async(passport_record_id) if passport_record_id`. |

#### P0-3 · `ContractTerminationService` — BurnWorker enqueued inside DB transaction

| | |
|---|---|
| **Файл** | `app/services/contract_termination_service.rb`, рядки 22–27 |
| **Вектор** | Network-in-Transaction Trap + Idempotency Failure (фінансова) |
| **Опис** | `BurnCarbonTokensWorker.perform_async(...)` викликається **всередині** `@contract.transaction`. Якщо після `update!(status: :cancelled)` і `perform_async` транзакція відкочується (будь-яка причина) — контракт повертається до статусу `:active`, але burn-job вже в Redis. `BurnCarbonTokensWorker` перевіряє лише `return if naas_contract.status_breached?`. Для статусу `:active` цей guard **не спрацює** — виконається повний `BlockchainBurningService` на активному контракті. Інвестор втратить токени за контрактом, який фактично не розірвано. |
| **Важкість** | **Фінансова катастрофа** (незворотнє on-chain спалювання токенів). |
| **Виправлення** | Перенести `BurnCarbonTokensWorker.perform_async` поза транзакцію. Або оновити guard у `BurnCarbonTokensWorker` на `return unless naas_contract.status_breached? || naas_contract.status_cancelled?`. |

---

### 🟠 P1 Warnings — Ризики та Розсинхронізація

#### P1-1 · `ToucanBridgeWorker` — Відсутній idempotency guard (Double-Bridge Risk)

| | |
|---|---|
| **Файл** | `app/workers/toucan_bridge_worker.rb` |
| **Вектор** | Idempotency Failure — подвійна витрата |
| **Опис** | На відміну від `BurnCarbonTokensWorker` (guard: `status_breached?`), `InsurancePayoutWorker` (guard: `status_triggered?`), `IotexVerificationWorker` (guard: `verified_by_iotex?`) — `ToucanBridgeWorker` не має жодної перевірки стану на початку `perform`. Сценарій: `Toucan::BridgeService.call` (on-chain `deposit`) виконується успішно → `tx.mark_as_sent!(tx_hash)` падає (DB conflict/constraint) → Sidekiq requeue → повторний виклик `Toucan::BridgeService.call` → **ті самі токени bridged вдруге**. |
| **Виправлення** | Додати на початку `perform`: `return if tx.status_sent? \|\| tx.status_confirmed?`. Аналогічно до `IotexVerificationWorker`: `return if log.verified_by_iotex?`. |

#### P1-2 · `AlertNotificationWorker` — OOM при `stakeholders.each` (Missing `find_each`)

| | |
|---|---|
| **Файл** | `app/workers/alert_notification_worker.rb`, метод `notify_stakeholders` |
| **Вектор** | Memory Black Hole |
| **Опис** | `organization.users.where(role: [:admin, :forester]).each` завантажує **всю колекцію** User об'єктів у пам'ять одночасно. Для великої організації (10 000+ лісників при планетарному масштабі) — одночасне завантаження AR об'єктів + синхронна постановка 20 000+ Sidekiq jobs. При 100 000 лісників (реалістично при мільярдах дерев) — OOM kill Sidekiq-воркера. |
| **Виправлення** | Замінити `.each` на `.find_each(batch_size: 500)`. |

#### P1-3 · `IotexVerificationWorker` — Відсутній `rescue ArgumentError`

| | |
|---|---|
| **Файл** | `app/workers/iotex_verification_worker.rb`, рядок 5 |
| **Вектор** | SSOT vs Reality (розбіжність з `ChainlinkDispatchWorker` паттерном) |
| **Опис** | `TelemetryLog.find_by(id: ..., created_at: Time.iso8601(created_at_iso))` — якщо `created_at_iso` некоректний (напр., `nil`, пошкоджений Redis payload), `Time.iso8601` кине `ArgumentError`. На відміну від `ChainlinkDispatchWorker` (який явно `rescue ArgumentError => e`) — `IotexVerificationWorker` пропускає цей сценарій. Перманентна помилка спожене всі 5 ретраїв даремно, блокуючи `web3_critical` слоти. |
| **Виправлення** | Додати `rescue ArgumentError => e` аналогічно до `ChainlinkDispatchWorker#find_log`. |

#### P1-4 · `InsightGeneratorService` — Data-loss вікно при `delete_all` → крах → втрата дня

| | |
|---|---|
| **Файл** | `app/services/insight_generator_service.rb`, рядок ≈21 |
| **Вектор** | Orphaned State (втрата даних) |
| **Опис** | `AiInsight.where(target_date: @date, insight_type: :daily_health_summary).delete_all` виконується **до** регенерації. При краші процесу після `delete_all` (OOM, SIGKILL при великому кластері) — денні інсайти втрачені безповоротно. `TelemetryLog` очищуються через 7 днів, тобто якщо це відбудеться на 7й день — повторна генерація неможлива. Поточна "ідемпотентність" є деструктивно-першою (delete-then-recreate замість upsert). |
| **Виправлення** | Використати `upsert_all` з `unique_by:` або зберігати нові записи поряд зі старими (marked `draft`), а потім атомарно замінювати. |

#### P1-5 · `OtaTransmissionWorker` — Orphaned Gateway state `:updating`

| | |
|---|---|
| **Файл** | `app/workers/ota_transmission_worker.rb` |
| **Вектор** | Orphaned State |
| **Опис** | Воркер використовує `retry: false`. Якщо процес впаде через нетворкову причину (SIGKILL, OOM) після `gateway.update!(state: :updating)` але до `handle_chunk_failure` — шлюз залишається у стані `:updating` нескінченно. Немає `sidekiq_retries_exhausted` хендлера (оскільки `retry: false`), немає timeout-based reset. Королева відмовлятиме всім наступним ActuatorCommand (`if gateway.updating? raise "Gateway Busy"`). |
| **Виправлення** | Додати `ensure` блок у `perform` що скидає `gateway.update!(state: :faulty)` при будь-якому некерованому виході. Або: встановити `retry: 3` + `sidekiq_retries_exhausted { Gateway.find_by(uid: queen_uid)&.update!(state: :faulty) }`. |

#### P1-6 · `InsurancePayoutWorker` — Orphaned `tx` при Etherisc flow (retry blocked by AASM)

| | |
|---|---|
| **Файл** | `app/workers/insurance_payout_worker.rb`, рядки після транзакції |
| **Вектор** | Orphaned State (зависання AASM) |
| **Опис** | Якщо `Etherisc::ClaimService.claim!` виконується успішно (on-chain `triggerClaim`), але наступний `tx.update!(status: :sent, tx_hash: etherisc_tx_hash)` падає (DB error) — Sidekiq requeue. На retry: `return unless insurance.status_triggered?` → guard блокує, бо `insurance.pay!` вже виконалось у першій спробі (AASM: `triggered → paid`). `BlockchainTransaction` залишається у статусі `:pending` назавжди без `BlockchainConfirmationWorker`. Etherisc DIP виплата on-chain відбулась, але DB не знає про неї. |
| **Виправлення** | Перевіряти стан `tx` перед guard: `return if tx&.status_sent? || tx&.status_confirmed?`. Або зберігати `tx_hash` в `insurance` безпосередньо для reconciliation. |

#### P1-7 · `TelemetryUnpackerService#commit_telemetry` — Jobs enqueued inside transaction

| | |
|---|---|
| **Файл** | `app/services/telemetry_unpacker_service.rb`, метод `commit_telemetry` |
| **Вектор** | Network-in-Transaction Trap (variant: phantom Sidekiq jobs) |
| **Опис** | `IotexVerificationWorker.perform_async(...)` та `StreamrBroadcastWorker.perform_async(...)` ставляться в чергу **всередині** `ActiveRecord::Base.transaction`. Якщо транзакція відкотиться (напр., `update_health_streak!` або `check_firmware_mismatch!` кинуть) — обидва jobs вже в Redis, але `TelemetryLog` запис відсутній. `IotexVerificationWorker` знайде `nil` (5 ретраїв даремно на `web3_critical`). Менш критично ніж P0 (немає фінансового ризику), але засмічує `web3_critical` чергу. |
| **Виправлення** | Аналогічно до P0: перенести `perform_async` виклики поза `transaction` блок — зберігати `record.id_value` та `record.created_at.iso8601(6)` і enqueue після commit. |

---

### 🔵 Architectural Suggestions

#### A-1 · Transactional Outbox Pattern для всіх P0 випадків

Системна проблема P0-1, P0-2, P0-3, P1-7 — один і той самий антипаттерн: Sidekiq job enqueued inside DB transaction. Рекомендоване рішення:

```ruby
# Rails 8 after_create_commit / after_commit
class EwsAlert < ApplicationRecord
  after_create_commit -> { AlertNotificationWorker.perform_async(id) }
end

# Або: накопичувати jobs в масиві, enqueue після transaction
jobs_to_enqueue = []
ActiveRecord::Base.transaction do
  alert = EwsAlert.create!(...)
  jobs_to_enqueue << -> { AlertNotificationWorker.perform_async(alert.id) }
end
jobs_to_enqueue.each(&:call)
```

Sidekiq Pro 7+ також підтримує `Sidekiq::Middleware::CurrentAttributes` + транзакційний outbox через `Kredis::List` — але це вимагає Pro ліцензії.

#### A-2 · `PartitionMaintenanceWorker` — рекомендовано запускати ДО `DailyAggregationWorker`

Поточний cron (якщо є) не специфікований у документі. Якщо `PartitionMaintenanceWorker` не запуститься до 01:00 UTC (час `DailyAggregationWorker`), вставка телеметрії на початку нового місяця падатиме з `no partition of relation` PostgreSQL помилкою. Рекомендовано: `00:30 UTC` щодня.

#### A-3 · `InsightGeneratorService` — розглянути Sidekiq Batch для покластерної обробки

При 10M+ дерев `InsightGeneratorService#perform` є монолітним синхронним процесом. Аналогічно до `TokenomicsEvaluatorWorker` (де використовується `Sidekiq::Batch` → `EvaluateTreeBatchWorker`), `InsightGeneratorService` варто розбити на `InsightGeneratorOrchestrator` (Batch) + `GenerateClusterInsightWorker` (child по 100 кластерів). Це усуне OOM-ризик при великому датасеті і надасть Sidekiq Pro Batch progress tracking.

#### A-4 · `AlertNotificationWorker` — розглянути Sidekiq Pro Bulk для масового enqueue

Замість синхронного циклу `stakeholders.find_each { |u| SingleNotificationWorker.perform_async(...) }` використати `Sidekiq::Client.push_bulk` для одного Redis `LPUSH` з усіма jobs:

```ruby
jobs = []
organization.users.where(role: [:admin, :forester]).find_each do |user|
  jobs << { "class" => SingleNotificationWorker, "args" => [user.id, alert.id, "push"] }
  jobs << { "class" => SingleNotificationWorker, "args" => [user.id, alert.id, "sms"] } if alert.severity_critical?
end
Sidekiq::Client.push_bulk("class" => SingleNotificationWorker.to_s, "args" => jobs.map { _1["args"] })
```

Це зменшує кількість Redis round-trips з N до 1 при масовому розсиланні.

---

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
