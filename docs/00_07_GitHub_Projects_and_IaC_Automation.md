# 00_07: GitHub Projects and IaC Automation

## 🎯 Мета

Звести когнітивне навантаження на Архітектора до нуля шляхом автоматизації рутинних процесів через **Infrastructure-as-Code**. Labels, fields, workflows та routing — все живе у репозиторії як `.yml` файли, а не як ручні чек-листи. SSOT — лише `.github/labels.yml`, `.github/labeler.yml`, `.github/workflows/*.yml` та цей документ.

Ключові компоненти автоматизації:
- **TRL Auto-Advancement:** Автоматична синхронізація рівнів зрілості технологій при завершенні циклів (Shape Up, [`00_05`](00_05_Shape_Up_Operations_and_RnD_Clusters)).
- **SSOT Integrity Guard:** Жорстка прив'язка коду до архітектурної документації (Wiki).
- **Parallel Workload Matrix:** Візуальний поділ потоків між фізичними (Лабораторія / Завод) та цифровими (ШІ) агентами.
- **Labels-as-Code:** `.github/labels.yml` + GitHub Actions workflow синхронізує лейбли при кожному push.

---

## ✅ Статус

- **Поточний TRL:** TRL 7 — CI/CD пайплайн TRL Auto-Advancement на стадії впровадження.
- **Пов'язані модулі:**
  - AI-Native методологія (philosophy) → [`00_04_AI_Native_Engineering_and_TRL`](00_04_AI_Native_Engineering_and_TRL)
  - Shape Up operations → [`00_05_Shape_Up_Operations_and_RnD_Clusters`](00_05_Shape_Up_Operations_and_RnD_Clusters)
  - Стратегічна дорожня карта → [`00_06_Strategic_Roadmap_and_HIL_Simulators`](00_06_Strategic_Roadmap_and_HIL_Simulators)
  - Деплой та CI/CD → [`06_01_Deployment_Kamal_Terraform`](06_01_Deployment_Kamal_Terraform)

---

## ⚙️ 1. Налаштування GitHub Projects V2

### 1.1 Custom Fields (SSOT)

| Поле | Тип | Опис / Функція |
| :--- | :--- | :--- |
| **Current TRL** | Single Select | Поточний рівень (**1-9**, NASA/ISO 16290 — лише технологічна готовність) згідно з [`00_04 §1`](00_04_AI_Native_Engineering_and_TRL). Головна колонка на дошці "Матриця TRL". |
| **Target TRL** | Single Select | Цільовий рівень (**1-9**) для поточного циклу. TRL НЕ розширюється до «10-12» (це нестандартно). |
| **Readiness Horizon** | Single Select | Beyond-TRL-9 R&D-епіки ([`00_04 §1`](00_04_AI_Native_Engineering_and_TRL), [`00_06 §7`](00_06_Strategic_Roadmap_and_HIL_Simulators)): **SRL** (System Readiness — forest-level emergence, edge self-evolution, cross-biome generalization, AI-adversarial security) стадії `SRL:Concept` / `SRL:Pilot` / `SRL:Deployed`, та **MRL** (Manufacturing Readiness, `MRL:8/9/10` — серійний друк 5 SKU). |
| **Assigned Agent** | Single Select | Виконавець: `Architect`, `AI Agent`, `Lab (ChNU)`, `Factory`, `nTop Expert`. |
| **Module** | Single Select | Компонент екосистеми (наприклад, `04: Server Core`). Формує Swimlanes. |
| **Appetite** | Single Select | `Small Batch` (1-2w) або `Big Bet` (6w) згідно з методологією Shape Up. |
| **SSOT Link** | URL | Пряме посилання на сторінку Wiki або звіт (Лабораторна валідація). |
| **R&D Cluster** | Single Select | Primary кластер відповідальності | `A — Hardware/EBFC`, `B — Verification/Math`, `C — Scaling/Cloud`, `D — Compliance/Legal`, `Cross-cluster` |
| **Shape Up Stage** | Single Select | Стадія всередині 8-тижневого циклу | `Shaping`, `Bet (active)`, `Building`, `Hill (uphill)`, `Hill (downhill)`, `Park`, `Drop`, `Done` |
| **Cycle** | Single Select | Cycle milestone (формат `YYYY.QN`) | `Cycle 2026.Q2`, `Cycle 2026.Q3`, … |
| **Academic Semester** | Single Select | Прив'язка до семестру партнерських ВНЗ | `Fall 2025-2026`, `Spring 2025-2026`, `Fall 2026-2027`, … |

