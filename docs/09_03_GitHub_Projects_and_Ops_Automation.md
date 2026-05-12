# 09_03: GitHub Projects та Автоматизація Операцій

## 🎯 Мета

Звести когнітивне навантаження на Архітектора до нуля шляхом автоматизації рутинних процесів. Ми використовуємо GitHub Projects V2 як динамічну 2D-матрицю (Swimlanes: Module, Columns: Current TRL), яка в реальному часі відображає еволюцію кіберфізичної системи від концепту до Production.

Ключові компоненти автоматизації:
- **TRL Auto-Advancement:** Автоматична синхронізація рівнів зрілості технологій при завершенні циклів (Shape Up).
- **SSOT Integrity Guard:** Жорстка прив'язка коду до архітектурної документації (Wiki).
- **Parallel Workload Matrix:** Візуальний поділ потоків між фізичними (Лабораторія/Завод) та цифровими (ШІ) агентами.

---

## ✅ Статус

- **Поточний TRL:** TRL 7 — CI/CD пайплайн TRL Auto-Advancement на стадії впровадження
- **Пов'язані модулі:**
  - AI-Native методологія → [`09_01_AI_Native_Concurrent_Engineering`](09_01_AI_Native_Concurrent_Engineering)
  - Стратегічна дорожня карта → [`09_02_Strategic_Roadmap_and_TRL_Matrix`](09_02_Strategic_Roadmap_and_TRL_Matrix)
  - Деплой та CI/CD → [`06_01_Deployment_Kamal_Terraform`](06_01_Deployment_Kamal_Terraform)

---

## ⚙️ 1. Налаштування GitHub Projects V2

| Поле | Тип | Опис / Функція |
| :--- | :--- | :--- |
| **Current TRL** | Single Select | Поточний рівень (1-9). Головна колонка на дошці "Матриця TRL". |
| **Target TRL** | Single Select | Цільовий рівень (1-9) для поточного циклу розробки. |
| **Assigned Agent** | Single Select | Виконавець: `Architect`, `AI Agent`, `Lab (ChNU)`, `Factory`, `nTop Expert`. |
| **Module** | Single Select | Компонент екосистеми (наприклад, `04: Server Core`). Формує Swimlanes. |
| **Appetite** | Single Select | `Small Batch` (1-2w) або `Big Bet` (6w) згідно з методологією Shape Up. |
| **SSOT Link** | URL | Пряме посилання на сторінку Wiki або звіт (Лабораторна валідація). |

## ⚙️ 2. Автоматизація через GitHub Actions

### Протокол "TRL Auto-Advancement" (`trl_sync.yml`)
Автоматизує рух карток по матриці готовності технологій.
* **Тригер:** `issues: types: [closed]`
* **Умова:** Завдання закрите (Done).
* **Дія:** GraphQL скрипт зчитує значення поля `Target TRL` закритого Issue і перезаписує ним значення `Current TRL` на дошці Project V2. Картка автоматично "перелітає" у нову колонку.
* **Авторизація:** Здійснюється через спеціальний токен Архітектора (`secrets.PROJECT_PAT`).

### Протокол "SSOT Integrity Guard"
Автоматична перевірка актуальності документації (The Codex).
* **Умова:** Pull Request вносить зміни в `app/models/` або ядро прошивки.
* **Дія:** Action перевіряє наявність відповідних змін у папці `docs/wiki/` (або заповненого поля SSOT Link). Мердж блокується, якщо документація не оновлена.

### Протокол "Solidity Audit" (`solidity_audit.yml`) ✅
Автоматизована перевірка та аудит смарт-контрактів Solidity (6 контрактів: SCC, SFC, StateRootAnchor, SilkenGovernor, SilkenTimelock, ProtocolParameters).
* **Тригер:** Push до `main` або PR з змінами у `contracts/**`
* **Job 1: Foundry Tests & Coverage** (`foundry-tests`, timeout: 15 хв):
  - `npm ci` → `forge build --sizes` → `forge test -vvv --gas-report` → `forge coverage --ir-minimum --report lcov --report summary`
  - Coverage artifact: `lcov.info` (retention 14 днів)
* **Job 2: Slither Static Analysis** (`slither`, timeout: 10 хв):
  - `crytic/slither-action@v0.4.0`, solc 0.8.28, `fail-on: high`
* **Конфігурація Foundry** (`contracts/foundry.toml`):
  - solc 0.8.28, EVM cancun, optimizer 200 runs (default), 1000 runs (production profile)
  - Gas reports: SCC, SFC, StateRootAnchor, SilkenGovernor, SilkenTimelock, ProtocolParameters
  - Fuzz: 512 runs (default), 256 (ci profile). Invariant: 128 runs, depth 64
