# EBFC Chemistry — RFQ Spec-Sheets (Gen 2.0 stack, CRO / supplier-ready)

> **Що це:** дистильовані з канону **специфікації для розсилки RFQ** контрактним лабораторіям (CRO) та
> постачальникам — щоб не починати листування з нуля. Один аркуш на компонент: що зробити · якість/QC ·
> кількість · формат поставки · lead time · IP/конфіденційність.
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (EBFC-хімія рядок · конвенція · hard-constraint доми §4.A).
> **Статус:** 🟡 робочий артефакт (не канон). **Усі числові значення тут — дзеркало канону**
> ([`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) / [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5 / L1); **правити у домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Цей аркуш реферить,
> не є джерелом істини про хімію.
> **Cross-ref:** [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (анод+матриця+мембрана) ·
> [`01_03 §2.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (катод) ·
> [`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (CRO-нюанси/bottlenecks) ·
> [`L1`](../ebfc/in_silico/L1_protein_architecture.md) (ген+11 N→Q — **owner послідовності**) ·
> [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5 (хімічний стек) / HW.24 (staged-validation) ·
> [`00_02`](../../00_02_Academic_Integration_and_IP.md) (ЧНУ нанохімія — ZIF за співавторство).
>
> ℹ️ **IP:** **defensive-publication** постава ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) —
> специфікації **відкриті** (вже публічні як prior art; патенту немає). CRO-CDA = **стандартні комерційні
> умови** (ціни/строки/QC), **НЕ** для захисту новизни. Окремий NDA доречний лише для **нерозкритого**
> (production-дані / ключі), не для tech-специфік.

---

## 0. Як користуватись + cover-note для RFQ

1. Один аркуш = один RFQ-пакет. Скопіювати секцію → у запит постачальнику.
2. **Перед відправкою:** CDA на комерц-умови (§IP). Cover-note: коротка мета («academic R&D,
   tree-integrated EBFC») + потрібне для квоти (синергія й так публічна — prior art).
3. **Послідовність запуску — за критичним шляхом** (§6): спершу 🔴 dgrFAD-GDH (4–8 тиж), паралельно
   геніпін (закупка, найшвидше) та ZIF; мембрана — окремий fluoropolymer-вендор.
4. Числа звіряти з каноном перед відправкою (вони дзеркало; якщо канон оновився — оновити тут).

---

## 1. Spec A — dgrFAD-GDH рекомбінантна експресія · 🔴 КРИТИЧНИЙ ШЛЯХ (4–8 тиж, пріоритет #1)

| Поле | Специфікація (дзеркало `00_07` HW.5 / L1) |
|---|---|
| **Продукт** | Деглікозильована FAD-залежна глюкозо-дегідрогеназа (dgrGcGDH), 600 aa |
| **Походження** | *Glomerella cingulata*, UniProt **G8E4B5** (baseline; *Aspergillus* — альт.) |
| **Хост експресії** | **Pichia pastoris** (секреторна). **НЕ** *E. coli* (inclusion bodies) — `01_03 §3.7` |
| **Деглікозилювання** | **Gene-level (preferred):** синтетичний ген із вбудованими **11 N→Q** → *Pichia* фізично не глікозилює → **PNGase F не потрібен**. Fallback: PNGase F / Endo-H **тільки native conditions** (без SDS/DTT) |
| **Послідовність** | 600 aa, 11 N→Q (N71/100/192/200/249/258/271/355/380/405/463) — **owner [`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md)**; ген синтезувати з L1 (не дублюю рядок тут — single source проти drift) |
| **Кофактор** | FAD (нативний; expression host забезпечує флавінілювання) |
| **QC / acceptance** | SDS-PAGE (один бенд ~600 aa, аглікозильований MW), активність (glucose-DH assay, U/mg), відсутність H₂O₂ (O₂-незалежність), MS-підтвердження N→Q-сайтів |
| **Кількість** | пілот: мг-масштаб для Stage 2 Ti-coins (HW.24); уточнити після квоти |
| **Формат** | ліофілізат або стабілізований буфер; CoA + QC-звіт |
| **IP** | ген відкритий (defensive disclosure / L1); CRO лише експресує; CDA — §IP |

> ⚠️ **Gate перед заморожуванням гена (sequence freeze ≠ now):** два in-silico кроки на dgr-мутанті ще
> відкриті ([`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md), → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5.IS):
> - **CHEM.11 (anti-aggregation):** 11 знятих гліканів оголюють гідрофобну поверхню → 4 hotspots
>   (Gln71/200/258/405). Перед CRO: Aggrescan3D + компенсаторні полярні мутації поруч.
> - **CHEM.10 (genipin-shield):** Lys109/Lys262 на виході електрона → мутувати **Lys→Arg** (інертний до
>   геніпіну), щоб зшивка не блокувала Os-докінг.
>
> **Тому:** RFQ на **квоту/спроможність/строки** можна слати зараз; **фінальний ген заморожувати
> після** CHEM.11+CHEM.10. У cover-note: «sequence to be finalized; quote against capability & timeline».

---

## 2. Spec B — Cu-Co-Ce ZIF laccase-mimic нанозим (катод DET)

| Поле | Специфікація (дзеркало `01_03 §2.2` / HW.5) |
|---|---|
| **Продукт** | Трьохметалевий **nCoCuCeZIF** нанозим (альт. nCuCeAuZIF) — laccase-mimic для ORR/DET |
| **Метод** | Сольвотермальний синтез |
| **Розмір частинок** | **40–80 нм** — жорстко в T&C + **SEM-контроль** (макрокристали відпадуть з електрода — `01_03 §3.7`) |
| **Гібрид** | поєднання з Laccase на MWCNT (резерв безферментного каталізу при денатурації) |
| **QC / acceptance** | SEM (розмір/морфологія), XRD (фаза ZIF), ICP/EDS (Cu:Co:Ce стехіометрія), BET (площа) |
| **Цільові показники** (дзеркало) | ×10 power density vs чиста Laccase; 75% активності після 10 днів; **+7.5%** з 0.25 М NaCl (vs −41.7% чиста Laccase) — **значення в `01_03 §2.2`** |
| **Партнер-опція** | Нанохімія **ЧНУ** або НАН України — за співавторство Q1 (`00_02`); або комерційний CRO |
| **IP** | за академ-партнерства — співавторство (`00_01 §8`); CDA — §IP |

---

## 3. Spec C — Геніпін (genipin) закупка · найшвидший пункт (просто purchase)

| Поле | Специфікація (дзеркало HW.5 / `01_03 §2.1` Шар 4) |
|---|---|
| **Продукт** | Genipin (нетоксичний зшивач хітозану замість глутаральдегіду) |
| **Чистота** | **>98%** |
| **Постачальник** | Challenge Bioproducts (приклад; ~**$50–80/г** — дзеркало HW.5) |
| **Зберігання** | у темряві, **@4°C** |
| **Acceptance / тест** | вхідний тест cross-linking хітозану при **pH 4.5** (xylem-середовище) |
| **Кількість** | г-масштаб для матриці Stage 2; уточнити |
| **Note** | закупка, не synth → найкоротший lead time зі стеку |

---

## 4. Spec D — Nafion-g-PSBMA цвітеріонна мембрана (SI-ATRP) · bottleneck-вендор

| Поле | Специфікація (дзеркало `01_03 §2.1` Шар 5 / HW.5) |
|---|---|
| **Продукт** | Nafion з прищепленим PSBMA (poly-sulfobetaine) через **SI-ATRP** — anti-biofouling |
| **⚠️ Bottleneck** | пришивка ATRP-ініціатора потребує переведення Nafion у **сульфонілхлоридну форму** → **вимагати досвіду з фторполімерами** (`01_03 §3.7`) |
| **Lead time** | **3–6 тиж** (дзеркало HW.5) |
| **Цільові показники** (дзеркало) | σ(H⁺) **45.2 мС/см**; 8 H₂O/ланцюг; UCST winter-lock **@5°C** — **значення в `01_03 §2.1`** |
| **QC / acceptance** | провідність (EIS), anti-fouling (абієтинова кислота/смоли), UCST-цикл (−10°C→+25°C регідратація) |
| **IP** | CDA — §IP (fluoropolymer-CRO — спец-вимога вище) |

---

## 5. Spec E — CNC (целюлозні нанокристали) закупка/синтез

| Поле | Специфікація (дзеркало HW.5 / `01_03 §2.1`) |
|---|---|
| **Продукт** | Целюлозні нанокристали (псевдопластика матриці проти тигмоморфогенезу) |
| **Завантаження** | **2–6%** у genipin-chitosan-CNC матриці |
| **Джерело** | ENERON (закупка) **або** кислотний гідроліз з alpha-целюлози |
| **QC** | розмір/aspect ratio (TEM/AFM), кристалічність |

---

## 6. RFQ dispatch checklist + послідовність (критичний шлях першим)

- [ ] 👤 **CDA-шаблон** (комерц-умови) — §IP.
- [ ] 👤 **Spec A (dgrFAD-GDH)** — RFQ на квоту/строки **зараз** (🔴 4–8 тиж тримає весь Stage 2). Sequence freeze — після CHEM.11+CHEM.10.
- [ ] 👤 **Spec C (геніпін)** — закупка паралельно (найшвидше).
- [ ] 👤 **Spec B (ZIF)** — RFQ або ЧНУ-партнерство ([`00_02`](../../00_02_Academic_Integration_and_IP.md)) паралельно.
- [ ] 👤 **Spec D (мембрана)** — окремий fluoropolymer-вендор (3–6 тиж).
- [ ] 👤 **Spec E (CNC)** — закупка ENERON.
- [ ] 👤 Усі deliverables → **Stage 2 Ti-coins (HW.24)**: in-vitro CV/EIS у синтетичному ксилемному соку (рецептура — біо-хаб ЧНУ, [`00_02`](../../00_02_Academic_Integration_and_IP.md)), 30-day stability, chloride-tolerance (0.25 М NaCl), UCST winter-lock. Електрод із «вушком» під потенціостат-кліпсу, A=2 см².

> **Залежність:** Spec A–E живлять **Stage 2** гейту HW.24 (Ti-coins) → Stage 3 (full anchor) → Stage 4
> (100 шт). Передчасне замовлення 100-DMLS-партії без Stage 2/3 — методологічна помилка ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24).

---

## 📤 Dispatch block (EN) — paste into vendor email

> Ready-to-send English text. Working body above stays Ukrainian. Anything our side
> must NOT disclose is deliberately absent — **немає:** приклад-ціни й наших lead-time-оцінок
> (§3/§1/§4 — price/time anchor проти нас), імен постачальників і академ-каналу (кожен адресат
> сліпий щодо решти), позицій 11 N→Q і gate-контексту §1 (послідовність ще не заморожена),
> трекер-ID/канон-рефів, статус-маркерів. **Цільові показники §2/§4 стоять окремою
> informational-рамкою, НЕ як acceptance.**
> **Один item = один лист** — беремо потрібний sub-блок §Item specification + спільні секції.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

| Item | Subject |
|---|---|
| A enzyme | RFQ — recombinant deglycosylated FAD-dependent glucose dehydrogenase, *Pichia* expression (R&D pilot) |
| B nanozyme | RFQ — tri-metallic Co/Cu/Ce ZIF laccase-mimic nanozyme, solvothermal synthesis, 40–80 nm |
| C genipin | RFQ — genipin >98%, gram scale, cold-chain |
| D membrane | RFQ — Nafion surface-grafted with PSBMA via SI-ATRP (fluoropolymer chemistry) |
| E CNC | RFQ — cellulose nanocrystals, R&D quantity (purchase or acid hydrolysis) |

### Scope of request

We are an R&D group developing a tree-integrated enzymatic bio-fuel cell for forest monitoring, and we are requesting a quotation for the item specified below. Volumes are R&D-scale, with possible repeat orders once the design is validated. The technical specification is openly published, so no confidentiality agreement is required to discuss it; we are happy to sign your standard mutual CDA covering commercial terms (prices, schedules, QC data).

### Item specification

**A — recombinant deglycosylated FAD-dependent glucose dehydrogenase (dgrGcGDH), ~600 aa**

- Source organism: *Glomerella cingulata*, UniProt **G8E4B5** as the baseline; an *Aspergillus* homologue is an acceptable alternative if you have an established construct.
- Expression host: ***Pichia pastoris*, secretory. *E. coli* is not acceptable** for this target (inclusion bodies).
- Deglycosylation, preferred route: a **synthetic gene carrying 11 N→Q substitutions**, so the host does not glycosylate the protein and no PNGase F step is needed. Fallback route: enzymatic deglycosylation (PNGase F / Endo-H) under **native conditions only** — no SDS, no DTT.
- Sequence: **sequence to be finalized; quote against capability & timeline.** The final coding sequence is supplied at order placement.
- Cofactor: FAD, native — flavinylation by the expression host.
- Not acceptable as a substitute: glucose **oxidase** (generates H₂O₂, incompatible with our application).
- Quantity: milligram scale for a pilot round — please quote the mg tiers you normally offer so we can size the order.
- Delivery form: lyophilised powder or stabilised buffer; CoA and QC report required.
- QC / acceptance: SDS-PAGE showing a single band at the aglycosylated molecular weight · specific activity by glucose-dehydrogenase assay in U/mg with the assay conditions stated · evidence that the enzyme does not generate H₂O₂ (dehydrogenase, not oxidase) · MS confirmation of the N→Q substitution sites.

**B — tri-metallic Co/Cu/Ce ZIF laccase-mimic nanozyme**

- Product: tri-metallic zeolitic-imidazolate-framework nanozyme (Co/Cu/Ce) acting as a laccase mimic for oxygen reduction and direct electron transfer. A Cu/Ce/Au ZIF composition is an acceptable alternative if that is your established route.
- Method: solvothermal synthesis.
- **Particle size 40–80 nm — a contractual requirement, SEM-verified.** Macrocrystalline product is unusable on our electrode.
- Optional add-on: a hybrid formulation with laccase supported on MWCNT — quote separately if you offer it.
- Quantity: R&D scale — please quote your minimum synthesis batch plus one scale-up tier.
- QC / acceptance: SEM (size distribution and morphology) · XRD (ZIF phase) · ICP-OES or EDS (Cu:Co:Ce stoichiometry) · BET specific surface area.

**C — genipin**

- Product: genipin, purity **>98%** (used as a non-toxic crosslinker for chitosan; glutaraldehyde is not an acceptable substitute for our application).
- Quantity: gram scale — please quote the pack sizes you stock and the per-gram price at each.
- Storage and shipping: must be shipped protected from light and held at 4 °C — state your cold-chain packaging and the temperature excursion it tolerates.
- QC / acceptance: CoA stating purity and lot. We run an incoming functional check (chitosan crosslinking at pH 4.5) on receipt.

**D — Nafion grafted with poly(sulfobetaine methacrylate) (PSBMA) via SI-ATRP**

- Product: Nafion membrane surface-grafted with PSBMA by surface-initiated ATRP, for anti-biofouling performance.
- **Required capability:** attaching the ATRP initiator requires converting the Nafion sulfonic groups to the **sulfonyl chloride** form — please describe your prior hands-on experience with fluoropolymer chemistry, as this step governs feasibility.
- Quantity and format: coupon-scale pieces for R&D — state the minimum area and format you can supply.
- QC / acceptance: proton conductivity by EIS · anti-fouling assessment against resin acids (abietic acid) · a rehydration cycle across the UCST transition (−10 °C → +25 °C).
- We recognise this is a development-type job rather than a catalogue item; quote development effort and material separately.

**E — cellulose nanocrystals (CNC)**

- Product: cellulose nanocrystals, used as a rheology modifier at 2–6 wt% loading in our matrix (loading given as context, so you can recommend a grade).
- Route: either supply of CNC (suspension or spray-dried powder), or production by acid hydrolysis from alpha-cellulose if that is a service you offer — quote whichever applies.
- QC / acceptance: particle size and aspect ratio (TEM or AFM) · crystallinity index · CoA.

### Processing / QC requirements

Applies to whichever item you quote:

- **CoA per batch/lot** plus the QC report listed for the item. Third-party analytical reports are acceptable; self-declaration without data is not.
- **No substitutions without written agreement** — in particular the host organism (A), the crosslinker chemistry (C) and the graft chemistry (D) are not interchangeable in our application.
- **Documentation:** SDS/MSDS, and REACH/RoHS or equivalent statements where applicable to the material.
- **Packaging:** state the packaging, the storage conditions on arrival, and the shelf life you guarantee. Light protection and cold chain are mandatory where the item specification says so.
- **Incoming inspection:** we perform an incoming functional check and will report any deviation with data; state your policy for non-conforming lots.

### Target performance envelope (informational, not acceptance)

The figures below are our **design and literature targets for the finished device**. They are given so you can judge fit — they are **not acceptance criteria for this order and not a performance guarantee we ask you to underwrite.** Acceptance is exclusively the QC list under each item.

| Item | Target envelope (informational) |
|---|---|
| B nanozyme | ~10× the power density of unmodified laccase · ≥75% activity retained after 10 days · activity gain rather than loss in 0.25 M NaCl (unmodified laccase loses roughly 40% under the same condition) |
| D membrane | proton conductivity of order 45 mS/cm · about 8 water molecules per chain · UCST transition near 5 °C |

### What we ask you to provide

Please reply with:

1. **Unit price** at the quantities/tiers named in the item specification, and the price break points above them.
2. **Setup, synthesis-development, gene-synthesis or tooling charges itemised separately** from unit price.
3. **Lead time from purchase order to shipment**, stating explicitly whether purification, QC and any post-processing are inside that lead time or added to it.
4. **MOQ** and available pack sizes.
5. **Certifications and documents you can supply:** CoA, ISO 9001 or GMP-grade status where applicable, SDS, REACH/RoHS statements, and animal-free / GMO-status statements where relevant to the item.
6. Whether a **sample, first-article or small pilot batch** is possible before a larger order, and at what price.
7. **Quote format:** currency, validity period, payment terms, and the point of contact for technical questions.

### Commercial & logistics

- Ship-to: Ukraine (Cherkasy region). We can nominate an **EU forwarding address** instead if that simplifies export or customs for you — state your preference.
- Incoterms you quote on, HS code, and any export-control or dual-use classification that applies.
- Cold-chain and light-protection handling per the item specification; state the courier and transit time you would use.
- Tell us what documentation you need from us (end-use statement, entity details, import permits).

### Attachments

Nothing is required from us for an initial quotation. On request we supply the incoming-test protocol we use for acceptance; for item A, the final coding sequence is provided at order placement.

---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 7. Cross-references

| Ресурс | Що бере |
|---|---|
| [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | анод · genipin-chitosan-CNC матриця · Nafion-g-PSBMA (Шар 4/5) |
| [`01_03 §2.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | катод Laccase/nCoCuCeZIF — цільові показники |
| [`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | CRO-нюанси: Pichia-not-E.coli, ZIF SEM-gate, мембрана-bottleneck |
| [`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md) | **owner** мутованої послідовності (600 aa, 11 N→Q) + CHEM.10/11 gate |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | HW.5 (хім-стек action items) · HW.24 (staged validation) · HW.5.IS (CHEM.*) |
| [`00_02`](../../00_02_Academic_Integration_and_IP.md) | ЧНУ нанохімія (ZIF) + біо-хаб (рецептура соку) |
| [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) | IP-постава (defensive publication) — owner |
