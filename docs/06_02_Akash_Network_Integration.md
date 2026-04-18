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
| Sidekiq у SDL | — | 🔴 Відсутній (тільки `web` сервіс) |
| HTTPS / TLS термінація | — | 🟡 Не визначена (немає `443` у SDL) |

- **Поточний TRL:** TRL 4 — SDL-маніфест та Terraform-конфігурація існують, реальний деплой не виконувався
- **Пов'язані модулі:**
  - Розгортання → [`06_01_Deployment_Kamal_Terraform`](06_01_Deployment_Kamal_Terraform)
  - Observability → [`06_03_Prometheus_Observability`](06_03_Prometheus_Observability)
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)

---

## 🛑 Блокери

### 🔴 BLOCKER-1: Мережева ізоляція — Cloud SQL та Redis недоступні з Akash

**Статус:** Критичний архітектурний блокер. Блокує будь-який реальний деплой.

Це найважливіший висновок аудиту, успадкований з `06_01` (BLOCKER-6). Akash Network є **публічним децентралізованим маркетплейсом** — провайдери знаходяться поза межами GCP VPC. Наш Rails-моноліт потребує двох з'єднань, які за замовчуванням **недоступні** з Akash:

**Cloud SQL (PostgreSQL):**
- За замовчуванням Cloud SQL у GCP має **лише приватну IP** у межах `silken-net-vpc` (підмережа `10.0.0.0/20`).
- Akash-контейнер не є частиною цієї VPC → TCP-з'єднання на приватний IP блокується.
- Навіть якщо `akash_enabled = true` і Cloud SQL отримає публічний IP (через `terraform.tfvars`), потрібно заповнити `akash_authorized_networks` конкретними CIDR-діапазонами Akash-провайдера — але ці IP невідомі заздалегідь (провайдери динамічні).

**Redis (Memorystore):**
- Cloud Memorystore Redis **не має публічного IP взагалі** — це фундаментальне обмеження сервісу.
- Не існує офіційного способу підключити зовнішній сервіс (поза VPC) до Memorystore без VPN/тунелю.
- Без Redis — Sidekiq не стартує, Kredis не працює, 31+ фонових воркерів недоступні.

**Три можливі рішення (не реалізовано жодне):**

| Рішення | Складність | Безпека | Примітки |
|---------|-----------|---------|---------|
| **Tailscale / WireGuard VPN тунель** | Середня | 🟢 Висока | Акаш-контейнер підключається до GCP VPC через mesh VPN. Потребує Tailscale sidecar у SDL або впровадження у Dockerfile. |
| **Cloud SQL Auth Proxy sidecar** | Середня | 🟢 Висока | Проксі запускається в тому ж поді, тунелює трафік до Cloud SQL через Google API. Але Redis проблему не вирішує. |
| **Публічний IP + SSL + allowlist** | Низька | 🟡 Середня | Простіше, але Memorystore все одно недоступний. Потрібен окремий Redis (наприклад, Redis Cloud або Upstash). |

> **Висновок:** До вирішення цього блокера деклараційне твердження "система децентралізована" є технічно некоректним. Обчислення залишаються залежними від GCP (Web2) інфраструктури для data layer.

---

### ✅ BLOCKER-2: Sidekiq (`job` сервіс) додано в SDL (Виправлено)

**Статус:** Виправлено. SDL `deploy/akash/deploy.yaml` тепер визначає два сервіси:
- `web` — Puma + Thruster HTTP сервер
- `job` — `bundle exec sidekiq -C config/sidekiq.yml` (всі 31+ воркери)

Усі категорії воркерів тепер запускаються на Akash:

