# Soldier — іоністор (EDLC) Eaton KR-5R5H474-R: котирування і три технічні питання до FAE

> **Що це:** RFQ-аркуш на єдиний вцілілий SKU іоністора вузла Soldier — **Eaton `KR-5R5H474-R` (0.47 F / 5.5 V)**. Дві частини одним листом: **(A)** котирування малої інженерної кількості, наявність, лідтайм, маршрут в Україну; **(B)** три питання до FAE, на які чинна таблиця KR не відповідає: множник строку при 4.82 В замість 5.5 В · струм витоку при 4.8 В · поведінка нижче −25 °C. Вибір SKU лист не ставить під сумнів — його закрито виключенням ([`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 3). **Лист питає й висновків не повідомляє:** наших оцінок строку служби й наших вимог до витоку в ньому немає (§3).
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-25, не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Маршрут (Eaton напряму ⊥ дистрибʼютор) обирає founder (§0 п. 1). Числа дзеркалять доми, і дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). **Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37** (ноги: котирування · FAE-питання про Voltage Acceleration Factor · самопрозряд ⊕ підлога −25 °C). Споживачі відповіді — ARCH.8 (третій вхід розвилки, ⛔ «не відвантажувати CCM» над FW.2) · HW.12 (ціна К2 клампа) · HW.7 (підстава ратифікованого Derate).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Капсула електроніка» · hard-constraint дім §4.D — звідти всі три FAE-питання).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)): специфікація відкрита, CDA — лише на комерційні умови.

---

## 0. Як користуватись + cover-note

1. **Адресат, два маршрути, мова.** **(А) Eaton напряму:** FAE з суперконденсаторів через регіональний відділ продажів або контактну форму електронного підрозділу Eaton. Адресу не звірено, обирає founder. **(Б) Дистрибʼютор DigiKey або Mouser:** на Part A він відповідає сам, а Part B пересилає FAE. Про це просить перший рядок листа, тож текст для обох маршрутів однаковий. На DigiKey нога HW.37 уже міряла статус і лідтайм (п. 2). Адресати поза UA, тому **лист англійською**. Українського дистрибʼютора канон не називає (у [`ua_vendor_map`](ua_vendor_map.md) рядка EDLC немає), тож лист не вигадує імʼя, а **питає**, хто обслуговує Україну.
2. **Базовий кейс + дельти, не прайс на все.** Базовий кейс — **`KR-5R5H474-R` у малій інженерній кількості**: MOQ, ціна на MOQ, наявність, лідтайм, доставка в Україну. Кількість свідомо не названо: канон її не несе, тож лист питає MOQ, а не просить ціну на вигадане число. Точка порівняння — вимір ноги HW.37 на DigiKey 2026-09-24: статус Active, стандартний лідтайм виробника **21 тиж**. У листі це подано як «a distributor lists», без назви, бо лист може піти й іншому дистрибʼюторові. Дельта «лише для планування» — орієнтир ціни на 1 000 і 10 000 шт (доми — §1).
3. **Що подано фактом, що питанням, а що свідомо не подано.** Фактом — застосування, діапазон напруги, масштаб енергобюджету й кліматична точка місця, кожне з домом (§1). Питанням — усі три FAE-числа. **Не подано** наших висновків, які анкерили б відповідь: вимоги «< 1–2 µA», оцінок строку, розкиду вендорських правил за напругою (§3). Масштаб витоку лист дає через сон вузла: «1 µA більше за весь сон». Це твердження канону, а не поріг прийняття.
4. **«Design value чи measured on production units» — для КОЖНОГО числа, разом із «guaranteed чи typical» і розкидом.** Для витоку це несуче: число сідає в баланс, що гейтує гроші (ARCH.8 → FW.2), і typical-значення від FAE там не дорівнює гарантії (§4).
5. **Відповідь у репо не комітиться як є.** Ціни, внутрішні дані тестування й переписка — чужі операційні факти. Репо публічне, тож лист **питає дозволу** цитувати числа з атрибуцією (розділ Confidentiality). Без дозволу в канон іде лише наш висновок і стендовий вимір. З дозволом — число з посиланням на документ виробника.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Застосування** | [`02_03 §2`](../../02_03_BQ25570_MPPT_Nano_Power.md) (BQ25570 заряджає іоністор на VSTOR) · [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) (свідома відмова від Li-ion: іоністор — єдиний накопичувач) · капсула на корі під радомом — нога 👤 [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37 | фактом | EBFC і ксилема · `delta_t` як біосенсор ([`02_03 §12.2`](../../02_03_BQ25570_MPPT_Nano_Power.md)) · SCC — не предмет FAE |
| **Деталь** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 3 · [`rfq_registry`](rfq_registry.md) §4.D (0.47 F / 5.5 V, 70 °C-рейтинг, горизонтальний) | фактом | висота 5.2 ⊥ 5.00 мм (§3) · виключені SKU (§3) |
| **Напруга 3.4 → 4.82 В, допуск «at least ±2 %»** | [`02_03 §8`](../../02_03_BQ25570_MPPT_Nano_Power.md) (робоче вікно 3.4 В → `VBAT_OV`) · [`02_03 §4`](../../02_03_BQ25570_MPPT_Nano_Power.md), §4.Б (`VBAT_OV` = 4.822 В, ⚖️ 2026-09-09; ±2 % — паспортний `VBAT_ACCURACY` для 0.1 %-резисторів, на наших 1 % — **нижня** оцінка) | «about 3.4 V» (у нормальній роботі; cold-start від 0 В і гістерезис VBAT_OK не названо) · «4.82 V» · «at least ±2 %» · «held at the upper threshold continuously» — ⛔ не «worst case»: гірший випадок лежить на верхньому краю допуску | смуга 4.726–4.919 В (у листі читалася б гарантією, а канон зве її нижньою оцінкою) · номінали ROV · те, що ROV2 ще не запаяно ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.7) — лист каже «in our design» |
| **Масштаб бюджету: «1 µA > весь сон»** | [`02_03 §9.3`](../../02_03_BQ25570_MPPT_Nano_Power.md) ⚠️ (+1 мкА на 4.5 В = 4.5 мкВт > 4.18 мкВт сну Сценарію C, [`02_03 §9.6`](../../02_03_BQ25570_MPPT_Nano_Power.md)) | фактом, без чисел бюджету; «in our design», бо правда лише для сну Сценарію C (STOP2 RTC-only, затверджено [`02_03 §9.8`](../../02_03_BQ25570_MPPT_Nano_Power.md) п. 2), а не для сьогоднішніх 1.07 µA | P_gen 15 µW · вимога «< 1–2 µA» · H 6.97 год · поріг ≈ +1.34 мкА (усе — §3) |
| **Таблиця KR і її примітка 1** | нога 👤 [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37 (Technical Data 4327, червень 2026, звірено 2026-09-24: нормує ємність, ESR і ресурс, витоку не нормує; примітка 1 — «under end application conditions»; підлога −25 °C) · [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) (1000 год @ 70 °C @ 5.5 В) | цитатою документа виробника | EOL-критерій ΔC 30 % числом (лист каже «the same end-of-life criteria») |
| **Part A: MOQ · ціна · наявність · лідтайм · Active** | нога 👤 [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37 (котирування; DigiKey 2026-09-24: Active, 21 тиж) | 21 тиж — цитатою «a distributor lists»; актуальність і наявність — питанням | назва DigiKey · дата виміру |
| **Part A: Україна** | та сама нога («доступність в українського дистрибʼютора») | питанням: відвантаження в Україну і хто авторизований дистрибʼютор | імʼя UA-дистрибʼютора (канон не називає) |
| **Part A: 1 000 / 10 000 шт** | [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) (ціновий рівень 1K) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) (ціни на партію 10 000+) | «for planning only» | наша BOM-ціна ~$1.10 |
| **Part B п. 1 — множник за напругою** | [`rfq_registry`](rfq_registry.md) §4.D (🔴 «RFQ МУСИТЬ включати пряме питання до FAE») · нога 🔗 HW.37 · [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) (температурне правило 2× на −10 °C; вендорські правила за напругою розходяться вдвічі) | питанням: множник 4.82 ⊥ 5.5 В · правило й діапазон його чинності · на комірку чи на деталь · чи множиться з температурним · гарантія чи guideline | роки строку (2.6 / 7.3, бракети) · «0.2 ⊥ 0.4 В» · «≤ 4.92 В» (§3) |
| **Part B п. 2 — витік при 4.8 В** | [`rfq_registry`](rfq_registry.md) §4.D п. (1) · нога 👤 HW.37 (4.8 В, ≥ 72 год, 25 °C і холодніше) | питанням + метод виміру + прохання розрізнити «self-discharge ≠ float current» | KEMET ≤ ≈ 4.4 µA · вимога «< 1–2 µA» (§3) |
| **Part B п. 3 — нижче −25 °C** | [`rfq_registry`](rfq_registry.md) §4.D п. (2) · нога HW.37 ⊕ (ємність · ESR · чи оборотно) · `tools/in_silico/cache/kinetics/gusak_degradation.json` §`arrhenius_field_temperature.freeze_thaw` (скрипт `51`: 30 зим ERA5, найхолодніша середньодобова −24.2 °C) | «about −24 °C» · «nights likely colder» (висновок, не вимір — так і подано) · «not measured inside the capsule» | дата 2006-01-21 · «12 днів нижче −20 °C» · назва міста |
| **Документи · Confidentiality · дозвіл цитувати** | [`rfq_registry`](rfq_registry.md) §3 (CDA не передумова запиту, розділ Confidentiality у кожному EN-листі) · [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) (репо публічне) | питанням: які числа можна цитувати з атрибуцією | — |

---

## 2. Питання → нога трекера, яку воно закриває

| Питання листа | Нога [`00_07`](../../00_07_Action_Plan_Tracker.md) | Куди сідає відповідь і що вона рухає |
|---|---|---|
| **Part A** (MOQ · ціна · наявність · лідтайм · Україна) | HW.37 👤 «закупівля вцілілого SKU — це вже не вибір, а котирування» | Закриває ногу, якщо є маршрут в Україну + ціна + лідтайм. 21 тиж DigiKey — точка порівняння. Дельта 1 000 / 10 000 — звірка BOM-ціни [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 3 і [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) |
| **Part B п. 1** (множник за напругою) | HW.37 🔗 «RFQ на EDLC несе FAE-питання про Voltage Acceleration Factor» | Бракет строку на ратифікованій точці — 23.6–76.5 року @ 10 °C · 8.4–27.1 року @ 25 °C ([`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md); кеш `edlc_endurance_hours.*.ratified_vbat_ov`) — стає точкою. Ширина бракета й є цим відкритим коефіцієнтом. ⚠️ **Рухає й ПІДСТАВУ ратифікованого Derate** (HW.7 / HW.37; [`02_03 §4`](../../02_03_BQ25570_MPPT_Nano_Power.md), §4.Б): 4.822 В обрано на ДВОХ осях — під консервативним «≤ 4.92 В» строку і за clamp-вікном HW.12. Сьогодні «20 років» тримається @ 10 °C в обох кінцях бракета, а @ 25 °C — лише в оптимістичному. Якщо множник Eaton слабший за консервативне правило (степеневий закон [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) слабший за обидва), може впасти й перша з двох підстав (друга від відповіді не залежить), а не лише число |
| **Part B п. 2** (витік при 4.8 В) | HW.37 👤 «самопрозряд вцілілого EDLC — член енергобалансу» (**P0**) | Член балансу [`02_03 §9.3`](../../02_03_BQ25570_MPPT_Nano_Power.md) і обох моделей (`tx_cadence_budget.rb` · `boot_brownout_cycle.rb`) → третій вхід розвилки ARCH.8 (⛔ CCM над FW.2) → ціна К2 клампа HW.12. Нога сама називає дві альтернативи: «вимір або FAE-відповідь» |
| **Part B п. 3** (нижче −25 °C) | HW.37, та сама нога, ⊕ про підлогу −25 °C | Канон підлоги −25 °C ще не несе ніде. Природний дім відповіді — [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) (фізична специфікація), вибір — за тим, хто інтегрує |

