# 10_02 — Action Plan Tracker (Залишок робіт)

> **Створено:** 2026-04-18 (Аудит 35 документів `00_00` → `09_03`)
> **Останнє оновлення:** 2026-04-19 Сесія 10 (Очищення трекера)
> **Принцип:** Цей документ містить ТІЛЬКИ незавершені задачі. Виконана робота задокументована у відповідних docs (`00_00` → `10_01`).

---

## 🛣️ Software / Backend / DevOps

#### S1.1 — GitHub Secrets заповнення
- **P0** | `06_01` | Блокує весь CI/CD pipeline
- **Опис:** 12 критичних секретів не встановлені: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `DATABASE_URL`, `SSH_PRIVATE_KEY`, тощо
- [ ] Створити список необхідних секретів (checklist)
- [ ] Заповнити GitHub repository secrets
- [ ] Верифікувати CI pipeline проходить

#### S1.5 — Kamal IP placeholders
- **P2** | `06_01` | Операційна задача після `terraform apply`
- **Опис:** `192.168.0.1` та `<CANOPY_SERVER_IP>` — плейсхолдери в Kamal config
- [ ] Підставити реальні IP після `terraform apply`
- [ ] Верифікувати Kamal deploy з реальними IP

#### S2.1 — Верифікація метрик після deploy
- **P0** | `06_03` | Alloy sidecar налаштовано, потрібна верифікація
- [ ] Верифікувати що метрики збираються (після першого Akash deploy)

#### S2.2 — Grafana Cloud dashboards
- **P0** | `06_03` | Операційна задача в Grafana Cloud UI
- [ ] Dashboard: Sidekiq queues (9 черг, size + latency)
- [ ] Dashboard: Web3 RPC errors by network
- [ ] Dashboard: Telemetry ingest rate + fraud detection
- [ ] Dashboard: Treasury / Oracle balance monitoring
- [ ] Dashboard: Database connection pool stats

#### S2.3 — Grafana Cloud alerting rules
- **P0** | `06_03` | Операційна задача в Grafana Cloud UI
- [ ] Alert: `web3_critical` queue depth > 100
- [ ] Alert: `silkennet_telemetry_fraud_detected_total` rate > 0
- [ ] Alert: `silkennet_rpc_errors_total` rate > 10/min
- [ ] Alert: Oracle balance < threshold
- [ ] Alert: Sidekiq queue latency > 5 min
- [ ] Налаштувати notification channel (Slack / Email / PagerDuty)

#### S2.4 — RSpec тести для Prometheus метрик
- **P1** | `06_03` | Потребує PostgreSQL
- [ ] Додати RSpec тести для нових метрик

#### S3.1 — Guard clause RSpec тести
- **P1** | `04_02` | Аудит завершено, потрібні тести
- [ ] Додати RSpec тести для обох сценаріїв (oracle-driven + batch emission)

#### S3.2 — dClimate Real API verification
- **P1** | `05_01` | Сервіс реалізований, потрібна staging верифікація
- [ ] Верифікувати з реальним API ключем в staging
- [ ] End-to-end тест з `DclimateVerificationWorker`

#### S3.3 — PuroEarth REST API інтеграція
- **P1** | `05_01`, `05_03` | On-chain anchoring є, REST API — TODO
- [ ] Інтеграція з реальним Puro.earth API (поточно: тільки on-chain anchoring)
- [ ] Верифікувати end-to-end flow: мертве дерево → `MaintenanceRecord` → passport → on-chain

#### S3.5 — Subgraph contract address
- **P2** | `05_03` | Блокує deploy subgraph
- [ ] ⚠️ Замінити placeholder `0x0000...0000` на реальну адресу SFC контракту у `subgraph.yaml`

#### INF.2 — Docker image registry для Akash providers
- **P2** | `06_02` | Akash провайдери не мають доступу до GCP Artifact Registry
- [ ] Mirror image до Docker Hub або GHCR (public або з token)
- [ ] Оновити SDL image reference
- [ ] CI workflow для автоматичного mirror

#### INF.3 — TLS termination
- **P2** | `06_02` | Port 443 додано в SDL, TLS потрібно налаштувати
- [ ] Налаштувати TLS (Akash ingress `*.ingress.akash.pub` або Cloudflare)

