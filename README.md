# 🌿 Silken Net — Gaia 2.0

**Silken Net** — перша у світі trustless D-MRV (Digital Measurement, Reporting, and Verification) платформа для моніторингу здоров'я лісів у планетарному масштабі. Кожне дерево отримує машинний паспорт (peaq DID), стає економічним агентом і заробляє вуглецеві токени (SCC) за підтверджений ріст біомаси.

> *"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."*

---

## 🏛️ Архітектура (8 Рівнів Gaia 2.0)

```
L8  Ethereum L1       Щотижневий SHA-256 state root (фіналізація)
L7  Polygon + DeFi    SCC/SFC мінтинг, Solana нагороди, Celo ReFi, KlimaDAO ESG
L6  Верифікація       peaq DID, IoTeX ZK-proofs, Streamr P2P, Filecoin/IPFS
L5  Rails Backend     Rails 8.1 API, PostgreSQL, Sidekiq (31+ воркерів)
L4  LoRa Мережа       868 МГц меш, CoAP/UDP, шлюзи Королеви, Starlink/LTE
L3  Прошивка + AI     STM32WLE5JC, TinyML (CMSIS-NN), mruby Лоренц, AES-256
L2  Апаратна Капсула  BQ25570 MPPT, суперконденсатор 0.47Ф, Pogo Pin
L1  Біофізика         Ti-6Al-4V гіроїдний анкер, EBFC (GOx анод + Laccase катод)
```

Кожен вузол («Солдат») — це STM32WLE5JC, вбудований у титановий гіроїдний анкер у стовбурі дерева. Ензимний біопаливний елемент (EBFC) перетворює глюкозу ксилемного соку на >500 мВ. Енергія заряджає суперконденсатор 0.47Ф, який живить мікроконтролер. Солдат класифікує звуки (пилка, кавітація, пожежа) через TinyML, обчислює гомеостаз дерева через Атрактор Лоренца (mruby) та відправляє 21-байтні AES-256 пакети через LoRa mesh (868 МГц) до шлюзу «Королева».

---

## 🌐 Мультичейн Стек (12 Мереж)

| Роль | Мережа | Функція |
|------|--------|---------|
| **Ідентичність** | peaq | Machine DID паспорт дерева |
| **Верифікація** | IoTeX W3bstream | ZK-proof автентичності даних STM32 |
| **Оракул** | Chainlink | CCIP/Functions: Rails → Polygon/Solana |
| **Токени** | Polygon | SCC (утилітарний) + SFC (governance DAO) |
| **Мікроплатежі** | Solana | USDC нагороди лісникам |
| **ReFi** | Celo | Нагороди громадам (cUSD) |
| **ESG** | KlimaDAO | Carbon retirement |
| **KYC/RWA** | Polygon Hadron | ERC-3643 compliance |
| **Фіналізація** | Ethereum L1 | Щотижневий state root |
| **Індексація** | The Graph | GraphQL subgraph для SCC подій |
| **P2P Дані** | Streamr | Real-time трансляція телеметрії |
| **Архів** | Filecoin/IPFS | Вічне зберігання аудит-логів |

---

## 🔗 Proof of Growth — Пайплайн

```
EBFC (дерево) → delta_t → Lorenz Z → growth_points → TelemetryLog
    ↓
peaq DID → IoTeX ZK-proof → Chainlink Oracle → Polygon mint(SCC)
    ↓
10 000 growth_points = 1 SCC токен
Slashing: якщо >20% дерев кластера в стресі → автоматичне спалювання SCC
```

---

## 🛠️ Технологічний Стек

| Шар | Технологія |
|-----|------------|
| **Backend** | Ruby 4.0.2 / Rails 8.1.2 (Omakase) |
| **База даних** | PostgreSQL (4 БД: primary, cache, queue, cable) |
| **Черги** | Sidekiq (31 воркер, 9 пріоритетних черг) + Solid Queue |
| **Frontend** | Phlex + Turbo 8 + Stimulus + Tailwind CSS 4 |
| **API** | REST v1 (82 ендпоінти), Blueprinter serializers, Pagy |
| **IoT** | CoAP/UDP listener (порт 5683), LoRa mesh 868 МГц |
| **Прошивка** | C (STM32 HAL) + mruby VM + TinyML (CMSIS-NN) |
| **Смарт-контракти** | Solidity (Foundry), Polygon Amoy/Mainnet |
| **Розгортання** | Kamal (Docker), Terraform (GCP), Akash Network |
| **Безпека** | AES-256, argon2id, Pundit, rack-attack, Brakeman |
| **Моніторинг** | Prometheus, Sentry, Grafana |

---

## 🚀 Швидкий Старт

### 0. Системні залежності

Перед `bundle install` встановіть системні пакети.

