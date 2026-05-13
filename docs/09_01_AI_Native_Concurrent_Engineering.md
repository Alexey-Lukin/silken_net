# 09_01: AI-Native Concurrent Engineering (Парадигма Окремого Розуму)

## 🎯 Мета

Впровадити фреймворк паралельного інжинірингу для подолання фізичних та часових бар'єрів DeepTech-розробки. Цей протокол трансформує роль ШІ-агентів (Gemini, Cursor, Copilot) на повноправних учасників життєвого циклу розробки, чия діяльність суворо спрямовується через Єдине Джерело Істини (SSOT).

---

## ✅ Статус

- **Поточний TRL:** TRL 8 — методологія інтегрована в операційні процеси, інструментарій MCP налаштований
- **Контекст:** Синхронізація двох потоків: **Атоми** (Hardware: лабораторія ЧНУ, заводи DMLS) та **Байти** (Software: Rails, прошивка, смарт-контракти)
- **Пов'язані модулі:**
  - Концептуальна основа (NASA TRL, AI pipeline) → [`00_03_AI_Native_Concurrent_Engineering`](00_03_AI_Native_Concurrent_Engineering)
  - Стратегічна дорожня карта та TRL матриця → [`09_02_Strategic_Roadmap_and_TRL_Matrix`](09_02_Strategic_Roadmap_and_TRL_Matrix)
  - GitHub Projects автоматизація → [`09_03_GitHub_Projects_and_Ops_Automation`](09_03_GitHub_Projects_and_Ops_Automation)

---

## 🛑 Блокери

- **Context Drift:** Ризик розсинхронізації між кодом та документацією. Вимагає суворого дотримання протоколу "Wiki-First".
- **Hardware Lead Times:** Затримки у виробництві титанових анкерів обмежують швидкість валідації натурних випробувань.

---

## ⚡ 1. Методологія Shape Up (6+2 Cycle)

Gaia 2.0 відмовляється від класичного Agile на користь 8-тижневих циклів для забезпечення глибокого інженерного фокусу:

- **Build Cycle (6 тижнів):** Робота над "Великими Ставками" (Big Bets). Команда (люди + AI) ізольована від нових вхідних запитів для виконання складних архітектурних задач.
- **Cool-down (2 тижні):** Період для вільного рефакторингу, виправлення дрібних багів та обов'язкового оновлення Wiki (SSOT).
- **Betting Table:** Фаза прийняття рішень Архітектором щодо наступного циклу на основі поточних рівнів TRL.

---

## 🤖 2. Роль AI-агентів та MCP (Model Context Protocol)

AI-агенти розглядаються як автономні інженерні одиниці, що діють у межах SSOT:

- **Intent-First Development:** Перехід від написання коду до формування наміру. Код є лише похідним результатом якісно описаної специфікації в Wiki.
- **Context Anchoring:** Перед початком сесії AI-агент (Cursor/Windsurf) зобов'язаний проіндексувати відповідні сторінки Wiki через MCP для запобігання галюцинаціям.
- **Agent Handoff Protocol:** Ланцюжок передачі: Архітектор (Візія) ➔ Gemini (Shaping/Специфікація) ➔ Wiki (SSOT) ➔ Cursor (Імплементація) ➔ Лабораторія ЧНУ (Фізична валідація).

---

## 🔄 3. Три паралельні потоки (The Triple Stream)

Розробка відбувається синхронно у трьох вимірах, що дозволяє уникнути простоїв софтової команди під час очікування заліза:

1. **Hardware Stream (Atoms):** Дизайн гіроїдних структур, друк Ti-6Al-4V, випробування біосумісності.
2. **Logic Stream (Bytes):** Розробка Rails-сервісів, Edge AI моделей та логіки Атрактора Лоренца.
3. **Verification Stream (Proofs):** Генерація ZK-доказів (IoTeX), налаштування DID (peaq) та оракулів (Chainlink).

---

## 📊 4. Управління через TRL-Ready Issues

Кожна задача в GitHub Projects маркується рівнем TRL. Задача не вважається закритою, доки її програмна реалізація не буде підтверджена фізичними даними або результатами лабораторних тестів, описаних у Модулі 08.

---

## 🎯 5. Shape Up Cycle Template (OPS.3)

Цей розділ — операційний template для запуску 6+2 циклу. Він покриває: (a) формат "shaping" документу, (b) Betting Table процедуру, (c) cool-down checklist. Cross-ref: `docs/10_02` OPS.3, `docs/09_03` §6 (kanban-mapping 4 кластерів).

### 5.1 Кадрова організація: 4 R&D кластери

Розподіл 25+ паралельних задач між 8+ науковцями реалізовано через **чотири кластери**. Кожна Big Bet прив'язується до одного кластера у момент betting table (детальне визначення кожного кластера + GitHub label conventions — у `09_03` §6).

