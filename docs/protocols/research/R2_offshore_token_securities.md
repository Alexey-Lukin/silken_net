# R2 — Offshore Token Structures & Securities-Ризик (SCC/SFC), 2025-2026

> **Що це:** знімок веб-дослідження, зібраний агентом під час §07 legal/business-кампанії. Це **вхідні дані** для артефактів у [`legal/`](../legal/) та [`business/`](../business/), а не самостійне джерело істини.
> **Concern-шар — НЕ канон.** Правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас.
> **⚠️ НЕ верифіковано пофактно.** Кожне твердження потребує перевірки першоджерела перед використанням; це не юридична/податкова/фінансова порада.


**Метод:** public web-research (WebSearch/WebFetch, липень 2026) + verification-read репо-канону (`docs/05_03`, `docs/00_04`, `app/models/user.rb`, `app/models/wallet.rb`) — щоб securities-аналіз ґрунтувався на РЕАЛЬНІЙ токеноміці SilkenNet, не на абстрактній «типовій ICO-схемі».

> **GUARDRAIL:** Це orientation-рівень public-дослідження, **НЕ юридична порада**. Кожне твердження нижче — з джерелом+датою+рівнем впевненості. Перед будь-яким token-launch/fundraise рішенням — реальний юрист (crypto-securities спеціалізація, US+EU+UA).

> **🔴 TOP FINDING (читай перед усім іншим):** Секція 3 знайшла в **самому коді/каноні репо** (не гіпотетично) fact-pattern, що дуже сильно нагадує investment contract — `NaasContract` має роль `User.role = :investor`, поле `total_funding` документоване як «сума **інвестиції**», early-exit fee + prorated refund, і динамічну DEX-ціну SCC. Це підважує токеноміку СЕРЙОЗНІШЕ, ніж вибір офшорної юрисдикції — див. §3.4 і Bottom Line.

---

## 1. Token/Foundation структури Web3

### 1.1 Порівняльна таблиця (2025-2026)

