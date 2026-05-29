# 06_07: CI/CD Pipeline & Operations Runbook Index

## 🎯 Мета

Зафіксувати **повний набір CI/CD workflows** (`.github/workflows/`) як єдину систему — тригери, призначення, gates — та надати **єдиний індекс операційних runbook'ів** (які раніше були розкидані по 06_02/04/05/06). Runbook'и тут **не дублюються** — лише посилання на канонічний дім кожного (DRY).

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — 11 workflows активні; production+canopy deploy налаштовані; частина gates ще не `required` (INF.6, OPS.2).
- **Пов'язані модулі:** [`06_01`](06_01_Deployment_Kamal_Terraform) (deploy) · [`06_02`](06_02_Akash_Network_Integration) (Akash) · [`06_04`](06_04_Secrets_Checklist) (secrets/revocation) · [`06_05`](06_05_Puma_Configuration) (Puma runbooks) · [`06_06`](06_06_Disaster_Recovery_and_Backup) (DR) · [`00_07`](00_07_GitHub_Projects_and_IaC_Automation) (Projects/TRL automation)

---

## 1. CI/CD Workflows (`.github/workflows/`)

### Quality gates
| Workflow | Trigger | Призначення |
|---|---|---|
| `ci.yml` | PR + push `main` | firmware host-tests, RAM-budget, brakeman, bundler-audit, importmap-audit, rubocop, i18n-tasks, **tracker:check**, **alloy_config_validate**, rspec, feature-tests |
| `ssot_guard.yml` | PR | SSOT integrity — code↔doc drift guard (OPS.2; ще не required) |
| `solidity_audit.yml` | PR/push `contracts/**` | Smart-contract статичний аудит |
| `in_silico_smoke.yml` | PR/push `tools/in_silico/**` | EBFC in-silico pipeline smoke (L2) |

### Deploy
| Workflow | Trigger | Призначення |
|---|---|---|
| `deploy.yml` | `workflow_run` (CI success on `main`) + dispatch | **Canopy** deploy: terraform + `kamal deploy -d canopy` |
| `deploy-production.yml` | `release: published` + dispatch | **Production**: `verify-secrets` (SEC.11) → terraform apply → `kamal deploy` |
| `coap_smoke.yml` | `workflow_call` (від deploy) + dispatch | Post-deploy CoAP/UDP boundary smoke (INF.6; ще не required gate) |
| `mirror-ghcr.yml` | `workflow_run` + `release` + dispatch | Дзеркалить Docker image у GHCR (для Akash pull) |

### Repo / Project governance
| Workflow | Trigger | Призначення |
|---|---|---|
| `trl_sync.yml` | `issues` | GraphQL Projects v2 — TRL-stamping (OPS.1; `00_07`) |
| `labeler.yml` | `pull_request_target` | Auto-label PR за шляхами |
| `labels_sync.yml` | push `.github/labels.yml` + dispatch | Labels-as-IaC sync |

## 2. Pipeline flow

```
PR ─→ ci.yml (+ ssot_guard / solidity_audit / in_silico за шляхами) ─→ merge main
main ─→ ci.yml ──success──→ deploy.yml (Canopy) ──→ coap_smoke (post-deploy)
                          └─→ mirror-ghcr.yml (image → GHCR)
release published ─→ deploy-production.yml (verify-secrets → terraform → kamal deploy)
                  └─→ mirror-ghcr.yml
```

> **Required-check прогалини (tracked):** `coap_smoke` ще не required post-deploy gate (`INF.6`); `ssot_guard` ще не required на `main` (`OPS.2`).

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
| Runtime failover (circuit breakers, comms-loss) | [`00_03`](00_03_Resilience_and_Failover_Policy) |
| `config.alloy` validation (local) | [`06_03 §2.9`](06_03_Prometheus_Observability) + `alloy_config_validate` CI |

---

## 🔗 Cross-references

| Файл / Документ | Зв'язок |
|---|---|
| `.github/workflows/*.yml` | 11 workflows (SSOT — фактична конфігурація) |
| `06_01_Deployment_Kamal_Terraform` | deploy-flow, Kamal/Terraform |
| `06_06_Disaster_Recovery_and_Backup` | DR runbooks |
| `00_07_GitHub_Projects_and_IaC_Automation` | TRL/Projects automation (trl_sync, labels) |
| `00_08_Action_Plan_Tracker` | INF.6 (coap gate), OPS.1/OPS.2 |
