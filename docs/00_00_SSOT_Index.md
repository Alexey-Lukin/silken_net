# 🌍 Gaia 2.0 (Silken Net) — Single Source of Truth (SSOT)

> _"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."_

Ласкаво просимо до Головного Архітектурного Реєстру проєкту **Silken Net**. Ця Wiki є Єдиним Джерелом Істини (SSOT) для розробки кіберфізичної D-MRV системи планетарного масштабу.

Система побудована за принципами **Zero-Trust** та **Нульового Лагу**. Будь-який код, згенерований ШІ, або фізичний прототип, створений підрядником, повинен суворо відповідати документації на цих сторінках.

> **Структура SSOT — дворівнева.** **Tier I (Система)** — інженерний канон того, *ЩО* ми будуємо: архітектура + вертикальний стек шарів (01 анкер → 06 інфраструктура). **Tier II (Програма)** — *ЯК і НАВІЩО*: стратегія/економіка, академічні партнерства, методологія/governance довкола системи. Стандарт самих доків — [`09_05`](09_05_SSOT_Documentation_Standard).

---

# 🏛️ Tier I — Система (The Blueprint)

## 🗺️ Системна Карта: 8 Рівнів Кіберфізики (The Constitution)

_Top-down конституція системи: дані течуть знизу вгору — від біохімії дерева до фіналізації в Ethereum L1. Кожен рівень розгортається у профільному модулі Tier I (01–06). Повний **12-крокового Proof-of-Growth конвеєр** — канонічно [`05_02`](05_02_Proof_of_Growth_Pipeline) (операційний потік) + [`05_01 §1–2`](05_01_Multichain_Architecture) (ролі 12 мереж); політика resilience/failover — [`06_08`](06_08_Resilience_and_Failover_Policy). Методологія/стратегія — Tier II (07/09)._

| Рівень | Сутність | Канон |
|--------|----------|-------|
| **1. Біофізика (The Root)** | Тризонний коаксіальний анкер Ti-6Al-4V + EBFC Gen 2.0 (dgrFAD-GDH анод + Laccase/ZIF катод, цвітеріонна мембрана) → >500 mV прямо з метаболізму дерева, без зовнішніх дротів | [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK) · [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) · [`01_04`](01_04_CODIT_and_Xylemointegration) |
| **2. Апаратура (The Capsule)** | Герметична капсула, blind-mate Pogo Pins до анкера, BQ25570 MPPT + іоністор 0.47F/5.5V, п'єзо-тригер пробудження | [`02_01`](02_01_Hardware_Architecture_and_BOM) · [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface) · [`02_03`](02_03_BQ25570_MPPT_Nano_Power) |
| **3. Прошивка / Edge AI (The Brain)** | STM32WLE5JC, STOP2 RTC-only **300 nA**, DMA-мікрофон, TinyML (тиша/вітер/пилка), mruby Lorenz-атрактор, апаратний AES-128 (LoRa) / AES-256-CBC (CoAP) | [`03_01`](03_01_Firmware_Lifecycle_and_DMA) · [`03_03`](03_03_TinyML_Acoustic_Inference) · [`03_04`](03_04_mruby_Lorenz_Attractor) · [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security) |
| **4. Мережа (The Veins)** | LoRa mesh 868 МГц (custom TTL-based); Queen-шлюз агрегує пакети → CoAP у хмару (опц. Starlink D2C); Helium як fallback при втраті Queen | [`02_05`](02_05_Queen_Hardware_and_Starlink) · [`03_02`](03_02_Queen_Gateway_Firmware) · failover [`06_08`](06_08_Resilience_and_Failover_Policy) |
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

> **📐 Модуль 00 → Foundation.** Технічна архітектура тепер живе в цій системній карті (вище). Сам Модуль 00 ре-деривується у **Фундамент (Візія + Метод)** у межах поточної таксономічної реструктуризації — сторінки Vision + методологія приземляться сюди наступною фазою.

## 🌱 Модуль 01: Біомеханіка та Хімія (The Anchor)

_Все, що фізично інтегрується в живе дерево — тризонний коаксіальний анкер, EBFC та ксилемоінтеграція._

