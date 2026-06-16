# 00_08: Beyond TRL 9 — Planetary Intelligence & Network Scaling

## 🎯 Мета

Канонічний дім **far-horizon R&D-агенди за межами TRL 9** (горизонт 2026–2040+): чотири Planetary-Intelligence прогалини (колективний гомеостаз, self-evolving edge AI, cross-biome генералізація, auto-immune sentinel безпека) + **фрактальна мережева топологія** (L1/L2/L3, H-LDSE, Edge Data Fusion, energy-aware routing) для масштабування до мільйонів вузлів. Це SRL/MRL-сходи, що перетворюють Silken Net з D-MRV-інструменту на планетарну нервову систему. Виокремлено з [`00_03`](00_03_TRL_Matrix_HIL_and_Beyond) (де лишається жива TRL-матриця + HIL), щоб стабільна 15-річна візія не ділила файл із щотижнево-оновлюваним станом готовності.

---

## ✅ Статус

- **Поточний TRL:** TRL 9 — це **Beyond-TRL-9 R&D-агенда** поверх TRL-9-продукту; **не TRL-gated** (комерційний продукт можливий і без неї). Зрілість трекається окремими шкалами **SRL** (System Readiness: `Concept → Pilot → Deployed`) / **MRL** (Manufacturing Readiness 8-10) — [`00_02 §1`](00_02_AI_Native_Engineering_and_TRL). Це стратегічні R&D-вектори, НЕ блокери (інженерні задачі → [`00_07`](00_07_Action_Plan_Tracker)).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_01` — Vision Mission and Roadmap](00_01_Vision_Mission_and_Roadmap) | Near-term roadmap (§4, фази 2025–2030); ця сторінка — far-horizon продовження |
| [`00_02` — AI Native Engineering and TRL](00_02_AI_Native_Engineering_and_TRL) | SRL/MRL шкали зрілості за межами TRL-9 |
| [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | Жива TRL-матриця (§1) + TRL-Layered-Independence (§2) + HIL (§3) — поточний стан/метод |
| [`01_01` — Coaxial Gyroid Topology and PEEK](01_01_Coaxial_Gyroid_Topology_and_PEEK) | Cross-biome 5 SKU (Gap #3 hardware-бік) |
| [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) | On-Device Learning / Edge RL (Gap #2 firmware-бік) |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | §6.3 Forest-Level Lorenz Coupling (Gap #1 firmware-бік) |
| [`05_06` — Governance and DAO](05_06_Governance_and_DAO) | Auto-Immune Sentinel §5 (Gap #4 governance-бік) |
| [`06_08` — Resilience and Failover Policy](06_08_Resilience_and_Failover_Policy) | Queen failover / Q2Q backhaul — мережева реалізація §2 |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | ARCH.1/6/7/10/22 — інженерні backlog-вектори цієї агенди |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Beyond TRL 9 — Planetary Intelligence Gaps (Long-Horizon R&D Agenda)](#-1-beyond-trl-9--planetary-intelligence-gaps-long-horizon-rd-agenda)
- [2. Фрактальна Мережева Топологія — Planetary Network Scaling](#-2-фрактальна-мережева-топологія--planetary-network-scaling)
- [3. Beyond the Forest — GaiaNexus Planetary Federation](#-3-beyond-the-forest--gaianexus-planetary-federation)
<!-- TOC:AUTO:END -->

---

## 🌌 1. Beyond TRL 9 — Planetary Intelligence Gaps (Long-Horizon R&D Agenda)

> **Контекст:** TRL 1–9 описують шлях від ідеї до «стабільного мінтингу SCC на мільйонах вузлів». Це готує **Silken Net як інструмент** — фізично надійний D-MRV для лісу. Але **жодний з TRL-рівнів не описує перехід від «розумних дерев» до «розумного лісу»** — від суми ізольованих агентів до колективного інтелекту планетарного масштабу.
>
> Цей розділ фіксує **4 архітектурні прогалини**, які стоять між поточною архітектурою та справжнім "planetary intelligence". Це **не блокери** для TRL 9 (комерційний продукт можливий і без них), але це **дослідницький горизонт за межами TRL 9** — наукова програма на 5–15 років, яка перетворить Silken Net з IoT-системи в самоорганізовану кібер-екосистему.
>
> **⚠️ Метрика: «TRL 10-12» — НЕ використовується.** TRL стандартизовано на 1-9 (NASA / ISO 16290) і вимірює лише технологічну готовність. Зрілість за межами TRL 9 трекається окремими шкалами ([`00_02 §1`](00_02_AI_Native_Engineering_and_TRL)): **SRL (System Readiness Level)** — системна/інтеграційна зрілість, стадії `Concept → Pilot → Deployed`; **MRL (Manufacturing Readiness Level, 8-10)** — серійне виробництво (5 SKU). Нижче «TRL шлях» кожної прогалини переформульовано як **SRL-шлях**.
>
> **Не плутати з блокерами в [`00_07`](00_07_Action_Plan_Tracker):** там — конкретні інженерні задачі з measurable outcomes. Тут — стратегічні R&D-вектори, які потребують академічної колаборації (Q1 публікації) та можуть стати темою PhD-дисертацій під школами Кирилюка (синергетика) + Мінаєва (квантова хімія) + FOTIUS кібернетика.

### 1.1. Gap #1 — Forest-Level Emergence (Колективний Гомеостаз)

**Поточний стан:** Кожне дерево обчислює власний Lorenz attractor **ізольовано** на mruby VM ([`03_04`](03_04_mruby_Lorenz_Attractor)). Сервер агрегує результати ex-post, але **деревам нічого не відомо одне про одного**. Немає колективного state на edge — типу «вся бухта дихає синхронно перед штормом», «ліс відчуває посуху раніше за окреме дерево».

**Чому це принципово важливо:**
- Реальні ліси демонструють **stigmergic communication** через мікоризну мережу (Wood Wide Web, Simard et al. 1997+; Sheldrake 2020): хімічні сигнали стресу передаються через грибкові гіфи між коренями за хвилини
- Колективна реакція **виявляє загрози раніше** за індивідуальну (predictive vs reactive): зграя птахів злітає раніше за самотнього птаха
- Без forest-level emergence Silken Net залишається **сенсорною мережею**, а не **нервовою системою лісу**

**Технічні вектори вирішення:**

| Підхід | Принцип | Потенційний партнер ЧНУ/СЄУ |
|---|---|---|
| **Розподілене навчання між Queens (дві РІЗНІ математики — не плутати):** | (a) **Lorenz σ/ρ/β** — це ODE-система **без ваг**, її не тренують backprop'ом → **Distributed Parameter Estimation** (PSO/GA на Queen знаходить оптимальні σ,ρ,β для локального кластера; Queens обмінюються *оцінками параметрів*, не градієнтами). (b) **TinyML акустика** — тут доречне навчання, але точна назва залежить від рівня. **Cluster-level Edge Retraining** (Queen ретренить класифікатор на даних свого кластера + компілює `.tflite` → OTA) — це **НЕ** Federated Learning, а локальний batch-training на edge-сервері (Soldier фізично не рахує градієнти, §1.2). **Справжній FL** можливий лише як обмін *оновленнями моделі* Queen↔Rails (не сирими даними) — і лише якщо так структуровано. Мотив — **не privacy** (у дерев немає GDPR-даних; бекенду навпаки потрібні сирі семпли кавітації/пилки для глобальної моделі), а **економія airtime/енергії** (не гнати все аудіо в хмару) + стійкість. | Любченко GA/NSGA-II ([`08_02`](08_02_Academic_Institutions_Registry)); Карапетян статистика ([`08_02 §2`](08_02_Academic_Institutions_Registry)) |
| **Stigmergic Communication (L2/L3-опосередкована, НЕ P2P)** | Soldier емітує 1-bit стрес-сигнал («я в червоному Z-bucket», ~110 ms LoRa TX) → **L3 Queen** (always-on) акумулює його як «феромонний слід» → команда «підняти sampling rate» доставляється сусідам у їхнє наступне заплановане RX-вікно (CAD / TDMA / OTA-downlink). Прямого peer-RX немає (фізика — у ⚠️ нижче) | Порубльов кібернетика ([`08_02`](08_02_Academic_Institutions_Registry)); mruby VM mod ([`03_04`](03_04_mruby_Lorenz_Attractor)) |
| **Chimera States у network of attractors** | Математична теорія Куромото (Kuramoto-Battogtokh 2002): network coupled Lorenz oscillators утворює **частково синхронізовані, частково хаотичні patterns** — це саме структура здорового лісу (homeostasis-coupled domains across disturbance gradients) | Кирилюк синергетика економічних систем ([`08_02 §1A`](08_02_Academic_Institutions_Registry)); Гусак нелінійна динаміка ([`08_02 §1A`](08_02_Academic_Institutions_Registry)) |
| **Forest-Wide Lorenz Coupling** | Розширення `bio_contract.rb`: вхідні параметри атрактора містять не лише власні `delta_t/temp/acoustic`, а й aggregated neighbor signals (median Z у кластері за останню годину) | Розширення `03_04 §X.Y` (новий розділ після TRL 9) |

> **⚠️ Stigmergy маршрутизується через L2/L3, не P2P:** рядок «Stigmergic Communication» вище описує лише *емісію* 1-bit сигналу (дешево: ~110 ms LoRa TX @ +14 dBm). **Зворотний шлях** («сусіди підвищують sampling rate») НЕ може бути peer-to-peer broadcast: Soldier перебуває у STOP2 ~99.9% часу ([`03_01`](03_01_Firmware_Lifecycle_and_DMA) / [`08_02`](08_02_Academic_Institutions_Registry)), радіо SX1262 вимкнене — він фізично не «чує» сусіда, а continuous-RX вичерпав би 0.47F supercap за хвилини. Тому: Soldier-емітент → сигнал ловить **always-on L2 Conductor / L3 Queen** і акумулює як «феромонний слід» → команда «підняти sampling rate» доставляється сусідам лише у їхнє наступне заплановане RX-вікно (CAD-пінг / TDMA-слот / OTA-downlink, [`03_02`](03_02_Queen_Gateway_Firmware)). Це не послаблення ідеї, а **точніша** stigmergy: мурахи теж не передають сигнал напряму, а лишають слід у середовищі — роль персистентного середовища тут грає Queen.
>
> **⚠️ Швидко vs повільно (інакше лісоруб випередить сигнал):** next-RX-window-латентність (≈15 хв) прийнятна лише для **повільних** процесів (посуха, хвороба, кліматичний тренд) — там «феромонний слід» Queen встигає. Для **швидких** загроз (бензопила, пожежа) 15 хв = вже спиляне сусіднє дерево. Тут зворотний шлях НЕ через розклад, а через **emergency extended-preamble wake-up**: вузол-детектор (або Queen) подовжує LoRa-преамбулу довше за період сну приймачів, і low-duty-cycle CAD-приймачі гарантовано ловлять її під час свого мс-«нюху» ефіру → асинхронне масове пробудження кластера (справжній «нервовий імпульс»). Механізм — канон у [`03_01 §1.9`](03_01_Firmware_Lifecycle_and_DMA) (Emergency TX / preamble sampling) + [`03_02 §5`](03_02_Queen_Gateway_Firmware). Тобто stigmergy (повільний слід) і preamble-wake (швидкий імпульс) — **дві окремі доставки**, не одна.

**SRL шлях:** `SRL:Concept` (concept formulated) → `SRL:Pilot` (Q1 publication "Chimera states in tree-borne IoT sensors of Cherkasy Pine Forest") → `SRL:Deployed` (opt-in firmware extension у кластерах ≥ 100 дерев).

> ⚠️ **Ієрархічне делегування інтелекту (Compute Budget Constraint).** L1 Soldier (STM32WLE5JC + 0.47F supercap, енергобаланс [`02_03 §9.6`](02_03_BQ25570_MPPT_Nano_Power) Сценарій C = +1.4 мДж/год запасу) **фізично не може** тренувати моделі або агрегувати градієнти — будь-який Federated Learning epoch, обчислення Chimera coupling або forest-wide attractor inversion утримуватиме MCU в active-режимі (≥12 mA × ≥секунди) і **гарантовано виведе supercap у brownout** ще до завершення першої епохи. Тому:
>
> - **L1 Soldiers (STM32 + 0.47F):** залишаються наївними виконавцями (Inference only). Емітують 1-bit stigmergic сигнали (рядок «Stigmergic Communication» — це **єдина дешева опція** на L1, ~110 ms LoRa TX @ +14 dBm).
> - **L2 Conductors / L3 Queens (LiFePO4 + Solar):** тут відбуваються Federated Learning, Chimera coupling math та network-level Lorenz координація. Queen має 20Ah батарею і Cortex-M4 + LTE backbone — обчислювально на 4-5 порядків багатший за Soldier.
>
> Solidiers отримують результат як **скомпільований mruby bytecode через OTA-канал** ([`03_02`](03_02_Queen_Gateway_Firmware) Queen → broadcast chunks по 11 байт), що зберігається у `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`. Жодного "self-training" на L1. Зберігає SRL roadmap реалістичним.

### 1.2. Gap #2 — Self-Evolving Behaviour (On-Device Edge AI)

**Поточний стан:** OTA bytecode update існує ([`03_02`](03_02_Queen_Gateway_Firmware) mruby flash slot `0x0803F000`), але всі зміни приходять **зверху** (Rails backend → Queen → broadcast). Soldier — це **виконавець**, не **навчач**. Немає механізмів адаптації **без human-in-loop**.

**Чому це принципово важливо:**
- Жодний backend не передбачить всі мікроклімати (Карпати vs Полісся vs Амазонія) — параметри атрактора (σ, ρ, β) повинні **самоналаштовуватися** під локальні умови
- Дерева **ростуть і змінюються** за 20 років. Дерево 5-річне і дерево 25-річне — різні системи. Статичні OPTIMAL_Z_TARGET = 29.0 → false positives stress alerts через ~10 років
- Адаптивність — це **рівень життя** (Maturana & Varela: autopoiesis). Без неї Silken Net залишається **імплантом**, а не **симбіонтом**

**Технічні вектори вирішення:**

| Підхід | Принцип | Виклики на STM32WLE5JC |
|---|---|---|
| **On-Device Evolutionary Algorithms** | mruby VM запускає mini-GA: 4 candidate parameter sets для (σ, ρ, β) → fitness = local power efficiency × low oracle rejection rate → щотижня elite-selection нового baseline | RAM 64 KB; flash bytecode budget 8 KB; mruby int-math performance (~10⁵ ops/sec) — обмежує до < 10 generations/тиждень |
| **Edge Reinforcement Learning** | Tabular Q-learning з 12-state × 4-action lookup (state = bucketed Z + vcap + temp; action = sleep_extend/normal/sample_extra/emergency_tx); reward = days-to-next-VBAT_OK | RL потребує episode memory — RTC DR0..DR19 повні ([`03_01 §2`](03_01_Firmware_Lifecycle_and_DMA); DR20+ не існують на WLE5), тож Q-таблиця живе у Flash-KV ([`03_01 §2.3`](03_01_Firmware_Lifecycle_and_DMA)) / SRAM, не у RTC; ε-greedy schedule зашитий у firmware |
| **Адаптивна модифікація `bio_contract.rb`** | Не тільки параметри, але й **сама структура** атрактора може evolve: спершу Lorenz, потім Lorenz-96 (більша dim для дерев у кластерах), потім кастомні мутації через genetic programming | Безпекова перевірка: будь-яка self-modified contract має слотом для cryptographic anchor — інакше зловмисник може injection через RL reward poisoning |
| **TinyML Online Learning** | Поточний CMSIS-NN модель ([`03_03`](03_03_TinyML_Acoustic_Inference)) — frozen після training. Розширення: on-device class incremental learning з новими акустичними патернами (типу «нової інвазивної комахи у Черкаському борі») без необхідності retraining у cloud | На STM32WLE5JC можливо лише з 1–4 class incremental memory; full on-device backprop недосяжний — потрібен AI-чип coprocessor (Syntiant NDP120 або Maxim MAX78000) у v3 hardware |

**Безпекова прірва:** Self-evolution + Web3-economic incentives = **attack surface для adversarial evolution**. Зловмисник може спровокувати «вигідну для нього» мутацію через підставні sensor patterns. Mitigation — `1.4 Auto-Immune Sentinel`.

> ⚠️ **Compute Budget Paradox — L1 не "self-evolves" фізично.** Стовпчик «Виклики на STM32WLE5JC» вище **не** є інженерним планом запуску GA/RL/online-backprop на Soldier — це інвентаризація причин, **чому це неможливо** у поточному hardware envelope:
>
> - **mini-GA (4 candidate sets × multi-epoch fitness):** кожна fitness-епоха = повний цикл sense+Lorenz+TX (≈58 мДж/cycle, [`02_03 §9.4`](02_03_BQ25570_MPPT_Nano_Power)). 10 generations/тиждень × 4 candidates × 58 мДж = **2.3 Дж/тиждень додатково** при загальному робочому вікні supercap **3.87 Дж** ([`02_03 §8`](02_03_BQ25570_MPPT_Nano_Power)). → Перевищує бюджет у 4-6× після врахування sleep drain.
> - **Tabular Q-learning (12-state × 4-action):** сам lookup дешевий, але **reward сигнал = "days-to-next-VBAT_OK"** вимагає тижневих епізодів — ε-greedy exploration з 0.1 ймовірністю "sample_extra" з'їсть весь energy headroom Сценарію C (+1.4 мДж/год).
> - **TinyML on-device incremental learning:** full backprop на Cortex-M4 без AI-accelerator потребує seconds × 12 mA, що **гарантовано brownout**.
>
> **Ієрархічне делегування інтелекту (HW envelope перерозподіл):**
>
> | Рівень | Що відбувається | Hardware envelope |
> |--------|----------------|-------------------|
> | **L1 Soldier** | Inference-only: запуск **попередньо скомпільованого** mruby bytecode (Lorenz constants, fitness evaluation, threshold lookup). Періодична відправка `lambda_exponent` + 1-bit stigmergic сигналу. | STM32WLE5JC + 0.47F, +1.4 мДж/год headroom |
> | **L2 Conductor** *(Hub Tree, formerly "Sergeant")* | Кластерний агрегатор: збирає 50-200 Soldiers lambda-stream, обчислює **локальний GA** на (σ, ρ, β) для свого кластера, відправляє candidate sets до Queen. Динамічно обирається на основі `vcap` та якості зв'язку. | Solar + LiFePO4 (TBD spec, §2.1 L2 placeholder) |
> | **L3 Queen** *(Mother Tree)* | Агрегатор розподіленого навчання: для Lorenz — обмін **оцінками параметрів σ/ρ/β** (distributed parameter estimation, PSO/GA); для TinyML — **Cluster-level Edge Retraining** (ретренінг на даних кластера → `.tflite` OTA); *справжній* FL лише як Queen↔Rails обмін оновленнями моделі. Мотив — airtime/енергія, не privacy (дерева не мають GDPR-даних). Компілює mruby contracts, broadcast'ить chunked OTA. | 20Ah LiFePO4 + Solar + LTE backbone ([`02_05`](02_05_Queen_Hardware_and_Starlink)) |
>
> Q-learning, GA-evolution, online TinyML training **відбуваються на L2/L3 з обмеженням енергії на 4-5 порядків легшим**, ніж у Soldier. До Soldier приходить **готовий compiled bytecode через OTA** (магік `0x45544952 "RITE"` у `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`, [`03_02`](03_02_Queen_Gateway_Firmware)). Це усуває "self-training on edge" парадокс і зберігає SRL roadmap реалістичним.

**SRL шлях:** `SRL:Concept` (Q1 paper "Edge evolutionary Lorenz parameter tuning **за делегованою L2/L3 архітектурою**") → `SRL:Pilot` (opt-in firmware feature for select cluster owners) → `SRL:Deployed` (default behavior після формальної верифікації безпеки).

### 1.3. Gap #3 — Cross-Species / Cross-Biome Generalization

**Поточний стан:** Архітектура жорстко заточена під **Pinus sylvestris** Черкаського бору:
- Хімія EBFC ([`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)): Gen 2.0 baseline — dgrFAD-GDH + Laccase/ZIF-nanozyme + Genipin-Chitosan-CNC + Nafion-g-PSBMA — оптимізовані під pH 4.5–5.5 (хвойні)
- Геометрія анкера ([`01_01 §5.5`](01_01_Coaxial_Gyroid_Topology_and_PEEK)): пори 100–500 µm — оптимум для трахеїд 20–50 µm
- Lorenz-константи ([`03_04`](03_04_mruby_Lorenz_Attractor)): σ=10, ρ=28, β=8/3, OPTIMAL_Z=29 — калібровано на pine baseline
- Хірургічний протокол ([`01_04 §3`](01_04_CODIT_and_Xylemointegration)): Flush Mount + microfrezing для м'якої soft-wood сосни

