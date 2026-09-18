# Anchor — Fatigue (S-N) Test-House RFQ (printed Ti-6Al-4V specimens in synthetic xylem sap)

> **Що це:** RFQ-аркуш для **механічного тест-хаусу** — осьове втомне (S-N, Wöhler) випробування гладких зразків друкованого Ti у синтетичному ксилемному соку, з гігацикловими опціями, фрактографією й статистичним плануванням. Зміст — [`sn_fatigue_test_plan`](../anchor/sn_fatigue_test_plan.md) §10, переписаний як лист; **план лишається домом предмета, серій, рівнів і відкритих присудів**, тож репо-шар нижче — мапа «розділ листа → параграф плану → що прибрано», а не друга копія плану.
> Зразки сюди ПРИХОДЯТЬ від DMLS-вендора деталей (пропозиція плану §9 п.15), тож сусід цього листа — [`vendor_templates`](vendor_templates.md) §Processing п.16, а не coin-лист: купон Stage-2 робочої частини під осьове навантаження не має (план §1.2).
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-14, не надіслано**. Усі числа — дзеркало плану (а через нього канону й кешу), дім кожного названо поруч; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 (плече Δbake — HW.27).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Анкер — втома друкованого Ti (S-N) — тест» · hard-constraint дім §4.B).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — специфікація відкрита; CDA = стандартні комерц-умови.

---

## 0. Як користуватись + cover-note

1. **Окремий аркуш, а не рядок сусіднього листа:** адресат інший (механічний тест-хаус, не електрохімічна лабораторія й не друк-бюро), зразок інший (гладкий під осьове навантаження), і тест споживає зразки, які друкує й обробляє вендор деталей.
2. **Квоту й спроможність просити можна зараз, замовлення — ні.** Лист чинний за будь-якого з присудів плану §9: маршрут випробування, run-out, R, критерій відмови, статистику, режим температури, кількість серій, а також пропозиції плану (§9 п.15 — «we plan / we intend … confirmed before the order») він просить оцінити поштучно («quote per …»), а не фіксує. Питати раніше варто ще й тому, що відповідь про маршрути — одна з трьох передумов послідовності (план §2.5 п.1); вибір маршруту лишається за founder, лист тест-хаусу його не передає.
3. **Сліпий аналіз — ДЕЛЕГОВАНИЙ присуд, розширений на цей лист і того ж дня ПЕРЕГЛЯНУТИЙ (2026-09-14)** (запис із підставою й ціною — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24; ✅ **ратифіковано founder 2026-09-17** — переглянута форма чинна). **Приховане лишається прихованим:** оцінка межі витривалості зі смугою, SF, in-silico вердикти й наші гіпотези про місце зародження та ланцюг шару — перелік у плані §10. Для σ_e є друга підстава, якої coin-лист не мав: число складене з множників, жоден із яких не виміряно (план §4.1), тож воно заякорило б сітку на числі без провенансу — ⚠️ і тому це відхід від винятку coin-листа (там ішли числа, під які будується метод, а смуга σ_e для втоми саме така). **Змінилось після ревʼю в рамці тест-хаусу:** «сліпоту» рівнів і фрактографії замінено процедурами, УЗГОДЖЕНИМИ ДО випробувань (рівні · критерії зупинки · класифікація місця зародження), а факти процесу серій, потрібні для поводження й фрактографії, узгоджуються при замовленні. Підстава перегляду — та сама нога «правдиво»: рівні однаково йдуть за процедурою, фрактографія до процесу сліпою не буває (HIP, обробку й травлення видно на зламі), а класифікація без фактів процесу гірша, тоді як попередня фіксація критеріїв саме й не дає висновку підлаштуватися. **Ціна:** (1) без смуги старт staircase може лягти далеко від медіани — мітигація: розтяг свідків до сітки, step-test зразки опцією, пілот; (2) тест-хаус знатиме маршрут серій, тож класифікація може нахилитися — мітигація: критерії фіксуються до випробувань, а сирі знімки повертаються нам для незалежної перекласифікації. ✅ **Останнє відкрите закрито — ⚖️ founder 2026-09-17:** статус bake серій **кодується** до звіту класифікації — факт процесу, якого на зламі, найімовірніше, не видно, і саме той, під яким стоїть гіпотеза про шар. **Ціна:** тест-хаус не зможе пояснити різницю серій маршрутом — пояснюємо ми, своїм прочитанням знімків. **Наслідок для посилки:** зразки йдуть через нас, без сертифіката вендора всередині (§3; EN «via us»).
4. **Відповідь тест-хаусу в репо не комітиться** — ціни, внутрішні методики й номери сертифікатів є чужими операційними фактами. Сюди й у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 іде лише наш висновок.

