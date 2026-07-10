---
name: deploy
description: "Use when deploying or operating silken_net infrastructure — Kamal/Terraform GCP, Akash decentralized cloud, secrets, observability (Grafana Alloy → Grafana Cloud), disaster-recovery, CI/CD, resilience/failover. This is Module 06 'The Matrix'. Routes to the 06_xx canon docs and the load-bearing infra invariants; does not restate them."
---

# Deploy & Infrastructure (Module 06 — The Matrix)

DevOps/Infra шар: Rails на **Akash** (децентралізовано, цензуростійко) +
**GCP** (Cloud SQL / Redis / failover). Деплой через **Kamal**, IaC через
**Terraform**, спостережуваність через **Grafana Alloy → Grafana Cloud**.

## Канон — читати ПЕРЕД зміною інфри/секретів/метрик

SSOT One-Home: цей skill лише **маршрутизує**; факти живуть у `docs/` + config-SSOT.
Не дублюй сюди значення/інвентар і **не хардкодь `file:line`** (дрейфує — стале вже за
комітом). Посилайся на стабільні якорі: канон-§ + імена символів/шляхів.

| Що треба | Канон-дім |
|---|---|
| Деплой **Kamal + Terraform GCP**, Canopy vs Production | `06_01` ← read-first для деплою |
| **Akash** SDL (`web` + `job` + `coap` + `alloy`), multi-provider failover | `06_02` |
| **Observability** — метрики / Alloy → Grafana Cloud / alerting | `06_03` (реєстр метрик — `06_03 §2.8`) |
| **Секрети** — інвентар + checklist (GitHub / Kamal / Akash / Terraform) | `06_04` (canonical = `config/deploy.yml env.secret`) |
| **Puma 8** config + cluster hooks + runbook'и | `06_05` |
| **Disaster Recovery** / backup / RTO-RPO / master-key | `06_06` (config SSOT = `terraform/database.tf`) |
| **CI/CD** workflows + єдиний operations runbook-індекс | `06_07` |
| **Resilience** — Queen failover (4 рівні) + Per-Chain Fallback Matrix | `06_08` |

## Несучі інваріанти (не очевидні з коду)

Будь-хто, хто чіпає деплой, МУСИТЬ це знати:

- **Akash + GCP — failover, не «або-або».** Rails-ворклоад на Akash; GCP тримає
  Cloud SQL + є failover-ціллю (Redis — зовнішній **Upstash** Serverless TLS, не GCP). → `06_01` / `06_02`.
- **CoAP-інтейк: PRIMARY = демон на Ingress Anchor** (e2-small; docker+systemd,
  VPC → Cloud SQL приватним IP БЕЗ Auth Proxy; секрети `/etc/silkennet/coap.env`,
  НЕ в metadata). Akash `coap`-сервіс = задеплоєний idle-**fallback** за socat;
  перемикання = 2×systemctl. Money/web лишаються на Akash (цензуростійкість). → `06_01` / `06_02`.
- **Cloud SQL Auth Proxy авторизує через Google API, але СОКЕТ іде на IP інстанса** —
  з Akash (поза VPC) досяжний лише ПУБЛІЧНИЙ IP → `ipv4_enabled = true` обов'язковий
  (authorized_networks порожній — доступ тільки IAM-proxy; ENCRYPTED_ONLY). private-only
  = crash-loop усіх сервісів у entrypoint-гейті. Проксі активується **лише** коли
  `CLOUD_SQL_INSTANCE_CONNECTION_NAME` заданий у ENV; Kamal-шлях (у VPC) — приватний IP напряму. → `06_02`.
- **Observability: Alloy → Grafana Cloud SaaS. Self-hosted Prometheus НЕ потрібен — за дизайном (OBS.1).**
  Prometheus-реєстр — **in-process** → Alloy скрейпить **три таргети** (`web:80` +
  `job:9394` + `coap:9395` embedded-експортери, лейбл `process`; порти 9394/9395 —
  service-scope only) → `remote_write` → Grafana Cloud. Механіка/стелі — `06_03 §2.9`;
  реєстр і кількість метрик — `06_03 §2.8` (regen з REGISTRY, **не хардкодь**).
- **Секрети One-Home:** канонічний дім — `config/deploy.yml env.secret`; повний
  інвентар + checklist — `06_04`. CI-гейт `verify-secrets`.
