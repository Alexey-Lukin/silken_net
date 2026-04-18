# 10_02 — Action Plan Tracker (Живий Документ)

> **Створено:** 2026-04-18 (Аудит 35 документів `00_00` → `09_03`)
> **Останнє оновлення:** 2026-04-18 (Сесія 2)
> **Відповідальний:** AI Copilot Sessions + Core Team
> **Принцип:** Кожна сесія оновлює чекбокси `[ ]` → `[x]` та додає дату + коміт.

---

## 📊 Зведена статистика

| Категорія | Знайдено | Виправлено | Залишилось |
|-----------|----------|------------|------------|
| Явні BLOCKER'и | ~65 | ~24 | ~41 |
| Архітектурні рішення | ~30+ | — | Задокументовані |
| Рекомендації та пропозиції | ~40+ | — | В роботі |
| Відкриті питання | ~25+ | — | В роботі |
| Технічний борг | ~30+ | — | В роботі |
| Безпекові проблеми | ~20+ | — | В роботі |
| Не реалізовані фічі | ~25+ | — | В роботі |

---

## 🛣️ Sprint Plan — Software / Backend / DevOps

---

### Sprint 1 — "Operations Foundation" (Тиждень 1-2)

#### S1.1 — GitHub Secrets заповнення
- **Пріоритет:** P0 | **Складність:** Низька | **Джерело:** `06_01`
- **Опис:** 12 критичних секретів не встановлені: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `DATABASE_URL`, `SSH_PRIVATE_KEY`, тощо
- **Блокує:** Весь CI/CD pipeline
- **Статус:**
  - [ ] Створити список необхідних секретів (checklist)
  - [ ] Заповнити GitHub repository secrets
  - [ ] Верифікувати CI pipeline проходить
- **Сесія:** —
- **Коміт:** —

#### S1.2 — Deploy-production.yml workflow
- **Пріоритет:** P0 | **Складність:** Низька | **Джерело:** `06_01`
- **Опис:** Workflow для production deployment
- **Статус:**
  - [x] `.github/workflows/deploy-production.yml` існує (trigger: release published + workflow_dispatch)
  - [x] Kamal deploy без `-d` flag (= production)
  - [x] CoAP UDP rate limiting включено
  - [x] Concurrency: strict (no cancel-in-progress)
- **Результат:** ✅ Вже реалізовано
- **Сесія:** Аудит 2026-04-18

#### S1.3 — Terraform bootstrapping
- **Пріоритет:** P2 | **Складність:** Низька | **Джерело:** `06_01`, `06_02`
- **Опис:** GCS bucket для Terraform state має існувати ДО першого `terraform init` (chicken-and-egg)
- **Статус:**
  - [x] `terraform/terraform.tfvars.example` існує з прикладом конфігурації
  - [x] Створити bootstrap скрипт `terraform/bootstrap.sh` (створює GCS bucket)
  - [ ] Документувати bootstrapping процедуру в README або окремому doc
- **Сесія:** 2026-04-18 Сесія 2
- **Коміт:** `39f6e7e`

#### S1.4 — Terraform: canopy_enabled
- **Пріоритет:** P2 | **Складність:** Низька | **Джерело:** `06_01`
- **Опис:** `canopy_enabled = false` за замовчуванням — staging не провізіонується
- **Статус:**
  - [x] `terraform.tfvars.example` має `canopy_enabled = true`
  - [ ] Верифікувати що Canopy deploy працює з `canopy_enabled = true`
- **Сесія:** —
- **Коміт:** —

#### S1.5 — Kamal IP placeholders
- **Пріоритет:** P2 | **Складність:** Низька | **Джерело:** `06_01`
- **Опис:** `192.168.0.1` та `<CANOPY_SERVER_IP>` — плейсхолдери в Kamal config
- **Статус:**
  - [ ] Підставити реальні IP після `terraform apply`
  - [ ] Верифікувати Kamal deploy з реальними IP
- **Сесія:** —
- **Коміт:** —
- **Примітка:** Операційна задача після інфраструктурного деплою

#### S1.6 — NaasContract `signed_at` migration
- **Пріоритет:** P1 | **Складність:** Низька | **Джерело:** `07_01`
- **Опис:** Controller серіалізує `signed_at`, але колонка відсутня в `db/structure.sql`
- **Статус:**
  - [x] Визначити: додати міграцію з `signed_at` АБО прибрати з контролера
  - [x] Реалізувати обране рішення
  - [x] Перевірити RSpec тести