---

## 1. Звідки кожен розділ листа — і що з нього свідомо прибрано

| Розділ листа (EN) | Дім | Як подано | Прибрано (§0 п.3) |
|---|---|---|---|
| **Scope · service exposure** | план §0 · §1.1 · §5.1 | предмет — матеріал у стані процесу деталі, не деталь; «до порядку 10⁹ циклів» замість одного числа, бо бюджет до одного числа не звужується (HW.43); частоту служби названо ще не зафіксованою — канонна смуга [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) не має джерела (план §5.1 ⚠️) | що напруження деталі не пораховане ніде (план §1.3) — наша прогалина, не параметр методу |
| **Base case** | план §10 п.7 · ревʼю в рамці тест-хаусу | базовий кейс ПРОПОНУЄ тест-хаус (одна серія, A, run-out 10⁷), усе інше — дельтами, щоб відповідь не стала прайсом; R = −1 — лише для ціни | — |
| **Specimens we supply · series** | план §2 · §3 | серії описано тим, що тест-хаус мусить ОБРОБИТИ (середовище · обробка робочої частини · кількість орієнтацій), а не маршрутом; дві орієнтації — ратифіковано ⚖️ 2026-09-18 («quote per orientation», без «confirmed»); «three to five further conditions» (обидва прочитання ΔHIP · Δbake на обох температурах) — «confirmed before the order»; виробник, робоча частина «в розмір» і простежуваність — «we plan / we intend» | параметри маршруту (HIP · bake — ⚖️ HW.27) і що саме змінює кожна серія, яка різниться маршрутом (серії «в повітрі» й «з обробленою робочою частиною» свою мету називають самі) |
| **Test medium** | план §7 → рецепт [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); форма — [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) §2 | точка тієї самої таблиці (⚖️ 2026-09-17: без оксалату, pH 5.75 через KOH) і те саме застереження про слабкий буфер, що в coin-листі; режим і уставка температури — «confirmed before the order»; O₂ · потенціал — опціями | число потенціалу: вікно стеку — висновок плану, не вимір |
| **Test methods A–H · run-out** | план §5.3 · §6.2 | вісім маршрутів і три run-out — опції з ціною й часом каналу; матриця серій × маршрутів; сила-контроль лише на звичайних машинах, на ультразвуку — амплітуда з калібруванням напруження; частота A — «confirmed before the order»; потенціостат — лише на A; міст частот мотивовано тим, що опубліковані результати розходяться (план §5.2 а) | Arrhenius-оцінка стиску (план §5.2 в) |
| **Stress levels** | план §4.2 | правило: якір — розтяг свідків, сітка на кожну серію; step-test зразки опцією; процедура узгоджується до випробувань | σ_e зі смугою (план §4.1) · SF · дерейт скрипта `55` |
| **Stop criteria · fracture surfaces · fractography · statistics** | план §6 | критерій на кожній точці; «функція може бути втрачена до розділення» + ціна виявлення зародження на підмножині; збереження зламів; класи місця зародження без нашої гіпотези, критерії — до випробувань; медіана ⊥ P-S-N для двох прикладів пар (p, γ) | ланцюг «тріщина шару → відкол із ферментами» (план §6.1) · гіпотеза «після HIP загрози поверхневі» (план §5.2 а) |
| **Programme phases** | план §2.5 | фаза 0 (платна інженерія: геометрія · перевірка співвісності · прогін середовища · процедури), пілот, далі фази | що послідовність — пропозиція плану |
| **Data · what we ask you to provide** | план §10 п.1–7 | пункти §10, розгорнуті в поля (+ питання про повернення зразків — як у coin-листі) | — |
| **Possible follow-on** | план §2.3 · §8 | другий сплав · шов дроту з друкованою деталлю · ґратка — «окремим запитом» | чому шов і ґратка окремо (HW.34 · план §8) |

⊕ **Лист додає до плану кілька речей, і всі записано в план** (§5.2 а · §5.3 · §10 п.2 · §11): **(1)** позначення ISO 1099 і ISO 12107 звірено за каталогом iso.org 2026-09-14 — тож лист називає їх без року й просить видання, бо ISO 1099 саме переходить до наступного видання; **(2)** питання, як статистика трактує змішані механізми зародження в одній серії: абстракт **відкликаної** ISO 12107:2003 обмежував метод даними одного механізму руйнування, абстракт чинного видання 2012 цього речення не несе, а змісту жодного ми не читали — тож лист питає, а не цитує; **(3)** з пошуку адресатів того ж дня (кожне звірено окремо): контрдоказ частотного ефекту, якого план не мав (Wycisk 2015 · Fitzka 2021) — звідси чесніше формулювання мосту D; ASTM F1801 як приклад практики корозійної втоми; акредитація **по тесту**, а не по лабораторії; число осередків зародження у фрактографії; об'єм і поверхня найбільш навантаженої зони кожної геометрії; **(4)** з адверсарного ревʼю в рамці тест-хаусу (усе записано в план): базовий кейс і дельти · матриця серій × маршрутів · маршрути G (резонанс у соку до 10⁸) і H (дві звичайні частоти в соку) · фаза 0 · збереження зламів · критерії класифікації й процедура рівнів ДО випробувань · step-test зразки · запаси, вхідний контроль і недійсні випробування · напруження на номінальному й виміряному перерізі · параметр западин шорсткості · P-S-N із прикладами пар · ASTM E739 / E1012 / ISO 11782-1 (назви звірено) · «tested in synthetic sap» замість «in the solution», яке металург прочитав би як solution treatment.

---

## 2. Відкрите, яке лист обходить питанням (присуд — не тут)

| Відкрите | Як лист лишається чинним | Дім присуду |
|---|---|---|
| маршрут випробування (план §5.3 A–H) · run-out · частота A | усі маршрути й три run-out — опції з ціною й часом каналу; частота A — «confirmed before the order» (тест-хаус називає діапазон, а не обирає: інакше обере найшвидшу) | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 (план §9 п.1) |
| R | R = −1 лише для базового кейсу ціни; решта R — питанням; «confirmed before the order» | HW.23 (п.2) |
| прочитання ΔHIP · Δbake на обох температурах | «three to five further conditions … quote per series» | HW.23 (п.4) · HW.27 (п.5) |
| температура bake · комірка bake × середовище | маршруту лист не несе; комірка — опція «one further condition in laboratory air» | HW.27 · HW.23 (п.5–6) |
| сплав | Ti-6Al-4V зараз; другий — follow-on | HW.24 (п.7) |
| pH · глюкоза · температура · O₂ · потенціал | межі + «confirmed before the order» (для температури — і режим: стала ⊥ цикл, цикл опцією); O₂ і потенціал — опції | HW.3 · HW.24 · HW.23 (п.8) |
| критерій відмови | критерій на кожній точці + ціна виявлення зародження | HW.23 (п.9) |
| статистика й `n` | ціна за медіанну криву і за P-S-N для двох прикладів пар (p, γ); наша пара — «confirmed before the order» | HW.23 (п.10) |
| частота гойдання в полі | лист її не називає — «the service frequency itself is still being fixed»: польова частота є дужкою двох прочитань одного майданчика (0.26–0.312 ⊥ 0.74 Гц, розбіжність без названої причини), а 1–5 Гц — частота стенда, не поля (план §5.1) | HW.43 |
| тонкостінна серія | питання про найменший надійний переріз | HW.23 (п.13) |
| **пропозиції плану, яких канон не несе** (п.15) | виробник зразків · робоча частина «в розмір» · простежуваність — «we plan / we intend», перші дві ще й «confirmed before the order»; шорсткість кожної серії — рядок ціни. **Лист стоїть на двох:** якір рівнів (розтяг свідків — без нього правило рівнів не формулюється) і фрактографія кожного зруйнованого (вона в Scope · Fractography · Phases · Data — зняти її означає правити чотири розділи, не рядок ціни). Сік прискореного тесту лист не називає: він дає діапазони рецепта, спільного з тим тестом | HW.23 (п.15) |
| хто виготовляє зразки | «the part manufacturer that prints them is confirmed before the order»; **шлях посилки вже вирішено** — «will reach you via us»: статус bake кодується (↓), а сертифікат вендора в посилці розкрив би маршрут серії | HW.23 (п.15) |

✅ **Знято з таблиці — ⚖️ founder 2026-09-17** ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24): сліпий аналіз у переглянутій формі чинний (процедури й критерії — до випробувань, факти процесу — при замовленні), а статус bake серій **кодується** до звіту класифікації — тож «The process information each series needs … is agreed at the order stage» статусу bake не охоплює, а зразки їдуть через нас.

---

## 3. Dispatch checklist (👤)

