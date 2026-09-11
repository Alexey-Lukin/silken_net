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
2. **CEM-SSOT + креслення:** геометрія — `tools/cad/cem/ti_coin.<alloy>.json`; STL+DXF регенерувати `dotnet run --project tools/cad/src/SilkenCad -- draw cem/ti_coin.<alloy>.json` (per-alloy title-block).
3. **Cost-driver = к-сть СПЛАВІВ** (порошок/SLM-сетап), не монет → ~3 репліки/сплав дешеві. Замовляти Tier-1 одразу; Tier-2 — паралельний vendor-hunt (не блокує TRL-4).
4. **Дерево-first:** down-select за CV/EIS + ICP-MS у **синтетичному ксилемному соку** (не PBS); Al³⁺ теж фітотоксичний → zero-Al кандидати дерево-чистіші ([`01_04 §4.2`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 1. Per-alloy spec (6 купонів — усі рівні до coin-даних)

| # | Сплав | Стандарт (AM ⊥ wrought) | V/Al wt% | E (ГПа) | Вісь bake-off | Tier |
|---|---|---|---|---|---|---|
| 1 | **Ti-6Al-4V** Gr5 | **F2924 — AM PBF** (єдиний AM-стандарт у таблиці) | 4 / 6 | 110 | control + друк-еталон (V+Al токсичні = нижня межа) | 1 |
| 2 | **Ti-6Al-7Nb** | F1295 / R56700 — **wrought**, лише склад | 0 / 6 | 103 | V-free (Al лишається) | 1 |
| 3 | **CP-Ti Gr4** | **F67 Gr4 / R50700** — wrought, лише склад | 0 / 0 | 104 | zero-tox, α-Ti (міцність ↓ ~480) | 1 |
| 4 | **β-Ti-13Nb-13Zr** | F1713 / R58130 — **wrought**, лише склад | 0 / 0 | 80 | low-E dual-win (ізоеластичність, HW.33) | 2 |
| 5 | **Tantalum** | F560 / R05200 — **wrought**, лише склад | 0 / 0 | 186 | benchmark біоінертності (⚠️ Ta₂O₅ DET-ризик; coin-only) | 2 |
| 6 | **Ti-15Zr** (Roxolid) | **стандарту НЕМАЄ** — датшит постачальника | 0 / 0 | 100 | high-strength V/Al-free (практичний анкер-кандидат) | 2 |

> 🔴 **Колонку звірено з ОБЛАСТЮ ЗАСТОСУВАННЯ кожного стандарту 2026-09-11 (HW.24), і два рядки називали не той предмет.** `F1581` на CP-Ti Gr4 **не є титановим стандартом узагалі** — це *Composition of Anorganic Bone for Surgical Implants*, кістковий апатит із нульовим вмістом Ti; нелегований титан специфікує **F67**, де Grade 4 = UNS R50700. `F2066-class` на Ti-15Zr є **Ti-15 МОЛІБДЕН** (UNS R58150) — збігається число, не елемент; стандарту ASTM чи ISO на бінарний Ti-Zr не існує ні для AM, ні для деформованого, бо Roxolid пропрієтарний Straumann. ⛔ Не відновлювати жодного з двох.
>
> ⚠️ **Друга вісь, і вона переживає обидва фікси: ми замовляємо ДРУК, а п'ять рядків із шести цитують специфікації ДЕФОРМОВАНОГО металу** (слово *Wrought* стоїть у власній назві F1295 · F67 · F1713 · F560). Перевірені AM-специфікації титану — `F2924` (Gr5) і `F3001` (ELI Gr23). Тому рядки 2–5 є **посиланням на СКЛАД**, ніколи на режим друку, а рядок 6 не має й того. Це рівно та процесна вісь, яку фікс `F136`→`F2924` 2026-09-08 лишив незвіреною первинкою; тепер вона звірена. ⛔ **А от чи ІСНУЄ AM-спека для 7Nb / CP-Ti / β-Ti — ми НЕ знаємо, і писати «немає» не можна:** `ASTM F3302` («Additive Manufacturing · Finished Part Properties · Titanium **Alloys** via Powder Bed Fusion») чинний, а його таблиця охоплених марок платна й нами не читана. Для Ta каталог F42 не перелічує жодної спеки матеріалу (єдина тугоплавка — `F3635`, Nb-Hf), але **перелік каталогу слабший за прочитану область застосування**. Тому в листі ми не стверджуємо відсутність, а ПИТАЄМО вендора (§Powder specification нижче). ⚖️ **Чи нарощувати замовлення до повного AM-стека** (склад по спеці вище · порошок ISO/ASTM 52907 · термообробка F3301 · приймання по свідках-купонах F3122) — **присуд закупівлі, не інженерії**: він піднімає ціну й може відсіяти дрібніші бюро, тож вирішує власник. Сьогодні документ просить менше: вендор сам оголошує, до чого друкує (§Powder specification нижче).

**+ Au-coated bracket (опц., 7-й купон — `cem/ti_coin.au.json`):** DET-electrical **стеля** (Au = найкращий electron transfer), пара до Ta біоінертної стелі → реальні сплави затиснуті між двома межами. Surface-only (дешевий Ti + thin Au), **НЕ** структурний/анкер-кандидат — лише control-точка bake-off.

**Спільна обробка (усі купони):** SLM/LPBF друк → **HIP** (920°C/100-150МПа Ar/2-4год, §4.B) → **EAAE dual-scale** активація грані (Sa 0.5-5µm + Sv 50-500nm, [`01_02 §1.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) → **dehydrogenation bake** (250°C/10⁻³mbar, <2год після rinse, H<100ppm, §4.B). ⚠️ **EAAE-протокол tuned під 4V, тож per-alloy etch-tuning потрібен КОЖНОМУ купону, крім самого 4V-контролю** (CRO; coin виявить — squeeze-data SEM Sa/Sv). 🔴 Тут стояв список із трьох сплавів, а CEM-нотатки несли список із трьох ІНШИХ; перетин був один. Обидва писались окремими комітами й жоден не виводився з підстави, яку це саме речення й називає: різна хімія травиться інакше, а «інша за 4V» є кожна з п'яти. **Ціна розбіжності не косметична — вісь травлення задає ECSA, тобто `j_max`, тобто головну метрику down-select'у: сплав, який CRO протравив 4V-протоколом, порівнюється з підтюненими сусідами й програє приладу, а не собі.**

**QC/acceptance (substrate):** **SEM грані ПЕРЕД відправкою — ×5 000 (Sa) і ×50 000 (Sv)**, обов'язок заводу за [`01_02 §1.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); не видно нанопор при ×50 000 ⇒ травлення недостатнє ⇒ повторити Крок 4 (⛔ ПЕРШИЙ кадр §1.5, ×500 по макропорах гіроїда, на плоскому купоні предмета не має) · LECO RH404 H<100ppm · ICP-MS промивної води (Al<1ppb для 4V/7Nb).

> ⚠️ **Просимо `Sa`, і саме тому це сказано окремо: канон називає цю вимогу ДВІЧІ й ПО-РІЗНОМУ.** Рядок приймання [`01_02 §1.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) вимагає **`Sa` 0.5–5 µm** — площинний (3D) параметр, зі СМУГОЮ й методом «SEM, профілометрія»; підпис кадру ×5 000 у [`01_02 §1.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) каже **`Ra` > 0.5 µm** — профільний (2D) параметр, одностороння підлога без стелі. Це різні прилади й різні числа на одній поверхні, тож «0.5» у двох рядках не є тим самим 0.5. **До вендора йде `Sa` зі смугою** (дім приймання), і в квотуванні просимо назвати МЕТОД, яким його отримано. Внутрішній присуд про параметр і метод — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.2; ⛔ не «уніфікувати» рядки редакцією: стилус фізично не заходить у порожнину гіроїда, тож вибір параметра тягне вибір приладу.

---

## 2. Sourcing tiers (заземлено)

**Tier-1 — одразу (control + V-free baseline → достатньо для TRL-4):**
- **Ti-6Al-4V** — UA **3D Metal Tech Київ** (Concept Laser M2, ISO 13485) / EU Protolabs.
- **CP-Ti Gr4** — medical AM-бюро (Eplus3D/MET3DP), дентал-стандарт.
- **Ti-6Al-7Nb** — ISO-13485 ортопед-стандарт (medical AM-бюро).

**Tier-2 — vendor-hunt паралельно (НЕ блокує):**
- **β-Ti-13Nb-13Zr** — research-grade порошок (гаряча LPBF-тема 2024; UTS~1020/yield~795 — ⚠️ літ-оцінка **розходиться** з дім-значенням `ALLOY_PROPERTIES` (`tools/in_silico/lib/constants.py`) `yield_MPa: 900`; жодне з двох не несе джерела — ймовірно as-built LPBF vs HIP'd, але це **не звірено**; для vendor-hunt-контексту не несуче, для acceptance — звірити ДО спека) → академ-колаборація (co-pub, Гусак/[`00_02`](../../00_02_Academic_Integration_and_IP.md)) або спец-порошок.
- **Ta** — LPBF **рідко** (вартість/відбивність/ризик принтеру) → **думка-outside workaround: Ta-coating на дешевому Ti-купоні** (біоінертна Ta-поверхня без bulk-Ta друку; EBFC бачить поверхню). Bulk-Ta — лише за EBM-Ta вендором.
- **Ti-15Zr** — Roxolid пропрієтарний (Straumann); AM-порошок research-grade → спец-постачальник або defer.

---

## 3. Test battery + acceptance (дім — `01_03 §3.5`)

На кожному функціоналізованому купоні (Gen 2.0 стек з [`ebfc_chem_rfq`](ebfc_chem_rfq.md)):
- **CV/EIS** у синт. ксилемному соку *Pinus sylvestris* pH 4.5-5.5 ([`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md)): j_max, k_s, DET-маржа.
- **ICP-MS** іон-release у сік: V≤0.02 / Al≤0.05 µg/cm² (4V/7Nb); Nb/Zr/Ta — informational (біоінертні). Predicted — `tools/in_silico` script 51.
- **30-day stability** ≥80% retention · **chloride** 0.25M ramp · **UCST** −10→+25°C recovery (квантитативні пороги — дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
- **Нано-індентор E** (post-coin) — ізоеластичність vs деревина 9-16 ГПа (β-Ti dual-win check); predicted — script 50.

**Electrochem-CRO:** **EL-CELL (DE)** — бере клієнтські купони + custom-electrolyte CV/EIS, будує протокол. Альт: ЧНУ/ЧМА co-pub ([`00_02 §1.2`](../../00_02_Academic_Integration_and_IP.md)).

---

## 4. Hard constraints (RFQ МУСИТЬ нести — дзеркало канону)

- **§4.B метал** ([`01_02 §1.6/§1.7/§1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): для bulk-структури анкера **SLM НЕ EBM** Zone 1 (порошок 15-45µm) — для плоского COIN менш критично, але грань потребує тієї ж EAAE-шорсткості · **HIP обов'язково** · **dehydrogenation bake** після EAAE · **ZnO-Ta ЗАБОРОНЕНО** на активній грані (блокує DET).
- **§4.E стерилізація** (якщо купон функціоналізований до тесту): **Co-60 НЕ EtO** · low-dose 15кГр для ферментів ([`01_04 §6`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 5. Dispatch checklist (👤)

- [ ] 👤 **Tier-1 RFQ** (4V/7Nb/CP-Ti) → 3D Metal Tech Київ / EU medical AM-бюро: 3 репліки×3 сплави, Ø16×1+вушко, HIP+EAAE+bake, SEM+ICP-MS acceptance. STL+DXF з `tools/cad` (`draw`).
- [ ] 👤 **Tier-2 vendor-hunt** (∥): β-Ti — академ-колаб/спец-порошок; Ta — coating-вендор (Ti+Ta-thin); Ti-15Zr — спец-постачальник.
- [ ] 👤 **Electrochem-CRO RFQ** → EL-CELL: CV/EIS+EIS у custom-electrolyte (синт. сік), 30-day, chloride, UCST, ICP-MS.
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
> Адресат — **друк-бюро (laser-PBF)**; електрохім-характеризація = окремий запит, у цьому листі її немає.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

RFQ — laser-PBF titanium coupons, Ø16 × 1 mm, six alloys, HIP + surface activation (R&D batch)

### Scope of request

We are an R&D group and need a small batch of flat metal coupons produced by laser powder-bed fusion in several titanium alloys (plus one refractory metal), post-processed and surface-activated as specified below. The coupons are used as working electrodes for electrochemical characterisation on our side, so surface condition and cleanliness are what we buy — mechanical performance is not an acceptance criterion for this order. Geometry is supplied by us as STL plus a dimensioned DXF drawing.

### Item specification

- **Geometry:** flat disc, **Ø16 mm × 1 mm** thick, with a small tab or edge through-hole for a potentiostat clip. The tab must not encroach on the active face. Per-alloy STL and dimensioned DXF are attached and are the **dimensional authority**.
- **Quantity: 3 replicates per alloy.** Please quote **each alloy as a separate line item** — we may award a subset depending on powder availability, and we may repeat the order at the same setup.
> ⚠️ **Рядок 1 ніс `ASTM F136` до 2026-09-08, і це була не косметика: F136 є специфікацією ELI (= Grade 23), а купон №1 є саме Gr5-контролем і друк-еталоном** — цитувати для нього implant-ELI-спеку означало замовити в вендора інший порошок. **Виправлено на `F2924`**, і це НЕ вибір, а виведення з нашого ж дерева: [`vendor_templates`](vendor_templates.md) незалежно парує «Grade 5 (F2924)» і називає F136 ELI-спекою, а [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) обрав V-free напрям **явно НЕ ELI**. Одної осі МАРКИ (ELI ⊥ Gr5) досить, і процесна вісь (AM ⊥ wrought) тоді лишилась нашим виведенням. ⛔ **І не звужувати вимогу до ELI взагалі** ([`02_06 §8.1.1`](../../02_06_Unit_Economics_and_BOM.md)) — фінальний сплав визначить bake-off. ✅ **Решту колонки звірено первинкою 2026-09-11** (області застосування самих стандартів; знахідки — у врізці під таблицею §1): F136 підтверджено ще й як **wrought**, тобто для друкованого Gr5-купона він хибний на ОБОХ осях. 🔑 **Урок, ширший за рядок: перший фікс закрив вісь, на якій його спіймали, і лишив сусідню відкритою в тому самому реченні** — коли правиш один бік пари, дочитай, чи другий не стоїть тут же непоміченим.

- **Powder specification:** for each alloy, state the powder specification you would actually use (designation, ASTM/ISO spec, grade, particle size distribution, lot traceability). If your available powder differs from the standard cited below, quote your equivalent and tell us what it is — do not substitute silently.

| # | Alloy | Standard cited | Qty |
|---|---|---|---|
| 1 | Ti-6Al-4V | ASTM F2924 — additive manufacturing, powder bed fusion | 3 |
| 2 | Ti-6Al-7Nb | ASTM F1295 (UNS R56700) — wrought spec, cited for CHEMISTRY only | 3 |
| 3 | CP-Ti Grade 4 | ASTM F67 Grade 4 (UNS R50700) — wrought spec, cited for CHEMISTRY only | 3 |
| 4 | Ti-13Nb-13Zr (β-Ti) | ASTM F1713 (UNS R58130) — wrought spec, cited for CHEMISTRY only | 3 |
| 5 | Tantalum | ASTM F560 (UNS R05200) — wrought spec, cited for CHEMISTRY only | 3 |
| 6 | Ti-15Zr | **no ASTM or ISO standard exists** for binary Ti-Zr — attach your powder datasheet | 3 |

> **The standard cited for rows 2–5 fixes the CHEMISTRY and nothing else** — each is a wrought-product specification and we are not buying wrought product. Row 1 is the only one where we cite an additive-manufacturing material spec (F2924). **We are NOT claiming that no AM standard covers rows 2–5** — we have not read the covered-grade table of ASTM F3302, so we are asking rather than asserting: tell us the specification you will actually print to (your own, the powder producer's, a company spec, or an AM standard we have missed), and if it differs from the chemistry cited, say how. Row 6 has no published standard at any process route we could find; attach the powder datasheet as the material reference.

- **Item 5 alternative:** if bulk tantalum is outside your process window, we will also consider a **tantalum-coated titanium coupon** of the same geometry (the coating only needs to cover the active face) — quote it as an alternative line item.
- **Optional item 7:** one coupon of the same geometry in titanium with a **thin gold coating on the active face** — surface treatment only, non-structural. Quote separately if you can supply or subcontract it.

### Processing / QC requirements

- **Process:** laser powder-bed fusion (SLM / DMLS / LPBF), powder 15–45 µm. If you propose a different powder-bed route for these flat parts, flag it explicitly in the quote rather than assuming it is equivalent.
- **HIP — mandatory:** 920 °C, 100–150 MPa argon, 2–4 h. In-house or through a qualified partner; if a partner, name them and include the cost and time in your quote.
- **Surface activation of the active face:** dual-scale etch producing **Sa 0.5–5 µm** with sub-micron structure **Sv 50–500 nm**, verified by SEM. Our etch parameters were developed on Ti-6Al-4V and the other alloys will respond differently — we expect **per-alloy etch parameter development** and ask you to quote it as a separate development line item, reporting the achieved Sa/Sv per alloy.
- **Dehydrogenation bake after the etch rinse — two independent parameters, both mandatory:** (a) bake **2–4 h** (3 h nominal) at **250 °C ± 25 °C under 10⁻³ mbar**; (b) the bake must **start no later than 2 h after the rinse** — that is a deadline for the start, not a duration. Acceptance: **hydrogen < 100 ppm** by vacuum hot extraction (LECO or equivalent), one coupon per batch. You may perform this step or accept it as a defined post-step.
- **Prohibited on the active face:** ZnO-Ta (tantalum-doped zinc oxide) or any comparable antibacterial oxide coating — it blocks electron transfer. Also no oil-based or organic release residues; state your final cleaning protocol.
- **QC deliverables per batch:** SEM of the active face with Sa/Sv measurements per alloy · hydrogen content report (< 100 ppm) · ICP-MS of the final rinse water, with **Al < 1 ppb** for the aluminium-bearing alloys · material CoC per powder lot (lot/heat number, O/N/H chemistry, virgin-to-reused powder ratio declared) · dimensional report against the supplied geometry.

### Target performance envelope (informational, not acceptance)

Alloy strength and elastic modulus are background context for our own material comparison and follow from the standards cited above; they are **not acceptance criteria for this order**, and we are not asking you to guarantee mechanical properties or electrochemical behaviour. Please do not price a mechanical-property warranty into the quote. **Acceptance is exclusively the QC deliverables listed above.**

### What we ask you to provide

1. **Unit price per coupon per alloy** at 3 replicates, plus the price at a higher replicate count so we can see the break points.
2. **Setup, build-plate and tooling charges itemised separately** from unit price, and stated per alloy — we understand the number of alloys, not the number of coupons, drives cost, and want that visible in the quote.
3. **Price for HIP, etch activation, per-alloy etch development and the dehydrogenation bake as separate lines**, whether in-house or bought in.
4. **Lead time from purchase order to shipment**, stating explicitly whether HIP, activation, bake and QC are inside that lead time or added to it.
5. **MOQ** and whether a single-coupon first-article build is possible before the full batch, and at what price.
6. **Certifications, with certificate number, issuing body, scope and validity:** ISO 13485, AS9100, ISO 9001 — whichever you hold.
7. **Evidence of comparable work:** a dimensional or metrology report from a previous titanium job with a controlled surface finish (redacted is fine).
8. **Quote format:** currency, validity period, payment terms, and the technical point of contact.

### Commercial & logistics

- Ship-to: Ukraine (Cherkasy region); we can nominate an **EU forwarding address** instead if that simplifies export or customs — state your preference.
- Incoterms you quote on, HS code, and any export-control classification applicable to the parts or powder.
- **Packaging:** coupons individually pouched, active face protected, no contact with oils or adhesives.
- Tell us what you need from us to proceed (end-use statement, entity details, drawing format preferences).

### Attachments

Per-alloy **STL** plus a dimensioned **DXF** drawing with title block, one set per alloy, attached to this request. On request we also supply the surface-metrology definition we use for acceptance (how Sa/Sv are measured and over what area).

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
