# 04_01: Моделі Даних та Сутності

## 🎯 Мета

Зафіксувати повну структуру реляційної бази даних (PostgreSQL) та ActiveRecord моделей для моноліту Ruby on Rails 8.1. Цей документ є **вичерпним довідником** усіх моделей, concerns, ключових індексів, AASM-машин стану та seeds-стану системи. Повнота реєстру гейтована `scripts/model_doc_sync.rb`, тому лічильники тут свідомо не наводяться — попередній ручний лічильник уже мовчки протухав (§12). Визначає, як фізичні об'єкти (дерева, шлюзи) та абстрактні концепції (контракти, токени, аудит) пов'язані між собою в єдину Кіберфізичну Державу SilkenNet.

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — Схема БД затверджена, міграції написані, поліморфні зв'язки та індекси оптимізовані для planetary-scale highload. Відкрите: data-шар беклог → [`00_07 §04`](00_07_Action_Plan_Tracker); §12 doc↔schema синхронність — enforced `model_doc_sync`-гейтом ([`00_06 §3`](00_06_SSOT_Documentation_Standard)), не ручний моніторинг.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) | Фізичний рівень (Soldier/Queen DID, RTC) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (сервіси над моделями) |
| [`03_06` — Factory Flashing and Key Provisioning](03_06_Factory_Flashing_and_Key_Provisioning) | HardwareKey HKDF/K_seed деривація (03_06 §2/§3): aes_key, lorenz_seed |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Web3-економіка (Wallet, BlockchainTransaction) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (§04 data-шар) |

### Конвенція впорядкування розділів

1. **§0 PostgreSQL Інфраструктура** — extensions, тригери, партиціонування (horizontal infra, не модель).
2. **§1 Concerns** — повторно вживані mixins (`include` у моделях). Свідомо перед моделями: модель може посилатися на concern у власному рядку.
3. **§2–§7** — domain-grouped моделі за **онтологічними шарами** реальної системи:
   - §2 Біологічний (TreeFamily, Tree, Cluster) — фізичний об'єкт моніторингу
   - §3 Апаратний (Gateway, HardwareKey, DeviceCalibration, TelemetryLog, GatewayTelemetryLog) — IoT-edge
   - §4 AI / OTA / Актуатори (TinyMlModel, BioContractFirmware, Actuator, ActuatorCommand) — інтелект та фізична відповідь
   - §5 Люди та Організації (Organization, User, Session) — соціальний шар
   - §6 Економічний (Wallet, BlockchainTransaction, NaasContract, ParametricInsurance) — токеноміка
   - §7 Інтелект та Аудит (AiInsight, EwsAlert, AuditLog, MaintenanceRecord, EthereumAnchor, SystemParameter, ProvisioningSession) — спостережуваність + governance
4. **§8 Seeds, §9 Індекси, §10 Карта зв'язків, §11 Архітектурні Принципи, §12 SSOT Drift Register** — horizontal cross-cuts (не належать до конкретного домену; стосуються всіх моделей одразу).

> **Anti-pattern, якого уникаємо:** змішувати моделі з різних доменів в одній секції лише за схожою назвою (наприклад, `BlockchainTransaction` живе в §6 Економіка, а `EthereumAnchor` — в §7 Аудит, хоч обидва "blockchain-related", бо відповідальність різна: одна — фінансовий tx, інша — read-only L1 evidence).