- [01\_01\_Coaxial\_Gyroid\_Topology\_and\_PEEK](01_01_Coaxial_Gyroid_Topology_and_PEEK) (3-зонний дизайн анкера: Ti-гіроїд + PEEK-терморозрив + катодний фланець)
- [01\_02\_Ti\_6Al\_4V\_Metallurgy\_and\_DMLS](01_02_Ti_6Al_4V_Metallurgy_and_DMLS) (DMLS друк металу + HIP + відпал)
- [01\_03\_EBFC\_Enzymatic\_Bio\_Fuel\_Cell](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) (EBFC Gen 2.0: dgrFAD-GDH анод + Laccase/ZIF катод + цвітеріонна мембрана — >500 mV, 20–25 років)
- [01\_04\_CODIT\_and\_Xylemointegration](01_04_CODIT_and_Xylemointegration) (Біологічна реакція дерева на імплантат + anti-overgrowth shield катода)

## ⚡ Модуль 02: Апаратне Забезпечення (The Capsule)

_Електроніка Soldier/Queen, енергетичні буфери, механіка blind-mate підключення та опціональна Starlink-uplink._

- [02\_01\_Hardware\_Architecture\_and\_BOM](02_01_Hardware_Architecture_and_BOM) (BOM капсули Солдата + ASCII power tree)
- [02\_02\_Blind\_Mate\_Pogo\_Pin\_Interface](02_02_Blind_Mate_Pogo_Pin_Interface) (Сліпий магнітний конектор Pogo-Pin до коаксіального анкера)
- [02\_03\_BQ25570\_MPPT\_Nano\_Power](02_03_BQ25570_MPPT_Nano_Power) (BQ25570 MPPT нано-потужність + пряме живлення від EBFC)
- [02\_04\_EDLC\_Supercapacitor\_Buffer](02_04_EDLC_Supercapacitor_Buffer) (Іоністор 0.47Ф / 5.5В)
- [02\_05\_Queen\_Hardware\_and\_Starlink](02_05_Queen_Hardware_and_Starlink) (Шлюз Королева + SIM7070G + Starlink Direct-to-Cell)
- [02\_06\_Legacy\_Breadboard\_Appendix](02_06_Legacy_Breadboard_Appendix) (📦 Архів: legacy LTC3108 breadboard-прототип — НЕ виробнича архітектура)

## 🧠 Модуль 03: Прошивка та Edge AI (The Brain)

_Логіка STM32WLE5JC: STOP2 / DMA / TinyML / mruby Lorenz / апаратний AES — Soldier і Queen firmware._

- [03\_01\_Firmware\_Lifecycle\_and\_DMA](03_01_Firmware_Lifecycle_and_DMA) (Soldier цикл Phase 0-5, Watchdog, STOP2, RX-вікно, RTC reg-map)
- [03\_02\_Queen\_Gateway\_Firmware](03_02_Queen_Gateway_Firmware) (Queen LoRa RX → CIFO → CoAP flush)
- [03\_03\_TinyML\_Acoustic\_Inference](03_03_TinyML_Acoustic_Inference) (CMSIS-NN: класифікація пилки/кавітації/тиші)
- [03\_04\_mruby\_Lorenz\_Attractor](03_04_mruby_Lorenz_Attractor) (mruby VM атрактор хаосу — гомеостаз дерева; канон Lorenz-констант)
- [03\_05\_Hardware\_Symmetric\_Crypto\_and\_Security](03_05_Hardware_Symmetric_Crypto_and_Security) (LoRa AES-128-CCM + CoAP AES-256-CBC + ATECC608B + Flash Key + RDP + PQC roadmap)

## 🗄️ Модуль 04: Серверне Ядро (Web2 Backend)

_Rails 8.1 Omakase: моделі даних, бізнес-логіка, REST API, Phlex UI та тестова матриця._

