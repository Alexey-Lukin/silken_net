# 06_01: Deployment Kamal & Terraform (Canopy vs Production)

## 🎯 Мета (Objective)

Зафіксувати **фактичний стан** конфігурацій розгортання та інфраструктури як коду (IaC) — результат "Reverse Shaping" Cycle 1. Документ відповідає на три ключові питання:

1. Чим відрізняються середовища **Canopy** (Staging) та **Production**?
2. Що розгортається в **GCP** (традиційна хмара), а що — в **Akash Network** (децентралізована мережа)?
3. Які **API-ключі, секрети та сертифікати** потрібні для першого реального деплою?

> **⚠️ SSOT Sync:** Цей документ синхронізовано з кодовою базою станом на 2026-03-23. Жодного реального деплою не виконувалось. Статус TRL 4 → 5: інфраструктурний код існує та повністю задокументований, але фізичного провізіонування ще не відбувалось. **Цей документ і є встановленням SSOT для модуля 06_01.**

## ✅ Статус (Status)

- **Поточний TRL:** TRL 4 (Інфраструктурний код існує, деплой не проводився, SSOT для деплою — цей документ)
- **Цільовий TRL:** TRL 5 (Повна прозорість інфраструктури та документація "як є")
- **Пов'язані модулі:** Backend — `04_02_Business_Logic_and_Services`. Observability — `06_03_Prometheus_Observability`. Akash детально — `06_02_Akash_Network_Integration`.

---

## 🛑 Блокери (Blockers / Needs Action)

> Цей розділ є критично важливим. Жоден реальний деплой неможливий без вирішення цих пунктів.

### 🔴 BLOCKER-1: IP-адреси серверів — плейсхолдери

**Статус:** Не заповнено. Блокує Kamal deploy.

У `config/deploy.yml` (production) та `config/deploy.canopy.yml` (canopy) прописані плейсхолдери замість реальних IP:

- `config/deploy.yml` → `192.168.0.1` (приватна IP — явно плейсхолдер)
- `config/deploy.canopy.yml` → `<CANOPY_SERVER_IP>` (текстовий плейсхолдер)

**Дія:** Після `terraform apply` отримати реальні IP з Terraform outputs і замінити:
```bash
terraform output web_server_ips      # → production IP
terraform output canopy_server_ip    # → canopy IP (якщо canopy_enabled = true)
```

---

### 🔴 BLOCKER-2: GCS Bucket для Terraform State — не існує

**Статус:** Chicken-and-egg проблема. Блокує `terraform init`.

Terraform backend в `terraform/main.tf` та `terraform/akash/main.tf` посилається на GCS-кошик `silken-net-terraform-state`. Цей кошик має існувати **до** першого `terraform init`. Але Terraform не може його створити автоматично.

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

Для автоматичного деплою через GitHub Actions потрібно заповнити секрети в **Settings → Secrets and variables → Actions**:

| Секрет | Опис | Де отримати |
|--------|------|-------------|
| `GCP_SA_KEY` | JSON ключ GCP Service Account (base64) | IAM → Service Accounts → `silken-net-deploy` → Keys |
| `GCP_PROJECT_ID` | ID GCP проєкту | GCP Console → Project selector |
| `DATABASE_PASSWORD` | Пароль Cloud SQL (≥16 символів) | Придумати. Зберегти у vault. |
| `DATABASE_URL` | Production DB URL | `terraform output database_url` |
| `CANOPY_DATABASE_URL` | Canopy DB URL | Окрема БД або схема для Canopy |
| `REDIS_URL` | Production Redis (DB 0) | `redis://<terraform output redis_host>:<port>/0` |
| `CANOPY_REDIS_URL` | Canopy Redis (DB 0) | Той самий Redis-інстанс, або окремий |
| `KREDIS_REDIS_URL` | Production Redis (DB 1) | `redis://<host>:<port>/1` |
| `SSH_PRIVATE_KEY` | Приватний SSH ключ (ed25519) для `deploy` user | Згенерувати: `ssh-keygen -t ed25519` |
| `SSH_PUBLIC_KEY` | Публічний SSH ключ | Пара до SSH_PRIVATE_KEY |
| `SSH_KNOWN_HOSTS` | SSH fingerprints серверів | `ssh-keyscan <server-ip>` |
| `KAMAL_MASTER_KEY` | Ключ шифрування Kamal secrets | `config/master.key` або `kamal secrets generate` |

