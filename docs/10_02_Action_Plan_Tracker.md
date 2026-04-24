# 10_02 — Action Plan Tracker (Залишок робіт)

> **Створено:** 2026-04-18 (Аудит 35 документів `00_00` → `09_03`)
> **Оновлено:** 2026-04-23 (Повторний аудит: cross-ref docs↔codebase, +33 DOC невідповідності, +11 SW, +3 SEC, +7 ARCH, +14 E.xx)
> **Принцип:** Цей документ містить ТІЛЬКИ незавершені задачі. Виконана робота задокументована у відповідних docs (`00_00` → `10_01`).

---

## 🛣️ Software / Backend / DevOps

> **Складність:** XS < 1 год · S = 1–4 год · M = 4–8 год · L = 1–3 дні

#### S1.1 — GitHub Secrets заповнення
- **P0** | `06_01` | **Складність: XS** | **🔧 Операційна** — ручне заповнення в GitHub UI, без коду
- **Опис:** 12 критичних секретів не встановлені: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `DATABASE_URL`, `SSH_PRIVATE_KEY`, тощо. Блокує весь CI/CD pipeline.
- [ ] Створити список необхідних секретів (checklist)
- [ ] Заповнити GitHub repository secrets
- [ ] Верифікувати CI pipeline проходить

#### S1.5 — Kamal IP placeholders
- **P2** | `06_01` | **Складність: XS** | **🔧 Операційна** — підстановка IP після `terraform apply`
- **Опис:** `192.168.0.1` та `<CANOPY_SERVER_IP>` — плейсхолдери в Kamal config
- [ ] Підставити реальні IP після `terraform apply`
- [ ] Верифікувати Kamal deploy з реальними IP

#### S2.1 — Верифікація метрик після deploy
- **P0** | `06_03` | **Складність: XS** | **🔧 Операційна** — верифікація після першого Akash deploy, без коду
- **Опис:** `/metrics` endpoint працює (10+ метрик), скрейпиться Grafana Alloy sidecar → Grafana Cloud. Інфраструктура налаштована (prometheus.rb, middleware, Alloy sidecar, Terraform vars). Потрібна верифікація після першого Akash deploy
- [ ] Верифікувати що метрики збираються (після першого Akash deploy)

#### S2.2 — Grafana Cloud dashboards
- **P0** | `06_03` | **Складність: S** | **🔧 Операційна** — налаштування в Grafana Cloud UI, без коду
- **Опис:** Grafana Cloud SaaS — метрики доступні, дашборди створюються в UI
- [ ] Dashboard: Sidekiq queues (9 черг, size + latency)
- [ ] Dashboard: Web3 RPC errors by network
- [ ] Dashboard: Telemetry ingest rate + fraud detection
- [ ] Dashboard: Treasury / Oracle balance monitoring
- [ ] Dashboard: Database connection pool stats

#### S2.3 — Grafana Cloud alerting rules
- **P0** | `06_03` | **Складність: S** | **🔧 Операційна** — налаштування в Grafana Cloud UI, без коду
- **Опис:** Grafana Cloud Alerting замінює потребу в self-hosted Alertmanager
- [ ] Alert: `web3_critical` queue depth > 100
- [ ] Alert: `silkennet_telemetry_fraud_detected_total` rate > 0
- [ ] Alert: `silkennet_rpc_errors_total` rate > 10/min
- [ ] Alert: Oracle balance < threshold
- [ ] Alert: Sidekiq queue latency > 5 min
- [ ] Налаштувати notification channel (Slack / Email / PagerDuty)

#### S3.2 — dClimate Real API verification
- **P1** | `05_01` | **Складність: S** | **🔧 Операційна** - отримати та встановити API key, сервіс реалізований, потрібна staging верифікація
- **Опис:** `Dclimate::VerificationService` реалізований з реальним API (NASA FIRMS через dClimate). Fire detection (FRP ≥ 10 MW, confidence ≥ 50%), cloud obscuration fallback, metadata extraction — все працює. Потрібна верифікація з реальним ключем
- [ ] Верифікувати з реальним API ключем в staging (отримати та встановити API key)
- [ ] End-to-end тест з `DclimateVerificationWorker`

#### S3.5 — Subgraph contract address
- **P2** | `05_03` | **Складність: XS** | **🔧 Операційна** — замінити placeholder після deploy контракту
- **Опис:** SFC events (ForestMinted, GovernanceSlashed) додано до subgraph. Задокументовано в `05_03` розділ Subgraph. Але contract address — placeholder. Блокує deploy subgraph.
- [ ] ⚠️ Замінити placeholder `0x0000...0000` на реальну адресу SFC контракту у `subgraph.yaml`

#### INF.3 — TLS termination
- **P2** | `06_02` BLOCKER-5 | **Складність: S** | **🔧 Операційна** — конфігурація Cloudflare або Akash ingress, без коду в Rails
- **Опис:** SDL відкриває HTTP (port 80), CoAP UDP (5683), та port 443 (додано Сесія 6). Але TLS termination не налаштовано. Browsers block WebSocket from HTTPS → HTTP
- [ ] Налаштувати TLS (Akash ingress `*.ingress.akash.pub` або Cloudflare)

#### S4.3 — Akash SDL secrets
- **P3** | `06_02` | **Складність: XS** | **🔧 Операційна** — заповнити 4 змінні у `deploy.yaml`
- **Опис:** `REQUIRED_SECRET_NOT_SET` для 4 критичних змінних
- [ ] Заповнити в `deploy/akash/deploy.yaml`
- [ ] Верифікувати startup

#### S5.2 — RELEASE_VERSION ENV для Sentry
- **P2** | `06_03` | **Складність: XS** | **🔧 Операційна**
- **Опис:** `RELEASE_VERSION` ENV не встановлено — Sentry release tracking не працює. Потрібно додати у Kamal/Akash deploy config
- **Статус:** ✅ Виконано. `RELEASE_VERSION` додано у: `deploy.yml` (Canopy, git SHA), `deploy-production.yml` (Production, release tag або git SHA), `config/deploy.yml` (Kamal clear env), `deploy/akash/deploy.yaml` (web + job services)
- [x] Додати `RELEASE_VERSION` у deploy pipeline (git SHA або tag)
- [ ] Верифікувати Sentry release tracking

#### S5.6 — GCS bucket для Terraform state (chicken-and-egg)
- **P3** | `06_02` BLOCKER-6 | **Складність: XS** | **🔧 Операційна**
- **Опис:** GCS bucket для remote Terraform state має бути створений вручну перед `terraform init`. Документація є, але checklist відсутній
- [ ] Створити GCS bucket вручну (`gsutil mb`)
- [ ] Верифікувати `terraform init` проходить

#### S6.1 — Redis SPOF для M2M автентифікації
- **P1** | `04_03` | **Складність: M** | **Код**
- **Опис:** Redis = single point of failure для Gateway M2M auth. Redis down → всі шлюзи заблоковані (503). Відсутній fallback
- **Варіанти fallback:** (a) DB-backed nonce validation з TTL index (performance overhead, але survives restarts), (b) Upstash Redis Cluster (managed HA, рекомендовано для production), (c) Memcached cluster (не зберігає стан між restarts). **Рекомендація:** Upstash Redis вже використовується — переконатись що включений multi-zone replication
- [ ] Верифікувати Upstash multi-zone replication у production
- [ ] Додати graceful degradation: при Redis недоступності → DB-based nonce lookup з TTL
- [ ] Тести: Redis down scenario → gateways залишаються active

#### S6.2 — Chainlink Functions Router v1 ENV змінні
- **P1** | `04_02` | **Складність: XS** | **🔧 Операційна**
- **Опис:** Chainlink ABI оновлено до Functions Router v1. Потрібні 3 нові ENV: `CHAINLINK_DATA_VERSION`, `CHAINLINK_CALLBACK_GAS_LIMIT`, `CHAINLINK_DON_ID`
- **Статус:** ✅ Виконано. Всі 3 ENVs додані до `.env.example`, `config/deploy.yml` (Kamal), `deploy/akash/deploy.yaml`, `.kamal/secrets`, та задокументовані в `06_01`
- [x] Додати до `.env.example`
- [x] Додати до deploy configs (Kamal, Akash SDL)
- [x] Задокументувати в `06_01`

#### S6.3 — deploy-production.yml відсутній
- **P1** | `06_01` | **Складність: S** | **Код**
- **Опис:** Workflow для production deploy згадується в документації але не існує. Production deploy неможливий через CI
- [ ] Створити `.github/workflows/deploy-production.yml`
- [ ] Інтегрувати з GitHub Releases (`v*.*.*`)

