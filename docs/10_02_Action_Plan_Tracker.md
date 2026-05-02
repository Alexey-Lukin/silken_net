# 10_02 — Action Plan Tracker (Залишок робіт)

> **Принцип:** Цей документ містить ТІЛЬКИ незавершені задачі. Виконана робота задокументована у відповідних docs (`00_00` → `10_01`).

> **Розмітка виконавців:**
> - 🤖 **Код/аналіз** — Copilot може виконати самостійно (код, firmware, розрахунок, документ, тест)
> - 👤 **Операційна** — потрібен власник (hardware, зовнішні UI/дашборди, секрети, зустрічі, юрист, фізична лабораторія)
> - 🔗 **Заблоковано** — чекає іншої задачі або рішення

---

## 🚨 Top-Critical Path (рекомендований порядок виконання)

> Виведено окремо, щоб видно «що варто робити прямо зараз». Це **не нові задачі**, а індекс уже існуючих пунктів, які блокують найбільше іншого.

### Перед будь-яким польовим деплоєм (life-safety + security)
1. **SEC.9** — замінити master AES key (FIPS-197 test vector) на криптостійкий random — **P0**
2. **SEC.11** — Provisioning master key production guard (raise при відсутності ENV) — **P0**
3. **FW.1 + SEC.3** — Per-device HKDF provisioning + Factory Flashing pipeline — **P0**
4. **FW.2** — AES-256-CCM (вирішує одразу: ECB→CCM, MIC, FW.23 OTA auth, SEC.10 panic auth, FW.29 disambiguation) — **P0**
5. **SEC.1** — Gnosis Safe multisig для `DEFAULT_ADMIN_ROLE` SCC/SFC до mainnet — **P0**

### Перед production-запуском Web3 mintingу
6. **S1.1** — заповнити GitHub Secrets (`DATABASE_PASSWORD`, `GCP_SA_KEY`, `SSH_PRIVATE_KEY`, ...) — **P0**
7. **E.45 / S3.5** — підставити реальну адресу SCC/SFC у `subgraph.yaml` — **P0**
8. **E.47** — встановити `SOLANA_RPC_URL` mainnet (інакше Devnet за замовчуванням) — **P0**
9. **S6.12** — аудит `TokenomicsEvaluatorWorker` оракул-guards bypass для не-oracle flow — **P1**
10. **INF.4 + INF.6** — TLS termination + CoAP Proxy verification на Akash ingress — **P1**

### Парк аналітики/спостережуваності перед першим Akash deploy
11. **S2.1 + S2.2 + S2.3** — Grafana Cloud dashboards & alerts після першого `/metrics` пуш — **P0** (ops)
12. **S5.2** — `RELEASE_VERSION` ENV для Sentry release tracking (вже інстальовано — потрібна верифікація) — **P2**

### Лабораторно-критичний шлях (TRL 4→6 hardware)
13. **HW.7** — BQ25570 VBAT_OV резистори: виміряти і замінити SMD якщо мисматч — **P1** (блокує PCBA freeze)
14. **HW.13 / ARCH.29-MPPT** — P-V крива EBFC + перейти з 50% VOC на 65% — **P1**
15. **HW.3** — 12-тижневий Arrhenius accelerated aging тест (синтетичний ксилемний сік) — **P1** (блокує seed)

### Академічний critical path
16. **UNI.1** — Перша зустріч з деканом Онищенком (ChNU FOTIUS) — **P0** (блокує всі публікації Q1)
17. **UNI.8** — Перший контакт з ректоратом СЄУ — **P0** (блокує MSA / B2B legal)
18. **UNI.13 / UNI.14** — Верифікувати посади науковців ЧМА і СЄУ через офіційні сайти — **P0**

---

## 🛣️ Software / Backend / DevOps

> **Складність:** XS < 1 год · S = 1–4 год · M = 4–8 год · L = 1–3 дні

#### S1.1 — GitHub Secrets заповнення
- **P0** | `06_01` | **Складність: XS** | **🔧 Операційна** — ручне заповнення в GitHub UI, без коду
- **Опис:** 12 критичних секретів не встановлені: `GCP_SA_KEY`, `DATABASE_PASSWORD`, `DATABASE_URL`, `SSH_PRIVATE_KEY`, тощо. Блокує весь CI/CD pipeline.
- **Статус:** ✅ Checklist створено у `docs/06_04_Secrets_Checklist.md` — повна інвентаризація 4 місць зберігання (GitHub Secrets, `.kamal/secrets`, Akash SDL, `terraform.tfvars`)
- [x] 🤖 Створити список необхідних секретів (checklist)
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
- [x] Backend: `silkennet_rpc_circuit_breaker_open` gauge (labeled `provider`) та `silkennet_rpc_errors_total` (labeled `network`, `error_type`) інструментовані в `Web3::ResilientClient` — відкриття/закриття circuit breaker та класифікація помилок (timeout/connection_refused/rate_limited тощо)
- [ ] 👤 Dashboard: Sidekiq queues (9 черг, size + latency)
- [ ] 👤 Dashboard: Web3 RPC errors by network
- [ ] 👤 Dashboard: Telemetry ingest rate + fraud detection
- [ ] 👤 Dashboard: Treasury / Oracle balance monitoring
- [ ] 👤 Dashboard: Database connection pool stats

#### S2.3 — Grafana Cloud alerting rules
- **P0** | `06_03` | **Складність: S** | **🔧 Операційна** — налаштування в Grafana Cloud UI, без коду
- **Опис:** Grafana Cloud Alerting замінює потребу в self-hosted Alertmanager
- [x] Backend: `silkennet_telemetry_acoustic_overflow_total` counter реалізований в `TelemetryUnpackerService` (інкрементується при `acoustic_events == 255`) — готовий для alert rule `rate() > 0`
- [ ] 👤 Alert: `web3_critical` queue depth > 100
- [ ] 👤 Alert: `silkennet_telemetry_fraud_detected_total` rate > 0
- [ ] 👤 Alert: `silkennet_rpc_errors_total` rate > 10/min
- [ ] 👤 Alert: Oracle balance < threshold
- [ ] 👤 Alert: Sidekiq queue latency > 5 min
- [ ] 👤 Налаштувати notification channel (Slack / Email / PagerDuty)

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

#### INF.4 — Akash TLS strategy decision: hostname operator vs Cloudflare
- **P1** | `06_02` BLOCKER-5, `06_01` | **Складність: S** | **🔧 Операційна + Док**
- **Опис:** Розширення INF.3. Не прийнято архітектурне рішення: (a) Akash hostname operator + Let's Encrypt автоматизація, (b) Cloudflare Proxy перед Akash (DDoS + WAF, але ще одна mw залежність), (c) Traefik у Kamal (тільки GCP path). Вибір впливає на CoAP UDP (Cloudflare НЕ proxies UDP — потребує separate Spectrum або direct ingress)
- [ ] 👤 Прийняти архітектурне рішення (Cloudflare Proxy для HTTPS + direct UDP для CoAP — рекомендовано)
- [ ] 🤖 Документувати у `06_02` runbook: pre-flight checklist + verification commands
- [ ] 🤖 Якщо Akash hostname — додати automation у `terraform/`

#### INF.6 — CoAP Proxy на Ingress Anchor: відсутня verification
- **P1** | `06_01` Pre-Flight Checklist | **Складність: S** | **🤖 Код + Док**
- **Опис:** Ingress Anchor (Kamal Traefik або Akash ingress) повинен проксіювати CoAP UDP port 5683. Документація рекомендує перевірити, але **точна команда verification відсутня**. Без перевірки можлива ситуація: HTTP ingress активний, але UDP заблокований → шлюзи не можуть пушити телеметрію (silent failure)
- **Статус (✅ виконано):** Додано рядок **#6** у Pre-Flight Checklist `06_01` з повними командами: `coap-client -m post` для CoAP smoke test + альтернатива через `nc`, troubleshooting checklist (GCP firewall, Ingress Anchor socat, Akash SDL UDP expose, Sidekiq daemon).
- [x] 🤖 Додати у `06_01` команду: `coap-client -m post -e "test" coap://<ingress-host>:5683/health` + очікуваний response
- [ ] 🤖 Smoke test workflow у CI: post-deploy CoAP health check (потребує CI workflow — окрема задача)
- [x] 🤖 Документувати точний HAProxy/socat/Traefik UDP config для кожного варіанту deploy (включено у troubleshooting секцію)

#### S4.3 — Akash SDL secrets
- **P3** | `06_02` | **Складність: XS** | **🔧 Операційна** — заповнити 4 змінні у `deploy.yaml`
- **Опис:** `REQUIRED_SECRET_NOT_SET` для 4 критичних змінних
- [ ] 👤 Заповнити в `deploy/akash/deploy.yaml`
- [ ] 👤 Верифікувати startup

