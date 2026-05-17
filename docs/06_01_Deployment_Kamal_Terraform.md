# 06_01: Розгортання Kamal & Terraform (Canopy vs Production)

## 🎯 Мета

Зафіксувати повний стан конфігурацій розгортання та інфраструктури як коду (IaC). Документ відповідає на три ключові питання:

1. Чим відрізняються середовища **Canopy** (Staging) та **Production**?
2. Що розгортається в **GCP** (традиційна хмара), а що — в **Akash Network** (децентралізована мережа)?
3. Які **API-ключі, секрети та сертифікати** потрібні для першого реального деплою?

---

## ✅ Статус

- **Поточний TRL:** TRL 4 — інфраструктурний код існує, реальний деплой не проводився
- **Пов'язані модулі:**
  - Backend → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Observability → [`06_03_Prometheus_Observability`](06_03_Prometheus_Observability)
  - Akash → [`06_02_Akash_Network_Integration`](06_02_Akash_Network_Integration)
  - Contracts → [`docs/DEPLOYMENT.md`](../DEPLOYMENT.md) — детальна операційна документація
  - IaC → `terraform/`, `terraform/akash/`
  - Kamal → `config/deploy.yml`, `config/deploy.canopy.yml`
  - SDL → `deploy/akash/deploy.yaml`

---

## 🛑 Блокери

> Цей розділ є критично важливим. Жоден реальний деплой неможливий без вирішення цих пунктів.

### 🔴 BLOCKER-1: IP-адреса Ingress Anchor — плейсхолдер

**Статус:** Не заповнено. Блокує DNS та маршрутизацію трафіку до Akash.

Після інфраструктурного піввоту залишається лише одна статична IP — **Ingress Anchor** (`e2-micro`), який проксює HTTP/HTTPS/CoAP трафік на Akash deployment. GCP web/canopy VM більше не існують.

**Дія:** Після `terraform apply` отримати IP:
```bash
terraform output ingress_ip    # → єдина статична IP (Ingress Anchor)
```

> `web_server_ips` та `canopy_server_ip` більше не існують. DNS A-запис вказує на `ingress_ip`.

---

### 🔴 BLOCKER-3: GitHub Secrets — не заповнені

**Статус:** Жоден CI/CD pipeline не спрацює без них.

| Секрет | Опис | Де отримати |
|--------|------|------------|
| `GCP_SA_KEY` | JSON ключ GCP Service Account (base64) | IAM → Service Accounts → Keys |
| `GCP_PROJECT_ID` | ID GCP проєкту | GCP Console |
| `DATABASE_PASSWORD` | Пароль Cloud SQL (≥16 символів) | Придумати. Зберегти у vault. |
| `DATABASE_URL` | Production DB URL | `terraform output database_url` |
| `CANOPY_DATABASE_URL` | Canopy DB URL | Окрема БД або схема |
| `REDIS_URL` | Production Redis (DB 0) — Sidekiq | Upstash: `rediss://<host>:<port>/0` (TLS) |
| `CANOPY_REDIS_URL` | Canopy Redis (DB 0) | Upstash: `rediss://<host>:<port>/0` |
| `KREDIS_REDIS_URL` | Production Redis (DB 1) — Kredis locks | Upstash: `rediss://<host>:<port>/1` |
| `RACK_ATTACK_REDIS_URL` | Production Redis (DB 2) — Rate limiting (опц., auto-derive) | Upstash: `rediss://<host>:<port>/2` |
| `SSH_PRIVATE_KEY` | Приватний SSH ключ (ed25519) | `ssh-keygen -t ed25519` |
| `SSH_PUBLIC_KEY` | Публічний SSH ключ | Пара до SSH_PRIVATE_KEY |
| `SSH_KNOWN_HOSTS` | SSH fingerprints серверів | `ssh-keyscan <server-ip>` |
| `KAMAL_MASTER_KEY` | Ключ шифрування Kamal secrets | `config/master.key` |

---

### ⬜ BLOCKER-4: `canopy_enabled` — N/A (Canopy на Akash)

**Статус:** N/A. Canopy (staging) тепер розгортається на Akash Network, а не на окремій GCP VM. Змінна `canopy_enabled` в Terraform більше не впливає на інфраструктуру — GCP містить лише Cloud SQL та Ingress Anchor (`e2-micro`).

**Дія:** Створити `terraform/terraform.tfvars` (в `.gitignore`!):
```hcl
project_id     = "your-gcp-project-id"
db_password    = "your-super-secret-password-16chars+"
ssh_source_ranges = ["<your-ip>/32"]
```

> ⚠️ `terraform.tfvars` містить секрети — **ніколи не комітити в git**.
> Canopy/Production розрізняються на рівні Akash SDL та environment variables, не GCP ресурсів.

---

### 🟡 BLOCKER-5: Akash SDL має `REQUIRED_SECRET_NOT_SET` плейсхолдери

**Статус:** `deploy/akash/deploy.yaml` потребує ручного редагування перед деплоєм. SDL дзеркалює повний список `env.secret` з Kamal (`config/deploy.yml`), включно з:
- 🛑 **Boot-critical:** `PROVISIONING_MASTER_KEY` (Puma crash без значення — `master_key_strength_check.rb`)
- **Web3 worker (DeadSet без значення):** `ORACLE_PRIVATE_KEY`, `ORACLE_MINTER_PRIVATE_KEY`, `ORACLE_SLASHER_PRIVATE_KEY`, `ETHEREUM_ANCHOR_PRIVATE_KEY`, `ALCHEMY_POLYGON_RPC_URL`, `ALCHEMY_ETHEREUM_RPC_URL`, `SOLANA_RPC_URL`, `SOLANA_WALLET_KEYPAIR`/`FEE_PAYER_PUBKEY`/`FEE_PAYER_TOKEN_ACCOUNT`/`USDC_MINT_ADDRESS`, `CHAINLINK_FUNCTIONS_ROUTER`/`SUBSCRIPTION_ID`/`DON_ID`/`HMAC_SECRET`
- **Observability (silent failure):** `SENTRY_DSN`

**Дія (рекомендовано):** Використати Terraform-шаблон `deploy/akash/deploy.yaml.tpl` — секрети підставляються автоматично з `terraform.tfvars`. Повний список Terraform-змінних та per-секрет breakdown див. [`06_02 §BLOCKER-3`](06_02_Akash_Network_Integration) та [`06_02 §Розділ 2 ENV Variables`](06_02_Akash_Network_Integration). Drift guard: будь-який новий ENV у `env.secret` Kamal має паралельно з'явитись у `.kamal/secrets`, обох сервісах SDL (`web` + `job`), `deploy.yaml.tpl`, `terraform/akash/variables.tf`, та `terraform/akash/main.tf` (`templatefile()` map). Інакше Akash deployment отримає boot crash або тиху Web3 відмову.

