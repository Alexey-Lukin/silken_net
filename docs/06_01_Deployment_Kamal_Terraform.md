# 06_01: Розгортання Kamal & Terraform (Canopy vs Production)

## 🎯 Мета

Зафіксувати повний стан конфігурацій розгортання та інфраструктури як коду (IaC). Документ відповідає на три ключові питання:

1. Чим відрізняються середовища **Canopy** (Staging) та **Production**?
2. Що розгортається в **GCP** (традиційна хмара), а що — в **Akash Network** (децентралізована мережа)?
3. Які **API-ключі, секрети та сертифікати** потрібні для першого реального деплою?

---

## ✅ Статус

- **Поточний TRL:** TRL 4 — інфраструктурний код існує, реальний деплой не проводився
- **Відкрите:** deploy-readiness (Ingress IP, GitHub Secrets, Akash SDL secrets) → [`00_07`](00_07_Action_Plan_Tracker) (S1.1, INF.4/6, S5.6).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `config/deploy.yml` · `config/deploy.canopy.yml` | Kamal (production / canopy) |
| `terraform/` · `terraform/akash/` | IaC: Cloud SQL, Ingress Anchor, Akash |
| `.github/workflows/deploy.yml` · `deploy-production.yml` | Canopy / Production CI/CD (деталі — [`06_07`](06_07_CICD_and_Runbook_Index)) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Backend (що деплоїться) |
| [`06_02` — Akash Network Integration](06_02_Akash_Network_Integration) | Akash SDL, ENV, TLS |
| [`06_03` — Prometheus Observability](06_03_Prometheus_Observability) | Observability |
| [`06_04` — Secrets Checklist](06_04_Secrets_Checklist) | секрети — SSOT |
| [`06_06` — Disaster Recovery and Backup](06_06_Disaster_Recovery_and_Backup) | backup / restore / RTO·RPO |
| [`06_07` — CICD and Runbook Index](06_07_CICD_and_Runbook_Index) | CI/CD pipeline + runbook index |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | S1.1, S1.5, INF.4/6, S5.6 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Pre-Flight Checklist (до першого фізичного деплою)](#-pre-flight-checklist-до-першого-фізичного-деплою)
- [Quickstart: Перший Деплой Інфраструктури](#-quickstart-перший-деплой-інфраструктури)
- [Архітектура Деплою (The Big Picture)](#-архітектура-деплою-the-big-picture)
- [Canopy vs 🌲 Production — Порівняльна Таблиця](#-canopy-vs--production--порівняльна-таблиця)
- [GCP vs Akash — Розподіл Ресурсів](#-gcp-vs-akash--розподіл-ресурсів)
- [Redis DB Isolation Strategy](#-redis-db-isolation-strategy)
- [Kamal — Детальний Аналіз](#-kamal--детальний-аналіз)
- [Terraform (GCP) — Детальний Аналіз](#-terraform-gcp--детальний-аналіз)
- [Docker — Multi-stage Build](#-docker--multi-stage-build)
- [Akash SDL — Технічний Аналіз](#-akash-sdl--технічний-аналіз)
- [DEPLOY-DAY: перший деплой фазами (Priority Order)](#-deploy-day-перший-деплой-фазами-priority-order)
- [Масштабування до Планетарного Рівня — CoAP/UDP та Ingress](#-масштабування-до-планетарного-рівня--coapudp-та-ingress)
- [Змінні Середовища: Web3 та Мультичейн](#-змінні-середовища-web3-та-мультичейн)
<!-- TOC:AUTO:END -->

---

## ⚠️ Pre-Flight Checklist (до першого фізичного деплою)

> Доповнення до блокерів Terraform/Kamal — фокус на типових помилках при першому виводі системи в роботу.

П'ять речей, які можуть мовчки зламати перший деплой:

| # | Перевірка | Деталі |
|---|-----------|--------|
| **1** | **DNS / TLS до `kamal setup`** | Після `terraform apply` скопіюй IP та створи A-запис (`api.silkennet.com → <IP>`). Дочекайся: `dig api.silkennet.com` → правильний IP. **Тільки тоді** запускай `kamal setup`. Причина: при ввімкненому `proxy.ssl` (зараз **закоментований** у `config/deploy.yml`) **kamal-proxy** (Kamal 2.x — НЕ Traefik 1.x) робить Let's Encrypt ACME-challenge — без живого DNS сертифікат не видасться і проксі не підніметься. Поточно `proxy.ssl` вимкнено → TLS термінується зовні (Cloudflare / Akash hostname, рішення `[INF.4]`); DNS усе одно потрібен для маршрутизації трафіку. |
| **2** | **`.kamal/secrets-common` файл існує + повний** | Kamal читає секрети з `.kamal/secrets-common` (не з environment). Заповни **усі** змінні з `config/deploy.yml env.secret` (drift = boot crash або silent Web3 failure): **(a) Application core:** `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD` (host/user/database — non-secret `env.clear`, component style `config/database.yml`), `REDIS_URL`, `GCP_ARTIFACT_REGISTRY_KEY` (registry pull). `KREDIS_REDIS_URL` — **не** додавати: Kredis auto-derive DB 1 з `REDIS_URL` (`config/redis/shared.yml`), порожній інжект перебив би derive [B1]. **(b) 🛑 Boot-critical:** `PROVISIONING_MASTER_KEY` (`master_key_strength_check.rb` raises `SecurityError` без неї) + `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`/`_DETERMINISTIC_KEY`/`_KEY_DERIVATION_SALT` ([SEC.22] `active_record_encryption_keys_check.rb` fail-closed; `db:encryption:init`). **(c) Observability:** `SENTRY_DSN`. **(d) Web3 oracle keys:** `ORACLE_MINTER_PRIVATE_KEY`, `ORACLE_SLASHER_PRIVATE_KEY`, `ETHEREUM_ANCHOR_PRIVATE_KEY` — legacy `ORACLE_PRIVATE_KEY` **RETIRED повністю** (INF.22: жоден код не читає, guard-tripwire відмовляє значенню під цим ім'ям); CI-джерело money-п'ятірки (ці три + `SOLANA_WALLET_KEYPAIR`, `ORACLE_CELO_PRIVATE_KEY`) = GH Environment `production`, НЕ repo-secrets (INF.22 → [`06_04 §1`](06_04_Secrets_Checklist)). **(e) RPC endpoints:** `ALCHEMY_POLYGON_RPC_URL`, `ALCHEMY_ETHEREUM_RPC_URL`, `SOLANA_RPC_URL`. **(f) Solana minting:** `SOLANA_WALLET_KEYPAIR`, `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS`. **(g) Chainlink:** `CHAINLINK_HMAC_SECRET` (лише callback-endpoint; dispatch-секрети вилучено — ARCH.53). **Той самий список застосовується для Akash SDL** (`deploy/akash/deploy.yaml` + `deploy.yaml.tpl`) та Terraform (`terraform/akash/terraform.tfvars`) — див. [`06_02 §2 ENV (Секрети SDL)`](06_02_Akash_Network_Integration). |
| **3** | **Gas на Web3-гаманцях** | Воркери потребують нативної крипто: **MATIC** (Polygon), **ETH** (L1), **SOL** (Solana), **CELO** (Celo). Без газу → "Insufficient Funds" на кожній транзакції → Sidekiq потоне у ретраях. |
| **4** | **LoRa-антена підключена** | **КРИТИЧНО.** Ніколи не подавай живлення без антени на SMA/U.FL порту. SX1262 відбиває RF назад у чип (high VSWR) — радіотракт згоряє за мілісекунди. Незворотно. Правило: антена → живлення. |
| **5** | **HKDF AES-ключів (post-FW.1 + ARCH.42 + FW.2 (в))** | Кожен Soldier має **per-device session AES-128 LoRa ключ** (`aes_key[4]`, 16 bytes) + **cluster control-plane KEYB** (`bcast_key[4]`, 16 bytes — двоключова модель [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); Queen — той самий KEYB як єдиний LoRa-ключ + окремий **AES-256 CoAP ключ** (`coap_key[8]`, 32 bytes). Усі деривуються з `PROVISIONING_MASTER_KEY` через HKDF з domain-separated info-strings (`"silken-aes-128-lora-key"` / `"silken-aes-128-broadcast-key"` / `"silken-aes-256-device-key"`). Перевіряй на factory bench, що backend і firmware повертають той самий байтовий ключ за тим самим salt. Симптом mismatch: сміття після декрипту (телеметрія на Rails / downlink на Солдаті). Детальніше: [`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning). |
| **6** | **CoAP UDP smoke test через Ingress Anchor** | **[INF.6]** Перевір end-to-end UDP-шлях `Queen → Ingress Anchor → CoAP daemon` (PRIMARY: демон бере UDP прямо на анкорі — INF.17 2026-07-04; FALLBACK: socat-релей → Akash `coap`-сервіс) ПЕРЕД першим прошиванням Queen. Без цього silent UDP failure не помітний з HTTP-only health checks. **Автоматизовано:** `.github/workflows/coap_smoke.yml` (`workflow_dispatch` для ad-hoc запуску; `workflow_call` — заведений post-deploy gate'ом у `deploy.yml`/`deploy-production.yml`, job `coap-smoke`, активується repo Variable `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST`); inputs: `host` / `port` (default `5683`) / `timeout_seconds` (default `10`) / `retries` (default `3`). **Ручна команда (з машини за межами VPC, що імітує Queen; stdlib-only Ruby, без libcoap):** <br>`bin/coap_smoke --host api.silkennet.com` <br>Зонди = freeze-contract FW.56 (точні байти: RST на сміття, `4.04` на невідомий маршрут з 0xFF-MID-піном, `2.04` лише після enqueue батча — НЕ generic liveness; семантика — [`03_02 §4`](03_02_Queen_Gateway_Firmware)). Якщо timeout: перевір (a) GCP firewall `allow-coap` UDP 5683 = `0.0.0.0/0`; (b) на анкорі `systemctl status coap-daemon` (PRIMARY; env-file `/etc/silkennet/coap.env` заповнений?) АБО, у fallback-режимі, `coap-relay` (socat → `<akash-pod-ip>:5683`) + (c) Akash SDL expose `5683/udp` (`coap`-сервіс); (d) rescue-логи демона: `docker logs silkennet-coap`. Швидка перевірка «чи взагалі слухає UDP» через `nc`: `echo -ne '\x40\x02\x00\x01' \| nc -u -w2 api.silkennet.com 5683 \| xxd` — повертає бінарний CoAP response якщо daemon приймає UDP. |
| **7** | **Schema bootstrap від squashed init_consolidated** | **[INF.7 — Phase 7]** На свіжій базі деплой `bin/rails db:setup` (= `db:create` + `db:schema:load` + `db:seed`). Ми **НЕ** використовуємо `db:migrate` в продакшні до першого деплою — всі pre-launch міграції згорнуті в єдиний `db/migrate/*_init_consolidated.rb` (**timestamp свідомо НЕ називається — бери з `ls db/migrate/`**: він міняється при кожному re-squash, і саме цей рядок уже двічі протухав на ньому), а схема живе в `db/structure.sql` (включно з усіма 3 RANGE-партиційними таблицями + початковими партиціями `_default` + поточним вікном). `schema_migrations` містить анкер **плюс кожну інкрементальну, додану після нього** — рівна кількість тут свідомо не називається, бо вона росте між сквошами; джерело істини — INSERT-блок у кінці `db/structure.sql`. Якщо хтось додає incremental міграцію після цього — `StrongMigrations.start_after` (стоїть на живому анкері — звіряй із `config/initializers/strong_migrations.rb`, ніколи з цього рядка) змусить її пройти всі checks. ⊕ **З 2026-08-23 воно ВИВОДИТЬСЯ з імені файлу анкера** [OPS.24], тож re-squash більше не має кроку «bump start_after» — а разом із ним зник і єдиний мовчазний спосіб зіпсувати процедуру (значення нижче за живий анкер знімало перевірки з уже застосованих міграцій, і ніщо не червоніло). **НЕ** робіть squash повторно після першого деплою (втратите history) без zero-downtime плану. |
| **8** | **PartitionMaintenanceWorker cron у Sidekiq** | **[INF.8 — Phase 7]** `30 0 * * *` UTC, `PARTITIONED_TABLES = %w[telemetry_logs gateway_telemetry_logs blockchain_transactions]`. На день-1 нового місяця партиція повинна вже існувати — інакше `INSERT` падає з `no partition of relation`. Перевір через `psql -c "\d+ telemetry_logs"` що партиція на наступний місяць є. Якщо worker silent-fails — перевір Sentry alert (Phase 7 додав `Sentry.capture_exception` у rescue блок). |
| **9** | **Kamal IP-плейсхолдери → реальний Ingress-IP** | **[S1.5]** Після `terraform apply`: `terraform output -raw ingress_ip` → підставити замість `192.168.0.1` (`config/deploy.yml` servers web/job/coap) і `<INGRESS_ANCHOR_IP>` (`config/deploy.canopy.yml`); також `image:` → повний AR-шлях з `terraform output artifact_registry_url` [INF.15]. Без цього `kamal deploy` б'є в приватний RFC-1918 нікуди. |
| **10** | **`akash-deployment-ip` metadata після Akash-лізи** | **[S1.5]** Після `akash provider lease-status`: `gcloud compute instances add-metadata silken-net-ingress --metadata akash-deployment-ip=<AKASH_IP> --zone <zone>` + `reset`. Живить HAProxy 80/443 → Akash і socat-**fallback**; PRIMARY CoAP-демон (INF.17) від metadata НЕ залежить. Поки unset — обидва юніти чесно логують skip (sentinel-guard), HAProxy не стартує. |

### Менеджер Секретів (Рекомендація)

З десятками API-ключів (12 блокчейнів, GCP, Akash, Starlink, DB, Redis, GitHub) критично мати єдине захищене сховище:

- **Bitwarden** (open-source, self-hostable) або **1Password** — один vault per середовище (canopy / production)
- Зберігай кожен токен, приватний ключ та credential там **до** заповнення shell-ENV перед `kamal deploy`
- Ніколи не комітити у git RAW-значення: `.env`, `terraform.tfvars`. Сам `.kamal/secrets-common` **закомічений свідомо** — він містить лише `$VAR`-посилання на shell-ENV (safe-for-git за дизайном Kamal), не значення; не виривай його з git

---

## 🚀 Quickstart: Перший Деплой Інфраструктури

> Покрокова послідовність першого реального деплою.

```bash
# Крок 1: Створити GCS bucket для Terraform State (один раз, до terraform init)
cd terraform
chmod +x bootstrap.sh
./bootstrap.sh  # gcloud auth check + bucket + CMEK-латч state-bucket'а [SEC.22]:
                # keyring silken-tfstate-ew1 → default-CMEK + PAP + retention 10в/30д;
                # усередині разовий sleep 30s (IAM-propagation) — не переривай

# Крок 2: Налаштувати terraform.tfvars
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Заповнити: project_id, db_password, ssh_source_ranges

# Крок 3: Провізіонувати GCP інфраструктуру (Cloud SQL + Ingress Anchor)
terraform init
terraform plan
terraform apply
# → outputs: ingress_ip, database_url
# GCP тепер містить: Cloud SQL PostgreSQL (приватна IP) + Ingress Anchor (e2-small,
#   статична IP, CoAP-демон PRIMARY, boot-disk CMEK через `silken-disk-ew1` keyring)
#   + Cloud KMS keyring (`kms.tf` — compute service-agent IAM створюється автоматично)
# ⚠️ Перший apply може РАЗ впасти "kmsPermissionDenied" (compute P4SA / KMS-IAM
#   propagation ще не поширилась) → просто re-apply (той самий клас, що першу
#   активацію billing-API; на brownfield-проєкті зазвичай проходить з першого разу)

# Крок 4: Створити DNS A-запис
# api.silkennet.com → $(terraform output -raw ingress_ip)
# Дочекатися: dig api.silkennet.com → правильний IP

# Крок 5: Налаштувати Akash SDL — повний список секретів (дзеркало .kamal/secrets-common)
# Заповнити в deploy/akash/deploy.yaml АБО terraform/akash/terraform.tfvars
# (рекомендовано — Terraform: cp terraform.tfvars.example terraform.tfvars)
#
# Application core:
#   RAILS_MASTER_KEY, POSTGRES_HOST, POSTGRES_USER, POSTGRES_PASSWORD, CLOUD_SQL_INSTANCE_CONNECTION_NAME,
#   GCP_SA_KEY_BASE64, REDIS_URL=rediss://<upstash>:6379
#   (KREDIS_REDIS_URL — НЕ задавати: Kredis auto-derive DB 1 з REDIS_URL, config/redis/shared.yml) [B1]
# 🛑 Boot-critical (інакше Puma crash):
#   PROVISIONING_MASTER_KEY=$(ruby -e "require 'securerandom'; puts SecureRandom.hex(32)")
# Observability:
#   SENTRY_DSN, PROMETHEUS_AUTH_USER, PROMETHEUS_AUTH_PASSWORD
#   GRAFANA_REMOTE_WRITE_URL/USERNAME/TOKEN (тільки в alloy сервісі)
# Web3 oracle keys (інакше Sidekiq DeadSet; legacy ORACLE_PRIVATE_KEY retired повністю — INF.22):
#   ORACLE_MINTER_PRIVATE_KEY, ORACLE_SLASHER_PRIVATE_KEY,
#   ETHEREUM_ANCHOR_PRIVATE_KEY
# RPC endpoints (Web3::RpcConnectionPool):
#   ALCHEMY_POLYGON_RPC_URL, ALCHEMY_ETHEREUM_RPC_URL, SOLANA_RPC_URL
# Solana minting:
#   SOLANA_WALLET_KEYPAIR, SOLANA_FEE_PAYER_PUBKEY,
#   SOLANA_FEE_PAYER_TOKEN_ACCOUNT, SOLANA_USDC_MINT_ADDRESS
# Chainlink oracle-callback HMAC (dispatch-секрети вилучено — ARCH.53):
#   CHAINLINK_HMAC_SECRET
#
# ⚠️ AKASH SECURITY NOTE: ENV vars видимі провайдеру у plaintext.
# Ротуй keys кожні 90 днів. Akash-deployment keys — тільки з MINTER_ROLE/
# SLASHER_ROLE (ніколи з DEFAULT_ADMIN_ROLE). Детальніше: 06_02 §2 (ENV/секрети) + 00_07 S4.3.

# Крок 6: Деплой на Akash Network
cd terraform/akash
terraform init
terraform apply
# → Akash розгортає web (Rails + Puma), job (Sidekiq) та coap (UDP-демон) сервіси
# → Cloud SQL Auth Proxy в контейнері тунелює DB-трафік через Google API
# → Redis через Upstash (зовнішній, TLS)

# Крок 7: Верифікація
# Коли в логах: "Listening on coap://0.0.0.0:5683" — ліс може говорити.
# Ingress Anchor: CoAP приймає демон ПРЯМО на анкорі (PRIMARY — INF.17);
# HAProxy проксює HTTP/HTTPS з GCP IP на Akash deployment (socat = CoAP-fallback → Akash).
```

---

## 🗺️ Архітектура Деплою (The Big Picture)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                            GITHUB REPOSITORY                                 │
│                                                                              │
│  ┌─────────┐    ┌───────┐    ┌──────────────────────────────────────────┐   │
│  │ Feature │───▶│  PR   │───▶│  CI (scan_ruby, scan_js, lint, test,    │   │
│  │ Branch  │    │       │    │      feature-test)                       │   │
│  └─────────┘    └───┬───┘    └───────────────────┬──────────────────────┘   │
│                     │ merge                       │ ✅ pass                  │
│                     ▼                             ▼                          │
│               ┌──────────┐       ┌────────────────────────────────┐         │
│               │   main   │──────▶│  Deploy Canopy 🌿 (auto)       │         │
│               └────┬─────┘       │  terraform apply → kamal -d    │         │
│                    │             │  canopy                        │         │
│                    │ ~2 тижні    └────────────────────────────────┘         │
│                    ▼                                                         │
│  ┌──────────────────────────────┐  ┌────────────────────────────────────┐   │
│  │  GitHub Release (v1.x.0)    │─▶│  Deploy Production 🌲              │   │
│  └──────────────────────────────┘  └────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 🌿 Canopy vs 🌲 Production — Порівняльна Таблиця

| Параметр | Canopy 🌿 | Production 🌲 |
|---------|-----------|--------------|
| **Тригер деплою** | Push в `main` після успішного CI (continuous) | GitHub Release (`v*.*.*`) — створюється **release-please** (`Ops · Release`) з conventional commits → канон [`06_07 §1`](06_07_CICD_and_Runbook_Index) |
| **Workflow** | `.github/workflows/deploy.yml` (`Deploy · Canopy`) | `.github/workflows/deploy-production.yml` (`Deploy · Production`) |
| **Платформа** | Akash (intended primary SDL) — але CI `deploy.yml` наразі робить `kamal deploy -d canopy` (Kamal/GCP-fallback, web-only) | Akash Network |
| **GCP ресурси** | Cloud SQL (спільна або окрема БД) + Ingress Anchor (`e2-small`) | Cloud SQL (HA) + Ingress Anchor (`e2-small`, CoAP-демон PRIMARY — INF.17) |
| **Redis** | Upstash Serverless Redis (TLS, `rediss://`) | Upstash Serverless Redis (TLS, `rediss://`) |
| **SSL/HTTPS** | ✅ `force_ssl` + HSTS (1рік, subdomains, preload). `DISABLE_SSL=true` для override | ✅ `force_ssl` + HSTS (1рік, subdomains, preload) |
| **DB** | `silken_net_canopy*` — ізольований набір на тому ж Cloud SQL інстансі (`POSTGRES_DATABASE` override; INF.16) | `silken_net_production` (HA) |
| **Puma workers** | `WEB_CONCURRENCY: 4` (Akash SDL; `2` на Kamal/GCP-fallback) | `WEB_CONCURRENCY: 4` (Akash SDL; `2` на Kamal/GCP-fallback) |

---

## ☁️ GCP vs Akash — Розподіл Ресурсів

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform (GCP)              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Ingress Anchor (e2-small, silken-net-ingress)      │   │
│  │    — статична IP, CoAP-демон (PRIMARY) + HAProxy/socat│   │
│  │    — проксює HTTP/HTTPS/CoAP на Akash deployment   │   │
│  │  Cloud SQL PostgreSQL 17 (3 бази, HA, приватна IP)  │   │
│  │  Artifact Registry (Docker images)                   │   │
│  └──────────────────────────────────────────────────────┘   │
│  ❌ Memorystore Redis — ВИДАЛЕНО (замінено на Upstash)      │
│  ❌ web-0 / canopy VMs — ВИДАЛЕНО (Rails на Akash)          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Akash Network                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  web сервіс (Rails 8.1 + Puma + Thruster)           │   │
│  │  4 vCPU / 8 GB RAM / 50 GB ephemeral                │   │
│  │  Порти: :80 (HTTP)                                   │   │
│  │                                                      │   │
│  │  ✅ job сервіс (Sidekiq, всі воркери)                │   │
│  │  ✅ coap сервіс (CoAP/UDP :5683 → Sidekiq) [INF.17]  │   │
│  │  ✅ alloy сервіс (Grafana Alloy → Grafana Cloud)     │   │
│  │  ✅ Cloud SQL через Auth Proxy (HTTPS tunnel)        │   │
│  │  ✅ Redis через Upstash (зовнішній, TLS, rediss://) │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Upstash (Serverless Redis)               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Redis 7.x з TLS (публічний endpoint, rediss://)    │   │
│  │  Доступний з Akash та будь-де через інтернет         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Grafana Cloud (SaaS)                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Prometheus (remote_write endpoint)                  │   │
│  │  Grafana (dashboards, PromQL)                        │   │
│  │  Alerting (alert rules, notification channels)       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

| Сервіс/Ресурс | GCP | Akash Network | Upstash | Grafana Cloud | Примітка |
|--------------|-----|---------------|---------|---------------|---------|
| **Rails web (Puma + Thruster)** | ❌ | ✅ | — | — | Повністю на Akash |
| **Sidekiq (job role)** | ❌ | ✅ | — | — | `job` сервіс в Akash SDL |
| **Grafana Alloy (metrics agent)** | ❌ | ✅ | — | — | `alloy` сервіс в Akash SDL, пушить у Grafana Cloud |
| **CoAP UDP daemon (:5683)** | ✅ **PRIMARY** | fallback | — | — | **PRIMARY = демон на Ingress Anchor** (docker + systemd `coap-daemon`, VPC → Cloud SQL приватним IP без Auth Proxy — founder 2026-07-04); fallback = socat-релей → Akash `coap`-сервіс (лишається задеплоєним) + Kamal `coap`-роль. Свідомо НЕ puma-thread — UDP у web-процесі сплітає lifecycle (INF.17) |
| **Cloud SQL PostgreSQL 17** | ✅ | — | — | — | Приватна IP, доступ через Auth Proxy |
| **ActionCable (Solid Cable)** | ✅ | ✅ | — | — | Спільна Cloud SQL БД `cable`, **POLLING** (`polling_interval`), НЕ LISTEN/NOTIFY — механіка й наслідки для ємності в `config/cable.yml` (без sticky sessions) |
| **Redis** | ❌ | — | ✅ | — | Upstash Serverless, TLS (`rediss://`) |
| **Prometheus + Grafana + Alerting** | ❌ | — | — | ✅ | SaaS, Alloy → remote_write |
| **Ingress Anchor** | ✅ | — | — | — | `e2-small`, статична IP: CoAP-демон (PRIMARY) + HAProxy 80/443→Akash + socat (fallback) |
| **Artifact Registry (Docker)** | ✅ | — | — | — | Kamal пушить у GCP AR |
| **GHCR (Docker mirror)** | — | ✅ | — | — | `.github/workflows/mirror-ghcr.yml`, публічний для Akash |

---

## 🔴 Redis DB Isolation Strategy

### Проблема

Без ізоляції Redis databases IoT телеметрія (мільйони дерев, пакети щогодини від кожної Queen) може витіснити критичні Web3 nonce locks → EVM nonce collision → double-spend на Polygon. При масштабі мільярдів-трильйонів дерев обсяг Sidekiq-черг та rate-limit counters зростає експоненціально, і shared Redis database стає single point of contention.

### Рішення: 3 Redis DB + 2 PostgreSQL-Backed + 1 In-Process

Система розділяє всі stateful підсистеми на ізольовані сховища. Кожна підсистема використовує окремий Redis DB number (або зовсім не Redis), що гарантує неможливість взаємного витіснення:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Upstash Serverless Redis (TLS)               │
│  ┌──────────────────────┬──────────────────┬──────────────────┐ │
│  │  DB 0: Sidekiq       │  DB 1: Kredis    │  DB 2: Rack::Atk │ │
│  │  Job queues          │  Distributed     │  Rate-limit      │ │
│  │  Scheduler           │  locks (Web3     │  counters        │ │
│  │  9 priority queues   │  nonce mgmt,     │  per-IP/DID      │ │
│  │                      │  M2M nonce)      │  (10 min TTL)    │ │
│  └──────────────────────┴──────────────────┴──────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────┬──────────────────────────────┐
│  PostgreSQL: Solid Cache         │  PostgreSQL: Solid Cable     │
│  Rails.cache (domain caching)    │  ActionCable adapter         │
│  Web3 circuit breaker state      │  POLLING (не pub/sub)        │
│  Alert silence windows           │  Multi-replica safe          │
│  Dashboard stats                 │  No sticky sessions          │
└──────────────────────────────────┴──────────────────────────────┘

┌──────────────────────────────────┐
│  In-Process RAM (SinLruRedux)    │
│  HardwareKey AES binary keys     │
│  Max 10,000 entries (~320 KB)    │
│  Keys never leave Ruby process   │
└──────────────────────────────────┘
```

### Детальна таблиця ізоляції

| Підсистема | Сховище | Redis DB | ENV змінна | Конфігурація | TTL / Eviction |
|-----------|---------|----------|------------|--------------|----------------|
| **Sidekiq** (9 черг, scheduler) | Upstash Redis | **DB 0** | `REDIS_URL` | `config/initializers/sidekiq.rb` | Persistent (no eviction) |
| **Kredis** (distributed locks) | Upstash Redis | **DB 1** | auto-derive з `REDIS_URL` [B1] | `config/redis/shared.yml` | 1–300 sec (lock TTL) |
| **Rack::Attack** (rate limiting) | Upstash Redis | **DB 2** | `RACK_ATTACK_REDIS_URL` | `config/initializers/rack_attack.rb` | 10 min |
| **Rails.cache** (Solid Cache) | PostgreSQL | — | — | `config/cache.yml` + `config/environments/production.rb` | ⚠️ **Розмірна стеля, НЕ вікова** — живе лише `max_size` (256 MB, LRU); `max_age` у `cache.yml` закоментований, тож віку запису ніхто не обмежує |
| **ActionCable** (Solid Cable) | PostgreSQL | — | — | `config/cable.yml` | 1 day message retention |
| **Hardware Key Cache** | In-Process RAM | — | — | `config/initializers/hardware_key_cache.rb` | Process lifetime |

### ENV змінні та автоматична деривація

```bash
# Обов'язкові:
REDIS_URL=rediss://default:password@endpoint.upstash.io:6379/0       # Sidekiq (DB 0)

# Опціональні (auto-derive з REDIS_URL — НЕ задавати без потреби, інакше перебиває derive):
# KREDIS_REDIS_URL      — Kredis locks; auto-derive /0 → /1 у config/redis/shared.yml [B1]
# RACK_ATTACK_REDIS_URL — rate-limit; auto-derive /0 → /2 у config/initializers/rack_attack.rb
```

Логіка auto-derive у `config/initializers/rack_attack.rb`:
```ruby
ENV.fetch("RACK_ATTACK_REDIS_URL") {
  uri = URI.parse(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  uri.path = "/2"
  uri.to_s
}
```

Аналогічна логіка для Kredis у `config/redis/shared.yml` та Terraform `main.tf`.

### Чому саме ця архітектура

1. **Sidekiq (DB 0)**: Найбільший обсяг даних — мільйони телеметричних job'ів щогодини. Ізоляція на DB 0 запобігає витісненню Web3 locks.
2. **Kredis (DB 1)**: Критичні distributed locks для Web3 nonce management (`BlockchainMintingService`, `BlockchainBurningService`, `CeloRewardService`), M2M nonce anti-replay. Lock TTL 30 sec = **concurrent** guard; **[ARCH.45]** durable money-path idempotency тепер тримає DB intent-marker + `BlockchainTransaction.in_flight` guard (не лише ephemeral lock) для slash/Solana payout — витіснення локу більше не єдина лінія проти double-spend ([`04_02 §4/§10`](04_02_Business_Logic_and_Services)).
3. **Rack::Attack (DB 2)**: Rate-limit counters з TTL 10 min. Менший обсяг, але потребує ізоляції від Sidekiq щоб counters не губились при spike-ах.
4. **Solid Cache (PostgreSQL)**: Rails.cache для Web3 circuit breaker state, dashboard stats, alert silence windows. PostgreSQL гарантує durability — circuit breaker state не зникає при Redis restart.
5. **Solid Cable (PostgreSQL)**: ActionCable через PostgreSQL — zero Redis dependency, multi-replica safe без sticky sessions. ⚠️ Механізм — **опитування**, не `LISTEN/NOTIFY`: кожен web-процес тримає listener-тред, що `SELECT`-ить нові рядки кожні `polling_interval`. Три наслідки для ємності (дім — `config/cable.yml`): латентність має підлогу ~`polling_interval`; вартість опитування росте з кількістю процесів, не подій; ціна броадкасту платиться НА ЗАПИСІ, навіть за нуля підписників. ⚠️ Метод адаптера НАЗВАНИЙ `listen`, тож греп по «listen» дає хибне підтвердження pub/sub — усередині це `loop { … sleep polling_interval }`.
6. **In-Process RAM**: AES hardware keys — Zero Network Exposure. Ключі ніколи не серіалізуються і не передаються по мережі.

### Масштабування (мільйони → мільярди → трильйони дерев)

| Масштаб | Дерев | Queens | Sidekiq jobs/год | Redis DB стратегія |
|---------|-------|--------|------------------|--------------------|
| **Pilot** (TRL 6-7) | ~1,000 | ~50 | ~50K | Single Upstash instance, 3 DBs |
| **Regional** (TRL 8) | ~1M | ~50K | ~50M | Upstash Pro, 3 DBs + dedicated Sidekiq |
| **Planetary** (TRL 9) | ~1B+ | ~50M | ~50B | Separate Redis clusters per DB: Sidekiq cluster (DB 0), Kredis cluster (DB 1), Rack::Attack cluster (DB 2). Або Upstash multi-region з read replicas. |

При planetary масштабі кожен DB може потребувати окремий Redis cluster або Upstash instance з окремим endpoint. ENV архітектура вже це підтримує — кожна підсистема має окрему ENV змінну.

---

## 📦 Kamal — Детальний Аналіз

### Файлова структура

| Файл | Опис |
|------|------|
| `config/deploy.yml` | Production-конфіг (основний) |
| `config/deploy.canopy.yml` | Canopy-перевизначення (`-d canopy`). **Web-only СТРУКТУРНО** — `servers:` = array-форма, яку deep_merge замінює цілком (омітнута `job:`-секція НЕ прибирає роль: destination-merge = keys-union, роль успадкувалась би з base разом із money-`env.secret` → present-empty guard-crash; INF.22). Sidekiq для Canopy іде через Akash primary `deploy.yaml` job-сервіс (INF.13). |
| `.kamal/secrets-common` | Runtime секрети (читаються при деплої) |
| `.kamal/hooks/` | Хуки ЖЦ (тільки sample-файли) |

### `config/deploy.yml` — Production

```yaml
service: silken_net
image: <GCP_PROJECT_ID>/silken-net/silken_net   # повний AR-шлях (registry.server prepend; INF.15)

servers:
  web:
    - 192.168.0.1            # ⚠️ PLACEHOLDER — замінити на реальну IP
  job:
    hosts:
      - 192.168.0.1          # ⚠️ PLACEHOLDER
    cmd: bundle exec sidekiq -C config/sidekiq.yml
    env:
      secret:                       # Money/signing-ключі = JOB-ONLY (п'ятірка:
        - ORACLE_MINTER_PRIVATE_KEY #  MINTER/SLASHER/CELO + ETHEREUM_ANCHOR +
        - …                         #  SOLANA_WALLET_KEYPAIR; legacy ORACLE_PRIVATE_KEY
                                    #  RETIRED — INF.22) — web/coap бутяться keyless;
                                    #  guard scoped signer_process: Sidekiq.server?
  coap:
    cmd: bundle exec ruby lib/daemons/coap_listener
    options:
      publish: ["5683:5683/udp"]   # UDP повз kamal-proxy (він HTTP-only)

boot:
  proxy:
    publish:                 # HTTP/S only — kamal-proxy НЕ проксіює UDP;
      - "80:80"              # 5683/udp публікує coap-роль напряму (вище)
      - "443:443"

registry:
  # [INF.22] Keyless: oauth2accesstoken + short-lived WIF access token (НЕ
  # _json_key_base64 + JSON) — CI видає його auth-кроком, локально
  # `gcloud auth print-access-token`. Дзеркалить config/deploy.yml.
  server:   europe-west1-docker.pkg.dev
  username: oauth2accesstoken
  password:
    - GCP_ARTIFACT_REGISTRY_KEY

env:
  secret:
    # --- Application core (host/user/database → env.clear, component style) ---
    - RAILS_MASTER_KEY
    - POSTGRES_PASSWORD
    - REDIS_URL
    # KREDIS_REDIS_URL omitted — Kredis auto-derives DB 1 from REDIS_URL (config/redis/shared.yml). [B1]
    # --- Observability ---
    - SENTRY_DSN
    # --- Hardware provisioning gate (config/initializers/master_key_strength_check.rb) ---
    - PROVISIONING_MASTER_KEY
    # --- Money/signing-ключі НЕ ТУТ: JOB-ONLY (servers.job.env.secret вище) —
    #     п'ятірка CELO/MINTER/SLASHER + ETHEREUM_ANCHOR + SOLANA_WALLET_KEYPAIR,
    #     однакова на Kamal і SDL (legacy ORACLE_PRIVATE_KEY RETIRED — INF.22);
    #     web/coap бутяться keyless (Web3NetworkGuard signer_process: Sidekiq.server?) ---
    # --- RPC endpoints (SSOT names expected by Web3::RpcConnectionPool) ---
    - ALCHEMY_POLYGON_RPC_URL
    - ALCHEMY_ETHEREUM_RPC_URL
    - SOLANA_RPC_URL
    # --- Solana публічні ідентифікатори (signing keypair — job-only) ---
    - SOLANA_FEE_PAYER_PUBKEY
    - SOLANA_FEE_PAYER_TOKEN_ACCOUNT
    - SOLANA_USDC_MINT_ADDRESS
    # --- Webhook HMACs: Chainlink callback (dispatch removed — ARCH.53) + Helium SOS (ARCH.34) ---
    - CHAINLINK_HMAC_SECRET
    - HELIUM_WEBHOOK_SECRET
  clear:
    POSTGRES_HOST: <CLOUD_SQL_PRIVATE_IP>    # component style (config/database.yml; INF.16)
    POSTGRES_USER: silken_net
    POSTGRES_DATABASE: silken_net_production  # canopy override → silken_net_canopy (deploy.canopy.yml)
    WEB_CONCURRENCY: 2
    APP_HOST: silkennet.com                   # Action Mailer host (INF.13)
    COAP_HOST: api.silkennet.com              # UDP-проба панелі здоров'я (ARCH.81) — той самий хост, що набирає Королева
    WEB3_STRICT_MODE: "true"                  # Web3 fail-closed (INF.11)
    RELEASE_VERSION: "${RELEASE_VERSION}"     # Sentry release tag (CI-set)
    # RAILS_ALLOWED_HOSTS: …  # ⚠️ operator-set, НЕ комітити (хибне значення = 403 block-all; S6.18 + INF.4)
    # DISABLE_SSL / CSP_ENFORCE — операторські тогли
```
> **One-home:** це ілюстрація структури. **Повний інвентар ENV** (secret + clear, контракт-адреси, RPC, credentials) — лише [`06_04 §2.1`](06_04_Secrets_Checklist); не дублювати тут.

> **🔴 Boot-time guard rationale:** Container injects ТІЛЬКИ ті secrets, що явно перелічені у `env: secret:`. Відсутність `PROVISIONING_MASTER_KEY` → `SecurityError` від `config/initializers/master_key_strength_check.rb` → Puma crash до accept. Відсутність `ORACLE_*_PRIVATE_KEY` → `KeyError` від `ENV.fetch` у `BlockchainMintingService`/`BlockchainBurningService` → web3-критичні воркери у DeadSet. Відсутність `ALCHEMY_ETHEREUM_RPC_URL` → `StateAnchorService` падає при тижневому anchor TX → `EthereumAnchor.status = failed`. **Bind these in `.kamal/secrets-common` first**, потім додавай у `env: secret:` блок.

> **Нові ENV змінні безпеки** (деталі у [`06_04 §2.1`](06_04_Secrets_Checklist)):
>
> | ENV | Тип | Default | Опис |
> |-----|-----|---------|------|
> | `RAILS_ALLOWED_HOSTS` | `env.clear` | — (попередження) | Comma-separated allowlist для DNS-rebinding захисту. ⚠️ Обов'язково у production. |
> | `DISABLE_SSL` | `env.clear` | `false` | Вимикає `force_ssl`/`assume_ssl`. Тільки якщо TLS термінується upstream (Cloudflare/Akash ingress). |
> | `ALLOW_ALL_HOSTS` | `env.clear` | `false` | Заглушує попередження `[SECURITY]` якщо `RAILS_ALLOWED_HOSTS` не встановлено. |
> | `CSP_ENFORCE` | `env.clear` | `false` | Переводить CSP з report-only у enforced. Рекомендується після burn-in (1–2 тижні). |

```bash
kamal rollback
kamal app exec --interactive --reuse "bin/rails console"
kamal logs -f
kamal app exec --interactive --reuse "bash"
# Canopy:
kamal app exec --interactive --reuse "bin/rails console" -d canopy
kamal logs -f -d canopy
```

---

## 🏗️ Terraform (GCP) — Детальний Аналіз

### Файлова структура

```
terraform/
├── main.tf       # Provider (google ~> 7.0), GCP APIs, Artifact Registry
├── vpc.tf        # VPC, subnet (10.0.0.0/20), Cloud Router, Cloud NAT, Firewall
├── compute.tf    # Ingress Anchor (e2-small, silken-net-ingress), Static IP + CoAP-демон (PRIMARY)
├── database.tf   # Cloud SQL PostgreSQL 17, 3 databases (primary/cache/cable — Solid Queue pruned INF.18) + canopy-тріо, Private Service Access
├── iam.tf        # Service Account silken-net-deploy + IAM roles (deploy-SA + IAP-operator)
├── variables.tf  # Всі input variables з валідацією
└── outputs.tf    # ingress_ip, DB URL тощо

terraform/akash/
├── main.tf       # SDL generation, null_resource (akash CLI)
├── variables.tf  # Akash-specific variables + app secrets + Grafana Cloud
└── outputs.tf    # SDL path, deployment notes
```

> **Примітка:** `redis.tf` видалено — Redis тепер обслуговується Upstash (serverless, зовнішній сервіс, не GCP). `compute.tf` більше не містить web/canopy VMs — лише Ingress Anchor (`e2-small`): CoAP-демон (PRIMARY інтейк, docker + systemd, секрети в `/etc/silkennet/coap.env` 0600 — НЕ в metadata) + HAProxy 80/443 → Akash + socat-fallback. Grafana Alloy `config.alloy` знаходиться в `deploy/akash/config.alloy` і кодується в Base64 через `filebase64()` при рендерингу SDL шаблону.

### GCP Region та Zone

| Параметр | Значення |
|---------|---------|
| Region | `europe-west1` (Belgium) |
| Zone | `europe-west1-b` |
| Причина | GDPR compliance + найближче до України |

### Firewall

| Правило | Порти | Джерело |
|---------|-------|---------|
| `allow-iap-ssh` | TCP 22 | `35.235.240.0/20` (Google IAP — канонічний SSH-шлях, INF.20 (в): keyless, доступ = `iap_admin_members`) |
| `allow-ssh` | TCP 22 | `ssh_source_ranges` (break-glass-only; normally `[]` → правило не створюється) |
| `allow-web` | TCP 80, 443 | `0.0.0.0/0` |
| `allow-coap` | UDP 5683 | `0.0.0.0/0` |
| `allow-internal` | Усі | `10.0.0.0/20` |
| `deny-all-ingress` | Усі | `0.0.0.0/0` (priority 65534) |

### IAM

```
Service Account: silken-net-deploy@<project>.iam.gserviceaccount.com
Ролі deploy-SA (iam.tf):
  - artifactregistry.writer   (push Docker images)
  - artifactregistry.reader   (pull на анкорі/fallback)
  - compute.instanceAdmin.v1  (Kamal SSH deploy)
  - compute.osLogin           (OS Login на анкор — SSH-модель, INF.20)
  - iam.serviceAccountUser    (impersonation)
  - logging.logWriter         (Cloud Logging)
  - monitoring.metricWriter   (Cloud Monitoring)
  - cloudsql.client           (Cloud SQL connect)
  - storage.objectAdmin       (GCS Terraform state, scoped до bucket)
IAP-operator ролі (iam.tf, for_each `iap_admin_members` — люди-адміни, не SA):
  - compute.osAdminLogin       (sudo на анкорі через IAP-тунель, INF.20)
  - iap.tunnelResourceAccessor (відкриття IAP-тунелю)
```

### Розрахунок `max_connections` (database.tf)

Поточне значення `400`. Формула пулу — SSOT у `config/database.yml` (коментований блок): `pool = RAILS_MAX_THREADS + PUMA_MAX_IO_THREADS + 2 (Cable headroom) = 3 + 16 + 2 = 21` на процес, на кожну з 3 баз набору (primary/cache/cable — Solid Queue pruned, INF.18). IO-доданок — [INF.22]: Puma-8 `max_io_threads` дозволяє io-маркованим запитам (oracle_callbacks/provisioning) бігти ПОНАД `max_threads`, і кожен тримає DB-checkout — пул без цього доданку голодує під сплеском (`ConnectionTimeoutError`). Пул = стеля, не преалокація: з'єднання відкриваються за потребою і реляться, тож фактичне число значно нижче.

| Компонент | З'єднання (стеля checkout) |
|-----------|------------|
| Akash web | `WEB_CONCURRENCY` (4) × pool (21) × 3 бази = **252 стеля** (факт ≪: io-burst рідкісний, idle реляться) |
| Akash job (Sidekiq) | `:concurrency` (15) → `DB_POOL=17` (встановлено в job env, INF.13) = **~51** (17 × 3 бази) |
| Cloud SQL Auth Proxy + admin/console | **~8** |

Навіть за одночасного пікового checkout усіх пулів — нижче `400` (≈311); запас під read-репліки/canopy тримається на тому, що web-стеля досяжна лише при повному io-burst усіх воркерів одночасно (не steady-state). Адекватно; ревізит при `WEB_CONCURRENCY` > 4.

> ⚠️ **Друга вісь того самого бюджету — ГОРИЗОНТАЛЬНА, і в будь-якому плані scale-out вона приходить першою.** Тригер `WEB_CONCURRENCY > 4` вертикальний, але арифметика ламається ідентично на **другому web-вузлі при тій самій конкурентності**: 2 × 252 + 51 + 8 = **563 > 400**. Тобто горизонтальне масштабування web упирається не в CPU і не в пам'ять аппки, а в цей рядок Terraform. Важелів рівно два, і обидва вимагають рішення заздалегідь: підняти `db_max_connections` (на `db-custom-2-7680` кожне з'єднання коштує реальну пам'ять — тобто це тягне і зміну tier) **або** завести пулер, якого в репозиторії немає **ніде** (`db_read_replica_count` теж `0`). Наслідок ширший за ємність: цей самий інстанс несе primary + cache + cable + canopy-staging, тож за REGIONAL-HA байти UI-фан-ауту cable реплікуються тим самим WAL, що money-записи — один інстанс вниз = money+cable+cache+staging разом. Ревізит: **або** `WEB_CONCURRENCY > 4`, **або** web-репліка №2 — що настане раніше.

---

## 🐳 Docker — Multi-stage Build

```
Stage 1: base          — ruby:4.0.6-slim + libjemalloc2, libvips (≥ 8.13), postgresql-client
Stage 2: build         — bundle install, bootsnap, assets:precompile
Stage 3: final         — COPY gems + app + Cloud SQL Auth Proxy, USER rails:1000, CMD: thrust ./bin/rails server
```

> **`libvips ≥ 8.13` — несуча межа, не косметика (2026-07-30).** Active Storage при буті кличе `Vips.block_untrusted(true)`, щоб вимкнути «unfuzzed» лоадери libvips (CVE-2026-66066); на старішій бібліотеці метод відсутній і Rails **не стартує взагалі** — тобто відкат base-образу на давніший Debian ламає не картинки, а весь застосунок. Той самий пакет потрібен CI-джобам, які реально ініціалізують Rails (`.github/actions/setup-rails-test` → `test`/`feature-test`); гем `ruby-vips` стоїть `require: false`, тож `bin/rails`-гейти без `:environment` (docs/i18n-смуги) його не вантажать і libvips їм не потрібна. Trixie дає 8.16.1, ubuntu-24.04 — 8.15.1, ubuntu-26.04 — 8.18.0.

> **Cloud SQL Auth Proxy** вбудовано у фінальний Docker-образ. Proxy запускається автоматично як фоновий процес при наявності ENV `CLOUD_SQL_INSTANCE_CONNECTION_NAME`. Він тунелює PostgreSQL-трафік через Google Cloud API (вихідний HTTPS на порт 443), тому Cloud SQL не потребує публічної IP. **Fail-loud (INF.13):** `bin/docker-entrypoint` чекає готовності proxy до 15 с; якщо не відповідає — `exit 1` (Rails не стартує, замість мовчазного boot без БД). **Post-boot supervisor (INF.22, 2026-07-05):** при активному proxy entrypoint далі НЕ `exec`-ає, а тримає app і proxy siblings-процесами: смерть proxy → TERM аппці + `exit 1` (Akash рестартить контейнер лише на вихід PID 1 — без цього мертвий proxy = вічний зомбі, що віддає DB-помилки); вихід аппки → її exit-код пропагується; TERM/INT форвардяться (graceful drain при `docker stop`). Kamal/VPC-шлях (без proxy) лишається чистим `exec`.

---

## 🚀 Akash SDL — Технічний Аналіз

### Файлова структура

| Файл | Призначення |
|------|------------|
| `deploy/akash/deploy.yaml` | Статичний SDL — ручний деплой |
| `deploy/akash/deploy.yaml.tpl` | Шаблон SDL (Terraform рендерить) |
| `terraform/akash/main.tf` | `local_file` + `null_resource` (CLI wrapper) |
| `terraform/akash/generated-deploy.yaml` | Генерується Terraform, права `0600` |

### Процес Akash деплою (через Terraform)

```bash
cd terraform/akash
# Створити terraform.tfvars з prefer-fuller екземпляра:
#   cp terraform.tfvars.example terraform.tfvars
# Повний набір змінних (мірор .kamal/secrets-common, ~25 sensitive):
#   akash_key_name, docker_image
#   rails_master_key, db_password, cloud_sql_instance_connection_name,
#     gcp_sa_key_base64, redis_url, kredis_redis_url
#   provisioning_master_key  ← 🛑 BOOT-CRITICAL
#   sentry_dsn, prometheus_auth_user/password
#   grafana_remote_write_url/username/token
#   oracle_minter_private_key, oracle_slasher_private_key,
#     ethereum_anchor_private_key   (легасі oracle_private_key RETIRED — INF.22)
#   alchemy_polygon_rpc_url, alchemy_ethereum_rpc_url, solana_rpc_url
#   solana_wallet_keypair, solana_fee_payer_pubkey,
#     solana_fee_payer_token_account, solana_usdc_mint_address
#   chainlink_hmac_secret (dispatch-секрети вилучено — ARCH.53)

terraform init
terraform apply

akash query market bid list --owner <your-address> --dseq <DSEQ>
akash tx market lease create --dseq <DSEQ> --provider <provider-address> --from silken-deploy

akash provider send-manifest terraform/akash/generated-deploy.yaml \
  --dseq <DSEQ> --provider <provider-address> --from silken-deploy

akash provider lease-status --dseq <DSEQ> --provider <provider-address> --from silken-deploy
```

---

## 📋 DEPLOY-DAY: перший деплой фазами (Priority Order)

> Переписано 2026-07-04 після операторського red-team: старий 18-крок чеклист мав
> ordering-інверсії (Upstash після секретів, що його вимагають), фантом-кроки і
> доменні суперечності. Машинні «☑ виправлено»-пункти прибрано (вони в git/00_07 §🗄️).
> Два шляхи НЕ плутати: **твій перший деплой = ручний Akash canopy-render** (Фаза 3);
> CI `Deploy · Canopy` — то Kamal→GCP web-only **fallback**, він оживе сам, щойно
> GitHub Secrets заповнені (тримай їх незаповненими до готовності; path-gate вже стоїть —
> деплой стріляє лише на deploy-релевантні зміни, [`06_07 §1`](06_07_CICD_and_Runbook_Index)).

**Фаза −1 — Акаунти й значення (за дні ДО дня X):**
GCP project + billing (+budget alert — OPS.11) · Akash-гаманець (`akash keys add`) + ≥5 AKT ескроу ·
**Upstash ×2** (production + canopy) → 2× `rediss://` URL · Cloudflare + **два домени:
`silkennet.app`** (HTTPS, proxied) **та `silkennet.com`** (його піддомен `api.silkennet.com` —
CoAP DNS-only; firmware Queen хардкодить саме його, `COAP_SERVER_HOST`) · Grafana Cloud
stack (remote_write URL/user/token) · Sentry project (DSN) · Alchemy (Polygon+ETH) +
Helius/QuickNode (Solana mainnet) RPC · 4+ Web3-гаманці (oracle/minter/slasher/anchor
+ опц. celo) + газ MATIC/ETH/SOL/CELO · SSH ed25519 keypair · згенерувати
`RAILS_MASTER_KEY`-бекап + `PROVISIONING_MASTER_KEY` → **vault + offline-копія (DR.1)**.

**Фаза 0 — Bootstrap інфри:**
`terraform/bootstrap.sh` (GCS state-bucket + CMEK-латч [SEC.22]: keyring `silken-tfstate-ew1`,
PAP, retention 10в/30д; має разовий 30s IAM-sleep — не переривай) → `terraform.tfvars` (project_id, db_password,
`ssh_source_ranges=[<твій реальний CIDR>]` — приклад у tfvars = TEST-NET-3, НЕ лишай!) →
GitHub Secrets **Batch A** (pre-infra: `GCP_PROJECT_ID`, `POSTGRES_PASSWORD`,
`RAILS_MASTER_KEY`, `PROVISIONING_MASTER_KEY`, `ACTIVE_RECORD_ENCRYPTION_*`×3
(`db:encryption:init`; boot-critical [SEC.22] — verify-secrets гейтить) — SA-JSON
`GCP_SA_KEY` більше НЕ потрібен: CI keyless через WIF, INF.22) → tfvars: `iap_admin_members`
(твій e-mail) + [INF.21] `coap_daemon_image` = іммутабельний `sha-<commit>` →
`terraform init && plan && apply` (перший apply — локально твоїм ADC; він створює WIF-pool,
тож CI не потребує ключа з дебюту) → зчитати outputs (`ingress_ip`, `database_private_ip`,
`artifact_registry_url` + `workload_identity_provider`/`service_account_email` → repo
**Variables** `GCP_WORKLOAD_IDENTITY_PROVIDER`/`GCP_SERVICE_ACCOUNT`, після чого CI-деплой keyless). **SSH на анкор = IAP-тунель + OS Login (INF.20 (в), wired):**
`gcloud compute ssh silken-net-ingress --tunnel-through-iap --zone europe-west1-b` —
порт 22 в інтернет не відкритий, ключі keyless (керує OS Login); Kamal-нога = (б)-клей
за потребою (`ssh.proxy_command` через `start-iap-tunnel` + SA-ролі); Akash-шлях
(Фаза 3) від SSH не залежить.

**Фаза 1 — Дротування post-infra:**
GitHub Secrets **Batch B** — ДВА доми [INF.22]: repo-level = `REDIS_URL`,
`CANOPY_REDIS_URL`, RPC×5, Solana-public×3, `SENTRY_DSN`, `CHAINLINK_HMAC_SECRET`,
`HELIUM_WEBHOOK_SECRET`; **money-п'ятірка (`ORACLE_MINTER/SLASHER/CELO` +
`ETHEREUM_ANCHOR_PRIVATE_KEY` + `SOLANA_WALLET_KEYPAIR`) = ЛИШЕ environment
`production`** (`gh secret set <NAME> --env production`; environment уже створений API з
wait-timer + ref-policy — [`06_04 §1`](06_04_Secrets_Checklist)). ⚠️ Пастка wrong-home:
покладеш п'ятірку repo-level — деплой лишиться ЗЕЛЕНИМ (environment-jobs бачать
repo-секрети як fallback), але ізоляція тихо знульована, а реверс = ручне повторне
введення значень (GitHub секретів назад не віддає) → **verify scope ДО деплою:** `ruby scripts/audit_deploy_secret_scope.rb` (S1.1 — read-only `gh`-preflight: money-квінтет ∈ env `production` ТІЛЬКИ (не repo), WIF-ids = Variables, retired ∉; ловить wrong-home перш ніж деплой його замаскує) → DNS: `api.silkennet.com` **A → ingress_ip
(DNS-only, сіра хмарка!)** + `silkennet.app` CNAME → Akash ingress (proxied, після Фази 3) →
Kamal-плейсхолдери: `image:` AR-шлях, servers-IP, `POSTGRES_HOST` (S1.5/INF.15) →
**заповнити `/etc/silkennet/coap.env` на анкорі** (7 значень: `POSTGRES_PASSWORD`/
`REDIS_URL`/`RAILS_MASTER_KEY`/`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`/`_DETERMINISTIC_KEY`/
`_KEY_DERIVATION_SALT`/`SENTRY_DSN`; **НЕ** `PROVISIONING_MASTER_KEY` — coap лише
enqueue-ить, `master_key_strength_check` його `$PROGRAM_NAME`-skip-ає [SEC.22]; AR-encryption
×3 = boot-critical, guard fail-closed без них; Postgres-host уже впечатаний terraform'ом) →
`systemctl restart coap-daemon` → `bin/coap_smoke --host <ingress_ip>`.

**Фаза 2 — Контракти (до першого mint; можна паралельно з Фазою 3):**
fund deployer wallet → export 6 ENV (`DEPLOYER_PRIVATE_KEY`/`ADMIN_ADDRESS`/`MINTER_ORACLE`/`SLASHER_ORACLE`/`ANCHOR_ORACLE`/`DAO_TREASURY_ADDRESS`) + `REQUIRE_SAFE_ADMIN=true` (mainnet-гейти: ADMIN+TREASURY = Safe-контракти, `MINTER != SLASHER` E.2) → `forge script contracts/script/Deploy.s.sol --broadcast --verify`
(ordered SCC→SFC→Anchor→Timelock→Governor→ProtocolParameters — [`05_03`](05_03_Tokenomics_SCC_and_SFC)) →
зібрати 9 адрес → вписати у `config/deploy.yml` env.clear + Akash SDL (INF.12) → redeploy job.

**Фаза 3 — ПЕРШИЙ деплой = Akash CANOPY-render (founder 2026-07-04):**
`terraform/akash/terraform.tfvars` з example (розкоментувати canopy-пару
`deployment_slot`/`postgres_database`!) → `terraform apply` → прийняти bid → send-manifest →
web/job/coap up → `gcloud compute instances add-metadata silken-net-ingress
--metadata akash-deployment-ip=<AKASH_IP>` + `reset` (Pre-Flight #10). Найризикованіший
шлях не дебютує на production; ізольований DB-set `silken_net_canopy` (INF.16).

**Фаза 4 — Верифікація (єдиний post-deploy список):**
`db:prepare` пройшов усі 3 бази (INF.16) · `curl https://silkennet.app/up` → 200 +
`/ready` → 200 (DB+Redis+Kredis) · `coap_smoke` зелений + задати repo Variables
`CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` (INF.6) · метрики: 3 process-таргети живі,
job-серії ≠ 0 (S2.4/INF.14) · Grafana-сесія: `deploy/grafana/import.rb` (dashboards+alerts+contact point)
+ contact point (S2.2/S2.4) · `/sidekiq` під admin-сесією → 200, під анонімом → 404
(ARCH.61 route-constraint — ops-інструмент DeadSet-runbook'ів живий і закритий) ·
`ss -tlnp | grep 3000` IPv6 (PUMA-IPV6-1) · money fail-closed
(INF.11) · Sentry release (S5.2) · mailer/DB_POOL/entrypoint (INF.13) · гаманці з газом
(Pre-Flight #3).

**Фаза 5 — Production-render + hardening:**
⏱️ [INF.22] Перший release-run **зависне ~10 хв PENDING ×2** (environment wait-timer,
per-job: перед `verify-secrets` і перед `deploy`) — це НЕ зависання, НЕ скасовуй run;
вікно = навмисний solo-approval-substitute ([`06_04 §1`](06_04_Secrets_Checklist)).
Akash production-render (дефолтні vars) → повтор Фази 4 → `RAILS_ALLOWED_HOSTS=
silkennet.app,api.silkennet.com` у env.clear/SDL (S6.18 — ОБИДВА легітимні хости:
app = Cloudflare-HTTPS, api = анкор-шлях) → [INF.10] фліп `proxy.healthcheck.path: /ready`
у `config/deploy.yml` ЛИШЕ після `/ready`→200 (на холодному старті /ready 503-ить →
kamal-proxy довбе до deploy_timeout → rollback; дефолт /up прощає bring-up; повільний
cold-start → підняти deploy_timeout; проба = ReadinessController, [`06_05`](06_05_Puma_Configuration)) →
CSP burn-in 1-2 тижні → `CSP_ENFORCE=true`.

**Фаза 6 — Залізо (Pre-Flight #4/#5):**
антена ДО живлення · AES-парність Soldier↔Queen побітово · прошивка Queens
(`COAP_SERVER_HOST=api.silkennet.com`) · перший boundary-smoke з Queen/`bin/forest_simulator`.

---

## 🌐 Масштабування до Планетарного Рівня — CoAP/UDP та Ingress

> Цей розділ описує архітектурні ризики та рекомендації для переходу від сотень до **мільйонів** вузлів. Поточна архітектура (CoAP прямо в Rails) є коректною для TRL 5–6, але потребує еволюції перед Series D.

### ✅ Ризик-1 & Ризик-2 — Conntrack + UDP Rate Limiting (Виправлено)

Обидва ризики вирішені в `terraform/compute.tf` (`startup-script` Ingress Anchor):
- **conntrack**: `nf_conntrack_max=2000000`, `nf_conntrack_udp_timeout=30s` — 2M entries замість 65K дефолт.
- **UDP rate limit**: `iptables` hashlimit 100 pkt/s per IP + burst 200; DROP з LOG (max 10/хв у Cloud Logging). Налаштування зберігаються через `/etc/sysctl.conf` та `iptables-persistent`.

### 🟡 Ризик-3: IP Exhaustion при Динамічних IP Шлюзів

**Проблема:** Якщо Queen-шлюзи мають динамічні IP (мобільний інтернет через SIM7070G) → при мільйонах шлюзів таблиця маршрутизації та whitelist-правила стають некерованими.

**Мітигація:** Аутентифікація Queen через AES-CBC підпис батча (вже реалізовано) + queen_uid у URI — IP не має значення. Firewall не потрібно прив'язувати до IP шлюзів.

---

### 🏗️ Series D Architecture Upgrade — Ingress Proxy + Kafka

Для обробки **>1M пакетів/годину** від мільйонів дерев потрібна буферизована архітектура між мережею та Rails:

```
Поточна архітектура (TRL 5–6):
  Queen → CoAP/UDP → lib/daemons/coap_listener.rb → Sidekiq → Rails

Series D архітектура (>1M вузлів):
  Queen → CoAP/UDP → [Ingress Proxy Rust/Go] → Kafka / Google Pub-Sub → [Rails Consumers]
```

#### Ingress Proxy (Rust або Go)

- **Роль:** Ультралегкий stateless proxy. Приймає UDP, валідує AES-CBC підпис, збирає пакети в батчі, кидає в Kafka
- **Мова:** Rust (tokio + bytes) або Go (net/udp + goroutines) — обидва дають < 1 мс latency при 100k req/s
- **Rails не бачить сирого UDP** — тільки готові батчі з черги

#### Kafka / Google Pub-Sub (Message Buffer)

- **Роль:** Буфер між Proxy та Rails. Якщо Rails тимчасово перевантажений → пакети не губляться, вони чекають у черзі
- **Throughput:** Kafka — до 1M msg/s на одному брокері; Pub-Sub — горизонтальна масштабованість без обмежень
- **Партиціювання:** За `queen_uid` → гарантований порядок пакетів з одного шлюзу

#### Read-Only PostgreSQL Replicas

- **Правило:** Лише Primary DB пише. Усі аналітичні запити, Oracle-виклики, Grafana-дашборди, The Graph indexer — читають з Read-Only Replicas
- **GCP конфігурація:** Cloud SQL → Add Read Replica (Terraform: `google_sql_database_instance` з `master_instance_name`)
- **Rails конфігурація:** `connects_to(database: { writing: :primary, reading: :replica })`

#### Статус

| Компонент | Поточний стан | Необхідна дія |
|-----------|--------------|--------------|
| CoAP Listener | `lib/daemons/coap_listener` (Ruby) | Достатньо до ~10k вузлів |
| Ingress Anchor (`e2-small`) | ✅ Виправлено (`terraform/compute.tf`) | Bottleneck при >10M дерев — див. нижче |
| Ingress Proxy (Rust/Go) | 🔴 Не реалізовано | Series D milestone |
| Kafka / Pub-Sub | 🔴 Не реалізовано | Series D milestone |
| Read-Only Replicas | 🔴 Не налаштовано | Terraform: `google_sql_database_instance` replica |
| conntrack + UDP rate limit | ✅ Виправлено | `terraform/compute.tf` startup_script |

#### 🌍 Front-Door Bottleneck — Ingress Anchor на `e2-small` (Series D)

**Проблема.** Ingress Anchor (`compute.tf`, `silken-net-ingress`) — це один `e2-small` (2 vCPU shared, 2 GB RAM, обмежений egress). CoAP-демон приймає UDP/5683 прямо на ньому (PRIMARY, INF.17); HAProxy проксює 80/443 на Akash. При >10M дерев → мільйони Queens → один VM стає вузьким горлом для CoAP/UDP (демонова стеля ~10k вузлів — E.5 — настане раніше за мережеву).

**Опції еволюції (упорядковані за зростанням інвазивності):**

| # | Підхід | Що дає | Що потрібно |
|---|--------|--------|-------------|
| 1 | **GCP L4 Network Load Balancer + MIG `e2-small`** | Горизонтальний autoscaling, безмежний throughput, та сама статична IP (forwarding rule) | Terraform: `google_compute_forwarding_rule` (L4 UDP) + `google_compute_region_instance_group_manager` з autoscaler; стартап-скрипт ідентичний існуючому (CoAP-демон на кожному інстансі MIG; за стелею демона — ARCH.2 Rust/Go proxy). DNS A не змінюється. |
| 2 | **Cloudflare Spectrum (UDP forwarding)** | Глобальний anycast → найближча PoP-нода, DDoS-фільтрація, без власної VM-інфраструктури | Cloudflare Enterprise (Spectrum — paid add-on); CNAME `api.silkennet.com` на Spectrum endpoint; whitelist Akash origin IP. GCP Ingress Anchor можна вимкнути. |
| 3 | **Ingress Proxy (Rust/Go) + Kafka** (нижче) | Stateless дешифрування AES-CBC + батч у Kafka до того, як Rails побачить пакет | Власна розробка (див. наступний підрозділ). Поєднується з #1 або #2 — L4/Spectrum дають мережевий шар, Proxy дає прикладний. |

> **Рекомендований шлях:** #1 (L4 NLB + MIG) як проміжний крок — мінімум коду, лише Terraform. Якщо у вас уже є Cloudflare Enterprise — #2 дешевший за операцію. #3 (Proxy + Kafka, нижче) обов'язковий при пакетних потоках >1M/год незалежно від мережевого шару.

---

## 🔑 Змінні Середовища: Web3 та Мультичейн

> **One-home:** повний інвентар Web3/мультичейн ENV — secret + clear, RPC (`ALCHEMY_*` + окремий `CELO_RPC_URL`), контракт-адреси (post-`forge deploy` placeholders), Solana/Chainlink, Active-Storage `aws`/`gcs` + credentials-only ключі (peaq/iotex/streamr/the_graph/hadron/filecoin) — живе в [`06_04 §2.1`](06_04_Secrets_Checklist) (+ §2.2 credentials), НЕ дублюється тут. ⚠️ `CELO_RPC_URL` порожній → Alfajores TESTNET (E.49; mainnet обов'язковий); контракт-адреси відомі лише після `forge deploy`.

### Деплой контрактів (Foundry)

```bash
# Встановіть Foundry (https://book.getfoundry.sh/)
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

> **Канонічний деплой — `contracts/script/Deploy.s.sol`** (усі 6 контрактів у правильному порядку SCC→SFC→StateRootAnchor→Timelock→Governor→ProtocolParameters + Gnosis-Safe admin guard `REQUIRE_SAFE_ADMIN`). Точні команди (`forge script … --broadcast --verify`) та ENV — [`05_03`](05_03_Tokenomics_SCC_and_SFC) (§Smart Contract Audit Roadmap). **НЕ** деплоїти контракти поштучно через `forge create` — це пропускає admin-setup, ordered dependencies й 4 з 6 контрактів.
