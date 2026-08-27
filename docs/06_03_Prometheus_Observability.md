# 06_03: Спостережуваність Prometheus (Метрики, Grafana, Alerting)

## 🎯 Мета

Зафіксувати стек спостережуваності (Observability): які інструменти збору помилок (Sentry) та метрик (Prometheus) реально імплементовані в коді, які кастомні бізнес-метрики збираються, і чи існує конфігурація для їх збору та візуалізації (Prometheus Server, Grafana).

Документ чітко розділяє три шари спостережуваності:

| Шар | Інструмент | Статус |
|-----|------------|--------|
| **APM / Error Tracking** | Sentry | ✅ Реалізовано в коді |
| **Time-series / Metrics** | Prometheus (`prometheus-client`) + Grafana Alloy | ✅ `/metrics` endpoint існує, ✅ Alloy scrapes + remote_write → Grafana Cloud |
| **Logs** | GCP Cloud Logging + Structured JSON | ✅ GCP/Kamal-шлях (Cloud Logging, WARNING+, JSON+Sentry correlation); ⚠️ **Akash-шлях = ефемерний lease-log** → Rails-push у Loki (§Частина III · [`INF.22`](00_07_Action_Plan_Tracker)) |
| **Visualization** | Grafana Cloud | ✅ **Доступна через SaaS (дашборди — операційна задача)** |
| **Alerting** | Grafana Cloud Alerting | ✅ **Доступний через SaaS (правила — операційна задача)** |

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — бібліотеки встановлені, кастомні метрики реалізовані та інструментовані (повний реєстр — §2.8; парність реєстру з кодом тримає гейт, не лічильник у прозі), структуровані JSON-логи активні; Grafana Alloy sidecar налаштований для scrape + remote_write до Grafana Cloud (Grafana Cloud SaaS, OBS.1); TRL 7 підтверджується після першого реального деплою з метриками в Grafana Cloud
- **Відкрите:** перший деплой з метриками в Grafana Cloud (TRL 6→7); dashboard import → [`00_07`](00_07_Action_Plan_Tracker) (OBS.1, S2.2).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | Розгортання (Kamal/Terraform) |
| [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) | Akash SDL (`alloy` сервіс) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (інструментовані метрики) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | OBS.1 (Grafana Cloud), S2.2 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Статус Імплементації](#-статус-імплементації)
- [Частина I: APM — Sentry Error Tracking](#-частина-i-apm--sentry-error-tracking)
- [Частина II: Time-Series — Prometheus Metrics](#-частина-ii-time-series--prometheus-metrics)
- [Частина III: Logs — GCP Cloud Logging](#-частина-iii-logs--gcp-cloud-logging)
- [Архітектура спостережуваності (Поточний стан vs Цільовий)](#-архітектура-спостережуваності-поточний-стан-vs-цільовий)
- [Карта файлів (File Map)](#-карта-файлів-file-map)
- [Зовнішні Залежності та ENV змінні](#-зовнішні-залежності-та-env-змінні)
- [Висновки аудиту](#-висновки-аудиту)
- [Архітектурне Рішення: Чому `prometheus-client](#-архітектурне-рішення-чому-prometheus-client)
<!-- TOC:AUTO:END -->

---

## ✅ Статус Імплементації

| Компонент | Файл | Статус |
|-----------|------|--------|
| `sentry-ruby` gem | `Gemfile` | ✅ 6.5.0 |
| `sentry-rails` gem | `Gemfile` | ✅ 6.5.0 (auto-instruments Rails) |
| `sentry-sidekiq` gem | `Gemfile` | ✅ 6.5.0 (auto-instruments Sidekiq) |
| `prometheus-client` gem | `Gemfile` | ✅ 4.2.5 |
| Sentry initializer | `config/initializers/sentry.rb` | ✅ Повністю налаштований |
| Prometheus initializer | `config/initializers/prometheus.rb` | ✅ реєстр метрик визначено (перелік — §2.8) |
| `/metrics` endpoint | `app/middleware/prometheus_collector.rb` | ✅ Реалізований (IP allowlist + Basic Auth) |
| Middleware registration | `config/application.rb` | ✅ `config.middleware.use PrometheusCollector` |
| `SCC_MINTED_TOTAL` instrumentation | `app/services/blockchain_minting_service.rb` | ✅ Реалізовано |
| `SCC_SLASHED_TOTAL` instrumentation | `app/services/blockchain_burning_service.rb` | ✅ Реалізовано |
| `RPC_ERRORS_TOTAL` instrumentation | `app/workers/application_web3_worker.rb` | ✅ Реалізовано (4 точки) |
| `TELEMETRY_PROCESSED_TOTAL` instrumentation | `app/services/telemetry_unpacker_service.rb` | ✅ Реалізовано |
| `TELEMETRY_FRAUD_DETECTED_TOTAL` instrumentation | `app/services/telemetry_unpacker_service.rb` | ✅ Реалізовано (2 точки) |
| Sentry context у workers | `app/workers/unpack_telemetry_worker.rb`, `app/workers/gateway_telemetry_worker.rb` | ✅ `Sentry.set_tags()` |
| Prometheus Server | `deploy/akash/deploy.yaml` (alloy сервіс) | ✅ **Grafana Alloy sidecar → Grafana Cloud** |
| Grafana | Grafana Cloud SaaS | ✅ **Доступна (дашборди — операційна задача)** |
| Alertmanager | Grafana Cloud Alerting | ✅ **Доступний (правила — операційна задача)** |
| `SENTRY_DSN` у secrets | `.kamal/secrets-common`, Akash SDL env | ✅ Додано |
| Grafana Alloy config | `deploy/akash/config.alloy` | ✅ Scrape + remote_write |
| Grafana Alloy SDL service | `deploy/akash/deploy.yaml` (`alloy` сервіс) | ✅ 0.5 CPU, 512Mi RAM |
| Terraform Grafana Cloud vars | `terraform/akash/variables.tf` | ✅ 5 змінних (3 sensitive) |
| Prometheus scrape config | `deploy/akash/config.alloy` | ✅ 3 таргети `web:80`/`job:9394`/`coap:9395` (лейбл `process`; реєстр in-process — §2.9; `coap` = Akash-**fallback**-сервіс — primary-демон на Ingress Anchor поза scrape, стеля §2.9(б)), 15s, Basic Auth |
| Grafana dashboards | Grafana Cloud UI | 🟡 Операційна задача |

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
AES-ключі, мнемоніки та бінарні payload у **extra-context** замінюються на `[FILTERED]` за **іменем поля**. Додатково редагуються секретні **значення**, що протекли у вільний текст — exception message (`event.exception.values[].value`) та `Sentry.capture_message` — за патерном `<secret-label>[=:]<value>` (напр. `aes_key=2b7e…` → `aes_key=[FILTERED]`); публічні хеші (tx/адреса) лишаються читабельними. `filter_parameters` покриває лише request-params, не текст помилок.

### 1.3 Інтеграція з Sidekiq (`sentry-sidekiq`)

Gem `sentry-sidekiq` автоматично додає Sentry middleware до Sidekiq server middleware chain. Це означає:
- Будь-який **необроблений виняток** у будь-якому воркері автоматично надсилається до Sentry.
- Кожна Sidekiq-задача отримує власну транзакцію Sentry з метаданими: `queue`, `class`, `jid`, `args`.
- Повторні спроби (retries) відстежуються як окремі події.

**Активна Sentry-інструментація у воркерах:**

| Воркер | Файл | Тег |
|--------|------|-----|
| `UnpackTelemetryWorker` | `app/workers/unpack_telemetry_worker.rb` | `Sentry.set_tags(gateway_uid: ...)` |
| `GatewayTelemetryWorker` | `app/workers/gateway_telemetry_worker.rb` | `Sentry.set_tags(queen_uid: ...)` |

Ці теги дозволяють в Sentry UI фільтрувати помилки за конкретним gateway або queen UID.

### 1.4 Виключені виключення (Zero Noise Policy)

Розширений набір **класів виключень** виключено зі Sentry, щоб уникнути alert fatigue (повний перелік — SSOT `config/initializers/sentry.rb`):

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
| Canopy (staging) | Працює під `RAILS_ENV=production` (НЕ окремий Rails-env); активний, `SENTRY_DSN` присутній — розрізняється `external_labels` env/release (§2.9) |
| `production` | Активний (✅ `SENTRY_DSN` додано у `.kamal/secrets-common`) |

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
        Активний ЛИШЕ коли обидва PROMETHEUS_AUTH_USER + PROMETHEUS_AUTH_PASSWORD непорожні.
        Порожні → auth skip (лише IP-allowlist). ⚠️ НІКОЛИ не лишати placeholder
        REQUIRED_SECRET_NOT_SET (непорожній = known-value bypass, B6) — provision реальні
        random creds (defense-in-depth) або лишити порожніми (internal-only Alloy scrape).
```

### 2.3 Реєстр кастомних бізнес-метрик (повний)

#### Counters (монотонно зростаючі)

| Metric Name | Ruby Constant | Labels | Де інкрементується | Бізнес-значення |
|-------------|--------------|--------|-------------------|-----------------|
| `silkennet_scc_minted_total` | `SilkenNet::Metrics::SCC_MINTED_TOTAL` | `token_type` (carbon_coin, forest_coin) | `BlockchainMintingService` | Кумулятивна **сума змінтованих токенів** (increment `by: tx.amount`, не лічильник подій) — [INF.26]. Доти був голий `.increment`, тобто рахував ТРАНЗАКЦІЇ під іменем «tokens», і це видно було лише через споживача: обидві серії стоять на одній панелі «SCC Minted vs Slashed». Лічбу ПОДІЙ на цьому тракті несе пара `MINT_ATTEMPTS_TOTAL`/`MINT_SUCCESS_TOTAL` (SLO) |
| `silkennet_mint_attempts_total` | `SilkenNet::Metrics::MINT_ATTEMPTS_TOTAL` | `token_type` | `BlockchainMintingService` (вхід `process_token_group`, до локу) | Спроби on-chain мінту (txs, що пройшли pre-flight guards) — знаменник SLO «≥80% mint success during outage» ([`06_08 §2.4`](06_08_Resilience_and_Failover_Policy)) |
| `silkennet_mint_success_total` | `SilkenNet::Metrics::MINT_SUCCESS_TOTAL` | `token_type` | `BlockchainMintingService` (status→sent) | Успішні broadcast'и в mempool — чисельник того ж SLO |
| `silkennet_dynamic_tax_collected_total` | `SilkenNet::Metrics::TAX_COLLECTED_TOTAL` | `token_type` | `BlockchainMintingService` (після broadcast) | [DOC-T.89] ЕФЕКТИВНА ставка податку: оголошені 2% стягує лише `batchMint`, а в одиночний `mint()` веде вісім детермінованих каналів. Знаменник — `silkennet_scc_minted_total` (теж у СУМАХ, INF.26), тож ставка = відношення двох лічильників. ⚠️ Інкремент лише ПІСЛЯ broadcast: `build_batch_arrays` рахує податок на кожному рівні бінарного пошуку |
| `silkennet_mint_chunk_errors_total` | `SilkenNet::Metrics::MINT_CHUNK_ERRORS_TOTAL` | — | `EvaluateTreeBatchWorker` (`rescue StandardError` кожного гаманця) | **[ARCH.94]** Проковтнуті відмови мінту НА РІВНІ ГАМАНЦЯ. Джоба при цьому вертає **успіх** (нема retry, нема DeadSet), а mint-SLO їх не бачить за побудовою: tx не створено, тож гаманець не входить навіть у ЗНАМЕННИК. Саме так P1 «емісія спрацьовує раз на гаманець» прожив непоміченим |
| `silkennet_scc_slashed_total` | `SilkenNet::Metrics::SCC_SLASHED_TOTAL` | — | `BlockchainBurningService` | Кумулятивна **сума спалених токенів** (increment `by: effective_burn` — [SLASH.2] on-chain-реалістичний upper-bound, свідомо НЕ pre-tax `burn_amount`, як стояло тут доти; не лічильник подій) |
| `silkennet_rpc_errors_total` | `SilkenNet::Metrics::RPC_ERRORS_TOTAL` | `network`, `error_type` (timeout, connection) | `ApplicationWeb3Worker` (4 точки) | Кожна RPC-помилка по всіх 12 блокчейн-мережах |
| `silkennet_telemetry_processed_total` | `SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL` | — | `TelemetryUnpackerService` | Кожен успішно оброблений telemetry chunk |
| `silkennet_telemetry_fraud_detected_total` | `SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL` | — | `TelemetryUnpackerService` (2 точки) | Відхилені пакети (sensor noise, unknown DID, tamper) |
| `silkennet_panic_replay_rejected_total` | `SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL` | — | `TelemetryUnpackerService` (SEC.10 panic Frame Counter) | **[SEC.10]** Panic-пакети відкинуті як replay через Redis SETNX nonce. Сторожовий пес панічного каналу — кожен сплеск тут означає або legitimate retransmission (LoRa duplicate) або replay-attack. Grafana alert при різкому стрибку → можливий attacker injection forged panic packets. |
| `silkennet_slash_attempts_total` | `SilkenNet::Metrics::SLASH_ATTEMPTS_TOTAL` | — | `BlockchainBurningService` (intent created) | **[ARCH.45]** Спроби slash — знаменник slash success-rate SLO |
| `silkennet_slash_success_total` | `SilkenNet::Metrics::SLASH_SUCCESS_TOTAL` | — | `BlockchainBurningService` (status→sent) | **[ARCH.45]** Успішні broadcast slash — чисельник того ж SLO |
| `silkennet_solana_payout_attempts_total` | `SilkenNet::Metrics::SOLANA_PAYOUT_ATTEMPTS_TOTAL` | — | `Solana::BatchPayoutService` | **[ARCH.45]** Спроби Solana batch payout — знаменник payout success-rate SLO |
| `silkennet_solana_payout_success_total` | `SilkenNet::Metrics::SOLANA_PAYOUT_SUCCESS_TOTAL` | — | `Solana::BatchPayoutService` (status→sent) | **[ARCH.45]** Успішні Solana batch payout — чисельник того ж SLO |
| `silkennet_insurance_payout_attempts_total` | `SilkenNet::Metrics::INSURANCE_PAYOUT_ATTEMPTS_TOTAL` | — | `InsurancePayoutWorker` (payout attempt) | **[INS.1]** Спроби страхової виплати — знаменник insurance payout success-rate SLO |
| `silkennet_insurance_payout_success_total` | `SilkenNet::Metrics::INSURANCE_PAYOUT_SUCCESS_TOTAL` | — | `InsurancePayoutWorker` (Etherisc claim sent / internal mint status→sent [INF.26]) | **[INS.1]** Успішні страхові виплати — чисельник того ж SLO |

#### Gauges (поточне значення — оновлюються при кожному scrape)

| Metric Name | Ruby Constant | Labels | Де оновлюється | Бізнес-значення |
|-------------|--------------|--------|----------------|-----------------|
| `silkennet_sidekiq_queue_size` | `SilkenNet::Metrics::SIDEKIQ_QUEUE_SIZE` | `queue` (всі 9 черг) | `PrometheusCollector#refresh_sidekiq_gauges` | Поточна кількість задач у кожній Sidekiq черзі |
| `silkennet_sidekiq_queue_latency_seconds` | `SilkenNet::Metrics::SIDEKIQ_QUEUE_LATENCY` | `queue` (всі 9 черг) | `PrometheusCollector#refresh_sidekiq_gauges` | Вік найстарішої задачі в черзі (секунди) |
| `silkennet_sidekiq_dead_set_size` | `SilkenNet::Metrics::SIDEKIQ_DEAD_SET_SIZE` | — | `PrometheusCollector#refresh_sidekiq_gauges` | **[ARCH.45]** Розмір Sidekiq DeadSet (job-и, що вичерпали retry) — money-path тут = stranded funds/tx без авто-відновлення |
| `silkennet_mint_eligible_unminted_depth` | `SilkenNet::Metrics::MINT_ELIGIBLE_UNMINTED_DEPTH` | `sn-alert-mint-stall-depth` | `MintStallProbeWorker` (cron `55 * * * *` — зріз ПЕРЕД наступним циклом емісії) | **[ARCH.94]** Глибина застряглої популяції: гаманці над порогом емісії, які цикл НЕ змінтував. Дискримінатор точний — мінт піднімає `locked_balance`, тож після здорового циклу множина порожня **за побудовою**. 🔴 Несучий ОКРЕМО від лічильника помилок: відмова, що не кидає винятку (порожній селектор, знятий cron, хибний фільтр), лишає той у нулі, а нуль спроб для SLO-відношення невідрізненний від спокою — алерт `sn-alert-mint-slo-breach` несе гард `and attempts > 0`. Лічильник СТАНУ бачить обидва режими; форма — прецедент `hadron_kyc_pending_depth` [ARCH.65]. 🔴 **Писач переїхав із `TokenomicsBatchCallbacks#on_success` [ARCH.59, 2026-08-25], і це не косметика:** той колбек вішається на `Sidekiq::Batch#on(:success)`, тобто (а) у проді не виконується взагалі (`sidekiq-pro` поза Gemfile — [`04_02 §11`](04_02_Business_Logic_and_Services) DOC-R.10), і (б) навіть із ліцензією `:success` означає «всі джоби завершились БЕЗ ПОМИЛОК» — детектор застрягання емісії мовчав би саме тоді, коли чанки падають. Час зрізу несучий: цикл стартує о `:00`, а `lock_and_mint!` виводить гаманець із множини синхронно в чанку, тож `:55` міряє залишок здорового проходу — зсув часу міняє ЗНАЧЕННЯ, не лише свіжість |

> **[ARCH.61]** Actioning DeadSet-алертів: **`/sidekiq`** (Sidekiq::Web, змонтований за admin-only route-constraint + SEC.16 salt-stamp; app-constraint = єдиний шлюз — HAProxy path-ACL немає; unmatched → 404). Механіка constraint — [`04_03 §1`](04_03_REST_API_v1_Reference).

> Проміжний підсумок видалено — див. фінальну цифру у §2.8 (SSOT).

### 2.4 Реалізовані додаткові метрики (Sprint 2, S2.4)

Нові метрики (S2.4) зареєстровані в `config/initializers/prometheus.rb` та інструментовані у відповідних воркерах (повний реєстр + кількість — §2.8):

| Metric Name | Тип | Воркер | Labels |
|-------------|-----|--------|--------|
| `silkennet_slashing_events_total` | Counter | `BurnCarbonTokensWorker` | `reason` |
| `silkennet_ota_chunks_sent_total` | Counter | `Downlink::PendingQueueService` (chunk-server [FW.60]) | `firmware_version` |
| `silkennet_ews_alerts_total` | Counter | `EwsAlert` (`after_create_commit`) — [INF.26] дім переїхав із `DclimateVerificationWorker`, який лічив лише супутниково верифіковану підмножину | `alert_type` |
| `silkennet_oracle_dispatch_duration_seconds` | Histogram | `ChainlinkDispatchWorker` | — |
| `silkennet_coap_packets_received_total` | Counter | `UnpackTelemetryWorker` | `status` |
| `silkennet_streamr_broadcast_failures_total` | Counter | `StreamrBroadcastWorker` | — |

> Проміжний підсумок видалено — див. фінальну цифру у §2.8 (SSOT).

### 2.4.1 RSpec покриття нових метрик (S2.4 — Виконано)

> Конвенції написання / coverage-гейт / тріаж — [`04_06`](04_06_Testing_Guide_and_Coverage) (Testing Guide). Нижче — per-subsystem інвентар тестів метрик (One-Home: біля підсистеми; example-counts навмисно не фіксуються — volatile).

| Spec файл | Метрика | Що перевіряється |
|-----------|---------|------------------|
| `spec/initializers/prometheus_spec.rb` | нові метрики | Реєстрація, інкрементування, доступність констант, label validation |
| `spec/workers/burn_carbon_tokens_worker_spec.rb` | `SLASHING_EVENTS_TOTAL` | Інкремент по reason (tree_death / cluster_degradation), не інкрементується при breached |
| `spec/workers/ota_transmission_worker_spec.rb` | `OTA_CHUNKS_SENT_TOTAL` | Інкремент при успішній передачі, не інкрементується при failure, послідовна передача |
| `spec/workers/dclimate_verification_worker_spec.rb` | `EWS_ALERTS_TOTAL` | Інкремент при успішній верифікації, не інкрементується при falsey/verified/not found |
| `spec/workers/chainlink_dispatch_worker_spec.rb` | `ORACLE_DISPATCH_DURATION` | Histogram observation, не observe при skip/not found |
| `spec/workers/unpack_telemetry_worker_spec.rb` | `COAP_PACKETS_RECEIVED_TOTAL` | Статуси: success, unknown_device, decrypt_error; ізоляція між статусами |

### 2.5 Додаткові метрики (S5.1 — Виконано)

| Metric Name | Тип | Файл | Buckets |
|-------------|-----|------|---------|
| `silkennet_oracle_dispatch_duration_seconds` | Histogram | `ChainlinkDispatchWorker` | 0.5, 1, 2.5, 5, 10, 30, 60 |
| `silkennet_lorenz_computation_duration_seconds` | Histogram | `SilkenNet::Attractor` | 0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5 |

Обидві метрики зареєстровані в `config/initializers/prometheus.rb` та інструментовані у відповідних класах. `ORACLE_DISPATCH_DURATION` вимірює повний цикл dispatch (від виклику до отримання request_id). `LORENZ_COMPUTATION_DURATION` вимірює час серверного розрахунку 250 ітерацій Лоренца (Float арифметика).

> Проміжний підсумок видалено — див. фінальну цифру у §2.8 (SSOT).

### 2.6 Entropy Monitor Metric (Quantum Pre-Stress Detector)

| Metric Name | Тип | Файл | Labels |
|-------------|-----|------|--------|
| `silkennet_cluster_entropy_score` | Gauge | `ClusterEntropyAnalyzerWorker` | `cluster_id` |

Нормалізована ентропія Шеннона Z-розподілу кластера (0.0–1.0). Оновлюється `ClusterEntropyAnalyzerWorker` (queue: `alerts`, рекомендовано: щогодинний cron). Здоровий ліс: ≈ 0.75-0.95. Критичний поріг: < 0.65 → `EwsAlert(entropy_anomaly)`.

**Grafana Alert Rule:** `sn-alert-cluster-entropy` (`< 0.65`, for 30m) — IaC-дім `deploy/grafana/alerts/silkennet-alerts.yaml`, 👤 import (S2.2).

> Проміжний підсумок видалено — див. фінальну цифру у §2.8 (SSOT).

### 2.7 Governance Parameter Sync Observability

`Governance::ParameterSyncWorker` (queue: `web3_low`, cron: 03:30 UTC щоденно) моніторинг:

| Аспект | Механізм | Деталі |
|--------|----------|--------|
| **Sidekiq Queue** | `silkennet_sidekiq_queue_size{queue="web3_low"}` | Gauge, вже покрито `refresh_sidekiq_gauges` |
| **Sidekiq Latency** | `silkennet_sidekiq_queue_latency_seconds{queue="web3_low"}` | Gauge, вже покрито |
| **RPC Errors** | `silkennet_rpc_errors_total{network="polygon"}` | Counter, через `ApplicationWeb3Worker` |
| **Bounds Rejections** | `silkennet_governance_param_rejected_total{parameter}` | Counter [GOV.1]: DAO-значення поза safety-межами → відхилено (чинним лишилось попереднє), потрібен коригувальний голос |
| **Sync Logging** | `Rails.logger.info` / `.warn` / `.error` | `synced/skipped/rejected` per run + WARN на DCI-locked Lorenz-голос (tripwire) + ERROR на кожен reject |
| **Failure Alerts** | Sentry + Sidekiq retry exhaustion | 3 retries, unique_for 24h |

> **Перспектива:** Коли обсяг governance-операцій зростатиме, можна додати histogram `silkennet_governance_sync_duration_seconds` (rejected-counter уже live ↑).

### 2.8 Circuit Breaker та Acoustic Overflow метрики (S2.2/FW.22)

2 нові метрики для покращення observability circuit breaker'а та acoustic overflow:

| Metric Name | Тип | Файл | Labels | Бізнес-значення |
|-------------|-----|------|--------|-----------------|
| `silkennet_telemetry_acoustic_overflow_total` | Counter | `TelemetryUnpackerService` | — | Лічильник пакетів з `acoustic_events=255` (uint8 saturation). Для Grafana alerting: `rate() > 0` = firmware data loss |
| `silkennet_rpc_circuit_breaker_open` | Gauge | `Web3::ResilientClient` | `provider` | Стан circuit breaker: 1.0 = open (провайдер виключений), 0.0 = closed (здоровий). Для дашборду S2.2 |

Додатково: `silkennet_rpc_errors_total` тепер інструментовано безпосередньо в `Web3::ResilientClient#record_failure` з класифікацією error_type (timeout, connection_refused, host_unreachable, dns_error, io_error, rate_limited, unknown).

**Grafana Alert Rules:** `sn-alert-acoustic-overflow` (`rate(...[5m]) > 0`, for 5m) та `sn-alert-circuit-breaker` (`> 0`, for 2m) — IaC-дім `deploy/grafana/alerts/silkennet-alerts.yaml`, 👤 import (S2.2). Споріднений firmware-діагностичний counter `silkennet_tinyml_threshold_invalid_reports_total` (FW.18b, той самий патерн warn-лог-атрибуції) і його `sn-alert-tinyml-threshold-invalid` — канон [`03_03 §5.4`](03_03_TinyML_Acoustic_Inference).

### 📊 Канонічний реєстр метрик (SSOT)

> **ЄДИНЕ авторитетне джерело переліку + кількості метрик** — згенеровано з
> `SilkenNet::Metrics::REGISTRY`, verified vs `config/initializers/prometheus.rb`
> 2026-07-19 (додано SILENCE-1 tree-silence пару — dead-man switch Солдата;
> раніше 07-04: GOV.1 bounds-reject + E.60 sweep counters + дожим 3 gauge-дрейфів). Усі інші
> згадки (CLAUDE.md, `config.alloy`, підсекції §2.3–2.7 з обґрунтуванням/alert-прикладами)
> **рефлять сюди**, не дублюють число/перелік.
> При зміні реєстру в коді — **регенерувати ЛИШЕ цю таблицю** (команда в кінці).
> Де інкрементується/оновлюється кожна — `grep -rn "SilkenNet::Metrics::<CONST>" app/`.
>
> **Кількість тут свідомо НЕ записана числом** (⚖️ 2026-08-25, INF.26). Реєстр — це таблиці нижче, і рівно вони гейтовані `metric_registry_doc_sync_spec` (імена + типи, обидва напрямки). А речення-підсумок гейта не має за побудовою, тож воно й протухло: цей рядок роками стверджував «79 = 45+32+2», доки таблиці під ним регенерувались до 86 = 48+36+2 — тобто секція, яка називає себе **єдиним авторитетним джерелом кількості**, була єдиним місцем, де кількість брехала. Порахувати завжди: `bin/rails runner 'puts SilkenNet::Metrics::REGISTRY.metrics.size'`, або просто прочитати таблиці.

**Counters:**

| Metric | Labels | Призначення |
|---|---|---|
| `silkennet_actuator_stuck_recovered_total` | `device_type` | Actuators found recorded active past their command window and reset by the safety sweep |
| `silkennet_anchor_missed_weeks_total` | — | Total missed Ethereum L1 anchor weeks detected (gap > 8 days) |
| `silkennet_circuit_breaker_rejections_total` | `service` | Web3 requests fast-failed because a provider circuit breaker was open |
| `silkennet_coap_packets_received_total` | `status` | Total CoAP UDP packets received by the telemetry daemon |
| `silkennet_ethereum_anchor_reverted_total` | — | EthereumAnchor storeStateRoot txs that reverted on-chain (ARCH.66) |
| `silkennet_ews_alerts_total` | `alert_type` | Total EWS alerts created — [INF.26] «created», бо інкремент живе в `after_create_commit`; доставка ([`ARCH.60`](00_07_Action_Plan_Tracker)) — окрема подія й власного лічильника не має |
| `silkennet_fauna_skip_reports_total` | — | FW.42 telemetry packets reporting a fauna session skipped on low Vcap (per-DID attribution in logs) |
| `silkennet_filecoin_archive_exhausted_total` | — | FilecoinArchiveWorker jobs that exhausted all retries (archive landed in Dead Set) |
| `silkennet_filecoin_repin_total` | — | AuditLog archive re-enqueues issued by FilecoinReconcileWorker |
| `silkennet_iotex_backfill_rearmed_total` | — | TelemetryLogs re-armed for IoTeX verification by the backfill sweep (sustained-outage recovery; a healthy tract leaves this at zero) |
| `silkennet_filecoin_verification_failures_total` | `reason` | Filecoin archive integrity verification failures (E.60 sweep) |
| `silkennet_telemetry_archive_batch_failures_total` | `reason` | [E.60 Фаза 1б] збої архів-тракту по фазах: `build` (fail-open → zero32-мінт; при непорожніх вікнах = кандидат-інцидент) · `pin` (exhausted-hook) · `mismatch` (rebuild ≠ root при живих логах — integrity, runbook 06_08 §4.7) · `retention_expired` · `dispatch_drift` · `leaf_stamp_drift` (sweeper-семпл) |
| `silkennet_fw2_fc_degraded_reports_total` | — | FW.2 telemetry packets reporting a lost FC high-water invariant (Flash refusing writes; per-DID attribution in logs) |
| `silkennet_gateways_offline_total` | — | Total gateway offline transitions detected by the staleness sweeper (queen_offline alerts) |
| `silkennet_governance_param_rejected_total` | `parameter` | Governance parameter syncs rejected by bounds validation |
| `silkennet_helium_sos_received_total` | `outcome` | Queen SOS frames received via the Helium webhook, by processing outcome |
| `silkennet_insurance_payout_attempts_total` | — | Parametric insurance payouts attempted by InsurancePayoutWorker (SLO denominator) |
| `silkennet_insurance_payout_success_total` | — | Parametric insurance payouts BROADCAST — Etherisc claim sent / internal mint status→sent (SLO numerator) |
| `silkennet_insurance_reserve_hold_total` | `reason` | Internal-mode виплати, зупинені reserve-gate [INS.2]. ⚖️ ARCH.82: **ЄДИНИЙ канал** — парний `EwsAlert` пишеться без кластера, тож орг-поверхні його не бачать за побудовою. Окремо від `manual_review_depth` навмисно: той не розрізняє казначейську політику від double-spend-лімбо, а відповіді протилежні. ⚠️ Штатно нуль до калібрування порогів INS.2; `:eval_error` сюди НЕ рахується (transient RPC → Sidekiq-retry) |
| `silkennet_lineage_root_failures_total` | — | Mint lineage Merkle-root computation failures (fail-open, root left NULL) |
| `silkennet_m2m_nonce_fallback_total` | — | Total M2M nonce checks falling back from Redis to DB-backed cache (Redis outage indicator) |
| `silkennet_mint_attempts_total` | `token_type` | Mint transactions attempted by BlockchainMintingService (SLO denominator) |
| `silkennet_mint_chunk_errors_total` | — | Per-wallet mint failures swallowed by EvaluateTreeBatchWorker (job still reports success) |
| `silkennet_mint_success_total` | `token_type` | Mint transactions successfully broadcast to mempool — status→sent (SLO numerator) |
| `silkennet_dynamic_tax_collected_total` | `token_type` | Dynamic Tax actually broadcast to DAO_TREASURY (SCC) — numerator of the EFFECTIVE tax rate |
| `silkennet_ota_chunks_sent_total` | `firmware_version` | Total OTA firmware chunks transmitted to field devices |
| `silkennet_panic_replay_rejected_total` | — | Panic packets rejected as replay via SEC.10 Frame Counter SETNX nonce |
| `silkennet_partition_maintenance_failures_total` | — | PartitionMaintenanceWorker run failures (missing partition → day-1 INSERT crash risk) |
| `silkennet_qatt_nonce_fallback_total` | — | Total Queen-attestation batch nonce checks falling back from Redis to DB-backed cache (Redis outage indicator) |
| `silkennet_rpc_errors_total` | `network`, `error_type` | Total Web3 RPC errors |
| `silkennet_scc_minted_total` | `token_type` | Total SCC (SilkenCarbonCoin) tokens minted |
| `silkennet_scc_slashed_total` | — | Total tokens slashed (burned due to cluster stress) |
| `silkennet_slash_attempts_total` | — | Slash transactions attempted by BlockchainBurningService (SLO denominator) |
| `silkennet_slash_success_total` | — | Slash transactions successfully broadcast — status→sent (SLO numerator) |
| `silkennet_slashing_events_total` | `reason` | Total slashing (burn) events by reason |
| `silkennet_solana_payout_attempts_total` | — | Solana batch payouts attempted by BatchPayoutService (SLO denominator) |
| `silkennet_solana_payout_success_total` | — | Solana batch payouts successfully broadcast — status→sent (SLO numerator) |
| `silkennet_streamr_broadcast_failures_total` | — | Total Streamr broadcast failures (P2P real-time telemetry delivery) |
| `silkennet_telemetry_acoustic_overflow_total` | — | Total telemetry packets with acoustic_events=255 (uint8 saturation) |
| `silkennet_telemetry_ccm_decrypt_ok_total` | — | FW.2 CCM packets successfully decrypted with valid MIC |
| `silkennet_telemetry_ccm_fc_replay_rejected_total` | — | FW.2 CCM packets rejected because per-DID Frame Counter was not strictly increasing |
| `silkennet_telemetry_ccm_mic_fail_total` | — | FW.2 CCM packets rejected due to MIC verification failure |
| `silkennet_telemetry_fraud_detected_total` | — | Total telemetry packets rejected (sensor noise, unknown DID, tamper) |
| `silkennet_telemetry_log_unpruned_lookups_total` | `caller` | Total TelemetryLog lookups without partition pruning (degraded path; missing or invalid ISO8601 created_at_iso) |
| `silkennet_blockchain_transaction_unpruned_lookups_total` | `caller` | Total BlockchainTransaction lookups without partition pruning (degraded path; missing or invalid created_at) |
| `silkennet_telemetry_processed_total` | — | Total telemetry chunks processed by TelemetryUnpackerService |
| `silkennet_tinyml_threshold_invalid_reports_total` | — | FW.18b telemetry packets reporting a nonzero rejected-OTA-thresholds counter (per-DID attribution in logs) |
| `silkennet_treasury_check_errors_total` | `network`, `signer`, `error_type` | Total treasury monitoring RPC errors |
| `silkennet_tree_silence_total` | — | Total tree silence transitions detected by the staleness sweeper (per-tree field_audit escalations) |
| `silkennet_w3bstream_signature_fallback_total` | `reason` | Telemetry with no usable HardwareKey — SHA256 fallback in dev, fail-closed rejection in production. ⚠️ [INF.26] Лічильник міряє ПЕРЕДУМОВУ, не наслідок: інкремент стоїть ДО розвилки prod/dev, тож ім'я (`_fallback_`) вужче за подію — у проді той самий рядок означає ВІДМОВУ. Перенести інкремент у dev-гілку не можна: осліпли б саме там, де сигнал найпотрібніший |

**Grafana Alert Rules (INF.26, дротовано 2026-08-26):** `sn-alert-ccm-mic-fail` · `sn-alert-telemetry-unpruned-lookups` · `sn-alert-blockchain-tx-unpruned-lookups` — IaC-дім `deploy/grafana/alerts/silkennet-alerts.yaml`, 👤 import (S2.2). 🔴 Закриття тут було **ратчетом, не ремонтом**: усі три лічильники були коректні й мовчали правдиво — бракувало СПОЖИВАЧА, тож «метрика чиста» про них було порожнім твердженням. ⚠️ Асиметрія, що це запустила, варта запису: `w3bstream_signature_fallback_total` алертився, а сусідній `telemetry_ccm_mic_fail_total` — ні, при тому що його власний докстрінг називав ненульовий rate сигналом безпеки, вартим пейджа. Два `unpruned_lookups`-лічильники носили ГОТОВИЙ вираз правила у власному коментарі коду — і саме готовність тексту приховувала, що в yaml його немає.

**Gauges:**

| Metric | Labels | Призначення |
|---|---|---|
| `silkennet_blockchain_limbo_locked_total` | — | Sum of locked_points on unsettled (:sent/:manual_review) tx older than 1h (funds in limbo) |
| `silkennet_blockchain_manual_review_depth` | — | Count of BlockchainTransaction rows stuck in :manual_review (double-spend guard queue) |
| `silkennet_chain_audit_delta` | — | Absolute delta between DB SCC total (mints−burns) and on-chain totalSupply |
| `silkennet_cluster_entropy_score` | `cluster_id` | Normalized Shannon entropy of Z-value distribution per cluster (0.0-1.0) |
| `silkennet_cluster_tree_count_drift` | `cluster_id` | Live active-tree COUNT minus the denormalized active_trees_count (0 = in sync; nonzero means the slashing trigger measures a fabricated denominator) |
| `silkennet_db_pool_connections` | `database` | Number of active (checked out) database connections |
| `silkennet_db_pool_idle` | `database` | Number of idle database connections in the pool |
| `silkennet_db_pool_size` | `database` | Maximum number of connections in the database pool |
| `silkennet_db_pool_waiting` | `database` | Number of threads waiting for a database connection |
| `silkennet_ethereum_anchor_manual_review_depth` | — | Count of EthereumAnchor rows escalated to :manual_review (unconfirmed seal awaiting human check, ARCH.66) |
| `silkennet_ethereum_anchor_stuck_sent_depth` | — | Count of EthereumAnchor rows stuck in :sent past the confirmation-poll SLA (ARCH.66) |
| `silkennet_filecoin_unarchived_depth` | — | Count of archive-requested AuditLog rows still missing ipfs_cid (Filecoin archive backlog) |
| `silkennet_telemetry_archive_unpinned_depth` | — | [E.60 Фаза 1б] незапінені архів-батчі (pending/build_failed); семплить `Treasury::MonitorService` (15-хв). SLO-поріг «unpinned age < ретеншн-горизонт партицій» = 👤 калібрування ([`00_07`](00_07_Action_Plan_Tracker) E.60-residual) |
| `silkennet_gateway_attest_lapsed` | — | Online QATT-capable gateways whose last Ed25519-attested batch is older than the lapse window |
| `silkennet_gateways_faulty` | — | Current number of gateways in the faulty state (set on each staleness sweep) |
| `silkennet_hadron_kyc_pending_depth` | — | Count of Wallet+Organization rows with hadron_kyc_status=pending (KYC backlog gating mint) |
| `silkennet_mint_eligible_unminted_depth` | — | Wallets over the emission threshold that produced no mint in the last cycle (stall detector) |
| `silkennet_mint_volume_window_scc` | `token_type` | SCC/SFC BROADCAST (sent_at) in the trailing 1h window (ARCH.62 volume-anomaly detector input) |
| `silkennet_oracle_balance` | `network`, `signer` | Oracle wallet balance in native currency (wei/lamports) |
| `silkennet_oracle_balance_ratio` | `network`, `signer` | Oracle balance as ratio to minimum threshold (below 1.0 = critical) |
| `silkennet_partition_sample_timestamp_seconds` | — | [ARCH.70] Unix-час останнього успішного семплу росту — свідок СВІЖОСТІ двох гейджів нижче. Без нього обидва вакуумні: cron наповнює їх у живому процесі, тож зупинка воркера серію не прибирає, а ЗАМОРОЖУЄ, і алерти лишаються зеленими |
| `silkennet_partitioned_table_bytes` | `table` | [ARCH.70] Байти RANGE-таблиці разом з усіма партиціями, індексами й TOAST. Диск межею НЕ є (`disk_autoresize`) — це вісь ЦІНИ: PD_SSD, розмір 30 бекапів, час DR-відновлення ([`06_06`](06_06_Disaster_Recovery_and_Backup)) |
| `silkennet_partitions` | `table` | [ARCH.70] Листові партиції RANGE-таблиці. Монотонний ЗА ПОБУДОВОЮ (`DETACH`/`DROP PARTITION` у репо нуль), тож фактично дорівнює місяцям накопиченої сирої історії — вісь ⚖️ ширини вікна дропу |
| `silkennet_process_resident_memory_bytes` | — | Resident set size (RSS) of the scraped process in bytes (Linux /proc; 0 elsewhere) |
| `silkennet_puma_backlog` | — | Puma requests waiting for a free thread (backlog; sustained >0 = under-provisioned) |
| `silkennet_puma_max_threads` | — | Puma configured max threads (pool ceiling) |
| `silkennet_puma_pool_capacity` | — | Puma free thread-pool capacity (0 = saturated → requests queue in backlog) |
| `silkennet_puma_running_threads` | — | Puma worker threads currently spawned (busy + idle) |
| `silkennet_rpc_circuit_breaker_open` | `provider` | Whether RPC provider circuit breaker is open (1=open/disabled, 0=closed/healthy) |
| `silkennet_ruby_gc_count` | — | Total Ruby GC runs since process start (GC.stat[:count]) |
| `silkennet_ruby_gc_heap_live_slots` | — | Live objects on the Ruby heap (GC.stat[:heap_live_slots]); sustained growth = leak |
| `silkennet_ruby_gc_major_count` | — | Major Ruby GC runs since process start (GC.stat[:major_gc_count]) |
| `silkennet_ruby_threads` | — | Live Ruby threads in the process (Thread.list.size); sustained growth = thread leak |
| `silkennet_sidekiq_dead_set_size` | — | Current size of the Sidekiq DeadSet (jobs that exhausted all retries) |
| `silkennet_sidekiq_queue_latency_seconds` | `queue` | Latency (age of oldest job) in a Sidekiq queue |
| `silkennet_sidekiq_queue_size` | `queue` | Current size of a Sidekiq queue |
| `silkennet_trees_silent` | — | Current number of active trees silent beyond the silence threshold (set on each staleness sweep) |

**Histograms:**

| Metric | Labels | Призначення |
|---|---|---|
| `silkennet_lorenz_computation_duration_seconds` | — | Lorenz attractor server-side computation time (Float IEEE-754, 250 iterations) |
| `silkennet_oracle_dispatch_duration_seconds` | — | Chainlink oracle dispatch ATTEMPT latency in seconds — successful and failed alike [INF.26]; circuit-open refusals are excluded on purpose (our own breaker answers in microseconds and would drag p99 down) |

**Регенерація таблиці** (після зміни реєстру):
```bash
bin/rails runner 'SilkenNet::Metrics::REGISTRY.metrics.sort_by{|m|[m.type.to_s,m.name.to_s]}.each{|m| l=(m.instance_variable_get(:@labels)||[]).map{|x| "`#{x}`"}.join(", "); puts "| `#{m.name}` | #{l.empty? ? %(—) : l} | #{m.docstring} |"}'
```

---

### 2.9 Industrial-Grade Hardening (аналіз 2026-05-29)

Аудит чинного стеку (Grafana Alloy → Grafana Cloud) на production-grade зрілість. Архітектура **достатня** (WAL-буферизація, Basic Auth, всі 9 черг + повний реєстр §2.8); бракувало лише атрибуції та захисних гейтів — закрито нижче (`external_labels`, `queue_config`+explicit WAL, cardinality budget, CI-валідація, runtime-метрики).

**✅ Зроблено зараз (`config.alloy`):**
- **`external_labels`** на `remote_write` — `service` / `source` / `env` (з `RAILS_ENV`) / `release` (з `RELEASE_VERSION`). Без них серії з prod/canopy **та** з різних Akash-провайдерів (multi-provider failover, [`06_02`](06_02_Akash_Network_Integration)) зливаються в Grafana Cloud — неможливо скоупити дашборди/алерти за середовищем чи провайдером, ні відстежити регресію за релізом (корелює з Sentry `release`).
- **`scrape_timeout = 10s`** явно (< 15s interval).
- Header-коментар більше не дублює реєстр метрик — реф на §2.8 (DRY).
- **CI-gate `alloy_config_validate`** (`.github/workflows/ci.yml` → `CI · Code`) — `grafana/alloy:v1.16.3 fmt` парсить `config.alloy` (образ **запінено** — версія синхронна з SDL `deploy/akash/deploy.yaml`+`.tpl`; bump оновлює всі три разом, INF.14); **path-gated** під `alloy`-домен (`changes`-job: біжить коли чіпається `deploy/**`); River parse-error = **red CI замість crash-loop sidecar** на Akash-деплої.
- **`queue_config` + явний `wal`** на `remote_write` (`config.alloy`) — shard fan-out `1→50` + batch-sizing дають backpressure при сповільненні Grafana Cloud замість необмеженого росту пам'яті; WAL-вікно (~2h truncate) тепер явне й тюнабельне. Конкретні значення — у `config.alloy` (SSOT), тут не дублюються (drift).
- **Cardinality budget** (`config.alloy`, `prometheus.relabel`) — `labeldrop` per-identity міток (`did`/`tree_id`/`peaq_did`/`wallet_address`/`tx_hash`) перед `remote_write`. Реєстр (§2.8) свідомо bounded — єдина growth-вісь `cluster_id` (per-forest entropy) **лишається** легітимною; guard не дає випадковій майбутній per-DID мітці тихо підірвати active-series біллінг (Grafana Cloud біллить за series/DPM). Нульовий ефект сьогодні (таких міток нема) — стоячий запобіжник на write-boundary.
- **Process/runtime метрики** (`prometheus.rb` §2.9, 9 gauges) — Ruby VM/GC/RSS/Puma-threads, `sample_process_runtime!` на кожен scrape. **Bonus fix:** `sample_connection_pool!` тепер ВИКЛИКАЄТЬСЯ у `PrometheusCollector` (раніше визначений, але ніде не звався → DB-pool gauges були завжди 0/stale).
- **Multi-process scrape topology (2026-07-04, INF.14/INF.17).** Prometheus-реєстр — **in-process**: web:80 фізично не бачить інкрементів Sidekiq-воркерів (mint/slash/payout SLO, CCM/QATT-security, dead-man switch) та CoAP-демона — до цього фіксу всі ці серії були вічними нулями web-процесу, і жоден P0-алерт не міг спрацювати. Фікс: кожен процес віддає власний `/metrics` — job/coap піднімають embedded-експортер `SilkenNet::MetricsExporter` (Puma::Server + той самий `PrometheusCollector`; Sidekiq `on(:startup)` 9394 / демон 9395), Alloy скрейпить **три таргети** з лейблом `process` (`config.alloy`); порти 9394/9395 — service-scope only (`to: service: alloy` у SDL), web:80 отримав `- service: alloy` (без нього scrape впирався в публічний ingress → IP-allowlist 403). Queue/DeadSet-гейджі (Redis-глобальний факт) семплить лише job (`refresh_sidekiq_gauges if Sidekiq.server?`) — інакше три ідентичні серії = потрійний page; alert-вирази додатково max-обгорнуті. Демон-рівень статусів `coap_packets` (`enqueued`/`malformed`/`unknown_route`/`oversized` — трункейт ядром, який інакше маскується під MIC-fail «fraud») не перетинається з воркер-рівнем. Puma-API-дрейф ловить спека реальним HTTP (`spec/lib/silken_net/metrics_exporter_spec.rb`). **Свідомі стелі:** (а) web-процес у cluster-режимі (`WEB_CONCURRENCY>1`) фрагментує реєстр між форкнутими воркерами (scrape бачить один випадковий) — прийнятно, бо web-локальні лічильники рідкісні/некритичні; при потребі точності — `DirectFileStore` всередині web-контейнера (крос-контейнерно він не працює: у Akash нема спільних volumes між сервісами); (б) **PRIMARY CoAP-демон живе на Ingress Anchor** (INF.17, founder 2026-07-04) — Alloy сидить у Akash-deployment і його НЕ дістає: `coap:9395`-таргет скрейпить **Akash-fallback-сервіс** (idle → чесні нулі демон-рівня, поки fallback не активовано). Видимість анкор-демона: воркер-half лічильники `coap_packets` (job-таргет — success/decrypt/attest), INF.6 smoke-зонди (e2e байт-точні), Sentry (SENTRY_DSN у `coap.env`) і — з ARCH.81 — **UDP-проба адмін-панелі здоров'я** (`SilkenNet::HealthProbes.coap_listener`: той самий freeze-contract зонд, що й INF.6, але з веб-процесу на вимогу; адреса = `COAP_HOST`, незадана ⇒ чесний `not_configured`, ніколи «мертвий»); скрейп самого анкора (GCP-Alloy чи scrape-endpoint через firewall) — лише якщо стеля почне муляти.

**🟡 Рекомендований роадмеп (потребує валідації/ops, поза цим коммітом):**

| # | Покращення | Чому | Пріоритет |
|---|------------|------|-----------|
| 1 | ✅ **CI-валідація `config.alloy`** (2026-05-29) — CI job `alloy_config_validate` (`grafana/alloy fmt`, parse-check) | Раніше **ніщо** не лінтило River-конфіг; parse-error = crash-loop alloy-sidecar у проді ([`06_02`](06_02_Akash_Network_Integration)). Гейт ловить це до деплою | ✅ DONE |
| 2 | ✅ **`queue_config` + явний WAL** (2026-06-04) на `remote_write` (`config.alloy`) | Default WAL ~2h буферить аутейдж; `capacity`/`max_shards` (1→50)/`batch_send_deadline` дають backpressure замість необмеженого росту пам'яті; WAL-вікно явне | ✅ DONE |
| 3 | ✅ **Process/runtime метрики** (2026-05-29) — 9 gauges (RSS · GC count/major/heap_live · ruby_threads · Puma running/max/pool_capacity/backlog), sampled on-scrape (`sample_process_runtime!`) + 13 specs | Закрило сліпоту до memory leak / GC pause / thread saturation. Pure stdlib (GC.stat / Thread / /proc / Puma.stats) | ✅ DONE |
| 4 | ✅ **Cardinality budget** (2026-06-04) — `prometheus.relabel` `labeldrop` per-identity (`config.alloy`) | `cluster_id` (entropy) лишається (легітимна growth-вісь); per-DID labels (`did`/`tree_id`/`peaq_did`/`wallet_address`/`tx_hash`) дропаються до remote_write, щоб майбутня випадкова мітка не підірвала active-series біллінг (Grafana Cloud біллить за series / DPM) | ✅ DONE |
| 5 | ✅ **`up` scrape-health alert** (IaC 2026-07-04) — `sn-alert-scrape-target-down`: `min by (process) (up{job="silken_net_scraper"})` per-process називає, КОТРИЙ з трьох таргетів мертвий; `NoData → Alerting` = сам Alloy впав. Лишається 👤 імпорт (S2.4) | ops |
| 6 | 🟡 **SLO + error-budget** — mint-half ✅ (IaC 2026-07-04): `sn-alert-mint-slo-breach` <80%/1h (єдина канон-ціль — [`06_08 §2.4`](06_08_Resilience_and_Failover_Policy); PromQL-guard `and attempts>0`). Slash/payout/insurance ratios — пороги калібруються з перших live-вікон (00_07 S2.4), не вигадуються. **[ARCH.62]** `sn-alert-mint-volume-anomaly` (agg mint-volume ceiling ~MAX_SUPPLY, operator-калібрований) + per-token inert circuit-break | ops |
| 7 | Dashboards + alerts + **contact point** import у Grafana Cloud (IaC у `deploy/grafana/`) | S2.2 — IaC готовий; ✅ one-command `deploy/grafana/import.rb` (auto-discovery UID + ідемпотентний upsert + contact point/root notification policy з ENV off-by-default `ALERT_CONTACT_EMAIL`/`_TELEGRAM_*`, `--dry-run` без credentials); лишається 👤 запуск із токеном + значення каналу + verify | ops |

**#2 + #4 — імплементовано (2026-06-04) у `deploy/akash/config.alloy`:** pipeline `prometheus.scrape → prometheus.relabel.cardinality_budget → prometheus.remote_write` (queue_config + явний WAL). Значення живуть у `config.alloy` (SSOT) — тут не дублюються, щоб уникнути drift; rationale — рядки #2/#4 вище. Валідація: CI job `alloy_config_validate` (`grafana/alloy fmt`).

---

## 🪵 Частина III: Logs — GCP Cloud Logging

> ⚠️ **Scope: GCP/Kamal-шлях.** Ця частина описує Cloud Logging, куди тече stdout при деплої на GCP VM (Kamal). На **Akash** та сама фізика не працює: кожен Akash-`service` — окремий контейнер, Alloy-сайдкар не має доступу до stdout інших сервісів (нема kubelet/docker-сокета, поза lease-ізоляцією) → lease-логи ефемерні (виживають лише Sentry-exceptions). Закриття = Rails-HTTP-push у Grafana Cloud Loki (backend **§04**, НЕ Alloy-scrape) — tracked [`INF.22`](00_07_Action_Plan_Tracker), робити з першим Akash-деплоєм (TRL-3 = нуль логів для тюну).

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

### Поточний стан (TRL 6 — "Як є")

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
│  │  /metrics — ТРИ process-таргети (§2.9, INF.14/17):     │   │
│  │  web:80 (middleware) · job:9394 · coap:9395            │   │
│  │  (embedded SilkenNet::MetricsExporter; реєстр §2.8)    │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │ [Alloy scrapes кожні 15s]        │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Grafana Alloy (alloy сервіс в Akash SDL)              │   │
│  │  ✅ prometheus.scrape → 3 таргети, лейбл `process`     │   │
│  │  ✅ prometheus.remote_write → Grafana Cloud (HTTPS)     │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │                                   │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Grafana Cloud (SaaS)                                   │   │
│  │  ✅ Prometheus (зберігання метрик)                       │   │
│  │  🟡 Grafana Dashboards (операційна задача)              │   │
│  │  🟡 Grafana Alerting (операційна задача)                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Rails.logger → GCP Cloud Logging                       │   │
│  │  ✅ WARNING+ логи  ✅ Structured JSON (Sentry trace)    │   │
│  └─────────────────────────────────────────────────────────┘   │
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
│  /metrics endpoint ──────→ Grafana Alloy ──remote_write──→           │
│  (метрики §2.8, Basic Auth)  (Akash sidecar)             │           │
│                                                           ▼           │
│                                                    Grafana Cloud     │
│                                                    (dashboards +     │
│                                                     alerting)        │
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
| `config/initializers/prometheus.rb` | Визначення `SilkenNet::Metrics` (реєстр + кількість — §2.8) | ✅ |
| `app/middleware/prometheus_collector.rb` | Rack middleware: `/metrics` endpoint, IP allowlist, Basic Auth, Sidekiq gauge refresh | ✅ |
| `config/application.rb` | `config.middleware.use PrometheusCollector` | ✅ |
| `app/services/blockchain_minting_service.rb` | `SCC_MINTED_TOTAL.increment(labels: {token_type:})` | ✅ |
| `app/services/blockchain_burning_service.rb` | `SCC_SLASHED_TOTAL.increment(by: burn_amount)` — кумулятивна сума спалених токенів | ✅ |
| `app/workers/application_web3_worker.rb` | `RPC_ERRORS_TOTAL.increment(labels: {network:, error_type:})` | ✅ |
| `app/services/telemetry_unpacker_service.rb` | `TELEMETRY_FRAUD_DETECTED_TOTAL.increment`, `TELEMETRY_PROCESSED_TOTAL.increment` | ✅ |
| `app/workers/unpack_telemetry_worker.rb` | `Sentry.set_tags(gateway_uid:)` | ✅ |
| `app/workers/gateway_telemetry_worker.rb` | `Sentry.set_tags(queen_uid:)` | ✅ |
| `terraform/main.tf` | `google_project_service.monitoring` (Cloud Monitoring API) | ✅ (Cloud Monitoring) |
| `terraform/iam.tf` | `roles/monitoring.metricWriter` (для GCP-native метрик) | ✅ |
| `deploy/akash/deploy.yaml` | Akash SDL (web + job + alloy services, CoAP/UDP) | ✅ (з Alloy sidecar) |
| `deploy/akash/config.alloy` | Grafana Alloy конфігурація (scrape + remote_write) | ✅ Створено |
| `terraform/akash/variables.tf` | Grafana Cloud змінні (URL, username, token, auth) | ✅ 5 змінних |
| `terraform/akash/main.tf` | SDL generation + `filebase64(config.alloy)` | ✅ Alloy config injection |
| `prometheus.yml` (scrape config) | — | ✅ Замінено на `config.alloy` (Alloy agent) |
| `grafana/` (дашборди) | Grafana Cloud SaaS | 🟡 Операційна задача |
| `alertmanager.yml` | Grafana Cloud Alerting | 🟡 Операційна задача |

---

## 🔗 Зовнішні Залежності та ENV змінні

| ENV змінна | Обов'язкова | Де використовується | Статус |
|-----------|-------------|---------------------|--------|
| `SENTRY_DSN` | ✅ Для production | `config/initializers/sentry.rb` | ✅ Додано у `.kamal/secrets-common` |
| `SENTRY_TRACES_SAMPLE_RATE` | ❌ (default: 0.001) | `config/initializers/sentry.rb` | — |
| `SENTRY_WORKER_THREADS` | ❌ (default: 2) | `config/initializers/sentry.rb` | — |
| `RELEASE_VERSION` | ❌ (рекомендовано) | `config.release` | ✅ Додано у deploy.yml (git SHA), deploy-production.yml (release tag), config/deploy.yml (Kamal), deploy/akash/deploy.yaml |
| `PROMETHEUS_ALLOWED_IPS` | ❌ | `app/middleware/prometheus_collector.rb` | Не задана (RFC 1918 дозволені за замовчуванням — Akash internal network) |
| `PROMETHEUS_AUTH_USER` | ✅ (рекомендовано) | `app/middleware/prometheus_collector.rb`, Alloy `config.alloy` | ✅ Додано в web SDL env |
| `PROMETHEUS_AUTH_PASSWORD` | ✅ (рекомендовано) | `app/middleware/prometheus_collector.rb`, Alloy `config.alloy` | ✅ Додано в web SDL env |
| `GRAFANA_REMOTE_WRITE_URL` | ✅ Для production | `deploy/akash/config.alloy` (Alloy sidecar) | ✅ В Terraform variables |
| `GRAFANA_REMOTE_WRITE_USERNAME` | ✅ Для production | `deploy/akash/config.alloy` (Alloy sidecar) | ✅ В Terraform variables |
| `GRAFANA_REMOTE_WRITE_TOKEN` | ✅ Для production | `deploy/akash/config.alloy` (Alloy sidecar) | ✅ В Terraform variables (sensitive) |

---

## 📋 Висновки аудиту

### Що реально реалізовано (TRL 6 факти)

1. **Prometheus-client інтегрований** — повний реєстр метрик визначено (кількість — §2.8), `/metrics` endpoint працює з IP-захистом + Basic Auth.
2. **Sentry SDK встановлений і налаштований** — zero-noise конфігурація (набір виключень — SSOT `config/initializers/sentry.rb`), автоматична Sidekiq-інтеграція, PII-scrubbing.
3. **Інструментація в бізнес-логіці** — всі критичні операції (мінтинг, слешинг, RPC-помилки, телеметрія, OTA, EWS, CoAP) мають Prometheus-лічильники.
4. **GCP Cloud Logging** — WARNING+ логи зберігаються, cost-control фільтр активний.
5. **Structured JSON logging** — активовано у production: кожен рядок містить `timestamp`, `pid`, `request_id`, `sentry_trace_id`, `sentry_span_id`.
6. **Grafana Alloy sidecar** — `alloy` сервіс в Akash SDL скрейпить `/metrics` кожні 15s, пушить у Grafana Cloud через remote_write.

### Що залишилось (операційні задачі)

1. **Grafana Cloud дашборди** — створити в Grafana Cloud UI: Sidekiq queues, Web3 RPC errors, Telemetry ingest, Treasury.
2. **Grafana Cloud алерти** — створити правила алертів: `web3_critical` > 100, fraud rate > 0, RPC errors > 10/min.
3. **Notification channels** — налаштувати Email / PagerDuty у Grafana Cloud.

### Наступні кроки

1. ✅ Prometheus Server — вирішено через Grafana Alloy → Grafana Cloud.
2. ✅ Grafana — вирішено через Grafana Cloud SaaS.
3. ✅ Alertmanager — вирішено через Grafana Cloud Alerting.
4. 🟡 **Створити дашборди** — операційна задача в Grafana Cloud UI.
5. 🟡 **Створити алерти** — операційна задача в Grafana Cloud UI.

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
3. **Thread-safe** — Критично для Sidekiq workers (15 потоків × 9 черг; SSOT числа — `config/sidekiq.yml`).
4. **Кастомні метрики** — Нам потрібні domain-specific counters (`scc_minted_total`, `rpc_errors_total`), а не generic Rails request histograms. Авто-інструментація Yabeda додає шум.
5. **Rails 8.1 native** — Працює з `ActiveSupport::Notifications`. Немає конфліктів з framework.
6. **Без Redis залежності** — Метрики живуть у пам'яті процесу. Без зайвої інфраструктури.
