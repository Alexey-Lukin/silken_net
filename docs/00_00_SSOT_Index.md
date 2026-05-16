# 🌍 Gaia 2.0 (Silken Net) — Single Source of Truth (SSOT)

> _"Ми не просто спостерігаємо за лісом. Ми даємо йому цифрову волю."_

Ласкаво просимо до Головного Архітектурного Реєстру проєкту **Silken Net**. Ця Wiki є Єдиним Джерелом Істини (SSOT) для розробки кіберфізичної D-MRV системи планетарного масштабу.

Система побудована за принципами **Zero-Trust** та **Нульового Лагу**. Будь-який код, згенерований ШІ, або фізичний прототип, створений підрядником, повинен суворо відповідати документації на цих сторінках.

---

## 🧭 Модуль 00: Архітектура, Стратегія та Операції (The Codex)

_Бізнес-візія, кіберфізична архітектура, політики resilience, операційна система проєкту (Shape Up + TRL + GitHub IaC) та живий backlog задач._

- [00\_01\_Vision\_Market\_and\_Slashing\_Policy](00_01_Vision_Market_and_Slashing_Policy) (Місія, проблема VCM, NaaS, Slashing v2 — negligence vs force-majeure)
- [00\_02\_System\_Architecture\_and\_12\_Chain\_Pipeline](00_02_System_Architecture_and_12_Chain_Pipeline) (8 рівнів кіберфізики + повний 12-крокової конвеєр Proof-of-Growth)
- [00\_03\_Resilience\_and\_Failover\_Policy](00_03_Resilience_and_Failover_Policy) (Queen failover 4 рівні + Per-Chain Fallback Matrix для 12 ланок Web3)
- [00\_04\_AI\_Native\_Engineering\_and\_TRL](00_04_AI_Native_Engineering_and_TRL) (Філософія: TRL метрика, Intent-First, Wiki-First, AI Pipeline)
- [00\_05\_Shape\_Up\_Operations\_and\_RnD\_Clusters](00_05_Shape_Up_Operations_and_RnD_Clusters) (Операційний template: 6+2 цикли, 4 R&D кластери, Betting Table, Async-Review)
- [00\_06\_Strategic\_Roadmap\_and\_HIL\_Simulators](00_06_Strategic_Roadmap_and_HIL_Simulators) (TRL Matrix + per-domain TRL + HIL-симулятори, які знімають TRL-Lock)
- [00\_07\_GitHub\_Projects\_and\_IaC\_Automation](00_07_GitHub_Projects_and_IaC_Automation) (Projects V2 fields + Labels-as-Code + GitHub Actions workflows)
- [00\_08\_Action\_Plan\_Tracker](00_08_Action_Plan_Tracker) (🔴 Живий документ — аудит блокерів, план дій, Sprint tracking)

## 🟢 Модуль 01: Біомеханіка та Хімія (The Anchor)

_Все, що фізично інтегрується в живе дерево — тризонний коаксіальний анкер, EBFC та ксилемоінтеграція._

- [01\_01\_Coaxial\_Gyroid\_Topology\_and\_PEEK](01_01_Coaxial_Gyroid_Topology_and_PEEK) (3-зонний дизайн анкера: Ti-гіроїд + PEEK-терморозрив + катодний фланець)
- [01\_02\_Ti\_6Al\_4V\_Metallurgy\_and\_DMLS](01_02_Ti_6Al_4V_Metallurgy_and_DMLS) (DMLS друк металу + HIP + відпал)
- [01\_03\_EBFC\_Enzymatic\_Bio\_Fuel\_Cell](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) (Двошарова GOx+Catalase / GDH-альтернатива + Laccase-AuNP DET — >500 mV з глюкози)
- [01\_04\_CODIT\_and\_Xylemointegration](01_04_CODIT_and_Xylemointegration) (Біологічна реакція дерева на імплантат + anti-overgrowth shield катода)

## 🟡 Модуль 02: Апаратне Забезпечення (The Capsule)

