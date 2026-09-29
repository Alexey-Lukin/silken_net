# Радом Солдата — марка PEEK із сонячною поглинальною здатністю α ≤ 0.5: лист постачальникові матеріалу

> **Що це:** RFQ-аркуш до **постачальника матеріалу** радома — виробника PEEK-компаундів чи кольорових концентратів під PEEK (задекларована альтернатива — UV-стійкий PC/ASA). Предмет — **марка з виміряною сонячною поглинальною здатністю α ≤ 0.5** і з діелектричними εr / tan δ саме ПІГМЕНТОВАНОЇ марки на 868 МГц. Присуд «задається α, а не колір» уже ухвалено (⚖️ делеговано 2026-09-27, [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md)), тож лист його не ставить під сумнів — він купує марку й числа, яких у дереві немає. Виробникові деталі (ЧПК або лиття) питання марки й α ставить аркуш `tools/cad/cem/radome.json`; цей лист — на крок раніше, про сам матеріал.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-29, не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Адресата не обрано: лист один і без імені в тексті, адресата обирає founder. Числа дзеркалять доми, дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37, нога «марка радома з виміряним α ≤ 0.5».
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Анкер hardware» · hard-constraint дім §4.B/§4.C).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)): специфікація відкрита, NDA — лише на комерційні умови.

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Виробники PEEK-компаундів і кольорових концентратів — поза UA, тож **лист англійською**. Якщо адресат постачає й PC/ASA, п. 6 листа питає альтернативу; окремого листа під неї немає.
2. **α — властивість марки, а не кольору, і лист просить ВИМІР.** Низьке α для приглушеного тону можливе лише з NIR-відбивним («cool») пігментом, а світле — з UV-стабільним (TiO₂); звичайний коричневий пігмент (α ≈ 0.9+) виключено ([`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md)). Лист просить виміряне α або сонячну відбивну здатність із методом, а не назву кольору.
3. **Найслабша ланка присуду — КОЛИ α ≤ 0.5.** Непігментований PEEK на сонці темнішає, тож α росте з роками, а присуд не каже, чи тримати α на прийманні, чи наприкінці служби ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37). Тому п. 3 листа питає дані після UV-старіння — відповідь закриває саме цю ланку.
4. **Пігмент зсуває RF-числа.** Канон тримає εr = 3.2 і tan δ = 0.003 на 868 МГц для НЕпігментованого PEEK ([`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md)); п. 4 листа питає числа пігментованої марки з частотою й методом виміру. Остаточне приймання — RF-перевірка під радомом ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.17), а не паспорт.
5. **Геометрія — орієнтовна.** Купол ≈ Ø25 розморожено присудом про корінь (⚖️ founder 2026-09-29): ціль — радом ≈ Ø29 ([`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md)); стінка в RF-вікні 1.5–2.0 мм ([`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md)). Лист каже «about 25–30 mm». ⛔ Вигляд RAL 8007 («мімікрія під кору») лист не вимагає, а питає, чи він досяжний при α ≤ 0.5 — це в дереві не звірено.
6. **Відповідь у репо не комітиться:** ціни й номери документів постачальника — чужі операційні факти. У [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37 іде лише наш висновок; виміряне α марки, якщо його дадуть, стає входом скрипта `71` (огинаюча капсули, [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md)).

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Вступ: що й навіщо** | [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) (Деталь 4 — PEEK-радом; присуд про α, ⚖️ делеговано 2026-09-27) | фактом | підстава присуду (скрипт `71`, ERA5, запас EDLC до 70 °C) |
| **α ≤ 0.5, виміряне** | [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) · `tools/cad/cem/radome.json` (`notes.surface_finish`) | вимогою; метод — питанням | «RAL 8007» як вимога |
| **UV-старіння** | [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37 (найслабша ланка: коли α ≤ 0.5) | питанням: дані після старіння, метод | — |
| **εr / tan δ на 868 МГц** | [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) (3.2 / 0.003 для непігментованого) · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.17 | питанням: числа пігментованої марки, частота, метод | наші числа RF-бюджету |
| **Геометрія ≈ 25–30 мм, стінка 1.5–2.0** | [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) (радом ≈ Ø29) · [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) | орієнтовно | вушка байонета · прилив · корона |
| **Процес і форма постачання** | [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) (радом — лиття) · [`ua_vendor_map`](ua_vendor_map.md) (ЧПК-цех як кандидат на радом) | питанням: гранули під лиття ⊥ заготовки під ЧПК | назви цехів |
| **Середовище** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (−40…+85 °C) · [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) (зовні, сонце, дощ) | фактом; «багаторічна служба» — без числа | «20 років» |
| **Не біоконтактна деталь** | `tools/cad/cem/radome.json` (`notes.material`: «Not a bio-contact part») | фактом — щоб не купувати медичну марку без потреби | суперечність із рядком «Medical Grade» у [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) (⚠️ відкрита — нижче) |
| **Альтернатива PC/ASA** | [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) (задекларована, той самий α ≤ 0.5) | питанням, одним пунктом | — |

⚠️ **Розбіжність, яку лист виявив і не розсуджує:** специфікація радома в [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) пише «PEEK, Medical Grade», а `radome.json` — «Not a bio-contact part». Лист питає обидва класи марок (п. 5) і нічого не стверджує; вибір класу — за [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37.

---

## 2. Dispatch checklist

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Адресата обирає founder** — виробник PEEK-компаундів або кольорових концентратів під PEEK; текст без імені.
- [ ] 👤 **Після відповіді:** марка, α (до й після старіння), εr / tan δ → висновок у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37; виміряне α — вхід `71`; RF-числа — вхід перевірки під радомом ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.17); цін не комітити (§0 п. 6).

---

## 📤 Dispatch block (EN) — radome material enquiry

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): PEEK (або PC/ASA) · α ≤ 0.5 виміряне · UV-старіння · εr / tan δ пігментованої марки на 868 МГц · купол ≈ 25–30 мм, стінка 1.5–2.0 мм · −40…+85 °C, зовні · не біоконтактна деталь. Питає те, чого канон не несе: марку й пігмент · α і метод · дані після старіння · діелектричні числа марки · форму постачання · кількості й ціну. **Немає свідомо:** підстави присуду · RAL-вимоги · наших RF-бюджетів · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Enquiry — pigmented PEEK grade with low solar absorptance (α ≤ 0.5) for a small outdoor radome at 868 MHz: optical, ageing and dielectric data

Dear colleagues,

**About us and the purpose of this enquiry.** We are an R&D project in Ukraine developing a sensor node for forest monitoring. The electronics sit in a small sealed capsule mounted on a tree trunk, under a **radome** — a small dome about 25–30 mm in diameter with a wall of 1.5–2.0 mm, through which a 868 MHz antenna radiates. The radome is outdoors in direct sun for many years, and the electronics inside are temperature-sensitive, so we specify its outer shell by **solar absorptance α ≤ 0.5**, not by colour. We are looking for a material grade that meets this, and we need its optical, ageing and dielectric data. This is a request for information, not yet an order; answering commits neither side to anything, and inline answers are fine.

**Please tell us**

1. **Grades.** Which of your PEEK grades or colour concentrates for PEEK can give a solar absorptance **α ≤ 0.5** — either a light, UV-stable pigmentation (for example TiO₂-based) or a darker, bark-like tone with an **NIR-reflective ("cool") pigment**? Is a muted brown or grey tone (for example close to RAL 8007) achievable at α ≤ 0.5, or only lighter colours?
2. **Measured α.** For each grade, the **measured** solar absorptance or solar reflectance, the method (for example ASTM E903 or equivalent) and the sample thickness.
3. **Ageing.** Do you have data on how α (or colour) changes after UV / weathering exposure — for example xenon-arc per ISO 4892-2 — and after how many hours? Unpigmented PEEK darkens in sunlight; we need to know whether α stays ≤ 0.5 after ageing, not only as delivered.
4. **Dielectric properties.** For the **pigmented** grade: the relative permittivity εr and loss tangent tan δ near 868 MHz (or the nearest frequency you have measured), with the method and temperature. We know the values for unfilled PEEK; pigments shift them, and the antenna sits behind this wall.
5. **Grade class.** The radome does not contact tissue or food. Please tell us whether your low-α grades exist as industrial grades, as medical grades, or both, and the price difference.
6. **Alternative.** If you also supply UV-stable PC/ASA, the same questions (1–4) for a PC/ASA grade.
7. **Supply form and processing.** Pellets for injection moulding and/or stock shapes (rod) for machining; minimum order quantities for prototypes and for series (orientation: prototypes, then 1 000 and 10 000 radomes); processing notes that affect the colour or α (drying, moulding temperature, machining).
8. **Documents.** Technical and safety data sheets for the proposed grades, and your quality certificates.
9. **Commercial.** Indicative price per kg for each form and quantity, lead time, shipping to Ukraine, and a technical point of contact.

**Confidentiality.** The technical specification of our device is openly published, so no confidentiality agreement is needed to discuss it. We are happy to sign your standard agreement covering commercial terms.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 3. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_01 §5.2`](../../02_01_Hardware_Architecture_and_BOM.md) | Деталь 4 — радом: матеріал, стінка, εr / tan δ непігментованого PEEK, присуд про α |
| [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_03 §12.1`](../../02_03_BQ25570_MPPT_Nano_Power.md) | розмір купола під корінь · скрипт `71`, для якого α — вхід |
| `tools/cad/cem/radome.json` | питання марки й α виробникові ДЕТАЛІ · «Not a bio-contact part» |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.37 · HW.17 | дім стану · RF-перевірка під радомом |
| [`rfq_registry`](rfq_registry.md) · [`ua_vendor_map`](ua_vendor_map.md) | procurement-індекс · цехи ЧПК |