- **SSH на Ingress Anchor = IAP-тунель + OS Login, keyless (INF.20 (в), 2026-07-04).**
  Порт 22 в інтернет НЕ відкритий (firewall лише 35.235.240.0/20); metadata ssh-keys
  ІГНОРУЮТЬСЯ (`enable-oslogin=TRUE`); SSH-секретів у deploy-наборі НЕМАЄ. Вхід:
  `gcloud compute ssh silken-net-ingress --tunnel-through-iap` (доступ = tf-var
  `iap_admin_members` → osAdminLogin+tunnelResourceAccessor). CI-Kamal-нога dormant
  до (б)-клею (`ssh.proxy_command` через `start-iap-tunnel`). → `06_01` / 00_07 INF.20.
- **CI→GCP auth = keyless WIF (INF.22, 2026-07-10).** Deploy/drift-workflow НЕ тримають
  довгоживучий `GCP_SA_KEY` JSON — `google-github-actions/auth` карбує GitHub OIDC-токен
  (`id-token: write` per-job) → GCP STS → impersonated deploy-SA access-token (`terraform/wif.tf`:
  pool+provider, owner-`attribute_condition` + repo-`principalSet`, `lowerAscii()` case-safe).
  Provider+SA email = repo **Variables** (не secrets; presence = deploy-gate, замінив `GCP_SA_KEY`).
  Kamal registry = `oauth2accesstoken` + access-token. Виняток = Akash `GCP_SA_KEY_BASE64` (Cloud SQL
  proxy — зовн. провайдер не досягає GitHub-issuer'а). → `06_04 §1.1` / `06_02 §Security Exception`.
- **Akash SDL ENV — plaintext, видимий провайдеру.** Реальні ключі **ніколи** не в
  `deploy/akash/deploy.yaml`; інжектити через Akash Console / `env.secret`. **Money/signing-
  шістка (`ORACLE_*`×4 вкл. `CELO` + `ETHEREUM_ANCHOR` + `SOLANA_WALLET_KEYPAIR`) = JOB-ONLY** —
  web/coap бутяться keyless (guard scoped `signer_process: Sidekiq.server?`). → `06_02` / `06_04 §1.1`.
- **SEC.22 latch (credentials→ENV, 2026-07-09).** at-rest ≠ runtime: провайдер читає
  `/proc/environ`, тож `RAILS_MASTER_KEY` у runtime-ENV розшифровує весь vault. Розчинено:
  8 зовн.-сервісів + `storage.yml` читають `ENV[..].presence || credentials`; **AR-encryption
  ключі** (`hardware_keys`/`identities` at-rest) = ENV `ACTIVE_RECORD_ENCRYPTION_*` (boot-guard
  fail-closed; були DEAD-in-prod — ніде не сконфігуровані); coap-guard пропускає master_key-check.
  Phase-2 drop `RAILS_MASTER_KEY` = deploy-gated (👤; SECRET_KEY_BASE+service-keys inject-at-deploy).
  Дім → `06_04 §5.7` / 00_07 SEC.22.
- **Secrets-at-rest = три ISOLATED KMS-осі (2026-07-10).** Boot-disk Anchor'а (тримає
  `coap.env` master-keys) шифрується **CMEK** — keyring `silken-disk-ew1` (`kms.tf`, grantee =
  compute service-agent, НЕ deploy-SA); money-signing custody (SEC.17, pre-mainnet) = окремий
  keyring `silken-sign-ew1` (job-SA); **tf-state bucket** (3-тя plaintext-копія секретів) =
  keyring `silken-tfstate-ew1` — **bootstrap.sh-owned, out-of-band** (chicken-egg: ключ ДО
  `terraform init`; grantee = GCS service-agent; deploy-SA KMS-ролі НЕ потребує — objectAdmin
  достатньо; retention 10 версій/30д). Key-level IAM + purpose-enum-бар'єр; **НЕ** generic keyring
  (blast-radius merge-trap). CMEK boot-dependency: `reset`=DEK-cached (safe), лише stop→start/revoke
  б'є KMS (bounded: `prevent_destroy` + 30d-grace + Akash coap-fallback). ⚠️ найбільша at-rest-діра
  лишається **Akash-plaintext** (money-sextet + `RAILS_MASTER_KEY` provider-visible) → SEC.17. → `06_04 §5.6`.
