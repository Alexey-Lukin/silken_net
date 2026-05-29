# 00_08: Action Plan Tracker (Залишок робіт)

## 🎯 Мета

Зберігати ТІЛЬКИ незавершені задачі з пріоритетами, виконавцями та статусами. Виконана робота задокументована у відповідних docs (`00_00` → `08_07`). Повністю завершені пункти виносяться у **§🗄️ Архів закритих пунктів** (вказівник ID→канон, внизу). Документ є живим операційним інструментом — оновлюється при кожному завершенні задачі.

---

> **Розмітка виконавців:**
> - 🤖 **Код/аналіз** — Copilot може виконати самостійно (код, firmware, розрахунок, документ, тест)
> - 👤 **Операційна** — потрібен власник (hardware, зовнішні UI/дашборди, секрети, зустрічі, юрист, фізична лабораторія)
> - 🔗 **Заблоковано** — чекає іншої задачі або рішення

---

## 🚨 Top-Critical Path (рекомендований порядок виконання)

> Виведено окремо, щоб видно «що варто робити прямо зараз». Це **не нові задачі**, а індекс уже існуючих пунктів, які блокують найбільше іншого.

### Перед будь-яким польовим деплоєм (life-safety + security)
1. **SEC.9** — замінити master AES key (FIPS-197 test vector) на криптостійкий random — **P0**
2. **FW.1 + SEC.3** — Per-device HKDF provisioning ✅ + Factory Flashing pipeline tool ✅ (Rake CLI dry-run, 2026-05-24); 👤 залишається real `STM32_Programmer_CLI` execution на STM32WLE5JC bench — **P0**
3. **FW.2** — AES-128-CCM [post-ARCH.42] (вирішує одразу: ECB→CCM, MIC, FW.23 OTA auth, SEC.10 panic auth, FW.29 disambiguation) — **P0**
4. **SEC.1** — Gnosis Safe multisig для `DEFAULT_ADMIN_ROLE` SCC/SFC до mainnet — **P0**

### Перед production-запуском Web3 mintingу
5. **S1.1** — заповнити GitHub Secrets (`DATABASE_PASSWORD`, `GCP_SA_KEY`, `SSH_PRIVATE_KEY`, ...) — **P0**
6. **E.45 / S3.5** — підставити реальну адресу SCC/SFC у `subgraph.yaml` — **P0**
7. **E.47** — встановити `SOLANA_RPC_URL` mainnet (інакше Devnet за замовчуванням) — **P0**
8. **INF.4 + INF.6** — TLS termination + CoAP Proxy verification на Akash ingress — **P1**

### Парк аналітики/спостережуваності перед першим Akash deploy
9. **S2.1 + S2.2 + S2.3** — Grafana Cloud dashboards & alerts після першого `/metrics` пуш — **P0** (ops)

### Лабораторно-критичний шлях (TRL 4→6 hardware)
10. **HW.24** — Staged validation gate (SLA → Ti-coin → full anchor) — **P0** (блокує замовлення 100 шт. DMLS до проходження попередніх етапів)
11. **HW.23** — HIP postprocess specification for SLM anode — **P0** (блокує перший SLM-замовлення)
12. **HW.22** — Sterilization protocol (no EtO) — **P1** (блокує перехід до Stage 4 польових тестів)
13. **HW.7** — BQ25570 VBAT_OV резистори: виміряти і замінити SMD якщо мисматч — **P1** (блокує PCBA freeze)
14. **HW.13 / ARCH.29-MPPT** — P-V крива EBFC + перейти з 50% VOC на 65% — **P1**
15. **HW.3** — 12-тижневий Arrhenius accelerated aging тест (синтетичний ксилемний сік) — **P1** (блокує seed)
16. **HW.25** — PTFE-GDL membrane для катода (Zone 3) — **P1** (блокує EBFC у новій тризонній архітектурі)

### Академічний critical path
17. **UNI.1** — Перша зустріч з деканом Онищенком (ChNU FOTIUS) — **P0** (блокує всі публікації Q1)
18. **UNI.8** — Перший контакт з ректоратом СЄУ — **P0** (блокує MSA / B2B legal)
19. **UNI.13 / UNI.14** — Верифікувати посади науковців ЧМА і СЄУ через офіційні сайти — **P0**

---

## 🛣️ Software / Backend / DevOps

> **Складність:** XS < 1 год · S = 1–4 год · M = 4–8 год · L = 1–3 дні

#### SLASH-1 — Slashing cause_classification gate (financial-safety) 🔴
- **P0** | `00_01 §6.2/§6.5` | **Складність: M** | 🤖+👤 (DAO/founder-go: незворотна фінансова логіка)
- **Опис:** `00_01 §6.2` обіцяє, що `BlockchainBurningService` перевіряє `cause_classification` перед `slash()`, плюс penalty-формулу `damage_ratio^1.3 × min(penalty_factor,2.0)`. **Код цього не має взагалі** (grep `cause_classification` → 0): `ContractHealthCheckService#perform` слешить на `daily_insights.empty?` (коментар «Starlink-блекаут») і `stress_index>=0.83` → `BurnCarbonTokensWorker` → `BlockchainBurningService` палить лінійно `total_minted × damage_ratio`. Наслідок: **force-majeure comms-loss (вкрадений/збитий шлюз, Starlink-блекаут) = незворотний burn інвесторських токенів, класифікований як ніщо.** Divergence: [`04_02 §11` 2026-05-29](04_02_Business_Logic_and_Services).
- [x] 🤖 ✅ (2026-05-29) **Blackout → Field Audit, НЕ burn:** `ContractHealthCheckService#flag_data_blackout!` — cluster-wide `daily_insights.empty?` → `system_fault` EwsAlert + контракт лишається `:active` (без `BurnCarbonTokensWorker`). 10 specs green, rubocop clean, GitNexus impact LOW. Лишається: B/insurance auto-route + going-dark-after-P0→A refinement (`00_01 §6.5`).
- [ ] 🤖 De-correlate penalty signals: no-ack (+0.5) + Streamr-gap (+0.25) мають спільний root-cause — не складати при недоступності шлюзу.
- [ ] 🤖 Реалізувати penalty-формулу §6.2 (`damage_ratio^GAMMA × min(penalty_factor, 2.0)`) у `BlockchainBurningService` (зараз лінійно).
- [ ] 👤 DAO/founder-confirm перед mainnet (тісно з BIZ.13 operator-bond, `00_01 §6.2.1`).

#### S1.1 — GitHub Secrets заповнення
- **P0** | `06_01` | **Складність: XS** | **🔧 Операційна** — ручне заповнення в GitHub UI, без коду
- **Опис:** 12 критичних секретів не встановлені: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `DATABASE_URL`, `SSH_PRIVATE_KEY`, тощо. Блокує весь CI/CD pipeline.
- ✅ Зроблено: checklist + інвентаризація 4 місць зберігання секретів. Канон: `06_04_Secrets_Checklist`.
- [ ] 👤 Заповнити GitHub repository secrets
- [ ] 👤 Верифікувати CI pipeline проходить

#### S1.5 — Kamal IP placeholders
- **P2** | `06_01` | **Складність: XS** | **🔧 Операційна** — підстановка IP після `terraform apply`
- **Опис:** `192.168.0.1` та `<CANOPY_SERVER_IP>` — плейсхолдери в Kamal config
- [ ] 👤 Підставити реальні IP після `terraform apply`
- [ ] 👤 Верифікувати Kamal deploy з реальними IP

#### S2.1 — Верифікація метрик після deploy
- **P0** | `06_03` | **Складність: XS** | **🔧 Операційна** — верифікація після першого Akash deploy, без коду
- **Опис:** `/metrics` endpoint працює (10+ метрик), скрейпиться Grafana Alloy sidecar → Grafana Cloud. Інфраструктура налаштована (prometheus.rb, middleware, Alloy sidecar, Terraform vars). Потрібна верифікація після першого Akash deploy
- [ ] 👤 Верифікувати що метрики збираються (після першого Akash deploy)

#### S2.2 — Grafana Cloud dashboards
- **P0** | `06_03` | **Складність: S** | **🔧 Операційна** — налаштування в Grafana Cloud UI, без коду
- **Опис:** Grafana Cloud SaaS — метрики доступні, дашборди створюються в UI
- ✅ Зроблено: dashboard IaC (5 секцій, 15 панелів) → `deploy/grafana/dashboards/silkennet-overview.json` (інструкції `deploy/grafana/README.md`).
- [ ] 👤 Імпортувати dashboard у Grafana Cloud (UI або API — інструкції у `deploy/grafana/README.md`)

#### S2.3 — Grafana Cloud alerting rules
- **P0** | `06_03` | **Складність: S** | **🔧 Операційна** — налаштування в Grafana Cloud UI, без коду
- **Опис:** Grafana Cloud Alerting замінює потребу в self-hosted Alertmanager
- ✅ Зроблено: 12 alert rules IaC (4 P0 / 5 P1 / 3 P2) → `deploy/grafana/alerts/silkennet-alerts.yaml`; backend counter `silkennet_telemetry_acoustic_overflow_total` у `TelemetryUnpackerService`.
- [ ] 👤 Замінити `${DATASOURCE_UID}` на реальний UID і застосувати через API або Grafana UI
- [ ] 👤 Налаштувати notification channel (Slack / Email / PagerDuty) — інструкції у README

#### S3.2 — dClimate Real API verification
- **P1** | `05_01` | **Складність: S** | **🔧 Операційна** - отримати та встановити API key, сервіс реалізований, потрібна staging верифікація
- **Опис:** `Dclimate::VerificationService` реалізований з реальним API (NASA FIRMS через dClimate). Fire detection (FRP ≥ 10 MW, confidence ≥ 50%), cloud obscuration fallback, metadata extraction — все працює. Потрібна верифікація з реальним ключем
- [ ] 👤 Верифікувати з реальним API ключем в staging (отримати та встановити API key)
- [ ] 👤 End-to-end тест з `DclimateVerificationWorker`

#### S3.5 — Subgraph contract address
- **P2** | `05_03` | **Складність: XS** | **🔧 Операційна** — замінити placeholder після deploy контракту
- **Опис:** SFC events (ForestMinted, GovernanceSlashed) додано до subgraph. Задокументовано в `05_03` розділ Subgraph. Але contract address — placeholder. Блокує deploy subgraph.
- [ ] 👤 ⚠️ Замінити placeholder `0x0000...0000` на реальну адресу SFC контракту у `subgraph.yaml`

#### INF.3 — TLS termination
- **P2** | `06_02` BLOCKER-5 | **Складність: S** | **🔧 Операційна** — конфігурація Cloudflare або Akash ingress, без коду в Rails
- **Опис:** SDL відкриває HTTP (port 80), CoAP UDP (5683), та port 443 (додано Сесія 6). Але TLS termination не налаштовано. Browsers block WebSocket from HTTPS → HTTP
- [ ] 👤 Налаштувати TLS (Akash ingress `*.ingress.akash.pub` або Cloudflare)

#### INF.6 — CoAP UDP smoke test через Ingress Anchor (post-deploy gate)
- **P1** | `06_01` §6 рядок 113, `06_02` runbook, `00_03` §🛑 | **Складність: XS** | **🤖 Код + 👤 верифікація**
- **Опис:** Без end-to-end UDP smoke перевірки `Queen → Ingress Anchor (HAProxy/socat) → Akash → CoAP daemon` silent UDP failure не помітний з HTTP-only health checks — це блокер для будь-якої uplink-resilience політики у [`00_03 §1.2 L1`](00_03_Resilience_and_Failover_Policy). **Що зроблено:** workflow `.github/workflows/coap_smoke.yml` (`workflow_dispatch` для ad-hoc + `workflow_call` від `deploy.yml` як post-deploy gate); приймає inputs `host`/`port`/`path`/`timeout_seconds`. **Що залишається:** активувати як required post-deploy gate у `deploy.yml`, виконати перший boundary-test з реальної Queen Soldier-симулятором (`bin/forest_simulator`).
- ✅ Зроблено: workflow `coap_smoke.yml` (`workflow_call` від `deploy.yml`). 🟡 ще не required gate у `deploy.yml`.
- [ ] 👤 Активувати як required post-deploy gate (set `coap-smoke` як `needs:` у production job після першого зеленого прогону)
- [ ] 👤 Перший boundary smoke з реальної Queen або `bin/forest_simulator`

#### INF.4 — Akash TLS strategy decision: hostname operator vs Cloudflare
- **P1** | `06_02` BLOCKER-5, `06_01` | **Складність: S** | **🔧 Операційна + Док**
- **Опис:** Розширення INF.3. Не прийнято архітектурне рішення: (a) Akash hostname operator + Let's Encrypt автоматизація, (b) Cloudflare Proxy перед Akash (DDoS + WAF, але ще одна mw залежність), (c) Traefik у Kamal (тільки GCP path). Вибір впливає на CoAP UDP (Cloudflare НЕ proxies UDP — потребує separate Spectrum або direct ingress)
- ✅ Зроблено (док): runbook TLS termination — Опція A (Cloudflare HTTPS + direct UDP CoAP) рекоменд. + pre-flight checklist + verification commands + failure modes + fallback Опція B. Канон: `06_02` BLOCKER-5.
- [ ] 👤 Прийняти архітектурне рішення (Cloudflare Proxy для HTTPS + direct UDP для CoAP — рекомендовано)
- [ ] 🤖 Якщо Akash hostname — додати automation у `terraform/`

#### S4.3 — Akash SDL secrets
- **P3** | `06_02` | **Складність: XS** | **🔧 Операційна** — заповнити 4 змінні у `deploy.yaml`
- **Опис:** `REQUIRED_SECRET_NOT_SET` для 4 критичних змінних
- [ ] 👤 Заповнити в `deploy/akash/deploy.yaml`
- [ ] 👤 Верифікувати startup

#### S5.2 — RELEASE_VERSION ENV для Sentry
- **P2** | `06_03` | **Складність: XS** | **🔧 Операційна**
- **Опис:** `RELEASE_VERSION` ENV не встановлено — Sentry release tracking не працює. Потрібно додати у Kamal/Akash deploy config
- ✅ Зроблено: `RELEASE_VERSION` у `deploy.yml` / `deploy-production.yml` / `config/deploy.yml` / `deploy/akash/deploy.yaml`.
- [ ] 👤 Верифікувати Sentry release tracking

#### S5.6 — GCS bucket для Terraform state (chicken-and-egg)
- **P3** | `06_02` BLOCKER-6 | **Складність: XS** | **🔧 Операційна**
- **Опис:** GCS bucket для remote Terraform state має бути створений вручну перед `terraform init`. Документація є, але checklist відсутній
- [ ] 👤 Створити GCS bucket вручну (`gsutil mb`)
- [ ] 👤 Верифікувати `terraform init` проходить

#### S6.1 — Redis SPOF для M2M автентифікації
- **P1** | `04_03` | **Складність: M** | **Код**
- **Опис:** Redis = single point of failure для Gateway M2M auth. Redis down → всі шлюзи заблоковані (503). Відсутній fallback
- **Варіанти fallback:** (a) DB-backed nonce validation з TTL index (performance overhead, але survives restarts), (b) Upstash Redis Cluster (managed HA, рекомендовано для production), (c) Memcached cluster (не зберігає стан між restarts). **Рекомендація:** Upstash Redis вже використовується — переконатись що включений multi-zone replication
- ✅ Зроблено: graceful degradation (Redis down → DB-backed nonce lookup, TTL 10 хв) + тести. Канон: `04_03` (M2M nonce fallback [S6.1]).
- [ ] 👤 Верифікувати Upstash multi-zone replication у production

#### S6.10 — MaintenanceRecord — лише лог
- **P3** | `04_02` | **Складність: L** | **Архітектурна**
- **Опис:** MaintenanceRecord — лише запис логу. Немає: призначення задач, оплати, верифікації. Потребує Forester Guild (E.20)
- ✅ Зроблено: архітектурний дизайн task-assignment (bounty fields, candidate filtering, composite scoring, notification cascade, race resolution `FOR UPDATE NOWAIT`, GPS/EXIF/IPFS verification → USDC payout, anti-Sybil). Канон: `04_02` §Forester Guild.
- [ ] 🔗 Зв'язати з Forester Guild PoPhW (E.20)

#### S6.14 — peaq_signing_key: відсутня rotation policy
- **P2** | `04_02` §4.2.2 (GeneratePeaqDidService, BLOCKER-08) | **Складність: M** | **🤖 Архітектура + Док**
- **Опис:** `peaq_signing_key` — обов'язковий (W3C DID compliance), raise `RegistrationError` при відсутності. Але немає процесу для: (1) ротації ключа без зламу існуючих DID, (2) emergency revocation при компрометації, (3) синхронізації між staging/production
- ✅ Зроблено: key rotation policy (dual-key 72h overlap, rotation/90 днів) → `04_02 §S6.14`; emergency revocation runbook (5-step) → `06_04 §5.4`.
- [ ] 👤 Vault-store production peaq_signing_key (Bitwarden/1Password)

#### S6.18 — Rails web security hardening (maquina-app/rails-claude-code §8 audit)
- **P1** | `06_01`, `06_02`, `06_04` | **Складність: M** | **🤖 Код + Конфігурація**
- **Опис:** Повний security audit Rails-шару по категоріях: PROD (SSL/HSTS), CSRF, HDR (Security Headers), CSP, SESS (Session cookie), RATE, AUTH, GEM (brakeman/bundler-audit), CI, DATA, FWKD.
- ✅ Зроблено: `production.rb` (force_ssl/assume_ssl/HSTS/config.hosts boot-warning), CSP initializer (jspm/unpkg/cartocdn/transparenttextures, report-only), `security_headers.rb` (X-Frame DENY/COOP/CORP/Permissions-Policy), `session_store.rb` (secure/httponly/same_site/14d) + нові ENV. Без змін (вже ок): CSRF/RATE/AUTH/GEM/CI/DATA/FWKD. Канон: `06_04 §2.1` (+ `06_01`/`06_02`).
- [ ] 👤 Встановити `RAILS_ALLOWED_HOSTS=api.silkennet.com,.silkennet.com` у Kamal `env.clear` / Akash SDL **перед першим production деплоєм**
- [ ] 👤 Після 1–2 тижнів спостережень CSP violation-репортів — встановити `CSP_ENFORCE=true` (переведення CSP з report-only у enforced)

#### PUMA-IPV6-1 — Верифікація IPv6 bind після першого Kamal-деплою
- **High** | `06_05` | **Складність: XS** | **🔧 Операційна** — верифікація після першого реального деплою, без коду
- **Опис:** Puma 8.0+ за замовчуванням bind'иться на `tcp://[::]:3000` (dual-stack) якщо є non-loopback IPv6 інтерфейс. Thruster конектиться до Puma по `127.0.0.1:3000`. Linux `IPV6_V6ONLY=0` = `[::]:3000` приймає і v4, і v6 → має працювати. Перевірка потрібна для впевненості.
- [ ] 👤 Після першого деплою canopy: `kamal app exec -i 'ss -tlnp | grep 3000'` — очікуємо `tcp6 LISTEN [::]:3000`
- [ ] 👤 `curl -fsS http://127.0.0.1:3000/up` і `curl -fsS http://[::1]:3000/up` — обидва 200
- [ ] 👤 Задокументувати результат у `06_05_Puma_Configuration` (IPv6 runbook section)

## 🔧 Firmware

### 🔴 P0 — Критичні

#### FW.1 — Hardcoded AES-256 Key
- `03_01`, `03_02`, `03_05`, `05_02` | `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:81-82`
- **Опис:** Один і той самий ключ на ВСІХ вузлах мережі. Злам одного пристрою = компрометація всієї мережі
- **Рішення:** Per-device provisioning через HKDF, Factory Flashing pipeline
- [ ] 👤 Firmware: RDP Level 2 activation як final step

#### FW.2 — AES-128-ECB → AES-128-CCM (24B packet) [post-ARCH.42]
- `03_05` | `firmware/soldier/main.c` (MX_CRYP_Init), `firmware/queen/main.c` (MX_CRYP_Init)
- **Опис:** Детерміністичний шифротекст, replay/bit-flip attacks можливі. Немає автентифікації пакетів. Після ARCH.42 (Variant B, 2026-05-23) LoRa-канал на AES-128, але режим залишається transitional ECB до повного CCM rollout.
- **Рішення (рекомендоване):** **AES-128-CCM** (апаратно підтримується STM32WLE5JC через `CRYP_AES_CCM` у HAL) з новим 24-байтним пакетом. Вирішує BLOCKER-2 та BLOCKER-3 одночасно. Узгоджено з ATECC608B Slot 0 (AES-128 SE constraint).
- **Альтернативи:** AES-128-GCM, AES-128-CTR + HMAC-SHA256 MIC (4-byte suffix), AES-128-CMAC LoRaWAN-style.
- ✅ Зроблено: дизайн 24B AES-128-CCM + backend парсер + firmware freeze-contract emit/decrypt + 14 host-тестів (byte-parity з `Cryptography::LoraCcm`); FC у RTC DR15. Лишається 1 HW-bench verify → flip `FW2_CCM_ENABLED`/`TELEMETRY_CCM_ENABLED`. Канон: `03_05 §3.2` BLOCKER-2.
- [ ] 🤖 Верифікувати `CRYP_AES_CCM` підтримку на цільовій ревізії STM32WLE5JC (RM0461 §27.4 — needs hardware bench). **ЄДИНИЙ HW-залежний пункт після 2026-05-24 freeze-contract landing.**

