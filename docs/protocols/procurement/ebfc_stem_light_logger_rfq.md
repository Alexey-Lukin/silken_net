# Логер зимового світла на грані стовбура — запит CiK Solutions (HOBO MX2309 ×1)

> RFQ-аркуш, **не канон** · ⏳ Станом на 2026-11-09 · стан — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.54, нога «Р3(б)(4) — замовити 1 × HOBO MX2309» · предмет, вимоги, прилад і канал — [`stem_face_winter_light`](../ebfc/stem_face_winter_light.md) §2 (⚖️ founder 2026-10-27; склад — один прилад на південній грані проти ERA5, ⚖️ founder 2026-11-09, там же ⊕), тут не переказуються · адресат — CiK Solutions GmbH (Карлсруе), `info@cik-solutions.com` — видимий текст шапки й сторінки доставки сайту, звірено 2026-11-09 · **надіслано 2026-11-09 на «так» founder-а** (журнал надісланого — корпус памʼяті; дата нагадування — нога HW.54).

## 0. Як користуватись

1. **Це запит, не замовлення.** Замовлення й оплата — 👤 founder після відповіді; лист нічого не купує.
2. **Що закрито сайтом CIK до тексту** (браузер, `cik-solutions.com`, 2026-11-09 — правило `legal-business` §Доменні правила #14):
   - сторінка «Zahlung und Versand»: тарифи доставки названо лише для Німеччини, Австрії й Швейцарії; оплата рахунком — лише для адрес у Німеччині; передоплата переказом, PayPal і картка — є;
   - AGB (редакція 14.04.2022, п. 1.1) діють щодо «gewerblichen Kunden», а форма контакту вимагає поле «Firma» — тож голос покупця в листі — ФОП founder-а, щабель 2 драбини [`rfq_registry`](rfq_registry.md) §3: сферу дії AGB — комерційні клієнти — вендор опублікував заздалегідь, і ми читаємо її як вимогу субʼєкта господарювання;
   - картка MX2309: €550 без ПДВ, «Verfügbar, Lieferzeit 5-8 Werktage» — ті самі числа, що в аркуші §2 від 2026-10-27, тож окремого питання про наявність лист не ставить; «Lieferumfang» — логер, гвинти, стяжки, батарею не названо.
3. **Що лишилось питанням і чому.** Батарея — проханням підтвердити: пошук на сайті Onset прямої відповіді не дав (каталог рендерить JS), тобто це сліпа зона приладу, а не відповідь. Доставку в Україну й покупця-ФОП знає лише продавець.
4. **Відповідь «ні» на доставку й на пересилку** → запасний канал Tempcon (аркуш §2 «Канал»), окремим листом на «так».

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт | Звідки | Свідомо НЕМАЄ |
|---|---|---|
| Абзац 1 (що й навіщо) | аркуш §0, §3 (грудень–лютий) | R, ERA5, модель `110`, PV на куполі, назва проєкту — вендорові вони не потрібні |
| Абзац 2 (що вже прочитали) | §0 п. 2 цього аркуша | наше прочитання AGB як вимоги — поданий факт, без висновку за CIK |
| 1. Доставка | аркуш §2 «Канал», найслабша ланка (1) | місто й адреса — дає founder у мить замовлення; адреси пересилки в ЄС у дереві немає |
| 2. Покупець і оплата | AGB п. 1.1; драбина `rfq_registry` §3 | реквізити ФОП — лише в рахунку, не в листі |
| 3. Батарея | аркуш §2 «Канал» («чи стоїть батарея»); Lieferumfang CIK | — |

Немає також: питання про наявність (сайт каже «Verfügbar»), фіксатора 2003S і партії приладів (склад — один прилад без опори), трекер-ID, канон-рефів, дат і гліфів (`copy_region_check`).

## 2. Dispatch checklist

- [x] ⚖️ «так» founder-а на версію на один прилад і на голос покупця — ФОП (§0 п. 2); ціну й «Verfügbar» переміряно на картці в день відправки
- [ ] 👤 після відповіді: замовлення → нога HW.54 «замовити 1 × HOBO MX2309»; ціни з відповіді — у дерево не йдуть (`legal-business` §Межі #3), лише висновок про канал і строк

---

## 📤 Dispatch block (EN) — CiK Solutions email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала: €550 і 5–8 робочих днів — картка CIK (§0 п. 2); грудень–лютий — аркуш §3. Мова — англійська: сайт CIK має EN-версію, лист дозволяє відповідати німецькою.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Enquiry: 1 × HOBO MX2309, delivery to Ukraine by the end of November

Dear CiK Solutions team,

I would like to buy **one HOBO MX2309** data logger (temperature, RH and solar radiation). It is for a winter field measurement of sunlight on the face of a tree trunk in Ukraine. The measurement runs from early December to the end of February, so I need the logger in Ukraine by the end of November.

Your shop lists the MX2309 at €550, available, with delivery in 5–8 working days. Your shipping page names Germany, Austria and Switzerland, and your terms apply to commercial customers, so I have a few questions before ordering. This is an enquiry, not yet an order. Inline answers in this email are fine, in English or German.

1. **Delivery to Ukraine.** Can you ship to Ukraine? If yes, please give the total price including delivery, the carrier and the expected delivery time. If not, can you ship to an address in the EU that I would give you, for onward forwarding, and how would the invoice be made out in that case?
2. **Buyer and payment.** The buyer would be my sole proprietorship registered in Ukraine (an individual entrepreneur). Do you accept such a customer, and which payment methods are open to a customer outside the EU?
3. **Battery.** Your delivery scope lists the logger, screws and cable ties. Please confirm that the logger ships with its battery installed.

Thank you in advance.

`[sender's signature — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 3. Cross-references

| Ресурс | Що там |
|---|---|
| [`stem_face_winter_light`](../ebfc/stem_face_winter_light.md) §2 | вимоги, обраний прилад і його склад, канал, монтаж, найслабші ланки |
| [`01_03 §4`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | ⚖️ Р3(б)(4) і звуження складу — навіщо міряти світло на грані |
| [`rfq_registry`](rfq_registry.md) §1 · §3 | рядок аркуша · драбина покупця й правило нагадування |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.54 | стан ноги замовлення |