---

### 🟢 INFO: `deploy-production.yml` workflow не знайдено

У репо є тільки `.github/workflows/deploy.yml` (для Canopy). Production деплой потребує окремого `deploy-production.yml`.

**Дія:** Створити аналогічно `deploy.yml` з тригером `on: release: types: [published]` та деплоєм без `-d canopy`.

---

## ⚠️ Pre-Flight Checklist (до першого фізичного деплою)

> **НОВА СЕКЦІЯ (інтегровано нотатки N7–N12, N18).** Це доповнення до існуючих блокерів Terraform/Kamal — фокус на типових помилках при першому виводі системи в роботу.

П'ять речей, які можуть мовчки зламати перший деплой:

| # | Перевірка | Деталі |
|---|-----------|--------|
| **1** | **DNS propagation до `kamal setup`** | Після `terraform apply` скопіюй IP та створи A-запис (`api.silkennet.com → <IP>`). Дочекайся: `dig api.silkennet.com` → правильний IP. **Тільки тоді** запускай `kamal setup`. Причина: Traefik використовує Let's Encrypt HTTP-01 challenge. Без DNS — сертифікат не видасться, Traefik не підніметься. |
| **2** | **`.kamal/secrets` файл існує + повний** | Kamal читає секрети з `.kamal/secrets` (не з environment). Заповни **усі** змінні з `config/deploy.yml env.secret` (drift = boot crash або silent Web3 failure): **(a) Application core:** `RAILS_MASTER_KEY`, `DATABASE_URL`, `REDIS_URL`, `KREDIS_REDIS_URL`, `GCP_ARTIFACT_REGISTRY_KEY`. **(b) 🛑 Boot-critical:** `PROVISIONING_MASTER_KEY` (`master_key_strength_check.rb` raises `SecurityError` без неї). **(c) Observability:** `SENTRY_DSN`. **(d) Web3 oracle keys:** `ORACLE_PRIVATE_KEY`, `ORACLE_MINTER_PRIVATE_KEY`, `ORACLE_SLASHER_PRIVATE_KEY`, `ETHEREUM_ANCHOR_PRIVATE_KEY`. **(e) RPC endpoints:** `ALCHEMY_POLYGON_RPC_URL`, `ALCHEMY_ETHEREUM_RPC_URL`, `SOLANA_RPC_URL`. **(f) Solana minting:** `SOLANA_WALLET_KEYPAIR`, `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS`. **(g) Chainlink:** `CHAINLINK_FUNCTIONS_ROUTER`, `CHAINLINK_SUBSCRIPTION_ID`, `CHAINLINK_HMAC_SECRET`, `CHAINLINK_DON_ID`. **Той самий список застосовується для Akash SDL** (`deploy/akash/deploy.yaml` + `deploy.yaml.tpl`) та Terraform (`terraform/akash/terraform.tfvars`) — див. [`06_02 §BLOCKER-3`](06_02_Akash_Network_Integration). |
| **3** | **Gas на Web3-гаманцях** | Воркери потребують нативної крипто: **MATIC** (Polygon), **ETH** (L1), **SOL** (Solana), **CELO** (Celo). Без газу → "Insufficient Funds" на кожній транзакції → Sidekiq потоне у ретраях. |
| **4** | **LoRa-антена підключена** | **КРИТИЧНО.** Ніколи не подавай живлення без антени на SMA/U.FL порту. SX1262 відбиває RF назад у чип (high VSWR) — радіотракт згоряє за мілісекунди. Незворотно. Правило: антена → живлення. |
| **5** | **Симетрія AES-ключів** | `aes_key[8]` у `soldier/main.c` та `queen/main.c` — **побітово ідентичні**. Один відмінний біт → Queen читає сміття з кожного пакету. Ліс мовчить без помилок. Перевіряй перед кожним flash-циклом. Детальніше: `03_05_Hardware_AES256_and_Security`. |
| **6** | **CoAP UDP smoke test через Ingress Anchor** | **[INF.6]** Перевір end-to-end UDP-шлях `Queen → Ingress Anchor (HAProxy/socat) → Akash → CoAP daemon` ПЕРЕД першим прошиванням Queen. Без цього silent UDP failure не помітний з HTTP-only health checks. **Автоматизовано:** `.github/workflows/coap_smoke.yml` (`workflow_dispatch` для ad-hoc запуску, `workflow_call` для post-deploy gate з `deploy.yml`); приймає inputs `host` / `port` (default `5683`) / `path` (default `/api/v1/telemetry/smoke`) / `timeout_seconds` (default `30`). **Ручні команди (з машини за межами VPC, що імітує Queen):** <br>`apt-get install -y libcoap2-bin` <br>`coap-client -m post -e '{"smoke":"test"}' coap://api.silkennet.com:5683/api/v1/telemetry/smoke -B 5 -v 9` <br>Очікуваний результат: `2.04 Changed` або `4.04 Not Found` (≠ timeout/`5.00`). Якщо timeout: перевір (a) GCP firewall `allow-coap` UDP 5683 = `0.0.0.0/0`; (b) Ingress Anchor `socat UDP-LISTEN:5683,fork UDP:<akash-pod-ip>:5683`; (c) Akash SDL expose `5683/udp`; (d) `lib/daemons/coap_listener.rb` запущений у Sidekiq. Альтернативний smoke test через `nc`: `echo -ne '\x40\x02\x00\x01' \| nc -u -w2 api.silkennet.com 5683 \| xxd` — повертає бінарний CoAP response якщо daemon приймає UDP. |
| **7** | **Schema bootstrap від squashed init_consolidated** | **[INF.7 — Phase 7]** На свіжій базі деплой `bin/rails db:setup` (= `db:create` + `db:schema:load` + `db:seed`). Ми **НЕ** використовуємо `db:migrate` в продакшні до першого деплою — всі pre-launch міграції згорнуті в `db/migrate/20260509120000_init_consolidated.rb`, а схема живе в `db/structure.sql` (включно з усіма 9 Codex-таблицями + 4 RANGE-партиційними таблицями + початковими партиціями `_default` + `y2026m04..m09`). `schema_migrations` містить рівно ОДИН рядок `20260509120000`. Якщо хтось додає incremental міграцію після цього — `StrongMigrations.start_after = 20260509120000` змусить її пройти всі checks. **НЕ** робіть squash повторно після першого деплою (втратите history) без zero-downtime плану. |
| **8** | **PartitionMaintenanceWorker cron у Sidekiq** | **[INF.8 — Phase 7]** `30 0 * * *` UTC, `PARTITIONED_TABLES = %w[telemetry_logs gateway_telemetry_logs blockchain_transactions codex_matches]`. На день-1 нового місяця партиція повинна вже існувати — інакше `INSERT` падає з `no partition of relation`. Перевір через `psql -c "\d+ telemetry_logs"` що партиція на наступний місяць є. Якщо worker silent-fails — перевір Sentry alert (Phase 7 додав `Sentry.capture_exception` у rescue блок). |