#### FW.3 — Queen AT Command Blocking (~25 сек)
- `03_01`, `03_02`
- **Опис:** Queen "сліпа" до LoRa пакетів під час CoAP flush. Single-packet buffer — пакети втрачаються
- ✅ Зроблено (🟡 частково): ring buffer + drain-loop закрив single-packet overwrite / emergency loss. Повний async UART DMA flush — окрема ітерація (HW bench). Канон: `03_02`.
- **Рішення:** UART DMA interrupt-driven + ring buffer
- [ ] 🟡 Переписати `Flush_Cache_To_Rails()` на UART DMA — deferred (наступна ітерація FW.3, потребує STM32 hardware bench)

#### FW.4 — TinyML `Run_Inference()` — compilation unblocked, inference TBD
- `03_03` | `main.c:1422` call-site закоментований; stub додано
- **Опис:** Compilation більше не блокується (stub fallback 2026-05-22); реальна модель + uncomment call-site залишаються.
- **Блокує:** Acoustic detection runtime (chainsaw, cavitation, wind), Mongabay biodiversity pivot
- [ ] 👤 Тренування моделі (Path B log-mel, 5 класів включно з fauna)
- [ ] 👤 Генерація реального `silken_net_audio_model.h` від ML-партнера (Бушин/Любченко) — заміняє stub автоматично через `__has_include`
- [ ] 🔗 Verify реальний Tensor Arena size через `arm-none-eabi-size firmware.elf` після інтеграції моделі
- [ ] 🔗 Розкоментувати `ml_event_id = Run_Inference(...)` у `main.c:1422`
- [ ] 🔗 Host-based golden vector тести
- [ ] 🌿 **FW.4-EXT (Mongabay pivot, post-TRL 7):** Розширення моделі з 4 → **5 класів** з додаванням `4 = fauna_activity` (циркадний dawn/dusk soundscape) — див. [`03_03` §10](../docs/03_03_TinyML_Acoustic_Inference). Залежить від калібрувального датасету ЧДТУ ПМКТ + ЧНУ Біо-хабу (UNI.11 + UNI.13a). Альтернативна архітектура: спектральний descriptor ACI (Acoustic Complexity Index) на STM32 без NN, як TRL-7 інкремент

#### ✅ FW.18b — OTA threshold invalid counter (production-visibility) — РЕАЛІЗОВАНО
- `03_03` §FW.18 audit refinement | `firmware/soldier/main.c §1.11` | **P2**
- **Опис:** Saturating uint8 counter `tinyml_threshold_invalid_count` інкрементується коли `TinyML_Apply_Thresholds` відкидає OTA payload (NaN, out-of-range, інверсія `warn >= crit`). Embedded LOG_ERR марний на headless STM32 — counter дає production visibility замість debugging-toy.
- ✅ Зроблено: saturating counter `tinyml_threshold_invalid_count` + 7 host-тестів (51/51 TinyML green). Канон: `03_03 §FW.18`.
- [ ] 🔗 Wiring до 21-byte LoRa packet (потребує перерозподілу бітів або додавання поля в Status Byte) — окрема задача
- [ ] 🔗 Backend: Prometheus метрика `tinyml_threshold_invalid_total{soldier_did}` + Grafana panel "OTA threshold corruption rate per Soldier"

### 🟠 P1 — Важливі

#### FW.7 — Float vs BigDecimal divergence (TRL 6 mitigation)
- `05_02`
- **Опис:** firmware `8.0/3.0 = 2.6666666666666665` vs backend BigDecimal `2.666666666666666667`
- ✅ Зроблено: backend `SilkenNet::Attractor` BigDecimal→Float (IEEE 754, ідентично firmware mruby → DCI однакові Z). Канон: `03_04` BLOCKER-4.
- ⚠️ *Увага: IEEE 754 Float математика все одно буде давати незначний drift між ARM (STM32 Soldier) та x86 (GCP/Akash Backend) архітектурами. Категоричний tolerance band (homeostasis/stress/anomaly) компенсує це для TRL 6, але строгий побітовий consensus потребує `ARCH.18`.*
- [ ] 👤 Верифікувати `MRB_USE_FLOAT` при першому lab-тестуванні (залишковий ризик)

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- `05_02`, `04_01`, `04_02`
- **Опис:** firmware: global 2.0/45.0 vs backend: per-species через `TreeFamily`
- **Рішення:** OTA sync species-specific thresholds
- ✅ Зроблено (🟡 deferred TRL-7): Rails-сторона + firmware-парсер `Soldier_Handle_CMD_SET_THRESHOLDS` (freeze-contract, `FW8_PARSER_ENABLED 0`) + 12 host-тестів. Defer: брак вільних RTC-регістрів (DR0-19 зайняті); розблок після FW.21. Канон: `03_01 §2`, `04_01`, `04_02`.
- [ ] 🟡 **Deferred TRL-7:** Активувати `FW8_PARSER_ENABLED 1` після того, як FW.21 рефакторинг звільнить хоча б 1 RTC Backup register

### 🟢 P2 — Низькопріоритетні

#### FW.17 — Key rotation mechanism (Hash Ratchet KDF)
- `03_05` BLOCKER-5 | Після FW.1 (per-device provisioning) — future cycle
- **Опис:** Поточна архітектура: статичний ключ при Factory Flashing. Немає механізму зміни ключа без перепрошивки всіх вузлів. Порушує GDPR/ISO 27001/NIST SP 800-57
- **Рішення (рекомендоване — Hash Ratchet KDF):** Синхронна деривація нового ключа на обох кінцях без передачі ключа по мережі. Backend надсилає `CMD:ROTATE_KEY:<UUID>` → Queen + Soldier проганяють `K_current` через AES-KDF → `K_next`. Забезпечує Perfect Forward Secrecy (PFS)
- [ ] 🔗 Дизайн Hash Ratchet протоколу (AES-based KDF on STM32 hardware)
- [ ] 🔗 CMD:ROTATE_KEY CoAP command + OTA relay через Queen
- [ ] 🔗 Cluster-wide activation confirmation (ACK від усіх вузлів)
- [ ] 🔗 Зберігання `K_current` та `rotation_counter` у Flash/RTC Backup Domain
- [ ] 🔗 Consider ECDH/Curve25519 key exchange при provisioning (альтернатива)

#### FW.19 — Float32 vs Float64 mruby compile flags
- `03_04` BLOCKER-4
- **Опис:** mruby без `MRB_USE_FLOAT` використовує double (64-bit), з прапорцем — float (32-bit). Makefile не верифікований. Різниця ±5-10 units на Z-осі після 250 ітерацій може змінити bio_status (false slashing)
- ✅ Зроблено (🟡 частково): tolerance band задокументовано як «by design» (категорична перевірка `check_z_divergence!`); верифікація mruby compile flags — lab. Канон: `03_04` BLOCKER-4.
- [ ] 👤 Верифікувати mruby compile flags (`MRB_USE_FLOAT` у Makefile або mrbconf.h) при lab-тестуванні

#### FW.20 + FW.20-S2 — Time Sync (Rails ↔ Queen ↔ Soldier)
- **SSOT (повний контекст, wire-формати, регресійний бенч):** [`03_02 §5а Time Sync — Канонічний хаб`](03_02_Queen_Gateway_Firmware). Цей запис у 00_08 — лише чек-лист прогресу.
- **TRL impact:** P2 для TRL-6 (`Derive_Cold_Start_State` живе з ±12 год толерантністю); блокер для TRL-7 (ARCH.26 TDMA, HMAC nonce replay-protection, корельовані події fire detection ±1 сек).

**FW.20 (Rails+Queen+Soldier 1-hop) — ✅ Done:**
- [ ] 👤 Lab drift compensation тест при ΔT = ±60°C (потребує термокамери — TRL-7)

**FW.20-S2 (mesh-relay extension, 5 підпунктів) — 4 з 5 ✅ Done, 1 deferred:**
- [ ] 🟡 (4/5) Anti-storm dedup bitmap — потребує вільного RTC регістра (DR15 наразі резерв; стратегія див. [`03_01 §2.3 ARCH.28`](03_01_Firmware_Lifecycle_and_DMA))

**Cross-ref:** ARCH.26 (TDMA Sync Windows), FW.30 (cold-start `epoch_day` consumer), SEC.10 (panic frame counter — disambiguator FW.29 PANIC_FLAG_BIT для нормал/паніка байтів 14-15).


#### FW.21 — Edge data aggregation (RAM-aware Soldier)
- Legacy notes + `08_02` (Kalman filter Vector 4) | P2 (потребує R&D partnership)
- **Опис:** Soldier MCU має обмежений RAM (~20 KB вільного). Поточна архітектура: кожен wakeup → один 21-байтний пакет → TX. Для майбутнього (Kalman filtering, TinyML context) потрібна локальна агрегація
- **Рішення:** Moving average / EMA прямо на MCU. Відправляти на Queen лише: (1) поточне значення, (2) дельту від попереднього EMA, (3) стиснуті "summary" пакети. Зменшує трафік LoRa та економить батарею
- ✅ Зроблено: `EmaState` + 4 функції (`EMA_Update`/`EMA_Get_DeltaT_Sec`/`EMA_Get_Vcap_Mv`/`EMA_Is_Warmed_Up`) у `main.c §1.10`, persistence RTC DR10+DR12 (звільнено DR11), 102 host-тести. Передача EMA→mruby — у FW.5 B+. Канон: `03_01 §2`.
- [ ] 👤 Інтегрувати з Kalman filter design (E.10 — Косенук)