---

### 🔴 BLOCKER-4: `canopy_enabled = false` за замовчуванням

**Статус:** Canopy-сервер не буде провізіонований без явного включення.

У `terraform/variables.tf` змінна `canopy_enabled` має значення `false`. Terraform не створить ні `google_compute_instance.canopy`, ні `google_compute_address.canopy`.

**Дія:** Створити `terraform/terraform.tfvars` (в `.gitignore`!) і вказати:
```hcl
project_id     = "your-gcp-project-id"
db_password    = "your-super-secret-password-16chars+"
canopy_enabled = true
```

> ⚠️ `terraform.tfvars` містить секрети — **ніколи не комітити в git**.

---

### 🟡 BLOCKER-5: Akash SDL має `REQUIRED_SECRET_NOT_SET` плейсхолдери

**Статус:** `deploy/akash/deploy.yaml` розрахований на ручне редагування перед деплоєм.

Статичний SDL містить `REQUIRED_SECRET_NOT_SET` для `RAILS_MASTER_KEY`, `DATABASE_URL`, `REDIS_URL`, `KREDIS_REDIS_URL`. При спробі деплою без замін — Rails не стартує.

**Дія (2 варіанти):**
1. **Рекомендовано:** Використати Terraform-шаблон (`deploy/akash/deploy.yaml.tpl`) через `terraform/akash/` — секрети підставляються автоматично з `terraform.tfvars`.
2. Ручне редагування `deploy/akash/deploy.yaml` перед деплоєм (небезпечно, не рекомендовано).

---

### 🟡 BLOCKER-6: Cloud SQL публічний IP для Akash

**Статус:** `akash_enabled = false` за замовчуванням → Cloud SQL не має публічного IP.

Akash-провайдери знаходяться **поза** GCP VPC. Коли Akash-контейнер намагається підключитися до Cloud SQL через приватну IP — з'єднання блокується.

**Дія:** Встановити `akash_enabled = true` в `terraform.tfvars` + обов'язково заповнити `akash_authorized_networks` з реальними CIDR-діапазонами Akash-провайдера (валідація забороняє `0.0.0.0/0`):
```hcl
akash_enabled = true
akash_authorized_networks = [
  { name = "akash-provider-1", cidr = "1.2.3.4/32" }
]
```

> **Більш безпечна альтернатива:** Cloud SQL Auth Proxy як sidecar-контейнер в SDL. Потребує додаткової конфігурації SDL.

---

### 🟡 BLOCKER-7: Sidekiq (job role) відсутній в Akash SDL

**Статус:** Архітектурний gap.

Kamal `config/deploy.yml` визначає дві ролі: `web` (Puma) та `job` (Sidekiq). Akash SDL у `deploy/akash/deploy.yaml` визначає **тільки** `web` сервіс. На Akash **Sidekiq не запускається**.

**Наслідок:** Всі 31+ фонових воркерів (телеметрія, Web3, OTA, EWS) не будуть виконуватись при деплої на Akash.

**Дія (2 варіанти):**
1. Додати `job` сервіс в Akash SDL з командою `bundle exec sidekiq -C config/sidekiq.yml`.
2. Залишити Sidekiq виключно на GCP (Kamal `job` role), а Akash використовувати лише для web-шару.

---

### 🟡 BLOCKER-8: `ssh_source_ranges = ["0.0.0.0/0"]` — небезпечно

**Статус:** SSH відкритий для всього інтернету.

У `terraform/variables.tf` `ssh_source_ranges` за замовчуванням `["0.0.0.0/0"]`. Це дозволяє SSH підключення з будь-якої IP-адреси.

**Дія:** В `terraform.tfvars` вказати конкретні IP VPN/офісу:
```hcl
ssh_source_ranges = ["203.0.113.10/32", "198.51.100.0/24"]
```

