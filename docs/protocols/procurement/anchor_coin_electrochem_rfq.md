# Anchor Coin — Electrochemistry & ICP-MS Lab RFQ (Stage-2 Ti-coin in-vitro test, CRO-ready)

> **Що це:** RFQ-аркуш для **вимірювальної** половини Stage-2 coin — лабораторії, що фізично проганяє CV/EIS · `V_OC` + `R_int` · 30-day · Cl⁻ · UCST · ICP-MS на функціоналізованих купонах у синтетичному ксилемному соку.
> Два сусідні аркуші ПОСТАЧАЮТЬ те, що тут міряється: підкладку — [`anchor_alloy_rfq`](anchor_alloy_rfq.md), хім-стек — [`ebfc_chem_rfq`](ebfc_chem_rfq.md); гейти — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).
> **Статус:** 🟡 робочий артефакт (не канон). **Усі числа — дзеркало канону**, дім кожного названо поруч; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24.
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Анкер coin (Stage-2) — тест» · hard-constraint дім §4.A).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — специфікація відкрита; CDA = стандартні комерц-умови; результати призначені до публікації ([`00_02 §2.1`](../../00_02_Academic_Integration_and_IP.md)).

---

## 0. Як користуватись + cover-note

0. ⚖️ **ЛИСТ РІЖЕТЬСЯ НА ДВА (founder 2026-09-17) — на українському маршруті це не вибір, а факт:** ферментна електрохімія й ICP-MS в Україні не живуть під одним дахом, а режим ЦКК НАН (2 год/зміну) несумісний із 720 безперервними годинами ноги C ([`ua_vendor_map §4`](ua_vendor_map.md)). **Форма аркуша не міняється** — для лабораторії «під одним дахом» (ЄС-кандидати) він лишається одним листом; ріжеться він по вимірюванню **F**. **Що це змінює технічно, і це не адресати:** середовище після 30 діб стає ЗРАЗКОМ, який мусить пережити дорогу — тож перший лист обовʼязково просить **зберігати кожну відібрану порцію** (вже §C), додає **бланк транспортування** (та сама партія середовища, той самий посуд, той самий маршрут — без нього ICP-MS міряє дорогу, а не купон), консервацію проби, посуд і ланцюг зберігання; другий лист (ICP-MS) отримує ті аліквоти з їхньою історією. ⛔ Обидва листи мусять називати ту саму площу грані й той самий обʼєм — інакше µg/см² рахуються від різних знаменників. **Український маршрут має тексти — §📤 (UA) ↓:** ТЗ 1 (електрохімія, установа НАН — зміст EN-блоку без F плюс відбір, зберігання й передача проб) і ТЗ 2 (ICP-MS); знаменник обидва беруть зі спільного журналу відбору.
1. **Окремий аркуш, а не третій лист у сусідах:** адресат інший (лабораторія, не друк-бюро й не постачальник матеріалу), предмет інший (послуга виміру, не компонент), і тест СПОЖИВАЄ обидва сусідні аркуші — лист [`anchor_alloy_rfq`](anchor_alloy_rfq.md) прямо каже, що електрохім-характеризації в ньому немає.
2. **Квоту й спроможність просити можна зараз, замовлення — ні.** Лист написано так, щоб він лишався чинним за будь-якого з відкритих присудів §6: усе відкрите він просить оцінити поштучно («quote per …») замість фіксувати.
3. **Сліпий аналіз.** Лабораторії йдуть лише числа, під які вона мусить збудувати МЕТОД (середовище, температури, навантаження, крок Cl⁻, рівні ICP-MS). Наші пороги pass/fail і in-silico прогнози в лист не йдуть — фіт не повинен знати, що від нього очікують. ⚖️ **Делегований присуд 2026-09-13** (форма листа; founder може перевернути до відправки). **Підстава:** нога «правдиво» критерію місії ([`00_01 §1.1`](../../00_01_Vision_Mission_and_Roadmap.md)) — фіт не підлаштовується під очікуване. **Ціна:** лабораторія не попередить, якщо число «не сходиться» з нашим прогнозом, тож ранній сигнал про помилку методики ловиться лише нашою власною звіркою сирих даних. **Виняток і його межа:** рівні ICP-MS ідуть, бо метод мусить їх розділити — саме цей виняток лист S-N пізніше свідомо не переніс ([`sn_fatigue_test_plan`](../anchor/sn_fatigue_test_plan.md) §4.2 п. 5).
4. **Відповідь лабораторії в репо не комітиться** — ціни, внутрішні методики й номери сертифікатів є чужими операційними фактами. Сюди й у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 іде лише наш висновок.

---

## 1. Зразки (що постачаємо)

