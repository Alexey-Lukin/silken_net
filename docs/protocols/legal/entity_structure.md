# Entity-структура SilkenNet — фазована драбина юр-форми (BIZ.20)

> **Що це:** матеріал для структурного рішення й вхід у платний юр-review — фазована драбина юр-форми SilkenNet (operational-vehicle / IP-owner / token-контур) плюс матриця опцій «коли знадобиться окрема або token-структура».
> **Concern-шар** (як [`procurement/`](../procurement/rfq_registry.md) / [`paper/`](../paper/self_review_checklist.md)) — **НЕ канон**: усе тут — робоча чернетка й вказівники на канон; правити факт у його домі ([`00_06 §2`](../../00_06_SSOT_Documentation_Standard.md)), не тут.
> **⏳ Станом на 2026-07-24.** Спирається на зовнішнє право/ринок, що рухається незалежно від нас — перед використанням звіряй актуальність.
> **⚠️ Не юридична / податкова / фінансова порада.** Робочий вхід у платну консультацію з фахівцем, не її заміна.
> **Дім стану:** [`00_07`](../../00_07_Action_Plan_Tracker.md) — **BIZ.20** (+ похідні BIZ.15 / BIZ.22 / UNI.14 / UNI.16).

---

> ## ⚠️ СТАТУС ДОКУМЕНТА: МАТЕРІАЛ ДЛЯ РІШЕННЯ + ЮР-REVIEW — НЕ юридична порада
>
> Це **entity-option matrix** (🤖-половина BIZ.20, [`00_07`](../../00_07_Action_Plan_Tracker.md) — «чернетка entity-option matrix → живить рішення»), призначена (а) підтримати структурне рішення founder'а й (б) стати вхідним матеріалом для платного юр-review (Аблязов Д.Е. / крипто-юрист TBD — UNI.14/UNI.16). Це **НЕ** юридична/податкова порада й не заміна консультації.
>
> **Джерела фактів:** [`R1_ua_legal.md`](../research/R1_ua_legal.md) (UA entity/tax) · [`R2_offshore_token_securities.md`](../research/R2_offshore_token_securities.md) (offshore/token/securities) · [`securities_review`](securities_review.md) (securities fact-pattern, code-verified) · [`tax_posture_ua`](tax_posture_ua.md) (tax + open-q token-емісія). Усі «як воно є» — з посиланням на R#/memo/код + рівнем впевненості; усі «як це кваліфікує право» — **відкриті питання для юриста**.
>
> **🔑 НЕСУЧІ ВХІДНІ ФАКТИ (вхід, не висновок):**
> - SilkenNet розміщується під **operational-vehicle** — **наявною UA-компанією, Дія.City-резидентом, співзасновником якої є founder** (тришар-присуд канонізовано: [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md), [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.20). Нової інкорпорації не потрібно.
> - Operational-vehicle — **multi-founder** компанія: founder є одним зі співзасновників, не єдиним власником. SilkenNet — **mission-first SOLO-проєкт** founder'а.
> - 🔴 **НЕСУЧИЙ НАСЛІДОК:** «під operational-vehicle» коректно **лише** якщо розвести **operational-vehicle** (так) від **IP/value-owner** (ні — титул лишається на фізособі founder'а). Ця вісь — центральна для всієї матриці (§1.2).
> - Founder особисто = **ФОП** (персональний-дохід-канал **+ IP/trademark-holder**, НЕ токен — п.291.5 ПКУ).
>
> **Канон:** [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) (BIZ.15 SPV, RWA, MSA/KYC open-items) · [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) (IP-постава: copyright/™ на фізособу) + [`00_02 §5`](../../00_02_Academic_Integration_and_IP.md) (бренд-архітектура) · [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.20/BIZ.15/UNI.14/UNI.16/UNI.15/BIZ.2/BIZ.21.

---

## 0. Головна теза (одним абзацом)

**Phase-1 (зараз): SilkenNet = R&D-продукт-лінія ПІД наявним operational-vehicle** — миттєво дає named counterparty для MSA/грантів, liability-щит під anchor-install, готову операційну інфраструктуру **і пільговий Дія.City-режим для dev-роботи**, не витрачаючи ані копійки на нову структуру. **АЛЕ IP/value SilkenNet лишається на фізособі founder'а, НЕ в operational-vehicle** — бо operational-vehicle multi-founder, а SilkenNet solo-mission; межа титулу має бути однозначною для обох сторін. **Phase-2 (gated): токен-емісія (SCC/SFC) виноситься в ОКРЕМИЙ контур** (offshore token-co), бо (а) UA-юрособа не може чисто емітувати+банкувати токен [R1 §2/§4, [`tax_posture_ua`](tax_posture_ua.md) open-q b], і (б) токен несе securities-ризик ([`securities_review`](securities_review.md), R2 §3.4), який **не варто вносити в діючу multi-founder операційну компанію**. Ключова послідовність: **спершу securities-консультація ([`securities_review`](securities_review.md)), потім — якщо потрібно — offshore-структура** (юрисдикція-шопінг не лікує security-shaped transaction — R2 Bottom Line).

**Дві незалежні осі (несуче — не плутати):**

| Ось | Питання | Phase-1-відповідь |
|---|---|---|
| **Operational-vehicle** | хто робить dev, підписує MSA, білінгує, дає liability-щит + Дія.City-режим | **Наявна UA-компанія** ✅ (multi-founder shell — це ОК для operations) |
| **IP / value-owner** | хто володіє IP + ™ + цінністю місії SilkenNet | **Фізособа founder'а** ✅ (solo-mission; НЕ спільна особа) |

**Драбина (bird's-eye):**

| Фаза | Тригер | Дія | Вартість |
|---|---|---|---|
| **Phase-1** | ЗАРАЗ (2026, R&D-пілот) | SilkenNet operational-під-наявним vehicle; IP+™ на фізособі; ФОП = персональний дохід | ≈0 (структура існує) |
| **Phase-2** | securities-консультація вирішена **+** перший revenue/mint horizon **+** TRL4+ | Offshore token-co (емісія SCC/SFC) + SPV-міст (BIZ.15) | $8–34k+ setup |
| **Phase-3** | далекий горизонт (DAO launch, [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) DAO-governance) | Foundation-as-DAO (Swiss Verein/Cayman) | залежить від форми |

**Don't gold-plate:** Phase-2/3 нижче — **інформаційна карта «коли/як»**, а НЕ «зробити зараз». Зараз робиться лише Phase-1-мінімум (§5).

---

## 1. PHASE-1 — SilkenNet під наявним operational-vehicle (зараз, 2026)

### 1.1 Форма розміщення: продукт-лінія / R&D-проєкт operational-vehicle (НЕ нова юрособа)

SilkenNet розміщується як **внутрішня R&D-продукт-лінія** наявної компанії (operational), а не окрема зареєстрована особа. Обґрунтування:

- **Найдешевша дія, що вирішує сьогоднішню проблему** (BIZ.20-core: «немає операційної юр-особи → undefined MSA/grant/trademark counterparty») — operational-vehicle **уже є** цією особою. Нова ТОВ дублювала б наявну структуру (YAGNI-драбинка, `CLAUDE.md §4`; R2 §1.2 «дешевша, миттєво корисна дія — звичайна операційна юрособа»).
- **Готовий пільговий vehicle:** operational-vehicle — резидент Дія.City → SilkenNet-dev-робота через нього одразу в пільговому режимі, і кваліфікаційні передумови резидентства несе сам vehicle (0 маржинального навантаження для SilkenNet). Деталі §1.6.
- **Консистентно з наявною mint-guard-архітектурою.** Модель «організація-of-record як KYC-якір» уже вшита в код: за custodial-minting-периметром [KYC.1] (`Wallet#kyc_approved_for_minting?`; гейт-канон [`05_02`](../../05_02_Proof_of_Growth_Pipeline.md)) custodial-гаманці **успадковують `organizations.hadron_kyc_status`**, і seed-фікстура демо-організації в `db/seeds.rb` ([`04_01 §8`](../../04_01_Data_Models_and_Entities.md)) уже несе `hadron_kyc_status: "approved"` + `crypto_public_address`. Рішення «operational-під-vehicle» **не потребує code-змін**.
  > ⚠️ Точність: seed — **демо-фікстура для розробки**, а не юридичний факт про будь-яку реальну компанію; збіг імені seed-org із реальною компанією — окремий відкритий ⚖️ у [`msa_skeleton`](msa_skeleton.md), тут не вирішується.
- **Застереження — це operational, НЕ ownership.** Розміщення dev-роботи в operational-vehicle НЕ означає, що він володіє SilkenNet-IP. Ця відмінність — §1.2.

### 1.2 🔴 ДВІ ОСІ: operational-vehicle ⊥ IP/value-owner

Operational-vehicle — **multi-founder** компанія (founder = співзасновник, не єдиний власник). Тому «під operational-vehicle» треба розкласти на дві **незалежні** осі, інакше титул на solo-mission SilkenNet лишається невизначеним.

| Ось | Що містить | Носій Phase-1 | Чому |
|---|---|---|---|
| **Operational-vehicle** | dev-робота, MSA-підпис, білінг/інвойсинг, liability-щит, Дія.City-режим, KYC-org-anchor | **Наявна UA-компанія** | Shell-послуги — саме те, для чого операційна компанія існує; multi-founder тут нешкідливо |
| **IP / value-owner** | copyright на код (`SilkenNet::Attractor`, `bio_contract.rb`…), trademark (SilkenNet™/GaiaNexus™/SCC™), governance/treasury-токеноміка, «цінність місії» | **Фізособа founder'а** | SilkenNet = solo-mission → титул має жити в особи, що несе місію; спільна особа зробила б власність на місію неоднозначною |

**🔴 Ризик, який знімає структурування:** без явного оформлення діє **мовчазний default** — режим «службового твору» / work-product за загальним правилом. Тоді титул на SilkenNet-IP стає **двозначним для обох сторін**: ані founder не має чистої власності для Phase-2, ані operational-vehicle не має безспірної підстави використовувати IP у delivery. Це суперечить канонізованій поставі ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) — copyright на фізособу «Oleksii Lukin»; `/NOTICE`).

**Механізм розведення (Phase-1) — стандартна двостороння IP-структурна практика:**
- Copyright + trademark **папіряться на фізособу founder'а** (не assignment у компанію).
- Operational-vehicle отримує **чистий, безспірний license-back** (операційна ліцензія / service-arrangement) на використання IP для delivery — достатній за scope, без двозначності щодо того, що саме йому дозволено.
- Dev-робота «через operational-vehicle» (Дія.City gig-контракти) — ОК **за умови**, що work-product/IP-authorship явно закріплено за founder'ом (carve-out у gig-договорі), а не лишено на default.

**⚖️ IP-РОЗВИЛКА (founder-рішення, потребує паперу):** оформити **явну двосторонню домовленість**, що SilkenNet — окрема власність founder'а (IP-carve-out / not-a-company-asset) з чистим license-back компанії. Це:
- **не 🤖-питання** — це рішення + документ (carve-out clause, corporate consent) → **юр-review** ([`securities_review`](securities_review.md) Блок 4.5);
- **гейт** перед тим, як будь-який SilkenNet-IP торкнеться балансу/репозиторіїв компанії;
- дешево **зараз** (проста угода), дорого **ретроактивно** (розплутувати неоднозначний титул після появи цінності/токена) — і виграють **обидві** сторони: компанія отримує визначеність щодо того, чим вона вправі користуватися, founder — чистий титул.

### 1.3 Operational-vehicle як counterparty — розкладка ролей

| Роль / артефакт | Хто | Обґрунтування · джерело |
|---|---|---|
| **MSA counterparty** (BIZ.2) | **Operational-vehicle** | MSA потребує named legal person ([`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md), [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.2). Готовий підписант із liability-щитом. **Розблоковує BIZ.2**. |
| **Грант-заявник** | **Operational-vehicle** (юрособа-грант) АБО **фізособа** (персональний грант) — обидва живі | Юрособа-заявник = liability-щит + інституційна довіра + можливий неоподаткований режим для бюджетних/МТД-грантів [R1 §5]. ⚠️ Якщо грант фінансує SilkenNet-IP-створення → узгодити з §1.2 (deliverable-IP → founder). Персональний грант на фізособу — [R1 §5], [`tax_posture_ua`](tax_posture_ua.md) Q1.3. **Вибір per-grant.** |
| **Trademark-заявник** (UNI.15) | **Фізособа (Oleksii Lukin)** | **Три причини сходяться:** (1) ™ у спільній компанії робить титул на бренд-рів неоднозначним (§1.2); (2) R1 §3/R5 — ™ на фізособу переживає ліквідацію/продаж, переходить у спадок; (3) уже ⚖️-default у UNI.15. |
| **IP / copyright holder** | **Фізособа (Oleksii Lukin)**, license-back компанії для операцій | **Три причини:** (1) однозначність титулу solo-mission (§1.2); (2) `/NOTICE` уже вестить copyright на фізособу, [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) пілар 2 — copyright заради enforcement копілефту (AGPL); (3) єдиний copyright-holder = standing to enforce ([`securities_review`](securities_review.md) Блок 4.3). License-back, НЕ assignment. |
| **Anchor-install liability-щит** | **Operational-vehicle** | Неінкорпорований founder ніс би «втручання в держмайно» особисто. Під юрособою — обмежена відповідальність. **Phase-1-виграш.** (E&O-поліс BIZ.21 — юрисдикція UA за operational-vehicle → [`eo_insurance_spec`](../business/eo_insurance_spec.md).) |
| **ФОП founder'а** | персональний-дохід + IP-holder-«фізособа» | Персональний дохід (гранти-фізособі, консалтинг). Носій IP/™ (як фізособа). **ФОП ВИКЛЮЧЕНИЙ для крипто** (п.291.5) → ФОП НЕ тримає й не емітує токен. |

### 1.4 Що Phase-1 ВИРІШУЄ

- ✅ Named MSA/grant/trademark counterparty (BIZ.20-core) → **розблоковує BIZ.2, UNI.15, частину BIZ.11**.
- ✅ Liability-щит під anchor-install (кримінальна/цивільна exposure зникає з фізособи).
- ✅ Готова операційна інфраструктура + **пільговий Дія.City-режим для dev одразу** (vehicle уже резидент).
- ✅ Інституційна довіра діючої компанії для climate-грантів/B2B.
- ✅ Консистентно з кодом (KYC.1 org-anchor).
- ✅ **Solo-mission-ownership однозначне** — IP+™ на фізособі (§1.2).

### 1.5 Що Phase-1 НЕ вирішує (→ Phase-2 / окремий папір)

- ❌ **Токен-емісія (SCC/SFC) + банкування виручки.** UA-юрособа не має чистого банк-channel для крипто-виручки (НБУ №14); пряма практика емісії юрособою **не підтверджена** [R1 §2/§4, [`tax_posture_ua`](tax_posture_ua.md) open-q b]. **Окремий контур** (§3), незалежно від Дія.City.
- ❌ **Securities-ізоляція.** NaaS-fact-pattern уже збігається з пронгами investment-contract-тесту ([`securities_review`](securities_review.md) F1–F13). Розміщення під operational-vehicle **не лікує** securities-питання (ортогональне до вибору особи — R2 §3.4). **Навпаки:** тримати securities-ризиковий токен у діючій **multi-founder** операційній компанії = імпорт регуляторного + банк-freeze + репутаційного ризику у спільне ядро → **аргумент за винесення** (§3).
- ❌ **IP-carve-out папір** (§1.2 ⚖️) — «під operational-vehicle» без оформленої межі = двозначний титул. **Закрити явною угодою ДО того, як IP торкнеться контуру компанії.**
- ❌ **Carbon-SPV** (fiat-to-retirement, BIZ.15) — окремий vehicle (§4).

### 1.6 Дія.City-режим operational-vehicle — наслідки для нас

Operational-vehicle — резидент Дія.City. Що це означає для operational-половини SilkenNet:

| Ось | Значення для SilkenNet |
|---|---|
| **Режим для dev-роботи** | Пільговий gig-режим резидента доступний одразу; конкретні ставки/режими — дім [`tax_posture_ua`](tax_posture_ua.md), тут не дублюємо (One-Home) |
| **Кваліфікаційні передумови резидентства** | Несе сам operational-vehicle → для SilkenNet **0 маржинального навантаження** (нічого не треба будувати чи підтримувати з нуля) |
| **Наявний перелік кваліфікованих видів діяльності** | IT/hardware/data-дохід SilkenNet — **ймовірно** кваліфікований (VASP + «виробництво обладнання для вимірювання» обидва в переліку [R1 §1]) |
| **🔴 90%-тест кваліфікованого доходу** | **Реальний гейт, не гіпотеза** — резидентство живе вже сьогодні. Чи carbon/token-виручка = кваліфікований дохід — **ВІДКРИТО** ([R1 open-q a], [`tax_posture_ua`](tax_posture_ua.md)). **Треба звірити вплив token/carbon-виручки на кваліфікований дохід operational-vehicle** ДО того, як такий потік стане матеріальним → [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.20 (звірка з фаховим обліковцем, UNI.14) |

> **Подвійний висновок:** carbon/token-виручку тримаємо **окремо** від operational-vehicle з **двох** незалежних причин одразу — (1) не змінювати профіль кваліфікованого доходу вже-живого резидента без попередньої фахової звірки, (2) однозначна межа титулу на solo-mission-value (§1.2). Обидві вказують в один бік: **operational-dev у vehicle (пільгово), але carbon/token/IP-value — окремо.**

---

## 2. ENTITY-MATRIX — осі для КОЛИ треба окрема / token-структура

> Карта опцій для Phase-2/3 — **коли** знадобиться окрема/token-структура, а не «зареєструвати зараз». Вартості — orientation-рівень [R1/R2] станом на дату документа, 🟡 MEDIUM (вторинні джерела; реальна ціна для UA-профілю варіює). Колонка **IP-owner** нагадує вісь §1.2 (де осідає value).

| # | Юрисдикція / форма | Тип / роль | Setup | Річна | IP/value-owner | Token/securities-ізоляція | MiCA / CASP-fit | Фаза |
|---|---|---|---|---|---|---|---|---|
| **1** | **Наявний operational-vehicle** (UA, Дія.City-резидент) | Operational-shell (dev, hardware, software, NaaS-сервіс, MSA, білінг) — пільговий режим | **0** (існує) | Пільговий режим резидента (ставки → [`tax_posture_ua`](tax_posture_ua.md)) | ⚠️ **multi-founder** → титул SilkenNet-IP лишається на фізособі | ❌ токен не емітує; ⚠️ вплив carbon/token-виручки на кваліфікований дохід — звірити (§1.6) | VASP у переліку, але не token-emitter path | **NOW** |
| **2** | **Фізособа founder'а (+ ФОП)** | IP/trademark-holder + персональний дохід | 0 | ФОП-режим (не крипто) | ✅ **solo** — SilkenNet-IP + ™ тут | ❌ крипто виключено (п.291.5) | N/A | **NOW** (IP/™-шар) |
| **3** | **Нова UA ТОВ** (SilkenNet-dedicated) | Окрема операційна дочка (якщо треба відділити від наявного vehicle) | Держреєстрація безкоштовна; ~300–1000 грн друк [R1 §3] | 18% | ✅ solo можливо | ⚠️ частково (окрема особа, АЛЕ UA → банк-проблема лишається) | N/A | Phase-2 (ймовірно НЕ треба — дублює shell) |
| **4** | **Estonia OÜ** (operating/IP, НЕ CASP) | EU-операційна / IP-holding / інвойсинг у ЄС | Компанія дешева | Помірна (без CASP) | ✅ solo можливо (EU IP-holdco) | ⚠️ краще (EU, Title II issuance доступний) | Issuer Title II (легкий whitepaper); **CASP €100–250k лише якщо крипто-послуги 3-м особам** [R2 §1.1] | Phase-2 (лише якщо EU-присутність/passporting треба) |
| **5** | **Cayman Foundation Company** | Token-emitent + treasury (orphan, no shareholders) | ~$6–30k [R2 §1.1] | ~$8–15k | orphan (no-equity) | ✅ **YES** — industry-стандарт token-co | Third-country Title II issuer можливий (обрати home MS) [R2 §2.5] | **Phase-2 (gated)** |
| **6** | **BVI Company / Foundation** | Token-emitent (простіший/дешевший) | ~$2–4k [R2 §1.1] | ~$1.5–2.5k | company/orphan | ✅ **YES** | ICO/ITO без VASP-ліцензії, якщо нема інших крипто-послуг; SIBA-тригер при «investment characteristics» [R2 §1.1] | **Phase-2 (gated)** |
| **7** | **Swiss Verein / Zug Stiftung** | Foundation-as-DAO governance home | Verein низька; Stiftung CHF 15–25k+ (CHF 50k min активів) | CHF 7–12k+ | orphan/member | ✅ YES + DAO-native governance | Класична форма «genuinely decentralised protocol» [R2 §1.1] | **Phase-3** (DAO launch) |
| **8** | **Wyoming DAO LLC / DUNA** | DAO legal-wrapper (US) | Недорого | Низька | members | ⚠️ «token if publicly issued → deemed security by SEC»-ризик; для pure-governance, НЕ token-sale [R2 §1.1] | Не для token-sale vehicle | Phase-3 (лише pure-governance DAO) |

**Двоособовий патерн (Phase-2), якщо/коли токен активується** [R2 §1.2]: **operational-vehicle (UA opco)** — розробники, delivery, зарплати (пільговий Дія.City) **+ offshore Foundation (#5/#6)** — token-treasury, емісія, ліцензування протоколу (orphan). IP-value протоколу ліцензується від founder-фізособи, НЕ від operational-vehicle (§1.2).
> ⚠️ **Флаг [R1 §3 open-q, [`tax_posture_ua`](tax_posture_ua.md) Q3.3.3]:** чистота «UA-резидент + offshore token-co» щодо **валютного контролю + правил КІК** (контрольовані іноземні компанії) — **не підтверджена**. Потребує профільної консультації ПЕРЕД реєстрацією.

---

## 3. TOKEN-КОНТУР — розв'язка (коли/як ізолювати емісію)

### 3.1 Чому окремо (не всередині operational-vehicle)

Чотири незалежні причини, кожна достатня:

1. **Банк/емісія (UA-механіка).** UA-юрособа не має чистого банк-channel для крипто-виручки (НБУ №14); пряма практика емісії юрособою не підтверджена [R1 §2/§4, [`tax_posture_ua`](tax_posture_ua.md) open-q b].
2. **Securities-ізоляція (захист going-concern).** NaaS-fact-pattern збігається з пронгами investment-contract-тесту ([`securities_review`](securities_review.md) F1–F13). Тримати цей ризик у **multi-founder** критично-важливій операційній компанії = імпорт регуляторного + банк-freeze + репутаційного ризику у спільне ядро. Ізоляція **захищає компанію та її співзасновників**.
3. **90%-тест (Дія.City резидент — живий).** Вплив carbon/token-виручки на кваліфікований дохід резидента не звірений — доки не звірений, потік не заводимо всередину (§1.6, [`tax_posture_ua`](tax_posture_ua.md)).
4. **Однозначність титулу на solo-mission-value (§1.2).** Токен = основний value-carrier місії; тримати його у спільній особі знову зробило б власність двозначною.

### 3.2 🔴 Критична послідовність — securities-консультація ПЕРЕДУЄ офшору

**Юрисдикція-шопінг НЕ лікує security-shaped transaction** — лише переміщує регулятора [R2 §3.4, Bottom Line]. Offshore-фундація вирішує «де сидить emitent/treasury», але **не** securities-питання. Тому:

```
securities-консультація на as-built NaaS-продукт (UNI.16 / BIZ.22)
        │
        ├─ redesign продукту (прибрати investor/refund/exit-fee/yield-мову,
        │   розв'язати money-in↔token-out, розв'язати SCC↔SFC bundling)
        │   АБО свідомий compliance-шлях (ERC-3643 + структура під security)
        ▼
ТІЛЬКИ ПОТІМ → offshore token-co (#5/#6), якщо ще потрібна
```

Витрачати $8–34k+ на dual-entity ЗАРАЗ, коли (а) TRL3-hardware (жодного реального Proof-of-Growth-mint близько), (б) NaaS-продукт має нерозв'язане securities-питання, (в) DAO — far-horizon — це **premature canon** за YAGNI-драбинкою [R2 Bottom Line].

### 3.3 Тригери активації Phase-2 token-co (усі три)

- ✅ Securities-питання вирішене ([`securities_review`](securities_review.md) → redesign АБО свідомий compliance-шлях).
- ✅ Перший реальний revenue / mainnet-mint horizon (не placeholder-адреси; зараз контракти code-complete, ще не задеплоєні — [`05_03`](../../05_03_Tokenomics_SCC_and_SFC.md)).
- ✅ Hardware TRL4+ (реальний якір/EBFC — System TRL наразі 3).

### 3.4 Форма (коли тригери спрацюють)

- **Дефолт:** Cayman Foundation (#5) — industry-стандарт token-treasury (за [R2 §1.1] — понад 1 700 foundation companies станом на дату research'у); АБО BVI (#6) якщо простіший utility-issuance достатній.
- **Третьосторонній issuer Title II** дозволяє пропонувати EU-клієнтам без EU-особи (обрати home MS), **якщо** SCC лишається «other/utility», а не ART/MiFID-financial-instrument [R2 §2.5] — що знову впирається в §3.2 (securities-класифікація).

---

## 4. SPV-ВІСЬ (BIZ.15 fiat-to-retirement) — де в драбині

**Що це:** корпорація платить **фіатом** → SPV купує+гасить SCC → ISO 14064-сумісний сертифікат офсету (voluntary Scope 1-3, НЕ regulatory-compliance). Знімає бар'єр «не хочу тримати токени/ключі» ([`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md), [`00_07`](../../00_07_Action_Plan_Tracker.md) BIZ.15).

| Ось | Розклад |
|---|---|
| **Фаза** | **Phase-2** (разом із token-co АБО одразу після), **gated на перший реальний B2B-клієнт** — GTM відкладено, зараз передчасно [BIZ.15-стан] |
| **Окремий vehicle?** | **Так** — третій контур, окремий від operational-vehicle (operations) і token-co (emitent). SPV = carbon-custody/retirement-міст. Може бути co-located з offshore token-co АБО окрема EU/UA-особа |
| **Що потрібно** ([`securities_review`](securities_review.md) Блок 2.4, BIZ.15) | (1) юрисдикція SPV · (2) ліцензія на роботу з вуглецевими активами — **чи потрібна окрема UA-ліцензія = ВІДКРИТО** · (3) крипто-кастодіан · (4) бухгалтерська класифікація + сертифікат-флоу (фаховий обліковець, UNI.14) |
| **Залежності** | BIZ.20 (entity) → BIZ.2 (MSA) → перший B2B-клієнт; методолог BIZ.9 (Verra/GS legitimacy) паралельно → [`carbon_registry_matrix`](../business/carbon_registry_matrix.md) |
| **Позиція в ланцюгу** | `Корпорація → фіат → [SPV: buy+retire SCC] → esg_retired_balance (незворотно) → сертифікат`. Поточний `KlimaRetirementWorker` припускає клієнта-власника SCC on-chain → SPV закриває цей розрив для fiat-only корпорацій |

**Висновок:** SPV — **Phase-2, не зараз.** Вісь у матриці = «окремий carbon-custody vehicle, gated на перший B2B-клієнт», юрисдикція вирішується разом з token-co (крипто-юрист + Аблязов на UA carbon-license-питання).

---

## 5. РЕКОМЕНДАЦІЯ

### 5.1 ✅ PHASE-1 МІНІМУМ — що САМЕ зробити зараз (don't gold-plate)

1. **Оформити SilkenNet як R&D-продукт-лінію ВСЕРЕДИНІ наявного operational-vehicle** — жодної нової юрособи. Vehicle = named counterparty для MSA/грантів + liability-щит + **готовий пільговий Дія.City-режим для dev**. **Розблоковує BIZ.2, UNI.15.**
2. **🔴 Розвести IP/value від operational (§1.2):** SilkenNet-**IP + trademark лишаються на фізособі founder'а**, operational-vehicle отримує чистий license-back. Причина №1 = SilkenNet solo-mission, а vehicle multi-founder → без явної межі титул двозначний для обох сторін (+ причини survivability R1/R5 і AGPL-standing [`securities_review`](securities_review.md) Блок 4.3).
3. **⚖️ IP-структурний папір:** зафіксувати **явну двосторонню домовленість** — SilkenNet = окрема власність founder'а (carve-out / not-a-company-asset) + чистий license-back компанії. **Дешево зараз, дорого ретроактивно.** → у юр-review ([`securities_review`](securities_review.md) Блок 4.5). Це **гейт** перед тим, як SilkenNet-IP торкнеться репозиторіїв/балансу компанії.
4. **Trademark-заявка → на фізособу (Oleksii Lukin)** (UNI.15; три причини — §1.3) → [`trademark_brief`](trademark_brief.md).
5. **Founder-ФОП = персональний-дохід + IP-holder-фізособа** — НЕ токен (п.291.5 виключає крипто).
6. **ОДИН платний юр-workshop** (UA-частина — Аблязов, UNI.14; крипто-securities — TBD, UNI.16) на **as-built NaaS-продукт** (securities fact-pattern F1–F13) **+ IP-carve-out (п.3)** — це **справжні гейти**, кратно дешевші за ретроактивне виправлення. Пакети питань готові: [`securities_review`](securities_review.md) + [`tax_posture_ua`](tax_posture_ua.md).

**Вартість Phase-1: ≈ трохи юр-часу + ™-збір (~5–10k UAH, UNI.15) + IP-структурний папір.** Жодної офшорної структури.

### 5.2 ⏸️ PHASE-2 — що ЧЕКАЄ (gated, НЕ зараз)

| Дія | Gated на |
|---|---|
| **Offshore token-co** (Cayman #5 / BVI #6) для емісії SCC/SFC | securities-консультація вирішена **+** перший mint horizon **+** TRL4+ (§3.3) |
| **SPV** (BIZ.15 fiat-to-retirement) | перший реальний B2B-клієнт (§4) |
| **Estonia OÜ / EU-присутність** | якщо EU-passporting/банкінг стануть потрібні |
| **КІК/валютний-контроль review** «UA opco + offshore token-co» | ПЕРЕД будь-якою offshore-реєстрацією [R1 §3 open-q] |

### 5.3 ⛔ ЧОГО НЕ РОБИТИ ЗАРАЗ

- **Не проектувати складну офшорну dual/tri-entity структуру як «зараз».** TRL3, нуль виручки, нічого не задеплоєно, DAO far-horizon → premature canon [R2 Bottom Line, YAGNI-драбинка].
- **Не вносити токен-емісію в operational-vehicle** (банк-проблема + securities-імпорт у multi-founder going-concern + незвірений 90%-тест + двозначність титулу).
- **Не лишати титул на SilkenNet-IP невизначеним** (§1.2) — оформити межу ДО того, як IP торкнеться контуру компанії.
- **Не реєструвати ™ на юрособу** (двозначність титулу + втрата survivability).
- **Не покладатися на жодну конкретну дату UA-crypto-закону** — законопроєкт №10225-д не чинний, ціль ~2027, рухома [R1 §2, R2 §3.3].

---

## 6. Впевненість і явні прогалини (чесно)

- **Висока:** ФОП виключений для крипто (п.291.5); ТОВ-мінімум для web3; operational-vehicle — наявна UA-компанія й Дія.City-резидент (founder-факт); базова Дія.City-механіка; модель «організація-of-record як KYC-якір» уже в коді (KYC.1); operational-vehicle multi-founder (founder-факт); securities-fact-pattern grounded у коді ([`securities_review`](securities_review.md) F1–F13).
- **Середня:** офшорні вартості/timeline (orientation, вторинні джерела); MiCA Title II issuer path; двоособовий патерн як industry-стандарт.
- **🔴 Відкриті питання (для юриста, не наші відповіді):**
  - (a) чи carbon/token-виручка = «кваліфікований дохід» 90%-тесту Дія.City — **вирішує, наскільки терміново виносити carbon/token за межі operational-vehicle** ([`tax_posture_ua`](tax_posture_ua.md)).
  - (b) чи законно UA-ТОВ (у т.ч. наш operational-vehicle) емітувати+банкувати токен ([`tax_posture_ua`](tax_posture_ua.md)) — **вирішує, чи token-co обов'язковий**.
  - (c) securities-класифікація NaaS as-built ([`securities_review`](securities_review.md) Блок 1) — **вирішує redesign vs compliance, ПЕРЕДУЄ офшору**.
  - (d) **механіка IP-carve-out + license-back** — як юридично закріпити SilkenNet як окрему власність founder'а при dev-роботі через multi-founder operational-vehicle (службовий твір / IP-assignment за UA ЦК; форма корпоративної згоди; cross-ref [`securities_review`](securities_review.md) Блок 4.4-4.5 — студентські/грантові службові твори).
  - (e) чистота «UA-резидент + offshore token-co» щодо КІК/валютного контролю (R1 §3, [`tax_posture_ua`](tax_posture_ua.md) Q3.3.3).
  - (f) окрема UA carbon-asset-ліцензія для SPV ([`securities_review`](securities_review.md) Блок 2.4).

> **Один рядок для рішення:** *Phase-1 = SilkenNet operational-під-наявним vehicle (пільговий Дія.City-shell, ≈0 вартість, розблоковує MSA/grant/™/liability), АЛЕ IP+™ на фізособі founder'а + оформлений IP-carve-out з чистим license-back (vehicle multi-founder → титул solo-mission має бути однозначним для обох сторін). Token-емісія + SPV = Phase-2, gated на securities-консультацію — і вона ПЕРЕДУЄ будь-якій офшорній структурі.*

---

## Cross-references

| Ресурс | Що бере |
|---|---|
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | **BIZ.20** (дім стану) + BIZ.15 / BIZ.22 / UNI.14 / UNI.15 / UNI.16 / BIZ.2 / BIZ.21 |
| [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) | IP-постава + канонізований тришар «хто оперує ≠ хто володіє ≠ хто емітує» |
| [`00_04 §8`](../../00_04_Nature_as_a_Service_Contracts.md) | юр/бізнес-передумови NaaS (MSA, RWA, SPV/BIZ.15, KYC) |
| [`securities_review`](securities_review.md) | securities/RWA/IP fact-pattern + питання до юриста (Блок 4.5 = IP-структурування) |
| [`tax_posture_ua`](tax_posture_ua.md) | Дія.City-ставки, 90%-тест, token-емісія/банкування — податковий дім |
| [`R1_ua_legal.md`](../research/R1_ua_legal.md) · [`R2_offshore_token_securities.md`](../research/R2_offshore_token_securities.md) | орієнтаційний research, на який спираються [R1 §X] / [R2 §X] |
