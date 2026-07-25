# R4 — Biodiversity-credit ринки: методології, TNFD, stacking, acoustic-MRV

> **Що це:** знімок веб-дослідження, зібраний агентом під час §07 legal/business-кампанії. Це **вхідні дані** для артефактів у [`legal/`](../legal/) та [`business/`](../business/), а не самостійне джерело істини.
> **Concern-шар — НЕ канон.** Правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас.
> **⚠️ НЕ верифіковано пофактно.** Кожне твердження потребує перевірки першоджерела перед використанням; це не юридична/податкова/фінансова порада.


**Дата дослідження:** 2026-07-24 (web, PUBLIC-джерела, orientation-глибина). **Контекст:** SilkenNet acoustic biodiversity-вимір (TinyML 5-клас fauna/silence/wind/chainsaw → `biodiversity_score`) ПОВЕРХ carbon D-MRV.

**Легенда впевненості:** 🟢 висока (peer-review / офіційний реєстр-документ, ≥2 незалежних джерела) · 🟡 середня (одне якісне джерело / trade-press без full-text) · 🔴 низька (paywall не проліз / суперечливі цифри / hype-заявка).

---

## TL;DR (bottom-line наперед)

**Biodiversity credit — це carbon market ~2008-2010: методології щойно народились, перші кредити щойно видані, обсяг ринку невідомий навіть аналітикам (розкид оцінок 2025 року — $0.09 млрд до $7.1 млрд, 80x!).** Це саме по собі є найчеснішим індикатором незрілості: немає навіть консенсусу, СКІЛЬКИ ринку вже існує, не кажучи про його якість.

**Жоден великий реєстр не приймає acoustic index (ACI/BI/NDSI тощо) як ФОРМУЛУ квантифікації кредиту.** Найближче до "прийнято" — Cercarbono/Savimbo ISBM, де звукозапис = один з трьох рівноправних non-invasive каналів доказу присутності *indicator species* (поруч з фото/відео), НЕ континуальний acoustic-index. Це живий, реально видає кредити реєстр (перші кредити вересень 2024) — найреалістичніший match для acoustic-MRV сьогодні, але вимагає species-level ідентифікації, не 5-класового presence/absence.

**Для SilkenNet це — far-horizon друга revenue-лінія, не готовий SKU 2026 року.** Найближча чесна позиція: acoustic-шар як *supplementary evidence / co-benefit наратив* поверх carbon-кредиту (за зразком NatureMetrics eDNA на forest-carbon проєктах або Delgado et al. 2026 Costa-Rica PES-verification), а не окремий продаваний "biodiversity credit" — доки ринок сам не стандартизує квантифікацію (дивитись на COP17, Єреван, жовтень 2026, як на можливий перелом).

---

## 1. Матриця методологій biodiversity-credit