#### S6.4 — Circuit breaker тільки на IoTeX/Chainlink
- **P2** | `05_01` | **Складність: M** | **Код**
- **Опис:** Circuit breaker реалізований лише для IoTeX та Chainlink. Відсутній на 10 інших Web3 мережах (Streamr, Filecoin, peaq, Polygon, Solana, Celo, KlimaDAO, Hadron, The Graph, Ethereum L1)
- [ ] Додати circuit breaker для Polygon/Solana/Celo (критичні для мінтингу)
- [ ] Оцінити потребу для інших мереж

#### S6.5 — 30s Kredis lock для мінтингу може бути замалим
- **P2** | `05_03` | **Складність: S** | **Код**
- **Опис:** Якщо мінтинг повільний (RPC congestion), 30s Kredis lock може expire → double-mint risk
- [ ] Збільшити lock timeout або використати pessimistic DB lock
- [ ] Тест: slow RPC scenario

#### S6.6 — Missed anchor week не backfilled
- **P2** | `05_04` | **Складність: S** | **Код**
- **Опис:** Якщо weekly `EthereumAnchorWorker` пропускає тиждень (downtime, gas), state root **назавжди втрачається**
- [ ] Додати backfill mechanism або alerting
- [ ] Задокументувати process для manual recovery

#### S6.7 — Double-anchoring race condition
- **P2** | `05_04` | **Складність: S** | **Код**
- **Опис:** Timeout → retry → два state roots для одного тижня на L1
- [ ] Додати idempotency guard (перевірка існуючого anchor перед TX)

#### S6.8 — Weekend telemetry blackouts
- **P3** | `04_02` | **Складність: XS** | **Код**
- **Опис:** Немає GLOBAL_BLACKOUT на вихідних. Телеметрія у вихідні мовчки ігнорується
- [ ] Задокументувати поведінку або додати weekend handling


#### S6.10 — MaintenanceRecord — лише лог
- **P3** | `04_02` | **Складність: L** | **Архітектурна**
- **Опис:** MaintenanceRecord — лише запис логу. Немає: призначення задач, оплати, верифікації. Потребує Forester Guild (E.20)
- [ ] Архітектурний дизайн task assignment
- [ ] Зв'язати з Forester Guild PoPhW (E.20)

#### S6.11 — No disaster recovery / chain outage strategy
- **P2** | `05_01` | **Складність: M** | **Архітектурна**
- **Опис:** Немає стратегії disaster recovery при виході з ладу однієї з 12 Web3 мереж
- [ ] Визначити critical path chains (Polygon, Chainlink, IoTeX)
- [ ] Дизайн graceful degradation для кожної мережі

---

## 🔧 Firmware

### 🔴 P0 — Критичні

#### FW.1 — Hardcoded AES-256 Key
- `03_01`, `03_02`, `03_05`, `05_02` | `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:81-82`
- **Опис:** Один і той самий ключ на ВСІХ вузлах мережі. Злам одного пристрою = компрометація всієї мережі
- **Рішення:** Per-device provisioning через HKDF, Factory Flashing pipeline
- [ ] Дизайн HKDF key derivation protocol
- [ ] Backend: provisioning endpoint (POST `/api/v1/provisioning/register` вже існує)
- [ ] Firmware: змінити key storage з hardcoded → Flash-based
- [ ] Firmware: RDP Level 2 activation як final step
- [ ] End-to-end тест provisioning flow

#### FW.2 — AES-256-ECB без MAC/MIC
- `03_05` | `firmware/soldier/main.c:747`, `firmware/queen/main.c:781`
- **Опис:** Детерміністичний шифротекст, replay/bit-flip attacks можливі. Немає автентифікації пакетів
- **Рішення (рекомендоване):** **AES-256-CCM** (апаратно підтримується STM32WLE5JC) з новим 24-байтним пакетом: `[DID:4][SensorData:8][FrameCounter:4][MIC:4][Reserved:4]`. Frame Counter у RTC Backup Domain як Nonce. MIC апаратно генерується CCM. Вирішує BLOCKER-2 та BLOCKER-3 одночасно
- **Альтернативи:** AES-256-GCM, AES-256-CTR + HMAC-SHA256 MIC (4-byte suffix)
- [ ] Верифікувати `CRYP_AES_CCM` підтримку на цільовій ревізії STM32WLE5JC
- [ ] Дизайн 24-байтного пакету (8 байт sensor data vs поточних 16 — оптимізувати поля)
- [ ] Firmware Soldier: CCM encrypt + Frame Counter інкремент + MIC append
- [ ] Firmware Queen: CCM decrypt + Frame Counter validation (anti-replay)
- [ ] Backend: оновити `TelemetryUnpackerService` для 24-байтного формату
- [ ] LoRa airtime budget verification (24B vs 16B при SF10/DR2)
- [ ] Тести

#### FW.3 — Queen AT Command Blocking (~25 сек)
- `03_01`, `03_02`
- **Опис:** Queen "сліпа" до LoRa пакетів під час CoAP flush. Single-packet buffer — пакети втрачаються
- **Рішення:** UART DMA interrupt-driven + ring buffer
- [ ] Переписати `Flush_Cache_To_Rails()` на UART DMA
- [ ] Замінити single-packet buffer на ring buffer
- [ ] Додати CoAP response parsing (замість blind HAL_Delay)
- [ ] Тести

#### FW.4 — TinyML `Run_Inference()` закоментований
- `03_03` | `main.c:355`, `silken_net_audio_model.h` відсутній
- **Опис:** `Run_Inference()` закоментована; model header відсутній
- **Блокує:** Acoustic detection (chainsaw, cavitation, wind)
- [ ] Тренування моделі (4 класи: silence/wind/cavitation/chainsaw)
- [ ] Генерація `silken_net_audio_model.h`
- [ ] DSP preprocessing (FFT/MFCC або вбудований у модель)
- [ ] Verify Tensor Arena size (< 54 KB)
- [ ] Розкоментувати `Run_Inference()`
- [ ] Host-based тести

### 🟠 P1 — Важливі

#### FW.5 — Lorenz Attractor: delta_t/vcap не передаються
- `03_04`, `05_02`
- **Опис:** Spec: `calculate_state(delta_t, vcap)`, реалізація: `calculate_state(chaos_seed, temp, acoustic)`. Аналіз показав: `chaos_seed` (HRNG) вносить значний випадковий компонент у growth_points — при 250 ітераціях Ейлера Z суттєво залежить від початкових умов. `delta_t` та `vcap` — прямі фізичні індикатори метаболізму дерева, що може бути більш обґрунтованим для "Proof of Growth" токеноміки
- [ ] Математичний аналіз: порівняти variance Z від chaos_seed vs delta_t/vcap після 250 ітерацій
- [ ] Архітектурне рішення: замінити chaos_seed на delta_t (Варіант A), додати delta_t/vcap як додаткові пертурбації (Варіант B), або зберегти + EMA фільтр (Варіант C)
- [ ] Задокументувати рішення в `03_04` з обґрунтуванням впливу на токеноміку
- [ ] Реалізувати (якщо зміна)

#### FW.7 — Float vs BigDecimal divergence (TRL 6 mitigation)
- `05_02`
- **Опис:** firmware `8.0/3.0 = 2.6666666666666665` vs backend BigDecimal `2.666666666666666667`
- **Статус:** ✅ Виправлено (TRL 6). Backend `SilkenNet::Attractor` переведено з BigDecimal на Float (IEEE 754 double) — ідентично firmware mruby. Dual Computation Integrity тепер дає однакові Z-значення на одній архітектурі
- ⚠️ *Увага: IEEE 754 Float математика все одно буде давати незначний drift між ARM (STM32 Soldier) та x86 (GCP/Akash Backend) архітектурами. Категоричний tolerance band (homeostasis/stress/anomaly) компенсує це для TRL 6, але строгий побітовий consensus потребує `ARCH.18`.*
- [x] Backend: замінити BigDecimal на Float в `SilkenNet::Attractor` (calculate_z, generate_trajectory, initialize_state)
- [x] Оновити тести (BigDecimal → Float assertions)
- [x] Задокументувати в `03_04` (BLOCKER-4 закрито)
- [ ] Верифікувати `MRB_USE_FLOAT` при першому lab-тестуванні (залишковий ризик)

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- `05_02`
- **Опис:** firmware: global 2.0/45.0 vs backend: per-species через `TreeFamily`
- **Рішення:** OTA sync species-specific thresholds
- [ ] Додати thresholds до OTA config payload
- [ ] Firmware: зберігати thresholds у Flash/RTC
- [ ] Backend: включити thresholds у OTA bytecode