| Структура | Setup-вартість | Річна підтримка | Timeline | Що дає щодо токена | Джерело / дата |
|---|---|---|---|---|---|
| **Swiss Verein (Association)** | Низька (не знайдено точних $-даних у джерелах — типово дешевше за Stiftung, member-based, легша реєстрація) | Невисока | Тижні | Member-based — token holders можуть напряму формувати статути/обирати представників; **найближче до DAO-native governance** серед юридичних форм | [Legalnodes/MME огляд](https://www.mme.ch/en/magazine/articles/switzerland-redefines-the-foundation-era), [Vectra Advisors](https://vectra-advisors.com/token-launch-in-switzerland/) — 2025, Середня впевненість (немає точних cost-цифр) |
| **Swiss/Zug Foundation (Stiftung)** | CHF 15,000–25,000 (+ FINMA-реєстрація → CHF 25,000–40,000 якщо потрібна) | CHF 7,000–12,000+ | 6-10 тижнів (FINMA-ліцензування — 3-6 міс, якщо потрібне) | **CHF 50,000 мінімум dedicated assets**, no-equity-ownership, board ≥1 trustee, кантональний нагляд (Stiftungsaufsicht). Класична форма для «genuinely decentralised protocol governance» | [Ventus](https://ventus.llc/crypto-foundation-setup/), [BlockGuests](https://www.blockguests.com/crypto-valley-zug-overview.html), [my-swiss-company](https://my-swiss-company.com/en/foundations-in-switzerland-and-cryptocurrencies/) — 2025-26, Висока впевненість |
| **Wyoming DAO LLC** | Недорого (точних $ не знайдено; порядок LLC filing fee, не $10k+) | Низька | «як мало 2 тижні» | Limited liability для members; **явно НЕ рекомендується** для «investment DAO» — Legalnodes прямо пише «token (if publicly issued) буде deemed a security by SEC» ризик; підходить для «pure governance DAO», НЕ token-sale vehicle. Потребує ідентифікувати smart-contract public keys ДО інкорпорації (проблема для pre-launch проєктів) | [Legalnodes Wyoming DAO LLC](https://www.legalnodes.com/article/wyoming-dao-llc) — 2025-26, Висока впевненість. Паралельно є новіший **Wyoming DUNA** (2025, Uniswap Foundation приклад) — нонпрофіт-асоціація, легше пасує DAO без token-security claim |
| **Cayman Foundation Company** | ~$6,000-30,000 (одна джерело: ~$6k upfront; інша: $15-30k formation) | ~$5,000-15,000 (комбіновано з BVI) / $8-15k standalone | ~1 тиждень після збору документів (рекомендовано закладати 1-2 міс) | «Orphan structure» — no shareholders; де-факто **industry-стандарт** для DAO/token treasury (1,700+ foundation companies зареєстровано до кінця 2025, +400 лише за 2025 рік) | [Cayman Finance](https://caymanfinance.ky/2025/12/01/cayman-islands-emerges-as-global-hub-for-web3-foundations-with-sharp-rise-in-legal-entity-registrations/) (грудень 2025), [Legalnodes Cayman+BVI](https://www.legalnodes.com/article/cayman-foundation-bvi-company-token-launches) — Висока впевненість |
| **BVI Company / Foundation** | $2,000-4,000 (company) | $1,500-2,500 | Швидко | Просте utility-token issuance — часто **без ліцензії**; токени з «investment characteristics» тригерять SIBA (Securities and Investment Business Act). ICO/ITO НЕ потребує VASP-ліцензії, якщо компанія не надає інших регульованих crypto-послуг | [Consulting24 BVI](https://www.consulting24.co/blog/bvi-crypto-company-costs-broken-down/), [FintechSimple](https://fintechsimple.com/crypto-license/bvi/) — 2026, Середня-Висока впевненість |
| **Estonia OÜ** | Компанія дешева, **АЛЕ CASP-ліцензія (з 2025)** = €100k-250k paid-up capital залежно від послуг | Compliance-важко (AML, local-presence, own-funds) | — | З 1 січня 2025 Естонія перейшла на MiCA-aligned CASP-режим — це вже НЕ дешевий «crypto-friendly OÜ» 2018-2021 років. **Важливо:** CASP-ліцензія потрібна лише для НАДАННЯ crypto-послуг третім особам (custody/exchange/тощо) — просто випуск власного utility-токена власним клієнтам під це НЕ підпадає (Title II, легший whitepaper-режим) | [Hacken Estonia](https://hacken.io/discover/estonia-crypto-license/), [Legarithm](https://legarithm.io/license/crypto/estonia/) — 2025, Висока впевненість |

### 1.2 Dual-entity pattern: «operating company (UA/EU) + token foundation (offshore)»

**Навіщо:**
- **OpCo** (Labs) — Delaware/Wyoming/Estonia/UA — тримає розробників, IP-розробку, клієнтські контракти, платить зарплати; звичайна операційна юрособа.
- **Foundation** (Cayman/BVI/Швейцарія) — «orphan» без акціонерів — тримає токен-treasury, видає гранти, ліцензує IP протоколу, є emitent токена. Розділяє «хто заробляє на успіху проєкту» (OpCo, traceable equity) від «хто керує децентралізованою мережею» (Foundation, no-equity).
- Джерело: [Legalnodes Cayman+BVI](https://www.legalnodes.com/article/cayman-foundation-bvi-company-token-launches), [Chambers Cayman](https://chambers.com/articles/cayman-structures-for-crypto-web3-and-blockchain-entities) — 2025, Висока впевненість.

**Коли доречно:** проєкт вже готовий до **серйозного публічного token distribution / fundraise** — DeFi, L2, GameFi, інфраструктура з реальним token-sale подієм. Explicitly: **NOT для «founders still validating product-market fit»** — цитата з Legalnodes.

**Коли передчасно (застосовано до SilkenNet):**
1. **System TRL = 3** (anchor/EBFC gate, `00_03`) — залізо ще не в TRL4 in-vitro навіть. Реальний production-mint токена «backed by verified biomass growth» на реальному hardware — це роки, не квартали.
2. **Zero юр-осіб зараз** — типовий dual-entity launch (Cayman+BVI за $8.5k-34k setup) розрахований на команду, що вже готова провести token sale цього року. SilkenNet — ні.
3. **DAO governance — «far-horizon»** за власним визначенням задачі. Foundation-як-DAO-дім (Verein/Stiftung/Cayman) вирішує проблему, якої ще немає.
4. Дешевша, миттєво корисна дія — **звичайна операційна юрособа** (UA ТОВ або Estonia OÜ — саме як «operating company», НЕ CASP-ліцензована) для контрактів/інвойсингу/IP-holding (вже узгоджено defensive-publication posture, `00_01 §8`) — це рішення сьогоднішньої, не 2027-28 проблеми.

**Відкрите питання:** жодне джерело не адресує напряму «forest-carbon D-MRV projects» як клас — усі приклади (ENS, Balancer, Uniswap) — DeFi/pure-software протоколи без фізичного активу (anchor/EBFC hardware) і без "Investor"-labeled B2C/B2B revenue-контракту. SilkenNet-специфічний fit — не перевірений жодним джерелом; екстраполяція моя, не задокументований прецедент.

---

## 2. MiCA (Markets in Crypto-Assets)

### 2.1 Стан впровадження 2025-2026 (чинне право, не проєкт)

| Дата | Подія | Джерело |
|---|---|---|
| 30 груд 2024 | Title II/III/IV/V (offer/CASP-регулювання) набрали чинності; transitional regime для CASP, що вже діяли до цієї дати | [Dechert](https://www.dechert.com/knowledge/onpoint/2025/1/application-of-second-part-of-mica---regulation-of-casps-and-oth.html) — січ 2025 |
| 26 лют 2025 | ESMA final guidelines щодо reverse solicitation (набрали чинності +60 днів) | [ESMA guidelines PDF](https://www.esma.europa.eu/sites/default/files/2025-02/ESMA35-1872330276-2030_Guidelines_on_reverse_solicitation_under_MiCA.pdf) — 26.02.2025 |
| до листоп. 2025 | 53+ CASP-ліцензій видано across EU | Кілька джерел, конвергентно — Середня-Висока впевненість |
| до 1 лип 2026 | Deadline для transitional CASPs на повну авторизацію | [Dechert](https://www.dechert.com/knowledge/onpoint/2025/1/application-of-second-part-of-mica---regulation-of-casps-and-oth.html) |
| 2026 (протягом) | ESMA Level 3 guidance щодо «fully decentralized» DAO-виключення (Recital 22) — ще НЕ видано, тест «genuine decentralization» відсутній | [Innreg](https://www.innreg.com/blog/eu-crypto-regulation-guide) — Середня впевненість, **явно in-flux** |

**Висновок:** MiCA Title II-V — це чинне право, не proposal. Але кілька важливих меж (fully-decentralized-виключення, точна ART-vs-utility межа для environmental-referenced токенів) — усе ще Level 3 guidance-in-progress. Флагую in-flux.

### 2.2 Класифікація ART / EMT / utility / other — застосовано до SCC/SFC

| Категорія | MiCA-визначення (стаття) | SCC? | SFC? |
|---|---|---|---|
| **EMT** (E-money token) | Art 3(1)(7) — стабільна вартість, референс до **одної** офіційної валюти | Ні (SCC не має stabilization mechanism, ціна плаває через Uniswap V3 DEX-quote, fallback $25.50) | Ні |
| **ART** (Asset-referenced) | Art 3(1)(6) — «purports to **maintain stable value** by referencing another value or right… or combination» | **Неоднозначно.** SCC технічно НЕ «purports to maintain stable value» — жодного peg'у й жодного цінового механізму в системі немає взагалі (виправлено проти коду 2026-08-26: доти тут стояло «ціна floating, DEX-driven») → формально не ART за буквою. АЛЕ SCC економічно **референсує реальний underlying** (верифікований carbon growth; 2000 SCC = 1 tCO₂ фіксований конверсійний параметр — дзеркало SSOT, дім `00_04 §3` `scc_per_tonne_co2`; KlimaDAO-retirement в `esg_retired_balance`) — це саме той функціональний профіль («референс до value/right»), який ESMA/регулятори схильні перекваліфіковувати. Жодне джерело НЕ адресує carbon-backed non-pegged token напряму — **екстраполяція, не підтверджений прецедент**. Середня-Низька впевненість, **потребує ESMA Token Taxonomy Tool / рахункового висновку юриста** | SFC — чиста governance (ERC20Votes), без referenced value → НЕ ART |
| **Utility token** | Art 3(1)(9) — «intended **solely** to provide access to a good or service supplied by issuer»; негативний тест: не має stable-value механізму, не обіцяє редемпшн за номіналом, не є claim на underlying asset | Лейбл у `05_03` = «Utility Token» — **АЛЕ** див. §3.4: SCC фактично видається В ОБМІН на `total_funding` (гроші) в рамках `NaasContract`, не «просто access to service». Це напружує «solely provide access» тест | SFC = «Governance Token» лейбл; немає revenue-share/dividend/buyback у коді (перевірено — не знайдено жодного механізму розподілу Treasury на SFC-холдерів) → сильніший utility/governance fact-pattern за замовчуванням, АЛЕ теж видається через ту саму `NaasContract`-транзакцію |
| **«Other» (не ART/EMT/utility)** | Title II light regime (whitepaper, no CASP) | Найімовірніша «домашня» категорія ЯКЩО NaaS-investor-фрейм вдасться відокремити від самого токена (див. §3) | Аналогічно |

Джерела класифікаційного тесту: [CSB Group](https://www.csbgroup.com/articles/establishing-the-regulatory-characterisation-of-a-utility-token-under-mica/), [EBA ART/EMT](https://www.eba.europa.eu/regulation-and-policy/asset-referenced-and-e-money-tokens-mica) — 2025, Висока впевненість щодо тесту, Середня щодо застосування до carbon-backed кейсу.

### 2.3 CASP-ліцензія — чи потрібна SilkenNet?

- CASP (Title V) регулює **надання crypto-послуг третім особам**: custody/adminstration, exchange, trading-platform operation, execution, portfolio management тощо (Art 3 + Art 63). Капітал: €50k (advisory) / €125k (custody+exchange) / €150k (trading platform). [AMLBot](https://blog.amlbot.com/mica-license-explained-casp-requirements-authorization-process-and-eu-passporting/) — Висока впевненість.
- **Простий випуск власного токена власним клієнтам — Title II (issuance), НЕ CASP.** Це важлива відмінність — не варто плутати «потрібен MiCA whitepaper» з «потрібна €125k CASP-ліцензія».
- **АЛЕ:** verification-read `app/models/wallet.rb` (коментар) підтверджує — SilkenNet має **custodial-гаманець** концепцію: «Custodial-гаманець (без власної адреси) успадковує статус організації» (`Wallet#kyc_approved_for_minting?`). Це означає: для частини користувачів (без власної on-chain адреси) SilkenNet **тримає/контролює** SCC/SFC від їхнього імені. **Custody and administration of crypto-assets on behalf of clients — окрема ліцензована CASP-послуга** (Art 3+63; «safekeeping… in the form of private cryptographic keys, or exercise of control over crypto-assets on behalf of clients») — [Global Law Experts](https://globallawexperts.com/what-is-the-casp-crypto-asset-service-provider-under-mica-regulation/), [Key2Law](https://key2law.com/en/news/which-services-should-be-licensed-under-mica) — Висока впевненість щодо норми, **Середня щодо застосування** (не перевіряв on-chain custody механіку глибше — чи це «custody-as-a-feature-of-issuance» проти «custody-as-a-service», межа факт-специфічна).
- **Відкрите питання (важливе, не риторичне):** чи custodial-гаманці — це (а) внутрішній bookkeeping до моменту, коли клієнт «claim»-ить власну адресу (issuer-side, не CASP), чи (б) SilkenNet фактично тримає приватні ключі на постійній основі для деякої когорти інвесторів (custody-service, CASP-тригер)? Потребує code-рівня verification окремо від цього research-таску.

### 2.4 Utility-token exemption + whitepaper-вимоги

- Загальне правило (Art 4(1), Title II): жодна публічна пропозиція crypto-активу (не ART/EMT) без **whitepaper** (складений + notified + published).
- **Exemptions (Art 4(2)-(3)):** offer <150 осіб/member-state; сукупно <€1M/12міс по всьому ЄС; тільки qualified investors (MiFID II); **utility tokens, що дають доступ до ВЖЕ ІСНУЮЧИХ товарів/послуг**. Якщо послуга ще не існує на момент офера — whitepaper обов'язковий, і публічна пропозиція обмежена 12 місяцями від публікації.
- **Art 4(4):** жодна з цих exemptions НЕ діє, якщо offeror (або хтось від його імені) **також шукає admission to trading** на платформі.
- Джерело: [a2co](https://a2co.com/utility-token-white-paper-mica/), [ESMA Q&A](https://www.micacryptoalliance.com/news/esma-q-a-on-mica-white-paper-exemptions-and-territorial-scope) — 2025, Висока впевненість щодо загальної структури; точна лейтерінг статей — **звірити з першоджерелом Regulation (EU) 2023/1114 перед формальним поданням**, вторинні джерела дають узгоджену, але не 100%-verbatim картину.
- **Застосовано:** SCC торгується на Uniswap V3 (DEX) з fallback price $25.50 → це **admission to trading**-подібна ситуація (навіть якщо технічно "просто ліквідність на DEX", а не formal listing) → **Art 4(4) exemption-block ризик**: якщо DEX-присутність рахується як «seeking admission to trading», small-offer/utility exemptions відпадають і повний whitepaper (Art 6-9) стає обов'язковим незалежно від розміру офера. Не підтверджено жодним джерелом напряму для DEX-liquidity-vs-formal-listing межі — **флагую як відкрите питання для юриста**, не факт.

### 2.5 Non-EU issuer (UA) → EU investors

- **Reverse solicitation** (client-ініційований контакт) — вузький exemption, НЕ загальний dodge. ESMA guidelines (26.02.2025) суттєво звужують що рахується «client-ініційованим»: будь-який маркетинг/реклама/просування, що досягає EU-клієнтів, вважається solicitation; навіть third-party/affiliate маркетинг має контролюватись; потрібен documented proof, що контакт був виключно client-ініційований. [Goodwin](https://www.goodwinlaw.com/en/insights/publications/2024/02/alerts-practices-ftec-marketing-crypto-assets-to-eu-investors-under-mica), [Clifford Chance PDF](https://www.cliffordchance.com/content/dam/cliffordchance/briefings/2025/01/the-reverse-solicitation-exemption-under-mica.pdf) — Висока впевненість.
- **Критично:** reverse solicitation НЕ звільняє від whitepaper-вимог, якщо EU-інвестор сам звернувся і купив — whitepaper-обов'язок лишається, звільняється лише «активний офер/маркетинг у ЄС».
- **Third-country offeror (Title II, не ART):** НЕ потребує фізичного EU-embodiment — обирає «home Member State» (де вперше пропонує publicly АБО де перша admission-to-trading заявка) і звідти notifies whitepaper. Це м'якше, ніж CASP (Title V, де EU-establishment обов'язковий) або ART (Art 16, EU-establishment обов'язковий). [MiCA Papers Title I](https://micapapers.com/rules/micar/title-1/) — Середня-Висока впевненість.
- **Отже:** якщо SilkenNet (UA, без юрособи) колись почне пропонувати SCC/SFC EU-клієнтам НЕ через reverse-solicitation-вузьке вікно — Title II дозволяє це зробити навіть без EU-компанії, аби була «legal person» (будь-яка, включно з майбутньою UA чи offshore) і обраний home Member State. Але це працює лише якщо SCC залишається в «other/utility», а не ART/MiFID-financial-instrument (§3).

---

## 3. Securities-класифікація — 🔴 НАЙВИЩІ СТАВКИ

### 3.1 Howey test (US) — 2026 SEC/CFTC framework

- Класичний 4-prong тест: (1) інвестиція грошей, (2) common enterprise, (3) очікування прибутку, (4) з зусиль інших. [Wilmerhale](https://www.wilmerhale.com/en/insights/client-alerts/20260324-the-secs-new-framework-for-crypto-assets-under-howey) — Висока впевненість (устояний прецедент з 1946 SEC v. Howey).
- **17 берез 2026** — SEC + CFTC спільний interpretive release: «крипто-актив сам по собі НЕ є цінним папером — **транзакція** є одиницею аналізу», не технічні характеристики токена. 5 категорій digital assets: digital commodities / digital collectibles / digital tools / stablecoins / digital securities (лише останнє — inherently security). [Chapman](https://www.chapman.com/publication-sec-and-cftc-clarify-crypto-asset-taxonomy-and-the-application-of-federal-securities-laws), [Orrick](https://www.orrick.com/en/Insights/2026/04/SEC-Issues-Interpretive-Guidance-on-Crypto-Asset-Classification) — Висока впевненість, **АЛЕ це дуже свіже interpretive guidance (не статут, не суд. рішення) — може змінюватись, і не є обов'язковим для судів**.
- **SEC v. Kik Interactive (2020)** — прецедент з зубами: назва «utility/ecosystem token» НЕ рятує, якщо є (a) pooled funds на єдиному рахунку, (b) management-заяви про майбутнє зростання ціни, (c) integration pre-sale+public-sale в один offering. [DLA Piper](https://www.dlapiper.com/en/insights/publications/2020/10/sec-wins-summary-judgment-that-kin-token-is-a-security) — Висока впевненість, устояний прецедент.
- **Governance-токени:** не автоматично non-security, але revenue-share/staking-yield/buyback механізми різко підвищують ризик («виглядає як акція, що очікує дивіденди»). SFC (§3.4 нижче) — **не має** такого механізму в перевіреному коді → це на користь SFC.

### 3.2 MiCA/MiFID II securities-межа (EU)

- Art 2(4) MiCA: якщо токен = MiFID II «financial instrument» (transferable security, derivative, Annex I Section C) → MiCA **взагалі не застосовується**, натомість повний MiFID II режим (проспект, інвестиційні послуги, ліцензування). Взаємовиключно. [Merkle Science](https://www.merklescience.com/blog/micar-vs-mifid-ii-a-comprehensive-guide-to-eu-crypto-regulations") — Висока впевненість.
- ESMA грудень 2024 final guidelines на «qualification of crypto-assets as financial instruments» — controlling document. Приклад з джерела: «token, що починається як MiCA crypto-asset, може поводитись як MiFID II financial instrument 6 місяців потому» — тобто класифікація НЕ статична, залежить від економічної поведінки в часі.
- **EU ETS carbon allowances (EUA) — вже ЦІННІ ПАПЕРИ за MiFID II** (Annex I Section C(11), явно НЕ commodity derivative) — це стосується лише **compliance market** (EU ETS), НЕ voluntary carbon market, де оперує SilkenNet. Але правовий принцип «carbon instrument = fin. instrument» вже існує в ЄС для суміжного інструменту — прецедентний тиск у той самий бік для VCM-токенів не виключений. [emissions-euets.com](https://www.emissions-euets.com/mifid2-mifir) — Висока впевненість щодо EU ETS факту; Низька-Середня щодо екстраполяції на VCM.

### 3.3 Україна

- **Чинний стан:** «On Virtual Assets» law ухвалено Радою, АЛЕ неактивний до податкових поправок. **Проєкт** № 10225-d (перше читання — 3 верес 2025) — НЕ чинне право, ціль набуття чинності — **1 січня 2027** (текст законопроєкту планують фіналізувати серпень 2026). НКЦПФР (NSSMC) — призначений регулятор, framework «aligned with MiCA». [CoinInsider](https://www.coininsider.com/news/ukraine-aims-to-finalize-crypto-bill-text-in-august-for-january-2027-launch/), [NSSMC офіційно](https://www.nssmc.gov.ua/en/virtualni-aktyvy-v-zakoni-v-ukraini-predstavlenyi-dovhoochikuvanyi-dokument-dlia-zapusku-rynku/) — Висока впевненість щодо статусу «proposal, not law»; Середня щодо точної дати (типово для UA-законодавства — зсуви).
- **Наслідок для SilkenNet:** зараз в Україні НЕМАЄ діючого спеціального virtual-asset regulatory regime — де-факто gray zone, "не заборонено" ≠ "регульовано". Securities-статус SCC/SFC за українським правом контекстуально би йшов через загальне визначення "цінний папір"/"інвестиційний договір" у Законі про ринки капіталу — жодне знайдене джерело не дає точного howey-аналога тесту в чинному УА-праві; це **прогалина в моєму дослідженні**, потребує окремого запиту до UA-юриста ринків капіталу.

### 3.4 🔴 КРИТИЧНА ЗНАХІДКА — grounded у власному коді/каноні SilkenNet

Я перевірив `docs/05_03_Tokenomics_SCC_and_SFC.md`, `docs/00_04_Nature_as_a_Service_Contracts.md`, `app/models/user.rb`, `app/models/wallet.rb` (read-only). Факти:

1. **`NaasContract` — це модель "підписки", де клієнт ("Organization" АБО individual) платить `total_funding` і отримує SCC + SFC.** Документ `00_04` буквально каже: «клієнти... платять за моніторинг лісів і отримують натомість... SCC та... SFC».
2. **RBAC явно містить роль `investor` (`enum :role, { investor: 0, forester: 1, ... }`, `app/models/user.rb`).** Не метафора — literal enum value.
3. **`total_funding`** документовано в `04_01`/`00_04` як **«Загальна сума інвестиції (USDC/USD)»** — слово "інвестиції" в самому каноні, не моя інтерпретація.
4. **Early-exit механіка:** `NaasContract#calculate_early_exit_fee`, `#calculate_prorated_refund` — «Дострокове розірвання (Early Exit **Investor**)» з штрафом і пропорційним поверненням. Це фінансово-інструментальна механіка (схожа на bond early-redemption / fund exit fee), НЕ типова для «купівлі carbon-credit» (carbon credit purchase не має "refund").
5. **B2C track (`00_04 §1.2`)** прямо описує individuals, що хочуть **"монетизувати"** свій ліс: SCC + мікро-USDC-нагороди (0.01-0.0162 USDC/LoRa-пакет) + Celo ReFi (5 cUSD/добу) — DePIN-style "заробіток за участь" fact-pattern (та сама категорія, що привертала SEC-увагу до Helium-подібних мереж).
6. **SCC — вільно передаваний plain ERC-20 без transfer-restriction**, тобто вторинний ринок МОЖЛИВИЙ, і це класичний Howey-фактор («чи є ринок, де токен може зростати в ціні завдяки зусиллям promoter'а»). ⚠️ **Виправлено проти коду 2026-08-26:** доти цей пункт стверджував, що SCC МАЄ floating DEX-ціну (Uniswap V3 Quoter + fallback $25.50 через `PriceOracleService`) — **як as-built факту цього немає**: механізм мав нуль прод-споживачів і знятий разом із governance-ключем, платформа ціну не читає й не публікує. Фактор ослаблений (наша участь у price-discovery = нульова), але **не знятий**: пул може створити третя сторона без нас. Розбір + питання до юриста — [`securities_review.md`](../legal/securities_review.md) F9 та 1.5.13.
7. **SFC — на противагу:** НЕ знайдено жодного revenue-share/dividend/buyback/staking-yield механізму в перевіреному коді. Dynamic Tax (2% від SCC-мінтингу) іде до DAO Treasury (страховий пул), не розподіляється на SFC-холдерів. Це на користь SFC як менш security-подібного інструменту — **АЛЕ** SFC теж видається через ту саму `NaasContract`-транзакцію (гроші → NaaS → SCC+SFC пакетом), тож "чистота" SFC як governance-only легко розмивається bundling'ом з SCC в одній інвестиційній транзакції (courts/SEC інтегрують bundled offerings в один аналіз — саме це сталось у Kik: SAFT+public sale integrated).

**Чому це "найвищі ставки" для securities-аналізу (більше, ніж будь-яка юрисдикція офшору):**

Howey (US) і функціонально аналогічний "фінансовий інструмент" тест у MiFID/EU — обидва питають **не "як називається токен", а "яка економічна транзакція відбувається"** (це буквально нова 2026 SEC-рамка: «transaction is the proper unit of analysis»). Fact-pattern "Organization/individual платить гроші → отримує SCC+SFC → може вийти достроково з штрафом/поверненням → SCC торгується на DEX з ринковою ціною" **вже сьогодні, до вибору будь-якої офшорної юрисдикції**, читається юристом-securities як investment contract candidate, незалежно від того, чи інкорпоруєте ви Cayman Foundation, Estonia OÜ чи нічого. Юрисдикція-шопінг **не лікує** security-shaped transaction — вона лише переміщує, ХТО і ЯК вас регулюватиме за неї.

**Що знижує ризик (за тими самими джерелами §3.1, «як уникнути security-класифікації»):**
- Прибрати "investor"/"total funding as investment"/"refund"/"exit fee" **мовний і продуктовий фрейм** — замінити на "carbon-offset service subscription" без фінансово-інструментальних rollback-механік (a purchase, not an investment note).
- Явно відв'язати SCC-видачу від "money in" (сплата за моніторинг-СЕРВІС, а не "купівля токена як інвестиції") — тонка, але юридично значуща різниця.
- Уникати будь-яких публічних заяв про очікуване зростання ціни SCC/SFC (Kik-урок: co-founder-твіт про token-price = докази проти вас).
- Progressive decentralization для SFC/DAO (менше admin-key control з часом) — знижує "efforts of others"-прогону.
- **Але:** жодна з цих mitigations не є "готовим рішенням" з коробки — потрібен цілісний перегляд `NaasContract`-продукту юристом ДО того, як з'явиться перший реальний "Investor"-платіж.

### 3.5 Суміжні режими, які case-факти теж активують (за межами буквального запиту, але прямо relevant)

- **AIFMD (EU Alternative Investment Fund Managers Directive):** «forestry» explicitly визнаний asset-класом під AIFMD; pooled investor money → managed forestry returns = класичний profile "collective investment scheme". Якщо NaaS-модель залучає багато "Investors", чиї кошти агрегуються в ліс-менеджмент з очікуваним поверненням — це **окрема, незалежна від MiCA regulatory-експозиція** (unauthorized AIF management). [Harneys AIFMD](https://www.harneys.com/funds-hub/resources/aifmd-explained/), [Legalnodes RWA EU](https://www.legalnodes.com/article/rwa-tokenization-in-the-eu-most-suitable-jurisdictions-and-regulatory-frameworks-for-2025-and-beyond) — Середня впевненість (загальний принцип підтверджено, специфічне застосування до SilkenNet — не перевірено жодним джерелом).
- **ECSPR (EU Crowdfunding):** якщо колись NaaS-фандрейзинг піде через публічну платформу (краудфандинг-стиль) — ECSPR кепить $5M/12міс/проєкт і виключає "reward-based"/ICO-токени зі своєї сфери, АЛЕ MiFID-financial-instrument токени під нього таки підпадають. [FIN LAW](https://fin-law.de/en/crypto-assets-and-regulation/crowdfunding-service-providers-according-to-ecspr/) — Середня впевненість.
- Обидва — попереджувальні прапорці, не підтверджені як точно застосовні; потребують юридичного review в контексті реальної go-to-market моделі.

---

## 4. RWA Carbon — правова рамка

### 4.1 ERC-3643 (стандарт токена, не закон)

- Permissioned-token standard (колишній T-REX), затверджений грудень 2023: on-chain KYC/AML, residency-restriction, investor-accreditation-check, pause/freeze. Побудований САМЕ для регульованих securities/RWA — тобто **вибір ERC-3643 замість plain ERC-20 сам по собі сигналізує «ми очікуємо, що це регульований інструмент»** (SilkenNet вже використовує щось подібне — Polygon Hadron ERC-3643 для KYC, per `05_03`). [docs.erc3643.org](https://docs.erc3643.org/erc-3643), [Chainalysis](https://www.chainalysis.com/blog/introduction-to-erc-3643-ethereum-rwa-token-standard/) — Висока впевненість щодо факту стандарту; це технічний стандарт, не сам по собі юридичний висновок.
- **Примітка:** SCC/SFC контракти (`SilkenCarbonCoin.sol`/`SilkenForestCoin.sol`) — за каноном `05_03` — це **звичайний OpenZeppelin ERC-20** (+AccessControl+Pausable+Permit(+Votes для SFC)), НЕ ERC-3643. Hadron ERC-3643 використовується лише як **окремий KYC-registry шар** (`hadron_kyc_status`), не як сам токен-стандарт SCC/SFC. Вартий уваги gap: якщо securities-аналіз (§3) підтвердить security-подібність, сам token-контракт (plain ERC-20) не має вбудованих transfer-restriction-можливостей, які типово вимагаються для legally-compliant security tokens (whitelist-only transfer, forced-transfer за судовим рішенням тощо) — **архітектурний might-need-to-revisit пункт, якщо securities-висновок піде в "так, це security".**

### 4.2 Правовий статус carbon credit самого по собі

| Ринок | Класифікація | Джерело |
|---|---|---|
| **EU ETS (compliance market)** | Emission allowances = **фінансовий інструмент** за MiFID II Annex I §C(11) (явно НЕ commodity derivative — окрема категорія від §C(5)/(6)/(7)/(10)) | [emissions-euets.com](https://www.emissions-euets.com/mifid2-mifir) — Висока впевненість |
| **Voluntary Carbon Market (VCM)** — де оперує SilkenNet | Здебільшого **НЕ фінансовий інструмент** сам по собі, class-by-class аналіз; EU/UK ETS **НЕ визнають tokenized offsets для compliance** (обмежує їх до voluntary/niche use) | [Gibraltar Law/Hassans](https://www.gibraltarlaw.com/insights/post/102lwoz/tokenised-carbon-credits-opportunities-and-key-market-distinctions/), [Lexology](https://www.lexology.com/library/detail.aspx?g=045f5abf-f496-4387-b4cd-b2c37fc11905) — Середня-Висока впевненість |
| **US — CFTC** | Ексклюзивна юрисдикція лише над carbon credit **derivatives/futures** (не spot/forward); anti-fraud authority поширюється й на spot/forward. Жовтень 2024 final guidance для DCM listing voluntary carbon credit derivatives | [CFTC press release](https://www.cftc.gov/PressRoom/PressReleases/8969-24), [Congress.gov CRS](https://www.congress.gov/crs-product/R48095) — Висока впевненість |
| **US — SEC** | Роль здебільшого disclosure-фокусована (ESG), не пряма commodity/security класифікація carbon credit самого по собі; **АЛЕ** якщо carbon credit tokenized-версія продається як investment contract (Howey) — SEC jurisdiction активується через транзакцію, не через сам «carbon credit»-статус | [Norton Rose Fulbright](https://www.nortonrosefulbright.com/en/knowledge/publications/137ce3c4/sec-and-cftc-considerations) — Середня впевненість |
| **Загальний висновок індустрії** | «Наймеш стандартизована категорія» серед tokenized RWA — regulatory gray zone, жоден federal US agency не має comprehensive authority | [FG Capital Advisors](https://www.fgcapitaladvisors.com/5-checks-before-tokenizing-a-carbon-credit-project), [GAO-25-107128](https://www.gao.gov/products/gao-25-107128) — Висока впевненість щодо "gray zone"-констатації |

### 4.3 EU CRCF (Carbon Removals and Carbon Farming Regulation) — новий, прямо relevant для forest-carbon

- **Regulation (EU) 2024/3012** — ухвалено Радою 19 листоп 2024, набрала чинності **9 груд 2024**. Voluntary EU-wide **certification** framework (НЕ trading/securities regulation) для carbon removal / carbon farming / carbon storage-in-products. 4 типи діяльності, включно з "carbon farming" (temporary storage + soil emission reduction) — **forestry explicitly в скоупі**.
- Timeline: перші certification methodologies — 2025-2026; спільний EU registry — не раніше кінця 2028.
- Джерела: [Bellona EU](https://eu.bellona.org/focus-area/carbon-accounting/crcf/), [Climate Action EC](https://climate.ec.europa.eu/eu-action/carbon-removals-and-carbon-farming/carbon-removals-and-carbon-farming-crcf-regulation_en), [Ecologic PDF](https://www.ecologic.eu/sites/default/files/publication/2024/50122-the-eu-carbon-removal-certification-framework.pdf) — Висока впевненість щодо факту й дат.
- **Значення для SilkenNet:** CRCF — це framework для **якості/легітимності самого carbon-removal claim**, окремо від securities/MiCA питань. Якщо SilkenNet колись схоче, щоб SCC визнавався як «сертифікований EU carbon removal» (а не лише власний D-MRV-claim) — CRCF-реєстр (з 2028) буде релевантним шляхом. Це **третій, окремий трек регуляції** (якість claim) поверх securities (§3) і crypto-asset (§2) — жодна з цих трьох осей не замінює інші.

### 4.4 Precedent: Toucan Protocol / KlimaDAO — прямо relevant (SilkenNet вже інтегрує KlimaDAO retirement)

- Toucan/KlimaDAO зазнали серйозної репутаційної та якісної критики (CarbonPlan: «zombie credits» — токенізовані credits від низькоякісних/довго-дормантних проєктів, що не давали реального екологічного ефекту). [CarbonPlan](https://carbonplan.org/research/toucan-crypto-offsets), [Time](https://time.com/6181907/crypto-carbon-credits/) — Висока впевненість щодо факту критики (документована, публічна).
- KLIMA token впав >99% від піку (до ~$0.04 до берез 2026) — критики вказують на speculative bonding-model dynamics, де staking-rewards тиснуть sell-pressure понад carbon-backing fundamentals. [огляд ринку](https://coinpaprika.com/education/tokenized-carbon-credits-toucan-protocol-and-klimadao-guide/) — Середня впевненість (ринкові дані, не строго "правова" знахідка, але **репутаційно-правовий ризик**: green-washing/consumer-protection allegations типово йдуть за market collapse наративом).
- В США tokenized carbon credits (Toucan/KlimaDAO типу) розглядаються радше під CFTC (commodities), не SEC — АЛЕ це для "чистого" carbon-credit-token без investment-contract-обгортки; SilkenNet's NaaS-bundling (§3.4) робить прямий précédent-паралель неповним.
- **Відкрите й нез'ясоване питання (важливе):** SCC — це claim на **власний, SilkenNet-internal D-MRV-verified** carbon growth, чи це bridged/wrapped claim на **third-party-registry-issued** credit (Verra/Gold Standard/Puro.earth)? З канону видно чітку third-party-registry інтеграцію ЛИШЕ для post-mortem biomass (Puro.earth Biochar CORC через `PuroEarthPassportWorker`) — САМЕ growing-tree SCC-мінтинг виглядає як **власний, не-registry-issued** claim, лише пізніше «ретайрметься» через KlimaDAO-облік. Якщо це вірно — SCC НЕ успадковує Toucan/Klima-специфічний "zombie credit" ризик (бо це не bridged зовнішній credit), АЛЕ й НЕ має third-party-registry legitimacy, яку B2B ESG-клієнти зазвичай вимагають (слабший value-prop, окреме бізнес-питання, не суто правове). **Я не можу підтвердити це зі 100% впевненістю без глибшого code-read за межами цього research-скоупу** — рекомендую окремо перевірити з командою.

---

## Bottom Line

**1. Securities-ризик SCC/SFC: ВИСОКИЙ і НЕ гіпотетичний.** Це не «токен міг би теоретично бути security, якщо погано структурувати». Сам канон (`docs/00_04`, `docs/05_03`) вже описує продукт мовою інвестиційного контракту: RBAC-роль `investor`, поле "сума інвестиції", early-exit fee + prorated refund, floating DEX-ціна. Це — до будь-якого вибору юрисдикції — fact-pattern, який Howey-тест (US) і функціонально паралельний MiFID/AIFMD-аналіз (EU) читають як candidate investment contract / collective investment scheme. SFC (чисте governance, без revenue-share) виглядає безпечніше саме по собі, АЛЕ bundling з SCC в одній `NaasContract`-транзакції (гроші → пакет SCC+SFC) імпортує SCC-ризик і на SFC (Kik-урок: integrated offerings аналізуються разом).

**2. Чи потрібен token-foundation зараз, чи Phase-2: однозначно Phase-2 — і не лише через TRL3-hardware-gate.** Офшорна фундація (Cayman/BVI/Swiss) вирішує питання «де юридично сидить treasury/emitent», але **не вирішує і не пом'якшує** securities-питання з п.1 — це ортогональні проблеми. Витрачати $8.5k-34k+ і місяці на dual-entity structure ЗАРАЗ, коли (а) hardware ще TRL3 (анкер/EBFC — жодного реального Proof-of-Growth-мінтингу на реальному дереві найближчим часом), (б) NaaS-продукт-дизайн сам по собі має нерозв'язане securities-питання, (в) DAO governance — заявлено far-horizon — це classic «premature canon» за вашою ж YAGNI-драбинкою (CLAUDE.md §4): будуєте дорогу юридичну інфраструктуру під токен, чия базова інвестиційно-контрактна форма ще не пройшла навіть первинний securities-review.

**Що натомість доречно Phase-1 (дешевше, і вирішує сьогоднішню, а не 2027-28 проблему):**
- Проста операційна юрособа (UA ТОВ або Estonia OÜ як OpCo — **не CASP-ліцензована**, просто для контрактів/інвойсингу/IP-holding) — не token-emitent, окреме питання від крипто-структури.
- **Один платний sit-down з crypto-securities юристом (US + EU, і, за можливості, UA capital-markets) на конкретний NaaS-контракт "as-built"**, не на абстрактну «чи SCC utility» — саме тому, що §3.4-знахідка показує: проблема сидить у ПРОДУКТОВОМУ дизайні (investor-role, refund-механіка, bundled SCC+SFC-видача-за-гроші), а не в токен-лейблінгу. Дешевше й важливіше зараз виправити продукт (мова контракту, розв'язати "money-in" від "token-out", прибрати refund/exit-fee фінансову механіку АБО свідомо прийняти security-статус і структуруватись під нього з самого початку) — ніж пізніше переробляти й ретроактивно захищати вже випущені токени.
- Офшорна token foundation → відкласти до моменту, коли є (a) реальний TRL4+ hardware і перший реальний mainnet-mint horizon, (б) securities-питання з продукту вирішене (redesign АБО усвідомлений compliance-шлях), (в) конкретний, не «far-horizon», DAO-запуск.

**Впевненість підсумку:** Висока щодо «securities-ризик реальний і grounded у власному коді» (це не web-джерело, а прямий read репо). Середня щодо «яка саме офшорна структура була б правильною, коли прийде час» (indústry-стандартні патерни задокументовані добре, але жодне джерело не адресує forest-hardware-D-MRV-специфіку). Explicit gaps: точний Ukraine capital-markets-law Howey-аналог (не знайдено), чи custodial-гаманці = CASP-custody-тригер (потрібен code-level review), чи SCC bridged на third-party carbon registry чи повністю proprietary (потрібен code-level review).
