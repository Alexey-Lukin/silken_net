# Anchor — Fatigue (S-N) Test-House RFQ (printed Ti-6Al-4V specimens in synthetic xylem sap)

> **Що це:** RFQ-аркуш для **механічного тест-хаусу** — осьове втомне (S-N, Wöhler) випробування гладких зразків друкованого Ti у синтетичному ксилемному соку, з гігацикловими опціями, фрактографією й статистичним плануванням. Зміст — [`sn_fatigue_test_plan`](../anchor/sn_fatigue_test_plan.md) §10, переписаний як лист; **план лишається домом предмета, серій, рівнів і відкритих присудів**, тож репо-шар нижче — мапа «розділ листа → параграф плану → що прибрано», а не друга копія плану.
> Зразки сюди ПРИХОДЯТЬ від DMLS-вендора деталей (пропозиція плану §9 п.15), тож сусід цього листа — [`vendor_templates`](vendor_templates.md) §Processing п.16, а не coin-лист: купон Stage-2 робочої частини під осьове навантаження не має (план §1.2).
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-14, не надіслано**. Усі числа — дзеркало плану (а через нього канону й кешу), дім кожного названо поруч; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 (плече Δbake — HW.27).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Анкер — втома друкованого Ti (S-N) — тест» · hard-constraint дім §4.B).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — специфікація відкрита; CDA = стандартні комерц-умови.

---

## 0. Як користуватись + cover-note

1. **Окремий аркуш, а не рядок сусіднього листа:** адресат інший (механічний тест-хаус, не електрохімічна лабораторія й не друк-бюро), зразок інший (гладкий під осьове навантаження), і тест споживає зразки, які друкує й обробляє вендор деталей.
2. **Квоту й спроможність просити можна зараз, замовлення — ні.** Лист чинний за будь-якого з присудів плану §9: маршрут гігациклу, run-out, R, критерій відмови, статистику, кількість орієнтацій і серій він просить оцінити поштучно («quote per …»), а не фіксує. Питати раніше варто ще й тому, що відповідь про маршрути гігациклу — передумова самої послідовності (план §2.5 п.1).
3. **Сліпий аналіз — ДЕЛЕГОВАНИЙ присуд, розширений на цей лист 2026-09-14** (запис із підставою й ціною — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24; founder перевертає до відправки). Тест-хаус не отримує оцінки межі витривалості зі смугою, SF, in-silico вердиктів, гіпотези про місце зародження тріщини і маршруту кожної серії; отримує правило рівнів (якір — виміряний розтяг свідків) і прохання запропонувати сітку. **Для втоми в сліпоти є друга підстава, якої coin-лист не мав:** наша оцінка σ_e складена з множників, жоден із яких не виміряно (план §4.1), тож передати її означало б заякорити сітку рівнів на числі без провенансу. **Ціна вища, ніж у coin-листі:** staircase ставить рівні послідовно, і без смуги перші точки можуть лягти в run-out або в миттєве руйнування — мітигація в листі: розтяг свідків ДО сітки та пілот.
4. **Відповідь тест-хаусу в репо не комітиться** — ціни, внутрішні методики й номери сертифікатів є чужими операційними фактами. Сюди й у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 іде лише наш висновок.

---

## 1. Звідки кожен розділ листа — і що з нього свідомо прибрано

