# 06_02: Akash Network Integration (Децентралізовані Обчислення)

## 🎯 Мета

Зафіксувати **фактичний стан** конфігурації Akash Network. Документ відповідає на три ключові питання:

1. Які **обчислювальні ресурси** (CPU, RAM, Disk) замовляються в Akash SDL?
2. Які **змінні середовища (ENV)** очікує отримати контейнер при деплої?
3. Які **архітектурні блокери** унеможливлюють повноцінне децентралізоване розгортання сьогодні?

---

## ✅ Статус

| Компонент | Файл | Статус |
|-----------|------|--------|
| SDL маніфест (статичний) | `deploy/akash/deploy.yaml` | ✅ Існує, плейсхолдери не заповнені |
| SDL шаблон (Terraform) | `deploy/akash/deploy.yaml.tpl` | ✅ Існує, рендериться через `templatefile()` |
| Terraform конфігурація | `terraform/akash/main.tf` | ✅ Існує, null_resource provisioner через Akash CLI |
| Terraform змінні | `terraform/akash/variables.tf` | ✅ Повністю задокументовані з валідацією |
| Terraform outputs | `terraform/akash/outputs.tf` | ✅ Виводить SDL path та наступні кроки |
| Приклад конфігурації | `terraform/akash/terraform.tfvars.example` | ✅ Існує |
| Реальний деплой (DSEQ) | `terraform/akash/akash-dseq.txt` | 🔴 Відсутній (деплой не проводився) |
| Sidekiq у SDL | `deploy/akash/deploy.yaml` (`job` сервіс) | ✅ Додано (BLOCKER-2 виправлено) |
| Grafana Alloy у SDL | `deploy/akash/deploy.yaml` (`alloy` сервіс) | ✅ Додано (OBS.1 — Grafana Cloud SaaS) |
| Alloy config | `deploy/akash/config.alloy` | ✅ Створено |
| Cloud SQL connectivity | Cloud SQL Auth Proxy в контейнері | ✅ Вирішено (BLOCKER-1) |
| Redis connectivity | Upstash serverless Redis (TLS) | ✅ Вирішено (BLOCKER-1) |
| Ingress Anchor (GCP) | `e2-micro` зі статичним IP | ✅ Замінює важкі web VM |
| Multi-replica ActionCable | Solid Cable (PostgreSQL LISTEN/NOTIFY) | ✅ Вирішено (BLOCKER-8) |
| GHCR image mirror | `.github/workflows/mirror-ghcr.yml` | ✅ Вирішено (BLOCKER-4 виправлено) |
| HTTPS / TLS термінація | `deploy/akash/deploy.yaml` | 🟡 Порт `443` оголошено в SDL; TLS termination через Akash ingress або Cloudflare ще не конфігурована |

- **Поточний TRL:** TRL 6 — SDL повністю конфігурований (`web` + `job` + `alloy`), DB+Redis connectivity вирішені (Cloud SQL Auth Proxy + Upstash TLS), GHCR mirror активний; TRL 7 підтверджується після першого реального деплою на Akash Mainnet
- **Пов'язані модулі:**
  - Розгортання → [`06_01_Deployment_Kamal_Terraform`](06_01_Deployment_Kamal_Terraform)
  - Observability → [`06_03_Prometheus_Observability`](06_03_Prometheus_Observability)
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)

---

## 🛑 Активні Блокери

> Вирішені блокери (BLOCKER-1, 2, 4, 8) перенесені у секцію **"✅ Архів вирішених блокерів"** наприкінці документа.

### 🔴 BLOCKER-3: Секрети SDL не заповнені — Rails не стартує

**Статус:** Критичний. Блокує будь-який тест деплою.

Статичний SDL `deploy/akash/deploy.yaml` містить `REQUIRED_SECRET_NOT_SET` для чотирьох критичних змінних:

```yaml
- RAILS_MASTER_KEY=REQUIRED_SECRET_NOT_SET
- DATABASE_URL=REQUIRED_SECRET_NOT_SET
- REDIS_URL=REQUIRED_SECRET_NOT_SET
- KREDIS_REDIS_URL=REQUIRED_SECRET_NOT_SET
- CLOUD_SQL_INSTANCE_CONNECTION_NAME=REQUIRED_SECRET_NOT_SET
- GCP_SA_KEY_BASE64=REQUIRED_SECRET_NOT_SET
```

