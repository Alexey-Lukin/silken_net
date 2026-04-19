# 06_03: Спостережуваність Prometheus (Метрики, Grafana, Alerting)

## 🎯 Мета

Зафіксувати стек спостережуваності (Observability): які інструменти збору помилок (Sentry) та метрик (Prometheus) реально імплементовані в коді, які кастомні бізнес-метрики збираються, і чи існує конфігурація для їх збору та візуалізації (Prometheus Server, Grafana).

Документ чітко розділяє три шари спостережуваності:

| Шар | Інструмент | Статус |
|-----|------------|--------|
| **APM / Error Tracking** | Sentry | ✅ Реалізовано в коді |
| **Time-series / Metrics** | Prometheus (`prometheus-client`) | ✅ `/metrics` endpoint існує, ❌ Prometheus Server відсутній |
| **Logs** | GCP Cloud Logging + Structured JSON | ✅ Реалізовано (WARNING+, JSON з Sentry correlation) |
| **Visualization** | Grafana | ❌ **Відсутня в інфраструктурі** |
| **Alerting** | Alertmanager | ❌ **Відсутній в інфраструктурі** |

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — бібліотеки встановлені, 10 кастомних метрик реалізовані та інструментовані, структуровані JSON-логи активні; Prometheus Server та Grafana відсутні в інфраструктурі
- **Пов'язані модулі:**
  - Розгортання → [`06_01_Deployment_Kamal_Terraform`](06_01_Deployment_Kamal_Terraform)
  - Akash → [`06_02_Akash_Network_Integration`](06_02_Akash_Network_Integration)
  - Бізнес-логіка → [`04_02_Business_Logic_and_Services`](04_02_Business_Logic_and_Services)

---

## 🛑 Блокери

> Без вирішення цих пунктів система летить "наосліп" у Mainnet.

### 🔴 BLOCKER-1: Prometheus Server не розгорнутий — `/metrics` нікому скрейпити

**Статус:** Критичний. Блокує збір будь-яких метрик.

Rails-застосунок **вже** генерує метрики та виставляє їх через `/metrics` endpoint (захищений IP allowlist). Але результат аудиту Terraform-конфігурацій (`terraform/main.tf`, `terraform/compute.tf`, `terraform/database.tf`, `terraform/vpc.tf`, `terraform/iam.tf`, `terraform/akash/main.tf`) та конфігів Akash SDL (`deploy/akash/deploy.yaml`) однозначний:

**Prometheus Server** — ні як Docker-контейнер в Akash SDL, ні як GCP Compute Instance — **ніде не визначений**.

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

**Примітка щодо GCP Cloud Monitoring:** Terraform вмикає `monitoring.googleapis.com` API та надає сервісному акаунту роль `roles/monitoring.metricWriter`. Однак це — нативний GCP Cloud Monitoring (Stackdriver) для системних метрик (CPU, RAM), а **не** Prometheus. Кастомні бізнес-метрики (`silkennet_scc_minted_total`, `silkennet_rpc_errors_total` тощо) наразі **не налаштовані для надсилання** до Cloud Monitoring (потребуватиме додаткового Prometheus → Cloud Monitoring exporter або OpenTelemetry Collector).

> **Примітка:** GCP Memorystore Redis видалено з інфраструктури (замінено на Upstash). Cloud Monitoring більше не збирає Redis-метрики автоматично. Upstash має власний дашборд для моніторингу Redis.

**Дія (варіанти вирішення, поза scope цього документа):**
1. Додати Prometheus Server як окремий сервіс в Akash SDL (`deploy/akash/deploy.yaml`).
2. Використати SaaS-рішення (Grafana Cloud, Prometheus Remote Write до managed endpoint).
3. Розгорнути Prometheus + Grafana на Ingress Anchor e2-micro (мінімальний overhead для TRL 6-7).

---

### 🔴 BLOCKER-2: Grafana відсутня — метрики є, але переглядати нема де

**Статус:** Критичний. Блокує візуалізацію та операційний моніторинг.

Пошук по всіх інфраструктурних файлах (`terraform/**/*.tf`, `deploy/akash/deploy.yaml`) не виявив жодної згадки про Grafana.

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

### ✅ BLOCKER-4: `SENTRY_DSN` додано до `.kamal/secrets` (Виправлено)

**Статус:** Виправлено. `SENTRY_DSN` додано до `.kamal/secrets` та `config/deploy.yml env.secret`. Для Akash деплоїв — задається в SDL env vars.

Sentry тепер активний у production. Всі помилки Sidekiq, збої Web3 та виключення Rails надсилаються до Sentry.

---

