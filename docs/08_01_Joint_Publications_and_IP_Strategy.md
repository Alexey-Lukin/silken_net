# 08_01: MOIC, Спільні Публікації та Стратегія IP

## 🎯 Мета

Легітимізація технології Silken Net у світовому науковому просторі та юридичне закріплення прав на інтелектуальну власність у межах співпраці ЧНУ та Silken Net. Формування системи публікацій, що охоплює весь технологічний стек від фізики анкера до математики токеноміки.

> **Принцип партнерства:** Silken Net надає інноваційний R&D-полігон. ЧНУ надає академічну легітимність та лабораторну інфраструктуру.

> **Карта документа** (cluster head Модуля 08, ~4 блоки): **§0** MOIC — місія/архітектура кластера · **§1–§1E** план публікацій (per-ВНЗ; нумерація рідка — діри = вилучені статті, номери НЕ перевикористовуються заради crossref-стабільності) · **§2–§2.1** IP-рамка (розподіл прав + TISC/trademark/юр-review). Реєстр самих ВНЗ-партнерів (хто / що валідує) — [`08_02`](08_02_Academic_Institutions_Registry); зовнішні стейкхолдери — [`08_03`](08_03_External_Stakeholders_Registry).

---

## ✅ Статус

- **Поточний TRL:** TRL 3 — Zero-Lab in-silico pipeline L1-L4 ✅ (2026-05-25; аналітичний PoC). Фізичний TRL 4 = in-vitro Ti-coin (Stage 2, pending) — канон [`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond).
- **Стратегічна цінність:** Наукові публікації ЧНУ + ЧДТУ (3 кафедри) + ЧІПБ + ЧМА + СЄУ = легітимізація технології + Hardware Proof для seed-раунду + Data Science валідація + RF-верифікація + акустична валідація + пожежна безпека + біохімічна валідація EBFC та токсикологія + макроекономічна валідація токеноміки та правова архітектура RWA
- **Відкрите:** спільні публікації + defensive-publication / open-license execution (потребує MoU) → [`00_07`](00_07_Action_Plan_Tracker) (UNI.*).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`08_02` — Academic Institutions Registry](08_02_Academic_Institutions_Registry) | Реєстр 5 ВНЗ-партнерів (хто / що валідує) — автори цих публікацій |
| [`08_03` — External Stakeholders Registry](08_03_External_Stakeholders_Registry) | Зовнішні B2G/B2B + культурний шар |
| [`07_02` — Unit Economics and BOM](07_02_Unit_Economics_and_BOM) | Юніт-економіка |
| [`05_03` — Tokenomics SCC and SFC](05_03_Tokenomics_SCC_and_SFC) | Токеноміка |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | UNI.* |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Відкриті передумови та статус](#-відкриті-передумови-та-статус)
- [0. MOIC — Mission-Oriented Innovation Cluster (Концепція та Архітектура Кластера)](#-0-moic--mission-oriented-innovation-cluster-концепція-та-архітектура-кластера)
- [1. План Публікацій (Scopus / Web of Science)](#-1-план-публікацій-scopus--web-of-science)
- [1B. Публікації ЧДТУ (Data Science)](#-1b-публікації-чдту-data-science)
- [1C. Міжуніверситетські Публікації (ЧНУ ФОТІУС × ЧДТУ)](#-1c-міжуніверситетські-публікації-чну-фотіус--чдту)
- [1E. Публікації ЧМА (Біохімія EBFC, Токсикологія)](#-1e-публікації-чма-біохімія-ebfc-токсикологія)
- [2. Розподіл Інтелектуальної Власності (IP Framework)](#-2-розподіл-інтелектуальної-власності-ip-framework)
- [2.1. IP-інструменти (TISC-консультація + trademark + UA-юр-review)](#-21-ip-інструменти-tisc-консультація--trademark--ua-юр-review)
<!-- TOC:AUTO:END -->

---

## 🚧 Відкриті передумови та статус

> Статуси трекаються в [`00_07`](00_07_Action_Plan_Tracker) (UNI.*); нижче — контекст партнерства.

- **Лабораторні дані відсутні** — більшість статей нижче gated на лабораторію (мокра хімія / ICP-MS / VNA / акустичний стенд). **Виняток — Стаття 1**: суто in-silico, дані готові, **submission-ready** без лабораторії й без партнера.
- **Авторський колектив не сформований** — партнери ідентифіковані, але **жоден не залучений** (MoU не підписаний; UNI.12 = «cold contact» ще не зроблено). Планування виходить з того, що **founder пише сам**; двері для партнерів відкриті.
- **Co-authorship + open-license MoU** — до початку спільних робіт (§2). Патентної заявки немає (defensive-publication постава §2)

> 🔪 **Критерій складу портфеля:** стаття лишається, лише якщо потрібна для **наукового підтвердження silken_net** — доводить, що система працює / легітимна / defensible (або знадобиться в майбутньому). **НЕ критерій** «алгоритм є в коді»: мокра хімія, лабораторна фізика й радіо-виміри за природою не в коді, і саме вони — найбільші фізичні невідомі (TRL-3-гейт anchor/EBFC). **Ключове розрізнення:** «робота потрібна» ≠ «стаття про неї потрібна» — SOP треба написати ([`00_07` ARCH.31](00_07_Action_Plan_Tracker)), юніт-економіку перерахувати ([`07_02 §7.3`](07_02_Unit_Economics_and_BOM) сам зве себе «НЕ committed-число»), але це не Q1-публікації. **Виконавець не важить** (партнери мовчать — founder робить сам); партнер вибуває з портфеля, лише якщо не лишилось **жодної** живої ланки. Вилучене git тримає — повернення коштує один `git show`.

---

## 🌐 0. MOIC — Mission-Oriented Innovation Cluster (Концепція та Архітектура Кластера)

> **Положення SSOT:** Цей розділ є канонічним описом **Продуктово-орієнтованого інноваційного кластера (MOIC)** екосистеми SilkenNet. Профілі п'яти ВНЗ консорціуму — у реєстрі [`08_02`](08_02_Academic_Institutions_Registry) (§1 ЧНУ [Hard Science §1A + ФОТІУС §1B], §2 ЧДТУ, §3 ЧІПБ, §4 ЧМА, §5 СЄУ); зовнішні B2G/B2B та культурний шар — [`08_03`](08_03_External_Stakeholders_Registry). Кожен профіль реалізує одну з ланок MOIC і читається як похідна цієї рамки. Існуюча модель «Потрійної Спіралі» (класична Triple Helix — §0.2) є частковою реалізацією MOIC; тут вона уніфікована під єдиним терміном.

### 0.1. The Grand Mission

SilkenNet об'єднує сім академічних та індустріальних вузлів навколо **єдиної фундаментальної місії**:

> **Створення першої у світі автономної, trustless D-MRV (Digital Measurement, Reporting, Verification) системи для моніторингу природного капіталу планетарного масштабу.**

Цільовий продукт — не «черговий IoT-датчик», а **зміна парадигми**: дерево перестає бути пасивним об'єктом екології і стає **активним економічним агентом**, який:
- має доводити життєздатність криптографічними ZK-доказами (IoTeX W3bstream, [`05_02`](05_02_Proof_of_Growth_Pipeline)) — ціль: ZK→mint наразі optimistic-L0, не enforced (ARCH.53),
- сам фінансує свій захист через Web3-ринок RWA-активів (Polygon SCC + Hadron ERC-3643, [`05_01`](05_01_Multichain_Architecture), [`05_03`](05_03_Tokenomics_SCC_and_SFC)),
- emit'ить власний грошовий потік (NaaS-контракти, [`07_01`](07_01_Nature_as_a_Service_Contracts)).

Така постановка автоматично виключає три провали ринку: (а) ручний аудит Verra/Gold Standard як bottleneck та джерело «green-washing», (б) централізовані MRV-платформи з gatekeeping, (в) сателіт-only підходи без ground-truth (cross-ref Стаття 24a, Mongabay-pivot).

### 0.2. Архітектура Довіри — Ортогональний Triple-Helix Консорціум

Для проблеми такого масштабу одного стартапу недостатньо. MOIC побудований за моделлю **Triple Helix (наука + бізнес + держава)**, але з критичною модифікацією: академічна вершина спіралі **ортогональна** — кожен з п'яти університетів закриває **виключно свою** ланку інфраструктури без дублювання.

**Ролі трьох вершин:**

1. **Бізнес-інтегратор як Mission Controller (TRL 8).**
   Silken Net (IP holder + system integrator) разом з ActiveBridge (software development) діють як **Mission Controller**: перетворюють фундаментальні дослідження п'яти університетів на робочий код (`app/services/`, [`05_02`](05_02_Proof_of_Growth_Pipeline)), мікросхеми (STM32WLE5JC firmware, [`03_01`](03_01_Firmware_Lifecycle_and_DMA)) та смарт-контракти (`contracts/SilkenCarbonCoin.sol`, `contracts/SilkenForestCoin.sol`). Mission Controller володіє правом ухвалення рішень про напрям R&D, розподіл ресурсів між модулями та фінальною інтеграцією; академічні партнери постачають верифіковані модулі.

2. **Академічний консорціум — ортогональний.**
   Кожен з п'яти університетів закриває **виключно свою** ланку без дублювання. Розподіл нижче (§0.3) є **інваріантом MOIC** — будь-яке нове залучення (наприклад, додатковий університет або дослідницький інститут) повинно або займати порожню комірку, або еволюціонувати існуючу без перекриття.

   > **Режим залучення (чесно):** 2 лаб-MoU (ЧНУ/ЧДТУ — розблокують ICP-MS/VNA/акустику) + персональні контакти (СЄУ/ЧІПБ/ЧМА, люди без лаб-доступу). Партнери **ідентифіковані, не законтрактовані** — жоден MoU ще не підписаний.

3. **Держава / регулятор / end-user.**
   Не пасивний споживач, а **третя вершина спіралі**: Черкаська ОДА (Стратегія розвитку області, ПЗФ-інтеграція через Спрягайла, [`08_02 §1A`](08_02_Academic_Institutions_Registry)), ДСНС (інтеграція EwsAlert через ЧІПБ, [`08_02 §3`](08_02_Academic_Institutions_Registry)), європейські реєстри (ISO 14064 / ICROA mapping — профільний carbon-методолог, [`00_07` BIZ.9](00_07_Action_Plan_Tracker)).
   > **Чесно (симетрично п.2):** контакти опосередковані (ОДА → через Спрягайла, ДСНС → через ЧІПБ) або TBD (carbon-методолог ще не залучений) — прямого MoU з жодним із цих вузлів не підписано.

### 0.3. Hard Science Layer ↔ Business Layer (Ортогональна Карта)

Уся наукова база розділена на дві **непересічні** вертикалі:

- **Hard Science Layer** — генерація даних та моделей: фізика, хімія, біологія, статистика, RF, акустика, біохімія. Виходи: лабораторні дані, валідовані моделі, Q1-публікації.
- **Business Layer** — перетворення даних та моделей на артефакти для інституційного капіталу: токеноміка, право, аудит D-MRV, параметричне страхування, фреймворки якості. Виходи: юридичні шаблони, ESG-фреймворки, актуарні моделі, MoU-структури.

| ВНЗ | Layer | Ортогональна ніша | Доменний документ | Деталі ролей |
|-----|-------|--------------------|---------------------|---------------|
| **ЧНУ (ректорат + hard-science школи)** | Hard Science | Фізика твердого тіла (Гусак), квантова хімія (Мінаєв), біоценологія/дендрологія (Спрягайло, Гаврилюк), кібернетика ФОТІУС (Ярмілко, Косенюк, Любченко) + інституційна парасоля (Спрягайло) | [`08_02 §1`](08_02_Academic_Institutions_Registry) | [§1, §1C](#-1-план-публікацій-scopus--web-of-science) |
| **ЧДТУ (3 кафедри)** | Hard Science | Data Science та статистика (Карапетян, кафедра статистики), радіофізика/signal-processing (Гончаров — перший проректор ЧДТУ, каф. РТРС), акустична мехатроніка та п'єзохарактеризація (Базіло, Бондаренко, ПМКТ) | [`08_02 §2`](08_02_Academic_Institutions_Registry) | [§1B](#-1b-публікації-чдту-data-science) |
| **ЧМА** | Hard Science | Токсикологія Ti-6Al-4V (Суховий), фітотоксикологія покриттів (Глущенко), фарм-стабілізація ферментів (Бушуєва — дотично); глибока EBFC-ензимологія → профільний біохімік (TBD); інституційний доступ — персонально | [`08_02 §4`](08_02_Academic_Institutions_Registry) | [§1E](#-1e-публікації-чма-біохімія-ebfc-токсикологія) |
| **ЧІПБ** | Business (regulated safety) | SOP реагування ДСНС на кіберфізичні тривоги: диспетчеризація + drone-розвідка (Биченко — тактика гасіння), SOP per alert_type (Ротар — правова регламентація) | [`08_02 §3`](08_02_Academic_Institutions_Registry) | [`00_07` ARCH.31/UNI.12](00_07_Action_Plan_Tracker) |
| **СЄУ** | Business | UA-правова рамка RWA + господарське право (Аблязов Д.), фінансовий облік криптоактивів (Гедз), цифрова економіка + моделювання (Ус); дизайн — self | [`08_02 §5`](08_02_Academic_Institutions_Registry) | — |
| **Silken Net + ActiveBridge** | Mission Controller | IP holder, system integrator, firmware/backend/contracts, фінальна інтеграція всіх модулів консорціуму у TRL 8 продукт | [`08_02 §5`](08_02_Academic_Institutions_Registry) | — |

> **Принцип ортогональності:** жодна комірка `(ВНЗ, ніша)` не дублюється. Якщо два університети потенційно претендують на одну тему то межа проходить за **об'єктом аналізу** (напр. ЧДТУ веде статистичне виявлення аномалій та шахрайства — Ст.13); перетин фіксується як **міжуніверситетська синергія** (зона §1C).

---

## 📚 1. План Публікацій (Scopus / Web of Science)

Серія фундаментальних статей для журналів рівня Q1/Q2 на перетині кіберфізики, матеріалознавства та екології:

> 🔍 **Перед сабмітом / передачею співавтору будь-якої з робіт нижче** — прогнати [`self_review_checklist`](protocols/paper/self_review_checklist.md) (citation-gate · 5-lens · anti-sycophancy · чесні межі). Тонкий self-review, не peer review; рішення завжди автора.

> ⚠️ **Дві наскрізні примітки до всіх магістерських/аспірантських робіт нижче:**
> 1. **Trade-secret (звужено під open-поставою §2):** код відкритий під AGPL → формат пакета та lightweight-crypto інтеграція **більше НЕ secret** (вони у відкритому firmware). Реальні секрети — **лише криптоключі** (ніколи не публікуються), production-дані, ваги ML. Обфускація макетів для tech не потрібна; публікація вільна (**publish-to-protect**, §2). Студентські роботи відкриваються в репозиторіях ВНЗ безперешкодно (крім роботи з реальними ключами/даними).
> 2. **Open-license + co-authorship:** результати студентських робіт — під open-license (§2; AGPL/CERN-OHL-S/CC-BY-SA) зі стандартним співавторством; **жодного embargo** (publish-to-protect, §2).

### Стаття 1: Електрон-трансферна енергетика EBFC Gen 2.0 (квантова хімія, Пріоритет: Перша)

> ⚠️ **Переформульовано (2026-06-05) — чесна рамка замість overclaim.** Стара назва *"Quantum-Chemical **Validation**…"* суперечила власним результатам L3: сирий обчислювальний вердикт каскаду FADH₂→Os — **uphill у кожному методі** (B3LYP Koopmans −1.05 eV на реальному dimethyl-медіаторі; ωB97X ΔSCF adiabatic +1.03 eV dimethyl / +0.88 eV plain, B1/B2 ✅), а downhill — це **верифіковані E°s** (+574 мВ: Os +309 − FAD-GDH −265 мВ SHE, Zafar 2012 + Schachinger 2023); стара «−0.07 ≈ −0.14 (Cosnier)» bias-корекція стояла на хибному +60 мВ FAD і **withdrawn**. Тобто обчислення не «валідує» — воно експонує межу методу; «validation» = reviewer-landmine. Переорієнтовано на **механізм + межі методу** (повний аудит — `docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md`). (ICP-MS Ti/Al/V перенесено → Стаття 2.)

**Назва (EN):** _"Computational Electron-Transfer Energetics of a FAD–Osmium Enzymatic Biofuel Cell: PCET Redox Potentials, Mediator Structure–Activity, ZIF-Nanozyme Direct Electron Transfer, and the Limits of Implicit-Solvation DFT"_

**Тип:** суто обчислювальна (quantum-chemistry) стаття — фізичний експеримент (Ti-coin CV/EIS) попереду (Stage 2) → ставка на **механістичну + методологічну** новизну, не на «валідацію».

**Журнали-цілі:** *J. Phys. Chem. B* (ACS, **primary** — enzyme catalysis + computational scope, прямий mediator-design прецедент) · *Phys. Chem. Chem. Phys.* (RSC, **fallback** — дім школи Мінаєва, OA-waiver для ЧНУ) · *Bioelectrochemistry* (Elsevier, applied-backup). НЕ *J. Power Sources* / *Electrochimica Acta* — comp-only поза їх scope без експерименту.

**Авторський колектив:**
- Архітектор (Silken Net) — in-silico baseline (PySCF DFT/ΔSCF, AF3, tunneling), дизайн каскаду, draft. **Пишеться зараз** на готових результатах.
- **Мінаєв-роль (reframe):** explicit-water QM/MM редоксу — **не** метод школи Мінаєва (їхній фах = spin-orbit / активація O₂, не ground-state solvation-термодинаміка). PCM-межу закриває власний follow-up або профільна computational-electrochemistry колаборація (TBD). Школа Мінаєва — потенційний co-author за **окремим** real-fit кутом: spin-forbidden кінетика активації O₂ на біоелектродах (майбутня EBFC-стаття, не scope цієї). Ст.1 лишається submission-ready як own in-silico (без gated-партнера).

**Foreground (сильні, чисті результати — обличчя статті):**
- **PCET редокс-потенціал FAD** — proton thermodynamic reference відтворює E°(FAD/FADH₂) у межах ~50 mV від експ. free-flavin (значення → `SUMMARY.md`, script 32).
- **Mediator structure–activity (Hammett LFER ①)** — E°(Os III/II) лінійний у σ_para (нахил ≈ −0.92 eV/σ) → **предиктивне правило дизайну** медіатора; реалістичний оптимум = інертний **SO₂CF₃** (NO₂ деградує на циклюванні). Триангульовано DFT↔Lever↔Hammett (числа → `SUMMARY.md` §Mediator, script 21e).
- **DET через ZIF-нанозим** — ΔSCF hopping (geom-fixed) + computed Nelsen λ: a λ-sensitive cathode margin — **borderline** at realistic λ (Cu-Co ~turnover, не old ×10⁵) + a low-λ-metal (Ru) design rule (числа → `SUMMARY.md` §Cathode, scripts 23/24/25/35).
- **Геометрія + through-bond tunneling pathway** анода — глибина залягання FAD < tunneling-межі (L1 + script 28).
- **Термічна робастність** frontier-орбіталі FAD (MD→DFT ensemble, script 27).

**Чесний методологічний внесок (це новизна, не діра):** каскадна термодинаміка FADH₂→Os сира uphill у всіх методах → **implicit-solvation (PCM) межу декомпозовано ② (script 34) у chloro-anchored bracket** (реальний медіатор = chloro `[Os(dmbpy)₂(PVI)Cl]`, Zafar): differential PCM solvation [chloro +1/+2 +0.21 eV ↔ bis-Im +2/+3 +0.55 eV, PVI-realistic] + 4,4'-dimethyl substituent ① +0.142 eV (Koopmans; +0.149 adiabatic); [Os(H₂O)₆] benchmark +0.98 eV — computed; chloro↔+2/+3 **bracket functional-robust** (ωB97X cross-check 34b/B4), хоча internal aqua↔bis-Im order functional-sensitive (≤0.15 eV). Стара теза «exp = аква» **відкликана** (Zafar-полімер явно chloro). Анодний λ — first-principles (29b: FADH⁻/FADH• couple → λ_i 0.39 eV, rescued the radical-cation-pathological script 29); PCET-каскад (script 33) не flip downhill → теж PCM-межа, не proton-coupling. explicit-water QM/MM (Мінаєв) закриває залишок. Визнаний жанр (пор. JCTC implicit-solvent redox-benchmarks).

**Scope:** L1 (відстань/шлях) + L3 (анод) + L3b (катод DET) + сольватаційна методологія. L2 (MD-стабільність) → окрема EBFC-стаття (майбутня); L4 (delta_t/EIS) → окрема EBFC-стаття (майбутня) + predictions для Ti-coin експерименту.

**SSOT/IP:** числа — дім `docs/protocols/ebfc/in_silico/SUMMARY.md` (стаття реферить, не дублює); сабміт **вільний** — publish-to-protect (§2): публікація = захист (prior art), без патентного гейту.

---

### Стаття 2: Довгострокова Біотрибокорозійна Стійкість (Пріоритет: Друга)

**Назва (EN):** _"Long-Term Bio-Tribocorrosion Resistance of TPMS Gyroid Ti-6Al-4V Implants in Simulated Xylem Sap: Accelerated Aging Protocol for Forest Bioelectronics"_

**Журнали-цілі:** *Corrosion Science* (Q1), *npj Materials Degradation* (Q1), *Acta Biomaterialia* (Q1)

**Авторський колектив:**
- Школа Гусака (ЧНУ) — Prony/Maxwell-Wiechert creep-fit PEEK по виміряних даних + калібрація Kirkendall-моделі (наш in-silico script 51) проти coin-ICP-MS
- Біо-хаб ЧНУ (Спрягайло) — склад ксилемного соку Pinus sylvestris
- Архітектор (Silken Net) — практичний контекст та вимоги 20-річної довговічності

**Ключові результати:**
- Математична модель деградації анкера на горизонті 20 років
- Протокол акселерованого тесту (12 тижнів @ 40°C ≈ 3–5 польових років)
- Верифікація self-healing покриття на основі мікрокапсул з 8-HQ інгібітором

---

## 📊 1B. Публікації ЧДТУ (Data Science)

> **Контекст:** ЧДТУ забезпечує академічну експертизу за трьома напрямами: Data Science (доц. Карапетян А.Р., кафедра статистики), радіофізика та EMC-верифікація (перший проректор Гончаров А.В., каф. РТРС — радіотехніки/телекомунікаційних/робототехнічних систем), акустична мехатроніка та приладобудування (проф. Базіло К.В., проф. Бондаренко М.О., кафедра ПМКТ). Повний реєстр задач — у [`08_02 §2`](08_02_Academic_Institutions_Registry).

### Стаття 13: Виявлення Аномалій у Масштабних Потоках Лісової Телеметрії

**Назва (EN):** _"Anomaly Detection in Large-Scale Forest Telemetry Streams"_
**Журнали:** IEEE Internet of Things Journal (Q1) · Information Sciences (Q1)

| Автор | Внесок |
|-------|--------|
| **Карапетян А.Р.** (ЧДТУ) | Статистична методологія anomaly/fraud-детекції телеметрії: контекстуальна (сезон/біом) + CUSUM/EWMA для replay/spoofing — research-шар поверх поточного порога `FRAUD_DEVIATION_THRESHOLD` + DCI (data-gated: флоту ще нема, System TRL 3) |
| Архітектор (Silken Net) | insight_generator_service.rb (fraud detection), alert_dispatch_service.rb, Dual Computation Integrity |

---

## 🤝 1C. Міжуніверситетські Публікації (ЧНУ ФОТІУС × ЧДТУ)

> **Принцип:** Де ЧНУ ФОТІУС створює алгоритм або модель — ЧДТУ статистично валідує та розширює. Де ЧНУ ФОТІУС виконує аналітичний розрахунок (RF, фільтри) — ЧДТУ (ФЕТР, ПМКТ) верифікує лабораторно. Зони перетину описані у цій секції.

### Стаття 23: Прихована SMD-Антена LoRa у Лісовому Середовищі — Розрахунок та Експериментальна Верифікація

**Назва (EN):** _"Concealed LoRa SMD Antenna Under PEEK Radome for EBFC-Powered Forest IoT: Impedance Matching, 3D Radiation Pattern, and VNA/EMC Verification"_

> ℹ️ **Поглинула Статтю 8** (2026-07-17, UNI.19): обидві йшли в *IEEE TAP* (Q1) журналом №1 про ту саму антену — Ст.8 несла аналітичну половину, Ст.23 експериментальну, і Link Budget Косенюка стояв двічі. Зняте при злитті: «Reed-Solomon FEC» (E.15 ⚫ — CR 4/5 Hamming-FEC уже в кремнії SX126x) і «Kalman» (E.10 🔗 «не пре-білдити»; продукт узяв EMA — FW.21).
**Журнали:** IEEE Transactions on Antennas and Propagation (Q1) · IEEE Antennas and Wireless Propagation Letters (Q1) · Sensors (Q1)

| Автор | Внесок |
|-------|--------|
| **Косенюк Г.В.** (ЧНУ ФОТІУС) | Аналітичний розрахунок імпедансу, FEKO/CST моделювання діаграми спрямованості, LC-узгодження; Link Budget LoRa у лісі (SF=7–9, [`02_01 §5.3`](02_01_Hardware_Architecture_and_BOM)); 3D-діаграма з Ti-анкером (Zone 1 + Zone 3 фланець) як Ground Plane; CE/FCC compliance roadmap |
| **Гончаров А.В.** (ЧДТУ, перший проректор, каф. РТРС) | VNA-виміри S11 реальної зборки, натурні вимірювання path loss у лісі, EMC pre-compliance тестування |
| **Ярмілко А.В.** (ЧНУ ФОТІУС) | Engaged-партнер (lightweight crypto / embedded; вхід у ректорат). Airtime↔CCM tradeoff = spot-check нашого self-own розрахунку (CCM = FW.2, airtime = наша LoRa-формула), не незалежна валідація; far-horizon PQC-консультації |
| Каф. РТРС (радіотехніка) | Лабораторна інфраструктура: VNA, EMC-камера, вимірювальні стенди |
| Архітектор (Silken Net) | STM32WLE5JC RF-конфігурація, PEEK-радом IoT-капсули (∅25 мм frozen, IP68 — **окрема деталь, не PEEK-втулка Zone 2** анкера; anti-overgrowth shield + 3D RF Keep-Out ≥8 мм Z-clearance проти Ti-фланця), Ti-6Al-4V Ground Plane, firmware radio driver, EBFC Gen 2.0 як джерело живлення (>500 мВ, <500 мкВт — [`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)) |

