# Soldier — B2B-пара Samtec FW-SM + CLP (мезонін Power Deck ↔ RF Deck): лист-запит виробникові

> **Що це:** RFQ-аркуш до **Samtec** на пару board-to-board роз'ємів, що зʼєднує дві плати капсули Soldier. Предмет — перевірити **найслабшу ланку делегованого присуду** про носія пари: з якими кодами висоти FW-SM і CLP дають мейтовані рівно 8.0 і 10.0 мм. Наш вивід стоїть на двох каталожних прикладах, а таблиця мейтів виробника в дереві відсутня. Друга мета — **допуск змикання** і документ, де він записаний: `±0.15` у Z-ланцюзі паспорта не має. Третя — ціна, MOQ, лідтайм і умова «non-returnable». Сам присуд (FW-SM + CLP замість пари FTSH + CLT, якої не існує) лист під сумнів не ставить. Він купує його підтвердження.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-25, не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Адресат — Samtec напряму або дистрибʼютор із доступом до інженерів виробника; канал обирає founder, текст від цього не змінюється. Числа дзеркалять доми, і дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29: нога «котирування FW-SM + CLP у Samtec». Та сама відповідь годує ще дві ноги пункту: footprint у KiCad і вимір першої партії (§2).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Капсула електроніка» · hard-constraint дім §4.D: для B2B вимог не несе).

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Samtec — виробник поза UA, тому **лист англійською**. Перший рядок просить дистрибʼютора, якщо лист дійде до нього, переслати текст виробникові: на пп. 1–3 відповідає лише Samtec. Канал DIST реєстр уже називає (Mouser/Digi-Key), а п. 8d питає, чи зразки доїдуть в Україну напряму.
2. **Базовий кейс — ОДНА пара: FW-SM (lead style –03, SMD) + CLP (SMD), 1.27 мм, 2 × 5, mated 8.0 мм, 5 пар.** Чому 8.0, а не верхній край смуги: під ратифікованою короною модуль LoRa-E5 (2.5 мм) над RF Deck **влазить лише при B2B 8** ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)). Кеш `52_z_stack_tolerance` (pad поруч, FR4 1.6) дає просвіт над RF Deck **4.15 мм** при 8 і **2.15 мм** при 10. ⚠️ Модуля на платі вузла з 2026-09-25 немає (чіп STM32WLE5CC, ⚖️ founder, [`02_01 §3`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 1). Його 2.5 мм лишаються верхньою межею серед прочитаних кандидатів верху RF-деку, тож для ВЕРХУ 8.0 — консервативний кейс; ⚠️ для самого проміжку — ні: EDLC (5.2 мм) під RF-деком і пʼєзо (1.9–3.3 мм) над Power Deck за площею перекриваються в плані ([`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md)), і з AST1240 проміжок 8.0 є тіснішим кінцем; переглядається разом із `52` ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9). Число 5 — з третьої ноги HW.29: вимір «на 5 зразках першої партії».
   - **Дельта 1 — mated 10.0 мм.** Це верхній край канонної смуги 8–10 ([`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12) і єдиний важіль, що піднімає антену: 11.85 → 13.85 мм ([`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md), дія 1). Він знадобиться, якщо RF-макет ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33) присудить підлогу вище за ту, що дає 8. Під чинною короною 10 не закривається, тож дельту **оцінюємо, але не обираємо**. Ціна переходу — перевідкриття корони або `cavity_height_mm`, а не цей лист.
   - **Дельта 2 — орієнтир серії:** 1 000 і 10 000 пар ([`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) — ціновий рівень 1K; [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) — ціни на партію 10 000).
   - ⛔ **Дельти за кількістю контактів немає свідомо:** канон фіксує 10-pin (2 × 5) під 6–8 ліній, і жоден дім іншої кількості не вимагає. ⛔ Альтернатив інших виробників (Hirose DF40TC, Molex SlimStack) у листі до Samtec немає: у каноні вони лише «названі, не обрані».
3. **Лист не бере боку відкритого виміру** (скіл `legal-business` §Доменні правила #4). Яку висоту B2B прийняти, залежить від антенної підлоги, а її ще судитиме макет. Тому лист питає обидві висоти й жодної не замовляє остаточно. Правило #6(б) лист виконує буквально: п. 1a просить **таблицю мейтів**, а не наявність кожного P/N, і саме це колись не спрацювало з FTSH + CLT.
4. **Що подано вимогою, а що питанням.** Вимоги — лише канонні: крок, 2 × 5, SMD обох половин, vertical, header на нижній платі й socket на верхній, mated 8.0 (база) / 10.0 (дельта), −40…+85 °C. Решта — питання без нашого числа: мейт за таблицею, повні P/N, допуск і його джерело, standoff, зсув і кут, цикли, покриття контактів, струм, упаковка, комерція.
5. **Чому `±0.15` у листі немає.** Число, з яким Z-ланцюг рахує RSS, стоїть без паспорта ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)). Назвати його вендорові означало б запросити відповідь «так, годиться», а це самосвідчення, не паспорт. Тому лист питає допуск, **документ-джерело** і внесок кожного процесного фактора. Звірка відповіді з `±0.15` — наша робота. З тієї самої причини в листі немає нашої формули «mated ≈ stacker + post + 0.56 мм»: ми просимо таблицю виробника, а не підтвердження нашого виводу.
6. **Як читати відповідь «найближчі висоти» (п. 1c).** Якщо рівно 8.0 немає, найближча **вища** висота зʼїдає просвіт над модулем. За кешем `52` модуль лишається під короною, поки B2B ≤ 8 + (4.15 − 2.5) = 9.65 мм. Це наша арифметика над огинаючою кешу, не канон: допуск, припій і монтажний зазор кеш не моделює (його власна стеля). Найближча **нижча** висота опускає зазор антена↔Ti нижче за 11.85 мм.
7. **Standoff — питання, не рішення.** [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) (дія 1) пише «standoff/PCB spacer 8–10 мм». Окремого рядка standoff у BOM немає, а Z-ланцюг `52` несе для цього проміжку лише член B2B. Лист просить рекомендацію виробника (п. 2c) і нічого не замовляє. Якщо Samtec радить standoff, це два нові входи: отвори на платі зі стелею контуру ≤ Ø15.57 ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) і ще один член Z-ланцюга. Рішення за founder у HW.29.
8. **Відповідь у репо не комітиться.** Котирувальний документ, внутрішні звіти й переписка виробника — чужі операційні факти. У репо їде наш висновок у HW.29 і те, що нога прямо наказує: ціну пари 🤖 переносить у BOM поз. 12, рядок TOTAL і rollup [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) з посиланням на котирування.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Застосування: дві плати, мезонін** | [`02_01 §1`](../../02_01_Hardware_Architecture_and_BOM.md) (Power Deck + RF Deck) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 8 (FR4 1.6 мм) · поз. 12 (роль: 3V3, GND, VSTOR_sense, EBFC_sense, piezo_EXTI, BQ25570 EN — 6–8 ліній; без B2B RF Deck не має живлення — [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) дія 1) · [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (стеля контуру) | фактом; лінії — описово за класом («supply · ground · two analog sense · interrupt · enable»); контур «about 15 mm, upper limit» | назви сигналів · 15.57 / 15.17 (стеля з нульовим допуском читалась би як креслярський розмір — як у [`node_parylene_rfq`](node_parylene_rfq.md)) · анкер, Ti, pogo |
| **Обрана пара** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 (FW-SM –03 SMD + CLP SMD · 1.27 · 2 × 5 · vertical · header на Power Deck, socket на RF Deck · mated 8–10 задається кодом висоти) | вимогою | історія FTSH/CLT · альтернативи Hirose/Molex · rigid-flex (deferred) |
| **1 мейт, P/N, висоти** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) врізка під таблицею (FW-SM із CLP: приклади каталогу 8.13 і 9.91; діапазон 7.72–19.15) · нога HW.29 «коди висоти під мейтовані 8.0 і 10.0» · [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (під короною лише B2B 8) | 8.0 — базою, 10.0 — дельтою; каталожні числа — цитатою ЇХНЬОГО ж каталогу; таблиця мейтів, повні P/N і найближчі висоти — питанням | формула «stacker + post + 0.56» · наш вивід коду · «10 під короною не влазить» (наш висновок, вендорові не потрібен) |
| **2 допуск змикання** | [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (член B2B у Z-ланцюзі, паспорта немає) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) врізка (цитата каталогу «processing conditions will affect mated height») · третя нога HW.29 | цитатою каталогу; допуск, документ-джерело, процесні фактори — питанням | ⛔ `±0.15` (якір, §0 п. 5) · RSS ±0.45 · вікна pogo/pad |
| **2c standoff** | [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) дія 1 («standoff/PCB spacer 8–10 мм») · BOM без рядка standoff · `52` (для проміжку — лише член B2B) | питанням: рекомендація виробника і діапазон глибини входу CLP | наша неоднозначність (§0 п. 7) |
| **3 зсув і кут при змиканні** | — (канон вимоги не несе; вхід footprint-ноги HW.29) | питанням, без нашого числа; alignment pin / поляризація — з ціною в площі плати | — |
| **4 цикли змикання** | — (канон мовчить; прототипи — акрил, «easily reworkable», [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) | питанням | — |
| **5 середовище, покриття** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (−40…+85 °C) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (Parylene C 10 µm у серії, маскування коннекторів; п. 3 — повітря, опційно осушувач) · [`node_parylene_rfq`](node_parylene_rfq.md) (маска контактів мезоніна; «окремо ⊥ стеком» — п. 6) | −40…+85 — вимогою; капсула й покриття — фактом; покриття контактів і порада щодо Parylene — питанням | «20 років» (дім має анкер, не капсула) · прототипний акрил |
| **6 електрика** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 (лінії) · ноги HW.29 «signal integrity для 6-8 сигналів» і «insertion loss» | питанням: струм на контакт, опір контакту | струм TX LoRa (числа в листі немає — питаємо паспорт, не під наш пік) |
| **7 монтаж і документи** | [`02_01 §6`](../../02_01_Hardware_Architecture_and_BOM.md) («Робот встановлює piezo + B2B на заводі») · footprint-нога HW.29 (KiCad) | питанням: tape and reel, pick-and-place, креслення, footprint, 3D | — |
| **8 комерція** | нога HW.29 (ціна пари · MOQ · лідтайм · «non-returnable») · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) врізка («non-standard, non-returnable») · третя нога HW.29 (5 зразків) · [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) (1K) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) (ціни 10k) · [`rfq_registry`](rfq_registry.md) (канал DIST) | 5 пар — базою; 1 000 / 10 000 — орієнтиром; доставка в Україну — питанням | «~$0.85» (стояло на парі, якої не існує) · ціль «< $11» на електроніку |

