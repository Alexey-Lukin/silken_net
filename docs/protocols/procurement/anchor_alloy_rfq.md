# Anchor Alloy — Ti-coupon RFQ (Stage-2 6-alloy bake-off, AM / CRO-ready)

> **Що це:** RFQ-аркуш для **substrate-половини** Stage-2 coin: 6 плоских Ti-купонів Ø16×1 мм у різних сплавах →
> емпіричний **down-select сплаву Zone 1** ДО committed 100-партії. Парний chem-стек (фермент/ZIF/мембрана) — окремий
> аркуш [`ebfc_chem_rfq`](ebfc_chem_rfq.md); тести — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).
> **Статус:** 🟡 робочий артефакт (не канон). **Усі числа — дзеркало канону**: сплави/властивості → [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) + `tools/in_silico/lib/constants.py ALLOY_PROPERTIES`; геометрія → [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md); **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (Анкер-сплав рядок · hard-constraint доми §4.B/§4.E).
>
> ℹ️ **IP:** defensive-publication ([`07_03 §3`](../../07_03_Academic_Integration_and_IP.md)) — specs відкриті; CDA = стандартні комерц-умови.

---

## 0. Як користуватись + cover-note

1. Купон = плоский диск **Ø16×1 мм**, 1 грань = π·8² = **2.01 см² ≈ A_electrode** ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)); `j` нормують на **проєкційну** площу. **«Вушко»** (отвір/виступ на краю) під потенціостат-кліпсу, не псуючи активну грань.
2. **CEM-SSOT + креслення:** геометрія — `tools/cad/cem/ti_coin.<alloy>.json`; STL+DXF регенерувати `dotnet run --project tools/cad/src/SilkenCad -- draw cem/ti_coin.<alloy>.json` (per-alloy title-block).
3. **Cost-driver = к-сть СПЛАВІВ** (порошок/SLM-сетап), не монет → ~3 репліки/сплав дешеві. Замовляти Tier-1 одразу; Tier-2 — паралельний vendor-hunt (не блокує TRL-4).
4. **Дерево-first:** down-select за CV/EIS + ICP-MS у **синтетичному ксилемному соку** (не PBS); Al³⁺ теж фітотоксичний → zero-Al кандидати дерево-чистіші ([`01_04 §4.2`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 1. Per-alloy spec (6 купонів — усі рівні до coin-даних)

| # | Сплав | ASTM | V/Al wt% | E (ГПа) | Вісь bake-off | Tier |
|---|---|---|---|---|---|---|
| 1 | **Ti-6Al-4V** Gr5 | F136 | 4 / 6 | 110 | control + друк-еталон (V+Al токсичні = нижня межа) | 1 |
| 2 | **Ti-6Al-7Nb** | F1295 | 0 / 6 | 103 | V-free (Al лишається) | 1 |
| 3 | **CP-Ti Gr4** | F1581 | 0 / 0 | 104 | zero-tox, α-Ti (міцність ↓ ~480) | 1 |
| 4 | **β-Ti-13Nb-13Zr** | F1713 | 0 / 0 | 80 | low-E dual-win (ізоеластичність, HW.33) | 2 |
| 5 | **Tantalum** | F560 | 0 / 0 | 186 | benchmark біоінертності (⚠️ Ta₂O₅ DET-ризик; coin-only) | 2 |
| 6 | **Ti-15Zr** (Roxolid) | F2066-class | 0 / 0 | 100 | high-strength V/Al-free (практичний анкер-кандидат) | 2 |

**+ Au-coated bracket (опц., 7-й купон — `cem/ti_coin.au.json`):** DET-electrical **стеля** (Au = найкращий electron transfer), пара до Ta біоінертної стелі → реальні сплави затиснуті між двома межами. Surface-only (дешевий Ti + thin Au), **НЕ** структурний/анкер-кандидат — лише control-точка bake-off.

**Спільна обробка (усі купони):** SLM/LPBF друк → **HIP** (920°C/100-150МПа Ar/2-4год, §4.B) → **EAAE dual-scale** активація грані (Sa 0.5-5µm + Sv 50-500nm, [`01_02 §1.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) → **dehydrogenation bake** (250°C/10⁻³mbar, <2год після rinse, H<100ppm, §4.B). ⚠️ EAAE-протокол tuned під 4V → β-Ti/CP-Ti/Ta травляться інакше → **per-alloy etch-tuning** (CRO; coin виявить — squeeze-data SEM Sa/Sv).

**QC/acceptance (substrate):** SEM грані (Sa/Sv) · LECO RH404 H<100ppm · ICP-MS промивної води (Al<1ppb для 4V/7Nb).

---

## 2. Sourcing tiers (заземлено)

**Tier-1 — одразу (control + V-free baseline → достатньо для TRL-4):**
- **Ti-6Al-4V** — UA **3D Metal Tech Київ** (Concept Laser M2, ISO 13485) / EU Protolabs.
- **CP-Ti Gr4** — medical AM-бюро (Eplus3D/MET3DP), дентал-стандарт.
- **Ti-6Al-7Nb** — ISO-13485 ортопед-стандарт (medical AM-бюро).

**Tier-2 — vendor-hunt паралельно (НЕ блокує):**
- **β-Ti-13Nb-13Zr** — research-grade порошок (гаряча LPBF-тема 2024; UTS~1020/yield~795 — ⚠️ літ-оцінка **розходиться** з дім-значенням `ALLOY_PROPERTIES` (`tools/in_silico/lib/constants.py`) `yield_MPa: 900`; жодне з двох не несе джерела — ймовірно as-built LPBF vs HIP'd, але це **не звірено**; для vendor-hunt-контексту не несуче, для acceptance — звірити ДО спека) → академ-колаборація (co-pub, Гусак/[`07_03`](../../07_03_Academic_Integration_and_IP.md)) або спец-порошок.
- **Ta** — LPBF **рідко** (вартість/відбивність/ризик принтеру) → **думка-outside workaround: Ta-coating на дешевому Ti-купоні** (біоінертна Ta-поверхня без bulk-Ta друку; EBFC бачить поверхню). Bulk-Ta — лише за EBM-Ta вендором.
- **Ti-15Zr** — Roxolid пропрієтарний (Straumann); AM-порошок research-grade → спец-постачальник або defer.

---

## 3. Test battery + acceptance (дім — `01_03 §3.5`)

На кожному функціоналізованому купоні (Gen 2.0 стек з [`ebfc_chem_rfq`](ebfc_chem_rfq.md)):
- **CV/EIS** у синт. ксилемному соку *Pinus sylvestris* pH 4.5-5.5 ([`07_03 §1.1`](../../07_03_Academic_Integration_and_IP.md)): j_max, k_s, DET-маржа.
- **ICP-MS** іон-release у сік: V≤0.02 / Al≤0.05 µg/cm² (4V/7Nb); Nb/Zr/Ta — informational (біоінертні). Predicted — `tools/in_silico` script 51.
- **30-day stability** ≥80% retention · **chloride** 0.25M ramp · **UCST** −10→+25°C recovery (квантитативні пороги — дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
- **Нано-індентор E** (post-coin) — ізоеластичність vs деревина 9-16 ГПа (β-Ti dual-win check); predicted — script 50.

**Electrochem-CRO:** **EL-CELL (DE)** — бере клієнтські купони + custom-electrolyte CV/EIS, будує протокол. Альт: ЧНУ/ЧМА co-pub ([`07_03 §1.2`](../../07_03_Academic_Integration_and_IP.md)).

---

## 4. Hard constraints (RFQ МУСИТЬ нести — дзеркало канону)

- **§4.B метал** ([`01_02 §1.6/§1.7/§1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)): для bulk-структури анкера **SLM НЕ EBM** Zone 1 (порошок 15-45µm) — для плоского COIN менш критично, але грань потребує тієї ж EAAE-шорсткості · **HIP обов'язково** · **dehydrogenation bake** після EAAE · **ZnO-Ta ЗАБОРОНЕНО** на активній грані (блокує DET).
- **§4.E стерилізація** (якщо купон функціоналізований до тесту): **Co-60 НЕ EtO** · low-dose 15кГр для ферментів ([`01_04 §6`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 5. Dispatch checklist (👤)

- [ ] 👤 **Tier-1 RFQ** (4V/7Nb/CP-Ti) → 3D Metal Tech Київ / EU medical AM-бюро: 3 репліки×3 сплави, Ø16×1+вушко, HIP+EAAE+bake, SEM+ICP-MS acceptance. STL+DXF з `tools/cad` (`draw`).
- [ ] 👤 **Tier-2 vendor-hunt** (∥): β-Ti — академ-колаб/спец-порошок; Ta — coating-вендор (Ti+Ta-thin); Ti-15Zr — спец-постачальник.
- [ ] 👤 **Electrochem-CRO RFQ** → EL-CELL: CV/EIS+EIS у custom-electrolyte (синт. сік), 30-day, chloride, UCST, ICP-MS.
- [ ] 👤 Синт. сік — біо-хаб ЧНУ Спрягайло (рецептура, [`07_03 §1.1`](../../07_03_Academic_Integration_and_IP.md)).
- [ ] 👤 **Критичний шлях паралельно:** chem-стек ([`ebfc_chem_rfq`](ebfc_chem_rfq.md) Spec A фермент 🔴 4-8тиж) — усе сходиться на функціоналізованих купонах.

---

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
