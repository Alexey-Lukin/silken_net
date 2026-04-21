# 10_02 — Action Plan Tracker (Залишок робіт)

> **Створено:** 2026-04-18 (Аудит 35 документів `00_00` → `09_03`)
> **Останнє оновлення:** 2026-04-21 Сесія 19 (ARCH.15 SystemParameter model + E.32 Slither CI)
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

---

## 📝 Документаційні невідповідності (DOC)

> Виявлені при cross-reference аудиті всіх 35 документів. Потребують узгодження між docs, firmware та backend.

| ID | Невідповідність | Документи | Дія |
|----|----------------|-----------|-----|

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

#### BIZ.1 — 1 SCC = ? kg CO₂
- **Джерело:** `07_01`
- **Опис:** CO₂ еквівалент для 1 SCC не визначений — ЮРИДИЧНИЙ БЛОКЕР
- **Блокує:** Carbon credit marketplace integration
- [ ] Визначити методологію розрахунку
- [ ] Додати в код (constants або config)
- [ ] Задокументувати для carbon registries

#### BIZ.2 — B2B MSA (Master Service Agreement)
- **Джерело:** `07_01`
- [ ] Створити юридичний шаблон
- [ ] Review з юристом

#### BIZ.3 — B2C ToS / Privacy Policy
- **Джерело:** `07_01`
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
| E.1 | SFC voting power зберігається після slashing | `07_01` | Дослідити |
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
| E.32 | ✅ (Slither) Smart Contract Audit: Slither в CI (`.github/workflows/solidity_audit.yml`). Foundry toolchain (`contracts/foundry.toml`): solc 0.8.24, EVM cancun, optimizer 200 runs, CI/production profiles. Mythril + Hacken — окремі етапи pre-mainnet | `05_03` | Slither CI ✅ (Сесія 19-20), Mythril + Hacken TODO |
| E.33 | AlertNotification rate limits: FCM multicast (500 tokens/req), Twilio Notify | `04_02` | Post-TRL 8 |
| E.34 | dClimate fallback → ForestBountyService (drone/ranger PoPhW) | `04_02` | Post-TRL 6 |
| E.35 | Flash Loan defense в GovernorContract.sol: `getPastVotes` + 48h Timelock | `05_03` | Post-TRL 6 |
| E.36 | PostGIS Generated Column (geo_boundary) замість тригера | `04_01` | Post-TRL 8 |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates | `04_01` | >100M рядків/місяць |
| E.38 | Press-Fit фаски: R ≥ 0.2 мм для зняття напружень у PEEK | `01_01` | Включити у nTop (HW.1) |
| E.39 | **EBFC Gen 2.0:** FAD-GDH + Laccase/nanozymes + ZIF (20-25 років) | `01_03` §3 | ЧНУ lab testing |
| E.40 | **Ignion Virtual Antenna™:** NN02-310 як альтернатива Yageo/Taoglas 868 МГц | `02_01` §5 | Evaluation kit + VSWR тест |
| DIFF.1 | `Wallet#lock_and_mint!` threshold = runtime param (не hardcoded) | `04_02` | Informational, no action |
| DIFF.7 | SNR parameter unused in Queen CIFO eviction | `03_02` | Low priority optimization |

---

## 🏛️ Архітектурні пропозиції (довгострокові)

| ID | Пропозиція | Джерело | Milestone |
|----|-----------|---------|-----------|
| ARCH.1 | Fractal topology: L2 Sergeant nodes (H-LDSE hierarchical routing, geohashing) | `00_01` | Post-TRL 7 |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka для >1M packets/hour | `00_01`, `06_01` | Series D |
| ARCH.4 | Governance DAO (SFC voting) — protocol constants via on-chain governance | `05_03` | Post-TRL 6 |
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

## 📝 Журнал оновлень

