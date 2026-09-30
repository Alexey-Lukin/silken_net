# Soldier — rigid-flex замість пари B2B (дві круглі деки + гнучка ділянка): лист виробникові плат

> **Що це:** RFQ-аркуш до **виробника rigid-flex плат**. Предмет — порівняти за ціною й технологією дві гілки зʼєднання двох дек капсули Soldier: пару B2B Samtec FW-SM + CLP (носій ⚖️ делеговано 2026-09-24, лист [`node_b2b_connector_rfq`](node_b2b_connector_rfq.md)) і одну rigid-flex плату, де дві круглі жорсткі деки зʼєднані гнучкою ділянкою. ⚖️ founder 2026-09-29 відкрив корінь заради контуру плати й велів переглянути rigid-flex тим самим рухом ([`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md), [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9 · HW.29): рішення 2026-07-03 «rigid-flex deferred» судило лише механічну точку відмови, а нова підстава — площа (−88 мм² пари B2B; ціль контуру з коренем Ø19.97, rigid-flex ≈ 18.54 — ⚖️ делеговано 2026-09-30; доти 19.5 → 18.1 під обвідну бустерів). Лист купує ЧИСЛА для цього перегляду; сам перегляд — наш.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-29, не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Адресата не обрано: лист один і без імені в тексті, адресата обирає founder серед виробників із rigid-flex у переліку послуг. Числа дзеркалять доми, дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29, нога «котирування rigid-flex проти пари FW/CLP».
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Капсула електроніка» · hard-constraint дім §4.D).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)): специфікація відкрита, NDA — лише на комерційні умови.

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Rigid-flex — окрема технологія, її роблять не всі фабрики плат, тож адресат — виробник із rigid-flex у переліку послуг; UA-носія ми не шукали, тому **лист англійською**. Текст однаковий для будь-якого адресата.
2. **Ціна — не єдине питання.** Порівняння з парою B2B стоїть на трьох осях: ціна вузла (пара B2B — «~$0.85» без котирування, rigid-flex — «~+$1.50», джерела обох чисел у дереві немає, [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 і §5.3), площа (−88.3 мм², калькулятор `tools/firmware/board_area_budget.rb`) і висота стеку. Лист питає й третю: як rigid-flex задає проміжок між деками (8–10 мм сьогодні несе мейтована висота пари B2B, і саме вона тримає зазор антена↔Ti — [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md)).
3. **Габарит — орієнтовний.** Розкладки немає ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9); ціль контуру живе в [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) — під обвідну бустерів (⚖️ делеговано 2026-09-29), і з rigid-flex, і з парою B2B у межах 18–20 мм. Лист каже «about 18–20 mm». ⛔ Точні цілі калькулятора в лист не йдуть: це не креслярські розміри.
4. **Згин — статичний:** плату згинають один раз при збиранні, і далі вона не рухається. Лист питає мінімальний радіус і довжину гнучкої ділянки під складання «дека над декою» з проміжком 8–10 мм; сам проміжок у такій конструкції тримає механічна стійка, а не зʼєднувач — і це теж питання листа.
5. **Покриття.** Серія йде під Parylene C ≈ 10 µm ([`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)); лист питає, чи є обмеження для гнучкої ділянки. ⊕ Побічний виграш rigid-flex для лист [`node_parylene_rfq`](node_parylene_rfq.md): маскувати контакти мезоніна вже не треба.
6. **Відповідь у репо не комітиться:** ціни, стек-апи й номери документів виробника — чужі операційні факти. У [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29 іде лише наш висновок.

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Вступ і мета** | [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) (присуд про корінь, rigid-flex — переглядається) · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29 | фактом: дві гілки, обираємо за відповіддю | наші відсотки площі · історія FTSH/CLT |
| **Дві деки ≈ 18–20 мм** | [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) (ціль — під обвідну бустерів; з rigid-flex і з парою — у межах 18–20 мм) | «about 18–20 mm, round, indicative» | точні цілі калькулятора |
| **Жорсткі ділянки: FR4, 4 шари, 1.6 мм, HASL/ENIG** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 8 | фактом для жорстких; для гнучкої — питанням | — |
| **Лінії через гнучку ділянку** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 12 (3V3, GND, VSTOR_sense, EBFC_sense, BQ25570 EN — 5–7 ліній) | фактом: живлення + повільні аналогові й цифрові лінії, без високих частот | назви ліній |
| **Проміжок 8–10 мм** | [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) (стек антена↔Ti) · [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (вертикальний бюджет `52`) | вимогою: «8–10 mm between the decks»; як його тримати — питанням | числа бюджету `52` · корона |
| **Компоненти** | [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 3 (EDLC THT, H 5.2) · [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (2 pogo-піни на нижній деці) | фактом: SMD + одна THT-деталь, найвища ≈ 5 мм | P/N |
| **Середовище й покриття** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (−40…+85 °C) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (Parylene C ≈ 10 µm у серії) | фактом; обмеження для гнучкої ділянки — питанням | «20 років» (дім має анкер, не капсула) |
| **Порівняння з парою B2B** | [`node_b2b_connector_rfq`](node_b2b_connector_rfq.md) | фактом: «we are comparing against a board-to-board connector pair» | ціну й P/N пари |
| **Кількості** | [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) (1K) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) (10k) | прототипи 5–10 · 100 · 1 000 · 10 000 — орієнтиром | наша цільова собівартість |

---

## 2. Dispatch checklist

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Адресата обирає founder** — виробник із rigid-flex у переліку послуг; текст без імені.
- [ ] 👤 **Після відповіді:** ціна й технологічні межі → висновок у [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29 (перегляд «rigid-flex ⊥ пара B2B» — наш, із трьома осями §0 п. 2); якщо обрано rigid-flex — ціль контуру [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) переходить на рядок rigid-flex, а лист [`node_b2b_connector_rfq`](node_b2b_connector_rfq.md) знімається; цін не комітити (§0 п. 6).

---

## 📤 Dispatch block (EN) — rigid-flex PCB quotation email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): дві круглі жорсткі деки ≈ 18–20 мм · FR4 4 шари 1.6 мм HASL/ENIG · 5–7 ліній без високих частот · проміжок 8–10 мм · SMD + одна THT ≈ 5 мм · 2 pogo-піни на нижній деці · −40…+85 °C · Parylene C ≈ 10 µm у серії · кількості 5–10 / 100 / 1 000 / 10 000. Питає те, чого канон не несе: стек-ап гнучкої ділянки · мінімальний радіус і довжину під статичний згин · як тримати проміжок · обмеження покриття · панелізацію двох круглих ділянок · ціну й строк на кожну кількість. **Немає свідомо:** цілей калькулятора · відсотків площі · ціни й P/N пари B2B · трекер-ID, канон-рефів, дат і гліфів.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** RFQ — small rigid-flex PCB: two round rigid sections joined by a flex section, folded once; stack-up, bend design, price and lead time

Dear colleagues,

**About us and the purpose of this enquiry.** We are an R&D project in Ukraine developing a sensor node for forest monitoring. Its electronics sit in a small sealed capsule on two round circuit boards stacked one above the other. Today we plan to join the two boards with a board-to-board connector pair; we are now comparing that against a single **rigid-flex** board in which the two round rigid sections are joined by a flex section and folded once at assembly. This is a request for information and an indicative quotation, not yet an order. Answering commits neither side to anything, and inline answers in this email are fine. The layout is **not frozen yet**, so all dimensions below are indicative.

**What we have in mind (indicative)**

- **Two rigid sections**, each round, **about 18–20 mm in diameter**; FR4, 4 layers, 1.6 mm thick, HASL or ENIG.
- **One flex section** joining them, carrying five to seven lines: a 3.3 V supply and ground, two slow analog sense lines and a few slow digital enable lines — no high-speed or RF signals.
- **Folded once at assembly (static bend)**, so that one rigid section sits above the other with **8–10 mm between them**; after assembly the flex does not move.
- **Components:** SMD parts plus one through-hole part (a horizontal supercapacitor about 5 mm high, the tallest component); two spring-loaded contact pins on the underside of the lower section.
- **Environment:** inside a capsule sealed with an O-ring and filled with air; −40 to +85 °C over many years of outdoor service. In series production the assembly will be coated with Parylene C, about 10 µm thick.

**Please tell us**

1. **Stack-up.** Which stack-up would you propose for the flex section (layer count, polyimide thickness, coverlay, adhesive or adhesiveless), and does the 4-layer 1.6 mm rigid section fit your standard rigid-flex constructions?
2. **Bend design.** For a one-time 180° fold with 8–10 mm between the rigid sections: the minimum bend radius you recommend, the flex length you would design for, and any rules for copper in the bend area (e.g. hatched planes, conductor direction).
3. **Holding the gap.** In your experience, should the 8–10 mm gap be held by a separate mechanical spacer or standoff between the two rigid sections, by stiffeners, or otherwise? What tolerance on that gap can we expect?
4. **Coating.** Any limitations for Parylene C (≈ 10 µm) on the flex section or at the rigid-to-flex transition?
5. **Panelisation.** How would you panelise two small round rigid sections with a flex section between them, and what outline tolerance do you hold?
6. **Price and lead time** for 5–10 prototypes, 100, 1 000 and 10 000 pieces (bare boards; please also tell us whether you offer assembly).
7. **What you need from us** to quote firmly: file formats, a stack-up drawing, fold and bend drawings.
8. **Quality and documents:** your quality system (for example ISO 9001), the standards you build to (for example IPC-6013 class), and what you issue per lot.
9. **Commercial:** quote currency and validity, payment terms, shipping to Ukraine, and a technical point of contact.

**Confidentiality.** The technical specification of our device is openly published, so no confidentiality agreement is needed to discuss it. We are happy to sign your standard agreement covering commercial terms.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 3. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_01 §3.5`](../../02_01_Hardware_Architecture_and_BOM.md) · `tools/firmware/board_area_budget.rb` | ціль контуру з rigid-flex і з парою B2B · площа |
| [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 8 · 12 · [`02_01 §5.3`](../../02_01_Hardware_Architecture_and_BOM.md) | плата · лінії зʼєднання · проміжок і зазор антена↔Ti |
| [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | температура · покриття · вертикальний бюджет |
| [`node_b2b_connector_rfq`](node_b2b_connector_rfq.md) · [`node_parylene_rfq`](node_parylene_rfq.md) | гілка-суперник · маскування мезоніна, яке rigid-flex знімає |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.29 · HW.9 | дім стану · розкладка |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс |
