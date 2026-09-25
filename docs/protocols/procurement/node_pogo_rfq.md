# Soldier — pogo-піни сліпого зʼєднання капсула ↔ анкер (Mill-Max 0906 / 0908): технічний запит виробникові або дистриб'юторові

> **Що це:** RFQ-аркуш — технічний запит до **Mill-Max** (виробник, якого називає канон [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) або до дистриб'ютора з проханням передати текст інженерам виробника. Предмет — **два пружинні контакти** капсули Soldier, що сідають на анкер наосліп. Лист питає те, від чого залежить вибір P/N і три прилади за ним: **механічне креслення пружини** (першим, ⚖️ 2026-09-22) · **чи є варіант покриття 30 µ″** · **хід, висоту й сили з допусками** · **ресурс і опір контакту в наших умовах** · **наконечник під ціль Ø1.0**. **Лист питає й висновків не повідомляє:** рамки втоми `59`, S-N-якорі й наш цикловий аналіз у текст не йдуть.
> **Статус:** 🟡 робочий артефакт (не канон); **написано 2026-09-25, не надіслано, founder тексту ще не бачив — ⛔ до „так“ не надсилати.** Адресата не обрано й не контактовано. Числа дзеркалять доми, і дім кожного названо в §1; **правити в домі, не тут** (One-Home, [`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)). Дім стану — [`00_07`](../../00_07_Action_Plan_Tracker.md) **HW.9** (нога «при виборі P/N спитати креслення пружини») і **HW.43** (споживач креслення); відповіді сідають і в HW.8 (8.1 покриття · 8.3 сила й хід · 8.6 співвісність · 8.7 Z-стек).
> **Частина procurement-реєстру** → [`rfq_registry`](rfq_registry.md) (рядок «Капсула електроніка»; pogo досі перелічено й у рядку «Анкер hardware»). ⚠️ **Hard-constraint дому в `rfq_registry` §4 pogo не має:** §4.B — метал анкера, §4.D — електроніка без рядка pogo; обмеження піна живуть прямо в [`02_02 §2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md).
>
> ℹ️ **IP:** defensive-publication ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)): специфікація відкрита, CDA — лише на комерційні умови. ⚠️ Але креслення пружини — ЧУЖІ дані каталожної деталі, і `59` зі своїм кешем публічний: якщо вендор позначить креслення непублічним, у дерево йде лише наш висновок (§0 п. 7).

---

## 0. Як користуватись + cover-note