#### PostGIS (обов'язково для просторових запитів кластерів)

**Ubuntu / Debian:**
```bash
sudo apt-get update
sudo apt-get install -y postgresql-16-postgis-3 postgresql-16-postgis-3-scripts
```

**macOS (Homebrew):**
```bash
brew install postgis
```

Після встановлення PostgreSQL-розширення активується автоматично через `structure.sql` (`CREATE EXTENSION IF NOT EXISTS postgis`). При ручному створенні бази виконайте в psql:
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

#### numo-narray (нативний gem, потребує компілятора)

`rumale` (ML-сервіси) залежить від `numo-narray-alt` — актуального fork'а `numo-narray`. Explicit `gem "numo-narray"` **видалено** з Gemfile, оскільки встановлення обох одночасно спричиняє конфлікт і runtime-попередження:

> *'numo-narray-alt' is an alternative implementation of 'numo-narray'. Having both gems installed may lead to conflicts.*

`numo-narray-alt` надає ідентичний API (`Numo::DFloat`, `Numo::NArray` тощо), тому в коді нічого змінювати не потрібно.

Обидва gem-и компілюють нативні C-розширення, тому потрібні інструменти збирання:

**Ubuntu / Debian:**
```bash
sudo apt-get install -y build-essential ruby-dev
```

**macOS (Homebrew):**
```bash
xcode-select --install   # або: brew install gcc
```

Після цього звичайний `bundle install` відпрацює без помилок.

---

### 1. Клонування та налаштування

```bash
git clone https://github.com/Alexey-Lukin/silken_net.git
cd silken_net
export PATH="/opt/hostedtoolcache/Ruby/4.0.2/x64/bin:$PATH"
bundle install
bin/rails db:prepare
```

### 2. Змінні середовища (`.env`)

Перед першим запуском скопіюйте шаблон та заповніть потрібні значення:

```bash
cp .env.example .env
```

Для локальної розробки та симуляції телеметрії достатньо залишити більшість полів порожніми — мінімальний набір:

| Змінна | Опис |
|--------|------|
| `REDIS_URL` | `redis://localhost:6379/0` (Sidekiq, вже є в шаблоні) |
| `WEB3_STRICT_MODE` | `false` — Web3-стаби активні, реальні ключі не потрібні |

Для повноцінного Web3-стеку (мінтинг SCC, Chainlink oracle, Solana мікроплатежі) потрібно заповнити:
`CHAINLINK_FUNCTIONS_ROUTER`, `CHAINLINK_HMAC_SECRET`, `CHAINLINK_SUBSCRIPTION_ID`, `SOLANA_WALLET_KEYPAIR`, `PROVISIONING_MASTER_KEY`.
Деталі — у [`docs/06_01_Deployment_Kamal_Terraform.md`](docs/06_01_Deployment_Kamal_Terraform.md).

### 3. Запуск

```bash
bin/dev   # Rails + Sidekiq + Tailwind CSS + CoAP listener
```

### 4. Симуляція телеметрії (без фізичного обладнання)

```bash
bin/rails db:seed      # Gateway, Tree, HardwareKey, TreeFamily
bin/forest_simulator   # Генерує CoAP пакети від 5–15 Солдатів кожні 3–8 сек
```

Моніторинг конвеєру:
```bash
rails runner "puts TelemetryLog.count"
open http://localhost:3000/sidekiq
tail -f log/development.log | grep -i telemetry
```

### 5. Тести та якість

```bash
bundle exec rspec                # Повний набір тестів
bundle exec rubocop -A           # Лінтер (обов'язково перед комітом)
bundle exec brakeman             # Статичний аналіз безпеки
bundle exec bundler-audit check  # Вразливості залежностей
```

### 5.1. Смарт-контракти (Foundry)

```bash
cd contracts
npm ci                           # Встановити OZ + forge-std
forge build --sizes              # Компіляція + розмір контрактів
forge test -vvv --gas-report     # Тести з газовим звітом
forge coverage --report summary  # Покриття (аналог SimpleCov)
forge coverage --report lcov     # lcov.info для CI/Codecov
```

Тестові файли: `contracts/test/*.t.sol` (6 контрактів × ~30-50 тестів кожен).

### 6. Розгортання (Kamal)

```bash
kamal setup
kamal deploy
```

---

## 📡 Ідентифікатори Вузлів

| Тип | Формат | Приклад |
|-----|--------|---------|
| Солдат (Tree DID) | `SNET-XXXXXXXX` | `SNET-1A2B3C4D` |
| Королева (Gateway UID) | `SNET-Q-XXXXXXXX` | `SNET-Q-5E6F7A8B` |

---

## ⛓️ Токеноміка

