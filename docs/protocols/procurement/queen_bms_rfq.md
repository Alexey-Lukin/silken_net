# Queen — BMS 4S LiFePO4 (JBD-клас): технічний запит виробникові або продавцеві

> **Що це:** RFQ-аркуш — технічний запит до **JBD (Jiabaida)** або до продавця з доступом до інженерів виробника щодо двох SKU шортлиста BMS Королеви. Предмет — **три питання, що розсуджують вибір SKU**, і те, що з тієї самої відповіді чекає гілка charge-protect. Прайс тут не предмет. **Лист питає й висновків не повідомляє:** рекомендацію «DP04S007» зроблено на ОПУБЛІКОВАНИХ максимумах, і в лист вона не йде.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-24, не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Адресат — адреса зі сторінки Contact магазину `jiabaida-bms.com` (2026-11-08, з браузера founder-а): About називає Shenzhen Jiabaida з дочірньою Dongguan Jiabaida — ту саму назву видавця, що в посібнику JBDTools (§0 п. 6), адреса стоїть на домені `@jiabaida.com`, і в домену є MX-записи — домен пошту приймає, а чи існує сама скринька, MX не каже (сама адреса — у журналі надісланого, у репо не кладемо); форма на тій самій сторінці — запасний шлях. ⚠️ Власника домену магазину не звірено ([`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) §0): About — самоопис сайту, а корпоративний `www.jiabaida.com` системним резолвером резолвиться, але браузер founder-а його не відкрив (шортлист мав там 403 і блок Zscaler). Тож текст і далі написано так, щоб продавець міг переслати його виробникові без правок. Числа дзеркалять доми, і дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15 (нога «спитати JBD») і HW.16 (charge-protect: розсуджує та сама відповідь).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Брама Queen» · hard-constraint дім §4.D).

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Перший адресат — JBD, а якщо виробник не відповідає, то продавець, який має доступ до виробника (агент, дистриб'ютор). Перший рядок листа просить продавця переслати текст інженерам виробника, бо на пп. 2–4 відповідає лише виробник. Адресати поза UA, тому **лист англійською**.
2. **Базовий кейс + дельта, не прайс на все.** Базовий кейс — **JBD-DP04S007 V1.5 LiFePO4 4S, 60 А**. Дельта — **JBD-SP04S034, 60-А варіант**: саме він перевертає вибір, якщо його типовий струм укладеться в бюджет (нога 🔗 HW.15 «BMS SKU», «Що перевертає вибір»). ⛔ Файл SP04S028A і модель SP04S020 **свідомо не питаємо**: файл суперечить сам собі щодо SKU, а spec-sheet на SP04S020 не знайшли ([`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) §1). Відповідь на ці дві моделі — це вже ширша робота, ніж потрібна ⚖️.
3. **Яке питання розсуджує яку ногу.** П. 1 (типовий running-струм) розсуджує вибір SKU. П. 2 (UART з боку навантаження) закриває «Ціну» рекомендації: у DP04S007 немає дротової телеметрії. П. 3 (чи записувані пороги холоду, окремо для заряду й розряду) потрібен і HW.15, і HW.16. П. 4 (чи триває розряд при закритому charge-FET), п. 3 d–f (чи переживає поріг скидання) і гарячий поріг заряду в п. 5 — це входи HW.16. Відповідь «так» дає гілку «BMS-інтегроване відсікання», «ні» — гілку «дискретний P-MOSFET». **Лист питає обидві гілки й жодної не замовляє** (скіл `legal-business` §Доменні правила #4).
4. **Що подано як НАШУ вимогу, а що питанням.** Бюджет **≤ 15 мА** — це наша вимога: межа гейта моделі на 10-хв каденсі флоту (⚖️ FW.64 2026-09-28, перемикається разом з ARCH.75), `tx_sessions_per_day=144 quiescent_ma=35.2` → EXIT 0, `35.3` → EXIT 1, тобто ≤ 15.2 мА (ККД buck'а 0.88 за TI SNVSB99C, не безпідставні 0.95), у лист — округлено вниз до 15 (на годинному каденсі межа 17.3). Щоб число не підказало відповіді, лист просить типове **і** максимальне значення з умовами. Вимога канону «заряд заблоковано нижче +1 °C» теж стоїть як вимога. **Нашої деривації «≥ +4 °C»** (+1 плюс допуск ±3 °C), яку рекомендує HW.16, у листі **немає**: вона ще не присуд, тож лист питає діапазон, крок і точність поля.
5. **Відповідь у репо не комітиться.** Ціни, внутрішні дані тестування й переписка продавця — чужі операційні факти. У [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15/HW.16 і в шортлист іде лише наш висновок; числа виробника — з посиланням на документ, який він надішле.
6. **Що публічна документація виробника вже відповіла (звірено 2026-10-05).** Посібник JBDTools v1.1 (Dongguan Jia Bai Da; копія на `cdn.hackaday.io/files/1628066965491904/User manual for v1.1.pdf` — текст виробника, чужий хостинг), розділ 2.4: серед базових параметрів захисту — «charging high and low temperature, discharge high and low temperature … Customers can set parameters according to their own need», із ОКРЕМИМИ полями `ChgUTP` і `DsgUTP`, які пише в плату кнопка «Write parameters». Тож на рівні класу відповідь на п. 3a — «так, окремо» — уже є текстом, а не скріншотом ([`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) §2 п. 2). ⊕ **Звірено 2026-11-08 перед «так» — увесь лист, кожен пункт проти аркушів DP04S007 V1.5 і SP04S034 A04, посібника JBDTools v1.1, «JBD BMS Tools instructions for RS485/UART» (Dongguan Jiabaida, ревізія A0 від 2021-06-03) і публічного протоколу V4 (скіл `legal-business` §Доменні правила #14).** Стали проханням підтвердити або фактом у листі: 2c (ізольовані RS485 і UART — «Not supported» в аркуші V1.5) · 2e (протокол V4 зве себе загальним) · 3a (окремі поля `ChgUTP` ⊥ `DsgUTP`) · 3d («Read parameters», розділ 4.3.1; транспорт RS485/UART — розділ 3.1) · 4c (самовідновлення після холоду — §4.5.2 обох аркушів) · §5 (гарячий поріг заряду 62/65/68 °C, відпускання 52/55/58 °C — в обох аркушах; записуваність — посібник, на рівні класу). 3c просить дані, а не дозвіл: кадр «0xA5-read / 0x5A-write» з адресою регістру в полі команди — протокол V4, пароль Bluetooth блокує читання й запис — інструкція 4.5.4. 2b називає розбіжність: аркуш V1.5 дає пін 4 «UART – VDD 5V», специфікація V1.7 (ревізія A05) — B+. Питаннями, на які жоден із цих документів не відповідає, лишаються: 1a–d (типовий струм, поріг сну, розкид) · 2a (що саме ламає UART з боку навантаження) · 2b (який пін 4 на V1.5 і струм із нього) · 2d · 3a (діапазон, крок, точність) · 3b · 3c (адреси регістрів, масштаб, інші кроки розблокування) · 3e–g · 4a–b (лише заряд чи й розряд; body-diode) · 4c (чи відновлення діє й у сні, §4.8) · §5 (нижче −20 °C; гарячий поріг — діапазон, крок, точність) · 6a–e. Число ≤ 15 мА переміряно того ж дня: `quiescent_ma=35.2` при `tx_sessions_per_day=144` — EXIT 0, `35.3` — EXIT 1.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Застосування** | [`02_05 §3`](../../02_05_Queen_Hardware_and_Starlink.md) (12 В LiFePO4 20 А·год · 50-Вт панель · MPPT · DC-DC) · [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) поз. 5–7 · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) (усередині корпусу взимку −20 °C) | фактом | Phase 3 (Starlink, 40 А·год / 100 Вт) — не базовий кейс · модель MPPT (Victron) — лист каже «MPPT solar charge controller» |
| **Вимоги 20 А / 50 А** | [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) поз. 8 | вимогою | — |
| **Базовий кейс + альтернатива** | [`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) §1 · нога 🔗 [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15 «BMS SKU» | дві моделі без ранжування | наша рекомендація і її підстава · SP04S028A-файл · SP04S020 |
| **1 self-consumption** | шортлист §1 (≤ 10 / ≤ 25 мА running) · шортлист §3 (умова сну «no current»; поріг не наведено) · `tools/firmware/queen_energy_budget.rb` (`quiescent_ma` 20 = лише Victron; на 10-хв каденсі FW.64 гейт тримає до 35.2, отже на BMS ≤ 15.2 мА) | ≤ 15 мА (межа 15.2, округлено вниз) — **нашою вимогою**; типове й максимальне, умови й розкид — питанням | баланси Wh/добу, EXIT-коди, таблиця шортлиста §3 · «що перевертає вибір» |
| **2 UART з боку навантаження** | шортлист §4 (цитата DP04S007 стор. 14; SP04S034 стор. 3 і 15) · [`02_05 §3`](../../02_05_Queen_Hardware_and_Starlink.md) (контролер живиться від пакета через DC-DC — отже він і є навантаженням) | цитатою виробника; «чому» · ізолятор на нашому боці — питанням; пін 4 роз'єму — розбіжністю аркуша V1.5 («UART – VDD 5V») і специфікації V1.7 A05 (B+, шортлист §6); ізольовані RS485/UART («Not supported» у V1.5) і єдність протоколу (V4 зве себе загальним) — проханням підтвердити | README `esphome-jbd-bms` і його «tested» (варіант 100 А на ESP32) · ESP32 ⊥ STM32 · наш висновок «дротової телеметрії немає» |
| **3 пороги холоду** | шортлист §1 (дефолти й допуски) · шортлист §2 п. 1–2 (налаштовуваність на рівні класу — посібник JBDTools v1.1, §0 п. 6; протокол V4 без регістрів порогів) · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) п. 1 (+1 °C) · нога 🔗 HW.16 «charge-protect» (поріг РОЗРЯДУ теж перепрограмовується) | +1 °C — вимогою; дефолти — цитатою datasheet; окремість полів · запис · читання назад — проханням підтвердити (посібник JBDTools v1.1 · «JBD BMS Tools instructions» · протокол V4 — §0 п. 6); діапазон · крок · точність · адреси регістрів · розблокування — питанням | **«≥ +4 °C»** (наша деривація, рекомендація HW.16) · «небезпечне значення і є дефолтом» |
| **3 d–g стійкість налаштувань** | нога 🔗 HW.16 «charge-protect», «Ціна» (заводський дефолт повертається мовчки при заміні плати чи скиданні) · шортлист §1 (варіант «з підігрівом» 0 °C) | питанням: енергонезалежність · що повертає дефолт · заводське передналаштування · підігрів — інше залізо чи інші налаштування | наш детектор тихого дефолту (DS18B20 + VE.Direct) і те, що коду під нього немає |
| **4 розряд при закритому charge-FET** | шортлист §2 п. 3 (цитата §4.5.2; окремі біти bit5 ⊥ bit7) · нога 🔗 HW.16 «charge-protect» · навантаження: модель `queen_energy_budget.rb` (десятки мА безперервно) · [`02_05`](../../02_05_Queen_Hardware_and_Starlink.md) «Пікові струми SIM7070G» (2 А — на шині VBAT 3.7 В модему) | цитата — «не можемо прочитати однозначно»; body-diode — питанням; самовідновлення — цитатою §4.5.2 і проханням підтвердити його й у сні (§4.8); імпульс — «below 1 A»: на 12-В боці 2 А × 3.7 В / (12 В × 0.88) ≈ 0.70 А, перераховано тут (ККД buck'а — TI SNVSB99C, як у §0 п. 4) | «≈ 2 А» як струм крізь BMS (канон ставить 2 А на системний рівень без перерахунку — вимога від цього лише консервативніша, у лист це не йде) · номери бітів протоколу · наш висновок «гасне при −15…−17 °C» (у листі лише питання про відновлення) |
| **5 робоча температура** | шортлист §1 (−20…+75 · −30…+75) · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) (−20 °C) · [`02_05 §4а.1`](../../02_05_Queen_Hardware_and_Starlink.md) і [`02_05 §4а.4`](../../02_05_Queen_Hardware_and_Starlink.md) (заряд комірки ≤ +45 °C; літня точка ≈ +55 °C) | фактом і питанням; +45 °C — вимогою; дефолт гарячого порога заряду — цитатою обох аркушів (62 / 65 / 68 °C, відпускання 52 / 55 / 58 °C); окремість від порога розряду — проханням підтвердити; діапазон · крок · точність — питанням; −20 °C і +55 °C подано як точку проєкту й розрахунок | «без запасу» (наш висновок) · «Victron сам заряд за перегрівом не відсікає» (наш висновок з мануалу) |
| **6 документи, зразки** | шортлист §0 (власника домену `jiabaida-bms.com` не звірено) · шортлист §2 п. 2 (перелік полів — посібник JBDTools v1.1, §0 п. 6) · шортлист §6 (ревізія V1.7) | питанням: діапазони й дефолти по моделі (поля посібник називає) · ревізія плати, яку відвантажують (6e) | — |

---

## 2. Dispatch checklist (👤)

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Адресат:** JBD (бізнес-контакт на домені `@jiabaida.com` — шортлист §0) або продавець. Якщо лист іде продавцеві, перший абзац уже просить переслати його виробникові; нічого не міняти.
- [ ] 👤 **Після відповіді:** SKU → нога 🔗 HW.15 «BMS SKU» (далі BOM [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) поз. 8 і рядок BMS у моделі `queen_energy_budget.rb`); пороги, стійкість налаштувань і поведінка розряду → нога 🔗 HW.16 «charge-protect» (далі [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) п. 1); числа виробника → шортлист із посиланням на надісланий документ. Цін і внутрішніх даних продавця не комітити (§0 п. 5).

---

## 📤 Dispatch block (EN) — JBD or distributor email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): вимоги 20 А / 50 А · 12 В 4S 20 А·год · −20 °C усередині корпусу · +1 °C · +45 °C і ≈ +55 °C влітку · ≤ 15 мА · дефолти й допуски з datasheet · цитати виробника про UART і §4.5.2. Питає лише те, чого не публікує жоден документ виробника (перелік — §0 п. 6), а опубліковане подає фактом або проханням підтвердити. **Немає свідомо:** нашої рекомендації SKU · «≥ +4 °C» · балансів моделі · детектора тихого дефолту · README `esphome-jbd-bms` · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** JBD-DP04S007 V1.5 and JBD-SP04S034: self-consumption, UART from the load side, temperature protection

**To a distributor receiving this:** if you are not the manufacturer, please forward this message to the Jiabaida (JBD) engineering team. Most of the questions below can only be answered by the manufacturer.

Dear colleagues,

**About us and the application.** We are an R&D project building an off-grid gateway for forest monitoring. It runs from a 12 V LiFePO4 battery (4S, 20 Ah), charged by a 50 W solar panel through an MPPT solar charge controller. It stays on around the clock: a microcontroller and an LTE-M cellular modem are powered from the battery through a DC-DC converter. The gateway is mounted outdoors in a forest, in a sealed enclosure; our winter design point for the inside of the enclosure is −20 °C.

We are choosing a BMS for this battery. Our requirements: 20 A continuous, 50 A peak, and temperature protection. Two of your models are on our shortlist. This is a technical enquiry and not yet an order. Answering commits neither side to anything, and inline answers in this email are fine.

**Base case and one alternative.** The base case is **JBD-DP04S007 V1.5, LiFePO4, 4S, 60 A**. The alternative is **JBD-SP04S034, 60 A version**. Please answer for the base case first, and for the alternative wherever its answer differs. We are working from the specification sheets on the download page of jiabaida-bms.com: the DP04S007 V1.5 LiFePO4 specification sheet and SP04S034 revision A04.

**1. Self-consumption: the figure that decides our choice**

The gateway draws current from the battery all the time, day and night, so we expect the BMS to spend its whole life in running mode, not in sleep. The specification sheets give maximum running self-consumption: 10 mA or less (DP04S007) and 25 mA or less (SP04S034). Our winter energy budget leaves at most **15 mA** at 12 V for the BMS.

- a. What is the **typical** running self-consumption of each model at 25 °C, and how does it change at −20 °C? Please state the conditions: Bluetooth module fitted or not, UART connected or not, balancing inactive.
- b. For the SP04S034: the typical running self-consumption with the isolated RS485 option fitted.
- c. What current counts as "no current" for entering sleep mode? Our load never drops to zero, so we assume the BMS will never sleep. Please confirm or correct this.
- d. Are these figures design values or measured on production units? If measured, what is the spread between units?

Please give the typical and the maximum values even if the answer is not good news for us. Knowing whether a model can meet 15 mA is less useful to us than having the actual figures.

**2. Communicating over UART from the load side (isolation)**

The DP04S007 sheet says that the ground wire of J4-UART is B−, that this is a non-isolated UART port, and that it does not support communication with chargers or loads. The SP04S034 sheet says the same about its standard UART. Our microcontroller is exactly such a load: it is powered from the battery through the BMS and a DC-DC converter.

- a. What goes wrong if the load communicates over this port? Is it the ground offset between B− and C− when the discharge MOSFET is turned off, or something else?
- b. Can the port be used safely from the load if we add a digital isolator on our side, with its BMS side powered and referenced from the BMS UART connector? The V1.5 sheet gives pin 4 of the UART connector as "UART – VDD 5V", while the V1.7 sheet (revision A05) gives the same pin as B+, the pack voltage. Which is true of V1.5 boards, and how much current may we draw from that pin?
- c. The DP04S007 V1.5 sheet lists both isolated RS485 and isolated UART as "Not supported". Please confirm, and tell us whether you offer an add-on isolation module for this board.
- d. For the SP04S034: how do we order the isolated RS485 option, and does it change the price or the self-consumption (see 1b)?
- e. Your public "RS485-RS232-UART-Bluetooth Communication Protocol" calls itself the general protocol of your boards. Please confirm that it applies unchanged to the DP04S007 60 A and 100 A versions and to the SP04S034, and that it is the current revision.

**3. Low-temperature protection: writing the thresholds, separately for charge and discharge**

Our battery must not be charged below **+1 °C** cell temperature. According to the sheets, charging is blocked at about −10 °C by default: −13 / −10 / −7 °C for the DP04S007 and −15 / −10 / −5 °C for the SP04S034. Discharge is cut off at about −20 °C by default, with a tolerance of ±3 °C for the DP04S007 and ±5 °C for the SP04S034. We therefore need to change both thresholds.

- a. Your JBDTools user manual (v1.1, section 2.4) shows separate charge and discharge low-temperature fields, ChgUTP and DsgUTP, written to the board with "Write parameters". Please confirm that both are writable, independently of each other, on the DP04S007 V1.5 and the SP04S034. What are the settable range, the step and the accuracy of each, for the protection value and the release value?
- b. In particular, can the charge low-temperature protection be set to a **positive** cell temperature, above 0 °C?
- c. Your "JBD BMS Tools instructions for RS485/UART" describe reading and writing the board's parameters with JBDTools, and your public communication protocol describes the read and write frames (0xA5 to read, 0x5A to write, with the register address as the command code). Please send the register addresses and the value scaling of the charge and discharge temperature protection and release fields. Your instructions (section 4.5.4) say that while a Bluetooth password is set, the parameters cannot be read or written; apart from that, does writing them need a factory mode or any other unlock step?
- d. JBDTools reads the parameters back from the board. Please confirm that our controller can **read** the active threshold values over UART in the same way, so that it can check them at every start-up.
- e. Are written settings kept in non-volatile memory? Which events return them to factory defaults: power loss, disconnecting the cells, a reset command, a firmware update, anything else?
- f. Can you supply units preset at the factory with our threshold values? From what quantity?
- g. Your sheets list a version "with heating" whose charge low-temperature protection is 0 °C nominal. Is that different hardware, or the same board with different default settings?

**4. Behaviour when only charging is blocked by cold**

- a. When charge low-temperature protection is active, is **only** the charge MOSFET turned off, so that the gateway keeps running from the battery? The protection section of the sheets says that "charging or discharging MOSFET is turned off, and the battery pack cannot be charged or discharged in this state", and we cannot read that unambiguously.
- b. If discharge continues in that state, does the current flow through the body diode of the charge MOSFET? Our load is a few tens of milliamps continuously, with short pulses below 1 A when the modem transmits. What voltage drop and heating should we expect?
- c. Your sheets (section 4.5.2) say that once the cell temperature rises to the low-temperature recovery value, the board turns the charge and discharge MOSFETs on again. Please confirm that this also happens if the BMS has entered sleep during a low-temperature **discharge** cut-off (section 4.8: sleep after one to two minutes without current or communication), so that no charger connection or button is needed. The gateway is unattended in the forest, so this matters to us.

**5. Operating temperature**

The DP04S007 sheet gives an operating range of −20 to +75 °C, and our winter design point inside the enclosure is −20 °C. What happens to the BMS below −20 °C: do the protections keep working, and are the MOSFETs held in a defined state? Is there an extended low-temperature version? For the SP04S034 the range is −30 to +75 °C. Does that also hold for the 60 A version with the isolated RS485 option?

In summer, by our calculation, the air inside the enclosure can reach about +55 °C in direct sun, and the solar panel charges the battery exactly then. Our cells must not be charged above **+45 °C**. Both sheets give the charge high-temperature protection as 62 / 65 / 68 °C (release 52 / 55 / 58 °C), so we must lower it. Please confirm that it is writable separately from the discharge high-temperature thresholds, and give the range, the step and the accuracy.

**6. Documents and samples**

- a. Please confirm that the specification sheets published on jiabaida-bms.com are the current official revisions, and send newer ones if they exist.
- b. For each model, the settable range and the default of every user-configurable parameter: your JBDTools manual names the fields, but not their ranges.
- c. Price and lead time for a sample order of a few units of each model, base case first, delivered to Ukraine.
- d. A technical point of contact.
- e. Which hardware revision of the DP04S007 do you ship today: V1.5, as in the sheet on your website, or V1.7? If V1.7, please confirm that your answers above apply to it.

Thank you in advance.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 3. Cross-references

| Ресурс | Що бере |
|---|---|
| [`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) | увесь фактичний вміст: SKU, дефолти, цитати виробника, межа [В] ⊥ [П], що не звірено |
| `tools/firmware/queen_energy_budget.rb` | бюджет BMS ≤ 15.2 мА на 10-хв каденсі FW.64 (межа гейта `--assert`; у лист — 15) |
| [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) · [`02_05 §3`](../../02_05_Queen_Hardware_and_Starlink.md) · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) | вимоги BMS (поз. 8) · дерево живлення · зимова точка й поріг заряду +1 °C |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15 · HW.16 | дім стану: нога «спитати JBD», ⚖️ SKU, ⚖️ charge-protect |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс (рядок «Брама Queen») |