**Тип зв'язку:** Послідовний — ЧНУ (Косенюк) розраховує аналітично → ЧДТУ (РТРС, Гончаров) верифікує на VNA/у лісі → коригування LC-ланцюга → серійна специфікація. ЧНУ (Ярмілко) паралельно тримає крипто-навантаження того ж кадру (CCM-MIC ↔ airtime).

**Магістерська робота (Науковий керівник — Гончаров, ЧДТУ РТРС):**
_«Експериментальне дослідження радіохарактеристик мікропотужних IoT-пристроїв LoRa 868 МГц у лісовому середовищі з прихованою антенною системою»_

**Магістерська робота (Науковий керівник — Косенюк, ЧНУ ФОТІУС):**
_«Радіотехнічна оптимізація мікропотужних IoT-пристроїв у лісовому середовищі: узгодження антенних систем»_
_(Запропонована тема; студент визначається після підписання R&D партнерської угоди ЧНУ–Silken Net)_

---

### Стаття 24: Фононна Лінза на Основі TPMS-Гіроїда для Акустичного Bio-IoT Сенсингу

**Назва (EN):** _"Phononic Lens Effect in Ti-6Al-4V TPMS Gyroid Structures for Passive Acoustic Filtering in Forest Bio-IoT: Experimental Characterization and TinyML Dataset Generation"_
**Журнали:** Journal of Sound and Vibration (Q1) · Ultrasonics (Q1) · Applied Acoustics (Q1)

> ⚠️ **Reframe (UNI.11, 2026-07-03):** кавітаційні емісії = 25–150 кГц (ultrasonic); поточний audible-тракт (16 кГц ADC / Nyquist-8 кГц) їх НЕ оцифровує → ця стаття = **UNI.11-канал / v3 AI-chip** (майбутній ultrasonic-тракт), не поточний firmware. TinyML-клас «cavitation» reframed до low-freq structural water-stress proxy ([`03_03 §4.2`](03_03_TinyML_Acoustic_Inference)).

| Автор | Внесок |
|-------|--------|
| **Базіло К.В.** (ЧДТУ ПМКТ) | П'єзоелектрична характеризація, імпедансна спектроскопія, акустоелектроніка |
| **Бондаренко М.О.** (ЧДТУ ПМКТ) | Акустичний стенд, мікродеформації, прецизійні вимірювання АЧХ |
| Архітектор (Silken Net) | Дизайн гіроїда (TPMS, ~65–67% пористість — CEM first-pass, не зафіксована константа, [`01_01 §5.2`](01_01_Coaxial_Gyroid_Topology_and_PEEK); Ti-6Al-4V), концепт Compute-by-Geometry, TinyML pipeline |

**Тип зв'язку:** Послідовний — ЧДТУ (ПМКТ) валідує фізику фононної лінзи (firmware ADC-DMA для п'єзо-тракту — self-owned, [`03_01`](03_01_Firmware_Lifecycle_and_DMA))

