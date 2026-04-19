# 06_01: Розгортання Kamal & Terraform (Canopy vs Production)

## 🎯 Мета

Зафіксувати повний стан конфігурацій розгортання та інфраструктури як коду (IaC). Документ відповідає на три ключові питання:

1. Чим відрізняються середовища **Canopy** (Staging) та **Production**?
2. Що розгортається в **GCP** (традиційна хмара), а що — в **Akash Network** (децентралізована мережа)?
3. Які **API-ключі, секрети та сертифікати** потрібні для першого реального деплою?

## ✅ Статус

- **Поточний TRL:** TRL 4 — інфраструктурний код існує, реальний деплой не проводився
- **Пов'язані модулі:**
  - Backend → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)
  - Observability → [`06_03_Prometheus_Observability`](06_03_Prometheus_Observability)
  - Akash → [`06_02_Akash_Network_Integration`](06_02_Akash_Network_Integration)

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

### ✅ BLOCKER-2: GCS Bucket для Terraform State — автоматизовано (Виправлено)

**Статус:** Вирішено. Скрипт `terraform/bootstrap.sh` автоматизує створення GCS-кошика до першого `terraform init`.

```bash
# Один раз — до terraform init
cd terraform
chmod +x bootstrap.sh
./bootstrap.sh  # запитає GCP_PROJECT_ID, створить bucket + перевірить gcloud auth
```

Скрипт виконує:
1. Перевіряє наявність `gcloud` та автентифікацію
2. Створює `gs://silken-net-terraform-state` у `europe-west1` з `uniform-bucket-level-access`
3. Виводить підтвердження — після цього `terraform init` спрацює

> Якщо бакет вже існує — скрипт завершується без помилки (idempotent).

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
| `REDIS_URL` | Production Redis (DB 0) | Upstash: `rediss://<host>:<port>/0` (TLS) |
| `CANOPY_REDIS_URL` | Canopy Redis (DB 0) | Upstash: `rediss://<host>:<port>/0` |
| `KREDIS_REDIS_URL` | Production Redis (DB 1) | Upstash: `rediss://<host>:<port>/1` |
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

**Статус:** `deploy/akash/deploy.yaml` потребує ручного редагування перед деплоєм.

**Дія (рекомендовано):** Використати Terraform-шаблон `deploy/akash/deploy.yaml.tpl` — секрети підставляються автоматично з `terraform.tfvars`.

---

### ✅ BLOCKER-6: Cloud SQL публічний IP для Akash — Вирішено (Cloud SQL Auth Proxy)

**Статус:** Вирішено. Cloud SQL Auth Proxy вбудовано в Docker-образ. Proxy тунелює PostgreSQL-трафік через Google Cloud API (вихідний HTTPS), тому Cloud SQL залишається з приватною IP (`ipv4_enabled=false`). Ні VPN, ні Tailscale, ні публічний IP на Cloud SQL не потрібні.

Proxy запускається автоматично, коли встановлена ENV-змінна `CLOUD_SQL_INSTANCE_CONNECTION_NAME`. Змінні `akash_enabled` та `akash_authorized_networks` видалені з `database.tf`/`variables.tf` — більше не потрібні.

> Cloud SQL Auth Proxy автентифікується через GCP Service Account JSON key (тіж самі credentials, що й для Artifact Registry).

---

### ✅ BLOCKER-7: Sidekiq (job role) додано в Akash SDL (Виправлено)

**Статус:** Виправлено. `job` сервіс додано в `deploy/akash/deploy.yaml`.

SDL тепер визначає два сервіси:
- `web` — Puma HTTP сервер
- `job` — `bundle exec sidekiq -C config/sidekiq.yml` (всі 31+ воркери)

Секрети в `job` сервісі позначено `REQUIRED` коментарями для явного налаштування перед деплоєм.

---

### ✅ BLOCKER-8: `ssh_source_ranges` — порожній список за замовчуванням (Виправлено)

**Статус:** Виправлено. Значення за замовчуванням змінено з `["0.0.0.0/0"]` на `[]` (порожній список). Terraform тепер блокує застосування з відкритим SSH (`0.0.0.0/0`) і виводить попередження при спробі використати такий CIDR. Необхідно явно вказати конкретні IP в `terraform.tfvars`:
```hcl
ssh_source_ranges = ["203.0.113.10/32", "198.51.100.0/24"]
```

---

### ✅ BLOCKER-9: `KREDIS_REDIS_URL` додано до `.kamal/secrets` (Виправлено)