---

## 2. Питання → нога трекера

| Питання листа | Нога [`00_07`](../../00_07_Action_Plan_Tracker.md) | Що закриває — і що ні |
|---|---|---|
| **1a–c** мейт за таблицею · повні P/N · висоти 8.0 / 10.0 і найближчі | HW.29 · «котирування FW-SM + CLP у Samtec» (коди висоти — «підтвердити») | Закриває найслабшу ланку присуду у врізці [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md): код висоти стає первинкою виробника, а не виводом із прикладів. Якщо 8.0 немає — §0 п. 6 |
| **2a–b** допуск, документ-джерело, процесні фактори | HW.29 · «виміряти insertion loss + height variation на 5 зразках» · Z-ланцюг `HW.8.7` ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), `52` → `TOL_PZ["B2B_stack"]`) | Дає члену `±0.15` **перше документне джерело** або прямо каже, що паспорта немає. ⛔ **Ногу виміру не закриває:** виробник сам попереджає, що висоту рухає процес, тобто наш reflow. Паспорт каже, що обіцяно; вимір — що вийшло на нашій лінії |
| **2c** standoff і глибина входу CLP | HW.29 (footprint) · `HW.8.7` (ще один член ланцюга, якщо standoff є) | Розсуджує неоднозначність «standoff/PCB spacer» у [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) порадою виробника; рішення — founder (§0 п. 7) |
| **3a–b** зсув, кут, alignment pin | HW.29 · KiCad «place footprints FW-SM/CLP на обидві деки» | Вхід footprint-у (отвори alignment pin на платі ≤ Ø15.57) і роботизованого монтажу. Вимоги в каноні немає, лист її не вводить |
| **4a–b** цикли, вплив перезмикання | HW.29 · вимір першої партії (чи рухає перезмикання висоту) | Інформаційне: канон циклів не вимагає |
| **5a** температурний діапазон | BOM поз. 12 (P/N) | Підтверджує, що пара не звужує −40…+85 капсули |
| **5b** покриття контактів | BOM поз. 12 (без коду покриття повного P/N не існує) | Потрібне, щоб п. 1b узагалі дав P/N |
| **5c** порада щодо Parylene | HW.11 · [`node_parylene_rfq`](node_parylene_rfq.md) п. 6 («окремо ⊥ стеком») | Незалежна думка виробника роз'єму для того самого вибору, який лист коатерові лишає відкритим. Нічого не розсуджує: обидві відповіді зводить founder |
| **6a** струм на контакт, опір контакту | HW.29 · KiCad «signal integrity для 6-8 сигналів» · вимір insertion loss | Паспортна база, з якою порівнюється вимір першої партії |
| **7a–b** tape and reel, pick-and-place, креслення, footprint, 3D | HW.29 · KiCad-нога | Вхід footprint-у; tape and reel — серійний монтаж ([`02_01 §6`](../../02_01_Hardware_Architecture_and_BOM.md)) |
| **8a–e** ціна, MOQ, лідтайм, non-returnable, зразки, 1K/10K, доставка | HW.29 · «ціна пари · MOQ · лідтайм · умова non-returnable» | 🤖 ціна → BOM поз. 12, TOTAL, rollup [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) — за самою ногою |

