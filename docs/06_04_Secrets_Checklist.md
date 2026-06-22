# 06_04: Secrets Checklist (Інвентаризація Секретів)

## 🎯 Мета

Єдиний SSOT-checklist усіх секретів, необхідних для роботи системи в Canopy (staging) та Production. Документ закриває **[`00_07`](00_07_Action_Plan_Tracker) S1.1** («GitHub Secrets заповнення», deploy-контекст [`06_01`](06_01_Deployment_Kamal_Terraform)) — частину 🤖.

> **Принцип:** Секрет = **будь-яке значення, втрата якого означає можливість компрометації або знищення системи**: приватні ключі, паролі БД, master keys, API tokens, RPC credentials. Реальні значення **ніколи** не комітяться в git та не зберігаються у цьому документі.

> **Чотири місця зберігання секретів:**
> 1. **GitHub Repository Secrets** — для CI/CD workflows (`.github/workflows/*.yml`)
> 2. **`.kamal/secrets`** — runtime секрети для Kamal-деплою на VM (читаються з ENV або keychain)
> 3. **`deploy/akash/deploy.yaml`** — секрети Akash деплою (поточно `REQUIRED_SECRET_NOT_SET` плейсхолдери)
> 4. **`terraform/terraform.tfvars`** — секрети Terraform (НЕ комітиться, `*.tfvars` у `.gitignore`)

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — механізм секретів (AR-encryption non-deterministic, HKDF per-device, `.kamal/secrets`, `verify-secrets` CI gate) реалізований і перевірений у Canopy; production-значення ще не провіженені (операційна, не технологічна задача). Канон модульного TRL — [`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond).
- **Поточний стан:** Backend код підтримує всі секрети, але production значення **не встановлені** в GitHub repository та `.kamal/secrets`. Це блокує весь CI/CD pipeline.
- **Відкрите:** production secret values не провіжені (блокує CI/CD) → [`00_07`](00_07_Action_Plan_Tracker) (S1.1, S4.3, S5.6).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | Деплой (Kamal/Terraform secrets) |
| [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) | Akash SDL secrets (§Секрети SDL) |
| [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) | Grafana Cloud + Sentry DSN |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | S1.1, S4.3, S5.6 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. GitHub Repository Secrets (CI/CD)](#1-github-repository-secrets-cicd)
- [2. (Kamal Runtime)](#2-kamalsecrets-kamal-runtime)
- [3. Akash SDL ( + )](#3-akash-sdl-deployakashdeployyaml--deployyamltpl)
- [4. `terraform/terraform.tfvars](#4-terraformterraformtfvars)
- [5. Operational Procedures](#5-operational-procedures)
- [Залежності та посилання](#-залежності-та-посилання)
<!-- TOC:AUTO:END -->

---

## 1. GitHub Repository Secrets (CI/CD)

> **Шлях створення:** `Settings → Secrets and variables → Actions → New repository secret`
>
> **Перевірка покриття:** `grep -rh "secrets\." .github/workflows/ | grep -oP "secrets\.[A-Z_]+" | sort -u`
>
> Поточно у workflows використовуються: `CANOPY_DATABASE_URL`, `CANOPY_REDIS_URL`, `DATABASE_PASSWORD`, `DATABASE_URL`, `GCP_PROJECT_ID`, `GCP_SA_KEY`, `GITHUB_TOKEN` (auto), `KAMAL_MASTER_KEY`, `PROJECT_PAT`, `RAILS_MASTER_KEY`, `REDIS_URL`, `SSH_KNOWN_HOSTS`, `SSH_PRIVATE_KEY`, `SSH_PUBLIC_KEY`.

### 1.1. P0 — Blocking (без цих secrets CI/CD не запуститься)

- [ ] `RAILS_MASTER_KEY` — Rails credentials decryption key (`config/master.key`)
- [ ] `KAMAL_MASTER_KEY` — Kamal-encrypted secrets master key
- [ ] `GCP_SA_KEY` — GCP Service Account JSON ключ (raw або base64). Дозволи: `roles/artifactregistry.writer`, `roles/cloudsql.client`. Створюється в GCP IAM → Service Accounts → Keys.
- [ ] `GCP_PROJECT_ID` — ID GCP проєкту (наприклад, `silken-net-prod`)
- [ ] `DATABASE_PASSWORD` — пароль Cloud SQL `silken_net` user (≥16 символів, генерується одноразово, зберігається у password manager)
- [ ] `DATABASE_URL` — Production DB URL: `postgres://silken_net:<DATABASE_PASSWORD>@<cloud-sql-private-ip>:5432/silken_net_production` (отримується через `terraform output database_url`)
- [ ] `CANOPY_DATABASE_URL` — Canopy DB URL (окрема БД або схема: `silken_net_canopy`)
- [ ] `REDIS_URL` — Production Redis (DB 0, Upstash): `rediss://default:<password>@<endpoint>.upstash.io:6379/0`
- [ ] `CANOPY_REDIS_URL` — Canopy Redis (DB 0): `rediss://default:<password>@<endpoint>.upstash.io:6379/0`
- [ ] `SSH_PRIVATE_KEY` — приватний SSH ключ для Kamal deploy на VM (`ssh-keygen -t ed25519`)
- [ ] `SSH_PUBLIC_KEY` — публічний SSH ключ (пара до `SSH_PRIVATE_KEY`)
- [ ] `SSH_KNOWN_HOSTS` — SSH fingerprints production серверів (`ssh-keyscan <server-ip>`)

### 1.2. P1 — Operations (потрібні для конкретних автоматизацій)

- [ ] `PROJECT_PAT` — GitHub Personal Access Token з `project:write` scope (для `trl_sync.yml` GitHub Action — OPS.1). Тип: classic PAT або fine-grained PAT.

### 1.3. P2 — Опціонально / Auto-derived

- [ ] `KREDIS_REDIS_URL` — Production Redis (DB 1) для Kredis distributed locks. **Auto-derive:** якщо не встановлено, можна вивести з `REDIS_URL` замінивши `/0` → `/1` (зробити вручну для безпеки).
- [ ] `RACK_ATTACK_REDIS_URL` — Production Redis (DB 2) для rate limiting. Опціонально (auto-derive із `REDIS_URL`).
- [ ] `SCORECARD_TOKEN` — fine-grained read-only PAT (repo admin: read) для `Sec · Scorecard` (OpenSSF, OPS.10). **Опціонально:** без нього Scorecard працює, але пропускає Branch-Protection/Webhooks-перевірки (`GITHUB_TOKEN` їх не читає). Дім workflow — [`06_07 §1`](06_07_CICD_and_Runbook_Index).

---

## 2. `.kamal/secrets` (Kamal Runtime)

> **Шлях:** `.kamal/secrets` (НЕ комітити!). Файл уже існує у репо і містить **посилання на ENV** (`$VARIABLE`), не raw values. Перед `kamal deploy` встанови ці змінні у shell або CI environment.

- [ ] `RAILS_MASTER_KEY` — `$(cat config/master.key)` (читається локально під час деплою)
- [ ] `GCP_ARTIFACT_REGISTRY_KEY` — base64-encoded GCP Service Account JSON для pull Docker images з Artifact Registry. У CI підставляється з `GCP_SA_KEY`.
- [ ] `DATABASE_URL` — те саме значення що й GitHub Secret
- [ ] `REDIS_URL` — те саме значення
- [ ] `KREDIS_REDIS_URL` — Redis DB 1 (Kredis locks для Web3 nonce)
- [ ] `SENTRY_DSN` — Sentry project DSN. Без цього Sentry **інертний** — production помилки не репортуються (BLOCKER у [`00_07`](00_07_Action_Plan_Tracker)). Отримати: Sentry → Project Settings → Client Keys (DSN).
- [ ] `PROVISIONING_MASTER_KEY` — HKDF master key для per-device AES key derivation. Генерувати: `ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"`. ⚠️ **Production guard:** provisioning endpoint **MUST** raise/refuse при відсутності ENV у production (`Rails.env.production?`) — будь-який fallback на raw AES key є **критичною security regression** і допустимий ТІЛЬКИ у TRL4 lab mode (`RAILS_ENV=development|test`). Recommended controller-level guard: `raise "PROVISIONING_MASTER_KEY required in production" if Rails.env.production? && ENV["PROVISIONING_MASTER_KEY"].blank?`
- [ ] `CHAINLINK_FUNCTIONS_ROUTER` — адреса Chainlink Functions Router contract на Polygon
- [ ] `CHAINLINK_SUBSCRIPTION_ID` — ID Chainlink Functions subscription (з https://functions.chain.link)
- [ ] `CHAINLINK_HMAC_SECRET` — HMAC-SHA256 секрет для верифікації `X-Chainlink-Signature` header у `/api/v1/oracle_callbacks`. Генерувати як `SecureRandom.hex(32)`.
- [ ] `CHAINLINK_DON_ID` — DON ID (bytes32, наприклад `fun-polygon-mainnet-1`)

### 2.1. ENV-only змінні (НЕ у `.kamal/secrets`, потрібні воркерам)

> Ці змінні встановлюються через Kamal `env: clear:` або Akash SDL. Не є секретами в строгому сенсі, але без них Web3 пайплайн не працює.

- [ ] `RELEASE_VERSION` — git SHA або release tag для Sentry release tracking. ✅ Налаштовано у deploy pipeline (`deploy.yml`, `deploy-production.yml`, `config/deploy.yml`, `deploy/akash/deploy.yaml`).
- [ ] `ORACLE_PRIVATE_KEY` — приватний ключ EVM oracle wallet для мінтингу SCC/SFC. **Критичний.** Гаманець потребує MATIC для газу.
- [ ] `ETHEREUM_ANCHOR_PRIVATE_KEY` — приватний ключ для тижневого SHA-256 state root anchoring на L1. Потребує ETH для газу.
- [ ] `ALCHEMY_POLYGON_RPC_URL` — Alchemy/Infura RPC для Polygon (Primary). `Web3::ResilientClient` підтримує fallback cascade — також встанови `ALCHEMY_POLYGON_RPC_URL_FALLBACK_*` за потреби.
- [ ] `ALCHEMY_ETHEREUM_RPC_URL` — Alchemy RPC для Ethereum L1
- [ ] `CELO_RPC_URL` — Celo RPC endpoint (без значення — `Forno`-public; для production — Infura/Alchemy)
- [ ] `SOLANA_RPC_URL` — Solana RPC. ⚠️ **БЕЗ цього ENV дефолт = Solana Devnet** — мікро-винагороди USDC підуть на тестову мережу (`E.47` у [`00_07`](00_07_Action_Plan_Tracker))! Mainnet: Helius/QuickNode.
- [ ] `CARBON_COIN_CONTRACT_ADDRESS` — адреса SCC контракту після deploy
- [ ] `KLIMA_RETIREMENT_CONTRACT` — адреса KlimaDAO Retirement Aggregator
- [ ] `SOLANA_USDC_MINT_ADDRESS` — SPL Token mint USDC (mainnet: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`)
- [ ] `FILECOIN_PINNING_API_URL` — Pinata IPFS pinning service URL
- [ ] `WEB3_STRICT_MODE` — `true` у production. Якщо `true`, Web3 stubs (Chainlink, Hadron) raise при відсутності ENV.
- [ ] `RAILS_ALLOWED_HOSTS` — comma-separated allowlist хостів для захисту від DNS-rebinding атак (підтримує leading `.` для subdomain wildcard, напр. `api.silkennet.com,.silkennet.com`). Якщо не встановлено — Rails логує попередження `[SECURITY]` при кожному старті контейнера. Встановлюється через Kamal `env.clear` або Akash SDL. **⚠️ Обов'язково для production.**
- [ ] `DISABLE_SSL` — встановлювати лише `true` якщо TLS термінується зовнішнім проксі (Cloudflare Full-Strict, Akash ingress) і Rails сам не повинен форсувати HTTPS. За замовчуванням (`false` або відсутнє) `force_ssl` та `assume_ssl` активні. Встановлюється через Kamal `env.clear`.
- [ ] `ALLOW_ALL_HOSTS` — встановлювати `true` щоб заглушити попередження `[SECURITY]` про відсутній `RAILS_ALLOWED_HOSTS` (наприклад, якщо хости динамічні на Akash deployment). Не рекомендується без явного RAILS_ALLOWED_HOSTS.
- [ ] `CSP_ENFORCE` — встановлювати `true` щоб перевести Content Security Policy з `report-only` у `enforced` режим. Рекомендується після спостереження CSP violation-репортів протягом 1–2 тижнів у production.

---

## 3. Akash SDL (`deploy/akash/deploy.yaml` + `deploy.yaml.tpl`)

> **Статус:** SDL містить `REQUIRED_SECRET_NOT_SET` плейсхолдери для критичних змінних — відкрите [`00_07`](00_07_Action_Plan_Tracker) **S4.3** (Akash SDL secrets; деталі — [`06_02 §Секрети SDL`](06_02_Akash_Network_Integration)).
>
> **Рекомендований workflow:** використовувати `deploy/akash/deploy.yaml.tpl` Terraform-шаблон — секрети підставляються автоматично з `terraform.tfvars`.
>
> **Принцип:** SDL `web` та `job` сервіси повинні мати **ідентичні** ENV-блоки (окрім `WEB_CONCURRENCY` / `PORT` — web-specific). Sidekiq у `job`-сервісі ходить через ті ж Rails initializers, що вимагають boot-critical guards.

### 3.1. Web service env (та дзеркало в Job service env)

**Application core (boot):**
- [ ] `RAILS_MASTER_KEY` — те саме що в Kamal
- [ ] `DATABASE_URL` — Cloud SQL (через Cloud SQL Auth Proxy sidecar)
- [ ] `CLOUD_SQL_INSTANCE_CONNECTION_NAME` — `<project>:<region>:<instance>`
- [ ] `GCP_SA_KEY_BASE64` — base64-encoded GCP SA JSON (роль `roles/cloudsql.client` only)
- [ ] `REDIS_URL` — Upstash Redis DB 0 (`rediss://`)
- [ ] `KREDIS_REDIS_URL` — Upstash Redis DB 1 (`rediss://`)
- [ ] `RAILS_ENV` — `production` або `canopy`
- [ ] `RAILS_MAX_THREADS` — типово `3` (узгоджено з `database.yml` pool)
- [ ] `WEB_CONCURRENCY` — кількість Puma workers (web only, типово `4`)
- [ ] `PORT` — типово `80` (Thruster)

**🛑 Boot-critical (Puma crash до accept loop без значення):**
- [ ] `PROVISIONING_MASTER_KEY` — HKDF root key. `config/initializers/master_key_strength_check.rb` raises `SecurityError` у `after_initialize`. Generate: `ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"`

**Observability:**
- [ ] `SENTRY_DSN` — без неї Sentry inert (silent prod errors)
- [ ] `RELEASE_VERSION` — git SHA / release tag для Sentry release tracking
- [ ] `PROMETHEUS_AUTH_USER` / `PROMETHEUS_AUTH_PASSWORD` — Basic Auth для `/metrics`

**Web3 oracle keys (dual-key split, B-02 — без них Sidekiq DeadSet):**
- [ ] `ORACLE_PRIVATE_KEY` — legacy fallback (Celo/Toucan/Klima/PuroEarth/Etherisc)
- [ ] `ORACLE_MINTER_PRIVATE_KEY` — MINTER_ROLE на SCC/SFC (`BlockchainMintingService`)
- [ ] `ORACLE_SLASHER_PRIVATE_KEY` — SLASHER_ROLE (`BlockchainBurningService`)
- [ ] `ETHEREUM_ANCHOR_PRIVATE_KEY` — окремий wallet для weekly L1 anchor (`Ethereum::StateAnchorService`)

**RPC endpoints (`Web3::RpcConnectionPool` — `ENV.fetch` raises KeyError без значення):**
- [ ] `ALCHEMY_POLYGON_RPC_URL`
- [ ] `ALCHEMY_ETHEREUM_RPC_URL`
- [ ] `SOLANA_RPC_URL`

> **Boot guard:** `config/initializers/web3_network_guard.rb` ([`04_02 §8`](04_02_Business_Logic_and_Services)) fail-closes at boot у production / `WEB3_STRICT_MODE`, якщо `ORACLE_*` ключ відсутній/malformed **або** будь-який `*_RPC_URL` несе testnet-маркер (Amoy / devnet / Sepolia) — перетворює «Sidekiq DeadSet» / «mint на testnet» на гучний boot-refuse ДО прийому трафіку (розширює `E.47` на boot-time + EVM).

**Solana minting (`Solana::MintingService` raises explicit errors):**
- [ ] `SOLANA_WALLET_KEYPAIR` — 64-byte hex keypair
- [ ] `SOLANA_FEE_PAYER_PUBKEY` — base58
- [ ] `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` — USDC ATA, base58
- [ ] `SOLANA_USDC_MINT_ADDRESS` — base58 (mainnet: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`)

**Chainlink Functions Router v1 (Proof of Growth — S6.2):**
- [ ] `CHAINLINK_FUNCTIONS_ROUTER` — Polygon contract address
- [ ] `CHAINLINK_SUBSCRIPTION_ID` — numeric subscription ID
- [ ] `CHAINLINK_DON_ID` — bytes32, наприклад `fun-polygon-mainnet-1`
- [ ] `CHAINLINK_HMAC_SECRET` — HMAC-SHA256 для callback signature verification
- [ ] `CHAINLINK_DATA_VERSION` — default `1` (не sensitive)
- [ ] `CHAINLINK_CALLBACK_GAS_LIMIT` — default `300000` (не sensitive)

### 3.2. Job (Sidekiq) service env

- [ ] **Усе з §3.1** (Sidekiq потребує boot-critical guards так само як Puma) — окрім `PORT` / `WEB_CONCURRENCY`.

> **⚠️ AKASH ENV plaintext exposure:** Akash не шифрує ENV-блок SDL — значення видимі провайдеру через `lease-logs`/kubectl. Mitigation: scoped on-chain roles (MINTER/SLASHER only, ніколи DEFAULT_ADMIN), 90-day key rotation, audited providers (`signedBy.anyOf`). Детальніше: [`06_02 §Секрети SDL (Akash ENV plaintext)`](06_02_Akash_Network_Integration).

### 3.3. Grafana Alloy sidecar (observability)

- [ ] `ALLOY_CONFIG_BASE64` — base64-encoded Alloy config
- [ ] `GRAFANA_REMOTE_WRITE_URL` — Grafana Cloud Prometheus endpoint
- [ ] `GRAFANA_REMOTE_WRITE_USERNAME` — Grafana Cloud user/instance ID
- [ ] `GRAFANA_REMOTE_WRITE_TOKEN` — Grafana Cloud API token
- [ ] `PROMETHEUS_AUTH_USER` / `PROMETHEUS_AUTH_PASSWORD` — Basic auth для `/metrics` endpoint
- [ ] `PROMETHEUS_ALLOWED_IPS` — **[INF.5]** Comma-separated CIDR allowlist для `/metrics` endpoint у `PrometheusCollector` middleware (`app/middleware/prometheus_collector.rb`). Запити з адрес поза `PRIVATE_RANGES` (RFC 1918/4193 + localhost) ТА поза цим списком отримають `403 Forbidden`. Приклади:
  - **GCP-only Kamal:** залишити пустим — внутрішня VPC IP належить RFC 1918 (`10.x`), уже allowed.
  - **Akash deployment:** залежить від cluster network — Akash може дати немутальний CIDR. Перевір `kubectl get pods -n akash-services` (на Akash provider) або `terraform output akash_pod_cidrs`. Приклад: `PROMETHEUS_ALLOWED_IPS=10.42.0.0/16,10.43.0.0/16`.
  - **Cloudflare Proxy:** додати [Cloudflare IP ranges](https://www.cloudflare.com/ips/) якщо scrape йде через CF. Приклад: `PROMETHEUS_ALLOWED_IPS=173.245.48.0/20,103.21.244.0/22,...`.
  - **Grafana Cloud direct scrape:** не використовуйте direct scrape з `/metrics`; використовуйте Alloy `prometheus.remote_write` — внутрішній push не потребує allowlist.

---

## 4. `terraform/terraform.tfvars`

> **Шлях:** `terraform/terraform.tfvars` (`*.tfvars` у `.gitignore` — **ніколи не комітити!**)

**Інфраструктура GCP:**
- [ ] `project_id` — GCP project ID
- [ ] `db_password` — пароль Cloud SQL (≥16 символів)
- [ ] `ssh_source_ranges` — список CIDR для SSH allowlist (напр., `["1.2.3.4/32"]`)

**Akash deployment app/infra (`terraform/akash/terraform.tfvars` рендериться у `deploy.yaml.tpl`):**

> Mirror зі списку `env.secret` Kamal — повний breakdown див. [`06_02 §3.2 Змінні Terraform`](06_02_Akash_Network_Integration). 29 sensitive variables нижче.

*Application core:*
- [ ] `rails_master_key`
- [ ] `database_url` — `postgres://...@127.0.0.1:5432/silken_net_production`
- [ ] `cloud_sql_instance_connection_name` — `terraform output database_connection_name`
- [ ] `gcp_sa_key_base64` — base64-encoded SA JSON (роль `roles/cloudsql.client` only, див. [`06_02 §Security Exception`](06_02_Akash_Network_Integration))
- [ ] `redis_url` — Upstash `rediss://...:6379` (DB 0)
- [ ] `kredis_redis_url` — Upstash DB 1 (опц. — auto-derive з `redis_url` коли empty)

*🛑 Boot-critical:*
- [ ] `provisioning_master_key` — `SecureRandom.hex(32)`, валідація `length >= 32`

*Observability:*
- [ ] `sentry_dsn`
- [ ] `alloy_config_base64` — base64-encoded Grafana Alloy config (містить вбудований `grafana_remote_write_token` — sensitive!)
- [ ] `grafana_remote_write_url` — Grafana Cloud Prometheus `remote_write` endpoint (`https://prometheus-prod-XX-XX.grafana.net/api/prom/push`)
- [ ] `grafana_remote_write_username` — Grafana Cloud Stack ID
- [ ] `grafana_remote_write_token` — Grafana Cloud API ключ зі scope `metrics:write`
- [ ] `prometheus_auth_user` — Basic Auth user для `/metrics` endpoint
- [ ] `prometheus_auth_password` — Basic Auth password (`Rails.application.config.prometheus_auth`)

*Web3 oracle keys (dual-key split, B-02):*
- [ ] `oracle_private_key` — hex `0x…`
- [ ] `oracle_minter_private_key` — hex `0x…`
- [ ] `oracle_slasher_private_key` — hex `0x…`
- [ ] `ethereum_anchor_private_key` — hex `0x…` (MUST differ from `oracle_private_key`)

*RPC endpoints:*
- [ ] `alchemy_polygon_rpc_url`
- [ ] `alchemy_ethereum_rpc_url`
- [ ] `solana_rpc_url`

*Solana minting:*
- [ ] `solana_wallet_keypair`
- [ ] `solana_fee_payer_pubkey`
- [ ] `solana_fee_payer_token_account`
- [ ] `solana_usdc_mint_address`

*Chainlink Functions Router v1:*
- [ ] `chainlink_functions_router`
- [ ] `chainlink_subscription_id`
- [ ] `chainlink_don_id`
- [ ] `chainlink_hmac_secret`

> **🔴 Drift guard:** Кожен sensitive у `terraform.tfvars` **обов'язково** на момент `terraform apply` — без нього `templatefile()` рендерить порожні рядки → SDL отримує `=` без value → Rails отримує `nil` ENV. Для boot-critical (`provisioning_master_key`) це Puma crash; для Web3 — Sidekiq DeadSet; для Alloy — німі метрики. Drift у будь-яку сторону між `.kamal/secrets`, Kamal `env.secret`, SDL (`web` + `job`), `deploy.yaml.tpl`, `variables.tf`, та `main.tf` `templatefile()` — критичний bug. **Single source of truth: `config/deploy.yml env.secret` блок** (Kamal canonical list).

---

## 5. Operational Procedures

### 5.1. Перед першим деплоєм Production

1. [ ] 👤 Створити GCS bucket для Terraform state (S5.6 в [`00_07`](00_07_Action_Plan_Tracker)): `gsutil mb -l europe-west1 gs://<project>-terraform-state`. Включити versioning: `gsutil versioning set on gs://<project>-terraform-state`.
2. [ ] 👤 Створити `terraform/terraform.tfvars` з §4
3. [ ] 👤 Виконати `terraform init && terraform apply`
4. [ ] 👤 Заповнити GitHub Secrets з §1
5. [ ] 👤 Створити `.kamal/secrets` ENV у CI (з §2)
6. [ ] 👤 Заповнити Akash SDL секрети з §3 (або через `.tpl` + `terraform output`)
7. [ ] 👤 Поповнити Web3 wallets газом (MATIC, ETH, SOL, CELO)
8. [ ] 👤 Верифікувати CI pipeline проходить (`Actions` tab)

### 5.2. Ротація секретів

- **AES master key** (`PROVISIONING_MASTER_KEY`): ротація потребує перевипуску всіх per-device ключів через provisioning. Несумісно зі вже зашитими пристроями. Plan: `FW.17` (Hash Ratchet KDF) у майбутньому циклі.
- **Database password**: змінити Cloud SQL → оновити `DATABASE_URL`/`DATABASE_PASSWORD` GitHub Secret → `kamal redeploy`.
- **Sentry DSN**: rotate у Sentry UI → оновити `SENTRY_DSN` → redeploy.
- **Chainlink HMAC**: координовано з backend deploy (зміна на льоту викличе rejected callbacks).
- **Oracle/Anchor private keys**: deploy новий гаманець → revoke старий → перевести залишок газу → redeploy.
- **peaq_signing_key** (Ed25519 DID signing): планова ротація кожні 90 днів або при зміні персоналу. Dual-Key Grace Period 72 години (див. §5.4 нижче та [`04_02 §S6.14`](04_02_Business_Logic_and_Services)).

### 5.3. Аудит виконання

```bash
# Перевірка наявності всіх референсів у workflows
grep -rh "secrets\." .github/workflows/ | grep -oP "secrets\.[A-Z_]+" | sort -u

# Перевірка Kamal secrets
grep -E "^[A-Z][A-Z0-9_]*=" .kamal/secrets | cut -d= -f1 | sort -u

# Перевірка Akash SDL
grep -E "^\s+[A-Z_]+:" deploy/akash/deploy.yaml | head -50
```

### 5.4. Emergency Revocation Runbook — `peaq_signing_key` (S6.14)

> **Threat Model:** Компрометація `peaq_signing_key` дозволяє зловмиснику реєструвати фейкові DIDs на peaq network від імені SilkenNet. Кожен фейковий DID може бути прив'язаний до неіснуючого дерева → фейковий Proof of Growth → несанкціонований мінтинг SCC.

#### Крок 1: Detection (моніторинг)

Ознаки компрометації:
- Аномальні `POST /api/v1/provisioning/register` запити без відповідного hardware provisioning flow
- DIDs зареєстровані в peaq мережі, які не мають відповідних `Tree` записів у БД
- Незвичні патерни: масова реєстрація DIDs, реєстрація з невідомих IP

```bash
# Аудит DID реєстрацій за останні 24 години
bin/rails runner "
  recent = Tree.where('peaq_did IS NOT NULL AND created_at > ?', 24.hours.ago)
  puts \"DIDs registered last 24h: #{recent.count}\"
  recent.find_each { |t| puts \"  #{t.did} -> #{t.peaq_did} at #{t.created_at}\" }
"
```

#### Крок 2: Containment (< 15 хвилин)

**2a. Негайна заміна ключа в credentials:**

```bash
RAILS_CREDENTIALS_EDITOR=vim bin/rails credentials:edit
# 1. Скопіювати поточний peaq_signing_key → peaq_signing_key_previous
# 2. Згенерувати новий ключ:
#    ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"
# 3. Замінити peaq_signing_key на новий ключ
# 4. Зберегти та вийти
```

**2b. Негайний redeploy:**

```bash
# Zero-downtime deploy через Kamal
kamal deploy

# АБО якщо потрібен лише перезапуск додатку (без нового Docker image):
kamal app boot
```

**2c. (Опціонально) Тимчасова зупинка реєстрації:**

Якщо масштаб компрометації невідомий — тимчасово заблокувати provisioning endpoint:

```bash
# Додати feature flag або ENV
# В production console:
bin/rails runner "Rails.cache.write('provisioning_suspended', true, expires_in: 24.hours)"
```

#### Крок 3: Investigation (аудит)

```bash
# Визначити часовий діапазон компрометації
bin/rails runner "
  # Всі DID реєстрації за останній тиждень (або з моменту підозри)
  compromise_start = Time.parse('2025-XX-XXTXX:XX:XXZ')  # замінити на estimated time
  compromise_end   = Time.current

  suspect_trees = Tree.where(
    'peaq_did IS NOT NULL AND created_at BETWEEN ? AND ?',
    compromise_start, compromise_end
  )
  puts \"Potentially compromised DIDs: #{suspect_trees.count}\"
  suspect_trees.find_each do |t|
    puts \"  Tree ##{t.id}: did=#{t.did}, peaq_did=#{t.peaq_did}, org=#{t.organization_id}\"
  end
"
```

Перевірити:
- Чи є відповідний `HardwareKey` для кожного підозрілого `Tree`
- Чи є `TelemetryLog` записи від цих пристроїв
- Чи збігається `peaq_did` з тим, що зареєстровано на peaq chain (cross-reference через `peaq_node_url`)

#### Крок 4: Recovery

> ✅ **Реалізовано (SEC.13, 2026-05-29):** колонка `trees.peaq_did_compromised` (structure.sql) + skip-guard у `BlockchainMintingService` (мінтинг **пропускає** flagged-дерева, не валить весь батч) + spec. Команди нижче робочі. Defense-in-depth під час інциденту: додатково Крок 2c (suspend provisioning) + ротація `ORACLE_MINTER_PRIVATE_KEY`.

```bash
# Позначити потенційно компрометовані DIDs
bin/rails runner "
  compromise_start = Time.parse('2025-XX-XXTXX:XX:XXZ')
  compromise_end   = Time.parse('2025-XX-XXTXX:XX:XXZ')

  affected = Tree.where(
    'peaq_did IS NOT NULL AND created_at BETWEEN ? AND ?',
    compromise_start, compromise_end
  )
  affected.update_all(peaq_did_compromised: true)
  puts \"Flagged #{affected.count} trees as peaq_did_compromised\"
"
```

- Заблокувати мінтинг для compromised DIDs (guard clause в `BlockchainMintingService`)
- За необхідності — повторно зареєструвати легітимні DIDs з новим ключем

#### Крок 5: Post-Incident

1. **Ротація пов'язаних секретів:**
   - M2M tokens (якщо gateway використовував той самий credentials файл)
   - API keys, якщо є підозра на ширшу компрометацію credentials
   - `RAILS_MASTER_KEY` (якщо вектор атаки — витік master key)

2. **Документація інциденту:**
   - Timeline компрометації
   - Кількість affected DIDs
   - Root cause analysis
   - Corrective actions

3. **Превентивні заходи:**
   - Увімкнути scheduled rotation (кожні 90 днів) — [`04_02 §S6.14`](04_02_Business_Logic_and_Services)
   - Налаштувати alerting на аномальні provisioning патерни
   - Розглянути HSM/Vault для зберігання signing keys замість Rails credentials

> **Зв'язок:** Key Rotation Policy → [`04_02 §S6.14`](04_02_Business_Logic_and_Services)

---

## 🔗 Залежності та посилання

| Документ | Зв'язок |
|---|---|
| [`06_01`](06_01_Deployment_Kamal_Terraform) | Kamal/Terraform secrets (00_07 S1.1) |
| [`06_02`](06_02_Akash_Network_Integration) | Akash SDL secrets / `REQUIRED_SECRET_NOT_SET` (00_07 S4.3) |
| [`06_03`](06_03_Prometheus_Observability) | `SENTRY_DSN`, Grafana Cloud tokens |
| [`05_01`](05_01_Multichain_Architecture) | Web3 ENV variables (§5) |
| [`00_07`](00_07_Action_Plan_Tracker) | S1.1, S4.3, S5.2, S5.6 |