| Дата | Зміни |
|------|-------|
| 2026-04-18 | Створено документ. Аудит 35 docs, codebase, firmware. Інтеграція legacy notes. |
| 2026-04-18 | Сесії 2-6: S1.3/S1.6-8/S2.4-5/S3.1/S3.4-6/FW.12-15/DIFF.2-6/INF.3/E.2/E.17 виконано. |
| 2026-04-19 | Сесії 7-8: ARCH.3/DIFF.4/DIFF.6/E.6/E.16/E.21-25/INF.1/INF.4-7/S4.1 виконано. Infrastructure Pivot. |
| 2026-04-19 | Сесія 9: OBS.1 — Grafana Alloy sidecar → Grafana Cloud (BLOCKERs 1-3 resolved). |
| 2026-04-19 | Сесія 10: Очищення трекера — видалено виконані задачі, прибрано sprint-групування. Відновлено описи для незавершених пунктів. |
| 2026-04-19 | Сесії 12-13: Глибокий аудит всіх 35 docs (повне читання, не лише заголовки). Cross-reference codebase. Додано: S5.1-S5.6 (backend), FW.22-FW.23 (firmware), SEC.5-SEC.7 (security), DOC.1-DOC.7 (документаційні невідповідності), OPS.1-OPS.2 (автоматизація), BIZ.6-BIZ.7 (бізнес), ARCH.7-ARCH.17 (архітектурні пропозиції). Всього ~40 нових пунктів. |
| 2026-04-20 | Сесія 14: **SEC.5** — fail-fast guard `SecurityError` при `WEB3_STRICT_MODE=true` без `CHAINLINK_HMAC_SECRET` + integration test. **DOC.1** — `02_04` Lorenz thresholds → 2.0/45.0/29.0. **DOC.3** — `04_04` TRL 9→8. **DOC.5** — `04_03` endpoint count 82→83. **DOC.6** — `05_02` `peaq_signing_key` → mandatory. **DOC.7** — `05_02` soldier 648→771 рядків. |
| 2026-04-21 | Сесія 15: **FW.11** — NVIC-рівнева ізоляція `vibration_detected` race condition. **FW.15** — `test_tinyml_pipeline.c` (25 тестів) + `test_encryption.c` (18 тестів). **FW.16** — `Restore_ECB_Mode()` helper з RCC reset + NVIC_SystemReset fallback. **FW.22** — backend warning для `acoustic_events==255` в `TelemetryUnpackerService`. **FW.7/FW.19** — задокументовано Float vs BigDecimal tolerance як "by design" в `03_04`. **FW.5** — BLOCKER-1 збагачено аналізом chaos_seed vs delta_t/vcap впливу на токеноміку (залишено відкритим). **CI** — `firmware_test` job додано до `.github/workflows/ci.yml`. **03_03** — BLOCKER-4 (тести) та BLOCKER-8 (race condition) закрито. Всього 207 firmware тестів (79+58+27+25+18). |
| 2026-04-21 | Сесія 16: **FW.6** — Lorenz State Persistence: стан (x,y,z) зберігається в RTC DR16-DR18 між циклами STOP2 (BLOCKER-3 закрито). 16 нових C-тестів. **FW.7** — уточнено як TRL 6 mitigation з попередженням про IEEE 754 ARM/x86 drift. **ARCH.18** — додано Fixed-Point Arithmetic (Integer Math) як довгостроковий roadmap для побітового consensus. Документація оновлена: `03_04` (BLOCKER-3), `03_01` (register map DR0-DR19), `05_02` (firmware phases). Всього 223 firmware тести (79+74+27+25+18). |
| 2026-04-21 | Сесія 17: **S5.2** — `RELEASE_VERSION` ENV додано до deploy.yml (Canopy: git SHA), deploy-production.yml (Production: release tag), config/deploy.yml (Kamal), deploy/akash/deploy.yaml (web+job). Sentry release tracking тепер активний. **SEC.5** — Документовано HMAC bypass security requirement у `04_03` (WEB3_STRICT_MODE=true → SecurityError). **DOC.4** — Пористість узгоджена: CLAUDE.md та copilot-instructions.md оновлені з 70% → 65% (target), діапазон 60-70% (відповідно до `01_01`). **Трекер** — Позначено як виконані: S5.1 (Prometheus метрики), S5.3 (deploy-production.yml), OPS.1 (trl_sync.yml). |
| 2026-04-21 | Сесія 18: **FW.22** — `acoustic_events` змінено з `uint16_t` на `uint8_t` із saturating increment (`if < 255`) у `soldier/main.c:415`. Packing спрощено (ternary видалено). 8 unit tests. **FW.10** — Temperature-based TX deferral: guard clause `packed_temp < -15 && vcap_voltage < 4000` → `goto phase5_kenosis`. Named constants `COLD_TX_DEFER_TEMP`, `COLD_TX_DEFER_VCAP_MV`. 10 unit tests. **OPS.2** — SSOT Integrity Guard: `.github/workflows/ssot_guard.yml` створено. Перевіряє 6 protected areas (models, firmware, contracts, services). `ssot-bypass` label для обходу. Всього 241 firmware тест (79+92+27+25+18). |
| 2026-04-21 | Сесія 19: **ARCH.15** — `SystemParameter` модель для governance-aware backend. Міграція, модель з `.current(:key, default:)` кешований lookup (TTL 24h), 19 seed-параметрів (Lorenz: σ/ρ/β/dt/iterations/z_min/z_max/z_target, tokenomics: emission_threshold/dynamic_tax_rate/insurance_pool_threshold, alerts: fraud/fire/seismic thresholds, hardware: vcap bounds). Factory, spec (валідації, typed_value, кешування, bounds, .set, .current_values). **E.32** — Slither static analysis CI: `.github/workflows/solidity_audit.yml` для 3 Solidity контрактів (SCC/SFC/StateRootAnchor). OpenZeppelin 5.x, pragma 0.8.24, `fail-on: high`. `contracts/package.json` для npm dependencies. |
| 2026-04-21 | Сесія 20: **E.32 (fix)** — Slither CI fix: pragma 0.8.20→0.8.24 (OZ 5.x ERC20Permit/ERC20Votes вимагають ^0.8.24). `contracts/foundry.toml` додано (evm_version=cancun для mcopy opcode в OZ Bytes.sol). Foundry profiles: default (optimizer 200 runs), ci (no optimizer, fast builds), production (optimizer 1000 runs, via_ir). `slither.config.json` оновлено: `--evm-version cancun`. `.gitignore` доповнено `contracts/out/`, `contracts/cache/`. Docs оновлено: `05_03`, `05_04`, `10_02`. |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
> 3. Заповнити поля **Сесія** та **Коміт**
> 4. Додати запис у таблицю **Журнал оновлень**
> 5. Оновити **Зведену статистику** вгорі (якщо блокер закрито)
> 6. Оновити поле **Останнє оновлення** у шапці документа