- **Deploy/release ланцюг (2026-06-19).** Canopy = кожен push у `main` після CI (continuous);
  Production = GitHub Release, який тримає **release-please** (`Ops · Release`: semver+CHANGELOG із
  conventional commits → `release: published`); GHCR-mirror path-gated + пушить SLSA provenance+SBOM
  з образом (`gh attestation verify`). `verify-secrets` у Canopy **skip-clean** без секретів (Production
  лишається fail-loud). `main` захищено branch-protection (required `CI passed` + `Docs passed`,
  `enforce_admins=false` — owner пушить напряму). Деталі/діаграма — `06_07 §1`/`§2`.
- **GH Environment `production` = дім money-шістки (INF.22, 2026-07-10).** Signing-шістка
  (`ORACLE_*`×4 + `ETHEREUM_ANCHOR` + `SOLANA_WALLET_KEYPAIR`) у GitHub живе **environment-scoped**
  (`gh secret set X --env production`), НЕ repo-level — читають лише `deploy-production.yml`
  jobs `verify-secrets`+`deploy` (`environment:`); wait-timer 10 хв **per-job** (2 гейти/release)
  + ref-policy `v*`∪`main`. Canopy шістку НЕ споживає (web-only, гейт підрізано). Kamal secrets-файл =
  **`.kamal/secrets-common`** (з destination плейн `secrets` НЕВИДИМИЙ — Kamal читає лише
  `-common` + `secrets.<dest>`). → `06_04 §1` / `06_07 §1`.

## Карта коду / конфігів

| Шар | Шлях |
|---|---|
| Kamal deploy | `config/deploy.yml` · `config/deploy.canopy.yml` · `.kamal/secrets-common` |
| IaC (GCP) | `terraform/` (`compute.tf` — incl. анкор-демон systemd/env-file + boot-disk CMEK · `database.tf` · `vpc.tf` · `iam.tf` · `main.tf` · `kms.tf` — Cloud KMS keyring/IAM, disk-CMEK) |
| Akash | `deploy/akash/` (`deploy.yaml` SDL · `deploy.yaml.tpl` · `config.alloy` · `encode-alloy-config.sh`); SDL-гейт `ruby scripts/sdl_consistency_check.rb` (services≡deployment, static≡tpl — CI + локально перед комітом SDL-змін) |
| Observability | `config/initializers/prometheus.rb` (`SilkenNet::Metrics`) · `app/middleware/prometheus_collector.rb` · `lib/silken_net/metrics_exporter.rb` (embedded /metrics job/coap) · `deploy/akash/config.alloy` · Grafana IaC `deploy/grafana/` (`alerts/silkennet-alerts.yaml` · `dashboards/` · `import.rb`) |
| Web-сервер | `config/puma.rb` |
| CI/CD | `.github/workflows/` (`deploy.yml` — path-gated INF.9 · `deploy-production.yml` · `coap_smoke.yml` — post-deploy gate + 30хв liveness-schedule · `akash_escrow_watch.yml` — AKT-runway вартовий OPS.11, skip-clean до `AKASH_OWNER_ADDRESS` · `iac_scan.yml` — Sec·IaC-Scan (Trivy `config`, SARIF soft-fail; baseline у `.trivyignore`) · `terraform_drift.yml` — Ops·TF-Drift (weekly `plan -detailed-exitcode`, skip-clean до 3 secrets) · `mirror-ghcr.yml` · `release-please.yml` · `ci.yml` · `docs.yml` · `ssot_guard.yml`) |

## Gotchas (верифіковані, не з канону)

1. **jemalloc через `LD_PRELOAD`** у Docker-образі (`libjemalloc.so`) — менше пам'яті
   й латентності. Не прибирай без бенчмарку.
2. **`SENTRY_DSN` задається at deploy time** (`.kamal/secrets-common`); без нього Sentry
   інертний — нуль crash-репортів.
3. **Старт через Thruster** (`thrust ./bin/rails server`) за замовчуванням; overridable at runtime.

## Робочі правила

1. **Docs-first.** Прочитай `06_0N` (саме *чому* + поточний стан/TRL) перед зміною
   деплою, секрету чи метрики — кожен 06-док несе власний member-TRL у ✅ Статус.
2. **SSOT One-Home.** Правиш факт — правь у його домі (`06_04` секрети, `06_03 §2.8`
   метрики, `terraform/` config), не тут. Skill лишається тонким маршрутом.
3. **Гейти.** Після правок канону — `bin/rails docs:check_refs` зелений; робота над
   SSOT-доками 06_xx — через skill `ssot-maintenance`.
