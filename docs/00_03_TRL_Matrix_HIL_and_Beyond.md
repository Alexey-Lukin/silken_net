# 00_03: TRL Matrix, HIL & Beyond-TRL-9

## 🎯 Мета

Канонічний дім **per-module TRL-матриці** (§1) та довгострокової R&D-агенди за межами TRL 9 (§7). Фіксує принцип **TRL-Layered-Independence** і HIL-симулятори — **програмні еквіваленти фізичного навантаження**, що дозволяють софт-доменам незалежно досягати свого *per-domain* TRL. ⚠️ HIL **НЕ «знімає» System-TRL-Lock** (той лишається обмеженим найнижчим модулем критичного шляху) — він лише декаплить per-domain прогрес. Стратегічна дорожня карта (фази масштабування) — у [`00_01`](00_01_Vision_Mission_and_Roadmap).

---

## ✅ Статус

- **Поточний TRL (System):** TRL 4 — EBFC TRL 3→4 PASSED (Zero-Lab 2026-05-25). Програмні домени TRL 6-9.
- **Per-domain TRL (декаплінг):** суть зняття TRL-Lock — програмні домени (Rails, Web3, Firmware, Security) рухаються до TRL 8–9 незалежно від фізичного відставання металу/хімії (anchor/EBFC **TRL 4**, Zero-Lab L1-L4 PASSED 2026-05-25; in vitro Stages 1-3 ще не закриті). **Канонічні per-module числа — `§1 Per-module TRL` нижче (єдиний дім; тут свідомо НЕ дублюються, щоб уникнути drift).** Оновлюється при кожному cool-down.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [00_01_Vision_Mission_and_Roadmap](00_01_Vision_Mission_and_Roadmap) | Бізнес-візія та slashing |
| [00_02_AI_Native_Engineering_and_TRL](00_02_AI_Native_Engineering_and_TRL) | AI-Native TRL philosophy (метрика прогресу) |
| [00_04_Shape_Up_Operations_and_RnD_Clusters](00_04_Shape_Up_Operations_and_RnD_Clusters) | Shape Up operations; §Async-Review TRL Gates |
| [00_05_GitHub_Projects_and_IaC_Automation](00_05_GitHub_Projects_and_IaC_Automation) | TRL Auto-Advancement (HIL → Projects V2 cards) |
| [04_06_Testing_Guide_and_Coverage](04_06_Testing_Guide_and_Coverage) | §B Coverage Matrix — HIL → RSpec/Firmware/Foundry coverage |
| [08_02_Academic_Institutions_Registry](08_02_Academic_Institutions_Registry) | Фізичні валідаційні протоколи ВНЗ (TRL 1-4) |
| [00_07_Action_Plan_Tracker](00_07_Action_Plan_Tracker) | **Відкриті блокери** (SSOT): Module 01 chemistry (HW.*), 06 DevOps deploy, 08 UNI.* |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Матриця готовності Silken Net (The TRL Matrix)](#-1-матриця-готовності-silken-net-the-trl-matrix)
- [3. Принцип "TRL-Lock" → "TRL-Layered Independence"](#-3-принцип-trl-lock--trl-layered-independence)
- [4. HIL Simulators — Програмне розблокування Software TRL](#-4-hil-simulators--програмне-розблокування-software-trl)
- [7. Beyond TRL 9 — Planetary Intelligence Gaps (Long-Horizon R&D Agenda)](#-7-beyond-trl-9--planetary-intelligence-gaps-long-horizon-rd-agenda)
- [8. Фрактальна Мережева Топологія — Planetary Network Scaling](#-8-фрактальна-мережева-топологія--planetary-network-scaling)
<!-- TOC:AUTO:END -->

---

## 📊 1. Матриця готовності Silken Net (The TRL Matrix)

Ми адаптували шкалу NASA TRL для кіберфізичних екосистем. Проєкт рухається від фундаментальної лабораторії до глобальної фіналізації.

| Рівень | Етап | Технічний критерій (Evidence) | Лабораторія / Хаб |
|:---|:---|:---|:---|
| **TRL 1-2** | Ідея / Принцип | Математичне обґрунтування EBFC та Атрактора Лоренца. | ЧНУ (Хімія/Фізика) |
| **TRL 3-4** | Proof of Concept | Валідація EBFC Gen 2.0 **>500 мВ** (OCV ~600 мВ > BQ25570 Cold-Start 330 мВ; `01_03`) → 3.3V boost та перша транзакція в Sandbox. *(«44 мВ» — застаріла гіпотеза streaming-potential/п'єзо, відкинута з Gen 2.0.)* | ЧНУ (ФОТІУС) |
| **TRL 5-6** | Прототипування | Робота кластера "Солдат-Королева" в Черкаському борі (30 днів). | Silken Lab |
| **TRL 7-8** | Кваліфікація | Повна інтеграція: DID → ZK-Proof → Chainlink → Polygon. | Production (Canopy) |
| **TRL 9** | Експлуатація | Стабільний мінтинг SCC на мільйонах вузлів, фіналізація в L1. | Global Mainnet |

### Per-module TRL (канонічне джерело)

> SSOT для per-domain TRL. **System TRL = найнижчий модуль критичного шляху (01–07 build-path)** — наразі 4 (модулі 01/02 — hardware-критичні). **Foundation (00)** = візія/метод (зрілі, TRL 9 — поза критичним шляхом, не гейтить). Модулі 08 (R&D-партнерства), 09 (PM-процес), 10 (Security-hardening) — це org/process/безпекова зрілість, яка трекається окремо і **не гейтить** System TRL (інакше System=2 за рахунок ранніх ВНЗ-партнерств, що хибно). Оновлюється при кожному cool-down. *(Мігровано з `00_07 §TRL Матриця` 2026-05-28 — канон тут.)*

| Модуль | TRL | Цільовий | Головний блокер |
|--------|-----|----------|-----------------|
| 00 Foundation (Vision + Method) | 9 | 9 | — (методологія/візія зрілі) |
| 01 Materials & EBFC | 4 | 6 | Lab tests (ЧНУ) |
| 02 Hardware & BOM | 4 | 6 | BQ25570, PCB, Pogo, PEEK |
| 03 Firmware | 6 | 8 | AES key, TinyML, AT blocking |
| 04 Backend Rails | 8 | 9 | RSpec тести |
| 05 Web3 Pipeline | 8 | 9 | SFC address |
| 06 DevOps | 5 | 9 | production deploy не проведено (06_01=4 outlier); Docker registry, TLS |
| 07 Business | 5 | 8 | CO₂ methodology, MSA, ToS |
| 08 University R&D | 2 | 6 | 5-сторонній партнерський фреймворк (ChNU + ChDTU + ChIPB + ChMA + СЄУ) — UNI.4-14 |
| 09 Project Management | 7 | 9 | OPS.3 R&D portfolio, OPS.4 semester sync |
| 10 Security | 7 | 9 | SEC.9 master key, ✅ SEC.11 Lorenz seed provenance, Multisig, RDP, Factory (Rails web layer ✅ S6.18) |

---

## 🛡️ 3. Принцип "TRL-Lock" → "TRL-Layered Independence"

> **Стара формулювання (Waterfall):** *"Жоден компонент не може бути переведений у стан Production, якщо він не досяг TRL 7. Якщо апаратна частина анкера на рівні TRL 4, а софт на TRL 8 — загальний статус модуля залишається TRL 4."*

Це лінійне правило знищує сенс Concurrent Engineering. Якщо Rails-модуль, токеноміка і Web3-мости готові до TRL 8, вони не повинні чекати, поки хіміки з ЧМА закінчать роботу з EBFC.

### Нова формулювання (Concurrent + HIL):

1. **System TRL** залишається обмеженим найнижчим модулем **критичного шляху** (01–07; §1-note) — це чесна метрика для grant заявок та regulator-комунікації ("система готова до пілоту тоді й тільки тоді, коли всі шари готові").
2. **Per-domain TRL** є **незалежним** і відстежується в `docs/00_03 §TRL Matrix` per-module. Software може бути TRL 8 коли Hardware TRL 4.
3. **HIL Simulators** (Hardware-in-the-Loop) — програмні генератори, які імітують поведінку реального hardware, дозволяють software-домену пройти TRL 5-8 без живої EBFC/анкера.

---

## 🧪 4. HIL Simulators — Програмне розблокування Software TRL

### 4.1 Чому це критично

Поточна політика блокувала весь TRL модулів 04 (Rails) і 05 (Web3) на TRL 4-5, попри те, що:

- `BlockchainMintingService` має 1092-рядкову spec з повним покриттям (`04_06 §B.1.2`).
- `TelemetryUnpackerService` 560+ рядків spec; CoAP Encryption concern, Web3CircuitBreaker concern.
- Solidity contracts: 171 тест Foundry + Slither static analysis.
- 31 Sidekiq worker, 9-рівнева черга з суворим пріоритетом.

Усе це **готове до production**. Без HIL — заблоковане TRL 4 формальністю.

### 4.2 HIL-симулятори в SilkenNet

| Симулятор | Імітує | Файл | Замінює реальний компонент для |
|-----------|--------|------|-------------------------------|
| `bin/forest_simulator` | Емулює **Queen→Backend CoAP-батчі** (AES-256-**CBC**) з телеметрією Soldier'ів, full Lorenz attractor curves. ⚠️ Це Queen-рівень: per-Soldier LoRa-хоп — на залізі **AES-128** (ECB→CCM, `03_05`), а до бекенду доходить CoAP-батч (AES-256-CBC). **Два режими (див. ⚠️ нижче):** `load_test_mode` (батч кожні 3–8 сек — стрес черг) та `realistic_mode` (CIFO-точний: рідкі об'ємні батчі ~раз на годину/45 записів + packet loss + jitter мобільної мережі) | `bin/forest_simulator` (load_test існує; realistic_mode — TODO) | Локальна розробка Rails + sidekiq + Web3 pipeline |
| `HilQueenSimulator` | Queen self-telemetry (`DID == 0x00000000`), CIFO flush, Starlink/LTE timing | новий: `lib/hil/queen_simulator.rb` (планований) | Test Queen failover ([`06_08 §Queen Failover`](06_08_Resilience_and_Failover_Policy)) |
| `HilWebPipelineSimulator` | peaq → IoTeX → Chainlink → Polygon → KlimaDAO → Filecoin → L1 — 12-chain mock з deterministic responses. ⚠️ Це **логіко-рівневий** інструмент (TRL 5-6): валідує pipeline-логіку та guard clauses, але **НЕ** Web3 реального світу (gas spikes, RPC 429/rate-limit, orphaned blocks, nonce collisions, Chainlink DON latency). НЕ є достатнім для TRL 7-8 — див. §4.3. | `WEB3_STRICT_MODE=false` + stub services у `app/services/web3/*_stub.rb` | Логіка pipeline + unit/integration (TRL 5-6) |
| `HilLorenzGenerator` | mruby Lorenz curves з різних tree species, environmental conditions (temp, vibration), faulty/normal patterns | `lib/hil/lorenz_generator.rb` (планований) | TinyML training data + Rails Attractor validation |
| `HilAttackerScenarios` | Bit-flip attacks, replay attacks, hardware tamper detection, dual-computation divergence > 30% | RSpec scenarios у `spec/integration/security/` (частково існує) | Anti-fraud cross-checks ([`05_05 §6`](05_05_Slashing_and_Risk_Policy)) |

> **⚠️ Реалістичний профіль навантаження vs DDoS (корекція 2026-05-28):** батч «кожні 3–8 сек» суперечить буферу CIFO ([`06_08 §1.2`](06_08_Resilience_and_Failover_Policy): flush на 45 записів **або** раз на годину) — для цього Soldier мав би передавати кілька разів на хвилину, що неможливо за енергобюджетом. Тобто 3–8 сек = `load_test_mode` (стрес черг/пропускної здатності), а НЕ реальний IoT-профіль. **`realistic_mode`** (потрібно додати) має відтворювати фізичну Queen: рідкі об'ємні батчі раз на ~годину, + мережеві умови **Starlink Direct-to-Cell**: Carrier-NAT, можливе блокування вхідного UDP (CoAP), зміна портів, високий jitter / packet loss супутникового LTE. Це тестує дефіцит з'єднань, тайм-аути long-poll та розриви TCP-сесій — справжні відмови, яких load-test не ловить. Транспортний фолбек (CoAP-over-TCP / MQTT-SN) — див. [`02_05`](02_05_Queen_Hardware_and_Starlink) + Ingress Proxy [`06_01`](06_01_Deployment_Kamal_Terraform).

### 4.3 TRL Промоція через HIL

> ⚠️ **Колонка нижче — НЕ блокер (інакше це повернуло б TRL-Lock з §3).** Сенс HIL саме в тому, щоб **не чекати** фізичних дерев. Тому це **Physical-Equivalent Target** — той фізичний стан, який HIL-симулятор *відтворює навантаженням*, а НЕ передумова. Software досягає TRL завдяки тому, що HIL генерує еквівалентне навантаження (напр. 1000+ віртуальних дерев), а не тому, що вони є в полі.

| Per-domain TRL | Physical-Equivalent Target (НЕ блокер) | HIL, що його відтворює | Status |
|----------------|----------------------|----------------|--------|
| Software TRL 5 (Prototype validated) | ~анкер у дереві 30 днів | `bin/forest_simulator` + integration tests | ✅ Достатньо |
| Software TRL 6 (Demonstration in relevant environment) | ~LoRa mesh у канопі | HIL Queen Simulator + Akash staging deploy + multi-node forest_simulator | 🟡 Частково (HIL Queen ще не написаний) |
| Software TRL 7 (Operational prototype) | ~pilot 100 дерев | Все HIL + chaos engineering + **реальний testnet pipeline ОБОВ'ЯЗКОВИЙ** (Polygon Amoy + Solana Devnet + Ethereum Sepolia) з реальними RPC-вузлами | 🟡 Частково (chaos engineering exists; testnet pipeline — TODO) |
| Software TRL 8 (Production-validated) | ~1000+ дерев у полі | **HIL відтворює 1000+ віртуальних дерев** + **повний testnet stress** (Amoy/Devnet/Sepolia: gas spikes, RPC 429, nonce collisions, DON latency, orphaned blocks) + Slither high-severity = 0 + multi-sig deployment dry-run. Mainnet — лише TRL 9. | 🟡 Контракти TRL 9-ready (Foundry/Slither); backend↔chain integration потребує testnet-стресу |

> **⚠️ Два рівні Web3-тестування (корекція 2026-05-28):** детермінований mock (`HilWebPipelineSimulator`) НЕ може давати Software TRL 8 — він валідує лише логіку (TRL 5-6). Реальні відмови Web3 (gas spikes, RPC rate-limit/429, orphaned blocks, nonce collisions, Chainlink DON latency) ловляться **тільки на справжніх testnet'ах**. Тому: **TRL 5-6** → deterministic mock; **TRL 7-8** → обов'язковий **Testnet Pipeline** (Polygon Amoy + Solana Devnet + Ethereum Sepolia, реальні RPC); **TRL 9** → mainnet. Без testnet-стресу вихід у mainnet після моків гарантує падіння бекенду у перші години.

### 4.4 Прозорість

> HIL-симулятори **не приховують** фізичне відставання — `docs/README.md` Current Stat показує **System TRL** (4) поряд із **per-domain TRL** (Rails 8, Solidity 9, EBFC 4). Це чесніше, ніж блокувати Software на TRL 4 формальністю TRL-Lock.

---


## 🌌 7. Beyond TRL 9 — Planetary Intelligence Gaps (Long-Horizon R&D Agenda)

> **Контекст:** TRL 1–9 описують шлях від ідеї до «стабільного мінтингу SCC на мільйонах вузлів». Це готує **Silken Net як інструмент** — фізично надійний D-MRV для лісу. Але **жодний з TRL-рівнів не описує перехід від «розумних дерев» до «розумного лісу»** — від суми ізольованих агентів до колективного інтелекту планетарного масштабу.
>
> Цей розділ фіксує **4 архітектурні прогалини**, які стоять між поточною архітектурою та справжнім "planetary intelligence". Це **не блокери** для TRL 9 (комерційний продукт можливий і без них), але це **дослідницький горизонт за межами TRL 9** — наукова програма на 5–15 років, яка перетворить Silken Net з IoT-системи в самоорганізовану кібер-екосистему.
>
> **⚠️ Метрика (2026-05-28): «TRL 10-12» — НЕ використовується.** TRL стандартизовано на 1-9 (NASA / ISO 16290) і вимірює лише технологічну готовність. Зрілість за межами TRL 9 трекається окремими шкалами ([`00_02 §1`](00_02_AI_Native_Engineering_and_TRL)): **SRL (System Readiness Level)** — системна/інтеграційна зрілість, стадії `Concept → Pilot → Deployed`; **MRL (Manufacturing Readiness Level, 8-10)** — серійне виробництво (5 SKU). Нижче «TRL шлях» кожної прогалини переформульовано як **SRL-шлях**.
>
> **Не плутати з блокерами в `00_07`:** там — конкретні інженерні задачі з measurable outcomes. Тут — стратегічні R&D-вектори, які потребують академічної колаборації (Q1 публікації) та можуть стати темою PhD-дисертацій під школами Кирилюка (синергетика) + Мінаєва (квантова хімія) + Порубльова (FOTIUS кібернетика).

### 7.1. Gap #1 — Forest-Level Emergence (Колективний Гомеостаз)

**Поточний стан:** Кожне дерево обчислює власний Lorenz attractor **ізольовано** на mruby VM (`03_04`). Сервер агрегує результати ex-post, але **деревам нічого не відомо одне про одного**. Немає колективного state на edge — типу «вся бухта дихає синхронно перед штормом», «ліс відчуває посуху раніше за окреме дерево».

**Чому це принципово важливо:**
- Реальні ліси демонструють **stigmergic communication** через мікоризну мережу (Wood Wide Web, Simard et al. 1997+; Sheldrake 2020): хімічні сигнали стресу передаються через грибкові гіфи між коренями за хвилини
- Колективна реакція **виявляє загрози раніше** за індивідуальну (predictive vs reactive): зграя птахів злітає раніше за самотнього птаха
- Без forest-level emergence Silken Net залишається **сенсорною мережею**, а не **нервовою системою лісу**

**Технічні вектори вирішення:**

| Підхід | Принцип | Потенційний партнер ЧНУ/СЄУ |
|---|---|---|
| **Розподілене навчання між Queens (дві РІЗНІ математики — не плутати):** | (a) **Lorenz σ/ρ/β** — це ODE-система **без ваг**, її не тренують backprop'ом → **Distributed Parameter Estimation** (PSO/GA на Queen знаходить оптимальні σ,ρ,β для локального кластера; Queens обмінюються *оцінками параметрів*, не градієнтами). (b) **TinyML акустика** — ось тут справжній **Federated Learning** доречний: агрегація градієнтів мікро-моделей (коли HW дозволить on-device training) АБО ретренінг класифікатора на Queen + компіляція `.tflite` → OTA. Privacy-preserving (не сирі дані). | Любченко GA/NSGA-II (`08_02`); Карапетян статистика (`08_02 §2`) |
| **Stigmergic Communication (L2/L3-опосередкована, НЕ P2P)** | Soldier емітує 1-bit стрес-сигнал («я в червоному Z-bucket», ~110 ms LoRa TX) → **L3 Queen** (always-on) акумулює його як «феромонний слід» → команда «підняти sampling rate» доставляється сусідам у їхнє наступне заплановане RX-вікно (CAD / TDMA / OTA-downlink). Прямого peer-RX немає (фізика — у ⚠️ нижче) | Порубльов кібернетика (`08_02`); mruby VM mod (`03_04`) |
| **Chimera States у network of attractors** | Математична теорія Куромото (Kuramoto-Battogtokh 2002): network coupled Lorenz oscillators утворює **частково синхронізовані, частково хаотичні patterns** — це саме структура здорового лісу (homeostasis-coupled domains across disturbance gradients) | Кирилюк синергетика економічних систем (`08_01 §1.4`); Гусак нелінійна динаміка (`08_01 §1.2`) |
| **Forest-Wide Lorenz Coupling** | Розширення `bio_contract.rb`: вхідні параметри атрактора містять не лише власні `delta_t/temp/acoustic`, а й aggregated neighbor signals (median Z у кластері за останню годину) | Розширення `03_04 §X.Y` (новий розділ після TRL 9) |

> **⚠️ Stigmergy маршрутизується через L2/L3, не P2P (корекція 2026-05-28):** рядок «Stigmergic Communication» вище описує лише *емісію* 1-bit сигналу (дешево: ~110 ms LoRa TX @ +14 dBm). **Зворотний шлях** («сусіди підвищують sampling rate») НЕ може бути peer-to-peer broadcast: Soldier перебуває у STOP2 ~99.9% часу (`03_01` / `08_02`), радіо SX1262 вимкнене — він фізично не «чує» сусіда, а continuous-RX вичерпав би 0.47F supercap за хвилини. Тому: Soldier-емітент → сигнал ловить **always-on L2 Conductor / L3 Queen** і акумулює як «феромонний слід» → команда «підняти sampling rate» доставляється сусідам лише у їхнє наступне заплановане RX-вікно (CAD-пінг / TDMA-слот / OTA-downlink, `03_02`). Це не послаблення ідеї, а **точніша** stigmergy: мурахи теж не передають сигнал напряму, а лишають слід у середовищі — роль персистентного середовища тут грає Queen.

**SRL шлях:** `SRL:Concept` (concept formulated) → `SRL:Pilot` (Q1 publication "Chimera states in tree-borne IoT sensors of Cherkasy Pine Forest") → `SRL:Deployed` (opt-in firmware extension у кластерах ≥ 100 дерев).

> ⚠️ **Ієрархічне делегування інтелекту (Compute Budget Constraint).** L1 Soldier (STM32WLE5JC + 0.47F supercap, енергобаланс `02_03 §9.6 Сценарій C` = +1.4 мДж/год запасу) **фізично не може** тренувати моделі або агрегувати градієнти — будь-який Federated Learning epoch, обчислення Chimera coupling або forest-wide attractor inversion утримуватиме MCU в active-режимі (≥12 mA × ≥секунди) і **гарантовано виведе supercap у brownout** ще до завершення першої епохи. Тому:
>
> - **L1 Soldiers (STM32 + 0.47F):** залишаються наївними виконавцями (Inference only). Емітують 1-bit stigmergic сигнали (рядок «Stigmergic Communication» — це **єдина дешева опція** на L1, ~110 ms LoRa TX @ +14 dBm).
> - **L2 Conductors / L3 Queens (LiFePO4 + Solar):** тут відбуваються Federated Learning, Chimera coupling math та network-level Lorenz координація. Queen має 20Ah батарею і Cortex-M4 + LTE backbone — обчислювально на 4-5 порядків багатший за Soldier.
>
> Solidiers отримують результат як **скомпільований mruby bytecode через OTA-канал** (`03_02` Queen → broadcast chunks по 11 байт), що зберігається у `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`. Жодного "self-training" на L1. Зберігає SRL roadmap реалістичним.

### 7.2. Gap #2 — Self-Evolving Behaviour (On-Device Edge AI)

**Поточний стан:** OTA bytecode update існує (`03_02` mruby flash slot `0x0803F000`), але всі зміни приходять **зверху** (Rails backend → Queen → broadcast). Soldier — це **виконавець**, не **навчач**. Немає механізмів адаптації **без human-in-loop**.

**Чому це принципово важливо:**
- Жодний backend не передбачить всі мікроклімати (Карпати vs Полісся vs Амазонія) — параметри атрактора (σ, ρ, β) повинні **самоналаштовуватися** під локальні умови
- Дерева **ростуть і змінюються** за 20 років. Дерево 5-річне і дерево 25-річне — різні системи. Статичні OPTIMAL_Z_TARGET = 29.0 → false positives stress alerts через ~10 років
- Адаптивність — це **рівень життя** (Maturana & Varela: autopoiesis). Без неї Silken Net залишається **імплантом**, а не **симбіонтом**

**Технічні вектори вирішення:**

| Підхід | Принцип | Виклики на STM32WLE5JC |
|---|---|---|
| **On-Device Evolutionary Algorithms** | mruby VM запускає mini-GA: 4 candidate parameter sets для (σ, ρ, β) → fitness = local power efficiency × low oracle rejection rate → щотижня elite-selection нового baseline | RAM 64 KB; flash bytecode budget 8 KB; mruby int-math performance (~10⁵ ops/sec) — обмежує до < 10 generations/тиждень |
| **Edge Reinforcement Learning** | Tabular Q-learning з 12-state × 4-action lookup (state = bucketed Z + vcap + temp; action = sleep_extend/normal/sample_extra/emergency_tx); reward = days-to-next-VBAT_OK | RL потребує episode memory — використати RTC backup registers (DR20-DR31) як state buffer; ε-greedy schedule зашитий у firmware |
| **Адаптивна модифікація `bio_contract.rb`** | Не тільки параметри, але й **сама структура** атрактора може evolve: спершу Lorenz, потім Lorenz-96 (більша dim для дерев у кластерах), потім кастомні мутації через genetic programming | Безпекова перевірка: будь-яка self-modified contract має слотом для cryptographic anchor — інакше зловмисник може injection через RL reward poisoning |
| **TinyML Online Learning** | Поточний CMSIS-NN модель (`03_03`) — frozen після training. Розширення: on-device class incremental learning з новими акустичними патернами (типу «нової інвазивної комахи у Черкаському борі») без необхідності retraining у cloud | На STM32WLE5JC можливо лише з 1–4 class incremental memory; full on-device backprop недосяжний — потрібен AI-чип coprocessor (Syntiant NDP120 або Maxim MAX78000) у v3 hardware |

**Безпекова прірва:** Self-evolution + Web3-economic incentives = **attack surface для adversarial evolution**. Зловмисник може спровокувати «вигідну для нього» мутацію через підставні sensor patterns. Mitigation — `7.4 Apex Predator Defense`.

> ⚠️ **Compute Budget Paradox — L1 не "self-evolves" фізично.** Стовпчик «Виклики на STM32WLE5JC» вище **не** є інженерним планом запуску GA/RL/online-backprop на Soldier — це інвентаризація причин, **чому це неможливо** у поточному hardware envelope:
>
> - **mini-GA (4 candidate sets × multi-epoch fitness):** кожна fitness-епоха = повний цикл sense+Lorenz+TX (≈58 мДж/cycle, `02_03 §9.4`). 10 generations/тиждень × 4 candidates × 58 мДж = **2.3 Дж/тиждень додатково** при загальному робочому вікні supercap **3.87 Дж** (`02_03 §8`). → Перевищує бюджет у 4-6× після врахування sleep drain.
> - **Tabular Q-learning (12-state × 4-action):** сам lookup дешевий, але **reward сигнал = "days-to-next-VBAT_OK"** вимагає тижневих епізодів — ε-greedy exploration з 0.1 ймовірністю "sample_extra" з'їсть весь energy headroom Сценарію C (+1.4 мДж/год).
> - **TinyML on-device incremental learning:** full backprop на Cortex-M4 без AI-accelerator потребує seconds × 12 mA, що **гарантовано brownout**.
>
> **Ієрархічне делегування інтелекту (HW envelope перерозподіл):**
>
> | Рівень | Що відбувається | Hardware envelope |
> |--------|----------------|-------------------|
> | **L1 Soldier** | Inference-only: запуск **попередньо скомпільованого** mruby bytecode (Lorenz constants, fitness evaluation, threshold lookup). Періодична відправка `lambda_exponent` + 1-bit stigmergic сигналу. | STM32WLE5JC + 0.47F, +1.4 мДж/год headroom |
> | **L2 Conductor** *(Hub Tree, formerly "Sergeant")* | Кластерний агрегатор: збирає 50-200 Soldiers lambda-stream, обчислює **локальний GA** на (σ, ρ, β) для свого кластера, відправляє candidate sets до Queen. Динамічно обирається на основі `vcap` та якості зв'язку. | Solar + LiFePO4 (TBD spec, §8.1 L2 placeholder) |
> | **L3 Queen** *(Mother Tree)* | Агрегатор розподіленого навчання: для Lorenz — обмін **оцінками параметрів σ/ρ/β** (distributed parameter estimation, PSO/GA); для TinyML — справжній Federated Learning (агрегація градієнтів / ретренінг → `.tflite` OTA), privacy-preserving. Компілює mruby contracts, broadcast'ить chunked OTA. | 20Ah LiFePO4 + Solar + LTE backbone (`02_05`) |
>
> Q-learning, GA-evolution, online TinyML training **відбуваються на L2/L3 з обмеженням енергії на 4-5 порядків легшим**, ніж у Soldier. До Soldier приходить **готовий compiled bytecode через OTA** (магік `0x45544952 "RITE"` у `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`, `03_02`). Це усуває "self-training on edge" парадокс і зберігає SRL roadmap реалістичним.

**SRL шлях:** `SRL:Concept` (Q1 paper "Edge evolutionary Lorenz parameter tuning **за делегованою L2/L3 архітектурою**") → `SRL:Pilot` (opt-in firmware feature for select cluster owners) → `SRL:Deployed` (default behavior після формальної верифікації безпеки).

### 7.3. Gap #3 — Cross-Species / Cross-Biome Generalization

**Поточний стан:** Архітектура жорстко заточена під **Pinus sylvestris** Черкаського бору:
- Хімія EBFC (`01_03`): Gen 2.0 baseline — dgrFAD-GDH + Laccase/ZIF-nanozyme + Genipin-Chitosan-CNC + Nafion-g-PSBMA — оптимізовані під pH 4.5–5.5 (хвойні)
- Геометрія анкера (`01_01 §5.5`): пори 100–500 µm — оптимум для трахеїд 20–50 µm
- Lorenz-константи (`03_04`): σ=10, ρ=28, β=8/3, OPTIMAL_Z=29 — калібровано на pine baseline
- Хірургічний протокол (`01_04 §3`): Flush Mount + microfrezing для м'якої soft-wood сосни

**Чому це обмежує:**
- Дуб (*Quercus*) — пори 200–400 µm (кільцепориста) → потрібна інша геометрія гіроїда
- Береза (*Betula*) — pH ксилеми 5.5–6.5 (м'якше); FAD-GDH pH-вікно 4.0–8.0 покриває, але потенціали Os та Laccase потребують перекалібрування
- Мангрові (*Rhizophora*) — sap salinity 10–35 ppt → у Gen 2.0 ZIF-нанозим уже здатний нейтралізувати Cl⁻ (+7.5% активності), але потребує валідації на 30+ ppt
- Тропічні евкаліпти (*Eucalyptus*) — phenolic compounds 2–5× вищі за pine → CODIT-реакція агресивніша
- **«Planetary intelligence» означає biome-agnostic**, поточна архітектура — **species-specific instrument**

**Технічні вектори вирішення:**

| Шар | Що треба узагальнити | Як |
|---|---|---|
| **Hardware (BOM)** | 5 SKU замість 1: pine, oak, broadleaf, mangrove, tropical-hardwood — різна геометрія гіроїда, ферменти, anchor довжина | Параметрична CAD-модель у nTop (vs static). Stage 2 Ti-coin тести (`01_01 §6.1`) на 5 синтетичних соках |
| **Firmware (Lorenz constants)** | `bio_contract.rb` приймає species_id → calibrated (σ, ρ, β) з flash table 16 × 24 bytes | OTA bytecode update із species-specific table; species_id зашитий у DID на provisioning |
| **Backend (Validation)** | `SilkenNet::Attractor` має model registry per-species; oracle dispatch validates against correct baseline | `MODEL_REGISTRY = { pine: '...', oak: '...' }` + migration `add_species to trees` |
| **DAO Governance** | Кожен new biome потребує community vote (SFC) + lab validation slot перш ніж SCC можуть мінтитись з нього | Розширення Slashing v2 на biome-specific stress detection thresholds |

**Партнерські школи:**
- Спрягайло (`08_01 §1.3`) — extension до інших порід ЧНУ Botanical Hub
- НАН України через школу НБС Гришка (intro Спрягайла, кандидатська 2013) — broadleaf і fruit tree calibration
- Future: international university partnerships (Brazil INPA для tropical, Australia CSIRO для eucalyptus, ASEAN MUSE для mangrove)

**SRL/MRL шлях:** `SRL:Concept` (multi-species PoC у 3 lab settings) → `SRL:Pilot` + `MRL:8` (deployed pilots у 3 biomes одночасно, мала серія 5 SKU) → `SRL:Deployed` + `MRL:10` (open framework + повносерійне виробництво per-biome SKU).

### 7.4. Gap #4 — Apex Predator Defense (Proactive AI-Adversarial Security)

**Поточний стан:** DAO governance існує (SFC, `05_03`), Slashing v2 реактивний (`05_05 §6`), 12-chain pipeline має cross-validation (`05_02`). Але:
- **Немає proactive захисту від AI-driven economic attack** — coordinated manipulation SCC market через synthetic telemetry patterns
- **Oracle attack surface** — Chainlink DON має finite operator count; targeted bribe + adversarial generation може зсунути medianer
- **Slashing — реактивний**: чекає, поки факт зловживання stane on-chain, тоді штрафує. До цього моменту attacker вже випередив 1000× ROI на dump SCC

**Чому це принципово важливо:**
- Як тільки SCC market cap перевищить ~$100M (TRL 9 milestone), система стане **апетитною ціллю для AI-driven trading bots**
- Майбутні Generative AI зможуть синтезувати telemetry-патерни, які проходять **всі поточні fraud detection** (Dual Computation Integrity, oracle validation) — adversarial ML attacks
- **Без apex predator defense Silken Net підданий тій самій долі, що й DeFi 2020–2024** (flash loan attacks, oracle manipulation, rug pulls) — але з фізичним лісом як collateral damage

**Технічні вектори вирішення:**

| Підхід | Принцип | Реалізація |
|---|---|---|
| **Proactive Anomaly Detection (Federated)** | Замість per-tree fraud detection — **cluster-level statistical fingerprints**. Якщо 100 дерев одного кластера раптом починають видавати «too perfect» Z-curves (lower variance than possible), це → suspicious | ML-сервіс у Rails + GA-оптимізація Любченка (`08_02`); запит до Карапетяна (статистика, `08_02 §2`) |
| **Adversarial Telemetry Generators (Red Team)** | Внутрішня команда генерує **GAN-вироблені синтетичні telemetry, які намагаються пройти Dual Computation** → знаходить вразливості до того, як їх знайде зовнішній attacker | Регулярні Red Team Exercises як частина CI/CD (`04_06 §B`); Q1 paper "Adversarial robustness of bio-token mints" |
| **Decoy DID Tripwire (backend, НЕ on-chain honeypot)** | ⚠️ Виправлено: on-chain honeypot не працює — стейт контракту публічний, а навіть «реальне-але-заблоковане» дерево видає себе **відсутністю mint-подій** (атакер аналізує on-chain патерн і обходить). Тому — **бекенд-tripwire**: набір **decoy DID**, яких немає як реальних анкерів, у серверному watchlist (НЕ публікуються, НЕ on-chain). **Будь-яка телеметрія/mint-спроба від decoy DID = доведена підробка** (жоден реальний Soldier його не має) → instant alert + slashing + 12-chain rotation. Додатково: **Shadow Trees** — синтетичні фейкові дані у *публічному дашборді* (information warfare: торговий бот, що будує атаку на shadow-даних, руйнує свою стратегію). | Backend watchlist decoy DIDs + `TelemetryUnpackerService` tripwire (НЕ on-chain flag) |
| **Quantum-Resistant Oracle Migration** | Сучасні ECDSA-підписи (Chainlink) вразливі до post-quantum cryptanalysis (~2030+). Перехід на **NIST PQC standards** (Kyber/Dilithium) у Web3 stack | Координовано з Аблязовим Д. (СЄУ, `08_02 §5`) для правової рамки + Ярмілко (`08_02`) для firmware integration |
| **Apex Predator AI Sentinel** | Окремий ML-сервіс, який моніторить весь стек 24/7 в режимі **«hunting for hunters»** — шукає координовані patterns між: trading volume на SCC DEXs + telemetry anomalies + oracle response patterns. Це **проактивний counter-AI** проти adversarial AI | Roadmap `SRL:Pilot`+; вимагає budget на dedicated AI/ML engineer; партнерство з академічними лабораторіями з ML security |

**Філософська позиція:** Silken Net — це **критична інфраструктура планетарного клімату**. Тому стандарт безпеки має бути не «не гірше за DeFi», а **на рівні national-grid SCADA**: continuous threat hunting, mandatory bug bounty, formal verification critical path.

**SRL шлях:** `SRL:Concept` (Red Team exercises у production) → `SRL:Pilot` (AI Sentinel deployed) → `SRL:Deployed` (formal verification of slashing protocol проти всіх відомих vectors).

### 7.5. Зведена Таблиця Чотирьох Прогалин

| # | Gap | Поточний стан (TRL 9) | Майбутній стан (SRL:Deployed) | Партнер | Q1 паперів |
|---|---|---|---|---|---|
| 1 | Forest-Level Emergence | Ізольовані Lorenz | Chimera states у network of attractors | Кирилюк, Гусак, Любченко | 2–3 (Synergetics + Network Science) |
| 2 | Self-Evolving Behaviour | Top-down OTA only | On-device edge GA + RL | Порубльов, Ярмілко | 2 (Edge AI + Evolutionary Comp.) |
| 3 | Cross-Biome Generalization | Pine-only | 5+ biomes, community-driven onboarding | Спрягайло + INPA/CSIRO/MUSE | 3–5 (per biome) |
| 4 | Apex Predator Defense | Reactive Slashing | Proactive AI Sentinel + PQC | Аблязов Д., Карапетян, ML-security partners | 2 (Adversarial ML + Web3 Security) |

### 7.6. Як це впливає на TRL ladder

Ці 4 прогалини **не блокують** TRL 9 (commercial product можливий і без них). Але вони визначають **SRL-ієрархію за межами TRL 9** (а не «TRL 10-12»), яка перетворює Silken Net з **D-MRV-інструменту** на **планетарну нервову систему**:

```
TRL 9        ━━━ Operational. Stable SCC mint.                ← Silken Net як IoT-продукт
SRL:Concept  ━━━ Forest-level emergence + cross-biome PoC      ← Silken Net як нервова система
SRL:Pilot    ━━━ Self-evolving + AI Sentinel deployed          ← Silken Net як адаптивний симбіонт
SRL:Deployed ━━━ Verified, formal, planetary-scale autopoiesis ← Silken Net як планетарний інтелект
             (+ MRL:8-10 — серійне виробництво 5 SKU per biome)
```

Це **15-річний горизонт** (2026–2040+) — за ним вже сяє візія Гедз+Чудаєвої (`08_02 §5`): D-MRV як база для **global climate governance protocol**, на рівні WTO або ISO.

### 7.7. Cross-references та де ще згадано

- **Gap #1 (Forest Emergence):** деталі у [`03_04 §X.Y`](03_04_mruby_Lorenz_Attractor) (новий розділ — TBD); координація з [`08_02 §1`](08_02_Academic_Institutions_Registry) (Порубльов кібернетика) та [`08_02 §1`](08_02_Academic_Institutions_Registry) (Кирилюк синергетика)
- **Gap #2 (Self-Evolving):** firmware extension у [`03_03 §Y`](03_03_TinyML_Acoustic_Inference) (TinyML online learning) + [`03_04 §Z`](03_04_mruby_Lorenz_Attractor) (mruby GA); безпекова валідація у [`05_03 §SCC Anti-Adversarial`](05_03_Tokenomics_SCC_and_SFC)
- **Gap #3 (Cross-Biome):** parametric CAD у [`01_01 §6`](01_01_Coaxial_Gyroid_Topology_and_PEEK) (Stages 2+ extended до 5 biomes); R&D у [`08_02 §1`](08_02_Academic_Institutions_Registry) (Спрягайло + НАН України канал)
- **Gap #4 (Apex Predator):** розширення Slashing v2 у [`05_05 §6`](05_05_Slashing_and_Risk_Policy) + [`05_06 §5`](05_06_Governance_and_DAO) + Chainlink hardening у [`05_02`](05_02_Proof_of_Growth_Pipeline)

---

## 🌐 8. Фрактальна Мережева Топологія — Planetary Network Scaling

> Поточна плоска LoRa-меш архітектура задихнеться від колізій та затримок вже на кількох тисячах вузлів. Для мільйонів дерев необхідна **фрактальна топологія**. Це мережевий (routing/topology) аналог §7 — там йшлося про *колективний інтелект*, тут — про *фізичне масштабування мережі*. Hardware/compute-envelope трьох рівнів (L1/L2/L3) описаний у [§7.2](#-72-gap-2--self-evolving-behaviour-on-device-edge-ai) (таблиця делегування інтелекту); нижче — їхня **мережева роль і маршрутизація**.

### 8.1. Трьохрівнева ієрархія вузлів (The Fractal Stack)

> **🌳 Біонічний rename (2026-05-22):** Рівень L2 перейменовано з "Sergeant/Сержант" на **"Conductor/Провідник"** (історично "Hub Tree" — найстаріше домінуюче дерево локального кластера). Це відображає природну Scale-Free Network лісу та акцентує **передачу енергії та інформації**, а не військову ієрархію. Технічна структура (3-рівнева топологія, TDMA, CAD Preamble) залишається без змін.

```
L3: Queen Gateways (Mother Tree — Супер-вузли)
    LoRa SF12 + Starlink/LTE backbone
    ├── Inter-cluster relay (Queen ↔ Queen Backhaul Mesh)
    └── Cloud uplink (CoAP → Rails)
         │
L2: Conductor Nodes (Провідник — Hub Tree, Cluster Head) [МАЙБУТНЄ]
    Сильне зріле дерево в центрі взводу; високий потенціал EBFC + LiFePO4
    ├── Агрегує 50–200 Солдатів у "Звіт про стан кластера"
    ├── Замість 100 пакетів → 1 стиснений summary
    └── Динамічно обирається на основі `vcap` та якості зв'язку
         │
L1: Soldier Nodes (Regular Tree — Листя) — поточна архітектура
    STM32WLE5JC + EBFC (0.47F), STOP2 (300 nA)
    └── Передає стиснутий стан (lambda-exponent) найближчому Провіднику
```

**Ключова зміна:** Солдати більше не спілкуються з усім світом — лише з найближчим Провідником. Зменшення радіочастотних колізій на порядки.

> **Передумова для L2 Conductor:** Рівень Провідників потребує вирішеної Проблеми Рандеву між Солдатом і Провідником. Провідник не може бути always-on (як Queen) — його живлення обмежене, хоча й більше ніж у Солдата. Рішення: TDMA Синхронні Вікна ([ARCH.26](00_07_Action_Plan_Tracker)) + CAD Preamble Detection. Деталі Рандеву — [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA).

### 8.2. H-LDSE — Ієрархічний Протокол Маршрутизації

Еволюція поточного LDSE-меш для мільйонної мережі:

| Механізм | Поточний LDSE | H-LDSE |
|----------|--------------|--------|
| Таблиця маршрутизації | Всі сусіди (OOM при >1000 вузлів) | Лише 2–3 хопи (локальна адресація) |
| Адресація | DID-based | Геохешинг (ID = координати) |
| Пошук шляху | TTL broadcast | Градієнтний потік до найближчої Queen |
| Частотні рівні | Один канал | Spatial Multiplexing (L1 → канал A, L2 → канал B) |

**Геохешинг:** Кожен супер-кластер отримує ID на основі координат. Пакет не шукає маршрут — він тече в бік зменшення градієнта до найближчої Королеви. Усуває broadcast storm.

> **⚠️ Розмежування рівнів (2026-05-28): геохешинг — це здатність L2 Conductor, НЕ L1 Soldier.** Поточна прошивка ([`03_01`](03_01_Firmware_Lifecycle_and_DMA), [`08_02`](08_02_Academic_Institutions_Registry)) — наївний **TTL-flood relay** (PANIC_TTL=5, DEFAULT_TTL=3) без маршрутизації. Градієнтний геохешинг вимагає, щоб вузол оперував координатами та сусідським градієнтом — це покладається на **L2 Conductor** (має RTC, більший енергобюджет, відомі координати). **L1 Soldiers залишаються TTL-flood вузлами**, які просто «кричать» у радіусі свого найближчого L2 Conductor (відповідно до фрактальної ієрархії вище). H-LDSE — це цільова еволюція рівня L2, а не зміна поведінки L1.

**Spatial Multiplexing:** L1 та L2 працюють на різних частотних підканалах 868 MHz ISM — усуває міжрівневі колізії (inter-tier interference).

### 8.3. Edge Data Fusion — Стиснення Інформації

Замість передачі повних координат атрактора Лоренца, вузол передає лише **lambda-exponent** (показник хаотичності Ляпунова):

```
Поточний підхід:      16 байт payload → Z-координата Лоренца
Gaia 2.0 підхід:      2 байти lambda → описує стан всього дерева
```

> **Що зберігається:** lambda-exponent (показник Ляпунова) відображає ступінь хаотичності атрактора — достатньо для визначення "норма / стрес / аномалія". **Що втрачається:** абсолютні координати (X, Y, Z) — їх відновлення неможливе без повного ряду. Коли lambda перевищує поріг аномалії (`|λ| > λ_threshold`), Солдат автоматично переходить у режим повного стрімінгу з 16-байт payload — втрата інформації повністю усувається при критичних подіях.

**Event-Triggered Reporting:** "Тиша означає здоров'я":
- Стабільний атрактор → heartbeat раз на добу (1 пакет/24 год)
- Атрактор "зривається" (пожежа / посуха) → безперервний стрімінг (~1 пакет/хв)

Скорочення трафіку в нормальному режимі в ~24× при збереженні повної чутливості до аномалій.

### 8.4. Network Sharding — Ізоляція Секторів

```
[Нормальний режим]      Cluster A ←→ Cluster B ←→ Cluster C

[Аномалія в Cluster B]  Cluster A | [B isolated] | Cluster C
                                    ↑
                         Вирубка / пожежа → шторм тривожних пакетів
                         не "кладе" сусідні кластери
```

**Queen-to-Queen Backhaul Mesh:** Королеви з'єднані між собою через LoRa SF12. Якщо одна Queen втрачає Starlink → передає дані сусідній Queen через LoRa-магістраль. Деталі — [`06_08 §Queen Failover`](06_08_Resilience_and_Failover_Policy).

### 8.5. Energy-Aware Routing

Маршрутизація будується не за найкоротшим шляхом, а за **найбільш енергонадлишковим**:

```
Route metric = f(hop_count, remaining_energy, bio_potential)
```

Пакет іде через дерево з найкращим сокорухом (найбільшим біопотенціалом сьогодні) → автоматичне балансування навантаження + екологічна маршрутизація.

### 8.6. Вимоги до Rails Backend (Gaia 2.0 Scale)

| Компонент | Поточний стан | Gaia 2.0 вимога |
|-----------|--------------|----------------|
| Вхідний шар | CoAP прямо в Rails | Ingress Proxy (Rust/Go) → Kafka/Pub-Sub → Rails consumers |
| БД читання | Primary + Query | Read-Only Replicas для всіх аналітичних запитів та Oracle |
| TinyML навчання | Централізоване | Federated Learning: навчання на кластерах → OTA-оновлення через `OtaPackagerService` (делегування — §7.2) |
