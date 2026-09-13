# Anchor Coin — Electrochemistry & ICP-MS Lab RFQ (Stage-2 Ti-coin in-vitro test, CRO-ready)

> **Що це:** RFQ-аркуш для **вимірювальної** половини Stage-2 coin — лабораторії, що фізично проганяє CV/EIS · `V_OC` + `R_int` · 30-day · Cl⁻ · UCST · ICP-MS на функціоналізованих купонах у синтетичному ксилемному соку.
> Два сусідні аркуші ПОСТАЧАЮТЬ те, що тут міряється: підкладку — [`anchor_alloy_rfq`](anchor_alloy_rfq.md), хім-стек — [`ebfc_chem_rfq`](ebfc_chem_rfq.md); гейти — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).
> **Статус:** 🟡 робочий артефакт (не канон). **Усі числа — дзеркало канону**, дім кожного названо поруч; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24.
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Анкер coin (Stage-2) — тест» · hard-constraint дім §4.A).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — специфікація відкрита; CDA = стандартні комерц-умови; результати призначені до публікації ([`00_02 §2.1`](../../00_02_Academic_Integration_and_IP.md)).

---

## 0. Як користуватись + cover-note

1. **Окремий аркуш, а не третій лист у сусідах:** адресат інший (лабораторія, не друк-бюро й не постачальник матеріалу), предмет інший (послуга виміру, не компонент), і тест СПОЖИВАЄ обидва сусідні аркуші — лист [`anchor_alloy_rfq`](anchor_alloy_rfq.md) прямо каже, що електрохім-характеризації в ньому немає.
2. **Квоту й спроможність просити можна зараз, замовлення — ні.** Лист написано так, щоб він лишався чинним за будь-якого з відкритих присудів §6: усе відкрите він просить оцінити поштучно («quote per …») замість фіксувати.
3. **Сліпий аналіз.** Лабораторії йдуть лише числа, під які вона мусить збудувати МЕТОД (середовище, температури, навантаження, крок Cl⁻, рівні ICP-MS). Наші пороги pass/fail і in-silico прогнози в лист не йдуть — фіт не повинен знати, що від нього очікують.
4. **Відповідь лабораторії в репо не комітиться** — ціни, внутрішні методики й номери сертифікатів є чужими операційними фактами. Сюди й у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 іде лише наш висновок.

---

## 1. Зразки (що постачаємо)