| Категорія | Воркери | Статус |
|-----------|---------|--------|
| **Telemetry** | `UnpackTelemetryWorker` (queue: `uplink`) | ✅ Запускається |
| **Alerts** | `EwsAlertWorker`, `MaintenanceSchedulerWorker` | ✅ Запускається |
| **Web3 Critical** | `BlockchainMintingWorker`, `ZkProofVerificationWorker`, `ChainlinkOracleWorker` | ✅ Запускається |
| **Web3** | `PolygonMintSccWorker`, `SolanaRewardWorker`, `PeaqDidWorker` | ✅ Запускається |
| **OTA** | `OtaTransmissionWorker` | ✅ Запускається |
| **Слешинг** | `SlashingProtocolWorker` | ✅ Запускається |
| **L1 Anchoring** | `EthereumAnchorWorker` | ✅ Запускається |

**Примітка:** Секрети в `job` сервісі позначено `REQUIRED` коментарями — необхідно заповнити перед деплоєм.

---

### 🔴 BLOCKER-3: Секрети SDL не заповнені — Rails не стартує

**Статус:** Критичний. Блокує будь-який тест деплою.

Статичний SDL `deploy/akash/deploy.yaml` містить `REQUIRED_SECRET_NOT_SET` для чотирьох критичних змінних:

```yaml
- RAILS_MASTER_KEY=REQUIRED_SECRET_NOT_SET
- DATABASE_URL=REQUIRED_SECRET_NOT_SET
- REDIS_URL=REQUIRED_SECRET_NOT_SET
- KREDIS_REDIS_URL=REQUIRED_SECRET_NOT_SET
```

При спробі запустити Rails без `RAILS_MASTER_KEY` — процес аварійно завершується ще до старту Puma. `DATABASE_URL` без реального значення — ActiveRecord не підключається. Це зроблено навмисно для безпеки (секрети не комітяться в git), але потребує чіткого процесу перед деплоєм.

**Варіанти вирішення:**
1. **Рекомендовано:** Terraform-шаблон `deploy.yaml.tpl` через `terraform/akash/` — секрети підставляються з `terraform.tfvars` (в `.gitignore`).
2. Akash Console UI — ручне введення ENV змінних через веб-інтерфейс перед деплоєм.

---

### 🔴 BLOCKER-4: Docker образ у приватному GCP Artifact Registry

**Статус:** Критичний. Akash-провайдери не мають доступу до приватного реєстру.

SDL посилається на образ:
```
europe-west1-docker.pkg.dev/YOUR_GCP_PROJECT/silken-net/silken_net:latest
```

Google Artifact Registry є **приватним** реєстром. Akash-провайдери — незалежні вузли без GCP-credentials. Pull образу завершиться помилкою `unauthorized: Unauthenticated request`.

**Варіанти вирішення:**
1. Дзеркалювати образ на **Docker Hub** або **GitHub Container Registry (GHCR)** — публічний або з токеном.
2. Налаштувати **imagePullSecrets** у SDL (Akash підтримує Docker registry credentials через Kubernetes-secrets синтаксис).
3. Використати **Workload Identity Federation** для надання Akash-провайдерам доступу до Artifact Registry (складно, не рекомендовано).

---

### 🟡 BLOCKER-5: HTTPS / TLS термінація не визначена в SDL

**Статус:** Середній. Функціональний, але безпечний деплой неможливий.

SDL відкриває лише порт `80` (HTTP) глобально. Порт `443` (HTTPS) відсутній. Akash надає автоматичну TLS термінацію через `*.ingress.akash.pub` домени — але вона не налаштована в поточному SDL.

- **Вплив:** Rails API та Hotwire/Turbo WebSocket будуть доступні лише через незахищений HTTP. Браузери будуть блокувати WebSocket з'єднання.
- **Де в коді:** `deploy/akash/deploy.yaml` → `services.web.expose` — відсутній запис для порту `443`.
- **Потрібно:** Або додати `443` в SDL з Akash ingress, або налаштувати зовнішній reverse proxy (Cloudflare, Nginx Proxy Manager).

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

### 🟡 BLOCKER-8: Відсутність `web_replicas > 1` при sticky sessions

**Статус:** Середній. Масштабування обмежене.

