# 00_05: GitHub Automation and IaC

## 🎯 Мета

Тримати CI/CD-автоматизацію репозиторію як **Infrastructure-as-Code**: гейти, лейбли, supply-chain-постава й token-permissions живуть у репо як `.yml`-файли, а не як ручні чек-листи чи клікання в GitHub UI. SSOT — `.github/labels.yml`, `.github/workflows/*.yml` та цей документ.

Ключові компоненти:
- **SSOT Integrity Guard:** прив'язка коду до архітектурної документації (§2.3).
- **Solidity Audit:** money-path merge-гейт зі static/symbolic/fuzz-проходами (§2.4).
- **Labels-as-Code:** `.github/labels.yml` + workflow синхронізує лейбли при кожному push (§2.5).
- **Supply-chain hardening:** SHA-піни, hash-pinned CLI, least-privilege токени, harden-runner, Scorecard, build-provenance (§2.7).

---

## ✅ Статус

- **Стан:** CI/IaC-постава впроваджена й гейтована; шкала готовності тут **незастосовна** — предмет процес, не технологія ([`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond), DOC-T.70). **`main` захищено branch-protection** (required status checks = усі **8** детермінованих PR-гейтів — `CI`/`Docs`/`Solidity`/`CAD`/`ML`/`In-silico`/`IaC`/`DCO passed`, `enforce_admins=false` — owner лишає прямий push; канон [`06_07 §2`](06_07_CICD_and_Runbook_Index)). Відкриті residual'и supply-chain → [`00_07`](00_07_Action_Plan_Tracker) OPS.10 / OPS.21.

---

## 🔗 Cross-references

| Ресурс | Опис |
|--------|------|
| [`00_02` — AI Native Engineering and TRL](00_02_AI_Native_Engineering_and_TRL) | AI-Native методологія (philosophy) + TRL-гейти рев'ю |
| [`00_03` — TRL Matrix HIL and Beyond](00_03_TRL_Matrix_HIL_and_Beyond) | Стратегічна дорожня карта + TRL-матриця |
| [`00_06` — SSOT Documentation Standard](00_06_SSOT_Documentation_Standard) | Реєстр drift-гейтів (§3) + ручний семантичний drift-аудит — дім методу, який ганяють ці workflow |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | §13b Doc↔Code Sync: механіка — гейт `model_doc_sync` (НЕ цей guard); відкриті drift-айтеми → [`00_07`](00_07_Action_Plan_Tracker) |
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | Kamal / Terraform CI integration |
| [`06_07` — CICD and Runbook Index](06_07_CICD_and_Runbook_Index) | Повний інвентар workflow + required-набір branch-protection |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | Open backlog (OPS.10 supply-chain · OPS.21 незапінені начинки) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [2. Автоматизація через GitHub Actions](#-2-автоматизація-через-github-actions)
- [4. Label Conventions (SSOT)](#-4-label-conventions-ssot)
<!-- TOC:AUTO:END -->

---

## ⚙️ 2. Автоматизація через GitHub Actions

### 2.1 Workflow Inventory

> **Повний CI/CD-індекс усіх workflows** (deploy/deploy-production/mirror-ghcr/ml_smoke/ci тощо) — канон [`06_07`](06_07_CICD_and_Runbook_Index). Нижче — лише **Projects/IaC-automation + governance**-релевантні (дім цього доку); інші реферять 06_07, не дублюють.

| Workflow | Файл | Тригер | Статус |
|----------|------|--------|--------|
| Labels Sync (IaC) | `.github/workflows/labels_sync.yml` | `push` на `.github/labels.yml` | ✅ Реалізовано |
| SSOT Integrity Guard | `.github/workflows/ssot_guard.yml` | `pull_request` | ✅ Реалізовано (OPS.2; semantic `type:*` bypass — §2.3) |
| Solidity Audit | `.github/workflows/solidity_audit.yml` | `push` / PR з `contracts/**` | ✅ Реалізовано |
| CoAP Smoke Test | `.github/workflows/coap_smoke.yml` | `workflow_dispatch` / `workflow_call` із `deploy.yml`+`deploy-production.yml` (post-deploy gate; активується repo Variable `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` — INF.6) + **`schedule` кожні 30 хв** (`17,47 * * * *` — безперервний liveness анкера-SPOF, S2.4) | ✅ Реалізовано — freeze-contract зонди `bin/coap_smoke` (точні байти FW.56 golden-векторів; loopback-довід `spec/lib/coap_smoke_spec.rb`) |
| In-silico L2 Smoke | `.github/workflows/in_silico_smoke.yml` | `pull_request` / `push` з path-filter — **4 шляхи**: `tools/in_silico/**`, `docs/protocols/ebfc/in_silico/**`, `docs/01_04_CODIT_and_Xylemointegration.md`, self-path воркфлоу | ✅ Реалізовано (Zero-Lab L2 engine gate; CPU-only via `SILKEN_FORCE_PLATFORM=CPU`, micromamba env cache, не гейтить деплой) |
| Docs CI (SSOT gates) → **CI · Docs** | `.github/workflows/docs.yml` | `push` / PR path-filter `docs/**`, `**.md`, linter-engine/специ, `.github/**`, `app/models/**` | ✅ Реалізовано (2026-05-30) — `tracker:check` + `docs:check_refs` + linter-специ + model↔code sync. **Branch-protection (2026-06-19):** `main` вимагає `CI passed` (ci-ok), який тепер завжди звітує — `ci.yml` більше **НЕ** `paths-ignore`s docs (інакше docs-only PR не дав би required-чек). SSOT-доки **required** через `Docs passed` (`docs-ok` always-on aggregate, з path-gated `docs_check` під ним) — [`06_07 §2`](06_07_CICD_and_Runbook_Index) |

### 2.3 Протокол "SSOT Integrity Guard" (`ssot_guard.yml`)

Автоматична перевірка актуальності документації (The Codex).

- **Умова:** Pull Request вносить зміни в захищені зони: `app/{models,services,workers}/`, `firmware/{soldier,queen,bio_contracts,common}/` або `contracts/` (точний список — `paths:`-фільтр живого файла; він дзеркалить `mappings` у скрипті — розширювати ОБИДВА).
- **Дія:** Action перевіряє наявність відповідних змін у `docs/` (або `README.md`/`CLAUDE.md`). Якщо документація не оновлена — чек червоніє (`core.setFailed`), але **advisory за позицією**: він не в required-списку branch-protection, мердж фізично не блокується — так ратифіковано [`06_07 §2`](06_07_CICD_and_Runbook_Index).
- **Bypass:** PR із semantic-label з whitelist (`type:chore`, `type:deps`, `type:perf`, `type:test`) автоматично пропускається — ці типи **за визначенням** не змінюють архітектуру/контракти. **`type:refactor` та `type:bugfix` навмисно ВИКЛЮЧЕНО з auto-bypass**: рефакторинг змінює імена класів / шляхи (напр. `app/services/blockchain_minting_service.rb`), а багфікс — логіку (класичний приклад: FW.7 Lorenz BigDecimal→Float) → обидва спричиняють Context Drift у Wiki. Для них guard вимагає **або** оновлення відповідного `docs/`-файла, **або** запис відкритого drift-айтема у [`00_07`](00_07_Action_Plan_Tracker) (One-Home для backlog — саме туди їх адресує [`04_02 §13b`](04_02_Business_Logic_and_Services), а не в датований лог у каноні) — а він сам є зміною у `docs/`, тож автоматично задовольняє перевірку. Явний вибір label лишається форс-функцією: автор класифікує зміну, а не додає порожній коміт у `docs/`.

> **Чому семантичні label замість `skip-ssot-guard`:** Generic skip-label буде зловживатись (натиснув-обійшов). Семантичні `type:*` змушують автора публічно класифікувати зміну. Якщо PR має `type:bugfix`, але насправді міняє схему — code reviewer одразу побачить mismatch у заголовку та назві label.

> **One-Home:** живий файл — `.github/workflows/ssot_guard.yml` (`github-script`/JS: diff base...head → `mappings`-матч захищених зон → bypass-лейбли → `core.setFailed`); код тут не дублюється: YAML-дзеркало в каноні розходиться з файлом мовчки — воно вже одного разу розійшлось у пʼятьох місцях і навіть іменувало неіснуючий ключ, тож тримаємо політику тут, а конфігурацію — у файлі.

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
      # ⚠️ Скелет ілюстративний: у ЖИВОМУ файлі кожен зовнішній `uses:` запінено на
      # повний 40-символьний SHA з коментарем `# vN` — рухомий тег заборонено (§2.7).
      - uses: actions/checkout@<40-char-sha>   # v7
      - uses: EndBug/label-sync@<40-char-sha>  # v2
        with:
          config-file: .github/labels.yml
          delete-other-labels: false  # НЕ видаляти лейбли ботів (Dependabot/Snyk) і GitHub-дефолти; прибирання — свідомо, див. §2.5
          token: ${{ secrets.GITHUB_TOKEN }}
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

## 🏷️ 4. Label Conventions (SSOT)

Файл `.github/labels.yml` — Single Source of Truth для всіх **керованих проєктом** лейблів. Будь-яке нове project-label має бути занесене сюди до використання. `labels_sync.yml` створює/оновлює їх, але **не видаляє** сторонні/ботівські лейбли (`delete-other-labels: false`, §2.5) — прибирання застарілого project-label робиться свідомо, щоб не ламати інтеграції ботів.

### 4.1 Cross-cuts

- `priority:P0` / `P1` / `P2` / `P3` ([`00_07`](00_07_Action_Plan_Tracker))
- `complexity:XS/S/M/L/XL`
- `agent:ai` / `agent:human` / `agent:ops` / `agent:hybrid` _(назви labels без emoji у [`.github/labels.yml`](../.github/labels.yml); emoji `🤖 / 👤 / 🔧 / 🔗` — **візуальні маркери виконавця** в [`00_07`](00_07_Action_Plan_Tracker), а в каноні Tier I/II трапляються точково (👤 bench-residual / 🤖 AI-doable))_
- `type:chore` / `type:deps` / `type:perf` / `type:test` — **SSOT Guard auto-bypass**; `type:refactor` / `type:bugfix` — класифікація **без** bypass (вимагають docs-update або запису в [`00_07`](00_07_Action_Plan_Tracker), див. §2.3)

> **Усі лейбли ставляться вручну** — авто-лейблера в репо немає. Єдина машинно-читана родина — `type:*` (SSOT-Guard bypass, §2.3); решта існує для навігації очима.