---

### 🟡 BLOCKER-9: `KREDIS_REDIS_URL` відсутній у `.kamal/secrets`

**Статус:** Неповна конфігурація секретів.

`.kamal/secrets` визначає `RAILS_MASTER_KEY`, `GCP_ARTIFACT_REGISTRY_KEY`, `DATABASE_URL`, `REDIS_URL` — але **не** `KREDIS_REDIS_URL`, хоча він прописаний в `config/deploy.yml` → `env.secret`.

**Дія:** Додати в `.kamal/secrets`:
```sh
KREDIS_REDIS_URL=$KREDIS_REDIS_URL
```
Та відповідний GitHub Secret `KREDIS_REDIS_URL` (або `CANOPY_KREDIS_REDIS_URL`).

---

### 🟢 INFO: `deploy-production.yml` workflow не знайдено

**Статус:** Згадується в `docs/DEPLOYMENT.md`, але файл відсутній в `.github/workflows/`.

У репо є тільки `.github/workflows/deploy.yml` (для Canopy). Production деплой через GitHub Release потребує окремого `deploy-production.yml`.

**Дія:** Створити `deploy-production.yml` аналогічно `deploy.yml`, але з тригером `on: release: types: [published]` та деплоєм без `-d canopy`.

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
│               │          │       │  terraform apply → kamal -d    │         │
│               └────┬─────┘       │  canopy                        │         │
│                    │             └────────────────────────────────┘         │
│                    │ ~2 тижні                                                │
│                    ▼                                                         │
│  ┌──────────────────────────────┐  ┌────────────────────────────────────┐   │
│  │  GitHub Release (v1.x.0)    │─▶│  Deploy Production 🌲              │   │
│  │  + changelog                │  │  terraform apply → kamal deploy    │   │
│  └──────────────────────────────┘  └────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
                  │                                  │
     ┌────────────┘                      ┌───────────┘
     ▼                                   ▼
┌──────────────────────────┐   ┌──────────────────────────┐
│    CANOPY (Staging) 🌿   │   │    PRODUCTION 🌲          │
│    GCE e2-medium         │   │    GCE n2-standard-2      │
│    2 vCPU / 4 GB RAM     │   │    2 vCPU / 8 GB RAM      │
│    20 GB SSD             │   │    30 GB SSD              │
│    HTTP only (no SSL)    │   │    HTTP + HTTPS            │
└──────────────────────────┘   └──────────────────────────┘
           │                              │
           └──────────┬───────────────────┘
                      ▼
     ┌────────────────────────────────────────┐
     │    GCP Data Layer (shared або окремий) │
     │    Cloud SQL PostgreSQL 16 (HA)        │
     │    Memorystore Redis 7.0 (HA)          │
     └────────────────────────────────────────┘
