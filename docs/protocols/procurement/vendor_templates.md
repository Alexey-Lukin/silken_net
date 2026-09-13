# Procurement Templates — DMLS-scoring · ESG-screen · CDA/NDA (BIZ.17)

> **Що це:** три операційні procure-шаблони для vendor-відбору та лаб-доступу — DMLS-scoring matrix, ESG-screening checklist і mutual CDA/NDA під ВНЗ-MoU; призначені founder'у/architect'у як робочий інструмент відбору, не як заморожена специфікація.
> **Concern-шар** (як [`procurement/`](rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — BIZ.17.

> **Склад:** **(A)** DMLS additive-manufacturing vendor-scoring matrix · **(B)** ESG vendor-screening checklist · **(C)** mutual CDA/NDA для ВНЗ-MoU. ⊕ Dispatch-листи: DMLS-бюро (EN; §A/§B як питання + інженерні питання трекера) · постачальник PEEK-мікротрубки лайнера шини (EN) · опромінювач ГІЛКИ A стерилізації (UA) · постачальник PTFE-мембрани катода (EN). Останні три — per-component, дім тимчасовий (нота над кожним листом).
> **Статус:** 🟡 робочий артефакт (**НЕ канон**) — draft-шаблони під заповнення/юр-review, не заморожені специфікації.
> **Усі числа/пороги — дзеркало канону або явний `PLACEHOLDER`**: сплав/метал-constraint → [`01_02 §1.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §1.7`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · гіроїд-геометрія/поруватість → [`01_01 §5`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_01 §6`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · шина (канал Ø1.35 · лайнер · дріт · вхід каналу) → [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md), чиї числа мають власника в `tools/in_silico/cache/mechanical/bus_mechanical.json` і `tools/cad/cem/cathode_flange.json` · стерилізація й мембрана катода → [`01_04 §6`](../../01_04_CODIT_and_Xylemointegration.md) · [`01_04 §5`](../../01_04_CODIT_and_Xylemointegration.md) · procurement-constraint-доми → [`rfq_registry`](rfq_registry.md) §4.B · IP/NDA-постава → [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md). **Правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)).
> **Розміщення:** артефакт живе в `docs/protocols/procurement/` поряд з [`rfq_registry`](rfq_registry.md) та RFQ-аркушами; canon-ID — relative-links за конвенцією [`rfq_registry §5`](rfq_registry.md).
>
> ℹ️ **IP-постава (наскрізь):** SilkenNet = **defensive-publication** ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — RFQ-specs/креслення/формат пакета **відкриті** (вже prior art під AGPL/MIT/CERN-OHL-S/CC-BY-SA). Тому:
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
| C6 | **Material-cert + СПРОМОЖНІСТЬ ПО СПЛАВАХ** (Gr5 baseline **І** V-free імплант-сплави, powder-traceability) | `___%` | несуче: implant + fatigue · [заповнити] |
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

> Поруватість ≥60% = **vendor-кваліфікаційний поріг** (дзеркало [`02_06 §8.1.1`](../../02_06_Unit_Economics_and_BOM.md)); геометрія гіроїда й ізоеластичність-таргет — окремий дім [`01_01 §5/§6`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (там пористість = CEM-параметр, не зафіксована константа). Точність тонкої стінки — picogk (voxel-dependent porosity — **MEASURE it**, не декларація). Vendor мусить показати як тримає wallParam на друці, не лише в STL.

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

**C6 — Material-cert + спроможність по сплавах** (powder-traceability):

> ⛔ **Вимогу НЕ звужувати до Ti-6Al-4V ELI** ([`02_06 §8.1.1`](../../02_06_Unit_Economics_and_BOM.md) — дім порогів C2/C6): канон називає ELI поіменно як ПАСТКУ (Grade 23 зберігає ~4 % ванадію, [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) — V-free напрям для Zone 1 уже обрано), а фінальний сплав ще не обрано: його визначить 6-сплавний coin bake-off (HW.24). Тому вендора оцінюємо не за ELI-сертифікатом, а за тим, чи вміє він надрукувати ТЕ, ЩО МИ ОБЕРЕМО.
| Бал | Умова |
|---|---|
| 5 | Gr5 (F2924) baseline **І** підтверджена спроможність по **V-free імплант-сплавах** (Nb/Fe/Zr-родина) · повна powder-traceability (lot/heat, O/N/H-хімія, virgin/reuse-mix declared) · CoC на кожну партію |
| 4 | Gr5 cert + готовність кваліфікувати V-free сплав під замовлення · traceability є, reuse-mix документований |
| 3 | лише Ti-6Al-4V (Gr5 або Gr23) без V-free спроможності — покриває bake-off-купони, але не фінальний анкер |
| 2 | Ti-cert без розрізнення марок / часткова traceability |
| 1 | без матеріал-сертифіката або без powder-traceability |

> **Словник спек — тримати тут, бо саме його плутанина вже коштувала хибного рядка в RFQ.** Дві осі, і вони НЕЗАЛЕЖНІ: **марка** (ELI = Grade 23, знижений O/Fe → fatigue+в'язкість для implant ⊥ Grade 5 — стандартний, вища міцність але нижча в'язкість) і **процес** (AM powder-bed-fusion ⊥ wrought). Наші купони й прінти — AM, тож для них: **Gr5 → `F2924`** · **Gr23 ELI → `F3001`** (обидві пари стоять у цьому файлі з доREFACTOR-редакції, тобто не виведені заднім числом). ⛔ **`F136` є ELI-спекою (Gr23)**, і саме вона стояла на **Gr5**-контролі в `anchor_alloy_rfq` до 2026-09-08 — помилка на осі МАРКИ, і цього одного досить, щоб її зняти. ✅ **Другу вісь звірено первинкою 2026-09-11: F136 є ще й WROUGHT** («Standard Specification for **Wrought** Titanium-6Aluminum-4Vanadium ELI…»), тобто для друкованого купона він хибний двічі. 🔴 **І та сама звірка показала межу самого цього словника: пара AM⊥wrought має ПЕРЕВІРЕНІ члени лише для Ti-6Al-4V.** Для 7Nb, CP-Ti, β-Ti-13Nb-13Zr, Ti-Zr і Ta ми AM-половини **не знайшли — і це не те саме, що «її немає»:** `ASTM F3302` («…Titanium **Alloys** via Powder Bed Fusion») чинний, а його таблиця охоплених марок платна й нами не читана; для Ta каталог F42 не перелічує спеки матеріалу взагалі (`F3635` — Nb-Hf), але перелік каталогу слабший за прочитану область застосування. **Чесна форма в листі одна: цитувати wrought-спеку ЯК СКЛАД і ПИТАТИ вендора, до чого він друкує й чи покриває це якийсь AM-стандарт** — ніколи не стверджувати відсутність за нього. ⛔ Не добирати «найближчу» AM-спеку за схожістю — саме такий добір і дав `F1581` на CP-Ti та `F2066` на Ti-15Zr, обидва про інший матеріал ([`anchor_alloy_rfq §1`](anchor_alloy_rfq.md)). ⛔ **Але замовлення final-анкера НЕ «Grade 23 ELI»:** ELI лишає ~4 % ванадію, а V-free напрям для Zone 1 обрано — сплав визначить bake-off (HW.24); bake-off-coupon Gr5-друк-еталон допустимий (пор. [`anchor_alloy_rfq §1`](anchor_alloy_rfq.md)).

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

> **Кандидат-пул (seed з [`rfq_registry`](rfq_registry.md)):** UA — 3D Metal Tech Київ (Concept Laser M2, ISO-13485) · **ALT print** (Alfa-150D 150×150×180 мм і Alfa-280N 280×280×300 мм, Ti-6Al-4V — верифіковано на сайті вендора 2026-09-12; доти дерево знало лише машину «Alfa-280» без імені постачальника, у вартісному рядку [`02_06 §3`](../../02_06_Unit_Economics_and_BOM.md)) · medical-AM-бюро (Eplus3D/MET3DP, CP-Ti/7Nb). EU-backup — Protolabs · 3D Lab PL. Внести реальні після RFQ-відгуку. ⚠️ **Діаметр плями лазера й фракція порошку в жодного з двох UA-вендорів на сайті НЕ вказані** — це і є питання про мін-стінку ([`00_07` HW.33](../../00_07_Action_Plan_Tracker.md)), а не число, яке можна взяти з реклами.

---
---

## B. ESG Vendor-Screening Checklist (репутаційний скрін)

> **Навіщо:** ⚠️ **Підстава ПЕРЕПИСАНА 2026-09-08 — доти тут стояв grant-mandate, і він мертвий:** грант-вектор знято ⚖️ founder 2026-07-23 (Horizon прибрано з проєкту; трек opportunistic-passive, дім негативний — [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.12/BIZ.20). Чинна підстава вужча й наша власна: SilkenNet = climate-D-MRV, тож постачальник, що сам «брудний», є репутаційним ризиком для свідчення, яке ми продаємо. ⛔ Не називати вендорові жодного фонду й жодного «reporting obligation» — їх немає. Постачальник, що сам «брудний», = репутаційний/eligibility-ризик для проєкту. Скрін = **захист eligibility**, не бюрократія.
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

> ⚠️ **DRAFT — потребує UA-юр-review ДО підпису.** Counterparty-юрист: **Аблязов Д.Е.** (СЄУ, к.ю.н., господарське/комерційне право) + профільний IP-юрист — [`00_02 §4.2`](../../00_02_Academic_Integration_and_IP.md) · **UNI.14**. Це шаблон-каркас, не готовий до підпису інструмент.
> **Мета:** розблокувати лаб-доступ ЧНУ/ЧДТУ (**UNI.2**, passive-гейт) через **mutual** confidentiality у рамках MoU.
> **Governing law:** Україна (ЦК України · ЗУ «Про захист від недобросовісної конкуренції» — комерційна таємниця).
> 🔑 **Ядро-принцип (defensive-publication, [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)):** цей NDA покриває **ЛИШЕ нерозкрите**. **Технологія (код під open-source-ліцензіями · доки CC-BY-SA · defensive-published ядро) — вже public → carve-out §C.2, НЕ конфіденційне.** MoU **не embargo-їть** технологію (сам [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md): «MoU з ВНЗ містять open-license + co-authorship, **не** embargo/NDA на технологію»).

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

- (1) 🔓 **Вже-публічне ядро SilkenNet:** код backend/firmware/tooling під **AGPL-3.0-or-later** (per-file SPDX), смарт-контракти `contracts/*.sol` під **MIT** (per-file SPDX; ратифіковано DOC-T.47), hardware-специфікації під **CERN-OHL-S-2.0**, документація під **CC-BY-SA-4.0**, а також те інвентивне ядро, що **вже опубліковане публічним repo**. 🔴 **⛔ TDCommons-якір і Стаття 1 сюди НЕ входять — вони постинг-готові, але НЕ виконані** ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) прямим текстом: «дата prior art має юридичну вагу, тож не цитуй їх як наявні»; стан — [`00_07`](../../00_07_Action_Plan_Tracker.md) UNI.3 і HW.5.IS, обидві ноги відкриті). Оголошувати їх у carve-out означало б віддати конфіденційність авансом за prior art, дати якого ще не існує. ⚠️ І перелік Synergy тут не вичерпний: `00_01 §8` несе ще **Synergy C** (хаотичне перетворення як печатка цілісності, додано 2026-09-05). Формат пакета, lightweight-crypto-інтеграція, RFQ-specs, креслення — **prior art лише в тій частині, що вже в публічному repo**. Ліцензійна мапа зон — дім [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) (дзеркало кореневих LICENSE-файлів; правити там);
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
- (c) **не є embargo** на технологію SilkenNet — публікація open-source/defensive-disclosure триває без обмежень цією угодою ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md));
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
- [ ] 👤 Підтвердити §C.2(1) carve-out проти актуальних кореневих ліцензій (`/LICENSE` AGPL + per-file SPDX по source-дереву · SPDX-MIT у `contracts/*.sol` · `/LICENSE-HARDWARE.txt` · `/LICENSE-DOCS.txt` · `/NOTICE`) — щоб NDA не суперечив open-license.
- [ ] 👤 Заповнити всі `PLACEHOLDER`: сторони, тема MoU, строки (N/M), forum спорів, поріг need-to-know.
- [ ] 👤 Узгодити з **co-authorship**-частиною MoU (§C.5(d)) — щоб конфіденційність не блокувала спільну публікацію.
- [ ] 👤 Зафіксувати підписанта per-engagement. ⚠️ **Це НЕ вибір юр-форми — її обрано ⚖️ 2026-07-24 і вона більше не гейтить** ([`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.20: тришар operational-vehicle ⊥ IP/™ на фізособі ⊥ token-контур Phase-2; сусідній `msa_skeleton` уже пише counterparty поіменно). ⛔ **Не нести цю розвилку юристові як відкриту** — DOC-T.101 щойно зняв рівно таку в `msa_skeleton`, бо вона продавала оплачену годину за вирішене. 🔴 **Живий гейт тут ІНШИЙ і його треба назвати:** предмет цієї NDA — криптоключі, польові дані й ML-ваги, тобто **SilkenNet-IP**, а канон ставить будь-який дотик IP до ActiveBridge-контуру **ПІСЛЯ co-founder IP-carve-out** (BIZ.20, двошаровий: ЦК 1113 ч.1 + розкриття конфлікту інтересів ст. 42 ч.6 ЗУ «Про ТОВ»). Юр-звірити треба саме це — правочинність обраного шару й проходження carve-out-гейта, а не відповідність тришару «оперує / володіє / емітує» ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md); residual — [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.20).

### §C.8 IP-режим ВНЗ-контрибуцій — каркас пункту для MoU (DRAFT, **UNI.20**)

> ⚠️ **Це НЕ частина NDA вище, і розділення несуче.** §C покриває *конфіденційність* (хто що не розголошує); цей пункт покриває *авторство й титул* на код/дані, що приходять ДО НАС із боку ВНЗ. Дві різні угоди можуть жити в одному MoU, але плутати їх не можна: NDA нічого не каже про те, кому належить студентський PR, а §C.5(a) прямо фіксує, що ліцензій ця угода не надає.
> 🔑 **Навіщо він узагалі:** платформа приймає inbound-код під копілефтом, і механізм узгодження — DCO (`git commit -s`, merge-гейт живий). Але наш власний огляд ([`oss_web3_standards.md`](../business/oss_web3_standards.md) §4) фіксує межу: **DCO фізособи не обовʼязково перекриває інституційну IP-претензію ВНЗ, коли робота виконана в межах формального гранту / дипломної / керованої роботи.** Тому пункт мусить лежати готовим **ДО** підписання MoU, а не писатись під тиском першої контрибуції.
> ⏳ Станом на 2026-08-30. **Не юридична порада** — вхід у консультацію (**UNI.14** → **UNI.16**, Блок 4 пакета [`securities_review.md`](../legal/securities_review.md)).

🔴 **ЩО ТУТ СВІДОМО НЕ НАПИСАНО, і чому порожнє місце чесніше за текст.** Режим **службових творів за правом України стосовно СТУДЕНТА** (не працівника) наш research **не досліджував** — наявна оцінка є проєкцією з чужих (US) університетських політик, і сам огляд це визнає. Отже нижче — **питання й розвилки з названими наслідками**, а не формулювання пункту. Хто заповнює: UA-юрист із IP-профілем; де стоїть питання: `securities_review` Блок 4.4 (службові твори студентів) і 4.5 (форма carve-out / license-back за ЦК України).

**Розвилка 1 — ЧИЙ титул на студентську контрибуцію.** `[юр-заповнити]`
- (а) студента як фізособи (тоді DCO самодостатній);
- (б) ВНЗ, коли робота є частиною гранту/дипломної (тоді потрібен окремий grant від ВНЗ);
- (в) змішаний за критерієм `[який саме — юр]`.
**Наслідок вибору:** лише за (а) merge-гейт, що вже стоїть, є достатнім; за (б)/(в) кожна така контрибуція потребує ще й інституційного підпису, і його форму треба закласти в MoU наперед — інакше перший же PR зупиняється на переговорах.

**Розвилка 2 — ФОРМА узгодження, якщо титул не в студента.** `[юр-заповнити]`
- (а) ВНЗ дає **невиключну ліцензію** на умовах кореневої ліцензії репозиторію (мінімальна форма, нічого не відбирає);
- (б) ВНЗ **відступає** майнові права на конкретний внесок;
- (в) інституційний **DCO-еквівалент** — підписаний уповноваженою особою один раз на MoU, а не на кожен PR.
**Наслідок:** (в) дешевше в експлуатації й ближче до нашої постави, але його юридична достатність за UA-правом — саме те, що ми не перевіряли.

**Розвилка 3 — dual-licensing-стеля, і вона вже оголошена.** Наш огляд фіксує, що DCO лишає копірайт контрибʼютору, тож зовнішній внесок **не можна** включити в майбутню комерційну dual-license без згоди автора. Сьогодні це не блокер, бо ядро — власність засновника. ⏳ **Але теза старіє В МОМЕНТ ВЛАСНОГО УСПІХУ:** вбиває її перша ж змерджена зовнішня контрибуція, а не календар. Питання юристу: чи варто вже зараз закладати в MoU легкий license-grant, який лишає цю опцію відкритою, — і чи не суперечить він копілефт-поставі ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)).

**Розвилка 4 — що НЕ покриває цей пункт (межі, щоб не роздувся).** Співавторство публікацій — окремим блоком MoU (§C.5(d) уже це фіксує); конфіденційність — §C.1–§C.4; ліцензії на *наш* код у бік ВНЗ — уже врегульовані кореневими ліцензіями й нічого не потребують.

**Мінімальний текст-заготовка** (наповнюється ПІСЛЯ розвилок 1–2, не раніше):

> `[N]`. **Права на результати, створені Стороною 2.** Код, дані та документація, передані Стороні 1 у межах співпраці за цим MoU, надаються на умовах кореневих ліцензій репозиторію `[перелік — дзеркало /NOTICE]`. Особа, що передає внесок, засвідчує право на таку передачу підписом `Signed-off-by` згідно з DCO. `[ЯКЩО титул ВНЗ — тут додається інституційний grant у формі за розвилкою 2]`. Цей пункт **не** надає Стороні 2 прав на технологію Сторони 1 і **не** обмежує публікацію відкритих результатів.

- [ ] 👤 **Питання винести на юр-workshop** (**UNI.14**): розвилки 1–3 → `securities_review` Блок 4.4/4.5.
- [ ] 👤 Після відповіді — заповнити заготовку й перенести пункт у сам MoU-документ, коли той зʼявиться (сьогодні MoU-шаблону в репо немає; цей каркас — його передвісник, а не він сам).

---
---

## 📤 Dispatch block (EN) — paste into vendor email

> Ready-to-send English text for a **laser-PBF (DMLS) bureau**: the capability/documentation half of §A and the E1–E5 questions of §B, turned into asks, plus the engineering questions the tracker routes to the same bureau (§Processing from item 8 on — each indexed in [`rfq_registry`](rfq_registry.md) §4.B/§4.C). Working body above stays Ukrainian.
> Anything our side must NOT disclose is deliberately absent — **немає:** ваг §A.1, rubric §A.2 і порогів §A.3/§B.2 (сам документ це забороняє: вендор, що бачить шкалу, оптимізує відповідь під неї — просимо ФАКТИ: сертифікат-№, lead-time, dimensional-report), вердикт-таблиць §A.5/§B.2 (DISQUALIFY/HOLD/ESCALATE), слова «hard-gate»/«дискваліфікація» (ті самі вимоги йдуть як mandatory confirmations), нашої dual-source-політики й імен кандидат-пулу, оцінки «дрібний spot-CRO» (§B.3), порогу поруватості як цифри (просимо **виміряне** as-built, не декларацію), трекер-ID/канон-рефів, статус-маркерів.
> ⚠️ **Вікно натягу пари «трубка ↔ дріт» (~21 мкм діаметрально, §Processing п.12 і лист трубки нижче) лист НАЗИВАЄ свідомо, і забороні показувати шкалу це не суперечить:** поріг поруватості кваліфікує ВЕНДОРА, а вікно обирає НАШ маршрут складання (купити посадку ⊥ підбирати ⊥ садити з нагрівом) — тож лист прямо каже, що ширша смуга є корисною відповіддю, а не провалом. **Номінального натягу не названо ніде** — він відкритий ⚖️ ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.34).
> 🔴 **§C (mutual CDA/NDA) не відправляється нікому** — там імʼя нашого юриста й невирішений підписант; іде на юр-review, не вендору.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

Vendor pre-qualification — implant-grade titanium laser-PBF, thin-wall lattice parts (R&D batches now, possible production follow-on)

### Scope of request

Before we issue detailed part RFQs we ask candidate suppliers for a short pre-qualification covering two things: manufacturing capability with the quality and material documentation you can supply, and a short supply-chain sustainability questionnaire we keep on file as part of our own due-diligence. Answering commits neither side to anything. If it is easier for you, answer inline in this email — attachments only where a document is asked for.

### Item specification

What we will be asking you to quote:

- **(a) Thin-wall TPMS (gyroid) lattice structural parts in titanium**, and **(b) flat coupons** of the same alloys for surface and electrochemical characterisation.
- **(c) A solid titanium cathode flange** — a flat disc on a shank, no lattice — whose axial through-channel is finished after printing (item 11 below).
- **Geometry is always supplied by us as STL plus a dimensioned DXF** drawing with title block, and the supplied geometry is the **dimensional authority** — we do not ask you to re-model or re-interpret it.
- **Materials.** Coupons and the current baseline structural prints are **Ti-6Al-4V Grade 5 (ASTM F2924)**, with full powder traceability (lot/heat, O/N/H chemistry, virgin/reuse mix declared, CoC per lot). ⚠️ **The final structural alloy is not yet chosen** — it will be decided by a six-alloy coupon bake-off, and the leading direction is **vanadium-free** (Nb / Fe / Zr implant families), because the anchor sits in living tissue for twenty years. **Please tell us which V-free titanium implant alloys you can print and certify, and what it takes to qualify one** — that capability, not an ELI certificate, is what we are scoring.

### Processing / QC requirements

These are mandatory process requirements for the structural part. **Please confirm each in writing, or say plainly that you cannot** — we would rather know now than after an award.

1. **Laser powder-bed fusion (SLM / DMLS / LPBF), powder 15–45 µm.** Electron-beam melting is not suitable for this part.
2. **HIP is mandatory: 920 °C / 100–150 MPa argon / 2–4 h** — in-house or through a named qualified partner (name them, include cost and time). ⊕ **Also state the ASTM F2924 CLASS you would certify the batch to, and its designation.** We understand one of that standard's classes to make HIP obligatory while the others leave it optional; if that is how you read it, we want the batch accepted against the class rather than against a requirement of ours. Please answer in your own terms — we are not quoting the standard back at you, and we have seen a second, unrelated classification axis in it, so tell us which axis you mean.
3. **Build orientation: build direction parallel to the part axis within 0 ± 5°, with supports on external surfaces only** (anisotropy control).
4. **Dehydrogenation bake after the etch rinse — two independent parameters, both mandatory:** bake **2–4 h** (3 h nominal) at **250 °C ± 25 °C under 10⁻³ mbar**, and the bake must **start no later than 2 h after the rinse** (a deadline for the start, not a duration). Acceptance: **hydrogen < 100 ppm** by vacuum hot extraction, one coupon per batch. You may perform this step or accept it as a defined post-step.
5. **No ZnO-Ta (tantalum-doped zinc oxide) or comparable antibacterial oxide coating** on functional surfaces — it blocks electron transfer.
6. **You accept our STL + dimensioned DXF as the geometry authority**, one set per alloy.
7. **Thin-wall lattice capability.** The required porosity and wall thickness are defined by the supplied geometry, not by a separate number we hand you. Confirm you can hold the wall thickness of a TPMS lattice at that scale, and that you can report **measured as-built** values — dimensional report, and CT or SEM of internal features if you have that capability. We buy measured values, not declared ones.
8. **Declare your minimum printable wall — per machine and per powder lot, in µm.** This is the one number we ask you to hand US, and it runs opposite to item 7: there we ask whether you can hold our geometry, here we ask what your process floor is, because we re-compute the lattice against it rather than assuming an industry figure. State it as a measured or qualified value with the basis (test artefact, coupon, machine specification), and say whether it differs between your titanium machines. If the answer is a range, give the range and the conditions that move it.

9. **A welded joint inside the part, and we need your view on WHERE it sits in the cycle.** One conductor — a cold-drawn titanium wire — is joined to the printed anode face and then threads the assembly; the method is yours (laser, micro-TIG, electron beam), our only constraint is **minimum heat-affected zone at the root**. Two things we ask rather than specify. **(a) Before or after HIP?** We care because residual *tensile* stress at the weld is the one term our fatigue margin does not carry, and a HIP cycle at the parameters in item 2 would relieve it — but we cannot price either side ourselves: our alloy strengths are generic wrought references, so an annealed wire moves nothing in our model, and we have no mean-stress correction in it at all. We would rather you answered a question with both halves on the table than one that looks open. **(b) What the joint is worth in fatigue** — the joint class you would assign, the procedure specification (WPS) you would work to, whether you do any post-weld treatment of the toe, and **how you would evidence soundness**. On the last point we specify the REQUIREMENT and leave the instrument to you: optical inspection alone does not reach sub-surface porosity or the heat-affected zone, which are exactly the mechanisms our margin turns on. A break at this joint is an open circuit in a sensor that is meant to sit inside a living tree for twenty years, so a knock-down factor is worth more to us than a reassurance.

10. **Machine-capability standards, and one acceptance method.** Where you hold or can work to them, say so and quote them as line items rather than as a claim: **ISO/ASTM 52902** (standard test artefacts — printing one *before* our batch turns item 8's minimum-feature question into a measured number from your machine rather than an industry figure), **ISO/ASTM 52920** (qualification of the production site) and **ISO/ASTM TS 52930** (installation, operation and performance qualification). Separately, the acceptance method for the lattice part is **ISO 13314** (compression testing of porous and cellular metals) — and we have to be precise about WHICH quantity, because the standard defines two gradients and calls neither a modulus of the material. The one comparable to our number is the **elastic gradient**: the secant of an **unload–reload hysteresis loop taken between 20 % and 70 % of the plateau stress** — not the quasi-elastic gradient, which is what a laboratory returns by default and which the standard uses to locate the strain zero. **A run without an unloading cycle gives us nothing to compare against**, and since that stiffness drifts as the specimen compresses, the report must name the point on the curve rather than a single number. Tell us whether you can supply such specimens from the same build, or whether we should route that to a test house. ⚠️ We do not yet hold the standard's own specimen-geometry clause; if you or your test house do, tell us what it requires — that answer has to reach us **before** the batch is printed, not after.

11. **A second part — the solid cathode flange — and the one feature on it we cannot accept as printed: its axial through-channel.** The flange is a flat Ø25 mm titanium disc on a shank, with no lattice. The conductor of item 9 runs up its axis through a **Ø1.35 mm channel that goes right through the shank and the disc and exits on the flange face** — a through-channel, not a blind bore — about 17 mm long, which puts its **depth-to-diameter ratio at about 12.6** (the diameter is fixed; the flange thickness, and with it the length, is not final). Items 1 and 2 are written for the lattice part and do not transfer to this one: tell us whether you would print the flange by laser or by electron beam, and whether you would HIP it — on a laser machine in particular we have no ground of our own for leaving HIP out, so this is a question, not a permission. **(a) The channel is the part's primary datum** (concentricity and runout 0.05 mm referenced to its axis, flange face as secondary datum), so it is **finished after printing, never accepted as printed** — and we ask rather than specify how. Tell us **the diametral band you can hold on it, and how you verify that band along its length**; **the surface you deliver inside it**, stated as a named parameter together with the instrument, because the liner's outer surface bears against that bore for twenty years; and **the operation you would use** — at this depth-to-diameter ratio the choice belongs to whoever holds the tool, so name yours; we do not name one. Please quote that finishing as its own line item. Why the band matters: the channel receives a separately bought PEEK liner tube about 1.30 mm across with only **50 µm diametral clearance at nominal**, and that clearance can vanish inside the tube's own tolerance plus yours. We have left both limits of this bore blank on purpose — quote the band you actually hold rather than filling the blank with a default. **(b) The entry edge of the channel carries a radius, not a chamfer.** The entry is the end face of the shank, opposite the flange face, where the liner-covered conductor comes in. As the conductor flexes it reaches that mouth at well under one degree (about 0.6° in our worst computed case) — far shallower than any lead-in chamfer — so it never lands on the chamfer: it bears on the line where the chamfer meets the cylinder. A chamfer only moves the edge; a radius removes it. **We deliberately give no radius value** — choosing one needs a contact model we do not have — so tell us **what edge radius you can produce at the entry of a channel this small and this deep, and how you would verify it**.

12. **The cold-drawn wire of item 9 — its diameter tolerance and its surface, each with how it is measured.** The wire is Ø1.0 mm, of the same alloy as the printed anode, and the PEEK liner tube of item 11 sits **tight on it**. We ask for **the diameter band the wire is delivered to**, and for **its surface roughness stated as a parameter together with the instrument**: a stylus profile Ra and an areal Sa (ISO 25178) are different measurements that give different numbers on the same surface, and our own specification has not chosen between them yet — so a roughness figure without its parameter and method is one we cannot use. Why the band matters: the wire's diameter band and the tube's bore band together must fit inside a window of **about 21 µm on diameter** — at the tight end the tube wall yields in the cold, at the loose end the fit is lost in the heat — and roughness spends part of that same window, because surface peaks flatten when the tube is pressed on. The window is optimistic in itself (it ignores creep and form error), so quote the band you actually get rather than one chosen to fit: a wider band is a useful answer, not a failed one — it tells us to select, machine or heat-assemble the pair instead of buying the fit. If the wire comes from a separate supplier, tell us who sources it, and in which of the candidate alloys cold-drawn wire of this diameter is available.

13. **Geometry file format — a question, not a change to item 6.** Item 6 stands: STL plus a dimensioned DXF is the geometry authority. STL, however, carries neither units nor any metadata, which makes it the weakest link for a part that has to stay traceable to its design for twenty years, whereas 3MF carries both natively. **Would you accept 3MF in place of the STL**, with the DXF unchanged? We have not switched, and we would only do that work if suppliers accept the format — your answer decides it.

### What we ask you to provide

**Capability and quality documentation**

1. Machine models and count, how many are dedicated to titanium, and your powder handling and reuse policy.
2. **Certifications with certificate number, issuing body, scope and validity:** ISO 13485, AS9100, ISO 9001 — whichever you hold; if a certification is in progress, say so with the expected date.
3. **Material documentation per alloy:** powder specification, lot/heat traceability, O/N/H chemistry, virgin-to-reused ratio declared, CoC per batch.
4. **Evidence of comparable work:** a dimensional or CT report from a previous thin-wall lattice job (redacted is fine).
5. **Continuity for our order:** backup site or machine, power arrangements, and the logistics route you would use to us.

**Commercial**

6. **Unit price** at the quantities in the part RFQ, and the price break points above them.
7. **Setup, build-plate and tooling charges itemised separately** from unit price.
8. **MOQ**, and the price of a **first-article single-part or single-coupon trial build** before a full batch.
9. **Lead time from purchase order to shipment**, stating explicitly whether HIP, surface activation, the bake and QC are inside that lead time or added to it.
10. **Capacity:** parts per week in titanium, and whether a follow-on production batch would require re-qualification of the process.
11. **Quote format:** currency, validity period, payment terms, technical point of contact.

**Supply-chain sustainability questionnaire.** Please attach documents rather than statements — a certificate, report or policy URL. Where something is in progress, say so with a date; we would rather have an honest gap than a claim we cannot verify.

| # | Topic | What we ask for |
|---|---|---|
| E1 | Environmental management | Current **ISO 14001 or EMAS** certificate — number, scope, validity. Scope must cover the production site doing our work. |
| E2 | Energy source | Your electricity grid mix or renewable share, **with evidence**: supplier disclosure, green-tariff certificate, PPA, or on-site generation. |
| E3 | Labour practices | **SA8000** or an equivalent third-party audit, or your code of conduct plus the most recent audit report; confirmation of ILO core-convention compliance. |
| E4 | Materials origin | OECD due-diligence or 3TG declaration where applicable · **titanium powder origin traceability** · REACH and RoHS statements. |
| E5 | Your own climate position | Published **LCA or carbon footprint**, and any net-zero or SBTi-validated target together with the plan behind it. |

### Commercial & logistics

- Ship-to: Ukraine (Cherkasy region); we can nominate an **EU forwarding address** instead if that simplifies export or customs — state your preference.
- Incoterms you quote on, HS code, and any export-control classification applicable to titanium powder-bed parts.
- **Packaging:** parts individually pouched, functional surfaces protected, no contact with oils or adhesives.
- Tell us what you need from us to proceed (end-use statement, entity details, preferred drawing format).

### Attachments

Nothing is needed from you to answer this pre-qualification beyond the documents named above. Part geometry (STL + dimensioned DXF) and the QC acceptance definition follow with the part RFQ once pre-qualification is complete.

---
---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---
---

## 📤 Dispatch block (EN) — PEEK micro-tube supplier (bus liner)

> **Окремий лист, бо пару смуг ID/OD тримає ЕКСТРУЗІЯ, а не друк-бюро:** DMLS-лист вище називає трубку лише як спряжену деталь каналу (§Processing п.11) і її смуг не питає — бюро не відповідає за чужий процес. Хто трубку купує й ставить, не питає жоден із двох листів свідомо: слот лайнера в порядку виробництва — відкритий ⚖️ ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.34). Індекс — [`rfq_registry`](rfq_registry.md) §4.C.
> **Немає свідомо:** номінального натягу трубки на дроті (відкритий ⚖️ HW.34) — «roughly 1.0 mm ID» у листі є класом розміру, а не номіналом, і лист каже це вголос · стінки як вимоги (процес її не тримає) · трекер-ID/канон-рефів.
> ⚠️ **Дім тимчасовий:** per-component лист у крос-доменному файлі йде проти конвенції [`rfq_registry §5`](rfq_registry.md) і переїжджає в аркуш «Анкер hardware», щойно той авториться (сьогодні рядок [`rfq_registry §1`](rfq_registry.md) несе 🟡).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота, у лист вона НЕ йде.

**Subject line:** Enquiry — PEEK micro-tube, roughly 1.0 mm ID × 1.3 mm OD: the ID and OD tolerance bands you hold (R&D quantities)

**Scope of request.** We are developing a titanium sensor anchor that sits inside a living tree for twenty years; one small part of it is a PEEK tube that insulates a conductor. Before we fix that tube's dimensions we need to know what your process holds. Answering commits neither side to anything, and inline answers in this email are fine.

**The part.** A PEEK tube that sits tight on a Ø1.0 mm titanium wire and, together with the wire, goes into a Ø1.35 mm machined titanium channel. Our specification currently gives it as a 0.15 mm wall — roughly 1.0 mm ID and 1.3 mm OD. We know extrusion holds ID and OD rather than wall thickness, so the tube will be expressed by ID and OD, and your bands are the input for choosing those numbers. **We have deliberately not fixed how tight the tube sits on the wire**, so please do not read an ID nominal into "roughly 1.0 mm".

**What we ask you to provide**

1. **The ID band and the OD band you can hold at this size — both, not the wall**, because they judge two different fits. The ID decides the fit of the tube on the wire: the tube's ID band and the wire's own diameter band together must fit inside a window of **about 21 µm on diameter** — at the tight end the tube wall yields in the cold, at the loose end the fit is lost in the heat. The OD decides the fit of the tube in the channel, where the nominal diametral clearance is **50 µm** and has to absorb your OD band and the channel's machining band together. Quote the bands your process actually holds, not bands chosen to fit these numbers: a wider band is a useful answer, not a failed one — it tells us to select, machine or heat-assemble instead of buying the fit — and the 21 µm window is optimistic in any case, because it ignores creep and form error.
2. **How you measure ID and OD**, and how often (per length, per lot, or by sampling).
3. **Whether you make the ID to a nominal we specify** rather than to a catalogue size, and whether you could sort or grade tubes by measured ID.
4. **Material:** the PEEK grade you would extrude this from, and the certificate that comes with a lot.
5. **Commercial:** price at R&D quantities (per metre or per cut piece), minimum order quantity, lead time, currency and validity of the quote.

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---
---

## 📤 Dispatch block (UA) — опромінювач, ГІЛКА A стерилізації (low-dose gamma 15 кГр)

> **Окремий лист, бо адресат інший:** установа з гамма-опромінювачем, а предмет — доставлена й задокументована доза на запакованих зразках із ферментним стеком (ГІЛКА A, [`01_04 §6.3`](../../01_04_CODIT_and_Xylemointegration.md) крок A4), не деталь і не вимір. **Мова українська**, бо кандидати трекера вітчизняні: Чорнобиль НДІ радіаційної медицини / Київ ІРОНЦ ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.22). **Не контактовано; наявність джерела й діапазон доз НЕ перевірені — лист їх питає, а не припускає.** Індекс — [`rfq_registry`](rfq_registry.md) §1 рядок «Стерилізація» · §4.E. ⏳ Станом на 2026-09-13.
> **Несе як дзеркало канону (дім кожного):** доза **15 кГр** і «свідомо нижче за 25 кГр» — [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md) (рядок low-dose і рядок «Стандартна медична доза») · Co-60 як НАША специфікація, установі не приписаний — там же · «низька потужність, охолодження» — там же, **без чисел** · опромінення в упаковці (блістер) — [`01_04 §6.3`](../../01_04_CODIT_and_Xylemointegration.md) кроки A3–A4 · після опромінення **4–8 °C, темнота** — там же · немедичний рівень (❌ SAL 10⁻⁶ · ISO 5 · ендотоксини) — там же, 🟢-блок · дві серії «з ZIF ⊥ без ZIF» — [`01_04 §6.5`](../../01_04_CODIT_and_Xylemointegration.md) + [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) §HW.22 · диск **Ø16 × 1 мм** — [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · ⛔ PTFE-мембрана й ущільнювальні кільця поза замовленням (ГІЛКА B — [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md)); причина «PTFE (> 10 кГр)» — [`01_04 §6.3`](../../01_04_CODIT_and_Xylemointegration.md), нота «Чому НЕ terminal gamma».
> **Питає, бо канон цього не несе:** **допуск дози і її тип** — §6.2/§6.3 кажуть лише «15 кГр» і не уточнюють, мінімум це, номінал чи максимум, тож ⛔ жодного «±N %» лист не пише · потужність дози, тривалість, температура в зоні, охолодження — чисел канон не має, а §HW.22 прямо називає себе сліпим до ефектів потужності дози й до пакувального середовища · **джерело** — desk-присуд §HW.22 стоїть на Комптоні при 1.25 МеВ, тож інше джерело лист просить назвати для окремої оцінки, ⛔ не стверджуючи, що воно гірше · дозиметрія, карта дози, сертифікат — жоден стандарт не названо, лише «за яким» · зберігання ДО опромінення й дорога до установи — канон задає 4–8 °C лише ПІСЛЯ кроку A4, тож «від приймання» є нашим проханням · партія, ціна, строки, ланцюг передачі — кількості зразків канон не фіксує.
> **Немає свідомо:** порогів приймання (втрата активності ≤ 20 % і CV ≤ 25 % — [`01_04 §6.5`](../../01_04_CODIT_and_Xylemointegration.md)): це наш аналіз, не послуга опромінювача · in-silico чисел §HW.22 і хімічного механізму · трекер-ID і канон-рефів · імен кандидатів · **підстави для кілець:** канон групує їх із мембраною в ГІЛКУ B, але про EPDM під гаммою не каже нічого, тож лист дає причину лише для PTFE. ⚠️ **Контрольні неопромінені зразки (п. 14 листа) — додаток ПОНАД канон:** «до/після» §6.5 не відокремлює втрату активності за дорогу й зберігання від дії дози; лист лише питає, чи установа це допускає, а чи вони потрібні — рішення HW.22.
> ⚠️ **Дім тимчасовий:** per-component лист у крос-доменному файлі йде проти конвенції [`rfq_registry §5`](rfq_registry.md) і переїжджає в аркуш «Стерилізація» ([`rfq_registry §1`](rfq_registry.md)), щойно той авториться.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота, у лист вона НЕ йде.

**Тема:** Запит щодо гамма-опромінення дослідницьких зразків дозою 15 кГр — металеві деталі з іммобілізованими ферментами (немедичне застосування)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо титановий сенсорний анкер, який встановлюється в стовбур живого дерева й живиться від ферментного біопаливного елемента. Перед встановленням деталі з нанесеними ферментами треба знезаразити — знищити дереворуйнівні гриби й бактерії, зберігши активність ферментів. Етиленоксид, автоклав і сухий жар для цього непридатні: вони денатурують ферменти. Тому наша специфікація процесу передбачає гамма-опромінення (Co-60) **низькою дозою 15 кГр** — свідомо нижче за стандартну медичну дозу 25 кГр.

Це запит пропозиції та інформації про ваші можливості, а ще не замовлення: відповідь ні до чого не зобов'язує жодну сторону, і відповідати можна просто в тексті листа.

**Рівень вимог — не медичний.** Зразки призначені для дерева, не для людини чи тварини, тож нам **не потрібні** валідація стерильності медичного рівня (SAL 10⁻⁶), чисті приміщення класу ISO 5 чи тест на ендотоксини. Дозу задаємо ми; від вас потрібні **виміряна доставлена доза й документ про неї**.

**Що опромінюється**

1. **Зразки двох типів:** плоскі металеві диски **Ø16 × 1 мм** і повні титанові анкери (їхні габарити надішлемо із замовленням) — просимо оцінити обидва варіанти. На поверхні — ферменти (FAD-залежна глюкозодегідрогеназа, лакказа), осмієвмісний редокс-полімер, вуглецеві нанотрубки, гідрогель на основі хітозану, мембрана на основі Nafion; у частини зразків — нанозим на основі цеолітного імідазолатного каркаса з кобальтом, міддю й церієм. Повний перелік матеріалів і паспорти безпеки надамо на запит.
2. **Упаковка:** зразки надходять уже знезараженими з поверхні й **запечатаними в блістерну упаковку**, опромінюються **в упаковці, без розкриття**. Просимо повідомити ваші вимоги до упаковки (матеріал, габарити, маркування) і чи використовуєте ви індикатори опромінення на упаковці.
3. **Дві серії, що порівнюються між собою:** зразки **з нанозимом і без нього**. Ми перевіряємо, чи впливає нанозим на збереження активності ферментів після опромінення, тож **обидві серії мусять отримати однакову дозу**. Просимо підтвердити, що їх можна опромінити в одному циклі, розмістивши так, щоб різниця доз між серіями була мінімальною, і повідомити, як ви це задокументуєте.
4. **Не опромінюються:** мембрани з PTFE та ущільнювальні кільця в це замовлення **не входять** — вони проходять окрему гілку процесу (автоклав або етиленоксид). Для PTFE причина — деградація вже за доз понад 10 кГр; кільця йдуть тією самою гілкою разом із мембраною.

**Просимо повідомити**

*Джерело й доза*

5. **Джерело випромінювання** — ізотоп і тип установки. Нашу оцінку сумісності ферментного шару з опроміненням виконано саме для гамма-випромінювання Co-60; якщо ви пропонуєте інше джерело, скажіть про це прямо — таке джерело ми мусимо оцінити окремо, перш ніж погодитися.
6. **Доза 15 кГр і допуск.** Чи можете ви забезпечити 15 кГр для невеликих дослідних партій, і яку **мінімальну й максимальну дозу в зразках** гарантуєте для такого завантаження? Допуску наша специфікація поки не містить — назвіть той, який ви реально тримаєте.
7. **Потужність дози й тривалість:** яку потужність (кГр/год) ви пропонуєте для 15 кГр, скільки триватиме опромінення і чи є вибір потужності. Наша специфікація вимагає низької потужності, але числа не фіксує, тож просимо варіанти.
8. **Температура:** яка температура в зоні опромінення, чи реєструється вона протягом циклу, **чи можливе опромінення з охолодженням** і до якої температури, і чи впливає охолодження на розподіл дози.

*Дозиметрія й документи*

9. **Карта дози й дозиметрія:** чи виконуєте ви картування дози для нового типу завантаження; яке відношення максимальної дози до мінімальної досяжне для невеликих деталей; які дозиметри ставите в кожному циклі; як калібровано дозиметричну систему і з якою невизначеністю виміряно дозу. Чи ведете дозиметрію за документованим стандартом (міжнародним чи національним) — якщо так, за яким?
10. **Сертифікат (протокол) опромінення:** що він містить — щонайменше ідентифікатор партії, дату, виміряні мінімальну й максимальну дози, потужність дози або тривалість і температурні умови. Просимо знеособлений зразок документа.

*Зберігання й передача*

11. **Холодовий ланцюг:** після опромінення наш процес вимагає зберігання **при 4–8 °C у темряві**. Чи можете ви тримати ці умови **від приймання до відправлення** (тобто й до опромінення), і як забезпечуєте їх під час відключень електроенергії?
12. **Приймання й повернення:** чи приймаєте ви зразки кур'єрською або поштовою доставкою в термоконтейнері, чи лише особисто; як повертаєте опромінені зразки і хто відповідає за температуру в дорозі.
13. **Документування передачі:** чи оформлюєте ви акт приймання-передачі з переліком ідентифікаторів зразків, станом упаковки й датою — при прийманні й при поверненні; чи дозволяєте вкласти в посилку наш термологер і чи може він лишатися в ній під час опромінення.
14. **Контрольні зразки (опційно):** чи можна, щоб частина зразків їхала тією самою партією й зберігалася в тих самих умовах, але **не опромінювалася** — як контроль впливу дороги й зберігання.

*Обсяг, ціна, строки*

15. **Мінімальне замовлення:** мінімальна партія або мінімальна вартість циклу; чи можна опромінити поодинокі зразки; чи опромінюються вони разом із продукцією інших замовників.
16. **Пробний цикл:** чи можливий пробний прогін із макетами без ферментів — для карти дози й перевірки упаковки — перед опроміненням справжніх зразків, і скільки він коштує.
17. **Ціна:** за цикл і/або за зразок; окремо — картування дози, дозиметрія, зберігання в холоді, пробний цикл.
18. **Строки:** черга до початку, тривалість виконання, строк повернення зразків.
19. **Умови співпраці:** на якій підставі ви надаєте такі послуги стороннім організаціям (договір, дозвільні документи), які документи потрібні від нас (реквізити, лист-запит, перелік матеріалів) і форма оплати.

**Конфіденційність і публікація.** Технічна специфікація нашого процесу відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну угоду щодо комерційних умов (ціни, строки). Результати нашої перевірки зразків після опромінення можуть бути опубліковані — повідомте, будь ласка, чи маєте умови щодо згадки вашої установи або опису режиму опромінення.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---
---

## 📤 Dispatch block (EN) — PTFE membrane supplier (cathode gas-diffusion layer)

> **Окремий лист, бо адресат інший:** виробник або дистриб'ютор мембрани, а предмет — матеріал із даними випробувань і зразки, не деталь і не послуга. Кандидати трекера — Gore-Tex industrial · Donaldson · український постачальник ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.25); **TBD, не контактовано, спроможність не перевірена.** Індекс — [`rfq_registry`](rfq_registry.md) §1 рядок «Покриття / біо» · §4.E. ⏳ Станом на 2026-09-13.
> **Несе як дзеркало канону (дім кожного):** e-PTFE ⊥ d-PTFE · пори **0.2–1.0 µm** · товщина **20–100 µm** · крайовий кут **> 110°** · фіксація механічним обтиском **без клеїв** (підстава канону — «контамінація», лист нічого не домальовує) — усе [`01_04 §5.3`](../../01_04_CODIT_and_Xylemointegration.md) · приймання **≥ 1 м H₂O** як детектор ДЕФЕКТУ, а не вимір пор — [`01_04 §5.6`](../../01_04_CODIT_and_Xylemointegration.md) (≈ 9.8 кПа — лише перерахунок одиниць; «запас великий» — інверсія [`01_04 §5.3`](../../01_04_CODIT_and_Xylemointegration.md), без її чисел) · головний ризик = втрата гідрофобності від смоляних кислот і терпенів — [`01_04 §5.3`](../../01_04_CODIT_and_Xylemointegration.md), 🔑-блок · утримання електроліту від випаровування — [`01_04 §5.1`](../../01_04_CODIT_and_Xylemointegration.md) · ГІЛКА B разом із кільцем: автоклав **121 °C / 15 psi / 30 хв** або EtO **50 °C / 40 % RH** з аерацією **7–14 днів** — [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md) (крок B1 у [`01_04 §6.3`](../../01_04_CODIT_and_Xylemointegration.md) називає 7 днів — усередині смуги) · bubble point до/після, **Δ ≤ 5 %** — [`01_04 §6.5`](../../01_04_CODIT_and_Xylemointegration.md) · мембрана НЕ опромінюється — [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md) · pH **4.5–5.5** як ОБ'ЄДНАННЯ двох смуг канону — [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) 5.0–5.5 ⊥ [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md), [`01_04 §5.2`](../../01_04_CODIT_and_Xylemointegration.md) і [`01_04 §5.6`](../../01_04_CODIT_and_Xylemointegration.md) 4.5–5.5; у листі «still being refined», присуд — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.3 · компоненти соку без концентрацій, як «working composition» — [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (провенанс не звірено, пор. [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) §2) · EPDM **70 Shore A** — [`01_04 §5.6`](../../01_04_CODIT_and_Xylemointegration.md), дім матеріалу [`02_02 §3.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · фланець **Ø25 мм** — [`01_01 §1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (Zone 3, frozen) = поле `flange_diameter_mm` у `tools/cad/cem/cathode_flange.json` · бічна грань як місце мембрани — [`01_04 §5.5`](../../01_04_CODIT_and_Xylemointegration.md) п. A.
> **Питає, бо канон цього не несе:** визначення рейтингу пор (номінал · середній потоковий · максимальний — «0.2–1.0 µm» цього не каже) і метод розподілу пор · 🔴 **bubble point і тиск входу води — ОКРЕМО, bubble point — з названою рідиною:** числа [`01_04 §5.6`](../../01_04_CODIT_and_Xylemointegration.md) «100 / 199 / 498 кПа (θ = 110°)» пораховано Young–Laplace для ВОДИ (4 · 0.0728 · |cos 110°| / 1.0 µm = 99.6 кПа), тобто це тиск входу води; вендорський bubble point міряють змочувальною рідиною, і від θ води він не залежить. ⛔ Тому ці числа в лист НЕ йдуть: зіставлені з даними іншої конвенції, вони дали б хибний вирок · метод і тип крайового кута · пористість і повітропроникність — замінюють **прийняті** ε і τ O₂-бюджету §5.3 · проникність водяної пари — вимога §5.1 чисел не має · поведінка після циклів ГІЛКИ B · хімічна сумісність, зокрема підкладки й клею в продукті як поставленому · придатність до обтиску без клею · формати зразків (висоти бічної грані немає: `flange_thickness_mm` у тому ж CEM — PLACEHOLDER за його `_note`) · MOQ · строки · ціна.
> **Немає свідомо:** порогу деградації θ ≈ 90° і 12-тижневого тесту (наш стенд, не спека постачальника) · запасу O₂ і польових навантажень §5.3 · нашого 30-см апарата · трекер-ID і канон-рефів. ⚠️ **Стик стрічки (п. 10 листа) — наш висновок із геометрії §5.5 п. A, канон про нього мовчить:** мембрана на бічній грані диска є стрічкою, а [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) §HW.25 прямо називає дефект шва тим, чого Young–Laplace не рахує.
> ⚠️ **Дім тимчасовий:** per-component лист у крос-доменному файлі йде проти конвенції [`rfq_registry §5`](rfq_registry.md) і переїжджає в аркуш рядка «Покриття / біо» ([`rfq_registry §1`](rfq_registry.md)), щойно той авториться.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота, у лист вона НЕ йде.

**Subject line:** Enquiry — microporous PTFE membrane (expanded or dense), 0.2–1.0 µm pore rating, 20–100 µm thick: technical data and R&D samples

**Scope of request.** We are developing a titanium sensor anchor that is installed in the trunk of a living tree and powered by an enzymatic bio-fuel cell. Its cathode takes oxygen from the air through an outer PTFE membrane, which has to let oxygen in and keep liquid water out — rain, dew and snow — because a flooded cathode stops producing current. We are looking for a supplier of that membrane. This is an enquiry for technical data and R&D samples, not yet an order; answering commits neither side to anything, and inline answers in this email are fine.

**The membrane we need**

- **Material:** expanded PTFE (e-PTFE) or dense PTFE (d-PTFE) — tell us which you supply.
- **Pore rating:** 0.2–1.0 µm.
- **Thickness:** 20–100 µm.
- **Water contact angle:** greater than 110°.
- **Fixing:** held only by mechanical clamping along its edges onto a titanium part — **no adhesive of any kind** (contamination risk).
- **Position:** the outermost layer over the cathode's catalytic layer, on the side face (perimeter) of a titanium flange 25 mm in diameter. The height of that face and the clamp design are not final.
- **Acceptance criterion we already hold:** the membrane must withstand a water column of **at least 1 m H₂O (about 9.8 kPa)** without water entry. We use it as a screen for defects such as pinholes, not as a measure of pore size: on our own calculation for ideal pores in the rating above the margin is large, so a failure at 1 m would mean a defect.

**What we ask you to provide**

1. **Data sheet** for the grade you would offer, with the **test method, unit and conditions** for every property — a figure without its method is one we cannot compare.
2. **Pore size:** how your pore rating is defined (nominal, mean flow pore size, or maximum pore size), the method you use to measure the pore-size distribution and the standard you follow if any, and a typical distribution for this grade.
3. **Bubble point and water entry pressure — as two separate figures.** For the bubble point, name the wetting liquid, the test area and the pressure ramp. For the water entry pressure — the pressure at which liquid water first passes through the dry membrane — give the method, area and ramp as well. They are different measurements, and we use them for different decisions. Please also say whether you test water entry pressure **per lot**, or can state per lot that the 1 m criterion above is met.
4. **Water contact angle** as delivered: value, method (static, advancing or receding), test liquid and conditions, and whether the surface carries any treatment beyond PTFE itself. **Retention matters more to us than the initial value:** in service the membrane meets tree resin, whose resin acids and terpenes are surface-active, and loss of hydrophobicity is the failure we are most concerned about. Do you have data on contact angle or water entry pressure after exposure to surfactants or resin-like compounds, or after outdoor ageing?
5. **Porosity and air permeability** — porosity in %, and air permeability with method, unit and test pressure differential. Our oxygen-transport estimate currently rests on an assumed porosity; your measured values replace that assumption.
6. **Water vapour transmission rate**, with method and conditions. The membrane also has to limit evaporation of the thin aqueous electrolyte film beneath it, so we need to know how much vapour passes.
7. **Construction:** is the membrane supplied unsupported or on a backing? If on a backing, name its material, give the thickness of the membrane and of the backing separately, and say whether any adhesive or binder is present in the product as supplied.
8. **Sterilisation compatibility.** The membrane will **not** be gamma-irradiated. Before assembly it goes, together with an EPDM seal, through **one** of these cycles:
   - **autoclave: 121 °C / 15 psi / 30 min**, or
   - **ethylene oxide: 50 °C / 40 % RH, followed by aeration of 7–14 days**.

   Tell us whether the membrane — and any backing — tolerates each cycle, and share any data on bubble point, water entry pressure or contact angle before and after. Our own acceptance check is the **bubble point before and after the cycle, changing by no more than 5 %**.
9. **Chemical compatibility.** In service the membrane may be in contact with:
   - aqueous media at **pH within 4.5–5.5** (the exact band is still being refined on our side): the electrolyte film beneath the membrane, and tree sap. Our in-vitro reference medium is a synthetic xylem sap of working composition — dilute organic acids (malic, oxalic) and salts (potassium nitrate, calcium chloride, magnesium sulfate) at a few millimolar or less;
   - tree resin (resin acids, terpenes) — see item 4;
   - an **EPDM elastomer, 70 Shore A**, in the same assembly.

   Tell us of any known incompatibility, including for a backing or surface treatment if present.
10. **Mechanical fixing without adhesive.** Is your membrane suitable for being held only by clamping along its edges? In particular: whether sustained clamping damages it or opens a leak path at the clamped edge over time; what edge design you recommend or advise against; whether it can be wrapped around a cylinder 25 mm in diameter without damage; and, if it is fitted as a band around that cylinder, how the joint where the two ends meet can be closed without adhesive.
11. **Sample formats:** the sizes in which you can supply samples (sheet, roll width, die-cut pieces), the smallest die-cut piece you can make, and whether you can cut to a drawing we supply. The membrane geometry on our part is not final, so sheet or roll stock we can cut ourselves is the most useful first sample.
12. **Documentation per lot:** certificate of conformance or test report, and lot traceability.
13. **Commercial:** price of R&D samples, minimum order quantity for samples and for later volumes, lead time, currency and validity of the quote, and a technical point of contact.

**Confidentiality.** The technical specification is openly published, so no confidentiality agreement is needed to discuss it; we are happy to sign your standard mutual CDA covering commercial terms (prices, schedules, QC data).

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## Cross-references

| Ресурс | Що бере |
|---|---|
| [`rfq_registry`](rfq_registry.md) | procurement-індекс · §4.B метал-constraint (hard-gate §A.4) · §3 IP/CDA/NDA-політика |
| [`anchor_alloy_rfq`](anchor_alloy_rfq.md) | парний Ti-coupon RFQ (Grade-cert контекст — критерій C6 §A.2) · стиль-еталон |
| [`01_02 §1.6/§1.7/§3.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | SLM≠EBM · HIP · dehydrogenation bake · ZnO-Ta-заборона (§A.4 дім) |
| [`01_01 §5/§6`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | гіроїд-геометрія + ізоеластичність/пористість як CEM-параметр (C2 геометрія-дім) |
| [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | шина: канал Ø1.35 як первинний датум · вхід із радіусом · лайнер (зазор 50 мкм, вікно натягу) · тягнутий дріт — §Processing пп. 11/12 і лист постачальникові трубки |
| [`02_06 §8.1.1`](../../02_06_Unit_Economics_and_BOM.md) | vendor-кваліфікаційні критерії DMLS-хабів (Gr5 baseline **І** V-free імплант-сплави · ≥60% пористості · ISO 13485) — дім порогів C2/C6, і він ⛔ забороняє звужувати вимогу до ELI |
| [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) / [`00_02 §4.2`](../../00_02_Academic_Integration_and_IP.md) | defensive-publication + ліцензійна матриця + trade-secret-scope (NDA §C дім) · Аблязов UA-юр-review |
| [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md) · [`01_04 §6.3`](../../01_04_CODIT_and_Xylemointegration.md) · [`01_04 §6.5`](../../01_04_CODIT_and_Xylemointegration.md) | лист опромінювачеві: доза 15 кГр · «низька потужність, охолодження» без чисел · опромінення в упаковці · 4–8 °C у темряві після кроку A4 · серії з ZIF ⊥ без ZIF · ГІЛКА B поза замовленням; для мембранника — цикли ГІЛКИ B і Δ bubble point |
| [`01_04 §5.3`](../../01_04_CODIT_and_Xylemointegration.md) · [`01_04 §5.6`](../../01_04_CODIT_and_Xylemointegration.md) | лист мембранникові: спека (тип · пори · товщина · кут · фіксація без клеїв) · приймання ≥ 1 м H₂O як детектор дефекту · EPDM-сумісність |
| [`01_01 §1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`02_02 §3.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | фланець Ø25 (`cathode_flange.json` §`flange_diameter_mm`) · EPDM 70 Shore A · робочий склад синтетичного соку |
| [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) §HW.22 · §HW.25 | межа desk-присуду ZIF (Co-60; сліпий до потужності дози) · інверсія Young–Laplace під числами §5.6 — підстави питань, у листи НЕ йдуть |
| [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md) | One-Home — реєстрація артефакту (промоція → registry §1) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | **BIZ.17** (procurement RFQ-layer) · UNI.2 (лаб-доступ) · UNI.14 (CDA/NDA legal) · BIZ.6/BIZ.20 · HW.22 (стерилізація) · HW.25 (PTFE-мембрана) · HW.3 (присуд pH соку) |

> **Статус-нагадування:** 🟡 draft-шаблони. Ваги/пороги (§A.1/§A.3/§B.2) + NDA-поля (§C) — `PLACEHOLDER` під founder/юр-рішення, **не** вигадані. NDA — **draft, юр-review обов'язковий** (§C.7).