| Розділ листа (EN) | Дім | Як подано | Прибрано (§0 п.3) |
|---|---|---|---|
| **Scope · service exposure** | план §0 · §1.1 · §5.1; частота гойдання — [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | предмет — матеріал у стані процесу деталі, не деталь; «до порядку 10⁹ циклів» замість одного числа, бо бюджет до одного числа не звужується (HW.43) | що напруження деталі не пораховане ніде (план §1.3) — наша прогалина, не параметр методу |
| **Specimens we supply · series** | план §2 · §3 | серії описано тим, що тест-хаус мусить ОБРОБИТИ (середовище · обробка робочої частини · кількість орієнтацій), а не маршрутом; дві орієнтації й «three or four further conditions» (прочитання ΔHIP) — «confirmed before the order» | параметри маршруту (HIP · bake — ⚖️ HW.27) і що саме змінює кожна серія, яка різниться маршрутом (серії «в повітрі» й «з обробленою робочою частиною» свою мету називають самі) |
| **Test medium** | план §7 → рецепт [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); форма — [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) §2 | та сама таблиця й та сама несумісність Ca/оксалату, що в coin-листі; температура · O₂ · потенціал — опціями | число потенціалу: вікно стеку — висновок плану, не вимір |
| **Test methods A–F · run-out** | план §5.3 · §6.2 | шість маршрутів і три run-out — опції з ціною; міст частот мотивовано опублікованою залежністю частотного ефекту від місця зародження | Arrhenius-оцінка стиску (план §5.2 в) |
| **Stress levels** | план §4.2 | правило: якір — розтяг свідків, сітка на кожну серію; ціна на R = −1 + перелік підтримуваних R | σ_e зі смугою (план §4.1) · SF · дерейт скрипта `55` |
| **Stop criteria · fractography · statistics** | план §6 | критерій на кожній точці; «функція може бути втрачена до розділення» + ціна виявлення зародження; класи місця зародження без нашої гіпотези; медіана ⊥ нижня межа — ціна обох | ланцюг «тріщина шару → відкол із ферментами» (план §6.1) · гіпотеза «після HIP загрози поверхневі» (план §5.2 а) |
| **Programme phases** | план §2.5 | фази цінуються окремо, пілот першим | що послідовність — пропозиція плану |
| **Data · what we ask you to provide** | план §10 п.1–7 | пункти §10, розгорнуті в поля (+ питання про повернення зразків — як у coin-листі) | — |
| **Possible follow-on** | план §2.3 · §8 | другий сплав · шов дроту з друкованою деталлю · ґратка — «окремим запитом» | чому шов і ґратка окремо (HW.34 · план §8) |

⊕ **Лист додає до плану дві речі, і обидві записано в план** (§11): **(1)** позначення ISO 1099 і ISO 12107 звірено за каталогом iso.org 2026-09-14 — тож лист називає їх без року й просить видання, бо ISO 1099 саме переходить до наступного видання; **(2)** питання, як статистика трактує змішані механізми зародження в одній серії: абстракт **відкликаної** ISO 12107:2003 обмежував метод даними одного механізму руйнування, абстракт чинного видання 2012 цього речення не несе, а змісту жодного ми не читали — тож лист питає, а не цитує.

---

## 2. Відкрите, яке лист обходить питанням (присуд — не тут)

| Відкрите | Як лист лишається чинним | Дім присуду |
|---|---|---|
| маршрут гігациклу (план §5.3 A–F) · run-out | усі маршрути й три run-out — опції з ціною за кожен | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 (план §9 п.1) |
| R | ціна на R = −1 + які R підтримують машини й геометрія; «confirmed before the order» | HW.23 (п.2) |
| орієнтація: одна чи дві | «possibly in two» + ціна за орієнтацію | HW.23, нога орієнтації (п.3) |
| прочитання ΔHIP | «three or four further conditions» | HW.23 (п.4) |
| температура bake · комірка bake × середовище | маршруту лист не несе; комірка — опція «one further condition in laboratory air» | HW.27 · HW.23 (п.5–6) |
| сплав | Ti-6Al-4V зараз; другий — follow-on | HW.24 (п.7) |
| pH · глюкоза · температура · O₂ · потенціал | межі + «confirmed before the order»; O₂ і потенціал — опції | HW.3 · HW.24 · HW.23 (п.8) |
| критерій відмови | критерій на кожній точці + ціна виявлення зародження | HW.23 (п.9) |
| статистика й `n` | ціна за медіанну криву і за нижню межу | HW.23 (п.10) |
| тонкостінна серія | питання про найменший надійний переріз | HW.23 (п.13) |
| **пропозиції плану, яких канон не несе** (п.15) | лист бере їх робочим прочитанням і **стоїть на двох:** хто виготовляє зразки («we plan … the manufacturer of our part») і якір рівнів (розтяг свідків). Решту — шорсткість кожної серії · фрактографію кожного зруйнованого · простежуваність · сік прискореного тесту — подано рядками ціни, які знімаються без переписування листа | HW.23 (п.15) |
| сліпий аналіз · і чи кодувати серії до звіту (сліпа фрактографія) | делеговано (§0 п.3); нейтральний опис серій лишає обидва шляхи — розкрити маршрут при замовленні ⊥ кодувати до звіту | HW.24 (п.12) |

---

## 3. Dispatch checklist (👤)

- [ ] 👤 **До відправки — лишити або перевернути делегований сліпий аналіз** (§0 п.3; запис і ціна — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24). Перевернутий, він змінює два розділи листа: «Scope of request» (речення про сліпоту) і «Stress levels».
- [ ] 👤 **Квота й спроможність — зараз:** відповідь про маршрути A–F — передумова послідовності (план §2.5 п.1). **Замовлення — після** присудів §2 і вибору DMLS-вендора.
- [ ] 👤 **Адресати.** Механічний тест-хаус із корозійною втомною коміркою та/або ультразвуковою VHCF-лабораторією — **TBD, не контактовано**.
- [ ] 👤 **Зразки йдуть DMLS-листом, і його пп. 2–4 (HIP · орієнтація · bake — «mandatory») на серії плану не поширюються.** Питання вже стоїть у pre-qual листі ([`vendor_templates`](vendor_templates.md) §Processing п.16) — перевірити, що воно поїхало тим самим листом; сам рядок замовлення зразків пишеться після ⚖️ «хто виготовляє зразки» (план §9 п.15).
- [ ] 👤 **CDA-шаблон** — комерц-умови ([`rfq_registry`](rfq_registry.md) §3).
- [ ] 👤 **Після відповіді:** висновок (не чужі ціни й внутрішні факти) → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23; маршрут, run-out і `n` — у присуди плану §9.

---

## 📤 Dispatch block (EN) — paste into test-house email

> Ready-to-send English text. Working body above stays Ukrainian. Anything our side
> must NOT disclose is deliberately absent — **немає:** оцінки межі витривалості зі смугою, SF і in-silico вердиктів
> (план §4.1 — сліпий аналіз, §0 п.3) · гіпотези про місце зародження тріщини й ланцюга «тріщина шару → відкол» ·
> маршруту, параметрів і призначення кожної серії · Arrhenius-оцінки стиску · відкритих присудів ЯК суперечок (лист каже
> «confirmed before the order») · імен вендора деталей, кандидатів і академ-каналу · трекер-ID/канон-рефів · статус-маркерів.
> Адресат — **механічний тест-хаус**; друк і обробка зразків ідуть DMLS-листом (`vendor_templates.md` §Processing п.16).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

RFQ — axial fatigue (S-N) testing of laser powder-bed-fused titanium specimens in synthetic xylem sap, with very-high-cycle options, fractography and statistical planning (R&D programme)

### Scope of request

We are an R&D group developing a titanium anchor that is implanted into living trees and has to stay there for about twenty years, flexed by the wind-driven sway of the trunk at roughly 1–5 Hz — up to the order of 10⁹ load cycles over its life. Before relying on the printed metal in that service we want its fatigue curve — the relation between stress amplitude and cycles to failure, with its scatter — measured on smooth specimens that carry the material condition of the part: the same printing route, the same heat treatment and the same surface treatment, tested in a medium that reproduces tree sap rather than a generic buffer.

What we buy from you is the test: planning, machine time, fractography and traceable raw data. The specimens reach you from our part manufacturer.

This is a request for a quotation and a capability statement, not yet an order. Several choices are still being fixed on our side and are marked **"confirmed before the order"** below — please price those per unit or per option, so that we can size the final work order from your quote. Your answer on the very-high-cycle routes also decides the sequence of our programme, which is why we ask now.

We deliberately send no estimate of the fatigue strength and no model predictions: we want both the level setting and the fractography to be blind to an expected outcome. Stress levels are to be anchored on tensile properties measured on witnesses from the same builds (see *Stress levels*).

### Specimens we supply

- **Alloy:** Ti-6Al-4V (Grade 5), laser powder-bed fusion. A second alloy — titanium-based or tantalum, not yet selected — may follow (see *Possible follow-on*).
- **Production route:** we plan to have the specimens printed and post-processed by the manufacturer of our part, along the part's own process route including its heat treatment and surface treatment, so that the curve describes that route and not a generic one. Each specimen arrives marked with an ID; build, plate position, build orientation and powder lot are recorded against it.
- **Type:** smooth specimens for axial loading, with no deliberate stress concentration. For a conventional machine the **gauge section is printed to size and not machined** in most series — the lattice walls of the part cannot be machined, so its surface is as printed and then chemically treated; grip ends may be machined. For an ultrasonic machine a resonant geometry is needed — please propose it.
- **Please propose the specimen geometry** for each machine you would use, and tell us:
  - how you calculate stress on a rough as-printed gauge — on the nominal section or on a measured minimum section — and how you measure that section;
  - the smallest gauge section you can test reliably: the lattice struts of the part are under 1 mm thick, and a thin-section series is an option we are considering;
  - whether a conventional and an ultrasonic test can run on **one** specimen geometry (see *D. Frequency bridge*).
- **Series.** Each series is its own S-N curve. All are the same alloy; they differ in post-processing, in the finish of the gauge, in build orientation or in test environment:
  - the **production condition in the solution** — possibly in **two build orientations** (specimen axis parallel and perpendicular to the build direction), confirmed before the order; please quote per orientation;
  - **three or four further conditions in the solution** — all with an as-printed gauge except one with a machined gauge;
  - the **production condition in laboratory air**, at the same frequency as in the solution;
  - *options:* one further condition in laboratory air, and one further condition in the solution.
- **Same-build witnesses, per series:** tensile specimens (yield strength, ultimate tensile strength, elongation) — quote per specimen; and the surface roughness of the gauge per series, stated as a named parameter together with the instrument.
- **Quantities** follow from your statistical proposal (see *Statistics*), so please quote per specimen and per machine-hour rather than for a fixed lot.

### Test medium

**Synthetic xylem sap**, target species Scots pine (*Pinus sylvestris*). Working composition ranges:

| Component | Concentration range |
|---|---|
| Malic acid | 1–5 mM |
| Oxalic acid | 0.5–2 mM |
| KNO₃ | 2–5 mM |
| CaCl₂ | 0.5–2 mM |
| MgSO₄ | 0.2–1 mM |
| Phytosiderophores (optional — tell us if you can source them) | 0.01–0.1 mM |

- **Exact recipe** (point values): **confirmed before the order.** Calcium and oxalate cannot both sit inside the ranges above — at those levels the medium exceeds the solubility of calcium oxalate — so the confirmed recipe will set calcium, oxalate or both well below their ranges. A precipitate on the specimen would change both the medium and the surface under test. Quote medium preparation per batch.
- **pH:** set-point **within pH 4.5–5.5**, **confirmed before the order**. Tell us how you set, hold and log pH over runs lasting days to weeks.
- **No sugar** is in the recipe. Should the confirmed recipe add glucose, multi-week runs will support microbial growth — say how you would control it. Add **no preservative, biocide or inhibitor** to the medium without agreeing it with us: any additive changes the corrosion chemistry under test.
- **Temperature:** held constant, set-point **within 20–40 °C** and **confirmed before the order**. State your control band, and whether a controlled temperature above ambient is possible in your fatigue cell.
- **Dissolved oxygen:** in service the sap carries little oxygen, and a variable amount, so an air-saturated cell does not reproduce it. Tell us whether you can log dissolved oxygen, and quote controlling it (for example by gas purging) as an option.
- **Electrochemical potential:** in service the metal is part of a working electrochemical cell rather than corroding freely. Quote, as an option, holding the specimen at a set potential during cycling (a potentiostat in the fatigue cell) — the potential is confirmed before the order — and tell us how the specimen is electrically isolated from grips and fixtures in the cell.
- **Medium upkeep and QC:** state the volume per specimen and the replacement schedule for long runs, logging pH (and oxygen, where logged) at every replacement; per batch, check pH with a calibrated meter, conductivity, the major ions, and that the batch carries **no precipitate** — right after preparation and again at the end of use. Include the records in the report.

### Test methods — please quote each as an option

**General conditions.** Constant-amplitude, force-controlled axial loading. The stress ratio is **confirmed before the order**: quote for fully reversed loading (**R = −1**) and tell us which other ratios your machines and the specimen geometry support — an as-printed thin gauge may buckle in compression.

**A. Conventional axial machine in the solution, to 10⁷ cycles.** State the frequency you would use, the channels available, the cell type (immersion or flow) and the machine time per specimen.

**B. Ultrasonic fatigue (about 20 kHz) in laboratory air, to 10⁹ cycles.** State the cooling method and pulse–pause regime, and the effective test time per specimen.

**C. Ultrasonic fatigue in the solution, to 10⁹ cycles** — whether it is possible at all; if so, how the specimen is kept wetted and at temperature.

**D. Frequency bridge.** The same stress level, series and medium at two frequencies within their shared range (up to 10⁷ cycles). Frequency effects in titanium alloys have been reported to depend on where the crack initiates, so we would rather measure the effect than assume it. Tell us whether the bridge can run on one specimen geometry: with two geometries it mixes frequency with geometry.

**E. Long static pre-exposure in the solution, then fatigue** — for example several weeks of immersion before cycling. State how practical this is for you.

**F. Low-frequency cycling at 1–5 Hz in the solution** — machine time per specimen to 10⁷ cycles, and a price per machine-month.

**Run-out.** Quote run-out options at **10⁷, 10⁸ and 10⁹ cycles** for each method where they apply. State what you do with run-out specimens (for example re-testing at a higher level) and how you report them.

### Stress levels

1. **Anchor the levels of each series on the measured tensile properties of that series' same-build witnesses.** We want the tensile results before the fatigue levels are set.
2. **Finite-life levels** to fix the slope, plus a **staircase (or probit) around the transition** at the chosen run-out. Propose the number of levels, the spacing and the method.
3. **Re-anchor per series.** The series may differ substantially, so one common grid could put half of a series' specimens into run-out or into immediate failure.

### Stop criteria, fractography and statistics

- **Stop criteria:** state the criterion each machine stops on — separation, a stated drop in stiffness or resonance frequency, or a detected crack — and record on every data point which criterion ended the test. The criterion is **confirmed before the order**. The function of our part can be lost at crack initiation, before the specimen separates: tell us whether and how you can detect initiation, and at what crack size, as a priced option.
- **Fractography:** **SEM fractography of every failed specimen**, with the crack-initiation site classified per specimen (for example at the surface, at a near-surface pore or defect, or internal) and images — price per specimen.
- **Statistics:**
  - quote the minimum number of specimens per series for **(a) a median S-N curve** and for **(b) a lower-bound curve** at a stated percentile and confidence level;
  - tell us how your analysis treats specimens within one series whose cracks initiate by **different mechanisms** (for example surface versus internal initiation) — as one population or as separate ones;
  - name the standards you work to, with their editions: the axial method (ASTM E466 or ISO 1099), statistical planning (ISO 12107), and any practice you follow for corrosion fatigue and for ultrasonic testing.

### Programme phases (please price separately)

1. **Pilot** on a few specimens of the production condition: tensile witnesses, first fatigue points and their fractography — before the full programme.
2. **Production condition in the solution** (one or two build orientations), with fractography.
3. **Further series** (one build orientation).
4. **Very-high-cycle extension** of the production condition by the route you recommend among A–F.

### Data we need back

Fitted curves alone are not enough: we compare the results against our own models and may re-analyse the raw points.

- **Every data point:** specimen ID (with the build, plate position and orientation supplied with it), series, stress amplitude and mean stress (or R), the section used to calculate stress, frequency, cycles, stop criterion, run-out flag, test start and end, and the environment logs — temperature, pH, dissolved oxygen and potential where applicable.
- **Native machine records and an open export** (CSV or ASCII) per specimen: force, displacement or stiffness history, or resonance-frequency history for ultrasonic tests.
- **Tensile witness curves** (raw), and roughness data with the parameter and the instrument.
- **Fractography images** of every failed specimen with the initiation-site classification, and a **deviation log**.
- **The statistical analysis together with its inputs** — raw points, never only fitted curves. Tell us whether you return tested specimens, with fracture surfaces protected.

### What we ask you to provide

1. **Capability statement:** axial machines (type, load range, frequency range, channels), ultrasonic fatigue system, corrosion-fatigue cells (immersion or flow, temperature control, pH and oxygen logging, potentiostat), SEM, tensile testing and roughness measurement.
2. **Comparable work:** fatigue of additively manufactured titanium, corrosion fatigue, very-high-cycle fatigue (redacted examples are fine).
3. **Accreditation and quality system**, with certificate number, issuing body, scope and validity — ISO/IEC 17025 (say whether its scope covers fatigue testing) and ISO 9001, whichever you hold.
4. **Itemised prices:** machine-hour per method (A–F) · cell set-up, and medium preparation and QC per batch · tensile witness per specimen · roughness per series · SEM fractography per specimen · each option separately (initiation detection, potential control, oxygen control) · specimen design · statistical planning, analysis and report · the pilot.
5. **Turnaround:** queue time to start, the duration of each phase, and the report.
6. **Quote format:** currency, validity period, payment terms, and the technical point of contact.

### Confidentiality & publication

The technical specification is openly published, so no confidentiality agreement is needed to discuss it; we are happy to sign your standard mutual CDA covering commercial terms (prices, schedules, QC data). We may publish the results — please state any conditions you attach to publishing data you generate for us, such as acknowledgement or a description of your method.

### Possible follow-on (not part of this quotation)

- The same programme, or its production-condition part, on a second alloy once it is selected.
- Fatigue of a welded joint between a cold-drawn titanium wire and a printed titanium part.
- Fatigue of lattice (gyroid) specimens.

If any of these is within your scope, say so and we will send a separate request.

### Commercial & logistics

- Specimens reach you from the manufacturer, which may ship from Ukraine; tell us your receiving requirements.
- Tell us whether you prepare the medium from our recipe (preferred) or need it supplied.
- The Incoterms you quote on for returning tested specimens, and any export-control considerations you are aware of.

### Attachments

Nothing is required from us for an initial quotation. On request we supply the medium recipe once confirmed, and the specimen requirements above as a drawing once you have proposed the geometry.

---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 4. Cross-references

| Ресурс | Що бере |
|---|---|
| [`sn_fatigue_test_plan`](../anchor/sn_fatigue_test_plan.md) | дім змісту: серії, рівні, маршрути A–F, критерії, статистика, відкриті ⚖️ §9 |
| [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | рецепт синтетичного соку (дім) · частота гойдання 1–5 Гц |
| [`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §1.7`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | маршрут процесу деталі, який повторює зразок · HIP |
| [`01_01 §1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | мало й непостійно O₂ у ксилемі · метал як струмозбирач анода (звідки опція потенціалу) |
| [`vendor_templates`](vendor_templates.md) §Processing п.16 | зразки питанням у DMLS-листі; пп. 2–4 на серії не поширюються |
| [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) | взірець листа · та сама таблиця середовища |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс · §3 IP/CDA · §4.B |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 · HW.24 · HW.27 | дім стану · делегований сліпий аналіз · плече Δbake |
