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

0. **Два маршрути, не один — форма адресата вирішує мову й жанр.** Комерційному постачальнику чи CRO їде **EN-блок** (§Dispatch (EN), один item = один лист). **Установі НАН їде ТЗ українською під договір НДР ⊥ послугу** — прецедент форми: [`anchor_hip_rfq`](anchor_hip_rfq.md) і ТЗ 1/2 [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md); цей аркуш сам записав правило для ІБК у §6. UA-блоки згруповано **по інститутах, не по специфікаціях** (один адресат = один лист, навіть коли бере кілька позицій): ІБК (Spec A + G + питання про нанозим) · ІФХ (Spec B) · ЦККНО Львівської політехніки (приймальний вимір Spec B: той, хто міряє, окремо від тих, хто синтезує) · ІЗНХ (Spec F) · ІХП (Spec I) · ІХВС (Spec H + E) · ЧНУ (два питання по Spec B). Spec C (геніпін) UA-адреси не має — імпорт; Spec D — не установа НАН ([`ua_vendor_map §3`](ua_vendor_map.md)), тож лишається EN-маршрутом.
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
| **Послідовність** | 600 aa, 11 N→Q (N71/100/192/200/249/258/271/355/380/405/463) **+ три компенсаційні заміни L80D · A70S · I401S** (⚖️ 2026-09-17/18) — **owner [`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md)**; ген синтезувати з L1 (не дублюю рядок тут — single source проти drift) |
| **Кофактор** | FAD (нативний; expression host забезпечує флавінілювання) |
| **QC / acceptance** | SDS-PAGE (один бенд ~600 aa, аглікозильований MW), активність (glucose-DH assay, U/mg), відсутність H₂O₂ (O₂-незалежність), MS-підтвердження N→Q-сайтів |
| **Кількість** | пілот: мг-масштаб для Stage 2 Ti-coins (HW.24); уточнити після квоти |
| **Формат** | ліофілізат або стабілізований буфер; CoA + QC-звіт |
| **IP** | ген відкритий (defensive disclosure / L1); CRO лише експресує; CDA — §IP |

> ⚠️ **Gate перед заморожуванням гена (sequence freeze ≠ now):** обидва in-silico кроки на dgr-мутанті пораховано — CHEM.10 ✅ 2026-06-06 (Lys→Arg) і CHEM.11 ✅ 2026-09-17 (script `69`, [`SUMMARY §CHEM.11`](../ebfc/in_silico/SUMMARY.md)).
> **Усі три рішення ухвалено:** `Leu80 → Asp` і `Ala70 → Ser` — ⚖️ founder 2026-09-17 (нічию в ΔSASA вирішив заряд); `Ile401 → Ser` — ⚖️ founder 2026-09-18, після того як підстава hold'у (консервативність позиції) була зміряна й не підтвердилась: Ile у 401 тримають 3.6 % гомологів проти 15.7 % Ser, і Ser стоїть там у семи видів того самого роду *Colletotrichum* ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5.IS). Отже послідовність для гена = **600 aa · 11 N→Q · L80D · A70S · I401S**, і патч Gln405 дістав свою компенсацію. **Відкрите одне:** прогін Aggrescan3D (зовнішній вебсервер з акаунтом, 👤) — ⚖️ founder 2026-09-17: прогнати окремою сесією, щоб не відволікати корінь ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5.IS) ([`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md), → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5.IS):
> - **CHEM.11 (anti-aggregation):** 11 знятих гліканів оголюють гідрофобну поверхню → чотири патчі
>   (Gln71/200/258/405) — це РАНГ серед одинадцяти сайтів деглікозилювання, не абсолютний ризик.
>   Компенсаційні заміни ухвалено й уже стоять у Spec A ↑; перед CRO лишилась друга половина
>   рецепта [`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md) — прогін Aggrescan3D.
> - **CHEM.10 (genipin-shield):** Lys109/Lys262 на виході електрона → мутувати **Lys→Arg** (інертний до
>   геніпіну), щоб зшивка не блокувала Os-докінг.
>
> **Тому:** RFQ на **квоту/спроможність/строки** можна слати зараз; **фінальний ген заморожувати
> після Aggrescan3D** — якщо він позначить іншу множину патчів, компенсацію переоцінюють (машинну
> половину CHEM.11 закрито 2026-09-17). У cover-note: «sequence to be finalized; quote against
> capability & timeline».

---

## 2. Spec B — Cu-Co-Ce ZIF laccase-mimic нанозим (катод DET)

| Поле | Специфікація (дзеркало `01_03 §2.2` / HW.5) |
|---|---|
| **Продукт** | Трьохметалевий **nCoCuCeZIF** нанозим (альт. nCuCeAuZIF) — laccase-mimic для ORR/DET |
| **Метод** | Сольвотермальний синтез |
| **Розмір частинок** | **Медіана 40–80 нм** за діаметром еквівалентного кола з SEM, `n ≥ 200` кристалів на `≥ 3` полях — це й є умова приймання (⚖️ делеговано 2026-09-24, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5). ⊕ Окремим рядком договору: звіт МУСИТЬ нести частку поза 40–80 нм, найбільший зміряний кристал і `D99` — вони не судяться в першій партії, але без них критерій вироджується в саму медіану (макрокристали відпадуть з електрода — `01_03 §3.7`) |
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
| **🔴 Питання №1 листа** | **чи адресат ВЗАГАЛІ береться за кастомний синтез цього роду** — додано 2026-09-22 дзеркально до Spec D. Підстава: [`ua_vendor_map §3`](ua_vendor_map.md) називає вузьким місцем саме ВИКОНАВЦЯ («прекурсор купується тривіально»), а лист доти питав про продукт, QC, безпеку й кількість — усе, крім ЗДАТНОСТІ адресата, тобто поїхав би, не спитавши того, на що чекає нога [`HW.5`](../../00_07_Action_Plan_Tracker.md). ⛔ У сам лист НЕ пишемо, що заявленого постачальника ми не знайшли — це віддає адресатові нашу переговорну позицію. ⚠️ §Dispatch-нота забороняє вужче (ціни, lead-time, імена постачальників), тож цей рядок її свідомо РОЗШИРЮЄ |
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
| **Продукт** | багатостінні вуглецеві нанотрубки з групами -COOH; кріплення до Ti декларує виконавець функціоналізації (⚖️ 2026-09-18) |
| **Геометрія й функціоналізація** | діаметр · довжина · вміст -COOH канон числами не задає — вендор декларує марку, обираємо ми |
| **🔴 Залишковий каталізатор** | вендор декларує вміст **Co/Ni/Fe** (TGA-залишок + ICP): Co стоїть у панелі ICP-MS coin-тесту як метал нанозиму, тож незадекларований кобальт трубок читався б як вимивання нанозиму |
| **QC / acceptance** | TEM/SEM · Raman (I_D/I_G) · XPS або титрування (-COOH) · TGA · CoA |
| **Кількість** | г-масштаб; уточнити |

> ⚖️ **Іонної рідини в Шарі 2 НЕМАЄ — ратифіковано founder 2026-09-18** ([`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) п.2, підстава й ціна там): первинка шару давала [BMIM][BF₄] на скловуглеці без Ti й без Os, її аніон гідролізується до фториду, що руйнує пасивацію Ti при pH ~5, а роль плівки в нашій MET-архітектурі несе Os-полімер Шару 3. **Отже IL у цьому аркуші не закуповується взагалі.** ⚠️ Кріплення MWCNT до Ti рецептом сюди теж не йде — його декларує виконавець функціоналізації, приймання за 30-денним утриманням струму (той самий патерн, що EAAE). Трубки закуповуються незалежно.

