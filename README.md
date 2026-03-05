# 🌿 Silken Net: Цифрова Екосистема Черкаського Бору

**Silken Net** — це титанова D-MRV (Digital Measurement, Reporting, and Verification) платформа, що об'єднує біологічний гомеостаз лісу, IoT-периферію на базі STM32 та децентралізовані фінанси в мережі Polygon.

Це "Океан", який дихає в унісон із ксилемним соком кожного "Солдата" (дерева) та кожної "Королеви" (шлюзу).

---

## 🏛️ Архітектура "Титанового Моноліту"

Система побудована за принципом **Zero-Trust** та **Нульового Лагу**, використовуючи стек **Rails 8.1 Omakase**.

Всі HTTP-маршрути версіоновані та доступні під простором `api/v1`.

### 🧬 API Контролери (`api/v1`)

| Контролер | Призначення |
|---|---|
| **Sessions** | Брама входу та керування токенами доступу |
| **Dashboard** | Центральний вівтар — зведена панель стану системи |
| **Clusters** | Гео-просторові сектори лісу (GeoJSON) |
| **Trees** | Шеренга Солдатів — імпеданс, DID, заряд іоністора |
| **TreeFamilies** | ДНК-реєстр біологічних видів та порогів Атрактора |
| **Gateways** | Шлюзи-Королеви — моніторинг LoRa-вузлів та Starlink |
| **Telemetry** | Пульс істини — historical дані та live-потік |
| **Alerts** | Нервова система — EWS-реагування (пожежі, засухи, вандалізм) |
| **Maintenance** | Журнал зцілення — Proof of Care у полі |
| **Provisioning** | Ритуал ініціації — прив'язка STM32 UID до DID |
| **Firmwares** | Еволюція — управління прошивками та OTA-деплой |
| **Actuators** | Руки Оракула — пряме керування клапанами та сиренами |
| **OracleVisions** | Прекогніція — AI-прогнози на основі Атрактора Лоренца |
| **Contracts** | Економічний купол NaaS (Nature-as-a-Service) |
| **Wallets** | Скарбниця — токен-баланси дерев та організацій |
| **BlockchainTransactions** | Блокчейн-леджер — журнал on-chain операцій |
| **Organizations** | Управління кланами інвесторів |
| **Users** | Реєстр Патрульних та RBAC |
| **Notifications** | Налаштування оповіщень (SMS, Telegram) |
| **Reports** | Архів — Carbon Absorption & Financial Summary |
| **AuditLogs** | Спостерігач — повний журнал дій у системі |
| **SystemAudits** | Безпека та етика — цілісність системи |
| **SystemHealth** | Пульс системи — health-check бекенду |
| **Settings** | Карта мозку — системні налаштування |

### 🗂️ Моделі (The Living World)

* **Tree** (Солдат): вузол лісу з DID, іоністором, TinyML-моделлю та гаманцем.
* **Gateway** (Королева): LoRa-шлюз зі Starlink/LTE (SIM7070G), управляє батальйоном Солдатів.
* **Cluster**: гео-сектор лісу, об'єднує Дерева та Шлюзи.
* **TreeFamily**: ДНК-реєстр (порогові значення `critical_z_min/max` для Атрактора).
* **TelemetryLog / GatewayTelemetryLog**: сирі пакети телеметрії від Солдатів та Королев.
* **AiInsight**: денний вердикт Оракула (`stress_index`, `daily_health_summary`).
* **EwsAlert**: сигнал раннього попередження (пожежа, засуха, системний збій).
* **Actuator / ActuatorCommand**: виконавчі механізми та журнал команд.
* **NaasContract**: контракт NaaS з повним Slashing-протоколом (D-MRV Арбітраж).
* **ParametricInsurance**: параметрична страховка кластера.
* **Wallet / BlockchainTransaction**: фінансова мережа (SCC/SFC баланси).
* **Organization**: клан інвесторів із NaaS-контрактами.
* **User**: Патрульний із RBAC (`investor`, `forester`, `admin`, `super_admin`).
* **HardwareKey**: апаратний AES-256 ключ вузла (Zero-Trust).
* **DeviceCalibration**: калібровочні константи сенсора.
* **Identity**: OAuth2-ідентичність (Google/Apple).
* **Session**: токен доступу з прив'язкою до `password_salt`.
* **MaintenanceRecord**: Proof of Care (поліморфний — Tree або Gateway).
* **AuditLog**: повний журнал дій (поліморфний).