### 1.2 Створення полів через GitHub CLI (IaC)

> Замість ручного клікання у Projects V2 UI, поля створюються скриптом `bin/setup_github_project.sh` (планований). Поточний gh CLI не підтримує `project add-field` повністю — workaround через GraphQL.

```bash
# bin/setup_github_project.sh — заплановано як частина IaC bootstrap
PROJECT_ID="PVT_xxxx"  # отримати через `gh project list --owner Alexey-Lukin --format json`

# Single-select option sets (SSOT — синхронізувати з §1.1 та lib/github_bootstrap.rb)
TRL_OPTIONS=(TRL:1 TRL:2 TRL:3 TRL:4 TRL:5 TRL:6 TRL:7 TRL:8 TRL:9)
# ↑ Шкала 1-9 (NASA/ISO 16290). TRL НЕ розширюється до 10-12 (00_04 §1).
READINESS_HORIZON_OPTIONS=(SRL:Concept SRL:Pilot SRL:Deployed MRL:8 MRL:9 MRL:10)
# ↑ Beyond TRL 9 = окремий вимір SRL/MRL (00_04 §1, 00_06 §7), не "TRL 10-12".

for FIELD in "Current TRL" "Target TRL" "Readiness Horizon" "Assigned Agent" "Module" "Appetite" "R&D Cluster" "Shape Up Stage" "Cycle" "Academic Semester"; do
  echo "Ensuring field: $FIELD"
  # gh api graphql -f query='mutation { addProjectV2Field(...) }'
  # Для Current TRL / Target TRL передавати TRL_OPTIONS[@] як SingleSelect options.
done
```

---

## ⚙️ 2. Автоматизація через GitHub Actions

### 2.1 Workflow Inventory

| Workflow | Файл | Тригер | Статус |
|----------|------|--------|--------|
| TRL Auto-Advancement | `.github/workflows/trl_sync.yml` | `issues: [closed]` | ✅ Реалізовано (OPS.1; чекає `PROJECT_PAT` secret) |
| Labels Sync (IaC) | `.github/workflows/labels_sync.yml` | `push` на `.github/labels.yml` | ✅ Реалізовано |
| PR Auto-Labeler | `.github/workflows/labeler.yml` | `pull_request` | ✅ Реалізовано |
| SSOT Integrity Guard | `.github/workflows/ssot_guard.yml` | `pull_request` | ✅ Реалізовано (OPS.2; semantic `type:*` bypass — §2.3) |
| Solidity Audit | `.github/workflows/solidity_audit.yml` | `push` / PR з `contracts/**` | ✅ Реалізовано |
| CoAP Smoke Test | `.github/workflows/coap_smoke.yml` | `workflow_dispatch` / `workflow_call` від `deploy.yml` | ✅ Реалізовано (INF.6 post-deploy gate) |
| In-silico L2 Smoke | `.github/workflows/in_silico_smoke.yml` | `pull_request` / `push` з path-filter `tools/in_silico/**`, `docs/protocols/ebfc/in_silico/**` | ✅ Реалізовано (Zero-Lab L2 engine gate; CPU-only via `SILKEN_FORCE_PLATFORM=CPU`, micromamba env cache, не гейтить деплой) |

### 2.2 Протокол "TRL Auto-Advancement" (`trl_sync.yml`)

Автоматизує рух карток по матриці готовності технологій.

- **Тригер:** `issues: types: [closed]`
- **Умова:** Завдання закрите (Done).
- **Дія:** GraphQL скрипт зчитує значення поля `Target TRL` закритого Issue і перезаписує ним значення `Current TRL` на дошці Project V2. Картка автоматично "перелітає" у нову колонку. Додатково: обчислює `completion_semester` із `closed_at` (UTC) — записує `Academic Semester` опцію.
- **Авторизація:** Здійснюється через спеціальний токен Архітектора (`secrets.PROJECT_PAT`).

```yaml
# .github/workflows/trl_sync.yml — skeleton
name: TRL Auto-Advancement
on:
  issues:
    types: [closed]
jobs:
  sync_trl:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Advance TRL on Project V2
        env:
          GH_TOKEN: ${{ secrets.PROJECT_PAT }}
          PROJECT_NUMBER: 1
          OWNER: Alexey-Lukin
        run: bin/ci/trl_sync.rb ${{ github.event.issue.number }}
```

### 2.3 Протокол "SSOT Integrity Guard" (`ssot_guard.yml`)

