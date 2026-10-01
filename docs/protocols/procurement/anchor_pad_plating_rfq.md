# Anchor — золочення контактних площадок (тверде золото по титану): лист гальванікові

> **Що це:** RFQ-аркуш для **гальванічного цеху** — селективне тверде золото на дві контактні плями анкера: торець дроту шини Ø1.0 (центральна площадка, V−) і кільцева pogo-зона на грані катодного фланця (V+). **Лист ПИТАЄ маршрут, а не диктує його:** канон несе функційну ВИМОГУ, маршрут обирає гальванік (⚖️ 2026-09-22, дім — [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)).
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-23, не надіслано, founder тексту ще не бачив; адресата не обрано** — кандидати з другого desk-проходу 2026-09-28: SIFCO ASC (тепер SIFCO Process; FR · SE · UK) · Mersi (Відень) · «Гальванік-Декор» (Харків, маршрут «Ni по Ti → Au» питати); сторінки вендорів звірено власним запитом 2026-10-01 — [`ua_vendor_map §5`](ua_vendor_map.md). Числа — дзеркало канону, дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8 (нога 8.2).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Анкер hardware» · hard-constraint дім §4.B/§4.C).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — специфікація відкрита; CDA = стандартні комерц-умови.

---

## 0. Як користуватись + cover-note

