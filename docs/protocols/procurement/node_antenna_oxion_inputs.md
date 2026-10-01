# Node — ККД бустер-антени на НАШІЙ землі: аркуш входу для платформи Oxion (Ignion)

> **Що це:** набір входів для безкоштовного звіту платформи Oxion виробника бустер-антен Ignion (оцінка інтеграції з узгоджувальним ланцюгом; що саме платформа приймає на вхід і як швидко відповідає — звірено з публічною частиною, §0 п.6). Предмет — **ККД бустера на землі нашого розміру**: числа, на якому стоїть ратифікований присуд «платимо ККД» ([`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md), врізка під «Чесним наслідком»), і якого немає в жодному прочитаному документі.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-24, переписано 2026-09-29 під корінь (⚖️ founder) і обвідну бустерів (⚖️ делеговано), доповнено 2026-10-01 присудом про число звіту (§0 п.5) і текстом запиту згоди (§3, EN); не подано, founder аркуша й тексту запиту ще не бачив — ⛔ до „так“ не надсилати.** Числа — дзеркало канону, дім кожного — у таблиці нижче; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.17 (нога «Oxion»).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Капсула електроніка»).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — геометрія анкера й капсули відкрита, тож завантаження огинаючої нічого не розкриває. ✅ **Умови використання прочитано 2026-10-01 — публічні, не за логіном** (розділ «Oxion™ Terms and Conditions» сторінки https://ignion.io/terms-of-use/ [HTML ✓я 2026-10-01, curl]); наш висновок — §0 п.6; клаузу про конфіденційність звіту розсуджено присудом §0 п.5 (⚖️ 2026-10-01).

---

## 0. Як користуватись

1. **Подаємо ОГИНАЮЧУ, а не розкладку.** Розкладки плати ще немає ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9), але ККД бустера задає насамперед земля, а ціль її контуру відома ([`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md): стелю Ø15.57 відкрито коренем, ⚖️ founder 2026-09-29). ⚠️ **Звіт на коло цілі — число для ІЗОЛЬОВАНОЇ огинаючої, і межею ні з якого боку він не є:** бустер випромінює землею, а наша земля не закінчується на платі — шина анкера несе анод на V−/GND ([`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)), тобто продовжується титаном у вологу деревину, а друга плата й фланець поруч можуть зсувати ККД в обидва боки. Цінність звіту — перше число з джерелом там, де зараз немає жодного, і номінали П-ланки під наш розмір.
2. **DXF — коло, згенероване в мить подачі.** Одна примітивна фігура — контур RF Deck діаметром цілі контуру; окремого генератора для неї в дереві немає й не заводимо. Якщо платформа приймає розміри формою, DXF не потрібен.
3. **Два кандидати — два звіти.** Обидва живі кандидати — в одному поданні або двома, як дозволить платформа; контур креслять під обвідну обох, тобто більший `NN02-224` (⚖️ делеговано 2026-09-29, [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md)), але ККД потрібен для обох — вибір носія стоїть саме на ньому.
4. ⛔ **Звіт — симуляція виробника над його моделлю, не вимір.** Він дає рядку `TX Antenna Gain` Link Budget значення з ДЖЕРЕЛОМ лише за письмовою згодою виробника (п.5), а вироком `≥ −2 dBi` у будь-якому разі лишається вимір — третя вісь RF-макета ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33, [`rf_mockup_bench_sheet`](../hardware/rf_mockup_bench_sheet.md)) або VNA-сесія.
5. **Відповідь у репо не комітиться — і число ККД теж: це орієнтир, публікація — за згодою** (⚖️ РАТИФІКОВАНО founder 2026-10-01 (закритим списком «одне так», за рекомендацією); підстава, ціна й найслабша ланка — [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md), врізка каналу). Звіт — конфіденційна інформація виробника (п.6), а його внутрішні моделі й номінали — ще й чужі операційні факти. ККД на 863 · 868 · 870 МГц — робочий орієнтир поза репо; сюди й у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.17 іде лише наш висновок без чисел звіту: чи змоделювано метал поруч, другу плату й кожух. У рядок `TX Antenna Gain` ([`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md)) число звіту заходить лише за письмовою згодою виробника — запит іде в тому самому поданні, що й огинаюча (§3); без згоди рядок дістає число лише з виміру макета ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33).
6. **Що каже первинка — і чого вона НЕ каже** (прочитано 2026-10-01; реєстрації й подання не робили). Джерела: умови — https://ignion.io/terms-of-use/ (розділ «Oxion™ Terms and Conditions») і FAQ — https://ignion.io/resources-support/technical-center/faq/ [обидва HTML ✓я 2026-10-01, curl]; вторинка — огляд Oxion 2.0 everythingrf.com (2025-03-13, через WebFetch-зведення). Сама платформа oxion.ai віддає машині порожню JS-оболонку — її інтерфейс не прочитано.
   - 🔴 **Звіт — конфіденційна інформація виробника.** Умови: «The use of the Services and resulting access to the reports (“Content“) includes access to Ignion Confidential Information, and if you and Ignion do not have an effective non-disclosure agreement in place, then you agree that you will not disclose Ignion Confidential Information nor any Content, except as required by law»; ліцензія на Content — «solely in connection with your design», без похідних творів. **Тому канон не може взяти число звіту без згоди:** канон публічний, тож ККД зі звіту в рядку `TX Antenna Gain` ([`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md)) — це розкриття Content без NDA. Присуд — п.5 (⚖️ 2026-10-01): число — орієнтир поза репо, публікація — за письмовою згодою виробника (запит — §3).
   - **Наші дані:** «The information provided by you to carry out the Services will be kept confidential, except as required by law»; виробник може використовувати «information about how you use and interact with the Services» для покращення сервісу. Для відкритої огинаючої це не ризик.
   - **Бенчмарки:** якщо ми розкриваємо порівняння сервісу, мусимо дати й усе для його відтворення, а виробник отримує право порівнювати наші продукти — стосується лише публікації порівнянь Oxion, не звичайного використання.
   - **Ціна:** FAQ — «Yes. You can create an account and get access to all features available, completely free of charge»; умови — «The access to the Services may be charged depending on exact service requirements». Безоплатність — для стандартних функцій, не гарантія для кожного запиту.
   - **Строк:** умови визначають «24h» як «delivery within the next working day (e.g. 12h-36h)», «Real-time» — до 30 с, «Subject to availability»; FAQ каже, що звіт, який раніше надсилали поштою, тепер показується наживо в інтерфейсі. Тож «до 24 год» — не обіцянка, а клас послуги.
   - **Вхід:** FAQ описує форму проєкту й вимог пристрою та інтерактивне налаштування «antenna location, clearance and dimension»; огляд Oxion 2.0 — аналіз Gerber-файлів. **DXF як вхід у прочитаних сторінках не названо** — п.2 лишається припущенням до першого входу в інтерфейс.
   - **Метал поруч і кожух:** публічна частина не каже, чи їх моделюють. Про кілька зʼєднаних плат FAQ прямо відсилає до окремих (платних) послуг виробника — тобто нашу другу плату звіт найімовірніше не врахує, і висновок мусить це назвати (рядки «Друга плата» й «Кожух» таблиці §1).

---

## 1. Входи — і дім кожного

| Вхід | Значення | Дім (правити там) | Примітка |
|---|---|---|---|
| **Смуга** | 863–870 МГц; робоча частота тракту 868.2 МГц | [`03_05 §2.1`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md) | просити ККД у трьох точках: 863 · 868 · 870 |
| **Контур плати (земля)** | коло **Ø ≈ 20.0 мм** — ЦІЛЬ контуру з парою B2B, не номінал розкладки (перераховано 2026-09-30 з кільцем кишені вента; до того 19.5); з rigid-flex (переглядається, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29) — **Ø ≈ 18.5** | [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) (ціль під обвідну бустерів; купол Ø29.8 застосовано 2026-09-30) | подати як «target board outline, not final»; якщо платформа дає другий прогін — і менше коло: нижча земля дає нижчий ККД, тобто це консервативний край |
| **Плата** | FR4, 4 шари, 1.6 мм | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 8 | — |
| **Кандидат 1** | `NN02-224` RUN mXTEND (12 × 3 × 2.4 мм) | [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) (таблиця ККД) | опублікований ККД на землі 40 × 20 мм — найближчий до нашої серед прочитаних |
| **Кандидат 2** | `NN02-201` ONE mXTEND (7 × 3 × 1 мм) | [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) | опублікований лише на 51 × 40 мм і 880 МГц |
| **Метал під платою** | диск Ti-6Al-4V (катодний фланець **Ø29.8** з 2026-09-30 — корінь [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33, виведено з цілі контуру плати; по вушках байонета Ø33.8 — верхня межа ПОТОЧНОЇ моделі: вушка ратифіковано всередину контуру на піднятому комірі, [`02_02 §4.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), а комір не змодельовано й тримається ⏸ на рух кореня, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33) під нижньою платою; зазор антена↔Ti **11.85–13.85 мм** (від Ø купола не залежить — стек pogo · FR4 · B2B 8–10 · FR4, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9) | [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md), дія 1 | якщо платформа приймає «nearby metal / enclosure» — подати; якщо ні — записати, що звіт його НЕ врахував |
| **Земля поза платою** | анод Zone 1 на V−/GND через шину анкера — титан у стовбурі, у вологій деревині | [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | платформа це навряд чи моделює; назвати в поданні й у висновку як неврахований член |
| **Друга плата** | Power Deck із власною землею нижче RF Deck на 8–10 мм (B2B) | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 | те саме: подати, якщо є поле |
| **Кожух** | PEEK-радом Ø29.8 (`tools/cad/cem/radome.json`, корінь застосовано 2026-09-30 — [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md)), стінка 2.0 мм, порожнина 13.0 мм, плоска корона | `tools/cad/cem/radome.json` · [`01_04 §5.5`](../../01_04_CODIT_and_Xylemointegration.md) | ε_r PEEK — з даних платформи, не наше число |

**Свідомо НЕ подаємо:** «keep-out 40 × 12 мм» з evaluation-плат — це розкладка ВИРОБНИКА, не наша вимога · номінали П-ланки з app-note — вони адаптуються під розмір плати, їх і питаємо · наші вимоги дальності й SF — звіт про ККД від них не залежить.

---

## 2. Що забрати зі звіту

- ККД (radiation efficiency) на 863 · 868 · 870 МГц для кожного кандидата — робочий орієнтир поза репо (§0 п.5): у рядок `TX Antenna Gain` ([`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md)) він заходить лише за письмовою згодою виробника; тригер гілки (б) судить виміряний ККД, а орієнтир лише підказує, чи той близько.
- Топологію й номінали узгоджувального ланцюга під огинаючу — як орієнтир для посадкових місць, не як BOM.
- Чи змоделювано Ti-фланець, другу плату й кожух: без цього ККД завищено, і висновок має це назвати.

---

## 3. 📤 Запит згоди на публікацію ККД (EN)

> **Репо-нота (у лист НЕ йде).** Присуд — §0 п.5 (повна форма — [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md), врізка каналу). Запит іде в ТОМУ САМОМУ поданні, що й огинаюча ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.17, нога «Oxion»): у поле коментаря проєкту, якщо інтерфейс його має, інакше — листом виробникові; адреси в дереві немає, а інтерфейс платформи не прочитано (§0 п.6), тож канал обирається в мить подачі. Просимо згоди на ОДИН клас чисел — ККД нашої огинаючої для двох кандидатів у трьох точках смуги, з атрибуцією — і прямо відмовляємось публікувати сам звіт, номінали ланки й моделі: що вужче прохання, то менше лишається тлумачити (найслабша ланка присуду). **Немає свідомо:** чисел контуру й зазорів (їх несе саме подання) · дослівної клаузи умов (цитата — §0 п.6; адресат знає власні умови) · трекер-ID, канон-рефів, дат і гліфів. Founder тексту не бачив — ⛔ до «так» не надсилати; надсилає founder разом із поданням огинаючої.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Oxion report for our board outline — permission to publish the efficiency figures

Dear Ignion team,

We are submitting a project to Oxion: a small round board in a sealed sensor capsule for forest monitoring (863–870 MHz), with two of your booster antennas as candidates.

**Why we are asking.** The technical specification of our device is openly published in a public repository, including the radio link budget, where the antenna gain is still a placeholder. We have read the Oxion Terms and Conditions and understand that the reports include Ignion Confidential Information and that we may use them only in connection with our design. Without your consent we will treat them exactly that way and keep every figure for internal use only.

**Our request.** May we publish, with attribution to Ignion and Oxion, the simulated radiation efficiency of each of the two boosters on our board outline at 863, 868 and 870 MHz? These figures would appear in the link budget of our published specification, labelled as your simulation for our outline — not as a measurement and not as a datasheet value of your product. We would not publish the report itself, the matching network values, your models or any other part of the report.

If you agree, a short written confirmation by reply is enough. If you would prefer a different attribution, specific wording, or to review the text before publication, please tell us. If the answer is no, we will keep the figures for internal use only and take the numbers for our specification from our own measurements.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 4. Cross-references

| Ресурс | Навіщо |
|---|---|
| [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) | клас антени, таблиця ККД, присуд «платимо ККД» і присуди про цей канал і про число звіту |
| [`rf_mockup_bench_sheet`](../hardware/rf_mockup_bench_sheet.md) | вимір, що лишається вироком |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс |
