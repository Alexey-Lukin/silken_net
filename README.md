# 🌿 Silken Net — Gaia 2.0: Кіберфізична Держава Черкаського Бору

**Silken Net** — це trustless D-MRV (Digital Measurement, Reporting, and Verification) платформа, що інтегрує 12 блокчейн-мереж та протоколів у єдину Кіберфізичну Державу. Деревам надаються машинні паспорти (peaq DID), їхня телеметрія верифікується ZK-proof (IoTeX W3bstream), а токен-нагороди розподіляються через Polygon, Solana, Celo та Ethereum.

Це "Океан", який дихає в унісон із ксилемним соком кожного "Солдата" (дерева) та кожної "Королеви" (шлюзу).

> 📖 **[Анатомія Gaia 2.0 — 12 кроків Кіберфізичної Держави](docs/GAIA_2_0_ANATOMY.md)**

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
* **TinyMlModel**: вагова матриця нейромережі для детекції аномалій на пристрої.
* **BioContractFirmware**: mruby-байткод Атрактора Лоренца (OTA-версіонована прошивка).
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
| `SilkenNet::Attractor` | Лоренц-атрактор — ядро AI-оракула (BigDecimal, 18 знаків) |
| `InsightGeneratorService` | Генерація денних `AiInsight` та `EwsAlert` (AI Fraud Guard) |
| `TelemetryUnpackerService` | Розпакування CoAP-пакетів від STM32 |
| `AlertDispatchService` | Маршрутизація тривог (SMS/Telegram) |
| `EmergencyResponseService` | Екстрений протокол реагування |
| `BlockchainMintingService` | Емісія SCC-токенів (Polygon, guard: IoTeX + Chainlink + Hadron) |
| `BlockchainBurningService` | Slashing-протокол (Burning) |
| `ChainAuditService` | Аудит on-chain транзакцій |
| `HardwareKeyService` | Генерація та ротація AES-256 ключів |
| `OtaPackagerService` | Упаковка та шифрування OTA-пакетів прошивки |
| `PriceOracleService` | Ціновий оракул (Uniswap V3 на Polygon) |
| `Iotex::W3bstreamVerificationService` | ZK-proof верифікація (IoTeX W3bstream) |
| `Chainlink::OracleDispatchService` | Децентралізований оракул (Chainlink Functions DON) |
| `Peaq::DidRegistryService` | Машинний паспорт (peaq DID) |
| `Solana::MintingService` | Мікро-платежі USDC (Solana) |
| `Celo::CommunityRewardService` | ReFi нагороди громаді (cUSD, Celo) |
| `KlimaDao::RetirementService` | ESG carbon retirement (KlimaDAO) |
| `Polygon::HadronComplianceService` | KYC/KYB для RWA (Polygon Hadron, ERC-3643) |
| `Ethereum::StateAnchorService` | Щотижневий state root (Ethereum L1) |
| `Streamr::BroadcasterService` | P2P real-time broadcast (Streamr) |
| `TheGraph::QueryService` | Subgraph indexing (The Graph, GraphQL) |
| `Filecoin::ArchiveService` | Вічний архів (IPFS/Filecoin) |
| `Filecoin::VerificationService` | Верифікація архівів (IPFS CID) |

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
| `EcosystemHealingWorker` | `critical` | Автоматична корекція аномалій |
| `InsurancePayoutWorker` | `critical` | Виплата страхових компенсацій |
| `IotexVerificationWorker` | `web3` | ZK-proof генерація (IoTeX W3bstream) |
| `ChainlinkDispatchWorker` | `web3` | Dispatch до Chainlink Oracle |
| `PeaqRegistrationWorker` | `web3` | Реєстрація peaq DID |
| `SolanaMicroRewardWorker` | `web3` | Мікро-платежі USDC (Solana) |
| `CeloRewardWorker` | `web3` | ReFi нагороди cUSD (Celo) |
| `KlimaRetirementWorker` | `web3` | ESG carbon retirement (KlimaDAO) |
| `EthereumAnchorWorker` | `web3` | State root → Ethereum L1 (щотижня) |
| `HadronAssetRegistrationWorker` | `web3` | RWA реєстрація (Polygon Hadron) |
| `StreamrBroadcastWorker` | `low` | P2P broadcast (Streamr) |
| `FilecoinArchiveWorker` | `low` | Архівація на IPFS/Filecoin |
| `AuditLogWorker` | `low` | Створення аудит-записів |

---

## 🛠️ Технологічний Стек (The Omakase Way)

* **Backend**: Ruby **4.0.1** / Rails **8.1.2**.
* **Database**: PostgreSQL + **Solid Cache** + **Solid Cable** + **Solid Queue**.
* **Background Jobs**: **Sidekiq** + **sidekiq-scheduler** (черги: `uplink`, `alerts`, `critical`, `downlink`, `default`, `web3`, `low`; 26 воркерів).
* **Frontend**: Hotwire (Turbo 8 / Stimulus), Tailwind CSS, **Phlex** (компонентна система).
* **Serialization**: **Blueprinter** (API JSON blueprints).
* **Pagination**: **Pagy** + **Groupdate** (time-series).
* **IoT Protocol**: CoAP / LoRaWAN (Sanctum Listener).
* **Blockchain (Primary)**: Polygon (ERC-20 Permit & Votes), **eth** gem.
* **Multichain (Gaia 2.0)**: Ethereum L1 (finality), Solana (micro-rewards), Celo (ReFi), KlimaDAO (ESG), Polygon Hadron (RWA/KYC).
* **Verification**: IoTeX W3bstream (ZK-proofs), Chainlink (Oracle), peaq (Machine DID).
* **Data**: Streamr (P2P), The Graph (Subgraph), Filecoin/IPFS (Archive).
* **Deployment**: **Kamal** (Docker), **Akash Network** (Decentralized Cloud), **Thruster** (HTTP/2 proxy).

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

* **[`GAIA_2_0_ANATOMY.md`](docs/GAIA_2_0_ANATOMY.md) — 🌐 Анатомія Gaia 2.0: 12 кроків Кіберфізичної Держави**
* [`API.md`](docs/API.md) — опис всіх API-ендпоінтів (24 контролери)
* [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) — мультичейн архітектура та потоки даних (12 мереж)
* [`MODELS.md`](docs/MODELS.md) — всі доменні моделі та їхні зв'язки
* [`LOGIC.md`](docs/LOGIC.md) — сервіси (24) та воркери (26) з призначеннями
* [`FIRMWARE.md`](docs/FIRMWARE.md) — специфікація прошивки STM32
* [`HARDWARE.md`](docs/HARDWARE.md) — апаратна специфікація та BOM
* [`TOKENOMICS.md`](docs/TOKENOMICS.md) — мультичейн токеноміка (Polygon, Solana, Celo, KlimaDAO, Ethereum L1)
* [`BLOCKCHAIN_DEVELOPMENT.md`](docs/BLOCKCHAIN_DEVELOPMENT.md) — розробка 12-chain Web3 інфраструктури
* [`DEPLOYMENT.md`](docs/DEPLOYMENT.md) — Kamal + Akash Network + Terraform
* [`VISION.md`](docs/VISION.md) — візія проекту та roadmap

---

## 👁️ Статус Проекту: **Gaia 2.0** (Cyber-Physical State)

Мультичейн архітектура з 12 мережами та протоколами завершена. Система готова до прийому телеметрії, ZK-верифікації та мультичейн емісії.

> *"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."* — **Alexey Architect**