**SCC (Silken Carbon Coin)** — утилітарний ERC-20 токен за верифіковану секвестрацію CO₂.
- 10 000 `growth_points` = 1 SCC
- Slashing: автоматичне спалювання при деградації кластера (поріг: >20% дерев зі `stress_index ≥ 1.0`)
- MAX_SUPPLY: 1 мільярд SCC

**SFC (Silken Forest Coin)** — governance ERC-20 + Votes (EIP-712) для DAO голосування.
- MAX_SUPPLY: 100 мільйонів SFC
- Підтримує gasless транзакції через EIP-712 permit

**Governance DAO** — SFC holders голосують за зміну параметрів протоколу:
- `SilkenGovernor.sol` — OZ Governor + GovernorVotes (snapshot defense) + 48h Timelock
- `SilkenTimelock.sol` — TimelockController з 48h мінімальною затримкою
- `ProtocolParameters.sol` — on-chain registry (13 параметрів: Lorenz σ/ρ/β, tokenomics, slashing)
- `StateRootAnchor.sol` — щотижнева фіналізація state root в Ethereum L1

Всі контракти: `contracts/*.sol`, тести: `contracts/test/*.t.sol` (Foundry)

---

## 🔐 Безпека Прошивки

- **RDP Level 2:** Апаратне блокування зчитування пам'яті STM32
- **AES-256:** Кожен пакет шифрується унікальним апаратним ключем (`HardwareKey`)
- **Shipping Mode:** Магнітний геркон утримує вузол у глибокому сні (2.1 µА) до монтажу
- **OTA Updates:** Зашифровані пакети прошивки (512 байт/чанк) через `OtaPackagerService`

---

## 📚 Документація

Детальна документація в директорії [`docs/`](docs/):

**Архітектура та Візія (Модуль 00)**
- [`00_00`](docs/00_00_SSOT_Index.md) — єдине джерело істини (SSOT), головний реєстр
- [`00_01`](docs/00_01_System_Architecture_and_Layers.md) — 8-рівнева кіберфізична архітектура
- [`00_02`](docs/00_02_Project_Vision_and_Roadmap.md) — місія та roadmap масштабування
- [`00_03`](docs/00_03_AI_Native_Concurrent_Engineering.md) — AI-Native парадигма управління та TRL

**Біомеханіка та Хімія (Модуль 01)**
- [`01_01`](docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md) — 3-складовий Ti-6Al-4V анкер
- [`01_02`](docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) — металургія Ti-6Al-4V, DMLS та біосумісність
- [`01_03`](docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) — EBFC: >500 мВ з глюкози дерева
- [`01_04`](docs/01_04_CODIT_and_Xylemointegration.md) — CODIT та ксилемоінтеграція

**Апаратне Забезпечення (Модуль 02)**
- [`02_01`](docs/02_01_Hardware_Architecture_and_BOM.md) — BOM та архітектура Солдата
- [`02_02`](docs/02_02_Blind_Mate_Pogo_Pin_Interface.md) — сліпий з'єднувач Pogo Pin
- [`02_03`](docs/02_03_BQ25570_MPPT_Nano_Power.md) — BQ25570 MPPT та нано-менеджмент живлення
- [`02_04`](docs/02_04_EDLC_Supercapacitor_Buffer.md) — буфер суперконденсатора EDLC 0.47Ф
- [`02_05`](docs/02_05_Queen_Hardware_and_Starlink.md) — шлюз Королева + Starlink/LTE

**Прошивка та Edge AI (Модуль 03)**
- [`03_01`](docs/03_01_Firmware_Lifecycle_and_DMA.md) — цикл Soldier: STOP2 → сенсори → LoRa TX
- [`03_02`](docs/03_02_Queen_Gateway_Firmware.md) — прошивка шлюзу Королеви (LoRa RX → CIFO → CoAP)
- [`03_03`](docs/03_03_TinyML_Acoustic_Inference.md) — TinyML: класифікація звуку пилки
- [`03_04`](docs/03_04_mruby_Lorenz_Attractor.md) — mruby Атрактор Лоренца (гомеостаз дерева)
- [`03_05`](docs/03_05_Hardware_AES256_and_Security.md) — апаратний AES-256 та безпека пакетів

**Серверне Ядро (Модуль 04)**
- [`04_01`](docs/04_01_Data_Models_and_Entities.md) — 26 ActiveRecord моделей, PostgreSQL схема
- [`04_02`](docs/04_02_Business_Logic_and_Services.md) — 29+ сервісів та 31 воркер
- [`04_03`](docs/04_03_REST_API_v1_Reference.md) — 82 REST API ендпоінти
- [`04_04`](docs/04_04_Phlex_UI_and_Tailwind.md) — дизайн-система Phlex + Tailwind

