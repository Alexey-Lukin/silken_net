## 06_01: Deployment Kamal & Terraform (Canopy vs Production)

## 🎯 Мета (Objective)

Зафіксувати **фактичний стан** конфігурацій розгортання та інфраструктури як коду (IaC) — результат "Reverse Shaping" Cycle 1. Документ відповідає на три ключові питання:

1. Чим відрізняються середовища **Canopy** (Staging) та **Production**?
2. Що розгортається в **GCP** (традиційна хмара), а що — в **Akash Network** (децентралізована мережа)?
3. Які **API-ключі, секрети та сертифікати** потрібні для першого реального деплою?

> **⚠️ SSOT Sync:** Цей документ синхронізовано з кодовою базою станом на 2026-03-24. Жодного реального деплою не виконувалось. TRL 4 → 5: інфраструктурний код існує та документований, фізичного провізіонування не відбувалось. Інтегровано нотатки N7–N12, N18 (Pre-Flight Checklist, Secrets Manager, Quickstart).

## ✅ Статус (Status)

- **Поточний TRL:** TRL 4 (Інфраструктурний код існує, деплой не проводився)
- **Цільовий TRL:** TRL 5 (Повна прозорість інфраструктури)
- **Пов'язані модулі:** Backend — `04_02_Business_Logic_and_Services`. Observability — `06_03_Prometheus_Observability`. Akash детально — `06_02_Akash_Network_Integration`.

---

## 🛑 Блокери (Blockers / Needs Action)

> Цей розділ є критично важливим. Жоден реальний деплой неможливий без вирішення цих пунктів.

### 🔴 BLOCKER-1: IP-адреси серверів — плейсхолдери

**Статус:** Не заповнено. Блокує Kamal deploy.

У `config/deploy.yml` та `config/deploy.canopy.yml` прописані плейсхолдери:
- `config/deploy.yml` → `192.168.0.1` (приватна IP — явно плейсхолдер)
- `config/deploy.canopy.yml` → `<CANOPY_SERVER_IP>` (текстовий плейсхолдер)

**Дія:** Після `terraform apply` отримати реальні IP:
```bash
terraform output web_server_ips    # → production IP
terraform output canopy_server_ip  # → canopy IP (якщо canopy_enabled = true)
```

---

### 🔴 BLOCKER-2: GCS Bucket для Terraform State — не існує

**Статус:** Chicken-and-egg проблема. Блокує `terraform init`.

Terraform backend посилається на GCS-кошик `silken-net-terraform-state`. Він має існувати **до** першого `terraform init`.

**Дія:** Створити вручну через `gcloud`:
```bash
# Перший раз — до terraform init
gcloud storage buckets create gs://silken-net-terraform-state \
  --project=<GCP_PROJECT_ID> \
  --location=europe-west1 \
  --uniform-bucket-level-access
```

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
| `REDIS_URL` | Production Redis (DB 0) | `redis://<host>:<port>/0` |
| `CANOPY_REDIS_URL` | Canopy Redis (DB 0) | — |
| `KREDIS_REDIS_URL` | Production Redis (DB 1) | `redis://<host>:<port>/1` |
| `SSH_PRIVATE_KEY` | Приватний SSH ключ (ed25519) | `ssh-keygen -t ed25519` |
| `SSH_PUBLIC_KEY` | Публічний SSH ключ | Пара до SSH_PRIVATE_KEY |
| `SSH_KNOWN_HOSTS` | SSH fingerprints серверів | `ssh-keyscan <server-ip>` |
| `KAMAL_MASTER_KEY` | Ключ шифрування Kamal secrets | `config/master.key` |

---

### 🔴 BLOCKER-4: `canopy_enabled = false` за замовчуванням

**Статус:** Canopy-сервер не буде провізіонований без явного включення.

**Дія:** Створити `terraform/terraform.tfvars` (в `.gitignore`!):
```hcl
project_id     = "your-gcp-project-id"
db_password    = "your-super-secret-password-16chars+"
canopy_enabled = true
```

> ⚠️ `terraform.tfvars` містить секрети — **ніколи не комітити в git**.

---

### 🟡 BLOCKER-5: Akash SDL має `REQUIRED_SECRET_NOT_SET` плейсхолдери

**Статус:** `deploy/akash/deploy.yaml` потребує ручного редагування перед деплоєм.

**Дія (рекомендовано):** Використати Terraform-шаблон `deploy/akash/deploy.yaml.tpl` — секрети підставляються автоматично з `terraform.tfvars`.

---

### 🟡 BLOCKER-6: Cloud SQL публічний IP для Akash

