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
2. **CDA — не передумова запиту:** специфікація відкрита, тож квоту просимо без угоди; стандартний взаємний CDA вендора — на комерційній стадії (ціни/строки/QC, [`rfq_registry`](rfq_registry.md) §3; EN-лист каже це сам). Cover-note: коротка мета («academic R&D,
   tree-integrated EBFC») + потрібне для квоти (синергія й так публічна — prior art).
3. **Послідовність запуску — за критичним шляхом** (§6): спершу 🔴 dgrFAD-GDH (4–8 тиж) **разом з Os-полімером**
   (кастомний синтез, строк невідомий), паралельно геніпін (закупка, найшвидше) та ZIF; мембрана — окремий fluoropolymer-вендор.
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

> ⚠️ **Gate перед заморожуванням гена (sequence freeze ≠ now):** обидва in-silico кроки на dgr-мутанті пораховано — CHEM.10 ✅ 2026-06-06 (Lys→Arg) і CHEM.11 ✅ 2026-09-17 (script `69`, [`SUMMARY §CHEM.11`](../ebfc/in_silico/SUMMARY.md)).
> **Freeze тепер тримають не розрахунки, а три рішення:** заміна в Leu80 (Asp ⊥ Ser — нічия всередині шум-підлоги, різниця це ЗАРЯД) · чи брати `Ile401→Ser` (найбільший ефект і найімовірніша хибна рекомендація: ΔΔG фолдингу не рахувався ніде) · чи прогонити Aggrescan3D, чи зняти цю половину рецепта з підставою ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5.IS) ([`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md), → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5.IS):
> - **CHEM.11 (anti-aggregation):** 11 знятих гліканів оголюють гідрофобну поверхню → 4 hotspots
>   (Gln71/200/258/405). Перед CRO: Aggrescan3D + компенсаторні полярні мутації поруч.
> - **CHEM.10 (genipin-shield):** Lys109/Lys262 на виході електрона → мутувати **Lys→Arg** (інертний до
>   геніпіну), щоб зшивка не блокувала Os-докінг.
>
> **Тому:** RFQ на **квоту/спроможність/строки** можна слати зараз; **фінальний ген заморожувати
> після** CHEM.11. У cover-note: «sequence to be finalized; quote against capability & timeline».

---

## 2. Spec B — Cu-Co-Ce ZIF laccase-mimic нанозим (катод DET)

| Поле | Специфікація (дзеркало `01_03 §2.2` / HW.5) |
|---|---|
| **Продукт** | Трьохметалевий **nCoCuCeZIF** нанозим (альт. nCuCeAuZIF) — laccase-mimic для ORR/DET |
| **Метод** | Сольвотермальний синтез |
| **Розмір частинок** | **40–80 нм** — жорстко в T&C + **SEM-контроль** (макрокристали відпадуть з електрода — `01_03 §3.7`) |
| **Гібрид** | поєднання з Laccase на MWCNT (резерв безферментного каталізу при денатурації) |
| **QC / acceptance** | SEM (розмір/морфологія), XRD (фаза ZIF), ICP/EDS (Cu:Co:Ce стехіометрія), BET (площа) |
| **Цільові показники** (дзеркало) | ×10 power density vs чиста Laccase; 75% активності після 10 днів; **+7.5%** з 0.25 М NaCl (vs −41.7% чиста Laccase) — **значення в `01_03 §1`** (таблиця «Катод») |
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
| **Acceptance / тест** | вхідний тест cross-linking хітозану при **pH 5.75** (сік — [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) |
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

## 5a. Spec F — Os-редокс-полімер (медіатор анода) · кастомний синтез · слати разом зі Spec A

| Поле | Специфікація (дзеркало `01_03 §1` MET · `§2.1` Шар 3) |
|---|---|
| **Продукт** | [Os(4,4'-dimethyl-2,2'-bipyridine)₂(poly(1-vinylimidazole))Cl]⁺/²⁺ — «Os(dmbpy)₂(PVI)Cl» |
| **Редокс-потенціал** | E°' = **+21 мВ vs Ag/AgCl (0.1 M KCl)** ≈ **+309 мВ vs NHE** (Zafar 2012, *Anal. Chem.* 84, 334) — ідентифікаційна властивість сполуки, не наш прогноз |
| **Не специфіковано в каноні** | співвідношення Os : імідазол (завантаження) · MW PVI · форма поставки (розчин ⊥ тверде) — вендор декларує, ми підтверджуємо до замовлення |
| **QC / acceptance** | CV з назвою електроліту й референсу (E°') · вміст Os (ICP-OES/MS) · ідентичність комплексу (UV-Vis MLCT; ЯМР прекурсора) · MW/дисперсність PVI (GPC) · CoA |
| **Безпека** | сполуки осмію; окиснення може дати летючий токсичний OsO₄ — вендор декларує поводження, пакування, SDS |
| **Кількість** | мг — сотні мг на пілот Stage 2; уточнити після квоти |
| **IP** | CDA — §IP |

> ⚠️ Os-полімер in-silico пройшов лише DFT-рівень (L2-MD без нього — [`01_03 §3.4.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)); закупівлю це не гейтує. До 2026-09-17 цього аркуша не було взагалі — ту саму діру мав канонний план закупівлі `01_03 §3.7`.

