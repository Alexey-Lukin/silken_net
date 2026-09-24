# Queen — BMS 4S LiFePO4 (JBD-клас): технічний запит виробникові або продавцеві

> **Що це:** RFQ-аркуш — технічний запит до **JBD (Jiabaida)** або до продавця з доступом до інженерів виробника щодо двох SKU шортлиста BMS Королеви. Предмет — **три питання, що розсуджують вибір SKU**, і те, що з тієї самої відповіді чекає гілка charge-protect. Прайс тут не предмет. **Лист питає й висновків не повідомляє:** рекомендацію «DP04S007» зроблено на ОПУБЛІКОВАНИХ максимумах, і в лист вона не йде.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-24, не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Адресата не обрано: сайт виробника з нашої мережі не відкривався ([`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) §0), тож текст написано так, щоб продавець міг переслати його виробникові без правок. Числа дзеркалять доми, і дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15 (нога «спитати JBD») і HW.16 (charge-protect: розсуджує та сама відповідь).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Брама Queen» · hard-constraint дім §4.D).

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Перший адресат — JBD, а якщо виробник не відповідає, то продавець, який має доступ до виробника (агент, дистриб'ютор). Перший рядок листа просить продавця переслати текст інженерам виробника, бо на пп. 2–4 відповідає лише виробник. Адресати поза UA, тому **лист англійською**.
2. **Базовий кейс + дельта, не прайс на все.** Базовий кейс — **JBD-DP04S007 V1.5 LiFePO4 4S, 60 А**. Дельта — **JBD-SP04S034, 60-А варіант**: саме він перевертає вибір, якщо його типовий струм укладеться в бюджет (нога ⚖️ HW.15, «Що перевертає вибір»). ⛔ Файл SP04S028A і модель SP04S020 **свідомо не питаємо**: файл суперечить сам собі щодо SKU, а spec-sheet на SP04S020 не знайшли ([`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) §1). Відповідь на ці дві моделі — це вже ширша робота, ніж потрібна ⚖️.
3. **Яке питання розсуджує яку ногу.** П. 1 (типовий running-струм) розсуджує вибір SKU. П. 2 (UART з боку навантаження) закриває «Ціну» рекомендації: у DP04S007 немає дротової телеметрії. П. 3 (чи записувані пороги холоду, окремо для заряду й розряду) потрібен і HW.15, і HW.16. П. 4 (чи триває розряд при закритому charge-FET) і п. 3 d–f (чи переживає поріг скидання) — це входи HW.16. Відповідь «так» дає гілку «BMS-інтегроване відсікання», «ні» — гілку «дискретний P-MOSFET». **Лист питає обидві гілки й жодної не замовляє** (скіл `legal-business` §Доменні правила #4).
4. **Що подано як НАШУ вимогу, а що питанням.** Бюджет **≤ 17 мА** — це наша вимога: межа гейта моделі, переміряна при написанні, `quiescent_ma=37` → EXIT 0, `38` → EXIT 1. Щоб число не підказало відповіді, лист просить типове **і** максимальне значення з умовами. Вимога канону «заряд заблоковано нижче +1 °C» теж стоїть як вимога. **Нашої деривації «≥ +4 °C»** (+1 плюс допуск ±3 °C), яку рекомендує HW.16, у листі **немає**: вона ще не присуд, тож лист питає діапазон, крок і точність поля.
5. **Відповідь у репо не комітиться.** Ціни, внутрішні дані тестування й переписка продавця — чужі операційні факти. У [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15/HW.16 і в шортлист іде лише наш висновок; числа виробника — з посиланням на документ, який він надішле.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Застосування** | [`02_05 §3`](../../02_05_Queen_Hardware_and_Starlink.md) (12 В LiFePO4 20 А·год · 50-Вт панель · MPPT · DC-DC) · [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) поз. 5–7 · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) (усередині корпусу взимку −20 °C) | фактом | Phase 3 (Starlink, 40 А·год / 100 Вт) — не базовий кейс · модель MPPT (Victron) — лист каже «MPPT solar charge controller» |
| **Вимоги 20 А / 50 А** | [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) поз. 8 | вимогою | — |
| **Базовий кейс + альтернатива** | [`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) §1 · нога ⚖️ [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15 | дві моделі без ранжування | наша рекомендація і її підстава · SP04S028A-файл · SP04S020 |
| **1 self-consumption** | шортлист §1 (≤ 10 / ≤ 25 мА running) · шортлист §3 (умова сну «no current»; поріг не наведено) · `tools/firmware/queen_energy_budget.rb` (`quiescent_ma` 20 = лише Victron; гейт тримає до 37, отже на BMS ≤ 17 мА) | ≤ 17 мА — **нашою вимогою**; типове й максимальне, умови й розкид — питанням | баланси Wh/добу, EXIT-коди, таблиця шортлиста §3 · «що перевертає вибір» |
| **2 UART з боку навантаження** | шортлист §4 (цитата DP04S007 стор. 14; SP04S034 стор. 3 і 15) · [`02_05 §3`](../../02_05_Queen_Hardware_and_Starlink.md) (контролер живиться від пакета через DC-DC — отже він і є навантаженням) | цитатою виробника; «чому» · ізолятор на нашому боці · опція ізольованого інтерфейсу · єдність протоколу — питанням | README `esphome-jbd-bms` і його «tested» (варіант 100 А на ESP32) · ESP32 ⊥ STM32 · наш висновок «дротової телеметрії немає» |
| **3 пороги холоду** | шортлист §1 (дефолти й допуски) · шортлист §2 п. 1–2 (налаштовуваність — лише загальне твердження; протокол V4 без регістрів порогів) · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) п. 1 (+1 °C) · нога ⚖️ HW.16 (поріг РОЗРЯДУ теж перепрограмовується) | +1 °C — вимогою; дефолти — цитатою datasheet; діапазон · крок · точність · засіб запису · читання назад — питанням | **«≥ +4 °C»** (наша деривація, рекомендація HW.16) · «небезпечне значення і є дефолтом» |
| **3 d–g стійкість налаштувань** | нога ⚖️ HW.16, «Ціна» (заводський дефолт повертається мовчки при заміні плати чи скиданні) · шортлист §1 (варіант «з підігрівом» 0 °C) | питанням: енергонезалежність · що повертає дефолт · заводське передналаштування · підігрів — інше залізо чи інші налаштування | наш детектор тихого дефолту (DS18B20 + VE.Direct) і те, що коду під нього немає |
| **4 розряд при закритому charge-FET** | шортлист §2 п. 3 (цитата §4.5.2; окремі біти bit5 ⊥ bit7) · нога ⚖️ HW.16 · навантаження: модель `queen_energy_budget.rb` (десятки мА безперервно) · [`02_05`](../../02_05_Queen_Hardware_and_Starlink.md) «Пікові струми SIM7070G» (2 А — на шині VBAT 3.7 В модему) | цитата — «не можемо прочитати однозначно»; body-diode і самовідновлення — питанням; імпульс — «below 1 A»: на 12-В боці 2 А × 3.7 В / (12 В × 0.95) ≈ 0.65 А, перераховано тут | «≈ 2 А» як струм крізь BMS (канон ставить 2 А на системний рівень без перерахунку — вимога від цього лише консервативніша, у лист це не йде) · номери бітів протоколу · наш висновок «гасне при −15…−17 °C» (у листі лише питання про відновлення) |
| **5 робоча температура** | шортлист §1 (−20…+75 · −30…+75) · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) (−20 °C) | фактом і питанням | «без запасу» (наш висновок) |
| **6 документи, зразки** | шортлист §0 (власника домену `jiabaida-bms.com` не звірено) · шортлист §2 п. 2 (перелік полів — лише скріншот JBDTools) | питанням | — |

---

## 2. Dispatch checklist (👤)

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Адресат:** JBD (бізнес-контакт на домені `@jiabaida.com` — шортлист §0) або продавець. Якщо лист іде продавцеві, перший абзац уже просить переслати його виробникові; нічого не міняти.
- [ ] 👤 **Після відповіді:** SKU → нога ⚖️ HW.15 (далі BOM [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) поз. 8 і рядок BMS у моделі `queen_energy_budget.rb`); пороги, стійкість налаштувань і поведінка розряду → нога ⚖️ HW.16 (далі [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) п. 1); числа виробника → шортлист із посиланням на надісланий документ. Цін і внутрішніх даних продавця не комітити (§0 п. 5).

---

## 📤 Dispatch block (EN) — JBD or distributor email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): вимоги 20 А / 50 А · 12 В 4S 20 А·год · −20 °C усередині корпусу · +1 °C · ≤ 17 мА · дефолти й допуски з datasheet · цитати виробника про UART і §4.5.2. Питає те, чого не публікує жоден документ виробника: типовий струм · поріг сну · що саме ламає UART з боку навантаження · чи записувані пороги холоду окремо для заряду й розряду · стійкість налаштувань · поведінку розряду при закритому charge-FET. **Немає свідомо:** нашої рекомендації SKU · «≥ +4 °C» · балансів моделі · детектора тихого дефолту · README `esphome-jbd-bms` · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Technical enquiry — JBD-DP04S007 V1.5 (LiFePO4, 4S, 60 A) and JBD-SP04S034 (60 A): typical self-consumption, UART use from the load side, low-temperature protection settings

**To a distributor receiving this:** if you are not the manufacturer, please forward this message to the Jiabaida (JBD) engineering team. Most of the questions below can only be answered by the manufacturer.

Dear colleagues,

**About us and the application.** We are an R&D project building an off-grid gateway for forest monitoring. It runs from a 12 V LiFePO4 battery (4S, 20 Ah), charged by a 50 W solar panel through an MPPT solar charge controller. It stays on around the clock: a microcontroller and an LTE-M cellular modem are powered from the battery through a DC-DC converter. The gateway is mounted outdoors in a forest, in a sealed enclosure; in winter the temperature inside the enclosure reaches −20 °C.

We are choosing a BMS for this battery. Our requirements: 20 A continuous, 50 A peak, and temperature protection. Two of your models are on our shortlist. This is a technical enquiry and not yet an order. Answering commits neither side to anything, and inline answers in this email are fine.

**Base case and one alternative.** The base case is **JBD-DP04S007 V1.5, LiFePO4, 4S, 60 A**. The alternative is **JBD-SP04S034, 60 A version**. Please answer for the base case first, and for the alternative wherever its answer differs. We are working from the specification sheets on the download page of jiabaida-bms.com: the DP04S007 V1.5 LiFePO4 specification sheet and SP04S034 revision A04.

**1. Self-consumption: the figure that decides our choice**

The gateway draws current from the battery all the time, day and night, so we expect the BMS to spend its whole life in running mode, not in sleep. The specification sheets give maximum running self-consumption: 10 mA or less (DP04S007) and 25 mA or less (SP04S034). Our winter energy budget leaves at most **17 mA** at 12 V for the BMS.

- a. What is the **typical** running self-consumption of each model at 25 °C, and how does it change at −20 °C? Please state the conditions: Bluetooth module fitted or not, UART connected or not, balancing inactive.
- b. For the SP04S034: the typical running self-consumption with the isolated RS485 option fitted.
- c. What current counts as "no current" for entering sleep mode? Our load never drops to zero, so we assume the BMS will never sleep. Please confirm or correct this.
- d. Are these figures design values or measured on production units? If measured, what is the spread between units?

Please give the typical and the maximum values even if the answer is not good news for us. Knowing whether a model can meet 17 mA is less useful to us than having the actual figures.

**2. Communicating over UART from the load side (isolation)**

The DP04S007 sheet says that the ground wire of J4-UART is B−, that this is a non-isolated UART port, and that it does not support communication with chargers or loads. The SP04S034 sheet says the same about its standard UART. Our microcontroller is exactly such a load: it is powered from the battery through the BMS and a DC-DC converter.

- a. What goes wrong if the load communicates over this port? Is it the ground offset between B− and P− when the discharge MOSFET opens, or something else?
- b. Can the port be used safely from the load if we add a digital isolator on our side, with its BMS side powered and referenced from the BMS UART connector? What supply voltage and current does that connector provide?
- c. Is an isolated RS485 or isolated UART option available for the DP04S007 V1.5? The sheet lists RS485 as "Not supported".
- d. For the SP04S034: how do we order the isolated RS485 option, and does it change the price or the self-consumption (see 1b)?
- e. Is the communication protocol the same for the DP04S007 60 A and 100 A versions and for the SP04S034? Is your public document "RS485-RS232-UART-Bluetooth Communication Protocol" the current revision?

**3. Low-temperature protection: are the thresholds writable, separately for charge and discharge?**

Our battery must not be charged below **+1 °C** cell temperature. According to the sheets, charging is blocked at about −10 °C by default: −13 / −10 / −7 °C for the DP04S007 and −15 / −10 / −5 °C for the SP04S034. Discharge is cut off at about −20 °C by default, with a tolerance of ±3 °C for the DP04S007 and ±5 °C for the SP04S034. We therefore need to change both thresholds.

- a. Can the user write the charge low-temperature protection and release thresholds, independently of the discharge low-temperature thresholds? What are the settable range, the step and the accuracy of each?
- b. In particular, can the charge low-temperature protection be set to a **positive** cell temperature, above 0 °C?
- c. How are the thresholds written: with JBDTools on a PC, with the Bluetooth app, or by commands over UART or RS485? If over UART, please send the register map for these parameters. As far as we can see, the public protocol document covers reading status and switching the MOSFETs, but not writing protection parameters.
- d. Can our controller **read** the active threshold values over UART, so that it can check them at every start-up?
- e. Are written settings kept in non-volatile memory? Which events return them to factory defaults: power loss, disconnecting the cells, a reset command, a firmware update, anything else?
- f. Can you supply units preset at the factory with our threshold values? From what quantity?
- g. Your sheets list a version "with heating" whose charge low-temperature protection is 0 °C nominal. Is that different hardware, or the same board with different default settings?

**4. Behaviour when only charging is blocked by cold**

- a. When charge low-temperature protection is active, is **only** the charge MOSFET turned off, so that the gateway keeps running from the battery? The protection section of the sheets says that "charging or discharging MOSFET is turned off, and the battery pack cannot be charged or discharged in this state", and we cannot read that unambiguously.
- b. If discharge continues in that state, does the current flow through the body diode of the charge MOSFET? Our load is a few tens of milliamps continuously, with short pulses below 1 A when the modem transmits. What voltage drop and heating should we expect?
- c. After a low-temperature **discharge** cut-off, does the BMS restore the output by itself once the temperature rises to the release value, or does it need a charger connection or a button to wake up? The gateway is unattended in the forest, so this matters to us.

**5. Operating temperature**

The DP04S007 sheet gives an operating range of −20 to +75 °C, and our enclosure reaches −20 °C in winter. What happens to the BMS below −20 °C: do the protections keep working, and are the MOSFETs held in a defined state? Is there an extended low-temperature version? For the SP04S034 the range is −30 to +75 °C. Does that also hold for the 60 A version with the isolated RS485 option?

**6. Documents and samples**

- a. Please confirm that the specification sheets published on jiabaida-bms.com are the current official revisions, and send newer ones if they exist.
- b. The full list of user-configurable parameters, with ranges and defaults. The sheets show it only as a screenshot of JBDTools.
- c. Price and lead time for a sample order of a few units of each model, base case first, delivered to Ukraine.
- d. A technical point of contact.

Thank you in advance.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 3. Cross-references

| Ресурс | Що бере |
|---|---|
| [`queen_bms_shortlist`](../hardware/queen_bms_shortlist.md) | увесь фактичний вміст: SKU, дефолти, цитати виробника, межа [В] ⊥ [П], що не звірено |
| `tools/firmware/queen_energy_budget.rb` | бюджет BMS ≤ 17 мА (межа гейта `--assert`) |
| [`02_05 §7`](../../02_05_Queen_Hardware_and_Starlink.md) · [`02_05 §3`](../../02_05_Queen_Hardware_and_Starlink.md) · [`02_05 §4а.5`](../../02_05_Queen_Hardware_and_Starlink.md) | вимоги BMS (поз. 8) · дерево живлення · зимова точка й поріг заряду +1 °C |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.15 · HW.16 | дім стану: нога «спитати JBD», ⚖️ SKU, ⚖️ charge-protect |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс (рядок «Брама Queen») |
