# 06_03: Спостережуваність Prometheus (Метрики, Grafana, Alerting)

## 🎯 Мета

Зафіксувати стек спостережуваності (Observability): які інструменти збору помилок (Sentry) та метрик (Prometheus) реально імплементовані в коді, які кастомні бізнес-метрики збираються, і чи існує конфігурація для їх збору та візуалізації (Prometheus Server, Grafana).

Документ чітко розділяє три шари спостережуваності:

| Шар | Інструмент | Статус |
|-----|------------|--------|
| **APM / Error Tracking** | Sentry | ✅ Реалізовано в коді |
| **Time-series / Metrics** | Prometheus (`prometheus-client`) + Grafana Alloy | ✅ `/metrics` endpoint існує, ✅ Alloy scrapes + remote_write → Grafana Cloud |
| **Logs** | GCP Cloud Logging + Structured JSON | ✅ GCP/Kamal-шлях (Cloud Logging, WARNING+, JSON+Sentry correlation); ⊕ **[OPS.37] Друга гілка знята разом із платформою:** мотив Rails-push у Loki був саме «ефемерний lease-log»; на GCP-VM stdout тече в Cloud Logging штатно, тож питання Loki звузилось до ретенції й пошуку ([`INF.22`](00_07_Action_Plan_Tracker)) |
| **Visualization** | Grafana Cloud | ✅ **Імпортовано 2026-08-29** — дашборд `silkennet-overview-v1` у стеку (folder `SilkenNet`) |
| **Alerting** | Grafana Cloud Alerting | ✅ **Імпортовано 2026-08-29** (⚠️ стек `violetmamba3330.grafana.net` — free trial 14 днів від 2026-08-30, далі ліміти free-тарифу: єдиний годинник, що цокає БЕЗ нашого коміту; ліміт правил проти імпортованого ЗВІРЕНО 2026-09-02 — §2.9 📏: Free = 500 правил, наших 58, запас ≈×8; дата кінця trial — ОДИН дім, §2.9 📏, тут свідомо не дублюється: рядок несе маркер завершення, тож майбутня дата в ньому непредставна за оголошеною стелею `no_future_dated_claims_spec`); ✅ **contact point (Email) + route `slot=canopy` задротовано 2026-08-30** — firing-правила доставляються founder-у (заміна каналу на `ops@` — після ESP; [`00_07`](00_07_Action_Plan_Tracker) S2.4: ✅ переімпорт і post-deploy verify ЗАКРИТО 2026-09-03 — `58/58 evaluated, 0 error`, знято НАД метриками з даними; відкрите там тепер інше — ⚖️ SLO-пороги і 👤 зняття silence) |

---

## ✅ Статус

- **Поточний TRL:** TRL 6 — бібліотеки встановлені, кастомні метрики реалізовані та інструментовані (повний реєстр — §2.8; парність реєстру з кодом тримає гейт, не лічильник у прозі), структуровані JSON-логи активні; Grafana Alloy sidecar налаштований для scrape + remote_write до Grafana Cloud (Grafana Cloud SaaS, OBS.1); TRL 7 підтверджується після першого реального деплою з метриками в Grafana Cloud
- **Відкрите:** перший деплой з метриками в Grafana Cloud (TRL 6→7). ⊕ **Імпорт дашборда й правил ЗРОБЛЕНО 2026-08-29; канал доставки задротовано 2026-08-30** (Email founder-а + route `slot=canopy`); лишаються переімпорт виправлених правил і post-deploy verify → [`00_07`](00_07_Action_Plan_Tracker) (OBS.1, S2.4).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | Розгортання (Kamal/Terraform) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (інструментовані метрики) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | OBS.1 (Grafana Cloud), S2.4 (verify + канал; `S2.2`-імпорт ✅ 2026-08-29 → §🗄️) |

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
| Prometheus Server | `config/deploy.yml` (accessory `alloy`) | ✅ **Grafana Alloy → Grafana Cloud** |
| Grafana | Grafana Cloud SaaS | ✅ **Дашборд імпортовано 2026-08-29** (`ruby deploy/grafana/import.rb`) |
| Alertmanager | Grafana Cloud Alerting | ✅ **Правила імпортовано 2026-08-29**; ✅ канал доставки задротовано 2026-08-30 (Email; ⚖️ таймінг перевернув сам founder — Grafana Cloud має вбудований sender, ESP не потрібен; [`00_07`](00_07_Action_Plan_Tracker) S2.4) |
| `SENTRY_DSN` у secrets | `.kamal/secrets-common` | ✅ Додано |
| Grafana Alloy config | `deploy/alloy/config.alloy` | ✅ Scrape + remote_write |
| Grafana Alloy accessory | `config/deploy.yml` (`accessories.alloy`) | ✅ монтування `files:`; ✅ мережевий доступ до таргетів ратифіковано 2026-08-30 (⚖️ OPS.37: адресація per-role `network-alias`, носій `spec/deploy/alloy_scrape_topology_spec.rb`); `network:` у конфізі свідомо НЕМАЄ |
| Grafana Cloud secrets | `.kamal/secrets-common` + обидва deploy-workflow (RUNTIME-тір) | ✅ 3 змінні |
| Prometheus scrape config | `deploy/alloy/config.alloy` | ✅ 5 таргетів: 3 production `silken-web:80`/`silken-job:9394`/`silken-coap:9395` + 2 canopy `canopy-web:80`/`canopy-job:9394` зі `slot = "canopy"` НА ТАРГЕТІ (⚖️ founder 2026-09-03 — target-мітка бере гору над `external_labels`, тож canopy-серії їдуть як slot=canopy, а `silken-*` тримають production-мітку єдиного агента; лейбл `process`; реєстр in-process — §2.9; ⚖️ [OPS.37 2026-08-30] адресація = per-role `network-alias` у спільній docker-мережі `kamal` — механіка й виміряна rolling-поведінка в ноті web-ролі `config/deploy.yml`; `coap` = дормантна Kamal-**fallback**-роль — PRIMARY-демон на Ingress Anchor поза scrape, стеля §2.9(б); 15s, Basic Auth опційний обабіч) |
| Grafana dashboards | `deploy/grafana/` IaC → `import.rb` | ✅ 2026-08-29 (звірка — `import.rb --verify`) |

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
| `config.environment` | `SilkenNet::DeploymentSlot.current` | СЛОТ, не `Rails.env` — обидва слоти біжать під `RAILS_ENV=production` [INF.27]; виміряно на живому canopy 2026-09-02 (`environment: canopy`) |
| `config.release` | `ENV["RELEASE_VERSION"].presence \|\| ENV["KAMAL_VERSION"].presence` | Git sha, який Kamal інжектить у кожен контейнер сам; `RELEASE_VERSION` — лише явний оверрайд для не-Kamal процесів. 🔴 Доти `env.clear` ніс `"${RELEASE_VERSION}"`, і ВІДДАЛЕНИЙ shell (Kamal передає `env.clear` як `--env` у `docker run` через ssh) розгортав його в порожній рядок — Sentry відкидав release на КОЖНІЙ події (виміряно 2026-09-02, «expected a non-empty string»); `.presence` закриває клас present-but-empty [S2.4] |
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
| Canopy (staging) | Працює під `RAILS_ENV=production` (НЕ окремий Rails-env); активний, `SENTRY_DSN` присутній. 🔴 **У Sentry canopy від прода НЕ відрізняється — виправлено 2026-08-29**: доти цей рядок посилався на `external_labels env/release`, тобто на мітки **Prometheus**, яких Sentry-подія не несе взагалі; до того ж `env` там КОНСТАНТА (`RAILS_ENV` = production в обох слотах), а `release` **не емітиться** — `RELEASE_VERSION` відсутній в `accessories.alloy.env`, тож мітка дропається як порожня. ✅ **Дискримінатор ЖИВИЙ з [INF.27]: `config.environment = SilkenNet::DeploymentSlot.current`** — на живому canopy Sentry показує `environment: canopy`, `server_name` = app-хост (виміряно 2026-09-02). ⚠️ Того ж виміру `release` був ПОРОЖНІЙ і Sentry його відкидав — лік у §1.2 (`KAMAL_VERSION`) |
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
| `silkennet_rpc_errors_total` | `SilkenNet::Metrics::RPC_ERRORS_TOTAL` | `network`, `error_type` (timeout, connection) | `ApplicationWeb3Worker` (4 точки) | Кожна RPC-помилка по всіх 11 блокчейн-мережах |
| `silkennet_telemetry_processed_total` | `SilkenNet::Metrics::TELEMETRY_PROCESSED_TOTAL` | — | `TelemetryUnpackerService` | Кожен успішно оброблений telemetry chunk |
| `silkennet_telemetry_fraud_detected_total` | `SilkenNet::Metrics::TELEMETRY_FRAUD_DETECTED_TOTAL` | — | `TelemetryUnpackerService` (2 точки) | Відхилені пакети (sensor noise, unknown DID, tamper) |
| `silkennet_panic_replay_rejected_total` | `SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL` | — | `TelemetryUnpackerService` (SEC.10 panic Frame Counter) | **[SEC.10]** Panic-пакети відкинуті як replay через SETNX-nonce у Rails.cache (Solid Cache/PostgreSQL, не Redis — [ARCH.105]). Сторожовий пес панічного каналу — кожен сплеск тут означає або legitimate retransmission (LoRa duplicate) або replay-attack. Grafana alert при різкому стрибку → можливий attacker injection forged panic packets. |
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