1. **Окремий аркуш, бо адресат інший:** не друк-бюро (DMLS-лист про золото мовчить і лише питає, чи можна замаскувати дріт від травлення — [`vendor_templates`](vendor_templates.md) §Processing п.9(c)) і не постачальник піна (його фініш — купована властивість, [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)). Предмет — послуга покриття двох плям на НАШИХ деталях.
2. **Базовий кейс + дельти, не прайс на все:** базовий — Ti-6Al-4V, окремі деталі до складання, одна партія на обидві плями; сплави-кандидати, стан поверхні (протравлена ⊥ замаскована) і складений виріб — дельтами. Так лист лишається чинним за будь-якого з відкритих §2.
3. **Форма й мова вирішені ДО тексту** (скіл `legal-business` §Доменні правила #6): адресат — комерційний цех, тож **лист українською, не ТЗ**. ⚠️ Якщо адресатом стане установа НАН (найближче названий носій — ІЕЗ ім. Патона, і це PVD, тобто інша фізика, ніж гальваніка), оболонку переробити на ТЗ під договір НДР за зразком [`anchor_hip_rfq`](anchor_hip_rfq.md) — зміст той самий. **EN-версія — §📤 (EN) нижче (2026-09-29)**: за цим же правилом вона пишеться, коли з'являється адресат у ЄС, а два ЄС-кандидати з'явились 2026-09-28 (SIFCO · Mersi); мапа §1 спільна для обох мов.
4. **Перше змістовне питання листа (п. 12) перевіряє найслабшу ланку самого присуду:** розбір «ENIG ⊥ hard gold» стоїть на **скоупі** двох стандартів (IPC-4552 · ASTM B488), а не на куплених текстах — [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md). Лист просить підтвердити або виправити, а не повідомляє висновок.
5. **Відповідь у репо не комітиться** — ціни, внутрішні режими й номери документів є чужими операційними фактами. Сюди й у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8 іде лише наш висновок.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **1 центральна площадка** | [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (дріт Ø1.0, «Термінус»: торець і є площадкою) · [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (PEEK-кільце Ø ≥ 4.0, ⚖️ 2026-09-18) · [`01_01 §3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) крок 4a (торець урівень із гранню) | фактом | лайнер 0.15 · канал Ø1.35 · закриття каналу на виході (елемента в дереві ще немає, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.34) — гальванікові не потрібні |
| **2 кільцева площадка** | [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (фланець Ø29.8, корінь 2026-09-30) | радіус і ширина — питанням: залежать від P/N піна HW.9 | «Ø4–5» (мертвий концепт) · «ø 2.5» (друкована площадка ПЛАТИ під пін, [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) |
| **3 один маршрут** | [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) Mandatory fix («тим самим кроком») | вимогою | — |
| **4 матеріал** | [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) («сплав = сплав анода») · [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (шість кандидатів; правило (в) для фланця) | базовий 4V + п'ять дельт; тантал окремо — інша хімія активації | наш down-select і його критерії |
| **5 поверхні без золота** | [`01_02 §3.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (карта) · вимога (г) [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | вимогою | ZnO-Ta (PEO) на сорочці фланця — інший виконавець, інший крок |
| **6 функція** | [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (ΔE ≈ 0.2 В, дрейф Rc) · вимога (а) · [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) («стик Ti↔Au під покриттям лишається») | чесно: пара виноситься з поверхні контакту, а не зникає — звідси адгезія й пористість | числа дрейфу (< 50 → > 500 мОм за 18–36 міс) — «в рази» · cold-start |
| **7 контакт** | вимога (б) · [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (≈140 зʼєднань) · [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (сила) | «до ≈ 1 Н» (0.96 Н spec ⊥ 60 ± 20 г даташита — HW.43) · «порядку сотні» («~7/рік» дому не має) · мікрорух без амплітуди | ⛔ **числа 0.76 / 1.27 мкм — специфікація ПІНА, для площадки не цитуються** (⚖️ 2026-09-22) — навіть як фініш контрпартнера, бо цех перенесе їх буквально |
| **8 електрично** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (500 мкА · > 500 мВ · Rc < 50 мОм) | вимогою | — |
| **9 середовище й строк** | [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (5.75 · бічна 4.5) · [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (−40…+85 °C) · вимога (в) (20 років) | фактом | провенанс pH (Tarvainen 2023) |
| **10 знезараження** | [`01_04 §6.3`](../../01_04_CODIT_and_Xylemointegration.md) ГІЛКА A (A1 · A2 · A4 · зберігання) | фактом; верхня межа дози — «ще не задано» | ферменти й причина низької дози |
| **11 маршрут** | [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) ⛔ «чого канон НЕ називає свідомо» | питанням — підшар · активація · тип золота · товщини | будь-яка НАША товщина |
| **12 прочитання норм** | [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) підстави 1–2 + найслабша ланка | «підтвердіть або виправте» | «8–15 × тонше» (наш висновок) · номер IPC-4552 — лише «фініш друкованих плат, ENIG» |
| **13 стан поверхні** | [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) ⚠️ («котрий маршрут торця — питання до гальваніка») · [`01_02 §1.7`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) / [`01_02 §6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (під час EAAE масковано) | ОБИДВІ гілки | назва EAAE — описово «кислотне травлення з ультразвуком» |
| **14 маскування** | вимога (г) · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8.2 (specмапа — разом із маршрутом, не раніше) | питанням | ⛔ specмапа маскування до листа НЕ додається |
| **15 місце в послідовності** | [`01_01 §3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) п.3(c) (кільце — крок фланця; торець — деталь Zone 1) · [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) («тим самим кроком») | базовий — окремі деталі до складання; складений виріб — дельтою | — |
| **16 водень і нагрів** | [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) Failure Mode C (R1: «золочення площадок — потенційне нове джерело водню», свідка немає) · [`01_01 §3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (bake після гарячої посадки заборонено, ⚖️ 2026-09-17) | питанням | числа bake і розкриття втулки |
| **17 контроль** | — (методів канон не задає) | питанням | — |
| **20–21 обсяг** | [`01_01 §6.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (Stage 3: 3–5 анкерів) · [`01_02 §6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (перша партія — 100) | базовий кейс + ціна-орієнтир | — |

---

## 2. Відкрите, яке лист обходить питанням (присуд — не тут)

| Відкрите | Як лист лишається чинним | Дім присуду |
|---|---|---|
| маршрут площадки (підшар · активація Ti · тип твердого золота · товщини) | питає, не диктує (пп. 11–12) | ⚖️ 2026-09-22 [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) — обирає гальванік |
| торець протравлений під золото ⊥ замаскований від травлення | обидві гілки (п. 13) | [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) ⚠️ · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8 |
| сплав дроту й анода | базовий 4V + п'ять кандидатів (п. 4) | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.24 · [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) |
| сплав фланця | «Ti-6Al-4V або безванадієвий» (п. 4) | правило (в) [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md), застосування гейтоване coin-даними |
| геометрія площини площадки (радіус і ширина pogo-кільця · закриття каналу) | розміри — кресленням (п. 2) | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9 → HW.34 |
| сила піна (98 г ⊥ 60 ± 20 г) | «до приблизно 1 Н» (п. 7) | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.43 · HW.9 |
| слот золочення в цеховій послідовності (одного дому послідовність не має) | базовий — окремі деталі; складений виріб — дельтою (п. 15) | [`01_01 §3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) ⚠️ «кроки 1–8 — не SOP» |
| амплітуда мікроруху від гойдання | «ще не виміряно» (п. 7) | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.43 |

---

## 3. Dispatch checklist (👤)

- [ ] 👤 **Адресат — нога [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8 «знайти гальваніка».** Кандидати є з 2026-09-28 ([`ua_vendor_map §5`](ua_vendor_map.md)) — обрати. Перед відправкою — форма за адресатом (§0 п.3): НАН → ТЗ; ЄС → §📤 (EN).
- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Specмапу маскування й креслення до першого листа НЕ додавати** — лише разом із маршрутом гальваніка (HW.8.2); лист так і каже («креслення — із замовленням»).
- [ ] 👤 **Після відповіді:** висновок (не чужі ціни й режими) → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8; маршрут → вимога [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) і рядок карти [`01_02 §3.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); відповідь про водень і нагрів → [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) R1; відповідь про стан поверхні → DMLS-лист п.9(c) (чи маскувати дріт від травлення) має отримати ту саму відповідь.

---

## 📤 Dispatch block (UA) — лист гальванікові (тверде золото по титану)

> **Репо-нота (у лист НЕ йде).** Несе як дзеркало канону й доми кожного — §1. Питає, бо канон цього свідомо не несе: маршрут (підшар · активація · тип золота · товщини) · стан поверхні на вході · маскування · місце в послідовності · водень і нагрів · методи контролю. **Немає свідомо:** трекер-ID і канон-рефів · чисел фінішу ПІНА (0.76 / 1.27 мкм) · терміна «Hard Gold ENIG» · нашого висновку «8–15 × тонше» · specмапи маскування · числа дрейфу Rc · імен інших адресатів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Тема:** Запит щодо селективного нанесення твердого золота на дві контактні площадки титанових деталей — вибір маршруту й пропозиція (дослідна партія)

Шановні колеги!

**Про нас і мету запиту.** Ми розробляємо сенсорний вузол для моніторингу лісу: титановий анкер встановлюється в стовбур живого дерева й живиться від вбудованого біопаливного елемента, а знімна капсула з електронікою підключається до анкера двома пружинними контактами (пінами). Контактні площадки анкера мають бути покриті твердим золотом, і ми шукаємо виконавця, який запропонує й виконає маршрут такого покриття по титану.

Це запит пропозиції та інформації про ваші можливості, а ще не замовлення: відповідь ні до чого не зобовʼязує жодну сторону, і відповідати можна просто в тексті листа.

**Ми не диктуємо процес.** Нижче — вимоги до результату й умови, у яких покриття працюватиме. Підготовку й активацію титану, підшар, тип твердого золота й товщини шарів просимо запропонувати вас, спираючись на власний досвід: це ваш технологічний маршрут, і вигадане нами число не повинно стати для вас вимогою. Базовий випадок — сплав Ti-6Al-4V, окремі деталі до складання; усе інше просимо оцінити як відхилення від нього.

**Що покривається**

1. **Центральна площадка — торець титанового дроту Ø1,0 мм.** Дріт тягнутий, одним кінцем приварений до пористої (решітчастої) титанової деталі; золотиться лише вільний торець. Після складання цей торець стоїть урівень із верхньою гранню фланця (п. 2) усередині полімерного кільця діаметром не менше 4,0 мм, і на нього сідає перший пін.
2. **Кільцева площадка — зона на плоскій верхній грані титанового фланця діаметром 29.8 мм**, на яку сідає другий пін. Радіус і ширину цієї зони ми уточнимо кресленням — вони залежать від моделі піна, яку ще обираємо; просимо назвати найменшу ширину зони й точність її межі, які ви витримуєте.
3. **Обидві площадки — одним маршрутом і однаковим покриттям.**
4. **Матеріал.** Базовий для ціни — Ti-6Al-4V для обох деталей (для пористої деталі це пробний еталон, а не кандидат: її сплав буде безванадієвим). Сплав пористої деталі й дроту остаточно не обрано; кандидати — Ti-6Al-7Nb, технічно чистий титан Grade 4, Ti-13Nb-13Zr, Ti-15Zr і тантал. Фланець — Ti-6Al-4V або один із цих безванадієвих сплавів. Скажіть, для яких сплавів ваш маршрут змінюється, і окремо — чи працюєте ви з танталом. Адгезія на титані залежить від сплаву — для деяких процесів технічно чисті марки поводяться інакше, ніж Ti-6Al-4V, — тож просимо відповісти про адгезію для кожного сплаву, який ви приймете, і вказати, чи вона підтверджена випробуваннями, чи є очікуванням.
5. **Решта поверхонь не золотиться:** ні пориста деталь, ні інші грані фланця — на частину з них пізніше наносять біологічно активні шари.

**Навіщо золото і в яких умовах воно працює**

6. **Функція.** Пін має тверде золоте покриття. Притиснутий до голого титану у вологому кислому середовищі, він утворює з ним гальванічну пару (різниця потенціалів близько 0,2 В), і контактний опір із часом зростає в рази. Золото на площадці виносить цю пару з поверхні контакту — але не прибирає її: під покриттям стик титану з покриттям лишається, і крізь пори до нього може дістатися конденсат. Тому для нас важать не лише товщина, а й адгезія та пористість покриття.
7. **Контакт ковзний і циклічний.** Пружинний пін притискається силою до приблизно 1 Н (точне значення залежить від моделі піна). Зʼєднань і розʼєднань під час обслуговування — за нашою оцінкою, порядку сотні за строк служби, а між ними — мікрорух від розгойдування стовбура, амплітуду якого ще не виміряно. Тому золото потрібне тверде, а не мʼяке.
8. **Електрично — слабкострумовий «сухий» контакт:** струм до 500 мкА при напрузі близько 0,5 В; контактний опір пари пін–площадка має лишатися нижче 50 мОм.
9. **Середовище й строк:** кислий конденсат ксилемного соку (pH близько 5,75, у наших випробуваннях — і 4,5), постійна волога, температура від −40 до +85 °C, строк служби — 20 років.
10. **Знезараження після золочення:** деталь проходить ультрафіолет (254 нм), промивання 70 % етанолом і гамма-опромінення Co-60 дозою не менше 15 кГр (верхньої межі ще не задано), далі зберігається при 4–8 °C. Покриття і його адгезія мають це пережити.

**Просимо повідомити**

*Маршрут*

11. **Маршрут повністю:** як ви готуєте й активуєте титан (як знімаєте оксид і не даєте йому відновитися до осадження); чи потрібен підшар — який, навіщо і що з ним станеться, якщо конденсат дістанеться до нього крізь пори; тип твердого золота (легувальний елемент, твердість); товщина кожного шару з допуском і методом вимірювання.
12. **Наше прочитання норм — просимо підтвердити або виправити.** Ми розуміємо, що занурювальне золото по хімічному нікелю (фініш друкованих плат, ENIG) дає тонкий мʼякий шар і для ковзного контакту не годиться, а тверде золото для інженерних застосувань осаджують електролітично (наприклад, за ASTM B488). Чи так це у вашій практиці? За яким стандартом ви працювали б і засвідчували результат?
13. **Стан поверхні, у якому ви приймаєте деталі** — просимо оцінити обидва варіанти: (а) площадки протравлені разом із рештою деталі (кислотне травлення з ультразвуком, шорстка поверхня); (б) площадки замасковані від травлення (торець дроту — як зрізаний, грань фланця — як оброблена). Який варіант ви воліли б і чому, і чи змінює він маршрут?
14. **Маскування:** як ви обмежуєте покриття двома площадками (маска й ванна, селективне тампонне нанесення чи інше); як не допускаєте потрапляння розчинів у пори решітчастої деталі; чим і як відмиваєте залишки хімії з сусідніх поверхонь.
15. **Місце в послідовності виготовлення.** Ми плануємо золотити окремі деталі до складання: торець дроту — на пористій деталі, кільце — на фланці, обидві — однією партією. Чи підходить це вашому маршруту? Якщо ваш маршрут радше потребує вже складеного виробу — обидві площадки в одній площині, між ними полімерне кільце, а всередині полімерна втулка, посаджена з натягом, — скажіть чому і що він вимагає від полімерних деталей.
16. **Водень і нагрів.** Чи може ваш маршрут (активація, осадження) вносити водень у титан? Чи потрібен після золочення нагрів — до якої температури й на який час? Для нас це важливо: окрему деталь нагріти можна, а складений виріб — лише обмежено, бо нагрів послаблює полімерну посадку.
17. **Контроль:** якими методами ви перевіряєте товщину, адгезію й пористість; чи можете виміряти контактний опір; чи надаєте свідків — зразки того самого сплаву, покриті в тій самій партії, для руйнівної перевірки (переріз, адгезія).

*Досвід і документи*

18. **Спроможність і досвід:** чи покривали ви золотом титан (і тантал) раніше; порівнянні роботи (знеособлені приклади годяться); обладнання для селективного нанесення.
19. **Система якості** — ISO 9001 чи інша, що маєте: номер документа, орган, сфера й строк дії.

*Обсяг, ціна, строки*

20. **Пробне покриття:** перед справжніми деталями — на наших зразках (відрізки дроту Ø1,0 мм і плоскі пластини того самого сплаву); ціна й строк.
21. **Дослідна партія:** від трьох до пʼяти комплектів (пориста деталь із дротом плюс фланець) — ціна за комплект; окремими рядками — налагодження процесу, маскувальне оснащення, свідки. Орієнтовно — ціна за комплект при партії 100 штук.
22. **Строки:** черга до початку, тривалість виконання, мінімальне замовлення.
23. **Умови співпраці:** договір, документи від нас, форма оплати, строк чинності пропозиції, контактна особа з технічних питань.

**Конфіденційність.** Технічна специфікація нашого виробу відкрито опублікована, тож для її обговорення угода про конфіденційність не потрібна; ми готові підписати вашу стандартну угоду щодо комерційних умов (ціни, строки, дані контролю якості).

**Додатки.** Для первинної пропозиції від нас нічого не потрібно; креслення деталей надамо із замовленням.

`[підпис і контакти відправника — заповнити перед відправкою]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Dispatch block (EN) — letter to a plating service (hard gold on titanium)

> **Репо-нота (у лист НЕ йде).** Той самий лист для ЄС-адресатів (кандидати — [`ua_vendor_map §5`](ua_vendor_map.md)). **Мапа провенансу — §1, спільна:** пункти нумеровано тими самими 1–23, і дім кожного числа той самий. **Немає свідомо — той самий перелік, що в UA-блоці:** трекер-ID і канон-рефів · чисел фінішу ПІНА (0.76 / 1.27 мкм) · терміна «Hard Gold ENIG» · нашого висновку «8–15 × тонше» · specмапи маскування · числа дрейфу Rc · імен інших адресатів (застереження про CP-Ti у п. 4 подано без джерела). **Відмінності від UA — лише адресатні:** п. 23 — чи беруть замовлення з України й як їде доставка деталей туди й назад; одиниці — з десятковою крапкою.

**⬇️ COPY FROM THIS LINE.** Everything above is the repo layer and does NOT go into the letter.

**Subject:** Request for information and quotation — selective hard gold plating of two contact pads on titanium parts (process route, pilot batch)

Dear Sir or Madam,

**About us and the purpose of this request.** We are developing a sensor node for forest monitoring: a titanium anchor is installed in the trunk of a living tree and is powered by a built-in biofuel cell, and a removable electronics capsule connects to the anchor through two spring-loaded contacts (pogo pins). The anchor's contact pads have to be finished with hard gold, and we are looking for a service provider who will propose and carry out a route for such a coating on titanium.

This is a request for a proposal and for information about your capabilities, not yet an order: a reply commits neither side, and you are welcome to answer directly in the text of this e-mail.

**We do not prescribe the process.** Below are the requirements for the result and the conditions in which the coating will work. We ask you to propose the preparation and activation of the titanium, the underlayer, the type of hard gold and the layer thicknesses from your own experience: this is your process route, and a number we invented must not become a requirement for you. The base case is Ti-6Al-4V, separate parts before assembly; please evaluate everything else as a deviation from it.

**What is to be plated**

1. **Central pad — the end face of a Ø1.0 mm titanium wire.** The wire is drawn and welded at one end to a porous (lattice) titanium part; only the free end face is plated. After assembly this end face sits flush with the top face of the flange (item 2), inside a polymer ring of at least 4.0 mm diameter, and the first pin lands on it.
2. **Annular pad — a zone on the flat top face of a titanium flange of 29.8 mm diameter**, where the second pin lands. We will specify the radius and width of this zone by drawing — they depend on the pin model we are still selecting; please state the minimum zone width and the accuracy of its boundary that you can hold.
3. **Both pads — by one route and with the same coating.**
4. **Material.** The base for pricing is Ti-6Al-4V for both parts (for the porous part this is a trial reference, not a candidate: its alloy will be vanadium-free). The alloy of the porous part and the wire is not final yet; the candidates are Ti-6Al-7Nb, commercially pure titanium Grade 4, Ti-13Nb-13Zr, Ti-15Zr and tantalum. The flange is Ti-6Al-4V or one of these vanadium-free alloys. Please tell us for which alloys your route changes and, separately, whether you work with tantalum. Adhesion on titanium depends on the alloy — for some processes commercially pure grades behave differently from Ti-6Al-4V — so please answer the adhesion question for each alloy you would accept, and state whether your adhesion on it is qualified by testing or is an expectation.
5. **The remaining surfaces are not plated:** neither the porous part nor the other faces of the flange — some of them later receive biologically active layers.

**Why gold, and in what conditions it works**

6. **Function.** The pin has a hard gold finish. Pressed against bare titanium in a humid acidic environment, it forms a galvanic couple with it (a potential difference of about 0.2 V), and the contact resistance grows several-fold over time. Gold on the pad moves this couple away from the contact surface — but does not remove it: under the coating the titanium–coating interface remains, and condensate can reach it through pores. This is why the adhesion and porosity of the coating matter to us, not only its thickness.
7. **The contact is sliding and cyclic.** The spring pin presses with a force of up to about 1 N (the exact value depends on the pin model). Matings and unmatings during maintenance — by our estimate, on the order of a hundred over the service life, and in between them, micro-motion from the swaying of the trunk, whose amplitude has not yet been measured. This is why the gold has to be hard, not soft.
8. **Electrically — a low-current "dry" contact:** current up to 500 µA at a voltage of about 0.5 V; the contact resistance of the pin–pad pair must stay below 50 mΩ.
9. **Environment and service life:** acidic condensate of xylem sap (pH about 5.75, and 4.5 in our tests), permanent humidity, temperature from −40 to +85 °C, service life of 20 years.
10. **Decontamination after plating:** the part goes through ultraviolet light (254 nm), rinsing with 70 % ethanol and Co-60 gamma irradiation at a dose of at least 15 kGy (the upper limit is not set yet), and is then stored at 4–8 °C. The coating and its adhesion must survive this.

**Please let us know**

*Process route*

11. **The complete route:** how you prepare and activate the titanium (how you remove the oxide and keep it from re-forming before deposition); whether an underlayer is needed — which one, why, and what happens to it if condensate reaches it through pores; the type of hard gold (alloying element, hardness); the thickness of each layer with its tolerance and measurement method.
12. **Our reading of the standards — please confirm or correct it.** We understand that immersion gold over electroless nickel (a printed-circuit-board finish, ENIG) gives a thin soft layer and is not suitable for a sliding contact, while hard gold for engineering applications is deposited electrolytically (for example, per ASTM B488). Is this so in your practice? To which standard would you work and certify the result?
13. **The surface condition in which you accept the parts** — please evaluate both options: (a) the pads etched together with the rest of the part (acid etching with ultrasound, rough surface); (b) the pads masked from etching (the wire end face as cut, the flange face as machined). Which option would you prefer and why, and does it change the route?
14. **Masking:** how you limit the coating to the two pads (mask and bath, selective brush plating or other); how you keep solutions out of the pores of the lattice part; how you rinse chemical residues off the adjacent surfaces.
15. **Position in the manufacturing sequence.** We plan to plate separate parts before assembly: the wire end face on the porous part, the ring on the flange, both in one batch. Does this suit your route? If your route rather needs the assembled product — both pads in one plane, a polymer ring between them and a polymer sleeve press-fitted inside — please tell us why and what it requires from the polymer parts.
16. **Hydrogen and heat.** Can your route (activation, deposition) introduce hydrogen into the titanium? Is heat treatment needed after plating — to what temperature and for how long? This matters to us: a separate part can be heated, but the assembled product only to a limited extent, because heating weakens the polymer interference fit.
17. **Inspection:** which methods you use to check thickness, adhesion and porosity; whether you can measure contact resistance; whether you provide witness samples — coupons of the same alloy plated in the same batch — for destructive testing (cross-section, adhesion).

*Experience and documents*

18. **Capability and experience:** whether you have plated titanium (and tantalum) with gold before; comparable jobs (anonymised examples are fine); equipment for selective plating.
19. **Quality system** — ISO 9001 or whatever you hold: certificate number, issuing body, scope and validity.

*Quantity, price, lead times*

20. **Trial plating:** before the real parts — on our samples (lengths of Ø1.0 mm wire and flat plates of the same alloy); price and lead time.
21. **Pilot batch:** three to five sets (porous part with wire, plus flange) — price per set; as separate lines — process set-up, masking tooling, witness samples. As an indication — price per set for a batch of 100.
22. **Lead times:** queue before start, execution time, minimum order.
23. **Terms of cooperation:** contract, documents required from us, payment terms, validity of the offer, technical contact person. We are based in Ukraine: please tell us whether you accept orders from Ukraine and how the shipment of parts to you and back would be arranged.

**Confidentiality.** The technical specification of our product is openly published, so no non-disclosure agreement is needed to discuss it; we are ready to sign your standard agreement covering commercial terms (prices, lead times, quality-control data).

**Attachments.** Nothing is needed from us for an initial proposal; drawings of the parts will be provided with the order.

`[sender's signature and contact details — fill in before sending]`

**⬆️ END OF LETTER TEXT.** Below is the repo layer again.

---

## 4. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | ⚖️ присуд 2026-09-22: вимога (а)–(г), чого канон свідомо не називає, найслабша ланка (дім) |
| [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | гальванопара Ti↔Au, Mandatory fix, PEEK-кільце Ø ≥ 4.0, двозначність маскування торця |
| [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | функційні вимоги контакту · спека піна (фініш піна — НЕ для площадки) |
| [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_01 §3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | шина (дріт Ø1.0, сплав = сплав анода, «стик під покриттям лишається») · збірка й заборона bake після посадки |
| [`01_02 §3.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §1.3a`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_02 §2.5`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | карта покриттів · золочення як джерело водню · сплави-кандидати |
| [`01_04 §6.3`](../../01_04_CODIT_and_Xylemointegration.md) | ГІЛКА A знезараження, яку покриття мусить пережити |
| [`fmea_fmeca_register`](../hardware/fmea_fmeca_register.md) | #11 — режим відмови, який золото площадки закриває |
| [`ua_vendor_map`](ua_vendor_map.md) · [`rfq_registry`](rfq_registry.md) | адресати (кандидати 2026-09-28, не обрано) · procurement-індекс |