```

---

## 🌿 Canopy vs 🌲 Production — Порівняльна Таблиця

| Параметр | Canopy 🌿 | Production 🌲 |
|----------|-----------|---------------|
| **Тригер деплою** | Push в `main` після успішного CI | GitHub Release (`v*.*.*`) |
| **Workflow** | `.github/workflows/deploy.yml` | `.github/workflows/deploy-production.yml` |
| **Kamal конфіг** | `config/deploy.canopy.yml` (`-d canopy`) | `config/deploy.yml` (за замовчуванням) |
| **GCE машина** | `e2-medium` (2 vCPU, 4 GB RAM) | `n2-standard-2` (2 vCPU, 8 GB RAM) |
| **Диск** | 20 GB SSD | 30 GB SSD |
| **Terraform змінна** | `canopy_enabled = true` (⚠️ зараз `false`) | `web_node_count = 1` |
| **SSL/HTTPS** | Вимкнено (коментар у `deploy.canopy.yml`) | Потребує налаштування (Let's Encrypt) |
| **DB** | Окрема або спільна Cloud SQL | `silken_net_production` (Cloud SQL HA) |
| **Redis** | Спільний або окремий Memorystore | Memorystore `STANDARD_HA` |
| **Puma workers** | `WEB_CONCURRENCY: 2` | `WEB_CONCURRENCY: 2` |
| **Призначення** | Тестування після merge в main | Продакшн для кінцевих користувачів |
| **Захист від видалення** | Немає | `enable_deletion_protection = true` (Cloud SQL) |

---

## ☁️ GCP vs Akash — Розподіл Ресурсів

Це найважливіший розділ документа. Нижче чітко визначено, **що де живе**.

### Схема розподілу

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform (GCP)                              │
│                    Традиційна хмара. Централізований data layer.            │
│                                                                             │
│  ┌────────────────────────┐  ┌────────────────────────────────────────────┐ │
│  │  Artifact Registry     │  │   VPC: silken-net-vpc (10.0.0.0/20)       │ │
│  │  europe-west1          │  │                                            │ │
│  │  Docker images         │  │  ┌──────────┐  ┌──────────┐               │ │
│  │  (shared by Kamal      │  │  │  web-0   │  │  canopy  │               │ │
│  │   AND Akash)           │  │  │  Prod 🌲 │  │  🌿      │               │ │
│  └────────────────────────┘  │  │ (Kamal)  │  │ (Kamal)  │               │ │
│                              │  └──────────┘  └──────────┘               │ │
│                              │                                            │ │
│                              │  ┌──────────────────────────────────────┐  │ │
│                              │  │  Cloud SQL PostgreSQL 16 (HA)        │  │ │
│                              │  │  4 бази: production, cache,          │  │ │
│                              │  │  queue, cable                        │  │ │
│                              │  │  Приватна IP (публічна при Akash)    │  │ │
│                              │  └──────────────────────────────────────┘  │ │
│                              │                                            │ │
│                              │  ┌──────────────────────────────────────┐  │ │
│                              │  │  Memorystore Redis 7.0 (HA)          │  │ │
│                              │  │  DB 0: Sidekiq / DB 1: Kredis locks  │  │ │
│                              │  │  Приватна IP — тільки GCP VPC        │  │ │
│                              │  └──────────────────────────────────────┘  │ │
│                              └────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                    Akash Network (Децентралізована мережа)                  │
│                    Web/API layer. Compute only. Data — в GCP.               │
│                                                                             │
│  ┌────────────────────────────────────────────────────────────────────────┐ │
│  │  web сервіс (Rails 8.1 + Puma + Thruster)                             │ │
│  │  4 vCPU / 8 GB RAM / 50 GB ephemeral / 10 GB persistent               │ │
│  │  Порти: :80 (HTTP) + :5683/UDP (CoAP)                                  │ │
│  │  Провайдер: верифікований auditor (akash1365yvmc4s7...)                │ │
│  │                                                                        │ │
│  │  ❌ НЕ запускає Sidekiq — job role відсутній в SDL!                    │ │
│  │  ✅ Підключається до Cloud SQL через публічний IP + SSL                │ │
│  │  ⚠️ Redis (Memorystore) недоступний — потрібен публічний IP або тунель │ │
│  └────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Таблиця: Що де розгортається

| Сервіс/Ресурс | GCP (Kamal) | Akash Network | Примітка |
|---------------|:-----------:|:-------------:|----------|
| **Rails web (Puma + Thruster)** | ✅ | ✅ | Обидва варіанти — один образ |
| **Sidekiq (job role)** | ✅ | ❌ | В Akash SDL відсутній `job` сервіс |
| **CoAP UDP daemon (:5683)** | ✅ | ✅ | Порт відкритий в обох |
| **Cloud SQL PostgreSQL 16** | ✅ | ❌ | DB завжди на GCP, Akash підключається ззовні |
| **Memorystore Redis 7.0** | ✅ | ❌ | Тільки приватна IP, недоступний з Akash |
| **Artifact Registry (Docker)** | ✅ | shared | Той самий образ pull-яться Akash |
| **Active Storage (volume)** | GCS / Volume | Persistent storage | 10 GB persistent в Akash SDL |
| **Terraform state** | GCS bucket | GCS bucket | Окремий prefix `terraform/akash` |

---

## 📦 Kamal — Детальний Аналіз

### Файлова структура

| Файл | Опис |
|------|------|
| `config/deploy.yml` | Production-конфіг (основний) |
| `config/deploy.canopy.yml` | Canopy-перевизначення (`-d canopy`) |
| `.kamal/secrets` | Runtime секрети (читаються при деплої) |
| `.kamal/hooks/` | Хуки ЖЦ (тільки sample-файли, не кастомізовані) |

### `config/deploy.yml` — Production

```yaml
service: silken_net          # Ім'я сервісу (використовується в іменах контейнерів)
image:  silken_net           # Ім'я Docker образу