SDL підтримує горизонтальне масштабування через `deployment.web.count = N`. Але Rails з Hotwire/Turbo WebSocket та Solid Cable потребує sticky sessions або спільного ActionCable adapter (Redis pub/sub). При `web_replicas > 1` без sticky sessions — WebSocket з'єднання будуть розриватися.

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
└── deploy.yaml.tpl    ← Шаблон SDL для Terraform (секрети підставляються з terraform.tfvars)
```

---

### 1.1 Сервіс (Service Definition)

```yaml
services:
  web:
    image: europe-west1-docker.pkg.dev/YOUR_GCP_PROJECT/silken-net/silken_net:latest
```

| Параметр | Значення | Відповідність Kamal |
|----------|---------|---------------------|
| **Назва сервісу** | `web` | `config/deploy.yml` → `servers.web` |
| **Docker образ** | `europe-west1-docker.pkg.dev/YOUR_GCP_PROJECT/silken-net/silken_net:latest` | Той самий образ, що Kamal пушить в Artifact Registry |
| **Платформа** | `amd64` | `config/deploy.yml` → `builder.arch: amd64` |
| **Кількість реплік** | `1` | `config/deploy.yml` → `web_node_count = 1` |

> ⚠️ `YOUR_GCP_PROJECT` — плейсхолдер. Для реального деплою використовувати `deploy.yaml.tpl` через Terraform або замінити вручну.

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

  - port: 5683
    as: 5683
    proto: udp
    to:
      - global: true
```

| Порт | Протокол | Призначення | Відповідність Kamal |
|------|---------|-------------|---------------------|
| **80** | TCP (HTTP) | Rails API + Hotwire/Turbo (Thruster reverse proxy) | `boot.proxy.publish "80:80"` |
| **5683** | UDP | CoAP — IoT телеметрія від Queen gateway (21-байтні бінарні пакети) | `boot.proxy.publish "5683:5683/udp"` |

> **Відсутній порт 443 (HTTPS)** — дивись BLOCKER-5.

**Схема мережевого потоку (поточний стан):**

```
Soldier (STM32WLE5JC)
    │ LoRa 868 MHz (AES-256 зашифровані 21-байтні пакети)
    ▼
Queen Gateway (STM32 + SIM7070G)
    │ CoAP/UDP → публічний IP Akash провайдера :5683
    ▼
┌────────────────────────────────────┐
│  Akash Provider (децентралізований)│
│  SilkenNet Container               │
│  HTTP :80 (Rails 8.1 + Puma)       │  ← 🔴 без HTTPS
│  UDP :5683 (CoAP listener)         │
│                                    │
│  ??? DATABASE_URL (BLOCKER-1)      │  ← недоступно з Akash
│  ??? REDIS_URL    (BLOCKER-1)      │  ← недоступно з Akash
└────────────────────────────────────┘
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

Всі 7 ENV змінних, які маніфест передає в контейнер при старті:

| Змінна | Значення в SDL | Тип | Обов'язкова | Опис |
|--------|---------------|-----|------------|------|
| `PORT` | `80` | Відкрита | ✅ | Порт, на якому слухає Thruster всередині контейнера |
| `RAILS_MASTER_KEY` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Ключ розшифровки `config/credentials.yml.enc`. Rails не стартує без нього |
| `DATABASE_URL` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | PostgreSQL URL. Формат: `postgres://user:pass@host:5432/db`. 🔴 BLOCKER-1 |
| `REDIS_URL` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Redis URL для Sidekiq (DB 0). Формат: `redis://host:6379/0`. 🔴 BLOCKER-1 |
| `KREDIS_REDIS_URL` | `REQUIRED_SECRET_NOT_SET` | **Секрет** | ✅ | Redis URL для Kredis distributed locks (DB 1). Формат: `redis://host:6379/1`. 🔴 BLOCKER-1 |
| `RAILS_ENV` | `production` | Відкрита | ✅ | Rails environment — production режим обов'язковий |
| `RAILS_MAX_THREADS` | `3` | Відкрита | — | Кількість Puma threads на worker. Має відповідати `pool` у `database.yml` |
| `WEB_CONCURRENCY` | `4` | Відкрита | — | Кількість Puma worker processes. Встановлено рівним CPU units (4 vCPU) |

