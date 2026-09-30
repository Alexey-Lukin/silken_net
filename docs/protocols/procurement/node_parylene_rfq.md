# Soldier — конформне покриття Parylene C 10 µm (CVD): лист сервісові нанесення

> **Що це:** RFQ-аркуш для **сервісу нанесення Parylene C** (CVD-камера, послуга на НАШИХ платах). Покриття — дві круглі плати капсули Soldier (Power Deck і RF Deck). Лист питає маскування, товщину й спосіб її виміру, engineering run, партію, ціну, строк і найперше — **чи беруть замовлення з України**. Рішення «Parylene C 10 µm» уже ухвалене ([`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)), тож лист його не ставить під сумнів, а купує виконання.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-24, виправлено 2026-09-29 (пʼєзо зрізано — пункт маскування знято; контур — під рух кореня; EDLC — THT), не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Адресата не обрано: лист один і без імені в тексті, **адресата обирає founder** серед чотирьох EU-кандидатів ([`ua_vendor_map §5`](ua_vendor_map.md), рядок «Parylene C, CVD-нанесення»). Числа дзеркалять доми, і дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.11.
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Капсула електроніка» · hard-constraint дім §4.D).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)): специфікація відкрита, CDA — лише на комерційні умови.

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Кандидати — CPS-IEP (PL) · SCS (CZ/DE) · Plasma Parylene Systems (DE) · Variosystems (DE), і всі поза UA, тому **лист англійською**. UA-носія desk-пошук не знайшов двічі. ⊕ **Одне імʼя, яке називав канон, звірено 2026-09-24 окремо:** [`02_06 §8.1`](../../02_06_Unit_Economics_and_BOM.md) п. 3 віддавав Parylene-CVD черкаському **SVS-ARTA**, але публічний перелік послуг компанії — чисті приміщення, вентиляція, 3D-сканування й друк, без CVD-камери; канон виправлено, рядок із підставою — [`ua_vendor_map §5`](ua_vendor_map.md). EU-адресат лишається.
2. **Базовий кейс + дельти, не прайс на все.** Базовий кейс — **кожна з двох плат окремо, до зʼєднання мезоніном**, ціна за плату. Дельта — зʼєднана пара (стек із двох плат). Порядку «покриття ⊥ зʼєднання» канон не несе, тож лист питає, яка з гілок ліпша, і просить ціну на обидві.
3. **Габарит — орієнтовний і позначений так у листі.** Розкладки плат немає ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9 ⚪). Стара стеля `≤ Ø15.57 − 2·t_коміра` більше не діє: корінь відкрито заради плати (⚖️ founder 2026-09-29), і ціль контуру тепер живе в [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) — під обвідну бустерів (⚖️ делеговано 2026-09-29), і з парою B2B, і з rigid-flex у межах 18–20 мм. Лист каже «about 18–20 mm; the housing is being sized around the final layout». ⛔ Точні числа цілі в лист не йдуть: це ціль калькулятора площі, а не креслярський розмір.
4. **Маскувальний перелік ширший за ногу трекера.** HW.11 перелічував «pogo-пади і пʼєзо-вікно» (пʼєзо-вікно зникло разом із пʼєзо, ⚖️ founder 2026-09-29, [`02_01 §6`](../../02_01_Hardware_Architecture_and_BOM.md)), канон [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) п. 1 — «коннектори/піни». Звірка з BOM дала ще **BME280**: канон кладе цей датчик вологості, температури й тиску «на платі рівно напроти» PTFE-вента ([`02_01 §3.4`](../../02_01_Hardware_Architecture_and_BOM.md), ADR 🟡), тож під Parylene він перестане бачити повітря. Лист називає його «if fitted», бо ADR не валідовано. ⊕ Порядок «заводська прошивка ⊥ покриття» розсудив присуд SEC.24 ([`03_05 §3.3`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md), ⚖️ делеговано 2026-09-27): покриття серії — після RDP L2. SWD-пади лист питає пунктом «d»: якщо coater маскує дрібні пади, вони лишаються відкритими на всіх платах серії заради spare-резерву L1 (⚖️ founder 2026-09-27, §0 п. 7).
5. **⚠️ Кордон: відправка ПЛАТИ — це не відправка листа.** Заповнена плата несе STM32WLE5CC з апаратним AES (чіп на платі, не модуль — ⚖️ founder 2026-09-25, [`02_01 §3`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 1). Її вивіз на покриття й повернення є міжнародною передачею товару за ЗУ № 549-IV, а «залізного» маршруту деконтролю в українському праві може не бути ([`export_control_ua`](../legal/export_control_ua.md) §4; дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.25). **Лист цього не розсуджує** і тримає обидві гілки відкритими. П. 7 питає, чи годиться engineering run на **репрезентативних тестових платах** (той самий контур, конектори й висоти, можливо частково запаяні). Бере він цю гілку чи ні — рішення founder-а, не листа.
6. **Пʼєзо в листі більше немає** — його зрізано з Солдата (⚖️ founder 2026-09-29, [`02_01 §6`](../../02_01_Hardware_Architecture_and_BOM.md)). Разом із ним пішли пункт маскування «c» редакції 2026-09-24 (решта пунктів зсунулась на літеру: BME280 — «c», SWD-пади — «d»), смуга 2–8 кГц і застереження про числа демпфування. Історії Sylgard лист не несе й тепер: відмову переприсуджено 2026-09-29 з іншими підставами ([`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)), а вендорові Parylene вона не потрібна.
7. **Лист не блокує TRL 4 і пілот:** прототипи й пілотна L1-партія покриваються вручну в себе поліуретаном HumiSeal 1A33, а Parylene — це серія ([`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), ✅-примітка; пілот — ⚖️ founder 2026-09-27, [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.11; продукт — ⚖️ founder 2026-09-27). Лист прямо каже вендорові про прототипи й пілот, щоб мала перша партія не читалась як нерішучість. SWD-пади лист ПИТАЄ пунктом «d»: серійним платам після RDP L2 вони не потрібні, але spare-резерв L1 іде під тим самим шаром і мусить лишитись перепрошивним (⚖️ founder 2026-09-27, [`03_05 §3.6`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md)) — відповідь на П. 2 («smallest feature you can mask») вирішує, чи spare лишається під Parylene, чи йде маршрутом пілоту. ⚠️ UART-пади BFU-лоадера, якщо його лишать ([`03_05 §3.3`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md), SEC.24), додадуться до «d».
8. **Відповідь у репо не комітиться:** ціни, внутрішні режими камери й номери документів вендора — чужі операційні факти. У [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.11 іде лише наш висновок.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Вступ: що й навіщо** | [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (Parylene C 10 µm CVD — серія; прототипи й пілот — HumiSeal 1A33 вручну) | фактом | історія Sylgard (⚖️ переприсуджено 2026-09-29) |
| **Плати: два поверхи, мезонін** | [`02_01 §1`](../../02_01_Hardware_Architecture_and_BOM.md) (Power Deck + RF Deck) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 8 (FR4, 4 шари, 1.6 мм, HASL/ENIG) · поз. 12 (мезонін: Samtec FW-SM/CLP 1.27 мм, mated height 8–10 мм — носій ⚖️ 2026-09-24, котирування не було; альтернативи Hirose DF40TC 0.4 мм · Molex SlimStack) | поверхи й плата — фактом; мезонін — «not selected, leading candidate 1.27 mm», альтернативи — «finer-pitch» | P/N мезоніна |
| **Контур ≈ 18–20 мм** | [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) (ціль — під обвідну бустерів, з обома міжзʼєднаннями в межах 18–20 мм; корінь відкрито ⚖️ founder 2026-09-29) · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9 (розкладки немає) | «about 18–20 mm, sized around the final layout» — **orientational** | точні цілі калькулятора · прилив · комір · вушка байонета |
| **Висоти компонентів** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 3 (EDLC горизонтальний THT, H 5.2 мм; reflow вендор забороняє — пайка двох виводів, [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md)) · найвищої деталі RF-деку ще немає: модуль LoRa-E5 (2.5 мм) знято з плати 2026-09-25, а P/N фронтенду не обрано ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9) | «about 5 mm» · «under about 2.5 mm» (верхня межа серед прочитаних кандидатів) | P/N (Eaton `KR-5R5H474-R`) |
| **Маскування: pogo-піни** | [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (2 піни, нижній шар, пад Ø2.5) · [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (корпус Ø1.02 або 1.27, хід 1.40 мм) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) п. 1 | вимогою: кінчик вільний, плунжер рухається; спосіб — питанням | P/N піна (HW.9) · фініш піна 0.76 / 1.27 µm · сила пружини |
| **Маскування: мезонін** | [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) п. 1 («селективне маскування коннекторів/пінів») · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 | вимогою | — |
| **Маскування: d — SWD-пади** | [`03_05 §3.6`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md) (spare-резерв L1 під серійним шаром, ⚖️ founder 2026-09-27) · розкладки немає ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9) | вимогою — відкриті на всіх платах; розмір і кількість — «pending» | RDP-рівні й навіщо резерву перепрошивка — наша справа |
| **Маскування: BME280** | [`02_01 §3.4`](../../02_01_Hardware_Architecture_and_BOM.md) (LGA 2.5 × 2.5 мм; в окремій кишені, запечатаній до PTFE-вента — ⚖️ 2026-09-29, «рівно напроти вента» спростовано; ADR 🟡) | вимогою, «if fitted» | статус ADR · VPD і навіщо він |
| **Середовище** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (−40…+85 °C) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) п. 3 (усередині повітря, опційно осушувач) · [`02_02 §3.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (ціль IP) | фактом; «багаторічна служба» — без числа | «20 років» (дім має анкер, не капсула) |
| **1 замовник з України** | нога 👤 [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.11 («чи беруть одиничне замовлення з України: мито, експорт, мінімальна сума») | **першим питанням** | наш експорт-контроль (§0 п. 5) — наша справа, не вендора |
| **2 маскування** | рядки вище | питанням: спосіб, мінімальний елемент, формат креслення | ⛔ масочне креслення до листа не додається (розкладки немає) |
| **3 товщина 10 µm** | [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (рекомендація 10 µm; діапазон таблиці 5–25) | 10 µm — вимогою; допуск, метод, звіт, затінені зони — питанням | діапазон 5–25 |
| **4 підготовка й адгезія** | — (канон мовчить) | питанням | — |
| **5 процес і компоненти** | — (вакуум CVD; EDLC — [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md)) | питанням | — |
| **6 окремо ⊥ стеком** | — (порядку канон не несе) | базовий — окремо; стек — дельтою | — |
| **7 engineering run** | нога [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.11 (1–3 плати) · §0 п. 5 (репрезентативні плати) | питанням, обидві гілки | причина гілки «тестові плати» (кордон) |
| **8 температура служби** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (−40…+85 °C) | «підтвердіть або виправте» | — |
| **9 доробка** | [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) таблиця («Re-work потребує плазмового знімання») | питанням | наш висновок про спосіб знімання |
| **10 серія** | [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) (ціновий рівень 1K) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) (ціни на партію 10 000) | орієнтир ціни на 1 000 і 10 000 плат | наша цільова собівартість (< $11 за електроніку) |
| **11 якість** | — | питанням (IPC-CC-830 / IPC-A-610 — прикладами, не вимогою) | — |

---

## 2. Dispatch checklist

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Адресата обирає founder** з чотирьох EU-кандидатів; текст той самий, імені в ньому немає.
- [ ] 👤 **Перш ніж везти плату через кордон** (не перш ніж надіслати лист): [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.25 і §0 п. 5. Гілку «репрезентативні тестові плати» лист тримає відкритою (п. 7).
- [ ] 👤 **Після відповіді:** висновок → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.11; перелік масок → вхід розкладки HW.9 (масочне креслення робиться разом із нею); цін і режимів не комітити (§0 п. 8).

---

## 📤 Dispatch block (EN) — Parylene coating service email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): Parylene C · 10 µm · два поверхи на мезоніні · FR4 4 шари 1.6 мм HASL/ENIG · контур ≈ 18–20 мм як ціль · висоти ≈ 5 / ≈ 2.5 мм · EDLC THT · 2 pogo-піни на нижньому шарі · мезонін 1.27 мм, стек 8–10 мм, або rigid-flex · BME280 LGA 2.5 × 2.5 мм (if fitted) · SWD-пади відкриті на всіх платах (d) · −40…+85 °C · прототипи й пілот — HumiSeal 1A33 вручну. Питає те, чого канон свідомо не несе: маршрут маскування · допуск і метод товщини · підготовку й адгезію · сумісність компонентів із вакуумом · порядок «окремо ⊥ стек» · engineering run · доробку · партію, ціну, строк · умови для замовника з України. **Немає свідомо:** пʼєзо (зрізано) · точних цілей калькулятора · P/N · експорт-контролю · SVS-ARTA · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** RFQ — Parylene C conformal coating, 10 µm, on two small round PCB assemblies: masking, thickness verification, engineering run, and orders from Ukraine

Dear colleagues,

**About us and the purpose of this enquiry.** We are an R&D project in Ukraine developing a sensor node for forest monitoring. A titanium anchor is installed in the trunk of a living tree, and a small sealed capsule with the electronics sits on top of it. For series production we intend to protect the electronics with a **Parylene C** conformal coating applied by CVD, **10 µm** thick, and we are looking for a coating service. Our prototypes and the pilot batch are coated by hand in-house; Parylene is for the series, which we would start with a small engineering run (question 7).

This is a request for information and an indicative quotation, not yet an order. Answering commits neither side to anything, and inline answers in this email are fine. The board layout is **not frozen yet**, so all dimensions below are indicative, and drawings will follow with an order.

**The assemblies to be coated (indicative)**

- **Two printed circuit board assemblies per node**, stacked one above the other and joined by a board-to-board mezzanine connector: a power board and a radio/microcontroller board.
- **Outline:** each board is round, **about 18–20 mm in diameter**. The housing is being sized around the final layout, so the outline may still change.
- **Board:** FR4, 4 layers, 1.6 mm thick, surface finish HASL or ENIG.
- **Components:** SMD parts plus one through-hole part: a horizontal supercapacitor about 5 mm high, the tallest component; everything else stays below about 2.5 mm (the radio is a bare chip with its own RF front-end, parts not yet selected). The mezzanine connector pair is not selected yet: our leading candidate has a 1.27 mm pitch and a stack height of 8–10 mm, and finer-pitch parts are among the alternatives. A rigid-flex board (two rigid round sections joined by a flexible section) is also being considered instead of the connector pair.
- **Operating conditions:** inside a capsule sealed with an O-ring, filled with air (possibly with a desiccant); the temperature ranges from −40 to +85 °C, over many years of outdoor service.

**What must stay free of coating**

- **a. Two spring-loaded contact pins (pogo pins)** on the underside of the power board, body diameter about 1 mm, soldered to 2.5 mm round pads. They make the electrical connection to the anchor, so the contact tip must stay bare and the plunger must keep moving freely through its full travel of about 1.4 mm.
- **b. The mezzanine connector** — the mating contacts of both halves.
- **c. An environmental sensor** (temperature, humidity and pressure; LGA package, 2.5 × 2.5 mm), if fitted in the final design. It measures the surrounding air through its vent hole, which must stay open.
- **d. A small group of programming test pads** on one of the boards (their size, count and layout are not fixed yet). They must stay uncoated on every board, so that a reserve of boards can be reprogrammed later.

**Please tell us**

1. **Working with a customer in Ukraine.** Do you accept orders from Ukraine, including a first engineering run of one to three boards? Is there a minimum order value? How are shipments handled in both directions: which customs procedure do your customers normally use for boards sent in for coating and returned, who acts as importer, who pays duty and VAT, and which courier routes work for you?
2. **Masking.** How would you mask each item a–d above: boots, caps, tape, liquid mask or another method? Is masking spring-loaded pins routine for you, and how do you keep coating out of the gap between plunger and barrel? What is the smallest feature you can mask, and how sharp is the edge of the coated area? What do you need from us to define the masking: a drawing, a marked-up photo, a CAD file, and in which format?
3. **Thickness.** What tolerance do you hold on 10 µm? How do you measure it — for example on witness slides coated in the same run — and do you issue a thickness report per run? How does the thickness vary under and around tall components, under the mezzanine connector and in narrow gaps?
4. **Preparation and adhesion.** How do you clean the boards before coating, and do you use an adhesion promoter? What do you require from incoming boards: flux type (no-clean or washed), cleanliness level, packaging, handling?
5. **Process compatibility.** Are there components that you would not coat, or that cannot go through your deposition process under vacuum — for example the through-hole supercapacitor? Is there anything else in the design you would advise us to change for coating?
6. **Separate boards or the joined pair.** Our base case is to coat each of the two boards separately, before they are joined. Would you recommend that, or coating the joined two-board stack? Please price both and explain why. If we move to the rigid-flex board, what changes for you?
7. **Engineering run.** For one to three boards (or pairs): what do you deliver — thickness data, photos, verification of the masking? Can the run be done on **representative test boards** with the same outline, connectors and component heights, possibly only partially populated, before the functional boards exist? Price and lead time.
8. **Service temperature — please confirm or correct.** What long-term service temperature in air does your data give for Parylene C? Is −40 to +85 °C, over many years, within it?
9. **Rework.** If a coated board needs repair, can the coating be removed locally, and how? Can you do it, or can we?
10. **Series.** Minimum batch size, and an indicative price per board at 1 000 and at 10 000 boards, with lead times.
11. **Quality and documents.** Your quality system (for example ISO 9001 or ISO 13485: certificate number, scope, validity). The standard you work to and inspect against (for example IPC-CC-830 or IPC-A-610). The documents you issue per lot.
12. **Commercial.** Quote currency and validity, payment terms, and a technical point of contact.

**Confidentiality.** The technical specification of our device is openly published, so no confidentiality agreement is needed to discuss it. We are happy to sign your standard agreement covering commercial terms (prices, schedules, quality data).

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 3. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | рішення Parylene C 10 µm · маскування коннекторів і пінів · відмова від заливки (⚖️ переприсуджено 2026-09-29) |
| [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | ціль контуру плати · пади pogo-пінів · габарит піна |
| [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_01 §3.4`](../../02_01_Hardware_Architecture_and_BOM.md) | BOM плати (PCB, мезонін, EDLC) · BME280 і його вент |
| [`02_06 §8.1`](../../02_06_Unit_Economics_and_BOM.md) | черкаський хаб, якому канон приписує Parylene (§0 п. 1) |
| [`export_control_ua`](../legal/export_control_ua.md) | чому відправка ПЛАТИ через кордон — окреме питання (§0 п. 5) |
| [`ua_vendor_map`](ua_vendor_map.md) · [`rfq_registry`](rfq_registry.md) | адресати (EU-кандидати, UA-носія немає) · procurement-індекс |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.11 · HW.9 · BIZ.25 | дім стану · розкладка плат · експорт-контроль |