- [ ] 👤 **Сліпий аналіз — ✅ ратифіковано founder 2026-09-17, лишилось виконати при замовленні** (§0 п.3; запис і ціна — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24): переглянута форма чинна, статус bake серій **кодується** до звіту класифікації → серії передати тест-хаусу під кодами, без статусу bake в супровідних документах; посилка зразків — через нас, без сертифіката вендора всередині (EN «via us» це вже каже).
- [ ] 👤 **Квота й спроможність — зараз:** відповідь про маршрути — одна з передумов послідовності (план §2.5 п.1). **Замовлення — після** присудів §2 і вибору DMLS-вендора.
- [ ] 👤 **Адресати — не контактовано.** Кандидати з desk-пошуку 2026-09-14 (публічні сторінки, реєстр НААУ й анотації; спроможність під наш зразок НЕ підтверджена ні в кого — лист її питає):
  - **ІПМіц ім. Писаренка НАН, Київ** (додано 2026-09-17, [`ua_vendor_map §6`](ua_vendor_map.md)) — Instron 8802 (мало- і багатоциклова втома, камера −198…250 °C) + резонансна RUMUL TESTRONIC; сертифікат ДСТУ EN ISO 10012 (не 17025); стороннім — договір НДР. ⚠️ Корозійної комірки й VHCF не заявлено.
  - **ФМІ ім. Г.В. Карпенка НАНУ, Львів** — корозійно-втомні випробування заявлено послугою; ⚠️ **посторінкова звірка обсягу 2026-09-17: втома акредитована лише за ГОСТ/ДСТУ, ISO 1099 і корозійної втоми в обсязі НЕМАЄ**; акредитація НААУ 202167 називає втомну міцність, але чинна до **20.10.2026** (питати про поновлення), методи обсягу — ГОСТ/ДСТУ; ультразвуку не знайдено.
  - **ІЕЗ ім. Є.О. Патона НАНУ, Київ** — акредитація НААУ 20362 до 02.04.2030, ⊕ звірено: **ISO 1099:2017 прямо в обсязі**; ЦКК MTS 318.25 заявлено як «випробування в різних середовищах», але чи це корозійна комірка під наш зразок, не звірено — окремої корозійної комірки не знайдено; ультразвуку не знайдено; поруч із київським друком.
  - **TU Dortmund, WPT** — публікації про VHCF лазерно-друкованого Ti-6Al-4V до 10⁹ і корозійну втому L-PBF у фізіологічному середовищі; акредитацію не знайдено.
  - **BOKU (Відень)** — ультразвукова втома 20 кГц, as-built AM-зразки (316L, не Ti), камери середовища; випробування в рідині на 20 кГц не звірено.
  - **EndoLab (DE)** — акредитований обсяг DAkkS називає корозійну втому ASTM F1801 і Ti6Al4V; VHCF не знайдено.
  - Ультразвукової VHCF в Україні пошук не знайшов. ⚠️ Інститути НАН працюють із зовнішніми замовниками договором НДР під технічне завдання — для них потрібен не EN-лист, а **ТЗ українською** з того самого змісту.
- [ ] 👤 **Зразки йдуть DMLS-листом, і його пп. 2–4 та 14 не поширюються на серії, що від них відходять** (пп. 2 · 4 · 14 — HIP · bake · активація — «mandatory»; п.3, орієнтація, — з 2026-09-17 питання, не вимога). Питання вже стоїть у pre-qual листі ([`vendor_templates`](vendor_templates.md) §Processing п.16, разом із ціною свідків на розтяг кожної серії) — перевірити, що воно поїхало тим самим листом; сам рядок замовлення зразків пишеться після ⚖️ «хто виготовляє зразки» (план §9 п.15). ⚠️ Статус bake серій кодується (⚖️ 2026-09-17) — тож посилка йде через нас, без сертифіката вендора всередині.
- [ ] 👤 **CDA — на комерційній стадії, не перед запитом:** лист сам каже, що для обговорення відкритої специфікації угода не потрібна; стандартний взаємний CDA — при замовленні ([`rfq_registry`](rfq_registry.md) §3).
- [ ] 👤 **Після відповіді:** висновок (не чужі ціни й внутрішні факти) → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23; маршрут, run-out і `n` — у присуди плану §9.

---

## 📤 Dispatch block (EN) — paste into test-house email

