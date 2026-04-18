# 10_02 — Action Plan Tracker (Живий Документ)

> **Створено:** 2026-04-18 (Аудит 35 документів `00_00` → `09_03`)
> **Останнє оновлення:** 2026-04-18 (Повний аудит docs + codebase: +40 нових пунктів)
> **Відповідальний:** AI Copilot Sessions + Core Team
> **Принцип:** Кожна сесія оновлює чекбокси `[ ]` → `[x]` та додає дату + коміт.

---

## 📊 Зведена статистика

| Категорія | Знайдено | Виправлено | Залишилось |
|-----------|----------|------------|------------|
| Явні BLOCKER'и | ~85 | ~35 | ~50 |
| Архітектурні рішення / пропозиції | ~35+ | — | Задокументовані |
| Рекомендації | ~45+ | — | В роботі |
| Відкриті питання | ~30+ | — | В роботі |
| Технічний борг | ~35+ | — | В роботі |
| Безпекові проблеми | ~25+ | ~3 | В роботі |
| Не реалізовані фічі | ~30+ | — | В роботі |
| Невідповідності код ↔ документація | ~15 | — | В роботі |
| Hardware / Lab блокери | ~20+ | — | Потребують фізичної роботи |

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
- **Пріоритет:** P1 | **Складність:** Низька-середня | **Джерело:** `06_03`
- **Опис:** 5 нових метрик реалізовано та інструментовано (Sprint 2). Задокументовано в `06_03` розділ 2.4.
- **Статус:**
  - [ ] Додати RSpec тести для нових метрик (потребує PostgreSQL)
- **Сесія:** 2026-04-18 Сесія 2
- **Коміт:** `39f6e7e`

---

### Sprint 3 — "Backend Completeness" (Тиждень 5-6)

#### S3.1 — Guard clause audit
- **Пріоритет:** P1 | **Складність:** Середня | **Джерело:** `04_02`
- **Опис:** Аудит завершено (Sprint 3). Архітектура коректна by design (задокументовано в `04_02` та трекері). Oracle-driven flow: IoTeX + Chainlink guards ENFORCED. Batch emission: guards bypassed intentionally. `hadron_kyc_status` завжди перевіряється.
- **Статус:**
  - [ ] Додати RSpec тести для обох сценаріїв (потребує PostgreSQL)
- **Сесія:** 2026-04-18 Сесія 3

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
  - [x] Дизайн: sliding window refresh — `POST /api/v1/auth/m2m_token/refresh` з Bearer token
  - [x] Реалізація: `M2mAuthController#refresh`, route, backward-compatible
  - [x] Тести: 4 request specs (valid token, invalid token, no token, new token validity)
- **Сесія:** 2026-04-18 Сесія 5 — Action Plan Tracker
- **Коміт:** (pending)

#### S3.5 — Subgraph: ForestMinted (SFC) event
- **Пріоритет:** P2 | **Складність:** Низька-середня | **Джерело:** `05_03`
- **Опис:** SFC events (ForestMinted, GovernanceSlashed) додано до subgraph (Sprint 3). Задокументовано в `05_03` розділ Subgraph.
- **Статус:**
  - [ ] ⚠️ Contract address placeholder `0x0000...0000` у `subgraph.yaml` — блокує deploy subgraph

#### S3.6 → Виконано, задокументовано в `06_01` (Ризик-1, conntrack sysctl tuning)

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
- **Рішення (рекомендоване):** **AES-256-CCM** (апаратно підтримується STM32WLE5JC) з новим 24-байтним пакетом: `[DID:4][SensorData:8][FrameCounter:4][MIC:4][Reserved:4]`. Frame Counter у RTC Backup Domain як Nonce. MIC апаратно генерується CCM. Вирішує BLOCKER-2 та BLOCKER-3 одночасно
- **Альтернативи:** AES-256-GCM, AES-256-CTR + HMAC-SHA256 MIC (4-byte suffix)
- **Статус:**
  - [ ] Верифікувати `CRYP_AES_CCM` підтримку на цільовій ревізії STM32WLE5JC
  - [ ] Дизайн 24-байтного пакету (8 байт sensor data vs поточних 16 — оптимізувати поля)
  - [ ] Firmware Soldier: CCM encrypt + Frame Counter інкремент + MIC append
  - [ ] Firmware Queen: CCM decrypt + Frame Counter validation (anti-replay)
  - [ ] Backend: оновити `TelemetryUnpackerService` для 24-байтного формату
  - [ ] LoRa airtime budget verification (24B vs 16B при SF10/DR2)
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

> FW.12 (acoustic_events saturation), FW.13 (clamp fix), FW.14 (Error_Handler soft reset) — виконано та задокументовано в `03_01`, `03_04`.