**Статус:** Виправлено. `KREDIS_REDIS_URL` додано до `.kamal/secrets`.

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
| **2** | **`.kamal/secrets` файл існує** | Kamal читає секрети з `.kamal/secrets` (не з environment). Заповни: `RAILS_MASTER_KEY`, `DATABASE_URL`, `REDIS_URL`, `KREDIS_REDIS_URL`, `GCP_ARTIFACT_REGISTRY_KEY`. Без нього контейнери стартують і одразу падають (немає доступу до БД або ключа дешифрування). |
| **3** | **Gas на Web3-гаманцях** | Воркери потребують нативної крипто: **MATIC** (Polygon), **ETH** (L1), **SOL** (Solana), **CELO** (Celo). Без газу → "Insufficient Funds" на кожній транзакції → Sidekiq потоне у ретраях. |
| **4** | **LoRa-антена підключена** | **КРИТИЧНО.** Ніколи не подавай живлення без антени на SMA/U.FL порту. SX1262 відбиває RF назад у чип (high VSWR) — радіотракт згоряє за мілісекунди. Незворотно. Правило: антена → живлення. |
| **5** | **Симетрія AES-ключів** | `aes_key[8]` у `soldier/main.c` та `queen/main.c` — **побітово ідентичні**. Один відмінний біт → Queen читає сміття з кожного пакету. Ліс мовчить без помилок. Перевіряй перед кожним flash-циклом. Детальніше: `03_05_Hardware_AES256_and_Security`. |

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

# Крок 5: Налаштувати Akash SDL
# Заповнити секрети в deploy/akash/deploy.yaml або terraform/akash/terraform.tfvars:
#   RAILS_MASTER_KEY, DATABASE_URL, CLOUD_SQL_INSTANCE_CONNECTION_NAME
#   REDIS_URL=rediss://<upstash-host>:6379  (Upstash TLS)
#   KREDIS_REDIS_URL=rediss://<upstash-host>:6379/1
#   GCP_SA_KEY (для Cloud SQL Auth Proxy)

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
| **SSL/HTTPS** | Вимкнено або Let's Encrypt через Ingress Anchor | Let's Encrypt через Ingress Anchor |
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
| **Artifact Registry (Docker)** | ✅ | shared | — | — | Той самий образ |

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
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - REDIS_URL
    - KREDIS_REDIS_URL
  clear:
    WEB_CONCURRENCY: 2
```

### Rollback та Аліаси

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
Stage 1: base          — ruby:4.0.1-slim + libjemalloc2, libvips, postgresql-client
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
# Створити terraform.tfvars:
# akash_key_name, docker_image, rails_master_key, database_url, redis_url

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
☑ 1. Створити GCS bucket для Terraform State (BLOCKER-2) ← ВИПРАВЛЕНО (bootstrap.sh)
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

☑ 6. KREDIS_REDIS_URL в .kamal/secrets (BLOCKER-9) ← ВИПРАВЛЕНО

☑ 7. Cloud SQL доступний з Akash (BLOCKER-6) ← ВИПРАВЛЕНО (Cloud SQL Auth Proxy)

☑ 8. Sidekiq на Akash (BLOCKER-7) ← ВИПРАВЛЕНО (job сервіс додано)

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
```

---

## 🔗 Пов'язані ресурси

- **`docs/DEPLOYMENT.md`** — детальна операційна документація (команди, діаграми)
- **`06_02_Akash_Network_Integration`** — поглиблений аналіз Akash SDL та провайдерів
- **`06_03_Prometheus_Observability`** — метрики, Grafana, Cloud Monitoring алерти
- **`04_02_Business_Logic_and_Services`** — Sidekiq workers та черги
- **`terraform/`** — Infrastructure as Code (GCP)
- **`terraform/akash/`** — Infrastructure as Code (Akash)
- **`config/deploy.yml`**, **`config/deploy.canopy.yml`** — Kamal конфіги
- **`deploy/akash/deploy.yaml`** — Akash SDL

---

## 🌐 Масштабування до Планетарного Рівня — CoAP/UDP та Ingress

> Цей розділ описує архітектурні ризики та рекомендації для переходу від сотень до **мільйонів** вузлів. Поточна архітектура (CoAP прямо в Rails) є коректною для TRL 5–6, але потребує еволюції перед Series D.

### ✅ Ризик-1: Conntrack Table Overflow — Виправлено (Sprint 3, S3.6)

**Проблема:** CoAP працює на UDP. Google Cloud (та будь-який Linux-сервер) веде таблицю `conntrack` у ядрі для відстеження з'єднань. При мільйонах IoT-пакетів на годину таблиця переповнюється → ядро починає мовчки ігнорувати нові сигнали від дерев. Ліс "замовкає" без жодної помилки в логах.

**Симптом:** `nf_conntrack: table full, dropping packet` у `/var/log/kern.log`.

**Статус:** Виправлено. `sysctl` тюнінг conntrack додано до `startup-script` Ingress Anchor у `terraform/compute.tf`. Налаштування зберігаються через `/etc/sysctl.conf` — переживають перезавантаження:

```bash
# Автоматично виконується при старті Ingress Anchor (terraform/compute.tf):
sysctl -w net.netfilter.nf_conntrack_max=2000000
sysctl -w net.netfilter.nf_conntrack_udp_timeout=30
echo "net.netfilter.nf_conntrack_max=2000000" >> /etc/sysctl.conf
echo "net.netfilter.nf_conntrack_udp_timeout=30" >> /etc/sysctl.conf
```

