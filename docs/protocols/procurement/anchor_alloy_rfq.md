# Anchor Alloy — Ti-coupon RFQ (Stage-2 6-alloy bake-off, AM / CRO-ready)

> **Що це:** RFQ-аркуш для **substrate-половини** Stage-2 coin: 6 плоских Ti-купонів Ø16×1 мм у різних сплавах →
> емпіричний **down-select сплаву Zone 1** ДО committed 100-партії. Парний chem-стек (фермент/ZIF/мембрана) — окремий
> аркуш [`ebfc_chem_rfq`](ebfc_chem_rfq.md); тести — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).
> **Статус:** 🟡 робочий артефакт (не канон). **Усі числа — дзеркало канону**: сплави/властивості → [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) + `tools/in_silico/lib/constants.py ALLOY_PROPERTIES`; геометрія → [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md); **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). **Надіслано 2026-11-05** трьом бюро першої хвилі — стан і нагадування: [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24.
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (Анкер-сплав рядок · hard-constraint доми §4.B/§4.E).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — specs відкриті; CDA = стандартні комерц-умови.

---

## 0. Як користуватись + cover-note

1. Купон = плоский диск **Ø16×1 мм**, 1 грань = π·8² = **2.01 см² ≈ A_electrode** ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)); `j` нормують на **проєкційну** площу. **«Вушко»** (отвір/виступ на краю) під потенціостат-кліпсу, не псуючи активну грань.
2. **CEM-SSOT + креслення:** геометрія — `tools/cad/cem/ti_coin.<alloy>.json`; STL — `dotnet run --project tools/cad/src/SilkenCad -- build cem/ti_coin.<alloy>.json`, DXF (+SVG) — той самий виклик із `draw` (per-alloy title-block); вендору аркуші йдуть у вендорській формі — той самий виклик із `draw --vendor`, вихід у `tools/cad/out/vendor/` (⚖️ founder 2026-10-15, `tools/cad/docs/drawings_program.md` §8 п. 5; збудовано того ж дня — перелік змінених нотаток founder бачить разом із діфом до відправки; першу хвилю перебудовано з чистого дерева й надіслано 2026-11-05 — Стан [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24). ⛔ Перебудовувати В ДЕНЬ відправки й звіряти bbox STL із маніфестом: `tools/cad/out/` під `.gitignore`, і копію, що їде вендору, не стереже жоден гейт (скіл `picogk` #17). ⚠️ Петлю (вушко) аркуш малює, але розміру їй не ставить — в обох формах; до наступної відправки аркушів — 🤖-нога [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24.
3. **Cost-driver = к-сть СПЛАВІВ** (порошок/SLM-сетап), не монет → купони дешеві, тож запас замовляється одразу (12 на сплав у точці ціни, §3; у замовленні — за числом реплік, [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) «Репліки»). Замовляти Tier-1 одразу; Tier-2 — паралельний vendor-hunt (не блокує TRL-4).
4. **Дерево-first:** down-select за CV/EIS + ICP-MS у **синтетичному ксилемному соку** (не PBS); Al³⁺ теж фітотоксичний → zero-Al кандидати дерево-чистіші ([`01_04 §4.2`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 1. Per-alloy spec (6 купонів — усі рівні до coin-даних)

| # | Сплав | Стандарт (AM ⊥ wrought) | V/Al wt% | E (ГПа) | Вісь bake-off | Tier |
|---|---|---|---|---|---|---|
| 1 | **Ti-6Al-4V** Gr5 | **F2924 — AM PBF** (єдиний AM-стандарт у таблиці) | 4 / 6 | 110 | control + друк-еталон (V+Al токсичні = нижня межа) | 1 |
| 2 | **Ti-6Al-7Nb** | F1295 / R56700 — **wrought**, лише склад | 0 / 6 | 103 | V-free (Al лишається) | 1 |
| 3 | **CP-Ti Gr4** | **F67 Gr4 / R50700** — wrought, лише склад | 0 / 0 | 104 | zero-tox, α-Ti (міцність ↓ ~480) | 1 |
| 4 | **β-Ti-13Nb-13Zr** | F1713 / R58130 — **wrought**, лише склад | 0 / 0 | 80 | low-E dual-win: менший розрив модулів із деревиною ([`01_01 §5`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)) | 2 |
| 5 | **Tantalum** | F560 / R05200 — **wrought**, лише склад | 0 / 0 | 186 | benchmark біоінертності (⚠️ Ta₂O₅ DET-ризик; coin-only) | 2 |
| 6 | **Ti-15Zr** (Roxolid) | **стандарту НЕМАЄ** — датшит постачальника | 0 / 0 | 100 | high-strength V/Al-free (практичний анкер-кандидат) | 2 |

> 🔴 **Колонку звірено з ОБЛАСТЮ ЗАСТОСУВАННЯ кожного стандарту 2026-09-11 (HW.24), і два рядки називали не той предмет.** `F1581` на CP-Ti Gr4 **не є титановим стандартом узагалі** — це *Composition of Anorganic Bone for Surgical Implants*, кістковий апатит із нульовим вмістом Ti; нелегований титан специфікує **F67**, де Grade 4 = UNS R50700. `F2066-class` на Ti-15Zr є **Ti-15 МОЛІБДЕН** (UNS R58150) — збігається число, не елемент; стандарту ASTM чи ISO на бінарний Ti-Zr не існує ні для AM, ні для деформованого, бо Roxolid пропрієтарний Straumann. ⛔ Не відновлювати жодного з двох.
>
> ⚠️ **Друга вісь, і вона переживає обидва фікси: ми замовляємо ДРУК, а п'ять рядків із шести цитують специфікації ДЕФОРМОВАНОГО металу** (слово *Wrought* стоїть у власній назві F1295 · F67 · F1713 · F560). Перевірені AM-специфікації титану — `F2924` (Gr5) і `F3001` (ELI Gr23). Тому рядки 2–5 є **посиланням на СКЛАД**, ніколи на режим друку, а рядок 6 не має й того. ⛔ **А от чи ІСНУЄ AM-спека для 7Nb / CP-Ti / β-Ti — ми НЕ знаємо, і писати «немає» не можна:** `ASTM F3302` («Additive Manufacturing · Finished Part Properties · Titanium **Alloys** via Powder Bed Fusion») чинний, а його таблиця охоплених марок платна й нами не читана. Для Ta каталог F42 не перелічує жодної спеки матеріалу (єдина тугоплавка — `F3635`, Nb-Hf), але **перелік каталогу слабший за прочитану область застосування**. Тому в листі ми не стверджуємо відсутність, а ПИТАЄМО вендора (§Powder specification нижче). ⚖️ **AM-стек купонів — мінімальний (ратифіковано founder 2026-09-17):** вендор сам декларує порошок і процес, до яких друкує (§Powder specification нижче). Повний стек (склад по спеці вище · порошок ISO/ASTM 52907 · **процес і машина ISO/ASTM 52904** · термообробка F3301 · приймання по свідках-купонах F3122) іде в part-RFQ Stage 3 ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.1, нога «текст part-RFQ»). **Підстава:** це присуд закупівлі, не інженерії, а на Stage 2 потрібні купони, не кваліфікація виробництва; повний стек піднімає ціну й відсіює дрібніші бюро. **Ціна:** частина різниці між сплавами може йти від процесу вендора, а не від сплаву.
>
> ⛔ **Не звужувати вимогу до ELI** ([`02_06 §8.1.1`](../../02_06_Unit_Economics_and_BOM.md)): купон №1 є Gr5-контролем і друк-еталоном, тож ELI-спека (`F136` — до того ж wrought, тобто хибна для друкованого купона на обох осях) замовила б у вендора інший порошок; фінальний сплав визначає bake-off, не лист.

**+ Au-coated bracket (7-й купон, обовʼязковий — `cem/ti_coin.au.json`):** DET-electrical **стеля** (Au = найкращий electron transfer), пара до Ta біоінертної стелі → реальні сплави затиснуті між двома межами. Surface-only (дешевий Ti + thin Au), **НЕ** структурний/анкер-кандидат. ⚖️ **Не опційний з 2026-09-18:** несе катод дня 0 — межу осі «оксид ↔ DET» ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)) — і є входом гілок (1)/(2) ратифікованого правила вибору катодного важеля ([`01_03 §3.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): без нього «катод на Au ≈ / помітно кращий за катод на Ti» нічим виміряти. На число 4V («at 12 and at 19») не впливає — це окремий купон.

> ⚖️ **Ланцюг обробки, коли рядки друкують різні бюро — founder 2026-11-17, дослівно «так на пропозицію»:** бюро роблять лише друк, відпуск і зняття підтримок без абразиву; HIP — один виконавець для всіх титанових рядків; травлення з прогріванням — один виконавець на всі купони одним заходом (так зберігається вимога «усі купони травить один виконавець», §1 листа нижче). Так уже домовлено з першим бюро для рядка 1 ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.1).

**Спільна обробка (усі купони):** SLM/LPBF друк → **HIP** (920°C/100-150МПа Ar/2-4год, §4.B — ⚠️ це режим **Ti-6Al-4V**; для решти Ti-сплавів режим не зафіксовано й EN-лист його ПИТАЄ, бо β-трансус Ti-13Nb-13Zr ≈ 735 °C лежить нижче обох температур, а один цикл на всі сплави є відкритим ⚖️ [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24, «CEM-сироти» п. (1); форма, у якій лист це питає, — присуд 2026-09-18, [`01_02 §1.7`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) → **EAAE dual-scale** активація грані (Sa 0.5-5µm + Sv 50-500nm, [`01_02 §1.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) → **dehydrogenation bake** (250°C/10⁻³mbar, <2год після rinse, H<100ppm, §4.B — ⚠️ як і HIP-режим поруч, це відкрита вісь: чи 250 °C дегазує, вирішує пара LECO+XRD за правилом R1–R3, і канон має маршрут БЕЗ bake [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.27). ✅ **Ta і Au розсуджено (⚖️ founder 2026-09-17, дім [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) Failure Mode C):** Ta (п.5) — той самий bake, **HIP — N/A** (920 °C = 0.36 T_m Ta), а H — **звітом проти 15 ppm F560**, не прийманням (⊕ 2026-10-15, дім [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) C); Au-купон (п.7) і Ta-покриття — Ti-підкладка проходить увесь маршрут Ti-купонів **до** покриття, bake після покриття декларує вендор, roughness factor Au — лише звіт. ⚠️ **EAAE-протокол написаний під 4V і не проганявся жодного разу (фізичної партії немає), тож per-alloy etch-tuning потрібен КОЖНОМУ купону, крім самого 4V-контролю** (CRO; coin виявить — squeeze-data SEM Sa/Sv). 🔴 ⛔ Не звужувати цю вимогу до переліку окремих сплавів: різна хімія травиться інакше, а «інша за 4V» є кожна з п'яти. **Ціна звуження не косметична — вісь травлення задає ECSA, тобто `j_max`, тобто головну метрику down-select'у: сплав, який CRO протравив 4V-протоколом, порівнюється з підтюненими сусідами й програє приладу, а не собі.**

**QC/acceptance (substrate):** **SEM грані ПЕРЕД відправкою — ×5 000 (Sa) і ×50 000 (Sv)**, обов'язок заводу за [`01_02 §1.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); не видно нанопор при ×50 000 ⇒ травлення недостатнє ⇒ повторити Крок 4 (⛔ ПЕРШИЙ кадр §1.5, ×500 по макропорах гіроїда, на плоскому купоні предмета не має) · LECO RH404 або еквівалент, H<100ppm (рядок 2, 7Nb — ≤ 90 ppm інструкцією PO, §5a) · ICP-MS промивної води (Al<1ppb для 4V/7Nb) · контроль промивки на залишкові Cl⁻ · F⁻ · SO₄²⁻ перед bake — метод і межу виявлення називає вендор (Крок 5 [`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); дзеркало п.14(c) DMLS-листа).

> ⚠️ **Кисень — ліміт питаємо, числа не цитуємо.** AM-спеки несуть стелю O: `F2924` (Gr5) **0.20 wt%**, `F3001` (ELI Gr23) **0.13 wt%** — обидва числа з ВТОРИННИХ джерел (первинні ASTM платні й не читані; ⊕ 2026-11-07: обидва звірено з прев'ю тексту чинних F2924-14 і F3001-14 (обидві Reapproved 2021), Table 1 — збігаються, [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) C ⊕ «Чинні редакції»; підставу «вторинні» цим знято, тож «числа не цитуємо» відтоді описує надісланий лист, а не підставу для наступного), тому EN-лист просить вендора назвати ліміт, до якого він сертифікує партію порошку, його спеку й виміряне значення, а не наводить їх. Причина вимоги: повторне використання порошку набирає кисень цикл за циклом, і перекиснена партія втрачає пластичність і в'язкість руйнування, лишаючись «титаном» на CoC.

> ✅ **Параметр шорсткості розсуджено (⚖️ founder 2026-09-17, дім [`01_02 §1.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)):** areal **`Sa` за ISO 25178**, смуга 0.5–5 µm; `Ra > 0.5` зі §1.5 зведено до цього рядка. Прилад · площу оцінки · фільтри декларує вендор, ми підтверджуємо до замовлення. Ціна: цех без оптичної профілометрії віддасть метрологію на субпідряд.
>
> ✅ **Травлення (⚖️ founder 2026-09-17, дім [`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) Крок 4):** параметри декларує вендор, приймання — за досягнутими Sa/Sv; **усі купони цього замовлення травить один виконавець одним заходом**, бо процес між вендорами не відтворюється, а вісь травлення задає ECSA, тобто головну метрику down-select'у.

---

## 2. Sourcing tiers (заземлено)

**Tier-1 — одразу (control + V-free baseline → достатньо для TRL-4):**
- **Ti-6Al-4V** — UA **3D Metal Tech Київ** (Concept Laser M2, ISO 13485) / EU Protolabs.
- **CP-Ti Gr4** — medical AM-бюро (Eplus3D/MET3DP), дентал-стандарт.
- **Ti-6Al-7Nb** — ISO-13485 ортопед-стандарт (medical AM-бюро).

**Tier-2 — vendor-hunt паралельно (НЕ блокує):**
- **β-Ti-13Nb-13Zr** — research-grade порошок (гаряча LPBF-тема 2024; UTS~1020/yield~795 — ⚠️ літ-оцінка **розходиться** з дім-значенням `ALLOY_PROPERTIES` (`tools/in_silico/lib/constants.py`) `yield_MPa: 900`; жодне з двох не несе джерела — ймовірно as-built LPBF vs HIP'd, але це **не звірено**; для vendor-hunt-контексту не несуче, для acceptance — звірити ДО спека) → академ-колаборація (co-pub, TBD — [`00_02`](../../00_02_Academic_Integration_and_IP.md)) або спец-порошок.
- **Ta** — LPBF **рідко** (вартість/відбивність/ризик принтеру) → **думка-outside workaround: Ta-coating на дешевому Ti-купоні** (біоінертна Ta-поверхня без bulk-Ta друку; EBFC бачить поверхню). ⚠️ **«Bulk-Ta лише за EBM-вендором» ЗНЯТО 2026-09-11:** LPBF-Ta існує промислово (вимір `00_07` HW.24), тож маршрут не обмежений EBM; відкритим лишається інше — **bulk-Ta ⊥ Ta-покриття на Ti**, і це присуд, бо друга гілка перетворює купон на підкладку з покриттям (патерн `.au`) і тягне за собою відпал підкладки.
- **Ti-15Zr** — Roxolid пропрієтарний (Straumann); AM-порошок research-grade → спец-постачальник або defer.

> ⊕ **2026-11-17, пізніше — для Ti-6Al-7Nb знайдено активну групу:** Кошалінський технологічний університет (Польща) надрукував його 2024 року на LPBF-машині ORLAS CREATOR з порошку SLM Solutions (*Materials* 17:4604, DOI 10.3390/ma17184604, прочитано того ж дня); отже порошок продається комерційно, бракує бюро — і це шлях на потім для бюро з відкритими параметрами машини. Лист (Б) — блок нижче.
>
> ⊕ **Desk-прохід 2026-11-17 — рядки першої хвилі без ванадію (CP-Ti · Ti-6Al-7Nb): кандидати, не домовленості, жодному не писали** (звіт з URL кожної сторінки й переліком запитів — корпус естафет, `handoff/2026-11-17_hw24_vfree_lpbf_bureaus.md`; ключові рядки звірено повторно того ж дня). **Перша хвиля:** з титанових сплавів 3D Metal Tech друкує лише Ti-6Al-4V (їхня відповідь 16.11), ALT print — так само (на власній сторінці матеріалів лише «Титан Ti6Al4V»), а сайт Velta переліку матеріалів не має. **CP-Ti:** Amnovis (Аршот, Бельгія; ISO 13485) — валідовані Ti-6Al-4V Grade 23 і Ti Grade 1; 3D Activation (Вісбаден, є й швейцарський сайт) — «Titan Grade 2» під SLM, ISO не заявлено; 3D Systems — матеріал Ti Gr 1 для власних машин, контрактний друк ним не підтверджено; Croom Medical — титан без марки. ⚠️ Grade 4, який стоїть у рядку CP-Ti вище, жодне з цих бюро не називає — доступні Grade 1 і Grade 2. **Ti-6Al-7Nb:** комерційного бюро в Європі й Україні не знайдено — лише дослідницькі групи (Вроцлавська політехніка, Падерборнський університет) і постачальник порошку для їхніх робіт; набору параметрів для цього сплаву не публікує жоден із великих виробників машин.
>
> ⊕ **Desk-прохід Tier-2 2026-11-15 — кандидати, не домовленості: жодному з названих нижче ще не писали** (рядки вище НЕ переписано; звіт проходу з URL кожної сторінки — корпус естафет, `handoff/2026-11-15_hw24_tier2_vendor_hunt.md`).
> - **Ta — серійна LPBF-послуга є, з іменами.** Croom Medical (Ірландія, сторінка `croommedical.com/talos`): «Available for customer designs from prototype to volume manufacturing»; там само — друк танталу на титанову підкладку, тобто третя гілка розвилки «масивний ⊥ покриття»: наплавлений LPBF-шар Ta на Ti. Thrustworks (Німеччина, `thrustworks.com`): «Pure Tantalum» у переліку матеріалів поруч із «Titanium Grade 5» — LPBF сторінка називає загальною спроможністю й до танталу прямо не привʼязує. Параметр виробника машини — Colibrium, M2 Series 5 (датшит RevA 2024-11-06: 400 Вт, шар 30 мкм, відносна щільність 99.95 %, порошок 15–45 мкм «similar to ASTM B365»): це гачок до бюро першої хвилі з машиною того ж сімейства — чи вона Series 5 і чи беруть вони Ta за цим параметром, знає лише бюро. Порошок Ta продають TANIOBIS і Global Advanced Metals — друку на прочитаних сторінках не пропонує жоден.
> - **β-Ti-13Nb-13Zr — бюро, що перелічує цей сплав серед своїх матеріалів, не знайдено; шлях — кастомний порошок і друк із нього.** Друкованість показує література (Hariharan et al., *Materials & Design* 217 (2022) 110618 — LPBF саме цього сплаву; де робили порошок, анотація не каже — це прочитав із повного тексту лише перший прохід). Кастомну атомізацію малих партій заявляє AMAZEMET (Польща, `amazemet.com`: «from just a few grams to a few kilograms»; сплав поіменно не названо); ECKART TLS (Німеччина) як виробника такого порошку називає лише перший прохід. Серійний безалюмінієвий β-сусід у каталозі TANIOBIS — Ti-42Nb: інший сплав, тож заміна була б присудом, а не закупівлею.
> - **Ti-15Zr — у периметрі проходу не знайдено ні каталожного, ні «research-grade» AM-порошку, ні бюро**, що його друкує: твердження рядка вище «AM-порошок research-grade» цим проходом не підтверджено — носія не знайдено. Лишається кастомна атомізація зі сплаву, виплавленого на замовлення; датшит порошку, якого чекає нога рядка 6 ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24), зʼявиться тоді лише з кастомною партією.
> - **Стеля проходу:** 24 пошукові запити (англійською й один німецькою) і 26 відкритих сторінок. Другим читанням дослівно звірено сторінки Croom · Thrustworks · AMAZEMET · TANIOBIS, запис статті й текст датшита Colibrium; решту читано одним проходом через зведення сторінок — перед листом звіряти оком. Поза периметром — бюро Китаю й США, пошук польською та українською. Про мінімальне замовлення, дослідні партії й відправку в Україну не каже жодна прочитана сторінка — це питання першого листа, не висновок проходу.

---

## 3. Test battery + acceptance (дім — `01_03 §3.5`)

На кожному функціоналізованому купоні (Gen 2.0 стек з [`ebfc_chem_rfq`](ebfc_chem_rfq.md)):
- **CV/EIS** у синт. ксилемному соку *Pinus sylvestris* pH 5.75 (рецептура й pH — [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): j_max, k_s, DET-маржа.
- **Бічна ICP-MS-серія:** по три **непокриті** купони на сплав (та сама обробка, без стеку) — занурення при pH 4.5 лише під ICP-MS ([`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), ⚖️ 2026-09-17); звідси 6 купонів на сплав під coin-тест. ⊕ **Ще 6 непокритих — запас під 12-тижневий прискорений тест** (⚖️ founder 2026-09-25, дім «Концепція» [`01_02 §2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): по 3 на кожну з двох серій його ТЗ 1 (40 °C · опційна 25 °C), на всі шість сплавів, бо down-select ще не відбувся; травляться тим самим заходом — разом **12 на сплав**.
- **ICP-MS** іон-release у сік: V≤0.02 / Al≤0.05 µg/cm² (4V/7Nb); Nb/Zr/Ta — informational (біоінертні). Predicted — `tools/in_silico` script 51.
- **30-day stability** ≥80% retention · **chloride** 0.25M ramp · **UCST** −10→+25°C recovery (квантитативні пороги — дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
- **Нано-індентор E** (post-coin) — модуль СУЦІЛЬНОГО сплаву купона (β-Ti dual-win check). ⛔ **Це НЕ перевірка жорсткості ҐРАТКИ, і плутати два виміри дорого:** апарентна жорсткість є властивістю ґратки, купон її не має, а порівнювати треба з ПОПЕРЕЧНИМ модулем деревини `E_R`/`E_T` ≈ 0.5–1.5 ГПа — анкер сидить поперек стовбура ([`01_01 §5.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)). Поздовжні 9–16 ГПа — ~вдесятеро завищена ціль. Апарентну жорсткість самої ґратки міряє voxel-FE (`dotnet run -- fea`, дім числа — [`01_01 §5.2`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)); фізичний метод для неї — ISO 13314 на друкованому зразку, не нано-індентор на купоні.

- **Чому 4V у листі «at 12 and at 19»** (⚖️ розкладка founder 2026-09-18, дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): 4V єдиний несе пʼять електродних плечей — аноди · катоди з нанозимом · контроль без нанозиму · свіжі катоди під хлорид D · свіжі аноди з мембраною під E — і жодне порівняльне плече не стоїть на одній репліці: 5 × 2 + 3 непокриті = 13, плюс 6 запасу 12-тижневого тесту = **19**. Це точка ціни, не замовлення: число реплік фіксується після цін лабораторії, а решта сплавів поки лишається на 12 (точка ціни; у замовленні — за числом реплік, [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) «Репліки»).

**Electrochem-CRO:** кандидат **EL-CELL (DE)** — ⚠️ не підтверджений: публічна сторінка його лабораторії описує тестування Li-ion батарей, а ICP-MS і ISO/IEC 17025 не згадує (звірено 2026-09-13); лист лабораторії — [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md). Альт: ЧНУ co-pub ([`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md)).

---

## 4. Hard constraints (RFQ МУСИТЬ нести — дзеркало канону)

- **§4.B метал** ([`01_02 §1.6/§1.7/§1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): для bulk-структури анкера **SLM НЕ EBM** Zone 1 (порошок 15-45µm) — для плоского COIN менш критично, але грань потребує тієї ж EAAE-шорсткості · **HIP обов'язково** · **dehydrogenation bake** після EAAE — ⚠️ до арбітра це **процедура запису**, а не доведена дегазація, і за правилом R1–R3 канон має гілку БЕЗ bake (обидва — для Ti-сплавів; Ta — bake так, HIP N/A; Au/Ta-покриття — маршрут Ti до покриття, [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) · **ZnO-Ta ЗАБОРОНЕНО** на активній грані (блокує DET) · **контроль промивки на залишкові Cl⁻ · F⁻ · SO₄²⁻ перед bake** (Крок 5 [`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) — лист, як і п.14(c) DMLS-листа, питає метод і межу виявлення, а порогу канону не друкує: поріг судиться лише проти межі виявлення того методу, який назве вендор. · **свідки ГІП — опційним рядком** (⚖️ делеговано 2026-10-02, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24): по парі на титановий сплав із тієї самої побудови — один поза ГІП, один крізь цикл; шліф SEM/EDS і O/N — окремими цінами на пару, звіт без порогу. Підстава: ГІП-ТЗ п. 1/6/10/14 уже розраховує на свідків «разом із деталями», а його перша партія — саме ці купони; без цього рядка ТЗ посилалося б на свідків, яких ніхто не друкує, а перший титановий цикл власника газостата не відділив би насичення киснем і азотом від сплаву. Мінімальний AM-стек (§1, ⚖️ founder 2026-09-17) це не скасовує: приймання по свідках F3122 лишається в part-RFQ Stage 3, тут — діагностичний звіт; вужчає лише його підстава «повний стек піднімає ціну». Ціна: друк свідків майже нічого не коштує (ціну задають сплави й сетапи, не кількість деталей — §0 п.3), ціни шліфу й O/N у дереві немає, і це ще одна правка схваленого листа (діф — нога відправки). Найслабша ланка: звіт не споживає жодне рішення Stage 2, а план S-N виключає свідка з плеча ΔHIP; якщо друк-бюро ГІП-ує в себе, підстава «ТЗ розраховує на свідків» вужчає до самого газостата бюро.
- **§4.E стерилізація** (якщо купон функціоналізований до тесту): **Co-60 НЕ EtO** · low-dose 15кГр для ферментів ([`01_04 §6`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 5. Dispatch checklist (👤)

- [x] 👤 **Tier-1 RFQ — надіслано 2026-11-05** (стан і нагадування — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24) (4V/7Nb/CP-Ti) → 3D Metal Tech Київ · ALT print (ТОВ «Адитивні лазерні технології України», скор. «АЛТ України») · Velta Medical (Дніпро) — усі три звірено desk-пошуком 2026-09-17, [`ua_vendor_map §1`](ua_vendor_map.md); ⚠️ HIP в Україні як комерційної послуги «принесіть деталь» немає, але МАРШРУТ є ([`ua_vendor_map §2`](ua_vendor_map.md)): Інститут магнетизму (Київ, камера Ø32 — купони й аноди; фланець у поточній моделі (по вушках до Ø33.8 — верхня межа; вушка переносяться всередину Ø29.8, форма ще не змодельована, [`02_02 §4.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) у неї прямо не входить, питанням) і Мотор Січ (Запоріжжя, наскрізний «друк → ГІП 1160 °C/160 МПа → вакуумна ТО 980 °C» на НАДРУКОВАНИХ зразках — ⚠️ зразки статті з Inconel 718, не з титану, а власника газостата стаття не називає, [`ua_vendor_map §2`](ua_vendor_map.md)) — писати їм НАПРЯМУ окремим листом ([`anchor_hip_rfq`](anchor_hip_rfq.md) — ТЗ українською, написано 2026-09-18, надіслано 2026-11-05 обом — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23), а не питати друк-бюро «хто ваш HIP-партнер» / EU medical AM-бюро: 12 на сплав (6 під coin-тест — 3 функціоналізовані + 3 непокриті під ICP-MS — і 6 запасу 12-тижневого тесту), 4V — ціна на 12 і на 19 (⚖️ founder 2026-09-25, §3), Ø16×1+вушко, HIP+EAAE+bake, SEM+ICP-MS acceptance. STL+DXF з `tools/cad` (`build` · `draw --vendor`).
- [ ] 👤 **Tier-2 vendor-hunt** (∥): β-Ti — академ-колаб/спец-порошок; Ta — спершу масивний (EN-лист, пункт 5), Ta-покриття на Ti — лише альтернативним рядком того самого листа (bulk ⊥ покриття — відкритий ⚖️ [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24, тримає відповідь вендора); Ti-15Zr — спец-постачальник.
- [ ] 👤 **Electrochem-CRO RFQ** — текст і чекліст відправки живуть в [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) (CV/EIS у синтетичному соку · 30-day · chloride · UCST · ICP-MS); адресат TBD — EL-CELL не підтверджений (↑). Середовище — синтетичний ксилемний сік — готує сама лабораторія за рецептурою [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md): ⚖️ 2026-09-22 make-vs-buy знято, окремого кроку «сік» немає ([`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.17).
- [ ] 👤 **Критичний шлях паралельно:** chem-стек ([`ebfc_chem_rfq`](ebfc_chem_rfq.md) Spec A фермент 🔴 4-8тиж) — усе сходиться на функціоналізованих купонах.

---

## 📤 Dispatch block (EN) — paste into vendor email

> Ready-to-send English text. Working body above stays Ukrainian. Anything our side
> must NOT disclose is deliberately absent — **немає:** імен друк-бюро та академ-каналу й Tier-1/Tier-2
> розкладки (§2 = наша sourcing-стратегія, лист мусить бути сліпим), літ-числа β-Ti UTS/yield
> (§2 сам каже «не звірено» → в acceptance не йде взагалі), «Вісь bake-off»/V-Al-раціоналі
> (наш down-select), трекер-ID/канон-рефів, `tools/cad`-команд (вендору віддається STL+DXF,
> не команда генерації), статус-маркерів.
> Адресат — **друк-бюро (laser-PBF)**; електрохім-характеризація = окремий запит, у цьому листі її немає → [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

RFQ — laser-PBF titanium coupons, Ø16 × 1 mm, six alloys, HIP + surface activation (R&D batch)

### Scope of request

We are an R&D group and need a small batch of flat metal coupons produced by laser powder-bed fusion in several titanium alloys (plus one refractory metal), post-processed and surface-activated as specified below. The coupons are used as working electrodes for electrochemical characterisation on our side, so surface condition and cleanliness are what we buy — mechanical performance is not an acceptance criterion for this order. Geometry is supplied by us as STL plus a dimensioned DXF drawing.

### Item specification

- **Geometry:** flat disc, **Ø16 mm × 1 mm** thick, with a small tab or edge through-hole for a potentiostat clip. The tab must not encroach on the active face. Per-alloy STL and dimensioned DXF are attached and are the **dimensional authority**.
- **Quantity: 12 per alloy** — 3 for electrode testing, 3 for an uncoated ion-release series and 6 uncoated coupons held in reserve for a separate 12-week corrosion test, all processed identically and etched in the same run. **Ti-6Al-4V will be ordered in a larger count than the rest**: it alone carries the cathode comparison and two further series on fresh coupons, so please quote it at 12 and at 19. Please quote **each alloy as a separate line item** — we may award a subset depending on powder availability, and we may repeat the order at the same setup.

- **Powder specification:** for each alloy, state the powder specification you would actually use (designation, ASTM/ISO spec, grade, particle size distribution, lot traceability). If your available powder differs from the standard cited below, quote your equivalent and tell us what it is — do not substitute silently.

| # | Alloy | Standard cited | Qty |
|---|---|---|---|
| 1 | Ti-6Al-4V | ASTM F2924 — additive manufacturing, powder bed fusion | 12 |
| 2 | Ti-6Al-7Nb | ASTM F1295 (UNS R56700) — wrought spec, cited for CHEMISTRY only | 12 |
| 3 | CP-Ti Grade 4 | ASTM F67 Grade 4 (UNS R50700) — wrought spec, cited for CHEMISTRY only | 12 |
| 4 | Ti-13Nb-13Zr (β-Ti) | ASTM F1713 (UNS R58130) — wrought spec, cited for CHEMISTRY only | 12 |
| 5 | Tantalum | ASTM F560 (UNS R05200) — wrought spec, cited for CHEMISTRY only | 12 |
| 6 | Ti-15Zr | **no ASTM or ISO standard exists** for binary Ti-Zr — attach your powder datasheet | 12 |

> **The standard cited for rows 2–5 fixes the CHEMISTRY and nothing else** — each is a wrought-product specification and we are not buying wrought product. Row 1 is the only one where we cite an additive-manufacturing material spec (F2924). **We are NOT claiming that no AM standard covers rows 2–5** — we have not read the covered-grade table of ASTM F3302, so we are asking rather than asserting: tell us the specification you will actually print to (your own, the powder producer's, a company spec, or an AM standard we have missed), and if it differs from the chemistry cited, say how. Row 6 has no published standard at any process route we could find; attach the powder datasheet as the material reference.

- **Item 5 alternative:** if bulk tantalum is outside your process window, we will also consider a **tantalum-coated titanium coupon** of the same geometry (the coating only needs to cover the active face) — quote it as an alternative line item.
- **Item 7 (required):** one coupon of the same geometry in titanium with a **thin gold coating on the active face** — surface treatment only, non-structural. The gold must be **continuous and pinhole-free** on the active face — electroplated hard gold over a nickel underlayer, or sputtered gold with its adhesion layer, your choice; **state the process and every layer thickness** (we fix none), and name the titanium you print the substrate from and to which specification — a pinhole makes it an exposed underlayer (continuity is checked on our side, electrochemically; it is not one of your QC deliverables). Quote it as a separate line, whether you supply it or subcontract it; if you can do neither, say so.

### Processing / QC requirements

- **Process:** laser powder-bed fusion (SLM / DMLS / LPBF), powder 15–45 µm. If you propose a different powder-bed route for these flat parts, flag it explicitly in the quote rather than assuming it is equivalent.
  - **Build atmosphere and layer:** build under **argon** with **chamber oxygen below 0.1 %** for the whole build, and state the oxygen level you actually hold and how it is logged. Our reference layer thickness is **30 µm** — state the layer of your qualified parameter set for each alloy rather than re-qualifying to our number.
- **HIP — mandatory for the titanium alloys:** our cycle is **920 °C, 100–150 MPa argon, 2–4 h**. In-house or through a qualified partner; if a partner, name them and include the cost and time in your quote. **We may also route HIP ourselves to a HIP provider, so please quote the coupons without HIP as a separate line as well, and say whether you would take them back after an external HIP for the activation and bake that follow.**
  - **That cycle is our specification for Ti-6Al-4V, set below that alloy's β-transus; we have not fixed cycles for the other titanium alloys of this order.** For each of them, tell us where the cycle sits relative to that alloy's β-transus and whether you would run a different one — we are asking, not assuming, because a cycle above the transus changes the microstructure we are comparing.
  - **For the Ti-6Al-4V coupons, HIP is followed by a vacuum anneal at 800 °C for 2 h** — quote it on the HIP line or name who performs it. **State the cooling rate or cooling profile of your HIP cycle:** we specify it only as controlled, because the cycle exists to remove the as-built martensite and an uncontrolled cool can bring it back; we hold no number for it, so give yours.
  - **For the other titanium alloys we specify no post-HIP anneal:** for each, state whether you would anneal after HIP and at what temperature, time and cooling — or confirm that none is needed. Do not apply the Ti-6Al-4V anneal to them without our written agreement.
- **Surface activation of the active face:** dual-scale etch producing **areal Sa 0.5–5 µm (ISO 25178)** with sub-micron structure **Sv 50–500 nm**, verified by SEM and profilometry. We hold no validated etch for any of these alloys — our reference protocol is written for Ti-6Al-4V and has not yet been run — and the other alloys will respond differently, so we expect **per-alloy etch parameter development** and ask you to quote it as a separate development line item. **Declare the parameters you use per alloy** (etchant composition and concentrations, time, temperature, agitation) — acceptance is the achieved Sa/Sv, not a recipe. **All coupons of this order, every alloy and the uncoated series included, are etched by a single etcher in a single campaign**; if you subcontract the etch, one subcontractor does all of them.
- **The rinse after the etch removes residual chloride, fluoride and sulphate before the bake** — state the method you verify that with and its detection limit.
- **Dehydrogenation bake after the etch rinse — two independent parameters, both mandatory:** (a) bake **2–4 h** (3 h nominal) at **250 °C ± 25 °C under 10⁻³ mbar**; (b) the bake must **start no later than 2 h after the rinse** — that is a deadline for the start, not a duration. Acceptance for the titanium alloys: **hydrogen < 100 ppm** by vacuum hot extraction (LECO or equivalent), one coupon per batch (tantalum is reported, not accepted, against a different figure — the paragraph on item 5 below). Please also quote, as a separate line, the same hydrogen analysis on one **etched-but-not-baked witness coupon from the same batch**, and state the furnace **base pressure** during the bake and, if you can measure it, the **residual-gas composition (hydrogen partial pressure)** — without both, a low hydrogen figure after the bake cannot tell us whether the bake removed anything. On the **CP-Ti Grade 4** coupons, quote as well an **XRD phase analysis for titanium hydride** on that same pair (etched-not-baked and etched-and-baked): hot extraction measures the bulk and cannot see a hydride layer at the surface. You may perform this step or accept it as a defined post-step. **If our hydrogen measurements show that this bake does not clear the hydride**, we may ask for the same bake at a higher temperature — still on the bare coupon: state the highest temperature and the vacuum your furnace holds for titanium, and whether you can report oxygen pick-up after such a bake.
- **Both analyses have to arrive with their own margin — our decision on this bake turns on a threshold, and a bare number cannot be read against one.** Whoever performs them, you, your subcontractor or a laboratory we appoint, please have the hydrogen report state four things. **(i) Which quantity is reported:** some instruments separate **diffusible, residual and total** hydrogen by stepped heating; our acceptance figure is the **total**, but where the instrument resolves the fractions we want all three, because the diffusible fraction is precisely what a vacuum bake is meant to remove. **(ii) The repeatability of the method at this level** — around 50 to 150 ppm on a titanium matrix — as a standard deviation, together with the laboratory's own expanded uncertainty at k = 2; not the instrument's catalogue range, because our threshold sits inside that range. **(iii) How many test portions per coupon** were run, and whether the figure is a mean with its scatter or a single determination. **(iv) The calibration** — the certified reference material used at this level and its matrix; **if that matrix is not titanium, please say so plainly.** For the **hydride XRD** we need the **detection limit for the phase** and the **diffraction geometry** (Bragg-Brentano or grazing incidence) together with the depth it actually probes: the layer we are looking for is 5 to 50 µm. **"Not detected" without a stated detection limit is not "absent".**
- **Tantalum and the coated coupons.** For **item 5 (bulk tantalum)**, apply the **dehydrogenation bake exactly as for the titanium alloys** — tantalum takes up hydrogen too, and every coupon's active face has to share one thermal history — but **do not HIP it**: at 920 °C the cycle is far too mild relative to tantalum's melting point to do its job. The 100 ppm hydrogen acceptance above is a titanium figure and **does not apply to item 5**; the chemistry we cite for tantalum (F560) holds hydrogen to **0.0015 wt % (15 ppm)** as its distributors reproduce the table — check it against your own copy of the standard and tell us if the current edition differs. For the tantalum coupons, **report** the post-bake hydrogen by the same hot extraction against that 15 ppm — a report, not an acceptance limit for this order — with the method's repeatability and calibration stated at that level on a tantalum matrix (the four points of the paragraph above), and tell us whether a 250 °C vacuum bake reaches it on tantalum in your experience or whether tantalum would need a higher-temperature vacuum degas, and at what temperature and vacuum; we are asking, not ordering it. For **its tantalum-coated alternative and for item 7 (gold-coated)**, the titanium substrate goes through the **full titanium route — HIP, surface activation and the bake — before coating**; any hydrogen-relief bake after coating is **yours to declare** (process, temperature, time), because a plating bath such as a nickel strike adds hydrogen of its own and a bake after coating acts on the whole coating/titanium stack. Quote the coating step as its own line. On the gold face, report the roughness factor (or double-layer capacitance) alongside the SEM — for information, not acceptance.
- **HIP witnesses — an optional line:** print two witnesses per titanium alloy in the same build as its coupons — one kept out of HIP, one sent through the HIP cycle with the coupons — and quote their printing; quote separately, per pair, a metallographic section of both with SEM and EDS (internal porosity: area fraction, largest pore, magnification and method; microstructure) and, if you can, oxygen and nitrogen in each. We may order the sections for a subset of alloys. This is a report, not an acceptance criterion: we set no porosity threshold. If the HIP is done elsewhere, the witness sent through the cycle travels with the coupons.
- **Prohibited on the active face:** ZnO-Ta (tantalum-doped zinc oxide) or any comparable antibacterial oxide coating — it blocks electron transfer. Also no oil-based or organic release residues; state your final cleaning protocol.
- **QC deliverables per batch:** SEM of the active face at **×5,000 and ×50,000** per alloy — if no nano-pores are visible at ×50,000 the etch is insufficient and is repeated — with **areal Sa (ISO 25178)** and Sv measurements, stating the instrument, evaluation area and filters · hydrogen content report (< 100 ppm for the titanium alloys; for tantalum the figure is reported against 15 ppm — item 5 above) · ICP-MS of the final rinse water, with **Al < 1 ppb** for the aluminium-bearing alloys · the rinse result for chloride, fluoride and sulphate, with the method and its detection limit · material CoC per powder lot (lot/heat number, O/N/H chemistry, virgin-to-reused powder ratio declared) · dimensional report against the supplied geometry.
  - **Oxygen, per powder lot:** state the oxygen limit you certify the lot to, the specification that limit comes from, and the measured value. Powder reuse picks oxygen up cycle by cycle, and an over-oxygenated lot loses ductility and fracture toughness while its certificate still reads titanium.

### Target performance envelope (informational, not acceptance)

Alloy strength and elastic modulus are background context for our own material comparison and follow from the standards cited above; they are **not acceptance criteria for this order**, and we are not asking you to guarantee mechanical properties or electrochemical behaviour. Please do not price a mechanical-property warranty into the quote. **Acceptance is exclusively the QC deliverables listed above.**

### What we ask you to provide

1. **Unit price per coupon per alloy** at 12 per alloy, plus the price at a higher count so we can see the break points.
2. **Setup, build-plate and tooling charges itemised separately** from unit price, and stated per alloy — we understand the number of alloys, not the number of coupons, drives cost, and want that visible in the quote.
3. **Price for HIP, etch activation, per-alloy etch development and the dehydrogenation bake as separate lines**, whether in-house or bought in.
4. **Lead time from purchase order to shipment**, stating explicitly whether HIP, activation, bake and QC are inside that lead time or added to it.
5. **MOQ** and whether a single-coupon first-article build is possible before the full batch, and at what price.
6. **Certifications, with certificate number, issuing body, scope and validity:** ISO 13485, AS9100, ISO 9001 — whichever you hold.
7. **Evidence of comparable work:** a dimensional or metrology report from a previous titanium job with a controlled surface finish (redacted is fine).
8. **Quote format:** currency, validity period, payment terms, and the technical point of contact.
9. **Electrical resistivity at 20 °C of each alloy as you supply it (µΩ·cm), with the datasheet it comes from or the measurement method.** We hold producer values for Ti-6Al-4V, CP-Ti Grade 4 and tantalum, a powder-metallurgy value only for Ti-6Al-7Nb, and none for Ti-13Nb-13Zr and Ti-15Zr; if you do not have a number, please say so — we will then measure it four-wire on a coupon rather than assume one.

### Confidentiality

The technical specification is openly published, so no confidentiality agreement is needed to quote it; we are happy to sign your standard mutual CDA covering commercial terms (prices, schedules, QC data) at the order stage.

### Commercial & logistics

- Ship-to: Ukraine (Cherkasy region); we can nominate an **EU forwarding address** instead if that simplifies export or customs — state your preference.
- Incoterms you quote on, HS code, and any export-control classification applicable to the parts or powder.
- **Packaging:** coupons individually pouched, active face protected, no contact with oils or adhesives.
- Tell us what you need from us to proceed (end-use statement, entity details, drawing format preferences).

### Attachments

Per-alloy **STL** plus a dimensioned **DXF** drawing with title block, one set per alloy, attached to this request. Surface acceptance is **areal Sa per ISO 25178** (0.5–5 µm) together with Sv (50–500 nm): state the instrument, evaluation area and filters you would use, and we will confirm them before the order.

---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 📤 Dispatch block (EN) — друга хвиля: лише друк, рядки CP-Ti і Ta (copy-region)

> **Репо-нота (в лист не йде).** ⚖️ founder 2026-11-17 — «(А) + (Б)» (купуємо доступне, сильного кандидата тримаємо дослідницьким шляхом), ланцюг обробки з окремими виконавцями (⚖️ вище в §1) і делеговано вибір адресатів; машина обрала: Amnovis — рядок CP-Ti; Croom Medical — обидва рядки; Thrustworks — рядок Ta (кандидати й звірка їхніх сторінок — §2 ⊕). Рядок, якого адресат не друкує, знімається при рендері (`--replace-line`), решта тексту однакова. Числа — з цього аркуша: Ø16 × 1 мм із вушком (§1), 12 на сплав (§1), аргон і кисень камери < 0.1 % (лист першої хвилі), стандарти — лише як хімія (§1). Розвилку «масивний Ta ⊥ Ta на Ti» лист лишає відкритою — питає обидві гілки ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24). Grade 4 — наш орієнтир, не вимога: друкований чистий титан часто міцніший за марку, тож судимо за виміряною міцністю друку. ⛔ До «так» founder-а на текст і «шли» не надсилати; у день відправки — адреса з контактної сторінки кожного й свіжі STL і креслення (`build` · `draw --vendor` для `ti_coin.cpti` / `ti_coin.ta`).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** RFQ — laser-PBF coupons Ø16 × 1 mm in commercially pure titanium and tantalum: printing and stress relief only (R&D batch)

Dear colleagues,

We are an R&D project in Ukraine developing a sensor node for forest monitoring: a titanium anchor sits in the trunk of a living tree. We are comparing candidate anchor alloys on small flat coupons, which we use as electrodes for electrochemical tests and for measuring the release of metal ions, and we are looking for a laser powder-bed fusion service to print them. This is a request for an indicative quotation, not yet an order.

**Scope: printing only.** We buy printing, a stress-relief heat treatment and support removal. Hot isostatic pressing, surface etching and a dehydrogenation bake are done afterwards by other contractors — one for all alloys of this programme, so that every coupon shares the same surface treatment. For the same reason the surface must stay as printed: please do not blast, polish or coat the coupons, and remove supports without abrasives.

**Items**

- **Geometry:** a flat disc Ø16 mm × 1 mm with a small tab for a clip; the attached STL and dimensioned drawing are the dimensional authority.
- **Quantity:** 12 coupons per alloy, each alloy identified separately and each coupon packed in its own bag.
- **Commercially pure titanium:** our reference is Grade 4 (ASTM F67, cited for chemistry only). If you print Grade 1, Grade 2 or your own commercially pure grade, quote that and state its printed yield and tensile strength.
- **Tantalum** (ASTM F560, cited for chemistry only): bulk tantalum coupons. If you can also deposit tantalum on a titanium coupon of the same geometry, please quote that as an alternative line.

**Please tell us**

1. The price per coupon at 12 per alloy and at a higher count, setup or build-plate charges per alloy, the lead time, and whether a single first-article coupon is possible first.
2. The powder you would use: designation, specification, particle size and lot traceability, and the oxygen content you certify the lot to, with the measured value.
3. The build conditions: argon atmosphere and the chamber oxygen level you hold, and the layer thickness of your qualified parameter set.
4. Your stress-relief regime for each alloy (temperature, time, atmosphere, cooling), or that you would not stress-relieve it.
5. Mechanical data you can share for these materials as printed or stress-relieved: yield and tensile strength, elongation.
6. Optionally, if you run hot isostatic pressing in-house, its price as a separate line; we may route it ourselves.
7. Whether you accept orders from Ukraine, and how you ship (courier, terms of delivery).
8. Your quality system (certificate and scope) and the documents you issue per lot.

The technical specification of our device is openly published, so no confidentiality agreement is needed to discuss it; we are happy to sign your standard agreement covering commercial terms.

`[sender's signature — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 📤 Letter block (EN) — (Б): Ti-6Al-7Nb, дослідницька група (copy-region)

> **Репо-нота (в лист не йде).** ⚖️ founder 2026-11-17 «(Б)»: сильного кандидата без ванадію тримаємо живим дослідницьким шляхом, бо комерційного бюро для Ti-6Al-7Nb не знайдено (§2 ⊕). Адресат — група Кошалінського технологічного університету (Польща), що 2024 року надрукувала Ti-6Al-7Nb на LPBF-машині з порошку, купленого в SLM Solutions (*Materials* 17:4604, 2024, DOI 10.3390/ma17184604, відкритий доступ — прочитано 2026-11-17); вроцлавська група друкувала цей сплав 2011–2015 років — давніше, тож другою. Імена й адреси — лише в журналі листів у памʼяті. Академічний жанр: без нагадування; оплата послугою або спільна публікація — на вибір групи. ⊕ «Шли» founder-а — **надіслано 2026-11-17 21:04** автору-кореспонденту (журнал листів).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Ti-6Al-7Nb by laser powder-bed fusion — a small batch of coupons for an R&D project in Ukraine

Dear colleagues,

We read your 2024 paper in Materials on as-built Ti-6Al-4V and Ti-6Al-7Nb produced by selective laser melting. We are an R&D project in Ukraine developing a sensor node for forest monitoring: a titanium anchor sits in the trunk of a living tree, and we are comparing vanadium-free alloys for it on small flat coupons, through electrochemical tests and the release of metal ions. Ti-6Al-7Nb is one of our candidates, and we have not found a commercial service that prints it.

Could your laboratory print a small batch for us: 12 flat discs Ø16 mm × 1 mm with a small tab, printed and stress-relieved only? Hot isostatic pressing, surface etching and baking are done elsewhere. We would pay for it as a service or, if you prefer, treat it as a collaboration — the comparison of the alloys could become a joint publication.

If this is possible, it would help to know the cost and time, the powder lot and its oxygen content, the parameters and stress-relief regime you would use, and any printed mechanical data you already have for this powder. We can send the STL and a drawing straight away.

`[sender's signature — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 📤 Reminder block (UA) — трьом бюро: купони й pre-qual одним листом

> **Репо-нота (у лист НЕ йде).** Одне нагадування на бюро, що покриває обидва листи від 5 листопада — цей лист купонів і DMLS pre-qual ([`vendor_templates`](vendor_templates.md)): відповіддю (Reply all) у треді pre-qual кожного з трьох бюро першої хвилі, без вкладень — архів листа купонів несе стару редакцію вушка, а перебудовані аркуші й STL їдуть лише з PO (§5a). Текст один на всіх; адреси й теми тредів — у корпусі памʼяті, не в дереві. **⚖️ founder 2026-11-15** — дослівно: «подання 1 - так на рекомендацію, так на текст». Подане в чаті, дослівно: **рекомендація** — «одне нагадування на бюро, що покриває обидва листи, — відповіддю (Reply all) у треді pre-qual, українською, без вкладень»; **підстава** — «тред pre-qual — надмножина адрес ([перелік адрес по бюро — у корпусі памʼяті]), і його тіло вже згадує запит на купони. Два нагадування одному бюро в один день читаються як розсилка»; **ціна** — «єдине нагадування за правилом витрачено на обидва листи одразу; далі по цих трьох — лише Tier-2»; **найслабша ланка** — «якщо бюро розглядає купони й pre-qual різними людьми, тред pre-qual може не дійти до того, хто рахує купони. Сайти бюро на реорганізацію чи зміну адрес я сьогодні не перечитував — це звірка дня відправки». Машинне, не частина присуду: день відправки й правило відліку — [`rfq_registry`](rfq_registry.md) §3 і ноги нагадування [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 (купони) · HW.1 (pre-qual); скринька на мить подання мовчала від усіх трьох бюро на обидва листи (перечитано 2026-11-15, разом зі спамом). ⊕ Машинне, після адверсара тексту: підстава «надмножина адрес» правдива для двох бюро з трьох — в одного перший лист купонів ішов ще й на адресу, якої тред pre-qual не несе (котру — корпус памʼяті), а видима адреса отримала обидва листи. ⚖️ founder 2026-11-15 — лишити як є («3. так» на рекомендацію; ціна, подана дослівно: «якщо купони рахує саме та перша скринька, нагадування її не дістане»). ⊕ Машинне, founder-у не подавалось: кандидати відповідей на найімовірніші прохання після «напишіть, надішлю» — файли купонів: переслати лист від 5 листопада як є, з рядком, що перебудовані аркуші й STL їдуть із замовленням (§5a); геометрія деталей анкера: приходить із запитом на конкретні деталі, як каже сам pre-qual, — кожна йде вендорові лише після окремого «так» founder-а. ⊕ Перед відправкою — звірка сайтів трьох бюро на реорганізацію й зміну адрес (найслабша ланка присуду вище). ⊕ ⚖️ founder 2026-11-15 — «2. так» на дві правки слів у схваленому тексті: «Пишу один раз, щоб перепитати» → «Пишу, щоб перепитати» («один раз» виносить назовні наше внутрішнє правило) і «тоді я не чекатиму відповіді» → «тоді я не чекатиму пропозиції» («ні» — це й є відповідь); текст нижче — уже з ними, а перше «так» вище стосувалось тексту до них. Підпис — `--signature "З повагою,|Олексій Лукін"`; треду-відповіді збирач потребує рядка теми — його дописують у скретч-копії (скіл `legal-business` §Доменні правила #13).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

Добрий день!

5 листопада я надіслав вам два запити: на партію титанових купонів Ø16 × 1 мм, надрукованих лазерним PBF, і — окремим листом — на попередню кваліфікацію для двох титанових деталей сенсорного анкера. Пишу, щоб перепитати, чи дійшли листи до людини, яка такі запити розглядає.

Якщо беретеся — буду вдячний за відповідь у зручному для вас обсязі: можна частинами, можна лише на один із двох запитів, можна лише по тих сплавах, які ви друкуєте. Якщо такі роботи не ваш профіль — коротке «ні» теж допоможе: тоді я не чекатиму пропозиції.

Якщо для оцінки чогось бракує з мого боку — напишіть, надішлю.

`[підпис відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 5a. Текст на мить замовлення (PO), не правка листа — ідентифікація купонів · водень рядка 2 · креслення й STL

> ⚖️ **РАТИФІКОВАНО founder 2026-10-18, за рекомендацією:** ідентифікатор купона `<сплав>-<серійний>` народжується на етикетці пакета у вендора — інструкцією в PO разом із +N купонів, а не правкою листа (форма — як ⚖️ 2026-10-15 про +N), тож сигнал 📬 і «слати» листа від 2026-10-15 цим не скидаються; ⛔ жодної мітки на самому купоні. **Ціна:** вендор може взяти за маркування окремо, і рядка в котируванні під нього не буде; ідентичність купона поза пакетом тримає дисципліна рук — наша й лабораторії. **Найслабша ланка:** постійної мітки на деталі немає, тож два Ti-сплави, переплутані ПІСЛЯ розпакування, вагою не розрізнити — підозрілий купон розсудить лише елементний аналіз (EDS/XRF: Al · V · Nb · Zr), якого як перевірки ідентичності при прийманні жоден наш лист не замовляє (EDS корозійного ТЗ на 12-му тижні — інший предмет, лише для корозійних купонів і запізно). Нога в трекері — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24, замовлення Stage 2.

**Навіщо.** Купонів близько дюжини на сплав (точне число — за числом реплік; Ti-6Al-4V — більше), сплавів шість, і на вигляд вони однакові. Вагою Ti-сплави не розрізнити: вирішальна пара — CP-Ti і Ti-6Al-7Nb з майже однаковою густиною (≈ 4.51 і 4.52 г/см³, довідкові значення, не з дерева), а креслення задає допуск лише діаметра (±0.1 мм — уже ±1.25 % маси), товщини не задає зовсім; вирізняються лише масивний Ta (у кілька разів важчий; Ta-покриття на Ti — ні) і Au (колір). Переплутаний пакет мовчки переносить результат на інший сплав, і ніщо далі по ланцюгу цього не побачить. А ідентифікатор купона далі по ланцюгу ВЖЕ вимагають усі вимірювальні листи: лабораторія — «coupon ID» у метаданих кожного запису ([`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md), EN «Data we need back» · UA ТЗ 1 п. 26), корозійний тест — акт із переліком ідентифікаторів і журнал по купону ([`anchor_accelerated_corrosion_rfq`](anchor_accelerated_corrosion_rfq.md) пп. 23 і 31). Народитись він може лише тут: лист друк-бюро просить тільки «individually pouched».

**Текст для PO — англійською, вставити дослівно:**

> **Identification.** Keep each alloy's coupons separate and traceable through every step — HIP, etching and baking included; if alloys share a run, state how you keep them apart. Pouch each coupon individually, as in our request, and label every pouch with: (1) the alloy designation as in the alloy table of our request — for a coated coupon, the coating and the base alloy (our drawings carry the same part name for every alloy); (2) a coupon serial within that alloy, one continuous sequence across this order and never reused — coupons of an alloy added on another line or build continue it; (3) the build number; (4) the powder lot. Keep the coupons of each alloy in a separate outer bag labelled with the alloy. In the certificate of conformance or the packing list, map each alloy's serial range to its build and powder lot. Do not laser-mark, engrave or ink the coupons themselves: they are corrosion and ion-release specimens, a mark changes the surface we measure, and the loop is our electrical contact.

**На нашому боці, при прийманні:** пакети звірити з CoC або пакувальним листом; ідентифікатор купона — `<сплав>-<серійний>` з етикетки; купон, вийнятий із пакета, іде в підписаний контейнер, ніколи в спільну тару; той самий ідентифікатор — в акт передачі лабораторії і в кожен рядок її звіту (листи лабораторій це вже просять — ↑).

**Водень рядка 2 (Ti-6Al-7Nb) — текст для PO, англійською, вставити дослівно** (⚖️ founder 2026-11-07, за рекомендацією; повна форма — [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) ⊕ «Водень Ti-6Al-7Nb»; надісланий лист купонів не правиться):

> **Hydrogen acceptance, item 2 (Ti-6Al-7Nb).** Our request accepts the titanium alloys at hydrogen < 100 ppm, but for item 2 the chemistry we cite (ASTM F1295) holds hydrogen to **0.009 wt % (90 ppm)** as its distributors reproduce the table — please check it against your own copy of the current edition and tell us before the etch campaign if it differs; until we answer, ≤ 90 ppm stands. Item 2 is therefore accepted at **≤ 90 ppm** total hydrogen as reported (not rounded to 0.009 wt %), whoever performs the analysis and with no product-analysis tolerance added, by the same method and report as for the other titanium alloys, which stay at < 100 ppm. Item 2 is baked exactly as the other titanium alloys — the same set point, time and vacuum within our request's window; do not change that without our written agreement. If you expect item 2 to miss 90 ppm under that bake, tell us before the etch campaign, with the change you would propose and its price. This replaces, for item 2, the hydrogen figure of our request and of the item-2 drawing sent with it; the revised drawing is attached.

**З цим PO — перебудовані аркуші й STL усіх замовлених сплавів:** `build` + `draw <cem> --vendor` з чистого дерева в день PO (рецепт пакета — скіл `picogk` tasks, «coupon dispatch pack»; #17) — вкладення листа купонів несуть стару редакцію вушка, а аркуш 7Nb ще й стару цифру водню (присуд — абзац «Drawings and STL files» нижче). ⛔ **Новому адресатові лист купонів іде з абзацом «Hydrogen acceptance, item 2» без останнього речення і без абзацу «Drawings and STL files» (замінювати в нього нічого — вкладення вже нові) поруч із §Processing** (або з правкою рядка приймання в copy-регіоні — це нова версія листа: діф і «так» founder-а перед відправкою) — інакше лист (< 100 ppm для всіх титанових) і перебудований аркуш 7Nb (≤ 90 ppm) розходяться в одних руках.

**Креслення й STL усіх сплавів — текст для PO, англійською, вставити дослівно** (⚖️ founder 2026-11-07, за рекомендацією, два присуди: PO везе перебудовані аркуші й STL ВСІХ замовлених сплавів; вушко — врівень із диском, дім геометрії й повна форма того присуду — [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)):

> **Drawings and STL files.** The attached drawings and STL files replace those sent with our request: the eyelet is now flush with the disc faces, and the drawings show and dimension it where the STL has it.

⚖️ **Чому всі аркуші, а не лише 7Nb.** **Підстава:** лист купонів називає STL і DXF разом «dimensional authority», а ці два документи розходились у положенні вушка на 0.6 мм (DXF, що пішли з листом, — ще й без бокової проєкції вушка); друк іде зі STL, тож контролер, що приймає за DXF, міг би відхилити правильно надруковану деталь. **Ціна:** нове речення в ратифікованому тексті PO і вся пачка аркушів замість одного. **Ціна «ні»:** перебудований аркуш 7Nb, який PO везе й так, показав би вушко на 9, а шість надісланих — на 9.6: розбіжність у руках одного бюро. **Найслабша ланка:** вушко без допуску й поза прийманням, тож розходження, найімовірніше, нічого б не зламало — але «найімовірніше» про документ, названий авторитетом, і є тим, від чого лік. Речення ратифіковано в редакції «The attached drawings replace those sent with our request: the eyelet is now drawn and dimensioned where the STL has it; the STL itself is unchanged.» з однією дозволеною зміною — сказати й про нові STL, якщо вушко стане врівень (стало, `01_01 §6.1`).

## 6. Cross-references

| Ресурс | Що бере |
|---|---|
| [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | V-конфлікт + 6-alloy bake-off (дім рішення) |
| [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | Stage-2 coin геометрія (Ø16, A=2см²) |
| [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | test-battery + acceptance-gates (дім) |
| [`ebfc_chem_rfq`](ebfc_chem_rfq.md) | парний chem-стек (Gen 2.0 функціоналізація) |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс + hard-constraint доми |
| `tools/cad/cem/ti_coin.*.json` | CEM-SSOT геометрії (шість сплавів + обовʼязковий Au-купон) · `build` → STL · `draw --vendor` → DXF вендору |
| `tools/in_silico` 51/50 | predicted V/Al-release + Lamé-E per alloy |
