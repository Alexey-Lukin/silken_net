# Web3/Token + Open-Source Enterprise Best-Practices — Gap-Analysis

> **Що це:** best-practices gap-analysis token-launch legal (securities-safe design, MiCA, TGE/foundation-governance) + open-source-compliance (SPDX/REUSE, SBOM/CRA, DCO, AGPL-монетизація) — web-research 2025-26 проти нашого стану; вхід для founder'а та UNI.16-консультації.
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — UNI.20 (DCO) / BIZ.24 (SBOM/CRA); суміжні BIZ.22 · UNI.16 · BIZ.20 · UNI.3; DOC-T.47 — закритий.

**Дата:** 2026-07-24 · **Тип:** best-practices gap-analysis (web-research 2025-26 + наші артефакти), **НЕ юридична порада**
**Вхідні артефакти:** [`entity_structure`](../legal/entity_structure.md) (token-контур/фази) · [`securities_review`](../legal/securities_review.md) (securities fact-pattern F1–F15) · [`trademark_brief`](../legal/trademark_brief.md) · [`R2_offshore_token_securities`](../research/R2_offshore_token_securities.md) · [`R5_trademark_ip`](../research/R5_trademark_ip.md)
**Трекер-прив'язки:** 🔴 **BIZ.22** (securities-fact-pattern у коді) · **UNI.20** (ВНЗ-contribution-governance, DCO) · **BIZ.24** (SBOM / EU CRA) · ✅ **DOC-T.47** (contracts = MIT — ратифіковано 2026-07-24) · UNI.16 · BIZ.20 · UNI.3 · BIZ.15

**Phase-легенда:** 🟢 = зараз (Phase-1, pre-token, дешево) · 🟡 = token-launch-gate (Phase-2, gated на UNI.16-консультацію + mint-horizon + TRL4+, за [`entity_structure`](../legal/entity_structure.md) §3.3) · ⚪ = later (Phase-3 / far-horizon)

---

## 0. Головна теза

Enterprise-credible **та** securities-safe одночасно — це не компроміс, а один вектор: усі 2025-26 best-practices (SEC/CFTC framework, MiCA, Token Transparency Framework, OpenSSF, CRA) сходяться на **«substance over form + verifiable transparency»**. Наша сильна сторона — чесний TRL, відкриті ліцензії, formal-verification контрактів (Halmos/Medusa) — уже в цьому векторі. Наша діра — **продуктова механіка NaaS написана мовою і механікою інвестиційного контракту (BIZ.22)**, що є прямою інверсією securities-safe design-патернів. Найдешевше вікно redesign — зараз, до першого live-mint (контракти ще не задеплоєні, UNI.16). Open-source-половина (SPDX/SBOM/DCO) — низька вартість, робиться 🟢 зараз і незалежно від token-фаз.

---

## 1. Token-launch legal best-practices

### 1.1 Securities-safe token-design (US, 2025-26) — 🔴 ПРЯМО ПРО BIZ.22