### ✅ BLOCKER-5: Усі 9 Sidekiq черг моніторяться Prometheus (Виправлено)

**Статус:** Виправлено. `refresh_sidekiq_gauges` розширено для всіх 9 черг.

`PrometheusCollector` middleware тепер моніторить усі 9 черг:
```ruby
ALL_QUEUES = %w[uplink alerts critical downlink default web3_critical web3 web3_low low]
```

| Черга | Пріоритет | Воркери | Статус |
|-------|-----------|---------|--------|
| `uplink` | 1 (найвищий) | `UnpackTelemetryWorker` | ✅ Моніториться |
| `alerts` | 2 | `EwsAlertWorker` | ✅ Моніториться |
| `critical` | 3 | `SlashingProtocolWorker` | ✅ Моніториться |
| `downlink` | 4 | `OtaTransmissionWorker` | ✅ Моніториться |
| `default` | 5 | Агрегація, health checks | ✅ Моніториться |
| `web3_critical` | 6 | Мінтинг, Oracle, ZK | ✅ Моніториться |
| `web3` | 7 | Celo, Solana, peaq | ✅ Моніториться |
| `web3_low` | 8 | L1 anchoring, KlimaDAO | ✅ Моніториться |
| `low` | 9 (найнижчий) | Audit logging, analytics | ✅ Моніториться |

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
| Prometheus Server | `deploy/akash/deploy.yaml`, `terraform/**/*.tf` | 🔴 **ВІДСУТНІЙ** |
| Grafana | `deploy/akash/deploy.yaml`, `terraform/**/*.tf` | 🔴 **ВІДСУТНЯ** |
| Alertmanager | `deploy/akash/deploy.yaml`, `terraform/**/*.tf` | 🔴 **ВІДСУТНІЙ** |
| `SENTRY_DSN` у secrets | `.kamal/secrets`, Akash SDL env | ✅ Додано |
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
| `production` | Активний (✅ `SENTRY_DSN` додано у `.kamal/secrets`) |

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
| `silkennet_sidekiq_queue_size` | `SilkenNet::Metrics::SIDEKIQ_QUEUE_SIZE` | `queue` (всі 9 черг) | `PrometheusCollector#refresh_sidekiq_gauges` | Поточна кількість задач у кожній Sidekiq черзі |
| `silkennet_sidekiq_queue_latency_seconds` | `SilkenNet::Metrics::SIDEKIQ_QUEUE_LATENCY` | `queue` (всі 9 черг) | `PrometheusCollector#refresh_sidekiq_gauges` | Вік найстарішої задачі в черзі (секунди) |

**Підсумок реєстру: 5 Counters + 2 Gauges = 7 кастомних метрик (всі 9 черг покриті).**

### 2.4 Реалізовані додаткові метрики (Sprint 2, S2.4)

5 нових метрик зареєстровані в `config/initializers/prometheus.rb` та інструментовані у відповідних воркерах:

| Metric Name | Тип | Воркер | Labels |
|-------------|-----|--------|--------|
| `silkennet_slashing_events_total` | Counter | `BurnCarbonTokensWorker` | `reason` |
| `silkennet_ota_chunks_sent_total` | Counter | `OtaTransmissionWorker` | `firmware_version` |
| `silkennet_ews_alerts_total` | Counter | `DclimateVerificationWorker` | `alert_type` |
| `silkennet_oracle_dispatch_duration_seconds` | Histogram | `ChainlinkDispatchWorker` | — |
| `silkennet_coap_packets_received_total` | Counter | `UnpackTelemetryWorker` | `status` |

**Підсумок реєстру: 10 кастомних метрик (7 оригінальних + 5 нових = 10: 7 counters + 1 histogram + 2 gauges).**

### 2.5 Відсутні метрики (залишкові прогалини)

| Компонент | Відсутня метрика | Бізнес-ризик |
|-----------|-----------------|--------------|
| `ChainlinkOracleWorker` | `oracle_dispatch_latency_seconds` — деталізація по мережах | Час відповіді оракула per-network невідомий |
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

### ✅ 3.3 Structured JSON Logging (Виправлено, Sprint 2 S2.5)

**Статус:** Реалізовано. `config/environments/production.rb` тепер конфігурує Rails logger з JSON-форматуванням через Oj-серіалізатор.

Кожен log-рядок містить:

```json
{
  "timestamp": "2026-04-18T10:47:13.123Z",
  "level": "INFO",
  "pid": 12345,
  "request_id": "abc123",
  "sentry_trace_id": "def456",
  "sentry_span_id": "ghi789",
  "message": "..."
}
```