### 🧠 AI Оракул

Система використовує математичну модель Атрактора Лоренца для аналізу стабільності екосистеми (`SilkenNet::Attractor`):


$$\begin{cases} \dot{x} = \sigma(y - x) \\ \dot{y} = x(\rho - z) - y \\ \dot{z} = xy - \beta z \end{cases}$$


Де координата $z$ відповідає електричному імпедансу ксилеми. Параметри $\sigma$ та $\rho$ динамічно коригуються за акустичними та температурними даними сенсора. Відхилення від траєкторії гомеостазу (`critical_z_min`/`critical_z_max`) автоматично генерує `EwsAlert`.

Траєкторія розраховується з **BigDecimal** (18 знаків), що гарантує **крос-платформну детермінованість** та юридичну точність Web3-аудиту.

### ⚙️ Сервіси (The Intelligence Layer)

| Сервіс | Роль |
|---|---|
| `SilkenNet::Attractor` | Лоренц-атрактор — ядро AI-оракула |
| `InsightGeneratorService` | Генерація денних `AiInsight` та `EwsAlert` |
| `TelemetryUnpackerService` | Розпакування CoAP-пакетів від STM32 |
| `AlertDispatchService` | Маршрутизація тривог (SMS/Telegram) |
| `EmergencyResponseService` | Екстрений протокол реагування |
| `BlockchainMintingService` | Емісія SCC-токенів (Minting) |
| `BlockchainBurningService` | Slashing-протокол (Burning) |
| `ChainAuditService` | Аудит on-chain транзакцій |
| `HardwareKeyService` | Генерація та ротація AES-256 ключів |
| `OtaPackagerService` | Упаковка та шифрування OTA-пакетів прошивки |
| `PriceOracleService` | Ціновий оракул для токен-розрахунків |

### 🔄 Фонові Воркери (The Async Army)

| Воркер | Черга | Призначення |
|---|---|---|
| `UnpackTelemetryWorker` | `uplink` | Розпакування вхідних CoAP-пакетів |
| `GatewayTelemetryWorker` | `uplink` | Обробка телеметрії Королев |
| `AlertNotificationWorker` | `alerts` | Відправка SMS/Telegram тривог |
| `SingleNotificationWorker` | `alerts` | Одиночне сповіщення патрульного |
| `ActuatorCommandWorker` | `downlink` | Виконання команд актуаторам |
| `OtaTransmissionWorker` | `downlink` | OTA-передача прошивки на вузол |
| `ResetActuatorStateWorker` | `downlink` | Скидання стану актуатора після команди |
| `MintCarbonCoinWorker` | `web3` | Емісія SCC на Polygon |
| `BurnCarbonTokensWorker` | `critical` | Slashing-протокол (спалювання токенів) |
| `BlockchainConfirmationWorker` | `web3` | Підтвердження on-chain транзакцій |
| `TokenomicsEvaluatorWorker` | `default` | Щогодинна оцінка токеноміки |
| `ClusterHealthCheckWorker` | `default` | Нічний арбітраж NaaS-контрактів |
| `DailyAggregationWorker` | `low` | Стиснення телеметрії в AiInsight (01:00) |
| `EcosystemHealingWorker` | `default` | Автоматична корекція аномалій |
| `InsurancePayoutWorker` | `web3` | Виплата страхових компенсацій |

---

## 🛠️ Технологічний Стек (The Omakase Way)