> Ready-to-send English text. Working body above stays Ukrainian. Anything our side
> must NOT disclose is deliberately absent — **немає** нічого з переліку плану §10 «Не йде в лист» (дім переліку; головне —
> оцінка межі витривалості зі смугою, SF, in-silico вердикти, гіпотеза про місце зародження, маршрут кожної серії;
> сліпий аналіз — §0 п.3) · а також імен вендора деталей, кандидатів і академ-каналу.
> Адресат — **механічний тест-хаус**; друк і обробка зразків ідуть DMLS-листом (`vendor_templates.md` §Processing п.16).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-нота (що саме прибрано й чому), у лист вона НЕ йде.

### Subject line

RFQ — axial fatigue (S-N) testing of laser powder-bed-fused Ti-6Al-4V specimens in synthetic xylem sap, with very-high-cycle options, fractography and statistical planning (R&D programme)

### Scope of request

We are an R&D group developing a titanium anchor that is implanted into living trees and has to stay there for about twenty years, flexed by the wind-driven sway of the trunk — up to the order of 10⁹ load cycles over its life; the service frequency itself is still being fixed on our side. Before relying on the printed metal in that service we want its fatigue curve — the relation between stress amplitude and cycles to failure, with its scatter — measured on smooth specimens that carry the material condition of the part: the same printing route, the same heat treatment and the same surface treatment, tested in a medium modelled on tree sap rather than a generic buffer.

What we buy from you is the test: planning, machine time, fractography and traceable raw data. The specimens will reach you via us; the part manufacturer that prints them is confirmed before the order.

This is a request for a quotation and a capability statement, not yet an order. Several choices are still being fixed on our side and are marked **"confirmed before the order"** below. So that the quote does not become a rate card, please **price one base case of your own design first** (see *Base case*) and every other item as a delta on it. Your answer on the test routes is also an input to how we sequence the programme, which is why we ask now. If specimen design and test planning are paid engineering for you, quote them as a **Phase 0** (see *Programme phases*).

We send no estimate of the fatigue strength and no model predictions: we want the stress levels and the classification of crack-initiation sites to follow procedures agreed before testing, not an expected outcome. The process information each series needs for handling and fractography is agreed at the order stage.

### Base case — please price this first

One series — the production condition, tested in synthetic sap — on method A at a frequency you propose, fully reversed loading (R = −1, the base case for pricing only), run-out at 10⁷ cycles, one constant temperature and one pH within the ranges below, your recommended number of specimens for a median S-N curve with a staircase at the run-out, tensile witnesses, SEM fractography of every failed specimen, and the report. State the machine-channel time the base case occupies. Price every other series, method, run-out and option below as a delta on it.

### Specimens we supply

- **Alloy:** Ti-6Al-4V (ASTM F2924, powder-bed fusion). A second alloy — titanium-based or tantalum, not yet selected — may follow (see *Possible follow-on*).
- **Production route:** we plan to have the specimens printed and post-processed by the manufacturer of our part, along the part's own process route including its heat treatment and surface treatment, so that the curve describes that route and not a generic one. We intend each specimen to carry an ID, with build, plate position, build orientation and powder lot recorded against it, and we will pass on the manufacturer's as-built tolerances, minimum-feature and support rules once we hold them.
- **Type:** smooth specimens for axial loading, with no deliberate stress concentration. For a conventional machine we intend the **gauge section of most series to be printed to size and not machined** (confirmed before the order) — the lattice walls of the part cannot be machined, so its surface is as printed and then chemically treated; grip ends may be machined. For an ultrasonic machine a resonant geometry is needed — tell us whether it would have to be machined, and propose it.
- **Please propose the specimen geometry** for each machine you would use, and tell us:
  - how you would report stress on a rough as-printed gauge — we ask for **both** the nominal section and a measured minimum section — and how you measure the latter (for example by CT);
  - the smallest gauge section you can test reliably, with the load range and the alignment verification it implies (for example to ASTM E1012): the lattice struts of the part are under 1 mm thick, and a thin-section series is an option we are considering — state the stress ratio such a gauge would need, since it may buckle at R = −1;
  - whether a conventional and an ultrasonic test can run on **one** specimen geometry (see *D*);
  - your incoming inspection, the spare specimens per series you would want, and how you treat a failure outside the gauge — for example at the blend between an as-printed gauge and a machined grip: as an invalid test, and at whose cost.
- **Series.** Each series is its own S-N curve. All are the same alloy; they differ in post-processing, in the finish of the gauge, in build orientation or in test environment:
  - the **production condition, tested in synthetic sap** — in **two build orientations** (specimen axis parallel and perpendicular to the build direction); please quote per orientation;
  - **three to five further conditions, tested in synthetic sap**, confirmed before the order — all with an as-printed gauge except one with a machined gauge; please quote per series;
  - the **production condition, tested in laboratory air** on the same machine type and at the same frequency as in sap;
  - *options:* one further condition tested in laboratory air, and one further condition tested in synthetic sap.
