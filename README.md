# 🌿 Silken Net

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/13358/badge)](https://www.bestpractices.dev/projects/13358)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/Alexey-Lukin/silken_net/badge)](https://securityscorecards.dev/viewer/?uri=github.com/Alexey-Lukin/silken_net)

<!-- hero: один представник кожного макро-шару, знизу-вгору (дерево→блокчейн) -->
<p align="center">
  <a href="docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md"><img alt="EBFC >500mV (L1 біофізика)" src="https://img.shields.io/badge/EBFC%20%3E500mV-2E7D32?style=flat-square"></a>
  <a href="docs/02_03_BQ25570_MPPT_Nano_Power.md"><img alt="BQ25570 MPPT (L2 живлення)" src="https://img.shields.io/badge/BQ25570-CC0000?style=flat-square"></a>
  <a href="https://www.st.com/en/microcontrollers-microprocessors/stm32wle5jc.html"><img alt="STM32WLE5JC (L3 firmware)" src="https://img.shields.io/badge/STM32WLE5-03234B?style=flat-square&logo=stmicroelectronics&logoColor=white"></a>
  <a href="https://lora-alliance.org/"><img alt="LoRa 868 (L4 мережа)" src="https://img.shields.io/badge/LoRa%20868-5BC236?style=flat-square"></a>
  <a href="https://rubyonrails.org/"><img alt="Rails 8.1 (L5 backend)" src="https://img.shields.io/badge/Rails%208.1-D30001?style=flat-square&logo=rubyonrails&logoColor=white"></a>
  <a href="https://www.peaq.xyz/"><img alt="peaq DID (L6 ідентичність)" src="https://img.shields.io/badge/peaq%20DID-FF00A8?style=flat-square"></a>
  <a href="https://polygon.technology/"><img alt="Polygon (L7 mint)" src="https://img.shields.io/badge/Polygon-7B3FE4?style=flat-square&logo=polygon&logoColor=white"></a>
  <a href="https://solana.com/"><img alt="Solana (L7 micro-rewards)" src="https://img.shields.io/badge/Solana-9945FF?style=flat-square&logo=solana&logoColor=white"></a>
  <a href="https://ethereum.org/"><img alt="Ethereum L1 (L8 фіналізація)" src="https://img.shields.io/badge/Ethereum%20L1-3C3C3D?style=flat-square&logo=ethereum&logoColor=white"></a>
</p>

**Silken Net** — перша у світі trustless D-MRV (Digital Measurement, Reporting, and Verification) платформа для моніторингу здоров'я лісів у планетарному масштабі. Кожне дерево отримує машинний паспорт (peaq DID), стає економічним агентом і заробляє вуглецеві токени (SCC) за підтверджений ріст біомаси.

> *"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."*

---

## 🌐 English overview

**Silken Net** is the world's first trustless **D-MRV** (Digital Measurement, Reporting & Verification) platform for planetary-scale forest-health monitoring. Each tree gets a machine identity (peaq DID), becomes an economic agent, and earns carbon tokens (**SCC**) for verified biomass growth. A titanium gyroid anchor with an enzymatic biofuel cell (EBFC — "zero-grid", >500 mV from xylem sap) powers an STM32 *Soldier* node that senses → runs TinyML → computes a Lorenz-attractor homeostasis signal → encrypts → transmits over LoRa 868 MHz to a *Queen* gateway, which relays via CoAP to a Rails 8 / PostgreSQL / Sidekiq backend and a 12-chain Web3 *Proof-of-Growth* pipeline (10,000 growth_points = 1 SCC). The rest of this README and the `docs/` canon are primarily in Ukrainian — English contributors should start with [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md), and are welcome to open issues and pull requests in English.

---

## 🏛️ Архітектура (8 Рівнів SilkenNet)

```
L8  Ethereum L1       Щотижневий SHA-256 state root (фіналізація)
L7  Polygon + DeFi    SCC/SFC мінтинг, Solana нагороди, Celo ReFi, KlimaDAO ESG
L6  Верифікація       peaq DID, IoTeX ZK-proofs, Streamr P2P, Filecoin/IPFS
L5  Rails Backend     Rails 8.1 API, PostgreSQL, Sidekiq (50+ воркерів)
L4  LoRa Мережа       868 МГц star-only, CoAP/UDP, шлюзи Королеви, Starlink/LTE
L3  Прошивка + AI     STM32WLE5JC, TinyML (INT8 pure-C + CMSIS-DSP log-mel), mruby Лоренц, AES-128-ECB/CCM
L2  Апаратна Капсула  BQ25570 MPPT, суперконденсатор 0.47Ф, Pogo Pin
L1  Біофізика         Ti-6Al-4V гіроїдний анкер, EBFC Gen 2.0 (dgrFAD-GDH анод + Laccase/ZIF-nanozyme катод)
```

Кожен вузол («Солдат») — це STM32WLE5JC, вбудований у титановий гіроїдний анкер у стовбурі дерева. Ензимний біопаливний елемент (EBFC) перетворює глюкозу ксилемного соку на >500 мВ. Енергія заряджає суперконденсатор 0.47Ф, який живить мікроконтролер. Солдат класифікує звуки (5-класовий TinyML: тиша / вітер / пилка / фауна / водно-стресовий проксі), обчислює гомеостаз дерева через Атрактор Лоренца (mruby) та відправляє 21-байтні AES-128 пакети через LoRa 868 МГц (star-only — mesh-релей гейтовано в CCM-ері, повернення = ARCH.43) до шлюзу «Королева» (CoAP-батч у хмару йде вже під AES-256-CBC).

---

## 🧬 Технологічний Стек — вертикальний зріз стовбура

_Знизу вгору, як сік у ксилемі: від кореня в живому дереві (**L1**) до фіналізації в Ethereum (**L8**) — той самий потік даних дерево→блокчейн, що й [8-рівнева конституція](#🏛️-архітектура-8-рівнів-silkennet) вище. `TRL`-мітка кожного рівня каже правду про зрілість заліза, а не лише «ми юзаємо X»._

| Рівень / Layer | Стек / Stack |
|:---|:---|
| **L1 · КОРІНЬ**<br><sub>Біофізика · `TRL 3`</sub> | ![Ti-6Al-4V](https://img.shields.io/badge/Ti--6Al--4V-8A8D8F?style=flat-square) ![Gyroid TPMS](https://img.shields.io/badge/Gyroid%20TPMS-556B2F?style=flat-square) ![EBFC >500mV](https://img.shields.io/badge/EBFC%20%3E500mV-2E7D32?style=flat-square) ![PicoGK](https://img.shields.io/badge/PicoGK-6E4B9E?style=flat-square) ![.NET 9](https://img.shields.io/badge/.NET%209-512BD4?style=flat-square&logo=dotnet&logoColor=white) ![AlphaFold 3](https://img.shields.io/badge/AlphaFold%203-2E6FF2?style=flat-square) ![OpenMM](https://img.shields.io/badge/OpenMM-3B7DD8?style=flat-square) ![PySCF](https://img.shields.io/badge/PySCF-1E5C97?style=flat-square) |
| **L2 · КАПСУЛА**<br><sub>Апаратура · `TRL 6`</sub> | ![BQ25570](https://img.shields.io/badge/BQ25570-CC0000?style=flat-square) ![Supercap 0.47F](https://img.shields.io/badge/Supercap%200.47F-5A6B7B?style=flat-square) ![SIM7070G](https://img.shields.io/badge/SIM7070G-1E88E5?style=flat-square) ![W25Q32](https://img.shields.io/badge/W25Q32-004B87?style=flat-square) ![SE051](https://img.shields.io/badge/SE051-0A6EBD?style=flat-square) |
| **L3 · МОЗОК**<br><sub>Прошивка + Edge-AI · `TRL 6`</sub> | ![STM32WLE5](https://img.shields.io/badge/STM32WLE5-03234B?style=flat-square&logo=stmicroelectronics&logoColor=white) ![SX1262](https://img.shields.io/badge/SX1262-00A3E0?style=flat-square) ![C](https://img.shields.io/badge/C-A8B9CC?style=flat-square&logo=c&logoColor=white) ![mruby](https://img.shields.io/badge/mruby-4A4A4A?style=flat-square) ![Arm CMSIS](https://img.shields.io/badge/Arm%20CMSIS-0091BD?style=flat-square&logo=arm&logoColor=white) ![TensorFlow](https://img.shields.io/badge/TensorFlow-FF6F00?style=flat-square&logo=tensorflow&logoColor=white) ![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white) |
| **L4 · ЖИЛИ**<br><sub>Мережа</sub> | ![LoRa 868](https://img.shields.io/badge/LoRa%20868-5BC236?style=flat-square) ![LoRaWAN 1.0.4](https://img.shields.io/badge/LoRaWAN%201.0.4-00295B?style=flat-square) ![CoAP](https://img.shields.io/badge/CoAP-2CA5E0?style=flat-square) ![Helium](https://img.shields.io/badge/Helium-0ACF83?style=flat-square&logo=helium&logoColor=white) |
| **L5 · СЕРЦЕВИНА**<br><sub>Backend · `TRL 8`</sub> | ![Ruby](https://img.shields.io/badge/Ruby-CC342D?style=flat-square&logo=ruby&logoColor=white) ![Rails](https://img.shields.io/badge/Rails-D30001?style=flat-square&logo=rubyonrails&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white) ![PostGIS](https://img.shields.io/badge/PostGIS-336791?style=flat-square) ![Sidekiq](https://img.shields.io/badge/Sidekiq-B1003E?style=flat-square&logo=sidekiq&logoColor=white) ![Puma](https://img.shields.io/badge/Puma-343A40?style=flat-square) ![Redis](https://img.shields.io/badge/Redis-FF4438?style=flat-square&logo=redis&logoColor=white) ![Kredis](https://img.shields.io/badge/Kredis-D92D2D?style=flat-square) ![Phlex](https://img.shields.io/badge/Phlex-F0453A?style=flat-square) ![Turbo](https://img.shields.io/badge/Turbo-5CD8E5?style=flat-square&logo=turbo&logoColor=white) ![Stimulus](https://img.shields.io/badge/Stimulus-77E8B9?style=flat-square&logo=stimulus&logoColor=white) ![Tailwind CSS](https://img.shields.io/badge/Tailwind-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white) |
| ⛓ **L6 · КАМБІЙ**<br><sub>Верифікація</sub> | ![peaq](https://img.shields.io/badge/peaq-FF00A8?style=flat-square) ![IoTeX](https://img.shields.io/badge/IoTeX-00C1D4?style=flat-square) ![Streamr](https://img.shields.io/badge/Streamr-FF5C00?style=flat-square) ![Filecoin](https://img.shields.io/badge/Filecoin-0090FF?style=flat-square) ![IPFS](https://img.shields.io/badge/IPFS-65C2CB?style=flat-square&logo=ipfs&logoColor=white) ![The Graph](https://img.shields.io/badge/The%20Graph-6F4CFF?style=flat-square) |
| ⛓ **L7 · КРОНА**<br><sub>Фінанси</sub> | ![Polygon](https://img.shields.io/badge/Polygon-7B3FE4?style=flat-square&logo=polygon&logoColor=white) ![Solana](https://img.shields.io/badge/Solana-9945FF?style=flat-square&logo=solana&logoColor=white) ![Celo](https://img.shields.io/badge/Celo-FCFF52?style=flat-square) ![Chainlink](https://img.shields.io/badge/Chainlink-375BD2?style=flat-square&logo=chainlink&logoColor=white) ![KlimaDAO](https://img.shields.io/badge/KlimaDAO-0AA152?style=flat-square) ![Hadron](https://img.shields.io/badge/Polygon%20Hadron-7B3FE4?style=flat-square) ![Uniswap V3](https://img.shields.io/badge/Uniswap%20V3-FF007A?style=flat-square) ![Gnosis Safe](https://img.shields.io/badge/Gnosis%20Safe-12FF80?style=flat-square) |
| ⛓ **L8 · ВЕРШИНА**<br><sub>Фіналізація</sub> | ![Ethereum L1](https://img.shields.io/badge/Ethereum%20L1-3C3C3D?style=flat-square&logo=ethereum&logoColor=white) ![Solidity](https://img.shields.io/badge/Solidity-363636?style=flat-square&logo=solidity&logoColor=white) ![Foundry](https://img.shields.io/badge/Foundry-FF8C00?style=flat-square) ![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=flat-square&logo=openzeppelin&logoColor=white) |
| 🌍 **ҐРУНТ**<br><sub>DevOps · CI · Observability</sub> | ![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white) ![Kamal](https://img.shields.io/badge/Kamal-0E4B6E?style=flat-square) ![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=flat-square&logo=terraform&logoColor=white) ![Google Cloud](https://img.shields.io/badge/Google%20Cloud-4285F4?style=flat-square&logo=googlecloud&logoColor=white) ![Akash](https://img.shields.io/badge/Akash-FF414D?style=flat-square) ![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white) ![Sigstore](https://img.shields.io/badge/Sigstore%2FSLSA-003399?style=flat-square) ![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white) ![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white) ![Sentry](https://img.shields.io/badge/Sentry-362D59?style=flat-square&logo=sentry&logoColor=white) ![RSpec](https://img.shields.io/badge/RSpec-E12C3E?style=flat-square) ![RuboCop](https://img.shields.io/badge/RuboCop-000000?style=flat-square&logo=rubocop&logoColor=white) ![Brakeman](https://img.shields.io/badge/Brakeman-FF6600?style=flat-square) ![Slither](https://img.shields.io/badge/Slither-3B3B3B?style=flat-square) ![Halmos](https://img.shields.io/badge/Halmos-5A4FCF?style=flat-square) |

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
bin/rspec                # Повний набір тестів
bin/rubocop -A           # Лінтер (обов'язково перед комітом)
bin/brakeman             # Статичний аналіз безпеки
bin/bundler-audit check  # Вразливості залежностей
```

### 5.1. Смарт-контракти (Foundry)

```bash
cd contracts
npm ci                           # Встановити OZ + forge-std
forge build --sizes              # Компіляція + розмір контрактів
forge test -vvv --gas-report     # Тести з газовим звітом
forge coverage --report summary  # Покриття (аналог SimpleCov)
forge coverage --report lcov     # lcov.info (CI coverage-артефакт, ≥90% floor)
```

Тестові файли: `contracts/test/*.t.sol` (6 контрактів; unit + Halmos symbolic + Medusa fuzz + Foundry invariant, ≥90% coverage-floor).

### 6. Розгортання (Kamal)

```bash
kamal setup
kamal deploy
```

> 🔏 **Signed releases:** the production image mirrored to GHCR carries a Sigstore-signed SLSA build-provenance attestation — verify it before pulling per [`SECURITY.md`](SECURITY.md) (`gh attestation verify oci://ghcr.io/alexey-lukin/silken_net:<tag> --owner Alexey-Lukin`).

---

## ⛓️ Токеноміка

**SCC (Silken Carbon Coin)** — утилітарний ERC-20 токен за верифіковану секвестрацію CO₂.
- 10 000 `growth_points` = 1 SCC
- Slashing: за деградацію від **халатності** (cause-gate A/B/C — стихія покривається страхуванням); cluster-trigger >20% дерев зі `stress_index ≥ 1.0`. Політика → [`05_05`](docs/05_05_Slashing_and_Risk_Policy.md)
- MAX_SUPPLY: 1 мільярд SCC

**SFC (Silken Forest Coin)** — governance ERC-20 + Votes (EIP-712) для DAO голосування.
- MAX_SUPPLY: 100 мільйонів SFC
- Підтримує gasless транзакції через EIP-712 permit

**Governance DAO** ([`05_06`](docs/05_06_Governance_and_DAO.md)) — SFC holders голосують за зміну параметрів протоколу:
- `SilkenGovernor.sol` — OZ Governor + GovernorVotes (snapshot defense) + 48h Timelock
- `SilkenTimelock.sol` — TimelockController з 48h мінімальною затримкою
- `ProtocolParameters.sol` — on-chain registry (17 well-known ключів: 8 Lorenz DCI-locked + 9 економічних tokenomics/slashing)
- `StateRootAnchor.sol` — щотижнева фіналізація state root в Ethereum L1

Всі контракти: `contracts/*.sol`, тести: `contracts/test/*.t.sol` (Foundry)

---

## 🔐 Безпека Прошивки

- **RDP (Readout Protection):** цільовий **Level 2** — незворотне апаратне блокування пам'яті STM32, фінальний крок перед першою партією в ліс; поточний стан = Level 0 (розробка), трекінг `SEC.2`
- **AES-128 (transitional ECB → CCM):** LoRa-**телеметрія** шифрується per-device session-ключем (KEYL, HKDF); **control-plane** (downlink OTA/beacon/CMD) — спільним cluster-ключем KEYB. CoAP-магістраль Queen↔Rails — AES-256-CBC.
- **Zero-Trust ключі:** усі AES-ключі виводяться HKDF з Protected-Flash master-seed і **не покидають Ruby-процес** у відкритому вигляді (in-process LRU, без Redis-serialize)
- **OTA Updates:** пакети прошивки (512 байт/чанк) чанкуються + CRC16/32 + HMAC-SHA256 у `OtaPackagerService`, шифруються AES-256-CBC у `OtaTransmissionWorker`

---

## 📚 Документація

Канон живе в [`docs/`](docs/) як SSOT-документи, згруповані у модулі 00–07.

> **Повний індекс — [`docs/00_00` — SSOT Index](docs/00_00_SSOT_Index.md):** порядок читання, системна карта восьми рівнів кіберфізики й опис кожного документа. Це **єдиний дім переліку**; тут він свідомо не дублюється, щоб не дрейфував удруге.

- **Модуль 00 — фундамент** (read-first): візія та дорожня карта · AI-Native метод і NASA TRL · TRL-матриця з HIL · SSOT-стандарт · Beyond-TRL-9 агенда
- **Модулі 01–06 — система:** анкер і EBFC · залізо капсули та Королеви · прошивка й Edge AI · серверне ядро Rails · Web3 та економіка · деплой і спостережуваність
- **Модуль 07 — програма:** NaaS-контракти · юніт-економіка · академічна інтеграція та IP-постава

🔴 Живий стан незавершеного — [`docs/00_07` — Action Plan Tracker](docs/00_07_Action_Plan_Tracker.md).

---

## 🌍 Масштаб

Система спроектована для **мільйонів → мільярдів → трильйонів** дерев по всьому світу. Кожне архітектурне рішення — від партиціонування PostgreSQL до черг Sidekiq — розраховане на планетарний масштаб.

---

## 🤝 Внесок (Contributing)

Баги та пропозиції — через [GitHub Issues](https://github.com/Alexey-Lukin/silken_net/issues); вразливості — приватно за [`SECURITY.md`](SECURITY.md). Процес внеску (fork → branch → PR), локальні перевірки та вимоги до коду — у [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## 📜 Ліцензія та IP-постава

SilkenNet — **mission-first, defensive-publication-first**: ми **не патентуємо** цю роботу, а публікуємо її як prior art, щоб вона лишалась вільною для всіх лісів і її **не можна було захопити**. Канон постави — [`07_03 §3`](docs/07_03_Academic_Integration_and_IP.md); повна мапа зон і винятків — [`NOTICE`](NOTICE).

| Зона | Ліцензія | Файл |
|------|----------|------|
| **Код** (backend / firmware / tooling / IaC) | **GNU AGPL-3.0-or-later** — per-file SPDX | [`LICENSE`](LICENSE) |
| **Смарт-контракти** (`contracts/*.sol`) | **MIT** — per-file SPDX (on-chain composability / audit-tooling; ратифіковано DOC-T.47) | [`LICENSE`](LICENSE) |
| **Залізо** (гіроїд / EBFC / PCB-дизайн) | **CERN-OHL-S-2.0** | [`LICENSE-HARDWARE.txt`](LICENSE-HARDWARE.txt) |
| **Документація** (`docs/**`) | **CC-BY-SA-4.0** | [`LICENSE-DOCS.txt`](LICENSE-DOCS.txt) |

- **Patent non-assertion pledge:** не подаємо й не assert-имо патенти; інвентивне ядро опубліковане як defensive disclosure — [`docs/protocols/anchor/defensive_disclosure.md`](docs/protocols/anchor/defensive_disclosure.md).
- **Third-party винятки:** виходи AlphaFold 3 (`docs/protocols/ebfc/in_silico/alphafold3/**` + `dgrGcGDH_AF3.pdb`) — під власними **non-commercial** AF3 Terms, **не** CC-BY-SA (див. [`NOTICE`](NOTICE)). Повний інвентар залежностей — `THIRD_PARTY_NOTICES`.
- **Торгові марки** SilkenNet™ / GaiaNexus™ / SCC™ — зарезервовані (захист бренду), вище не ліцензуються.