#### S4.3 — Akash SDL secrets
- **P3** | `06_02` | `REQUIRED_SECRET_NOT_SET` для критичних змінних
- [ ] Заповнити в `deploy/akash/deploy.yaml`
- [ ] Верифікувати startup

#### S4.5 — Multi-replica sticky sessions
- **P3** | `06_02` | Потрібно при >1 репліці
- [ ] Визначити load balancing strategy
- [ ] Реалізувати sticky sessions або shared ActionCable adapter

---

## 🔧 Firmware

### 🔴 P0 — Критичні

#### FW.1 — Hardcoded AES-256 Key
- `03_01`, `03_02`, `03_05`, `05_02` | `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:81-82`
- **Опис:** Один ключ на ВСІХ вузлах. Злам одного пристрою = компрометація всієї мережі
- [ ] Дизайн HKDF key derivation protocol
- [ ] Backend: provisioning endpoint (POST `/api/v1/provisioning/register` вже існує)
- [ ] Firmware: змінити key storage з hardcoded → Flash-based
- [ ] Firmware: RDP Level 2 activation як final step
- [ ] End-to-end тест provisioning flow

#### FW.2 — AES-256-ECB без MAC/MIC
- `03_05` | `firmware/soldier/main.c:747`, `firmware/queen/main.c:781`
- **Опис:** Детерміністичний шифротекст, replay/bit-flip attacks можливі
- **Рішення:** AES-256-CCM (апаратна підтримка STM32WLE5JC) з 24-байтним пакетом
- [ ] Верифікувати `CRYP_AES_CCM` підтримку на цільовій ревізії STM32WLE5JC
- [ ] Дизайн 24-байтного пакету (8 байт sensor data vs поточних 16)
- [ ] Firmware Soldier: CCM encrypt + Frame Counter інкремент + MIC append
- [ ] Firmware Queen: CCM decrypt + Frame Counter validation (anti-replay)
- [ ] Backend: оновити `TelemetryUnpackerService` для 24-байтного формату
- [ ] LoRa airtime budget verification (24B vs 16B при SF10/DR2)
- [ ] Тести

#### FW.3 — Queen AT Command Blocking (~25 сек)
- `03_01`, `03_02`
- **Опис:** Queen "сліпа" до LoRa пакетів під час CoAP flush. Пакети втрачаються
- [ ] Переписати `Flush_Cache_To_Rails()` на UART DMA
- [ ] Замінити single-packet buffer на ring buffer
- [ ] Додати CoAP response parsing (замість blind HAL_Delay)
- [ ] Тести

#### FW.4 — TinyML `Run_Inference()` закоментований
- `03_03` | `main.c:355`, `silken_net_audio_model.h` відсутній
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
- [ ] Архітектурне рішення: прийняти "snapshot" модель АБО змінити firmware inputs
- [ ] Задокументувати рішення в `03_04`
- [ ] Реалізувати (якщо зміна)

#### FW.6 — Lorenz State persistence
- `03_04` | Стан (x,y,z) не зберігається між STOP2 циклами
- [ ] Зберегти (x,y,z) у RTC DR0-DR5 (3 × float → 3 × uint32_t)
- [ ] Відновити при wakeup
- [ ] Тести

#### FW.7 — Float vs BigDecimal divergence
- `05_02` | firmware Float64 vs backend BigDecimal
- [ ] Рішення: tolerance band АБО integer math
- [ ] Задокументувати в `05_02` та `03_04`
- [ ] Якщо tolerance — додати check у `SilkenNet::Attractor`

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- `05_02` | firmware: global 2.0/45.0 vs backend: per-species через `TreeFamily`
- [ ] Додати thresholds до OTA config payload
- [ ] Firmware: зберігати thresholds у Flash/RTC
- [ ] Backend: включити thresholds у OTA bytecode

#### FW.9 — CoAP retry logic
- `03_02` | ACK miss → весь кеш втрачається
- [ ] Парсинг UART RX для `OK`/`ERROR` відповіді модему
- [ ] Double-buffering або persistent buffer для retry
- [ ] Configurable retry count