#### FW.15 — Missing test suites: TinyML, Crypto, Bio-Contract
- **Джерело:** `03_03` BLOCKER-4 + codebase audit
- **Опис:** `firmware/test/` має лише `test_soldier_logic.c` та `test_queen_logic.c`. Відсутні: тести аудіо-пайплайну (mock `Run_Inference`), тести AES-256 ECB/CBC mode switching, тести Lorenz attractor math (`calculate_z_axis`)
- **Ризик:** Зміни в crypto або bio-contract пройдуть CI без валідації
- **Статус:**
  - [ ] `test_tinyml_pipeline.c` — mock Run_Inference(), 4 класи × confidence boundary
  - [ ] `test_encryption.c` — ECB/CBC switching, ECB restore, key verification
  - [ ] `test_bio_contract.c` — σ/ρ clamp, Z-axis bounds, growth_points calculation
- **Сесія:** —
- **Коміт:** —

#### FW.16 — ECB restore race condition при HAL_CRYP_Init failure
- **Джерело:** `03_05` BLOCKER-6
- **Опис:** `HAL_CRYP_Init()` для restore ECB не має timeout. Якщо AES peripheral зависне (hardware defect), наступний LoRa decrypt використає CBC → garbage → data loss. Handle_CoAP_Command error path може повернутися без ECB restore
- **Рішення:** Перевірка return code `HAL_CRYP_Init()`. При помилці — жорсткий апаратний скид: `__HAL_RCC_CRYP_FORCE_RESET()` + `__HAL_RCC_CRYP_RELEASE_RESET()` + повторна ініціалізація. Якщо повторна ініціалізація теж невдала — `NVIC_SystemReset()` (повний перезапуск MCU)
- **Статус:**
  - [ ] Додати return-code check на `HAL_CRYP_Init()` при ECB restore
  - [ ] Додати RCC CRYP_FORCE_RESET як hard recovery path
  - [ ] Verify `hcryp.State` перед кожним Encrypt/Decrypt
  - [ ] Забезпечити ECB restore навіть на error path
- **Сесія:** —
- **Коміт:** —

#### FW.17 — Key rotation mechanism
- **Джерело:** `03_05` BLOCKER-5
- **Опис:** Поточна архітектура: статичний ключ при Factory Flashing. Немає механізму зміни ключа без перепрошивки всіх вузлів. Порушує GDPR/ISO 27001/NIST SP 800-57
- **Рішення (рекомендоване — Hash Ratchet KDF):** Синхронна деривація нового ключа на обох кінцях без передачі ключа по мережі. Backend надсилає `CMD:ROTATE_KEY:<UUID>` → Queen + Soldier одночасно проганяють `K_current` через AES-KDF → `K_next`. Забезпечує Perfect Forward Secrecy (PFS): компрометація поточного ключа не розкриває попередній трафік
- **Статус:**
  - [ ] Дизайн Hash Ratchet протоколу (AES-based KDF on STM32 hardware)
  - [ ] CMD:ROTATE_KEY CoAP command + OTA relay через Queen
  - [ ] Cluster-wide activation confirmation (ACK від усіх вузлів)
  - [ ] Зберігання `K_current` та `rotation_counter` у Flash/RTC Backup Domain
  - [ ] Consider ECDH/Curve25519 key exchange при provisioning (альтернатива)
- **Пріоритет:** Після FW.1 (per-device provisioning) — future cycle
- **Сесія:** —
- **Коміт:** —

#### FW.18 — Hardcoded confidence threshold 0.80
- **Джерело:** `03_03` BLOCKER-6
- **Опис:** `if (ml_confidence > 0.80)` hardcoded в Flash. Неможливо remote-tune для різних лісів/сезонів. Немає "warning" рівня (лише binary: alarm / no alarm)
- **Статус:**
  - [ ] Зберегти threshold у RTC Backup Register (updateable via OTA)
  - [ ] Дизайн dual-threshold: WARNING (0.60) → event counter; CRITICAL (0.85) → Emergency TX
- **Сесія:** —
- **Коміт:** —

#### FW.19 — Float32 vs Float64 mruby compile flags
- **Джерело:** `03_04` BLOCKER-4
- **Опис:** mruby без `MRB_USE_FLOAT` використовує double (64-bit), з прапорцем — float (32-bit). Makefile не верифікований. Різниця ±5-10 units на Z-осі після 250 ітерацій може змінити bio_status (false slashing)
- **Статус:**
  - [ ] Верифікувати mruby compile flags (`MRB_USE_FLOAT` у Makefile або mrbconf.h)
  - [ ] Додати tolerance band у `TelemetryUnpackerService` (±2.0 на Z)
  - [ ] Задокументувати результат
- **Сесія:** —
- **Коміт:** —

#### FW.20 — LoRa Time Sync (clock drift compensation)
- **Джерело:** Legacy notes
- **Опис:** Дешеві кварцові резонатори / внутрішні осцилятори STM32 мають температурний дрейф. При -20°C та +40°C RTC годинник Soldier йде з різною швидкістю. За кілька місяців автономної роботи без LTE-синхронізації "час дерева" розсинхронізується з "часом бекенду" на хвилини або години. Це впливає на: (1) `created_at` timestamp у TelemetryLog → partition pruning errors, (2) HMAC/nonce replay protection windows, (3) cron-like wakeup scheduling
- **Рішення:** Протокол Time Sync через Queen downlink. Queen має точний час через LTE/NTP. Періодично (раз на добу або при flush ACK) Queen надсилає OTA-корекцію часу (downlink). Soldier звіряє свій RTC і застосовує поправку. Аналог LoRaWAN MAC command `DeviceTimeReq`
- **Статус:**
  - [ ] Firmware Queen: додати time correction у CoAP ACK або окремий downlink command
  - [ ] Firmware Soldier: прийняти та застосувати RTC correction
  - [ ] Backend: включити server UTC timestamp у downlink payload
  - [ ] Тести: перевірити drift compensation при ΔT = ±60°C