---

## 3. Найслабша ланка листа

**Найпотрібнішу відповідь виробник дати найменше здатен.** Допуск змикання цей лист питає саме тому, що `±0.15` не має паспорта. Але каталог уже сказав, від чого залежить висота: «processing conditions will affect mated height». Отже, розкид живе значною мірою в НАШОМУ процесі (паста, профіль reflow, площинність плати), а не в деталі. Найімовірніша відповідь — номінал плюс застереження або допуск самої деталі без внеску монтажу. Жодна з двох не закриває член Z-ланцюга. Лист це компенсує двома способами: п. 2b просить внесок кожного фактора, а п. 2a — документ, звіт кваліфікації чи креслення, а не число в тексті листа. **Прикмета, що відповідь закрила лише половину:** допуск прийшов без назви документа або без умов процесу. Тоді його першим джерелом, як і каже нога, лишається вимір першої партії.

⊕ **Друга, вужча ланка — сама база 8.0.** Вона стоїть на тому, що корона й `cavity_height_mm` 13.0 лишаються ратифікованими ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)). Якщо RF-макет присудить антенну підлогу, якої 8 не дає, база переходить на дельту 10.0. Під чинною короною 10.0 не закривається. Лист до цього готовий, бо ціну обох висот питає одним заходом.

---

