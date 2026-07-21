# 08_02: Реєстр Академічних Інституцій (Academic Institutions Registry)

## 🎯 Мета

Зведений **реєстр академічних партнерів** консорціуму MOIC (5 університетів) — хто, яка кафедра, що валідує і куди веде вихід. Консолідує колишні per-ВНЗ доки (ЧНУ Hard-Science, ФОТІУС, ЧДТУ, ЧІПБ, ЧМА, СЄУ): інженерна субстанція їхніх deliverable'ів **живе в каноні Tier I (01–06)** і **реферується** звідси, а не дублюється. Mission-концепція кластера, план публікацій та IP-рамка — [`08_01`](08_01_Joint_Publications_and_IP_Strategy); зовнішні (B2G/B2B) стейкхолдери — [`08_03`](08_03_External_Stakeholders_Registry).

> **Принцип (Zero-Trust / DRY):** жоден запис не блокує production-merge і не лежить у hot-path. Реєстр — це **матриця інтерфейсів** «партнер → що валідує → канонічний дім», а не художній есей і не копія інженерних деталей.

---

## ✅ Статус

- **Поточний TRL:** TRL 3 — партнери ідентифіковані, валідаційні треки окреслені; більшість — pre-contract. ЧНУ: ректорські зустрічі (Кирилюк 6 травня, Спрягайло 8 травня 2026) проведено, очікується рішення + парасольовий MoU. **Відкрите:** MoU ЧНУ + перші зустрічі ФОТІУС/ЧДТУ/ЧІПБ/ЧМА/СЄУ → [`00_07`](00_07_Action_Plan_Tracker) (UNI.*).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`08_01` — Joint Publications and IP Strategy](08_01_Joint_Publications_and_IP_Strategy) | MOIC-концепція (§0), план публікацій, IP-рамка — **голова кластера** |
| [`08_03` — External Stakeholders Registry](08_03_External_Stakeholders_Registry) | Зовнішні B2G/B2B + культурний шар (не академічні) |
| [`01_03` — EBFC Enzymatic Bio Fuel Cell](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) | EBFC — валідують ЧНУ Мінаєв (DFT) + ЧМА Бушуєва (ензими) |
| [`01_02` — Ti 6Al 4V Metallurgy and DMLS](01_02_Ti_6Al_4V_Metallurgy_and_DMLS) | Ti-довговічність/Kirkendall — ЧНУ Гусак + ЧМА Суховой (токсикологія) |
| [`03_03` — TinyML Acoustic Inference](03_03_TinyML_Acoustic_Inference) | §10 Soundscape — ЧДТУ ПМКТ (датасет) + наш NDVI-адаптер (open-data Sentinel-2) |
| [`03_04` — mruby Lorenz Attractor](03_04_mruby_Lorenz_Attractor) | Lorenz = status-гейт + DCI-anti-fraud; партнерська ланка = ground-truth-протокол §6 нижче |
| [`05_05` — Slashing and Risk Policy](05_05_Slashing_and_Risk_Policy) | §8 Ground-Truth Z↔health протокол (партнерський ростер — §6 нижче) |
| [`06_08` — Resilience and Failover Policy](06_08_Resilience_and_Failover_Policy) | Mesh percolation/Markov — надійність mesh |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Backend ML/DS = наш (`InsightGeneratorService`); статистична консультація — ЧДТУ Карапетян |
| [`07_01` — Nature as a Service Contracts](07_01_Nature_as_a_Service_Contracts) | NaaS/страхування — Кирилюк/Аблязов |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | UNI.* outreach-трекер |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [0. Реєстр у структурі MOIC](#-0-реєстр-у-структурі-moic)
- [1. ЧНУ — Черкаський національний університет](#-1-чну--черкаський-національний-університет)
- [2. ЧДТУ — Черкаський державний технологічний університет](#-2-чдту--черкаський-державний-технологічний-університет)
- [3. ЧІПБ — Черкаський інститут пожежної безпеки (ДСНС)](#-3-чіпб--черкаський-інститут-пожежної-безпеки-дснс)
- [4. ЧМА — Черкаська медична академія](#-4-чма--черкаська-медична-академія)
- [5. СЄУ — Східноєвропейський університет](#-5-сєу--східноєвропейський-університет)
- [6. Ground-Truth Validation — партнерський ростер](#-6-ground-truth-validation--партнерський-ростер)
<!-- TOC:AUTO:END -->

---

## 🌐 0. Реєстр у структурі MOIC

Кластер — **ортогональний Triple-Helix**: кожен ВНЗ закриває непересічну нішу, постачаючи Mission Controller'у (Silken Net + ActiveBridge) фундаментальні дані без перекриття. Концепція, архітектура довіри та «ортогональна карта» — [`08_01`](08_01_Joint_Publications_and_IP_Strategy). Нижче — операційний ростер:

| ВНЗ | Ніша | Рівень валідації |
|---|---|---|
| **ЧНУ** (Hard Science + ФОТІУС) | фізика/хімія/біологія + кібернетика/ПЗ/радіо | TRL 1–6 |
| **ЧДТУ** | дані/моделі, RF-виміри, акустика, прецизійна механіка | TRL 2–8 |
| **ЧІПБ** | пожежна безпека, ДСНС-міст | TRL 3–5 |
| **ЧМА** | біомедична валідація EBFC, токсикологія, ксилемоінтеграція | TRL 2–4 |
| **СЄУ** | макроекономіка токеноміки, RWA-право, промдизайн | TRL 1–5 |

---

## 🎓 1. ЧНУ — Черкаський національний університет

Домашня база (Архітектор — випускник ФОТІУС 2011, ПЗАС). Дві площини: **Hard Science** (хімія/фізика/біологія, TRL 1–4) і **ФОТІУС** (обчислювальна техніка/ПЗ/радіо, TRL 3–6). Парасольовий MoU — в.о. ректора Кирилюк (один підпис розблоковує ICP-MS/EIS/SEM-лабораторії + грантові заявки).

### 1A. Наукові школи (Hard Science)

| Партнер | Кафедра / роль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| проф. **Мінаєв Б.Ф.** (+ проф. Мінаєва В.О.) | хімія та наноматеріалознавство | Квантова хімія EBFC (DFT: dgrFAD-GDH/Os, Laccase-ZIF, PSBMA) → [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) + [`L3_quantum_chemistry`](protocols/ebfc/in_silico/L3_quantum_chemistry.md); DFT-адсорбція на TiO₂ (Ст.28) | Ст. 1/28 |
| проф. **Гусак А.М.** | фізика (Wiley-монографія, UCLA-колаб.) | Нанодифузія/Kirkendall: 20-річний V/Al release + PEEK creep → [`01_02 §2`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS), [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK); sheet-vs-network FEA-E homogenization ([`00_07` HW.33](00_07_Action_Plan_Tracker)); FEM термо-механіка Ti↔деревина (Ст.30) | Ст. 2/29/30 |
| доц. **Спрягайло О.В.** (проректор) + к.б.н. **Гаврилюк М.В.** (дир. ННІ) | біо-хаб (дендрофлора/ПЗФ/екологія) | *Pinus sylvestris* baseline + хім. склад ксилемного соку + dawn/dusk «Cherkasy Soundscape Library» → [`03_04`](03_04_mruby_Lorenz_Attractor), [`03_03 §10`](03_03_TinyML_Acoustic_Inference), [`01_04`](01_04_CODIT_and_Xylemointegration) | Ст. 2/24a/29/30/35 (Спрягайло) · 2/24a/35 (Гаврилюк) |
| проф. **Кирилюк Є.М.** (в.о. ректора) | ННІ економіки і права, біоекономіка/синергетика | Теор. база NaaS + біоекономіка; парасольовий MoU → [`07_01`](07_01_Nature_as_a_Service_Contracts); синергетика порогового гейта (Ст.34) | Ст. 34/35 |

> Протоколи Hard-Science (Quantum-Sap, Long-Term Integrity, Homeostasis Baseline, Xylem-Sim, Steril) — already-canon: дім у [`01_01 §6.1`](01_01_Coaxial_Gyroid_Topology_and_PEEK)/[`01_02`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)/[`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)/[`01_04 §6`](01_04_CODIT_and_Xylemointegration)/[`03_04`](03_04_mruby_Lorenz_Attractor) + [`in_silico/`](protocols/ebfc/in_silico/SUMMARY.md).

### 1B. ФОТІУС (обчислювальна техніка, інтелектуальні та управляючі системи)

| Партнер | Профіль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| доц. **Ярмілко А.В.** | IIoT / embedded / lightweight crypto | Engaged partner (зустрічі 2026, вхід у ректорат); airtime↔крипто tradeoff-аналіз (Ст.23); SPI/DMA-консультація ([`03_01`](03_01_Firmware_Lifecycle_and_DMA) — Open-Research) | Ст. 23/24 |
| доц. **Косенюк Г.В.** | військова радіотехніка, теорія кодування | RF impedance / Link Budget / ground-plane / 3D-діаграма з Ti-фланцем як Ground Plane ([`02_01 §5`](02_01_Hardware_Architecture_and_BOM)) — фізична лаб-валідація прихованої антени під PEEK (TRL-гейт) | Ст. 23 |
| ст.викл. **Любченко К.М.** | нейромережі, GA, Master of Logic | Ст.24a + 2 магістерські: NSGA-II 5-class TinyML tuning + циркадні пороги ([`03_03`](03_03_TinyML_Acoustic_Inference)) — метод generic (pymoo), gate = ground-truth Біо-хаб | Ст. 24a |

> **План публікацій ЧНУ:** [`08_01 §1`](08_01_Joint_Publications_and_IP_Strategy) (Hard Science + ФОТІУС) · [`08_01 §1C`](08_01_Joint_Publications_and_IP_Strategy) (ФОТІУС × ЧДТУ синергія) · [`08_01 §1G`](08_01_Joint_Publications_and_IP_Strategy) (ректорат ННІ — біоекономіка/синергетика).

---

## 📡 2. ЧДТУ — Черкаський державний технологічний університет

Комплементарний до ЧНУ (3 кафедри): закриває **дані/моделі**, **радіоканал** (лабораторна верифікація розрахунків Косенюка), **акустичний hardware** та **прецизійну механіку**.

| Партнер | Кафедра / роль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| доц. **Карапетян А.Р.** (зав.) | статистика та прикл. математика (R/Data Science) | Anomaly/fraud-статистика телеметрії (`FRAUD_DEVIATION_THRESHOLD`, Ст.13) + biodiversity fusion-статистика (ANOVA/permutation, Ст.24a) + ground-truth Z-калібрація (§6) → [`04_02`](04_02_Business_Logic_and_Services), [`05_05`](05_05_Slashing_and_Risk_Policy) | Ст. 13/24a |
| декан **Гончаров А.** | ФЕТР, радіотехніка | Експериментальна RF-верифікація (VNA S11, EMC pre-scan, натурний Link Budget) розрахунків Косенюка → [`02_01 §5`](02_01_Hardware_Architecture_and_BOM) | Ст. 23 |
| проф. **Базіло К.В.** + проф. **Бондаренко М.О.** | ПМКТ, акустична мехатроніка | Валідація фононної лінзи гіроїда (EIS + AE) + **калібрувальний TinyML-датасет** (польова валідність 5-class моделі — [`03_03 §4.1`](03_03_TinyML_Acoustic_Inference)); резонанс п'єзо у діапазоні фауни 0.5–12 кГц (Ст.24a) | Ст. 24/24a |
| доц. **Хоменко Ю.В.** | металорізальні верстати (80+ патентів) | CNC post-DMLS (PEEK Zone 2 фрезерування, bayonet, катод Zone 3) + різальна геометрія анкера → [`01_01`](01_01_Coaxial_Gyroid_Topology_and_PEEK), [`01_02`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS), [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface) | — |

> Повний реєстр Data-Science задач (≈10 тем × методи) — research-агенда рівня публікацій; інженерні точки дотику вже в каноні (`InsightGeneratorService`, `Attractor`, `dClimate`, `ParametricInsurance`). Деталі методів — у спільних статтях [`08_01 §1B`](08_01_Joint_Publications_and_IP_Strategy).

> ⚖️ **Карапетян trim (2026-07-21, UNI.19-лінія):** real-fit статистик (к.т.н. «Інформаційні технології», методи оптимізації/R), але була over-attributed на 5 статей. Зняті **Ст.34** (Ляпунов/RQA — нелінійна динаміка поза її документованим фахом + аналіз декоративної динаміки: Z «емпірично degenerate + temp-confounded», [`03_04 §4`](03_04_mruby_Lorenz_Attractor); константи атрактора фіксовані/textbook), **Ст.24** (тонка статистична гарнітура на future-ultrasonic фізику Базіло/Бондаренка) і **Ст.31** (Monte Carlo власного контракту → self-owned; статтю несе Чудаєва). Лишились **genuine-fit 13+24a** (класична anomaly/fraud + ANOVA/permutation — точний R-фах). git тримає зняте.

---

## 🔥 3. ЧІПБ — Черкаський інститут пожежної безпеки (ДСНС)

B2G-міст до ДСНС + академічне обґрунтування SOP реагування на кіберфізичні тривоги. Двоє профільних експертів: Биченко (тактика гасіння / керівництво діями підрозділів → диспетчеризація + drone-розвідка), Ротар (правова компетентність ЦЗ, тактичні алгоритми → SOP-регламентація).

| Партнер | Роль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| **Биченко А.** | диспетчеризація | Інтеграція EWS ↔ протоколи реагування ДСНС → [`04_02`](04_02_Business_Logic_and_Services) (`EwsAlert`/`AlertDispatch`) | Ст. 26 |
| **Ротар В.** | SOP | SOP-документи per alert_type (field ops) → [`04_02`](04_02_Business_Logic_and_Services) (EwsAlert/AlertDispatch — дім); трек [`00_07` ARCH.31/UNI.12](00_07_Action_Plan_Tracker) (SOP-compliance = зворотний бік Кат-A negligence-evidence для slashing) | Ст. 26 |

> **План публікацій ЧІПБ:** [`08_01 §1D`](08_01_Joint_Publications_and_IP_Strategy) (ДСНС SOP).

---

## 🧬 4. ЧМА — Черкаська медична академія

Біомедична валідація EBFC + токсикологія Ti + ксилемоінтеграція як аналогія остеоінтеграції.

| Партнер | Роль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| **Губенко І.** (ректор) | біосумісність | Макро-біосумісність + ксилемоінтеграція ↔ CODIT-каскад → [`01_04`](01_04_CODIT_and_Xylemointegration) | Ст. 30 |
| **Боєчко В.** | фізіологія стресу | Preclinical stress signature + recovery curve → незалежні ground-truth мітки для `stress_index` ([`04_02`](04_02_Business_Logic_and_Services); блокер E.52) + CODIT-aware калібрація ([`01_04`](01_04_CODIT_and_Xylemointegration)) | Ст. 30 |
| **Бушуєва І.** | фармацевтичні дисципліни | EBFC ензимна іммобілізація (валідація стеку Gen 2.0) → [`01_03 §2`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell) | Ст. 28 |
| **Суховой Г.** | токсикологія | Токсикологія Ti-6Al-4V (V/Al release у ксилему) → [`01_02`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS), [`01_04`](01_04_CODIT_and_Xylemointegration) | Ст. 29 |
| **Глущенко О.** | покриття | Self-healing 8-HQ мікрокапсули — **already-canon** → [`01_02 §3`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS); Os redox polymer стабільність + cross-linking (Ст.28) | Ст. 28/29 |

> **План публікацій ЧМА:** [`08_01 §1E`](08_01_Joint_Publications_and_IP_Strategy) (біохімія EBFC, токсикологія Ti, ксилемоінтеграція).

---

## 💼 5. СЄУ — Східноєвропейський університет

Економіка/право/дизайн. **Diff від Кирилюка (ЧНУ):** СЄУ = прикладний макро-стрес-тест + legal wrapper + промдизайн; Кирилюк — фундаментальна біоекономічна рамка.

| Партнер | Роль | Що валідує → канон-дім | Публ. |
|---|---|---|---|
| **Чудаєва І.Б.** (ректор СЄУ) | макроекономіка | Стрес-тест dual-token (інфляція, Dynamic Tax 2%, рівновага) → [`05_03`](05_03_Tokenomics_SCC_and_SFC); макро-модель SCC-ринку живить біфуркаційний макро-шар Ст.34 і регіональний Ст.35 | Ст. 31/34/35 |
| **Ус Г.О.** | unit-econ / ESG | ESG-облік, KlimaDAO retirement, loss ratio → [`05_03`](05_03_Tokenomics_SCC_and_SFC), [`07_02`](07_02_Unit_Economics_and_BOM) | Ст. 31 |
| **Аблязов Д.Е.** | право | RWA legal architecture (ERC-3643), KYC/AML templates → [`07_01`](07_01_Nature_as_a_Service_Contracts), [`05_06`](05_06_Governance_and_DAO); правова сумісність токенізації з режимом ПЗФ (Ст.35) | Ст. 32/35 |
| **Гедз М.Й.** | аудит D-MRV | Методологічний аудит pipeline (IoTeX→Chainlink→mint, DCI) → [`05_02`](05_02_Proof_of_Growth_Pipeline) | Ст. 32/35 |
| **Денисенко Ю.М.** | промисловий дизайн | Біомімікрічний антивандальний PEEK-радом капсули → [`02_01`](02_01_Hardware_Architecture_and_BOM), [`02_02`](02_02_Blind_Mate_Pogo_Pin_Interface) | — |
| **Теліженко О.В.** (Олександра) | етнодизайн / UX | Народний художник України (етнодизайн, монументальне мистецтво). Орнаментальний патерн-бренд: «Silken Net» = текстильна метафора, mesh-топологія що обплітає бір ≈ рушник-оберіг → [`04_04`](04_04_Phlex_UI_and_Tailwind) (Phlex UI motifs), [`02_05`](02_05_Queen_Hardware_and_Starlink) (Queen radome graphics); B2B data-viz / UX-дашборд для ESG-інвесторів; Genesis NFT → [`08_03`](08_03_External_Stakeholders_Registry) | — |

> **План публікацій СЄУ:** [`08_01 §1F`](08_01_Joint_Publications_and_IP_Strategy) (токеноміка, RWA-право).

---

## 🔬 6. Ground-Truth Validation — партнерський ростер

Протокол валідації гіпотези «Лоренц Z ↔ здоров'я дерева» (когорта 20–30 дерев, незалежний ground-truth, калібрування slashing-порогів, `SilkenNet::LorenzValidationService`) — канонічний дім [`05_05 §8`](05_05_Slashing_and_Risk_Policy) (вихід протоколу = пороги ризику/slashing; «одна річ — один дім»).

**Ростер для протоколу:** польова когорта Черкаського бору + незалежний ground-truth (sap-flow, дендрометр, NDVI, експертний бал) — **ЧНУ біо-хаб** (Спрягайло/Гаврилюк, UNI.13a) + **Data Science ЧДТУ** (Карапетян, §2, UNI.9) + **лабораторія Гусака** (§1A, UNI.5). Deliverable — **калібрування предиктивності Z** (вихід протоколу = пороги ризику/slashing). Публікаційного виходу НЕМА — стаття можлива лише ПІСЛЯ позитивного протоколу, не до нього.