Автоматична перевірка актуальності документації (The Codex).

- **Умова:** Pull Request вносить зміни в `app/models/`, `app/services/`, `firmware/` або `contracts/`.
- **Дія:** Action перевіряє наявність відповідних змін у папці `docs/` (або заповненого поля `SSOT Link` у linked issue). Мердж блокується, якщо документація не оновлена.
- **Bypass:** PR із semantic-label з whitelist (`type:bugfix`, `type:refactor`, `type:chore`, `type:deps`, `type:perf`, `type:test`) автоматично пропускається — ці зміни не змінюють архітектуру. Не-архітектурний характер змін підтверджується явним вибором label автором PR (форс-функція: автор зобов'язаний класифікувати зміну, а не просто додавати порожній коміт у `docs/`).

> **Чому семантичні label замість `skip-ssot-guard`:** Generic skip-label буде зловживатись (натиснув-обійшов). Семантичні `type:*` змушують автора публічно класифікувати зміну. Якщо PR має `type:bugfix`, але насправді міняє схему — code reviewer одразу побачить mismatch у заголовку та назві label.

```yaml
# .github/workflows/ssot_guard.yml
name: SSOT Integrity Guard
on:
  pull_request:
    paths:
      - 'app/models/**'
      - 'app/services/**'
      - 'firmware/**'
      - 'contracts/**'
jobs:
  guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }

      - name: Check bypass labels
        id: bypass
        env:
          LABELS: ${{ toJson(github.event.pull_request.labels.*.name) }}
        run: |
          # Whitelist non-architectural change types
          BYPASS_LABELS="type:bugfix type:refactor type:chore type:deps type:perf type:test"
          for label in $BYPASS_LABELS; do
            if echo "$LABELS" | grep -q "\"$label\""; then
              echo "✅ Bypass: PR has label '$label' — non-architectural change, SSOT update not required."
              echo "skip=true" >> $GITHUB_OUTPUT
              exit 0
            fi
          done
          echo "skip=false" >> $GITHUB_OUTPUT

      - name: Check docs/ changes
        if: steps.bypass.outputs.skip == 'false'
        run: |
          BASE=${{ github.event.pull_request.base.sha }}
          HEAD=${{ github.event.pull_request.head.sha }}
          CODE_CHANGED=$(git diff --name-only $BASE $HEAD | grep -E '^(app|firmware|contracts)/' | wc -l)
          DOCS_CHANGED=$(git diff --name-only $BASE $HEAD | grep -E '^docs/' | wc -l)
          if [ "$CODE_CHANGED" -gt 0 ] && [ "$DOCS_CHANGED" -eq 0 ]; then
            echo "❌ Code changed but no docs/* updated."
            echo ""
            echo "Either:"
            echo "  (a) Update relevant SSOT file in docs/, or"
            echo "  (b) Add one of: type:bugfix, type:refactor, type:chore, type:deps, type:perf, type:test"
            echo "      if this PR genuinely does not alter architecture."
            exit 1
          fi
```

**Whitelist `type:*` labels потрібно додати у `.github/labels.yml`** як частину Labels-as-Code SSOT (див. §2.5). Запропоновані визначення:

| Label | Колір | Семантика |
|-------|-------|-----------|
| `type:bugfix` | `#D73A4A` | Виправлення дефекту без зміни архітектури/контрактів |
| `type:refactor` | `#A2EEEF` | Рефакторинг (renaming, extract method, без зміни поведінки) |
| `type:chore` | `#CFCFCF` | Build/CI/tooling зміни (Gemfile bump, .github maintenance) |
| `type:deps` | `#0366D6` | Bump dependency versions (Gemfile.lock, package.json) |
| `type:perf` | `#FFAA33` | Оптимізація без зміни функціональної семантики |
| `type:test` | `#0E8A16` | Додавання/корекція тестів без зміни production code |

### 2.4 Протокол "Solidity Audit" (`solidity_audit.yml`) ✅

Автоматизована перевірка та аудит смарт-контрактів Solidity (6 контрактів: SCC, SFC, StateRootAnchor, SilkenGovernor, SilkenTimelock, ProtocolParameters).

- **Тригер:** Push до `main` або PR з змінами у `contracts/**`
- **Job 1: Foundry Tests & Coverage** (`foundry-tests`, timeout: 15 хв):
  - `npm ci` → `forge build --sizes` → `forge test -vvv --gas-report` → `forge coverage --ir-minimum --report lcov --report summary`
  - Coverage artifact: `lcov.info` (retention 14 днів)
- **Job 2: Slither Static Analysis** (`slither`, timeout: 10 хв):
  - `crytic/slither-action@v0.4.0`, solc 0.8.28, `fail-on: high`
- **Конфігурація Foundry** (`contracts/foundry.toml`):
  - solc 0.8.28, EVM cancun, optimizer 200 runs (default), 1000 runs (production profile)
  - Gas reports: SCC, SFC, StateRootAnchor, SilkenGovernor, SilkenTimelock, ProtocolParameters
  - Fuzz: 512 runs (default), 256 (ci profile). Invariant: 128 runs, depth 64
- **Тестове покриття:** 171 тест у 6 test suites (`contracts/test/*.t.sol`)

### 2.5 Labels Sync (IaC) — `.github/labels.yml` + `labels_sync.yml`

> **Чому Labels-as-Code:** ручні інструкції типу "створи 12 лейблів через UI" — це не автоматизація. Файл `.github/labels.yml` — SSOT; workflow `labels_sync.yml` синхронізує лейбли при кожному push, що змінює цей файл. Видалення лейбла з YAML → автоматичне видалення з репозиторію (з `delete: true` опцією).

```yaml
# .github/workflows/labels_sync.yml — skeleton
name: Labels Sync (IaC)
on:
  push:
    branches: [main]
    paths: ['.github/labels.yml']
  workflow_dispatch:
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: EndBug/label-sync@v2
        with:
          config-file: .github/labels.yml
          delete-other-labels: true
          token: ${{ secrets.GITHUB_TOKEN }}
```

### 2.6 PR Auto-Labeler — `.github/labeler.yml` + `labeler.yml` workflow

Routes PRs автоматично у відповідні кластери на основі шляхів файлів.

```yaml
# .github/labeler.yml — config
'cluster:C-scaling':
  - any: ['app/**', 'config/**', 'lib/**', 'db/**', 'spec/**']
'cluster:D-compliance':
  - any: ['app/services/polygon/hadron_*', 'docs/07_*']
'cluster:A-hardware':
  - any: ['firmware/**', 'docs/01_*', 'docs/02_*', 'docs/08_*']
'cluster:B-verification':
  - any: ['contracts/**', 'app/services/iotex/**', 'app/services/web3/chainlink_router_version*', 'app/services/silken_net/attractor*', 'app/services/silken_net/seed_derivation*']
'cluster-ref:B':
  - any: ['app/services/blockchain_*', 'app/services/celo/**', 'app/services/solana/**']
'module:04-server-core':
  - any: ['app/models/**', 'app/controllers/**', 'app/services/**', 'app/workers/**', 'app/views/**']
'module:03-firmware':
  - any: ['firmware/**']
'module:06-infra':
  - any: ['deploy/**', '.kamal/**', 'terraform/**']
```

```yaml
# .github/workflows/labeler.yml
name: PR Auto-Labeler
on: [pull_request]
jobs:
  label:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/labeler@v5
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}
```

---

## 🗂️ 3. Репозиторії Екосистеми

Кожен репозиторій керується єдиними правилами контекстного управління:

- **silken_net:** Ядро системи (Rails 8.1, PostgreSQL, Sidekiq). Включає смарт-контракти у `contracts/` (Solidity, Foundry toolchain).
- **silken-soldier-fw:** Низькорівнева прошивка (C, mruby) для STM32 та LoRa.
- **silken-contracts:** ⚠️ Архівний. Активні контракти тепер у `silken_net/contracts/` з повним Foundry CI.

---

## 🏷️ 4. Label Conventions (SSOT)

Файл `.github/labels.yml` — Single Source of Truth для всіх лейблів. Будь-яке нове label має бути занесене сюди до використання. Видалення з файла → видаленне з репозиторію через `labels_sync.yml`.

### 4.1 Cluster routing (primary, mutually exclusive)

| Label | Колір (hex) | Семантика |
|-------|-------------|-----------|
| `cluster:A-hardware` | `#FF6B35` (orange) | Primary кластер — Hardware/EBFC |
| `cluster:B-verification` | `#4ECDC4` (teal) | Primary кластер — Verification/Math |
| `cluster:C-scaling` | `#3D5A80` (blue) | Primary кластер — Scaling/Cloud |
| `cluster:D-compliance` | `#7209B7` (purple) | Primary кластер — Compliance/Legal |
| `cluster:cross-cluster` | `#F1E05A` (yellow) | 5-та опція Projects V2 для задач, що **архітектурно не належать** одному кластеру (наприклад, MOIC governance, cross-cluster refactors). Має наступним кроком резолвитись у конкретний primary — або документуватися як свідомо cross-cluster |

### 4.2 Cluster cross-reference (secondary, optional)

| Label | Колір | Семантика |
|-------|-------|-----------|
| `cluster-ref:A` / `cluster-ref:B` / `cluster-ref:C` / `cluster-ref:D` | `#D3D3D3` | Інший кластер, з яким задача має RACI-консультацію |

### 4.3 Shape Up lifecycle

| Label | Колір | Семантика |
|-------|-------|-----------|
| `shape:shaping` | `#FFE066` | Shaping document створюється |
| `shape:bet-active` | `#06D6A0` | Bet у поточному циклі |
| `shape:building` | `#0E8A16` | Активна імплементація (Week 3-4 циклу) |
| `shape:hill-uphill` | `#FFB627` | ще exploration |
| `shape:hill-downhill` | `#06D6A0` | downhill execution |
| `shape:park` | `#9C9C9C` | Park'ed |
| `shape:drop` | `#E63946` | Drop'ped |
| `shape:done` | `#1D76DB` | Завершена Big Bet (закрита у поточному циклі) |

> **Mapping label ↔ Projects V2 field `Shape Up Stage`:** `Shaping → shape:shaping`, `Bet (active) → shape:bet-active`, `Building → shape:building`, `Hill (uphill) → shape:hill-uphill`, `Hill (downhill) → shape:hill-downhill`, `Park → shape:park`, `Drop → shape:drop`, `Done → shape:done`. Label sync — через `trl_sync.yml` (опційне розширення) або вручну при зміні стадії.

### 4.4 Cross-cuts (наявні)

- `priority:P0` / `P1` / `P2` / `P3` (`00_08`)
- `complexity:XS/S/M/L/XL`
- `agent:ai` / `agent:human` / `agent:ops` / `agent:hybrid` _(назви labels без emoji у [`.github/labels.yml`](../.github/labels.yml); emoji `🤖 / 👤 / 🔧 / 🔗` використовуються лише як **візуальні маркери у `00_08`** для swimlane-навігації)_
- `module:00-codex` / `module:01-anchor` / `module:02-capsule` / `module:03-firmware` / `module:04-server-core` / `module:05-ledger` / `module:06-matrix` / `module:07-naas` / `module:08-academic`
- `type:bugfix` / `type:refactor` / `type:chore` / `type:deps` / `type:perf` / `type:test` — **SSOT Guard bypass** (див. §2.3)

---

## ✔️ 5. Верифікація та Критерії Виходу

- **Протокол тестування:** Закриття тестового Issue повинно фізично перемістити його колонку на дошці "Матриця TRL" — без ручного втручання.
- **Критерій Виходу:** Жодного ручного перетягування карток або зміни статусів Архітектором.
- **Критерій IaC:** Жодного ручного клікання у GitHub UI для створення / видалення labels (все через `.github/labels.yml`).
- **Результат валідації:** `[Dashboard: Gaia 2.0 Command Center]` (URL TBD)

---

## 🎯 6. Первинне налаштування репозиторію (Bootstrap)

> Раніше тут був ручний 7-point checklist ("👤 Створити single-select field …"). Замість цього — single script + автоматизовані workflows.

```bash
# bin/bootstrap_github.sh — заплановано
set -euo pipefail

# 1. Створити лейбли з .github/labels.yml
# (виконується автоматично через labels_sync.yml на push)
git push origin main

# 2. Створити Projects V2 fields
bin/setup_github_project.sh

# 3. Створити перший Betting Table milestone
gh api repos/Alexey-Lukin/silken_net/milestones \
  -f title="Cycle 2026.Q2" \
  -f description="First betting cycle after UNI.1 & UNI.8 onboarding"

# 4. Створити baseline shaping documents
mkdir -p docs/shaping
echo "Stub shape for cluster C: First Akash production deploy" > docs/shaping/akash-prod-deploy.md
```

---

## 🔗 7. Cross-ref

- `docs/00_05` §5.2 — Betting Table процедура.
- `docs/00_05` §6 — Academic Semester мапінг.
- `docs/00_08` — open backlog задач (OPS.3 / OPS.4).
- `docs/06_01` — Kamal / Terraform CI integration.
- `docs/04_02 §13b` — Drift Register, який живиться SSOT Integrity Guard результатами.