- [04\_01\_Data\_Models\_and\_Entities](04_01_Data_Models_and_Entities) (ActiveRecord моделі, PostgreSQL-схема, RANGE-partitioning)
- [04\_02\_Business\_Logic\_and\_Services](04_02_Business_Logic_and_Services) (Service Objects + Sidekiq воркери, Web3CircuitBreaker, Drift Register)
- [04\_03\_REST\_API\_v1\_Reference](04_03_REST_API_v1_Reference) (REST API v1, Pagy, Idempotency-Key, RBAC)
- [04\_04\_Phlex\_UI\_and\_Tailwind](04_04_Phlex_UI_and_Tailwind) (Phlex компоненти + Tailwind 4 + gaia design tokens + i18n)
- [04\_05\_Codex\_Lore\_Module](04_05_Codex_Lore_Module) (Codex — read-only наративний шар над телеметрією; ADR-зафіксований, поза hot-path)
- [04\_06\_Testing\_Guide\_and\_Coverage](04_06_Testing_Guide_and_Coverage) (RSpec best practices + Coverage Matrix: RSpec/Firmware C/Foundry Solidity)

## ⛓️ Модуль 05: Web3 та Економіка (The Ledger)

_DePIN-стек, Proof of Growth pipeline, токеноміка SCC/SFC, slashing/governance та фіналізація в Ethereum L1._

- [05\_01\_Multichain\_Architecture](05_01_Multichain_Architecture) (**Core DePIN**: peaq + IoTeX + Chainlink + Polygon · **Expansion**: Solana / Celo / KlimaDAO / Filecoin)
- [05\_02\_Proof\_of\_Growth\_Pipeline](05_02_Proof_of_Growth_Pipeline) (Повний uplink → oracle → mint flow + Dynamic Tax)
- [05\_03\_Tokenomics\_SCC\_and\_SFC](05_03_Tokenomics_SCC_and_SFC) (SCC ERC-20 + SFC governance-токен + Dynamic Tax)
- [05\_04\_Ethereum\_L1\_State\_Anchor](05_04_Ethereum_L1_State_Anchor) (Щотижневий SHA-256 state root в Ethereum mainnet)
- [05\_05\_Slashing\_and\_Risk\_Policy](05_05_Slashing_and_Risk_Policy) (Політика штрафів: negligence/force-majeure/indeterminate + формула + insurance + anti-fraud)
- [05\_06\_Governance\_and\_DAO](05_06_Governance_and_DAO) (On-chain governance: SilkenGovernor/Timelock/ProtocolParameters + Flash-Loan-захист)

## 🚀 Модуль 06: DevOps та Інфраструктура (The Matrix)

_Деплой, моніторинг, секрети та децентралізовані обчислення (Akash + GCP failover)._

