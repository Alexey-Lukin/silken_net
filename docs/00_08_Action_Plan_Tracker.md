# 00_08: Action Plan Tracker (Залишок робіт)

## 🎯 Мета

Зберігати ТІЛЬКИ незавершені задачі з пріоритетами, виконавцями та статусами. Виконана робота задокументована у відповідних docs (`00_00` → `08_07`). Документ є живим операційним інструментом — оновлюється при кожному завершенні задачі.

---

## ✅ Статус

- **Поточний TRL:** TRL 4 (System) / per-domain decoupled через HIL Simulators ([`00_06`](00_06_Strategic_Roadmap_and_HIL_Simulators)). Операційний трекер активний.
- **Пов'язані модулі:**
  - SSOT індекс → [`00_00_SSOT_Index`](00_00_SSOT_Index)
  - Матриця покриття тестами → [`04_06_Testing_Guide_and_Coverage`](04_06_Testing_Guide_and_Coverage)
  - Деплой та інфраструктура → [`06_01_Deployment_Kamal_Terraform`](06_01_Deployment_Kamal_Terraform)
  - Resilience & failover policy → [`00_03_Resilience_and_Failover_Policy`](00_03_Resilience_and_Failover_Policy)

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
2. **FW.1 + SEC.3** — Per-device HKDF provisioning + Factory Flashing pipeline — **P0**
3. **FW.2** — AES-256-CCM (вирішує одразу: ECB→CCM, MIC, FW.23 OTA auth, SEC.10 panic auth, FW.29 disambiguation) — **P0**
4. **SEC.1** — Gnosis Safe multisig для `DEFAULT_ADMIN_ROLE` SCC/SFC до mainnet — **P0**
5. **ARCH.42** — архітектурне рішення AES-128 vs AES-256 (ATECC608B апаратно підтримує лише AES-128 — конфлікт з системним AES-256; блокує SEC.6 Secure Element integration та BOM freeze) — **P1 (до BOM freeze)**

### Перед production-запуском Web3 mintingу
6. **S1.1** — заповнити GitHub Secrets (`DATABASE_PASSWORD`, `GCP_SA_KEY`, `SSH_PRIVATE_KEY`, ...) — **P0**
7. **E.45 / S3.5** — підставити реальну адресу SCC/SFC у `subgraph.yaml` — **P0**
8. **E.47** — встановити `SOLANA_RPC_URL` mainnet (інакше Devnet за замовчуванням) — **P0**
9. ✅ ~~**S6.12**~~ — аудит `TokenomicsEvaluatorWorker` оракул-guards bypass — **виконано** (аудит + spec coverage + документація завершено)
10. **INF.4 + INF.6** — TLS termination + CoAP Proxy verification на Akash ingress — **P1**

### Парк аналітики/спостережуваності перед першим Akash deploy
11. **S2.1 + S2.2 + S2.3** — Grafana Cloud dashboards & alerts після першого `/metrics` пуш — **P0** (ops)
12. ✅ ~~**S5.2**~~ — `RELEASE_VERSION` ENV додано у Kamal/Akash/CI config — **реалізовано** (залишилось: 👤 верифікувати Sentry release tracking після першого деплою)

### Лабораторно-критичний шлях (TRL 4→6 hardware)
13. **HW.24** — Staged validation gate (SLA → Ti-coin → full anchor) — **P0** (блокує замовлення 100 шт. DMLS до проходження попередніх етапів)
14. **HW.23** — HIP postprocess specification for SLM anode — **P0** (блокує перший SLM-замовлення)
15. **HW.22** — Sterilization protocol (no EtO) — **P1** (блокує перехід до Stage 4 польових тестів)
16. **HW.7** — BQ25570 VBAT_OV резистори: виміряти і замінити SMD якщо мисматч — **P1** (блокує PCBA freeze)
17. **HW.13 / ARCH.29-MPPT** — P-V крива EBFC + перейти з 50% VOC на 65% — **P1**
18. **HW.3** — 12-тижневий Arrhenius accelerated aging тест (синтетичний ксилемний сік) — **P1** (блокує seed)
19. **HW.25** — PTFE-GDL membrane для катода (Zone 3) — **P1** (блокує EBFC у новій тризонній архітектурі)

### Академічний critical path
20. **UNI.1** — Перша зустріч з деканом Онищенком (ChNU FOTIUS) — **P0** (блокує всі публікації Q1)
21. **UNI.8** — Перший контакт з ректоратом СЄУ — **P0** (блокує MSA / B2B legal)
22. **UNI.13 / UNI.14** — Верифікувати посади науковців ЧМА і СЄУ через офіційні сайти — **P0**

---

## 🛣️ Software / Backend / DevOps

> **Складність:** XS < 1 год · S = 1–4 год · M = 4–8 год · L = 1–3 дні

#### S1.1 — GitHub Secrets заповнення
- **P0** | `06_01` | **Складність: XS** | **🔧 Операційна** — ручне заповнення в GitHub UI, без коду
- **Опис:** 12 критичних секретів не встановлені: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `DATABASE_URL`, `SSH_PRIVATE_KEY`, тощо. Блокує весь CI/CD pipeline.
- **Статус:** ✅ Checklist створено у `docs/06_04_Secrets_Checklist` — повна інвентаризація 4 місць зберігання (GitHub Secrets, `.kamal/secrets`, Akash SDL, `terraform.tfvars`)
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
- **Статус (🤖, 2026-05-17):** ✅ IaC JSON згенеровано: `deploy/grafana/dashboards/silkennet-overview.json` — один dashboard з 5 секціями (Telemetry, Sidekiq, Web3, Treasury, DB Pool), 15 панелів. Імпортується через Grafana UI або HTTP API. Інструкції: `deploy/grafana/README.md`.
- [x] 🤖 `deploy/grafana/dashboards/silkennet-overview.json` — Dashboard IaC (Telemetry + Sidekiq + Web3 + Treasury + DB Pool)
- [ ] 👤 Імпортувати dashboard у Grafana Cloud (UI або API — інструкції у `deploy/grafana/README.md`)

#### S2.3 — Grafana Cloud alerting rules
- **P0** | `06_03` | **Складність: S** | **🔧 Операційна** — налаштування в Grafana Cloud UI, без коду
- **Опис:** Grafana Cloud Alerting замінює потребу в self-hosted Alertmanager
- **Статус (🤖, 2026-05-17):** ✅ IaC YAML згенеровано: `deploy/grafana/alerts/silkennet-alerts.yaml` — 12 alert rules (4 P0 critical + 5 P1 warning + 3 P2 info). Grafana Unified Alerting формат (Grafana 9+). Інструкції та `sed` команда для `${DATASOURCE_UID}`: `deploy/grafana/README.md`.
- [x] Backend: `silkennet_telemetry_acoustic_overflow_total` counter реалізований в `TelemetryUnpackerService` (інкрементується при `acoustic_events == 255`) — готовий для alert rule `rate() > 0`
- [x] 🤖 `deploy/grafana/alerts/silkennet-alerts.yaml` — Alert rules IaC (12 rules: P0/P1/P2)
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
- **Статус:** ✅ workflow реалізований (`coap_smoke.yml`). 🟡 не активований як required gate у `deploy.yml`.
- [x] 🤖 `coap_smoke.yml` як `workflow_call` від `deploy.yml`
- [ ] 👤 Активувати як required post-deploy gate (set `coap-smoke` як `needs:` у production job після першого зеленого прогону)
- [ ] 👤 Перший boundary smoke з реальної Queen або `bin/forest_simulator`

