# R6 — Insurance + GDPR/DPA orientation-дослідження для SilkenNet

> **Що це:** знімок веб-дослідження, зібраний агентом під час §07 legal/business-кампанії. Це **вхідні дані** для артефактів у [`legal/`](../legal/) та [`business/`](../business/), а не самостійне джерело істини.
> **Concern-шар — НЕ канон.** Правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас.
> **⚠️ НЕ верифіковано пофактно.** Кожне твердження потребує перевірки першоджерела перед використанням; це не юридична/податкова/фінансова порада.


**Статус:** PUBLIC web-research → orientation, **НЕ страхова/юридична порада**. Кожна цифра/твердження — з джерелом+датою+рівнем впевненості. Перед будь-яким реальним придбанням поліса чи підписанням DPA — консультація з ліцензованим broker'ом (страхування) та юристом з data-protection (GDPR), особливо там де позначено 🔴 LOW confidence.

**Контекст задачі:** solo-founder forest-D-MRV, продає B2B carbon-credits + D-MRV-дані як «верифікований факт», фізична інсталяція Ti-анкерів у дерева (арбористи в полі), збирає telemetry + B2C дані (email + пароль), хостинг GCP + RPC-провайдери + Redis. Nothing deployed yet — готується до першого B2B-продажу.

---

## 1. Insurance-матриця