- **Same-build witnesses, per series** (per build, if a series spans builds): tensile specimens (yield strength, ultimate tensile strength, elongation) — quote per specimen; and the surface roughness of the gauge per series, stated as named parameters together with the instrument, including a **valley parameter** (for example Sv, Sz or Rv) besides an average one.

| Series | Method | Environment | Run-out options | Phase |
|---|---|---|---|---|
| Production condition (two build orientations) | A | synthetic sap | 10⁷ | 1–2 |
| Further conditions (three to five) | A | synthetic sap | 10⁷ | 3 |
| Production condition | A | laboratory air | 10⁷ | 3 |
| Production condition — very-high-cycle extension | B · C · D · G | air (B, D) · sap (C, G) | 10⁸ · 10⁹ | 4 |
| Production condition — time dependence in the medium | E · F · H | synthetic sap | see each method | 4 |
| Options: one further condition in air, one in sap | A | as named | 10⁷ | 3 |

### Test medium

**Synthetic xylem sap**, target species Scots pine (*Pinus sylvestris*). Working composition:

| Component | Concentration |
|---|---|
| Malic acid | 2.2 mM |
| KNO₃ | 3.2 mM |
| CaCl₂ | 1.0 mM |
| MgSO₄ | 0.45 mM |
| KOH | to the pH set-point — record the amount added per batch |

- **pH: 5.75.** There is no added buffer system — malic acid is the only buffer and KOH sets the pH — so the medium is weakly buffered and small amounts of acid move its pH noticeably. Tell us how you set, hold and log pH over runs lasting days to months. A precipitate on the specimen would change both the medium and the surface under test, so check for one (Medium upkeep below). Quote medium preparation per batch.
- **No sugar** is in the medium, but malate is itself a carbon source, so multi-week runs can still support microbial growth — say how you would control it. Add **no preservative, biocide or inhibitor** to the medium without agreeing it with us: any additive changes the corrosion chemistry under test.
- **Temperature:** **constant or slowly cycled within 20–40 °C — confirmed before the order.** Quote a constant set-point and, as an option, a cycle within that range; state your control band, and whether a controlled temperature above ambient is possible in your fatigue cell.
- **Dissolved oxygen:** in service the sap carries little oxygen, and a variable amount, so an air-saturated cell does not reproduce it. Tell us whether you can log dissolved oxygen, and quote controlling it (for example by gas purging) as an option.
- **Electrochemical potential:** in service the metal is part of an electrochemical cell, so its potential need not be the free-corrosion potential. Quote, as an option **on method A only**, holding the specimen at a set potential during cycling (a potentiostat in the fatigue cell) — the potential is confirmed before the order — and tell us how the specimen is electrically isolated from grips and fixtures, and how a potential-drop crack-detection current, if you use one, would interact with it.
- **Medium upkeep and QC:** state the volume per specimen and the replacement schedule for long runs, logging pH (and oxygen, where logged) at every replacement; per batch, check pH with a calibrated meter, conductivity, the major ions, and that the batch carries **no precipitate** — right after preparation and again at the end of use. Include the records in the report.

### Test methods — please quote each as a delta on the base case

**General conditions.** Constant-amplitude axial loading — force-controlled on conventional machines; on ultrasonic machines, displacement-amplitude-controlled with the stress calibration stated. The stress ratio is **confirmed before the order**: tell us which ratios your machines and the specimen geometry support besides R = −1 — on an ultrasonic machine a ratio other than −1 needs an added static load.

**A. Conventional axial machine, to 10⁷ cycles** — in synthetic sap, and in laboratory air for the air series. State the frequency range you can run in each environment (the test frequency is confirmed before the order), the channels available, the cell type (immersion or flow) and the machine-channel time per specimen.

**B. Ultrasonic fatigue (about 20 kHz) in laboratory air, to 10⁹ cycles.** State the cooling method and pulse–pause regime, the effective test time per specimen, and how you calibrate the stress in the specimen.

**C. Ultrasonic fatigue in synthetic sap, to 10⁹ cycles** — whether it is possible at all, and at what development cost. If so: how the liquid is kept to the gauge (a displacement node) and off the specimen ends, where it would turn the test into cavitation erosion; how you keep the liquid from heating or degassing; and how you log its temperature and dissolved oxygen. 10⁹ cycles at 20 kHz is under a day of loading against years in service, so we read this route with caution in a time-dependent medium.