| Реєстр / методологія | Одиниця виміру | MRV-метод (базовий) | Верифікація | Acoustic/eDNA прийняття? | Статус 2025-26 | Впевненість |
|---|---|---|---|---|---|---|
| **Wallacea Trust** (UK non-profit, biodiversity credit methodology v3, жовт. 2023) | 1% uplift біорізноманіття/га = медіанна % зміна в "кошику" з ≥5 метрик (1 структурна + 4 неструктурні) | Метод-агностична: canopy cover, kelp occupancy, reef rugosity (структурні); indicator species relative abundance × conservation value (неструктурні) | Незалежний **academic peer review** (Biodiversity Futures Initiative, мережа університетів) | Не прописано explicitly в методології; framework method-agnostic → acoustic-похідна метрика (напр. bird-community index) теоретично МОЖЕ бути одним з 5 кошика-метрик, якщо пройде peer review. **Живих прикладів не знайдено.** | Operation Wallacea + Wallacea Trust + Biodiversity Credit Company, working group з 2021; методологія "ranked top" у незалежному аналізі | 🟢 методологія; 🔴 acoustic-приклад (не знайдено) |
| **Verra SD VISta Nature Framework** (нова, v1.0) | Nature Credit = 1% net biodiversity outcome на "quality hectare" (Qha) | Загальний глобальний framework + локалізовані модулі за біомом/екорегіоном (в розробці) | Verra third-party verification (аналог carbon-VCS) | Конкретні approved indicators/monitoring methods **не опубліковані публічно** в доступних джерелах — документ v1.0 + worked examples існують, але деталі MRV-техніки (remote sensing/acoustic/eDNA) не вдалось витягнути з відкритих сторінок | **Active з 29.10.2024**; pilot-проєкти, що відповідають v1.0, могли подавати документи з 1 квітня 2025 і генерувати credits | 🟢 launch-факти; 🔴 деталі acoustic-acceptance (недоступні) |
| **Cercarbono — Savimbo ISBM** (Indicator Species Biodiversity Methodology v1.2, Колумбія) | Кредит = звітування присутності indicator species (56 видів, вкл. endangered/vulnerable) у визначеній зоні кожні 2 місяці | **Non-invasive: відео, фото, АБО звукозапис** — рівноправні докази присутності виду; Biodiversity Performance Status (BPS) + Nature Integrity Score (NIS) як два ключові індекси | Cercarbono сертифікація (перший затверджений reg. в світі, вересень 2024) | ✅ **Explicitly приймає звукозапис** — але як canonical species-presence evidence, НЕ як континуальний acoustic-index. Перші CBCP-сертифіковані кредити вже видані (Savimbo Biodiversity Putumayo, Колумбійська Амазонія, 3184.5 га) | **Живий, видає кредити.** Явно позначено: "can never be used to provide offsets of any kind" (voluntary-only, не-offset) | 🟢 |
| **Plan Vivo — PV Nature** | Plan Vivo Biodiversity Certificates (PVBCs); multimetric % change unit, 5 "pillars" біорізноманіття | Стандартизовані ecosystem + species-based індекси (аналог Wallacea multimetric підходу) | Plan Vivo Foundation verification | Не знайдено explicit згадки acoustic/eDNA в опублікованих матеріалах методології | ~10 проєктів на розгляді (січ. 2025), перші кредити очікувались "наступного року" (тобто 2026); пілот Wild Elephant Forest (Зімбабве) | 🟡 |
| **UK Biodiversity Net Gain (Statutory Metric 4.0)** | % Biodiversity Units (habitat area/hedgerow/river modules, distinctiveness × condition × strategic significance) | **Habitat-based** — площа/тип/стан оселища, НЕ прямий species-count чи acoustic-signal | Local Planning Authority + Natural England statutory framework; HMMP (Habitat Management & Monitoring Plan) на 30 років | ❌ **Статутний метрик НЕ включає acoustic monitoring.** Дослідники прямо критикують: "habitat-based statutory biodiversity metric has been shown to be an ineffective proxy for wider biodiversity outcomes" → рекомендують доповнювати species-based моніторингом. У ПРАКТИЦІ приватні консультанти (Chirrup.ai, Oakbank, Naturesound, Baker Consultants) продають bioacoustic-моніторинг ЯК ДОПОВНЕННЯ для BNG-звітності/ESG, але це НЕ статутний вхід у формулу Units | Обов'язковий з лют. 2024 (більшість забудов); Statutory Metric User Guide опубл. лип. 2025 | 🟢 |
| **Australia Nature Repair Market** (Nature Repair Act 2023, Clean Energy Regulator) | Tradeable **Biodiversity Certificate** (1 на проєкт, за методологією) | Перший затверджений метод: "Replanting Native Forest and Woodland Ecosystems" (реставрація) | Clean Energy Regulator (той самий орган, що carbon ACCUs) | Не знайдено explicit acoustic-положень у першому методі; ринок щойно запущений, методи ще розробляються (DCCEEW "Methods for the Nature Repair Market") | **Офіційно запущено березень 2025** — перший легалізований національний biodiversity-ринок у світі. Листопад 2025: EPBC Act reform дозволяє certificates покривати offset-зобов'язання (набуде чинності 1 лип. 2026) | 🟢 |
| **Wilderlands** (Австралія, приватний) | "Biological Diversity Unit" = 1 м² permanent protection + 20 років active management | Conservation covenant + expert ecologist reports | Незалежна реєстрація, geotagging | Не знайдено acoustic-специфіки | 4 проєкти (Coorong Lakes, Crowes Lookout, Alleena, Budgerum) | 🟡 |

**Ключовий структурний висновок матриці:** з 7 методологій жодна не будує кредит НАВКОЛО acoustic-index. Найближче — Cercarbono/Savimbo (звук як один з трьох рівноправних доказових каналів присутності виду). Wallacea Trust і Verra — method-agnostic баскети, теоретично відкриті, але без живих acoustic-прецедентів. UK BNG — офіційно habitat-only, acoustic живе лише в приватному consulting-шарі НАВКОЛО реєстру, не в самому реєстрі.