---

## 5b. Spec G — Лаказа *Trametes versicolor* (катод) · закупка

| Поле | Специфікація (дзеркало `01_03 §2.2`) |
|---|---|
| **Продукт** | природна лаказа *Trametes versicolor*, комерційний препарат |
| **Активність** | вендор декларує U/мг за ABTS із названими умовами (pH, T) |
| **Склад препарату** | ⛔ **без азиду натрію** — інгібітор лакази, `K_i` 2.72 мкМ ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)); стабілізатори й наповнювачі — задекларувати |
| **QC / acceptance** | CoA: активність · вміст білка · чистота (SDS-PAGE) · домішки |
| **Зберігання** | холодовий ланцюг — вендор декларує умови й термін придатності |
| **Кількість** | мг — г; уточнити |

---

## 5c. Spec H — Хітозан біомедичного класу (Шар 4) · закупка

| Поле | Специфікація (дзеркало `01_03 §2.1` Шар 4) |
|---|---|
| **Ступінь деацетилювання** | **> 75 %** |
| **MW** | **200–500 кДа** |
| **Застосування** | 1–2 % мас. у гідрогелі genipin-chitosan-CNC — контекст для вибору марки |
| **QC / acceptance** | DD (титрування або ЯМР) · MW (віскозиметрія або GPC) · зольність · важкі метали · CoA |
| **Кількість** | г-масштаб; уточнити |

---

## 5d. Spec I — fMWCNT, карбоксил-функціоналізовані (анод Шар 2 · катод базовий шар) · закупка

| Поле | Специфікація (дзеркало `01_03 §2.1` Шар 2 · `§2.2` п.1) |
|---|---|
| **Продукт** | багатостінні вуглецеві нанотрубки з групами -COOH — під EDC/NHS-зшивку з TiO₂ |
| **Геометрія й функціоналізація** | діаметр · довжина · вміст -COOH канон числами не задає — вендор декларує марку, обираємо ми |
| **🔴 Залишковий каталізатор** | вендор декларує вміст **Co/Ni/Fe** (TGA-залишок + ICP): Co стоїть у панелі ICP-MS coin-тесту як метал нанозиму, тож незадекларований кобальт трубок читався б як вимивання нанозиму |
| **QC / acceptance** | TEM/SEM · Raman (I_D/I_G) · XPS або титрування (-COOH) · TGA · CoA |
| **Кількість** | г-масштаб; уточнити |

> ⚠️ **Іонну рідину Шару 2 («IL @ MWCNT») канон не називає** — протокол нанесення невиконуваний, доки її не обрано ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5). Трубки закуповуються незалежно від цього.

---

## 6. RFQ dispatch checklist + послідовність (критичний шлях першим)