- [06\_01\_Deployment\_Kamal\_Terraform](06_01_Deployment_Kamal_Terraform) (Kamal + Terraform GCP, Canopy vs Production)
- [06\_02\_Akash\_Network\_Integration](06_02_Akash_Network_Integration) (SDL 2.0 манифест + multi-provider failover)
- [06\_03\_Prometheus\_Observability](06_03_Prometheus_Observability) (Grafana Alloy → Grafana Cloud + Alerting)
- [06\_04\_Secrets\_Checklist](06_04_Secrets_Checklist) (Інвентаризація секретів: GitHub Secrets, Kamal, Akash, Terraform)
- [06\_05\_Puma\_Configuration](06_05_Puma_Configuration) (Puma 8 IO-bound pool + кластерні хуки + runbook'и)
- [06\_06\_Disaster\_Recovery\_and\_Backup](06_06_Disaster_Recovery_and_Backup) (Cloud SQL PITR/HA + restore-runbook'и + RTO/RPO + master-key backup)
- [06\_07\_CICD\_and\_Runbook\_Index](06_07_CICD_and_Runbook_Index) (CI/CD workflows + єдиний operations runbook-індекс)
- [06\_08\_Resilience\_and\_Failover\_Policy](06_08_Resilience_and_Failover_Policy) (Queen failover 4 рівні + Per-Chain Fallback Matrix для Web3-ланок — runtime resilience)

---

# 🌿 Tier II — Програма

## 💰 Модуль 07: Стратегія та Економіка (Strategy & Economics)

_Візія/місія/дорожня карта, NaaS-контракти, юніт-економіка, гранти та зовнішні стейкхолдери (B2G/B2B + культурний шар)._

- [07\_01\_Vision\_Mission\_and\_Roadmap](07_01_Vision_Mission_and_Roadmap) (Місія, проблема VCM, науковий підхід, NaaS, дорожня карта, Proof-of-Growth; філософія Slashing → 05_05)
- [07\_02\_Nature\_as\_a\_Service\_Contracts](07_02_Nature_as_a_Service_Contracts) (NaaS контракти + параметричне страхування + фінансові константи)
- [07\_03\_Unit\_Economics\_and\_BOM](07_03_Unit_Economics_and_BOM) (Юніт-економіка + ROI через SCC + Supply Chain Ukraine)
- [07\_04\_Grant\_Applications\_Tracker](07_04_Grant_Applications_Tracker) (Трекер грантових заявок — Horizon Europe, Verra, Gold Standard)
- [07\_05\_External\_Stakeholders\_Registry](07_05_External_Stakeholders_Registry) (Social API Registry: B2G/B2B + культурний шар — лісники, ДСНС, митці, журналісти; non-hot-path)

## 🔬 Модуль 08: Академічна Інтеграція (Academic & Partnerships)

_Партнерства ВНЗ (ЧНУ ФОТІУС, ЧДТУ, ЧІПБ, ЧМА, СЄУ) під рамкою MOIC: MoU, спільні публікації, IP-стратегія. (Доменна R&D-субстанція дисолюється у профільні модулі — Stage B.)_

- [08\_01\_University\_R\_and\_D\_Protocols](08_01_University_R_and_D_Protocols) (ЧНУ: chemistry & physics протоколи — Hard Science Layer)
- [08\_02\_Cybernetic\_and\_Mathematical\_Validation](08_02_Cybernetic_and_Mathematical_Validation) (ФОТІУС: кібернетична/математична валідація, GA/NSGA-II оптимізація)
- [08\_03\_Joint\_Publications\_and\_IP\_Strategy](08_03_Joint_Publications_and_IP_Strategy) (MOIC-рамка + спільні публікації + патентна стратегія)
- [08\_04\_CHDTU\_Data\_Science\_Collaboration](08_04_CHDTU_Data_Science_Collaboration) (ЧДТУ: Data Science, математична статистика, RF-верифікація, акустичний стенд)
- [08\_05\_CHIPB\_Fire\_Safety\_Integration](08_05_CHIPB_Fire_Safety_Integration) (ЧІПБ: пожежна безпека + параметричне страхування + SOP)
- [08\_06\_CHMA\_Biomedical\_Integration](08_06_CHMA_Biomedical_Integration) (ЧМА: біохімія EBFC, токсикологія Ti, ксилемоінтеграція)
- [08\_07\_SEU\_Economics\_and\_Legal\_Integration](08_07_SEU_Economics_and_Legal_Integration) (СЄУ: токеноміка NaaS + RWA-легалізація + промисловий дизайн)

## ⚙️ Модуль 09: Методологія та Governance (Methodology & Governance)

_Як ми будуємо: AI-Native/TRL філософія, Shape Up операції, GitHub IaC, стандарт SSOT-доків та живий backlog задач._

- [09\_01\_AI\_Native\_Engineering\_and\_TRL](09_01_AI_Native_Engineering_and_TRL) (Філософія: NASA TRL метрика, Intent-First, Wiki-First, AI Pipeline + Validation Gate)
- [09\_02\_TRL\_Matrix\_HIL\_and\_Beyond](09_02_TRL_Matrix_HIL_and_Beyond) (Канон per-module TRL-матриці + per-domain TRL + HIL-симулятори + Beyond-TRL-9 агенда)
- [09\_03\_Shape\_Up\_Operations\_and\_RnD\_Clusters](09_03_Shape_Up_Operations_and_RnD_Clusters) (Операційний template: 6+2 цикли, 4 R&D кластери, Betting Table, Async-Review)
- [09\_04\_GitHub\_Projects\_and\_IaC\_Automation](09_04_GitHub_Projects_and_IaC_Automation) (Projects V2 fields + Labels-as-Code + GitHub Actions workflows)
- [09\_05\_SSOT\_Documentation\_Standard](09_05_SSOT_Documentation_Standard) (Стандарт канон-доків: skeleton + home-registry + drift-tooling + restructure-метод)
- [09\_06\_Action\_Plan\_Tracker](09_06_Action_Plan_Tracker) (🔴 Живий документ — аудит блокерів, план дій, Sprint tracking)
