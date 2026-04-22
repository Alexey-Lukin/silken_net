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