#### FW.10 — Temperature-based TX deferral
- `02_04` | При T < -15°C ESR іоністора зростає
- [ ] Додати check: `temp < -15` && `vcap_voltage < 4.0V` → відкласти TX
- [ ] Тести

### 🟢 P2 — Низькопріоритетні

#### FW.11 — Race condition: `vibration_detected`
- `03_03` | ISR vs main loop атомарність
- [ ] NVIC-рівнева ізоляція: `HAL_NVIC_DisableIRQ(EXTI0_IRQn)`
- [ ] Fallback: `__disable_irq()` / `__enable_irq()`
- [ ] Тести

#### FW.15 — Missing test suites: TinyML, Crypto
- `03_03` | `test_bio_contract.c` ✅ done (27 тестів), залишились:
- [ ] `test_tinyml_pipeline.c` — mock Run_Inference(), 4 класи × confidence boundary
- [ ] `test_encryption.c` — ECB/CBC switching, ECB restore, key verification

#### FW.16 — ECB restore race condition
- `03_05` BLOCKER-6 | `HAL_CRYP_Init()` без timeout
- [ ] Return-code check на `HAL_CRYP_Init()` при ECB restore
- [ ] RCC CRYP_FORCE_RESET як hard recovery path
- [ ] Verify `hcryp.State` перед кожним Encrypt/Decrypt
- [ ] ECB restore навіть на error path

#### FW.17 — Key rotation mechanism (Hash Ratchet KDF)
- `03_05` BLOCKER-5 | Після FW.1
- [ ] Дизайн Hash Ratchet протоколу (AES-based KDF on STM32)
- [ ] CMD:ROTATE_KEY CoAP command + OTA relay
- [ ] Cluster-wide activation confirmation
- [ ] Зберігання `K_current` та `rotation_counter`

#### FW.18 — Hardcoded confidence threshold 0.80
- `03_03` BLOCKER-6
- [ ] Threshold у RTC Backup Register (updateable via OTA)
- [ ] Dual-threshold: WARNING (0.60) → counter; CRITICAL (0.85) → Emergency TX

#### FW.19 — Float32 vs Float64 mruby compile flags
- `03_04` BLOCKER-4
- [ ] Верифікувати mruby compile flags (`MRB_USE_FLOAT`)
- [ ] Tolerance band у `TelemetryUnpackerService` (±2.0 на Z)
- [ ] Задокументувати результат

#### FW.20 — LoRa Time Sync (clock drift compensation)
- Legacy notes | P2 (критичний для TRL 7+)
- [ ] Queen: time correction у CoAP ACK або downlink command
- [ ] Soldier: прийняти та застосувати RTC correction
- [ ] Backend: server UTC timestamp у downlink payload
- [ ] Тести drift compensation при ΔT = ±60°C

#### FW.21 — Edge data aggregation (RAM-aware Soldier)
- Legacy + `08_02` | P2, потребує R&D
- [ ] Визначити які метрики потребують EMA
- [ ] Lightweight EMA на Soldier (O(1) memory)
- [ ] Інтегрувати з Kalman filter design (E.10)
- [ ] Верифікувати RAM footprint < 80%

---

## 🧪 Hardware / Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

#### HW.1 — nTop model → DMLS factory (`01_01`)
- [ ] Генерація TPMS gyroid geometry (65% porosity)
- [ ] STL/STEP файл → DMLS завод
- [ ] SEM criteria для приймання партії

#### HW.2 — Dual-scale roughness spec (`01_02`)
- Блокує: Максимальний струм EBFC, TRL 5
- [ ] Factory spec з метриками (Sa 0.5-5 µm, Sv 50-500 nm)
- [ ] Передати на завод
- [ ] SEM images ×500/×5,000/×50,000

#### HW.3 — Accelerated aging test Arrhenius (`01_02`)
- Блокує: Seed раунд, whitepaper, TRL 5→6
- [ ] Синтез штучного ксилемного соку
- [ ] 12-тижневий тест
- [ ] ICP-MS аналіз: Ti < 0.1 µg/cm², V < 0.02 µg/cm²
- [ ] EIS degradation < 50%

#### HW.4 — Self-healing coating (`01_02`)
- Блокує: 20+ років longevity, TRL 6
- [ ] Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] Інтеграція в PEO electrolyte або layer-by-layer
- [ ] Тест: 10× вищий Rct

