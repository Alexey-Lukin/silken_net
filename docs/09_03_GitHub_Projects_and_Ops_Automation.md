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