_Електроніка Soldier/Queen, енергетичні буфери, механіка blind-mate підключення та опціональна Starlink-uplink._

- [02\_01\_Hardware\_Architecture\_and\_BOM](02_01_Hardware_Architecture_and_BOM) (BOM капсули Солдата + ASCII power tree)
- [02\_02\_Blind\_Mate\_Pogo\_Pin\_Interface](02_02_Blind_Mate_Pogo_Pin_Interface) (Сліпий магнітний конектор Pogo-Pin до коаксіального анкера)
- [02\_03\_BQ25570\_MPPT\_Nano\_Power](02_03_BQ25570_MPPT_Nano_Power) (BQ25570 MPPT нано-потужність + пряме живлення від EBFC)
- [02\_03\_appendix\_legacy\_breadboard](02_03_appendix_legacy_breadboard) (Додаток: legacy breadboard configurations для архіву)
- [02\_04\_EDLC\_Supercapacitor\_Buffer](02_04_EDLC_Supercapacitor_Buffer) (Іоністор 0.47Ф / 5.5В)
- [02\_05\_Queen\_Hardware\_and\_Starlink](02_05_Queen_Hardware_and_Starlink) (Шлюз Королева + SIM7070G + Starlink Direct-to-Cell)

## 🔵 Модуль 03: Прошивка та Edge AI (The Brain)

_Логіка STM32WLE5JC: STOP2 / DMA / TinyML / mruby Lorenz / апаратний AES — Soldier і Queen firmware._

- [03\_01\_Firmware\_Lifecycle\_and\_DMA](03_01_Firmware_Lifecycle_and_DMA) (Soldier цикл Phase 0-5, Watchdog, STOP2, RX-вікно)
- [03\_02\_Queen\_Gateway\_Firmware](03_02_Queen_Gateway_Firmware) (Queen LoRa RX → CIFO → CoAP flush)
- [03\_03\_TinyML\_Acoustic\_Inference](03_03_TinyML_Acoustic_Inference) (CMSIS-NN: класифікація пилки/кавітації/тиші)
- [03\_04\_mruby\_Lorenz\_Attractor](03_04_mruby_Lorenz_Attractor) (mruby VM атрактор хаосу — гомеостаз дерева)
- [03\_05\_Hardware\_AES256\_and\_Security](03_05_Hardware_AES256_and_Security) (CRYP-блок AES-256 ECB/CBC + Flash Key + RDP Level 2)

## 🟣 Модуль 04: Серверне Ядро (Web2 Backend)

_Rails 8.1 Omakase, моделі, бізнес-логіка, REST API, Phlex UI та тестова матриця._

- [04\_01\_Data\_Models\_and\_Entities](04_01_Data_Models_and_Entities) (26 ActiveRecord моделей, PostgreSQL схема, partitioning)
- [04\_02\_Business\_Logic\_and\_Services](04_02_Business_Logic_and_Services) (29+ сервісів, 31 воркер, Web3CircuitBreaker, Drift Register)
- [04\_03\_REST\_API\_v1\_Reference](04_03_REST_API_v1_Reference) (82 REST ендпоінти, Pagy, Idempotency-Key)
- [04\_04\_Phlex\_UI\_and\_Tailwind](04_04_Phlex_UI_and_Tailwind) (Phlex компоненти + Tailwind 4 + gaia design tokens)
- [04\_05\_Codex\_Lore\_Module](04_05_Codex_Lore_Module) (Lore Layer Codex: 4 Realm × 79 Nodes, Fractions, Battle, Discovery)
- [04\_06\_Testing\_Guide\_and\_Coverage](04_06_Testing_Guide_and_Coverage) (30 RSpec best practices + повна Coverage Matrix: RSpec/Firmware C/Foundry Solidity)

## 🟠 Модуль 05: Web3 та Економіка (The Ledger)

_12-chain DePIN стек, Proof of Growth pipeline, токеноміка SCC/SFC та фіналізація в Ethereum L1._