- **Пріоритет:** P2 (не блокує TRL 6, критичний для тривалої автономної роботи TRL 7+)
- **Сесія:** —
- **Коміт:** —

#### FW.21 — Edge data aggregation (RAM-aware Soldier)
- **Джерело:** Legacy notes + `08_02` (Kalman filter Vector 4)
- **Опис:** Soldier MCU має обмежений RAM (~20 KB вільного). При накопиченні даних (acoustic_events, delta_t history) між wakeup циклами, є ризик buffer overflow. Поточна архітектура: кожен wakeup → один 21-байтний пакет → TX. Але для майбутнього (Kalman filtering, TinyML context) потрібна локальна агрегація
- **Рішення:** Використовувати moving average / exponential moving average (EMA) прямо на MCU. Відправляти на Queen лише: (1) поточне значення, (2) дельту від попереднього EMA, (3) стиснуті "summary" пакети замість raw arrays. Це зменшує трафік LoRa та економить батарею
- **Статус:**
  - [ ] Визначити які метрики потребують EMA (delta_t, vcap — кандидати)
  - [ ] Реалізувати lightweight EMA на Soldier (O(1) memory, O(1) compute)
  - [ ] Інтегрувати з Kalman filter design (E.10 — Косенук)
  - [ ] Верифікувати RAM footprint залишається < 80% available
