# 00_05: Shape Up Operations and R&D Clusters

## 🎯 Мета

Зафіксувати операційну механіку методології AI-Native Concurrent Engineering: 6+2-тижневий цикл Shape Up, 4 R&D кластери, Betting Table процедура, async-review для нижчих TRL (щоб Архітектор не був bottleneck'ом), Triple Stream та інтеграція з академічним календарем партнерських ВНЗ.

> Філософська основа (NASA TRL, Intent-First, Wiki-First) — [`00_04_AI_Native_Engineering_and_TRL`](00_04_AI_Native_Engineering_and_TRL).
> Інструментарій (GitHub Projects V2 fields, labels, workflows) — [`00_07_GitHub_Projects_and_IaC_Automation`](00_07_GitHub_Projects_and_IaC_Automation).

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — методологія інтегрована в операційні процеси, інструментарій MCP налаштований.
- **Контекст:** Синхронізація двох потоків: **Атоми** (Hardware: лабораторія ЧНУ, заводи DMLS) та **Байти** (Software: Rails, прошивка, смарт-контракти).
- **Пов'язані модулі:**
  - Концептуальна основа (NASA TRL, AI pipeline, Triple Stream, Wiki-First) → [`00_04_AI_Native_Engineering_and_TRL`](00_04_AI_Native_Engineering_and_TRL)
  - Стратегічна дорожня карта та TRL матриця → [`00_06_Strategic_Roadmap_and_HIL_Simulators`](00_06_Strategic_Roadmap_and_HIL_Simulators)
  - GitHub Projects + IaC automation → [`00_07_GitHub_Projects_and_IaC_Automation`](00_07_GitHub_Projects_and_IaC_Automation)
  - Open backlog → [`00_08_Action_Plan_Tracker`](00_08_Action_Plan_Tracker)

---

## 🛑 Блокери

- **Context Drift:** Ризик розсинхронізації між кодом та документацією. Вимагає суворого дотримання протоколу "Wiki-First" та автоматизованого SSOT Integrity Guard ([`00_07 §SSOT Guard`](00_07_GitHub_Projects_and_IaC_Automation)).
- **Hardware Lead Times:** Затримки у виробництві титанових анкерів обмежують швидкість валідації натурних випробувань. Mitigation — HIL Simulators ([`00_06 §HIL`](00_06_Strategic_Roadmap_and_HIL_Simulators)).

---

## ⚡ 1. Методологія Shape Up (6+2 Cycle)

Gaia 2.0 відмовляється від класичного Agile на користь 8-тижневих циклів для забезпечення глибокого інженерного фокусу:

- **Build Cycle (6 тижнів):** Робота над "Великими Ставками" (Big Bets). Команда (люди + AI) ізольована від нових вхідних запитів для виконання складних архітектурних задач.
- **Cool-down (2 тижні):** Період для вільного рефакторингу, виправлення дрібних багів та обов'язкового оновлення Wiki (SSOT).
- **Betting Table:** Фаза прийняття рішень Архітектором щодо наступного циклу на основі поточних рівнів TRL.

### 1.1 Build Cycle (6 тижнів): структура

```
Week 0 (Betting Table, ≤4 год) — рішення які Big Bets входять у цикл
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
| **A — Hardware / EBFC** | Атоми, фізика, матеріали, біопаливний елемент, гідрогелі | EBFC catalyst R&D, Ti-6Al-4V DMLS, EDLC supercap MPPT, friction-fit pull-out, біосумісність, BIO.* sterilization | ChNU FOTIUS (декан, біохімія), ChDTU materials, ChIPB safety |
| **B — Verification / Math** | Докази, математика, верифікація, ZK | Lorenz attractor params, IoTeX W3bstream, peaq DID schemes, Chainlink Functions, dual-computation integrity, Solidity governance | ChNU math/CS, ChIPB cryptography, AI agents (theorem proving) |
| **C — Scaling / Cloud** | Software stack, infrastructure, performance | Rails core (`04_02`), multi-chain web3 (12 chains), Akash deploy (`06_02`), Prometheus/Grafana, Sidekiq queues, Solid Cable, Phlex UI | Architect + AI agents (Copilot, Cursor) |
| **D — Compliance / Legal** | Юриспруденція, регуляторика, IP, B2B | Polygon Hadron (ERC-3643), MSA з СЄУ, Verra / Gold Standard методологія, GDPR / ESG звітність, patent portfolio | СЄУ (Аблязов), UNI.8, external advisors |

> **Принцип взаємовиключності:** кожна задача має **рівно один primary cluster label** (`cluster:A-hardware` / `cluster:B-verification` / `cluster:C-scaling` / `cluster:D-compliance`). Cross-cluster задачі мають **secondary label** (`cluster-ref:X`). Primary cluster визначає, хто веде задачу на betting table; secondary — кого консультують у RACI-режимі. Повна label-таксономія + YAML SSOT — у [`00_07 §Labels`](00_07_GitHub_Projects_and_IaC_Automation).

---

## 🧮 3. Async-Review Policy (Розблокування Архітектора)

> **Проблема:** Архітектор не може фізично рев'ювити кожен PR / схему / звіт з 4 паралельних кластерів — це створює bottleneck, який нівелює сенс Concurrent Engineering. Раніше документ казав "Архітектор перевіряє результат і піднімає рівень TRL", без розрізнення між low-TRL прототипом і production-критичним merge.

**Async-review правила (TRL-stratified):**

| TRL | Хто рев'ює | Тригер на втручання Архітектора |
|-----|------------|----------------------------------|
| **TRL 1-2** (Idea / Principle) | Лід відповідного кластера (наприклад, декан ChNU FOTIUS для cluster A; lead developer для C) + AI agent self-check | Тільки на запит ліда: коли потрібна "epoch-defining" архітектурна декларація. |
| **TRL 3-4** (PoC / Breadboard) | Лід кластера + Required CI checks: `rubocop`, `rspec`, `brakeman`, `bundler-audit`, host-firmware tests, `solidity_audit.yml` (Foundry + Slither). | Тільки на TRL Gate (перехід з 4 → 5). |
| **TRL 5-6** (Prototype / Pilot) | Лід кластера + Architect approval **required** + повний `SSOT Integrity Guard`. | Always. |
| **TRL 7-8** (Field / Qualification) | Architect + DAO governance proposal (`SilkenGovernor.sol`) + Quality Gate (Codex ADR-CDX-1..7). | Always + multisig (`Gnosis Safe`). |
| **TRL 9** (Operational) | Multi-sig + DAO Timelock (48h) + Slither/Foundry green. | Always + production sign-off. |

**TRL Gate Events** (єдині точки, де Архітектор **гарантовано** втручається):
- 4 → 5: перехід з лабораторії до pilot (потребує HIL-валідації, `00_06`).
- 6 → 7: перехід до canopy environment (real LoRa mesh, real CoAP intake).
- 8 → 9: production mainnet deploy (SCC mint enabled на Polygon mainnet).

---

## 🤝 4. Triple Stream & AI Handoff

Розробка відбувається синхронно у трьох вимірах (детально — у [`00_04 §Triple Stream`](00_04_AI_Native_Engineering_and_TRL)):

1. **Hardware Stream (Atoms)** — рев'ю клстера A.
2. **Logic Stream (Bytes)** — рев'ю клстера C + cross-ref B для Solidity / ZK.
3. **Verification Stream (Proofs)** — рев'ю клстера B + cross-ref C для Rails-інтеграції.

**Agent Handoff Protocol:** Architect (Vision) ➔ Gemini (Shaping) ➔ Wiki (SSOT) ➔ Cursor (Implementation) ➔ ChNU Lab (Validation) — все автоматизовано через `MCP` (Model Context Protocol) індексацію відповідних `docs/*.md`.

---

## 🎯 5. Shape Up Cycle Template (OPS.3)

### 5.1 Shaping Document Template

Кожна Big Bet перед потраплянням на Betting Table має `shaping/<slug>.md` (у `docs/`, або у RFC-репо). Формат:

```markdown
# Shape: <назва Big Bet> [cluster A/B/C/D]

## Problem (1-2 параграфи)
Конкретна болячка з даних: метрика, інцидент, або blocker (з `docs/00_08`).
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

Betting Table — `≤4 години` event у Week 0 кожного 8-тижневого циклу. Учасники: Архітектор, представник кожного активного кластера (A/B/C/D), AI-agent з access до `docs/` SSOT.

**Pre-bet checklist (👤 Architect, за тиждень до Betting Table):**

- [ ] Список усіх відкритих `shaping/*.md` зведено у короткий бриф (одна сторінка на bet).
- [ ] Поточний `docs/00_08_Action_Plan_Tracker` оновлено: P0/P1 не закриті задачі винесені у обов'язкові nominees.
- [ ] TRL-матриця у Projects V2 переглянута на наявність stuck cards (закрита без advance — flag).
- [ ] Bandwidth check кожного кластера: hours-per-week × cycle weeks мінус известні відсутності (захисти, конференції).

**Betting Table процедура (Week 0, 4 години):**

| Step | Час | Хто веде | Артефакт |
|------|-----|----------|----------|
| 1. Огляд попереднього циклу | 30 хв | Architect | Hill chart + closed/dropped bets |
| 2. Презентація shaping documents | по 15 хв на bet | Автор shape | Slide / fat-marker walkthrough |
| 3. Per-bet open questions | по 10 хв | Усі | Notes у shaping doc під "Rabbit holes" |
| 4. Cluster bandwidth match | 30 хв | Architect | Таблиця cluster ↔ bet з % allocation |
| 5. Drop / Park / Bet рішення | 30 хв | Architect (final say) | Updated Projects V2 cards |
| 6. Кодифікація рішень | 30 хв | AI-agent | PR з оновленим `docs/00_08` + `docs/00_05` milestone link |

**Рішення для кожного shape:**
- **Bet** — потрапляє в цикл, прив'язується до кластера + `Cycle YYYY.QN` milestone.
- **Park** — shape залишається, але не в цьому циклі (review через 6+ тижнів).
- **Drop** — закрити shape з reason; не повертатися без перепакування.

**Anti-patterns на Betting Table:**

- ❌ "Майже готово, давайте дотягнемо у наступному циклі" — ні. Якщо не закрилось — Drop або повний re-shape.
- ❌ Більше 6 Bets на 4 кластери — приймай менше, не розпорошуй людей.
- ❌ Один кластер забирає >2 Big Bets — це сигнал, що інші кластери знесилені; resort cluster routing.

### 5.3 Cool-down (2 тижні) — обов'язкові пункти

Cool-down — не "відпустка", а інвестиція у SSOT-цілісність. Без цього система втрачає synchronicity між кодом і документами.

- [ ] **SSOT drift audit** для змінених модулів циклу: code-vs-doc diff проти `docs/04_02` §13b (Drift Register), `docs/04_03`, `docs/05_02`, `docs/06_02`.
- [ ] Закриті cycle issues анотувати TRL advancement (через `trl_sync.yml` — авто, див. `00_07`).
- [ ] Bug-bash: 1-2 дні фікс bugs, які накопичились але були "не critical".
- [ ] Refactor: тільки якщо явно покращує цикл наступного betting (наприклад, виносимо повторюваний код у service, який повинні юзати 2+ нові bets).
- [ ] Підготовка shaping documents до наступного Betting Table.
- [ ] Update `docs/00_06_Strategic_Roadmap_and_HIL_Simulators`: фактичні TRL зрушення проти прогнозованих.

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
| TRL 4-5 (lab validation) | Fall (вересень — січень) | Лабораторні протоколи, перший draft публікації | UNI.1 / UNI.5 декан ChNU FOTIUS |
| TRL 5-6 (relevant environment) | Spring (лютий — травень) | Магістерські та дипломні **захисти у червні** | UNI.13 / UNI.14 верифікація науковців |
| TRL 6-7 (pilot deploy) | Літня перерва + Fall | Pilot installation, conference paper draft | UNI.8 СЄУ MSA |
| TRL 7-8 (operational) | Spring | Peer-reviewed публікація | UNI.* IP strategy (`08_03`) |

> Фінальні захисти у червні — **hard deadline** для TRL freeze поточного циклу. Будь-яка картка з `Target TRL ≥ 6` повинна бути закрита **до 15 червня**, інакше прив'язка зсувається у `Fall {Y}-{Y+1}`.

---

## 🔗 7. Cross-ref

- `docs/00_04` — філософська основа (TRL, AI pipeline, Triple Stream, Wiki-First).
- `docs/00_06` — TRL Matrix + HIL Simulators (як ми технічно decoupling-уємо software TRL від hardware TRL).
- `docs/00_07 §6 Kanban / Labels / Routing` — Projects V2 fields, labels.yml, GitHub Actions workflows для cluster routing.
- `docs/00_08 OPS.3 / OPS.4` — оригінальний задачний контекст + alignment з Convolution Method (10× / 100× speedup PN-state explosion).
- `docs/08_01 §1.1-1.3` — стратегічні підстави для multi-cluster R&D.
