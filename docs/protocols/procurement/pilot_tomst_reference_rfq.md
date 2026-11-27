# Референс пілота «перший польовий свідок» — запит котирування TOMST (Point Dendrometer × 1 + TMD adapter × 1)

> RFQ-аркуш, **не канон** · ⏳ Станом на 2026-11-27 · **не надіслано — чекає «так» founder-а на текст** · стан — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.54 (нога «склад пілота — «так» на тексти й відправка») · предмет — присуд складу пілота, п. (3) «TOMST + адаптер» і дописка «TOMST на той самий домашній стенд» ([`01_03 §4`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) ⊕ «П3 — склад пілота»), тут не переказується · адресат — TOMST s.r.o. (Прага), `tomst@tomst.com` — видимий текст сторінки Contact («Email: tomst@tomst.com») і Price list («For quotations and orders, write to tomst@tomst.com»), звірено 2026-11-27 на сторінках регіону EU; read-only адверсар того ж дня відкрив і регіон Global (`tomst.com/price-list/`: «Region: Global», той самий прайс і той самий рядок про котирування); статус юрособи (IČO 27139140) у реєстрі ARES не звірено — через корпоративний проксі реєстр віддав сторінку замість даних, звірити в день відправки.

## 0. Як користуватись

1. **Це запит котирування, не замовлення.** Замовлення й оплата — 👤 founder після відповіді; лист нічого не купує.
2. **Що закрито сайтом TOMST до тексту** (сторінки `tomst.com/eu/…` і два PDF виробника, прочитані текстом 2026-11-27 — правило `legal-business` §Доменні правила #14):
   - прайс «TOMST dataloggers price list 2026 EUR»: Point Dendrometer — €107, TMD adapter — €49 з приміткою «May be complementary as a hardware bonus; please refer to your quotation for details»; «For shipments outside the EU, the total price will be itemized on the invoice for administrative and customs purposes»; «Valid from January 12th, 2026, price without VAT». Ціни збіглися з присудом (3) і ринковим сканом;
   - сторінка продукту: «Request a quotation and we will reply with the details, including shipping to your country. No prepayment is required.» — тож лист не питає, ЧИ можлива доставка в Україну, а просить її ціну; «Stays on the tree outdoors through every season» — питання про мороз лист не ставить;
   - форма котирування на сайті вимагає імʼя, email, індекс і країну, а поля організації й VAT — необовʼязкові: форма не вимагає організації (висновок «продає фізособі» — наш, не слова виробника), тож голос покупця — щабель 1 драбини [`rfq_registry`](rfq_registry.md) §3 (founder особисто), ФОП — запасним реченням. Форму не обрано: канал — email, бо тред лишає запис домовленого, а сайт сам називає email для котирувань і замовлень;
   - Installation Guide (PDF виробника): монтаж на гвинт у стовбурі — свердло 5 мм, отвір «a minimum depth of 40 mm»; на місці приладу знімають лише зовнішню мертву кору. Це вхід прохання власникові сосни ([`pilot_tree_owner_request`](../outreach/pilot_tree_owner_request.md)), не цього листа.
3. **Що лишилось питанням і чому.** Сума з доставкою, перевізник і строк — знає лише виробник. Пересилки через адресу в ЄС лист свідомо не питає: у прецеденті MERA польську адресу продавець прийняв лише з експортним документом пересилки ([`ebfc_stem_light_logger_rfq`](ebfc_stem_light_logger_rfq.md), репо-нота «Order block (EN) — MERA»), а прайс TOMST — без ПДВ, тож доставка фізособі на адресу в ЄС додала б ПДВ; гілка повертається, лише якщо котирування з доставкою в Україну виявиться неприйнятним. Чи стосується «no prepayment» покупця поза ЄС і які способи оплати — сайт не каже. Адаптер «бонусом» — прайс сам відсилає до котирування. Гвинт і гайки в комплекті — посібник монтажу їх уживає, але переліку комплекту на сторінках не знайдено: проханням підтвердити. Посібник монтажу каже «You can also use the Lolly Manager to check the current preload value» — тобто поточне значення якийсь застосунок виробника показує; чи показує його TOMST Lolly для Android — сайт не каже, а від цього залежить тривалість кроку 5 домашнього стенда (§1, рядок 5).
4. **Не питання до виробника:**
   - **мито** — дім митниці України; чинний поріг для посилок фізособі звірити в день замовлення первинкою, не з памʼяті (дві позиції за прайсом — €156 без доставки);
   - **чим зчитувати прилад** — сторінка Software: TOMST Lolly — Android 9+ через TMD adapter (USB-C), позначено «Recommended»; версії для Windows і macOS — «Coming soon»; «Old Lolly is at the end of its life … It will stop working with the new datalogger firmware, which we plan to release at the start of 2027»; про режим Experiment (1 хв): «no longer available in the Android app. Use Old Lolly on Windows if you need it». Тож зчитувач — Android-пристрій (Android 9+) із USB-C; Old Lolly — лише як цитата вище: «end of its life … no longer supported», умова його кінця — прошивка конкретного приладу, а з якою прошивкою прийде прилад і чи не оновить її перший же сеанс застосунку для Android («Check and update datalogger and TMD firmware»), сайт не каже. Чи є Android-пристрій — питання founder-у (нога купівлі [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.54); якщо немає — у лист додається питання про дату десктопної версії.
5. **Входи інших ніг, знайдені в посібнику** (машинне прочитання, не присуд): «If possible, avoid installing the Dendrometer on the side of the tree that receives the most sunlight throughout the day» · «Be wary of placing the Dendrometer close to or below any disrupted resin ducts» — для сосни порушеними ходами можуть стати й отвір нашого Ti-стрижня, і гвинт самого TOMST; відстань і взаємне положення приладів задає креслення рами, не цей аркуш; «Check the Dendrometer regularly, at least once a year, or more frequently for fast-growing trees». Ноги — монтаж і креслення рами [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.54.

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт | Звідки | Свідомо НЕМАЄ |
|---|---|---|
| Абзац 1 (що й навіщо) | присуд (3) і дописка «TOMST на той самий домашній стенд»; строк — нога монтажу («ціль — до весняного старту росту») | назва проєкту, наш логер і датчик, недооцінка росту TOMST у звіті AMC — вендорові вони не потрібні |
| Абзац 2 (що вже прочитали) | §0 п. 2 цього аркуша | — |
| 1. Сума з доставкою | сторінка продукту («including shipping to your country») | місто й індекс — плейсхолдер; адресу, одержувача й телефон вписує founder лише в Gmail (прецедент MERA) |
| 2. Покупець і оплата | драбина [`rfq_registry`](rfq_registry.md) §3 (щабель 1, ФОП — щабель 2); «No prepayment is required» | реквізити — лише в рахунку, не в листі |
| 3. Комплект | прайс (адаптер «may be complementary»); посібник монтажу (гвинт і гайки) | — |
| 4. Перевірка вдома | дописка «TOMST на той самий домашній стенд» (присуд складу) і крок 5 [`ktr_home_stand_sheet`](../hardware/ktr_home_stand_sheet.md); посібник: «You can also use the Lolly Manager to check the current preload value»; чи вміє це TOMST Lolly для Android — сайт не каже | підсилення, AMC, наш датчик — лише «step by step» проти мікрометричної головки |

Немає також: пересилки через адресу в ЄС (§0 п. 3), питання про мороз (сторінка продукту), ПДВ (рахунок поза ЄС розписує сам виробник — прайс), питання про Old Lolly (§0 п. 4), трекер-ID, канон-рефів, дат і гліфів (`copy_region_check`).

## 2. Dispatch checklist

- [ ] ⚖️ «так» founder-а на текст і на голос покупця (щабель 1, ФОП — запасним реченням; «так» на голос попереднього листа сюди не переходить), відповідь на §0 п. 4 (чим зчитувати); ціни прайсу переміряти, статус юрособи звірити в день відправки
- [ ] 👤 відправка з особистої скриньки ([`rfq_registry`](rfq_registry.md) §3, «Відправник листів»); одне нагадування — на сьомий робочий день тиші (там же)
- [ ] 👤 після відповіді — замовлення; ціни й суми з відповіді в дерево не йдуть (`legal-business` §Межі #3), лише висновок про канал і строк

---

## 📤 Dispatch block (EN) — TOMST email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала: €107 і €49 без ПДВ, «may be complementary», «including shipping to your country», «No prepayment is required» — прайс і сторінка продукту (§0 п. 2), переміряти в день відправки. Мова — англійська: сайт виробника має EN-версію. Підпис — за правилом відправника [`rfq_registry`](rfq_registry.md) §3.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Quotation request: 1 × Point Dendrometer and 1 × TMD adapter, delivery to Ukraine

Dear TOMST team,

I would like to buy **one Point Dendrometer** and **one TMD adapter**. The dendrometer will be the reference instrument on a single pine tree in Ukraine: I plan to test it at home this winter and install it on the tree before the growing season starts in spring.

Your 2026 price list gives €107 for the Point Dendrometer and €49 for the TMD adapter, without VAT, and says the adapter may come as a hardware bonus. Your product page says that a quotation includes shipping to my country and that no prepayment is required. This is a quotation request, not yet an order; inline answers in this email are fine.

1. **Total with delivery to Ukraine.** Please quote the total for both items with delivery to `[delivery city and postal code — fill in before sending]`, Ukraine, with the carrier and the expected delivery time.
2. **Buyer and payment.** The buyer would be me personally, a private individual in Ukraine; if you prefer a business customer, I can buy through my sole proprietorship registered in Ukraine. Does "no prepayment" also apply to a buyer outside the EU, and which payment methods do you accept?
3. **What is in the box.** Please confirm that the dendrometer ships with its mounting screw and nuts, and show in the quotation whether the TMD adapter comes as the hardware bonus your price list mentions.
4. **Checking it at home.** Before installing it, I want to check the dendrometer against a micrometer head at home, step by step. Your installation guide says that Lolly Manager can show the current preload value. Can TOMST Lolly for Android show the current reading live?

Thank you in advance.

Best regards,
Oleksii Lukin

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## Cross-references

- Присуд складу пілота — [`01_03 §4`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) ⊕ «П3 — склад пілота»; стан і ноги — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.54.
- Домашній стенд, на якому TOMST калібрують головкою, — [`ktr_home_stand_sheet`](../hardware/ktr_home_stand_sheet.md).
- Ринкові числа TOMST (рівні джерел) — [`dendrometer_market_scan`](../business/dendrometer_market_scan.md).
- Прохання власникові сосни (два отвори — гвинт TOMST і Ti-стрижень) — [`pilot_tree_owner_request`](../outreach/pilot_tree_owner_request.md).
