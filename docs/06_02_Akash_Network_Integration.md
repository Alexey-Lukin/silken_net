# 06_02: Akash Network Integration (Децентралізовані Обчислення)

## 🎯 Мета

Зафіксувати **фактичний стан** конфігурації Akash Network. Документ відповідає на три ключові питання:

1. Які **обчислювальні ресурси** (CPU, RAM, Disk) замовляються в Akash SDL?
2. Які **змінні середовища (ENV)** очікує отримати контейнер при деплої?
3. Які **архітектурні блокери** унеможливлюють повноцінне децентралізоване розгортання сьогодні?

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — SDL повністю конфігурований (`web` + `job` + `alloy`), DB+Redis connectivity вирішені (Cloud SQL Auth Proxy + Upstash TLS), GHCR mirror активний; жоден реальний деплой на Akash Mainnet ще не проведений (TRL 6 — після першого успішного деплою).
- **Конфігуровано:** Cloud SQL Auth Proxy, Upstash Redis (TLS), Solid Cable (multi-replica ActionCable), GHCR mirror, Ingress Anchor, Rails security hardening (`force_ssl`/HSTS/CSP).
- **Відкрите:** SDL secrets, TLS термінація, GCS state bucket, перший Mainnet деплой → [`00_07`](00_07_Action_Plan_Tracker) (S4.3, INF.4, S5.6).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `deploy/akash/deploy.yaml` · `deploy.yaml.tpl` | SDL: `web` + `job` + `alloy` сервіси |
| `deploy/akash/config.alloy` | Grafana Alloy scrape + remote_write |
| `terraform/akash/` | SDL templating + Akash CLI provisioner |
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | GCP/Kamal, Ingress Anchor |
| [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) | Alloy → Grafana Cloud |
| [`06_04` — Secrets Checklist](06_04_Secrets_Checklist) | SDL secrets — SSOT |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Бізнес-логіка (що деплоїться) |
| [`06_07` — CICD and Runbook Index](06_07_CICD_and_Runbook_Index) | mirror-ghcr, deploy pipeline |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | S4.3, INF.4, S5.6 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Відкриті передумови деплою та Runbooks](#-відкриті-передумови-деплою-та-runbooks)
- [1. SDL Маніфест — Розбір "Як Є"](#1-sdl-маніфест--розбір-як-є)
- [2. Змінні Середовища (Environment Variables)](#2-змінні-середовища-environment-variables)
- [3. Terraform Конфігурація](#3-terraform-конфігурація)
- [4. Процес Деплою (CLI Commands)](#4-процес-деплою-cli-commands)
- [5. Порівняння: Akash vs GCP Production](#5-порівняння-akash-vs-gcp-production)
- [6. Відповідність Kamal → Akash](#6-відповідність-kamal--akash)
- [7. Інтеграція у Загальну Архітектуру Gaia 2.0](#7-інтеграція-у-загальну-архітектуру-gaia-20)
- [8. Дорожня Карта (Path to TRL 5 → 9)](#8-дорожня-карта-path-to-trl-5--9)
<!-- TOC:AUTO:END -->

---

## ⚙️ Відкриті передумови деплою та Runbooks

> Відкриті передумови першого деплою + операційні runbooks. Статуси трекаються в [`00_07`](00_07_Action_Plan_Tracker) (S4.3, INF.4, S5.6).

### Секрети SDL не заповнені — Rails не стартує + Web3 воркери у DeadSet

**Статус:** Критичний. Блокує будь-який тест деплою.

Статичний SDL `deploy/akash/deploy.yaml` (та шаблон `deploy.yaml.tpl`) містить `REQUIRED_SECRET_NOT_SET` плейсхолдери. Список секретів розширено для повного дзеркала Kamal `config/deploy.yml` (`env.secret`), щоб уникнути паралітичних відмов після першого деплою.

#### Категорія A — 🛑 Boot-critical (Puma crash до accept loop)

| ENV | Файл-guard | Поведінка без значення |
|-----|-----------|------------------------|
| `RAILS_MASTER_KEY` | `config/credentials.yml.enc` | Rails refuses to load credentials |
| `DATABASE_URL` | `config/database.yml` | `ActiveRecord::AdapterNotSpecified` |
| `CLOUD_SQL_INSTANCE_CONNECTION_NAME` | `bin/docker-entrypoint` | Cloud SQL Auth Proxy не стартує → `127.0.0.1:5432` недоступний |
| `GCP_SA_KEY_BASE64` | `bin/docker-entrypoint` | Auth Proxy не може автентифікуватися до Google Cloud API |
| `REDIS_URL` | `config/initializers/sidekiq.rb` | Sidekiq client не підключиться |
| `KREDIS_REDIS_URL` | `config/initializers/kredis.rb` | Distributed locks не працюють |
| `PROVISIONING_MASTER_KEY` | `config/initializers/master_key_strength_check.rb:33-37` | **`SecurityError` у `after_initialize` → Puma crash до accept loop** |

#### Категорія B — Web3 worker DeadSet (всі Sidekiq-воркери `web3_critical`)

Без цих ENV `ENV.fetch` raises `KeyError` при першому виконанні воркера. Sidekiq перекидає job у DeadSet після retry exhaustion → жоден SCC не мінтиться, жоден slashing не виконується, weekly L1 anchor падає.

| ENV | Сервіс / Worker | Поведінка |
|-----|-----------------|-----------|
| `ORACLE_PRIVATE_KEY` | `Celo::CommunityRewardService`, `Toucan::BridgeService`, `Klima::RetirementService`, `Etherisc::ClaimService`, `PuroEarth::PassportService`, fallback для minter/slasher | `KeyError` при першому виклику |
| `ORACLE_MINTER_PRIVATE_KEY` | `BlockchainMintingService:107` (MINTER_ROLE) | SCC/SFC mint неможливий |
| `ORACLE_SLASHER_PRIVATE_KEY` | `BlockchainBurningService:58` (SLASHER_ROLE) | Slashing зривається |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | `Ethereum::StateAnchorService:147` | Weekly state-root anchor падає |
| `ALCHEMY_POLYGON_RPC_URL` | `Web3::RpcConnectionPool.client_for` | Усі Polygon-операції недоступні |
| `ALCHEMY_ETHEREUM_RPC_URL` | `Ethereum::StateAnchorService:146` | L1 anchor TX зривається |
| `SOLANA_RPC_URL` | `Solana::MintingService:112` | Defaults to devnet — не критично, але неправильна мережа |
| `SOLANA_WALLET_KEYPAIR` | `Solana::MintingService:116` | `nil`-check невдалий |
| `SOLANA_FEE_PAYER_PUBKEY` | `Solana::MintingService:119` | Raises `🛑 [Solana] SOLANA_FEE_PAYER_PUBKEY is required` |
| `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` | `Solana::MintingService:125` | Raises explicit error |
| `SOLANA_USDC_MINT_ADDRESS` | `Solana::MintingService:127` | Raises explicit error |
| `CHAINLINK_FUNCTIONS_ROUTER` | `Chainlink::OracleDispatchService:67` | Fallback на stub (або raise у `WEB3_STRICT_MODE`) |
| `CHAINLINK_SUBSCRIPTION_ID` | `Chainlink::OracleDispatchService:68` | Те саме |
| `CHAINLINK_DON_ID` | `Chainlink::OracleDispatchService:95` | Raises `DispatchError` для on-chain dispatch |
| `CHAINLINK_HMAC_SECRET` | `Api::V1::OracleCallbacksController` | Підпис callback не перевіряється |

#### Категорія C — Observability (silent failures)

| ENV | Файл | Поведінка без значення |
|-----|------|------------------------|
| `SENTRY_DSN` | `config/initializers/sentry.rb:15` | Sentry inert → production errors невидимі |

> **Чому критично:** Akash provider реструктує контейнер у нескінченному hot loop при boot-crash. Це означає що навіть найменша помилка у Категорії A зробить deployment **постійно недоступним** при тому що ескроу AKT продовжує згорати. Категорія B веде до «тихої» поломки Proof of Growth pipeline — Rails запускається, телеметрія приймається, але токени ніколи не мінтяться.

#### ⚠️ Akash ENV plaintext exposure — security note

Akash Network **не шифрує** ENV-блок SDL на стороні провайдера. Зміст `services.web.env` зберігається у форматі, аналогічному Kubernetes ConfigMap, і доступний:
- через `akash provider lease-logs` адміністратору провайдера,
- через kubectl/k9s, якщо провайдер скомпрометований,
- у самому SDL-маніфесті, який Terraform рендерить у `terraform/akash/generated-deploy.yaml` (`file_permission = "0600"`, але існує на диску деплоєра).

Це **слабша гарантія**, ніж у GCP Secret Manager (HSM-backed) або Kamal `.kamal/secrets` (тільки на машинах деплоєра, не на серверах).

**Mitigation (TRL 6-7, поточний пріоритет):**
1. **Scoped on-chain roles:** Akash-deployment ORACLE keys повинні мати **тільки** `MINTER_ROLE`/`SLASHER_ROLE` на SCC/SFC контрактах — **ніколи** `DEFAULT_ADMIN_ROLE`. Це обмежує blast radius при витоку до конкретної операції (mint/burn), без можливості змінити contract owner або вкрасти treasury.
2. **Key rotation:** 90-денний цикл ротації через Terraform pipeline. Старі ключі revoke-ються на контрактах (revoke role).
3. **Окремі гаманці per chain:** `ETHEREUM_ANCHOR_PRIVATE_KEY` ≠ `ORACLE_PRIVATE_KEY` (вже зроблено через B-02 split).
4. **Audited Akash providers only:** `signedBy.anyOf` обмежує deployment до провайдерів, перевірених Akash community auditor — зменшує ризик зловмисного провайдера.

**Mitigation (TRL 8+, deferred):**
- Vault/Doppler sidecar агент, який тягне секрети у runtime memory без появи у SDL ENV (потрібен окремий identity для Akash → Vault auth).
- Hardware Security Module (HSM) для підпису транзакцій без експорту приватного ключа (наприклад, через AWS KMS asymmetric keys або Fireblocks API).

Cross-ref: [`06_04 §2.1`](06_04_Secrets_Checklist) — повний список секретів, [`06_01`](06_01_Deployment_Kamal_Terraform) — eqv. Boot-time guard rationale для Kamal.

> **⚠️ Security Exception — GCP_SA_KEY_BASE64 (Akash-only):** На TRL 5-6 Akash-вузли автентифікуються до Cloud SQL Auth Proxy довгоживучим Service Account JSON ключем у форматі `GCP_SA_KEY_BASE64`. Це **архітектурний виняток** з принципу **Workload Identity Federation** (WIF — короткоживучі OIDC-токени замість довгоживучих SA-ключів), за яким GCP-сервіси не повинні тримати статичні JSON-ключі. Akash як зовнішній провайдер не має доступу до GCE метаданих та не може напряму використовувати WIF без додаткового OIDC provider'а. **Mitigation:** SA з якого згенеровано ключ має **тільки** роль `roles/cloudsql.client` (нічого більше — ні Storage, ні Secret Manager), key rotation кожні 90 днів через Terraform pipeline. На TRL 7+ розглянути міграцію на WIF через зовнішній OIDC provider (наприклад, GitHub Actions як trust anchor для Akash deployment manifests). Cross-ref: [`06_04 §3.1/§4`](06_04_Secrets_Checklist) — `GCP_SA_KEY_BASE64` / `gcp_sa_key_base64` (scoped `roles/cloudsql.client`).

**Варіанти вирішення:**
1. **Рекомендовано:** Terraform-шаблон `deploy.yaml.tpl` через `terraform/akash/` — секрети підставляються з `terraform.tfvars` (в `.gitignore`).
2. Akash Console UI — ручне введення ENV змінних через веб-інтерфейс перед деплоєм.

#### `ALLOY_CONFIG_BASE64` — кодування для manual SDL deploy [INF.7]

При Terraform-деплої `ALLOY_CONFIG_BASE64` генерується автоматично через `filebase64("../../deploy/akash/config.alloy")` у `terraform/akash/main.tf` — **не використовуйте скрипт нижче для Terraform-флоу**.

При **manual deploy** (Akash Console UI або `akash tx deployment create` без Terraform) використовуйте helper-скрипт `deploy/akash/encode-alloy-config.sh`:

```bash
# Друк base64-значення у stdout (paste-ready, без trailing newline)
./deploy/akash/encode-alloy-config.sh

# Тільки sanity-перевірка (без друку секрету в stdout)
./deploy/akash/encode-alloy-config.sh --check
# ✅ deploy/akash/config.alloy: 2096 bytes → 2796 base64 chars (single line, round-trip OK)

# Кастомний шлях до Alloy config
ALLOY_CONFIG=path/to/custom.alloy ./deploy/akash/encode-alloy-config.sh
```

**Що скрипт гарантує (і чому це важливо):**

1. **Single-line output** — `base64` без `-w 0` на GNU coreutils переносить рядки на 76-у колонку. Перенесення зламає `echo $ALLOY_CONFIG_BASE64 | base64 -d` у `services.alloy.args` (shell інтерпретує newline як кінець значення → отримаємо truncated config + Alloy crash з парс-помилкою River-формату).
2. **Кросплатформова сумісність** — детектує BSD/macOS `base64` (немає `-w`) і застосовує `| tr -d '\n'`.
3. **Round-trip verification** — декодує результат назад і порівнює з джерелом байт-в-байт. Ловить CRLF / BOM / append-byte помилки до того як вони потраплять у Akash deployment.

**Куди вставляти результат:**

```yaml
# deploy/akash/deploy.yaml — services.alloy.env
- ALLOY_CONFIG_BASE64=Ly8gPT09PT09PT09PT09PT0...   # ← вставити вивід скрипта (одним рядком)
```

> ⚠️ **Не комітьте заповнений `deploy.yaml`** — це не секрет, але змішує конфіг із data, що ускладнює diff. Якщо часто деплоїте manually, зберігайте заповнений файл як `deploy/akash/deploy.local.yaml` (у `.gitignore`).

**Перевірка після деплою:**

```bash
# Через akash provider lease-logs — знайти стартовий лог Alloy
akash provider lease-logs --service alloy ...
# Очікуємо: "level=info msg=\"server listening\" addr=0.0.0.0:12345"
# При помилці декодування Alloy впаде з: "could not parse config file"
```

---

### TLS термінація не конфігурована

**Статус:** Середній. Порт `443` вже оголошений у SDL — потрібна конфігурація Akash ingress або Cloudflare для TLS термінації.

SDL визначає порти `80`, `443` та `5683`. Порт `443` присутній у `services.web.expose`, проте TLS термінація не підключена:
- **Akash ingress:** надає `*.ingress.akash.pub` субдомени з автоматичним Let's Encrypt — потрібно додати `accept: [*.ingress.akash.pub]` в placement або використати Akash hostname operator.
- **Cloudflare Proxy:** зовнішній варіант — Cloudflare термінує TLS перед Ingress Anchor.

- **Вплив:** Rails API та Hotwire/Turbo WebSocket доступні по HTTP. Браузери блокують WebSocket з'єднання на незахищеному `ws://`.
- **Де в коді:** `deploy/akash/deploy.yaml` → `services.web.expose` — порт `443` є, `accept`-домен не вказаний.
- **Потрібно:** Або налаштувати Akash hostname operator (ingress), або проксіювати через Cloudflare (Ingress Anchor → HTTPS).

#### Runbook: TLS Termination Strategy [INF.4]

> **Архітектурне рішення (рекомендоване):** **Cloudflare Proxy для HTTPS + direct UDP для CoAP**. Cloudflare DOES NOT proxy UDP у безкоштовному/Pro тарифах — для CoAP/UDP:5683 потрібен **окремий шлях через Ingress Anchor (статичний GCP IP)**, який і так уже існує в архітектурі. Akash hostname operator + Let's Encrypt — fallback варіант, якщо Cloudflare недоступний для проекту (санкції, gov-policy).
>
> Cross-ref: 00_07 INF.4 (P1), INF.6 (CoAP Proxy verification).

##### Опція A (рекомендована): Cloudflare Proxy для HTTPS + Direct UDP для CoAP

**Архітектура:**
```
Browser / API client                Queen Gateway (LoRa→CoAP)
        │                                   │
        ▼ HTTPS :443 (Cloudflare termin.)   ▼ CoAP/UDP :5683 (NO TLS)
┌───────────────────────────────┐    ┌───────────────────────────────┐
│ Cloudflare Edge (Proxy ON,    │    │ Ingress Anchor (e2-micro,     │
│ TLS termination, DDoS/WAF)    │    │ статичний GCP IP, HAProxy)    │
└────────┬──────────────────────┘    └──────────┬────────────────────┘
         │ HTTPS / Cloudflare Tunnel*           │ UDP forward
         │ (origin: Akash deployment)           │
         ▼                                      ▼
                  ┌─────────────────────────────────┐
                  │  Akash Provider                 │
                  │  web :80 (Rails)  :5683 (CoAP)  │
                  └─────────────────────────────────┘
```
\* Origin: або (a) `*.ingress.akash.pub` як CF origin (Akash сам видає http URL), або (b) Cloudflare Tunnel `cloudflared` як sidecar.

**Pre-flight checklist (👤 admin):**

- [ ] **Cloudflare account** з активним Pro/Business планом (для proxied CNAME + WAF rules).
- [ ] **Домен у Cloudflare** (DNS-only або full proxy режим — для silken net має бути `silkennet.app` або обраний продакшн-домен).
- [ ] **SSL/TLS режим**: `Full (strict)` — Cloudflare→origin вимагає валідного сертифіката на Akash. Якщо origin це `*.ingress.akash.pub`, Akash provider автоматично надає Let's Encrypt → strict mode OK.
- [ ] **Origin URL відомий:** після `akash provider lease-status`, скопіювати URL виду `https://<lease-id>.ingress.akash.pub`.
- [ ] **CNAME-запис створено:** `silkennet.app` (або subdomain) → `<lease-id>.ingress.akash.pub`, Proxy status: 🟠 **Proxied** (через CF).
- [ ] **Ingress Anchor running:** `gcloud compute instances list --filter="name=ingress-anchor"` повертає running. Статичний IP закріплено (`gcloud compute addresses list`).
- [ ] **Queens сконфігуровані** на `<INGRESS_ANCHOR_IP>:5683` (не на Cloudflare!) у firmware `QUEEN_BACKEND_HOST` або downlink config block.
- [ ] **Rails-side ENVs** не вимикати: `force_ssl=true`, `assume_ssl=true`, `HSTS` активні. CF додає `X-Forwarded-Proto: https`, Rails з `assume_ssl` чесно це поважає.
- [ ] **`DISABLE_SSL` ENV не встановлений** у `deploy/akash/deploy.yaml` (інакше Rails сам не форсуватиме HTTPS — false sense of security).

**Verification commands (виконати після deploy):**

```bash
# 1. TLS handshake через Cloudflare → перевірити SNI, ALPN, версію TLS
openssl s_client -connect silkennet.app:443 -servername silkennet.app -alpn h2,http/1.1 -brief </dev/null
# Очікуємо: "Protocol  : TLSv1.3", "Cipher    : TLS_AES_256_GCM_SHA384", "ALPN protocol: h2"

# 2. HSTS header + Cloudflare присутній + Rails redirect HTTP→HTTPS
curl -sI https://silkennet.app/up | head -15
# Очікуємо: HTTP/2 200, strict-transport-security: max-age=…, server: cloudflare,
#           cf-ray: <id>, x-frame-options: SAMEORIGIN

# 3. HTTP має бути redirected на HTTPS (Rails force_ssl)
curl -sI http://silkennet.app/up | head -5
# Очікуємо: HTTP/1.1 301 Moved Permanently або 308, location: https://silkennet.app/up

# 4. Cloudflare proxy ACTIVE (cf-ray header має бути)
curl -sI https://silkennet.app/ | grep -i "cf-ray\|server"
# Очікуємо обидва: server: cloudflare + cf-ray header

# 5. Origin server вже НЕ доступний напряму по HTTP (security perimeter)
# Знайти origin: dig +short silkennet.app, потім перевірити що direct hit blocked WAF/IP rules
# або повертає Cloudflare 403

# 6. WebSocket / Turbo Stream підключення (важливо для Hotwire)
# Браузер DevTools → Network → WS → ws://… → має бути wss://
# Або через cli:
curl -sI -H "Upgrade: websocket" -H "Connection: Upgrade" \
  -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
  -H "Sec-WebSocket-Version: 13" \
  https://silkennet.app/cable
# Очікуємо: HTTP/2 101 Switching Protocols (або 426 з deeper handshake)

# 7. CoAP UDP — ОКРЕМИЙ шлях. Cloudflare НЕ задіяний. Тестуємо direct UDP до Ingress Anchor:
INGRESS_IP=$(gcloud compute addresses describe ingress-anchor-ip --region europe-west1 --format='value(address)')
nc -u -w2 $INGRESS_IP 5683 < /dev/null && echo "UDP reachable" || echo "UDP blocked"
# Або через coap-client (libcoap-tools):
coap-client -m get coap://$INGRESS_IP:5683/health -v 6
# Очікуємо: 2.05 Content або response від Rails CoAP daemon

# 8. SSL Labs grade (виконати один раз після deploy)
# https://www.ssllabs.com/ssltest/analyze.html?d=silkennet.app
# Очікуємо: A або A+ (HSTS + TLS 1.3 + secure ciphers Cloudflare = grade A+)
```

**Failure modes та діагностика:**

| Симптом | Ймовірна причина | Виправлення |
|---------|------------------|-------------|
| `curl https://… → 525 SSL handshake failed` | Cloudflare→origin не може встановити TLS | Перевірити Akash `*.ingress.akash.pub` URL валідний (`akash provider lease-status`); CF SSL/TLS режим знизити до `Full` (без strict) на час діагностики |
| `301 → http://...` нескінченний loop | Rails бачить `X-Forwarded-Proto: http`, hot-redirect-loop | Перевірити CF Page Rules — має бути `Always Use HTTPS`. У Rails — `config.force_ssl = true`, `config.ssl_options = { redirect: { exclude: ->(req) { req.path == "/up" } } }` для health-check |
| WebSocket падає одразу | Hotwire/ActionCable через CF Free плану лімітується | Upgrade до CF Pro (WebSocket unlimited) АБО використати Cloudflare Tunnel з sticky origin |
| CoAP запити від Queen не доходять | Queen прошитий на CF домен замість Ingress Anchor IP | OTA flash оновити `QUEEN_BACKEND_HOST` через `CMD_SET_BACKEND` downlink config block |
| TLS grade B-C на SSL Labs | CF SSL/TLS режим = `Flexible` (CF→origin по HTTP) | Перемкнути на `Full (strict)`; примусово вимкнути TLS 1.0/1.1 в CF Edge Certificates |

##### Опція B (fallback): Akash hostname operator + Let's Encrypt

Якщо Cloudflare недоступний для проекту:

**Pre-flight checklist (👤 admin):**

- [ ] DNS-запис `silkennet.app A <PROVIDER_IP>` створено у власному DNS (Route53 / Namecheap / etc.).
- [ ] У `deploy/akash/deploy.yaml` додати `accept` секцію в expose:443:
  ```yaml
  - port: 443
    as: 443
    accept:
      - silkennet.app
    to:
      - global: true
  ```
- [ ] Provider у placement має `attributes.host: akash` (більшість public provider'ів підтримують hostname operator).
- [ ] Перевірити TLS-сертифікат після провіжна (Akash auto-issues Let's Encrypt через ~5 хв):
  ```bash
  openssl s_client -connect silkennet.app:443 -servername silkennet.app -brief </dev/null
  # Очікуємо: subject=CN = silkennet.app, issuer=CN = R3 (Let's Encrypt)
  ```
- [ ] CoAP UDP по тому ж домену **не пройде** через Akash hostname operator (тільки TCP/HTTP) — для UDP завжди потрібен Ingress Anchor.

##### Automation note (🤖 чекбокс)

Якщо обрана Опція B — додати `terraform/akash/hostname-operator.tf` з automation для `accept`-домену у SDL template (`deploy.yaml.tpl`). Для Опції A automation не потрібна — Cloudflare DNS налаштовується вручну один раз. Поточний deploy template (`deploy.yaml.tpl`) НЕ містить hostname operator block — це OK, бо Опція A рекомендована.

##### Cross-ref

- [`00_07` — INF.4](00_07_Action_Plan_Tracker) — оригінальна задача.
- [`00_07` — INF.6](00_07_Action_Plan_Tracker) — CoAP Proxy verification (Ingress Anchor лежить у тій же площині, бо CoAP UDP не йде через Cloudflare).
- [`06_01`](06_01_Deployment_Kamal_Terraform) — Ingress Anchor (e2-micro, статичний IP, HAProxy).
- [`06_04`](06_04_Secrets_Checklist) — `DISABLE_SSL` ENV (небезпечний override; canonical secrets-home + [`06_01`](06_01_Deployment_Kamal_Terraform) env-table).

---

### GCS bucket для Terraform State — потрібно створити вручну

**Статус:** Середній. Chicken-and-egg проблема.

`terraform/akash/main.tf` використовує GCS backend:
```hcl
backend "gcs" {
  bucket = "silken-net-terraform-state"
  prefix = "terraform/akash"
}
```

Цей bucket має існувати **до** першого `terraform init`. Terraform не може його створити автоматично. Деталі вирішення — в [`06_01`](06_01_Deployment_Kamal_Terraform) (Quickstart, Крок 1 — `terraform/bootstrap.sh`).

---

### Akash не має офіційного Terraform provider

**Статус:** Середній. Архітектурне обмеження.

На відміну від GCP (`hashicorp/google`), Akash Network **не має офіційного Terraform provider**. Поточне рішення у `terraform/akash/main.tf` використовує `null_resource` з `local-exec` provisioner, що обгортає Akash CLI команди:

```hcl
resource "null_resource" "akash_deployment" {
  provisioner "local-exec" {
    command = "akash tx deployment create ..."
  }
}
```

**Наслідки:**
- `terraform plan` не показує Akash-ресурси (лише `null_resource`).
- Стан деплою зберігається у локальному файлі `akash-dseq.txt`, а не в Terraform state.
- Потребує встановленого `akash` CLI на машині, де запускається Terraform.
- `terraform destroy` — закриває деплой через `akash tx deployment close`.

---

### 🟢 INFO: Відсутній офіційний Akash auditor address — потрібна актуалізація

**Статус:** Інформаційний.

SDL вказує auditor address `akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24`. Актуальний список аудиторів потрібно перевіряти на:
[https://github.com/akash-network/community/blob/main/sig-providers/auditors.md](https://github.com/akash-network/community/blob/main/sig-providers/auditors.md)

---

## 1. SDL Маніфест — Розбір "Як Є"

**Файл:** `deploy/akash/deploy.yaml`  
**Версія SDL:** `2.0`  
**Метод деплою:** Akash CLI або Terraform (`null_resource` provisioner)

SDL (Stack Definition Language) — це декларативний формат конфігурації Akash Network, аналог `docker-compose.yml` або Kubernetes маніфесту, але для децентралізованого хмарного маркетплейсу.

```
deploy/akash/
├── deploy.yaml        ← Статичний SDL (для ручного деплою через akash CLI або Akash Console)
├── deploy.yaml.tpl    ← Шаблон SDL для Terraform (секрети підставляються з terraform.tfvars)
└── config.alloy       ← Grafana Alloy конфігурація (River format, кодується в Base64 для SDL)
```

---

### 1.1 Сервіс (Service Definition)

```yaml
services:
  web:
    image: ghcr.io/alexey-lukin/silken_net:latest
```

| Параметр | Значення | Відповідність Kamal |
|----------|---------|---------------------|
| **Назва сервісу** | `web` | `config/deploy.yml` → `servers.web` |
| **Docker образ** | `ghcr.io/alexey-lukin/silken_net:latest` | GHCR дзеркало, автоматично синхронізується `.github/workflows/mirror-ghcr.yml` |
| **Платформа** | `amd64` | `config/deploy.yml` → `builder.arch: amd64` |
| **Кількість реплік** | `1` | `config/deploy.yml` → `web_node_count = 1` |

> ✅ GHCR образ — публічний, доступний Akash-провайдерам без credentials. Дзеркалюється автоматично `.github/workflows/mirror-ghcr.yml`. Kamal паралельно пушить у GCP Artifact Registry для GCP деплою.

> **Ingress Anchor:** Важкі GCP web VM замінені легковажним `e2-micro` інстансом зі статичним IP. HAProxy/socat на Ingress Anchor перенаправляє трафік до Akash deployment. Queen шлюзи надсилають CoAP на цей статичний IP, який проксіює до Akash-контейнера.

---

### 1.2 Профіль Обчислень (Compute Profile)

**Розділ SDL:** `profiles.compute.web`

```yaml
profiles:
  compute:
    web:
      resources:
        cpu:
          units: 4
        memory:
          size: 8Gi
        storage:
          - size: 50Gi          # Ephemeral
          - name: data
            size: 10Gi          # Persistent
            attributes:
              persistent: true
              class: beta3
```

| Ресурс | Akash | GCP Production | Пояснення |
|--------|-------|---------------|-----------|
| **CPU** | 4 vCPU | 2 vCPU (n2-standard-2) | +2 vCPU для компенсації варіативності децентралізованих провайдерів |
| **RAM** | 8 GiB | 8 GB | Однаково |
| **Ephemeral Disk** | 50 GiB | 30 GB SSD | Більше — контейнер включає gems, assets, tmp |
| **Persistent Disk** | 10 GiB (`class: beta3`) | Docker volume `silken_net_storage` | Active Storage uploads + Rails logs |

**`class: beta3`** — клас персистентного зберігання Akash Network. Еквівалент SSD-блочного сховища. Перживає перезапуск контейнера на тому ж провайдері, але **не переноситься** при зміні провайдера.

---

### 1.3 Профіль Розміщення (Placement Profile)

**Розділ SDL:** `profiles.placement.silken-dcloud`

```yaml
profiles:
  placement:
    silken-dcloud:
      attributes:
        host: akash
      signedBy:
        anyOf:
          - akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24
      pricing:
        web:
          denom: uakt
          amount: 10000
```

| Параметр | Значення | Пояснення |
|----------|---------|-----------|
| **Назва placement** | `silken-dcloud` | Ідентифікатор стратегії розміщення |
| **Атрибут `host`** | `akash` | Фільтр провайдерів — тільки офіційні Akash вузли |
| **`signedBy.anyOf`** | `akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24` | Адреса аудитора — провайдери, перевірені Akash community |
| **Ціна** | `10000 uAKT / block` | Максимальна ціна за блок (~6 секунд). Провайдери пропонують меншу ціну — система обирає найдешевшого |
| **Валюта** | `uAKT` (micro-AKT) | 1 AKT = 1,000,000 uAKT |

**Розрахунок вартості:**

```
10,000 uAKT/block × 10 blocks/min × 60 min × 24 год × 30 днів
= 432,000,000,000 uAKT/місяць
= 432,000 AKT/місяць   ← ВЕРХНІЙ ЛІМІТ (providers bid lower)
```

> Реальна ціна від провайдерів зазвичай у 10-100x менша від встановленого ліміту. Актуальні ціни: [stats.akash.network](https://stats.akash.network/)

---

### 1.4 Мережева Архітектура (Exposed Ports)

**Розділ SDL:** `services.web.expose`

```yaml
expose:
  - port: 80
    as: 80
    to:
      - global: true

  - port: 443
    as: 443
    to:
      - global: true

  - port: 5683
    as: 5683
    proto: udp
    to:
      - global: true
```

| Порт | Протокол | Призначення | Відповідність Kamal |
|------|---------|-------------|---------------------|
| **80** | TCP (HTTP) | Rails API + Hotwire/Turbo (Thruster reverse proxy) | `boot.proxy.publish "80:80"` |
| **443** | TCP (HTTPS) | TLS-термінований трафік; TLS через Akash ingress або Cloudflare | `boot.proxy.publish "443:443"` |
| **5683** | UDP | CoAP — IoT телеметрія від Queen gateway (21-байтні бінарні пакети) | `boot.proxy.publish "5683:5683/udp"` |

> **Порт 443** оголошений у SDL. TLS термінація потребує налаштування Akash hostname operator або зовнішнього Cloudflare proxy — див. §TLS термінація (00_07 INF.4).

**Схема мережевого потоку (поточний стан):**

```
Soldier (STM32WLE5JC)
    │ LoRa 868 MHz (AES-128 зашифровані 21-байтні пакети, post-ARCH.42)
    ▼
Queen Gateway (STM32 + SIM7070G)
    │ CoAP/UDP → статичний IP Ingress Anchor :5683
    ▼
┌─────────────────────────────────────────┐
│  GCP Ingress Anchor (e2-micro)          │
│  Статичний IP, HAProxy/socat            │
│  CoAP/UDP :5683 → forward to Akash     │
│  HTTP :80 → forward to Akash           │
└─────────────┬───────────────────────────┘
              │ (forward)
              ▼
┌─────────────────────────────────────────┐
│  Akash Provider (децентралізований)     │
│  SilkenNet Container                    │
│  HTTP :80 (Rails 8.1 + Puma)            │
│  HTTPS :443 (TLS термінація — INF.4)      │
│  UDP :5683 (CoAP listener)              │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Cloud SQL Auth Proxy (in-container)│  │
│  │ 127.0.0.1:5432 → Cloud SQL     │    │
│  │ (HTTPS tunnel, no public IP)    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Grafana Alloy (alloy service)   │    │
│  │ scrapes web:80/metrics (15s)    │    │
│  │ remote_write → Grafana Cloud    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  REDIS_URL = rediss://upstash (TLS) ✅  │
│  DATABASE_URL = 127.0.0.1:5432    ✅    │
└─────────────────────────────────────────┘
                    │
                    │ remote_write (HTTPS)
                    ▼
┌─────────────────────────────────────────┐
│  Grafana Cloud (SaaS)                   │
│  Prometheus + Grafana + Alerting        │
└─────────────────────────────────────────┘
```

---

### 1.5 Персистентне Сховище (Persistent Storage)

**Розділ SDL:** `services.web.params.storage`

```yaml
params:
  storage:
    data:
      mount: /rails/storage
      readOnly: false
```

| Параметр | Значення | Відповідність Kamal |
|----------|---------|---------------------|
| **Назва тому** | `data` | `silken_net_storage` (Docker volume) |
| **Точка монтування** | `/rails/storage` | `config/deploy.yml` → `volumes: "silken_net_storage:/rails/storage"` |
| **Режим** | `readOnly: false` | Read-Write |
| **Призначення** | Active Storage uploads, Rails logs | Ті ж дані, що в Kamal Docker volume |

---

## 2. Змінні Середовища (Environment Variables)

**Розділ SDL:** `services.web.env` + `services.job.env`  
**Відповідність:** `config/deploy.yml` → `env.secret` + `env.clear`  
**Кількість:** ~30 ENV-змінних (мірор `.kamal/secrets`)

ENV-блоки `web` та `job` сервісів **дзеркалюють** один одного — Sidekiq у `job`-сервісі ходить через ті ж Rails initializers, які перевіряють boot-critical секрети. Колонка **«Required for»** показує, де змінна *критично* необхідна:
- **boot** — Rails не стартує без неї (Puma crash до accept loop).
- **web3-worker** — Sidekiq worker впаде у DeadSet при першому виконанні.
- **observability** — silent failure, продакшн працює, але без видимості.
- **runtime** — використовується у звичайних запитах.

### 2.1 Application core (boot)

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `PORT` | `80` | runtime | Порт Thruster |
| `RAILS_ENV` | `production` | boot | Rails environment |
| `RAILS_MASTER_KEY` | `REQUIRED_SECRET_NOT_SET` | **boot** | Ключ розшифровки `config/credentials.yml.enc` |
| `DATABASE_URL` | `REQUIRED_SECRET_NOT_SET` | **boot** | PostgreSQL URL → Cloud SQL Auth Proxy `127.0.0.1:5432` |
| `CLOUD_SQL_INSTANCE_CONNECTION_NAME` | `REQUIRED_SECRET_NOT_SET` | **boot** | Cloud SQL instance connection (`project:region:instance`) |
| `GCP_SA_KEY_BASE64` | `REQUIRED_SECRET_NOT_SET` | **boot** | Base64 SA JSON для Auth Proxy |
| `REDIS_URL` | `REQUIRED_SECRET_NOT_SET` | **boot** | Sidekiq + ActionCable (Upstash `rediss://`) |
| `KREDIS_REDIS_URL` | `REQUIRED_SECRET_NOT_SET` | **boot** | Distributed locks (DB 1) |
| `RACK_ATTACK_REDIS_URL` | — (auto-derive з `REDIS_URL` → `/2`) | runtime | Rate-limiting (опц.) |
| `RAILS_MAX_THREADS` | `3` | runtime | Puma threads/worker — узгоджено з `database.yml` pool |
| `WEB_CONCURRENCY` | `4` | runtime | Puma worker processes (web only) |

### 2.2 🛑 Boot-critical security guards

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `PROVISIONING_MASTER_KEY` | `REQUIRED_SECRET_NOT_SET` | **boot** | HKDF root key. `config/initializers/master_key_strength_check.rb` raises `SecurityError` у `after_initialize` → Puma crash. Generate: `SecureRandom.hex(32)` |

### 2.3 Observability

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `SENTRY_DSN` | `REQUIRED_SECRET_NOT_SET` | **observability** | Без неї Sentry inert → production errors невидимі |
| `RELEASE_VERSION` | `` (empty) | observability | Git SHA/release tag для Sentry grouping |
| `PROMETHEUS_AUTH_USER` | `REQUIRED_SECRET_NOT_SET` | observability | Basic Auth для `/metrics` (Alloy scrape) |
| `PROMETHEUS_AUTH_PASSWORD` | `REQUIRED_SECRET_NOT_SET` | observability | — |

### 2.4 Web3 oracle keys (dual-key split, B-02 resolved)

| Змінна | Значення в SDL | Required for | Сервіс |
|--------|---------------|-------------|--------|
| `ORACLE_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Legacy fallback (Celo/Toucan/Klima/PuroEarth/Etherisc) |
| `ORACLE_MINTER_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | `BlockchainMintingService:107` (MINTER_ROLE) |
| `ORACLE_SLASHER_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | `BlockchainBurningService:58` (SLASHER_ROLE) |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | `Ethereum::StateAnchorService:147` (окремий гаманець!) |

### 2.5 RPC endpoints (`Web3::RpcConnectionPool`)

| Змінна | Значення в SDL | Required for | Призначення |
|--------|---------------|-------------|-------------|
| `ALCHEMY_POLYGON_RPC_URL` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Усі SCC/SFC операції на Polygon |
| `ALCHEMY_ETHEREUM_RPC_URL` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Weekly L1 state-root anchor |
| `SOLANA_RPC_URL` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Solana мікро-винагороди |

### 2.6 Solana minting

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `SOLANA_WALLET_KEYPAIR` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | 64-byte hex keypair |
| `SOLANA_FEE_PAYER_PUBKEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Base58 fee payer |
| `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | USDC ATA |
| `SOLANA_USDC_MINT_ADDRESS` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Base58 mint (mainnet USDC) |

### 2.7 Chainlink Functions Router v1 (Proof of Growth — S6.2)

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `CHAINLINK_FUNCTIONS_ROUTER` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Router contract address |
| `CHAINLINK_SUBSCRIPTION_ID` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Functions subscription |
| `CHAINLINK_DON_ID` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | bytes32, наприклад `fun-polygon-mainnet-1` |
| `CHAINLINK_HMAC_SECRET` | `REQUIRED_SECRET_NOT_SET` | runtime (web) | Перевірка `X-Chainlink-Signature` у callback |
| `CHAINLINK_DATA_VERSION` | `1` | runtime | Functions API version |
| `CHAINLINK_CALLBACK_GAS_LIMIT` | `300000` | runtime | Gas limit для callback |

### 2.8 Security knobs (Rails hardening)

| Змінна | Значення | Required for | Опис |
|--------|---------|-------------|------|
| `RAILS_ALLOWED_HOSTS` | *(потрібно встановити)* | runtime ⚠️ | Comma-separated allowlist (DNS-rebinding захист) — напр. `api.silkennet.com,.silkennet.com` |
| `DISABLE_SSL` | *(не встановлювати)* | runtime | `true` лише якщо Akash ingress / Cloudflare термінує TLS |
| `CSP_ENFORCE` | *(не встановлювати)* | runtime | `true` після burn-in CSP report-only (1–2 тижні) |

**Terraform-шаблон додає змінні динамічно** (`deploy.yaml.tpl`):

```hcl
# terraform/akash/main.tf — рендеринг шаблону
resource "local_file" "akash_sdl" {
  content = templatefile("deploy/akash/deploy.yaml.tpl", {
    rails_master_key                    = var.rails_master_key    # sensitive = true
    database_url                        = var.database_url         # sensitive = true
    redis_url                           = var.redis_url            # sensitive = true
    cloud_sql_instance_connection_name  = var.cloud_sql_instance_connection_name  # sensitive = true
    gcp_sa_key_base64                   = var.gcp_sa_key_base64   # sensitive = true
    kredis_redis_url  = var.kredis_redis_url != "" ?
                        var.kredis_redis_url :
                        "${trimsuffix(var.redis_url, "/0")}/1"  # auto-derive DB 1
    # ...
  })
  file_permission = "0600"  # Захист файлу із секретами
}
```

> `kredis_redis_url` автоматично виводиться з `redis_url` (заміна `/0` на `/1`) якщо не вказано явно — це зручна поведінка для єдиного Redis instance.

---

## 3. Terraform Конфігурація

### 3.1 Структура файлів

```
terraform/akash/
├── main.tf                   # SDL rendering + null_resource Akash CLI provisioner
├── variables.tf              # 14 вхідних змінних (мережа, ресурси, ціна, секрети)
├── outputs.tf                # SDL path, SHA-256 hash, deployment notes
└── terraform.tfvars.example  # Приклад заповнення (для копіювання в terraform.tfvars)
```

**Окремий Terraform root module** — `terraform/akash/` є незалежним від основного `terraform/`. Причина: різні lifecycle та credentials:

```
silken-net-terraform-state/ (GCS bucket)
├── terraform/state    ← GCP інфраструктура (VPC, Cloud SQL, Redis, Compute)
└── terraform/akash    ← Akash deployment (SDL, DSEQ)
```

### 3.2 Змінні Terraform (variables.tf)

**Акаш мережа:**

| Змінна | За замовчуванням | Валідація | Опис |
|--------|-----------------|-----------|------|
| `akash_key_name` | — (обов'язкова) | — | Назва ключа в `akash keys list` |
| `akash_chain_id` | `akashnet-2` | — | Chain ID основної мережі Akash |
| `akash_node` | `https://rpc.akashnet.net:443` | — | RPC endpoint Akash ноди |
| `akash_auditor_address` | `akash1365yvmc4s7awdyj3n2sav7xfx76axy6czqt24` | — | Адреса аудитора для фільтрації провайдерів |

**Ресурси обчислень:**

| Змінна | За замовчуванням | Валідація | Опис |
|--------|-----------------|-----------|------|
| `web_cpu_units` | `4` | 1–32 | CPU units (1 unit = 1 vCPU) |
| `web_memory_size` | `"8Gi"` | — | Оперативна пам'ять |
| `web_storage_size` | `"50Gi"` | — | Ephemeral storage |
| `persistent_storage_size` | `"10Gi"` | — | Persistent storage (Active Storage) |

**Масштабування та ціна:**

| Змінна | За замовчуванням | Валідація | Опис |
|--------|-----------------|-----------|------|
| `web_replicas` | `1` | 1–10 | Кількість реплік сервісу |
| `web_concurrency` | `4` | — | Puma worker processes |
| `rails_max_threads` | `3` | 1–8 | Puma threads per worker (обмежено 8 — GVL thrashing) |
| `max_price_uakt` | `10000` | ≥100 | Максимальна ціна за блок у uAKT |

**Секрети (sensitive = true):**

> Усі секрети нижче передаються у `templatefile()` у `terraform/akash/main.tf` та рендеряться у `generated-deploy.yaml` (`file_permission = "0600"`). Mirror зі списку `env.secret` в `config/deploy.yml` (Kamal) — окрім `GCP_ARTIFACT_REGISTRY_KEY` (не потрібен для GHCR public image).

**Application core:**

| Змінна | Валідація |
|--------|-----------|
| `rails_master_key` | — |
| `database_url` | Must start with `postgres://` or `postgresql://` |
| `redis_url` | Must start with `redis://` or `rediss://` |
| `kredis_redis_url` | — (auto-derived if empty) |
| `cloud_sql_instance_connection_name` | Формат: `project:region:instance` |
| `gcp_sa_key_base64` | Base64-encoded GCP service account JSON key |

**🛑 Boot-critical (Puma crash без значення):**

| Змінна | Валідація |
|--------|-----------|
| `provisioning_master_key` | length ≥ 32 chars (recommend 64 hex = 256-bit). Generate: `ruby -e 'require "securerandom"; puts SecureRandom.hex(32)'` |

**Observability:**

| Змінна | Валідація |
|--------|-----------|
| `sentry_dsn` | Sentry DSN URL |
| `grafana_remote_write_token` | Grafana Cloud API token (metrics:write scope) |
| `prometheus_auth_password` | Basic Auth password для `/metrics` |

**Web3 oracle keys (dual-key split, B-02):**

| Змінна | Валідація |
|--------|-----------|
| `oracle_private_key` | Hex `0x…` (legacy fallback для Celo/Toucan/Klima/PuroEarth/Etherisc) |
| `oracle_minter_private_key` | Hex `0x…` (MINTER_ROLE на SCC/SFC) |
| `oracle_slasher_private_key` | Hex `0x…` (SLASHER_ROLE на SCC/SFC) |
| `ethereum_anchor_private_key` | Hex `0x…` (окремий wallet для L1 anchor — MUST differ from `oracle_private_key`) |

**RPC endpoints (Web3::RpcConnectionPool — ENV.fetch raises KeyError без значення):**

| Змінна | Валідація |
|--------|-----------|
| `alchemy_polygon_rpc_url` | HTTPS URL (sensitive — містить API key у path) |
| `alchemy_ethereum_rpc_url` | HTTPS URL |
| `solana_rpc_url` | HTTPS URL Solana JSON-RPC |

**Solana minting (Solana::MintingService raises explicit errors):**

| Змінна | Валідація |
|--------|-----------|
| `solana_wallet_keypair` | 64-byte hex keypair |
| `solana_fee_payer_pubkey` | Base58 pubkey |
| `solana_fee_payer_token_account` | Base58 USDC ATA |
| `solana_usdc_mint_address` | Base58 (mainnet: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`) |

**Chainlink Functions Router v1:**

| Змінна | Валідація |
|--------|-----------|
| `chainlink_functions_router` | Polygon contract address `0x…` |
| `chainlink_subscription_id` | Numeric subscription ID |
| `chainlink_don_id` | bytes32 (e.g. `fun-polygon-mainnet-1`) |
| `chainlink_hmac_secret` | HMAC-SHA256 secret для callback signature |

**Observability — Grafana Cloud (OBS.1):**

| Змінна | За замовчуванням | Sensitive | Опис |
|--------|-----------------|-----------|------|
| `grafana_remote_write_url` | — (обов'язкова) | ❌ | Grafana Cloud Prometheus remote_write URL |
| `grafana_remote_write_username` | — (обов'язкова) | ❌ | Grafana Cloud instance ID (числовий) |
| `grafana_remote_write_token` | — (обов'язкова) | ✅ | Grafana Cloud API token |
| `prometheus_auth_user` | — (обов'язкова) | ❌ | Basic Auth username для `/metrics` |
| `prometheus_auth_password` | — (обов'язкова) | ✅ | Basic Auth password для `/metrics` |

### 3.3 Lifecycle Provisioner

`terraform apply` викликає Akash CLI через `null_resource.local-exec`:

```
terraform apply
    │
    ├─► local_file.akash_sdl          (рендер SDL шаблону → generated-deploy.yaml, chmod 0600)
    │
    └─► null_resource.akash_deployment
            │
            ├─ IF akash-dseq.txt EXISTS:
            │    akash tx deployment update <SDL> --dseq <DSEQ> --fees 5000uakt
            │
            └─ IF akash-dseq.txt MISSING:
                 akash tx deployment create <SDL> --fees 5000uakt
                     │
                     └─► Отримати DSEQ з події akash.v1beta3.EventDeploymentCreated
                             └─► Зберегти DSEQ в akash-dseq.txt
```

`terraform destroy` → `akash tx deployment close --dseq <DSEQ>`

---

## 4. Процес Деплою (CLI Commands)

> ⚠️ **ЖОДНОГО РЕАЛЬНОГО ДЕПЛОЮ!** Цей розділ — виключно документація очікуваного процесу. Команди `akash tx deployment create` **не запускались**.

### 4.1 Через Terraform (рекомендовано)

```bash
# 0. Передумови
# - akash CLI встановлений: https://docs.akash.network/guides/cli
# - Гаманець Akash: akash keys add silken-deploy
# - Поповнити гаманець AKT токенами (мінімум ~5 AKT для ескроу)
# - GCS bucket існує: gs://silken-net-terraform-state (див. 06_01 Quickstart Крок 1, bootstrap.sh)

# 1. Налаштування ENV для Akash CLI
export AKASH_KEY_NAME=silken-deploy
export AKASH_KEYRING_BACKEND=os
export AKASH_ACCOUNT_ADDRESS=$(akash keys show silken-deploy -a)
export AKASH_NODE=https://rpc.akashnet.net:443
export AKASH_CHAIN_ID=akashnet-2

# 2. Підготовка Terraform
cd terraform/akash
cp terraform.tfvars.example terraform.tfvars
# Заповнити terraform.tfvars (НЕ комітити в git!)

# 3. Ініціалізація та деплой
terraform init
terraform plan
terraform apply

# 4. Прийняти бід від провайдера (після apply)
DSEQ=$(cat akash-dseq.txt)
akash query market bid list --owner $AKASH_ACCOUNT_ADDRESS --dseq $DSEQ
akash tx market lease create \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME \
  --fees 5000uakt

# 5. Відправити маніфест провайдеру
akash provider send-manifest generated-deploy.yaml \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME

# 6. Перевірити статус
akash provider lease-status \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME

# 7. Переглянути логи
akash provider lease-logs \
  --dseq $DSEQ \
  --provider <PROVIDER_ADDRESS> \
  --from $AKASH_KEY_NAME
```

### 4.2 Через Akash CLI (без Terraform)

```bash
# Відредагувати deploy/akash/deploy.yaml — замінити плейсхолдери
# (DANGER: ризик зберегти секрети в git)

akash tx deployment create deploy/akash/deploy.yaml \
  --from silken-deploy \
  --chain-id akashnet-2 \
  --fees 5000uakt \
  --gas auto \
  --yes

# Далі — аналогічно крокам 4-7 вище
```

### 4.3 Закриття деплою

```bash
# Через Terraform (рекомендовано)
cd terraform/akash && terraform destroy

# Через CLI
akash tx deployment close \
  --dseq $(cat terraform/akash/akash-dseq.txt) \
  --from silken-deploy \
  --fees 5000uakt
```

---

## 5. Порівняння: Akash vs GCP Production

| Параметр | GCP Production 🌲 | Akash ☁️ | Статус |
|----------|-------------------|----------|--------|
| **CPU** | 2 vCPU (n2-standard-2) | 4 vCPU | ✅ Більше для компенсації |
| **RAM** | 8 GB | 8 GiB | ✅ Однаково |
| **Ephemeral Disk** | 30 GB SSD | 50 GiB | ✅ Більше |
| **Persistent Disk** | Docker volume | 10 GiB (`beta3`) | ✅ Аналогічно |
| **Порт 80 (HTTP)** | ✅ | ✅ | ✅ |
| **Порт 443 (HTTPS)** | ✅ (Kamal proxy) | 🟡 В SDL, TLS термінація не конфігурована | 🟡 INF.4 |
| **Rails security headers** | ✅ `force_ssl`, HSTS, CSP, X-Frame: DENY, Permissions-Policy | ✅ (ті самі Rails initializers) | ✅ Однакова конфігурація |
| **Порт 5683 (CoAP/UDP)** | ✅ | ✅ (через Ingress Anchor) | ✅ |
| **Database** | Cloud SQL private IP | ✅ Cloud SQL Auth Proxy (in-container) | ✅ вирішено |
| **Redis** | Memorystore private | ✅ Upstash serverless Redis (TLS) | ✅ вирішено |
| **Sidekiq (job role)** | ✅ (Kamal `job` role) | ✅ (`job` сервіс в SDL) | ✅ вирішено |
| **ActionCable (multi-replica)** | Solid Cable (PostgreSQL) | ✅ Solid Cable (Cloud SQL) | ✅ вирішено |
| **Управління** | Kamal + Terraform GCP | Akash CLI + Terraform | ✅ |
| **Цінова модель** | Фіксована (GCP billing) | Аукціон (uAKT/block) | ✅ Потенційно дешевше |
| **Відмовостійкість** | GCP SLA + Shielded VM | Залежить від провайдера | 🟡 Без SLA гарантій |
| **Цензурна стійкість** | ❌ (Web2, GCP control) | ✅ (децентралізовано) | Мета архітектури |

---

## 6. Відповідність Kamal → Akash

Mapping між конфігурацією Kamal (`config/deploy.yml` + `.kamal/secrets`) та SDL (`deploy/akash/deploy.yaml` + `deploy/akash/deploy.yaml.tpl`). Список повністю синхронізовано — кожен запис у Kamal `env.secret` повинен мати відповідник у обох сервісах SDL (`web` + `job`).

### Структурні відповідники

| Kamal (config/deploy.yml) | Akash SDL (deploy/akash/deploy.yaml) |
|--------------------------|--------------------------------------|
| `servers.web` | `services.web` |
| `servers.job` (Sidekiq) | `services.job` (✅ виправлено) |
| `image` (Artifact Registry) | `services.web.image` (GHCR public) |
| `boot.proxy.publish "80:80"` | `expose[0]: port: 80, global: true` |
| `boot.proxy.publish "443:443"` | `expose[1]: port: 443, global: true` (🟡 INF.4: TLS термінація) |
| `boot.proxy.publish "5683:5683/udp"` | `expose[2]: port: 5683, proto: udp, global: true` |
| `env.clear RAILS_ENV=production` | `env: RAILS_ENV=production` |
| `env.clear WEB_CONCURRENCY=2` | `env: WEB_CONCURRENCY=4` (більше CPU на Akash) |
| `env.clear RAILS_MAX_THREADS=3` | `env: RAILS_MAX_THREADS=3` |
| `volumes: silken_net_storage:/rails/storage` | `params.storage.data.mount: /rails/storage` |
| `builder.arch: amd64` | `profiles.compute.web.resources.cpu.units: 4` |
| — | ✅ `alloy` сервіс (OBS.1 — Grafana Cloud sidecar) |
| `password: GCP_ARTIFACT_REGISTRY_KEY` | ❌ Не потрібен (GHCR public image) |

### Mapping `env.secret` → SDL `env:`

> **Принцип:** кожна змінна нижче повинна бути одночасно у `.kamal/secrets`, `config/deploy.yml env.secret`, `deploy/akash/deploy.yaml` (обидва сервіси), `deploy/akash/deploy.yaml.tpl` (обидва сервіси), `terraform/akash/variables.tf` (як `sensitive = true`), та `terraform/akash/main.tf` (у `templatefile()` map). Drift = boot crash або тиха відмова Web3 pipeline.

**Application core (boot):**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `RAILS_MASTER_KEY` | `RAILS_MASTER_KEY=${rails_master_key}` | `var.rails_master_key` |
| `DATABASE_URL` | `DATABASE_URL=${database_url}` | `var.database_url` |
| `REDIS_URL` | `REDIS_URL=${redis_url}` | `var.redis_url` |
| `KREDIS_REDIS_URL` | `KREDIS_REDIS_URL=${kredis_redis_url}` | `var.kredis_redis_url` (auto-derive) |
| — (Cloud SQL Auth Proxy) | `CLOUD_SQL_INSTANCE_CONNECTION_NAME=...` | `var.cloud_sql_instance_connection_name` |
| — (Cloud SQL Auth Proxy) | `GCP_SA_KEY_BASE64=...` | `var.gcp_sa_key_base64` |

**🛑 Boot-critical security guard:**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `PROVISIONING_MASTER_KEY` | `PROVISIONING_MASTER_KEY=${provisioning_master_key}` | `var.provisioning_master_key` |

**Observability:**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `SENTRY_DSN` | `SENTRY_DSN=${sentry_dsn}` | `var.sentry_dsn` |
| — | `PROMETHEUS_AUTH_USER=...` (web + alloy) | `var.prometheus_auth_user` |
| — | `PROMETHEUS_AUTH_PASSWORD=...` (web + alloy) | `var.prometheus_auth_password` |
| — | `GRAFANA_REMOTE_WRITE_*` (alloy only) | `var.grafana_remote_write_*` |

**Web3 oracle keys (dual-key split, B-02):**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `ORACLE_PRIVATE_KEY` | `ORACLE_PRIVATE_KEY=${oracle_private_key}` | `var.oracle_private_key` |
| `ORACLE_MINTER_PRIVATE_KEY` | `ORACLE_MINTER_PRIVATE_KEY=${oracle_minter_private_key}` | `var.oracle_minter_private_key` |
| `ORACLE_SLASHER_PRIVATE_KEY` | `ORACLE_SLASHER_PRIVATE_KEY=${oracle_slasher_private_key}` | `var.oracle_slasher_private_key` |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | `ETHEREUM_ANCHOR_PRIVATE_KEY=${ethereum_anchor_private_key}` | `var.ethereum_anchor_private_key` |

**RPC endpoints:**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `ALCHEMY_POLYGON_RPC_URL` | `ALCHEMY_POLYGON_RPC_URL=${alchemy_polygon_rpc_url}` | `var.alchemy_polygon_rpc_url` |
| `ALCHEMY_ETHEREUM_RPC_URL` | `ALCHEMY_ETHEREUM_RPC_URL=${alchemy_ethereum_rpc_url}` | `var.alchemy_ethereum_rpc_url` |
| `SOLANA_RPC_URL` | `SOLANA_RPC_URL=${solana_rpc_url}` | `var.solana_rpc_url` |

**Solana minting:**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `SOLANA_WALLET_KEYPAIR` | `SOLANA_WALLET_KEYPAIR=${solana_wallet_keypair}` | `var.solana_wallet_keypair` |
| `SOLANA_FEE_PAYER_PUBKEY` | `SOLANA_FEE_PAYER_PUBKEY=${solana_fee_payer_pubkey}` | `var.solana_fee_payer_pubkey` |
| `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` | `SOLANA_FEE_PAYER_TOKEN_ACCOUNT=${solana_fee_payer_token_account}` | `var.solana_fee_payer_token_account` |
| `SOLANA_USDC_MINT_ADDRESS` | `SOLANA_USDC_MINT_ADDRESS=${solana_usdc_mint_address}` | `var.solana_usdc_mint_address` |

**Chainlink Functions Router v1:**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `CHAINLINK_FUNCTIONS_ROUTER` | `CHAINLINK_FUNCTIONS_ROUTER=${chainlink_functions_router}` | `var.chainlink_functions_router` |
| `CHAINLINK_SUBSCRIPTION_ID` | `CHAINLINK_SUBSCRIPTION_ID=${chainlink_subscription_id}` | `var.chainlink_subscription_id` |
| `CHAINLINK_HMAC_SECRET` | `CHAINLINK_HMAC_SECRET=${chainlink_hmac_secret}` | `var.chainlink_hmac_secret` |
| `CHAINLINK_DON_ID` | `CHAINLINK_DON_ID=${chainlink_don_id}` | `var.chainlink_don_id` |

> **🔴 Drift guard:** при додаванні нового ENV у Kamal `env.secret` **ОБОВ'ЯЗКОВО** додати у всі 5 локацій вище. Інакше Akash deployment отримає boot crash (категорія A) або тиху Web3 відмову (категорія B). Див. також §Секрети SDL (категорії A/B/C) вище.

---

## 7. Інтеграція у Загальну Архітектуру Gaia 2.0

Akash Network займає рівень **L5 (Rails Backend)** в 8-рівневій архітектурі. З вирішенням мережевої ізоляції (DB + Redis connectivity) всі рівні L5–L8 тепер працюють на Akash:

```
L8  Ethereum L1          Weekly State Root          (EthereumAnchorWorker — ✅ запускається на Akash через Sidekiq job сервіс)
L7  Polygon + DeFi       SCC/SFC minting            (BlockchainMintingWorker — ✅ запускається на Akash через Sidekiq job сервіс)
L6  Verification          peaq DID, IoTeX ZK         (ZkProofVerificationWorker — ✅ запускається на Akash через Sidekiq job сервіс)
L5  Rails Backend         Rails 8.1 API ← [Akash]   (Puma HTTP + Sidekiq job сервіс)
L4  LoRa Network          Queen CoAP → Ingress Anchor → :5683 ← [Akash UDP port] ✅
L3  Firmware & Edge AI    STM32WLE5JC               (не залежить від Akash)
L2  Hardware Capsule      BQ25570, EDLC             (не залежить від Akash)
L1  Biophysics            Ti-6Al-4V EBFC            (не залежить від Akash)
```

**Висновок:** SDL визначає три сервіси: `web` (Rails API + CoAP), `job` (Sidekiq workers), та `alloy` (Grafana Alloy → Grafana Cloud). Cloud SQL Auth Proxy (in-container) забезпечує доступ до PostgreSQL через HTTPS тунель, Upstash serverless Redis (TLS) замінює GCP Memorystore. `job` сервіс використовує entrypoint (`/rails/bin/docker-entrypoint bundle exec sidekiq ...`) для запуску Cloud SQL Proxy і для Sidekiq. `alloy` сервіс скрейпить `/metrics` endpoint `web` сервісу кожні 15 секунд та пушить метрики у Grafana Cloud через remote_write — вирішуючи BLOCKER'и спостережуваності (06_03). Ingress Anchor (`e2-micro` зі статичним IP) проксіює CoAP-трафік від Queens до Akash. Multi-replica ActionCable працює без sticky sessions завдяки Solid Cable adapter — всі репліки `web` підключені до спільної Cloud SQL БД `silken_net_production_cable`, PostgreSQL `LISTEN/NOTIFY` забезпечує крос-реплікову доставку Turbo Stream broadcasts.

---

## 8. Дорожня Карта (Path to TRL 5 → 9)

| TRL | Що потрібно | Статус |
|-----|------------|--------|
| **TRL 5** ✅ | SDL-маніфест (`web` + `job` + `alloy`), DB+Redis connectivity, GHCR mirror | ✅ Всі передумови виконані |
| **TRL 5** ✅ | Вирішити мережеву ізоляцію (Cloud SQL + Redis) | ✅ Cloud SQL Auth Proxy + Upstash |
| **TRL 5** ✅ | Додати `job` сервіс в SDL для Sidekiq | ✅ виправлено |
| **TRL 5** ✅ | Замінити Docker образ на публічний реєстр (GHCR) | ✅ виправлено (`mirror-ghcr.yml`) |
| **TRL 6** 🎯 | Перший реальний деплой на Akash Mainnet + функціональне тестування CoAP | 🔴 00_07 S4.3 (секрети — заповнити `terraform.tfvars`) |
| **TRL 7** 🎯 | Налаштувати TLS через Akash ingress hostname operator або Cloudflare | 🟡 00_07 INF.4 (порт 443 у SDL, TLS не активована) |
| **TRL 7** 🎯 | GCS bucket для Terraform state | 🟡 00_07 S5.6 (створити вручну перед `terraform init`) |
| **TRL 8** | Production деплой з Grafana Cloud метриками + alerting | Потребує TRL 7 + GRAFANA_* secrets |
| **TRL 9** | Automated failover GCP ↔ Akash + повна CI/CD інтеграція | — |