---

## 2. Nature/TNFD-ринок: стан 2025-26

### Обсяг і зростання — розкид як сигнал незрілості

Оцінки розміру ринку 2025 року з різних аналітичних звітів (Grand View Research, Meticulous Research, Fact.MR, InsightAce, MarketIntelo): **$0.09 млрд – $2.8 млрд – $5.7 млрд – $7.1 млрд** залежно від методології й визначення "biodiversity credit" (частина рахує весь "natural capital credit" ринок, частина — вузько voluntary biodiversity credits). Прогнози на 2032-2034: $12.4 млрд – $38 млрд – $48.7 млрд, CAGR 23–49%. 🔴 **Ці цифри — типовий boilerplate market-research звіт (paywalled повні звіти, безкоштовні прес-релізи), інтерпретувати як "порядок величини", НЕ як точні дані.**

Якісніший сигнал — галузевий звіт **Terrasos/Pollination "State of Voluntary Biodiversity Credit Markets"**: voluntary credits = >72% ринку 2025 р.; **>2.5 млн га під управлінням; ~15 млн кредитів видано або заплановано**. Ключові гравці: South Pole, Verra, Terrasos, Biodiversity Credit Alliance, Plan Vivo, Climate Impact Partners, Wilderlands, NatureMetrics, EcoRegistry. 🟡

### Ціни

Діапазон екстремально широкий: **$5–$120/одиницю** типово; більшість продажів ≤$25; окремі транзакції зафіксовані від $7 до $41 000/одиницю за 100-річний період консервації (найвища верхня межа — $500k). Premium (indigenous co-benefit + verified permanence + ecosystem distinctiveness) зростав **+30-45% у цінах 2022→2025** — сигнал, що покупці вже почали розрізняти якість, попри незрілість. 🟡

### Покупці

Мультинаціонали, SME, фінустанови — головно заради branding/marketing + risk mitigation, ще не regulatory-compliance (окрім UK BNG і тепер Австралії, де це частково статутна вимога). 🟡

### TNFD — framework, не ринок

TNFD (Taskforce on Nature-related Financial Disclosures) — це ДИСКЛОЗЬОР-стандарт (як carbon reporting), НЕ crediting-механізм; напряму не "приймає" acoustic MRV, а радше створює попит-side тиск (компанії мусять звітувати nature-related risk → шукають дані, зокрема biodiversity credits як proxy-докази дії).

- **733+ організацій у 56 країнах** взяли зобов'язання звітувати за TNFD станом на листопад 2025 (капіталізація $6.5 трлн; фінустанови під управлінням $17.7 трлн).
- LEAP-підхід (Locate-Evaluate-Assess-Prepare) — метод-агностичний; **не знайдено explicit TNFD-рекомендації acoustic monitoring** як стандартного інструменту в LEAP — TNFD оперує на вищому рівні агрегації (supply-chain geospatial risk), не на рівні site-specific MRV-техніки.
- Листопад 2025: TNFD підписав MoU з IFRS Foundation — консолідується під ISSB; завершує власну технічну роботу до Q3 2026, потім **призупиняє розробку нових гайдів**, передає естафету ISSB. ISSB планує Exposure Draft до COP17 (жовтень 2026). 🟢

### CBD COP16/COP17 і IAPB

- Kunming-Montreal GBF (2022): ціль **$200 млрд/рік** до 2030 на біорізноманіття з усіх джерел; поточний потік — менше половини цього. Target 19 (мобілізація ресурсів) — офіційний якір, на який Verra Nature Credits явно посилаються.
- **IAPB (International Advisory Panel on Biodiversity Credits)** — заснований Францією+Великобританією 2023, framework запущено на COP16 (Калі, жовтень 2024), 6 критеріїв integrity.
- **COP17 (Єреван, 19-30 жовтня 2026)** = midpoint-оцінка GBF; biodiversity credits прогнозовано перейдуть "from specialized concept to central pillar" переговорів — вартий моніторингу переломний момент. 🟢

### Критика / ризики — чесний burden of proof