**D. Frequency bridge.** The production condition at the same stress level and in the same environment on two machines whose cycle ranges overlap (up to 10⁷ cycles) — in laboratory air (conventional against ultrasonic), and in synthetic sap as well if C is possible. Published results differ — a review reports titanium alloys insensitive to test frequency, while a study of one Ti-6Al-4V reported an effect for crack initiation at the surface of smooth specimens — and our as-printed gauge is surface-dominated, so we ask the price of measuring the effect rather than assuming either answer. Tell us whether the bridge can run on one specimen geometry; if it needs two, state the highly stressed volume and surface of each, or a size effect will read as a frequency effect. State the specimens per frequency you would need to resolve, for example, a factor of two in life.

**E. Long static pre-exposure in synthetic sap, then fatigue** — for example several weeks of immersion before cycling. State how practical this is for you.

**F. Low-frequency cycling in synthetic sap** — at a low frequency confirmed before the order, of the order of 1 Hz: machine-channel time per specimen to 10⁶ and to 10⁷ cycles, and a price per machine-month.

**G. Resonant machine in synthetic sap, to 10⁸ cycles** — of the order of 100 Hz, if you have one with a cell: a middle route between A and the ultrasonic ones.

**H. Two conventional frequencies in synthetic sap** — the same series and stress level at the frequency of A and at a low frequency as in F, to show whether the time per cycle matters in the medium.

**Run-out.** Quote run-out options at **10⁷, 10⁸ and 10⁹ cycles** for each method where they are practical, with the machine-channel time each implies. State what you do with run-out specimens (for example re-testing at a higher level) and how you report them.

### Stress levels

1. **Anchor the levels of each series on the measured tensile properties of that series' same-build witnesses.** We want the tensile results before the fatigue levels are set.
2. *Option:* **two or three step-test specimens per series** to locate the starting level, where tensile properties alone could place it far from the median.
3. **Finite-life levels** to fix the slope, plus a **staircase or probit allocation** for the fatigue strength at the chosen run-out. Propose the number of levels, the spacing and the method.
4. **Re-anchor per series.** The series may differ, so one common grid could waste a series' specimens in run-out or in immediate failure.
5. The level procedure is **agreed before testing and followed as agreed**, on the information we supply.

### Stop criteria, fracture surfaces, fractography and statistics

- **Stop criteria:** state the criterion each machine stops on — separation, a stated drop in stiffness or resonance frequency, or a detected crack — and record on every data point which criterion ended the test. The criterion is **confirmed before the order**. The function of our part can be lost at crack initiation, before the specimen separates: tell us whether and how you can detect initiation, and at what crack size, as a priced option on a subset of specimens (for example three).
- **Fracture surfaces:** tell us how you preserve them — where possible stopping before separation and breaking the specimen open, and rinsing and drying specimens tested in sap within a day of failure. At R = −1 the crack faces can rub the initiation site away.
- **Fractography:** **SEM fractography of every failed specimen**, with the crack-initiation site classified per specimen (for example at the surface, at a near-surface pore or defect, or internal), the number of initiation sites, and images — price per specimen. The **classification criteria are agreed before testing**.
- **Statistics:**
  - quote the specimens per series for **(a) a median S-N curve** and for **(b) a probabilistic (P-S-N) curve** at a failure probability p and one-sided confidence γ, for two example pairs — for example p = 10 % at γ = 90 %, and p = 1 % at γ = 95 %; our pair is confirmed before the order;
  - tell us how your analysis treats specimens within one series whose cracks initiate by **different mechanisms** (for example surface versus internal initiation) — as one population or as separate ones;
  - name the standards you work to, with their editions: the axial method (ASTM E466 or ISO 1099), statistical planning and analysis (ISO 12107, ASTM E739), alignment (ASTM E1012), corrosion fatigue (for example ISO 11782-1 or ASTM F1801, with our medium as a declared deviation), and any practice for ultrasonic testing — and say which of the tests above fall outside every standard you hold.

### Programme phases (please price separately)

0. **Phase 0**, if specimen design and planning are paid engineering for you: the specimen geometry, an alignment check on dummy specimens, a medium-stability run without specimens, and the agreed test matrix and procedures (levels, stop criteria, initiation-site classification).
1. **Pilot** on the production condition — propose its size: tensile witnesses, first fatigue points and their fractography, before the full programme.
2. **Production condition tested in sap** (two build orientations), with fractography.
3. **Further series** (one build orientation), including the air series.
4. **Extensions** by the routes we select after your quote — tell us which of B–D and E–H you would recommend, and why.