---

## 3. Немає свідомо

- **Наші оцінки строку** (2.6 року @ 25 °C / 7.3 @ 10 °C при 5.5 В, бракети 11.5 / 15.1 / 20.7 ⊥ 9.1 / 10.5 / 12.3, поріг «≤ 4.92 В», бракет на ратифікованій точці 23.6–76.5 @ 10 °C · 8.4–27.1 @ 25 °C) і **розкид вендорських правил за напругою** (2× на −0.2 В ⊥ на −0.4 В ⊥ степеневий закон, [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md)). FAE, якому показали наш бракет, підтвердить одну з його меж замість того, щоб дати власне число.
- **«20 років».** [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) дозволяє цитувати це число лише разом із температурою й бракетом, тобто назовні воно понесло б наш бракет (пункт вище). Тож лист питає множник, а не «чи дотягне до N років». Так само вирішено в [`node_parylene_rfq`](node_parylene_rfq.md) §1. Лист каже «many years of outdoor service» і не каже «unattended»: частоту обслуговування капсули канон називає числом без дому ([`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)).
- **Вимога витоку «< 1–2 µA»** ([`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md)). Причин дві. (а) Вона підказала б відповідь «вкладаємось». (б) Канон сам під нею не стоїть: у моделі Сценарію C ([`02_03 §9.3`](../../02_03_BQ25570_MPPT_Nano_Power.md)) уже +1 мкА дає H 6.97 год при m = 0, а від ≈ +1.34 мкА баланс відʼємний. Тобто смуга вимоги ширша, ніж дозволяє власна модель канону. Ця розбіжність вимоги й балансу в самому каноні лишається. Лист її не лікує й не несе назовні.
- **P_gen 15 µW** — робоче число без простежуваного джерела, а L4 дає ≈ 369 µW ([`02_03 §9.1`](../../02_03_BQ25570_MPPT_Nano_Power.md)). Будь-яке число генерації в листі було б здогадом із виглядом специфікації.
- **KEMET `FG0H474ZF` і його межа самопрозряду** (≤ ≈ 4.4 µA за першу добу). Це виключений SKU, число іншого вендора, та ще й інша величина (стеля з перерозподілом заряду, не флоат-витік). У листі воно стало б якорем.
- **Альтернативи SKU**: `FG0H474ZF` · `PHV-5R4H474-R` · фантом `HV0H474AEJ-R` · 85 °C KEMET FU0H (oversize). ⚖️ закриті (HW.37, 2026-09-09 і 2026-09-22), а лист не питає обидві гілки розсудженого присуду (скіл `legal-business` §Доменні правила #4, зворотний бік).
- **Висота 5.2 ⊥ 5.00 мм.** Розбіжність розсуджено в HW.37: дім числа — таблиця виробника (5.2 мм), і питати нема чого.
- **Верхній край огинаючої капсули.** [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) тримає −40…+85 °C, а рейтинг деталі — 70 °C. Жодна нога HW.37 питання вище 70 °C не ставить, тож лист огинаючої не називає: вендор прочитав би +85 °C як нашу вимогу до деталі й відповідав би не на наші три питання. ⚠️ Сама розбіжність 85 ⊥ 70 — кандидат на окрему ногу трекера; цей лист її не відкриває.
- **Чи тримає температурне правило 2× на −10 °C, екстрапольоване від 70 °C до польових температур.** Бракет строку на ньому стоїть, але жодна нога цього не питає. П. 1c листа питає лише, чи множиться вольтажний множник із температурним правилом, а не чи чинне саме правило.
- **Трекер-ID, канон-рефи, ISO-дати, гліфи** — у copy-регіоні їх немає (гейт `copy_region_check`).

---

## 4. Найслабша ланка листа

**Питання P0 — витік (Part B п. 2) — лист, найімовірніше, НЕ закриє, а лише звузить.** Таблиця KR витоку не нормує, а її ж примітка 1 відсилає перевірку «under end application conditions», тобто до нас. Найімовірніша відповідь FAE — typical-значення, «не нормуємо» або число самопрозряду замість флоат-струму. Typical-значення в балансі, що гейтує гроші (ARCH.8 → FW.2), гарантією не стає. Тож ногу, ймовірно, закриє стендовий вимір, який нога HW.37 уже називає альтернативою: флоат-струм при 4.8 В після ≥ 72 год, на 25 °C і холодніше. Лист цей вимір не блокує й не заміняє. Що в листі зменшує шкоду: прохання дати guaranteed ⊥ typical, розкид і метод; прохання назвати самопрозряд самопрозрядом (п. 2d); фраза «“we have no data” is a useful answer».

Дві менші ланки. **(а) Маршрут Б:** техпідтримка дистрибʼютора схильна відповідати з того самого датащита, не пересилаючи FAE. Якщо Part B повернеться як «see datasheet», це сигнал ескалювати маршрутом А, а не відповідь. **(б) «Guaranteed» у п. 1:** вольтажний множник вендори розкривають як емпіричне правило, тож найімовірніше прийде guideline. Він усе одно звужує бракет [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) до одного вендорського правила, але в канон іде з позначкою «guideline», а не «guaranteed».

---

## 5. Dispatch checklist (👤)

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Маршрут:** А (Eaton, FAE з суперконденсаторів) або Б (DigiKey / Mouser). Текст той самий: перший рядок уже просить дистрибʼютора переслати Part B.
- [ ] 👤 **Перед відправкою:** перевірити, що Technical Data 4327 (червень 2026) досі чинна редакція. Лист на неї посилається, і якщо вийшла нова, питання п. 2–3 могли застаріти.
- [ ] 👤 **Після відповіді:** Part A → нога котирування HW.37. П. 1 → [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) + кеш `edlc_endurance_hours` і перевірка підстави Derate (§2). П. 2 → член балансу [`02_03 §9.3`](../../02_03_BQ25570_MPPT_Nano_Power.md) + обидві моделі → ARCH.8 / HW.12. П. 3 → дім за інтегратором (§2). Цін не комітити. Числа виробника — лише з його дозволу й з посиланням на документ (§0 п. 5).

---

## 📤 Dispatch block (EN) — Eaton FAE or distributor email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): 0.47 F / 5.5 V · горизонтальний · Technical Data 4327 (червень 2026) і її примітку 1 · 1000 год @ 70 °C @ 5.5 В · підлогу −25 °C · BQ25570 · вікно 3.4 → 4.82 В, допуск «at least ±2 %» · «1 µA > весь сон вузла» · 21 тиж лідтайму · 1 000 / 10 000 шт · найхолоднішу середньодобову ≈ −24 °C за 30 років. Питає те, чого таблиця KR не дає: множник строку при 4.82 В · флоат-витік при 4.8 В після ≥ 72 год · поведінку нижче −25 °C · для кожного числа — guaranteed ⊥ typical і design ⊥ measured. **Немає свідомо** (повний перелік — §3): наших оцінок строку · розкиду вендорських правил · вимоги «< 1–2 µA» · P_gen · чисел KEMET · виключених SKU · огинаючої капсули −40…+85 °C · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** RFQ and technical questions — Eaton KR-5R5H474-R (0.47 F, 5.5 V): quotation, voltage derating factor at 4.82 V, leakage current at 4.8 V, behaviour below −25 °C

**To a distributor receiving this:** Part A is for you. Part B can only be answered by the manufacturer: please forward it to the Eaton field application engineer responsible for supercapacitors.

Dear colleagues,

**About us and the application.** We are an R&D project in Ukraine building a sensor node for forest monitoring. The node sits in a small sealed capsule mounted on the outside of the trunk of a living tree, under a plastic cover, and is meant for many years of outdoor service. It is powered by an energy harvester with a very small output through a TI BQ25570 boost charger, which charges the capacitor. The node wakes, measures, transmits a short radio packet and goes back to sleep. The capacitor is the node's energy store: there is no battery.

We have selected the **Eaton KR-5R5H474-R** (0.47 F, 5.5 V, horizontal). In normal operation the capacitor voltage in our design moves between about 3.4 V and the charger's upper threshold of **4.82 V**. That threshold has a tolerance of at least ±2 %. For life estimates we assume the capacitor is held at the upper threshold continuously. Our energy budget is very small: in our design, a leakage current of one microampere would already be larger than the node's entire sleep consumption.

This is a request for a quotation and for technical information, not yet an order. Answering commits neither side to anything, and inline answers in this email are fine.

**Part A — Quotation and availability**

- a. **Engineering quantity.** Your minimum order quantity for the KR-5R5H474-R, the price at that quantity, and current stock.
- b. **Lead time and status.** A distributor currently lists this part as active, with a standard manufacturer lead time of 21 weeks. Is that current? Is the part in active production with no discontinuation notice planned?
- c. **Delivery to Ukraine.** Can you ship to Ukraine? If not, which authorised Eaton distributor serves customers in Ukraine?
- d. **For planning only.** An indicative price per piece at 1 000 and at 10 000 pieces.

**Part B — Technical questions for the Eaton field application engineer**

Your KR series data sheet (Technical Data 4327, June 2026) specifies capacitance, ESR and endurance, the endurance rating being 1000 hours at 70 °C and 5.5 V. Note 1 of that table recommends verification "under end application conditions". Our application falls outside what the table states in three respects, listed below. We would value your data more than general rules.

For **every figure** you give, please tell us: whether it is a guaranteed (specified) value or a typical one; whether it is a design value or was measured on production units; and, if measured, on how many units and with what spread. "We have no data on this" is also a useful answer for us.

**1. Voltage acceleration factor at 4.82 V**

- a. Relative to the endurance rating at 5.5 V, by what factor does the expected life of the KR-5R5H474-R increase when the capacitor is held at 4.82 V instead of 5.5 V? Please assume the same temperature and the same end-of-life criteria as the endurance rating.
- b. If your data is a rule or a curve rather than one number (for example, life doubling for a given voltage reduction), please give the rule and the voltage range over which it holds. Please also state whether the voltage step refers to the whole 5.5 V part or to one cell inside it. Because our threshold has a tolerance, a rule is more useful to us than a single point.
- c. Can this factor be multiplied with the temperature rule (life doubling for every 10 °C lower) at field temperatures far below 70 °C, or do the two effects interact?
- d. Is this factor specific to the KR-5R5H474-R, or a general guideline for your supercapacitor range?

**2. Leakage current at 4.8 V**

- a. What is the leakage current of the KR-5R5H474-R when held (float-charged) at 4.8 V and measured after at least 72 hours at that voltage? Please give the value at 25 °C and, if you have it, at lower temperatures, and state the temperature of each figure.
- b. Is there a guaranteed maximum, or only a typical value? What is the spread between units?
- c. How is it measured: charging voltage, holding time before the reading, temperature, any preconditioning?
- d. If what you have is a self-discharge figure (the voltage remaining after a period on open circuit) rather than a float current, please send it with its test conditions and tell us that it is a self-discharge figure. For our energy budget we need the steady float current, and the two are not the same quantity.

**3. Behaviour below −25 °C**

The table gives an operating range down to −25 °C. In 30 years of weather reanalysis data for our planned installation region, the coldest daily mean temperature is about −24 °C, so on the coldest nights the temperature is likely to fall below −25 °C. We have not measured the temperature inside the capsule.

- a. What happens to the capacitance and the ESR of the KR-5R5H474-R below −25 °C? Please give figures as far down as you have data.
- b. Are these changes reversible when the temperature rises again, or does exposure below −25 °C cause a permanent loss? Does repeated exposure, on cold nights every winter, make a difference?
- c. Is there a temperature below which the part is damaged, whether or not it is held at voltage?

**4. Documents and contact**

- a. Please confirm that Technical Data 4327 (June 2026) is the current revision of the KR data sheet, and send a newer one if it exists.
- b. Any application note, qualification report or test data that supports your answers to questions 1–3.
- c. A technical point of contact for follow-up questions.

**Confidentiality.** The technical specification of our device is openly published, so no confidentiality agreement is needed to discuss it. We are happy to sign your standard agreement covering commercial terms (prices, schedules). Because our design documentation is public, please tell us which of your figures we may quote there, with attribution to Eaton, and mark anything that is for internal use only.

Thank you in advance.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 6. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) | фізична специфікація EDLC · endurance-hours замість cycle-count · вимога витоку · температурне правило |
| [`02_03 §9.3`](../../02_03_BQ25570_MPPT_Nano_Power.md) · [`02_03 §9.6`](../../02_03_BQ25570_MPPT_Nano_Power.md) | член самопрозряду, якого баланс не несе · сон Сценарію C |
| [`02_03 §4`](../../02_03_BQ25570_MPPT_Nano_Power.md) · [`02_03 §8`](../../02_03_BQ25570_MPPT_Nano_Power.md) | `VBAT_OV` = 4.822 В і його допуск (§4.Б) · робоче вікно 3.4 В → `VBAT_OV` |
| [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 3 | SKU, закритий виключенням · ціна на партію 10 000+ |
| [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | огинаюча капсули −40…+85 °C (§3 — чому не в листі) |
| [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) §HW.37 · `tools/in_silico/cache/kinetics/gusak_degradation.json` | бракет строку (`edlc_endurance_hours`) · найхолодніша середньодобова (`arrhenius_field_temperature.freeze_thaw`) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37 · ARCH.8 · HW.12 · HW.7 | дім стану · розвилка, що чекає витоку · ціна К2 клампа · підстава Derate |
| [`rfq_registry`](rfq_registry.md) · [`ua_vendor_map`](ua_vendor_map.md) | procurement-індекс (рядок «Капсула електроніка», §4.D — дім трьох FAE-питань) · карта UA-адресатів (рядка EDLC немає) |