- **Royal Society Proceedings B, серпень 2025** (Kim, Dellecker, Field, Stephenson, Schrodt): оцінили **11 великих постачальників biodiversity credits проти 6 IAPB-критеріїв → середній результат 2/3**, найслабше місце — **незалежність third-party verification і transparency risk disclosure**. Тобто навіть існуюча пропозиція має структурні integrity-діри. 🟢
- **Wunder et al., Business Strategy and the Environment, 2025** (аналіз 34 пілотних проєктів): "quality credits will be more expensive than those cutting integrity corners, which may dampen the expected biodiversity credit boom" — прямий чесний прогноз, що якість і обсяг ринку — в конфлікті.
- Порівняння з carbon market: carbon у 2025 демонструє "maturing around quality" (buyers селективні, ціни відображають integrity-рейтинги, напр. ARR BBB+ ≈ $26/credit); biodiversity market **не має навіть цього** — "owing to the low level of maturity... limited publicly available information on how to measure outcomes... in a way that ensures high integrity." 🟢
- Ризики фунгібельності: на відміну від tCO2e (універсальна одиниця), biodiversity — **не commensurable** за конструкцією (Royal Society папір: "carbon credits utilize a standardized unit... functions as commensurable... [biodiversity] cannot"). Це не тимчасова вада, а структурна відмінність предмету виміру.
- Загальний тон незалежних оглядів (Eco-Business, WRI, OECD): "biodiversity credits doomed to repeat voluntary carbon market's flaws?" — стаття прямо ставить питання; відповідь індустрії — вчитися на carbon market помилках (verification independence, additionality, benefit-sharing), а не повторювати їх. 🟡

**Bottom-line секції 2:** ринок реальний у сенсі "гроші вже течуть і кредити вже видаються" (не чистий hype), але **структурно ідентичний ранньому voluntary carbon market**: без консенсусної одиниці виміру, без консенсусного розміру ринку, з задокументованою integrity-слабкістю навіть у топ-постачальників. TNFD — попит-side тиск, який підживлює інтерес, але сам не валідує жоден MRV-метод.

---

## 3. Stacking: чи можна carbon + biodiversity на одній ділянці

### Базові визначення (Ecosystem Marketplace, "Beetles in a Pay Stack")

- **Bundling** — кілька ecosystem services з однієї ділянки продаються ОДНИМ кредитом одному покупцю (implicit — не квантифіковані окремо; explicit — квантифіковані окремо, але однією транзакцією).
- **Stacking** — ті самі overlapping services вимірюються й пакуються в РІЗНІ типи кредитів, що продаються ОКРЕМО різним покупцям. Вимагає "ecosystem unbundling" — представлення екосистеми як дискретних, подільних функцій.
- **Double-counting/double-dipping** (заборонено всюди) — коли ТОЙ САМИЙ environmental outcome зараховується більше одного разу.

### Позиції по реєстрах

| Реєстр/юрисдикція | Позиція щодо stacking | Деталі |
|---|---|---|
| **Plan Vivo** | ✅ Explicitly підтримує | Офіційна position statement: "Plan Vivo supports the principle of stacking... to unlock greater and more durable finance for nature." Умови: (1) окрема additionality для кожного типу кредиту, (2) окремий продаж/retirement з різними claims, (3) окремі методології квантифікації, (4) revenue-sharing з місцевими громадами. **Але наразі дозволено лише в межах власного стандарту** (PV Nature + PV Climate carbon code) — interoperability з іншими стандартами "actively evaluating", ще не жива. |
| **Biodiversity Credit Alliance (загальна позиція індустрії)** | ✅ "Yes, if additionality criteria are met, as set out by the emerging standards" | Форвардна guidance від WEF + McKinsey щодо того, ЯК stacked credits підтримують claims — ще в розробці (не знайдено фінального документа зі stacking-специфікою; є "High-Level Principles" 2025 і "Demand Analysis" звіти, але explicit stacking-протокол не підтверджений публічно). |
| **US (Clean Water Act wetland/species banks)** | Обмежено | Joint banks можуть продавати co-located wetland/stream + species credits, але **кредити не можна "unbundle" і продавати окремо для різних проєктів**; water quality trading використовує proportional accounting (продаж одного типу зменшує доступність іншого зі стеку). **Справжніх stacking-прикладів у встановлених US biodiversity-ринках НЕ знайдено.** |
| **UK** | ✅ Частково дозволено | England BNG guidance explicitly дозволяє stacking між BNG і nutrient markets; British Standards Institute розробляє "flex standard", що "залишає двері відкритими" для різних stacking-підходів. |
| **Australia (національно)** | ❌ Заборонено на нацрівні, ✅ дозволено окремими штатами | Національна Biodiversity Offset Policy **забороняє** stacking carbon+biodiversity; кілька штатів мають власні політики, що ФОРМАЛЬНО дозволяють це (напр. Cassowary Credits endorsed by Clean Energy Regulator для stacking на carbon). Суперечність нац./штатного рівня — джерело плутанини. |

