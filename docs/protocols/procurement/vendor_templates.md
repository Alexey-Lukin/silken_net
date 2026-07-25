# Procurement Templates — DMLS-scoring · ESG-screen · CDA/NDA (BIZ.17)

> **Що це:** три операційні procure-шаблони для vendor-відбору та лаб-доступу — DMLS-scoring matrix, ESG-screening checklist і mutual CDA/NDA під ВНЗ-MoU; призначені founder'у/architect'у як робочий інструмент відбору, не як заморожена специфікація.
> **Concern-шар** (як [`procurement/`](rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — BIZ.17.

> **Склад:** **(A)** DMLS additive-manufacturing vendor-scoring matrix · **(B)** ESG vendor-screening checklist · **(C)** mutual CDA/NDA для ВНЗ-MoU.
> **Статус:** 🟡 робочий артефакт (**НЕ канон**) — draft-шаблони під заповнення/юр-review, не заморожені специфікації.
> **Усі числа/пороги — дзеркало канону або явний `PLACEHOLDER`**: сплав/метал-constraint → [`01_02`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) §1.6/§1.7 · гіроїд-геометрія/поруватість → [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) §5/§6 · procurement-constraint-доми → [`rfq_registry`](rfq_registry.md) §4.B · IP/NDA-постава → [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md). **Правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)).
> **Розміщення:** артефакт живе в `docs/protocols/procurement/` поряд з [`rfq_registry`](rfq_registry.md) та RFQ-аркушами; canon-ID — relative-links за конвенцією [`rfq_registry §5`](rfq_registry.md).
>
> ℹ️ **IP-постава (наскрізь):** SilkenNet = **defensive-publication** ([`07_03 §3`](../../07_03_Academic_Integration_and_IP.md)) — RFQ-specs/креслення/формат пакета **відкриті** (вже prior art під AGPL/MIT/CERN-OHL-S/CC-BY-SA). Тому:
> **CDA** (шаблони A/B) = стандартні комерц-умови (ціни/строки/QC), **НЕ** для новизни. **NDA** (шаблон C) покриває **ЛИШЕ нерозкрите** — криптоключі · польові production-дані · ML-ваги · невалідовані результати. **NDA-ити вже-публічне (open-source-код / CC-BY-SA-доки / defensive-published ядро) заборонено** — це суперечило б поставі.

---
---

## A. DMLS Vendor-Scoring Matrix (additive-manufacturing підрядник)