- **Результат:** ✅ Вже вирішено — контролер НЕ серіалізує `signed_at` (only: [:id, :status, :total_value, :emitted_tokens])
- **Сесія:** 2026-04-18 Сесія 2
- **Коміт:** Верифікація, код не змінювався

#### S1.7 — Legacy Tailwind colors cleanup
- **Пріоритет:** P1 | **Складність:** Низька | **Джерело:** `04_04`
- **Опис:** `--color-gaia-green`, `--color-gaia-dark`, `--color-gaia-muted` — не в офіційному дизайн-словнику
- **Статус:**
  - [x] Аудит використання legacy кольорів (grep по кодовій базі)
  - [x] Замінити на офіційні дизайн-токени або видалити
  - [x] Верифікувати UI не зламано
- **Результат:** ✅ Видалено 3 legacy кольори з `@theme` — НЕ використовувались жодним компонентом (bg-gaia-green/text-gaia-green тощо). Семантичні токени (gaia-primary, gaia-text-muted) залишаються.
- **Сесія:** 2026-04-18 Сесія 2
- **Коміт:** `39f6e7e`

#### S1.8 — Файл `8_02` → `08_02` naming fix
- **Пріоритет:** P2 | **Складність:** Мінімальна | **Джерело:** `00_00` SSOT Index
- **Опис:** `8_02_Cybernetic_and_Mathematical_Validation.md` порушує naming convention
- **Статус:**
  - [x] Перейменувати на `08_02_Cybernetic_and_Mathematical_Validation.md`
  - [x] Оновити посилання в `00_00_SSOT_Index.md`
- **Результат:** ✅ Виконано
- **Сесія:** 2026-04-18 Сесія 1
- **Коміт:** `6c20644`

---

### Sprint 2 — "Observability" (Тиждень 3-4)

#### S2.1 — Prometheus Server deployment
- **Пріоритет:** P0 | **Складність:** Середня | **Джерело:** `06_03`
- **Опис:** `/metrics` endpoint працює (7+ метрик), але НІКУДИ не скрейпиться — Prometheus Server відсутній
- **Блокує:** Production-readiness, операційна видимість, інвестиційний due diligence
- **Статус:**
  - [x] `config/initializers/prometheus.rb` — метрики зареєстровані
  - [x] `app/middleware/prometheus_collector.rb` — endpoint `/metrics` з IP allowlist + Basic Auth
  - [ ] Додати Prometheus Server у Terraform (`terraform/prometheus.tf`) АБО налаштувати Grafana Cloud SaaS
  - [ ] Налаштувати scrape config для `/metrics` endpoint
  - [ ] Верифікувати що метрики збираються
- **Сесія:** —
- **Коміт:** —

#### S2.2 — Grafana dashboards
- **Пріоритет:** P0 | **Складність:** Середня | **Джерело:** `06_03`
- **Опис:** Grafana відсутня — 7+ метрик невидимі для команди
- **Статус:**
  - [ ] Розгорнути Grafana (Terraform або Grafana Cloud)
  - [ ] Dashboard: Sidekiq queues (9 черг, size + latency)
  - [ ] Dashboard: Web3 RPC errors by network
  - [ ] Dashboard: Telemetry ingest rate + fraud detection
  - [ ] Dashboard: Treasury / Oracle balance monitoring
  - [ ] Dashboard: Database connection pool stats
- **Сесія:** —
- **Коміт:** —

#### S2.3 — Alertmanager rules
- **Пріоритет:** P0 | **Складність:** Середня | **Джерело:** `06_03`
- **Опис:** Alertmanager не налаштований — Web3 оракули падають без сповіщень
- **Статус:**
  - [ ] Розгорнути Alertmanager (Terraform або Grafana Cloud Alerting)
  - [ ] Alert: `web3_critical` queue depth > 100
  - [ ] Alert: `silkennet_telemetry_fraud_detected_total` rate > 0
  - [ ] Alert: `silkennet_rpc_errors_total` rate > 10/min
  - [ ] Alert: Oracle balance < threshold
  - [ ] Alert: Sidekiq queue latency > 5 min
  - [ ] Налаштувати notification channel (Slack / Email / PagerDuty)
- **Сесія:** —
- **Коміт:** —