#### HW.5 — Enzyme lifespan (`01_03`)
- Gen 1.0: 3-5 років (Chitosan + Nafion), Gen 2.0: 20-25 років (FAD-GDH + ZIF)
- [ ] Protective polymer matrix
- [ ] Тест Chitosan-шару, Nafion-покриття, комбінації
- [ ] Тест: 3-5 років (Gen 1.0)
- [ ] Gen 2.0: FAD-GDH, Laccase/nanozymes, ZIF-інкапсуляція

#### HW.6 — Resin barrier (`01_04`)
- [ ] 30° installation angle verification
- [ ] Hydrophilic coating / PEG / gradient test
- [ ] Thermal installation test (150-200°C)
- [ ] FEM-моделювання теплового поля

#### HW.7 — BQ25570 resistors verification (`02_03`)
- Блокує: PCBA production
- [ ] Виміряти 8 резисторів
- [ ] Порівняти з таблицею
- [ ] Замінити SMD якщо мисматч

#### HW.8 — Pogo pin specification (`02_02`, 5 блокерів)
- [ ] Матеріал напилення (Gold Au 0.76 µm)
- [ ] Сила пружини (~100 г/пін)
- [ ] Механізм фіксації (bayonet)
- [ ] O-ring (EPDM)
- [ ] Допуски соосності (Lead-in chamfer)

#### HW.9 — PCB KiCad layouts (`02_01`)
- [ ] Soldier PCB layout
- [ ] Queen PCB layout
- [ ] RF Keep-Out Zone verification

#### HW.10 — Modem discrepancy SIM7000G vs SIM7070G (`02_05`)
- Рішення: SIM7070G
- [ ] Фізично перевірити маркування на прототипі
- [ ] Узгодити Wiki, BOM та firmware
- [ ] AT+CPSMS та AT+CEDRXS команди у firmware Queen

#### HW.11 — Potting material selection (`02_01`)
- Блокує: Hardware freeze, IP67
- [ ] Обрати compound (Sylgard 184)
- [ ] Верифікувати при -20°C / +60°C

#### HW.12 — EBFC >5.5V protection (`02_01`)
- Блокує: Hardware safety, TRL 5
- [ ] Верифікувати BQ25570 OV threshold
- [ ] TVS-діод або зенерівський обмежувач

#### HW.13 — MPPT coefficient verification (`02_03`)
- Блокує: Max EBFC power
- [ ] P-V крива EBFC
- [ ] VOC та VMP при різному освітленні
- [ ] Оптимальна фракція (65%)
- [ ] Замінити ROC1/ROC2 якщо потрібно

#### HW.14 — Winter energy deficit Queen Phase 3 (`02_05`)
- Phase 3 only
- [ ] Збільшити батарею або зменшити duty cycle або 100W panel
- [ ] Оновити Unit Economics (07_02)

#### HW.15 — BMS not specified for Queen (`02_05`)
- [ ] BMS: 12V / 20A continuous / 50A peak
- [ ] MPPT: Victron SmartSolar 75/15
- [ ] Оновити BOM

#### HW.16 — Thermal management в IP67 (`02_05`)
- [ ] Thermal budget для enclosure
- [ ] Temperature sensor (NTC/DS18B20)
- [ ] Hardware charge protection при T < 0°C

#### HW.17 — PEEK radome prototype Деталь 4 (`02_01`)
- Блокує: RF performance, Zero-Touch Assembly
- [ ] KiCad → PEEK radome dimensions
- [ ] Тип кріплення (різьба vs байонет)
- [ ] Матеріал O-ring (EPDM vs FKM)
- [ ] Замовити PEEK прототип
- [ ] RF performance (VSWR)

#### HW.18 — Starlink DTC WiFi co-processor (`02_05`)
- Phase 3 only
- [ ] Архітектурне рішення ESP32-S3 vs SIM8200G-M2
- [ ] Оновити 03_02
- [ ] Co-processor firmware

#### HW.19 — VOC-діагностика деградації конденсатора (`02_04`)
- TRL 8+
- [ ] Валідувати на 12-біт ADC
- [ ] ADS1220 + TPS22860 якщо 12-біт недостатньо
- [ ] Backend: `voc_mv` у TelemetryLog

