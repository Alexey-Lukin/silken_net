# 06_04: Secrets Checklist (Інвентаризація Секретів)

## 🎯 Мета

Єдиний SSOT-checklist усіх секретів, необхідних для роботи системи в Canopy (staging) та Production. Документ закриває **[`00_07`](00_07_Action_Plan_Tracker) S1.1** («GitHub Secrets заповнення», deploy-контекст [`06_01`](06_01_Deployment_Kamal_Terraform)) — частину 🤖.

> **Принцип:** Секрет = **будь-яке значення, втрата якого означає можливість компрометації або знищення системи**: приватні ключі, паролі БД, master keys, API tokens, RPC credentials. Реальні значення **ніколи** не комітяться в git та не зберігаються у цьому документі.

> **Чотири місця зберігання секретів:**
> 1. **GitHub Repository Secrets** — для CI/CD workflows (`.github/workflows/*.yml`)
> 2. **`.kamal/secrets-common`** — runtime секрети для Kamal-деплою на VM (читаються з ENV або keychain)
> 3. **`deploy/akash/deploy.yaml`** — секрети Akash деплою (поточно `REQUIRED_SECRET_NOT_SET` плейсхолдери)
> 4. **`terraform/terraform.tfvars`** — секрети Terraform (НЕ комітиться, `*.tfvars` у `.gitignore`)

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — механізм секретів (AR-encryption non-deterministic, HKDF per-device, `.kamal/secrets-common`, `verify-secrets` CI gate) реалізований, і **CI-гейт `verify-secrets` його стереже** — але ⚠️ **у Canopy він НЕ перевірявся: staging-деплою не було жодного** (крок `Kamal Deploy (Canopy)` skipped у всіх перевірених прогонах; deploy-секретів у репо — один, і той не деплойний; [`06_01`](06_01_Deployment_Kamal_Terraform) каже це прямо). Доти цей рядок стверджував «перевірений у Canopy» — виправлено 2026-08-22 виміром. Production-значення не провіжені (операційна задача, [`00_07`](00_07_Action_Plan_Tracker) S1.1). Канон модульного TRL — [`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond).
- **Поточний стан:** Backend код підтримує всі секрети, але production значення **не встановлені** в GitHub repository та `.kamal/secrets-common`. Це блокує весь CI/CD pipeline.
- **Відкрите:** production secret values не провіжені (блокує CI/CD) → [`00_07`](00_07_Action_Plan_Tracker) (S1.1, S4.3, S5.6).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | Деплой (Kamal/Terraform secrets) |
| [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) | Akash SDL secrets (§Секрети SDL) |
| [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) | Grafana Cloud + Sentry DSN |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | S1.1, S4.3, S5.6 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [1. GitHub Repository Secrets (CI/CD)](#1-github-repository-secrets-cicd)
- [2. (Kamal Runtime)](#2-kamalsecrets-common-kamal-runtime)
- [3. Akash SDL ( + )](#3-akash-sdl-deployakashdeployyaml--deployyamltpl)
- [4. `terraform/terraform.tfvars](#4-terraformterraformtfvars)
- [5. Operational Procedures](#5-operational-procedures)
- [Залежності та посилання](#-залежності-та-посилання)
<!-- TOC:AUTO:END -->

---

## 1. GitHub Repository Secrets (CI/CD)

> **Шлях створення:** `Settings → Secrets and variables → Actions → New repository secret`
>
> **[INF.22 2026-07-10] Два рівні скоупу — money-ключі НЕ repo-level.** GH Environment **`production`** (створений API, wait-timer 10 хв + ref-policy `v*`-теги ∪ `main`) скоупить **money/signing-п'ятірку GH/Kamal-поверхні**: `ORACLE_MINTER_PRIVATE_KEY` · `ORACLE_SLASHER_PRIVATE_KEY` · `ORACLE_CELO_PRIVATE_KEY` · `ETHEREUM_ANCHOR_PRIVATE_KEY` · `SOLANA_WALLET_KEYPAIR` — класти через `Settings → Environments → production → Add secret` (або `gh secret set <NAME> --env production`), **НЕ** як repository secret. (Legacy `ORACLE_PRIVATE_KEY` **повністю RETIRED [INF.22 2026-07-10]** — жоден код його не читає, `Web3NetworkGuard` відмовляє значенню під цим ім'ям (tripwire), `deploy_secret_scan` Invariant B2 ловить повернення в SDL на CI; кожен підписант = dedicated-ключ, E.2.) Environment-секрет читається ЛИШЕ job'ами з `environment: production` (`deploy-production.yml`: `verify-secrets` + `deploy`; будь-який інший workflow бачить `""`); wait-timer спрацьовує **per-job** → 2 гейти по 10 хв на release (свідомо: перед terraform-apply і перед kamal-шипом signing-контейнера; solo-substitute людського approval, bus_factor=1). Canopy **структурно web-only** (array-form `servers:` у `deploy.canopy.yml` — Kamal deep_merge = keys-union, тож ОМІТНУТА роль успадковується з base; масив замінює hash повністю) і money-ключі не споживає (гейт/env підрізано — див. коментарі в `deploy.yml`). Решта секретів (shared boot-core: master-keys, POSTGRES, REDIS, RPC, HMAC) = **repo-level** — їх потребують canopy + drift-workflow; стеля позначена: окремий environment для canopy = YAGNI до появи canopy-специфічних money-потреб. ⚠️ Пастки: (1) репо стане private → environment-protection **ігнорується** (rules лишаються, не діють); (2) workflow-реф на НЕІСНУЮЧИЙ environment **авто-створює його БЕЗ protection-rules** — новий environment завжди створюй API/UI з rules ДО мержу yml, що на нього посилається (так зроблено з `production` 2026-07-10).
>
> **Перевірка покриття:** `grep -rh "secrets\." .github/workflows/ | grep -oP "secrets\.[A-Z_]+" | sort -u`
>
> **[B1] CI Kamal deploy мапить увесь `env.secret` набір.** `deploy.yml`/`deploy-production.yml` у кроці `kamal deploy` передають **весь** `config/deploy.yml env.secret` набір із GitHub Secrets у shell-ENV — `.kamal/secrets-common` читає кожну як `$VAR`. Пропущена тут = порожній інжект → boot-crash (`RAILS_MASTER_KEY` decrypt / `PROVISIONING_MASTER_KEY` guard / oracle KeyError) або web3-strict raise. Тому **і P0-набір (§1.1), і Web3/runtime-набір (§1.4) = GitHub Secrets.** `verify-secrets` гейтить повний boot-critical набір (fail-loud на production, skip-clean на canopy).
>
> `DATABASE_URL`/`DATABASE_PASSWORD`/`CANOPY_DATABASE_URL` виведені — component style, INF.16. `KREDIS_REDIS_URL` виведений — Kredis auto-derive DB 1 із `REDIS_URL` (`config/redis/shared.yml`, §2.1).

### 1.1. P0 — Blocking (без цих secrets CI/CD не запуститься)

- [ ] `RAILS_MASTER_KEY` — Rails credentials decryption key. **[B1]** CI читає його як GitHub Secret; `.kamal/secrets-common` тепер ENV-first (`${RAILS_MASTER_KEY:-$(cat config/master.key)}`) — `config/master.key` gitignored, відсутній у CI checkout, тож GitHub Secret мусить перемогти, інакше boot-decrypt падає.
> ~~`KAMAL_MASTER_KEY`~~ — **ВИДАЛЕНО 2026-07-04 (фантом):** Kamal 2.x не має механізму «encrypted secrets master key»; `.kamal/secrets-common` — plain `$VAR`-файл, споживача не існувало ніде в репо, а verify-secrets гейтив production на неіснуючу залежність. Не заводити.
- [ ] `PROVISIONING_MASTER_KEY` — HKDF root для per-device AES-деривації (boot-critical: `config/initializers/master_key_strength_check.rb` raise при відсутності в production). **[B1]** `verify-secrets` перевіряє присутність + довжину ≥64; обидва deploy-workflow маплять його у `kamal deploy`. Генерувати: `ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"`. (Runtime-роль — §2.)
- [ ] `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` · `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY` · `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT` — **[SEC.22] AR-encryption at-rest** (`hardware_keys` device-ключі + `users.otp_secret` TOTP-seed; §5.7). Boot-critical: `active_record_encryption_keys_check.rb` fail-closed у production без них (або на `<32` chars). **[B1 2026-07-10, R3a-fresh-eye]** обидва deploy-workflow маплять усі три у verify (BOOT_CRITICAL) + `kamal deploy` env — до того вони жили в `env.secret`/`secrets-common`, але НЕ в workflow-мапінгу → перший live-kamal інжектнув би `""` = boot-crash ПІСЛЯ зеленого verify (той самий B1-клас 4-місячної діри). Генерувати всі три разом: `bin/rails db:encryption:init`.
> ~~`GCP_SA_KEY`~~ — **ВИДАЛЕНО як CI-secret 2026-07-09 (INF.22, keyless WIF):** CI автентифікується до GCP через **Workload Identity Federation** (`terraform/wif.tf`) — GitHub карбує короткоживучий OIDC-токен, GCP STS обмінює його на impersonated deploy-SA access-token; JSON-ключ (6-місний, boot-critical, безстроковий credential) з CI зник. Замість нього — два **repo Variables** (не secrets, це публічні ідентифікатори): `GCP_WORKLOAD_IDENTITY_PROVIDER` (з `terraform output workload_identity_provider`) + `GCP_SERVICE_ACCOUNT` (SA email). Довгоживучий SA-ключ лишається ЛИШЕ в Akash `GCP_SA_KEY_BASE64` (Cloud SQL proxy — §3.1/§4; [`06_02 §Security Exception`](06_02_Akash_Network_Integration)).
- [ ] `GCP_PROJECT_ID` — ID GCP проєкту (наприклад, `silken-net-prod`)
- [ ] `POSTGRES_PASSWORD` — пароль Cloud SQL `silken_net` user (≥16 символів, password manager). **Component style** (`config/database.yml`): host/user/database — non-secret (`config/deploy.yml env.clear`), лише пароль = секрет. Один секрет живить Kamal `POSTGRES_PASSWORD` **і** Terraform `TF_VAR_db_password`. Той самий для production + canopy — ізоляція через `POSTGRES_DATABASE` (canopy = `silken_net_canopy`), НЕ окремий URL. (Замінив `DATABASE_URL`/`DATABASE_PASSWORD`/`CANOPY_DATABASE_URL` — INF.16.)
- [ ] `REDIS_URL` — Production Redis (DB 0, Upstash): `rediss://default:<password>@<endpoint>.upstash.io:6379/0`
- [ ] `CANOPY_REDIS_URL` — Canopy Redis (DB 0): `rediss://default:<password>@<endpoint>.upstash.io:6379/0`
> ~~`SSH_PRIVATE_KEY` / `SSH_PUBLIC_KEY` / `SSH_KNOWN_HOSTS`~~ — **ЗНЯТО 2026-07-04 (INF.20 (в)):** SSH на анкор = IAP-тунель + OS Login, ключового матеріалу для провіжна НЕМАЄ (ключі керує OS Login; порт 22 в інтернет не відкритий — firewall лише 35.235.240.0/20). Доступ = IAM: tf-var `iap_admin_members` (osAdminLogin + tunnelResourceAccessor). CI-Kamal при потребі — (б)-клей: `ssh.proxy_command` через `gcloud compute start-iap-tunnel` + ті самі ролі для SA. Не заводити ці секрети.

### 1.2. P1 — Operations (потрібні для конкретних автоматизацій)

- [ ] `GCP_BILLING_ACCOUNT_ID` — **[OPS.11]** дзеркало tfvars `billing_account_id` для CI terraform apply (`TF_VAR_billing_account_id` в обох deploy-workflow). ⚠️ Заводиться **разом** із tfvars-значенням: локальний apply з бюджетом + CI-apply без секрета = count→0 → CI **знесе бюджет**. ⚠️ ПЕРЕД активацією — обов'язковий грант CI-SA `roles/billing.costsManager` на billing-акаунті (plan-refresh 403-ить і блокує весь deploy-ланцюг — точна команда/механіка → [`06_02 §4.4`](06_02_Akash_Network_Integration)). Порожній = budget просто не керується (no-op).

> **Repo Variables (не Secrets):** `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_SERVICE_ACCOUNT` (keyless WIF-auth deploy/drift — INF.22; з `terraform output` після 1-го apply; їх presence = infra-provisioned deploy-gate, який раніше ніс `GCP_SA_KEY`) · `CANOPY_COAP_HOST` / `PRODUCTION_COAP_HOST` (активують `coap_smoke` — INF.6) · `AKASH_OWNER_ADDRESS` (+опц. `AKASH_MIN_RUNWAY_DAYS`, `AKASH_LCD_BASE`) — активує **Ops · Akash Escrow Watch** [OPS.11] після першого lease. До заповнення обидва workflow видимо skip-clean.

### 1.3. P2 — Опціонально / Auto-derived

- [ ] `KREDIS_REDIS_URL` — **[B1] виведено з усіх deploy-surface.** Kredis auto-derive DB 1 із `REDIS_URL` (`config/redis/shared.yml`: `/0`→`/1`). Не оголошений у Kamal / Akash / Terraform. Заводь GitHub Secret лише щоб указати на **окремий** Redis-інстанс (рідко).
- [ ] `RACK_ATTACK_REDIS_URL` — Production Redis (DB 2) для rate limiting. Опціонально (auto-derive із `REDIS_URL`).
- [ ] `SCORECARD_TOKEN` — fine-grained read-only PAT (repo admin: read) для `Sec · Scorecard` (OpenSSF, OPS.10). **Опціонально:** без нього Scorecard працює, але пропускає Branch-Protection/Webhooks-перевірки (`GITHUB_TOKEN` їх не читає). Дім workflow — [`06_07 §1`](06_07_CICD_and_Runbook_Index).
- _(секрет НЕ потрібен)_ **Build-provenance attestation** (`mirror-ghcr.yml`, OpenSSF `signed_releases`) підписує GHCR-образ **keyless** через GitHub OIDC (`id-token: write`) + вбудований `GITHUB_TOKEN` — Sigstore Fulcio видає ефемерний сертифікат per-build, тож **підписувального ключа провіженити/зберігати не треба**. Політика → [`06_07 §1a`](06_07_CICD_and_Runbook_Index); verify → `SECURITY.md`.

### 1.4. Web3 / runtime secrets — GitHub Secrets для CI Kamal deploy [B1]

> Раніше ці жили лише у `.kamal/secrets-common` (§2) / Akash SDL (§3) / Terraform (§4). **Після B1** обидва deploy-workflow маплять їх із GitHub Secrets у крок `kamal deploy`, тож для CI-деплою вони **мусять існувати як GitHub Repository Secrets**. Повний опис кожного — §2.1 (one-home); тут лише перелік + boot-vs-lazy клас (`verify-secrets` гейтить boot-critical, warn на lazy).

**Boot-critical** (порожній → контейнер падає на boot / terraform не apply-неться; `verify-secrets` блокує; гейт покриває і infra-передумови `GCP_PROJECT_ID` + WIF-Variables `GCP_WORKLOAD_IDENTITY_PROVIDER`/`GCP_SERVICE_ACCOUNT` — SA-JSON `GCP_SA_KEY` вилучено, CI keyless WIF INF.22; SSH-секрети ЗНЯТО, INF.20 (в) IAP keyless, див. §1.1):
- [ ] `ORACLE_MINTER_PRIVATE_KEY` · `ORACLE_SLASHER_PRIVATE_KEY` — `web3_network_guard` raise при boot **signer-процесу (Sidekiq job)**, якщо dedicated-ключа немає (legacy fallback retired — INF.22; значення під старим ім'ям = guard-violation). **Money/signing-ключі = JOB-ONLY (2026-07-04):** signing-**п'ятірка** живе лише в `job`-поверхнях — Akash SDL job-сервіс і Kamal `servers.job.env.secret` несуть однакові 5 (`ORACLE_MINTER/SLASHER/CELO` + `ETHEREUM_ANCHOR_PRIVATE_KEY` + `SOLANA_WALLET_KEYPAIR`); web/coap бутяться keyless by design (Akash ENV = plaintext провайдеру; guard scoped `signer_process: Sidekiq.server?` — [`04_02 §Web3NetworkGuard`](04_02_Business_Logic_and_Services)). **[INF.22 2026-07-10] У GitHub п'ятірка = environment-scoped `production`** (не repo-level — §1 header): доступна лише `deploy-production.yml` jobs з `environment:`, за wait-timer + ref-policy.

**Lazy runtime** (порожній → фіча degraded на першому use, НЕ boot-crash; `verify-secrets` warn):
- [ ] `SENTRY_DSN` · `ETHEREUM_ANCHOR_PRIVATE_KEY` · `ORACLE_CELO_PRIVATE_KEY` (ARCH.50 dedicated, no fallback — порожній = Celo rewards KeyError на першому виклику). Activation-gated aux-підписанти `ORACLE_ETHERISC/PURO/KLIMA_PRIVATE_KEY` — НЕ в GH/Kamal/SDL: Console-інжект при активації шляху (§2.1)
- [ ] RPC: `ALCHEMY_POLYGON_RPC_URL` · `ALCHEMY_ETHEREUM_RPC_URL` · `SOLANA_RPC_URL` · `CELO_RPC_URL` (порожній RPC `web3_network_guard` толерує; testnet-marker — raise)
- [ ] Solana: `SOLANA_WALLET_KEYPAIR` · `SOLANA_FEE_PAYER_PUBKEY` · `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` · `SOLANA_USDC_MINT_ADDRESS`
- [ ] Webhook HMACs: `CHAINLINK_HMAC_SECRET` (callback-endpoint; dispatch вилучено — ARCH.53) · `HELIUM_WEBHOOK_SECRET` (Queen SOS — під `WEB3_STRICT_MODE` контролер raise'ить per-request без нього)

> **🔴 Drift guard:** цей набір = `config/deploy.yml env.secret` = `.kamal/secrets-common` = deploy-workflow `env:` блок. Розбіжність у будь-яку сторону → порожній інжект → boot-crash. Канонічний список — `config/deploy.yml env.secret` (SSOT).

---

## 2. `.kamal/secrets-common` (Kamal Runtime)

> **Шлях:** `.kamal/secrets-common` — **закомічений свідомо** ($VAR-форма: лише посилання на shell-ENV, не raw values — safe-for-git за дизайном Kamal; RAW-значень сюди не вписувати ніколи). Перед `kamal deploy` встанови ці змінні у shell або CI environment. **Чому `-common`, не `secrets` [INF.22]:** з destination (`kamal deploy -d canopy`) Kamal читає ЛИШЕ `secrets-common` + `secrets.<destination>` — плейн `secrets`-файл для destination-запусків невидимий (canopy-нога падала б `Secret not found` на першому ж global env.secret lookup); `-common` живить обидві ноги.

- [ ] `RAILS_MASTER_KEY` — **[B1]** ENV-first: `${RAILS_MASTER_KEY:-$(cat config/master.key)}`. CI бере з GitHub Secret (§1.1; `config/master.key` gitignored → відсутній у checkout); локально fallback на файл.
- [ ] `GCP_ARTIFACT_REGISTRY_KEY` — **[INF.22]** короткоживучий WIF access-token для Kamal push у Artifact Registry (registry username = `oauth2accesstoken` у `config/deploy.yml`), НЕ довгоживучий JSON-ключ. У CI видає auth-крок (`token_format: access_token`); локально — `gcloud auth print-access-token`.
- [ ] `POSTGRES_PASSWORD` — те саме значення що й GitHub Secret (host/user/database → `env.clear`, не secret)
- [ ] `REDIS_URL` — те саме значення
- [ ] `SENTRY_DSN` — Sentry project DSN. Без цього Sentry **інертний** — production помилки не репортуються (BLOCKER у [`00_07`](00_07_Action_Plan_Tracker)). Отримати: Sentry → Project Settings → Client Keys (DSN).

> **`KREDIS_REDIS_URL` виведено [B1]** — Kredis auto-derive DB 1 із `REDIS_URL` (`config/redis/shared.yml`). Не оголошуй у `.kamal/secrets-common` / `env.secret`: порожній або placeholder-інжект truthy для `ENV.fetch` і перебив би derive → Kredis конектиться до сміття. Override лише вказівкою на окремий Redis-інстанс.
- [ ] `PROVISIONING_MASTER_KEY` — HKDF master key для per-device AES key derivation. Генерувати: `ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"`. ⚠️ **Production guard:** provisioning endpoint **MUST** raise/refuse при відсутності ENV у production (`Rails.env.production?`) — будь-який fallback на raw AES key є **критичною security regression** і допустимий ТІЛЬКИ у TRL4 lab mode (`RAILS_ENV=development|test`). Recommended controller-level guard: `raise "PROVISIONING_MASTER_KEY required in production" if Rails.env.production? && ENV["PROVISIONING_MASTER_KEY"].blank?`
- [ ] `CHAINLINK_HMAC_SECRET` — HMAC-SHA256 секрет для верифікації `X-Chainlink-Signature` header у `/api/v1/oracle_callbacks`. Генерувати як `SecureRandom.hex(32)`. (Dispatch-секрети `ROUTER`/`SUBSCRIPTION_ID`/`DON_ID` вилучено — ARCH.53 демоут.)
- [ ] `HELIUM_WEBHOOK_SECRET` — [ARCH.34] HMAC-SHA256 секрет `X-Helium-Signature` для `/api/v1/telemetry/helium` (SOS Королеви; той самий рецепт `SecureRandom.hex(32)`; вписується і у Helium Console HTTP Integration). `WEB3_STRICT_MODE=true` → відсутність = SecurityError. ✅ 2026-07-04 провід заведено НАСКРІЗНО: Kamal `env.secret` + `.kamal/secrets-common` + обидва deploy-workflows (RUNTIME-warn) + Akash SDL web (static + `.tpl` + tf-var) — до того секрет був задекларований лише тут, і кожен Kamal/Akash-деплой гарантовано 500-ив Queen-SOS endpoint.

### 2.1. ENV-only змінні (НЕ у `.kamal/secrets-common`, потрібні воркерам)

> Ці змінні встановлюються через Kamal `env: clear:` або Akash SDL. Не є секретами в строгому сенсі, але без них Web3 пайплайн не працює.

- [ ] `RELEASE_VERSION` — git SHA або release tag для Sentry release tracking. ✅ Налаштовано у deploy pipeline (`deploy.yml`, `deploy-production.yml`, `config/deploy.yml`, `deploy/akash/deploy.yaml`).
- [ ] `ORACLE_ETHERISC_PRIVATE_KEY` · `ORACLE_PURO_PRIVATE_KEY` · `ORACLE_KLIMA_PRIVATE_KEY` — **activation-gated aux-підписанти** [INF.22]: dedicated-ключі `Etherisc::ClaimService` (insurance claim) / `PuroEarth::PassportService` (passport anchor) / `KlimaDao::RetirementService` (воркер DEAD, 0 enqueue). Свідомо **поза** GH/Kamal/SDL/tfvars (placeholder = guard format-raise): при активації шляху — згенерувати ключ, інжектнути в job-ENV (Console + `.kamal/secrets-common`), фондувати MATIC; `Treasury::MonitorService` підхопить **автоматично** (activation-gated `WALLETS`-записи per-signer: відсутній ключ = skip без алерту, present = власний gauge `network`+`signer` + EWS/Grafana-алерт — [`06_03 §2.8`](06_03_Prometheus_Observability)). Легасі спільний `ORACLE_PRIVATE_KEY`, що їх покривав, — **RETIRED** (guard-tripwire; жоден код не читає).
- [ ] `ETHEREUM_ANCHOR_PRIVATE_KEY` — приватний ключ для тижневого SHA-256 state root anchoring на L1. Потребує ETH для газу.
- [ ] `ALCHEMY_POLYGON_RPC_URL` — Alchemy/Infura RPC для Polygon (Primary). `Web3::ResilientClient` підтримує fallback cascade — також встанови `ALCHEMY_POLYGON_RPC_URL_FALLBACK_*` за потреби.
- [ ] `ALCHEMY_ETHEREUM_RPC_URL` — Alchemy RPC для Ethereum L1
- [ ] `SOLANA_RPC_URL` — Solana RPC. ⚠️ **БЕЗ цього ENV дефолт = Solana Devnet** — мікро-винагороди USDC підуть на тестову мережу (`E.47` у [`00_07`](00_07_Action_Plan_Tracker))! Mainnet: Helius/QuickNode. Опц. `SOLANA_RPC_URL_FALLBACK_1/2` — fallback-каскад (INF.22, `Solana::MintingService#execute_rpc_call`); порожні = single-RPC.
- [ ] `CARBON_COIN_CONTRACT_ADDRESS` — адреса SCC контракту після deploy (`BlockchainMintingService`, `ENV.fetch` без default → `KeyError` на першому SCC mint). Тихий споживач (`ChainAuditService` хибне «all clean») → також у boot-guard `address_violations` (presence signer + формат)
- [ ] `FOREST_COIN_CONTRACT_ADDRESS` — адреса SFC контракту після deploy (той самий `ENV.fetch`-патерн → `KeyError` на першому SFC mint; тихий audit-споживач → boot-guard `address_violations`). ✅ placeholder заведено у Kamal env.clear + Akash SDL (INF.12 machine-half; fill = post-`forge deploy`).
- [ ] `KLIMA_RETIREMENT_CONTRACT` — адреса KlimaDAO Retirement Aggregator
- [ ] `DAO_TREASURY_ADDRESS` — DAO Treasury (Dynamic Tax 2% · `BlockchainMintingService` + INS.2 `Insurance::ReserveGate`). ⚠️ **Виняток із «fail-loud on use»**: mint-сайт (E.46 rescue) fail-SILENT — tax тихо OFF, лог хибно «RPC degraded»; ReserveGate — fail-closed hold, але config-баг маскується під transient `:eval_error`. Гучність дає **boot-guard** `Web3NetworkGuard.address_violations` (presence у signer-процесі + формат `0x`+40hex; значення в лог не echo-иться; той самий guard-set покриває SCC/SFC-адреси й Solana-четвірку — [`04_02 §8`](04_02_Business_Logic_and_Services)). Custody = Safe, не EOA — deploy-гейт `_requireSafeOrWarn` ([`05_03` — Admin-Role Split](05_03_Tokenomics_SCC_and_SFC)).
- [ ] `CELO_CUSD_CONTRACT_ADDRESS` — cUSD на Celo (`CommunityRewardService`)
- [ ] `ETHERISC_DIP_CONTRACT_ADDRESS` · `PURO_EARTH_REGISTRY_CONTRACT_ADDRESS` — параметричне страхування / D-MRV registry (Toucan-адресу вилучено — E.66 prune)
- [ ] `ETHEREUM_ANCHOR_CONTRACT` — StateRootAnchor (Ethereum L1, weekly anchor)
- [ ] `PROTOCOL_PARAMETERS_CONTRACT_ADDRESS` — ProtocolParameters.sol (governance sync; `ENV[]` nil-safe → skip-sync)
- [ ] `CELO_RPC_URL` — Celo RPC. ⚠️ **БЕЗ значення → код fallback на Alfajores TESTNET** (реальні cUSD на testnet; E.49). З 2026-07-12 **умовно гейтовано boot-guard'ом**: `ORACLE_CELO_PRIVATE_KEY` присутній ∧ RPC blank → violation (озброєний Celo-шлях без mainnet-RPC не бутиться; неозброєний — чистий). Mainnet: Forno/Alchemy.
> Усі контракт-адреси вище = **post-`forge deploy`** (deploy-order): у Kamal `env.clear` + Akash SDL як `REQUIRED_SECRET_NOT_SET` placeholder, fill після деплою контрактів (INF.12). Публічні on-chain → не секрети, але fail-loud на use поки не задані (виняток — `DAO_TREASURY_ADDRESS`: use-сайти fail-SILENT, гучним його робить boot-guard — див. рядок вище).
- [ ] `SOLANA_USDC_MINT_ADDRESS` — SPL Token mint USDC (mainnet: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`). Solana-четвірка (keypair · fee-payer pubkey · token-account · цей mint) також presence-чекається boot-guard'ом `solana_violations` (signer-процес; batch-payout цикл ковтає per-wallet помилки без escalation — E.61)
- [ ] `FILECOIN_PINNING_API_URL` — Pinata IPFS pinning service URL
- [ ] `WEB3_STRICT_MODE` — `true` у production. У production **АБО** `WEB3_STRICT_MODE=true` (belt-and-suspenders — Hadron harden 2026-07-10) Hadron-stub raise при відсутності ENV + oracle-callback HMAC fail-fast (SEC.5; Chainlink-dispatch більше не STRICT-gated — local marker, ARCH.53). Заведено в `config/deploy.yml` env.clear + Akash `deploy.yaml`/`.tpl` (web+job) (INF.11); canopy успадковує (`RAILS_ENV=production`). Інвентар Akash — §3.1 + [`06_02 §2.8`](06_02_Akash_Network_Integration).
- [ ] `RAILS_ALLOWED_HOSTS` — comma-separated allowlist хостів для захисту від DNS-rebinding атак (підтримує leading `.` для subdomain wildcard, напр. `.silkennet.com` покриє `api.silkennet.com`). **Канон-пара (INF.4 Опція A): `silkennet.app,api.silkennet.com`** — web-хост треба перелічити **явно**: wildcard `.silkennet.com` його НЕ покриває (інший TLD; `ActionDispatch::HostAuthorization` матчить суфікс літерально → 403 block-all на КОЖЕН запит, крім probe-шляхів ↓). Якщо INF.25 піде варіантом B (apex-redirect) — додати й `silkennet.com`. Якщо не встановлено — Rails логує попередження `[SECURITY]` при кожному старті контейнера. Встановлюється через Kamal `env.clear` або Akash SDL. **⚠️ Обов'язково для production.** Probe-шляхи `/up`/`/ready`/`/metrics` виключені і з `host_authorization`, і з `force_ssl`-redirect — single-sourced `probe_paths`/`probe_request` у `production.rb` **[S6.18]** (дрейф однієї копії ламав би deploy health-check за зеленим boot).
- [ ] `APP_HOST` — хост для Action Mailer `default_url_options` (`config/environments/production.rb`; `ENV.fetch("APP_HOST", "silkennet.com")`). Дефолт `silkennet.com`; override для іншого домену. Заведено в `config/deploy.yml` env.clear + Akash web/job (INF.13) — замінив хардкоджений `example.com`. ⚠️ Це хост у ТІЛІ листа — транспорт і відправник окремі, нижче.
- [ ] `MAIL_FROM` — відправник для `ApplicationMailer.default from:` (резолвить `Notifications::DeliveryChannels.configured_sender`). **Обовʼязковий у production** — без нього boot-гард `mail_transport_check.rb` відмовляє в старті (ARCH.60). Мусить бути адресою на домені, для якого нижче стоять SPF/DKIM, інакше лист = спам.
- [ ] `SMTP_ADDRESS` · `SMTP_PORT` (дефолт 587) · `SMTP_USER_NAME` · `SMTP_PASSWORD` — вихідний SMTP (`production.rb` → `config.action_mailer.smtp_settings`). **`SMTP_ADDRESS` обовʼязковий у production** — той самий boot-гард. Вендор-агностично: кожен ESP (Postmark / SES / Mailgun / SendGrid / Resend) говорить звичайним SMTP, тож гем провайдера не потрібен і зміна вендора = зміна цих трьох значень. **Секрети — лише `SMTP_PASSWORD` (і, залежно від ESP, `SMTP_USER_NAME`).**
- [ ] `TELEGRAM_BOT_TOKEN` — токен бота ([ARCH.60] Telegram-канал алертів; видає BotFather безкоштовно). **Опційний, НЕ boot-critical:** порожній = канал чесно вимкнено (`Notifications::TelegramTransport.configured?` — форматна перевірка, тож деплой-плейсхолдер читається як «вимкнено», не як живий канал). Секрет.
- [ ] `SMTP_DOMAIN` — HELO-домен; опційний, але деякі провайдери відкидають імʼя контейнера, яке `Net::SMTP` інакше оголошує. Не секрет.
- [ ] `SMTP_AUTHENTICATION` — дефолт `plain`; `login` для SES та деяких інших. Не секрет.
- [ ] `SILKENNET_SKIP_MAIL_TRANSPORT_CHECK` — `1` щоб свідомо задеплоїти БЕЗ пошти (boot-гард пропускає з гучним WARN). ⚠️ Тоді password-reset і критична тривога на цьому деплої мертві — ставити лише як тимчасовий вибір, не як норму.
- [ ] `COAP_HOST` — адреса CoAP-інтейку для проби адмін-панелі здоров'я (ARCH.81; `api.silkennet.com` — **та сама**, яку набирає прошивка Королеви `COAP_SERVER_HOST`, тобто A-запис на Ingress Anchor із кроку 1 чеклісту [`06_01`](06_01_Deployment_Kamal_Terraform)). Заведено в `config/deploy.yml` env.clear + Akash web (`deploy.yaml`/`.tpl`). **Не секрет.** Якщо не задано — панель чесно рапортує `not_configured`; вона НІКОЛИ не називає інтейк мертвим лише тому, що не мала куди подивитись. Демон живе поза Rails-процесом (PRIMARY — анкер, [`06_03 §2.9(б)`](06_03_Prometheus_Observability)), тож loopback-дефолту тут свідомо немає.
- [ ] `DISABLE_SSL` — встановлювати лише `true` якщо TLS термінується зовнішнім проксі (Cloudflare Full-Strict, Akash ingress) і Rails сам не повинен форсувати HTTPS. За замовчуванням (`false` або відсутнє) `force_ssl` та `assume_ssl` активні. Встановлюється через Kamal `env.clear`.
- [ ] `ALLOW_ALL_HOSTS` — встановлювати `true` щоб заглушити попередження `[SECURITY]` про відсутній `RAILS_ALLOWED_HOSTS` (наприклад, якщо хости динамічні на Akash deployment). Не рекомендується без явного RAILS_ALLOWED_HOSTS.
- [ ] `CSP_ENFORCE` — встановлювати `true` щоб перевести Content Security Policy з `report-only` у `enforced` режим. Рекомендується після спостереження CSP violation-репортів протягом 1–2 тижнів у production.

### 2.2. `credentials.yml.enc` ключі (Rails encrypted credentials — розшифровуються `RAILS_MASTER_KEY`)

> Встановлюються через `bin/rails credentials:edit` (НЕ ENV). Відсутність → `nil`-помилки або explicit raise у відповідному сервісі **при виклику** (не на boot). `RAILS_MASTER_KEY` (§1) лише розшифровує файл — його вмісту не інвентаризує. Перевірено grep'ом `credentials.*` по `app/`+`config/`.

- [ ] `aws.access_key_id` / `aws.secret_access_key` — S3 Active Storage (`config/storage.yml` `amazon`; `credentials.dig(:aws, …)`)
- [ ] `gcs` — GCS keyfile JSON-hash (Active Storage mirror, `config/storage.yml` `google`; `credentials.dig(:gcs)`)
- [ ] `peaq_signing_key` / `peaq_node_url` — Ed25519 ключ + RPC для peaq DID (ротація 90д → §5.4)
- [ ] `iotex_w3bstream_url` / `iotex_api_key` — IoTeX W3bStream верифікація
- [ ] `streamr_stream_id` / `streamr_api_key` — Streamr broadcast
- [ ] `hadron_api_key` — Hadron KYC compliance
- [ ] `filecoin_api_key` — Pinata/Filecoin архівація
- [ ] `puro_earth.api_key` — Puro.earth registry · `dclimate.api_key` — dClimate верифікація
- [ ] `the_graph_api_url` — The Graph query endpoint
> 🗄️ **`smtp.user_name` / `smtp.password` виведено звідси 2026-08-14 (ARCH.60):** транспорт пошти ENV-керований, імена — `SMTP_USER_NAME` / `SMTP_PASSWORD` у §2.1. Рядок стояв тут, поки `production.rb` ніс закоментований credentials-скаффолд; він ніколи не був живим — `smtp_settings` не задавались узагалі.

---

## 3. Akash SDL (`deploy/akash/deploy.yaml` + `deploy.yaml.tpl`)

> **Статус:** SDL містить `REQUIRED_SECRET_NOT_SET` плейсхолдери для критичних змінних — відкрите [`00_07`](00_07_Action_Plan_Tracker) **S4.3** (Akash SDL secrets; деталі — [`06_02 §Секрети SDL`](06_02_Akash_Network_Integration)).
>
> **Рекомендований workflow:** використовувати `deploy/akash/deploy.yaml.tpl` Terraform-шаблон — секрети підставляються автоматично з `terraform.tfvars`.
>
> **Принцип:** SDL `web` та `job` сервіси мають **ідентичні** ENV-блоки з **двома** класами винятків: (1) web-specific `WEB_CONCURRENCY` / `PORT`; (2) 🔴 **money/signing-п'ятірка — JOB-ONLY** (INF.22, 2026-07-04): `ORACLE_MINTER_PRIVATE_KEY` · `ORACLE_SLASHER_PRIVATE_KEY` · `ORACLE_CELO_PRIVATE_KEY` · `ETHEREUM_ANCHOR_PRIVATE_KEY` · `SOLANA_WALLET_KEYPAIR` **не заводяться у `web` взагалі**. Причина несуча: Akash SDL ENV — **plaintext для провайдера**, а кожен signing-call-site = Sidekiq-воркер, тож інтернет-обернена web-поверхня не має підстав нести ключі (`deploy/akash/deploy.yaml` несе цей інваріант коментарем у web-сервісі; boot-guard scoped через `Security::Web3NetworkGuard`, `signer_process: Sidekiq.server?`). Решта — Sidekiq у `job`-сервісі ходить через ті ж Rails initializers, що вимагають boot-critical guards.

### 3.1. Web service env (та дзеркало в Job service env)

**Application core (boot):**
- [ ] `RAILS_MASTER_KEY` — те саме що в Kamal
- [ ] `POSTGRES_HOST`=`127.0.0.1` / `POSTGRES_USER`=`silken_net` / `POSTGRES_PASSWORD` / `POSTGRES_DATABASE`=`silken_net_production` — Cloud SQL через Auth Proxy sidecar (component style; host/user/database non-secret, лише пароль секрет). **[H2]** `POSTGRES_DATABASE` тепер explicit у SDL (web+job) — canopy-on-Akash render override на `silken_net_canopy`.
- [ ] `CLOUD_SQL_INSTANCE_CONNECTION_NAME` — `<project>:<region>:<instance>`
- [ ] `GCP_SA_KEY_BASE64` — base64-encoded GCP SA JSON (роль `roles/cloudsql.client` only)
- [ ] `REDIS_URL` — Upstash Redis DB 0 (`rediss://`). **[B1]** `KREDIS_REDIS_URL` НЕ в SDL — Kredis auto-derive DB 1 (`config/redis/shared.yml`).
- [ ] `RAILS_ENV` — `production` або `canopy`
- [ ] `RAILS_MAX_THREADS` — типово `3` (узгоджено з `database.yml` pool)
- [ ] `WEB_CONCURRENCY` — кількість Puma workers (web only, типово `4`)
- [ ] `PORT` — типово `80` (Thruster)
- [ ] `TURBO_SIGNED_STREAM_KEY` — ключ підпису імен Turbo-стрімів [SEC.25]. Generate: `SecureRandom.hex(32)`. ⚠️ **Не boot-critical і саме тому легко загубити:** без нього гем деривує ключ із `secret_key_base`, застосунок працює нормально — зникає лише **важіль відкликання** (§5.9 Крок 4б), тобто єдиною відповіддю на витік record-form адреси лишається ротація `secret_key_base` з усім її колатералом. Boot-guard'а свідомо нема (щоб забутий секрет не валив деплой), тож цей рядок і є єдиним сторожем. Мусить бути **однаковий на web + job** — інакше підписи розійдуться між процесами й живі оновлення тихо помруть.

**🛑 Boot-critical (Puma crash до accept loop без значення):**
- [ ] `PROVISIONING_MASTER_KEY` — HKDF root key. `config/initializers/master_key_strength_check.rb` raises `SecurityError` у `after_initialize`. Generate: `ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"`

**Observability:**
- [ ] `SENTRY_DSN` — без неї Sentry inert (silent prod errors)
- [ ] `RELEASE_VERSION` — git SHA / release tag для Sentry release tracking
- [ ] `PROMETHEUS_AUTH_USER` / `PROMETHEUS_AUTH_PASSWORD` — Basic Auth для `/metrics`

> 🔴 **Web3 money/signing-ключі тут НЕ заводяться** — вони JOB-ONLY (§3.2, INF.22). Не «продзеркалюй» їх у web, навіть якщо решта блоку дзеркалиться: web-ENV видимий Akash-провайдеру plaintext.

**RPC endpoints (`Web3::RpcConnectionPool` — `ENV.fetch` raises KeyError без значення):**
- [ ] `ALCHEMY_POLYGON_RPC_URL`
- [ ] `ALCHEMY_ETHEREUM_RPC_URL`
- [ ] `SOLANA_RPC_URL`

> **Boot guard:** `config/initializers/web3_network_guard.rb` ([`04_02 §8`](04_02_Business_Logic_and_Services)) fail-closes at boot у production / `WEB3_STRICT_MODE`, якщо `ORACLE_*` ключ відсутній/malformed **або** будь-який `*_RPC_URL` несе testnet-маркер (Amoy / devnet / Sepolia) — перетворює «Sidekiq DeadSet» / «mint на testnet» на гучний boot-refuse ДО прийому трафіку (розширює `E.47` на boot-time + EVM).

**Solana minting (`Solana::MintingService` raises explicit errors):**
- [ ] `SOLANA_WALLET_KEYPAIR` — 64-byte hex keypair
- [ ] `SOLANA_FEE_PAYER_PUBKEY` — base58
- [ ] `SOLANA_FEE_PAYER_TOKEN_ACCOUNT` — USDC ATA, base58
- [ ] `SOLANA_USDC_MINT_ADDRESS` — base58 (mainnet: `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`)

**Chainlink oracle-callback HMAC (dispatch вилучено — ARCH.53):**
- [ ] `CHAINLINK_HMAC_SECRET` — HMAC-SHA256 для callback signature verification

### 3.2. Job (Sidekiq) service env

- [ ] **Усе з §3.1** (Sidekiq потребує boot-critical guards так само як Puma) — окрім `PORT` / `WEB_CONCURRENCY`.

**🔴 Money/signing-п'ятірка — ЛИШЕ тут, ніколи у web** (INF.22, 2026-07-04; dual-key split B-02 — без них Sidekiq DeadSet; legacy `ORACLE_PRIVATE_KEY` retired). Кожен signing-call-site — Sidekiq-воркер, тож web-копія не давала б нічого, крім зайвої експозиції:
- [ ] `ORACLE_MINTER_PRIVATE_KEY` — MINTER_ROLE на SCC/SFC (`BlockchainMintingService`)
- [ ] `ORACLE_SLASHER_PRIVATE_KEY` — SLASHER_ROLE (`BlockchainBurningService`)
- [ ] `ORACLE_CELO_PRIVATE_KEY` — **[ARCH.50]** dedicated Celo cUSD-підписант (no fallback); ізолює blast-radius Celo від Polygon-флоту (ARCH.49)
- [ ] `ETHEREUM_ANCHOR_PRIVATE_KEY` — окремий wallet для weekly L1 anchor (`Ethereum::StateAnchorService`)
- [ ] `SOLANA_WALLET_KEYPAIR` — Ed25519 keypair мікро-виплат (`Solana::*`)
- [ ] `DB_POOL` — **лише job-роль.** Sidekiq concurrency=15 (`config/sidekiq.yml`); дефолтна `database.yml` формула (`RAILS_MAX_THREADS+2 = 5`) → `ActiveRecord::ConnectionTimeoutError` під навантаженням. Встанови `DB_POOL=17` (concurrency + 2 headroom). Заведено в `config/deploy.yml` job env + Akash `deploy.yaml` job (INF.13). **НЕ** виставляй на web-ролі (Puma threads = `RAILS_MAX_THREADS+2`, коректно).

> **⚠️ AKASH ENV plaintext exposure:** Akash не шифрує ENV-блок SDL — значення видимі провайдеру через `lease-logs`/kubectl. Mitigation, у порядку сили: (1) 🔴 **surface-minimization — money-п'ятірка взагалі відсутня у `web`** (INF.22; ключ, якого немає в контейнері, не витікає з нього — решта пунктів лише зменшують наслідки, цей прибирає поверхню); (2) scoped on-chain roles (MINTER/SLASHER only, ніколи DEFAULT_ADMIN); (3) 90-day key rotation; (4) audited providers (`signedBy.anyOf`). Детальніше: [`06_02 §Секрети SDL (Akash ENV plaintext)`](06_02_Akash_Network_Integration).

### 3.3. Grafana Alloy sidecar (observability)

- [ ] `ALLOY_CONFIG_BASE64` — base64-encoded Alloy config
- [ ] `GRAFANA_REMOTE_WRITE_URL` — Grafana Cloud Prometheus endpoint
- [ ] `GRAFANA_REMOTE_WRITE_USERNAME` — Grafana Cloud user/instance ID
- [ ] `GRAFANA_REMOTE_WRITE_TOKEN` — Grafana Cloud API token
- [ ] `PROMETHEUS_AUTH_USER` / `PROMETHEUS_AUTH_PASSWORD` — Basic auth для `/metrics` endpoint
- [ ] `PROMETHEUS_ALLOWED_IPS` — **[INF.5]** Comma-separated CIDR allowlist для `/metrics` endpoint у `PrometheusCollector` middleware (`app/middleware/prometheus_collector.rb`). Запити з адрес поза `PRIVATE_RANGES` (RFC 1918/4193 + localhost) ТА поза цим списком отримають `403 Forbidden`. Приклади:
  - **GCP-only Kamal:** залишити пустим — внутрішня VPC IP належить RFC 1918 (`10.x`), уже allowed.
  - **Akash deployment:** залежить від cluster network — Akash може дати немутальний CIDR. Дізнатись фактичний pod-CIDR можна лише з боку провайдера (`akash provider lease-status` / логи) — Terraform-output для цього НЕ існує. Приклад: `PROMETHEUS_ALLOWED_IPS=10.42.0.0/16,10.43.0.0/16`.
  - **Cloudflare Proxy:** додати [Cloudflare IP ranges](https://www.cloudflare.com/ips/) якщо scrape йде через CF. Приклад: `PROMETHEUS_ALLOWED_IPS=173.245.48.0/20,103.21.244.0/22,...`.
  - **Grafana Cloud direct scrape:** не використовуйте direct scrape з `/metrics`; використовуйте Alloy `prometheus.remote_write` — внутрішній push не потребує allowlist.

---

## 4. `terraform/terraform.tfvars`

> **Шлях:** `terraform/terraform.tfvars` (`*.tfvars` у `.gitignore` — **ніколи не комітити!**)

**Інфраструктура GCP:**
- [ ] `project_id` — GCP project ID
- [ ] `db_password` — пароль Cloud SQL (≥16 символів)
- [ ] `iap_admin_members` — хто входить на Ingress Anchor (INF.20 (в): IAP-тунель keyless; напр., `["user:you@example.com"]` → osAdminLogin+tunnelResourceAccessor)
- [ ] `ssh_source_ranges` — break-glass-only CIDR (normally `[]` — канонічний SSH-шлях = IAP, правило `allow-ssh` без значень не створюється)
- [ ] `billing_account_id` (+опц. `billing_budget_usd`) — **[OPS.11]** budget-guard; порожній = no-op; заповнив → той самий id у GH-секрет `GCP_BILLING_ACCOUNT_ID` (§1.2), інакше CI-apply знесе бюджет

**Akash deployment app/infra (`terraform/akash/terraform.tfvars` рендериться у `deploy.yaml.tpl`):**

> Mirror зі списку `env.secret` Kamal — повний breakdown див. [`06_02 §3.2 Змінні Terraform`](06_02_Akash_Network_Integration). Sensitive variables нижче.

*Application core:*
- [ ] `rails_master_key`
- [ ] `db_password` — Cloud SQL пароль (host=`127.0.0.1` proxy + user `silken_net` — non-secret SDL-літерали; component style, INF.16)
- [ ] `cloud_sql_instance_connection_name` — `terraform output database_connection_name`
- [ ] `gcp_sa_key_base64` — base64-encoded SA JSON (роль `roles/cloudsql.client` only, див. [`06_02 §Security Exception`](06_02_Akash_Network_Integration))
- [ ] `redis_url` — Upstash `rediss://...:6379` (DB 0)
> **[B1]** `kredis_redis_url` variable видалено з `terraform/akash/variables.tf` + `main.tf` — Kredis auto-derive DB 1 із `redis_url` (`config/redis/shared.yml`); SDL більше не інжектить `KREDIS_REDIS_URL`.

*🛑 Boot-critical:*
- [ ] `provisioning_master_key` — `SecureRandom.hex(32)`, валідація `length >= 32`

*Observability:*
- [ ] `sentry_dsn`
- [ ] `alloy_config_base64` — base64-encoded Grafana Alloy config (містить вбудований `grafana_remote_write_token` — sensitive!)
- [ ] `grafana_remote_write_url` — Grafana Cloud Prometheus `remote_write` endpoint (`https://prometheus-prod-XX-XX.grafana.net/api/prom/push`)
- [ ] `grafana_remote_write_username` — Grafana Cloud Stack ID
- [ ] `grafana_remote_write_token` — Grafana Cloud API ключ зі scope `metrics:write`
- [ ] `prometheus_auth_user` — Basic Auth user для `/metrics` endpoint
- [ ] `prometheus_auth_password` — Basic Auth password (`Rails.application.config.prometheus_auth`)

*Web3 oracle keys (dual-key split, B-02; легасі `oracle_private_key` RETIRED [INF.22] — значення під старим ім'ям = guard-violation):*
- [ ] `oracle_minter_private_key` — hex `0x…`
- [ ] `oracle_slasher_private_key` — hex `0x…` (MUST differ from minter — E.2; boot-guard колізії + deploy-гейт `_requireDistinctOracles`)
- [ ] `ethereum_anchor_private_key` — hex `0x…` (MUST differ from minter/slasher)

*RPC endpoints:*
- [ ] `alchemy_polygon_rpc_url`
- [ ] `alchemy_ethereum_rpc_url`
- [ ] `solana_rpc_url`

*Solana minting:*
- [ ] `solana_wallet_keypair`
- [ ] `solana_fee_payer_pubkey`
- [ ] `solana_fee_payer_token_account`
- [ ] `solana_usdc_mint_address`

*Chainlink oracle-callback HMAC (dispatch вилучено — ARCH.53):*
- [ ] `chainlink_hmac_secret`

> **🔴 Drift guard:** Кожен sensitive у `terraform.tfvars` **обов'язково** на момент `terraform apply` — без нього `templatefile()` рендерить порожні рядки → SDL отримує `=` без value → Rails отримує `nil` ENV. Для boot-critical (`provisioning_master_key`) це Puma crash; для Web3 — Sidekiq DeadSet; для Alloy — німі метрики. Drift у будь-яку сторону між `.kamal/secrets-common`, Kamal `env.secret`, SDL (`web` + `job`), `deploy.yaml.tpl`, `variables.tf`, та `main.tf` `templatefile()` — критичний bug. **Single source of truth: `config/deploy.yml env.secret` блок** (Kamal canonical list).

---

## 5. Operational Procedures

### 5.1. Перед першим деплоєм Production

> **One-Home: порядок дня деплою живе у [`06_01 §DEPLOY-DAY`](06_01_Deployment_Kamal_Terraform)** (фази −1…6) — старий 8-кроковий список тут суперечив 06_01-порядку (секрети до/після apply). Секрет-специфіка, яку тримає ЦЕЙ дім:
>
> - **GitHub Secrets = дві партії:** Batch A (pre-infra, ДО `terraform apply`): `GCP_PROJECT_ID` · `POSTGRES_PASSWORD` · `RAILS_MASTER_KEY` · `PROVISIONING_MASTER_KEY` · `ACTIVE_RECORD_ENCRYPTION_*`×3 (§1.1 — генеруються `db:encryption:init` будь-коли, boot-critical на kamal-етапі) (SSH-секретів НЕМАЄ — INF.20 (в): IAP+OS Login keyless; `GCP_SA_KEY` НЕМАЄ — CI keyless через WIF, INF.22: після 1-го apply зчитай `workload_identity_provider`/`service_account_email` у repo **Variables** `GCP_WORKLOAD_IDENTITY_PROVIDER`/`GCP_SERVICE_ACCOUNT`). Batch B (post-infra, значення існують лише ПІСЛЯ apply/акаунтів): `REDIS_URL`/`CANOPY_REDIS_URL` (Upstash ×2 — Фаза −1) · RPC×5 · Solana-public×3 · `SENTRY_DSN` · webhook-HMACs — repo-level; **money/signing-п'ятірка** (oracle×3: MINTER/SLASHER/CELO + anchor + Solana keypair; legacy `ORACLE_PRIVATE_KEY` retired повністю — §1 header) — **[INF.22] НЕ repo-level: environment `production`** (`gh secret set <NAME> --env production`; §1 header — wait-timer + ref-policy вже сконфігуровані API).
> - `.kamal/secrets-common` вже закомічений ($VAR-форма) — «створювати» його не треба; треба заповнити shell-ENV (CI робить це сам з GitHub Secrets).
> - Akash SDL секрети — через `.tpl` + `terraform/akash/terraform.tfvars` (§3/§4); gas на гаманцях — Фаза −1/4.

### 5.2. Ротація секретів

- **`PROVISIONING_MASTER_KEY`** (HKDF root, **6** key classes): планова ротація потребує перевипуску всіх деривованих ключів через provisioning — per-device (KEYL session, K_seed, KEYC) + per-cluster (K_ota, KEYB — FW.2 (в)) + backend-only (**iotex_seed** Ed25519 W3bstream — єдиний клас без hardware-persistence, ротується redeploy'єм); несумісно зі вже зашитими пристроями (rotation = fleet re-flash). Plan: `FW.17` (Hash Ratchet KDF, session-only) у майбутньому циклі. ⚠️ **On-compromise = crown-jewel, effectively un-rotatable сьогодні** (fleet re-flash + усі деривовані ключі — Opus-sweep 2026-07-09); справжній latch = GCP-KMS-MAC (ключ не покидає HSM) → `SEC.22` (pre-mainnet). **Порядок дій при компрометації → §5.8-A.**
- **`RAILS_MASTER_KEY`** / **`secret_key_base`**: планової ротації немає; on-compromise **entangled** — ротація master-key re-encrypt'ить `credentials.yml.enc`, але той самий `secret_key_base` лишається → атакер зберігає session/cookie-forge; щоб revoke, треба ротувати й `secret_key_base`, що invalidate'ить УСІ сесії + `generates_token_for`-токени (найдовший хвіст — `api_access` 30 днів) + CSRF/ActiveStorage signed IDs. **Порядок дій → §5.8-B** (`SECRET_KEY_BASE`-env-detach механіка — §5.7 Phase-2).
- **Database password**: змінити Cloud SQL → оновити `POSTGRES_PASSWORD` GitHub Secret (живить Kamal `POSTGRES_PASSWORD` + Terraform `TF_VAR_db_password`) → `kamal redeploy`.
- **Sentry DSN**: rotate у Sentry UI → оновити `SENTRY_DSN` → redeploy.
- **Chainlink HMAC**: координовано з backend deploy (зміна на льоту викличе rejected callbacks).
- **Oracle/Anchor private keys**: deploy новий гаманець → revoke старий → перевести залишок газу → redeploy.
- **peaq_signing_key** (Ed25519 DID signing): планова ротація кожні 90 днів або при зміні персоналу. Dual-Key Grace Period 72 години (див. §5.4 нижче та [`04_02 §S6.14`](04_02_Business_Logic_and_Services)).

### 5.3. Аудит виконання

**Live GitHub-scope preflight (S1.1 verify-half)** — `scripts/audit_deploy_secret_scope.rb`
запусти ПІСЛЯ заведення секретів, ДО першого деплою. Read-only через `gh` (віддає лише
**імена**, не значення — value-safe): стверджує scope-інваріанти, яких `verify-secrets`
(CI, presence-only) не ловить — money-квінтет ∈ Environment `production` **тільки** (repo-level
копія = R3c isolation breach, deploy лишається зеленим), retired `ORACLE_PRIVATE_KEY` ∉ ніде,
WIF-ids = repo **Variables** (не Secrets). Не CI-гейт (потребує admin-token + заведені секрети);
доповнює, не заміняє §1. `--self-test` = класифікатор offline без `gh`.

```bash
ruby scripts/audit_deploy_secret_scope.rb              # live scope-audit (exit 0/1/2)
ruby scripts/audit_deploy_secret_scope.rb --self-test  # класифікатор, без gh

# Статичні перевірки (файлові): референси у workflows
grep -rh "secrets\." .github/workflows/ | grep -oP "secrets\.[A-Z_]+" | sort -u
# Kamal secrets
grep -E "^[A-Z][A-Z0-9_]*=" .kamal/secrets-common | cut -d= -f1 | sort -u
# Akash SDL
grep -E "^\s+[A-Z_]+:" deploy/akash/deploy.yaml | head -50
```

### 5.4. Emergency Revocation Runbook — `peaq_signing_key` (S6.14)

> **Threat Model:** Компрометація `peaq_signing_key` дозволяє зловмиснику реєструвати фейкові DIDs на peaq network від імені SilkenNet. Кожен фейковий DID може бути прив'язаний до неіснуючого дерева → фейковий Proof of Growth → несанкціонований мінтинг SCC.

#### Крок 1: Detection (моніторинг)

Ознаки компрометації:
- Аномальні `POST /provisioning/register` запити без відповідного hardware provisioning flow
- DIDs зареєстровані в peaq мережі, які не мають відповідних `Tree` записів у БД
- Незвичні патерни: масова реєстрація DIDs, реєстрація з невідомих IP

```bash
# Аудит DID реєстрацій за останні 24 години
bin/rails runner "
  recent = Tree.where('peaq_did IS NOT NULL AND created_at > ?', 24.hours.ago)
  puts \"DIDs registered last 24h: #{recent.count}\"
  recent.find_each { |t| puts \"  #{t.did} -> #{t.peaq_did} at #{t.created_at}\" }
"
```

#### Крок 2: Containment (< 15 хвилин)

**2a. Негайна заміна ключа в credentials:**

> ⚠️ **ENV-first (SEC.22, §5.7/§5.8):** сервіс читає `ENV["PEAQ_SIGNING_KEY"].presence || credentials.peaq_signing_key` — якщо ключ заведено в deploy-ENV (GitHub Secret / Kamal / SDL), `credentials:edit` **НЕ ротує активне значення** (ENV перемагає). Спочатку перевір і ротуй ENV-поверхні, credentials — другим.

```bash
RAILS_CREDENTIALS_EDITOR=vim bin/rails credentials:edit
# 1. Скопіювати поточний peaq_signing_key → peaq_signing_key_previous
# 2. Згенерувати новий ключ:
#    ruby -e "require 'securerandom'; puts SecureRandom.hex(32)"
# 3. Замінити peaq_signing_key на новий ключ
# 4. Зберегти та вийти
```

**2b. Негайний redeploy:**

```bash
# Zero-downtime deploy через Kamal
kamal deploy

# АБО якщо потрібен лише перезапуск додатку (без нового Docker image):
kamal app boot
```

**2c. (Опціонально) Тимчасова зупинка реєстрації:**

Якщо масштаб компрометації невідомий — тимчасово заблокувати provisioning endpoint:

```bash
# Додати feature flag або ENV
# В production console:
bin/rails runner "Rails.cache.write('provisioning_suspended', true, expires_in: 24.hours)"
```

#### Крок 3: Investigation (аудит)

```bash
# Визначити часовий діапазон компрометації
bin/rails runner "
  # Всі DID реєстрації за останній тиждень (або з моменту підозри)
  compromise_start = Time.parse('2025-XX-XXTXX:XX:XXZ')  # замінити на estimated time
  compromise_end   = Time.current

  suspect_trees = Tree.where(
    'peaq_did IS NOT NULL AND created_at BETWEEN ? AND ?',
    compromise_start, compromise_end
  )
  puts \"Potentially compromised DIDs: #{suspect_trees.count}\"
  suspect_trees.find_each do |t|
    puts \"  Tree ##{t.id}: did=#{t.did}, peaq_did=#{t.peaq_did}, org=#{t.organization_id}\"
  end
"
```

Перевірити:
- Чи є відповідний `HardwareKey` для кожного підозрілого `Tree`
- Чи є `TelemetryLog` записи від цих пристроїв
- Чи збігається `peaq_did` з тим, що зареєстровано на peaq chain (cross-reference через `peaq_node_url`)

#### Крок 4: Recovery

> ✅ **Реалізовано (SEC.13, 2026-05-29):** колонка `trees.peaq_did_compromised` (structure.sql) + skip-guard у `BlockchainMintingService` (мінтинг **пропускає** flagged-дерева, не валить весь батч) + spec. Команди нижче робочі. Defense-in-depth під час інциденту: додатково Крок 2c (suspend provisioning) + ротація `ORACLE_MINTER_PRIVATE_KEY`.

```bash
# Позначити потенційно компрометовані DIDs
bin/rails runner "
  compromise_start = Time.parse('2025-XX-XXTXX:XX:XXZ')
  compromise_end   = Time.parse('2025-XX-XXTXX:XX:XXZ')

  affected = Tree.where(
    'peaq_did IS NOT NULL AND created_at BETWEEN ? AND ?',
    compromise_start, compromise_end
  )
  affected.update_all(peaq_did_compromised: true)
  puts \"Flagged #{affected.count} trees as peaq_did_compromised\"
"
```

- Заблокувати мінтинг для compromised DIDs (guard clause в `BlockchainMintingService`)
- За необхідності — повторно зареєструвати легітимні DIDs з новим ключем

#### Крок 5: Post-Incident

1. **Ротація пов'язаних секретів:**
   - M2M tokens (якщо gateway використовував той самий credentials файл)
   - API keys, якщо є підозра на ширшу компрометацію credentials
   - `RAILS_MASTER_KEY` (якщо вектор атаки — витік master key)

2. **Документація інциденту:**
   - Timeline компрометації
   - Кількість affected DIDs
   - Root cause analysis
   - Corrective actions

3. **Превентивні заходи:**
   - Увімкнути scheduled rotation (кожні 90 днів) — [`04_02 §S6.14`](04_02_Business_Logic_and_Services)
   - Налаштувати alerting на аномальні provisioning патерни
   - Money-mint-key custody: **GCP-KMS remote-signer** — custody-поріг вирішено (§5.5)

> **Зв'язок:** Key Rotation Policy → [`04_02 §S6.14`](04_02_Business_Logic_and_Services)

### 5.5. Money-mint-key custody — GCP-KMS remote-signer (SEC.17)

**Рішення (2026-07-06):** приватники `ORACLE_MINTER_PRIVATE_KEY`/`ORACLE_SLASHER_PRIVATE_KEY` (та решта oracle-ключів) живуть **plaintext у deploy-ENV** — у момент mint'у за реальну вартість ENV-ключ мінтера/слешера = найбільша одинична точка катастрофи. Custody-поріг вирішено: **GCP Cloud KMS remote-signer** (asymmetric secp256k1) — ключ ніколи не покидає HSM, backend шле лише digest. Обрано над Fireblocks (enterprise-cost; забирає broadcast/nonce → перетин з `BlockchainConfirmationWorker`/ARCH.47-lock) і Safe-module-mint (on-chain роль + relayer = знову ключ; це admin-вектор SEC.1, не hot-mint): KMS = HSM-grade + дешево (~$0.06/ключ/міс) + автоматизований hot-path + GCP уже в стеку.

**Impl-план (🤖, pre-mainnet — захищає ключ у момент mint реальної вартості; до prod-mint ENV-ключ теж нічого не мінтить, тож НЕ TRL-3-блокер):**

1. **`Web3::OracleSigner` seam** — eth-gem `client.transact(sender_key:)` хардкодить локальний `Eth::Key` (KMS не має чим його повернути), тож потрібен інтерфейс `address` + `transact(...)` + `static_call(...)` навколо 7 signing-сервісів (minting/burning/celo/puro/klima/etherisc/anchor; 12 call-sites, minting сам 5 — 4 `transact` + 1 `call` (число переміряно проти дерева 2026-08-26; доти тут стояло 6)). `LocalEnvSigner` (default) делегує as-is — behavior-preserving, дзеркало SEC.3 master-key DI.
2. **`Web3::KmsSigner`** — залежність `google-cloud-kms`; `digest → asymmetric_sign(EC_SIGN_SECP256K1_SHA256) → DER-decode(r,s) → enforce low-s (EIP-2) → recovery-id (brute v=0/1 vs address)`. Crypto-шар offline-тестовний (локальний `Eth::Key` як фейк-KMS: sign→DER→decode→звірка recovered address); live round-trip = deploy-verify.
3. **KMS keyring/key + IAM** — підписує лише **job**-процес (web/coap money-ключів не тримають — `web3_network_guard` `signer_process:`); ENV `ORACLE_MINTER_KMS_KEY`/`ORACLE_SLASHER_KMS_KEY` (KMS resource-path) активують KMS-backend, default = `LocalEnvSigner` (поточна ENV-поведінка).

Cross-ref: [`00_07`](00_07_Action_Plan_Tracker) SEC.17 (стан/тригер), E.2 role-split [`05_03`](05_03_Tokenomics_SCC_and_SFC), SEC.3 master-key DI-патерн.

### 5.6. Disk-encryption CMEK + KMS keyring architecture (GCP-0033)

**Рішення (2026-07-09):** boot-disk Ingress Anchor'а тримає `coap.env` (`RAILS_MASTER_KEY` + AR-encryption-ключі; **НЕ** `PROVISIONING_MASTER_KEY` — INF.17 2026-07-10 прибрав його з coap, fleet-forge root off анкора) at-rest. Поверх дефолтного GMEK — **CMEK** (`terraform/kms.tf`: keyring `silken-disk-ew1`, key `anchor-boot`, symmetric) для key-lifecycle-контролю (disable/rotate/audit/crypto-shred). Wrap DEK робить **Compute Engine Service Agent** (`service-<num>@compute-system`, key-level encrypter/decrypter — **НЕ** deploy-SA; `google_project_service_identity` compute-excluded → constructed string + `depends_on` compute-API). SHIPPED pre-deploy (timing: `kms_key_self_link`=ForceNew → на живий VM = replacement; до 1-го apply = нуль-cost).

**KMS keyring architecture (one-home, всі ключі) — ТРИ isolated keyring'и** (blast-radius-бар'єр: роль на одному не тече на sibling):

| Keyring | Key | Purpose · grantee (key-level IAM) | Стан |
|---|---|---|---|
| `silken-disk-ew1` | `anchor-boot` | ENCRYPT_DECRYPT · compute service-agent | ✅ shipped |
| `silken-sign-ew1` | `oracle-minter`/`slasher` | ASYMMETRIC_SIGN secp256k1 · job signer-SA | 🔗 SEC.17 (§5.5), pre-mainnet |
| `silken-tfstate-ew1` | `tfstate` | ENCRYPT_DECRYPT · **GCS service-agent** | ✅ shipped 2026-07-10 (bootstrap-owned, [SEC.22]) |

Separation тримається на: key-level IAM (не keyring-level); `purpose`-enum = hard type-barrier (symmetric НЕ підписує, asymmetric НЕ wrap'ить disk → key-role-confusion структурно неможлива; residual IAM-scope знято keyring-split'ом); E.2 mint⊥burn (окремі CryptoKey). Усі — `europe-west1` (EU at-rest pin; для tfstate це ще й hard KMS↔GCS same-region constraint). Архітектурний дім — `terraform/kms.tf` header (SEC.17 додає sign-keyring без rename). **НЕ** робити generic `silken-kms` (blast-radius-merge trap).

**tfstate-CMEK latch ([SEC.22], 2026-07-10):** GCS-state = **третя** повна plaintext-копія секретів, які terraform торкається (`db_password` тече туди на кожному CI plan/apply) — після Akash-ENV та `coap.env`. Латч живе у `terraform/bootstrap.sh` **out-of-band** (chicken-and-egg: backend-bucket потребує ключ ДО `terraform init`, тому keyring/key створює gcloud, не `kms.tf`; для terraform він drift-invisible — `import`, якщо колись знадобиться). Складники: default-CMEK на `silken-net-terraform-state` + `--public-access-prevention` + versioning-retention підрізано **30в/90д → 10 noncurrent-версій / 30 днів** (кожна noncurrent-версія = ще одна копія секретів; 10/30 досі покриває rollback зіпсованого apply). Крипто-принципал = **GCS service agent** (`service-<num>@gs-project-accounts…`) — deploy-SA KMS-ролі **НЕ потребує** (terraform gcs-backend читає/пише state лише зі `storage.objectAdmin` на bucket, уже scoped в `iam.tf` [INF.15]); між authorize та bucket-update скрипт чекає 30s IAM-propagation (документований GCS race). Rotation 90d мінтить нову PRIMARY, старі версії лишаються decrypt-capable → існуючі state-версії читаються; ⚠️ ручний destroy key-версії = state-версії під нею назавжди нечитабельні → DR-inventory [`06_06 §1`](06_06_Disaster_Recovery_and_Backup).

**Availability (boot-dependency):** disabled/destroyed key → **stopped** VM не старт (DEK re-fetch fail); operator-`reset`=reboot з cached DEK (safe, нуль KMS-call), live-migration зберігає DEK. Bounded: `prevent_destroy` + KMS 30-day restore-grace + Akash coap-fallback (INF.17). Rotation 90d НЕ re-encrypt'ить live disk (старі versions decrypt-capable → boot-safe). Keyring/key **undeletable** у GCP (dev-teardown: `state rm` перед destroy).

Cross-ref: [`00_07`](00_07_Action_Plan_Tracker) INF.22 (GCP-0033-fix), §5.5 (sign-keyring SEC.17), [`06_06 §1`](06_06_Disaster_Recovery_and_Backup) (KMS key = availability-critical DR-inventory).

### 5.7. Secrets-at-rest/runtime latch — credentials→ENV + AR-Encryption keys (SEC.22)

**Принцип (at-rest ≠ runtime):** Akash-провайдер читає `/proc/<pid>/environ` живого процесу, тож `RAILS_MASTER_KEY` у runtime-ENV дозволяє провайдеру розшифрувати `credentials.yml.enc` (→ `secret_key_base` + увесь vault). Латч розчиняє runtime-потребу в `RAILS_MASTER_KEY`: кожне читання секрету в проді йде з ENV, не з master-key-розблокованого vault. **НЕ** коштує Akash — справжній «sealed-never-undone» = pre-mainnet SEC.17 KMS-signing + KMS-MAC `PROVISIONING` (§5.5), не Akash-shuffle (blast-radius-reduction, не повний seal).

**AR-Encryption keys (3, boot-critical) — SHIPPED 2026-07-09.** `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` / `_DETERMINISTIC_KEY` / `_KEY_DERIVATION_SALT` шифрують колонки `hardware_keys` (device AES/Lorenz-seed) + `users.otp_secret` (TOTP-seed). З ENV, **НЕ** `credentials.yml.enc` (інакше поглибили б `RAILS_MASTER_KEY`-залежність). Раніше не сконфігуровані НІДЕ в проді → `hardware_keys` encryption raise-ила на першому use (provisioning dead-on-first-boot). Guard `config/initializers/active_record_encryption_keys_check.rb` (production-wide — web+workers декриптять; coap лише enqueue-ить, але uniform-перевірка простіша) fail-closed на blank/`<32`/weak (пуста content-логіка = `Security::EncryptionKeyGuard`). Генерувати всі три: `bin/rails db:encryption:init`. Deploy-дім: SDL web/job/coap (23-char placeholder `<32` → guard fails-closed) + Kamal `env.secret` + **анкор `compute.tf` coap.env** (systemd env-file — 3-тя поверхня, guard production-wide БЕЗ coap-skip; пропущена SEC.22-sweep'ом → анкор-демон raise-ив на 1-му boot, виправлено 2026-07-10 + regression-guard `spec/deploy/anchor_coap_env_spec.rb`) + `terraform/akash/variables.tf` (≥32 validation) + `deploy_secret_scan` SECRET_NAME. Bypass: `SILKENNET_SKIP_AR_ENCRYPTION_KEYS_CHECK=1` (rescue-boot).

**credentials→ENV (8 сервісів) — SHIPPED.** iotex/streamr/the_graph/filecoin/peaq(+signing_key)/hadron/dclimate/puro читають `ENV["X"].presence || credentials.x` (per-process: the_graph=web, 7=job). `config/storage.yml` (AWS+GCS) теж ENV-primary. Behavior-preserving (vault nil сьогодні). ENV-імена — `.env.example` (reconciled до код-читаних) + §2.1. **Durable guard `spec/deploy/credentials_env_fallback_spec.rb`** (2026-07-11): кожен `Rails.application.credentials`-read у app/lib/config несе `ENV[..].presence ||`-префікс (whitespace-collapsed → multi-line теж) — робить Phase-2 `RAILS_MASTER_KEY`-drop (§5.8) безпечним і ловить майбутній голий read (регресія = dead-on-first-boot); дзеркало INF.12 `env_fetch_declaration_spec` (одноразовий sweep → standing gate).

**coap PROVISIONING-drop — DEFINITIVE 2026-07-10.** coap-guard (`master_key_strength_check.rb` `$PROGRAM_NAME`-skip) дозволяє coap бутитись без `PROVISIONING_MASTER_KEY` (coap лише enqueue-ить, ключів не деривує — code-proven: демон → PDU-парс → `perform_async`, нуль key-derivation). Раніше SDL/анкор несли його «для parity»; тепер **знято з усіх coap-поверхонь** (Akash static+tpl coap + анкор `compute.tf`) — HKDF fleet-forge root off coap `/proc/environ` [SEC.22]. Web/job тримають shared tf-var `provisioning_master_key` (реально деривують). Regression-guard: `spec/deploy/anchor_coap_env_spec.rb` (forbidden-set).

**Phase-2 (👤, deploy-gated): drop `RAILS_MASTER_KEY`.** Після інжекту `SECRET_KEY_BASE` (= поточне `credentials.secret_key_base`, інакше ВСІ сесії ламаються — §5.2 entangled) + AR-encryption keys + service keys, ніщо не читає vault у runtime → `RAILS_MASTER_KEY` droppable з web/coap/job. **НЕ** додано в SDL сьогодні (свідомо): `SECRET_KEY_BASE` (present-placeholder override footgun) + 8 service keys (present-placeholder → 401) — inject-at-deploy через Console.

**iotex_seed hot-path cache — SHIPPED.** `HardwareKeyService.derive_iotex_seed` підписується на КОЖЕН uplink (`W3bstreamVerificationService` через `IotexVerificationWorker`, ампліфіковано ретраями) → щоразу re-touch'ив `PROVISIONING_MASTER_KEY` crown-jewel через HKDF. Тепер memoized in-process (`DERIVED_KEY_CACHE`, дзеркало `HardwareKey#cached_binary_key`): cache-hit **не торкається master-key**. Keyed by `(hkdf-info, device_uid)`; лише ENV-path — explicit `master_key:` (SEC.3 DI / factory) derives fresh (не ділить slot із іншим коренем). Валідний увесь process-life бо master-key boot-immutable (§5.2/§5.4: rotation = fleet re-flash + redeploy → restart чистить кеш). `K_ota` (`OtaHmacKeyService`) звірено cold-path (єдиний caller = `OtaPackagerService`/downlink, не per-uplink) → свідомо НЕ кешовано (YAGNI + OTA-verify blast-radius).

Cross-ref: [`00_07`](00_07_Action_Plan_Tracker) SEC.22, §5.2 (rotation entanglement), §5.5 (KMS pre-mainnet seal), [`04_02`](04_02_Business_Logic_and_Services) `Security::EncryptionKeyGuard`.

### 5.8. Rotation-on-compromise Runbook — crown-jewels `PROVISIONING_MASTER_KEY` + `RAILS_MASTER_KEY` (SEC.22)

> **Threat model + чесна рамка.** Обидва ключі — effectively **un-rotatable сьогодні** (§5.2): цей runbook = впорядкована деградація й пріоритети, НЕ «заміна за 15 хв» (контраст: `peaq_signing_key` §5.4 — повністю rotatable). Структура дзеркалить §5.4 (Detection → Containment → Recovery → Post-Incident). Справжній latch (ключ не покидає HSM) = pre-mainnet GCP-KMS-MAC / KMS-signing — §5.5/§5.7. ⚠️ **ENV-first пастка (стосується КОЖНОГО кроку будь-якого runbook'а):** після SEC.22 credentials→ENV `bin/rails credentials:edit` НЕ ротує значення, якщо той самий ключ заведено в deploy-ENV (`ENV[..].presence ||` перемагає) — **перевіряй ENV-поверхні першими** (GitHub Secrets / Kamal / SDL / tfvars / `coap.env`).

**A. `PROVISIONING_MASTER_KEY` compromised** (HKDF-корінь **6** класів ключів — §5.2; blast-radius вищий за minter-ключ):

1. **Detection:** масові DCI-дивергенції, що «сходяться» (fraud, який ПРОХОДИТЬ Z-звірку = сигнатура K_seed-компрометації — чесний збій дає розбіжність, не збіг) · fauna/telemetry-аномалії кластерами · невпізнані provisioning-запити в `AuditLog` · IoTeX-верифікації від неіснуючих пристроїв.
2. **Containment (порядок = за незворотністю шкоди):**
   - **Зупинити provisioning** нових пристроїв (кожен новий = розширення компрометованого кореня); ротувати ENV на новий master для **майбутнього** provisioning — старі деривації в `HardwareKey`/Flash лишаються під старим коренем (це і є un-rotatable половина).
   - **Підняти недовіру до телеметрії всього existing-fleet:** K_seed відтворюється offline із master + публічного `device_uid` (DID on-chain) → **DCI anti-fraud invariant зламано для ВСІХ прошитих дерев до re-flash** — найвищий blast-radius клас із шести. Мінт-рішення (freeze/manual_review-режим) = founder per-інцидент.
   - **Прийняти: OTA-канал заморожений** — K_ota деривується з master, кожен непрошитий вузол відхиляє образ під новим коренем fail-safe → rescue-прошивку ефіром НЕ доставиш; єдиний канал = фізичний SWD.
   - Gateway-ключі: `HardwareKeyService#rotate_gateway_random!` (KEYC вже SecureRandom, master-незалежний) — але доставка на Queen = той самий re-flash bottleneck.
3. **Recovery = fleet re-flash (SWD, фізична експедиція):** через `FactoryFlashing` per-device (KEYL/K_seed/KEYC) + per-cluster (KEYB — **нуль soft-path, кластер синхронно**; K_ota). Пріоритет: Queen'и першими (KEYC/KEYB відновлюють control-plane кластера), Soldier'и — за економічною вагою кластера. `iotex_seed` — єдиний клас БЕЗ hardware-persistence (чистий backend-derive) → ротується redeploy'єм, АЛЕ ⚠️ незвірено, чи W3bstream пінить pubkey per-DID довгостроково — **перший крок інциденту: звірити з IoTeX, чи зміна ключа ламає верифікацію existing DID**. `DERIVED_KEY_CACHE` тримає старі деривації process-wide → **redeploy/restart обов'язковий** після ENV-ротації.
   - **Що НЕ зачеплено (за дизайном):** Gateway M2M Ed25519-ідентичність (EDSK/voice-сім'я) — `SecureRandom` на factory host, НЕ HKDF-від-master (`FactoryFlashing::Session#gateway_voice_seed`) — компрометація master її не розкриває.
4. **Post-Incident:** інцидент в `AuditLog` + оновити residual у `SECURITY_ASSURANCE §6` · прискорити KMS-MAC (§5.5) · переглянути custody-тір ([`03_06 §5.A`](03_06_Factory_Flashing_and_Key_Provisioning) ранжує Direct-ENV найнижче — сьогодні це єдиний живий шлях).

**B. `RAILS_MASTER_KEY` / `secret_key_base` compromised (entangled — §5.2):**

1. **Detection:** сесії/дії без відповідних login-подій (session-forge) · валідні `generates_token_for`-токени, яких ніхто не видавав · Sentry CSRF-аномалії.
2. **Containment — два ключі, дві половини:**
   - Re-encrypt vault: `bin/rails credentials:edit` з новим master (commit нового `.enc`) — закриває ЧИТАННЯ vault'а, але **НЕ** revoke: той самий `secret_key_base` лишається → session/token-forge триває.
   - Справжній revoke = **ротація `secret_key_base`** (інжект нового `SECRET_KEY_BASE` у deploy-ENV — механіка Phase-2 §5.7) = one-shot інвалідація **всіх**: dashboard-сесій · `password_reset` (15 хв) · `email_verification` (24 год) · **`api_access` (30 днів — усі API-клієнти re-issue)** · **`m2m_access` (30 днів, [SEC.16] — НАЙДОРОЖЧИЙ хвіст: кожна польова Королева мусить перевидати токен через Ed25519-підпис, і зробити це може лише сама)** · CSRF · ActiveStorage signed IDs.
3. **Recovery:** користувачі re-login (очікуваний support-сплеск), API-інтеграції перевипускають токени; даних не втрачено (AR-encryption ключі — ОКРЕМІ ENV-секрети §5.7, цим інцидентом не зачеплені).
4. **Post-Incident:** як A.4 + якщо вектор = витік із running-process на Akash — аргумент прискорити Phase-2 drop `RAILS_MASTER_KEY` (§5.7).

Cross-ref: §5.2 (un-rotatable вердикти + 6 класів) · §5.4 (rotatable-контраст + ENV-first нота) · §5.5/§5.7 (KMS-latch = вихід із цього runbook'а) · [`06_06 §4`](06_06_Disaster_Recovery_and_Backup) (**втрата ≠ компрометація**: втрата master-keys незворотна — інший клас) · [`03_06`](03_06_Factory_Flashing_and_Key_Provisioning) (re-flash механіка) · §5.9 (той самий `secret_key_base` під іншим кутом: **per-tenant** відкликання без глобального вилогінювання).

---

### 5.9. Revocation-on-leak Runbook — підписане ім'я Turbo-стріму (SEC.25 Ф3)

> **Threat Model.** Підписане ім'я стріму — це bearer-capability: непідробне (HMAC на **`Turbo.signed_stream_verifier_key`** — власному ключі гема, який ми з 2026-07-30 **задаємо самі** з `ENV["TURBO_SIGNED_STREAM_KEY"]`, тож він більше не прив'язаний до `secret_key_base`; деталь і наслідок — [`04_04 §8.1`](04_04_Phlex_UI_and_Tailwind)), але **прозоре** (org-id читається відкритим текстом) і **детерміноване, без TTL**. Дістати його можна лише зі сторінки, відрендереної членові організації, — але після цього рядок працює **назавжди**, бо ActionCable підписку не ре-авторизує. Тобто інсайдер організації A, передавши рядок будь-якому автентифікованому користувачеві, віддає йому живу стрічку A без сліду в HTTP-логах. Механіка й межі — [`04_04 §8.1`](04_04_Phlex_UI_and_Tailwind).
>
> ⚠️ **Чому не ротація `secret_key_base` (§5.8).** Вона теж інвалідує всі імена, але заразом вилогінює **всіх** користувачів платформи, палить `api_access` І `m2m_access`-токени (обидва 30-денні; другий = весь флот Королев) і ламає CSRF — тобто глобальна ціна за локальний інцидент. Епоха — той самий ефект, звужений до однієї організації.

**Крок 1: Detection.** Прямих ознак у HTTP-логах немає за побудовою (витік їде вебсокетом після підписки). Реальні тригери — зовнішні: повідомлення від організації, offboarding із підозрою, знайдений рядок `..._org_<id>_e<n>` поза застосунком (тікет, чат, скріншот).

**Крок 2: Containment.** Ротація епохи — один виклик; стара адреса вмирає для всіх продюсерів одразу.

```ruby
org = Organization.find(<id>)
org.rotate_stream_epoch!   # bump → tombstone у покинуту адресу → слід ARCH.57
```

**Крок 3: Дотиснути тих, кого tombstone не застав.** Він доїжджає лише до **підключених** у ту мить сокетів (Solid Cable ставить точку приєднання нової підписки на поточний максимум — backlog не реплеїться). Вкладка, що спала під час bump'а, ре-підпишеться на мертве імʼя з ще не перезавантаженого DOM і виглядатиме `connected`, будучи глухою. Тому повторний поштовх — **штатний крок, не crash-recovery**:

```ruby
org.broadcast_stream_tombstone!(org.stream_epoch - 1)   # ідемпотентно, епохи не рухає
```

**Крок 4: Post-incident.** Слід уже в ланцюгу (`action: "stream_epoch_rotated"`, metadata `from`/`to`) — звірити з `AuditLog.verify_chain_integrity(org.id)`. ⚠️ Якщо витік стосувався **record-form стріму**, епоха його НЕ накриває — але спершу з'ясуй, ЩО саме витекло, бо з чотирьох таких адрес дані несе одна. `[cluster, :alerts]` — чистий сигнал без payload'а, `[actuator, :commands]` — заглушка, чий `src` ре-авторизується org-скоупленим `find`, `ota_channel_{uid}` — прогрес поверх `uid`, який уже в самому імені; реальний вміст (суми SCC, tx-хеші) тече лише `[wallet, :transactions]`. Для нього важіль тепер є, і він **вужчий за `secret_key_base`** — ротація `TURBO_SIGNED_STREAM_KEY` (нижче), яка знецінює всі видані імена стрімів, не чіпаючи сесій, `api_access`, CSRF і ActiveStorage.

**Крок 4б: ротація stream-ключа** (коли витекла record-form адреса, або коли невідомо, що саме витекло).

```bash
# 1. згенерувати новий секрет
bin/rails runner 'puts SecureRandom.hex(32)'
# 2. оновити TURBO_SIGNED_STREAM_KEY у deploy-ENV (§3.1) — ОДНАКОВО на web + job
# 3. прокотити РЕСТАРТ усіх процесів — без нього ротація не діє (див. ⚠️ нижче)
```

⚠️ **Три речі, які треба знати ДО того, як тягнути цей важіль.**
1. 🔴 **Він деплой-часовий, не консольний.** `Turbo.signed_stream_verifier` мемоїзований (`@signed_stream_verifier ||=`), тож зміна ключа в живому процесі не робить **нічого** — стара підпис лишається валідним до рестарту. Виміряно: підміна в рантаймі лишала ім'я валідним, і лише окремий процес із новим секретом дав `nil`.
2. Він **глобальний по організаціях** — б'є всіх, тоді як епоха (Крок 2) б'є одну. Тому порядок саме такий: епоха першою, цей важіль — коли її замало.
3. Він **не рве відкриті сокети** (верифікатор читають раз у `subscribed`) і лишає чесних глядачів у тихій глухоті до наступної навігації — tombstone тут не рятує, бо їх уже відреджектило.

⚠️ Якщо `TURBO_SIGNED_STREAM_KEY` у середовищі **не заведено**, гем деривує ключ із `secret_key_base` як раніше — застосунок працює, але цього важеля в нього немає. Boot-guard'а на це свідомо нема (щоб забутий секрет не валив деплой), тож єдиний сторож — цей чекліст: секрет обов'язковий у §1 разом із рештою.

⚠️ **Чого цей runbook НЕ покриває:** перемикання контексту адміном. Bump — подія рівня організації, тож switch одного super_admin'а перезавантажив би всіх її глядачів заради гігієни одного; межа привілею там і не перетинається ([`04_03 §3.1`](04_03_REST_API_v1_Reference)).

---

## 🔗 Залежності та посилання

| Документ | Зв'язок |
|---|---|
| [`06_01`](06_01_Deployment_Kamal_Terraform) | Kamal/Terraform secrets (00_07 S1.1) |
| [`06_02`](06_02_Akash_Network_Integration) | Akash SDL secrets / `REQUIRED_SECRET_NOT_SET` (00_07 S4.3) |
| [`06_03`](06_03_Prometheus_Observability) | `SENTRY_DSN`, Grafana Cloud tokens |
| [`05_01`](05_01_Multichain_Architecture) | Web3 ENV variables (§5) |
| [`00_07`](00_07_Action_Plan_Tracker) | S1.1, S4.3, S5.2, S5.6 |