* **Backend**: Ruby **4.0.1** / Rails **8.1.2**.
* **Database**: PostgreSQL + **Solid Cache** + **Solid Cable** + **Solid Queue**.
* **Background Jobs**: **Sidekiq** + **sidekiq-scheduler** (черги: `uplink`, `alerts`, `critical`, `downlink`, `default`, `web3`, `low`).
* **Frontend**: Hotwire (Turbo 8 / Stimulus), Tailwind CSS, **Phlex** (компонентна система).
* **Serialization**: **Blueprinter** (API JSON blueprints).
* **Pagination**: **Pagy** + **Groupdate** (time-series).
* **IoT Protocol**: CoAP / LoRaWAN (Sanctum Listener).
* **Blockchain**: Solidity / Polygon (ERC-20 Permit & Votes), **eth** gem.
* **Deployment**: **Kamal** (Docker-контейнеризація), **Thruster** (HTTP/2 proxy).

---

## 🔐 Апаратна Броня (Hardware & Provisioning)

Кожен вузол (STM32WLE5) захищений на рівні кремнію:

* **RDP Level 2**: Апаратне блокування зчитування пам'яті (Drifting Ice Mode).
* **AES-256**: Кожен пакет шифрується унікальним апаратним ключем (`HardwareKey`).
* **Shipping Mode**: Магнітний геркон утримує пристрій у глибокому сні до моменту монтажу. Перший "вдих" відбувається при відриві магніту в лісі.
* **OTA Updates**: Зашифровані пакети прошивки доставляються через `OtaPackagerService` → `OtaTransmissionWorker`.

Формат ідентифікаторів:
* **Солдат (Tree DID)**: `SNET-XXXXXXXX` (8 hex digits, STM32 uint32_t)
* **Королева (Gateway UID)**: `SNET-Q-XXXXXXXX`

---

## ⛓️ Токеноміка (Dual Token System)

1. **SCC (Silken Carbon Coin)**: Утилітарний токен. Нараховується автоматично за підтверджений ріст та поглинання $CO_2$. Підлягає **Slashing-протоколу** (спалюванню) у разі деградації кластера (поріг: >20% активних дерев з `stress_index ≥ 1.0`).
2. **SFC (Silken Forest Coin)**: Governance-токен. Надає право голосу в DAO та вплив на стратегію розвитку Черкаського бору. Підтримує безгазові транзакції (EIP-712).

Обидва контракти реалізовані на Solidity (`contracts/SilkenCarbonCoin.sol`, `contracts/SilkenForestCoin.sol`).

---

## 🚀 Швидкий Старт

### 1. Клонування та налаштування

```bash
git clone https://github.com/alexey-architect/silken-net.git
cd silken-net
bundle install
bin/rails db:prepare
```

### 2. Запуск Океану

```bash
# Запуск сервера, воркерів та CSS
bin/dev
```

### 3. Деплой (Kamal)

```bash
kamal setup
```

---

## 📚 Документація

Детальна документація знаходиться в директорії [`docs/`](docs/):

* [`API.md`](docs/API.md) — опис всіх API-ендпоінтів
* [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) — архітектурні рішення
* [`FIRMWARE.md`](docs/FIRMWARE.md) — специфікація прошивки STM32
* [`HARDWARE.md`](docs/HARDWARE.md) — апаратна специфікація
* [`TOKENOMICS.md`](docs/TOKENOMICS.md) — деталі токеноміки
* [`BLOCKCHAIN_DEVELOPMENT.md`](docs/BLOCKCHAIN_DEVELOPMENT.md) — розробка смарт-контрактів
* [`VISION.md`](docs/VISION.md) — візія проекту

---

## 👁️ Статус Проекту: **Titanium Baseline** (98% Ready)

Фундамент моделей, сервісів, API-контролерів та фонових воркерів завершено. Система готова до прийому телеметрії та Web3-емісії.

> *"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."* — **Alexey Architect**