1. **Адресат і мова.** Перший адресат — інженери застосувань Mill-Max; якщо виробник не відповідає — дистриб'ютор, перший абзац листа вже просить переслати текст виробникові. Імені контактної особи канон не називає, тож лист без імені. Адресат поза UA — **лист англійською**.
2. **Базовий кейс + дельти, а не прайс на каталог.** Базовий кейс — **`0906-1-15-20-75-14-11-0`**: це єдиний P/N, чий даташит прочитано ([`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) ⚠️), і лист прямо каже, що він базовий лише тому. Дельти: (а) той самий пін із 30 µ″ Au; (б) відповідник серії **0908**; (в) варіант монтажу (SMT ⊥ TH, [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) — «SMD або Through-Hole», не обрано).
3. **Чи вирішує лист відкритий ⚖️ (скіл `legal-business` §Доменні правила #4) — звірено з трекером, по кожному «we …»:**
   - **Серія.** Не відкритий присуд із гілками, а **відкритий вибір, який ратифікований ⚖️ 2026-09-18 ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.43) свідомо лишив HW.9** («0906 або 0908 — обирає HW.9»). Лист не бере бік: питає обидві серії й жодної не замовляє. ⚠️ Відповідь може **перевідкрити** той присуд: за Validation Gate [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), якщо 0908 покаже іншу пружину чи хід, HW.43 повертається до форми «обрати серію й сплав» — тому п. 1c і 3a питають сплав і хід для ОБОХ серій (дані 0908 дотепер — лише сторінка серії й Digi-Key).
   - **Сила.** Канон тримає ~98 г @ повний хід (spec-freeze 07-03) і сам пише, що даташит цього числа не несе (60 ± 20 г на середині ходу), а «яке правдиве — скаже P/N HW.9». Лист подає **обидва числа** й питає, чи вони сумісні для однієї пружини; ⛔ не вимагає 98 г і не просить іншої пружини (→ «Немає свідомо»).
   - **Хід 1.40 ± 0.13 і покриття 0.76 / 1.27 мкм** — ратифіковані (⚖️ 2026-09-18 · founder 07-03): лист подає їх як базу проєкту й просить підтвердити, а 30 µ″ — питанням наявності з гілкою «якщо ні — найтовще, що є».
   - **Маршрут золочення площадки** (HW.8.2, ⚖️ 2026-09-22 — обирає гальванік) — не предмет цього листа; тут лише вимога канону «тверде золото» ([`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (б)).
   - **Наконечник і монтаж** — відкриті до P/N: лист просить рекомендацію, а не замовляє форму.
4. **Чому креслення пружини — перше питання, і чому в ньому ЧОТИРИ числа, а не два.** Порядок «першим креслення, потім вимір» ратифіковано ⚖️ 2026-09-22 ([`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), врізка). Трекер формулює запит як «Ø дроту та жорсткість», але для гвинтової пружини дотичне напруження `τ = 8·F·D·K_w / (π·d³)` при `F = k·δ` вимагає ще **середнього діаметра витка D** (або числа робочих витків n, з якого D виводиться через `k = G·d⁴ / (8·D³·n)`): пара (d, k) — **необхідна, але не достатня**, і відповідь «ось d і k» мм у МПа не перекладе. Лист тому просить повне креслення й явно називає d · D · n · вільну довжину · k · попереднє підтискання. Запасний хід на випадок відмови — **допустима амплітуда прямо**, як його називає «Ціна» того ж присуду (п. 1b); тоді рамка стає вендорською ДЕКЛАРАЦІЄЮ, а не нашим розрахунком.
5. **Питання про висоту піна закриває діру, якої доти не бачив жоден прилад.** У `52_z_stack_tolerance` ланцюг спільного проміжку `TOL_PZ` має п'ять членів (DMLS · FR4 ×2 · B2B · CNC) і **жодного члена самого піна**: `POGO_FREE` виведено як проєктну ціль («щоб пін сидів на 60 % при номінальному проміжку»), а не взято з креслення. Отже вільна висота піна над платою після пайки та її допуск — вхід, якого Z-стек не має; п. 3b його питає. Застосувати відповідь у `52` — робота оркестратора/HW.8.7, не цього листа.
6. **Чого вендор не дасть — і лист цього не купує.** Амплітуду мікро-деформації від гойдання ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.43, нога (1)) і стендовий вимір Rc та сили (HW.8.1 / 8.3) робимо МИ: продавець продає пін, а наш поріг міряється на нашому стеку. Вендорські дані про ресурс і Rc — апріорі для стенду, не заміна йому.
7. **Відповідь у репо не комітиться сирою.** Ціни, строки й внутрішні дані випробувань — чужі операційні факти. Креслення пружини: якщо вендор дозволить публікацію — числа сідають у `59`; якщо позначить непублічним — у дерево йде лише наш висновок (напруження проти якоря), а як тоді бути з публічним кешем `59`, вирішує founder. Лист прямо просить позначити непублічне (абзац «Confidentiality»).

---

## 1. Звідки кожен пункт листа — і що з нього свідомо прибрано

| Пункт листа | Дім | Як подано | Прибрано |
|---|---|---|---|
| **Вступ: анкер, капсула, два піни, байонет** | [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (коаксіал, 2 контакти) · [`02_02 §4.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (байонет 1/4 оберту) · [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (піни на нижньому шарі плати) · [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (осьовий хід) | фактом | полярність (GND/VIN_DC) · хімія EBFC · TRL |
| **Базовий кейс + альтернатива** | [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (серія «0906 або 0908 — обирає HW.9»; даташит прочитано лише для `0906-1-15-20-75-14-11-0`) · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.43 (найслабша ланка: дані 0908 — сторінка серії й Digi-Key) | дві серії без ранжування; «базовий, бо єдиний прочитаний» | серія «0909» (знято, 404) |
| **Два однакові піни** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 7 («2 шт») | фактом | ціна BOM ~$0.40 |
| **Електрика: ≈15 мкА … 0.5 мА, ≈0.5 В, Rc < 50 мОм** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (до 500 мкА · > 500 мВ · < 50 мОм) · [`02_02 §5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (cold-start 15 мкА → [`02_03 §1.5`](../../02_03_BQ25570_MPPT_Nano_Power.md)) | вимогою | пороги деградації (> 500 мОм · 1–2 кОм) — послабили б вимогу · розрахунок ΔV |
| **−40 … +85 °C** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | вимогою, п. 5e — підтвердити | — |
| **Покриття 0.76 мкм (30 µin) Au по 1.27 мкм (50 µin) Ni** | [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (✅ founder 07-03 — ПІН) | вимогою | ⛔ для площадки анкера не цитується (⚖️ 2026-09-22, [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) |
| **«-20-» = 20 µin (≈0.51 мкм)** | [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) ⚠️ ⊕ («чи є варіант 30 µ″, не перевірено») · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.43 | «we read … please correct us» | «на корпусі» — канон приписує код корпусу; яка деталь несе який код, лист ПИТАЄ (п. 2a), не стверджує |
| **Хід 1.40 мм (.055 in ± .005 in)** | [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (⚖️ 2026-09-18) | «as we read it from your datasheet» + п. 3a | 1.52 мм (верхній край допуску) · серія 0938 |
| **Робоче вікно 50–70 % (0.70–0.98 мм)** | [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (happy path) | фактом | залишкова смуга 52–68 % після спейсера · RSS ±0.45 · спейсер · hard-stop |
| **Сила ~98 г (0.96 Н) @ повний хід ⊥ 60 ± 20 г @ середина** | [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8.3 | обидва числа + п. 4b «чи сумісні» | що сила годує `52` (датум обода), `55`/`68` (тяга по шині) |
| **Сплав пружини BeCu C17200 per ASTM B194** | [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (властивість каталожної деталі, ⚖️ 2026-09-18) | «we read … please confirm for both series» (п. 1c) | код пружини #75 · S-N-якорі 240 МПа / 10¹⁰ |
| **Ціль центрального піна: торець дроту Ø1.0 урівень із гранню, полімерне кільце Ø ≥ 4.0** | [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (⚖️ 2026-09-18, HW.34) · [`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (дріт Ø1.0) · [`01_01 §3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (торець урівень — крок 4a) | фактом; кільце — «will be» (у CAD його ще немає) | лайнер 0.15 · канал Ø1.35 · закриття каналу · PEEK як назва |
| **Ціль зовнішнього піна: грань фланця Ø25; радіус і ширина зони — після піна** | [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (Ø25 frozen) · лист гальваніка п. 2 ([`anchor_pad_plating_rfq`](anchor_pad_plating_rfq.md)) | фактом + «depend on the pin we choose» | «Ø4–5» (мертвий концепт) |
| **Обидві плями — тверде золото** | [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) вимога (б) | фактом | маршрут, підшар, товщини площадки · термін «ENIG» |
| **Радіальний зазор ≈0.3 мм; XY-ланцюг не пораховано** | [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (зазор сокета 0.3 мм; «1.5 мм не виведене — немає ні діаметра наконечника, ні XY-ланцюга») · [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (0.3 мм = зазор сокета) · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.8.6 | «at least that much» | «60 % радіуса площадки» (наш висновок) |
| **Середовище: O-ring, повітря; волога й конденсат соку pH ≈5.75 не виключено** | [`02_02 §3.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §3.4`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) п. 3 (повітря) · [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (сценарій конденсату) · [`02_02 §5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) («в умовах вологості») · [`01_02 §2.1`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) (pH 5.75) | фактом | бічна серія 4.5 · провенанс pH |
| **Зʼєднань «порядку сотні» — наша оцінка** | [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (≈140; «~7/рік» дому не має) | без точного числа, «by our estimate» — узгоджено з листом гальваніка п. 7 | 140 · «≥ 50 000» (каталожний клас, не потреба) |
| **Гойдання: ≤ ≈4.7 × 10⁸ циклів за 20 років — верхня межа, не лічба** | [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) §HW.43 (стеля 4.67 × 10⁸ при верхньому прочитанні частоти) · канон-headline [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | стеля + одне речення межі «bounds the number, not the size» | дужка частот 0.26 ⊥ 0.74 Гц · duty-cycle · межі (2)–(3) · джерела |
| **Амплітуда не виміряна, очікуємо малу проти ходу** | [`01_01 §2`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (задум: хід компенсує мікрорухи; «без втоми — не встановлено») · [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.43 нога (1) | «we expect it to be small … not measured» | переклад «рух стовбура → pogo» (моделі немає) |
| **Каталожний ресурс 100 000–1 000 000 циклів (0906)** | [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) §HW.43 (таблиця) · кеш `59` (`contact_endurance_check.json`, sources) | «we read» + питання про умови рейтингу (п. 5a) | рамка A «FAILS» · рамка B · якорі |
| **Пад Ø2.5 · SMT ⊥ TH** | [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (футпринт «круглий pad ø 2.5 мм», джерела не названо; «SMD або TH») · [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (площадка ø 2.5) | питанням: «would a 2.5 mm round pad suit?» | thermal relief · «різний діаметр посадки» (§6 poka-yoke — не звірено, у лист не йде) |
| **Кількості 2 000 / 20 000 пінів** | [`02_06 §1.2`](../../02_06_Unit_Economics_and_BOM.md) (ціновий рівень 1K) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) (ціни на партію 10 000) · × 2 піни ([`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) | орієнтир ціни | наша цільова собівартість |
| **Конфіденційність** | [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) | специфікація відкрита; непублічне — позначити | — |

---

## 2. Питання листа → нога трекера (куди сідає відповідь)

| П. | Питання | Нога [`00_07`](../../00_07_Action_Plan_Tracker.md) | Що відповідь закриває — і що НЕ закриває |
|---|---|---|---|
| **1a** | креслення пружини: d · D · n · вільна довжина · k · попереднє підтискання | **HW.9** нога 👤 «спитати креслення пружини» → **HW.43** нога 🔗 «прийняти у `59`» (`missing_datum` «spring wire diameter/rate») | закриває ПЕРШИЙ із двох відсутніх входів рамки B. ⛔ Не закриває: амплітуду (HW.43 нога (1)) — отже й саму endurance-звірку |
| **1b** | запасний хід: допустима амплітуда, якщо креслення не дадуть | те саме (Ціна присуду [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)) | рамка стає вендорською декларацією, не нашим розрахунком |
| **1c** | сплав пружини для ОБОХ серій | **HW.43** `[x]` ⚖️ 2026-09-18 — Validation Gate [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | «BeCu для обох» — присуд стоїть; інша пружина в 0908 → присуд повертається до «обрати серію й сплав» |
| **2a–d** | коди покриття · 30 µin · найтовше, що є · тверде | **HW.8.1** (P/N при BOM HW.9) · ⊕ у HW.43 `[x]` «чи є варіант 30 µ″, не перевірено» | «є / код» — P/N рядка BOM; «немає» — ратифіковане 0.76 мкм зустрічається з каталогом, і це вже рішення founder-а, не листа |
| **3a** | номінал і допуск ходу для обох серій | **HW.8.3** (хід 1.40 ± 0.13 — номінал) · Validation Gate HW.43 | підтвердження або повернення присуду про хід |
| **3b** | вільна висота над платою після пайки + допуск | **HW.8.7** (Z-стек, спейсер) через перепрогін `52` | новий член `TOL_PZ`, якого ланцюг не має (§0 п. 5) |
| **4a–b** | сила vs хід із допусками; чи сумісні 98 г і 60 ± 20 г | **HW.8.3** (сила ~98–100 г) · Стан HW.8 ⚠️ | входи `52` (`POGO_SPRING_FORCE_N`, датум обода) і `55`/`68` (`F_POGO_N`, тяга по шині — HW.34). ⛔ Не закриває стендовий вимір сили |
| **5a–e** | умови рейтингу ресурсу · Rc на малих струмах · Rc після ресурсу й вологи · дані про малоамплітудний рух · температура | **HW.8.1** / **HW.8.3** (Rc bench) · **HW.43** (що саме означає каталожний ресурс — рамка A) · [`02_02 §5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) примітка («після 20 000+ циклів і в умовах вологості — верифікувати») | апріорі для стенду; ⛔ не заміна виміру Rc на нашому стеку |
| **6a–c** | наконечники · рекомендація під ціль Ø1.0 зі зсувом ≥ 0.3 · мінімальний розмір цілі | **HW.9** Стан («P/N піна (серія, наконечник) → … геометрія площини площадки й закриття каналу HW.34») → **HW.34** нога «застосувати геометрію площини площадки одним проходом» · **HW.8.6** (співвісність XY) | діаметр наконечника, якого бракує [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) для виведення «1.5 мм»; мінімальна ширина кільцевої зони — зустрічне питання до листа гальваніка п. 2 (там — найменша ширина, яку він ВИТРИМУЄ; тут — найменша, якої ПОТРЕБУЄ пін) |
| **7a–b** | SMT ⊥ TH · рекомендований футпринт · чи годиться пад 2.5 | **HW.9** (KiCad-розкладка) | звірка «пари» пін ↔ футпринт [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md), чий «рекомендований ø 2.5» джерела не має |
| **8a–d** | документи · зразки в Україну · ціна на 2 000 / 20 000 · контакт | **HW.9** (BOM) · [`02_01 §3.1`](../../02_01_Hardware_Architecture_and_BOM.md) поз. 7 | — |

⊕ **Пара деталей тут — не «пін + мейт виробника»** (скіл `legal-business` §Доменні правила #6(б)): зустрічної деталі Mill-Max не продає, ціль — НАШ анкер. Тож «таблиця мейтів» для цього листа — дві звірки, і обидві стоять питаннями, а не припущеннями: наконечник ↔ ціль Ø1.0 зі зсувом (п. 6) і пін ↔ футпринт плати (п. 7); «діапазон висоти» — вільна висота й робоче вікно ходу (п. 3).

---

## 3. Dispatch checklist (👤)

- [ ] 👤 **⛔ До «так» founder-а на цей текст не надсилати.**
- [ ] 👤 **Адресат:** Mill-Max (інженери застосувань) або дистриб'ютор — обирає founder; текст той самий, імені в ньому немає, перший абзац уже просить дистриб'ютора переслати.
- [ ] 👤 **Не чекати розкладки HW.9:** питання безкоштовне рівно доти, доки їде тією самою розмовою про P/N ([`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9) — окремим листом після вибору воно вже коштує.
- [ ] 👤 **Після відповіді:** креслення → `59` (`missing_datum`, нога HW.43) з перерахунком дотичного напруження — ⚠️ і з перерахунком ТИПУ напруження (див. «Найслабша ланка» п. 3); сплав і хід 0908 → Validation Gate [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md); 30 µin → HW.8.1 і ⊕ [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md); хід, вільна висота й сила → `52` (новий член `TOL_PZ`, `POGO_SPRING_FORCE_N`) і `55` (`F_POGO_N`) → HW.8.3 / HW.8.7; наконечник і мінімальна ціль → HW.9 + HW.34 + лист гальваніка п. 2; ресурс і Rc → HW.8.1 / 8.3 як апріорі стенду. Цін, строків і позначених вендором непублічних даних не комітити (§0 п. 7).

---

## 📤 Dispatch block (EN) — Mill-Max or distributor email

> **Репо-нота (у лист НЕ йде).** Несе дзеркала домів (§1): 2 однакові піни · ≈15 мкА … 0.5 мА при ≈0.5 В · Rc < 50 мОм · −40 … +85 °C · Au 0.76 / Ni 1.27 мкм (30 / 50 µin) · «-20-» = 20 µin · хід 1.40 мм (.055 ± .005 in) · вікно 50–70 % (0.70–0.98 мм) · сила ~98 г (0.96 Н) ⊥ 60 ± 20 г · BeCu C17200 per ASTM B194 · ціль Ø1.0 урівень, кільце Ø ≥ 4.0 · фланець Ø25 · зазор ≈0.3 мм · pH ≈5.75 · «порядку сотні» зʼєднань · ≤ ≈4.7 × 10⁸ циклів за 20 років · 100 000–1 000 000 циклів каталогу · пад 2.5 мм · 2 000 / 20 000 пінів. Питає те, чого канон не несе й не може нести без вендора (§2).
>
> **Немає свідомо:** наш вибір серії (жодної не замовляємо) · серія «0909» · корпус 1.27 мм «для вищого струму» (наш струм — мікроампери, опція без рушія) · «≥ 50 000 циклів» (каталожний клас, а не потреба) · ⛔ **прохання про іншу, «сильнішу» пружину** — інший код пружини може бути іншим сплавом, тобто лист мовчки перевідкрив би ратифіковану вісь HW.43 (сплав = S-N-вхід) · рекомендація покриття ЦІЛІ — маршрут площадки обирає гальванік (⚖️ 2026-09-22), а pogo-вендор не авторитет щодо титану · статична релаксація пружини під сталим стиском роками при +85 °C — кандидат-питання, але ні канон, ні трекер його не називають (рамка `59` — циклічна), тож у лист не вписано; рішення — founder-а · маскування піна під Parylene — питання коатера, воно вже в [`node_parylene_rfq`](node_parylene_rfq.md) п. 2 · пороги деградації Rc · S-N-якорі, рамки A/B `59` і наш вирок · дужка частот і межі (2)–(3) циклового бюджету · контур плати Ø15.57 · ціна BOM · полярність і EBFC-хімія · трекер-ID, канон-рефи, дати й гліфи.
>
> **Найслабша ланка листа.** **(1)** Головна мета листа — креслення пружини — залежить від того, чи віддасть каталожний виробник дані власної пружини. Відмова переводить нас на п. 1b, а там ми просимо допустиму амплітуду, **не маючи власної амплітуди**: вендорська декларація «до X мкм» стане порогом без виміру, з яким її порівнювати (HW.43 нога (1) під паузою крони). **(2)** Навіть повне креслення закриває лише ОДИН із двох відсутніх входів рамки B — амплітуда лишається, і переклад «рух стовбура → відносний рух крізь pogo» моделі в дереві не має. **(3)** Поза листом, але на тій самій нозі: S-N-якорі `59` (240 МПа / 10¹⁰, 400 МПа / 3.05 × 10⁶) — ультразвукові й на згин, тобто за **нормальним** напруженням, тоді як дріт гвинтової пружини працює на **кручення**; дотичне τ з креслення проти σ-якоря без перерахунку (фон Мізес чи торсійні S-N) порівнювати не можна — це робота `59`, не вендора, але без неї відповідь на п. 1a дасть число, зіставлене не з тим.

**⬇️ КОПІЮВАТИ ВІД ЦЬОГО РЯДКА.** Усе вище — репо-шар, у лист він НЕ йде.

**Subject line:** Technical enquiry — spring-loaded pins, series 0906 and 0908: spring drawing, 30 µin gold option, travel and height tolerances, life under small-amplitude motion

**To a distributor receiving this:** if you are not Mill-Max, please forward this message to the Mill-Max applications engineering team. Most of the questions below can only be answered by the manufacturer.

Dear colleagues,

**About us and the application.** We are an R&D project in Ukraine developing a sensor node for forest monitoring. A titanium anchor is installed in the trunk of a living tree and works as a small biofuel cell. A sealed capsule with the electronics sits on top of the anchor and takes its power from it through **two spring-loaded pins**. The pins are soldered to the underside of the capsule's lower circuit board and press axially onto two flat contacts on the anchor's top face. The connection is blind: the capsule is placed onto the anchor and locked with a quarter-turn bayonet, and nobody sees the pins touch down.

This is a technical enquiry and not yet an order. Answering commits neither side to anything, and inline answers in this email are fine.

**Base case and one alternative.** Your series 0906 and 0908 are both candidates, and we have not chosen between them; the choice will be made together with the board layout. The base case is **0906-1-15-20-75-14-11-0**, only because it is the one part in these series whose full datasheet we have read. The alternative is the equivalent part in the **0908** series, for which we have only the series page and a distributor listing. Please answer for the base case first, and for the 0908 wherever the answer differs.

**Our design basis**

- **Quantity:** two identical pins per node.
- **Electrical:** a low-level circuit, from about 15 µA at start-up up to 0.5 mA in normal operation, at around 0.5 V. Contact resistance must stay below **50 mΩ** per pin.
- **Temperature:** −40 to +85 °C.
- **Plating we specified:** hard gold, **0.76 µm (30 µin) over 1.27 µm (50 µin) nickel**.
- **Travel:** we design around a nominal travel of **1.40 mm (.055 in ± .005 in)**, as we read it from your datasheet. The gap is set so that the pins sit between **50 % and 70 % of travel** (0.70 to 0.98 mm compressed), never at either end.
- **Spring force:** our preliminary specification assumed about **98 g (0.96 N) per pin at full travel**. The datasheet we have gives **60 ± 20 g at mid-stroke** and no full-travel figure (see question 4).
- **Mating targets:** the centre pin lands on the end face of a **1.0 mm diameter titanium wire**, flush with the anchor's top face, which will be surrounded by a polymer insulating ring of at least 4.0 mm diameter. The outer pin lands on the flat top face of a titanium flange of 25 mm diameter; the radius and width of that contact zone are not fixed yet, because they depend on the pin we choose. Both contact spots will be plated with hard gold. The capsule seats in its socket with a radial clearance of about **0.3 mm**, so a tip can land off-centre by at least that much; our full lateral tolerance chain is not computed yet.
- **Environment:** the contacts are inside a capsule sealed with an O-ring and filled with air. We still design for humidity, and we cannot exclude condensate from the tree sap (mildly acidic, pH about 5.75) reaching the contact.
- **Motion:** the capsule is removed only for maintenance, by our estimate of the order of a hundred mating cycles over the service life. Between those, the pins stay compressed at one working point while the swaying trunk superimposes small cyclic motion on it. An upper bound on the number of those cycles is about **4.7 × 10⁸ over 20 years** (continuous sway at the highest sway frequency measured for this pine species). That figure bounds the number of cycles, not their size: we have not measured the amplitude at the pins yet, and we expect it to be small compared with the travel.

**1. Spring drawing: our main question**

To judge the fatigue of the spring under this small-amplitude motion, we have to convert a deflection into stress in the spring wire. For that we need mechanical data of the spring that we could not find in the datasheet.

- a. Could you send the mechanical drawing of the spring used in the base case, and in the 0908 equivalent: **wire diameter, mean coil diameter, number of active coils, free length, spring rate and preload**? Wire diameter and spring rate alone are not enough for us; we also need the coil geometry.
- b. If the drawing cannot be shared: what is the largest amplitude of cyclic deflection, superimposed on a static compression within 50 to 70 % of travel, that the spring withstands for about 4.7 × 10⁸ cycles? If you have one, what is the amplitude below which you consider its fatigue life unlimited?
- c. Please confirm the spring material for both series. For the base case we read beryllium copper C17200 per ASTM B194.

**2. Plating: is a 30 µin gold option available?**

- a. Which plating codes in 0906-1-15-20-75-14-11-0 apply to the plunger and which to the barrel, and what gold and nickel thicknesses do they stand for? We read "-20-" as 20 µin (about 0.51 µm) of gold; please correct us if that is wrong.
- b. Is **30 µin (0.76 µm) hard gold over 50 µin (1.27 µm) nickel** available on the plunger, the contacting part, for the base case and for the 0908 equivalent? What is its part number, and does it change the price, the minimum order or the lead time?
- c. If 30 µin is not available, what is the heaviest gold you offer on these parts?
- d. Please confirm that the gold on the plunger is hard gold.

**3. Travel, height and their tolerances**

We need these figures for our height tolerance stack-up.

- a. Please confirm the nominal travel and its tolerance (1.40 ± 0.13 mm) for the base case and for the 0908 equivalent.
- b. What is the uncompressed height of the plunger tip above the board after soldering, and its tolerance? Does soldering add its own variation, for example the part floating or tilting on the pad?

**4. Spring force**

- a. Please give the force against travel for both series: the preload, the force at mid-stroke, at 70 % of travel and at full travel, each with its tolerance.
- b. The "about 98 g at full travel" in our specification does not appear in the datasheet we have, which gives 60 ± 20 g at mid-stroke. Are both figures consistent for the same spring, or does one of them belong to a different part?

**5. Rated life and contact resistance in our conditions**

- a. We read a mechanical life of 100,000 to 1,000,000 cycles for the 0906 series. At what stroke, at what cycling rate and with what end-of-life criterion (a contact resistance limit, a loss of force) is that figure rated?
- b. The contact resistance figure of 50 mΩ: at what test current and by what method is it measured? Does it hold at our low levels, from microamps up to 0.5 mA at around 0.5 V, where the current is too small to break through surface films?
- c. Do you have contact resistance data after life testing, and after exposure to humidity?
- d. Do you have any data on contact resistance, wear or fretting, at the tip or inside the pin, for small-amplitude cyclic motion around a fixed compression, over a number of cycles of the order of 10⁸? If you have none, please say so; that is also a useful answer for us.
- e. Please confirm that the operating temperature range of these parts covers −40 to +85 °C.

**6. Tip style and target size**

- a. Which tip styles are available in these series, and what is the contact diameter of each?
- b. Which tip would you recommend for the centre target, a flat spot of 1.0 mm diameter, given a lateral offset of at least 0.3 mm? And for the outer target, a flat zone on a larger face?
- c. What minimum target size, as a diameter or as the width of a flat zone, do you recommend for each tip, with that lateral offset included?

**7. Mounting and PCB footprint**

- a. Which mounting styles exist for these series: surface mount, through-hole, or both? We have not fixed this yet.
- b. What PCB land pattern do you recommend for each? Would a round pad of 2.5 mm diameter suit the surface-mount version?

**8. Documents, samples and supply**

- a. The current datasheets and drawings for the base case and for the 0908 equivalent.
- b. A small sample quantity of each candidate, delivered to Ukraine directly or through a distributor you name, with price and lead time.
- c. An indicative price per pin and lead time at 2,000 and at 20,000 pins (1,000 and 10,000 nodes).
- d. A technical point of contact.

**Confidentiality.** The technical specification of our device is openly published, so no confidentiality agreement is needed to discuss it. If any data you send us, for example the spring drawing, must not be published, please mark it; we will then use it only internally and publish only our own conclusions.

Thank you in advance.

`[sender's signature and contact details — fill in before sending]`

**⬆️ КІНЕЦЬ ТЕКСТУ ЛИСТА.** Нижче знову репо-шар.

---

## 4. Cross-references

| Ресурс | Що бере |
|---|---|
| [`02_02 §2.1`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §2.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | вимоги до піна · спека (серія, хід, сила, сплав, покриття) · ⚖️ «першим креслення пружини» і його Ціна · Validation Gate |
| [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §1.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | ціль Ø1.0 у кільці Ø ≥ 4.0 · зазор сокета 0.3 мм · вимога «тверде золото» на площадках |
| [`02_02 §3.5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · `tools/in_silico/scripts/52_z_stack_tolerance.py` | вікно 50–70 % · ланцюг `TOL_PZ` без члена піна (§0 п. 5) |
| [`02_02 §5`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_02 §6`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | Rc після циклів і вологи — верифікувати · футпринт ø 2.5, SMD ⊥ TH |
| [`SUMMARY.md`](../ebfc/in_silico/SUMMARY.md) §HW.43 · `tools/in_silico/cache/mechanical/contact_endurance_check.json` | стеля циклів 4.67 × 10⁸ і її межі · каталожний ресурс · `missing_datum` пружини |
| [`01_01 §2`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) · [`01_02 §2.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | задум «хід компенсує мікрорухи» і його межа · канон-headline циклового бюджету |
| [`anchor_pad_plating_rfq`](anchor_pad_plating_rfq.md) · [`node_parylene_rfq`](node_parylene_rfq.md) | зустрічне питання про ширину кільцевої зони · маскування піна під покриттям |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) HW.9 · HW.43 · HW.8 · HW.34 | дім стану · споживач креслення · 8.1/8.3/8.6/8.7 · геометрія площини площадки |
| [`rfq_registry`](rfq_registry.md) | procurement-індекс (рядок «Капсула електроніка») |