- **Кореляція з Sentry:** `sentry_trace_id` / `sentry_span_id` — можна знайти будь-який запит між Cloud Logging та Sentry.
- **Opt-out:** `RAILS_LOG_JSON=false` вимикає JSON-форматування (зручно в dev/CI).
- **PID мемоізація:** `Process.pid` кешується один раз — уникається системний виклик при кожному лог-записі.
- **Вартість:** INFO/DEBUG логи як і раніше виключаються Cloud Logging cost-exclusion фільтром (тільки WARNING+ зберігається).

---

## 🗺️ Архітектура спостережуваності (Поточний стан vs Цільовий)

### Поточний стан (TRL 4 — "Як є")

```
┌─────────────────────────────────────────────────────────────────┐
│                        RAILS APPLICATION                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Sentry SDK (sentry-rails, sentry-sidekiq)              │   │
│  │  ✅ Налаштований  ✅ SENTRY_DSN додано у production    │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │ [Активний у production]          │
│                             ▼                                   │
│                     sentry.io (активний)                        │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  /metrics endpoint (PrometheusCollector middleware)     │   │
│  │  ✅ 7 кастомних метрик  ✅ Всі 9 черг  ❌ Ніхто не скрейпить  │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │ [НІКУДИ]                         │
│                             ▼                                   │
│                 Prometheus Server (ВІДСУТНІЙ)                   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Rails.logger → GCP Cloud Logging                       │   │
│  │  ✅ WARNING+ логи  ✅ Structured JSON (Sentry trace)    │   │
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
| `config/initializers/prometheus.rb` | Визначення `SilkenNet::Metrics` (7 Counters + 1 Histogram + 2 Gauges = 10 метрик) | ✅ |
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
| `deploy/akash/deploy.yaml` | Akash SDL (web + job services, CoAP/UDP) | ✅ (без Prometheus) |
| `prometheus.yml` (scrape config) | — | 🔴 **ВІДСУТНІЙ** |
| `grafana/` (дашборди) | — | 🔴 **ВІДСУТНЯ** |
| `alertmanager.yml` | — | 🔴 **ВІДСУТНІЙ** |

---

## 🔗 Зовнішні Залежності та ENV змінні

| ENV змінна | Обов'язкова | Де використовується | Статус |
|-----------|-------------|---------------------|--------|
| `SENTRY_DSN` | ✅ Для production | `config/initializers/sentry.rb` | ✅ Додано у `.kamal/secrets` |
| `SENTRY_TRACES_SAMPLE_RATE` | ❌ (default: 0.001) | `config/initializers/sentry.rb` | — |
| `SENTRY_WORKER_THREADS` | ❌ (default: 2) | `config/initializers/sentry.rb` | — |
| `RELEASE_VERSION` | ❌ (рекомендовано) | `config.release` | Не задана |
| `PROMETHEUS_ALLOWED_IPS` | ❌ | `app/middleware/prometheus_collector.rb` | Не задана |
| `PROMETHEUS_AUTH_USER` | ❌ (рекомендовано) | `app/middleware/prometheus_collector.rb` | Не задана |
| `PROMETHEUS_AUTH_PASSWORD` | ❌ (рекомендовано) | `app/middleware/prometheus_collector.rb` | Не задана |

---

## 📋 Висновки аудиту

### Що реально реалізовано (TRL 5 факти)

1. **Prometheus-client інтегрований** — 10 метрик визначені (7 counters + 1 histogram + 2 gauges), `/metrics` endpoint працює з IP-захистом.
2. **Sentry SDK встановлений і налаштований** — zero-noise конфігурація з 34 виключеннями, автоматична Sidekiq-інтеграція, PII-scrubbing.
3. **Інструментація в бізнес-логіці** — всі критичні операції (мінтинг, слешинг, RPC-помилки, телеметрія, OTA, EWS, CoAP) мають Prometheus-лічильники.
4. **GCP Cloud Logging** — WARNING+ логи зберігаються, cost-control фільтр активний.
5. **Structured JSON logging** — активовано у production: кожен рядок містить `timestamp`, `pid`, `request_id`, `sentry_trace_id`, `sentry_span_id`.

### Що відсутнє (Gap Analysis)

1. **Prometheus Server** — метрики генеруються, але не збираються.
2. **Grafana** — нема де переглядати метрики.
3. **Alertmanager** — нема автоматичних сповіщень.

### Наступні кроки (поза scope цього документа)

1. **Вирішити BLOCKER-1** (Prometheus Server) — додати як сервіс в Akash SDL або Grafana Cloud SaaS.
2. **Вирішити BLOCKER-2** (Grafana) — розгорнути після Prometheus Server.
3. **Вирішити BLOCKER-3** (Alertmanager) — додати PromQL правила алертів.

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