* **Тестове покриття:** 171 тест у 6 test suites (`contracts/test/*.t.sol`)

## 🗂️ 3. Репозиторії Екосистеми
Кожен репозиторій керується єдиними правилами контекстного управління:
* **silken_net:** Ядро системи (Rails 8.1, PostgreSQL, Sidekiq). Включає смарт-контракти у `contracts/` (Solidity, Foundry toolchain).
* **silken-soldier-fw:** Низькорівнева прошивка (C, mruby) для STM32 та LoRa.
* **silken-contracts:** ⚠️ Архівний. Активні контракти тепер у `silken_net/contracts/` з повним Foundry CI.

## ✔️ 4. Верифікація та Критерії Виходу
* **Протокол тестування:** Закриття тестового Issue повинно фізично перемістити його колонку на дошці "Матриця TRL".
* **Критерій Виходу:** Жодного ручного перетягування карток або зміни статусів Архітектором.
* **Результат валідації:** [Dashboard: Gaia 2.0 Command Center]

---

## 🎓 5. Академічний календар ↔ TRL milestones (OPS.4)

### 5.1 Чому це окремий вимір

TRL-матриця крокує "квартально-функціональним" темпом, але UNI.* партнери (ChNU FOTIUS, ChDTU, ChIPB, ChMA, СЄУ) працюють по **академічних семестрах**. Без явного мапінгу milestone deadlines зміщуються відносно дат захисту магістерських / дипломних робіт, а Shape Up betting table (OPS.3) не може коректно "приклеїти" Big Bet до семестру, в якому фактично виконуватиметься R&D-частина.

Тому в Projects V2 додано **окремий single-select field `Academic Semester`** — він не замінює `Target TRL`, а доповнює його: на дошці видно і коли працювали, і *до якого академічного циклу* робота прив'язана.

### 5.2 Мапінг семестрів (Україна, ChNU/ChDTU convention)

| Період (включно) | Семестр | Назва опції в Projects V2 |
| :--- | :--- | :--- |
| 1 вересня — 31 січня | Осінній (Fall) | `Fall {Y}-{Y+1}` (наприклад, `Fall 2025-2026` для дат у вересні 2025 — січні 2026) |
| 1 лютого — 30 червня | Весняний (Spring) | `Spring {Y-1}-{Y}` (наприклад, `Spring 2025-2026` для дат у лютому — червні 2026) |
| 1 липня — 31 серпня | Літня перерва | приклеюється до наступного `Fall {Y}-{Y+1}` (R&D-робота, закрита у липні-серпні, рахується підготовкою до осіннього семестру) |

> Назва опції завжди використовує формат «академічний рік», `{Y}-{Y+1}` — щоб і Fall, і наступний Spring мали одне посилання (наприклад, дипломні роботи захисту червня 2026 повністю всередині `Spring 2025-2026`).

### 5.3 Мапінг TRL milestones ↔ семестр

| TRL | Очікуваний семестр | Академічний deliverable | Прив'язка |
| :--- | :--- | :--- | :--- |
| TRL 4-5 (lab validation) | Fall (вересень — січень) | Лабораторні протоколи, перший draft публікації | UNI.1 / UNI.5 декан ChNU FOTIUS |
| TRL 5-6 (relevant environment) | Spring (лютий — травень) | Магістерські та дипломні **захисти у червні** | UNI.13 / UNI.14 верифікація науковців |
| TRL 6-7 (pilot deploy) | Літня перерва + Fall | Pilot installation, conference paper draft | UNI.8 СЄУ MSA |
| TRL 7-8 (operational) | Spring | Peer-reviewed публікація | UNI.* IP strategy (08_03) |

> Фінальні захисти у червні — **hard deadline** для TRL freeze поточного циклу. Будь-яка картка з `Target TRL ≥ 6` повинна бути закрита **до 15 червня**, інакше прив'язка зсувається у `Fall {Y}-{Y+1}`.

### 5.4 Автоматизація (`trl_sync.yml` extension)

При кожному `issues.closed`, поряд із копіюванням `Target TRL → Current TRL`, скрипт також:

1. Обчислює `completion_semester` із `closed_at` (UTC) за таблицею 5.2.
2. Шукає у проекті single-select поле з ім'ям `Academic Semester`.
3. Якщо поле існує і має опцію з відповідним ім'ям — записує її через `updateProjectV2ItemFieldValue`.
4. Якщо поле відсутнє або потрібна опція не створена — пише **warning** і завершується успіхом (TRL sync не повинен ламатися). Опції створюються один раз вручну при налаштуванні дошки (наприклад, `Fall 2025-2026`, `Spring 2025-2026`, `Fall 2026-2027`, … на 3-5 років наперед).

Це означає що:

* **TRL Auto-Advancement** залишається первинним інваріантом і не залежить від наявності поля.
* **Academic Semester** — опціональний шар спостережуваності: якщо адміністратор не створив поле/опції, ніщо не зламається.
* **Не записується "Current Semester"** — це окрема задача (потребує `schedule:` cron на 1 вересня / 1 лютого і пише в project-level field, не в item). Свідомо винесено за межі цього циклу.

---

## 🗂️ 6. Kanban-mapping: 4 R&D кластери у Projects V2 (OPS.3)

Цей розділ — операційний дизайн дошки для multi-cluster routing задач Shape Up циклу (детальна методологія: `09_01` §5). Мета — щоб Архітектор за 5 секунд бачив у Projects V2 (а) кому належить задача, (б) у якому кластері R&D вона живе, (в) чи це Big Bet у поточному циклі чи park'ed shape.

### 6.1 Чотири кластери — визначення

| Кластер | Сфера відповідальності | Типові epic-домени | Базова команда |
|---------|-------------------------|---------------------|-----------------|
| **A — Hardware / EBFC** | Атоми, фізика, матеріали, біопаливний елемент | EBFC catalyst R&D, Ti-6Al-4V DMLS, EDLC supercap MPPT, friction-fit pull-out, біосумісність, BIO.* sterilization | ChNU FOTIUS (декан, біохімія), ChDTU materials, ChIPB safety |
| **B — Verification / Math** | Докази, математика, верифікація, ZK | Lorenz attractor params, IoTeX W3bstream, peaq DID schemes, Chainlink Functions, dual-computation integrity, Solidity governance | ChNU math/CS, ChIPB cryptography, AI agents (theorem proving) |
| **C — Scaling / Cloud** | Software stack, infrastructure, performance | Rails core (04_02), multi-chain web3 (12 chains), Akash deploy (06_02), Prometheus/Grafana, Sidekiq queues, Solid Cable, Phlex UI | Architect + AI agents (Copilot, Cursor) |
| **D — Compliance / Legal** | Юриспруденція, регуляторика, IP, B2B | Polygon Hadron (ERC-3643), MSA з СЄУ, Verra / Gold Standard методологія, GDPR / ESG звітність, patent portfolio | СЄУ (Аблязов), UNI.8, external advisors |

> **Принцип взаємовиключності:** кожна задача має **рівно один primary cluster label** (`cluster:A` / `cluster:B` / `cluster:C` / `cluster:D`). Cross-cluster задачі мають **secondary label** (наприклад, primary `cluster:C` + secondary `cluster:B` для voting power Solidity audit). Primary cluster визначає, хто веде задачу на betting table; secondary — кого консультують у RACI-режимі.

### 6.2 Projects V2 fields — додавання до існуючих

До existing fields (`Current TRL`, `Target TRL`, `Assigned Agent`, `Module`, `Appetite`, `SSOT Link`, `Academic Semester`) додаються:

| Поле | Тип | Опис | Опції |
|------|-----|------|-------|
| **R&D Cluster** | Single Select | Primary кластер відповідальності | `A — Hardware/EBFC`, `B — Verification/Math`, `C — Scaling/Cloud`, `D — Compliance/Legal`, `Cross-cluster` (тимчасово, до allocation) |
| **Shape Up Stage** | Single Select | Стадія всередині 8-тижневого циклу | `Shaping`, `Bet (active)`, `Building`, `Hill (uphill)`, `Hill (downhill)`, `Park`, `Drop`, `Done` |
| **Cycle** | Single Select | Cycle milestone (формат `YYYY.QN`) | `Cycle 2026.Q2`, `Cycle 2026.Q3`, …; backlog без cycle присвоєння |

### 6.3 GitHub Label Conventions

Labels у issue-репозиторії (бо Projects V2 не показуються у API-консьюмерах типу `gh issue list`). SSOT — `docs/09_03` §6.3 (цей розділ). Кожне нове label має бути занесено сюди до використання.

**Cluster routing (primary, mutually exclusive):**

