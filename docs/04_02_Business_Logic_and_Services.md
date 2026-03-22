# 04_02: Business Logic and Services (Бізнес-Логіка та Сервіси)

## 🎯 Мета (Objective)

Зафіксувати повний реєстр бізнес-логіки Rails-моноліту як Єдине Джерело Істини (SSOT). Документ описує всі **Service Objects** та **Sidekiq Workers**: їхні вхідні дані, відповідальність та вихідні ефекти. Слугує картою поточних сервісів для запобігання дублювання логіки під час розробки нових фіч і REST API (04_03).

## ✅ Статус (Status)

* **Поточний TRL:** TRL 4 (Повна синхронізація кодової бази з Wiki — Reverse Shaping завершено).
* **Пов'язані модулі:** Схема БД — `04_01_Database_Schema`. Proof of Growth — `05_02_Proof_of_Growth_Pipeline`. Апаратне шифрування — `03_05_Hardware_AES256`.

## 🛑 Блокери (Blockers / Needs Action)

* **`Solana::MintingService`**: Поточна реалізація використовує `simulateTransaction` (Devnet). Потрібна заміна на `sendTransaction` + реальний Ed25519-підпис перед Mainnet.
* **`Dclimate::VerificationService#query_dclimate_api`**: Заглушка (`OUTCOMES.sample`). Потрібна реальна HTTP-інтеграція з dClimate API.
* **`PuroEarthPassportWorker`**: `TODO` — заміна stub `tx_hash` на реальний `PuroEarth::PassportService`.
* **`InsurancePayoutWorker` + `BlockchainMintingService`**: Метод `insurance_pool_requires_funding?` повертає `true` хардкодом — потрібна on-chain інтеграція з балансом DAO Treasury.
* **`DailyAggregationWorker` `unique_for`**: Поточне значення `6.hours` (з коду "як є"). Рекомендовано збільшити до `24.hours` щоб запобігти повторному запуску за одну добу при ручних тригерах.
* **`TokenomicsEvaluatorWorker` `unique_for`**: Поточне значення `30.minutes` (з коду). Рекомендовано `60.minutes` для точного захисту щогодинного cron-циклу.
* **`EthereumAnchorWorker` `unique_for`**: Поточне значення `1.hour` (з коду). Рекомендовано `7.days` для захисту від дублювання щотижневого anchoring.

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
| **Що робить** | Пакетна емісія SCC/SFC на Polygon через `mint` або `batchMint`. Guard clauses: `verified_by_iotex?`, `oracle_status == "fulfilled"`, `hadron_kyc_status == "approved"`. Dynamic Tax 2% при carbon_coin + недофінансований страховий пул (→ DAO Treasury). `Kredis.lock` проти race conditions. `transact` (fire-and-forget). Prometheus metric `SCC_MINTED_TOTAL`. |
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
| **Що робить** | USDC мікро-винагороди на Solana. Guard: `verified_by_iotex?` + `oracle_status == "fulfilled"`. Розраховує `reward_lamports = 10_000 + (growth_points × 100)`, де `growth_points` — 6-бітне поле телеметрії (0–63, зі статус-байту солдата). Діапазон: 10_000–16_300 lamports (0.01–0.0163 USDC). JSON RPC `simulateTransaction` (Devnet) → `sendTransaction` (Mainnet). Ed25519 підпис через `Ed25519Crypto::SigningService`. |
| **Зовнішні виклики** | `Web3::HttpClient.post` → Solana RPC JSON API |
| **Вихід** | `tx_signature` (String). Створює `BlockchainTransaction` (audit). |

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
| **Що робить** | Супутникова верифікація EWS-алертів через dClimate. 3 результати: `fire_confirmed` → InsurancePayoutWorker, `clear_sky_no_fire` → BurnCarbonTokensWorker (Slashing за фрод), `obscured_by_clouds` → raise `OrbitalLagError` (Sidekiq retry до 48 год). |
| **Зовнішні виклики** | `InsurancePayoutWorker.perform_async` або `BurnCarbonTokensWorker.perform_async` |
| **Вихід** | `nil`. Side effects: оновлює `alert.satellite_status`, тригерує воркери. |

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
| **Тригер** | `AlertDispatchService`, `GatewayTelemetryWorker`, `DclimateVerificationWorker` |
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

#### `DailyAggregationWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `low` |
| **Retry** | 3, unique_for: 6 годин |
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
| **Retry** | 3, unique_for: 30 хвилин |
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
| **Сервіси** | — (TODO: `PuroEarth::PassportService`) |
| **Side Effects** | `record.update!(biomass_passport_tx_hash:)`. |

---

### 💤 Web3 Low — Не Критичний Блокчейн

#### `EthereumAnchorWorker`

| Параметр | Значення |
|----------|----------|
| **Черга** | `web3_low` |
| **Retry** | 3, unique_for: 1 година |
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
| **Solana RPC** | JSON-RPC 2.0 | `SOLANA_RPC_URL` | Solana::MintingService |
| **Celo RPC** | EVM JSON-RPC | `CELO_RPC_URL` | Celo::CommunityRewardService |
| **IoTeX W3bstream** | HTTPS REST | `iotex_w3bstream_url`, `iotex_api_key` | Iotex::W3bstreamVerificationService |
| **peaq Network** | HTTPS REST | `peaq_node_url`, `peaq_signing_key` | Peaq::DidRegistryService |
| **Chainlink Functions** | On-chain (Polygon) | `CHAINLINK_FUNCTIONS_ROUTER`, `CHAINLINK_SUBSCRIPTION_ID` | Chainlink::OracleDispatchService |
| **dClimate API** | HTTPS REST | — (TODO: real integration) | Dclimate::VerificationService |
| **Streamr Network** | HTTPS REST | `streamr_stream_id`, `streamr_api_key` | Streamr::BroadcasterService |
| **Filecoin/IPFS** (Pinata) | HTTPS REST | `filecoin_api_key` / `FILECOIN_PINNING_API_URL` | Filecoin::ArchiveService, VerificationService |
| **The Graph** | GraphQL | `the_graph_api_url` | TheGraph::QueryService |
| **Polygon Hadron** | HTTPS REST | `hadron_api_key` / `HADRON_API_URL` | Polygon::HadronComplianceService |
| **Etherisc DIP** | On-chain (Polygon) | `ETHERISC_DIP_CONTRACT_ADDRESS` | Etherisc::ClaimService |
| **KlimaDAO** | On-chain (Polygon) | `KLIMA_RETIREMENT_CONTRACT` | KlimaDao::RetirementService |
| **Toucan Protocol** | On-chain (Polygon) | `TOUCAN_BRIDGE_CONTRACT_ADDRESS` | Toucan::BridgeService |
| **Uniswap V3 Quoter** | On-chain (Polygon) | `POLYGON_RPC_URL` | PriceOracleService |
| **CoAP Gateway** | CoAP/UDP | `gateway.ip_address` (dynamic) | ActuatorCommandWorker, OtaTransmissionWorker |

---

> **Версія документа:** v1.0 · 2026-03-22 · Gaia 2.0 — Cycle 1 Small Batch (Reverse Shaping).
> **Метод:** Пасивне сканування кодової бази "як є" (`app/services/` + `app/workers/`). Жодного рефакторингу.
> **Покриття:** 35 service objects (35 файлів), 30 Sidekiq workers + 2 concerns (base infrastructure).