servers:
  web:
    - 192.168.0.1            # ⚠️ PLACEHOLDER — замінити на реальну IP
  job:                       # Sidekiq worker
    hosts:
      - 192.168.0.1          # ⚠️ PLACEHOLDER — може бути окремий хост
    cmd: bundle exec sidekiq -C config/sidekiq.yml

boot:
  proxy:
    publish:
      - "80:80"              # HTTP
      - "443:443"            # HTTPS (Let's Encrypt)
      - "5683:5683/udp"      # CoAP IoT uplink

registry:
  server:   europe-west1-docker.pkg.dev
  username: _json_key_base64
  password:
    - GCP_ARTIFACT_REGISTRY_KEY  # GCP SA JSON key (base64)

env:
  secret:
    - RAILS_MASTER_KEY
    - DATABASE_URL
    - REDIS_URL
    - KREDIS_REDIS_URL
  clear:
    WEB_CONCURRENCY: 2       # Puma: 2 worker processes (на 2 vCPU)
```

### `config/deploy.canopy.yml` — Canopy

```yaml
# Тільки перевизначення відносно deploy.yml:
servers:
  web:
    - <CANOPY_SERVER_IP>     # ⚠️ PLACEHOLDER — замінити після terraform apply

# proxy: ssl вимкнено (HTTP only для розробки)
```

### Rollback та Аліаси

```bash
kamal rollback              # Відкат до попередньої версії
kamal app exec --interactive --reuse "bin/rails console"   # Rails console
kamal logs -f               # Стримінг логів
kamal app exec --interactive --reuse "bash"                # Shell
kamal app exec --interactive --reuse "bin/rails dbconsole --include-password"
# Canopy-специфічні:
kamal app exec --interactive --reuse "bin/rails console" -d canopy
kamal logs -f -d canopy
```

---

## 🏗️ Terraform (GCP) — Детальний Аналіз

### Файлова структура

```
terraform/
├── main.tf          # Provider (google ~> 5.0), GCP APIs, Artifact Registry, Logging exclusion
├── vpc.tf           # VPC, subnet (10.0.0.0/20), Cloud Router, Cloud NAT, Firewall rules
├── compute.tf       # GCE instances (web-0...N, canopy), Static IPs
├── database.tf      # Cloud SQL PostgreSQL 16, 4 databases, read replicas, Private Service Access
├── redis.tf         # Memorystore Redis 7.0, HA, DB isolation strategy
├── iam.tf           # Service Account silken-net-deploy + 7 IAM roles
├── variables.tf     # Всі input variables з валідацією
└── outputs.tf       # IP-адреси, DB URL, Redis URL, Registry URL тощо

terraform/akash/
├── main.tf          # SDL generation (templatefile), null_resource (akash CLI)
├── variables.tf     # Akash-specific variables + app secrets
└── outputs.tf       # SDL path, deployment notes
```

### GCP Region та Zone

| Параметр | Значення |
|----------|---------|
| Region | `europe-west1` (Бельгія) |
| Zone | `europe-west1-b` |
| Redis alternative zone | `europe-west1-c` (HA failover) |

### VPC та Мережа (vpc.tf)

```
silken-net-vpc (custom, no auto subnets)
└── silken-net-web-subnet (10.0.0.0/20 → 4094 хостів)
    ├── web-0 (production)
    └── canopy (staging, якщо увімкнено)