> **Мета:** обʼєктивний down-select друк-бюро для Ti-анкера (гіроїд Zone-1 + coupon). DMLS = laser-powder-bed-fusion (EOS-термін); **синонім-родина** LPBF/SLM. **Hard-gate: laser-PBF, НЕ EBM** для Zone-1 (§A.4 нижче — [`01_02 §1.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)).
> **Порядок:** (1) hard-gate §A.4 — pass/fail ДО скорингу; хто впав — вибуває. (2) вижилих скоримо §A.1–§A.3.

### A.0 Як користуватись

1. **Ваги (§A.1) — узгодити ДО розсилки RFQ**, не після отримання котирувань (інакше bias під улюбленого вендора). Сума ваг = **100%**.
2. Кожен критерій оцінюється **1–5** за rubric §A.2 (5 = найкраще). `зважений_бал = Σ(вага_i × бал_i) / 5 × 100` → 0–100 шкала.
3. **Hard-gate §A.4 — бінарний, ПЕРЕД скорингом.** Провал будь-якого = дискваліфікація незалежно від score (напр. EBM-only вендор, або відмова від HIP).
4. Vendor-дані заносити в §A.5 (по одному стовпцю на кандидата) — evidence-backed (сертифікат-№, зразок-звіт), не self-declared на віру.

### A.1 Критерії + ваги (PLACEHOLDER — founder/architect узгоджує)

| # | Критерій | Вага (%) | Обґрунтування ваги (заповнити) |
|---|---|---|---|
| C1 | **Lead-time** (RFQ→delivery, вкл. HIP+post) | `___%` | критичний шлях TRL-4 · [заповнити] |
| C2 | **Quality** (ISO-13485/AS9100 + гіроїд ≥60% поруватість-точність) | `___%` | несуче: implant-grade + TPMS-друкованість · [заповнити] |
| C3 | **Price-per-unit** (за coupon / за анкер, вкл. setup-amortization) | `___%` | R&D-фаза → cost-driver = к-сть сплавів, не монет · [заповнити] |
| C4 | **Capacity / scale** (репліки/тиждень · runway до 100-партії) | `___%` | Stage-2 малий, але Production-шар потребує scale · [заповнити] |
| C5 | **Geo-risk** (UA war-zone continuity vs EU-backup) | `___%` | supply-resilience · dual-source політика · [заповнити] |
| C6 | **Material-cert** (Ti-6Al-4V **Grade 23 ELI**, powder-traceability) | `___%` | несуче: implant + fatigue · [заповнити] |
|   | **СУМА** | **100%** | — |

> ⚠️ **Ваги — навмисний `PLACEHOLDER`.** Не вигадувати — це рішення founder/architect (trade-off lead-time↔quality↔price під поточний runway та procurement-authority). Типовий R&D-нахил: quality+material-cert домінують над price (implant-критичність), але це **не** захардкоджено тут.
>
> 🔒 **Заповнену матрицю (реальні ваги §A.1 + пороги §A.3) не тримати в публічному repo** — вендор, який бачить, за що саме нараховуються бали, оптимізує відповідь під шкалу, а не під реальну спроможність; заповнений примірник живе у приватному робочому файлі.

### A.2 Scoring rubric (1–5 per критерій)

**C1 — Lead-time** (менше = краще):
| Бал | Умова |
|---|---|
| 5 | ≤ `[T_fast]` тиж (заповнити target); порошок на складі, слот вільний |
| 4 | помірна черга, у межах критичного шляху |
| 3 | середня галузева (типово 3–5 тиж coupon) |
| 2 | довга черга / порошок під замовлення (+ тижні) |
| 1 | > `[T_slow]` тиж або невизначений; блокує TRL-4 |

**C2 — Quality** (ISO-сертифікація + TPMS-гіроїд друкованість):
| Бал | Умова |
|---|---|
| 5 | **ISO-13485 + AS9100** обидва · доведена ≥60%-поруватість гіроїда з dimensional-report на тонких стінках · власний CT/SEM-QC |
| 4 | ISO-13485 (implant) · TPMS-lattice-досвід, поруватість вимірювана · зовн. metrology |
| 3 | ISO-9001 · lattice-друк без TPMS-специфіки · базовий QC |
| 2 | загальний AM-сертифікат · без lattice-досвіду · self-report QC |
| 1 | без релевантної сертифікації або не тримає ≥60%-поруватість/точність |

> Поруватість ≥60% = **vendor-кваліфікаційний поріг** (дзеркало [`07_02 §8.1.1`](../../07_02_Unit_Economics_and_BOM.md)); геометрія гіроїда й ізоеластичність-таргет — окремий дім [`01_01 §5/§6`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (там пористість = CEM-параметр, не зафіксована константа). Точність тонкої стінки — picogk (voxel-dependent porosity — **MEASURE it**, не декларація). Vendor мусить показати як тримає wallParam на друці, не лише в STL.

**C3 — Price-per-unit** (нижче = краще; нормувати на однакову geometry/сплав):
| Бал | Умова |
|---|---|
| 5 | ≤ `[P_low]` за unit (заповнити) · прозорий setup-amortization |
| 4 | конкурентно, у межах бюджету |
| 3 | галузева медіана |
| 2 | вище медіани / непрозорий setup-charge |
| 1 | > `[P_high]` · прихований min-order / tooling-charge |

**C4 — Capacity / scale:**
| Бал | Умова |
|---|---|
| 5 | multi-machine Ti-parallel · очевидний runway Stage-2 → 100-партія без re-qualify |
| 4 | достатньо на R&D + помірний production-scale |
| 3 | покриває R&D-репліки, production TBD |
| 2 | single-machine / shared Ti-камера · вузьке горло |
| 1 | prototype-only · не масштабує |

**C5 — Geo-risk** (continuity під UA-war-zone; EU-backup = resilience):
| Бал | Умова |
|---|---|
| 5 | EU-локація АБО UA з доведеним war-continuity (backup-майданчик/genset/укриття) + чіткий logistics-шлях (Nova-Poshta/EU-customs) |
| 4 | стабільний UA-хаб поза hot-zone + EU-fallback-опція named |
| 3 | UA-хаб, continuity-план базовий |
| 2 | UA-хаб у ризиковій зоні / без backup |
| 1 | single-point-of-failure, без continuity / logistics-невизначеність |

> **Політика dual-source:** тримати ≥1 UA-хаб (напр. 3D Metal Tech Київ) + ≥1 EU-backup (Protolabs / 3D Lab PL) qualified паралельно — [`rfq_registry §1`](rfq_registry.md) Анкер-рядок · BIZ.6.

**C6 — Material-cert** (Ti-6Al-4V Grade 23 ELI + powder-traceability):
| Бал | Умова |
|---|---|
| 5 | **Grade 23 ELI** до **ASTM F3001** (AM PBF ELI) АБО **F136** (implant ELI) · повна powder-traceability (lot/heat, O/N/H-хімія, virgin/reuse-mix declared) · CoC на кожну партію |
| 4 | Grade 23 ELI cert · traceability є, reuse-mix документований |
| 3 | Ti-6Al-4V cert, але **Grade 5** (не-ELI, F2924) — прийнятно coupon-only, не implant-final |
| 2 | Ti-cert без ELI-розрізнення / часткова traceability |
| 1 | без матеріал-сертифіката або без powder-traceability |

> **ELI = Grade 23** (Extra-Low-Interstitial, знижений O/Fe → fatigue+в'язкість для implant); **Grade 5** (F2924) — стандартний, вища міцність але нижча в'язкість. Замовлення final-анкера → **Grade 23 ELI**; bake-off-coupon Gr5-друк-еталон допустимий (пор. [`anchor_alloy_rfq §1`](anchor_alloy_rfq.md)).

### A.3 Зважений підсумок

```
зважений_бал = Σ (вага_i × бал_i)  для i = C1..C6
нормований (0–100) = зважений_бал / 5 × 100
```

| Поріг | Значення (PLACEHOLDER) | Дія |
|---|---|---|
| **Award-floor** | ≥ `[S_pass]` (напр. 70) | кандидат на award |
| **Shortlist-band** | `[S_short]`–`[S_pass]` | short-list, follow-up/зразок |
| **Reject** | < `[S_short]` | вибуває |

> Пороги = `PLACEHOLDER` (founder-рішення). Скоринг **не заміняє** hard-gate §A.4 — вендор із 95/100, що друкує лише EBM або відмовляє HIP, все одно **fail**.

### A.4 Hard-gate (бінарний pass/fail — дзеркало канону, RFQ МУСИТЬ нести)

Провал будь-якого = **дискваліфікація** ([`rfq_registry §4.B`](rfq_registry.md) · [`01_02 §1.6/§1.7/§1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)):