**Web3 та Економіка (Модуль 05)**
- [`05_01`](docs/05_01_Multichain_Architecture.md) — 12-chain DePIN стек
- [`05_02`](docs/05_02_Proof_of_Growth_Pipeline.md) — повний пайплайн Proof of Growth
- [`05_03`](docs/05_03_Tokenomics_SCC_and_SFC.md) — токеноміка SCC/SFC
- [`05_04`](docs/05_04_Ethereum_L1_State_Anchor.md) — щотижнева фіналізація в Ethereum L1

**Розгортання та Інфраструктура (Модуль 06)**
- [`06_01`](docs/06_01_Deployment_Kamal_Terraform.md) — Kamal + Terraform (GCP) + Web3 ENV
- [`06_02`](docs/06_02_Akash_Network_Integration.md) — децентралізована хмара Akash
- [`06_03`](docs/06_03_Prometheus_Observability.md) — Prometheus + Grafana + Sentry

**Бізнес та Фінанси (Модуль 07)**
- [`07_01`](docs/07_01_Nature_as_a_Service_Contracts.md) — NaaS контракти та страхування
- [`07_02`](docs/07_02_Unit_Economics_and_BOM.md) — юніт-економіка та ROI через SCC
- [`07_03`](docs/07_03_Grant_Applications_Tracker.md) — трекер грантових заявок

**Наука та R&D (Модуль 08)**
- [`08_01`](docs/08_01_University_R_and_D_Protocols.md) — партнерство з ЧНУ
- [`08_02`](docs/08_02_Cybernetic_and_Mathematical_Validation.md) — кіберфізична валідація ФОТІУС
- [`08_03`](docs/08_03_Joint_Publications_and_IP_Strategy.md) — спільні публікації та стратегія IP
- [`08_04`](docs/08_04_CHDTU_Data_Science_Collaboration.md) — ЧДТУ: Data Science, статистика та оптимізація
- [`08_05`](docs/08_05_CHIPB_Fire_Safety_Integration.md) — ЧІПБ: пожежна безпека, параметричне страхування, SOP
- [`08_06`](docs/08_06_CHMA_Biomedical_Integration.md) — ЧМА: біомедична валідація EBFC, токсикологія Ti-6Al-4V, ксилемоінтеграція
- [`08_07`](docs/08_07_SEU_Economics_and_Legal_Integration.md) — СЄУ: макроекономіка NaaS, RWA-легалізація, промисловий дизайн PEEK-радому

**Управління та Масштабування (Модуль 09)**
- [`09_01`](docs/09_01_AI_Native_Concurrent_Engineering.md) — AI-Native Concurrent Engineering (Shape Up)
- [`09_02`](docs/09_02_Strategic_Roadmap_and_TRL_Matrix.md) — матриця TRL та roadmap
- [`09_03`](docs/09_03_GitHub_Projects_and_Ops_Automation.md) — GitHub Projects V2 + CI/CD автоматизація

**Тестування (Модуль 10)**
- [`10_01`](docs/10_01_View_Component_Testing_Guide.md) — 30 best practices для тестування Phlex-компонентів
- [`10_02`](docs/10_02_Action_Plan_Tracker.md) — трекер незавершених задач (DOC/SW/SEC/ARCH аудит)

---

## 📊 Поточний Стан (TRL Matrix)

| Підсистема | TRL | Статус |
|------------|-----|--------|
| Rails Backend (API, сервіси, воркери) | 8 | Production Ready |
| Смарт-контракти (SCC/SFC) | 9 | Mainnet Ready |
| Токеноміка та Proof of Growth | 8 | Production Ready |
| REST API (82 ендпоінти) | 8 | Production Ready |
| Phlex UI + Tailwind дизайн-система | 9 | Production Ready |
| Прошивка Солдата (C + mruby + TinyML) | 6 | 112 тестів проходять |
| Прошивка Королеви (C + SIM7070G) | 6 | 59 тестів проходять |
| Апаратна капсула (BOM, MPPT) | 6 | Архітектура заморожена |
| Ti-6Al-4V гіроїдний анкер | 4 | Очікується nTop ліцензія |
| EBFC (GOx/Laccase ферменти) | 3 | Лабораторний етап (ЧНУ + ЧМА) |
| Академічна мережа (ЧНУ/ФОТІУС/ЧДТУ/ЧІПБ/ЧМА/СЄУ) | 3 | 6 університетів, 33+ публікацій Q1 pipeline |
| Розгортання GCP + Kamal | 4 | Код існує, деплой не проводився |

---

## 🌍 Масштаб

Система спроектована для **мільйонів → мільярдів → трильйонів** дерев по всьому світу. Кожне архітектурне рішення — від партиціонування PostgreSQL до черг Sidekiq — розраховане на планетарний масштаб.
