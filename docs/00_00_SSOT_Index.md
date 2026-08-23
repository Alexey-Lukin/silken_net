# 🌍 SilkenNet — Single Source of Truth (SSOT)

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/13358/badge)](https://www.bestpractices.dev/projects/13358)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/Alexey-Lukin/silken_net/badge)](https://securityscorecards.dev/viewer/?uri=github.com/Alexey-Lukin/silken_net)

> _"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."_

Ласкаво просимо до Головного Архітектурного Реєстру проєкту **SilkenNet** — Єдиного Джерела Істини (SSOT) для розробки кіберфізичної D-MRV системи, спроєктованої на планетарний масштаб. ⚠️ **Масштаб тут — ціль, ПРОТИ якої міряємо, а не заява про поточну спроможність:** сьогодні System TRL = 3 (гейт — анкер/EBFC), у лісі нуль вузлів; чесний per-domain стан — [`00_03`](00_03_TRL_Matrix_HIL_and_Beyond). ⚠️ **SSOT живе в `docs/` репозиторію**; Wiki — детермінована one-way генерація з нього (правка через web-інтерфейс буде затерта наступним sync), тож ця сторінка = дзеркало `00_00`, а не джерело — стандарт [`00_06`](00_06_SSOT_Documentation_Standard).

Система побудована за принципами **Zero-Trust** та **«нульового лагу»** — де «нульовий лаг» означає **event-driven реакцію без polling-затримки на рівні заліза** (DMA/EXTI async-wakeup + RTC-WUT розклад — канон wake-source [`03_01 §1.10`](03_01_Firmware_Lifecycle_and_DMA); `VBAT_OK` — апаратний живлення-гейт, [`02_03 §7`](02_03_BQ25570_MPPT_Nano_Power)), а **не** миттєвість end-to-end: сама система **свідомо асинхронна** (STOP2-сон ~99 % часу, батчинг на Королеві, governance-timelock 48 год). Будь-який код, згенерований ШІ, або фізичний прототип, створений підрядником, повинен суворо відповідати документації на цих сторінках.

> **Структура SSOT — двошарова.** **Модуль 00 — Фундамент** (read-first мета-лінза): *НАВІЩО* (візія/місія/дорожня карта, NaaS-умови, академічні партнери та IP) та *ЯК* (методологія, TRL, governance процесу) ми будуємо — плюс конституція всієї системи (карта нижче). **Tier I (Система, 01–06)** — інженерний канон того, *ЩО* ми будуємо: вертикальний стек шарів (01 анкер у дереві → 06 інфраструктура). Стандарт самих доків — [`00_06`](00_06_SSOT_Documentation_Standard).

---

# 🧭 Модуль 00 — Фундамент (Foundation: Візія + Метод)

_Read-first мета-лінза проєкту: **НАВІЩО** (візія, місія, дорожня карта; NaaS-пропозиція, академічна валідація та IP-постава) і **ЯК** (методологія AI-Native, NASA TRL, governance процесу, стандарт SSOT-доків) ми будуємо — плюс **конституція всієї системи** (карта 8 рівнів нижче). Деталі кожного рівня розкриваються у профільних модулях Tier I (01–06), і партнерська R&D-субстанція їх реферить, а не дублює; культурний шар (митці) — `cultural_layer.md`._

## 🗺️ Системна Карта: 8 Рівнів Кіберфізики (The Constitution)

_Top-down конституція системи: дані течуть знизу вгору — від біохімії дерева до фіналізації в Ethereum L1. Кожен рівень розгортається у профільному модулі Tier I (01–06). Повний **Proof-of-Growth конвеєр** (кроки A–F) — канонічно [`05_02`](05_02_Proof_of_Growth_Pipeline) (операційний потік) + [`05_01 §1–2`](05_01_Multichain_Architecture) (ролі 12 мереж); політика resilience/failover — [`06_08`](06_08_Resilience_and_Failover_Policy). Методологія/процес, а віднедавна й економіка з партнерствами — цей Модуль 00 (Фундамент, сторінки нижче); BOM-рол-ап і юніт-економіка — при залізі, [`02_06`](02_06_Unit_Economics_and_BOM)._

| Рівень | Сутність | Канон |
|--------|----------|-------|
| **1. Біофізика (The Root)** | Тризонний коаксіальний анкер Ti-6Al-4V + EBFC Gen 2.0 (dgrFAD-GDH анод + Laccase/ZIF катод, цвітеріонна мембрана) → >500 mV прямо з метаболізму дерева, без зовнішніх дротів | [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK) · [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) · [`01_04`](01_04_CODIT_and_Xylemointegration) |
| **2. Апаратура (The Capsule)** | Герметична капсула, blind-mate Pogo Pins до анкера, BQ25570 MPPT + іоністор 0.47F/5.5V, акустичний п'єзо-тригер пробудження (Zero-Power Wake) | [`02_01`](02_01_Hardware_Architecture_and_BOM) · [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface) · [`02_03`](02_03_BQ25570_MPPT_Nano_Power) |
| **3. Прошивка / Edge AI (The Brain)** | STM32WLE5JC, STOP2 RTC-only (🟡 **300 nA — таргет, не вимір**; bench-гейт [`00_07`](00_07_Action_Plan_Tracker) FW.54), DMA-мікрофон, TinyML (тиша/вітер/пилка), mruby Lorenz-атрактор, апаратний AES-128 (LoRa-payload), factory provisioning ключів | [`03_01`](03_01_Firmware_Lifecycle_and_DMA) · [`03_03`](03_03_TinyML_Acoustic_Inference) · [`03_04`](03_04_mruby_Lorenz_Attractor) · [`03_05`](03_05_Hardware_Symmetric_Crypto_and_Security) · [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning) |
| **4. Мережа (The Veins)** | LoRa 868 МГц, **star-only** (ухвала FW.2 (а) — TTL-flood mesh гейтовано в CCM-ері; повернення = wire-rev3, [`00_07`](00_07_Action_Plan_Tracker) ARCH.43); Queen-шлюз агрегує пакети → CoAP-батч (**AES-256-CBC**) у хмару (опц. Starlink D2C); 🟡 Helium-fallback + Q2Q backhaul — **target, не в польоті** (ARCH.34 / ARCH.10) | [`02_05`](02_05_Queen_Hardware_and_Starlink) · [`03_02`](03_02_Queen_Gateway_Firmware) · failover [`06_08`](06_08_Resilience_and_Failover_Policy) |
| **5. Серверне ядро (The Engine)** | Rails 8.1 Omakase + PostgreSQL + Sidekiq: декодування L3, REST API, бізнес-логіка NaaS-контрактів | Модуль 04 ([`04_01`](04_01_Data_Models_and_Entities) · [`04_02`](04_02_Business_Logic_and_Services)) |
| **6. Верифікація (The Truth)** | peaq Machine DID (паспорт дерева) + IoTeX W3bstream ZK-proofs (pipeline-integrity + peaq-DID binding — hardware-origin = North-Star, не доведено; + гомеостаз Лоренца) + Streamr/Filecoin | [`05_01`](05_01_Multichain_Architecture) · [`05_02`](05_02_Proof_of_Growth_Pipeline) |
| **7. Фінанси (The Ledger)** | Polygon EVM — mint SCC/SFC; Chainlink DON oracle; Solana/Celo мікро-рейки; KlimaDAO ESG retirement; Polygon Hadron KYC (ERC-3643) | [`05_01`](05_01_Multichain_Architecture) · [`05_03`](05_03_Tokenomics_SCC_and_SFC) |
| **7.5 Governance (The Parliament)** | On-chain: `SilkenGovernor` + `SilkenTimelock` (48h) + `ProtocolParameters` (registry параметрів), Flash-Loan-захист | [`05_06`](05_06_Governance_and_DAO) |
| **8. Фіналізація (The Anchor)** | Ethereum L1 — щотижневий SHA-256 state root усієї економіки (rollup-стиль гарантія від збоїв сайдчейнів) | [`05_04`](05_04_Ethereum_L1_State_Anchor) |

### 🌐 Топологія Мережі (High-Level)

```
Soldier (Tree)         Soldier (Tree)         Soldier (Tree)
      │ LoRa                │ LoRa                 │ LoRa      ← star-only
      ▼                     ▼                      ▼
   Queen (Gateway)   ◄╌╌ Q2Q backhaul ╌╌►   Queen (Gateway)    ← 🟡 ARCH.10, не в польоті
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

> **Порядок тут — не абетковий і не за важливістю, це ДУГА ЧИТАННЯ, і номери її кодують** (founder-формулювання, ратифіковано 2026-08-22): навіщо → з ким → де ми → за що → як працюємо → як пишемо → що лишилось. `00_01` візія · `00_02` академ-партнери та IP · `00_03` TRL-чесність · `00_04` NaaS і чим платять · `00_05` як ми працюємо · `00_06` як пишемо доки · `00_07` що відкрито. `06_07` слота в дузі не має — це модуль 06, який читається як фундамент, і стоїть він при «як пишемо». ⚠️ Призначення слотів **виміряне, а не вибране**, тож переставляння рядка тут мовчки ламає дугу — саме так і сталось при заселенні `00_05` 2026-08-22.

- [`00_01` — Vision Mission and Roadmap](00_01_Vision_Mission_and_Roadmap) (Місія, проблема VCM, науковий підхід, NaaS, дорожня карта, Proof-of-Growth; філософія Slashing → 05_05)
- [`00_02` — Academic Integration and IP](00_02_Academic_Integration_and_IP) (Реєстр 5 ВНЗ + спільні публікації + IP-постава + бренд-архітектура)
- [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) (Шкала NASA TRL + канон per-module матриці · per-domain TRL · HIL-симулятори · критерій закриття задачі та TRL Gate Events; шкали SRL/MRL за межами TRL 9)
- [`00_04` — Nature as a Service Contracts](00_04_Nature_as_a_Service_Contracts) (NaaS контракти · параметричне страхування · фінансові константи · юридичні події → on-chain)
- [`00_05` — AI-Native Operating Model](00_05_AI_Native_Operating_Model) (Як ми працюємо: яруси інструкцій · хребет задачі · закриваючий свіп · дисципліна перевірки · агенти)
- [`06_07` — CICD and Runbook Index](06_07_CICD_and_Runbook_Index) (CI/IaC-політика: SSOT-Guard · Solidity audit · Labels-as-Code · supply-chain hardening)
- [`00_06` — SSOT Documentation Standard](00_06_SSOT_Documentation_Standard) (Стандарт канон-доків: skeleton + home-registry + drift-tooling + restructure-метод; 🚦 Validation Gate і AI-ростер — §5/§5.1)
- [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) (🔴 Живий документ — аудит блокерів, план дій, Sprint tracking)

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
- [`02_03` — BQ25570 MPPT Nano Power](02_03_BQ25570_MPPT_Nano_Power) (BQ25570 MPPT нано-потужність + пряме живлення від EBFC + EDLC-буфер іоністор 0.47Ф / 5.5В §12)
- [`02_04` — Bench Build & Test Guide](02_04_Bench_Build_Guide) (🔧 Живий bench build+test guide — повний Soldier поблоково на макетці: harvester-фронт + production sense/SE/radio на LoRa-E5)
- [`02_05` — Queen Hardware and Starlink](02_05_Queen_Hardware_and_Starlink) (Шлюз Королева + SIM7070G + Starlink Direct-to-Cell)
- [`02_06` — Unit Economics and BOM](02_06_Unit_Economics_and_BOM) (BOM Soldier/Queen · CAPEX/OPEX кластера · ROI-waterfall · supply chain — виділено з `00_04` 2026-08-22, DOC-T.83, поруч із залізом, яке рахує)

## 🧠 Модуль 03: Прошивка та Edge AI (The Brain)

_Логіка STM32WLE5JC: STOP2 / DMA / TinyML / mruby Lorenz / апаратний AES — Soldier і Queen firmware._

- [`03_01` — Firmware Lifecycle and DMA](03_01_Firmware_Lifecycle_and_DMA) (Soldier цикл Phase 0-5, Watchdog, STOP2, RX-вікно, RTC reg-map)
- [`03_02` — Queen Gateway Firmware](03_02_Queen_Gateway_Firmware) (Queen LoRa RX → CIFO → CoAP flush)
- [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) (INT8 pure-C forward-pass + CMSIS-DSP log-mel: класифікація пилки/кавітації/тиші)
- [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) (mruby VM атрактор хаосу — гомеостаз дерева; канон Lorenz-констант)
- [`03_05` — Hardware Symmetric Crypto and Security](03_05_Hardware_Symmetric_Crypto_and_Security) (LoRa AES-128-CCM + CoAP AES-256-CBC + SE050 Secure Element + Flash Key + RDP + PQC roadmap)
- [`03_06` — Factory Flashing and Key Provisioning](03_06_Factory_Flashing_and_Key_Provisioning) (фабричний флешинг Гілки A/B + HKDF per-device ключі + per-cluster K_ota/KEYB + Lorenz K_seed SEC.11 + OTA-HMAC FW.23 + factory-ops SEC.3)

## 🗄️ Модуль 04: Серверне Ядро (Web2 Backend)

_Rails 8.1 Omakase: моделі даних, бізнес-логіка, REST API, Phlex UI та тестова матриця._

- [`04_01` — Data Models and Entities](04_01_Data_Models_and_Entities) (ActiveRecord моделі, PostgreSQL-схема, RANGE-partitioning)
- [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) (Service Objects + Sidekiq воркери, Web3CircuitBreaker, doc↔code sync)
- [`04_03` — REST API v1 Reference](04_03_REST_API_v1_Reference) (REST API v1, Pagy, Idempotency-Key, RBAC)
- [`04_04` — Phlex UI and Tailwind](04_04_Phlex_UI_and_Tailwind) (Phlex компоненти + Tailwind 4 + gaia design tokens + i18n)
- [`04_06` — Testing Guide and Coverage](04_06_Testing_Guide_and_Coverage) — ⚠️ **крос-доменний, попри номер модуля**: методологія й карта покриття ВСІХ шарів (RSpec · firmware C · Foundry Solidity), на нього реферять `03_02`/`05_04`/`CLAUDE.md §8`. Частина A — RSpec/Phlex-конвенції; Частина B — gap-аналіз ризиків покриття. Дім і присуд про номер — [`00_06 §2`](00_06_SSOT_Documentation_Standard)

## ⛓️ Модуль 05: Web3 та Економіка (The Ledger)

_DePIN-стек, Proof of Growth pipeline, токеноміка SCC/SFC, slashing/governance та фіналізація в Ethereum L1._

- [`05_01` — Multichain Architecture](05_01_Multichain_Architecture) (**Core DePIN**: peaq + IoTeX + Chainlink + Polygon + **Filecoin** — audit-critical immutable archive [нот.18: НЕ optional як Solana/Celo; E.60 Фаза 1б SHIPPED — `archive_root` = **Merkle-witness** мінт-диспатчів → формально Core; пін наразі Pinata IPFS, Filecoin-deal = майбутнє] · **Expansion** [optional]: Solana / Celo / KlimaDAO)
- [`05_02` — Proof of Growth Pipeline](05_02_Proof_of_Growth_Pipeline) (Повний uplink → oracle → mint flow + Dynamic Tax)
- [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) (SCC ERC-20 + SFC governance-токен + Dynamic Tax)
- [`05_04` — Ethereum L1 State Anchor](05_04_Ethereum_L1_State_Anchor) (Щотижневий Merkle state root — leaf0-агрегат + телеметрія-субкорені — в Ethereum mainnet)
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