### Ризики (консенсус індустрії)

1. Double-counting/double-dipping — головний ризик №1 всюди.
2. Екологічна складність — взаємопов'язані функції екосистеми не завжди можна надійно роз'єднати без непередбачених наслідків ("ecosystem unbundling has its limits").
3. Невизначеність additionality при множинних claims з однієї дії.
4. Прозорість — розмита guidance створює політичну двозначність щодо "коли окремий продаж доречний".
5. Транзакційні витрати — множинний credit-accounting = складність + вартість.
6. Регуляторна неузгодженість між юрисдикціями (яскраво видно на прикладі Австралії нац./штат).

**Практичних живих прикладів carbon+biodiversity stacking (крім Plan Vivo-внутрішнього і Австралія-Cassowary-кейсу) НЕ знайдено** — це переважно "дозволено на папері", ринок ще не наповнив цю нішу реальними транзакціями. 🟡

---

## 4. Acoustic-специфіка: наука, гравці, MRV-легітимність

### Наукова база acoustic-індексів — зріла, але все ще активно ревізується

- **Farina, Oikos 2025** — "The acoustic complexity index (ACI): theoretical foundations, applied perspectives and semantics" — свіжа (2025!) стаття РЕВІЗУЄ теоретичні основи індексу, введеного ще 2011 р. Сам факт, що фундаментальна теорія перевидається 14 років по тому, каже: **консенсус досі не "застиг"**, поле активно самокоригується. 🟢
- **Kemp et al., Methods in Ecology and Evolution 2025** — "Impact of acoustic index parameters on soundscape comparisons": показали, що вибір FFT-параметрів (NFFT) **змінює напрямок тренду** результату ACI (нелінійна залежність від call rate реверсується при різних NFFT). Це прямий удар по commensurability/фунгібельності — без стандартизації параметрів, acoustic-score з різних проєктів **непорівнювані**, а порівнюваність — саме те, що потрібно для кредитної одиниці. 🟢
- Загальний висновок галузевих оглядів: ACI "demonstrates reliability across diverse environments" ОДНОЧАСНО з "inconsistencies in performance across different biomes" — тобто робочий інструмент з відомими межами, не "решене питання". 🟡

### Ключове порівняльне дослідження: acoustic vs eDNA vs traditional для biocredits

**Bell & Malerba, Biodiversity and Conservation, 2025** — "Biodiversity monitoring for biocredits: a case study comparing acoustic, eDNA, and traditional methods" (temperate agricultural landscape, південно-східна Австралія):

- Порівняли: aural/visual survey людьми, camera trapping, eDNA sampling, passive acoustic monitoring (PAM) з автоматичною детекцією видів.
- **PAM (обмежено вокалізуючими таксонами з готовими детекційними моделями — птахи, амфібії) дав ~70x більше детекцій, ніж інші методи, і виявив на 10+ видів більше на локацію в середньому, при найнижчій вартості на вид за 5+ повторних кампаній.**
- **Критичне обмеження, явно назване авторами: PAM працює ЛИШЕ для вокалізуючих таксонів** — не покриває рослини, більшість безхребетних, немі ссавці, бентос тощо. Тобто **acoustic-only biodiversity_score структурно неповний** — не заміна повного біорізноманіття, а proxy для конкретної піднавіски (переважно птахо-амфібійна вокальна спільнота). 🟢 (сильна пряма відповідність до задачі — це найточніша знайдена наукова робота).

**Ford et al., Journal of Applied Ecology, 2024** — "A technological biodiversity monitoring toolkit for biocredits" — існує (paywalled, 402 не вдалось прочитати повний текст), сама назва підтверджує: наукова спільнота вже explicitly фреймує acoustic+інші технології САМЕ як "toolkit for biocredits" ще 2024 р. — тобто питання "чи технологія готова" активно досліджується, але фінальний текст недоступний у цьому дослідженні (публічний web). 🔴 (назва/факт існування 🟢, зміст 🔴).

### Delgado et al. — базовий контекст задачі, підтверджена цитата