#### S2.4 — Додаткові Prometheus метрики
- **Пріоритет:** P1 | **Складність:** Низька-середня | **Джерело:** `06_03` gap analysis
- **Опис:** Відсутні метрики для важливих воркерів
- **Статус:**
  - [x] `slashing_events_total{reason}` — BurnCarbonTokensWorker
  - [x] `ota_chunks_sent_total{firmware_version}` — OtaTransmissionWorker
  - [x] `ews_alerts_total{alert_type}` — DclimateVerificationWorker
  - [x] `oracle_dispatch_duration_seconds` — ChainlinkDispatchWorker (histogram)
  - [x] `coap_packets_received_total{status}` — UnpackTelemetryWorker
  - [x] Додати метрики до `config/initializers/prometheus.rb`
  - [x] Інструментувати відповідні воркери
  - [ ] Додати тести (потребує PostgreSQL)
- **Результат:** ✅ 5 нових метрик зареєстровані та інструментовані в 5 воркерах
- **Сесія:** 2026-04-18 Сесія 2
- **Коміт:** `39f6e7e`

#### S2.5 — Structured JSON logging
- **Пріоритет:** P1 | **Складність:** Середня | **Джерело:** `06_03`
- **Опис:** Логи неструктуровані, кореляція з Sentry утруднена
- **Статус:**
  - [x] Впровадити structured JSON logger (Rails config)
  - [x] Додати correlation ID (request_id + Sentry trace)
  - [x] Верифікувати формат у production.rb
  - [x] Перевірити сумісність з Cloud Logging cost exclusion
- **Результат:** ✅ JSON logging з Oj serializer + Sentry trace_id/span_id correlation. Opt-out: `RAILS_LOG_JSON=false`.
- **Сесія:** 2026-04-18 Сесія 2
- **Коміт:** `39f6e7e`

---

### Sprint 3 — "Backend Completeness" (Тиждень 5-6)

#### S3.1 — Guard clause unification (BLOCKER-11)
- **Пріоритет:** P1 | **Складність:** Середня | **Джерело:** `04_02`
- **Опис:** Tokenomics flow guards активні тільки при `telemetry_log` (oracle-driven); direct growth_points flow bypasses guard clauses
- **Ризик:** Фінансова логіка inconsistency
- **Статус:**
  - [ ] Аудит: де `verified_by_iotex?` + `oracle_status_fulfilled?` + `hadron_kyc_status` перевіряються
  - [ ] Аудит: `TokenomicsEvaluatorWorker` flow без `telemetry_log`
  - [ ] Уніфікувати guard clauses для обох flow
  - [ ] Додати тести для обох сценаріїв
- **Сесія:** —
- **Коміт:** —

#### S3.2 — dClimate Real API integration
- **Пріоритет:** P1 | **Складність:** Середня | **Джерело:** `05_01`
- **Опис:** `Dclimate::VerificationService` — вже реалізований з реальним API (NASA FIRMS через dClimate)
- **Статус:**
  - [x] Сервіс реалізований (`app/services/dclimate/verification_service.rb`)
  - [x] Fire detection logic (FRP ≥ 10 MW, confidence ≥ 50%)
  - [x] Cloud obscuration fallback (retry via Sidekiq)
  - [x] Metadata extraction (satellite, timestamp)
  - [ ] Верифікувати з реальним API ключем в staging
  - [ ] End-to-end тест з `DclimateVerificationWorker`
- **Результат:** Переважно реалізовано
- **Сесія:** Аудит 2026-04-18

#### S3.3 — PuroEarth::PassportService
- **Пріоритет:** P1 | **Складність:** Середня | **Джерело:** `05_01`, `05_03`
- **Опис:** Сервіс для D-MRV Biomass Passport
- **Статус:**
  - [x] `PuroEarthPassportWorker` існує (`app/workers/puro_earth_passport_worker.rb`)
  - [x] `PuroEarth::PassportService` реалізований (`app/services/puro_earth/passport_service.rb`)
  - [x] SHA-256 payload hashing + Polygon anchoring
  - [ ] Інтеграція з реальним Puro.earth API (поточно: тільки on-chain anchoring)
  - [ ] Верифікувати end-to-end flow: мертве дерево → `MaintenanceRecord` → passport → on-chain
- **Результат:** Переважно реалізовано (on-chain anchoring є; Puro.earth REST API — TODO)
- **Сесія:** Аудит 2026-04-18

#### S3.4 — M2M Token refresh mechanism
- **Пріоритет:** P1 | **Складність:** Середня | **Джерело:** `04_03`
- **Опис:** 30-денний M2M token не має механізму автоматичного оновлення
- **Ризик:** Token expires mid-uplink для Gateway devices
- **Статус:**
  - [ ] Дизайн: sliding window refresh або auto-renew endpoint
  - [ ] Реалізація
  - [ ] Тести