### Менеджер Секретів (Рекомендація)

З десятками API-ключів (12 блокчейнів, GCP, Akash, Starlink, DB, Redis, GitHub) критично мати єдине захищене сховище:

- **Bitwarden** (open-source, self-hostable) або **1Password** — один vault per середовище (canopy / production)
- Зберігай кожен токен, приватний ключ та credential там **до** створення `.kamal/secrets`
- Ніколи не комітити у git: `.kamal/secrets`, `.env`, `terraform.tfvars`

---

## 🚀 Quickstart: Перший Деплой Інфраструктури

> Покрокова послідовність першого реального деплою (інтегровано нотатку N18).

```bash
# Крок 1: Створити GCS bucket для Terraform State (один раз, до terraform init)
cd terraform
chmod +x bootstrap.sh
./bootstrap.sh  # автоматично перевіряє gcloud auth та створює bucket

# Крок 2: Налаштувати terraform.tfvars
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Заповнити: project_id, db_password, ssh_source_ranges

# Крок 3: Провізіонувати GCP інфраструктуру (Cloud SQL + Ingress Anchor)
terraform init
terraform plan
terraform apply
# → outputs: ingress_ip, database_url
# GCP тепер містить: Cloud SQL PostgreSQL (приватна IP) + Ingress Anchor (e2-micro, статична IP)

# Крок 4: Створити DNS A-запис
# api.silkennet.com → $(terraform output -raw ingress_ip)
# Дочекатися: dig api.silkennet.com → правильний IP

# Крок 5: Налаштувати Akash SDL — повний список секретів (дзеркало .kamal/secrets)
# Заповнити в deploy/akash/deploy.yaml АБО terraform/akash/terraform.tfvars
# (рекомендовано — Terraform: cp terraform.tfvars.example terraform.tfvars)
#
# Application core:
#   RAILS_MASTER_KEY, DATABASE_URL, CLOUD_SQL_INSTANCE_CONNECTION_NAME,
#   GCP_SA_KEY_BASE64, REDIS_URL=rediss://<upstash>:6379,
#   KREDIS_REDIS_URL=rediss://<upstash>:6379/1
# 🛑 Boot-critical (інакше Puma crash):
#   PROVISIONING_MASTER_KEY=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(32)")
# Observability:
#   SENTRY_DSN, PROMETHEUS_AUTH_USER, PROMETHEUS_AUTH_PASSWORD
#   GRAFANA_REMOTE_WRITE_URL/USERNAME/TOKEN (тільки в alloy сервісі)
# Web3 oracle keys (інакше Sidekiq DeadSet):
#   ORACLE_PRIVATE_KEY, ORACLE_MINTER_PRIVATE_KEY, ORACLE_SLASHER_PRIVATE_KEY,
#   ETHEREUM_ANCHOR_PRIVATE_KEY
# RPC endpoints (Web3::RpcConnectionPool):
#   ALCHEMY_POLYGON_RPC_URL, ALCHEMY_ETHEREUM_RPC_URL, SOLANA_RPC_URL
# Solana minting:
#   SOLANA_WALLET_KEYPAIR, SOLANA_FEE_PAYER_PUBKEY,
#   SOLANA_FEE_PAYER_TOKEN_ACCOUNT, SOLANA_USDC_MINT_ADDRESS
# Chainlink Functions Router v1:
#   CHAINLINK_FUNCTIONS_ROUTER, CHAINLINK_SUBSCRIPTION_ID,
#   CHAINLINK_DON_ID, CHAINLINK_HMAC_SECRET
#
# ⚠️ AKASH SECURITY NOTE: ENV vars видимі провайдеру у plaintext.
# Ротуй keys кожні 90 днів. Akash-deployment keys — тільки з MINTER_ROLE/
# SLASHER_ROLE (ніколи з DEFAULT_ADMIN_ROLE). Детальніше: 06_02 BLOCKER-3.

# Крок 6: Деплой на Akash Network
cd terraform/akash
terraform init
terraform apply
# → Akash розгортає web (Rails + Puma) та job (Sidekiq) сервіси
# → Cloud SQL Auth Proxy в контейнері тунелює DB-трафік через Google API
# → Redis через Upstash (зовнішній, TLS)

# Крок 7: Верифікація
# Коли в логах: "Listening on coap://0.0.0.0:5683" — ліс може говорити.
# Ingress Anchor (HAProxy/socat) проксює HTTP/HTTPS/CoAP з GCP IP на Akash deployment.
```

---

## 🗺️ Архітектура Деплою (The Big Picture)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            GITHUB REPOSITORY                                 │
│                                                                              │
│  ┌─────────┐    ┌───────┐    ┌──────────────────────────────────────────┐   │
│  │ Feature │───▶│  PR   │───▶│  CI (scan_ruby, scan_js, lint, test,    │   │
│  │ Branch  │    │       │    │      feature-test)                       │   │
│  └─────────┘    └───┬───┘    └───────────────────┬──────────────────────┘   │
│                     │ merge                       │ ✅ pass                  │
│                     ▼                             ▼                          │
│               ┌──────────┐       ┌────────────────────────────────┐         │
│               │   main   │──────▶│  Deploy Canopy 🌿 (auto)       │         │
│               └────┬─────┘       │  terraform apply → kamal -d    │         │
│                    │             │  canopy                        │         │
│                    │ ~2 тижні    └────────────────────────────────┘         │
│                    ▼                                                         │
│  ┌──────────────────────────────┐  ┌────────────────────────────────────┐   │
│  │  GitHub Release (v1.x.0)    │─▶│  Deploy Production 🌲              │   │
│  └──────────────────────────────┘  └────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 🌿 Canopy vs 🌲 Production — Порівняльна Таблиця

| Параметр | Canopy 🌿 | Production 🌲 |
|---------|-----------|--------------|
| **Тригер деплою** | Push в `main` після успішного CI | GitHub Release (`v*.*.*`) |
| **Workflow** | `.github/workflows/deploy.yml` | `.github/workflows/deploy-production.yml` |
| **Платформа** | Akash Network (окремий SDL або namespace) | Akash Network |
| **GCP ресурси** | Cloud SQL (спільна або окрема БД) + Ingress Anchor (`e2-micro`) | Cloud SQL (HA) + Ingress Anchor (`e2-micro`) |
| **Redis** | Upstash Serverless Redis (TLS, `rediss://`) | Upstash Serverless Redis (TLS, `rediss://`) |
| **SSL/HTTPS** | ✅ `force_ssl` + HSTS (1рік, subdomains, preload). `DISABLE_SSL=true` для override | ✅ `force_ssl` + HSTS (1рік, subdomains, preload) |
| **DB** | Окрема або спільна Cloud SQL | `silken_net_production` (HA) |
| **Puma workers** | `WEB_CONCURRENCY: 2` | `WEB_CONCURRENCY: 2` |

