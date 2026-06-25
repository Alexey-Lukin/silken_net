# 04_01: Моделі Даних та Сутності

## 🎯 Мета

Зафіксувати повну структуру реляційної бази даних (PostgreSQL) та ActiveRecord моделей для моноліту Ruby on Rails 8.1. Цей документ є **вичерпним довідником** всіх 36 моделей (27 ядра + 9 шар Codex / Lore — Realm, Node, Citation у Phase 1; Comment, Attunement у Phase 2; Fraction у Phase 3; Match у Phase 4; Discovery, DiscoveryRule у Phase 5), 6 concerns, ключових індексів, AASM-машин стану та seeds-стану системи. Визначає, як фізичні об'єкти (дерева, шлюзи) та абстрактні концепції (контракти, токени, аудит, lore-вузли) пов'язані між собою в єдину Кіберфізичну Державу SilkenNet.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Схема БД затверджена, міграції написані, поліморфні зв'язки та індекси оптимізовані для planetary-scale highload. Відкрите: SSOT Drift Register моніторинг (§12) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Фізичний рівень (Soldier/Queen DID, RTC) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (сервіси над моделями) |
| [`03_06` — Factory Flashing and Key Provisioning](03_06_Factory_Flashing_and_Key_Provisioning) | HardwareKey HKDF/K_seed деривація (03_06 §2/§3): aes_key, lorenz_seed |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Web3-економіка (Wallet, BlockchainTransaction) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (SSOT Drift Register §12) |

### Конвенція впорядкування розділів

1. **§0 PostgreSQL Інфраструктура** — extensions, тригери, партиціонування (horizontal infra, не модель).
2. **§1 Concerns** — повторно вживані mixins (`include` у моделях). Свідомо перед моделями: модель може посилатися на concern у власному рядку.
3. **§2–§7** — domain-grouped моделі за **онтологічними шарами** реальної системи:
   - §2 Біологічний (TreeFamily, Tree, Cluster) — фізичний об'єкт моніторингу
   - §3 Апаратний (Gateway, HardwareKey, DeviceCalibration, TelemetryLog, GatewayTelemetryLog) — IoT-edge
   - §4 AI / OTA / Актуатори (TinyMlModel, BioContractFirmware, Actuator, ActuatorCommand) — інтелект та фізична відповідь
   - §5 Люди та Організації (Organization, User, Session, Identity) — соціальний шар
   - §6 Економічний (Wallet, BlockchainTransaction, NaasContract, ParametricInsurance) — токеноміка
   - §7 Інтелект та Аудит (AiInsight, EwsAlert, AuditLog, MaintenanceRecord, EthereumAnchor, SystemParameter, ProvisioningSession) — спостережуваність + governance
4. **§7b Codex (Lore Layer)** — окремий шар, не на критичному шляху телеметрії. Read-only outbound полі-морфні посилання на core-моделі.
5. **§8 Seeds, §9 Індекси, §10 Карта зв'язків, §11 Архітектурні Принципи, §12 SSOT Drift Register** — horizontal cross-cuts (не належать до конкретного домену; стосуються всіх моделей одразу).

> **Anti-pattern, якого уникаємо:** змішувати моделі з різних доменів в одній секції лише за схожою назвою (наприклад, `BlockchainTransaction` живе в §6 Економіка, а `EthereumAnchor` — в §7 Аудит, хоч обидва "blockchain-related", бо відповідальність різна: одна — фінансовий tx, інша — read-only L1 evidence).