- `nf_conntrack_max=2000000` — 2M entry замість типових 65K
- `nf_conntrack_udp_timeout=30s` — UDP записи очищаються вчасно (замість 180s за замовчуванням)

### ✅ Ризик-2: UDP Rate Limiting реалізовано через Terraform (Виправлено)

**Статус:** Виправлено. `iptables` hashlimit правило додано в `startup-script` Ingress Anchor.

```bash
# Автоматично виконується при старті Ingress Anchor (terraform/compute.tf):
iptables -A INPUT -p udp --dport 5683 \
  -m hashlimit --hashlimit-name coap \
  --hashlimit-upto 100/sec --hashlimit-burst 200 \
  --hashlimit-mode srcip -j ACCEPT
iptables -A INPUT -p udp --dport 5683 \
  -m limit --limit 10/min -j LOG --log-prefix "CoAP-RATELIMIT-DROP: "
iptables -A INPUT -p udp --dport 5683 -j DROP
```

Правила зберігаються через `iptables-persistent` — переживають перезавантаження Ingress Anchor.

- **100 UDP пакетів/сек** на IP-адресу + burst 200 → легальна Queen не обмежується
- **LOG** перед DROP (max 10/хв) → DDoS атаки видимі у Cloud Logging без флуду логів

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
| Ingress Proxy (Rust/Go) | 🔴 Не реалізовано | Series D milestone |
| Kafka / Pub-Sub | 🔴 Не реалізовано | Series D milestone |
| Read-Only Replicas | 🔴 Не налаштовано | Terraform: `google_sql_database_instance` replica |
| conntrack tuning | ✅ Виправлено | `sysctl` у Ingress Anchor `startup_script` (`terraform/compute.tf`) |

---

## 🔄 Оновлення Kamal (Upgrade Notes)

### Kamal 2.11.0 (з 2.10.1)

> ⚠️ **Kamal 2.11.0 вимагає kamal-proxy ≥ v0.9.2.** Без оновлення proxy деплой зафейлиться.

**Крок 1: Оновити kamal-proxy на серверах**

Перед першим деплоєм з Kamal 2.11.0 потрібно оновити proxy на кожному сервері:

```bash
# Canopy
kamal proxy reboot -d canopy

# Production
kamal proxy reboot
```

> `kamal proxy reboot` завантажує новий образ kamal-proxy, перезапускає контейнер. Це зазвичай спричиняє **короткий даунтайм** (~1-3 сек).

CI/CD workflows (`deploy.yml`, `deploy-production.yml`) вже включають крок `kamal proxy reboot` перед деплоєм.

**Крок 2: Оновити gem**

```bash
bundle update kamal
```

**Що змінилось у Kamal 2.11.0:**

| Зміна | Тип | Вплив на проєкт |
|-------|-----|-----------------|
| Вимога kamal-proxy ≥ v0.9.2 | ⚠️ Breaking | CI workflows оновлено, proxy reboot додано |
| Aliases з destination (`-d`) | ✨ Нове | Додано `canopy-console`, `canopy-logs` в `deploy.yml` |
| Конфігурована verbosity хуків | ✨ Нове | Доступно для `.kamal/hooks/` |
| Підтримка ssh-config в run-over-ssh | ✨ Нове | Можна використовувати `~/.ssh/config` |
| Секрети для pre-connect хука | 🐛 Фікс | Секрети тепер доступні в `pre-connect` хуках |
| Цитування filter names у docker | 🐛 Фікс | Виправлено проблеми зі спецсимволами |
| ERB rendering: trim blank lines | 🔧 Покращення | Чистіший парсинг конфігурацій |
| Додавання user до docker групи | 🔧 Покращення | Автоматично для non-superuser |

**Що нового в kamal-proxy v0.9.2:**

| Фіча | Опис |
|-------|------|
| `--http3` | Підтримка HTTP/3 (QUIC) |
| `--canonical-host` | Редирект на канонічний хост (напр. `example.com → www.example.com`) |
| `--health-check-host` / `--health-check-port` | Кастомний хост/порт для health checks |
| `--acme-cache-path` | Спільний кеш Let's Encrypt між proxy-інстансами |
| `--scope-cookie-paths` | Автоматичний scope cookies до path-prefix |
| Chunked responses | Не буферизує відповіді з `Transfer-Encoding: chunked` (важливо для SSE/streaming) |

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
# Ethereum L1 (State Anchoring)
ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# IoTeX W3bstream (ZK Verification)
W3BSTREAM_API_URL=https://w3bstream-api.iotex.io
W3BSTREAM_PROJECT_ID=silken_net_dmrv

# Chainlink Functions (Oracle)
CHAINLINK_ROUTER_ADDRESS=0x...
CHAINLINK_SUBSCRIPTION_ID=...

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