---

## 6. RFQ dispatch checklist + послідовність (критичний шлях першим)

- [ ] 👤 **CDA — на комерційній стадії, не перед запитом:** стандартний взаємний CDA вендора на комерц-умови (§IP; [`rfq_registry`](rfq_registry.md) §3).
- [ ] 👤 **Адресати — [`ua_vendor_map §3`](ua_vendor_map.md)** (Spec A: ІБК НАН Львів ⊥ Bienta/Enamine — питання №1 «Pichia, не E. coli»; Os-полімер — **дві адреси є** (ІЗНХ ім. Вернадського ⊥ Enamine на полімерну половину), вузьке місце — не сировина й не лист, а те, чи ХТОСЬ береться: питання №1 §5a; приймання ZIF — ЦККНО Львівської політехніки). ⚠️ ІБК НАН — інститут НАН: лист туди йде проєктом ТЗ українською під договір НДР ⊥ послугу (прецедент — [`anchor_hip_rfq`](anchor_hip_rfq.md)), не EN-аркушем. ✅ **ТЗ українською складено для пʼяти установ НАН** (ІБК · ІФХ · ІЗНХ · ІХП · ІХВС) — UA-блоки нижче, згруповані по інститутах (§0 п.0); founder тексту ще не бачив, тож ⛔ до його «так» не надсилати.
- [ ] 👤 **Spec A (dgrFAD-GDH)** — RFQ на квоту/строки **зараз** (🔴 4–8 тиж тримає весь Stage 2). Sequence freeze — після Aggrescan3D (CHEM.10 ✅; машинна половина CHEM.11 ✅ 2026-09-17, три компенсації вже у Spec A).
- [ ] 👤 **Spec F (Os-полімер)** — RFQ кастомного синтезу **разом зі Spec A**: без медіатора анод не працює, а строк синтезу невідомий.
- [ ] 👤 **Spec C (геніпін)** — закупка паралельно (найшвидше).
- [ ] 👤 **Spec B (ZIF)** — RFQ або ЧНУ-партнерство ([`00_02`](../../00_02_Academic_Integration_and_IP.md)) паралельно. ЧНУ — ⚖️ 2026-09-23: два питання (синтез · чим підтвердить 40–80 нм і фазу), текст — UA-блок нижче; канал пасивний — один лист, без нагадувань. Приймальний вимір партії — окремий адресат (ЦККНО Львівської політехніки), UA-блок нижче.
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
- **Particle size — the MEDIAN equivalent-circle diameter from SEM must fall in 40–80 nm**, counted over at least 200 crystals in at least 3 fields; that median is the acceptance condition for the first batch. Please also REPORT, as a separate contractual line, the fraction outside 40–80 nm, the largest crystal measured and `D99`: we do not set a limit on them for the first batch, but without them the criterion collapses into the median alone. Macrocrystalline product is unusable on our electrode.
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
- **Required capability:** this is a custom synthesis rather than a catalogue item — please state whether you undertake work of this type, and describe your prior hands-on experience with osmium polypyridyl complexes and with anchoring a metal complex to a polymer backbone, as this governs feasibility. Quote development effort separately from material.
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

- Product: MWCNT carrying carboxyl groups. We do not fix diameter, length or carboxyl content — state the grades you offer with those values.
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

## 📤 Dispatch block (UA) — Spec B: два питання до ЧНУ (синтез і приймання ZIF)

> **Репо-нота (у лист НЕ йде).** ⚖️ founder 2026-09-23 ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5): питати ЧНУ ДВОМА питаннями — чи бере кафедра синтез і чим підтвердить розмір та фазу. Адресат — проректор з науки ([`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md)). **Ціна присуду:** лист іде в канал, який founder тримає пасивним, тож надсилається ОДИН раз, без нагадувань. Паралельно, не замість — ІФХ/ІБК на синтез і ЦККНО Львівської політехніки на приймання ([`ua_vendor_map §3`](ua_vendor_map.md)). ⛔ Умов (співавторство, оплата, договір) лист не обіцяє — їх канон тримає як опцію Spec B ↑, а вибір за founder-ом.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Два питання щодо сольвотермального синтезу нанозиму Co/Cu/Ce-ZIF на кафедрі хімії та наноматеріалознавства

Вельмишановний пане проректоре!

Звертаюся з двома конкретними питаннями про можливу участь кафедри хімії та наноматеріалознавства в синтезі каталізатора для катода нашого ферментного біопаливного елемента.

Йдеться про триметалевий нанозим на основі цеолітного імідазолатного каркаса (ZIF) з кобальтом, міддю та церієм — міметик лакази, що працює як каталізатор відновлення кисню на катоді. Метод — сольвотермальний синтез. Критична вимога — розмір кристалів: медіана 40–80 нм за скануючою електронною мікроскопією.

1. Чи може кафедра виконати сольвотермальний синтез такого Co/Cu/Ce-ZIF у лабораторній кількості для перших електродних зразків?
2. Чим кафедра може підтвердити розмір кристалів (медіану щонайменше за 200 кристалами з кількох полів зору) і кристалічну фазу ZIF — скануючою електронною мікроскопією та рентгенівською дифрактометрією власними силами чи через партнерські лабораторії?

Відповідь «ні» на будь-яке з питань для нас теж корисна: вона визначає, куди звертатися далі. Умови можливої співпраці готовий обговорити окремо.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 📤 Dispatch block (UA) — ТЗ для ІБК: рекомбінантний фермент (Spec A) і лаказа (Spec G)

> **Репо-нота (у лист НЕ йде).** Український маршрут Spec A + Spec G ↑ для установи НАН: форма — проєкт ТЗ під договір НДР ⊥ послугу, як [`anchor_hip_rfq`](anchor_hip_rfq.md) і ТЗ 1/2 [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md); правило «власникові установки/інституту НАН — ТЗ українською» сам цей аркуш записав у §6. Адресат #1 обох позицій — ІБК НАН, Львів ([`ua_vendor_map §3`](ua_vendor_map.md)); комерційна гілка (Bienta/Enamine) лишається EN-блоком ↑ і в цьому тексті не згадується. **Дзеркало, не новий зміст:** кожне число — з §1 і §5b, доми — [`01_03 §1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`L1 §2`](../ebfc/in_silico/L1_protein_architecture.md). **Додано третім блоком питання про нанозим** — той самий предмет, що ТЗ для ІФХ ↓: карта тримає цю групу другою адресою по Co/Cu/Ce лаказо-міміках, і ⚖️ 2026-09-23 велить тримати альтернативи ПАРАЛЕЛЬНО, не замість ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5); вимоги приймання там ті самі, тому блок короткий. **Немає свідомо:** позицій 11 N→Q і gate-контексту §1 (послідовність не заморожена) · наших lead-time-оцінок і прикладів цін · імен інших адресатів і комерційної гілки · трекер-ID, канон-рефів, статус-маркерів · нанесення стеку на купони (його купує лист лабораторії [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md), і дублювати предмет між двома листами не можна). ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо контрактної експресії рекомбінантної глюкозодегідрогенази та препарату лакази — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева: він живиться глюкозою ксилемного соку й має працювати без обслуговування два десятиліття. Анод такого елемента несе рекомбінантну глюкозодегідрогеназу, катод — лаказу в поєднанні з неорганічним каталізатором. Ми шукаємо виконавця, який виготовить ці біокомпоненти, і звертаємося до вас як до установи, що веде відповідні напрями.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону. Нижче — проєкт технічного завдання для узгодження. Те, чого ми не фіксуємо, подано як питання: просимо відповідати своїми даними, а не підганяти їх під наш текст. Якщо якась із трьох позицій не ваш профіль — скажіть прямо про неї, решта питань лишаються чинними.