---

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [0. PostgreSQL Інфраструктура](#-0-postgresql-інфраструктура) — extensions, тригери, партиціонування (4 таблиці), TimescaleDB rationale
- [1. Concerns](#-1-concerns) — 6 mixin'ів (EthAddressValidatable, Firmwareable, GeoLocatable, HasArgon2Password, NormalizeIdentifier, OtaChunkable)
- [2. Біологічний Рівень](#-2-біологічний-рівень) — TreeFamily, **Tree** (Soldier), Cluster
- [3. Апаратний Рівень](#-3-апаратний-рівень) — **Gateway** (Queen), HardwareKey, DeviceCalibration, **TelemetryLog** (partitioned), GatewayTelemetryLog (partitioned)
- [4. AI / OTA / Актуатори](#-4-ai--ota--актуатори) — TinyMlModel, BioContractFirmware, Actuator, ActuatorCommand
- [5. Люди та Організації](#-5-люди-та-організації) — Organization, User, Session, Identity
- [6. Економічний Рівень](#-6-економічний-рівень) — Wallet, **BlockchainTransaction** (partitioned), NaasContract, ParametricInsurance
- [7. Інтелект та Аудит](#-7-інтелект-та-аудит) — AiInsight, EwsAlert, AuditLog, MaintenanceRecord, EthereumAnchor, SystemParameter, ProvisioningSession
- [7b. Codex — Lore Layer (Кодекс Архетипів)](#-7b-codex--lore-layer-кодекс-архетипів) — Realm, Node, Citation, Comment, Attunement, Fraction, **Match** (partitioned), Discovery, DiscoveryRule
- [8. Seeds — Початковий Стан Системи](#-8-seeds--початковий-стан-системи)
- [9. Ключові Індекси](#-9-ключові-індекси)
- [10. Карта Зв'язків](#-10-карта-звязків)
- [11. Архітектурні Принципи БД](#-11-архітектурні-принципи-бд)
- [12. SSOT Drift Register (Doc ↔ Schema Sync)](#-12-ssot-drift-register-doc--schema-sync)
<!-- TOC:AUTO:END -->

> **Bold** = модель/таблиця з партиціонуванням RANGE BY `created_at`. Завжди передавайте `created_at_iso` у відповідні воркери для partition pruning.

---

## 🏛️ 0. PostgreSQL Інфраструктура

### Розширення

| Розширення | Призначення |
|------------|-------------|
| `postgis` | Геопросторові запити (ST_Contains, ST_MakePoint, GIST-індекси) |
| `pgcrypto` | Криптографічні функції на рівні БД |
| `uuid-ossp` | UUID генерація |
| `pg_trgm` | Trigram-нечіткий пошук назв (`codex_nodes.title_uk/_en` через GIN) |

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
| `codex_matches` | RANGE by month | Codex Battle Arena (Phase 4) — 100M+ duel-рядків очікувано на масштабі. Додано в `PartitionMaintenanceWorker.PARTITIONED_TABLES` (див. [`04_02 §11`](04_02_Business_Logic_and_Services) DOC-R.11) |

Поточні партиції: для трьох core-таблиць — `y2026m01` → `y2026m06` + `_default`. Для `codex_matches` (Phase 4) — `y2026m04` → `y2026m09` (запущена пізніше) + `_default`.

**Автоматизація:** `PartitionMaintenanceWorker` (черга `default`) щодня о 02:30 UTC гарантує існування партицій для **поточного та наступного місяця** для всіх **чотирьох** партиційованих таблиць (`telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`, `codex_matches`). Назва партиції формується за шаблоном `<table>_y<YYYY>m<MM>` (напр. `blockchain_transactions_y2026m04`). Операція ідемпотентна — `CREATE TABLE IF NOT EXISTS`. SSOT константа: `PartitionMaintenanceWorker::PARTITIONED_TABLES`. При додаванні нової RANGE-таблиці — внесіть її **і сюди (§0)**, і у `PARTITIONED_TABLES`, і у `spec/workers/partition_maintenance_worker_spec.rb` (очікуване число OK-ліній = `tables × 2 months`).

> **📝 Розглянута альтернатива — TimescaleDB (E.37):**
> Для IoT-телеметрії такого масштабу розглядалось розширення TimescaleDB (hypertables, continuous aggregates, автоматична компресія до 90% економії місця). **Чому відхилено для поточного TRL:**
> - Нативний PostgreSQL RANGE partitioning повністю покриває потреби TRL 6-8 (мільйони рядків/місяць, partition pruning через `find_with_partition_pruning`)
> - TimescaleDB додає зовнішню залежність та ускладнює деплой (Kamal Docker, Akash SDL, GCP Cloud SQL)
> - Continuous Aggregates можна замінити `AiInsight` воркером (вже реалізовано: денна агрегація)
> - При масштабуванні за 100M+ рядків/місяць — переглянути рішення (TimescaleDB або ClickHouse)

---

## 🔧 1. Concerns

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

## 🌲 2. Біологічний Рівень

### `TreeFamily` — Генетичний Шаблон

**Призначення:** Вид дерева (порода). Містить біологічні константи для Атрактора Лоренца та TinyML.

**Асоціації:**
- `has_many :trees, dependent: :restrict_with_error` — захист: не можна видалити, поки є живі носії геному

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Унікальна назва (напр. "Сосна Звичайна") |
| `scientific_name` | string | Латинська назва (nullable, для міжнародних контрактів) |
| `baseline_impedance` | integer | Базовий імпеданс ксилеми (Ω) |
| `critical_z_min` | decimal | Мінімум Z-значення атрактора (нижня межа гомеостазу) |
| `critical_z_max` | decimal | Максимум Z-значення атрактора (`> critical_z_min`) |
| `carbon_sequestration_coefficient` | decimal | Коефіцієнт секвестрації (> 0) для зваженого нарахування SCC |
| `biological_properties` | jsonb | `sap_flow_index`, `bark_thickness`, `foliage_density`, `fire_resistance_rating`, `optimal_z_target` |

**Ключові методи:**

| Метод | Повертає | Опис |
|-------|----------|------|
| `attractor_thresholds` | `{min:, max:, optimal:, baseline:}` | Параметри для Lorenz attractor (включає `optimal_z_target` з FW.8) |
| `attractor_thresholds_cached` | Hash | Кешована версія (24 год) для hot path |
| `effective_optimal_z_target` | Float | [FW.8] `optimal_z_target || 29.0` — per-species sweet spot або global default |
| `death_threshold_impedance` | Float | `baseline_impedance * 0.3` — "Межа Смерті" |
| `healthy_z?(z_value)` | Boolean | Чи Z у межах гомеостазу |
| `stress_level(impedance)` | Symbol | `:normal / :warning / :critical / :dead` |
| `weighted_growth_points(raw)` | Float | `raw * carbon_sequestration_coefficient` |
| `display_name` | String | "Quercus robur (Дуб звичайний)" або просто назва |

**Callbacks:** `after_update :invalidate_thresholds_cache` — при зміні порогів Атрактора або `biological_properties` (включає `optimal_z_target`).

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
| `peaq_did` | string | peaq DID-ідентифікатор для Proof of Growth |
| `altitude` | numeric | Висота над рівнем моря (м) |
| `firmware_version` | string | Версія прошивки STM32 (SemVer) |

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
- `GLOBAL_LORENZ_Z_MIN = 2.0` — [FW.8] global fallback (дзеркало `BioContract::CRITICAL_Z_MIN`)
- `GLOBAL_LORENZ_Z_MAX = 45.0` — [FW.8] global fallback
- `GLOBAL_LORENZ_Z_OPTIMAL = 29.0` — [FW.8] global fallback

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `mark_seen!(voltage_mv)` | Hot path: `GREATEST` атомарне оновлення `last_seen_at` + `latest_voltage_mv`. Обходить колбеки. |
| `current_stress` | Читає `latest_stress_index` (денормалізовано, без N+1) |
| `charge_percentage` | `(voltage - MIN) / (MAX - MIN) * 100` |
| `low_power?` | `voltage > 0 && voltage < 3300` |
| `under_threat?` | `ews_alerts.unresolved.exists?` |
| `broadcast_map_update` | Turbo Stream → `geospatial_matrix` |
| `effective_lorenz_thresholds` | [FW.8] `{ min:, max:, optimal: }` з 3-рівневим пріоритетом: Cluster override → TreeFamily → Global default. Використовується `TelemetryUnpackerService#check_z_divergence!` та `OtaPackagerService.build_threshold_config_block`. |

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
| `geojson_polygon` | jsonb | GeoJSON-представлення (синхронізується тригером → див. примітку нижче) |
| `health_index` | decimal | Денормалізований індекс `1.0 - stress_index` (0..1) |
| `entropy_score` | float | Нормалізована ентропія Шеннона Z-розподілу (0..1). Оновлюється `ClusterEntropyAnalyzerWorker` |
| `active_trees_count` | bigint | Counter cache (оновлюється Tree callbacks) |
| `climate_type` | string | Кліматичний тип зони (напр. "temperate_continental") |
| `environmental_settings` | jsonb | `custom_fire_threshold`, `seismic_sensitivity_threshold`, `timezone`, `lorenz_overrides_by_species` |

> **`lorenz_overrides_by_species`** [FW.8] — JSONB hash з per-species Lorenz thresholds для цього кластера. Ключ: `scientific_name` (string); значення: `{ "z_min": Float, "z_max": Float, "z_optimal": Float }`. Дозволяє override для конкретного виду тільки в цьому кластері. Підлягає валідації через `validate_lorenz_overrides_by_species`. Приклад:
> ```json
> {
>   "Pinus sylvestris": { "z_min": 1.5, "z_max": 46.0, "z_optimal": 30.0 },
>   "Quercus robur":    { "z_min": 3.0, "z_max": 42.0, "z_optimal": 27.0 }
> }
> ```

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
| `lorenz_overrides_for(scientific_name)` | [FW.8] Повертає `{ min:, max:, optimal: }` або `nil` для даного виду. Читає `lorenz_overrides_by_species[scientific_name]`. |

**Scopes:** `alphabetical`, `containing_point(lat, lng)`, `under_threat`.

> **📝 PostGIS Оптимізація — Generated Column vs Тригер (E.36):**
> Поточна синхронізація `geojson_polygon` → `geo_boundary` використовує PL/pgSQL тригер `sync_cluster_geo_boundary()`. Починаючи з PostgreSQL 12, для таких прямих трансформацій рекомендовано використовувати **Generated Columns**:
> ```sql
> ALTER TABLE clusters
> ADD COLUMN geo_boundary geometry(Polygon, 4326)
> GENERATED ALWAYS AS (ST_GeomFromGeoJSON(geojson_polygon)) STORED;
> ```
> **Переваги:** працює на рівні C-рушія БД (швидше), не потребує підтримки тригерних функцій, автоматично оновлюється при зміні `geojson_polygon`. **Обмеження:** generated column не може посилатися на інші generated columns; GIST-індекс на generated column підтримується. **Статус:** Оптимізація для Post-TRL 8.

---

## ⚙️ 3. Апаратний Рівень

### `Gateway` — Королева (LoRa mesh Шлюз)

**Включає:** `AASM`, `Firmwareable`, `GeoLocatable`, `NormalizeIdentifier`

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `cluster` | `belongs_to` (required, NOT NULL) | Сектор відповідальності |
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
| `last_attested_at` | datetime | **[L1 QATT]** Останній батч з валідним Ed25519-підписом Королеви (wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)); `nil` = шлюз на L0 |
| `latest_voltage_mv` | integer | Денормалізована напруга |
| `firmware_version` | string | Версія прошивки STM32 (SemVer) |
| `altitude` | numeric | Висота над рівнем моря (м) |

> **Примітка:** `firmware_hash` НЕ є полем Gateway і наразі не існує як колонка — UI-компонент
> (`components/gateways/show.rb`) робить `try(:firmware_hash)` із safe fallback `"—"`. Хеші OTA-артефактів
> живуть у `BioContractFirmware` / `TinyMlModel` (`binary_sha256`), окремої моделі `Firmware` немає.

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

**Призначення:** Per-device криптографічний матеріал. Після **ARCH.42 Variant B (2026-05-23)** ключі розділені по каналах:
- **Tree (Soldier) HardwareKey:** AES-128 ключ (16 байт = 32 HEX) для LoRa Soldier↔Queen каналу.
- **Gateway (Queen) HardwareKey:** AES-256 ключ (32 байти = 64 HEX) для CoAP Queen↔Rails магістралі.

Обидва секрети шифруються AR Encryption (non-deterministic) і деривуються незалежно firmware ↔ backend через HKDF з `PROVISIONING_MASTER_KEY` з різними info-strings (domain separation). Плюс **Lorenz `K_seed` [SEC.11]** (32 байти) — окрема per-device деривація для атрактора. Жоден з секретів не передається через мережу.

**Асоціації:**
- `belongs_to :tree` via `device_uid/did` (optional)
- `belongs_to :gateway` via `device_uid/uid` (optional)
- `delegate :organization, :cluster, to: :owner`

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `device_uid` | string | Унікальний ідентифікатор пристрою |
| `aes_key_hex` | string (encrypted) | **Conditional length за `owner` type** (post-ARCH.42): **32 HEX символи** (AES-128, 16 байт) для Tree (LoRa, HKDF info `"silken-aes-128-lora-key"`); **64 HEX символи** (AES-256, 32 байти) для Gateway (CoAP, HKDF info `"silken-aes-256-device-key"`). AR Encryption non-deterministic. Cross-ref [`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning). Validation: `length: { in: [32, 64] }` + custom validator на узгодженість з owner type |
| `previous_aes_key_hex` | string (encrypted) | Попередній AES ключ (Grace Period при ротації); same conditional length |
| `lorenz_seed_hex` | string (encrypted) | **[SEC.11]** 64 HEX символи `K_seed` для атрактора Лоренца. AR Encryption non-deterministic. HKDF info-string: `"silken-lorenz-seed\|<DID>"`, salt: `"silken-lorenz-v1"`. Validated `presence: true` (hard cutover — кожен пристрій ОБОВ'ЯЗКОВО має K_seed). Cross-ref [`03_06 §3`](03_06_Factory_Flashing_and_Key_Provisioning) |
| `ed25519_public_key_hex` | string | Публічний ключ Gateway: (а) M2M auth (`POST /api/v1/auth/m2m_token`); (б) **[L1 QATT]** верифікація Ed25519-підпису CoAP-батчів — wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security). Тільки для Gateway, не Tree. Приватна сім'я (`EDSK`) — лише у Protected Flash пристрою; бекенд її НЕ знає (НЕ HKDF-від-master — інакше L1 не захищав би від backend-compromise) |
| `rotated_at` | datetime | Час останньої ротації |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `binary_key` | `[aes_key_hex].pack("H*")` — мемоізовано (**16 байт AES-128 для Tree, 32 байти AES-256 для Gateway** після ARCH.42) |
| `binary_lorenz_seed` | **[SEC.11]** `[lorenz_seed_hex].pack("H*")` — мемоізовано (32 байти `K_seed`); входить у `SilkenNet::SeedDerivation.derive_initial_state(seed_bin, epoch_day)` |
| `cached_binary_key` | In-process LRU (SinLruRedux::ThreadSafeCache, max 10 000 entries). Ключ: `versioned_cache_key` — включає `updated_at` для самоінвалідації. Ключі не залишають Ruby-процес (немає Redis-serialize) |
| `versioned_cache_key` | `"#{device_uid}:v:#{updated_at.to_f}"` — при будь-якому `update!` `updated_at` змінюється → новий ключ → стара запис ніколи не збігається (Cache Key Versioning). Усуває race condition між `COMMIT` і `after_commit` |
| `binary_previous_key` | Попередній AES ключ у байтах (Grace Period) |
| `rotate_key!` | М'яка ротація: старий → `previous_aes_key_hex`, новий генерується. Deprecated — використовуйте `HardwareKeyService.rotate` |
| `clear_grace_period!` | Очищення `previous_aes_key_hex` після підтвердження синхронізації |
| `owner` | `tree || gateway` |

**Callbacks:** немає cache-інвалідаційних callbacks (`after_commit :clear_key_cache` видалено). Інвалідація відбувається автоматично через `versioned_cache_key`.

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
- ~~`belongs_to :bio_contract_firmware` via `firmware_version_id`~~ — **вимкнено (E.62-патерн, mis-join trap)**: колонка зберігає wire-ідентифікатор (21B uint16 / CCM 4-бітний epoch-нібл), не автоінкрементний id; трекінг версій — SemVer-рядки

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `bio_status` | enum | `homeostasis(0) / stress(1) / anomaly(2) / tamper_detected(3)` |
| `temperature_c` | decimal | Температура (°C) |
| `voltage_mv` | integer | Напруга EBFC (мВ) |
| `z_value` | decimal | Z-значення Атрактора Лоренца |
| `acoustic_events` | integer | Кількість акустичних подій (TinyML) |
| `mesh_ttl` | integer | Time-To-Live пакету в mesh-мережі (на прибутті; стартовий — 3 normal / 5 panic, дзеркало firmware `DEFAULT_TTL`/`PANIC_TTL`) |
| `panic` | boolean | **[FW.29]** Панічний пакет (PanicFlag, біт 7 StatusByte; default `false`). Єдина надійна wire-ознака паніки — `acoustic_events=255` колізує з FW.22-сатурацією |
| `queen_uid` | string | UID Королеви-ретранслятора |
| `oracle_status` | enum | **[BLOCKER-12 FIX]** `pending / dispatched / fulfilled / failed` (string-backed Rails enum з prefix `oracle_status_`). Забезпечує type safety, валідацію та автоматичні scope-методи (`oracle_status_dispatched`, `oracle_status_fulfilled` тощо). Default: `pending`. |
| `firmware_version_id` | integer | Версія прошивки з padding-байтів |
| `growth_points` | numeric | Нараховані очки зростання (raw) |
| `metabolism_s` | integer | Час метаболічного циклу (с) |
| `rssi` | integer | RSSI LoRa-каналу (дБм) |
| `sap_flow` | numeric | Потік соку ксилеми |
| `humidity` | numeric | **[HW.32]** Відносна вологість повітря (% RH, BME280) — climate frame, nullable |
| `pressure` | numeric | **[HW.32]** Атмосферний тиск (hPa, BME280) — nullable; барометр → раннє попередження про шторм |
| `vpd` | numeric | **[HW.32]** Vapor Pressure Deficit (kPa) — прямий confounder сокоруху (False-Slashing guard, [`05_05 §6/§7`](05_05_Slashing_and_Risk_Policy)). Hot-path: device шле VPD-індекс; nullable. ⚠️ НЕ входить у Lorenz-Z (DCI-guard) |
| `verified_by_iotex` | boolean | Підтверджено IoTeX W3bstream ZK-proof |
| `zk_proof_ref` | string | Посилання на ZK-proof IoTeX |
| `gateway_attested` | boolean | **[L1 QATT]** Рядок приїхав під валідним Ed25519-підписом Королеви (default `false`; wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security), ladder [`05_02`](05_02_Proof_of_Growth_Pipeline)) |
| `chainlink_request_id` | string | ID запиту Chainlink Oracle |
| `tamper_detected` | boolean | Спроба відкриття корпусу капсули |
| `cold_start_flag` | boolean | `true` якщо пакет перший після VBAT loss (initial_state від K_seed, не warm chain) |
| `lorenz_state_x/y/z` | float | Хвіст траєкторії Лоренца для chain-старту наступного пакету |
| `time_unsynced_fallback` | boolean | `true` якщо DCI mismatch відновлено через ARCH.41 epoch_day fallback (Soldier мав застарілий RTC після VBAT loss); `CMD_TIME_SYNC` downlink поставлено в чергу автоматично |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `relayed_via_mesh?` | `mesh_ttl < стартовий TTL типу пакета` (`panic? ? 5 : 3` — `INITIAL_TTL_PANIC/NORMAL`). До FW.29-персистенції давній default 5 позначав «релейнутим» кожен direct normal-пакет |
| `critical?` | `anomaly?` або `tamper_detected?` |
| `healthy?` | homeostasis + temp < 50 + acoustic < 20 |
| `optimal?` | healthy + voltage > 3600 + `\|z_value − 29.0\| ≤ 4.0` (`Tree::GLOBAL_LORENZ_Z_OPTIMAL` ± `OPTIMAL_Z_BAND`; реліктовий до-FW.8 діапазон 0.1..0.5 ретирувано) |
| `recovery_confirmed?` | `healthy? && tree.health_streak >= 3` |
| `.partition_pruned(iso, metric_caller:)` | **[S6.16]** One-Home pruning-логіки: chainable 1с-вікно по `created_at` (толерантне до секундної точності ISO — стандарт `BlockchainTransaction`) + облік degraded path лічильником `unpruned_lookups`. Воркери/сервіси/контролери делегують сюди, НЕ дублюють |

**Scopes:** `recent`, `anomalies`, `in_timeframe`, `vandalized`.

> ⚡ **KENOSIS TITAN:** Валідації видалено з hot path. Перевірка відбувається в `TelemetryUnpackerService.valid_sensor_data?` до INSERT.

> ⚠️ **CLEANUP CONSTRAINT [DOC.8]:** Будь-який cleanup-скрипт або ad-hoc DELETE на `telemetry_logs` **повинен виключати** записи з `oracle_status = 'dispatched'`. Ці записи очікують callback від Chainlink DON; видалення призведе до `RecordNotFound` у `OracleCallbacksController` → 5 марних retry → loss of mint. Канонічне виконання cleanup — `InsightGeneratorService.cleanup_old_logs!` (викликається з `InsightBatchCallbacks` на завершенні денного циклу). Не дублюйте логіку в нових воркерах — викликайте сервіс. Cross-ref: [`04_02 §3` InsightGeneratorService](04_02_Business_Logic_and_Services#insightgeneratorservice), [`05_02` — PATH 1 Oracle-driven](05_02_Proof_of_Growth_Pipeline#усі-шляхи-до-walletlock_and_mint-guard-inventory-doc7).

> ⚡ **PARTITION PRUNING INVARIANT [S6.16]:** `telemetry_logs` — RANGE-партиціонована по `created_at` (місячні партиції). PostgreSQL застосовує partition pruning **тільки** коли `WHERE` містить literal/parameter на `created_at`. Без цього → Global Partition Scan (`O(P × log N)`) — на масштабі мільярдів рядків це секунди замість мілісекунд.
>
> **Інваріант:** усі читачі `TelemetryLog` за PK повинні передавати `created_at_iso` (ISO 8601) разом з `id`. Sidekiq workers, що ставлять у чергу follow-up jobs, **зобов'язані** передавати `log.created_at.iso8601(6)` як аргумент.
>
> **Інвентар читачів:**
>
> | Читач | Файл | Шлях pruning | Source `created_at` |
> |-------|------|--------------|---------------------|
> | `IotexVerificationWorker#find_log` | `app/workers/iotex_verification_worker.rb` | ✅ manual `find_by(id:, created_at:)` | sidekiq arg `created_at_iso` |
> | `ChainlinkDispatchWorker#find_log` | `app/workers/chainlink_dispatch_worker.rb` | ✅ manual `find_by(id:, created_at:)` | sidekiq arg `created_at_iso` |
> | `StreamrBroadcastWorker` | `app/workers/streamr_broadcast_worker.rb` | ✅ manual `find_by(id:, created_at:)` | sidekiq arg `created_at_iso` |
> | `MintCarbonCoinWorker#find_telemetry_log` | `app/workers/mint_carbon_coin_worker.rb` | ✅ через `ApplicationWeb3Worker#find_telemetry_log_with_pruning` | sidekiq arg |
> | `SolanaMicroRewardWorker` | `app/workers/solana_micro_reward_worker.rb` | ✅ через `ApplicationWeb3Worker#find_telemetry_log_with_pruning` | sidekiq arg |
> | `Api::V1::OracleCallbacksController#find_telemetry_log` | `app/controllers/api/v1/oracle_callbacks_controller.rb` | ⚠️ pruning якщо `params[:created_at]` присутній; інакше degraded scan | Chainlink DON callback param |
> | `MintingRollbackService#find_telemetry_log` | `app/services/minting_rollback_service.rb` | ⚠️ pruning якщо `@created_at_iso` присутній; інакше degraded scan | admin tool / cold path |
> | `InsightGeneratorService.cleanup_old_logs!` | `app/services/insight_generator_service.rb` | ✅ range scan (`created_at <= threshold`) — pruning по верхній межі | scheduled cron |
> | `DailyAggregationWorker` | `app/workers/daily_aggregation_worker.rb` | ✅ `created_at: day_range` — 1-2 партиції | scheduled cron |
>
> **Observability (degraded path detector):** Counter `silkennet_telemetry_log_unpruned_lookups_total{caller}` інкрементується у трьох точках, де `created_at` може бути відсутнім або malformed:
> - `ApplicationWeb3Worker:missing_created_at_iso` / `:invalid_iso8601` — sidekiq worker не передав argument; **hot path → ALERT**.
> - `OracleCallbacksController:missing_created_at` / `:invalid_iso8601` — Chainlink DON callback без `created_at` query param; **hot path → ALERT** (виправити Chainlink Functions JS source).
> - `MintingRollbackService:missing_created_at_iso` / `:invalid_iso8601` — admin manual rollback; **cold path, acceptable**, але трекати для прозорості.
>
> Grafana alert rule (приклад): `rate(silkennet_telemetry_log_unpruned_lookups_total{caller=~"ApplicationWeb3Worker.*|OracleCallbacksController.*"}[5m]) > 0`.

---

### `GatewayTelemetryLog` — Діагностика Королеви

**Призначення:** Власна телеметрія шлюзу (батарея, температура, сигнал). Партиціонована.

**Асоціації:** `belongs_to :gateway, foreign_key: :queen_uid, primary_key: :uid`
> **Dual-key патерн:** AR-зв'язок використовує `queen_uid` → `gateways.uid` (бізнес-ключ). Колонка `gateway_id` (FK NOT NULL) існує в БД, але не використовується Rails — слугує для DB-level referential integrity. Запити через AR завжди йдуть через `uid`.

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `queen_uid` | string | UID Королеви |
| `voltage_mv` | numeric | Напруга батареї/сонячної панелі (мВ) |
| `temperature_c` | decimal | Температура корпусу (°C) |
| `cellular_signal_csq` | integer | Сила сигналу LTE (0-31, 99=unknown) |

**Константи:** `LOW_BATTERY_THRESHOLD=3300` мВ, `OVERHEAT_THRESHOLD=65` °C, `LOW_TEMPERATURE_THRESHOLD=-20` °C (LiFePO4 cut-off), `LOW_SIGNAL_THRESHOLD=5` CSQ.

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `signal_quality_percentage` | `(csq / 31.0) * 100` |
| `signal_dbm` | `2 * csq - 113` (формула 3GPP) |
| `critical_fault?` | Будь-яка з **чотирьох** констант перевищена (battery low, overheat, freeze, weak signal). Nil-safe: повертає `false` коли voltage/temperature/csq ще не зафіксовано (insert_all hot path). |

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
| `true_positive_rate` | decimal | **Accuracy** (correct ÷ total). Імена колонок легасі від ранньої схеми; модель не зберігає TP/FP/TN/FN роздільно, тож справжня статистична TPR недоступна. Read-side віддає через `#accuracy`. |
| `false_positive_rate` | decimal | **Error rate** (1 − accuracy). Поріг `drifting?` — > 0.15. Read-side віддає через `#error_rate`. |
| `total_predictions` | integer | Лічильник передбачень |
| `confirmed_predictions` | integer | Підтверджені передбачення |
| `target_pest` | string | Вид шкідника, на якого налаштована модель |
| `drift_checked_at` | timestamp | Час останньої перевірки дрейфу |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `accuracy_score` / `threshold` | BigDecimal з JSONB (уникає Float похибок) |
| `accuracy` | Read-side для `true_positive_rate` (correct ÷ total). Float, повертає `nil` якщо predictions ще не накопичено. |
| `error_rate` | Read-side для `false_positive_rate` (1 − accuracy). |
| `firmware_compatible?(version)` | `Gem::Version` порівняння |
| `activate!(percentage:)` | Деактивує інші версії, активує цю з відсотком |
| `record_prediction!(confirmed:)` | Drift tracking (інкремент `total_predictions`/`confirmed_predictions` + перерахунок accuracy/error_rate) |
| `drifting?` | `false_positive_rate > 0.15` (error_rate > 15% = drift) |
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
| `priority` | `low(0) / medium(1) / high(2) / override(3)` (prefix: true) |

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

## 👤 5. Люди та Організації

### `Organization` — Власник Лісових Активів

**Включає:** `EthAddressValidatable`

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `users` | `has_many, restrict_with_error` | Захист аудит-логів |
| `naas_contracts` | `has_many, restrict_with_error` | Фінансова цілісність |
| `clusters` | `has_many, dependent: :destroy` | Лісові масиви |
| `trees` | `has_many, through: :clusters` | Всі дерева |
| `wallets` | `has_many, dependent: :nullify` | Пряма магістраль (без 4-рівневого JOIN); `organization_id` обнуляється при видаленні Organization |
| `ews_alerts` | `has_many, through: :clusters` | Тривоги всіх кластерів (через `under_threat?`) |
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
| `telegram_chat_id` | string | Для Telegram сповіщень |
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

## 💰 6. Економічний Рівень

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
| `locked_balance` | decimal | Заморожені points (в процесі емісії). **Подвійне призначення:** (1) lock під час `lock_and_mint!` між Polygon-mint dispatch і `confirmed` AASM; (2) **finality-lag lock** — коли SCC вже мінтовано на Polygon, але тижневий L1 anchor (`EthereumAnchor`, крок #12) ще не зафіксував state root. У випадку Polygon reorg або catastrophic sidechain failure до anchor — токени технічно повертаються у `locked_balance` через `escalate_to_review`. Це запобігає double-spend сценарію, описаному в [`06_08 §2.2 Manual review terminal state`](06_08_Resilience_and_Failover_Policy). |
| `esg_retired_balance` | decimal | Списані балансом ESG-retired |
| `toucan_bridged_balance` | decimal | Bridged через Toucan Protocol |
| `crypto_public_address` | string | Polygon/Ethereum-адреса гаманця (EIP-55) |
| `solana_public_address` | string | Solana Base58-адреса (для мікро-нагород) |
| `hadron_kyc_status` | string | KYC статус Polygon Hadron (default: `pending`) |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `available_balance` | `balance - locked_balance` |
| `lock_funds!(amount)` | Переміщує з `balance` до `locked_balance` |
| `release_locked_funds!(amount)` | Повертає до `balance` |
| `finalize_spend!(amount)` | Зменшує `locked_balance` (після мінту) |
| `credit!(points)` | Зараховує з урахуванням `carbon_sequestration_coefficient` породи |
| `lock_and_mint!(points_to_lock, threshold, token_type)` | Повний цикл емісії SCC (курс — [`05_03`](05_03_Tokenomics_SCC_and_SFC)) |
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
| `status` | `pending(0) / processing(1) / confirmed(2) / failed(3) / sent(4) / manual_review(5)` |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `amount` | decimal | Сума (> 0) |
| `to_address` | string | Ethereum або Base58 (Solana) адреса |
| `blockchain_network` | string | `evm / solana / celo` |
| `tx_hash` | string | Хеш транзакції (required для sent/confirmed) |
| `gas_price` / `gas_used` | decimal | EVM-газ |
| `block_number` | bigint | Номер блоку |
| `nonce` | bigint | EVM nonce |
| `sent_at` | timestamp | Час відправлення в мемпул |
| `confirmed_at` | timestamp | Час підтвердження в блокчейні |
| `chainlink_request_id` | string | ID запиту Chainlink Oracle |
| `zk_proof_ref` | string | Посилання на ZK-proof IoTeX |
| `locked_points` | bigint | Заблоковані growth_points при мінтингу |
| `cumulative_gas_cost` | numeric | Накопичені витрати на газ |

**AASM:**
- `process` (pending→processing)
- `mark_as_sent(tx_hash)` (pending/processing→sent)
- `confirm(block_num, gas_cost)` (sent/processing→confirmed)
- `fail(reason)` (any→failed)
- `escalate_to_review(reason)` (pending/processing/sent/failed→manual_review) — **[DOUBLE-SPEND GUARD]**: tx_hash вже існує або стан на блокчейні невідомий; кошти залишаються у `locked_balance` до ручної звірки
- `scope :in_flight` (recent `:pending`/`:sent`) — **[ARCH.45]** intent-marker idempotency guard (дзеркало `EthereumAnchor.in_flight`): на retry ловить on-chain↔DB crash-window для slash / Solana payout проти double-pay / double-burn ([`04_02 §4/§10`](04_02_Business_Logic_and_Services))

**Методи:** `find_with_partition_pruning(id, created_at = nil)` _(клас)_, `explorer_url`, `solana_network?`, `celo_network?`, `broadcast_status_change`.

> **`find_with_partition_pruning`** — partition-aware lookup: при наявності `created_at` додає `WHERE created_at IN [time, time+1s)`, дозволяючи PostgreSQL звернутись до однієї партиції (`O(log N)`) замість глобального сканування (`O(P×log N)`). Використовується в `ApplicationWeb3Worker#find_blockchain_tx_with_pruning` та контролері (параметр `?created_at=ISO8601`).

**Масштабування:** Таблиця переведена на PostgreSQL Declarative RANGE Partitioning по `created_at` (місячні партиції). Composite PK `(id, created_at)` — вимога partitioning. `self.primary_key = "id"` — Rails використовує `id` для `dom_id` та асоціацій. Всі 8 індексів перестворені (автоматично пропагуються на партиції). `PartitionMaintenanceWorker` тепер підтримує `blockchain_transactions` поряд з `telemetry_logs` та `gateway_telemetry_logs`.

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
| `start_date` / `end_date` | timestamp | Строки контракту |
| `emitted_tokens` | numeric | Кількість емітованих SCC (default: 0) |
| `cancelled_at` | timestamp | Час відміни контракту |
| `hadron_asset_id` | string | ID активу на Polygon Hadron |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `check_cluster_health!` | Оцінює здоров'я кластера (Worker); делегує в `ContractHealthCheckService`, повертає verdict `:healthy`/`:degraded`/`:blackout`/`:skipped` (SLASH-1 — breach асинхронний, не тут) |
| `calculate_early_exit_fee` | Штраф за дострокове розірвання |
| `calculate_prorated_refund` | Пропорційне повернення |
| `terminate_early!` | Дострокове розірвання |
| `current_yield_performance` | Поточна прибутковість |
| `active_threats?` | Загрози в кластері |
| `insurance_premium_amount` | `total_funding * INSURANCE_PREMIUM_RATE` (5%) — обчислювальний метод |
| `forester_share_amount` | `total_funding * 0.95` — частка лісника (обчислювальний метод) |
| `self.total_insurance_premiums` | Σ премій (5%) по активованих (active/fulfilled/breached) контрактах — DB-джерело premium-показника Real-Yield звіту ([`04_03`](04_03_REST_API_v1_Reference) `reports#financial_summary`); off-chain USDC-факт, НЕ on-chain подія |

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

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `payout_amount` | decimal | Сума виплати |
| `threshold_value` | decimal | Поріг спрацювання (0..100) |
| `required_confirmations` | integer | Кількість підтверджень |
| `etherisc_policy_id` | string | ID страхового контракту Etherisc Oracle (nullable) |

**Ключові методи:** `evaluate_daily_health!(target_date)`, `activate_payout!(percentage)`, `recipient_wallet_address`, `uses_etherisc?` (`etherisc_policy_id.present?`).

---

## 🚨 7. Інтелект та Аудит

### `AiInsight` — Висновок Оракула

**Призначення:** Результат роботи `InsightGeneratorService` — щоденний звіт або прогноз для Tree або Cluster.

**Асоціації:** `belongs_to :analyzable, polymorphic: true` (Tree або Cluster)

**Enum `insight_type`:**

| Значення | Int | Опис |
|----------|-----|------|
| `daily_health_summary` | 0 | Щоденний підсумок (stress_index) — РЕАЛЬНІСТЬ |
| `drought_probability` | 1 | Ймовірність посухи — ПРОГНОЗ |
| `carbon_yield_forecast` | 2 | Прогноз вуглецевого виходу — ПРОГНОЗ |
| `biodiversity_trend` | 3 | Стабільність Атрактора Лоренца — ПРОГНОЗ |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `insight_type` | enum | Тип висновку |
| `target_date` | date | Дата, до якої відноситься (unique per analyzable+type) |
| `stress_index` | decimal | 0.0..1.0 (ключовий показник) |
| `probability_score` | decimal | 0.0..100.0 (впевненість Оракула) |
| `reasoning` | jsonb (GIN) | Структуровані причини рішення. Два індекси: `idx_ai_insights_reasoning_gin` (JSONB GIN — containment `@>` запити) та `idx_ai_insights_reasoning_fts` (tsvector GIN — повнотекстовий пошук по `reasoning->>'description'`) |
| `source_log_ids` | integer[] (GIN) | IDs telemetry_logs, що стали джерелом |
| `fraud_detected` | boolean | Прапор маніпуляції даними |
| `model_source` | string | AI-модель (GPT-4, Claude, тощо) |
| `recommendation` | jsonb | Рекомендації Оракула (`action_required`, `priority`) via `store_accessor` |
| `prediction_data` | jsonb | Структуровані прогнозні метрики (`yield_impact`, `confidence_interval`, тощо). Споживається `OracleVisions::ForecastCard` для рендеру `forecast?` карток. Окремо від `reasoning` (raw chain-of-thought) і `recommendation` (action). |
| `analyzed_date` | date | Reserve-стовпець для майбутнього партиціонування за датою аналізу. Зараз у коді не читається — канонічна дата інсайту лежить у `target_date`. Лишається у схемі як точка розширення для багатоосей партиціонування post-TRL 8 (cross-ref E.37 TimescaleDB roadmap). |
| `average_temperature` | decimal | Середня температура за аналізований день |
| `total_growth_points` | bigint | Загальні очки зростання за день |
| `summary` | text | Текстовий підсумок (human-readable) |

**Ключові методи:** `contract_breach?`, `confidence_level`, `forecast?`, `source_logs`, `attach_evidence!(log_ids)`, `status_label`.

**Scopes:** `highly_probable`, `upcoming`, `critical_stress`, `for_date(date)`, `fraudulent`, `referencing_log(log_id)`, `search_reasoning(query)` — повнотекстовий пошук у `reasoning->>'description'` через `plainto_tsquery('simple', ...)` з використанням tsvector GIN-індексу `idx_ai_insights_reasoning_fts`.

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
| `alert_type` | `severe_drought(0) / insect_epidemic(1) / vandalism_breach(2) / fire_detected(3) / seismic_anomaly(4) / system_fault(5) / entropy_anomaly(6)` (prefix: true) |
| `satellite_status` | `unverified(0) / verified(1) / rejected_fraud(2) / inconclusive(3)` (prefix: :satellite) |

**AASM:** `mark_resolved`, `ignore`, `reopen` (resolved/ignored→active).

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `severity` | enum | `low(0) / medium(1) / critical(2)` |
| `message` | text | Опис тривоги |
| `resolved_at` | datetime | Час вирішення |
| `dclimate_ref` | string | Посилання на dClimate для супутникової верифікації |

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

**Includes:** `GeoLocatable`

**Асоціації:**
- `belongs_to :user`
- `belongs_to :maintainable, polymorphic: true` (Tree або Gateway)
- `belongs_to :ews_alert` (optional)
- `has_many_attached :photos` (Active Storage, ≤ 20 МБ, JPEG/PNG/WebP/HEIC/HEIF, макс. 10 фото)

**Enum `action_type`** (prefix: true)**:**

| Значення | Int | Опис |
|----------|-----|------|
| `installation` | 0 | Монтаж EBFC-анкера та капсули |
| `inspection` | 1 | Плановий огляд |
| `cleaning` | 2 | Очищення панелей і датчиків |
| `repair` | 3 | Ремонт обладнання |
| `decommissioning` | 4 | Демонтаж |
| `biomass_extraction` | 5 | Вилучення біомаси (Puro.earth Biochar) |

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
| `biomass_passport_tx_hash` | string | TX-хеш паспорту біомаси (Puro.earth Biochar) |

**Методи:** `total_cost` (labor + parts), `trigger_ecosystem_healing!`.

---

### `EthereumAnchor` — Аудит-Трейл L1 Anchoring

**Призначення:** Персистентний журнал щотижневих операцій фіналізації стану SilkenNet в Ethereum Mainnet. Зберігає `state_root`, `tx_hash`, `block_number` та компоненти для незалежної верифікації (BLOCKER-2, BLOCKER-6).

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `state_root` | string(64) | 64-char SHA-256 hex дайджест (`UNIQUE`) |
| `total_scc` | decimal(30,4) | Загальний SCC-баланс усіх гаманців на момент anchoring |
| `total_sfc` | decimal(30,4) | Сума підтверджених SFC мінтингів на момент anchoring [E.53] |
| `active_tree_count` | integer | Кількість активних дерев в екосистемі на момент anchoring [E.54] |
| `chain_hash` | string | chain_hash останнього `AuditLog` на момент anchoring |
| `anchored_at` | datetime | UTC-timestamp включений у хеш |
| `tx_hash` | string(66) | Ethereum TX hash (`0x` + 64 hex chars, `UNIQUE WHERE NOT NULL`) |
| `block_number` | bigint | Номер блоку підтвердження |
| `gas_used` | bigint | Витрачений газ |
| `status` | integer | Enum: `pending(0) / sent(1) / confirmed(2) / failed(3)` |
| `error_message` | string(500) | Деталі помилки (якщо є) |

**Enum `status`** (prefix: true)**:**

| Значення | Int | Опис |
|----------|-----|------|
| `pending` | 0 | State root обчислено, TX ще не відправлена |
| `sent` | 1 | TX відправлена в мемпул |
| `confirmed` | 2 | TX підтверджена в L1 блоці |
| `failed` | 3 | Помилка відправлення або підтвердження |

**Валідації:**
- `state_root` — presence, uniqueness, format `/\A[a-f0-9]{64}\z/`
- `tx_hash` — uniqueness, format `/\A0x[a-fA-F0-9]{64}\z/` (when present); presence required for `sent`/`confirmed`
- `total_scc` — presence, `>= 0`
- `chain_hash`, `anchored_at` — presence

**Scopes:** `recent`, `successful` (confirmed), `latest_confirmed`.

**Методи:**
- `verify_state_root` — незалежно відтворює хеш з `total_scc|total_sfc|active_tree_count|chain_hash|anchored_at.iso8601` та порівнює з `state_root` (для зовнішнього аудитора)
- `etherscan_url` — повертає `https://etherscan.io/tx/#{tx_hash}` або `nil`

**Використовується:** `Ethereum::StateAnchorService#anchor_to_l1!` (записує до TX), `EthereumAnchorWorker`.

---

### `SystemParameter` — Governance-Aware Протокольні Константи

**Призначення:** Реєстр протокольних параметрів, які можуть оновлюватися через DAO governance (on-chain `ProtocolParameters.sol` → `Governance::ParameterSyncWorker`) або адмін-панель. Забезпечує кешовані lookups з fallback на default значення.

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `key` | string | Унікальний ідентифікатор (`snake_case`, UNIQUE) |
| `value` | string | Серіалізоване значення параметра |
| `value_type` | string | Тип: `integer`, `float`, `decimal`, `string`, `boolean`, `json` |
| `category` | string | Категорія: `lorenz`, `tokenomics`, `minting`, `alerts`, `hardware`, `insurance`, `general` |
| `source` | string | Джерело: `default`, `admin`, `governance` |
| `description` | text | Людський опис параметра |
| `min_value` | decimal | Мінімальне допустиме значення (опціональне) |
| `max_value` | decimal | Максимальне допустиме значення (опціональне) |
| `updated_by_id` | bigint | FK → User (хто оновив) |

**Публічний API:**
- `SystemParameter.current(:lorenz_sigma, default: 10.0)` — кешований lookup (TTL 24h), повертає typed value або default
- `SystemParameter.current_values(lorenz_sigma: 10.0, lorenz_rho: 28.0)` — batch lookup кількох параметрів
- `SystemParameter.set("lorenz_sigma", "12.0", updated_by: admin, source: "governance")` — оновлення з аудит-трейлом

**Валідації:**
- `key` — presence, uniqueness, format `/\A[a-z][a-z0-9_]*\z/`
- `value` — presence
- `value_type` — presence, inclusion
- `category`, `source` — presence, inclusion
- `value_within_bounds` — custom validation при наявності `min_value`/`max_value`

**Кешування:** `after_commit :invalidate_cache`. Ключ: `"system_parameter:#{key}"`. TTL: 24 години.

**Використовується:** `SilkenNet::Attractor` (Lorenz параметри), `ContractHealthCheckService` (slashing threshold), `TokenomicsEvaluatorWorker` (emission threshold), `BlockchainMintingService` (dynamic_tax_rate, insurance_pool_threshold — читаються через `SystemParameter.current` для on-chain параметрів мінтингу), `Governance::ParameterSyncWorker` (sync on-chain → DB).

---

### `ProvisioningSession` — Сесія Factory Flashing (SEC.3)

**Включає:** `AASM`

**Призначення:** [SEC.3] Стан-машина однієї спроби Factory Flashing для одного пристрою. Енфорсить **2-Person Rule** ([`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning)): оператор ініціює, супервайзер схвалює, лише тоді сесія виконується. Кожен перехід аудитований через FK на `users` + `AuditTrail`-записи від `FactoryFlashing::Session`. Перехід `approve` guard-нутий (`credentials_verified?`) — лише `approve_with_credentials!` (Argon2id-пароль супервайзера) досягає `supervisor_approved`; сирий `approve!` відмовляється ([`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning)).

**Асоціації:**
- `belongs_to :operator, class_name: "User"`
- `belongs_to :supervisor, class_name: "User", optional: true`

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `device_uid` | string | Пристрій, що провіжиниться (presence) |
| `batch_id` | string | Ідентифікатор партії (presence) |
| `gilka` | string | Гілка провіжинингу: `"A"` (Protected Flash + RDP) / `"B"` (Secure Element; `atecc_serial_hex` обов'язковий) — `GILKAS = %w[A B]` |
| `rdp_level` | integer | Рівень RDP після flash — `RDP_LEVELS = [0, 1, 2]` |
| `atecc_serial_hex` | string | 18 HEX (9-байт SE serial); presence лише для гілки B, format `/\A[0-9A-F]{18}\z/` |
| `flash_addr` | string | Адреса запису ключа (presence) |
| `firmware_version` | string | Версія прошивки (presence) |
| `state` | enum (AASM) | `pending / supervisor_approved / active / completed / failed` |
| `started_at` · `supervisor_approved_at` · `completed_at` | datetime | Часові мітки переходів |
| `error_message` | string | Причина `failed` |

**AASM (column: `state`, whiny_persistence):**

```
pending ──approve──► supervisor_approved ──start──► active ──complete──► completed
supervisor_approved/active ──fail_with(reason)──► failed
```

`approve` має guard `supervisor_present?` (`supervisor_id` присутній і ≠ `operator_id`).

**Валідації:** `supervisor_must_differ_from_operator` (2-Person Rule); `gilka` inclusion `[A,B]`; `rdp_level` inclusion `[0,1,2]`; `atecc_serial_hex` format (18 HEX).

> Service-шар (orchestrator `FactoryFlashing::Session` + `MasterKeySource`/`CommandBuilder`/`Executor`/`AteccProvisioner`/`AuditTrail`, Rake CLI) — канон [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning); дзеркало у [`04_02`](04_02_Business_Logic_and_Services).

---

## 📖 7b. Codex — Lore Layer (Кодекс Архетипів)

Lore-шар SilkenNet — read-only бібліотека "архетипів" (екосистеми, унікальні дерева, біо/інженерні протоколи, міфо-фреймворки) + соціальний шар (коментарі, attunements). Повна специфікація: **[`04_05`](04_05_Codex_Lore_Module)**. Phase 1 додає 3 моделі (Realm/Node/Citation), Phase 2 — 2 моделі (Comment/Attunement) + ActionCable broadcast. Phase 3-5 розширять цей шар (`Match`, `Discovery`, `Fraction`).

### `Codex::Realm` — Шар (4 семантичні групи)

**Атрибути:** `slug` (UNIQUE), `name_uk`, `name_en`, `glyph` (`forest`/`tree`/`protocol`/`mythos`), `accent_token` (gaia-* design token), `position`, `description_md`, `is_active`. Лежить у таблиці `codex_realms`.

**Методи:**
- `Codex::Realm.ordered` — за `position ASC, name_en ASC`
- `name(locale)` — bilingual switch

**Сидиться через:** `bin/rails codex:seed` (idempotent UPSERT за `slug`). 4 рядки: ecosystem, unique_tree, protocol, mythos.

### `Codex::Node` — Запис у Кодексі

**Атрибути:** `codex_realm_id` (FK), `slug` (UNIQUE), `codex_uid` (`CDX-{ECO|TRE|PRT|MYT}-NNNN`, UNIQUE), bilingual `title_uk`/`title_en`/`subtitle_uk`/`subtitle_en`, `archetype_key` (з реєстру `Codex::ARCHETYPES`, 79 значень), markdown лор `context_md`, `cyber_meaning_md`, `lore_md` (рендериться через `Codex::MarkdownRenderer`), геопросторові `latitude`/`longitude`/`geo_point` (PostGIS GEOGRAPHY(POINT, 4326)) + `geo_region`, лічильники-каунтери (`attunement_count`, `comments_count`, `view_count`, `discovery_count`, `citation_count`, `match_count`), `attunement_elo` (battle rating, default 1500, range 0..4000), `lifecycle_status` enum (`mythical`/`extinct`/`endangered`/`thriving`/`destroyed`/`unknown`), `seed_origin` enum (`seed`/`dao_proposal`/`community_submission`), `external_refs` (JSONB `[{label, url}]`), `discoverable_after_minutes`, `published_at`. Active Storage: `cover_image`, `gallery`.

**Concerns:** `GeoLocatable`. **Sync:** `before_save :sync_geo_point` — оновлює PostGIS точку при зміні lat/lng.

**Scopes:** `published`, `for_realm(realm_or_slug)`, `search_title(q)` (ILIKE по обох locale, GIN-pg_trgm), `by_archetype(key)`, `by_lifecycle(status)`, `ordered_by_elo`.

**Helpers:** `title(locale)`, `subtitle(locale)`, `to_param` → `slug`.

**Партиціонування:** немає (79 базових записів + поступовий ріст; коли `codex_matches` досягне сотень тисяч у Phase 4 — партиціонується сам).

### `Codex::Citation` — Полі-морфне Посилання

**Атрибути:** `codex_node_id` (FK), `citable_type` + `citable_id` (поліморфне), `created_by_user_id`, `note`, `created_at`. Унікальний індекс `(codex_node_id, citable_type, citable_id)` запобігає дублюванню. Counter cache → `Codex::Node.citation_count`.

**Призначення:** будь-яка доменна сутність (`Tree`, `Cluster`, `EwsAlert`, `OracleVision`, `BlockchainTransaction`) може отримати "пілюлю-посилання" на Codex-запис. Phase 6 додасть `CitationPill` UI-примітив.

### `Codex::Comment` — Коментар (Phase 2)

**Атрибути:** `commentable_type` + `commentable_id` (поліморфне; Phase 2 пише лише `"Codex::Node"`), `user_id` (FK), `parent_id` (self-FK, **один рівень вкладеності** — модельна валідація, не DB-CHECK), `body_md` (≤ 2 KiB), модераційні поля `flagged_at`/`flag_reason` (з `FLAG_REASONS = %w[spam abuse offtopic other]`), soft-hide пара `hidden_at`/`hidden_by_admin_id`. Counter cache → `Codex::Node.comments_count`.

**Scopes:** `visible` (`hidden_at IS NULL`), `hidden`, `top_level` (`parent_id IS NULL`), `chronological`. **Helper:** `editable_by?(user)` — true якщо користувач = автор ∧ створено ≤ 24 годин тому (`EDIT_GRACE`).

**Валідації:** `parent_must_be_top_level` (rejects reply-to-reply), `parent_must_share_commentable` (rejects cross-node parent).

**ActionCable:** `Codex::CommentsController#create` після `comment.save` робить `ActionCable.server.broadcast("codex_node_<id>_comments", { node_id, comment_id, data: serialized })` через `Codex::CommentBlueprint`.

**Модерація:** автор може edit/destroy ≤ 24h, admin+ може **hide** (`hidden_at` set), але **не destroy** — журнал модерації лишається tamper-evident.

### `Codex::Attunement` — Семантична Прив'язка (Phase 2)

**Атрибути:** `user_id` (FK), `codex_node_id` (FK), `intensity` (1..5, DB CHECK + model validation), `quote` (≤ 280 chars, optional особистий девіз), `started_at` (default = `now()`).

**Унікальність:** UNIQUE `(user_id, codex_node_id)` — на DB-рівні + на моделі. Re-POST оновлює існуючий рядок (idempotent toggle), ніколи не дублює.

**Counter cache:** `Codex::Node.attunement_count`.

**Constants:** `INTENSITY_RANGE = (1..5)`, `QUOTE_MAX = 280`.

**Scopes:** `for_node(node)`, `for_user(user)`, `ordered` (за `created_at DESC`).

**Workflow:** `Codex::AttunementsController` (create/destroy) → `Codex::AttunementBroadcastWorker.perform_async(node_id, user_id)` (queue: `default`) → broadcasts `attunement_count` на public-канал `codex_node_<id>_attunements` + `attuned: bool` на private-канал `codex_node_<id>_attunements_user_<uid>`.

### `Codex::Fraction` — Особиста Ідентичність (Phase 3)

**Атрибути:** `user_id` (FK UNIQUE — DB-рівень), `codex_node_id` (FK), `archetype_key` (string ≤ 64, денормалізація з Node для index-only фільтрів), `chosen_at` / `last_changed_at` (timestamps), `house_color_token` (≤ 64 chars, optional Tailwind токен типу `gaia-primary`).

**Унікальність:** UNIQUE `(user_id)` — користувач має максимум одну активну фракцію. UNIQUE на DB-рівні (а не лише в моделі) ⇒ жодний race-condition між контролером та сервісом не може лишити дві активні фракції.

**Constants:** `COOLDOWN = 7.days`. Helpers: `cooldown_active?`, `cooldown_until`, `seconds_until_unlocked`.

**Validations:** lifecycle вузла НЕ повинен бути `destroyed` чи `extinct` (вшито в `node_lifecycle_pickable` валідатор). `mythical` дозволяється — міф є валідною ідентичністю.

**Association:** `User has_one :codex_fraction, dependent: :destroy`. Безпечний destroy — фракція не є модераційним артефактом, видалення користувача чисто стирає його identity claim.

**Workflow:** `Codex::FractionChangeService` — єдина точка мутації. Перевіряє cooldown, атомарно `find_or_initialize_by(user_id:)` → save → enqueue `Codex::FractionAuditWorker` (queue `default`, ADR-CDX-4) → AuditLog `action: "codex.fraction.chosen"` (тільки коли user має organization, бо ledger є per-org).

### `Codex::Match` — Battle Arena Duel (Phase 4) — `codex_matches` (PARTITIONED RANGE by `created_at`)

**Атрибути:** `id` + `created_at` (composite PK, як у `blockchain_transactions`), `user_id` (FK), `codex_realm_id` (FK — denormalised для leaderboard scoping без JOIN), `left_node_id` / `right_node_id` (FKs), `winner_node_id` (FK, nullable — NULL = skip), `pair_seed` (varchar 64, HMAC-SHA256), `elo_delta_left` / `elo_delta_right` (integer, K=32 — `EloMath.deltas`).

**Партиціювання:** RANGE по `created_at`. `_default` партиція + 6 monthly windows seeded inline у міграції; `PartitionMaintenanceWorker` додає нові партиції щомісяця (включено `codex_matches` у `PARTITIONED_TABLES` список).

**Індекси:** BTREE `(user_id, created_at DESC)` (own-history feed), BTREE `(left_node_id, right_node_id)` (replay-protection lookups), BTREE `codex_realm_id` (leaderboard), BTREE `pair_seed` (unique-by-seed scrub queries).

**Validations:** `winner_node_id ∈ [left, right, nil]`, `left ≠ right`, обидва nodes мають належати тому ж realm що і `codex_realm_id`.

**Scopes:** `for_user(user)`, `for_realm(realm_id)`, `recent` (created_at DESC).

**FKs БЕЗ cascade на user/realm/node delete** — battle history є audit-grade; `_default` партиція рятує від data loss при clock-skew рядках.

**Workflow:**
1. `MatchesController#new` → `PairSelectorService` обирає anchor (weighted by inverse `match_count`) + opponent в Elo-bucket ±200 → HMAC-SHA256 seed зберігається у Redis з TTL 5 хв.
2. `MatchesController#create` → `VoteRecorderService` consume'ить seed (atomic GETDEL → replay-proof), створює Match-row, обчислює Elo deltas, enqueue `EloRecomputeWorker.perform_async(left_id, right_id, delta_left, delta_right)`.
3. `EloRecomputeWorker` (queue `low`) атомарно `UPDATE codex_nodes SET attunement_elo = attunement_elo + ?, match_count = match_count + 1` для обох вузлів у транзакції.

### `Codex::Discovery` — Unlock Log (Phase 5) — `codex_discoveries`

**Атрибути:** `user_id` (FK, `on_delete: :cascade`), `codex_node_id` (FK, `on_delete: :restrict` — counter_cache → `discovery_count`), `trigger_type` (integer enum: `telemetry_observation` / `manual_unlock` / `match_milestone` / `fraction_choice` / `attunement_streak` / `oracle_seasonal`, prefix `triggered_by`), polymorphic `(trigger_ref_type, trigger_ref_id)` (БЕЗ FK — Discovery survives partition drops & match archival), `unlocked_at` (timestamp).

**Індекси:** UNIQUE `(user_id, codex_node_id)` (anti-double-unlock на DB-рівні), BTREE `(trigger_ref_type, trigger_ref_id)`, BTREE `(user_id, unlocked_at DESC)` (own-collection feed).

**Validations:** `unlocked_at` presence; `before_validation :default_unlocked_at on: :create` для зручності API.

**Scopes:** `for_user(user)`, `recent` (unlocked_at DESC).

**Workflow:**
1. Trigger fires (TelemetryUnpackerService finalizer / EloRecomputeWorker / FractionChangeService / AttunementsController) → `Codex::DiscoveryProbeWorker.perform_async(user_id, trigger_type, payload)`.
2. Worker → `Codex::DiscoveryEngine.evaluate(user:, trigger_type:, payload:)` → `Array<Codex::Node>` (skips already-unlocked).
3. Worker `find_or_create_by(user_id:, codex_node_id:)` + `previously_new_record?` → ActionCable broadcast тільки на справжньому create (race-safe).

### `Codex::DiscoveryRule` — DAO Rule Registry (Phase 5) — `codex_discovery_rules`

**Атрибути:** `name` (varchar, ≤ 120, унікальний на logical level), `codex_node_id` (FK, на яку картку правило unlocks), `condition_type` (integer enum: `tree_observation_minutes` / `acoustic_class_count` / `cluster_visited` / `match_count` / `attunement_streak_days` / `firmware_version_seen` / `oracle_dispatched`, prefix `condition`), `threshold_value` (integer, ≥ 1), `params` (JSONB, default `{}`), `active` (boolean), `created_by_user_id` (FK to users, `on_delete: :restrict` — audit trail).

**Індекс:** BTREE `(active, condition_type)` (hot-path `active_only` filter for `cached_active_by_condition`).

**Validations:** `name`/`threshold_value` presence; `params_must_be_hash`.

**Caching:** `Rails.cache.fetch("codex.discovery_rules.v1", expires_in: 1.hour)` busted `after_commit` (create/update/destroy). DAO-зміни візуальні всім worker'ам у ≤ 1 сек.

**CRUD:** admin+ через `Api::V1::Codex::Admin::DiscoveryRulesController`. Seeds через `Codex::DiscoveryRuleImportService` (idempotent UPSERT by `name`, `db/seeds/codex/discovery_rules.yml`).

---

## 🌱 8. Seeds — Початковий Стан Системи

Порядок видалення при очищенні (від листя до кореня):

```
AuditLog, Session, Identity, EthereumAnchor
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

**Codex (Lore Layer):**

Сидиться **окремою idempotent rake-таскою** (НЕ через `db:seeds.rb`, бо `seeds.rb` не виконується на проді):

```bash
bin/rails codex:seed              # UPSERT 4 realms + 79 nodes (за slug)
bin/rails governance:seed_parameters  # UPSERT dynamic_tax_rate + insurance_pool_threshold
```

Обидві таски ідемпотентні (повторний запуск не дублює та зберігає DAO-промотовані поля). Джерело: `db/seeds/codex/realms.yml` + `db/seeds/codex/nodes/{ecosystems,unique_trees,protocols,mythos}.yml`.

---

## 📊 9. Ключові Індекси

### Критичні індекси продуктивності

| Таблиця | Індекс | Тип | Призначення |
|---------|--------|-----|-------------|
| `ai_insights` | `idx_ai_insights_unique_report` | UNIQUE BTREE | analyzable + date + type + model_source |
| `ai_insights` | `idx_ai_insights_polymorphic_type_date` | BTREE | Пошук по типу та даті |
| `ai_insights` | `idx_ai_insights_reasoning_gin` | GIN (JSONB) | Containment-запити (`@>`) в JSONB полі reasoning |
| `ai_insights` | `idx_ai_insights_reasoning_fts` | GIN (tsvector) | Повнотекстовий пошук по `reasoning->>'description'` — використовується scope `search_reasoning` |
| `ai_insights` | `index_ai_insights_on_source_log_ids` | GIN | Пошук по масиву log IDs |
| `telemetry_logs` | `idx_telemetry_logs_bio_status_created` | BTREE (ONLY) | Фільтр аномалій |
| `telemetry_logs` | `idx_telemetry_logs_oracle_dispatched` | PARTIAL | oracle_status = 'dispatched' |
| `telemetry_logs` | `idx_telemetry_logs_oracle_failed` | PARTIAL | oracle_status = 'failed' |
| `gateway_telemetry_logs` | `idx_gateway_telemetry_logs_queen_uid_created` | BTREE (ONLY) | Зв'язок через uid |
| `actuator_commands` | `index_actuator_commands_on_idempotency_token` | UNIQUE | Захист від дублів |
| `actuator_commands` | `index_actuator_commands_on_expires_at` | PARTIAL | status IN (0,1) |
| `ethereum_anchors` | `index_ethereum_anchors_on_state_root` | UNIQUE BTREE | Дедуплікація state roots |
| `ethereum_anchors` | `index_ethereum_anchors_on_tx_hash` | UNIQUE PARTIAL (WHERE NOT NULL) | Lookup по TX hash |
| `ethereum_anchors` | `index_ethereum_anchors_on_status` | BTREE | Фільтр по статусу |
| `ethereum_anchors` | `index_ethereum_anchors_on_created_at` | BTREE | Хронологічна пагінація |
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

## 🗺️ 10. Карта Зв'язків

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
  │     │     │     └── ActuatorCommands (delete_all)
  │     │     └── MaintenanceRecords (restrict_with_error)
  │     ├── NaasContracts (restrict_with_error)
  │     ├── ParametricInsurances (restrict_with_error)
  │     ├── EwsAlerts (delete_all)
  │     └── AiInsights polymorphic (delete_all)
  ├── Wallets (nullify)
  │     └── BlockchainTransactions (delete_all) ← PARTITION
  └── AuditLogs (delete_all)

User
  ├── Sessions (destroy)
  ├── Identities (destroy)
  ├── MaintenanceRecords (restrict_with_error)
  └── AuditLogs (restrict_with_error)

TreeFamily
  └── Trees (restrict_with_error)

Polymorphic:
  AiInsight.analyzable → Tree | Cluster
  MaintenanceRecord.maintainable → Tree | Gateway
  BlockchainTransaction.sourceable → NaasContract | ParametricInsurance
  AuditLog.auditable → any model
  HardwareKey → Tree (via did) | Gateway (via uid)
  Codex::Citation.citable → Tree | Cluster | EwsAlert | OracleVision | BlockchainTransaction | … (read-only outbound)

Codex (Lore — read-only):
  Codex::Realm
    └── Codex::Nodes (destroy on realm removal — admin-only path)
          └── Codex::Citations (destroy)
```

---

## 🏗️ 11. Архітектурні Принципи БД

| Принцип | Реалізація |
|---------|-----------|
| **Hot Path без валідацій** | `TelemetryLog`, `GatewayTelemetryLog` — валідації в сервісі, не в AR |
| **Денормалізація для N+1 Kill** | `latest_stress_index`, `latest_voltage_mv`, `active_trees_count`, `health_index`, `entropy_score` |
| **GREATEST для race conditions** | `mark_seen!` в Tree та Gateway — атомарне оновлення без дублів |
| **delete_all для масових таблиць** | Телеметрія, тривоги, логи, ActuatorCommands — уникнення OOM при DELETE |
| **restrict_with_error для фінансів** | NaasContract, ParametricInsurance, Users — захист аудит-слідів |
| **Партиціонування по місяцях** | telemetry_logs, gateway_telemetry_logs, blockchain_transactions, codex_matches — прунінг старих даних. SSOT — `PartitionMaintenanceWorker::PARTITIONED_TABLES` (4 таблиці) |
| **Counter Cache** | `active_trees_count` в Cluster — уникнення COUNT на мільйонах рядків |
| **Поліморфізм** | AiInsight, MaintenanceRecord, AuditLog, BlockchainTransaction |
| **PostGIS GIST** | Cluster.geo_boundary — O(log n) геопросторовий пошук |
| **AR Encryption + In-Process LRU Cache** | HardwareKey.aes_key_hex — шифрування в БД + `cached_binary_key` у in-process LRU (SinLruRedux, max 10 000 entries). Ключі не залишають Ruby-процес (Zero Network Exposure) |
| **BigDecimal в JSONB** | TinyMlModel accuracy_score/threshold — уникнення Float похибок |
| **Partial Index для sparse поля** | `blockchain_transactions.tx_hash WHERE tx_hash IS NOT NULL` — виключає рядки без tx_hash (pending/processing) |

---

## 🧭 12. SSOT Drift Register (Doc ↔ Schema Sync)

> **Принцип:** `db/structure.sql` після `db:migrate` — authoritative reality схеми; 04_01 — її SSOT-опис. Загальний метод drift-resolution (schema-ahead → онови док; doc-ahead → задача в [`00_07`](00_07_Action_Plan_Tracker); не «допишу до 04_01 потім») — [`00_06`](00_06_SSOT_Documentation_Standard) + скіл `ssot-maintenance`. Дзеркало для service-шару (сервіси/воркери/ENV, інший скоуп) — [`04_02 §13b`](04_02_Business_Logic_and_Services).

**Механічні інваріанти — ✅ enforced by `scripts/model_doc_sync.rb`** (CI `docs.yml` тригериться і на `docs/`, і на `app/models/**`, тож дрейф ловиться з обох боків; локально — `ruby scripts/model_doc_sync.rb`):

1. Model-файли (`app/models/**`, мінус `application_record` / `codex.rb`-shim / `concerns/`) ⟷ код-спан-заголовки `### Model` у §2..§7b — рівно 1:1.
2. Concern-файли (`app/models/concerns/`) ⟷ код-спан-заголовки `### Concern` у §1.
3. `PartitionMaintenanceWorker::PARTITIONED_TABLES` ⟷ згадки таблиць у §0 + §11.

> Раніше це був ручний «drift register» з датованим логом виправлень — він мовчки протух (заявляв 35 моделей при 36 файлах), тож логіку винесено у скрипт-гейт; історія виправлень живе в git.

**Решта (ручний cool-down audit, [`00_04 §5.3`](00_04_Shape_Up_Operations_and_RnD_Clusters), поки не автоматизовано):** кожна `include AASM`-модель має state-перелік у своєму §; поліморфні `_type/_id` пари §10 «Карта Зв'язків» ⟷ реальні колонки `structure.sql`.

> **Поза скоупом (за дизайном, не drift):** Active Storage (`active_storage_*`), `schema_migrations` / `ar_internal_metadata` — framework-інфра; документується inline-згадками у моделях (`Organization.logo`, `MaintenanceRecord.photos`, `Codex::Node.cover_image`), не як окремі сутності.