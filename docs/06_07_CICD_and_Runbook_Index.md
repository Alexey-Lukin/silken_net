# 06_07: CI/CD Pipeline & Operations Runbook Index

## 🎯 Мета

Зафіксувати **повний набір CI/CD workflows** (`.github/workflows/`) як єдину систему — тригери, призначення, gates — та надати **єдиний індекс операційних runbook'ів** (які раніше були розкидані по 06_02/04/05/06). Runbook'и тут **не дублюються** — лише посилання на канонічний дім кожного (DRY).

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — workflows активні; production+canopy deploy налаштовані; **`main` захищено branch-protection** (required status checks = усі **8** детермінованих PR-гейтів: `CI passed` + `Docs passed` + `Solidity passed` + `CAD passed` + `ML passed` + `In-silico passed` + `IaC passed` + `DCO passed`, `enforce_admins=false` → owner лишає прямий push, PR-и гейтяться); `coap-smoke` gate заведений, але dormant до host-Variable (INF.6).
- **Supply-chain (OPS.10):** усі Actions + базовий Docker-образ pinned (SHA / `@sha256:` digest; Dependabot `github-actions`+`docker`) · top-level **token-permissions** least-privilege · `harden-runner` egress-audit (Linux) · **actionlint** workflow-gate · `Sec · Scorecard` weekly · secret-scanning + push-protection + CodeQL ON · CI CLI-тулзи hash-pinned (pip `--require-hashes`: Solidity-audit + in-silico pytest; + sha256-binaries). 👤-залишки (signed-commits, опц. toggles) → [`00_07`](00_07_Action_Plan_Tracker) OPS.10.
- **Відкрите:** активація coap-smoke (repo Variables — INF.6) → [`00_07`](00_07_Action_Plan_Tracker).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `.github/workflows/*.yml` | workflows (SSOT — фактична конфігурація) |
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | deploy-flow, Kamal/Terraform |
| [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) | Akash deploy |
| [`06_04` — Secrets Checklist](06_04_Secrets_Checklist) | secrets/revocation |
| [`06_05` — Puma Configuration](06_05_Puma_Configuration) | Puma runbooks |
| [`06_06` — Disaster Recovery and Backup](06_06_Disaster_Recovery_and_Backup) | DR runbooks |
| [`00_05` — GitHub Projects and IaC Automation](00_05_GitHub_Projects_and_IaC_Automation) | TRL/Projects automation |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | INF.6, OPS.1/OPS.2 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. CI/CD Workflows](#1-cicd-workflows-githubworkflows)
- [2. Pipeline flow](#2-pipeline-flow)
- [3. Operations Runbook Index (канонічні доми — НЕ дублювати тут)](#3-operations-runbook-index-канонічні-доми--не-дублювати-тут)
<!-- TOC:AUTO:END -->

---

## 1. CI/CD Workflows (`.github/workflows/`)

> **Naming:** workflows follow a `Категорія · Назва` taxonomy (CI · / Smoke · / Deploy · / Ops ·) so they group in the Actions UI. The table keys on the stable **filename**; the display `name:` is shown after `→`.

### Quality gates
| Workflow (`file` → name) | Trigger | Призначення |
|---|---|---|
| `ci.yml` → **CI · Code** | PR + push `main` (no paths-ignore) | Path-gated by changed area — a `changes` job (`dorny/paths-filter`) flips firmware / ruby / js / python / alloy / workflows / terraform / docker, and each job runs only when its area changed (a Gemfile bump skips the 25-min ARM build; a firmware-only change skips RSpec; a `.github/workflows/**` change runs **actionlint** + shellcheck via the `workflow_lint` job; a `terraform/**` change runs offline `terraform validate` + `fmt -check` on both roots via the `terraform_validate` job — no GCP creds, catches config errors pre-deploy since the deploy-workflow validate is secrets-gated, INF.15; a `deploy/**` change runs the alloy lane's `sdl_consistency_check` (static SDL ≡ `.tpl` — the INF.17 dead-path class at manifest level) + `deploy_secret_scan` (no committed key literals; signing set job-only); a `Dockerfile`/`Gemfile*`/`.ruby-version`/`vendor/**` change runs `docker_smoke` — full production-image build, `push:false` — closing the false-green class where the only image build fired post-merge from `main` (OPS.13, PR #463)). The always-on **`ci-ok` aggregate (check name `CI passed`)** is one of the **eight required** status checks on `main` (branch-protection, `enforce_admins=false`; full set → §2 callout below). A change to `ci.yml`/the composite action self-validates the whole matrix. |
| `ssot_guard.yml` → **CI · SSOT Guard** | PR incl. labeled/unlabeled (paths: app/{models,services,workers}, firmware/{soldier,queen,bio_contracts,common}, contracts) | code↔doc drift guard (OPS.2 §🗄️; advisory — path-gated, so NOT a hard required check) |
| `solidity_audit.yml` → **CI · Solidity** | PR/push `contracts/**` | Smart-contract audit: static (Slither + Aderyn) · symbolic (Halmos) · fuzz (Foundry + Medusa) · gas-regression (`forge snapshot --check` vs закомічений `contracts/.gas-snapshot`; tolerance 3%, без `invariant_` — fuzz-seed запінений у foundry.toml) · coverage-floor (deployable-контракти ≥90% lines per-file; lcov-Total розбавлений test-harness'ами by-design; `SilkenTimelock` відсутній у lcov — constructor-only). Aderyn SARIF → Security tab; усі gate-на-fail [CONTRACT.1] |
| CodeQL (GitHub **default-setup**) | PR + push `main` + weekly | First-party SAST — `Analyze (<lang>)` checks for actions/c-cpp/js/ts/python/ruby. Configured in the **Security tab** (no workflow file → a file-scan won't see it). |
| `scorecard.yml` → **Sec · Scorecard** | weekly + push `main` + `branch_protection_rule` + dispatch | OpenSSF supply-chain Scorecard (~18 checks) → SARIF у Security tab + публічний бейдж (`publish_results`, репо публічне). Опц. `SCORECARD_TOKEN` для Branch-Protection/Webhooks-перевірок (OPS.10). |
| `iac_scan.yml` → **Sec · IaC Scan** | PR/push `terraform/**`·`Dockerfile` + dispatch | Trivy `config` misconfig-скан IaC (terraform + Dockerfile) → SARIF у Security tab; **HARD** (`exit-code: '1'` — початковий soft-fail baseline тріажнуто до 0 відкритих, тож НОВИЙ misconfig валить білд; ловить його ДО першого деплою). Політика (tool-вибір · SHA-pin) — [`00_05 §2.7`](00_05_GitHub_Projects_and_IaC_Automation). [INF.22] |
| `sbom.yml` → **Sec · SBOM** | `release: published` + weekly `schedule` + dispatch | Агрегований **CycloneDX-1.6** SBOM усієї polyglot-поверхні (EU CRA Annex I Part II · enterprise-procurement): Trivy `fs` (gems/npm/conda-імена/NuGet-CPM) + власні фрагменти для того, чого не бачить ЖОДЕН сканер — git-сабмодулі (`scripts/sbom_submodules.rb`; емпірично: ні Syft, ні Trivy, ні GitHub-ів dependency-graph SBOM не дають жодного з 10) і `conda-lock.yml` (`scripts/sbom_conda_lock.rb`; жоден інструмент його не читає) — злиті власним `scripts/sbom_merge.rb` (чужий merge дефолтиться на specVersion 1.7 і демотить `metadata.component` у компоненти). **НЕ merge-гейт** — артефакт, тож свідомо без `pull_request`-тригера (інакше потрапив би в OPS.14-периметр за нуль безпеки). Названі стелі — у шапці воркфлоу. [BIZ.24] |
| `in_silico_smoke.yml` → **Smoke · In-silico L2** | PR/push `tools/in_silico/**` | EBFC in-silico pipeline smoke (L2) |
| `docs.yml` → **CI · Docs** | PR/push `docs/**`, `**.md`, lib-docs engines/specs, `.github/**`, `app/models/**` | SSOT doc gates — `docs:check_refs` + `tracker:check` + linter-specs + model↔code sync ([`00_06 §3`](00_06_SSOT_Documentation_Standard)) |
| `wiki.yml` → **Docs · Wiki Sync** | push `main` (paths: `docs/**`) + dispatch | Auto-publishes `docs/NN_NN_*.md` → GitHub wiki (00_00 → `Home` landing) via pure-Ruby `scripts/wiki_sync.rb` (no Rails boot, stdlib+git). Publish, **not** a gate. Off-switch: repo var `DISABLE_WIKI_AUTOSYNC=true` (for Shape-Up cycles / multi-maintainer). |
| `ml_smoke.yml` → **Smoke · ML log-mel** | PR/push `tools/ml/**`, `firmware/common/logmel_*.h` | TinyML/log-mel contract smoke — `emit_c --check` golden-parity ([`00_06 §3`](00_06_SSOT_Documentation_Standard), [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference)) |
| `cad_smoke.yml` → **Smoke · CAD PicoGK** | PR/push `tools/cad/**` | PicoGK Code-as-CAD — **2-job**: `logic` (Linux) = pure-xUnit **hard-gate** (CEM/SDF/mate math, PicoGK-runtime-free) + `render` (macOS Apple-Silicon) = `dotnet build` **hard** (LEAP source vs PicoGK 2.2) + `verify` golden-metrics best-effort (Library.Go SIGSEGV 139 headless) + CycloneDX SBOM/artifacts ([`01_02 §6`](01_02_Ti_6Al_4V_Metallurgy_and_DMLS)) |

> **Supply-chain hardening (OPS.10) — cross-cutting (не окремі рядки):** усі зовнішні `uses:` + базовий Docker-образ запінені (commit-SHA `# vN` / `@sha256:` digest; Dependabot `github-actions`+`docker` maintained); `step-security/harden-runner` (egress-audit) першим кроком кожного Linux-джоба (macOS `render` + no-op `ci-ok` пропущені); **token-permissions** — top-level read-floor + job-рівневий write-elevation (+ критичний `workflow_run`/`pull_request_target` не checkout-ить untrusted ref); **actionlint**-гейт workflow-файлів (`workflow_lint` у `ci.yml`); **pip-встановлювані CI-тулзи** hash-pinned (не лише version) — pip `--require-hashes` (locked `requirements-*.txt`: `halmos`/`crytic-compile` + in-silico `pytest` у `cache_doc_sync` + `conda-lock` у `lock_sync`) + sha256-verified release-binaries (`aderyn` — release-`.sha256`; `medusa` — hardcoded sha256, звірений із Sigstore-attestation). IaC-політика (дім, з обґрунтуванням) → [`00_05 §2.7`](00_05_GitHub_Projects_and_IaC_Automation).

### Deploy
| Workflow (`file` → name) | Trigger | Призначення |
|---|---|---|
| `deploy.yml` → **Deploy · Canopy** | `workflow_run` (CI success on `main`) + dispatch | **Canopy** deploy: terraform + `kamal deploy -d canopy`. **Path-gated [INF.9]** — на workflow_run деплоїть лише коли змінились image-релевантні (список mirror-ghcr — canopy = continuous для app-коду) або infra-файли (`terraform/` · `.kamal/` · сам workflow); firmware/docs/tools-only коміти видимо skip'аються, dispatch завжди деплоїть. `verify-secrets` **skips cleanly** (green run) when no deploy secrets are configured — no red noise. |
| `deploy-production.yml` → **Deploy · Production** | `release: published` + dispatch | **Production**: `verify-secrets` (SEC.11) → terraform apply → `kamal deploy`. The GitHub Release that triggers it is created by **Ops · Release** (release-please). **[INF.22] GH Environment `production`** гейтить `verify-secrets` + `deploy` (не `terraform` — його TF-вари repo-level, drift ділить): money-п'ятірка (legacy `ORACLE_PRIVATE_KEY` retired повністю — guard-tripwire) = environment-scoped secrets, wait-timer 10 хв **per-job** (2 гейти/release) + ref-policy `v*`∪`main` (dispatch поза ними падає до секретів). Куди класти секрети → [`06_04 §1`](06_04_Secrets_Checklist). |
| `coap_smoke.yml` → **Smoke · CoAP UDP** | `workflow_call` (job `coap-smoke` в обох deploy-workflows, `needs: deploy`) + **`schedule` кожні 30 хв** (`17,47 * * * *` — безперервний liveness анкора-SPOF, S2.4) + dispatch | Post-deploy CoAP/UDP boundary smoke (INF.6; активується repo Variable `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST`, до того — видимо skipped) |
| `mirror-ghcr.yml` → **Deploy · GHCR Mirror** | `workflow_run` + `release` + dispatch | Дзеркалить Docker image у GHCR (для Akash pull). **Path-gated** — на workflow_run перебудовує лише коли змінились image-релевантні файли; підписує образ **Sigstore-signed SLSA build-provenance** (`actions/attest-build-provenance`, keyless OIDC→Fulcio/Rekor) + BuildKit SBOM, attestation attached. User-facing verify → `SECURITY.md`. |
| `akash_escrow_watch.yml` → **Ops · Akash Escrow Watch** | `schedule` daily (`37 5 * * *`) + dispatch | FinOps-вартовий AKT-ескроу [OPS.11]: LCD REST → runway-математика, fail при < порога або нулі активних leases; skip-clean до repo Variable `AKASH_OWNER_ADDRESS`. Механіка → [`06_02 §4.4`](06_02_Akash_Network_Integration) |
| `terraform_drift.yml` → **Ops · TF Drift** | `schedule` weekly (`43 6 * * 2`) + dispatch | Scheduled drift-детектор: `terraform plan -detailed-exitcode` GCP-root проти LIVE-стану, fail-loud при drift (exit 2) → GH-notification власнику; **skip-clean** доки WIF-провайдер (repo Variable) + `GCP_PROJECT_ID`/`POSTGRES_PASSWORD` не задані (keyless OIDC-auth, INF.22 — guard дзеркалить verify-secrets; config-half зараз, активується з першим `apply`). GCP-root only — `terraform/akash/` = `null_resource`/local-exec (не refreshable provider → plan там no-op). Дім → [`06_01`](06_01_Deployment_Kamal_Terraform) [INF.22] |

### Repo / Project governance
| Workflow (`file` → name) | Trigger | Призначення |
|---|---|---|
| `release-please.yml` → **Ops · Release** | push `main` | Тримає release-PR (semver bump + CHANGELOG з conventional commits); merge → tag `vX.Y.Z` + GitHub Release → годує **Deploy · Production** + **Deploy · GHCR Mirror** |
| `trl_sync.yml` → **Ops · TRL Sync** | `issues` | GraphQL Projects v2 — TRL-stamping (OPS.1; [`00_05`](00_05_GitHub_Projects_and_IaC_Automation)) |
| `labeler.yml` → **Ops · PR Labeler** | `pull_request_target` | Auto-label PR за шляхами |
| `labels_sync.yml` → **Ops · Labels Sync** | push `.github/labels.yml` + dispatch | Labels-as-IaC sync |

## 2. Pipeline flow

```
PR ─→ CI · Code (changes → path-gated jobs → ci-ok = "CI passed")  ─┐ required: ci-ok green
   └→ CI · Docs / CI · Solidity / Smoke · * / CodeQL (за шляхами)    ▼
                                              merge main (PR; admin може push напряму)
main push ─→ CI · Code ──ci-ok──→ Deploy · Canopy ──→ Smoke · CoAP UDP
          │                    └─→ Deploy · GHCR Mirror (path-gated, +signed provenance/SBOM)
          └→ Ops · Release (release-please тримає release-PR)
release-PR merge ─→ GitHub Release vX.Y.Z ─→ Deploy · Production (verify-secrets → terraform → kamal)
                                          └─→ Deploy · GHCR Mirror (semver tag)
```

> **Branch-protection (`main`):** required status checks = усі **8** детермінованих PR-гейтів — **`CI passed`** (ci-ok) + **`Docs passed`** (docs-ok) + **`Solidity passed`** (solidity-ok, money-path SCC/SFC/Governor) + **`CAD passed`** + **`ML passed`** + **`In-silico passed`** + **`IaC passed`** (cad/ml/in-silico/iac smoke-агрегати) + **`DCO passed`** (dco-ok, inbound-contribution sign-off — 👤-флип 2026-07-25, UNI.20), `enforce_admins=false` → owner лишає прямий push, PR-и (вкл. Dependabot / release-please) мерджаться лише на всіх зелених. Кожен = `if:always()`-агрегат (path-gated джоба не може бути required напряму — skip блокує merge назавжди; агрегат емітить статус на КОЖНОМУ PR). Налаштування: `gh api -X PATCH repos/Alexey-Lukin/silken_net/branches/main/protection/required_status_checks` (контексти); перевірка периметра — `ruby scripts/workflow_gate_perimeter.rb --live` (OPS.14).
> **SSOT doc gate (OPS.2, landed):** `CI · Docs` runs on every PR/push; its always-on **`docs-ok` aggregate (check `Docs passed`)** is a **required** check on `main` alongside `CI passed` + the five solidity/smoke aggregates (path-gated `docs_check` can't be required directly — would block code-only PRs; `docs-ok` `if: always()` never skips). `ssot_guard` stays advisory (path-gated, `type:*` bypass).
> **Gate-прогалини (tracked):** `coap-smoke` post-deploy gate dormant до host-Variables (`INF.6`).
> **Signed commits (OPS.10, planned 👤):** `required_signatures` наразі `false`. Порядок ввімкнення: (1) локальний підпис — `git config --global gpg.format ssh` + `user.signingkey <~/.ssh/id_ed25519.pub>` + `commit.gpgsign true`, той самий ключ у GitHub як **Signing Key**; (2) тест-коміт → «Verified»; (3) ЛИШЕ ТОДІ ввімкнути (`gh api -X PUT …/branches/main/protection/required_signatures`). Порядок важливий — інакше тертя на push. Бот-коміти (Dependabot/release-please) GitHub підписує сам; `enforce_admins=false` → owner може обійти, але з локальним підписом усі коміти й так підписані. Дія → [`00_07`](00_07_Action_Plan_Tracker) OPS.10.
> **Gate-perimeter invariant (OPS.14, landed):** новий детермінований PR-гейт може народитися ПОЗА required-множиною непоміченим — саме так money-path `solidity_audit` лишався merge-advisory, поки канон казав «all gating». (Історія периметра: спершу required були лише `CI passed`+`Docs passed`; migration OPS.15/OPS.16 довела набір до семи, а DCO-флип 2026-07-25 — до нинішніх **восьми** ↑.) `scripts/workflow_gate_perimeter.rb` (HARD `docs.yml`, pure-Ruby) стереже сам периметр: курований `PERIMETER`-SSOT класифікує кожен PR-workflow у три відра — **`:required`** (merge-blocking через `if: always()`-агрегат, чиє `name:` ∈ branch-protection — усі вісім ↑) · **`:advisory_by_design`** (свідомо не блокує, з ратифікованою причиною — `ssot_guard.yml`, path-gated red-X інформує) · **`:flip_pending`** (МАЄ стати required, трекається в [`00_07`](00_07_Action_Plan_Tracker) — **наразі список ПОРОЖНІЙ**: OPS.15/OPS.16-migration solidity+4 смоків завершена 2026-07-19, останній мешканець `dco.yml` вийшов 2026-07-25 із 👤-флипом branch-protection [UNI.20]). HARD-осі: некласифікований PR-гейт → RED «класифікуй» · мертвий запис (workflow зник / більше не PR-тригер) · `:required` без свого `if: always()`-агрегату. Опційний `--live` (локально, не CI — токен CI не читає protection) звіряє `:required`-мітки з реальними `required_status_checks`. **Чому `:flip_pending` не «майже required», а окреме відро:** заявити `:required` до реального оновлення branch-protection = рівно той дрейф «канон каже gating, ніщо не гейтить», проти якого цей гейт і будувався; тож запис лишається `:flip_pending`, доки контекст не зʼявиться у `required_status_checks`.

---

## 3. Operations Runbook Index (канонічні доми — НЕ дублювати тут)

| Runbook | Дім (SSOT) |
|---|---|
| Перший деплой інфраструктури (GCS state → terraform → secrets → deploy) | [`06_01 §Quickstart`](06_01_Deployment_Kamal_Terraform) |
| Akash SDL deploy + `ALLOY_CONFIG_BASE64` encode + Alloy debug | [`06_02 §2 ENV (Секрети SDL)/INF.7`](06_02_Akash_Network_Integration) |
| TLS / Cloudflare verification (8-step) | [`06_02 §TLS термінація`](06_02_Akash_Network_Integration) |
| Secrets: pre-deploy checklist, rotation, audit | [`06_04 §5.1–5.3`](06_04_Secrets_Checklist) |
| **Emergency:** `peaq_signing_key` compromise/revocation | [`06_04 §5.4`](06_04_Secrets_Checklist) |
| Puma: SIGPWR backtrace dump, IPv6 listen verify | [`06_05 §Runbooks`](06_05_Puma_Configuration) |
| **DR:** Cloud SQL PITR restore, TF-state rollback, region rebuild | [`06_06 §5`](06_06_Disaster_Recovery_and_Backup) |
| Runtime failover (circuit breakers, comms-loss) | [`06_08`](06_08_Resilience_and_Failover_Policy) |
| `config.alloy` validation (local) | [`06_03 §2.9`](06_03_Prometheus_Observability) + `alloy_config_validate` CI |
| Grafana Cloud dashboards + alerts + contact point import (S2.2) + post-deploy metrics verify (S2.4) | `deploy/grafana/README.md` (`import.rb` — datasource UID + contact point/notification policy з ENV) + [`06_03 §2.9`](06_03_Prometheus_Observability) |
| **Bench-gated §06** (CoAP boundary smoke INF.6 · W25Q32 flash-ring ARCH.35) | `firmware/scripts/bench/RUNBOOK.md §5.3/§6` |