**Проєкт технічного завдання**

*1. Позиція 1 — деглікозильована ФАД-залежна глюкозодегідрогеназа (контрактна експресія)*

1. **Продукт:** рекомбінантна ФАД-залежна глюкозодегідрогеназа, приблизно 600 амінокислотних залишків, у деглікозильованій формі. Базовий білок — фермент *Glomerella cingulata*, запис UniProt **G8E4B5**; гомолог *Aspergillus* прийнятний як альтернатива, якщо у вас уже є налагоджена конструкція.
2. **Хост експресії:** ***Pichia pastoris* (секреторна експресія).** *E. coli* для цієї мішені **неприйнятна** — білок такого розміру йде в тільця включення.
3. **Деглікозилювання, бажаний маршрут:** синтетичний ген із **11 замінами N→Q**, тож хост фізично не глікозилює білок і ферментативний етап не потрібен. **Запасний маршрут:** ферментативне деглікозилювання (PNGase F або ендо-H) **лише в нативних умовах** — без додецилсульфату натрію й без дитіотреїтолу, бо розгортання білка тут неприпустиме.
4. **Послідовність:** остаточну кодуючу послідовність ми передамо при розміщенні замовлення. Пропозицію просимо складати **під спроможність і строк**, а не під конкретний текст гена. Скажіть, чи замовляєте синтез гена самі й чи входить він у ціну окремим рядком.
5. **Кофактор:** ФАД, нативний — флавінілювання забезпечує хост.
6. **Неприйнятна заміна:** глюкозооксидаза. Вона виробляє пероксид водню, несумісний із нашим застосуванням; нам потрібна саме дегідрогеназа.
7. **Кількість:** міліграмовий масштаб на пілотний раунд. Назвіть градації за масою, у яких ви зазвичай працюєте, щоб ми визначили обсяг замовлення.
8. **Формат поставки:** ліофілізат або стабілізований буфер; сертифікат аналізу й звіт контролю якості обовʼязкові. Назвіть умови зберігання, строк придатності й вимоги до холодового ланцюга.
9. **Приймання (контроль якості):** електрофорез у поліакриламідному гелі з додецилсульфатом натрію — одна смуга на молекулярній масі аглікозильованої форми · питома активність за глюкозодегідрогеназним тестом у ОД/мг із наведеними умовами тесту · підтвердження, що фермент **не утворює пероксиду водню** (дегідрогеназа, не оксидаза) · мас-спектрометричне підтвердження сайтів замін N→Q. Сторонні аналітичні звіти приймаються; самодекларація без даних — ні.

*2. Позиція 2 — лаказа для катода*

10. **Продукт:** препарат лакази, базовий варіант — лаказа *Trametes versicolor*. Якщо ви можете запропонувати власний очищений препарат іншого продуцента, скажіть: випробування йдуть у синтетичному ксилемному соку pH 5,75 (бічна серія — 4,5), а в службі середовище катода може доходити до pH ~6–7 взимку, тож нам потрібен не вузький кислий оптимум, а **профіль активності й стабільності в діапазоні pH 4,5–7**. Назвіть продуцента, спосіб одержання й доступну кількість.
11. **Склад препарату:** **азиду натрію бути не повинно** — він пригнічує лаказу вже в мікромолярних концентраціях. Усі стабілізатори й наповнювачі просимо задекларувати поіменно: кожну добавку ми перевіряємо на сумісність із рештою електродного стеку.
12. **Приймання:** сертифікат аналізу з активністю в ОД/мг за тестом з ABTS і наведеними pH та температурою · вміст білка · чистота за електрофорезом · перелік домішок.
13. **Зберігання й доставка:** холодовий ланцюг — назвіть умови, строк придатності й пакування.
14. **Кількість:** від міліграмів до грамів; назвіть фасування, яке маєте.

*3. Позиція 3 — питання про триметалевий нанозим (окрема спроможність)*

15. Катод нашого елемента працює на парі «лаказа + неорганічний міметик лакази»: триметалевий нанозим на основі цеолітного імідазолатного каркаса з **кобальтом, міддю та церієм**, одержаний сольвотермальним (або гідротермальним) синтезом. **Питання одне: чи виконує ваша установа синтез такого матеріалу** в лабораторній кількості для перших електродних зразків — і якщо так, то за якою схемою.
16. **Критична вимога, якщо ви за це беретесь:** **медіана розміру кристалів 40–80 нм** — діаметр еквівалентного кола за скануючою електронною мікроскопією, щонайменше 200 кристалів із трьох і більше полів зору; це умова договору, а не побажання. Частку кристалів поза 40–80 нм і найбільший зміряний кристал просимо звітувати окремо. **Чим ви підтвердите розмір і кристалічну фазу** — скануючою електронною мікроскопією та рентгенівською дифрактометрією власними силами, чи через партнерську лабораторію? Повне приймання, яке ми просимо: мікроскопія (розподіл за розміром і морфологія) · дифрактометрія (фаза каркаса) · елементний аналіз співвідношення міді, кобальту й церію · питома поверхня за методом БЕТ.
17. Відповідь «ні» на цей блок для нас теж корисна — вона визначає, куди звертатися далі, і не впливає на позиції 1 і 2.