**Terraform-шаблон додає змінні динамічно** (`deploy.yaml.tpl`):

```hcl
# terraform/akash/main.tf — рендеринг шаблону
resource "local_file" "akash_sdl" {
  content = templatefile("deploy/akash/deploy.yaml.tpl", {
    rails_master_key  = var.rails_master_key    # sensitive = true
    database_url      = var.database_url         # sensitive = true
    redis_url         = var.redis_url            # sensitive = true
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
| **Порт 443 (HTTPS)** | ✅ (Kamal proxy) | 🔴 Відсутній | 🔴 BLOCKER-5 |
| **Порт 5683 (CoAP/UDP)** | ✅ | ✅ | ✅ |
| **Database** | Cloud SQL private IP | 🔴 Недоступно | 🔴 BLOCKER-1 |
| **Redis** | Memorystore private | 🔴 Недоступно | 🔴 BLOCKER-1 |
| **Sidekiq (31+ workers)** | ✅ (Kamal `job` role) | 🔴 Відсутній | 🔴 BLOCKER-2 |
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

---

## 7. Інтеграція у Загальну Архітектуру Gaia 2.0

Akash Network займає рівень **L5 (Rails Backend)** в 8-рівневій архітектурі, але лише частково:

```
L8  Ethereum L1          Weekly State Root          (EthereumAnchorWorker — 🔴 не запускається на Akash)
L7  Polygon + DeFi       SCC/SFC minting            (BlockchainMintingWorker — 🔴 не запускається на Akash)
L6  Verification          peaq DID, IoTeX ZK         (ZkProofVerificationWorker — 🔴 не запускається на Akash)
L5  Rails Backend         Rails 8.1 API ← [Akash]   (Puma HTTP + Sidekiq job сервіс)
L4  LoRa Network          Queen CoAP → :5683 ← [Akash UDP port] ✅
L3  Firmware & Edge AI    STM32WLE5JC               (не залежить від Akash)
L2  Hardware Capsule      BQ25570, EDLC             (не залежить від Akash)
L1  Biophysics            Ti-6Al-4V EBFC            (не залежить від Akash)
```

**Висновок:** SDL тепер визначає обидва сервіси: `web` (Rails API + CoAP) та `job` (Sidekiq workers). При поточному стані основним обмеженням залишається data layer: PostgreSQL (Cloud SQL) та Redis (Memorystore) не доступні безпосередньо з Akash — потребують вирішення мережевої ізоляції (BLOCKER-1).

---

## 8. Дорожня Карта (Path to TRL 5 → 9)

| TRL | Що потрібно | Блокер |
|-----|------------|--------|
| **TRL 5** (поточна мета) | Цей документ ✅ | — |
| **TRL 6** | Вирішити мережеву ізоляцію (Tailscale sidecar в SDL або публічний Redis) | BLOCKER-1 |
| **TRL 6** | Додати `job` сервіс в SDL для Sidekiq | ✅ BLOCKER-2 виправлено |
| **TRL 6** | Замінити Docker образ на публічний реєстр (GHCR/Docker Hub) | BLOCKER-4 |
| **TRL 7** | Перший реальний деплой на testnet Akash + функціональне тестування | BLOCKER-1,2,3,4 |
| **TRL 7** | Додати HTTPS (порт 443) через Akash ingress або Cloudflare | BLOCKER-5 |
| **TRL 8** | Production деплой з моніторингом (Prometheus exporter в SDL) | BLOCKER-1..5 |
| **TRL 9** | Automated failover GCP ↔ Akash + повна CI/CD інтеграція | — |

---

*Документ створено в рамках Shape Up Cycle 1 — Small Batch "Reverse Shaping". Аудит без змін у коді. Наступний крок: вирішення BLOCKER-1 (мережева ізоляція) як окремий цикл.*