#### HW.20 — Buffer Cap MLCC part number (`02_03`)
- [ ] Part number: 100µF/6.3V X5R 1210 (Murata GRM32ER60J107ME20)
- [ ] DC bias derating (~80µF ефективна)
- [ ] Додати до KiCad BOM (HW.9)

---

## 🔐 Безпека

#### SEC.1 — Multisig Gnosis Safe (`05_03`)
- Before mainnet deploy
- [ ] Створити Gnosis Safe wallet
- [ ] Reassign DEFAULT_ADMIN_ROLE у SCC та SFC

#### SEC.2 — RDP Level 2 activation (`03_05`)
- [ ] Верифікувати OTA flow end-to-end
- [ ] RDP Level 1 для field batch
- [ ] Процедура Level 2 activation (необоротна)

#### SEC.3 — Factory Flashing pipeline (`03_05`)
- Блокує: Mass production
- [ ] Реалізація Factory Flashing tool
- [ ] Integration тест з provisioning API

#### SEC.4 — Reed Switch shipping mode (`03_05`)
- [ ] Hamlin 59140-1-T-00-A + N52 magnet до BOM
- [ ] KiCad schematic

---

## 📋 Юридичні / Бізнес

#### BIZ.1 — 1 SCC = ? kg CO₂ (`07_01`)
- ЮРИДИЧНИЙ БЛОКЕР: Carbon credit marketplace
- [ ] Методологія розрахунку
- [ ] Додати в код
- [ ] Задокументувати для registries

#### BIZ.2 — B2B MSA (`07_01`)
- [ ] Юридичний шаблон
- [ ] Review з юристом

#### BIZ.3 — B2C ToS / Privacy Policy (`07_01`)
- [ ] Terms of Service
- [ ] Privacy Policy (GDPR)
- [ ] Cookie Policy

#### BIZ.4 — DAO Governance Process (`07_01`, `05_03`)
- Post-TRL 6
- [ ] GovernorContract.sol
- [ ] ProtocolParameters.sol
- [ ] Governance::ParameterSyncWorker

#### BIZ.5 — Patent application (`08_03`)
- [ ] Engagement з патентним адвокатом
- [ ] Патентна заявка на дизайн анкера

---

## 🎓 Академічні блокери (ЧНУ)

#### UNI.1 — Перший контакт з деканом Онищенком (`08_01`)
- Блокує: Всю лабораторну роботу, 10 публікацій, 11 магістерських
- [ ] Призначити зустріч
- [ ] Підготувати презентацію
- [ ] Провести зустріч

#### UNI.2 — 8 зустрічей з факультетом ФОТІУС (`08_02`)
- [ ] Супруненко — PN-verification, Convolution Method
- [ ] Онищенко — stochastic B&B, Petri nets
- [ ] Ярмілко — Embedded Systems, ECDH
- [ ] Порублів — Discrete Math, reliability
- [ ] Косенук — RF/FEC/compliance
- [ ] Бушин — CNN/BSP/DMLS physics
- [ ] Осауленко — Portfolio management
- [ ] Любченко — GA/Neural Networks

#### UNI.3 — IP договір з ЧНУ (`08_03`)
- Блокує: Старт публікацій
- [ ] Юридичне оформлення IP-договору
- [ ] Підпис обома сторонами

---

## 💡 Додаткові знахідки (не блокери)

