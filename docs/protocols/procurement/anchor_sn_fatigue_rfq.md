# Anchor — Fatigue (S-N) Test-House RFQ (printed Ti-6Al-4V specimens in synthetic xylem sap)

> **Що це:** RFQ-аркуш для **механічного тест-хаусу** — осьове втомне (S-N, Wöhler) випробування гладких зразків друкованого Ti у синтетичному ксилемному соку, з гігацикловими опціями, фрактографією й статистичним плануванням. Зміст — [`sn_fatigue_test_plan`](../anchor/sn_fatigue_test_plan.md) §10, переписаний як лист; **план лишається домом предмета, серій, рівнів і відкритих присудів**, тож репо-шар нижче — мапа «розділ листа → параграф плану → що прибрано», а не друга копія плану.
> Зразки сюди ПРИХОДЯТЬ від DMLS-вендора деталей (пропозиція плану §9 п.15), тож сусід цього листа — [`vendor_templates`](vendor_templates.md) §Processing п.16, а не coin-лист: купон Stage-2 робочої частини під осьове навантаження не має (план §1.2).
> **Статус:** 🟡 робочий артефакт (не канон); **EN-лист написано 2026-09-14, ТЗ українською для установ НАН — 2026-09-23 (§📤 (UA) ↓); не надіслано жодного**. Усі числа — дзеркало плану (а через нього канону й кешу), дім кожного названо поруч; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 (плече Δbake — HW.27).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Анкер — втома друкованого Ti (S-N) — тест» · hard-constraint дім §4.B).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — специфікація відкрита; CDA = стандартні комерц-умови.

---

## 0. Як користуватись + cover-note

1. **Окремий аркуш, а не рядок сусіднього листа:** адресат інший (механічний тест-хаус, не електрохімічна лабораторія й не друк-бюро), зразок інший (гладкий під осьове навантаження), і тест споживає зразки, які друкує й обробляє вендор деталей.
2. **Квоту й спроможність просити можна зараз, замовлення — ні.** Ратифіковане планом §9.1 (маршрут і run-out · `R = −1` · критерій відмови · стала температура · кількість серій після ΔHIP-опції) лист НЕСЕ як рішення; відкрите — статистику й `n` (№10) і тонкостінне плече (№13) — просить запропонувати, а пропозиції плану (§9 п.15 — «we plan / we intend … confirmed before the order») — оцінити поштучно («quote per …»). Питати раніше варто ще й тому, що відповідь про маршрути — одна з трьох передумов послідовності (план §2.5 п.1); вибір маршруту лишається за founder, лист тест-хаусу його не передає.
3. **Сліпий аналіз — ДЕЛЕГОВАНИЙ присуд, розширений на цей лист і того ж дня ПЕРЕГЛЯНУТИЙ (2026-09-14)** (запис із підставою й ціною — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24; ✅ **ратифіковано founder 2026-09-17** — переглянута форма чинна). **Приховане лишається прихованим:** оцінка межі витривалості зі смугою, SF, in-silico вердикти й наші гіпотези про місце зародження та ланцюг шару — перелік у плані §10. Для σ_e є друга підстава, якої coin-лист не мав: число складене з множників, жоден із яких не виміряно (план §4.1), тож воно заякорило б сітку на числі без провенансу — ⚠️ і тому це відхід від винятку coin-листа (там ішли числа, під які будується метод, а смуга σ_e для втоми саме така). **Змінилось після ревʼю в рамці тест-хаусу:** «сліпоту» рівнів і фрактографії замінено процедурами, УЗГОДЖЕНИМИ ДО випробувань (рівні · критерії зупинки · класифікація місця зародження), а факти процесу серій, потрібні для поводження й фрактографії, узгоджуються при замовленні. Підстава перегляду — та сама нога «правдиво»: рівні однаково йдуть за процедурою, фрактографія до процесу сліпою не буває (HIP, обробку й травлення видно на зламі), а класифікація без фактів процесу гірша, тоді як попередня фіксація критеріїв саме й не дає висновку підлаштуватися. **Ціна:** (1) без смуги старт staircase може лягти далеко від медіани — мітигація: розтяг свідків до сітки, step-test зразки опцією, пілот; (2) тест-хаус знатиме маршрут серій, тож класифікація може нахилитися — мітигація: критерії фіксуються до випробувань, а сирі знімки повертаються нам для незалежної перекласифікації. ✅ **Останнє відкрите закрито — ⚖️ founder 2026-09-17:** статус bake серій **кодується** до звіту класифікації — факт процесу, якого на зламі, найімовірніше, не видно, і саме той, під яким стоїть гіпотеза про шар. **Ціна:** тест-хаус не зможе пояснити різницю серій маршрутом — пояснюємо ми, своїм прочитанням знімків. **Наслідок для посилки:** зразки йдуть через нас, без сертифіката вендора всередині (§3; EN «via us»).
4. **Відповідь тест-хаусу в репо не комітиться** — ціни, внутрішні методики й номери сертифікатів є чужими операційними фактами. Сюди й у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 іде лише наш висновок.
5. **Установам НАН — не EN-лист, а ТЗ українською: §📤 (UA) ↓** (написано 2026-09-23; ⚠️ founder тексту ще не бачив — ⛔ до його «так» не надсилати). Той самий зміст в оболонці проєкту ТЗ під договір НДР ⊥ послугу (форма — [`anchor_hip_rfq`](anchor_hip_rfq.md)). Розбіжності EN із планом, які знайшло складання ТЗ (кількість серій після №4 · pH-точка базового варіанта · уламок речення про `R` · «oxygen control» у цінах · «recipe once confirmed»), зведено в EN-блоці наступним проходом того ж дня (2026-09-24) — обидва блоки тепер кажуть одне.

---

## 1. Звідки кожен розділ листа — і що з нього свідомо прибрано