## 4. Dispatch checklist

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Канал:** Samtec напряму (технічна підтримка / sales) або дистрибʼютор; текст той самий, перший абзац просить дистрибʼютора переслати лист виробникові.
- [ ] 👤 **Після відповіді** висновок → HW.29. Далі:
  - коди висоти й P/N → [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 і врізка; «Найслабша ланка» там закривається або звужується;
  - допуск і його джерело → [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) і `52` (`TOL_PZ`); ногу виміру це не знімає (§2);
  - ціна → 🤖 BOM поз. 12, TOTAL, [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md);
  - footprint, alignment і standoff → KiCad-нога HW.29 і founder (§0 п. 7);
  - порада щодо Parylene → HW.11.

  Котирувальних документів і внутрішніх даних виробника не комітити (§0 п. 8).

---

## 📤 Dispatch block (EN) — Samtec email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): FW-SM (–03, SMD) + CLP (SMD) · 1.27 мм · 2 × 5 · vertical · header знизу, socket зверху · mated 8.0 (база) / 10.0 (дельта) · каталожні 8.13 / 9.91 і 7.72–19.15 · цитата «processing conditions will affect mated height» · дві круглі плати ≈ 15 мм (стеля), FR4 1.6 · 6–8 ліній · −40…+85 °C · капсула з O-ring, повітря, опційно осушувач · Parylene C ≈ 10 µm із маскою контактів · pick-and-place · 5 пар · 1 000 / 10 000. Питає те, чого канон не фіксує: таблицю мейтів і повні P/N · найближчі висоти · допуск змикання, його документ і процесні фактори · standoff · зсув і кут · цикли · покриття контактів · струм і опір контакту · упаковку й документи · комерцію й доставку в Україну. Яке питання закриває яку ногу — §2. **Немає свідомо:** `±0.15` і RSS · формули «stacker + post + 0.56» · нашого виводу коду · «~$0.85» і цілі собівартості · історії FTSH/CLT · альтернатив Hirose/Molex/rigid-flex · висновку «10 під короною не влазить» · дельти за кількістю контактів · рішення про standoff · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** RFQ — FW-SM terminal strip + CLP socket strip, 1.27 mm pitch, 2 × 5, SMT: mating confirmation, part numbers for 8.0 mm and 10.0 mm mated height, mated-height tolerance, samples

**To a distributor receiving this:** if you are not Samtec, please forward this message to Samtec technical support. Several of the questions below can only be answered by the manufacturer.

Dear colleagues,

**About us and the application.** We are an R&D project in Ukraine developing a small sensor node for forest monitoring. Its electronics sit in a sealed capsule on two round printed circuit boards stacked one above the other: a lower power board and an upper radio and microcontroller board. Each board is **about 15 mm in diameter** (an upper limit set by the housing; the final outline may be smaller), FR4, 1.6 mm thick. A board-to-board connector pair joins the two boards and is the only electrical connection between them. It carries six to eight lines: the 3.3 V supply and ground for the upper board, two analog sense lines, a digital interrupt line and enable lines.

This is a request for information and a quotation for engineering samples, not yet a production order. Answering commits neither side to anything, and inline answers in this email are fine.

**What we have selected from your catalog**

- **Lower board:** FW-SM terminal strip, surface-mount lead style (-03), 1.27 mm pitch, double row, 5 positions per row (10 contacts), vertical.
- **Upper board:** CLP socket strip, surface mount, 1.27 mm pitch, double row, 5 positions per row.
- **Mated height:** base case **8.0 mm**; alternative **10.0 mm**.

We are working from your FW-SM catalog pages, which show mated heights with CLP of 8.13 mm and 9.91 mm among their examples, and which give a range of 7.72 to 19.15 mm for FW-SM with CLP. We have not found a table that gives the height codes for exactly 8.0 mm and 10.0 mm, so that is the core of this enquiry.

**1. Mating and part numbers: the question that matters most to us**

- a. Please confirm from your mating table that FW-SM and CLP, as described above, mate with each other in a double-row, 5-position configuration.
- b. Please give the complete part numbers of both halves for a mated height of 8.0 mm, and separately for 10.0 mm, with the plating you recommend in item 5. We understand that the mated height is set by the height codes of the FW-SM together with the CLP, and we would rather rely on your table than on our own reading of the examples.
- c. If exactly 8.0 mm or 10.0 mm is not available, please give the nearest available mated heights above and below each, with their part numbers.

**2. Mated-height tolerance**

Your catalog notes that processing conditions will affect mated height. The mated height enters a tolerance stack inside our capsule, so we need the figure together with its source.

- a. What is the tolerance on the mated height for the combinations in item 1? Where is it specified: a customer drawing, a product specification or a qualification test report? Please send that document.
- b. Which processing conditions change the mated height, and by how much each: solder paste thickness, reflow profile, board flatness, coplanarity of the parts, anything else? What do you recommend to keep the variation small?
- c. Is the mated pair meant to hold the spacing between the two boards by itself, or do you recommend separate standoffs? If standoffs are used, how much variation in board spacing can the CLP absorb, in insertion depth, while keeping full contact?

**3. Alignment when mating**

The connector sits between the two boards, so it mates without visual access.

- a. What lateral offset and angular misalignment does the pair accept at mating? Does it guide itself into position?
- b. Are alignment pins or polarisation available for these parts, and how do they change the recommended PCB footprint? Our boards are small, so every square millimetre of board area matters.

**4. Mating cycles**

- a. What is the rated number of mating cycles for this pair?
- b. Does repeated mating and unmating change the contact resistance or the mated height?

**5. Environment, plating and conformal coating**

The capsule is sealed with an O-ring and filled with air, possibly with a desiccant. The operating temperature ranges from −40 to +85 °C, over many years of outdoor service. In series production the boards will be coated with Parylene C, about 10 µm thick, with the mating contacts of the connector masked.

- a. Please confirm that the rated temperature range of both parts covers −40 to +85 °C.
- b. Which contact plating do you recommend for these conditions?
- c. Do you have guidance on conformal coating of boards that carry this pair, for example on masking the mating area, or on whether the boards should be coated before or after the two halves are mated?

**6. Electrical**

- a. Current rating per contact, both with a single contact powered and with several adjacent contacts powered.
- b. Contact resistance, initial and after the rated mating cycles.

**7. Production and documents**

- a. In production, both halves will be placed by pick-and-place. Are they available on tape and reel, and is a pick-and-place pad or cap available for each half?
- b. Please send the customer drawings for the part numbers in item 1, the recommended PCB footprint for each half, and 3D models.

**8. Commercial**

- a. Price and lead time for **5 mated pairs at 8.0 mm mated height** (our base case), and separately for 5 mated pairs at 10.0 mm.
- b. Your catalog describes this product as non-standard and non-returnable. What does that mean for these part numbers: minimum order quantity, cancellation terms, and whether samples are available through your sample programme?
- c. An indicative price per mated pair at 1 000 and at 10 000 pairs, with lead times.
- d. Can samples be delivered to Ukraine directly, or should we order through a distributor?
- e. Quote currency and validity, and a technical point of contact.

Thank you in advance.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 5. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) | BOM поз. 12 (пара, крок, 2 × 5, 8–10, лінії) і врізка під таблицею (присуд, каталожні висоти, «non-returnable», найслабша ланка присуду) · поз. 8 (FR4 1.6) |
| [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_01 §6`](../../02_01_Hardware_Architecture_and_BOM.md) | дія 1: B2B як єдиний міст Power↔RF, «standoff/PCB spacer», зазор антена↔Ti 11.85–13.85 · робот ставить B2B на заводі |
| [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | член B2B у Z-ланцюзі без паспорта · вертикальний бюджет (лише B2B 8 під короною) · стеля контуру · Parylene C 10 µm і маскування · −40…+85 °C |
| `tools/in_silico/scripts/52_z_stack_tolerance.py` · `cache/mechanical/z_stack_tolerance.json` | `B2B_STACK_MM`, `TOL_PZ`, просвіт над RF Deck 4.15 / 2.15 мм (§0 пп. 2, 6) |
| [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) | rollup, куди 🤖 переносить ціну пари |
| [`node_parylene_rfq`](node_parylene_rfq.md) | маска контактів мезоніна · «окремо ⊥ стеком» (п. 5c тут) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29 · HW.8 (8.7) · HW.33 · HW.11 | дім стану · Z-ланцюг · RF-макет (що може перевернути базу) · покриття |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс (рядок «Капсула електроніка») |