- **Сесія:** —
- **Коміт:** —

#### S3.5 — Subgraph: ForestMinted (SFC) event
- **Пріоритет:** P2 | **Складність:** Низька-середня | **Джерело:** `05_03`
- **Опис:** SFC mint event не індексується The Graph
- **Статус:**
  - [x] `subgraph/subgraph.yaml` існує (SCC events індексуються)
  - [ ] Додати SFC data source у `subgraph.yaml`
  - [ ] Додати `ForestMinted` event handler у `src/mapping.ts`
  - [ ] Додати `ForestMintEvent` entity у `schema.graphql`
  - [ ] ⚠️ Contract address placeholder `0x0000...0000` — блокує deploy
- **Сесія:** —
- **Коміт:** —

#### S3.6 — Conntrack table tuning
- **Пріоритет:** P2 | **Складність:** Низька | **Джерело:** `06_01`
- **Опис:** Ризик overflow при масштабі (`nf_conntrack: table full, dropping packet`)
- **Статус:**
  - [x] CoAP UDP rate limiting додано до startup-script (`terraform/compute.tf`)
  - [x] Додати `sysctl` tuning: `net.netfilter.nf_conntrack_max=2000000`
  - [x] Додати `sysctl` tuning: `net.netfilter.nf_conntrack_udp_timeout=30`
- **Результат:** ✅ Conntrack tuning додано до startup-script, persistent через `/etc/sysctl.conf`
- **Сесія:** 2026-04-18 Сесія 2
- **Коміт:** `39f6e7e`

---

### Sprint 4 — "Akash Network" (Тиждень 7-8)

#### S4.1 — Akash ↔ Cloud SQL/Redis network isolation
- **Пріоритет:** P3 | **Складність:** Висока | **Джерело:** `06_02`
- **Опис:** Akash не може дістатися до Cloud SQL та Redis (приватні IP)
- **Блокує:** Будь-який реальний Akash deployment
- **Варіанти рішення:**
  1. Tailscale/WireGuard VPN tunnel
  2. Cloud SQL Auth Proxy sidecar
  3. Public IP + SSL + allowlist
- **Статус:**
  - [ ] Обрати архітектурне рішення
  - [ ] Реалізувати
  - [ ] Верифікувати connectivity
- **Сесія:** —
- **Коміт:** —

#### S4.2 — Docker image registry для Akash
- **Пріоритет:** P3 | **Складність:** Середня | **Джерело:** `06_02`
- **Опис:** Akash-провайдери не мають доступу до приватного GCP Artifact Registry
- **Статус:**
  - [ ] Створити mirror workflow → Docker Hub або GHCR
  - [ ] Оновити `deploy/akash/deploy.yaml` image reference
- **Сесія:** —
- **Коміт:** —

#### S4.3 — Akash SDL secrets
- **Пріоритет:** P3 | **Складність:** Низька | **Джерело:** `06_02`
- **Опис:** `REQUIRED_SECRET_NOT_SET` для 4 критичних змінних
- **Статус:**
  - [ ] Заповнити в `deploy/akash/deploy.yaml` (після S4.1)
  - [ ] Верифікувати startup
- **Сесія:** —
- **Коміт:** —

#### S4.4 — HTTPS/TLS у Akash SDL
- **Пріоритет:** P3 | **Складність:** Низька | **Джерело:** `06_02`
- **Опис:** Порт 443 (HTTPS) відсутній в SDL
- **Статус:**
  - [ ] Додати порт 443 до SDL expose
  - [ ] Налаштувати TLS termination (Akash ingress або Cloudflare)
- **Сесія:** —
- **Коміт:** —

#### S4.5 — Multi-replica sticky sessions
- **Пріоритет:** P3 | **Складність:** Середня | **Джерело:** `06_02`
- **Опис:** ActionCable/Turbo потребують sticky sessions при >1 репліці
- **Статус:**
  - [ ] Визначити load balancing strategy
  - [ ] Реалізувати sticky sessions або shared ActionCable adapter
- **Сесія:** —
- **Коміт:** —

---

## 🔧 Firmware Sprint (Паралельна команда)

### 🔴 P0 — Критичні