| Розділ листа (EN) | Дім | Як подано | Прибрано (§0 п.3) |
|---|---|---|---|
| **Scope · service exposure** | план §0 · §1.1 · §5.1 | предмет — матеріал у стані процесу деталі, не деталь; «до порядку 10⁹ циклів» замість одного числа, бо бюджет до одного числа не звужується (HW.43); частоту служби названо ще не зафіксованою — канонна смуга [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) не має джерела (план §5.1 ⚠️) | що напруження деталі не пораховане ніде (план §1.3) — наша прогалина, не параметр методу |
| **Base case** | план §10 п.7 · ревʼю в рамці тест-хаусу | базовий кейс ПРОПОНУЄ тест-хаус (одна серія, A, run-out 10⁷), усе інше — дельтами, щоб відповідь не стала прайсом; R = −1 — чинний для всіх серій першої програми (⚖️ 2026-09-21), не лише для ціни | — |
| **Specimens we supply · series** | план §2 · §3 | серії описано тим, що тест-хаус мусить ОБРОБИТИ (середовище · обробка робочої частини · кількість орієнтацій), а не маршрутом; дві орієнтації — ратифіковано ⚖️ 2026-09-18 («quote per orientation», без «confirmed»); «two or three further conditions» (Δbake на одній чи обох температурах · Δповерхня) — «confirmed before the order», і до двох опційних (ΔEAAE · ΔHIP прочитання (i)); виробник, робоча частина «в розмір» і простежуваність — «we plan / we intend» | параметри маршруту (HIP · bake — ⚖️ HW.27) і що саме змінює кожна серія, яка різниться маршрутом (серії «в повітрі» й «з обробленою робочою частиною» свою мету називають самі) |
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
| R | ✅ ⚖️ делеговано 2026-09-21 (план §9.1 №2): **R = −1 для ВСІХ серій першої програми**, не лише для ціни — один R тримає A, B/C і D на одній кривій. Другий R — лише коли стане відомим середнє напруження деталі | HW.23 (п.2) |
| прочитання ΔHIP · Δbake на обох температурах | «two or three further conditions … quote per series» + «options: up to two». ⚖️ **ΔHIP переведено в опційні діагностичні** (делеговано 2026-09-21, план §9.1 №4) — воно більше не живить жодного рішення, тож стоїть серед опцій, а не плечем; якщо купувати — прочитання (i). Δbake на обох температурах лишається живим: його температуру закриє пара LECO + XRD | HW.23 (п.4) · HW.27 (п.5) |
| температура bake · комірка bake × середовище | маршруту лист не несе. ⛔ Комірку bake × середовище **НЕ замовляємо** (⚖️ делеговано 2026-09-21, план §9.1 №6), тож опцію «one further condition in laboratory air» з листа знято; опція в соку лишається | HW.27 · HW.23 (п.5–6) |
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
  - Ультразвукової VHCF в Україні пошук не знайшов. ⚠️ Інститути НАН працюють із зовнішніми замовниками договором НДР під технічне завдання — для них потрібен не EN-лист, а **ТЗ українською** з того самого змісту — **текст готовий: §📤 (UA) ↓** (⚠️ 2026-09-23, founder ще не бачив; ⛔ до його «так» не надсилати; один текст — обом установам окремими листами).
- [ ] 👤 **Зразки йдуть DMLS-листом, і його пп. 2–4 та 14 не поширюються на серії, що від них відходять** (пп. 2 · 4 · 14 — HIP · bake · активація — «mandatory»; п.3, орієнтація, — з 2026-09-17 питання, не вимога). Питання вже стоїть у pre-qual листі ([`vendor_templates`](vendor_templates.md) §Processing п.16, разом із ціною свідків на розтяг кожної серії) — перевірити, що воно поїхало тим самим листом; сам рядок замовлення зразків пишеться після ⚖️ «хто виготовляє зразки» (план §9 п.15). ⚠️ Статус bake серій кодується (⚖️ 2026-09-17) — тож посилка йде через нас, без сертифіката вендора всередині.
- [ ] 👤 **CDA — на комерційній стадії, не перед запитом:** лист сам каже, що для обговорення відкритої специфікації угода не потрібна; стандартний взаємний CDA — при замовленні ([`rfq_registry`](rfq_registry.md) §3).
- [ ] 👤 **Після відповіді:** висновок (не чужі ціни й внутрішні факти) → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23; `n` і статистика — у присуди плану §9 (№10, відкрите). ⚠️ **Маршрут і run-out сюди більше НЕ йдуть — їх ухвалено** ⚖️ делеговано 2026-09-21 (план §9.1 №1: дельти A@10⁷, P до 10⁹ + міст D); відповідь тест-хаусу їх ПЕРЕВІРЯЄ на здійсненність, а не обирає.

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

One series — the production condition, tested in synthetic sap — on method A at a frequency you propose, fully reversed loading (R = −1 — the ratio for every series in this first programme, not only for pricing), run-out at 10⁷ cycles, one constant temperature within the range below and the pH set-point below, your recommended number of specimens for a median S-N curve with a staircase at the run-out, tensile witnesses, SEM fractography of every failed specimen, and the report. State the machine-channel time the base case occupies. Price every other series, method, run-out and option below as a delta on it.

### Specimens we supply

- **Alloy:** Ti-6Al-4V (ASTM F2924, powder-bed fusion). A second alloy — titanium-based or tantalum, not yet selected — may follow (see *Possible follow-on*).
- **Production route:** we plan to have the specimens printed and post-processed by the manufacturer of our part, along the part's own process route including its heat treatment and surface treatment, so that the curve describes that route and not a generic one. We intend each specimen to carry an ID, with build, plate position, build orientation and powder lot recorded against it, and we will pass on the manufacturer's as-built tolerances, minimum-feature and support rules once we hold them.
- **Type:** smooth specimens for axial loading, with no deliberate stress concentration. For a conventional machine we intend the **gauge section of most series to be printed to size and not machined** (confirmed before the order) — the lattice walls of the part cannot be machined, so its surface is as printed and then chemically treated; grip ends may be machined. For an ultrasonic machine a resonant geometry is needed — tell us whether it would have to be machined, and propose it.
- **Please propose the specimen geometry** for each machine you would use, and tell us:
  - how you would report stress on a rough as-printed gauge — we ask for **both** the nominal section and a measured minimum section — and how you measure the latter (for example by CT);
  - the smallest gauge section you can test reliably, with the load range and the alignment verification it implies (for example to ASTM E1012): the lattice struts of the part are under 1 mm thick, and a thin-section series is an option we are considering outside this programme's R = −1 — tell us whether such a gauge can run at R = −1 at all and, if not, which ratio it would need, with its price quoted separately;
  - whether a conventional and an ultrasonic test can run on **one** specimen geometry (see *D*);
  - your incoming inspection, the spare specimens per series you would want, and how you treat a failure outside the gauge — for example at the blend between an as-printed gauge and a machined grip: as an invalid test, and at whose cost.
