# BIZ.21 — E&O / D&O / Liability Coverage-Requirements Specification

> **Що це:** специфікація вимог до страхового покриття SilkenNet — робочий вхід для intake-дзвінка з ліцензованим страховим брокером перед першим B2B-підписанням.
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — BIZ.21.

---

> ## ⚠️ СТАТУС ДОКУМЕНТА: COVERAGE-SPEC — НЕ поліс, НЕ страхова/юридична порада
>
> Це **специфікація вимог до покриття** («що поліс має покривати»), призначена живити ліцензованого страхового брокера при першому intake-дзвінку. Це **НЕ** сам поліс і не заміна консультації брокера/юриста. Усі цифри (ліміти/вартість) — з [`R6_insurance_dpa.md`](../research/R6_insurance_dpa.md), 🟡 **MEDIUM confidence** (агреговані з декількох broker/insurtech-блогів, жодне не є первинним прайс-листом carrier'а; реальна ціна для UA-домицільованої компанії з forest-hardware-профілем ризику може суттєво відрізнятись). Перед будь-яким реальним придбанням — консультація з ліцензованим брокером.
>
> **Хто купує:** 👤 страхувальник = **operational-vehicle** — наявна UA-компанія (Дія.City-резидент, співзасновником якої є founder), що виступає named counterparty за B2B-контрактами. Отже юрисдикція страхувальника = **Україна**, і це вже не відкрите питання; відкритим лишається **доступ до carrier'ів** за такої домициляції (§5.3). Цей документ = 🤖-половина BIZ.21 ([`00_07`](../../00_07_Action_Plan_Tracker.md) — coverage-spec); 👤-половина = брокер + фактичний поліс, гейт підписання BIZ.2 MSA.
>
> **Канон:** [`00_04 §7`](../../00_04_Nature_as_a_Service_Contracts.md) (INS.1 — інша вісь, див. §4 нижче) + [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) (open-item BIZ.21) · [`00_02 §1.5`](../../00_02_Academic_Integration_and_IP.md) (СЄУ/Аблязов — UA legal-risk консультація, дотично, не insurance-продукт) · [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.21/BIZ.20/BIZ.2/BIZ.9.

---

## 0. Навіщо цей документ

SilkenNet — solo-founder pre-revenue forest-D-MRV платформа, що готується до першого B2B-продажу, з фізичною інсталяцією Ti-анкерів у дерева (арбористи в полі).

**Що саме продається (важливо для underwriting-класифікації):** продаваний продукт ЗАРАЗ — **MRV-дані та permanence/disturbance-monitoring** (continuous ground-truth телеметрія + real-time детекція порушень як «верифікований факт»), **а не carbon-кредити**. Кредит може випустити лише незалежний реєстр за затвердженою методологією; цей трек gated на BIZ.9 і структурно недоступний за поточного registry-ландшафту — деталь і метрологічне обґрунтування → [`carbon_registry_matrix`](carbon_registry_matrix.md) §1 + §6.1. Це розрізнення несуче саме для страхування: «MRV data services» і «carbon-credit sales» — **різні класи ризику** для андеррайтера, і назвати себе другим, будучи першим, означає купити не той поліс за не ту ціну.

**Ніщо зараз не страхує SilkenNet/founder'а від власної professional-liability.** BIZ.2 (MSA) due-diligence типово вимагає Certificate of Insurance (CoI) як signing-exhibit — без coverage-spec (цей документ) → без брокер-intake → без полісу → без CoI → блокує підписання першого B2B-контракту.

**Філософія (не gold-plate):** не купувати все зараз. Phase-gate по тригеру (pre-revenue → перший B2B-signing → board/priced-раунд), не по календарю.

---

## 1. Ризик-мапа — 3 конкретні ризики → тип поліса

| # | Ризик (конкретний сценарій) | Покриває | Межа покриття (де НЕ покриває) |
|---|---|---|---|
| **R1** | **D-MRV-accuracy dispute** — B2B-клієнт стверджує: «продані D-MRV-дані/carbon-credit розрахунок були недбало виміряні чи хибно верифіковані» | **Tech E&O / Professional Liability** — canonical fit. Ринковий precedent уже існує: «Consulting Foresters Professional Liability» endorsement (PHLY/AssuredPartners, Outdoor Underwriters) — нішевий продукт саме для forestry-консультантів, дослівно «safeguards against claims of negligence, errors, or omissions in the execution of MRV protocols or project reporting». | Не покриває, якщо спір — НЕ про недбалість SilkenNet, а про факт third-party fraud у самому carbon-проєкті (→ R3). |
| **R2** | **Anchor-install third-party injury** — арборист встромляє Ti-анкер, гілка падає й травмує перехожого/власника ділянки; АБО анкер через тиждень після інсталяції спричиняє шкоду (post-completion дефект) | **CGL + Products-Completed-Operations extension.** Products-completed-ops — окреме розширення (не default) саме для «дефект вже зданої роботи», а не лише «під час операції». | **Первинне покриття = арбористів власний GL + Workers' Comp**, НЕ SilkenNet-поліс (арборист типово subcontractor, не employee) — SilkenNet додається як **additional insured**, не самострахує сам акт інсталяції (деталь §5.2). Майнова шкода дереву власника — теж GL, ймовірно НЕ Environmental Impairment Liability (метал у стовбурі — не класичне «забруднення», але формулювання policy wording варто явно перевірити з брокером щодо pollution-exclusion). |
| **R3** | **Carbon-credit-claim dispute** — покупець оспорює credit; АБО третя сторона доводить fraud/reversal у самому проєкті; АБО реєстратор інвалідовує credit | **Контрактна risk-allocation в Carbon Credit Sale & Purchase Agreement** (representations & warranties + clawback clause) — насамперед. Опційно **carbon-credit-specific project-level insurance** (Kita CPPC/CPRC-типу, Oka) — окрема вісь, methodology-gated (§3.4). | Tech E&O покриває ЛИШЕ якщо спір зводиться до «наш D-MRV-процес був недбалим» (= R1). Tech E&O **НЕ покриває** «сам carbon-проєкт third-party fraud» чи «market invalidated credit» — це активний, не гіпотетичний, судовий тренд 2024-2025 (Бразилія REDD+ R$180M фрод, жовт.2025; CQC Impact Investors SDNY wire/securities-fraud indictment, жовт.2024; British American Tobacco project-legitimacy спір). |

**Ключовий висновок:** R1 і R3 виглядають подібно («хтось оспорює наш carbon-credit») але вимагають РІЗНИХ інструментів — R1 = поліс (Tech E&O), R3 = контракт (SPA-мова) в першу чергу, поліс (project-level) лише опційно й пізніше. Не плутати.

> ℹ️ R3 описує **майбутній** стан (коли/якщо з'явиться registry-issued кредит і його продаж). ЗАРАЗ продаваний продукт — MRV-дані/permanence-monitoring (§0), тож живий ризик сьогодні = R1 і R2. R3 тримається в спеці, бо risk-allocation-мова має потрапити в SPA **до** першого кредитного продажу, а не після.

---

## 2. Поліс-типи × покриття × cost × phase-gate (master-таблиця)

| Тип поліса | Що покриває (SilkenNet-specific) | Cost-діапазон (R6, 🟡 MEDIUM) | Phase-gate | B2B COI-ask? |
|---|---|---|---|---|
| **Tech E&O / Professional Liability** («Professional Indemnity» — UK/EU термін) | R1 (D-MRV-accuracy negligence) + частково R3 (якщо зводиться до недбалості) | US consultant-tier ~**$1,000/рік за $1M ліміту**; tech-specific ~$110/міс (**$500–$9,000+/рік**); UK PI від **£96/рік за £100k** (нижня межа, малий ліміт). Enterprise-ask стандарт: **$1–2M ліміт** | **Перший B2B-signing** (купити ПЕРШИМ з усього списку) | **Так** — procurement просить «by name», часто поруч із SOC2-запитом |
| **CGL + Products-Completed-Operations** | R2 (anchor-install injury, both operations + post-completion) | US baseline **$500–$1,200/рік** (low-risk consultant); **$600–$1,500/рік** (moderate-risk, field-ops на кшталт landscaper). Enterprise ask: **$1M/occurrence – $2M aggregate** | **Перед першою фізичною інсталяцією анкера** (не до, а саме до pilot-install, не обов'язково одночасно з E&O) | **Так** — «required before pulling permits, signing commercial contracts, issuing COI»; клієнт вимагає **additional insured** |
| **Cyber Liability** (часто bundled з Tech E&O) | Data breach, unauthorized access, business interruption, breach-notification, ransomware (OAuth/email PII + Web3-adjacent high-value target профіль) | US small-biz avg $129/міс (**$400–$8,000/рік**); tech-company avg $179/міс (**$650–$9,500/рік**). ⚠️ Premium зростає **~97%** при переході з <$1M у $1–5M revenue-бенд | **Разом із Tech E&O** (перший B2B-signing) | Так, «сидить поруч із SOC2-запитом» — **АЛЕ прочитай war-exclusion wording ПЕРЕД покупкою** (§5.1, критично для UA) |
| **D&O (Directors & Officers)** | Позови проти директорів/офіцерів за рішення від імені компанії (fiduciary breach, misrepresentation інвесторам) — Side A/B/C | Pre-seed/seed **$3,500–$6,000/рік за $1M** (деякі carriers — промо $2,500 перший рік); Series A **$5,000–$10,000/рік за $1–3M**; Series B+ **$10,000–$25,000/рік за $5–10M** | **Відкласти до board / priced-раунду** (VC-мандат перед закриттям раунду, НЕ pre-revenue-пріоритет) | **Зазвичай НІ** — це про інвесторів/board, не delivery-risk; B2B-клієнт цього не питає |
| **Carbon-credit project-level insurance** (Kita CPPC/CPRC-типу, Oka) — ⚠️ ІНША вісь, не corporate-поліс | R3 non-delivery/reversal (fraud, negligence, human error, insolvency, invalidation); Kita CPRC — political/host-country risk | **2–10% від вартості кредиту/рік** (project-risk-залежний, широкий діапазон). Ринок росте швидко: Kita розширила underwriting-capacity **на 450% — до $29.1M (=£22.5M, той самий показник у двох валютах)**, квіт.2025; базова сума ДО зростання в джерелі не наведена, тож абсолютний старт-рівень не відтворюваний | **Methodology-gated, НЕ time-gated** — лише якщо (a) buyer-контракт вимагає, АБО (b) реєстрація під Verra/Gold Standard де «Approved Insurance Policy» (Verra v5) — визнана альтернатива buffer-pool. Залежить від `BIZ.9` (незалежний carbon-методолог) рішення | Лише якщо buyer/реєстратор явно вимагає — **не default-checklist item** |
| ~~Smart-contract/DeFi cover~~ (Nexus Mutual-типу) | Exploit смарт-контракту, deposit/protocol-рівня втрати on-chain | <1%/рік per-protocol; pool ~$190M capital / ~$194M active cover (mid-2025) | **SKIP** — не приоритет зараз | **НІ** — не визнається enterprise-procurement як COI-eligible (mutual/DAO-модель, не ліцензований traditional carrier); revisit лише коли on-chain TVL стане матеріальним |

---

## 3. Phase-gate timeline (детально)

### 3.1 ЗАРАЗ — pre-revenue, solo, нічого не задеплоєно

**Юридично нічого не обов'язкове.** Немає employees крім founder'а → немає Workers' Comp-тригера; немає board/priced-раунду → немає D&O-мандату; немає живого B2B-контракту → немає COI-запиту ще. Дешевий pre-seed D&O ($2.5–6k/рік) іноді береться раніше якщо вже є advisor/board-структура чи investor-tied priced SAFE — **для чистого solo pre-revenue founder'а це відкладається**.

**Дія зараз:** нічого не купувати. Єдина підготовча дія — цей coverage-spec (готовий, цей документ). Чекати на вибір юрособи більше не потрібно: страхувальник = operational-vehicle (UA) уже визначений — лишається з'ясувати, які carrier'и за такої домициляції взагалі доступні (§5.3; це питання №1 до брокера, а не наслідок ще-не-ухваленого рішення).

### 3.2 Тригер: «B2B-signing» / перша pilot-інсталяція

Пріоритет придбання — **в порядку, не паралельно**:

1. **Tech E&O / Professional Liability** — купити ПЕРШИМ. Procurement просить «by name»; єдиний поліс що напряму мапиться на core-ризик бізнесу (R1).
2. **CGL + Products-Completed-Operations** ($1M/occ–$2M agg) — купити ПЕРЕД першою фізичною інсталяцією анкера. Вимагай від арбориста-підрядника власну GL + додай SilkenNet (і власника ділянки за контрактом) як additional insured (§5.2).
3. **Cyber liability** (часто bundled з #1) — разом із Tech E&O. **Прочитай war/cyber-war exclusion wording рядок-в-рядок** (§5.1) — це не формальність для UA-домицільованої компанії.
4. D&O — НЕ на цьому тригері (див. 3.3).
5. Carbon-credit project-level cover — НЕ на цьому тригері, окрім якщо buyer вже на етапі MSA explicitly вимагає (рідкість pre-BIZ.9).

**Результат цієї фази:** CoI-пакет (E&O + CGL, опційно cyber) готовий як signing-exhibit для BIZ.2 MSA.

### 3.3 Тригер: board seated / priced-раунд / зовнішні investor-гроші

**D&O** — тепер, не раніше. Зверни увагу: Web3/DAO-специфічний D&O — молодий, вузький ринок (перший спеціалізований crypto-D&O продукт для Web3-founders запущено лише **2026-06-24**, Nico Laqua/Cointrust); юридичний статус DAO лишається fluid globally. Це означає: коли настане час купувати D&O, очікуй вужчий вибір carrier'ів і вищу премію за «Web3-founder»-профіль порівняно з generic SaaS D&O — закладай це в бюджет-планування раунду, не сюрприз post-closing.

### 3.4 Orthogonal вісь: carbon-credit project-level insurance (НЕ time-gated)

Це **не startup-insurance-checklist item** — це methodology/registry-рішення. Активується лише коли:
- (a) `BIZ.9` (незалежний carbon-методолог, Verra/Gold Standard/Puro.earth) вирішено на користь реєстру що визнає/вимагає insurance-backed buffer-альтернативу (Verra v5 «Approved Insurance Policy»), АБО
- (b) конкретний B2B-buyer explicitly вимагає в SPA.

До того — трактуй R3 виключно через контрактну risk-allocation (SPA reps & warranties + clawback), не через поліс.

---

## 4. Розрізнення від INS.1 (щоб не плутати — критично)

⚠️ **INS.1 ([`00_04 §7`](../../00_04_Nature_as_a_Service_Contracts.md)) і BIZ.21 (цей документ) — це ДВІ РІЗНІ речі**, що випадково схожі назвою («страхування») але захищають протилежні сторони контракту:

| Вимір | **INS.1** (параметричне страхування) | **BIZ.21** (E&O/D&O/liability — цей документ) |
|---|---|---|
| **Кого захищає** | **Клієнта** (власника дерева/лісу) — від деградації/загибелі застрахованого лісового активу | **SilkenNet/founder'а** — від professional-liability за власні дії/послуги |
| **Тип продукту** | Внутрішній платформний feature — параметричний dual-trigger payout (`ParametricInsurance` model, [`05_05 §4`](../../05_05_Slashing_and_Risk_Policy.md)) | Зовнішній корпоративний поліс, куплений у traditional insurance carrier через ліцензованого брокера |
| **Тригер виплати** | Trigger-1 (AI-оракул, `ParametricInsurance#evaluate_daily_health!`) озброює кандидата; Trigger-2 (незалежне підтвердження — dClimate FIRMS-супутник для пожежі; Field-Audit для посухи/шкідників, бо супутникового drought/pest-оракула немає) підтверджує payout | Claim-процес через страхового carrier'а (adjuster, underwriting-review) — стандартний insurance-claims workflow, не on-chain механіка |
| **Хто платить** | SilkenNet (internal SCC/SFC mint, `Insurance::ReserveGate` stop-loss) АБО Etherisc DIP-пул (oracle mode, зовнішній USDC) | Insurance carrier (traditional, off-chain, USD/EUR) |
| **Статус** | Механіка inert за дизайном — kill-switch `:parametric_insurance_oracle_enabled` = off (default), чекає DAO/founder-активації | Не існує взагалі — це якраз діра, яку цей coverage-spec адресує |
| **Канон-дім** | [`00_04 §7`](../../00_04_Nature_as_a_Service_Contracts.md), [`05_05 §4`](../../05_05_Slashing_and_Risk_Policy.md) (dual-trigger policy) | [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) (open item), [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.21 |

**Мнемоніка:** INS.1 = «ми страхуємо ЇХНЄ дерево». BIZ.21 = «хтось страхує НАС, якщо ми накосячили».

---

## 5. 🔴 UA-специфічні gotchas

### 5.1 War / state-actor exclusion (cyber — критично; дотично GL/D&O/property)

- **Прецедент Merck v. ACE American (NotPetya, 2022):** NJ court визнав, що «hostile/warlike action» exclusion вимагає ФАКТИЧНОЇ військової дії — Merck виграв $700M+ claim, бо кібератака (2017, Russian military hackers) не була формальним актом війни за ТОДІШНІМ формулюванням exclusion.
- **Але з грудня 2021 ринок закрив цю дірку:** Lloyd's Market Association — 4 модельні clauses (**LMA5564–5567**), обов'язкові для syndicates з серпня 2022 (Market Bulletin Y5381). **LMA5564** = найширший (виключає ВСІ state-attributed атаки); **LMA5567** = найпоширеніший, вужчий (не blanket-виключає nation-state атаки).
- **Наслідок:** будь-який cyber-поліс підписаний ПІСЛЯ 2022 майже гарантовано містить один із цих clauses. Ukraine = активна ціль Russian state-sponsored cyber-операцій; страхувальник домицільований в Україні (незалежно від того, що серверна інфра GCP/Akash поза Україною) → «атака атрибутована РФ» — правдоподібний сценарій, НЕ хвостовий ризик.

**Конкретні питання до брокера (обов'язково поставити, не пропускати):**
1. Який EXACT clause-варіант (LMA5564 vs LMA5567 vs інший) у пропонованому cyber-полісі — покажи мені точний текст, не summary.
2. Чи атрибуція «державна атака» вимагає офіційної заяви уряду (як в LMA5564), чи carrier може атрибутувати самостійно на власний розсуд?
3. Чи є на ринку carrier, що пише вужчий war-exclusion (LMA5567-типу чи кращий) саме для UA-based tech-компаній — чи це взагалі недоступно given профіль ризику?
4. Чи є backup/альтернативне formulation (sub-limit замість повного excl., чи окремий war-risk rider) що carrier готовий запропонувати?
5. Аналогічне питання для CGL/D&O/property поліса — стандартний war-exclusion (repository ~900 варіантів формулювань) виключає property/business-interruption від воєнних дій; дотично, якщо буде фізичний офіс/склад в Україні.

**Домашній backstop (не заміна страхування, лише доповнення):** Постанова КМУ №1541 (чинна з 01.01.2026) — пряма компенсація до 10 млн грн за знищені/пошкоджені активи у високоризикових регіонах + часткова компенсація (до 1 млн грн/рік) премій за страхування воєнного ризику, придбане в Україні. Це про **майно**, НЕ про liability — не покриває третю особу, що постраждала від анкера, чи claim від B2B-клієнта. Не рахувати як заміну §2-полісів.

### 5.2 Subcontractor-арборист GL + additional insured (не самострахувати install)

- Арборист, що фізично вкручує Ti-анкер, — **subcontractor, не employee SilkenNet**. Первинне покриття травми третьої особи/майнової шкоди = **арбористова власна GL** (+ Workers' Comp за травму власного робітника, якщо релевантно).
- **SilkenNet НЕ повинен самострахувати цей акт** — натомість: (a) вимагати COI від арбориста ПЕРЕД початком робіт, (b) додати SilkenNet **named additional insured** на арбористовому полісі, (c) де релевантно — додати і власника ділянки/кінцевого клієнта як additional insured теж (суцільний ланцюг: арборист → SilkenNet → клієнт).
- **Products-completed-operations gap-перевірка:** це розширення типово НЕ default (окрема галка в policy wording) — explicitly перевір, чи арбористів поліс його включає, бо саме воно покриває «анкер підвів через тиждень після інсталяції», а не базове «operations»-покриття.
- Використай цю ж вимогу (арборист COI + additional-insured) як **contract clause в Subcontractor Agreement** з кожним арбористом-партнером, не лише як insurance-checklist — контрактна мова робить вимогу enforceable, не лише «просимо ввічливо».

### 5.3 UA-домициляція страхувальника = чинна friction-точка доступу до carrier'ів

- Страхувальник = operational-vehicle, наявна UA-компанія (§0) → домициляція **Україна**. Це не гіпотеза й не «залежить від майбутнього вибору»: constraint **активний уже зараз**, і планувати треба від нього.
- Mainstream US/UK insurtech-MGA (Vouch, Founder Shield, Coalition, Corgi) побудовані навколо US-domiciled стартапів — UA-домицільована компанія має обмежений прямий доступ.
- Типовий шлях для non-US founders — Delaware C-Corp «flip» (робиться переважно заради US VC-доступу) — **побічно вирішує і insurance-access проблему** через відкриття доступу до US/UK specialty-carriers. Але це **fundraising-driven рішення про корпоративну структуру**, що лежить поза чинною entity-рамкою (operational-vehicle UA + IP на фізособі + token-контур окремою фазою → [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)). Insurance-access — **tailwind** такого рішення, якщо воно ухвалюється з інших причин, і ніколи не самостійна причина його ухвалювати.
- ⚖️ **Реально відкрите питання:** чи знайдеться взагалі carrier, готовий underwrite'ити UA-домицільованого страхувальника з forest-hardware + Web3-adjacent профілем **напряму** — і на яких умовах. Це питання №1 до брокера (§6), бо воно може виявитись гейтингом раніше за будь-яку ціну.

---

## 6. Broker Intake Checklist (практичний handoff)

Коли настане час дзвонити брокеру (перед першим B2B-signing) — принеси:

- [ ] Цей coverage-spec (весь документ) + risk-мапа §1.
- [ ] Реєстраційні реквізити operational-vehicle (UA) — юрисдикція страхувальника визначає доступних carrier'ів (§5.3).
- [ ] Опис бізнесу для underwriting — **формулювання має значення для класифікації ризику; НЕ називай це «carbon-credit sales»**: «forest D-MRV data services + permanence/disturbance monitoring, B2B; carbon-кредити нами НЕ емітуються й не продаються — кредит випускає незалежний реєстр за затвердженою методологією, і цей трек gated ([`carbon_registry_matrix`](carbon_registry_matrix.md)); фізична field-інсталяція (Ti-анкер у дерево) через субпідрядників-арбористів (не employees); Web3/blockchain-adjacent (SCC/SFC token minting, публічна платформа Polygon)».
- [ ] Explicit ask #1: Tech E&O / Professional Liability, ліміт $1–2M, з мовою що покриває «negligence, errors, or omissions in MRV protocols/project reporting» (пошукай явний match з «Consulting Foresters Professional Liability»-категорією).
- [ ] Explicit ask #2: CGL, $1M/occurrence–$2M aggregate, З products-completed-operations extension explicitly включеним (не default — попроси письмово підтвердити).
- [ ] Explicit ask #3 (за бюджетом/готовністю): Cyber liability bundled з #1 — з War-exclusion питаннями §5.1 поставленими ПЕРЕД підписанням, не після.
- [ ] Explicit НЕ-ask зараз: D&O (відклади до board/priced-раунду, §3.3), carbon-credit project-level cover (methodology-gated, §3.4), smart-contract/DeFi cover (skip, §2).
- [ ] Питання: чи carrier взагалі underwrite'ить UA-домицільовану компанію з цим профілем ризику напряму, чи потрібен US/UK-entity wrapper (§5.3) — постав це питання ПЕРШИМ, до детального price-shopping (може виявитись гейтинг-фактором раніше за все інше).

---

## Джерела

Усі факти/цифри — з [`R6_insurance_dpa.md`](../research/R6_insurance_dpa.md) §1–§2, §4 (insurance-half; §3 DPA/GDPR — поза скоупом цього документа). Первинні web-джерела — повний список у R6 (insurance-relevant URLs: Embroker, QuoteSweep, Insureon, TechInsurance, WHINS, Corgi, Kita, Oka, Trellis, Sylvera, Vouch, Insura, Beancount.io, HUB International, Construction Coverage, Quinn Emanuel, 5SAH, green.earth, PHLY/AssuredPartners/Outdoor Underwriters, MoneyGeek, Cointrust, Suited.insure, DAC Beachcroft, KWM, Cyber Insurance Academy, IBM/Merck, CMS Law-Now, CEE Legal Matters — усі 2025-2026).

> ⚠️ **Kita-число — корекція проти R6.** R6 переказує показник як «$22.5M/£22.5M → $29.1M (450% зростання)», що читається як зростання з $22.5M до $29.1M (+29%) і суперечить «450%». Первинне формулювання: capacity зросла **на 450% до $29.1M (£22.5M)** — тобто £22.5M і $29.1M є **тією самою сумою у двох валютах**, а базовий рівень до зростання в джерелі не наведений. У §2 наведено виправлену форму; переказ із R6 не використовувати.

Канон: [`00_04 §7`](../../00_04_Nature_as_a_Service_Contracts.md) (INS.1) + [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) (BIZ.21 open-item) · [`05_05 §4`](../../05_05_Slashing_and_Risk_Policy.md) (dual-trigger) · [`00_02 §1.5`](../../00_02_Academic_Integration_and_IP.md) (СЄУ/Аблязов) · [`00_07`](../../00_07_Action_Plan_Tracker.md) (BIZ.21, BIZ.20, BIZ.2, BIZ.9, BIZ.18).