#### S5.2 — RELEASE_VERSION ENV для Sentry
- **P2** | `06_03` | **Складність: XS** | **🔧 Операційна**
- **Опис:** `RELEASE_VERSION` ENV не встановлено — Sentry release tracking не працює. Потрібно додати у Kamal/Akash deploy config
- **Статус:** ✅ Виконано. `RELEASE_VERSION` додано у: `deploy.yml` (Canopy, git SHA), `deploy-production.yml` (Production, release tag або git SHA), `config/deploy.yml` (Kamal clear env), `deploy/akash/deploy.yaml` (web + job services)
- [x] Додати `RELEASE_VERSION` у deploy pipeline (git SHA або tag)
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
- [ ] 🤖 Архітектурний дизайн task assignment
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

#### S6.15 — Chainlink Functions Router ABI v1: ризик version drift
- **P2** | `04_02` §4.2.2 (DispatchToChainlinkService, BLOCKER-09) | **Складність: S** | **🤖 Код**
- **Опис:** ABI оновлено на Functions Router v1 (5 параметрів — `CHAINLINK_DATA_VERSION`, `CHAINLINK_CALLBACK_GAS_LIMIT`, `CHAINLINK_DON_ID`, ...). Немає fallback на старіший ABI. При наступному upgrade Chainlink router або зміні DON ID — пайплайн впаде без graceful degradation
- [ ] 🤖 Додати `Web3::ChainlinkRouterVersion` enum + ABI registry для multi-version підтримки
- [ ] 🤖 Health check: розпарсити router contract code → перевірити сигнатуру `sendRequest()` при бутстрапі сервісу
- [ ] 🤖 Документувати в `04_02` процес upgrade ABI

#### S6.17 — Dynamic Tax (2%) hardcoded — потребує on-chain governance
- **P2** | `05_03` (HYBRID PROTOCOL GAIA), `BlockchainMintingService` | **Складність: M** | **🤖 Архітектура**
- **Опис:** `DYNAMIC_TAX_RATE = BigDecimal("0.02")` hardcoded у `BlockchainMintingService`. Для true governance це має бути on-chain параметр через `ProtocolParameters` контракт (як `OPTIMAL_Z_TARGET`, `CRITICAL_Z_MIN/MAX`). Поточно — application-level override без DAO voting
- **Статус:** ✅ Виконано. `BlockchainMintingService` тепер читає `dynamic_tax_rate` та `insurance_pool_threshold` через `SystemParameter.current()` з fallback на defaults. Hardcoded константи перейменовані на `DEFAULT_*`. DB migration seeds обидва параметри. Spec coverage: 6 тестів (governance override + default fallback).
- **Залежність:** BIZ.4 ✅ (ProtocolParameters інфраструктура вже існує) — лише треба додати ключ
- [x] 🤖 Додати `KEY_DYNAMIC_TAX_RATE` у `ProtocolParameters.sol` — ✅ вже існує
- [x] 🤖 `BlockchainMintingService` читає ставку через `Governance::ParameterSyncWorker` → `SystemParameter`
- [x] 🤖 Migration: seed `SystemParameter(:dynamic_tax_rate, value: 0.02)` та `SystemParameter(:insurance_pool_threshold, value: 100000)`

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
- [ ] 👤 Задокументувати результат у `06_05_Puma_Configuration.md` (IPv6 runbook section)

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
- [x] 🤖 Backend: provisioning endpoint (POST `/api/v1/provisioning/register` вже існує) — ✅ Аудит підтвердив відповідність HKDF-дизайну з `03_05` §3.4а. Контроллер `Api::V1::ProvisioningController#register` (179 рядків) виконує: FW.24 magic-UID guard → duplicate check → атомарну транзакцію (Tree/Gateway + HardwareKey + MaintenanceRecord(installation)) → опційну реєстрацію Ed25519 публічного ключа → enqueue `PeaqRegistrationWorker` (тільки для Tree) → JSON-відповідь без `aes_key` у HKDF mode (Zero-Trust) і з `aes_key` + warning у TRL4 lab mode. SEC.11 production guard (`HardwareKeyService.derive_device_key`) raise'ить `SecurityError` при відсутньому `PROVISIONING_MASTER_KEY` у production. RBAC: `authorize_forester!`. Контракт відповідає `04_03 §POST /api/v1/provisioning/register`.
- [x] 🤖 Firmware: змінити key storage з hardcoded → Flash-based (`Load_AES_Key()` в soldier/queen main.c — FLASH_KEY_ADDR 0x0803E000, magic "SKEY")
- [ ] 👤 Firmware: RDP Level 2 activation як final step
- [x] 🤖 End-to-end тест provisioning flow — ✅ Додано `spec/integration/provisioning_e2e_spec.rb` (8 examples, all passing). Покриває без моків `HardwareKeyService`: (1) HKDF determinism — persisted `aes_key_hex` точно збігається з незалежно повторно деривованим ключем (firmware-equivalence assertion); (2) atomic creation Tree+HardwareKey+MaintenanceRecord з DID/UID у notes + enqueue `PeaqRegistrationWorker`; (3) gateway flow з Ed25519 public key persistence та БЕЗ peaq enqueue; (4) `binary_key.bytesize == 32` (firmware-readable AES-256); (5) TRL4 lab mode повертає `aes_key`+warning, HKDF mode НЕ повертає; (6) SEC.11 production guard raise'ить `SecurityError` без DB side effects; (7) FW.24 magic UID rejection без DB side effects; (8) duplicate UID → 409 без DB side effects.

#### FW.2 — AES-256-ECB без MAC/MIC
- `03_05` | `firmware/soldier/main.c:747`, `firmware/queen/main.c:781`
- **Опис:** Детерміністичний шифротекст, replay/bit-flip attacks можливі. Немає автентифікації пакетів
- **Рішення (рекомендоване):** **AES-256-CCM** (апаратно підтримується STM32WLE5JC) з новим 24-байтним пакетом: `[DID:4][SensorData:8][FrameCounter:4][MIC:4][Reserved:4]`. Frame Counter у RTC Backup Domain як Nonce. MIC апаратно генерується CCM. Вирішує BLOCKER-2 та BLOCKER-3 одночасно
- **Альтернативи:** AES-256-GCM, AES-256-CTR + HMAC-SHA256 MIC (4-byte suffix)
- [ ] 🤖 Верифікувати `CRYP_AES_CCM` підтримку на цільовій ревізії STM32WLE5JC
- [ ] 🤖 Дизайн 24-байтного пакету (8 байт sensor data vs поточних 16 — оптимізувати поля)
- [ ] 🤖 Firmware Soldier: CCM encrypt + Frame Counter інкремент + MIC append
- [ ] 🤖 Firmware Queen: CCM decrypt + Frame Counter validation (anti-replay)
- [ ] 🤖 Backend: оновити `TelemetryUnpackerService` для 24-байтного формату
- [x] 🤖 LoRa airtime budget verification (24B vs 16B при SF10/DR2) — ✅ Розрахунок додано в `03_05` BLOCKER-2. Висновок: +10% airtime (+41 мс), duty cycle 0.013% (79× запас), енергоспоживання +12 мДж/TX (1.8% EDLC). **Перехід на CCM 24B схвалений**
- [ ] 🤖 Тести

#### FW.3 — Queen AT Command Blocking (~25 сек)
- `03_01`, `03_02`
- **Опис:** Queen "сліпа" до LoRa пакетів під час CoAP flush. Single-packet buffer — пакети втрачаються
- **Рішення:** UART DMA interrupt-driven + ring buffer
- [ ] 🤖 Переписати `Flush_Cache_To_Rails()` на UART DMA
- [ ] 🤖 Замінити single-packet buffer на ring buffer
- [ ] 🤖 Додати CoAP response parsing (замість blind HAL_Delay)
- [ ] 🤖 Тести

#### FW.4 — TinyML `Run_Inference()` закоментований
- `03_03` | `main.c:355`, `silken_net_audio_model.h` відсутній
- **Опис:** `Run_Inference()` закоментована; model header відсутній
- **Блокує:** Acoustic detection (chainsaw, cavitation, wind)
- [ ] 👤 Тренування моделі (4 класи: silence/wind/cavitation/chainsaw)
- [ ] 👤 Генерація `silken_net_audio_model.h`
- [ ] 🔗 DSP preprocessing (FFT/MFCC або вбудований у модель)
- [ ] 🔗 Verify Tensor Arena size (< 54 KB)
- [ ] 🔗 Розкоментувати `Run_Inference()`
- [ ] 🔗 Host-based тести

### 🟠 P1 — Важливі