Cloud Router + Cloud NAT → вихідний інтернет для приватних інстансів
Private Service Access → Cloud SQL через приватну IP
```

**Правила фаєрволу:**

| Правило | Протокол:Порт | Джерело | Тег |
|---------|---------------|---------|-----|
| `allow-ssh` | TCP:22 | `ssh_source_ranges` (за замовч. `0.0.0.0/0` ⚠️) | `web-nodes` |
| `allow-web` | TCP:80,443 | `0.0.0.0/0` | `web-nodes` |
| `allow-coap` | UDP:5683 | `0.0.0.0/0` | `web-nodes` |
| `allow-internal` | TCP/UDP/ICMP:all | `10.0.0.0/20` | — |
| `deny-all-ingress` | all | `0.0.0.0/0` | — (priority 65534) |

### Compute (compute.tf)

| Параметр | Production 🌲 | Canopy 🌿 |
|----------|---------------|-----------|
| Terraform resource | `google_compute_instance.web[0..N]` | `google_compute_instance.canopy[0]` |
| Machine type | `n2-standard-2` (2 vCPU, 8 GB) | `e2-medium` (2 vCPU, 4 GB) |
| Disk | 30 GB `pd-ssd` | 20 GB `pd-ssd` |
| ОС | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| Shielded VM | ✅ (secure boot + vTPM + integrity) | ✅ |
| OS Login | ✅ | ✅ |
| SSH user | `deploy` | `deploy` |
| Terraform toggle | `web_node_count` (за замовч. `1`) | `canopy_enabled` (за замовч. `false` ⚠️) |

### Cloud SQL PostgreSQL 16 (database.tf)

| Параметр | Значення |
|----------|---------|
| Instance name | `silken-db` |
| Версія | PostgreSQL 16 |
| Tier | `db-custom-2-7680` (2 vCPU, 7.68 GB RAM) |
| Availability | `REGIONAL` (HA з automatic failover) |
| Диск | 50 GB SSD, автоматичне розширення |
| SSL | Обов'язковий (`require_ssl = true`) |
| Приватна мережа | Так (Private Service Access) |
| Публічна IP | Лише при `akash_enabled = true` |
| Бекап | Увімкнено, PITR, 30 днів |
| `max_connections` | `400` |

**4 бази даних:**

| База | Призначення |
|------|-------------|
| `silken_net_production` | Основні дані (Rails primary DB) |
| `silken_net_production_cache` | Solid Cache |
| `silken_net_production_queue` | Solid Queue |
| `silken_net_production_cable` | Solid Cable (ActionCable) |

**Read replicas:** `db_read_replica_count = 0` за замовчуванням (горизонтальне читання не активовано).

### Memorystore Redis 7.0 (redis.tf)

| Параметр | Значення |
|----------|---------|
| Tier | `STANDARD_HA` (автоматичний failover) |
| Пам'ять | 1 GB |
| `maxmemory-policy` | `noeviction` (при переповненні Redis відмовляє в записі, але не втрачає наявні ключі — безпечніше за `volatile-lru` для Web3 nonce-локів) |
| Transit encryption | `SERVER_AUTHENTICATION` |
| Мережа | Приватна (тільки VPC) |

**DB ізоляція:**

| Redis DB | ENV var | Призначення |
|----------|---------|-------------|
| DB 0 | `REDIS_URL` | Sidekiq job queues |
| DB 1 | `KREDIS_REDIS_URL` | Kredis distributed locks (Web3 nonce management) |

> Ізоляція DB запобігає витісненню Web3 nonce-локів при flood-і черги телеметрії.

### IAM Service Account (iam.tf)

Account: `silken-net-deploy@<project>.iam.gserviceaccount.com`

| Роль | Призначення |
|------|-------------|
| `compute.instanceAdmin.v1` | Управління GCE інстансами (Kamal SSH + start/stop) |
| `compute.osLogin` | SSH через OS Login на Shielded VMs |
| `artifactregistry.writer` | Push Docker образів під час деплою |
| `artifactregistry.reader` | Pull Docker образів з інстансів |
| `logging.logWriter` | Відправка логів у Cloud Logging |
| `monitoring.metricWriter` | Відправка метрик у Cloud Monitoring |
| `cloudsql.client` | Cloud SQL Auth Proxy (для Akash sidecar) |

### Artifact Registry (main.tf)

| Параметр | Значення |
|----------|---------|
| URL | `europe-west1-docker.pkg.dev/<project>/silken-net` |
| Формат | Docker |
| Cleanup | Зберігати 10 останніх, видаляти старші за 30 днів |

### Logging Cost Control (main.tf)

Виключено log-ингestion нижче `WARNING` severity в Cloud Logging. Мільйони INFO-логів з телеметрії не генерують білінг.

### Terraform State Backends

| Модуль | GCS Prefix |
|--------|-----------|
| `terraform/` (GCP) | `terraform/state` |
| `terraform/akash/` | `terraform/akash` |

---

## 🔑 Повний Список ENV / Секретів для Деплою

### Kamal Runtime Secrets (`.kamal/secrets`)

| Змінна | Джерело |
|--------|---------|
| `RAILS_MASTER_KEY` | `cat config/master.key` |
| `GCP_ARTIFACT_REGISTRY_KEY` | GCP SA JSON key (base64) |
| `DATABASE_URL` | `terraform output -raw database_url` |
| `REDIS_URL` | `redis://<terraform output redis_host>:<redis_port>/0` |
| `KREDIS_REDIS_URL` ⚠️ *не додано* | `redis://<host>:<port>/1` |