- [05\_01\_Multichain\_Architecture](05_01_Multichain_Architecture) (12 мереж: peaq + IoTeX + Chainlink + Polygon + Solana + Celo + KlimaDAO + ...)
- [05\_02\_Proof\_of\_Growth\_Pipeline](05_02_Proof_of_Growth_Pipeline) (Повний uplink → oracle → mint flow + Dynamic Tax)
- [05\_03\_Tokenomics\_SCC\_and\_SFC](05_03_Tokenomics_SCC_and_SFC) (SCC ERC-20 + SFC governance + slashing parameters)
- [05\_04\_Ethereum\_L1\_State\_Anchor](05_04_Ethereum_L1_State_Anchor) (Щотижневий SHA-256 state root в Ethereum mainnet)

## ⚙️ Модуль 06: DevOps та Інфраструктура (The Matrix)

_Деплой, моніторинг, секрети та децентралізовані обчислення (Akash + GCP failover)._

- [06\_01\_Deployment\_Kamal\_Terraform](06_01_Deployment_Kamal_Terraform) (Kamal + Terraform GCP, Canopy vs Production)
- [06\_02\_Akash\_Network\_Integration](06_02_Akash_Network_Integration) (SDL 2.0 манифест + multi-provider failover)
- [06\_03\_Prometheus\_Observability](06_03_Prometheus_Observability) (20 метрик + Grafana Cloud + Alerting)
- [06\_04\_Secrets\_Checklist](06_04_Secrets_Checklist) (Інвентаризація секретів: GitHub Secrets, Kamal, Akash, Terraform)
- [06\_05\_Puma\_Configuration](06_05_Puma_Configuration) (Puma 8 IO-bound pool + кластерні хуки + runbook'и)

## 🟤 Модуль 07: Економіка та Бізнес (Nature-as-a-Service)

_Юриспруденція, юніт-економіка та портфель грантових заявок._

- [07\_01\_Nature\_as\_a\_Service\_Contracts](07_01_Nature_as_a_Service_Contracts) (NaaS контракти + параметричне страхування)
- [07\_02\_Unit\_Economics\_and\_BOM](07_02_Unit_Economics_and_BOM) (Юніт-економіка + ROI через SCC)
- [07\_03\_Grant\_Applications\_Tracker](07_03_Grant_Applications_Tracker) (Трекер грантових заявок — Horizon Europe, Verra, Gold Standard)

## 🎓 Модуль 08: Академічна Інтеграція (University Research Hub)

_Завдання для лабораторій ЧНУ ФОТІУС, ЧДТУ, ЧІПБ, ЧМА та СЄУ (TRL 1-4)._

- [08\_01\_University\_R\_and\_D\_Protocols](08_01_University_R_and_D_Protocols) (Chemistry & Physics protocols для ЧНУ)
- [08\_02\_Cybernetic\_and\_Mathematical\_Validation](08_02_Cybernetic_and_Mathematical_Validation) (FOTIUS Hub: кібернетична та математична валідація)
- [08\_03\_Joint\_Publications\_and\_IP\_Strategy](08_03_Joint_Publications_and_IP_Strategy) (Спільні публікації + патентна стратегія)
- [08\_04\_CHDTU\_Data\_Science\_Collaboration](08_04_CHDTU_Data_Science_Collaboration) (ЧДТУ: Data Science, статистика, GA-оптимізація)
- [08\_05\_CHIPB\_Fire\_Safety\_Integration](08_05_CHIPB_Fire_Safety_Integration) (ЧІПБ: пожежна безпека + параметричне страхування + SOP)
- [08\_06\_CHMA\_Biomedical\_Integration](08_06_CHMA_Biomedical_Integration) (ЧМА: біохімія EBFC, токсикологія Ti, ксилемоінтеграція)
- [08\_07\_SEU\_Economics\_and\_Legal\_Integration](08_07_SEU_Economics_and_Legal_Integration) (СЄУ: токеноміка NaaS + RWA-легалізація + промисловий дизайн)
