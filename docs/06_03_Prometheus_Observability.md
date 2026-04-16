# 06_03: Prometheus Observability (Метрики, Grafana, Alerting)

**Модуль:** 06_03 — Prometheus Observability, Sentry & Alerting
**Пов'язані модулі:** [06_01 Deployment Kamal & Terraform](06_01_Deployment_Kamal_Terraform) · [06_02 Akash Network Integration](06_02_Akash_Network_Integration) · [04_02 Business Logic & Services](04_02_Business_Logic_and_Services)
**Поточний TRL:** 4 (Бібліотеки встановлені, кастомні метрики частково прописані в коді, Prometheus Server та Grafana відсутні в інфраструктурі, SSOT відсутня)
**Цільовий TRL:** 5 (Повна прозорість моніторингу — реєстр метрик, аналіз Sentry, фіксація інфраструктурних прогалин)
**Статус Аудиту:** Reverse Shaping завершено — документ синхронізовано з кодбейсом станом на 2026-03-23

---

## 🎯 Мета (Objective)

Провести "Reverse Shaping" стеку спостережуваності (Observability). Зафіксувати, які інструменти збору помилок (Sentry) та метрик (Prometheus) **реально імплементовані** в коді, які кастомні бізнес-метрики збираються, і чи існує конфігурація для їх збору та візуалізації (Prometheus Server, Grafana).

Документ чітко розділяє три шари спостережуваності:

| Шар | Інструмент | Статус |
|-----|------------|--------|
| **APM / Error Tracking** | Sentry | ✅ Реалізовано в коді |
| **Time-series / Metrics** | Prometheus (`prometheus-client`) | ✅ `/metrics` endpoint існує, ❌ Prometheus Server відсутній |
| **Logs** | GCP Cloud Logging (WARNING+) | ✅ Часткова конфігурація (GCP Logging API) |
| **Visualization** | Grafana | ❌ **Відсутня в інфраструктурі** |
| **Alerting** | Alertmanager | ❌ **Відсутній в інфраструктурі** |

> **⚠️ SSOT Sync:** Цей документ є результатом аудиту без жодних змін у коді (Shape Up: Rabbit Holes / No Gos). Жодних нових конфігів для Grafana чи Prometheus Server не створювалось. **Цей документ і є встановленням SSOT для модуля 06_03.**

---

## 🛑 Блокери (Blockers / Needs Action)

> Цей розділ є критично важливим. Без вирішення цих пунктів система летить "наосліп" у Mainnet.

### 🔴 BLOCKER-1: Prometheus Server не розгорнутий — `/metrics` нікому скрейпити

**Статус:** Критичний. Блокує збір будь-яких метрик.

Rails-застосунок **вже** генерує метрики та виставляє їх через `/metrics` endpoint (захищений IP allowlist). Але результат аудиту Terraform-конфігурацій (`terraform/main.tf`, `terraform/compute.tf`, `terraform/database.tf`, `terraform/vpc.tf`, `terraform/redis.tf`, `terraform/iam.tf`, `terraform/akash/main.tf`) та конфігів Kamal (`config/deploy.yml`, `config/deploy.canopy.yml`) однозначний:

**Prometheus Server** — ні у вигляді GCP Compute Instance, ні як Docker-контейнер в Kamal, ні як ресурс в Akash SDL — **ніде не визначений**.

Поточний стан:
```
Rails /metrics ──→ [НІКУДИ] — немає Prometheus Server, який би скрейпив endpoint
```

Очікуваний стан:
```
Prometheus Server ──scrapes──→ Rails :3000/metrics (кожні 15s)
      │
      └──→ Grafana (PromQL дашборди)
      └──→ Alertmanager (правила алертів)
```

**Примітка щодо GCP Cloud Monitoring:** Terraform вмикає `monitoring.googleapis.com` API та надає сервісному акаунту роль `roles/monitoring.metricWriter`. Однак це — нативний GCP Cloud Monitoring (Stackdriver) для системних метрик (CPU, RAM, Redis memory), а **не** Prometheus. Кастомні бізнес-метрики (`silkennet_scc_minted_total`, `silkennet_rpc_errors_total` тощо) наразі **не налаштовані для надсилання** до Cloud Monitoring (потребуватиме додаткового Prometheus → Cloud Monitoring exporter або OpenTelemetry Collector).

**Дія (варіанти вирішення, поза scope цього документа):**
1. Додати Prometheus Server як Kamal accessory (Docker-контейнер) в `config/deploy.yml`.
2. Розгорнути Prometheus + Grafana як GCP Compute Instance через Terraform.
3. Використати SaaS-рішення (Grafana Cloud, Prometheus Remote Write до managed endpoint).

---

### 🔴 BLOCKER-2: Grafana відсутня — метрики є, але переглядати нема де

**Статус:** Критичний. Блокує візуалізацію та операційний моніторинг.

Пошук по всіх інфраструктурних файлах (`terraform/**/*.tf`, `config/deploy.yml`, `config/deploy.canopy.yml`, `deploy/akash/deploy.yaml`) не виявив жодної згадки про Grafana.

Повний реєстр зібраних метрик (7 метрик, деталі в розділі 3) залишається **невидимим** для команди без Grafana-дашбордів. У системі, що керує реальними фінансовими активами на-чейні, відсутність dashboards — це відсутність контролю.

**Критичні сценарії без Grafana:**

| Подія | Метрика | Наслідок без дашборду |
|-------|---------|----------------------|
| Alchemy RPC починає відхиляти запити | `silkennet_rpc_errors_total{network="polygon"}` | Зростання не видно — мінтинг SCC зупиняється мовчки |
| Sidekiq `web3_critical` черга переповнюється | `silkennet_web3_queue_size{queue="web3_critical"}` | Підтвердження транзакцій затримуються — інвестори не отримують токени |
| Атака підробленими DID | `silkennet_telemetry_fraud_detected_total` | Спайк непомітний — незаконний мінтинг можливий |
| Слешинг кластерів | `silkennet_scc_slashed_total` | Масове спалювання токенів без сповіщення |

**Дія:** Після розгортання Prometheus Server (BLOCKER-1) — розгорнути Grafana та імпортувати дашборди.

---

### 🔴 BLOCKER-3: Alertmanager не налаштований — Web3-оракули падають без сповіщень

**Статус:** Критичний. Блокує отримання статусу "Production-Ready".

"Сліпий" політ у Mainnet без автоматичних алертів на падіння Chainlink Oracle, зростання `rpc_errors_total` або зупинку телеметрії (`telemetry_processed_total` = 0 за 10 хвилин) — це критичний операційний ризик.

Alertmanager — частина стандартного Prometheus-стеку. Жодної конфігурації Alertmanager (правила алертів `*.rules.yml`, `alertmanager.yml`, Slack/PagerDuty webhook) не виявлено в репозиторії.

**Мінімальні алерти, що мають бути налаштовані (поза scope):**

```yaml
# Приклад правил (не реалізовано — лише довідка)
- alert: Web3QueueCritical
  expr: silkennet_web3_queue_size{queue="web3_critical"} > 500
  for: 5m
  annotations:
    summary: "Критична Web3 черга переповнена — мінтинг SCC заблокований"

- alert: TelemetryIngestDown
  expr: rate(silkennet_telemetry_processed_total[10m]) == 0
  for: 10m
  annotations:
    summary: "Телеметрія з дерев зупинилась — CoAP/LoRa канал недоступний"

- alert: RpcErrorSpike
  expr: rate(silkennet_rpc_errors_total[5m]) > 10
  for: 2m
  annotations:
    summary: "RPC помилки: {{ $labels.network }} / {{ $labels.error_type }}"
```

---

### 🟡 BLOCKER-4: `SENTRY_DSN` відсутній у `.kamal/secrets` — Sentry інертний у Production

**Статус:** Середній. Sentry налаштований, але не підключений.

`.kamal/secrets` містить: `RAILS_MASTER_KEY`, `GCP_ARTIFACT_REGISTRY_KEY`, `DATABASE_URL`, `REDIS_URL`. Але **`SENTRY_DSN` відсутній**.

Ініціалізатор `config/initializers/sentry.rb` використовує `ENV["SENTRY_DSN"]`:
```ruby
config.dsn = ENV["SENTRY_DSN"]
```

Якщо `SENTRY_DSN` не задано — Sentry не надсилає жодних подій (за документацією `sentry-ruby`, SDK є інертним без DSN). Весь Production-трафік — помилки Sidekiq, збої Web3 — не потрапляє до Sentry.

**Дія:**
1. Створити проєкт у [sentry.io](https://sentry.io) (або self-hosted Sentry).
2. Отримати DSN.
3. Додати до `.kamal/secrets`: `SENTRY_DSN=$SENTRY_DSN`
4. Додати до `config/deploy.yml` → `env.secret`: `- SENTRY_DSN`
5. Зберегти в GitHub Secret `SENTRY_DSN`.

---

### 🟡 BLOCKER-5: Лише 2 з 9 Sidekiq черг моніторяться Prometheus

**Статус:** Середній. Архітектурна прогалина в охопленні метрик.

`PrometheusCollector` middleware (функція `refresh_sidekiq_gauges`) моніторить лише дві черги:
```ruby
web3_queues = %w[web3 web3_critical]
```

З 9 пріоритетних черг **7 залишаються поза Prometheus-моніторингом**:

| Черга | Пріоритет | Воркери | Статус |
|-------|-----------|---------|--------|
| `uplink` | 9 (найвищий) | `UnpackTelemetryWorker` | ❌ Не моніториться |
| `alerts` | 8 | `EwsAlertWorker` | ❌ Не моніториться |
| `critical` | 7 | `SlashingProtocolWorker` | ❌ Не моніториться |
| `downlink` | 6 | `OtaTransmissionWorker` | ❌ Не моніториться |
| `default` | 5 | Агрегація, health checks | ❌ Не моніториться |
| `web3_critical` | 4 | Мінтинг, Oracle, ZK | ✅ Моніториться |
| `web3` | 3 | Celo, Solana, peaq | ✅ Моніториться |
| `web3_low` | 2 | L1 anchoring, KlimaDAO | ❌ Не моніториться |
| `low` | 1 | Audit logging, analytics | ❌ Не моніториться |

**Найкритичніша прогалина:** черга `uplink` (пріоритет 9 — обробка 21-байтових CoAP/UDP телеметрія-пакетів від "солдатів" через `UnpackTelemetryWorker`) має **найвищий пріоритет** у системі, але її стан невидимий для Prometheus. Переповнення `uplink` означає, що дані з дерев не обробляються — але жодного алерту немає.

**Дія (поза scope — аудит тільки):** Розширити `refresh_sidekiq_gauges` для всіх 9 черг або реалізувати через `yabeda-sidekiq` при майбутньому рефакторингу.

---

## ✅ Статус Імплементації

| Компонент | Файл | Статус |
|-----------|------|--------|
| `sentry-ruby` gem | `Gemfile` | ✅ 6.5.0 |
| `sentry-rails` gem | `Gemfile` | ✅ 6.5.0 (auto-instruments Rails) |
| `sentry-sidekiq` gem | `Gemfile` | ✅ 6.5.0 (auto-instruments Sidekiq) |
| `prometheus-client` gem | `Gemfile` | ✅ 4.2.5 |
| Sentry initializer | `config/initializers/sentry.rb` | ✅ Повністю налаштований |
| Prometheus initializer | `config/initializers/prometheus.rb` | ✅ 5 Counters + 2 Gauges визначені |
| `/metrics` endpoint | `app/middleware/prometheus_collector.rb` | ✅ Реалізований (IP allowlist + Basic Auth) |
| Middleware registration | `config/application.rb` | ✅ `config.middleware.use PrometheusCollector` |
| `SCC_MINTED_TOTAL` instrumentation | `app/services/blockchain_minting_service.rb` | ✅ Реалізовано |
| `SCC_SLASHED_TOTAL` instrumentation | `app/services/blockchain_burning_service.rb` | ✅ Реалізовано |
| `RPC_ERRORS_TOTAL` instrumentation | `app/workers/application_web3_worker.rb` | ✅ Реалізовано (4 точки) |
| `TELEMETRY_PROCESSED_TOTAL` instrumentation | `app/services/telemetry_unpacker_service.rb` | ✅ Реалізовано |
| `TELEMETRY_FRAUD_DETECTED_TOTAL` instrumentation | `app/services/telemetry_unpacker_service.rb` | ✅ Реалізовано (2 точки) |
| Sentry context у workers | `app/workers/unpack_telemetry_worker.rb`, `app/workers/gateway_telemetry_worker.rb` | ✅ `Sentry.set_tags()` |
| Prometheus Server | `terraform/**/*.tf`, `config/deploy.yml` | 🔴 **ВІДСУТНІЙ** |
| Grafana | `terraform/**/*.tf`, `config/deploy.yml` | 🔴 **ВІДСУТНЯ** |
| Alertmanager | `terraform/**/*.tf` | 🔴 **ВІДСУТНІЙ** |
| `SENTRY_DSN` у Kamal secrets | `.kamal/secrets` | 🟡 Відсутній |
| Prometheus scrape config | — | 🔴 Відсутній |
| Grafana dashboards | — | 🔴 Відсутні |

---

## 🛡️ Частина I: APM — Sentry Error Tracking

### 1.1 Gem-залежності та версії

```ruby
# Gemfile
gem "sentry-ruby"    # 6.5.0 — core SDK
gem "sentry-rails"   # 6.5.0 — auto-instruments Rails (exceptions, breadcrumbs, performance)
gem "sentry-sidekiq" # 6.5.0 — auto-instruments Sidekiq
```

### 1.2 Налаштування (config/initializers/sentry.rb)

| Параметр | Значення | Пояснення |
|----------|----------|-----------|
| `config.dsn` | `ENV["SENTRY_DSN"]` | Інертний без DSN (dev/test) |
| `config.environment` | `Rails.env` | Всі environment покриваються |
| `config.release` | `ENV["RELEASE_VERSION"]` | Версія деплою для tracking регресій |
| `config.send_default_pii` | `false` | Zero-Trust: PII не надсилається |
| `config.traces_sample_rate` | `0.001` (0.1%) | Контроль бюджету APM при мільярдах подій |
| `config.background_worker_threads` | `2` | Асинхронна передача — не блокує Puma/Sidekiq |
| `config.max_breadcrumbs` | `30` | Обмеження розміру payload |
| `config.breadcrumbs_logger` | `[:active_support_logger, :http_logger]` | Контекст Rails + HTTP |

**Фільтрація секретів (`before_send`):**
```ruby
scrub_patterns = /aes_key|wallet_private_key|mnemonic|private_key|binary_payload|secret_key/i
```
AES-ключі, мнемоніки та бінарні payload автоматично замінюються на `[FILTERED]`.

### 1.3 Інтеграція з Sidekiq (`sentry-sidekiq`)

Gem `sentry-sidekiq` автоматично додає Sentry middleware до Sidekiq server middleware chain. Це означає:
- Будь-який **необроблений виняток** у будь-якому з 31+ воркерів автоматично надсилається до Sentry.
- Кожна Sidekiq-задача отримує власну транзакцію Sentry з метаданими: `queue`, `class`, `jid`, `args`.
- Повторні спроби (retries) відстежуються як окремі події.

**Активна Sentry-інструментація у воркерах:**

| Воркер | Файл | Тег |
|--------|------|-----|
| `UnpackTelemetryWorker` | `app/workers/unpack_telemetry_worker.rb:21` | `Sentry.set_tags(gateway_uid: ...)` |
| `GatewayTelemetryWorker` | `app/workers/gateway_telemetry_worker.rb:17` | `Sentry.set_tags(queen_uid: ...)` |

Ці теги дозволяють в Sentry UI фільтрувати помилки за конкретним gateway або queen UID.

### 1.4 Виключені виключення (Zero Noise Policy)

**34 класи виключень** виключені зі Sentry, щоб уникнути alert fatigue:

| Категорія | Приклади |
|-----------|----------|
| Rails/Rack (очікувані HTTP) | `RoutingError`, `RecordNotFound`, `ParameterMissing` |
| Auth/Authorization | `Pundit::NotAuthorizedError` |
| CoAP/IoT transient | `CoapClient::Error`, `CoapClient::NetworkError` |
| Web3 transient (Sidekiq retries обробляють) | `HTTPX::TimeoutError`, `Errno::ECONNREFUSED` |
| Sidekiq Enterprise rate limiting | `Sidekiq::Limiter::OverLimit` |
| Domain-specific handled errors | `Peaq::DidRegistryService::RegistrationError`, `Chainlink::OracleDispatchService::DispatchError`, та ін. |

**Принцип:** Sentry отримує лише **невідомі збої** (справжні 5xx), а не очікувані операційні виключення.

### 1.5 Покриття Environments

| Environment | Поведінка |
|-------------|-----------|
| `development` | Інертний (немає `SENTRY_DSN`) |
| `test` | Інертний (немає `SENTRY_DSN`) |
| `canopy` (staging) | Активний при наявності `SENTRY_DSN` |
| `production` | Активний при наявності `SENTRY_DSN` (**🟡 BLOCKER-4: відсутній у `.kamal/secrets`**) |

---

## 📊 Частина II: Time-Series — Prometheus Metrics

### 2.1 Gem та реєстр

```ruby
# Gemfile
gem "prometheus-client"  # 4.2.5 — офіційний Prometheus Ruby client

# config/initializers/prometheus.rb
require "prometheus/client"
module SilkenNet
  module Metrics
    REGISTRY = Prometheus::Client::Registry.new
    # ... всі метрики визначаються тут
  end
end
```

### 2.2 Endpoint `/metrics`

**Реалізація:** `app/middleware/prometheus_collector.rb`
**Реєстрація:** `config/application.rb` → `config.middleware.use PrometheusCollector`
**Формат:** Prometheus text format (Content-Type: `text/plain; version=0.0.4`)

**Безпека (двошарова):**

```
Запит → /metrics
    │
    ├─ IP Allowlist → 403 Forbidden (якщо публічна IP)
    │   ✓ 127.0.0.0/8 (localhost)
    │   ✓ 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 (RFC 1918)
    │   ✓ fc00::/7 (RFC 4193 IPv6)
    │   ✓ PROMETHEUS_ALLOWED_IPS env (custom CIDR список)
    │
    └─ HTTP Basic Auth → 403 Forbidden (якщо credentials невірні)
        Лише при наявності PROMETHEUS_AUTH_USER + PROMETHEUS_AUTH_PASSWORD
```

### 2.3 Реєстр кастомних бізнес-метрик (повний)

#### Counters (монотонно зростаючі)

| Metric Name | Ruby Constant | Labels | Де інкрементується | Бізнес-значення |
|-------------|--------------|--------|-------------------|-----------------|
| `silkennet_scc_minted_total` | `SilkenNet::Metrics::SCC_MINTED_TOTAL` | `token_type` (carbon_coin, forest_coin) | `BlockchainMintingService` (рядок 162–163) | Кожен успішний мінт SCC/SFC в Polygon mempool |
| `silkennet_scc_slashed_total` | `SilkenNet::Metrics::SCC_SLASHED_TOTAL` | — | `BlockchainBurningService` (рядок 96–97) | Кумулятивна **сума спалених токенів** (increment `by: burn_amount`, не лічильник подій) |
| `silkennet_rpc_errors_total` | `SilkenNet::Metrics::RPC_ERRORS_TOTAL` | `network`, `error_type` (timeout, connection) | `ApplicationWeb3Worker` (4 точки: рядки 76, 80, 84, 88) | Кожна RPC-помилка по всіх 12 блокчейн-мережах |
| `silkennet_telemetry_processed_total` | `SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL` | — | `TelemetryUnpackerService` (рядок 154) | Кожен успішно оброблений telemetry chunk |
| `silkennet_telemetry_fraud_detected_total` | `SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL` | — | `TelemetryUnpackerService` (рядки 79, 87) | Відхилені пакети (sensor noise, unknown DID, tamper) |

#### Gauges (поточне значення — оновлюються при кожному scrape)

| Metric Name | Ruby Constant | Labels | Де оновлюється | Бізнес-значення |
|-------------|--------------|--------|----------------|-----------------|
| `silkennet_web3_queue_size` | `SilkenNet::Metrics::WEB3_QUEUE_SIZE` | `queue` (web3, web3_critical) | `PrometheusCollector#refresh_sidekiq_gauges` | Поточна кількість задач у Sidekiq Web3 чергах |
| `silkennet_web3_queue_latency_seconds` | `SilkenNet::Metrics::WEB3_QUEUE_LATENCY` | `queue` (web3, web3_critical) | `PrometheusCollector#refresh_sidekiq_gauges` | Вік найстарішої задачі в черзі (секунди) |

**Підсумок реєстру: 5 Counters + 2 Gauges = 7 кастомних метрик.**

### 2.4 Відсутні метрики (прогалини аудиту)

Бізнес-логіка, яка **НЕ має** Prometheus-інструментації (аудит "як є"):

| Компонент | Відсутня метрика | Бізнес-ризик |
|-----------|-----------------|--------------|
| `SlashingProtocolWorker` | `slashing_events_total{reason}` | Немає деталізації причин слешингу |
| `OtaTransmissionWorker` | `ota_chunks_sent_total{firmware_version}` | Прогрес OTA оновлення невидимий |
| `EwsAlertWorker` | `ews_alerts_total{alert_type}` | Статистика EWS тривог недоступна |
| `ChainlinkOracleWorker` | `oracle_dispatch_latency_seconds` | Час відповіді оракула невідомий |
| `CoAP UDP listener` | `coap_packets_received_total` | Вхідний потік не вимірюється |
| Всі Lorenz-обчислення | `lorenz_computation_duration_seconds` | Час обчислення атрактора невідомий |

---

## 🪵 Частина III: Logs — GCP Cloud Logging

### 3.1 Поточна конфігурація

GCP Cloud Logging налаштований через Terraform (`terraform/main.tf`):

```hcl
# Вмикає Cloud Logging API
resource "google_project_service" "logging" {
  service = "logging.googleapis.com"
}

# Фільтр вартості: виключає INFO та DEBUG (лише WARNING+ потрапляє до Cloud Logging)
resource "google_logging_project_exclusion" "exclude_info_logs" {
  name    = "silken-net-exclude-info-debug"
  filter  = "severity < WARNING"
}
```

Сервісний акаунт GCP (`google_service_account.deploy`) має право `logging-write` — Rails та Sidekiq можуть писати логи до Cloud Logging.

### 3.2 Що потрапляє до Cloud Logging

| Severity | Потрапляє до Cloud Logging | Приклади |
|----------|--------------------------|---------|
| `DEBUG` | ❌ Виключено (cost control) | ActiveRecord SQL queries |
| `INFO` | ❌ Виключено (cost control) | Стандартні Rails request logs |
| `WARNING` | ✅ Зберігається | `Rails.logger.warn "⚠️ [Uplink] Невідоме джерело..."` |
| `ERROR` | ✅ Зберігається | `Rails.logger.error "🛑 [Security] Критична помилка..."` |
| `CRITICAL` | ✅ Зберігається | Незамасковані виключення |

### 3.3 Відсутня інтеграція

Structured logging (JSON з `trace_id`, `span_id`, `request_id`) у Rails не налаштований. Логи є простим текстом, що ускладнює кореляцію між помилками в Sentry та відповідними log-записами в Cloud Logging.

---

## 🗺️ Архітектура спостережуваності (Поточний стан vs Цільовий)

### Поточний стан (TRL 4 — "Як є")

```
┌─────────────────────────────────────────────────────────────────┐
│                        RAILS APPLICATION                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Sentry SDK (sentry-rails, sentry-sidekiq)              │   │
│  │  ✅ Налаштований  ❌ SENTRY_DSN відсутній у production  │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │ [НІКУДИ в production]            │
│                             ▼                                   │
│                     sentry.io (недосяжний)                      │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  /metrics endpoint (PrometheusCollector middleware)     │   │
│  │  ✅ 7 кастомних метрик  ❌ Ніхто не скрейпить          │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │ [НІКУДИ]                         │
│                             ▼                                   │
│                 Prometheus Server (ВІДСУТНІЙ)                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Rails.logger → GCP Cloud Logging                       │   │
│  │  ✅ WARNING+ логи  ❌ Структуровані логи відсутні       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│                 Grafana (ВІДСУТНЯ)                              │
│                 Alertmanager (ВІДСУТНІЙ)                        │
└─────────────────────────────────────────────────────────────────┘
```

### Цільовий стан (TRL 7 — "Production-Ready")

```
┌───────────────────────────────────────────────────────────────────────┐
│                          RAILS APPLICATION                            │
│                                                                       │
│  Sentry SDK ──────────────────────────────────────────→ sentry.io   │
│  (errors, 0.1% traces)    ✅ SENTRY_DSN налаштований                 │
│                                                                       │
│  /metrics endpoint ──────→ Prometheus Server ──────→ Grafana        │
│  (7+ метрик, secured)          (scrape 15s)          (dashboards)   │
│                                      │                               │
│                                      └──────────────→ Alertmanager  │
│                                                        (Slack/PD)   │
│                                                                       │
│  Rails.logger ───────────→ GCP Cloud Logging                        │
│  (WARNING+, structured)      (alerts on ERROR)                      │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 📁 Карта файлів (File Map)

| Файл | Роль | Статус |
|------|------|--------|
| `Gemfile` | `prometheus-client` 4.2.5, `sentry-ruby/rails/sidekiq` 6.5.0 | ✅ |
| `config/initializers/sentry.rb` | Ініціалізація Sentry (DSN, sampling, exclusions, scrubbing) | ✅ |
| `config/initializers/prometheus.rb` | Визначення `SilkenNet::Metrics` (5 Counters, 2 Gauges) | ✅ |
| `app/middleware/prometheus_collector.rb` | Rack middleware: `/metrics` endpoint, IP allowlist, Basic Auth, Sidekiq gauge refresh | ✅ |
| `config/application.rb` (рядок 31) | `config.middleware.use PrometheusCollector` | ✅ |
| `app/services/blockchain_minting_service.rb` (р.162) | `SCC_MINTED_TOTAL.increment(labels: {token_type:})` | ✅ |
| `app/services/blockchain_burning_service.rb` (р.97) | `SCC_SLASHED_TOTAL.increment(by: burn_amount)` — кумулятивна сума спалених токенів | ✅ |
| `app/workers/application_web3_worker.rb` (р.76,80,84,88) | `RPC_ERRORS_TOTAL.increment(labels: {network:, error_type:})` | ✅ |
| `app/services/telemetry_unpacker_service.rb` (р.79,87,154) | `TELEMETRY_FRAUD_DETECTED_TOTAL.increment`, `TELEMETRY_PROCESSED_TOTAL.increment` | ✅ |
| `app/workers/unpack_telemetry_worker.rb` (р.21) | `Sentry.set_tags(gateway_uid:)` | ✅ |
| `app/workers/gateway_telemetry_worker.rb` (р.17) | `Sentry.set_tags(queen_uid:)` | ✅ |
| `terraform/main.tf` | `google_project_service.monitoring` (Cloud Monitoring API) | ✅ (Cloud Monitoring) |
| `terraform/iam.tf` | `roles/monitoring.metricWriter` (для GCP-native метрик) | ✅ |
| `prometheus.yml` (scrape config) | — | 🔴 **ВІДСУТНІЙ** |
| `grafana/` (дашборди) | — | 🔴 **ВІДСУТНЯ** |
| `alertmanager.yml` | — | 🔴 **ВІДСУТНІЙ** |

---

## 🔗 Зовнішні Залежності та ENV змінні

| ENV змінна | Обов'язкова | Де використовується | Статус |
|-----------|-------------|---------------------|--------|
| `SENTRY_DSN` | ✅ Для production | `config/initializers/sentry.rb` | 🔴 Відсутня у `.kamal/secrets` |
| `SENTRY_TRACES_SAMPLE_RATE` | ❌ (default: 0.001) | `config/initializers/sentry.rb` | — |
| `SENTRY_WORKER_THREADS` | ❌ (default: 2) | `config/initializers/sentry.rb` | — |
| `RELEASE_VERSION` | ❌ (рекомендовано) | `config.release` | Не задана |
| `PROMETHEUS_ALLOWED_IPS` | ❌ | `app/middleware/prometheus_collector.rb` | Не задана |
| `PROMETHEUS_AUTH_USER` | ❌ (рекомендовано) | `app/middleware/prometheus_collector.rb` | Не задана |
| `PROMETHEUS_AUTH_PASSWORD` | ❌ (рекомендовано) | `app/middleware/prometheus_collector.rb` | Не задана |

---

## 📋 Висновки аудиту

### Що реально реалізовано (TRL 4 факти)

1. **Prometheus-client інтегрований** — 7 метрик визначені, `/metrics` endpoint працює з IP-захистом.
2. **Sentry SDK встановлений і налаштований** — zero-noise конфігурація з 34 виключеннями, автоматична Sidekiq-інтеграція, PII-scrubbing.
3. **Інструментація в бізнес-логіці** — всі критичні операції (мінтинг, слешинг, RPC-помилки, телеметрія) мають Prometheus-лічильники.
4. **GCP Cloud Logging** — WARNING+ логи зберігаються, cost-control фільтр активний.

### Що відсутнє (Gap Analysis)

1. **Prometheus Server** — метрики генеруються, але не збираються.
2. **Grafana** — нема де переглядати метрики.
3. **Alertmanager** — нема автоматичних сповіщень.
4. **`SENTRY_DSN` у production** — Sentry інертний.
5. **7 з 9 Sidekiq черг** не моніторяться (включаючи найвищопріоритетну `uplink`).
6. **Structured logging** — логи неструктуровані, кореляція з Sentry утруднена.

### Наступні кроки (поза scope цього документа)

1. **Вирішити BLOCKER-4** (SENTRY_DSN) — 15 хвилин, максимальний impact.
2. **Вирішити BLOCKER-1** (Prometheus Server) — додати як Kamal accessory.
3. **Вирішити BLOCKER-2** (Grafana) — розгорнути після Prometheus Server.
4. **Вирішити BLOCKER-3** (Alertmanager) — додати PromQL правила алертів.
5. **Вирішити BLOCKER-5** (решта черг) — розширити `refresh_sidekiq_gauges`.

---

## 🏗️ Архітектурне Рішення: Чому `prometheus-client`

### Альтернативи, що розглядались

| Інструмент | Потрібні gems | Плюси | Мінуси |
|---|---|---|---|
| **Yabeda** (`yabeda-prometheus`, `yabeda-sidekiq`, `yabeda-rails`) | 4–5 gems | Nice DSL, auto-instruments Rails/Sidekiq | Транзитивні залежності, "магічна" авто-інструментація, повільніший maintenance cadence |
| **OpenTelemetry** (`opentelemetry-sdk`, `opentelemetry-exporter-otlp`, adapters) | 6–10 gems | Industry standard для traces/spans/logs | Масивний overhead для нашого use case (нам потрібні counters/gauges, не distributed tracing), складне налаштування, vendor-орієнтований |
| **`prometheus-client`** (один gem) | **1 gem** | Офіційний Prometheus Ruby client, thread-safe, zero magic, ідеально для кастомних бізнес-метрик | Немає авто-інструментації (що нам і потрібно — інструментуємо лише те, що важливо) |

### Чому обрано `prometheus-client`

1. **Lean** — Один gem, нуль транзитивного bloat. Gemfile залишається чистим.
2. **Офіційний** — Підтримується самою організацією Prometheus (не community wrapper).
3. **Thread-safe** — Критично для Sidekiq workers (16 потоків × 7 черг).
4. **Кастомні метрики** — Нам потрібні domain-specific counters (`scc_minted_total`, `rpc_errors_total`), а не generic Rails request histograms. Авто-інструментація Yabeda додає шум.
5. **Rails 8.1 native** — Працює з `ActiveSupport::Notifications`. Немає конфліктів з framework.
6. **Без Redis залежності** — Метрики живуть у пам'яті процесу. Без зайвої інфраструктури.