**Delgado G. et al., Global Change Biology, 2026** — "Large-Scale Forest Restoration Accompanied by Biodiversity Recovery in Costa Rica's Redistributive Payment for Ecosystem Service Program" (DOI: 10.1111/gcb.70730). 119 сайтів, Nicoya Peninsula, Коста-Рика; 16 658 годин аудіо; порівняння PES-регенерованих лісів, монокультурних плантацій, деградованих пасовищ і mature forest reference.

- **Ключовий аргумент (саме той, що цитує задача):** супутникові дані показують відновлення canopy cover, але **не показують, чи функціонує ліс як middle**. Soundscape-профіль натомість ловить *функцію* — регенеровані ліси звучали суттєво ближче до mature forest, ніж до деградованих пасовищ.
- **Явного зв'язку з видачею biodiversity-кредитів чи PES-верифікацією в статті не описано** — це наукова валідація гіпотези "sound = ecosystem function proxy", НЕ (ще) операціоналізований MRV-протокол для кредитного реєстру. 🟢 факт дослідження; 🔴 (немає) прямого MRV/credit-застосування.
- Бонус-знахідка: паралельна незалежна робота (Dr. Sean Yap, National University of Singapore, Center for Nature-based Climate Solutions) також досліджує AI-bioacoustic моніторинг тропічних лісів (2026) — сигнал, що напрямок "acoustic = forest function proxy" розробляється кількома незалежними групами одночасно, не одинична робота. 🟡

### Хто вже комерціалізує acoustic biodiversity monitoring

| Гравець | Що робить | Зв'язок з credit-реєстрами |
|---|---|---|
| **Rainforest Connection (RFCx) / ARBIMON** | AI bioacoustic-платформа; детекція 7025+ видів, 310+ threatened; **історично founding use-case = anti-poaching/illegal-logging real-time alert**, не credit-issuance; LUCA-платформа інтегрує acoustic + eDNA | Не знайдено прямого партнерства з конкретним biodiversity-credit реєстром для issuance (immanent monitoring/conservation tool, не credit-supply chain) |
| **NatureMetrics** | eDNA (не acoustic, але прямий "сусід" по MRV-технології) + Earth Observation; $25M Series B (січ. 2025, лідер Just Climate) | Названий "key player" у Terrasos/Pollination огляді biodiversity credit market; партнерство з Arva (agri) |
| **Chirrup.ai** | Bioacoustic пристрій + AI-звіт для землевласників/фермерів; "listens to birdsong... AI identifies each species" | Явно позиціонує під **BNG-звітність, ESG-compliance** — АЛЕ це НЕ статутний BNG-вхід (BNG Metric 4.0 habitat-based), а supplementary evidence layer; жодної згадки Verra/Gold Standard/формального credit-реєстру |
| **Oakbank, Naturesound, Baker Consultants** (UK) | Ecoacoustic consultancy — "continuous, verifiable record" для biodiversity baseline/BNG/EIA | Той самий патерн: продають acoustic-evidence В екосистему навколо BNG (landowners, planning consultants), не самі є реєстром і не є статутним входом |
| **Earthstream** (стартап, 2024) | Low-cost scalable acoustic-only biodiversity reporting (свідомо БЕЗ imaging) | Рання стадія, недостатньо публічних даних для оцінки |

**Структурний патерн, що повторюється у всіх UK-прикладах:** bioacoustic-компанії продають "evidence layer" НАВКОЛО BNG-екосистеми (землевласникам, консультантам, corporates), а не ВСЕРЕДИНУ статутної формули. Це узгоджується з висновком матриці §1 — BNG Metric сам залишається habitat-based; acoustic живе в приватному шарі compliance-підтримки.

### Науково-market verdict для acoustic-MRV

1. **Наука не "не готова"** — ACI/PAM-підхід має десятиліття peer-review, і 2025 рік приніс і ревізію теорії (Farina), і пряме емпіричне порівняння в контексті biocredits (Bell & Malerba) з дуже сильним результатом на користь PAM (70x детекцій, найнижча вартість/вид).
2. **Але наука ≠ операціоналізований MRV-стандарт.** Жоден major реєстр не кодифікував acoustic-index → credit-quantity формулу. Найближче — Cercarbono/Savimbo, де звук = один із трьох рівноправних raw-evidence каналів для species presence (категоричне так/ні), не континуальний індекс.
3. **Ключове обмеження навіть у найкращому науковому результаті:** PAM покриває лише вокалізуючі таксони (Bell & Malerba — прямо звучить як попередження проти over-claiming "biodiversity_score" з чисто акустичних даних).
4. **Комерційний шар вже існує і монетизується** (Chirrup.ai, Oakbank, Naturesound, Rainforest Connection) — але як evidence-as-a-service НАВКОЛО існуючих кредитних/ESG механізмів, не як самостійний "acoustic credit" SKU.