#### FW.5 — Lorenz Attractor: delta_t/vcap не передаються
- `03_04`, `05_02`
- **Опис:** Spec: `calculate_state(delta_t, vcap)`, реалізація: `calculate_state(chaos_seed, temp, acoustic)`. Аналіз показав: `chaos_seed` (HRNG) вносить значний випадковий компонент у growth_points — при 250 ітераціях Ейлера Z суттєво залежить від початкових умов. `delta_t` та `vcap` — прямі фізичні індикатори метаболізму дерева, що може бути більш обґрунтованим для "Proof of Growth" токеноміки
- **Статус:** 🟡 Архітектурне рішення прийнято (2026-04-29). Math аналіз variance Z + порівняння варіантів A/B/C задокументовано в `03_04` BLOCKER-1. **Прийнято Варіант B+:** зберегти FW.6 state continuity, chaos_seed тільки для cold-start, додати delta_t/vcap як soft perturbation на β (геометричний параметр конвективної клітини). Імплементація — в наступному циклі (потребує координованого firmware+backend update).
- [x] 🤖 Математичний аналіз: порівняти variance Z від chaos_seed vs delta_t/vcap після 250 ітерацій
- [x] 🤖 Архітектурне рішення: замінити chaos_seed на delta_t (Варіант A), додати delta_t/vcap як додаткові пертурбації (Варіант B), або зберегти + EMA фільтр (Варіант C) — **обрано B+**
- [x] 🤖 Задокументувати рішення в `03_04` з обґрунтуванням впливу на токеноміку
- [ ] 🤖 Реалізувати (firmware + backend mirror update) — наступний цикл

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
- `05_02`
- **Опис:** firmware: global 2.0/45.0 vs backend: per-species через `TreeFamily`
- **Рішення:** OTA sync species-specific thresholds
- **Статус:** 🤖 ✅ Повний дизайн OTA Config Payload для per-species Z thresholds додано в `05_02` §4а. Включає: новий CMD_SET_THRESHOLDS (0x9A) payload format (10 байт з CRC16), firmware RTC Backup DR20-23 storage з fallback на defaults, mruby BioContract dynamic thresholds, Rails `OtaPackagerService#build_threshold_config_block`, per-species default threshold table (Pinus/Quercus/Fagus/Picea/Betula), backend mirror verification
- [x] 🤖 Додати thresholds до OTA config payload
- [x] 🤖 Firmware: зберігати thresholds у Flash/RTC
- [x] 🤖 Backend: включити thresholds у OTA bytecode

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
- **Статус:** 🤖 ✅ Реалізовано (firmware-частина): RTC-storage у `DR13/DR14` + dual-threshold decision logic + Phase 5 writeback + 19 host-tests (44 у TinyML suite, 283 загалом). Hardcoded `0.80` повністю замінено зонами SILENCE/WARNING/CRITICAL з ескалацією. **Уточнення розташування:** оригінальний дизайн вказував `DR6/DR7`, але після FW.21 ці регістри зайняті (`DR6 = mesh_relay_payload[12..15]`, `DR7 = tree_did`); канонічна SSOT-таблиця в `03_01` §2 показує `DR13/DR14` як вільний резерв (єдиний залишок `DR15`). **Залишковий блокер:** OTA CMD dispatcher на Soldier (`CMD_SET_THRESHOLDS` 0x9A) deferred до спільного циклу з FW.8 — обидва завдання потребують єдиного downlink-CMD-фреймворку, який поки існує лише в Queen-firmware.
- [x] 🤖 Зберегти threshold у RTC Backup Register (updateable via OTA) — RTC + decision logic + tests; OTA dispatcher deferred → FW.8
- [x] 🤖 Дизайн dual-threshold: WARNING (0.60) → event counter; CRITICAL (0.85) → Emergency TX
- [x] 🤖 Реалізація dual-threshold zones з warning_counter ескалацією (3× → fallback Emergency для chainsaw)
- [x] 🤖 19 host-тестів: 9 zones + 10 validation/RTC roundtrip
- [x] 🤖 Доку оновлено: `03_03` BLOCKER-6 (DR6/DR7 → DR13/DR14, ✅ partial), `03_01` §2 (RTC map), `10_03` §2.5 (test count 25→44)

#### FW.19 — Float32 vs Float64 mruby compile flags
- `03_04` BLOCKER-4
- **Опис:** mruby без `MRB_USE_FLOAT` використовує double (64-bit), з прапорцем — float (32-bit). Makefile не верифікований. Різниця ±5-10 units на Z-осі після 250 ітерацій може змінити bio_status (false slashing)
- **Статус:** 🟡 Частково вирішено. Tolerance band задокументовано як "by design" через категоричну перевірку в `check_z_divergence!`. Верифікація mruby compile flags — при першому lab-тестуванні
- [x] Задокументувати tolerance підхід (категоричний, не числовий) в `03_04` BLOCKER-4
- [ ] 👤 Верифікувати mruby compile flags (`MRB_USE_FLOAT` у Makefile або mrbconf.h) при lab-тестуванні

#### FW.20 — LoRa Time Sync (clock drift compensation)
- Legacy notes | P2 (не блокує TRL 6, критичний для TRL 7+)
- **Опис:** Дешеві кварцові резонатори / внутрішні осцилятори STM32 мають температурний дрейф. При -20°C та +40°C RTC годинник Soldier йде з різною швидкістю. За кілька місяців "час дерева" розсинхронізується з "часом бекенду" на хвилини або години. Впливає на: (1) `created_at` timestamp → partition pruning errors, (2) HMAC/nonce replay protection windows, (3) cron-like wakeup scheduling, (4) **TDMA Синхронні Вікна** (ARCH.26) — без синхронізації годинників координований mesh relay неможливий
- **Рішення:** Протокол Time Sync через Queen downlink. Queen має точний час через LTE/NTP. Періодично Queen надсилає OTA-корекцію часу. Аналог LoRaWAN MAC command `DeviceTimeReq`
- **Залежності:** Є передумовою для ARCH.26 (TDMA Sync Windows). Без FW.20 синхронні вікна неможливі — годинники дрейфують і вузли "промахуються" повз спільне RX-вікно
- **Статус:** 🟡 Backend envelope реалізовано: `CoapEncryption.coap_encrypt` обгортає всі downlink-payloadи у `[0x9C][unix_ts_be:4][payload]` перед AES-256-CBC (`app/workers/concerns/coap_encryption.rb`). 47/47 specs зелені (`coap_encryption_spec`, `actuator_command_worker_spec`). Marker `0x9C = CMD_TIME_SYNC` обраний disjoint від `CMD_OTA_BYTECODE = 0x99` і ASCII `"CMD:"`. Year-2106 wrap покритий тестом. **Firmware Queen handler — TODO** (приймати envelope, парсити ts, оновити RTC, далі обробляти inner payload).
- [x] 🤖 Backend: включити server UTC timestamp у downlink payload — `[0x9C][unix_ts_be:4][payload]` envelope
- [x] 🤖 Backend specs: round-trip, monotonicity, year-2106 wrap, structural marker — 47/47 зелені
- [ ] 🤖 Firmware Queen: парсити CMD_TIME_SYNC envelope, оновити RTC, route inner payload (CMD/0x99)
- [ ] 🤖 Firmware Queen: реалізувати periodic beacon broadcast (UTC timestamp + network schedule) — забезпечує базову синхронізацію часу для ARCH.26
- [ ] 🤖 Firmware Soldier: прийняти та застосувати RTC correction (через mesh relay від Queen)
- [ ] 🤖 Тести: перевірити drift compensation при ΔT = ±60°C

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
- **Рішення:** (1) Підписати OTA image Ed25519 на backend, (2) Queen верифікує підпис перед relay, (3) Soldier верифікує перед Flash write. АБО: HMAC-SHA256 над повним image, transmitted як фінальний chunk
- [x] 🤖 Дизайн OTA authentication protocol — ✅ Повний дизайн HMAC-SHA256 OTA authentication додано в `03_05` §3.4б. Включає: threat model (substitution/bit-flip CRC16/replay), wire format `[0x9B]` HMAC-trailer chunks (3 додаткових LoRa-чанків після bytecode), HMAC input canonical (`bytecode || version_id || total_chunks` для anti-replay+anti-truncation), per-cluster `K_ota` через HKDF з окремим info-string `"silken-ota-hmac-v1"` для domain separation від AES key (FW.1), dual-gate verification на Soldier (Gate 1 magic `0x45544952` ~1 µs, Gate 2 HMAC ~3 мс через STM32 SHA256 hardware) — це покриває **й чекбокс «Magic check + HMAC verification = dual gate»** на дизайн-рівні. Implementation plan: 3 синхронні зміни (Backend `OtaPackagerService` + `OtaHmacKeyService`, Firmware Soldier dual-gate, Firmware Queen stateless relay) — mandatory з дня 1, без backward-compat shim (pre-production, no devices in field). ATECC608B slot 3 — future evolution до ECDSA-P256 при billion-tree масштабі
- [ ] 🤖 Backend: підпис OTA image перед відправкою
- [ ] 🤖 Firmware Queen: верифікація підпису/HMAC перед relay
- [ ] 🤖 Firmware Soldier: верифікація перед Flash write (`MRUBY_CONTRACT_FLASH_ADDR`)
- [ ] 🤖 Magic check `0x45544952 ("RITE")` + HMAC verification = dual gate