#### FW.9 — CoAP retry logic
- `03_02`
- **Опис:** Після AT+CCOAPSEND: `HAL_Delay(2000)` без парсингу відповіді. ACK miss → весь кеш втрачається
- [ ] Парсинг UART RX для `OK`/`ERROR` відповіді модему
- [ ] Double-buffering або persistent buffer для retry
- [ ] Configurable retry count

### 🟢 P2 — Низькопріоритетні

#### FW.17 — Key rotation mechanism (Hash Ratchet KDF)
- `03_05` BLOCKER-5 | Після FW.1 (per-device provisioning) — future cycle
- **Опис:** Поточна архітектура: статичний ключ при Factory Flashing. Немає механізму зміни ключа без перепрошивки всіх вузлів. Порушує GDPR/ISO 27001/NIST SP 800-57
- **Рішення (рекомендоване — Hash Ratchet KDF):** Синхронна деривація нового ключа на обох кінцях без передачі ключа по мережі. Backend надсилає `CMD:ROTATE_KEY:<UUID>` → Queen + Soldier проганяють `K_current` через AES-KDF → `K_next`. Забезпечує Perfect Forward Secrecy (PFS)
- [ ] Дизайн Hash Ratchet протоколу (AES-based KDF on STM32 hardware)
- [ ] CMD:ROTATE_KEY CoAP command + OTA relay через Queen
- [ ] Cluster-wide activation confirmation (ACK від усіх вузлів)
- [ ] Зберігання `K_current` та `rotation_counter` у Flash/RTC Backup Domain
- [ ] Consider ECDH/Curve25519 key exchange при provisioning (альтернатива)

#### FW.18 — Hardcoded confidence threshold 0.80
- `03_03` BLOCKER-6
- **Опис:** `if (ml_confidence > 0.80)` hardcoded в Flash. Неможливо remote-tune для різних лісів/сезонів. Немає "warning" рівня (лише binary: alarm / no alarm)
- [ ] Зберегти threshold у RTC Backup Register (updateable via OTA)
- [ ] Дизайн dual-threshold: WARNING (0.60) → event counter; CRITICAL (0.85) → Emergency TX

#### FW.19 — Float32 vs Float64 mruby compile flags
- `03_04` BLOCKER-4
- **Опис:** mruby без `MRB_USE_FLOAT` використовує double (64-bit), з прапорцем — float (32-bit). Makefile не верифікований. Різниця ±5-10 units на Z-осі після 250 ітерацій може змінити bio_status (false slashing)
- **Статус:** 🟡 Частково вирішено. Tolerance band задокументовано як "by design" через категоричну перевірку в `check_z_divergence!`. Верифікація mruby compile flags — при першому lab-тестуванні
- [x] Задокументувати tolerance підхід (категоричний, не числовий) в `03_04` BLOCKER-4
- [ ] Верифікувати mruby compile flags (`MRB_USE_FLOAT` у Makefile або mrbconf.h) при lab-тестуванні

#### FW.20 — LoRa Time Sync (clock drift compensation)
- Legacy notes | P2 (не блокує TRL 6, критичний для TRL 7+)
- **Опис:** Дешеві кварцові резонатори / внутрішні осцилятори STM32 мають температурний дрейф. При -20°C та +40°C RTC годинник Soldier йде з різною швидкістю. За кілька місяців "час дерева" розсинхронізується з "часом бекенду" на хвилини або години. Впливає на: (1) `created_at` timestamp → partition pruning errors, (2) HMAC/nonce replay protection windows, (3) cron-like wakeup scheduling
- **Рішення:** Протокол Time Sync через Queen downlink. Queen має точний час через LTE/NTP. Періодично Queen надсилає OTA-корекцію часу. Аналог LoRaWAN MAC command `DeviceTimeReq`
- [ ] Firmware Queen: додати time correction у CoAP ACK або окремий downlink command
- [ ] Firmware Soldier: прийняти та застосувати RTC correction
- [ ] Backend: включити server UTC timestamp у downlink payload
- [ ] Тести: перевірити drift compensation при ΔT = ±60°C

#### FW.21 — Edge data aggregation (RAM-aware Soldier)
- Legacy notes + `08_02` (Kalman filter Vector 4) | P2 (потребує R&D partnership)
- **Опис:** Soldier MCU має обмежений RAM (~20 KB вільного). Поточна архітектура: кожен wakeup → один 21-байтний пакет → TX. Для майбутнього (Kalman filtering, TinyML context) потрібна локальна агрегація
- **Рішення:** Moving average / EMA прямо на MCU. Відправляти на Queen лише: (1) поточне значення, (2) дельту від попереднього EMA, (3) стиснуті "summary" пакети. Зменшує трафік LoRa та економить батарею
- [ ] Визначити які метрики потребують EMA (delta_t, vcap — кандидати)
- [ ] Реалізувати lightweight EMA на Soldier (O(1) memory, O(1) compute)
- [ ] Інтегрувати з Kalman filter design (E.10 — Косенук)
- [ ] Верифікувати RAM footprint залишається < 80% available

#### FW.22 — acoustic_events payload overflow (uint16 → uint8 truncation)
- `03_03` BLOCKER-7
- **Опис:** `acoustic_events` — тип `uint16_t` в firmware, але в 21-байтний пакет пишеться лише молодший байт (low byte). Якщо між TX циклами більше 255 подій — silent overflow, дані корумпуються. Backend отримує обрізане значення без можливості виявити overflow
- **Пріоритет:** P2 (рідкий сценарій при нормальній роботі, критичний при stress-тестуванні)
- **Статус:** ✅ Виконано (Сесія 18). Тип змінено на `uint8_t`, додано saturating increment `if (acoustic_events < 255) acoustic_events++`. Packing спрощено (ternary видалено). 8 unit tests.
- [x] Firmware: обмежити `acoustic_events` до `uint8_t` з saturating increment (cap at 255)
- [ ] АБО: виділити 2 байти в payload (потребує перепакування — пов'язано з FW.2 CCM transition)
- [x] Backend: додати warning якщо `acoustic_events == 255` (ймовірний overflow) — реалізовано в `TelemetryUnpackerService`

#### FW.23 — OTA firmware broadcast: ECB без автентифікації
- `03_05` | `firmware/queen/main.c`
- **Опис:** OTA bytecode chunks (`[0x99][index:2][total:2][bytecode:11]`) передаються через AES-256-ECB без MAC/signature. Зловмисник може підмінити firmware chunks → code injection на всіх Soldiers у радіусі Queen. Відсутня верифікація цілісності зібраного bytecode перед записом у Flash (`0x0803F000`)
- **Пріоритет:** P1 (критичний для security, але блокується FW.2 CCM transition)
- **Рішення:** (1) Підписати OTA image Ed25519 на backend, (2) Queen верифікує підпис перед relay, (3) Soldier верифікує перед Flash write. АБО: HMAC-SHA256 над повним image, transmitted як фінальний chunk
- [ ] Дизайн OTA authentication protocol
- [ ] Backend: підпис OTA image перед відправкою
- [ ] Firmware Queen: верифікація підпису/HMAC перед relay
- [ ] Firmware Soldier: верифікація перед Flash write (`MRUBY_CONTRACT_FLASH_ADDR`)
- [ ] Magic check `0x45544952 ("RITE")` + HMAC verification = dual gate

---

## 🧪 Hardware / Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

#### HW.1 — nTop model → DMLS factory
- **Джерело:** `01_01` | ✅ Ліцензія отримана
- [ ] Генерація TPMS gyroid geometry (65% porosity)
- [ ] STL/STEP файл → передати на DMLS завод (Київ/Дніпро)
- [ ] SEM criteria для приймання партії

#### HW.2 — Dual-scale roughness spec
- **Джерело:** `01_02`
- **Опис:** Sa 0.5-5 µm, Sv 50-500 nm НЕ передана на завод
- **Блокує:** Максимальний струм EBFC, TRL 5
- [ ] Підготувати factory spec з метриками
- [ ] Передати на завод
- [ ] Отримати SEM images ×500/×5,000/×50,000

#### HW.3 — Accelerated aging test (Arrhenius)
- **Джерело:** `01_02`
- **Опис:** 12-тижневий тест у synthetic xylem sap
- **Блокує:** Seed раунд, whitepaper, TRL 5→6
- [ ] Синтез штучного ксилемного соку (потрібен ботанік)
- [ ] Запуск 12-тижневого тесту
- [ ] ICP-MS аналіз: Ti < 0.1 µg/cm², V < 0.02 µg/cm²
- [ ] EIS degradation < 50%

#### HW.4 — Self-healing coating
- **Джерело:** `01_02`
- **Опис:** 8-HQ мікрокапсули не синтезовані
- **Блокує:** 20+ років longevity claims, TRL 6
- [ ] Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] Інтеграція в PEO electrolyte або layer-by-layer
- [ ] Тест: 10× вищий Rct