**Магістерська робота (Науковий керівник — Базіло або Бондаренко, ЧДТУ ПМКТ):**
_«Дослідження акустичних властивостей пористих TPMS-структур зі сплаву Ti-6Al-4V для пасивної фільтрації ультразвукових емісій біологічних об'єктів»_

---

### 🌿 Стаття 24a (Mongabay Pivot): Acoustic Biodiversity Verification of Satellite Land-Cover

**Назва (EN):** _"Multi-Scale Acoustic Verification of Satellite Land-Cover Through TinyML Edge AI: Distinguishing Functional Forest Ecosystems from Plantation Monocultures via Continuous Bio-IoT Soundscape Classification"_
**Назва (UA):** _«Мультимасштабна акустична верифікація супутникового лісового покриву через TinyML Edge AI: розрізнення функціональних екосистем та монокультурних плантацій за допомогою безперервної Bio-IoT класифікації звукового ландшафту»_
**Журнали:** *Ecological Indicators* (Q1, IF ~6.3) · *Remote Sensing of Environment* (Q1, IF ~13.5) · *Methods in Ecology and Evolution* (Q1, IF ~8.0) · *Bioacoustics* (Q2)

> ⚠️ **Рамка (both/and — не заміна карбону):** «Pivot» у назві = історичний ярлик кампанії Mongabay, а НЕ зміна позиціювання від карбону. Biodiversity — **другий D-MRV вимір ПОВЕРХ карбонового ядра**, не замість нього: `growth_points → SCC` лишається ядром економіки; fauna = 5-й акустичний клас (поверх 4: silence/wind/cavitation/chainsaw) + `biodiversity_score` (proposed) як метадані `ForestNFT` (proposed) — окремий шар доказу, не інший токен.