#### FW.25 — TinyML DSP preprocessing (FFT/MFCC) — undefined
- `03_03` BLOCKER-5 | `firmware/soldier/main.c` | **P1** (блокує FW.4)
- **Опис:** Поточна архітектура передає лише лінійну нормалізацію [0.0, 1.0] до TinyML моделі. **Невідомо**, чи модель очікує raw time-domain, чи частотні ознаки (FFT/MFCC). Залежить від `silken_net_audio_model.h` (відсутній). Якщо потрібен MFCC — це додає ~5-15 KB Flash + ~40 µs CPU на inference
- [ ] 👤 Узгодити з ML-партнером (Бушин ChNU або CHDTU): який preprocessing вбудований у модель?
- [ ] 🤖 Якщо MFCC — оцінити Flash/RAM/CPU budget і інтегрувати CMSIS-DSP
- [ ] 🤖 Тести: золотий вектор inference (наперед відома класифікація)

#### FW.26 — TENSOR_ARENA_SIZE ніколи не верифіковано
- `03_03` BLOCKER-3 | `firmware/soldier/main.c` | **P1**
- **Опис:** Точна величина `TENSOR_ARENA_SIZE` невідома з коду — документація оцінює ~8-16 KB. Ніколи не виміряно через `arm-none-eabi-size`. Якщо tensor arena > 46 KB → stack overflow при Lorenz обчисленнях (250 ітерацій mruby + Lorenz state)
- [ ] 🤖 Запустити `arm-none-eabi-size firmware/soldier/build/soldier.elf` після додавання моделі (FW.4) → виміряти `.bss + .data`
- [ ] 🤖 Якщо > 46 KB — оптимізувати модель (INT8 quantization, prune)
- [ ] 🤖 CI gate: build fail якщо `.bss + .data > 50 KB`

#### FW.27 — OTA broadcast: відсутня RX-верифікація Soldier
- `03_02` §5 | **P2**
- **Опис:** Queen транслює OTA chunks послідовно через LoRa без перевірки чи Soldier активно слухає. Якщо Soldier у STOP2 під час broadcast — chunk втрачається без retry. Документація **не описує recovery механізм** для пропущених chunks. Без TDMA Sync Windows (ARCH.26) — broadcast ненадійний
- **Статус:** 🤖 ✅ Дизайн обох recovery-механізмів завершено та задокументовано в `03_02` §5.X. (1) **ACK-Aggregation (Дизайн A):** Queen чекає 10-сек aggregation window після broadcast, Soldier'и відправляють bitmap-ACK; aggregated_missing → targeted re-broadcast. Імплементація залежить від ARCH.26 TDMA — без скоординованих RX-вікон 100 Soldier'ів = collision storm. (2) **Magic Re-Request (Дизайн B):** Soldier при `ota_chunks_received < ota_total_chunks` після 5-хв таймауту відправляє uplink-pacкет з `REREQUEST_MARKER (0x55)` + missing-bitmap; Queen ретранслює лише missing chunks (60-90% energy saving vs повний wave). Дизайн B feasible **без ARCH.26** — використовує існуючий `random_jitter % 500ms` (FW.10) для collision avoidance. Рекомендація: реалізовувати B першим, A — спільно з ARCH.26.
- [x] 🤖 Дизайн ACK-aggregation: Queen чекає consolidated ACK після всіх chunks → re-broadcast пропущених (`03_02` §5.X.2)
- [x] 🤖 Magic re-request: Soldier при detected gap → request specific chunks via uplink (vector OTA, `03_02` §5.X.3)
- [ ] 🔗 Залежить від ARCH.26 (TDMA для координованого RX вікна) — лише для Дизайну A; B можна реалізувати незалежно
- [ ] 🤖 Імплементація Дизайну B (firmware/soldier + firmware/queen) — наступний цикл

#### FW.29 — Panic packet (0xFF) vs saturated acoustic_events (255) — disambiguation
- `03_03` §5.3 | **P1**
- **Опис:** Panic пакети (chainsaw detection) форматуються з маркером `0xFF` (255). Saturated acoustic_events теж досягає 255 (FW.22 cap). **Без MAC/MIC** Queen не може розрізнити: bit-flip атака може перетворити нормальний пакет з 255 events на panic broadcast → false fire alert. Вирішується разом з FW.2 (CCM MIC), але потребує окремого дизайну на канальному рівні
- **Статус:** ✅ Виконано. `PANIC_FLAG_BIT` (0x80) додано в біт 7 StatusByte (байт 10). Нормальні пакети маскують біт 7 (`& 0x7F`), panic пакети встановлюють його. StatusByte формат: `[panic:1 | status:2 | growth_points:5]`. 2 unit tests: `test_panic_flag_set_in_emergency_payload`, `test_normal_payload_panic_flag_clear`.
- [x] 🤖 Дизайн: окреме поле `panic_flag:1 bit` у StatusByte (звільнити 1 біт від growth_points 6→5)
- [x] 🤖 АБО: panic packets мають окремий destination header byte
- [ ] 🔗 Інтегрувати з FW.2 CCM transition

---

## 🧪 Hardware / Lab

> ⚠️ Потребують фізичної роботи в лабораторії та/або з підрядниками.

#### HW.1 — nTop model → DMLS factory
- **Джерело:** `01_01` | ✅ Ліцензія отримана
- [ ] 👤 Генерація TPMS gyroid geometry (65% porosity)
- [ ] 👤 STL/STEP файл → передати на DMLS завод (Київ/Дніпро)
- [ ] 👤 SEM criteria для приймання партії

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

#### HW.4 — Self-healing coating
- **Джерело:** `01_02`
- **Опис:** 8-HQ мікрокапсули не синтезовані
- **Блокує:** 20+ років longevity claims, TRL 6
- [ ] 👤 Синтез 8-HQ мікрокапсул (in-situ polymerization)
- [ ] 👤 Інтеграція в PEO electrolyte або layer-by-layer
- [ ] 👤 Тест: 10× вищий Rct

#### HW.5 — Enzyme lifespan
- **Джерело:** `01_03` + Legacy notes
- **Опис:** GOx/Laccase деградація у кислому ксилемному середовищі (pH 4.5-5.5). Глутаральдегід фіксує ферменти механічно, але НЕ захищає від кислотної деградації. GOx виробляє H₂O₂ (окислювальний стрес для дерева)
- **Gen 1.0 ціль:** 3-5 років (Chitosan + Nafion захист)
- **Gen 2.0 ціль:** 20-25 років (FAD-GDH + Laccase/nanozyme + ZIF інкапсуляція)
- [ ] 👤 Розробка protective polymer matrix
- [ ] 👤 Тест Chitosan-шару (pH-буферизація) — додано в `01_03`
- [ ] 👤 Тест Nafion-покриття (селективна мембрана) — додано в `01_03`
- [ ] 👤 Тест комбінації Chitosan + Nafion (пріоритетний варіант)
- [ ] 👤 Тест: 3-5 років функціонального ферменту (Gen 1.0)
- [ ] 👤 **Gen 2.0:** FAD-GDH замість GOx (без H₂O₂) — `01_03` §3
- [ ] 👤 **Gen 2.0:** Laccase + laccase-like nanozymes (Cu/Ce/Au ZIF) — `01_03` §3
- [ ] 👤 **Gen 2.0:** ZIF-інкапсуляція для 20-25 років — `01_03` §3.3

#### HW.6 — Resin barrier
- **Джерело:** `01_04` + Legacy notes
- **Опис:** Сосни заливають рану смолою → блокує доступ до ферментів
- [ ] 👤 30° installation angle verification
- [ ] 👤 Hydrophilic coating test
- [ ] 👤 PEG обробка гіроїда: смола зісковзує з PEG-покритих пор — додано в `01_03`
- [ ] 👤 Hydrophobic/hydrophilic gradient test (PTFE знизу, гідрофільний верх) — додано в `01_04`
- [ ] 👤 Thermal installation test: T° нагріву (150-200°C), час витримки — додано в `01_04`
- [ ] 👤 FEM-моделювання теплового поля в Ti-6Al-4V анкері (λ = 6.7 W/m·K)