| Поле | Специфікація | Дім |
|---|---|---|
| **Геометрія** | диск **Ø16×1 мм**; 1 грань = π·8² = **2.01 см² ≈ A_electrode**; «вушко» під кліпсу потенціостата — поза активною гранню | [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) п.4 |
| **Площа** | `j` — на **проєкційну** площу; площу задає **вікно** flat O-ring cell, не край купона (EAAE-шорсткість робить реальну площу невимірною). Звідси прохання експонувати лише активну грань: той самий знаменник і в струмі, і в ICP-MS | [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) |
| **Підкладки** | Ti-6Al-4V (контроль) · Ti-6Al-7Nb · CP-Ti Gr4 · β-Ti-13Nb-13Zr · Ta · Ti-15Zr. Кількість реплік і розкладку купонів між тестами канон не фіксує → лист просить ціну за купон | [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) |
| **Au-стеля (опц.)** | Ti-купон із тонким Au на активній грані — стеля DET-порівняння. ⚠️ Канон-дому не має: живе лише в сусідньому аркуші й CEM | [`anchor_alloy_rfq`](anchor_alloy_rfq.md) §1 · `tools/cad/cem/ti_coin.au.json` |
| **Анод** | dgrFAD-GDH + Os-полімер на fMWCNT · genipin-chitosan-CNC · Nafion-g-PSBMA. E°(Os) = **+309 мВ vs NHE** — іде в лист як вікно потенціалів (опублікована властивість медіатора, не наш прогноз) | [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **Катод** | Laccase + nCoCuCeZIF на MWCNT (DET) | [`01_03 §2.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **Пара ZIF-стабілізації** | катод **без** нанозиму ⊥ катод **з** нанозимом, той самий 30-day протокол → різниця спаду струму ізолює стабілізацію ФЕРМЕНТУ. ⚠️ Трекер пише «bare + ZIF-coated»; лист бере єдине прочитання, за якого порівняння ізолює саме цей ефект (голий Ti без ферменту каталітичного струму не дає) — прочитання на підтвердження (§6) | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 — другого дому немає |
| **Хто наносить стек** | відкрите: (A) лабораторія — з наших матеріалів за нашим протоколом ⊥ (B) ми привозимо функціоналізовані купони. Лист просить ціну на обидві | §6 |
| **Поводження** | ⛔ EtO · автоклав · сухий жар на функціоналізованому купоні (денатурація ферментів); жодних консервантів у середовищі без узгодження | [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md) |

---

## 2. Середовище

**Синтетичний ксилемний сік** — дзеркало рецепта [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (цільова порода *Pinus sylvestris* — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)):

| Компонент | Діапазон |
|---|---|
| Яблучна кислота | 1–5 mM |
| Щавлева кислота | 0.5–2 mM |
| KNO₃ | 2–5 mM |
| CaCl₂ | 0.5–2 mM |
| MgSO₄ | 0.2–1 mM |
| Фітосидерофори (опц.) | 0.01–0.1 mM |

- ⚠️ **Температурний рядок того рецепта (20–40 °C, цикл) належить прискореному тесту [`01_02 §2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), не монеті** — у лист він не йде. Coin-тест: **20–25 °C** ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
- ⚖️ **pH канон тримає ДВОМА смугами:** [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) — 5.0–5.5 ⊥ [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) — 4.5–5.5 (а реф останнього на [`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md) pH-числа не містить). Катодне середовище — pH 4.5 (там же, §3.5). **Лист смуги не обирає:** межею називає обʼєднання 4.5–5.5, set-point — «confirmed before the order», ціну просить **за pH-умову**, тож лишається чинним за обох присудів.
- 🔴 **Діапазони кальцію й оксалату разом не готуються:** кожен кут рецептури пересичений щодо оксалату кальцію на обох pH-смугах ([`SUMMARY §HW.3`](../ebfc/in_silico/SUMMARY.md)), тож точна рецептура «before the order» винесе Ca, оксалат або обидва далеко нижче діапазону — котрий, ⚖️ [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.3. **Лист вибору не робить:** «point values within these ranges» знято, несумісність названо лабораторії як факт приготування, а QC партії просить перевірку на осад — порогу не ставить.
- 🔴 **Глюкози в рецепті немає, а анод без субстрату `j_max` не дає.** Специфікації середовища для coin-тесту канон не тримає: глюкоза в ньому стоїть лише умовою літературного виміру ([`01_03 §1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)) і сценаріями in-silico L4 ([`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md), `Km` там «Estimated»). Лист: концентрація «confirmed before the order» + опційна серія глюкози з ціною за точку, бо споживач даних (`40_validate_vs_experiment.py`) чекає `Km` саме із серії.
- ⚠️ **Провенанс рецепта не звірено:** обидва джерела [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) без DOI, і пошук за точними назвами 2026-09-13 їх не знайшов. Це **не** доказ відсутності, але й не підстава подавати рецепт лабораторії як літературно валідований — тому в листі він «working composition». Виміряний склад соку *Pinus sylvestris* — робота біо-хабу ЧНУ ([`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md)).
- **Мікробний ріст** у глюкозному середовищі за 30 днів канон не адресує → лист питає метод контролю, а добавки дозволяє лише за узгодженням.

---

## 3. Вимірювальна батарея

Пороги pass/fail нижче — **для нас**; у лист вони не йдуть (§0 п.3). У лист іде лише колонка «Задаємо ⊥ питаємо».

| # | Вимір | Задаємо ⊥ питаємо | Що судить (гейт) | Дім |
|---|---|---|---|---|
| **A** | CV, день 0 | задаємо: анод без глюкози і з нею, катод у катодному середовищі · питаємо: метод `k_s`/`n_e` | анод: `j_max` (мкА/см²) · `k_s` · `n_e` | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **A** | EIS, день 0 | питаємо: частоти · амплітуду · DC-bias · межі приладу з ОБОХ боків | `R_ct` межі фермент↔метал. Катодний `R_ct` апріорі не передбачуваний → саме coin-EIS вирішує DET-маржу | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) (EIS Predictions) · [`fmea_fmeca_register`](../hardware/fmea_fmeca_register.md) §1 #1 |
| **B** | `V_OC` пари + OCP кожного електрода | питаємо: критерій стабілізації · конфігурацію комірки | `V_OC` ≥ 700 мВ pass · 600–700 conditional (LTC3108) · < 600 fail | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) — дзеркало [`02_03 §1.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) |
| **B** | напруга під ≈25 мкА, та сама пара | задаємо струм | `R_int ≤ (V_OC − VIN(CS)) × VIN(CS) / PIN(CS)` | [`02_03 §1.5`](../../02_03_BQ25570_MPPT_Nano_Power.md) |
| **B опц.** | P-V крива + та сама на подвоєній площі | питаємо, як подвоїти площу | MPP-фракція; площа як одно-анкерна мітигація `R_int` | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.13 |
| **C** | 30-day potentiostatic hold @ V_op, 20–25 °C | питаємо: V_op з CV дня 0 · графік повторних CV · обʼєм і заміну середовища | ≥ 80 % retention `j_max` | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **D** | Cl⁻ step-ramp до 0.25 М NaCl, катод | питаємо: кроки · як референс не додає Cl⁻ | не нижче −10 % (ціль +7.5 %) | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · ціль — таблиця «Катод» [`01_03 §1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (⚠️ сам §3.5 відсилає за нею в §2.2, де числа немає) |
| **E** | UCST −10 °C → +25 °C, анод із мембраною | задаємо: тест ВІДНОВЛЕННЯ при +25 °C, не вимір при холоді · питаємо: витримки | струм відновлюється до 100 % | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) |
| **F** | ICP-MS середовища | задаємо: елементи й рівні, які метод мусить розділити · питаємо: LOQ у матриці · обʼєм | V ≤ 0.02 · Al ≤ 0.05 µg/см² (токсичні, 4V/7Nb); Nb/Zr/Ta informational; Os + метали ZIF | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **F** | Ti у тому самому аліквоті | задаємо рівень | Ti < 0.1 µg/см² — ціль **прискореного** тесту, не coin-гейта | [`01_02 §2.4`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) |
| **G опц.** | матриця: ±5 % strain @ 0.1 Гц, 10,000 циклів · мембрана: абієтинова кислота 10 мг/мл у соку, 7 днів | питаємо: in-house чи партнер | неелектрохімічні ноги того самого переліку | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |

- ⚖️ **Часова база µg/см² не зафіксована.** Гейт [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) тривалості експозиції не називає; [`01_02 §2.4`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) формулює ціль як результат прискореного тесту, а [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) ділить на те саме 0.02 µg/см² річну швидкість (µg/см²/рік), тобто читає його як річну межу. Від прочитання залежить потрібний LOQ, тож лист рівні дає, а часову базу відкрито називає незафіксованою й просить LOQ у µg/л + обʼєм + площу — з цього обчислюється будь-яка база.
- ⊕ **Два методичні питання F — хімія методу, не наші числа, у каноні їх немає:** хлорид матриці утворює поліатомну інтерференцію на ізотопі V, що міряється ICP-MS (найсуворіший рівень таблиці сидить саме на V); Os втрачається летким оксидом під час окисної пробопідготовки (Os — вимір самого [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)). Обидва лист ПИТАЄ, способу не приписує.
- ⚠️ **Послідовність руйнівних ніг канон не задає** — D і E на тих самих купонах, що й C, чи на окремих репліках. Від цього залежить кількість купонів, тож лист просить розкладку в лабораторії, а присуд лишається за нами (§6).

---

## 4. Формат даних (що повертають)

- **Сирі файли приладу + відкритий експорт.** Споживач даних — `tools/in_silico/scripts/40_validate_vs_experiment.py`: він зіставляє наші прогнози з виміром, а фітовані параметри без спектра не дозволяють перефітити іншою еквівалентною схемою.
- **Поля, які той скрипт споживає:** `j_max` · `Rct` · `Rs` · `Cdl` · `OCV` · `Km` · `stability_30d_pct`. Лист просить величини, з яких обчислюється кожне (сирі CV/EIS/хроноамперометрія/OCV + серія глюкози).
- ⚠️ **`j_max` у скрипті — «CV peak current density», а в моделі L4 — параметр Міхаеліса-Ментен** ([`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md), L4). Сирі CV за кожної концентрації глюкози дають обидва, тому лист не просить «j_max» одним числом.
- **ICP-MS:** LOD/LOQ · бланки · калібрування · spike recovery у матриці соку · розведення · обʼєми.
- **Повернення купонів** після тесту (подальший огляд поверхні).

---

## 5. IP / публікація

- **Defensive publication** → специфікацію відкрито; CDA покриває комерц-умови (ціни/строки/QC), НЕ новизну ([`rfq_registry`](rfq_registry.md) §3; [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)). Конфіденційності вже публічного лист не обіцяє.
- **Результати — до публікації** ([`00_02 §2.1`](../../00_02_Academic_Integration_and_IP.md) Стаття 2; пара ZIF-стабілізації живить саме її — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24) → лист питає умови лабораторії на публікацію згенерованих нею даних, а не відкриває цю тему після підпису.

---

## 6. Відкрите, яке лист обходить питанням (присуд — не тут)

| Відкрите | Як лист лишається чинним | Дім присуду |
|---|---|---|
| pH соку: 5.0–5.5 ⊥ 4.5–5.5 | межа = обʼєднання · set-point «before the order» · ціна за pH-умову | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.3 |
| рецептура: Ca ⊥ оксалат — у діапазонах разом пересичені | несумісність названо як факт приготування · точна рецептура «before the order» · QC партії на осад | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.3 |
| глюкоза: концентрація / серія | «before the order» + опційна серія з ціною за точку | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 |
| часова база µg/см² | рівні названо, база — «still being fixed»; LOQ + обʼєм + площа + кумулятивні дані | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 · HW.3 |
| матриця тестів: репліки · субстрат катодних купонів · послідовність C/D/E | ціна за одиницю + розкладку пропонує лабораторія | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 (пріоритети живить HW.36) |
| хто наносить стек: (A) лабораторія ⊥ (B) ми / партнер | обидві опції з окремою ціною | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 · HW.5 |
| «bare» у парі ZIF-стабілізації | прочитання «катод без нанозиму» названо вголос | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 |
| реальний склад і pH соку *Pinus sylvestris* | «working composition» | біо-хаб ЧНУ, [`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md) |

---

## 7. Dispatch checklist (👤)

- [ ] 👤 **Квота й спроможність — зараз**, паралельно зі Spec A [`ebfc_chem_rfq`](ebfc_chem_rfq.md): купони й фермент сходяться саме тут, тож цикл відповіді лабораторії не повинен стартувати останнім. **Замовлення — після** присудів §6 і дат прибуття купонів ([`anchor_alloy_rfq`](anchor_alloy_rfq.md)) та стеку.
- [ ] 👤 **Адресати.** Кандидат реєстру — **EL-CELL (DE)**. ⚠️ Публічна сторінка його application-lab (звірено 2026-09-13) описує battery-R&D (lithium-ion): клієнтські електроди й протокол «за інструкціями» бере, ICP-MS і ISO/IEC 17025 не згадано → спроможність під водний ферментний електрод не підтверджена, і лист її ПИТАЄ, а не припускає. Біоелектрохімічна лабораторія / CRO — **TBD, не контактовано**. Паралельно — біо-хаб ЧНУ **ACAD** ([`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md), MoU passive).
- [ ] 👤 **CDA-шаблон** — комерц-умови ([`rfq_registry`](rfq_registry.md) §3).
- [ ] 👤 **Після відповіді:** висновок (не чужі ціни й внутрішні факти) → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24.

---

## 📤 Dispatch block (EN) — paste into lab email

> Ready-to-send English text. Working body above stays Ukrainian. Anything our side
> must NOT disclose is deliberately absent — **немає:** наших порогів pass/fail (§3 — сліпий аналіз; виняток — рівні ICP-MS,
> бо їх мусить розділити метод) · in-silico прогнозів (`SUMMARY.md`, `40_validate_vs_experiment.py`) · відкритих присудів
> ЯК суперечок (лист каже «confirmed before the order») · імен кандидатів, академ-каналу й інших постачальників ·
> трекер-ID/канон-рефів · привʼязки пари ZIF-стабілізації до конкретної статті · статус-маркерів.
> Адресат — **електрохімічна лабораторія**; друк купонів і матеріали стеку їдуть окремими листами сусідніх аркушів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

RFQ — CV/EIS, open-circuit and load point, 30-day stability and ICP-MS ion release on enzyme-coated titanium-alloy coupons in synthetic xylem sap (R&D programme)

### Scope of request

We are an R&D group developing a tree-integrated enzymatic bio-fuel cell for forest monitoring. Before committing to full-size parts we validate the electrode chemistry on flat metal coupons, and we are looking for a laboratory to run the electrochemical characterisation and the ion-release analysis on those coupons. The coupons and the electrode materials come from other suppliers; what we buy from you is measurement — traceable raw data, taken in a medium that reproduces tree sap rather than a generic buffer, because both the metal's ion release and the enzymes' behaviour depend on the sap chemistry.

This is a request for a quotation and a capability statement, not yet an order. Several parameters are still being fixed on our side and are marked **"confirmed before the order"** below — please price those per unit, so that we can size the final work order from your quote.

We deliberately send neither our pass/fail thresholds nor our model predictions: we want the analysis to be blind to the expected outcome. The only numbers given are those your method has to be designed around.

### Specimens we supply

- **Geometry:** flat disc **Ø16 mm × 1 mm** with a small tab or edge hole for the potentiostat clip. One face is the **active face (projected area 2.01 cm²)**; the tab lies outside it.
- **Expose only the active face** — for example in a flat cell whose O-ring window defines the area. Current density and ion release are both normalised per unit of exposed area, so that area has to be known exactly and must not include the back face or the edge. If you propose full immersion instead, say so and state the total exposed area.
- **Substrate alloys** (several replicate coupons each — please price per coupon): Ti-6Al-4V (control) · Ti-6Al-7Nb · CP-Ti Grade 4 · Ti-13Nb-13Zr (β-Ti) · tantalum · Ti-15Zr — plus, optionally, one titanium coupon with a thin **gold** coating on the active face, used as a best-case electron-transfer reference. Coupons may arrive in more than one batch; tell us whether a later batch can run as a separate campaign at the same unit prices.
- **Electrodes built on the coupons:**
  - *Anode:* FAD-dependent glucose dehydrogenase wired by an osmium redox polymer on functionalised carbon nanotubes, under a genipin-crosslinked chitosan / cellulose-nanocrystal hydrogel and a zwitterion-grafted Nafion membrane. The mediator's published formal potential is **+309 mV vs NHE** — given so you can set the potential window.
  - *Cathode:* laccase combined with a Co/Cu/Ce zeolitic-imidazolate-framework (ZIF) nanozyme on carbon nanotubes, working by direct electron transfer.
  - *Matched cathode control:* the same cathode **without the nanozyme**, run through the identical stability protocol in parallel. The difference in current decay between the two isolates the stabilising effect of the nanozyme on the enzyme.
- **Who applies the electrode layers — tell us which option you can offer:**
  - **(A)** you apply the layers to our coupons from materials we supply, following our written immobilisation protocol — quote protocol set-up as a development line, then a price per coupon; or
  - **(B)** we deliver coupons already functionalised and you measure only — in that case state how you receive and store enzyme electrodes and how soon after receipt the first measurement starts, because the day-0 baseline is the reference for every later result.
- **Handling:** do **not sterilise** functionalised coupons — no ethylene oxide, autoclave or dry heat, all of which denature the enzymes. Add **no preservative or antimicrobial agent** to any medium without agreeing it with us first: every additive has to be checked against the enzymes on the electrode. In particular, **do not use sodium azide** — it inhibits laccase at micromolar concentrations.

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

- **Exact recipe** (point values): **confirmed before the order.** Calcium and oxalate cannot both sit inside the ranges above — at those levels the medium exceeds the solubility of calcium oxalate — so the confirmed recipe will set calcium, oxalate or both well below their ranges. Quote medium preparation per batch.
- **pH:** buffered by the recipe's own organic acids, not by an added buffer system. The set-point lies **within pH 4.5–5.5** and is **confirmed before the order**; please quote **per pH condition**, as we may add a second condition at the other end of that band. Tell us how you set and hold pH over 30 days and how often you log it.
- **Glucose** is added as the anode substrate; its concentration is **confirmed before the order**. As a separately priced option, quote a **glucose concentration series** (price per concentration point), from which an apparent Michaelis constant can be extracted.
- **Cathode medium:** pH 4.5, air-exposed. Tell us how you keep it air-saturated and whether you log dissolved oxygen.
- **Microbial growth:** a glucose-containing medium held for 30 days will support it, and growth would consume the substrate and confound the stability result — state how you prevent it (additives only by agreement, see Handling).
- **Medium QC per batch:** pH with a calibrated meter, conductivity, verification of the major ions, and a check that the batch carries **no precipitate** — right after preparation and again at the end of the 30-day hold. State the methods and include the records in the report.

### Measurements requested

**General conditions.** Electrochemical measurements at the controlled temperature of the stability hold, **within 20–25 °C**, logged throughout. Potentials against the reference electrode used, with the conversion to SHE stated. Current density normalised to the **projected geometric area of the exposed window** — not to an electrochemically estimated area (you may report such an estimate in addition): the etched surface is too rough for its true area to be measured reliably.

**A. Electrode characterisation — every anode and cathode coupon, day 0**

- **Cyclic voltammetry.** Anode: in the absence of glucose (for the heterogeneous electron-transfer rate constant *k*ₛ and the apparent number of electrons *n*) and in its presence (for the maximum catalytic current density, µA/cm²). Cathode: catalytic current density in the air-exposed medium, and *k*ₛ where a non-turnover signal can be resolved. State your analysis method — we would expect a scan-rate series with Laviron analysis, but tell us if you use another.
- **EIS:** charge-transfer resistance of the enzyme–metal interface, solution resistance and double-layer capacitance. Propose frequency range, amplitude and DC bias. **State your instrument's impedance and frequency limits at both ends:** our model cannot predict the cathode's charge-transfer resistance even to within orders of magnitude, so the measured cathode spectrum is the decisive input, and the instrument must resolve a very small interfacial arc as well as a large one.

**B. Open circuit and load point — anode/cathode coupon pairs**

- **Open-circuit voltage** of the pair, plus each electrode's open-circuit potential against the reference. Report the stabilisation criterion you applied and the drift at the moment of reading.
- **Cell voltage while drawing a constant current of about 25 µA** from the same pair, read soon after the open-circuit value. Together these two readings decide whether our power-management circuit can cold-start from the cell: the open-circuit voltage decides whether it can start at all, and the internal resistance derived from the two readings decides whether it starts under load.
- Propose the cell configuration in which the anode sees the sap and the cathode the air-exposed medium (one compartment or two).
- *Option:* a full **polarisation and power curve** of the pair, and the same curve at **double the electrode area** — for example two coupons connected in parallel per electrode; tell us how you would do it.

**C. 30-day stability — anode and cathode coupons, including the matched cathode control**

- **Potentiostatic hold for 30 days.** Propose the hold potential from the day-0 CV and agree it with us before the hold starts.
- **Repeat the CV at intervals you propose** (price per check-point), so that retention of the maximum catalytic current can be tracked.
- **Substrate depletion and acidification.** During the hold the anode consumes glucose and its oxidation product acidifies the medium, so a small fixed volume can fail a stability test through depletion alone. Either **replace the medium on a schedule** or use a volume large enough that glucose and pH stay near their set-points for the whole 30 days — propose which, with the volume per coupon and the schedule, and **log glucose concentration and pH at every replacement or sampling**. Keep every removed portion for ICP-MS (F), so that the release figure stays cumulative.
- Quote per potentiostat **channel-day** and state how many channels you can dedicate at once.

**D. Chloride tolerance — cathode coupons**

- **Stepwise NaCl additions** to the cathode medium **up to 0.25 M**; propose the steps and report the catalytic current at each step relative to the chloride-free start.
- State your reference electrode and how you keep its filling solution from adding chloride to the cell — chloride is itself one of the variables under test.

**E. Freeze–thaw recovery — anode coupons carrying the membrane**

- One cycle: **freeze at −10 °C, thaw to +25 °C**, then measure the current against its pre-freeze value. This is a **recovery test at +25 °C**, not a measurement at the cold temperature. Propose the hold time at each temperature and whether the coupon is frozen in the medium.

**F. Ion release by ICP-MS**

- Analyse a **medium blank** before exposure and the **exposure medium at the end of the 30-day test**; quote intermediate sampling as an option.
- **Elements:** Ti, V, Al, Nb, Zr, Ta from the substrate (as relevant per alloy) · Os from the anode mediator · Cu, Co, Ce from the cathode nanozyme.
- Report concentrations (µg/L) together with the solution volume and the exposed area, so that release can be expressed per cm² of exposed face.
- **Sensitivity:** the levels our comparison has to resolve are **V 0.02 µg/cm², Al 0.05 µg/cm² and Ti 0.1 µg/cm²** of exposed face. The exposure time those levels refer to is still being fixed on our side, so please state your limit of quantification per element **in this matrix** and the lowest per-cm² release it corresponds to at your proposed volume — lower is better.
- **Two method points to address explicitly:** chloride in the medium forms a polyatomic interference on the vanadium isotope measured by ICP-MS — state how your method removes it (for example a collision/reaction cell); and osmium can be lost as a volatile oxide during oxidising sample preparation — state how you prevent that loss.
- Include blanks, calibration, spike recovery in the sap matrix and dilution factors.

**G. Optional — non-electrochemical tests from the same programme** (in-house or through a partner; if neither, say so and we will source them separately)

- Cyclic mechanical test of the hydrogel matrix: **±5 % strain at 0.1 Hz, 10,000 cycles**.
- Anti-fouling (protein-adsorption) assay of the membrane against an **abietic-acid suspension, 10 mg/mL in synthetic sap, 7 days**.

### Data we need back

Fitted parameters alone are not enough: we compare your measurements against our own models, may refit the raw data with a different equivalent circuit, and intend to publish the results.

- **Native instrument files and an open export** (CSV or ASCII) of every CV, EIS spectrum, potentiostatic hold, open-circuit record and polarisation curve.
- **EIS fits:** the equivalent circuit, fitted values with uncertainties, and the residuals — alongside the raw spectra, never instead of them.
- **Metadata per record:** coupon ID, electrode type, exposed area, reference electrode, temperature and pH logs, instrument and software version.
- **ICP-MS:** per-sample results with limits of detection and quantification, blanks, calibration, spike recoveries, dilution factors and volumes.
- **A deviation log**, photographs of each coupon before and after testing, and **return of all tested coupons**, individually packed with the active face protected — they may be examined further.

### What we ask you to provide

1. **Capability statement:** potentiostat/galvanostat models, current resolution at the µA level, EIS frequency and impedance range, channels available for a 30-day hold, cell type for Ø16 mm discs, reference electrodes suited to an acidic organic-acid medium, a climate chamber reaching −10 °C, and ICP-MS in-house or through a named subcontractor.
2. **Comparable work:** enzyme or other bio-electrodes in aqueous media (redacted examples are fine).
3. **Accreditation and quality system**, with certificate number, issuing body, scope and validity — ISO/IEC 17025 (say whether its scope covers the methods above), ISO 9001 or GLP, whichever you hold.
4. **Itemised prices:** per coupon per test (A, B, D, E) · per channel-day (C) · per CV check-point · medium preparation and QC per batch · ICP-MS per sample for the element panel above · electrode-layer application if you offer option (A), as a development line plus per coupon · data analysis and report · every option separately.
5. **Turnaround:** queue time to start, the fixed 30-day hold, analysis and report — and whether a **short pilot** on one or two coupons (day-0 characterisation, open circuit and load point, no 30-day hold) is possible before the full programme, and at what price.
6. **Quote format:** currency, validity period, payment terms, and the technical point of contact.

### Confidentiality & publication

The technical specification is openly published, so no confidentiality agreement is needed to discuss it; we are happy to sign your standard mutual CDA covering commercial terms (prices, schedules, QC data). We intend to publish the measurement results in a peer-reviewed paper — please state any conditions you attach to publishing data you generate for us, such as acknowledgement or a description of your method.

### Possible follow-on (not part of this quotation)

We also plan a longer accelerated-ageing exposure of coupons in the same medium, with elevated-temperature cycling, mechanical loading, and ion release and EIS at intervals. If that is within your scope, say so and we will send a separate request.

### Commercial & logistics

- Coupons reach you from the manufacturer or from Ukraine; tell us your receiving requirements, including cold-chain handling for functionalised coupons.
- Tell us what documentation you need to receive and handle the materials — osmium-complex polymer, recombinant enzymes, nanomaterials: safety data sheets, end-use statement, entity details, import permits.
- The Incoterms you quote on for returning tested coupons, and any export-control considerations you are aware of.

### Attachments

Nothing is required from us for an initial quotation. On request we supply the written immobilisation protocol, the coupon drawing, and the medium recipe once confirmed.

---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 8. Cross-references

| Ресурс | Що бере |
|---|---|
| [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | test-battery + acceptance-гейти (дім) |
| [`02_03 §1.5`](../../02_03_BQ25570_MPPT_Nano_Power.md) | `V_OC` + `R_int` двоточково, стеля `R_int` (дім деривації); пороги `VIN(CS)`/`PIN(CS)` — [`02_03 §1.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) |
| [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | рецепт синтетичного соку (дім) · [`01_02 §2.4`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) ICP-MS-цілі прискореного тесту |
| [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | Stage-2 геометрія, проєкційна площа, вікно комірки |
| [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md) | заборонені методи стерилізації ферментного стеку |
| [`anchor_alloy_rfq`](anchor_alloy_rfq.md) | підкладка — постачає купони |
| [`ebfc_chem_rfq`](ebfc_chem_rfq.md) | хім-стек — постачає матеріали |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс · §3 IP/CDA · §4.A |
| [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) | in-silico прогнози EIS/L4 — у лист НЕ йдуть |
| `tools/in_silico/scripts/40_validate_vs_experiment.py` | споживач даних — задає формат повернення |
| [`fmea_fmeca_register`](../hardware/fmea_fmeca_register.md) | §1 рядок #1: DET-маржа чекає coin-EIS |