| Тип поліса | Що покриває | Типовий ліміт / cost (джерело) | Коли B2B-контракт вимагає COI | Юрисдикція-нотатка |
|---|---|---|---|---|
| **Tech E&O / Professional Liability** («Professional Indemnity» — UK/EU термін) | Негативна помилка/недбалість у наданій послузі чи проданих даних — тобто ТОЧНО сценарій «D-MRV-дані продані як факт виявились помилковими» | US: consultant-tier ~$1,000/рік за $1M ліміту (Insureon/TechInsurance); tech-specific ~$110/міс, $500–$9,000+/рік (WHINS/Insureon); UK PI від £96/рік за £100k (Suited.insure — це нижня межа, малий ліміт). Ринковий стандарт для enterprise-ask: $1–2M | Так — «procurement teams ask for it by name»; це поліс що **unlocks enterprise contracts**, часто поруч із SOC2-запитом | US/UK терміни різні (E&O vs PI) але покриття еквівалентне; FR=«RC Professionnelle», DE=«Berufshaftpflicht» — якщо клієнт з EU, очікуй запит саме локальним терміном |
| **D&O (Directors & Officers)** | Позови проти директорів/офіцерів за рішення від імені компанії (fiduciary breach, misrepresentation інвесторам); Side A (особистий захист) / B (реімбурсація компанії) / C (entity/securities) | Pre-seed/seed: $3,500–$6,000/рік за $1M ліміту (деякі carriers — промо $2,500 перший рік); Series A: $5,000–$10,000/рік за $1–3M; Series B+: $10,000–$25,000/рік за $5–10M (Vouch, Beancount.io, Insura — 2026 pricing guides) | Зазвичай НЕ B2B-клієнтський ask (це про інвесторів/board, не про delivery-risk) — але **VCs mandate D&O перед закриттям раунду**; M&A/фінансові контрагенти теж іноді просять COI | Web3/DAO-специфічний D&O — молодий, вузький ринок: перший спеціалізований crypto-D&O продукт для Web3-засновників запущено лише 2026-06-24 (Nico Laqua/Cointrust) — юридичний статус DAO лишається fluid globally |
| **General Liability (CGL) + Product Liability** | Тілесні ушкодження / майнова шкода третім особам від бізнес-операцій; **products-completed operations** розширення = покриває дефект вже зданої роботи (анкер підвів ПІСЛЯ інсталяції) | US baseline: $500–$1,200/рік для low-risk консультанта; $600–$1,500/рік для moderate-risk (польові роботи, на кшталт landscaper) (MoneyGeek/Insureon/Copeland). Enterprise-стандартний ask: **$1M/occurrence – $2M aggregate** | Так — «required before pulling permits, signing commercial contracts, or issuing a COI»; клієнт типово вимагає бути доданим як **additional insured** (не просто «certificate holder») | Арборист-підрядник (хто фізично вкручує анкер) має нести ВЛАСНУ GL + додати SilkenNet/власника ділянки як additional insured — не самострахувати цей акт |
| **Cyber Liability** (часто bundled з Tech E&O) | Data breach, unauthorized access, business interruption від кібератаки, breach-notification costs, ransomware | US small-biz avg $129/міс ($400–$8,000/рік); tech-company avg $179/міс ($650–$9,500/рік) (TechInsurance/Insureon). ⚠️ Premium зростає ~97% при переході з <$1M у $1–5M revenue-бенд | Так, разом із Tech E&O — «insurance clause increasingly sits right next to the SOC 2 request» | 🔴 **Критичний gotcha для UA-based бізнесу**: майже кожен cyber-поліс з 2022 має явний **war/state-backed-attack exclusion** (Lloyd's LMA5564–5567, з грудня 2021 + Market Bulletin Y5381 серпень 2022) — деталь нижче §2.4 |
| **Smart-contract / DeFi cover** (Nexus Mutual та подібні) | Exploit смарт-контракту, deposit чи protocol-рівня втрати on-chain | Прайсинг <1%/рік для окремих протоколів (лют. 2025); capital pool ~$190M, active cover ~$194M (mid-2025) | НІ — це НЕ визнаний enterprise-procurement COI-продукт (mutual/DAO-модель, не ліцензований traditional carrier) | Доповнення, не заміна traditional Tech E&O/cyber для SCC/SFC minting-контрактів |
| **Carbon-credit / project-рівня insurance** (Kita CPPC/CPRC, Oka) — ⚠️ ІНША вісь, не corporate-поліс | Недопоставка/reversal кредитів: fraud, negligence, human error, insolvency, invalidation (Kita CPPC); political/host-country risk (CPRC); Oka з серп.2025 — green-credit/transition-financing de-risking | **2–10% від вартості кредиту/рік** (широкий діапазон, project-risk-залежний — Trellis/Sylvera); Kita capacity → $29.1M (квіт. 2025, зростання на 450%) ⚠️ **корекція знімка:** первісне формулювання «$22.5M/£22.5M → $29.1M» хибне — £22.5M і $29.1M це ОДНА сума у двох валютах (дослівно в джерелі: «expanded its underwriting capacity by 450% to $29.1 million (£22.5 million)»); базова сума ДО зростання в джерелі не наведена | Може вимагатись buyer'ом carbon-credit угоди АБО реєстратором (Verra v5, 2024/2025: «Approved Insurance Policy» — визнана альтернатива buffer-pool для land-based reversal-risk, реєстр САМ верифікує страховика) | Актуально лише якщо SilkenNet реєструється під Verra/Gold Standard замість proprietary-реєстру — це **methodology-рішення, не insurance-checklist item** |

**Довірчий рівень:** усі cost-рейнджі — 🟡 MEDIUM confidence (multiple broker/insurtech blog-джерела узгоджені між собою, але жодне не є первинним прайс-листом carrier'а; реальна ціна для конкретно UA-inc компанії з forest-hardware ризиком може суттєво відрізнятись). Carbon-credit insurance % — 🟡 MEDIUM (2 незалежні джерела збігаються в порядку величини).

---

## 2. Специфічні ризики → який поліс

### 2.1 Carbon-credit-claim dispute (покупець оспорює кредит)
- **Реальність ринку:** «no single regulator governs the voluntary market... credibility depends on private contractual agreements» → buyer-seller спори — не гіпотетичний, а активний judicial trend. Приклади 2024–2025: Бразилія (жовт. 2025) — 31 особа обвинувачена в R$180M REDD+ фрод-справі; CQC Impact Investors executives (жовт. 2024, SDNY) — wire/securities fraud indictment; British American Tobacco — тривалий спір навколо «illegitimacy» проєктів. (Quinn Emanuel client alert; carbonherald.com; 5SAH; green.earth — усі 2025-2026)
- **Який поліс:** це НЕ Tech E&O в класичному розумінні — це **carbon-credit-specific delivery/reversal insurance** (Kita CPPC-типу) на рівні проєкту/угоди, АБО contractual risk-allocation у самому Carbon Credit Sale & Purchase Agreement (representations & warranties, clawback clause). Tech E&O покриє SilkenNet якщо спір зводиться до «ваш D-MRV-процес був недбалим» (тобто помилка/negligence у вимірюванні) — але не покриє «сам carbon-проєкт виявився фродом третьої сторони» чи «market invalidated the credit».
- **Висновок:** SilkenNet потребує ОБИДВА: (a) Tech E&O за власну D-MRV-методологію, (b) контрактну структуру угоди (SPA-мова, не поліс) що чітко розмежовує «ми ручаємось за точність вимірювання» vs «ми не ручаємось за факт non-reversal/non-fraud третьої сторони», якщо є намір уникнути carbon-specific insurance на старті.

### 2.2 D-MRV-accuracy negligence (помилка у вимірюванні/верифікації)
- **Найближчий існуючий продукт-аналог:** «Consulting Foresters Professional Liability» endorsement — реально існуючий нішевий продукт (Philadelphia Insurance Companies/PHLY, AssuredPartners, Outdoor Underwriters) для forestry-консультантів, з знижками для членів Association of Consulting Foresters. Це прямий precedent що ринок вже має «forestry data professional negligence»-поліс-категорію.
- Окремо: «Mangrove Blue Carbon MRV Liability Insurance» — знайдено в market-research-report (dataintelo.com), що заявляє $1.2B ринок 2024→$5.8B до 2033 (CAGR 19.1%). 🔴 **LOW confidence** — це типовий auto-generated/report-mill сайт (продає paywalled звіт), цифри непровірювані з незалежного джерела; НЕ покладайся на конкретні числа звідси, лише як сигнал що «MRV professional liability» — це вже named категорія в insurance-мисленні ринку.
- **Який поліс:** Tech E&O / Professional Liability — це canonical fit. Deep dive: carrier explicitly frames це як «safeguards against claims of negligence, errors, or omissions in the execution of MRV protocols or project reporting» — точна мова під SilkenNet-кейс.

### 2.3 Anchor-install injury (арборист встромляє Ti-анкер, гілка падає, травма третьої особи)
- **Хто несе:** якщо арборист — subcontractor (не employee SilkenNet), первинне покриття = **арбористовий власний GL + Workers' Comp** (WC покриває травму власного/підрядного робітника; GL покриває третю особу — перехожого, власника ділянки). SilkenNet як контрактор-у-ланцюгу типово вимагає бути **additional insured** на арбористовому полісі + вимагає COI ПЕРЕД початком робіт.
- **Products-completed operations:** якщо анкер (вже встановлений, арборист поїхав) через тиждень спричинить шкоду — це post-completion дефект, покривається `products-completed operations` розширенням GL, НЕ базовим «operations» покриттям — перевір explicitly чи в арбористовому/власному полісі це розширення включене (типово не default, окрема galka).
- **Property damage до самого дерева** (шкода/загибель дерева власника ділянки від процесу інсталяції) — це майнова шкода, теж під GL, не «environmental impairment liability» (EIL — той продукт про pollution/contamination сайту, Ti-6Al-4V метал у стовбурі навряд формально «забруднення», отже EIL-рейдер, ймовірно, зайвий; але формулювання «зашкодив дереву» варто явно перевірити в policy wording, чи не підпадає під pollution-exclusion щодо чужорідного матеріалу в живій тканині).
- **Який поліс:** CGL з products-completed-operations extension — і саме тому COI-ланцюг (арборист → SilkenNet → кінцевий клієнт/власник ділянки) має бути суцільним, кожна ланка named additional insured на попередній.

### 2.4 🔴 Ukraine-специфічний gotcha: war / state-actor exclusion (крос-риз для ВСІХ 4 полісів вище)
- **Прецедент Merck v. ACE American (NotPetya):** NJ Superior Court (2022) + Appellate Division визнали, що «hostile/warlike action» exclusion вимагає **фактичної військової дії** — Merck виграв $700M+ claim, бо кібератака (Russian military hackers, 2017) не була формальним актом війни за тодішнім формулюванням exclusion.
- **Але з грудня 2021 ринок закрив цю дірку:** Lloyd's Market Association випустила 4 модельні clauses (LMA5564–5567, LMA21-042-PD), Lloyd's Market Bulletin Y5381 (16.08.2022) зробила їх обов'язковими для syndicates. LMA5564 = найширший (виключає ВСІ state-attributed атаки, атрибуція — насамперед за заявою уряду держави де знаходиться уражена система); LMA5567 = найпоширеніший, вужчий (не blanket-виключає nation-state атаки).
- **Наслідок для SilkenNet:** будь-який cyber-поліс, підписаний ПІСЛЯ 2022, майже гарантовано містить один із цих clauses. Given Ukraine = активна ціль Russian state-sponsored cyber-операцій, а SilkenNet — UA-inc/hosted компанія (навіть якщо серверна інфра — GCP поза Україною, компанія-як-суб'єкт still UA) — **прочитай EXACT exclusion wording перед покупкою**, бо «атака атрибутована РФ» — правдоподібний сценарій, не хвостовий ризик.
- **Аналогічно для GL/D&O/property:** стандартний war-exclusion (Lloyd's repository налічує ~900 варіантів формулювань) виключає property/business-interruption втрати від воєнних дій; це стосується фізичних активів/офісу в Україні, не так прямо самого cyber/data-risk, але той самий принцип «active conflict zone = coverage friction» застосовується до GL за фізичну присутність (наприклад інсталяційна команда в зоні бойових дій — малоймовірно для Черкас, але relevant для регіонів ближче до фронту).
- **Домашній backstop (не заміна страхування, доповнення):** Постанова КМУ №1541 (набирає чинності 01.01.2026) — новий механізм: пряма компенсація до 10 млн грн за знищені/пошкоджені активи у високоризикових регіонах + часткова компенсація (до 1 млн грн/рік) премій за війни-ризик страхування, придбаного в Україні (CMS Law-Now, груд. 2025; ceelegalmatters.com). Це про **майно**, не про liability — не покриває третю особу що постраждала від встановленого анкера чи claim від B2B-клієнта.
- **Практичний висновок:** UA-інкорпорація — реальна friction-точка для доступу до mainstream US/UK insurtech-MGA (Vouch, Founder Shield, Coalition, Corgi — усі побудовані навколо US-domiciled стартапів). Типовий шлях для non-US засновників (Delaware C-Corp «flip» — робиться переважно заради US VC-інвестицій, SeedLegals/Capbase/Fellow.legal, 2025-2026 guides) **побічно вирішує і insurance-access проблему**, бо відкриває доступ до US/UK specialty-carriers що інакше не пишуть UA-ризик напряму. Це рішення про corporate structure, не просто insurance-checklist — вартий окремого founder-рівня обговорення, не тут.

---

## 3. GDPR / Data Processing Agreement (DPA)

### 3.1 Базові вимоги DPA (Art. 28(3) GDPR)
Письмовий DPA обов'язковий щоразу, коли третя сторона обробляє персональні дані ЗА ІНСТРУКЦІЄЮ контролера. Має містити: scope/purpose/duration обробки, інструкції контролера, конфіденційність, технічні/організаційні заходи безпеки (Art. 32), правила sub-processor'ів, допомогу з data-subject rights, breach-notification, видалення/повернення даних по завершенню, audit rights. Два режими авторизації sub-processor'ів: **general authorization** (публічний список + вікно заперечення, типово 14–30 днів — стандарт для SaaS) vs **specific authorization** (названі sub-processors поіменно). (complydog.com, secureprivacy.ai, promise.legal — усі 2025)

### 3.2 Хто є controller / хто processor для SilkenNet (мапа ролей)
- **SilkenNet = CONTROLLER** власних B2C-даних кінцевого користувача (email, обліковий запис) — САМ визначає мету/засоби обробки → на ньому lawful basis, privacy notice, DSR-процес, 72-годинний breach-notification обов'язок (Art. 33) щодо цих даних.
- **SilkenNet = CONTROLLER**, а НЕ processor, щодо персональних даних вбудованих у B2B-проданий «verified fact» data-продукт (carbon-credit + D-MRV) — це продаж ВЛАСНОГО верифікованого output, не «обробка за інструкцією» покупця → **DPA покупцю НЕ потрібен** для цього потоку даних (не плутай з DPA логікою account-даних).
- **SilkenNet = CONTROLLER відносно власних infra-вендорів** (GCP, RPC-провайдери, Redis-hosting), котрі виступають **processors/sub-processors** обробки user-даних SilkenNet → SilkenNet потребує DPA **ВІД кожного** з них:
  - **Google Cloud** — публікує стандартний DPA + власні SCC (cloud.google.com/terms/sccs, cloud.google.com/privacy/gdpr) — 🟢 HIGH confidence, добре задокументовано.
  - **RPC-провайдери (Infura/ConsenSys, Alchemy та подібні)** — 🟡 підтверджено, що вони збирають **IP-адресу + гаманець-адресу** користувача при кожній транзакції (Decrypt/Blockworks/crypto.news, 2022-дослідження, досі актуальна практика) — IP-адреса = персональні дані за прецедентом CJEU Breyer → це РЕАЛЬНИЙ, не теоретичний, sub-processor-link що потребує DPA-перевірки. Знайдений research-pass НЕ підтвердив чи Infura/Alchemy публікують GDPR-стандартний DPA explicitly — **verify напряму** (🔴 відкрите питання).

### 3.3 Екстериторіальна дія GDPR (UA-компанія + EU data subjects)
- **Article 3(2):** застосовується до non-EU controller/processor коли (a) пропонує товари/послуги EU data subjects (навіть безкоштовно), АБО (b) моніторить їхню поведінку в межах EU. Просто доступність вебсайту з EU — **недостатньо**, потрібен доказ наміру таргетувати EU (валюта, мова, EU-специфічний маркетинг тощо). SilkenNet, продаючи carbon-credits/дані EU-based корпоративним покупцям + потенційно маючи EU-based B2C-користувачів → GDPR **майже напевно застосовується напряму**, незалежно від UA-інкорпорації. (gdpr.eu, IAPP, EDPB Guidelines 3/2018 — стабільна, добре усталена норма)
- **Article 27 — обов'язок призначити EU-representative**, якщо потрапляєш в Art. 3(2) scope (виняток лише для «occasional, small-scale, low-risk» обробки — систематичний збір B2C-акаунтів, ймовірно, НЕ підпадає під виняток, щойно з'явиться реальна EU-users база). Представник — контактна точка для supervisory authorities/data subjects, і **може нести пряму відповідальність** за провали закордонного controller'а — це реальна фінансова/репутаційна ставка, не просто paperwork.
- **Ukraine adequacy-статус:** Україна **НЕ має** Art. 45 adequacy decision від EU Commission (станом на дослідження) → трансфер персональних даних З EU ДО UA-based controller/processor потребує transfer-механізму — стандарт = **2021 SCCs** (4 модулі: Module 1 C2C controller-to-controller, Module 2 C2P controller-to-processor, Module 3 P2P processor-to-processor, Module 4 P2C processor-to-controller — Module 2 покриває заразом і Art.28(3) DPA-вимогу, окремий DPA не потрібен якщо SCC Module 2 підписано). Draft Law 8153 (гармонізація UA з GDPR) — в процесі, **зісковзнув** з таргету ~Q1 2026 (Council of Europe дала формальний висновок на початку 2025 з рекомендаціями). **Практичний висновок:** SCC — інструмент на найближчі роки, не чекай adequacy decision.
- **US sub-processor кут (якщо будь-який вендор хостить EU-дані на US-землі):** EU-US Data Privacy Framework (DPF, adequacy decision 2023) — **все ще чинний**, пережив перший виклик (General Court, 03.09.2025, справа Latombe), АЛЕ апеляція подана до CJEU (31.10.2025) і ще розглядається; окремо noyb/Max Schrems (лист 30.06.2026) підняв питання про **незалежність FTC** після рішення US Supreme Court, що може підірвати adequacy-логіку DPF. Це третя framework поспіль (після Safe Harbor 2015 і Privacy Shield 2020 — обидва CJEU скасував по Schrems I/II) — **реальна, не гіпотетична юридична невизначеність**. Best practice: НЕ покладайся лише на DPF-adequacy, дублюй SCC як backup transfer-механізм у вендор-DPA (більшість великих US cloud-вендорів вже так роблять — Google Cloud публікує і DPF-reliance, і SCCs одночасно).

### 3.4 DPO (Data Protection Officer) — чи потрібен?
- Обов'язковий (Art. 37) лише коли: (a) публічний орган, (b) core activities = «regular and systematic monitoring of data subjects on a large scale», або (c) core activities = large-scale обробка спеціальних категорій даних. Розмір компанії сам по собі НЕ є критерієм — приклад з дослідження: «50-осібний стартап що обробляє health-дані 5,000 пацієнтів може потребувати DPO, тоді як 500-осібна plain B2B SaaS-компанія може не потребувати».
- Деякі member states йдуть далі GDPR-baseline (Німеччина BDSG: обов'язковий DPO при >20 осіб що регулярно обробляють персональні дані) — релевантно ЛИШЕ якщо SilkenNet матиме EU-establishment/дочірню компанію.
- **Висновок для SilkenNet:** на поточному pre-revenue/early-B2B етапі — DPO **НЕ потрібен** (B2C-акаунти навряд «large-scale systematic monitoring» поки немає реального EU-users бази; не спеціальні категорії даних). Признач внутрішнього «privacy contact» неформально, повернись до питання коли з'явиться реальна EU-масштабна user-база чи EU-юрособа.

### 3.5 🔴 Крайовий кейс: чи є forest-telemetry «персональними даними»?
- Дерево/анкер-телеметрія (growth, EBFC-напруга, GPS) сама по собі — НЕ персональні дані (дерево — не фізична особа). АЛЕ GDPR трактує геолокацію як персональні дані, коли вона МОЖЕ ідентифікувати фізичну особу — і **granular parcel-рівня геолокація, поєднана з land-registry/кадастровими записами власності, теоретично МОЖЕ пере-ідентифікувати конкретного (особливо малого/сімейного) власника лісової ділянки**. Той самий принцип що «smart meter data can reveal who's home».
- **Практичний mitigation, якщо релевантно:** не публікувати/не розкривати сирі high-precision координати анкера, прив'язані до named власника, у жодному B2B data-продукті без (a) агрегації/огрублення локації, АБО (b) lawful basis + контракт/згода з власником ділянки що покриває САМЕ цю обробку.
- Це **не вирішено цим research-pass** — це orientation-прапорець, вартий design-review на боці backend/telemetry-pipeline (де саме зберігається зв'язок anchor↔GPS↔organization/owner) радше ніж юридичного припущення тут. Рекомендація: занести як open item у `docs/00_07`, не вирішувати заднім числом у цьому звіті.

---

## 4. Bottom line — мінімальний набір

### Pre-revenue (немає підписаних B2B-контрактів, немає польових інсталяцій)
Юридично **нічого не є обов'язковим** на етапі solo-founder pre-revenue в Україні (немає employees крім засновника → немає Workers' Comp-тригера; немає board/priced round → немає D&O-мандату; немає живого контракту → немає COI-запиту ще). Дешевий D&O ($2.5–6k/рік promo-прайсинг) іноді береться pre-seed якщо вже є advisor/board-структура чи priced SAFE-раунд з investor-тиском — для чистого solo pre-revenue founder це **відкладається**.

### На тригер-точці «B2B-signing» / перша pilot-інсталяція
Пріоритет придбання (в порядку, не паралельно):

1. **Tech E&O / Professional Liability** — купити ПЕРШИМ. Це поліс що procurement просить «by name», і єдиний що напряму мапиться на core-ризик бізнесу (помилкове «verified fact»-твердження).
2. **Commercial General Liability** ($1M/occ–$2M agg — де-факто ринковий стандарт) з products-completed-operations розширенням — купити ПЕРЕД першою фізичною інсталяцією анкера. Вимагай від арбориста-підрядника ВЛАСНУ GL + додай SilkenNet (і власника ділянки/клієнта, за контрактом) як additional insured — не самострахуй сам акт інсталяції.
3. **Cyber liability** (часто bundled з #1 в один package) — разом із Tech E&O, given email PII + Web3-adjacent high-value target профіль. **Прочитай war/cyber-war exclusion wording рядок-в-рядок** given Ukraine-експозицію (§2.4).
4. **D&O** — відклади до появи board, priced-раунду, чи officer-структури з зовнішніми грошима; це зазвичай НЕ B2B-контрагентський ask (D&O захищає insiders від investors/shareholders, не delivery-risk сертифікат).
5. **Carbon-credit project-рівня reversal/non-delivery cover** (Kita CPPC-типу) — НЕ corporate-поліс, релевантно лише якщо (a) buyer-контракт вимагає, або (b) SilkenNet реєструється під Verra/Gold Standard де «Approved Insurance Policy» — визнана альтернатива buffer-pool методології. Прайсинг ~2–10% від вартості кредиту — трактуй як project/methodology-рішення, не startup-insurance checklist item, повернись на тому ґейті.
6. **DeFi/smart-contract cover** (Nexus Mutual-типу) — спекулятивний nice-to-have, не визнається enterprise-procurement як COI-eligible поліс — пропусти поки on-chain TVL не стане матеріальним.

### Мінімальний DPA-набір
1. Отримай підписаний/click-accepted DPA (з SCC Module 2 C2P annex) від **КОЖНОГО** вендора що торкається EU-персональних даних: cloud-host (у GCP є стандартний), Redis-hosting, RPC-провайдери — **перевір кожного окремо**, не припускай.
2. Опублікуй власну privacy policy що називає Google/Apple як identity-login джерела (не «sub-processors» у сенсі Art.28) + перелічує власний sub-processor ланцюг SilkenNet (general-authorization модель, з change-notification/objection window) для DPA що SilkenNet пропонує СВОЇМ B2B/B2C користувачам.
3. Оскільки SilkenNet — UA-inc і (за умови будь-якого EU user/customer) чітко в Art. 3(2) territorial scope: признач Art. 27 EU-representative щойно EU-users стануть non-occasional/non-trivial — не чекай на штраф як тригер.
4. DPO поки не потрібен; повернись до питання якщо масштаб/EU-дочірня компанія змінить розрахунок.
5. Занеси (не вирішуй тут) landowner-геолокація-пере-ідентифікація крайовий кейс у `docs/00_07` як відкрите compliance-питання для дизайну D-MRV data-продукту.

---

## Sources

- [Climate Change Software Insurance | Embroker](https://www.embroker.com/case-studies/climate-change-software-insurance/)
- [Tech Startup Insurance: 2026 Guide | QuoteSweep](https://www.quotesweep.com/blog/insurance-for-tech-startups)
- [Insurance for Tech Companies: Your Ultimate Guide in 2025 | Unbridled](https://unbridledinsurance.com/insurance-for-tech-companies-your-ultimate-guide-in-2025/)
- [E&O Insurance for Startups | Corgi Insurance](https://www.corgi.insure/blog/tech-eo-insurance-for-startups)
- [Insurtech Kita launches NPI cover | beinsure](https://beinsure.com/news/insurtech-kita-launches-npi-cover/)
- [Kita Expands Carbon Insurance Capacity To $29.1M | carbonherald](https://carbonherald.com/kita-expands-carbon-insurance-capacity-to-29-1m-amid-rising-market-demand/)
- [Kita — Carbon Insurance Products](https://www.kita.earth/whycarboninsurance)
- [Oka Expands Climate Risk Solutions with Green Credit Insurance](https://carboninsurance.co/oka-expands-climate-risk-solutions-with-green-credit-insurance-offering/)
- [Insurers hope new policies covering carbon credits will restore trust | Trellis](https://trellis.net/article/insurers-hope-new-policies-covering-carbon-credits-will-restore-trust-battered-market/)
- [Carbon Credit Insurance: What It Is and When It Makes Sense | Sylvera](https://www.sylvera.com/blog/carbon-credit-insurance)
- [Technology Business Insurance Costs | Insureon](https://www.insureon.com/technology-business-insurance/cost)
- [Tech E&O and Cyber Insurance for Startups: 2025 Guide | WHINS](https://www.whins.com/tech-eo-and-cyber-insurance-for-startups-2025-guide-to-protection-compliance/)
- [Cyber Liability Insurance Cost | TechInsurance](https://www.techinsurance.com/cyber-liability-insurance/cost)
- [Vouch: Directors & Officers Insurance Cost in 2026](https://www.vouch.us/blog/directors-and-officers-insurance-cost)
- [How Much Does D&O Insurance Cost? (2026) | Insura](https://insura.ai/articles/do-insurance-cost-guide)
- [D&O Insurance for Startups 2026 | Beancount.io](https://beancount.io/blog/2026/05/10/directors-officers-d-and-o-insurance-startups-2026-coverage-limits-premium-benchmarks-investors-guide)
- [General Liability Insurance for Contractors | HUB International](https://www.hubinternational.com/blog/2022/01/general-liability-insurance-for-contractors/)
- [Contractor General Liability Insurance Coverage Guide (2026) | Construction Coverage](https://constructioncoverage.com/insurance/general-liability/coverage)
- [Carbon Offsets: A Coming Wave of Litigation? | Quinn Emanuel](https://www.quinnemanuel.com/the-firm/publications/client-alert-carbon-offsets-a-coming-wave-of-litigation/)
- [Carbon Credit Fraud | 5SAH](https://www.5sah.co.uk/knowledge-hub/articles/2026-01-22/carbon-credit-fraud-the-lustre-of-green-gold-continues-to-blind-investors-and-frustrate-prosecutors)
- [Legal challenges in carbon offsetting | green.earth](https://www.green.earth/blog/legal-challenges-in-carbon-offsetting-what-recent-lawsuits-teach-us)
- [Climate and Carbon Litigation Trends | Harvard Law CorpGov](https://corpgov.law.harvard.edu/2025/07/07/climate-and-carbon-litigation-trends/)
- [Mangrove Blue Carbon MRV Liability Insurance Market Research Report (🔴 low-confidence report-mill source)](https://dataintelo.com/report/mangrove-blue-carbon-mrv-liability-insurance-market)
- [Monitoring, reporting and verification (MRV) | Carbon Market Watch](https://carbonmarketwatch.org/glossary/monitoring-reporting-and-verification-mrv/)
- [Arborist & Tree Service Insurance | NIP Group](https://nipgroup.com/business-insurance-programs/tree-service-insurance/)
- [Tree Removal Insurance | ArboStar](https://arbostar.com/education-hub/tree-removal-insurance-what-every-arborist-business-needs)
- [Consulting Foresters | Philadelphia Insurance Companies](https://www.phly.com/products/Foresters)
- [Consulting Foresters Insurance | AssuredPartners](https://www.assuredpartners.com/outdoor-insurance/consulting-foresters-insurance/)
- [Consulting Foresters | Outdoor Underwriters](https://www.outdoorunderwriters.com/consulting_foresters_liability.html)
- [Subprocessors under GDPR | complydog](https://complydog.com/blog/subprocessors)
- [SaaS DPA Requirements | promise.legal](https://blog.promise.legal/startup-central/saas-dpa-requirements-enterprise/)
- [The SaaS DPA Guide | Secure Privacy](https://secureprivacy.ai/blog/data-processing-agreements-dpas-for-saas)
- [Understanding How GDPR Applies to Non-EU Businesses | Pandectes](https://pandectes.io/blog/how-gdpr-applies-to-non-eu-businesses/)
- [GDPR Article 3: Territorial Scope | LegalClarity](https://legalclarity.org/gdpr-article-3-territorial-scope-and-who-it-covers/)
- [EDPB Guidelines 3/2018 on territorial scope (Article 3)](https://www.edpb.europa.eu/sites/default/files/files/file1/edpb_guidelines_3_2018_territorial_scope_after_public_consultation_en_1.pdf)
- [Does the GDPR apply to companies outside of the EU? | GDPR.eu](https://gdpr.eu/companies-outside-of-europe/)
- [GDPR Article 27 Explained | gdprinfo.eu](https://gdprinfo.eu/gdpr-article-27-explained-eu-representative-requirement-for-non-eu-controllers-and-processors-with-practical-examples)
- [GDPR Article 27 EU Representative | Captain Compliance](https://captaincompliance.com/education/gdpr-article-27-eu-representative-requirements-enforcement-and-compliance-steps-for-non-eu-companies/)
- [Startup Guide to Data Protection Officers (DPOs) | Agency Insights](https://blog.getagency.com/articles/startup-dpo-guide)
- [DPO Requirements: Complete 2025 Guide | PrivacyForge.ai](https://www.privacyforge.ai/blog/dpo-requirements-when-you-need-data-protection-officer-complete-2025-guide)
- [Ukraine Data Privacy Laws: Draft Law 8153 and GDPR Reform (2026) | Recording Law](https://www.recordinglaw.com/world-laws/world-data-privacy-laws/ukraine-data-privacy-laws/)
- [Data Protection Laws and Regulations Report 2025-2026 Ukraine | ICLG](https://iclg.com/practice-areas/data-protection-laws-and-regulations/ukraine/)
- [Data protection adequacy for non-EU countries | European Commission](https://commission.europa.eu/law/law-topic/data-protection/international-dimension-data-protection/adequacy-decisions_en)
- [Google Cloud Standard Contractual Clauses](https://cloud.google.com/terms/sccs)
- [GDPR and Google Cloud](https://cloud.google.com/privacy/gdpr)
- [The new Standard Contractual Clauses - A deeper dive | Taylor Wessing](https://www.taylorwessing.com/en/global-data-hub/2021/august---data-transfers-a-clearer-picture/the-new-standard-contractual-clauses)
- [European Court of Justice to Review Challenge to EU-U.S. DPF | WilmerHale](https://www.wilmerhale.com/en/insights/blogs/wilmerhale-privacy-and-cybersecurity-law/20251201-european-court-of-justice-to-review-challenge-to-eu-us-data-privacy-framework)
- [EU-U.S. Data Privacy Framework Survives First Challenge | DLA Piper Privacy Matters](https://privacymatters.dlapiper.com/2025/09/eu-u-s-data-privacy-framework-survives-first-challenge/)
- [Adequacy of the EU-U.S. DPF Survives Challenge | National Law Review](https://natlawreview.com/article/adequacy-eu-us-data-privacy-framework-survives-challenge)
- [Is the EU-US DPF Still Valid? 2026 status | EuropeanMartech](https://europeanmartech.eu/blog/eu-us-data-privacy-framework-2026-status)
- [GNSS & The Law: Collecting and Processing Geolocation Data | Inside GNSS](https://insidegnss.com/gnss-the-law-collecting-and-processing-geolocation-data/)
- [Privacy Research Highlights Difficulties with Anonymization of Location Data | Clarip](https://www.clarip.com/blog/privacy-research-anonymization-location-data/)
- [Protecting business in Ukraine: war risk management and insurance | CMS Law-Now (Dec 2025)](https://cms-lawnow.com/en/ealerts/2025/12/protecting-business-in-ukraine-a-comprehensive-guide-to-war-risk-management-and-insurance)
- [War Risk Insurance in Ukraine: New Government Mechanisms | CEE Legal Matters](https://ceelegalmatters.com/briefings/31771-war-risk-insurance-in-ukraine-new-government-mechanisms-and-market-outlook)
- [War exclusions in cyber policies: an overview | DAC Beachcroft](https://www.dacbeachcroft.com/en/What-we-think/War-exclusions-in-cyber-policies-an-overview)
- [Lloyd's of London announces cyber-attack insurance exclusions | KWM](https://www.kwm.com/global/en/insights/latest-thinking/lloyds-of-london-announces-cyber-attack-insurance-exclusions.html)
- [LMA5567A/B: A 2026 Market Update | Cyber Insurance Academy](https://www.cyberinsuranceacademy.com/blog/guides/lma5567a-b-lloyds-cyber-war-exclusions-2026/)
- [How will the Merck settlement affect the insurance industry? | IBM](https://www.ibm.com/think/insights/merck-settlement-affect-insurance-industry)
- [Merck's $1.4 billion cyberattack claim – the specter of NotPetya | United Policyholders](https://uphelp.org/mercks-1-4-billion-cyberattack-claim-the-specter-of-notpetya/?print=print)
- [Cybersecurity & Insurance Law: Warlike-Action Exclusion & the Merck case | Dakota Digital Review](https://dda.ndus.edu/ddreview/cybersecurity-insurance-law-warlike-action-exclusion-the-merck/)
- [Delaware Flip: Get ready to take US investment | SeedLegals](https://seedlegals.com/grow/delaware-flip/)
- [Flipping Non-U.S. Companies to Delaware C-Corps | Startup Law Review](https://www.startuplawreview.co/index/flipping-non-us-companies-to-delaware-c-corps-a-guide-for-attracting-us-investment)
- [Nexus Mutual: Smart Contract Insurance and NXM Coin — gemini.com](https://www.gemini.com/cryptopedia/nexus-mutual-blockchain-insurance-nxm-crypto)
- [Comparing DeFi Insurance Protocols | DeFi Coverage](https://deficoverage.org/2025/09/19/comparing-defi-insurance-protocols-nexus-mutual-vs-insurace-vs-unslashed/)
- [Registration and Issuance Process v4.1 | Verra](https://verra.org/wp-content/uploads/2022/10/Registration-and-Issuance-Process_v4.1.pdf)
- [Gold Standard And Verra Introduce Insurance Criteria For CORSIA Carbon Credits | carbonherald](https://carbonherald.com/gold-standard-and-verra-introduce-insurance-criteria-for-corsia-carbon-credits/)
- [Average General Liability Insurance Cost (2026 Report) | MoneyGeek](https://www.moneygeek.com/insurance/business/general-liability/cost/)
- [Nico Laqua Launches Crypto D&O Insurance for Web3 Founders | Cointrust](https://www.cointrust.com/market-news/nico-laqua-launches-crypto-do-insurance-for-web3-founders)
- [Understanding Web3 Insurance | Vouch](https://www.vouch.us/blog/understanding-web3-insurance)
- [Insurance Requirements in Enterprise Contracts (2026 Guide) | Alton Risk](https://altonrisk.io/blog/enterprise-contract-insurance-requirements/)
- [Environmental Consultant Insurance | Suited](https://www.suited.insure/business-insurance/environmental-consultants-insurance)
- [Avoiding GDPR fines in 2025: Enforcement trends | Scrut](https://www.scrut.io/hub/gdpr/gdpr-fines-penalties-us-eu-guide)
- [GDPR Fines and Penalties: 2025 Enforcement Guide | complydog](https://complydog.com/blog/gdpr-fines-penalties-2025-enforcement-guide)
- [Complete Guide to Decentralized Cloud Computing (2026) | Fluence](https://www.fluence.network/blog/decentralized-cloud-computing-guide/)
- [AWS Data Processing Addendum (DPA) - Navigating GDPR Compliance on AWS](https://docs.aws.amazon.com/whitepapers/latest/navigating-gdpr-compliance/aws-data-processing-addendum-dpa.html)
- [Infura Collecting MetaMask Users' IP, Ethereum Addresses | Decrypt](https://decrypt.co/115486/infura-collect-metamask-users-ip-ethereum-addresses-after-privacy-policy-update)
- [Alchemy joins ConsenSys and Infura in collecting user's private information | crypto.news](https://crypto.news/alchemy-joins-consensys-and-infura-in-collecting-users-private-information/)