#### HW.7 — BQ25570 resistors verification
- **Джерело:** `02_03`
- **Опис:** CJMCU-25570 може мати Li-Po дефолт (VBAT_OV = 4.2V замість 5.5V для supercap)
- **Блокує:** Фіналізацію схеми, PCBA production
- [ ] 👤 Виміряти 8 резисторів мультиметром
- [ ] 👤 Порівняти з розрахунковою таблицею (Section 4 в `02_03`)
- [ ] 👤 Замінити SMD резистори якщо мисматч
- [ ] 👤 Задокументувати фінальні номінали

#### HW.8 — Pogo pin specification (5 блокерів)
- **Джерело:** `02_02`
- [ ] 👤 BLOCKER-1: Матеріал напилення → Gold (Hard Gold, Au 0.76 µm)
- [ ] 👤 BLOCKER-2: Сила пружини → ~100 г/пін, Travel ≥ 1.5 мм
- [ ] 👤 BLOCKER-3: Механізм фіксації → Quarter-turn bayonet (рекомендовано)
- [ ] 👤 BLOCKER-4: O-ring → EPDM, CS 1.5-2.0 мм, 15-25% compression
- [ ] 👤 BLOCKER-5: Допуски соосності → Lead-in chamfer

#### HW.9 — PCB KiCad layouts
- **Джерело:** `02_01`
- **Опис:** Soldier PCB та Queen PCB: "Не розпочато"
- [ ] 👤 Soldier PCB layout (KiCad)
- [ ] 👤 Queen PCB layout (KiCad)
- [ ] 👤 RF Keep-Out Zone verification

#### HW.11 — Potting material selection (quartz resonator risk)
- **Джерело:** `02_01` BLOCKER-1
- **Опис:** Потрібно обрати epoxy compound що НЕ знищить quartz resonator LoRa модуля при -20°C. Rigid compound при температурному стисненні → тріщини кварцу → RF loss
- **Рішення:** Soft compound Shore A < 50 (Dow Sylgard 184 або аналог)
- **Блокує:** Hardware freeze, IP67 certification
- [ ] 👤 Обрати compound (Sylgard 184 рекомендовано)
- [ ] 👤 Верифікувати з кварцовим резонатором при -20°C / +60°C

#### HW.12 — EBFC upper voltage limit >5.5V protection
- **Джерело:** `02_01` BLOCKER-2
- **Опис:** При тривалій інсоляції EBFC може генерувати напругу >5.5V → overcharge supercap → деградація/вибух
- **Блокує:** Hardware safety, TRL 5
- [ ] 👤 Верифікувати BQ25570 OV protection threshold (VBAT_OV = 5.5V, див. HW.7)
- [ ] 👤 Додати TVS-діод або зенерівський обмежувач як backup

#### HW.13 — MPPT coefficient verification for EBFC
- **Джерело:** `02_03` BLOCKER-2 + Legacy notes
- **Опис:** Поточний MPPT = 50% VOC (ROC1=ROC2=10MΩ) — **занадто низько для EBFC**. EBFC (GOx/Laccase) має специфічну поляризаційну криву (Міхаеліс-Ментен + Тафель), MPP лежить у діапазоні 60-70% VOC. При 50% — зона масо-транспортних обмежень ферменту
- **Рекомендація:** Почати з 65% (ROC1=5.36 MΩ, ROC2=10 MΩ)
- **Блокує:** Max EBFC power, optimal charge speed
- [ ] 👤 Зняти повну P-V криву (потужність-напруга) EBFC
- [ ] 👤 Виміряти VOC та VMP при різному освітленні (ранок/день/вечір, сезонно)
- [ ] 👤 Визначити оптимальну фракцію (починати з 65%)
- [ ] 👤 Якщо потрібно — замінити ROC1/ROC2

#### HW.14 — Winter energy deficit for Queen Phase 3 (Starlink Mini)
- **Джерело:** `02_05` BLOCKER-2
- **Опис:** Phase 3 (Starlink Mini): 44 Wh/day consumption vs 18.75 Wh/day winter generation = -25 Wh/day deficit. 12V/20Ah LiFePO4 → 7.7 днів автономності
- **Пріоритет:** Phase 3 only (Phase 2.5 unaffected)
- [ ] 👤 Збільшити батарею до 40Ah (15 днів автономності), АБО
- [ ] 👤 Зменшити Starlink duty cycle до 1 хв/год (~9 Wh/day), АБО
- [ ] 👤 Встановити 100W solar panel
- [x] 🤖 Оновити Unit Economics (07_02) — ✅ Phase 3 BOM таблиця (Queen ~$825 + $599 Starlink = $1,424/cluster), Phase 3 cluster economics ($5,404 CAPEX, $179/міс OPEX), ROI сценарії (breakeven SCC $0.41 standalone / $0.18 при 3-cluster sharing / $0.07 duty-cycle), стратегія Starlink sharing через ARCH.10 додано в `07_02` §4а + §5а

#### HW.15 — BMS not specified for Queen
- **Джерело:** `02_05` BLOCKER-4
- **Опис:** SIM7070G TX peak current до 2A. BMS model не вказано в BOM
- [ ] 👤 Обрати BMS: мінімум 12V / 20A continuous / 50A peak
- [ ] 👤 Обрати MPPT: мінімум Victron SmartSolar MPPT 75/15
- [ ] 👤 Оновити BOM

#### HW.16 — Thermal management в IP67 enclosure
- **Джерело:** `02_05` BLOCKER-5
- **Опис:** SIM7070G + MCU при TX: ~500 mW × 5 sec. Літній interior temp до 60-70°C. LiFePO4 charging при T < 0°C пошкоджує батарею
- **Статус:** 🤖 ✅ Тепловий бюджет розраховано та задокументовано в `02_05` §4а «Тепловий бюджет IP67 корпусу» — Phase 1/2.5 (~130 мВт середнє → ΔT < 1 K) та Phase 3 (3 Вт burst → ΔT ~4.5 K), sun load — головний внесок (+15 K). Активне охолодження не потрібне при T_зовн ≤ +40°C. Sun-shade / світлий корпус — рекомендовано
- [x] 🤖 Розрахувати thermal budget для enclosure (T_ext = +40°C)
- [ ] 👤 Додати temperature sensor (NTC або DS18B20)
- [ ] 👤 Реалізувати hardware charge protection при T < 0°C

#### HW.17 — PEEK radome prototype (Деталь 4)
- **Джерело:** `02_01` §5.2 + Legacy notes
- **Опис:** Деталь 4 (PEEK Crown / Капсула-Радом) — радіопрозорий купол ∅20–30 мм, який «насаджується» на зовнішню різьбу Деталі 3 (Анод). Різьба або байонет + O-ring EPDM → IP68. Керамічна SMD-антена в міліметрі від внутрішньої стінки PEEK. Прототип "Не розпочато"
- **Блокує:** Ceramic antenna protection, RF performance validation, Zero-Touch Assembly validation
- [ ] 👤 KiCad PCB layout (HW.9) → PEEK radome dimensions
- [ ] 👤 Визначити тип кріплення: різьба на Деталь 3 vs байонет
- [ ] 👤 Визначити матеріал O-ring (EPDM vs FKM) для ксилемного середовища
- [ ] 👤 Замовити PEEK прототип (CNC або injection molding)
- [ ] 👤 Верифікувати RF performance (VSWR, КСВ) з антеною під радомом

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
- [ ] 🤖 Дизайн завершений
- [ ] 🤖 Реалізація Factory Flashing tool
- [ ] 🤖 Integration тест з provisioning API

#### SEC.4 — Reed Switch shipping mode (not in BOM)
- **Джерело:** `03_05` NOTE-3
- **Опис:** Reed switch (магнітний сенсор) для zero consumption при транспортуванні. Магніт на коробці → circuit open. Інсталятор знімає магніт → first power-up. ~$0.05/unit. Дизайн approved, BOM не оновлений
- [ ] 👤 Додати Hamlin 59140-1-T-00-A reed switch + N52 neodymium magnet до BOM
- [ ] 👤 Оновити KiCad schematic