*4. Орієнтири продуктивності (довідково, не критерії приймання)*

18. Наведені нижче числа — наші проєктні й літературні орієнтири **для готового пристрою**, дані лише щоб ви оцінили придатність. Вони **не є критеріями приймання цього замовлення** й не є характеристикою, яку ми просимо вас гарантувати; приймання — виключно переліки контролю якості вище. Для гібридного катода орієнтири такі: приблизно десятикратна питома потужність проти немодифікованої лакази · збереження близько 75 % активності після 10 діб · у присутності 0,25 М хлориду натрію — приріст активності, а не втрата (немодифікована лаказа за тієї самої умови втрачає близько 40 %).

*5. Що просимо надати*

19. **Ціни постатейно:** за позицію й за градацію кількості; окремими рядками — синтез гена, налагодження експресії, очищення, ліофілізація, контроль якості.
20. **Строки:** від укладення договору до відвантаження, із прямою вказівкою, чи входять очищення й контроль якості в цей строк, чи додаються до нього.
21. **Мінімальне замовлення** й доступні фасування; чи можливий **пробний зразок або малий пілотний раунд** перед більшим замовленням і за якою ціною.
22. **Спроможність:** біореактори й обʼєми ферментації, маршрут очищення, досвід секреторної експресії в дріжджових хостах, ліофілізація; знеособлені приклади порівнянних робіт.
23. **Документи, які можете надати:** сертифікат аналізу, паспорт безпеки, довідки про статус системи якості, заяви щодо походження матеріалів — що саме маєте.
24. **Форма співпраці:** на якій підставі ви виконуєте роботи для сторонніх замовників — договір на науково-дослідну роботу, договір про надання послуг чи інше; які документи потрібні від нас (реквізити, лист-запит, технічне завдання в узгодженій формі); форма оплати, строк чинності пропозиції й контактна особа з технічних питань.
25. **Приймання й доставка:** як передаєте продукт (курʼєр, пошта, особисто), вимоги до пакування, маркування й холодового ланцюга, хто відповідає за вантаж у дорозі; чи оформлюєте акт приймання-передачі з переліком ідентифікаторів партій. Місце доставки — Черкаська область; за потреби можемо назвати адресу пересилання в ЄС.

**Конфіденційність і публікація.** Технічна специфікація нашого стеку відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов (ціни, строки, дані контролю якості). Результати випробувань ми маємо намір опублікувати в рецензованому журналі — повідомте, будь ласка, чи маєте умови щодо згадки установи або опису методу, і чи розглядаєте участь у публікації як співавтори.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — ТЗ для ІФХ: триметалевий нанозим катода (Spec B)

> **Репо-нота (у лист НЕ йде).** Український маршрут Spec B ↑ для установи НАН; адресат #1 синтезу — ІФХ ім. Писаржевського (пористі координаційні полімери 3d-металів, [`ua_vendor_map §3`](ua_vendor_map.md)). Числа — дзеркало [`01_03 §1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (таблиця «Катод») і [`01_03 §2.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md); цільові показники подано окремою довідковою рамкою, НЕ як приймання — так само, як в EN-блоці. **Цей лист ⊥ лист ЧНУ ↑:** там два питання про спроможність кафедри, тут повне ТЗ під договір; обидва йдуть паралельно (⚖️ 2026-09-23, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.5). **Немає свідомо:** імен інших адресатів і лабораторії приймання · наших оцінок ціни й строку · трекер-ID, канон-рефів, статус-маркерів. «Сторонню лабораторію» з п. 12 адресує UA-блок ЦККНО ↓ (2026-09-24), а в сам лист її імʼя свідомо не йде. ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо сольвотермального синтезу триметалевого нанозиму на основі цеолітного імідазолатного каркаса (Co/Cu/Ce) — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева, для моніторингу лісу. Катод цього елемента відновлює атмосферний кисень і працює на парі «фермент + неорганічний міметик ферменту». Саме міметик — триметалевий нанозим на основі цеолітного імідазолатного каркаса — ми й шукаємо виконавця синтезувати, і звертаємося до вас як до установи, що веде хімію пористих координаційних полімерів перехідних металів.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону. Нижче — проєкт технічного завдання для узгодження; те, чого ми не фіксуємо, подано як питання.

**Проєкт технічного завдання**

*1. Предмет*

1. **Продукт:** триметалевий нанозим на основі цеолітного імідазолатного каркаса з **кобальтом, міддю та церієм**, що працює як міметик лакази у відновленні кисню й забезпечує пряме перенесення електронів із вуглецевої матриці. Композиція з міддю, церієм і золотом прийнятна як альтернатива, якщо саме вона у вас налагоджена.
2. **Метод:** сольвотермальний синтез. Якщо ваш робочий маршрут гідротермальний або інший — скажіть, ми розглянемо його за тими самими критеріями приймання.
3. **Критична вимога — медіана розміру кристалів 40–80 нм.** Міра — діаметр еквівалентного кола за скануючою електронною мікроскопією, щонайменше 200 кристалів із трьох і більше полів зору. Це умова договору, а не побажання. Цільова морфологія — пориста губчаста структура з агрегованих нанокристалів цього розміру; окремі великі кристали не утримуються на нашому електроді, тож їх ми не судимо порогом, а просимо звітувати (п. 7).
4. **Опційно:** гібридна композиція, де на тому самому вуглецевому носії (багатостінні нанотрубки) поєднано нанозим і лаказу. Якщо пропонуєте — оцініть окремим рядком.
5. **Кількість:** лабораторний масштаб для перших електродних зразків. Назвіть мінімальну партію синтезу й один ступінь укрупнення.
6. **Формат поставки:** порошок або суспензія — назвіть, що для вашого маршруту природніше, з умовами зберігання й строком придатності.

*2. Приймання й документ про якість*

7. **Мікроскопія:** скануюча електронна мікроскопія з розподілом за розміром і морфологією — **медіана в межах 40–80 нм** (умова п. 3); окремими рядками протоколу — частка кристалів поза 40–80 нм, найбільший зміряний кристал і 99-й перцентиль розподілу.
8. **Фазовий склад:** рентгенівська дифрактометрія — підтвердження фази каркаса.
9. **Стехіометрія:** вміст міді, кобальту й церію — оптико-емісійна спектрометрія з індуктивно звʼязаною плазмою або енергодисперсійний аналіз.
10. **Питома поверхня:** за методом БЕТ.
11. **Документ:** сертифікат або протокол аналізу на кожну партію з наведеними методами й умовами. Сторонні аналітичні звіти приймаються; самодекларація без даних — ні.
12. **Якщо частина цих вимірювань не у вашій сфері — скажіть прямо, які саме.** Це не привід відмовлятися від роботи: ми організуємо їх у сторонній лабораторії, але маємо знати це до початку, бо приймання партії без підтвердженого розміру частинок для нас неможливе.
13. **Відтворюваність:** нанозим цього класу чутливий до умов синтезу. Просимо назвати, які параметри ви фіксуєте від партії до партії й чи зберігаєте зразок-свідок кожної партії.