#### FW.22 — acoustic_events payload overflow (uint16 → uint8 truncation)
- `03_03` BLOCKER-7
- **Опис:** `acoustic_events` — тип `uint16_t` в firmware, але в 21-байтний пакет пишеться лише молодший байт (low byte). Якщо між TX циклами більше 255 подій — silent overflow, дані корумпуються. Backend отримує обрізане значення без можливості виявити overflow
- **Пріоритет:** P2 (рідкий сценарій при нормальній роботі, критичний при stress-тестуванні)
- ✅ Зроблено: тип `uint8_t` + saturating increment (cap 255), backend overflow-warning + Prometheus counter у `TelemetryUnpackerService`, 8 тестів. Канон: `03_03` BLOCKER-7.
- [ ] 🔗 АБО: виділити 2 байти в payload (потребує перепакування — пов'язано з FW.2 CCM transition)

#### FW.23 — OTA firmware broadcast: ECB без автентифікації
- `03_05` | `firmware/queen/main.c`
- **Опис:** OTA bytecode chunks (`[0x99][index:2][total:2][bytecode:11]`) передаються через AES-128-ECB (OTA reflex, post-ARCH.42) без MAC/signature. Зловмисник може підмінити firmware chunks → code injection на всіх Soldiers у радіусі Queen. Відсутня верифікація цілісності зібраного bytecode перед записом у Flash (`0x0803F000`)
- **Пріоритет:** P1 (критичний для security, але блокується FW.2 CCM transition)
- ✅ Зроблено: HMAC-SHA256 OTA auth — `OtaHmacKeyService` (HKDF info `silken-ota-hmac-v1`) + `OtaPackagerService` (`compute_hmac_tag` / `build_hmac_trailer_chunks` `[0x9B]`) + Queen stateless relay + Soldier dual-gate (magic `RITE` + constant-time HMAC) → Flash. 30 RSpec + 17 host-тестів. Канон: `03_05 §3.4б`.
- [ ] 🟡 mbedTLS HMAC-SHA256 compute on STM32 HASH peripheral — deferred до lab integration (analog FW.30 mbedTLS deferred TODO)

#### FW.25 — TinyML DSP-path: **Path B (log-mel) SELECTED** [DECISION 2026-05-22]
- `03_03` §3.2 Decision Matrix + BLOCKER-5 | `firmware/soldier/main.c:1417-1419` | **P0** — implementation gate, не choice gate
- **Owner (revised 2026-05-22):** **Primary: Бушин або Любченко (ЧНУ ФОТІУС, ML)** — тренування 2D-CNN з log-mel features (`librosa.feature.melspectrogram` без DCT); **Secondary: Ярмілко (ЧНУ ФОТІУС, embedded)** — CMSIS-DSP integration (`arm_rfft_fast_f32` + custom Mel-bank + `arm_vlog_f32`)
- **Опис (FINALIZED 2026-05-22):** Choice gate **закрито**. Архітектурне рішення: **Path B (log-mel spectrogram + 2D CNN)** як офіційний baseline. Обґрунтування:
  1. **Path A провалюється на fauna (клас 4):** layered soundscape (комахи 4–8 кГц + птахи 1–6 кГц + амфібії 0.5–3 кГц) має ідентичну часову огинаючу з шумом вітру/дощу — розрізнення можливе тільки через spectral structure. Time-domain 1D CNN на STM32WLE5JC (64 KB SRAM) не вистачить ємності навчити FFT-features з нуля. Path A залишається fast-path MVP для 4-class (без fauna), якщо ML-партнер недоступний.
  2. **Path C (TFLM microfrontend) має більший Tensor Arena overhead** (+5-10 KB vs Path B) — критично на 64 KB SRAM. Path C залишається fallback'ом, якщо ML-партнер натисне на TFLM end-to-end через Edge Impulse workflow.
  3. **ESC консенсус:** Salamon & Bello 2015 (ESC-50), BirdNET 2021, UrbanSound8K — усі сходяться на log-mel для CNN-based ESC. DCT-крок MFCC декорелює ознаки для GMM/HMM (speech anachronism), але знищує spatial structure для 2D-CNN.
  4. **CMSIS-DSP вже в стеку** (FW.21 EMA, FW.5 Lorenz). Custom Mel-bank ~50 рядків C додасться без зміни toolchain.
  5. **Mongabay pivot** робить fauna стратегічним — рішення мусить бути fauna-ready з самого початку.
- [ ] 👤 ML-партнер (Бушин/Любченко) **підтверджує/коригує log-mel контракт** `03_03 §3.4` (конкретні параметри готові: 16k / n_fft=512 / 40 mel / HTK / ln+1e-6) — переводить FW.25 з implementation-gate у executing
- [ ] 🤖 **Path B implementation** (`Compute_LogMel` per `03_03 §3.4` contract): CMSIS-DSP `arm_rfft_fast_f32` + вшитий HTK mel-bank (40 bands, sparse triplet) + `arm_vlog_f32` + golden-vector host-тести (numpy ↔ C, tol 1e-3). **НЕ `arm_mfcc_f32`** (DCT anti-pattern). Розблоковано після §3.4 confirm.
- [ ] 🤖 Verify TENSOR_ARENA budget для Path B (~15-30 KB target; cross-ref FW.26 + BLOCKER-3)
- [ ] 🤖 Тести: золотий вектор inference (наперед відома класифікація) на log-mel input
- [ ] 🌿 Cross-ref UNI.11 + UNI.13a: акустичний датасет dawn/dusk Черкаського бору
- [ ] 🤖 Фалбек-план: якщо ML-партнер сильно натисне на Path C (Edge Impulse / TFLM end-to-end) — допустимо, але потребує повторної верифікації Tensor Arena

#### FW.26 — TENSOR_ARENA_SIZE ніколи не верифіковано
- `03_03` BLOCKER-3 | `firmware/soldier/main.c` | **P1**
- **Опис:** Точна величина `TENSOR_ARENA_SIZE` невідома з коду — документація оцінює ~8-16 KB. Ніколи не виміряно через `arm-none-eabi-size`. Якщо tensor arena > 46 KB → stack overflow при Lorenz обчисленнях (250 ітерацій mruby + Lorenz state)
- [ ] 🤖 Запустити `arm-none-eabi-size firmware/soldier/build/soldier.elf` після додавання моделі (FW.4) → виміряти `.bss + .data`
- [ ] 🤖 Якщо > 46 KB — оптимізувати модель (INT8 quantization, prune)
- ✅ Зроблено (CI gate): `make -C firmware/test size-check` (host `.bss+.data` < 51200B; baseline soldier 2.5K / queen 12.4K) у `ci.yml`. ARM-gate (`arm-none-eabi-size`) — після lab build (FW.4). Канон: `03_03` BLOCKER-3, `04_06`.

#### FW.27 — OTA broadcast: відсутня RX-верифікація Soldier
- `03_02` §5 | **P2**
- **Опис:** Queen транслює OTA chunks послідовно через LoRa без перевірки чи Soldier активно слухає. Якщо Soldier у STOP2 під час broadcast — chunk втрачається без retry. Документація **не описує recovery механізм** для пропущених chunks. Без TDMA Sync Windows (ARCH.26) — broadcast ненадійний
- ✅ Зроблено: обидва recovery-дизайни + Дизайн B (Magic Re-Request) реалізовано — Soldier bitmap uplink `[0x55]` → Queen targeted re-broadcast (60-90% economy), 22 host-тести. Дизайн A (ACK-aggregation) — з ARCH.26. Канон: `03_02 §5`.
- [ ] 🔗 Залежить від ARCH.26 (TDMA для координованого RX вікна) — лише для Дизайну A; B реалізовано незалежно

#### FW.30 — SEC.11 C-bridge gap: `firmware/soldier/main.c` mruby виклик не оновлено
- `firmware/soldier/main.c:685-740`, `firmware/bio_contracts/bio_contract.rb` | **P1** | 🔗 Блокує FW.5 B+
- **Опис:** SEC.11 cutover змінив API `bio_contract.rb` (видалено `calculate_state_continued` і старий 3-arg `calculate_state(seed, ...)`; залишена лише єдина сигнатура `calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s, vcap_mv)`). Проте `firmware/soldier/main.c` **не було оновлено** разом з mruby-скриптом:
  - warm path (рядок 701): викликає `calculate_state_continued` з 5 args → **mruby NoMethodError** → `BIO_STATUS_VM_ERROR` на кожному теплому старті
  - cold path (рядок 724): викликає `calculate_state(chaos_seed, temp, acoustic)` з 3 args → **ArgumentError** (нова сигнатура очікує 7 args); крім того, вручну повторює `seed→(x,y,z)` перетворення (рядки 731-735) замість mbedTLS HKDF cold-start
- **Наслідок:** поточна пара (main.c + новий bio_contract bytecode) **не функціонує**. Пристрої працюють на старому OTA-байткоді (до SEC.11). Новий bytecode OTA-деплоїти до виправлення main.c — неможливо.
- **Рішення:** оновити `firmware/soldier/main.c` mruby-секцію:
  - Об'єднати warm/cold paths в один виклик `calculate_state(x_prev, y_prev, z_prev, temp, acoustic, delta_t_s_default, vcap_mv_default)` (7 args; `delta_t_s`/`vcap_mv` default поки без EMA — FW.5 B+ наступний крок)
  - Cold-start: замість `chaos_seed → seed→xyz` перетворення — mbedTLS HKDF-SHA256 cold-start derive із K_seed у Flash (такий самий алгоритм як у firmware/test/test_seed_derivation.c)
  - Додати `firmware/test/` тест для нової C-bridge сигнатури
- ✅ Зроблено: warm/cold paths → єдиний 7-arg `calculate_state`; `Load_Lorenz_Seed()` (K_seed з Flash, magic `LSED`) + `Derive_Cold_Start_State()` (placeholder hash, TODO mbedTLS lab); 11 host-тестів. Канон: `03_04`.
- [ ] 🔗 Після FW.30 — FW.5 B+ (передавання EMA delta_t/vcap як args[5..6]) стає незалежним кроком

#### FW.31 — DCI: числовий tolerance band у `check_z_divergence!` (feature-flag flip)
- `app/services/telemetry_unpacker_service.rb`, `docs/03_04` §BLOCKER-2 | **P2**
- **Опис:** Після SEC.11 обидві сторони стартують з byte-identical `(x₀,y₀,z₀)` і виконують ідентичну Float IEEE-754 математику. Емпіричний Float divergence ARM↔x86 за 250 ітерацій < 1e-12. Проте `check_z_divergence!` зберігає **категоричну** перевірку (homeostasis/stress/anomaly enum match) замість числового `|server_z − device_z| < ε`. Числовий tolerance band (`ε < 0.001`) вже закоментований як "готовий до flip" у docs/03_04 §BLOCKER-2.
- **Умова для flip:** потрібно виміряти реальний drift `server_z − device_z` на цільовому ARM hardware (STM32WLE5JC vs GCP x86-64) з тією ж Float/mruby compile-flag комбінацією. Очікуваний drift < 0.001 — це значно менше розміру одного growth_points step (~1 unit), тому false-слешинг малоймовірний.
- **Вплив після flip:** fraud detection стає **числовим** — дозволяє виявляти не лише категоричні (homeostasis vs stress) помилки, але й систематичне зміщення Z (наприклад, replay атаку з правильним status-byte але неправильним Z magnitude).
- [ ] 👤 Лабораторне вимірювання: запустити однакові тест-вектори на STM32WLE5JC + GCP x86-64, виміряти `|server_z - device_z|` distribution (N=10,000)
- [ ] 🤖 Оновити `03_04` §BLOCKER-2 з реально виміряним drift + остаточно обраним ε — **залишається lab-blocked** (потребує STM32WLE5JC REVB + GCP x86-64 instrumented run); попередньо ε=0.001 closed-loop default

#### FW.42 — Vcap guard для fauna acoustic sampling (brownout protection)
- `firmware/soldier/main.c` (FW.4 fauna sampler), `docs/03_03` §10.3 | **P1**
- **Опис:** Після audit-fix енергетичного бюджету (`03_03 §10.3`, патч 2026-05-16) реальна вартість одного fauna-сесійного циклу = **~78.3 мДж** (× 20 від попередньої оцінки `3.3 мДж/доба`). Активний CPU під час 156 MFCC+inference вікон тягне ~12 мА × 1.56 с → транзієнтна просадка V_cap. При `V_cap ≈ 3.5 V` (margin ~100 мВ над `VBAT_OK ON = 3.4V`) просадка ~37 мВ ставить EDLC на межу — будь-який concurrent TX = brownout посеред інференсу.
- **Рішення:** Guard clause `Fauna_Should_Sample(uint16_t vcap_mv)` — повертає 1 коли V_cap ≥ FAUNA_VCAP_MIN_MV, інакше 0 і інкрементує saturating uint8 counter `fauna_skipped_low_vcap`.
- ✅ Зроблено (firmware-side): `Fauna_Should_Sample()` + `fauna_skipped_low_vcap` counter (freeze-contract) + 8 host-тестів. Активація — 2 рядки у fauna-pathway після FW.4. Канон: `03_03 §10.3`.
- [ ] 🔗 Активація: викликати `Fauna_Should_Sample()` всередині fauna-pathway після FW.4 uncomment
- [ ] 🤖 Прометей метрика + Grafana panel "Fauna skip rate per cluster" — після FW.4 (метрика без даних = шум)

## 🧭 Architecture / SSOT-drift fixes (2026-05-16 cross-doc audit)

> Знахідки з рев'ю модулів 00_, 01_, 02_, 03_, 03_05 (інженерний аудит, 2026-05-16). Слоти ARCH.39–ARCH.42 зарезервовано під цей патч-комплект.

#### ARCH.39 — Fauna acoustic energy budget — арифметична + системна корекція
- `docs/03_03_TinyML_Acoustic_Inference.md` §10.3 | **P2** | ✅ **Doc-fix вкочено 2026-05-16**
- **Опис:** Перша редакція §10.3 містила (1) арифметичну помилку `1 мА × 3.3V × 10 с = 3.3 мДж` (правильно 33 мДж — у 10× нижче), (2) ігнорування активного CPU під час MFCC+inference (~12 мА × 1.56 с). Реальна вартість fauna-сесії ≈ 78.3 мДж/сесію, ~156.6 мДж/добу (× 20 від оригінальної оцінки). Все ще сумісно з EDLC бюджетом, але імпульсна потужність потребує V_cap guard'у — див. **FW.42**.

#### ARCH.40 — Fauna 5-секундне вікно: монолітне awake-обчислення (SRAM2 wipe constraint)
- `docs/03_03_TinyML_Acoustic_Inference.md` §10.2 | **P1** | ✅ **Doc-fix вкочено 2026-05-16**
- **Опис:** Architecture v3 використовує STOP2 RTC-only з `PWR_CR1_RRSTP=1` → SRAM2 wipe при кожному переході в сон. Декомпозиція 5 с акумульованого вікна (156 MFCC-векторів `mean+std`) на «32 мс → STOP2 → 32 мс» неможлива: проміжна float-матриця у RAM не переживе сну, DR15 (єдиний вільний RTC регістр) не вміщає float[156][N_mfcc].
- **Рішення:** Явно зафіксовано у §10.2 — fauna-сесія мусить виконуватись монолітно за один цикл активного пробудження (156 циклів TIM2+DMA послідовно).
- [ ] 🔗 При імплементації FW.4 fauna-pivot: вимагати unit-тест `test_fauna_sampling_no_stop2_in_session()`

#### ARCH.41 — Cold-start Time Paradox для Dual Computation Integrity
- `docs/03_04_mruby_Lorenz_Attractor.md` §2.1, `firmware/soldier/main.c` `Derive_Cold_Start_State`, `app/services/telemetry_unpacker_service.rb#compute_server_z` | **P2**
- **Опис:** Після VBAT loss Soldier'ський RTC скидається на default-дату (2000-01-01) → `Derive_Cold_Start_State()` обчислює `epoch_day ≈ 10 951` замість серверного ≈ 20 585. Server при дереві з історією chain'ить з попереднього `lorenz_state_tail` (не cold-derive) → траєкторії розходяться категорично доки `CMD_TIME_SYNC` beacon від Queen не оновить RTC Soldier'а.
- **Поточний імпакт:** Категоричний DCI можуть тригерити false-positives на cold-boot пакетах (≤ 50 wake-up циклів до ergodicity ~2 доби). Numeric DCI branch (FW.31) інертний у production (LoRa packet 21B не несе raw Z) — стане критичним після post-FW.2 packet revision.
- **План мітигації (вибрати один):**
  - **(A) Server-side fallback** (рекомендовано, без firmware change): У `compute_server_z` при категоричному DCI mismatch + tree має історію → retry через cold-start derivation з трьома кандидатами `epoch_day` (today, today−1, firmware RTC-default ≈ 10 951). При збігу — позначити `TelemetryLog#time_unsynced_fallback = true`, queue `CMD_TIME_SYNC` через downlink, не падати DCI.
  - **(B) Soldier-side sentinel** (потрібен координований firmware rollout): При cold-boot Soldier шле `acoustic_events = 0xFE` як sentinel у першому uplink. Backend трактує як «time uncertain».
  - **(C) Defer first uplink** (потребує firmware redesign): Soldier у grace-вікні (10 хв) шле спрощений «hello» пакет без Lorenz state — тільки DID + Vcap + TIME_REQ маркер.
- [ ] 🔗 (B/C) Розглянути після стабілізації (A) — потребують координованого firmware rollout

## 🧪 Hardware / Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

#### HW.20 — BME280 environmental sensing + VPD confounder [ADR `02_01 §3.4`]
- **P1** | `02_01 §3.4` / `07_02 §1.3` | **Складність: L** | 🤖 (docs/firmware/backend specs) + 👤 (bench + механіка)
- **Опис:** BME280 (t°/RH/тиск, I2C, за TPS22860-гейтом) → **VPD** як прямий фізіологічний confounder (вбивця False Slashing, `00_01 §6.5/§6.6`) + гіперлокальний клімат-оракул (NaaS-дохід, `07_01`). 🚨 DCI-guard: VPD **НЕ** входить у Lorenz-Z. Поправки до вихідної нотатки: BME280 (не BME680); MCU sleep 300нА (не 2.1µA); gated draw ≈8нА.
- ✅ Зроблено (docs): `02_01 §3.4` ADR + §7.2 promote + §2 + §3.2; `00_01 §6.6`; `08_02 §4` (collection + VPD-confounder); `07_02 §1.3` (+$2.60 add-on); `02_03 §9.6` (gated energy); `07_01` (climate data-product).
- [ ] 🤖 `03_01`: SENSE-фаза читає BME280; hybrid packet (1B VPD-індекс hot-path + періодичний climate frame).
- [x] 🤖 ✅ (2026-05-29) TelemetryLog поля `humidity`/`pressure`/`vpd` — у `structure.sql` (parent + 7 партицій via ALTER+pg17 dump), recreate+seed verified, 04_01 doc + модель-коментар. **Лишається:** VPD confounder-gate у `stress_index`/`ContractHealthCheckService` (slashing-adjacent, тісно з SLASH-1).
- [ ] 👤 Bench: I2C bring-up, forced-mode середній струм, TPS22860 gate-timing, VPD-калібрування vs референс-гігрометр.
- [ ] 👤 Механіка: PTFE/Gore мікро-вент у корпусі (`02_02`), IP68 re-test.

#### HW.1 — nTop model → SLM+HIP factory (Anode Zone 1)
- **Джерело:** `01_01`, `01_02` §1.7 | ✅ Ліцензія отримана
- **Контекст:** Тризонний анкер (`01_01` §1) — Zone 1 (анод, гіроїд) виготовляється SLM+HIP; Zone 3 (катодний фланець) — SLM або EBM (`01_02` §1.7); Zone 2 (PEEK-втулка) — CNC з annealing 200–250°C
- [ ] 👤 Генерація TPMS gyroid geometry (65% porosity, **тільки для Zone 1**)
- [ ] 👤 **Вертикальна орієнтація пор** (`01_01` §5.5): головна вісь TPMS-комірки паралельна осі анкера (паралельно потоку соку)
- [ ] 👤 **Градієнт розміру пор** (`01_01` §5.5): центр 300–500 µm → периферія 100–150 µm при сталій пористості 65% — параметризація nTop cell size як функція радіуса
- [ ] 👤 Окреме креслення Zone 3 (катодний фланець ∅20–30 мм)
- [ ] 👤 STL/STEP файли → передати на SLM завод (Київ/Дніпро) разом з вимогою HIP-постпроцесу (`01_02` §1.7 + HW.23)
- [ ] 👤 **Build orientation specification** (`01_02` §1.6): BD ∥ довгій осі анкера, кут до build plate 0° ± 5°, externally only support
- [ ] 👤 **Карта обмежень покриттів** (`01_02` §3.6): передати заводу інструкцію — ZnO-Ta НЕ наносити на гіроїдні стінки Zone 1
- [ ] 👤 SEM criteria для приймання партії
- [ ] 👤 µCT-сканування для верифікації градієнту розміру пор (центр 300–500 → периферія 100–150 µm) при пористості 65 ± 2%

##### Підблокер HW.1.PicoGK — Code-as-CAD Alternative (paralleled R&D track) — `01_02 §6 PicoGK`
> **Стратегія:** PicoGK (open-source SDF engine від LEAP 71) + C# як AI-агент-сумісна альтернатива nTop GUI. Усуває "GUI-blindness" Cursor/Claude/Copilot та робить геометрію Git-friendly. Не замінює nTop одразу — паралельний evaluation track.
- [ ] 👤 **Setup C# проєкту:** Visual Studio 2022 або JetBrains Rider, .NET 7+, console project
- [ ] 👤 **Build PicoGK з GitHub** (`github.com/leap71/PicoGK`) → підключити як бібліотеку
- [ ] 👤 **Promt template для Claude/Copilot:** Senior C# інженер пише `Zone1Anode` клас з SDF гіроїда (формула sin(x)cos(y)+sin(y)cos(z)+sin(z)cos(x)=0), параметризованим діаметром/пор/wall thickness
- [ ] 👤 **Stage 1 SLA generation через PicoGK** (паралельно з nTop reference) — порівняти STL output на topology errors
- [ ] 👤 **Per-species CEM (5 SKU):** pine/oak/broadleaf/mangrove/tropical — параметрична генерація через зміну однієї змінної (`00_06 §7.3` cross-biome generalization)
- [ ] 👤 **Migration decision gate (Q2 2026):** якщо PicoGK видає clean STL без BREP errors → почати міграцію SSOT з `.ntop` на `.cs` (Git-friendly)
- [ ] 👤 **Annular barbs SDF:** реалізувати asymmetric triangle profile h=0.3mm у C# для PEEK mechanical lock (`01_01 §4.3`, HW.26)

#### HW.2 — Dual-scale roughness spec
- **Джерело:** `01_02`
- **Опис:** Sa 0.5-5 µm, Sv 50-500 nm НЕ передана на завод
- **Блокує:** Максимальний струм EBFC, TRL 5
- [ ] 👤 Підготувати factory spec з метриками
- [ ] 👤 Передати на завод
- [ ] 👤 Отримати SEM images ×500/×5,000/×50,000

#### HW.3 — Accelerated aging test (Arrhenius)
- **Джерело:** `01_02`
- **Опис:** 12-тижневий тест у synthetic xylem sap
- **Блокує:** Seed раунд, whitepaper, TRL 5→6
- [ ] 👤 Синтез штучного ксилемного соку (потрібен ботанік)
- [ ] 👤 Запуск 12-тижневого тесту
- [ ] 👤 ICP-MS аналіз: Ti < 0.1 µg/cm², V < 0.02 µg/cm²
- [ ] 👤 EIS degradation < 50%

##### Підблокер HW.3.IS — In Silico FEA Aging (Stage 0, mechanics) — `00_04 §4a` Trek C
> **Стратегія:** Симуляція напружень Ti+PEEK при extreme температурах ще ДО фізичного 12-week теста. Використовуються рівняння Ляме для thick-walled cylinder (Zone 1 ↔ Zone 2 ↔ Zone 3 коаксіальний press-fit). Закриває (a) механічну цілісність PEEK creep на 20-річному horizon'і, (b) сезонні термоциклічні навантаження.
- [ ] 👤 **FEA setup:** CalculiX (open source, .NET/Python wrappers) або Code_Aster (Python) — заміна ANSYS GUI для AI-агент-сумісного workflow
- [ ] 👤 **DFT (PySCF) для іонного бар'єра:** енергія активації дифузії Ti²⁺/Ti⁴⁺/Al³⁺/V³⁺ через PEEK-матрицю → корозія НЕ отруїть ферменти за 20+ років

#### HW.4 — Self-healing coating (NEW: zone-restricted)
- **Джерело:** `01_02` §3 + `01_02` §3.6
- **Опис:** 8-HQ мікрокапсули не синтезовані
- **⚠️ Zone restriction:** Self-healing наноситься **тільки на неактивні поверхні** (зовнішня сорочка катодного фланця Zone 3, торці PEEK-втулки). НЕ наноситься на гіроїдні стінки Zone 1 (блокує DET) і не на катодну каталітичну поверхню (блокує DET до Cu T1 лаккази). Деталі — `01_02` §3.6.
- **Блокує:** 20+ років longevity claims, TRL 6
- [ ] 👤 Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] 👤 Інтеграція в PEO electrolyte або layer-by-layer — ТІЛЬКИ на дозволених зонах
- [ ] 👤 Тест: 10× вищий Rct
- [ ] 👤 **Thiol-Michael interphase** (`01_02` §1a.1): тест адгезії self-healing шару при ростовому навантаженні, порівняння з простою APTES-силанізацією — додано в `01_02`

#### HW.5 — Enzyme lifespan + Gen 2.0 chemistry stack
- **Джерело:** `01_03` § 1–3 (REWRITTEN 2026-05-22)
- **Опис:** Довгострокова стабільність біоелектрохімічного стеку у кислому ксилемному середовищі (pH 4.5–5.5) при повній імунологічній невидимості для CODIT-каскаду. Цільовий термін **20–25 років**.
- **Gen 2.0 baseline (REWRITTEN 2026-05-22 — одношарова FAD-GDH архітектура):** Архітектура `01_03` повністю переписана на Gen 2.0. Gen 1.0 (GOx + Catalase + глутаральдегід + PEG) **визнана нежиттєздатною** і виключена з усіх лабораторних протоколів — не використовується навіть як baseline. Новий стек:
  - **Анод (Zone 1):** одношаровий `fMWCNT + Os-полімер + dgrFAD-GDH` (деглікозильована FAD-залежна глюкозодегідрогеназа з *Glomerella cingulata* або *Aspergillus*) → не виробляє H₂O₂, O₂-незалежна, повний pH 4.0–8.0 діапазон. Каталаза не потрібна.
  - **Захисна матриця:** **Genipin-Chitosan-CNC** (геніпін як нетоксичний зшивач замість глутаральдегіду + целюлозні нанокристали 2–6% для псевдопластики проти тигмоморфогенезу).
  - **Катод (Zone 3):** Гібрид `Laccase + ZIF-nanozyme` (nCoCuCeZIF/Lac або nCuCeAuZIF/Lac) — ×10 power density, 75% активності після 10 днів, **+7.5% з 0.25 М NaCl** (vs -41.7% для чистої Laccase), резервний безферментний каталізатор при денатурації.
  - **Anti-biofouling мембрана (Шар 5):** **Nafion-g-PSBMA** (цвітеріонний полімер ковалентно прищеплений через SI-ATRP) — 8 молекул води/ланцюг, блокує абієтинову кислоту/смоли, σ(H⁺) = 45.2 мС/см, UCST winter-lock @ 5°C.