При спробі запустити Rails без `RAILS_MASTER_KEY` — процес аварійно завершується ще до старту Puma. `DATABASE_URL` без реального значення — ActiveRecord не підключається. `CLOUD_SQL_INSTANCE_CONNECTION_NAME` та `GCP_SA_KEY_BASE64` необхідні для Cloud SQL Auth Proxy — без них проксі не стартує і `DATABASE_URL=127.0.0.1:5432` не працює. Це зроблено навмисно для безпеки (секрети не комітяться в git), але потребує чіткого процесу перед деплоєм.

**Варіанти вирішення:**
1. **Рекомендовано:** Terraform-шаблон `deploy.yaml.tpl` через `terraform/akash/` — секрети підставляються з `terraform.tfvars` (в `.gitignore`).
2. Akash Console UI — ручне введення ENV змінних через веб-інтерфейс перед деплоєм.

---

### 🟡 BLOCKER-5: TLS термінація не конфігурована

**Статус:** Середній. Порт `443` вже оголошений у SDL — потрібна конфігурація Akash ingress або Cloudflare для TLS термінації.

SDL визначає порти `80`, `443` та `5683`. Порт `443` присутній у `services.web.expose`, проте TLS термінація не підключена:
- **Akash ingress:** надає `*.ingress.akash.pub` субдомени з автоматичним Let's Encrypt — потрібно додати `accept: [*.ingress.akash.pub]` в placement або використати Akash hostname operator.
- **Cloudflare Proxy:** зовнішній варіант — Cloudflare термінує TLS перед Ingress Anchor.

- **Вплив:** Rails API та Hotwire/Turbo WebSocket доступні по HTTP. Браузери блокують WebSocket з'єднання на незахищеному `ws://`.
- **Де в коді:** `deploy/akash/deploy.yaml` → `services.web.expose` — порт `443` є, `accept`-домен не вказаний.
- **Потрібно:** Або налаштувати Akash hostname operator (ingress), або проксіювати через Cloudflare (Ingress Anchor → HTTPS).

---

### 🟡 BLOCKER-6: GCS bucket для Terraform State — потрібно створити вручну

**Статус:** Середній. Chicken-and-egg проблема.

`terraform/akash/main.tf` використовує GCS backend:
```hcl
backend "gcs" {
  bucket = "silken-net-terraform-state"
  prefix = "terraform/akash"
}
```

Цей bucket має існувати **до** першого `terraform init`. Terraform не може його створити автоматично. Деталі вирішення — в `06_01` BLOCKER-2.

---

### 🟡 BLOCKER-7: Akash не має офіційного Terraform provider

**Статус:** Середній. Архітектурне обмеження.

На відміну від GCP (`hashicorp/google`), Akash Network **не має офіційного Terraform provider**. Поточне рішення у `terraform/akash/main.tf` використовує `null_resource` з `local-exec` provisioner, що обгортає Akash CLI команди:

```hcl
resource "null_resource" "akash_deployment" {
  provisioner "local-exec" {
    command = "akash tx deployment create ..."
  }
}
```

**Наслідки:**
- `terraform plan` не показує Akash-ресурси (лише `null_resource`).
- Стан деплою зберігається у локальному файлі `akash-dseq.txt`, а не в Terraform state.
- Потребує встановленого `akash` CLI на машині, де запускається Terraform.
- `terraform destroy` — закриває деплой через `akash tx deployment close`.

---

### 🟢 INFO: Відсутній офіційний Akash auditor address — потрібна актуалізація

**Статус:** Інформаційний.