| Кластер | Фокус | Приклади доменів | Базова команда |
|---------|-------|-------------------|-----------------|
| **A — Hardware / EBFC** | Атоми: матеріали, friction-fit, біопаливний елемент, гідрогелі | EBFC catalyst R&D, Ti-6Al-4V DMLS, pull-out test, біосумісність | ChNU FOTIUS + ChDTU mat. eng. |
| **B — Verification / Math** | Докази: атрактор Лоренца, ZK-proof, dual-computation integrity | Lorenz parameters, IoTeX W3bstream, peaq DID schemes | ChNU math/CS + ChIPB |
| **C — Scaling / Cloud** | Software: Rails core, blockchain, infrastructure, Sidekiq queues | Akash deploy, multi-chain web3, Prometheus, Solid Cable | Architect + AI agents |
| **D — Compliance / Legal** | Юриспруденція: KYC/ERC-3643, MSA, IP, регуляторика | Hadron compliance, СЄУ MSA, Verra методологія | СЄУ (Аблязов) + UNI.8 |

### 5.2 Build Cycle (6 тижнів): структура

```
Week 0 (Betting Table, ≤4 год) — рішення які Big Bets входять у цикл
Week 1-2 (Discovery) — shaping documents до "fat marker sketch" рівня
Week 3-4 (Build) — основна імплементація, перші demo
Week 5    (Hill chart) — кожна Big Bet проходить middle line; ризики уточнюються
Week 6    (Closing) — feature freeze, integration testing, doc оновлення
Week 7-8 (Cool-down, 2 тижні) — рефакторинг, SSOT-аудит, наступний betting prep
```

Для кожного циклу створюється milestone у GitHub `Cycle YYYY.QN` (приклад: `Cycle 2026.Q2`) і прив'язується до карток Projects V2 у Big-Bet статусі.

### 5.3 Shaping Document Template

Кожна Big Bet перед потраплянням на Betting Table має `shaping/<slug>.md` (у `docs/`, або у RFC-репо). Формат:

```markdown
# Shape: <назва Big Bet> [cluster A/B/C/D]

## Problem (1-2 параграфи)
Конкретна болячка з даних: метрика, інцидент, або blocker (з `docs/10_02`).
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

### 5.4 Betting Table процедура

Betting Table — `≤4 години` event у Week 0 кожного 8-тижневого циклу. Учасники: Архітектор, представник кожного активного кластера (A/B/C/D), AI-agent з access до `docs/` SSOT.

**Pre-bet checklist (👤 Architect, за тиждень до Betting Table):**

- [ ] Список усіх відкритих `shaping/*.md` зведено у короткий бриф (одна сторінка на bet).
- [ ] Поточний `docs/10_02_Action_Plan_Tracker.md` оновлено: P0/P1 не закриті задачі винесені у обов'язкові nominees.
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
| 6. Кодифікація рішень | 30 хв | AI-agent | PR з оновленим `docs/10_02` + `docs/09_01` milestone link |

**Рішення для кожного shape:**
- **Bet** — потрапляє в цикл, прив'язується до кластера + `Cycle YYYY.QN` milestone.
- **Park** — shape залишається, але не в цьому циклі (review через 6+ тижнів).
- **Drop** — закрити shape з reason; не повертатися без перепакування.

**Anti-patterns на Betting Table:**

- ❌ "Майже готово, давайте дотягнемо у наступному циклі" — нi. Якщо не закрилось — Drop або повний re-shape.
- ❌ Більше 6 Bets на 4 кластери — приймай менше, не розпорошуй людей.
- ❌ Один кластер забирає >2 Big Bets — це сигнал, що інші кластери знесилені; resort cluster routing.

### 5.5 Cool-down (2 тижні) — обов'язкові пункти

Cool-down — не "відпустка", а інвестиція у SSOT-цілісність. Без цього система втрачає synchronicity між кодом і документами.

- [ ] **SSOT drift audit** для змінених модулів циклу: code-vs-doc diff проти `docs/04_02` §13b (Drift Register), `docs/04_03`, `docs/05_02`, `docs/06_02`.
- [ ] Закриті cycle issues анотувати TRL advancement (через `trl_sync.yml` — авто).
- [ ] Bug-bash: 1-2 дні фікс bugs, які накопичились але були "не critical".
- [ ] Refactor: тільки якщо явно покращує цикл наступного betting (наприклад, виносимо повторюваний код у service, який повинні юзати 2+ нові bets).
- [ ] Підготовка shaping documents до наступного Betting Table.
- [ ] Update `docs/09_02_Strategic_Roadmap_and_TRL_Matrix.md`: фактичні TRL зрушення проти прогнозованих.

### 5.6 Cross-ref

- `docs/09_03` §6 — kanban-mapping 4 кластерів у GitHub Projects V2 + label conventions.
- `docs/10_02` OPS.3 — оригінальний задачний контекст + alignment з Convolution Method (10× / 100× speedup PN-state explosion).
- `docs/10_02` OPS.4 — академічний календар, `Academic Semester` field у Projects V2 (cross-cuts з cluster routing).
- `docs/08_01` §1.1-1.3 — стратегічні підстави для multi-cluster R&D.
