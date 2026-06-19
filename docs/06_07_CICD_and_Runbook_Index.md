# 06_07: CI/CD Pipeline & Operations Runbook Index

## 🎯 Мета

Зафіксувати **повний набір CI/CD workflows** (`.github/workflows/`) як єдину систему — тригери, призначення, gates — та надати **єдиний індекс операційних runbook'ів** (які раніше були розкидані по 06_02/04/05/06). Runbook'и тут **не дублюються** — лише посилання на канонічний дім кожного (DRY).

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — workflows активні; production+canopy deploy налаштовані; **`main` захищено branch-protection** (required status check = `CI passed`, `enforce_admins=false` → owner лишає прямий push, PR-и гейтяться); `coap-smoke` gate заведений, але dormant до host-Variable (INF.6).
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
| `ci.yml` → **CI · Code** | PR + push `main` (no paths-ignore) | Path-gated by changed area — a `changes` job (`dorny/paths-filter`) flips firmware / ruby / js / python / alloy, and each job runs only when its area changed (a Gemfile bump skips the 25-min ARM build; a firmware-only change skips RSpec). The always-on **`ci-ok` aggregate (check name `CI passed`)** is the single **required** status check on `main` (branch-protection, `enforce_admins=false`). A change to `ci.yml`/the composite action self-validates the whole matrix. |
| `ssot_guard.yml` → **CI · SSOT Guard** | PR (paths: app/models, app/services, firmware/{soldier,queen,bio_contracts}, contracts) | code↔doc drift guard (OPS.2; advisory — path-gated, so NOT a hard required check) |
| `solidity_audit.yml` → **CI · Solidity** | PR/push `contracts/**` | Smart-contract static audit (forge + Slither) |
| CodeQL (GitHub **default-setup**) | PR + push `main` + weekly | First-party SAST — `Analyze (<lang>)` checks for actions/c-cpp/js/ts/python/ruby. Configured in the **Security tab** (no workflow file → a file-scan won't see it). |
| `in_silico_smoke.yml` → **Smoke · In-silico L2** | PR/push `tools/in_silico/**` | EBFC in-silico pipeline smoke (L2) |
| `docs.yml` → **CI · Docs** | PR/push `docs/**`, `**.md`, lib-docs engines/specs, `.github/**`, `app/models/**` | SSOT doc gates — `docs:check_refs` + `tracker:check` + linter-specs + model↔code sync ([`00_06 §3`](00_06_SSOT_Documentation_Standard)) |
| `ml_smoke.yml` → **Smoke · ML log-mel** | PR/push `tools/ml/**`, `firmware/common/logmel_*.h` | TinyML/log-mel contract smoke — `emit_c --check` golden-parity ([`00_06 §3`](00_06_SSOT_Documentation_Standard), [`03_03 §3.4`](03_03_TinyML_Acoustic_Inference)) |

### Deploy
| Workflow (`file` → name) | Trigger | Призначення |
|---|---|---|
| `deploy.yml` → **Deploy · Canopy** | `workflow_run` (CI success on `main`) + dispatch | **Canopy** deploy: terraform + `kamal deploy -d canopy`. `verify-secrets` **skips cleanly** (green run) when no deploy secrets are configured — no red noise. |
| `deploy-production.yml` → **Deploy · Production** | `release: published` + dispatch | **Production**: `verify-secrets` (SEC.11) → terraform apply → `kamal deploy`. The GitHub Release that triggers it is created by **Ops · Release** (release-please). |
| `coap_smoke.yml` → **Smoke · CoAP UDP** | `workflow_call` (job `coap-smoke` в обох deploy-workflows, `needs: deploy`) + dispatch | Post-deploy CoAP/UDP boundary smoke (INF.6; активується repo Variable `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST`, до того — видимо skipped) |
| `mirror-ghcr.yml` → **Deploy · GHCR Mirror** | `workflow_run` + `release` + dispatch | Дзеркалить Docker image у GHCR (для Akash pull). **Path-gated** — на workflow_run перебудовує лише коли змінились image-релевантні файли; пушить **SLSA provenance + SBOM** з образом (verify: `gh attestation verify oci://…`). |

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
          │                    └─→ Deploy · GHCR Mirror (path-gated, +provenance/SBOM)
          └→ Ops · Release (release-please тримає release-PR)
release-PR merge ─→ GitHub Release vX.Y.Z ─→ Deploy · Production (verify-secrets → terraform → kamal)
                                          └─→ Deploy · GHCR Mirror (semver tag)
```

> **Branch-protection (`main`):** required status check = **`CI passed`** (ci-ok), `enforce_admins=false` → owner лишає прямий push, PR-и (вкл. Dependabot / release-please) мерджаться лише на зеленому ci-ok. Налаштування: `gh api -X PUT repos/Alexey-Lukin/silken_net/branches/main/protection` (контексти + `enforce_admins`).
> **Gate-прогалини (tracked):** `coap-smoke` post-deploy gate dormant до host-Variables (`INF.6`); `ssot_guard` / `docs_check` лишаються **advisory** (path-gated → не можуть бути hard-required без блокування code-only PR; hard docs-gate = окремий рефактор `docs.yml` з changes+aggregate, OPS.2).

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
| Grafana Cloud dashboards + alerts import + post-deploy metrics verify (S2.1/S2.2/S2.3) | `deploy/grafana/README.md` (`import.rb` — datasource UID, contact point) + [`06_03 §2.9`](06_03_Prometheus_Observability) |
| **Bench-gated §06** (CoAP boundary smoke INF.6 · W25Q32 flash-ring ARCH.35) | `firmware/scripts/bench/RUNBOOK.md §5.3/§6` |