- **Пріоритет:** P2 (пов'язано з E.10, потребує R&D partnership)
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
- **Джерело:** `01_04` + Legacy notes
- **Опис:** Сосни заливають рану смолою → блокує доступ до ферментів
- **Статус:**
  - [ ] 30° installation angle verification
  - [ ] Hydrophilic coating test
  - [ ] Hydrophobic/hydrophilic gradient test (PTFE на нижній частині гіроїда, гідрофільний верх) — додано в `01_04`
  - [ ] Thermal installation test: визначити точну T° нагріву (150-200°C рекомендовано), час витримки, глибину прогріву — додано в `01_04`
  - [ ] FEM-моделювання теплового поля в Ti-6Al-4V анкері (λ = 6.7 W/m·K — низька теплопровідність!)

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

#### HW.11 — Potting material selection (quartz resonator risk)
- **Джерело:** `02_01` BLOCKER-1
- **Опис:** Потрібно обрати epoxy compound що НЕ знищить quartz resonator LoRa модуля при -20°C. Rigid compound при температурному стисненні → тріщини кварцу → RF loss
- **Рішення:** Soft compound Shore A < 50 (Dow Sylgard 184 або аналог)
- **Статус:**
  - [ ] Обрати compound (Sylgard 184 рекомендовано)
  - [ ] Верифікувати з кварцовим резонатором при -20°C / +60°C
- **Блокує:** Hardware freeze, IP67 certification

#### HW.12 — EBFC upper voltage limit >5.5V protection
- **Джерело:** `02_01` BLOCKER-2
- **Опис:** При тривалій інсоляції EBFC може генерувати напругу >5.5V → overcharge supercap → деградація/вибух
- **Статус:**
  - [ ] Верифікувати BQ25570 OV protection threshold (VBAT_OV = 5.5V, див. HW.7)
  - [ ] Додати TVS-діод або зенерівський обмежувач як backup
- **Блокує:** Hardware safety, TRL 5

#### HW.13 — MPPT coefficient verification for EBFC
- **Джерело:** `02_03` BLOCKER-2
- **Опис:** Поточний MPPT = 50% VOC (ROC1=ROC2=10MΩ) — теоретична оцінка. Реальний оптимум для EBFC (Ti-6Al-4V | GOx/Laccase | Pinus sylvestris) може бути 60-70%
- **Статус:**
  - [ ] Виміряти VOC та VMP при різному освітленні (ранок/день/вечір, сезонно)
  - [ ] Визначити оптимальну фракцію
  - [ ] Якщо потрібно — замінити ROC1/ROC2
- **Блокує:** Max EBFC power, optimal charge speed

#### HW.14 — Winter energy deficit for Queen Phase 3 (Starlink Mini)
- **Джерело:** `02_05` BLOCKER-2
- **Опис:** Phase 3 (Starlink Mini): 44 Wh/day consumption vs 18.75 Wh/day winter generation = -25 Wh/day deficit. 12V/20Ah LiFePO4 → 7.7 днів автономності
- **Статус:**
  - [ ] Збільшити батарею до 40Ah (15 днів автономності), АБО
  - [ ] Зменшити Starlink duty cycle до 1 хв/год (~9 Wh/day), АБО
  - [ ] Встановити 100W solar panel
  - [ ] Оновити Unit Economics (07_02)
- **Пріоритет:** Phase 3 only (Phase 2.5 unaffected)

#### HW.15 — BMS not specified for Queen
- **Джерело:** `02_05` BLOCKER-4
- **Опис:** SIM7070G TX peak current до 2A. BMS model не вказано в BOM
- **Статус:**
  - [ ] Обрати BMS: мінімум 12V / 20A continuous / 50A peak
  - [ ] Обрати MPPT: мінімум Victron SmartSolar MPPT 75/15
  - [ ] Оновити BOM

#### HW.16 — Thermal management в IP67 enclosure
- **Джерело:** `02_05` BLOCKER-5
- **Опис:** SIM7070G + MCU при TX: ~500 mW × 5 sec. Літній interior temp до 60-70°C. LiFePO4 charging при T < 0°C пошкоджує батарею
- **Статус:**
  - [ ] Розрахувати thermal budget для enclosure (T_ext = +40°C)
  - [ ] Додати temperature sensor (NTC або DS18B20)
  - [ ] Реалізувати hardware charge protection при T < 0°C

#### HW.17 — PEEK radome prototype
- **Джерело:** `02_01`
- **Опис:** PEEK-Radome прототип "Не розпочато". Потребує KiCad PCB dimensions
- **Блокує:** Ceramic antenna protection, RF performance validation
- **Статус:**
  - [ ] KiCad PCB layout (HW.9) → PEEK radome dimensions
  - [ ] Замовити PEEK прототип

#### HW.18 — Starlink DTC: ESP32-S3 vs SIM8200G-M2 WiFi co-processor
- **Джерело:** `02_05` BLOCKER-1
- **Опис:** Phase 3 (Starlink Mini terminal) потребує WiFi co-processor. Архітектурне рішення між ESP32-S3 та SIM8200G-M2 не прийнято
- **Статус:**
  - [ ] Прийняти архітектурне рішення
  - [ ] Оновити 03_02 з рішенням
  - [ ] Додати co-processor firmware до `firmware/`
- **Пріоритет:** Phase 3 only

#### HW.19 — VOC-діагностика деградації конденсатора (ADS1220 + TPS22860)
- **Джерело:** Legacy notes + `02_04` §4.2
- **Опис:** Раз на добу вимірювати чисту VOC EBFC (при від'єднаному навантаженні) для розрізнення "дерево хворіє" vs "конденсатор деградує". Обидва стани проявляються як зростання delta_t. ADS1220 (24-bit ADC) + TPS22860 (load switch) для прецизійного duty-cycling вимірювання. Для TRL 6 достатньо вбудованого 12-біт ADC STM32
- **Статус:**
  - [ ] Валідувати концепт на вбудованому 12-біт ADC (firmware: GPIO disconnect EDLC → measure VOC → reconnect)
  - [ ] Якщо 12-біт недостатньо — додати ADS1220 + TPS22860 до BOM
  - [ ] Backend: поле `voc_mv` у TelemetryLog для серверної корекції моделі Лоренца
- **Пріоритет:** TRL 8+ (після базової валідації в полі)

---

## 🔐 Безпекові пункти

#### SEC.1 — Multisig Gnosis Safe для production admin role
- **Джерело:** `05_03` Operational Security
- **Опис:** `DEFAULT_ADMIN_ROLE` у production контрактах SCC/SFC має бути Gnosis Safe multisig (3/5 або 2/3), а не EOA
- **Статус:**
  - [ ] Створити Gnosis Safe wallet
  - [ ] Reassign DEFAULT_ADMIN_ROLE у SCC та SFC контрактах
- **Пріоритет:** Before mainnet deploy

#### SEC.2 — RDP Level 2 activation timeline
- **Джерело:** `03_05` NOTE-1
- **Опис:** Поточний стан: RDP Level 0 (development). Level 1 потрібен перед першою польовою партією, Level 2 — тільки після повної OTA верифікації (незворотній — лише OTA updates можливі)
- **Статус:**
  - [ ] Верифікувати OTA flow end-to-end
  - [ ] Перейти на RDP Level 1 для field batch
  - [ ] Задокументувати процедуру Level 2 activation (необоротна)

#### SEC.3 — Factory Flashing pipeline
- **Джерело:** `03_05` NOTE-2
- **Опис:** Multi-step factory process: (1) Flash firmware з placeholder key, (2) Backend → HKDF(master_key, device_uid) → unique_key, (3) Robot пише key у protected Flash sector, (4) STM32CubeProgrammer → RDP Level 1/2
- **Блокує:** Mass production
- **Статус:**
  - [ ] Дизайн завершений
  - [ ] Реалізація Factory Flashing tool
  - [ ] Integration тест з provisioning API

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **Джерело:** `03_05` NOTE-3
- **Опис:** Reed switch (магнітний сенсор) для zero consumption при транспортуванні. Магніт на коробці → circuit open. Інсталятор знімає магніт → first power-up. ~$0.05/unit. Дизайн approved, BOM не оновлений
- **Статус:**
  - [ ] Додати Hamlin 59140-1-T-00-A reed switch + N52 neodymium magnet до BOM
  - [ ] Оновити KiCad schematic

---

## 🏗️ Інфраструктурні пункти (Akash / Terraform / Deploy)

#### INF.1 — Akash ↔ Cloud SQL/Redis network isolation (CRITICAL)
- **Джерело:** `06_02` BLOCKER-1
- **Опис:** Akash providers — поза GCP VPC. Cloud SQL: private IP only. Memorystore Redis: NO public IP option. Akash workers не можуть стартувати (no Redis → no Sidekiq)
- **Ризик:** Твердження "система децентралізована" технічно некоректне — data layer залишається GCP (Web2)
- **Варіанти:**
  1. Tailscale/WireGuard VPN tunnel sidecar
  2. Cloud SQL Auth Proxy sidecar (Redis unsolved)
  3. Public IP + SSL + external Redis Cloud/Upstash
- **Статус:**
  - [ ] Обрати рішення
  - [ ] Реалізувати
  - [ ] Тест connectivity
- **Блокує:** Real Akash deployment

#### INF.2 — Docker image registry для Akash providers
- **Джерело:** `06_02` BLOCKER-4
- **Опис:** SDL reference `europe-west1-docker.pkg.dev/.../silken_net:latest`. Akash providers без GCP credentials → pull fails "unauthorized"
- **Статус:**
  - [ ] Mirror image до Docker Hub або GHCR (public або з token)
  - [ ] Оновити SDL image reference
  - [ ] CI workflow для автоматичного mirror

#### INF.3 — HTTPS у Akash SDL
- **Джерело:** `06_02` BLOCKER-5
- **Опис:** SDL відкриває лише HTTP (port 80) та CoAP UDP (5683). Port 443 відсутній. Browsers block WebSocket from HTTPS → HTTP
- **Статус:**
  - [ ] Додати port 443 до SDL
  - [ ] Налаштувати TLS (Akash ingress `*.ingress.akash.pub` або Cloudflare)

#### INF.4 — Akash no official Terraform provider
- **Джерело:** `06_02` BLOCKER-7
- **Опис:** На відміну від GCP, Akash не має Terraform provider. Поточне рішення: `null_resource` + `local-exec`. `terraform plan` не показує Akash ресурси, state у файлі `akash-dseq.txt`
- **Статус:**
  - [ ] Прийняти як architectural limitation
  - [ ] Задокументувати workaround в ops runbook

#### INF.5 — Kamal 2.11.0 proxy reboot
- **Джерело:** `06_01`
- **Опис:** Kamal 2.11.0 потребує `kamal-proxy >= v0.9.2`. Перший deploy з 2.11.0 вимагає `kamal proxy reboot` (~1-3 sec downtime). CI workflows вже включають цей крок
- **Статус:**
  - [x] CI workflow оновлено
  - [ ] Задокументувати в ops runbook для першого deploy

#### INF.6 — Conntrack table sysctl tuning
- **Джерело:** `06_01` Risk-1
- **Статус:** ✅ Виправлено. `nf_conntrack_max=2000000` та `nf_conntrack_udp_timeout=30s` у Terraform startup-script

---

## 🏛️ Архітектурні пропозиції (довгострокові)

#### ARCH.1 — Fractal topology: L2 Sergeant nodes
- **Джерело:** `00_01`
- **Опис:** Поточна архітектура (flat LoRa mesh) масштабується до тисяч вузлів. Для мільйонів потрібен L2 Sergeant рівень з H-LDSE hierarchical routing, geohashing, spatial multiplexing
- **Статус:** Архітектурний proposal, post-TRL 7

#### ARCH.2 — Ingress Proxy (Rust/Go) + Kafka
- **Джерело:** `00_01`, `06_01`
- **Опис:** Для >1M packets/hour: CoAP → Ingress Proxy (stateless) → Kafka → Rails consumers. Read-only replicas для analytics
- **Поточний стан:** `lib/daemons/coap_listener.rb` (Ruby) достатній для ~10k nodes
- **Статус:** Series D milestone

#### ARCH.3 — Redis DB isolation strategy
- **Джерело:** `00_01`
- **Опис:** DB 0 для Sidekiq, DB 1 для Kredis (Web3 nonce management). Запобігає eviction критичних Web3 nonce locks при overflow telemetry queue
- **Ризик без цього:** EVM nonce collisions → double-spend vulnerabilities
- **Статус:**
  - [ ] Верифікувати поточну Redis конфігурацію
  - [ ] Додати `database:` parameter у `config/cable.yml` та Sidekiq config

#### ARCH.4 — Governance DAO (SFC voting)
- **Джерело:** `05_03`
- **Опис:** Protocol constants (SIGMA, RHO, BETA, SLASH_THRESHOLD, POINTS_PER_SCC) зашиті в Rails services та firmware. Зміна = full deploy + перепрошивка. DAO через SFC-токен (ERC20Votes + ERC20Permit вже є)
- **Статус:** Post-TRL 6, не блокує прототип

#### ARCH.5 — Cross-Registry Export (Verra, Gold Standard, UNFCCC)
- **Джерело:** `04_02`
- **Опис:** `CrossRegistryExportService`, `Verra::ApiClient`, `GoldStandard::ApiClient`. MRV Report structure defined
- **Статус:** Post-TRL 7, critical для institutional sales

#### ARCH.6 — Federated Learning auto-retraining
- **Джерело:** `04_02`
- **Опис:** Auto-retraining ML loop для `silken_forest.marshal`. Monthly cycle з A/B testing, rollback on >5% false positives
- **Статус:** Post-TRL 7

---

## 🔍 Невідповідності код ↔ документація (codebase audit)

> Знайдені при порівнянні коду з документацією. НЕ виправляємо — лише документуємо.

#### DIFF.1 — `Wallet#lock_and_mint!` threshold documentation misleading
- **Документація:** "10,000 growth_points = 1 SCC" як fixed threshold
- **Код:** `app/models/wallet.rb:99-120` — threshold є **параметром методу**, не hardcoded константою. Значення 10,000 приходить від caller (`TokenomicsEvaluatorWorker`)
- **Дія:** Уточнити в документації що threshold = runtime parameter

#### DIFF.2 — `carbon_sequestration_coefficient` NOT IMPLEMENTED
- **Документація:** Згадується як фактор у `Wallet#credit!`
- **Код:** Не знайдено ні в `wallet.rb`, ні в жодному сервісі
- **Дія:** Або реалізувати, або видалити з документації

#### DIFF.3 — Divergence 30% threshold location unclear
- **Документація:** "Divergence > 30% → fraud flag" для Lorenz Z
- **Код:** `BlockchainMintingService::POISONED_RATIO_THRESHOLD = 0.3` — це про batch poisoned records, НЕ про Z divergence
- **Дія:** Знайти або реалізувати actual Z divergence check у `TelemetryUnpackerService`

#### DIFF.4 — `vibration_detected` race condition undocumented
- **Код:** `firmware/soldier/main.c:70,320-337` — subtle window між flag check та IRQ disable. Mitigated, але не задокументований
- **Дія:** Задокументувати pattern у `03_01` або `03_03`

#### DIFF.5 — Sentry gem versions not pinned
- **Код:** `Gemfile:42-44` — `gem "sentry-rails"`, `gem "sentry-ruby"`, `gem "sentry-sidekiq"` без версій
- **Документація:** `06_03` каже "sentry-ruby 6.5.0"
- **Дія:** Запінити версії у Gemfile для reproducible builds

#### DIFF.6 — Queen AES key line numbers mismatch
- **Документація (CLAUDE.md, 03_01, 03_02, 05_02):** "firmware/queen/main.c:65-66"
- **Код:** Actual position `firmware/queen/main.c:81-82`
- **Дія:**
  - [ ] Оновити line references у документації (03_01, 03_02, 05_02)
  - [ ] Оновити CLAUDE.md окремо (критичний SSOT для AI assistants)

#### DIFF.7 — SNR parameter unused in Queen CIFO eviction
- **Джерело:** `03_02`, `03_03` (NOTE)
- **Код:** `OnRxDone()` отримує SNR але ігнорує. CIFO eviction використовує лише RSSI
- **Дія:** Low priority optimization — SNR+RSSI покращить eviction decisions

---

## 📋 Юридичні / Бізнес блокери

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
| E.2 | Oracle private key має MINTER + SLASHER roles (single point of failure) | `07_01` | [x] Ролі розділено: `ORACLE_MINTER_PRIVATE_KEY` / `ORACLE_SLASHER_PRIVATE_KEY` з fallback на `ORACLE_PRIVATE_KEY` |
| E.3 | Breadboard video відсутнє (потрібне для грантів) | `07_03` | [ ] Зняти відео |
| E.4 | Helium Network fallback — concept є, реалізації немає | `02_05` | [ ] Дизайн + реалізація |
| E.5 | CoAP listener — Ruby, масштабується до ~10k вузлів | `06_01` | [ ] Series D: Rust/Go proxy |
| E.6 | `gateway_id` FK exists but not used by Rails | `04_01` | [ ] Аудит + cleanup |
| E.7 | dClimate mock mode — прийнятно для TRL 8, потрібна реальна інтеграція для Production | `05_01` | [ ] Real API integration (S3.2 частково) |
| E.8 | SNR parameter unused у Queen CIFO eviction (лише RSSI) | `03_02`, `03_03` | [ ] Low priority optimization |
| E.9 | DMA SPI optimization — зменшення енергоспоживання (Vector 1 — Ярмілко) | `08_02` | [ ] Потребує R&D partnership |
| E.10 | Kalman/EMA filtering для delta_t noise suppression (±8% → ±1.2%) | `08_02` | [ ] Потребує R&D partnership |
| E.11 | CE/FCC/EMC/IP68 certification roadmap не розпочато | `08_02` | [ ] Потребує Косенук (RF) |
| E.12 | Boolean minimization TX decision conditions (Karnaugh/Quine-McCluskey) | `08_02` | [ ] Потребує Любченко |
| E.13 | Petri Net model of Rails monolith — deadlock-free verification at 10k concurrent IoT | `08_02` | [ ] Потребує Супруненко |
| E.14 | Multi-source satellite + anchor data fusion (Sentinel-2 NDVI) | `08_02` | [ ] Потребує Любченко + Бушин |
| E.15 | Reed-Solomon FEC або Hamming для LoRa error correction | `08_02` | [ ] Потребує Косенук |
| E.16 | `oracle_dispatch_latency_seconds` per-network detail metric missing | `06_03` | [ ] Low priority |
| E.17 | `lorenz_computation_duration_seconds` metric missing | `06_03` | [ ] Low priority |
| E.18 | 10 запланованих Q1 публікацій — blocked by lab data and author collective | `08_03` | [ ] Blocked by UNI.1-UNI.3 |
| E.19 | 8 магістерських — blocked by TRL 4 advancement | `08_03` | [ ] Post-TRL 4 |
| E.20 | Forester Guild (Proof-of-Physical-Work) — planned post-TRL 6 module | `04_02` | [ ] Post-TRL 6 |
| E.21 | `Scaffold files в app/javascript/controllers/` — видалити перед production | `04_04` | [ ] Cleanup |
| E.22 | Leaflet map Turbo Drive cache fix — verified working (disconnect() cleanup) | `04_04` | [x] Реалізовано |
| E.23 | Пропущений тиждень Ethereum anchoring не буде перезаписано (cron creates new state_root) | `05_04` | [ ] Задокументувати в ops runbook |
| E.24 | `PROVISIONING_MASTER_KEY` not set → AES key in response (TRL4 lab mode only) | `04_03` | [ ] Забезпечити що в production ENV встановлений |
| E.25 | Euler method DT=0.01 — acceptable for PoG but not scientific simulations | `03_04` | [x] Задокументовано як design tradeoff |
| E.26 | `health_trend` field для TelemetryLog — predictive degradation: якщо шум Pogo Pin зростає, auto-tune Kalman params via Downlink | Legacy notes | [ ] Post-TRL 6, потребує E.10 (Kalman) |
| E.27 | Chaos Engineering: Chaos Mesh для Akash або kill-scripts для Kamal web nodes — верифікація RpcConnectionPool + Sidekiq retries resilience | Legacy notes | [ ] Post-TRL 7, production hardening |
| E.28 | Kamal deploy hooks idempotency audit: `kamal deploy` повторний запуск після перерваного деплою не повинен дублювати DB migrations або blockchain TX | Legacy notes, `06_01` | [ ] Верифікувати `.kamal/hooks/` + migration idempotency |
| E.29 | Альтернативні EBFC медіатори (ferrocene, methylene blue) для лабораторного порівняння з поточним осмієвим MET | Legacy notes, `01_03` | [ ] Додано в `01_03` як R&D alternatives |
| E.30 | InsightGeneratorService: кліматичні базлайни per region, не лише per cluster — для точнішого AI Fraud Guard при планетарному масштабуванні | Legacy notes, `04_02` | [ ] Post-TRL 7 (поточний cluster-level baseline достатній для TRL 6-8) |
| E.31 | TinyML OTA: `.tflite` формат (INT8 quantization) + Python ML microservice для Federated Learning. Ruby `.marshal` неприпустимий для STM32 | Legacy notes, `03_03` | [ ] Post-TRL 8 (залежить від BLOCKER-1/2 в `03_03`) |
| E.32 | Smart Contract Audit: Slither/Mythril в CI + Hacken/Hashlock pre-mainnet + CertiK Skynet post-mainnet | Legacy notes, `05_03` | [ ] Pre-Mainnet (Slither/Mythril можна додати зараз) |
| E.33 | AlertNotificationWorker rate limits: FCM multicast (500 tokens/req), Twilio Notify (10k/req) замість окремих SingleNotificationWorker HTTP-запитів | Legacy notes, `04_02` | [ ] Post-TRL 8 (поточні стаби не мають rate limit проблем) |
| E.34 | DclimateVerificationWorker: при `severity: :critical` + `:obscured_by_clouds` → миттєвий fallback на ForestBountyService (drone/ranger Proof-of-Physical-Work) | Legacy notes, `04_02` | [ ] Post-TRL 6 (залежить від E.20 Forester Guild) |
| E.35 | Flash Loan defense в GovernorContract.sol: `getPastVotes` snapshot voting + Voting Delay 7200 блоків + 4% quorum + 48h Timelock | Legacy notes, `05_03` | [ ] Разом з Governor deployment (Post-TRL 6) |
| E.36 | PostGIS Cluster.geo_boundary: заміна тригера `sync_cluster_geo_boundary()` на PostgreSQL Generated Column (GENERATED ALWAYS AS) | Legacy notes, `04_01` | [ ] Post-TRL 8 (оптимізація, тригер працює коректно) |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates + автоматична компресія. Відхилено для TRL 6-8 (нативний RANGE partitioning достатній) | Legacy notes, `04_01` | [ ] Тільки при >100M рядків/місяць |

---

## 📊 TRL Матриця по модулях

| Модуль | Поточний TRL | Цільовий TRL | Головний блокер | Трекер |
|--------|-------------|-------------|-----------------|--------|
| 00 System Architecture | 4 | 9 | Module 01 chemistry | ARCH.1-ARCH.6 |
| 01 Materials & EBFC | 3 | 6 | Lab tests (ЧНУ) | HW.1-HW.6 |
| 02 Hardware & BOM | 4 | 6 | BQ25570, PCB layout, Pogo pins | HW.7-HW.19 |
| 03 Firmware | 6 | 8 | AES key, TinyML, AT blocking, Time Sync | FW.1-FW.21 |
| 04 Backend Rails | 8 | 9 | Prometheus Server, тести guard clauses | S1-S3, DIFF.1-DIFF.7 |
| 05 Web3 Pipeline | 8-9 | 9 | PuroEarth real API, SFC contract address | S3.3, S3.5 |
| 06 DevOps | 6 | 9 | Prometheus, Akash isolation | S2.1-S2.3, S4, INF.1-INF.6 |
| 07 Business | 5 | 8 | CO₂ methodology, MSA, ToS | BIZ.1-BIZ.5 |
| 08 University R&D | 2 | 6 | ЧНУ partnership, lab data | UNI.1-UNI.3 |
| 09 Project Management | 7 | 9 | TRL auto-advancement, SSOT guard | — |
| 10 Security | 5 | 9 | Multisig, RDP, Factory Flashing | SEC.1-SEC.4 |

---

## 📝 Журнал оновлень

| Дата | Сесія | Зміни |
|------|-------|-------|
| 2026-04-18 | Аудит документації | Створено документ. Аудит 35 docs. Відмічені вже реалізовані пункти. |
| 2026-04-18 | Сесія 2 — Sprint 1-3 | ✅ S1.3/S1.6/S1.7/S1.8/S2.4/S2.5/S3.6 виконано та задокументовано. |
| 2026-04-18 | Сесія 3 — Firmware + Subgraph | ✅ FW.12/FW.13/FW.14/S3.1/S3.5 виконано. 137 firmware tests pass. |
| 2026-04-18 | Оновлення документації | Виконані задачі задокументовано в 03_01/03_04/04_04/05_03/06_01/06_03. Трекер очищено від завершених пунктів. |
| 2026-04-18 | Сесія 5 — E.2 + S3.4 | ✅ E.2 Oracle Role Separation (MINTER/SLASHER окремі ключі з fallback). ✅ S3.4 M2M Token Refresh endpoint + тести. |
| 2026-04-18 | Повний аудит docs + codebase | Повторний аудит ВСІХ 35 документів (повне читання). Аудит кодбейзу (firmware, backend, infra). Додано: FW.15-FW.19, HW.11-HW.18, SEC.1-SEC.4, INF.1-INF.6, ARCH.1-ARCH.6, DIFF.1-DIFF.7, E.7-E.25. Оновлено TRL матрицю та зведену статистику. |
| 2026-04-18 | Legacy notes integration | Аналіз 10 старих нотаток. Додано: FW.20 (Time Sync), FW.21 (Edge aggregation), E.26-E.30. Оновлено HW.6 (thermal spec + hydrophobic gradient). Оновлено `01_04` (CODIT spec temperature + hydrophobic gradient). Оновлено `01_03` (альтернативні медіатори). Notes 3/6/9 — вже реалізовано або неактуальні. |
| 2026-04-18 | Security notes integration | Аналіз 4 security/firmware нотаток. Оновлено FW.2 (AES-CCM 24-байтний пакет з Frame Counter + MIC), FW.16 (RCC CRYP_FORCE_RESET recovery), FW.17 (Hash Ratchet KDF замість key-over-air). Оновлено BLOCKER-2/3/5/6 у `03_05`. Note 4 (HRNG ADC noise) — вже виправлено краще (djb2 HW UID). |
| 2026-04-18 | Hardware notes integration | Аналіз нотаток щодо ADS1220 / TPS22860 / LIC Eaton HS1016. Додано §4 "Розглянуті альтернативи" в `02_04` (LIC vs EDLC, концепт VOC-діагностики). Додано §7 "Розглянуті альтернативні компоненти" в `02_01` (ADS1220, TPS22860). Всі три компоненти відхилено для TRL 6 з документованим обґрунтуванням. |
| 2026-04-18 | Architecture notes integration | Аналіз 8 архітектурних нотаток. Додано: E.31 (TinyML tflite format), E.32 (Smart Contract Audit roadmap), E.33 (FCM/Twilio rate limits), E.34 (dClimate fallback oracle), E.35 (Flash Loan defense), E.36 (PostGIS Generated Column), E.37 (TimescaleDB evaluation). Оновлено `03_03` (OTA model format + Federated Learning pipeline), `05_03` (Flash Loan attack vector + Audit Roadmap + Bonding Curves), `05_04` (Merkle Tree + EigenLayer AVS), `04_02` (rate limits + fallback oracle), `04_01` (Generated Column + TimescaleDB). |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
> 3. Заповнити поля **Сесія** та **Коміт**
> 4. Додати запис у таблицю **Журнал оновлень**
> 5. Оновити **Зведену статистику** вгорі (якщо блокер закрито)
> 6. Оновити поле **Останнє оновлення** у шапці документа