#### HW.5 — Enzyme lifespan
- **Джерело:** `01_03` + Legacy notes
- **Опис:** GOx/Laccase деградація у кислому ксилемному середовищі (pH 4.5-5.5). Глутаральдегід фіксує ферменти механічно, але НЕ захищає від кислотної деградації. GOx виробляє H₂O₂ (окислювальний стрес для дерева)
- **Gen 1.0 ціль:** 3-5 років (Chitosan + Nafion захист)
- **Gen 2.0 ціль:** 20-25 років (FAD-GDH + Laccase/nanozyme + ZIF інкапсуляція)
- [ ] Розробка protective polymer matrix
- [ ] Тест Chitosan-шару (pH-буферизація) — додано в `01_03`
- [ ] Тест Nafion-покриття (селективна мембрана) — додано в `01_03`
- [ ] Тест комбінації Chitosan + Nafion (пріоритетний варіант)
- [ ] Тест: 3-5 років функціонального ферменту (Gen 1.0)
- [ ] **Gen 2.0:** FAD-GDH замість GOx (без H₂O₂) — `01_03` §3
- [ ] **Gen 2.0:** Laccase + laccase-like nanozymes (Cu/Ce/Au ZIF) — `01_03` §3
- [ ] **Gen 2.0:** ZIF-інкапсуляція для 20-25 років — `01_03` §3.3

#### HW.6 — Resin barrier
- **Джерело:** `01_04` + Legacy notes
- **Опис:** Сосни заливають рану смолою → блокує доступ до ферментів
- [ ] 30° installation angle verification
- [ ] Hydrophilic coating test
- [ ] PEG обробка гіроїда: смола зісковзує з PEG-покритих пор — додано в `01_03`
- [ ] Hydrophobic/hydrophilic gradient test (PTFE знизу, гідрофільний верх) — додано в `01_04`
- [ ] Thermal installation test: T° нагріву (150-200°C), час витримки — додано в `01_04`
- [ ] FEM-моделювання теплового поля в Ti-6Al-4V анкері (λ = 6.7 W/m·K)

#### HW.7 — BQ25570 resistors verification
- **Джерело:** `02_03`
- **Опис:** CJMCU-25570 може мати Li-Po дефолт (VBAT_OV = 4.2V замість 5.5V для supercap)
- **Блокує:** Фіналізацію схеми, PCBA production
- [ ] Виміряти 8 резисторів мультиметром
- [ ] Порівняти з розрахунковою таблицею (Section 4 в `02_03`)
- [ ] Замінити SMD резистори якщо мисматч
- [ ] Задокументувати фінальні номінали

#### HW.8 — Pogo pin specification (5 блокерів)
- **Джерело:** `02_02`
- [ ] BLOCKER-1: Матеріал напилення → Gold (Hard Gold, Au 0.76 µm)
- [ ] BLOCKER-2: Сила пружини → ~100 г/пін, Travel ≥ 1.5 мм
- [ ] BLOCKER-3: Механізм фіксації → Quarter-turn bayonet (рекомендовано)
- [ ] BLOCKER-4: O-ring → EPDM, CS 1.5-2.0 мм, 15-25% compression
- [ ] BLOCKER-5: Допуски соосності → Lead-in chamfer

#### HW.9 — PCB KiCad layouts
- **Джерело:** `02_01`
- **Опис:** Soldier PCB та Queen PCB: "Не розпочато"
- [ ] Soldier PCB layout (KiCad)
- [ ] Queen PCB layout (KiCad)
- [ ] RF Keep-Out Zone verification

#### HW.10 — Modem name discrepancy
- **Джерело:** `02_05` + Legacy notes
- **Опис:** SIM7000G (Wiki) vs SIM7070G (firmware AT-commands). **Рішення прийнято: SIM7070G** — краща підтримка eDRX/PSM, нижче idle-споживання (~3 мкА vs ~10 мкА)
- [ ] Фізично перевірити маркування на прототипі
- [ ] Узгодити Wiki, BOM та firmware → **SIM7070G**
- [ ] Додати AT+CPSMS та AT+CEDRXS команди у firmware Queen

#### HW.11 — Potting material selection (quartz resonator risk)
- **Джерело:** `02_01` BLOCKER-1
- **Опис:** Потрібно обрати epoxy compound що НЕ знищить quartz resonator LoRa модуля при -20°C. Rigid compound при температурному стисненні → тріщини кварцу → RF loss
- **Рішення:** Soft compound Shore A < 50 (Dow Sylgard 184 або аналог)
- **Блокує:** Hardware freeze, IP67 certification
- [ ] Обрати compound (Sylgard 184 рекомендовано)
- [ ] Верифікувати з кварцовим резонатором при -20°C / +60°C

#### HW.12 — EBFC upper voltage limit >5.5V protection
- **Джерело:** `02_01` BLOCKER-2
- **Опис:** При тривалій інсоляції EBFC може генерувати напругу >5.5V → overcharge supercap → деградація/вибух
- **Блокує:** Hardware safety, TRL 5
- [ ] Верифікувати BQ25570 OV protection threshold (VBAT_OV = 5.5V, див. HW.7)
- [ ] Додати TVS-діод або зенерівський обмежувач як backup

#### HW.13 — MPPT coefficient verification for EBFC
- **Джерело:** `02_03` BLOCKER-2 + Legacy notes
- **Опис:** Поточний MPPT = 50% VOC (ROC1=ROC2=10MΩ) — **занадто низько для EBFC**. EBFC (GOx/Laccase) має специфічну поляризаційну криву (Міхаеліс-Ментен + Тафель), MPP лежить у діапазоні 60-70% VOC. При 50% — зона масо-транспортних обмежень ферменту
- **Рекомендація:** Почати з 65% (ROC1=5.36 MΩ, ROC2=10 MΩ)
- **Блокує:** Max EBFC power, optimal charge speed
- [ ] Зняти повну P-V криву (потужність-напруга) EBFC
- [ ] Виміряти VOC та VMP при різному освітленні (ранок/день/вечір, сезонно)
- [ ] Визначити оптимальну фракцію (починати з 65%)
- [ ] Якщо потрібно — замінити ROC1/ROC2

#### HW.14 — Winter energy deficit for Queen Phase 3 (Starlink Mini)
- **Джерело:** `02_05` BLOCKER-2
- **Опис:** Phase 3 (Starlink Mini): 44 Wh/day consumption vs 18.75 Wh/day winter generation = -25 Wh/day deficit. 12V/20Ah LiFePO4 → 7.7 днів автономності
- **Пріоритет:** Phase 3 only (Phase 2.5 unaffected)
- [ ] Збільшити батарею до 40Ah (15 днів автономності), АБО
- [ ] Зменшити Starlink duty cycle до 1 хв/год (~9 Wh/day), АБО
- [ ] Встановити 100W solar panel
- [ ] Оновити Unit Economics (07_02)

#### HW.15 — BMS not specified for Queen
- **Джерело:** `02_05` BLOCKER-4
- **Опис:** SIM7070G TX peak current до 2A. BMS model не вказано в BOM
- [ ] Обрати BMS: мінімум 12V / 20A continuous / 50A peak
- [ ] Обрати MPPT: мінімум Victron SmartSolar MPPT 75/15
- [ ] Оновити BOM

#### HW.16 — Thermal management в IP67 enclosure
- **Джерело:** `02_05` BLOCKER-5
- **Опис:** SIM7070G + MCU при TX: ~500 mW × 5 sec. Літній interior temp до 60-70°C. LiFePO4 charging при T < 0°C пошкоджує батарею
- [ ] Розрахувати thermal budget для enclosure (T_ext = +40°C)
- [ ] Додати temperature sensor (NTC або DS18B20)
- [ ] Реалізувати hardware charge protection при T < 0°C

