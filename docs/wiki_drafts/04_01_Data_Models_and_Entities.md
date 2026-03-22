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

- **Database Locking:** При одночасному надходженні тисяч пакетів телеметрії, оновлення балансу `Wallet` вимагає `pessimistic locks` (`lock!("FOR UPDATE")`), щоб уникнути race conditions при нарахуванні балів росту. Моніторити Connection Pool.
- **Partition Automation:** Таблиці `telemetry_logs` та `gateway_telemetry_logs` партиціоновані вручну по місяцях. Необхідний `PartitionMaintenanceWorker` для автоматичного створення нових партицій наперед.
- **HardwareKey Decrypt Cache:** При мільйонах пакетів/хв десеріалізація зашифрованих ключів AR Encryption створює навантаження на CPU. Рекомендується Redis-кеш binary_key з TTL 5-15 хв + інвалідація при `rotate_key!`.

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

Поточні партиції: `y2026m01` → `y2026m06` + `_default` (для старих/нових даних).

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
| `binary_previous_key` | Попередній ключ у байтах (Grace Period) |
| `rotate_key!` | М'яка ротація: старий → `previous_aes_key_hex`, новий генерується |
| `clear_grace_period!` | Очищення `previous_aes_key_hex` після підтвердження синхронізації |
| `owner` | `tree || gateway` |

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
- `has_many :commands, class_name: "ActuatorCommand"`

**Enums:**

| Enum | Значення |
|------|----------|
| `device_type` | `water_valve / alarm_siren / led_marker / camera / vibration_sensor / other` |
| `state` | `idle / active / offline / maintenance_needed` |

**AASM:** `activate` (idle→active), `deactivate` (active→idle), `go_offline`, `report_fault` (→maintenance_needed).

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
| `status` | `pending(0) / processing(1) / sent(2) / confirmed(3) / failed(4)` |

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
  │     │     │     └── ActuatorCommands (destroy)
  │     │     └── MaintenanceRecords (restrict_with_error)
  │     ├── NaasContracts (restrict_with_error)
  │     ├── ParametricInsurances (restrict_with_error)
  │     ├── EwsAlerts (delete_all)
  │     └── AiInsights polymorphic (delete_all)
  ├── Wallets (direct FK, delete_all)
  │     └── BlockchainTransactions (delete_all)
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
| **delete_all для масових таблиць** | Телеметрія, тривоги, логи — уникнення OOM при DELETE |
| **restrict_with_error для фінансів** | NaasContract, ParametricInsurance, Users — захист аудит-слідів |
| **Партиціонування по місяцях** | telemetry_logs, gateway_telemetry_logs — прунінг старих даних |
| **Counter Cache** | `active_trees_count` в Cluster — уникнення COUNT на мільйонах рядків |
| **Поліморфізм** | AiInsight, MaintenanceRecord, AuditLog, BlockchainTransaction |
| **PostGIS GIST** | Cluster.geo_boundary — O(log n) геопросторовий пошук |
| **AR Encryption** | HardwareKey.aes_key_hex — non-deterministic шифрування в БД |
| **BigDecimal в JSONB** | TinyMlModel accuracy_score/threshold — уникнення Float похибок |
