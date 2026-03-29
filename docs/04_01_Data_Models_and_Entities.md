# 04_01: Data Models and Entities (The PostgreSQL Core)

## 🎯 Мета (Objective)

Зафіксувати повну структуру реляційної бази даних (PostgreSQL) та ActiveRecord моделей для моноліту Ruby on Rails 8.1. Цей документ є **вичерпним довідником** всіх 25 моделей, 6 concerns, ключових індексів, AASM-машин стану та seeds-стану системи. Визначає, як фізичні об'єкти (дерева, шлюзи) та абстрактні концепції (контракти, токени, аудит) пов'язані між собою в єдину Кіберфізичну Державу Gaia 2.0.

---

## ✅ Статус (Status)

- **Поточний TRL:** TRL 8 — Схема БД затверджена, міграції написані, поліморфні зв'язки та індекси оптимізовані для planetary-scale highload.
- **Пов'язані модулі:**
  - Фізичний рівень → [`03_01_Firmware_Lifecycle_and_DMA`](03_01_Firmware_Lifecycle_and_DMA)
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Web3-економіка → [`05_03_Tokenomics_SCC_and_SFC`](05_03_Tokenomics_SCC_and_SFC)

---

## 🛑 Блокери (Blockers / Needs Action)

- ~~**Database Locking:** При одночасному надходженні тисяч пакетів телеметрії, оновлення балансу `Wallet` вимагає `pessimistic locks` (`lock!("FOR UPDATE")`), щоб уникнути race conditions при нарахуванні балів росту. Моніторити Connection Pool.~~ ✅ **ВИРІШЕНО** у [commit 59352473](https://github.com/Alexey-Lukin/silken_net/commit/59352473b7f2ce630532a2ec9e941cbf7d721c99):
  - `Wallet#credit!` — додано `with_lock` (SELECT ... FOR UPDATE) для захисту від race conditions
  - `Wallet#lock_funds!` — додано `with_lock` для усунення TOCTOU race condition
  - `Wallet#release_locked_funds!` — додано `with_lock` для консистентності
  - `TelemetryUnpackerService#commit_telemetry` — кредитування Wallet винесено поза основну транзакцію для мінімізації часу утримання лока (мс замість повної тривалості транзакції)
  - Prometheus: додано gauge-метрики пулу з'єднань БД (size / connections / idle / waiting)
  - Тести: 10 нових RSpec-специфікацій, що верифікують pessimistic locking поведінку
- ~~**Partition Automation:** Таблиці `telemetry_logs` та `gateway_telemetry_logs` партиціоновані вручну по місяцях. Необхідний `PartitionMaintenanceWorker` для автоматичного створення нових партицій наперед.~~ ✅ **ВИРІШЕНО** у [commit cc7609c](https://github.com/Alexey-Lukin/silken_net/commit/cc7609c12ac4cfbc3daed4a6aeb7229d1b3b60bd):
  - Додано `PartitionMaintenanceWorker` (черга `default`, 3 ретраї) — ідемпотентне DDL-створення партицій через `CREATE TABLE IF NOT EXISTS ... PARTITION OF`
  - Охоплює поточний та наступний місяці для `telemetry_logs` і `gateway_telemetry_logs`
  - Безпечна параметризація: `quote_table_name` / `quote` для захисту від SQL-ін'єкцій
  - Заплановано щодня о 02:30 UTC через sidekiq-scheduler cron (`30 2 * * *`)
  - Тести: 122 рядки RSpec-специфікацій у `spec/workers/partition_maintenance_worker_spec.rb`
- ~~**HardwareKey Decrypt Cache:** При мільйонах пакетів/хв десеріалізація зашифрованих ключів AR Encryption створює навантаження на CPU. Рекомендується Redis-кеш binary_key з TTL 5-15 хв + інвалідація при `rotate_key!`.~~ ✅ **ВИРІШЕНО** у [commit 513556a](https://github.com/Alexey-Lukin/silken_net/commit/513556ad2fb094c420f2ab85c7971be2545e2845):
  - Додано `HardwareKey#cached_binary_key` — `Rails.cache.fetch("hw_key:#{device_uid}:bin", expires_in: 15.minutes)` (Redis у prod)
  - Усуває «Double Crypto Tax»: AR Encryption десеріалізація відбувається 1 раз/15 хв замість кожного пакету телеметрії (~2 мс/виклик)
  - Автоматична інвалідація через `after_commit :clear_key_cache, on: %i[update destroy]`
  - `UnpackTelemetryWorker#attempt_decryption` — перехід з `binary_key` → `cached_binary_key` на hot path
  - Безпека: ключі в PostgreSQL залишаються зашифрованими (AR Encryption); Redis — ізольована мережа (Private VPC, TLS, ACL)
  - Тести: 79 нових рядків RSpec у `spec/models/hardware_key_spec.rb`
- ~~**🔴 P0 — Missing index on `blockchain_transactions.tx_hash`:** `BlockchainConfirmationWorker` виконує `BlockchainTransaction.where(tx_hash: tx_hash)` без індексу — повний Sequential Scan на таблиці з мільярдами рядків при планетарному масштабі (1 млрд дерев × щомісячний SCC мінтинг). Файл: `app/workers/blockchain_confirmation_worker.rb:29`.~~ ✅ **ВИРІШЕНО** ([migration 20260328110000](db/migrate/20260328110000_add_tx_hash_index_to_blockchain_transactions.rb)):
  - Додано `CREATE INDEX CONCURRENTLY index_blockchain_transactions_on_tx_hash ... WHERE (tx_hash IS NOT NULL)`
  - `CONCURRENTLY` — Zero-Downtime: без table-level lock, без блокування writes під час індексування
  - `WHERE tx_hash IS NOT NULL` — partial index: виключає `pending/processing` рядки (без tx_hash), зменшує розмір індексу
- ~~**🟠 P1 — `Actuator#commands dependent: :destroy` (OOM ризик при деактивації Gateway):** `app/models/actuator.rb:9` — при видаленні Gateway Rails завантажував кожну `ActuatorCommand` у Ruby і запускав AASM-колбеки + Turbo broadcasts. При 1000+ команд на актуатор → OOM.~~ ✅ **ВИРІШЕНО**: Замінено на `dependent: :delete_all` — один SQL DELETE замість N Ruby-об'єктів. `ActuatorCommand` не несе фінансових зобов'язань (не впливає на `Wallet` балans або `BlockchainTransaction`), тому bypass callbacks безпечний.
- ~~**🟠 P1 — `blockchain_transactions` не партиціонована:** При планетарному масштабі (1B дерев × щомісячний мінтинг ≈ 12B рядків/рік) повний Sequential Scan деградує до хвилин. Необхідне RANGE-партиціонування по `created_at` (квартальне або місячне) аналогічно `telemetry_logs`. Потребує `pg_partman` або ручного `PartitionMaintenanceWorker` для автоматичного DDL.~~ ✅ **ВИРІШЕНО** у PR #221 ([migration 20260328120000](db/migrate/20260328120000_partition_blockchain_transactions_by_created_at.rb)):
  - Стратегія: rename → recreate as partitioned → migrate data → drop old (аналогічно `telemetry_logs`)
  - Composite PK `(id, created_at)` — обов'язкова умова PostgreSQL declarative partitioning (partition key повинен входити в PK)
  - `BlockchainTransaction.self.primary_key = "id"` — Rails використовує `id` для `dom_id`, lookups і асоціацій (composite PK прозорий для AR)
  - Default partition `blockchain_transactions_default` + місячні партиції `y2026m01`..`y2026m06`
  - Всі 8 індексів перестворені на новій партиційованій таблиці (без CONCURRENTLY — PostgreSQL не підтримує CONCURRENTLY на partitioned tables; індекси автоматично пропагуються на всі партиції)
  - FK-constraints перестворені (`wallet_id → wallets`, `cluster_id → clusters`) через `ALTER TABLE` (без ONLY) для пропагації на партиції
  - `PartitionMaintenanceWorker::PARTITIONED_TABLES` оновлено: тепер обслуговує 3 таблиці (`telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`)

### 🔍 Аудит 2026-03-29 — Нові знайдені проблеми

#### 🔴 Блокери

- **🔴 BLK-01 · `AiInsight` — Повністю неправильні назви `insight_type` enum.** Код `app/models/ai_insight.rb` містить 4 значення: `daily_health_summary(0)`, `drought_probability(1)`, `carbon_yield_forecast(2)`, `biodiversity_trend(3)`. Документ §7 натомість наводить `fire_risk_forecast`, `drought_prediction`, `anomaly_detection`, `pest_detection` — жодне з них не існує в коді. Виклик `AiInsight.fire_risk_forecast` або `.pest_detection` підніме `ArgumentError`. **Дія:** Замінити таблицю enum у §7 на актуальні 4 значення.

- **🔴 BLK-02 · `EwsAlert` — `alert_type` enum: неправильні назви І неправильні цілочисельні значення.** Код: `severe_drought(0)`, `insect_epidemic(1)`, `vandalism_breach(2)`, `fire_detected(3)`, `seismic_anomaly(4)`, `system_fault(5)`. Документ §7 вказує `fire(0)`, `drought(1)`, `vandalism(2)`, `system_fault(3)`, `pest(4)`, `seismic(5)` — всі значення неправильні, включно з цілочисельними. Критично для страхових виплат та slashing-логіки. З `prefix: true` → запити використовують `alert_type_fire_detected?`, а не `alert_type_fire?`. **Дія:** Замінити таблицю enum повністю.

- **🔴 BLK-03 · `EwsAlert` — `satellite_status` enum повністю неправильний.** Код: `unverified(0)`, `verified(1)`, `rejected_fraud(2)`, `inconclusive(3)`. Документ §7 вказує `not_required`, `pending`, `verified`, `contradicted`, `unverifiable` — 4 з 5 задокументованих значень не існують. **Дія:** Замінити на актуальні 4 значення.

- **🔴 BLK-04 · `ActuatorCommand` — `priority` enum: всі назви неправильні.** Код: `low(0)`, `medium(1)`, `high(2)`, `override(3)` (з `prefix: true`). Документ §4 вказує `routine(0)`, `urgent(1)`, `emergency(2)`, `override(3)`. Виклики `priority_routine?`, `priority_urgent?`, `priority_emergency?` підняли б `NoMethodError`. **Дія:** Замінити на `low / medium / high / override`, зазначити `prefix: true`.

- **🔴 BLK-05 · `TelemetryLog` — колонка `impedance_ohms` відсутня в БД і моделі.** Документ §3 перераховує `impedance_ohms | integer | Імпеданс ксилеми (Ω)` як поле `TelemetryLog`. Ні DB-схема, ні модель цього поля не мають. **Дія:** Видалити з таблиці полів або відстежити як Open Item.

- **🔴 BLK-06 · `NaasContract` — `insurance_premium_rate` та `forester_share_rate` не є DB-колонками.** Документ §6 перераховує їх як збережені поля. В коді: константа `INSURANCE_PREMIUM_RATE = BigDecimal("0.05")`, обчислювальні методи `insurance_premium_amount` та `forester_share_amount`. **Дія:** Перенести з таблиці "Поля" до таблиці "Методи".

- **🔴 BLK-07 · `Gateway` — `cluster_id` в DB є `NOT NULL`, але модель оголошує `belongs_to :cluster, optional: true`.** `db/structure.sql`: `cluster_id bigint NOT NULL`. Документ §3 вказує "optional". Спроба створити Gateway без cluster_id викличе PG-виключення `null value in column "cluster_id"`. **Дія:** Узгодити схему і модель — або прибрати `optional: true`, або видалити `NOT NULL` з DB.

- **🔴 BLK-08 · `NaasContract` — `start_date`/`end_date`: документ вказує тип `date`, DB зберігає `timestamp`.** `db/structure.sql`: `start_date timestamp(6) without time zone`. **Дія:** Виправити тип на `timestamp`.

#### 🟠 Попередження

- **🟠 WARN-01 · `GatewayTelemetryLog` — два задокументовані поля не існують в БД.** `packets_received_count` та `packets_forwarded_count` відсутні в DB-схемі та моделі. **Дія:** Видалити з документа або створити міграцію.

- **🟠 WARN-02 · `GatewayTelemetryLog#voltage_mv`: тип у документі `integer`, в БД `numeric`.** **Дія:** Виправити тип на `numeric/decimal`.

- **🟠 WARN-03 · `TreeFamily#baseline_impedance`: тип у документі `decimal`, в БД `integer`.** **Дія:** Виправити тип або створити міграцію на `numeric`.

- **🟠 WARN-04 · `MaintenanceRecord` — `action_type` enum: всі значення неправильні.** Код: `installation(0)`, `inspection(1)`, `cleaning(2)`, `repair(3)`, `decommissioning(4)`, `biomass_extraction(5)`. Документ §7 наводить 8 неіснуючих значень. **Дія:** Замінити таблицю enum повністю.

- **🟠 WARN-05 · `MaintenanceRecord` — обмеження фото неправильні.** Код: `size: { less_than: 20.megabytes }`, `content_type: %w[image/jpeg image/png image/webp image/heic image/heif]`, максимум 10 фото. Документ §7 вказує `≤ 5 МБ, JPEG/PNG/HEIC`. **Дія:** Виправити на `≤ 20 МБ, JPEG/PNG/WebP/HEIC/HEIF, макс. 10 фото`.

- **🟠 WARN-06 · `MaintenanceRecord` — відсутній `GeoLocatable` concern у документі §7.** **Дія:** Додати `GeoLocatable` до розділу асоціацій/includes.

- **🟠 WARN-07 · `ParametricInsurance` — поле `uses_etherisc`: документ вказує `boolean`, в коді це рядкова колонка + метод-предикат.** DB: `etherisc_policy_id character varying`. Метод: `def uses_etherisc? = etherisc_policy_id.present?`. **Дія:** Видалити `uses_etherisc` з таблиці полів; додати `etherisc_policy_id | string` і документувати `uses_etherisc?` як метод.

- **🟠 WARN-08 · ER-карта §10: `TreeFamily → TinyMlModels (nullify)` та `→ BioContractFirmwares (nullify)` не існують.** В моделі `TreeFamily` є лише `has_many :trees, dependent: :restrict_with_error`. `TinyMlModel` та `BioContractFirmware` мають `belongs_to :tree_family`, але зворотньої `has_many` в `TreeFamily` немає. **Дія:** Прибрати ці асоціації з ER-карти.

- **🟠 WARN-09 · ER-карта §10: `Organization → Wallets (delete_all)` — в коді відсутній `dependent:`.** `has_many :wallets` без жодної опції `dependent:`. Видалення Organization залишить orphaned Wallets. **Дія:** Додати `dependent: :nullify` або `:destroy`; оновити ER-карту.

- **🟠 WARN-10 · `User#telegram_chat_id`: документ вказує `bigint`, в БД `character varying`.** **Дія:** Виправити тип на `string / varchar`.

- **🟠 WARN-11 · `GatewayTelemetryLog` — AR-асоціація через `queen_uid`, тоді як БД має `gateway_id NOT NULL`.** `belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid` — Rails ніколи не використовує `gateway_id` для AR. Колонка-"привид" невидима моделі. **Дія:** Задокументувати dual-key патерн; вирішити питання канонічного FK.

- **🟠 WARN-12 · `Identity` — провайдер `apple` згаданий у коментарі моделі, але відсутній у `SUPPORTED_PROVIDERS`.** **Дія:** Або видалити `apple` з документа, або додати до константи.

- **🟠 WARN-13 · `BlockchainTransaction` — статус `sent(4)` має розрив після `failed(3)`.** Документ не показує цілочисельні значення enum. **Дія:** Додати цілочисельні значення до таблиці статусів.

- **🟠 WARN-14 · `Organization` — відсутня асоціація `ews_alerts` у документі §5.** Модель: `has_many :ews_alerts, through: :clusters`. Метод `under_threat?` покладається на цю асоціацію. **Дія:** Додати рядок до таблиці асоціацій Organization.

- **🟠 WARN-15 · `AiInsight` — JSONB-колонка `recommendation` не задокументована.** Код: `store_accessor :recommendation, :action_required, :priority`. **Дія:** Додати `recommendation | jsonb | Рекомендації Оракула (action_required, priority)`.

#### 🟡 Нотатки

- **🟡 NOTE-01 · `Tree` — `active_trees_count` помилково вказаний як поле `Tree`.** Це counter cache на таблиці `clusters`, а не `trees`. **Дія:** Видалити з таблиці полів Tree.

- **🟡 NOTE-02 · Численні незадокументовані DB-колонки.** Серед них: `trees` (`peaq_did`, `firmware_version`, `altitude`); `gateways` (`firmware_version`, `altitude`); `telemetry_logs` (`growth_points`, `metabolism_s`, `rssi`, `sap_flow`, `verified_by_iotex`, `zk_proof_ref`, `chainlink_request_id`, `tamper_detected`); `wallets` (`solana_public_address`, `hadron_kyc_status`); `naas_contracts` (`emitted_tokens`, `cancelled_at`, `hadron_asset_id`); `blockchain_transactions` (`cumulative_gas_cost`, `sent_at`, `confirmed_at`, `chainlink_request_id`, `zk_proof_ref`, `locked_points`); `ews_alerts` (`dclimate_ref`); `maintenance_records` (`biomass_passport_tx_hash`); `tiny_ml_models` (`target_pest`, `drift_checked_at`); `clusters` (`climate_type`); `ai_insights` (`analyzed_date`, `average_temperature`, `total_growth_points`, `summary`). **Дія:** Задокументувати у відповідних таблицях моделей.

- **🟡 NOTE-03 · TRL 8 завищений за наявності незакритих BLK-01..BLK-08.** 8 блокерів означають, що документ не точно описує систему. **Дія:** Закрити всі BLK; після цього TRL 8 обґрунтований.

- **🟡 NOTE-04 · Factory для `Wallet` не встановлює асоціацію `organization`.** Тести що будують wallet напряму (без tree) можуть отримати `organization: nil`. **Дія:** Додати `organization { tree&.cluster&.organization }` до factory.

- **🟡 NOTE-05 · `BlockchainTransaction` — AASM event `confirm` приймає два аргументи, але документ не відображає підписи подій.** Код: `event :confirm do |block_num, gas_cost|`. **Дія:** Додати підписи подій: `confirm(block_num, gas_cost)`, `mark_as_sent(tx_hash)`, `fail(reason)`.


---

## 🏛️ 0. PostgreSQL Інфраструктура

### Розширення

| Розширення | Призначення |
|------------|-------------|
| `postgis` | Геопросторові запити (ST_Contains, ST_MakePoint, GIST-індекси) |
| `pgcrypto` | Криптографічні функції на рівні БД |
| `uuid-ossp` | UUID генерація |

### Тригери

| Тригер | Таблиця | Призначення |
|--------|---------|-------------|
| `sync_cluster_geo_boundary()` | `clusters` | Автоматична синхронізація PostGIS geometry `geo_boundary` з JSONB `geojson_polygon` |

### Партиціонування (RANGE BY created_at)

| Таблиця | Стратегія | Причина |
|---------|-----------|---------|
| `telemetry_logs` | RANGE by month | Мільйони рядків/місяць від Солдатів |
| `gateway_telemetry_logs` | RANGE by month | Тисячі рядків/місяць від Королев |
| `blockchain_transactions` | RANGE by month | ≈ 12B рядків/рік при 1B дерев × щомісячний SCC мінтинг; composite PK `(id, created_at)` |

Поточні партиції: `y2026m01` → `y2026m06` + `_default` (для старих/нових даних).

**Автоматизація:** `PartitionMaintenanceWorker` (черга `default`) щодня о 02:30 UTC гарантує існування партицій для **поточного та наступного місяця** для всіх трьох таблиць (`telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`). Назва партиції формується за шаблоном `<table>_y<YYYY>m<MM>` (напр. `blockchain_transactions_y2026m04`). Операція ідемпотентна — `CREATE TABLE IF NOT EXISTS`.

---

## 🔧 1. Concerns (Shared Modules)

Шість спільних модулів, що підключаються через `include` до відповідних моделей.

### `EthAddressValidatable`
**Використовується:** `Organization`, `Wallet`, `BlockchainTransaction`

Валідація Ethereum/Polygon-адрес формату EIP-55.

```
ETH_ADDRESS_FORMAT = /\A0x[a-fA-F0-9]{40}\z/
```

Метод: `validates_eth_address(attribute, presence:, allow_blank:)` — додає валідацію формату до поля.

---

### `Firmwareable`
**Використовується:** `Tree`, `Gateway`

OTA-lifecycle для IoT-пристроїв. Додає enum `firmware_update_status` (7 станів) та AASM-машину.

| Стан | Значення | Опис |
|------|----------|------|
| `fw_idle` | 0 | Немає активного оновлення |
| `fw_pending` | 1 | Оновлення заплановано |
| `fw_downloading` | 2 | Завантаження чанків через LoRa |
| `fw_verifying` | 3 | Верифікація SHA-256 |
| `fw_flashing` | 4 | Запис у Flash пам'ять STM32 |
| `fw_failed` | 5 | Збій OTA |
| `fw_completed` | 6 | Успішно оновлено |

AASM-переходи: `schedule_update` → `start_download` → `start_verification` → `start_flashing` → `complete_update`. Збій на будь-якому етапі → `fail_update`. Скидання → `reset_firmware`.

---

### `GeoLocatable`
**Використовується:** `Tree`, `Gateway`

WGS-84 валідація координат.

| Поле | Діапазон |
|------|----------|
| `latitude` | -90..90 |
| `longitude` | -180..180 |

Метод: `geolocated?` — обидва поля присутні.

---

### `HasArgon2Password`
**Використовується:** `User`

Замінює `has_secure_password` на Argon2id (переможець Password Hashing Competition, рекомендація OWASP). Memory-hard, стійкий до GPU/ASIC атак. Інтерфейс сумісний з Rails: `password=`, `authenticate(password)`, `password_salt`.

---

### `NormalizeIdentifier`
**Використовується:** `Tree`, `Gateway`, `HardwareKey`

Нормалізація апаратних ідентифікаторів: `strip + upcase`.

```ruby
normalize_identifier :did   # Tree  → "SNET-1A2B3C4D"
normalize_identifier :uid   # Gateway → "SNET-Q-1A2B3C4D"
normalize_identifier :device_uid  # HardwareKey
```

---

### `OtaChunkable`
**Використовується:** `TinyMlModel`, `BioContractFirmware`

Розбиття бінарного payload на CoAP-сегменти для OTA.

| Метод | Результат |
|-------|-----------|
| `chunks(512)` | `Array<String>` — масив бінарних чанків по 512 байт |
| `total_chunks(512)` | `Integer` — кількість чанків |

Потребує реалізації `#binary_payload` та `#payload_size` в моделі.

---

## 🌲 2. Біологічний Рівень (Environment)

### `TreeFamily` — Генетичний Шаблон

**Призначення:** Вид дерева (порода). Містить біологічні константи для Атрактора Лоренца та TinyML.

**Асоціації:**
- `has_many :trees, dependent: :restrict_with_error` — захист: не можна видалити, поки є живі носії геному

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Унікальна назва (напр. "Сосна Звичайна") |
| `scientific_name` | string | Латинська назва (nullable, для міжнародних контрактів) |
| `baseline_impedance` | decimal | Базовий імпеданс ксилеми (Ω) |
| `critical_z_min` | decimal | Мінімум Z-значення атрактора (нижня межа гомеостазу) |
| `critical_z_max` | decimal | Максимум Z-значення атрактора (`> critical_z_min`) |
| `carbon_sequestration_coefficient` | decimal | Коефіцієнт секвестрації (> 0) для зваженого нарахування SCC |
| `biological_properties` | jsonb | `sap_flow_index`, `bark_thickness`, `foliage_density`, `fire_resistance_rating` |

**Ключові методи:**

| Метод | Повертає | Опис |
|-------|----------|------|
| `attractor_thresholds` | `{min:, max:, baseline:}` | Параметри для Lorenz attractor |
| `attractor_thresholds_cached` | Hash | Кешована версія (24 год) для hot path |
| `death_threshold_impedance` | Float | `baseline_impedance * 0.3` — "Межа Смерті" |
| `healthy_z?(z_value)` | Boolean | Чи Z у межах гомеостазу |
| `stress_level(impedance)` | Symbol | `:normal / :warning / :critical / :dead` |
| `weighted_growth_points(raw)` | Float | `raw * carbon_sequestration_coefficient` |
| `display_name` | String | "Quercus robur (Дуб звичайний)" або просто назва |

**Callbacks:** `after_update :invalidate_thresholds_cache` — при зміні порогів Атрактора.

---

### `Tree` — Солдат (основний юніт моніторингу)

**Призначення:** Кожне дерево з встановленим EBFC-анкером та STM32WLE5JC-капсулою.

**Includes:** `AASM`, `Firmwareable`, `GeoLocatable`, `NormalizeIdentifier`

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `cluster` | `belongs_to, optional` | Геосектор |
| `tree_family` | `belongs_to, counter_cache` | Геном (порода) |
| `tiny_ml_model` | `belongs_to, optional` | Активна ML-модель |
| `wallet` | `has_one, dependent: :destroy` | Вуглецевий гаманець |
| `hardware_key` | `has_one` via `did/device_uid` | AES-256 ключ |
| `device_calibration` | `has_one, dependent: :destroy` | Офсети датчиків |
| `telemetry_logs` | `has_many, dependent: :delete_all` | Сирі пакети з поля |
| `ews_alerts` | `has_many, dependent: :delete_all` | Тривоги |
| `maintenance_records` | `has_many, polymorphic` | Журнал обслуговування |
| `ai_insights` | `has_many, polymorphic` | Висновки Оракула |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `did` | string | `SNET-[8 HEX]` — апаратний ідентифікатор STM32 |
| `status` | enum | `active(0) / dormant(1) / removed(2) / deceased(3)` |
| `firmware_update_status` | enum | OTA lifecycle (via Firmwareable) |
| `latitude`, `longitude` | decimal | WGS-84 координати (via GeoLocatable) |
| `last_seen_at` | datetime | Останній пакет телеметрії |
| `latest_voltage_mv` | integer | Денормалізована напруга іоністора (мВ) |
| `latest_stress_index` | decimal | Денормалізований stress_index від InsightGeneratorService |
| `health_streak` | integer | Кількість послідовних здорових пакетів (Anti-Flapping) |
| `active_trees_count` | integer | Counter cache на Cluster |

**AASM State Machine (column: `status`):**

```
active ──suspend──► dormant
active/dormant ──decommission──► removed
active/dormant ──declare_deceased──► deceased
dormant ──reactivate──► active
```

**Константи:**
- `VCAP_MIN_MV = 2800` — мінімум для mesh-relay
- `VCAP_MAX_MV = 5500` — повний заряд іоністора
- `LOW_POWER_MV = 3300` — поріг критичного рівня
- `DID_FORMAT = /\ASNET-[0-9A-F]{8}\z/`

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `mark_seen!(voltage_mv)` | Hot path: `GREATEST` атомарне оновлення `last_seen_at` + `latest_voltage_mv`. Обходить колбеки. |
| `current_stress` | Читає `latest_stress_index` (денормалізовано, без N+1) |
| `charge_percentage` | `(voltage - MIN) / (MAX - MIN) * 100` |
| `low_power?` | `voltage > 0 && voltage < 3300` |
| `under_threat?` | `ews_alerts.unresolved.exists?` |
| `broadcast_map_update` | Turbo Stream → `geospatial_matrix` |

**Callbacks:**
- `after_create :build_default_wallet` — автоматично створює Wallet
- `after_create :ensure_calibration` — автоматично створює DeviceCalibration
- `after_update_commit :trigger_slashing_protocol` — при `removed?` або `deceased?` → `BurnCarbonTokensWorker`
- `after_update_commit :broadcast_map_update, if: :map_relevant_change?` — лише при зміні lat/lng/status/voltage

**Scopes:** `active`, `geolocated`, `silent` (> 24 год мовчання), `critical_stress` (stress > 0.8).

---

### `Cluster` — Геопросторовий Контейнер

**Призначення:** Лісовий сектор (гектар, квартал). Об'єднує Дерева та Шлюзи. Одиниця NaaS-контракту.

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `organization` | `belongs_to` | Власник |
| `trees` | `has_many, dependent: :nullify` | Солдати |
| `gateways` | `has_many, dependent: :nullify` | Королеви |
| `naas_contracts` | `has_many, dependent: :restrict_with_error` | Захист фінансової історії |
| `parametric_insurances` | `has_many, dependent: :restrict_with_error` | Захист страхової історії |
| `ews_alerts` | `has_many, dependent: :delete_all` | Тривоги сектора |
| `ai_insights` | `has_many, polymorphic, dependent: :delete_all` | Daily Health Summary |
| `actuators` | `has_many, through: :gateways` | Виконавчі пристрої |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Унікальна назва кластера |
| `region` | string | Географічний регіон |
| `geo_boundary` | geometry (PostGIS) | Полігон сектора для ST_Contains |
| `geojson_polygon` | jsonb | GeoJSON-представлення (синхронізується тригером) |
| `health_index` | decimal | Денормалізований індекс `1.0 - stress_index` (0..1) |
| `active_trees_count` | integer | Counter cache (оновлюється Tree callbacks) |
| `environmental_settings` | jsonb | `custom_fire_threshold`, `seismic_sensitivity_threshold`, `timezone` |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `contains_point?(lat, lng)` | PostGIS: `ST_Contains` через GIST-індекс |
| `total_active_trees` | Читає `active_trees_count` (без COUNT(*)) |
| `health_index` | Читає денормалізовану колонку (0..1) |
| `recalculate_health_index!` | `1.0 - stress_index` зі щоденного AiInsight |
| `local_yesterday` | Дата "вчора" в TZ кластера (для детермінованого арбітражу) |
| `geo_center` | Мемоізований центроїд полігону (Resilient — підтримує MultiPolygon) |
| `active_contract` | Останній активний NaasContract (з ORDER BY) |
| `active_threats?` | `ews_alerts.unresolved.critical.exists?` |
| `mapped?` | Чи є GeoJSON координати |

**Scopes:** `alphabetical`, `containing_point(lat, lng)`, `under_threat`.

---

## ⚙️ 3. Апаратний Рівень (Hardware & IoT)

### `Gateway` — Королева (LoRaWAN Шлюз)

**Включає:** `AASM`, `Firmwareable`, `GeoLocatable`, `NormalizeIdentifier`

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `cluster` | `belongs_to, optional` | Сектор відповідальності |
| `hardware_key` | `has_one` via `uid/device_uid` | AES-256 ключ розшифровки батчів |
| `trees` | `has_many, through: :cluster` | Підлеглі Солдати |
| `telemetry_logs` | `has_many` via `queen_uid/uid` | Пакети, прийняті цією Королевою |
| `gateway_telemetry_logs` | `has_many, dependent: :delete_all` | Власна діагностика |
| `latest_gateway_telemetry_log` | `has_one` (ordered) | Останній стан Королеви |
| `maintenance_records` | `has_many, polymorphic, restrict_with_error` | Журнал (незмінний) |
| `actuators` | `has_many, dependent: :destroy` | Виконавчі пристрої |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `uid` | string | `SNET-Q-[8 HEX]` |
| `state` | enum | `idle/active/updating/maintenance/faulty` |
| `firmware_update_status` | enum | OTA lifecycle (via Firmwareable) |
| `config_sleep_interval_s` | integer | Інтервал сну (≥ 60 сек) |
| `ip_address` | string | IP модему SIM7070G |
| `last_seen_at` | datetime | Останній CoAP batch |
| `latest_voltage_mv` | integer | Денормалізована напруга |

**AASM State Machine (column: `state`):**

```
idle ──wake──► active ──sleep──► idle
idle/active ──begin_update──► updating ──finish_update──► idle
idle/active/faulty ──enter_maintenance──► maintenance ──exit_maintenance──► idle
any ──report_fault──► faulty
```

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `mark_seen!(new_ip:, voltage_mv:)` | `GREATEST` атомарне оновлення, обходить колбеки |
| `online?` | `last_seen_at >= (sleep_interval * 1.2).seconds.ago` |
| `next_wakeup_expected_at` | `last_seen_at + sleep_interval` |
| `battery_critical?` | `latest_voltage_mv < 3300` |
| `system_fault?` | EwsAlert `system_fault` або `battery_critical?` |

**Scopes:** `online`, `offline`, `ready_for_commands` (idle + online).

---

### `HardwareKey` — Криптографічний Ключ

**Включає:** `NormalizeIdentifier`

**Призначення:** AES-256 ключ для розшифровки пакетів від Солдата або Королеви. Зашифрований на рівні AR Encryption (non-deterministic).

**Асоціації:**
- `belongs_to :tree` via `device_uid/did` (optional)
- `belongs_to :gateway` via `device_uid/uid` (optional)
- `delegate :organization, :cluster, to: :owner`

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `device_uid` | string | Унікальний ідентифікатор пристрою |
| `aes_key_hex` | string (encrypted) | 64 HEX символи (AES-256). AR Encryption non-deterministic |
| `previous_aes_key_hex` | string (encrypted) | Попередній ключ (Grace Period при ротації) |
| `rotated_at` | datetime | Час останньої ротації |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `binary_key` | `[aes_key_hex].pack("H*")` — мемоізовано |
| `cached_binary_key` | `Rails.cache.fetch("hw_key:#{device_uid}:bin", expires_in: 15.minutes)` — Redis-кеш для hot path |
| `binary_previous_key` | Попередній ключ у байтах (Grace Period) |
| `rotate_key!` | М'яка ротація: старий → `previous_aes_key_hex`, новий генерується |
| `clear_grace_period!` | Очищення `previous_aes_key_hex` після підтвердження синхронізації |
| `owner` | `tree || gateway` |

**Callbacks:**
- `after_commit :clear_key_cache, on: %i[update destroy]` — автоматична інвалідація Redis-кешу при зміні або видаленні ключа

---

### `DeviceCalibration` — Офсети Датчиків

**Призначення:** Програмна компенсація апаратного дрейфу сенсорів дерева.

**Асоціації:** `belongs_to :tree`, `delegate :cluster_id, to: :tree`

**Ключові поля:**

| Поле | Тип | Значення за замовчуванням | Опис |
|------|-----|--------------------------|------|
| `temperature_offset_c` | decimal | 0.0 | Офсет температури (°C) |
| `impedance_offset_ohms` | decimal | 0.0 | Офсет імпедансу (Ω) |
| `vcap_coefficient` | decimal | 1.0 | Коефіцієнт напруги (0 < x < 2.0) |

**Константи критичного дрейфу:**
- `MAX_TEMP_DRIFT = 5.0` °C
- `MAX_IMPEDANCE_DRIFT = 500` Ω
- `MAX_VCAP_TOLERANCE = 0.2` (20%)

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `normalize_temperature(raw)` | `raw + temperature_offset_c` |
| `normalize_impedance(raw)` | `raw + impedance_offset_ohms` |
| `normalize_voltage(raw)` | `raw * vcap_coefficient` |
| `sensor_drift_critical?` | Перевищення порогів → потрібна заміна |

**Callback:** `after_save :check_for_hardware_fault` — при критичному дрейфі автоматично створює `EwsAlert` (system_fault / medium), дедуплікація через `find_or_create_by!`.

---

### `TelemetryLog` — Сирий Пакет Телеметрії

**Призначення:** Декодований 21-байтний пакет від Солдата. Партиціонована таблиця (RANGE by month).

**Асоціації:**
- `belongs_to :tree`
- `belongs_to :gateway` via `queen_uid/uid` (optional)
- `belongs_to :bio_contract_firmware` via `firmware_version_id` (optional)

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `bio_status` | enum | `homeostasis(0) / stress(1) / anomaly(2) / tamper_detected(3)` |
| `temperature_c` | decimal | Температура (°C) |
| `voltage_mv` | integer | Напруга EBFC (мВ) |
| `z_value` | decimal | Z-значення Атрактора Лоренца |
| `impedance_ohms` | integer | Імпеданс ксилеми (Ω) |
| `piezo_voltage_mv` | integer | П'єзодатчик (сейсміка) |
| `acoustic_events` | integer | Кількість акустичних подій (TinyML) |
| `mesh_ttl` | integer | Time-To-Live пакету в mesh-мережі |
| `queen_uid` | string | UID Королеви-ретранслятора |
| `oracle_status` | string | Статус обробки Oracle (dispatched/fulfilled/failed) |
| `firmware_version_id` | integer | Версія прошивки з padding-байтів |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `relayed_via_mesh?(initial_ttl=5)` | `mesh_ttl < initial_ttl` |
| `critical?` | `anomaly?` або `tamper_detected?` |
| `healthy?` | homeostasis + temp < 50 + acoustic < 20 |
| `optimal?` | healthy + voltage > 3600 + z_value 0.1..0.5 |
| `recovery_confirmed?` | `healthy? && tree.health_streak >= 3` |

**Scopes:** `recent`, `anomalies`, `in_timeframe`, `vandalized`, `seismic_activity`.

> ⚡ **KENOSIS TITAN:** Валідації видалено з hot path. Перевірка відбувається в `TelemetryUnpackerService.valid_sensor_data?` до INSERT.

---

### `GatewayTelemetryLog` — Діагностика Королеви

**Призначення:** Власна телеметрія шлюзу (батарея, температура, сигнал). Партиціонована.

**Асоціації:** `belongs_to :gateway` via `queen_uid/uid`

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `queen_uid` | string | UID Королеви |
| `voltage_mv` | integer | Напруга батареї/сонячної панелі (мВ) |
| `temperature_c` | decimal | Температура корпусу (°C) |
| `cellular_signal_csq` | integer | Сила сигналу LTE (0-31, 99=unknown) |
| `packets_received_count` | integer | Прийнятих пакетів від Солдатів |
| `packets_forwarded_count` | integer | Переданих пакетів до Rails API |

**Константи:** `LOW_BATTERY_THRESHOLD=3300`, `OVERHEAT_THRESHOLD=65`, `LOW_SIGNAL_THRESHOLD=5`

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `signal_quality_percentage` | `(csq / 31.0) * 100` |
| `signal_dbm` | `2 * csq - 113` (формула 3GPP) |
| `critical_fault?` | Будь-яка з трьох констант перевищена |

---

## 🧠 4. AI / OTA / Актуатори

### `TinyMlModel` — Акустичний Інтелект

**Включає:** `OtaChunkable`

**Призначення:** Версіонована ML-модель для on-device акустичної класифікації (6 класів: chainsaw, fire, woodpecker, cavitation, wind, silence).

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `version` | string | Унікальна версія (напр. "v2.1.0-silken") |
| `binary_weights_payload` | binary | Ваги моделі (≤ 256 KB) |
| `checksum` | string | SHA-256 бінарних ваг |
| `model_format` | string | `tflite / edge_impulse / onnx / c_array` |
| `is_active` | boolean | Чи активна ця версія |
| `rollout_percentage` | integer | Відсоток розгортання (0-100) |
| `min_firmware_version` | string | Мінімальна сумісна прошивка (SemVer) |
| `tree_family_id` | bigint | Специфічна порода (сосна ≠ дуб) |
| `metadata` | jsonb | `accuracy_score` (BigDecimal 0..1), `threshold` (BigDecimal), `input_shape` |
| `true_positive_rate` | decimal | TPR (drift tracking) |
| `false_positive_rate` | decimal | FPR (> 0.15 = drift) |
| `total_predictions` | integer | Лічильник передбачень |
| `confirmed_predictions` | integer | Підтверджені передбачення |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `accuracy_score` / `threshold` | BigDecimal з JSONB (уникає Float похибок) |
| `firmware_compatible?(version)` | `Gem::Version` порівняння |
| `activate!(percentage:)` | Деактивує інші версії, активує цю з відсотком |
| `record_prediction!(confirmed:)` | Drift tracking |
| `drifting?` | `false_positive_rate > 0.15` |
| `chunks(512)` | OTA-сегменти (via OtaChunkable) |
| `binary_sha256` | SHA-256 для OtaPackagerService |

---

### `BioContractFirmware` — mruby Байткод

**Включає:** `OtaChunkable`

**Призначення:** Версіонована прошивка — mruby байткод Lorenz attractor або С-бінарник STM32.

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `version` | string | Унікальна версія |
| `bytecode_payload` | string | HEX-рядок (≤ MAX_BYTECODE_SIZE = 512 KB) |
| `target_hardware_type` | string | Цільова архітектура апаратури |
| `is_active` | boolean | Активна версія |
| `rollout_percentage` | integer | Phased diffusion (0-100) |
| `tree_family_id` | bigint | Специфічна порода (optional) |

**Методи:** `binary_payload`, `payload_size`, `binary_sha256`, `verify_integrity!`, `deploy_globally!(percentage:)`, `chunks(512)`.

---

### `Actuator` — Виконавчий Пристрій

**Включає:** `AASM`

**Призначення:** Фізичний актуатор, підключений до Королеви (клапан поливу, сирена, LED-маркер).

**Асоціації:**
- `belongs_to :gateway`
- `has_one :cluster, through: :gateway`
- `has_many :commands, class_name: "ActuatorCommand", dependent: :delete_all`

**Enums:**

| Enum | Значення |
|------|----------|
| `device_type` | `water_valve(0) / fire_siren(1) / seismic_beacon(2) / drone_launcher(3)` |
| `state` | `idle(0) / active(1) / offline(2) / maintenance_needed(3)` |

**AASM:** `activate` (idle→active), `deactivate` (→idle), `go_offline` (→offline), `report_fault` (→maintenance_needed).

**Методи:** `ready_for_deployment?`, `mark_active!`, `mark_idle!`, `require_maintenance!(reason)`.

---

### `ActuatorCommand` — Команда Актуатору

**Включає:** `AASM`

**Призначення:** Одна команда до актуатора з підтвердженням виконання та idempotency.

**Асоціації:**
- `belongs_to :actuator`
- `belongs_to :ews_alert` (optional) — причина команди
- `belongs_to :user` (optional) — хто видав
- `belongs_to :organization` (optional, денормалізовано)

**Enums:**

| Enum | Значення |
|------|----------|
| `status` | `issued(0) / sent(1) / acknowledged(2) / failed(3) / confirmed(4)` |
| `priority` | `routine(0) / urgent(1) / emergency(2) / override(3)` |

**AASM:** `dispatch` (issued→sent), `acknowledge` (sent→acknowledged), `confirm` (acknowledged→confirmed), `fail`.

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `command_payload` | jsonb | Команда (action, params) |
| `idempotency_token` | string | UUID для захисту від дублів |
| `duration_seconds` | integer | Тривалість дії (safety envelope) |
| `expires_at` | datetime | Термін придатності |
| `priority` | enum | Рівень пріоритету |

**Методи:** `estimated_completion_at`, `expired?`, `dispatch_to_edge!`, `cancel_pending_for_actuator!`.

---

## 👤 5. Люди та Організації (Core & Identity)

### `Organization` — Власник Лісових Активів

**Включає:** `EthAddressValidatable`

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `users` | `has_many, restrict_with_error` | Захист аудит-логів |
| `naas_contracts` | `has_many, restrict_with_error` | Фінансова цілісність |
| `clusters` | `has_many, dependent: :destroy` | Лісові масиви |
| `trees` | `has_many, through: :clusters` | Всі дерева |
| `wallets` | `has_many` (direct FK) | Пряма магістраль (без 4-рівневого JOIN) |
| `audit_logs` | `has_many, dependent: :delete_all` | Незмінний аудит |
| `logo` | `has_one_attached` | Active Storage |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Унікальна назва |
| `billing_email` | string | Нормалізований (lowercase) |
| `crypto_public_address` | string | Ethereum/Polygon-адреса (EIP-55, strip without downcase) |
| `data_region` | string | `eu-west / eu-central / us-east / us-west / ap-southeast` (GDPR sharding) |
| `alert_threshold_critical_z` | decimal | Поріг Z для власних тривог (0..10) |
| `ai_sensitivity` | decimal | Чутливість AI (0..1) |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `total_carbon_points` | `wallets.sum(:balance)` — прямий SELECT |
| `health_score` | `clusters.average(:health_index)` — SQL AVG |
| `total_invested` | `naas_contracts.sum(:total_funding)` |
| `cached_trees_count` | 1 год кеш `organization_#{id}_trees_count` |
| `under_threat?` | `ews_alerts.unresolved.critical.exists?` |

---

### `User` — Суб'єкт Системи

**Включає:** `HasArgon2Password`

**Ролі (RBAC):**

| Роль | Рівень доступу | Опис |
|------|---------------|------|
| `investor(0)` | `:read_only` | Лише власні ресурси |
| `forester(1)` | `:field` | Польовий доступ в межах org |
| `admin(2)` | `:organization` | Повний доступ в межах org |
| `super_admin(3)` | `:system` | Повний доступ до платформи |

**Токени (Rails 8 `generates_token_for`):**

| Токен | TTL | Прив'язка до |
|-------|-----|-------------|
| `password_reset` | 15 хв | `password_salt.last(10)` |
| `email_verification` | 24 год | `email_address` |
| `api_access` | 30 днів | `password_salt.last(10)` (згорає при зміні пароля) |
| `stream_access` | 1 год | `password_salt.last(10)` |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `email_address` | string | Нормалізований (lowercase + strip) |
| `password_digest` | string | Argon2id хеш |
| `role` | enum | investor/forester/admin/super_admin |
| `phone_number` | string | E.164 формат |
| `otp_required_for_login` | boolean | MFA активовано |
| `recovery_codes` | text | JSON масив 10 одноразових кодів |
| `telegram_chat_id` | bigint | Для Telegram сповіщень |
| `last_seen_at` | datetime | Оновлюється через Session |

**Системний бот:** `User.oracle_executioner` — `oracle.executioner@system.silken.net` (super_admin без org). Використовується для автоматичних операцій системи.

**Ключові методи:** `access_level`, `forest_commander?`, `full_name`, `touch_visit!`, `mfa_enabled?`, `consume_recovery_code!`, `generate_recovery_codes!`.

---

### `Session` — Нативний Токен Rails 8

**Асоціації:** `belongs_to :user`

**Ключові поля:** `ip_address`, `user_agent`, `updated_at` (оновлюється `after_touch`).

**Методи:** `mobile_app?` (regex `SilkenNetMobile`), `touch_activity!`.

**Scopes:** `stale` (> 30 днів), `active_in_field` (foresters за 24 год).

---

### `Identity` — OAuth2 Ідентичність

**Асоціації:**
- `belongs_to :user`
- `delegate :organization, :role, to: :user`
- `delegate :wallets, to: :organization`

**Підтримувані провайдери:** `google_oauth2`, `facebook`, `linkedin`, `twitter`

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `provider` | string | Назва провайдера |
| `uid` | string | Унікальний ID у провайдера (unique per provider) |
| `access_token` / `refresh_token` | string | OAuth2 токени |
| `expires_at` | datetime | Термін дії токена |
| `auth_data` | jsonb | Повний зліпок профілю |
| `primary` | boolean | Основний метод входу |
| `locked_at` | datetime | Час блокування (Account Takeover Protection) |

**Ключові методи:** `find_or_create_from_auth_hash(auth_hash, user:)`, `token_expired?`, `locked?`, `lock!`, `unlock!`, `make_primary!`.

---

## 💰 6. Економічний Рівень (Economy & Web3)

### `Wallet` — Вуглецевий Гаманець

**Включає:** `EthAddressValidatable`

**Асоціації:**
- `belongs_to :tree`
- `belongs_to :organization` (optional, денормалізований FK)
- `has_many :blockchain_transactions, dependent: :delete_all`
- `has_one :cluster, through: :tree`

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `balance` | decimal | Основний баланс growth_points (≥ 0) |
| `locked_balance` | decimal | Заморожені points (в процесі емісії) |
| `esg_retired_balance` | decimal | Списані балансом ESG-retired |
| `toucan_bridged_balance` | decimal | Bridged через Toucan Protocol |
| `crypto_public_address` | string | Polygon/Ethereum-адреса гаманця (EIP-55) |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `available_balance` | `balance - locked_balance` |
| `lock_funds!(amount)` | Переміщує з `balance` до `locked_balance` |
| `release_locked_funds!(amount)` | Повертає до `balance` |
| `finalize_spend!(amount)` | Зменшує `locked_balance` (після мінту) |
| `credit!(points)` | Зараховує з урахуванням `carbon_sequestration_coefficient` породи |
| `lock_and_mint!(points_to_lock, threshold, token_type)` | Повний цикл емісії SCC (10,000 points = 1 SCC) |
| `lock_for_toucan_bridge!(amount)` | Підготовка до Toucan Bridge |
| `broadcast_balance_update` | Turbo Stream оновлення UI |

---

### `BlockchainTransaction` — Незмінний Лог Web3

**Включає:** `AASM`, `EthAddressValidatable`

**Асоціації:**
- `belongs_to :wallet` (optional)
- `belongs_to :cluster` (optional)
- `belongs_to :sourceable, polymorphic: true` (optional) — NaasContract, ParametricInsurance

**Enums:**

| Enum | Значення |
|------|----------|
| `token_type` | `carbon_coin(0) / forest_coin(1) / cusd(2)` |
| `status` | `pending(0) / processing(1) / confirmed(2) / failed(3) / sent(4)` |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `amount` | decimal | Сума (> 0) |
| `to_address` | string | Ethereum або Base58 (Solana) адреса |
| `blockchain_network` | string | `evm / solana / celo` |
| `tx_hash` | string | Хеш транзакції (required для sent/confirmed) |
| `gas_price` / `gas_used` | decimal | EVM-газ |
| `block_number` | integer | Номер блоку |
| `nonce` | integer | EVM nonce |

**AASM:** `process` (pending→processing), `mark_as_sent`, `confirm`, `fail`.

**Методи:** `explorer_url`, `solana_network?`, `celo_network?`, `broadcast_status_change`.

**Scalability (P1 — ✅ ВИРІШЕНО у PR #221):** Таблиця переведена на PostgreSQL Declarative RANGE Partitioning по `created_at` (місячні партиції). Composite PK `(id, created_at)` — вимога partitioning. `self.primary_key = "id"` — Rails використовує `id` для `dom_id` та асоціацій. Всі 8 індексів перестворені (автоматично пропагуються на партиції). `PartitionMaintenanceWorker` тепер підтримує `blockchain_transactions` поряд з `telemetry_logs` та `gateway_telemetry_logs`.

---

### `NaasContract` — Nature-as-a-Service Контракт

**Включає:** `AASM`

**Асоціації:**
- `belongs_to :organization`
- `belongs_to :cluster`

**AASM State Machine (column: `status`):**

```
draft ──activate──► active ──fulfill──► fulfilled
active ──breach──► breached    (якщо > 20% дерев deceased/removed → Slashing)
active/draft ──cancel──► cancelled
```

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `status` | enum | `draft/active/fulfilled/breached/cancelled` |
| `total_funding` | decimal | Загальний обсяг фінансування (> 0) |
| `start_date` / `end_date` | date | Строки контракту |
| `insurance_premium_rate` | decimal | Ставка страхової премії |
| `forester_share_rate` | decimal | Частка лісника |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `check_cluster_health!` | Оцінює здоров'я кластера (викликається Worker) |
| `calculate_early_exit_fee` | Штраф за дострокове розірвання |
| `calculate_prorated_refund` | Пропорційне повернення |
| `terminate_early!` | Дострокове розірвання |
| `current_yield_performance` | Поточна прибутковість |
| `active_threats?` | Загрози в кластері |

**Scopes:** `active`, `pending_completion` (active + end_date < now).

---

### `ParametricInsurance` — Страховий Щит

**Включає:** `AASM`

**Асоціації:**
- `belongs_to :organization`
- `belongs_to :cluster`
- `has_one :blockchain_transaction, as: :sourceable`

**Enums:**

| Enum | Значення |
|------|----------|
| `status` | `active(0) / triggered(1) / paid(2) / expired(3)` |
| `trigger_event` | `critical_fire(0) / extreme_drought(1) / insect_epidemic(2)` |
| `token_type` | `carbon_coin(0) / forest_coin(1)` |

**AASM:** `trigger` (active→triggered), `pay` (triggered→paid), `expire` (active→expired).

**Ключові поля:** `payout_amount`, `threshold_value` (0..100), `required_confirmations`, `uses_etherisc` (boolean).

**Ключові методи:** `evaluate_daily_health!(target_date)`, `activate_payout!(percentage)`, `recipient_wallet_address`.

---

## 🚨 7. Інтелект та Аудит (Intelligence, Alerts & Compliance)

### `AiInsight` — Висновок Оракула

**Призначення:** Результат роботи `InsightGeneratorService` — щоденний звіт або прогноз для Tree або Cluster.

**Асоціації:** `belongs_to :analyzable, polymorphic: true` (Tree або Cluster)

**Enum `insight_type`:**

| Тип | Опис |
|-----|------|
| `daily_health_summary` | Щоденний підсумок (stress_index) |
| `fire_risk_forecast` | Прогноз пожежного ризику |
| `drought_prediction` | Прогноз посухи |
| `anomaly_detection` | Виявлення аномалії |
| `carbon_yield_forecast` | Прогноз вуглецевого виходу |
| `pest_detection` | Виявлення шкідників |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `insight_type` | enum | Тип висновку |
| `target_date` | date | Дата, до якої відноситься (unique per analyzable+type) |
| `stress_index` | decimal | 0.0..1.0 (ключовий показник) |
| `probability_score` | decimal | 0.0..100.0 (впевненість Оракула) |
| `reasoning` | jsonb (GIN) | Текстові причини з повнотекстовим пошуком |
| `source_log_ids` | integer[] (GIN) | IDs telemetry_logs, що стали джерелом |
| `fraud_detected` | boolean | Прапор маніпуляції даними |
| `model_source` | string | AI-модель (GPT-4, Claude, тощо) |

**Ключові методи:** `contract_breach?`, `confidence_level`, `forecast?`, `source_logs`, `attach_evidence!(log_ids)`, `status_label`.

---

### `EwsAlert` — Тривога Раннього Попередження

**Включає:** `AASM`

**Асоціації:**
- `belongs_to :cluster` (optional)
- `belongs_to :tree` (optional)
- `belongs_to :resolver, class_name: "User"` via `resolved_by` (optional)

**Enums:**

| Enum | Значення |
|------|----------|
| `status` | `active(0) / resolved(1) / ignored(2)` |
| `severity` | `low(0) / medium(1) / critical(2)` |
| `alert_type` | `fire(0) / drought(1) / vandalism(2) / system_fault(3) / pest(4) / seismic(5)` |
| `satellite_status` | `not_required / pending / verified / contradicted / unverifiable` |

**AASM:** `mark_resolved`, `ignore`, `reopen` (resolved/ignored→active).

**Унікальність:** `alert_type` унікальний в межах `[tree_id, status]` — захист від дублів.

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `resolve!(user:, notes:)` | Закрити тривогу + закрити пов'язаний MaintenanceRecord |
| `coordinates` | `{lat:, lng:}` через tree або cluster.geo_center |
| `actionable?` | Чи можна автоматично відреагувати |
| `requires_satellite_consensus?` | fire або drought → IoTeX ZK-верифікація |
| `dispatch_notifications!` | Надіслати SMS/Telegram/Push |
| `schedule_satellite_verification!` | Поставити в чергу Worker |
| `broadcast_new_alert` | Turbo Stream |

**Scopes:** `unresolved` (status_active), `critical`, `recent`.

---

### `AuditLog` — Незмінний Журнал Дій

**Призначення:** Повний compliance-журнал усіх дій. Підтримує blockchain-ланцюжок хешів та IPFS-архів.

**Асоціації:**
- `belongs_to :user`
- `belongs_to :organization`
- `belongs_to :auditable, polymorphic: true` (optional)

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `action` | string | Назва дії |
| `ip_address` | string | IP ініціатора |
| `metadata` | jsonb | Контекст дії |
| `chain_hash` | string | SHA-256 попереднього запису + payload (blockchain-ланцюг) |
| `ipfs_cid` | string | IPFS CID при архівуванні |
| `l1_anchor_tx_hash` | string | TX хеш на Ethereum L1 |

**Класові методи:**

| Метод | Опис |
|-------|------|
| `record_async!(attrs)` | Async-запис через Worker |
| `bulk_record!(entries)` | Bulk insert_all |
| `verify_chain_integrity(org_id)` | Перевірка ланцюжка хешів |

**Scopes:** `recent`, `archived` (ipfs_cid присутній), `not_archived`, `by_action`, `by_user`, `by_ip`, `for_period`.

---

### `MaintenanceRecord` — Журнал Обслуговування

**Призначення:** Фізична дія лісника в полі (Proof of Care). Прикріплені фото з GPS.

**Асоціації:**
- `belongs_to :user`
- `belongs_to :maintainable, polymorphic: true` (Tree або Gateway)
- `belongs_to :ews_alert` (optional)
- `has_many_attached :photos` (Active Storage, ≤ 5 МБ, JPEG/PNG/HEIC)

**Enum `action_type`:**

| Тип | Опис |
|-----|------|
| `anchor_replacement` | Заміна Ti-6Al-4V анкера |
| `capsule_swap` | Заміна STM32-капсули |
| `enzyme_replenishment` | Поповнення ферментів (GOx/Laccase) |
| `gateway_repair` | Ремонт Королеви |
| `sensor_calibration` | Калібровка датчиків |
| `vandalism_repair` | Ремонт після вандалізму |
| `inspection` | Плановий огляд |
| `tree_health_assessment` | Оцінка стану дерева |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `performed_at` | datetime | Час виконання (≤ now) |
| `notes` | text | Опис (≥ 10 символів) |
| `latitude` / `longitude` | decimal | GPS координати патрульного |
| `hardware_verified` | boolean | Обов'язкове підтвердження |
| `biomass_yield_kg` | decimal | Вимірювання біомаси (для tokenomics) |
| `labor_hours` | decimal | Витрачений час |
| `parts_cost` | decimal | Вартість запчастин |

**Методи:** `total_cost` (labor + parts), `trigger_ecosystem_healing!`.

---

## 🌱 8. Seeds — Початковий Стан Системи

Порядок видалення при очищенні (від листя до кореня):

```
AuditLog, Session, Identity
ActuatorCommand, MaintenanceRecord
BlockchainTransaction, TelemetryLog, GatewayTelemetryLog, AiInsight, EwsAlert
Wallet, DeviceCalibration
Actuator, HardwareKey
Tree, TinyMlModel, TreeFamily
Gateway
ParametricInsurance, NaasContract
BioContractFirmware
Cluster, User, Organization
```

**Початкові організації:** `ActiveBridge` + `EcoFuture Fund`

**Початкові ролі:**
- `oracle.executioner@system.silken.net` — super_admin, системний бот (без org)
- `admin@silken.net` — super_admin, Архітектор платформи
- `alexey@activebridge.org` — admin, ActiveBridge (access_level :organization)
- `forester@activebridge.org` — forester (access_level :field)
- `investor@ecofuture.fund` — investor (access_level :read_only)

**Початковий Cluster:** "Черкаський бір" — `region: "Центральна Україна"`, timezone: `Europe/Kyiv`, fire threshold: 60°C.

---

## 📊 9. Ключові Індекси

### Критичні індекси продуктивності

| Таблиця | Індекс | Тип | Призначення |
|---------|--------|-----|-------------|
| `ai_insights` | `idx_ai_insights_unique_report` | UNIQUE BTREE | analyzable + date + type + model_source |
| `ai_insights` | `idx_ai_insights_polymorphic_type_date` | BTREE | Пошук по типу та даті |
| `ai_insights` | `idx_ai_insights_reasoning_gin` | GIN | Повнотекстовий пошук в reasoning |
| `ai_insights` | `index_ai_insights_on_source_log_ids` | GIN | Пошук по масиву log IDs |
| `telemetry_logs` | `idx_telemetry_logs_bio_status_created` | BTREE (ONLY) | Фільтр аномалій |
| `telemetry_logs` | `idx_telemetry_logs_piezo_created` | BTREE (ONLY) | Сейсмічний моніторинг |
| `telemetry_logs` | `idx_telemetry_logs_oracle_dispatched` | PARTIAL | oracle_status = 'dispatched' |
| `telemetry_logs` | `idx_telemetry_logs_oracle_failed` | PARTIAL | oracle_status = 'failed' |
| `gateway_telemetry_logs` | `idx_gateway_telemetry_logs_queen_uid_created` | BTREE (ONLY) | Зв'язок через uid |
| `actuator_commands` | `index_actuator_commands_on_idempotency_token` | UNIQUE | Захист від дублів |
| `actuator_commands` | `index_actuator_commands_on_expires_at` | PARTIAL | status IN (0,1) |
| `audit_logs` | `index_audit_logs_on_org_and_created` | BTREE DESC | Пагінація аудиту |
| `audit_logs` | `index_audit_logs_on_ip_address` | PARTIAL | ip_address IS NOT NULL |
| `bio_contract_firmwares` | `index_bio_contract_firmwares_on_is_active` | PARTIAL | is_active = true |
| `blockchain_transactions` | `index_blockchain_transactions_on_wallet_id` | BTREE | FK lookup по wallet |
| `blockchain_transactions` | `index_blockchain_transactions_on_wallet_id_and_status` | BTREE | Фільтр транзакцій по статусу для wallet |
| `blockchain_transactions` | `index_blockchain_transactions_on_cluster_id` | BTREE | FK lookup по cluster (slashing-аудит) |
| `blockchain_transactions` | `index_blockchain_transactions_on_tx_hash` | PARTIAL (WHERE tx_hash IS NOT NULL) | `BlockchainConfirmationWorker` lookup; виключає pending/processing |
| `blockchain_transactions` | `index_blockchain_transactions_on_block_number` | BTREE | Запити по номеру блоку |
| `blockchain_transactions` | `index_blockchain_transactions_on_confirmed_at` | BTREE | Часові запити підтверджених TX |
| `blockchain_transactions` | `index_blockchain_transactions_on_sourceable` | BTREE (sourceable_type, sourceable_id) | Поліморфний зворотній lookup |
| `blockchain_transactions` | `index_blockchain_transactions_on_chainlink_request_id` | BTREE | Chainlink Oracle correlation |

---

## 🗺️ 10. Карта Зв'язків (Entity Relationship Summary)

```
Organization
  ├── Users (restrict_with_error)
  ├── Clusters (destroy)
  │     ├── Trees (nullify)
  │     │     ├── Wallet (destroy)
  │     │     ├── HardwareKey (destroy)
  │     │     ├── DeviceCalibration (destroy)
  │     │     ├── TelemetryLogs (delete_all) ← PARTITION
  │     │     ├── EwsAlerts (delete_all)
  │     │     ├── MaintenanceRecords (delete_all)
  │     │     └── AiInsights polymorphic (delete_all)
  │     ├── Gateways (nullify)
  │     │     ├── HardwareKey (destroy)
  │     │     ├── GatewayTelemetryLogs (delete_all) ← PARTITION
  │     │     ├── Actuators (destroy)
  │     │     │     └── ActuatorCommands (delete_all) ← P1 Fix
  │     │     └── MaintenanceRecords (restrict_with_error)
  │     ├── NaasContracts (restrict_with_error)
  │     ├── ParametricInsurances (restrict_with_error)
  │     ├── EwsAlerts (delete_all)
  │     └── AiInsights polymorphic (delete_all)
  ├── Wallets (direct FK, delete_all)
  │     └── BlockchainTransactions (delete_all) ← PARTITION
  └── AuditLogs (delete_all)

User
  ├── Sessions (destroy)
  ├── Identities (destroy)
  ├── MaintenanceRecords (restrict_with_error)
  └── AuditLogs (restrict_with_error)

TreeFamily
  ├── Trees (restrict_with_error)
  ├── TinyMlModels (nullify)
  └── BioContractFirmwares (nullify)

Polymorphic:
  AiInsight.analyzable → Tree | Cluster
  MaintenanceRecord.maintainable → Tree | Gateway
  BlockchainTransaction.sourceable → NaasContract | ParametricInsurance
  AuditLog.auditable → any model
  HardwareKey → Tree (via did) | Gateway (via uid)
```

---

## 🏗️ 11. Архітектурні Принципи БД

| Принцип | Реалізація |
|---------|-----------|
| **Hot Path без валідацій** | `TelemetryLog`, `GatewayTelemetryLog` — валідації в сервісі, не в AR |
| **Денормалізація для N+1 Kill** | `latest_stress_index`, `latest_voltage_mv`, `active_trees_count`, `health_index` |
| **GREATEST для race conditions** | `mark_seen!` в Tree та Gateway — атомарне оновлення без дублів |
| **delete_all для масових таблиць** | Телеметрія, тривоги, логи, ActuatorCommands — уникнення OOM при DELETE |
| **restrict_with_error для фінансів** | NaasContract, ParametricInsurance, Users — захист аудит-слідів |
| **Партиціонування по місяцях** | telemetry_logs, gateway_telemetry_logs, blockchain_transactions — прунінг старих даних |
| **Counter Cache** | `active_trees_count` в Cluster — уникнення COUNT на мільйонах рядків |
| **Поліморфізм** | AiInsight, MaintenanceRecord, AuditLog, BlockchainTransaction |
| **PostGIS GIST** | Cluster.geo_boundary — O(log n) геопросторовий пошук |
| **AR Encryption + Redis Cache** | HardwareKey.aes_key_hex — шифрування в БД + `cached_binary_key` у Redis (TTL 15 хв) |
| **BigDecimal в JSONB** | TinyMlModel accuracy_score/threshold — уникнення Float похибок |
| **Partial Index для sparse поля** | `blockchain_transactions.tx_hash WHERE tx_hash IS NOT NULL` — виключає рядки без tx_hash (pending/processing) |