- [ ] **Laser-PBF (SLM/DMLS/LPBF), НЕ EBM** для Zone-1 bulk-структури (порошок 15–45 µm). *(EBM-only вендор → fail.)*
- [ ] **HIP обов'язково** (920 °C / 100–150 МПа Ar / 2–4 год) — вендор виконує або має qualified HIP-партнера. *(Відмова HIP → fail.)*
- [ ] **Build-orientation BD ∥ вісь** анкера (анізотропія).
- [ ] **Dehydrogenation bake** після EAAE-rinse — **два різні параметри, обидва обов'язкові** ([`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) Крок 5b): **(а) тривалість випалу 2–4 год** (номінал 3 год) при 250 °C ± 25 / 10⁻³ mbar — нижча T → довше, вища → коротше; **(б) вікно старту — випал починається не пізніше 2 год після промивки** (це строк ДО початку, а НЕ тривалість: кожна година затримки жене H углиб TPMS). QC: H < 100 ppm (LECO vacuum hot extraction, купон з кожної партії). Вендор виконує або приймає як post-step.
- [ ] **ZnO-Ta ЗАБОРОНЕНО** на активній грані/Zone-1 (блокує DET) — [`01_02 §3.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md).
- [ ] Приймає **STL+DXF з `tools/cad`** (CEM-SSOT) як geometry-authority, з per-alloy title-block.

### A.5 Vendor-порівняння (заповнити per candidate)

| Критерій | Вага | **Vendor 1** `[назва]` | **Vendor 2** `[назва]` | **Vendor 3** `[назва]` |
|---|---|---|---|---|
| Hard-gate §A.4 (ALL pass?) | — | ☐ pass / ☐ fail | ☐ pass / ☐ fail | ☐ pass / ☐ fail |
| C1 Lead-time | `__%` | `_` (evidence) | `_` | `_` |
| C2 Quality | `__%` | `_` | `_` | `_` |
| C3 Price/unit | `__%` | `_` | `_` | `_` |
| C4 Capacity | `__%` | `_` | `_` | `_` |
| C5 Geo-risk | `__%` | `_` | `_` | `_` |
| C6 Material-cert | `__%` | `_` | `_` | `_` |
| **Зважений (0–100)** | 100% | `___` | `___` | `___` |
| **Verdict** | — | award/short/reject | … | … |

> **Кандидат-пул (seed з [`rfq_registry`](rfq_registry.md)):** UA — 3D Metal Tech Київ (Concept Laser M2, ISO-13485) · medical-AM-бюро (Eplus3D/MET3DP, CP-Ti/7Nb). EU-backup — Protolabs · 3D Lab PL. Внести реальні після RFQ-відгуку.

---
---

## B. ESG Vendor-Screening Checklist (репутаційний скрін)

> **Навіщо:** SilkenNet = climate-D-MRV → grant-фонди / кліматичні інвестори роблять **supply-chain ESG due-diligence** (Horizon Europe, EU-Taxonomy, green-bond умови). Постачальник, що сам «брудний», = репутаційний/eligibility-ризик для проєкту. Скрін = **захист eligibility**, не бюрократія.
> **Формат:** **Pass / Flag / Fail** per рядок. **Pass** = доказ є. **Flag** = часткова / self-declared без audit / потребує follow-up. **Fail** = невідповідність або red-line.
> **Evidence-first:** кожен рядок вимагає **документ**, не заяву (сертифікат-№, звіт, policy-URL). Self-declaration без доказу = максимум **Flag**.

### B.1 Скрін-матриця

| # | Категорія | Що запитати (evidence) | ✅ Pass | 🟡 Flag | ❌ Fail |
|---|---|---|---|---|---|
| E1 | **Екологічні сертифікати** | ISO 14001 / EMAS сертифікат (чинний, scope-релевантний) | чинний ISO 14001/EMAS, scope покриває виробництво | сертифікація в процесі / EMS без audit / протермінований | без EMS і без наміру |
| E2 | **Energy-source** | grid-mix / renewable-% / PPA / on-site solar | ≥ `[R%]` renewable (заповнити) або 100%-green-tariff з доказом | частково renewable / декларація без доказу | вугле-важкий grid без offset-плану |
| E3 | **Labor-practices** | ILO-core / SA8000 / code-of-conduct + audit | SA8000 або equiv. third-party-audit, ILO-core compliant | policy є, audit нема / self-assessment | **red-line:** дитяча/примусова праця, або відмова розкрити |
| E4 | **Conflict-materials** | OECD-DD / 3TG-declaration / Ti-powder origin (REACH/RoHS) | OECD-DD conformant + Ti-powder origin-traceable, REACH/RoHS ✓ | часткова due-diligence / origin partly-known | conflict-source або відмова декларувати походження |
| E5 | **Vendor сам «green»** | LCA / carbon-footprint / net-zero-commitment (SBTi?) | опублікований LCA/footprint + credible net-zero (SBTi-validated) | ціль є без плану / **greenwashing-flag** (заяви без даних) | протилежне (fossil-expansion, спростований green-claim) |

> Категорії: E1 екосертифікати · E2 energy-source · E3 labor · E4 conflict-materials · E5 self-green. Розширювати за grant-вимогою (напр. окремий water/waste-рядок під конкретний фонд).

### B.2 Aggregate-правило (як звести рядки у вердикт)

| Умова | Вердикт постачальника |
|---|---|
| Будь-який **red-line Fail** (E3 праця / E4 conflict-source) | **DISQUALIFY** — не проходить незалежно від решти |
| Будь-який не-red-line **Fail** | **HOLD** — усунути до award або перейти на альтернативу |
| ≥ `[N_flag]` **Flag** (заповнити, напр. 3) | **ESCALATE** — founder-review + remediation-план у контракт |
| Усі **Pass**, ≤1 Flag | **CLEAR** — proceed |

> `[N_flag]`-поріг = `PLACEHOLDER`. **Red-line ≠ tradeable:** child/forced-labor чи conflict-material не «компенсуються» гарним energy-score — це дискваліфікація, не мінус-бали.

### B.3 Нотатки

- **Пропорційність:** для дрібного spot-CRO (напр. genipin-реагент) — легкий скрін (E1/E3/E4); для Frame-Agreement-вендора 100-партії — повний + періодичний re-screen.
- **Greenwashing-lens (E5):** «green»-заяви без LCA/даних = **Flag**, не Pass. Verify-by-data — той самий етос honesty-engine, що наскрізь у проєкті.
- **Академ-канал (ЧНУ/ЧМА/ЧДТУ):** ВНЗ-лаба зазвичай поза комерц-ESG-режимом → скрінити на safety/ethics-compliance (біо/хім-waste), не на SA8000. Скрін тут = commercial-vendor-tool.

---
---

## C. Mutual CDA / NDA — ВНЗ-MoU (DRAFT)

> ⚠️ **DRAFT — потребує UA-юр-review ДО підпису.** Counterparty-юрист: **Аблязов Д.Е.** (СЄУ, к.ю.н., господарське/комерційне право) + профільний IP-юрист — [`07_03 §4.2`](../../07_03_Academic_Integration_and_IP.md) · **UNI.14**. Це шаблон-каркас, не готовий до підпису інструмент.
> **Мета:** розблокувати лаб-доступ ЧНУ/ЧДТУ (**UNI.2**, passive-гейт) через **mutual** confidentiality у рамках MoU.
> **Governing law:** Україна (ЦК України · ЗУ «Про захист від недобросовісної конкуренції» — комерційна таємниця).
> 🔑 **Ядро-принцип (defensive-publication, [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md)):** цей NDA покриває **ЛИШЕ нерозкрите**. **Технологія (код під open-source-ліцензіями · доки CC-BY-SA · defensive-published ядро) — вже public → carve-out §C.2, НЕ конфіденційне.** MoU **не embargo-їть** технологію (сам [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md): «MoU з ВНЗ містять open-license + co-authorship, **не** embargo/NDA на технологію»).

---

**УГОДА ПРО КОНФІДЕНЦІЙНІСТЬ (взаємна) № `[___]`**

**Сторони:**
- **«SilkenNet»** — `[підписант: operational-vehicle (наявна UA-компанія, Дія.City-резидент, співзасновником якої є founder) АБО founder як фізична особа — вибір per-engagement; повне найменування/реквізити ___]`, в особі `[___]` («Сторона 1»);
- **`[Назва ВНЗ]`** (напр. Черкаський національний університет ім. Б. Хмельницького / Черкаський державний технологічний університет), в особі `[ректор/проректор — напр. проректор Спрягайло]`, кафедра/лабораторія `[___]` («Сторона 2»);

разом — «Сторони», кожна — і **Розкривач**, і **Одержувач** (угода **взаємна**).

**Дата набрання чинності:** `[___]`.

### §C.1 Конфіденційна інформація (ЩО покривається)

«Конфіденційна інформація» — лише нерозкрите, позначене «Конфіденційно» або очевидно-конфіденційне за характером:

**Від SilkenNet:**
- (a) **криптографічні ключі** (device/gateway/factory — ніколи не публікуються);
- (b) **польові production-дані** (реальна телеметрія лісу, GPS-локації анкерів, gateway-логи);
- (c) **ваги ML-моделі** (навчені TinyML-параметри);
- (d) **невалідовані/попередні результати** до публікації (raw bench-дані, чернетки in-silico до peer-review).

**Від ВНЗ:**
- (e) непубліковані дослідницькі дані, методики, pre-publication-рукописи, студентські роботи **до їх відкриття** в репозиторії ВНЗ;
- (f) внутрішні лаб-процедури / know-how, позначені конфіденційними.

### §C.2 Виключення (carve-outs — ЩО НЕ конфіденційне)

**Не є Конфіденційною інформацією** (жодне зобов'язання §C.3 не застосовується), зокрема:

- (1) 🔓 **Вже-публічне ядро SilkenNet:** код backend/firmware/tooling під **AGPL-3.0-or-later**, смарт-контракти `contracts/*.sol` під **MIT** (per-file SPDX; ратифіковано DOC-T.47), hardware-специфікації під **CERN-OHL-S-2.0**, документація під **CC-BY-SA-4.0**, а також **defensive-published** інвентивне ядро (Synergy A/B — TDCommons + публічний repo + Стаття 1). Формат пакета, lightweight-crypto-інтеграція, RFQ-specs, креслення — **prior art, не secret**. Ліцензійна мапа зон — дім [`07_03 §3`](../../07_03_Academic_Integration_and_IP.md) (дзеркало кореневих LICENSE-файлів; правити там);
- (2) інформація, що стала публічною **не з вини** Одержувача;
- (3) вже правомірно відома Одержувачу до розкриття (з доказом);
- (4) незалежно розроблена Одержувачем без використання Конфіденційної інформації;
- (5) правомірно отримана від третьої сторони без порушення обов'язку конфіденційності;
- (6) розкриття якої вимагає закон/суд/регулятор (з попереднім письмовим повідомленням іншій Стороні, якщо законно).

> ℹ️ Carve-out (1) — **несучий** для постави проєкту: не можна NDA-ити те, що самі опублікували як prior art. Спроба закрити вже-відкрито-ліцензований код цією угодою — **нікчемна** в цій частині.

### §C.3 Зобов'язання Одержувача (взаємні)

Кожна Сторона як Одержувач зобов'язується:
- (a) використовувати Конфіденційну інформацію **лише** для мети MoU (спільна валідація/дослідження за `[тема]`), не для іншого;
- (b) не розкривати третім особам без письмової згоди Розкривача, крім співробітників/студентів за принципом need-to-know, зв'язаних не-меншими зобов'язаннями;
- (c) застосовувати **не менший** ступінь турботи, ніж до власної конфіденційної інформації (не нижче розумного);
- (d) не реверс-інжинірити ключі/production-дані/ML-ваги;
- (e) на вимогу або по завершенні — **повернути/знищити** Конфіденційну інформацію (з письмовим підтвердженням), окрім архів-копії для legal-compliance та застосовних open-license-примірників.

### §C.4 Строк (term)

- Угода діє `[N]` років від дати чинності (**PLACEHOLDER** — типово 3–5, юр-узгодити);
- зобов'язання щодо **криптоключів (a)** — **безстроково** (survival після припинення);
- решта категорій — `[M]` років після припинення (**PLACEHOLDER**).

### §C.5 Що угода НЕ робить

- (a) **не надає ліцензій** на IP жодної Сторони (окрім явних open-license, що діють незалежно); не передає прав власності;
- (b) **не створює** ексклюзивності, зобов'язання купувати/постачати, спільного підприємства;
- (c) **не є embargo** на технологію SilkenNet — публікація open-source/defensive-disclosure триває без обмежень цією угодою ([`07_03 §3`](../../07_03_Academic_Integration_and_IP.md));
- (d) **не обмежує** співавторство/публікацію спільних результатів за окремими co-authorship-умовами MoU (publish-to-protect, без embargo).

### §C.6 Загальне

- **Право, що застосовується:** матеріальне право України;
- **Спори:** переговори → `[суд за місцем / арбітраж — юр-узгодити]`;
- **Повнота:** угода + MoU = повна домовленість щодо конфіденційності; зміни — письмово, підписами обох Сторін;
- **Подільність:** нікчемність частини (напр. спроба покрити вже-public §C.2) не торкається решти;
- **Без відступлення** прав без згоди іншої Сторони.

**Підписи:** `[SilkenNet]` __________ · `[ВНЗ]` __________ · Дата `[___]`

### §C.7 Юр-review checklist (ДО підпису, 👤)

- [ ] 👤 **UA-юр-review** — Аблязов Д.Е. (СЄУ) + IP-юрист: звірити з ЦК України + ЗУ про комерц-таємницю (**UNI.14**).
- [ ] 👤 Підтвердити §C.2(1) carve-out проти актуальних кореневих ліцензій (`/LICENSE` AGPL · SPDX-MIT у `contracts/*.sol` · `/LICENSE-HARDWARE.txt` · `/LICENSE-DOCS.txt` · `/NOTICE`) — щоб NDA не суперечив open-license.
- [ ] 👤 Заповнити всі `PLACEHOLDER`: сторони, тема MoU, строки (N/M), forum спорів, поріг need-to-know.
- [ ] 👤 Узгодити з **co-authorship**-частиною MoU (§C.5(d)) — щоб конфіденційність не блокувала спільну публікацію.
- [ ] 👤 Зафіксувати підписанта per-engagement: operational-vehicle (наявна UA-компанія, Дія.City-резидент) або founder як фізична особа — юр-звірити правочинність та відповідність тришару «оперує / володіє / емітує» ([`07_03 §3`](../../07_03_Academic_Integration_and_IP.md); residual — [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.20).

---
---

## Cross-references

| Ресурс | Що бере |
|---|---|
| [`rfq_registry`](rfq_registry.md) | procurement-індекс · §4.B метал-constraint (hard-gate §A.4) · §3 IP/CDA/NDA-політика |
| [`anchor_alloy_rfq`](anchor_alloy_rfq.md) | парний Ti-coupon RFQ (Grade-cert контекст — критерій C6 §A.2) · стиль-еталон |
| [`01_02 §1.6/§1.7/§3.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | SLM≠EBM · HIP · dehydrogenation bake · ZnO-Ta-заборона (§A.4 дім) |
| [`01_01 §5/§6`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | гіроїд-геометрія + ізоеластичність/пористість як CEM-параметр (C2 геометрія-дім) |
| [`07_02 §8.1.1`](../../07_02_Unit_Economics_and_BOM.md) | vendor-кваліфікаційні критерії DMLS-хабів (Grade 23 ELI · ≥60% пористості · ISO 13485) — дім порогів C2/C6 |
| [`07_03 §3/§4.2`](../../07_03_Academic_Integration_and_IP.md) | defensive-publication + ліцензійна матриця + trade-secret-scope (NDA §C дім) · Аблязов UA-юр-review |
| [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md) | One-Home — реєстрація артефакту (промоція → registry §1) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | **BIZ.17** (procurement RFQ-layer) · UNI.2 (лаб-доступ) · UNI.14 (CDA/NDA legal) · BIZ.6/BIZ.20 |

> **Статус-нагадування:** 🟡 draft-шаблони. Ваги/пороги (§A.1/§A.3/§B.2) + NDA-поля (§C) — `PLACEHOLDER` під founder/юр-рішення, **не** вигадані. NDA — **draft, юр-review обов'язковий** (§C.7).