*3. Орієнтири продуктивності (довідково, не критерії приймання)*

14. Наведені числа — наші проєктні й літературні орієнтири **для готового пристрою**, дані лише щоб ви оцінили придатність; вони **не є критеріями приймання цього замовлення** й не є характеристикою, яку ми просимо гарантувати. Приймання — виключно перелік розділу 2. Орієнтири: приблизно десятикратна питома потужність гібридного катода проти немодифікованої лакази · збереження близько 75 % активності після 10 діб · у присутності 0,25 М хлориду натрію — приріст активності, тоді як немодифікована лаказа за тієї самої умови втрачає близько 40 %.

*4. Що просимо надати*

15. **Спроможність:** чи виконує установа синтез такого класу матеріалів для сторонніх замовників, і які близькі за складом каркаси ви вже одержували (знеособлені приклади годяться).
16. **Ціни постатейно:** розробка й відпрацювання методики окремим рядком від матеріалу; ціна за мінімальну партію та за ступінь укрупнення; кожне вимірювання приймання окремо.
17. **Строки:** від укладення договору до відвантаження, із вказівкою, чи входять у цей строк аналізи приймання.
18. **Форма співпраці:** договір на науково-дослідну роботу, договір про надання послуг чи інше; які документи потрібні від нас (реквізити, лист-запит, технічне завдання в узгодженій формі); форма оплати, строк чинності пропозиції й контактна особа з технічних питань.
19. **Приймання й доставка:** пакування, маркування, хто відповідає за вантаж у дорозі, акт приймання-передачі з ідентифікаторами партій; паспорт безпеки на матеріал. Місце доставки — Черкаська область.

**Конфіденційність і публікація.** Технічна специфікація нашого стеку відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов. Результати випробувань електродів ми маємо намір опублікувати в рецензованому журналі — повідомте, будь ласка, чи маєте умови щодо згадки установи або опису методу синтезу, і чи розглядаєте участь у публікації як співавтори.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — ТЗ для ЦККНО Львівської політехніки: приймальний вимір нанозиму катода (Spec B)