**Контекст / мотивація:** Дослідження Delgado et al. (Nicoya Peninsula, Costa Rica, 119 ділянок, 16 000 годин аудіо; огляд: *Mongabay News*, травень 2026) інструментально довело фундаментальне обмеження виключно супутникового MRV: NDVI не розрізняє функціональну екосистему (захищений ліс / PES-регенерація з dawn-dusk піками фауни) від монокультурної плантації або деградованого пасовища (нерухомий, шар-без-шарів звуковий фон). Стаття 24a переносить методологію Delgado у **безперервну on-tree IoT-площину** — замість 119 портативних рекордерів на 1 рік дослідження, Silken Net надає тисячі STM32WLE5JC сенсорів з `fauna_activity_index` 24/7, цифрово підписаним та anchored на блокчейн (Polygon SCC).

**Унікальність публікації (відсутня в світовій літературі станом на 2026-05):**
1. Перша інтеграція **soundscape ecology** (Pijanowski et al. 2011, ACI Index Pieretti et al. 2011) з **embedded TinyML на суб-кілобайтному бюджеті**: self-contained INT8 forward-pass (40 log-mel → 16 → 5 класів), **972 B ваг у Flash** (`const`/.rodata) / **~76 B стеку** (активації forward-pass) / ~0 .bss, без TFLM- і без CMSIS-NN-рантайму ([`03_03 §4.1`](03_03_TinyML_Acoustic_Inference)) — тоді як типова ESC-CNN потребує ~16 КБ tensor arena, що при цьому енерго/RAM-бюджеті **фізично не деплоїться** ([`03_03 §3.4`](03_03_TinyML_Acoustic_Inference)).
2. Перший **D-MRV pipeline**, що зв'язує акустичний біо-сигнал із on-chain записом: `TinyML soundscape → CoAP → Rails → Polygon SCC`. **Both/and:** це **другий D-MRV вимір** (biodiversity) ПОВЕРХ карбонового ядра — `growth_points → SCC` лишається емісійним драйвером, а `fauna` живитиме `biodiversity_score` (proposed метадані `ForestNFT`, ще не в коді), НЕ заміна карбону. ⚠️ **Не «продакшн» і не «cryptographically доводить» (виправлено 2026-07-17 за ARCH.53):** живий шлях мінтить **оптимістично** — IoTeX/Chainlink НЕ enforced; ланка `W3bstream ZK-proof → Chainlink Oracle → mint guard` = PATH 1 ⚪ **Demoted/unwired** (нема DON source/consumer/relayer), trust-origin = **L0**, anti-fraud = ex-post clawback (ще не збудований) → [`05_02`](05_02_Proof_of_Growth_Pipeline). Це архітектура-**намір** (North-Star §0.1), не доведений факт: «доводить» тут = той самий reviewer-landmine, за який Статтю 1 переписали з «*Validation*» (2026-06-05).
3. Перша **Macro-Micro residual analysis**: де NDVI=high & fauna=low → кандидат на «green-washing», де NDVI=low & fauna=high → ранньо-стадія регенерації, що supercluster карбон/біо інтегруються.

