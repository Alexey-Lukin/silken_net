# Soldier — B2B-пара Samtec FW-SM + CLP (мезонін Power Deck ↔ RF Deck): лист-запит виробникові

> **Що це:** RFQ-аркуш до **Samtec** на пару board-to-board роз'ємів, що зʼєднує дві плати капсули Soldier. Предмет — перевірити **найслабшу ланку делегованого присуду** про носія пари: з якими кодами висоти FW-SM і CLP дають мейтовані рівно 8.0 і 10.0 мм. Наш вивід стоїть на двох каталожних прикладах, а таблиця мейтів виробника в дереві відсутня. Друга мета — **допуск змикання** і документ, де він записаний: `±0.15` у Z-ланцюзі паспорта не має. Третя — ціна, MOQ, лідтайм і умова «non-returnable». Сам присуд (FW-SM + CLP замість пари FTSH + CLT, якої не існує) лист під сумнів не ставить. Він купує його підтвердження.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-25; 2026-11-07 переписано до читання founder-а — опубліковане Samtec стало «please confirm X» з цитатою документа (скіл `legal-business` §Доменні правила #14; кожну цитату звірено з первинкою — §0 п. 9 ⊕), лінії пари — за розводкою; **надіслано 2026-11-07** напряму Samtec (⚖️ founder «так» на текст і канал): To — інженерна підтримка, копія — служба котирувань і зразків (обидві адреси з їхньої сторінки техпідтримки; самі адреси — у корпусі памʼяті), версія `165aeb4a6` без рядка до дистрибʼютора.** ⊕ Перша відповідь координатора ASG 2026-11-09 — уточнення; «Follow-up block (EN)» нижче надіслано того ж дня на «так» founder-а (маршрут комерції — питанням, без нової адреси). Адресат — Samtec напряму або дистрибʼютор із доступом до інженерів виробника; канал обирає founder, текст від цього не змінюється. Числа дзеркалять доми, і дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29: нога «котирування FW-SM + CLP у Samtec». Та сама відповідь годує ще дві ноги пункту: footprint у KiCad і вимір першої партії (§2).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Капсула електроніка» · hard-constraint дім §4.D: для B2B вимог не несе).

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Samtec — виробник поза UA, тому **лист англійською**. Перший рядок просить дистрибʼютора, якщо лист дійде до нього, переслати текст виробникові: на пп. 1–3 відповідає лише Samtec. Канал DIST реєстр уже називає (Mouser/Digi-Key), а п. 8d питає, чи зразки доїдуть в Україну напряму.
2. **Базовий кейс — ОДНА пара: FW-SM (lead style –03, SMD) + CLP (SMD), 1.27 мм, 2 × 5, mated 8.0 мм, 5 пар.** Чому 8.0, а не верхній край смуги: під ратифікованою короною найвищий прочитаний член верху RF-деку — антена `NN02-224` (2.4 мм; з 2026-09-30, коли поз. 19 обмежено ≤ 1.10 мм; поз. 17 LSE — `ABS06-107-32.768kHz-T` (клас з 2026-10-05, P/N з 2026-10-06), H ≤ 0.6 мм за кресленням паспорта, тобто нижче антени — [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 17) — над RF Deck **влазить лише при B2B 8** ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)). Кеш `52_z_stack_tolerance` (стек без пʼєзо, FR4 1.6) дає просвіт над RF Deck **4.15 мм** при 8 і **2.15 мм** при 10. ⚠️ Модуля на платі вузла з 2026-09-25 немає (чіп STM32WLE5CC, ⚖️ founder, [`02_01 §3`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 1). Верхньою межею верху RF-деку тепер є антена 2.4 мм, тож для ВЕРХУ 8.0 — консервативний кейс; для самого проміжку конфлікт висот EDLC (5.2 мм під RF-деком) ↔ пʼєзо над Power Deck зник разом із пʼєзо (⚖️ founder 2026-09-29, [`02_01 §6`](../../02_01_Hardware_Architecture_and_BOM.md)). Число 5 — з третьої ноги HW.29: вимір «на 5 зразках першої партії».
   - **Дельта 1 — mated 10.0 мм.** Це верхній край канонної смуги 8–10 ([`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12) і єдиний важіль, що піднімає антену: 11.85 → 13.85 мм ([`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md), дія 1). Він знадобиться, якщо RF-макет ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33) присудить підлогу вище за ту, що дає 8. Під чинною короною 10 не закривається, тож дельту **оцінюємо, але не обираємо**. Ціна переходу — перевідкриття корони або `cavity_height_mm`, а не цей лист.
   - **Дельта 2 — орієнтир серії:** 1 000 і 10 000 пар ([`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) — ціновий рівень 1K; [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) — колонка цілить у партію 10 000).
   - ⛔ **Дельти за кількістю контактів немає свідомо:** канон фіксує 10-pin (2 × 5) під 5–7 ліній, і жоден дім іншої кількості не вимагає. ⛔ Альтернатив інших виробників (Hirose DF40TC, Molex SlimStack) у листі до Samtec немає: у каноні вони лише «названі, не обрані».
3. **Лист не бере боку відкритого виміру** (скіл `legal-business` §Доменні правила #4). Яку висоту B2B прийняти, залежить від антенної підлоги, а її ще судитиме макет. Тому лист питає обидві висоти й жодної не замовляє остаточно. Правило #6(б) лист виконує буквально: п. 1a просить **таблицю мейтів**, а не наявність кожного P/N, і саме це колись не спрацювало з FTSH + CLT.
4. **Що подано вимогою, а що питанням.** Вимоги — лише канонні: крок, 2 × 5, SMD обох половин, vertical, header на нижній платі й socket на верхній, mated 8.0 (база) / 10.0 (дельта), −40…+85 °C. Решта — питання без нашого числа: мейт за таблицею, повні P/N, допуск і його джерело, standoff, зсув і кут, цикли, покриття контактів, струм, упаковка, комерція.
5. **Чому `±0.15` у листі немає.** Число, з яким Z-ланцюг рахує RSS, стоїть без паспорта пари ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md); креслення FW нормує ±.005″ лише положення тіла хедера, розмір «A» — §0 п. 9). Назвати його вендорові означало б запросити відповідь «так, годиться», а це самосвідчення, не паспорт. Тому лист питає допуск, **документ-джерело** і внесок кожного процесного фактора. Звірка відповіді з `±0.15` — наша робота. З тієї самої причини в листі немає нашої формули «mated ≈ stacker + post + 0.56 мм»: ми просимо таблицю виробника, а не підтвердження нашого виводу.
6. **Як читати відповідь «найближчі висоти» (п. 1c).** Якщо рівно 8.0 немає, найближча **вища** висота зʼїдає просвіт над антеною `NN02-224` (2.4 мм — найвищий прочитаний член верху RF-деку з 2026-09-30). За кешем `52` антена лишається під короною, поки B2B ≤ 8 + (4.15 − 2.4) = 9.75 мм над центром деки (на краю плати при стелі контуру просвіт 4.136 → 9.74). Обережне прочитання з допуском із того ж кешу (`room_after_tolerance_mm`): просвіт 3.7 мм за RSS, як його цитує [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), → ≤ 9.3 мм; за найгіршим випадком 3.2 → ≤ 8.8. Межу подано смугою, а не одним числом, бо котра з них діє, залежить від місця антени на RF-деку, а розкладки немає (кеш сам називає це відсутнім датумом). Це наша арифметика над огинаючою кешу, не канон: припій і монтажний зазор кеш не моделює (його власна стеля). Найближча **нижча** висота опускає зазор антена↔Ti нижче за 11.85 мм.
7. **Standoff — тепер рішення (⚖️ 2026-10-05, поз. 25); питанням лишилась глибина входу CLP.** Стійки Є — присуд прокладки кишені BME280 (⚖️ founder 2026-10-05, [`02_01 §3.4`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 24) тримає Z позитивним упором стійок між деками; висоту, P/N і отвори веде `00_07` HW.9, а п. 2c лишається питанням про глибину входу CLP при стійках. ⊕ Того ж дня P/N і форму вирішено — без гвинтів, `9774080243R` × 2: поз. 25 і врізка під таблицею [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md); відповідь на пп. 1a–c покаже, чи пара рівно 8.0 — інакше висота стійки є ⚖️ переприсудом (найслабша ланка присуду поз. 25), а не машинною правкою; без гвинтів отворів у RF Deck немає.
8. **Відповідь у репо не комітиться.** Котирувальний документ, внутрішні звіти й переписка виробника — чужі операційні факти. У репо їде наш висновок у HW.29 і те, що нога прямо наказує: ціну пари 🤖 переносить у BOM поз. 12, рядок TOTAL і rollup [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) з посиланням на котирування.
9. **Що публічний каталог уже відповів (звірено 2026-10-05: аркуші FW-SM і CLP, ред. грудня 2025, і сторінка продукту на сайті Samtec).** CLP мейтиться з FW (рядок «Mates» самого аркуша) · обидві −55…+125 °C → п. 5a · CLP 3.4 A на пін → п. 6a (струм; опору контакту аркуш не дає) · 100 циклів змикання з 10 µ″ Au → п. 4a · опція направляючих пінів –A → п. 3b · «Samtec recommends mechanical board spacers be used in applications with gold or selective gold plated connectors» → п. 2c (рекомендацію дано; глибини входу й діапазону стійки — ні) · «non-standard, non-returnable» → п. 8 (умову підтверджено). Тіло FW ставлять на пін кроком 0.005″ (0.13 мм), а `FW-05-03-L-D-228-065` сайт приймає як конфігурацію; ціни без входу в акаунт сайт не показує. **У мить відправки** ці пункти листа стають ПІДТВЕРДЖЕННЯМ із цитатою каталогу, а не питанням (⊕ 2026-11-07: зроблено ДО читання founder-а, як велить #14 — тут, а не в мить відправки); відкритими лишаються таблиця мейтів і коди висоти (п. 1), допуск змикання з документом-джерелом (п. 2a–b) і комерція (п. 8a–e). ⊕ 2026-10-08: діапазон кодів дав сам каталог, інструмент мейтів сайту з каталожною прямою розходиться на номіналі, а «крок .005″» сторінки продукту не сходиться з прикладами каталогу — числа у врізці [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12. Тож п. 1 у мить відправки питає вже не «чи існує код», а який документ Samtec правий для коду під 8.0 / 10.0 і що означає «крок»; п. 2a уже питає про CLP і решту пари поверх ±.005″ на «A» хедера з креслення FW.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Застосування: дві плати, мезонін** | [`02_01 §1`](../../02_01_Hardware_Architecture_and_BOM.md) (Power Deck + RF Deck) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 8 (FR4 1.6 мм) · поз. 12 (роль: 3V3, GND, VSTOR_sense, EBFC_sense, BQ25570 EN — 5–7 ліній; ⚠️ «BQ25570 EN» застаріло 2026-11-02: `VOUT_EN` іде на `VBAT_OK`, не на МК, а пін `EN` канон не розводить — тож «two analog sense lines and enable lines» у тексті листа звірити з розводкою перед надсиланням (⊕ 2026-11-07: лист описує лінії за розводкою — «analog sense lines, possibly one digital enable line» і силова лінія накопичувача за одного з розподілів дек, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29, нога KiCad); без B2B RF Deck не має живлення — [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) дія 1) · [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (стеля контуру) | фактом; лінії — описово за класом («supply · ground · two analog sense · interrupt · enable»); контур «about 21–23 mm in diameter, possibly larger … the outline may still change» (на застосованому куполі ціль Ø19.97; ⊕ «Пакет кореня» 2026-10-13 — пара B2B ≈ Ø21.58–22.75, і це нижня межа; рух кореня — один, після осі 3 RF-макета, ⚖️ founder 2026-10-13) | назви сигналів · 20.37 / 19.97 (стеля з нульовим допуском читалась би як креслярський розмір — як у [`node_parylene_rfq`](node_parylene_rfq.md)) · анкер, Ti, pogo · пакет кореня й причина руху |
| **Обрана пара** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 (FW-SM –03 SMD + CLP SMD · 1.27 · 2 × 5 · vertical · header на Power Deck, socket на RF Deck · mated 8–10 задається кодом висоти) | вимогою | історія FTSH/CLT · альтернативи Hirose/Molex · rigid-flex (deferred) |
| **1 мейт, P/N, висоти** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) врізка під таблицею (FW-SM із CLP: приклади каталогу 8.13 і 9.91; стекер –03 .215–.335″ — «7.72–19.15» є діапазоном усієї серії разом із –05/FLE) · нога HW.29 «коди висоти під мейтовані 8.0 і 10.0» · [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (під короною лише B2B 8) | 8.0 — базою, 10.0 — дельтою; каталожні числа — цитатою ЇХНЬОГО ж каталогу; таблиця мейтів, повні P/N і найближчі висоти — питанням | формула «stacker + post + 0.56» · наш вивід коду · «10 під короною не влазить» (наш висновок, вендорові не потрібен) |
| **2 допуск змикання** | [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (член B2B у Z-ланцюзі, паспорта пари немає; на розмір «A» хедера — ±.005″ за кресленням FW) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) врізка (цитата каталогу «processing conditions will affect mated height») · третя нога HW.29 | цитатою каталогу; допуск, документ-джерело, процесні фактори — питанням | ⛔ `±0.15` (якір, §0 п. 5) · RSS ±0.45 · вікна pogo/pad |
| **2c standoff** | [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) дія 1 («standoff/PCB spacer 8–10 мм») · BOM поз. 25 — стійки (⚖️ 2026-10-05) · `52` (для проміжку — член B2B до пакета кореня) | EN ще питає й рекомендацію — у мить відправки вона стає підтвердженням із цитатою каталогу (§0 п. 9); питанням лишається діапазон глибини входу CLP при стійках | наш присуд стійок (поз. 25: P/N, 8.0) — §0 п. 7 |
| **3 зсув і кут при змиканні** | — (канон вимоги не несе; вхід footprint-ноги HW.29) | питанням, без нашого числа; alignment pin / поляризація — з ціною в площі плати | — |
| **4 цикли змикання** | — (канон мовчить; прототипи й пілот — HumiSeal 1A33 вручну, знімається стрипером, [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) | питанням | — |
| **5 середовище, покриття** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (−40…+85 °C) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (Parylene C 10 µm у серії, маскування коннекторів; п. 3 — повітря, опційно осушувач) · [`node_parylene_rfq`](node_parylene_rfq.md) (маска контактів мезоніна; «окремо ⊥ стеком» — п. 6) | −40…+85 — вимогою; капсула й покриття — фактом; покриття контактів і порада щодо Parylene — питанням | «20 років» (дім має анкер, не капсула) · прототипне ручне покриття |
| **6 електрика** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 (лінії) · ноги HW.29 «signal integrity для 5–7 сигналів» і «insertion loss» | питанням: струм на контакт, опір контакту | струм TX LoRa (числа в листі немає — питаємо паспорт, не під наш пік) |
| **7 монтаж і документи** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 (SMD-пара — монтаж машиною) · footprint-нога HW.29 (KiCad) | питанням: tape and reel, pick-and-place, креслення, footprint, 3D | — |
| **8 комерція** | нога HW.29 (ціна пари · MOQ · лідтайм · «non-returnable») · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) врізка («non-standard, non-returnable») · третя нога HW.29 (5 зразків) · [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) (1K) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) (колонка цілить у 10k) · [`rfq_registry`](rfq_registry.md) (канал DIST) | 5 пар — базою; 1 000 / 10 000 — орієнтиром; доставка в Україну — питанням | «~$0.85» (стояло на парі, якої не існує) · ціль «< $11» на електроніку |

---

## 2. Питання → нога трекера

| Питання листа | Нога [`00_07`](../../00_07_Action_Plan_Tracker.md) | Що закриває — і що ні |
|---|---|---|
| **1a–c** мейт за таблицею · повні P/N · висоти 8.0 / 10.0 і найближчі | HW.29 · «котирування FW-SM + CLP у Samtec» (коди висоти — «підтвердити») | Закриває найслабшу ланку присуду у врізці [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md): код висоти стає первинкою виробника, а не виводом із прикладів. Якщо 8.0 немає — §0 п. 6 |
| **2a–b** допуск, документ-джерело, процесні фактори | HW.29 · «виміряти insertion loss + height variation на 5 зразках» · Z-ланцюг `HW.8.7` ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), `52` → `TOL_PZ["B2B_stack"]`) | Дає члену `±0.15` **перше документне джерело для пари** (креслення FW дає ±.005″ лише на розмір «A» хедера) або прямо каже, що паспорта немає. ⛔ **Ногу виміру не закриває:** виробник сам попереджає, що висоту рухає процес, тобто наш reflow. Паспорт каже, що обіцяно; вимір — що вийшло на нашій лінії |
| **2c** standoff і глибина входу CLP | HW.29 (footprint) · HW.9 (висота стійки поз. 25; член `52` у пакеті кореня) · `HW.8.7` | Чи стійка 8.0 упирається, не перетягуючи CLP; самі стійки вирішено ⚖️ 2026-10-05 (поз. 25, §0 п. 7) |
| **3a–b** зсув, кут, alignment pin | HW.29 · KiCad «place footprints FW-SM/CLP на обидві деки» | Вхід footprint-у (отвори alignment pin на платі; контур — ціль Ø ≈ 20.0 під обвідну бустерів (з кільцем кишені вента, 2026-09-30), [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md)) і роботизованого монтажу. Вимоги в каноні немає, лист її не вводить |
| **4a–b** цикли, вплив перезмикання | HW.29 · вимір першої партії (чи рухає перезмикання висоту) | Інформаційне: канон циклів не вимагає |
| **5a** температурний діапазон | BOM поз. 12 (P/N) | Підтверджує, що пара не звужує −40…+85 капсули |
| **5b** покриття контактів | BOM поз. 12 (без коду покриття повного P/N не існує) | Потрібне, щоб п. 1b узагалі дав P/N |
| **5c** порада щодо Parylene | HW.11 · [`node_parylene_rfq`](node_parylene_rfq.md) п. 6 («окремо ⊥ стеком») | Незалежна думка виробника роз'єму для того самого вибору, який лист коатерові лишає відкритим. Нічого не розсуджує: обидві відповіді зводить founder |
| **6a** струм на контакт, опір контакту | HW.29 · KiCad «signal integrity для 5–7 сигналів» · вимір insertion loss | Паспортна база, з якою порівнюється вимір першої партії |
| **7a–b** tape and reel, pick-and-place, креслення, footprint, 3D | HW.29 · KiCad-нога | Вхід footprint-у; tape and reel — серійний монтаж (SMD обох половин — [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12; що SMD-частини ставить pick-and-place, канон каже лише неявно — [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md), «THT-крок поза pick-and-place») |
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
  - footprint, alignment → KiCad-нога HW.29; глибина входу CLP → висота стійки поз. 25 і бенч-нога стійок HW.9 (§0 п. 7);
  - порада щодо Parylene → HW.11.

  Котирувальних документів і внутрішніх даних виробника не комітити (§0 п. 8).

---

## 📤 Dispatch block (EN) — Samtec email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): FW-SM (–03, SMD) + CLP (SMD) · 1.27 мм · 2 × 5 · vertical · header знизу, socket зверху · mated 8.0 (база) / 10.0 (дельта) · каталожні 8.13 / 9.91 і стекер –03 .215–.335″ · цитата «processing conditions will affect mated height» · дві круглі плати ≈ 21–23 мм, можливо більше (ціль), FR4 1.6 · 5–7 ліній · −40…+85 °C · капсула з O-ring, повітря, опційно осушувач · Parylene C ≈ 10 µm із маскою контактів · pick-and-place · 5 пар · 1 000 / 10 000. Питає те, чого канон не фіксує: таблицю мейтів і повні P/N · найближчі висоти · допуск змикання, його документ і процесні фактори · standoff · зсув і кут · цикли · покриття контактів · струм і опір контакту · упаковку й документи · комерцію й доставку в Україну. Яке питання закриває яку ногу — §2. **Немає свідомо:** `±0.15` і RSS · формули «stacker + post + 0.56» · нашого виводу коду · «~$0.85» і цілі собівартості · історії FTSH/CLT · альтернатив Hirose/Molex/rigid-flex · висновку «10 під короною не влазить» · дельти за кількістю контактів · рішення про standoff · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** RFQ: FW-SM + CLP, 1.27 mm, 2 × 5 SMT — part numbers for 8.0 mm and 10.0 mm mated height, tolerance, samples

**To a distributor receiving this:** if you are not Samtec, please forward this message to Samtec technical support. Several of the questions below can only be answered by the manufacturer.

Dear colleagues,

**About us and the application.** We are an R&D project in Ukraine developing a small sensor node for forest monitoring. Its electronics sit in a sealed capsule on two round printed circuit boards stacked one above the other: a lower power board and an upper radio and microcontroller board. Each board is **about 21–23 mm in diameter**, possibly larger (the housing is being sized around the final layout, so the outline may still change), FR4, 1.6 mm thick. A board-to-board connector pair joins the two boards and is the only electrical connection between them. It carries five to seven lines, and the final list depends on the board layout: the supply and ground for the upper board, analog sense lines, possibly one digital enable line and, depending on how the parts are split between the two boards, the supply line of the energy-storage capacitor.

This is a request for information and a quotation for engineering samples, not yet a production order. Answering commits neither side to anything, and inline answers in this email are fine. Where your published documents already answer a question, we quote them and ask you only to confirm that they apply to this pair.

**What we have selected from your catalog**

- **Lower board:** FW-SM terminal strip, surface-mount lead style –03, 1.27 mm pitch, double row, 5 positions per row (10 contacts), vertical.
- **Upper board:** CLP socket strip, surface mount, 1.27 mm pitch, double row, 5 positions per row.
- **Mated height:** base case **8.0 mm**; alternative **10.0 mm**.

Your FW-SM catalog (F-226, Rev 09 DEC25) gives a stacker-height range of .215 to .335 in for lead style –03 and, with CLP, mated heights of .320 in (8.13 mm) for stacker code 233 and .390 in (9.91 mm) for code 303. The mated sets on your CLP product page list other combinations, for example FW-03-03-L-D-255-065 with CLP-103-02-F-D-TR-BE at 8.760 mm and FW-02-03-L-D-260-065 with CLP-102-02-F-D-TR-BE at 8.890 mm. From these documents we could not tell which stacker code gives exactly 8.0 mm or 10.0 mm, nor which of them governs the nominal mated height, and that is the core of this enquiry.

**1. Mating and part numbers: the question that matters most to us**

- a. Your FW-SM catalog lists CLP as a board mate, and your CLP catalog lists FW. Please confirm that FW-SM and CLP, as described above, mate in a double-row, 5-position configuration.
- b. Please give the complete part numbers of both halves for a mated height of 8.0 mm, and separately for 10.0 mm, with the plating you recommend in item 5. Please also tell us which document governs the nominal mated height (the catalog table or the mated-set data on your website) and in what steps the stacker-height code can be ordered.
- c. If exactly 8.0 mm or 10.0 mm is not available, please give the nearest available mated heights above and below each, with their part numbers.

**2. Mated-height tolerance**

Your FW-SM catalog notes that processing conditions will affect mated height. The mated height enters a tolerance stack inside our capsule, so we need the figure together with its source.

- a. Your FW drawing (Rev DG) gives dimension "A" as ±.005 in and a maximum height variation between rows of .005 in, and your CLP drawing (Rev DH) gives .090 +.003/–.002 in, measured at the bend. Which of these enter the mated height of the pair, and is there a tolerance on the mated height of the pair as a whole for the combinations in item 1? Where is it specified: a customer drawing, a product specification or a qualification test report? Please send that document.
- b. Your product specification for this family (Rev B) gives a 0.15 mm stencil, up to three reflow passes at a maximum component temperature of 260 °C and machine placement in the Z axis, and both catalogs give a lead coplanarity of .004 in. How much does each processing condition change the mated height (solder paste thickness, reflow profile, board flatness, coplanarity of the parts), and what do you recommend to keep the variation small?
- c. Your FW-SM catalog recommends mechanical board spacers with gold-plated connectors, and we plan to use them. Your CLP catalog gives a minimum top-entry insertion depth of 1.40 mm (.055 in). What range of board spacing, in insertion depth, can the CLP absorb while keeping full contact?

**3. Alignment when mating**

The connector sits between the two boards, so it mates without visual access.

- a. What lateral offset and angular misalignment does the pair accept at mating? Does it guide itself into position?
- b. Your FW-SM catalog lists an alignment-pin option (–A) from 3 positions. Please confirm which alignment option is available for both halves in 2 × 5, and send the recommended PCB footprint with it: our boards are small, so every square millimetre of board area matters.

**4. Mating cycles**

- a. Your CLP catalog gives a maximum of 100 mating cycles with 10 µ″ gold, and your product specification a durability test of 500 cycles. Which applies to FW-SM + CLP with the plating you recommend?
- b. Your qualification report 720050 (CLP with FTSH) shows a contact-resistance change of no more than +5.0 mΩ after 100 cycles. Does it apply to FW-SM + CLP, and does repeated mating change the mated height?

**5. Environment, plating and conformal coating**

The capsule is sealed with an O-ring and filled with air, possibly with a desiccant. The operating temperature ranges from −40 to +85 °C, over many years of outdoor service; your catalogs give −55 to +125 °C for both series, which covers it. In series production the boards will be coated with Parylene C, about 10 µm thick, with the mating contacts of the connector masked.

- a. Which contact plating do you recommend for these conditions?
- b. Do you have guidance on conformal coating of boards that carry this pair, for example on masking the mating area, or on whether the boards should be coated before or after the two halves are mated?

**6. Electrical**

- a. Your product specification gives 4.2 A with one pin powered per row, and your CLP catalog 3.4 A per pin with 2 pins powered. Please confirm that these apply to FW-SM + CLP, and give the rating with several adjacent contacts powered.
- b. Your qualification report 720050 gives an initial contact resistance of 9.98 mΩ maximum, and your product specification a change of no more than 15 mΩ. Please confirm that these apply to FW-SM + CLP.

**7. Production and documents**

- a. In production, both halves will be placed by pick-and-place. Your catalogs list tape and reel (–TR) and a pick-and-place pad (–P; for FW-SM from 5 positions). Please confirm that both are available for both halves in 2 × 5.
- b. Please send the customer drawings for the part numbers in item 1, the recommended PCB footprint for each half, and 3D models.

**8. Commercial**

- a. Price and lead time for **5 mated pairs at 8.0 mm mated height** (our base case), and separately for 5 mated pairs at 10.0 mm.
- b. Your FW-SM catalog says that the series is non-standard and non-returnable (your CLP catalog: some lengths, styles and options). What does that mean for these part numbers: minimum order quantity, cancellation terms, and whether samples are available through your sample programme?
- c. An indicative price per mated pair at 1 000 and at 10 000 pairs, with lead times.
- d. Can samples be delivered to Ukraine directly, or should we order through a distributor?
- e. Quote currency and validity, and a technical point of contact.

Thank you in advance.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Follow-up block (EN) — відповідь координаторові ASG

> **Репо-нота (у лист НЕ йде).** Відповідь у треді на першу відповідь Samtec ASG 2026-11-09 — уточнення, не котирування: сумісність пари підтверджено; найближчі опубліковані висоти — коди 233 і 303 (8.13 / 9.91 мм), а точні P/N, допуск висоти пари й вирівнювання — «needs Engineering confirmation»; опублікованого допуску висоти ПАРИ немає; 500 циклів специфікації на пару «не застосовувати автоматично», звіт 720050 — CLP/FTSH; комерцію перенаправлено на окрему скриньку відділу цін. **Закрито й не питається:** сумісність · опубліковані коди · цикли й звіт · маскування Parylene · струм на два піни. **Питається, вузько, щоб Engineering відповів словом:** коди 228 і 307 — наш вивід із двох каталожних прикладів (мейтована = стекер + .087″), розбіжність сайту з каталогом (≈ 0.05 мм у ряду –F–) і сітка .005″ сторінки продукту — усе дзеркало врізки [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12; допуск висоти пари — член Z-ланцюга без паспорта пари ([`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)); вирівнювання — посилання з відповіді веде на product specification CLP/FTSH, яку перший лист уже цитував. **Комерція:** адреса відділу цін прийшла від працівника в треді й на сторінці підтримки не видима (там лише служба клієнтів, куди пішла копія першого листа й відкрито окремий кейс), тож лист питає маршрут, а не пише на нову адресу (скіл `legal-business` §Доменні правила #13 ⊕ — новий адресат лише на «так» founder-а). **Немає свідомо:** трекер-ID, дат і §-рефів · номера кейсу ASG (тред його вже несе) · стійок між деками й нашого Z-бюджету.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Re: RFQ: FW-SM + CLP, 1.27 mm, 2 × 5 SMT — part numbers for 8.0 mm and 10.0 mm mated height, tolerance, samples

Hi Brian,

Thank you for the quick and clear feedback. Three questions for Engineering, so that the part numbers can be fixed:

1. **Stacker codes for 8.0 mm and 10.0 mm.** In your FW-SM catalog, the two published pairs with CLP give a mated height equal to the stacker height plus .087″ (233 → .320″, 303 → .390″). On that line, stacker code 228 gives .315″ (8.00 mm) and 307 gives .394″ (10.01 mm), both inside the .215–.335″ range for lead style –03. However, your product page says the body is set on the pin in .005″ steps, and the mated-set data on your website does not sit on that line (for the –F– plating, about 0.05 mm above it). Can codes 228 and 307 be ordered? If not, which codes do you recommend, and which document governs the nominal mated height: the catalog table or the mated-set data on your website?
2. **Mated-height tolerance.** As there is no published figure for the pair, could Engineering give the tolerance of the mated height for the codes in item 1, or the tolerances of the two halves that we should stack?
3. **Alignment.** Is an alignment-pin option available on both halves in 2 × 5, and what lateral offset does the pair accept at mating? The link in your message opens the CLP/FTSH product specification, which we have already read; we are looking for the figures for FW-SM with CLP.

For the commercial part (item 8 of our first message): that message also went to your Customer Service, which opened a separate case. Should we write to the Pricing team directly, or will that case reach them?

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 5. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) | BOM поз. 12 (пара, крок, 2 × 5, 8–10, лінії) і врізка під таблицею (присуд, каталожні висоти, «non-returnable», найслабша ланка присуду) · поз. 8 (FR4 1.6) |
| [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) | дія 1: B2B як єдиний міст Power↔RF, «standoff/PCB spacer», зазор антена↔Ti 11.85–13.85 (⊕ 2026-11-07: «робот ставить B2B на заводі» з `02_01 §6` знято — §6 цього не каже) |
| [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | член B2B у Z-ланцюзі без паспорта пари · вертикальний бюджет (лише B2B 8 під короною) · Parylene C 10 µm і маскування · −40…+85 °C |
| `tools/in_silico/scripts/52_z_stack_tolerance.py` · `cache/mechanical/z_stack_tolerance.json` | `B2B_STACK_MM`, `TOL_PZ`, просвіт над RF Deck 4.15 / 2.15 мм (§0 пп. 2, 6) |
| [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) | rollup, куди 🤖 переносить ціну пари |
| [`node_parylene_rfq`](node_parylene_rfq.md) | маска контактів мезоніна · «окремо ⊥ стеком» (п. 5c тут) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29 · HW.8 (8.7) · HW.33 · HW.11 | дім стану · Z-ланцюг · RF-макет (що може перевернути базу) · покриття |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс (рядок «Капсула електроніка») |
