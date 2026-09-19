# Anchor Alloy — Ti-coupon RFQ (Stage-2 6-alloy bake-off, AM / CRO-ready)

> **Що це:** RFQ-аркуш для **substrate-половини** Stage-2 coin: 6 плоских Ti-купонів Ø16×1 мм у різних сплавах →
> емпіричний **down-select сплаву Zone 1** ДО committed 100-партії. Парний chem-стек (фермент/ZIF/мембрана) — окремий
> аркуш [`ebfc_chem_rfq`](ebfc_chem_rfq.md); тести — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).
> **Статус:** 🟡 робочий артефакт (не канон). **Усі числа — дзеркало канону**: сплави/властивості → [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) + `tools/in_silico/lib/constants.py ALLOY_PROPERTIES`; геометрія → [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md); **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (Анкер-сплав рядок · hard-constraint доми §4.B/§4.E).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — specs відкриті; CDA = стандартні комерц-умови.

---

## 0. Як користуватись + cover-note

1. Купон = плоский диск **Ø16×1 мм**, 1 грань = π·8² = **2.01 см² ≈ A_electrode** ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)); `j` нормують на **проєкційну** площу. **«Вушко»** (отвір/виступ на краю) під потенціостат-кліпсу, не псуючи активну грань.
2. **CEM-SSOT + креслення:** геометрія — `tools/cad/cem/ti_coin.<alloy>.json`; STL — `dotnet run --project tools/cad/src/SilkenCad -- build cem/ti_coin.<alloy>.json`, DXF (+SVG) — той самий виклик із `draw` (per-alloy title-block). ⛔ Перебудовувати В ДЕНЬ відправки й звіряти bbox STL із маніфестом: `tools/cad/out/` під `.gitignore`, і копію, що їде вендору, не стереже жоден гейт (скіл `picogk` #17).
3. **Cost-driver = к-сть СПЛАВІВ** (порошок/SLM-сетап), не монет → ~3 репліки/сплав дешеві. Замовляти Tier-1 одразу; Tier-2 — паралельний vendor-hunt (не блокує TRL-4).
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
> ⚠️ **Друга вісь, і вона переживає обидва фікси: ми замовляємо ДРУК, а п'ять рядків із шести цитують специфікації ДЕФОРМОВАНОГО металу** (слово *Wrought* стоїть у власній назві F1295 · F67 · F1713 · F560). Перевірені AM-специфікації титану — `F2924` (Gr5) і `F3001` (ELI Gr23). Тому рядки 2–5 є **посиланням на СКЛАД**, ніколи на режим друку, а рядок 6 не має й того. Це рівно та процесна вісь, яку фікс `F136`→`F2924` 2026-09-08 лишив незвіреною первинкою; тепер вона звірена. ⛔ **А от чи ІСНУЄ AM-спека для 7Nb / CP-Ti / β-Ti — ми НЕ знаємо, і писати «немає» не можна:** `ASTM F3302` («Additive Manufacturing · Finished Part Properties · Titanium **Alloys** via Powder Bed Fusion») чинний, а його таблиця охоплених марок платна й нами не читана. Для Ta каталог F42 не перелічує жодної спеки матеріалу (єдина тугоплавка — `F3635`, Nb-Hf), але **перелік каталогу слабший за прочитану область застосування**. Тому в листі ми не стверджуємо відсутність, а ПИТАЄМО вендора (§Powder specification нижче). ⚖️ **AM-стек купонів — мінімальний (ратифіковано founder 2026-09-17):** вендор сам декларує порошок і процес, до яких друкує (§Powder specification нижче). Повний стек (склад по спеці вище · порошок ISO/ASTM 52907 · **процес і машина ISO/ASTM 52904** · термообробка F3301 · приймання по свідках-купонах F3122) іде в part-RFQ Stage 3 ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.1, нога «текст part-RFQ»). **Підстава:** це присуд закупівлі, не інженерії, а на Stage 2 потрібні купони, не кваліфікація виробництва; повний стек піднімає ціну й відсіює дрібніші бюро. **Ціна:** частина різниці між сплавами може йти від процесу вендора, а не від сплаву.
>
> ⛔ **Не звужувати вимогу до ELI** ([`02_06 §8.1.1`](../../02_06_Unit_Economics_and_BOM.md)): купон №1 є Gr5-контролем і друк-еталоном, тож ELI-спека (`F136` — до того ж wrought, тобто хибна для друкованого купона на обох осях) замовила б у вендора інший порошок; фінальний сплав визначає bake-off, не лист.

**+ Au-coated bracket (7-й купон, обовʼязковий — `cem/ti_coin.au.json`):** DET-electrical **стеля** (Au = найкращий electron transfer), пара до Ta біоінертної стелі → реальні сплави затиснуті між двома межами. Surface-only (дешевий Ti + thin Au), **НЕ** структурний/анкер-кандидат. ⚖️ **Не опційний з 2026-09-18:** несе катод дня 0 — межу осі «оксид ↔ DET» ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)) — і є входом гілок (1)/(2) ратифікованого правила вибору катодного важеля ([`01_03 §3.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): без нього «катод на Au ≈ / помітно кращий за катод на Ti» нічим виміряти. На число 4V («at 6 and at 13») не впливає — це окремий купон.

**Спільна обробка (усі купони):** SLM/LPBF друк → **HIP** (920°C/100-150МПа Ar/2-4год, §4.B — ⚠️ це режим **Ti-6Al-4V**; для решти Ti-сплавів режим не зафіксовано й EN-лист його ПИТАЄ, бо β-трансус Ti-13Nb-13Zr ≈ 735 °C лежить нижче обох температур, а один цикл на всі сплави є відкритим ⚖️ [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24, «CEM-сироти» п. (1)) → **EAAE dual-scale** активація грані (Sa 0.5-5µm + Sv 50-500nm, [`01_02 §1.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) → **dehydrogenation bake** (250°C/10⁻³mbar, <2год після rinse, H<100ppm, §4.B). ✅ **Ta і Au розсуджено (⚖️ founder 2026-09-17, дім [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) Failure Mode C):** Ta (п.5) — той самий bake, **HIP — N/A** (920 °C = 0.36 T_m Ta); Au-купон (п.7) і Ta-покриття — Ti-підкладка проходить увесь маршрут Ti-купонів **до** покриття, bake після покриття декларує вендор, roughness factor Au — лише звіт. ⚠️ **EAAE-протокол написаний під 4V і не проганявся жодного разу (фізичної партії немає), тож per-alloy etch-tuning потрібен КОЖНОМУ купону, крім самого 4V-контролю** (CRO; coin виявить — squeeze-data SEM Sa/Sv). 🔴 Тут стояв список із трьох сплавів, а CEM-нотатки несли список із трьох ІНШИХ; перетин був один. Обидва писались окремими комітами й жоден не виводився з підстави, яку це саме речення й називає: різна хімія травиться інакше, а «інша за 4V» є кожна з п'яти. **Ціна розбіжності не косметична — вісь травлення задає ECSA, тобто `j_max`, тобто головну метрику down-select'у: сплав, який CRO протравив 4V-протоколом, порівнюється з підтюненими сусідами й програє приладу, а не собі.**

**QC/acceptance (substrate):** **SEM грані ПЕРЕД відправкою — ×5 000 (Sa) і ×50 000 (Sv)**, обов'язок заводу за [`01_02 §1.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); не видно нанопор при ×50 000 ⇒ травлення недостатнє ⇒ повторити Крок 4 (⛔ ПЕРШИЙ кадр §1.5, ×500 по макропорах гіроїда, на плоскому купоні предмета не має) · LECO RH404 H<100ppm · ICP-MS промивної води (Al<1ppb для 4V/7Nb).

> ⚠️ **Кисень — ліміт питаємо, числа не цитуємо.** AM-спеки несуть стелю O: `F2924` (Gr5) **0.20 wt%**, `F3001` (ELI Gr23) **0.13 wt%** — обидва числа з ВТОРИННИХ джерел (первинні ASTM платні й не читані), тому EN-лист просить вендора назвати ліміт, до якого він сертифікує партію порошку, його спеку й виміряне значення, а не наводить їх. Причина вимоги: повторне використання порошку набирає кисень цикл за циклом, і перекиснена партія втрачає пластичність і в'язкість руйнування, лишаючись «титаном» на CoC.

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
- **β-Ti-13Nb-13Zr** — research-grade порошок (гаряча LPBF-тема 2024; UTS~1020/yield~795 — ⚠️ літ-оцінка **розходиться** з дім-значенням `ALLOY_PROPERTIES` (`tools/in_silico/lib/constants.py`) `yield_MPa: 900`; жодне з двох не несе джерела — ймовірно as-built LPBF vs HIP'd, але це **не звірено**; для vendor-hunt-контексту не несуче, для acceptance — звірити ДО спека) → академ-колаборація (co-pub, Гусак/[`00_02`](../../00_02_Academic_Integration_and_IP.md)) або спец-порошок.
- **Ta** — LPBF **рідко** (вартість/відбивність/ризик принтеру) → **думка-outside workaround: Ta-coating на дешевому Ti-купоні** (біоінертна Ta-поверхня без bulk-Ta друку; EBFC бачить поверхню). ⚠️ **«Bulk-Ta лише за EBM-вендором» ЗНЯТО 2026-09-11:** LPBF-Ta існує промислово (вимір `00_07` HW.24), тож маршрут не обмежений EBM; відкритим лишається інше — **bulk-Ta ⊥ Ta-покриття на Ti**, і це присуд, бо друга гілка перетворює купон на підкладку з покриттям (патерн `.au`) і тягне за собою відпал підкладки.
- **Ti-15Zr** — Roxolid пропрієтарний (Straumann); AM-порошок research-grade → спец-постачальник або defer.

---

## 3. Test battery + acceptance (дім — `01_03 §3.5`)

На кожному функціоналізованому купоні (Gen 2.0 стек з [`ebfc_chem_rfq`](ebfc_chem_rfq.md)):
- **CV/EIS** у синт. ксилемному соку *Pinus sylvestris* pH 5.75 (рецептура й pH — [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): j_max, k_s, DET-маржа.
- **Бічна ICP-MS-серія:** по три **непокриті** купони на сплав (та сама обробка, без стеку) — занурення при pH 4.5 лише під ICP-MS ([`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), ⚖️ 2026-09-17); звідси 6 купонів на сплав у замовленні.
- **ICP-MS** іон-release у сік: V≤0.02 / Al≤0.05 µg/cm² (4V/7Nb); Nb/Zr/Ta — informational (біоінертні). Predicted — `tools/in_silico` script 51.
- **30-day stability** ≥80% retention · **chloride** 0.25M ramp · **UCST** −10→+25°C recovery (квантитативні пороги — дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
- **Нано-індентор E** (post-coin) — модуль СУЦІЛЬНОГО сплаву купона (β-Ti dual-win check). ⛔ **Це НЕ перевірка жорсткості ҐРАТКИ, і плутати два виміри дорого:** апарентна жорсткість є властивістю ґратки, купон її не має, а порівнювати треба з ПОПЕРЕЧНИМ модулем деревини `E_R`/`E_T` ≈ 0.5–1.5 ГПа — анкер сидить поперек стовбура ([`01_01 §5.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)). Поздовжні 9–16 ГПа, що стояли тут, є ~вдесятеро завищеною ціллю. Апарентну жорсткість самої ґратки міряє voxel-FE (`dotnet run -- fea`, дім числа — [`01_01 §5.2`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)); фізичний метод для неї — ISO 13314 на друкованому зразку, не нано-індентор на купоні.

- **Чому 4V у листі «at 6 and at 13»** (⚖️ розкладка founder 2026-09-18, дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): 4V єдиний несе пʼять електродних плечей — аноди · катоди з нанозимом · контроль без нанозиму · свіжі катоди під хлорид D · свіжі аноди з мембраною під E — і жодне порівняльне плече не стоїть на одній репліці: 5 × 2 + 3 непокриті = 13. Це точка ціни, не замовлення: число реплік фіксується після цін лабораторії, а решта сплавів поки лишається на 6.

**Electrochem-CRO:** кандидат **EL-CELL (DE)** — ⚠️ не підтверджений: публічна сторінка його лабораторії описує тестування Li-ion батарей, а ICP-MS і ISO/IEC 17025 не згадує (звірено 2026-09-13); лист лабораторії — [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md). Альт: ЧНУ/ЧМА co-pub ([`00_02 §1.2`](../../00_02_Academic_Integration_and_IP.md)).

---

## 4. Hard constraints (RFQ МУСИТЬ нести — дзеркало канону)

- **§4.B метал** ([`01_02 §1.6/§1.7/§1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): для bulk-структури анкера **SLM НЕ EBM** Zone 1 (порошок 15-45µm) — для плоского COIN менш критично, але грань потребує тієї ж EAAE-шорсткості · **HIP обов'язково** · **dehydrogenation bake** після EAAE (обидва — для Ti-сплавів; Ta — bake так, HIP N/A; Au/Ta-покриття — маршрут Ti до покриття, [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) · **ZnO-Ta ЗАБОРОНЕНО** на активній грані (блокує DET).
- **§4.E стерилізація** (якщо купон функціоналізований до тесту): **Co-60 НЕ EtO** · low-dose 15кГр для ферментів ([`01_04 §6`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 5. Dispatch checklist (👤)

- [ ] 👤 **Tier-1 RFQ** (4V/7Nb/CP-Ti) → 3D Metal Tech Київ · ALT print (АЛТ України) · Velta Medical (Дніпро) — усі три звірено desk-пошуком 2026-09-17, [`ua_vendor_map §1`](ua_vendor_map.md); ⚠️ HIP в Україні як комерційної послуги «принесіть деталь» немає, але МАРШРУТ є ([`ua_vendor_map §2`](ua_vendor_map.md)): Інститут магнетизму (Київ, камера Ø32 приймає всю нашу номенклатуру) і Мотор Січ (Запоріжжя, наскрізний «друк → ГІП 1160 °C/160 МПа → вакуумна ТО 980 °C» на НАДРУКОВАНИХ зразках) — писати їм НАПРЯМУ окремим листом ([`anchor_hip_rfq`](anchor_hip_rfq.md) — ТЗ українською, написано 2026-09-18), а не питати друк-бюро «хто ваш HIP-партнер» / EU medical AM-бюро: (3 репліки + 3 непокриті під ICP-MS)×3 сплави, Ø16×1+вушко, HIP+EAAE+bake, SEM+ICP-MS acceptance. STL+DXF з `tools/cad` (`draw`).
- [ ] 👤 **Tier-2 vendor-hunt** (∥): β-Ti — академ-колаб/спец-порошок; Ta — спершу масивний (EN-лист, пункт 5), Ta-покриття на Ti — лише альтернативним рядком того самого листа (bulk ⊥ покриття — відкритий ⚖️ [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24, тримає відповідь вендора); Ti-15Zr — спец-постачальник.
- [ ] 👤 **Electrochem-CRO RFQ** — текст і чекліст відправки живуть в [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) (CV/EIS у синтетичному соку · 30-day · chloride · UCST · ICP-MS); адресат TBD — EL-CELL не підтверджений (↑).
- [ ] 👤 Синт. сік — біо-хаб ЧНУ Спрягайло (рецептура, [`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md)).
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
- **Quantity: 6 per alloy** — 3 for electrode testing and 3 for an uncoated ion-release series, all processed identically. **Ti-6Al-4V will be ordered in a larger count than the rest**: it alone carries the cathode comparison and two further series on fresh coupons, so please quote it at 6 and at 13. Please quote **each alloy as a separate line item** — we may award a subset depending on powder availability, and we may repeat the order at the same setup.

- **Powder specification:** for each alloy, state the powder specification you would actually use (designation, ASTM/ISO spec, grade, particle size distribution, lot traceability). If your available powder differs from the standard cited below, quote your equivalent and tell us what it is — do not substitute silently.

| # | Alloy | Standard cited | Qty |
|---|---|---|---|
| 1 | Ti-6Al-4V | ASTM F2924 — additive manufacturing, powder bed fusion | 6 |
| 2 | Ti-6Al-7Nb | ASTM F1295 (UNS R56700) — wrought spec, cited for CHEMISTRY only | 6 |
| 3 | CP-Ti Grade 4 | ASTM F67 Grade 4 (UNS R50700) — wrought spec, cited for CHEMISTRY only | 6 |
| 4 | Ti-13Nb-13Zr (β-Ti) | ASTM F1713 (UNS R58130) — wrought spec, cited for CHEMISTRY only | 6 |
| 5 | Tantalum | ASTM F560 (UNS R05200) — wrought spec, cited for CHEMISTRY only | 6 |
| 6 | Ti-15Zr | **no ASTM or ISO standard exists** for binary Ti-Zr — attach your powder datasheet | 6 |

> **The standard cited for rows 2–5 fixes the CHEMISTRY and nothing else** — each is a wrought-product specification and we are not buying wrought product. Row 1 is the only one where we cite an additive-manufacturing material spec (F2924). **We are NOT claiming that no AM standard covers rows 2–5** — we have not read the covered-grade table of ASTM F3302, so we are asking rather than asserting: tell us the specification you will actually print to (your own, the powder producer's, a company spec, or an AM standard we have missed), and if it differs from the chemistry cited, say how. Row 6 has no published standard at any process route we could find; attach the powder datasheet as the material reference.

- **Item 5 alternative:** if bulk tantalum is outside your process window, we will also consider a **tantalum-coated titanium coupon** of the same geometry (the coating only needs to cover the active face) — quote it as an alternative line item.
- **Item 7 (required):** one coupon of the same geometry in titanium with a **thin gold coating on the active face** — surface treatment only, non-structural. Quote it as a separate line, whether you supply it or subcontract it; if you can do neither, say so.

### Processing / QC requirements

- **Process:** laser powder-bed fusion (SLM / DMLS / LPBF), powder 15–45 µm. If you propose a different powder-bed route for these flat parts, flag it explicitly in the quote rather than assuming it is equivalent.
  - **Build atmosphere and layer:** build under **argon** with **chamber oxygen below 0.1 %** for the whole build, and state the oxygen level you actually hold and how it is logged. Our reference layer thickness is **30 µm** — state the layer of your qualified parameter set for each alloy rather than re-qualifying to our number.
- **HIP — mandatory for the titanium alloys:** our cycle is **920 °C, 100–150 MPa argon, 2–4 h**. In-house or through a qualified partner; if a partner, name them and include the cost and time in your quote. **We may also route HIP ourselves to a HIP provider, so please quote the coupons without HIP as a separate line as well, and say whether you would take them back after an external HIP for the activation and bake that follow.**
  - **That cycle is our specification for Ti-6Al-4V, set below that alloy's β-transus; we have not fixed cycles for the other titanium alloys of this order.** For each of them, tell us where the cycle sits relative to that alloy's β-transus and whether you would run a different one — we are asking, not assuming, because a cycle above the transus changes the microstructure we are comparing.
  - **For the Ti-6Al-4V coupons, HIP is followed by a vacuum anneal at 800 °C for 2 h** — quote it on the HIP line or name who performs it. **State the cooling rate or cooling profile of your HIP cycle:** we specify it only as controlled, because the cycle exists to remove the as-built martensite and an uncontrolled cool can bring it back; we hold no number for it, so give yours.
  - **For the other titanium alloys we specify no post-HIP anneal:** for each, state whether you would anneal after HIP and at what temperature, time and cooling — or confirm that none is needed. Do not apply the Ti-6Al-4V anneal to them without our written agreement.
- **Surface activation of the active face:** dual-scale etch producing **areal Sa 0.5–5 µm (ISO 25178)** with sub-micron structure **Sv 50–500 nm**, verified by SEM and profilometry. We hold no validated etch for any of these alloys — our reference protocol is written for Ti-6Al-4V and has not yet been run — and the other alloys will respond differently, so we expect **per-alloy etch parameter development** and ask you to quote it as a separate development line item. **Declare the parameters you use per alloy** (etchant composition and concentrations, time, temperature, agitation) — acceptance is the achieved Sa/Sv, not a recipe. **All coupons of this order, every alloy and the uncoated series included, are etched by a single etcher in a single campaign**; if you subcontract the etch, one subcontractor does all of them.
- **Dehydrogenation bake after the etch rinse — two independent parameters, both mandatory:** (a) bake **2–4 h** (3 h nominal) at **250 °C ± 25 °C under 10⁻³ mbar**; (b) the bake must **start no later than 2 h after the rinse** — that is a deadline for the start, not a duration. Acceptance: **hydrogen < 100 ppm** by vacuum hot extraction (LECO or equivalent), one coupon per batch. Please also quote, as a separate line, the same hydrogen analysis on one **etched-but-not-baked witness coupon from the same batch**, and state the furnace **base pressure** during the bake and, if you can measure it, the **residual-gas composition (hydrogen partial pressure)** — without both, a low hydrogen figure after the bake cannot tell us whether the bake removed anything. On the **CP-Ti Grade 4** coupons, quote as well an **XRD phase analysis for titanium hydride** on that same pair (etched-not-baked and etched-and-baked): hot extraction measures the bulk and cannot see a hydride layer at the surface. You may perform this step or accept it as a defined post-step. **If our hydrogen measurements show that this bake does not clear the hydride**, we may ask for the same bake at a higher temperature — still on the bare coupon: state the highest temperature and the vacuum your furnace holds for titanium, and whether you can report oxygen pick-up after such a bake.
- **Tantalum and the coated coupons.** For **item 5 (bulk tantalum)**, apply the **dehydrogenation bake exactly as for the titanium alloys** — tantalum takes up hydrogen too, and every coupon's active face has to share one thermal history — but **do not HIP it**: at 920 °C the cycle is far too mild relative to tantalum's melting point to do its job. For **its tantalum-coated alternative and for item 7 (gold-coated)**, the titanium substrate goes through the **full titanium route — HIP, surface activation and the bake — before coating**; any hydrogen-relief bake after coating is **yours to declare** (process, temperature, time), because a plating bath such as a nickel strike adds hydrogen of its own and a bake after coating acts on the whole coating/titanium stack. Quote the coating step as its own line. On the gold face, report the roughness factor (or double-layer capacitance) alongside the SEM — for information, not acceptance.
- **Prohibited on the active face:** ZnO-Ta (tantalum-doped zinc oxide) or any comparable antibacterial oxide coating — it blocks electron transfer. Also no oil-based or organic release residues; state your final cleaning protocol.
- **QC deliverables per batch:** SEM of the active face at **×5,000 and ×50,000** per alloy — if no nano-pores are visible at ×50,000 the etch is insufficient and is repeated — with **areal Sa (ISO 25178)** and Sv measurements, stating the instrument, evaluation area and filters · hydrogen content report (< 100 ppm) · ICP-MS of the final rinse water, with **Al < 1 ppb** for the aluminium-bearing alloys · material CoC per powder lot (lot/heat number, O/N/H chemistry, virgin-to-reused powder ratio declared) · dimensional report against the supplied geometry.
  - **Oxygen, per powder lot:** state the oxygen limit you certify the lot to, the specification that limit comes from, and the measured value. Powder reuse picks oxygen up cycle by cycle, and an over-oxygenated lot loses ductility and fracture toughness while its certificate still reads titanium.

### Target performance envelope (informational, not acceptance)

Alloy strength and elastic modulus are background context for our own material comparison and follow from the standards cited above; they are **not acceptance criteria for this order**, and we are not asking you to guarantee mechanical properties or electrochemical behaviour. Please do not price a mechanical-property warranty into the quote. **Acceptance is exclusively the QC deliverables listed above.**

### What we ask you to provide

1. **Unit price per coupon per alloy** at 6 per alloy, plus the price at a higher count so we can see the break points.
2. **Setup, build-plate and tooling charges itemised separately** from unit price, and stated per alloy — we understand the number of alloys, not the number of coupons, drives cost, and want that visible in the quote.
3. **Price for HIP, etch activation, per-alloy etch development and the dehydrogenation bake as separate lines**, whether in-house or bought in.
4. **Lead time from purchase order to shipment**, stating explicitly whether HIP, activation, bake and QC are inside that lead time or added to it.
5. **MOQ** and whether a single-coupon first-article build is possible before the full batch, and at what price.
6. **Certifications, with certificate number, issuing body, scope and validity:** ISO 13485, AS9100, ISO 9001 — whichever you hold.
7. **Evidence of comparable work:** a dimensional or metrology report from a previous titanium job with a controlled surface finish (redacted is fine).
8. **Quote format:** currency, validity period, payment terms, and the technical point of contact.

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

## 6. Cross-references

| Ресурс | Що бере |
|---|---|
| [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | V-конфлікт + 6-alloy bake-off (дім рішення) |
| [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | Stage-2 coin геометрія (Ø16, A=2см²) |
| [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | test-battery + acceptance-gates (дім) |
| [`ebfc_chem_rfq`](ebfc_chem_rfq.md) | парний chem-стек (Gen 2.0 функціоналізація) |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс + hard-constraint доми |
| `tools/cad/cem/ti_coin.*.json` | CEM-SSOT геометрії (6 сплав-варіантів) · `draw` → STL+DXF |
| `tools/in_silico` 51/50 | predicted V/Al-release + Lamé-E per alloy |