> **Репо-нота (у лист НЕ йде).** Вимірювач Spec B ↑ окремим листом: той, хто ПРОДАЄ нанозим, і той, хто МІРЯЄ його приймання, — різні адресати, бо розмір 40–80 нм є умовою договору з виробником і підтверджувати його має незалежна сторона. Адресат — ЦККНО Львівської політехніки: карта ([`ua_vendor_map §3`](ua_vendor_map.md), рядок «Приймання ZIF», доказ [HTML]) бачить там SEM+EDS у режимі низького вакууму без металізації, XRD і FTIR в одному місці. БЕТ карта там не показує, тож у листі він лише питання спроможності (п. 14), а не предмет замовлення. Форма — ТЗ українською для державної установи з одним базовим випадком (одна партія, один зразок) і доповненнями окремими рядками, як ТЗ 2 [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md). **Що цей блок адресує:** п. 12 ТЗ для ІФХ ↑ («організуємо в сторонній лабораторії») — до цього блоку в тієї обіцянки адреси не було. Питання 2 листа ЧНУ і п. 16 ТЗ для ІБК нічого не обіцяють, а лише ПИТАЮТЬ адресата, чим він підтвердить розмір; якщо відповідь буде «партнерська лабораторія» чи «ні», маршрут веде сюди. Числа — дзеркало [`01_03 §1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (катод: агреговані нанокристали 40–80 нм; Co/Cu/Ce, альтернатива Cu/Ce/Au) і [`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (рядок 4: SEM · XRD; bottleneck 3). **Лист несе МЕТОД і нашу умову читання, а вердикт лишається за нами:** статистичний критерій приймання ратифіковано делеговано 2026-09-24 ([`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) п. 3 — медіана діаметра еквівалентного кола, n ≥ 200 на ≥ 3 полях, хвіст звітується), тож лист просить вимір саме в тій формі, у якій ми його читаємо, плюс розподіл і сирі дані; це та сама конвенція, що в [`rfq_registry`](rfq_registry.md) §4.A для coin-тесту. **40–80 нм — розмір НАНОКРИСТАЛІВ, а не агрегатів** (у каноні — «губчаста архітектура з агрегованих нанокристалів»), тоді як рядок Spec B ↑ каже «частинок». Тому лист явно розводить три величини: кристал, агрегат і окремий макрокристал. **Немає свідомо:** імені виробника синтезу, бо його ще не обрано (ЧНУ · ІФХ · ІБК відкриті) · інших адресатів · наших оцінок ціни й строку · трекер-ID, канон-рефів, статус-маркерів · нових чисел понад канон: методичні застереження (напилення, пучок, перекриття ліній, нижній край ІЧ-діапазону) подано словами. ⚠️ **Написано 2026-09-24, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо приймального вимірювання партій триметалевого нанозиму на основі цеолітного імідазолатного каркаса (Co/Cu/Ce): скануюча електронна мікроскопія з енергодисперсійним аналізом і рентгенівська дифрактометрія — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева, для моніторингу лісу. Катод цього елемента працює на парі «фермент + неорганічний міметик ферменту». Міметик — це триметалевий нанозим на основі цеолітного імідазолатного каркаса з кобальтом, міддю та церієм. Синтезує його окремий виробник, якого ми зараз обираємо, а у вас ми хотіли б замовити **приймальне вимірювання кожної партії**. Синтез і вимірювання ми розділяємо свідомо: розмір частинок є умовою договору з виробником, тож підтверджувати його має незалежна сторона. Звертаємося саме до вашого центру колективного користування, бо за публічним переліком обладнання в ньому є водночас скануюча електронна мікроскопія з енергодисперсійним аналізом, рентгенівська дифрактометрія та інфрачервона спектроскопія.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону. Просимо запропонувати й оцінити **один базовий випадок — одна партія, один зразок, вимірювання з розділу 2**. Решту подано в розділі 3 як доповнення до нього, кожне окремим рядком. Те, чого ми не фіксуємо, подано як питання: просимо відповідати за своїми методиками, а не підганяти їх під наш текст.

**Проєкт технічного завдання**

*1. Зразок*

1. **Матеріал:** триметалевий нанозим на основі цеолітного імідазолатного каркаса — кобальт, мідь, церій; як альтернативу ми можемо прийняти композицію з міддю, церієм і золотом. Форма — порошок або суспензія, залежно від маршруту виробника. Якщо для ваших методик одна з форм помітно краща, скажіть, і ми передамо цю вимогу виробникові.
2. **Що саме ми хочемо побачити.** Цільова морфологія — пориста губчаста структура з агрегованих нанокристалів розміром **40–80 нм**. Агрегація очікувана й сама по собі не є дефектом. Дефект — окремі великі кристали, бо вони не утримуються на нашому електроді. Тому розмір окремих кристалів і розмір їхніх агрегатів для нас — дві різні величини (п. 5).
3. **Кількість, тара, зберігання — просимо визначити ВИ:** мінімальну масу зразка для кожного вимірювання; чи вистачить однієї порції на всі методи і в якому порядку їх виконувати; вимоги до тари, пакування й умов зберігання до вимірювання.
4. **Надходження:** зразок надійде від нас або безпосередньо від виробника — з ідентифікатором партії й за актом приймання-передачі. Скажіть, чи повертаєте ви залишок зразка, а якщо ні — скільки часу його зберігаєте.

*2. Вимірювання базового випадку*

5. **Скануюча електронна мікроскопія — розмір і морфологія.** Нам потрібен розподіл за розміром, а не одне характерне зображення. Медіану розміру кристалів ми читаємо лише тоді, коли вона виміряна щонайменше за 200 кристалами з трьох і більше полів зору, а величина розміру — діаметр еквівалентного кола; якщо ваша методика інша, скажіть, і оцініть обидва варіанти. Просимо запропонувати методику й назвати:
   - пробопідготовку: диспергування в розчиннику з нанесенням на підкладку чи сухий порошок, з ультразвуком чи без. Від неї залежить, що саме буде видно як «частинку»;
   - скільки частинок ви вимірюєте, зі скількох полів зору й за якого збільшення, вручну чи програмно;
   - яку величину розміру берете: діаметр Фере, діаметр еквівалентного кола чи іншу.

   Результат просимо подати трьома окремими частинами: **розмір окремих кристалів** (там, де межі між ними розрізняються), **розмір агрегатів**, а також чи є у зразку великі окремі кристали. Для кристалів — гістограма, середнє, медіана, стандартне відхилення, частка поза діапазоном 40–80 нм, найбільший зміряний кристал і 99-й перцентиль розподілу.
6. **Три методичні моменти мікроскопії — просимо відповісти прямо.** (а) Якщо зразок потребує струмопровідного напилення, назвіть матеріал і товщину шару. На кристалах розміром кілька десятків нанометрів шар у кілька нанометрів уже зсуває виміряний розмір, а золото до того ж є елементом альтернативної композиції. Якщо можна знімати без напилення, у режимі низького вакууму, назвіть роздільну здатність у цьому режимі. (б) Каркаси цього класу чутливі до електронного пучка — як ви обираєте умови зйомки, щоб пучок не змінив розмір і форму кристалів? (в) Калібрування масштабу — за яким еталоном і як часто?
7. **Енергодисперсійний аналіз — елементний склад,** тобто співвідношення кобальту, міді й церію в партії. Просимо назвати:
   - прискорювальну напругу й аналітичні лінії: у низькоенергетичній ділянці спектра лінії цих трьох металів перекриваються;
   - з якої площі знято спектр — для складу партії нам потрібне усереднення по кількох ділянках, а не одна частинка;
   - чи кількісний аналіз безеталонний і яка тоді його невизначеність;
   - матеріал підкладки, бо його лінії теж будуть у спектрі.

   Спектр просимо повертати повністю, а не лише для трьох елементів: сторонні елементи, наприклад залишки прекурсорів, мають бути видні.
8. **Рентгенівська дифрактометрія — фазовий склад.** Просимо ідентифікувати **всі** кристалічні фази, а не лише підтвердити каркас: оксиди цих металів чи залишки прекурсорів, якщо вони є, мають бути названі. Назвіть еталон, з яким порівнюєте (картку бази даних чи розраховану дифрактограму каркаса), і вкажіть, чи є аморфна складова. Назвіть також геометрію зйомки, діапазон кутів, крок і тримач. Наскільки ми розуміємо, для малої маси зразка потрібен низькофоновий тримач.

*3. Доповнення до базового випадку (кожне — окремим рядком ціни)*

9. **ІЧ-спектроскопія з Фурʼє-перетворенням:** присутність і координація імідазолатного ліганду, залишки розчинника синтезу. Назвіть спосіб (таблетка з бромідом калію чи порушене повне внутрішнє відбиття) і діапазон. Нижня межа тут важлива, бо смуга звʼязку метал–азот лежить біля нижнього краю звичайного робочого діапазону.
10. **Розмір кристалітів за уширенням дифракційних піків,** якщо ваш прилад і еталон інструментального уширення це дозволяють. Це незалежна перевірка мікроскопії: якщо розмір кристалітів помітно менший за видимий розмір «частинок», мікроскоп бачить агрегати, а не окремі кристали.
11. **Кожна наступна партія — за тим самим протоколом:** та сама пробопідготовка, ті самі збільшення й кількість виміряних частинок, ті самі умови дифрактометрії. Інакше розподіли різних партій не можна буде порівняти, а ми перевіряємо саме відтворюваність від партії до партії. Назвіть ціну повторної партії, якщо вона відрізняється від першої (методику відпрацьовують лише один раз).

*4. Що повернути*

12. **Протокол вимірювань** на кожну партію з методиками й умовами, а також **первинні дані у відкритих форматах:** зображення з масштабною лінійкою в повній роздільній здатності · таблицю виміряних розмірів по кожній частинці · спектри енергодисперсійного аналізу · дифрактограму в текстовому форматі «кут — інтенсивність» · ІЧ-спектр, якщо його замовлено.
13. Рішення про приймання партії ми ухвалюємо самі за вашими даними. Висновку «відповідає / не відповідає» від вас не потрібно — потрібні лише результати вимірювань.

*5. Що просимо надати*

14. **Спроможність:** моделі мікроскопа, детектора енергодисперсійного аналізу, дифрактометра й ІЧ-спектрометра; роздільна здатність у режимі, в якому ви знімали б наш зразок; режим доступу для сторонніх замовників і типова черга. Якщо центр визначає питому поверхню за методом БЕТ, скажіть про це: це не умова цього запиту, але для партії нам потрібна й ця величина.
15. **Ціни:** базовий випадок · кожне доповнення з розділу 3 окремо · пробопідготовка, якщо вона тарифікується окремо.
16. **Строки:** від отримання зразка до видачі протоколу.
17. **Форма співпраці:** договір про надання послуг, договір на науково-дослідну роботу чи інше. Якщо центр приймає заявки за власною формою, надішліть її, і ми її заповнимо. Також назвіть, які документи потрібні від нас, форму оплати, строк чинності пропозиції й контактну особу з технічних питань.
18. **Пересилання зразка:** адреса й отримувач, вимоги до тари й маркування.

**Конфіденційність і публікація.** Технічна специфікація нашого стеку відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов. Результати ми маємо намір опублікувати в рецензованому журналі. Повідомте, будь ласка, чи маєте ви умови щодо згадки центру або опису методики вимірювання.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — ТЗ для ІЗНХ: осмієвий редокс-полімер, кастомний синтез (Spec F)

> **Репо-нота (у лист НЕ йде).** Український маршрут Spec F ↑; адресат #1 — ІЗНХ ім. Вернадського (хімія комплексних сполук, [`ua_vendor_map §3`](ua_vendor_map.md)); полімерна половина комерційною гілкою лишається в EN-блоці. **Питання про здатність стоїть ПЕРШИМ** — підстава та сама, що у Spec F: вузьке місце стеку є ВИКОНАВЕЦЬ, а не сировина. ⛔ У самому тексті НЕ сказано, що заявленого виконавця ми не знайшли — це віддавало б переговорну позицію. Числа — дзеркало §5a і [`01_03 §1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (MET). **Немає свідомо:** наших оцінок строку й ціни · імен інших адресатів · трекер-ID, канон-рефів, статус-маркерів. ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо кастомного синтезу осмієвого редокс-полімеру для медіаторного перенесення електронів — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева. Активний центр ферменту на аноді занурений глибоко в білкову глобулу, тож електрон від нього до металу переносить редокс-полімер із комплексом осмію. Ми шукаємо виконавця кастомного синтезу такого полімеру й звертаємося до вас як до установи, що веде хімію координаційних сполук.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону.

**Проєкт технічного завдання**

*1. Перше й головне питання — чи беретесь ви за роботу такого роду*

1. Це **кастомний синтез, а не каталожна позиція**. Просимо прямо сказати, чи виконує ваша установа роботи такого типу для сторонніх замовників, і описати наявний досвід із **поліпіридильними комплексами осмію** та з **закріпленням металокомплексу на полімерному носії** — саме це вирішує здійсненність. Розробку й відпрацювання методики просимо оцінити окремим рядком від матеріалу. Якщо ви бачите доцільнішим розділити роботу (комплекс окремо, полімерна матриця окремо) — скажіть, як саме.

*2. Предмет*

2. **Продукт:** редокс-полімер складу **[Os(4,4'-диметил-2,2'-біпіридин)₂(полі(1-вінілімідазол))Cl]⁺/²⁺**.
3. **Ідентифікація сполуки:** опублікований формальний потенціал цього комплексу — **+21 мВ відносно хлоридсрібного електрода (0,1 М KCl)**, тобто приблизно **+309 мВ відносно нормального водневого електрода**. Наводимо його як ознаку сполуки, а не як характеристику, яку ви маєте гарантувати.
4. **Ми свідомо НЕ фіксуємо і просимо вас запропонувати й задекларувати:** співвідношення осмію до імідазольних ланок (ступінь завантаження) · молекулярну масу полі(1-вінілімідазолу) · форму поставки — розчин чи тверда речовина. Ці параметри ми узгодимо до замовлення за вашою пропозицією.
5. **Кількість:** від міліграмів до кількох сотень міліграмів на пілотний раунд. Назвіть мінімальну партію синтезу й один ступінь укрупнення.

*3. Приймання й документ про якість*

6. **Циклічна вольтамперометрія** з обовʼязково названими електролітом і електродом порівняння — формальний потенціал полімеру.
7. **Вміст осмію** — мас-спектрометрія або оптико-емісійна спектрометрія з індуктивно звʼязаною плазмою.
8. **Ідентичність комплексу** — електронна спектроскопія (смуга переносу заряду метал–ліганд); ядерний магнітний резонанс прекурсора.
9. **Молекулярна маса й дисперсність полімеру** — гель-проникна хроматографія.
10. **Сертифікат аналізу** на партію з умовами всіх вимірювань. Якщо частина аналізів не у вашій сфері — скажіть, які саме, ми організуємо їх окремо.

*4. Безпека й поводження*

11. Сполуки осмію за окиснення можуть давати леткий токсичний тетраоксид. Просимо описати ваше поводження з матеріалом, пакування для перевезення й надати паспорт безпеки. Умови зберігання й строк придатності назвіть разом із формою поставки.

*5. Що просимо надати*

12. **Ціни постатейно:** розробка методики · синтез за партію · кожен аналіз приймання окремо.
13. **Строки:** від укладення договору до відвантаження, із вказівкою, чи входять у них аналізи; якщо строк залежить від етапу відпрацювання — назвіть етапи.
14. **Форма співпраці:** договір на науково-дослідну роботу, договір про надання послуг чи інше; які документи потрібні від нас; форма оплати, строк чинності пропозиції й контактна особа з технічних питань.
15. **Приймання й доставка:** пакування, маркування, документи на перевезення, акт приймання-передачі з ідентифікаторами партій. Місце доставки — Черкаська область.

**Конфіденційність і публікація.** Технічна специфікація нашого стеку відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов. Результати електрохімічних випробувань ми маємо намір опублікувати — повідомте, будь ласка, чи маєте умови щодо згадки установи або опису методу синтезу, і чи розглядаєте участь у публікації як співавтори.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — ТЗ для ІХП: карбоксил-функціоналізовані нанотрубки (Spec I)

> **Репо-нота (у лист НЕ йде).** Український маршрут Spec I ↑; адресат — ІХП ім. Чуйка НАН, єдина адреса карти, що дає і матеріал, і функціоналізацію ([`ua_vendor_map §3`](ua_vendor_map.md)). ⛔ **Кріплення нанотрубок до титану в цей лист НЕ йде** — ⚖️ 2026-09-18 віддало маршрут виконавцеві функціоналізації купонів, і його купує лист лабораторії [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) (гілка A); тут купується лише матеріал. Іонної рідини в шарі немає — той самий присуд ([`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) п.2), тож про неї в листі жодного слова. Підстава вимоги про залишковий кобальт — панель аналізу іонів coin-тесту ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)). ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо карбоксил-функціоналізованих багатостінних вуглецевих нанотрубок із задекларованим залишковим каталізатором — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева. Провідну основу обох електродів у ньому утворюють багатостінні вуглецеві нанотрубки з карбоксильними групами. Ми шукаємо постачальника такого матеріалу й звертаємося до вас як до установи, що виробляє нанотрубки й виконує їхню функціоналізацію.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону.

**Проєкт технічного завдання**

*1. Предмет*

1. **Продукт:** багатостінні вуглецеві нанотрубки з поверхневими **карбоксильними групами**.
2. **Геометрію й ступінь функціоналізації ми НЕ фіксуємо:** діаметр, довжину й вміст карбоксильних груп визначає ваша марка. **Просимо назвати марки, які ви маєте, з цими значеннями** — вибір зробимо ми. Якщо серійної марки з потрібним вмістом карбоксильних груп немає, скажіть, чи виконуєте функціоналізацію на замовлення й за якими умовами.
3. **Кількість:** грамовий масштаб. Назвіть фасування й ціну за кожне.
4. **Формат поставки:** порошок або суспензія — назвіть, що доступно, з умовами зберігання й строком придатності.

*2. Вимога, яка для нас критична*

5. **Залишковий каталізатор синтезу — кобальт, нікель, залізо — має бути задекларований числом**, за термогравіметричним залишком і елементним аналізом. Підстава конкретна: у наших випробуваннях ми вимірюємо вихід металів у середовище, і **кобальт стоїть у панелі аналізу як метал каталізатора катода**. Незадекларований кобальт із нанотрубок ми прочитали б як вимивання з іншого компонента, тобто отримали б хибний результат усієї серії. Якщо вміст залежить від партії — потрібне значення саме постаченої партії, а не типове для марки.

*3. Приймання й документ про якість*

6. **Морфологія:** просвічувальна або скануюча електронна мікроскопія.
7. **Структурна якість:** спектроскопія комбінаційного розсіяння — відношення інтенсивностей D- і G-смуг.
8. **Вміст карбоксильних груп:** рентгенівська фотоелектронна спектроскопія або титрування.
9. **Термогравіметричний аналіз** — залишок і його елементний склад (пункт 5).
10. **Сертифікат аналізу** на партію з умовами вимірювань. Сторонні аналітичні звіти приймаються; самодекларація без даних — ні.

*4. Що просимо надати*

11. **Ціни** за марку й фасування, точки зниження ціни за обсягом; мінімальне замовлення.
12. **Строки** від замовлення до відвантаження; чи входить у них контроль якості.
13. **Зразок:** чи можливий невеликий зразок марки перед основним замовленням і за якою ціною.
14. **Документи:** паспорт безпеки, довідки щодо класифікації матеріалу — що можете надати.
15. **Форма співпраці:** договір на науково-дослідну роботу, договір про надання послуг, постачання за рахунком чи інше; які документи потрібні від нас; форма оплати, строк чинності пропозиції й контактна особа з технічних питань.
16. **Доставка:** пакування й маркування, хто відповідає за вантаж у дорозі, акт приймання-передачі з ідентифікаторами партій. Місце доставки — Черкаська область.

**Конфіденційність і публікація.** Технічна специфікація нашого стеку відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов. Результати випробувань електродів ми маємо намір опублікувати — повідомте, будь ласка, чи маєте умови щодо згадки установи або марки матеріалу.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — ТЗ для ІХВС: хітозан і целюлозні нанокристали (Spec H · Spec E)

> **Репо-нота (у лист НЕ йде).** Український маршрут Spec H + Spec E ↑ одним листом: адресат #1 обох позицій — ІХВС НАН (модифікація природних полімерів, композити з целюлозними нанокристалами, [`ua_vendor_map §3`](ua_vendor_map.md)). Геніпіну в Україні карта не знайшла взагалі (імпорт), тож Spec C у цей лист не входить. Числа — дзеркало §5c/§5 і [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) Шар 4. ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо хітозану біомедичного класу та целюлозних нанокристалів для гідрогелевої матриці — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева. Фермент на електроді захищає гідрогелева матриця з хітозану, зшитого геніпіном, із додаванням целюлозних нанокристалів; нанокристали надають матриці псевдопластичності, щоб вона поглинала мікродеформації стовбура від вітру. Ми шукаємо постачальника обох полімерних компонентів і звертаємося до вас як до установи, що веде хімію та модифікацію природних полімерів.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону. Якщо якась із двох позицій не ваш профіль — скажіть прямо про неї, друга лишається чинною.

**Проєкт технічного завдання**

*1. Позиція 1 — хітозан біомедичного класу*

1. **Ступінь деацетилювання:** **понад 75 %**.
2. **Молекулярна маса:** **200–500 кДа**.
3. **Контекст застосування** (наводимо, щоб ви могли порадити марку): 1–2 % мас. у гідрогелі, зшитому геніпіном, разом із целюлозними нанокристалами; робоче середовище слабкокисле.
4. **Приймання:** ступінь деацетилювання (титруванням або ядерним магнітним резонансом) · молекулярна маса (віскозиметрією або гель-проникною хроматографією) · зольність · вміст важких металів · сертифікат аналізу на партію.
5. **Кількість:** грамовий масштаб; назвіть фасування й ціну за кожне.

*2. Позиція 2 — целюлозні нанокристали*

6. **Продукт:** целюлозні нанокристали. **Завантаження в нашій матриці — 2–6 % мас.**; наводимо як контекст для вибору марки.
7. **Маршрут:** або постачання готових нанокристалів (суспензія чи висушений порошок — назвіть, що маєте), **або** виготовлення кислотним гідролізом з альфа-целюлози, якщо це послуга, яку ви надаєте. Просимо оцінити той варіант, який для вас робочий; якщо обидва — обидва.
8. **Приймання:** розмір і співвідношення сторін частинок (просвічувальна електронна або атомно-силова мікроскопія) · індекс кристалічності · сертифікат аналізу на партію.
9. **Кількість:** грамовий масштаб у перерахунку на суху речовину; для суспензії вкажіть концентрацію.

*3. Спільне для обох позицій*

10. **Документ про якість:** сертифікат або протокол аналізу на кожну партію з методами й умовами; сторонні аналітичні звіти приймаються, самодекларація без даних — ні. Якщо частина вимірювань не у вашій сфері — назвіть, які саме.
11. **Заміни без письмового погодження неприпустимі:** склад і характеристики матеріалу в нашому застосуванні не взаємозамінні.
12. **Зберігання й пакування:** умови зберігання на момент отримання й гарантований строк придатності; для суспензій — чи потрібен холодовий ланцюг.
13. **Ціни:** за фасування, точки зниження ціни за обсягом, мінімальне замовлення; якщо гідроліз виконується на замовлення — налагодження окремим рядком від матеріалу.
14. **Строки:** від замовлення до відвантаження, із вказівкою, чи входить у них контроль якості.
15. **Зразок:** чи можливий невеликий зразок кожної марки перед основним замовленням і за якою ціною.
16. **Форма співпраці:** договір на науково-дослідну роботу, договір про надання послуг, постачання за рахунком чи інше; які документи потрібні від нас (реквізити, лист-запит, технічне завдання в узгодженій формі); форма оплати, строк чинності пропозиції й контактна особа з технічних питань.
17. **Приймання й доставка:** пакування й маркування, хто відповідає за вантаж у дорозі, акт приймання-передачі з ідентифікаторами партій; паспорти безпеки. Місце доставки — Черкаська область.

**Конфіденційність і публікація.** Технічна специфікація нашого стеку відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов. Результати випробувань матриці ми маємо намір опублікувати — повідомте, будь ласка, чи маєте умови щодо згадки установи або марки матеріалу.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

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