- [ ] 👤 **Gen 2.0 anode (priority):** одношаровий dgrFAD-GDH+Os electroactive layer + geniпin-chitosan-CNC матриця — `01_03` §2.1
- [ ] 👤 **Gen 2.0 cathode (priority):** Laccase + nCoCuCeZIF nanozyme гібрид на MWCNT — `01_03` §2.2
- [ ] 👤 **Цвітеріонна мембрана:** SI-ATRP синтез Nafion-g-PSBMA (контрактна синтез-лабораторія) — `01_03` §2.1 Шар 5. ⚠️ **Bottleneck:** пришивка ATRP-ініціатора потребує переведення Nafion у сульфонілхлоридну форму → вимагати досвіду з фторполімерами. Lead time 3–6 тиж. (`01_03 §3.7`)
- [ ] 👤 **Геніпін постачання:** контракт з Challenge Bioproducts (~$50–80/г, >98%, зберігати в темряві @4°C); тест cross-linking хітозану при pH 4.5 — `01_03` §2.1 Шар 4. **Найшвидший пункт — просто закупка.**
- [ ] 👤 **dgrFAD-GDH (🔴 КРИТИЧНИЙ ШЛЯХ, 4–8 тиж — пріоритет #1):** контрактна експресія у *Pichia pastoris* через B2B CRO. **Деглікозилювання gene-level (preferred):** віддати CRO ген з уже вбудованими 11 N→Q мутаціями (з L1) → *Pichia* не глікозилює → крок PNGase F не потрібен. Fallback PNGase F/endo-H — тільки native conditions (без SDS/DTT). *Pichia*, не *E. coli* (inclusion bodies). **Дія зараз:** скласти spec sheet (dgr-mutant ген, послідовність з L1) + розіслати RFQ. — `01_03` §3.7
- [ ] 👤 **ZIF-нанозим синтез:** сольвотермальний синтез nCoCuCeZIF (співпраця з нанохімією ЧНУ або НАН України, за співавторство Q1) — `01_03` §1 Катод. ⚠️ **Bottleneck:** ZIF чутливий до умов синтезу → жорстко прописати розмір 40–80 нм + SEM-контроль у T&C (макрокристали відпадуть з електрода). (`01_03 §3.7`)
- [ ] 👤 **CNC (целюлозні нанокристали):** закупка з ENERON або синтез з alpha-целюлози кислотним гідролізом
- [ ] 👤 **Поліпірол (PPy)** як опційний кополімерний підсилювач MET-стеку (паралельний з осмієвим полімером) — `01_03` §2.3
- [ ] 👤 Test 30-day stability на Ti-coins у синтетичному ксилемному соку — `01_03` §3.5
- [ ] 👤 UCST winter-lock тест PSBMA: -10°C → +25°C цикл, регідратація мембрани — `01_03` §2.1 Шар 5

##### Підблокер HW.5.IS — In Silico Stage 0 (Zero-Lab) — `01_03 §3.4`
> **Стратегія:** Computational reverse engineering хімії ДО першого Ti-monet. AlphaFold 3 + OpenMM + PySCF + scipy/numpy повністю Python-кервані → інтеграція з AI-clones. **TRL 3→4 gate PASSED (2026-05-25).** Зараз: publication-grade ωB97X ⏳ + xylem sap sweep ⏳.
- [ ] 👤 **Інфраструктура:** workstation NVIDIA RTX 4090 ($5–10K) АБО AWS p5.2xlarge / GCP g2-standard-12 ($2–5/год)
- [ ] 👤 **Joint Q1-publication з ЧНУ Мінаєвим:** "In Silico Design of Long-Lived Enzymatic Bio-Fuel Cells for Tree-Integrated Energy Harvesting" — `08_03` Стаття 28

#### HW.6 — Resin barrier + Flush Mount Installation
- **Джерело:** `01_04` §3 + Legacy notes
- **Опис:** Сосни заливають рану смолою → блокує доступ до ферментів. **Корінь проблеми = інструмент свердління**, а не лише матеріал анкера.
- **Стратегія:** (a) Flush Mount step drilling — анкер врівень з корою, камбій не пошкоджено; (b) Microfrezing замість стандартного свердла — хірургічно чистий розріз не тригерить resinosis
- [ ] 👤 **Flush Mount step drilling** (`01_04` §3.1): тестування багатоступеневого свердла на калібрувальних колодах сосни (товщина перидерми → ширина широкої ступені)
- [ ] 👤 **Microfrezing** (`01_04` §3.3): закупити прецизійні кінцеві фрези типу MicroX (карбід вольфраму + TiN-покриття), стендовий тест на колодах vs стандартні шнекові свердла — порівняння resinosis intensity
- [ ] 👤 30° installation angle verification (узгоджено з Flush Mount)
- [ ] 👤 Hydrophilic coating test
- [ ] 👤 **Nafion-g-PSBMA анти-resin coating** (Шар 5 анодного стеку, `01_03 §2.1 Крок 5`, REWRITTEN 2026-05-22): цвітеріонний полі(сульфобетаїн метакрилат) ковалентно прищеплений до Nafion через SI-ATRP; 8 H₂O/ланцюг блокує абієтинову кислоту термодинамічно; протонна провідність зростає до 45.2 мС/см; UCST @ 5°C winter-lock. **PEG (Gen 1.0) повністю виключений** — недостатній гідратаційний шар, окислювальне розщеплення
- [ ] 👤 Hydrophobic/hydrophilic gradient test (PTFE знизу, гідрофільний верх) — додано в `01_04` §3.4
- [ ] 👤 Thermal installation test: T° нагріву (150-200°C), час витримки — додано в `01_04` §3.5 (резервний метод, тільки для нефункціоналізованих анкерів)
- [ ] 👤 FEM-моделювання теплового поля в Ti-6Al-4V анкері (λ = 6.7 W/m·K)
- [ ] 👤 **Біоміметичні покриття проти CODIT** (`01_04` §4): Zn-HAp + хітозан композит на периферійних стінках пор — лабораторний синтез та in vitro тест адгезії клітин паренхіми Pinus sylvestris (запит до біо-хабу ЧНУ, [`08_01`](08_01_University_R_and_D_Protocols))
- [ ] 👤 **PEDOT:PSS гідрогель інтерфейс** (`01_02` §1a.2, `01_04` §4.1): тонкий шар (10–50 µm) на стінках периферійних пор для модульного буферу Ti↔калюс — верифікація провідності EBFC після нанесення
- [ ] 👤 **Лігнін-покриття** (`01_04` §4.1): «свій» полімер для дерева — тест зменшення каскаду CODIT Wall 4
- [ ] 🔗 **SA reservoir — НЕ інтегрувати без верифікації** (`01_04` §4.2 caveat #2): чи не маскує екзогенна саліцилова кислота природний сигнал стресу, який вимірює Lorenz attractor (запит до біо-хабу, [`08_01`](08_01_University_R_and_D_Protocols))

#### HW.7 — BQ25570 resistors verification
- **Джерело:** `02_03`
- **Опис:** CJMCU-25570 може мати Li-Po дефолт (VBAT_OV = 4.2V замість 5.5V для supercap)
- **Блокує:** Фіналізацію схеми, PCBA production
- [ ] 👤 Виміряти 8 резисторів мультиметром
- [ ] 👤 Порівняти з розрахунковою таблицею (Section 4 в `02_03`)
- [ ] 👤 Замінити SMD резистори якщо мисматч
- [ ] 👤 Задокументувати фінальні номінали

#### HW.8 — Pogo pin specification (7 блокерів)
- **Джерело:** `02_02`
- [ ] 👤 BLOCKER-1: Матеріал напилення piн → Gold (Hard Gold, Au 0.76 µm)
- [ ] 👤 **BLOCKER-1a (NEW 2026-05-16): Hard Gold ENIG на центральній площадці анкера** (торець виводу шини Zone 1, ø 4–5 мм) — **обов'язково**, інакше золотий pogo притискається до голого Ti → гальванічна пара Ti↔Au → Rc drift > 500 мОм за 18–36 міс → cold-start fail. Передати specмапу селективного gold-plating заводу (~$0.05/анкер). Деталі — `02_02 §1.2` ⚠️ блок.
- [ ] 👤 BLOCKER-2: Сила пружини → ~100 г/пін, Travel ≥ 1.5 мм
- [ ] 👤 BLOCKER-3: Механізм фіксації → Quarter-turn bayonet (рекомендовано)
- [ ] 👤 BLOCKER-4: O-ring → EPDM, CS 1.5-2.0 мм, 15-25% compression
- [ ] 👤 BLOCKER-5: Допуски соосності (XY-площина) → Lead-in chamfer
- [ ] 👤 **BLOCKER-6 (NEW 2026-05-16): 1D Tolerance Stack-Up по Z-осі** — обов'язковий розрахунок RSS або worst-case envelope для PCB→Radome→O-ring→Zone3 stack так, щоб O-ring завжди компресував 15-25% **і** Pogo Pin завжди в 50-70% страйку (0.76-1.06 мм з 1.52). Без цього ~10-30% капсул йде у брак (О-ring under-compressed → water ingress, АБО Pogo under-engaged → Cold-Start Fail). Деталі — `02_02 BLOCKER-6`. **P0** для PCBA/анкер/Радом freeze.

#### HW.9 — PCB KiCad layouts
- **Джерело:** `02_01`
- **Опис:** Soldier PCB та Queen PCB: "Не розпочато"
- [ ] 👤 Soldier PCB layout (KiCad)
- [ ] 👤 Queen PCB layout (KiCad)
- [ ] 👤 RF Keep-Out Zone verification

#### HW.11 — Conformal Coating (REVISED 2026-05-16: Sylgard відхилено через TinyML)
- **Джерело:** `02_01` BLOCKER-1, `02_02` §3.4
- **Опис:** Раніше планувався full-potting Sylgard 184 (Shore A < 50 проти crack кварцу при -20°C). Архітектурна рецензія виявила **критичний конфлікт**: Sylgard 184 — відомий **акустичний демпфер** (3-bands attenuation 15–25 dB @ 16 kHz), який глушить п'єзодиск Soldier для TinyML-детекції бензопили та кавітації ксилеми (`03_03`).
- **Нове рішення (v3):** **Parylene C 10 µm (CVD)** для серійного виробництва — конформне покриття всіх SMD-компонентів та припою через CVD-деposition; selective masking п'єзодиска (відкрита поверхня або тонка PDMS ≤ 10 µm); внутрішній об'єм капсули — повітря (опційно desiccant). Для прототипів TRL 4–5 — acrylic conformal (Humiseal 1A33) easily reworkable. ✅ Acoustically transparent, ✅ IP67 з O-ring.
- **Блокує:** Hardware freeze, IP67 certification, TinyML функціональність
- [ ] 👤 Обрати coating: Parylene C (production) + Humiseal 1A33 (prototypes)
- [ ] 👤 Контакт з CVD-сервісом Parylene-deposition (Київ / Львів — пошукати спеціалізовані PCB-house)
- [ ] 👤 Верифікувати п'єзо-attenuation: тест 16 kHz tone з/без coating на калібрувальному стенді
- [ ] 👤 Верифікувати з кварцовим резонатором при -20°C / +60°C (Parylene Shore D ~50, м'якший за air-gap воду)

#### HW.12 — EBFC upper voltage limit >5.5V protection
- **Джерело:** `02_01` BLOCKER-2
- **Опис:** При тривалій інсоляції EBFC може генерувати напругу >5.5V → overcharge supercap → деградація/вибух
- **Блокує:** Hardware safety, TRL 5
- [ ] 👤 Верифікувати BQ25570 OV protection threshold (VBAT_OV = 5.5V, див. HW.7)
- [ ] 👤 Додати TVS-діод або зенерівський обмежувач як backup

#### HW.13 — MPPT coefficient verification for EBFC
- **Джерело:** `02_03` BLOCKER-2 + Legacy notes
- **Опис:** Поточний MPPT = 50% VOC (R_OC1=R_OC2=10MΩ) — **занадто низько для EBFC**. EBFC (GOx/Laccase) має специфічну поляризаційну криву (Міхаеліс-Ментен + Тафель), MPP лежить у діапазоні 60-70% VOC. При 50% — зона масо-транспортних обмежень ферменту
- **Рекомендація (REVISED 2026-05-16 — TI convention):** Почати з 65%, з іменуванням за TI BQ25570 datasheet SLUSBH2G §8.2.3.2: **R_OC1 = 10.0 MΩ** (нижнє плече, VOC_SAMP → GND), **R_OC2 = 5.36 MΩ** (верхнє плече, VSTOR → VOC_SAMP). Формула: V_MPP / V_OC = R_OC1 / (R_OC1 + R_OC2). ⚠️ Не плутати позначення — якщо запаяти за зворотньою конвенцією, фракція стане 35% замість 65% → знекровлення ферменту.
- **Блокує:** Max EBFC power, optimal charge speed
- [ ] 👤 Зняти повну P-V криву (потужність-напруга) EBFC
- [ ] 👤 Виміряти VOC та VMP при різному освітленні (ранок/день/вечір, сезонно)
- [ ] 👤 Визначити оптимальну фракцію (починати з 65%)
- [ ] 👤 Якщо потрібно — замінити R_OC1/R_OC2 (звіряти з TI Figure 42 та `02_03 §4.А` SSOT Convention block)

#### HW.14 — Winter energy deficit for Queen Phase 3 (Starlink Mini)
- **Джерело:** `02_05` BLOCKER-2
- **Опис:** Phase 3 (Starlink Mini): 44 Wh/day consumption vs 18.75 Wh/day winter generation = -25 Wh/day deficit. 12V/20Ah LiFePO4 → 7.7 днів автономності
- **Пріоритет:** Phase 3 only (Phase 2.5 unaffected)
- [ ] 👤 Збільшити батарею до 40Ah (15 днів автономності), АБО
- [ ] 👤 Зменшити Starlink duty cycle до 1 хв/год (~9 Wh/day), АБО
- [ ] 👤 Встановити 100W solar panel

#### HW.15 — BMS + VBAT decoupling для SIM7070G
- **Джерело:** `02_05` BLOCKER-4, §2.2.1 (новий блок)
- **Опис:** SIM7070G TX peak current до 2A. Дві окремі проблеми: (1) BMS model не вказано в BOM (system-level); (2) транзієнтна просадка VBAT модему при 2A burst → brownout reboot (module-level). Тепер з обома вирішеннями.
- **Module-level fix (✅ specification зафіксовано 2026-05-16):** 5-cap tank bank біля VBAT pin SIM7070G — 470 µF aluminum polymer SP-Cap (Panasonic EEFCX0J471R) + 100 µF MLCC X7R 25V 1210 + 10 µF X7R 0805 + 100 nF X7R 0402 + 33 pF NP0 0402. Розрахункова просадка: 8 mV (margin > 35× проти 700 mV brownout). Деталі — `02_05 §2.2.1`.
- [ ] 👤 Обрати BMS: мінімум 12V / 20A continuous / 50A peak
- [ ] 👤 Обрати MPPT: мінімум Victron SmartSolar MPPT 75/15
- [ ] 👤 PCB layout: розмістити C_BULK ≤ 10 мм від VBAT pin, HF caps впритул
- [ ] 👤 Оновити BOM (закупка 5 нових компонентів)

#### HW.16 — Thermal management в IP67 enclosure
- **Джерело:** `02_05` BLOCKER-5
- **Опис:** SIM7070G + MCU при TX: ~500 mW × 5 sec. Літній interior temp до 60-70°C. LiFePO4 charging при T < 0°C пошкоджує батарею; розряд нижче −20°C → graphite plating damage
- ✅ Зроблено: тепловий бюджет IP67 (Phase 1/2.5 ~130мВт→ΔT<1K; Phase 3 3Вт→ΔT~4.5K; sun load +15K; sun-shade рекоменд.) + backend critical-temp гілка. Канон: `02_05 §4а`.
- [ ] 👤 Додати temperature sensor (NTC або DS18B20)
- [ ] 👤 Реалізувати hardware charge protection при T < 0°C

#### HW.17 — PEEK radome prototype (Деталь 4) — REVISED 2026-05-16
- **Джерело:** `02_01` §5.2 + `01_04` §5.5 + Legacy notes
- **Опис:** Деталь 4 (PEEK Crown / Капсула-Радом) — радіопрозорий купол ∅20–30 мм, який «насаджується» на зовнішню різьбу **Деталі 3 = Zone 3 = КАТОДНОГО ФЛАНЦЯ** (раніше документ помилково писав «Деталь 3 (Анод)» — критичний SSOT-bug, виправлено). Різьба або байонет + O-ring EPDM → IP68. Керамічна SMD-антена в ≥ 8 мм Z-clearance від Ti-фланця (`02_01 §5.3` revised — 2D ≥3мм, **3D ≥8мм** вертикально + overhang за периметр Ti). Anti-overgrowth shield: виступ ≥ 3 мм + R ≥ 5 мм + super-hydrophobic coating (Fluoropel PFC-1601V) — `01_04 §5.5`.
- **Блокує:** Ceramic antenna protection, RF performance validation, Zero-Touch Assembly validation, long-term cathode O₂ access
- [ ] 👤 KiCad PCB layout (HW.9) → PEEK radome dimensions
- [ ] 👤 Визначити тип кріплення: різьба на **Деталь 3 = Катод** (НЕ Анод!) vs байонет
- [ ] 👤 Визначити матеріал O-ring (EPDM vs FKM) для ксилемного середовища
- [ ] 👤 **HFSS-симуляція** з 3D-моделями Ti-фланця + PEEK-радома + чіп-антени (нова вимога 02_01 §5.3 revised) — VSWR < 1.8, gain ≥ −2 dBi
- [ ] 👤 Замовити PEEK прототип з виступаючим конусом ≥ 3 мм над корою + R заокруглення ≥ 5 мм (anti-overgrowth shield, `01_04 §5.5`)
- [ ] 👤 Super-hydrophobic coating: контакт із постачальником Fluoropel PFC-1601V або еквівалент, технологія nano-texturing
- [ ] 👤 Верифікувати RF performance (VSWR, КСВ) з антеною під радомом + з Ti-фланцем нижче (overhang тест)
- [ ] 👤 12-місячний польовий тест anti-overgrowth shield на тестовому дереві — фотодокументація щоквартально

#### HW.18 — Starlink DTC: ESP32-S3 vs SIM8200G-M2 WiFi co-processor
- **Джерело:** `02_05` BLOCKER-1
- **Опис:** Phase 3 (Starlink Mini terminal) потребує WiFi co-processor. Архітектурне рішення між ESP32-S3 та SIM8200G-M2 не прийнято
- **Пріоритет:** Phase 3 only
- ✅ Зроблено (🤖): decision memo + рекомендація **ESP32-S3** → `02_05` BLOCKER-1.
- [ ] 👤 Підтвердити рішення (рекоменд. ESP32-S3)
- [ ] 🤖 Оновити 03_02 з рішенням
- [ ] 🔗 Додати co-processor firmware до `firmware/`

#### HW.19 — VOC-діагностика деградації конденсатора (ADS1220 + TPS22860)
- **Джерело:** Legacy notes + `02_04` §4.2
- **Опис:** Раз на добу вимірювати чисту VOC EBFC (при від'єднаному навантаженні) для розрізнення "дерево хворіє" vs "конденсатор деградує". Обидва стани проявляються як зростання delta_t. ADS1220 (24-bit ADC) + TPS22860 (load switch) для прецизійного duty-cycling вимірювання. Для TRL 6 достатньо вбудованого 12-біт ADC STM32
- **Пріоритет:** TRL 8+ (після базової валідації в полі)
- [ ] 🤖 Валідувати концепт на вбудованому 12-біт ADC (firmware: GPIO disconnect EDLC → measure VOC → reconnect)
- [ ] 👤 Якщо 12-біт недостатньо — додати ADS1220 + TPS22860 до BOM
- ✅ Зроблено (🤖 verify, 2026-05-29): DCI-safe дизайн зафіксовано → `02_04 §4.2`. Попереднє «корекція моделі Лоренца» **зламало б DCI** (server-Z ≠ device-Z, бо firmware VOC не має → fraud-flag на кожному пакеті). Корекція має жити на slashing-шарі, не в Z.
- [ ] 🤖 Backend (gated): `voc_mv` колонка + VOC-корекція у `ContractHealthCheckService` (виключити hardware-confounded дерева зі slashing-підрахунку), **НЕ в `Attractor`**. Чекає firmware VOC-вимір + delivery-контракт.

#### HW.20 — Buffer Cap: Tantalum → MLCC migration
- **Джерело:** `02_03` §6 + Legacy notes
- **Опис:** Buffer Cap 100µF на лінії VOUT для LoRa TX peak. Рання специфікація вказувала танталовий конденсатор, але його струм витоку (1-10 мкА) подвоює/потроює E_sleep (1.5 мкА). Документація оновлена на MLCC X5R/X7R (виток ~десятки нА)
- ✅ Зроблено: DC bias derating (~20% @3.3V/6.3V → ~80µF ефективна, достатньо для 100мс LoRa TX піку). Канон: `02_03 §6`.
- [ ] 👤 Обрати конкретний part number: 100µF/6.3V X5R 1210 (напр. Murata GRM32ER60J107ME20)
- [ ] 👤 Додати до KiCad BOM (HW.9)

#### HW.21 — Hybrid energy R&D: TEG + Anchor stacking (post-TRL 6)
- **Джерело:** `01_03` §5 (Batch Integration Session 3)
- **Опис:** Future R&D для усунення зимового енергодефіциту без збільшення EDLC. Два **доповнювальні** (НЕ замінюючі) джерела: (a) TEG Bi₂Te₃ на стовбурі (~50–200 µW зимою при ΔT 15–25 K серцевина ↔ амбієнт), (b) послідовне з'єднання 3–4 анкерів (V_OC × 3–4 для кластерних/арктичних розгортань).
- **Пріоритет:** TRL 7+ (post field validation Phase 2.5). Поточна одно-анкерна архітектура задовольняє BQ25570 cold-start 330 мВ.
- **Не плутати з:** SolarBotanic «nano-leaves» — не інтегруємо без peer-reviewed per-node даних
- [ ] 👤 TEG: вибір модуля Bi₂Te₃ (4×4 см), стендовий тест ΔT-V кривої на тестовому стовбурі
- [ ] 👤 TEG: інтеграція з BQ25570 multi-input (можливість одночасного MPPT для EBFC + TEG)
- [ ] 👤 Stacking: 3-анкерна тестова конфігурація на одному дереві з PEEK-ізоляцією (Zone 2)
- [ ] 👤 Stacking: оцінка впливу на провіженінг (групова реєстрація DID) та Lorenz-аналітику (декомпозиція V_OC)
- [ ] 🔗 Залежить від HW.13 (P-V крива EBFC) для правильного бюджетування доповнення

#### HW.22 — Sterilization protocol (No EtO, Split-cycle + Aseptic, REVISED 2026-05-16)
- **Джерело:** `01_04` §6 (REVISED)
- **Опис:** Раніше — single-cycle terminal gamma 25 кГр в запакованому стані. **Виявлений архітектурний конфлікт:** PTFE-GDL мембрана (HW.25, Zone 3) зазнає chain scission при ≥10 кГр → крихкість, втрата bubble point → катод затоплюється першим дощем. Terminal gamma 25 кГр **неможлива** на готовому виробі з PTFE.
- **Нова стратегія (Split-cycle + Aseptic Assembly, `01_04 §6.3`):**
  - **ГІЛКА A — Ti-анкер з ферментами (без PTFE):** UV-C + 70% EtOH → low-dose gamma **15 кГр** (не 25) → SAL 10⁻⁶
  - **ГІЛКА B — PTFE-GDL + O-ring (окремо):** autoclave 121°C / 15 psi АБО EtO (без ферментів — EtO дозволено)
  - **ФІНАЛЬНА ЗБІРКА:** аcептична ламінація PTFE на Zone 3 у ISO Class 5 cleanroom; параметричний випуск за ISO 13408-1
- **Блокує:** Перехід від stage 3 (лабораторний прототип) до Stage 4 (польові випробування).
- [ ] 👤 ГІЛКА A: Тест активності ферментів **до та після** UV-C + 70% EtOH + **gamma 15 кГр** (не 25 кГр) — деградація ≤ 20%
- [ ] 👤 ГІЛКА B: PTFE-GDL bubble-point test до та після autoclave 121°C / EtO — Δ ≤ 5% (інтегральність мікропор)
- [ ] 👤 Фінальна збірка: ISO Class 5 cleanroom validation (particle counts, settle plates, finger dabs); bioburden ≤ 100 CFU перед F1
- [ ] 👤 CV-вимірювання EBFC-струму до/після ПОВНОГО циклу (A + B + Final) — деградація ≤ 25%
- [ ] 👤 Стерильність-тест USP <71>: TSB + FTM, 14 діб, відсутність росту фінального виробу
- [ ] 👤 LAL-тест на ендотоксини USP <85>: ≤ 0.5 EU/мл
- [ ] 👤 Обладнання: low-dose Co-60 (15 кГр) для ГІЛКИ A; autoclave або EtO chamber для ГІЛКИ B; ISO Class 5 LAF cabinet для аcептичної фінальної ламінації
- [ ] 👤 Постачальник Co-60: Чорнобиль НДІ радіаційної медицини / Київ ІРОНЦ — підтвердити можливість low-dose 15 кГр (не стандартної 25)

#### HW.23 — HIP postprocess specification for SLM anode
- **Джерело:** `01_02` §1.7 BLOCKER-3
- **Опис:** SLM-друк створює залишкові термічні напруження та внутрішню металургійну пористість. Без HIP (Hot Isostatic Pressing) ці дефекти стануть зародками втомних тріщин при 20-річному циклічному навантаженні.
- **Параметри:** 920°C ± 20°C / 100–150 МПа Ar / 2–4 год / контрольоване охолодження
- **Блокує:** Втомну міцність, 20-річну довговічність, TRL 5
- [ ] 👤 Передати специфікацію HIP-постпроцесу на завод (Київ/Дніпро) разом зі специфікацією SLM
- [ ] 👤 Перевірити наявність HIP-обладнання у заводу-кандидата (часто окремий підрядник)
- [ ] 👤 SEM/EDS до та після HIP — підтвердити закриття внутрішніх мікропустот
- [ ] 👤 Втомні випробування (Wöhler) у синтетичному ксилемному соку — еквівалент 5+ років фретингу

#### HW.24 — Staged validation gate (SLA → Ti-coin → full anchor)
- **Джерело:** `01_01` §6.1 BLOCKER-2
- **Опис:** Тризонний анкер — складна збірка. Передчасний перехід на DMLS-партію 100 шт. без верифікації базових принципів був методологічною помилкою. Цей блокер фіксує гейт: 100 анкерів замовляємо **тільки** після проходження двох попередніх етапів.
- [ ] 👤 **Stage 1 — SLA макети (5 шт):** друк прозорого фотополімеру (Form 3 або SLA-сервіс) для перевірки form & fit, ергономіки, Flush Mount step drilling, допусків press-fit «пластик-в-пластик»
- [ ] 👤 **Stage 2 — Ti-coins (~15 шт, ⌀10–15 мм або 10×10×1 мм):** SLM-друк + EAAE (з обов'язковим dehydrogenation bake `01_02 §1.3 Крок 5b`) → **Gen 2.0 анодний стек** (одношаровий dgrFAD-GDH + Os polymer в geniпin-chitosan-CNC матриці поверх fMWCNT, `01_03 §2.1`) + **Gen 2.0 катодний стек** (Laccase + nCoCuCeZIF nanozyme гібрид DET, `01_03 §2.2`) + **Nafion-g-PSBMA анти-resin coating** → in vitro CV/EIS у синтетичному ксилемному соку (рецептура від біо-хабу ЧНУ, [`08_01`](08_01_University_R_and_D_Protocols)). 30-day stability gate. Chloride tolerance test (0.25 М NaCl). UCST winter-lock тест (-10°C → +25°C цикл). 💡 **Electrode-дизайн:** замовити з «вушком» (отвір/виступ на краю) для кріплення потенціостат-кліпси без пошкодження активної площі (A_electrode = 2 см²). In-silico predictions для порівняння — `40_validate_vs_experiment.py` готовий. (`01_03 §3.7`)
- [ ] 👤 **Stage 3 — Full anchor (3–5 шт):** SLM+HIP анодних секцій, CNC PEEK-втулок, SLM/EBM катодних фланців, повний press-fit + EBFC у синтетичному соку
- [ ] 👤 **Stage 4 — Партія 100 шт:** після підтвердження Stage 3 — оптове замовлення для польових випробувань

#### HW.25 — PTFE-GDL membrane (Cathode)
- **Джерело:** `01_04` §5
- **Опис:** Газодифузійний шар для катодного фланця (Zone 3) — пропускає атмосферний O₂, блокує краплі води. Без коректної специфікації катод або задихається (опір O₂), або затоплюється (flooding) при дощі/росі.
- **Параметри:** e-PTFE або d-PTFE, розмір пор 0.2–1.0 µm, товщина 20–100 µm, крайовий кут > 110°
- [ ] 👤 Закупка зразків e-PTFE / d-PTFE (Gore-Tex industrial, Donaldson, або український постачальник)
- [ ] 👤 Стендовий тест breakthrough pressure: H₂O column 30 см → 1 м (повинна витримати ≥ 1 м)
- [ ] 👤 Електрохімічний тест: ORR-струм катода з PTFE-GDL vs без — порівняння продуктивності
- [ ] 👤 12-тижневий тест з імітацією дощу/росі — резистентність до flooding
- [ ] 👤 Сумісність O-ring (EPDM vs FKM) з PTFE та pH 4.5–5.5
- [ ] 👤 Метод ламінації PTFE на катодний фланець (без клеїв — механічний обтиск по периметру)

#### HW.26 — PEEK Cold-Flow Creep: Mechanical Lock (NEW 2026-05-16)
- **Джерело:** `01_01` BLOCKER-3 + §4.3
- **Опис:** PEEK як термопласт **повзе** під постійним hoop-stress press-fit на 5–10 років. Без mechanical lock через 10 років contact pressure падає на 60% → втрата герметичності O-ring + ризик вириву Zone 3 при штормі. Mandatory complementary fix до §4.2 ΔCTE розрахунку натягу.
- **Параметри:** Annular barbs (трикутні, h=0.25-0.4mm, α=30°/β=70°) на Zone 1 та Zone 3 контактних поверхнях + DIN 471 Ti retaining ring у канавках ∅0.8×0.6mm + hex tolerance ≤ 0.05mm radial. Press-fit при T = 150°C (>T_g PEEK 143°C) для barb engagement.
- **Cost impact:** ~$0.30/анкер (negligible vs $15-18 base DMLS cost)
- **Блокує:** Long-term reliability (20+ років), TRL 7→8 gate
- [ ] 👤 Update nTop CAD-моделі: додати annular barbs на циліндричних частинах Zone 1 та Zone 3
- [ ] 👤 Update CNC-чертежі: retaining ring grooves на anchor end Zone 1 + flange end Zone 3
- [ ] 👤 Закупка DIN 471 internal retaining rings Ti grade 2 (або 316SS) у відповідних розмірах
- [ ] 👤 Update press-fit процедуру: temp 150°C (>T_g PEEK 143°C для Victrex 450G) + контрольована сила 800–1200 N
- [ ] 👤 **FEA-валідація** ANSYS LS-DYNA з visco-elastic PEEK Prony model — simulation 10y creep, residual pull-out > 200 N
- [ ] 👤 Stage 1 SLA-mock (HW.24): включити barb-detail у фотополімерну збірку для перевірки клацання

#### HW.27 — Dehydrogenation Bake: Hydrogen Embrittlement Mitigation (NEW 2026-05-16)
- **Джерело:** `01_02` §1.3 Крок 5b + Failure Mode C
- **Опис:** EAAE (Крок 4) генерує атомарний H через реакції Ti+HCl/H₂SO₄; ультразвукова кавітація прискорює дифузію H у кристалічну ґратку Ti. Без вакуумного відпалу між промивкою (Крок 5) та пасивацією (Крок 6) поверхневий шар TPMS-гіроїда стає brittle (TiH₂) на глибину 5–50 µm → втомне руйнування при першому ж шторм-навантаженні.
- **Параметри:** Вакуумна піч 250°C ± 25°C, 10⁻³ mbar, 3 год (range: 200–300°C / 2–4 год). Обов'язково within 2 hours of rinse (H мігрує глибше при кімнатній T).
- **Контроль:** LECO RH404 vacuum hot extraction → H content < 100 ppm (ASTM B348 grade 5 ліміт 150 ppm).
- **Блокує:** Втомну міцність TPMS-гіроїда, заявлений термін служби 20+ років, TRL 4→5
- [ ] 👤 Передати специфікацію Крок 5b заводу-підряднику (Київ/Дніпро) разом із протоколом EAAE
- [ ] 👤 Перевірити наявність вакуумної печі 200–300°C у заводу-кандидата (або стороннього subcontractor)
- [ ] 👤 LECO RH404 hot extraction analysis на тестовому купоні з кожної партії
- [ ] 👤 Втомне тестування Ti-coin Stage 2 (HW.24) — порівняння з/без dehydrogenation bake для підтвердження ефекту

#### HW.28 — Anti-Overgrowth Shield для Zone 3 (NEW 2026-05-16)
- **Джерело:** `01_04` §5.5 + §2 Фаза 4 revision
- **Опис:** Поправка Фази 4 ксилемоінтеграції — анкер **НЕ повинен** повністю поглинатися стовбуром. Лише Zone 1 (анод) інтегрується; Zone 3 (катод) має залишатися постійно експонованим атмосфері для ORR (Laccase + AuNPs + O₂). Без shield через 3–5+ років нова кора накриває PTFE-GDL → дифузія O₂ зупиняється → EBFC мертва за 2–3 додаткових роки.
- **Три захисти (complementary):** (A) виступаючий PEEK Radome conus ≥ 3 мм + R заокруглення ≥ 5 мм; (B) super-hydrophobic fluoropolymer coating (CA > 150°, Fluoropel PFC-1601V); (C) periodic forester maintenance every 5–7 років (мікрорізець для зчищення приростаючої тканини).
- **Cross-ref:** Інтегровано у HW.17 (PEEK radome prototype) + OPEX додано у `07_02`
- **Блокує:** 20-річний термін служби EBFC, OPEX-розрахунок (`07_02`)
- [ ] 👤 Update PEEK Radome CAD з виступаючим конусом — у HW.17
- [ ] 👤 Закупка/тест super-hydrophobic coating (Fluoropel PFC-1601V або аналог)
- [ ] 👤 Field protocol для forester visit: процедура зачистки приростаючої тканини без traumatic surgery
- [ ] 👤 12-місячний польовий тест на тестовому дереві (Черкаський бір)
- [ ] 👤 Update `07_02` OPEX: 1 visit / 5–7 років × $20/visit = ~$3–4/рік/анкер (форестер у Черкаському борі)

#### HW.29 — Board-to-Board Connector pair: Power Deck ↔ RF Deck (NEW 2026-05-16)
- **Джерело:** `02_01` §3.1 (BOM поз. 12), §5.3
- **Опис:** Multi-deck PCB архітектура (Power Deck + RF Deck, standoff 8–10 мм) була специфікована у §5.3 без відповідного компонента у BOM. Без B2B-конектора RF Deck не отримує живлення 3V3 (Pogo Pins зайняті VIN_DC+GND). Тепер BOM включає Samtec FTSH header + CLT socket (1.27 мм pitch SMD, 8–10 мм stack) ~$0.85/пара.
- **Альтернатива (дорожча):** rigid-flex PCB замість двох плат + B2B (~+$1.50, але усуває механічну точку відмови).
- [ ] 👤 KiCad: place B2B footprints на обидві деки + перевірка signal integrity для 6-8 сигналів (3V3, GND, VSTOR_sense, EBFC_sense, piezo_EXTI, BQ25570 EN)
- [ ] 👤 Виміряти insertion loss + height variation на 5 зразках першої партії
- [ ] 👤 Pre-fabrication sanity check vs `HW.8 BLOCKER-6` (B2B stack height впливає на Z-tolerance envelope)

#### HW.30 — SMD Piezo + Acoustic Pad (Zero-Touch Wake) (NEW 2026-05-16)
- **Джерело:** `02_01` §6.2 (REVISED 2026-05-16)
- **Опис:** Раніше — клеєний ZP-3/ZP-5 ∅27 мм через-отворний з дротами до GPIO. **Порушення Zero-Touch §5.2:** клеєння + дроти ≠ робот pick-and-place. Pogo Pins вже зайняті VIN_DC+GND.
- **Нове рішення:** SMD-piezo (Murata 7BB-15-6L0 / TDK B-Series / Mallory MSR205P) на нижній стороні Power Deck + Bergquist Sil-Pad 1500ST (0.5–1.0 мм, Z_acoustic ≈ 1.5 МRayl ~ Ti) як coupling до Ti Zone 3. Сигнал через B2B (HW.29) до RF Deck → BAT54S → EXTI GPIO. Усе SMD; робот installs everything.
- [ ] 👤 Вибрати SMD-piezo з 3 кандидатів (Murata/TDK/Mallory), компроміс sensitivity vs пасивний voltage swing на резонансі ~4 кГц
- [ ] 👤 Acoustic coupling test: SMD-piezo + Sil-Pad + Ti-coin → подаючи 16 кГц tone через анкер → виміряти voltage spike на p'єзо vs стара ZP-3 архітектура
- [ ] 👤 Verify EXTI wake-on-vibration latency vs ZP-3 baseline (target < 5 мс)
- [ ] 👤 Lifecycle test: Sil-Pad creep під 30-40% compression × 20 років (Arrhenius accelerated)

---

## 🔐 Безпека

#### SEC.1 — Multisig Gnosis Safe для production admin role
- **Джерело:** `05_03` Operational Security
- **Опис:** `DEFAULT_ADMIN_ROLE` у production контрактах SCC/SFC має бути Gnosis Safe multisig (3/5 або 2/3), а не EOA
- **Пріоритет:** Before mainnet deploy
- ✅ Зроблено (🤖 prep): `Deploy.s.sol` ставить admin=Safe на genesis + `REQUIRE_SAFE_ADMIN` guard (revert якщо admin=EOA); runbook + cast-верифікація. Канон: `05_03 §Admin-Role → Gnosis Safe`. **Нічого не задеплоєно → reassign НЕ потрібен.**
- [ ] 👤 Створити Gnosis Safe wallet (3/5 або 2/3) на Polygon
- [ ] 👤 Деплоїти з `ADMIN_ADDRESS=<Safe>` + `REQUIRE_SAFE_ADMIN=true` (admin = Safe одразу)

#### SEC.2 — RDP Level 2 activation timeline
- **Джерело:** `03_05` NOTE-1
- **Опис:** Поточний стан: RDP Level 0 (development). Level 1 потрібен перед першою польовою партією, Level 2 — тільки після повної OTA верифікації (незворотній — лише OTA updates можливі)
- ✅ Зроблено: процедура активації RDP Level 2 (pre-flight + STM32CubeProgrammer CLI + rollout R&D→Pilot→Mass). Канон: `03_05 §3.6`.
- [ ] 🤖 Верифікувати OTA flow end-to-end
- [ ] 👤 Перейти на RDP Level 1 для field batch

#### SEC.3 — Factory Flashing pipeline
- **Джерело:** `03_05` NOTE-2
- **Опис:** Multi-step factory process: (1) Flash firmware з placeholder key, (2) Backend → HKDF(master_key, device_uid) → unique_key, (3) Robot пише key у protected Flash sector, (4) STM32CubeProgrammer → RDP Level 1/2
- **Блокує:** Mass production
- ✅ Зроблено: дизайн (Гілка A + B) + Rake-driven tool — `provisioning_sessions` AASM + 2-Person Rule; `app/services/factory_flashing/*` (MasterKeySource / CommandBuilder / Executor / AteccProvisioner / AuditTrail / Session); rake `factory:flash|approve|execute` (dry-run) + 63 specs (firmware-equivalence verified). Канон: `03_05 §3.4` + `§3.4г` (ops-security threat model: access control / anti-key-leak / audit-trail / Гілка A↔B).
- [ ] 👤 Реальний STM32_Programmer_CLI execution на bench (post-FW.2 HW gate); зараз `EXECUTE=1` шлях рейзить `ProgrammerMissingError` коли CLI відсутній у PATH
- [ ] 👤 Bitwarden Secrets Manager API live integration (`BitwardenAdapter#fetch_master_key` зараз raise `NotImplementedError`)
- [ ] 🔗 Реальний `cryptoauthlib` I²C для AteccProvisioner — після SEC.6 PCBA з ATECC608B

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **Джерело:** `03_05` NOTE-3
- **Опис:** Reed switch (магнітний сенсор) для zero consumption при транспортуванні. Магніт на коробці → circuit open. Інсталятор знімає магніт → first power-up. ~$0.05/unit. Дизайн approved, BOM не оновлений
- [ ] 👤 Додати Hamlin 59140-1-T-00-A reed switch + N52 neodymium magnet до BOM
- [ ] 👤 Оновити KiCad schematic

#### SEC.7 — OTA image автентифікація (cross-ref FW.23)
- **Джерело:** `03_05`, `03_02`
- **Опис:** OTA broadcast (mruby bytecode та потенційно firmware updates) не має цифрового підпису. Пов'язано з FW.23 але виділено як окремий security item через критичність.
- **Пріоритет:** P1 (перед першою OTA в полі)
- ✅ Зроблено (🟡 частково через FW.23): HMAC-SHA256 dual-gate (`OtaHmacKeyService` + `OtaPackagerService` + Soldier dual-gate + Queen relay). Лишається mbedTLS compute на STM32 (lab); Ed25519 — post-TRL 7. Канон: `03_05 §3.4б`.
- [ ] 🟡 mbedTLS HMAC-SHA256 compute на STM32 HASH peripheral — deferred до lab build (cross-ref FW.23)
- [ ] 🔗 Ed25519 key pair (Post-TRL 7, якщо SRAM бюджет дозволить після RTOS/FW.2 оптимізацій)

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **Джерело:** `03_05` | **Пріоритет: P0 (до будь-якого field deploy)**
- **Опис:** Аудит виявив: перші 4 слова production AES key **ідентичні публічно відомому** FIPS-197 Appendix B AES-128 test vector (стандартний тест-вектор зі специфікації NIST). Будь-який фахівець з криптографії може впізнати цей паттерн. При RDP Level 0 — trivial key extraction
- **Важливо:** Це ОКРЕМЕ від FW.1 (hardcoded key) — навіть після per-device provisioning, якщо master seed базується на цьому ключі, весь derivation tree скомпрометований
- ✅ Зроблено (guard): `Security::WeakKeyDetector` + boot-guard `master_key_strength_check.rb` — refuse-to-boot на FIPS-197/NIST/RFC/degenerate/placeholder vectors; 30 specs. Канон: `03_05 §3.1а`. (Заміна самого ключа — 👤 нижче.)
- [ ] 👤 Негайно замінити seed key на криптографічно стійкий random (hardware RNG або аудитований генератор)
- [ ] 👤 Задокументувати процес генерації нового master key у vault (Bitwarden/1Password) — **без коміту ключа в репозиторій**
- [ ] 👤 Після заміни: re-flash всі існуючі прототипи

## 📝 Документаційні невідповідності (DOC)

Потребують узгодження між docs, firmware та backend. **Не блокери виконання, але блокери для аудиту і онбордингу.**

DOC.9 — потребує лабораторного вимірювання TX-струму

| ID | Невідповідність | Документи / Файли | Дія | Статус |
|----|----------------|-------------------|-----|--------|
| DOC.1 | Документація AES master key суперечлива: `03_05` лінія 531-537 каже «навмисно не публікується», а лінія 538 натякає що перші 4 слова збігаються з FIPS-197 Appendix B test vector. Скоординувати після SEC.9 (заміна seed key) | `03_05`, `firmware/soldier/main.c:66-67` | Після SEC.9 видалити test-vector згадку, оновити обидва параграфи | ⏸️ Заблоковано SEC.9 |
| DOC.9 | Documentation `02_03` §9.3 raніше використовувала 15 mA/50 ms для LoRa TX. Виправлено на 120 mA/100 ms (~39 мДж) per SX1262 datasheet. Firmware energy accounting **не верифіковано незалежно** | `02_03`, `firmware/soldier/main.c` | Лабораторне вимірювання поточного TX (HW.x) + cross-ref у `02_03` після верифікації | ⏸️ Заблоковано лаб-стендом |

---

## ⚙️ Операційна автоматизація (OPS)

#### OPS.1 — TRL Auto-Advancement GitHub Action
- **Джерело:** `00_07` | **Складність: M**
- **Опис:** `trl_sync.yml` — GitHub Action що автоматично переміщує картки на Project Board при закритті issues з TRL-labels. Описаний як "на стадії впровадження" (TRL 7), але не реалізований. Потребує `secrets.PROJECT_PAT` з GraphQL project board permissions
- ✅ Зроблено: `.github/workflows/trl_sync.yml` (GraphQL Projects v2, user+org fallback; TRL≥5 gate per OPS.9). Канон: `00_07`.
- [ ] 👤 Створити `PROJECT_PAT` secret з project:write scope
- [ ] 👤 Тестування з тестовими issues

#### OPS.2 — SSOT Integrity Guard
- **Джерело:** `00_07` | **Складність: M**
- **Опис:** GitHub Action що блокує merge PRs якщо зміни в `app/models/` або `firmware/` не супроводжуються відповідними оновленнями в `docs/` або Wiki. Запобігає context drift між кодом та документацією
- ✅ Зроблено: `.github/workflows/ssot_guard.yml` (перевіряє app/models, firmware/*, contracts, app/services; bypass через `type:*` labels — `refactor`/`bugfix` НЕ обходять, OPS.9). Канон: `00_07`.
- [ ] 👤 Налаштувати як required check на `main` branch

#### OPS.3 — R&D Portfolio Management: Shape Up + cluster routing
- **Джерело:** `08_01` §1.1-1.3, `08_02` §1, `08_03`, `00_05` | **Складність: L** | **🤖 Методологія + Док**
- **Опис:** 25+ паралельних R&D-задач розподілені між 8+ науковцями (ChNU FOTIUS + ChDTU + ChIPB + ChMA + СЄУ). Поточно — ad-hoc розподіл. Запропоновано: 4-кластерна структура (A: Hardware/EBFC, B: Verification/Math, C: Scaling/Cloud, D: Compliance/Legal) + Shape Up 6-week cycles + Convolution Method для скорочення PN-state explosion 10-100×
- ✅ Зроблено: Shape Up cycle template (`00_05 §5`) + Projects V2 kanban-mapping (`00_07 §6`: R&D Cluster/Shape Up Stage/Cycle fields + labels + auto-routing). Лишається 👤 перший betting cycle після UNI.1/8. Канон: `00_05 §5`, `00_07 §6`.
- [ ] 👤 Перший betting cycle після UNI.1 (декан) та UNI.8 (СЄУ)

#### OPS.4 — GitHub Projects V2: семестрова синхронізація з ChNU/ChDTU
- **Джерело:** `00_07`, `08_01` | **Складність: M** | **🤖 Код**
- **Опис:** TRL-матриця прив'язана до seasons (Q1/Q2/Q3/Q4), але навчальний рік ChNU/ChDTU має семестри (вересень-грудень, лютий-травень). Без mapping — milestone-deadlines не синхронізовані з академічним календарем (наприклад, фінальні захисти магістерських у червні)
- ✅ Зроблено: семестр-мапінг (`00_07 §5`: Fall/Spring таблиці + TRL milestones + 15.VI deadline) + `trl_sync.yml` стемпить `Academic Semester` з `closed_at` (graceful no-op). Канон: `00_07 §5`.
- [ ] 👤 Узгодити календар з 8 науковцями ФОТІУС (UNI.2 — 8 зустрічей)
- [ ] 👤 Створити single-select field `Academic Semester` у Projects V2 + опції `Fall {Y}-{Y+1}` / `Spring {Y-1}-{Y}` на 3-5 років наперед

#### OPS.6 — Bootstrap scripts для GitHub Projects V2 + IaC initial sync
- **Джерело:** `00_07` §1.2 + §6 | **Пріоритет: P2** | **Складність: M** | **🤖 Код**
- **Опис:** `00_07` посилається на два планований скрипти, яких **не існує**: (1) `bin/setup_github_project.sh` — створює Projects V2 fields (`Current TRL`, `Target TRL`, `Assigned Agent`, `Module`, `Appetite`, `R&D Cluster`, `Shape Up Stage`, `Cycle`, `Academic Semester`) через `gh api graphql` (gh CLI не підтримує `project add-field` повністю); (2) `bin/bootstrap_github.sh` — orchestrate: label sync (через push, що тригерить `labels_sync.yml`) → fields create → first milestone (`Cycle 2026.QN`) → baseline shaping docs. Без них нові ВНЗ-партнери або deploy у форкований репозиторій вимагає ручного клікання у GitHub UI, що суперечить IaC філософії `00_07`.
- ✅ Зроблено: `lib/github_bootstrap.rb` (`GithubBootstrap::FIELDS` SSOT — 11 полів, TRL 1-9 + Readiness Horizon; idempotent GraphQL diff; rake `github:project_fields`/`bootstrap`; 16 specs). Канон: `00_07`, `00_04 §1`, `00_06 §7`.
- [ ] 👤 Запустити `bin/bootstrap_github.sh` проти живого Projects V2 при першому setup'і / в новому fork'у

#### OPS.5 — EU DMLS quotes від 2-3 backup підрядників
- **Джерело:** `07_02` §8.1.1 | **Складність: S** | **🔧 Операційна**
- **Опис:** BIZ.6 ✅ ідентифікував 4 EU кандидати (3D Lab PL, Materialise BE, Sauber CH/Lithoz AT, TRUMPF DE). Наступний крок — отримати quotes на пробну партію 10 шт. для benchmarking + frame agreement letter
- [ ] 👤 Запит quotes у 3D Lab PL (priority 1) + Materialise BE (priority 2)
- [ ] 👤 Заповнити порівняльну таблицю у `07_02` §8.1.1
- [ ] 👤 Letter of Intent / Frame Agreement з top vendor

#### OPS.9 — CI/CD workflow hardening (00_07 review, 2026-05-28)
- **Джерело:** `00_07` §2.2/§2.3/§2.5/§2.6 review (2026-05-28) | **Пріоритет: P2** | **Складність: M** | **🤖 Код**
- **Опис:** Рев'ю `00_07` виявило 4 розбіжності між специфікацією та реальними `.github/`-файлами + 1 stale-опис у цьому трекері. Doc-частину виправлено у `00_07`; workflow-файли синхронізовано з оновленою специфікацією (✅ 2026-05-28):

---

## 📋 Юридичні / Бізнес

#### BIZ.1 — 1 SCC = ? kg CO₂ ✅
- **Джерело:** `07_01`
- **Опис:** CO₂ еквівалент для 1 SCC — визначено: **2000 SCC = 1 tCO₂ (1 SCC = 0.5 кг CO₂)**
- ✅ Зроблено (2026-04-23): carbon coefficient per-species. Канон: `07_01`, `05_03`.
- [ ] 👤 Сертифікація методології (Verra VCS / Gold Standard) — потребує залучення методолога (Post-TRL 7)

#### BIZ.2 — B2B MSA (Master Service Agreement)
- **Джерело:** `07_01`
- **Академічний партнер:** СЄУ (Аблязов Д.Е., к.ю.н.) → [`08_07`](08_07_SEU_Economics_and_Legal_Integration) §1.3
- [ ] 👤 Організувати юридичну консультацію з Аблязовим Д.Е. (СЄУ) — MiCA, ERC-3643, RWA
- [ ] 👤 Створити юридичний шаблон MSA (Term Sheet + Carbon Credit Purchase Agreement)
- [ ] 👤 Review з практикуючим юристом

#### BIZ.3 — B2C ToS / Privacy Policy
- **Джерело:** `07_01`
- [ ] 👤 Terms of Service draft
- [ ] 👤 Privacy Policy (GDPR-compliant)
- [ ] 👤 Cookie Policy

#### BIZ.5 — Patent application
- **Джерело:** `08_03`
- [ ] 👤 Engagement з патентним адвокатом
- [ ] 👤 Патентна заявка на дизайн анкера

#### BIZ.6 — Supply chain war-zone risk mitigation
- **Джерело:** `07_02` | **Пріоритет: P1**
- **Опис:** DMLS manufacturing залежить від українських підрядників (Київ 3D Metal Tech, Дніпро ALT Ukraine, Черкаси SVS-ARTA) — зона активних бойових дій. Логістичні ризики, енергетичні перебої, мобілізація персоналу. Відсутній contingency plan з EU/US альтернативами
- ✅ Зроблено: `07_02 §8.1.1` Contingency Plan EU Backup DMLS Hubs (4 кандидати: 3D Lab PL / Materialise BE / Sauber CH+Lithoz AT / TRUMPF DE; triggers; +~20% payback). Канон: `07_02 §8.1.1`.
- [ ] 👤 Отримати quotes для порівняння вартості

#### BIZ.8 — EU DMLS Frame Agreement (extension of BIZ.6)
- **Джерело:** `07_02` §8.1.1 | **Пріоритет: P1**
- **Опис:** BIZ.6 ✅ ідентифікував кандидатів. Наступний рівень — формальний frame agreement з sample part quotes для активації при war-zone disruption. Без цього contingency — лише на папері (~3 місяці lead-time на onboarding нового підрядника якщо буде emergency)
- [ ] 👤 NDA + RFQ зі 3D Lab PL (priority 1)
- [ ] 👤 Sample part order (10 шт.) для quality benchmark vs UA-вендорів
- [ ] 👤 Frame Agreement: pricing locked at +20% premium з 30-day activation clause

#### BIZ.9 — Незалежний carbon credit методолог (Verra/Gold Standard)
- **Джерело:** `07_01` §3, `07_02` §7.3 | **Пріоритет: P2** (Post-TRL 7)
- **Опис:** BIZ.1 ✅ визначив `2000 SCC = 1 tCO₂` через ProtocolParameters. Для конвертації SCC з utility token у сертифіковані kg CO₂ для institutional buyers (ESG, retiring) — потрібна **independent methodology audit** від акредитованого реєстра (Verra VCS / Gold Standard / Puro.earth)
- [ ] 👤 Engagement акредитованого carbon methodologist (cost ~$50-100k)
- [ ] 👤 Подача Project Description Document (PDD) у Verra
- [ ] 🔗 Залежить від HW.3 (lab data Arrhenius) + UNI.6/UNI.7 (DFT + diffusion publications)

#### BIZ.10 — Multi-party IP Contract + NDA framework
- **Джерело:** `08_03`, `08_05`, `08_06`, `08_07` | **Пріоритет: P1**
- **Опис:** 5-сторонній партнерський фреймворк ChNU + ChDTU + ChIPB + ChMA + СЄУ + Silken Net. Потребує: (1) bilateral NDA з кожною установою для preprint sharing, (2) шаблон IP-договору щодо спільного авторства Q1 публікацій, (3) патентні права на анкер-дизайн/EBFC-протокол, (4) clear royalty structure при комерціалізації
- [ ] 👤 Залучити патентний повірений (Україна + EU)
- [ ] 👤 Bilateral NDA з кожною з 5 установ (паралельно з UNI.4-14)
- [ ] 👤 Master IP Framework Agreement (post-перших зустрічей)
- [ ] 🔗 Залежить від UNI.1 (декан) + UNI.8 (СЄУ) + UNI.9 (ChDTU) + UNI.12 (ChIPB) + UNI.13 (ChMA)

#### BIZ.11 — RWA pilot реєстрація лісової ділянки через Polygon Hadron
- **Джерело:** `07_01` BLOCKER-6 | **Пріоритет: P2**
- **Опис:** Hadron (ERC-3643 KYC/Compliance) — обраний шлях для RWA tokenization. Потрібна пілотна реєстрація **однієї** реальної лісової ділянки з: (1) кадастровими документами, (2) незалежною оцінкою біомаси (LIDAR + ground truth), (3) Hadron compliance attestation
- [ ] 👤 Знайти партнера-лісокористувача в Україні (post-war або Carpathian region)
- [ ] 👤 Кадастровий експерт + biomass appraisal company
- [ ] 🤖 Hadron integration spec: `Hadron::TokenizeForestPlotService` + KYC flow
- [ ] 🔗 Залежить від BIZ.2 (MSA template)

#### 🌿 BIZ.12 — Horizon Europe CLUSTER 6 заявка (Biodiversity Monitoring, Mongabay pivot)
- **Джерело:** `03_03` §10 + `08_03` Стаття 24a + E.59 | **Пріоритет: P1 (стратегічна заявка, post-publication)**
- **Опис:** Horizon Europe CLUSTER 6 — Food, Bioeconomy, Natural Resources, Agriculture and Environment, тематика _Biodiversity Monitoring_ (бюджет однієї дії 2–6 М€, terms 36–48 місяців). Mongabay/Delgado pivot робить Silken Net природним кандидатом: єдиний планетарний D-MRV проєкт з безперервною micro-acoustic верифікацією біорізноманіття на on-tree IoT-сенсорах. Заявка прив'язана до моменту, коли Стаття 24a (`08_03`) приймається до Q1-журналу — це переводить заявку з категорії «концепт» у категорію «published research» (вирішальна різниця для Horizon evaluators)
- [ ] 👤 Identify call topic (HORIZON-CL6-202X-BIODIV-* — щорічно оновлюється)
- [ ] 👤 Сформувати consortium: Silken Net (coordinator) + ЧНУ ФОТІУС (Бушин/Любченко) + ЧДТУ (Карапетян/Базіло/Бондаренко) + ЧНУ біо-хаб (Спрягайло/Гаврилюк) + 1–2 EU академічні партнери (рекомендовано: Linköping University через зв'язок Мінаєв-KTH/`08_01`, або іспанський CSIC bioacoustics group)
- [ ] 👤 Submission прив'язати до моменту acceptance Статті 24a (08_03) → "published research" status
- [ ] 🔗 Залежить від E.59 / FW.4-EXT (5-class TinyML модель — навіть на TRL 5 рівні достатньо для гранту)
- [ ] 🔗 Залежить від UNI.13a (Cherkasy Soundscape Library — preliminary data для Section "Methodology" заявки)

#### BIZ.13 — Slashing principal-agent: investor capital vs operator-bond (governance design)
- **Джерело:** `00_01` §6.2 (governance flag) | **Пріоритет: P2** | **Складність: M** | **👤 Governance + 🤖 Док/Код**
- **Опис:** Slashing категорії A (negligence) зрізає `wallet.locked_balance`, який належить **інвестору** — але недбалість (немає протипожежної смуги після алерту, Forester не приєднався до інциденту) зазвичай провина **оператора (Forester)**. Зрізати капітал інвестора за дії оператора порушує принцип principal-agent і демотивує інвесторів брати географічний ризик. Відкрите питання дизайну: лишити slash на investor `locked_balance` чи ввести окремий **operator-bond** (Forester стейкає власний депозит, що слешиться першим; можливий гібрид: bond → потім locked_balance).
- ✅ Зроблено (🤖): decision memo → рекомендація **hybrid operator-bond** (`00_01 §6.2.1`)
- [ ] 👤 DAO confirm: hybrid operator-bond (рекоменд.) vs investor-slash vs pure operator-bond
- [ ] 🤖 Якщо operator-bond — `OperatorBond` модель + `ProtocolParameters` запис + контракт-механіка
- [ ] 🤖 Синхронізувати фінальне рішення у `00_01 §6.2`, `05_03 §Slashing`, `04_02` (BlockchainBurningService)
- **Cross-ref:** `00_01 §6.2`, `05_03 §Slashing`, `04_02 §1.2` (BlockchainBurningService).

---

## 🎓 Академічні блокери (5 установ)

> **Поточний стан:** Партнерство з 5+ академічними установами — ChNU (фізико-хімія + ФОТІУС), ChDTU (Data Science + RF + акустика), ChIPB-NUTSU (пожежна безпека), ChMA (біохімія + токсикологія), СЄУ (правова + економічна архітектура). UNI.1-3, UNI.8 — раніше ідентифіковані; нижче — розширення на всі 5 установ.

#### UNI.1 — Перший контакт з деканом Онищенком (ChNU FOTIUS)
- **Джерело:** `08_01`
- **Блокує:** Всю лабораторну роботу, 10 публікацій, 11 магістерських
- [ ] 👤 Призначити зустріч
- [ ] 👤 Провести зустріч

#### UNI.2 — 8 зустрічей з факультетом ФОТІУС
- **Джерело:** `08_02`
- [ ] 👤 Супруненко (ПЗАС) — PN-verification, Convolution Method
- [ ] 👤 Онищенко (Декан) — stochastic B&B, Petri nets
- [ ] 👤 Ярмілко — Embedded Systems, ECDH key exchange
- [ ] 👤 Порубльов — Discrete Math, reliability
- [ ] 👤 Косенюк — RF/FEC/compliance
- [ ] 👤 Бушин — CNN/BSP/DMLS physics
- [ ] 👤 Осауленко — Portfolio management
- [ ] 👤 Любченко — GA/Neural Networks

#### UNI.3 — IP договір з ЧНУ
- **Джерело:** `08_03`
- **Блокує:** Старт публікацій
- [ ] 👤 Юридичне оформлення IP-договору
- [ ] 👤 Підпис обома сторонами

#### UNI.4 — ChNU школа Мінаєва: DFT-моделювання EBFC
- **Джерело:** `08_01` §1.1, `08_03` Стаття 1 | **Пріоритет: P1**
- **Опис:** Квантово-хімічна симуляція генерації потокового потенціалу на TiO₂-поверхні гіроїда + адсорбція органічних кислот ксилеми. Школа Мінаєва (ChNU) — світовий рівень DFT досліджень. Цільовий результат: стаття Q1 *Electrochimica Acta*. Блокує seed pitch deck (немає академічного credibility для EBFC механізму)
- [ ] 👤 Зустріч з представниками школи Мінаєва (через декана факультету хімії)
- [ ] 👤 NDA + IP framework (BIZ.10)
- [ ] 👤 Спільна заявка на грант MES Ukraine / Horizon Europe

#### UNI.5 — ChNU школа Гусака: дифузійна деградація 20-років (Kirkendall effect)
- **Джерело:** `08_01` §1.2, `08_03` Стаття 2 | **Пріоритет: P1**
- **Опис:** Математичне моделювання ефекту Кіркендалла на межі Ti-6Al-4V / xylem sap + 12-тижневий accelerated тест за Arrhenius (40°C). Школа Гусака — спеціалізація на diffusion-controlled corrosion. Цільовий результат: стаття Q1 *Corrosion Science*. Блокує investor-grade credibility щодо 20+ years longevity claim
- **Залежність:** HW.3 (Arrhenius test) — для emperichnoi верифікації моделі
- [ ] 👤 Зустріч зі школою Гусака
- [ ] 👤 Спільний експеримент з HW.3
- [ ] 👤 Co-authored paper draft

#### UNI.9 — ChDTU Карапетян: Data Science колаборація
- **Джерело:** `08_04` §1.1 | **Пріоритет: P1**
- **Опис:** ChDTU має R-кластер для тренування ML моделей. А.Р. Карапетян — головний кандидат для статистики телеметрії (anomaly detection, fraud), магістерські теми, спільні публікації
- [ ] 👤 Формальна зустріч з Карапетяном (cold contact через ChDTU rectorat)
- [ ] 👤 Узгодити кафедральну тему «Statistics of Bio-IoT Telemetry»
- [ ] 👤 2-3 магістерських теми на 2026-2027 academic year
- [ ] 🤖 SLA для R-кластеру (доступ для тренування `silken_forest.marshal` post-TRL 7)

#### UNI.10 — ChDTU Гончаров (ФЕТР): RF верифікація + EMC pre-compliance
- **Джерело:** `08_04` §1.2 | **Пріоритет: P1**
- **Опис:** А.А. Гончаров (ФЕТР ChDTU) має VNA + спектроаналізатор + anechoic chamber. Потрібен для: (a) VNA вимір SMD-антени під PEEK-радомом (HW.17 verification), (b) натурні Link Budget вимірювання у лісі (SF=7-9, 50/100/150/200/250 м), (c) EMC pre-compliance тести для CE/FCC (E.11)
- [ ] 👤 Формальна зустріч + access agreement до RF-лабораторії
- [ ] 👤 VNA-вимір 3-5 варіантів PEEK-кришки (товщина 1.5/2.0/2.5 мм)
- [ ] 👤 Link Budget field test (потребує польової експедиції)
- [ ] 🔗 Залежить від HW.9 (PCB) + HW.17 (radome prototype)

#### UNI.11 — ChDTU Базіло+Бондаренко (ПМКТ): акустична валідація фононної лінзи
- **Джерело:** `08_04` §1.3 | **Пріоритет: P2 (P1 для Mongabay pivot)**
- **Опис:** ПМКТ (Прикладна механіка + комп'ютерні технології) ChDTU — спеціалізація п'єзоелектрика + акустичні метаматеріали. Потрібно: EIS-характеризація п'єзодиска 25-150 кГц (TinyML cavitation detection), верифікація гіроїдного фокусування (phonon lens) для кавітації ксилеми. Цільовий результат: стаття Q1 *IEEE Transactions on Biomedical Engineering*. **🌿 Mongabay pivot (травень 2026):** ТЗ розширено — калібрувальний акустичний датасет повинен включати **записи лісового фону на світанку та в сутінках** (Cherkasy Soundscape Library) для тренування 5-го класу TinyML «Fauna Activity» (див. [`03_03` §10](../docs/03_03_TinyML_Acoustic_Inference), [`08_03` Стаття 24a](../docs/08_03_Joint_Publications_and_IP_Strategy))
- [ ] 👤 Формальна зустріч з Базіло + Бондаренко
- [ ] 👤 EIS-протокол для п'єзодиска (постачання зразка)
- [ ] 👤 Acoustic стенд-тест для гіроїда (cross-ref HW.1)
- [ ] 🌿 **dawn/dusk recordings (Mongabay):** методологія польових записів спільно з ЧНУ Біо-хабом (UNI.13a / Спрягайло-Гаврилюк) — AudioMoth-клас рекордери, 4 сезони, мінімум 30 хв на світанку + 30 хв у сутінках на ділянку, домінантні таксономічні групи labeled

#### 🌿 UNI.13a — ChNU Біо-хаб (Спрягайло+Гаврилюк): Acoustic Biodiversity Baseline (Mongabay pivot)
- **Джерело:** `08_01` §1.3 + §2 (Homeostasis Baseline крок 5) | **Пріоритет: P1 (новий, Mongabay)**
- **Опис:** Стаття Delgado et al. (Nicoya Peninsula, Costa Rica, 119 ділянок, 16 000 годин аудіо; огляд: *Mongabay News*, травень 2026) інструментально довела: NDVI бачить покрив, але не функцію екосистеми; dawn/dusk піки фауни — надійний маркер реального біорізноманіття. Українським аналогом цього дослідження стає **«Cherkasy Soundscape Library»** — польові записи на світанку та в сутінках Черкаського бору в усі 4 сезони, спільно з кафедрою ПМКТ ЧДТУ (UNI.11). Результат: ground truth для тренування 5-class TinyML моделі (FW.4-EXT) + co-authored Q1 publication ([`08_03` Стаття 24a](../docs/08_03_Joint_Publications_and_IP_Strategy))
- [ ] 👤 Формальна зустріч з О.В. Спрягайлом (проректор з науки) + М.В. Гаврилюком (директор ННІ природничих та аграрних наук)
- [ ] 👤 Узгодити участь студентів-біологів у польових експедиціях (наукова практика)
- [ ] 👤 Joint methodology workshop: ЧНУ біо-хаб + ЧДТУ ПМКТ — узгодження протоколу польових записів (рекордер, висота, тривалість, метадані)
- [ ] 👤 Перші expedition runs: 4 ділянки × 4 сезони × dawn+dusk → ~32 запису на baseline cycle
- [ ] 🔗 Manual labeling студентами (комахи / птахи / амфібії; інтенсивність 0–63) → labeled dataset для GA-оптимізації Любченком (UNI.6 / E.52-EXT)
- [ ] 🔗 Cross-validation з 10-річними даними стресових подій (Спрягайло) — external validation
- [ ] 🔗 Інтеграція у Horizon Europe CLUSTER 6 grant заявку (Biodiversity Monitoring) — підтримка BIZ-секції

#### UNI.12 — ChIPB-NUTSU: пожежна безпека + параметричне страхування
- **Джерело:** `08_05` | **Пріоритет: P1**
- **Опис:** Черкаський інститут пожежної безпеки + Національний університет цивільного захисту України (НУЦЗУ). Потрібно: (1) валідація тригерів параметричного страхування (FRP threshold, confidence levels — з dClimate flow), (2) розробка SOP для 7 типів EwsAlert (drought/insect_epidemic/vandalism/fire/seismic/fault/entropy), (3) інтеграція з ДСНС API (якщо існує)
- [ ] 👤 Cold contact з ректоратом ChIPB
- [ ] 👤 Перша зустріч + презентація fire-safety stack
- [ ] 👤 Joint SOP development workshop (cross-ref ARCH.31)
- [ ] 🔗 Залежить від UNI.14 (СЄУ legal) для structuring параметричного страхування

#### UNI.13 — ChMA: біохімія EBFC + токсикологія
- **Джерело:** `08_06` | **Пріоритет: P2**
- **Опис:** Черкаська медична академія (ChMA). Потрібно: (1) валідація **dgrFAD-GDH + Laccase/ZIF-nanozyme** інгібіції при pH ксилеми (4.5-5.5) (Gen 2.0 baseline, `01_03`), (2) токсикологічні тести іонів Ti/Al/V (поглинання деревом, безпека для ecosystem), (3) **геніпін cross-linking** як нетоксична альтернатива глутаральдегіду — біосумісність тести. **⚠️ Посади науковців у docs не верифіковані** через офіційний сайт ChMA — критичний блокер
- [ ] 👤 **СПОЧАТКУ:** Верифікувати посади всіх науковців ChMA через офіційний сайт
- [ ] 👤 Cold contact з ректором ChMA
- [ ] 👤 Joint biochemistry protocol для EBFC Gen 2.0 (cross-ref HW.5)

#### UNI.14 — СЄУ: токеноміка RWA + правова архітектура
- **Джерело:** `08_07` | **Пріоритет: P1**
- **Опис:** Розширення UNI.8. СЄУ — національний університет; потрібно: (1) MSA/Term Sheet для B2B контрактів (Аблязов Д. — право, к.ю.н.), (2) KYC/AML процес для юридичних осіб (Hadron flow), (3) структура DAO як юридичної особи (cooperative? Swiss Verein?), (4) ESG Accounting Framework (Ус Г.О. — облік). **⚠️ Посади 7 науковців СЄУ потребують верифікації** через офіційний сайт
- [ ] 👤 Перша зустріч з Чудаєвою (ректор) або Аблязовою Н. (президент) — UNI.8
- [ ] 👤 Верифікувати посади та наукові профілі всіх 7 науковців СЄУ
- [ ] 👤 Меморандум про співпрацю СЄУ ↔ Silken Net
- [ ] 👤 Joint workshop: Аблязов Д. (право) + Silken Net legal → MSA шаблони
- [ ] 👤 Joint workshop: Ус Г.О. (облік) → ESG Accounting Framework

#### UNI.8 — Перший контакт з ректоратом СЄУ (legacy ID — see UNI.14)
- **Джерело:** `08_07`
- **Блокує:** Economic Whitepaper, Legal Framework, NaaS юридичні шаблони (07_01 BLOCKER-1, BLOCKER-3)
- [ ] 👤 Перша зустріч з Чудаєвою (ректор) або Аблязовою Н. (президент)
- [ ] 👤 Верифікувати посади та наукові профілі всіх 7 науковців через офіційний сайт СЄУ
- [ ] 👤 Підписати Меморандум про співпрацю між СЄУ та Silken Net
- [ ] 👤 Організувати спільну зустріч: Аблязов Д. (право) + юрист Silken Net → MSA шаблони
- [ ] 👤 Організувати спільну зустріч: Ус Г.О. (облік) → ESG Accounting Framework

#### UNI.15 — ЧНУ TISC engagement (патентний захист анкера + торгові марки)
- **Джерело:** `08_03 §2.1.1` | **Пріоритет: P1** | **Складність: M** | 🔗 **Заблоковано:** UNI.1 (парасольовий MoU ЧНУ↔Silken Net)
- **Опис:** Замість найму комерційного патентного бюро (~$3–8k за UA заявку), використати **TISC при ЧНУ** (Technology and Innovation Support Center, WIPO-мережа, координує УкрНОІВІ). Сервіси: (1) prior art search для коаксіального гіроїдного анкера Ti-6Al-4V + PEEK у Espacenet/PATENTSCOPE/Google Patents; (2) консультації з оформлення патентних заявок UA→PCT→EU/US; (3) реєстрація торгових марок (SilkenNet™, Gaia 2.0™, SCC™); (4) тренінги команди з патентного аналізу. Вартість: лише офіційний збір УкрНОІВІ (~5–10k UAH). **Caveat:** TISC консультує, але саму подачу заявки робить **патентний повірений** — TISC може порадити кандидата зі своєї мережі за rate нижчий за комерційний.
- [ ] 👤 Перший контакт з директором TISC ЧНУ (через ректорат, проректора Спрягайла)
- [ ] 👤 Auxiliary MoU про послуги TISC у рамках парасольового MoU ЧНУ↔Silken Net
- [ ] 🤖 Зібрати prior art search query-set (коаксіальний гіроїд, EBFC mediator, LoRa mesh)
- [ ] 👤 Запросити TISC prior art search для дизайну анкера
- [ ] 👤 Знайти патентного повіреного через TISC мережу
- [ ] 👤 Подати UA utility model на дизайн анкера (пріоритетна дата фіксована)
- [ ] 👤 PCT-розширення через 12 місяців (Phase 2, post-TRL 6)

#### UNI.16 — ЧНУ Кафедра ІВ engagement (юридична експертиза RWA + токеноміки)
- **Джерело:** `08_03 §2.1.2` | **Пріоритет: P1** | **Складність: L** | 🔗 **Заблоковано:** UNI.1 (MoU)
- **Опис:** Кафедра Інтелектуальної Власності та Цивільно-Правових Дисциплін ЧНУ дає UA-юрисдикційну верифікацію двох доменів, де СЄУ §1F дає макро/regulatory shape, але потрібен **точковий UA-юридичний review**: (1) RWA-токенізація лісу через ERC-3643 — сумісність з Лісовим Кодексом та Законом «Про природно-заповідний фонд»; (2) класифікація SCC/SFC за Законом «Про віртуальні активи» 2022 + MiCA-imports 2024; (3) юридична природа NaaS-контрактів у UA Civil Code; (4) авторське право на `bio_contract.rb` / `SilkenNet::Attractor` як комп'ютерної програми. Очікувані результати: 2 меморандуми (RWA + Tokenomics).
- [ ] 👤 Перший контакт з зав. кафедри ІВ ЧНУ (через ректорат)
- [ ] 👤 Joint workshop з Аблязовим Д.Е. (СЄУ) для координації UA × EU/MiCA рамок
- [ ] 👤 Меморандум "Юридична допустимість токенізації UA-лісу через ERC-3643" — розблоковує `07_01` BLOCKER-6
- [ ] 👤 Меморандум "Класифікація SCC за Законом про віртуальні активи; compliance roadmap"
- [ ] 👤 Sui generis review NaaS-контракту як цивільно-правового інституту

#### UNI.17 — ChDTU Хоменко (Кафедра металорізальних верстатів): прецизійна механіка + DMLS post-processing
- **Джерело:** `08_04 §1.4` | **Пріоритет: P2** | **Складність: M**
- **Опис:** Заслужений винахідник України (80+ патентів) — закриває непокриту вертикаль ЧДТУ: прецизійна обробка, нестандартний інструмент, оптимізація різьби анкера для живої деревини. Cross-ref `01_01` (geometry), `01_02` (DMLS), `02_02` (installation tooling), `08_05 §1.5 Несен` (deinstall кооперація). Plus: патентний аудит дизайну анкера.
- [ ] 👤 Перший контакт (через ChDTU rectorat)
- [ ] 👤 Узгодити патентний аудит дизайну анкера (UNI.15 cross-ref)
- [ ] 👤 Прототипування різальної геометрії в machine shop ЧДТУ

---

## 🌐 External Stakeholders (B2G/B2B/Cultural — non-academic outreach)

> **Поточний стан:** Зовнішні залежності виокремлені в [`04_07`](04_07_Cultural_Layer_External_Stakeholders) (Cultural Layer) та [`07_04`](07_04_B2G_External_Stakeholders) (B2G/B2B Matrix). Це не операційні залежності hot-path — це outreach pool, що активується за TRL-тригерами у відповідних модулях. Імена нижче — публічна інформація; контакти живуть у gitignored CRM.

#### STK.1 — Tier 1 B2G: Дзюбенко (ДП "Ліси України") — легальний доступ до Черкаського бору
- **Джерело:** `07_04 §2.1` | **Пріоритет: P1** | **Складність: M**
- **Trigger:** TRL 5 у `01_01` (фізичний прототип анкера готовий до польового тесту).
- **Опис:** Найважливіший B2G-контакт — Заслужений лісівник + д.е.н. + проф. ЧДТУ. Підпис розблокує експериментальний полігон у держлісі без багаторічної бюрократії. Бекенд-канал — через `08_04` (ЧДТУ MoU).
- [ ] 👤 Verify current title and contact via ChDTU rector channel
- [ ] 👤 First meeting brief (NaaS pitch + ESG/FSC argument)
- [ ] 👤 Договір про науковий полігон (Pilot Site MoU)
- [ ] 👤 Координація з UNI.6 (Спрягайло) для ПЗФ-сумісності

#### STK.2 — Tier 1 B2G: Сегеда (ДП "Смілянське ЛГ") — еко-аудит + Геронимівка
- **Джерело:** `07_04 §2.2` | **Пріоритет: P1** | **Складність: M**
- **Trigger:** після STK.1 first meeting.
- **Опис:** Заслужений природоохоронець, проживає в Геронимівці (центр Genesis-кластера). Експертний еко-аудит проєкту + наступний крок розширення в Смілянщину.
- [ ] 👤 First contact letter (cross-link з UNI.6 Спрягайло для ПЗФ context)
- [ ] 👤 Біосумісність висновок (LoRaWAN radio + CODIT)
- [ ] 👤 DAO advisory role offer (Proof of Growth oracle validation)

#### STK.3 — Tier 1 B2G: Заслужений юрист — Legal Wrapper для SCC
- **Джерело:** `07_04 §2.4` | **Пріоритет: P1** | **Складність: L** | 🔗 **Заблоковано:** UNI.16 (Кафедра ІВ ЧНУ), UNI.14 (СЄУ Аблязов)
- **Опис:** Перекласифікація Soldier-анкера з "втручання" на "науково-вимірювальний прилад" — перш ніж приходить прокуратура. Конкретне ім'я ще не верифіковане; кандидати через ННІ економіки і права ЧНУ (Кирилюк, `08_01 §1.4`).
- [ ] 👤 Identify candidate (via Кирилюк + Аблязов)
- [ ] 👤 Узгодити запит на legal opinion з UNI.16 framework

#### STK.4 — Tier 1 B2G: Землевпорядник (TBD) — RWA кадастр oracle
- **Джерело:** `07_04 §2.3` | **Пріоритет: P2** | **Складність: M**
- **Trigger:** TRL 6 у `05_02` (RWA tokenization pipeline ready).
- **Опис:** Сервітут під Queen-щоглу + кадастровий oracle для смарт-контрактів. Ім'я не верифіковане (Сіроштан згадувалась з застереженням — перевірити через юр. канал).
- [ ] 👤 Identify candidate (cross-ref Аблязов УNI.14)

#### STK.5 — Tier 3 Certification: Чорней (ДП "Черкасистандартметрологія") — SCC certification
- **Джерело:** `07_04 §4.1` | **Пріоритет: P1** | **Складність: L**
- **Trigger:** TRL 6 у `05_02`; критичний gate для CBAM-юридичного статусу SCC.
- **Опис:** Сертифікація Soldier як засобу вимірювальної техніки + дрейф-компенсація + audit сумарної похибки D-MRV. Без цього SCC = "цифри з інтернету".
- [ ] 👤 Verify Chorney current status (active vs retired)
- [ ] 👤 First meeting brief: SCC ↔ ДСТУ ↔ BIPM/OIML pathway
- [ ] 👤 Засіб вимірювальної техніки registration roadmap

#### STK.6 — Tier 4 B2B: ПрАТ "Азот" — CBAM offset + хімічний scale-up
- **Джерело:** `07_04 §5.2` | **Пріоритет: P2** | **Складність: L**
- **Trigger:** TRL 7 у `05_02` (live SCC mint).
- **Опис:** Першочерговий великий B2B-клієнт SCC (CBAM offset). Також канал на хімічний scale-up осмієвих полімерів для EBFC. Іменовані: І. Кухоль, О. Хуторний.
- [ ] 👤 ESG officer Azot — first cold contact
- [ ] 👤 CBAM economic model (cross-ref `07_02`)
- [ ] 👤 EBFC chemical scale-up feasibility (cross-ref `08_06`)

#### STK.7 — Tier 5 Social Inclusion: Кучер (соц. сфера) — Horizon Europe Cluster 4/6
- **Джерело:** `07_04 §6.1` | **Пріоритет: P2** | **Складність: M**
- **Trigger:** перед подачею великого Horizon Europe гранту (cross-ref `07_03`).
- **Опис:** Соціальна інклюзія для grant-пріоритету + кадровий резерв розгортання + Eco-Therapy 4.0 для ветеранів.
- [ ] 👤 First contact (via обласну раду каналом)
- [ ] 👤 Eco-Therapy concept paper (deferred — потребує mobile UI у `04_04`)

#### STK.8 — Cultural Tier A (Cherkasy 8 artists): pre-Genesis NFT outreach
- **Джерело:** `04_07 §2.1` | **Пріоритет: P3** | **Складність: M**
- **Trigger:** TRL 7 у `05_02` + Genesis cluster onchain.
- **Опис:** 8 черкаських митців (Бабак, Теліженко, Афонін, Бондар, Іщенко, Олексенко, Касьян, Гладько). Активний канал через А2 Теліженко (вже в `08_07 §1.7`).
- [ ] 👤 Pre-screen список: verify life status + active работа
- [ ] 👤 Через А2 Теліженко — collective interest probe
- [ ] 👤 Name & Likeness Release framework (UNI.14 Аблязов)

#### STK.9 — Cultural Tier B (National 8 artists): pre-launch outreach
- **Джерело:** `04_07 §2.2` | **Пріоритет: P3** | **Складність: L**
- **Trigger:** TRL 8 у `05_03` (Genesis NFT smart-contracts ready).
- **Опис:** 8 національних митців (Марчук, Чебаник, Микита, Сидоренко, Медвідь, Гуменюк, Гуйда, Ковтун). Більшість — старша когорта; критично зафіксувати window. Hand-off: PR-агентство, не CTO.
- [ ] 👤 Verify life/health status all 8 (через відкриті джерела)
- [ ] 👤 Identify gallery/agent для кожного
- [ ] 👤 Pitch package: technical brief + animation concept

#### STK.10 — Cultural Tier C (Media): Калініченко / Душок (ТРК Ільдана) — PR shield
- **Джерело:** `04_07 §2.3` C2/C3` | **Пріоритет: P2** | **Складність: S**
- **Trigger:** перед першою публічною інсталяцією анкера у борі.
- **Опис:** Превентивний інформаційний фон проти екопанік ("чіпуют дерева" типу). Калініченко — викладач ЧНУ, природний міст із `08_01`.
- [ ] 👤 Через ЧНУ rectorat (Кирилюк, `08_01 §1.4`) — узгодити перший контакт
- [ ] 👤 Документальний міні-сюжет про DMLS-друк анкера (post-prototype)

---

## 💡 Додаткові знахідки (не блокери)

| # | Знахідка | Джерело | Примітка |
|---|----------|---------|----------|
| E.3 | Breadboard video відсутнє (для грантів) | `07_03` | Зняти відео |
| E.4 | Helium Network fallback — concept є, реалізації немає | `02_05` | Дизайн + реалізація |
| E.5 | CoAP listener Ruby — масштабується до ~10k вузлів | `06_01` | Series D: Rust/Go proxy |
| E.7 | dClimate mock mode — потрібна реальна інтеграція для Production | `05_01` | Пов'язано з S3.2 |
| E.9 | DMA SPI optimization — зменшення енергоспоживання (Vector 1 — Ярмілко) | `08_02` | R&D partnership |
| E.10 | Kalman/EMA filtering для delta_t noise suppression (±8% → ±1.2%) | `08_02` | R&D partnership |
| E.11 | CE/FCC/EMC/IP68 certification roadmap не розпочато | `08_02` | Потребує Косенюк (RF) |
| E.12 | Boolean minimization TX decision conditions (Karnaugh/Quine-McCluskey) | `08_02` | Потребує Любченко |
| E.13 | Petri Net model of Rails monolith — deadlock-free verification at 10k concurrent IoT | `08_02` | Потребує Супруненко |
| E.14 | Multi-source satellite + anchor data fusion (Sentinel-2 NDVI) | `08_02` | Потребує Любченко + Бушин |
| E.15 | Reed-Solomon FEC або Hamming для LoRa error correction | `08_02` | Потребує Косенюк |
| E.18 | 10 запланованих Q1 публікацій — blocked by lab data | `08_03` | Blocked by UNI.1-3 |
| E.19 | 8 магістерських — blocked by TRL 4 advancement | `08_03` | Post-TRL 4 |
| E.20 | Forester Guild (Proof-of-Physical-Work) — planned post-TRL 6 | `04_02` | Post-TRL 6 |
| E.26 | `health_trend` field для TelemetryLog — predictive degradation | Legacy | Post-TRL 6, потребує E.10 (Kalman) |
| E.27 | Chaos Engineering: Chaos Mesh для Akash або kill-scripts для Kamal | Legacy | Post-TRL 7, production hardening |
| E.29 | Альтернативні EBFC медіатори (ferrocene, methylene blue) | `01_03` | R&D alternatives |
| E.30 | InsightGenerator: кліматичні базлайни per region | `04_02` | Post-TRL 7 |
| E.31 | TinyML OTA: `.tflite` формат (INT8 quantization) + Python ML microservice | `03_03` | Post-TRL 8 |
| E.32 | ✅ (Slither + Foundry) Smart Contract Audit: Slither в CI (`.github/workflows/solidity_audit.yml`). Foundry toolchain (`contracts/foundry.toml`): solc 0.8.28, EVM cancun, optimizer 200 runs, CI/production profiles. 178 тестів у 6 test suites. Coverage via `forge coverage --ir-minimum`. Mythril + Hacken — окремі етапи pre-mainnet | `05_03` | Slither CI ✅ (Сесія 19-20), Foundry tests ✅ (Сесія 22-23), Mythril + Hacken TODO |
| E.33 | AlertNotification rate limits: FCM multicast (500 tokens/req), Twilio Notify | `04_02` | Post-TRL 8 |
| E.34 | dClimate fallback → ForestBountyService (drone/ranger PoPhW) | `04_02` | Post-TRL 6 |
| E.36 | PostGIS Generated Column (geo_boundary) замість тригера | `04_01` | Post-TRL 8 |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates | `04_01` | >100M рядків/місяць |
| E.38 | Press-Fit фаски: R ≥ 0.2 мм для зняття напружень у PEEK + **annular barbs (h=0.3mm)** на Zone 1 та Zone 3 контактних поверхнях для PEEK creep mechanical lock (`01_01 §4.3`, HW.26) | `01_01` | Включити у nTop (HW.1, HW.26) |
| E.39 | **EBFC Gen 2.0 (BASELINE, REWRITTEN 2026-05-22):** dgrFAD-GDH (deglycosylated) + Laccase/ZIF-nanozyme + Genipin-Chitosan-CNC матриця + Nafion-g-PSBMA цвітеріонна мембрана. 20–25 років. Gen 1.0 (GOx+CAT+GA+PEG) виключена як нежиттєздатна. | `01_03` §1–3 | ЧНУ lab testing |
| E.40 | **Ignion Virtual Antenna™:** NN02-310 як альтернатива Yageo/Taoglas 868 МГц | `02_01` §5 | Evaluation kit + VSWR тест |
| DIFF.1 | `Wallet#lock_and_mint!` threshold = runtime param (не hardcoded) | `04_02` | Informational, no action |
| E.41 | **Fire events delayed 48h** via dClimate satellite obscuration — **⚠️ life-safety risk**. Mitigation: Forester Guild as Fallback Oracle (E.20) + immediate local broadcast via panic TX (не чекати satellite clearance при chainsaw detection). **Пріоритет: P1** (не відкладати на Post-TRL 6) | `04_02`, `05_01` | P1: interim emergency fallback |
| ✅ E.45 | **SCC/SFC contract addresses** = `0x0000...0` в subgraph.yaml — блокує deploy subgraph на testnet/mainnet. **Статус (2026-05-17):** додано `subgraph/validate_addresses.sh` — fail-fast скрипт, який перевіряє відсутність нульових адрес перед `graph deploy`. Запускати: `./subgraph/validate_addresses.sh && graph deploy`. Адреси залишаються `0x0000...0` до деплою контрактів через Foundry (instructed в subgraph.yaml comments). | `05_03` | ✅ Guard-скрипт додано; адреси = placeholder до контрактного деплою (S3.5) |
| E.48 | **The Graph subgraph на testnet `polygon-amoy`** — потребує mainnet deploy перед production | `05_01` | Post mainnet deploy |
| E.50 | **Edge fuzzy_distance dedup function** на STM32WLE5JC: <1 мс CPU, <128 байт RAM, ціль — 30-40% TX зниження за рахунок suppression near-duplicate пакетів | `08_02` §1.3 (Vector 1, Ярмілко) | Post-TRL 7 (R&D — Ярмілко) |
| E.51 | **Monte Carlo TTL-flood симуляція** для обґрунтування `PANIC_TTL=5` та `DEFAULT_TTL=3`: цільовий P_delivery ≥ 0.99 при 20-30% одночасних відмов вузлів. Виходи: math-обґрунтування для seed deck | `08_02` §1.2 (Vector 2) | Post-TRL 6 (Порубльов, ЧНУ) |
| E.52 | **GA-оптимізація ваг `silken_forest.marshal`** ML моделі на Akash GPU кластері — генетичний алгоритм для `InsightGeneratorService` stress_index класифікації | `08_02` §1.6 (Любченко) | Post-TRL 7 |
| E.53 | **VNA-вимір SMD-антени під PEEK радомом** — VSWR <1.5 на 868 МГц для 3-5 варіантів товщини PEEK (1.5/2.0/2.5 мм) у вологому/сухому стані + **3D Keep-Out з Ti-фланцем нижче** (Z-clearance 5/8/12 мм, з/без overhang за периметр Ti). Лабораторна задача (cross-ref UNI.10 ChDTU Гончаров, нова вимога `02_01 §5.3` revised) | `08_02` §1.3 + `02_01` | P1, blocked by HW.17 + UNI.10 |
| E.54 | **SOP документи для 7 типів EwsAlert** — стандартизовані інструкції UA+EN: severe_drought, insect_epidemic, vandalism_breach, fire_detected, seismic_anomaly, system_fault, entropy_anomaly. Інтеграція як inline UI у Phlex (cross-ref ARCH.31) | `08_05` | P1, joint with ChIPB-NUTSU (UNI.12) |
| E.55 | **Multi-party NDA + IP framework** для 5-сторонньої академічної співпраці (ChNU + ChDTU + ChIPB + ChMA + СЄУ + Silken Net) — base-line для всіх UNI.x публікацій | `08_03`, `08_05`, `08_06`, `08_07` | P1, cross-ref BIZ.10 |
| E.56 | **DSP preprocessing для TinyML** — невідомо чи модель очікує raw time-domain чи MFCC. Якщо MFCC → +5-15 KB Flash + 40 µs CPU (CMSIS-DSP) | `03_03` BLOCKER-5 | P1, cross-ref FW.25 |
| E.57 | **TENSOR_ARENA_SIZE budget verification** — ніколи не виміряно через `arm-none-eabi-size`. Ризик stack overflow якщо > 46 KB | `03_03` BLOCKER-3 | P1, cross-ref FW.26 |
| E.58 | **Lorenz state continuity** після brownout: документація specifies повний (x,y,z) save в RTC Backup, але недостатня формалізація first-boot vs continuation logic. Магічний marker `LZST` (0x4C5A5354) реалізовано — потребує канонічної таблиці RTC layout | `03_04`, `03_01` | P2, cross-ref DOC.3, DOC.4 |
| 🌿 E.59 | **Mongabay biodiversity pivot — acoustic D-MRV** — стратегічний pivot Silken Net від карбонового MRV до повноцінного D-MRV біорізноманіття після Delgado et al. (Nicoya Peninsula, 119 ділянок, 16 000 год аудіо; *Mongabay News*, травень 2026). Включає: (1) FW.4-EXT 5-class TinyML модель з класом `fauna_activity`; (2) FW.25 DSP MFCC з P1→P0; (3) UNI.11+UNI.13a Cherkasy Soundscape Library (ЧДТУ ПМКТ + ЧНУ Біо-хаб); (4) 08_02 §1.5 Macro-Micro verification (Бушин CNN + fauna feature); (5) 08_02 §1.8 NSGA-II multi-objective GA (Любченко); (6) 08_03 Стаття 24a co-authored Q1 publication; (7) Horizon Europe CLUSTER 6 (Biodiversity Monitoring) grant vector; (8) AiInsight#biodiversity_trend → ForestNFT metadata "biodiversity_score"; (9) ринкова диференціація — defensible moat проти Pachama/Sylvera/NCX (тільки Silken Net має micro-acoustic verification layer) | `03_03` §10 + `08_01` §1.3+§2 + `08_02` §1.5+§1.8 + `08_03` Стаття 24a | **P1 strategic** — координує FW.4-EXT, FW.25, UNI.11, UNI.13a |
| E.60 | **CID witness у IoTeX ZK-proof** — bidirectional integrity bridge Polygon ↔ Filecoin. Раніше Filecoin pin (крок #11) йшов **після** мінту Polygon (крок #8), створюючи gap: зловмисник міг ex-post підмінити archive у Pinata. Виправлення: `archive_cid_preimage` детерміністично обчислюється з batch payload через `Filecoin::CidGenerator.cidv1()` ще на кроці #5 (IoTeX W3bstream) і включається у ZK-witness. Polygon `mint()` отримує `archive_cid` як `bytes32` metadata. `FilecoinArchiveWorker` fail-fast якщо Pinata-CID не збігається з очікуваним → `manual_review`. | `00_02` §5.1 (новий розділ) | P1, новий `Filecoin::CidGenerator` service |
| E.61 | **Solana micro-rewards batch payouts** — поточний `SolanaMicroRewardWorker` робить окрему транзакцію на кожен fulfilled telemetry (10,000 + growth_points*100 lamports = 0.01–0.016 USDC), де gas-fee на одну Solana tx (~0.000005 SOL ≈ 0.0007 USD) може зрівнятись із самою винагородою при низьких growth_points. Рішення: акумулювати fulfilled-винагороди в Kredis (`solana_pending_payouts:<wallet_id>`) до досягнення порогу 0.10–1.00 USDC (`SOLANA_BATCH_THRESHOLD_USDC` ENV), потім один `transferChecked()` ATA → ATA batch. Cron `SolanaBatchPayoutWorker` (every 1h) дренує накопичені. Backward-compat: при `SOLANA_BATCH_THRESHOLD_USDC=0` — поведінка як зараз (per-event). | `04_02 §Solana` + `05_01` | P1, economic correctness fix |
| ARCH.34 | **Queen-side LoRaWAN Helium Fallback** — переніс Helium fallback з Soldier (фундаментально несумісно з flash/RAM/topology STM32WLE5JC) на Queen. Queen інтегрує LoRaMac-node (Semtech BSD-3) stack + персистентний OTAA join state (DevEUI/AppEUI/AppKey у Queen Flash) + FCntUp counter survive reboot. Aggregated lambda-summary 11 байт (ARCH.22) пакується у LoRaWAN frame і доставляється через будь-який Helium hotspot у радіусі ~15 км → Helium LNS → HTTP Integration webhook → Rails `POST /api/v1/telemetry/helium`. Активація: own Starlink/LTE-M down + Q2Q backhaul недоступний + buffer fill > 50%. Soldier-side `helium_compat_emit()` (попередній план) **відкинуто**. | `00_03 §1.2 L3` + `02_05 §6.1` | P2, blocker для повної resilience policy (без нього L3 fallback архітектурно неможливий) |
| ARCH.35 | **Queen Flash Ring Buffer (W25Q32 overflow tier)** — поточний CIFO 50-slot RAM cache переповнюється за ~30 хв при 100 Soldiers/Queen × 1 пакет/год (на 200 Soldiers/Queen — за 15 хв). Додати SPI NOR Flash чип Winbond W25Q32JV (~$0.50, 4 MB, SOIC-8) до Queen BOM як overflow tier: ~190k слотів × 21 байт = ~7 діб буферизації при 100 Soldiers/год. Ring-buffer pointer (`write_ptr`/`read_ptr`) у RTC backup DR20-DR21. Drain order: спочатку Flash (FIFO), потім RAM. Енерго-impact: ~700 µA·s/добу (negligible проти 3.2 Вт·год/добу LTE-M phase 2.5). | `00_03 §1.2 L1` + `02_05 §2.1` + `02_05 §BOM` | P1, blocker для resilience policy на верхньому краю scaling |
| HW.31 | **Queen Antenna Split (REVISED 2026-05-16)** — раніше BOM Queen позиція 11 була «868/LTE-M dual-band SMA», що шкодить покриттю на 868 МГц (high VSWR на вузькому ISM). Розділено на: **поз. 11** = wideband LTE-M/NB-IoT cellular (700-2700 МГц, покриває Kyivstar B1/B3/B7/B8/B20), опційно LTE+GNSS combo для SIM7070G PPS time sync; **поз. 12** = LoRa 868 МГц **tuned** 5 dBi fiberglass omni (Mobilemark OD8-868, Taoglas ALL.4101). Окремі RF-порти SX1262 vs SIM7070G — жодного combining. | `02_05 §7 BOM` | P0, blocked by 02_05 BOM freeze; вплив: ~5 dBi gain regain on LoRa link to Soldiers |
| ✅ OPS.5 | **Projects V2 TRL field schema — 1-9 + SRL/MRL (СУПЕРСЕДЕД 2026-05-28)** — ~~раніше TRL розширювали до 1-12~~. **Корекція (2026-05-28, методологічна):** «TRL 10-12» нестандартні (NASA/ISO 16290 = 1-9); відкинуто. Тепер `lib/github_bootstrap.rb` має `TRL_OPTIONS = (1..9)` + нове поле **Readiness Horizon** (`READINESS_HORIZON_OPTIONS = SRL:Concept/Pilot/Deployed + MRL:8/9/10`) для Beyond-TRL-9 R&D (00_04 §1, 00_06 §7). `bin/setup_github_project.sh` — thin wrapper над `rake github:project_fields` (споживає `GithubBootstrap::FIELDS`, SSOT). 18 RSpec прикладів. 👤 **Залишилось:** перезапустити bootstrap, щоб додати поле `Readiness Horizon` на live-дошку (TRL:10-12 опцій ніхто не використовував, тож re-tag не потрібен; залишкові невживані опції 10-12 видалити вручну в UI за бажанням). | `00_07 §1.1` + `00_04 §1` + `00_06 §7` + `lib/github_bootstrap.rb` | ✅ Schema у коді (2026-05-28); 👤 bootstrap-run на live-дошці |

---

## 🏛️ Архітектурні пропозиції (довгострокові)

| ID | Пропозиція | Джерело | Milestone |
|----|-----------|---------|-----------|
| ARCH.1 | Fractal topology: L2 Conductor nodes (Hub Trees, formerly "Sergeant"; H-LDSE hierarchical routing, geohashing) | `00_01` | Post-TRL 7 |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka для >1M packets/hour | `00_01`, `06_01` | Series D |
| ARCH.5 | Cross-Registry Export (Verra, Gold Standard, UNFCCC) | `04_02` | Post-TRL 7 |
| ARCH.6 | Federated Learning auto-retraining (monthly cycle, A/B testing) — **обмежено L2 Conductors / L3 Queens; ніколи на L1 Soldier** (compute budget paradox, `00_06 §7.2` revised 2026-05-16: 0.47F supercap + STOP2 300 nA не витримує жодного gradient epoch'у) | `04_02`, `00_06 §7.1-7.2` | Post-TRL 7 |
| ARCH.7 | Edge Data Fusion: transmit 2-byte λ-exponent замість 16-byte Z payload | `00_01` | Post-TRL 7 |
| ARCH.8 | Event-Triggered Reporting: heartbeat 1/day normal, continuous on anomaly | `00_01` | Post-TRL 6 |
| ARCH.9 | Network Sharding: isolate anomalous clusters to prevent storm propagation | `00_01` | Post-TRL 7 |
| ARCH.10 | Queen-to-Queen Backhaul Mesh: LoRa SF12 inter-Queen relay (Starlink fallback) | `00_01` | Post-TRL 8 |
| ARCH.11 | Energy-Aware Routing: route metric = f(hop_count, remaining_energy, bio_potential) | `00_01` | Post-TRL 7 |
| ARCH.12 | Merkle Tree state root (замість flat SHA-256) для partial verification / ISO 14064 | `05_04` | TRL 9 |
| ARCH.13 | EigenLayer AVS як альтернатива direct L1 write (~$0.01/week vs $5-15/week) | `05_04` | Research |
| ARCH.14 | Read-Only PostgreSQL Replicas для analytics та Oracle queries | `00_01`, `06_01` | Post-TRL 7 |
| ARCH.16 | Mobile app для foresters (Phase 2 roadmap) | `00_02` | Post-TRL 7 |
| ARCH.17 | Bonding Curves для dynamic SCC pricing | `05_03` | TRL 9+ |
| ARCH.18 | Детерміністична Fixed-Point арифметика (Integer Math): для досягнення побітової ідентичності розрахунків (consensus) між STM32 (Soldier) та GCP/Akash (Backend), необхідно відмовитись від IEEE 754 Floating-Point. Всі вхідні дані мають множитись на 10⁶ (або 10⁸) і розраховуватись у 64-бітних цілих числах (`int64_t` у C, `Integer` у Ruby). Це усуне апаратний drift при розрахунку Атрактора Лоренца. Потребує повного переписування математики в прошивці з урахуванням ризиків переповнення буферів (overflows) під час множення великих чисел. | `03_04`, `05_02` | Post-TRL 7 |
| ARCH.19 | BSP-кластеризація IoT-графу для заміни flat TTL-mesh при масштабуванні: Binary Space Partitioning дерево на основі географічних координат Queen. Зменшує broadcast collisions та енергоспоживання. Кожна Queen знає тільки своїх сусідів | `08_02` | Post-TRL 7 |
| ARCH.20 | Petri Net PN-модель Rails моноліту: формальна верифікація відсутності deadlock при 10,000 concurrent IoT connections. Sidekiq + Puma + PostgreSQL modeling. Конволюційний метод для зменшення state space explosion у 10-100 разів | `08_02` | R&D (Супруненко, ЧНУ) |
| ARCH.22 | Arithmetic compression для LoRa payload: lambda-exponent (2 байти) замість повного Z (16 байт). Потенційна економія ~34% TX часу (21→~14 bytes). Event-Triggered Reporting: "мовчання = здоров'я" — 24× зниження трафіку | `08_02`, `00_01` | Post-TRL 7 |
| ARCH.23 | Multi-Attribute Utility Function для автономного рішення TX на MCU: оцінка важливості поточного пакету (Vcap, delta_t, acoustic, bio_status) — відправляти лише якщо utility > threshold. Оцінка: 30-40% зниження TX | `08_02` | Post-TRL 7 (Ярмілко, ЧНУ) |
| ARCH.24 | CE/FCC/RoHS/EMC/IP68 compliance roadmap для EU/NA ринків: CE-RED (868 МГц LoRa), FCC Part 15/90, RoHS-2, IP68 (IEC 60529), REACH. Кожна сертифікація потребує 3-6 місяців та спеціалізованої лабораторії | `08_02` | Pre-mass production (Косенюк, ЧНУ) |
| ARCH.25 | Gyroid geometric validation scripts: Python/C++ верифікація 65% пористості per-slice, topological integrity mesh, capillary channel connectivity via BFS (breadth-first search). Запускається після кожного nTop build для запобігання помилкам DMLS | `08_02` | Before DMLS factory order |
| ARCH.26 | **Синхронні Вікна (TDMA) та CAD Preamble Detection — вирішення Проблеми Рандеву для mesh relay.** Поточна архітектура: Queen always-on (`Radio.Rx(LORA_RX_INFINITE)`), Soldier має лише 600 мс post-TX RX window — mesh relay між Солдатами стохастичний і ненадійний за межами прямої видимості Queen. **Три рівні рішення:** (L1) Queen always-on ✅ реалізовано; (L2) TDMA Sync Windows — Queen транслює beacon з точним часом (NTP через LTE), Солдати синхронізують RTC, кожні 15 хвилин координоване 2-секундне RX-вікно для mesh relay. Залежить від FW.20 (LoRa Time Sync); (L3) CAD — SX1262 `Radio.StartCad()` дозволяє wake на ~2 мс/секунду для детекції LoRa-преамбули без повного RX. Критично для PANIC mode: Солдат при chainsaw detection посилає довгу преамбулу (~1 сек), сусідні Провідники ловлять через CAD навіть між TDMA-вікнами. **Firmware зміни:** Soldier: CAD periodic wakeup (LPTIM або RTC sub-second alarm), beacon RX handler, RTC sync logic. Queen: beacon TX (periodic broadcast з UTC timestamp + network schedule). **Енергобюджет:** CAD wake 1/сек × 2 мс × 4.5 мА = ~9 µA середнє — допустимо для Провідників (дерева з високим vcap), неприйнятно для слабких Солдатів. Рольова диференціація: Солдат (TX-only, глухий) vs Провідник (TX+CAD, еліта з надлишком енергії). | `00_01`, `03_01`, `03_02` | Post-TRL 6 (Firmware + Queen beacon) |
| ARCH.29 | **RTOS Deadlock-Free верифікація через Petri Nets** — формальна PN-модель firmware tasks (Sensing/Compute/TX/OTA/WDT) на Soldier + reachability graph аналіз для доведення відсутності circular wait. Відрізняється від ARCH.20 (Petri Net Rails моноліт) тим що моделює embedded RTOS scheduling | `08_02` §1.2 (Ярмілко) | Post-TRL 6 (R&D — Ярмілко, ЧНУ) |
| ARCH.30 | **Parallel CFD gyroid simulation на Akash GPU** — domain decomposition алгоритм для 3D TPMS-симуляцій на heterogeneous GPU вузлах Akash. Скорочує CFD lead-time з ~2 годин до real-time валідації геометрії перед DMLS order. Cross-ref ARCH.25 (gyroid validation scripts) | `08_02` §1.4 (Онищенко) | Post-TRL 7 (методологія + Akash GPU integration) |
| ARCH.31 | **SOP-в-Phlex inline UI для EwsAlert** — інтеграція 7 SOP документів (drought/epidemic/vandalism/fire/seismic/fault/entropy) як inline-інструкцій, що показуються при кліку на EwsAlert у дашборді. UX: forester отримує немедіане runbook замість пошуку у документах | `08_05` + `04_02` | Post-TRL 6, cross-ref E.54 + UNI.12 |
| ARCH.32 | **Shape Up 6-week cycle Petri Net formalization** — формальна верифікація фази Shape Up (betting table → build → cool-down) щоб довести: будь-яка фіча може бути завершена у межах cycle constraints. Цільова стаття Q1 *IEEE Transactions on Software Engineering* | `08_02`, `00_05` | Post-TRL 7 (методологія + R&D, Супруненко ЧНУ) |
| ARCH.33 | **ECDH P-256 key exchange як альтернатива HKDF-only provisioning** — мерехтливий розгляд: замість per-device HKDF (FW.1) використати ECDH у factory або field provisioning. Plus: Perfect Forward Secrecy без shared master key. Minus: Curve25519/P-256 потребує ~512 байт SRAM + 50 мс CPU на handshake | `08_02` §1.1 (Vector 2, Ярмілко), `03_05` | Research alternative (узгодити з FW.17 Hash Ratchet) |

---

## 🗄️ Архів закритих пунктів (мігровано в канон)

> Повністю завершені пункти, винесені з активного трекера 2026-05-28. Знання — у канонічних доках (стовпець «Канон»); повна історія — у git. Тримаємо лише вказівник для крос-реф цілісності (CLAUDE.md та живі пункти посилаються на ці ID).

| ID | Пункт | Канон |
|----|-------|-------|
| ARCH.42 | ATECC608B AES-128 vs AES-256 — DECIDED (Variant B) | `03_05 §3.7` |
| SEC.6 | ATECC608B Secure Element — оцінка інтеграції | `03_05 §3.7`, §3.4 |
| SEC.10 | Emergency-TX anti-replay frame counter (DR0 packing) | `03_02`, `03_01 §2` |
| SEC.11 | Lorenz Seed Provenance (DCI hardening, K_seed HKDF) | `03_04`, `03_05 §3.4а`, `04_02`, `05_02` |
| FW.5 | Lorenz β-пертурбація від delta_t/vcap (Variant B+) | `03_04`, `05_02` |
| FW.18 | TinyML confidence threshold (RTC DR13/14 dual-zone) | `03_03`, `03_01 §2`, `04_06` |
| FW.29 | Panic vs saturated acoustic disambiguation (PANIC_FLAG_BIT) | `03_03 §5.3` |
| FW.29-PACK | StatusByte layout collision fix (5-bit growth_points) | `03_01 §11.5`, `03_04 §4.3-5.2`, `05_02` |
| FW.43 | 03_05 §3.1 SSOT drift fix (post-FW.1 hardcoded-key ghost) | `03_05 §3.1/§3.4г` |
| S6.12 | TokenomicsEvaluator oracle-guards audit (KYC all-paths) | `04_02`, `05_02` |
| OPS.7 | Sync labels.yml + Projects V2 ↔ 00_07 §4 | `00_07 §4.3/§4.4` |
| OPS.8 | TreeFamily seed drift vs Lorenz SSOT fix | `03_04 §4.1`, `04_01` |
| BIZ.4 | DAO Governance (SilkenGovernor + Timelock) | `05_03`, `07_01` |
| PUMA-RACK-1 | Idempotency write off response path (`rack.response_finished`) | `06_05 §7` |
| TRL Матриця | Per-module TRL (мігровано з 00_08) | `00_06 §1` |
| E.8 / DIFF.7 | SNR tiebreaker у Queen CIFO eviction | `03_02`, `04_06` |
| E.28 | Kamal `pre-build` hook idempotency audit | `06_01` |
| E.35 | Flash-loan defense (SilkenGovernor governance params) | `05_03` |
| E.42 | TelemetryLog cleanup `dispatched` guard | `04_02` |
| E.47 | Solana RPC production guard (raise on missing ENV) | `05_01` |
| E.49 | Celo RPC fallback cascade (ResilientClient) | `04_02`, `05_01` |
| E.62 | Dead `clusters.active_firmware_id` assoc removed | `04_01` |
| ARCH.21 | Brownout PVD → Lorenz state save в RTC | `03_01`, `08_02` |
| ARCH.28 | RTC Backup Domain allocation policy | `03_01 §2` |
| ARCH.27 | Node-role flag (Soldier/Provisioner, Flash magic) | `03_01 §1.11` |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
> 3. Для нових знахідок — додавати у відповідну секцію + посилання на джерело docs
> 4. Раз на квартал — повний docs audit з оновленням «Top-Critical Path» секції зверху
