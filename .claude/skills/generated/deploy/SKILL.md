---
name: deploy
description: "Navigation + gotchas for GCP/Kamal/Akash deployment. Read SSOT docs first."
---

# Deploy & Infrastructure

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §10` | GCP, Kamal, Akash, Docker, Prometheus, Sentry overview |
| `docs/07_01_Infrastructure.md` | GCP setup, Cloud SQL, Redis, networking |
| `docs/07_02_Deployment_Guide.md` | Kamal config, deploy commands, rollback |
| `docs/07_03_Akash_Decentralized_Cloud.md` | Akash SDL, censorship-resistant deployment |
| `docs/07_04_Monitoring_and_Alerting.md` | Prometheus metrics, Grafana, Sentry |
| `docs/03_05_Security_Architecture.md §8` | Secrets management, .kamal/secrets |

## Gotchas Not Obvious From Docs

1. **SENTRY_DSN must be set at deploy time** — listed in `.kamal/secrets` as `SENTRY_DSN=$SENTRY_DSN`. Without it, Sentry is inert (no crash reporting).
2. **Prometheus Server missing in Terraform** — `/metrics` endpoint exists (20 metrics) but no Prometheus Server to scrape it. BLOCKER.
3. **Akash SDL ENV is plaintext** — secrets in `deploy/akash/deploy.yaml` are not encrypted. Don't put real keys there.
4. **Antenna BEFORE power** — SX1262 hardware: powering radio without antenna damages PA. Pre-flight check for field deployments.
5. **Docker image uses jemalloc** — Ruby memory allocator. Don't remove `LD_PRELOAD` from Dockerfile without benchmarking.
6. **Cloud SQL Auth Proxy** — baked into Docker image. Needs `GOOGLE_APPLICATION_CREDENTIALS` or workload identity.