SDL вказує auditor address `akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24`. Актуальний список аудиторів потрібно перевіряти на:
[https://github.com/akash-network/community/blob/main/sig-providers/auditors.md](https://github.com/akash-network/community/blob/main/sig-providers/auditors.md)

---

## 1. SDL Маніфест — Розбір "Як Є"

**Файл:** `deploy/akash/deploy.yaml`  
**Версія SDL:** `2.0`  
**Метод деплою:** Akash CLI або Terraform (`null_resource` provisioner)

SDL (Stack Definition Language) — це декларативний формат конфігурації Akash Network, аналог `docker-compose.yml` або Kubernetes маніфесту, але для децентралізованого хмарного маркетплейсу.

```
deploy/akash/
├── deploy.yaml        ← Статичний SDL (для ручного деплою через akash CLI або Akash Console)
├── deploy.yaml.tpl    ← Шаблон SDL для Terraform (секрети підставляються з terraform.tfvars)
└── config.alloy       ← Grafana Alloy конфігурація (River format, кодується в Base64 для SDL)
```

---

### 1.1 Сервіс (Service Definition)

```yaml
services:
  web:
    image: ghcr.io/alexey-lukin/silken_net:latest
```

| Параметр | Значення | Відповідність Kamal |
|----------|---------|---------------------|
| **Назва сервісу** | `web` | `config/deploy.yml` → `servers.web` |
| **Docker образ** | `ghcr.io/alexey-lukin/silken_net:latest` | GHCR дзеркало, автоматично синхронізується `.github/workflows/mirror-ghcr.yml` |
| **Платформа** | `amd64` | `config/deploy.yml` → `builder.arch: amd64` |
| **Кількість реплік** | `1` | `config/deploy.yml` → `web_node_count = 1` |

> ✅ GHCR образ — публічний, доступний Akash-провайдерам без credentials. Дзеркалюється автоматично `.github/workflows/mirror-ghcr.yml`. Kamal паралельно пушить у GCP Artifact Registry для GCP деплою.

> **Ingress Anchor:** Важкі GCP web VM замінені легковажним `e2-micro` інстансом зі статичним IP. HAProxy/socat на Ingress Anchor перенаправляє трафік до Akash deployment. Queen шлюзи надсилають CoAP на цей статичний IP, який проксіює до Akash-контейнера.

---

### 1.2 Профіль Обчислень (Compute Profile)

**Розділ SDL:** `profiles.compute.web`

```yaml
profiles:
  compute:
    web:
      resources:
        cpu:
          units: 4
        memory:
          size: 8Gi
        storage:
          - size: 50Gi          # Ephemeral
          - name: data
            size: 10Gi          # Persistent
            attributes:
              persistent: true
              class: beta3
```

| Ресурс | Akash | GCP Production | Пояснення |
|--------|-------|---------------|-----------|
| **CPU** | 4 vCPU | 2 vCPU (n2-standard-2) | +2 vCPU для компенсації варіативності децентралізованих провайдерів |
| **RAM** | 8 GiB | 8 GB | Однаково |
| **Ephemeral Disk** | 50 GiB | 30 GB SSD | Більше — контейнер включає gems, assets, tmp |
| **Persistent Disk** | 10 GiB (`class: beta3`) | Docker volume `silken_net_storage` | Active Storage uploads + Rails logs |

**`class: beta3`** — клас персистентного зберігання Akash Network. Еквівалент SSD-блочного сховища. Перживає перезапуск контейнера на тому ж провайдері, але **не переноситься** при зміні провайдера.

---

### 1.3 Профіль Розміщення (Placement Profile)

**Розділ SDL:** `profiles.placement.silken-dcloud`

```yaml
profiles:
  placement:
    silken-dcloud:
      attributes:
        host: akash
      signedBy:
        anyOf:
          - akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24
      pricing:
        web:
          denom: uakt
          amount: 10000
```

| Параметр | Значення | Пояснення |
|----------|---------|-----------|
| **Назва placement** | `silken-dcloud` | Ідентифікатор стратегії розміщення |
| **Атрибут `host`** | `akash` | Фільтр провайдерів — тільки офіційні Akash вузли |
| **`signedBy.anyOf`** | `akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24` | Адреса аудитора — провайдери, перевірені Akash community |
| **Ціна** | `10000 uAKT / block` | Максимальна ціна за блок (~6 секунд). Провайдери пропонують меншу ціну — система обирає найдешевшого |
| **Валюта** | `uAKT` (micro-AKT) | 1 AKT = 1,000,000 uAKT |

**Розрахунок вартості:**

```
10,000 uAKT/block × 10 blocks/min × 60 min × 24 год × 30 днів
= 432,000,000,000 uAKT/місяць
= 432,000 AKT/місяць   ← ВЕРХНІЙ ЛІМІТ (providers bid lower)
```

> Реальна ціна від провайдерів зазвичай у 10-100x менша від встановленого ліміту. Актуальні ціни: [stats.akash.network](https://stats.akash.network/)

---

### 1.4 Мережева Архітектура (Exposed Ports)

**Розділ SDL:** `services.web.expose`

```yaml
expose:
  - port: 80
    as: 80
    to:
      - global: true

  - port: 443
    as: 443
    to:
      - global: true

  - port: 5683
    as: 5683
    proto: udp
    to:
      - global: true
```

| Порт | Протокол | Призначення | Відповідність Kamal |
|------|---------|-------------|---------------------|
| **80** | TCP (HTTP) | Rails API + Hotwire/Turbo (Thruster reverse proxy) | `boot.proxy.publish "80:80"` |
| **443** | TCP (HTTPS) | TLS-термінований трафік; TLS через Akash ingress або Cloudflare | `boot.proxy.publish "443:443"` |
| **5683** | UDP | CoAP — IoT телеметрія від Queen gateway (21-байтні бінарні пакети) | `boot.proxy.publish "5683:5683/udp"` |

> **Порт 443** оголошений у SDL. TLS термінація потребує налаштування Akash hostname operator або зовнішнього Cloudflare proxy — див. BLOCKER-5.

**Схема мережевого потоку (поточний стан):**

```
Soldier (STM32WLE5JC)
    │ LoRa 868 MHz (AES-256 зашифровані 21-байтні пакети)
    ▼
Queen Gateway (STM32 + SIM7070G)
    │ CoAP/UDP → статичний IP Ingress Anchor :5683
    ▼
┌─────────────────────────────────────────┐
│  GCP Ingress Anchor (e2-micro)          │
│  Статичний IP, HAProxy/socat            │
│  CoAP/UDP :5683 → forward to Akash     │
│  HTTP :80 → forward to Akash           │
└─────────────┬───────────────────────────┘
              │ (forward)
              ▼
┌─────────────────────────────────────────┐
│  Akash Provider (децентралізований)     │
│  SilkenNet Container                    │
│  HTTP :80 (Rails 8.1 + Puma)            │
│  HTTPS :443 (TLS термінація — BLOCKER-5)│
│  UDP :5683 (CoAP listener)              │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Cloud SQL Auth Proxy (in-container)│  │
│  │ 127.0.0.1:5432 → Cloud SQL     │    │
│  │ (HTTPS tunnel, no public IP)    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Grafana Alloy (alloy service)   │    │
│  │ scrapes web:80/metrics (15s)    │    │
│  │ remote_write → Grafana Cloud    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  REDIS_URL = rediss://upstash (TLS) ✅  │
│  DATABASE_URL = 127.0.0.1:5432    ✅    │
└─────────────────────────────────────────┘
                    │
                    │ remote_write (HTTPS)
                    ▼
┌─────────────────────────────────────────┐
│  Grafana Cloud (SaaS)                   │
│  Prometheus + Grafana + Alerting        │
└─────────────────────────────────────────┘
```

---

### 1.5 Персистентне Сховище (Persistent Storage)

**Розділ SDL:** `services.web.params.storage`

```yaml
params:
  storage:
    data:
      mount: /rails/storage
      readOnly: false
```

| Параметр | Значення | Відповідність Kamal |
|----------|---------|---------------------|
| **Назва тому** | `data` | `silken_net_storage` (Docker volume) |
| **Точка монтування** | `/rails/storage` | `config/deploy.yml` → `volumes: "silken_net_storage:/rails/storage"` |
| **Режим** | `readOnly: false` | Read-Write |
| **Призначення** | Active Storage uploads, Rails logs | Ті ж дані, що в Kamal Docker volume |

---

## 2. Змінні Середовища (Environment Variables)

**Розділ SDL:** `services.web.env`  
**Відповідність:** `config/deploy.yml` → `env.secret` + `env.clear`

Всі 10 ENV змінних, які маніфест передає в контейнер при старті:

| Змінна | Значення в SDL | Тип | Обов'язкова | Опис |
|--------|---------------|-----|------------|------|
| `PORT` | `80` | Відкрита | ✅ | Порт, на якому слухає Thruster всередині контейнера |
| `RAILS_MASTER_KEY` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Ключ розшифровки `config/credentials.yml.enc`. Rails не стартує без нього |
| `DATABASE_URL` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | PostgreSQL URL. Формат: `postgres://user:pass@127.0.0.1:5432/db`. Вказує на локальний Cloud SQL Auth Proxy |
| `REDIS_URL` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Redis URL для Sidekiq (DB 0). Формат: `rediss://...@host:port/0` (Upstash, TLS) |
| `KREDIS_REDIS_URL` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Redis URL для Kredis distributed locks (DB 1). Формат: `rediss://...@host:port/1` (Upstash, TLS) |
| `RACK_ATTACK_REDIS_URL` | — (auto-derive) | **Секрет** | — | Redis URL для rate-limiting (DB 2). Опц.: auto-derive з `REDIS_URL` → `/2` |
| `CLOUD_SQL_INSTANCE_CONNECTION_NAME` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Cloud SQL instance connection name (з `terraform output database_connection_name`). Формат: `project:region:instance` |
| `GCP_SA_KEY_BASE64` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Base64-encoded GCP service account JSON key для Cloud SQL Auth Proxy |
| `RAILS_ENV` | `production` | Відкрита | ✅ | Rails environment — production режим обов'язковий |
| `RAILS_MAX_THREADS` | `3` | Відкрита | — | Кількість Puma threads на worker. Має відповідати `pool` у `database.yml` |
| `WEB_CONCURRENCY` | `4` | Відкрита | — | Кількість Puma worker processes. Встановлено рівним CPU units (4 vCPU) |

**Terraform-шаблон додає змінні динамічно** (`deploy.yaml.tpl`):

```hcl
# terraform/akash/main.tf — рендеринг шаблону
resource "local_file" "akash_sdl" {
  content = templatefile("deploy/akash/deploy.yaml.tpl", {
    rails_master_key                    = var.rails_master_key    # sensitive = true
    database_url                        = var.database_url         # sensitive = true
    redis_url                           = var.redis_url            # sensitive = true
    cloud_sql_instance_connection_name  = var.cloud_sql_instance_connection_name  # sensitive = true
    gcp_sa_key_base64                   = var.gcp_sa_key_base64   # sensitive = true
    kredis_redis_url  = var.kredis_redis_url != "" ?
                        var.kredis_redis_url :
                        "${trimsuffix(var.redis_url, "/0")}/1"  # auto-derive DB 1
    # ...
  })
  file_permission = "0600"  # Захист файлу із секретами
}
```

> `kredis_redis_url` автоматично виводиться з `redis_url` (заміна `/0` на `/1`) якщо не вказано явно — це зручна поведінка для єдиного Redis instance.

---

## 3. Terraform Конфігурація

### 3.1 Структура файлів

```
terraform/akash/
├── main.tf                   # SDL rendering + null_resource Akash CLI provisioner
├── variables.tf              # 14 вхідних змінних (мережа, ресурси, ціна, секрети)
├── outputs.tf                # SDL path, SHA-256 hash, deployment notes
└── terraform.tfvars.example  # Приклад заповнення (для копіювання в terraform.tfvars)
```

**Окремий Terraform root module** — `terraform/akash/` є незалежним від основного `terraform/`. Причина: різні lifecycle та credentials:

```
silken-net-terraform-state/ (GCS bucket)
├── terraform/state    ← GCP інфраструктура (VPC, Cloud SQL, Redis, Compute)
└── terraform/akash    ← Akash deployment (SDL, DSEQ)
```

### 3.2 Змінні Terraform (variables.tf)

**Акаш мережа:**

| Змінна | За замовчуванням | Валідація | Опис |
|--------|-----------------|-----------|------|
| `akash_key_name` | — (обов'язкова) | — | Назва ключа в `akash keys list` |
| `akash_chain_id` | `akashnet-2` | — | Chain ID основної мережі Akash |
| `akash_node` | `https://rpc.akashnet.net:443` | — | RPC endpoint Akash ноди |
| `akash_auditor_address` | `akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24` | — | Адреса аудитора для фільтрації провайдерів |

**Ресурси обчислень:**

| Змінна | За замовчуванням | Валідація | Опис |
|--------|-----------------|-----------|------|
| `web_cpu_units` | `4` | 1–32 | CPU units (1 unit = 1 vCPU) |
| `web_memory_size` | `"8Gi"` | — | Оперативна пам'ять |
| `web_storage_size` | `"50Gi"` | — | Ephemeral storage |
| `persistent_storage_size` | `"10Gi"` | — | Persistent storage (Active Storage) |

**Масштабування та ціна:**

| Змінна | За замовчуванням | Валідація | Опис |
|--------|-----------------|-----------|------|
| `web_replicas` | `1` | 1–10 | Кількість реплік сервісу |
| `web_concurrency` | `4` | — | Puma worker processes |
| `rails_max_threads` | `3` | 1–8 | Puma threads per worker (обмежено 8 — GVL thrashing) |
| `max_price_uakt` | `10000` | ≥100 | Максимальна ціна за блок у uAKT |

**Секрети (sensitive = true):**

| Змінна | Валідація |
|--------|-----------|
| `rails_master_key` | — |
| `database_url` | Must start with `postgres://` or `postgresql://` |
| `redis_url` | Must start with `redis://` or `rediss://` |
| `kredis_redis_url` | — (auto-derived if empty) |
| `cloud_sql_instance_connection_name` | Формат: `project:region:instance` |
| `gcp_sa_key_base64` | Base64-encoded GCP service account JSON key |
| `grafana_remote_write_token` | Grafana Cloud API token (metrics:write scope) |
| `prometheus_auth_password` | Basic Auth password для `/metrics` endpoint |

**Observability — Grafana Cloud (OBS.1):**

| Змінна | За замовчуванням | Sensitive | Опис |
|--------|-----------------|-----------|------|
| `grafana_remote_write_url` | — (обов'язкова) | ❌ | Grafana Cloud Prometheus remote_write URL |
| `grafana_remote_write_username` | — (обов'язкова) | ❌ | Grafana Cloud instance ID (числовий) |
| `grafana_remote_write_token` | — (обов'язкова) | ✅ | Grafana Cloud API token |
| `prometheus_auth_user` | — (обов'язкова) | ❌ | Basic Auth username для `/metrics` |
| `prometheus_auth_password` | — (обов'язкова) | ✅ | Basic Auth password для `/metrics` |

### 3.3 Lifecycle Provisioner

`terraform apply` викликає Akash CLI через `null_resource.local-exec`:

```
terraform apply
    │
    ├─► local_file.akash_sdl          (рендер SDL шаблону → generated-deploy.yaml, chmod 0600)
    │
    └─► null_resource.akash_deployment
            │
            ├─ IF akash-dseq.txt EXISTS:
            │    akash tx deployment update <SDL> --dseq <DSEQ> --fees 5000uakt
            │
            └─ IF akash-dseq.txt MISSING:
                 akash tx deployment create <SDL> --fees 5000uakt
                     │
                     └─► Отримати DSEQ з події akash.v1beta3.EventDeploymentCreated
                             └─► Зберегти DSEQ в akash-dseq.txt
```

`terraform destroy` → `akash tx deployment close --dseq <DSEQ>`

---

## 4. Процес Деплою (CLI Commands)

> ⚠️ **ЖОДНОГО РЕАЛЬНОГО ДЕПЛОЮ!** Цей розділ — виключно документація очікуваного процесу. Команди `akash tx deployment create` **не запускались**.

### 4.1 Через Terraform (рекомендовано)

```bash
# 0. Передумови
# - akash CLI встановлений: https://docs.akash.network/guides/cli
# - Гаманець Akash: akash keys add silken-deploy
# - Поповнити гаманець AKT токенами (мінімум ~5 AKT для ескроу)
# - GCS bucket існує: gs://silken-net-terraform-state (див. 06_01 BLOCKER-2)

# 1. Налаштування ENV для Akash CLI
export AKASH_KEY_NAME=silken-deploy
export AKASH_KEYRING_BACKEND=os
export AKASH_ACCOUNT_ADDRESS=$(akash keys show silken-deploy -a)
export AKASH_NODE=https://rpc.akashnet.net:443
export AKASH_CHAIN_ID=akashnet-2

# 2. Підготовка Terraform
cd terraform/akash
cp terraform.tfvars.example terraform.tfvars
# Заповнити terraform.tfvars (НЕ комітити в git!)

# 3. Ініціалізація та деплой
terraform init
terraform plan
terraform apply

# 4. Прийняти бід від провайдера (після apply)
DSEQ=$(cat akash-dseq.txt)
akash query market bid list --owner $AKASH_ACCOUNT_ADDRESS --dseq $DSEQ
akash tx market lease create \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME \
  --fees 5000uakt

# 5. Відправити маніфест провайдеру
akash provider send-manifest generated-deploy.yaml \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME

# 6. Перевірити статус
akash provider lease-status \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME

# 7. Переглянути логи
akash provider lease-logs \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME
```

### 4.2 Через Akash CLI (без Terraform)

```bash
# Відредагувати deploy/akash/deploy.yaml — замінити плейсхолдери
# (DANGER: ризик зберегти секрети в git)

akash tx deployment create deploy/akash/deploy.yaml \
  --from silken-deploy \
  --chain-id akashnet-2 \
  --fees 5000uakt \
  --gas auto \
  --yes

# Далі — аналогічно крокам 4-7 вище
```

### 4.3 Закриття деплою

```bash
# Через Terraform (рекомендовано)
cd terraform/akash && terraform destroy

# Через CLI
akash tx deployment close \
  --dseq $(cat terraform/akash/akash-dseq.txt) \
  --from silken-deploy \
  --fees 5000uakt
```

---

## 5. Порівняння: Akash vs GCP Production

| Параметр | GCP Production 🌲 | Akash ☁️ | Статус |
|----------|-------------------|----------|--------|
| **CPU** | 2 vCPU (n2-standard-2) | 4 vCPU | ✅ Більше для компенсації |
| **RAM** | 8 GB | 8 GiB | ✅ Однаково |
| **Ephemeral Disk** | 30 GB SSD | 50 GiB | ✅ Більше |
| **Persistent Disk** | Docker volume | 10 GiB (`beta3`) | ✅ Аналогічно |
| **Порт 80 (HTTP)** | ✅ | ✅ | ✅ |
| **Порт 443 (HTTPS)** | ✅ (Kamal proxy) | 🟡 В SDL, TLS термінація не конфігурована | 🟡 BLOCKER-5 |
| **Порт 5683 (CoAP/UDP)** | ✅ | ✅ (через Ingress Anchor) | ✅ |
| **Database** | Cloud SQL private IP | ✅ Cloud SQL Auth Proxy (in-container) | ✅ BLOCKER-1 вирішено |
| **Redis** | Memorystore private | ✅ Upstash serverless Redis (TLS) | ✅ BLOCKER-1 вирішено |
| **Sidekiq (31+ workers)** | ✅ (Kamal `job` role) | ✅ (`job` сервіс в SDL) | ✅ BLOCKER-2 вирішено |
| **ActionCable (multi-replica)** | Solid Cable (PostgreSQL) | ✅ Solid Cable (Cloud SQL) | ✅ BLOCKER-8 вирішено |
| **Управління** | Kamal + Terraform GCP | Akash CLI + Terraform | ✅ |
| **Цінова модель** | Фіксована (GCP billing) | Аукціон (uAKT/block) | ✅ Потенційно дешевше |
| **Відмовостійкість** | GCP SLA + Shielded VM | Залежить від провайдера | 🟡 Без SLA гарантій |
| **Цензурна стійкість** | ❌ (Web2, GCP control) | ✅ (децентралізовано) | Мета архітектури |

---

## 6. Відповідність Kamal → Akash

Mapping між конфігурацією Kamal (`config/deploy.yml`) та SDL (`deploy/akash/deploy.yaml`):

| Kamal (config/deploy.yml) | Akash SDL (deploy/akash/deploy.yaml) |
|--------------------------|--------------------------------------|
| `servers.web` | `services.web` |
| `image` (Artifact Registry) | `services.web.image` |
| `boot.proxy.publish "80:80"` | `expose[0]: port: 80, global: true` |
| `boot.proxy.publish "5683:5683/udp"` | `expose[1]: port: 5683, proto: udp, global: true` |
| `env.secret RAILS_MASTER_KEY` | `env: RAILS_MASTER_KEY=...` |
| `env.secret DATABASE_URL` | `env: DATABASE_URL=...` |
| `env.secret REDIS_URL` | `env: REDIS_URL=...` |
| `env.secret KREDIS_REDIS_URL` | `env: KREDIS_REDIS_URL=...` |
| `env.clear RAILS_ENV=production` | `env: RAILS_ENV=production` |
| `env.clear RAILS_MAX_THREADS=3` | `env: RAILS_MAX_THREADS=3` |
| `volumes: silken_net_storage:/rails/storage` | `params.storage.data.mount: /rails/storage` |
| `builder.arch: amd64` | `profiles.compute.web.resources.cpu.units: 4` |
| `servers.job` (Sidekiq) | ✅ Додано (BLOCKER-2 виправлено) |
| — (Grafana Alloy sidecar) | ✅ `alloy` сервіс (OBS.1 — Grafana Cloud) |

---

## 7. Інтеграція у Загальну Архітектуру Gaia 2.0

Akash Network займає рівень **L5 (Rails Backend)** в 8-рівневій архітектурі. З вирішенням BLOCKER-1 (DB + Redis connectivity) всі рівні L5–L8 тепер працюють на Akash:

```
L8  Ethereum L1          Weekly State Root          (EthereumAnchorWorker — ✅ запускається на Akash через Sidekiq job сервіс)
L7  Polygon + DeFi       SCC/SFC minting            (BlockchainMintingWorker — ✅ запускається на Akash через Sidekiq job сервіс)
L6  Verification          peaq DID, IoTeX ZK         (ZkProofVerificationWorker — ✅ запускається на Akash через Sidekiq job сервіс)
L5  Rails Backend         Rails 8.1 API ← [Akash]   (Puma HTTP + Sidekiq job сервіс)
L4  LoRa Network          Queen CoAP → Ingress Anchor → :5683 ← [Akash UDP port] ✅
L3  Firmware & Edge AI    STM32WLE5JC               (не залежить від Akash)
L2  Hardware Capsule      BQ25570, EDLC             (не залежить від Akash)
L1  Biophysics            Ti-6Al-4V EBFC            (не залежить від Akash)
```

**Висновок:** SDL визначає три сервіси: `web` (Rails API + CoAP), `job` (Sidekiq workers), та `alloy` (Grafana Alloy → Grafana Cloud). Cloud SQL Auth Proxy (in-container) забезпечує доступ до PostgreSQL через HTTPS тунель, Upstash serverless Redis (TLS) замінює GCP Memorystore. `job` сервіс використовує entrypoint (`/rails/bin/docker-entrypoint bundle exec sidekiq ...`) для запуску Cloud SQL Proxy і для Sidekiq. `alloy` сервіс скрейпить `/metrics` endpoint `web` сервісу кожні 15 секунд та пушить метрики у Grafana Cloud через remote_write — вирішуючи BLOCKER'и спостережуваності (06_03). Ingress Anchor (`e2-micro` зі статичним IP) проксіює CoAP-трафік від Queens до Akash. Multi-replica ActionCable працює без sticky sessions завдяки Solid Cable adapter — всі репліки `web` підключені до спільної Cloud SQL БД `silken_net_production_cable`, PostgreSQL `LISTEN/NOTIFY` забезпечує крос-реплікову доставку Turbo Stream broadcasts.

---

## 8. Дорожня Карта (Path to TRL 6 → 9)

| TRL | Що потрібно | Статус |
|-----|------------|--------|
| **TRL 6** ✅ | SDL-маніфест (`web` + `job` + `alloy`), DB+Redis connectivity, GHCR mirror | ✅ Всі передумови виконані |
| **TRL 6** ✅ | Вирішити мережеву ізоляцію (Cloud SQL + Redis) | ✅ BLOCKER-1 — Cloud SQL Auth Proxy + Upstash |
| **TRL 6** ✅ | Додати `job` сервіс в SDL для Sidekiq | ✅ BLOCKER-2 виправлено |
| **TRL 6** ✅ | Замінити Docker образ на публічний реєстр (GHCR) | ✅ BLOCKER-4 виправлено (`mirror-ghcr.yml`) |
| **TRL 7** 🎯 | Перший реальний деплой на Akash Mainnet + функціональне тестування CoAP | 🔴 BLOCKER-3 (секрети — заповнити `terraform.tfvars`) |
| **TRL 7** 🎯 | Налаштувати TLS через Akash ingress hostname operator або Cloudflare | 🟡 BLOCKER-5 (порт 443 у SDL, TLS не активована) |
| **TRL 7** 🎯 | GCS bucket для Terraform state | 🟡 BLOCKER-6 (створити вручну перед `terraform init`) |
| **TRL 8** | Production деплой з Grafana Cloud метриками + alerting | Потребує TRL 7 + GRAFANA_* secrets |
| **TRL 9** | Automated failover GCP ↔ Akash + повна CI/CD інтеграція | — |

---

## ✅ Архів вирішених блокерів

> Деталі реалізованих рішень для довідки.

### ✅ BLOCKER-1: Мережева ізоляція — Cloud SQL та Redis (Вирішено)

- **Cloud SQL:** Cloud SQL Auth Proxy запускається в Docker-контейнері (через `bin/docker-entrypoint`). Тунелює трафік через Google Cloud API (HTTPS) — публічний IP на Cloud SQL не потрібен (`ipv4_enabled=false`). `DATABASE_URL` вказує на `127.0.0.1:5432`.
- **Redis:** GCP Memorystore замінено на **Upstash** serverless Redis з публічними TLS-ендпоінтами (`rediss://`). Free tier достатній до TRL 8.

### ✅ BLOCKER-2: Sidekiq `job` сервіс в SDL (Вирішено)

SDL `deploy/akash/deploy.yaml` визначає три сервіси: `web` (Puma + Thruster), `job` (Sidekiq, 9 черг, strict priority), `alloy` (Grafana Alloy → Grafana Cloud). Всі 36+ воркерів (telemetry, Web3, slashing, OTA, L1 anchoring) запускаються на Akash.

### ✅ BLOCKER-4: Docker образ — GHCR mirror (Вирішено)

`.github/workflows/mirror-ghcr.yml` автоматично збирає та пушить образ `ghcr.io/alexey-lukin/silken_net:latest` (public) після CI на `main` та на GitHub Release. SDL та Terraform variable `docker_image` посилаються на GHCR. Kamal + GCP Artifact Registry залишаються для GCP деплою.

### ✅ BLOCKER-8: Multi-replica ActionCable (Вирішено — Solid Cable)

**Solid Cable** (`adapter: solid_cable`, `config/cable.yml`) — нативний Rails 8.1 adapter, PostgreSQL LISTEN/NOTIFY як pub/sub брокер. Виділена БД `silken_net_production_cable` (без навантаження на основну). При `deployment.web.count = N` всі репліки отримують broadcasts через LISTEN/NOTIFY < 1 мс. Sticky sessions не потрібні.