| Поле | Специфікація | Дім |
|---|---|---|
| **Геометрія** | диск **Ø16×1 мм**; 1 грань = π·8² = **2.01 см² ≈ A_electrode**; «вушко» під кліпсу потенціостата — поза активною гранню | [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_03 §3.7`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) п.4 |
| **Площа** | `j` — на **проєкційну** площу; площу задає **вікно** flat O-ring cell, не край купона (EAAE-шорсткість робить реальну площу невимірною). Звідси прохання експонувати лише активну грань: той самий знаменник і в струмі, і в ICP-MS | [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) |
| **Підкладки** | Ti-6Al-4V (контроль) · Ti-6Al-7Nb · CP-Ti Gr4 · β-Ti-13Nb-13Zr · Ta · Ti-15Zr. Розкладку купонів між тестами канон фіксує (⚖️ 2026-09-18: які електроди на якому сплаві · D і E на свіжих купонах 4V); відкритим лишається лише число реплік → лист просить ціну за купон | [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · розкладка — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **Непокриті купони — бічна ICP-MS-серія** | по три на сплав, та сама активація поверхні, **без** шарів стеку; лише занурення на 30 діб при **pH 4.5** і ICP-MS (без каналів потенціостата). ⚠️ Не плутати з «катодом без нанозиму» ↓: там фермент є, тут металу нічого не вкриває — у листі два різні слова | [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (⚖️ 2026-09-17) |
| **Au-стеля** | Ti-купон із тонким Au на активній грані — стеля DET-порівняння. **Не опційний (⚖️ 2026-09-18):** несе катод дня 0 як межа осі «оксид ↔ DET» ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)) і є ВХОДОМ гілок (1)/(2) ратифікованого правила вибору катодного важеля ([`01_03 §3.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md): «катод на Au ≈ / помітно кращий за катод на Ti») | [`01_03 §3.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`anchor_alloy_rfq`](anchor_alloy_rfq.md) §1 · `tools/cad/cem/ti_coin.au.json` |
| **Анод** | dgrFAD-GDH + Os-полімер на fMWCNT · genipin-chitosan-CNC · Nafion-g-PSBMA. E°(Os) = **+309 мВ vs NHE** — іде в лист як вікно потенціалів (опублікована властивість медіатора, не наш прогноз) | [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **Катод** | Laccase + nCoCuCeZIF на MWCNT (DET) | [`01_03 §2.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **Пара ZIF-стабілізації** | катод **без** нанозиму ⊥ катод **з** нанозимом, той самий 30-day протокол → різниця спаду струму ізолює стабілізацію ФЕРМЕНТУ. «bare» = катод без нанозиму — ⚖️ ратифіковано founder 2026-09-17 | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **Хто наносить стек** | ⚖️ **founder 2026-09-18 (HW.24): один виконавець на всі купони, за замовчуванням (A)** — лабораторія з наших матеріалів за нашим протоколом; (B) лист просить лише як альтернативу, бо виконавця для неї в дереві немає. Розкладка електродів по сплавах — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md). ⚖️ **2026-09-18: один крок протоколу свідомо НЕ наш** — маршрут кріплення MWCNT до Ti декларує виконавець, приймання за 30-денним утриманням струму ([`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) п.2); лист передає йому дві куплені читанням межі (карбодіімід потребує аміну; аміносилан гідролізується при 40 °C) | §6 |
| **Поводження** | ⛔ EtO · автоклав · сухий жар на функціоналізованому купоні (денатурація ферментів); жодних консервантів у середовищі без узгодження | [`01_04 §6.2`](../../01_04_CODIT_and_Xylemointegration.md) |

---

## 2. Середовище

**Синтетичний ксилемний сік** — дзеркало рецепта [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (цільова порода *Pinus sylvestris* — [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)):

| Компонент | Концентрація |
|---|---|
| Яблучна кислота | 2.2 mM |
| KNO₃ | 3.2 mM |
| CaCl₂ | 1.0 mM |
| MgSO₄ | 0.45 mM |
| KOH | до уставки pH (≈ 4.1 mM при 5.75 · ≈ 2.6–2.7 mM при 4.5 — фактичну кількість пише журнал партії) |
| pH | **5.75** · бічна серія непокритих купонів **4.5** |

- ⚠️ **Температурний рядок того рецепта (стала 40 °C, ⚖️ 2026-09-24) належить прискореному тесту [`01_02 §2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), не монеті** — у лист він не йде. Coin-тест: **20–25 °C** ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
- ✅ **pH розсуджено (⚖️ founder 2026-09-17, дім [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)):** уставка **5.75** — виміряний pH соку *P. sylvestris* (Tarvainen 2023); бічна серія непокритих купонів лише під ICP-MS при **4.5**, бо вищий pH може занижувати вивільнення Al. Катодне середовище лишається pH 4.5 ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
- 🔴 **Буфер слабкий, і лист мусить це сказати:** β ≈ 0.61 mM на одиницю pH при 5.75 — pH на 0.1 зсуває ≈ 0.066 mM сильної кислоти, а анод кислоту виробляє ([`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), script 67 Q6). Звідси заміна середовища й журнал pH у C — умова, не побажання. Число в лист не йде: лабораторії досить знати, що середовище слабко буферне.
- ✅ **Рецептура — точка (⚖️ founder 2026-09-17):** оксалат прибрано, бо з мілімолярним Ca він пересичує оксалат кальцію в кожному куті колишніх діапазонів ([`SUMMARY §HW.3`](../ebfc/in_silico/SUMMARY.md)); решта — геометричні середини, фітосидерофори поза рецептурою. Перевірку партії на осад лист лишає — вона дешева й ловить помилку приготування.
- ✅ **Глюкоза розсуджена (⚖️ founder 2026-09-17, дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)):** серія дня 0 **0/1/2/5/10/20/50 мМ** на кожному анодному купоні — із неї `K_m^app`, якого чекає `40_validate_vs_experiment.py` — плюс утримання **10 мМ**; без азиду; заміна середовища й журнал глюкози й pH (вимога C). Корозійна рецептура [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) глюкози не несе — її додає лише coin-середовище.
- ⚠️ **Провенанс рецепта звірено лише наполовину:** pH має первинку (Tarvainen 2023), а концентрації іонів — середини діапазонів, чиї джерела пошуком за точними назвами не знайдено. Тому в листі рецепт і далі «working composition», не літературно валідований склад. Виміряний склад соку *Pinus sylvestris* — робота біо-хабу ЧНУ ([`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md)).
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
| **F** | ICP-MS середовища | задаємо: елементи й рівні, які метод мусить розділити · питаємо: LOQ у матриці · обʼєм | V ≤ 0.02 · Al ≤ 0.05 µg/см² (токсичні, 4V/7Nb) — **кумулятив 30 діб: ранжування + ранній провал**, не pass/fail; Nb/Zr/Ta informational; Os + метали ZIF | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |
| **F** | Ti у тому самому аліквоті | задаємо рівень | Ti < 0.1 µg/см² — ціль **прискореного** тесту, не coin-гейта | [`01_02 §2.4`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) |
| **G опц.** | матриця: ±5 % strain @ 0.1 Гц, 10,000 циклів · мембрана: абієтинова кислота 10 мг/мл у соку, 7 днів | питаємо: in-house чи партнер | неелектрохімічні ноги того самого переліку | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) |

- ✅ **Часову базу розсуджено (⚖️ founder 2026-09-17, дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)):** рівні F на coin — кумулятив за 30-денну експозицію на см² активної грані, для ранжування сплавів і раннього провалу; формальний pass/fail — прискорений тест [`01_02 §2.4`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md). LOQ у µg/л + обʼєм + площу лист і далі просить: з них обчислюється кумулятив, а нижче рівнів дані все одно ранжують.
- ⊕ **Два методичні питання F — хімія методу, не наші числа, у каноні їх немає:** хлорид матриці утворює поліатомну інтерференцію на ізотопі V, що міряється ICP-MS (найсуворіший рівень таблиці сидить саме на V); Os втрачається летким оксидом під час окисної пробопідготовки (Os — вимір самого [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)). Обидва лист ПИТАЄ, способу не приписує.
- ✅ **Послідовність руйнівних ніг задано:** D і E — на СВІЖИХ купонах Ti-6Al-4V, не після C (⚖️ 2026-09-18, [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)); звідси й більша кількість купонів 4V (лист купонів — «at 12 and at 19», де 6 з них — запас 12-тижневого тесту, ⚖️ 2026-09-25). ⚠️ Англійський текст листа розкладки в лабораторії НЕ просить — він її називає (Specimens · заголовки D і E), а просить лише ціни за купон і тест, канал-день, кількість каналів і опцію нанесення (A ⊥ B).

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
| число реплік на плече | ціна за одиницю й кількість каналів — від лабораторії; лист каже «no comparison runs on a single replicate» і фіксує число після цін | [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) розкладка (⚖️ 2026-09-18, HW.24) |
| реальний склад соку *Pinus sylvestris* (pH — вже первинка) | «working composition» | біо-хаб ЧНУ, [`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md) |

✅ **Знято з таблиці 2026-09-18 — розсуджено founder (HW.24), дім [`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md):** субстрат катодних купонів · послідовність C/D/E (D і E — на свіжих купонах 4V) · хто наносить стек (один виконавець, за замовчуванням A).