#### SEC.6 — Secure Element (ATECC608B) не використовується
- **Джерело:** `03_05` | Firmware architecture
- **Опис:** AES-256 ключ зберігається у plain Flash STM32 (навіть з RDP Level 1 — key extraction можливий через glitching/side-channel). ATECC608B забезпечує hardware-protected key storage з tamper-detection. Ціна ~$0.60/unit
- **Пріоритет:** P2 (Post-TRL 7, перед mass production >1000 units)
- **Статус:** 🤖 ✅ Інтеграційна оцінка ATECC608B з STM32WLE5JC задокументована в `03_05` §3.7 «ATECC608B Secure Element — оцінка інтеграції»: I²C interface (PB6/PB7), slot mapping (slot 0=AES, 1=ECC priv, 2=cert, 3=HMAC OTA), latency impact (~1.5 мс/блок vs 10 µs HAL_CRYP — нехтовно), power impact (+0.1% energy budget), Factory Flashing pipeline з ATECC, альтернатива STSAFE-A110 (native CubeMX, переважна для unified ST toolchain), OPTIGA Trust M (overkill), NXP A71CH (EOL — уникати). Firmware HAL drop-in API окреслено
- [x] 🤖 Оцінити ATECC608B integration з STM32WLE5JC (I²C interface)
- [x] 🤖 Дизайн key storage: ATECC608B slot 0 = AES key, slot 1 = device certificate
- [ ] 🤖 Оновити Factory Flashing pipeline (SEC.3) для ATECC608B provisioning — наступний цикл
- [x] 🤖 Оцінити альтернативи: STSAFE-A110 (ST ecosystem), Infineon OPTIGA Trust M

#### SEC.7 — OTA image автентифікація (cross-ref FW.23)
- **Джерело:** `03_05`, `03_02`
- **Опис:** OTA broadcast (mruby bytecode та потенційно firmware updates) не має цифрового підпису. Пов'язано з FW.23 але виділено як окремий security item через критичність. Поточний захист — лише AES-256-ECB шифрування (яке буде замінено на CCM в FW.2)
- **Пріоритет:** P1 (перед першою OTA в полі)
- [ ] 🤖 Ed25519 key pair: private на backend, public у Soldier/Queen Flash (protected sector)
- [ ] 🤖 Backend: `OtaPackagerService` → sign(bytecode) → append signature
- [ ] 🤖 Firmware: verify signature перед Flash write
- [ ] 🤖 Fallback: HMAC-SHA256 якщо Ed25519 не вміщується в SRAM budget

#### SEC.9 — Production AES Key містить FIPS-197 Appendix B Test Vector
- **Джерело:** `03_05` | **Пріоритет: P0 (до будь-якого field deploy)**
- **Опис:** Аудит виявив: перші 4 слова production AES key **ідентичні публічно відомому** FIPS-197 Appendix B AES-128 test vector (стандартний тест-вектор зі специфікації NIST). Будь-який фахівець з криптографії може впізнати цей паттерн. При RDP Level 0 — trivial key extraction
- **Важливо:** Це ОКРЕМЕ від FW.1 (hardcoded key) — навіть після per-device provisioning, якщо master seed базується на цьому ключі, весь derivation tree скомпрометований
- [ ] 👤 Негайно замінити seed key на криптографічно стійкий random (hardware RNG або аудитований генератор)
- [ ] 🤖 Верифікувати що новий master key НЕ є жодним відомим test vector (FIPS-197, NIST, RFC)
- [ ] 👤 Задокументувати процес генерації нового master key у vault (Bitwarden/1Password) — **без коміту ключа в репозиторій**
- [ ] 👤 Після заміни: re-flash всі існуючі прототипи

#### SEC.10 — Emergency TX пакети без MAC/MIC автентифікації
- **Джерело:** `03_05`, `03_02` | **Пріоритет: P1**
- **Опис:** EwsAlert panic packets (chainsaw detection, PANIC_TTL=5) відправляються без жодної автентифікації. Зловмисник може: (1) replay легітимний panic packet → false forest fire alert → евакуація/паніка, (2) inject forged panic packets → множинні false alarms → недовіра до системи та страхових виплат
- **Важливо:** Критичніше за звичайні пакети — emergency TX обходить звичайні rate limits. Вирішується разом з FW.2 (AES-256-CCM), але потребує окремої уваги через life-safety implications
- [ ] 🤖 Не відкладати вирішення на "після FW.2" — мінімальний fix: Frame Counter у RTC як anti-replay для panic packets
- [ ] 🔗 Верифікувати що `EwsAlert` broadcast застосовує той самий CCM MIC що і звичайні пакети (після FW.2)
- [x] Backend: rate limiting на emergency callbacks — не більше N panic alerts/хвилину від одного DID

#### SEC.11 — Raw DID як seed Lorenz атрактора (Dual Computation Integrity bypass)
- **Джерело:** `03_06` (повний дизайн SSOT) | `03_04` BLOCKER-1 cross-ref | **Пріоритет: P1**
- **Опис:** Поточний firmware mruby `bio_contract.rb` стартує атрактор з `(x₀,y₀,z₀)` виведених із `chaos_seed = HRNG()` (Soldier-side) і **DID** (server-side mirror). DID їде відкритим текстом у заголовку LoRa-пакета (`[DID:4]`, поза AES-блоком). Чотири фундаментальні вади: (1) публічний seed → атакер з open-source формулою Лоренца обчислює очікуваний Z для будь-якого дерева → підробляє телеметрію з валідним StatusByte, `check_z_divergence!` мовчить; (2) сусідні DID видаються послідовно → перші ~30 ітерацій Ейлера дають майже ідентичні траєкторії (знижена статистична ентропія); (3) семантична помилка категорій — DID *identifier*, не *key*; (4) відсутність forward secrecy — одне дерево все життя стартує з тієї ж точки.
- **Наслідок для DCI:** `check_z_divergence!` змушений бути **категоричним** (homeostasis/stress/anomaly enum), а не числовим, бо публічний DID не дозволяє використовувати точне `(server_z − device_z).abs < ε` без розкриття алгоритму атакеру. Атакер з `Z_fake = 28.0` проходить перевірку.
- **Прийняте рішення (2026-05-02):** **Гібрид варіантів A + B + D** — повний дизайн у `docs/03_06_Lorenz_Seed_Provenance.md` §4.
  - **A** — `K_seed = HKDF-SHA256(PROVISIONING_MASTER_KEY, salt="silken-lorenz-v1", info=DID, len=32)`, виводиться при provisioning, зберігається в `hardware_keys.lorenz_seed_hex` (AR Encryption non-deterministic) і в Soldier Flash (поряд з `K_aes`).
  - **B** — daily epoch rotation: `(x₀,y₀,z₀) = unpack_signed_unit_floats(HMAC-SHA256(K_seed, "init|" || epoch_day_be)[0..23])`. Forward secrecy ≤ 24 год, синхронізовано через FW.20 `CMD_TIME_SYNC`.
  - **D** — cold-start derive відбувається лише після VBAT loss (рідкісна подія); у норму FW.6 RTC continuation (DR16-DR18 magic `"LZST"`) пропускає re-init.
  - Варіант **C** (per-packet seed) відкинуто — overhead на STM32WLE5JC не виправдовує marginal security gain над B + continuation.