#### INF.4 — Akash TLS strategy decision: hostname operator vs Cloudflare
- **P1** | `06_02` BLOCKER-5, `06_01` | **Складність: S** | **🔧 Операційна + Док**
- **Опис:** Розширення INF.3. Не прийнято архітектурне рішення: (a) Akash hostname operator + Let's Encrypt автоматизація, (b) Cloudflare Proxy перед Akash (DDoS + WAF, але ще одна mw залежність), (c) Traefik у Kamal (тільки GCP path). Вибір впливає на CoAP UDP (Cloudflare НЕ proxies UDP — потребує separate Spectrum або direct ingress)
- **Статус (🤖, 2026-05-12):** Документація runbook завершена у `docs/06_02` BLOCKER-5 → "Runbook: TLS Termination Strategy [INF.4]". Покрито: рекомендоване рішення (Опція A — Cloudflare Proxy для HTTPS + direct UDP для CoAP через Ingress Anchor) з повним pre-flight checklist (8 пунктів) та 8 verification commands (openssl, curl, websocket handshake, coap-client, SSL Labs); failure modes таблиця (5 типових проблем + діагностика); fallback Опція B (Akash hostname operator + Let's Encrypt). Залишається 👤 архітектурне approve + (опційно) 🤖 Terraform automation якщо обрана Опція B.
- [ ] 👤 Прийняти архітектурне рішення (Cloudflare Proxy для HTTPS + direct UDP для CoAP — рекомендовано)
- [x] 🤖 Документувати у `06_02` runbook: pre-flight checklist + verification commands
- [ ] 🤖 Якщо Akash hostname — додати automation у `terraform/`

#### S4.3 — Akash SDL secrets
- **P3** | `06_02` | **Складність: XS** | **🔧 Операційна** — заповнити 4 змінні у `deploy.yaml`
- **Опис:** `REQUIRED_SECRET_NOT_SET` для 4 критичних змінних
- [ ] 👤 Заповнити в `deploy/akash/deploy.yaml`
- [ ] 👤 Верифікувати startup

#### S5.2 — RELEASE_VERSION ENV для Sentry
- **P2** | `06_03` | **Складність: XS** | **🔧 Операційна**
- **Опис:** `RELEASE_VERSION` ENV не встановлено — Sentry release tracking не працює. Потрібно додати у Kamal/Akash deploy config
- **Статус:** ✅ Виконано. `RELEASE_VERSION` додано у: `deploy.yml` (Canopy, git SHA), `deploy-production.yml` (Production, release tag або git SHA), `config/deploy.yml` (Kamal clear env), `deploy/akash/deploy.yaml` (web + job services)
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
- [ ] 👤 Верифікувати Upstash multi-zone replication у production
- [x] Додати graceful degradation: при Redis недоступності → DB-based nonce lookup з TTL
- [x] Тести: Redis down scenario → gateways залишаються active

#### S6.10 — MaintenanceRecord — лише лог
- **P3** | `04_02` | **Складність: L** | **Архітектурна**
- **Опис:** MaintenanceRecord — лише запис логу. Немає: призначення задач, оплати, верифікації. Потребує Forester Guild (E.20)
- **Статус (🤖, 2026-05-13):** ✅ Архітектурний дизайн task assignment завершено та задокументовано у `04_02` §"Forester Guild" → "Архітектурний дизайн: Task Assignment Algorithm 🤖 (S6.10)". Покриває 6 етапів: (1) Bounty fields (severity TTL: critical=6h…low=7d, required_skills/certifications bitmap, AASM state machine); (2) Candidate filtering (KYC-verified Hadron, in-radius з severity-driven exponential escalation, not-busy, not-cluster-blacklisted); (3) Composite scoring — 0.40·distance + 0.25·reputation + 0.20·responsiveness + 0.10·specialization + 0.05·cluster_familiarity (weights tunable через SystemParameter→BIZ.4 DAO); (4) Notification cascade — exclusive 10-хв lock для :critical, top-N race для інших, ForestBountyExpansionWorker для escalation; (5) Race conflict resolution через `lock("FOR UPDATE NOWAIT")`; (6) Verification (GPS/EXIF/IPFS) → USDC on-chain payout → MaintenanceRecord → reputation feedback. Включено: crash recovery/idempotency таблицю, anti-Sybil (geo-staking + KYC), dClimate fallback integration (E.34).
- [x] 🤖 Архітектурний дизайн task assignment — ✅ `04_02` §Forester Guild (2026-05-13)
- [ ] 🔗 Зв'язати з Forester Guild PoPhW (E.20)

#### S6.12 — TokenomicsEvaluatorWorker: oracle-guards bypass для не-oracle flow
- **P1** | `04_02` §4.2.2 (BlockchainMintingService) | **Складність: M** | **🤖 Аудит**
- **Опис:** Документація явно заявляє: «Guards (`verified_by_iotex?`, `oracle_status_fulfilled?`, `hadron_kyc_status=="approved"`) активні лише при `telemetry_log` (oracle-driven flow); tokenomics flow працює без прямої прив'язки до log — growth_points вже верифіковані pipeline'ом». **Ризик:** якщо `TokenomicsEvaluatorWorker` довіряє upstream pipeline без власної перевірки, можливе мінтінг неверифікованих growth_points при пошкодженні pipeline upstream
- **Статус (✅ виконано):** Audit виконано: `TokenomicsEvaluatorWorker → EvaluateTreeBatchWorker → wallet.lock_and_mint!` створює `BlockchainTransaction(:pending)`, який потім `MintCarbonCoinWorker#process_batch` передає у `BlockchainMintingService.call_batch(ids)` БЕЗ `telemetry_log:`. Виявлено: фактичний upstream perimeter — це **AES-256-CBC decrypt + `valid_sensor_data?`** у `TelemetryUnpackerService`, а **не** повний oracle pipeline (IoTeX/Chainlink виконуються async і незалежно для Path 1). **Hadron KYC — єдиний обов'язковий guard для всіх шляхів** (Path 1, Path 2, Path 3, Path 5). Документація уточнена у двох місцях: `04_02` (BlockchainMintingService row — деталізація `[BLOCKER-11 / S6.12]` з перерахуванням guards per-path) та `05_02` (PATH 2 callout розгорнуто з фактичним інваріантом + залишковий ризик AES-key compromise + mitigation track FW.1/FW.2/SEC.3). Spec coverage: `spec/services/blockchain_minting_service_spec.rb` → context "tokenomics flow without telemetry_log [S6.12]" (3 examples: skip oracle guards / enforce KYC pending / enforce KYC rejected).
- [x] 🤖 Code audit: `TokenomicsEvaluatorWorker` довіряє upstream (per-packet AES + sensor validation), Hadron KYC enforced незалежно
- [x] 🤖 Документувати фактичний інваріант: «всі шляхи до `Wallet#lock_and_mint!` повинні мати Hadron KYC guard; oracle-guards активні лише в Path 1 (per-telemetry); growth_points perimeter — AES decrypt у `TelemetryUnpackerService`»
- [x] 🤖 Spec coverage: tokenomics flow з KYC `pending` / `rejected` → expect raise `Compliance Breach`

#### S6.14 — peaq_signing_key: відсутня rotation policy
- **P2** | `04_02` §4.2.2 (GeneratePeaqDidService, BLOCKER-08) | **Складність: M** | **🤖 Архітектура + Док**
- **Опис:** `peaq_signing_key` — обов'язковий (W3C DID compliance), raise `RegistrationError` при відсутності. Але немає процесу для: (1) ротації ключа без зламу існуючих DID, (2) emergency revocation при компрометації, (3) синхронізації між staging/production
- [x] 🤖 Дизайн key rotation policy (overlap window, migration strategy) — ✅ Dual-key overlap window (72 год) з `peaq_signing_key` + `peaq_signing_key_previous`. Scheduled rotation кожні 90 днів. Задокументовано в `04_02` §S6.14
- [x] 🤖 Документувати emergency revocation runbook — ✅ 5-step incident response (Detection → Containment <15хв → Investigation → Recovery → Post-Incident). Задокументовано в `06_04` §5.4
- [ ] 👤 Vault-store production peaq_signing_key (Bitwarden/1Password)

#### S6.18 — Rails web security hardening (maquina-app/rails-claude-code §8 audit)
- **P1** | `06_01`, `06_02`, `06_04` | **Складність: M** | **🤖 Код + Конфігурація**
- **Опис:** Повний security audit Rails-шару по категоріях: PROD (SSL/HSTS), CSRF, HDR (Security Headers), CSP, SESS (Session cookie), RATE, AUTH, GEM (brakeman/bundler-audit), CI, DATA, FWKD.
- **Статус (✅ виконано):**
  - **PROD** (`config/environments/production.rb`) — `force_ssl`, `assume_ssl`, HSTS (1 рік, subdomains, preload) активовані. `ssl_options` виключає `/up` та `/metrics` для health probe / Prometheus scrape. `config.hosts` з `RAILS_ALLOWED_HOSTS` ENV; при відсутності — boot-time `[SECURITY]` попередження замість silent відкриття.
  - **CSP** (`config/initializers/content_security_policy.rb`) — реальна CSP налаштована під фактичні залежності кодбейсу: `script-src` self + `https://ga.jspm.io` (Leaflet importmap), `style-src` self + `https://unpkg.com` + `unsafe-inline` (Leaflet runtime styles), `img-src` self + `https://*.basemaps.cartocdn.com` (CartoDB tiles) + `https://www.transparenttextures.com` (decorative texture), `connect-src` self (Solid Cable same-origin). Nonce для inline `<script>`. Report-only за замовчуванням.
  - **HDR** (`config/initializers/security_headers.rb`) — `X-Frame-Options: DENY`, `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Resource-Policy: same-origin`, `X-XSS-Protection: 0`, повний `Permissions-Policy` (camera/mic/geo/USB/payment/FLoC/Topics/browsing-topics — всі заборонені).
  - **SESS** (`config/initializers/session_store.rb`) — `:cookie_store` з `httponly: true`, `secure: Rails.env.production?`, `same_site: :lax`, `expire_after: 14.days`, namespaced key `_silken_net_session`.
  - **Без змін (вже відповідає):** CSRF (`ActionController::API` + Rails 8.1 defaults), RATE (Rack::Attack), AUTH (Pundit + Argon2id + Ed25519), GEM (brakeman 0 warnings, bundler-audit 0 CVEs), CI (brakeman + bundler-audit + importmap audit), DATA (AR Encryption + `filter_parameters`), FWKD (`load_defaults 8.1`).
  - **Нові ENV** задокументовані у `docs/06_04_Secrets_Checklist §2.1`, `docs/06_01 deploy.yml snippet`, `docs/06_02 SDL env table`, `.env.example`.
- [x] 🤖 Активувати `force_ssl`, `assume_ssl`, HSTS у `production.rb`
- [x] 🤖 Активувати `config.hosts` (DNS-rebinding захист) з boot-time warning
- [x] 🤖 Написати реальну CSP, обрізану під фактичні залежності (jspm/unpkg/cartocdn/transparenttextures)
- [x] 🤖 Створити `security_headers.rb` (X-Frame DENY, COOP/CORP, Permissions-Policy)
- [x] 🤖 Створити `session_store.rb` (secure/httponly/same_site/expire_after)
- [x] 🤖 Оновити `.env.example`, `docs/06_01`, `docs/06_02`, `docs/06_04` з новими ENV
- [ ] 👤 Встановити `RAILS_ALLOWED_HOSTS=api.silkennet.com,.silkennet.com` у Kamal `env.clear` / Akash SDL **перед першим production деплоєм**
- [ ] 👤 Після 1–2 тижнів спостережень CSP violation-репортів — встановити `CSP_ENFORCE=true` (переведення CSP з report-only у enforced)

#### PUMA-IPV6-1 — Верифікація IPv6 bind після першого Kamal-деплою
- **High** | `06_05` | **Складність: XS** | **🔧 Операційна** — верифікація після першого реального деплою, без коду
- **Опис:** Puma 8.0+ за замовчуванням bind'иться на `tcp://[::]:3000` (dual-stack) якщо є non-loopback IPv6 інтерфейс. Thruster конектиться до Puma по `127.0.0.1:3000`. Linux `IPV6_V6ONLY=0` = `[::]:3000` приймає і v4, і v6 → має працювати. Перевірка потрібна для впевненості.
- [ ] 👤 Після першого деплою canopy: `kamal app exec -i 'ss -tlnp | grep 3000'` — очікуємо `tcp6 LISTEN [::]:3000`
- [ ] 👤 `curl -fsS http://127.0.0.1:3000/up` і `curl -fsS http://[::1]:3000/up` — обидва 200
- [ ] 👤 Задокументувати результат у `06_05_Puma_Configuration` (IPv6 runbook section)

#### PUMA-RACK-1 — Idempotency-Key write поза response path
- **Low** | `06_05` | **Складність: S** | **🤖 Код** — актуально при planetary scale
- **Опис:** `actuators#execute` зберігає Idempotency-Key через `Rails.cache.write(..., expires_in: 24.hours)` у Solid Cache (PostgreSQL). Виклик ~1-2ms додає latency до відповіді. `rack.response_finished` callback (Puma 7.0+) дозволяє виконати write ПІСЛЯ flush response до клієнта. Поточний 1-2ms не блокер (TRL 6–8), але при мільйонах актуаторних команд/добу — значуща економія latency p50.
- **Статус:** ✅ Виконано. `Rails.cache.write` переміщено у `rack.response_finished` callback (Puma 7.0+). Кеш записується ПІСЛЯ flush response клієнту, зменшуючи p50 latency на ~1-2ms. TTL та логіка незмінні. Spec coverage оновлено.
- [x] 🤖 Перенести `Rails.cache.write(cache_key, response_body, ...)` в `actuators#execute` на `rack.response_finished` callback: `env["rack.response_finished"] << -> { Rails.cache.write(...) }`
- [x] 🤖 Верифікувати що TTL та logic незмінні, додати spec coverage
- 🔗 Залежить від: planetary scale milestone (перегляд при > 1M actuator commands/добу)

---

## 🔧 Firmware

### 🔴 P0 — Критичні

#### FW.1 — Hardcoded AES-256 Key
- `03_01`, `03_02`, `03_05`, `05_02` | `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:81-82`
- **Опис:** Один і той самий ключ на ВСІХ вузлах мережі. Злам одного пристрою = компрометація всієї мережі
- **Рішення:** Per-device provisioning через HKDF, Factory Flashing pipeline
- [x] 🤖 Дизайн HKDF key derivation protocol — ✅ Повний дизайн HKDF-SHA256 (RFC 5869) додано в `03_05` §3.4а. Включає: кроки Provisioning (factory flashing pipeline), C firmware API (`Load_AES_Key`, `FLASH_KEY_ADDR = 0x0803E000`), Rails backend (`HardwareKeyService.derive_device_key`), варіанти зберігання ключа Queen (A/B/C з ATECC608B), WRPROT Flash sector protection, таблицю безпекових параметрів
- [x] 🤖 Backend: provisioning endpoint (POST `/api/v1/provisioning/register` вже існує) — ✅ Аудит підтвердив відповідність HKDF-дизайну з `03_05` §3.4а. Контроллер `Api::V1::ProvisioningController#register` виконує: FW.24 magic-UID guard → duplicate check → атомарну транзакцію (Tree/Gateway + HardwareKey + MaintenanceRecord(installation)) → опційну реєстрацію Ed25519 публічного ключа → enqueue `PeaqRegistrationWorker` (тільки для Tree) → JSON-відповідь БЕЗ `aes_key`/`lorenz_seed`/`warning` (Zero-Trust, єдиний режим після SEC.11 hard cutover). `HardwareKeyService.derive_device_key` raise'ить `SecurityError` при відсутньому `PROVISIONING_MASTER_KEY` (no SecureRandom fallback ANYWHERE). RBAC: `authorize_forester!`. Контракт відповідає `04_03 §POST /api/v1/provisioning/register`.
- [x] 🤖 Firmware: змінити key storage з hardcoded → Flash-based (`Load_AES_Key()` в soldier/queen main.c — FLASH_KEY_ADDR 0x0803E000, magic "SKEY")
- [ ] 👤 Firmware: RDP Level 2 activation як final step
- [x] 🤖 End-to-end тест provisioning flow — ✅ `spec/integration/provisioning_e2e_spec.rb` покриває без моків `HardwareKeyService`: (1) HKDF determinism — persisted `aes_key_hex` точно збігається з незалежно повторно деривованим ключем (firmware-equivalence assertion); (2) atomic creation Tree+HardwareKey+MaintenanceRecord з DID/UID у notes + enqueue `PeaqRegistrationWorker`; (3) gateway flow з Ed25519 public key persistence та БЕЗ peaq enqueue; (4) `binary_key.bytesize == 32` (firmware-readable AES-256); (5) Zero-Trust assertion — response НІКОЛИ не містить `aes_key`/`lorenz_seed`/`warning` (єдиний режим після SEC.11 cutover); (6) SEC.11 hard-cutover guard raise'ить `SecurityError` без DB side effects при відсутньому `PROVISIONING_MASTER_KEY`; (7) FW.24 magic UID rejection без DB side effects; (8) duplicate UID → 409 без DB side effects.

#### FW.2 — AES-256-ECB без MAC/MIC
- `03_05` | `firmware/soldier/main.c:747`, `firmware/queen/main.c:781`
- **Опис:** Детерміністичний шифротекст, replay/bit-flip attacks можливі. Немає автентифікації пакетів
- **Рішення (рекомендоване):** **AES-256-CCM** (апаратно підтримується STM32WLE5JC) з новим 24-байтним пакетом. Вирішує BLOCKER-2 та BLOCKER-3 одночасно
- **Альтернативи:** AES-256-GCM, AES-256-CTR + HMAC-SHA256 MIC (4-byte suffix)
- **Статус (🤖, 2026-05-13):** Дизайн пакету завершено та задокументовано у `03_05` §3.2 BLOCKER-2. Фінальна структура: Header cleartext AAD `[DID:4][FrameCounter:4 BE]` + encrypted sensor payload `[Vcap_mv:2][temp:1][acoustic:1][delta_t_s:2][status_byte:1][mesh_ctrl:1]` + MIC `[8B 64-bit MAC]` = 24B без wasted Reserved-полів. Покращення проти чернетки: (1) MIC розширено до 8B (64-bit) замість 4B — forge probability ≈ 5.4×10⁻²⁰ vs 2.3×10⁻¹⁰, безпечний на 25-річний горизонт при billion-tree scale; (2) `mesh_ctrl` byte компресує TTL:4 + fw_version_epoch:4 (замість витраченого `firmware_version_id` uint16); (3) Frame Counter = CCM nonce (4B monotonic uint32, RTC DR2) субструє SEC.10 RTC panic counter і gossip_ts_byte — обидва interim workarounds до повного CCM; (4) backend cross-ref: per-DID FC monotonic check через Redis SETNX TTL=25h, growth_points апскейл з 5-bit (0..31) через species multiplier. Firmware (Soldier CCM encrypt, Queen CCM decrypt+FC validation) та backend parser — наступні ітерації.
- [ ] 🤖 Верифікувати `CRYP_AES_CCM` підтримку на цільовій ревізії STM32WLE5JC
- [x] 🤖 Дизайн 24-байтного пакету (8 байт sensor data vs поточних 16 — оптимізувати поля) — ✅ Виконано (2026-05-13). Повна специфікація у `03_05` §3.2 BLOCKER-2 (фінальний дизайн 🤖 FW.2): field layout, nonce construction, MIC rationale, removed-fields migration table, HAL_CRYP config, backend cross-refs
- [ ] 🤖 Firmware Soldier: CCM encrypt + Frame Counter інкремент + MIC append
- [ ] 🤖 Firmware Queen: CCM decrypt + Frame Counter validation (anti-replay)
- [ ] 🤖 Backend: оновити `TelemetryUnpackerService` для 24-байтного формату
- [x] 🤖 LoRa airtime budget verification (24B vs 16B при SF10/DR2) — ✅ Розрахунок додано в `03_05` BLOCKER-2. Висновок: +10% airtime (+41 мс), duty cycle 0.013% (79× запас), енергоспоживання +12 мДж/TX (1.8% EDLC). **Перехід на CCM 24B схвалений**
- [ ] 🤖 Тести

#### FW.3 — Queen AT Command Blocking (~25 сек)
- `03_01`, `03_02`
- **Опис:** Queen "сліпа" до LoRa пакетів під час CoAP flush. Single-packet buffer — пакети втрачаються
- **Статус:** 🟡 Частково виправлено (2026-05-02). Single-packet buffer overwrite + emergency-pakck loss закрито через ring buffer + drain-loop. Повна async UART DMA flush — окрема ітерація (потребує DMA controller hardware-in-loop validation, не покривається host-тестами).
- **Рішення:** UART DMA interrupt-driven + ring buffer
- [ ] 🟡 Переписати `Flush_Cache_To_Rails()` на UART DMA — deferred (наступна ітерація FW.3, потребує STM32 hardware bench)
- [x] 🤖 Замінити single-packet buffer на ring buffer — ✅ Виконано (2026-05-02). 16-слотовий FIFO у `firmware/queen/main.c` (capacity = 15, lock-free single-producer/single-consumer на ARM Cortex-M4 атомарності 8-біт). `OnRxDone` інкрементує `lora_rx_drops` при переповненні замість мовчазного перезапису. Main loop дренує весь ринг циклом `while (LoRa_Rx_Ring_Pop(...))` перед перевіркою flush-таймера. Закриває head-of-list пункт BLOCKER-2: під час 25-секундного flush'у до 15 голосів буферуються; bursts > 15 видимі через лічильник.
- [x] 🤖 Додати CoAP response parsing (замість blind HAL_Delay) — ✅ Виконано через FW.9 (`SIM7070_SendATCommand_WithResponse` + `COAP_MAX_RETRIES=3` retry-логіка з парсингом `OK`/`ERROR` у `Flush_Cache_To_Rails`). Boot-time AT-команди (CNMP/CPSMS/CEDRXS) залишаються на blind delay — вони не у критичному 25-секундному вікні.
- [x] 🤖 Тести — ✅ 13 host-тестів у `firmware/test/test_queen_logic.c` секція "LoRa RX Ring Buffer (FW.3)": initial empty, pop-on-empty, single push/pop roundtrip, FIFO order preserved, fill to capacity 15, overflow increments drop counter (existing voices preserved), drain+refill wraps correctly, RSSI -128 preserved, ISR simulator drops non-16B / clamps RSSI, **25-сек flush сценарій** (30 ISR пакетів → 15 уцілілих + 15 видимих втрат), count zero after full drain. Усі 126 queen tests зелені (113 baseline + 13 нові FW.3).

#### FW.4 — TinyML `Run_Inference()` закоментований
- `03_03` | `main.c:355`, `silken_net_audio_model.h` відсутній
- **Опис:** `Run_Inference()` закоментована; model header відсутній
- **Блокує:** Acoustic detection (chainsaw, cavitation, wind), Mongabay biodiversity pivot
- [ ] 👤 Тренування моделі (4 класи: silence/wind/cavitation/chainsaw)
- [ ] 👤 Генерація `silken_net_audio_model.h`
- [ ] 🔗 DSP preprocessing (FFT/MFCC або вбудований у модель)
- [ ] 🔗 Verify Tensor Arena size (< 54 KB)
- [ ] 🔗 Розкоментувати `Run_Inference()`
- [ ] 🔗 Host-based тести
- [ ] 🌿 **FW.4-EXT (Mongabay pivot, post-TRL 7):** Розширення моделі з 4 → **5 класів** з додаванням `4 = fauna_activity` (циркадний dawn/dusk soundscape) — див. [`03_03` §10](../docs/03_03_TinyML_Acoustic_Inference). Залежить від калібрувального датасету ЧДТУ ПМКТ + ЧНУ Біо-хабу (UNI.11 + UNI.13a). Альтернативна архітектура: спектральний descriptor ACI (Acoustic Complexity Index) на STM32 без NN, як TRL-7 інкремент

### 🟠 P1 — Важливі

#### ✅ FW.5 — Lorenz Attractor: β-пертурбація від delta_t/vcap — РЕАЛІЗОВАНО
- `03_04`, `05_02`
- **Опис:** Spec: `calculate_state(delta_t, vcap)`, реалізація: `calculate_state(chaos_seed, temp, acoustic)`. Аналіз показав: `chaos_seed` (HRNG) вносить значний випадковий компонент у growth_points — при 250 ітераціях Ейлера Z суттєво залежить від початкових умов. `delta_t` та `vcap` — прямі фізичні індикатори метаболізму дерева.
- **Статус:** ✅ **Реалізовано (2026-04-30). Варіант B+:** зберегти FW.6 state continuity, chaos_seed тільки для cold-start; `delta_t_s`/`vcap_mv` передаються як soft β-perturbation. Firmware `bio_contract.rb` та backend `SilkenNet::Attractor` оновлені координовано. 500-case parity fuzz: 0 mismatches. `TelemetryUnpackerService` передає `metabolism_s`/`voltage_mv`.
- [x] 🤖 Математичний аналіз: порівняти variance Z від chaos_seed vs delta_t/vcap після 250 ітерацій
- [x] 🤖 Архітектурне рішення: замінити chaos_seed на delta_t (Варіант A), додати delta_t/vcap як додаткові пертурбації (Варіант B), або зберегти + EMA фільтр (Варіант C) — **обрано B+**
- [x] 🤖 Задокументувати рішення в `03_04` з обґрунтуванням впливу на токеноміку
- [x] 🤖 Реалізувати (firmware mruby + backend mirror update, 500-case fuzz)
- [x] 🤖 Передавання args[5..6] у C (EMA delta_t_s/vcap_mv з RTC DR10/DR12 у mruby args) — ✅ Виконано (2026-05-02). `firmware/soldier/main.c` біля `mrb_funcall_argv("calculate_state", 7, ...)`: warmup-guard `EMA_Is_Warmed_Up()` → `EMA_Get_DeltaT_Sec()` / `EMA_Get_Vcap_Mv()`; до warmup — нейтральні defaults `60 c` / `3300 mV` (= `BASELINE_DELTA_T_S` / `NOMINAL_VCAP_MV` у `bio_contract.rb`, β-перетурбація = 0). 6 host-тестів у `firmware/test/test_soldier_logic.c` блок `EMA → mruby calculate_state args[5..6]`: cold-boot defaults / warmup-phase defaults / warmed-up forwarding / boundary vcap=5500 / fast charge dt=1 / zero-input после warmup. 130 soldier tests passed, +6 від 124.

#### FW.7 — Float vs BigDecimal divergence (TRL 6 mitigation)
- `05_02`
- **Опис:** firmware `8.0/3.0 = 2.6666666666666665` vs backend BigDecimal `2.666666666666666667`
- **Статус:** ✅ Виправлено (TRL 6). Backend `SilkenNet::Attractor` переведено з BigDecimal на Float (IEEE 754 double) — ідентично firmware mruby. Dual Computation Integrity тепер дає однакові Z-значення на одній архітектурі
- ⚠️ *Увага: IEEE 754 Float математика все одно буде давати незначний drift між ARM (STM32 Soldier) та x86 (GCP/Akash Backend) архітектурами. Категоричний tolerance band (homeostasis/stress/anomaly) компенсує це для TRL 6, але строгий побітовий consensus потребує `ARCH.18`.*
- [x] Backend: замінити BigDecimal на Float в `SilkenNet::Attractor` (calculate_z, generate_trajectory, initialize_state)
- [x] Оновити тести (BigDecimal → Float assertions)
- [x] Задокументувати в `03_04` (BLOCKER-4 закрито)
- [ ] 👤 Верифікувати `MRB_USE_FLOAT` при першому lab-тестуванні (залишковий ризик)

#### FW.8 — CRITICAL_Z_MIN/MAX hardcoded
- `05_02`, `04_01`, `04_02`
- **Опис:** firmware: global 2.0/45.0 vs backend: per-species через `TreeFamily`
- **Рішення:** OTA sync species-specific thresholds
- **Статус:** 🟡 **Deferred TRL-7.** Rails-сторона реалізована (2026-04-30); firmware-парсер написано як freeze-контракт (`Soldier_Handle_CMD_SET_THRESHOLDS` у `firmware/soldier/main.c` + 12 host-тестів у `test_soldier_logic.c`), АЛЕ виклик у production-цикл захищено `#define FW8_PARSER_ENABLED 0`. Бекенд `OtaPackagerService.build_threshold_config_block` — лише class method, через `OtaTransmissionWorker` не передається. **Причина defer:** STM32WLE5JC має лише 20 RTC Backup Register'ів (DR0..DR19), повністю зайнятих (SSOT: `03_01 §2`). Єдиний вільний DR15 (4 байти) — недостатньо для 8-байтного body порогів. Flash-варіант відкинуто (wear + erase-time LoRa-deafness). На TRL-6 всі 5 видів використовують ті самі firmware-defaults, тому feature нічого не змінює. **Розблокування:** після FW.21 EMA-рефакторингу або щільнішої упаковки DR8/9/11 — якщо звільниться 1 регістр, увімкнути `FW8_PARSER_ENABLED 1` + boot-restore + KENOSIS-write блок.
- [x] 🤖 Додати thresholds до OTA config payload (build_threshold_config_block)
- [x] 🤖 Backend: effective_lorenz_thresholds 3-tier + Cluster lorenz_overrides_by_species
- [x] 🤖 Integration tests: fw8_threshold_governance_spec.rb
- [x] 🤖 Firmware C-side parser: `Soldier_Handle_CMD_SET_THRESHOLDS` + 12 host-тестів (frame layout, CRC16, invariants) — freeze-контракт
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

#### FW.18 — Hardcoded confidence threshold 0.80
- `03_03` BLOCKER-6
- **Опис:** `if (ml_confidence > 0.80)` hardcoded в Flash. Неможливо remote-tune для різних лісів/сезонів. Немає "warning" рівня (лише binary: alarm / no alarm)
- **Статус:** 🤖 ✅ Реалізовано (firmware-частина): RTC-storage у `DR13/DR14` + dual-threshold decision logic + Phase 5 writeback + 19 host-tests (44 у TinyML suite, 283 загалом). Hardcoded `0.80` повністю замінено зонами SILENCE/WARNING/CRITICAL з ескалацією. **Уточнення розташування:** оригінальний дизайн вказував `DR6/DR7`, але після FW.21 ці регістри зайняті (`DR6 = mesh_relay_payload[12..15]`, `DR7 = tree_did`); канонічна SSOT-таблиця в `03_01` §2 показує `DR13/DR14` як вільний резерв (єдиний залишок `DR15`). **OTA CMD dispatcher закрито** (2026-05-02) — Soldier-side downlink-CMD-фреймворк реалізовано окремою опкод-картою: `0x9D = CMD_SET_AUDIO_THRESHOLDS` (FW.18) щоб не зіткнутися з `0x9A = CMD_SET_THRESHOLDS` (FW.8 Lorenz Z thresholds). Парсер у `firmware/soldier/main.c` Сценарій 2 + 7 host-тестів (default/CRC/range/inversion/short_frame). Опкод-карта SSOT: `0x99=OTA / 0x9A=Lorenz thresholds / 0x9B=HMAC trailer / 0x9C=TIME_SYNC envelope / 0x9D=audio confidence thresholds`.
- [x] 🤖 Зберегти threshold у RTC Backup Register (updateable via OTA) — RTC + decision logic + tests + dispatcher (2026-05-02)
- [x] 🤖 Дизайн dual-threshold: WARNING (0.60) → event counter; CRITICAL (0.85) → Emergency TX
- [x] 🤖 Реалізація dual-threshold zones з warning_counter ескалацією (3× → fallback Emergency для chainsaw)
- [x] 🤖 19 host-тестів: 9 zones + 10 validation/RTC roundtrip
- [x] 🤖 Doc оновлено: `03_03` BLOCKER-6 (DR6/DR7 → DR13/DR14, ✅ partial), `03_01` §2 (RTC map), `04_06` §2.5 (test count 25→44)
- [x] 🤖 Soldier OTA CMD dispatcher (`CMD_SET_AUDIO_THRESHOLDS` 0x9D) + 7 host-тестів (2026-05-02)

#### FW.19 — Float32 vs Float64 mruby compile flags
- `03_04` BLOCKER-4
- **Опис:** mruby без `MRB_USE_FLOAT` використовує double (64-bit), з прапорцем — float (32-bit). Makefile не верифікований. Різниця ±5-10 units на Z-осі після 250 ітерацій може змінити bio_status (false slashing)
- **Статус:** 🟡 Частково вирішено. Tolerance band задокументовано як "by design" через категоричну перевірку в `check_z_divergence!`. Верифікація mruby compile flags — при першому lab-тестуванні
- [x] Задокументувати tolerance підхід (категоричний, не числовий) в `03_04` BLOCKER-4
- [ ] 👤 Верифікувати mruby compile flags (`MRB_USE_FLOAT` у Makefile або mrbconf.h) при lab-тестуванні

#### FW.20 + FW.20-S2 — Time Sync (Rails ↔ Queen ↔ Soldier)
- **SSOT (повний контекст, wire-формати, регресійний бенч):** [`03_02 §5а Time Sync — Канонічний хаб`](03_02_Queen_Gateway_Firmware). Цей запис у 00_08 — лише чек-лист прогресу.
- **TRL impact:** P2 для TRL-6 (`Derive_Cold_Start_State` живе з ±12 год толерантністю); блокер для TRL-7 (ARCH.26 TDMA, HMAC nonce replay-protection, корельовані події fire detection ±1 сек).

**FW.20 (Rails+Queen+Soldier 1-hop) — ✅ Done:**
- [x] 🤖 Backend `CoapEncryption` envelope `[0x9C][unix_ts_be:4][payload]` + 47/47 specs
- [x] 🤖 Queen parsing CMD_TIME_SYNC envelope, `Apply_Server_Time` → `queen_unix_ts`
- [x] 🤖 Queen periodic `Broadcast_Time_Beacon()` (15 хв, ECB 16-байт LoRa, suppressed коли ts=0)
- [x] 🤖 Soldier RX-гілка: приймає beacon, оновлює `soldier_unix_ts` (1-hop reach)
- [x] 🤖 14 host-тестів (8 Queen + 6 Soldier RX)
- [ ] 👤 Lab drift compensation тест при ΔT = ±60°C (потребує термокамери — TRL-7)

**FW.20-S2 (mesh-relay extension, 5 підпунктів) — 4 з 5 ✅ Done, 1 deferred:**
- [x] 🤖 (1/5) Authoritativeness flag — `BEACON_AUTH_FLAG=0x80` у byte 9 + Soldier RX зчитування у `time_source_authoritative` (5 host-тестів)
- [x] 🤖 (2/5) Drift-monitor + panic sync request — `Soldier_Should_Request_Time_Sync` + `Build_Time_Sync_Request_Payload` (опкод 0x56 + magic 'S'); 9 host-тестів. Активація потребує hot-path вшивання у RX TX queue (окрема ітерація).
- [x] 🤖 (3/5) Per-hop drift compensation — `Soldier_Try_Relay_Time_Beacon` (Provisioner-only, 6 reasons of drop, freeze-contract callable); 13 host-тестів. Активація потребує Queen TTL≥2 + anti-storm bitmap.
- [ ] 🟡 (4/5) Anti-storm dedup bitmap — потребує вільного RTC регістра (DR15 наразі резерв; стратегія див. [`03_01 §2.3 ARCH.28`](03_01_Firmware_Lifecycle_and_DMA))
- [x] 🤖 (5/5) Gossip-piggyback freeze-contract — `Soldier_Pack_Gossip_Ts_Byte` / `Soldier_Try_Apply_Gossip_Ts` у byte 14 normal-telemetry payload (2026-05-03); 7 host-тестів. ±128 sec window, не cold-start sync — refines local drift через сусідні uplink'и без TDMA. Активація потребує hook у Phase 2 (1 рядок) + RX-обробник для нормальних telemetry-кадрів.

**Cross-ref:** ARCH.26 (TDMA Sync Windows), FW.30 (cold-start `epoch_day` consumer), SEC.10 (panic frame counter — disambiguator FW.29 PANIC_FLAG_BIT для нормал/паніка байтів 14-15).


#### FW.21 — Edge data aggregation (RAM-aware Soldier)
- Legacy notes + `08_02` (Kalman filter Vector 4) | P2 (потребує R&D partnership)
- **Опис:** Soldier MCU має обмежений RAM (~20 KB вільного). Поточна архітектура: кожен wakeup → один 21-байтний пакет → TX. Для майбутнього (Kalman filtering, TinyML context) потрібна локальна агрегація
- **Рішення:** Moving average / EMA прямо на MCU. Відправляти на Queen лише: (1) поточне значення, (2) дельту від попереднього EMA, (3) стиснуті "summary" пакети. Зменшує трафік LoRa та економить батарею
- **Статус:** 🤖 ✅ **Реалізовано** в `firmware/soldier/main.c` (секція 1.10) — `EmaState` + 4 функції (`EMA_Update`, `EMA_Get_DeltaT_Sec`, `EMA_Get_Vcap_Mv`, `EMA_Is_Warmed_Up`), інтегровано в Phase 1 SENSE main loop. Persistence через RTC Backup Registers: **DR10** (`ema_delta_t_x100`, full uint32) + **DR12** (`[valid:8 \| count:8 \| ema_vcap_x10:16]`, packed) — vcap_x10 максимум 5500×10 = 55 000 ≤ 2¹⁶, тому пакується в low 16 біт, **звільняючи DR11 під 3-й anti-pingpong slot** (`MESH_DID_CACHE_SIZE` 8→3 fallback від попередньої спроби 8→2). VBAT-loss reset тригерить warmup (3 цикли). Тести: **102 passed** у `firmware/test/test_soldier_logic.c` (10 EMA-тестів + оновлений 3-slot mesh suite: `test_mesh_3_slots_all_known`, `test_mesh_4th_evicts_oldest`, `test_mesh_pingpong_scenario` + RTC pack/unpack roundtrip із новою розкладкою DR12). **Передавання EMA значень у mruby `calculate_state()` — НЕ реалізовано тут**, винесено в задачу FW.5 B+ (потребує координованого backend апдейту: `SilkenNet::Attractor` β-пертурбація mirror, per-tree EMA state на сервері, 50k fuzz-тести Z-divergence < 1%, міграція DB).
- [x] 🤖 Визначити які метрики потребують EMA (delta_t, vcap — кандидати)
- [x] 🤖 Реалізувати lightweight EMA на Soldier (O(1) memory, O(1) compute)
- [ ] 👤 Інтегрувати з Kalman filter design (E.10 — Косенук)
- [x] 🤖 Верифікувати RAM footprint залишається < 80% available — 10 байтів static (0.015% від 64KB SRAM)

#### FW.22 — acoustic_events payload overflow (uint16 → uint8 truncation)
- `03_03` BLOCKER-7
- **Опис:** `acoustic_events` — тип `uint16_t` в firmware, але в 21-байтний пакет пишеться лише молодший байт (low byte). Якщо між TX циклами більше 255 подій — silent overflow, дані корумпуються. Backend отримує обрізане значення без можливості виявити overflow
- **Пріоритет:** P2 (рідкий сценарій при нормальній роботі, критичний при stress-тестуванні)
- **Статус:** ✅ Виконано (Сесія 18). Тип змінено на `uint8_t`, додано saturating increment `if (acoustic_events < 255) acoustic_events++`. Packing спрощено (ternary видалено). 8 unit tests.
- [x] Firmware: обмежити `acoustic_events` до `uint8_t` з saturating increment (cap at 255)
- [ ] 🔗 АБО: виділити 2 байти в payload (потребує перепакування — пов'язано з FW.2 CCM transition)
- [x] Backend: додати warning якщо `acoustic_events == 255` (ймовірний overflow) — реалізовано в `TelemetryUnpackerService`
- [x] Backend: `TELEMETRY_ACOUSTIC_OVERFLOW_TOTAL.increment` при `acoustic_events == 255` — Prometheus counter для Grafana alerting реалізовано в `TelemetryUnpackerService`

#### FW.23 — OTA firmware broadcast: ECB без автентифікації
- `03_05` | `firmware/queen/main.c`
- **Опис:** OTA bytecode chunks (`[0x99][index:2][total:2][bytecode:11]`) передаються через AES-256-ECB без MAC/signature. Зловмисник може підмінити firmware chunks → code injection на всіх Soldiers у радіусі Queen. Відсутня верифікація цілісності зібраного bytecode перед записом у Flash (`0x0803F000`)
- **Пріоритет:** P1 (критичний для security, але блокується FW.2 CCM transition)
- **Статус:** 🤖 ✅ Реалізовано (2026-05-02). Backend HMAC-SHA256 повний пайплайн + Soldier dual-gate framework + Queen stateless relay. Implementation:
  - **Backend:** `OtaHmacKeyService.fetch_for(cluster_id)` — HKDF-SHA256 з info `"silken-ota-hmac-v1"` (domain separation від FW.1 AES key); `SecurityError` без master key (SEC.11 hard cutover). `OtaPackagerService.compute_hmac_tag(bytecode, version_id, lora_total_chunks, cluster_id:)` — anti-replay+anti-truncation binding. `OtaPackagerService.build_hmac_trailer_chunks` — 3 LoRa-formatted блоки `[0x9B][seg_idx:2][total:2][hmac:11]`. `OtaPackagerService.prepare(..., cluster_id:)` — opt-in, backward-compat без cluster_id. **30 нових RSpec прикладів** (services + integration end-to-end).
  - **Firmware Queen:** stateless relay — `Handle_CoAP_Command` зберігає `[0x9B]` chunks у `pending_ota_hmac_chunks[3][16]`, reflex broadcast loop додає Phase 1 (HMAC trailer broadcast після Phase 0 bytecode). 4 host-тести (segments assemble, seg_idx_4 reject, wrong marker, overwrite same segment).
  - **Firmware Soldier:** `Parse_HMAC_Trailer_Chunk` парсер (`received_hmac_tag[32]`, `ota_hmac_segments_received` bitmask) + Gate 1 magic `0x45544952` "RITE" + Gate 2 HMAC verify constant-time (`Hmac_Constant_Time_Compare`) перед `Write_OTA_Contract_To_Flash`. Fail-safe: затирання magic у RAM-bytecode при negative gate щоб частково записаний OTA не активувався. `OTA_Verify_Dual_Gate` placeholder для mbedTLS HMAC compute — actual MCU integration deferred to lab build (відповідає FW.30 cold-start placeholder pattern). 13 host-тестів (3-chunk assemble, out-of-order, marker/seg_idx/size rejects, both-pass/magic-fail/hmac-fail/short, constant-time first/last byte).
- [x] 🤖 Дизайн OTA authentication protocol — повний дизайн HMAC-SHA256 у `03_05` §3.4б
- [x] 🤖 Backend: підпис OTA image перед відправкою (`OtaHmacKeyService` + `OtaPackagerService.compute_hmac_tag`/`build_hmac_trailer_chunks`)
- [x] 🤖 Firmware Queen: stateless-relay `[0x9B]` chunks ідентично до `[0x99]` (без verification — backend↔soldier end-to-end trust)
- [x] 🤖 Firmware Soldier: dual-gate verification (magic `0x45544952` "RITE" + HMAC constant-time) перед Flash write
- [x] 🤖 Magic check + HMAC verification = dual gate (host-test framework + fail-safe RAM wipe)
- [ ] 🟡 mbedTLS HMAC-SHA256 compute on STM32 HASH peripheral — deferred до lab integration (analog FW.30 mbedTLS deferred TODO)

#### FW.25 — TinyML DSP preprocessing (FFT/MFCC) — undefined
- `03_03` BLOCKER-5 | `firmware/soldier/main.c` | **P0 (Mongabay pivot)** — раніше P1, переведено у P0 після [`03_03` §10](../docs/03_03_TinyML_Acoustic_Inference): без MFCC принципово неможливо розрізнити layered soundscape (комахи + птахи + амфібії dawn/dusk) від шуму вітру у часовій області. Блокує FW.4-EXT (5-class fauna)
- **Опис:** Поточна архітектура передає лише лінійну нормалізацію [0.0, 1.0] до TinyML моделі. **Невідомо**, чи модель очікує raw time-domain, чи частотні ознаки (FFT/MFCC). Залежить від `silken_net_audio_model.h` (відсутній). Якщо потрібен MFCC — це додає ~5-15 KB Flash + ~40 µs CPU на inference. **Mongabay підсилення (травень 2026):** Delgado et al. на 119 ділянках Коста-Ріки інструментально показали, що `forest cover ≠ forest function` — і це розрізнення доступне лише через спектральну структуру звуку, а не часову. MFCC стає обов'язковим компонентом, не опціональним
- [ ] 👤 Узгодити з ML-партнером (Бушин ЧНУ ФОТІУС або Любченко): який preprocessing вбудований у модель?
- [ ] 🤖 Якщо MFCC — оцінити Flash/RAM/CPU budget і інтегрувати CMSIS-DSP (`arm_rfft_fast_f32`, `arm_dct4_f32`)
- [ ] 🤖 Тести: золотий вектор inference (наперед відома класифікація)
- [ ] 🌿 Cross-ref UNI.11 + UNI.13a: акустичний датасет dawn/dusk Черкаського бору

#### FW.26 — TENSOR_ARENA_SIZE ніколи не верифіковано
- `03_03` BLOCKER-3 | `firmware/soldier/main.c` | **P1**
- **Опис:** Точна величина `TENSOR_ARENA_SIZE` невідома з коду — документація оцінює ~8-16 KB. Ніколи не виміряно через `arm-none-eabi-size`. Якщо tensor arena > 46 KB → stack overflow при Lorenz обчисленнях (250 ітерацій mruby + Lorenz state)
- [ ] 🤖 Запустити `arm-none-eabi-size firmware/soldier/build/soldier.elf` після додавання моделі (FW.4) → виміряти `.bss + .data`
- [ ] 🤖 Якщо > 46 KB — оптимізувати модель (INT8 quantization, prune)
- [x] 🤖 CI gate: build fail якщо `.bss + .data > 50 KB`
- **Статус (CI gate, 2026-05-03):** ✅ **Активовано** через host-build placeholder. `make -C firmware/test size-check` запускає host gcc проти `test_soldier` + `test_queen`, рахує `.bss + .data` і fail'ить якщо > 51200 байт. Поточна baseline: soldier=2.5 KB, queen=12.4 KB — комфортно < 50 KB. Інтегровано в існуючий `firmware_test` job у `.github/workflows/ci.yml` як окремий step. Negative-test перевірено: `SIZE_LIMIT_BYTES=1000 make size-check` коректно повертає exit 1 з повідомленням про перевищення budget. Host build НЕ ідентичний ARM build (mock-структури, host-stdlib), але поділяє ті ж глобальні буфери (`raw_audio_buffer`, OTA chunk map, EMA state etc.) — регресія тут = регресія на target. Co-existence з існуючим `firmware_ram_budget` job (який очікує ARM ELF artifacts через `arm-none-eabi-size`): обидва будуть жити паралельно, host gate закриває розрив **зараз**, ARM gate — після lab build pipeline (FW.4).

#### FW.27 — OTA broadcast: відсутня RX-верифікація Soldier
- `03_02` §5 | **P2**
- **Опис:** Queen транслює OTA chunks послідовно через LoRa без перевірки чи Soldier активно слухає. Якщо Soldier у STOP2 під час broadcast — chunk втрачається без retry. Документація **не описує recovery механізм** для пропущених chunks. Без TDMA Sync Windows (ARCH.26) — broadcast ненадійний
- **Статус:** 🤖 ✅ Дизайн **обох** recovery-механізмів завершено + Дизайн B повністю реалізовано (2026-05-02). (1) **ACK-Aggregation (Дизайн A):** Queen чекає 10-сек aggregation window після broadcast, Soldier'и відправляють bitmap-ACK; aggregated_missing → targeted re-broadcast. Імплементація залежить від ARCH.26 TDMA — без скоординованих RX-вікон 100 Soldier'ів = collision storm. (2) **Magic Re-Request (Дизайн B) — реалізовано:** Soldier при `ota_chunks_received < ota_total_chunks` після `OTA_REREQUEST_TIMEOUT_MS` (5 хв) тиші формує uplink-пакет `[0x55][DID:4][total:2 BE][bitmap:9]` через `Build_OTA_ReRequest_Payload`; Queen приймає у `Process_LoRa_RX` (НЕ йде у CIFO/CoAP — це службовий control-пакет), дедуплікує `(DID, missing_bitmap)` через `cmd_dedup_ring` з новим `djb2_hash_bytes` (length-strict NUL-safe варіант — fix collision-bug де total_chunks BE-upper байт = 0 для total<256), потім targeted re-broadcast лише missing chunks (60-90% economy vs повний wave). 22 host-тести (12 Soldier bitmap correctness + 10 Queen dedup/total-mismatch/CIFO-bypass). Дизайн B feasible **без ARCH.26** — використовує існуючий `random_jitter % 500ms` (FW.10) для collision avoidance. Дизайн A — спільно з ARCH.26.
- [x] 🤖 Дизайн ACK-aggregation: Queen чекає consolidated ACK після всіх chunks → re-broadcast пропущених (`03_02` §5.X.2)
- [x] 🤖 Magic re-request: Soldier при detected gap → request specific chunks via uplink (vector OTA, `03_02` §5.X.3)
- [ ] 🔗 Залежить від ARCH.26 (TDMA для координованого RX вікна) — лише для Дизайну A; B реалізовано незалежно
- [x] 🤖 Магічна Re-Request Дизайн B — повна імплементація (firmware/soldier + firmware/queen + 22 host-тести) — 2026-05-02
- [x] 🤖 **Edge cases follow-up (2026-05-03):** 6 додаткових host-тестів — anti-tamper duplicate з іншим payload, STOP2 between OTA chunks (out-of-order + duplicate after sleep), HMAC trailer cross-cycle persistence + idempotent overwrite, total_chunks=0 malformed packet. Деталі: [`03_02 §5.X.5 FW.27 follow-up`](03_02_Queen_Gateway_Firmware). Жодних змін у production firmware — це freeze-contract regression bank.

#### FW.29 — Panic packet (0xFF) vs saturated acoustic_events (255) — disambiguation
- `03_03` §5.3 | **P1**
- **Опис:** Panic пакети (chainsaw detection) форматуються з маркером `0xFF` (255). Saturated acoustic_events теж досягає 255 (FW.22 cap). **Без MAC/MIC** Queen не може розрізнити: bit-flip атака може перетворити нормальний пакет з 255 events на panic broadcast → false fire alert. Вирішується разом з FW.2 (CCM MIC), але потребує окремого дизайну на канальному рівні
- **Статус:** ✅ Виконано. `PANIC_FLAG_BIT` (0x80) додано в біт 7 StatusByte (байт 10). Нормальні пакети маскують біт 7 (`& 0x7F`), panic пакети встановлюють його. StatusByte формат: `[panic:1 | status:2 | growth_points:5]`. 2 unit tests: `test_panic_flag_set_in_emergency_payload`, `test_normal_payload_panic_flag_clear`.
- [x] 🤖 Дизайн: окреме поле `panic_flag:1 bit` у StatusByte (звільнити 1 біт від growth_points 6→5)
- [x] 🤖 АБО: panic packets мають окремий destination header byte
- [ ] 🔗 Інтегрувати з FW.2 CCM transition

#### FW.29-PACK — StatusByte layout collision з PANIC_FLAG_BIT (silent corruption fix)
- `firmware/bio_contracts/bio_contract.rb`, `firmware/queen/main.c`, `app/services/telemetry_unpacker_service.rb` | **P1** | 🔗 closure для FW.29
- **Опис:** SSOT-аудит (2026-05-13) виявив, що FW.29 додав `PANIC_FLAG_BIT = 0x80` у bit 7 StatusByte і нормальні пакети маскують `lora_payload[10] &= ~PANIC_FLAG_BIT`, але `bio_contract.rb` продовжував пакувати `(status << 6) | growth_points` (status у bits 7..6). Bit 7 status'у конфліктував з PANIC_FLAG_BIT mask'ом → backend читав:
  - `status=2` (anomaly) → `0x80 | gp` → mask → `0x00` → `(0x00 >> 6) = 0` (homeostasis) — **anomaly events silently lost**
  - `status=3` (tamper) → `0xC0 | gp` → mask → `0x40` → `(0x40 >> 6) = 1` (stress) — **tamper events demoted**
  - `BIO_STATUS_VM_ERROR=0xFF` (crashed mruby) → mask → `0x7F` → `(0x7F >> 6) = 1` (stress), `gp=63` — **crashed VM мінтить SCC як здорове "stressed" дерево**
  - Queen CIFO eviction (`firmware/queen/main.c:835`) використовує той самий `>> 6` → anomaly/tamper trees не отримували cache-pressure protection
- **Документи з canonical layout** (`docs/03_01 §1.6` line 443, `docs/03_05 §FW.2` line 147) уже описували правильний `[PanicFlag:1 | Status:2 | GrowthPoints:5]` — лише код від нього відстав.
- **Статус:** ✅ Виконано (2026-05-13). Wire format узгоджено з документованим дизайном:
  - **Firmware mruby (`bio_contract.rb`):** `(status << 5) | growth_points`, gp clamped до 0..31, reward `(50 - dev) / 2` для 5-bit wire space
  - **Firmware Queen (`main.c`):** `QUEEN_HEALTH_GP_MAX = 31`, sentinel cap, eviction `(payload[10] >> 5) & 0x03`
  - **Backend ×2 upscale** на unpack: `growth_points: (status_byte & 0x1F) * 2` → stored 0..62 (vs old 0..63, **≤1.6% resolution loss**); `bio_status: (status_byte >> 5) & 0x03`. **Tokenomic invariant збережений** — `Wallet#lock_and_mint!` 10 000-point threshold та emission rate без змін.
  - **Tests:** 504 firmware host tests + 74 RSpec examples pass. Додано 2 firmware regression guards (`test_bio_anomaly_survives_panic_mask`, `test_status_anomaly_no_panic_bit_collision`, `test_vm_error_byte_0xFF_decodes_as_tamper_after_mask`) + 2 backend regression specs (anomaly/tamper survive PANIC_FLAG_BIT mask).
  - **Doc cleanup:** `03_01 §11.5` (packing example), `03_02 §6.4` (Queen CIFO + Sentinel cap), `03_04 §4.3/§4.4/§5.2` (formula + bit diagram + verification flow), `05_02` (3 діаграми pipeline + storage layout), `04_02` Solana reward range, `07_02` GP/SCC unit economics, `08_06`/`08_04` cross-refs.
- [x] 🤖 Firmware fix (3 files: bio_contract.rb, queen/main.c, telemetry_unpacker_service.rb)
- [x] 🤖 Test updates (3 firmware test files + 1 RSpec) + 5 нових regression guards
- [x] 🤖 SSOT cross-doc audit + cleanup (8 documents)

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
- **Статус:** ✅ Виконано (2026-05-02). Warm/cold paths об'єднані у єдиний 7-arg `mrb_funcall_argv("calculate_state", 7, ...)`. `Load_Lorenz_Seed()` зчитує K_seed з Flash (`FLASH_SEED_ADDR = FLASH_KEY_ADDR + 36`, magic `"LSED"` = `0x4C534544`). `Derive_Cold_Start_State()` — placeholder hash деривація (TODO: mbedTLS HMAC-SHA256 при lab-тестуванні). Cold-start більше не використовує `chaos_seed`. 11 нових host-тестів у `test_soldier_logic.c`. Всі 335 firmware tests pass.
- [x] 🤖 Дизайн нової C-bridge сигнатури (7-arg + cold-start HKDF path)
- [x] 🤖 Firmware `soldier/main.c` — оновити mruby виклики до нової єдиної 7-arg сигнатури (warm + cold paths)
- [x] 🤖 Firmware cold-start — замінити `chaos_seed` path на K_seed-derived cold-start (`Load_Lorenz_Seed()` + `Derive_Cold_Start_State()`, placeholder hash — TODO: mbedTLS HMAC-SHA256)
- [x] 🤖 `firmware/test/` — додати C-bridge integration test (11 нових тестів: 6 seed loading + 4 cold-start + 1 C-bridge 7-arg)
- [ ] 🔗 Після FW.30 — FW.5 B+ (передавання EMA delta_t/vcap як args[5..6]) стає незалежним кроком

#### FW.31 — DCI: числовий tolerance band у `check_z_divergence!` (feature-flag flip)
- `app/services/telemetry_unpacker_service.rb`, `docs/03_04` §BLOCKER-2 | **P2**
- **Опис:** Після SEC.11 обидві сторони стартують з byte-identical `(x₀,y₀,z₀)` і виконують ідентичну Float IEEE-754 математику. Емпіричний Float divergence ARM↔x86 за 250 ітерацій < 1e-12. Проте `check_z_divergence!` зберігає **категоричну** перевірку (homeostasis/stress/anomaly enum match) замість числового `|server_z − device_z| < ε`. Числовий tolerance band (`ε < 0.001`) вже закоментований як "готовий до flip" у docs/03_04 §BLOCKER-2.
- **Умова для flip:** потрібно виміряти реальний drift `server_z − device_z` на цільовому ARM hardware (STM32WLE5JC vs GCP x86-64) з тією ж Float/mruby compile-flag комбінацією. Очікуваний drift < 0.001 — це значно менше розміру одного growth_points step (~1 unit), тому false-слешинг малоймовірний.
- **Вплив після flip:** fraud detection стає **числовим** — дозволяє виявляти не лише категоричні (homeostasis vs stress) помилки, але й систематичне зміщення Z (наприклад, replay атаку з правильним status-byte але неправильним Z magnitude).
- [ ] 👤 Лабораторне вимірювання: запустити однакові тест-вектори на STM32WLE5JC + GCP x86-64, виміряти `|server_z - device_z|` distribution (N=10,000)
- [x] 🤖 Після вимірювання: flip `check_z_divergence!` до числового `|server_z - device_z| < ε` під ENV feature-flag (`GAIA_DCI_NUMERIC_TOLERANCE`) — ✅ Code-ready (2026-05-02). `TelemetryUnpackerService#check_z_divergence!` тепер має numeric-branch під двома ENV: `GAIA_DCI_NUMERIC_TOLERANCE=true` (off за замовчанням → нульова поведінкова зміна для production) + `GAIA_DCI_NUMERIC_EPSILON` (Float, default = `DEFAULT_DCI_EPSILON = 0.001`, malformed value graceful fallback). Numeric branch виконується **лише** коли `attributes[:device_z]` присутній — сьогодні LoRa packet (21B) не несе raw Z, тож branch інертний у production до post-FW.2 packet revision. 6 нових spec examples у `spec/services/telemetry_unpacker_service_spec.rb` describe `[FW.31] numeric tolerance band`: toggle off / within ε silent / drift > ε fraud / default ε constant / malformed ENV fallback / device_z missing. Awaits 👤 lab measurement реального ARM↔x86 IEEE-754 drift.
- [ ] 🤖 Специфікація: оновити `03_04` §BLOCKER-2 з виміряним drift + обраним ε (потребує лабораторних даних, попередньо ε=0.001)

#### FW.42 — Vcap guard для fauna acoustic sampling (brownout protection)
- `firmware/soldier/main.c` (FW.4 fauna sampler), `docs/03_03` §10.3 | **P1**
- **Опис:** Після audit-fix енергетичного бюджету (`03_03 §10.3`, патч 2026-05-16) реальна вартість одного fauna-сесійного циклу = **~78.3 мДж** (× 20 від попередньої оцінки `3.3 мДж/доба`). Активний CPU під час 156 MFCC+inference вікон тягне ~12 мА × 1.56 с → транзієнтна просадка V_cap. При `V_cap ≈ 3.5 V` (margin ~100 мВ над `VBAT_OK ON = 3.4V`) просадка ~37 мВ ставить EDLC на межу — будь-який concurrent TX = brownout посеред інференсу.
- **Рішення:** Guard clause `Fauna_Should_Sample(uint16_t vcap_mv)` — повертає 1 коли V_cap ≥ FAUNA_VCAP_MIN_MV, інакше 0 і інкрементує saturating uint8 counter `fauna_skipped_low_vcap`.
- **Статус (✅ firmware-side, 2026-05-16):** Helper реалізовано як **freeze-contract** у `firmware/soldier/main.c` (поряд із TinyML threshold-блоком). 8 host-тестів у `firmware/test/test_soldier_logic.c` (constant=4500 / allowed at threshold / allowed above / blocked below / blocked deep-brownout / counter increments / counter saturates uint8 / mixed calls preserve count). 260/260 soldier tests pass. **Активація** — 2 рядки у fauna-pathway, коли FW.4 розкоментує `Run_Inference()`.
- [x] 🤖 Firmware — `Fauna_Should_Sample()` helper + `fauna_skipped_low_vcap` saturating counter (2026-05-16)
- [x] 🤖 Host tests — 8 examples у `test_soldier_logic.c` секція "Fauna Vcap Guard (FW.42, freeze-contract)"
- [ ] 🔗 Активація: викликати `Fauna_Should_Sample()` всередині fauna-pathway після FW.4 uncomment
- [ ] 🤖 Прометей метрика + Grafana panel "Fauna skip rate per cluster" — після FW.4 (метрика без даних = шум)

#### FW.43 — 03_05 §3.1 SSOT drift (привид hardcoded AES-key після FW.1)
- `docs/03_05_Hardware_AES256_and_Security.md` §3.1 | **P3**
- **Опис:** Hot-fix doc-only. FW.1 (Per-device HKDF provisioning) вже реалізовано — `Load_AES_Key()` зчитує унікальний ключ з Protected Flash. Проте §3.1 досі описує "ідентичний на ВСІХ вузлах" + hardcoded `uint32_t aes_key[8] = { 0xXXXXXXXX, ... }`. Це SSOT-drift, який вводить в оману нових інженерів.
- [x] 🤖 Замінити блок §3.1 на актуальний (`uint32_t aes_key[8] = {0};` + посилання на `Load_AES_Key()` у §3.4а HKDF derivation) — ✅ BLOCKER-1 оновлено до `✅ Firmware CLOSED (FW.1)`, historical code анотовано, status table виправлено (2026-05-17)
- [x] 🤖 Прибрати фразу "Ідентичний на ВСІХ вузлах мережі" — поточна архітектура per-device unique через HKDF — ✅ header змінено на `✅ BLOCKER-1: ... Firmware CLOSED`; historical блок чітко анотований `[PRE-FW.1 HISTORICAL]` (2026-05-17)
- [x] 🤖 **Розширено scope (2026-05-17):** Той самий SSOT-drift виправлено у `03_01 BLOCKER-1` + `03_02 BLOCKER-1` + status tables (03_01, 03_02, 03_05 §10) + `03_05 §9 Resources` (provisioning endpoint `Майбутній` → `✅ Реалізовано`) + `03_02 §BLOCKER-7 Footer` (IV reuse mitigation note) + `03_02 §13 Cross-ref` (Factory Flashing row) + `CLAUDE.md §12 HW-AES-KEY`. Усі посилання cross-ref на новий `03_05 §3.4г`.

---

## 🧭 Architecture / SSOT-drift fixes (2026-05-16 cross-doc audit)

> Знахідки з рев'ю модулів 00_, 01_, 02_, 03_, 03_05 (інженерний аудит, 2026-05-16). Слоти ARCH.39–ARCH.42 зарезервовано під цей патч-комплект.

#### ARCH.39 — Fauna acoustic energy budget — арифметична + системна корекція
- `docs/03_03_TinyML_Acoustic_Inference.md` §10.3 | **P2** | ✅ **Doc-fix вкочено 2026-05-16**
- **Опис:** Перша редакція §10.3 містила (1) арифметичну помилку `1 мА × 3.3V × 10 с = 3.3 мДж` (правильно 33 мДж — у 10× нижче), (2) ігнорування активного CPU під час MFCC+inference (~12 мА × 1.56 с). Реальна вартість fauna-сесії ≈ 78.3 мДж/сесію, ~156.6 мДж/добу (× 20 від оригінальної оцінки). Все ще сумісно з EDLC бюджетом, але імпульсна потужність потребує V_cap guard'у — див. **FW.42**.
- [x] 🤖 Перерахувати таблицю енергобюджету у `03_03` §10.3 (1 мА wait + 12 мА active phases)
- [ ] 🔗 Узгодити sensitivity-модель `02_03 §9.6 Сценарій C` з новими цифрами

#### ARCH.40 — Fauna 5-секундне вікно: монолітне awake-обчислення (SRAM2 wipe constraint)
- `docs/03_03_TinyML_Acoustic_Inference.md` §10.2 | **P1** | ✅ **Doc-fix вкочено 2026-05-16**
- **Опис:** Architecture v3 використовує STOP2 RTC-only з `PWR_CR1_RRSTP=1` → SRAM2 wipe при кожному переході в сон. Декомпозиція 5 с акумульованого вікна (156 MFCC-векторів `mean+std`) на «32 мс → STOP2 → 32 мс» неможлива: проміжна float-матриця у RAM не переживе сну, DR15 (єдиний вільний RTC регістр) не вміщає float[156][N_mfcc].
- **Рішення:** Явно зафіксовано у §10.2 — fauna-сесія мусить виконуватись монолітно за один цикл активного пробудження (156 циклів TIM2+DMA послідовно).
- [x] 🤖 Додати constraint-блок у `03_03` §10.2
- [ ] 🔗 При імплементації FW.4 fauna-pivot: вимагати unit-тест `test_fauna_sampling_no_stop2_in_session()`

#### ARCH.41 — Cold-start Time Paradox для Dual Computation Integrity
- `docs/03_04_mruby_Lorenz_Attractor.md` §2.1, `firmware/soldier/main.c` `Derive_Cold_Start_State`, `app/services/telemetry_unpacker_service.rb#compute_server_z` | **P2**
- **Опис:** Після VBAT loss Soldier'ський RTC скидається на default-дату (2000-01-01) → `Derive_Cold_Start_State()` обчислює `epoch_day ≈ 10 951` замість серверного ≈ 20 585. Server при дереві з історією chain'ить з попереднього `lorenz_state_tail` (не cold-derive) → траєкторії розходяться категорично доки `CMD_TIME_SYNC` beacon від Queen не оновить RTC Soldier'а.
- **Поточний імпакт:** Категоричний DCI можуть тригерити false-positives на cold-boot пакетах (≤ 50 wake-up циклів до ergodicity ~2 доби). Numeric DCI branch (FW.31) інертний у production (LoRa packet 21B не несе raw Z) — стане критичним після post-FW.2 packet revision.
- **План мітигації (вибрати один):**
  - **(A) Server-side fallback** (рекомендовано, без firmware change): У `compute_server_z` при категоричному DCI mismatch + tree має історію → retry через cold-start derivation з трьома кандидатами `epoch_day` (today, today−1, firmware RTC-default ≈ 10 951). При збігу — позначити `TelemetryLog#time_unsynced_fallback = true`, queue `CMD_TIME_SYNC` через downlink, не падати DCI.
  - **(B) Soldier-side sentinel** (потрібен координований firmware rollout): При cold-boot Soldier шле `acoustic_events = 0xFE` як sentinel у першому uplink. Backend трактує як «time uncertain».
  - **(C) Defer first uplink** (потребує firmware redesign): Soldier у grace-вікні (10 хв) шле спрощений «hello» пакет без Lorenz state — тільки DID + Vcap + TIME_REQ маркер.
- [x] 🤖 (A) Реалізувати `compute_server_z` retry logic + `time_unsynced_fallback` колонка — ✅ Виконано (2026-05-17). `TelemetryUnpackerService#try_time_sync_recovery` + `FIRMWARE_RTC_DEFAULT_EPOCH_DAY=10_951`. Колонка `time_unsynced_fallback boolean NOT NULL DEFAULT false` squash'нута в `db/structure.sql` (parent + 7 partitions, O(1) PG16). 9 нових spec examples. Документовано: `04_01` (TelemetryLog fields), `04_02` (ARCH.41 fallback row).
- [x] 🤖 (A) Trigger CMD_TIME_SYNC downlink — ✅ Виконано (2026-05-17). `TimeSyncDownlinkWorker` (queue: downlink, retry: 2). Envelope-only CoAP: `coap_encrypt("".b, key)` → Queen `Handle_CoAP_Command` line 1203-1204 → `inner_aligned==0` → `return` після `Apply_Server_Time`. Endpoint: `/cmd/time_sync`.
- [ ] 🔗 (B/C) Розглянути після стабілізації (A) — потребують координованого firmware rollout

#### ARCH.42 — ATECC608B AES-128 vs system AES-256 апаратний конфлікт
- `docs/03_05_Hardware_AES256_and_Security.md` §3.7 | **P1**
- **Опис:** §3.7 пропонує мапінг Slot 0 → "AES-128 key", але вся мережа Gaia 2.0 використовує AES-256 (`CRYP_KEYSIZE_256B` у STM32WLE5JC + `MX_CRYP_Init` у `soldier/main.c`). Microchip ATECC608B апаратно **не підтримує AES-256** — лише AES-128. Якщо перенести шифрування всередину чипа (key never leaves SE), доведеться даунгрейдити всю мережу до AES-128. Якщо ж зберегти AES-256, потрібно витягувати ключ із SE у RAM MCU — це нівелює DPA/EM захист, заради якого вводився SE.
- **Архітектурне рішення (вибрати):**
  - **(A) Змінити Secure Element** на NXP EdgeLock SE050 або STSAFE-A110 з підтвердженою підтримкою AES-256 у HW. Збільшує BOM (~$2–4 vs ATECC ~$0.85), але зберігає крипто-консистентність.
  - **(B) Даунгрейд LoRa-каналу до AES-128.** AES-128 — золотий стандарт IoT (LoRaWAN використовує саме його). Оновити `MX_CRYP_Init` (`CRYP_KEYSIZE_256B → CRYP_KEYSIZE_128B`), всі doc-посилання, HKDF output length, AES key column у `HardwareKey` (64 hex → 32 hex). Коштує меншу security margin (`2^128` все ще практично нездоланно) і зберігає DPA-захист SE.
- **Рекомендація:** Варіант (B) — AES-128 для LoRa каналу. Аргументи: (i) industry-standard для constrained IoT, (ii) дешевший BOM, (iii) `ATECC608B` вже у плані як комбо-SE для ECC P-256 signing + ECDH, (iv) симетричний AES-128 переважає у LoRaWAN/Helium/Sigfox-екосистемах — простіше bridging. **Вплив:** ~2 тижні firmware/backend rework + переписати всі `MX_CRYP_Init` тести.
- **Cross-ref:** SEC.6 (Secure Element не використовується) — вирішується разом з ARCH.42.
- [ ] 👤 Архітектурне рішення A vs B (потребує stakeholder review — security margin vs BOM cost)
- [ ] 🤖 Після рішення: глобальний SSOT-патч (03_05 + 03_01 + 04_01 HardwareKey schema + firmware AES init + всі тести)
- [ ] 🔗 Блокує: SEC.6 (Secure Element integration), будь-який BOM freeze з ATECC608B

---

## 🧪 Hardware / Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

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

#### HW.4 — Self-healing coating (NEW: zone-restricted)
- **Джерело:** `01_02` §3 + `01_02` §3.6
- **Опис:** 8-HQ мікрокапсули не синтезовані
- **⚠️ Zone restriction:** Self-healing наноситься **тільки на неактивні поверхні** (зовнішня сорочка катодного фланця Zone 3, торці PEEK-втулки). НЕ наноситься на гіроїдні стінки Zone 1 (блокує DET) і не на катодну каталітичну поверхню (блокує DET до Cu T1 лаккази). Деталі — `01_02` §3.6.
- **Блокує:** 20+ років longevity claims, TRL 6
- [ ] 👤 Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] 👤 Інтеграція в PEO electrolyte або layer-by-layer — ТІЛЬКИ на дозволених зонах
- [ ] 👤 Тест: 10× вищий Rct
- [ ] 👤 **Thiol-Michael interphase** (`01_02` §1a.1): тест адгезії self-healing шару при ростовому навантаженні, порівняння з простою APTES-силанізацією — додано в `01_02`

#### HW.5 — Enzyme lifespan + H₂O₂ neutralization
- **Джерело:** `01_03` § 1–3 + Legacy notes
- **Опис:** Деградація ферментів у кислому ксилемному середовищі (pH 4.5–5.5) + токсичність H₂O₂ від GOx
- **Gen 1.0 baseline (REVISED 2026-05-16 — двошарова архітектура):** Двошаровий стек на аноді (`01_03` §2.1) — внутрішній електроактивний шар `fMWCNT + Os-полімер + GOx ONLY` (без катализи, щоб уникнути electron shunting через heme b group катализи + steric blocking FAD-центру GOx); зовнішній захисний шар `chitosan hydrogel + Catalase ALONE` (перехоплює H₂O₂ через diffusion barrier, регенерує O₂ назад у GOx); зовнішня Nafion-мембрана. На катоді — `Laccase + AuNPs + MWCNT` DET (`01_03` §2.2). Ціль 3–5 років.
- **Gen 2.0 ціль:** 20–25 років (GDH мутанти — без H₂O₂, стек спрощується до одного шару + Laccase/nanozyme + ZIF інкапсуляція)
- [ ] 👤 **Gen 1.0 anode (двошарова — пріоритет):** внутрішній GOx+Os electroactive layer + зовнішній Catalase-in-chitosan protective layer — `01_03` §2.1
- [ ] 👤 **Gen 1.0 anode (Combi-CLEA — NEGATIVE CONTROL):** одношарова Combi-CLEA для прямого порівняння (підтвердження ефекту shunting via CV/EIS) — `01_03` §2.1
- [ ] 👤 **Gen 1.0 cathode:** Laccase-AuNP DET stack замість Os-полімерного MET — `01_03` §2.2
- [ ] 👤 Розробка protective polymer matrix
- [ ] 👤 Тест Chitosan-шару (pH-буферизація) — додано в `01_03`
- [ ] 👤 Тест Nafion-покриття (селективна мембрана) — додано в `01_03`
- [ ] 👤 Тест комбінації Chitosan + Nafion (пріоритетний варіант)
- [ ] 👤 Тест: 3–5 років функціонального ферменту (Gen 1.0)
- [ ] 👤 **Gen 2.0:** GDH (Bacillus megaterium Q252L/E170K) замість GOx+CAT (взагалі без H₂O₂) — `01_03` §3.1
- [ ] 👤 **Gen 2.0:** Laccase + laccase-like nanozymes (Cu/Ce/Au ZIF) на катоді — `01_03` §3.2
- [ ] 👤 **Gen 2.0:** ZIF-інкапсуляція для 20–25 років — `01_03` §3.3
- [ ] 👤 **Bridge Gen 1.0→2.0:** мікропориста тейп-ізоляція + міцелярний модифікований Nafion (>1 рік lab data) — додано в `01_03` §2
- [ ] 👤 **Поліпірол (PPy)** як кополімерний підсилювач MET-стеку (паралельний з осмієвим полімером) — додано в `01_03` §2

#### HW.6 — Resin barrier + Flush Mount Installation
- **Джерело:** `01_04` §3 + Legacy notes
- **Опис:** Сосни заливають рану смолою → блокує доступ до ферментів. **Корінь проблеми = інструмент свердління**, а не лише матеріал анкера.
- **Стратегія:** (a) Flush Mount step drilling — анкер врівень з корою, камбій не пошкоджено; (b) Microfrezing замість стандартного свердла — хірургічно чистий розріз не тригерить resinosis
- [ ] 👤 **Flush Mount step drilling** (`01_04` §3.1): тестування багатоступеневого свердла на калібрувальних колодах сосни (товщина перидерми → ширина широкої ступені)
- [ ] 👤 **Microfrezing** (`01_04` §3.3): закупити прецизійні кінцеві фрези типу MicroX (карбід вольфраму + TiN-покриття), стендовий тест на колодах vs стандартні шнекові свердла — порівняння resinosis intensity
- [ ] 👤 30° installation angle verification (узгоджено з Flush Mount)
- [ ] 👤 Hydrophilic coating test
- [ ] 👤 PEG обробка гіроїда (Шар 5 анодного стеку, `01_03 §2.1 Крок 5`, REVISED 2026-05-16): PEG MW 4000–8000 dip-coat поверх Nafion 117, ~1–2 µm; смола зісковзує з PEG-покритих пор; H⁺-провідність Nafion зберігається >95%
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
- [x] 🤖 Оновити Unit Economics (07_02) — ✅ Phase 3 BOM таблиця (Queen ~$825 + $599 Starlink = $1,424/cluster), Phase 3 cluster economics ($5,404 CAPEX, $179/міс OPEX), ROI сценарії (breakeven SCC $0.41 standalone / $0.18 при 3-cluster sharing / $0.07 duty-cycle), стратегія Starlink sharing через ARCH.10 додано в `07_02` §4а + §5а

#### HW.15 — BMS + VBAT decoupling для SIM7070G
- **Джерело:** `02_05` BLOCKER-4, §2.2.1 (новий блок)
- **Опис:** SIM7070G TX peak current до 2A. Дві окремі проблеми: (1) BMS model не вказано в BOM (system-level); (2) транзієнтна просадка VBAT модему при 2A burst → brownout reboot (module-level). Тепер з обома вирішеннями.
- **Module-level fix (✅ specification зафіксовано 2026-05-16):** 5-cap tank bank біля VBAT pin SIM7070G — 470 µF aluminum polymer SP-Cap (Panasonic EEFCX0J471R) + 100 µF MLCC X7R 25V 1210 + 10 µF X7R 0805 + 100 nF X7R 0402 + 33 pF NP0 0402. Розрахункова просадка: 8 mV (margin > 35× проти 700 mV brownout). Деталі — `02_05 §2.2.1`.
- [ ] 👤 Обрати BMS: мінімум 12V / 20A continuous / 50A peak
- [ ] 👤 Обрати MPPT: мінімум Victron SmartSolar MPPT 75/15
- [x] 🤖 Специфікувати tank cap bank біля SIM7070G VBAT pin (`02_05 §2.2.1`, BOM позиції 17–20)
- [ ] 👤 PCB layout: розмістити C_BULK ≤ 10 мм від VBAT pin, HF caps впритул
- [ ] 👤 Оновити BOM (закупка 5 нових компонентів)

#### HW.16 — Thermal management в IP67 enclosure
- **Джерело:** `02_05` BLOCKER-5
- **Опис:** SIM7070G + MCU при TX: ~500 mW × 5 sec. Літній interior temp до 60-70°C. LiFePO4 charging при T < 0°C пошкоджує батарею; розряд нижче −20°C → graphite plating damage
- **Статус:** 🤖 ✅ Тепловий бюджет розраховано та задокументовано в `02_05` §4а «Тепловий бюджет IP67 корпусу» — Phase 1/2.5 (~130 мВт середнє → ΔT < 1 K) та Phase 3 (3 Вт burst → ΔT ~4.5 K), sun load — головний внесок (+15 K). Активне охолодження не потрібне при T_зовн ≤ +40°C. Sun-shade / світлий корпус — рекомендовано. Backend критична-температура гілка реалізована (2026-05-16).
- [x] 🤖 Розрахувати thermal budget для enclosure (T_ext = +40°C)
- [x] 🤖 Backend: `GatewayTelemetryLog::LOW_TEMPERATURE_THRESHOLD = -20` + scope `:freezing` + `critical_fault?` branch + `GatewayTelemetryWorker#format_health_message` ❄️ message + factory `:freezing` trait + specs (51/51 ✅) — 2026-05-16. Symmetry для overheat/freeze, спрацьовує до hardware charge MOSFET cut-off (рання попередня тривога операторам).
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
- [ ] 👤 Прийняти архітектурне рішення
- [ ] 🤖 Оновити 03_02 з рішенням
- [ ] 🔗 Додати co-processor firmware до `firmware/`

#### HW.19 — VOC-діагностика деградації конденсатора (ADS1220 + TPS22860)
- **Джерело:** Legacy notes + `02_04` §4.2
- **Опис:** Раз на добу вимірювати чисту VOC EBFC (при від'єднаному навантаженні) для розрізнення "дерево хворіє" vs "конденсатор деградує". Обидва стани проявляються як зростання delta_t. ADS1220 (24-bit ADC) + TPS22860 (load switch) для прецизійного duty-cycling вимірювання. Для TRL 6 достатньо вбудованого 12-біт ADC STM32
- **Пріоритет:** TRL 8+ (після базової валідації в полі)
- [ ] 🤖 Валідувати концепт на вбудованому 12-біт ADC (firmware: GPIO disconnect EDLC → measure VOC → reconnect)
- [ ] 👤 Якщо 12-біт недостатньо — додати ADS1220 + TPS22860 до BOM
- [ ] 🤖 Backend: поле `voc_mv` у TelemetryLog для серверної корекції моделі Лоренца

#### HW.20 — Buffer Cap: Tantalum → MLCC migration
- **Джерело:** `02_03` §6 + Legacy notes
- **Опис:** Buffer Cap 100µF на лінії VOUT для LoRa TX peak. Рання специфікація вказувала танталовий конденсатор, але його струм витоку (1-10 мкА) подвоює/потроює E_sleep (1.5 мкА). Документація оновлена на MLCC X5R/X7R (виток ~десятки нА)
- **Статус (🤖):** ✅ Виконано — DC bias derating (~20% при 3.3V/6.3V → ефективна ємність ~80µF) задокументовано в `02_03` §6 рядок 409 ("навіть 80 мкФ ефективної ємності більш ніж достатньо для покриття 100 мс LoRa TX піку").
- [ ] 👤 Обрати конкретний part number: 100µF/6.3V X5R 1210 (напр. Murata GRM32ER60J107ME20)
- [x] 🤖 Врахувати DC bias derating (~20% при 3.3V/6.3V → ефективна ємність ~80µF)
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
- [ ] 👤 **Stage 2 — Ti-coins (10 шт, 10×10×1 мм):** SLM-друк + EAAE (з обов'язковим dehydrogenation bake `01_02 §1.3 Крок 5b`) → паралельне тестування **трьох** анодних архітектур: (a) двошаровий GOx+Os внутрішній / Catalase-chitosan зовнішній (priority, `01_03 §2.1`), (b) Combi-CLEA одношарова (negative control), (c) GDH (Bacillus megaterium Q252L/E170K) одношарова; + Laccase-AuNP DET катодний стек → in vitro CV/EIS у синтетичному ксилемному соку (рецептура від біо-хабу ЧНУ, [`08_01`](08_01_University_R_and_D_Protocols))
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
- [ ] 👤 Створити Gnosis Safe wallet
- [ ] 👤 Reassign DEFAULT_ADMIN_ROLE у SCC та SFC контрактах

#### SEC.2 — RDP Level 2 activation timeline
- **Джерело:** `03_05` NOTE-1
- **Опис:** Поточний стан: RDP Level 0 (development). Level 1 потрібен перед першою польовою партією, Level 2 — тільки після повної OTA верифікації (незворотній — лише OTA updates можливі)
- **Статус:** 🤖 ✅ Процедура активації RDP Level 2 (pre-flight checklist + STM32CubeProgrammer CLI послідовність + поетапний rollout R&D→Pilot→Mass) задокументовано в `03_05` §3.6 «Процедура активації RDP Level 2 (необоротна)»
- [ ] 🤖 Верифікувати OTA flow end-to-end
- [ ] 👤 Перейти на RDP Level 1 для field batch
- [x] 🤖 Задокументувати процедуру Level 2 activation (необоротна)

#### SEC.3 — Factory Flashing pipeline
- **Джерело:** `03_05` NOTE-2
- **Опис:** Multi-step factory process: (1) Flash firmware з placeholder key, (2) Backend → HKDF(master_key, device_uid) → unique_key, (3) Robot пише key у protected Flash sector, (4) STM32CubeProgrammer → RDP Level 1/2
- **Блокує:** Mass production
- **Статус (🤖, 2026-05-13):** ✅ Дизайн Factory Flashing pipeline завершено та задокументовано у `03_05` §3.4 у вигляді двох гілок: Гілка A (Protected Flash Sector, TRL 6/7, ≤10k unit) та Гілка B (ATECC608B/STSAFE-A110 Secure Element, mass production >10k або high-value). Включено: decision matrix (pilot / 1-10k / >10k / regulated), defense-in-depth таблицю, двошарову схему lock (data zone lock + RDP), latency/power/cost impact, irreversibility note (B→A неможливо). Cross-ref до §3.4а (HKDF) та §3.7 (SE оцінка).
- [x] 🤖 Дизайн завершений — ✅ `03_05` §3.4 Гілка A + Гілка B (2026-05-13)
- [ ] 🤖 Реалізація Factory Flashing tool
- [ ] 🤖 Integration тест з provisioning API
- [x] 🤖 **Задокументувати Factory Flashing pipeline як окрему секцію** з явною позначкою **"Internal Admin Tool, поза публічним REST API"** (запит: 2026-05-17). Розмежування з `/api/v1/provisioning/register` (registration-after-deployment) має бути нерозмитим: `04_03 §5.2` залишається Zero-Trust (no keys in response), нова секція описує **окремий канал** доставки ключів програматору. Проектування з нуля з повним threat model:
  - **Access control до `PROVISIONING_MASTER_KEY`:** хто (роль/особа) має право запускати tool, як master key потрапляє у tool (HSM injection / envelope encryption / short-lived token + KMS), як ротується, fail-closed boot guard (cross-ref `master_key_strength_check.rb` SEC.11)
  - **Anti-key-leak via factory operator:** operator UI показує тільки `status: key_burned` (без raw key), key flow `tool → SWD/JTAG → protected Flash sector` без проходження через operator screen / clipboard / logfile, secure RAM wipe після write, відсутність персистентного key cache на factory machine, screen-recording mitigations
  - **Audit-trail provisioning сесій:** append-only chain-hashed log (паттерн `AuditLog` з `pg_advisory_xact_lock`) — operator_id + supervisor_id + device_uid + timestamp + ATECC serial (Гілка B); інтеграція з `MaintenanceRecord(action_type: :installation)` у backend (закриває loop "fizzично прошито ↔ DB-зареєстровано"); tamper-evident retention policy
  - **Гілка A vs Гілка B threat model diff:** як змінюється attack surface при переході Protected Flash → ATECC608B (chip-swap detection через `(device_uid, atecc_serial)` pinning — вже згадано у §3.4, але threat model має це formalізувати)
  - **Цільова секція:** ✅ `03_05 §3.4г Factory Flashing Operations Security` (2026-05-17) — покриває всі 4 вимоги: A. Access Control, B. Anti-Key-Leak, C. Audit-Trail, D. Threat Model Гілка A vs B
  - **Cross-ref:** SEC.1 (Multisig для admin role), SEC.2 (RDP Level 2), SEC.6 (ATECC608B), SEC.9 (FIPS test vector guard), `03_05 §3.4` (existing pipeline design — extend, not duplicate)

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **Джерело:** `03_05` NOTE-3
- **Опис:** Reed switch (магнітний сенсор) для zero consumption при транспортуванні. Магніт на коробці → circuit open. Інсталятор знімає магніт → first power-up. ~$0.05/unit. Дизайн approved, BOM не оновлений
- [ ] 👤 Додати Hamlin 59140-1-T-00-A reed switch + N52 neodymium magnet до BOM
- [ ] 👤 Оновити KiCad schematic

#### SEC.6 — Secure Element (ATECC608B) не використовується
- **Джерело:** `03_05` | Firmware architecture
- **Опис:** AES-256 ключ зберігається у plain Flash STM32 (навіть з RDP Level 1 — key extraction можливий через glitching/side-channel). ATECC608B забезпечує hardware-protected key storage з tamper-detection. Ціна ~$0.60/unit
- **Пріоритет:** P2 (Post-TRL 7, перед mass production >1000 units)
- **⚠️ Cross-ref ARCH.42:** ATECC608B апаратно підтримує лише AES-128, але система Gaia 2.0 використовує AES-256. Вибір Secure Element і вибір cipher strength — взаємозалежні рішення. **Не реалізовувати SEC.6 до архітектурного рішення ARCH.42** (A: змінити SE на NXP SE050/STSAFE-A110 з AES-256, B: даунгрейд LoRa-каналу до AES-128).
- **Статус:** 🤖 ✅ Інтеграційна оцінка ATECC608B з STM32WLE5JC задокументована в `03_05` §3.7 «ATECC608B Secure Element — оцінка інтеграції»: I²C interface (PB6/PB7), slot mapping (slot 0=AES, 1=ECC priv, 2=cert, 3=HMAC OTA), latency impact (~1.5 мс/блок vs 10 µs HAL_CRYP — нехтовно), power impact (+0.1% energy budget), Factory Flashing pipeline з ATECC, альтернатива STSAFE-A110 (native CubeMX, переважна для unified ST toolchain), OPTIGA Trust M (overkill), NXP A71CH (EOL — уникати). Firmware HAL drop-in API окреслено. Factory Flashing pipeline §3.4 оновлено (2026-05-13) з Гілкою B що включає повний I²C provisioning sequence, `(device_uid, atecc_serial)` pinning (tamper-detect chip swap), slot write послідовність та dual lock strategy.
- [x] 🤖 Оцінити ATECC608B integration з STM32WLE5JC (I²C interface)
- [x] 🤖 Дизайн key storage: ATECC608B slot 0 = AES key, slot 1 = device certificate
- [x] 🤖 Оновити Factory Flashing pipeline (SEC.3) для ATECC608B provisioning — ✅ Виконано (2026-05-13). `03_05` §3.4 містить повну Гілку B з ATECC608B/STSAFE-A110: I²C provisioning sequence (7 steps), (device_uid, atecc_serial) pinning для chip-swap tamper detection, slot mapping cross-ref до §3.7, irreversibility note, decision matrix pilot/1-10k/>10k/regulated
- [x] 🤖 Оцінити альтернативи: STSAFE-A110 (ST ecosystem), Infineon OPTIGA Trust M

#### SEC.7 — OTA image автентифікація (cross-ref FW.23)
- **Джерело:** `03_05`, `03_02`
- **Опис:** OTA broadcast (mruby bytecode та потенційно firmware updates) не має цифрового підпису. Пов'язано з FW.23 але виділено як окремий security item через критичність.
- **Пріоритет:** P1 (перед першою OTA в полі)
- **Статус (🟡 частково вирішено через FW.23, 2026-05-02):** HMAC-SHA256 dual-gate реалізовано: `OtaHmacKeyService` (HKDF-SHA256, domain separation від FW.1 AES key) + `OtaPackagerService.compute_hmac_tag / build_hmac_trailer_chunks` (backend) + Soldier dual-gate (magic `"RITE"` + HMAC constant-time verify) + Queen stateless relay `[0x9B]` chunks. HMAC обраний як основний підхід (Ed25519 потребує ~512 байт SRAM + 50 мс — критично для STM32WLE5JC). **Залишається:** mbedTLS HMAC-SHA256 compute на STM32 HASH peripheral — deferred до lab integration (placeholder у `OTA_Verify_Dual_Gate`). Ed25519 — відкладено Post-TRL 7.
- [x] 🤖 **HMAC-SHA256 dual-gate (обраний підхід):** `OtaHmacKeyService` + `OtaPackagerService` + Soldier/Queen firmware — ✅ виконано через FW.23
- [ ] 🟡 mbedTLS HMAC-SHA256 compute на STM32 HASH peripheral — deferred до lab build (cross-ref FW.23)
- [ ] 🔗 Ed25519 key pair (Post-TRL 7, якщо SRAM бюджет дозволить після RTOS/FW.2 оптимізацій)

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **Джерело:** `03_05` | **Пріоритет: P0 (до будь-якого field deploy)**
- **Опис:** Аудит виявив: перші 4 слова production AES key **ідентичні публічно відомому** FIPS-197 Appendix B AES-128 test vector (стандартний тест-вектор зі специфікації NIST). Будь-який фахівець з криптографії може впізнати цей паттерн. При RDP Level 0 — trivial key extraction
- **Важливо:** Це ОКРЕМЕ від FW.1 (hardcoded key) — навіть після per-device provisioning, якщо master seed базується на цьому ключі, весь derivation tree скомпрометований
- **Статус (🤖 verification, 2026-05-12):** ✅ Автоматизовано через `Security::WeakKeyDetector` (`app/services/security/weak_key_detector.rb`) + boot-time guard `config/initializers/master_key_strength_check.rb`. Production refuses to boot якщо `PROVISIONING_MASTER_KEY` співпадає з: FIPS-197 App.B/C.1-C.3, NIST SP 800-38A F.5, RFC 3686/4231 HMAC test cases, FIPS 198-1, виродженими патернами (all-zero/all-0xFF/single-byte repeat/монотонна), плейсхолдерами (`CHANGEME`, `your-master-…`, `<…>`). Перевіряє raw + hex-decoded + base64-decoded інтерпретації. 30 specs (`spec/services/security/weak_key_detector_spec.rb`). Bypass: `SILKENNET_SKIP_MASTER_KEY_STRENGTH_CHECK=1` (rescue-boot, логується гучно). Документація у `03_05` §3.1а
- [ ] 👤 Негайно замінити seed key на криптографічно стійкий random (hardware RNG або аудитований генератор)
- [x] 🤖 Верифікувати що новий master key НЕ є жодним відомим test vector (FIPS-197, NIST, RFC) — автоматичний boot-time guard, див. статус вище
- [ ] 👤 Задокументувати процес генерації нового master key у vault (Bitwarden/1Password) — **без коміту ключа в репозиторій**
- [ ] 👤 Після заміни: re-flash всі існуючі прототипи

#### SEC.10 — Emergency TX пакети без MAC/MIC автентифікації
- **Джерело:** `03_05`, `03_02` | **Пріоритет: P1**
- **Опис:** EwsAlert panic packets (chainsaw detection, PANIC_TTL=5) відправляються без жодної автентифікації. Зловмисник може: (1) replay легітимний panic packet → false forest fire alert → евакуація/паніка, (2) inject forged panic packets → множинні false alarms → недовіра до системи та страхових виплат
- **Важливо:** Критичніше за звичайні пакети — emergency TX обходить звичайні rate limits. Вирішується разом з FW.2 (AES-256-CCM), але потребує окремої уваги через life-safety implications
- [x] 🤖 Не відкладати вирішення на "після FW.2" — мінімальний fix: Frame Counter у RTC як anti-replay для panic packets
- [ ] 🔗 Верифікувати що `EwsAlert` broadcast застосовує той самий CCM MIC що і звичайні пакети (після FW.2)
- [x] Backend: rate limiting на emergency callbacks — не більше N panic alerts/хвилину від одного DID
- **Статус (Frame Counter anti-replay, 2026-05-03):** ✅ **Реалізовано як життєво-безпекова сторожа панічного каналу до приходу повного FW.2 CCM.**
  - **Firmware (Soldier):** `panic_frame_counter` (uint16, monotonic + saturating @ 0xFFFF) пакується у `RTC_BKP_DR0[31:16]` поряд з `acoustic_events` у `DR0[7:0]` — **без використання нових RTC слотів** (DR15 залишається вільним для майбутніх фічей). Cold-boot resync через HRNG (range 0x0001..0xFFFF) уникає колізії з ще-не-протухлими nonce-ключами Redis попереднього втілення. Counter інкрементується перед кожним `Trigger_Emergency_LoRa_TX`, пакується BE у `panic_payload[14..15]` (вільні PAD-байти), персистується у DR0 НЕГАЙНО + при Phase 5 + при PVD-брауноуті (ARCH.21 callback теж збергіає packed DR0).
  - **Backend:** `TelemetryUnpackerService` детектує panic через `status_byte & 0x80` (FW.29 PANIC_FLAG_BIT), читає counter з `pad_data[2..3].unpack1("n")`, виконує SETNX через `Rails.cache.write(unless_exist: true)` з ключем `silken:panic:nonce:{hex_did}:{counter}` і TTL 25 годин. При replay → log warning + Prometheus increment + early return (TelemetryLog НЕ створюється, AlertDispatchService не викликається). Counter==0 (legacy firmware без SEC.10) пропускає перевірку, бо існує rate-limit на AlertDispatchService рівні (вже існував).
  - **Метрики:** новий Prometheus counter `silkennet_panic_replay_rejected_total` (`SilkenNet::Metrics::PANIC_REPLAY_REJECTED_TOTAL`) — Grafana alert при різкому стрибку = можлива spoofing-атака.
  - **Тести:** 13 host-тестів firmware (`test_sec10_*` у `test_soldier_logic.c`: DR0 packing roundtrip, BE counter encoding, saturate @ 0xFFFF, cold-boot HRNG reseed, warm-boot preserve, two-panic distinct nonces, no-overlap with DID/PANIC_FLAG/firmware_id) + 8 backend rspec у `spec/services/telemetry_unpacker_service_spec.rb` (fresh accept, replay reject, distinct counters accepted, distinct DIDs accepted, non-panic skip, legacy counter=0 skip, FW.22 firmware_id coexistence, TTL guard ≈ 25h).
  - **DR map оптимізація:** замість претендування на новий регістр (DR15 був останнім вільним), packing у DR0 економить дефіцитний ресурс RTC Backup Domain — критично для майбутніх ARCH.21 brownout state extensions.

#### SEC.11 — Lorenz Seed Provenance (Dual Computation Integrity hardening) — **✅ DONE**
- **Джерело:** `03_04` BLOCKER-1 cross-ref, `03_05` §3.4а K_seed | **Пріоритет: P1** | **Закрито:** 2026-05-02 (PR `copilot/update-documents-and-tests`)
- **Опис (історичний):** Firmware mruby `bio_contract.rb` стартував атрактор з `(x₀,y₀,z₀)` виведених із `chaos_seed = HRNG()` (Soldier-side) і `DID` (server-side mirror). DID їде відкритим текстом у заголовку LoRa-пакета (`[DID:4]`, поза AES-блоком). Чотири фундаментальні вади: (1) публічний seed → атакер з open-source формулою Лоренца обчислює очікуваний Z для будь-якого дерева → підробляє телеметрію з валідним StatusByte, `check_z_divergence!` мовчить; (2) сусідні DID видаються послідовно → перші ~30 ітерацій Ейлера дають майже ідентичні траєкторії (знижена статистична ентропія); (3) семантична помилка категорій — DID *identifier*, не *key*; (4) відсутність forward secrecy.
- **Прийнятий дизайн (гібрид A + B + D):** `K_seed = HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info="silken-lorenz-seed|<DID>", len=32)`, виведений при provisioning, збережений в `hardware_keys.lorenz_seed_hex` (AR Encryption non-deterministic) і в Soldier Flash. Daily epoch rotation: `(x₀,y₀,z₀) = unpack_signed_unit_floats(HMAC-SHA256(K_seed, "init|" || epoch_day_be)[0..23])` — forward secrecy ≤ 24 год, синхронізовано через FW.20 `CMD_TIME_SYNC`. Cold-start derive відбувається лише після VBAT loss (рідкісна подія); у норму FW.6 RTC continuation (DR16-DR18 magic `"LZST"`) пропускає re-init. Документація — у §03_04 §2.1 (entry-point), §03_05 §3.4а (HKDF info-string), §04_01 (HardwareKey + TelemetryLog колонки), §04_02 (`SilkenNet::SeedDerivation`), §04_03 (provisioning контракт), §05_02 (DCI pipeline).
- **Ефект на DCI:** обидві сторони стартують з byte-identical `(x₀,y₀,z₀)`. Float divergence між ARM та x86 IEEE-754 за 250 ітерацій < 1e-12 (емпірично, FW.7 closure). `check_z_divergence!` зберігає категоричну невідповідність і отримує hook для числового tolerance band — flip під feature-flag після інструментального вимірювання реального drift.
- **Hard-cutover deliverables (pre-prod, без shim'ів):**
  - [x] 🤖 Schema migration `db/migrate/20260502090000_add_lorenz_seed_provenance_columns.rb` — `hardware_keys.lorenz_seed_hex` (RANGE-partitioned `telemetry_logs` отримує `lorenz_state_x/y/z` + `cold_start_flag` через DDL на parent + всі live partitions)
  - [x] 🤖 `SilkenNet::SeedDerivation` (HKDF-SHA256 + HMAC-SHA256 + signed-unit-float unpack) + 16 examples в `spec/services/silken_net/seed_derivation_spec.rb`
  - [x] 🤖 `HardwareKey#binary_lorenz_seed` (AR Encryption non-deterministic, як `binary_key`); `lorenz_seed_hex` validated `presence: true`
  - [x] 🤖 `Attractor.calculate_z_from_state(x0, y0, z0, σ, ρ, β, n)` — sole entry-point; legacy `calculate_z(chaos_seed, ...)` та `calculate_z_continued` ВИДАЛЕНО (не deprecated — hard cutover)
  - [x] 🤖 `TelemetryUnpackerService` — single K_seed-derived path; raises `MissingLorenzSeedError` при відсутньому K_seed; persist `lorenz_state_x/y/z` + `cold_start_flag` на кожному uplink; chaining continuation з попереднього `TelemetryLog` tail
  - [x] 🤖 `HardwareKeyService.provision` — деривує AES key + K_seed одним викликом (single source of truth); raises `SecurityError` без `PROVISIONING_MASTER_KEY` (no SecureRandom fallback ANYWHERE — навіть у dev/test, тести pin-ять `PROVISIONING_MASTER_KEY` в `spec/rails_helper.rb`)
  - [x] 🤖 `ProvisioningController#register` — НІКОЛИ не повертає `aes_key`/`lorenz_seed`/`warning` (Zero-Trust)
  - [x] 🔥 Firmware `bio_contracts/bio_contract.rb` — sole entry-point `calculate_state(x_prev, y_prev, z_prev, …)`; chaos_seed і всі legacy сигнатури видалено
  - [x] 🔥 `firmware/test/test_bio_contract.c` — нова сигнатура `calculate_z_axis(x, y, z, …)`; `seed_to_xyz()` test helper для детермінованих фікстур
  - [x] 🔥 `firmware/test/test_seed_derivation.c` — host-based parity test (OpenSSL HKDF/HMAC = mbedTLS на MCU), 13 examples
  - [x] 🤖 `db/seeds.rb` + `spec/factories/hardware_keys.rb` — populate `lorenz_seed_hex`
  - [x] 🤖 `docs/03_06_Lorenz_Seed_Provenance` — DELETED, контент розподілено в `03_04`/`03_05`/`04_02`/`05_02` (див. вище)
- **Свідомо НЕ робимо** (pre-prod, no field devices, no prototypes, no firmware in flight): `POST ty6/api/v1/provisioning/upgrade_seed` field-migration endpoint, TRL4 lab-mode response, SecureRandom fallback в `Rails.env != production`.

---

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
- **Статус:** ✅ Виконано. `.github/workflows/trl_sync.yml` створено з GraphQL API для GitHub Projects v2 (user + org fallback)
- [x] Створити `.github/workflows/trl_sync.yml`
- [x] Налаштувати GraphQL API для GitHub Projects v2
- [ ] 👤 Створити `PROJECT_PAT` secret з project:write scope
- [ ] 👤 Тестування з тестовими issues

#### OPS.2 — SSOT Integrity Guard
- **Джерело:** `00_07` | **Складність: M**
- **Опис:** GitHub Action що блокує merge PRs якщо зміни в `app/models/` або `firmware/` не супроводжуються відповідними оновленнями в `docs/` або Wiki. Запобігає context drift між кодом та документацією
- **Статус:** ✅ Виконано (Сесія 18). `.github/workflows/ssot_guard.yml` створено. Перевіряє: `app/models/`, `firmware/soldier/`, `firmware/queen/`, `firmware/bio_contracts/`, `contracts/`, `app/services/`. Bypass через label `ssot-bypass`. Виводить деталізований звіт у PR check.
- [x] Створити `.github/workflows/ssot_guard.yml`
- [x] Визначити mapping: які файли потребують яких doc updates
- [ ] 👤 Налаштувати як required check на `main` branch

#### OPS.3 — R&D Portfolio Management: Shape Up + cluster routing
- **Джерело:** `08_01` §1.1-1.3, `08_02` §1, `08_03`, `00_05` | **Складність: L** | **🤖 Методологія + Док**
- **Опис:** 25+ паралельних R&D-задач розподілені між 8+ науковцями (ChNU FOTIUS + ChDTU + ChIPB + ChMA + СЄУ). Поточно — ad-hoc розподіл. Запропоновано: 4-кластерна структура (A: Hardware/EBFC, B: Verification/Math, C: Scaling/Cloud, D: Compliance/Legal) + Shape Up 6-week cycles + Convolution Method для скорочення PN-state explosion 10-100×
- **Статус (🤖, 2026-05-12):** ✅ Документація готова. (1) `docs/00_05` §5 — повна Shape Up cycle template: 4 кластери з ролями та командами, 8-тижневий timeline (6+2), shaping document template, betting table процедура (6 steps × конкретний час), cool-down checklist. (2) `docs/00_07` §6 — kanban-mapping 4 кластерів у Projects V2: нові fields (`R&D Cluster`, `Shape Up Stage`, `Cycle`), label conventions (4 primary cluster labels + 4 cross-ref + 6 shape lifecycle labels з hex-кольорами), auto-routing rules для `actions/labeler@v5`, первинний betting cycle checklist для UNI.1 / UNI.8. Залишається 👤 перший betting cycle після UNI.1/UNI.8 confirms.
- [x] 🤖 Дизайн kanban-mapping: 4 кластери у GitHub Projects V2 + label conventions — `docs/00_07` §6
- [x] 🤖 Документувати у `00_05` Shape Up cycle template + betting table процедуру — `docs/00_05` §5
- [ ] 👤 Перший betting cycle після UNI.1 (декан) та UNI.8 (СЄУ)

#### OPS.4 — GitHub Projects V2: семестрова синхронізація з ChNU/ChDTU
- **Джерело:** `00_07`, `08_01` | **Складність: M** | **🤖 Код**
- **Опис:** TRL-матриця прив'язана до seasons (Q1/Q2/Q3/Q4), але навчальний рік ChNU/ChDTU має семестри (вересень-грудень, лютий-травень). Без mapping — milestone-deadlines не синхронізовані з академічним календарем (наприклад, фінальні захисти магістерських у червні)
- **Статус (🤖, 2026-05-12):** ✅ Mapping + automation готові. (1) `docs/00_07` §5 додано — таблиці семестрів (Fall 1.IX–31.I / Spring 1.II–30.VI / літня перерва) + мапінг TRL milestones на семестри + hard deadline 15.VI для фінальних захистів. (2) `.github/workflows/trl_sync.yml` розширено: при кожному `issues.closed` скрипт обчислює completion semester з `closed_at` (UTC) і пише у single-select поле `Academic Semester` Projects V2, якщо воно існує. Graceful no-op якщо поле/опція відсутні (TRL Auto-Advancement залишається первинним інваріантом). Опції створюються адміністратором один раз (`Fall 2025-2026`, `Spring 2025-2026`, … на 3-5 років наперед). **Cron-driven "Current Semester"** (1.IX / 1.II) свідомо не входить у цей цикл — `issues.closed` штампує *completion*, не *active*
- [x] 🤖 Додати у `00_07` mapping: семестр ↔ TRL milestone — `docs/00_07` §5
- [x] 🤖 Розширити `trl_sync.yml` на запис академічних semestriv як окремий field у Projects V2 — gracefully optional, не ламає TRL sync
- [ ] 👤 Узгодити календар з 8 науковцями ФОТІУС (UNI.2 — 8 зустрічей)
- [ ] 👤 Створити single-select field `Academic Semester` у Projects V2 + опції `Fall {Y}-{Y+1}` / `Spring {Y-1}-{Y}` на 3-5 років наперед

#### OPS.6 — Bootstrap scripts для GitHub Projects V2 + IaC initial sync
- **Джерело:** `00_07` §1.2 + §6 | **Пріоритет: P2** | **Складність: M** | **🤖 Код**
- **Опис:** `00_07` посилається на два планований скрипти, яких **не існує**: (1) `bin/setup_github_project.sh` — створює Projects V2 fields (`Current TRL`, `Target TRL`, `Assigned Agent`, `Module`, `Appetite`, `R&D Cluster`, `Shape Up Stage`, `Cycle`, `Academic Semester`) через `gh api graphql` (gh CLI не підтримує `project add-field` повністю); (2) `bin/bootstrap_github.sh` — orchestrate: label sync (через push, що тригерить `labels_sync.yml`) → fields create → first milestone (`Cycle 2026.QN`) → baseline shaping docs. Без них нові ВНЗ-партнери або deploy у форкований репозиторій вимагає ручного клікання у GitHub UI, що суперечить IaC філософії `00_07`.
- **Статус (✅ виконано 2026-05-16):** Ядро логіки винесене у `lib/github_bootstrap.rb` (testable Ruby), bash-скрипти — тонкі обгортки. Field schema у `GithubBootstrap::FIELDS` — SSOT для 10 полів (9 single-select + 1 TEXT), TRL шкала 1–12 під `Beyond TRL 9` (00_06 §7). Idempotency через GraphQL fetch + diff by name. Rake tasks `github:project_fields` і `github:bootstrap` (з auto-default `Cycle YYYY.QN`). 16 RSpec прикладів покривають: idempotent skip, error paths, milestone create-or-skip, field schema invariants. Без живого `gh` CLI — executor мокається.
- [x] 🤖 Написати `bin/setup_github_project.sh` (тонка обгортка над `rake github:project_fields`)
- [x] 🤖 Написати `bin/bootstrap_github.sh` (orchestration: gh auth check → fields create → milestone create)
- [x] 🤖 Hooks у `Rakefile`: `rake github:bootstrap[cycle_title]` як user-facing entry-point
- [x] 🤖 Spec/тест: 16 прикладів у `spec/lib/github_bootstrap_spec.rb` з stubbed executor (без потреби живого репо)
- [ ] 👤 Запустити `bin/bootstrap_github.sh` проти живого Projects V2 при першому setup'і / в новому fork'у

#### OPS.8 — TreeFamily seed drift vs Lorenz attractor SSOT (`db/seeds.rb`)
- **Джерело:** Cross-doc audit 01_01–01_04 + 03_04 (2026-05-16) | **Пріоритет: P1** (silent — fail-shut, не fail-fast) | **Складність: XS** | **🤖 Код**
- **Опис:** Рядки 196–212 `db/seeds.rb` сіяли `Pinus sylvestris` з `critical_z_min: -2.5, critical_z_max: 2.5` і `Quercus robur` з `-3.0 .. 3.0`. Ці значення — реліквія impedance-based bio_status моделі до Lorenz cutover'а. Природний Lorenz Z сидить ~9..50 (≈ ρ−1 при ρ_eff ∈ [10, 50]), тож після `db:seed`:
  - `Tree#effective_lorenz_thresholds` повертав [-2.5, 2.5];
  - `SilkenNet::Attractor.homeostatic?` повертав `false` для **усіх** Lorenz Z;
  - `TelemetryUnpackerService#check_z_divergence!` flag'ив fraud на КОЖНОМУ пакеті (device-claim homeostasis vs server-classified anomaly);
  - `OtaPackagerService` відправляв `CMD_SET_THRESHOLDS [-2.5, 2.5]` → firmware класифікував всі живі дерева як anomaly → growth_points=0 → ніякого мінтингу.
- **Виправлено (2026-05-16):**
  - `db/seeds.rb` тепер сіє Pine `5.0 .. 45.0` (`optimal_z_target: 29.0`) і Oak `8.0 .. 40.0` (`optimal_z_target: 24.0`) — узгоджено з `Tree::GLOBAL_LORENZ_Z_MIN/MAX/OPTIMAL` і `spec/factories/tree_families.rb`.
  - Regression spec `spec/integration/seeded_tree_families_lorenz_alignment_spec.rb` (14 examples) фіксує SSOT: optimal_z_target homeostatic, off-band non-homeostatic, band всередині глобального Lorenz envelope, raw seed source match. Якщо seed колись відкотять — спек впаде голосно.
  - Production rebaseline rake task НЕ потрібен — підтверджено що seed ніколи не запускався проти живої БД.
- [x] 🤖 Виправити seeds.rb (Pine + Oak + optimal_z_target)
- [x] 🤖 Regression spec для catch майбутніх регресій seed
- [x] 🤖 Перевірити що `spec/models/tree_family_spec.rb`, `spec/integration/cluster_tree_family_spec.rb`, `spec/integration/fw8_threshold_governance_spec.rb` все ще зелені (177/177 ✅)
- **Cross-ref:** `03_04 §4.1` (Lorenz Decision Table), `04_01 §TreeFamily`, `firmware/bio_contracts/bio_contract.rb:97-99` (firmware-side CRITICAL_Z_*).

#### OPS.7 — Sync labels.yml + Projects V2 fields with 00_07 §4
- **Джерело:** `00_07` §4 audit (2026-05-16) | **Пріоритет: P2** | **Складність: XS** | **🤖 Код**
- **Опис:** SSOT audit виявив 3 невідповідності між `00_07 §4`/§1.1 і `.github/labels.yml`: (1) `cluster:cross-cluster` був у Projects V2 R&D Cluster field option, але не у `labels.yml`; (2) `shape:building` та `shape:done` були у Shape Up Stage field options, але не у `labels.yml`; (3) `agent:*` labels у `00_07 §4.4` показувалися з emoji prefix у назві (`agent:🤖 ai`), але `labels.yml` має `agent:ai` без emoji. **Що зроблено (2026-05-16):** додано 3 нові labels (`cluster:cross-cluster`, `shape:building`, `shape:done`) у `labels.yml`; виправлено `00_07 §4.4` emoji rationale (emoji — лише візуальні маркери у 00_08, не у label names); додано mapping table label ↔ Projects V2 field option у §4.3.
- **Статус:** ✅ Done.
- [x] 🤖 Додати `cluster:cross-cluster` label у `labels.yml` (color `#F1E05A`)
- [x] 🤖 Додати `shape:building` (color `#0E8A16`) + `shape:done` (color `#1D76DB`)
- [x] 🤖 Виправити `00_07 §4.4` emoji rationale
- [x] 🤖 Додати mapping table label ↔ Projects V2 field у `00_07 §4.3`

#### OPS.5 — EU DMLS quotes від 2-3 backup підрядників
- **Джерело:** `07_02` §8.1.1 | **Складність: S** | **🔧 Операційна**
- **Опис:** BIZ.6 ✅ ідентифікував 4 EU кандидати (3D Lab PL, Materialise BE, Sauber CH/Lithoz AT, TRUMPF DE). Наступний крок — отримати quotes на пробну партію 10 шт. для benchmarking + frame agreement letter
- [ ] 👤 Запит quotes у 3D Lab PL (priority 1) + Materialise BE (priority 2)
- [ ] 👤 Заповнити порівняльну таблицю у `07_02` §8.1.1
- [ ] 👤 Letter of Intent / Frame Agreement з top vendor

---

## 📋 Юридичні / Бізнес

#### BIZ.1 — 1 SCC = ? kg CO₂ ✅
- **Джерело:** `07_01`
- **Опис:** CO₂ еквівалент для 1 SCC — визначено: **2000 SCC = 1 tCO₂ (1 SCC = 0.5 кг CO₂)**
- **Статус:** ✅ Реалізовано (2026-04-23)
- [x] Визначити методологію розрахунку — **2000 SCC = 1 tonne CO₂** (закрито в `07_01` BLOCKER-4)
- [x] Додати в код — `ProtocolParameters.sol#KEY_SCC_PER_TONNE_CO2 + sccPerTonneCo2()`, `SystemParameter(:scc_per_tonne_co2, value: 2000)`, `db/seeds.rb`
- [x] Задокументувати — `07_01` §3 + BLOCKER-4, `07_02` §7.1
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
- [ ] 👤 Engagement з патентним адвокатом
- [ ] 👤 Патентна заявка на дизайн анкера

#### BIZ.6 — Supply chain war-zone risk mitigation
- **Джерело:** `07_02` | **Пріоритет: P1**
- **Опис:** DMLS manufacturing залежить від українських підрядників (Київ 3D Metal Tech, Дніпро ALT Ukraine, Черкаси SVS-ARTA) — зона активних бойових дій. Логістичні ризики, енергетичні перебої, мобілізація персоналу. Відсутній contingency plan з EU/US альтернативами
- **Статус (🤖):** ✅ Розділ §8.1.1 "Contingency Plan: EU Backup DMLS Hubs" доданий у `07_02` — 4 кваліфіковані EU кандидати (3D Lab PL, Materialise BE, Sauber CH/Lithoz AT, TRUMPF DE), activation triggers, очікуваний price impact (+~20% Payback)
- [x] 🤖 Ідентифікувати 2-3 backup DMLS заводи в ЄС (Польща, Чехія, Німеччина)
- [ ] 👤 Отримати quotes для порівняння вартості
- [x] 🤖 Задокументувати contingency план у `07_02`

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

---

## 🎓 Академічні блокери (5 установ)

> **Поточний стан:** Партнерство з 5+ академічними установами — ChNU (фізико-хімія + ФОТІУС), ChDTU (Data Science + RF + акустика), ChIPB-NUTSU (пожежна безпека), ChMA (біохімія + токсикологія), СЄУ (правова + економічна архітектура). UNI.1-3, UNI.8 — раніше ідентифіковані; нижче — розширення на всі 5 установ.

#### UNI.1 — Перший контакт з деканом Онищенком (ChNU FOTIUS)
- **Джерело:** `08_01`
- **Блокує:** Всю лабораторну роботу, 10 публікацій, 11 магістерських
- [ ] 👤 Призначити зустріч
- [x] 🤖 Підготувати презентацію проєкту — ✅ 7-слайдова 15-хвилинна презентація додана в `08_01` §4. Структура: проблема → рішення → техстек → що потрібно від ЧНУ → що отримає ЧНУ → наступні кроки
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
- **Опис:** Черкаська медична академія (ChMA). Потрібно: (1) валідація FAD-GDH + Laccase інгібіції при pH ксилеми (4.5-5.5), (2) токсикологічні тести іонів Ti/Al/V (поглинання деревом, безпека для ecosystem). **⚠️ Посади науковців у docs не верифіковані** через офіційний сайт ChMA — критичний блокер
- [ ] 👤 **СПОЧАТКУ:** Верифікувати посади всіх науковців ChMA через офіційний сайт
- [ ] 👤 Cold contact з ректором ChMA
- [ ] 👤 Joint biochemistry protocol для EBFC Gen 2.0 (cross-ref HW.5)

#### UNI.14 — СЄУ: токеноміка RWA + правова архітектура
- **Джерело:** `08_07` | **Пріоритет: P1**
- **Опис:** Розширення UNI.8. СЄУ — національний університет; потрібно: (1) MSA/Term Sheet для B2B контрактів (Аблязов Д. — право, к.ю.н.), (2) KYC/AML процес для юридичних осіб (Hadron flow), (3) структура DAO як юридичної особи (cooperative? Swiss Verein?), (4) ESG Accounting Framework (Ус Г.О. — облік). **⚠️ Посади 7 науковців СЄУ потребують верифікації** через офіційний сайт
- [x] 🤖 Підготувати pitch для ректора (Чудаєва І.Б.) — ✅ 10-хвилинний pitch-документ додано в `08_07` §6
- [ ] 👤 Перша зустріч з Чудаєвою (ректор) або Аблязовою Н. (президент) — UNI.8
- [ ] 👤 Верифікувати посади та наукові профілі всіх 7 науковців СЄУ
- [ ] 👤 Меморандум про співпрацю СЄУ ↔ Silken Net
- [ ] 👤 Joint workshop: Аблязов Д. (право) + Silken Net legal → MSA шаблони
- [ ] 👤 Joint workshop: Ус Г.О. (облік) → ESG Accounting Framework

#### UNI.8 — Перший контакт з ректоратом СЄУ (legacy ID — see UNI.14)
- **Джерело:** `08_07`
- **Блокує:** Economic Whitepaper, Legal Framework, NaaS юридичні шаблони (07_01 BLOCKER-1, BLOCKER-3)
- [x] 🤖 Підготувати pitch для ректора (Чудаєва І.Б.) — ✅ 10-хвилинний pitch-документ додано в `08_07` §6. 4 блоки: проблема/ринок → що побудовано → 5 напрямів для СЄУ → що отримає СЄУ. Матеріали для зустрічі специфіковані
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
| E.8 | ✅ SNR parameter wired into Queen CIFO eviction (tiebreaker) | `03_02`, `04_06` | Реалізовано (2026-05-03): `LoRaRxSlot.snr` + `EdgeCache.snr` + `OnRxDone` plumbing + tiebreaker logic у `Process_And_Cache_Data` (нижчий SNR при рівному RSSI = preferred to evict). 7 нових host-тестів: persisted, dedup updates SNR, tiebreaker triggers on equal RSSI, doesn't override worse RSSI, respects critical priority, fallback path tiebreaker, ring carries SNR ISR→consumer. 128 → 135 queen tests; всі test_soldier/test_bio_contract/test_tinyml/test_encryption/test_seed_derivation залишилися зеленими. RAM budget (.bss + .data) у межах 50 KB gate. |
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
| ✅ E.28 | **Kamal deploy hooks idempotency audit** — всі `.kamal/hooks/` є `.sample`-only (не активні). Аудит (2026-05-17): усі sample-хуки ідемпотентні (read-only git/DNS операції). Активовано `pre-build` (без зовнішніх залежностей): чистота git-checkout + наявність remote + гілка pushed + `KAMAL_VERSION` збігається з remote HEAD → fail-fast перед docker build. `pre-deploy.sample` (GitHub CI status check) потребує `GITHUB_TOKEN` — залишається sample до налаштування secret. Решта sample'ів — прості echo, активація не потрібна. | `06_01` | ✅ Done (2026-05-17): `.kamal/hooks/pre-build` активовано |
| E.29 | Альтернативні EBFC медіатори (ferrocene, methylene blue) | `01_03` | R&D alternatives |
| E.30 | InsightGenerator: кліматичні базлайни per region | `04_02` | Post-TRL 7 |
| E.31 | TinyML OTA: `.tflite` формат (INT8 quantization) + Python ML microservice | `03_03` | Post-TRL 8 |
| E.32 | ✅ (Slither + Foundry) Smart Contract Audit: Slither в CI (`.github/workflows/solidity_audit.yml`). Foundry toolchain (`contracts/foundry.toml`): solc 0.8.28, EVM cancun, optimizer 200 runs, CI/production profiles. 178 тестів у 6 test suites. Coverage via `forge coverage --ir-minimum`. Mythril + Hacken — окремі етапи pre-mainnet | `05_03` | Slither CI ✅ (Сесія 19-20), Foundry tests ✅ (Сесія 22-23), Mythril + Hacken TODO |
| E.33 | AlertNotification rate limits: FCM multicast (500 tokens/req), Twilio Notify | `04_02` | Post-TRL 8 |
| E.34 | dClimate fallback → ForestBountyService (drone/ranger PoPhW) | `04_02` | Post-TRL 6 |
| E.35 | ✅ Flash Loan defense реалізовано в `SilkenGovernor.sol`: GovernorVotes (`getPastVotes`), GovernorSettings (votingDelay=43200 блоків ~1 day, votingPeriod=302400 ~7 days), GovernorVotesQuorumFraction (4%), GovernorTimelockControl (48h через `SilkenTimelock.sol`) | `05_03` | ✅ Реалізовано |
| E.36 | PostGIS Generated Column (geo_boundary) замість тригера | `04_01` | Post-TRL 8 |
| E.37 | TimescaleDB для telemetry_logs: hypertables + continuous aggregates | `04_01` | >100M рядків/місяць |
| E.38 | Press-Fit фаски: R ≥ 0.2 мм для зняття напружень у PEEK + **annular barbs (h=0.3mm)** на Zone 1 та Zone 3 контактних поверхнях для PEEK creep mechanical lock (`01_01 §4.3`, HW.26) | `01_01` | Включити у nTop (HW.1, HW.26) |
| E.39 | **EBFC Gen 2.0:** FAD-GDH + Laccase/nanozymes + ZIF (20-25 років) | `01_03` §3 | ЧНУ lab testing |
| E.40 | **Ignion Virtual Antenna™:** NN02-310 як альтернатива Yageo/Taoglas 868 МГц | `02_01` §5 | Evaluation kit + VSWR тест |
| DIFF.1 | `Wallet#lock_and_mint!` threshold = runtime param (не hardcoded) | `04_02` | Informational, no action |
| DIFF.7 | ✅ SNR parameter wired into Queen CIFO eviction as tiebreaker — див. E.8 | `03_02`, `04_06` | Реалізовано (2026-05-03) |
| E.41 | **Fire events delayed 48h** via dClimate satellite obscuration — **⚠️ life-safety risk**. Mitigation: Forester Guild as Fallback Oracle (E.20) + immediate local broadcast via panic TX (не чекати satellite clearance при chainsaw detection). **Пріоритет: P1** (не відкладати на Post-TRL 6) | `04_02`, `05_01` | P1: interim emergency fallback |
| ✅ E.42 | **TelemetryLog cleanup safety**: guard `where.not(oracle_status: "dispatched")` наявний у `InsightGeneratorService.cleanup_old_logs!` (рядок 125) з 2026-05-03. Spec `"preserves dispatched logs when called as class method"` у `spec/services/insight_generator_service_spec.rb:645` регресійно фіксує поведінку. | `04_02` | ✅ Done — guard + spec вже в коді |
| ✅ E.45 | **SCC/SFC contract addresses** = `0x0000...0` в subgraph.yaml — блокує deploy subgraph на testnet/mainnet. **Статус (2026-05-17):** додано `subgraph/validate_addresses.sh` — fail-fast скрипт, який перевіряє відсутність нульових адрес перед `graph deploy`. Запускати: `./subgraph/validate_addresses.sh && graph deploy`. Адреси залишаються `0x0000...0` до деплою контрактів через Foundry (instructed в subgraph.yaml comments). | `05_03` | ✅ Guard-скрипт додано; адреси = placeholder до контрактного деплою (S3.5) |
| ✅ E.47 | **Solana RPC defaults to Devnet** — **Статус (2026-05-17):** `Solana::MintingService#send_transfer_request` тепер raise'ить `"SOLANA_RPC_URL is required in production"` якщо ENV пустий у `Rails.env.production?`. `Treasury::MonitorService#fetch_solana_balance` логує warn і повертає 0 (non-critical monitoring path). `SOLANA_RPC_URL` вже в `config/deploy.yml` secrets — Kamal crash-at-boot якщо не в `.kamal/secrets`. 2 нові specs: `minting_service_spec.rb` (raise in production) + `monitor_service_spec.rb` (warn + return 0). | `05_01` | ✅ Done (2026-05-17) |
| E.48 | **The Graph subgraph на testnet `polygon-amoy`** — потребує mainnet deploy перед production | `05_01` | Post mainnet deploy |
| ✅ E.49 | **Celo RPC fallback mechanism** не вказаний — при збої primary RPC немає автоматичного переключення. **Статус (🤖, 2026-05-12):** ✅ Реалізовано. `Celo::CommunityRewardService::RPC_FALLBACK_ENV_KEYS = %w[CELO_RPC_URL_FALLBACK_1 CELO_RPC_URL_FALLBACK_2]` через `Web3::RpcConnectionPool.client_for(..., fallback_env_keys:)` → `Web3::ResilientClient` (3 fail / 60s cooldown). `MintingRollbackService` Celo гілка тепер використовує той самий cascade (виправлено баг: раніше Celo TX rollback вживав polygon-rpc.com fallback). `.env.example` оновлений. Спеки: 3 нові expectations у `community_reward_service_spec.rb`, 16/16 pass. Док: `04_02` §10 (Celo service row + External API row) + §13b Drift Register | `05_01`, `04_02` | ✅ Done (E.49) |
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
| OPS.5 | **Projects V2 TRL field schema 1-9 → 1-12 (REVISED 2026-05-16)** — `00_07 §1.1` Custom Fields `Current TRL` / `Target TRL` розширено до 1-12, щоб відповідати `00_04 §1` (Beyond TRL 9) і `00_06 §7` (Planetary Intelligence Gaps TRL 10-12). Якщо `bin/setup_github_project.sh` створював лише 1-9 — оновити TRL_OPTIONS=(TRL:1..TRL:12) перед першим API-write. TRL labels у `.github/labels.yml` наразі не використовуються — Projects V2 SingleSelect є SSOT. | `00_07 §1.1` + `00_04 §1` + `00_06 §7` | P1, bootstrap blocker для R&D-эпіків TRL 10-12 |

---

## 🏛️ Архітектурні пропозиції (довгострокові)

| ID | Пропозиція | Джерело | Milestone |
|----|-----------|---------|-----------|
| ARCH.1 | Fractal topology: L2 Sergeant nodes (H-LDSE hierarchical routing, geohashing) | `00_01` | Post-TRL 7 |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka для >1M packets/hour | `00_01`, `06_01` | Series D |
| ARCH.5 | Cross-Registry Export (Verra, Gold Standard, UNFCCC) | `04_02` | Post-TRL 7 |
| ARCH.6 | Federated Learning auto-retraining (monthly cycle, A/B testing) — **обмежено L2 Sergeants / L3 Queens; ніколи на L1 Soldier** (compute budget paradox, `00_06 §7.2` revised 2026-05-16: 0.47F supercap + STOP2 300 nA не витримує жодного gradient epoch'у) | `04_02`, `00_06 §7.1-7.2` | Post-TRL 7 |
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
| ARCH.21 | Brownout detection + graceful shutdown: PVD IRQ при vcap < 1.8V → збереження Lorenz стану у RTC DR0-DR10 → STOP2. При відновленні живлення — продовжити з того самого стану. Захищає від корупції стану при раптовому знеструмленні. **✅ Реалізовано (2026-05-03):** Існуючий `HAL_PWR_PVDCallback` (поріг `PWR_PVDLEVEL_7` ≈ 2.2V) розширено симетрично до Phase 5 — рятує DR0 (packed `[panic_counter:16 \| reserved:8 \| acoustic:8]`), DR1 (`last_wakeup_timestamp` для delta_t continuity), DR16-DR19 (Lorenz state з magic `LORENZ_STATE_MAGIC = 0x4C5A5354 "LZST"`) перед `HAL_PWREx_EnterSTOP2Mode`. Без цього rescue брауноут = втрата траєкторії = cold-start через HKDF на наступному boot'і = розрив growth_points streak = false slashing проти живого здорового дерева. 5 host-тестів (`test_arch21_*` у `test_soldier_logic.c`): PVD saves Lorenz / preserves packed DR0 / preserves last_wakeup / skips Lorenz when invalid / save+restore roundtrip. Поріг лишається 2.2V — близько до плану (1.8V), але STM32WLE5JC PVD рівні дискретні (PWR_PVDLEVEL_0..7), 2.2V є найближчим до 1.8V у безпечну сторону (раніше срабатує = більший margin перед SRAM corruption). | `08_02` | ✅ Post-TRL 6 (Firmware) — done |
| ARCH.22 | Arithmetic compression для LoRa payload: lambda-exponent (2 байти) замість повного Z (16 байт). Потенційна економія ~34% TX часу (21→~14 bytes). Event-Triggered Reporting: "мовчання = здоров'я" — 24× зниження трафіку | `08_02`, `00_01` | Post-TRL 7 |
| ARCH.23 | Multi-Attribute Utility Function для автономного рішення TX на MCU: оцінка важливості поточного пакету (Vcap, delta_t, acoustic, bio_status) — відправляти лише якщо utility > threshold. Оцінка: 30-40% зниження TX | `08_02` | Post-TRL 7 (Ярмілко, ЧНУ) |
| ARCH.24 | CE/FCC/RoHS/EMC/IP68 compliance roadmap для EU/NA ринків: CE-RED (868 МГц LoRa), FCC Part 15/90, RoHS-2, IP68 (IEC 60529), REACH. Кожна сертифікація потребує 3-6 місяців та спеціалізованої лабораторії | `08_02` | Pre-mass production (Косенюк, ЧНУ) |
| ARCH.25 | Gyroid geometric validation scripts: Python/C++ верифікація 65% пористості per-slice, topological integrity mesh, capillary channel connectivity via BFS (breadth-first search). Запускається після кожного nTop build для запобігання помилкам DMLS | `08_02` | Before DMLS factory order |
| ARCH.26 | **Синхронні Вікна (TDMA) та CAD Preamble Detection — вирішення Проблеми Рандеву для mesh relay.** Поточна архітектура: Queen always-on (`Radio.Rx(LORA_RX_INFINITE)`), Soldier має лише 600 мс post-TX RX window — mesh relay між Солдатами стохастичний і ненадійний за межами прямої видимості Queen. **Три рівні рішення:** (L1) Queen always-on ✅ реалізовано; (L2) TDMA Sync Windows — Queen транслює beacon з точним часом (NTP через LTE), Солдати синхронізують RTC, кожні 15 хвилин координоване 2-секундне RX-вікно для mesh relay. Залежить від FW.20 (LoRa Time Sync); (L3) CAD — SX1262 `Radio.StartCad()` дозволяє wake на ~2 мс/секунду для детекції LoRa-преамбули без повного RX. Критично для PANIC mode: Солдат при chainsaw detection посилає довгу преамбулу (~1 сек), сусідні Провідники ловлять через CAD навіть між TDMA-вікнами. **Firmware зміни:** Soldier: CAD periodic wakeup (LPTIM або RTC sub-second alarm), beacon RX handler, RTC sync logic. Queen: beacon TX (periodic broadcast з UTC timestamp + network schedule). **Енергобюджет:** CAD wake 1/сек × 2 мс × 4.5 мА = ~9 µA середнє — допустимо для Провідників (дерева з високим vcap), неприйнятно для слабких Солдатів. Рольова диференціація: Солдат (TX-only, глухий) vs Провідник (TX+CAD, еліта з надлишком енергії). | `00_01`, `03_01`, `03_02` | Post-TRL 6 (Firmware + Queen beacon) |
| ARCH.27 | **Node Role Differentiation (Soldier vs Provisioner) у firmware** — ARCH.26 передбачає рольову диференціацію (Soldier=TX-only, Provisioner=TX+CAD), але **firmware компілюється ідентично для обох ролей**. Runtime role не персистована у Flash/RTC. Без role-aware logic — неможливо реалізувати енерго-диференційовану mesh relay. **✅ Реалізовано як інфраструктурна передумова (2026-05-03):** `FLASH_ROLE_ADDR = FLASH_KEY_ADDR + 72` (одразу після K_seed, у тому ж WRPROT-захищеному 4 KB Protected Flash Sector — `0x0803E000 + 72 = 0x0803E048`, **без створення нового сектора**). Один uint32 magic-word: `0x534F4C44 "SOLD"` → `ROLE_SOLDIER`, `0x50524F56 "PROV"` → `ROLE_PROVISIONER`. Будь-яке інше значення (0xFFFFFFFF unprovisioned, 0x00000000 erased, корупція) → fallback на `ROLE_SOLDIER` (безпечний дефолт, бо більшість вузлів — звичайні датчики). Глобальний `volatile uint8_t g_node_role` встановлюється `Load_Node_Role()` у `main()` одразу після `Load_Lorenz_Seed()`. ARCH.26 (CAD relay) і повний FW.20-S2 будуть споживати цей прапорець без додаткової логіки. 5 host-тестів (`test_arch27_*`): SOLD / PROV / unprovisioned 0xFFFFFFFF / zero / corrupted magic. Жодних змін у backend `HardwareKeyService` для цього інкрементального патчу — це чистий firmware-flag. | `00_01`, `03_01` | ✅ Post-TRL 6 — done (передумова для ARCH.26 L3) |
| ARCH.28 | **RTC Backup Domain allocation policy** — DR0..DR23 регістри активно використовуються (Lorenz state, mesh cache, EMA, FW.18 thresholds). Резерв вичерпується. Потрібна формальна політика: (a) канонічна таблиця у `03_01`, (b) procedure для додавання нової фічі (review impact на existing fields), (c) consideration для Flash-based key-value store як overflow. **✅ Виконано (2026-05-03):** Документація доточена у `03_01` §2.1-2.4: §2.2 — 7-крокова процедура додавання нової RTC-фічі (SSOT-рев'ю → packing-аудит → ASCII bit-field діаграма → magic policy → restore guard → host-test bank → doc update) з реальними прикладами кенозису з SEC.10/FW.21/ARCH.27; §2.3 — overflow strategy 3 шляхами (A: Flash sector emulated EEPROM, B: ATECC608B slots, C: bit-перепакування) з порівняльною таблицею плюсів/мінусів і критеріями вибору; §2.4 — sketch helper-макросів `RTC_BKUP_READ32`/`WRITE32` як freeze-контракт SSOT (ще НЕ застосовані до hot path: ROI на TRL-6 негативний, повернутися при RTOS-рефакторингу або реальному debug-сесії). | `03_01` §2 | ✅ Post-TRL 6 (документація) — done |
| ARCH.29 | **RTOS Deadlock-Free верифікація через Petri Nets** — формальна PN-модель firmware tasks (Sensing/Compute/TX/OTA/WDT) на Soldier + reachability graph аналіз для доведення відсутності circular wait. Відрізняється від ARCH.20 (Petri Net Rails моноліт) тим що моделює embedded RTOS scheduling | `08_02` §1.2 (Ярмілко) | Post-TRL 6 (R&D — Ярмілко, ЧНУ) |
| ARCH.30 | **Parallel CFD gyroid simulation на Akash GPU** — domain decomposition алгоритм для 3D TPMS-симуляцій на heterogeneous GPU вузлах Akash. Скорочує CFD lead-time з ~2 годин до real-time валідації геометрії перед DMLS order. Cross-ref ARCH.25 (gyroid validation scripts) | `08_02` §1.4 (Онищенко) | Post-TRL 7 (методологія + Akash GPU integration) |
| ARCH.31 | **SOP-в-Phlex inline UI для EwsAlert** — інтеграція 7 SOP документів (drought/epidemic/vandalism/fire/seismic/fault/entropy) як inline-інструкцій, що показуються при кліку на EwsAlert у дашборді. UX: forester отримує немедіане runbook замість пошуку у документах | `08_05` + `04_02` | Post-TRL 6, cross-ref E.54 + UNI.12 |
| ARCH.32 | **Shape Up 6-week cycle Petri Net formalization** — формальна верифікація фази Shape Up (betting table → build → cool-down) щоб довести: будь-яка фіча може бути завершена у межах cycle constraints. Цільова стаття Q1 *IEEE Transactions on Software Engineering* | `08_02`, `00_05` | Post-TRL 7 (методологія + R&D, Супруненко ЧНУ) |
| ARCH.33 | **ECDH P-256 key exchange як альтернатива HKDF-only provisioning** — мерехтливий розгляд: замість per-device HKDF (FW.1) використати ECDH у factory або field provisioning. Plus: Perfect Forward Secrecy без shared master key. Minus: Curve25519/P-256 потребує ~512 байт SRAM + 50 мс CPU на handshake | `08_02` §1.1 (Vector 2, Ярмілко), `03_05` | Research alternative (узгодити з FW.17 Hash Ratchet) |

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
| 08 University R&D | 2 | 6 | 5-сторонній партнерський фреймворк (ChNU + ChDTU + ChIPB + ChMA + СЄУ) — UNI.4-14 |
| 09 Project Management | 7 | 9 | OPS.3 R&D portfolio, OPS.4 semester sync |
| 10 Security | 7 | 9 | SEC.9 master key, ✅ SEC.11 Lorenz seed provenance, Multisig, RDP, Factory (Rails web layer ✅ S6.18) |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
> 3. Для нових знахідок — додавати у відповідну секцію + посилання на джерело docs
> 4. Раз на квартал — повний docs audit з оновленням «Top-Critical Path» секції зверху