**Статус:** `akash_enabled = false` за замовчуванням → Cloud SQL не має публічного IP.

**Дія:** В `terraform.tfvars`:
```hcl
akash_enabled = true
akash_authorized_networks = [
  { name = "akash-provider-1", cidr = "1.2.3.4/32" }
]
```

> **Безпечніша альтернатива:** Cloud SQL Auth Proxy як sidecar-контейнер в SDL.

---

### 🟡 BLOCKER-7: Sidekiq (job role) відсутній в Akash SDL

**Статус:** Архітектурний gap.

Akash SDL визначає **тільки** `web` сервіс. На Akash **Sidekiq не запускається** — всі 31+ фонових воркерів (телеметрія, Web3, OTA) не виконуються.

**Дія:**
1. Додати `job` сервіс в Akash SDL: `bundle exec sidekiq -C config/sidekiq.yml`
2. Або залишити Sidekiq виключно на GCP, а Akash — тільки для web-шару.

---

### 🟡 BLOCKER-8: `ssh_source_ranges = ["0.0.0.0/0"]` — небезпечно

**Дія:** В `terraform.tfvars`:
```hcl
ssh_source_ranges = ["203.0.113.10/32", "198.51.100.0/24"]
```

---

### 🟡 BLOCKER-9: `KREDIS_REDIS_URL` відсутній у `.kamal/secrets`

**Дія:** Додати в `.kamal/secrets`:
```
KREDIS_REDIS_URL=$KREDIS_REDIS_URL
```
Та відповідний GitHub Secret.

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
gcloud storage buckets create gs://silken-net-terraform-state \
  --project=<GCP_PROJECT_ID> \
  --location=europe-west1 \
  --uniform-bucket-level-access

# Крок 2: Налаштувати terraform.tfvars
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Заповнити: project_id, db_password, canopy_enabled=true, ssh_source_ranges

# Крок 3: Провізіонувати інфраструктуру (10–15 хвилин)
terraform init
terraform plan
terraform apply
# → outputs: web_server_ips, canopy_server_ip, database_url, redis_url

# Крок 4: Оновити Kamal configs з реальними IP
# config/deploy.yml → servers.web: [<web_server_ip>]
# config/deploy.canopy.yml → servers.web: [<canopy_server_ip>]

# Крок 5: Створити DNS A-записи
# api.silkennet.com      → <web_server_ip>
# canopy.silkennet.com   → <canopy_server_ip>
# Дочекатися: dig api.silkennet.com → правильний IP

# Крок 6: Заповнити .kamal/secrets (з vault Bitwarden/1Password)
# RAILS_MASTER_KEY=...
# DATABASE_URL=$(terraform output -raw database_url)
# REDIS_URL=redis://<redis_host>:6379/0
# KREDIS_REDIS_URL=redis://<redis_host>:6379/1
# GCP_ARTIFACT_REGISTRY_KEY=<base64-json-key>

# Крок 7: Налаштувати Docker registry
gcloud auth configure-docker europe-west1-docker.pkg.dev

# Крок 8: Перший деплой
kamal setup
# → Traefik стартує → Let's Encrypt видає SSL → Rails запускається → CoAP listener відкриває UDP 5683
# Коли в логах: "Listening on coap://0.0.0.0:5683" — ліс може говорити.
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
| **Kamal конфіг** | `config/deploy.canopy.yml` (`-d canopy`) | `config/deploy.yml` (за замовчуванням) |
| **GCE машина** | `e2-medium` (2 vCPU, 4 GB RAM) | `n2-standard-2` (2 vCPU, 8 GB RAM) |
| **Диск** | 20 GB SSD | 30 GB SSD |
| **Terraform змінна** | `canopy_enabled = true` (⚠️ зараз `false`) | `web_node_count = 1` |
| **SSL/HTTPS** | Вимкнено | Let's Encrypt (потрібен DNS!) |
| **DB** | Окрема або спільна Cloud SQL | `silken_net_production` (HA) |
| **Redis** | Спільний або окремий Memorystore | Memorystore `STANDARD_HA` |
| **Puma workers** | `WEB_CONCURRENCY: 2` | `WEB_CONCURRENCY: 2` |

---