### Akash SDL Variables (`terraform/akash/terraform.tfvars`)

| Змінна | Тип | Примітка |
|--------|-----|----------|
| `akash_key_name` | string | Ім'я ключа в Akash keyring |
| `akash_chain_id` | string | За замовч. `akashnet-2` |
| `akash_node` | string | За замовч. `https://rpc.akashnet.net:443` |
| `docker_image` | string | Full image URL (з Artifact Registry) |
| `rails_master_key` | sensitive | З `config/master.key` |
| `database_url` | sensitive | Cloud SQL public IP + SSL |
| `redis_url` | sensitive | Memorystore (потрібен тунель або публічний IP) |
| `kredis_redis_url` | sensitive | Memorystore DB 1 |
| `web_cpu_units` | number | За замовч. `4` |
| `web_memory_size` | string | За замовч. `"8Gi"` |
| `web_replicas` | number | За замовч. `1` |
| `max_price_uakt` | number | За замовч. `10000` |

### Розрахунок `max_connections` (database.tf)

Поточне значення `400`. Розрахунок мінімальних потреб:

| Компонент | Підключення |
|-----------|-------------|
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
┌──────────────────────────────────────────────────┐
│  Stage 1: base                                   │
│  ruby:4.0.1-slim                                 │
│  + curl, libjemalloc2, libvips, postgresql-client│
│  RAILS_ENV=production                            │
│  LD_PRELOAD=libjemalloc.so  (RAM -30..40%)       │
├──────────────────────────────────────────────────┤
│  Stage 2: build (throw-away)                     │
│  + build-essential, git, libpq-dev, libyaml-dev  │
│  → bundle install (vendor/)                      │
│  → bootsnap precompile (-j 1, QEMU safe)         │
│  → assets:precompile (SECRET_KEY_BASE_DUMMY=1)   │
├──────────────────────────────────────────────────┤
│  Stage 3: final                                  │
│  COPY gems + app від build                       │
│  USER rails:1000 (non-root)                      │
│  ENTRYPOINT: bin/docker-entrypoint (db:prepare)  │
│  CMD: ./bin/thrust ./bin/rails server            │
│  EXPOSE 80 (Thruster HTTP/2 proxy)               │
└──────────────────────────────────────────────────┘
```

---

## 🚀 Akash SDL — Технічний Аналіз

### Файлова структура

| Файл | Призначення |
|------|-------------|
| `deploy/akash/deploy.yaml` | Статичний SDL — ручний деплой через `akash` CLI або Akash Console |
| `deploy/akash/deploy.yaml.tpl` | Шаблон SDL — рендериться Terraform з підстановкою змінних |
| `terraform/akash/main.tf` | `local_file` (рендер шаблону) + `null_resource` (CLI wrapper) |
| `terraform/akash/generated-deploy.yaml` | Генерується Terraform, містить секрети (права `0600`) |

### Ресурси (profiles.compute.web)

| Ресурс | Значення | vs GCP Production |
|--------|---------|-------------------|
| CPU | 4 units | +2 (компенсація нестабільності провайдерів) |
| RAM | 8 Gi | = |
| Ephemeral storage | 50 Gi | +20 GB (контейнер включає все) |
| Persistent storage | 10 Gi (beta3) | Active Storage volume |

### Провайдер та ціна (profiles.placement)

| Параметр | Значення |
|----------|---------|
| Auditor | `akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24` (офіційний Akash auditor) |
| Max price | `10000 uAKT/block` (~6 сек) |
| Атрибут | `host: akash` |

### Процес Akash деплою (через Terraform)

```bash
# 1. Заповнити змінні
cd terraform/akash
# terraform.tfvars.example відсутній у репо — створити вручну:
cat > terraform.tfvars <<'EOF'
akash_key_name   = "silken-deploy"
docker_image     = "europe-west1-docker.pkg.dev/<project>/silken-net/silken_net:latest"
rails_master_key = "<contents of config/master.key>"
database_url     = "postgres://silken_net:<pass>@<cloud-sql-public-ip>:5432/silken_net_production"
redis_url        = "redis://<host>:6379/0"
EOF