### Data we need back

Fitted curves alone are not enough: we may re-analyse the raw points with a different statistical model and use them as inputs to our own models.

- **Every data point:** specimen ID (with the build, plate position and orientation supplied with it), series, stress amplitude on both the nominal and the measured minimum section, mean stress (or R), frequency, cycles, stop criterion, run-out flag, test start and end, and the environment logs — temperature, pH, dissolved oxygen and potential where applicable.
- **Native machine records and an open export** (CSV or ASCII) per specimen — force, displacement or stiffness history, or resonance-frequency history for ultrasonic tests — with the sampling rate you log at.
- **Tensile witness curves** (raw), and roughness data with the parameters and the instrument.
- **Fractography images** of every failed specimen with the initiation-site classification, a **deviation log**, and every invalid test with its reason.
- **The statistical analysis together with its inputs** — raw points, never only fitted curves. Tell us whether you return tested specimens, with fracture surfaces protected.

### What we ask you to provide

1. **Capability statement:** axial machines (type, load range and the verified range of their load cells, frequency range, channels), resonant and ultrasonic fatigue systems, corrosion-fatigue cells (immersion or flow, temperature control, pH and oxygen logging, potentiostat), SEM, tensile testing and roughness measurement.
2. **Comparable work:** fatigue of additively manufactured titanium, corrosion fatigue, very-high-cycle fatigue (redacted examples are fine).
3. **Accreditation and quality system**, with certificate number, issuing body, scope and validity — ISO/IEC 17025 and ISO 9001, whichever you hold. **Per test, not per laboratory:** which accredited scope item (certificate and method) covers each test above, which tests would be run outside the accredited scope, and whether titanium alloys fall under the object of that scope.
4. **Itemised prices, as deltas on the base case:** machine-channel time per method (A–H) · Phase 0 · cell set-up, and medium preparation and QC per batch · tensile witness per specimen · step-test specimens · roughness per series · SEM fractography per specimen · each option separately (initiation detection, potential control, oxygen control) · statistical planning, analysis and report · the pilot.
5. **Turnaround:** queue time to start, the duration of each phase, and the report.
6. **Quote format:** currency, validity period, payment terms, and the technical point of contact.

### Confidentiality & publication

The technical specification is openly published, so no confidentiality agreement is needed to discuss it; we are happy to sign your standard mutual CDA covering commercial terms (prices, schedules, QC data). We may publish the results — please state any conditions you attach to publishing data you generate for us, such as acknowledgement, a description of your method, or a review of any text that names you.

### Possible follow-on (not part of this quotation)

- The same programme, or its production-condition part, on a second alloy once it is selected.
- Fatigue of a welded joint between a cold-drawn titanium wire and a printed titanium part.
- Fatigue of lattice (gyroid) specimens.

If any of these is within your scope, say so and we will send a separate request.

### Commercial & logistics

- Specimens will reach you via us, not directly from their manufacturer; tell us your receiving requirements.
- Tell us whether you prepare the medium from our recipe (preferred) or need it supplied.
- The Incoterms you quote on for returning tested specimens, and any export-control considerations you are aware of.

### Attachments

Nothing is required from us for an initial quotation. On request we supply the medium recipe once confirmed, the manufacturer's as-built design rules once we hold them, and the specimen requirements above as a drawing once you have proposed the geometry.

---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

## 4. Cross-references

| Ресурс | Що бере |
|---|---|
| [`sn_fatigue_test_plan`](../anchor/sn_fatigue_test_plan.md) | дім змісту: серії, рівні, маршрути A–F, критерії, статистика, відкриті ⚖️ §9 |
| [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | рецепт синтетичного соку (дім) · частота: польова — дужка іменованих прочитань, 1–5 Гц — смуга СТЕНДА |
| [`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §1.7`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | маршрут процесу деталі, який повторює зразок · HIP |
| [`01_01 §1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | мало й непостійно O₂ у ксилемі · метал як струмозбирач анода (звідки опція потенціалу) |
| [`vendor_templates`](vendor_templates.md) §Processing п.16 | зразки питанням у DMLS-листі; пп. 2–4 на серії не поширюються |
| [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) | взірець листа · та сама таблиця середовища |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс · §3 IP/CDA · §4.B |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 · HW.24 · HW.27 | дім стану · делегований сліпий аналіз · плече Δbake |