## ☁️ GCP vs Akash — Розподіл Ресурсів

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform (GCP)              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  web-0 (Prod 🌲, Kamal)  + canopy (🌿, Kamal)       │   │
│  │  Cloud SQL PostgreSQL 16 (4 бази, HA, приватна IP)  │   │
│  │  Memorystore Redis 7.0 (HA, приватна IP)             │   │
│  │  Artifact Registry (Docker images)                   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Akash Network                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  web сервіс (Rails 8.1 + Puma + Thruster)           │   │
│  │  4 vCPU / 8 GB RAM / 50 GB ephemeral                │   │
│  │  Порти: :80 (HTTP) + :5683/UDP (CoAP)               │   │
│  │                                                      │   │
│  │  ❌ НЕ запускає Sidekiq (job role відсутній в SDL)  │   │
│  │  ✅ Підключається до Cloud SQL (публічний IP + SSL) │   │
│  │  ⚠️ Redis (Memorystore) недоступний з Akash         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

| Сервіс/Ресурс | GCP (Kamal) | Akash Network | Примітка |
|--------------|-------------|---------------|---------|
| **Rails web (Puma + Thruster)** | ✅ | ✅ | Один Docker образ |
| **Sidekiq (job role)** | ✅ | ❌ | В Akash SDL відсутній |
| **CoAP UDP daemon (:5683)** | ✅ | ✅ | Порт відкритий в обох |
| **Cloud SQL PostgreSQL 16** | ✅ | ❌ | DB завжди на GCP |
| **Memorystore Redis 7.0** | ✅ | ❌ | Тільки приватна IP |
| **Artifact Registry (Docker)** | ✅ | shared | Той самий образ |

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
├── compute.tf    # GCE instances (web-0...N, canopy), Static IPs
├── database.tf   # Cloud SQL PostgreSQL 16, 4 databases, Private Service Access
├── redis.tf      # Memorystore Redis 7.0, HA
├── iam.tf        # Service Account silken-net-deploy + 7 IAM roles
├── variables.tf  # Всі input variables з валідацією
└── outputs.tf    # IP-адреси, DB URL, Redis URL тощо

terraform/akash/
├── main.tf       # SDL generation, null_resource (akash CLI)
├── variables.tf  # Akash-specific variables + app secrets
└── outputs.tf    # SDL path, deployment notes
```

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
| Puma workers (2) × Threads (5) | 10 |
| Sidekiq threads (25) | 25 |
| Puma canopy | 10 |
| Akash replicas (1) × Threads (3) × WEB_CONCURRENCY (4) | 12 |
| Rails DB console / admin | 5 |
| **Мінімум** | **~62** |

`400` — з великим запасом для масштабування. Адекватно.

---

## 🐳 Docker — Multi-stage Build

```
Stage 1: base          — ruby:4.0.1-slim + libjemalloc2, libvips, postgresql-client
Stage 2: build         — bundle install, bootsnap, assets:precompile
Stage 3: final         — COPY gems + app, USER rails:1000, CMD: thrust ./bin/rails server
```

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
☐ 1. Створити GCS bucket вручну (BLOCKER-2)
      gcloud storage buckets create gs://silken-net-terraform-state ...

☐ 2. Створити terraform/terraform.tfvars (BLOCKER-4)
      project_id, db_password, canopy_enabled=true, ssh_source_ranges=[<your-ip>]

☐ 3. Заповнити всі GitHub Secrets (BLOCKER-3)
      GCP_SA_KEY, GCP_PROJECT_ID, DATABASE_PASSWORD, DATABASE_URL, ...

☐ 4. terraform init && terraform plan && terraform apply
      Перевірити outputs: web_server_ips, canopy_server_ip, redis_host

☐ 5. Оновити IP в конфігах Kamal (BLOCKER-1)
      config/deploy.yml: 192.168.0.1 → <web_server_ips[0]>
      config/deploy.canopy.yml: <CANOPY_SERVER_IP> → <canopy_server_ip>

☐ 6. Додати KREDIS_REDIS_URL в .kamal/secrets (BLOCKER-9)

☐ 7. Вирішити підключення Redis з Akash (BLOCKER-6)

☐ 8. Вирішити Sidekiq на Akash (BLOCKER-7)

☐ 9. Створити deploy-production.yml workflow (INFO)

☐ 10. DNS A-запис створено та поширився (Pre-Flight #1) ← НОВЕ
       dig api.silkennet.com → правильний IP

☐ 11. .kamal/secrets заповнені реальними значеннями (Pre-Flight #2) ← НОВЕ

☐ 12. Oracle гаманці поповнені газом (MATIC/ETH/SOL/CELO) (Pre-Flight #3) ← НОВЕ

☐ 13. LoRa-антени підключені до всіх плат (Pre-Flight #4) ← НОВЕ

☐ 14. AES-ключ Soldier = AES-ключ Queen (побітово) (Pre-Flight #5) ← НОВЕ

☐ 15. Перший тестовий деплой Canopy:
       kamal setup -d canopy
       kamal deploy -d canopy
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