# 2. Ініціалізація
terraform init   # Потребує GCS bucket silken-net-terraform-state

# 3. Деплой
terraform apply

# 4. Прийняти бід
akash query market bid list --owner <your-address> --dseq <DSEQ>
akash tx market lease create --dseq <DSEQ> --provider <provider-address> --from <akash_key_name>

# 5. Маніфест
akash provider send-manifest terraform/akash/generated-deploy.yaml \
  --dseq <DSEQ> --provider <provider-address> --from <akash_key_name>

# 6. Перевірка
akash provider lease-status --dseq <DSEQ> --provider <provider-address> --from <akash_key_name>
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
       Перевірити outputs: web_server_ips, canopy_server_ip, redis_host, database_connection_name

☐ 5. Оновити IP в конфігах Kamal (BLOCKER-1)
       config/deploy.yml: 192.168.0.1 → <terraform output web_server_ips[0]>
       config/deploy.canopy.yml: <CANOPY_SERVER_IP> → <terraform output canopy_server_ip>

☐ 6. Додати KREDIS_REDIS_URL в .kamal/secrets (BLOCKER-9)

☐ 7. Вирішити підключення Redis з Akash (BLOCKER-6)
       Варіант А: Tailscale/WireGuard тунель
       Варіант Б: Окремий Redis instance з публічним IP

☐ 8. Вирішити Sidekiq на Akash (BLOCKER-7)
       Додати job сервіс в SDL або залишити Sidekiq виключно на GCP

☐ 9. Створити deploy-production.yml workflow (INFO)

☐ 10. Перший тестовий деплой Canopy:
        kamal setup -d canopy  (перший раз — встановлює Kamal Proxy)
        kamal deploy -d canopy
```

---

## 🔗 Пов'язані ресурси

- **`docs/DEPLOYMENT.md`** — детальна операційна документація (команди, діаграми)
- **`06_02_Akash_Network_Integration`** — поглиблений аналіз Akash SDL та провайдерів
- **`06_03_Prometheus_Observability`** — метрики, Grafana, Cloud Monitoring алерти
- **`04_02_Business_Logic_and_Services`** — Sidekiq workers та черги (що НЕ запускається на Akash)
- **`terraform/`** — Infrastructure as Code (GCP)
- **`terraform/akash/`** — Infrastructure as Code (Akash)
- **`config/deploy.yml`**, **`config/deploy.canopy.yml`** — Kamal конфіги
- **`deploy/akash/deploy.yaml`** — Akash SDL