#### FW.1 — Hardcoded AES-256 Key
- **Джерело:** `03_01`, `03_02`, `03_05`, `05_02`
- **Опис:** Один і той самий ключ на ВСІХ вузлах мережі. Злам одного пристрою = компрометація всієї мережі
- **Файли:** `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:65-66`
- **Рішення:** Per-device provisioning через HKDF, Factory Flashing pipeline
- **Статус:**
  - [ ] Дизайн HKDF key derivation protocol
  - [ ] Backend: provisioning endpoint (POST `/api/v1/provisioning/register` вже існує)
  - [ ] Firmware: змінити key storage з hardcoded → Flash-based
  - [ ] Firmware: RDP Level 2 activation як final step
  - [ ] End-to-end тест provisioning flow
- **Сесія:** —
- **Коміт:** —

#### FW.2 — AES-256-ECB без MAC/MIC
- **Джерело:** `03_05`
- **Опис:** Детерміністичний шифротекст, replay/bit-flip attacks можливі. Немає автентифікації пакетів
- **Файли:** `firmware/soldier/main.c:747`, `firmware/queen/main.c:781`
- **Рішення:** AES-256-GCM або додавання HMAC-SHA256 MIC (4-byte suffix)
- **Статус:**
  - [ ] Обрати: GCM (одна операція) vs HMAC MIC (простіше, але +4 байти)
  - [ ] Зміна формату пакету (21 → 25 байт або оптимізація payload)
  - [ ] Firmware: оновити encrypt/decrypt
  - [ ] Backend: оновити `TelemetryUnpackerService`
  - [ ] Тести
- **Сесія:** —
- **Коміт:** —

#### FW.3 — Queen AT Command Blocking (~25 сек)
- **Джерело:** `03_01`, `03_02`
- **Опис:** Queen "сліпа" до LoRa пакетів під час CoAP flush. Single-packet buffer — пакети втрачаються
- **Рішення:** UART DMA interrupt-driven + ring buffer
- **Статус:**
  - [ ] Переписати `Flush_Cache_To_Rails()` на UART DMA
  - [ ] Замінити single-packet buffer на ring buffer
  - [ ] Додати CoAP response parsing (замість blind HAL_Delay)
  - [ ] Тести
- **Сесія:** —
- **Коміт:** —

#### FW.4 — TinyML `Run_Inference()` закоментований
- **Джерело:** `03_03`
- **Опис:** `Run_Inference()` закоментована (main.c:355); `silken_net_audio_model.h` відсутній
- **Блокує:** Acoustic detection (chainsaw, cavitation, wind)
- **Статус:**
  - [ ] Тренування моделі (4 класи: silence/wind/cavitation/chainsaw)
  - [ ] Генерація `silken_net_audio_model.h`
  - [ ] DSP preprocessing (FFT/MFCC або вбудований у модель)
  - [ ] Verify Tensor Arena size (< 54 KB)
  - [ ] Розкоментувати `Run_Inference()`
  - [ ] Host-based тести
- **Сесія:** —
- **Коміт:** —

### 🟠 P1 — Важливі

#### FW.5 — Lorenz Attractor: delta_t/vcap не передаються
- **Джерело:** `03_04`, `05_02`
- **Опис:** Spec: `calculate_state(delta_t, vcap)`, реалізація: `calculate_state(chaos_seed, temp, acoustic)`
- **Статус:**
  - [ ] Архітектурне рішення: прийняти "snapshot" модель АБО змінити firmware inputs
  - [ ] Задокументувати рішення в `03_04`
  - [ ] Реалізувати (якщо зміна)
- **Сесія:** —
- **Коміт:** —

#### FW.6 — Lorenz State persistence
- **Джерело:** `03_04`
- **Опис:** Стан (x,y,z) НЕ зберігається між циклами STOP2 в RTC Backup Registers
- **Статус:**
  - [ ] Зберегти (x,y,z) у RTC DR0-DR5 (3 × float → 3 × uint32_t)
  - [ ] Відновити при wakeup
  - [ ] Тести
- **Сесія:** —
- **Коміт:** —

#### FW.7 — Float vs BigDecimal divergence
- **Джерело:** `05_02`
- **Опис:** firmware `8.0/3.0 = 2.6666666666666665` vs backend BigDecimal `2.666666666666666667`
- **Рішення:** Документувати як "by design" + tolerance band (±2.0 на Z) або integer math на firmware
- **Статус:**
  - [ ] Рішення: tolerance band АБО integer math
  - [ ] Задокументувати в `05_02` та `03_04`
  - [ ] Якщо tolerance — додати відповідний check у `SilkenNet::Attractor` (backend)
- **Сесія:** —
- **Коміт:** —

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- **Джерело:** `05_02`
- **Опис:** firmware: global 2.0/45.0 vs backend: per-species через `TreeFamily`
- **Рішення:** OTA sync species-specific thresholds
- **Статус:**
  - [ ] Додати thresholds до OTA config payload
  - [ ] Firmware: зберігати thresholds у Flash/RTC
  - [ ] Backend: включити thresholds у OTA bytecode