---

## Bottom-line (розгорнутий)

**Це реальний другий revenue-стрім чи far-horizon?** → **Far-horizon зі значним "але".**

- **"Але" #1:** Ринок не гіпотетичний — перші кредити вже видаються (Cercarbono/Savimbo, вересень 2024; Verra Nature Framework з квітня 2025; Australia Nature Repair Market з березня 2025; Plan Vivo очікує 2026), венчурні гроші вже течуть у суміжні MRV-технології (NatureMetrics $25M), і TNFD створює структурний попит-side тиск на 733+ організацій.
- **"Але" #2 (застереження):** Royal Society 2025 знайшли, що навіть 11 НАЙБІЛЬШИХ існуючих постачальників в середньому набирають 2/3 за integrity-критеріями IAPB, найслабше саме на **незалежній верифікації** — тобто "будувати MRV-протокол зараз" означає будувати на рухомому піску стандартів.
- **Найреалістичніший вхід для SilkenNet сьогодні:** не "продавати biodiversity credit" як окремий SKU, а (a) позиціонувати acoustic-шар як **co-benefit evidence поверх carbon-наративу** (за зразком Delgado-типу "sound proves forest function, satellite тільки покриття" — це ПРЯМО підсилює довіру до Proof-of-Growth carbon-клейму), і (b) тримати на радарі **Cercarbono/Savimbo ISBM** як єдиний живий реєстр, що вже explicitly приймає звукозапис як доказ — але тільки якщо/коли TinyML-класифікатор розшириться за межі 5-класового fauna/silence/wind/chainsaw до species-level (indicator-species) ідентифікації, бо ISBM вимагає видо-специфічну присутність, не родову "є фауна чи нема".
- **Вартий моніторингу перелом:** COP17 (Єреван, жовтень 2026) — заявлений як момент, коли biodiversity credits можуть перейти "from specialized concept to central pillar" політичних переговорів; це природна контрольна точка для повторної оцінки цього дослідження за ~3 місяці.

**Який реєстр приймає acoustic зараз, підсумково:** **Cercarbono/Savimbo ISBM** — єдиний, з явним і вже впровадженим (не проєктним) прийняттям звукозапису як доказового каналу; все інше або method-agnostic-в-теорії (Wallacea, Verra — без живих acoustic-прецедентів), або explicitly habitat-based і закрите для acoustic на статутному рівні (UK BNG).

---

## Джерела (репрезентативна вибірка, не повний список — усі URL перевірені живими web-запитами 2026-07-24)

