# 🌍 Gaia 2.0 (Silken Net) — Single Source of Truth (SSOT)

> _"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."_

Ласкаво просимо до Головного Архітектурного Реєстру проєкту **Silken Net**. Ця Wiki є Єдиним Джерелом Істини (SSOT) для розробки кіберфізичної D-MRV системи планетарного масштабу.

Система побудована за принципами **Zero-Trust** та **«нульового лагу»** — де «нульовий лаг» означає **event-driven реакцію без polling-затримки на рівні заліза** (`VBAT_OK`/DMA wakeup, [`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)), а **не** миттєвість end-to-end: сама система **свідомо асинхронна** (STOP2-сон ~99 % часу, батчинг на Королеві, governance-timelock 48 год). Будь-який код, згенерований ШІ, або фізичний прототип, створений підрядником, повинен суворо відповідати документації на цих сторінках.

> **Структура SSOT — тришарова.** **Модуль 00 — Фундамент** (read-first мета-лінза): *НАВІЩО* (візія/місія/дорожня карта) та *ЯК* (методологія, TRL, governance процесу) ми будуємо — плюс конституція всієї системи (карта нижче). **Tier I (Система, 01–06)** — інженерний канон того, *ЩО* ми будуємо: вертикальний стек шарів (01 анкер у дереві → 06 інфраструктура). **Tier II (Програма, 07–08)** — економіка/фінансування та академічні партнерства довкола системи. Стандарт самих доків — [`00_06`](00_06_SSOT_Documentation_Standard).

---

# 🧭 Модуль 00 — Фундамент (Foundation: Візія + Метод)

_Read-first мета-лінза проєкту: **НАВІЩО** (візія, місія, дорожня карта) і **ЯК** (методологія AI-Native, NASA TRL, Shape Up, governance процесу, стандарт SSOT-доків) ми будуємо — плюс **конституція всієї системи** (карта 8 рівнів нижче). Деталі кожного рівня розкриваються у профільних модулях Tier I (01–06)._

## 🗺️ Системна Карта: 8 Рівнів Кіберфізики (The Constitution)

_Top-down конституція системи: дані течуть знизу вгору — від біохімії дерева до фіналізації в Ethereum L1. Кожен рівень розгортається у профільному модулі Tier I (01–06). Повний **12-крокового Proof-of-Growth конвеєр** — канонічно [`05_02`](05_02_Proof_of_Growth_Pipeline) (операційний потік) + [`05_01 §1–2`](05_01_Multichain_Architecture) (ролі 12 мереж); політика resilience/failover — [`06_08`](06_08_Resilience_and_Failover_Policy). Методологія/процес — цей Модуль 00 (Фундамент, сторінки нижче); економіка/фінансування — Tier II (07)._

| Рівень | Сутність | Канон |
|--------|----------|-------|
| **1. Біофізика (The Root)** | Тризонний коаксіальний анкер Ti-6Al-4V + EBFC Gen 2.0 (dgrFAD-GDH анод + Laccase/ZIF катод, цвітеріонна мембрана) → >500 mV прямо з метаболізму дерева, без зовнішніх дротів | [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK) · [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) · [`01_04`](01_04_CODIT_and_Xylemointegration) |
| **2. Апаратура (The Capsule)** | Герметична капсула, blind-mate Pogo Pins до анкера, BQ25570 MPPT + іоністор 0.47F/5.5V, п'єзо-тригер пробудження | [`02_01`](02_01_Hardware_Architecture_and_BOM) · [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface) · [`02_03`](02_03_BQ25570_MPPT_Nano_Power) |
| **3. Прошивка / Edge AI (The Brain)** | STM32WLE5JC, STOP2 RTC-only **300 nA**, DMA-мікрофон, TinyML (тиша/вітер/пилка), mruby Lorenz-атрактор, апаратний AES-128 (LoRa-payload) | [`03_01`](03_01_Firmware_Lifecycle_and_DMA) · [`03_03`](03_03_TinyML_Acoustic_Inference) · [`03_04`](03_04_mruby_Lorenz_Attractor) · [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security) |
| **4. Мережа (The Veins)** | LoRa mesh 868 МГц (custom TTL-based, AES-128); Queen-шлюз агрегує пакети → CoAP-батч (**AES-256-CBC**) у хмару (опц. Starlink D2C); Helium як fallback при втраті Queen | [`02_05`](02_05_Queen_Hardware_and_Starlink) · [`03_02`](03_02_Queen_Gateway_Firmware) · failover [`06_08`](06_08_Resilience_and_Failover_Policy) |
| **5. Серверне ядро (The Engine)** | Rails 8.1 Omakase + PostgreSQL + Sidekiq: декодування L3, REST API, бізнес-логіка NaaS-контрактів | Модуль 04 ([`04_01`](04_01_Data_Models_and_Entities) · [`04_02`](04_02_Business_Logic_and_Services)) |
| **6. Верифікація (The Truth)** | peaq Machine DID (паспорт дерева) + IoTeX W3bstream ZK-proofs (real-silicon + гомеостаз Лоренца) + Streamr/Filecoin | [`05_01`](05_01_Multichain_Architecture) · [`05_02`](05_02_Proof_of_Growth_Pipeline) |
| **7. Фінанси (The Ledger)** | Polygon EVM — mint SCC/SFC; Chainlink DON oracle; Solana/Celo мікро-рейки; KlimaDAO ESG retirement; Polygon Hadron KYC (ERC-3643) | [`05_01`](05_01_Multichain_Architecture) · [`05_03`](05_03_Tokenomics_SCC_and_SFC) |
| **7.5 Governance (The Parliament)** | On-chain: `SilkenGovernor` + `SilkenTimelock` (48h) + `ProtocolParameters` (registry параметрів), Flash-Loan-захист | [`05_06`](05_06_Governance_and_DAO) |
| **8. Фіналізація (The Anchor)** | Ethereum L1 — щотижневий SHA-256 state root усієї економіки (rollup-стиль гарантія від збоїв сайдчейнів) | [`05_04`](05_04_Ethereum_L1_State_Anchor) |

### 🌐 Топологія Мережі (High-Level)

```
Soldier (Tree)         Soldier (Tree)         Soldier (Tree)
      │ LoRa                │ LoRa mesh            │ LoRa
      ▼                     ▼                      ▼
   Queen (Gateway) ◄──── Mesh Relay ────► Queen (Gateway)
      │ LTE/Starlink                          │ LTE/Starlink
      ▼                                       ▼
   ┌──────────────────────────────────────────────┐
   │  Rails Backend (Akash Network / GCP)          │
   │  CoAP Listener + Sidekiq                       │
   │                                                │
   │  ┌── Verification ─────────────────────────┐  │
   │  │ peaq DID → IoTeX ZK-proof → Chainlink   │  │
   │  └─────────────────────────────────────────┘  │
   │                                                │
   │  ┌── Data Streams ─────────────────────────┐  │
   │  │ Streamr (P2P real-time forest pulse)     │  │
   │  └─────────────────────────────────────────┘  │
   └──────────────────┬───────────────────────────┘
                      │ Multi-RPC
       ┌──────────────┼──────────────────────────┐
       ▼              ▼                          ▼
   ┌────────┐   ┌──────────┐            ┌──────────┐
   │Polygon │   │  Solana  │            │   Celo   │
   │SCC/SFC │   │  micro-  │            │  cUSD    │
   │Hadron  │   │  rewards │            │  ReFi    │
   │Chainlnk│   └──────────┘            └──────────┘
   └───┬────┘
       │
   ┌───┴────────────────────────────────────────────┐
   │  The Graph (subgraph indexing)                  │
   │  KlimaDAO (ESG carbon retirement)              │
   │  Filecoin/IPFS (immutable archive)             │
   │  Ethereum L1 (weekly state root finality)      │
   └────────────────────────────────────────────────┘
```

### 📚 Сторінки Фундаменту (Read-First)

- [`00_01` — Vision Mission and Roadmap](00_01_Vision_Mission_and_Roadmap) (Місія, проблема VCM, науковий підхід, NaaS, дорожня карта, Proof-of-Growth; філософія Slashing → 05_05)
- [`00_02` — AI Native Engineering and TRL](00_02_AI_Native_Engineering_and_TRL) (Філософія: NASA TRL, Intent-First, Wiki-First, AI Pipeline + Validation Gate)
- [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) (Канон per-module TRL-матриці + per-domain TRL + HIL-симулятори; Beyond-TRL-9 агенда винесена → 00_08)
- [`00_04` — Shape Up Operations and RnD Clusters](00_04_Shape_Up_Operations_and_RnD_Clusters) (Операційний template: 6+2 цикли, 4 R&D кластери, Betting Table, Async-Review)
- [`00_05` — GitHub Projects and IaC Automation](00_05_GitHub_Projects_and_IaC_Automation) (Projects V2 fields + Labels-as-Code + GitHub Actions workflows)
- [`00_06` — SSOT Documentation Standard](00_06_SSOT_Documentation_Standard) (Стандарт канон-доків: skeleton + home-registry + drift-tooling + restructure-метод)
- [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) (🔴 Живий документ — аудит блокерів, план дій, Sprint tracking)
- [`00_08` — Beyond TRL9 Planetary Roadmap](00_08_Beyond_TRL9_Planetary_Roadmap) (Beyond TRL 9: 4 Planetary-Intelligence прогалини + фрактальна мережева топологія — far-horizon R&D 2026–2040+)

---

# 🏛️ Tier I — Система (The Blueprint)

_Інженерний канон того, **ЩО** ми будуємо — вертикальний стек шарів від анкера в живому дереві (01) до децентралізованої інфраструктури (06). Кожен модуль розкриває свій рівень системної карти (вище)._

## 🌱 Модуль 01: Біомеханіка та Хімія (The Anchor)

_Все, що фізично інтегрується в живе дерево — тризонний коаксіальний анкер, EBFC та ксилемоінтеграція._

- [`01_01` — Coaxial Gyroid Topology and PEEK](01_01_Coaxial_Gyroid_Topology_and_PEEK) (3-зонний дизайн анкера: Ti-гіроїд + PEEK-терморозрив + катодний фланець)
- [`01_02` — Ti 6Al 4V Metallurgy and DMLS](01_02_Ti_6Al_4V_Metallurgy_and_DMLS) (DMLS друк металу + HIP + відпал)
- [`01_03` — EBFC Enzymatic Bio Fuel Cell](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) (EBFC Gen 2.0: dgrFAD-GDH анод + Laccase/ZIF катод + цвітеріонна мембрана — >500 mV, 20–25 років)
- [`01_04` — CODIT and Xylemointegration](01_04_CODIT_and_Xylemointegration) (Біологічна реакція дерева на імплантат + anti-overgrowth shield катода)

## ⚡ Модуль 02: Апаратне Забезпечення (The Capsule)

_Електроніка Soldier/Queen, енергетичні буфери, механіка blind-mate підключення та опціональна Starlink-uplink._

- [`02_01` — Hardware Architecture and BOM](02_01_Hardware_Architecture_and_BOM) (BOM капсули Солдата + ASCII power tree)
- [`02_02` — Blind Mate Pogo Pin Interface](02_02_Blind_Mate_Pogo_Pin_Interface) (Сліпий магнітний конектор Pogo-Pin до коаксіального анкера)
- [`02_03` — BQ25570 MPPT Nano Power](02_03_BQ25570_MPPT_Nano_Power) (BQ25570 MPPT нано-потужність + пряме живлення від EBFC)
- [`02_04` — EDLC Supercapacitor Buffer](02_04_EDLC_Supercapacitor_Buffer) (Іоністор 0.47Ф / 5.5В)
- [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) (Шлюз Королева + SIM7070G + Starlink Direct-to-Cell)
- [`02_06` — Legacy Breadboard Appendix](02_06_Legacy_Breadboard_Appendix) (📦 Архів: legacy LTC3108 breadboard-прототип — НЕ виробнича архітектура)

## 🧠 Модуль 03: Прошивка та Edge AI (The Brain)

_Логіка STM32WLE5JC: STOP2 / DMA / TinyML / mruby Lorenz / апаратний AES — Soldier і Queen firmware._

- [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) (Soldier цикл Phase 0-5, Watchdog, STOP2, RX-вікно, RTC reg-map)
- [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) (Queen LoRa RX → CIFO → CoAP flush)
- [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) (CMSIS-NN: класифікація пилки/кавітації/тиші)
- [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) (mruby VM атрактор хаосу — гомеостаз дерева; канон Lorenz-констант)
- [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) (LoRa AES-128-CCM + CoAP AES-256-CBC + ATECC608B + Flash Key + RDP + PQC roadmap)

## 🗄️ Модуль 04: Серверне Ядро (Web2 Backend)

_Rails 8.1 Omakase: моделі даних, бізнес-логіка, REST API, Phlex UI та тестова матриця._

- [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) (ActiveRecord моделі, PostgreSQL-схема, RANGE-partitioning)
- [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) (Service Objects + Sidekiq воркери, Web3CircuitBreaker, Drift Register)
- [`04_03` — REST API v1 Reference](04_03_REST_API_v1_Reference) (REST API v1, Pagy, Idempotency-Key, RBAC)
- [`04_04` — Phlex UI and Tailwind](04_04_Phlex_UI_and_Tailwind) (Phlex компоненти + Tailwind 4 + gaia design tokens + i18n)
- [`04_05` — Codex Lore Module](04_05_Codex_Lore_Module) (Codex — read-only наративний шар над телеметрією; ADR-зафіксований, поза hot-path)
- [`04_06` — Testing Guide and Coverage](04_06_Testing_Guide_and_Coverage) (RSpec best practices + Coverage Matrix: RSpec/Firmware C/Foundry Solidity)

## ⛓️ Модуль 05: Web3 та Економіка (The Ledger)

_DePIN-стек, Proof of Growth pipeline, токеноміка SCC/SFC, slashing/governance та фіналізація в Ethereum L1._

- [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) (**Core DePIN**: peaq + IoTeX + Chainlink + Polygon + **Filecoin** — audit-critical immutable archive [нот.18: НЕ optional як Solana/Celo; E.60 planned → `archive_root` стає ZK-witness, тоді формально Core] · **Expansion** [optional]: Solana / Celo / KlimaDAO)
- [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) (Повний uplink → oracle → mint flow + Dynamic Tax)
- [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) (SCC ERC-20 + SFC governance-токен + Dynamic Tax)
- [`05_04` — Ethereum L1 State Anchor](05_04_Ethereum_L1_State_Anchor) (Щотижневий SHA-256 state root в Ethereum mainnet)
- [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy) (Політика штрафів: negligence/force-majeure/indeterminate + формула + insurance + anti-fraud)
- [`05_06` — Governance and DAO](05_06_Governance_and_DAO) (On-chain governance: SilkenGovernor/Timelock/ProtocolParameters + Flash-Loan-захист)

## 🚀 Модуль 06: DevOps та Інфраструктура (The Matrix)

_Деплой, моніторинг, секрети та децентралізовані обчислення (Akash + GCP failover)._

- [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) (Kamal + Terraform GCP, Canopy vs Production)
- [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) (SDL 2.0 манифест + multi-provider failover)
- [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) (Grafana Alloy → Grafana Cloud + Alerting)
- [`06_04` — Secrets Checklist](06_04_Secrets_Checklist) (Інвентаризація секретів: GitHub Secrets, Kamal, Akash, Terraform)
- [`06_05` — Puma Configuration](06_05_Puma_Configuration) (Puma 8 IO-bound pool + кластерні хуки + runbook'и)
- [`06_06` — Disaster Recovery and Backup](06_06_Disaster_Recovery_and_Backup) (Cloud SQL PITR/HA + restore-runbook'и + RTO/RPO + master-key backup)
- [`06_07` — CICD and Runbook Index](06_07_CICD_and_Runbook_Index) (CI/CD workflows + єдиний operations runbook-індекс)
- [`06_08` — Resilience and Failover Policy](06_08_Resilience_and_Failover_Policy) (Queen failover 4 рівні + Per-Chain Fallback Matrix для Web3-ланок — runtime resilience)

---

# 🌿 Tier II — Програма

## 💰 Модуль 07: Економіка та Фінансування (Economics & Funding)

_NaaS-контракти, юніт-економіка та гранти. Зовнішні стейкхолдери (B2G/B2B + культурний шар) переїхали у Модуль 08 ([`08_03`](08_03_External_Stakeholders_Registry)). Візія/місія/дорожня карта — у Фундаменті [`00_01`](00_01_Vision_Mission_and_Roadmap)._

- [`07_01` — Nature as a Service Contracts](07_01_Nature_as_a_Service_Contracts) (NaaS контракти + параметричне страхування + фінансові константи)
- [`07_02` — Unit Economics and BOM](07_02_Unit_Economics_and_BOM) (Юніт-економіка + ROI через SCC + Supply Chain Ukraine)
- [`07_03` — Grant Applications Tracker](07_03_Grant_Applications_Tracker) (Трекер грантових заявок — Horizon Europe, Verra, Gold Standard)

## 🔬 Модуль 08: Академічна Інтеграція (Academic & Partnerships)

_Партнерства ВНЗ (ЧНУ+ФОТІУС, ЧДТУ, ЧІПБ, ЧМА, СЄУ) під рамкою MOIC: MoU, спільні публікації, IP-стратегія. Інженерна R&D-субстанція реферить канон Tier I (01–06), не дублює._

- [`08_01` — Joint Publications and IP Strategy](08_01_Joint_Publications_and_IP_Strategy) (MOIC-рамка + спільні публікації (Статті 1–35) + патентна стратегія/IP)
- [`08_02` — Academic Institutions Registry](08_02_Academic_Institutions_Registry) (Реєстр 5 ВНЗ: хто/кафедра → що валідує [канон-дім] → публікація)
- [`08_03` — External Stakeholders Registry](08_03_External_Stakeholders_Registry) (Social API Registry: B2G/B2B + культурний шар — лісники, ДСНС, митці; non-hot-path)