- **Series.** Each series is its own S-N curve. All are the same alloy; they differ in post-processing, in the finish of the gauge, in build orientation or in test environment:
  - the **production condition, tested in synthetic sap** — in **two build orientations** (specimen axis parallel and perpendicular to the build direction); please quote per orientation;
  - **two or three further conditions, tested in synthetic sap**, confirmed before the order — all with an as-printed gauge except one with a machined gauge; please quote per series;
  - the **production condition, tested in laboratory air** on the same machine type and at the same frequency as in sap;
  - *options:* up to two further conditions tested in synthetic sap — please quote each separately.
- **Same-build witnesses, per series** (per build, if a series spans builds): tensile specimens (yield strength, ultimate tensile strength, elongation) — quote per specimen; and the surface roughness of the gauge per series, stated as named parameters together with the instrument, including a **valley parameter** (for example Sv, Sz or Rv) besides an average one.

**Which of these we intend to buy, so that the quote can be a plan and not a price list.** Our programme is decided: the single-factor delta series run on **method A in synthetic sap with run-out at 10⁷** — they measure the *difference* between conditions, so a flat limit beyond 10⁷ does not affect them — and the **production condition additionally runs to 10⁹** (method B or C, whichever your capability makes sound) **plus the frequency bridge D**, because 10⁹ is the only requested level that covers the service exposure stated above — which does not narrow to a single number on our side — and because the sign of the frequency effect on an as-built surface is unknown and the bridge measures it rather than assuming it. Methods **E · F · G · H stay in the table as priced alternates**: we ask their price so that we have a route if you tell us the intended one is not sound on your machines. The stress ratio is R = −1 throughout.

| Series | Method | Environment | Run-out options | Phase |
|---|---|---|---|---|
| Production condition (two build orientations) | A | synthetic sap | 10⁷ | 1–2 |
| Further conditions (two or three) | A | synthetic sap | 10⁷ | 3 |
| Production condition | A | laboratory air | 10⁷ | 3 |
| Production condition — very-high-cycle extension | B · C · D · G | air (B, D) · sap (C, G) | 10⁸ · 10⁹ | 4 |
| Production condition — time dependence in the medium | E · F · H | synthetic sap | see each method | 4 |
| Options: up to two further conditions in sap | A | synthetic sap | 10⁷ | 3 |

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
- **Temperature:** **constant, within 20–40 °C** — we have decided against a cycle for this programme, because a cycling temperature would be confounded with frequency and time, and those are exactly what the frequency bridge is there to separate. Quote a constant set-point of 30 °C (the middle of the range); state your control band, and whether a controlled temperature above ambient is possible in your fatigue cell. (A slow cycle within the same range stays available as a later option, not part of this programme.)
- **Dissolved oxygen:** in service the sap carries little oxygen, and a variable amount, so an air-saturated cell does not reproduce it — and neither does a de-aerated one, which reproduces only one end of that range. We therefore want it **logged, not controlled**: tell us whether you can log dissolved oxygen and at what interval. We are **not** ordering control by gas purging — please do not price it; if you believe the series cannot be interpreted without it, say so and we will reconsider.
- **Electrochemical potential:** in service the metal is part of an electrochemical cell, so its potential need not be the free-corrosion potential. We are **not buying a potentiostat in this first programme** — the service window is our own inference and not a measurement, and holding a bare specimen (it carries no enzyme layer) at a potential we inferred would reproduce our assumption rather than the service. So the specimens run at free corrosion, and we accept that the direction of the difference is unknown to us. Quote it only as a **later option on method A** — holding the specimen at a set potential during cycling (a potentiostat in the fatigue cell) — and tell us how the specimen is electrically isolated from grips and fixtures, and how a potential-drop crack-detection current, if you use one, would interact with it.
- **Medium upkeep and QC:** state the volume per specimen and the replacement schedule for long runs, logging pH (and oxygen, where logged) at every replacement; per batch, check pH with a calibrated meter, conductivity, the major ions, and that the batch carries **no precipitate** — right after preparation and again at the end of use. Include the records in the report.

### Test methods — please quote each as a delta on the base case

**General conditions.** Constant-amplitude axial loading — force-controlled on conventional machines; on ultrasonic machines, displacement-amplitude-controlled with the stress calibration stated. The stress ratio is **R = −1 for every series in this programme** — fully reversed axial loading, so that the conventional, ultrasonic and frequency-bridge series all sit on one curve. Tell us if your machines or the specimen geometry cannot hold R = −1 on any method, and what you would run instead; a second stress ratio is not part of this programme.

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

- **Stop criteria:** the primary criterion on **every** machine is a **stated drop in stiffness** — read as a shift in resonance frequency on ultrasonic and resonant systems, which is the same physical quantity — with separation recorded as a secondary event. We choose it because two machines' curves are comparable only when the criterion is the same at every point, because the function of our part is lost before separation, and because stopping before separation is what preserves the fracture surface. **Tell us the threshold you can detect reliably on each machine** — that number is yours to set, and we will fix one value across the programme from your answer. Record on every data point which criterion ended the test. The function of our part can be lost at crack initiation, before the specimen separates: tell us whether and how you can detect initiation, and at what crack size, as a priced option on a subset of specimens (for example three).
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
4. **Itemised prices, as deltas on the base case:** machine-channel time per method (A–H) · Phase 0 · cell set-up, and medium preparation and QC per batch · tensile witness per specimen · step-test specimens · roughness per series · SEM fractography per specimen · each option separately (initiation detection, potential control) · statistical planning, analysis and report · the pilot.
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

Nothing is required from us for an initial quotation. On request we supply the medium recipe with its preparation notes, the manufacturer's as-built design rules once we hold them, and the specimen requirements above as a drawing once you have proposed the geometry.

---

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (UA) — технічне завдання для установи НАН (втомні випробування)

