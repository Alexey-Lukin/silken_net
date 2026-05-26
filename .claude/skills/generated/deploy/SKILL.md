---
name: deploy
description: "Domain knowledge for deployment — GCP/Kamal/Akash/Docker infrastructure, Prometheus metrics, Sentry, secrets management"
---

## Architecture Overview

Primary compute runs on **Akash Network** (decentralized, censorship-resistant). GCP hosts the **Ingress Anchor** (e2-micro, HAProxy+socat) that forwards HTTP/HTTPS/CoAP UDP to Akash, plus **Cloud SQL** (private, no public IP). Kamal is retained as fallback for direct GCP deploys.

## GCP (europe-west1, GDPR)

- **Cloud SQL PostgreSQL 16**: private-only (`ipv4_enabled = false`), REGIONAL HA, PIT recovery 30 days, `db-custom-2-7680`, SSD, autoresize. Four databases: production, cache (Solid Cache), queue (Solid Queue), cable (Solid Cable). Accessed from Akash via **Cloud SQL Auth Proxy** (built into Dockerfile, outbound HTTPS tunnel). Terraform: `terraform/database.tf`.
- **Ingress Anchor**: e2-micro with static IP (`google_compute_address.ingress_ip`). HAProxy forwards TCP 80/443, socat relays UDP 5683 (CoAP). Akash IP set via instance metadata. Kernel-tuned: conntrack 2M, UDP timeout 30s, CoAP rate-limit 100pps/srcip. Terraform: `terraform/compute.tf`.
- **Artifact Registry**: `europe-west1-docker.pkg.dev`, keeps latest 10 images, deletes >30 days. Also mirrored to GHCR for Akash.
- **Logging**: WARNING+ only ingested (cost control via `google_logging_project_exclusion`).

## Kamal (fallback / tooling)

Config: `config/deploy.yml`. Service `silken_net`, image `silken_net`.
- **Servers**: `web` + `job` (Sidekiq via `config/sidekiq.yml`).
- **Proxy**: ports 80, 443, 5683/udp (CoAP). SSL via Let's Encrypt (commented out, pending domain).
- **Registry**: Google Artifact Registry (`europe-west1-docker.pkg.dev`), auth via `GCP_ARTIFACT_REGISTRY_KEY`.
- **SSH**: user `deploy`, arch `amd64`.
- **Aliases**: `kamal console`, `kamal shell`, `kamal logs`, `kamal dbc`, `kamal canopy-console`, `kamal canopy-logs`.
- **Volumes**: `silken_net_storage:/rails/storage` (Active Storage).

## Akash Network (primary compute)

SDL: `deploy/akash/deploy.yaml`. Three services:
- **web**: Rails + Thruster (4 vCPU, 8Gi RAM, 50Gi ephemeral + 10Gi persistent). Ports: 80 (HTTP), 443 (HTTPS), 5683/udp (CoAP).
- **job**: Sidekiq (2 vCPU, 4Gi RAM, 20Gi). Entrypoint: `bundle exec sidekiq -C config/sidekiq.yml`.
- **alloy**: Grafana Alloy metrics agent (0.5 vCPU, 512Mi). Scrapes `/metrics` every 15s, pushes to Grafana Cloud via `remote_write`.

Image: `ghcr.io/alexey-lukin/silken_net:latest` (mirrored by CI). ENV vars are **plaintext to providers** -- rotate Web3 keys on 90-day cadence, use scoped on-chain roles. Template for Terraform-managed deploys: `deploy/akash/deploy.yaml.tpl`.

## Docker

`Dockerfile`: multi-stage build on `ruby:4.0.2-slim`. Base installs jemalloc, libvips, postgresql-client. Build stage compiles gems + bootsnap + assets. Final stage adds Cloud SQL Auth Proxy (`v2.15.2`), runs as non-root user 1000. Entrypoint: `bin/docker-entrypoint`. CMD: `./bin/thrust ./bin/rails server` (Thruster HTTP/2 proxy on port 80).

## Prometheus / Observability

Rails exposes `/metrics` (Basic Auth: `PROMETHEUS_AUTH_USER`/`PROMETHEUS_AUTH_PASSWORD`). 20 metrics: 10 counters + 8 gauges + 2 histograms. Grafana Alloy sidecar on Akash scrapes and pushes to Grafana Cloud. Grafana dashboards and alerts in `deploy/grafana/`. **BLOCKER**: no standalone Prometheus Server in Terraform (resolved by Grafana Cloud SaaS via Alloy).

## Sentry

Version 6.5.0. `SENTRY_DSN` declared in `.kamal/secrets` and Akash SDL. `RELEASE_VERSION` env var tracks deploy SHA. `send_default_pii: false` (Zero-Trust). Without `SENTRY_DSN` set at deploy time, Sentry is inert and production errors are silent.

## Secrets (.kamal/secrets)

All secrets pulled from ENV -- never hardcoded. Key groups: application core (`RAILS_MASTER_KEY`, `DATABASE_URL`, `REDIS_URL`, `KREDIS_REDIS_URL`), observability (`SENTRY_DSN`), hardware (`PROVISIONING_MASTER_KEY`), Web3 oracle keys (4 keys, dual-key split), RPC endpoints (3 chains), Solana minting (4 vars), Chainlink Functions (4 vars). Drift guard: every `env.secret` entry in `deploy.yml` MUST also appear in `.kamal/secrets`.

## Gotchas

1. **Antenna BEFORE power** on SX1262 -- powering the radio without antenna damages the PA. Hardware pre-flight check.
2. **Per-device AES keys via HKDF** -- LoRa AES-128 for Tree, CoAP AES-256 for Queen. Domain separation in HKDF info strings.
3. **SENTRY_DSN must be set at deploy time** -- otherwise error tracking is completely silent in production.
4. **Akash ENV plaintext** -- providers see all env vars. Never put long-lived admin keys; use scoped roles.
5. **Ingress Anchor IP update** -- after Akash redeployment, update metadata: `gcloud compute instances add-metadata silken-net-ingress --metadata akash-deployment-ip=<IP> --zone europe-west1-b` then reset instance.
6. **Cloud SQL Auth Proxy** -- activated by `CLOUD_SQL_INSTANCE_CONNECTION_NAME` env var. Needs `GCP_SA_KEY_BASE64`.

## Common Tasks

- **Deploy (Kamal)**: `kamal deploy` (builds, pushes, deploys). Logs: `kamal logs` or `kamal app logs -r job`.
- **Deploy (Akash)**: `akash tx deployment create deploy/akash/deploy.yaml --from <wallet> --chain-id akashnet-2` or `cd terraform/akash && terraform apply`.
- **Rails console**: `kamal console` or `kamal canopy-console` (canopy env).
- **DB console**: `kamal dbc`.
- **Update Akash IP on Ingress**: update metadata + `gcloud compute instances reset silken-net-ingress --zone europe-west1-b`.
- **Infrastructure changes**: `cd terraform && terraform plan && terraform apply`.
- **Check secrets drift**: verify every `env.secret` in `config/deploy.yml` has a matching line in `.kamal/secrets`.