> Проміжний підсумок видалено — див. фінальну цифру у §2.8 (SSOT).

### 2.4.1 RSpec покриття нових метрик (S2.4 — Виконано)

> Конвенції написання / coverage-гейт / тріаж — [`04_06`](04_06_Testing_Guide_and_Coverage) (Testing Guide). Нижче — per-subsystem інвентар тестів метрик (One-Home: біля підсистеми; example-counts навмисно не фіксуються — volatile).

| Spec файл | Метрика | Що перевіряється |
|-----------|---------|------------------|
| `spec/initializers/prometheus_spec.rb` | нові метрики | Реєстрація, інкрементування, доступність констант, label validation |
| `spec/workers/burn_carbon_tokens_worker_spec.rb` | `SLASHING_EVENTS_TOTAL` | Інкремент по reason — міток **ТРИ**: `contractual_forfeiture` ⊥ `tree_death` ⊥ `cluster_degradation` ([SLASH-1] 2026-08-29: доти добровільний вихід замовника йшов на панель як `cluster_degradation`, тобто як провина оператора — дискримінатор існував у сервісі й сюди не доїжджав). ⚠️ Клауза «не інкрементується при breached» знята 2026-09-04 як спростована: вона описувала гард `return if status_breached?`, який той самий фікс замінив на перевірку settled burn-інтенту |
| `spec/workers/ota_transmission_worker_spec.rb` | `OTA_CHUNKS_SENT_TOTAL` | Інкремент при успішній передачі, не інкрементується при failure, послідовна передача |
| `spec/workers/dclimate_verification_worker_spec.rb` | `EWS_ALERTS_TOTAL` | Інкремент при успішній верифікації, не інкрементується при falsey/verified/not found |
| `spec/workers/chainlink_dispatch_worker_spec.rb` | `ORACLE_DISPATCH_DURATION` | Histogram observation, не observe при skip/not found |
| `spec/workers/unpack_telemetry_worker_spec.rb` | `COAP_PACKETS_RECEIVED_TOTAL` | Статуси: success, unknown_device, decrypt_error; ізоляція між статусами |

### 2.5 Додаткові метрики

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

**Grafana Alert Rule:** `sn-alert-cluster-entropy` (`< 0.65`, for 30m) — IaC-дім `deploy/grafana/alerts/silkennet-alerts.yaml`, ✅ імпортовано 2026-08-29.

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

**Grafana Alert Rules:** `sn-alert-acoustic-overflow` (`rate(...[5m]) > 0`, for 5m) та `sn-alert-circuit-breaker` (`> 0`, for 2m) — IaC-дім `deploy/grafana/alerts/silkennet-alerts.yaml`, ✅ імпортовано 2026-08-29. ⊕ Сусід по тому ж проходу — `sn-alert-ccm-mic-fail` (FW.2 CCM MIC-fail, дротований 2026-08-26): його єдина канон-згадка жила в цьому абзаці й ледь не зникла при переписі §2.8. Споріднений firmware-**діагностичний за ПРЕДМЕТОМ** counter `silkennet_tinyml_threshold_invalid_reports_total` (FW.18b, той самий патерн warn-лог-атрибуції) і його `sn-alert-tinyml-threshold-invalid` — ⚠️ слово тут про ПРИРОДУ сигналу, а не про **ярус** реєстру нижче: за ярусом ця метрика **алертна** (споживач у неї є). Той самий токен у двох доменах, тож не читай його як декларацію — канон [`03_03 §5.4`](03_03_TinyML_Acoustic_Inference).

### 📊 Канонічний реєстр метрик (SSOT)

> **ЄДИНЕ авторитетне джерело переліку + кількості метрик** — згенеровано з
> `SilkenNet::Metrics::REGISTRY`, verified vs `config/initializers/prometheus.rb`
> 2026-07-19 (додано SILENCE-1 tree-silence пару — dead-man switch Солдата;
> раніше 07-04: GOV.1 bounds-reject + E.60 sweep counters + дожим 3 gauge-дрейфів). Усі інші
> згадки (CLAUDE.md, `config.alloy`, підсекції §2.3–2.7 з обґрунтуванням/alert-прикладами)
> **рефлять сюди**, не дублюють число/перелік.
> При зміні реєстру в коді — **регенерувати таблиці скриптом** (`ruby scripts/metric_registry_table.rb --write`; повний рецепт і його межі — нижче, під таблицями).
> Де інкрементується/оновлюється кожна — `grep -rn "SilkenNet::Metrics::<CONST>" app/`.
>
> **Кількість тут свідомо НЕ записана числом** (⚖️ 2026-08-25, INF.26). Реєстр — це таблиці нижче, і рівно вони гейтовані `metric_registry_doc_sync_spec` (імена + типи, обидва напрямки; з 2026-08-29 — ще й **ярус**, див. врізку нижче). А речення-підсумок гейта не має за побудовою, тож воно й протухло: цей рядок роками стверджував «79 = 45+32+2», доки таблиці під ним регенерувались до 86 = 48+36+2 — тобто секція, яка називає себе **єдиним авторитетним джерелом кількості**, була єдиним місцем, де кількість брехала. Порахувати завжди: `bin/rails runner 'puts SilkenNet::Metrics::REGISTRY.metrics.size'`, або просто прочитати таблиці.

### 🎚️ Два яруси реєстру (⚖️ founder, 2026-08-29 — INF.26)

Кожна метрика належить до одного з двох ярусів, і різниця в **ОБОВʼЯЗКУ**, не у важливості:

| Ярус | Обовʼязок | Як оголошується |
|---|---|---|
| **алертна** | мусить мати **споживача** — alert-правило в `deploy/grafana/alerts/` **або** панель у `deploy/grafana/dashboards/` | дефолт: маркера не несе |
| **діагностична** | споживача мати не мусить | маркер у власному докстрінгу: `[<ID>; diagnostic tier: <подія дротування>]` |

**Що це купує.** Доти будь-яке твердження «ця метрика чиста» про метрику без споживача було **порожнім**: її ніхто не читає, тож і брехати їй нема перед ким. Декларація перетворює «без споживача» з **дефекту** на **оголошений стан** — і тоді гейт судить наявність ДЕКЛАРАЦІЇ, а не наявність алерту. Це лік класу «тихий дефолт»: ні масової чистки (втратили б корисний діагностичний сигнал), ні масового дротування (народили б два десятки алертів, яких ніхто не читає — рівно гейт, що ні на чому не падає, [`00_05 §5`](00_05_AI_Native_Operating_Model)).

🔑 **«Споживач», а не «алерт» — і це несуче.** Чимало метрик живуть лише на панелях (обсяг, пул, GC), і це здоровий стан; вимога саме алерту зробила б декларацію обовʼязковою для більшості з них. ⚠️ Отже мітка «алертна» означає «**мусить мати читача**», а не «має алерт-правило» — той самий токен у двох доменах, і плутати їх тут дорого.