| Автор | Афіліація | Внесок |
|-------|-----------|--------|
| **Любченко К.М.** (ЧНУ ФОТІУС) | Genetic Algorithms, Edge AI, Master of Logic | Опційний GA-tuning ваг (generic pymoo NSGA-II на нашій self-owned моделі — self-generable апгрейд, **НЕ** load-bearing валідація; [`00_07` FW.4](00_07_Action_Plan_Tracker) «опц., не блокер»). Реальні двері = 2 магістерські-теми (студентська GA-робота) |
| **Базіло К.В.** (ЧДТУ ПМКТ) | П'єзоелектрика, EIS-характеризація | Резонансні характеристики п'єзосенсора у діапазоні фауни 0.5–12 кГц; калібрування АЧХ під soundscape |
| **Бондаренко М.О.** (ЧДТУ ПМКТ) | Acoustic Emission, мікродеформації | AE-методологія для розрізнення layered soundscape від механічного шуму; "Cherkasy Soundscape Library" — методологія записів |
| **Карапетян А.Р.** (ЧДТУ) | Math statistics, R, Data Science | ANOVA dawn/dusk peak amplitude між ландшафтами (над польовими даними); Permutation tests для biodiversity_trend |
| **Спрягайло О.В.** (ЧНУ біо-хаб) | Ботаніка, фітоценологія, екологія | Польові експедиції Черкаського бору, ground-truth labeling таксономічних груп, 10-річні дані стресових подій як external validation |
| **Гаврилюк М.В.** (ЧНУ біо-хаб) | Зоологія, remote sensing, GIS | Cross-validation soundscape ↔ зоологічні обліки птахів та амфібій; GIS-інтеграція ділянок |
| Архітектор (Silken Net) | TinyML, firmware, Web3 | Едж AI архітектура — **Path B (log-mel) обрано + DSP front-end реалізовано self-owned** (`Compute_LogMel`, librosa≡stdlib≡C golden-vector parity; повний MFCC з DCT **не рекомендовано** для CNN-ESC — [`03_03 §3.2`](03_03_TinyML_Acoustic_Inference)); 5-class INT8 baseline натреновано **self-owned end-to-end** (ESC-50; per-frame FC 40→16→5 — **не** CNN, [`00_07` FW.4](00_07_Action_Plan_Tracker)) на контракті ознак [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference); AiInsight#biodiversity_trend integration; ForestNFT metadata (proposed) |

**Тип зв'язку:** Багатошарова паралель з фінальним синтезом — ЧНУ біо-хаб (ground truth) + ЧДТУ ПМКТ (hardware acoustic) працюють паралельно з ЧНУ ФОТІУС (GA — Любченко) + ЧДТУ Карапетян (статистика + fusion-верифікація); архітектор інтегрує firmware і backend; усі шари сходяться на одному датасеті ("Cherkasy Soundscape Library") та одній публікації.

**Cross-references:**
- [`03_03 §10`](03_03_TinyML_Acoustic_Inference) Mongabay Pivot — повна архітектура 5-class TinyML
- [`08_02 §1A`](08_02_Academic_Institutions_Registry) — біо-хаб: польова методологія «Cherkasy Soundscape Library»
- [`08_02 §1B`](08_02_Academic_Institutions_Registry) — наш NDVI-адаптер (open-data Sentinel-2) + fauna feature
- [`08_02 §1B` NSGA-II GA](08_02_Academic_Institutions_Registry) — Любченко 5-class оптимізація
- [`08_02 §2`](08_02_Academic_Institutions_Registry) — ПМКТ калібрувальний датасет
- [`00_07` — UNI.11](00_07_Action_Plan_Tracker) — операційний tracker

**Магістерські та PhD роботи:**
- (магістерська ЧНУ біо) _«Динаміка денних та сутіночних піків акустичної активності фауни Черкаського бору як індикатор екологічного здоров'я»_ (Спрягайло)
- (магістерська ЧНУ ФОТІУС) _«Багатоцільова генетична оптимізація 5-класової TinyML моделі акустичного моніторингу лісу»_ (Любченко)
- (бакалаврська ЧДТУ ПМКТ) _«Створення калібрувального soundscape-датасету для embedded biodiversity monitoring»_ (Базіло/Бондаренко)
- (PhD ЧДТУ Data Science) _«Статистичні методи валідації мультимасштабної верифікації лісового покриву»_ (Карапетян)

---

## 🧬 1E. Публікації ЧМА (Біохімія EBFC, Токсикологія)

> **Контекст:** ЧМА (Черкаська медична академія) забезпечує токсикологічну оцінку вивільнення іонів V/Al з Ti-6Al-4V (Суховий) та фітотоксикологію self-healing покриттів (Глущенко); фарм-технологію стабілізації ферментів у матрицях (Бушуєва — дотично); глибока EBFC-ензимологія → профільний біохімік (TBD). ЧМА = навчальний коледж (не матеріалознавча лабораторія); інституційний доступ — персонально. Повний реєстр задач — у [`08_02` — Academic Institutions Registry](08_02_Academic_Institutions_Registry).

### Стаття 28: Біохімічна Валідація Enzymatic Bio-Fuel Cell для Дерево-Живленого IoT

**Назва (EN):** _"Biochemical Validation of Enzymatic Bio-Fuel Cell for Tree-Powered IoT: Enzyme Immobilization Stability, Protective Matrix Optimization, and In Vitro Performance in Simulated Xylem Sap"_
**Журнали:** Biosensors and Bioelectronics (Q1) · Journal of Power Sources (Q1) · Electrochimica Acta (Q1)