- **Сесія:** —
- **Коміт:** —

#### FW.9 — CoAP retry logic
- **Джерело:** `03_02`
- **Опис:** Після AT+CCOAPSEND: `HAL_Delay(2000)` без парсингу відповіді. ACK miss → весь кеш втрачається
- **Статус:**
  - [ ] Парсинг UART RX для `OK`/`ERROR` відповіді модему
  - [ ] Double-buffering або persistent buffer для retry
  - [ ] Configurable retry count
- **Сесія:** —
- **Коміт:** —

#### FW.10 — Temperature-based TX deferral
- **Джерело:** `02_04`
- **Опис:** При T < -15°C ESR іоністора зростає; може спричинити просадку LoRa TX
- **Статус:**
  - [ ] Додати check: якщо `temp < -15` && `vcap_voltage < 4.0V` → відкласти TX
  - [ ] Тести
- **Сесія:** —
- **Коміт:** —

### 🟢 P2 — Низькопріоритетні firmware fixes

#### FW.11 — Race condition: `vibration_detected`
- **Джерело:** `03_03`
- **Опис:** Між read та write немає атомарності (ISR vs main loop)
- **Статус:**
  - [ ] Wrap read-clear-start у `__disable_irq()` / `__enable_irq()`
  - [ ] Тести
- **Сесія:** —
- **Коміт:** —

#### FW.12 — `acoustic_events` overflow
- **Джерело:** `03_03`
- **Опис:** uint16_t але пакується в uint8_t; >255 events → silent corruption
- **Статус:**
  - [ ] `lora_payload[7] = (uint8_t)MIN(acoustic_events, 255);`
  - [ ] Тести
- **Сесія:** —
- **Коміт:** —

#### FW.13 — Dead code: `reward > 0 ? reward : 10`
- **Джерело:** `03_04`
- **Опис:** В homeostasis zone, `reward` завжди > 0, тому ternary завжди вибирає `reward`
- **Статус:**
  - [ ] Замінити на explicit `clamp(reward, 10, 63)`
- **Сесія:** —
- **Коміт:** —

#### FW.14 — Error_Handler без відновлення
- **Джерело:** `03_01`
- **Опис:** `Error_Handler()` = infinite loop без `NVIC_SystemReset()`
- **Статус:**
  - [ ] Додати `NVIC_SystemReset()` або logging + soft reset
- **Сесія:** —
- **Коміт:** —

---

## 🧪 Hardware / Lab — Блокери

> ⚠️ Ці пункти потребують фізичної роботи в лабораторії та/або з підрядниками. Трекаються тут для повноти.

#### HW.1 — nTop model → DMLS factory
- **Джерело:** `01_01`
- **Статус:** ✅ Ліцензія отримана
  - [ ] Генерація TPMS gyroid geometry (65% порosity)
  - [ ] STL/STEP файл → передати на DMLS завод (Київ/Дніпро)
  - [ ] SEM criteria для приймання партії

#### HW.2 — Dual-scale roughness spec
- **Джерело:** `01_02`
- **Опис:** Sa 0.5-5 µm, Sv 50-500 nm НЕ передана на завод
- **Блокує:** Максимальний струм EBFC, TRL 5
- **Статус:**
  - [ ] Підготувати factory spec з метриками
  - [ ] Передати на завод
  - [ ] Отримати SEM images ×500/×5,000/×50,000

#### HW.3 — Accelerated aging test (Arrhenius)
- **Джерело:** `01_02`
- **Опис:** 12-тижневий тест у synthetic xylem sap
- **Блокує:** Seed раунд, whitepaper, TRL 5→6
- **Статус:**
  - [ ] Синтез штучного ксилемного соку (потрібен ботанік)
  - [ ] Запуск 12-тижневого тесту
  - [ ] ICP-MS аналіз: Ti < 0.1 µg/cm², V < 0.02 µg/cm²
  - [ ] EIS degradation < 50%

#### HW.4 — Self-healing coating
- **Джерело:** `01_02`
- **Опис:** 8-HQ мікрокапсули не синтезовані
- **Блокує:** 20+ років longevity claims, TRL 6
- **Статус:**
  - [ ] Синтез 8-HQ мікрокапсул (in-situ polymerization)
  - [ ] Інтеграція в PEO electrolyte або layer-by-layer
  - [ ] Тест: 10× вищий Rct