| # | Знахідка | Джерело | Примітка |
|---|----------|---------|----------|
| E.1 | SFC voting power зберігається після slashing | `07_01` | Дослідити |
| E.3 | Breadboard video відсутнє (для грантів) | `07_03` | Зняти відео |
| E.4 | Helium Network fallback | `02_05` | Дизайн + реалізація |
| E.5 | CoAP listener Ruby — до ~10k вузлів | `06_01` | Series D: Rust/Go proxy |
| E.7 | dClimate mock mode → real API | `05_01` | Пов'язано з S3.2 |
| E.8 | SNR unused у Queen CIFO eviction | `03_02` | Low priority |
| E.9 | DMA SPI optimization (Ярмілко) | `08_02` | R&D partnership |
| E.10 | Kalman/EMA delta_t filtering | `08_02` | R&D partnership |
| E.11 | CE/FCC/EMC/IP68 certification | `08_02` | Потребує Косенук |
| E.12 | Boolean minimization TX (Карно/Quine-McCluskey) | `08_02` | Потребує Любченко |
| E.13 | Petri Net model Rails (deadlock-free 10k IoT) | `08_02` | Потребує Супруненко |
| E.14 | Multi-source satellite fusion (Sentinel-2 NDVI) | `08_02` | Потребує Любченко + Бушин |
| E.15 | Reed-Solomon FEC LoRa | `08_02` | Потребує Косенук |
| E.18 | 10 Q1 публікацій | `08_03` | Blocked by UNI.1-3 |
| E.19 | 8 магістерських | `08_03` | Post-TRL 4 |
| E.20 | Forester Guild (Proof-of-Physical-Work) | `04_02` | Post-TRL 6 |
| E.26 | `health_trend` field TelemetryLog | Legacy | Post-TRL 6, потребує E.10 |
| E.27 | Chaos Engineering Akash/Kamal | Legacy | Post-TRL 7 |
| E.28 | Kamal deploy hooks idempotency | `06_01` | Верифікувати |
| E.29 | Альтернативні EBFC медіатори (ferrocene, MB) | `01_03` | R&D alternatives |
| E.30 | InsightGenerator: per-region baselines | `04_02` | Post-TRL 7 |
| E.31 | TinyML OTA `.tflite` format | `03_03` | Post-TRL 8 |
| E.32 | Smart Contract Audit (Slither/Mythril) | `05_03` | Pre-Mainnet |
| E.33 | AlertNotification rate limits (FCM/Twilio) | `04_02` | Post-TRL 8 |
| E.34 | dClimate fallback → ForestBountyService | `04_02` | Post-TRL 6 |
| E.35 | Flash Loan defense GovernorContract.sol | `05_03` | Post-TRL 6 |
| E.36 | PostGIS Generated Column (geo_boundary) | `04_01` | Post-TRL 8 |
| E.37 | TimescaleDB для telemetry_logs | `04_01` | >100M рядків/місяць |
| E.38 | Press-Fit фаски R≥0.2мм | `01_01` | Включити у nTop (HW.1) |
| E.39 | EBFC Gen 2.0 enzyme R&D (FAD-GDH + ZIF) | `01_03` | ЧНУ lab testing |
| E.40 | Ignion Virtual Antenna™ evaluation | `02_01` | Evaluation kit + VSWR тест |
| DIFF.1 | `Wallet#lock_and_mint!` threshold = runtime param | `04_02` | Informational, no action |
| DIFF.7 | SNR unused in Queen CIFO eviction | `03_02` | Low priority optimization |

---

## 🏛️ Архітектурні пропозиції (довгострокові)

| ID | Пропозиція | Джерело | Milestone |
|----|-----------|---------|-----------|
| ARCH.1 | Fractal topology: L2 Sergeant nodes | `00_01` | Post-TRL 7 |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka | `00_01`, `06_01` | Series D |
| ARCH.4 | Governance DAO (SFC voting) | `05_03` | Post-TRL 6 |
| ARCH.5 | Cross-Registry Export (Verra, Gold Standard) | `04_02` | Post-TRL 7 |
| ARCH.6 | Federated Learning auto-retraining | `04_02` | Post-TRL 7 |

---

## 📊 TRL Матриця

| Модуль | TRL | Цільовий | Головний блокер |
|--------|-----|----------|-----------------|
| 00 System Architecture | 4 | 9 | Module 01 chemistry |
| 01 Materials & EBFC | 3 | 6 | Lab tests (ЧНУ) |
| 02 Hardware & BOM | 4 | 6 | BQ25570, PCB, Pogo, PEEK |
| 03 Firmware | 6 | 8 | AES key, TinyML, AT blocking |
| 04 Backend Rails | 8 | 9 | RSpec тести |
| 05 Web3 Pipeline | 8-9 | 9 | PuroEarth API, SFC address |
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
| 2026-04-19 | Сесія 10: Очищення трекера — видалено виконані задачі (задокументовані в основних docs), прибрано sprint-групування. |