#### HW.17 — PEEK radome prototype (Деталь 4)
- **Джерело:** `02_01` §5.2 + Legacy notes
- **Опис:** Деталь 4 (PEEK Crown / Капсула-Радом) — радіопрозорий купол ∅20–30 мм, який «насаджується» на зовнішню різьбу Деталі 3 (Анод). Різьба або байонет + O-ring EPDM → IP68. Керамічна SMD-антена в міліметрі від внутрішньої стінки PEEK. Прототип "Не розпочато"
- **Блокує:** Ceramic antenna protection, RF performance validation, Zero-Touch Assembly validation
- [ ] KiCad PCB layout (HW.9) → PEEK radome dimensions
- [ ] Визначити тип кріплення: різьба на Деталь 3 vs байонет
- [ ] Визначити матеріал O-ring (EPDM vs FKM) для ксилемного середовища
- [ ] Замовити PEEK прототип (CNC або injection molding)
- [ ] Верифікувати RF performance (VSWR, КСВ) з антеною під радомом

#### HW.18 — Starlink DTC: ESP32-S3 vs SIM8200G-M2 WiFi co-processor
- **Джерело:** `02_05` BLOCKER-1
- **Опис:** Phase 3 (Starlink Mini terminal) потребує WiFi co-processor. Архітектурне рішення між ESP32-S3 та SIM8200G-M2 не прийнято
- **Пріоритет:** Phase 3 only
- [ ] Прийняти архітектурне рішення
- [ ] Оновити 03_02 з рішенням
- [ ] Додати co-processor firmware до `firmware/`