#### HW.5 — Enzyme lifespan
- **Джерело:** `01_03`
- **Опис:** GOx/Laccase деградація у кислому ксилемному середовищі (pH 4.5-5.5)
- **Статус:**
  - [ ] Розробка protective polymer matrix
  - [ ] Тест: 3-5 років функціонального ферменту

#### HW.6 — Resin barrier
- **Джерело:** `01_04`
- **Опис:** Сосни заливають рану смолою → блокує доступ до ферментів
- **Статус:**
  - [ ] 30° installation angle verification
  - [ ] Hydrophilic coating test
  - [ ] Optional: thermal installation test

#### HW.7 — BQ25570 resistors verification
- **Джерело:** `02_03`
- **Опис:** CJMCU-25570 може мати Li-Po дефолт (VBAT_OV = 4.2V замість 5.5V для supercap)
- **Блокує:** Фіналізацію схеми, PCBA production
- **Статус:**
  - [ ] Виміряти 8 резисторів мультиметром
  - [ ] Порівняти з розрахунковою таблицею (Section 4 в `02_03`)
  - [ ] Замінити SMD резистори якщо мисматч
  - [ ] Задокументувати фінальні номінали

#### HW.8 — Pogo pin specification (5 блокерів)
- **Джерело:** `02_02`
- **Статус:**
  - [ ] BLOCKER-1: Матеріал напилення → Gold (Hard Gold, Au 0.76 µm)
  - [ ] BLOCKER-2: Сила пружини → ~100 г/пін, Travel ≥ 1.5 мм
  - [ ] BLOCKER-3: Механізм фіксації → Quarter-turn bayonet (рекомендовано)
  - [ ] BLOCKER-4: O-ring → EPDM, CS 1.5-2.0 мм, 15-25% compression
  - [ ] BLOCKER-5: Допуски соосності → Lead-in chamfer

#### HW.9 — PCB KiCad layouts
- **Джерело:** `02_01`
- **Опис:** Soldier PCB та Queen PCB: "Не розпочато"
- **Статус:**
  - [ ] Soldier PCB layout (KiCad)
  - [ ] Queen PCB layout (KiCad)
  - [ ] RF Keep-Out Zone verification

#### HW.10 — Modem name discrepancy
- **Джерело:** `02_05`
- **Опис:** SIM7000G (Wiki) vs SIM7070G (firmware AT-commands)
- **Статус:**
  - [ ] Фізично перевірити маркування на прототипі
  - [ ] Узгодити Wiki, BOM та firmware

---

## 📝 Юридичні / Бізнес блокери

#### BIZ.1 — 1 SCC = ? kg CO₂
- **Джерело:** `07_01`
- **Опис:** CO₂ еквівалент для 1 SCC не визначений — ЮРИДИЧНИЙ БЛОКЕР
- **Блокує:** Carbon credit marketplace integration
- **Статус:**
  - [ ] Визначити методологію розрахунку
  - [ ] Додати в код (constants або config)
  - [ ] Задокументувати для carbon registries

#### BIZ.2 — B2B MSA (Master Service Agreement)
- **Джерело:** `07_01`
- **Статус:**
  - [ ] Створити юридичний шаблон
  - [ ] Review з юристом

#### BIZ.3 — B2C ToS / Privacy Policy
- **Джерело:** `07_01`
- **Статус:**
  - [ ] Terms of Service draft
  - [ ] Privacy Policy (GDPR-compliant)
  - [ ] Cookie Policy

#### BIZ.4 — DAO Governance Process
- **Джерело:** `07_01`, `05_03`
- **Опис:** SFC voting mechanism не визначений
- **Статус:** Post-TRL 6 (не блокує прототип)
  - [ ] GovernorContract.sol design
  - [ ] ProtocolParameters.sol registry
  - [ ] Governance::ParameterSyncWorker

#### BIZ.5 — Patent application
- **Джерело:** `08_03`
- **Статус:**
  - [ ] Engagement з патентним адвокатом
  - [ ] Патентна заявка на дизайн анкера

---

## 🎓 Академічні блокери (ЧНУ)

#### UNI.1 — Перший контакт з деканом Онищенком
- **Джерело:** `08_01`
- **Блокує:** Всю лабораторну роботу, 10 публікацій, 11 магістерських
- **Статус:**
  - [ ] Призначити зустріч
  - [ ] Підготувати презентацію проєкту
  - [ ] Провести зустріч