| Label | Колір (hex) | Семантика |
|-------|-------------|-----------|
| `cluster:A-hardware` | `#FF6B35` (orange) | Primary кластер — Hardware/EBFC |
| `cluster:B-verification` | `#4ECDC4` (teal) | Primary кластер — Verification/Math |
| `cluster:C-scaling` | `#3D5A80` (blue) | Primary кластер — Scaling/Cloud |
| `cluster:D-compliance` | `#7209B7` (purple) | Primary кластер — Compliance/Legal |

**Cluster cross-reference (secondary, optional):**

| Label | Колір | Семантика |
|-------|-------|-----------|
| `cluster-ref:A` / `cluster-ref:B` / `cluster-ref:C` / `cluster-ref:D` | `#D3D3D3` (light grey) | Інший кластер, з яким задача має RACI-консультацію |

**Shape Up lifecycle:**

| Label | Колір | Семантика |
|-------|-------|-----------|
| `shape:shaping` | `#FFE066` (yellow) | Shaping document створюється, не на betting table |
| `shape:bet-active` | `#06D6A0` (green) | Bet у поточному циклі (паралельно `Cycle` field) |
| `shape:hill-uphill` | `#FFB627` (gold) | Hill chart: ще exploration, риски не вирішені |
| `shape:hill-downhill` | `#06D6A0` | Hill chart: рутина, downhill execution |
| `shape:park` | `#9C9C9C` (grey) | Park'ed — review через >6 тижнів |
| `shape:drop` | `#E63946` (red) | Drop'ped (closed з причиною, не resurrect без re-shape) |

**Cross-cuts з існуючим:**

- `priority:P0` / `P1` / `P2` / `P3` — наявні (`10_02`).
- `complexity:XS/S/M/L/XL` — наявні.
- `agent:🤖 ai` / `agent:👤 human` / `agent:🔧 ops` / `agent:🔗 hybrid` — наявні (`10_02` emoji convention).
- `module:04-server-core` / `module:03-firmware` / `module:06-infra` / etc. — відповідає `Module` Project field.

### 6.4 Routing rules (PR labeler / auto-assign)

Опціональна автоматизація через `.github/labeler.yml` + `actions/labeler@v5`:

- PR на `app/services/blockchain_*`, `app/services/celo/`, `app/services/solana/`, `app/services/iotex/`, `contracts/**` → auto-label `cluster:C-scaling` + `cluster-ref:B`.
- PR на `app/services/polygon/hadron_*`, `docs/07_*` → auto-label `cluster:D-compliance`.
- PR на `firmware/**` → auto-label `cluster:A-hardware` (наявний firmware repo окремий, але silken_net має `firmware/bio_contracts/`, тому правило застосовне і тут) + `cluster-ref:B`.
- PR на `docs/04_*`, `docs/05_*`, `docs/06_*` → auto-label `cluster:C-scaling`.
- PR на `docs/08_*` → `cluster:A-hardware` (Module 08 — академічна валідація).
- PR на `docs/07_*` → `cluster:D-compliance`.

> Auto-labels — лише **suggestion**. Архітектор на betting table може переоприсати primary cluster, якщо routing rule зачіпає cross-cluster задачу.

### 6.5 Перший betting cycle — checklist

OPS.3 чекбокс 👤 (`Перший betting cycle після UNI.1 (декан) та UNI.8 (СЄУ)`) — підготовка:

- [ ] 👤 Створити 4 single-select опції у Projects V2 field `R&D Cluster` (точні назви + кольори з §6.2).
- [ ] 👤 Створити single-select field `Shape Up Stage` (опції з §6.2).
- [ ] 👤 Створити single-select field `Cycle` (заздалегідь додати `Cycle 2026.Q2`, `Cycle 2026.Q3`, `Cycle 2026.Q4`).
- [ ] 👤 Додати у repo labels з §6.3 (через `gh label create` або UI).
- [ ] 👤 Опціонально: створити `.github/labeler.yml` з правилами §6.4.
- [ ] 👤 UNI.1 (декан ChNU FOTIUS) confirms cluster A team membership.
- [ ] 👤 UNI.8 (СЄУ Аблязов) confirms cluster D team membership.
- [ ] 👤 Архітектор створює перший batch shaping documents (cluster C — найбільший backlog у `10_02`).
- [ ] 👤 Перший Betting Table session: дата + agenda за `09_01` §5.4.

### 6.6 Cross-ref

- `docs/09_01` §5 — повна Shape Up методологія + Betting Table процедура.
- `docs/09_03` §5 — академічний календар (Academic Semester field — cross-cuts з cluster routing).
- `docs/10_02` OPS.3 — оригінальна задача.
- `docs/08_01` §1.1-1.3 — стратегічні підстави для cluster decomposition.