#### HW.19 — VOC-діагностика деградації конденсатора (ADS1220 + TPS22860)
- **Джерело:** Legacy notes + `02_04` §4.2
- **Опис:** Раз на добу вимірювати чисту VOC EBFC (при від'єднаному навантаженні) для розрізнення "дерево хворіє" vs "конденсатор деградує". Обидва стани проявляються як зростання delta_t. ADS1220 (24-bit ADC) + TPS22860 (load switch) для прецизійного duty-cycling вимірювання. Для TRL 6 достатньо вбудованого 12-біт ADC STM32
- **Пріоритет:** TRL 8+ (після базової валідації в полі)
- [ ] Валідувати концепт на вбудованому 12-біт ADC (firmware: GPIO disconnect EDLC → measure VOC → reconnect)
- [ ] Якщо 12-біт недостатньо — додати ADS1220 + TPS22860 до BOM
- [ ] Backend: поле `voc_mv` у TelemetryLog для серверної корекції моделі Лоренца

#### HW.20 — Buffer Cap: Tantalum → MLCC migration
- **Джерело:** `02_03` §6 + Legacy notes
- **Опис:** Buffer Cap 100µF на лінії VOUT для LoRa TX peak. Рання специфікація вказувала танталовий конденсатор, але його струм витоку (1-10 мкА) подвоює/потроює E_sleep (1.5 мкА). Документація оновлена на MLCC X5R/X7R (виток ~десятки нА)
- [ ] Обрати конкретний part number: 100µF/6.3V X5R 1210 (напр. Murata GRM32ER60J107ME20)
- [ ] Врахувати DC bias derating (~20% при 3.3V/6.3V → ефективна ємність ~80µF)
- [ ] Додати до KiCad BOM (HW.9)

---

## 🔐 Безпека

#### SEC.1 — Multisig Gnosis Safe для production admin role
- **Джерело:** `05_03` Operational Security
- **Опис:** `DEFAULT_ADMIN_ROLE` у production контрактах SCC/SFC має бути Gnosis Safe multisig (3/5 або 2/3), а не EOA
- **Пріоритет:** Before mainnet deploy
- [ ] Створити Gnosis Safe wallet
- [ ] Reassign DEFAULT_ADMIN_ROLE у SCC та SFC контрактах

#### SEC.2 — RDP Level 2 activation timeline
- **Джерело:** `03_05` NOTE-1
- **Опис:** Поточний стан: RDP Level 0 (development). Level 1 потрібен перед першою польовою партією, Level 2 — тільки після повної OTA верифікації (незворотній — лише OTA updates можливі)
- [ ] Верифікувати OTA flow end-to-end
- [ ] Перейти на RDP Level 1 для field batch
- [ ] Задокументувати процедуру Level 2 activation (необоротна)

#### SEC.3 — Factory Flashing pipeline
- **Джерело:** `03_05` NOTE-2
- **Опис:** Multi-step factory process: (1) Flash firmware з placeholder key, (2) Backend → HKDF(master_key, device_uid) → unique_key, (3) Robot пише key у protected Flash sector, (4) STM32CubeProgrammer → RDP Level 1/2
- **Блокує:** Mass production
- [ ] Дизайн завершений
- [ ] Реалізація Factory Flashing tool
- [ ] Integration тест з provisioning API

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **Джерело:** `03_05` NOTE-3
- **Опис:** Reed switch (магнітний сенсор) для zero consumption при транспортуванні. Магніт на коробці → circuit open. Інсталятор знімає магніт → first power-up. ~$0.05/unit. Дизайн approved, BOM не оновлений
- [ ] Додати Hamlin 59140-1-T-00-A reed switch + N52 neodymium magnet до BOM
- [ ] Оновити KiCad schematic

#### SEC.6 — Secure Element (ATECC608B) не використовується
- **Джерело:** `03_05` | Firmware architecture
- **Опис:** AES-256 ключ зберігається у plain Flash STM32 (навіть з RDP Level 1 — key extraction можливий через glitching/side-channel). ATECC608B забезпечує hardware-protected key storage з tamper-detection. Ціна ~$0.60/unit
- **Пріоритет:** P2 (Post-TRL 7, перед mass production >1000 units)
- [ ] Оцінити ATECC608B integration з STM32WLE5JC (I²C interface)
- [ ] Дизайн key storage: ATECC608B slot 0 = AES key, slot 1 = device certificate
- [ ] Оновити Factory Flashing pipeline (SEC.3) для ATECC608B provisioning
- [ ] Оцінити альтернативи: STSAFE-A110 (ST ecosystem), Infineon OPTIGA Trust M

#### SEC.7 — OTA image автентифікація (cross-ref FW.23)
- **Джерело:** `03_05`, `03_02`
- **Опис:** OTA broadcast (mruby bytecode та потенційно firmware updates) не має цифрового підпису. Пов'язано з FW.23 але виділено як окремий security item через критичність. Поточний захист — лише AES-256-ECB шифрування (яке буде замінено на CCM в FW.2)
- **Пріоритет:** P1 (перед першою OTA в полі)
- [ ] Ed25519 key pair: private на backend, public у Soldier/Queen Flash (protected sector)
- [ ] Backend: `OtaPackagerService` → sign(bytecode) → append signature
- [ ] Firmware: verify signature перед Flash write
- [ ] Fallback: HMAC-SHA256 якщо Ed25519 не вміщується в SRAM budget

#### SEC.8 — ECB Restoration Race Condition (HAL_CRYP_Init timeout)
- **Джерело:** `03_05` BLOCKER-6 | **Пріоритет: P1**
- **Опис:** Після CoAP CBC flush Queen повинна відновити AES-ECB режим для прийому LoRa. `HAL_CRYP_Init()` — blocking call БЕЗ timeout. Якщо AES hardware hung (transient defect, power glitch) → ECB restoration зависне назавжди → вся мережа "мовчить" без error log
- **Рішення:** RCC peripheral reset (`__HAL_RCC_CRYP_FORCE_RESET()`) як fallback + повторна ініціалізація, `Error_Handler()` якщо другий init також fails
- [ ] Firmware Queen: додати timeout або watchdog до `HAL_CRYP_Init()` в `Restore_ECB_Mode()`
- [ ] Firmware Queen: `__HAL_RCC_CRYP_FORCE_RESET()` → `__HAL_RCC_CRYP_RELEASE_RESET()` як recovery
- [ ] Тест: симуляція hanging CRYP peripheral

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **Джерело:** `03_05` | **Пріоритет: P0 (до будь-якого field deploy)**
- **Опис:** Аудит виявив: перші 4 слова production AES key **ідентичні публічно відомому** FIPS-197 Appendix B AES-128 test vector (стандартний тест-вектор зі специфікації NIST). Будь-який фахівець з криптографії може впізнати цей паттерн. При RDP Level 0 — trivial key extraction
- **Важливо:** Це ОКРЕМЕ від FW.1 (hardcoded key) — навіть після per-device provisioning, якщо master seed базується на цьому ключі, весь derivation tree скомпрометований
- [ ] Негайно замінити seed key на криптографічно стійкий random (hardware RNG або аудитований генератор)
- [ ] Верифікувати що новий master key НЕ є жодним відомим test vector (FIPS-197, NIST, RFC)
- [ ] Задокументувати процес генерації нового master key у vault (Bitwarden/1Password) — **без коміту ключа в репозиторій**
- [ ] Після заміни: re-flash всі існуючі прототипи

#### SEC.10 — Emergency TX пакети без MAC/MIC автентифікації
- **Джерело:** `03_05`, `03_02` | **Пріоритет: P1**
- **Опис:** EwsAlert panic packets (chainsaw detection, PANIC_TTL=5) відправляються без жодної автентифікації. Зловмисник може: (1) replay легітимний panic packet → false forest fire alert → евакуація/паніка, (2) inject forged panic packets → множинні false alarms → недовіра до системи та страхових виплат
- **Важливо:** Критичніше за звичайні пакети — emergency TX обходить звичайні rate limits. Вирішується разом з FW.2 (AES-256-CCM), але потребує окремої уваги через life-safety implications
- [ ] Не відкладати вирішення на "після FW.2" — мінімальний fix: Frame Counter у RTC як anti-replay для panic packets
- [ ] Верифікувати що `EwsAlert` broadcast застосовує той самий CCM MIC що і звичайні пакети (після FW.2)
- [ ] Backend: rate limiting на emergency callbacks — не більше N panic alerts/хвилину від одного DID

---

## 📝 Документаційні невідповідності (DOC)

> Виявлені при cross-reference аудиті всіх 35 документів. Потребують узгодження між docs, firmware та backend.

| ID | Невідповідність | Документи | Дія |
|----|----------------|-----------|-----|
| DOC.2 | Катод/Анод labels плутанина в `01_01`: Деталь 1 (нижня частина) — в `01_01` описана як "Катод / передає Мінус", але у `01_03` правильно ідентифікована як **Анод** (GOx окислення). В `01_01` визначення суперечливе: реально анод є від'ємним полюсом джерела ЕРС, але cathode/anode маркування потребує уніфікації з `01_03` | `01_01`, `01_03` | Уніфікувати термінологію з `01_03` |
| DOC.4 | "Binary payload 16 bytes" (`00_01`) — це зашифрований inner payload. Повний зовнішній пакет = **21 байт** (4 DID + 1 RSSI + 16 encrypted) | `00_01` | Уточнити: 21B outer, 16B encrypted inner |
| DOC.10 | Dual Computation Integrity описана як ">30% числова дивергенція", але код робить **категоричне порівняння** (homeostasis vs stress) | `05_02`, CLAUDE.md | Виправити doc → "categorical comparison" |
| DOC.16 | Енергія TX: `02_01` каже 120mA/39mJ, `02_03` §9 каже 15mA/2.475mJ — несумісні значення | `02_01`, `02_03` | Узгодити (120mA = +22dBm коректно) |
| DOC.17 | RAM budget Queen: §5 header каже "~3.7 KB", але детальна таблиця = **~14.4 KB** (22% of 64KB) | `03_02` | Виправити header |
| DOC.21 | State root hash delimiter: `\|` в коді vs `:` в іншій секції doc | `05_01`, `05_04` | Уніфікувати → `\|` (як в коді) |
| DOC.24 | TRL 8 для backend (`04_01`) vs "7-8" в CLAUDE.md | `04_01`, CLAUDE.md | Узгодити |
| DOC.30 | OPTIMAL_Z_TARGET=29.0 vs математичний рівноважний z=ρ−1=27.0 — невідповідність без пояснення | `03_04`, `08_02` | Задокументувати rationale або виправити на 27.0 |
| DOC.31 | TRL 8 заявлено для `09_02` але модулі на TRL 3-4 — TRL-Lock principle (§3 `09_02`) обмежує загальний TRL | `09_02` | Застосувати TRL-Lock |
| DOC.32 | Akash TRL "6 ✅" але **жоден deploy не проведений** — аргументовано TRL 5 | `06_02` | Понизити до TRL 5 |

---

## ⚙️ Операційна автоматизація (OPS)

#### OPS.1 — TRL Auto-Advancement GitHub Action
- **Джерело:** `09_03` | **Складність: M**
- **Опис:** `trl_sync.yml` — GitHub Action що автоматично переміщує картки на Project Board при закритті issues з TRL-labels. Описаний як "на стадії впровадження" (TRL 7), але не реалізований. Потребує `secrets.PROJECT_PAT` з GraphQL project board permissions
- **Статус:** ✅ Виконано. `.github/workflows/trl_sync.yml` створено з GraphQL API для GitHub Projects v2 (user + org fallback)
- [x] Створити `.github/workflows/trl_sync.yml`
- [x] Налаштувати GraphQL API для GitHub Projects v2
- [ ] Створити `PROJECT_PAT` secret з project:write scope
- [ ] Тестування з тестовими issues

#### OPS.2 — SSOT Integrity Guard
- **Джерело:** `09_03` | **Складність: M**
- **Опис:** GitHub Action що блокує merge PRs якщо зміни в `app/models/` або `firmware/` не супроводжуються відповідними оновленнями в `docs/` або Wiki. Запобігає context drift між кодом та документацією
- **Статус:** ✅ Виконано (Сесія 18). `.github/workflows/ssot_guard.yml` створено. Перевіряє: `app/models/`, `firmware/soldier/`, `firmware/queen/`, `firmware/bio_contracts/`, `contracts/`, `app/services/`. Bypass через label `ssot-bypass`. Виводить деталізований звіт у PR check.
- [x] Створити `.github/workflows/ssot_guard.yml`
- [x] Визначити mapping: які файли потребують яких doc updates
- [ ] Налаштувати як required check на `main` branch

---

## 📋 Юридичні / Бізнес

#### BIZ.1 — 1 SCC = ? kg CO₂ ✅
- **Джерело:** `07_01`
- **Опис:** CO₂ еквівалент для 1 SCC — визначено: **2000 SCC = 1 tCO₂ (1 SCC = 0.5 кг CO₂)**
- **Статус:** ✅ Реалізовано (2026-04-23)
- [x] Визначити методологію розрахунку — **2000 SCC = 1 tonne CO₂** (закрито в `07_01` BLOCKER-4)
- [x] Додати в код — `ProtocolParameters.sol#KEY_SCC_PER_TONNE_CO2 + sccPerTonneCo2()`, `SystemParameter(:scc_per_tonne_co2, value: 2000)`, `db/seeds.rb`
- [x] Задокументувати — `07_01` §3 + BLOCKER-4, `07_02` §7.1
- [ ] Сертифікація методології (Verra VCS / Gold Standard) — потребує залучення методолога (Post-TRL 7)

#### BIZ.2 — B2B MSA (Master Service Agreement)
- **Джерело:** `07_01`
- [ ] Створити юридичний шаблон
- [ ] Review з юристом

#### BIZ.3 — B2C ToS / Privacy Policy
- **Джерело:** `07_01`
- [ ] Terms of Service draft
- [ ] Privacy Policy (GDPR-compliant)
- [ ] Cookie Policy

#### BIZ.4 — DAO Governance Process ✅
- **Джерело:** `07_01`, `05_03`
- **Опис:** SFC voting mechanism — Governance DAO
- **Статус:** ✅ Реалізовано (ARCH.4 / E.35 / E.1)
- [x] SilkenGovernor.sol — OZ Governor + GovernorVotes + GovernorTimelockControl + GovernorCountingSimple + GovernorVotesQuorumFraction (4% quorum, 43200 blocks delay ~1 day, 302400 blocks period ~7 days, 100 SFC threshold)
- [x] SilkenTimelock.sol — TimelockController (48h min delay)
- [x] ProtocolParameters.sol — on-chain registry з 13 well-known parameter keys (Lorenz, tokenomics, slashing)
- [x] Governance::ParameterSyncWorker — queue: web3_low, 1×/day, Eth::Contract + Web3::RpcConnectionPool → SystemParameter

#### BIZ.5 — Patent application
- **Джерело:** `08_03`
- [ ] Engagement з патентним адвокатом
- [ ] Патентна заявка на дизайн анкера

#### BIZ.6 — Supply chain war-zone risk mitigation
- **Джерело:** `07_02` | **Пріоритет: P1**
- **Опис:** DMLS manufacturing залежить від українських підрядників (Київ 3D Metal Tech, Дніпро ALT Ukraine, Черкаси SVS-ARTA) — зона активних бойових дій. Логістичні ризики, енергетичні перебої, мобілізація персоналу. Відсутній contingency plan з EU/US альтернативами
- [ ] Ідентифікувати 2-3 backup DMLS заводи в ЄС (Польща, Чехія, Німеччина)
- [ ] Отримати quotes для порівняння вартості
- [ ] Задокументувати contingency план у `07_02`

#### BIZ.7 — Soldier failure rate та replacement OPEX
- **Джерело:** `07_02` | **Пріоритет: P2**
- **Опис:** Unit Economics (`07_02`) не враховують failure rate Soldiers в полі та вартість їх заміни. При 10,000+ деревах навіть 1% annual failure = 100 replacements/рік. Також відсутня оцінка деградації LiFePO4 батареї Queen (12V 6Ah) за 5+ років
- [ ] Визначити expected failure rate (target < 1% annually)
- [ ] Додати replacement OPEX у Unit Economics
- [ ] Додати Queen battery degradation (80% capacity після 2000 циклів ≈ 5.5 років)
- [ ] Оновити ROI model в `07_02`

---

## 🎓 Академічні блокери (ЧНУ)

#### UNI.1 — Перший контакт з деканом Онищенком
- **Джерело:** `08_01`
- **Блокує:** Всю лабораторну роботу, 10 публікацій, 11 магістерських
- [ ] Призначити зустріч
- [ ] Підготувати презентацію проєкту
- [ ] Провести зустріч

#### UNI.2 — 8 зустрічей з факультетом ФОТІУС
- **Джерело:** `08_02`
- [ ] Супруненко (ПЗАС) — PN-verification, Convolution Method
- [ ] Онищенко (Декан) — stochastic B&B, Petri nets
- [ ] Ярмілко — Embedded Systems, ECDH key exchange
- [ ] Порубльов — Discrete Math, reliability
- [ ] Косенюк — RF/FEC/compliance
- [ ] Бушин — CNN/BSP/DMLS physics
- [ ] Осауленко — Portfolio management
- [ ] Любченко — GA/Neural Networks

#### UNI.3 — IP договір з ЧНУ
- **Джерело:** `08_03`
- **Блокує:** Старт публікацій
- [ ] Юридичне оформлення IP-договору
- [ ] Підпис обома сторонами

---

## 💡 Додаткові знахідки (не блокери)

| # | Знахідка | Джерело | Примітка |
|---|----------|---------|----------|
| E.1 | ✅ SFC voting power коректно зменшується після slashing — ERC20Votes `_update` → `_transferVotingUnits` → checkpoint update. Підтверджено аналізом OZ v5 | `07_01` | ✅ Досліджено та підтверджено |
| E.3 | Breadboard video відсутнє (для грантів) | `07_03` | Зняти відео |
| E.4 | Helium Network fallback — concept є, реалізації немає | `02_05` | Дизайн + реалізація |
| E.5 | CoAP listener Ruby — масштабується до ~10k вузлів | `06_01` | Series D: Rust/Go proxy |
| E.7 | dClimate mock mode — потрібна реальна інтеграція для Production | `05_01` | Пов'язано з S3.2 |
| E.8 | SNR parameter unused у Queen CIFO eviction (лише RSSI) | `03_02`, `03_03` | Low priority optimization |
| E.9 | DMA SPI optimization — зменшення енергоспоживання (Vector 1 — Ярмілко) | `08_02` | R&D partnership |
| E.10 | Kalman/EMA filtering для delta_t noise suppression (±8% → ±1.2%) | `08_02` | R&D partnership |
| E.11 | CE/FCC/EMC/IP68 certification roadmap не розпочато | `08_02` | Потребує Косенук (RF) |
| E.12 | Boolean minimization TX decision conditions (Karnaugh/Quine-McCluskey) | `08_02` | Потребує Любченко |
| E.13 | Petri Net model of Rails monolith — deadlock-free verification at 10k concurrent IoT | `08_02` | Потребує Супруненко |
| E.14 | Multi-source satellite + anchor data fusion (Sentinel-2 NDVI) | `08_02` | Потребує Любченко + Бушин |
| E.15 | Reed-Solomon FEC або Hamming для LoRa error correction | `08_02` | Потребує Косенук |
| E.18 | 10 запланованих Q1 публікацій — blocked by lab data | `08_03` | Blocked by UNI.1-3 |
| E.19 | 8 магістерських — blocked by TRL 4 advancement | `08_03` | Post-TRL 4 |
| E.20 | Forester Guild (Proof-of-Physical-Work) — planned post-TRL 6 | `04_02` | Post-TRL 6 |
| E.26 | `health_trend` field для TelemetryLog — predictive degradation | Legacy | Post-TRL 6, потребує E.10 (Kalman) |
| E.27 | Chaos Engineering: Chaos Mesh для Akash або kill-scripts для Kamal | Legacy | Post-TRL 7, production hardening |
| E.28 | Kamal deploy hooks idempotency audit | `06_01` | Верифікувати `.kamal/hooks/` |
| E.29 | Альтернативні EBFC медіатори (ferrocene, methylene blue) | `01_03` | R&D alternatives |
| E.30 | InsightGenerator: кліматичні базлайни per region | `04_02` | Post-TRL 7 |
| E.31 | TinyML OTA: `.tflite` формат (INT8 quantization) + Python ML microservice | `03_03` | Post-TRL 8 |
| E.32 | ✅ (Slither + Foundry) Smart Contract Audit: Slither в CI (`.github/workflows/solidity_audit.yml`). Foundry toolchain (`contracts/foundry.toml`): solc 0.8.28, EVM cancun, optimizer 200 runs, CI/production profiles. 178 тестів у 6 test suites. Coverage via `forge coverage --ir-minimum`. Mythril + Hacken — окремі етапи pre-mainnet | `05_03` | Slither CI ✅ (Сесія 19-20), Foundry tests ✅ (Сесія 22-23), Mythril + Hacken TODO |
| E.33 | AlertNotification rate limits: FCM multicast (500 tokens/req), Twilio Notify | `04_02` | Post-TRL 8 |
| E.34 | dClimate fallback → ForestBountyService (drone/ranger PoPhW) | `04_02` | Post-TRL 6 |
| E.35 | ✅ Flash Loan defense реалізовано в `SilkenGovernor.sol`: GovernorVotes (`getPastVotes`), GovernorSettings (votingDelay=43200 блоків ~1 day, votingPeriod=302400 ~7 days), GovernorVotesQuorumFraction (4%), GovernorTimelockControl (48h через `SilkenTimelock.sol`) | `05_03` | ✅ Реалізовано |
| E.36 | PostGIS Generated Column (geo_boundary) замість тригера | `04_01` | Post-TRL 8 |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates | `04_01` | >100M рядків/місяць |
| E.38 | Press-Fit фаски: R ≥ 0.2 мм для зняття напружень у PEEK | `01_01` | Включити у nTop (HW.1) |
| E.39 | **EBFC Gen 2.0:** FAD-GDH + Laccase/nanozymes + ZIF (20-25 років) | `01_03` §3 | ЧНУ lab testing |
| E.40 | **Ignion Virtual Antenna™:** NN02-310 як альтернатива Yageo/Taoglas 868 МГц | `02_01` §5 | Evaluation kit + VSWR тест |
| DIFF.1 | `Wallet#lock_and_mint!` threshold = runtime param (не hardcoded) | `04_02` | Informational, no action |
| DIFF.7 | SNR parameter unused in Queen CIFO eviction | `03_02` | Low priority optimization |
| E.41 | **Fire events delayed 48h** via dClimate satellite obscuration — **⚠️ life-safety risk**. Mitigation: Forester Guild as Fallback Oracle (E.20) + immediate local broadcast via panic TX (не чекати satellite clearance при chainsaw detection). **Пріоритет: P1** (не відкладати на Post-TRL 6) | `04_02`, `05_01` | P1: interim emergency fallback |
| E.42 | **TelemetryLog cleanup safety**: видалення записів з `oracle_status='dispatched'` ламає Chainlink callbacks. Cleanup job MUST exclude `dispatched` status — підтверджено в коді | `04_02` | ⚠️ Не видаляти dispatched records |
| E.43 | **OPTIMAL_Z_TARGET=29.0 vs z_eq=27.0**: математичний рівноважний стан Лоренца при ρ=28 є z=ρ−1=27. Значення 29.0 — навмисний offset (+2σ від equilibrium) для кращої розрізнення класів. Потребує документування rationale або консультації з ЧНУ (Порубльов) | `03_04`, `08_02` | Задокументувати в `03_04` |
| E.44 | **Sensor University mismatch**: `08_02` згадує "ЧНУ ім. Юрія Федьковича" (Чернівці) але контекст — Черкаський ЧНУ. Можливо два університети або factual error у назві | `08_02` | Уточнити назву університету |
| E.45 | **SCC/SFC contract addresses** = `0x0000...0` в subgraph.yaml — блокує deploy subgraph на testnet/mainnet | `05_03` | Пов'язано з S3.5 |
| E.46 | **Insurance pool failsafe → true on RPC failure**: `insurance_pool_requires_funding?` повертає `true` при RPC error → unnecessary 2% tax на кожен mint під час RPC degradation | `04_02`, `05_03` | P2: більш graceful fallback |
| E.47 | **Solana RPC defaults to Devnet** — production мінтинг USDC мікро-винагород піде на Devnet якщо не встановлений `SOLANA_RPC_URL` | `05_01` | ⚠️ Перевірити ENV перед mainnet |
| E.48 | **The Graph subgraph на testnet `polygon-amoy`** — потребує mainnet deploy перед production | `05_01` | Post mainnet deploy |
| E.49 | **Celo RPC fallback mechanism** не вказаний — при збої primary RPC немає автоматичного переключення | `05_01` | P3: додати fallback RPC |
| E.50 | **Streamr broadcast failures silently dropped** — немає alerting/logging при неможливості доставки P2P real-time broadcast | `05_01` | P3: додати error tracking |
| E.51 | **Hardcoded oracle balance thresholds** (0.05 MATIC, 0.05 SOL) — рекомендується зробити configurable через `ProtocolParameters` | `05_02` | P3: перемістити до SystemParameter |
| E.53 | **SFC excluded from state root** — `SilkenForestCoin` total supply не входить у weekly state root hash, хоча SFC є частиною tokenomics | `05_04` | Оцінити додавання до state root |
| E.54 | **Active tree count excluded from state root** — кількість активних дерев не верифікується на L1 | `05_04` | Оцінити додавання |

---

## 🏛️ Архітектурні пропозиції (довгострокові)

| ID | Пропозиція | Джерело | Milestone |
|----|-----------|---------|-----------|
| ARCH.1 | Fractal topology: L2 Sergeant nodes (H-LDSE hierarchical routing, geohashing) | `00_01` | Post-TRL 7 |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka для >1M packets/hour | `00_01`, `06_01` | Series D |
| ARCH.4 | ✅ Governance DAO (SFC voting) — protocol constants via on-chain governance. `SilkenGovernor.sol` + `SilkenTimelock.sol` + `ProtocolParameters.sol` + `Governance::ParameterSyncWorker` | `05_03` | ✅ Реалізовано |
| ARCH.5 | Cross-Registry Export (Verra, Gold Standard, UNFCCC) | `04_02` | Post-TRL 7 |
| ARCH.6 | Federated Learning auto-retraining (monthly cycle, A/B testing) | `04_02` | Post-TRL 7 |
| ARCH.7 | Edge Data Fusion: transmit 2-byte λ-exponent замість 16-byte Z payload | `00_01` | Post-TRL 7 |
| ARCH.8 | Event-Triggered Reporting: heartbeat 1/day normal, continuous on anomaly | `00_01` | Post-TRL 6 |
| ARCH.9 | Network Sharding: isolate anomalous clusters to prevent storm propagation | `00_01` | Post-TRL 7 |
| ARCH.10 | Queen-to-Queen Backhaul Mesh: LoRa SF12 inter-Queen relay (Starlink fallback) | `00_01` | Post-TRL 8 |
| ARCH.11 | Energy-Aware Routing: route metric = f(hop_count, remaining_energy, bio_potential) | `00_01` | Post-TRL 7 |
| ARCH.12 | Merkle Tree state root (замість flat SHA-256) для partial verification / ISO 14064 | `05_04` | TRL 9 |
| ARCH.13 | EigenLayer AVS як альтернатива direct L1 write (~$0.01/week vs $5-15/week) | `05_04` | Research |
| ARCH.14 | Read-Only PostgreSQL Replicas для analytics та Oracle queries | `00_01`, `06_01` | Post-TRL 7 |
| ARCH.15 | ✅ SystemParameter model для governance-aware backend (`SystemParameter.current(:lorenz_sigma)`) | `05_03` | ✅ Реалізовано (Сесія 19): модель, міграція, 19 seed-параметрів (Lorenz, tokenomics, alerts, hardware), spec, factory. Кешований lookup з TTL 24h, fallback на default |
| ARCH.16 | Mobile app для foresters (Phase 2 roadmap) | `00_02` | Post-TRL 7 |
| ARCH.17 | Bonding Curves для dynamic SCC pricing | `05_03` | TRL 9+ |
| ARCH.18 | Детерміністична Fixed-Point арифметика (Integer Math): для досягнення побітової ідентичності розрахунків (consensus) між STM32 (Soldier) та GCP/Akash (Backend), необхідно відмовитись від IEEE 754 Floating-Point. Всі вхідні дані мають множитись на 10⁶ (або 10⁸) і розраховуватись у 64-бітних цілих числах (`int64_t` у C, `Integer` у Ruby). Це усуне апаратний drift при розрахунку Атрактора Лоренца. Потребує повного переписування математики в прошивці з урахуванням ризиків переповнення буферів (overflows) під час множення великих чисел. | `03_04`, `05_02` | Post-TRL 7 |
| ARCH.19 | BSP-кластеризація IoT-графу для заміни flat TTL-mesh при масштабуванні: Binary Space Partitioning дерево на основі географічних координат Queen. Зменшує broadcast collisions та енергоспоживання. Кожна Queen знає тільки своїх сусідів | `08_02` | Post-TRL 7 |
| ARCH.20 | Petri Net PN-модель Rails моноліту: формальна верифікація відсутності deadlock при 10,000 concurrent IoT connections. Sidekiq + Puma + PostgreSQL modeling. Конволюційний метод для зменшення state space explosion у 10-100 разів | `08_02` | R&D (Супруненко, ЧНУ) |
| ARCH.21 | Brownout detection + graceful shutdown: PVD IRQ при vcap < 1.8V → збереження Lorenz стану у RTC DR0-DR10 → STOP2. При відновленні живлення — продовжити з того самого стану. Захищає від корупції стану при раптовому знеструмленні | `08_02` | Post-TRL 6 (Firmware) |
| ARCH.22 | Arithmetic compression для LoRa payload: lambda-exponent (2 байти) замість повного Z (16 байт). Потенційна економія ~34% TX часу (21→~14 bytes). Event-Triggered Reporting: "мовчання = здоров'я" — 24× зниження трафіку | `08_02`, `00_01` | Post-TRL 7 |
| ARCH.23 | Multi-Attribute Utility Function для автономного рішення TX на MCU: оцінка важливості поточного пакету (Vcap, delta_t, acoustic, bio_status) — відправляти лише якщо utility > threshold. Оцінка: 30-40% зниження TX | `08_02` | Post-TRL 7 (Ярмілко, ЧНУ) |
| ARCH.24 | CE/FCC/RoHS/EMC/IP68 compliance roadmap для EU/NA ринків: CE-RED (868 МГц LoRa), FCC Part 15/90, RoHS-2, IP68 (IEC 60529), REACH. Кожна сертифікація потребує 3-6 місяців та спеціалізованої лабораторії | `08_02` | Pre-mass production (Косенюк, ЧНУ) |
| ARCH.25 | Gyroid geometric validation scripts: Python/C++ верифікація 65% пористості per-slice, topological integrity mesh, capillary channel connectivity via BFS (breadth-first search). Запускається після кожного nTop build для запобігання помилкам DMLS | `08_02` | Before DMLS factory order |

---

## 📊 TRL Матриця

| Модуль | TRL | Цільовий | Головний блокер |
|--------|-----|----------|-----------------|
| 00 System Architecture | 4 | 9 | Module 01 chemistry |
| 01 Materials & EBFC | 3 | 6 | Lab tests (ЧНУ) |
| 02 Hardware & BOM | 4 | 6 | BQ25570, PCB, Pogo, PEEK |
| 03 Firmware | 6 | 8 | AES key, TinyML, AT blocking |
| 04 Backend Rails | 8 | 9 | RSpec тести |
| 05 Web3 Pipeline | 8-9 | 9 | SFC address |
| 06 DevOps | 7 | 9 | Docker registry, TLS |
| 07 Business | 5 | 8 | CO₂ methodology, MSA, ToS |
| 08 University R&D | 2 | 6 | ЧНУ partnership |
| 09 Project Management | 7 | 9 | — |
| 10 Security | 5 | 9 | Multisig, RDP, Factory |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
