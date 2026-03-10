# 🚀 Deployment & Infrastructure

Цей документ описує повний процес деплою Silken Net — від коміту в `main` до продакшн-релізу.

## Зміст

- [Огляд](#огляд)
- [Середовища](#середовища)
- [CI/CD Pipeline](#cicd-pipeline)
- [Інфраструктура Google Cloud (Terraform)](#інфраструктура-google-cloud-terraform)
- [Kamal — оркестрація контейнерів](#kamal--оркестрація-контейнерів)
- [Docker](#docker)
- [GitHub Secrets](#github-secrets)
- [Як зробити деплой](#як-зробити-деплой)
- [Операційні команди](#операційні-команди)
- [Діаграма](#діаграма)
- [Akash Network — децентралізований деплой](#akash-network--децентралізований-деплой)

---

## Огляд

Silken Net використовує **двосередовищну модель** деплою:

| Середовище | Тригер | Сервер | Призначення |
|------------|--------|--------|-------------|
| **Canopy** 🌿 | Пуш в `main` (після CI) | `e2-medium` (легкий) | Тестування для розробників |
| **Production** 🌲 | GitHub Release | `n2-standard-2` (потужний) | Користувачі, прод |

> **Canopy** (полог лісу) — верхній шар крон дерев, який першим зустрічає сонце і дощ, захищаючи основний ліс. Розробники тестують у "кроні", перш ніж зміни дістануться до "лісу" (production).

Немає окремого `production` бранча. Команда працює в `main` протягом спрінту (≈2 тижні), а потім створює GitHub Release для деплою на прод.

---

## Середовища

### 🌿 Canopy

- **Коли деплоїться:** Автоматично після кожного пушу в `main`, якщо всі CI-перевірки пройшли.
- **Сервер:** `e2-medium` (2 vCPU, 4 GB RAM) — дешевший за прод.
- **Мета:** Розробники бачать актуальний стан `main` на живому сервері.
- **Kamal destination:** `canopy` (`config/deploy.canopy.yml`).
- **Workflow:** `.github/workflows/deploy.yml`.

### 🌲 Production

- **Коли деплоїться:** Коли створюється GitHub Release (тег + changelog).
- **Сервер:** `n2-standard-2` (2 vCPU, 8 GB RAM) — Shielded VM, SSD.
- **Мета:** Прод для кінцевих користувачів.
- **Kamal destination:** за замовчуванням (`config/deploy.yml`).
- **Workflow:** `.github/workflows/deploy-production.yml`.

### RAILS_ENV

Обидва середовища працюють з `RAILS_ENV=production`. Це стандартна практика — Rails production-режим означає скомпільовані ассети, кешування, оптимізації. Різниця між Canopy та Production — в інфраструктурі (потужність серверу, окремі бази), а не в Rails-конфігурації.

---

## CI/CD Pipeline

### 1. CI — Перевірки (`ci.yml`)

Спрацьовує на **pull request** та **push в main**.

| Джоба | Що робить |
|-------|-----------|
| `scan_ruby` | Brakeman (безпека Rails) + bundler-audit (вразливості гемів) |
| `scan_js` | importmap audit (JS-залежності) |
| `lint` | RuboCop (стиль коду) |
| `test` | RSpec юніт/інтеграційні тести |
| `feature-test` | RSpec feature-тести (Capybara + Selenium) |

### 2. Deploy Canopy (`deploy.yml`)

Спрацьовує **автоматично** після успішного CI на `main` (через `workflow_run`).

```
CI (усі 5 джоб) ✅ → Terraform Apply → Kamal Deploy -d canopy
```

Також можна запустити вручну через **workflow_dispatch** у GitHub Actions.

### 3. Deploy Production (`deploy-production.yml`)

Спрацьовує при **створенні GitHub Release** (`release: published`).

```
GitHub Release ✅ → Terraform Apply → Kamal Deploy (production)
```

Також можна запустити вручну через **workflow_dispatch**.

### Процес роботи команди

```
Day 1-14: Розробка в main
  ├── PR → CI перевірки → merge
  ├── Push в main → CI ✅ → Auto-deploy Canopy 🌿
  └── Розробники тестують на Canopy-сервері

Day 14: Реліз
  ├── GitHub → Releases → "Create a new release"
  ├── Вибираємо тег (наприклад v1.2.0)
  ├── Генеруємо changelog (кнопка "Generate release notes")
  └── Publish → Auto-deploy Production 🌲
```

---

## Інфраструктура Google Cloud (Terraform)

Вся інфраструктура описана в `terraform/` як Infrastructure as Code.

### Структура файлів

```
terraform/
├── main.tf                   # Provider, GCP APIs, Artifact Registry
├── vpc.tf                    # VPC, підмережі, фаєрвол, NAT
├── compute.tf                # Web-сервери (production + canopy)
├── database.tf               # Cloud SQL PostgreSQL 16
├── redis.tf                  # Memorystore Redis 7.0
├── iam.tf                    # Service account та ролі
├── variables.tf              # Змінні конфігурації
├── outputs.tf                # Виходи (IP-адреси, URL тощо)
└── terraform.tfvars.example  # Приклад значень змінних
```

### Мережа (vpc.tf)

```
┌─────────────────────────────────────────┐
│           silken-net-vpc                │
│        (custom, no auto subnets)        │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  silken-net-web-subnet          │    │
│  │  10.0.0.0/20 (4094 IPs)        │    │
│  │                                 │    │
│  │  ┌──────────┐  ┌──────────┐    │    │
│  │  │ web-0    │  │ canopy   │    │    │
│  │  │ (prod) 🌲│  │ (dev) 🌿 │    │    │
│  │  └──────────┘  └──────────┘    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  Cloud Router + Cloud NAT               │
│  (автоматичний вихідний трафік)         │
└─────────────────────────────────────────┘
```

**Правила фаєрволу:**

| Правило | Порти | Джерело | Призначення |
|---------|-------|---------|-------------|
| `allow-ssh` | TCP 22 | `ssh_source_ranges` | SSH доступ |
| `allow-web` | TCP 80, 443 | `0.0.0.0/0` | HTTP/HTTPS |
| `allow-coap` | UDP 5683 | `0.0.0.0/0` | IoT (Queen → сервер) |
| `allow-internal` | Усі | `10.0.0.0/20` | Внутрішнє спілкування |
| `deny-all-ingress` | Усі | `0.0.0.0/0` | Заборона решти (priority 65534) |

### Compute (compute.tf)

**Production сервер(и)** 🌲:
- Тип: `n2-standard-2` (2 vCPU, 8 GB RAM)
- ОС: Ubuntu 24.04 LTS
- Диск: 30 GB SSD
- Shielded VM (secure boot, vTPM, integrity monitoring)
- OS Login увімкнено
- Кількість: `web_node_count` (за замовчуванням 1)

**Canopy сервер** 🌿:
- Тип: `e2-medium` (2 vCPU, 4 GB RAM) — дешевший
- ОС: Ubuntu 24.04 LTS
- Диск: 20 GB SSD
- Shielded VM
- Увімкнення: `canopy_enabled = true`

### База даних (database.tf)

- **Cloud SQL PostgreSQL 16**
- Тіер: `db-custom-2-7680` (2 vCPU, 7.68 GB RAM)
- Доступність: REGIONAL (HA з автоматичним failover)
- Приватна мережа (без публічного IP)
- SSL обов'язковий
- Диск: 50 GB SSD, автоматичне розширення
- Бекапи: увімкнені, PITR, зберігання 30 днів

**Бази даних:**

| База | Призначення |
|------|-------------|
| `silken_net_production` | Основні дані додатку |
| `silken_net_production_cache` | Solid Cache |
| `silken_net_production_queue` | Solid Queue (фонові задачі) |
| `silken_net_production_cable` | Solid Cable (WebSocket) |

### Redis (redis.tf)

- **Memorystore Redis 7.0**
- Тіер: STANDARD_HA (автоматичний failover)
- Пам'ять: 1 GB
- Приватна мережа
- Transit encryption
- Політика: `noeviction`
- Призначення: Sidekiq черги та кешування

### IAM (iam.tf)

Service account `silken-net-deploy` з мінімальними правами:

| Роль | Призначення |
|------|-------------|
| `compute.instanceAdmin.v1` | Управління інстансами при деплої |
| `compute.osLogin` | SSH через OS Login |
| `artifactregistry.writer` | Пуш Docker-образів |
| `artifactregistry.reader` | Пул Docker-образів |
| `logging.logWriter` | Відправка логів у Cloud Logging |
| `monitoring.metricWriter` | Відправка метрик у Cloud Monitoring |

### Artifact Registry (main.tf)

- Реєстр: `europe-west1-docker.pkg.dev/{project}/silken-net`
- Формат: Docker
- Політика очищення: зберігати 10 останніх образів, видаляти старші за 30 днів

### Terraform State

- Бекенд: Google Cloud Storage (`silken-net-terraform-state`)
- Файл стану зберігається віддалено для командної роботи

### Як працювати з Terraform

```bash
cd terraform

# Ініціалізація (перший раз або після зміни бекенду)
terraform init

# Перевірка конфігурації
terraform validate

# Переглянути план змін (що зміниться)
terraform plan

# Застосувати зміни
terraform apply

# Переглянути поточний стан
terraform output
terraform output database_url    # конкретний вихід
```

---

## Kamal — оркестрація контейнерів

[Kamal](https://kamal-deploy.org/) — інструмент деплою від Basecamp (автори Rails). Він:
- Збирає Docker-образ
- Пушить у Google Artifact Registry
- Підключається до серверів по SSH
- Запускає нові контейнери
- Перемикає трафік через вбудований proxy (Kamal Proxy)
- Видаляє старі контейнери

### Конфігурація

| Файл | Середовище | Опис |
|------|------------|------|
| `config/deploy.yml` | Production 🌲 | Основна конфігурація Kamal |
| `config/deploy.canopy.yml` | Canopy 🌿 | Перевизначення для Canopy-сервера |
| `.kamal/secrets` | Обидва | Секрети (runtime) |
| `.kamal/hooks/` | Обидва | Хуки життєвого циклу деплою |

### Production (`config/deploy.yml`)

```yaml
service: silken_net
image: silken_net

servers:
  web:
    - <production-server-ip>

boot:
  proxy:
    publish:
      - "80:80"       # HTTP
      - "443:443"     # HTTPS
      - "5683:5683/udp" # CoAP (IoT)

registry:
  server: europe-west1-docker.pkg.dev
  username: _json_key_base64
  password:
    - GCP_ARTIFACT_REGISTRY_KEY
```

### Canopy (`config/deploy.canopy.yml`)

Kamal "destination" — наслідує від `deploy.yml` і перевизначає:

```yaml
# The forest canopy: first layer that meets the sun 🌿
servers:
  web:
    - <canopy-server-ip>
```

Деплой Canopy:
```bash
kamal deploy -d canopy
```

### Секрети

Секрети передаються через змінні середовища в GitHub Actions або `.kamal/secrets`:

| Секрет | Опис |
|--------|------|
| `RAILS_MASTER_KEY` | Ключ шифрування Rails credentials |
| `DATABASE_URL` | Рядок підключення до PostgreSQL |
| `REDIS_URL` | Рядок підключення до Redis |
| `GCP_ARTIFACT_REGISTRY_KEY` | GCP Service Account ключ (base64) |

---

## Docker

### Multi-stage build (`Dockerfile`)

```
┌─────────────────────┐
│ Stage 1: base        │  ruby:4.0.1-slim + runtime packages
├─────────────────────┤
│ Stage 2: build       │  + build tools → bundle install → precompile
├─────────────────────┤
│ Stage 3: final       │  base + compiled gems + app code (non-root user)
└─────────────────────┘
```

**Особливості:**
- **Jemalloc** — оптимізація пам'яті (`LD_PRELOAD`)
- **Non-root** — додаток працює від `rails:1000`
- **Entrypoint** — автоматичний `db:prepare` при старті сервера
- **Thruster** — HTTP/2 proxy перед Puma
- Порт: 80

### .dockerignore

Виключає з образу: `.git`, `.github`, `.kamal`, `node_modules`, `storage`, `tmp`, `.env`, `master.key`.

---

## GitHub Secrets

Необхідні секрети в **Settings → Secrets and variables → Actions**:

| Секрет | Опис |
|--------|------|
| `GCP_SA_KEY` | JSON ключ GCP Service Account |
| `GCP_PROJECT_ID` | ID проєкту в Google Cloud |
| `DATABASE_PASSWORD` | Пароль Cloud SQL (≥16 символів) |
| `DATABASE_URL` | Production: `postgres://silken_net:<pass>@<ip>:5432/silken_net_production` |
| `CANOPY_DATABASE_URL` | Canopy: URL бази даних для canopy-середовища |
| `REDIS_URL` | Production: `redis://<ip>:6379/0` |
| `CANOPY_REDIS_URL` | Canopy: URL Redis для canopy-середовища |
| `SSH_PRIVATE_KEY` | Приватний SSH ключ (`ed25519`) |
| `SSH_PUBLIC_KEY` | Публічний SSH ключ |
| `SSH_KNOWN_HOSTS` | SSH fingerprints серверів |
| `KAMAL_MASTER_KEY` | Ключ шифрування Kamal |

---

## Як зробити деплой

### 🌿 Canopy (автоматично)

```
1. Зроби зміни в feature-бранчі
2. Створи PR → CI перевірки запускаються автоматично
3. Merge PR в main
4. CI проходить на main → Deploy Canopy запускається автоматично
5. Через ~5 хвилин зміни доступні на Canopy-сервері
```

### 🌲 Production (через Release)

```
1. Переходь на GitHub → Releases → "Draft a new release"
2. "Choose a tag" → введи новий тег (наприклад v1.2.0)
3. Target: main
4. Натисни "Generate release notes" (автоматичний changelog)
5. Відредагуй опис за потреби
6. Натисни "Publish release"
7. Deploy Production запускається автоматично
8. Через ~10 хвилин зміни на продакшні
```

### Ручний деплой

Будь-який деплой можна запустити вручну:

```
GitHub → Actions → "Deploy Canopy" або "Deploy Production" → Run workflow
```

Або через CLI:
```bash
# Canopy 🌿
kamal deploy -d canopy

# Production 🌲
kamal deploy
```

---

## Операційні команди

```bash
# ── Production 🌲 ──────────────────────────
kamal console                # Rails консоль
kamal shell                  # Bash на контейнері
kamal logs -f                # Логи в реальному часі
kamal dbc                    # Консоль бази даних
kamal app boot               # Перезапустити додаток
kamal details                # Статус контейнерів

# ── Canopy 🌿 ──────────────────────────────
kamal console -d canopy      # Rails консоль
kamal shell -d canopy        # Bash на контейнері
kamal logs -f -d canopy      # Логи в реальному часі
kamal dbc -d canopy          # Консоль бази даних
kamal app boot -d canopy     # Перезапустити додаток
kamal details -d canopy      # Статус контейнерів
```

---

## Діаграма

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            GITHUB REPOSITORY                                │
│                                                                              │
│  ┌─────────┐    ┌───────┐    ┌────────────────────────────────────────────┐  │
│  │ Feature │───▶│  PR   │───▶│  CI (scan, lint, test, feature-test)      │  │
│  │ Branch  │    │       │    └───────────────────────┬────────────────────┘  │
│  └─────────┘    └───┬───┘                            │                       │
│                     │ merge                          │ ✅ pass               │
│                     ▼                                ▼                       │
│               ┌──────────┐          ┌──────────────────────────────┐         │
│               │   main   │─────────▶│  Deploy Canopy 🌿 (auto)    │         │
│               │          │          │  terraform → kamal -d canopy │         │
│               └────┬─────┘          └──────────────────────────────┘         │
│                    │                                                         │
│                    │ кожні ~2 тижні                                          │
│                    ▼                                                         │
│  ┌──────────────────────────────┐   ┌──────────────────────────────┐        │
│  │  GitHub Release (v1.x.0)    │──▶│  Deploy Production 🌲 (auto) │        │
│  │  + автоматичний changelog   │   │  terraform → kamal deploy    │        │
│  └──────────────────────────────┘   └──────────────────────────────┘        │
└──────────────────────────────────────────────────────────────────────────────┘
                                         │                  │
                              ┌──────────┘                  └──────────┐
                              ▼                                        ▼
                 ┌──────────────────┐                    ┌──────────────────┐
                 │  CANOPY SERVER   │                    │   PROD SERVER    │
                 │  🌿 e2-medium    │                    │  🌲 n2-standard-2│
                 │   (GCE)          │                    │   (GCE)          │
                 └────────┬─────────┘                    └────────┬─────────┘
                          │                                       │
              ┌───────────┴───────────┐               ┌───────────┴───────────┐
              ▼                       ▼               ▼                       ▼
    ┌──────────────┐      ┌────────────────┐ ┌──────────────┐     ┌────────────────┐
    │  Cloud SQL   │      │  Memorystore   │ │  Cloud SQL   │     │  Memorystore   │
    │  PostgreSQL  │      │  Redis 7.0     │ │  PostgreSQL  │     │  Redis 7.0     │
    │  16          │      │                │ │  16 (HA)     │     │  (HA)          │
    └──────────────┘      └────────────────┘ └──────────────┘     └────────────────┘
```

### Google Cloud Platform

```
┌─────────────────────────────────────────────────────────────────────┐
│                    GCP Project                                      │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  Artifact Registry (europe-west1)                          │    │
│  │  silken-net — Docker images                                │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │  VPC: silken-net-vpc                                       │    │
│  │                                                            │    │
│  │  Subnet: 10.0.0.0/20                                      │    │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │    │
│  │  │  web-0   │ │ canopy   │ │Cloud SQL │ │  Redis   │     │    │
│  │  │(prod) 🌲 │ │   🌿     │ │(priv IP) │ │(priv IP) │     │    │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │    │
│  │                                                            │    │
│  │  Cloud Router → Cloud NAT (outbound internet)              │    │
│  └────────────────────────────────────────────────────────────┘    │
│                                                                     │
│  IAM: silken-net-deploy (service account, least privilege)          │
│  Terraform State: GCS bucket (silken-net-terraform-state)           │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Akash Network — децентралізований деплой

Окрім Google Cloud, SilkenNet може бути розгорнутий на **[Akash Network](https://akash.network/)** — децентралізованому хмарному маркетплейсі. Це дає:

- 🌐 **Децентралізація** — жодна компанія не контролює інфраструктуру
- 💰 **Економія** — провайдери конкурують за ціною (часто дешевше за GCP/AWS)
- 🛡️ **Стійкість** — додатковий шар розгортання, незалежний від одного хмарного провайдера

### Архітектура

```
┌─────────────────────────────────────────────────────┐
│              Akash Network (Web Layer)               │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  SilkenNet Container (Rails 8.1 + Puma)        │  │
│  │  - HTTP :80 (Rails API + Hotwire)              │  │
│  │  - UDP :5683 (CoAP — IoT телеметрія)           │  │
│  │  - Solid Queue (в Puma, single-node)           │  │
│  │  - 4 vCPU / 8 GB RAM / 50 GB ephemeral        │  │
│  │  - 10 GB persistent storage (Active Storage)   │  │
│  └────────────────┬──────────────┬────────────────┘  │
│                   │              │                    │
└───────────────────┼──────────────┼────────────────────┘
                    │              │
          SSL/Public IP    SSL/Public IP
                    │              │
┌───────────────────┼──────────────┼────────────────────┐
│         Google Cloud Platform (Data Layer)             │
│                   ▼              ▼                     │
│          ┌──────────────┐ ┌────────────────┐          │
│          │  Cloud SQL   │ │  Memorystore   │          │
│          │  PostgreSQL  │ │  Redis 7.0     │          │
│          │  16 (PostGIS)│ │                │          │
│          └──────────────┘ └────────────────┘          │
└───────────────────────────────────────────────────────┘
```

> **Важливо:** База даних залишається на Cloud SQL (GCP). Akash запускає лише web/API шар. Для з'єднання з Cloud SQL потрібен публічний IP з SSL або Cloud SQL Auth Proxy.

### Файли

| Файл | Призначення |
|------|-------------|
| `deploy/akash/deploy.yaml` | Статичний SDL 2.0 — для ручного деплою через `akash` CLI або Akash Console |
| `deploy/akash/deploy.yaml.tpl` | SDL шаблон для Terraform (змінні підставляються автоматично) |
| `terraform/akash/main.tf` | Terraform конфігурація — створює/оновлює/закриває Akash deployment |
| `terraform/akash/variables.tf` | Вхідні змінні (ресурси, секрети, ціна) |
| `terraform/akash/outputs.tf` | Виходи (шлях до SDL, наступні кроки) |
| `terraform/akash/terraform.tfvars.example` | Приклад значень змінних |

### Передумови

1. **Akash CLI** встановлений: [docs.akash.network/guides/cli](https://docs.akash.network/guides/cli)
2. **Гаманець Akash** з AKT токенами для ескроу
3. **Docker образ** доступний з Akash (Docker Hub, GHCR, або публічний Artifact Registry)
4. **Cloud SQL публічний IP** з SSL або Cloud SQL Auth Proxy для зовнішнього доступу

### Деплой через Terraform

```bash
# 1. Підготовка змінних
cd terraform/akash
cp terraform.tfvars.example terraform.tfvars
# Відредагувати terraform.tfvars — заповнити секрети та URL образу

# 2. Ініціалізація та деплой
terraform init
terraform plan
terraform apply

# 3. Після apply — прийняти бід від провайдера
akash query market bid list --owner <your-address> --dseq <DSEQ>
akash tx market lease create --dseq <DSEQ> --provider <provider-address> --from silken-deploy

# 4. Відправити маніфест
akash provider send-manifest terraform/akash/generated-deploy.yaml \
  --dseq <DSEQ> --provider <provider-address> --from silken-deploy

# 5. Перевірити статус
akash provider lease-status --dseq <DSEQ> --provider <provider-address> --from silken-deploy
```

### Деплой через CLI (без Terraform)

```bash
# Відредагувати deploy/akash/deploy.yaml — змінити image та env змінні
akash tx deployment create deploy/akash/deploy.yaml --from silken-deploy --chain-id akashnet-2

# Прийняти бід та відправити маніфест (аналогічно Terraform flow)
```

### Ресурси Akash vs GCP

| Параметр | GCP Production 🌲 | Akash ☁️ | Пояснення |
|----------|-------------------|----------|-----------|
| CPU | 2 vCPU (n2-standard-2) | 4 vCPU | Більше CPU для компенсації варіативності провайдерів |
| RAM | 8 GB | 8 GB | Однаково |
| Disk | 30 GB SSD | 50 GB ephemeral + 10 GB persistent | Більше — контейнер включає все |
| Порти | 80, 443, 5683/udp | 80, 5683/udp | SSL терміновано на рівні Akash proxy |
| DB | Cloud SQL (приватна мережа) | Cloud SQL (публічний IP + SSL) | Потрібна зовнішня доступність |
| Redis | Memorystore (приватна мережа) | Memorystore (публічний IP або тунель) | Аналогічно DB |

### Terraform State

Akash Terraform state зберігається окремо від GCP:

```
silken-net-terraform-state/
├── terraform/state       ← GCP інфраструктура
└── terraform/akash       ← Akash deployment
```

Це розділення запобігає ситуації, коли проблема з Akash впливає на GCP стан, і навпаки.

### Закриття Akash deployment

```bash
# Через Terraform
cd terraform/akash && terraform destroy

# Через CLI
akash tx deployment close --dseq <DSEQ> --from silken-deploy
```