---

## ☁️ GCP vs Akash — Розподіл Ресурсів

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform (GCP)              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Ingress Anchor (e2-micro, silken-net-ingress)      │   │
│  │    — статична IP, HAProxy/socat                     │   │
│  │    — проксює HTTP/HTTPS/CoAP на Akash deployment   │   │
│  │  Cloud SQL PostgreSQL 16 (4 бази, HA, приватна IP)  │   │
│  │  Artifact Registry (Docker images)                   │   │
│  └──────────────────────────────────────────────────────┘   │
│  ❌ Memorystore Redis — ВИДАЛЕНО (замінено на Upstash)      │
│  ❌ web-0 / canopy VMs — ВИДАЛЕНО (Rails на Akash)          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Akash Network                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  web сервіс (Rails 8.1 + Puma + Thruster)           │   │
│  │  4 vCPU / 8 GB RAM / 50 GB ephemeral                │   │
│  │  Порти: :80 (HTTP) + :5683/UDP (CoAP)               │   │
│  │                                                      │   │
│  │  ✅ job сервіс (Sidekiq, всі 31+ воркери)            │   │
│  │  ✅ alloy сервіс (Grafana Alloy → Grafana Cloud)     │   │
│  │  ✅ Cloud SQL через Auth Proxy (HTTPS tunnel)        │   │
│  │  ✅ Redis через Upstash (зовнішній, TLS, rediss://) │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Upstash (Serverless Redis)               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Redis 7.x з TLS (публічний endpoint, rediss://)    │   │
│  │  Доступний з Akash та будь-де через інтернет         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Grafana Cloud (SaaS)                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Prometheus (remote_write endpoint)                  │   │
│  │  Grafana (dashboards, PromQL)                        │   │
│  │  Alerting (alert rules, notification channels)       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

| Сервіс/Ресурс | GCP | Akash Network | Upstash | Grafana Cloud | Примітка |
|--------------|-----|---------------|---------|---------------|---------|
| **Rails web (Puma + Thruster)** | ❌ | ✅ | — | — | Повністю на Akash |
| **Sidekiq (job role)** | ❌ | ✅ | — | — | `job` сервіс в Akash SDL |
| **Grafana Alloy (metrics agent)** | ❌ | ✅ | — | — | `alloy` сервіс в Akash SDL, пушить у Grafana Cloud |
| **CoAP UDP daemon (:5683)** | proxy | ✅ | — | — | Ingress Anchor проксює UDP на Akash |
| **Cloud SQL PostgreSQL 16** | ✅ | — | — | — | Приватна IP, доступ через Auth Proxy |
| **ActionCable (Solid Cable)** | ✅ | ✅ | — | — | Спільна Cloud SQL БД `cable`, LISTEN/NOTIFY (без sticky sessions) |
| **Redis** | ❌ | — | ✅ | — | Upstash Serverless, TLS (`rediss://`) |
| **Prometheus + Grafana + Alerting** | ❌ | — | — | ✅ | SaaS, Alloy → remote_write |
| **Ingress Anchor** | ✅ | — | — | — | `e2-micro`, HAProxy/socat, статична IP |
| **Artifact Registry (Docker)** | ✅ | — | — | — | Kamal пушить у GCP AR |
| **GHCR (Docker mirror)** | — | ✅ | — | — | `.github/workflows/mirror-ghcr.yml`, публічний для Akash |

---

## 🔴 Redis DB Isolation Strategy

### Проблема

Без ізоляції Redis databases IoT телеметрія (мільйони дерев, пакети щогодини від кожної Queen) може витіснити критичні Web3 nonce locks → EVM nonce collision → double-spend на Polygon. При масштабі мільярдів-трильйонів дерев обсяг Sidekiq-черг та rate-limit counters зростає експоненціально, і shared Redis database стає single point of contention.

### Рішення: 3 Redis DB + 2 PostgreSQL-Backed + 1 In-Process

Система розділяє всі stateful підсистеми на ізольовані сховища. Кожна підсистема використовує окремий Redis DB number (або зовсім не Redis), що гарантує неможливість взаємного витіснення:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Upstash Serverless Redis (TLS)               │
│  ┌──────────────────────┬──────────────────┬──────────────────┐ │
│  │  DB 0: Sidekiq       │  DB 1: Kredis    │  DB 2: Rack::Atk │ │
│  │  Job queues          │  Distributed     │  Rate-limit      │ │
│  │  Scheduler           │  locks (Web3     │  counters        │ │
│  │  9 priority queues   │  nonce mgmt,     │  per-IP/DID      │ │
│  │                      │  M2M nonce)      │  (10 min TTL)    │ │
│  └──────────────────────┴──────────────────┴──────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────┬──────────────────────────────┐
│  PostgreSQL: Solid Cache         │  PostgreSQL: Solid Cable     │
│  Rails.cache (domain caching)    │  ActionCable adapter         │
│  Web3 circuit breaker state      │  LISTEN/NOTIFY pub/sub       │
│  Alert silence windows           │  Multi-replica safe          │
│  Dashboard stats                 │  No sticky sessions          │
└──────────────────────────────────┴──────────────────────────────┘

┌──────────────────────────────────┐
│  In-Process RAM (SinLruRedux)    │
│  HardwareKey AES binary keys     │
│  Max 10,000 entries (~320 KB)    │
│  Keys never leave Ruby process   │
└──────────────────────────────────┘
```

### Детальна таблиця ізоляції

| Підсистема | Сховище | Redis DB | ENV змінна | Конфігурація | TTL / Eviction |
|-----------|---------|----------|------------|--------------|----------------|
| **Sidekiq** (9 черг, scheduler) | Upstash Redis | **DB 0** | `REDIS_URL` | `config/initializers/sidekiq.rb` | Persistent (no eviction) |
| **Kredis** (distributed locks) | Upstash Redis | **DB 1** | `KREDIS_REDIS_URL` | `config/redis/shared.yml` | 1–300 sec (lock TTL) |
| **Rack::Attack** (rate limiting) | Upstash Redis | **DB 2** | `RACK_ATTACK_REDIS_URL` | `config/initializers/rack_attack.rb` | 10 min |
| **Rails.cache** (Solid Cache) | PostgreSQL | — | — | `config/cache.yml` + `config/environments/production.rb` | Per-entry max_age |
| **ActionCable** (Solid Cable) | PostgreSQL | — | — | `config/cable.yml` | 1 day message retention |
| **Hardware Key Cache** | In-Process RAM | — | — | `config/initializers/hardware_key_cache.rb` | Process lifetime |

### ENV змінні та автоматична деривація

```bash
# Обов'язкові:
REDIS_URL=rediss://default:password@endpoint.upstash.io:6379/0       # Sidekiq (DB 0)
KREDIS_REDIS_URL=rediss://default:password@endpoint.upstash.io:6379/1 # Kredis (DB 1)

# Опціональні (автоматично деривуються з REDIS_URL):
# RACK_ATTACK_REDIS_URL — якщо не вказано, auto-derive: замінює /0 → /2 в REDIS_URL
```

Логіка auto-derive у `config/initializers/rack_attack.rb`:
```ruby
ENV.fetch("RACK_ATTACK_REDIS_URL") {
  uri = URI.parse(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  uri.path = "/2"
  uri.to_s
}
```

Аналогічна логіка для Kredis у `config/redis/shared.yml` та Terraform `main.tf`.

### Чому саме ця архітектура

1. **Sidekiq (DB 0)**: Найбільший обсяг даних — мільйони телеметричних job'ів щогодини. Ізоляція на DB 0 запобігає витісненню Web3 locks.
2. **Kredis (DB 1)**: Критичні distributed locks для Web3 nonce management (`BlockchainMintingService`, `BlockchainBurningService`, `CeloRewardService`), M2M nonce anti-replay. Lock TTL 30 sec — якщо lock витіснений, це double-spend vulnerability.
3. **Rack::Attack (DB 2)**: Rate-limit counters з TTL 10 min. Менший обсяг, але потребує ізоляції від Sidekiq щоб counters не губились при spike-ах.
4. **Solid Cache (PostgreSQL)**: Rails.cache для Web3 circuit breaker state, dashboard stats, alert silence windows. PostgreSQL гарантує durability — circuit breaker state не зникає при Redis restart.
5. **Solid Cable (PostgreSQL)**: ActionCable через PostgreSQL LISTEN/NOTIFY — zero Redis dependency, multi-replica safe без sticky sessions.
6. **In-Process RAM**: AES hardware keys — Zero Network Exposure. Ключі ніколи не серіалізуються і не передаються по мережі.

### Масштабування (мільйони → мільярди → трильйони дерев)

| Масштаб | Дерев | Queens | Sidekiq jobs/год | Redis DB стратегія |
|---------|-------|--------|------------------|--------------------|
| **Pilot** (TRL 6-7) | ~1,000 | ~50 | ~50K | Single Upstash instance, 3 DBs |
| **Regional** (TRL 8) | ~1M | ~50K | ~50M | Upstash Pro, 3 DBs + dedicated Sidekiq |
| **Planetary** (TRL 9) | ~1B+ | ~50M | ~50B | Separate Redis clusters per DB: Sidekiq cluster (DB 0), Kredis cluster (DB 1), Rack::Attack cluster (DB 2). Або Upstash multi-region з read replicas. |

При planetary масштабі кожен DB може потребувати окремий Redis cluster або Upstash instance з окремим endpoint. ENV архітектура вже це підтримує — кожна підсистема має окрему ENV змінну.

---

## 📦 Kamal — Детальний Аналіз

### Файлова структура

| Файл | Опис |
|------|------|
| `config/deploy.yml` | Production-конфіг (основний) |
| `config/deploy.canopy.yml` | Canopy-перевизначення (`-d canopy`) |
| `.kamal/secrets` | Runtime секрети (читаються при деплої) |
| `.kamal/hooks/` | Хуки ЖЦ (тільки sample-файли) |

### `config/deploy.yml` — Production

```yaml
service: silken_net
image:  silken_net

servers:
  web:
    - 192.168.0.1            # ⚠️ PLACEHOLDER — замінити на реальну IP
  job:
    hosts:
      - 192.168.0.1          # ⚠️ PLACEHOLDER
    cmd: bundle exec sidekiq -C config/sidekiq.yml

boot:
  proxy:
    publish:
      - "80:80"
      - "443:443"
      - "5683:5683/udp"      # CoAP IoT uplink

registry:
  server:   europe-west1-docker.pkg.dev
  username: _json_key_base64
  password:
    - GCP_ARTIFACT_REGISTRY_KEY

env:
  secret:
    # --- Application core ---
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - REDIS_URL
    - KREDIS_REDIS_URL
    # --- Observability ---
    - SENTRY_DSN
    # --- Hardware provisioning gate (config/initializers/master_key_strength_check.rb) ---
    - PROVISIONING_MASTER_KEY
    # --- Web3 oracle / minter / slasher (dual-key split, B-02 resolved) ---
    - ORACLE_PRIVATE_KEY           # legacy fallback для existing services
    - ORACLE_MINTER_PRIVATE_KEY    # SCC/SFC batch mint (BlockchainMintingService)
    - ORACLE_SLASHER_PRIVATE_KEY   # token burn (BlockchainBurningService)
    - ETHEREUM_ANCHOR_PRIVATE_KEY  # weekly state-root anchor (Ethereum::StateAnchorService)
    # --- RPC endpoints (SSOT names expected by Web3::RpcConnectionPool) ---
    - ALCHEMY_POLYGON_RPC_URL
    - ALCHEMY_ETHEREUM_RPC_URL
    - SOLANA_RPC_URL
    # --- Solana minting (Solana::MintingService raises without these) ---
    - SOLANA_WALLET_KEYPAIR
    - SOLANA_FEE_PAYER_PUBKEY
    - SOLANA_FEE_PAYER_TOKEN_ACCOUNT
    - SOLANA_USDC_MINT_ADDRESS
    # --- Chainlink Functions Router v1 (Proof of Growth pipeline) ---
    - CHAINLINK_FUNCTIONS_ROUTER
    - CHAINLINK_SUBSCRIPTION_ID
    - CHAINLINK_HMAC_SECRET
    - CHAINLINK_DON_ID
  clear:
    WEB_CONCURRENCY: 2
    RAILS_ALLOWED_HOSTS: api.silkennet.com,.silkennet.com  # DNS rebinding protection
    # DISABLE_SSL: "true"   # розкоментувати якщо Akash ingress або Cloudflare термінує TLS
    # CSP_ENFORCE: "true"   # розкоментувати після burn-in спостереження CSP violation репортів
```

> **🔴 Boot-time guard rationale:** Container injects ТІЛЬКИ ті secrets, що явно перелічені у `env: secret:`. Відсутність `PROVISIONING_MASTER_KEY` → `SecurityError` від `config/initializers/master_key_strength_check.rb` → Puma crash до accept. Відсутність `ORACLE_*_PRIVATE_KEY` → `KeyError` від `ENV.fetch` у `BlockchainMintingService`/`BlockchainBurningService` → web3-критичні воркери у DeadSet. Відсутність `ALCHEMY_ETHEREUM_RPC_URL` → `StateAnchorService` падає при tижневому anchor TX → `EthereumAnchor.status = failed`. **Bind these in `.kamal/secrets` first**, потім додавай у `env: secret:` блок.

> **Нові ENV змінні безпеки** (деталі у `06_04_Secrets_Checklist §2.1`):
>
> | ENV | Тип | Default | Опис |
> |-----|-----|---------|------|
> | `RAILS_ALLOWED_HOSTS` | `env.clear` | — (попередження) | Comma-separated allowlist для DNS-rebinding захисту. ⚠️ Обов'язково у production. |
> | `DISABLE_SSL` | `env.clear` | `false` | Вимикає `force_ssl`/`assume_ssl`. Тільки якщо TLS термінується upstream (Cloudflare/Akash ingress). |
> | `ALLOW_ALL_HOSTS` | `env.clear` | `false` | Заглушує попередження `[SECURITY]` якщо `RAILS_ALLOWED_HOSTS` не встановлено. |
> | `CSP_ENFORCE` | `env.clear` | `false` | Переводить CSP з report-only у enforced. Рекомендується після burn-in (1–2 тижні). |

```bash
kamal rollback
kamal app exec --interactive --reuse "bin/rails console"
kamal logs -f
kamal app exec --interactive --reuse "bash"
# Canopy:
kamal app exec --interactive --reuse "bin/rails console" -d canopy
kamal logs -f -d canopy
```

---

## 🏗️ Terraform (GCP) — Детальний Аналіз

### Файлова структура

```
terraform/
├── main.tf       # Provider (google ~> 5.0), GCP APIs, Artifact Registry
├── vpc.tf        # VPC, subnet (10.0.0.0/20), Cloud Router, Cloud NAT, Firewall
├── compute.tf    # Ingress Anchor (e2-micro, silken-net-ingress), Static IP
├── database.tf   # Cloud SQL PostgreSQL 16, 4 databases, Private Service Access
├── iam.tf        # Service Account silken-net-deploy + 7 IAM roles
├── variables.tf  # Всі input variables з валідацією
└── outputs.tf    # ingress_ip, DB URL тощо

terraform/akash/
├── main.tf       # SDL generation, null_resource (akash CLI)
├── variables.tf  # Akash-specific variables + app secrets + Grafana Cloud
└── outputs.tf    # SDL path, deployment notes
```

> **Примітка:** `redis.tf` видалено — Redis тепер обслуговується Upstash (serverless, зовнішній сервіс, не GCP). `compute.tf` більше не містить web/canopy VMs — лише Ingress Anchor (`e2-micro`) з HAProxy/socat для проксування трафіку на Akash. Grafana Alloy `config.alloy` знаходиться в `deploy/akash/config.alloy` і кодується в Base64 через `filebase64()` при рендерингу SDL шаблону.

### GCP Region та Zone

| Параметр | Значення |
|---------|---------|
| Region | `europe-west1` (Belgium) |
| Zone | `europe-west1-b` |
| Причина | GDPR compliance + найближче до України |

### Firewall

| Правило | Порти | Джерело |
|---------|-------|---------|
| `allow-ssh` | TCP 22 | `ssh_source_ranges` (змінна) |
| `allow-web` | TCP 80, 443 | `0.0.0.0/0` |
| `allow-coap` | UDP 5683 | `0.0.0.0/0` |
| `allow-internal` | Усі | `10.0.0.0/20` |
| `deny-all-ingress` | Усі | `0.0.0.0/0` (priority 65534) |

### IAM

```
Service Account: silken-net-deploy@<project>.iam.gserviceaccount.com
Ролі:
  - artifactregistry.writer   (push Docker images)
  - compute.instanceAdmin.v1  (Kamal SSH deploy)
  - iam.serviceAccountUser    (impersonation)
  - logging.logWriter         (Cloud Logging)
  - monitoring.metricWriter   (Cloud Monitoring)
  - sql.client                (Cloud SQL connect)
  - storage.objectAdmin       (GCS Terraform state)
```

### Розрахунок `max_connections` (database.tf)

Поточне значення `400`. Розрахунок мінімальних потреб:

| Компонент | Підключення |
|-----------|------------|
| Akash web: Puma workers (2) × Threads (5) | 10 |
| Akash job: Sidekiq threads (25) | 25 |
| Akash replicas (canopy) × Threads | 12 |
| Rails DB console / admin | 5 |
| Cloud SQL Auth Proxy overhead | 3 |
| **Мінімум** | **~55** |

`400` — з великим запасом для масштабування. Адекватно.

---

## 🐳 Docker — Multi-stage Build

```
Stage 1: base          — ruby:4.0.2-slim + libjemalloc2, libvips, postgresql-client
Stage 2: build         — bundle install, bootsnap, assets:precompile
Stage 3: final         — COPY gems + app + Cloud SQL Auth Proxy, USER rails:1000, CMD: thrust ./bin/rails server
```

> **Cloud SQL Auth Proxy** вбудовано у фінальний Docker-образ. Proxy запускається автоматично як фоновий процес при наявності ENV `CLOUD_SQL_INSTANCE_CONNECTION_NAME`. Він тунелює PostgreSQL-трафік через Google Cloud API (вихідний HTTPS на порт 443), тому Cloud SQL не потребує публічної IP.

---

## 🚀 Akash SDL — Технічний Аналіз

### Файлова структура

| Файл | Призначення |
|------|------------|
| `deploy/akash/deploy.yaml` | Статичний SDL — ручний деплой |
| `deploy/akash/deploy.yaml.tpl` | Шаблон SDL (Terraform рендерить) |
| `terraform/akash/main.tf` | `local_file` + `null_resource` (CLI wrapper) |
| `terraform/akash/generated-deploy.yaml` | Генерується Terraform, права `0600` |

### Процес Akash деплою (через Terraform)

```bash
cd terraform/akash
# Створити terraform.tfvars з prefer-фuller exemплара:
#   cp terraform.tfvars.example terraform.tfvars
# Повний набір змінних (мірор .kamal/secrets, ~25 sensitive):
#   akash_key_name, docker_image
#   rails_master_key, database_url, cloud_sql_instance_connection_name,
#     gcp_sa_key_base64, redis_url, kredis_redis_url
#   provisioning_master_key  ← 🛑 BOOT-CRITICAL
#   sentry_dsn, prometheus_auth_user/password
#   grafana_remote_write_url/username/token
#   oracle_private_key, oracle_minter_private_key, oracle_slasher_private_key,
#     ethereum_anchor_private_key
#   alchemy_polygon_rpc_url, alchemy_ethereum_rpc_url, solana_rpc_url
#   solana_wallet_keypair, solana_fee_payer_pubkey,
#     solana_fee_payer_token_account, solana_usdc_mint_address
#   chainlink_functions_router, chainlink_subscription_id,
#     chainlink_don_id, chainlink_hmac_secret

terraform init
terraform apply

akash query market bid list --owner <your-address> --dseq <DSEQ>
akash tx market lease create --dseq <DSEQ> --provider <provider-address> --from silken-deploy

akash provider send-manifest terraform/akash/generated-deploy.yaml \
  --dseq <DSEQ> --provider <provider-address> --from silken-deploy

akash provider lease-status --dseq <DSEQ> --provider <provider-address> --from silken-deploy
```

---

## 📋 Чеклист першого деплою (Priority Order)

```
☑ 1. Створити GCS bucket для Terraform State ← ВИПРАВЛЕНО (bootstrap.sh)
      cd terraform && ./bootstrap.sh

☐ 2. Створити terraform/terraform.tfvars
      project_id, db_password, ssh_source_ranges=[<your-ip>]

☐ 3. Заповнити всі GitHub Secrets (BLOCKER-3)
      GCP_SA_KEY, GCP_PROJECT_ID, DATABASE_PASSWORD, DATABASE_URL, ...

☐ 4. terraform init && terraform plan && terraform apply
      Перевірити outputs: ingress_ip, database_url

☐ 5. DNS A-запис створено та поширився
      api.silkennet.com → $(terraform output -raw ingress_ip)
      dig api.silkennet.com → правильний IP

☑ 6. KREDIS_REDIS_URL в .kamal/secrets ← ВИПРАВЛЕНО

☑ 7. Cloud SQL доступний з Akash ← ВИПРАВЛЕНО (Cloud SQL Auth Proxy)

☑ 8. Sidekiq на Akash ← ВИПРАВЛЕНО (job сервіс додано)

☐ 9. Створити deploy-production.yml workflow (INFO)

☐ 10. Налаштувати Upstash Redis (заміна GCP Memorystore)
       Створити Upstash інстанс, отримати rediss:// URL
       Вказати REDIS_URL та KREDIS_REDIS_URL в Akash SDL

☐ 11. Деплой на Akash Network
       cd terraform/akash && terraform apply
       Верифікувати web та job сервіси запущені

☐ 12. Верифікувати Ingress Anchor маршрутизацію
       curl https://api.silkennet.com/up → 200

☐ 13. Oracle гаманці поповнені газом (MATIC/ETH/SOL/CELO) (Pre-Flight #3)

☐ 14. LoRa-антени підключені до всіх плат (Pre-Flight #4)

☐ 15. AES-ключ Soldier = AES-ключ Queen (побітово) (Pre-Flight #5)

☐ 16. Встановити RAILS_ALLOWED_HOSTS у Kamal env.clear / Akash SDL
       Приклад: RAILS_ALLOWED_HOSTS=api.silkennet.com,.silkennet.com
       Без цього Rails логує [SECURITY] попередження при кожному старті.

☐ 17. Вирішити CSP burn-in: спостерігати violation-репорти 1-2 тижні,
       потім встановити CSP_ENFORCE=true в env.clear для enforced режиму.
```

---

## 🌐 Масштабування до Планетарного Рівня — CoAP/UDP та Ingress

> Цей розділ описує архітектурні ризики та рекомендації для переходу від сотень до **мільйонів** вузлів. Поточна архітектура (CoAP прямо в Rails) є коректною для TRL 5–6, але потребує еволюції перед Series D.

### ✅ Ризик-1 & Ризик-2 — Conntrack + UDP Rate Limiting (Виправлено)

Обидва ризики вирішені в `terraform/compute.tf` (`startup-script` Ingress Anchor):
- **conntrack**: `nf_conntrack_max=2000000`, `nf_conntrack_udp_timeout=30s` — 2M entries замість 65K дефолт.
- **UDP rate limit**: `iptables` hashlimit 100 pkt/s per IP + burst 200; DROP з LOG (max 10/хв у Cloud Logging). Налаштування зберігаються через `/etc/sysctl.conf` та `iptables-persistent`.

### 🟡 Ризик-3: IP Exhaustion при Динамічних IP Шлюзів

**Проблема:** Якщо Queen-шлюзи мають динамічні IP (мобільний інтернет через SIM7070G) → при мільйонах шлюзів таблиця маршрутизації та whitelist-правила стають некерованими.

**Мітигація:** Аутентифікація Queen через AES-CBC підпис батча (вже реалізовано) + queen_uid у URI — IP не має значення. Firewall не потрібно прив'язувати до IP шлюзів.

---

### 🏗️ Series D Architecture Upgrade — Ingress Proxy + Kafka

Для обробки **>1M пакетів/годину** від мільйонів дерев потрібна буферизована архітектура між мережею та Rails:

```
Поточна архітектура (TRL 5–6):
  Queen → CoAP/UDP → lib/daemons/coap_listener.rb → Sidekiq → Rails

Series D архітектура (>1M вузлів):
  Queen → CoAP/UDP → [Ingress Proxy Rust/Go] → Kafka / Google Pub-Sub → [Rails Consumers]
```

#### Ingress Proxy (Rust або Go)

- **Роль:** Ультралегкий stateless proxy. Приймає UDP, валідує AES-CBC підпис, збирає пакети в батчі, кидає в Kafka
- **Мова:** Rust (tokio + bytes) або Go (net/udp + goroutines) — обидва дають < 1 мс latency при 100k req/s
- **Rails не бачить сирого UDP** — тільки готові батчі з черги

#### Kafka / Google Pub-Sub (Message Buffer)

- **Роль:** Буфер між Proxy та Rails. Якщо Rails тимчасово перевантажений → пакети не губляться, вони чекають у черзі
- **Throughput:** Kafka — до 1M msg/s на одному брокері; Pub-Sub — горизонтальна масштабованість без обмежень
- **Партиціювання:** За `queen_uid` → гарантований порядок пакетів з одного шлюзу

#### Read-Only PostgreSQL Replicas

- **Правило:** Лише Primary DB пише. Усі аналітичні запити, Oracle-виклики, Grafana-дашборди, The Graph indexer — читають з Read-Only Replicas
- **GCP конфігурація:** Cloud SQL → Add Read Replica (Terraform: `google_sql_database_instance` з `master_instance_name`)
- **Rails конфігурація:** `connects_to(database: { writing: :primary, reading: :replica })`

#### Статус

| Компонент | Поточний стан | Необхідна дія |
|-----------|--------------|--------------|
| CoAP Listener | `lib/daemons/coap_listener.rb` (Ruby) | Достатньо до ~10k вузлів |
| Ingress Anchor (`e2-micro`) | ✅ Виправлено (`terraform/compute.tf`) | Bottleneck при >10M дерев — див. нижче |
| Ingress Proxy (Rust/Go) | 🔴 Не реалізовано | Series D milestone |
| Kafka / Pub-Sub | 🔴 Не реалізовано | Series D milestone |
| Read-Only Replicas | 🔴 Не налаштовано | Terraform: `google_sql_database_instance` replica |
| conntrack + UDP rate limit | ✅ Виправлено | `terraform/compute.tf` startup_script |

#### 🌍 Front-Door Bottleneck — Ingress Anchor на `e2-micro` (Series D)

**Проблема.** Ingress Anchor (`compute.tf`, `silken-net-ingress`) — це один `e2-micro` (2 vCPU shared, 1 GB RAM, обмежений egress). HAProxy/socat на ньому проксують UDP/5683 на Akash. При >10M дерев → мільйони Queens → один процесор стає вузьким горлом для CoAP/UDP.

**Опції еволюції (упорядковані за зростанням інвазивності):**

| # | Підхід | Що дає | Що потрібно |
|---|--------|--------|-------------|
| 1 | **GCP L4 Network Load Balancer + MIG `e2-small`** | Горизонтальний autoscaling, безмежний throughput, та сама статична IP (forwarding rule) | Terraform: `google_compute_forwarding_rule` (L4 UDP) + `google_compute_region_instance_group_manager` з autoscaler; стартап-скрипт ідентичний існуючому (socat → Akash). DNS A не змінюється. |
| 2 | **Cloudflare Spectrum (UDP forwarding)** | Глобальний anycast → найближча PoP-нода, DDoS-фільтрація, без власної VM-інфраструктури | Cloudflare Enterprise (Spectrum — paid add-on); CNAME `api.silkennet.com` на Spectrum endpoint; whitelist Akash origin IP. GCP Ingress Anchor можна вимкнути. |
| 3 | **Ingress Proxy (Rust/Go) + Kafka** (нижче) | Stateless дешифрування AES-CBC + батч у Kafka до того, як Rails побачить пакет | Власна розробка (див. наступний підрозділ). Поєднується з #1 або #2 — L4/Spectrum дають мережевий шар, Proxy дає прикладний. |

> **Рекомендований шлях:** #1 (L4 NLB + MIG) як проміжний крок — мінімум коду, лише Terraform. Якщо у вас уже є Cloudflare Enterprise — #2 дешевший за операцію. #3 (Proxy + Kafka, нижче) обов'язковий при пакетних потоках >1M/год незалежно від мережевого шару.

---

## 🔑 Змінні Середовища: Web3 та Мультичейн

### Обов'язкові (Polygon)

```bash
# Polygon RPC (Alchemy)
ALCHEMY_POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY

# Oracle-гаманець (керує мінтингом/слешингом)
ORACLE_PRIVATE_KEY=0x...  # ⚠️ Зберігати в Rails credentials або Vault, НІКОЛИ не в .env

# Адреси смарт-контрактів (Polygon)
CARBON_COIN_CONTRACT_ADDRESS=0x...  # SCC
FOREST_COIN_CONTRACT_ADDRESS=0x...  # SFC
```

### Мультичейн (Gaia 2.0)

```bash
# Ethereum L1 (State Anchoring) — SSOT name expected by app/services/ethereum/state_anchor_service.rb:146 та treasury/monitor_service.rb:54.
ALCHEMY_ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
ETHEREUM_ANCHOR_PRIVATE_KEY=0x...  # Окремий гаманець для тижневого state-root anchoring (НЕ дорівнює ORACLE_PRIVATE_KEY).

# IoTeX W3bstream (ZK Verification)
W3BSTREAM_API_URL=https://w3bstream-api.iotex.io
W3BSTREAM_PROJECT_ID=silken_net_dmrv

# Chainlink Functions Router v1 (Oracle DON)
CHAINLINK_FUNCTIONS_ROUTER=0x...
CHAINLINK_SUBSCRIPTION_ID=...
CHAINLINK_HMAC_SECRET=...
CHAINLINK_DON_ID=fun-polygon-mainnet-1
CHAINLINK_DATA_VERSION=1
CHAINLINK_CALLBACK_GAS_LIMIT=300000

# peaq DID (Machine Identity)
PEAQ_NODE_URL=https://peaq-node.example.com

# Solana (Micro-Rewards)
SOLANA_RPC_URL=https://api.mainnet-beta.solana.com
SOLANA_WALLET_KEYPAIR=...

# Celo (Community Rewards)
CELO_RPC_URL=https://forno.celo.org
CELO_CUSD_CONTRACT_ADDRESS=0x...

# KlimaDAO (Carbon Retirement)
KLIMA_RETIREMENT_CONTRACT_ADDRESS=0x...

# Polygon Hadron (RWA Compliance)
HADRON_API_URL=https://api.hadron.polygon.technology
HADRON_API_KEY=...

# Streamr (P2P Data)
STREAMR_API_URL=https://streamr.network/api/v2
STREAMR_STREAM_ID=silken_net/forest_telemetry

# Filecoin/IPFS (Archive)
PINATA_API_KEY=...
PINATA_SECRET_KEY=...

# The Graph (Indexing)
THE_GRAPH_SUBGRAPH_URL=https://api.thegraph.com/subgraphs/name/silken-net/carbon

# Akash Network (Deployment)
AKASH_WALLET_ADDRESS=...

# CoAP listener
COAP_PORT=5683
```

### Деплой контрактів (Foundry)

```bash
# Встановіть Foundry (https://book.getfoundry.sh/)
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Деплой SCC на testnet
cd contracts/
forge create SilkenCarbonCoin --rpc-url $ALCHEMY_POLYGON_RPC_URL --private-key $ORACLE_PRIVATE_KEY

# Деплой SFC на testnet
forge create SilkenForestCoin --rpc-url $ALCHEMY_POLYGON_RPC_URL --private-key $ORACLE_PRIVATE_KEY

# Деплой на Mainnet з верифікацією
forge create SilkenCarbonCoin \
  --rpc-url $ALCHEMY_POLYGON_RPC_URL \
  --private-key $ORACLE_PRIVATE_KEY \
  --verify --etherscan-api-key $POLYGONSCAN_API_KEY
```