| Автор | Внесок |
|-------|--------|
| **Бушуєва І.В.** (ЗДМФУ, стейкхолдер ЧМА) | Фарм-технологія стабілізації активних речовин у гель-матрицях + регуляторна валідація (дотично до Genipin-Chitosan-CNC immobilization); глибока EBFC-ензимологія (in vitro лакказа/Nafion, 30-day) → профільний біохімік/електрохімік (TBD) |
| **Мінаєв Б.Ф.** (ЧНУ) | Spin-forbidden кінетика активації O₂ на laccase ORR-катоді (SOC — світовий фах школи), механізм поза власним L3 |
| **Глущенко О.** (ЧМА) | Характеризація Os redox polymer стабільності + експериментальна cross-linking характеризація обраного медіатора |
| Архітектор (Silken Net) | EBFC архітектура (01_03), interfacial oxide-DET DFT (script-53), BQ25570 Cold Start вимоги, firmware delta_t специфіка |

**Тип зв'язку:** Комплементарний — ЧНУ: теоретична модель (DFT), ЧМА: in vitro валідація, Silken Net: системні вимоги

> **In-silico baseline для Статті 28:** Zero-Lab L1-L4 PASSED (2026-05-25). Публікаційні headline-claims: L1 **d_FAD=15.998 Å** (MET viable); L3 cascade **verified +574 мВ / −0.574 eV downhill** (E°s, Os +309 / FAD −265; raw DFT uphill = method limit decomposed by ②); L3b cathode DET **borderline** at realistic λ (geom-fixed; не old ×10⁵); L4 recharge-model (delta_t → GP, E.63 calibration-pending). Headline-claims вище — для контексту; **повні/поточні числа не дублюємо** — канонічний [`SUMMARY.md`](protocols/ebfc/in_silico/SUMMARY.md) + [`PIPELINE_STATUS.md`](protocols/ebfc/in_silico/PIPELINE_STATUS.md) (проти розсинхрону).

---

### Стаття 29: Токсикологічна Оцінка Ti-6Al-4V Гіроїдних Анкерів для Лісових Кіберфізичних Систем

**Назва (EN):** _"Phytotoxicological Assessment of Ti-6Al-4V TPMS Gyroid Anchors for Forest Cyber-Physical Systems: Vanadium and Aluminum Ion Release, Bioaccumulation, and 20-Year Safety Modeling"_
**Журнали:** Environmental Pollution (Q1) · Science of The Total Environment (Q1) · Chemosphere (Q1)

| Автор | Внесок |
|-------|--------|
| **Суховий Г.П.** (ЧМА) | Фітотоксичність V/Al для Pinus sylvestris, Safety Margin, хронічна біоакумуляція |
| **Гусак А.М.** (ЧНУ) | ICP-MS вимірювання V/Al release + калібрація Kirkendall-моделі (наш script 51) проти виміряного (20-рік екстраполяція) |
| **Глущенко О.** (ЧМА) | Оцінка фітотоксичності 8-HQ self-healing покриття, альтернативні інгібітори |
| **Спрягайло О.В.** (ЧНУ) | Склад ксилемного соку Pinus sylvestris, фітоценологічний контекст Черкаського бору |
| Архітектор (Silken Net) | Ti-6Al-4V специфікація (01_02), self-healing концепт, 20-річна цільова довговічність |

**Тип зв'язку:** Послідовний — ЧНУ (Гусак) вимірює концентрації + модель → ЧМА (Суховий) оцінює біологічний вплив + Safety Margin

> ⚠️ **V-free напрям (2026-06-21):** founder обрав сплав **Ti-6Al-7Nb** (V-free, [`01_02 §2.5`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)) → наратив статті зсувається з «чи безпечний V-release» на **design-rationale V-free + comparative 4V↔7Nb release** (дані дає Stage-2 coin ICP-MS, HW.24/HW.3). Назву/scope не переписуємо до coin-валідації (baseline ще 4V — no-premature-canon).

---

## ⚖️ 2. Розподіл Інтелектуальної Власності (IP Framework)

> **Рішення (2026-06-07): SilkenNet — місія, не виключність → патент НЕ подаємо.** Замість
> патенту-на-монополію — **defensive-publication-first**: публікуємо інвентивне ядро як prior art, щоб
> воно лишалось **вільним для всіх лісів** і його **не можна було захопити**. Технологія відкрита для
> ВСІХ (партнерів теж) під ліцензіями нижче; SilkenNet утримує лише **бренд (™), governance/treasury
> токеноміки та операційні секрети (ключі/дані)**.

### Ліцензійна матриця (значення — дзеркало кореневих LICENSE-файлів; правити там)

| Зона | Ліцензія | Дім |
|---|---|---|
| Код (backend / firmware / contracts / tooling) | **GNU AGPL-3.0-or-later** | `/LICENSE` |
| Залізо (gyroid / EBFC / PCB-дизайн) | **CERN-OHL-S-2.0** | `/LICENSE-HARDWARE.txt` |
| Документація (`docs/**`) | **CC-BY-SA-4.0** | `/LICENSE-DOCS.txt` |
| Мапа зон + third-party винятки (AF3 non-commercial!) + pledge | — | `/NOTICE` |

### Чотири стовпи постави