> **Репо-нота (у лист НЕ йде).** Український маршрут того самого змісту, що EN-блок ↑, — для установ НАН, де предметом договору НДР ⊥ послуги є ТЗ, а не лист (§3). Форма — проєкт ТЗ, як [`anchor_hip_rfq`](anchor_hip_rfq.md) і ТЗ 1 [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md): звернення → мета → «це не замовлення» → нумероване ТЗ → конфіденційність → підпис. Адресати — ІЕЗ ім. Патона · ІПМіц ім. Писаренка ([`ua_vendor_map §6`](ua_vendor_map.md)); **один текст — окремими листами**, ТЗ іншого адресата не називає. **Предмет** — випробування (планування · машинний час · фрактографія · первинні дані), не зразки (п. 1). **Приймання** — повнота даних п. 39, отриманих за процедурами, узгодженими до випробувань; порогів придатності немає (сліпий аналіз §0 п.3; форма — ГІП-ТЗ п. 10). **Питання до виконавця** — усе, що EN подає як «confirmed before the order», тут «підтвердимо до замовлення».
> **Що додала оболонка, а не нова вимога:** форма співпраці й акти приймання-передачі (пп. 46–47, з ГІП-ТЗ пп. 17–18) · які маршрути виконавець робить сам, через партнера чи не робить (п. 40; ультразвукової VHCF в Україні не знайдено — [`ua_vendor_map §6`](ua_vendor_map.md)) · **режим доступу для безперервних прогонів** (п. 41; типове положення ЦКК НАН — 2 год/зміну для сторонніх, [`ua_vendor_map §4`](ua_vendor_map.md), а MTS 318.25 ІЕЗ заявлено саме в ЦКК, §3 ↑; урок ТЗ 1 coin-тесту) · документ акредитації кожного випробування «ДСТУ, ISO чи ASTM» (п. 43; у ФМІ втома акредитована лише за ГОСТ/ДСТУ). **Прибрано:** увесь перелік «Не йде в лист» плану §10 (як в EN) · Incoterms і експортний контроль — адресат вітчизняний (як ТЗ 1 coin-тесту).
> **Відкриті ⚖️ плану — питаннями, не рішеннями:** №10 статистика й `n` — обидві гілки, кількість на серію й на рівень «обґрунтуйте, наприклад за ISO 12107», вибір — за пропозицією виконавця (п. 35) · №13 тонкостінна серія — «розглядаємо, але ще не вирішили», здійсненність і потрібний `R` (п. 6). Орієнтація — рівно ⚖️ 2026-09-18: виробничий стан у двох, решта — «в одній», без того, в якій саме.
> ⚠️ **Написано 2026-09-23, founder тексту ще не бачив** — ⛔ до його «так» не надсилати. 🔴 **Найслабша ланка:** якщо ультразвукову половину візьме інший виконавець, частотний міст D розпадеться між двома лабораторіями, а він чинний лише на спільній геометрії (план §5.3 D) — тоді п. 21 доведеться узгоджувати з обома до замовлення.

### Звідки кожен розділ ТЗ — і де він свідомо відходить від EN-блоку

