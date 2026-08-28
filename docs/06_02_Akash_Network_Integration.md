# 06_02: Akash Network Integration (Децентралізовані Обчислення)

## 🎯 Мета

Зафіксувати **фактичний стан** конфігурації Akash Network. Документ відповідає на три ключові питання:

1. Які **обчислювальні ресурси** (CPU, RAM, Disk) замовляються в Akash SDL?
2. Які **змінні середовища (ENV)** очікує отримати контейнер при деплої?
3. Які **архітектурні блокери** унеможливлюють повноцінне децентралізоване розгортання сьогодні?

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — SDL повністю конфігурований (`web` + `job` + `coap` + `alloy`), DB+Redis connectivity вирішені (Cloud SQL Auth Proxy + Upstash TLS), GHCR mirror активний; жоден реальний деплой на Akash Mainnet ще не проведений (TRL 6 — після першого успішного деплою).
- **Конфігуровано:** Cloud SQL Auth Proxy, Upstash Redis (TLS), Solid Cable (multi-replica ActionCable), GHCR mirror, Ingress Anchor, Rails security hardening (`force_ssl`/HSTS/CSP).
- **Відкрите:** SDL secrets, TLS термінація, GCS state bucket, перший Mainnet деплой → [`00_07`](00_07_Action_Plan_Tracker) (S4.3, INF.4, S5.6).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `deploy/akash/deploy.yaml` · `deploy.yaml.tpl` | SDL: `web` + `job` + `coap` + `alloy` сервіси |
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
- [7. Інтеграція у Загальну Архітектуру SilkenNet](#7-інтеграція-у-загальну-архітектуру-silkennet)
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
| `POSTGRES_HOST` / `POSTGRES_USER` / `POSTGRES_PASSWORD` | `config/database.yml` | `ActiveRecord::AdapterNotSpecified` (component style; host=`127.0.0.1` proxy + user `silken_net` non-secret, лише пароль секрет) |
| `CLOUD_SQL_INSTANCE_CONNECTION_NAME` | `bin/docker-entrypoint` | Cloud SQL Auth Proxy не стартує → entrypoint чекає 15 с → `exit 1` (fail-loud, INF.13; Rails не стартує замість мовчазного boot без БД) |
| `GCP_SA_KEY_BASE64` | `bin/docker-entrypoint` | Auth Proxy не може автентифікуватися до Google Cloud API |
| `REDIS_URL` | `config/initializers/sidekiq.rb` | Sidekiq client не підключиться |
| `PROVISIONING_MASTER_KEY` | `config/initializers/master_key_strength_check.rb` | **`SecurityError` у `after_initialize` → Puma crash до accept loop** |

> **[B1]** `KREDIS_REDIS_URL` свідомо **не** boot-critical і не в SDL — Kredis auto-derive DB 1 з `REDIS_URL` (`config/redis/shared.yml`); placeholder/порожній інжект був би truthy для `ENV.fetch` і перебив би derive. Інвентар секретів — [`06_04 §2.1`](06_04_Secrets_Checklist).

#### Категорія B — Web3 worker DeadSet (всі Sidekiq-воркери `web3_critical`)

Без цих ENV `ENV.fetch` raises `KeyError` при першому виконанні воркера. Sidekiq перекидає job у DeadSet після retry exhaustion → жоден SCC не мінтиться, жоден slashing не виконується, weekly L1 anchor падає.

| ENV | Сервіс / Worker | Поведінка |
|-----|-----------------|-----------|
| `ORACLE_CELO_PRIVATE_KEY` | `Celo::CommunityRewardService` (dedicated cUSD-підписант) — **[ARCH.50]** ізолює Celo blast-radius від Polygon-флоту | `KeyError` при першому виклику (fallback retired — INF.22) |
| `ORACLE_MINTER_PRIVATE_KEY` | `BlockchainMintingService` (MINTER_ROLE) | SCC/SFC mint неможливий |
| `ORACLE_SLASHER_PRIVATE_KEY` | `BlockchainBurningService` (SLASHER_ROLE) | Slashing зривається |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | `Ethereum::StateAnchorService` | Weekly state-root anchor падає |
| `ORACLE_ETHERISC_PRIVATE_KEY` · `ORACLE_PURO_PRIVATE_KEY` · `ORACLE_KLIMA_PRIVATE_KEY` | activation-gated aux-підписанти (`Etherisc::ClaimService` / `PuroEarth::PassportService` / `Klima::RetirementService`, Klima-воркер DEAD) — **НЕ в SDL/tfvars**: інжект через Console при активації шляху ([`06_04 §4`](06_04_Secrets_Checklist)) | `KeyError` при виклику неактивованого шляху — by design |

> **[INF.22] Легасі спільний `ORACLE_PRIVATE_KEY` — RETIRED.** Жоден код його не читає; `Security::Web3NetworkGuard` **відмовляє** значенню під цим ім'ям (zombie-config tripwire), а `scripts/deploy_secret_scan.rb` (Invariant B2) ловить його повернення в SDL на CI. Кожен підписант = свій dedicated-ключ (E.2).
| `ALCHEMY_POLYGON_RPC_URL` | `Web3::RpcConnectionPool.client_for` | Усі Polygon-операції недоступні |
| `ALCHEMY_ETHEREUM_RPC_URL` | `Ethereum::StateAnchorService` | L1 anchor TX зривається |
| `SOLANA_RPC_URL` | `Solana::MintingService` | Defaults to devnet — не критично, але неправильна мережа |
| `SOLANA_WALLET_KEYPAIR` | `Solana::MintingService` | `nil`-check невдалий |
| `SOLANA_FEE_PAYER_PUBKEY` | `Solana::MintingService` | Raises `🛑 [Solana] SOLANA_FEE_PAYER_PUBKEY is required` |
| `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` | `Solana::MintingService` | Raises explicit error |
| `SOLANA_USDC_MINT_ADDRESS` | `Solana::MintingService` | Raises explicit error |
| `CHAINLINK_HMAC_SECRET` | `Api::V1::OracleCallbacksController` | Підпис callback не перевіряється (dev/test); `WEB3_STRICT_MODE` → `SecurityError`. Dispatch-секрети (`ROUTER`/`SUBSCRIPTION_ID`/`DON_ID`) вилучено — ARCH.53 |

> **[ARCH.49] Per-address nonce-serialization.** eth-gem бере nonce per-call (`eth_getTransactionCount(pending)`), тож конкурентні підписи **на одній адресі** колізять nonce → orphan «sent-but-never-mined» tx. Кожен `transact` серіалізується через `Kredis.lock("lock:web3:oracle:#{addr}", expires_in: 30.seconds, after_timeout: :raise)`, ключований адресою підписанта. Після повного dedicated-спліту [INF.22] (спільна base-EOA retired) кожен сервіс має власну адресу → lock серіалізує лише конкуренцію **всередині** сервісу (два mint-батчі, два Etherisc-claims), а mint/slash/aux не контендять між собою (дзеркало ARCH.47-мети). Celo додатково має chain-prefixed lock (ARCH.50, історично — ізоляція від Polygon base ще до спліту). Klima той самий патерн, але DEAD (0 enqueue) → lock при активації; Toucan видалено повністю (E.66 prune, воскресає з git при E.20-go — тоді ж lock обов'язковий).

#### Категорія C — Observability (silent failures)

| ENV | Файл | Поведінка без значення |
|-----|------|------------------------|
| `SENTRY_DSN` | `config/initializers/sentry.rb` | Sentry inert → production errors невидимі |

> **Чому критично:** Akash provider реструктує контейнер у нескінченному hot loop при boot-crash. Це означає що навіть найменша помилка у Категорії A зробить deployment **постійно недоступним** при тому що ескроу AKT продовжує згорати. Категорія B веде до «тихої» поломки Proof of Growth pipeline — Rails запускається, телеметрія приймається, але токени ніколи не мінтяться.

#### ⚠️ Akash ENV plaintext exposure — security note

Akash Network **не шифрує** ENV-блок SDL на стороні провайдера. Зміст `services.web.env` зберігається у форматі, аналогічному Kubernetes ConfigMap, і доступний:
- через `akash provider lease-logs` адміністратору провайдера,
- через kubectl/k9s, якщо провайдер скомпрометований,
- у самому SDL-маніфесті, який Terraform рендерить у `terraform/akash/generated-deploy.yaml` (`file_permission = "0600"`, але існує на диску деплоєра).

Це **слабша гарантія**, ніж у GCP Secret Manager (HSM-backed) або Kamal `.kamal/secrets-common` (тільки на машинах деплоєра, не на серверах).

**Mitigation (TRL 6-7, поточний пріоритет):**
1. **Scoped on-chain roles:** Akash-deployment ORACLE keys повинні мати **тільки** `MINTER_ROLE`/`SLASHER_ROLE` на SCC/SFC контрактах — **ніколи** `DEFAULT_ADMIN_ROLE`. Це обмежує blast radius при витоку до конкретної операції (mint/burn), без можливості змінити contract owner або вкрасти treasury.
2. **Key rotation:** 90-денний цикл ротації через Terraform pipeline. Старі ключі revoke-ються на контрактах (revoke role).
3. **Окремі гаманці per signer:** повний dedicated-спліт [INF.22] — MINTER ⊥ SLASHER ⊥ CELO ⊥ ANCHOR ⊥ aux (Etherisc/Puro/Klima); легасі спільний ключ retired, guard-tripwire проти повернення.
4. **Audited Akash providers only:** `signedBy.anyOf` обмежує deployment до провайдерів, перевірених Akash community auditor — зменшує ризик зловмисного провайдера.

**Mitigation (TRL 8+, deferred):**
- Vault/Doppler sidecar агент, який тягне секрети у runtime memory без появи у SDL ENV (потрібен окремий identity для Akash → Vault auth).
- Hardware Security Module (HSM) для підпису транзакцій без експорту приватного ключа (наприклад, через AWS KMS asymmetric keys або Fireblocks API).

Cross-ref: [`06_04 §2.1`](06_04_Secrets_Checklist) — повний список секретів, [`06_01`](06_01_Deployment_Kamal_Terraform) — eqv. Boot-time guard rationale для Kamal.

> **⚠️ Security Exception — GCP_SA_KEY_BASE64 (Akash-only, runtime):** Akash-вузли автентифікуються до Cloud SQL Auth Proxy довгоживучим Service Account JSON ключем у форматі `GCP_SA_KEY_BASE64`. Це **архітектурний виняток** з принципу **Workload Identity Federation** (WIF — короткоживучі OIDC-токени замість статичних JSON-ключів): Akash як зовнішній провайдер не має доступу до GCE-метаданих і не досягає GitHub OIDC-issuer'а, тож не може напряму використати WIF. **CI→GCP плече вже мігровано на WIF** (INF.22, 2026-07-09: `terraform/wif.tf` + keyless auth у deploy/drift workflow, CI-secret `GCP_SA_KEY` вилучено), тож `GCP_SA_KEY_BASE64` лишається **ЄДИНИМ** довгоживучим SA-ключем у системі. **Mitigation:** SA має **тільки** роль `roles/cloudsql.client` (нічого більше — ні Storage, ні Secret Manager), key rotation кожні 90 днів через Terraform pipeline. Майбутнє: WIF і для Akash через зовнішній OIDC provider (GitHub Actions як trust anchor для Akash deployment manifests). Cross-ref: [`06_04 §3.1/§4`](06_04_Secrets_Checklist) — `GCP_SA_KEY_BASE64` / `gcp_sa_key_base64` (scoped `roles/cloudsql.client`).

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

> **Архітектурне рішення ✅ ОБРАНО (founder 2026-07-03): Опція A — Cloudflare Proxy для HTTPS + direct UDP для CoAP** (публічний домен `silkennet.app`). Cloudflare DOES NOT proxy UDP у безкоштовному/Pro тарифах — для CoAP/UDP:5683 потрібен **окремий шлях через Ingress Anchor (статичний GCP IP)**, який і так уже існує в архітектурі. Akash hostname operator + Let's Encrypt (домен `silkennet.com`) — fallback варіант, якщо Cloudflare недоступний для проекту (санкції, gov-policy).
>
> Cross-ref: 00_07 INF.4 (P1), INF.6 (CoAP Proxy verification).

##### Опція A (рекомендована): Cloudflare Proxy для HTTPS + Direct UDP для CoAP

**Архітектура:**
```
Browser / API client                Queen Gateway (LoRa→CoAP)
        │                                   │
        ▼ HTTPS :443 (Cloudflare termin.)   ▼ CoAP/UDP :5683 (NO TLS)
┌───────────────────────────────┐    ┌───────────────────────────────┐
│ Cloudflare Edge (Proxy ON,    │    │ Ingress Anchor (e2-small,     │
│ TLS termination, DDoS/WAF)    │    │ статичний IP, CoAP-демон      │
│                               │    │ PRIMARY тут — INF.17)         │
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
- [ ] **Queens бʼють у Ingress Anchor, не в Cloudflare:** firmware резолвить `COAP_SERVER_HOST` (`api.silkennet.com`, `firmware/queen/main.c` — CDNSGIP) → A-запис цього хоста МУСИТЬ бути **DNS-only (сіра хмарка), НЕ proxied**, і вказувати на статичний Ingress-IP. Fail-triggered re-resolve host-shipped [FW.58]: після N=3 flush-провалів підряд кеш інвалідується → A-запис-фліп підхоплюється без ребута (механізм — [`03_02 §4`](03_02_Queen_Gateway_Firmware); bench-verify на живому SIM7070 → [`00_07` FW.58](00_07_Action_Plan_Tracker)).
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
| CoAP запити від Queen не доходять | A-запис `api.silkennet.com` став CF-proxied (UDP крізь CF не проходить) АБО Королева тримає застарілий DNS-пін | Повернути запис у DNS-only → Ingress-IP; Королева підхопить сама після N=3 flush-провалів підряд (fail-triggered re-resolve [FW.58], [`03_02 §4`](03_02_Queen_Gateway_Firmware)) або post-reboot; bench-verify → [`00_07` FW.58](00_07_Action_Plan_Tracker) |
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

> ⚠️ **«Один раз» має виняток — re-lease.** CNAME-origin (`<lease-id>.ingress.akash.pub`) прив'язаний до Akash lease: новий deployment/провайдер (redeploy, multi-provider failover) = новий hostname = ручний CNAME-update у Cloudflare в найгарячіший момент (той самий клас, що `akash-deployment-ip` metadata Ingress Anchor — S1.5). Для першого деплою і стабільного lease — прийнятно руками; коли multi-provider failover стане живою практикою, CNAME-update автоматизувати (Cloudflare API-скрипт або cloudflare terraform-provider) як крок failover-runbook.

##### Cross-ref

- [`00_07` — INF.4](00_07_Action_Plan_Tracker) — оригінальна задача.
- [`00_07` — INF.6](00_07_Action_Plan_Tracker) — CoAP Proxy verification (Ingress Anchor лежить у тій же площині, бо CoAP UDP не йде через Cloudflare).
- [`06_01`](06_01_Deployment_Kamal_Terraform) — Ingress Anchor (e2-small, статичний IP: CoAP-демон PRIMARY + HAProxy 80/443).
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

**[SEC.22] той самий bootstrap латчить state-at-rest:** tf-state = повна plaintext-копія секретів terraform (третя, після Akash-ENV і `coap.env`) → скрипт створює CMEK-keyring `silken-tfstate-ew1` (той самий chicken-and-egg: ключ потрібен ДО `init`, тому gcloud out-of-band, не `kms.tf`), ставить default-CMEK + `--public-access-prevention` на bucket і ріже versioning-retention до 10 версій / 30 днів. Механіка/IAM-модель (GCS service-agent = крипто-принципал; deploy-SA без KMS-ролі) — [`06_04 §5.6`](06_04_Secrets_Checklist).

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

### 🟢 INFO: Akash community auditor address (виправлено — INF.24)

**Статус:** Інформаційний.

SDL пінить community-auditor `akash1365yvmc4s7awdyj3n2sav7xfx76adc6dnmlx63` (валідна bech32; попереднє значення `…axy6czqt24` було корумпованим 43-символьним рядком, що провалював checksum — INF.24). Джерело правди — [akash-audited-attributes](https://github.com/akash-network/docs/blob/master/providers/akash-audited-attributes.md); яку адресу реально підписують живі провайдери — звірити on-chain при деплої (`akash query audit`).

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

> ✅ GHCR образ — публічний, доступний Akash-провайдерам без credentials. Дзеркалюється автоматично `.github/workflows/mirror-ghcr.yml` (`Deploy · GHCR Mirror`) — несе **Sigstore-signed SLSA build-provenance** (keyless OIDC→Fulcio/Rekor) + BuildKit SBOM, тож недовірений Akash-провайдер (або будь-хто) може криптографічно верифікувати походження+вміст образу перед pull. Команда верифікації + деталі — `SECURITY.md` (§Verifying release artifacts). Kamal паралельно пушить у GCP Artifact Registry для GCP деплою.
>
> ⚠️ **`:latest` тут — приклад static-SDL, НЕ бойовий пін** ([`00_07` INF.21](00_07_Action_Plan_Tracker)): мутабельний тег перезаписується кожним push у main — рестарт/міграція lease підхопить інший образ без rollback-цілі. Реальний деплой рендериться з `.tpl` через tf-var `docker_image` — на render підставляється іммутабельний `sha-<commit>`/semver (обидва `tfvars.example` несуть приклад).

> **Ingress Anchor:** Важкі GCP web VM замінені `e2-small` інстансом зі статичним IP. Queen шлюзи надсилають CoAP на цей статичний IP, де його приймає **демон прямо на анкорі** (PRIMARY — INF.17, founder 2026-07-04: та сама VPC, що Cloud SQL → приватний IP без Auth Proxy, −1 хоп); HAProxy проксює лише HTTP/HTTPS 80/443 до Akash. Socat-релей → Akash `coap`-сервіс лишається задокументованим fallback'ом (перемикання — `systemctl stop coap-daemon && systemctl start coap-relay`).

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

| Ресурс | Akash (production) | GCP Kamal (fallback) | Пояснення |
|--------|-------|---------------|-----------|
| **CPU** | 4 vCPU | 2 vCPU | +2 vCPU для компенсації варіативності децентралізованих провайдерів |
| **RAM** | 8 GiB | 8 GB | Однаково |
| **Ephemeral Disk** | 50 GiB | 30 GB SSD | Більше — контейнер включає gems, assets, tmp |
| **Persistent Disk** | 10 GiB (`class: beta3`) | Docker volume `silken_net_storage` | Active Storage uploads + Rails logs |

> ⚠️ **Колонка «GCP» = Kamal-fallback, а НЕ провіжений хост** [DOC-T.50]. Після інфра-півоту `terraform/compute.tf` піднімає рівно **один** інстанс — Ingress Anchor **`e2-small` (2 GB)** під CoAP-демон + HAProxy; Rails web/job живуть на Akash (`config/deploy.yml` шапка). Числа GCP-колонки = розмір, який обирає оператор при fallback-деплої, не специфікація наявної машини.

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
          - akash1365yvmc4s7awdyj3n2sav7xfx76adc6dnmlx63
      pricing:
        web:
          denom: uakt
          amount: 10000
```

| Параметр | Значення | Пояснення |
|----------|---------|-----------|
| **Назва placement** | `silken-dcloud` | Ідентифікатор стратегії розміщення |
| **Атрибут `host`** | `akash` | Фільтр провайдерів — тільки офіційні Akash вузли |
| **`signedBy.anyOf`** | `akash1365yvmc4s7awdyj3n2sav7xfx76adc6dnmlx63` | Адреса аудитора — провайдери, перевірені Akash community |
| **Ціна** | `10000 uAKT / block` | Максимальна ціна за блок (~6 секунд). Провайдери пропонують меншу ціну — система обирає найдешевшого |
| **Валюта** | `uAKT` (micro-AKT) | 1 AKT = 1,000,000 uAKT |

**Розрахунок вартості:**

```
10,000 uAKT/block × 10 blocks/min × 60 min × 24 год × 30 днів
= 432,000,000,000 uAKT/місяць
= 432,000 AKT/місяць   ← ВЕРХНІЙ ЛІМІТ (providers bid lower)
```

> Реальна ціна від провайдерів зазвичай у 10-100x менша від встановленого ліміту. Актуальні ціни: [stats.akash.network](https://stats.akash.network/)

#### ⚠️ Географічне розміщення провайдера — residency-межа [SEC.19]

Placement вище фільтрує лише `host: akash` + `signedBy` (аудит-довіра). **Географічного фільтра свідомо немає за замовчуванням** — і це несе residency-нюанс, який треба розуміти до EU-онбордингу:

- **Data-at-rest** уже EU-пінований: Cloud SQL `europe-west1` + [`04_01`](04_01_Data_Models_and_Entities) `data_region`-шардинг (`eu-west`/`eu-central`) + PII-політики (SEC.18/ARCH.57).
- **Data-in-use** — ні: Rails-моноліт тримає User/Org-PII у пам'яті процесу, а Akash-lease може сісти на провайдера будь-де у світі.

**Важіль (off-by-default):** атрибут `region` у `placement.attributes`, керований tf-var `akash_region` (порожній → рядок омітиться; значення дзеркалять `data_region`, напр. `eu-west`). Активація звужує пул до провайдерів, що **заявили** цей регіон.

**Чесна межа — це НЕ residency-гарантія.** Akash криптопідписує (аудує) лише `host` / `tier` / `organization`; `region`/`datacenter` — **self-reported без governance** (звірено з [akash-network/docs](https://github.com/akash-network/docs/blob/master/providers/akash-audited-attributes.md)). Тому `signedBy` географію НЕ підкріплює: провайдер може заявити `eu-west`, а крутитися деінде. Фільтр лише **знижує випадкове не-EU-розміщення**, не гарантує його. Плюс over-tight `region` × audited-`signedBy` може звузити пул до нуля bid'ів → деплой без пропозицій (тому off-by-default).

**Справжній EU-residency-важіль для PII** = EU-пінований Ingress Anchor (GCP, data-in-use для coap/DB-шляху) + Cloud SQL at-rest — не Akash-тег. Akash несе цензуростійкі money/web за дизайном.

**✅ Рішення (founder 2026-07-10, → [`00_07`](00_07_Action_Plan_Tracker) SEC.19): м'яка EU-преференція АКТИВНА з першого render'а** — `akash_region = "eu-west"` розкоментовано в `terraform.tfvars.example`. Операційний фолбек: якщо render збирає **нуль bid'ів** (over-tight `region` × `signedBy`), закоментувати рядок і пере-render'ити — доступність важливіша за м'яку преференцію; повернути фільтр при ширшому пулі / EU-онбордингу (BIZ.3 / ARCH.57).

#### ⚠️ Art.28 processor-вимір — контрагент, а не географія [SEC.23]

🔴 **Це ІНША вісь, ніж residency-блок вище, і саме тому вона тут: SEC.19 ратифіковано, і це легко прочитати як «Akash-питання закрите».** Той блок відповідає на «**ДЕ** крутиться навантаження», цей — на «**З КИМ** укладено договір». Осі ортогональні: м'яка EU-преференція може спрацювати ідеально, а контрактної вимоги не задовольнити жодного разу.

**Механізм напруги.** GDPR Art.28 вимагає **названого, законтрактованого** processor'а з письмовим DPA. Akash — permissionless-маркетплейс: провайдери взаємозамінні, часто псевдонімні, і `signedBy` аудує **спроможність** (`host` / `tier` / `organization`), а не **ідентичність контрагента**. Тобто той самий факт, що робить платформу цензуростійкою (будь-хто може стати провайдером, lease переїжджає), структурно ламає вимогу «конкретний processor, з яким підписано». Це не пробіл у паперах — це властивість архітектури, і закривається вона архітектурним рішенням, не документом.

**Дві опції, обидві відкриті** (⚖️ [`00_07`](00_07_Action_Plan_Tracker) SEC.23, ДО першого live-деплою з EU-PII):
- **(а)** гео-фільтр Audited Attributes звужує пул до GDPR-адекватних провайдерів + прямий контракт із обраним;
- **(б)** PII-шар (Postgres / Redis / сесії / web-PII) лишається на GCP-анкорі, де DPA існує як click-accept, а Akash несе **лише non-personal** workload (CoAP-intake до прив'язки до User).

⚠️ **Друга нога того самого пункту — не Akash, а RPC:** `ALCHEMY_*_RPC_URL` (§2.5) означає, що зовнішній провайдер бачить **IP-адресу разом із адресою гаманця** на кожному виклику web3-воркерів. IP є персональними даними (CJEU *Breyer*), а зв'язка IP↔wallet створює новий ідентифікатор — тобто це недекларований субпроцесор, чий DPA-статус не верифіковано. Лік: верифікувати напряму → self-hosted node → або задокументований accept.

✅ **Вікно ще відкрите, і це несуче:** mainnet-розгортання не відбулось, тож рішення лишається архітектурним, а не ретроспективним. **⛔ Перелік субпроцесорів сюди НЕ копіюється** — його дім у concern-шарі ([`b2c_tos_privacy.md`](protocols/legal/b2c_tos_privacy.md) §D.3, повна матриця з регіонами, transfer-механізмами й DPA-статусом; ризик-оцінка — [`dpia_art35.md`](protocols/legal/dpia_art35.md) §R5), і дублювати його тут означало б завести другу копію таблиці, яка вже має три дзеркала.

---

### 1.4 Мережева Архітектура (Exposed Ports)

**Розділи SDL:** `services.web.expose` (HTTP/HTTPS) + `services.coap.expose` (UDP — INF.17)

```yaml
services:
  web:
    expose:
      - port: 80
        as: 80
        to:
          - global: true

      - port: 443
        as: 443
        to:
          - global: true

  coap:                # виділений UDP-демон (lib/daemons/coap_listener)
    expose:
      - port: 5683
        as: 5683
        proto: udp
        to:
          - global: true
```

| Порт | Протокол | Сервіс | Призначення | Відповідність Kamal |
|------|---------|--------|-------------|---------------------|
| **80** | TCP (HTTP) | `web` | Rails API + Hotwire/Turbo (Thruster reverse proxy) | `boot.proxy.publish "80:80"` |
| **443** | TCP (HTTPS) | `web` | TLS-термінований трафік; TLS через Akash ingress або Cloudflare | `boot.proxy.publish "443:443"` |
| **5683** | UDP | `coap` | CoAP — IoT телеметрія від Queen gateway (21-байтні бінарні пакети) | `coap`-роль `options.publish "5683:5683/udp"` (kamal-proxy UDP не проксіює — прямий docker-publish) |

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
│  GCP Ingress Anchor (e2-small)          │
│  Статичний IP                           │
│  ✅ CoAP-демон :5683 — PRIMARY інтейк   │
│     (docker, coap_listener; VPC →       │
│     Cloud SQL приват-IP БЕЗ Auth Proxy; │
│     Upstash TLS; INF.17 2026-07-04)     │
│  HTTP/HTTPS :80/:443 → HAProxy → Akash │
│  (socat :5683 → Akash = FALLBACK, off)  │
└─────────────┬───────────────────────────┘
              │ (HTTP/S forward; CoAP далі не йде —
              ▼  приймається на анкорі)
┌─────────────────────────────────────────┐
│  Akash Provider (децентралізований)     │
│  web:  HTTP :80 (Rails 8.1 + Puma)      │
│        HTTPS :443 (TLS терм. — INF.4)   │
│  coap: UDP :5683 (fallback-сервіс,      │
│        idle поки socat вимкнений)       │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Cloud SQL Auth Proxy (in-container)│  │
│  │ 127.0.0.1:5432 → Cloud SQL     │    │
│  │ (auth через Google API; сокет → │    │
│  │  ПУБЛІЧНИЙ IP інстанса)         │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Grafana Alloy (alloy service)   │    │
│  │ scrapes web:80 + job:9394 +     │    │
│  │ coap:9395 /metrics (15s;        │    │
│  │ реєстр in-process — 06_03 §2.9) │    │
│  │ remote_write → Grafana Cloud    │    │
│  └─────────────────────────────────┘    │
│                                         │
│  REDIS_URL = rediss://upstash (TLS) ✅  │
│  POSTGRES_HOST = 127.0.0.1:5432   ✅    │
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
**Кількість:** ~30 ENV-змінних (мірор `.kamal/secrets-common`)

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
| `POSTGRES_HOST` | `127.0.0.1` | boot | Cloud SQL Auth Proxy endpoint (non-secret literal) |
| `POSTGRES_USER` | `silken_net` | boot | DB user (non-secret literal) |
| `POSTGRES_PASSWORD` | `REQUIRED_SECRET_NOT_SET` | **boot** | Cloud SQL пароль (секрет; `POSTGRES_PORT` default 5432) |
| `CLOUD_SQL_INSTANCE_CONNECTION_NAME` | `REQUIRED_SECRET_NOT_SET` | **boot** | Cloud SQL instance connection (`project:region:instance`) |
| `GCP_SA_KEY_BASE64` | `REQUIRED_SECRET_NOT_SET` | **boot** | Base64 SA JSON для Auth Proxy |
| `REDIS_URL` | `REQUIRED_SECRET_NOT_SET` | **boot** | Sidekiq + ActionCable (Upstash `rediss://`) |
| `KREDIS_REDIS_URL` | — (auto-derive з `REDIS_URL` → `/1`) | runtime | Kredis distributed locks — **не** задавати в SDL [B1] |
| `RACK_ATTACK_REDIS_URL` | — (auto-derive з `REDIS_URL` → `/2`) | runtime | Rate-limiting (опц.) |
| `RAILS_MAX_THREADS` | `3` | runtime | Puma threads/worker — узгоджено з `database.yml` pool |
| `DB_POOL` | `17` (лише job) | runtime | ActiveRecord pool для job-сервісу — Sidekiq concurrency 15 (INF.13); web лишається default (io-aware `3+16+2=21` — формула-SSOT `config/database.yml`, INF.22) |
| `APP_HOST` | `silkennet.com` | runtime | Action Mailer `default_url_options` host (`production.rb`); web+job (INF.13) |
| `COAP_HOST` | `api.silkennet.com` | runtime | Адреса CoAP-інтейку, яку пробує адмін-панель здоров'я UDP-раундтріпом (ARCH.81); **web only** — та сама, що набирає Королева (`COAP_SERVER_HOST` прошивки). Незадана ⇒ панель каже «не сконфігуровано», а не «мертвий» |
| `WEB_CONCURRENCY` | `4` | runtime | Puma worker processes (web only) |

### 2.2 🛑 Boot-critical security guards

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `PROVISIONING_MASTER_KEY` | `REQUIRED_SECRET_NOT_SET` | **boot** | HKDF root key. `config/initializers/master_key_strength_check.rb` raises `SecurityError` у `after_initialize` → Puma crash. Generate: `SecureRandom.hex(32)` |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | `REQUIRED_SECRET_NOT_SET` | **boot** | AR-encryption at-rest (`hardware_keys` / `users.otp_secret`). `Security::EncryptionKeyGuard::REQUIRED_ENVS` → `config/initializers/active_record_encryption_keys_check.rb` raises fail-closed. Свідомо **ENV, не credentials** — інакше вертається runtime-залежність від `RAILS_MASTER_KEY` (SEC.22). Generate: `bin/rails db:encryption:init` |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | `REQUIRED_SECRET_NOT_SET` | **boot** | ↑ той самий guard (min 32 символи) |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | `REQUIRED_SECRET_NOT_SET` | **boot** | ↑ той самий guard (min 32 символи) |

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
| `ORACLE_CELO_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | **[ARCH.50]** Dedicated Celo cUSD-підписант (no fallback — INF.22) |
| `ORACLE_MINTER_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | `BlockchainMintingService` (MINTER_ROLE) |
| `ORACLE_SLASHER_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | `BlockchainBurningService` (SLASHER_ROLE) |
| `ETHEREUM_ANCHOR_PRIVATE_KEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | `Ethereum::StateAnchorService` (окремий гаманець!) |

> Легасі `ORACLE_PRIVATE_KEY` retired [INF.22] — зі SDL знято (Invariant B2 `deploy_secret_scan` проти повернення). Aux-підписанти (ETHERISC/PURO/KLIMA) — activation-gated, Console-інжект, НЕ в SDL.

### 2.5 RPC endpoints (`Web3::RpcConnectionPool`)

| Змінна | Значення в SDL | Required for | Призначення |
|--------|---------------|-------------|-------------|
| `ALCHEMY_POLYGON_RPC_URL` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Усі SCC/SFC операції на Polygon |
| `ALCHEMY_ETHEREUM_RPC_URL` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Weekly L1 state-root anchor |
| `SOLANA_RPC_URL` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Solana мікро-винагороди |
| `CELO_RPC_URL` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Celo ReFi винагороди (`Celo::CommunityRewardService`) |
| `HELIUM_WEBHOOK_SECRET` | `REQUIRED_SECRET_NOT_SET` | **runtime** | HMAC inbound-вебхука Helium (fail-closed у prod) |

### 2.6 Solana minting

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `SOLANA_WALLET_KEYPAIR` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | 64-byte hex keypair |
| `SOLANA_FEE_PAYER_PUBKEY` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Base58 fee payer |
| `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | USDC ATA |
| `SOLANA_USDC_MINT_ADDRESS` | `REQUIRED_SECRET_NOT_SET` | **web3-worker** | Base58 mint (mainnet USDC) |

### 2.7 Chainlink oracle-callback HMAC (dispatch вилучено — ARCH.53)

| Змінна | Значення в SDL | Required for | Опис |
|--------|---------------|-------------|------|
| `CHAINLINK_HMAC_SECRET` | `REQUIRED_SECRET_NOT_SET` | runtime (web) | Перевірка `X-Chainlink-Signature` у callback (єдиний Chainlink-ENV після демоуту; Router/subscription/DON-ID вилучено разом з on-chain dispatch) |

### 2.8 Security knobs (Rails hardening)

| Змінна | Значення | Required for | Опис |
|--------|---------|-------------|------|
| `WEB3_STRICT_MODE` | `true` | web3-worker | Hadron KYC/RWA + Chainlink-callback HMAC fail-closed на missing creds — **belt-and-suspenders** `WEB3_STRICT_MODE == "true" \|\| Rails.env.production?` (прапор може дрейфнути з deploy-поверхні, production — ні; Hadron harden 2026-07-10 вирівняв його з контролерами/W3bstream/boot-guard — раніше він єдиний був flag-only → forgotten-flag=fake-KYC mint); dispatch більше не STRICT-gated — local marker, ARCH.53; web+job (INF.11) |
| `RAILS_ALLOWED_HOSTS` | *(потрібно встановити)* | runtime ⚠️ | Comma-separated allowlist (DNS-rebinding захист) — канон-пара INF.4: `silkennet.app,api.silkennet.com` (web-хост обов'язковий — wildcard `.silkennet.com` його НЕ покриває → 403 block-all) |
| `DISABLE_SSL` | *(не встановлювати)* | runtime | `true` лише якщо Akash ingress / Cloudflare термінує TLS |
| `CSP_ENFORCE` | *(не встановлювати)* | runtime | `true` після burn-in CSP report-only (1–2 тижні) |

**Terraform-шаблон додає змінні динамічно** (`deploy.yaml.tpl`):

```hcl
# terraform/akash/main.tf — рендеринг шаблону (ілюстрація; повна map — у файлі)
resource "local_file" "akash_sdl" {
  content = templatefile("deploy/akash/deploy.yaml.tpl", {
    rails_master_key                    = var.rails_master_key    # sensitive = true
    db_password                         = var.db_password          # sensitive = true
    redis_url                           = var.redis_url            # sensitive = true
    cloud_sql_instance_connection_name  = var.cloud_sql_instance_connection_name  # sensitive = true
    gcp_sa_key_base64                   = var.gcp_sa_key_base64   # sensitive = true
    # ...
  })
  file_permission = "0600"  # Захист файлу із секретами
}
```

> **[B1]** `kredis_redis_url` у Terraform **не існує** (variable видалено) — Kredis auto-derive DB 1 із `REDIS_URL` живе на Rails-стороні (`config/redis/shared.yml`), жодної Terraform-логіки для нього немає.

---

## 3. Terraform Конфігурація

### 3.1 Структура файлів

```
terraform/akash/
├── main.tf                   # SDL rendering + null_resource Akash CLI provisioner
├── variables.tf              # вхідні змінні (мережа, ресурси, ціна, секрети) — к-сть: `grep -c '^variable' `
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
| `akash_auditor_address` | `akash1365yvmc4s7awdyj3n2sav7xfx76adc6dnmlx63` | — | Адреса аудитора для фільтрації провайдерів |

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
| `db_password` | Length ≥ 16 chars (host=127.0.0.1 proxy + user silken_net — non-secret SDL literals) |
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
| `oracle_minter_private_key` | Hex `0x…` (MINTER_ROLE на SCC/SFC) |
| `oracle_slasher_private_key` | Hex `0x…` (SLASHER_ROLE на SCC/SFC) |
| `ethereum_anchor_private_key` | Hex `0x…` (окремий wallet для L1 anchor — MUST differ from minter/slasher signers) |

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

**Chainlink oracle-callback HMAC (dispatch вилучено — ARCH.53):**

| Змінна | Валідація |
|--------|-----------|
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

### 4.4 FinOps guards [OPS.11]

Дві фінансові «тихі смерті» деплою мають по машинному вартовому (обидва — config-SSOT, тут лише механіка):

1. **GCP billing budget** — `terraform/billing.tf`: `google_billing_budget` з порогами 50/90/100% + forecasted-100% (лист летить Billing-адмінам без додаткових notification-каналів). Guard: порожній `billing_account_id` (tf-var) = блок no-op; заповнюєш у `terraform.tfvars` — **той самий** id мусить стояти у GitHub-секреті `GCP_BILLING_ACCOUNT_ID` (обидва deploy-workflow передають `TF_VAR_billing_account_id`), інакше наступний CI-apply побачить count=0 і знесе бюджет. ⚠️ **Грант CI-SA на billing-акаунті = ОБОВ'ЯЗКОВИЙ перед активацією** (Opus-ревю 2026-07-05): billing-ролі живуть в окремій ієрархії (project-ролі не покривають), а `terraform plan` **рефрешить** бюджет щоразу (`billing.budgets.get`) — разовий founder-auth apply НЕ рятує: наступний CI-plan отримує 403 і через `needs: terraform` блокує ВЕСЬ deploy-ланцюг. Разово: `gcloud billing accounts add-iam-policy-binding <ACCT_ID> --member="serviceAccount:silken-net-deploy@<project>.iam.gserviceaccount.com" --role="roles/billing.costsManager"`. Enablement `billingbudgets.googleapis.com` eventually-consistent — перший activation-apply може впасти раз; re-apply проходить.
2. **AKT escrow runway** — ескроу lease **вигорає щоблоку**; на нулі lease закривається (web+job+coap гинуть разом). Вартовий: `.github/workflows/akash_escrow_watch.yml` (**Ops · Akash Escrow Watch**, daily + dispatch) — читає публічний LCD REST (market `v1beta5` + deployment `v1beta4`; старші версії на mainnet відповідають "Not Implemented"), рахує `runway = (funds − накопичене з settled_at) / (Σ price·blocks/day)` і падає гучно при runway < порога (default 14 діб) **або при нулі активних leases** (= lease уже закрився). Skip-clean до repo Variable `AKASH_OWNER_ADDRESS` (патерн `coap_smoke`); календарний мінімум дня-1 — over-fund ≥2× місячної оцінки — лишається оператору.

   ⚠️ **Не звіряй escrow-структуру з published proto** (`akash-api` main = escrow v1beta3 — застарілий за живою мережею; Opus-ревю 2026-07-05 мало не зарепортило робочі jq-шляхи як баг). Жива форма `deployments/info` (звірено проти mainnet 2026-07-05; `state.funds` == Σ `deposits[].balance`, окремого `state.balance` більше НЕМАЄ; lease `price.amount` — decimal-рядок за блок):

   ```json
   "escrow_account": { "state": {
     "state": "open", "settled_at": "27567175",
     "funds":    [{ "denom": "uact", "amount": "557523.000000000000000000" }],
     "deposits": [{ "owner": "akash1…", "height": "25869478", "source": "grant",
                    "balance": { "denom": "uact", "amount": "557523.000000000000000000" } }]
   } }
   ```

### 4.5 Доступ до Rails-процесу на ЖИВОМУ lease — рецепт-КАНДИДАТ [OPS.20]

🔴 **Чому ця секція існує.** Кожен console-рецепт репо починається словами «виконай у
консолі», а канон описував дорогу до процесу **лише для Kamal/GCP-fallback**
([`06_01`](06_01_Deployment_Kamal_Terraform)). Живий шлях — Akash (так його називає
`config/database.yml`), і для нього еквівалента не було ЖОДНОГО. Інертними ставали всі
рецепти разом, зокрема два money-path: резолюція `manual_review` та ескалація Field-Audit
C→A ([`06_08 §4.4`](06_08_Resilience_and_Failover_Policy) / [`§4.6`](06_08_Resilience_and_Failover_Policy)),
що відчиняє ворота необоротного слешингу. Спільна нота — одним домом у
[`06_07 §3`](06_07_CICD_and_Runbook_Index).

🔒 **СТАТУС: КАНДИДАТ.** Механізм не доведений на живому lease — його ще не було. Нижче
розведено те, що **доводиться нашим кодом уже зараз**, і те, що чекає першого lease; не
зливай ці дві половини, читаючи рецепт в інциденті.

**✅ Доводиться зараз — проксі живе В ТОМУ САМОМУ контейнері.** Це і є справжнє питання
ноги («чи шелл потрапляє туди, де вже піднятий Cloud SQL Auth Proxy»), і відповідь у
`bin/docker-entrypoint`, не в чужій документації: проксі стартує фоновим процесом
(`cloud-sql-proxy … &`) усередині контейнера сервісу, а **не** окремим Akash-сервісом
(в SDL їх рівно чотири: `web` · `job` · `coap` · `alloy`). Отже будь-який шелл у контейнер
`web`/`job` ділить із застосунком мережевий неймспейс, і `127.0.0.1:5432` — це той самий
сокет, яким ходить Rails. ⊕ **Сильніше:** PID 1 наглядає за проксі й виходить, щойно той
помер (INF.22-супервізор у тому ж файлі), а Akash перезапускає контейнер лише на виході
PID 1 — тож **контейнер, у який вдалося зайти, за побудовою має живий проксі**. Це не
припущення, а наслідок нашого ж entrypoint'а.

**⏳ Чекає першого lease — САМ механізм входу.** Офіційний інструмент —
`provider-services lease-shell` (аналог `kubectl exec` через ендпоінт провайдера):

```bash
# ⚠️ ФЛАГИ ЗВІРЯЙ ІЗ САМИМ ІНСТРУМЕНТОМ, не з цього рядка — CLI рухається без наших комітів:
provider-services lease-shell --help

# Форма станом на 2026-08-28 (docs.akash.network, «Deployment Shell Access»):
provider-services lease-shell   --from "$AKASH_KEY_NAME"   --dseq "$(cat terraform/akash/akash-dseq.txt)"   --provider "$AKASH_PROVIDER"   --tty   web /bin/bash
# `web` — ім'я сервісу з SDL (для Sidekiq-контексту: `job`).
# Наш образ Debian-slim, тож `/bin/bash` є; `/bin/sh` теж (в Alpine було б `/bin/ash`).

# Далі — звичайна консоль, БД доступна через уже піднятий проксі:
bin/rails console
```

⛔ **Не бери `coap` для консолі.** Той процес свідомо звільнений від master-key-перевірки
(`$PROGRAM_NAME`-виняток, [`06_04 §5.7`](06_04_Secrets_Checklist)) і є UDP-клеєм — консоль
там не має ані повного ENV, ані призначення.

⚠️ **Названі межі кандидата** (кожна — те, що перевіряє `👤`-нога):
- провайдер мусить підтримувати shell-ендпоінт; це властивість ПРОВАЙДЕРА, не мережі;
- апстрім має відомий дефект: після рестарту сервісу провайдера `lease-shell` віддає
  `remote server returned 404` ([akash-network/support#87](https://github.com/akash-network/support/issues/87)),
  тобто в інциденті — саме тоді, коли контейнер щойно перезапустився, — інструмент може
  бути недоступним. Це найважливіша половина для money-path-рецептів: **план Б потрібен
  саме на цей випадок**, і сьогодні його немає;
- `--gseq`/`--oseq` за замовчуванням `1`; при кількох групах/ордерах їх треба задавати явно;
- при `count > 1` у профілі шелл треба цілити в конкретну репліку.

**Що робить `👤`-верифікація на першому lease:** прогнати команду вище, дійти до
`bin/rails console`, виконати `ActiveRecord::Base.connection.execute("select 1")` — і
доти, доки це не зроблено, знімати з рецепта слово «кандидат» не можна.

---


---

## 5. Порівняння: Akash vs GCP Production

> ⚠️ Колонка «GCP» тут — той самий **Kamal-fallback**, не провіжений веб-хост (див. ноту під таблицею ресурсів вище, [DOC-T.50]).

| Параметр | GCP Kamal fallback 🌲 | Akash ☁️ (production) | Статус |
|----------|-------------------|----------|--------|
| **CPU** | 2 vCPU | 4 vCPU | ✅ Більше для компенсації |
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

Mapping між конфігурацією Kamal (`config/deploy.yml` + `.kamal/secrets-common`) та SDL (`deploy/akash/deploy.yaml` + `deploy/akash/deploy.yaml.tpl`). Список повністю синхронізовано — кожен запис у Kamal `env.secret` повинен мати відповідник у обох сервісах SDL (`web` + `job`).

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
| `env.clear APP_HOST=silkennet.com` | `env: APP_HOST=silkennet.com` (web+job) |
| `env.clear COAP_HOST=api.silkennet.com` | `env: COAP_HOST=api.silkennet.com` (web only — проба панелі, ARCH.81) |
| `env.clear WEB3_STRICT_MODE=true` | `env: WEB3_STRICT_MODE=true` (web+job) |
| `(job) DB_POOL=17` | `env: DB_POOL=17` (job-сервіс — Sidekiq pool) |
| `volumes: silken_net_storage:/rails/storage` | `params.storage.data.mount: /rails/storage` |
| `builder.arch: amd64` | `profiles.compute.web.resources.cpu.units: 4` |
| — | ✅ `alloy` сервіс (OBS.1 — Grafana Cloud sidecar) |
| `password: GCP_ARTIFACT_REGISTRY_KEY` | ❌ Не потрібен (GHCR public image) |

### Mapping `env.secret` → SDL `env:`

> **Принцип:** кожна змінна нижче повинна бути одночасно у `.kamal/secrets-common`, `config/deploy.yml env.secret`, `deploy/akash/deploy.yaml` (обидва сервіси), `deploy/akash/deploy.yaml.tpl` (обидва сервіси), `terraform/akash/variables.tf` (як `sensitive = true`), та `terraform/akash/main.tf` (у `templatefile()` map). Drift = boot crash або тиха відмова Web3 pipeline. (Колишній виняток `ORACLE_PRIVATE_KEY` знято — legacy retired повністю [INF.22]; activation-gated aux-підписанти свідомо поза УСІМА цими поверхнями — Console-only.)

**Application core (boot):**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `RAILS_MASTER_KEY` | `RAILS_MASTER_KEY=${rails_master_key}` | `var.rails_master_key` |
| `POSTGRES_PASSWORD` | `POSTGRES_PASSWORD=${db_password}` | `var.db_password` |
| — (non-secret literals у SDL) | `POSTGRES_HOST=127.0.0.1` · `POSTGRES_USER=silken_net` | — |
| `REDIS_URL` | `REDIS_URL=${redis_url}` | `var.redis_url` |
| `KREDIS_REDIS_URL` | — (не в SDL — auto-derive DB 1) | — (variable видалено, B1) |
| — (Cloud SQL Auth Proxy) | `CLOUD_SQL_INSTANCE_CONNECTION_NAME=...` | `var.cloud_sql_instance_connection_name` |
| — (Cloud SQL Auth Proxy) | `GCP_SA_KEY_BASE64=...` | `var.gcp_sa_key_base64` |

**🛑 Boot-critical security guard:**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `PROVISIONING_MASTER_KEY` | `PROVISIONING_MASTER_KEY=${provisioning_master_key}` | `var.provisioning_master_key` |
| `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` | `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=${active_record_encryption_primary_key}` | `var.active_record_encryption_primary_key` |
| `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` | `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=${active_record_encryption_deterministic_key}` | `var.active_record_encryption_deterministic_key` |
| `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` | `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=${active_record_encryption_key_derivation_salt}` | `var.active_record_encryption_key_derivation_salt` |

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
| `ORACLE_CELO_PRIVATE_KEY` | `ORACLE_CELO_PRIVATE_KEY=${oracle_celo_private_key}` | `var.oracle_celo_private_key` |
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

**Chainlink oracle-callback HMAC (dispatch вилучено — ARCH.53):**

| Kamal `env.secret` | Akash SDL (web + job) | Terraform variable |
|-------------------|----------------------|---------------------|
| `CHAINLINK_HMAC_SECRET` | `CHAINLINK_HMAC_SECRET=${chainlink_hmac_secret}` | `var.chainlink_hmac_secret` |

> **🔴 Drift guard:** при додаванні нового ENV у Kamal `env.secret` **ОБОВ'ЯЗКОВО** додати у всі 5 локацій вище. Інакше Akash deployment отримає boot crash (категорія A) або тиху Web3 відмову (категорія B). Див. також §Секрети SDL (категорії A/B/C) вище.

---

## 7. Інтеграція у Загальну Архітектуру SilkenNet

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

**Висновок:** SDL визначає **чотири** сервіси: `web` (Rails API), `job` (Sidekiq workers), `coap` (виділений UDP-демон 5683 — INF.17, Akash-**fallback** за socat) та `alloy` (Grafana Alloy → Grafana Cloud). Cloud SQL Auth Proxy (in-container) забезпечує доступ до PostgreSQL через публічний IP інстанса з IAM-авторизацією, Upstash serverless Redis (TLS) замінює GCP Memorystore. `job` сервіс використовує entrypoint (`/rails/bin/docker-entrypoint bundle exec sidekiq ...`) для запуску Cloud SQL Proxy і для Sidekiq. `alloy` сервіс (образ запінено `grafana/alloy:v1.16.3` — синхронно з `deploy.yaml.tpl`/`ci.yml`, INF.14) скрейпить **три** `/metrics`-таргети (`web:80` + `job:9394` + `coap:9395`, лейбл `process` — [`06_03 §2.9`](06_03_Prometheus_Observability)) кожні 15 секунд та пушить метрики у Grafana Cloud через remote_write. Ingress Anchor (`e2-small` зі статичним IP) приймає CoAP **демоном прямо на анкорі** (PRIMARY — INF.17) і проксіює лише HTTP/HTTPS до Akash. Multi-replica ActionCable працює без sticky sessions завдяки Solid Cable adapter — всі репліки `web` підключені до спільної Cloud SQL БД `silken_net_production_cable`, і крос-реплікову доставку Turbo Stream broadcasts забезпечує **опитування** спільної таблиці кожною реплікою (`polling_interval`), а НЕ `LISTEN/NOTIFY` — того механізму в solid_cable немає взагалі; наслідки для ємності — [`06_01`](06_01_Deployment_Kamal_Terraform) (Redis DB Isolation Strategy) + `config/cable.yml`.

---

## 8. Дорожня Карта (Path to TRL 5 → 9)

| TRL | Що потрібно | Статус |
|-----|------------|--------|
| **TRL 5** ✅ | SDL-маніфест (`web` + `job` + `coap` + `alloy`), DB+Redis connectivity, GHCR mirror | ✅ Всі передумови виконані |
| **TRL 5** ✅ | Вирішити мережеву ізоляцію (Cloud SQL + Redis) | ✅ Cloud SQL Auth Proxy + Upstash |
| **TRL 5** ✅ | Додати `job` сервіс в SDL для Sidekiq | ✅ виправлено |
| **TRL 5** ✅ | Замінити Docker образ на публічний реєстр (GHCR) | ✅ виправлено (`mirror-ghcr.yml`) |
| **TRL 6** 🎯 | Перший реальний деплой на Akash Mainnet + функціональне тестування CoAP | 🔴 00_07 S4.3 (секрети — заповнити `terraform.tfvars`) |
| **TRL 7** 🎯 | Налаштувати TLS через Akash ingress hostname operator або Cloudflare | 🟡 00_07 INF.4 (порт 443 у SDL, TLS не активована) |
| **TRL 7** 🎯 | GCS bucket для Terraform state | 🟡 00_07 S5.6 (створити вручну перед `terraform init`) |
| **TRL 8** | Production деплой з Grafana Cloud метриками + alerting | Потребує TRL 7 + GRAFANA_* secrets |
| **TRL 9** | Automated failover GCP ↔ Akash + повна CI/CD інтеграція | — |