1. **Defensive publication** — інвентивне ядро (Synergy A: EBFC = одночасно живлення + zero-noise
   `delta_t`-сенсор; Synergy B: gyroid triple-function) опубліковане як prior art →
   [`defensive_disclosure.md`](protocols/anchor/defensive_disclosure.md) (TDCommons + публічний repo +
   Стаття 1). Ландшафт новизни/анти-захоплення — [`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md).
2. **Open license** — копілефт (AGPL / CERN-OHL-S) тримає деривативи відкритими + має patent-retaliation;
   share-alike (CC-BY-SA) для доків. **Copyright утримуємо** — але мета = **enforcement копілефту**, не
   пропрієтарність (Lorenz / `bio_contract.rb` / `attractor.rb` — об'єкт авт. права, ліцензований відкрито).
3. **Trademark** — SilkenNet™ / GaiaNexus™ / SCC™ зарезервовані (захист довіри/бренду — справжній рів
   MRV-мережі); відкритими ліцензіями НЕ покриваються. Заявка через прямого повіреного УкрНОІВІ (§2.1).
4. **Trade secret** — ТІЛЬКИ для нерозкритого: **криптоключі (ніколи не публікуються), польові
   production-дані, ваги ML-моделі**. Під AGPL код відкритий → формат пакета / crypto-інтеграція **вже
   open**, не secret.

### Patent non-assertion pledge

SilkenNet не подає й не assert-итиме патентів на цю технологію. Якщо колись отримаємо патент захисно
(щоб запобігти захопленню) — pledge безвідкличного non-assertion проти всіх добросовісних користувачів (`/NOTICE`).

### Publish-to-protect (інверсія колишнього embargo)

> 🟢 **Публікація = захист.** Раніше тут стояло patent-embargo («тримати сабміт до пріоритетної дати»).
> Під defensive-publication логіка **інвертується**: публікувати **свідомо й рано** — публічний repo +
> наукова стаття **фіксують prior art** і тим блокують захоплення. **Стаття 1 — submission-ready** (без
> патентного гейту). MoU з ВНЗ містять open-license + co-authorship, а не embargo/NDA на саму технологію.

### Що відкрито vs що утримуємо

- **Відкрито для всіх (вкл. ЧНУ/ЧДТУ/СЄУ та будь-кого):** увесь код / залізо / доки під ліцензіями вище
  — використання, вивчення, модифікація, поширення за копілефт/share-alike умовами. Партнери НЕ
  потребують окремого «гранту прав» — open license уже це дає. Co-authorship публікацій — предмет §1, не
  tech-IP.
- **SilkenNet утримує (НЕ покривається open-ліцензіями):** торгові марки SilkenNet™/GaiaNexus™/SCC™;
  governance/treasury токеноміки (SCC/SFC, DAO — [`05_03`](05_03_Tokenomics_SCC_and_SFC) / [`05_06`](05_06_Governance_and_DAO));
  production API-доступ і **blockchain / Oracle / Slasher / Admin приватні ключі**; raw production-телеметрію.
- **Колишні «патент/trade-secret» об'єкти** (gyroid-дизайн, Lorenz, 12-chain pipeline, TinyML-модель,
  формат 21-байт пакета) тепер **відкриті** під відповідними ліцензіями; «формат пакета = trade secret»
  **знято** (він у відкритому firmware). Реальні секрети — лише ключі / production-дані / ваги (стовп 4).

### Партнери та внески

Під open-поставою партнерські «права/обмеження» спрощуються: **усе технічне відкрите всім** (вище), тож
окремих per-партнер грантів прав не треба. Partner-внески йдуть у repo під тими ж ліцензіями зі спільним
авторством: R-аналітика (Карапетян), RF-дані (Гончаров / РТРС), акустичні калібрування (Базіло /
Бондаренко / ПМКТ), юр-шаблони NaaS (Аблязов Д.), крипто-облік SCC (Гедз).
Co-authorship публікацій — §1 (**без embargo**). SilkenNet утримує лише невідкрите (™ /
governance-treasury / ключі / raw-дані — вище).

### Бренд-архітектура (модель найменування)

> **Рішення (2026-06-16, [`00_07` — BIZ.16](00_07_Action_Plan_Tracker)):** імена проєкту розведені
> **за висотою** — продукт vs планетарна федерація. Колишній двозначний проєктний codename (що осідлав
> обидві висоти) розчинено в цю модель; версійний хвіст прибрано.

| Ім'я | Роль | Канонічна форма |
|---|---|---|
| **SilkenNet** / Silken Net | Лісовий net — продукт/мережа (орган №1, існує сьогодні). Код-неймспейс `SilkenNet::`; ™. | `SilkenNet` (code/™) · `Silken Net` (display) |
| **GaiaNexus** | Планетарна федерація / ноосферний апекс — нексус усіх майбутніх net-ів (far-horizon, [`00_08 §3`](00_08_Beyond_TRL9_Planetary_Roadmap)); ™. | `GaiaNexus` (закрита, окрема від «X Net») |
| **SCC** / **SFC** | Токени екосистеми (Silken Carbon / Forest Coin); ™ SCC. | — |
| **Gen 2.0** | Покоління біохімії EBFC ([`01_03`](01_03_EBFC_Enzymatic_Bio_Fuel_Cell)) — **окрема технічна вісь**, не назва проєкту. | — |

**Конвенція найменування net-ів** (на випадок розгортання федерації — далекий горизонт, не зараз):
`<Корінь> Net` (display) / `<Корінь>Net` (code/™), дзеркалить `Silken Net`/`SilkenNet`; корінь —
греко-латинський домен-морфем за **геофізичною сферою** (biosphere → Silken · cryosphere → Cryo ·
hydrosphere → Abyssal · lithosphere → Litho · pedosphere → Myco), а **noosphere → GaiaNexus** як
інтегратор. `Silken Net` — grandfathered первісток (поетичний корінь = легітимний виняток). Вузлова
абстракція — `PlanetaryNode` (Збір енергії → Сенсорика → Оцифрування хаосу → Токенізація). Сиблінг-нети
та їхні токени — кандидати рівня `SRL:Concept`, **свідомо НЕ канонізовані** як baseline
([`00_08 §3`](00_08_Beyond_TRL9_Planetary_Roadmap)).

---

## 🏛️ 2.1. IP-інструменти (TISC-консультація + trademark + UA-юр-review)

> **Контекст:** Під defensive-publication (§2) prior-art landscape уже готовий ([`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)); лишаються **TISC-консультація**, **trademark** і **точковий UA-юр-review**.

### 2.1.1. TISC — консультація (prior-art / IP / open-license)

**Що це:** Центр Підтримки Технологій та Інновацій — публічна мережа **WIPO** (координує УкрНОІВІ); academic-rate консультація.

| Сервіс TISC (консультативний) | Кейс SilkenNet |
|---|---|
| Prior-art landscape (Espacenet / PATENTSCOPE / Google Patents) | верифікація новизни Статті 1 + анти-захоплення (база вже є → [`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)) |
| Консультація з **торгових марок** | напрям заявки SilkenNet™ / GaiaNexus™ / SCC™ (подача — повірений, ↓) |
| Консультація з **open-license** сумісності у UA-юрисдикції | AGPL / CERN-OHL-S / CC-BY-SA legal sanity |

**Подача ™** — прямий **повірений УкрНОІВІ** (~5-10k UAH; TISC консультативний, сам не подає).

### 2.1.2. UA-юр-review → Аблязов + крипто/IP-юрист TBD

**Точковий UA-юр-review:** RWA як `hadron_asset_id` vs Лісовий Кодекс/ПЗФ ([`00_07` BIZ.11](00_07_Action_Plan_Tracker)) · SCC utility-vs-security за ЗУ «Про віртуальні активи» + MiCA ([`05_03`](05_03_Tokenomics_SCC_and_SFC)) · NaaS у Civil Code + `parametric_insurance` ([`07_01`](07_01_Nature_as_a_Service_Contracts)) · AGPL-enforcement + open-license/AF3 valida (§2). Виконавець: **Аблязов Д.Е.** (СЄУ, персонально) + профільний крипто/IP-юрист TBD.

### 2.1.3. Операційна послідовність

| Етап | Дія | Власник |
|---|---|---|
| 1 | Prior-art landscape ✅ ([`prior_art_landscape.md`](protocols/anchor/prior_art_landscape.md)) | 🤖 done |
| 2 | Публікація disclosure (TDCommons) + LICENSE-файли → [`defensive_disclosure.md`](protocols/anchor/defensive_disclosure.md) | 👤 + 🤖 |
| 3 | Заявка на ™ (прямий повірений УкрНОІВІ) | 👤 повірений |
| 4 | UA-юр-review (Аблязов + крипто/IP-юрист TBD) | 👤 |
| 5 | Сабміт Статті 1 (вже unblocked — publish-to-protect) | 👤 |

