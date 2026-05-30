# 00_04: Shape Up Operations and R&D Clusters

## 🎯 Мета

Зафіксувати операційну механіку методології AI-Native Concurrent Engineering: 6+2-тижневий цикл Shape Up, 4 R&D кластери, Betting Table процедура, async-review для нижчих TRL (щоб Архітектор не був bottleneck'ом), Triple Stream та інтеграція з академічним календарем партнерських ВНЗ.

> Філософська основа (NASA TRL, Intent-First, Wiki-First) — [`00_02_AI_Native_Engineering_and_TRL`](00_02_AI_Native_Engineering_and_TRL).
> Інструментарій (GitHub Projects V2 fields, labels, workflows) — [`00_05_GitHub_Projects_and_IaC_Automation`](00_05_GitHub_Projects_and_IaC_Automation).

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — методологія інтегрована в операційні процеси, інструментарій MCP налаштований.
- **Контекст:** Синхронізація двох потоків: **Атоми** (Hardware: лабораторія ЧНУ, заводи DMLS) та **Байти** (Software: Rails, прошивка, смарт-контракти).
- **Стоячі ризики (мітиговані):** Context Drift → автоматизований SSOT Integrity Guard ([`00_05`](00_05_GitHub_Projects_and_IaC_Automation)); Hardware lead-times → HIL-симулятори ([`00_03`](00_03_TRL_Matrix_HIL_and_Beyond)).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [00_02_AI_Native_Engineering_and_TRL](00_02_AI_Native_Engineering_and_TRL) | Концептуальна основа: NASA TRL, AI pipeline, Triple Stream, Wiki-First |
| [00_03_TRL_Matrix_HIL_and_Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | TRL-матриця + HIL (decoupling software TRL від hardware) |
| [00_05_GitHub_Projects_and_IaC_Automation](00_05_GitHub_Projects_and_IaC_Automation) | Projects V2 fields, labels-as-code, cluster routing |
| [00_07_Action_Plan_Tracker](00_07_Action_Plan_Tracker) | Open backlog (OPS.3 / OPS.4 + Convolution Method context) |
| [08_01_University_R_and_D_Protocols](08_01_University_R_and_D_Protocols) | Стратегічні підстави для multi-cluster R&D (§1.1-1.3) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Методологія Shape Up (6+2 Cycle)](#-1-методологія-shape-up-62-cycle)
- [2. Кадрова організація: 4 R&D кластери](#-2-кадрова-організація-4-rd-кластери)
- [3. Async-Review Policy (Розблокування Архітектора)](#-3-async-review-policy-розблокування-архітектора)
- [4. Triple Stream & AI Handoff](#-4-triple-stream--ai-handoff)
- [5. Shape Up Cycle Template (OPS.3)](#-5-shape-up-cycle-template-ops3)
- [6. Академічний календар ↔ TRL milestones (OPS.4)](#-6-академічний-календар--trl-milestones-ops4)
<!-- TOC:AUTO:END -->

---

## ⚡ 1. Методологія Shape Up (6+2 Cycle)

Gaia 2.0 відмовляється від класичного Agile на користь 8-тижневих циклів для забезпечення глибокого інженерного фокусу:

- **Build Cycle (6 тижнів):** Робота над "Великими Ставками" (Big Bets). Команда (люди + AI) ізольована від нових вхідних запитів для виконання складних архітектурних задач.
- **Cool-down (2 тижні):** Період для вільного рефакторингу, виправлення дрібних багів та обов'язкового оновлення Wiki (SSOT).
- **Betting Table:** Фаза прийняття рішень Архітектором щодо наступного циклу на основі поточних рівнів TRL.

### 1.1 Build Cycle (6 тижнів): структура

```
Week 0 (Betting Table — async pre-read ≥3 дні + синхронний колл ≤1.5 год) — рішення які Big Bets входять у цикл
Week 1-2 (Discovery) — shaping documents до "fat marker sketch" рівня
Week 3-4 (Build) — основна імплементація, перші demo
Week 5    (Hill chart) — кожна Big Bet проходить middle line; ризики уточнюються
Week 6    (Closing) — feature freeze, integration testing, doc оновлення
Week 7-8 (Cool-down, 2 тижні) — рефакторинг, SSOT-аудит, наступний betting prep
```

Для кожного циклу створюється milestone у GitHub `Cycle YYYY.QN` (приклад: `Cycle 2026.Q2`) і прив'язується до карток Projects V2 у Big-Bet статусі.

---

## 🧑‍🔬 2. Кадрова організація: 4 R&D кластери

Розподіл 25+ паралельних задач між 8+ науковцями реалізовано через **чотири кластери**. Кожна Big Bet прив'язується до одного кластера у момент betting table.

| Кластер | Сфера відповідальності | Типові epic-домени | Базова команда |
|---------|-------------------------|---------------------|-----------------|
| **A — Hardware / EBFC** | Атоми, фізика, матеріали, біопаливний елемент, гідрогелі | EBFC catalyst R&D, Ti-6Al-4V DMLS, EDLC supercap MPPT, friction-fit pull-out, біосумісність, BIO.* sterilization | **ЧНУ** (Мінаєв — квант. хімія `08_01`, Гусак — металургія/FEA, Біо-Хаб Спрягайло), **ЧМА** (біохімія EBFC, токсикологія `08_06`), **ЧДТУ ПМКТ** (Базіло/Бондаренко — акустика `08_04`), **СЄУ** (Денисенко — промдизайн радому `08_07`) |
| **B — Verification / Math** | Докази, математика, верифікація, ZK | Lorenz attractor params, IoTeX W3bstream, peaq DID schemes, Chainlink Functions, dual-computation integrity, Solidity governance | **ЧНУ ФОТІУС** (Порубльов — дискр. математика, Онищенко — стох. оптимізація, Любченко — Master of Logic/GA `08_02`), **ЧДТУ** (Карапетян — Data Science/статистика `08_04`), AI agents (theorem proving) |
| **C — Scaling / Cloud** | Software stack, infrastructure, performance | Rails core (`04_02`), multi-chain web3 (12 chains), Akash deploy (`06_02`), Prometheus/Grafana, Sidekiq queues, Solid Cable, Phlex UI | Architect + AI agents (Copilot, Cursor), **ЧНУ ФОТІУС** (Супруненко — Rails PN-верифікація, Ярмілко — firmware/crypto, Косенюк — RF/FEC, Бушин — CNN/Web-DB `08_02`), **ЧДТУ ФЕТР** (Гончаров — RF-лабораторія `08_04`) |
| **D — Compliance / Legal** | Юриспруденція, регуляторика, IP, B2B, операційні SOP | Polygon Hadron (ERC-3643), MSA з СЄУ, Verra / Gold Standard методологія, GDPR / ESG звітність, patent portfolio, аварійні SOP | **СЄУ** (Аблязов — право, Чудаєва/Ус — економіка, Гедз — D-MRV аудит `08_07`), **ЧІПБ** (пожежна безпека, SOP, параметричне страхування `08_05`), **ЧНУ ФОТІУС** (Осауленко — R&D-портфель `08_02`) |

> **Принцип взаємовиключності:** кожна задача має **рівно один primary cluster label** (`cluster:A-hardware` / `cluster:B-verification` / `cluster:C-scaling` / `cluster:D-compliance`). Cross-cluster задачі мають **secondary label** (`cluster-ref:X`). Primary cluster визначає, хто веде задачу на betting table; secondary — кого консультують у RACI-режимі. Повна label-таксономія + YAML SSOT — у [`00_05 §Labels`](00_05_GitHub_Projects_and_IaC_Automation).

---

## 🧮 3. Async-Review Policy (Розблокування Архітектора)

> **Проблема:** Архітектор не може фізично рев'ювити кожен PR / схему / звіт з 4 паралельних кластерів — це створює bottleneck, який нівелює сенс Concurrent Engineering. Раніше документ казав "Архітектор перевіряє результат і піднімає рівень TRL", без розрізнення між low-TRL прототипом і production-критичним merge.

> **⚠️ Хто такий «Лід кластера» (корекція 2026-05-28):** Це **внутрішній R&D-інженер Silken Net** (представник ActiveBridge або Архітектор), який оперує GitHub (PR, approve, CI). Це **НЕ** професор ЧНУ/ЧМА/ЧІПБ — науковці не мають GitHub-акаунтів і не роблять Git-approve. Академічний «апрув» — це **підписаний офіційний лабораторний звіт / протокол (PDF/Markdown)**. Лід кластера агрегує ці звіти від університетів і конвертує їх у затверджений PR з посиланням на звіт. Тобто Git-процес — для інженерів Silken Net; підпис на лабораторному звіті — для науковців.

**Async-review правила (TRL-stratified):**

| TRL | Хто рев'ює | Тригер на втручання Архітектора |
|-----|------------|----------------------------------|
| **TRL 1-2** (Idea / Principle) | Лід кластера (внутрішній R&D-інженер Silken Net — див. ⚠️ вище) на основі підписаного лаб-звіту від науковців + AI agent self-check | Тільки на запит ліда: коли потрібна "epoch-defining" архітектурна декларація. |
| **TRL 3-4** (PoC / Breadboard) | Лід кластера + Required CI checks: `rubocop`, `rspec`, `brakeman`, `bundler-audit`, host-firmware tests, `solidity_audit.yml` (Foundry + Slither). | Тільки на TRL Gate (перехід з 4 → 5). |
| **TRL 5-6** (Prototype / Pilot) | Лід кластера + Architect approval **required** + повний `SSOT Integrity Guard`. | Always. |
| **TRL 7-8** (Field / Qualification) | Architect + DAO governance proposal (`SilkenGovernor.sol`) + Quality Gate (Codex ADR-CDX-1..7). | Always + multisig (`Gnosis Safe`). |
| **TRL 9** (Operational) | Multi-sig + DAO Timelock (48h) + Slither/Foundry green. | Always + production sign-off. |

**TRL Gate Events** (єдині точки, де Архітектор **гарантовано** втручається):
- 4 → 5: перехід з лабораторії до pilot (потребує HIL-валідації, `00_03`).
- 6 → 7: перехід до canopy environment (real LoRa mesh, real CoAP intake).
- 8 → 9: **зняття «тренувальних коліс»** — передача повного управління контрактами від Multi-sig (`Gnosis Safe`) до децентралізованого DAO (`SilkenGovernor` + Timelock) + зняття штучних лімітів емісії, при доведеній стабільній роботі на масштабі (мільйони вузлів без втручання).

  > **⚠️ Корекція (2026-05-28):** мінтинг SCC — **НЕ перемикач**, який Архітектор вмикає на TRL 9. Він керується децентралізованим оракулом (Chainlink) + Guard Clauses (`verified_by_iotex` + `oracle_status_fulfilled` + `hadron_kyc`, [`05_02`](05_02_Proof_of_Growth_Pipeline)/[`00_01 §5`](00_01_Vision_Mission_and_Roadmap)). На TRL 7-8 система **вже** в mainnet — з малим лімітом емісії та multi-sig на DAO-скарбниці. TRL 9 = **масштаб + децентралізація**, а не «deploy».

---

## 🤝 4. Triple Stream & AI Handoff

Розробка відбувається синхронно у трьох вимірах (детально — у [`00_02 §Triple Stream`](00_02_AI_Native_Engineering_and_TRL)):

1. **Hardware Stream (Atoms)** — рев'ю кластера A.
2. **Logic Stream (Bytes)** — рев'ю кластера C + cross-ref B для Solidity / ZK.
3. **Verification Stream (Proofs)** — рев'ю кластера B + cross-ref C для Rails-інтеграції.

**Agent Handoff Protocol:** Architect (Vision) ➔ Gemini (Shaping) ➔ Wiki (SSOT) ➔ Cursor (Implementation) ➔ ChNU Lab (Validation) — все автоматизовано через `MCP` (Model Context Protocol) індексацію відповідних `docs/*.md`.

---

## 🎯 5. Shape Up Cycle Template (OPS.3)

### 5.1 Shaping Document Template

Кожна Big Bet перед потраплянням на Betting Table має `shaping/<slug>.md` (у `docs/`, або у RFC-репо). Формат:

```markdown
# Shape: <назва Big Bet> [cluster A/B/C/D]

## Problem (1-2 параграфи)
Конкретна болячка з даних: метрика, інцидент, або blocker (з `docs/00_07`).
Що НЕ є проблемою — щоб уникнути scope creep.

## Appetite (Small Batch 1-2w / Big Bet 6w)
Час, який ми готові інвестувати. Це НЕ оцінка трудозатрат — це cap.
Якщо не вкладаємось у 6 тижнів — циркулюємо через cool-down знову.

## Solution (fat marker sketch)
Архітектурний скетч на рівні діаграми блоків / послідовності.
БЕЗ деталей: без коду, без точних API сигнатур.

## Rabbit holes (ризики)
Конкретні технічні pitfalls які можуть забрати тиждень+:
- "X може потребувати міграції Y, що блокує деплой"
- "Зовнішня API має rate limit Z — потрібен fallback"

## No-go's (out of scope)
Що НЕ робимо в цьому циклі.

## Affected SSOT docs
Перелік `docs/0X_NN_*.md` які доведеться оновити.
```

### 5.2 Betting Table процедура

Betting Table — у Week 0 кожного 8-тижневого циклу. **Асинхронний за замовчуванням** (поважає час розподіленої академічної команди): огляд попереднього циклу + shaping documents викладаються у Wiki **за ≥3 дні** до зустрічі для async-читання. Синхронний колл — **≤1.5 години**, лише для відкритих конфліктів (rabbit holes) та фінальних рішень. Учасники: Архітектор, представник кожного активного кластера (A/B/C/D), AI-agent з access до `docs/` SSOT.

> **⚠️ Корекція (2026-05-28):** 4-годинний синхронний колл (4 кластери × 15 хв презентації + 10 хв питань + огляди) для 6 ВНЗ і розподіленої команди = некерований хаос і марнування часу професури. Тому фази «Огляд» та «Презентація shape-документів» — **асинхронні** (Wiki за 3 дні); синхронно обговорюємо лише `Rabbit holes` і рішення `Drop/Park/Bet`.

**Pre-bet checklist (👤 Architect, за тиждень до Betting Table):**

- [ ] Список усіх відкритих `shaping/*.md` зведено у короткий бриф (одна сторінка на bet).
- [ ] Поточний `docs/00_07_Action_Plan_Tracker` оновлено: P0/P1 не закриті задачі винесені у обов'язкові nominees.
- [ ] TRL-матриця у Projects V2 переглянута на наявність stuck cards (закрита без advance — flag).
- [ ] Bandwidth check кожного кластера: hours-per-week × cycle weeks мінус известні відсутності (захисти, конференції).

**Фаза A — Асинхронно (Wiki, ≥3 дні до коллу):**

| Step | Хто веде | Артефакт |
|------|----------|----------|
| 1. Огляд попереднього циклу | Architect | Hill chart + closed/dropped bets у Wiki |
| 2. Shaping documents для читання | Автор shape | `shaping/<slug>.md` + fat-marker sketch у Wiki |
| 3. Cluster bandwidth check | Architect | Таблиця cluster ↔ bet з % allocation (pre-bet checklist) |

**Фаза B — Синхронний колл (Week 0, ≤1.5 год):**

| Step | Час | Хто веде | Артефакт |
|------|-----|----------|----------|
| 4. Відкриті конфлікти / rabbit holes | ~45 хв | Усі | Notes у shaping doc під "Rabbit holes" |
| 5. Drop / Park / Bet рішення | ~30 хв | Architect (final say) | Updated Projects V2 cards |
| 6. Кодифікація рішень | ~15 хв | AI-agent | PR з оновленим `docs/00_07` + `docs/00_04` milestone link |

**Рішення для кожного shape:**
- **Bet** — потрапляє в цикл, прив'язується до кластера + `Cycle YYYY.QN` milestone.
- **Park** — shape залишається, але не в цьому циклі (review через 6+ тижнів).
- **Drop** — закрити shape з reason; не повертатися без перепакування.

**Anti-patterns на Betting Table:**

- ❌ "Майже готово, давайте дотягнемо у наступному циклі" — ні. Якщо не закрилось — Drop або повний re-shape.
- ❌ Більше 6 Bets на 4 кластери — приймай менше, не розпорошуй людей.
- ❌ Один кластер забирає >2 Big Bets — це сигнал, що інші кластери знесилені; resort cluster routing.

### 5.3 Cool-down (2 тижні) — обов'язкові пункти

Cool-down — це **дихальний простір** (Shape Up: unstructured time), а НЕ ще один спринт. Якщо набити його обов'язковим bug-bash + refactor + документуванням, після 6 тижнів Big Bets це дає миттєвий burnout. Тому жорстко-обов'язкові — лише пункти, що підтримують **життєздатність системи**; решта — на розсуд команди.

**Обов'язково (system viability):**
- [ ] **SSOT drift audit** для змінених модулів циклу: code-vs-doc diff проти `docs/04_02` §13b (Drift Register), `docs/04_03`, `docs/05_02`, `docs/06_02`.
- [ ] Закриті cycle issues анотувати TRL advancement (через `trl_sync.yml` — авто, див. `00_05`); update `docs/00_03` (фактичні TRL зрушення).

**Опціонально (на розсуд команди, НЕ мандат):**
- [ ] Bug-bash дрібних некритичних багів — скільки команда захоче, без квоти днів.
- [ ] Легка підготовка shaping-чернеток до наступного Betting Table (повний shaping — асинхронно, див. §5.2).

> **⚠️ Не в cool-down (2026-05-28):** Великий **refactor** та значущий **bug-bash** планувати як окремі **Small Bets** у наступному 6-тижневому циклі (з власним appetite/shape), а не вганяти у 2-тижневий cool-down. Інакше cool-down перетворюється на прихований спринт → вигорання.

---

## 🎓 6. Академічний календар ↔ TRL milestones (OPS.4)

### 6.1 Чому це окремий вимір

TRL-матриця крокує "квартально-функціональним" темпом, але UNI.* партнери (ChNU FOTIUS, ChDTU, ChIPB, ChMA, СЄУ) працюють по **академічних семестрах**. Без явного мапінгу milestone deadlines зміщуються відносно дат захисту магістерських / дипломних робіт, а Betting Table не може коректно "приклеїти" Big Bet до семестру.

Тому в Projects V2 додано **окремий single-select field `Academic Semester`** — він не замінює `Target TRL`, а доповнює його.

### 6.2 Мапінг семестрів (Україна, ChNU/ChDTU convention)

| Період (включно) | Семестр | Назва опції в Projects V2 |
| :--- | :--- | :--- |
| 1 вересня — 31 січня | Осінній (Fall) | `Fall {Y}-{Y+1}` (наприклад, `Fall 2025-2026` для дат у вересні 2025 — січні 2026) |
| 1 лютого — 30 червня | Весняний (Spring) | `Spring {Y-1}-{Y}` (наприклад, `Spring 2025-2026` для дат у лютому — червні 2026) |
| 1 липня — 31 серпня | Літня перерва | приклеюється до наступного `Fall {Y}-{Y+1}` |

### 6.3 Мапінг TRL milestones ↔ семестр

| TRL | Очікуваний семестр | Академічний deliverable | Прив'язка |
| :--- | :--- | :--- | :--- |
| TRL 4-5 (lab validation) | Fall (вересень — січень) | Лабораторні протоколи, перший draft публікації | UNI.1 (декан Онищенко) + UNI.4 (школа Мінаєва) + UNI.5 (школа Гусака) |
| TRL 5-6 (relevant environment) | Spring (лютий — травень) | Магістерські та дипломні **захисти у червні** | UNI.13 / UNI.14 верифікація науковців |
| TRL 6-7 (pilot deploy) | Літня перерва + Fall | Pilot installation, conference paper draft | UNI.8 СЄУ MSA |
| TRL 7-8 (operational) | Spring | Peer-reviewed публікація | UNI.* IP strategy (`08_03`) |

> Фінальні захисти у червні — **hard deadline** для TRL freeze поточного циклу. Будь-яка картка з `Target TRL ≥ 6` повинна бути закрита **до 15 червня**, інакше прив'язка зсувається у `Fall {Y}-{Y+1}`.

---