---

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [0. PostgreSQL Інфраструктура](#-0-postgresql-інфраструктура) — extensions, тригери, партиціонування (3 таблиці), TimescaleDB rationale
- [1. Concerns](#-1-concerns) — 7 mixin'ів (Auditable, EthAddressValidatable, Firmwareable, GeoLocatable, HasArgon2Password, NormalizeIdentifier, OtaChunkable)
- [2. Біологічний Рівень](#-2-біологічний-рівень) — TreeFamily, **Tree** (Soldier), Cluster
- [3. Апаратний Рівень](#-3-апаратний-рівень) — **Gateway** (Queen), HardwareKey, DeviceCalibration, **TelemetryLog** (partitioned), GatewayTelemetryLog (partitioned)
- [4. AI / OTA / Актуатори](#-4-ai--ota--актуатори) — TinyMlModel, BioContractFirmware, Actuator, ActuatorCommand
- [5. Люди та Організації](#-5-люди-та-організації) — Organization, User, Session
- [6. Економічний Рівень](#-6-економічний-рівень) — Wallet, **BlockchainTransaction** (partitioned), NaasContract, ParametricInsurance
- [7. Інтелект та Аудит](#-7-інтелект-та-аудит) — AiInsight, EwsAlert, AuditLog, MaintenanceRecord, EthereumAnchor, SystemParameter, ProvisioningSession
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
| `pg_trgm` | Trigram-нечіткий пошук назв через GIN. ⚠️ **Поточного споживача немає.** Розширення лишається встановленим; комірка стоїть як запис про відсутність споживача, а не як опис живого шляху |

### Тригери

**Жодного.** ⚠️ Тут жив `sync_cluster_geo_boundary()`; знято 2026-08-14 разом із переходом `clusters.geo_boundary` на `GENERATED ALWAYS ... STORED` ([E.36], §2 нижче). Рядок лишається як запис про порожню множину, а не як пропуск: тригерна функція у `structure.sql` є окремим класом ризику (`pg_dump` не зберігає `OR REPLACE`), тож «тригерів немає» — властивість, варта оголошення.

### Партиціонування (RANGE BY created_at)

| Таблиця | Стратегія | Причина |
|---------|-----------|---------|
| `telemetry_logs` | RANGE by month | Мільйони рядків/місяць від Солдатів |
| `gateway_telemetry_logs` | RANGE by month | Тисячі рядків/місяць від Королев |
| `blockchain_transactions` | RANGE by month | ≈ 12B рядків/рік при 1B дерев × щомісячний SCC мінтинг; composite PK `(id, created_at)` |

Партиції створюються rolling-window'ом (`PartitionMaintenanceWorker` — **попередній + поточний + наступний** місяць, щодня), тож точний перелік живе у `db/structure.sql`, не тут. Усі + `_default`. ⚠️ **Найраніший місяць НЕ називається тут числом**: він рухається разом із вікном воркера, а разова прибирачка порожніх листів (2026-09-01) уже одного разу зробила записане тут `y2026m01` неправдою.

**Автоматизація:** `PartitionMaintenanceWorker` (черга `default`) щодня о 00:30 UTC гарантує існування партицій для **попереднього, поточного та наступного місяця** для всіх **трьох** партиційованих таблиць (`telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`). Назва партиції формується за шаблоном `<table>_y<YYYY>m<MM>` (напр. `blockchain_transactions_y2026m04`). Операція ідемпотентна — `CREATE TABLE IF NOT EXISTS`. SSOT константа: `PartitionMaintenanceWorker::PARTITIONED_TABLES`. При додаванні нової RANGE-таблиці — внесіть її **і сюди (§0)**, і у `PARTITIONED_TABLES`, і у `spec/workers/partition_maintenance_worker_spec.rb` (очікуване число OK-ліній = `tables × 3 months`). 🔴 **ПОПЕРЕДНІЙ місяць у вікні — не запас, а діапазон, у який система реально пише:** `db/seeds.rb` датує «мовчунку» моментом останнього почутого пакета (`73.hours.ago`), а `LoadTest::Provisioning#seed_history!` розтягує історію 12-год кроками — тож першого-третього числа обидва цілять у попередній місяць. Доти вужче вікно МАСКУВАВ застиглий календар дампу; щойно той перестав нести минуле, `db:seed` кроку 7 [`06_01`](06_01_Deployment_Kamal_Terraform) осідав у `_default` і незворотно блокував партицію того місяця (виміряно 2026-09-01 відтворенням `PG::CheckViolation`; рунбук [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup)).

> **📝 Розглянута альтернатива — TimescaleDB (E.37):**
> Для IoT-телеметрії такого масштабу розглядалось розширення TimescaleDB (hypertables, continuous aggregates, автоматична компресія до 90% економії місця). **Чому відхилено для поточного TRL:**
> - Нативний PostgreSQL RANGE partitioning повністю покриває потреби TRL 6-8 (мільйони рядків/місяць, partition pruning через One-Home цієї моделі — `TelemetryLog.partition_pruned`, НЕ `find_with_partition_pruning`: той живе на `BlockchainTransaction`)
> - TimescaleDB-extension **недоступний на GCP Cloud SQL** (не в allow-list; вимагає `shared_preload_libraries`) — наш prod-Postgres ([`06_06`](06_06_Disaster_Recovery_and_Backup)) його фізично не прийме; шлях = ClickHouse-OLAP / Timescale Cloud окремим інстансом / pg_partman
> - Continuous Aggregates можна замінити `AiInsight` воркером (вже реалізовано: денна агрегація)
> - При масштабуванні за 100M+ рядків/місяць — переглянути рішення (ClickHouse або Timescale Cloud)

### DB-level integrity backstops [ARCH.56]

Кожна Ruby-`uniqueness`-валідація має **дзеркальний unique-індекс** (race-вікно між SELECT і INSERT валідація не закриває): `organizations.name` + `organizations.crypto_public_address` · `clusters.name` · `tree_families.name` · `actuators (gateway_id, endpoint)` · `bio_contract_firmwares.version` · `tiny_ml_models.version` · `wallets.tree_id` · `device_calibrations.tree_id` (останні два — `has_one`: друга row = phantom; `Tree.after_create` сам створює wallet+калібровку, тож фабрики специв реюзають авто-створені через `initialize_with`).

Money-інваріант застраховано CHECK-констрейнтом `wallets_balance_invariants`: `balance ≥ 0 AND locked_balance ≥ 0 AND esg_retired_balance ≥ 0 AND locked_balance ≤ balance` (семантика `Wallet#available_balance = balance − locked_balance`; прод-шляхи `lock_funds!`/`lock_and_mint!` мають guard, CHECK ловить bypass через `update_all`/SQL). `blockchain_transactions.amount` = `numeric(24,6)` (був bare `numeric`). `gateways.state` = `NOT NULL DEFAULT 0` (AASM nil-state footgun). Композитний PK партиційованих таблиць вимагає `self.primary_key = "id"` у моделі — інакше `record.id` повертає масив `[id, created_at]` (TelemetryLog / GatewayTelemetryLog / BlockchainTransaction — усі три декларують). ⚠️ **Клас куплено кровʼю, і його вартий памʼятати без носія** (ARCH.56, 2026-07-26): четверта партиційована модель тодішнього дерева декларувала `self.primary_key = [:id, :created_at]`, через що `record.id` віддавав МАСИВ — він летів у bigint-колонку (`StatementInvalid` повз rescue → DeadSet) і друкувався як `"id": [42, …]` у публічній JSON-відповіді через блупринт-`identifier`. Тобто композитний DB-PK — вимога партиціювання, а скалярний AR-PK — вимога всього, що читає `.id`. Живого інстансу в дереві немає; правило лишається чинним для КОЖНОЇ нової партиційованої моделі.

---

## 🔧 1. Concerns

Сім спільних модулів, що підключаються через `include` до відповідних моделей.

### `Auditable`
**Використовується:** `NaasContract`, `ActuatorCommand`, `User`, `SystemParameter` (+ сервіси `BlockchainBurningService`, `HardwareKeyService`)

**[ARCH.57]** Запис привілейованих дій у tamper-evident AuditLog-ланцюг: `record_audit_trail!(action:, organization_id:, auditable:, user_id:, ip_address:, user_agent:, metadata:, archive:)` — async (дзеркало MRV.1), актор = людський ініціатор або `Auditable.system_actor_id` (`oracle_executioner`; без актора → WARN-skip, дію не валимо). `archive: false` (default) = chain-only; ЄДИНИЙ `archive: true` = MRV.1 money-tx переходи (IPFS-outbox). Coverage-мапа + хук-механізм → §7 AuditLog-картка.

---

### `EthAddressValidatable`
**Використовується:** `Organization`, `Wallet`, `BlockchainTransaction` (+ boot-guard `Security::Web3NetworkGuard` реюзає предикат)

Два шари валідації Ethereum/Polygon-адрес: **форма** + **EIP-55 контрольна сума** [ARCH.56].

```
ETH_ADDRESS_FORMAT = /\A0x[a-fA-F0-9]{40}\z/
```

Метод: `validates_eth_address(attribute, presence:, allow_blank:)` — додає обидва шари до поля.

**Правило суми** (сам EIP-55; рахує гем `eth`): адреса в ОДНОМУ регістрі — все-нижньому або все-верхньому — суми не несе, тож приймається як є; **mixed-case суму НЕСЕ**, тож вона мусить збігтися, інакше `EIP55_MESSAGE`. Форма й сума — ОКРЕМІ валідації: зламаний рядок дає одну причину, не дві. Сам shape-regex друкарську помилку побачити не може (40 hex лишаються 40 hex після підміни символа — кошти пішли б на неіснуючу адресу), і саме тому предикат `EthAddressValidatable.eip55_valid?` = One-Home правила: ним же boot-guard звіряє env-адреси (`DAO_TREASURY_ADDRESS`, контракти SCC/SFC) — там мис-пейст інакше лишається тихим до першої транзакції.

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

> 🔴 ⚠️ **`fw_pending` не write-only, а БЕЗ ПИСАЧА ВЗАГАЛІ** (виправлено 2026-08-16; доти тут стояло «єдиний писач — `TelemetryUnpackerService#check_firmware_mismatch!»`, і це перестало бути правдою 2026-08-14). Присуд `ARCH.85` зробив детекцію mismatch **спостережною**: дієвий `update_all(firmware_update_status: :fw_pending)` **знято**, метод лише логує. ⚠️ **Але ЧИТАЧ живий, і він на ГАРЯЧОМУ шляху** — `TelemetryUnpackerService#check_firmware_mismatch!` гейтує власну гілку предикатами `firmware_fw_idle?/…_completed?/…_failed?`, і робить це ВСЕРЕДИНІ транзакції `commit_telemetry`: зняття колонки дало б `NoMethodError` → відкат транзакції → **втрату `TelemetryLog`** на кожному кадрі з розбіжним contract-id. Тобто «нуль писачів» ≠ «мертвий код». ⊕ Сім подій AASM-машини при цьому не викликались у проді **жодного разу за історію репо** (`git log --all -S` по кожній = 0) — машину додали тим комітом, що переводив шість ІНШИХ моделей на події, і жодного воркера в неї не перевели. ⊕ Словник семи станів **дзеркалить реальний автомат прошивки** (`OTA_FINALIZE_WAIT/APPLY/REJECT`, CRC32 + dual-gate HMAC, `Flash_Write_Contract`, anti-rollback hiwater), тож він не вигаданий — бракує лише wire-фіда ФАЗ: пристрій звітує самий `FwContractReport [semantic|reverted|hiwater]`, без per-фазних переходів. Умову оживлення назвав сам `ARCH.85` — «після того, як лічильник покаже правдоподібні числа на живому флоті». Доля машини → [`00_07` ARCH.59](00_07_Action_Plan_Tracker).
>
> ⊕ **Асиметрія обернена до інтуїтивної: жива саме Tree-половина, мертвіша — Gatewayʼина** [ARCH.59]. Шлюзу те саме питання вже відповідає власна трійця `state` + `pending_firmware_id` + `ota_started_at` ([`04_02 §11`](04_02_Business_Logic_and_Services) `GatewayStalenessSweepWorker`), тобто на `Gateway` цей concern **дублює наявний механізм**, а не доповнює його — і саме тому «зняти машину цілком» не є симетричним рішенням для двох моделей.

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
| `critical_z_min` | decimal | Мінімум Z-значення атрактора (нижня межа гомеостазу) |
| `critical_z_max` | decimal | Максимум Z-значення атрактора (`> critical_z_min`) |
| `carbon_sequestration_coefficient` | decimal | Коефіцієнт секвестрації (> 0) для зваженого нарахування SCC |
| `biological_properties` | jsonb | `bark_thickness`, `foliage_density`, `fire_resistance_rating`, `optimal_z_target` (`sap_flow_index` знято [ARCH.102] ⚖️ 08-20 — споживача не існувало; історичні ключі в jsonb нешкідливі) |

**Ключові методи:**

| Метод | Повертає | Опис |
|-------|----------|------|
| `effective_optimal_z_target` | Float | [FW.8] `optimal_z_target || 29.0` — per-species sweet spot або global default |
| `healthy_z?(z_value)` | Boolean | Чи Z у межах гомеостазу |
| `weighted_growth_points(raw)` | Float | `raw * carbon_sequestration_coefficient` |
| `display_name` | String | "Quercus robur (Дуб звичайний)" або просто назва |

> 🔴 **[ARCH.84] `biological_properties` нормалізується ПЕРЕД валідацією, і це не гігієна — це дві живі поломки.** `store_accessor` кладе в JSONB рівно те, що приїхало, а з HTML-форми приїжджає **рядок**. Звідси: (1) порожній `number_field` шле `""`, `allow_nil` його не покриває — і кожна ОПЦІЙНА властивість ставала де-факто обовʼязковою (єдиний UI-шлях завести породу відповідав 422 «is not a number»); (2) заповнене поле осідало рядком, а `AlertDispatchService` ним арифметичить — `temperature_c >= "60"` (fire-поріг бере `fire_resistance_rating`) кидає `ArgumentError`, і ціна оманлива: його ловить сусідній `rescue ArgumentError` і рапортує «корупція Base64» на невинний шлюз, тобто провину приписано не туди. Тому `before_validation :normalize_biological_properties`: порожній рядок → ключ знімається, числовий рядок → число, **нечисловий лишається рядком** (щоб `numericality` про нього доповіла). ⛔ Не міняти на `to_f`: він зробив би «abc» нулем, тобто невалідне валідним, а fire-поріг — нульовим. ⚠️ `normalizes` тут не працює — `store_accessor` не є справжнім атрибутом (переміряно).
>
> 🔴 **[ARCH.86] Імпедансної осі тут НЕМАЄ, і це присуд, а не пропуск.** `baseline_impedance` (з `presence: true`), `death_threshold_impedance`, `stress_level` і пара `attractor_thresholds`/`_cached` знято 2026-08-13: пристрій імпеданс не міряє й ніколи не слав (немає поля в жодній ері wire-формату, ADC Солдата має два канали, у BOM немає компонента), а сідові значення були рядом номіналів резисторів E12. Дім порогів Лоренца для СПОЖИВАЧІВ — `Tree#effective_lorenz_thresholds` (він накладає ще й cluster-overrides); знята пара мала нуль продакшн-викликачів, а її докстрінг називав неіснуючих. ⛔ Не відбудовувати без рішення про сенсорний тракт — підстава й дослідження в [`00_07 §🗄️`](00_07_Action_Plan_Tracker) ARCH.86.
>
> ⚖️ **[ARCH.84] `carbon_sequestration_coefficient DEFAULT 1.0 NOT NULL` ЛИШАЄТЬСЯ — присуд founder 2026-08-19, і підстава в тому, що шкала ВІДНОСНА.** Дуб 1.5, сосна 0.8, тож `1.0` означає «рівно середній вид» — це законне значення, а не підстановка на місце невиміряного, і саме цим колонка відрізняється від решти класу. ⚠️ **Механізм не той, що здається:** порожнє поле форма ВІДХИЛЯЄ (`numericality` без `allow_nil` → 422), тобто дефолт спрацьовує не «коли забули», а показується людині вже підставленим у `number_field` — значення АВТОРСЬКЕ, підтверджене збереженням. ⛔ Не робити nullable: колонка годує `weighted_growth_points` → `Wallet#credit!` → мінт, тож нульабельність купила б fail-closed-гілку на грошовому тракті заради величини, яка визначена. ⊥ Дзеркало з ПРОТИЛЕЖНИМ вердиктом — `device_calibrations.vcap_coefficient` (той самий `DEFAULT 1.0`, але писача немає взагалі): картка `DeviceCalibration` нижче. **Однакова форма дефолту не означає однакового вердикту — вирішує наявність писача, не число.**

**Callbacks:** немає — пороги читаються ЖИВО (`Tree#effective_lorenz_thresholds`: `Cluster#lorenz_overrides_for` → `TreeFamily` → глобальні константи), кешу порогів не існує, тож і колбека-інвалідатора немає. ⛔ Не дописувати сюди `invalidate_thresholds_cache`: такого методу в моделі нема (виміряно 2026-09-03, OPS.38).

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
| `did` | string | `SNET-[8 HEX]` — ДЕРИВОВАНИЙ з 96-біт silicon UID (murmur3-fmix32, [`03_01 §7`](03_01_Firmware_Lifecycle_and_DMA)); НЕ сирий апаратний ідентифікатор |
| `silicon_uid_hex` | string | [FW.54] 24-hex кремнієвий паспорт (три %08X-слова UID); unique-nullable — відрізняє re-flash від DID-колізії (quarantine); nil = legacy-дерево до one-pass провіженінгу |
| `status` | enum | `active(0) / dormant(1) / removed(2) / deceased(3)` |
| `status_changed_at` | **datetime, nullable** | [SLASH-1, 2026-08-26] Мить останньої зміни `status` — штампує `before_save`-колбек моделі, і ЛИШЕ він. Носій `dead_count` у формулі шкоди ([`05_05 §3`](05_05_Slashing_and_Risk_Policy)): вирок мусить лічити й трупів, а не самих вцілілих. 🔴 **Три кандидати відхилено з ОДНІЄЇ підстави — чисельник шкоди не має бути клієнт-контрольованим:** `AuditLog` (Tree не аудитується), `MaintenanceRecord#performed_at` (мить вводить ОПЕРАТОР — той самий, чию шкоду міряють), `updated_at` (шумний — рухається від будь-якого запису). ⚠️ `NULL` для дерев, що вмерли ДО міграції — читач це знає й падає на `Time.current` |
| `firmware_update_status` | enum | OTA lifecycle (via Firmwareable) |
| `latitude`, `longitude` | decimal | WGS-84 координати (via GeoLocatable) |
| `last_seen_at` | datetime | Останній пакет телеметрії |
| `latest_voltage_mv` | integer | Денормалізована **напруга шини живлення MCU** (мВ VDDA, VREFINT-калібрування — [`03_01`](03_01_Firmware_Lifecycle_and_DMA) FW.50). ⚠️ **[ARCH.99]** НЕ заряд іоністора: каналу Vcap на вузлі не існує, тож здоровий вузол стоїть біля номіналу 3300 мВ |
| `latest_stress_index` | **decimal, nullable** | Денормалізований stress_index від `InsightGeneratorService`. ⚡ **[ARCH.84]** `NULL` = «не виміряно **за цю добу**» — окремий СТАН, не нуль; доти стояв `DEFAULT 0.0 NOT NULL`, див. нижче |
| `peaq_did` | string | peaq DID-ідентифікатор для Proof of Growth |
| `altitude` | numeric | ⚠️ **Не задротовано** [ARCH.103]: нуль посилань у `app/`/`lib/`, `GeoLocatable` знає лише lat/lng. Єдина згадка наміру — [`00_02 §1`](00_02_Academic_Integration_and_IP) (вибір висот Queen-шлюзів за оглядовими точками), і жоден інженерний розділ її не розвиває — link-budget [`02_01 §5.3`](02_01_Hardware_Architecture_and_BOM) моделює відстань і матеріали, не висоту |
| `firmware_version` | string | Версія прошивки STM32 (SemVer) |

**AASM State Machine (column: `status`):**

```
active ──suspend──► dormant
active/dormant ──decommission──► removed
active/dormant ──declare_deceased──► deceased
dormant ──reactivate──► active
```

**Константи:**
- ⛔ **`VCAP_MIN_MV` / `VCAP_MAX_MV` / `LOW_POWER_MV` ЗНЯТО** — [ARCH.99], присуд founder 2026-08-13. Вони описували шкалу іоністора, а прикладались до `latest_voltage_mv` = мВ VDDA; BQ25570 стабілізує ту шину на 3.3 В від VSTOR ≥ 3.4 В аж до 5.5 на іоністорі ([`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)), тож вона **за конструкцією не несе інформації про запас енергії** — buck існує рівно щоб сховати напругу сховища від MCU. Разом із константами знято `charge_percentage` і `low_power?`. **Повертати шкалу можна ЛИШЕ разом із живим Vcap-каналом** ([`00_07` — FW.50](00_07_Action_Plan_Tracker)); носій заборони — `spec/models/tree_spec.rb` «energy semantics [ARCH.99]»
- `SILENCE_THRESHOLD = 24.hours` — [transitional] дефолт порога тиші, ОДИН дім на `scope :silent` і `#fresh_signal?`; рантайм веде `TreeStalenessSweepWorker` через `SystemParameter`. **Дім сигналу «мало енергії»**: нижче `VBAT_UV` BQ25570 просто знеструмлює MCU, тож низький запас спостережуваний ЛИШЕ як тиша, ніколи як низьке число
- `DID_FORMAT = /\ASNET-[0-9A-F]{8}\z/`
- `GLOBAL_LORENZ_Z_MIN = 2.0` — [FW.8] global fallback (дзеркало `BioContract::CRITICAL_Z_MIN`)
- `GLOBAL_LORENZ_Z_MAX = 45.0` — [FW.8] global fallback
- `GLOBAL_LORENZ_Z_OPTIMAL = 29.0` — [FW.8] global fallback

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `mark_seen!(voltage_mv)` | Hot path: `GREATEST` атомарне оновлення `last_seen_at` + `latest_voltage_mv`. Обходить колбеки. 🔴 **[ARCH.109] Писати цей канал має право ЛИШЕ той, хто справді почув вузол** — для дерева це `TelemetryUnpackerService` (розпакований пакет), для шлюза `GatewayTelemetryWorker`/`UnpackTelemetryWorker`. ⛔ Людський артефакт (запис обслуговування, форма, ручна дія) `mark_seen!` НЕ кличе: до 2026-08-25 його безумовно штампував `EcosystemHealingWorker`, і одна людина двома кліками робила `hardware_pulse_confirmed?` [UI.7] істинним, ховала дерево від `Tree.silent` [SILENCE-1] і оживляла `fresh_signal?` [ARCH.99]. Підстава заборони — [`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap): тиша є єдиним чесним сигналом вузла, тож канал, у який пише гейтований актор, перестає бути доказом |
| `current_stress` | Читає `latest_stress_index` **як є** (денормалізовано, без N+1): `nil` = не виміряно [ARCH.84]. ⛔ Не повертати `.to_f`/`\|\| 0` — це була ридер-підстановка, і без її зняття міграція нічого б не змінила |
| `supply_voltage_mv` | Читає `latest_voltage_mv` **як є**: сира напруга шини VDDA, діагностична (просідання = близькість брауноуту), `nil` = не виміряно [ARCH.84]. **НЕ похідна для шкали заряду.** ⛔ Не повертати `\|\| 0` — доти цей рядок ПРИПИСУВАВ ту саму форму, яку рядок вище ЗАБОРОНЯЄ, тобто одна таблиця суперечила собі через рядок; і ціна тут вища, ніж у сусіда: **нуль мВ на цій шині означає браунаут**, тож вузол, що ніколи не виходив в ефір, друкувався найгіршим МОЖЛИВИМ виміром — на `trees/index` і на головній («0mV»), тоді як `trees/show` для тієї самої величини вже казав «не виміряно». Рендер — `ApplicationComponent#measured_value` |
| `latest_telemetry_log` | Останній рядок телеметрії ОДНОГО дерева (`trees#show`). 🔴 **Межа несуча:** у циклі по флоту вироджується в N+1 (`ORDER BY created_at DESC LIMIT 1` на дерево, по ВСІХ партиціях) — саме так він жив у прогнозі врожаю [PERF.1]; питання «останній рядок на КОЖНЕ дерево набору» має власний дім `TelemetryLog.latest_per_tree` (один `DISTINCT ON` на батч, [`04_02 §2`](04_02_Business_Logic_and_Services)-суміжне). ⚠️ **Сирота тут була ПОЗІРНА, і це урок про метод пошуку:** `trees#show` не кликав метод, а писав його тіло рукою, тож греп за ІМЕНЕМ показував нуль споживачів і схиляв зняти живий примітив — дублікат ховався другим ВИВОДОМ, не другим викликом (скіл `backend` #48). Зведено на дім 2026-08-15 |
| `fresh_signal?(threshold = SILENCE_THRESHOLD)` | **[ARCH.99]** Рядковий бік сигналу тиші — ОДИН дім порога для скоупа й в'ю. ⊥ Свідомо НЕ дзеркало `scope :silent`: той відкидає `last_seen_at IS NULL` (sweeper не гонить Field Audit на вузол, що ще не виходив в ефір), глядачеві ж «жодного пакета» = така сама відсутність свіжого сигналу. 🔴 **[ARCH.84, 2026-08-14] Периметр домкнуто — сайтів було ТРИ, і третій прожив довше за фікс:** `trees/index` перейшов на цей предикат ще при [ARCH.99], а `trees/show` лишався на рукописних «15 хв від `@latest_log.created_at`». Обидві величини штампуються в одній транзакції, тож розходились не дані, а ПОРОГИ — і одне дерево було зеленим у списку й мертвим на власній сторінці ~23 год 45 хв із кожних 24. ⊕ Заразом зникла тихіша розбіжність: `@latest_log` це останній РЯДОК телеметрії, тобто `nil` після retention-зрізу — сторінка називала мертвим дерево з живим `last_seen_at`. **Грепати такий залишок треба за СПІЛЬНИМ ВХОДОМ (`last_seen_at`), а не за іменем предиката: обхід його не згадує за побудовою** (той самий урок, що `Gateway#online?` — скіл `backend` #10) |
| `under_threat?` | `ews_alerts.unresolved.exists?` |
| `broadcast_map_update` | Turbo Stream → `geospatial_matrix_org_{cluster.organization_id}` — імʼя **org-скоуплене** (SEC.25); дерево без кластера не броадкастить узагалі (fail-closed; ⚠️ це вже НЕ «звичайний стан» — каскад став `restrict_with_error`, ⚖️ 2026-07-30, і гард лишається як defense-in-depth) |
| `effective_lorenz_thresholds` | [FW.8] `{ min:, max:, optimal: }` з 3-рівневим пріоритетом: Cluster override → TreeFamily → Global default. Використовується `TelemetryUnpackerService#check_z_divergence!` та `OtaPackagerService.build_threshold_config_block`. |

**Callbacks:**
- `after_create :build_default_wallet` — автоматично створює Wallet
- `after_create :ensure_calibration` — автоматично створює DeviceCalibration
- `after_update_commit :trigger_slashing_protocol` — при `removed?` або `deceased?` → `BurnCarbonTokensWorker`
- `after_update_commit :broadcast_map_update, if: :map_relevant_change?` — **множина тригерів = множина колонок, які маркер справді малює** (`Dashboard::MapNode`: lat · lng · status · `latest_stress_index`), і рівність тут не косметика, бо розійтись вона вміє В ОБИДВА боки, обидва тихо [ARCH.84]: тригер, якого бракує, вбиває живе оновлення (стрес — колір маркера — не броадкастився ніколи), а зайвий перемальовує вузол на величину, якої вже не існує в розмітці (`latest_voltage_mv` лишався тригером ще після того, як [ARCH.99] зняв `data-charge`) — у механізмі, збудованому саме щоб броадкасти скоротити. 🔴 **Колбек — лише ОДНА з двох умов доставки:** усі писачі денормалізованого стресу йдуть `update_column`/`update_all`, які колбеків не пускають взагалі, тож броадкаст там **явний** ([`04_02 §3`](04_02_Business_Logic_and_Services), `InsightGeneratorService`). Правлячи будь-яку з половин, полагодь ОБИДВІ — кожна поодинці не міняє нічого видимого. Носії: `spec/models/tree_spec.rb` (тригери, з дзеркалом «напруга НЕ перемальовує») + `spec/services/insight_generator_service_spec.rb` (пін на кожного з трьох писачів)

**Scopes:** `active`, `geolocated`, `silent` (> 24 год мовчання). ⛔ `critical_stress` **знято 2026-08-25** [SLASH-1] як мертву гілку — нуль викликачів поза власною спекою, при трьох пастках усередині (сирий `0.8` замість DAO-live `AiInsight.slash_stress_threshold` · строге `>` проти `>=` у живих споживачів · `joins` без `.distinct`, тобто лічба РЯДКІВ замість ДЕРЕВ — рівно та, що вже роздувала спалення [ARCH.46]).

> ⚡ **«НЕ ВИМІРЯНО» = СТАН, А НЕ ЗНАЧЕННЯ — друга колонка того ж класу [ARCH.84].**
> `latest_stress_index` більше не має ані `DEFAULT 0.0`, ані ридера-підстановки.
>
> 🔴 **Підстава та сама, що в `health_index`, і тут вона СИЛЬНІША: нуль — не просто
> досяжний вимір, а МОДАЛЬНИЙ.** `calculate_stress_index_heuristic` віддає рівно
> `0.0` здоровому дереву (обидва доданки — sap і акустика — інертні до
> ENV-калібрування), тож «бездоганне» й «не міряли» були **одним числом**, і жоден
> споживач їх не розрізняв. Ціна була видима: після зняття фабрикованої
> `charge`-ноги ([ARCH.99]) колір маркера на карті тримається на самому стресі —
> і невиміряне дерево малювалось **смарагдовим «гомеостазом»**.
>
> **Писач дає вердикт КОЖНОМУ дереву за добу — двома шляхами, бо діри дві:**
>
> | Хто мовчить | Механізм | Чому окремо |
> |---|---|---|
> | дерево в кластері, що має дані | `InsightGeneratorService#process_cluster_trees` — явний `nil` замість `next` | цикл уже обходить кожне дерево кластера; додається лише запис |
> | кластер, що замовк ЦІЛКОМ | `InsightGeneratorService.reset_stress_outside(cluster_ids)` — один set-based `UPDATE` | обидва шляхи писача (синхронний і шардований) беруть `cluster_baselines.keys`, тобто мовчазний кластер не відвідується ВЗАГАЛІ |
>
> ⚠️ Другий механізм враховує `cluster_id IS NULL` **явно**: `belongs_to :cluster,
> optional: true`, а `NOT IN` такі рядки мовчки виключає (та сама сліпота, що
> [ARCH.98]). І межа `IS NOT NULL` тримає набір мінімальним — знаменник тут 10¹²
> ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap)).
>
> ⊥ **Відмінність від `health_index`, і вона несуча:** там колонка пер-КЛАСТЕРНА й
> агрегується, тож їй знадобилась структура покриття (`Cluster.health_coverage`).
> Ця — пер-деревна, тож сама по собі підстави не потребує; її потребує КОЖЕН, хто
> зводить дерева в одне число — і байдуже, СУМОЮ чи СЕРЕДНІМ.
> 🔴 **Тут доти стояло «покриття потрібне лише там, де дерева СУМУЮТЬ», і це
> узагальнення було ХИБНЕ — воно ж і аргументувало геть механізм, який упіймав би
> [ARCH.84]-дефект поверхом нижче** (виміряно 2026-08-17): кластерний
> `AiInsight.stress_index` УСЕРЕДНЮЄ дерева, і кластер із одним виміряним деревом
> із пʼяти віддавав той самий `stress_index`, той самий `health_index` і те саме
> `health_coverage(measured: 1, total: 1)`, що й виміряний повністю. Середнє
> залежить від покриття не менше за суму — і подає себе переконливіше, бо
> читається як властивість цілого. Споживачів покриття тому **два**: прогноз
> емісії ([`04_03 §5.9`](04_03_REST_API_v1_Reference)) і кластерний денний
> агрегат (`AiInsight` §7 — `measured_trees`/`total_trees`).
>
> ⛔ Бекфілу немає свідомо: єдиний доступний дискримінатор («дерево має AiInsight
> ⇒ колонку писали») спростовується сідами — вони створюють `daily_health_summary`
> кожному дереву й колонку не писали; тепер пишуть.

---

### `Cluster` — Геопросторовий Контейнер

**Призначення:** Лісовий сектор (гектар, квартал). Об'єднує Дерева та Шлюзи. Одиниця NaaS-контракту.

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `organization` | `belongs_to` | Власник |
| `trees` | `has_many, dependent: :restrict_with_error` | Солдати. ⚠️ Було `:nullify` — знято присудом ⚖️ 2026-07-30: `clusters.id` є **фабрично-заморожена координата** (HKDF-salt прошитих `K_ota`/`KEYB` + координата історичних MRV-груп), тож занулення стирало б реєстр salt і робило `unprovable` минулі якорі. Повний розбір і два ⛔-наслідки (tree-transfer неможливий · кластер не розщеплюється на чотири сутності) — §10 нижче |
| `gateways` | `has_many, dependent: :restrict_with_error` | Королеви. ⚠️ Було `:nullify` при `gateways.cluster_id NOT NULL` — тобто декларація, чий єдиний можливий вихід був `PG::NotNullViolation` (ARCH.76, виміряно рантаймом). Знято тим самим присудом, що й `trees` |
| `naas_contracts` | `has_many, dependent: :restrict_with_error` | Захист фінансової історії |
| `parametric_insurances` | `has_many, dependent: :restrict_with_error` | Захист страхової історії |
| `blockchain_transactions` | `has_many, dependent: :restrict_with_error` | **[ARCH.76, 2026-08-13]** Cluster-sourced гроші (`wallet: nil` — слеш «останнього дерева», Celo-винагорода). ⚠️ DB-FK `fk_blockchain_transactions_cluster_id` існував і без цієї асоціації, тож Rails не мав куди поставити `restrict`, і `cluster.destroy` падав СИРИМ `PG::ForeignKeyViolation` повз усю драбину `rescue_from` — клас гірший за відсутній `dependent:`, бо той видно при читанні `has_many`, а тут декларації не було взагалі |
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
| `health_index` | **double precision, nullable** | Денормалізований індекс `1.0 - stress_index` (0..1). ⚡ **`NULL` = «не виміряно» — окремий СТАН, не нуль і не порожнеча** [ARCH.84], див. нижче. ⚠️ Тут доти стояло `decimal`, а схема каже `double precision` — і в цьому дереві різниця не косметична: `decimal` приходить у Ruby BigDecimal'ом, а `CLAUDE.md §6` окремо вимагає Float (IEEE 754) на Lorenz-шляху, бо він бітово дзеркалить mruby |
| `entropy_score` | float | Нормалізована ентропія Шеннона Z-розподілу (0..1). Оновлюється `ClusterEntropyAnalyzerWorker` |
| `active_trees_count` | bigint | Counter cache (оновлюється Tree callbacks) |
| `climate_type` | string | Кліматичний тип зони (напр. "temperate_continental") |
| `environmental_settings` | jsonb | `custom_fire_threshold`, `seismic_sensitivity_threshold`, `timezone`, `lorenz_overrides_by_species` |
| `ota_version_hiwater` | bigint | [SEC.20] Anti-rollback high-water: максимальний `BioContractFirmware#id`, ВЖЕ dispatch-нутий у кластер. Guard `firmware.id > hiwater` + бамп — `Ota::DeploymentDispatcherService` ([`03_06 §4`](03_06_Factory_Flashing_and_Key_Provisioning)); default 0 = кампаній не було |

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
| `health_index` | Читає денормалізовану колонку **як є**: `nil` = не виміряно [ARCH.84] |
| `Cluster.health_coverage(scope)` | **One-Home агрегату** → `HealthCoverage(average:, measured:, total:)` одним запитом; предикати `no_clusters?` ⊥ `unmeasured?` ⊥ `partial?` |
| `recalculate_health_index!` | `1.0 - stress_index` зі щоденного AiInsight за `AiInsight.reporting_date`; **без ВИМІРУ пише явний `nil`** — гард питає сам `stress_index`, а не наявність інсайту [ARCH.84]: колонка легально `NULL` (`allow_nil: true`), і `nil.to_f` дав би рівно `1.0`, тобто «бездоганний ліс» для стресу, якого не рахували. ⚠️ Виміряний `0.0` лишається законним входом (→ `1.0`), тож дискримінатор — `nil`, ніколи `.zero?`/`present?`. 🔴 **Друга вісь, і гард її не покриває ЗА ПОБУДОВОЮ [ARCH.84]:** він судить, чи вимір Є, і не питає, про СКІЛЬКИ дерев той вимір говорить — а вхід є середнім по тих, що заговорили. Тому підстава живе не тут, а на самому інсайті (`reasoning.measured_trees`/`total_trees`, `AiInsight` §7), і читач `health_index` зобовʼязаний везти її поруч (`Clusters::Show` → `measurement_coverage`) |
| `geo_center` | Мемоізований центроїд полігону (Resilient — підтримує MultiPolygon) |
| `active_contract` | Останній активний NaasContract (з ORDER BY) |
| `active_threats?` | `ews_alerts.unresolved.critical.exists?` |
| `mapped?` | Чи є GeoJSON координати |
| `lorenz_overrides_for(scientific_name)` | [FW.8] Повертає `{ min:, max:, optimal: }` або `nil` для даного виду. Читає `lorenz_overrides_by_species[scientific_name]`. |

**Scopes:** `alphabetical`, `containing_point(lat, lng)`, `under_threat`.

> ⚡ **«НЕ ВИМІРЯНО» = СТАН, А НЕ ЗНАЧЕННЯ [ARCH.84].** `health_index` більше не має ридера-підстановки, а писач кладе **явний `NULL`** щоразу, коли ВИМІРУ немає — і межа тут по виміру, не по його носієві: інсайт може існувати з `stress_index IS NULL` (колонка `allow_nil`), тож гард питає саме поле, інакше `nil.to_f` віддав би `1.0` — «бездоганний ліс» для стресу, якого не рахували.
>
> 🔴 **Підстава герметична й не потребує міркувань про напрямок fail-safe: `1.0` — ДОСЯЖНЕ ВИМІРЯНЕ значення** (`stress_index == 0` → `1.0 − 0`; пін «returns 1.0 when stress_index is 0» стоїть у `cluster_spec` роками). Доти воно ж підставлялось на порожнечу — тобто «бездоганний ліс» і «ми його не міряли» були **одним числом**, і жоден споживач їх не розрізняв. Прецедент форми — [`ARCH.81`](00_07_Action_Plan_Tracker): скалярне поле не вміє сказати «не знаю», тож стан робиться першокласним.
>
> **Стани агрегату** (`Cluster.health_coverage`, один SQL-запит — `COUNT(колонка)` рахує не-NULL, `COUNT(*)` усі):
>
> | Стан | `average` | Значення |
> |---|---|---|
> | `no_clusters?` | `nil` | Міряти **нема чого** — структурний стан |
> | `unmeasured?` | `nil` | Кластери Є, жоден не виміряно — операційний стан, **не те саме, що попередній** |
> | `partial?` | число | Виміряно частину. Число правдиве про **підмножину** — тому `measured`/`total` їдуть разом із ним, і в'ю **зобовʼязана** їх показати |
> | (повне покриття) | число | Твердження про весь набір |
>
> ⚠️ **Партіальний стан створює сама відмова від підстановки:** доти NULL-ів у стійкому стані не бувало (писач їх забивав), тож `AVG`, що мовчки пропускає NULL, нікому не брехав. Відвантажити середнє **без** покриття означало б завести свіжу брехню замість старої — мовчазний відкид невиміряних і є той «відбір», який місія ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap)) забороняє словом «**невідбирано**».
>
> ⛔ **Округлення в домі обчислення НЕ живе** — воно подача, і в кожного споживача своя (портфель показує один знак, `health_score` два). Спіймано прикладом: `round(2)` у домі перетворив «87.3%» на «87.0%».
>
> ⚠️ Колонка не знає, ЯКУ добу описує: `ClusterHealthCheckWorker` приймає довільну дату, тож значення = «результат останнього прогону з тією датою, яку той узяв».

> ✅ **PostGIS: `geo_boundary` — GENERATED ALWAYS ... STORED [E.36, закрито 2026-08-14].**
> Синхронізація `geojson_polygon` → `geo_boundary` більше не тригерна: колонка обчислюється рушієм БД, тригер і функція `sync_cluster_geo_boundary()` знято.
>
> 🔴 **Це була НЕ оптимізація, і саме тому потребувало присуду власника: змінилась СЕМАНТИКА ПОМИЛКИ.** Тригер мав `EXCEPTION WHEN OTHERS` і на битому GeoJSON тихо писав `NULL` — запис проходив. Вираз generated column винятків ловити не може, тож тепер це **hard-fail при записі**. Підстава присуду: кордон кластера, тихо записаний як NULL, є втратою геометрії там, де координата входить у ДОКАЗ (MRV-лінійка, Field Audit) — гучна відмова чесніша за NULL, якого ніхто не помітить.
>
> ⚠️ **`CASE` без `ELSE` лишає легальним «кордон не заданий»:** відсутній або неповний GeoJSON (`type`/`coordinates` = NULL) і далі дає NULL. Змінилась доля саме **невалідного** — доти EXCEPTION-хендлер зводив його до того самого NULL.
>
> ⚠️ **«КОЛИ» важило більше за «чи»:** на порожній таблиці це `DROP+ADD` без переписування рядків; після польового деплою та сама операція означала б `ACCESS EXCLUSIVE` rewrite tenant-root + GIST-rebuild + ризик backfill'у на битих рядках.
>
> 🔬 **Виміряно ПЕРЕД міграцією, а не припущено:** вираз generated column мусить бути IMMUTABLE, і обидві функції такими є (`pg_proc.provolatile = i`) — інакше PostgreSQL відхилив би колонку за побудовою. Перевірено рантаймом ПІСЛЯ: битий GeoJSON → `PG::InternalError`, валідний → обчислено.
>
> ⚠️ **У Ruby ця колонка — РЯДОК, не геометрія, і це властивість платформи, а не цієї колонки.** Адаптер тут `postgresql`, не `postgis` (гема немає навмисно — [`Gemfile`](../Gemfile)), тож жоден просторовий тип у реєстрі не зареєстрований: AR логує `unknown OID … will be treated as String` і віддає WKB-hex. Той самий клас уже жив у дереві задовго до E.36 на іншій `geography(Point,4326)`-колонці — тобто він **не новий**, і попередження в логах сюїти не є симптомом цієї міграції. Наслідок практичний: просторову роботу робить БД (GiST-індекс, `ST_*` у SQL), а читати колонку в Ruby як об'єкт **не можна** — той, кому це знадобиться, заводить `activerecord-postgis-adapter` окремим присудом, бо він змінює адаптер усій програмі.
>
> ⊕ Побічно зникла функція, яку `pg_dump` не вміє зберігати з `OR REPLACE` — клас «неідемпотентна функція у `structure.sql`» закрився сам собою.
>
> ⚠️ **`unknown OID …: failed to recognize type of 'geo_boundary'. It will be treated as String` у консолі — ШУМ, не дефект, і це перевірено, щоб наступний читач за ним не гнався.** PostGIS-тип не зареєстрований в адаптері, тож AR не десеріалізує значення — але **жоден рядок Ruby його й не читає**: усі звертання йдуть через SQL (`ST_Contains(…)` у скоупі `containing_point`, `where.not(geo_boundary: nil)` у предикаті `geo_boundary_present?`). Десеріалізації немає кому знадобитись. Попередження стане значущим рівно тоді, коли зʼявиться перший Ruby-читач самого значення.

---

## ⚙️ 3. Апаратний Рівень

### `Gateway` — Королева (LoRa Шлюз, star-only)

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
| `config_sleep_interval_s` | integer | Інтервал сну (≥ 60 сек). 🔴 **[ARCH.115] Це НАШЕ ПЕРЕКОНАННЯ про пристрій, а не його поведінка: прошивка колонку НЕ ЧИТАЄ** (`grep sleep_interval firmware/` = нуль), і downlink'а, який доніс би її Королеві, не існує — реальний каденс зашитий компайл-тайм таймером `FLUSH_INTERVAL_MS` + jitter. Тобто шлюз на 3600 і шлюз на 300 флашать ОДНАКОВО. ⛔ **Не будувати на ній вікон живості:** `Gateway#online?`/`.online`/`.offline` до 2026-08-29 рахували вікно саме звідси, і сідовий шлюз (1800) числився `offline` ~25 хв щогодини — хибний critical `queen_offline`, виключення з `ota_deployable`, і `EmergencyResponseService.deliverable?` хибний на пожежному протоколі. Дім вікна тепер — `Gateway::LIVENESS_WINDOW_S` (виміряний каденс × 1.2), спільний зі скоупами. ⊕ Колонка лишається як **намір конфігурації** (її показує UI, її валідує модель) і як вхід `next_wakeup_expected_at`; ВИМІРОМ вона стане тоді, коли зʼявиться downlink-тракт доставки конфігу |
| `ip_address` | string | Спостережений source-IP **останнього uplink** (`mark_seen!`; nil до першого виходу в ефір). Це CGNAT/Starlink-egress — НЕ inbound-reachable адреса ([`00_07` FW.60](00_07_Action_Plan_Tracker)) |
| `last_seen_at` | datetime | Останній CoAP batch |
| `last_attested_at` | datetime | **[L1 QATT]** Останній батч з валідним Ed25519-підписом Королеви (wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security)); `nil` = шлюз на L0 |
| `latest_voltage_mv` | integer | Денормалізована напруга |
| `firmware_version` | string | Версія прошивки STM32 (SemVer) |
| `altitude` | numeric | ⚠️ **Не задротовано** [ARCH.103]: нуль посилань у `app/`/`lib/`, `GeoLocatable` знає лише lat/lng. Єдина згадка наміру — [`00_02 §1`](00_02_Academic_Integration_and_IP) (вибір висот Queen-шлюзів за оглядовими точками), і жоден інженерний розділ її не розвиває — link-budget [`02_01 §5.3`](02_01_Hardware_Architecture_and_BOM) моделює відстань і матеріали, не висоту |
| `helium_dev_eui` | string | **[ARCH.54]** Helium SOS fallback dev EUI (`HeliumSosWorker` → `EwsAlert(queen_uplink_lost)`) |
| `ota_started_at` | datetime | **[ARCH.59]** якір віку КАМПАНІЇ для stuck-OTA watchdog'а (`GatewayStalenessSweepWorker`). ⚠️ Ставить його **диспетчер** при таргетингу, а poll-тракт **не перезаписує**: інакше шлюз, що поллить рідко, обнуляв би власний годинник і не старів ніколи, а вікно між таргетингом і першим анонсом лишалось би без якоря взагалі — саме там живуть keyless-таргет, Королева, що не поллить, і dangling `pending_firmware_id`. Доти тут стояло «якір майбутнього watchdog'а, sweep-воркера ще нема» — протухло 2026-08-13, виправлено 08-16 |
| `pending_firmware_id` | bigint | **[FW.60]** таргет OTA-кампанії per-gateway (пише dispatcher атомарно з hiwater-burn; canary-когорта); Королева дізнається через hint у власному poll'і, глушиться спостереженим `?fw=` — [`04_02`](04_02_Business_Logic_and_Services) `Downlink::PendingQueueService` |

> **Примітка:** `firmware_hash` НЕ є полем Gateway і колонкою не стане — присуд власника
> 2026-08-14 ([`00_07`](00_07_Action_Plan_Tracker) UI.10): рядок знято з UI, а не задротовано.
> Підстава — не відсутність кандидата, а те, що єдиний кандидат (`pending_firmware_id` →
> `bio_contract_firmwares.binary_sha256`) називає хеш **очікуваної** прошивки, тоді як сусідній
> `firmware_version` називає **встановлену**: дві різні прошивки в сусідніх рядках під спільним
> підписом. Хеш як доказ цілісності належить attestation-осі (QATT), не конфіг-панелі. Хеші
> OTA-артефактів живуть у `BioContractFirmware` / `TinyMlModel` (`binary_sha256`), окремої
> моделі `Firmware` немає.

**AASM State Machine (column: `state`):**

```
idle ──wake──► active ──sleep──► idle
idle/active ──begin_update──► updating ──finish_update──► idle
idle/active/faulty ──enter_maintenance──► maintenance ──exit_maintenance──► idle
any ──report_fault──► faulty
faulty ──recover──► idle              # [ARCH.54 Шар 0] sweeper повертає шлюз у стрій
```

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `mark_seen!(new_ip:, voltage_mv:)` | `GREATEST` атомарне оновлення, обходить колбеки |
| `online?` | `last_seen_at >= (sleep_interval * 1.2).seconds.ago` |
| `next_wakeup_expected_at` | `last_seen_at + sleep_interval` |
| `battery_critical?` | `latest_voltage_mv < 3300`. ⚠️ **[ARCH.99]** Гілка сьогодні НЕ виконується: писача колонки не існує (пульс QATT-v2 напруги не несе — у Королеви нема ADC), тож `.present?` завжди хибний. Fail-closed у безпечний бік, свідомо — предикат чекає залізного тракту. ⊥ НЕ те саме, що зняте в `Tree`: там величину міряли, і вона не могла відповісти на питання; тут її ще не міряють |
| `system_fault?` | EwsAlert `system_fault` або `battery_critical?` — доки другий операнд мертвий, зводиться до першого. Живий сигнал стану доти — тиша (`Gateway.offline` + `GatewayStalenessSweepWorker`, [`06_08 §1.3`](06_08_Resilience_and_Failover_Policy)) |

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
| `binary_lorenz_seed` | **[SEC.11]** `[lorenz_seed_hex].pack("H*")` — мемоізовано (32 байти `K_seed`); входить у `SilkenNet::SeedDerivation.initial_state(seed_bin, epoch_day)` |
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
| `vcap_coefficient` | decimal | 1.0 | Коефіцієнт напруги (0 < x < 2.0) |

**Константи критичного дрейфу:**
- `MAX_TEMP_DRIFT = 5.0` °C
- `MAX_VCAP_TOLERANCE = 0.2` (20%)

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `normalize_temperature(raw)` | `raw + temperature_offset_c` |
| `normalize_voltage(raw)` | `raw * vcap_coefficient` |
| `sensor_drift_critical?` | Перевищення порогів → потрібна заміна |

> ⚠️ **[ARCH.86] Осей калібрування ДВІ, не три.** `impedance_offset_ohms` / `MAX_IMPEDANCE_DRIFT` / `normalize_impedance` знято 2026-08-13 разом з імпедансною віссю: офсет калібрував сенсор, якого немає, писачів у проді мав нуль, а `normalize_impedance` не кликав ніхто — unpacker нормалізує лише температуру й напругу. Гілка `sensor_drift_critical?` лишається живою на температурі й `vcap`.

**Callback:** `after_save :check_for_hardware_fault` — при критичному дрейфі автоматично створює `EwsAlert` (system_fault / medium), дедуплікація через `find_or_create_by!`.

> ⚖️ **[ARCH.84] Увесь шар калібрування СЬОГОДНІ ІНЕРТНИЙ — присуд founder 2026-08-19: оголосити, не лагодити.** Писачів у `vcap_coefficient` і `temperature_offset_c` **нуль** — контролера немає, маршруту немає, сіди їх не пишуть; єдині присвоєння це `set_defaults` (`||= 1.0` / `||= 0.0`) у самій моделі та `Tree#ensure_calibration`, що створює рядок із самими дефолтами. **Два наслідки, обидва структурні.** (1) Обидві диз'юнкти `sensor_drift_critical?` хибні назавжди (`(1.0 − 1.0).abs > 0.2` ⊥ `0.0.abs > 5.0`), тож `after_save :check_for_hardware_fault` не підніме `EwsAlert(system_fault)` **ніколи** — канал апаратного дрейфу озброєний, але не має чим вистрелити. (2) `normalize_voltage` і `normalize_temperature` сьогодні є ТОТОЖНИМИ перетвореннями, тобто «нормалізований» вимір побайтово дорівнює сирому. ⚠️ **Периметр ширший за той, що називав пункт:** він казав про `vcap_coefficient`, а вимір дає обидві осі — інертна не колонка, а МОДЕЛЬ. 🧭 **Пускач оживлення названо:** перший писач цих колонок (стендова калібровка). ⛔ Доти не «лагодити» предикат і не робити колонки nullable — нульабельність шляху не будить, вона лише міняє форму мовчання. ⊥ Дзеркало з ПРОТИЛЕЖНИМ вердиктом — `tree_families.carbon_sequestration_coefficient`: той самий `DEFAULT 1.0`, але писач Є (людина у формі), тож там `1.0` є авторським значенням, а тут — незаповненим слотом.

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
| `bio_status` | enum | `homeostasis(0) / stress(1) / anomaly(2) / vm_error(3)` — **[SLASH-1 P0]** код 3 = `BIO_STATUS_VM_ERROR` (софт-збій прошивки: mruby-crash/OOM/unprovisioned), НЕ tamper; фізичний tamper їде PANIC_FLAG-каналом (стара назва `tamper_detected` інвертувала semantics → хибний positive-A slash) |
| `temperature_c` | decimal | Температура кристала STM32 у капсулі анкера (°C), після `DeviceCalibration#normalize_temperature`. ⚠️ **[ARCH.99]** НЕ температура ксилеми — окремого сенсора в деревині немає; сирий wire-градус (той, з якого прошивка рахувала Z) живе окремо, [FW.57 F2] |
| `voltage_mv` | integer | **[ARCH.99]** Напруга шини живлення MCU (мВ VDDA, VREFINT-калібрування — [`03_01`](03_01_Firmware_Lifecycle_and_DMA) FW.50). ⚠️ НЕ напруга EBFC і не заряд іоністора: обидві ті величини вузол не міряє (ADC має рівно два канали — внутрішня температура + VREFINT) |
| `z_value` | decimal | Z-значення Атрактора Лоренца |
| `acoustic_events` | integer | Кількість акустичних подій (TinyML) |
| `mesh_ttl` | integer | Time-To-Live пакету в mesh-мережі (на прибутті; стартовий — 3 normal / 5 panic, дзеркало firmware `DEFAULT_TTL`/`PANIC_TTL`) |
| `panic` | boolean | **[FW.29]** Панічний пакет (PanicFlag, біт 7 StatusByte; default `false`). Єдина надійна wire-ознака паніки — `acoustic_events=255` колізує з FW.22-сатурацією |
| `queen_uid` | string | UID Королеви-ретранслятора |
| `oracle_status` | enum | **[BLOCKER-12 FIX]** `pending / dispatched / fulfilled / failed` (string-backed Rails enum з prefix `oracle_status_`). Забезпечує type safety, валідацію та автоматичні scope-методи (`oracle_status_dispatched`, `oracle_status_fulfilled` тощо). Default: `pending`. |
| `firmware_version_id` | integer | Версія прошивки з padding-байтів |
| `growth_points` | numeric | Нараховані бали зростання (raw) |
| `metabolism_s` | integer | Час метаболічного циклу (с) |
| `rssi` | integer | RSSI LoRa-каналу (дБм) |
| `sap_flow` | numeric | ⚠️ **Колонка без ЖОДНОГО писача** — поля немає в жодному wire-форматі, тож у проді вона структурно `NULL` [ARCH.102]. Два читачі (sap-терм стресу, ML-фіча `sap_deviation`) знято 2026-08-16 — вимірювача не існує. 🔴 **А ТРЕТІЙ живий і донині, і саме він робить порожньою цілу сторінку** [ARCH.103, виміряно 2026-08-17]: `OracleVisionsController#calculate_expected_yield` бере `sap_flow` через мапу `TelemetryLog.latest_per_tree`, тож `next if sap_index.nil?` спрацьовує на КОЖНОМУ дереві — покриття прогнозу структурно `0 з N`, а «Projected 24h Emission» є константою `0.0`. Число при цьому НЕ бреше (покриття їде поруч), тож читач лишений свідомо з названою умовою оживлення — поле `sap_flow` у wire-форматі. ⚠️ **Урок про свіп:** попереднє «читачі знято» було чесним виміром за ІМЕНЕМ колонки; цей сайт заходить за спільним ВХОДОМ (мапа `tree_id → log`), тобто імені моделі поруч не має. Прецедент маркування — `tamper_detected` нижче |
| `humidity` | numeric | **[HW.32]** Відносна вологість повітря (% RH, BME280) — climate frame, nullable |
| `pressure` | numeric | **[HW.32]** Атмосферний тиск (hPa, BME280) — nullable; барометр → раннє попередження про шторм |
| `vpd` | numeric | **[HW.32]** Vapor Pressure Deficit (kPa) — прямий confounder сокоруху (False-Slashing guard, [`05_05 §6/§7`](05_05_Slashing_and_Risk_Policy)). Hot-path: device шле VPD-індекс; nullable. ⚠️ НЕ входить у Lorenz-Z (DCI-guard) |
| `verified_by_iotex` | boolean | Підтверджено IoTeX W3bstream ZK-proof |
| `zk_proof_ref` | string | Посилання на ZK-proof IoTeX |
| `gateway_attested` | boolean | **[L1 QATT]** Рядок приїхав під валідним Ed25519-підписом Королеви (default `false`; wire-дім [`03_05 §2.2`](03_05_Hardware_Symmetric_Crypto_and_Security), ladder [`05_02`](05_02_Proof_of_Growth_Pipeline)) |
| `chainlink_request_id` | string | ID запиту Chainlink Oracle |
| `tamper_detected` | boolean | ⚠️ **DEAD-колонка** — жоден код не читає і не пише (tamper-семантика живе в алертах: panic→`chainsaw_detected`, ручний `vandalism_breach`); кандидат на прибирання або майбутній HW tamper-канал (tamper-switch/SE05x) |
| `archive_root` / `merkle_leaf` | string(64) ×2 | **[E.60]** стемп архів-батчу (пише pin-воркер raw-SQL'ем ПІСЛЯ звірки кореня): `archive_root` = корінь батчу-власника (join-ключ до `TelemetryArchiveBatch`), `merkle_leaf` = CID листа. Partial index `WHERE merkle_leaf IS NOT NULL` (sweeper-семпл). **Seal-guard** `before_update` (перший AR-колбек моделі; прецедент `AuditLog#forbid_business_field_mutation!`): мутація leaf-payload-поля (`z_value`/`bio_status`/`created_at`/`tree_id`) стемпнутого рядка = raise; пара захистів — guard тримає AR-шлях, sweeper-нога ловить raw-SQL. KENOSIS недоторканий (intake = insert_all, колбек не стріляє) |
| `cold_start_flag` | boolean | `true` якщо пакет перший після VBAT loss (initial_state від K_seed, не warm chain) |
| `lorenz_state_x/y/z` | float | Хвіст траєкторії Лоренца для chain-старту наступного пакету |
| `time_unsynced_fallback` | boolean | `true` якщо DCI mismatch відновлено через ARCH.41 epoch_day fallback (Soldier мав застарілий RTC після VBAT loss); `CMD_TIME_SYNC` downlink поставлено в чергу автоматично |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `relayed_via_mesh?` | `mesh_ttl < стартовий TTL типу пакета` (`panic? ? 5 : 3` — `INITIAL_TTL_PANIC/NORMAL`). До FW.29-персистенції давній default 5 позначав «релейнутим» кожен direct normal-пакет |
| `critical?` | `anomaly?` або `vm_error?` |
| ⛔ *знято* | `healthy?` · `optimal?` · `recovery_confirmed?` + колонка `trees.health_streak` — anti-flapping-петля, ⚖️ присуд founder 2026-08-16. Підстава НЕ «нуль читачів» (продакшну не було), а хибна КОНСТРУКЦІЯ: критерій закриття не спростовує критерій відкриття — `healthy?` не кликав `Attractor.homeostatic?`, тобто був сліпий до половини тригера посухи; для `insect_epidemic` міряв кавітацію (класу «комаха» в TinyML немає); для `entropy_anomaly` — інший рівень агрегації. Не відроджувати: канон [`05_05`](05_05_Slashing_and_Risk_Policy) INS.1 призначив суддею ЛЮДИНУ, а активна біо-тривога є ворітьми перед незворотною виплатою → [`00_07`](00_07_Action_Plan_Tracker) ARCH.84 |
| `.partition_pruned(iso, metric_caller:)` | **[S6.16]** One-Home pruning-логіки: chainable 1с-вікно по `created_at` (толерантне до секундної точності ISO — стандарт `BlockchainTransaction`) + облік degraded path лічильником `unpruned_lookups`. Воркери/сервіси/контролери делегують сюди, НЕ дублюють |

**Scopes:** `recent`, `anomalies`, `in_timeframe` (`vandalized` видалено — мертвий scope на хибній tamper-семантиці).

> ⚡ **KENOSIS TITAN:** Валідації видалено з hot path. Перевірка відбувається в `TelemetryUnpackerService.valid_sensor_data?` до INSERT.

> ⛔ **CLEANUP CONSTRAINT [DOC.8]:** рядкового cleanup над `telemetry_logs` **не існує, і це присуд** (⚖️ 2026-08-21, [`00_07`](00_07_Action_Plan_Tracker) ARCH.59). Ретеншн сирої телеметрії робить ВИКЛЮЧНО дроп місячних партицій; будь-який `delete_all`/ad-hoc DELETE тут — регресія. ⚠️ **Читати як ДОЗВІЛ, не як опис системи:** дозволений механізм рівно один, але його ще НЕ збудовано (автоматичного дропу в `app/`/`lib/` немає — [`00_07`](00_07_Action_Plan_Tracker) ARCH.70), тож фактичний ретеншн сирої телеметрії сьогодні нульовий, а гард нижче стереже, щоб доти не зʼявився ДРУГИЙ шлях, і її ловить `spec/quality/telemetry_retention_home_spec.rb`. **Підстава — прилад, а не смак:** тракт архіву вже очікує саме дропу й має для нього чесний стан (`TelemetryArchiveBatch.retention_expired` = «листя менше, бо партиції дропнуто — НЕ tamper»), тож ДРУГИЙ механізм зникнення рядків зробив би цей статус неоднозначним.
>
> ⚠️ **Але сам інваріант не помер — він змінив адресата, і це неочевидно: дроп партиції НЕ ВМІЄ виключати рядок.** Стара вимога («виключай `oracle_status = 'dispatched'`, бо запис чекає callback і його зникнення дасть `RecordNotFound` у `OracleCallbacksController`») була здійсненна лише для рядкового DELETE. Партиційний дроп знімає місяць цілком, тож питання перетворюється на **ширину вікна**: доки партиція жива, живий і незакритий dispatch. Це робить дроп СУВОРО безпечнішим за попередній семиденний DELETE (місяці замість тижня), але вибір горизонту тепер несе money-вагу й належить механізму дропу — [`00_07`](00_07_Action_Plan_Tracker) ARCH.70. Cross-ref: [`04_02 §3` InsightGeneratorService](04_02_Business_Logic_and_Services#insightgeneratorservice), [`05_02` — PATH 1 Oracle-driven](05_02_Proof_of_Growth_Pipeline#усі-шляхи-до-walletlock_and_mint-guard-inventory-doc7).
>
> ⊕ **Друга, НЕЗАЛЕЖНА підстава того самого присуду — крос-модульний прохід** [ARCH.59, 2026-08-21]. `Mrv::LineageReportService` гілки «джерельні рядки застаріли» не має ВЗАГАЛІ — і після [`ARCH.70`](00_07_Action_Plan_Tracker) ⚖️ 2026-08-29 рядкове видалення дасть `subroot_diverged`, тобто чесний НАСЛІДОК без причини. ⚠️ **Ця підстава ослабла, і сила її формулювання переміряна:** редакція 08-21 казала «чужий діагноз на нашу власну ретеншн-дію» (аудитор чув би «дерево змінило кластер») — після розчеплення статусів це вже неправда. Чинна, слабша форма: тракт не відрізняє нашу ретеншн-дію від підміни payload'а, тож другий механізм зникнення рядків лишається забороненим — але з іншої причини, ніж записувалось. А пін архівного батча їде чергою `low`(9/9 strict), тож семиденний DELETE встигав би випередити його, і `archiveRoot`, уже записаний on-chain, лишався б без відновлюваного офчейн-свідка. ⊕ **Чесний негатив, вартий рядка:** грошей це не чіпало — сума мінту рахується в ingest-час, а lineage-перерахунки на шляху dispatch явно fail-open.

> ⚡ **PARTITION PRUNING INVARIANT [S6.16]:** `telemetry_logs` — RANGE-партиціонована по `created_at` (місячні партиції). PostgreSQL застосовує partition pruning **тільки** коли `WHERE` містить literal/parameter на `created_at`. Без цього → Global Partition Scan (`O(P × log N)`) — на масштабі мільярдів рядків це секунди замість мілісекунд.
>
> **Інваріант:** усі читачі `TelemetryLog` за PK повинні передавати `created_at_iso` (ISO 8601) разом з `id`. Sidekiq workers, що ставлять у чергу follow-up jobs, **зобов'язані** передавати `log.created_at.iso8601(6)` як аргумент.
>
> 🔴 **Родина — ТРИ моделі, а інструмент у них РІЗНИЙ; не вгадуй метод.** `PartitionMaintenanceWorker::PARTITIONED_TABLES` = `telemetry_logs` · `gateway_telemetry_logs` · `blockchain_transactions`. One-Home:
>
> | Модель | One-Home | Форма |
> |--------|----------|-------|
> | `TelemetryLog` | `.partition_pruned(iso, metric_caller:)` | chainable scope |
> | `BlockchainTransaction` | `.find_with_partition_pruning(id, created_at, metric_caller:)` | фінідер ОДНОГО рядка |
> | `BlockchainTransaction` | `.where_ids_pruned(ids, span, metric_caller:)` | chainable, набір за ВІДОМИМИ id |
> | `GatewayTelemetryLog` | немає — і це свідомо | у нього немає жодного id-звертання, тож хелпер був би важелем без пускача |
>
> ⚠️ **Чому set-форма з'явилась окремо (PERF.1, 2026-08-07):** доти інваріант вимагав «делегуйте, не дублюйте», маючи для `BlockchainTransaction` лише фінідер ОДНОГО рядка — а мінт-тракт за побудовою працює батчами. Тобто кожен batch-сайт мусив писати `where(id: …)` руками не з недбалості, а тому що делегувати не було куди; форму винайшли рукою тричі незалежно. Правило, що оголошує обов'язок без інструмента для більшості своїх випадків, відтворює власне порушення.
>
> ⛔ **`status`-скан — НЕ цей клас, і межа там ШКІДЛИВА** (ратифіковано ARCH.52): `where(status: :pending)` без `created_at` коректний, бо reset-to-pending тримає СТАРИЙ `created_at`, і нижня межа осиротила б застряглі кошти. Важіль для скану — partial index `(status, created_at) WHERE status IN (0,1)`, він уже стоїть. Правило коротко: **`created_at`-вікно прунить звертання за ВІДОМИМ рядком (id/tx_hash); множину невідомого розміру прунить індекс.**
>
> 🔒 **Носій інваріанта — `spec/quality/partition_key_discipline_spec.rb`** (mutation-verified у два плечі: незадекларований `.reload` і незапрунене id-звертання червонять поіменно). До нього правило трималось лише на пам'яті автора й було порушене щонайменше тричі. Стеля гейта чесно названа в його шапці — зокрема він НЕ бачить preload асоціацій і НЕ читає прози.
>
> **Інвентар читачів:**
>
> | Читач | Файл | Шлях pruning | Source `created_at` |
> |-------|------|--------------|---------------------|
> | `IotexVerificationWorker` | `app/workers/iotex_verification_worker.rb` | ✅ через `ApplicationWeb3Worker#find_telemetry_log_with_pruning` | sidekiq arg `created_at_iso` |
> | `ChainlinkDispatchWorker` | `app/workers/chainlink_dispatch_worker.rb` | ✅ через `ApplicationWeb3Worker#find_telemetry_log_with_pruning` | sidekiq arg `created_at_iso` |
> | `MintCarbonCoinWorker#find_telemetry_log` | `app/workers/mint_carbon_coin_worker.rb` | ✅ через `ApplicationWeb3Worker#find_telemetry_log_with_pruning` | sidekiq arg |
> | `SolanaMicroRewardWorker` | `app/workers/solana_micro_reward_worker.rb` | ✅ через `ApplicationWeb3Worker#find_telemetry_log_with_pruning` | sidekiq arg |
> | `Api::V1::OracleCallbacksController#find_telemetry_log` | `app/controllers/api/v1/oracle_callbacks_controller.rb` | ⚠️ pruning якщо `params[:created_at]` присутній; інакше degraded scan | Chainlink DON callback param |
> | `MintingRollbackService#find_telemetry_log` | `app/services/minting_rollback_service.rb` | ⚠️ pruning якщо `@created_at_iso` присутній; інакше degraded scan | admin tool / cold path |
> | `DailyAggregationWorker` | `app/workers/daily_aggregation_worker.rb` | ✅ `created_at: day_range` — 1-2 партиції | scheduled cron |
>
> **Observability (degraded path detector):** Counter `silkennet_telemetry_log_unpruned_lookups_total{caller}` інкрементується у трьох точках, де `created_at` може бути відсутнім або malformed:
> - `ApplicationWeb3Worker:missing_created_at_iso` / `:invalid_iso8601` — sidekiq worker не передав argument; **hot path → ALERT**.
> - `OracleCallbacksController:missing_created_at_iso` / `:invalid_iso8601` — Chainlink DON callback без `created_at` query param; **hot path → ALERT** (виправити Chainlink Functions JS source).
> - `MintingRollbackService:missing_created_at_iso` / `:invalid_iso8601` — admin manual rollback; **cold path, acceptable**, але трекати для прозорості.
>
> ⚠️ Суфікс `_iso` несе КОЖНА мітка blank-гілки — вона деривується одним рядком у `TelemetryLog.partition_pruned` (`"#{metric_caller}:missing_created_at_iso"`); тут доти стояла форма без нього, тобто точний PromQL по мітці нічого б не знайшов. Префіксний regex у прикладі нижче цим не зачеплений.
>
> 🔴 **Дзеркало на грошовій моделі з'явилось лише 2026-08-07** (PERF.1): `silkennet_blockchain_transaction_unpruned_lookups_total{caller}` — доти `BlockchainTransaction` деградувала так само, але **МОВЧКИ**, тобто рівно та подія, заради якої лічильник заводили, була невидима там, де скан коштує найдорожче. Мітки: `<caller>:missing_created_at` · `:invalid_created_at` · `:missing_span` · `undeclared:*`, коли викликач себе не назвав. Два викликачі годують її прямо з URL-параметра (`wallets#transaction_status`, `blockchain_transactions#show`), тож битий клієнтський рядок — реальний пускач, не лише забутий аргумент воркера.
>
> Grafana alert rule: **`sn-alert-telemetry-unpruned-lookups`** — живе правило в IaC (`deploy/grafana/alerts/silkennet-alerts.yaml`), не приклад у прозі [INF.26, 2026-08-26]. Money-двійник — `sn-alert-blockchain-tx-unpruned-lookups`.
>
> 🔴 **Три факти, мігровані сюди 2026-09-04 із [`06_08 §2.6`](06_08_Resilience_and_Failover_Policy) (DOC-T.98) — вони жили ПОЗА цим домом, тож читач інваріанту їх не бачив:**
>
> - **Форма вікна залежить від того, що ти шукаєш.** Known-row lookup за відомим `id`/`tx_hash` бере СИМЕТРИЧНЕ вікно довкола `created_at`; батчевий шлях (`batchMint` через `.where_ids_pruned`) бере **span**, тобто lower-bound від найстарішого відомого рядка. Плутати їх дорого в обидва боки: симетричне вікно на батчі губить хвіст, span на одиничному звертанні знімає прунинг майже повністю.
> - **`created_at_iso` прокидають НЕ всі enqueue-сайти `BlockchainConfirmationWorker` — шість із семи.** Сьомий, `PuroEarthPassportWorker`, стоїть на іншому тракті (біомас-паспорт), і його виняток свідомий. ⚠️ Число тут — не інвентар, а **застереження**: додаючи сайт, звіряй, чи він мітку несе, бо промах ТИХИЙ.
> - ⛔ **Свідомо НЕ прунимо (design, не борг):** slash `total_minted` sum (`BlockchainBurningService`) і anchor SFC-supply sum (`Ethereum::StateAnchorService`) є **all-time агрегатами** — вони семантично unprunable, бо питання звучить «скільки за ВЕСЬ час». Гейт на них був би хибним позитивом назавжди.

---

### `GatewayTelemetryLog` — Діагностика Королеви

**Призначення:** Власна телеметрія шлюзу (батарея, температура, сигнал). Партиціонована — але One-Home-хелпера **не має, і це свідомо**: жодного id-звертання до неї не існує, тож хелпер був би важелем без пускача (розкладка інструмента — блок [S6.16] вище; поява першого id-звертання і є привід його завести).

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
| `latest_per_gateway(uids)` | **[PERF.1 (а)]** «Останній пульс на КОЖЕН шлюз набору» — хеш `queen_uid → лог`, **LATERAL + `LIMIT 1`**. 🔴 **Форма ІНША, ніж у дзеркального `TelemetryLog.latest_per_tree`, попри дослівно те саме питання — і різницю дав вимір, не аналогія:** `DISTINCT ON` тут віддає `Unique` над ТИМ САМИМ `Sort` над `Append` по всіх партиціях, тобто скану не скорочує; його виграш там був у **кількості запитів** (N→1), а сторінка шлюзів уже робила один — преload `has_one`. LATERAL дає `Limit` → `Merge Append` → `Index Scan Backward` на індексі `(queen_uid, created_at)`, тобто **ранню зупинку**. ⚠️ Часової межі немає свідомо: питання звучить «останній, хоч би коли він був», тож будь-яке вікно змінило б ВІДПОВІДЬ (пастка `2.months`, [`00_07`](00_07_Action_Plan_Tracker) PERF.1). ⊥ Асоціація `Gateway#latest_gateway_telemetry_log` ЛИШАЄТЬСЯ для `gateways#show`: на ОДНОМУ шлюзі вона вже дістає той самий добрий план — дефект жив у кардинальності **списку**, не в асоціації |
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
| `target_pest` | string | ⚠️ **Колонка без ЖОДНОГО читача, і її семантика класифікатору недоступна** [ARCH.102]: акустична модель має рівно пʼять класів (`silence`/`wind`/`cavitation`/`chainsaw`/`fauna` — [`03_03`](03_03_TinyML_Acoustic_Inference)), серед них НЕМАЄ жодного виду шкідника, тож «модель, налаштована на короїда» не існує ні на дроті, ні в тренері. Сід більше її не заповнює (доти демо роздавало соснам `v1.0.4-bark-beetle`). Оголошено, а не знято: прецедент `sap_flow` ↑ — нуль викликачів у передпродовому репо вимірює недобудованість, не смерть; умова оживлення — окремий вимірювач, а не мітка |
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

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `endpoint` | string | Шлях CoAP на конкретній Королеві (unique у скоупі `gateway_id`) |
| `max_active_duration_s` | integer | Safety envelope: фізична стеля безперервної роботи; валідує `duration_seconds` команди |
| `last_activated_at` | datetime | Мітка останнього `activate` (пише `before`-хук події) |
| `estimated_mj_per_action` | decimal | Орієнтовна витрата енергії за активацію (мДж) |

**Методи:** `ready_for_deployment?`, `mark_active!`, `mark_idle!`, `require_maintenance!(reason)`.

---

### `ActuatorCommand` — Команда Актуатору

**Включає:** `AASM`, `Auditable` ([ARCH.57] `after_update_commit if: :saved_change_to_status?` → `actuator_to_*` chain-only; bulk-обходи закриті ручними викликами — `actuator_bulk_cancelled` на override-`update_all` + pre-dispatch failures `ttl_expired`/`actuator_not_ready` на `update_columns`)

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
| `command_payload` | text | Скалярна команда `ACTION` або `ACTION:value` (`ALLOWED_PAYLOAD_FORMAT`) — **НЕ** jsonb: дротова форма `CMD:<payload>:<duration>:<actuator_id>:<token>` ([`03_02 §6`](03_02_Queen_Gateway_Firmware)) тримається на скалярності, а двокрапка всередині payload зсуває вікно дедупу Королеви |
| `idempotency_token` | uuid | Захист від дублів; Королева дедуплікує за ним ([`03_02 §6`](03_02_Queen_Gateway_Firmware)) |
| `duration_seconds` | integer | Тривалість дії (safety envelope, ≤ `actuator.max_active_duration_s`) |
| `sent_at` | datetime | Мітка `dispatch` — момент видачі в downlink |
| `executed_at` | datetime | Мітка `acknowledge` — момент, з якого дія вважається початою (колонка UI «Started») |
| `completed_at` | datetime | Мітка `confirm` — закриття наказу |
| `expires_at` | datetime | Термін придатності (TTL); команда від контролера його НЕ отримує |
| `priority` | enum | Рівень пріоритету |

**Методи:** `estimated_completion_at`, `expired?`, `dispatch_to_edge!`, `cancel_pending_for_actuator!`.

---

## 👤 5. Люди та Організації

### `Organization` — Власник Лісових Активів

**Включає:** `EthAddressValidatable` · `Auditable` (ротація епохи стрімів = привілейована дія, [ARCH.57])

**Асоціації:**

| Зв'язок | Тип | Опис |
|---------|-----|------|
| `users` | `has_many, restrict_with_error` | Захист аудит-логів |
| `naas_contracts` | `has_many, restrict_with_error` | Фінансова цілісність |
| `clusters` | `has_many, dependent: :destroy` | Лісові масиви |
| `trees` | `has_many, through: :clusters` | Всі дерева |
| `wallets` | `has_many, dependent: :nullify` | Пряма магістраль (без 4-рівневого JOIN); `organization_id` обнуляється при видаленні Organization |
| `ews_alerts` | `has_many, through: :clusters` | Тривоги всіх кластерів (через `under_threat?`) |
| `audit_logs` | `has_many, dependent: :restrict_with_error` | Незмінний аудит — журнал переживає Org [ARCH.57] |
| `logo` | `has_one_attached` | Active Storage — **≤ 5 МБ, JPEG/PNG/WebP** [SEC.27]. Єдине вкладення дерева з живим upload-шляхом (`settings_controller` кладе `:logo` у `permit`), тож валідація тут межа довіри, не гігієна. SVG свідомо поза allow-list: Rails віддає його `attachment`, а не inline (`content_types_to_serve_as_binary`), але список тримається растровим — логотип іде через `url_for` без variant'а |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `name` | string | Унікальна назва |
| `billing_email` | string | Нормалізований (lowercase) |
| `crypto_public_address` | string | Ethereum/Polygon-адреса (EIP-55, strip without downcase) |
| `hadron_kyc_status` | string | [KYC.1] KYC бенефіціара custodial-мінту (default `pending`; успадковується гаманцями без власної адреси через `Wallet#kyc_approved_for_minting?`); біндинг/зміна адреси → reset у `pending` + enqueue `HadronKycVerificationWorker` |
| `data_region` | string | `eu-west / eu-central / us-east / us-west / ap-southeast` (GDPR sharding) |
| `alert_threshold_critical_z` | decimal | Поріг Z для власних тривог (0..10) |
| `ai_sensitivity` | decimal | Чутливість AI (0..1) |
| `locale` | string | [I18N.1] Мова, якою організація отримує **пошту** (`AlertMailer` → `billing_email`). Не дубль `users.locale`: за цією скринькою може не стояти жоден User. `nil` = «не обрано» → базова локаль; валідація деривує перелік з `available_locales` ([`04_04 §12.8`](04_04_Phlex_UI_and_Tailwind)) |
| `stream_epoch` | integer | [SEC.25 Ф3] Покоління імен Turbo-стрімів (`..._org_{id}_e{epoch}`), default 1, NOT NULL. Єдиний механізм відкликання виданого capability-токена: підпис детермінований і без TTL, тож знецінити збережене імʼя можна лише **покинувши адресу**. Важіль — `#rotate_stream_epoch!` (bump → tombstone у стару адресу → слід ARCH.57); стелі й чому `:map` не гаситься — [`04_04 §8.1`](04_04_Phlex_UI_and_Tailwind) |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `total_carbon_points` | `wallets.sum(:balance)` — прямий SELECT |
| `health_coverage` | [ARCH.84] One-Home `Cluster.health_coverage(clusters)` — середнє **разом із покриттям** |
| `health_score` | Тонка подача над ним: `average&.round(2)`, **nullable**. ⚠️ Доти цей метод мав ДВА взаємовиключні дефолти на дві форми «нічого» — `1.0` на порожню організацію й `0.0` на всі-NULL кластери, тобто вигадані числа, призначені задом наперед |
| `total_clusters` | `clusters.size` — **не `.count`**, див. нижче |
| `total_contracted` | `naas_contracts.sum { … .to_f }` — блокова форма, **не `sum(:колонка)`**, див. нижче |
| `cached_trees_count` | 1 год кеш `organization_#{id}_trees_count` |
| `under_threat?` | `ews_alerts.unresolved.critical.exists?` |
| `rotate_stream_epoch!` | [SEC.25 Ф3] Відкликати всі видані імена стрімів організації: bump `stream_epoch` → tombstone у покинуту адресу → слід ARCH.57. Ручний ops-важіль (рецепт — [`06_08 §4.7`](06_08_Resilience_and_Failover_Policy)); автотригера немає свідомо, бо членство в цьому дереві незмінне |
| `broadcast_stream_tombstone!(epoch)` | Повторно штовхнути минулу епоху на перезавантаження — **штатна** дія, не crash-recovery: tombstone доїжджає лише до підключених у ту мить сокетів ([`04_04 §8.1`](04_04_Phlex_UI_and_Tailwind)) |

🔴 **Форма агрегату тут не стиль, а вибір між двома різними правильними відповідями — і критерій ОДИН: чи метод кличуть у ЦИКЛІ.** `.count` і `sum(:колонка)` шлють SQL **завжди**, навіть коли асоціація вже завантажена через `includes` — тобто в колекційному рендері дбайливий preload поруч із ними лише додає запит, і виглядає це як турбота. Саме так `Organizations::Index` тримав два SQL-агрегати на РЯДОК ([`00_07`](00_07_Action_Plan_Tracker) N+1-пункт): `total_clusters`/`total_contracted` рендеряться з `OrganizationBlueprint view: :index` у циклі, тому переведені на `.size` і блокову `sum`, які беруть завантажений масив. ⚠️ **Сусіди в таблиці навмисно НЕ переведені, і «уніфікувати» їх — регресія:** `total_carbon_points`, `health_score` кличуть лише в однозаписових контекстах (`reports_controller`, `reports/index`), де SQL-агрегат дешевший за завантаження всіх рядків. Тож перед зміною форми питай не «яка гарніша», а **де цей метод стоїть — у рядку списку чи на сторінці одного запису**. 🔴 І знай, чому дефект прожив: спека реєстру мала у фікстурі рівно ОДНУ організацію, а клас «на рядок» потребує N≥2, тож Prosopite не міг спрацювати за побудовою ([`04_06 §B.2`](04_06_Testing_Guide_and_Coverage) BP 21).

---

### `User` — Суб'єкт Системи

**Включає:** `HasArgon2Password`, `Auditable` ([ARCH.57] `after_update_commit if: :saved_change_to_role?` → `user_role_changed` chain-only — model-layer ловить і console-шлях, role-контролера не існує)

**Ролі (RBAC):**

| Роль | Рівень доступу | Опис |
|------|---------------|------|
| `subscriber(0)` | `:read_only` | Лише власні ресурси |
| `forester(1)` | `:field` | Польовий доступ в межах org |
| `admin(2)` | `:organization` | Повний доступ в межах org |
| `super_admin(3)` | `:system` | Повний доступ до платформи |

**Токени (Rails 8 `generates_token_for`):**

| Токен | TTL | Прив'язка до |
|-------|-----|-------------|
| `password_reset` | 15 хв | `password_salt.last(10)` |
| `email_verification` | 24 год | `email_address` |
| `api_access` | 30 днів | `password_salt.last(10)` (згорає при зміні пароля) |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `email_address` | string | Нормалізований (lowercase + strip) |
| `password_digest` | string | Argon2id хеш |
| `role` | enum | subscriber/forester/admin/super_admin |
| `first_name` / `last_name` | string | ПІБ — PII. **[SEC.18]** Обидва (+ `recovery_codes`) скрабляться з логів через `filter_parameters` (`config/initializers/filter_parameter_logging.rb`; Sentry реюзить той самий список); schema-parity гейт `spec/initializers/filter_parameter_logging_spec.rb` — кожна нова string/text-колонка `users`/`organizations` мусить бути класифікована: filtered-PII або явний allow-list |
| `otp_required_for_login` | boolean | ✅ **[S6.21] МЕХАНІЗМ з 2026-08-20:** шлях входу ЧИТАЄ прапорець — `sessions#create` на `mfa_enabled?` кладе pending-мітку (TTL 5 хв) і шле на `/login/mfa` (`MfaChallengesController`), сесія не існує до TOTP/recovery. Піднімається ЛИШЕ setup-флоу (`MfaSetupsController`: провижн → QR → verify свіжого коду + rotation recovery-набору); toggle-enable шле туди (409 `mfa_setup_required`), disable тримає step-up. Наскрізний носій — `spec/requests/api/v1/mfa_flow_spec.rb` (анти-replay · одноразовість recovery · TTL) |
| `otp_secret` | string | **[S6.21]** TOTP-секрет (RFC 6238) — AR-encrypted (прецедент `hardware_keys`, SEC.22); ротується кожним стартом setup-флоу до активації |
| `otp_last_used_at` | datetime | **[S6.21]** Мітка останнього успішного TOTP — ROTP `after:` відкидає replay того самого коду всередині 30-с вікна |
| `recovery_codes` | text | JSON масив 10 одноразових кодів |
| `telegram_chat_id` | string | Для Telegram сповіщень — формат Bot API (`/\A-?\d{1,20}\z/`, strip-нормалізація): сміттєвий chat_id коштував би RequestError × 5 Sidekiq-ретраїв на кожну тривогу. `phone_number` знято разом зі SMS-каналом (⚖️ ARCH.78 2026-08-20: email покриває сценарій — телефон був PII без цілі processing) |
| `locale` | string | [I18N.1/I18N.3] Persisted мовна вподоба — джерело для ОБОХ контурів: **веб** (третій щабель резолву, [`04_04 §12.4`](04_04_Phlex_UI_and_Tailwind) — те, що переживає зміну пристрою й чистку cookie) та **пошта** (Sidekiq, куди cookie не доїжджає). ⚠️ Рядок доти казав «для НЕ-веб-контекстів», і то було не описом, а МЕЖЕЮ: колонку читала сама лише пошта, тож людина з обраною мовою бачила англійський сайт і діставала лист своєю. Пишеться при явному виборі в перемикачі (`LocalesController`, guard дзеркалить [SEC.16]); `nil` = «не обрано» → наступний щабель |
| `last_seen_at` | datetime | Оновлюється через Session |

**Системний бот:** `User.oracle_executioner` — `oracle.executioner@system.silkennet.com` (super_admin без org). Використовується для автоматичних операцій системи.

**Ключові методи:** `access_level`, `forest_commander?`, `full_name`, `touch_visit!`, `mfa_enabled?`, `consume_recovery_code!`, `generate_recovery_codes!`.

---

### `Session` — Нативний Токен Rails 8

**Асоціації:** `belongs_to :user`

**Ключові поля:** `ip_address`, `user_agent`, `updated_at` (оновлюється `after_touch`).

**Методи:** `mobile_app?` (regex `SilkenNetMobile` — ⚠️ **заготовка без контракту**: нуль прод-викликачів, а UA-рядок мусить збігтися з оболонкою, форма якої ще не обрана — [`00_07`](00_07_Action_Plan_Tracker) UI.18), `touch_activity!`.

**Scopes:** `stale` (> 30 днів), `active_in_field` (foresters за 24 год).

---

### `Current` — Контекст Виконавця Запиту [SEC.25 Ф2]

**Не AR-модель** — `ActiveSupport::CurrentAttributes` (живе в `app/models/`, звідси й місце
в цьому реєстрі). Per-request, скидається Rails-екзекутором між запитами; поза HTTP
(Sidekiq) не виставляється взагалі.

| Атрибут | Опис |
|---------|------|
| `acting_organization_id` | Організація, в контексті якої виконується запит |
| `home_organization_id` | Власна організація виконавця (колонка `users.organization_id`) |

**Ключовий метод:** `switched_context?` — істина, коли super_admin працює в чужій
організації. Єдиний споживач — `Auditable#record_audit_trail!`, який за цією ознакою
дописує в `metadata` мітку `acting_organization_id` + `actor_home_organization_id`.
Без неї організація бачила б наслідок привілейованої дії (OTA-деплой, команда
актуатору, зміна налаштувань) без сліду, що виконавець прийшов ззовні — сам факт
перемикання лежить окремим записом, і зшивати їх довелося б руками по часу.

🔴 **Чого сюди класти НЕ можна — і це головне про цей клас.** Тут немає й не повинно
бути організації як **джерела скоупу**. Скоуп даних живе в
`Api::V1::BaseController#acting_organization` і доїжджає до Pundit явним `UserContext`,
тобто передається аргументом. Амбієнтна організація була б доступна і в моделі, і в
воркері, і всередині `Turbo::StreamsChannel.broadcast_*` — а там діє ПРОТИЛЕЖНЕ
правило: броадкаст іде в організацію **власника ресурсу** (`cluster.organization_id`),
не глядача. Один `Current.organization` у продюсері — і оновлення чужої організації
поїхали б у стрім того, хто щойно перемкнув контекст. Тому тут лише id, лише для сліду.

---

## 💰 6. Економічний Рівень

### `Wallet` — Вуглецевий Гаманець

**Включає:** `EthAddressValidatable`

**Асоціації:**
- `belongs_to :tree`
- `belongs_to :organization` (optional, денормалізований FK) — **[ARCH.87] інваріант: колонка НІКОЛИ не розходиться з ланцюгом `tree → cluster → organization`, і це структурно, а не декларативно.** Письменник рівно один (`Tree#build_default_wallet` → `cluster&.organization` при народженні дерева), бекфілу немає й не потрібно: єдине, що могло б колонку інвалідувати — переїзд дерева в інший кластер, а такої операції **не існує й не може існувати** (`clusters.id` = фабрично заморожена координата, HKDF-salt для `K_ota`/`KEYB` у кремнії; ⚖️ 2026-07-30 → канон робить «переїзд» парою decommission + factory-provision нового DID). Виміряно на живому наборі: нуль розбіжностей. ⚠️ Порожня колонка = ВІДСУТНІСТЬ, не конфлікт: `Tree belongs_to :cluster, optional: true` свідомо лишає захисний стан «дерево без кластера», і саме тому `WalletPolicy::Scope` приймає ОБИДВІ гілки, дзеркалячи `show?` — інакше такий гаманець зникає зі списку й із суми ліквідності, лишаючись відкритим за прямою адресою. Носій інваріанта — `spec/quality/wallet_org_denormalization_spec.rb` (стеля названа в шапці: детектор ключується на ІМЕНІ отримувача й не бачить присвоєння через довільно названу локальну змінну).
- `has_many :blockchain_transactions, dependent: :nullify` — **[ARCH.57]** дозволений destroy (порожній/чисто-pending гаманець) лишає tx-ряди сиротами, не стирає (сирітський ряд валідний за дизайном — cluster-sourced money вже живе без wallet); первинний захист доказів = `guard_mrv_evidence!`
- `has_one :cluster, through: :tree`

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `balance` | decimal | Основний баланс growth_points (≥ 0) |
| `locked_balance` | decimal | Заморожені points (в процесі емісії). **Подвійне призначення:** (1) lock під час `lock_and_mint!` між Polygon-mint dispatch і `confirmed` AASM; (2) **finality-lag lock** — коли SCC вже мінтовано на Polygon, але тижневий L1 anchor (`EthereumAnchor`, крок #12) ще не зафіксував state root. У випадку Polygon reorg або catastrophic sidechain failure до anchor — токени технічно повертаються у `locked_balance` через `escalate_to_review`. Це запобігає double-spend сценарію, описаному в [`06_08 §2.2 Manual review terminal state`](06_08_Resilience_and_Failover_Policy). |
| `esg_retired_balance` | decimal | **МОНЕТИ SCC**, необоротно погашені через KlimaDAO ([ARCH.95] ⚖️ 2026-08-25 — одиниця тут НЕ бали: клієнт погашає, щоб довести tCO₂, а міст до tCO₂ (`2000 SCC = 1 tCO₂`, [`00_04`](00_04_Nature_as_a_Service_Contracts)) приймає лише монети). Єдиний писач — `KlimaDao::RetirementService`; форматується `formatted_amount` (ARCH.89), не `formatted_points` |
| `crypto_public_address` | string | Polygon/Ethereum-адреса гаманця (EIP-55) |
| `solana_public_address` | string | Solana Base58-адреса (для мікро-нагород) |
| `hadron_kyc_status` | string | KYC статус Polygon Hadron (default: `pending`); [KYC.1] зміна `crypto_public_address` скидає у `pending` + enqueue `HadronKycVerificationWorker` (KYC чіпляється до адреси) |
| `lineage_cursor_at` / `lineage_cursor_log_id` | timestamp / bigint | **[MRV.1]** watermark-курсор lineage: позиція останнього TelemetryLog, спожитого mint-вікном (`lock_and_mint!` рухає монотонно — clock-regression clamp: верхня межа ≤ курсора → порожнє вікно, курсор стоїть — і лише разом зі створенням tx). NULL = мінтів ще не було → перше вікно чесно атрибутує всю історію дерева. Ціна: mint-лок тепер несе 1 indexed telemetry-SELECT (pick позиції) |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `available_balance` | `balance - locked_balance` |
| `lock_funds!(amount)` | **Резервує** `amount` у `locked_balance`; `balance` НЕ змінюється (reserve-, не move-семантика — див. нижче) |
| `release_locked_funds!(amount)` | Знімає резерв із `locked_balance`; `balance` НЕ змінюється. Кличеться лише на ПРОВАЛЬНОМУ шляху (`fail`-подія tx + rollback-сервіс) — успішний мінт резерв не звільняє [E.66] |
| `credit!(points)` | Зараховує РІВНО те, що дали: `with_lock { increment!(:balance, points) }` — жодного множника всередині. 🔴 **Дім зважування — ВИКЛИКАЧ, не метод** [ARCH.115]: `carbon_sequestration_coefficient` накладає `TelemetryUnpackerService` (`tree.tree_family&.weighted_growth_points(points)`), і сьогодні він **єдиний** продакшн-викликач. ⚠️ Доти цей рядок казав «зараховує з урахуванням `carbon_sequestration_coefficient` породи» — тобто приписував методу чужу відповідальність, і ціна не редакційна: **другий писач балів** (Guild-виплата · backfill · ручна компенсація), що повірить картці й передасть сирі бали, дасть дубу −33% і сосні +25% — а звідти `lock_and_mint!` помножить помилку в незворотний мінт |
| `lock_and_mint!(points_to_lock, threshold, token_type)` | Повний цикл емісії SCC (курс — [`05_03`](05_03_Tokenomics_SCC_and_SFC)) |
| `kyc_approved_for_minting?` | [KYC.1] Гейт мінтингу = статус БЕНЕФІЦІАРА адреси: власна адреса → власний статус; custodial (без власної) → успадковує `organizations.hadron_kyc_status` (гейт — [`05_02` — Крок E](05_02_Proof_of_Growth_Pipeline)) |
| `broadcast_balance_update` | Turbo Stream оновлення UI |
| `guard_mrv_evidence!` | **[MRV.1]** `before_destroy` (prepend) destroy-guard MRV-доказів: гаманець із settled/in-flight `blockchain_transactions` → abort (грошові докази незнищенні); чисто-pending видаляється. **[E.60]** + tx з `archive_batch_id` (будь-який статус, включно pending/failed) → abort: стемпнутий tx = член архів-батчу, видалення стерло б вікна → хибний `mismatch` у pin-воркера. **Межа (fable №2, звужена E.60):** лише failed-tx БЕЗ архів-членства не блокують destroy |

> 🔴 **Семантика трьох величин — RESERVE, не MOVE (дім визначення; [ARCH.94] 2026-08-12).** `balance` — **gross**-лічильник: усе, що дерево заробило за життя; він НЕ спадає при мінті. `lock_and_mint!` лише інкрементить `locked_balance`, тобто позначає бали як сконвертовані, а `available_balance = balance − locked_balance` — те, що ще можна сконвертувати. **Move-семантика («`balance -= points`») тут структурно НЕМОЖЛИВА:** DB-констрейнт `wallets_balance_invariants` вимагає `locked_balance <= balance`, тож списання `balance` при зростанні `locked` падає `PG::CheckViolation`. ⚠️ **Практичний наслідок, куплений живим дефектом:** будь-який споживач, що вирішує «скільки можна змінтувати», мусить читати **`available_balance`**, ніколи `balance` — інакше з другого циклу він просить більше, ніж доступно. Так упав `EvaluateTreeBatchWorker` (сайзинг від gross) разом із селектором `TokenomicsEvaluatorWorker`, і так само раніше падав ESG-retire, виправлений під [ARCH.56]. 🔴 **І дзеркальний бік того самого визначення: `lock_and_mint!` блокує рівно СКОНВЕРТОВАНЕ (`tokens_to_mint × threshold`), а не запитане.** Некратний вхід (25 000 при порозі 10 000 → 2 монети) доти лишав 5 000 у `locked_balance` під нуль монет — і **назавжди**, бо locked за цією ж семантикою не звільняється взагалі. Клампінг тут не ховає помилку викликача, а виконує визначення колонки: блокувати більше, ніж сконвертовано, означало б, що `locked_balance` бреше про власний зміст. Розбіжність логується WARN'ом (живий викликач завжди передає кратне — гілка озброїлась би першим новим). ✅ **Винятків із цього визначення БІЛЬШЕ НЕМА** ([ARCH.95] ⚖️ 2026-08-25). Доти єдиним був `KlimaDao::RetirementService` із `decrement!(:balance, …)`, і ціна була не локальна: перше поле тижневого L1-якоря = `Wallet.sum(:balance)` ([`05_04 §3`](05_04_Ethereum_L1_State_Anchor)), тож ESG-погашення переписувало б офчейн-леджер балів заднім числом. Присуд зняв не симптом, а причину: погашення рухає ЛИШЕ `esg_retired_balance` (лічильник МОНЕТ), а всі три балові величини лишаються недоторканими. 🔴 **Записану в трекері альтернативу — `available_balance = balance − locked_balance − esg_retired_balance` — відкинуто, бо вона сама несла дефект одиниці:** щоб мати SCC, гаманець їх намінтив, а мінт уже наклав ті бали в `locked_balance` назавжди, тож віднімати їх удруге є ПОДВІЙНИМ списанням. ⚠️ Дзеркальний наслідок для будь-якого майбутнього споживача: «скільки монет має гаманець» **не виводиться з балансових колонок узагалі** — це `blockchain_transactions.net_minted_supply`, і `available_balance` на це питання не відповідає (він про протилежний бік конвертації). ⊕ **Конверсію «бали → монети» рахують ДВІ арифметики, і це свідомо** (названо 2026-08-26, DOC-T.89): `EvaluateTreeBatchWorker` ділить BigDecimal, `Wallet#lock_and_mint!` — Float. Вони тотожні, доки тримаються ТРИ незалежні примуси: integer-typed `emission_threshold` (стереже гейт GOV.3), добуток `n·threshold < 2⁵³` (на 4 порядки вище `MAX_SUPPLY`), і невідʼємний `available_balance` (CHECK `wallets_balance_invariants` — інакше `.to_i` і `.floor` розійшлися б на відʼємних). ⚠️ **Перший, хто зробить поріг дробовим, зламає НЕ арифметику, а колонку `locked_points bigint`**: `converted_points` округлиться мовчки, а залишок осяде в `locked_balance` назавжди — той самий клас, що [ARCH.94]. ⛔ Не «уніфікувати» типи: прецедент FW.7 зійшов BigDecimal→Float СВІДОМО, бо тип обирає непорушний бік; тут непорушного боку немає, тож уніфікація нічого не ловить.
>
> **[E.66] Toucan-prune:** `lock_for_toucan_bridge!` / `finalize_spend!` / `toucan_bridged_balance` видалено (flow DEAD, 0 enqueue-callerів; failure-path мав money-integrity діру — несиметричний rollback). Escrow-примітив воскресає з git при E.20-go (locked у mint-flow = «сконвертовано назавжди» by design — finalize не потрібен).

---

### `BlockchainTransaction` — Незмінний Лог Web3

**Включає:** `AASM`, `EthAddressValidatable`

**Асоціації:**
- `belongs_to :wallet` (optional)
- `belongs_to :cluster` (optional)
- `belongs_to :sourceable, polymorphic: true` (optional) — NaasContract, ParametricInsurance

> ⚡ **Власник — ДЕРИВАЦІЯ, і дім її один: `#organization`** [UI.4, 2026-08-18]. Три ланки, у порядку: денормалізований ярлик гаманця (`wallets.organization_id` — nullable, **без бекфілу**: пишеться лише при народженні дерева) → ланцюг дерево→кластер → власний `cluster` рядка. **Це рівно та пара координат, якою резолвить `for_organization`**, і збіг тут несучий: розходження означало б, що рядок, ВИДИМИЙ в аудит-списку організації, адресується в чужий стрім або нікуди. 🔴 Тут доти стояв `delegate :organization, to: :wallet, allow_nil: true` з коментарем «може бути nil для slashing-аудиту — тоді через cluster» — **фолбеку через cluster делегат не мав**, тобто cluster-sourced рядок віддавав `nil` мовчки; не помічалось, бо викликачів у делегата не було жодного, отже обіцянку ніколи не перевіряла реальність. ⚠️ Вужча форма `wallet&.organization_id || cluster&.organization_id` (вона живе в `record_money_audit_trail` і там доречна) читає ЛИШЕ колонку — для адресації стріму вона завузька.

**Enums:**

| Enum | Значення |
|------|----------|
| `token_type` | `carbon_coin(0) / forest_coin(1) / cusd(2)` |
| `status` | `pending(0) / processing(1) / confirmed(2) / failed(3) / sent(4) / manual_review(5)` |

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `amount` | decimal | Сума (> 0) **у МОНЕТАХ токена**, не в балах: mint пише сюди `tokens_to_mint = (points_to_lock / threshold).floor` (`Wallet#lock_and_mint!`), тобто вже сконвертоване. Парний `locked_points` тримає БАЛИ тієї самої операції — дві колонки одного рядка навмисно в різних одиницях, і плутанина між ними коштує 10 000× ([`05_03`](05_03_Tokenomics_SCC_and_SFC) — дім курсу) |
| `direction` | string | **[ARCH.95]** Напрямок руху: `mint` (емісія) / `burn` (вилучення з обігу). `NOT NULL`, default `mint`. 🔴 Дискримінатор ОДИН для всіх агрегатів (`net_minted_supply`, `net_minted_by_cluster`, `#burn?`) — доти напрямок ДЕРИВУВАВСЯ з `sourceable_type = NaasContract`, і [ARCH.101] цю деривацію ратифікував на передумові «єдиний slash-шлях», яку ESG-погашення зняло. ⛔ Знак `amount` напрямку НЕ несе: slash пишеться ДОДАТНИМ. Причин `burn` дві — slash (несе `sourceable`) і ESG-погашення (не несе); інваріант `slash_intent_must_be_a_burn` не дає першій поїхати мінтом ⊕ **Носій форми — `spec/quality/money_direction_home_spec.rb`** [DOC-T.89]: поведінку тримали піни (валідація вище + ретайрмент-спека), а повернення самої ЗАБОРОНЕНОЇ ФОРМИ не стерегло ніщо. Виняток для дому свідомо вужчий за файл — burn-маркер лишається легальним у валідації й заборонений усередині агрегату |
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
| `telemetry_window_from_at/from_id` · `telemetry_window_to_at/to_id` | timestamp/bigint | **[MRV.1]** lineage-вікно вимірів mint-інтенту (від watermark-курсора Wallet до нового; пишеться в `lock_and_mint!` під wallet-локом). NULL = pre-lineage tx або non-mint |
| `telemetry_merkle_root` | string(64) | **[MRV.1/ARCH.12]** Merkle-корінь вікна (leaf = `Mrv::TelemetryLeaf`); **fail-open** — nil легітимний (witness-фіча ніколи не блокує мінт). AuditLog-печатка = стан кореня НА МОМЕНТ status-переходу (attach йде post-commit — перший перехід теоретично може запечатати nil; bundle показує стан tx-рядка) |
| `archive_batch_id` | bigint | **[E.60]** set-once membership архів-батчу (`belongs_to :archive_batch`, FK + btree): ставиться РАЗ атомарно зі створенням батчу (`Mrv::TelemetryArchiveBatchService`), re-dispatch реюзає stored root; НІКОЛИ не перевішується. Non-NULL = MRV-доказ → `Wallet#guard_mrv_evidence!` abort'ить destroy |
| `telemetry_lineage_version` | integer | Версія leaf-формули (`Mrv::TelemetryLeaf::LEAF_VERSION`) — historical-верифікація при майбутньому bump'і |

**AASM:**
- `process` (pending→processing)
- `mark_as_sent(tx_hash)` (pending/processing→sent)
- `confirm(block_num, gas_cost)` (sent/processing/**manual_review**→confirmed)
- `fail(reason)` (any→failed, вкл. **manual_review**)
  - 🔴 **[ARCH.115, 2026-08-29] `manual_review` доти був станом БЕЗ ВИХОДУ, і ціна цього не реєстрова.** Подій із `from: :manual_review` було НУЛЬ, тож ескальований рядок лишався там назавжди; а `net_minted_supply` рахує лише `:confirmed`, отже монети, що **ймовірно існують on-chain**, дорівнювали нулю для L1-якоря ([`05_04 §3`](05_04_Ethereum_L1_State_Anchor)) і для бази розміру спалення ([`05_05 §3`](05_05_Slashing_and_Risk_Policy)) — НАЗАВЖДИ. Єдиним фактичним шляхом лишався сирий SQL повз валідації й аудит-хук, тобто саме те, що картка `EthereumAnchor` нижче називає забороненим. ⚠️ Канон при цьому описував вихід у СИБЛІНГА і мовчки приписував його тому, у кого його немає.
  - 🔑 **ДЕ стоїть гард — і це головне в цій формі.** Подія широка, а від авто-резолву захищає СПОЖИВАЧ: `BlockchainConfirmationWorker.confirmation_scope` виключає `:manual_review` (обидві гілки, включно з `rescue`-фолбеком), а обидва Solana-сайти (`Solana::MintingService#reconcile_event_in_flight`, `Solana::BatchPayoutService`) несуть явний `&& !tx.status_manual_review?`. Форма — дзеркало ратифікованого [ARCH.66] в `EthereumAnchor`. ⛔ **Не «спрощувати» жоден із трьох гардів назад до самого `may_confirm?`**: доти предикат був гардом ВИПАДКОВО (подія не приймала стан), і після цієї зміни він віддає `true` — тобто спрощення тихо вмикає авто-резолв, проти якого ескалація й існує (CLAUDE §6 «не авто-резолвити»). Виміряно на собі: Solana-сайти впали саме так, і спіймала їх сюїта, не ревʼю.
- `escalate_to_review(reason)` (pending/processing/sent/failed→manual_review) — **[DOUBLE-SPEND GUARD]**: tx_hash вже існує або стан на блокчейні невідомий; кошти залишаються у `locked_balance` до ручної звірки
- `after_update_commit :record_money_audit_trail, if: :saved_change_to_status?` — **[MRV.1/ARCH.57]** кожна зміна статусу (AASM І raw `update!`) пише SHA-256 `AuditLog`-ланцюг ПІСЛЯ commit (AASM `after_all_transitions` файрив ДО персистенції → phantom-рядок на rollback; event-ім'я зберігається з freshness-guard'ом, fallback = state-based `blockchain_tx_to_*`); actor=`oracle_executioner`, metadata from/to/tx_hash; org-резолюція `wallet&.organization_id || cluster&.organization_id` — cluster-sourced рухи (Celo reward, last-tree slash; `wallet=nil`) атрибутуються через кластер; без org/actor — WARN-skip, tx не валимо
- `scope :in_flight` (recent `:pending`/`:sent`) — **[ARCH.45]** intent-marker idempotency guard (дзеркало `EthereumAnchor.in_flight`): на retry ловить on-chain↔DB crash-window для slash / Solana payout проти double-pay / double-burn ([`04_02 §4/§10`](04_02_Business_Logic_and_Services))

**Методи:** `find_with_partition_pruning(id, created_at = nil)` _(клас)_, `net_minted_supply(token_type)` _(клас)_, `net_minted_by_cluster(cluster_ids, token_type)` _(клас)_, `burn?`, `signed_amount`, `explorer_url`, `solana_network?`, `celo_network?`, `broadcast_status_change`.

**Скоупи власності:** `.for_organization(org_id)` · `.for_cluster(cluster_id)` — обидва резолвлять ДВОМА гілками (гаманці ∪ прямий `cluster_id`), бо cluster-sourced рухи живуть із `wallet: nil` (Celo-reward, слеш останнього дерева). Одногілковий `joins(wallet: :tree)` їх не бачить — і саме ці рядки найбільші за сумою.

> 🔴 **[ARCH.98] Це ОБОВʼЯЗКОВИЙ вхід для будь-якого org-читача транзакцій, і ось чому правило сформульоване так різко.** `joins(wallet: …)` — це **INNER JOIN**, тож рядок із `wallet_id IS NULL` для нього не існує; виміряно рантаймом — стара форма бачила `0`, `for_organization` бачить `1` на тому самому наборі. Форма стояла в **пʼятьох** живих читачах одразу (фінзвіт · аудит-список · lookup за id · стрічка дашборда · MRV-lineage) і поширювалась КОПІЮВАННЯМ — коментар `Mrv::LineageReportService` прямо називав `ReportsController#financial_summary` своїм «прецедентом». Ціна різна: на екрані це неповний список, на `#find_transaction` — **404 за прямою адресою на власні гроші організації**, а в lineage — неповний ДОКАЗ на виданий кредит (ISO 14064/Verra). ⚠️ Сюїта клас не бачила за побудовою: кожна фікстура створює транзакцію ЧЕРЕЗ гаманець, тож `wallet: nil` у прикладах не траплявся жодного разу.

> **[ARCH.97/ARCH.96] `net_minted_supply(token_type)` — One-Home «скільки монет реально в обігу».** Σ(`confirmed` mints) − Σ(`confirmed` burns) для одного типу токена; burn розпізнається **колонкою `direction`** ([ARCH.95]; slash-інтент пишеться з ДОДАТНИМ `amount`, тож знак сумі його не видає, а `sourceable_type` після ARCH.95 відповідає на інше питання — «який burn є слешем»). Chainable — комбінується з `.for_cluster` / `.for_organization`. **Два живі споживачі, обидва незворотні:** поле `total_scc_supply` L1-якоря ([`05_04 §3`](05_04_Ethereum_L1_State_Anchor)) і база розміру спалення ([`05_05 §3`](05_05_Slashing_and_Risk_Policy)). ⚠️ Величина **не кумулятивна** — slash її зменшує; для «скільки взагалі колись намінтили» це НЕ той метод.

> 🔴 **[ARCH.103] `net_minted_by_cluster(cluster_ids, token_type)` — БАТЧЕВА форма того самого агрегату, і вона є третьою ФОРМОЮ, а не третьою КОПІЄЮ.** Віддає `{cluster_id => BigDecimal}` одним запитом; дискримінатор напрямку той самий (колонка `direction`, [ARCH.95]) — доти тут стояв `BURN_SOURCEABLE_TYPE` + `IS DISTINCT FROM`, бо наївний `!=` дав би `NULL` і мінти (`sourceable_type IS NULL`) випали б; `NOT NULL`-колонка цю вісь зняла. Заведено під СПИСКОВІ поверхні: після присуду про кластерну семантику кожен рядок списку контрактів питав би власний агрегат. ⊥ **Координата резолвиться `COALESCE(trees.cluster_id, blockchain_transactions.cluster_id)`, і це НЕ те саме, що `for_cluster`:** той бере координати через **OR**, тобто рядок з ОБОМА порахувався б у двох кластерах, а `COALESCE` — лише в одному. Сьогодні обидві форми дають однакову відповідь **лише через конвенцію писачів** (слеш ставить координати взаємовиключно; мінт і страховка — лише гаманець; Celo — лише кластер), а не через схему; тому рівність тримає пін у `blockchain_transaction_spec`, і перший писач з обома координатами розвів би список і деталку мовчки. 🔴 **Нуль ТУТ виміряний, а не фабрикований**, і межу треба тримати поруч із сусідами: кластер, відсутній у хеші, має емісію `0`, бо агрегат ВИКОНАВСЯ і підтверджених рухів немає — читач мусить робити `fetch(id, 0)`, а не `[id]`. Намалювати на такому кластері «не виміряно» було б [`ARCH.84`](00_07_Action_Plan_Tracker) навиворіт: приховати вимір замість вигадати його. ⚠️ **Часового вікна немає свідомо** — питання звучить «скільки намінтовано за ВЕСЬ час», тож будь-яка межа змінила б ВІДПОВІДЬ, а не лише вартість (партиційний прунінг тут структурно незастосовний, прецедент — `PERF.1`).

> 🔴 **[ARCH.101] НАПРЯМОК руху — деривація, і в неї ДВА споживачі різної форми, тож дім тримає саме ЗНАЧЕННЯ.** `BURN_SOURCEABLE_TYPE` читають SQL-агрегат вище **і** рядковий предикат `#burn?`, яким користується UI: той самий літерал, написаний двічі, розійшовся б тихо (обидві сторони «present» для будь-якого гейта). ⚠️ Вага цього не бухгалтерська: доти стрічка дашборда друкувала кожну транзакцію як «⬢ Minted … SCC», тобто **спалення показувалось емісією, приписаною конкретному дереву за DID** — знак `amount` напрямку не видає за побудовою (`validates numericality: greater_than: 0`). Правило для будь-якого читача: питання «мінт це чи burn» має рівно одну відповідь у застосунку, і вона НЕ виводиться зі знака суми. ✅ **Дисплей-половина (⚖️ 08-20): `#signed_amount`** — знак входить у число (−X для спалення) ОДНИМ домом на всіх екранних читачів (обидва леджери · tx-show · стрічка); НЕ для дроту (JSON/CSV віддають сирий `amount` + деривацію окремим полем) і НЕ для агрегатів (там SQL-CASE). Екранний бік і межа кольору → [`04_04 §12.14`](04_04_Phlex_UI_and_Tailwind).

> **`find_with_partition_pruning`** — partition-aware lookup: при наявності `created_at` додає `WHERE created_at IN [time, time+1s)`, дозволяючи PostgreSQL звернутись до однієї партиції (`O(log N)`) замість глобального сканування (`O(P×log N)`). ⚠️ **Переліку викликачів тут НЕМА свідомо** [PERF.1, 2026-08-15]: доти стояло «в `ApplicationWeb3Worker` **та контролері**» (однина) при семи живих сайтах у двох контролерах, сервісі й трьох воркерах — тобто картка занижувала периметр рівно тієї форми, яку інваріант наказує ВЖИВАТИ, і читалась як «це вузький випадок». Список викликачів volatile за побудовою; беріть його прогоном (`rg -n find_with_partition_pruning app/`), а не звідси. Клієнтський параметр — `?created_at=ISO8601`.

**Масштабування:** Таблиця переведена на PostgreSQL Declarative RANGE Partitioning по `created_at` (місячні партиції). Composite PK `(id, created_at)` — вимога partitioning. `self.primary_key = "id"` — Rails використовує `id` для `dom_id` та асоціацій. Всі 8 індексів перестворені (автоматично пропагуються на партиції). `PartitionMaintenanceWorker` тепер підтримує `blockchain_transactions` поряд з `telemetry_logs` та `gateway_telemetry_logs`.

---

### `TelemetryArchiveBatch` — Реєстр Архів-Батчів (E.60 Фаза 1б)

Один рядок = один `archive_root` mint-диспатчу (mint-anchored батч → `mint(bytes32)` → пін артефакту). Механіка/семантика — One-Home [`05_02 §E.60`](05_02_Proof_of_Growth_Pipeline); тут — модель-факти:

| Поле / аспект | Опис |
|------|------|
| `archive_root` | string(64), **nullable** + partial-unique `(archive_root, token_type) WHERE archive_root IS NOT NULL` — NULL-root легальний для `build_failed` (слід збою) і `superseded`-через-`abandon_repair!` (невиправний слід), обидва поза unique; zero32 у реєстрі НІКОЛИ не зберігається (derived-only on-chain) |
| `status` | integer-enum prefix: `pending`/`pinned`/`build_failed`/`mismatch`/`retention_expired`/`superseded`. **CAS-переходи** (`with_lock`-гарди — прецедент `EthereumAnchor` ARCH.66): термінали лише з `pending` (конкурентна pin-копія no-op, не перетираються); `repair!` (`build_failed`→`pending`, пізній rebuild вдався) і `abandon_repair!` (`build_failed`→`superseded`, невиправний — усі tx розібрані / вікна порожні; вихід із `.reconcilable`) — лише з `build_failed`. `pin_failed`-стану СВІДОМО нема (вичерпання = `pending` + `error_message`, документована стеля) |
| `tx_ids` | jsonb — snapshot-слід диспатчу (авторитетне членство = `blockchain_transactions.archive_batch_id`, set-once) |
| `txs_created_from` / `txs_created_to` | timestamp ×2 — `created_at`-межі tx-набору диспатчу: pin-/repair-воркер несе їх у КОЖЕН read-back по партиційованій `blockchain_transactions` (partition-pruning; id-only lookup сканував би кожну партицію) |
| `leaf_count` / `tx_count` / `ipfs_cid` / `tax_rate_applied` / `error_message` | лічильники + Pinata-CID артефакту + застосована tax-rate (у артефакт) + слід збою (≤500). 🔴 **`tax_rate_applied` = `nil`, коли податку НЕ стягували** — заповнюється з One-Home предиката `BlockchainMintingService#taxing?` (тип І стан пулу), не з самого типу токена [DOC-T.89]; доти поле стверджувало ставку на кожному carbon-диспатчі незалежно від того, чи пул її потребував. ⚠️ Запис **set-once** — усередині блоку `create_or_find_by`, тож повторний диспатч по НАЯВНОМУ батчу успадковує ставку творця; це коректно (той самий root ⇒ той самий tx-набір), але означає, що поле описує момент СТВОРЕННЯ рядка, не момент останнього мінта. Дім умови — розділ Dynamic Tax у [`05_03`](05_03_Tokenomics_SCC_and_SFC) |
| Індекси | partial-unique вище + `(status, updated_at)` (reconcile-скоуп `.reconcilable`, дзеркало `index_audit_logs_pending_archive`) |

### `NaasContract` — Nature-as-a-Service Контракт

**Включає:** `AASM`, `Auditable` ([ARCH.57] `after_update_commit if: :saved_change_to_status?` → `naas_contract_to_*` chain-only — ловить і raw `update!`-шляхи breach/cancel, що йдуть повз AASM у Burning/Termination-сервісах)

**Асоціації:**
- `belongs_to :organization`
- `belongs_to :cluster`

**AASM State Machine (column: `status`):**

```
draft ──activate──► active ──fulfill──► fulfilled
active ──breach──► breached    (positive-A slash — cluster >20% stress-деградація АБО per-tree deceased/removed)
active/draft ──cancel──► cancelled
```

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `status` | enum | `draft/active/fulfilled/breached/cancelled` |
| `total_funding` | decimal | Загальний обсяг фінансування (> 0) |
| `start_date` / `end_date` | timestamp | Строки контракту |
| `cancellation_terms` | jsonb | Ключ-сет умов дострокового виходу: `early_exit_fee_percent` · `burn_accrued_points` · `min_days_before_exit`. Читають `ContractTerminationService` (лише `burn_accrued_points`/`min_days_before_exit`) і `contracts/show` (рендер із запису); `burn_accrued_points = true` — єдиний шлях, яким `slash()` викликається як **погоджена форфейтура** (`contractual: true`, поза positive-A gate → [`05_05 §3.2`](05_05_Slashing_and_Risk_Policy)). ⚠️ `early_exit_fee_percent` — історичні ДАНІ без обчислювального читача: методи fee/refund зняті [BIZ.22, ⚖️ 2026-08-30 — Опція 1 MSA, без повернень і штрафів] |
| `cancelled_at` | timestamp | Час відміни контракту |
| `hadron_asset_id` | string | ID активу на Polygon Hadron |

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `check_cluster_health!` | Оцінює здоров'я кластера (Worker); делегує в `ContractHealthCheckService`, повертає verdict `:healthy`/`:degraded`/`:blackout`/`:skipped` (SLASH-1 — breach асинхронний, не тут) |
| `terminate_early!` | Дострокове розірвання (Опція 1 MSA: cancel + погоджена форфейтура; fee/refund-методи зняті [BIZ.22, ⚖️ 2026-08-30]) |
| `insurance_premium_amount` | `total_funding * INSURANCE_PREMIUM_RATE` (5%) — обчислювальний метод |
| `forester_share_amount` | `total_funding * 0.95` — частка лісника (обчислювальний метод) |
| `self.total_insurance_premiums` | Σ премій (5%) по активованих (active/fulfilled/breached) контрактах; off-chain USDC-факт, НЕ on-chain подія. 🔴 **Викликається у ДВОХ формах, і вибір форми — рішення про приналежність, не про стиль:** на класі це агрегат **усієї платформи**, на relation (`org.naas_contracts.…`) — внесок однієї організації (`where` чейниться на `current_scope`, як у `BlockchainTransaction.net_minted_supply`). Фінзвіт ([`04_03 §5.14а`](04_03_REST_API_v1_Reference)) бере САМЕ relation-форму: класова клала pooled-агрегат по всіх орендарях у звіт одного, а це ще й securities-фактор F8 ([ARCH.90](00_07_Action_Plan_Tracker)) |

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
| `trigger_event` | `critical_fire(0) / extreme_drought(1)` — ⛔ **ціле `2` зарезервоване, не вільне** (enum-значення лягає в колонку — переприсвоєння мовчки перейменувало б історичні рядки); **[INS.1]** застрахований перил, `validates presence` при створенні (peril-honest маршрутизація [`05_05 §4`](05_05_Slashing_and_Risk_Policy) без нього сліпа); прод-шляху створення полісів ще немає (E.20-майбутнє) — валідація = структурна гарантія, що будь-який майбутній шлях перил проставить (зараз seeds/фабрики) |
| `token_type` | `carbon_coin(0)` — ⛔ **лише одне значення, і це ПРИСУД, не недороблений enum** (DOC-T.89, ⚖️ 2026-08-26): поліс не може бути підписаний у типі, який система відмовляється виконувати, тож SFC знято з ДЖЕРЕЛА вибору, а не з наслідку. Ціле `1` зарезервоване тією ж підставою, що й `2` у `trigger_event` — переприсвоєння мовчки перейменувало б історичні рядки. ⚠️ Не плутати з `blockchain_transactions.token_type`, де `forest_coin(1)` лишається законним (мінт-лійка відбиває його до `:pending`) |

**AASM:** `trigger` (active→triggered), `pay` (triggered→paid), `expire` (active→expired).

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `payout_amount` | decimal | Сума виплати |
| `threshold_value` | decimal | Поріг спрацювання (0..100) |
| `required_confirmations` | integer | Кількість підтверджень |
| `etherisc_policy_id` | string | ID страхового контракту Etherisc Oracle (nullable) |

**Ключові методи:** `evaluate_daily_health!(target_date)` — Trigger-1 dual-trigger оракула (викликається `InsuranceOracleWorker` per-cluster fan-out за прапором `:parametric_insurance_oracle_enabled`; **arm-кандидат, НЕ payout**), `arm_candidate!(percentage)` (`:triggered` + `field_audit`; settlement окремо за НЕЗАЛЕЖНИМ підтвердженням — [`05_05 §6`](05_05_Slashing_and_Risk_Policy)), `escalate_no_data_field_audit!` (no-data «не карати жертву»-guard — дзеркало `flag_data_blackout!`), `recipient_wallet_address`, `uses_etherisc?` (`etherisc_policy_id.present?`).

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
| `probability_score` | decimal, **nullable** | 0.0..100.0 (впевненість Оракула). 🔴 **[ARCH.84] Писачів НУЛЬ:** `InsightGeneratorService` створює лише `daily_health_summary`, тож прогноз-інсайт у проді не народжується взагалі, а значення приходить винятково з `db/seeds.rb`. `NULL` = «не виміряно» — окремий СТАН, і модель це вже кодує (`#confidence_level` → `:n_a`). ⛔ Читач не сміє друкувати його голим: `ForecastCard` давав «%» без числа і `style="width: %"` (невалідний CSS) — смуга тепер **не малюється взагалі**, бо будь-яка довжина є твердженням про вимір. Те саме стосується сусіда `prediction_data["yield_impact"]` — у нього писачів теж нуль |
| `reasoning` | jsonb (GIN) | Структуровані причини рішення. Два індекси: `idx_ai_insights_reasoning_gin` (JSONB GIN — containment `@>` запити) та `idx_ai_insights_reasoning_fts` (tsvector GIN — повнотекстовий пошук по `reasoning->>'description'`). ⚡ **[ARCH.84] На КЛАСТЕРНОМУ рядку несе покриття** — `measured_trees`/`total_trees` (`store_accessor`), див. ⚡ нижче. ⊕ **[SEC.18] Третій із тієї ж родини — `fraud_trees`**: скільки вузлів сектора дали фрод-телеметрію. Заведений 2026-08-27 не заради нової осі, а тому, що ця магнітуда існувала ЛИШЕ всередині відрендереного `summary`, а той несе `cluster.name` і їхав у незворотний пін; знявши прозу, число мусили підняти в структуру, інакше зняття коштувало б доказу. ⚠️ `nil` = інсайт старший за поле, **не** «фроду не було» — «не було» виражає колонка `fraud_detected` |
| `source_log_ids` | integer[] (GIN) | IDs telemetry_logs, що стали джерелом |
| `fraud_detected` | boolean | Прапор маніпуляції даними |
| `model_source` | string | AI-модель (GPT-4, Claude, тощо) |
| `recommendation` | jsonb | Рекомендації Оракула (`action_required`, `priority`) via `store_accessor` |
| `prediction_data` | jsonb | Структуровані прогнозні метрики (`yield_impact`, `confidence_interval`, тощо). Споживається `OracleVisions::ForecastCard` для рендеру `forecast?` карток. Окремо від `reasoning` (raw chain-of-thought) і `recommendation` (action). |
| `analyzed_date` | date | Reserve-стовпець для майбутнього партиціонування за датою аналізу. Зараз у коді не читається — канонічна дата інсайту лежить у `target_date`. Лишається у схемі як точка розширення для багатоосей партиціонування post-TRL 8 (cross-ref E.37 TimescaleDB roadmap). |
| `average_temperature` | decimal | Середня температура за аналізований день |
| `total_growth_points` | bigint | Загальні бали зростання за день |
| `summary` | text | Текстовий підсумок (human-readable). 🔒 **[SEC.18] У публічний пін НЕ їде — це стеля, оголошена 2026-08-27.** На КЛАСТЕРНОМУ рядку речення інтерполює `cluster.name` (вільний рядок людини: `presence`+`uniqueness`, формат не судить ніхто), а `Filecoin::ArchiveService` пінить артефакт у IPFS незворотно. Форму обрано тим самим дискримінатором, що й для `AuditLog.metadata[:error]` — напрямок дефолту на незворотній поверхні, — але вихід ІНШИЙ: `error` є єдиним джерелом свого факту, тож звужений до КОДУ, а `summary` джерелом не був (решта рядка вже несе величини, з яких він рендериться), тож дешевше зняти поверхню, ніж класифікувати вміст. Проза лишається в БД і на екрані; носій — приклад `never carries the human-entered cluster name into the irreversible pin` |

**Ключові методи:** `confidence_level`, `forecast?`, `source_logs`, `attach_evidence!(log_ids)`, `status_label`. ⛔ `contract_breach?` **знято 2026-08-25** [SLASH-1]: його докстрінг стверджував «використовується в Slashing Protocol» при нулі викликачів, а поріг усередині був `0.8` — НЕ slash-поріг (той DAO-live `slash_stress_threshold`, дефолт `0.83`). Небезпечним його робила не мертвість, а підпис: перший читач, що повірив би імені, взяв би чужий поріг на грошовому шляху.

**Класові методи:** `AiInsight.slash_stress_threshold` (DAO-live поріг, ARCH.46 — дім спільності «тригер ≡ розмір») · **`AiInsight.reporting_date(now = Time.current)`** — див. ⚡ нижче.

> ⚡ **ДОБА ЗВІТУ = ОДИН ДІМ [ARCH.100].** Денний інсайт є агрегатом **UTC-доби** (`InsightGeneratorService` ріже вікно телеметрії в UTC і штампує нею `target_date`), а `for_date` шукає **точною рівністю**. Тому і писач, і КОЖЕН читач беруть добу з `AiInsight.reporting_date` — власних виразів не існує. ⚠️ Доти якорів було два: чотири копії `Time.current.utc.to_date - 1` і `Cluster#local_yesterday` («вчора» в поясі орендаря) дефолтом у шести вердикт-несучих сайтах. Для будь-якого поясу західніше **UTC−2** (уся Америка від Сан-Паулу) о 02:00 UTC ці дати не збігаються **ніколи**, тож нічний крон читав порожню добу — і одна вигадана порожнеча роз'їжджалась чотирма вироками протилежного знаку: `health_index = 1.0` («ідеально здоровий») · `:blackout` → Field Audit + невиплачена Celo-винагорода · страховий no-data → Field Audit · `:frozen` на слешингу. ✅ **ПРИСУД власника 2026-08-14: доба звіту ГЛОБАЛЬНА, пер-орендарський агрегатор ВІДХИЛЕНО** — і це вже не «доти», а рішення. Підстава — критерій місії «**відтворювано**» ([`00_01 §1.1`](00_01_Vision_Mission_and_Roadmap)): аудитор, що перераховує вікно, мусить дістати той самий результат, а пер-орендарська доба зробила б агрегат залежним від **мутабельного налаштування** на грошовому шляху (пороги слешингу, Celo-винагороди) — «денна» цифра дерева мінялася б від редагування таймзони організації. ⚠️ Ціна прийнята явно, не замовчана: UTC-доба для UTC−4 справді ріже локальний вечір навпіл — це властивість МЕТОДУ вимірювання, і саме тому вона оголошена тут, а не виведена читачем. `clusters.environmental_settings["timezone"]` **лишається** — периметр перевірено грепом, його єдиний споживач це картка кластера, тобто чесний факт ПРО кластер, а не вхід арбітражу. Носій єдиності — `spec/quality/reporting_date_home_spec.rb` (mutation-verified обома формами).

> ⚡ **КЛАСТЕРНИЙ РЯДОК НЕСЕ СВОЄ ПОКРИТТЯ [ARCH.84].** `stress_index` кластера — це СЕРЕДНЄ по деревах, що вийшли в ефір за добу, тож він правдивий про них і **німий про решту**. Доти дискримінатор існував лише в ПРОЗІ `summary` («Оброблено N вузлів»), а всі три машинні читачі — `Cluster#recalculate_health_index!` (звідти в комерційний `backing_asset.cluster_health`), `Celo::CommunityRewardService` (реальна виплата) і `Filecoin::ArchiveService` (незмінний IPFS-доказ) — бачили однакове: виміряно рантаймом, кластер із **1 із 5** дерев і кластер із **5 із 5** дали ідентичний `stress_index`, ідентичний `health_index = 1.0` і ідентичне `health_coverage(measured: 1, total: 1)`. Тому писач кладе в `reasoning` пару **`measured_trees`** (`.distinct` по деревах — дзеркало `DailyHealthRouter#critical_count`) і **`total_trees`** (живий `COUNT` по `trees.active`, не денормалізований `active_trees_count`: рядок годує гроші й доказ, а лічильник тримають колбеки, які `update_all` обходить). Читає її `Clusters::Show` через `measurement_coverage` (мовчить на повному покритті) і `Filecoin::ArchiveService`. ⚠️ **Популяція середнього — `trees.active`**, як у всіх трьох денних читачів: доти писач брав `cluster.trees` цілком, тож інсайт мертвого дерева входив у середнє живого лісу — те саме «кладовище розбавляло», що ⚖️ 2026-07-30 зняв на слешинг-шляху. ⛔ Стеля: `average(:stress_index)` усереднює РЯДКИ, а `measured_trees` рахує ДЕРЕВА; розійтись вони могли б лише на дублікаті одного дерева за добу (unique-індекс його легалізує через nullable `model_source`), але такий рядок до підрахунку не доживає — `InsightGeneratorService#perform` починається з тотального `delete_all` по добі. Тригер перегляду обох — перший писач денного інсайту поза цим сервісом. ⚠️ На TREE-рядку пара `nil` за побудовою: дерево не агрегат.

**Scopes:** `highly_probable`, `upcoming`, `critical_stress`, `for_date(date)`, `fraudulent`, `referencing_log(log_id)`, `search_reasoning(query)` — повнотекстовий пошук у `reasoning->>'description'` через `plainto_tsquery('simple', ...)` з використанням tsvector GIN-індексу `idx_ai_insights_reasoning_fts`.

---

### `EwsAlert` — Тривога Раннього Попередження

**Включає:** `AASM`

**Асоціації:**
- `belongs_to :cluster` (optional)
- `belongs_to :tree` (optional)
- `belongs_to :resolver, class_name: "User"` via `resolved_by` (optional)
- `belongs_to :assignee, class_name: "User"` via `assigned_to_id` (optional) — **[E.20]** «хто зараз на гачку» ⊥ `resolver` («хто закрив»): дві РІЗНІ ролі в часі

**Enums:**

| Enum | Значення |
|------|----------|
| `status` | `active(0) / resolved(1) / ignored(2)` |
| `severity` | `low(0) / medium(1) / critical(2)` |
| `alert_type` | `severe_drought(0) / vandalism_breach(2) / fire_detected(3) / system_fault(5) / entropy_anomaly(6) / field_audit(7) / queen_offline(8) / queen_uplink_lost(9) / chainsaw_detected(10) / firmware_fault(11) / firmware_reverted(12) / firmware_canary_trip(13) / actuator_stuck(14) / emergency_response_undeliverable(15)` (prefix: true) — ⛔ **цілі `1` і `4` зарезервовані, не вільні**: enum-значення лягає в колонку, тож переприсвоєння мовчки перейменувало б історичні рядки; вердиктів «комахи»/«сейсміки» немає, бо немає вимірювача — класу «комаха» в TinyML не існує, сейсмічного каналу теж ([`03_03 §5`](03_03_TinyML_Acoustic_Inference)); `field_audit` = аудит на місці (причина невизначена: no-data blackout / freeze без прямого доказу A / insurance-кандидат), свідомо окремий від `system_fault` (поломка заліза/зв'язку), щоб не накручувати penalty_factor через `comms_no_ack?` (gap-D) і не конфлатити дедуп ([SLASH-1](00_07_Action_Plan_Tracker)); `queen_offline(8)`/`queen_uplink_lost(9)` = дзеркальна пара gateway-health (Rails помітив тишу / Королева кричить через Helium — ARCH.54/34); `chainsaw_detected(10)` = acoustic-anomaly АБО panic-TX без термального сигналу ([SLASH-1] спліт + P0-фікс гейта `panic? \|\| bio_status_anomaly?`: реальна пилка їде panic-кадром зі status=homeostasis; non-fire маршрут dClimate → Field-Audit; ⚠️ НЕ в A-сет slash'а до field-validation TinyML); `firmware_fault(11)` = софт-збій прошивки (wire `vm_error`: mruby-crash/OOM/unprovisioned — vendor-attributable ops-тріаж; НЕ в A-сеті, НЕ в `comms_no_ack?`, виключений з `critical_unmaintained?`); `vandalism_breach(2)` — [SLASH-1 P0] авто-writer'а немає, створюється лише ручною Field-Audit C→A ескалацією ([`06_08 §4`](06_08_Resilience_and_Failover_Policy)); `actuator_stuck(14)` = [ARCH.58] Rails загубив слід ВЛАСНОЇ команди (актуатор числиться active понад вікно наказу) — vendor-attributable, як `firmware_fault`, тож поза A-сетом, поза `comms_no_ack?` і виключений з `critical_unmaintained?`; носій свідомо ВЛАСНИЙ, бо `system_fault` дав би подвійний упліфт, а cluster-level `field_audit` осліпив би per-tree dead-man switch ([`06_08 §1.3`](06_08_Resilience_and_Failover_Policy)); машинного resolve не має — фізичний стан пристрою невідомий; `emergency_response_undeliverable(15)` = [ARCH.75] аварійну фізичну відповідь **не відправлено** — єдиний тип, що свідчить про НЕ-дію: команд не створено взагалі, замість невалідних рядків, які доти лягали мовчки й не вміли навіть померти. Причин ЧОТИРИ на двох осях дедупу (дім механіки — [`04_02 §7`](04_02_Business_Logic_and_Services)): доїхати не може КОНКРЕТНИЙ пристрій (протокол просить понад `Actuator#max_active_duration_s` АБО каденс шлюза довший за вікно релевантності кроку) ⊥ виконати нема ЧИМ цілий крок протоколу (пристрою цього типу в кластері не встановлювали АБО жоден зі встановлених не придатний — стан пристрою чи мовчазний шлюз). ⚠️ Друга вісь свідомо не колапсує в «немає інструментів»: «залізо не купили» і «залізо є, але недосяжне» — різні дії людини, і згортання їх в одне повідомлення приписувало б операторові власну недоробку платформи; класифікація дзеркалить `actuator_stuck` (vendor-attributable → поза A-сетом, поза `comms_no_ack?`, виключений з `critical_unmaintained?`), бо конфігурацію задали МИ, і виїзд лісника числа не лікує |
| `satellite_status` | `unverified(0) / verified(1) / rejected_fraud(2) / inconclusive(3)` (prefix: :satellite) |

**AASM:** `mark_resolved`, `ignore`, `reopen` (resolved/ignored→active).

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `severity` | enum | `low(0) / medium(1) / critical(2)` |
| `message_key` | string | **Який саме інцидент** — ключ у `alerts.messages.*` (усі локалі). Проза НЕ зберігається: алерт народжується у воркері, де локалі глядача не існує, тож готовий рядок замерзав би однією мовою назавжди |
| `message_params` | jsonb | **Виміряні значення** для інтерполяції (`did`, `voltage_mv`, `temperature_c`, `acoustic_events`, `z_value`, …) — те, що від мови не залежить. ⊕ **Enum-параметр теж їде СИРИМ** (`token_type`), а мітку збирає читач у момент показу: `PARAM_LABEL_RESOLVERS` конвертує named-параметри через label-дім (`BlockchainTransaction.token_type_label`) в обох читачах — `#message` і `#resolution_texts` (⚖️ 2026-08-20; готова мітка в JSONB заморозила б локаль продюсера) |
| ~~`message`~~ | — | **Колонки НЕМА** (знята 2026-07-26). `EwsAlert#message` — це МЕТОД-рендер: `I18n.t("alerts.messages.<key>", **params, default: key.humanize)`. Fail-open на невідомий ключ, `nil` за порожнього. Присутність несе валідація на `message_key` — не на `message`, інакше кожен `save` гнав би I18n-лукап заради того самого висновку |
| `resolved_at` | datetime | Час вирішення |
| `assigned_to_id` | bigint, FK→users, nullable | **[E.20]** Виконавець, що взяв тривогу. Пишуть лише `EwsAlert#claim!`/`#release!` — обидва вимагають `status_active?`, тож приєднання ПІСЛЯ резолюції неможливе за побудовою. Претензія лише на нічию (`AlreadyAssigned` → 409); відпустити може виконавець **АБО** admin+ (`NotAssignee` → 403), інакше хибний клік замикав би тривогу назавжди |
| `assigned_at` | datetime, nullable | **[E.20]** Момент приєднання. Окрема колонка, а НЕ деривація з `updated_at`: різниця `assigned_at − created_at` і є Кат-A-сигналом [`05_05 §2`](05_05_Slashing_and_Risk_Policy) «неприєднання Forester'а до інциденту в SLA», у якого доти не було референта в коді. 🔴 Повтор ВЛАСНОЇ претензії — no-op саме тому: `update!` зсунув би цей штамп, тобто другий клік мовчки покращував би власний SLA. ⚠️ Сам ПОРІГ SLA лишається ⚖️ — колонка робить сигнал виразним, а не вирішує його |
| `resolution_log` | jsonb, NOT NULL, default `[]` | **[I18N.1]** Масив записів закриття: машинні `{key, params, at}` ⊥ людські `{text, at}` — у БД ідентифікатор події, фраза локаллю глядача в момент показу (`resolution_texts`; контракт і ключі — рядок `resolve!` нижче). Замінив text-колонку `resolution_notes` 2026-08-20: append-проза мовами впереміш пара «ключ+параметри» виразити не могла |
| `dclimate_ref` | string | Посилання на dClimate для супутникової верифікації |

**Унікальність:** `alert_type` унікальний в межах `[tree_id, status]` — захист від дублів. **[SLASH-1]** cluster-level дзеркало: частковий unique-index `(cluster_id, message_key) WHERE alert_type=field_audit AND status=active AND tree_id IS NULL` + One-Home хелпер `EwsAlert.escalate_field_audit!(cluster:, message_key:, message_params: {}, tree: nil)` (exists?-skip → nil; `RecordNotUnique`-rescue) — одна АКТИВНА ескалація на кластер **НА КОЖНУ ПРИЧИНУ** (щоденні crons при тривалій деградації плодили дубль щодоби; той самий продюсер шле той самий ключ, тож дедуплікується й далі). 🔴 **[ARCH.110, ⚖️ 2026-08-25] `message_key` у ключі — не деталь індексу, а фікс мовчазної втрати вироку:** доти ключ був `(cluster_id)`, тож продюсер, що приходив другим, діставав `nil` та INFO-лог, а виклик-сайти на `nil` не реагують за побудовою — після slash-freeze справжній cluster-wide blackout не був би записаний НІДЕ, хоч це протилежні за змістом вироки з різними діями людини. **Причини розділено оголошеним реєстром** `SILENCE_ASSERTING_KEYS` («кластера не чути») ⊥ `VERDICT_HELD_KEYS` («вердикт утримано / зовнішня перешкода»); першу половину читає глушник dead-man switch'а ([`06_08 §1.3`](06_08_Resilience_and_Failover_Policy)), і повноту обох стереже `spec/quality/cluster_field_audit_key_registry_spec.rb`. ⚠️ Класифікує ПУСКАЧ, а не ім'я: `insurance_no_data` стоїть у silence-половині, бо його єдина дорога — `router.blackout?`. **[SILENCE-1]** per-tree гілка того ж хелпера (`tree:` задано): dedup = модельна валідація + частковий unique-index `..._unique_active_per_tree` (`tree_id IS NOT NULL`) + вузький `RecordInvalid(:taken)`-rescue (другий гоночний шлях — committed-дубль ловить валідація, не index); індекси взаємовиключні → cluster-blackout ⊥ per-tree тиша співіснують. Усі creation-сайти через хелпер ([`04_02 §11`](04_02_Business_Logic_and_Services) — 5 cluster-scoped + `TreeStalenessSweepWorker`).

**Ключові методи:**

| Метод | Опис |
|-------|------|
| `resolve!(user:, notes:, key:, params:)` | Закрити тривогу + закрити пов'язаний MaintenanceRecord. [I18N.1] Слід закриття — запис у **`resolution_log`** (jsonb-масив): машинні викликачі дають `key:`+`params:` (у БД їде ідентифікатор події, фраза збирається локаллю ГЛЯДАЧА через `#resolution_texts`, fail-open `humanize` — той самий контракт, що `message_key`), людина — вільний `notes:` (text-запис, мова резолвера, не локалізується). Без обох — дефолтний ключ деривується від АГЕНТА (`operator_closed` ⊥ `system_closed`). Час — поле `at` самого запису. Ключі — `alerts.resolutions.*` ×4; appendери поза resolve! (dclimate) кличуть `#log_resolution` |

🔴 **Безкластерний алерт закривається САМ, і це не оптимізація, а єдиний можливий шлях** [ARCH.82, ⚖️ founder 2026-08-14]. `Organization has_many :ews_alerts, through: :clusters` — це INNER JOIN, тож рядок без кластера не існує на жодній орг-поверхні; `alerts#resolve` теж іде через `acting_organization!.ews_alerts`, отже людської дії над ним НЕМАЄ ні в кого, включно з super_admin. Три такі писачі (`oracle_balance_low` · `mint_volume_anomaly` — обидва `Treasury::MonitorService`; `insurance_reserve_hold_*` — `InsurancePayoutWorker`), і без резолвера кожен їхній рядок висів би `active` вічно.

**Форма ліку — резолвер біля ПИСАЧА, у тому ж проході, що й детектор** (зразок: `TreeStalenessSweepWorker#resolve_returned_trees`). Причина спостережувана саме там: баланс відновився · обсяг повернувся під стелю. 🔴 **Ключ одужання мусить збігатися з ключем ДЕДУПУ** — для балансів це ПАРА (мережа, підписник): резолвер, що закриває все, гірший за його відсутність, бо гасить живу тривогу (носій цього напрямку — окремий приклад, mutation-verified). ⚠️ **Дві причини закриття розрізняються в нотатці:** «повернулось під стелю» це одужання, а «детектор вимкнули» — ні; закриваємо обидва (алерт від вимкненого детектора не має жодного шляху зникнути), але запис не сміє стверджувати одужання. ⊕ Стеля названа: резолвер бачить лише гаманці, ПЕРЕВІРЕНІ цим проходом, тож activation-gated гаманець зі знятим ключем випадає — «ключ зник» ≠ «баланс поповнено».

**Читальну половину закрито НЕ видимістю, а каналом:** оператор бачить усі три роди в Grafana (`oracle_balance_ratio` ×2 · `mint_volume_window_scc` · `insurance_reserve_hold_total` — останній заведено тим же присудом), тож розширювати id-set-форму на запис не знадобилось — [`04_03 §3.1`](04_03_REST_API_v1_Reference).
| `coordinates` | `[lat, lng]` через `tree` або `cluster.geo_center` — інакше **`nil`** [ARCH.82]. 🔴 Доти віддавав `[0.0, 0.0]` «щоб не ламати Leaflet.js», але це не відсутність, а **вигадана географія** (Гвінейська затока), і стан досяжний: `trees.latitude/longitude` nullable (тому й існує скоуп `geolocated`), а `geo_center` деривується з опційного полігона. Ціна була доказова, не косметична — єдиний споживач (`Dclimate::VerificationService`) годує координати в запит про пожежу, і його вердикт лягає на алерт як `satellite_status`. ⚠️ Споживач мусить розрізняти ЗАТРИМКУ і ВИРОК: `nil` дає **термінальний** `inconclusive` (без orbital-ретраю, бо координати чеканням не зʼявляться), для критичних — той самий негайний Field Audit, що при затемненні |
| `actionable?` | Чи можна автоматично відреагувати |
| `requires_satellite_consensus?` | fire або drought → IoTeX ZK-верифікація |
| `dispatch_notifications!` | Надіслати Telegram/Push (email — critical) |
| `schedule_satellite_verification!` | Поставити в чергу Worker |
| `broadcast_new_alert` | Turbo Stream |

**Scopes:** `unresolved` (status_active), `critical`, `recent`.

---

### `AuditLog` — Незмінний Журнал Дій

**Призначення:** Повний compliance-журнал усіх дій. Підтримує blockchain-ланцюжок хешів та IPFS-архів.

**Append-only [ARCH.57]:** «незмінність» тримається кодом, не лише конвенцією — `before_update` дозволяє мутацію ЛИШЕ архівних полів (`ARCHIVAL_MUTABLE_COLUMNS`: `ipfs_cid`/`archive_requested_at`/`updated_at` — останній механічний, Rails бампає на кожен update), решта → `ActiveRecord::ReadOnlyRecord`; `before_destroy` завжди raise. `delete_all`/`update_all` обходять колбеки — org-каскад закритий `dependent: :restrict_with_error` (Org із журналом не видаляється; узгоджено з `users`/`naas_contracts`).

**Chain-payload tamper-evidence [ARCH.57]:** канонічний рядок хешу = `org|user|action|auditable_type|auditable_id|metadata(sorted-JSON)|created_at|ip_address|user_agent` — часова мітка й актор-форензика В ланцюзі, тож tamper через `update_all`/raw SQL (повз append-only колбек) ламає `verify_chain_integrity` (mutation-verified спеки). Timestamp канонізує `canonical_timestamp` (UTC + `iso8601(6)` — µs-трім збігається з PG `timestamp(6)`-серіалізацією → DB round-trip детермінований); `compute_chain_hash` фіксує `created_at ||= Time.current` ДО хешування.

**Auditable-концерн [ARCH.57]** (`app/models/concerns/auditable.rb`): привілейовані дії пишуться в ланцюг через `record_audit_trail!` (async, дзеркало MRV.1; актор = людський ініціатор або `oracle_executioner` через `Auditable.system_actor_id`, без актора → WARN-skip). **Хук-механізм = `after_update_commit if: :saved_change_to_status?`, НЕ AASM `after_all_transitions`** — з двох причин: (1) AASM-колбек файрить ДО персистенції → rollback переходу лишав би фантомний рядок (Sidekiq-push не відкочується); (2) prod-шляхи ставлять статус raw `update!`-ом повз AASM (breach/cancel контрактів). Bulk-обходи (`update_all`/`update_columns` в ActuatorCommand) закриті ручними викликами (aggregate-рядок `actuator_bulk_cancelled` + pre-dispatch failures). Coverage: money-переходи (MRV.1, єдиний `archive: true` — IPFS-outbox) · `NaasContract`-статуси · slash-вердикти `slash_verdict_burn/frozen/evasion` (`BlockchainBurningService` — ПРИЧИНА вироку; MRV.1 логує лише рух коштів) · `ActuatorCommand`-статуси · `User` role-change · `SystemParameter` value-мутація · `HardwareKeyService`-ротація — усе нове **chain-only** (`archive: false`: fraud-attribution/DID/key/role-метадані не пінити на публічний IPFS — INF.22 over-exposure клас; tamper-evidence дає сам ланцюг). Стеля: глобальний (org=nil) ланцюг наразі read-only через console `verify_chain_integrity(nil)` — org-скоуплені контролери його не віддають; UI-reader = за першою ops-потребою.

**Асоціації:**
- `belongs_to :user`
- `belongs_to :organization` (**optional [ARCH.57]** — `nil` = глобальний системний ланцюг для org-less дій, як-от `SystemParameter`; окремий advisory-lock ключ 0, верифікація `verify_chain_integrity(nil)`)
- `belongs_to :auditable, polymorphic: true` (optional)

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `action` | string | Назва дії |
| `ip_address` | string | IP ініціатора |
| `metadata` | jsonb | Контекст дії |
| `chain_hash` | string | SHA-256 попереднього запису + payload (blockchain-ланцюг) |
| `ipfs_cid` | string | IPFS CID при архівуванні |
| `l1_anchor_tx_hash` | string | ⚠️ **Не задротовано** [ARCH.103]: нуль посилань у `app/`/`lib/`, навіть `AuditLogBlueprint` його не віддає. Залишок ПЕР-РЯДКОВОЇ архітектури якорення, витісненої АГРЕГАТНОЮ: `Ethereum::StateAnchorService` бере лише ОСТАННІЙ `chain_hash` як інгредієнт leaf0, і tx-хеш назад у рядок не пише ніколи. Leaf-рівневий proof (ARCH.12) дістав лише `TelemetryLog`, дзеркала для `AuditLog` немає |
| `archive_requested_at` | datetime | [INF.22] Outbox-маркер: money/MRV-лог, призначений для IPFS-архіву (виставляє `AuditLogWorker`; factory/console прямий `create!` не ставить) |

**Класові методи:**

| Метод | Опис |
|-------|------|
| `record_async!(attrs, archive: true)` | Async-запис через Worker; `archive: false` = chain-only [ARCH.57] (без outbox-маркера і Filecoin-піна) |
| `bulk_record!(entries)` | Bulk insert_all |
| `verify_chain_integrity(org_id)` | Перевірка ланцюжка хешів (`nil` = глобальний ланцюг) |

**Scopes:** `recent`, `archived` (ipfs_cid присутній), `not_archived`, `archivable` (archive_requested_at присутній — outbox-eligible), `pending_archive` (archivable ∧ not_archived — FilecoinReconcileWorker-скоуп), `by_action`, `by_user`, `by_ip`, `for_period`.

---

### `MaintenanceRecord` — Журнал Обслуговування

**Призначення:** Фізична дія лісника в полі (Proof of Care). Прикріплені фото з GPS.

**Includes:** `GeoLocatable`

> 🔴 **[SEC.28] Знищення фотодоказу входить у ланцюг аудиту — але писач СИНХРОННИЙ і живе в контролері, тож `include Auditable` тут свідомо НЕМА.** Периметр `Auditable` будувався під governance/money/hardware, і фотодоказ виглядав вужчим класом; насправді він несе **доказову базу D-MRV**, тобто саме те, заради чого ланцюг існує (критерій місії «невідбирано»). ⚠️ **Вагу дає ПАРА властивостей, не одна:** видалення незворотне (`purge_later` → S3) І доти було безслідним — разом це множник, бо та сама помилка авторизації коштує тут дорожче, ніж на сусідніх поверхнях: наслідок не відновлюється і не розслідується.
>
> 🔴 **Чому `AuditLog.create!`, а не штатний `record_audit_trail!`:** той іде через `record_async!` → `AuditLogWorker`, тобто «слід перед знищенням» означало б порядок ВИКЛИКУ, а не персистенції — при зупиненому Sidekiq фото зникає незворотно, а сліду не лишається взагалі, тобто асинхронність **відтворює рівно ту пару властивостей, проти якої захист і ставиться**. Прецедент форми — `organizations_controller#record_switch!` (там та сама підстава, слабша). Включений concern був би мертвим кодом: він віддає лише async-обгортку.
>
> ⚠️ **Слід несе ІДЕНТИЧНІСТЬ, не факт** (`filename` · `byte_size` · `checksum` · `content_type`): після purge доказу не існує, тож запис «фото видалено» дав би нуль для розслідування — цей набір є єдиною ниткою, якою знищений блоб можна звірити із зовнішньою копією. Дім виклику — `MaintenanceRecordPhotosController#record_audit_trail_for_purge!`; **зворотність** (мʼяке видалення / archive-before-purge) свідомо відкладена до [`00_07`](00_07_Action_Plan_Tracker) SEC.18: ретеншен доказу й GDPR-стирання — одна політика, і другий її дім тут був би дрейфом.

**Асоціації:**
- `belongs_to :user`
- `belongs_to :maintainable, polymorphic: true` (Tree або Gateway)
- `belongs_to :ews_alert` (optional)
- `belongs_to :attestor, class_name: "User"` via `attested_by_id` (optional) — **[E.20]** друга пара очей
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
| `action_type` — заявка на біомасу | enum | 🔴 **[E.20, ⚖️ 2026-08-24] Три інваріанти, і кожен закриває двері, які інші лишають відчиненими.** (1) **Фото від дверей:** `photo_required_for_biomass_claim` — запис не створюється й не ПЕРЕВОДИТЬСЯ в `biomass_extraction` без доказу. Умова спрацювання — «тип щойно став biomass» (`new_record? || action_type_changed?`), а не `on: :create`: `#update` пермітить `:action_type`, тож форма `on: :create` лишала б обхід «створити як inspection → перевести». ⛔ Every-save форма (як у `repair`/`installation`) неможлива — обидва Puro-воркери роблять `update!` на вже-створеному записі, і паспорт завис би в `:sent` назавжди ([ARCH.91]). ⛔ Винятку для `system_generated` НЕМА свідомо: платформа камери не має, отже не може подавати заявку в зовнішній реєстр. (2) **Односторонні двері:** `biomass_claim_is_one_way` — назад тип не міняється; без цього `biomass → inspection` вимикав і presence `biomass_yield_kg`, і замок доказу, після чого фото під виданим CORC знищувалось `purge_later`. (3) **Замок:** `evidence_locked?` (⊥ `evidence_backed?`) — два РІЗНІ питання під одним предикатом доти: «чи фото обовʼязкові на кожен save» ⊥ «чи вони незнищенні». Читачі замка — `guard_evidence_purge!` і кнопка `PhotoCard`. |
| `attested_by_id` · `attested_at` | bigint FK→users · datetime, обидва nullable | **[E.20] «Атестатор ≠ бенефіціар».** ⚖️ founder 2026-08-24: акаунт атестатора живе **В організації власника**, а незалежність купується **ДОГОВОРОМ** (сторонній аудитор / академічний партнер, якому платить не бенефіціар). 🔴 Буквальну форму «організація атестатора ≠ організація власника» **відкинуто виміром**, і підстава структурна: читацький скоуп записів деривується з `acting_organization!.clusters`, а перемикати контекст організації вміє лише `super_admin` — тобто атестатор із чужої орг запису НЕ БАЧИТЬ, і вимога означала б пробити крос-тенантне читання, тобто ту саму ізоляцію, в якій жив ланцюг account-takeover. Тому машинно перевірний тут рівно ОДИН інваріант — **підписант ≠ автор** (`MaintenanceRecord::SelfAttestation` → 403); решту тримає договір, і канон каже це прямо, замість вдавати сильніший гард. Повтор тим самим атестатором — no-op: `attested_at` не зсувається, бо саме штамп робить запис доказом. ⚠️ **Виміряно 2026-08-25: стан-пастки «нікому підписати» НЕМАЄ — але вихід тихо підмінює атестатора.** `forest_commander?` включає `role_super_admin?`, а той єдиний уміє перемикати контекст організації (`resolve_acting_organization`), тож у організації з ОДНИМ лісником заявку може засвідчити платформа. Це рятує тракт від глухого кута й водночас дає незалежність СЛАБШУ за ратифіковану договірну. ✅ **З 2026-08-25 підміна ОГОЛОШЕНА, а не схована** — предикат `attested_outside_owner_organization?` (організація підписанта ≠ організація автора) і рядок метаданих на сторінці запису: читач доказу мусить знати, чиїм підписом той доказ стоїть. Доти єдиним слідом було голе `attested_by_id`, якого людина не читає. 🔴 **Атестація — ПУСКАЧ ОБОХ незворотних ланок (⚖️ founder 2026-08-24 · розширено 2026-08-25), не лише дозвіл:** `attest!` сам ставить `PuroEarthPassportWorker` у чергу і сам оголошує дерево мертвим (`declare_deceased!`, в ОДНІЙ транзакції з підписом), а `EcosystemHealingWorker` не робить ні того, ні того. ⚖️ **Смерть переїхала сюди 2026-08-25 із трьома звіреними опорами:** (1) `declare_deceased!` ТЕРМІНАЛЬНИЙ — подій `from: :deceased` немає жодної, писачів `status` повз AASM теж, тож помилкове оголошення відкату не має, і тим самим переходом смикається `trigger_slashing_protocol`; (2) сам перехід приймав `from: :active` **без жодної передумови** (ні тиші, ні стресу, ні `last_seen_at`), тобто достатньою причиною був рядок форми однієї людини; (3) корисна ланка — CORC-паспорт — і так не стріляє (`ORACLE_PURO_PRIVATE_KEY` activation-gated), тож попередній гейт стеріг єдину ланку, яка не виконується, а безвідкатна йшла вільно. Транзакція спільна СВІДОМО: заатестований запис, що не змінив статус дерева, стверджував би виконану дію, якої не сталося. ⛔ **Дзеркальний двір `decommissioning` → `removed` присуд свідомо НЕ накрив** (⚖️ founder 2026-08-25): «зняли обладнання» ≠ «дерево померло», CORC-заявки той шлях не породжує, тож розширення означало б присуд про робочий процес, якого ще ніхто не проходив; тригер перегляду — перша реальна колізія в полі. Підстава виміряна: доти enqueue був безумовним, тож «вікно для атестатора» фактично дорівнювало життю джоби (`retry: 5` без власного `sidekiq_retry_in` ≈ 7–10 хв до DeadSet) — дедлайн, що селектує підпис не дивлячись, тобто рівно ту профанацію, проти якої правило й стоїть |
| `notes` | text | Опис (≥ 10 символів) |
| `latitude` / `longitude` | decimal | GPS координати патрульного |
| `hardware_verified` | boolean | Залізне підтвердження обслуговування. ⚖️ [UI.7, 2026-08-20] Ставиться ЛИШЕ через `verify`-екшен за предикатом **`#hardware_pulse_confirmed?`** — вузол вийшов в ефір (`maintainable.last_seen_at`) ПІСЛЯ `performed_at`; єдиний канал, якого технік не контролює (пульс заліза, не телефон і не поле форми). Доти екшен ставив `true` безумовно — «залізне підтвердження» було самоатестацією другого кліку |
| `system_generated` | boolean | Провенанс: рядок написала платформа, не лісник (default `false`) |
| `biomass_yield_kg` | decimal | Вимірювання біомаси (для tokenomics) |
| `labor_hours` | decimal, **nullable** | Витрачений час. `NULL` = не введено (форма пропонує поле без `required:`), і це НЕ нуль годин |
| `parts_cost` | decimal, **nullable** | Вартість запчастин. `NULL` = не введено ⊥ введений `0` = вимір «запчастин не було» |
| `biomass_passport_tx_hash` | string | TX-хеш паспорту біомаси (Puro.earth Biochar) |
| `biomass_passport_status` | string enum, **nullable** | [PERF.1(д), 2026-08-20] Lifecycle Puro-анкера — «третя форма» (прецедент `EthereumAnchor`, БЕЗ грошової таблиці): `sent` → `confirmed`/`failed`/`manual_review`; `NULL` = анкер не broadcast'ився. Переходи гардовані `with_lock` (`confirm_biomass_passport!`/`fail_biomass_passport!`/`escalate_biomass_passport!`; confirm/fail приймають і `manual_review` — гардований console-вихід оператора). Phase 3 (REST у Puro) гейтована на `confirmed` |

**Методи:** `total_cost`, `trigger_ecosystem_healing!`, `biomass_claim_state`, `attested_outside_owner_organization?`.

> 🔴 **[E.20, 2026-08-25] «Де зараз заявка на CORC» — ДЕРИВАЦІЯ, а не колонка, і дім у неї один: `#biomass_claim_state`.** Читачів троє (сторінка запису · рядок реєстру · блупринт), і кожен інакше відповів би на порожнє поле, бо `biomass_passport_status = NULL` однаковий у ДВОХ станах із протилежними адресатами: `:awaiting_attestation` (підпису ще немає — лікує інший лісник) ⊥ `:not_filed` (підпис є, заявка не вийшла — потрібен оператор платформи). Далі стан збігається з паспортним lifecycle (`sent`/`confirmed`/`failed`/`manual_review`); для не-biomass записів — `nil`, бо питання до них не стоїть. Мітка стану має власний дім-скоуп `BIOMASS_CLAIM_STATE_LABEL_SCOPE` (дзеркало `ACTION_TYPE_LABEL_SCOPE`, і з тієї ж підстави: показують її два компоненти).
>
> ⚠️ **Порогу на «джоба ще в дорозі» тут свідомо НЕМА.** `PuroEarthPassportWorker` вичерпує `retry: 5` за ≈7–10 хв і осідає в DeadSet, після чого статус не зміниться НІКОЛИ без консольного re-enqueue — тобто «не подано» правдиве в обох випадках, а вигаданий таймер додав би третю відповідь на те саме питання. Скоуп черги — `MaintenanceRecord.awaiting_attestation`; поверхні — [`04_03 §4`](04_03_REST_API_v1_Reference) (`?pending_attestation=1`) і маркер у самому рядку реєстру. **Маркер стоїть у рядку, а не лише за фільтром, свідомо: фільтр знаходить того, хто вже ШУКАЄ, а подавач заявки не шукає — він вважає, що подав.**

> 🔴 **[ARCH.103] `total_cost` віддає `nil`, коли бодай ОДИН доданок не введено — «Total» стверджує повноту, тож сума з невідомим доданком не є total.** Доти обидва `.to_f` перетворювали «не введено» на нуль, метод не повертав `nil` жодного разу, і три поверхні друкували `$0.00` там, де технік просто не заповнював поле; blueprint віддавав `total_cost: 0.0` поруч із чесними `null` для обох доданків. ⚠️ Ціна була ЗАНИЖЕННЯ (unit-economics Series C), а введений `0` лишається виміром — безкоштовний візит видимий.

**Evidence Protocol** — `repair` і `installation` вимагають фото на КОЖЕН save (`photos_required_for_critical_actions`); решта `action_type` виходить із валідації рано. ⊕ **[E.20] `biomass_extraction` — окремий гейт із іншою межею** (`photo_required_for_biomass_claim`): фото вимагається в мить, коли тип СТАЄ заявкою, а не на кожному save — інакше `update!` обох Puro-воркерів завісив би паспорт назавжди. Три питання й три предикати — картка `action_type` вище.

🔴 **Виняток для системних записів мусить бути КОЛОНКОЮ, а не транзієнтною ознакою [ARCH.91].** Валідація оголошена **без `on:`**, тож біжить на кожен `save`, а не лише на `create` — отже ознака, що не переживає `find`, робить запис невиправно невалідним: `verify` віддає `false`, і будь-яка правка теж. Писачі `system_generated: true` — провізія (`ProvisioningController#register`), factory-flashing bench (`FactoryFlashing::AuditTrail`) і slash-надгробок (`BurnCarbonTokensWorker`, підписант — Oracle Executioner). ⚠️ **Ознака НЕ входить у `maintenance_params`**: вона фіксує провенанс, а не намір клієнта — інакше лісник знімає з себе вимогу фотодоказів одним ключем payload'а.

⚖️ **Чому інваріант лишається «сильним» (присуд 2026-08-13):** валідація на кожному `save` означає, що запис, який утратив фото через вкладений `photos#destroy`, стає неоновлюваним, доки докази не повернуть. Це виміряна, а не теоретична поведінка, тож послаблення до `on: :create` було відхилено — воно зняло б працюючий захист заради двох системних писачів (дотично до `SEC.28`: `purge_later` незворотний і йде поза `Auditable`).

⚖️ **[SEC.28] Фотодоказ не має СТРОКУ зберігання — він має ГАРД (присуд founder 2026-08-19).** Форму взято з ратифікованої доктрини гаманця (`Wallet#guard_mrv_evidence!` — «грошові докази незнищенні, off-board = деактивація»), бо питання те саме, лише носій інший: фото запису, чия доказовість на них стоїть, не знищуються НІКОМУ, а виправлення робиться ДОДАВАННЯМ кадру. 🔴 **[E.20, 2026-08-24] Замок ШИРШИЙ за валідність, і саме тому в нього ВЛАСНИЙ предикат `evidence_locked?`:** для `biomass_extraction` кожен наступний save лишається валідним без фото (інакше Puro-тракт помер би), але доказ усе одно незнищенний — заявка вже пішла в ЗОВНІШНІЙ реєстр. Доти замок читав `evidence_backed?` і biomass не покривав, тож фото, обовʼязкове на вході заявки, знімалося наступним кліком. 🔴 **Підстава подвійна, і обидві половини виміряні.** (1) `purge_later` запис НЕ зберігає, тож зняте останнє фото лишало `repair`/`installation` назавжди невалідним — це рівно ⚖️-абзац вище, лише з боку незворотності. (2) `BlockchainBurningService#critical_unmaintained?` тим часом бачив ТОЙ САМИЙ рядок і далі гасив `PF_NO_MAINTENANCE` — тобто економічний ефект «обслуговування відбулося» ПЕРЕЖИВАВ знищення власного доказу, і напрямок шкоди тут недо-слешинг, а потерпілий — сама D-MRV-заява. ⊕ **Дім умови ОДИН** — `MaintenanceRecord#evidence_backed?` (не `system_generated` ∧ `repair`/`installation`), і читачів у неї ТРИ: валідація, гард контролера, кнопка `PhotoCard`. Мутація предиката червонить обидва боки одразу (гардові приклади + наявні валідаційні), тож тихо розійтись вони не можуть; без третього читача гард народив би кнопку, що веде в нікуди. ⚠️ **Ретеншен-політики це НЕ вводить, і межу названо явно:** питання «скільки зберігати доказ» дому в репо не має взагалі, а адреса, куди його доти слали, тримає лише GDPR-половину — тобто відкладання йшло в дім, що цієї половини не має. ⊥ Пропорційність гарда дає асиметрія: append-only доказових поверхонь у платформі чотири (`AuditLog` · `TelemetryLog` · L1-якір · Filecoin-пін), знищенна була ОДНА — і саме та, що несе ЛЮДСЬКИЙ, а не машинний доказ.

---

### `EthereumAnchor` — Аудит-Трейл L1 Anchoring

**Призначення:** Персистентний журнал щотижневих операцій фіналізації стану SilkenNet в Ethereum Mainnet. Зберігає `state_root`, `tx_hash`, компоненти для незалежної верифікації (BLOCKER-2, BLOCKER-6), а також `block_number`/`gas_used` **після підтвердження** ([ARCH.66] — поллер доводить `:sent`→`:confirmed`; до того обидва NULL).

**Ключові поля:**

| Поле | Тип | Опис |
|------|-----|------|
| `state_root` | string(64) | 64-char SHA-256 hex дайджест (`UNIQUE`) |
| `total_growth_points` | decimal(30,6) | **[ARCH.97]** Бали росту всіх гаманців (офчейн-леджер, НЕ монети). Шкала 6 = шкала джерела `wallets.balance` — інакше збережене значення округлювалось і `verify_state_root` не сходився САМ ІЗ СОБОЮ |
| `total_scc_supply` | decimal(30,6) | **[ARCH.97]** Чинний SCC-supply (Σmints − Σburns, One-Home `BlockchainTransaction.net_minted_supply`) — дзеркало on-chain `totalSupply()` |
| `total_sfc` | decimal(30,4) | Сума підтверджених SFC мінтингів на момент anchoring [E.53] |
| `active_tree_count` | integer | Кількість активних дерев в екосистемі на момент anchoring [E.54] |
| `chain_hash` | string | chain_hash останнього `AuditLog` на момент anchoring |
| `anchored_at` | datetime | UTC-timestamp включений у хеш |
| `tx_hash` | string(66) | Ethereum TX hash (`0x` + 64 hex chars, `UNIQUE WHERE NOT NULL`) |
| `block_number` | bigint | Номер блоку підтвердження |
| `gas_used` | bigint | Витрачений газ |
| `nonce` | bigint | EVM nonce broadcast'у — персиститься **перед** `transact` ([ARCH.66] companion: F2a same-nonce resume проти double-send; NULL доти, доки anchor не дійшов до broadcast) |
| `status` | integer | Enum: `pending(0) / sent(1) / confirmed(2) / failed(3) / manual_review(4)` [ARCH.66] |
| `error_message` | string(500) | Деталі помилки (якщо є) |
| `root_version` | integer | **[ARCH.12 Фаза 1а]** 0 = legacy flat SHA-256 commitment · 1 = Merkle-корінь; `verify_state_root` маршрутизується за версією (legacy-рядки верифікуються старою формулою назавжди) |
| `window_from` | timestamp | **[ARCH.12]** нижня межа вікна телеметрія-листя (= `window_to` попереднього confirmed v1-якоря, exclusive — вікна ланцюжаться без дір); NULL для legacy і для першого merkle-якоря (from-genesis вікно) |
| `window_to` | timestamp | **[ARCH.12]** верхня межа вікна (= `anchored_at − GRACE` на момент генерації, ПЕРСИСТОВАНА — історичні вікна не залежать від значення константи); presence-валідація при `root_version=1` |
| `leaf_count` | integer | **[ARCH.12]** кількість телеметрія-листя у вікні (без leaf0) — аудитор відрізняє «партицію дропнули» від «листя не було» |
| `subtree_roots` | jsonb | **[ARCH.12]** упорядкований tier2-масив: перший елемент = leaf0-агрегат `{kind: "aggregate", root: hex}` (**БЕЗ** ключа `cluster_id` — свідомо, щоб не колізити з NULL-cluster sentinel-групою), далі `{cluster_id: int\|null, root: hex}` за cluster_id asc (null-sentinel остання). `verify_state_root` самодостатній O(#кластерів) і переживає ретеншн-дроп партицій; фіксує групування-як-було (cluster_id мутабельний) |

**Enum `status`** (prefix: true)**:**

| Значення | Int | Опис |
|----------|-----|------|
| `pending` | 0 | State root обчислено, TX ще не відправлена |
| `sent` | 1 | TX відправлена в мемпул, поллер опитує receipt [ARCH.66] |
| `confirmed` | 2 | TX підтверджена в L1 блоці (reorg-depth пройдено; `block_number`/`gas_used` заповнені) |
| `failed` | 3 | storeStateRoot revert on-chain, або guard відправлення (balance) |
| `manual_review` | 4 | [ARCH.66] broadcast, доля невідома після poll-SLA — людська звірка (виходить з `in_flight`) |

**Валідації:**
- `state_root` — presence, uniqueness, format `/\A[a-f0-9]{64}\z/`
- `tx_hash` — uniqueness, format `/\A0x[a-fA-F0-9]{64}\z/` (when present); presence required for `sent`/`confirmed`
- `total_growth_points` — presence, `>= 0`
- `total_scc_supply` — presence, `>= 0`
- `chain_hash`, `anchored_at` — presence

**Scopes:** `recent`, `successful` (confirmed), `latest_confirmed`, `stuck_sent` [ARCH.66] (`:sent` AND `updated_at < STUCK_SENT_THRESHOLD`=6год — One-Home предикат для reconcile-sweeper + gauge).

**Методи:**
- `verify_state_root` — незалежно відтворює хеш з `total_growth_points|total_sfc|active_tree_count|chain_hash|anchored_at.iso8601|total_scc_supply` та порівнює з `state_root` (для зовнішнього аудитора; працює на будь-якому статусі — компоненти заповнюються ще при `:pending`)
- `etherscan_url` — рендерить лінк через `Web3::Explorer` (`:ethereum`-родина) або `nil` без `tx_hash`. 🔴 **Хост залежить від ОГОЛОШЕНОЇ родини чейну слоту** (`WEB3_CHAIN_ENV` — [`04_02 §8`](04_02_Business_Logic_and_Services)): `etherscan.io` на mainnet, `sepolia.etherscan.io` на testnet [INF.27]. Доти був зашитий у mainnet, і ціна цього не косметична — саме цей лінк їде АУДИТОРОВІ як референс якоря в `Mrv::LineageReportService`, тож на testnet-слоті «transaction not found» читалось би як «якоря не існує», а не як «не той чейн»
- `confirm!(block_number, gas_used)` / `mark_failed!(reason)` / `escalate_to_review!(reason)` [ARCH.66] — гардовані переходи (`with_lock`, idempotent, plain enum): `confirm!`/`mark_failed!` з `:sent` **або** `:manual_review` (останнє = гардований операторський вихід із manual_review після etherscan-звірки, без raw `update_column`); `escalate!` лише з `:sent`

**Використовується:** `Ethereum::StateAnchorService#anchor_to_l1!` (записує до TX), `EthereumAnchorWorker`, `EthereumAnchorConfirmationWorker` (confirm/fail/escalate), `StuckSentAnchorSweeperWorker` (re-arm) [ARCH.66].

---

### `SystemParameter` — Governance-Aware Протокольні Константи

**Призначення:** Реєстр протокольних параметрів, які можуть оновлюватися через DAO governance (on-chain `ProtocolParameters.sol` → `Governance::ParameterSyncWorker`) або адмін-панель. Забезпечує кешовані lookups з fallback на default значення.

> ⚡ **ІНВАРІАНТ ДОСТАВКИ [ARCH.104, 2026-08-19]: засіяний ключ мусить мати канал, яким його значення доходить до поведінки** — або його читає код (`SystemParameter.current(:key)`), або він стоїть у `Governance::ParameterSyncWorker::PARAMETER_MAP` і його виставляє DAO. Правило не нове: `db/seeds.rb` оголошував його для Lorenz-ключів («запис, якого жоден споживач не читає, був би пасткою»), просто застосовувалось воно до однієї гілки — а вісім сусідніх рядків його порушували.
>
> 🔴 **Чому клас дожив: гейт над цією парою ІСНУВАВ і був зелений ЗА ПОБУДОВОЮ.** `GOV.3` звіряє `db/seeds.rb` ⟷ `PARAMETER_MAP`, але лише МЕЖІ ключів, які в мапі Є — рядок ПОЗА мапою для нього не існує взагалі. Тобто він чесно відповідає на «чи узгоджені спільні ключі», а читається як «сіди звірені»: перевірка ІСНУВАННЯ там, де дефект у ПОКРИТТІ. Вісь покриття тепер тримає окремий носій — `spec/quality/system_parameter_delivery_spec.rb`; він `GOV.3` не дублює.
>
> ⚠️ **Периметр міряй ПРОГОНОМ, не переліком:** трекер називав пʼять ключів, вимірювач знайшов **вісім** — три хардверні (`vcap_*`, `low_power_mv`) були залишком шкали заряду, знятої ARCH.99, і в жодному переліку не стояли. Знято всі вісім; підстава кожного — вже ратифікований присуд (ARCH.99 · ARCH.102 · заборона рантайм-порога DCI в [`00_03`](00_03_TRL_Matrix_HIL_and_Beyond)), а для трійки пожежних додатково те, що `FRP`/`confidence` виносять `satellite_status`, тобто ДОКАЗ для страхової виплати: DAO-рухомий поріг доказу був би важелем на сам доказ, а не governance-ручкою.
>
> ⚠️ Стеля носія названа: читачі беруться ЛІТЕРАЛАМИ, тож єдиний динамічний споживач (`Treasury::MonitorService` — ключ із мапи гаманців) оголошений у гейті поіменно; другий такий споживач треба оголосити так само.

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
- `SystemParameter.set("lorenz_sigma", "12.0", updated_by: admin, source: "governance")` — оновлення з аудит-трейлом: окрім row-колонок (`updated_by`/`source`), **[ARCH.57]** value-мутація (`after_update_commit if: :saved_change_to_value?`, концерн `Auditable`) пише tamper-evident рядок `system_parameter_changed` у **глобальний (org=nil) hash-ланцюг** AuditLog; bootstrap-create (seeds) свідомо не аудитується

**Валідації:**
- `key` — presence, uniqueness, format `/\A[a-z][a-z0-9_]*\z/`
- `value` — presence
- `value_type` — presence, inclusion
- `category`, `source` — presence, inclusion
- `value_within_bounds` — custom validation при наявності `min_value`/`max_value`

**Кешування:** `after_commit :invalidate_cache`. Ключ: `"system_parameter:#{key}"`. TTL: 24 години.

**Використовується (GOV.1 read-path):** `TokenomicsEvaluatorWorker.emission_threshold` (курс конверсії; One-Home для `EvaluateTreeBatchWorker`/`OracleVisionsController`), `ContractHealthCheckService` (`slash_threshold`-частка) + `AiInsight.slash_stress_threshold` (спільний slash/damage-поріг, ARCH.46), `BlockchainBurningService` (`slash_gamma`/`slash_penalty_factor_max`), `BlockchainMintingService` (`dynamic_tax_rate`, `insurance_pool_threshold`), `Governance::ParameterSyncWorker` (sync on-chain → DB, bounds-clamp). ⚠️ `SilkenNet::Attractor` свідомо НЕ читає (Lorenz = DCI-locked константи, FW.7 — [`05_06 §7`](05_06_Governance_and_DAO)).

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
| `device_uid` | string | Wire-ідентифікатор пристрою, що провіжиниться (presence): Tree → деривований DID (rake приймає 24-hex UID і сам деривує, [FW.54]); Gateway → uid |
| `batch_id` | string | Ідентифікатор партії (presence) |
| `gilka` | string | Гілка провіжинингу: `"A"` (Protected Flash + RDP) / `"B"` (Secure Element; `se_serial_hex` обов'язковий) — `GILKAS = %w[A B]` |
| `rdp_level` | integer | Рівень RDP після flash — `RDP_LEVELS = [0, 1, 2]` |
| `se_serial_hex` | string | 18 HEX (9-байт SE serial); presence лише для гілки B, format `/\A[0-9A-F]{18}\z/` |
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

**Валідації:** `supervisor_must_differ_from_operator` (2-Person Rule); `gilka` inclusion `[A,B]`; `rdp_level` inclusion `[0,1,2]`; `se_serial_hex` format (18 HEX).

> Service-шар (orchestrator `FactoryFlashing::Session` + `MasterKeySource`/`CommandBuilder`/`Executor`/`SecureElementProvisioner`/`AuditTrail`, Rake CLI) — канон [`03_06 §5`](03_06_Factory_Flashing_and_Key_Provisioning); дзеркало у [`04_02`](04_02_Business_Logic_and_Services).

---

## 🌱 8. Seeds — Початковий Стан Системи

Порядок видалення при очищенні (від листя до кореня):

```
AuditLog, Session, EthereumAnchor
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
- `oracle.executioner@system.silkennet.com` — super_admin, системний бот (без org)
- `admin@silkennet.com` — super_admin, Архітектор платформи
- `alexey@activebridge.org` — admin, ActiveBridge (access_level :organization)
- `forester@activebridge.org` — forester (access_level :field)
- `subscriber@ecofuture.fund` — subscriber (access_level :read_only)

**Початковий Cluster:** "Черкаський бір" — `region: "Центральна Україна"`, timezone: `Europe/Kyiv`, fire threshold: 60°C.

**Governance-параметри:**

Мусять сідатись **окремою idempotent rake-таскою** (НЕ через `db/seeds.rb`, бо той на слоті `production` fail-closed). Носій виклику з 2026-09-03 — `.kamal/hooks/post-deploy`: після КОЖНОГО `kamal deploy` (обидва слоти) він запускає в одноразовому контейнері `web`-ролі композицію продового bootstrap ([`00_07`](00_07_Action_Plan_Tracker) OPS.38):

```bash
bin/rails governance:bootstrap        # oracle_executioner (money-audit актор; без нього record_money_audit_trail
                                      # мовчки не пише НІЧОГО) + governance:seed_parameters + ОДНА TreeFamily
                                      # (*Pinus sylvestris*; числа оголошено провізорними в самому рядку — ⚖️ 2026-09-03 OPS.38)
bin/rails governance:seed_parameters  # лише UPSERT dynamic_tax_rate + insurance_pool_threshold
```

Обидві таски ідемпотентні (повторний запуск не дублює, актора не чіпає, DAO-промотовані поля зберігає); `web`-роль обрано, бо її несе кожен деплой і вона не несе жодного підписного ключа — одноразовий runner ніколи не бутиться підписантом.

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
  │     ├── Trees (restrict_with_error)
  │     │     ├── Wallet (destroy)
  │     │     ├── HardwareKey (destroy)
  │     │     ├── DeviceCalibration (destroy)
  │     │     ├── TelemetryLogs (delete_all) ← PARTITION
  │     │     ├── EwsAlerts (delete_all)
  │     │     ├── MaintenanceRecords (delete_all)
  │     │     └── AiInsights polymorphic (delete_all)
  │     ├── Gateways (restrict_with_error)
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
  │     └── BlockchainTransactions (nullify [ARCH.57]) ← PARTITION
  └── AuditLogs (restrict_with_error) ← журнал переживає Org [ARCH.57]

User
  ├── Sessions (destroy)
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
```

> 🧱 **Чому діти кластера — `restrict_with_error`, а не `nullify`: `clusters.id` не є ідентифікатором рядка, він є ФАБРИЧНО-ЗАМОРОЖЕНОЮ КООРДИНАТОЮ ЮНІТА** (⚖️ 2026-07-30, [ARCH.76]/[SEC.26]). Він одночасно HKDF-salt прошитих `K_ota`/`KEYB` — незмінних після RDP-lock, бо в salt немає епохи, тож «ротація кластерного ключа» без зміни master неможлива В ПРИНЦИПІ — **і** координата історичних MRV-груп (`telemetry_subtree_roots` групує по ПОТОЧНОМУ `trees.cluster_id`). Отже головний потерпілий від знищення рядка — не дерева, а **пруф і ключ**: занулення стирає реєстр salt-значення й робить `unprovable` усі минулі якорі групи. ⚠️ Аналогія «як на `maintenance_records`» тут НЕ працює: усі наявні `restrict_with_error` захищають ДОКАЗИ (контракти · журнали · історія ремонтів), жоден не захищає сам фізичний АКТИВ — це перший.
>
> ⛔ **Наслідок, який знімає найприроднішу майбутню пропозицію: «перемістити дерево в інший кластер» НЕ ІСНУЄ як software-операція і не може існувати.** Ключі лежать у флеші, після RDP-L2 SWD мертвий, анкер упресований у ксилему — тож обидва кінці вже канонізовані окремо: `decommission!` старого юніта ⊕ factory-provision нового з новим DID. Єдина життєздатна форма «переносу» — кластер ЦІЛКОМ між організаціями (паперова: `organization_id` + ресинк денормалізованого `wallets.organization_id` + новація контрактів), і вона `destroy` не потребує, тобто `restrict` її не блокує. **Не проєктуй tree-transfer: він не відкладений, він неможливий.**
>
> ⛔ **І дзеркальна пропозиція, теж зважена: чотири «роботи» кластера — тенансі · контракт · крипто-домен · MRV-група — НЕ чотири сутності.** Це чотири проєкції ОДНІЄЇ координати в різні моменти часу (зараз / строк дії / фабрика / момент якоря). Розщеплювати не треба: фізика тримає їх злитими, а операцій розриву не існує.

---

## 🏗️ 11. Архітектурні Принципи БД

| Принцип | Реалізація |
|---------|-----------|
| **Hot Path без валідацій** | `TelemetryLog`, `GatewayTelemetryLog` — валідації в сервісі, не в AR |
| **Денормалізація для N+1 Kill** | `latest_stress_index`, `latest_voltage_mv`, `active_trees_count`, `health_index`, `entropy_score` |
| **GREATEST для race conditions** | `mark_seen!` в Tree та Gateway — атомарне оновлення без дублів |
| **delete_all для масових таблиць** | Телеметрія, тривоги, логи, ActuatorCommands — уникнення OOM при DELETE |
| **restrict_with_error для фінансів** | NaasContract, ParametricInsurance, Users — захист аудит-слідів |
| **Партиціонування по місяцях** | telemetry_logs, gateway_telemetry_logs, blockchain_transactions — **прунінг ЗАПИТІВ** (планувальник пропускає непотрібні листи). SSOT — `PartitionMaintenanceWorker::PARTITIONED_TABLES` (3 таблиці). ⚠️ Тут доти стояло «прунінг старих даних» — це інша спроможність, і її НЕМА: `DETACH`/`DROP PARTITION` у репо нуль, воркер партиції лише СТВОРЮЄ, retention-політики не існує ([`05_04`](05_04_Ethereum_L1_State_Anchor) це визнає). Тобто листів стає +1 щомісяця назавжди. ⚠️ **Ключ прунінгу парситься `Time.zone.iso8601`, ніколи голим `Time.iso8601`** [ARCH.92]: другий читає зону ПРОЦЕСУ, тож рядок без суфікса зсуває СЕКУНДНЕ вікно на UTC-офсет хоста — і промах тут не сповільнює, а віддає порожньо (`first!` → `RecordNotFound` повз наявний `rescue`). Обидва хелпери додатково вимагають, щоб рядок НІС ЧАС: `Time.zone.iso8601` приймає голу дату як північ, і без гарда це дало б вікно навколо 00:00:00 замість чесного fallback'у. Механізм і посайтові присуди → [`04_03 §1.3б`](04_03_REST_API_v1_Reference) |
| **Counter Cache** | `active_trees_count` в Cluster — уникнення COUNT на мільйонах рядків |
| **Поліморфізм** | AiInsight, MaintenanceRecord, AuditLog, BlockchainTransaction |
| **PostGIS GIST** | Cluster.geo_boundary — O(log n) геопросторовий пошук |
| **AR Encryption + In-Process LRU Cache** | HardwareKey.aes_key_hex — шифрування в БД + `cached_binary_key` у in-process LRU (SinLruRedux, max 10 000 entries). Ключі не залишають Ruby-процес (Zero Network Exposure) |
| **BigDecimal в JSONB** | TinyMlModel accuracy_score/threshold — уникнення Float похибок |
| **Partial Index для sparse поля** | `blockchain_transactions.tx_hash WHERE tx_hash IS NOT NULL` — виключає рядки без tx_hash (pending/processing) |
| **Вкладення декларує МЕЖІ** [SEC.27] | Кожне наше Active-Storage-вкладення оголошує `content_type` + `size`, а колекційне (`has_many_attached`) — ще й `limit`. 🔴 Дефект тут — **відсутність рядка**, тож ані греп, ані ревʼю його не бачать: голий `has_one_attached` читається як завершений код, доки хтось не покладе у сховище довільний блоб. Носій — `spec/quality/attachment_validation_discipline_spec.rb`: множину бере з рантайму (`attachment_reflections`), тож нове вкладення входить у периметр самим фактом оголошення; периметр — `app/models` (фреймворкові вкладення ActionText/ActiveStorage/ActionMailbox свідомо поза ним). ⚠️ Гейт судить НАЯВНІСТЬ валідатора, ніколи його ЗМІСТ — доречність allow-list лишається на ревʼю |

---

### PII-реєстр — які колонки несуть персональні дані [SEC.18]

🔴 **Навіщо реєстр, коли колонки й так описані в таблицях моделей вище.** Три різні
обовʼязки читають ОДИН перелік і доти виводили його кожен по-своєму: RoPA Art.30
(реєстр processing-активностей), DSAR-експорт Art.15/20 (що саме віддати субʼєкту)
і retention-TTL (для чого взагалі потрібен строк). Розсипаний по тридцяти таблицях,
цей перелік не має способу бути ПОВНИМ — і саме повнота тут є вимогою, а не
охайністю.

⚠️ **Класифікація — ДЕКЛАРАЦІЯ ЛЮДИНИ, не вивід регексу.** Механічний свіп по іменах
колонок дає 16 таблиць і серед них хибні позитиви: `maintenance_records.biomass_passport_tx_hash`
збігається на слові «passport», а це TX-хеш Puro.earth. Тому кожен рядок нижче
несе ПІДСТАВУ, а гейт судить наявність рядка, ніколи його правильність.

| Таблиця · колонки | Клас | Підстава й наслідок |
|---|---|---|
| `users` — `email_address` · `first_name` · `last_name` · `telegram_chat_id` · `push_token` | **PII (ядро)** | Прямі ідентифікатори живої людини. Усі скрабляться з логів (`filter_parameters`); `recovery_codes` і `password_digest` — креденшели, не PII, але видаляються тим самим ходом |
| `sessions` — `ip_address` · `user_agent` | **PII (слід входу)** | Обидва `validates presence`, тобто заповнені ЗАВЖДИ. Стирання сесій — найдешевша половина erasure: таблиця не append-only |
| `audit_logs` — `ip_address` · `user_agent` · `user_id` | 🔴 **PII в APPEND-ONLY** | Ядро напруги з [`ARCH.57`](00_07_Action_Plan_Tracker): ланцюг tamper-evident, тож рядок не видаляють — erasure тут можлива лише ПСЕВДОНІМІЗАЦІЄЮ поля при збереженні хеш-ланцюга. Це ⚖️-половина erasure ([`00_07`](00_07_Action_Plan_Tracker) SEC.18): `Gdpr::AnonymizeUserService` (безсуперечна половина — users-tombstone + sessions destroy, слід у ланцюг ДО мутацій) ці рядки свідомо НЕ чіпає, і його спека пінить, що ланцюг переживає анонімізацію цілим |
| `organizations` — `billing_email` | **PII (умовно)** | Для ФОП/одноосібного власника платіжна адреса Є персональними даними; для ТОВ — ні. Клас залежить від контрагента, тож поле трактується як PII за замовчуванням |
| `gateways` — `ip_address` | **Межовий: пристрій** | Спостережений CGNAT/Starlink-egress ШЛЮЗА, не людини (§3). Лінкується з оператором ділянки опосередковано, тож не PII-ядро, але й не «нічого» — потрапляє в RoPA як дані пристрою |
| `wallets` · `organizations` — `crypto_public_address` · `solana_public_address`; `blockchain_transactions.to_address` | **Псевдонімні** | Адреси публічного ланцюга. `wallets.tree_id` — `NOT NULL`, тож гаманець завжди належить ДЕРЕВУ, не людині ([`03_04 §6.3`](03_04_mruby_Lorenz_Attractor) — «у дерев немає GDPR-даних»). ⚠️ **Стане PII, щойно бенефіціаром стане ФІЗОСОБА** — адреса отримувача-людини вже персональна. 🔴 Тригер тут переписано 2026-08-28: доти він казав «коли зʼявиться виплата рейнджеру ([`E.20`](00_07_Action_Plan_Tracker))», а той пункт після ⚖️ 2026-08-24 перелицьовано на фізичного виконавця (атестатор — акаунт У організації власника, платить власник), тобто виплат фізособам його тіло не несе, і адреса тихо спорожніла. **Чинна форма — ПОДІЯ, не пункт:** перша прив'язка гаманця до адреси, чий держатель є фізособою, або перша виплата такому бенефіціару ([`dpia_art35.md`](protocols/legal/dpia_art35.md) §3.4 + захід M9). ⚠️ Сьогодні продуктової поверхні прив'язки власної адреси до `Wallet` НЕМАЄ (нуль писачів поза сідом і специми), тож спостерігати треба **появу писача**, а не рядок у даних |
| `maintenance_records` — `biomass_passport_tx_hash` · `biomass_passport_status` | **НЕ PII** | Хибний позитив свіпу по імені («passport» = документ ОСОБИ в патерні): TX-хеш паспорта біомаси Puro.earth та його lifecycle-стан [PERF.1(д)] — обидва про мертву деревину, не про людину |
| ActiveStorage-блоби `maintenance_records.photos` — **EXIF усередині файла** (GPS · timestamp · модель телефона) | 🔴 **PII поза колонками** | Смартфонний кадр везе координати й час ТЕХНІКА в самому JPEG — поверхня, якої не бачить жоден колонковий свіп. ⚖️ [SEC.18, 2026-08-20]: **стрип із ПОКАЗУ, оригінал ТРИМАЄМО** — variant `:thumb` (єдина поверхня показу глядачам) іде `saver: { strip: true }`, оригінал лишається незачепленим свідомо: EXIF-геотег є потенційним незалежним доказом «технік був на місці» (Anti-Sofa-Repair, ⚖️ [`00_07`](00_07_Action_Plan_Tracker) UI.7), і глобальний стрип знищив би його незворотно. Носій обох половин — `spec/models/maintenance_record_photos_exif_spec.rb` (mutation-verified: знятий strip червонить variant-половину). 🔴 **Два НАСЛІДКИ, що з цього ⚖️ природно виводяться, кодом СПРОСТОВАНІ — сам присуд стоїть, падають саме вони.** (а) Erasure блоб **НЕ чіпає**: `Gdpr::AnonymizeUserService` свідомо не торкається `maintenance_records` (Evidence Protocol `guard_evidence_purge!` тримає фото `repair`/`installation` незнищенними — його власний докблок називає це стелею й ⚖️), тож EXIF-геотег техніка **переживає його власне стирання**, а не помирає з блобом. (б) DSAR-експорт віддає **лише метадані запису** (`filename`/`byte_size`/`content_type`/`created_at` — `Gdpr::DataExportService`), не байти й не EXIF. Обидва факти вже правильно названі в [`dpia_art35.md`](protocols/legal/dpia_art35.md) R2 («оригінали, які неможливо видалити», захід M7) — тобто розходився саме цей реєстр, і в бік, що ЗАВИЩУЄ нашу відповідність. Напруга «доказ ⊥ erasure» тут — та сама ⚖️, що для `audit_logs` вище, лише на ДРУГІЙ поверхні ([`00_07`](00_07_Action_Plan_Tracker) SEC.18) |

| `trees` — `latitude` · `longitude`; `clusters` — `geojson_polygon` (→ похідна `geo_boundary`) | 🔴 **PII через ПЕРЕ-ІДЕНТИФІКАЦІЮ (quasi-identifier)** | Самі по собі це координати ДЕРЕВА, не людини — і саме тому клас довго читався як «не PII». Але гранулярна геометрія ділянки × **публічний кадастр** дає власника: smart-meter-клас, де неособові виміри стають особовими через зовнішній довідник. Наш власний research рахує тут **щонайменше три критерії EDPB WP248** (location data · systematic monitoring · innovative tech) при порозі «2+ = DPIA required», тобто це high-risk processing, і DPIA потрібен **ДО** обробки, а не заднім числом ([`b2b_readiness.md`](protocols/business/b2b_readiness.md) §2.2). ✅ DPIA написано 2026-08-21 — [`dpia_art35.md`](protocols/legal/dpia_art35.md), де ця пара є ризиком R1; ⚠️ технічної мітигації (огрублення) в коді НЕМАЄ, і DPIA кваліфікує це як питання Art.5(1)(c), не як покращення. ⚠️ **Пара невидима носію ДВІЧІ, кожен раз іншою стелею:** `latitude`/`longitude` немає в PII-патерні (стеля 2 — «патерн ловить ІМЕНА»), а `geojson_polygon` це JSONB (стеля 1), і `geo_boundary` ще й `GENERATED ALWAYS AS`. Тому рядок тут — ЄДИНИЙ спосіб, у який ці колонки взагалі потрапляють у три обовʼязки; стан → [`00_07`](00_07_Action_Plan_Tracker) SEC.18 |

**Виконавча форма реєстру [SEC.18]:** DSAR-експорт = `Gdpr::DataExportService` (User-owned вісь; креденшели свідомо поза віддачею — докблок) + self-service `GET /account_security/data_export`; erasure = `Gdpr::AnonymizeUserService` + self-service `DELETE /account_security/erase` (⚖️ 2026-08-21, step-up на пароль). ⚠️ Двері **асиметричні навмисно**: експорт ідемпотентний і відкритий кожному, стирання незворотне, тож його гард **fail-CLOSED** — акаунт без `password_digest` дістає 422, а не пропуск, і для нього лишається лише операторський шлях ([`04_02 §5`](04_02_Business_Logic_and_Services)). Парність зі СХЕМОЮ тримають два гейти з одним іменним патерном: `pii_register_spec` (схема↔цей реєстр) і schema-parity приклад у `spec/services/gdpr/data_export_service_spec.rb` (схема↔віддача) — нова PII-колонка `users` червонить обидва, доки не дістане і рядка, і рішення про експорт.

🔒 **Чого цей реєстр НЕ вирішує:** строки зберігання (⚖️ per-юрисдикція,
[`00_07`](00_07_Action_Plan_Tracker) SEC.18) і законну підставу обробки — вони належать
RoPA й політиці, не схемі. Тут лише ВІДПОВІДЬ НА «що саме ми тримаємо».

✅ **Носій — `spec/quality/pii_register_spec.rb`:** кожна колонка, що збігається з
PII-патерном у `db/structure.sql`, мусить бути КЛАСИФІКОВАНА тут. Нова колонка з
іменем `*_email`/`*_phone`/`ip_address`/… не проходить мовчки — і саме мовчазний
прохід є тут дефектом, бо повнота реєстру і є його змістом.

🔒 **Друга стеля тієї самої таблиці — ВМІСТ `audit_logs.metadata` [SEC.18, DPIA захід M6
проти ризику R7].** Реєстр вище класифікує КОЛОНКИ, а `metadata` — JSONB, тож його вміст
лежить поза периметром `pii_register_spec` **за побудовою** (та сама «стеля 1», якою вище
ховається `geojson_polygon`). Ціна тут максимальна саме через незворотність: money/MRV-лог
їде в **публічний пін** (`Filecoin::ArchiveService` → IPFS/Filecoin), і персональне поле,
одного разу запінене, не стирається фізично — жодним DSAR і жодною анонімізацією. Носій —
`AuditLog::ARCHIVED_METADATA_KEYS` (оголошений перелік ключів) + відмова на межі піна
(`UndeclaredMetadataError`); перелік ведеться тим самим способом, що й реєстр вище —
ДЕКЛАРАЦІЄЮ людини, не виводом регексу. ⚠️ **Судяться КЛЮЧІ, ніколи ЗНАЧЕННЯ** — і саме тому
єдиний ключ, що ніс ВІЛЬНИЙ текст, звужено окремо: ✅ **`error` тепер несе КОД**
(`Web3::TransactionErrorClassifier`, ⚖️ 2026-08-27), бо `error_message` заповнюється
`e.message` довільного винятку — чужим RPC-тілом, URL, текстом Kredis. **Форму обрано за
напрямком дефолту на НЕЗВОРОТНІЙ поверхні:** `truncate` ріже довжину, не природу; redaction
за патернами **fail-OPEN за побудовою** (що не збіглося — те їде); класифікація єдина
**fail-CLOSED** — невідоме стає `:unknown` і не виносить жодного байта. 🔴 Звужено на
**ПИСАЧІ**, не на межі піна: пін мусить бути ВІРНОЮ копією аудит-рядка, інакше аудитор,
звіряючи його з БД, бачив би розбіжність — і пін перестав би бути доказом. Повний текст
лишається в `blockchain_transactions.error_message` під retention/erasure, тобто діагностику
переадресовано, не втрачено. ⛔ **Другий канал того ж класу лишається поза периметром цього
переліку ЗА ПОБУДОВОЮ** — `telemetry_summary` їде в той самий пін і **не є** `metadata`,
тож `ARCHIVED_METADATA_KEYS` його не судить і судити не може. ✅ **Канал закрито 2026-08-27
іншим ліком, і різниця між двома ліками несуча:** `AiInsight#summary` із піна **знято
зовсім**, бо він інтерполював `cluster.name` — вільний рядок ЛЮДИНИ. `error` є ЄДИНИМ
джерелом свого факту, тому його звужують до коду; `summary` джерелом не був — решта
рядка вже несе величини, з яких він рендериться, — тому дешевше зняти поверхню, ніж
класифікувати вміст (У-ВЕЙ: важке зробити непотрібним). Єдину магнітуду, що жила лише
в реченні, піднято в структуру (`reasoning.fraud_trees`, картка `AiInsight` §7).
⚠️ `telemetry_summary` не входить у `CONTENT_DIGEST_KEYS`, тож зміна форми блоку не
зсуває жодного вже виданого `content_cid` — свідок E.60 цілий. ⛔ Периметр вужчий за таблицю: `Auditable`
дефолтить `archive: false`, тобто security/ops-метадані на публічний IPFS не йдуть узагалі
(INF.22 over-exposure) — і саме тому фікстура, що архівує `update_settings`-лог, описувала
сценарій, якого канон не дозволяє.


## 🧭 12. SSOT Drift Register (Doc ↔ Schema Sync)

> **Принцип:** `db/structure.sql` після `db:migrate` — authoritative reality схеми; 04_01 — її SSOT-опис. Загальний метод drift-resolution (schema-ahead → онови док; doc-ahead → задача в [`00_07`](00_07_Action_Plan_Tracker); не «допишу до 04_01 потім») — [`00_06`](00_06_SSOT_Documentation_Standard) + скіл `ssot-maintenance`. Дзеркало для service-шару (сервіси/воркери/ENV, інший скоуп) — [`04_02 §13b`](04_02_Business_Logic_and_Services).

**Механічні інваріанти — ✅ enforced by `scripts/model_doc_sync.rb`** (CI `docs.yml` тригериться і на `docs/`, і на `app/models/**`, тож дрейф ловиться з обох боків; локально — `ruby scripts/model_doc_sync.rb`):

1. Model-файли (`app/models/**`, мінус `application_record` / `concerns/`) ⟷ код-спан-заголовки `### Model` у §2..§7 — рівно 1:1.
2. Concern-файли (`app/models/concerns/`) ⟷ код-спан-заголовки `### Concern` у §1.
3. `PartitionMaintenanceWorker::PARTITIONED_TABLES` ⟷ згадки таблиць у §0 + §11.

> Раніше це був ручний «drift register» з датованим логом виправлень — він мовчки протух (заявляв 35 моделей при 36 файлах), тож логіку винесено у скрипт-гейт; історія виправлень живе в git.

🔴 **Четвертий інваріант має ІНШУ природу — його не можна загейтити, і це не пропуск, а властивість предмета** (OPS.27). Дамп схеми ПРИБИРАЄ рядки так само легко, як додає, і **легітимне видалення колонки статично не відрізнити від дрейфу dev-БД**: обидва дають валідний `structure.sql`, який спокійно комітиться, а зникнення виявляється вже як відсутня поведінка. Тому носій тут не гейт, а **показ**: `db:schema:dump` сам друкує прибрані рядки (`lib/tasks/migration_hygiene.rake`), щойно їх стає ≥3 — поріг узято з виміру, бо нормальний дамп прибирає один-два (сам блок `schema_migrations`), тоді як реальні події давали десятки й сотні. Він нічого не забороняє й не має права падати; його робота — зробити зникнення видимим у мить, коли воно стається, а не через тиждень.

**Решта (ручний семантичний аудит, [`00_06 §3а`](00_06_SSOT_Documentation_Standard), поки не автоматизовано):** кожна `include AASM`-модель має state-перелік у своєму §; поліморфні `_type/_id` пари §10 «Карта Зв'язків» ⟷ реальні колонки `structure.sql`.

> **Поза скоупом (за дизайном, не drift):** Active Storage (`active_storage_*`), `schema_migrations` / `ar_internal_metadata` — framework-інфра; документується inline-згадками у моделях (`Organization.logo`, `MaintenanceRecord.photos`), не як окремі сутності.