| Пункти ТЗ | Джерело | Відносно EN-блоку |
|---|---|---|
| вступ · п. 1 предмет | EN Scope ← план §0 · §1.1 · §5.1; «через нас» — §0 п.3 | «предмет робіт» — окремим пунктом, бо ТЗ і є предметом договору |
| п. 2 базовий варіант | EN Base case ← план §10 п.8 · §4.2 п.4 (№2) | те саме — pH-точка 5,75 (рецептура — точка, ⚖️ 2026-09-17, план §7) |
| пп. 3–8 зразки · серії · свідки | EN Specimens ← план §2.1–§2.2 · §3.1–§3.2 · §9.1 №15 | те саме — «два-три» стани в соку + опції «до двох» (план §9.1 №4: ΔHIP став опційним діагностичним, лише прочитання (i); обовʼязкові — Δbake (1, або 2 на обох температурах) + Δповерхня (1); опційні — ΔHIP (i) і ΔEAAE, план §2.2) |
| п. 9 програма й таблиця | EN «Which of these we intend to buy» ← план §5.3 · §6.2 · §9.1 №1 | рядок опції — «до двох станів» |
| пп. 10–16 середовище | EN Test medium ← план §7 · §9.1 №8 → рецепт [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | те саме |
| пп. 17–26 маршрути · база | EN Test methods ← план §5.3 · §6.2 | те саме — другий `R` у програму не входить (№2); `R` тонкого зразка питає п. 6 |
| пп. 27–31 рівні | EN Stress levels ← план §4.2 | те саме |
| пп. 32–34 зупинка · злами · фрактографія | EN Stop criteria ← план §6.1 · §9.1 №9 | те саме |
| пп. 35–37 статистика | EN Statistics ← план §6.3 · §9 №10 (відкрите) | обидві гілки названо явно · «обґрунтуйте» · кількість і «на рівень» (план §6.3) |
| п. 38 етапи | EN Programme phases ← план §2.5 | те саме |
| п. 39 дані | EN Data ← план §10 п.6 | + «звіт, а не перевірка на відповідність» |
| пп. 40–47 що надати · форма · приймання | EN What we ask · Commercial ← план §10 пп. 1–2 · 7 | те саме (кисень — журнал, не контроль, тож у цінах його немає — №8) + маршрути сам ⊥ партнер ⊥ ні · режим доступу · документ акредитації · форма й акти |
| конфіденційність · продовження · додатки | EN ← план §2.3 · §8 | без Incoterms і експортного контролю |

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо осьових втомних випробувань (крива S-N) надрукованих зразків Ti-6Al-4V у синтетичному ксилемному соку, з гігацикловими варіантами, фрактографією й статистичним плануванням — проєкт технічного завдання для узгодження (дослідна програма)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо титановий анкер, який встановлюється в стовбур живого дерева, має простояти там близько двадцяти років і весь цей час зазнає згину від гойдання стовбура під вітром — за строк служби до порядку 10⁹ циклів навантаження; саму частоту служби ми ще уточнюємо. Перш ніж покладатися на надрукований метал у такій службі, ми хочемо виміряти його криву втоми — залежність амплітуди напруження від числа циклів до руйнування разом із розкидом — на гладких зразках, що несуть стан матеріалу деталі (той самий маршрут друку, та сама термічна й та сама поверхнева обробка), і в середовищі, змодельованому на ксилемному соку дерева, а не в типовому буфері.

Це запит інформації та пропозиції, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону. Частину параметрів ми ще фіксуємо — їх позначено нижче словами **«підтвердимо до замовлення»**. Щоб пропозиція не перетворилася на прейскурант, просимо **спершу оцінити один базовий варіант вашого власного планування** (п. 2), а кожну іншу позицію — як відхилення від нього. Ваша відповідь щодо маршрутів випробувань — також вхід для того, як ми вибудуємо послідовність програми, тому питаємо зараз. Якщо проєктування зразка й планування випробувань для вас є окремою платною роботою, оцініть їх як **етап 0** (п. 38). Режими, яких ми не фіксуємо, подано як питання — просимо відповідати своїми даними, а не підганяти їх під наш текст. Відповідати можна просто в тексті листа.

Ми свідомо не надсилаємо ні оцінки втомної міцності, ні прогнозів наших моделей: рівні напружень і класифікація місць зародження тріщин мають іти за процедурами, узгодженими до випробувань, а не за очікуваним результатом. Відомості про обробку кожної серії, потрібні для поводження зі зразками й фрактографії, узгоджуються на стадії замовлення.

**Проєкт технічного завдання**

*1. Предмет робіт*

1. **Предмет робіт — випробування:** планування, машинний час, фрактографія й простежувані первинні дані. Зразки постачаємо ми (пп. 3–8): вони надійдуть до вас через нас, а виробника, який їх друкує, підтвердимо до замовлення.

*2. Базовий варіант — просимо оцінити першим*

2. Одна серія — **виробничий стан, випробуваний у синтетичному соку**, — маршрутом A на частоті, яку запропонуєте ви; **симетричний цикл, R = −1** (цей коефіцієнт асиметрії чинний для всіх серій цієї програми, а не лише для оцінки); база випробувань **10⁷ циклів**; одна стала температура в межах, наведених у п. 13, і pH 5,75; рекомендована вами кількість зразків для медіанної кривої втоми з методом «сходинок» (staircase) на базі; свідки на розтяг (п. 8); фрактографія кожного зруйнованого зразка на растровому електронному мікроскопі (SEM); звіт. Назвіть машинний час, який займає базовий варіант. Кожну іншу серію, маршрут, базу й опцію оцініть як відхилення від нього.

*3. Зразки (що ми постачаємо)*

3. **Сплав:** Ti-6Al-4V (ASTM F2924, лазерне сплавлення в порошковому шарі). Згодом може додатися другий сплав — на основі титану або тантал, ще не обраний (див. «Можливе продовження»).
4. **Маршрут виготовлення:** ми плануємо, що зразки надрукує й обробить виробник нашої деталі — тим самим маршрутом, що й деталь, включно з її термічною й поверхневою обробкою, — щоб крива описувала саме цей маршрут, а не типовий. Ми маємо намір дати кожному зразку ідентифікатор і записати до нього побудову, позицію на платформі, орієнтацію побудови й партію порошку; допуски друку, мінімальні розміри елементів і правила підтримок виробника передамо, щойно їх отримаємо.
5. **Тип:** гладкі зразки для осьового навантаження, без навмисних концентраторів напружень. Для звичайної машини ми маємо намір **друкувати робочу частину більшості серій у розмір і не обробляти її механічно** (підтвердимо до замовлення): стінки ґратки деталі обробити неможливо, тож її поверхня лишається в стані після друку з подальшою хімічною обробкою; захватні частини (головки) обробляти механічно можна. Для ультразвукової машини потрібна резонансна геометрія — скажіть, чи її довелося б обробляти, і запропонуйте її.
6. **Просимо запропонувати геометрію зразка** для кожної машини, яку ви застосуєте, і сказати:
   - як ви рахуватимете напруження на шорсткій робочій частині в стані після друку — ми просимо **обидва** значення, на номінальному й на виміряному мінімальному перерізі, — і як ви вимірюєте мінімальний переріз (наприклад, компʼютерною томографією);
   - **найменший переріз робочої частини, який ви можете надійно випробувати**, з діапазоном навантаження й перевіркою співвісності, яких він потребує (наприклад, за ASTM E1012). Перемички ґратки деталі тонші за 1 мм, і серію з тонким перерізом ми **розглядаємо, але ще не вирішили**: скажіть, чи вона здійсненна на ваших машинах і за якого коефіцієнта асиметрії циклу, — за R = −1 тонкий зразок може втратити стійкість; якщо здійсненна, оцініть її окремо;
   - чи можна провести звичайне й ультразвукове випробування на **одній** геометрії зразка (п. 21);
   - ваш вхідний контроль, скільки запасних зразків на серію ви хотіли б мати і як ви трактуєте руйнування поза робочою частиною — наприклад, на переході від робочої частини в стані після друку до механічно обробленої головки: як недійсне випробування, і за чий рахунок.
7. **Серії.** Кожна серія — окрема крива втоми. Усі серії — з того самого сплаву; вони різняться післядруковою обробкою, станом робочої частини, орієнтацією побудови або середовищем випробування:
   - **виробничий стан, випробуваний у синтетичному соку**, — у **двох орієнтаціях побудови** (вісь зразка паралельна й перпендикулярна напрямку побудови); ціна — за кожну орієнтацію;
   - **ще два-три стани, випробувані в синтетичному соку** (перелік підтвердимо до замовлення), — усі з робочою частиною в стані після друку, крім одного, з механічно обробленою; ціна — за серію;
   - **виробничий стан, випробуваний на повітрі лабораторії**, — на машині того самого типу й на тій самій частоті, що й у соку;
   - *опція:* ще до двох станів, випробуваних у синтетичному соку; ціна — за кожен.
8. **Свідки з тієї самої побудови — на кожну серію** (на кожну побудову, якщо серія охоплює кілька): зразки на розтяг (границя текучості, границя міцності, відносне видовження) — ціна за зразок; і шорсткість робочої частини кожної серії — названими параметрами разом із приладом, включно з **параметром западин** (наприклад, Sv, Sz чи Rv) поряд із середнім.

*4. Програма: які серії якими маршрутами*

9. **Що ми маємо намір замовити — щоб пропозиція була планом, а не прейскурантом.** Нашу програму визначено: однофакторні серії-відхилення йдуть **маршрутом A в синтетичному соку з базою 10⁷** — вони вимірюють *різницю* між станами, тож пласка межа понад 10⁷ на них не впливає; а **виробничий стан додатково йде до 10⁹** (маршрутом B або C — тим, який ваша спроможність робить обґрунтованим) **плюс частотний міст D**. Причини: 10⁹ — єдиний із запитаних рівнів, що покриває наведену вище службову експозицію, яка в нас до одного числа не звужується; а знак частотного ефекту на поверхні в стані після друку невідомий, тож міст його вимірює, а не припускає. Маршрути **E, F, G і H лишаються в таблиці як оцінені альтернативи**: ми просимо їхню ціну, щоб мати шлях, якщо ви скажете, що намічений маршрут на ваших машинах не обґрунтований. Коефіцієнт асиметрії — R = −1 для всіх серій.

| Серія | Маршрут | Середовище | База, циклів | Етап |
|---|---|---|---|---|
| Виробничий стан (дві орієнтації побудови) | A | синтетичний сік | 10⁷ | 1–2 |
| Інші стани (два-три) | A | синтетичний сік | 10⁷ | 3 |
| Виробничий стан | A | повітря лабораторії | 10⁷ | 3 |
| Виробничий стан — гігациклове продовження | B · C · D · G | повітря (B, D) · сік (C, G) | 10⁸ · 10⁹ | 4 |
| Виробничий стан — залежність від часу в середовищі | E · F · H | синтетичний сік | див. кожен маршрут | 4 |
| Опція: до двох інших станів | A | синтетичний сік | 10⁷ | 3 |

*5. Середовище*

10. **Синтетичний ксилемний сік**, цільовий вид — сосна звичайна (*Pinus sylvestris*). Робочий склад:

| Компонент | Концентрація |
|---|---|
| Яблучна кислота | 2,2 мМ |
| KNO₃ | 3,2 мМ |
| CaCl₂ | 1,0 мМ |
| MgSO₄ | 0,45 мМ |
| KOH | до уставки pH — записувати кількість на кожну партію |

11. **pH: 5,75.** Доданої буферної системи немає — єдиний буфер яблучна кислота, а pH задає KOH, — тож середовище слабко буферне: невелика кількість кислоти помітно зсуває pH. Опишіть, як ви задаєте, утримуєте й реєструєте pH у прогонах тривалістю від днів до місяців. Осад на зразку змінив би і середовище, і поверхню, що випробовується, тож перевіряйте, що його немає (п. 16). Ціна приготування середовища — за партію.
12. **Цукру** в середовищі **немає**, але малат сам є джерелом вуглецю, тож багатотижневі прогони все одно можуть підтримувати мікробний ріст — скажіть, як ви його контролюватимете. **Не додавайте консервантів, біоцидів чи інгібіторів** без узгодження з нами: будь-яка добавка змінює корозійну хімію, яку ми випробовуємо.
13. **Температура — стала, в межах 20–40 °C.** Від циклу температури в цій програмі ми свідомо відмовилися: змінна температура змішалася б із частотою й часом, а саме їх має розвести частотний міст. Оцініть сталу уставку 30 °C (середина смуги); назвіть смугу регулювання і скажіть, чи можливе у вашій втомній комірці регулювання температури вище кімнатної. (Повільний цикл у тих самих межах лишається можливою пізнішою опцією, поза цією програмою.)
14. **Розчинений кисень:** у службі сік несе мало кисню, і його кількість змінюється, тож комірка, насичена повітрям, службу не відтворює — як і деаерована, що відтворює лише один край цього діапазону. Тому ми хочемо його **реєструвати, а не регулювати**: скажіть, чи можете реєструвати розчинений кисень і з яким інтервалом. Регулювання продуванням газу ми **не замовляємо** — не оцінюйте його; якщо вважаєте, що без нього серії неможливо інтерпретувати, скажіть — ми переглянемо.
15. **Електрохімічний потенціал:** у службі метал є частиною електрохімічної комірки, тож його потенціал не обовʼязково дорівнює потенціалу вільної корозії. **Потенціостата в цій першій програмі ми не замовляємо**: робоче вікно потенціалів — наш висновок, а не вимірювання, а утримання голого зразка (ферментного шару він не несе) при потенціалі, який ми вивели, відтворило б наше припущення, а не службу. Тож зразки випробовуються при вільній корозії, і ми визнаємо, що напрямок цієї різниці нам невідомий. Оцініть потенціостат лише як **пізнішу опцію на маршруті A** — утримання зразка при заданому потенціалі під час циклування (потенціостат у втомній комірці) — і скажіть, як зразок електрично ізолюється від захватів і оснащення та як із ним взаємодіяв би струм методу падіння потенціалу для виявлення тріщини, якщо ви такий метод застосовуєте.
16. **Підтримання середовища й контроль якості:** назвіть обʼєм на зразок і графік заміни для довгих прогонів, із реєстрацією pH (і кисню, де він реєструється) при кожній заміні; для кожної партії — pH каліброваним приладом, електропровідність, основні іони й **відсутність осаду** — одразу після приготування й ще раз наприкінці використання. Додайте записи до звіту.

*6. Маршрути випробувань — кожен оцінити як відхилення від базового варіанта*

17. **Загальні умови.** Осьове навантаження зі сталою амплітудою — з керуванням за силою на звичайних машинах; на ультразвукових — з керуванням за амплітудою переміщення, із зазначеним калібруванням напруження. Коефіцієнт асиметрії — **R = −1 для всіх серій цієї програми**: симетричний осьовий цикл розтягу-стиску, щоб серії звичайних машин, ультразвукових і частотного мосту лягли на одну криву. Скажіть, якщо ваші машини чи геометрія зразка не можуть тримати R = −1 на якомусь маршруті, і що ви запропонували б натомість; другий коефіцієнт асиметрії до цієї програми не входить.
18. **A. Звичайна осьова машина, до 10⁷ циклів** — у синтетичному соку, а для серії на повітрі — на повітрі лабораторії. Назвіть діапазон частот, доступний вам у кожному середовищі (частоту випробування підтвердимо до замовлення), кількість доступних каналів, тип комірки (занурення чи протік) і машинний час на зразок.
19. **B. Ультразвукові втомні випробування (близько 20 кГц) на повітрі лабораторії, до 10⁹ циклів.** Назвіть спосіб охолодження й режим «імпульс–пауза», ефективний час випробування одного зразка і як ви калібруєте напруження в зразку.
20. **C. Ультразвукові втомні випробування в синтетичному соку, до 10⁹ циклів** — чи це можливо взагалі й якою ціною розробки. Якщо так: як рідина утримується на робочій частині (у вузлі зміщення) і не потрапляє на кінці зразка, де вона перетворила б випробування на кавітаційну ерозію; як ви не допускаєте нагрівання й дегазації рідини; як реєструєте її температуру й розчинений кисень. 10⁹ циклів при 20 кГц — це менше доби навантаження проти років служби, тож цей маршрут у середовищі, дія якого залежить від часу, ми читатимемо обережно.
21. **D. Частотний міст.** Виробничий стан на тому самому рівні напруження й у тому самому середовищі на двох машинах, чиї діапазони циклів перекриваються (до 10⁷ циклів), — на повітрі лабораторії (звичайна машина проти ультразвукової), а також у синтетичному соку, якщо можливий маршрут C. Опубліковані результати розходяться: огляд повідомляє, що титанові сплави до частоти випробування нечутливі, тоді як дослідження одного Ti-6Al-4V показало ефект для зародження тріщини на поверхні гладких зразків, — а наша робоча частина в стані після друку визначається саме поверхнею, тож ми просимо ціну вимірювання цього ефекту замість того, щоб припускати будь-яку з відповідей. Скажіть, чи можна виконати міст на одній геометрії зразка; якщо потрібні дві — назвіть найбільш навантажений обʼєм і поверхню кожної, інакше масштабний ефект прочитається як частотний. Назвіть кількість зразків на кожну частоту, потрібну, щоб розрізнити, наприклад, дворазову різницю в довговічності.
22. **E. Тривала статична витримка в синтетичному соку, а потім втома** — наприклад, кілька тижнів занурення перед циклуванням. Скажіть, наскільки це практично для вас.
23. **F. Низькочастотне циклування в синтетичному соку** — на низькій частоті порядку 1 Гц, яку підтвердимо до замовлення: машинний час на зразок до 10⁶ і до 10⁷ циклів і ціна за машино-місяць.
24. **G. Резонансна машина в синтетичному соку, до 10⁸ циклів** — порядку 100 Гц, якщо маєте таку з коміркою: проміжний маршрут між A й ультразвуковими.
25. **H. Дві звичайні частоти в синтетичному соку** — та сама серія й той самий рівень напруження на частоті маршруту A і на низькій частоті, як у F, щоб показати, чи важить у середовищі час, що припадає на один цикл.
26. **База випробувань.** Оцініть бази **10⁷, 10⁸ і 10⁹ циклів** для кожного маршруту, де вони практичні, з машинним часом, якого кожна потребує. Скажіть, що ви робите зі зразками, які не зруйнувалися до бази (наприклад, повторне випробування на вищому рівні), і як їх звітуєте.

*7. Рівні напружень*

27. **Якір рівнів кожної серії — виміряні властивості на розтяг свідків цієї серії з тієї самої побудови.** Результати розтягу потрібні нам до того, як буде встановлено втомні рівні.
28. *Опція:* **два-три зразки на серію для ступінчастого пошуку стартового рівня** (step-test) — там, де самі лише властивості на розтяг могли б поставити старт далеко від медіани.
29. **Рівні скінченної довговічності**, щоб зафіксувати нахил кривої, плюс **метод «сходинок» (staircase) або пробіт-метод** для втомної міцності на обраній базі. Запропонуйте кількість рівнів, крок і метод.
30. **Переякорення на кожну серію.** Серії можуть різнитися, тож одна спільна сітка рівнів могла б витратити зразки серії на незруйновані до бази або на миттєве руйнування.
31. Процедуру рівнів **узгоджуємо до випробувань і виконуємо як узгоджено** — на основі даних, які надаємо ми.

*8. Критерій зупинки, злами, фрактографія*

32. **Критерій зупинки:** первинний критерій на **кожній** машині — **задане падіння жорсткості** (на ультразвукових і резонансних системах воно читається як зсув резонансної частоти — це та сама фізична величина); розділення зразка записується як вторинна подія. Ми обираємо його тому, що криві двох машин порівнянні лише за однакового критерію в кожній точці, тому, що функція нашої деталі втрачається раніше за розділення, і тому, що зупинка до розділення зберігає злам. **Назвіть поріг, який ви надійно фіксуєте на кожній машині**, — це число встановлюєте ви, а ми за вашою відповіддю зафіксуємо одне значення на всю програму. Для кожної точки даних записуйте, який критерій завершив випробування. Функцію нашої деталі може бути втрачено вже на зародженні тріщини, до розділення зразка: скажіть, чи й як ви можете виявити зародження і за якого розміру тріщини, — як оцінену опцію на підмножині зразків (наприклад, трьох).
33. **Злами:** скажіть, як ви їх зберігаєте — де можливо, зупиняючи випробування до розділення й доламуючи зразок, а зразки, випробувані в соку, промиваючи й висушуючи протягом доби після руйнування. За R = −1 береги тріщини можуть стерти місце зародження.
34. **Фрактографія:** **SEM-фрактографія кожного зруйнованого зразка** з класифікацією місця зародження тріщини для кожного зразка (наприклад, на поверхні, на приповерхневій порі чи дефекті, або всередині), кількістю осередків зародження й знімками — ціна за зразок. **Критерії класифікації узгоджуємо до випробувань.**

*9. Статистика й кількість зразків*

35. **Кількості зразків ми не задаємо, і який вид кривої замовимо, ще не вирішили.** Просимо оцінити обидва варіанти й обґрунтувати кількість зразків на серію й на рівень (наприклад, за ISO 12107): **(а) медіанна крива втоми**; **(б) імовірнісна крива (P-S-N)** при імовірності руйнування p і односторонній довірчій імовірності γ — для двох прикладів пар, наприклад p = 10 % при γ = 90 % і p = 1 % при γ = 95 %. Варіант і нашу пару підтвердимо до замовлення, за вашою пропозицією.
36. Скажіть, як ваш аналіз трактує зразки однієї серії, у яких тріщини зароджуються за **різними механізмами** (наприклад, на поверхні й усередині), — як одну сукупність чи як окремі.
37. Назвіть стандарти, за якими працюєте, з їхніми виданнями: осьовий метод (ASTM E466 або ISO 1099), статистичне планування й аналіз (ISO 12107, ASTM E739), перевірка співвісності (ASTM E1012), корозійна втома (наприклад, ISO 11782-1 або ASTM F1801 — наше середовище тоді є задекларованим відхиленням), а також практику ультразвукових випробувань, якщо маєте, — і скажіть, яких із наведених вище випробувань не охоплює жоден із ваших стандартів.

*10. Етапи робіт — оцінити окремо*

38. Етапи:
   - **етап 0**, якщо проєктування зразка й планування для вас — окрема платна робота: геометрія зразка, перевірка співвісності на макетних зразках, прогін середовища без зразків, узгоджені матриця випробувань і процедури (рівні, критерії зупинки, класифікація місць зародження);
   - **етап 1 — пілотний** на виробничому стані (обсяг запропонуйте): свідки на розтяг, перші втомні точки та їхня фрактографія — до повної програми;
   - **етап 2 — виробничий стан у соку** (дві орієнтації побудови), з фрактографією;
   - **етап 3 — інші серії** (в одній орієнтації побудови), включно із серією на повітрі;
   - **етап 4 — продовження** маршрутами, які ми оберемо після вашої пропозиції: скажіть, які з B–D та E–H ви рекомендуєте і чому.

*11. Дані, які потрібно повернути*

39. Це звіт, а не перевірка на відповідність: порогів придатності ми не задаємо. Самих підігнаних кривих недостатньо — ми можемо переаналізувати первинні точки іншою статистичною моделлю й використати їх як вхід для власних моделей.
   - **Кожна точка даних:** ідентифікатор зразка (разом із побудовою, позицією на платформі й орієнтацією, що надійдуть із ним), серія, амплітуда напруження на номінальному й на виміряному мінімальному перерізі, середнє напруження (або R), частота, число циклів, критерій зупинки, позначка «не зруйнувався до бази», початок і кінець випробування, журнали середовища — температура, pH, розчинений кисень і потенціал, де застосовно.
   - **Файли машини у власному форматі й відкритий експорт** (CSV або ASCII) для кожного зразка — історія сили, переміщення чи жорсткості, а для ультразвукових випробувань — історія резонансної частоти, — із частотою дискретизації запису.
   - **Первинні криві розтягу свідків** і дані шорсткості з параметрами й приладом.
   - **Фрактографічні знімки** кожного зруйнованого зразка з класифікацією місця зародження, **журнал відхилень** і кожне недійсне випробування з причиною.
   - **Статистичний аналіз разом із вхідними даними** — первинні точки, ніколи не лише підігнані криві. Скажіть, чи повертаєте випробувані зразки із захищеними зламами.

*12. Що просимо надати*

40. **Спроможність:** осьові машини (тип, діапазон навантаження й повірений діапазон їхніх датчиків сили, діапазон частот, кількість каналів), резонансні й ультразвукові втомні системи, комірки для корозійної втоми (занурення чи протік, регулювання температури, реєстрація pH і кисню, потенціостат), SEM, випробування на розтяг і вимірювання шорсткості. Для кожного маршруту A–H скажіть, чи виконуєте його **самі, через партнера** (назвіть якого) **чи не виконуєте** — остання відповідь для нас теж корисна.
41. **Режим доступу:** випробування одного зразка до бази йде безперервно — скажіть, чи дозволяє ваш порядок роботи зі сторонніми замовниками **безперервну роботу машини впродовж усього випробування** (без зупинок на ніч і між змінами, зокрема якщо обладнання працює в режимі центру колективного користування) і скільки такого машинного часу ви можете виділити одночасно.
42. **Порівнянні роботи:** втома адитивно виготовленого титану, корозійна втома, гігациклова втома (знеособлені приклади годяться).
43. **Акредитація й система якості** — номер свідоцтва, орган, сфера й строк дії: ISO/IEC 17025 і ISO 9001 — що маєте. **По кожному випробуванню, а не по лабораторії:** який пункт сфери акредитації (свідоцтво й методика — ДСТУ, ISO чи ASTM) охоплює кожне випробування вище, які випробування виконувалися б поза сферою акредитації і чи входять титанові сплави в обʼєкт цієї сфери.
44. **Постатейні ціни як відхилення від базового варіанта:** машинний час за маршрутом (A–H) · етап 0 · налаштування комірки, приготування й контроль середовища за партію · свідок на розтяг за зразок · зразки для ступінчастого пошуку · шорсткість за серію · SEM-фрактографія за зразок · кожна опція окремо (виявлення зародження, пізніша опція потенціостата) · статистичне планування, аналіз і звіт · пілотний етап.
45. **Строки:** черга до початку, тривалість кожного етапу, звіт.
46. **Форма співпраці:** на якій підставі ви виконуєте роботи для сторонніх організацій — договір на науково-дослідну роботу, договір про надання послуг чи інше; які документи потрібні від нас (реквізити, лист-запит, технічне завдання в узгодженій формі); форма оплати, строк чинності пропозиції й контактна особа з технічних питань.
47. **Приймання й повернення:** зразки надійдуть від нас, а не напряму від виробника — назвіть ваші вимоги до приймання, пакування й маркування і скажіть, чи оформлюєте акт приймання-передачі з переліком ідентифікаторів — при прийманні й при поверненні. Скажіть також, чи готуєте середовище за нашою рецептурою (так нам зручніше), чи потребуєте, щоб ми його постачали.

**Конфіденційність і публікація.** Технічна специфікація відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну взаємну угоду щодо комерційних умов (ціни, строки, дані контролю якості). Результати ми можемо опублікувати — повідомте, будь ласка, чи маєте умови щодо публікації даних, отриманих для нас, наприклад згадку установи, опис методу чи перегляд тексту, що вас називає.

**Можливе продовження (не входить у цю пропозицію).** Та сама програма або її частина для виробничого стану — на другому сплаві, щойно його оберемо; втома зварного зʼєднання холоднотягнутого титанового дроту з надрукованою титановою деталлю; втома ґратчастих (гіроїдних) зразків. Якщо щось із цього у вашій сфері — скажіть, і ми надішлемо окремий запит.

**Додатки.** Для первинної пропозиції від нас нічого не потрібно. На запит надамо рецептуру середовища з примітками щодо приготування, правила друку виробника, щойно їх отримаємо, і вимоги до зразка кресленням, щойно ви запропонуєте геометрію.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 4. Cross-references

| Ресурс | Що бере |
|---|---|
| [`sn_fatigue_test_plan`](../anchor/sn_fatigue_test_plan.md) | дім змісту: серії, рівні, маршрути A–F, критерії, статистика, відкриті ⚖️ §9 |
| [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | рецепт синтетичного соку (дім) · частота: польова — дужка іменованих прочитань, 1–5 Гц — смуга СТЕНДА |
| [`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §1.7`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | маршрут процесу деталі, який повторює зразок · HIP |
| [`01_01 §1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_03 §2.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | мало й непостійно O₂ у ксилемі · метал як струмозбирач анода (звідки опція потенціалу) |
| [`vendor_templates`](vendor_templates.md) §Processing п.16 | зразки питанням у DMLS-листі; пп. 2–4 на серії не поширюються |
| [`anchor_coin_electrochem_rfq`](anchor_coin_electrochem_rfq.md) | взірець листа · та сама таблиця середовища · ТЗ 1 — прецедент UA-оболонки (режим доступу ЦКК) |
| [`anchor_hip_rfq`](anchor_hip_rfq.md) · [`ua_vendor_map §4`](ua_vendor_map.md) · [`ua_vendor_map §6`](ua_vendor_map.md) | форма UA-ТЗ під договір НДР ⊥ послугу · режим доступу ЦКК · адресати UA-ТЗ і відсутність VHCF в Україні |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс · §3 IP/CDA · §4.B |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.23 · HW.24 · HW.27 | дім стану · делегований сліпий аналіз · плече Δbake |
