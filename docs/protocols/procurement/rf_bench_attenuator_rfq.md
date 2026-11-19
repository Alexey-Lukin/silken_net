# RF-макет — ступінчастий атенюатор 0–90 дБ / 1 дБ / до 2.5 ГГц, SMA: запит ціни SGLabs (×1, доставка в Україну)

> **Що це:** RFQ-аркуш до **SGLabs** (Італія, продавець вимірювальних приладів) — запит ціни й доступності **одного** ручного ступінчастого атенюатора з їхньої картки (`sglabs.it/en/product.php?id=1575`, «Step Attenuator 90dB») у **SMA-версії**, з доставкою в Україну (Черкаси). Прилад — зі стенда `[bench:rf-mockup]`: лінійність RSSI й метод запасу «атенюація до відмови» ([`rf_mockup_bench_sheet`](../hardware/rf_mockup_bench_sheet.md) §2); у переліку приладів стенда — [`RUNBOOK §0`](../../../firmware/scripts/bench/RUNBOOK.md).
> **Статус:** 🟡 робочий артефакт (не канон) · ⏳ Станом на 2026-11-15 · **надіслано 2026-11-15 на «так» founder-а того ж дня** (адресати — журнал надісланого, поза деревом; copy-регіон після відправки не правиться). ⚖️ **Підстава:** founder 2026-11-15, п. 9 закупівлі осі 3 — SGLabs, запит ціни з доставкою в Україну (подання закупівлі HW.9 + HW.33, розділ HW.33, присуд (в) — корпус естафет, поза деревом). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33, нога «замовити тестові плати осі 3 RF-макета й деталі до них» (прилади осі 3 — там само). Числа аркуша стенда — дзеркало, правити в домі (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) §1, рядок «Стендові прилади — RF-макет».

---

## 0. Як користуватись