🔴 **Подія дротування обовʼязкова, бо саме вона робить виняток ЗВОРОТНИМ.** Декларація без названої події означає «назавжди», а такого ярусу присуд не вводив. Гейт вимагає непорожню подію — але судить її **наявність, ніколи настання**: `back`-умова є передбаченням, і протухлий виняток виглядає точно як живий (`ssot-maintenance` §Guard-craft #53). Перечитувати їх — робота ревʼювера, не машини.

⛔ **Декларація легітимна ЛИШЕ там, де питання справді немає.** Реєстр енфорсить **паритет, ніколи законність** (§Guard-craft #74): на грошовому, слешинговому, MRV-доказовому чи безпековому шляху «діагностична» **узаконює діру**, і гейт не відрізнить її від чесної. Виміряно на цьому ж проході: `lineage_root_failures_total` (кредит виданий, а witness-корінь NULL) і `fw2_fc_degraded_reports_total` (nonce-гарантія пристрою відпала, прошивка передає далі) обидва спокусливо читались як «діагностичні» — і обидва дістали споживача.

Носій — `spec/quality/metric_registry_doc_sync_spec.rb` (чотири осі: споживач ⊥ протухла декларація ⊥ названа подія ⊥ парність колонки `Ярус`); колонка виводиться з докстрінгів скриптом регенерації, руками її не правлять.

**Counters:**

| Metric | Ярус | Labels | Призначення |
|---|---|---|---|
| `silkennet_actuator_stuck_recovered_total` | діагностична | `device_type` | Actuators found recorded active past their command window and reset by the safety sweep |
| `silkennet_anchor_missed_weeks_total` | алертна | — | Total missed Ethereum L1 anchor weeks detected (gap > 8 days) |
| `silkennet_blockchain_transaction_unpruned_lookups_total` | алертна | `caller` | Total BlockchainTransaction lookups without partition pruning (degraded path; missing or invalid created_at) |
| `silkennet_circuit_breaker_rejections_total` | діагностична | `service` | Web3 requests fast-failed because a provider circuit breaker was open |
| `silkennet_coap_packets_received_total` | алертна | `status` | Total CoAP UDP packets received by the telemetry daemon |
| `silkennet_dclimate_verification_total` | алертна | `result` | Total dClimate satellite verdicts by terminal result — [INF.26] вісь ГРОШОВА обабіч (`verified` → InsurancePayoutWorker, `rejected_fraud` → BurnCarbonTokensWorker, `inconclusive` → людський/DAO-вердикт); дім лічби — `EwsAlert.after_update_commit`, бо термінальних писачів `satellite_status` чотири й один із них у `sidekiq_retries_exhausted` воркера |
| `silkennet_dynamic_tax_collected_total` | діагностична | `token_type` | Dynamic Tax actually broadcast to DAO_TREASURY (SCC) — numerator of the EFFECTIVE tax rate |
| `silkennet_ethereum_anchor_reverted_total` | алертна | — | EthereumAnchor storeStateRoot txs that reverted on-chain (ARCH.66) |
| `silkennet_ews_alerts_total` | діагностична | `alert_type` | Total EWS alerts created — [INF.26] «created», бо інкремент живе в `after_create_commit`; доставка ([`ARCH.60`](00_07_Action_Plan_Tracker)) — окрема подія й власного лічильника не має |
| `silkennet_fauna_skip_reports_total` | алертна | — | FW.42 telemetry packets reporting a fauna session skipped on low Vcap (per-DID attribution in logs) |
| `silkennet_filecoin_archive_exhausted_total` | діагностична | — | FilecoinArchiveWorker jobs that exhausted all retries (archive landed in Dead Set) |
| `silkennet_filecoin_repin_total` | діагностична | — | AuditLog archive re-enqueues issued by FilecoinReconcileWorker |
| `silkennet_filecoin_verification_failures_total` | алертна | `reason` | Filecoin archive integrity verification failures (E.60 sweep) |
| `silkennet_fw2_fc_degraded_reports_total` | алертна | — | FW.2 telemetry packets reporting a lost FC high-water invariant (Flash refusing writes; per-DID attribution in logs) |
| `silkennet_gateways_offline_total` | алертна | — | Total gateway offline transitions detected by the staleness sweeper (queen_offline alerts) |
| `silkennet_governance_param_rejected_total` | алертна | `parameter` | Governance parameter syncs rejected by bounds validation |
| `silkennet_helium_sos_received_total` | алертна | `outcome` | Queen SOS frames received via the Helium webhook, by processing outcome |
| `silkennet_insurance_payout_attempts_total` | алертна | — | Parametric insurance payouts attempted by InsurancePayoutWorker (SLO denominator) |
| `silkennet_insurance_payout_success_total` | алертна | — | Parametric insurance payouts BROADCAST — Etherisc claim sent / internal mint status→sent (SLO numerator) |
| `silkennet_insurance_reserve_hold_total` | алертна | `reason` | Internal-mode виплати, зупинені reserve-gate [INS.2]. ⚖️ ARCH.82: **ЄДИНИЙ канал** — парний `EwsAlert` пишеться без кластера, тож орг-поверхні його не бачать за побудовою. Окремо від `manual_review_depth` навмисно: той не розрізняє казначейську політику від double-spend-лімбо, а відповіді протилежні. ⚠️ Штатно нуль до калібрування порогів INS.2; `:eval_error` сюди НЕ рахується (transient RPC → Sidekiq-retry) |
| `silkennet_iotex_backfill_rearmed_total` | алертна | — | TelemetryLogs re-armed for IoTeX verification by the backfill sweep (sustained-outage recovery; a healthy tract leaves this at zero) |
| `silkennet_peaq_backfill_rearmed_total` | діагностична | — | Дерева, ре-армовані `PeaqBackfillWorker` на peaq-DID реєстрацію [ARCH.119]. ⚠️ Ярус оголошено, а не заслужено алертом: нога activation-gated, `PEAQ_*` не стоять на жодній деплой-поверхні, тож лічильник **нуль за побудовою** — споживача дротуємо, коли ключі зʼявляться |
| `silkennet_lineage_root_failures_total` | алертна | — | Mint lineage Merkle-root computation failures (fail-open, root left NULL) |
| `silkennet_m2m_nonce_fallback_total` | алертна | — | Total M2M nonce checks falling back from Redis to DB-backed cache (Redis outage indicator) |
| `silkennet_mint_attempts_total` | алертна | `token_type` | Mint transactions attempted by BlockchainMintingService (SLO denominator) |
| `silkennet_mint_chunk_errors_total` | алертна | — | Per-wallet mint failures swallowed by EvaluateTreeBatchWorker (job still reports success) |
| `silkennet_mint_success_total` | алертна | `token_type` | Mint transactions successfully broadcast to mempool — status→sent (SLO numerator) |
| `silkennet_ota_chunks_sent_total` | діагностична | `firmware_version` | Total OTA firmware chunks transmitted to field devices |
| `silkennet_panic_replay_rejected_total` | алертна | — | Panic packets rejected as replay via SEC.10 Frame Counter SETNX nonce |
| `silkennet_partition_maintenance_failures_total` | алертна | — | PartitionMaintenanceWorker run failures (missing partition → rows silently land in the _default leaf, which then blocks CREATE PARTITION for that month permanently) |
| `silkennet_qatt_nonce_fallback_total` | алертна | — | Total Queen-attestation batch nonce checks falling back from Redis to DB-backed cache (Redis outage indicator) |
| `silkennet_rate_limit_store_errors_total` | алертна | — | **[INF.22]** Операції cache-store'у Rack::Attack, проковтнуті failsafe'ом `RedisCacheStore`. 🔴 Не деградація, а ВІДСУТНІСТЬ щита: фолбеку тут немає, `nil`-читання невідрізненне від «нуль страйків», тож throttle не рахує й fail2ban не банить — мовчки, з порожнім логом. ⛔ Ярус НЕ діагностичний і не сміє ним стати (безпековий шлях — [INF.26] судить, що там декларація узаконює діру). Споживач — `sn-alert-rate-limit-store-errors`; писач — `error_handler` у `config/initializers/rack_attack.rb`. ⚠️ **Лічильник ПО-ВОРКЕРНИЙ, і це псує ЧИСЛО в анотації, не сам вердикт:** реєстр in-process, а web-роль форкає `WEB_CONCURRENCY` воркерів без спільного сховища, тож `increase(...[1h])` читає перехід між воркерами як reset+delta й завищує. Вердикт (`> 0`) вистоює — при збої Redis помиляються ВСІ воркери, поріг перетинається однаково, — але людина, що прийде за анотацією, побачить не ту величину. 🔑 Це та сама вісь, що три scrape-таргети нижче, лише на рівень глибше: там процес⊥процес, тут воркер⊥воркер УСЕРЕДИНІ одного таргета. ⊕ І окремо: `error_handler` тут **ПЕРЕКРИВ** дефолтний `RedisCacheStore::DEFAULT_ERROR_HANDLER`, отже вся видимість цього класу висить на ОДНОМУ цьому правилі (підстава — шапка `rack_attack.rb`). 🔴 **Але «…який робив `error_reporter.report` → Sentry» СПРОСТОВАНО 2026-08-31 і знято:** дефолт справді кличе `ActiveSupport.error_reporter&.report`, однак `sentry-rails` тримає `register_error_subscriber = false` за замовчуванням і ми його не вмикаємо, тож у НАШОМУ застосунку той виклик фанився в порожній список підписників — тихий no-op без логер-фолбеку. Тобто до перекриття клас був лог-only й НЕалертований, а перекриття є **приростом** видимості, не розміном; правило «перекриття ≠ доповнення» лишається, приклад був хибний ([`00_07`](00_07_Action_Plan_Tracker) INF.22) |
| `silkennet_rpc_errors_total` | алертна | `network`, `error_type` | Total Web3 RPC errors |
| `silkennet_scc_minted_total` | алертна | `token_type` | Total SCC (SilkenCarbonCoin) tokens minted |
| `silkennet_scc_slashed_total` | алертна | — | Total tokens slashed (burned due to cluster stress) |
| `silkennet_slash_attempts_total` | алертна | — | Slash transactions attempted by BlockchainBurningService (SLO denominator) |
| `silkennet_slash_success_total` | алертна | — | Slash transactions successfully broadcast — status→sent (SLO numerator) |
| `silkennet_slashing_events_total` | алертна | `reason` | Total slashing (burn) events by reason |
| `silkennet_solana_payout_attempts_total` | алертна | — | Solana batch payouts attempted by BatchPayoutService (SLO denominator) |
| `silkennet_solana_payout_success_total` | алертна | — | Solana batch payouts successfully broadcast — status→sent (SLO numerator) |
| `silkennet_telemetry_acoustic_overflow_total` | алертна | — | Total telemetry packets with acoustic_events=255 (uint8 saturation) |
| `silkennet_telemetry_archive_batch_failures_total` | алертна | `reason` | [E.60 Фаза 1б] збої архів-тракту по фазах: `build` (fail-open → zero32-мінт; при непорожніх вікнах = кандидат-інцидент) · `pin` (exhausted-hook) · `mismatch` (rebuild ≠ root при живих логах — integrity, runbook 06_08 §4.7) · `retention_expired` · `dispatch_drift` · `leaf_stamp_drift` (sweeper-семпл) |
| `silkennet_telemetry_ccm_decrypt_ok_total` | діагностична | — | FW.2 CCM packets successfully decrypted with valid MIC |
| `silkennet_telemetry_ccm_fc_replay_rejected_total` | алертна | — | FW.2 CCM packets rejected because per-DID Frame Counter was not strictly increasing |
| `silkennet_telemetry_ccm_mic_fail_total` | алертна | — | FW.2 CCM packets rejected due to MIC verification failure |
| `silkennet_telemetry_fraud_detected_total` | алертна | — | Total telemetry packets rejected (sensor noise, unknown DID, tamper) |
| `silkennet_telemetry_log_unpruned_lookups_total` | алертна | `caller` | Total TelemetryLog lookups without partition pruning (degraded path; missing or invalid ISO8601 created_at_iso) |
| `silkennet_telemetry_processed_total` | алертна | — | Total telemetry chunks processed by TelemetryUnpackerService |
| `silkennet_tinyml_threshold_invalid_reports_total` | алертна | — | FW.18b telemetry packets reporting a nonzero rejected-OTA-thresholds counter (per-DID attribution in logs) |
| `silkennet_treasury_check_errors_total` | алертна | `network`, `signer`, `error_type` | Total treasury monitoring RPC errors |
| `silkennet_tree_silence_total` | діагностична | — | Total tree silence transitions detected by the staleness sweeper (per-tree field_audit escalations) |
| `silkennet_w3bstream_signature_fallback_total` | алертна | `reason` | Telemetry with no usable HardwareKey — SHA256 fallback in dev, fail-closed rejection in production. ⚠️ [INF.26] Лічильник міряє ПЕРЕДУМОВУ, не наслідок: інкремент стоїть ДО розвилки prod/dev, тож ім'я (`_fallback_`) вужче за подію — у проді той самий рядок означає ВІДМОВУ. Перенести інкремент у dev-гілку не можна: осліпли б саме там, де сигнал найпотрібніший |
**Gauges:**

| Metric | Ярус | Labels | Призначення |
|---|---|---|---|
| `silkennet_blockchain_limbo_locked_total` | алертна | — | Sum of locked_points on unsettled (:sent/:manual_review) tx older than 1h (funds in limbo) |
| `silkennet_blockchain_manual_review_depth` | алертна | — | Count of BlockchainTransaction rows stuck in :manual_review (double-spend guard queue) |
| `silkennet_chain_audit_delta` | алертна | — | Absolute delta between DB SCC total (mints−burns) and on-chain totalSupply |
| `silkennet_cluster_entropy_score` | алертна | `cluster_id` | Normalized Shannon entropy of Z-value distribution per cluster (0.0-1.0) |
| `silkennet_cluster_tree_count_drift` | алертна | `cluster_id` | Live active-tree COUNT minus the denormalized active_trees_count (0 = in sync; nonzero means the slashing trigger measures a fabricated denominator) |
| `silkennet_db_pool_connections` | алертна | `database` | Number of active (checked out) database connections |
| `silkennet_db_pool_idle` | алертна | `database` | Number of idle database connections in the pool |
| `silkennet_db_pool_size` | алертна | `database` | Maximum number of connections in the database pool |
| `silkennet_db_pool_waiting` | алертна | `database` | Number of threads waiting for a database connection |
| `silkennet_ethereum_anchor_manual_review_depth` | алертна | — | Count of EthereumAnchor rows escalated to :manual_review (unconfirmed seal awaiting human check, ARCH.66) |
| `silkennet_ethereum_anchor_stuck_sent_depth` | алертна | — | Count of EthereumAnchor rows stuck in :sent past the confirmation-poll SLA (ARCH.66) |
| `silkennet_filecoin_unarchived_depth` | алертна | — | Count of archive-requested AuditLog rows still missing ipfs_cid (Filecoin archive backlog) |
| `silkennet_gateway_attest_lapsed` | алертна | — | Online QATT-capable gateways whose last Ed25519-attested batch is older than the lapse window |
| `silkennet_gateways_faulty` | алертна | — | Current number of gateways in the faulty state (set on each staleness sweep) |
| `silkennet_hadron_kyc_pending_depth` | алертна | — | Count of Wallet+Organization rows with hadron_kyc_status=pending (KYC backlog gating mint) |
| `silkennet_mint_eligible_unminted_depth` | алертна | — | Wallets over the emission threshold that produced no mint in the last cycle (stall detector) |
| `silkennet_mint_volume_window_scc` | алертна | `token_type` | SCC/SFC BROADCAST (sent_at) in the trailing 1h window (ARCH.62 volume-anomaly detector input) |
| `silkennet_oracle_balance` | алертна | `network`, `signer` | Oracle wallet balance in native currency (wei/lamports) |
| `silkennet_oracle_balance_ratio` | алертна | `network`, `signer` | Oracle balance as ratio to minimum threshold (below 1.0 = critical) |
| `silkennet_partition_default_occupied` | алертна | `table` | [ARCH.70] `1` = DEFAULT-лист таблиці тримає бодай один рядок. **Не вісь росту, а вісь ПОЛОМКИ:** такий рядок назавжди блокує `CREATE ... PARTITION OF` для свого місяця (`PG::CheckViolation`), ретраї не лікують, і прохід воркера падає щодня — а разом із ним замерзають два гейджі нижче, бо семпл стоїть ПІСЛЯ циклу. Величина свідомо бінарна (`EXISTS`, не `count`): рішення оператора не залежить від кількості, а скан розрослого DEFAULT коштував би саме в інциденті. `0` = очікуване здоровʼя; рунбук — [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup) |
| `silkennet_partition_sample_timestamp_seconds` | алертна | — | [ARCH.70] Unix-час останнього успішного семплу росту — свідок СВІЖОСТІ двох гейджів нижче. Без нього обидва вакуумні: cron наповнює їх у живому процесі, тож зупинка воркера серію не прибирає, а ЗАМОРОЖУЄ, і алерти лишаються зеленими |
| `silkennet_partitioned_table_bytes` | алертна | `table` | [ARCH.70] Байти RANGE-таблиці разом з усіма партиціями, індексами й TOAST. Диск межею НЕ є (`disk_autoresize`) — це вісь ЦІНИ: PD_SSD, розмір 30 бекапів, час DR-відновлення ([`06_06`](06_06_Disaster_Recovery_and_Backup)) |
| `silkennet_partitions` | алертна | `table` | [ARCH.70] Листові партиції RANGE-таблиці. Монотонний ЗА ПОБУДОВОЮ (автоматичного дропу в `app/`/`lib/` немає; ручний DETACH рунбука [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup) — єдиний виняток, і він оператор-ініційований). 🔴 **Це НЕ «місяці накопиченої історії», і різниця не косметична, бо на цьому числі стоїть ⚖️ ширини вікна дропу:** серед листів завжди є DEFAULT (місяцем не є ніколи) і — коли воркер біжить — УСЕ його вікно, а поточний місяць іще неповний. ⚠️ **Вікно вже змінювалось, тож поправку виводь із `PartitionMaintenanceWorker#perform`, а не з числа тут:** з 2026-09-01 воно накриває попередній+поточний+наступний (доти поточний+наступний), бо `db:seed` і load-test датують записи минулим і 1-3 числа цілили в непокритий місяць. Тобто число більше за кількість місяців із даними на 1 (лише DEFAULT) і до +3 при повному вікні, а поправку задає не формула, а факт, чи відпрацював воркер і якою була його ширина. Місяці з даними лічити прямо: `SELECT count(DISTINCT date_trunc('month', created_at)) FROM telemetry_logs`. ⊕ Алерт-правила ЧЕТВІРКИ (`sn-alert-partition-count-unbounded` · `sn-alert-partitioned-table-growth` · `sn-alert-partition-sampler-stale` · `sn-alert-partition-default-occupied` — останнє не про ріст, а про поломку) живуть в IaC-домі `deploy/grafana/alerts/silkennet-alerts.yaml` — пороги там, не тут; ⛔ добирати їх глобом `sn-alert-partition-*` НЕ можна: він захоплює чуже (`-maintenance-failed`) і пропускає своє (`partitioned-` не має дефіса після `partition`), тобто помиляється в обидва боки |
| `silkennet_payout_float_balance` | діагностична | `network`, `token` | **[SEC.22] Флоат гарячого payout-гаманця в одиницях ТОКЕНА (SPL/ERC-20) — реальна стеля збитку при компрометації ключа виплат, а НЕ газ.** Заведено 2026-08-29, бо присуд SEC.22 прийняв резидентний Solana-ключ як bounded-blast саме на підставі «вибух = флоат гаманця», а міряли ми лише SOL на газ (`silkennet_oracle_balance`) — тобто підстава присуду не мала вимірювача. ⚠️ **Окрема серія від `oracle_balance` СВІДОМО:** там одиниця «native currency (wei/lamports)», тут — токен із власними decimals (USDC = 6); спільна серія змішала б дві шкали під одним іменем. 🔒 **ЯРУС — ДІАГНОСТИЧНИЙ (оголошено, не пропущено):** alert-правила немає, бо ПОРІГ прийнятного флоату є deploy-day присудом разом із числами `INS.2`; прилад стоїть раніше за число навмисно — інакше поріг ухвалюють без величини, яку він обмежує. Дротування правила = момент ратифікації числа. ⛔ На збої читання гейдж НЕ ставиться (нуль означав би «гаманець порожній»); помилка йде в `silkennet_treasury_check_errors_total` |
| `silkennet_process_resident_memory_bytes` | алертна | — | Resident set size (RSS) of the scraped process in bytes (Linux /proc; 0 elsewhere) |
| `silkennet_puma_backlog` | алертна | — | Puma requests waiting for a free thread (backlog; sustained >0 = under-provisioned) |
| `silkennet_puma_max_threads` | алертна | — | Puma configured max threads (pool ceiling) |
| `silkennet_puma_pool_capacity` | алертна | — | Puma free thread-pool capacity (0 = saturated → requests queue in backlog) |
| `silkennet_puma_running_threads` | алертна | — | Puma worker threads currently spawned (busy + idle) |
| `silkennet_rpc_circuit_breaker_open` | алертна | `provider` | Whether RPC provider circuit breaker is open (1=open/disabled, 0=closed/healthy) |
| `silkennet_ruby_gc_count` | алертна | — | Total Ruby GC runs since process start (GC.stat[:count]) |
| `silkennet_ruby_gc_heap_live_slots` | алертна | — | Live objects on the Ruby heap (GC.stat[:heap_live_slots]); sustained growth = leak |
| `silkennet_ruby_gc_major_count` | алертна | — | Major Ruby GC runs since process start (GC.stat[:major_gc_count]) |
| `silkennet_ruby_threads` | алертна | — | Live Ruby threads in the process (Thread.list.size); sustained growth = thread leak |
| `silkennet_sidekiq_dead_set_size` | алертна | — | Current size of the Sidekiq DeadSet (jobs that exhausted all retries) |
| `silkennet_sidekiq_queue_latency_seconds` | алертна | `queue` | Latency (age of oldest job) in a Sidekiq queue |
| `silkennet_sidekiq_queue_size` | алертна | `queue` | Current size of a Sidekiq queue |
| `silkennet_telemetry_archive_unpinned_depth` | алертна | — | [E.60 Фаза 1б] незапінені архів-батчі (pending/build_failed); семплить `Treasury::MonitorService` (15-хв). SLO-поріг «unpinned age < ретеншн-горизонт партицій» = 👤 калібрування ([`00_07`](00_07_Action_Plan_Tracker) E.60-residual) |
| `silkennet_telemetry_oracle_dispatched_rows` | діагностична | — | **[ARCH.70] ТРЕТІЙ вимір ретеншну — РЯДКИ** (місяці дає `silkennet_partitions`, байти — `silkennet_partitioned_table_bytes`; рядків доти не було, а саме вони визначають, що зітре майбутнє вікно). ⛔⛔ **Це НЕ беклог, і підпис тут є присудом** (⚖️ 2026-08-29): `ChainlinkDispatchWorker` ставить `dispatched` локальним маркером без RPC, callback unwired, PATH 1 демоутовано ([`00_07`](00_07_Action_Plan_Tracker) ARCH.53) — закривача не існує ЗА ПОБУДОВОЮ, тож популяція монотонна не через затор, а через відсутність другої половини тракту. Назвати її «скільки чекає на callback» означало б вигадати число. 🔒 **Ярус діагностичний:** алерт-правила немає, бо для монотонної-за-побудовою величини «скільки прийнятно» не визначене — законна форма це операторська стеля-дедлайн, і вона ратифікується РАЗОМ із шириною вікна ретеншну. ⊕ Ціна лічби виміряна: партіальний `idx_telemetry_logs_oracle_dispatched` дає `Index Only Scan` по кожній партиції, тож це не скан ([ARCH.52]); ⛔ не розширювати на `group(:oracle_status)` — решта станів індексу не має |
| `silkennet_trees_silent` | алертна | — | Current number of active trees silent beyond the silence threshold (set on each staleness sweep) |
**Histograms:**

| Metric | Ярус | Labels | Призначення |
|---|---|---|---|
| `silkennet_lorenz_computation_duration_seconds` | діагностична | — | Lorenz attractor server-side computation time (Float IEEE-754, 250 iterations) |
| `silkennet_oracle_dispatch_duration_seconds` | алертна | — | Chainlink oracle dispatch ATTEMPT latency in seconds — successful and failed alike [INF.26]; circuit-open refusals are excluded on purpose (our own breaker answers in microseconds and would drag p99 down) |
**Регенерація таблиць** (після зміни реєстру метрик у коді):

```bash
ruby scripts/metric_registry_table.rb            # dry-run: чи розійшлось
ruby scripts/metric_registry_table.rb --write    # застосувати
```

🔴 **Однорядковика тут більше немає, і це не косметика — він ЗНИЩУВАВ канон** (⚖️ 2026-08-29, INF.26). Стара команда друкувала рядок ЦІЛКОМ, тобто перезаписувала й колонку `Призначення`; вимір того дня показав, що **дванадцять** комірок дописані руками поверх докстрінга — до +1210 символів на рядок, і саме там живуть підстави присудів (чому `silkennet_partitions` лічить ЛИСТИ, а не місяці історії — а на цьому числі стоїть ⚖️ ширини вікна ретеншну; чому флоат виплат окремий від газу). Тобто задокументована процедура, виконана ДОСЛІВНО, стирала їх мовчки, і жоден гейт цього не бачив: усі вони судять імена й типи, ніколи прозу.

**Скрипт розводить колонки за ВЛАСНІСТЮ:** `Metric` · `Ярус` · `Labels` виводяться з коду й переписуються завжди; `Призначення` є канон-прозою й не чіпається ніколи (для НОВОГО рядка засівається докстрінгом). ⚠️ Він не судить, чи проза ще правдива — лише не дає її затерти.

⛔ **Три гарди в ньому куплені власними промахами, і знімати їх не можна.** (1) *Ідемпотентність*: перша редакція читала прозу регексом між роздільниками, і на вже-регенерованому рядку той захоплював `Labels | Призначення`, тож ДРУГИЙ прогін задвоював стовпчик — тепер поле береться позиційно, а кількість колонок перевіряється. (2) *Збереження прози*: межа таблиці бралась «до `---`», тож секція, яку ви зараз читаєте, опинилась усередині захопленого тіла `Histograms` і **зникла при перебудові, не потрапивши в жоден коміт** — тепер блок обмежений суцільними `|`-рядками. (3) *Незалежність гарда*: перша редакція гарда (2) виводила «не-табличні рядки» з тієї самої межі — тобто ділила з дефектом його сліпоту й пропускала мутацію ЗЕЛЕНОЮ; тепер визначення незалежне (рядок не починається з `|`).

---

### 2.9 Industrial-Grade Hardening (аналіз 2026-05-29)

Аудит чинного стеку (Grafana Alloy → Grafana Cloud) на production-grade зрілість. Архітектура **достатня** (WAL-буферизація, Basic Auth, всі 9 черг + повний реєстр §2.8); бракувало лише атрибуції та захисних гейтів — закрито нижче (`external_labels`, `queue_config`+explicit WAL, cardinality budget, CI-валідація, runtime-метрики).

**✅ Зроблено зараз (`config.alloy`):**
- **`external_labels`** на `remote_write` — `service` / `source` / `env` (з `RAILS_ENV`) / **`slot`** (з `DEPLOYMENT_SLOT`). 🔴 **Розводить слоти ЛИШЕ `slot`:** `env` константна (`RAILS_ENV` = production в обох слотах свідомо). ⊕ **`DEPLOYMENT_SLOT` більше не accessory-only [INF.27, 2026-08-30]:** та сама змінна тепер оголошена й у ГЛОБАЛЬНОМУ `env.clear` обох маніфестів, тобто доступна Rails-ролям — звідти її читає `SilkenNet::DeploymentSlot` і мітить нею Sentry-`environment`, namespace кешу, обидва бакети ActiveStorage і поле `slot` у JSON-логу. Тобто мітка спостережуваності й мітка застосунку — ОДНЕ значення, і телеметрія більше не є єдиною поверхнею, що вміє розрізнити слоти. Носій — `spec/deploy/deployment_slot_axis_spec.rb` ([`00_06 §3`](00_06_SSOT_Documentation_Standard)). ⊕ Споживач `slot`: дашборд фільтрує (`{slot=~"$slot"}`), алерти РОЗЩЕПЛЮЮТЬ (`by (slot)`) — різниця не стильова, див. S2.4. Без них серії з prod/canopy зливаються в Grafana Cloud. ✅ **Мітку `release` ЗНЯТО 2026-08-30 (S2.4):** `RELEASE_VERSION` ніколи не постачався в accessory-env, тож мітка була порожня й дропалась — мертва external_label із наміром без механізму; а дротування дрейфувало б ЗА ПОБУДОВОЮ (accessory бутиться окремо від деплою, env-знімок черствіє між релізами). Канонічна форма, ЯКЩО release-атрибуція колись знадобиться, — gauge `silkennet_build_info{version=…}` із САМОГО процесу (завжди свіжий, переживає будь-який механізм скрейпу); пускач = перший живий інцидент із питанням «який реліз це зламав», записано в `config.alloy`.
- **`scrape_timeout = 10s`** явно (< 15s interval).
- Header-коментар більше не дублює реєстр метрик — реф на §2.8 (DRY).
- **CI-gate `alloy_config_validate`** (`.github/workflows/ci.yml` → `CI · Code`) — `grafana/alloy:v1.16.3 fmt` парсить `config.alloy` (образ **запінено** — версія синхронна з `config/deploy.yml` `accessories.alloy`; bump оновлює обидва разом, INF.14); **path-gated** під `alloy`-домен (`changes`-job; периметр розширено 2026-08-30 [OPS.37] — крім `deploy/**` він тепер тягне `config/deploy*.yml`, `.kamal/**`, `terraform/compute.tf`, бо ТА САМА джоба несе ще й `deploy_secret_scan`, чиї предмети лежать саме там); River parse-error = **red CI замість crash-loop accessory** на деплої.
- **`queue_config` + явний `wal`** на `remote_write` (`config.alloy`) — shard fan-out `1→50` + batch-sizing дають backpressure при сповільненні Grafana Cloud замість необмеженого росту пам'яті; WAL-вікно (~2h truncate) тепер явне й тюнабельне. Конкретні значення — у `config.alloy` (SSOT), тут не дублюються (drift).
- **Cardinality budget** (`config.alloy`, `prometheus.relabel`) — `labeldrop` per-identity міток (`did`/`tree_id`/`peaq_did`/`wallet_address`/`tx_hash`) перед `remote_write`. Реєстр (§2.8) свідомо bounded — єдина growth-вісь `cluster_id` (per-forest entropy) **лишається** легітимною; guard не дає випадковій майбутній per-DID мітці тихо підірвати active-series біллінг (Grafana Cloud біллить за series/DPM). Нульовий ефект сьогодні (таких міток нема) — стоячий запобіжник на write-boundary.
- **Process/runtime метрики** (`prometheus.rb` §2.9, 9 gauges) — Ruby VM/GC/RSS/Puma-threads, `sample_process_runtime!` на кожен scrape. 🔴 **DB-pool ґейджі мовчали ВІД НАРОДЖЕННЯ, і твердження «Bonus fix: `sample_connection_pool!` тепер викликається» було правдивим лише наполовину** [виміряно з ЖИВОГО стека 2026-09-03]: викликається він справді (рядком вище за `sample_process_runtime!` у тому самому колекторі), але кликав `ActiveRecord::Base.connection_handler.all_connection_pools`, якого на Rails 8.1 **не існує**, — тож кожен скрейп кидав `NoMethodError`, а власний `rescue StandardError` ловив його в `logger.warn`. Наслідок: `silkennet_db_pool_{size,connections,idle,waiting}` не мали ЖОДНОЇ серії ніколи, а P2-правило `sn-alert-db-pool-saturation` стояло над неіснуючою метрикою. ⚠️ **Чому не червоніло ніде:** сусід по колектору віддавав свої 9 серій, тож «метрики рендеряться» було правдою; покриття теж зелене, бо request-спека на `/metrics` ці рядки ВИКОНУВАЛА — включно з `rescue` (покриття міряє виконання, не успіх); а `grafana_alerts_spec` судить, що метрика є в РЕЄСТРІ, тобто оголошена, — не що її бодай раз `set`. Лік: `each_connection_pool` (без аргументу, тож переживе зміну ролей). Носій — `spec/middleware/prometheus_collector_spec.rb` §«DB-pool gauge refresh», і форма піна несуча: рівно ЗНАЧЕННЯ в тілі відповіді, бо пін на «не кинуло» вакуумний за наявності `rescue`, а пін на саме імʼя — теж (prometheus-client друкує `# HELP`/`# TYPE` і для ґейджа без жодного значення).
- **Multi-process scrape topology (2026-07-04, INF.14/INF.17).** Prometheus-реєстр — **in-process**: web:80 фізично не бачить інкрементів Sidekiq-воркерів (mint/slash/payout SLO, CCM/QATT-security, dead-man switch) та CoAP-демона — до цього фіксу всі ці серії були вічними нулями web-процесу, і жоден P0-алерт не міг спрацювати. Фікс: кожен процес віддає власний `/metrics` — job/coap піднімають embedded-експортер `SilkenNet::MetricsExporter` (Puma::Server + той самий `PrometheusCollector`; Sidekiq `on(:startup)` 9394 / демон 9395), Alloy скрейпить **пʼять таргетів** із лейблом `process` (`config.alloy`; три production + два canopy з 2026-09-03 — цей абзац описував епоху ДО canopy-таргетів і суперечив сусіднім булетам того ж §, а пін тримає пʼять: `alloy_scrape_topology_spec`); ⚖️ **[OPS.37 2026-08-30] адресація таргетів РАТИФІКОВАНА: per-role `network-alias` у спільній docker-мережі `kamal`** (`servers.<role>.options` ідуть дослівно в `docker run` після хардкодженого `--network kamal`; accessory живе в тій самій мережі за замовчуванням — kamal-2.12.0 `DEFAULT_NETWORK`). Алias — не порт: у роллінг-вікні старий і новий контейнер ділять його легально (виміряно живим експериментом: DNS віддає обидва IP, після stop — конвергує), тож клас «start_new_version падає на allocated port» сюди структурно не переноситься; алias вмирає з контейнером → NXDOMAIN → `up=0` → `sn-alert-scrape-target-down` за призначенням. Відхилено з виміром: published-порти ламають роллінг (спроба 2026-08-29, відкочено) ⊥ docker-socket — прямий чи через socket-proxy — віддає env-read усіх контейнерів включно з money-квінтетом job-ролі (haproxy-шаблон tecnativa гейтить весь префікс `/containers` ОДНИМ regex — list і inspect нероздільні). Обидві половини механізму (таргети `config.alloy` ⟷ аліаси `config/deploy.yml`) стереже крос-файловий пін `spec/deploy/alloy_scrape_topology_spec.rb`; пускач accessory — крок «Ensure Alloy accessory is running» в обох deploy-воркфлоу (`kamal accessory boot` ідемпотентний; зміна `config.alloy` = свідомий `kamal accessory reboot alloy`). 🔴 **Alloy-контейнер ОДИН на два слоти, і до 2026-08-31 canopy-крок мовчки перемарковував ПРОДОВІ серії** (⚖️ founder, знайдено прогоном `kamal config -d canopy`, механізм звірено з джерелом kamal 2.12): `Kamal::Configuration::Accessory#service_name` = `"#{config.service}-#{name}"`, а `config.service` **не несе destination** (`service_and_destination` існує, але вживається лише для каталогу застосунку) ⇒ обидва призначення дають `silken_net-alloy`; canopy-override чіпав лише `env.clear`, тож `host` лишався базовим ⇒ той самий контейнер на тому самому хості; а `kamal accessory boot` ідемпотентний **ПРОПУСКОМ** («Skipping … a container already exists», жовтим, exit 0) ⇒ мітку вигравав слот, що встиг **першим**, а це canopy (кожен push у main проти релізу). 🔑 І це була чиста втрата, бо **canopy тоді не мав жодної цілі скрейпу** (до 2026-09-03 — булет нижче): `config.alloy` скрейпить три `silken-*` `network-alias`-імені, а ролі canopy несуть власні `canopy-*` аліаси, дизʼюнктні з ними ([`00_07`](00_07_Action_Plan_Tracker) OPS.37, 2026-09-02; доти canopy був alias-less через масив-форму `servers:`) — носій `spec/deploy/alloy_scrape_topology_spec.rb`. Лік — крок кличе `kamal accessory boot alloy` **без** `-d canopy`, тож мітка збігається з тим, що скрейпиться; canopy `accessories:`-override знято. ⚠️ Залишок названо: canopy не може «не оголосити» успадкований accessory (deep_merge = keys-UNION, форми видалення немає), тож `kamal setup -d canopy` підняв би його — Фаза 3 свідомо каже `kamal deploy -d canopy`, який accessories не чіпає. Носій — `spec/deploy/alloy_scrape_topology_spec.rb` §«the ONE-Alloy invariant». Queue/DeadSet-гейджі (Redis-глобальний факт) семплить лише job (`refresh_sidekiq_gauges if Sidekiq.server?`) — інакше три ідентичні серії = потрійний page; alert-вирази додатково max-обгорнуті. Демон-рівень статусів `coap_packets` (`enqueued`/`malformed`/`unknown_route`/`oversized` — трункейт ядром, який інакше маскується під MIC-fail «fraud») не перетинається з воркер-рівнем. Puma-API-дрейф ловить спека реальним HTTP (`spec/lib/silken_net/metrics_exporter_spec.rb`). **Свідомі стелі:** (а) web-процес у cluster-режимі (`WEB_CONCURRENCY>1`) фрагментує реєстр між форкнутими воркерами (scrape бачить один випадковий); при потребі точності — `DirectFileStore` всередині web-контейнера (крос-контейнерно він не працює: спільних volumes між ролями немає). 🔴 **Підстава цієї стелі — «web-локальні лічильники рідкісні/НЕКРИТИЧНІ» — СПРОСТОВАНА виміром 2026-08-31, а вердикт вистояв:** із **11** critical-правил рівно ОДНЕ стоїть на web-писаному лічильнику (`silkennet_rate_limit_store_errors_total` ← `config/initializers/rack_attack.rb`, Rack-middleware ⇒ Puma-процес); решта 10 пишуть job/coap, а ті однопроцесні й до фрагментації імунні структурно. ⚠️ Ціна вужча, ніж читається: ТИШІ це не створює (при живому збої обидва воркери помиляються на кожному запиті, поріг `>0` перетинається), бреше **ВЕЛИЧИНА** — `increase(...[1h])` читає кожен перескок між воркерами як reset+приріст, тож число в анотації алерту завищене. Тобто щит працює, а цифра, яку читає людина, — ні. Лік `DirectFileStore` глобальний (store прив'язується при СТВОРЕННІ метрики — `Prometheus::Client::Metric#initialize`, — тож мусив би стояти ДО побудови реєстру й накрив би всі 94 метрики, включно з високочастотними job-лічильниками) → дім рішення [`00_07`](00_07_Action_Plan_Tracker) INF.22; (б) **PRIMARY CoAP-демон живе на Ingress Anchor** (INF.17, founder 2026-07-04) — Alloy живе на app-хості й анкера НЕ дістає: `coap`-таргет скрейпить **дормантну Kamal-роль** (idle → чесні нулі демон-рівня, поки fallback не активовано). ✅ **Анкерний `coap-daemon` стартував і проніс телеметрію 2026-09-03** — нулі цього таргета вперше є СПОСТЕРЕЖЕННЯМ, а не спроєктованою поведінкою (доказ — рядки в БД canopy, [`00_07`](00_07_Action_Plan_Tracker) INF.17). Різниця лишається несучою, бо PRIMARY поза скрейпом за побудовою: перший бут демона був first-catch, а не re-verify, і ловитиме його не цей таргет, а `coap_smoke` ([`00_07`](00_07_Action_Plan_Tracker) `INF.17`). Видимість анкор-демона: воркер-half лічильники `coap_packets` (job-таргет — success/decrypt/attest), INF.6 smoke-зонди (e2e байт-точні), Sentry (SENTRY_DSN у `coap.env`) і — з ARCH.81 — **UDP-проба адмін-панелі здоров'я** (`SilkenNet::HealthProbes.coap_listener`: той самий freeze-contract зонд, що й INF.6, але з веб-процесу на вимогу; адреса = `COAP_HOST`, незадана ⇒ чесний `not_configured`, ніколи «мертвий»); скрейп самого анкора (GCP-Alloy чи scrape-endpoint через firewall) — лише якщо стеля почне муляти.
- **Canopy-таргети (⚖️ founder 2026-09-03, OPS.37).** `canopy-web:80` + `canopy-job:9394` зі `slot = "canopy"` НА ТАРГЕТІ (`config.alloy`): у remote-write Prometheus `external_labels` додаються лише там, де серія мітки ще не має, тож canopy-серії їдуть як slot=canopy, а `silken-*` тримають production-мітку accessory. ONE-Alloy лишається — єдиний агент просто скрейпить обидва слоти; `coap`-таргета в canopy нема (роль нейтралізована). Носій — `alloy_scrape_topology_spec` (пʼять адрес + «canopy-аліас лише з міткою, production — без»); розкатка — dispatch-вхід `gh workflow run deploy.yml -f alloy=reboot` (файл монтується при boot; локальний `kamal accessory reboot alloy` з ноутбука падає на posix-акаунті SA); доказ пріоритету мітки — перша серія `up{slot="canopy"}` у Grafana Cloud, статично він недоказовий (✅ виміряно 2026-09-03 10:43Z: `up{instance="canopy-web:80",slot="canopy"}` = 1, `relabel` не знадобився). ⚠️ Та сама перша серія показала ДРУГУ діру: Alloy за замовчуванням ставить `job` = id компонента (`prometheus.scrape.silken_net_scraper`), а всі правила й дашборди селектують `job="silken_net_scraper"` — тому `sn-alert-scrape-target-down` не міг зматчити жодної серії навіть із живим remote-write; лік — `job_name = "silken_net_scraper"` у `prometheus.scrape` (той самий день). ⚠️ Хибний бік вимірний: серія з `slot="production"` на canopy-таргеті означає, що мітка таргета НЕ взяла гору над `external_labels` accessory — лік тоді переносити `slot` у `prometheus.relabel`, не міняти таргет. Доти canopy свідомо не скрейпився, і дашборд слоту читав «No data» усюди — саме це й купило два таргети.

📏 **Ліміти Grafana Cloud, звірені проти ІМПОРТОВАНОГО 2026-09-02 (DEPLOY-1 Фаза −1):** trial стеку `violetmamba3330` закінчується **2026-09-12**, далі Free Forever. Наші правила — Grafana-managed (provisioning API, `import.rb`), і їхній ліміт на Free = **500 правил, по 1000 alert-інстансів на правило** (доки Grafana Cloud «Configure Grafana-managed alert rules»); у нас 3 групи · 58 правил (p0 10 · p1 32 · p2 16) при `by (process|slot|…)`-кардинальності в одиниці — запас ≈×8. ⚠️ Мімірівський ruler-ліміт `ruler_max_rules_per_rule_group = 20` (usage-limits) стосується **data-source-managed** правил і на наші НЕ діє — інакше група p1 (32) вже провалювалась би; не «розбивати групи» на цій підставі. Що після trial'у справді звузиться — метрики (10k активних серій, 14 днів) і 3 користувачі; кардинальність стереже `prometheus.relabel` (↑).

- 🔴 **Форма alert-правила: `A(запит) → B(reduce,last) → C(threshold)`, і `reduce` тут НЕСУЧИЙ** [S2.4, ТРЕТІЙ клас «stored ≠ evaluates», виміряно на живому canopy 2026-09-03]. Вираз `threshold` приймає ЛИШЕ зведене число; датасорс-запит віддає ЧАСОВИЙ РЯД, тож правило, чия alert-condition читає його напряму, падає в evaluation — і лік приписує сама Grafana («consider adding a reduce expression»). 🔴 **Дефект ЛАТЕНТНИЙ, доки метрика порожня:** без даних правило звітує `nodata` й читається як здорове — тому обидва попередні вердикти («57/57 evaluated, 0 error») були ПРАВДИВІ в мить виміру і впали від першого живого job-контейнера: **29 із 42 перевірених правил стали Error, серед них 9 із 10 `p0-critical`** — включно з `sn-alert-scrape-target-down`, що стереже сам скрейп, і `sn-alert-gateway-faulty` при живому `silkennet_gateways_faulty` = 8. Упала не форма фікса, а ПІДСТАВА вердикту ([`00_05 §5`](00_05_AI_Native_Operating_Model) — пін на порожній множині зелений завжди). ⛔ `instant: true` замість `reduce` ВІДХИЛЕНО виміром: редактор Grafana малює `Type: Instant` там, де бекенд усе одно біжить range, тобто прапорець спирається на дефолт, який у цього імпортера вже двічі розійшовся зі збереженою моделлю. ⚠️ Анотації цитують `$values.B.Value` (зведений вузол), не `$values.A` — після вставки `reduce` скаляр живе в `B`. Носій — `spec/deploy/grafana_alerts_spec.rb` («no expression reads a raw datasource query»), і він СТРУКТУРНИЙ саме тому, що не залежить від наявності даних; оголошена стеля — судить ФОРМУ ланцюга, ніколи доречність редьюсера.

**🟡 Рекомендований роадмеп (потребує валідації/ops, поза цим коммітом):**

| # | Покращення | Чому | Пріоритет |
|---|------------|------|-----------|
| 1 | ✅ **CI-валідація `config.alloy`** (2026-05-29) — CI job `alloy_config_validate` (`grafana/alloy fmt`, parse-check) | Раніше **ніщо** не лінтило River-конфіг; parse-error = crash-loop Kamal-accessory `alloy` у проді. Гейт ловить це до деплою | ✅ DONE |
| 2 | ✅ **`queue_config` + явний WAL** (2026-06-04) на `remote_write` (`config.alloy`) | Default WAL ~2h буферить аутейдж; `capacity`/`max_shards` (1→50)/`batch_send_deadline` дають backpressure замість необмеженого росту пам'яті; WAL-вікно явне | ✅ DONE |
| 3 | ✅ **Process/runtime метрики** (2026-05-29) — 9 gauges (RSS · GC count/major/heap_live · ruby_threads · Puma running/max/pool_capacity/backlog), sampled on-scrape (`sample_process_runtime!`) + 13 specs | Закрило сліпоту до memory leak / GC pause / thread saturation. Pure stdlib (GC.stat / Thread / /proc / Puma.stats) | ✅ DONE |
| 4 | ✅ **Cardinality budget** (2026-06-04) — `prometheus.relabel` `labeldrop` per-identity (`config.alloy`) | `cluster_id` (entropy) лишається (легітимна growth-вісь); per-DID labels (`did`/`tree_id`/`peaq_did`/`wallet_address`/`tx_hash`) дропаються до remote_write, щоб майбутня випадкова мітка не підірвала active-series біллінг (Grafana Cloud біллить за series / DPM) | ✅ DONE |
| 5 | ✅ **`up` scrape-health alert** (IaC 2026-07-04) — `sn-alert-scrape-target-down`: `min by (slot, process) (up{job="silken_net_scraper"})` per-process і per-slot називає, КОТРИЙ з пʼяти таргетів мертвий (три production + два canopy з 2026-09-03); `NoData → Alerting` = сам Alloy впав. ✅ імпортовано (2026-08-29, переімпорт 09-03); правило ГОРИТЬ на трьох production-таргетах `up=0` — під silence з терміном до Фази 5 (S2.4) | ✅ DONE |
| 6 | 🟡 **SLO + error-budget** — mint-half ✅ (IaC 2026-07-04): `sn-alert-mint-slo-breach` <80%/1h (єдина канон-ціль — [`06_08 §2.4`](06_08_Resilience_and_Failover_Policy); PromQL-guard `and attempts>0`). Slash/payout/insurance ratios — пороги калібруються з перших live-вікон (00_07 S2.4), не вигадуються. **[ARCH.62]** `sn-alert-mint-volume-anomaly` (agg mint-volume ceiling ~MAX_SUPPLY, operator-калібрований) + per-token inert circuit-break | ops |
| 7 | Dashboards + alerts + **contact point** import у Grafana Cloud (IaC у `deploy/grafana/`) | S2.2 — IaC готовий; ✅ one-command `deploy/grafana/import.rb` (auto-discovery UID + ідемпотентний upsert + contact point/root notification policy з ENV off-by-default `ALERT_CONTACT_EMAIL`/`_TELEGRAM_*`, `--dry-run` без credentials); ✅ канал задротовано 2026-08-30 через UI (Email; реімпорт його не чіпає — ENV off-by-default); ✅ переімпорт + verify закрито 2026-09-03 (`58/58 evaluated, 0 error`) | ✅ DONE |

**#2 + #4 — імплементовано (2026-06-04) у `deploy/alloy/config.alloy`:** pipeline `prometheus.scrape → prometheus.relabel.cardinality_budget → prometheus.remote_write` (queue_config + явний WAL). Значення живуть у `config.alloy` (SSOT) — тут не дублюються, щоб уникнути drift; rationale — рядки #2/#4 вище. Валідація: CI job `alloy_config_validate` (`grafana/alloy fmt`).

---

## 🪵 Частина III: Logs — GCP Cloud Logging

> ⚠️ **Scope: GCP/Kamal-шлях.** Ця частина описує Cloud Logging, куди тече stdout при деплої на GCP VM (Kamal). ⊕ **[OPS.37] Друга половина цього застереження знята разом із платформою** — доти вона казала, що на ній stdout інших сервісів недосяжний (окремі контейнери, без kubelet/docker-сокета, поза lease-ізоляцією) → lease-логи ефемерні (виживають лише Sentry-exceptions). Закриття = Rails-HTTP-push у Grafana Cloud Loki (backend **§04**, НЕ Alloy-scrape) — tracked [`INF.22`](00_07_Action_Plan_Tracker), робити з першим деплоєм (TRL-3 = нуль логів для тюну).

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
│  │  /metrics — 3 prod + 2 canopy таргети (§2.9, OPS.37):  │   │
│  │  web:80 (middleware) · job:9394 · coap:9395            │   │
│  │  (embedded SilkenNet::MetricsExporter; реєстр §2.8)    │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │ [Alloy scrapes кожні 15s]        │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Grafana Alloy (Kamal accessory; DNS-аліаси ролей ⚖️)   │   │
│  │  ✅ prometheus.scrape → 5 таргетів (process+slot)      │   │
│  │  ✅ prometheus.remote_write → Grafana Cloud (HTTPS)     │   │
│  └──────────────────────────┬──────────────────────────────┘   │
│                             │                                   │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Grafana Cloud (SaaS)                                   │   │
│  │  ✅ Prometheus (зберігання метрик)                       │   │
│  │  ✅ Grafana Dashboards (імпортовано 2026-08-29)         │   │
│  │  ✅ Grafana Alerting (правила ✅; канал ✅ 08-30)         │   │
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
│  (метрики §2.8, Basic Auth)  (Kamal accessory)           │           │
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
| `deploy/alloy/config.alloy` | Grafana Alloy конфігурація (scrape + remote_write) | ✅ Створено |
| `prometheus.yml` (scrape config) | — | ✅ Замінено на `config.alloy` (Alloy agent) |
| `grafana/` (дашборди+правила) | Grafana Cloud SaaS | ✅ Імпортовано 2026-08-29 |
| `alertmanager.yml` | Grafana Cloud Alerting | 🟡 Операційна задача |

---

## 🔗 Зовнішні Залежності та ENV змінні

> 🏠 **Значення й наслідки відсутності КОЖНОЇ змінної — дзеркало [`06_04 §2.1`](06_04_Secrets_Checklist), правити ТАМ.** Тут — лише те, який компонент спостережуваності її споживає. ⊕ Пʼять рядків цієї таблиці (`PROMETHEUS_AUTH_*` · `PROMETHEUS_ALLOWED_IPS` · `SENTRY_TRACES_SAMPLE_RATE` · `SENTRY_WORKER_THREADS`) до 2026-09-04 не мали рядка в домі ВЗАГАЛІ — тобто тут була не копія, а **єдина адреса**; дірку закрито (DOC-T.98).

| ENV змінна | Обов'язкова | Де використовується | Статус |
|-----------|-------------|---------------------|--------|
| `SENTRY_DSN` | ✅ Для production | `config/initializers/sentry.rb` | ✅ Додано у `.kamal/secrets-common` |
| `SENTRY_TRACES_SAMPLE_RATE` | ❌ (default: 0.001) | `config/initializers/sentry.rb` | — |
| `SENTRY_WORKER_THREADS` | ❌ (default: 2) | `config/initializers/sentry.rb` | — |
| `RELEASE_VERSION` | ❌ (оверрайд) | `config.release` | Не постачається жодним Kamal-шляхом свідомо: release несе `KAMAL_VERSION` (§1.2); змінна лишається оверрайдом для не-Kamal процесів (анкер-демон) |
| `PROMETHEUS_ALLOWED_IPS` | ❌ | `app/middleware/prometheus_collector.rb` | Не задана (RFC 1918 + loopback дозволені за замовчуванням — host-мережа accessory) |
| `PROMETHEUS_AUTH_USER` | ✅ (рекомендовано) | `app/middleware/prometheus_collector.rb`, Alloy `config.alloy` | ⚠️ deploy-поверхні не має — вона зникла з платформою (OPS.37); колектор auth-skip'ає приватні діапазони, тож unset = чесний skip |
| `PROMETHEUS_AUTH_PASSWORD` | ✅ (рекомендовано) | `app/middleware/prometheus_collector.rb`, Alloy `config.alloy` | ⚠️ deploy-поверхні не має (OPS.37); unset = чесний auth-skip |
| `GRAFANA_REMOTE_WRITE_URL` | ✅ Для production | `deploy/alloy/config.alloy` (Kamal accessory) | ✅ У `.kamal/secrets-common` |
| `GRAFANA_REMOTE_WRITE_USERNAME` | ✅ Для production | `deploy/alloy/config.alloy` (Kamal accessory) | ✅ У `.kamal/secrets-common` |
| `GRAFANA_REMOTE_WRITE_TOKEN` | ✅ Для production | `deploy/alloy/config.alloy` (Kamal accessory) | ✅ У `.kamal/secrets-common` |

---

## 📋 Висновки аудиту

### Що реально реалізовано (TRL 6 факти)

1. **Prometheus-client інтегрований** — повний реєстр метрик визначено (кількість — §2.8), `/metrics` endpoint працює з IP-захистом + Basic Auth.
2. **Sentry SDK встановлений і налаштований** — zero-noise конфігурація (набір виключень — SSOT `config/initializers/sentry.rb`), автоматична Sidekiq-інтеграція, PII-scrubbing.
3. **Інструментація в бізнес-логіці** — всі критичні операції (мінтинг, слешинг, RPC-помилки, телеметрія, OTA, EWS, CoAP) мають Prometheus-лічильники.
4. **GCP Cloud Logging** — WARNING+ логи зберігаються, cost-control фільтр активний.
5. **Structured JSON logging** — активовано у production: кожен рядок містить `timestamp`, `pid`, `request_id`, `sentry_trace_id`, `sentry_span_id`.
6. **Grafana Alloy** — Kamal accessory скрейпить `/metrics` кожні 15s, пушить у Grafana Cloud через remote_write.

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
