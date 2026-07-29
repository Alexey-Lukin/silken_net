# 00_05: GitHub Projects and IaC Automation

## 🎯 Мета

Звести когнітивне навантаження на Архітектора до нуля шляхом автоматизації рутинних процесів через **Infrastructure-as-Code**. Labels, fields, workflows та routing — все живе у репозиторії як `.yml` файли, а не як ручні чек-листи. SSOT — лише `.github/labels.yml`, `.github/labeler.yml`, `.github/workflows/*.yml` та цей документ.

Ключові компоненти автоматизації:
- **TRL Auto-Advancement:** Автоматична синхронізація рівнів зрілості технологій при завершенні циклів (Shape Up, [`00_04`](00_04_Shape_Up_Operations_and_RnD_Clusters)).
- **SSOT Integrity Guard:** Жорстка прив'язка коду до архітектурної документації (Wiki).
- **Parallel Workload Matrix:** Візуальний поділ потоків між фізичними (Лабораторія / Завод) та цифровими (ШІ) агентами.
- **Labels-as-Code:** `.github/labels.yml` + GitHub Actions workflow синхронізує лейбли при кожному push.

---

## ✅ Статус

- **Поточний TRL:** TRL 7 — CI/CD пайплайн TRL Auto-Advancement на стадії впровадження. **`main` захищено branch-protection** (required status checks = усі **8** детермінованих PR-гейтів — `CI`/`Docs`/`Solidity`/`CAD`/`ML`/`In-silico`/`IaC`/`DCO passed`, `enforce_admins=false` — owner лишає прямий push; канон [`06_07 §2`](06_07_CICD_and_Runbook_Index)). Відкриті: `PROJECT_PAT` provision + GitHub App-token міграція → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_02` — AI Native Engineering and TRL](00_02_AI_Native_Engineering_and_TRL) | AI-Native методологія (philosophy) |
| [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | Стратегічна дорожня карта + TRL-матриця |
| [`00_04` — Shape Up Operations and RnD Clusters](00_04_Shape_Up_Operations_and_RnD_Clusters) | Shape Up operations; §5.2 Betting Table, §6 Academic Semester |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | §13b Doc↔Code Sync: механіка — гейт `model_doc_sync` (НЕ цей guard), семантика — ручний cool-down аудит ([`00_04 §5.3`](00_04_Shape_Up_Operations_and_RnD_Clusters)); відкриті drift-айтеми → [`00_07`](00_07_Action_Plan_Tracker) |
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | Kamal / Terraform CI integration |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (OPS.3 / OPS.4 + trl_sync/labeler) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. Налаштування GitHub Projects V2](#-1-налаштування-github-projects-v2)
- [2. Автоматизація через GitHub Actions](#-2-автоматизація-через-github-actions)
- [3. Репозиторій (Monorepo)](#-3-репозиторій-monorepo)
- [4. Label Conventions (SSOT)](#-4-label-conventions-ssot)
- [5. Верифікація та Критерії Виходу](#-5-верифікація-та-критерії-виходу)
- [6. Первинне налаштування репозиторію (Bootstrap)](#-6-первинне-налаштування-репозиторію-bootstrap)
<!-- TOC:AUTO:END -->

---

## ⚙️ 1. Налаштування GitHub Projects V2

### 1.1 Custom Fields (SSOT)

| Поле | Тип | Опис / Функція |
| :--- | :--- | :--- |
| **Current TRL** | Single Select | Поточний рівень (**1-9**, NASA/ISO 16290 — лише технологічна готовність) згідно з [`00_02 §1`](00_02_AI_Native_Engineering_and_TRL). Головна колонка на дошці "Матриця TRL". |
| **Target TRL** | Single Select | Цільовий рівень (**1-9**) для поточного циклу. TRL НЕ розширюється до «10-12» (це нестандартно). |
| **Readiness Horizon** | Single Select | Beyond-TRL-9 R&D-епіки ([`00_02 §1`](00_02_AI_Native_Engineering_and_TRL), [`00_08 §1`](00_08_Beyond_TRL9_Planetary_Roadmap)): **SRL** (System Readiness — forest-level emergence, edge self-evolution, cross-biome generalization, AI-adversarial security) стадії `SRL:Concept` / `SRL:Pilot` / `SRL:Deployed`, та **MRL** (Manufacturing Readiness, `MRL:8/9/10` — серійний друк 5 SKU). |
| **Assigned Agent** | Single Select | Виконавець: `Architect`, `AI Agent`, `Lab (ChNU)`, `Factory`, `nTop Expert`. |
| **Module** | Single Select | Компонент екосистеми (наприклад, `04: Server Core`). Формує Swimlanes. |
| **Appetite** | Single Select | `Small Batch` (1-2w) або `Big Bet` (6w) згідно з методологією Shape Up. |
| **SSOT Link** | Text | Пряме посилання на сторінку Wiki або звіт (Лабораторна валідація). Тип Text, бо Projects V2 не має URL-dataType (`GithubBootstrap::FIELDS` = `:text`). |
| **R&D Cluster** | Single Select | Primary кластер відповідальності — **рівно ОДИН** (accountability): `A — Hardware/EBFC`, `B — Verification/Math`, `C — Scaling/Cloud`, `D — Compliance/Legal`. *(«Cross-cluster» прибрано як resting-стан поля — крос-кластерність виражають secondary-лейбли `cluster-ref:*` (§4.2); драйвер завжди один, [`00_04 §2`](00_04_Shape_Up_Operations_and_RnD_Clusters).)* |
| **Shape Up Stage** | Single Select | Стадія всередині 8-тижневого циклу: `Shaping`, `Bet (active)`, `Building`, `Hill (uphill)`, `Hill (downhill)`, `Park`, `Drop`, `Done` |
| **Cycle** | Single Select | Cycle milestone (формат `YYYY.QN`): `Cycle 2026.Q2`, `Cycle 2026.Q3`, … |
| **Academic Semester** | Single Select | Прив'язка до семестру партнерських ВНЗ: `Fall 2025-2026`, `Spring 2025-2026`, `Fall 2026-2027`, … |

### 1.2 Створення полів через GitHub CLI (IaC)

> Замість ручного клікання у Projects V2 UI, поля створюються скриптом `bin/setup_github_project.sh` (тонка обгортка над `rake github:project_fields`; схема полів — SSOT у `lib/github_bootstrap.rb`). Поточний gh CLI не підтримує `project add-field` повністю — workaround через GraphQL.

```bash
# bin/setup_github_project.sh — обгортка над `rake github:project_fields` (схема полів — lib/github_bootstrap.rb)
PROJECT_ID="PVT_xxxx"  # отримати через `gh project list --owner Alexey-Lukin --format json`