- **Ефект на DCI:** після SEC.11 обидві сторони стартують з byte-identical `(x₀,y₀,z₀)` (HMAC-SHA256 detrministic). Float divergence між ARM та x86 IEEE-754 за 250 ітерацій < 1e-12 (емпірично, FW.7 closure). `check_z_divergence!` стає числовим: `(server_z - device_z).abs < 0.001` — 9 порядків запасу над архітектурним drift, fake-телеметрія детектується з ~99.99% recall.
- **Залежності:** Reuse існуючої `PROVISIONING_MASTER_KEY` infra (нуль нових сервісів). Synергізує з FW.20 (час потрібен ± 1 година) і FW.6 (RTC continuation вже працює).
- **Threat model post-SEC.11** (`03_06` §7): sniff LoRa → відтворити Z ❌; replay вчорашнього пакета ❌ (epoch_day змінився); compromise одного `K_seed` ⚠️ (вузол уразливий ≤ 24 год, інші — ні); compromise `PROVISIONING_MASTER_KEY` 🚨 (cascading — окрема rotation strategy SEC.9).
- [ ] 🤖 Schema migration: `hardware_keys.lorenz_seed_hex`, `telemetry_logs.lorenz_state_x/y/z`, `telemetry_logs.cold_start_flag`
- [ ] 🤖 `SilkenNet::SeedDerivation` сервіс (HKDF + HMAC-SHA256 + signed-unit-float unpack) + 8-10 specs
- [ ] 🤖 `HardwareKey#binary_lorenz_seed` (AR Encryption non-deterministic, як `binary_key`)
- [ ] 🤖 `Attractor.calculate_z_from_state(x0, y0, z0, σ, ρ, β, n)` — новий API; legacy `calculate_z(chaos_seed, ...)` deprecate-then-delete (pre-prod, без shim'ів)
- [ ] 🤖 `TelemetryUnpackerService` — per-tree seed dispatch; numeric divergence (`< 0.001`) включити після 100% field migration, до того — категоричний як fallback
- [ ] 🤖 `Provisioning::RegistrationService` — генерувати + повертати `K_seed` поряд з `K_aes`
- [ ] 🤖 Firmware: HKDF/HMAC через mbedTLS (вже linkована для AES); ~4KB image overhead; Flash sector для `K_seed` поряд з `K_aes`
- [ ] 🤖 Firmware `bio_contract.rb` — приймати `(x₀,y₀,z₀)` як args, видалити DID-derive code path
- [ ] 🤖 `firmware/test/test_seed_derivation.c` — host-based parity test (1000-case fuzz: byte-exact `(x₀,y₀,z₀)` match із backend `SeedDerivation`)
- [ ] 🤖 100-case end-to-end parity: random `(K_seed, epoch_day, σ, ρ, β)` → Z-divergence < 1e-9 firmware vs backend
- [ ] 🤖 Field migration endpoint: `POST /api/v1/provisioning/upgrade_seed` — re-provision існуючих вузлів upon first uplink post-deploy
- [ ] 🤖 Flip `check_z_divergence!` на numeric tolerance band після 100% migration

---

## 📝 Документаційні невідповідності (DOC)

Потребують узгодження між docs, firmware та backend. **Не блокери виконання, але блокери для аудиту і онбордингу.**

DOC.9 — потребує лабораторного вимірювання TX-струму

| ID | Невідповідність | Документи / Файли | Дія | Статус |
|----|----------------|-------------------|-----|--------|
| DOC.1 | Документація AES master key суперечлива: `03_05` лінія 531-537 каже «навмисно не публікується», а лінія 538 натякає що перші 4 слова збігаються з FIPS-197 Appendix B test vector. Скоординувати після SEC.9 (заміна seed key) | `03_05`, `firmware/soldier/main.c:66-67` | Після SEC.9 видалити test-vector згадку, оновити обидва параграфи | ⏸️ Заблоковано SEC.9 |
| DOC.4 | Lorenz first-boot vs continuation logic розкидана між `03_04` §2.1 (опис `calculate_state_continued`) та `03_01` §6 (RTC magic check). Потрібна одна точка істини | `03_04`, `03_01` | Об'єднати у `03_04` §2.1 з cross-ref на RTC layout | ✅ Виконано (`03_04` §2.1 callout + cross-ref) |
| DOC.7 | `04_02` §4.2.2 (BlockchainMintingService) описує що guards активні тільки для oracle-driven flow, але tokenomics flow проходить **без явного guard chain**. Зв'язок між цими шляхами не пояснений у `05_02_Proof_of_Growth_Pipeline.md` | `04_02`, `05_02` | Об'єднати у `05_02` §4: діаграма «всі шляхи до `Wallet#lock_and_mint!`» з invariant'ами кожного | ✅ Виконано (`05_02` нова секція «Усі Шляхи до `Wallet#lock_and_mint!`» з 5 шляхами + інваріанти) |
| DOC.9 | Documentation `02_03` §9.3 raніше використовувала 15 mA/50 ms для LoRa TX. Виправлено на 120 mA/100 ms (~39 мДж) per SX1262 datasheet. Firmware energy accounting **не верифіковано незалежно** | `02_03`, `firmware/soldier/main.c` | Лабораторне вимірювання поточного TX (HW.x) + cross-ref у `02_03` після верифікації | ⏸️ Заблоковано лаб-стендом |

---

## ⚙️ Операційна автоматизація (OPS)

#### OPS.1 — TRL Auto-Advancement GitHub Action
- **Джерело:** `09_03` | **Складність: M**
- **Опис:** `trl_sync.yml` — GitHub Action що автоматично переміщує картки на Project Board при закритті issues з TRL-labels. Описаний як "на стадії впровадження" (TRL 7), але не реалізований. Потребує `secrets.PROJECT_PAT` з GraphQL project board permissions
- **Статус:** ✅ Виконано. `.github/workflows/trl_sync.yml` створено з GraphQL API для GitHub Projects v2 (user + org fallback)
- [x] Створити `.github/workflows/trl_sync.yml`
- [x] Налаштувати GraphQL API для GitHub Projects v2
- [ ] 👤 Створити `PROJECT_PAT` secret з project:write scope
- [ ] 👤 Тестування з тестовими issues

#### OPS.2 — SSOT Integrity Guard
- **Джерело:** `09_03` | **Складність: M**
- **Опис:** GitHub Action що блокує merge PRs якщо зміни в `app/models/` або `firmware/` не супроводжуються відповідними оновленнями в `docs/` або Wiki. Запобігає context drift між кодом та документацією
- **Статус:** ✅ Виконано (Сесія 18). `.github/workflows/ssot_guard.yml` створено. Перевіряє: `app/models/`, `firmware/soldier/`, `firmware/queen/`, `firmware/bio_contracts/`, `contracts/`, `app/services/`. Bypass через label `ssot-bypass`. Виводить деталізований звіт у PR check.
- [x] Створити `.github/workflows/ssot_guard.yml`
- [x] Визначити mapping: які файли потребують яких doc updates
- [ ] 👤 Налаштувати як required check на `main` branch

#### OPS.3 — R&D Portfolio Management: Shape Up + cluster routing
- **Джерело:** `08_01` §1.1-1.3, `08_02` §1, `08_03`, `09_01` | **Складність: L** | **🤖 Методологія + Док**
- **Опис:** 25+ паралельних R&D-задач розподілені між 8+ науковцями (ChNU FOTIUS + ChDTU + ChIPB + ChMA + СЄУ). Поточно — ad-hoc розподіл. Запропоновано: 4-кластерна структура (A: Hardware/EBFC, B: Verification/Math, C: Scaling/Cloud, D: Compliance/Legal) + Shape Up 6-week cycles + Convolution Method для скорочення PN-state explosion 10-100×
- [ ] 🤖 Дизайн kanban-mapping: 4 кластери у GitHub Projects V2 + label conventions
- [ ] 🤖 Документувати у `09_01` Shape Up cycle template + betting table процедуру
- [ ] 👤 Перший betting cycle після UNI.1 (декан) та UNI.8 (СЄУ)

#### OPS.4 — GitHub Projects V2: семестрова синхронізація з ChNU/ChDTU
- **Джерело:** `09_03`, `08_01` | **Складність: M** | **🤖 Код**
- **Опис:** TRL-матриця прив'язана до seasons (Q1/Q2/Q3/Q4), але навчальний рік ChNU/ChDTU має семестри (вересень-грудень, лютий-травень). Без mapping — milestone-deadlines не синхронізовані з академічним календарем (наприклад, фінальні захисти магістерських у червні)
- [ ] 🤖 Додати у `09_03` mapping: семестр ↔ TRL milestone
- [ ] 🤖 Розширити `trl_sync.yml` на запис академічних semestriv як окремий field у Projects V2
- [ ] 👤 Узгодити календар з 8 науковцями (UNI.5)

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
- **Джерело:** `08_04` §1.3 | **Пріоритет: P2**
- **Опис:** ПМКТ (Прикладна механіка + комп'ютерні технології) ChDTU — спеціалізація п'єзоелектрика + акустичні метаматеріали. Потрібно: EIS-характеризація п'єзодиска 25-150 кГц (TinyML cavitation detection), верифікація гіроїдного фокусування (phonon lens) для кавітації ксилеми. Цільовий результат: стаття Q1 *IEEE Transactions on Biomedical Engineering*
- [ ] 👤 Формальна зустріч з Базіло + Бондаренко
- [ ] 👤 EIS-протокол для п'єзодиска (постачання зразка)
- [ ] 👤 Acoustic стенд-тест для гіроїда (cross-ref HW.1)

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

---

## 💡 Додаткові знахідки (не блокери)

| # | Знахідка | Джерело | Примітка |
|---|----------|---------|----------|
| E.3 | Breadboard video відсутнє (для грантів) | `07_03` | Зняти відео |
| E.4 | Helium Network fallback — concept є, реалізації немає | `02_05` | Дизайн + реалізація |
| E.5 | CoAP listener Ruby — масштабується до ~10k вузлів | `06_01` | Series D: Rust/Go proxy |
| E.7 | dClimate mock mode — потрібна реальна інтеграція для Production | `05_01` | Пов'язано з S3.2 |
| E.8 | SNR parameter unused у Queen CIFO eviction (лише RSSI) | `03_02`, `03_03` | Low priority optimization |
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
| E.45 | **SCC/SFC contract addresses** = `0x0000...0` в subgraph.yaml — блокує deploy subgraph на testnet/mainnet | `05_03` | Пов'язано з S3.5 |
| E.47 | **Solana RPC defaults to Devnet** — production мінтинг USDC мікро-винагород піде на Devnet якщо не встановлений `SOLANA_RPC_URL` | `05_01` | ⚠️ Перевірити ENV перед mainnet |
| E.48 | **The Graph subgraph на testnet `polygon-amoy`** — потребує mainnet deploy перед production | `05_01` | Post mainnet deploy |
| E.49 | **Celo RPC fallback mechanism** не вказаний — при збої primary RPC немає автоматичного переключення | `05_01` | P3: додати fallback RPC |
| E.50 | **Edge fuzzy_distance dedup function** на STM32WLE5JC: <1 мс CPU, <128 байт RAM, ціль — 30-40% TX зниження за рахунок suppression near-duplicate пакетів | `08_02` §1.3 (Vector 1, Ярмілко) | Post-TRL 7 (R&D — Ярмілко) |
| E.51 | **Monte Carlo TTL-flood симуляція** для обґрунтування `PANIC_TTL=5` та `DEFAULT_TTL=3`: цільовий P_delivery ≥ 0.99 при 20-30% одночасних відмов вузлів. Виходи: math-обґрунтування для seed deck | `08_02` §1.2 (Vector 2) | Post-TRL 6 (Порубльов, ЧНУ) |
| E.52 | **GA-оптимізація ваг `silken_forest.marshal`** ML моделі на Akash GPU кластері — генетичний алгоритм для `InsightGeneratorService` stress_index класифікації | `08_02` §1.6 (Любченко) | Post-TRL 7 |
| E.53 | **VNA-вимір SMD-антени під PEEK радомом** — VSWR <1.5 на 868 МГц для 3-5 варіантів товщини PEEK (1.5/2.0/2.5 мм) у вологому/сухому стані. Лабораторна задача (cross-ref UNI.10 ChDTU Гончаров) | `08_02` §1.3 + `02_01` | P1, blocked by HW.17 + UNI.10 |
| E.54 | **SOP документи для 7 типів EwsAlert** — стандартизовані інструкції UA+EN: severe_drought, insect_epidemic, vandalism_breach, fire_detected, seismic_anomaly, system_fault, entropy_anomaly. Інтеграція як inline UI у Phlex (cross-ref ARCH.31) | `08_05` | P1, joint with ChIPB-NUTSU (UNI.12) |
| E.55 | **Multi-party NDA + IP framework** для 5-сторонньої академічної співпраці (ChNU + ChDTU + ChIPB + ChMA + СЄУ + Silken Net) — base-line для всіх UNI.x публікацій | `08_03`, `08_05`, `08_06`, `08_07` | P1, cross-ref BIZ.10 |
| E.56 | **DSP preprocessing для TinyML** — невідомо чи модель очікує raw time-domain чи MFCC. Якщо MFCC → +5-15 KB Flash + 40 µs CPU (CMSIS-DSP) | `03_03` BLOCKER-5 | P1, cross-ref FW.25 |
| E.57 | **TENSOR_ARENA_SIZE budget verification** — ніколи не виміряно через `arm-none-eabi-size`. Ризик stack overflow якщо > 46 KB | `03_03` BLOCKER-3 | P1, cross-ref FW.26 |
| E.58 | **Lorenz state continuity** після brownout: документація specifies повний (x,y,z) save в RTC Backup, але недостатня формалізація first-boot vs continuation logic. Магічний marker `LZST` (0x4C5A5354) реалізовано — потребує канонічної таблиці RTC layout | `03_04`, `03_01` | P2, cross-ref DOC.3, DOC.4 |

---

## 🏛️ Архітектурні пропозиції (довгострокові)

| ID | Пропозиція | Джерело | Milestone |
|----|-----------|---------|-----------|
| ARCH.1 | Fractal topology: L2 Sergeant nodes (H-LDSE hierarchical routing, geohashing) | `00_01` | Post-TRL 7 |
| ARCH.2 | Ingress Proxy (Rust/Go) + Kafka для >1M packets/hour | `00_01`, `06_01` | Series D |
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
| ARCH.26 | **Синхронні Вікна (TDMA) та CAD Preamble Detection — вирішення Проблеми Рандеву для mesh relay.** Поточна архітектура: Queen always-on (`Radio.Rx(LORA_RX_INFINITE)`), Soldier має лише 600 мс post-TX RX window — mesh relay між Солдатами стохастичний і ненадійний за межами прямої видимості Queen. **Три рівні рішення:** (L1) Queen always-on ✅ реалізовано; (L2) TDMA Sync Windows — Queen транслює beacon з точним часом (NTP через LTE), Солдати синхронізують RTC, кожні 15 хвилин координоване 2-секундне RX-вікно для mesh relay. Залежить від FW.20 (LoRa Time Sync); (L3) CAD — SX1262 `Radio.StartCad()` дозволяє wake на ~2 мс/секунду для детекції LoRa-преамбули без повного RX. Критично для PANIC mode: Солдат при chainsaw detection посилає довгу преамбулу (~1 сек), сусідні Провідники ловлять через CAD навіть між TDMA-вікнами. **Firmware зміни:** Soldier: CAD periodic wakeup (LPTIM або RTC sub-second alarm), beacon RX handler, RTC sync logic. Queen: beacon TX (periodic broadcast з UTC timestamp + network schedule). **Енергобюджет:** CAD wake 1/сек × 2 мс × 4.5 мА = ~9 µA середнє — допустимо для Провідників (дерева з високим vcap), неприйнятно для слабких Солдатів. Рольова диференціація: Солдат (TX-only, глухий) vs Провідник (TX+CAD, еліта з надлишком енергії). | `00_01`, `03_01`, `03_02` | Post-TRL 6 (Firmware + Queen beacon) |
| ARCH.27 | **Node Role Differentiation (Soldier vs Provisioner) у firmware** — ARCH.26 передбачає рольову диференціацію (Soldier=TX-only, Provisioner=TX+CAD), але **firmware компілюється ідентично для обох ролей**. Runtime role не персистована у Flash/RTC. Без role-aware logic — неможливо реалізувати енерго-диференційовану mesh relay | `00_01`, `03_01` | Post-TRL 6 (передумова для ARCH.26 L3) |
| ARCH.28 | **RTC Backup Domain allocation policy** — DR0..DR23 регістри активно використовуються (Lorenz state, mesh cache, EMA, FW.18 thresholds). Резерв вичерпується. Потрібна формальна політика: (a) канонічна таблиця у `03_01`, (b) procedure для додавання нової фічі (review impact на existing fields), (c) consideration для Flash-based key-value store як overflow | `03_01` §2 | Post-TRL 6 (документація + майбутнє розширення) |
| ARCH.29 | **RTOS Deadlock-Free верифікація через Petri Nets** — формальна PN-модель firmware tasks (Sensing/Compute/TX/OTA/WDT) на Soldier + reachability graph аналіз для доведення відсутності circular wait. Відрізняється від ARCH.20 (Petri Net Rails моноліт) тим що моделює embedded RTOS scheduling | `08_02` §1.2 (Ярмілко) | Post-TRL 6 (R&D — Ярмілко, ЧНУ) |
| ARCH.30 | **Parallel CFD gyroid simulation на Akash GPU** — domain decomposition алгоритм для 3D TPMS-симуляцій на heterogeneous GPU вузлах Akash. Скорочує CFD lead-time з ~2 годин до real-time валідації геометрії перед DMLS order. Cross-ref ARCH.25 (gyroid validation scripts) | `08_02` §1.4 (Онищенко) | Post-TRL 7 (методологія + Akash GPU integration) |
| ARCH.31 | **SOP-в-Phlex inline UI для EwsAlert** — інтеграція 7 SOP документів (drought/epidemic/vandalism/fire/seismic/fault/entropy) як inline-інструкцій, що показуються при кліку на EwsAlert у дашборді. UX: forester отримує немедіане runbook замість пошуку у документах | `08_05` + `04_02` | Post-TRL 6, cross-ref E.54 + UNI.12 |
| ARCH.32 | **Shape Up 6-week cycle Petri Net formalization** — формальна верифікація фази Shape Up (betting table → build → cool-down) щоб довести: будь-яка фіча може бути завершена у межах cycle constraints. Цільова стаття Q1 *IEEE Transactions on Software Engineering* | `08_02`, `09_01` | Post-TRL 7 (методологія + R&D, Супруненко ЧНУ) |
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
| 10 Security | 6 | 9 | SEC.9 master key, SEC.11 prod guard, Multisig, RDP, Factory (Rails web layer ✅ S6.18) |

---

> **Як оновлювати цей документ:**
> 1. Знайти відповідний пункт (S1.1, FW.3, HW.7, тощо)
> 2. Змінити `[ ]` → `[x]` для виконаних підзадач
> 3. Для нових знахідок — додавати у відповідну секцію + посилання на джерело docs
> 4. Раз на квартал — повний docs audit з оновленням «Top-Critical Path» секції зверху