Стан поля:
- **SEC Division of Corporation Finance statement (10 квіт 2025)** — disclosure-вимоги для crypto asset securities; **SEC+CFTC joint interpretive release (17 бер 2026)**: «транзакція, не токен — одиниця аналізу»; 5 категорій digital assets ([Cointelegraph 2025](https://cointelegraph.com/explained/secs-2025-guidance-what-tokens-are-and-arent-securities), [Astraea Counsel 2025](https://astraea.law/insights/token-launch-legal-checklist-sec-compliance-2025), R2 §3.1).
- **«Utility-label irrelevant»** — суди/SEC дивляться на economic reality, не назву ([Promise Legal](https://blog.promise.legal/howey-test-founders-token-security/); Kik-прецедент, R2 §3.1).
- Канонічні design-патерни уникнення security-класифікації ([StartSmart Counsel](https://www.startsmartcounsel.com/resource-center/understanding-when-tokens-are-not-securities-a-legal-guide-to-utility-tokens), [Legalnodes utility-token guide](https://www.legalnodes.com/article/utility-token-launch-legal-guide), 2025):
  1. **Consumptive-use-only продаж** — токен продається для використання у застосунку, не як інвестиція;
  2. **No-profit-expectation messaging** — жодних заяв про зростання ціни, у жодному каналі (Kik-твіт-урок);
  3. **Функціональність існує на момент продажу** (не «купіть зараз — мережа потім»);
  4. **Decentralization / зниження issuer-контролю** з часом (прогон «efforts of others»);
  5. **Записаний Howey-аналіз + legal opinion** у файлах компанії;
  6. Review усіх публічних комунікацій + geofencing за потреби.

**Gap проти нашого стану:** as-built fact-pattern (code-verified, F1–F15) **систематично інвертує патерни 1–2 — самою механікою, не маркетингом**: redemption/refund-механіка, common-enterprise pooling і profit-expectation-канали, яких немає в «купівлі carbon-credit». Повна securities-мапа з code-sites — One-Home: [`00_07`](../../00_07_Action_Plan_Tracker.md) **BIZ.22** + [`securities_review`](../legal/securities_review.md); тут не дублюється.

**Best-practice-висновок для BIZ.22 (integration, не нове рішення):** 2025-26 стандарт індустрії — **redesign до першого live-mint** — саме те вікно, в якому ми зараз (контракти code-complete, не задеплоєні, UNI.16). Мінімальний securities-safe пакет за best-practices, який має оцінити юрист ([`securities_review`](../legal/securities_review.md) Блок 1.5, питання 9–15):
- перейменування F1/F3/F4 — потрібне, але **недостатнє** (label-фікс без механіки = Kik-пастка);
- **прибрати refund/exit-fee (F5/F6/F10)** — найдешевший високоефективний хід (purchase не має refund);
- **розв'язати money-in↔token-out** (SCC = оплата за D-MRV-сервіс, не «інвестиція в токен») і **SCC↔SFC bundling** (F13);
- yield-метод (F7) → нейтральна назва/семантика («emission_progress», прогрес постачання сервісу);
- **«no-price-talk» — настанова для нас уже зараз:** уникати інвест-мови в будь-яких публічних доках і комунікаціях (Kik-урок стосується і doc-сторінок, не лише твітів).

🟢 **Зараз:** BIZ.22-redesign (мова + механіка) — трекається; ця секція дає йому industry-обґрунтування. 🟡 **Gate:** фінальний call redesign-vs-compliance = UNI.16-консультація (наш research не замінює її).

### 1.2 MiCA whitepaper (Art. 6) — 🟡 token-launch-gate

- **Title II:** будь-який offer to the public / admission to trading в ЄС ⇒ whitepaper drawn up + notified + published; **machine-readable format**, table of contents; зміст: issuer identity, проєкт/milestones/use of funds, права й обов'язки токена, технологія, ризики (market/tech/legal), governance ([Legal Bison 2026](https://legalbison.com/blog/mica-white-paper-requirements/), [a2co](https://a2co.com/utility-token-white-paper-mica/), [White & Case](https://www.whitecase.com/insight-alert/mica-regulation-new-regulatory-framework-crypto-assets-issuers-and-crypto-asset), 2025-26).
- **Exemptions (Art 4):** <150 осіб/member-state · <€1M/12міс · qualified-investors-only · utility для **вже існуючих** товарів/послуг. **Art 4(4):** якщо offeror шукає admission to trading — exemptions відпадають; чи DEX-ліквідність = «admission to trading» — відкрите питання (R2 §2.4; [`securities_review`](../legal/securities_review.md) Блок 3.3).
- Enforcement уже живий: ESMA/NCAs де-лістять non-compliant токени ([Paul Hastings 2025-26](https://www.paulhastings.com/insights/client-alerts/mica-crypto-white-papers-comply-or-be-de-listed)).

**Gap:** whitepaper-обов'язок активується лише при EU-офері (Phase-2, third-country-issuer path — [`entity_structure`](../legal/entity_structure.md) §3.4). **Дешевий 🟢-крок уже зараз:** будувати doc-дисципліну так, щоб канон-доки мапилися на Art. 6-розділи (issuer/tech/risks/governance) — у нас SSOT-культура вже це вміє; окремий whitepaper не пишемо (premature), але «risk-розділ чесних ризиків» — те, що і TRL-честність вимагає.

### 1.3 Pre-launch instruments (SAFT vs SAFE+token-warrant) — 🟡

2025-26 консенсус: **SAFT — «за звичкою, не за fit»** — імпортує невирішений securities-ризик; для проєктів з незафіналеною токеномікою — **SAFE + token warrant / token side letter** (продаж права купівлі, не pre-sale токена; гнучкіше ціноутворення, чистіша securities-позиція) ([Promise Legal SAFT-vs-SAFE](https://blog.promise.legal/saft-vs-safe-web3-pre-token-funding/), [Legalnodes SAFT-guide](https://www.legalnodes.com/template/simple-agreement-for-future-tokens), [LegalVision](https://legalvision.com.au/safts-vs-token-warrants/), 2025-26).

**Gap:** ми не фандрейзимо токеном зараз (і не повинні — BIZ.22 нерозв'язаний). Якщо Phase-2 включить залучення капіталу: **не тягнутися до SAFT рефлекторно**; SAFE+warrant — сучасніший дефолт, рішення з юристом. ⚪ до появи fundraise-наміру.

### 1.4 TGE-governance best-practices — 🟡

Індустрійний стандарт 2025-26 ([TokenMinds TGE-checklist](https://tokenminds.co/content/tge-token-generation-event-checklist), [Tokenomics.com vesting-guide](https://tokenomics.com/articles/token-vesting-complete-guide-to-vesting-schedules-cliffs-and-unlock-mechanisms), [Bitbond](https://www.bitbond.com/resources/token-generation-event-tge-guide), 2025-26):
- lockup 12–36 міс.; консервативний unlock **5–15% на TGE**; vesting on-chain (контракти vesting/lockup/claim), role-separation, deployment runbook;
- **зовнішній аудит = передумова серйозного market-access** («audit readiness before serious market access», 2026);
- fair-launch / LBP / tiered sales з anti-bot;
- **Blockworks Token Transparency Framework (18 черв 2025):** 18 disclosure-критеріїв (entity structure, insider allocations, market-maker agreements, listing terms, buybacks); Transparency Alliance = 40+ фірм (Coinbase/Kraken/Binance.US); 44 протоколи вже filed; SEC Crypto Task Force зустрічалась із Blockworks/Jito 13 черв 2025 ([CoinDesk, трав 2026](https://www.coindesk.com/markets/2026/05/27/crypto-s-biggest-exchanges-back-push-for-token-disclosure-standards-as-industry-courts-institutional-capital), [Coincu 2026](https://coincu.com/analysis/deep-analysis/2026-crypto-investor-relations-token-transparency-report/)).

**Наш стан:** технічний фундамент **уже enterprise-grade** — MAX_SUPPLY-інваріанти, розділені MINTER/SLASHER-ключі, Halmos-symbolic + Medusa-fuzz + invariant-тести merge-required (CLAUDE.md §8; [`05_03`](../../05_03_Tokenomics_SCC_and_SFC.md)) — це рівно те, що «audit readiness» вимагає, і сильний козир. **Gap:** allocation/vesting/unlock-календаря не існує (токеноміка розподілу не фіналізована) — і за best-practice **insider-allocation не слід фіксувати до securities-розв'язки (UNI.16)**: передчасна фіксація робить майбутній redesign дорожчим. 🟡 на TGE-фазі: зовнішній аудит + Transparency-filing як credibility-мінімум. ⚠️ Guardrail: TTF-filing — це **disclosure-мова для інвесторів**; застосовувати лише якщо UNI.16-шлях = «свідомий security/compliance», інакше воно суперечить no-investment-messaging.

---

## 2. Foundation-governance best-practices — 🟡/⚪

Що робить token-foundation credible (2025-26): [Legalnodes Cayman-DAO](https://www.legalnodes.com/article/caymanian-foundation-for-dao), [Cavenwell](https://cavenwell.io/insights/cayman-islands-dao-foundation-the-premier-choice-for-dao-legal-structures), [Bolder Group](https://boldergroup.com/resources/blogs/why-a-cayman-foundation-is-the-premier-legal-wrapper-for-your-dao/), R2 §1:

| Практика | Зміст |
|---|---|
| **Orphan-структура** | Cayman Foundation Company без shareholders (1,700+ на кінець 2025, R2 §1.1) — розводить «хто заробляє» (OpCo) від «хто керує мережею» (Foundation) |
| **Council + Supervisor** | Council (виконує; може бути multisig-backed) + Foundation Supervisor/guardian (наглядає, що Council не йде проти волі token-holders) — вбудований checks-and-balances |
| **Treasury multi-sig** | Multisig-кастодія treasury, asset segregation від операційних коштів, диверсифікація |
| **Register-синхронізація** | Реєстр members ↔ beneficiaries; приватний, але ведеться |
| **Transparency-reporting** | Періодичні звіти: treasury composition, allocation, unlock-календар, governance authority (див. §1.4 TTF) |
| Альтернативи | Swiss Verein (member-based, DAO-native governance) · Wyoming **DUNA** (2025, прецедент Uniswap Foundation) — для pure-governance, НЕ token-sale vehicle (R2 §1.1) |

**Gap:** жодного gap **зараз** — Phase-2/3-карта в [`entity_structure`](../legal/entity_structure.md) §2–3 уже відповідає цим стандартам (Cayman #5 дефолт, тригери §3.3, послідовність «securities-консультація ПЕРЕДУЄ офшору» §3.2). Best-practice-додаток до матриці: коли Phase-2 активується — закладати **Supervisor-роль і treasury-multisig у bylaws з першого дня** (це і є «credible foundation» проти shell-компанії), і публічний transparency-report-ритм. До того — ⚪, не будувати.

---

## 3. Open-source-compliance enterprise — 🟢 (наша найдешевша credibility-зона)

### 3.1 SPDX per-file headers + REUSE — 🟢, прив'язка UNI.3 (DOC-T.47 ✅ закрито)

- **REUSE spec (FSFE)** — індустрійний стандарт machine-readable licensing: SPDX-header у кожному файлі + `LICENSES/` + `reuse lint`; «SPDX is the rock upon which REUSE is built»; REUSE-compliant репо різко спрощує downstream-scanning (ORT прямо це каже) ([reuse.software/comparison](https://reuse.software/comparison/), [SPDX tools](https://spdx.dev/tools/open-source-tools/), 2025).
- Наш стан: ✅ **виконано 2026-07** — per-file SPDX по всьому source-дереву; двигун `scripts/spdx_headers.rb`, його ж `--check` = **HARD-гейт** ([`00_06 §3`](../../00_06_SSOT_Documentation_Standard.md)). Скоуп, названі стелі й причина кожного виключення — шапка скрипта (дім, бо не розходиться з кодом). Зонні винятки ратифіковано DOC-T.47 (`contracts`=MIT · `tools/cad/src|tests`=AGPL · `tools/cad/extern`=Apache-submodule) → [`00_07`](../../00_07_Action_Plan_Tracker.md) UNI.3.
- ✅ **DOC-T.47 — license-drift ЗАКРИТО (ратифіковано 2026-07-24):** доки казали «contracts (Solidity) = AGPL», код = MIT (100% contracts-дерева) — **web-research вердикт «КОД ПРАВИЙ, ДОКИ ВІДСТАЛИ» підтверджено ратифікацією**: `/NOTICE` + ліцензійна матриця [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) тепер вирівняні (contracts = MIT, per-file SPDX). Обґрунтування, чому MIT на смартконтрактах — industry-стандарт (лишається тут як research-слід): (1) **composability** — core design-principle контрактів; copyleft-контракт отруює інтеграцію (кожен протокол, що будує поверх, мусив би copyleft-итись → ніхто не інтегрує); (2) наші контракти імпортують OpenZeppelin (MIT) — консистентність дерева; (3) Solidity-компілятор + verify/audit-tooling (Etherscan-verification, аналізатори) очікують SPDX-ідентифікатор і найкраще працюють із permissive ([Solidity docs — SPDX](https://docs.soliditylang.org/en/latest/contracts.html), [SPDX-in-Solidity огляди](https://medium.com/@Oseokhale/understanding-spdx-license-in-solidity-b903e47ebbfc), 2025). Додатковий AGPL-нюанс on-chain: чи deployed bytecode = «conveying» і чи взаємодія з контрактом = §13-network-interaction — юридично невизначені зони; MIT їх знімає повністю. Копілефт-периметр НЕ страждає: рів = AGPL на Rails/firmware/tooling + ™; контракти — публічний інтерфейс, їх форкабельність = feature (DePIN-довіра), не втрата.
- 🟢 **Зараз (дешева частина):** (а) ✅ DOC-T.47 — закрито; (б) ✅ scope-присуд ухвалено; (в) ✅ mass-кампанія виконана — per-дерево, з гейтом після кожного дерева. REUSE lint як CI-advisory — після кампанії, не до.

### 3.2 SBOM + EU CRA — 🟢 почати, 🟡 hard-обов'язок; прив'язка **BIZ.24**

Факти ([Anchore EU-CRA](https://anchore.com/sbom/eu-cra/), [Keysight countdown](https://www.keysight.com/blogs/en/tech/nwvs/2025/09/11/one-year-countdown-to-eu-cra-compliance-september-11-2026-changes-everything), [Mend.io CRA-guide](https://www.mend.io/blog/eu-cra-compliance-guide/), [LPI — CRA & Open Source, вер 2025](https://www.lpi.org/blog/2025/09/09/the-cyber-resilience-act-and-open-source/), 2025-26):
- CRA чинний з 10 груд 2024; **vulnerability/incident-reporting з 11 вер 2026 (24-год вікно!)**; повний compliance (включно з formal SBOM у technical documentation) — **11 груд 2027**. Практично SBOM потрібен ДО вересня 2026, бо component-visibility — передумова 24h-reporting.
- **Скоуп:** «products with digital elements» placed on the EU market. **Некомерційний FOSS — exempt** (нуль комерційної активності); комерційна активність (paid support, premium, business-entity-involvement) знімає виняток; «**open-source steward**» (юрособа, що sustained-підтримує OSS-розробку — типово foundation) = полегшений режим, але не нульовий.
- **Наша специфіка (несуча):** CRA б'є нас не як SaaS (чистий SaaS — це NIS2-територія), а як **hardware-manufacturer: Soldier/Queen + firmware = класичний «product with digital elements»** (→ [`00_07`](../../00_07_Action_Plan_Tracker.md) **BIZ.24**; канон-дім [`02_06 §8`](../../02_06_Unit_Economics_and_BOM.md) + [`02_01`](../../02_01_Hardware_Architecture_and_BOM.md)). Продаж/поставка анкерів+сенсорів на EU-ринок = full manufacturer-obligations (SBOM, secure-by-default, vuln-handling, CE-marking процес).
- **Фаза:** зараз — pre-revenue open-source R&D → exempt. Перший EU-B2B-контракт з поставкою заліза (або комерційний SaaS-supply з firmware-компонентом) → CRA-годинник вмикається. Дія 🟢 зараз (бо дешево і enterprise-очікувано незалежно від CRA): **SBOM у CI**. Частина вже стоїть — image-SBOM генерується в CI (mirror-ghcr; вхід Trivy-скану, `00_07` OPS.10); residual = **повний multi-lock SBOM** (CycloneDX/SPDX-формат з усіх маніфестів: Gemfile.lock, package-lock/importmap, conda-lock, git submodules `firmware/extern`, forge/npm у contracts) — це 🤖-чекбокс BIZ.24. Один workflow-job, нуль рантайм-ризику. Полиця «SBOM є» — це те, що enterprise-procurement 2025-26 питає ДО того, як спитає CRA.
- 🟡 На Phase-2/EU-market: SBOM-у-tech-doc + 24h-vuln-процес + рішення manufacturer-vs-steward (залежить від entity-розкладки BIZ.20: хто «placing on market» — operational-vehicle? token-co? — питання в юр-workshop).

### 3.3 License-scanning + OpenSSF — 🟢

- **Scanning-драбинка** ([Aikido top-scanners 2025](https://www.aikido.dev/blog/top-open-source-license-scanners), [REUSE comparison](https://reuse.software/comparison/), [AppSec Santa 2026](https://appsecsanta.com/sca-tools/open-source-license-compliance)): для нашого масштабу — **ScanCode** (безкоштовний backbone compliance-програм) point-in-time + **ORT** лише якщо захочемо повний policy-pipeline (ORT сам каже: REUSE-compliance спершу — тоді ORT тривіальний); **FOSSA/Black Duck** — комерційні, для нас overkill зараз. Порядок: SPDX-кампанія (3.1) → SBOM (3.2) → ScanCode-verify → (⚪) ORT-policy.
- **OpenSSF: ✅ обидва рівні вже стоять** (не «додати», а «тримати»): **Best Practices Badge silver — earned 2026-06-25** (динамічна плашка README + [`00_00`](../../00_00_SSOT_Index.md) авто-рендер; → `00_07` OPS.10), і **Scorecard GitHub Action уже працює** (weekly + push `main`, SARIF у Security-tab + публічний бейдж — [`06_07 §1`](../../06_07_CICD_and_Runbook_Index.md)); Badge й Scorecard — компліментарні, не дубль; **OpenSSF Security Baseline (бер 2025)** — новий синтез Badge+Scorecard+CLOMonitor ([ossf/scorecard](https://github.com/ossf/scorecard), [ossf/best-practices-badge](https://github.com/ossf/best-practices-badge), [InfoQ, бер 2025](https://www.infoq.com/news/2025/03/openssf-security-baseline/)). **Residual (свідома стеля):** ⚪ **gold** — вимагає ≥2 maintainers (bus-factor >1), solo-founder структурно не проходить; не цілимо (той самий присуд у OPS.10). CONTRIBUTING/DCO (§4) підсилює contribution-policy-вісь незалежно від бейджів.

---

## 4. CLA/DCO contribution-governance — 🟢, прив'язка **UNI.20** (ВНЗ)

Стан поля 2025-26 — консенсус зсунувся до DCO:
- **CNCF:** вимагає CLA або DCO, **рекомендує DCO** («unless strong necessity») ([cncf/foundation#130](https://github.com/cncf/foundation/issues/130)); **OpenInfra Foundation: офіційний перехід CLA→DCO з 1 лип 2025** ([openinfra.org/dco](https://openinfra.org/dco/)); Linux kernel = походження DCO; **Nextcloud (AGPL!) = DCO-only** — прямий прецедент нашої ліцензії (R5 §5.2); GitLab теж мігрував CLA→DCO.
- Tooling: `git commit -s` + GitHub App **`dcoapp/app`** або **`cncf/dco2`** — блокує merge без sign-off; нуль paperwork, нуль архіву угод ([FINOS CLAs-and-DCOs](https://osr.finos.org/docs/bok/artifacts/clas-and-dcos), [Hypertext Dispatches, квіт 2026](https://tenthirtyam.org/dispatches/2026/04/08/dco-vs-cla-managing-contribution-agreements-in-open-source/)).

**Рекомендація для нас — DCO, з двома чесними застереженнями:**

1. **ВНЗ-flag (ядро UNI.20):** DCO студента-фізособи покриває **вільні PR**; НЕ обов'язково покриває контрибуції в контексті **формального ЧНУ-гранту/thesis/supervised-роботи** — там UA-режим службових творів може дати інституційну claim ЧНУ (R5 §5.3; UA-норми не досліджені — proxy з US-policies). Тому: у будь-який майбутній ЧНУ-MoU — **явний IP-пункт про студентські контрибуції окремо від DCO** (уже питання до юр-workshop — [`securities_review`](../legal/securities_review.md) Блок 4.4). Зараз тиску немає (ЧНУ-канал пасивний, MoU unsigned, UNI.18 archived) — але пункт має лежати готовим у MoU-шаблоні ДО підписання.
2. **Dual-licensing-tension (несуча, майже ніде не проговорюється явно):** комерційна dual-license поверх AGPL (§5) вимагає, щоб licensor мав **повні права на весь релліцензований код**. DCO лишає copyright у контриб'юторів → зовнішні DCO-контрибуції **не можна** включити в комерційну ліцензію без згоди авторів. Саме тому dual-license-компанії (MongoDB історично, Grafana Labs) тримають **CLA**, а Nextcloud (DCO) — монетизує підпискою/послугами, НЕ dual-license. Для нас це не блокер: ядро = 100% founder-copyright (solo, [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md); [`securities_review`](../legal/securities_review.md) Блок 4.3 standing), зовнішні контрибуції будуть рідкі й периферійні → DCO зараз, а якщо Phase-2 обере dual-license-монетизацію — вона реалізовна на founder-owned ядрі; масовий зовнішній contribution-потік (не наш кейс) вимагав би перегляду в бік легкого license-grant-CLA. Свідома стеля, познач у CONTRIBUTING.

✅ **Зроблено (2026-07-25):** `CONTRIBUTING.md` §DCO + enforcement (🤖-чекбокс [`00_07`](../../00_07_Action_Plan_Tracker.md) UNI.20). Реалізовано **власним** гейтом, а не `dcoapp/app`, який радив цей огляд — обидві причини (org-install із write-скоупом на публічному репо · author-match-дефолт стороннього App ламається на Dependabot) живуть у шапці `scripts/dco_check.rb`, вона ж і дім. ✅ `DCO passed` у `required_status_checks` з 2026-07-25 (звірено проти GitHub API, не з канону).

---

## 5. AGPL-commercial best-practices — 🟢 підтвердження пози, 🟡 механіка

Патерн-поле ([Grafana relicense-to-AGPL](https://grafana.com/blog/grafana-loki-tempo-relicensing-to-agplv3/), [Grafana licensing](https://grafana.com/licensing/), [Monetizely AGPL-vs-MIT](https://www.getmonetizely.com/articles/should-you-license-your-open-source-saas-under-agpl-or-mit-a-decision-guide-for-founders), [Viprasol OSS business models](https://viprasol.com/blog/open-source-business-model/), 2025-26; R5 §4.4):
- AGPL + комерція — доведений патерн: Grafana/Loki/Tempo (Apache→AGPL relicense саме для монетизаційного важеля), Mattermost, Bitwarden, Nextcloud, MongoDB (історично). Чотири моделі: **open-core** (платні enterprise-фічі), **dual-license** («хочеш закритий форк — купи ліцензію»; вимагає consolidated copyright → §4 tension), **hosted SaaS** (наша модель), **support-контракти**.
- AGPL працює **як комерційний захист**: конкурент може захостити форк, але зобов'язаний публікувати всі свої модифікації (§13) — усуває proprietary-fork-перевагу.
- Наш головний §13-нюанс (R5 §4.2; [`securities_review`](../legal/securities_review.md) Блок 5.1): обов'язок розкриття modified Corresponding Source **власному B2B-клієнту** (privacy деплою не звільняє); «як далеко по ланцюгу users» — in-flux, питання юристу. Ключі/production-дані/ваги/™ — легітимно поза Corresponding Source (R5 §4.3): постава «код відкритий, ключі/дані/бренд утримуємо» внутрішньо несуперечлива.

**Gap:** наша ліцензійна постава (AGPL + CERN-OHL-S + CC-BY-SA + ™-рів + defensive publication — [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)) — **уже best-practice-aligned**; це підтвердження, не зміна. Дві дії: 🟢 у майбутній MSA-шаблон (BIZ.2; counterparty = operational-vehicle) — пункт про AGPL-природу платформи (клієнт знає right-to-source ДО підписання — знімає найбільший комерційний сюрприз §13); 🟡 вибір монетизаційної механіки поверх AGPL (open-core межа: що enterprise-only — напр. приватні аналітичні модулі; чи dual-license) — Phase-2-рішення разом із entity (BIZ.20) і пам'ятаючи §4-tension.

---

## 6. Зведена gap-матриця (стандарт × наш стан × phase-gate)

| # | Best-practice (джерело) | Наш стан | Gap-дія | Фаза | Трекер |
|---|---|---|---|---|---|
| 1 | Consumptive-use design, no-refund/no-yield механіка, no-investment-мова (SEC/CFTC 2025-26, Kik) | 🔴 інверсія патернів у самій механіці коду — повна мапа One-Home: BIZ.22 + [`securities_review`](../legal/securities_review.md) | Product-redesign ДО live-mint; фінал = юрист | 🟢 (вікно найдешевше зараз) | **BIZ.22**/UNI.16 |
| 2 | Записаний Howey-аналіз + legal opinion у файлах | Fact-pattern dossier готовий ([`securities_review`](../legal/securities_review.md)) | Провести платну консультацію → opinion on file | 🟢→🟡 (гейт усього token-контуру) | UNI.16 |
| 3 | MiCA Art. 6 whitepaper (machine-readable) / Art. 4 exemptions | Немає (і не треба ще) | Лише при EU-офері; DEX-vs-admission — питання юристу | 🟡 | UNI.16 Блок 3 |
| 4 | SAFE+token-warrant замість SAFT | Не фандрейзимо | Не тягнутись до SAFT за звичкою | 🟡/⚪ | BIZ.20 |
| 5 | TGE: vesting 12-36міс, unlock 5-15%, зовнішній аудит, Transparency-filing (Blockworks TTF 2025) | Formal-verification вже є (Halmos/Medusa, merge-required) ✅; allocation не фіксована (правильно!) | Аудит + vesting-контракти + disclosure на TGE; allocation НЕ фіксувати до UNI.16-розв'язки | 🟡 | BIZ.20 |
| 6 | Foundation: orphan + Council/Supervisor + treasury-multisig + transparency-reports (Cayman-стандарт) | Карта Phase-2/3 готова ([`entity_structure`](../legal/entity_structure.md) §2–3) ✅ | При активації — Supervisor+multisig у bylaws з дня 1 | 🟡/⚪ | BIZ.20 |
| 7 | REUSE/SPDX per-file headers | ✅ **виконано** — per-file SPDX по source-дереву + HARD-гейт `spdx_headers.rb --check`; зонні винятки ратифіковано (DOC-T.47) | — | ✅ | UNI.3 |
| 8 | Ліцензійна карта доків = коду | ✅ **ЗАКРИТО** (ратифіковано 2026-07-24): `/NOTICE` + [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) вирівняні — contracts = MIT (industry-правильно: composability/tooling/OZ) | — (зроблено) | ✅ | DOC-T.47 (closed) |
| 9 | SBOM у CI (CycloneDX/SPDX); CRA: reporting 2026-09-11, full 2027-12-11 | Image-SBOM у CI вже є (mirror-ghcr, OPS.10); повного multi-lock SBOM нема; зараз CRA-exempt (некомерційний FOSS); Soldier/Queen = майбутній «product with digital elements» | Multi-lock SBOM-CI-job зараз; manufacturer-процеси — при EU-market-вході | 🟢 старт / 🟡 hard | **BIZ.24** |
| 10 | OpenSSF Scorecard + Best Practices Badge (Baseline 2025) | ✅ Badge **silver earned 2026-06-25**; Scorecard Action live (weekly, публічний бейдж — [`06_07 §1`](../../06_07_CICD_and_Runbook_Index.md)); SHA-pin, branch-protection, fuzzing стоять | — (стоїть; тримати). Residual ⚪ gold — gated bus-factor >1, свідомо не цілимо | ✅/⚪ | OPS.10 |
| 11 | DCO + enforcement-bot (CNCF/OpenInfra 2025-консенсус; Nextcloud-AGPL-прецедент) | ✅ `CONTRIBUTING.md` §DCO + enforcement власним гейтом (`scripts/dco_check.rb` у `dco.yml`) | ✅ required-контекст із 2026-07-25; лишився ВНЗ-MoU IP-пункт | 🟢 | **UNI.20** |
| 12 | AGPL-монетизація: open-core/dual-license/hosted (Grafana-патерн) | Постава aligned ✅; MSA ще немає | AGPL-пункт у MSA-шаблон; механіка монетизації — Phase-2 | 🟢 пункт / 🟡 механіка | BIZ.2/BIZ.20 |

---

## 7. Пріоритети

**🟢 ЗАРАЗ (Phase-1, усе дешеве, нічого не гейтиться токеном):**
1. **BIZ.22-redesign** — найвищий пріоритет усього списку: інверсувати мову + refund/exit-fee/yield-механіку поки контракти не задеплоєні (мапа → [`securities_review`](../legal/securities_review.md)); «no-price-talk» у публічних доках — настанова вже зараз.
2. ✅ **DOC-T.47 — закрито 2026-07-24** (contracts = MIT ратифіковано; `/NOTICE` + [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) вирівняні) — знято зі списку.
3. ✅ **DCO — зроблено 2026-07-25:** `CONTRIBUTING.md` §DCO + власний гейт `dco.yml` (не `dcoapp`, причина — §4). Флип branch-protection ✅ зроблено 2026-07-25; лишається ВНЗ-MoU IP-пункт (= UNI.20).
4. **Multi-lock SBOM-CI-job** (CycloneDX/SPDX з lock-файлів; BIZ.24 🤖-half — image-SBOM уже є, OPS.10). Scorecard-action ✅ уже live — дій не потребує.
5. UNI.16-консультація = гейт-подія, що відкриває все 🟡.

**🟡 TOKEN-LAUNCH-GATE (Phase-2, лише після UNI.16 + mint-horizon + TRL4+):** MiCA-whitepaper (або exemption-стратегія) · Cayman Foundation з Supervisor+multisig+bylaws · зовнішній контракт-аудит + vesting/lockup-контракти + transparency-disclosure · SAFE+warrant (якщо fundraise) · CASP-аналіз custodial · CRA-manufacturer-процеси при EU-hardware-market (BIZ.24).

**⚪ LATER:** progressive decentralization/DAO (Phase-3) · ORT-policy-pipeline · OpenSSF gold (bus-factor >1) · continuous transparency-filings.

**Наскрізний guardrail:** усі token-🟡-практики виконувати ЛИШЕ в порядку [`entity_structure`](../legal/entity_structure.md) §3.2 — securities-консультація передує будь-якій структурі/whitepaper/TGE; жодна foundation/юрисдикція не лікує security-shaped транзакцію (R2 Bottom Line). Best-practices §1.1 — це і Є механізм зробити транзакцію не-security-shaped.