- [ ] 👤 **CDA — на комерційній стадії, не перед запитом:** стандартний взаємний CDA вендора на комерц-умови (§IP; [`rfq_registry`](rfq_registry.md) §3).
- [ ] 👤 **Spec A (dgrFAD-GDH)** — RFQ на квоту/строки **зараз** (🔴 4–8 тиж тримає весь Stage 2). Sequence freeze — після CHEM.11 (CHEM.10 ✅).
- [ ] 👤 **Spec F (Os-полімер)** — RFQ кастомного синтезу **разом зі Spec A**: без медіатора анод не працює, а строк синтезу невідомий.
- [ ] 👤 **Spec C (геніпін)** — закупка паралельно (найшвидше).
- [ ] 👤 **Spec B (ZIF)** — RFQ або ЧНУ-партнерство ([`00_02`](../../00_02_Academic_Integration_and_IP.md)) паралельно.
- [ ] 👤 **Spec D (мембрана)** — окремий fluoropolymer-вендор (3–6 тиж).
- [ ] 👤 **Spec E (CNC)** — закупка ENERON.
- [ ] 👤 **Spec G · H · I (лаказа · хітозан · fMWCNT)** — закупка паралельно; у лаказі — підтвердження «без азиду», у трубках — задекларовані залишкові Co/Ni/Fe.
- [ ] 👤 Усі deliverables → **Stage 2 Ti-coins (HW.24)**: in-vitro CV/EIS у синтетичному ксилемному соку (рецептура й pH — [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), ⚖️ 2026-09-17; вимір реального соку — біо-хаб ЧНУ, [`00_02`](../../00_02_Academic_Integration_and_IP.md)), 30-day stability, chloride-tolerance (0.25 М NaCl), UCST winter-lock. Електрод із «вушком» під потенціостат-кліпсу, A=2 см². Лист лабораторії, що це міряє, — [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md).

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
| F mediator | RFQ — custom synthesis of an osmium redox polymer, Os(dmbpy)₂(PVI)Cl, R&D quantity |
| G laccase | RFQ — laccase from *Trametes versicolor*, azide-free, R&D quantity |
| H chitosan | RFQ — biomedical-grade chitosan, DD > 75 %, MW 200–500 kDa |
| I carbon nanotubes | RFQ — carboxyl-functionalised multi-walled carbon nanotubes, residual catalyst declared |

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
- QC / acceptance: CoA stating purity and lot. We run an incoming functional check (chitosan crosslinking at pH 5.75) on receipt.

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

**F — osmium redox polymer (anode mediator), custom synthesis**

- Product: **[Os(4,4'-dimethyl-2,2'-bipyridine)₂(poly(1-vinylimidazole))Cl]⁺/²⁺**. Its published formal potential is **+21 mV vs Ag/AgCl (0.1 M KCl)**, about **+309 mV vs NHE** — given to identify the compound.
- Not fixed on our side — please propose and declare: the Os : imidazole loading, the molecular weight of the poly(1-vinylimidazole), and the delivery form (solution or solid).
- QC / acceptance: cyclic voltammetry with the electrolyte and reference stated · osmium content (ICP-OES or ICP-MS) · identity of the complex (UV-Vis MLCT band; NMR of the precursor) · molecular weight and dispersity of the polymer (GPC) · CoA.
- Safety: oxidation of osmium compounds can release volatile OsO₄ — state your handling and packaging, with SDS.
- Quantity: milligrams to a few hundred milligrams for a pilot — quote your minimum synthesis batch and one scale-up tier.

**G — laccase from *Trametes versicolor***

- Product: natural laccase from *Trametes versicolor*, commercial preparation.
- **The preparation must contain no sodium azide** — it inhibits laccase at micromolar levels. Declare every stabiliser or filler in the formulation.
- QC / acceptance: activity in U/mg by the ABTS assay with its pH and temperature stated · protein content · purity (SDS-PAGE) · CoA.
- Storage and shipping: cold chain — state conditions and shelf life.
- Quantity: milligrams to grams — quote the pack sizes you stock.

**H — chitosan, biomedical grade**

- Degree of deacetylation **> 75 %**; molecular weight **200–500 kDa** (used at 1–2 wt% in a genipin-crosslinked hydrogel — given so you can recommend a grade).
- QC / acceptance: degree of deacetylation (titration or NMR) · molecular weight (viscometry or GPC) · ash · heavy metals · CoA.
- Quantity: gram scale.

**I — carboxyl-functionalised multi-walled carbon nanotubes**

- Product: MWCNT carrying carboxyl groups, for EDC/NHS coupling to a titanium oxide surface. We do not fix diameter, length or carboxyl content — state the grades you offer with those values.
- **Declare the residual catalyst metals (cobalt, nickel, iron)** by TGA residue and ICP: our ion-release analysis measures cobalt, and undeclared cobalt from the tubes would be misread.
- QC / acceptance: TEM or SEM · Raman (I_D/I_G) · carboxyl content (XPS or titration) · TGA · CoA.
- Quantity: gram scale.

### Processing / QC requirements

Applies to whichever item you quote:

- **CoA per batch/lot** plus the QC report listed for the item. Third-party analytical reports are acceptable; self-declaration without data is not.
- **No substitutions without written agreement** — in particular the host organism (A), the crosslinker chemistry (C), the graft chemistry (D) and the mediator complex (F) are not interchangeable in our application.
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