#### UNI.2 — 8 зустрічей з факультетом ФОТІУС
- **Джерело:** `8_02`
- **Статус:**
  - [ ] Супруненко (ПЗАС) — PN-verification, Convolution Method
  - [ ] Онищенко (Декан) — stochastic B&B, Petri nets
  - [ ] Ярмілко — Embedded Systems, ECDH key exchange
  - [ ] Порублів — Discrete Math, reliability
  - [ ] Косенук — RF/FEC/compliance
  - [ ] Бушин — CNN/BSP/DMLS physics
  - [ ] Осауленко — Portfolio management
  - [ ] Любченко — GA/Neural Networks

#### UNI.3 — IP договір з ЧНУ
- **Джерело:** `08_03`
- **Блокує:** Старт публікацій
- **Статус:**
  - [ ] Юридичне оформлення IP-договору
  - [ ] Підпис обома сторонами

---

## 💡 Додаткові знахідки (не блокери, але варті уваги)

| # | Знахідка | Джерело | Статус |
|---|----------|---------|--------|
| E.1 | SFC voting power зберігається після slashing | `07_01` | [ ] Дослідити |
| E.2 | Oracle private key має MINTER + SLASHER roles (single point of failure) | `07_01` | [ ] Розділити ролі |
| E.3 | Breadboard video відсутнє (потрібне для грантів) | `07_03` | [ ] Зняти відео |
| E.4 | Helium Network fallback — concept є, реалізації немає | `02_05` | [ ] Дизайн + реалізація |
| E.5 | CoAP listener — Ruby, масштабується до ~10k вузлів | `06_01` | [ ] Series D: Rust/Go proxy |
| E.6 | `gateway_id` FK exists but not used by Rails | `04_01` | [ ] Аудит + cleanup |
| E.7 | SFC ForestMinted event не індексується The Graph | `05_03` | Дублює S3.5 |
| E.8 | OPTIMAL_Z: коментар каже 20.0, константа 29.0 | `03_04` | [ ] Уточнити |
| E.9 | Queen HRNG IV reuse при blackout (IV→0) | `03_02` | [x] Виправлено PR #273 |
| E.10 | Queen OTA loop: `ota_is_active` ніколи не скидався | `03_02` | [x] Виправлено PR #273 |

---

## 📊 TRL Матриця по модулях

| Модуль | Поточний TRL | Цільовий TRL | Головний блокер | Трекер |
|--------|-------------|-------------|-----------------|--------|
| 00 System Architecture | 4 | 9 | Module 01 chemistry | — |
| 01 Materials & EBFC | 3 | 6 | Lab tests (ЧНУ) | HW.1-HW.6 |
| 02 Hardware & BOM | 4 | 6 | BQ25570, PCB layout | HW.7-HW.10 |
| 03 Firmware | 6 | 8 | AES key, TinyML, AT blocking | FW.1-FW.14 |
| 04 Backend Rails | 8 | 9 | Guard clauses, Prometheus | S1-S3 |
| 05 Web3 Pipeline | 8-9 | 9 | PuroEarth real API | S3.3, S3.5 |
| 06 DevOps | 6 | 9 | Prometheus, Akash isolation | S2, S4 |
| 07 Business | 5 | 8 | CO₂ methodology, MSA | BIZ.1-BIZ.5 |
| 08 University R&D | 2 | 6 | ЧНУ partnership | UNI.1-UNI.3 |
| 09 Project Management | 7 | 9 | TRL auto-advancement | — |

---

## 📝 Журнал оновлень

| Дата | Сесія | Зміни |
|------|-------|-------|
| 2026-04-18 | Аудит документації | Створено документ. Аудит 35 docs. Відмічені вже реалізовані пункти: S1.2, S3.2, S3.3, E.9, E.10 |
| 2026-04-18 | Сесія 2 — Sprint 1-3 | ✅ S1.3: `terraform/bootstrap.sh` створено. ✅ S1.6: Верифіковано — вирішено. ✅ S1.7: Legacy кольори видалені. ✅ S1.8: Naming fix (попередня сесія). ✅ S2.4: 5 нових Prometheus метрик + інструментація 5 воркерів. ✅ S2.5: Structured JSON logging з Sentry correlation. ✅ S3.6: Conntrack sysctl tuning у Terraform. |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
> 3. Заповнити поля **Сесія** та **Коміт**
> 4. Додати запис у таблицю **Журнал оновлень**
> 5. Оновити **Зведену статистику** вгорі (якщо блокер закрито)
> 6. Оновити поле **Останнє оновлення** у шапці документа