✅ **Знято з таблиці 2026-09-17 — розсуджено founder, дім присуду в каноні:** pH соку і рецептура ([`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)) · глюкоза, часова база ICP-MS і прочитання «bare» у парі ZIF ([`01_03 §3.5`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).

---

## 7. Dispatch checklist (👤)

- [ ] 👤 **Квота й спроможність — зараз**, паралельно зі Spec A [`ebfc_chem_rfq`](ebfc_chem_rfq.md): купони й фермент сходяться саме тут, тож цикл відповіді лабораторії не повинен стартувати останнім. **Замовлення — після** присудів §6 і дат прибуття купонів ([`anchor_alloy_rfq`](anchor_alloy_rfq.md)) та стеку.
- [ ] 👤 **Адресати.** Українські кандидати — [`ua_vendor_map §4`](ua_vendor_map.md) (ІМБГ НАН · ІБК НАН Львів · ФМІ ім. Карпенка; ICP-MS окремо — ІКХХВ / ІГМР / НУБіП). ⚠️ **Інститутові НАН цей EN-аркуш як є не надсилати:** предметом договору там є ТЗ, тож лист іде проєктом ТЗ українською під договір НДР ⊥ послугу — форма й прецедент у [`anchor_hip_rfq`](anchor_hip_rfq.md); зміст аркуша не міняється, міняється оболонка — **тексти готові: §📤 (UA) ↓, ТЗ 1 і ТЗ 2** (⚠️ написано 2026-09-23, founder ще не бачив). ⛔ **ТЗ 2 надсилати не пізніше за ТЗ 1:** вимоги аналітика до посуду й консервації мусять дійти до лабораторії ТЗ 1 до початку експозиції. 🔴 **В Україні лист майже напевно розпадеться на два** (електрохімія ⊥ ICP-MS), і головна перешкода — режим доступу ЦКК: 2 год/зміну проти наших 720 безперервних годин на канал. ЄС-кандидати desk-пошуку: EndoLab (DAkkS D-PL-18838-02-01: ASTM F3306 + F2129) · Questmed (D-PL-18753-02-00: F3306, ICP-MS Ti/V/Al) · Zimmer & Peacock (NO, ферментні електроди) · UJ ZASB (PL). Кандидат реєстру — **EL-CELL (DE)**, у резерв: ⚠️ Публічна сторінка його application-lab (звірено 2026-09-13) описує battery-R&D (lithium-ion): клієнтські електроди й протокол «за інструкціями» бере, ICP-MS і ISO/IEC 17025 не згадано → спроможність під водний ферментний електрод не підтверджена, і лист її ПИТАЄ, а не припускає. Біоелектрохімічна лабораторія / CRO — **TBD, не контактовано**. Паралельно — біо-хаб ЧНУ **ACAD** ([`00_02 §1.1`](../../00_02_Academic_Integration_and_IP.md), MoU passive).
- [ ] 👤 **CDA — на комерційній стадії, не перед запитом:** лист сам каже, що для обговорення відкритої специфікації угода не потрібна; стандартний взаємний CDA — при замовленні ([`rfq_registry`](rfq_registry.md) §3).
- [ ] 👤 **Після відповіді:** висновок (не чужі ціни й внутрішні факти) → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24.

---

## 📤 Dispatch block (EN) — paste into lab email

> Ready-to-send English text. Working body above stays Ukrainian. Anything our side
> must NOT disclose is deliberately absent — **немає:** наших порогів pass/fail (§3 — сліпий аналіз; виняток — рівні ICP-MS,
> бо їх мусить розділити метод) · in-silico прогнозів (`SUMMARY.md`, `40_validate_vs_experiment.py`) · відкритих присудів
> ЯК суперечок (лист каже, що число реплік на плече фіксується після цін) · імен кандидатів, академ-каналу й інших постачальників ·
> трекер-ID/канон-рефів · привʼязки пари ZIF-стабілізації до конкретної статті · статус-маркерів.
> Адресат — **електрохімічна лабораторія**; друк купонів і матеріали стеку їдуть окремими листами сусідніх аркушів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

RFQ — CV/EIS, open-circuit and load point, 30-day stability and ICP-MS ion release on enzyme-coated titanium-alloy coupons in synthetic xylem sap (R&D programme)

### Scope of request

We are an R&D group developing a tree-integrated enzymatic bio-fuel cell for forest monitoring. Before committing to full-size parts we validate the electrode chemistry on flat metal coupons, and we are looking for a laboratory to run the electrochemical characterisation and the ion-release analysis on those coupons. The coupons and the electrode materials come from other suppliers; what we buy from you is measurement — traceable raw data, taken in a medium that reproduces tree sap rather than a generic buffer, because both the metal's ion release and the enzymes' behaviour depend on the sap chemistry.

This is a request for a quotation and a capability statement, not yet an order. One parameter is still being fixed on our side — the number of replicate coupons per arm — so please price per coupon and per channel, and we will size the final work order from your quote.

We deliberately send neither our pass/fail thresholds nor our model predictions: we want the analysis to be blind to the expected outcome. The only numbers given are those your method has to be designed around.

### Specimens we supply

- **Geometry:** flat disc **Ø16 mm × 1 mm** with a small tab or edge hole for the potentiostat clip. One face is the **active face (projected area 2.01 cm²)**; the tab lies outside it.
- **Expose only the active face** — for example in a flat cell whose O-ring window defines the area. Current density and ion release are both normalised per unit of exposed area, so that area has to be known exactly and must not include the back face or the edge. If you propose full immersion instead, say so and state the total exposed area.
- **Substrate alloys** (several replicate coupons each — please price per coupon): Ti-6Al-4V (control) · Ti-6Al-7Nb · CP-Ti Grade 4 · Ti-13Nb-13Zr (β-Ti) · tantalum · Ti-15Zr — plus one titanium coupon with a thin **gold** coating on the active face, used as a best-case electron-transfer reference — it carries the cathode layers, so that the cathode on gold can be compared with the cathode on titanium. Coupons may arrive in more than one batch; tell us whether a later batch can run as a separate campaign at the same unit prices.
- **Which electrodes on which alloy:** anodes on every alloy. Cathodes on Ti-6Al-4V (the matched cathode pair of test C and the chloride test D), on Ti-6Al-7Nb, Ti-13Nb-13Zr and Ti-15Zr (day-0 characterisation A and one anode/cathode pair B of the same alloy), and on tantalum and the gold-coated coupon (day 0 only, as the two ends of the oxide ↔ direct-electron-transfer comparison); CP-Ti Grade 4 carries no cathode. No comparison runs on a single replicate; we fix the number of replicates after your prices.
- **Uncoated coupons for an ion-release series:** in addition, **three coupons per alloy** with the same surface treatment but **no electrode layers**, immersed for the same 30 days in the medium at **pH 4.5** and analysed by ICP-MS only (F) — no potentiostat channels.
- **Electrodes built on the coupons:**
  - *Anode:* FAD-dependent glucose dehydrogenase wired by an osmium redox polymer on functionalised carbon nanotubes, under a genipin-crosslinked chitosan / cellulose-nanocrystal hydrogel and a zwitterion-grafted Nafion membrane. The mediator's published formal potential is **+309 mV vs NHE** — given so you can set the potential window.
  - *Cathode:* laccase combined with a Co/Cu/Ce zeolitic-imidazolate-framework (ZIF) nanozyme on carbon nanotubes, working by direct electron transfer.
  - *Matched cathode control:* the same cathode **without the nanozyme**, run through the identical stability protocol in parallel. The difference in current decay between the two isolates the stabilising effect of the nanozyme on the enzyme.
- **Who applies the electrode layers — tell us which option you can offer** (our default is (A), with one party applying the layers to every coupon so that the route is the same across alloys; quote (B) as the alternative):
  - **(A)** you apply the layers to our coupons from materials we supply, following our written immobilisation protocol — quote protocol set-up as a development line, then a price per coupon. **One step of that protocol is deliberately yours: how the carbon-nanotube layer is bonded to the etched titanium.** We specify the RESULT — the layer must survive the 30-day stability run without losing current — and not the recipe, because the route is not reproducible between operators. Tell us what you would use and why. Two constraints we hand you rather than discover later: a carbodiimide coupling needs a primary amine, which bare titanium oxide does not have, and an aminosilane interlayer is known to hydrolyse in water at 40 °C, which is the top of our service envelope; or
  - **(B)** we deliver coupons already functionalised and you measure only — in that case state how you receive and store enzyme electrodes and how soon after receipt the first measurement starts, because the day-0 baseline is the reference for every later result.
- **Handling:** do **not sterilise** functionalised coupons — no ethylene oxide, autoclave or dry heat, all of which denature the enzymes. Add **no preservative or antimicrobial agent** to any medium without agreeing it with us first: every additive has to be checked against the enzymes on the electrode. In particular, **do not use sodium azide** — it inhibits laccase at micromolar concentrations.

### Test medium

**Synthetic xylem sap**, target species Scots pine (*Pinus sylvestris*). Working composition:

| Component | Concentration |
|---|---|
| Malic acid | 2.2 mM |
| KNO₃ | 3.2 mM |
| CaCl₂ | 1.0 mM |
| MgSO₄ | 0.45 mM |
| KOH | to the pH set-point — record the amount added per batch |

- **pH:** **5.75** for the electrode tests; **4.5** for the uncoated ion-release series. There is no added buffer system — malic acid is the only buffer and KOH sets the pH — so the medium is **weakly buffered at 5.75**: a small amount of acid moves its pH noticeably, and a working anode produces acid. Tell us how you set, hold and log pH over 30 days, and plan the medium replacement in C around it. Quote medium preparation per batch and per pH.
- **Glucose** is the anode substrate: **10 mM** in the medium for the 30-day hold and for every other test run at a single concentration. On **day 0**, characterise **every anode coupon at 0, 1, 2, 5, 10, 20 and 50 mM glucose** (A) — we extract an apparent Michaelis constant per coupon from that series — and quote it per concentration point.
- **Cathode medium:** pH 4.5, air-exposed. Tell us how you keep it air-saturated and whether you log dissolved oxygen.
- **Microbial growth:** a glucose-containing medium held for 30 days will support it, and growth would consume the substrate and confound the stability result — state how you prevent it (additives only by agreement, see Handling).
- **Medium QC per batch:** pH with a calibrated meter, conductivity, verification of the major ions, and a check that the batch carries **no precipitate** — right after preparation and again at the end of the 30-day hold. State the methods and include the records in the report.

### Measurements requested

**General conditions.** Electrochemical measurements at the controlled temperature of the stability hold, **within 20–25 °C**, logged throughout. Potentials against the reference electrode used, with the conversion to SHE stated. Current density normalised to the **projected geometric area of the exposed window** — not to an electrochemically estimated area (you may report such an estimate in addition): the etched surface is too rough for its true area to be measured reliably.

**A. Electrode characterisation — every anode and cathode coupon, day 0**

- **Cyclic voltammetry.** Anode: in the absence of glucose (for the heterogeneous electron-transfer rate constant *k*ₛ and the apparent number of electrons *n*) and in its presence (for the maximum catalytic current density, µA/cm²). Cathode: catalytic current density in the air-exposed medium, and *k*ₛ measured oxygen-free, where a non-turnover signal can be resolved — if none can be resolved, say so rather than fitting one. State your analysis method — we would expect a scan-rate series with Laviron analysis, but tell us if you use another.
- **EIS:** charge-transfer resistance of the enzyme–metal interface, solution resistance and double-layer capacitance. Propose frequency range, amplitude and DC bias. **State your instrument's impedance and frequency limits at both ends:** our model cannot predict the cathode's charge-transfer resistance even to within orders of magnitude, so the measured cathode spectrum is the decisive input, and the instrument must resolve a very small interfacial arc as well as a large one.

**B. Open circuit and load point — anode/cathode coupon pairs**

- **Open-circuit voltage** of the pair, plus each electrode's open-circuit potential against the reference. Report the stabilisation criterion you applied and the drift at the moment of reading.
- **Cell voltage while drawing a constant current of about 25 µA** from the same pair, read soon after the open-circuit value. Together these two readings decide whether our power-management circuit can cold-start from the cell: the open-circuit voltage decides whether it can start at all, and the internal resistance derived from the two readings decides whether it starts under load.
- Propose the cell configuration in which the anode sees the sap and the cathode the air-exposed medium (one compartment or two).
- *Option:* a full **polarisation and power curve** of the pair, and the same curve at **double the electrode area** — for example two coupons connected in parallel per electrode; tell us how you would do it.

**C. 30-day stability — anode and cathode coupons, including the matched cathode control**

- **Potentiostatic hold for 30 days.** Propose the hold potential from the day-0 CV and agree it with us before the hold starts.
- **Channel order, if channels are fewer than coupons:** the anodes of every alloy first, then the matched cathode pair on Ti-6Al-4V, then the rest.
- **Repeat the CV at intervals you propose** (price per check-point), so that retention of the maximum catalytic current can be tracked.
- **Substrate depletion and acidification.** During the hold the anode consumes glucose and its oxidation product acidifies the medium, so a small fixed volume can fail a stability test through depletion alone. Either **replace the medium on a schedule** or use a volume large enough that glucose and pH stay near their set-points for the whole 30 days — propose which, with the volume per coupon and the schedule, and **log glucose concentration and pH at every replacement or sampling**. Keep every removed portion for ICP-MS (F), so that the release figure stays cumulative.
- Quote per potentiostat **channel-day** and state how many channels you can dedicate at once.

**D. Chloride tolerance — separate, fresh Ti-6Al-4V cathode coupons, not those of C**

- **Stepwise NaCl additions** to the cathode medium **up to 0.25 M**; propose the steps and report the catalytic current at each step relative to the chloride-free start.
- State your reference electrode and how you keep its filling solution from adding chloride to the cell — chloride is itself one of the variables under test.

**E. Freeze–thaw recovery — separate, fresh Ti-6Al-4V anode coupons carrying the membrane, not those of C**

- One cycle: **freeze at −10 °C, thaw to +25 °C**, then measure the current against its pre-freeze value. This is a **recovery test at +25 °C**, not a measurement at the cold temperature. Propose the hold time at each temperature and whether the coupon is frozen in the medium.

**F. Ion release by ICP-MS**

- Analyse a **medium blank** before exposure and the **exposure medium at the end of the 30-day test**; quote intermediate sampling as an option.
- *Option:* a **cell blank** — the same cell with the same medium but no coupon, held for the same 30 days — so that what the O-ring, the reference electrode and the vessel release can be separated from what the coupon releases (glassware, for one, can release aluminium).
- The **uncoated-coupon series at pH 4.5** (Specimens) runs through the same analysis — substrate elements only, since it carries no electrode layers.
- **Elements:** Ti, V, Al, Nb, Zr, Ta from the substrate (as relevant per alloy) · Os from the anode mediator · Cu, Co, Ce from the cathode nanozyme.
- Report concentrations (µg/L) together with the solution volume and the exposed area, so that release can be expressed per cm² of exposed face.
- **Sensitivity:** the levels our comparison has to resolve are **V 0.02 µg/cm², Al 0.05 µg/cm² and Ti 0.1 µg/cm²** of exposed face, as **cumulative release over the 30-day exposure**. Please state your limit of quantification per element **in this matrix** and the lowest cumulative per-cm² release it corresponds to at your proposed volume — lower is better: below those levels the data still rank the alloys.
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

We also plan a longer accelerated-ageing exposure of coupons in the same medium, at a constant 40 °C, with mechanical loading, and ion release and EIS at intervals. If that is within your scope, say so and we will send a separate request.

### Commercial & logistics

- Coupons reach you from the manufacturer or from Ukraine; tell us your receiving requirements, including cold-chain handling for functionalised coupons.
- Tell us what documentation you need to receive and handle the materials — osmium-complex polymer, recombinant enzymes, nanomaterials: safety data sheets, end-use statement, entity details, import permits.
- The Incoterms you quote on for returning tested coupons, and any export-control considerations you are aware of.

### Attachments

Nothing is required from us for an initial quotation. On request we supply the written immobilisation protocol, the coupon drawing, and the medium recipe with its preparation notes.

---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — ТЗ 1 із 2: електрохімічна лабораторія (установа НАН)

> **Репо-нота (у лист НЕ йде).** Український маршрут того самого змісту, що EN-блок ↑, розрізаний по вимірюванню F (⚖️ founder 2026-09-17, §0 п.0): **ТЗ 1** — усе, крім ICP-MS; **ТЗ 2** ↓ — ICP-MS на пробах, які готує ТЗ 1. Форма — проєкт ТЗ під договір НДР ⊥ послугу, як [`anchor_hip_rfq`](anchor_hip_rfq.md). **Дзеркало, не новий зміст:** кожне число — з EN-блоку, їхні доми — §1–§4. **Що додано, бо цього вимагає розріз, а не нова вимога:** п. 22–25 «Відбір, зберігання й передача проб» — транспортна холоста проба (та сама партія середовища, той самий посуд, той самий маршрут), посуд і консервація за вимогою аналітичної лабораторії, журнал і акт передачі (ланцюг зберігання), той самий знаменник (площа й обʼєм із журналу) в обох ТЗ · пп. 32–33 форма співпраці й приймання-повернення (з ГІП-ТЗ). **Що прибрано:** F (ICP-MS) і сумарні рівні чутливості — вони в ТЗ 2; решта «немає свідомо» — як у нотатці EN-блоку ↑. ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо електрохімічних випробувань ферментних електродів на титанових купонах у синтетичному ксилемному соку — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева, для моніторингу лісу. Перш ніж переходити до повнорозмірних деталей, ми перевіряємо хімію електродів на плоских металевих купонах і шукаємо лабораторію, яка виконає їхню електрохімічну характеризацію. Купони й матеріали електродів надходять від інших постачальників; від вас ми купуємо вимірювання — простежувані первинні дані, отримані в середовищі, що відтворює ксилемний сік дерева, а не в типовому буфері, бо і поведінка ферментів, і вихід іонів металу залежать від хімії соку.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону. Один параметр ми ще фіксуємо — кількість купонів-повторів на кожен варіант порівняння, — тож просимо давати ціни за купон і за канал, а обсяг замовлення визначимо за вашою пропозицією. Нижче — проєкт технічного завдання для узгодження; режими, яких ми не фіксуємо, подано як питання — просимо відповідати своїми даними, а не підганяти їх під наш текст.

Ми свідомо не надсилаємо ні наших порогів «придатний / непридатний», ні прогнозів наших моделей: аналіз має бути сліпим щодо очікуваного результату. Єдині числа в завданні — ті, під які ви маєте побудувати метод.

Аналіз вмісту металів у середовищі (ICP-MS) ми замовляємо в окремої аналітичної лабораторії; від вас для нього потрібні лише проби — відібрані, збережені й передані так, як описано в пп. 22–25 (тому в переліку випробувань нижче немає літери F).

**Проєкт технічного завдання**

*1. Зразки (що ми постачаємо)*

1. **Геометрія:** плоский диск **Ø16 × 1 мм** із невеликим вушком або отвором на краю під затискач потенціостата. Одна грань — **активна (проєкційна площа 2,01 см²)**; вушко лежить поза нею.
2. **Експонувати лише активну грань** — наприклад, у плоскій комірці, де площу задає вікно ущільнювального кільця. І густину струму, і вихід іонів ми нормуємо на одиницю експонованої площі, тож її треба знати точно, і вона не повинна включати зворотну грань чи край. Якщо пропонуєте повне занурення — скажіть про це й назвіть повну експоновану площу.
3. **Сплави підкладок** (по кілька купонів-повторів кожного — ціна за купон): Ti-6Al-4V (контроль) · Ti-6Al-7Nb · технічно чистий титан Grade 4 · Ti-13Nb-13Zr (β-сплав) · тантал · Ti-15Zr — і один титановий купон із тонким **золотим** покриттям активної грані як еталон найкращого перенесення електронів: він несе шари катода, щоб катод на золоті можна було порівняти з катодом на титані. Купони можуть надійти кількома партіями — скажіть, чи можна виконувати пізнішу партію окремою кампанією за тими самими цінами.
4. **Які електроди на якому сплаві:** аноди — на кожному сплаві. Катоди — на Ti-6Al-4V (парний катод випробування C і тест на хлорид D), на Ti-6Al-7Nb, Ti-13Nb-13Zr і Ti-15Zr (характеризація дня 0 — A — і одна пара анод/катод того самого сплаву — B), на танталі й на золоченому купоні (лише день 0, як два кінці порівняння «оксид ↔ пряме перенесення електронів»); технічно чистий титан Grade 4 катода не несе. Жодне порівняння не виконується на одному повторі; кількість повторів зафіксуємо після ваших цін.
5. **Непокриті купони для серії виходу іонів:** додатково — **по три купони на сплав** із тією самою обробкою поверхні, але **без шарів електродів**, занурені на ті самі 30 діб у середовище з **pH 4,5**. Каналів потенціостата вони не потребують — від вас потрібні лише експозиція й проби за пп. 22–25.
6. **Електроди на купонах:**
   - *Анод:* FAD-залежна глюкозодегідрогеназа, підʼєднана осмієвим редокс-полімером на функціоналізованих вуглецевих нанотрубках, під гідрогелем із хітозану, зшитого геніпіном, і нанокристалів целюлози та мембраною Nafion із прищепленим цвітеріоном. Опублікований формальний потенціал медіатора — **+309 мВ відносно НВЕ**; наводимо його, щоб ви могли задати вікно потенціалів.
   - *Катод:* лаказа в поєднанні з нанозимом — цеолітно-імідазолатним каркасом (ZIF) Co/Cu/Ce — на вуглецевих нанотрубках; працює через пряме перенесення електронів.
   - *Парний контроль катода:* той самий катод **без нанозиму**, паралельно за ідентичним протоколом стабільності. Різниця спаду струму між ними ізолює стабілізувальну дію нанозиму на фермент.
7. **Хто наносить шари електродів — скажіть, який варіант можете запропонувати** (за замовчуванням — (А): одна сторона наносить шари на всі купони, щоб маршрут був однаковим для всіх сплавів; (Б) просимо оцінити як альтернативу):
   - **(А)** ви наносите шари на наші купони з наданих нами матеріалів за нашим письмовим протоколом іммобілізації — налагодження протоколу окремим рядком ціни, далі ціна за купон. **Один крок цього протоколу свідомо ваш: спосіб закріплення шару вуглецевих нанотрубок на протравленому титані.** Ми задаємо РЕЗУЛЬТАТ — шар мусить пережити 30-денне випробування стабільності без втрати струму, — а не рецепт, бо маршрут не відтворюється між виконавцями. Скажіть, що ви застосували б і чому. Два обмеження передаємо заздалегідь: карбодіімідне зшивання потребує первинного аміну, якого голий оксид титану не має, а амінсилановий підшар, як відомо, гідролізується у воді при 40 °C — це верхня межа нашого робочого діапазону; або
   - **(Б)** ми постачаємо вже функціоналізовані купони, а ви лише вимірюєте — тоді скажіть, як ви приймаєте й зберігаєте ферментні електроди і як швидко після отримання починається перше вимірювання, бо базова лінія дня 0 є відліком для всіх подальших результатів.
8. **Поводження:** функціоналізовані купони **не стерилізувати** — ні етиленоксидом, ні автоклавом, ні сухим жаром: усе це денатурує ферменти. **Не додавати консервантів чи антимікробних речовин** у жодне середовище без узгодження з нами — кожну добавку треба перевірити на сумісність із ферментами на електроді. Зокрема, **не використовувати азид натрію** — він пригнічує лаказу вже в мікромолярних концентраціях.

*2. Середовище*

9. **Синтетичний ксилемний сік**, цільовий вид — сосна звичайна (*Pinus sylvestris*). Робочий склад:

| Компонент | Концентрація |
|---|---|
| Яблучна кислота | 2,2 мМ |
| KNO₃ | 3,2 мМ |
| CaCl₂ | 1,0 мМ |
| MgSO₄ | 0,45 мМ |
| KOH | до уставки pH — записувати кількість на кожну партію |

10. **pH:** **5,75** для випробувань електродів; **4,5** для серії непокритих купонів. Доданої буферної системи немає — єдиний буфер яблучна кислота, а pH задає KOH, — тож при **5,75** середовище **слабко буферне**: невелика кількість кислоти помітно зсуває pH, а працюючий анод кислоту виробляє. Опишіть, як ви задаєте, утримуєте й реєструєте pH протягом 30 діб, і сплануйте заміну середовища у випробуванні C з урахуванням цього. Ціна приготування середовища — за партію й за значення pH.
11. **Глюкоза** — субстрат анода: **10 мМ** у середовищі для 30-денної витримки й для всіх інших випробувань з однією концентрацією. **У день 0** характеризувати **кожен анодний купон при 0, 1, 2, 5, 10, 20 і 50 мМ глюкози** (A) — з цієї серії ми виводимо уявну константу Міхаеліса для кожного купона; ціна — за точку концентрації.
12. **Середовище катода:** pH 4,5, відкрите до повітря. Скажіть, як ви підтримуєте насичення повітрям і чи реєструєте розчинений кисень.
13. **Мікробний ріст:** середовище з глюкозою, що стоїть 30 діб, його підтримуватиме, а ріст споживатиме субстрат і спотворить результат стабільності — скажіть, як ви йому запобігаєте (добавки — лише за узгодженням, п. 8).
14. **Контроль якості кожної партії середовища:** pH каліброваним приладом, електропровідність, перевірка основних іонів і відсутність **осаду** — одразу після приготування й ще раз наприкінці 30-денної витримки. Назвіть методи й додайте записи до звіту.

*3. Вимірювання*

15. **Загальні умови.** Електрохімічні вимірювання — при контрольованій температурі витримки стабільності, **в межах 20–25 °C**, із реєстрацією протягом усього часу. Потенціали — відносно використаного електрода порівняння, з наведеним перерахунком на СВЕ. Густина струму — на **проєкційну геометричну площу експонованого вікна**, а не на електрохімічно оцінену площу (таку оцінку можна навести додатково): протравлена поверхня надто шорстка, щоб її справжню площу можна було надійно виміряти.
16. **A. Характеризація електродів — кожен анодний і катодний купон, день 0.**
   - **Циклічна вольтамперометрія.** Анод: без глюкози (для константи швидкості гетерогенного перенесення електронів *k*ₛ і уявного числа електронів *n*) і з глюкозою (для максимальної каталітичної густини струму, мкА/см²). Катод: каталітична густина струму в середовищі, відкритому до повітря, і *k*ₛ, виміряна без кисню, якщо сигнал без обороту ферменту вдається розділити; якщо не вдається — так і скажіть, не підганяючи його. Назвіть метод аналізу — ми очікуємо серію швидкостей розгортки з аналізом за Лавіроном, але скажіть, якщо застосовуєте інший.
   - **Імпедансна спектроскопія (EIS):** опір перенесення заряду межі фермент–метал, опір розчину й ємність подвійного шару. Запропонуйте діапазон частот, амплітуду й постійне зміщення. **Назвіть межі імпедансу й частоти вашого приладу з обох боків:** наша модель не може передбачити опір перенесення заряду катода навіть із точністю до порядків, тож виміряний спектр катода є вирішальним входом, і прилад мусить розділяти як дуже малу міжфазну дугу, так і велику.
17. **B. Розімкнене коло й робоча точка — пари анод/катод.**
   - **Напруга розімкненого кола** пари, а також потенціал розімкненого кола кожного електрода відносно електрода порівняння. Назвіть критерій стабілізації й дрейф у момент відліку.
   - **Напруга комірки під постійним струмом близько 25 мкА** з тієї самої пари — невдовзі після відліку розімкненого кола. Разом ці два відліки вирішують, чи зможе наша схема керування живленням холодно стартувати від елемента: напруга розімкненого кола — чи можливий старт узагалі, а внутрішній опір, виведений із двох відліків, — чи старт відбудеться під навантаженням.
   - Запропонуйте конфігурацію комірки, у якій анод бачить сік, а катод — середовище, відкрите до повітря (одна камера чи дві).
   - *Опція:* повна **поляризаційна крива й крива потужності** пари, і та сама крива при **подвоєній площі електродів** — наприклад, два купони паралельно на кожен електрод; скажіть, як ви це зробили б.
18. **C. 30-денна стабільність — анодні й катодні купони, включно з парним контролем катода.**
   - **Потенціостатична витримка 30 діб.** Потенціал витримки запропонуйте за вольтамперограмою дня 0 й узгодьте з нами до початку.
   - **Черговість каналів, якщо каналів менше, ніж купонів:** спершу аноди всіх сплавів, далі парний катод на Ti-6Al-4V, потім решта.
   - **Повторювати вольтамперометрію з інтервалами, які ви запропонуєте** (ціна за контрольну точку), щоб відстежити збереження максимального каталітичного струму.
   - **Вичерпання субстрату й підкиснення.** Під час витримки анод споживає глюкозу, а продукт її окиснення підкислює середовище, тож малий сталий обʼєм може провалити випробування стабільності самим лише вичерпанням. Або **замінюйте середовище за графіком**, або візьміть обʼєм, достатній, щоб глюкоза й pH лишалися біля уставок усі 30 діб, — запропонуйте варіант з обʼємом на купон і графіком (обʼєм не має перевищувати найбільшого, який назве аналітична лабораторія, — п. 23) і **реєструйте концентрацію глюкози й pH при кожній заміні чи відборі**. **Кожну відібрану порцію зберігайте** як пробу для аналізу іонів (пп. 22–25): вихід має лишатися сумарним.
   - Ціна — за **канало-добу** потенціостата; скажіть, скільки каналів можете виділити одночасно.
19. **D. Стійкість до хлориду — окремі, нові катодні купони Ti-6Al-4V, не ті, що в C.**
   - **Ступінчасті додавання NaCl** у середовище катода **до 0,25 М**; кроки запропонуйте й повідомте каталітичний струм на кожному кроці відносно початку без хлориду.
   - Назвіть ваш електрод порівняння й те, як ви не допускаєте, щоб його заповнювальний розчин додавав хлорид у комірку, — хлорид тут сам є змінною випробування.
20. **E. Відновлення після заморожування — окремі, нові анодні купони Ti-6Al-4V із мембраною, не ті, що в C.**
   - Один цикл: **заморожування при −10 °C, відтавання до +25 °C**, далі вимірювання струму відносно значення до заморожування. Це **випробування відновлення при +25 °C**, а не вимірювання при низькій температурі. Запропонуйте час витримки на кожній температурі й скажіть, чи заморожується купон у середовищі.
21. **G. Опційно — неелектрохімічні випробування з тієї самої програми** (у вас або через партнера; якщо ні — скажіть, ми знайдемо їх окремо):
   - циклічне механічне випробування гідрогелевої матриці: **±5 % деформації при 0,1 Гц, 10 000 циклів**;
   - тест на обростання (адсорбцію білка) мембрани проти **суспензії абієтинової кислоти, 10 мг/мл у синтетичному соку, 7 діб**.

*4. Відбір, зберігання й передача проб для аналізу іонів*

22. **Які проби:** (а) холоста проба середовища кожної партії до експозиції; (б) кожна відібрана при заміні порція й кінцеве середовище наприкінці 30 діб — для кожного купона випробування C (опція — проміжні відбори за графіком, який ви запропонуєте); (в) середовище серії непокритих купонів (п. 5) наприкінці 30 діб; (г) **транспортна холоста проба** — п. 24; (д) *опція:* **холоста комірка** — та сама комірка з тим самим середовищем без купона на ті самі 30 діб, щоб відокремити внесок ущільнювального кільця, електрода порівняння й посудини від внеску купона (скло, наприклад, може віддавати алюміній); оцініть окремо.
23. **Посуд, консервація, строки.** Вимоги до посуду, консервації проб, допустимих строків зберігання й **найбільшого обʼєму розчину на купон**, сумісного з її чутливістю, визначає аналітична лабораторія, і ми передамо їх вам **до початку експозиції**. Скажіть, який посуд ви можете забезпечити і як зберігаєте проби до передачі (температура, строк).
24. **Транспортна холоста проба:** порція середовища **з тієї самої партії**, у **тому самому посуді**, що проходить **той самий маршрут і той самий час** зберігання й передачі, що й проби, але без контакту з купоном. Без неї аналіз не відрізнить внесок дороги від внеску купона.
25. **Журнал і передача.** Для кожної проби — ідентифікатор, купон, дата й час відбору, **обʼєм розчину в посудині до відбору й обʼєм відібраної порції**, **площа експонованої поверхні** (виміряна площа вікна; 2,01 см² — лише коли експонується вся активна грань), pH і концентрація глюкози на момент відбору, умови зберігання. Вихід іонів на см² рахується саме з цих обʼєму й площі, тож вони мають стояти в журналі для кожної проби. Передача аналітичній лабораторії — за актом приймання-передачі з переліком ідентифікаторів; скажіть, чи можете організувати курʼєра, чи проби забирає наш представник.

*5. Дані, які потрібно повернути*

26. Самих підігнаних параметрів недостатньо: ми порівнюємо ваші вимірювання з власними моделями, можемо перепідігнати первинні дані іншою еквівалентною схемою й маємо намір публікувати результати.
   - **Файли приладу у власному форматі й відкритий експорт** (CSV або ASCII) кожної вольтамперограми, спектра EIS, потенціостатичної витримки, запису розімкненого кола й поляризаційної кривої.
   - **Підгонка EIS:** еквівалентна схема, підігнані значення з похибками й залишки — поряд із первинними спектрами, ніколи замість них.
   - **Метадані до кожного запису:** ідентифікатор купона, тип електрода, експонована площа, електрод порівняння, журнали температури й pH, прилад і версія програмного забезпечення.
   - **Журнал відхилень**, фото кожного купона до й після випробувань і **повернення всіх випробуваних купонів**, кожен в окремому пакуванні з захищеною активною гранню, — їх можуть досліджувати далі.

*6. Що просимо надати*

27. **Спроможність:** моделі потенціостатів/гальваностатів, роздільна здатність за струмом на рівні мкА, частотний та імпедансний діапазони EIS, кількість каналів для 30-денної витримки — і чи це **незалежні канали**, а не мультиплексор, що перемикає електроди (для безперервної витримки потрібні незалежні), та чи дозволяє ваш режим доступу до приладу **720 годин безперервної роботи на канал**, тип комірки для дисків Ø16 мм, електроди порівняння, придатні для кислого середовища з органічною кислотою, кліматична камера до −10 °C.
28. **Порівнянні роботи:** ферментні чи інші біоелектроди у водних середовищах (знеособлені приклади годяться).
29. **Акредитація й система якості** — номер свідоцтва, орган, сфера й строк дії: ISO/IEC 17025 (скажіть, чи охоплює її сфера наведені методи), ISO 9001 чи GLP — що маєте.
30. **Постатейні ціни:** за купон за випробування (A, B, D, E) · за канало-добу (C) · за контрольну точку вольтамперометрії · приготування й контроль середовища за партію · відбір, зберігання й передача проб (пп. 22–25) · нанесення шарів електродів, якщо пропонуєте варіант (А), — налагодження окремим рядком, далі за купон · аналіз даних і звіт · кожна опція окремо.
31. **Строки:** черга до старту, фіксовані 30 діб витримки, аналіз і звіт — і чи можливий **короткий пілот** на одному-двох купонах (характеризація дня 0, розімкнене коло й робоча точка, без 30-денної витримки) перед повною програмою, і за якою ціною.
32. **Форма співпраці:** на якій підставі ви виконуєте роботи для сторонніх організацій — договір на науково-дослідну роботу, договір про надання послуг чи інше; які документи потрібні від нас; форма оплати, строк чинності пропозиції й контактна особа з технічних питань.
33. **Приймання й повернення:** як приймаєте купони й матеріали (курʼєр, пошта, особисто), вимоги до пакування, маркування й холодового ланцюга для функціоналізованих купонів; чи оформлюєте акт приймання-передачі з переліком ідентифікаторів — при прийманні й при поверненні; які документи потрібні для роботи з матеріалами (полімер осмієвого комплексу, рекомбінантні ферменти, наноматеріали) — паспорти безпеки тощо.

**Конфіденційність і публікація.** Технічна специфікація відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов (ціни, строки, дані контролю якості). Результати вимірювань ми маємо намір опублікувати в рецензованому журналі — повідомте, будь ласка, чи маєте умови щодо публікації даних, отриманих для нас, наприклад згадку установи чи опис методу.

**Можливе продовження (не входить у цю пропозицію).** Ми плануємо також довшу прискорену експозицію купонів у тому самому середовищі — за сталої 40 °C, з механічним навантаженням, виходом іонів і EIS з інтервалами. Якщо це у вашій сфері — скажіть, і ми надішлемо окремий запит.

**Додатки.** Для первинної пропозиції від нас нічого не потрібно. На запит надамо письмовий протокол іммобілізації, креслення купона й рецептуру середовища з примітками щодо приготування.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — ТЗ 2 із 2: лабораторія ICP-MS

> **Репо-нота (у лист НЕ йде).** Вимірювання F EN-блоку ↑, винесене окремим ТЗ (§0 п.0). **Надсилати НЕ ПІЗНІШЕ за ТЗ 1:** вимоги до посуду, консервації й строків зберігання мусять дійти до лабораторії ТЗ 1 ДО початку експозиції (ТЗ 1 п. 23), інакше проби відберуть у посуд, який аналітик потім забракує. Рівні чутливості — єдиний виняток зі сліпого аналізу, як в EN (метод мусить їх розділяти). Площа грані й обʼєм — зі спільного журналу відбору, тобто той самий знаменник, що в ТЗ 1. ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо визначення металів методом ICP-MS у пробах синтетичного ксилемного соку після 30-денної експозиції титанових купонів — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо ферментний біопаливний елемент, інтегрований у стовбур живого дерева, для моніторингу лісу, і перевіряємо на плоских купонах із кількох титанових сплавів, скільки металу виходить у середовище, що відтворює ксилемний сік. Експозицію й відбір проб виконує електрохімічна лабораторія; від вас ми купуємо аналіз цих проб методом мас-спектрометрії з індуктивно звʼязаною плазмою (ICP-MS).

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону. Кількість купонів-повторів ми ще фіксуємо, тож просимо ціну за пробу.

**Проєкт технічного завдання**

*1. Проби*

1. **Що надійде:** (а) холоста проба середовища кожної партії до експозиції; (б) проби середовища після 30-денної експозиції купонів із ферментними електродами — разом із порціями, відібраними при заміні середовища, бо вихід рахується сумарно; (в) проби середовища після 30-денної експозиції купонів без покриття при pH 4,5; (г) **транспортна холоста проба** — середовище з тієї самої партії, у тому самому посуді, що пройшло той самий маршрут і той самий час зберігання й передачі, але без контакту з купоном; (д) *за опцією* — холоста комірка: середовище, що 30 діб простояло в тій самій комірці без купона.
2. **Матриця:** синтетичний ксилемний сік — яблучна кислота 2,2 мМ, KNO₃ 3,2 мМ, CaCl₂ 1,0 мМ, MgSO₄ 0,45 мМ, KOH до уставки pH (5,75 або 4,5); у пробах із електродами — ще глюкоза 10 мМ і продукти її окиснення, а також можливі органічні компоненти шарів електродів.
3. **Посуд, консервація, строки — просимо визначити ВИ, і до початку експозиції:** матеріал і підготовку посуду, консервацію проби (з огляду на осмій — п. 8), допустимі строк і температуру зберігання, мінімальний обʼєм проби на повну панель елементів — і **найбільший обʼєм розчину експозиції на один купон**, за якого ваша межа кількісного визначення ще розділяє рівні п. 7. Ці вимоги ми передамо лабораторії, що відбирає проби, і вона добиратиме обʼєм експозиції під них.
4. **Приймання:** за актом приймання-передачі з переліком ідентифікаторів; до кожної проби — журнал відбору (купон, дата й час, обʼєм розчину в посудині до відбору, обʼєм відібраної порції, площа експонованої поверхні — виміряна площа вікна (2,01 см² — лише коли експонується вся активна грань), pH і глюкоза на момент відбору, умови зберігання).

*2. Аналіз*

5. **Елементи:** Ti, V, Al, Nb, Zr, Ta — з підкладки (залежно від сплаву) · Os — з медіатора анода · Cu, Co, Ce — з нанозиму катода. Для проб купонів без покриття — лише елементи підкладки.
6. **Результати:** концентрації (мкг/л) для кожної проби. Перерахунок на см² експонованої поверхні ми зробимо з обʼєму й площі, записаних у журналі відбору для кожної проби.
7. **Чутливість:** рівні, які має розділяти наше порівняння, — **V 0,02 мкг/см², Al 0,05 мкг/см² і Ti 0,1 мкг/см²** експонованої поверхні як **сумарний вихід за 30 діб експозиції**. Назвіть межу кількісного визначення для кожного елемента **в цій матриці** — ми перерахуємо її на см² за обʼємом розчину експозиції й площею з журналу відбору. Нижче за ці рівні дані однаково ранжують сплави, тож нижча межа — краще.
8. **Два методичні моменти — просимо відповісти прямо:** хлорид у середовищі утворює поліатомну інтерференцію на ізотопі ванадію, який вимірює ICP-MS, — скажіть, як ваш метод її усуває (наприклад, колізійна/реакційна комірка); осмій може втрачатися як летка сполука (оксид) під час окиснювальної пробопідготовки — скажіть, як ви запобігаєте цій втраті.
9. **Контроль якості:** холості проби, градуювання, введення-знайдення (spike recovery) у матриці соку, коефіцієнти розведення.

*3. Дані, які потрібно повернути*

10. Результати по кожній пробі з межами виявлення й кількісного визначення, холості проби, градуювання, введення-знайдення, коефіцієнти розведення й обʼєми; відкритий експорт (CSV або ASCII); журнал відхилень.

*4. Що просимо надати*

11. **Спроможність:** модель мас-спектрометра й наявність колізійної/реакційної комірки; чи приймаєте таку нестандартну матрицю (синтетичний сік з органічною кислотою); якщо елементи панелі визначаються в РІЗНИХ підрозділах чи різними приладами — назвіть, які де і з якими межами; режим доступу для сторонніх замовників; порівнянні роботи з органічними матрицями.
12. **Акредитація й система якості** — номер свідоцтва, орган, сфера й строк дії: ISO/IEC 17025 (чи охоплює її сфера ці елементи й таку матрицю), ISO 9001 чи GLP — що маєте.
13. **Ціни:** за пробу для панелі елементів вище · пробопідготовка · кожна опція окремо.
14. **Строки:** від приймання проб до звіту.
15. **Форма співпраці:** договір на науково-дослідну роботу, договір про надання послуг чи інше; які документи потрібні від нас; форма оплати, строк чинності пропозиції й контактна особа з технічних питань.

**Конфіденційність і публікація.** Технічна специфікація відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов. Результати аналізу ми маємо намір опублікувати в рецензованому журналі — повідомте, будь ласка, чи маєте умови щодо публікації даних, отриманих для нас, наприклад згадку установи чи опис методу.

`[підпис і контакти відправника — заповнити перед відправкою]`

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