1. **Це запит ціни, не замовлення.** Лист нічого не купує й ні до чого не зобовʼязує; замовлення й оплата — 👤 founder після відповіді й окремого «так».
2. **Для чого прилад і що в ньому важить** ([`rf_mockup_bench_sheet`](../hardware/rf_mockup_bench_sheet.md)): калібрування (б) §2 — провідний прогін крізь атенюатор дає RSSI приймача одиницю, без нього різниці `A_thr` між конфігураціями не мають одиниці (там само §9, друга найслабша ланка); метод запасу §2 — крок угору до PER-порогу, той самий атенюатор у провідній осі 2a (§4) і в стані W на колоді (§8.1, «Що привезти»); смуга повторюваності ρ — не менша за крок атенюатора 1 дБ (§8.1, «Що з чим порівнюється» п. 3). Тож важать три речі: що 868 МГц лежить у смузі приладу, яка там точність кроків і яке узгодження (VSWR) — атенюатор стоїть у 50-омному ланцюгу перед входом RX. ⚠️ **Витоку повз атенюатор лист не питає:** його ловить перевірка (в) §2 на самому стенді (відʼєднаний кабель — PER мусить піти в 100 %), а не паспорт продавця. **Діапазону потреби аркуш не задає** — «90 дБ» стоїть на оцінці запасу лінку на столі з подання закупівлі (найслабша ланка присуду (в)); у лист не йде.
3. **SMA, а не N:** LoRa-E5 mini на стенді має SMA-K ([`02_04`](../../02_04_Bench_Build_Guide.md), рядок «868 антена»), кабель тестової плати осі 3 — U.FL → SMA ([`README`](../../../tools/pcb/hw33_rf_axis3_boards/README.md) плат, «Ordering notes»). Стать роз'ємів SMA-версії картка не друкує — питаємо (п. 1 листа), щоб перехідники лягли в те саме замовлення.
4. **Що закрито сайтом SGLabs до тексту** (`legal-business` §Доменні правила #14; видимий текст сторінок через `curl`, 2026-11-15):
   - **картка** (EN- і IT-версії збігаються): «Manual Step Attenuator, DC-2.5 GHz, with maximum attenuation of 90 dB and 1 dB of step. N or SMA connectors» (IT уточнює «meccanico»); 50 Ω; VSWR 1.40 max; 5 W average; точність 1–10 дБ ±0.8 дБ · 10–50 дБ ±1.25 дБ · 50–90 дБ ±3 %; −10…+50 °C; «N type connector (picture), SMA type available»; 20 × 36 × 150 мм; секції 1, 2, 4, 8, 16, 20, 20, 20 дБ; insertion loss ≤ 3 dB; €180,00; кнопка «REQUEST QUOTATION». **ПДВ на сторінці не названо; наявності й стану (новий ⊥ уживаний) картка не друкує** — позиція стоїть у розділі «RF Component » Attenuator», не в «Second hand»;
   - **форма котирування** (`sglabs.it/en/quote.php?id=1575`, сторінка кнопки «REQUEST QUOTATION», а не сама картка) називає позицію видимим текстом посилання «SgLabs SGLabs - Step Attenuator 90-KT2.5-90-1S-2N» (переміряно повторним завантаженням того ж дня; на картці код стоїть лише в іменах файлів фото — «KT2.5-901S-2N»): це позначення показаної N-версії з форми, ще не код замовлення SMA-версії (`legal-business` §Доменні правила #6); пошук за «KT2.5-90-1S» того ж дня ні виробника, ні паспорта не дав — це межа одного пошуку, а не «паспорта немає» (#6 (в));
   - **«How to order»** (EN) — лише «contact us through the form»; IT-сторінка «Come ordinare» віддає політику приватності. Умов доставки, оплати й ПДВ на сайті не знайдено — тому пп. 2–4 листа;
   - **«Company»**: продаж, оренда приладів, калібрування «like ISO and Accredia (ex SIT) standard» через партнерську лабораторію, ремонт — тож п. 6 листа спирається на їхній власний текст;
   - **«Contacts»**: технічно-комерційний відділ і загальна скринька — адреси у видимому тексті сторінки; у дерево не кладуться (журнал надісланого);
   - **адресат існує:** ПДВ-номер із підвалу сайту чинний у VIES (запит 2026-11-15), назва платника збігається з назвою на сторінці приватності сайту (`legal-business` §Доменні правила #14 ⊕ «і самого адресата»);
   - **не відкривали:** eBay-магазин SGLabs (посилання з сайту) — сліпа зона; там може стояти та сама позиція з тарифом доставки.
5. **Що свідомо НЕ питаємо, бо відповідає картка:** опір, смуга, діапазон і склад секцій, вносні втрати, потужність, температури, габарит. VSWR і допуски на картці теж є, тож у листі вони стоять не питанням, а проханням підтвердити, що ці числа тримаються на 868 МГц і для SMA-версії (п. 5). Дві речі з картки важать для стенда, але питання не дають:
   - секції в сумі дають 91 дБ при заявлених 90 — на метод не впливає (крок 1 дБ, діапазон не менший за заявлений);
   - −10 °C — нижня межа робочого діапазону, а стан W на колоді (аркуш §8.1) може випасти на мороз: пропозиція машини — атенюатор тоді в теплому боксі, як логер температури там само.
6. **Голос і покупець.** Відправник — founder особисто, підпис без телефону ([`rfq_registry`](rfq_registry.md) §3). Покупця лист не називає й щабля драбини не пропонує: умов продажу на сайті немає, тож лист питає, кому продавець продає й які дані покупця потрібні для рахунку (п. 4); вибір покупця — ⚖️ founder після відповіді, за драбиною [`rfq_registry`](rfq_registry.md) §3.
7. **Відповідь у репо не комітиться:** ціни й умови — чужі операційні факти (`legal-business` §Межі #3); у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33 іде лише наш висновок — канал, строк, чи береться калібрувальний протокол.
8. **Запасні шляхи — поза листом:** цифровий модуль із фіксованими атенюаторами або позичити ([`RUNBOOK §0`](../../../firmware/scripts/bench/RUNBOOK.md): «можна позичити — крім VNA»); вибір між ними — ⚖️ founder, не цей лист.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Звідки | Як подано | Свідомо НЕМАЄ |
|---|---|---|---|
| **Абзац 1 (що й навіщо)** | картка (§0 п. 4) · аркуш стенда §2 (атенюація до відмови) · Черкаси — нога закупівлі | фактом | адреса доставки (дає founder у мить замовлення) · назва проєкту · ланцюг стенда |
| **Абзац 2 (рамка)** | `legal-business` §Доменні правила #5 (а) — «request for a quotation, not yet an order» | фактом | — |
| **1. Версія й код** | картка «SMA type available» · форма котирування «KT2.5-90-1S-2N» · §0 п. 3 | питанням: код SMA-версії, стать роз'єму на кожному порту | наше прочитання коду форми |
| **2. Ціна й ПДВ** | картка €180, ПДВ не названо | питанням | — |
| **3. Склад і доставка** | картка (наявності немає) · `legal-business` §Доменні правила #8 (д) — склад питають за будь-якого статусу картки | питанням | строк потреби: дати сеансу немає (аркуш §6), тож дедлайну лист не ставить |
| **4. Покупець і оплата** | [`rfq_registry`](rfq_registry.md) §3 (драбина покупця) | питанням: кому продають, які дані покупця для рахунку, оплата | хто покупець і щабель драбини — ⚖️ founder після відповіді (§0 п. 6) · реквізити |
| **5. Точність на 868 МГц** | картка (VSWR · допуски · вісім секцій) · аркуш §2 (б) | «підтвердьте X» + виміряні дані примірника, якщо є | наші пороги, ρ, `A_thr` |
| **6. Калібрування й гарантія** | сторінка «Company» (калібрування через партнера) · аркуш §9 (RSSI як вимірювач) | опцією — дельтою до базової ціни (`legal-business` §Доменні правила #5 (а)): який протокол доступний, ціна, строк | наша специфікація послуги (секції, частота — частота лише в п. 5) · клас акредитації як вимога |

Немає також: витоку чи екранування (ловить перевірка §2 (в) на стенді) · діапазону потреби (аркуш не задає) · розділу Confidentiality — лист не розкриває специфікації, як і лист логера [`ebfc_stem_light_logger_rfq`](ebfc_stem_light_logger_rfq.md) · трекер-ID, канон-рефів, дат і гліфів (`copy_region_check`).

---

## 2. Dispatch checklist

- [x] 👤 «Так» founder-а на текст (2026-11-15) (покупця лист не називає — питає, кому продають; вибір покупця — ⚖️ founder після відповіді, §0 п. 6).
- [x] ⊕ 2026-11-15: картку й форму котирування переміряно того ж дня до відправки (у мить відправки сайт віддавав помилку бази даних, повторно не відкрився); тіло зібрано `scripts/letter_body.rb`, чернетку звірено машинно — тема, тіло, адресати. Пункт чекліста: Перед Send: переміряти картку (ціна, характеристики, «SMA type available») і форму котирування (назва позиції «…KT2.5-90-1S-2N», п. 1 листа) в день відправки (`legal-business` §Доменні правила #14 (б)); тіло зібрати `scripts/letter_body.rb` і звірити чернетку за `legal-business` §Доменні правила #13; адреса — з видимого тексту «Contacts».
- [ ] 👤 Після відповіді: висновок → [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33 (прилади осі 3); цін не комітити (§0 п. 7); одне нагадування — після 7 робочих днів тиші ([`rfq_registry`](rfq_registry.md) §3).

---

## 📤 Dispatch block (EN) — SGLabs email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала картки (§0 п. 4): назва позиції, DC–2.5 GHz, 0–90 dB із кроком 1 dB, вісім секцій, VSWR 1.40 max, допуски трьох діапазонів, €180, «SMA type available», позначення з форми котирування; калібрування через партнера — сторінка «Company». Мова — англійська: сайт має EN-версію, лист дозволяє відповідати італійською. **Немає свідомо:** адреси доставки, назви проєкту, вибору покупця (лише питання, кому продають), нашої специфікації калібрування, наших порогів, трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Price enquiry: 1 × Step Attenuator 90 dB, SMA version, delivery to Ukraine

Dear SGLabs team,

I would like a price quotation for **one Step Attenuator 90 dB** from your website (manual, DC–2.5 GHz, 0–90 dB in 1 dB steps), **in the SMA version**, delivered to Cherkasy, Ukraine. It is for bench tests of 868 MHz radio modules, where the link is attenuated step by step until packets start to be lost.

This is a request for a quotation, not yet an order; replying commits neither side. Inline answers in this email are fine, in English or Italian.

1. **Version and model code.** Your page shows the N version and says the SMA version is available; your quotation form names the item "KT2.5-90-1S-2N". Please quote the SMA version and tell me its model code and the SMA gender (male or female) on each port.
2. **Price and VAT.** Your page shows €180 without saying whether VAT is included. Please give the price of one SMA unit and say whether VAT is included, or not charged, for a shipment to Ukraine.
3. **Stock and delivery.** Is the SMA version new and in stock, or made to order (and if so, with what lead time)? Can you ship to Ukraine? If so, please give the shipping options and cost to Cherkasy and the expected delivery time.
4. **Buyer and payment.** Do you sell to private individuals, to businesses, or both, for delivery to Ukraine? What buyer details do you need for the invoice, and which payment methods do you accept from Ukraine?
5. **Accuracy at 868 MHz.** Your page gives VSWR 1.40 maximum and attenuation tolerances of ±0.8 dB (1–10 dB), ±1.25 dB (10–50 dB) and ±3 % (50–90 dB), without naming a frequency for them. Please confirm that these figures hold at 868 MHz and apply to the SMA version as well. If you have measured data for the unit you would ship — the attenuation of each of the eight switch sections (1, 2, 4, 8, 16 and 3 × 20 dB) and the VSWR near 868 MHz — I would be glad to receive a copy.
6. **Calibration and warranty.** Your company page mentions calibration through a partner laboratory. What calibration report is available for this unit, and at what extra price and lead time? What warranty comes with the unit?

Thank you in advance.

`[sender's signature — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 📤 Reminder block (EN) — SGLabs: one follow-up on the price enquiry

> **Репо-нота (у лист НЕ йде).** Одне нагадування у треді запиту ціни (лист 2026-11-15; правило й лічба — [`rfq_registry`](rfq_registry.md) §3; нога — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33). Нового не питає: найменша корисна відповідь — ціна одного приладу у версії SMA, наявність і чи відвантажують в Україну (пп. 2 і 3 листа). Написано 2026-11-19 заздалегідь; ⚖️ founder 2026-11-19 — «так на всі» (тексти нагадувань подано переліком блоків із датами; у чаті повністю показано лише текст кліматичної лабораторії); у день відправки — звірка скриньки разом зі спамом. Підпис — `--signature "Best regards,|Oleksii Lukin"`; рядок теми треду дописують у скретч-копії (скіл `legal-business` §Доменні правила #13).

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

Dear SGLabs team,

A short follow-up on my price enquiry of 15 November below — one Step Attenuator 90 dB in the SMA version, delivered to Cherkasy, Ukraine.

Could you confirm that it has reached you? A short reply would already help: the price of one SMA unit, whether it is in stock, and whether you ship to Ukraine (items 2 and 3 of that email). The other answers can follow later, in English or Italian. If you do not ship to Ukraine, a short "no" is useful too.

`[sender's signature — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 3. Cross-references

| Ресурс | Що бере |
|---|---|
| [`rf_mockup_bench_sheet`](../hardware/rf_mockup_bench_sheet.md) §2 · §4 · §8.1 · §9 | навіщо атенюатор: калібрування (б), метод запасу, перевірка витоку (в), стан W, RSSI як вимірювач |
| [`RUNBOOK §0`](../../../firmware/scripts/bench/RUNBOOK.md) | атенюатор у переліку приладів стенда; «можна позичити — крім VNA» |
| [`02_04`](../../02_04_Bench_Build_Guide.md) · [`README`](../../../tools/pcb/hw33_rf_axis3_boards/README.md) плат осі 3 | роз'єми ланцюга стенда — чому SMA |
| [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) | куди йдуть числа стенда (Link Budget) |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.33 | дім стану |
| [`rfq_registry`](rfq_registry.md) §1 · §3 | procurement-індекс · відправник, покупець, нагадування |