# Single-select option sets (SSOT — синхронізувати з §1.1 та lib/github_bootstrap.rb)
TRL_OPTIONS=(TRL:1 TRL:2 TRL:3 TRL:4 TRL:5 TRL:6 TRL:7 TRL:8 TRL:9)
# ↑ Шкала 1-9 (NASA/ISO 16290). TRL НЕ розширюється до 10-12 (00_02 §1).
READINESS_HORIZON_OPTIONS=(SRL:Concept SRL:Pilot SRL:Deployed MRL:8 MRL:9 MRL:10)
# ↑ Beyond TRL 9 = окремий вимір SRL/MRL (00_02 §1, 00_08 §1), не "TRL 10-12".

for FIELD in "Current TRL" "Target TRL" "Readiness Horizon" "Assigned Agent" "Module" "Appetite" "R&D Cluster" "Shape Up Stage" "Cycle" "Academic Semester"; do
  echo "Ensuring field: $FIELD"
  # gh api graphql -f query='mutation { addProjectV2Field(...) }'
  # Для Current TRL / Target TRL передавати TRL_OPTIONS[@] як SingleSelect options.
done
```

⚠️ **Односторонні двері (властивість, не баг):** `sync_project_fields` дифить лише за ІМ'ЯМ поля — створює відсутні, але зміна option-сету *існуючого* поля у `FIELDS`/§1.1 НЕ оновить живу дошку; редагування опцій наявного поля = ручна UI-операція.

---

## ⚙️ 2. Автоматизація через GitHub Actions

### 2.1 Workflow Inventory

> **Повний CI/CD-індекс усіх workflows** (deploy/deploy-production/mirror-ghcr/ml_smoke/ci тощо) — канон [`06_07`](06_07_CICD_and_Runbook_Index). Нижче — лише **Projects/IaC-automation + governance**-релевантні (дім цього доку); інші реферять 06_07, не дублюють.

| Workflow | Файл | Тригер | Статус |
|----------|------|--------|--------|
| TRL Auto-Advancement | `.github/workflows/trl_sync.yml` | `issues: [closed]` | ✅ Workflow + TRL≥5 architect-approval gate реалізовані (OPS.1/OPS.9); чекає `PROJECT_PAT` provision (OPS.1, 00_07) |
| Labels Sync (IaC) | `.github/workflows/labels_sync.yml` | `push` на `.github/labels.yml` | ✅ Реалізовано |
| PR Auto-Labeler | `.github/workflows/labeler.yml` | `pull_request_target` | ✅ Реалізовано (fork-PR write-token → top-level `permissions: {}`, job піднімає лише `pull-requests:write`, §2.7) |
| SSOT Integrity Guard | `.github/workflows/ssot_guard.yml` | `pull_request` | ✅ Реалізовано (OPS.2; semantic `type:*` bypass — §2.3) |
| Solidity Audit | `.github/workflows/solidity_audit.yml` | `push` / PR з `contracts/**` | ✅ Реалізовано |
| CoAP Smoke Test | `.github/workflows/coap_smoke.yml` | `workflow_dispatch` / `workflow_call` із `deploy.yml`+`deploy-production.yml` (post-deploy gate; активується repo Variable `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` — INF.6) + **`schedule` кожні 30 хв** (`17,47 * * * *` — безперервний liveness анкера-SPOF, S2.4) | ✅ Реалізовано — freeze-contract зонди `bin/coap_smoke` (точні байти FW.56 golden-векторів; loopback-довід `spec/lib/coap_smoke_spec.rb`) |
| In-silico L2 Smoke | `.github/workflows/in_silico_smoke.yml` | `pull_request` / `push` з path-filter — **4 шляхи**: `tools/in_silico/**`, `docs/protocols/ebfc/in_silico/**`, `docs/01_04_CODIT_and_Xylemointegration.md`, self-path воркфлоу | ✅ Реалізовано (Zero-Lab L2 engine gate; CPU-only via `SILKEN_FORCE_PLATFORM=CPU`, micromamba env cache, не гейтить деплой) |
| Docs CI (SSOT gates) → **CI · Docs** | `.github/workflows/docs.yml` | `push` / PR path-filter `docs/**`, `**.md`, linter-engine/специ, `.github/**`, `app/models/**` | ✅ Реалізовано (2026-05-30) — `tracker:check` + `docs:check_refs` + linter-специ + model↔code sync. **Branch-protection (2026-06-19):** `main` вимагає `CI passed` (ci-ok), який тепер завжди звітує — `ci.yml` більше **НЕ** `paths-ignore`s docs (інакше docs-only PR не дав би required-чек). SSOT-доки **required** через `Docs passed` (`docs-ok` always-on aggregate, з path-gated `docs_check` під ним) — [`06_07 §2`](06_07_CICD_and_Runbook_Index) |

### 2.2 Протокол "TRL Auto-Advancement" (`trl_sync.yml`)

Автоматизує рух карток по матриці готовності технологій.

- **Тригер:** `issues: types: [closed]`
- **Умова:** Завдання закрите (Done).
- **Дія (TRL-stratified gate):** скрипт зчитує `Target TRL` закритого Issue. **`Target TRL ≤ 4`** → авто-перезапис `Current TRL` (картка «перелітає» у нову колонку), бо рев'ю TRL 1-4 делеговане лідам + CI ([`00_04 §3`](00_04_Shape_Up_Operations_and_RnD_Clusters)). **`Target TRL ≥ 5`** → скрипт **НЕ** рухає `Current TRL` (warning у run-лозі пояснює причину); просування відбувається лише за наявності лейбла `architect-approved` (його ставить виключно Архітектор). Інваріант тримає **лейбл**, не статус-поле: окремого поля `Status` схема §1.1 свідомо не має (лайфсайкл картки живе у `Shape Up Stage` — друге стан-поле було б подвійним домом), а коментар-нотифікація без другого maintainer'а — ритуал (присуд ⚖️ 2026-07-16). Це поважає обов'язкові TRL-гейти 4→5 / 6→7 / 8→9 (Architect/DAO approval, [`00_04 §3`](00_04_Shape_Up_Operations_and_RnD_Clusters), [`00_02 §5`](00_02_AI_Native_Engineering_and_TRL)). Додатково: рахує `completion_semester` з `closed_at` (UTC) → поле `Academic Semester`.
- **Авторизація:** наразі `secrets.PROJECT_PAT` (PAT Архітектора). ⚠️ **Рекомендація безпеки:** мігрувати на **GitHub App installation token** (fine-grained, авто-ротація, short-lived) — PAT прив'язаний до акаунта, надто широкий, протермінується й тихо ламає пайплайн. **Важливо:** дефолтний `secrets.GITHUB_TOKEN` тут НЕ підходить — він **не має доступу до Projects V2** (а permission `repository-projects` покриває лише *classic* projects, не V2). Тож єдина безпечна заміна PAT для Projects V2 — **GitHub App token**. Tracked → [`00_07`](00_07_Action_Plan_Tracker).

> **Чому gate, а не безумовний авто-рух:** інакше будь-який «Close Issue» (розробник або AI-агент) підняв би технологію до TRL 9, обійшовши обов'язкові Architect/DAO-гейти — і TRL-метрика з інструмента оцінки зрілості виродилась би у звичайний task-tracker. Авто-рух лишається лише для TRL 1-4 (рев'ю там і так делеговане); TRL ≥5 завжди проходить людський gate. **`trl_sync.yml` реалізує цей gate (OPS.9): для Target TRL ≥5 без лейбла `architect-approved` `Current TRL` НЕ рухається. Workflow активується по provision `PROJECT_PAT` (OPS.1 → [`00_07`](00_07_Action_Plan_Tracker)).**

```yaml
# .github/workflows/trl_sync.yml — skeleton (повна логіка inline у файлі)
name: Ops · TRL Sync
on:
  issues:
    types: [closed]
jobs:
  sync_trl:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v9
        with:
          github-token: ${{ secrets.PROJECT_PAT }}   # ⚠️ мігрувати → GitHub App token (GITHUB_TOKEN не вміє Projects V2). Див. §2.2.
          script: |
            # 1. resolve Project V2 + поля   2. знайти item для issue
            # 3. Target TRL ≥5 без лейбла `architect-approved` → Current TRL НЕ рухається (OPS.9 gate)
            # 4. copy Target TRL → Current TRL   5. (OPS.4) stamp Academic Semester
```

### 2.3 Протокол "SSOT Integrity Guard" (`ssot_guard.yml`)

Автоматична перевірка актуальності документації (The Codex).

- **Умова:** Pull Request вносить зміни в захищені зони: `app/{models,services,workers}/`, `firmware/{soldier,queen,bio_contracts,common}/` або `contracts/` (точний список — `paths:`-фільтр живого файла; він дзеркалить `mappings` у скрипті — розширювати ОБИДВА).
- **Дія:** Action перевіряє наявність відповідних змін у `docs/` (або `README.md`/`CLAUDE.md`). Якщо документація не оновлена — чек червоніє (`core.setFailed`), але **advisory за позицією**: він не в required-списку branch-protection, мердж фізично не блокується — так ратифіковано [`06_07 §2`](06_07_CICD_and_Runbook_Index).
- **Bypass:** PR із semantic-label з whitelist (`type:chore`, `type:deps`, `type:perf`, `type:test`) автоматично пропускається — ці типи **за визначенням** не змінюють архітектуру/контракти. **`type:refactor` та `type:bugfix` навмисно ВИКЛЮЧЕНО з auto-bypass**: рефакторинг змінює імена класів / шляхи (напр. `app/services/blockchain_minting_service.rb`), а багфікс — логіку (класичний приклад: FW.7 Lorenz BigDecimal→Float) → обидва спричиняють Context Drift у Wiki. Для них guard вимагає **або** оновлення відповідного `docs/`-файла, **або** запис відкритого drift-айтема у [`00_07`](00_07_Action_Plan_Tracker) (One-Home для backlog — саме туди їх адресує [`04_02 §13b`](04_02_Business_Logic_and_Services), а не в датований лог у каноні) — а він сам є зміною у `docs/`, тож автоматично задовольняє перевірку. Явний вибір label лишається форс-функцією: автор класифікує зміну, а не додає порожній коміт у `docs/`.

> **Чому семантичні label замість `skip-ssot-guard`:** Generic skip-label буде зловживатись (натиснув-обійшов). Семантичні `type:*` змушують автора публічно класифікувати зміну. Якщо PR має `type:bugfix`, але насправді міняє схему — code reviewer одразу побачить mismatch у заголовку та назві label.

> **One-Home:** живий файл — `.github/workflows/ssot_guard.yml` (`github-script`/JS: diff base...head → `mappings`-матч захищених зон → bypass-лейбли → `core.setFailed`); код тут не дублюється (прецедент §2.6 — YAML-дзеркало розійшлось із файлом і було згорнуто).

**`type:*` labels заведені у `.github/labels.yml`** як частину Labels-as-Code SSOT (див. §2.5) — таблиця нижче лишається дзеркалом файла. Auto-bypass SSOT Guard дають **лише** `chore/deps/perf/test` (§2.3).

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

- **Тригер:** Push до `main` або PR зі змінами у `contracts/**` (або в самому workflow-файлі); + ручний `workflow_dispatch`
- **Позиція в branch-protection:** кожен джоб — fail-on (**job-level gate**), і агрегат **`Solidity passed` ∈ required-checks `main`** з 2026-07-19 (OPS.15 ✅ — червоний audit **блокує** merge; required-набір → §2.1 / [`06_07 §2`](06_07_CICD_and_Runbook_Index))
- **Job 1: Foundry Tests & Coverage** (`foundry-tests`, timeout: 15 хв):
  - `npm ci` → `forge build --sizes` → `forge test -vvv --gas-report` → `forge coverage --ir-minimum --report lcov --report summary`
  - Coverage artifact: `lcov.info` (retention 14 днів)
- **Job 2: Slither Static Analysis** (`slither`, timeout: 10 хв):
  - Install Foundry + `npm ci` → `forge build --build-info` (компілюємо самі), далі `crytic/slither-action@v0.4.2` з `ignore-compile: true` — crytic читає Foundry build-info, а власний `forge install` екшена **не** запускається (deps з npm, не `lib/`-сабмодулі — рішення FW.47, [`03_01`](03_01_Firmware_Lifecycle_and_DMA))
  - `slither-config: contracts/slither.config.json` (фільтр `node_modules|test/` → аудит лише деплойних контрактів), solc (версія → [`05_03`](05_03_Tokenomics_SCC_and_SFC)), `fail-on: high`
  - ⚠️ `slither-version` запінено явно (**SHA-пін екшена не тримає його начинку** — образ ставить `slither-analyzer` з PyPI свіжим щоразу; апстрим-реліз віком 1 доба поклав цей required-гейт 2026-07-29, бо новіший `crytic-compile` кличе `forge` навіть під `ignore-compile`, а forge живе на раннері, не в контейнері). Дзеркалить дисципліну сусідніх job-ів: halmos/medusa = `--require-hashes`, aderyn = sha256-verify. Стан + шлях зняття піна → [`00_07`](00_07_Action_Plan_Tracker) OPS.21
- **Job 3: Halmos Symbolic Proofs** (`halmos`, timeout: 30 хв, **gating**):
  - `setup-python` (3.13) + `pip install --require-hashes -r requirements-halmos.txt` (hash-pinned) → `halmos --function "^check_" --solver-threads 1 --loop 3` — symbolic proof-и money-path інваріантів (`test/symbolic/*`; symbolic params + `vm.assume`, без halmos-cheatcodes) — доводить cap / last-admin / pause-allows-slash symbolically (не семпл)
- **Job 4: Aderyn Static Analysis** (`aderyn`, timeout: 10 хв) — 2-й static-прохід, комплементарний до Slither:
  - `npm ci` (OZ remappings) → aderyn **release-бінарник із sha256-verify** (не npm-global) → `aderyn .` (JSON-gate на high + SARIF → GitHub Security tab через `upload-sarif`); foundry-native (читає `foundry.toml` solc/cancun), `aderyn.toml` фільтрує `node_modules|test|lib` + виключає 6 by-design low-детекторів (centralization-risk / costly-loop / require-in-loop / large-literal / unchecked-return-in-ctor / OZ-ctor-shadow — архітектурні false-positive на AccessControl+Governor+batch). 2 fixable low-notes пофіксено **в коді** (magic-256 → `MAX_STRING_BYTES`; `nonReentrant`-first modifier order)
- **Job 5: Medusa Property Fuzzing** (`medusa`, timeout: 15 хв, **gating**):
  - `pip install --require-hashes -r requirements-crytic.txt` (hash-pinned) + medusa binary → `medusa fuzz --config medusa-{scc,sfc}.json` (`test/medusa/*`); **single-file target** тримає crytic-compile поза forge-std (його `LibVariable` ABI crytic-compile не парсить), corpus persist у `actions/cache`
- **Конфігурація Foundry** (`contracts/foundry.toml`):
  - solc (версія → [`05_03`](05_03_Tokenomics_SCC_and_SFC)), EVM cancun, optimizer 200 runs (default), 1000 runs (production profile)
  - Gas reports: SCC, SFC, StateRootAnchor, SilkenGovernor, SilkenTimelock, ProtocolParameters
  - Fuzz: 512 runs (default). Invariant: 128 runs, depth 64 (+ Medusa coverage-guided property-fuzz — `medusa` job, `test/medusa/*`)
- **Тестове покриття:** per-contract suites (`contracts/test/*.t.sol`; к-сть suite й тестів — `forge test`)

### 2.5 Labels Sync (IaC) — `.github/labels.yml` + `labels_sync.yml`

> **Чому Labels-as-Code:** ручні інструкції типу "створи 12 лейблів через UI" — це не автоматизація. Файл `.github/labels.yml` — SSOT; workflow `labels_sync.yml` синхронізує лейбли при кожному push, що змінює цей файл. **`delete-other-labels: false`:** sync **створює/оновлює** лейбли з YAML, але **не видаляє** ті, яких у файлі немає — інакше label-sync затирав би ефемерні лейбли зовнішніх ботів (Dependabot `dependencies`, Snyk, Renovate) і дефолтні GitHub-лейбли (`good first issue`, `help wanted`), ламаючи їхні інтеграції. Прибирання застарілого project-label — **свідома** окрема дія (видалити з YAML + цілеспрямований cleanup), а не агресивний `delete` на кожен push.

```yaml
# .github/workflows/labels_sync.yml — skeleton
name: Ops · Labels Sync
on:
  push:
    branches: [main]
    paths: ['.github/labels.yml']
  workflow_dispatch:
jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: EndBug/label-sync@v2
        with:
          config-file: .github/labels.yml
          delete-other-labels: false  # НЕ видаляти лейбли ботів (Dependabot/Snyk) і GitHub-дефолти; прибирання — свідомо, див. §2.5
          token: ${{ secrets.GITHUB_TOKEN }}
```

### 2.6 PR Auto-Labeler — `.github/labeler.yml` + `labeler.yml` workflow

Routes PRs автоматично у відповідні кластери на основі шляхів файлів.

> **Конфіг = SSOT у [`.github/labeler.yml`](../.github/labeler.yml); тут — лише політика.** Дзеркало глобів раніше жило в цьому §, розійшлося з файлом у 5 місцях і навіть іменувало неіснуючий `module:06-infra` (живий — `module:06-matrix`, §4.4) — прибрано за One-Home, як solc-pragma. Правки застосовані (OPS.9 — вже в архіві [`00_07`](00_07_Action_Plan_Tracker)); coverage-residual → [`00_07`](00_07_Action_Plan_Tracker) OPS.3.

**Політика роутингу (durable):**

- **Primary-кластери взаємовиключні** (§4.1): широкий `app/**` кластера C **мусить** явно виключати спеціалізовані піддерева B (`iotex`, `attractor*`, `seed_derivation*`) і D (`hadron_*`) — інакше PR дістає два primary-label; специфічний кластер виграє над загальним.
- 🔴 **`all:`-обгортка обов'язкова скрізь, де є негативні глоби.** Матчери під одним `changed-files` дефолтяться в `any:` (**OR**) → негативна клауза сама матчить кожен PR поза виключеними піддеревами, і лейбл липне на все. AND дає лише `- all:` з окремими `changed-files`-блоками. Цей баг був живий (C липнув на всі PR) і пофікшений 2026-07-16 — деталь у [`00_07`](00_07_Action_Plan_Tracker) OPS.3.
- `chainlink_router_version*` — **не** primary-B: це Router-ABI failover, інфраструктура ([`06_08`](06_08_Resilience_and_Failover_Policy)), а не математика/ZK → primary-C через `app/**` + secondary `cluster-ref:B`, як інші web3-сервіси.
- PR, що чіпає різні top-level дерева (`app/` + `contracts/`) — справді cross-cluster: auto-labeler чесно ставить **обидва** primary-лейбли (labeler v6 не вміє правила «matched ≥2»), і саме dual-primary Є машинним сигналом; `cluster:cross-cluster` як **транзитний** triage-маркер вішається вручну при розборі (§4.1) і резолвиться у рівно один драйвер + `cluster-ref:*`.
- **Routing-coverage = інваріант §4.1** (100% accountability): кожен шлях мусить мати primary-кластер. Діри закрито 2026-07-16 (OPS.3; повний аудит знайшов ширше за флаговані `.github/**`/`docs/03_*`): **→ A** — `docs/03_*` (firmware-канон) + `tools/**` (дзеркало ci.yml firmware-area); **→ C** — `.github/**`/`.claude/**`/`.kamal/**`/`bin/**`/`public/**`/`vendor/**`/`docs/00_*` + root-файли (`*` і `.*` — Gemfile/Dockerfile/orientation-`*.md`/dot-конфіги): process/CI/infra = світ кластера C ([`00_04 §2`](00_04_Shape_Up_Operations_and_RnD_Clusters) — база «Architect + AI coding-agents»).


```yaml
# .github/workflows/labeler.yml  (skeleton — реальний файл SHA-пінить `uses:` + має harden-runner першим кроком, §2.7)
name: Ops · PR Labeler
on:
  pull_request_target:
    types: [opened, reopened, synchronize]
permissions: {}          # top-level least-privilege floor (§2.7); job піднімає лише потрібне
jobs:
  label:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/labeler@v7          # v7 = ESM-міграція; schema (changed-files / *-glob-to-*-file) та сама, що й .github/labeler.yml
        with:
          repo-token: ${{ secrets.GITHUB_TOKEN }}
          configuration-path: .github/labeler.yml
          sync-labels: true
```

### 2.7 Supply-chain hardening (IaC: pin-by-digest · token-least-privilege · harden-runner · actionlint · Scorecard)

> **Дія/стан — [`OPS.10`](00_07_Action_Plan_Tracker); інвентар workflow — [`06_07 §1`](06_07_CICD_and_Runbook_Index). Тут — IaC-політика (дім).**

Постава supply-chain для `.github/workflows/` як IaC:

- **SHA-pin (обов'язково).** Кожен зовнішній `uses:` запінено на повний 40-символьний commit-SHA з коментарем `# vN` (напр. `actions/checkout@9c091bb… # v7`). Рухомий тег `@vN` — мутабельний покажчик: скомпрометований екшен-репо може мовчки перепнути його (вектор `tj-actions/changed-files`, 2025); SHA незмінний. **Dependabot** (`github-actions` ecosystem, `.github/dependabot.yml`) розуміє SHA-піни й оновлює і SHA, і `# vN` через PR → незмінність без застигання. Локальні `uses: ./…` не пінять (вони в репо). **Базовий Docker-образ** (`Dockerfile` `FROM`) теж запінено по digest (`ruby:…@sha256:…`); тег **literal** (не через `ARG` — Dependabot не резолвить ARG'd FROM, dependabot-core #4597), а `docker`-ecosystem у Dependabot оновлює тег і digest разом → pin без застигання.
- **Hash-pinned CLI-аналізатори (закриває Scorecard `Pinned-Dependencies`).** pip-встановлювані CI-тулзи запінені по **hash**, не лише версії: pip (`halmos`, `crytic-compile`) — `pip install --require-hashes -r contracts/requirements-{halmos,crytic}.txt` (locked-файли згенеровано `pip-compile --generate-hashes` під Python 3.13 = CI-версія, з усіма транзитивними хешами; `.in`-джерело комічене поряд → reproducible build); `pytest` для stdlib-only `cache_doc_sync`-гейта (`in_silico_smoke.yml`) — той самий рецепт, `tools/in_silico/requirements-pytest.{in,txt}`; `conda-lock` для `lock_sync`-гейта — `tools/in_silico/requirements-conda-lock.{in,txt}`, згенеровано **`uv pip compile --universal --python-version 3.12`** (до 2026-07-16 плавав `pipx`-latest — єдиний виняток політики; ⚠️ pip-compile тут НЕ годиться — він фіксує markers під платформою компіляції, macOS-лок викинув linux-only `SecretStorage` і крок падав; `--universal` тримає marker-гілки всіх платформ. Транзитивний кап: conda-lock 4.0.2 тримає dulwich `<0.25` при PYSEC-fix лише в 1.2.5 — documented-blocker у `.in`, Scorecard-alert → dismiss-with-reason [👤]); `aderyn` — GitHub release-бінарник із **sha256-verify** (не npm-global); `medusa` — release-бінарник із **hardcoded sha256** (реліз `.sha256` не публікує — значення обчислено з асета і звірено з digest його Sigstore-attestation, деталь у коментарі кроку). Re-gen `requirements-*.txt` при version-bump'і (`dependency-update`-прохід). (`ruff` — pinned-action `version:`; Dependabot-ecosystem'и покривають `uses:` + `contracts/package.json` + Docker.)
- **Token-permissions (least-privilege).** Кожен workflow має **top-level** `permissions:`-поверх із read-floor (`{}` або `contents: read`); write-скоупи піднімає **лише той job**, якому вони потрібні (`packages:write` у GHCR-build-джобі; `contents`+`pull-requests:write` у release-please). Без top-level-поверху новий job успадкував би широкий дефолт. **Критичний інваріант:** workflow на `workflow_run`/`pull_request_target` (write-token + секрети) **не checkout-ить** untrusted head-ref — GHCR-mirror бере список змінених файлів через `gh api commits/{sha}`, а не checkout події (Scorecard DangerousWorkflow).
- **harden-runner** (`step-security/harden-runner`, `egress-policy: audit`) — перший крок кожного Linux-джоба: пасивний egress/FS-монітор (нічого не блокує), збирає baseline для майбутнього `block`-режиму з allowlist. macOS-джоби (harden-runner Linux-only) та no-op-агрегати (`ci-ok`) свідомо пропущені.
- **actionlint** (CI-джоб `workflow_lint` у `ci.yml`, path-gated на `.github/workflows/**` + `.github/actions/**`) — статичний аналіз самих workflow-файлів (синтаксис, `${{ }}`-вирази, типи подій, permissions-скоупи, glob'и) + shellcheck кожного `run:`. Встановлюється як pinned-release-binary з sha256-verify (не moving-tag) → ловить regression-и, яких YAML-parse не бачить. Інвентар → [`06_07 §1`](06_07_CICD_and_Runbook_Index).
- **OpenSSF Scorecard** (`Sec · Scorecard`) — щотижневий аудит supply-chain-гігієни (~18 перевірок) → SARIF у Security tab + публічний бейдж (`publish_results: true` — репо публічне). Постійний вартовий замість разового аудиту, що протухає.
- **IaC misconfig-скан** (`Sec · IaC Scan`, Trivy `config`) — статичний скан IaC-поверхні (`terraform/**` + `Dockerfile`) на misconfiguration (публічні бакети, permissive firewall/IAM, відсутнє шифрування, unpinned base-image) → SARIF у Security tab. **HARD** (`exit-code: '1'`): початковий soft-fail baseline **тріажнуто до 0 відкритих**, тож підняття вже відбулось — НОВИЙ misconfig валить білд, а `IaC passed` входить у вісім required-чеків ([`06_07 §2`](06_07_CICD_and_Runbook_Index)). Дозволені винятки живуть у `.trivyignore`, не в зниженій суворості. Tool = **Trivy** (tfsec deprecated — aquasecurity злив його в Trivy; один прохід покриває terraform *і* Dockerfile). Pin — **SHA-pinned action + `version:`-бінарник** (`ruff`-прецедент вище), не moving-tag (інакше self-inflict Scorecard `Pinned-Dependencies`). Live-state дрейф (не статичний файл) — окремий `Ops · TF Drift` (`terraform plan -detailed-exitcode` GCP-root, weekly, **skip-clean** до WIF-провайдера — keyless OIDC-auth, INF.22). Інвентар → [`06_07 §1`](06_07_CICD_and_Runbook_Index).
- **Build-provenance attestation (signed releases).** GHCR-образ (`mirror-ghcr.yml`) підписується **Sigstore-keyless SLSA build-provenance** через `actions/attest-build-provenance` (`id-token: write` → GitHub OIDC → Fulcio CA, запис у публічний Rekor transparency log) + BuildKit SBOM; attestation push-иться в registry поряд з образом. Підписувальний ключ ефемерний (per-build, не зберігається) → **не на сайті роздачі**. User-facing verify-процес (one-home) — `SECURITY.md`. Закриває OpenSSF `signed_releases`. *(harden-runner = `audit` → Fulcio/Rekor досяжні; при майбутньому `block`-режимі — allowlist `fulcio.sigstore.dev` / `rekor.sigstore.dev` / `tuf-repo-cdn.sigstore.dev` / `*.actions.githubusercontent.com`.)*
- **Keyless CI→GCP (WIF).** Deploy/drift-workflow автентифікуються до GCP через **Workload Identity Federation** (`terraform/wif.tf`), не довгоживучий JSON SA-ключ: `google-github-actions/auth` карбує GitHub OIDC-токен (`id-token: write`), GCP STS обмінює його на короткоживучий impersonated deploy-SA access-token. Довіру замкнено на цей репозиторій `attribute_condition` (owner-рівень) + repo-scoped `principalSet` на SA-binding (owner-case нормалізовано `lowerAscii()`). CI-secret `GCP_SA_KEY` вилучено; лишається лише Akash `GCP_SA_KEY_BASE64` (Cloud SQL proxy — зовнішній провайдер не досягає GitHub-issuer'а, [`06_02 §Security Exception`](06_02_Akash_Network_Integration)). Провайдер+SA email = repo **Variables** (не secrets). Дзеркало Sigstore-keyless вище — жодного статичного GCP-credential у CI. Дім → [`06_04 §1.1`](06_04_Secrets_Checklist) / INF.22.
- **GitHub-side** (звірено gh API 2026-06-22): secret-scanning + push-protection **ON**; Dependabot security-updates **ON**; CodeQL default-setup активний (first-party SAST). 👤-залишки (signed-commits, опц. toggles) — [`OPS.10`](00_07_Action_Plan_Tracker).

---

## 🗂️ 3. Репозиторій (Monorepo)

Уся система живе в **одному репозиторії `silken_net`** (monorepo) — єдині правила контекстного управління та один CI на всі шари:

- **`app/` · `lib/` · `config/` · `db/`** — Rails 8.1 ядро (PostgreSQL, Sidekiq — єдиний job-backend, Solid Cache/Cable; Solid Queue scaffold pruned — INF.18 §🗄️, воскресає з git).
- **`contracts/`** — смарт-контракти (Solidity, Foundry toolchain + Slither/Aderyn/Halmos/Medusa CI).
- **`firmware/`** — прошивка Soldier/Queen (C, mruby) для STM32WLE5JC + LoRa (host-тести `make -C firmware/test`).
- **`tools/`** — in-silico (EBFC: PySCF/OpenMM) + ML (TinyML/log-mel) + CAD (PicoGK Code-as-CAD `tools/cad`, .NET 9; [`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)) пайплайни.
- **`docs/`** — SSOT-канон (**авто-дзеркалиться** у GitHub Wiki на кожен push у `main`, що чіпає `docs/` — `wiki.yml` → `scripts/wiki_sync.rb`; 00_00 → `Home`; off-switch — репо-змінна `DISABLE_WIKI_AUTOSYNC`; інвентар [`06_07 §1`](06_07_CICD_and_Runbook_Index) — [`00_06`](00_06_SSOT_Documentation_Standard)).

> **Історія:** колишні окремі репо `silken-soldier-fw` (прошивка) та `silken-contracts` (контракти) **консолідовані в monorepo** — активні джерела тепер тут, під спільним CI; старі репо архівні.

---

## 🏷️ 4. Label Conventions (SSOT)

Файл `.github/labels.yml` — Single Source of Truth для всіх **керованих проєктом** лейблів. Будь-яке нове project-label має бути занесене сюди до використання. `labels_sync.yml` створює/оновлює їх, але **не видаляє** сторонні/ботівські лейбли (`delete-other-labels: false`, §2.5) — прибирання застарілого project-label робиться свідомо, щоб не ламати інтеграції ботів.

### 4.1 Cluster routing (primary, mutually exclusive)

| Label | Колір (hex) | Семантика |
|-------|-------------|-----------|
| `cluster:A-hardware` | `#FF6B35` (orange) | Primary кластер — Hardware/EBFC |
| `cluster:B-verification` | `#4ECDC4` (teal) | Primary кластер — Verification/Math |
| `cluster:C-scaling` | `#3D5A80` (blue) | Primary кластер — Scaling/Cloud |
| `cluster:D-compliance` | `#7209B7` (purple) | Primary кластер — Compliance/Legal |
| `cluster:cross-cluster` | `#F1E05A` (yellow) | **Транзитний triage-маркер** (НЕ resting-стан, НЕ власник): вішається **вручну** при triage multi-tree PR — авто-сигналом слугує dual-primary від labeler'а, бо labeler v6 правила «matched ≥2» не виражає (§2.6). **Зобов'язаний** до Betting Table резолвитись у **рівно один** `cluster:*` (драйвер) + будь-яку к-сть `cluster-ref:*` (консультанти) — завдання не може лишатися «нічиїм» (100% accountability, [`00_04 §2`](00_04_Shape_Up_Operations_and_RnD_Clusters)). |

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

- `priority:P0` / `P1` / `P2` / `P3` ([`00_07`](00_07_Action_Plan_Tracker))
- `complexity:XS/S/M/L/XL`
- `agent:ai` / `agent:human` / `agent:ops` / `agent:hybrid` _(назви labels без emoji у [`.github/labels.yml`](../.github/labels.yml); emoji `🤖 / 👤 / 🔧 / 🔗` — **візуальні маркери виконавця**: передусім swimlane-навігація у [`00_07`](00_07_Action_Plan_Tracker), а в каноні Tier I/II трапляються точково (👤 bench-residual / 🤖 AI-doable))_
- `module:00-codex` / `module:01-anchor` / `module:02-capsule` / `module:03-firmware` / `module:04-server-core` / `module:05-ledger` / `module:06-matrix` / `module:07-naas` / `module:08-academic`
- `type:chore` / `type:deps` / `type:perf` / `type:test` — **SSOT Guard auto-bypass**; `type:refactor` / `type:bugfix` — класифікація **без** bypass (вимагають docs-update або запису в [`00_07`](00_07_Action_Plan_Tracker), див. §2.3)

---

## ✔️ 5. Верифікація та Критерії Виходу

- **Протокол тестування:** Закриття тестового Issue з `Target TRL ≤ 4` фізично переміщує колонку на дошці "Матриця TRL" без ручного втручання; Issue з `Target TRL ≥ 5` лишається на місці (warning у run-лозі) і просувається лише після лейбла `architect-approved` (§2.2 gate).
- **Критерій Виходу:** Жодного ручного перетягування карток. Єдине свідоме втручання Архітектора — `architect-approved` на TRL-гейтах ≥5 (approval, а не рутинна зміна статусу).
- **Критерій IaC:** Жодного ручного клікання у GitHub UI для створення / видалення labels (все через `.github/labels.yml`).
- **Результат валідації:** `[Dashboard: SilkenNet Command Center]` (URL TBD)

---

## 🎯 6. Первинне налаштування репозиторію (Bootstrap)

> Раніше тут був ручний 7-point checklist ("👤 Створити single-select field …"). Замість цього — single script + автоматизовані workflows.

```bash
# bin/bootstrap_github.sh — реалізовано (idempotent; `rake github:bootstrap`)
set -euo pipefail

# 1. Створити лейбли з .github/labels.yml
# (виконується автоматично через labels_sync.yml на push)
git push origin main

# 2. Створити Projects V2 fields
bin/setup_github_project.sh

# 3. Створити перший Betting Table milestone
gh api repos/Alexey-Lukin/silken_net/milestones \
  -f title="Cycle 2026.Q2" \
  -f description="First betting cycle after UNI.2 & UNI.14 onboarding"

# 4. Створити baseline shaping documents
mkdir -p docs/shaping
echo "Stub shape for cluster C: First Akash production deploy" > docs/shaping/akash-prod-deploy.md
```