- [Wallacea Trust biodiversity credit methodology v3 (PDF)](https://wallaceatrust.org/wp-content/uploads/2022/12/Biodiversity-credit-methodology-V3.pdf) · [Replanet пояснення методології](https://www.replanet.org.uk/article/how-does-the-wallacea-trust-methodology-calculate-biodiversity-uplift/) · [Carbon Pulse — peer review update](https://carbon-pulse.com/233151/)
- [Verra Launches Nature Framework](https://verra.org/verra-launches-nature-framework/) · [Verra Nature Framework сторінка методології](https://verra.org/methodologies/nature-framework/)
- [Plan Vivo launch biodiversity Standard](https://www.planvivo.org/news-insights/plan-vivo-launch-biodiversity-standard) · [Plan Vivo Position Statement on Stacking](https://www.planvivo.org/news-insights/position-statement-on-stacking-biodiversity-and-carbon-credits)
- [UK BNG Statutory Metric 4.0 explainer](https://acp-consultants.com/biodiversity-net-gain/statutory-biodiversity-metric/) · [Oxford Nature Recovery — BNG promises/pitfalls PDF](https://naturerecovery.ox.ac.uk/wp-content/uploads/2025/12/BNG-explainer-final-1.pdf)
- [Australia Nature Repair Market — DCCEEW](https://www.dcceew.gov.au/environment/environmental-markets/nature-repair-market) · [Clean Energy Regulator scheme page](https://cer.gov.au/schemes/nature-repair-market-scheme) · [Clayton Utz — offsets under scrutiny, 2026-05](https://www.claytonutz.com/insights/2026/may/biodiversity-offsets-under-scrutiny-in-nature-repair-market-consultation)
- [Mongabay — Cercarbono перша методологія затверджена](https://news.mongabay.com/short-article/2024/09/colombia-voluntary-biodiversity-credit-methodology-is-first-to-be-approved/) · [Savimbo ISBM документація](https://isbm.savimbo.com/) · [Cercarbono biodiversity credits issued](https://cercarbono.com/updates/cercarbono-biodiversity-credits/)
- [Grand View Research — biodiversity credit market size](https://www.grandviewresearch.com/industry-analysis/biodiversity-credit-market-report) · [Terrasos — State of Voluntary Biodiversity Credit Markets](https://www.terrasos.co/en/the-state-of-the-voluntary-biodiversity-credit-markets-key-trends-and-insights/) · [Carbon Pulse — Q4 2025 price report](https://carbon-pulse.com/472517/)
- [TNFD офіційний сайт](https://tnfd.global/) · [IFRS — ISSB welcomes TNFD support, 2025-11](https://www.ifrs.org/news-and-events/news/2025/11/issb-welcomes-tnfd-support-nature-related-disclosure/)
- [IAPB офіційний сайт](https://www.iapbiocredits.org/) · [Royal Society Proceedings B — Towards high-integrity biodiversity credits, 2025-08](https://royalsocietypublishing.org/rspb/article/292/2053/20250990/234518/Towards-high-integrity-biodiversity-credits) · [PMC full text](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12364579/) · [phys.org прес-реліз](https://phys.org/news/2025-08-biodiversity-credits-transparency-impact-credibility.html)
- [Wunder et al. 2025, Business Strategy and the Environment (Bangor University сторінка)](https://research.bangor.ac.uk/en/publications/biodiversity-credits-an-overview-of-the-current-state-future-oppo/)
- [Ecosystem Marketplace — Beetles in a Pay Stack (stacking vs bundling)](https://www.ecosystemmarketplace.com/articles/beetles-in-a-pay-stack-stacking-and-bundling-in-biodiversity-credit-markets/) · [Biodiversity Credit Alliance FAQ — stacking на одній ділянці](https://www.biodiversitycreditalliance.org/faq/can-a-carbon-credit-and-a-biodiversity-credit-be-issued-from-the-same-parcel-of-land/)
- [Farina 2025, Oikos — ACI theoretical foundations](https://nsojournals.onlinelibrary.wiley.com/doi/10.1111/oik.10760?af=R) · [Kemp et al. 2025, Methods in Ecology and Evolution — acoustic index parameters](https://besjournals.onlinelibrary.wiley.com/doi/10.1111/2041-210X.70007)
- [Bell & Malerba 2025, Biodiversity and Conservation — acoustic/eDNA/traditional comparison](https://link.springer.com/article/10.1007/s10531-025-03083-0) · [Ford et al. 2024, Journal of Applied Ecology — technological toolkit for biocredits](https://besjournals.onlinelibrary.wiley.com/doi/full/10.1111/1365-2664.14725)
- [Delgado et al. 2026, Global Change Biology (DOI 10.1111/gcb.70730)](https://onlinelibrary.wiley.com/doi/10.1111/gcb.70730) · [Mongabay короткий огляд](https://news.mongabay.com/short-article/2026/05/can-listening-to-a-forest-reveal-whether-it-is-ecologically-healthy/) · [Phys.org — Costa Rica bioacoustics, 2026-06](https://phys.org/news/2026-06-costa-rica-paid-landowners-forests.html)
- [Rainforest Connection / RFCx ecoacoustics](https://rfcx.org/ecoacoustics) · [Chirrup.ai](https://chirrup.ai/) · [Oakbank bioacoustics](https://www.oakbankgc.co.uk/natural-capital-advice-baselining/biodiversity-action-planning-bioacoustics-uk) · [NatureMetrics $25M Series B](https://www.justclimate.com/news/news/naturemetrics-secures-25m-series-b-funding-to-accelerate-biodiversity-monitoring-technology-solution/)
- [CBD COP17 Yerevan 2026 контекст](https://environment.ec.europa.eu/news/cbd-cop17-addressing-biodiversity-financing-gap-2026-05-22_en)