**Чому це обмежує:**
- Дуб (*Quercus*) — пори 200–400 µm (кільцепориста) → потрібна інша геометрія гіроїда
- Береза (*Betula*) — pH ксилеми 5.5–6.5 (м'якше); FAD-GDH pH-вікно 4.0–8.0 покриває, але потенціали Os та Laccase потребують перекалібрування
- Мангрові (*Rhizophora*) — sap salinity 10–35 ppt → у Gen 2.0 ZIF-нанозим уже здатний нейтралізувати Cl⁻ (+7.5% активності), але потребує валідації на 30+ ppt
- Тропічні евкаліпти (*Eucalyptus*) — phenolic compounds 2–5× вищі за pine → CODIT-реакція агресивніша
- **«Planetary intelligence» означає biome-agnostic**, поточна архітектура — **species-specific instrument**

**Технічні вектори вирішення:**

| Шар | Що треба узагальнити | Як |
|---|---|---|
| **Hardware (BOM)** | 5 SKU замість 1: pine, oak, broadleaf, mangrove, tropical-hardwood — різна геометрія гіроїда, ферменти, anchor довжина | Параметрична CAD-модель у nTop (vs static). Stage 2 Ti-coin тести ([`01_01 §6.1`](01_01_Coaxial_Gyroid_Topology_and_PEEK)) на 5 синтетичних соках |
| **Firmware (Lorenz constants)** | `bio_contract.rb` приймає species_id → calibrated (σ, ρ, β) з flash table 16 × 24 bytes | OTA bytecode update із species-specific table; species_id зашитий у DID на provisioning |
| **Backend (Validation)** | `SilkenNet::Attractor` має model registry per-species; oracle dispatch validates against correct baseline | `MODEL_REGISTRY = { pine: '...', oak: '...' }` + migration `add_species to trees` |
| **DAO Governance** | Кожен new biome потребує community vote (SFC) + lab validation slot перш ніж SCC можуть мінтитись з нього | Розширення Slashing v2 на biome-specific stress detection thresholds |

**Партнерські школи:**
- Спрягайло ([`08_02 §1A`](08_02_Academic_Institutions_Registry)) — extension до інших порід ЧНУ Botanical Hub
- НАН України через школу НБС Гришка (intro Спрягайла, кандидатська 2013) — broadleaf і fruit tree calibration
- Future: international university partnerships (Brazil INPA для tropical, Australia CSIRO для eucalyptus, ASEAN MUSE для mangrove)

**SRL/MRL шлях:** `SRL:Concept` (multi-species PoC у 3 lab settings) → `SRL:Pilot` + `MRL:8` (deployed pilots у 3 biomes одночасно, мала серія 5 SKU) → `SRL:Deployed` + `MRL:10` (open framework + повносерійне виробництво per-biome SKU).

### 1.4. Gap #4 — Auto-Immune Sentinel (Proactive AI-Adversarial Security)

**Поточний стан:** DAO governance існує (SFC, [`05_03`](05_03_Tokenomics_SCC_and_SFC)), Slashing v2 реактивний ([`05_05 §6`](05_05_Slashing_and_Risk_Policy)), 12-chain pipeline має cross-validation ([`05_02`](05_02_Proof_of_Growth_Pipeline)). Але:
- **Немає proactive захисту від AI-driven economic attack** — coordinated manipulation SCC market через synthetic telemetry patterns
- **Oracle attack surface** — Chainlink DON має finite operator count; targeted bribe + adversarial generation може зсунути medianer
- **Slashing — реактивний**: чекає, поки факт зловживання stane on-chain, тоді штрафує. До цього моменту attacker вже випередив 1000× ROI на dump SCC

**Чому це принципово важливо:**
- Як тільки SCC market cap перевищить ~$100M (TRL 9 milestone), система стане **апетитною ціллю для AI-driven trading bots**
- Майбутні Generative AI зможуть синтезувати telemetry-патерни, які проходять **всі поточні fraud detection** (Dual Computation Integrity, oracle validation) — adversarial ML attacks
- **Без auto-immune sentinel Silken Net підданий тій самій долі, що й DeFi 2020–2024** (flash loan attacks, oracle manipulation, rug pulls) — але з фізичним лісом як collateral damage

**Технічні вектори вирішення:**

| Підхід | Принцип | Реалізація |
|---|---|---|
| **Proactive Anomaly Detection (Federated)** | Замість per-tree fraud detection — **cluster-level statistical fingerprints**. Якщо 100 дерев одного кластера раптом починають видавати «too perfect» Z-curves (lower variance than possible), це → suspicious | ML-сервіс у Rails + GA-оптимізація Любченка ([`08_02`](08_02_Academic_Institutions_Registry)); запит до Карапетяна (статистика, [`08_02 §2`](08_02_Academic_Institutions_Registry)) |
| **Adversarial Telemetry Generators (Red Team)** | Внутрішня команда генерує **GAN-вироблені синтетичні telemetry, які намагаються пройти Dual Computation** → знаходить вразливості до того, як їх знайде зовнішній attacker | Регулярні Red Team Exercises як частина CI/CD ([`04_06 §B`](04_06_Testing_Guide_and_Coverage)); Q1 paper "Adversarial robustness of bio-token mints" |
| **Decoy DID Tripwire (backend, НЕ on-chain honeypot)** | ⚠️ Виправлено: on-chain honeypot не працює — стейт контракту публічний, а навіть «реальне-але-заблоковане» дерево видає себе **відсутністю mint-подій** (атакер аналізує on-chain патерн і обходить). Тому — **бекенд-tripwire**: набір **decoy DID**, яких немає як реальних анкерів, у серверному watchlist (НЕ публікуються, НЕ on-chain). **Будь-яка телеметрія/mint-спроба від decoy DID = доведена підробка** (жоден реальний Soldier його не має) → instant alert + slashing + 12-chain rotation. Додатково: **Shadow Trees** — синтетичні фейкові дані у *публічному дашборді* (information warfare: торговий бот, що будує атаку на shadow-даних, руйнує свою стратегію). | Backend watchlist decoy DIDs + `TelemetryUnpackerService` tripwire (НЕ on-chain flag) |
| **Quantum-Resistant Oracle Migration** | ⚠️ PQC — це **асиметрична** проблема (Shor): вразливі ECDSA (Chainlink/Polygon/ETH), Ed25519 (peaq DID), ECDH-provisioning. **Симетричний LoRa/CoAP-трафік (AES-128/256) уже квантово-стійкий** (Grover лише √-ослаблення: AES-256 = 2¹²⁸) — на Soldier PQC-коду НЕ пишемо (Dilithium 2420 B не вміщається у 28B-пакет). Канон-дім — [`03_05 §10`](03_05_Hardware_Symmetric_Crypto_and_Security) (TRL-stratified roadmap). | Аблязов Д. (СЄУ, [`08_02 §5`](08_02_Academic_Institutions_Registry)) — правова рамка; Ярмілко ([`08_02`](08_02_Academic_Institutions_Registry)) — **лише асиметричний provisioning/identity шар** (Ed25519 + Dilithium-2 dual-sign, [`03_05 §10`](03_05_Hardware_Symmetric_Crypto_and_Security)), НЕ симетричний payload-crypto |
| **Auto-Immune Sentinel** | Окремий ML-сервіс, який моніторить весь стек 24/7 в режимі **«hunting for hunters»** — шукає координовані patterns між: trading volume на SCC DEXs + telemetry anomalies + oracle response patterns. Це **проактивний counter-AI** проти adversarial AI | Roadmap `SRL:Pilot`+; вимагає budget на dedicated AI/ML engineer; партнерство з академічними лабораторіями з ML security |

**Філософська позиція:** Silken Net — це **критична інфраструктура планетарного клімату**. Тому стандарт безпеки має бути не «не гірше за DeFi», а **на рівні national-grid SCADA**: continuous threat hunting, mandatory bug bounty, formal verification critical path.

**SRL шлях:** `SRL:Concept` (Red Team exercises у production) → `SRL:Pilot` (AI Sentinel deployed) → `SRL:Deployed` (formal verification of slashing protocol проти всіх відомих vectors).

### 1.5. Зведена Таблиця Чотирьох Прогалин

| # | Gap | Поточний стан (TRL 9) | Майбутній стан (SRL:Deployed) | Партнер | Q1 паперів |
|---|---|---|---|---|---|
| 1 | Forest-Level Emergence | Ізольовані Lorenz | Chimera states у network of attractors | Кирилюк, Гусак, Любченко | 2–3 (Synergetics + Network Science) |
| 2 | Self-Evolving Behaviour | Top-down OTA only | On-device edge GA + RL | Порубльов, Ярмілко | 2 (Edge AI + Evolutionary Comp.) |
| 3 | Cross-Biome Generalization | Pine-only | 5+ biomes, community-driven onboarding | Спрягайло + INPA/CSIRO/MUSE | 3–5 (per biome) |
| 4 | Auto-Immune Sentinel | Reactive Slashing | Proactive AI Sentinel + PQC | Аблязов Д., Карапетян, ML-security partners | 2 (Adversarial ML + Web3 Security) |

### 1.6. Як це впливає на TRL ladder

Ці 4 прогалини **не блокують** TRL 9 (commercial product можливий і без них). Але вони визначають **SRL-ієрархію за межами TRL 9** (а не «TRL 10-12»), яка перетворює Silken Net з **D-MRV-інструменту** на **планетарну нервову систему**:

```
TRL 9        ━━━ Operational. Stable SCC mint.                ← Silken Net як IoT-продукт
SRL:Concept  ━━━ Forest-level emergence + cross-biome PoC      ← Silken Net як нервова система
SRL:Pilot    ━━━ Self-evolving + AI Sentinel deployed          ← Silken Net як адаптивний симбіонт
SRL:Deployed ━━━ Verified, formal, planetary-scale autopoiesis ← Silken Net як планетарний інтелект
             (+ MRL:8-10 — серійне виробництво 5 SKU per biome)
```

Це **15-річний горизонт** (2026–2040+) — за ним вже сяє візія ([`08_02 §5`](08_02_Academic_Institutions_Registry)): D-MRV як база для **global climate governance protocol**, на рівні WTO або ISO.

### 1.7. Cross-references та де ще згадано

- **Gap #1 (Forest Emergence):** деталі у [`03_04 §6.3`](03_04_mruby_Lorenz_Attractor); координація з [`08_02 §1B`](08_02_Academic_Institutions_Registry) (Порубльов кібернетика) та [`08_02 §1A`](08_02_Academic_Institutions_Registry) (Кирилюк синергетика)
- **Gap #2 (Self-Evolving):** firmware extension у [`03_03 §Y`](03_03_TinyML_Acoustic_Inference) (TinyML online learning) + [`03_04 §Z`](03_04_mruby_Lorenz_Attractor) (mruby GA); безпекова валідація у [`05_03 §SCC Anti-Adversarial`](05_03_Tokenomics_SCC_and_SFC)
- **Gap #3 (Cross-Biome):** parametric CAD у [`01_01 §6`](01_01_Coaxial_Gyroid_Topology_and_PEEK) (Stages 2+ extended до 5 biomes); R&D у [`08_02 §1`](08_02_Academic_Institutions_Registry) (Спрягайло + НАН України канал)
- **Gap #4 (Auto-Immune Sentinel):** розширення Slashing v2 у [`05_05 §6`](05_05_Slashing_and_Risk_Policy) + [`05_06 §5`](05_06_Governance_and_DAO) + Chainlink hardening у [`05_02`](05_02_Proof_of_Growth_Pipeline)

---

## 🌐 2. Фрактальна Мережева Топологія — Planetary Network Scaling

> Поточна плоска LoRa-меш архітектура задихнеться від колізій та затримок вже на кількох тисячах вузлів. Для мільйонів дерев необхідна **фрактальна топологія**. Це мережевий (routing/topology) аналог §1 — там йшлося про *колективний інтелект*, тут — про *фізичне масштабування мережі*. Hardware/compute-envelope трьох рівнів (L1/L2/L3) описаний у [§1.2](#12-gap-2--self-evolving-behaviour-on-device-edge-ai) (таблиця делегування інтелекту); нижче — їхня **мережева роль і маршрутизація**.

### 2.1. Трьохрівнева ієрархія вузлів (The Fractal Stack)

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

### 2.2. H-LDSE — Ієрархічний Протокол Маршрутизації

Еволюція поточного LDSE-меш для мільйонної мережі:

| Механізм | Поточний LDSE | H-LDSE |
|----------|--------------|--------|
| Таблиця маршрутизації | Всі сусіди (OOM при >1000 вузлів) | Лише 2–3 хопи (локальна адресація) |
| Адресація | DID-based | Геохешинг (ID = координати) |
| Пошук шляху | TTL broadcast | Градієнтний потік до найближчої Queen |
| Частотні рівні | Один канал | Spatial Multiplexing (L1 → канал A, L2 → канал B) |

**Геохешинг:** Кожен супер-кластер отримує ID на основі координат. Пакет не шукає маршрут — він тече в бік зменшення градієнта до найближчої Королеви. Усуває broadcast storm.

> **⚠️ Розмежування рівнів: геохешинг — це здатність L2 Conductor, НЕ L1 Soldier.** Поточна прошивка ([`03_01`](03_01_Firmware_Lifecycle_and_DMA), [`08_02`](08_02_Academic_Institutions_Registry)) — наївний **TTL-flood relay** (PANIC_TTL=5, DEFAULT_TTL=3) без маршрутизації. Градієнтний геохешинг вимагає, щоб вузол оперував координатами та сусідським градієнтом — це покладається на **L2 Conductor** (має RTC, більший енергобюджет, відомі координати). **L1 Soldiers залишаються TTL-flood вузлами**, які просто «кричать» у радіусі свого найближчого L2 Conductor (відповідно до фрактальної ієрархії вище). H-LDSE — це цільова еволюція рівня L2, а не зміна поведінки L1.

**Spatial Multiplexing:** L1 та L2 працюють на різних частотних підканалах 868 MHz ISM — усуває міжрівневі колізії (inter-tier interference).

### 2.3. Edge Data Fusion — Стиснення Інформації

Замість передачі повних координат атрактора Лоренца, вузол передає лише **lambda-exponent** (показник хаотичності Ляпунова):

```
Поточний підхід:      16 байт payload → Z-координата Лоренца
Gaia 2.0 підхід:      2 байти lambda → описує стан всього дерева
```

> **Що зберігається:** lambda-exponent (показник Ляпунова) відображає ступінь хаотичності атрактора — достатньо для визначення "норма / стрес / аномалія". **Що втрачається:** абсолютні координати (X, Y, Z) — їх відновлення неможливе без повного ряду. Коли lambda перевищує поріг аномалії (`|λ| > λ_threshold`), Солдат автоматично переходить у режим повного стрімінгу з 16-байт payload — втрата інформації повністю усувається при критичних подіях.

> **⚠️ Стиснення × Dual Computation Integrity (design-flag).** Поточний DCI ([`03_04 §5`](03_04_mruby_Lorenz_Attractor)) порівнює device-Z vs server-recomputed-Z — точну координату після 250 ітерацій, чутливу до input-tampering майже на біт-рівні. У lambda-mode вузол передає лише скаляр Ляпунова, тож DCI змушений порівнювати **device-λ vs server-λ** (сервер так само рекомпʼютить λ з тих самих inputs + K_seed). Це **слабший** cross-check: λ — many-to-one відображення (різні траєкторії → той самий λ), тож простір підробки ширший, ніж проти точного Z. Тому lambda-compression лишається **Beyond-TRL-9** і не вмикається без DCI-захисту: періодичний **full-Z challenge** (random-sample вузли віддають 16-байт Z для калібрування) АБО λ + occasional Z-sentinel. Це **не** «fatal» для поточної архітектури (вона передає повний Z) — це передумова *безпечного* вмикання стиснення.

**Event-Triggered Reporting:** "Тиша означає здоров'я":
- Стабільний атрактор → heartbeat раз на добу (1 пакет/24 год)
- Атрактор "зривається" (пожежа / посуха) → безперервний стрімінг (~1 пакет/хв)

Скорочення трафіку в нормальному режимі в ~24× при збереженні повної чутливості до аномалій.

### 2.4. Network Sharding — Ізоляція Секторів

```
[Нормальний режим]      Cluster A ←→ Cluster B ←→ Cluster C

[Аномалія в Cluster B]  Cluster A | [B isolated] | Cluster C
                                    ↑
                         Вирубка / пожежа → шторм тривожних пакетів
                         не "кладе" сусідні кластери
```

**Queen-to-Queen Backhaul Mesh:** Королеви з'єднані між собою через LoRa SF12. Якщо одна Queen втрачає Starlink → передає дані сусідній Queen через LoRa-магістраль. Деталі — [`06_08 §Queen Failover`](06_08_Resilience_and_Failover_Policy).

### 2.5. Energy-Aware Routing (Load-Balanced)

Маршрутизація будується не за найкоротшим шляхом, а за **наявним енергозапасом**, з **вирівнюванням** навантаження по кластеру:

```
Route metric   = f(hop_count, vcap_headroom)        # НЕ bio_potential!
relay_eligible = vcap_mv > VCAP_SAFE_THRESHOLD       # інакше Mesh Relay Off
```

> **⚠️ Чому НЕ «найбільший біопотенціал» (попередня версія карала б успіх):** гнати трафік через найздоровіше дерево = покласти на нього 90% ретрансляції → виснаження іоністора → воно не встигає слати **власну** телеметрію → його Z-атрактор «падає» → система хибно класифікує здорове дерево як хворе. Подвійна вада: (1) **observer-effect** — мережеве навантаження спотворює сам сигнал, який система міряє (`bio_potential` — це **вимірюване**, а не ресурс маршрутизації); (2) позитивний зворотний зв'язок убиває найкращі вузли. **Правильно:** метрика залежить лише від **`vcap_headroom`** (доступна енергія, не здоров'я); дерево нижче `VCAP_SAFE_THRESHOLD` **відмовляється** бути реле (Mesh Relay Off), поки не відновить заряд — навіть якщо воно супер-здорове. Балансування **вирівнює** Vcap по кластеру, а не шукає «найбагатшого». Здоров'я дерева не перетворює його на раба мережі.

### 2.6. Вимоги до Rails Backend (Gaia 2.0 Scale)

| Компонент | Поточний стан | Gaia 2.0 вимога |
|-----------|--------------|----------------|
| Вхідний шар | CoAP прямо в Rails | Ingress Proxy (Rust/Go) → Kafka/Pub-Sub → Rails consumers |
| БД читання | Primary + Query | Read-Only Replicas для всіх аналітичних запитів та Oracle |
| TinyML навчання | Централізоване | **Cluster-level Edge Retraining** (на кластерах → OTA через `OtaPackagerService`); справжній FL лише як Queen↔Rails обмін оновленнями (делегування — §1.2) |

---

## 🪐 3. Beyond the Forest — GaiaNexus Planetary Federation

> **Горизонт цього розділу — найдальший** (за §1/§2, які масштабують *лісовий* net). Це **рамка
> найменування й візії, НЕ дорожня карта**: фокус проєкту лишається на **Silken Net** (ліс). Повний
> каталог планетарних процесів свідомо **не канонізується** ([`00_06 §4`](00_06_SSOT_Documentation_Standard) —
> Ruthless Pruning) — він живе як артефакт-нотатки, не baseline.

Інженерна абстракція Silken Net факторизується у **`PlanetaryNode`**: `Збір енергії → Сенсорика →
Оцифрування хаосу (Атрактор Лоренца) → Токенізація`. Той самий чотиритактний інваріант лягає не лише на
ксилемний сік дерева, а й на інші планетарні процеси — тож **Silken Net = перший інстанс** (орган
біосфери), а не кінцева система.

За геофізичними сферами Землі (кандидати рівня `SRL:Concept` — **НЕ** baseline, **НЕ** TRL-gated):

| Сфера | Net | `z`-сигнал (приклад) |
|---|---|---|
| Biosphere | **Silken Net** *(є)* | гомеостаз дерева (`delta_t` / акустика) |
| Cryosphere | Cryo Net | стабільність шельфу / альбедо |
| Hydrosphere | Abyssal Net | солоність / швидкість занурення (AMOC) |
| Lithosphere | Litho Net | тектонічна напруга (форшоки) |
| Pedosphere | Myco Net | мікробіом / іонні потоки ґрунту |

Інтегратор усіх сфер — **GaiaNexus**: федерація net-ів на спільному L1, де забезпеченням цінності стає
**планетарний гомеостаз** (звід `z` усіх сфер). Це фізичний контур **ноосфери** Вернадського; топологія
звʼязку — образ **сітки Індри** (кожен вузол-самоцвіт віддзеркалює стан усієї мережі). Назва-конвенція
та ™-розклад — [`08_01 §2`](08_01_Joint_Publications_and_IP_Strategy); near-term візія/місія —
[`00_01`](00_01_Vision_Mission_and_Roadmap).
