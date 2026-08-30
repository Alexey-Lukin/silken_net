# 06_01: Розгортання Kamal & Terraform (Canopy vs Production)

## 🎯 Мета

Зафіксувати повний стан конфігурацій розгортання та інфраструктури як коду (IaC). Документ відповідає на три ключові питання:

1. Чим відрізняються середовища **Canopy** (Staging) та **Production**?
2. Що розгортається в **GCP**, а що — у зовнішніх SaaS (Upstash, Grafana Cloud, GHCR)?
3. Які **API-ключі, секрети та сертифікати** потрібні для першого реального деплою?

---

## ✅ Статус

- **Поточний TRL:** TRL 4 — інфраструктурний код існує, реальний деплой не проводився
- **Відкрите:** deploy-readiness (акаунт GCP, Ingress IP, GitHub Secrets) → [`00_07`](00_07_Action_Plan_Tracker) (S1.1, INF.4/6, S5.6).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `config/deploy.yml` · `config/deploy.canopy.yml` | Kamal (production / canopy) |
| `terraform/` | IaC: Cloud SQL, Ingress Anchor, **app-хост** (Kamal web+job+coap), VPC, KMS |
| `.github/workflows/deploy.yml` · `deploy-production.yml` | Canopy / Production CI/CD (деталі — [`06_07`](06_07_CICD_and_Runbook_Index)) |
| [`04_02` — Business Logic and Services](04_02_Business_Logic_and_Services) | Backend (що деплоїться) |
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
- [Розподіл Ресурсів між провайдерами](#-розподіл-ресурсів-між-провайдерами)
- [Redis Isolation Strategy](#-redis-isolation-strategy)
- [Kamal — Детальний Аналіз](#-kamal--детальний-аналіз)
- [Terraform (GCP) — Детальний Аналіз](#-terraform-gcp--детальний-аналіз)
- [Docker — Multi-stage Build](#-docker--multi-stage-build)
- [TLS-термінація — Cloudflare](#-tls-термінація--cloudflare-inf4)
- [DEPLOY-DAY: перший деплой фазами (Priority Order)](#-deploy-day-перший-деплой-фазами-priority-order)
- [Масштабування до Планетарного Рівня — CoAP/UDP та Ingress](#-масштабування-до-планетарного-рівня--coapudp-та-ingress)
- [Змінні Середовища: Web3 та Мультичейн](#-змінні-середовища-web3-та-мультичейн)
<!-- TOC:AUTO:END -->

---

## ⚠️ Pre-Flight Checklist (до першого фізичного деплою)

> Доповнення до блокерів Terraform/Kamal — фокус на типових помилках при першому виводі системи в роботу.

Перевірки, що можуть мовчки зламати перший деплой (лічильника нема свідомо — таблиця росте, число в прозі бреше):

| # | Перевірка | Деталі |
|---|-----------|--------|
| **1** | **DNS / TLS до `kamal setup`** | Після `terraform apply` скопіюй IP та створи A-запис (`api.silkennet.com → <IP>`). Дочекайся: `dig api.silkennet.com` → правильний IP. **Тільки тоді** запускай `kamal setup`. Причина: при ввімкненому `proxy.ssl` (зараз **закоментований** у `config/deploy.yml`) **kamal-proxy** (Kamal 2.x — НЕ Traefik 1.x) робить Let's Encrypt ACME-challenge — без живого DNS сертифікат не видасться і проксі не підніметься. 🔴 **Твердження «`proxy.ssl` вимкнено → TLS термінується зовні» стояло тут до 2026-08-30 і було НЕПОВНЕ саме там, де це дорого:** воно правдиве про клієнтське плече й мовчки припускало, що CF→origin іде по HTTP. CF стоїть у `Full (strict)` (виміряно), а той вимагає сертифіката НА ORIGIN — тож із вимкненим `proxy.ssl` origin не має чим відповісти на :443 і web-ярус віддає 521/525. Правильний стан кроку: `proxy.ssl` **увімкнено з Origin CA-парою** (НЕ Let's Encrypt — під `Full (strict)` ACME не доставляється), і саме тому цей крок тепер залежить не лише від DNS, а й від секретів `TLS_ORIGIN_*` (§Сертифікат НА ORIGIN); ACME-передумова вище лишається чинною тільки для TLS-fallback БЕЗ CF. DNS усе одно потрібен для маршрутизації трафіку. |
| **2** | **`.kamal/secrets-common` файл існує + повний** | Kamal читає секрети з `.kamal/secrets-common` (не з environment). Заповни **усі** змінні з `config/deploy.yml env.secret` (drift = boot crash або silent Web3 failure): **(a) Application core:** `RAILS_MASTER_KEY`, `POSTGRES_PASSWORD` (host/user/database — non-secret `env.clear`, component style `config/database.yml`), `REDIS_URL`, `GCP_ARTIFACT_REGISTRY_KEY` (registry pull). `KREDIS_REDIS_URL` — **не** додавати: Kredis читає `REDIS_URL` як є (`config/redis/shared.yml`), а порожній інжект перебив би це значенням «» [B1]; задавати лише щоб вивести локи на ОКРЕМИЙ інстанс. **(b) 🛑 Boot-critical:** `PROVISIONING_MASTER_KEY` (`master_key_strength_check.rb` raises `SecurityError` без неї) + `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`/`_DETERMINISTIC_KEY`/`_KEY_DERIVATION_SALT` ([SEC.22] `active_record_encryption_keys_check.rb` fail-closed; `db:encryption:init`). **(c) Observability:** `SENTRY_DSN`. **(d) Web3 oracle keys:** `ORACLE_MINTER_PRIVATE_KEY`, `ORACLE_SLASHER_PRIVATE_KEY`, `ETHEREUM_ANCHOR_PRIVATE_KEY` — legacy `ORACLE_PRIVATE_KEY` **RETIRED повністю** (INF.22: жоден код не читає, guard-tripwire відмовляє значенню під цим ім'ям); CI-джерело money-п'ятірки (ці три + `SOLANA_WALLET_KEYPAIR`, `ORACLE_CELO_PRIVATE_KEY`) = GH Environment `production`, НЕ repo-secrets (INF.22 → [`06_04 §1`](06_04_Secrets_Checklist)). **(e) RPC endpoints:** `ALCHEMY_POLYGON_RPC_URL`, `ALCHEMY_ETHEREUM_RPC_URL`, `SOLANA_RPC_URL`. **(f) Solana minting:** `SOLANA_WALLET_KEYPAIR`, `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS`. **(g) Chainlink:** `CHAINLINK_HMAC_SECRET` (лише callback-endpoint; dispatch-секрети вилучено — ARCH.53). |
| **3** | **Gas на Web3-гаманцях** | Воркери потребують нативної крипто: **MATIC** (Polygon), **ETH** (L1), **SOL** (Solana), **CELO** (Celo). Без газу → "Insufficient Funds" на кожній транзакції → Sidekiq потоне у ретраях. |
| **4** | **LoRa-антена підключена** | **КРИТИЧНО.** Ніколи не подавай живлення без антени на SMA/U.FL порту. SX1262 відбиває RF назад у чип (high VSWR) — радіотракт згоряє за мілісекунди. Незворотно. Правило: антена → живлення. |
| **5** | **HKDF AES-ключів (post-FW.1 + ARCH.42 + FW.2 (в))** | Кожен Soldier має **per-device session AES-128 LoRa ключ** (`aes_key[4]`, 16 bytes) + **cluster control-plane KEYB** (`bcast_key[4]`, 16 bytes — двоключова модель [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); Queen — той самий KEYB як єдиний LoRa-ключ + окремий **AES-256 CoAP ключ** (`coap_key[8]`, 32 bytes). Усі деривуються з `PROVISIONING_MASTER_KEY` через HKDF з domain-separated info-strings (`"silken-aes-128-lora-key"` / `"silken-aes-128-broadcast-key"` / `"silken-aes-256-device-key"`). Перевіряй на factory bench, що backend і firmware повертають той самий байтовий ключ за тим самим salt. Симптом mismatch: сміття після декрипту (телеметрія на Rails / downlink на Солдаті). Детальніше: [`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning). |
| **6** | **CoAP UDP smoke test через Ingress Anchor** | **[INF.6]** Перевір end-to-end UDP-шлях `Queen → Ingress Anchor → CoAP daemon` (PRIMARY: демон бере UDP прямо на анкорі — INF.17 2026-07-04; FALLBACK: socat-релей → дормантна Kamal `coap`-роль) ПЕРЕД першим прошиванням Queen. Без цього silent UDP failure не помітний з HTTP-only health checks. **Автоматизовано:** `.github/workflows/coap_smoke.yml` (`workflow_dispatch` для ad-hoc запуску; `workflow_call` — заведений post-deploy gate'ом у `deploy.yml`/`deploy-production.yml`, job `coap-smoke`, активується repo Variable `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST`); inputs: `host` / `port` (default `5683`) / `timeout_seconds` (default `10`) / `retries` (default `3`). **Ручна команда (з машини за межами VPC, що імітує Queen; stdlib-only Ruby, без libcoap):** <br>`bin/coap_smoke --host api.silkennet.com` <br>Зонди = freeze-contract FW.56 (точні байти: RST на сміття, `4.04` на невідомий маршрут з 0xFF-MID-піном, `2.04` лише після enqueue батча — НЕ generic liveness; семантика — [`03_02 §4`](03_02_Queen_Gateway_Firmware)). Якщо timeout: перевір (a) GCP firewall `allow-coap` UDP 5683 = `0.0.0.0/0`; (b) на анкорі `systemctl status coap-daemon` (PRIMARY; env-file `/etc/silkennet/coap.env` заповнений?) АБО, у fallback-режимі, `coap-relay` (socat → app-хост) + (c) Kamal `coap`-роль публікує `5683/udp`; (d) rescue-логи демона: `docker logs silkennet-coap`. Швидка перевірка «чи взагалі слухає UDP» через `nc`: `echo -ne '\x40\x02\x00\x01' \| nc -u -w2 api.silkennet.com 5683 \| xxd` — повертає бінарний CoAP response якщо daemon приймає UDP. |
| **7** | **Schema bootstrap від squashed init_consolidated** | **[INF.7 — Phase 7]** На свіжій базі деплой `bin/rails db:setup` (= `db:create` + `db:schema:load` + `db:seed`). Ми **НЕ** використовуємо `db:migrate` в продакшні до першого деплою — всі pre-launch міграції згорнуті в єдиний `db/migrate/*_init_consolidated.rb` (**timestamp свідомо НЕ називається — бери з `ls db/migrate/`**: він міняється при кожному re-squash, і саме цей рядок уже двічі протухав на ньому), а схема живе в `db/structure.sql` (включно з усіма 3 RANGE-партиційними таблицями + початковими партиціями `_default` + поточним вікном). `schema_migrations` містить анкер **плюс кожну інкрементальну, додану після нього** — рівна кількість тут свідомо не називається, бо вона росте між сквошами; джерело істини — INSERT-блок у кінці `db/structure.sql`. Якщо хтось додає incremental міграцію після цього — `StrongMigrations.start_after` (стоїть на живому анкері — звіряй із `config/initializers/strong_migrations.rb`, ніколи з цього рядка) змусить її пройти всі checks. ⊕ **З 2026-08-23 воно ВИВОДИТЬСЯ з імені файлу анкера** [OPS.24], тож re-squash більше не має кроку «bump start_after» — а разом із ним зник і єдиний мовчазний спосіб зіпсувати процедуру (значення нижче за живий анкер знімало перевірки з уже застосованих міграцій, і ніщо не червоніло). **НЕ** робіть squash повторно після першого деплою (втратите history) без zero-downtime плану. |
| **8** | **PartitionMaintenanceWorker cron у Sidekiq** | `30 0 * * *` UTC, `PARTITIONED_TABLES = %w[telemetry_logs gateway_telemetry_logs blockchain_transactions]`. На день-1 нового місяця партиція повинна вже існувати — інакше `INSERT` падає з `no partition of relation`. Перевір через `psql -c "\d+ telemetry_logs"` що партиція на наступний місяць є. Якщо worker silent-fails — перевір Sentry alert (Phase 7 додав `Sentry.capture_exception` у rescue блок). |
| **9** | **Kamal IP-плейсхолдери → реальний Ingress-IP** | **[S1.5]** Після `terraform apply`: `terraform output -raw ingress_ip` → підставити замість `192.168.0.1` (`config/deploy.yml` servers web/job/coap) і `<INGRESS_ANCHOR_IP>` (`config/deploy.canopy.yml`); також `image:` → повний AR-шлях з `terraform output artifact_registry_url` [INF.15]. Без цього `kamal deploy` б'є в приватний RFC-1918 нікуди. |
| **10** | **`app-host-ip` metadata після провіжну app-хоста** | **[S1.5]** Після того, як app-хост існує: `gcloud compute instances add-metadata silken-net-ingress --metadata app-host-ip=<APP_HOST_IP> --zone <zone>` + `reset`. Живить HAProxy 80/443 → app-хост і socat-**fallback**; PRIMARY CoAP-демон (INF.17) від metadata НЕ залежить. Поки unset — обидва юніти чесно логують skip (sentinel-guard), HAProxy не стартує. ⚠️ [OPS.37] App-хост є в `terraform/` з 2026-08-30 (`google_compute_instance.app`), тож крок гейтований уже не його відсутністю, а самим `apply`; IP беруть командою, не очима: `terraform output -raw app_host_ip`. |

### Менеджер Секретів (Рекомендація)

З десятками API-ключів (12 блокчейнів, GCP, Starlink, DB, Redis, GitHub) критично мати єдине захищене сховище:

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

# Крок 3: Провізіонувати GCP інфраструктуру (Cloud SQL + Ingress Anchor + app-хост)
terraform init
terraform plan
terraform apply
# → outputs: ingress_ip, database_url
# GCP тепер містить: Cloud SQL PostgreSQL (приватна IP) + Ingress Anchor (e2-small,
#   статична IP, CoAP-демон PRIMARY, boot-disk CMEK через `silken-disk-ew1` keyring)
#   + app-хост silken-net-app (e2-standard-2, БЕЗ зовнішньої IP — анкер фронтить 80/443
#     і 5683; Docker передвстановлений, бо deploy-SA не має sudo; власний CMEK app-boot)
#   + Cloud KMS keyring (`kms.tf` — ДВА disk-ключі, compute service-agent IAM автоматично)
# ⚠️ Перший apply може РАЗ впасти "kmsPermissionDenied" (compute P4SA / KMS-IAM
#   propagation ще не поширилась) → просто re-apply (той самий клас, що першу
#   активацію billing-API; на brownfield-проєкті зазвичай проходить з першого разу)

# Крок 4: Створити DNS A-запис
# api.silkennet.com → $(terraform output -raw ingress_ip)
# Дочекатися: dig api.silkennet.com → правильний IP

# Крок 5: Заповнити .kamal/secrets-common — повний список секретів
# (дзеркало config/deploy.yml env.secret; значення з GitHub Secrets або менеджера)
#
# Application core:
#   RAILS_MASTER_KEY, POSTGRES_HOST, POSTGRES_USER, POSTGRES_PASSWORD,
#   REDIS_URL=rediss://<upstash>:6379, TURBO_SIGNED_STREAM_KEY
#   ⛔ CLOUD_SQL_INSTANCE_CONNECTION_NAME / GCP_SA_KEY_BASE64 більше НЕ заводити [OPS.37]:
#   Auth Proxy знято з рантайм-шляху разом із платформою, що його вимагала. Ці два рядки
#   пережили зріз коду на пів дня — 👤-процедура наказувала СТВОРИТИ довгоживучий SA-ключ,
#   чиє зникнення той самий зріз оголосив закриттям ARCH.114.
#   (KREDIS_REDIS_URL — НЕ задавати: Kredis читає REDIS_URL як є, config/redis/shared.yml) [B1]
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
# ⚠️ SECURITY NOTE: ENV-змінні лежать у контейнері plaintext і читаються будь-ким
# із root на хості. Ротуй keys кожні 90 днів; ключі деплою — тільки з MINTER_ROLE/
# SLASHER_ROLE (ніколи з DEFAULT_ADMIN_ROLE). Інвентар — 06_04 §1.

# Крок 6: Деплой застосунку
kamal deploy -d canopy   # спершу canopy (ізольований DB-set), потім production

# Крок 7: Верифікація
# Коли в логах: "Listening on coap://0.0.0.0:5683" — ліс може говорити.
# Ingress Anchor: CoAP приймає демон ПРЯМО на анкорі (PRIMARY — INF.17);
# HAProxy проксює HTTP/HTTPS зі статичного GCP IP на app-хост (socat = CoAP-fallback).
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
│               └────┬─────┘       │  verify-secrets → kamal -d     │         │
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
| **Платформа** | Kamal/GCP, web-only (`kamal deploy -d canopy`) | Kamal/GCP (усі ролі) |
| **GCP ресурси** | Cloud SQL (спільна або окрема БД) + Ingress Anchor (`e2-small`) | Cloud SQL (HA) + Ingress Anchor (`e2-small`, CoAP-демон PRIMARY — INF.17) |
| **Redis** | Upstash Serverless Redis (TLS, `rediss://`) | Upstash Serverless Redis (TLS, `rediss://`) |
| **SSL/HTTPS** | ✅ `force_ssl` + HSTS (1рік, subdomains, preload). `DISABLE_SSL=true` для override | ✅ `force_ssl` + HSTS (1рік, subdomains, preload) |
| **DB** | `silken_net_canopy*` — ізольований набір на тому ж Cloud SQL інстансі (`POSTGRES_DATABASE` override; INF.16) | `silken_net_production` (HA) |
| **Puma workers** | `WEB_CONCURRENCY: 2` (спека app-хоста — `config/deploy.yml`) | `WEB_CONCURRENCY: 2` (те саме; рухається разом із тіром хоста) |

---

## ☁️ Розподіл Ресурсів між провайдерами

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform (GCP)              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Ingress Anchor (e2-small, silken-net-ingress)        │   │
│  │    — статична IP, CoAP-демон (PRIMARY) + HAProxy/socat│   │
│  │    — проксює HTTP/HTTPS на app-хост                   │   │
│  │  App host (Kamal: ролі web + job + coap)              │   │
│  │    e2-standard-2, приватний IP, CMEK boot-disk        │   │
│  │  Cloud SQL PostgreSQL 17 (3 бази, HA, ПРИВАТНА IP —   │   │
│  │    ipv4_enabled = false з 2026-08-29)                 │   │
│  │  Artifact Registry (Docker images)                    │   │
│  └──────────────────────────────────────────────────────┘   │
│  ❌ Memorystore Redis — ВИДАЛЕНО (замінено на Upstash)      │
└─────────────────────────────────────────────────────────────┘

┌──────────────────────────┐  ┌──────────────────────────────┐
│  Upstash (Redis 7.x TLS) │  │  Grafana Cloud (SaaS)        │
│  публічний rediss://     │  │  remote_write · панелі·алерти│
└──────────────────────────┘  └──────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  GHCR — ПУБЛІЧНЕ дзеркало образу                            │
│  анкер тягне coap-демона звідси (він поза WIF-ланцюгом)      │
└─────────────────────────────────────────────────────────────┘
```

> 🔴 **[OPS.37, 2026-08-29] Провайдер компʼюту ОДИН, і це названо, а не замовчано.** Доти тут
> стояли дві колонки — GCP і децентралізована мережа — і вони читались як дві незалежні ноги.
> Це був **подвійний рахунок одного контролера**: под не бутився без GCP (стан у Cloud SQL,
> бекап у GCS, CoAP-PRIMARY на анкері, образ у GHCR), тож другий деплой із тим самим контролером
> не додавав свідка (⛔ [`00_05 §7`](00_05_AI_Native_Operating_Model), Аттар/Навої). Чесний присуд
> формулюється не «який вендор безпечніший», а **«яку концентрацію ми ПРИЙНЯЛИ — і чи ми її
> назвали»**; носій цього питання — [`00_07`](00_07_Action_Plan_Tracker) `ARCH.114`.

### 🔌 Хто може вимкнути НАС — інфра-половина реєстру стоячих повноважень [ARCH.114]

**Питання цієї таблиці — не «які секрети ми тримаємо»** (це інвентар [`06_04 §1`](06_04_Secrets_Checklist), і множина інша), **а «який зовнішній контролер здатен ОДНООСІБНО зупинити платформу, і чи є подія, після якої це право має бути розподілене».** Форма й підстава — дзеркало on-chain половини ([`05_03` — Стоячі повноваження](05_03_Tokenomics_SCC_and_SFC) [ARCH.112]): там ролі, тут вендори, питання те саме. Провенанс форми — [`00_05 §7`](00_05_AI_Native_Operating_Model): Толкін («захоплення АДМІНІСТРАТИВНЕ, не видовищне») + Пінчон («картель складається сам, діяча немає» — тобто реєстр виправданий ІНВЕНТАРЕМ, а не гіпотезою про зловмисника) + амана («право без названого строку перестає бути довіреним»).

⚠️ **Читай таблицю разом із цим рядком: вісім із девʼяти важелів сьогодні ПРОЄКТНІ, а не діючі** — акаунтів не створено, деплою не було ([`00_03 §1`](00_03_TRL_Matrix_HIL_and_Beyond); Фаза −1 у `DEPLOY-1`). Це не робить реєстр передчасним — навпаки: **момент найдешевший рівно тому, що жоден важіль ще нікому не відданий.** 🔏 Підпис прийняття цієї концентрації ставиться у **Фазі −1** рунбука нижче, разом із трьома рядками, які знає лише людина (момент ратифіковано ⚖️ founder 2026-08-30 — `ARCH.114`).

| Важіль | Тримач | Що дає ОДНООСІБНО | Розподіляється на події? |
|---|---|---|---|
| **GCP-проєкт + білінг** | Google · платник — **особиста картка засновника** (`terraform/billing.tf` — «the solo founder IS the billing admin») | 🔴 **вимкнути все.** У GCP живуть web · job · Alloy · **CoAP-демон PRIMARY** на Ingress Anchor · Cloud SQL (усі бази, вкл. `cache`/`cable`/canopy) · Artifact Registry · статична IP. Поза ним — рівно три сервіси (Upstash · Grafana Cloud · GHCR) | ⛔ **ні, і це ПРИЙНЯТА концентрація, не пропуск** — другої ноги немає й вона свідомо не будується ([`06_08 §1`](06_08_Resilience_and_Failover_Policy); подвійний рахунок одного контролера — [`00_05 §7`](00_05_AI_Native_Operating_Model)). Бюджет-алерти 50/90/100% ловлять ВИТРАТИ, не втрату доступу |
| **GitHub-акаунт** (репо · Actions · Secrets · GHCR · релізи) | GitHub · особистий акаунт `Alexey-Lukin` | 🔴 **більше, ніж здається, і саме тому він тут ДЕВʼЯТИМ:** через нього йде (1) ЄДИНА ідентичність CI→GCP (WIF довіряє GitHub-OIDC; іншого credential не існує), (2) СХОВИЩЕ всіх deploy-секретів + GH Environment `production`, (3) образ для анкера (GHCR), (4) реліз-ланцюг, (5) merge-gate (branch protection живе на GitHub-стороні, не в дереві), (6) підпис образів (Sigstore-ідентичність = сам workflow) | ⚖️ **подія НАЗВАНА, виконавця немає** — `terraform/wif.tf` дослівно: довіра ключується на **ІМʼЯ** власника (`assertion.repository_owner`), не на незмінний `repository_owner_id`, і стеля оголошена там же: «harden to numeric `*_id` **if the repo ever changes hands**». Тобто зміна власника/організації = обовʼязковий перехід на числовий id |
| **Реєстратор домену** (`silkennet.com` · `.app`) | **GoDaddy — ОБИДВА домени куплено founder-ом 2026-08-30** (по 1 року; незалежний реєстратор — сумісний із TLS-fallback, чужі NS дозволені; ⚠️ цей рядок казав «.app ще НЕ куплено» рівно годину — друга купівля відбулась тим самим вечором, і таблиця важелів свіпається після КОЖНОГО заведення) | 🔴 **єдиний важіль, чия відмова вимагає ФІЗИЧНОЇ експедиції до заліза:** `COAP_SERVER_HOST "api.silkennet.com"` — `#define` у прошивці Королеви (`firmware/queen/main.c`), тож втрата зони = пере-прошити ВЕСЬ флот; зона тепер наша, а не гіпотетична. Гейт `spec/deploy/coap_host_consistency_spec.rb` стереже firmware↔host | 👤 подія настала: реєстратора й власника обрано (особистий акаунт founder-а, GoDaddy 2FA — його рука); лишились NS `.app` → CF (зона провіжниться) + дата продовження в календарі власника |
| **Cloudflare** (TLS + DNS) | Cloudflare · **акаунт живий 2026-08-30** (⚠️ на пошті SHARED-компанії `@active-bridge.com` — рядок «на кого оформлено» підпису ARCH.114 має що записати); обидві зони заведені (Free), SSL = **Full (strict)** на обох, NS `silkennet.com` уже перемкнуто на CF | 🔴 знімає HTTPS усього web-ярусу **і** DNS для CoAP-хоста. ⚠️ Формулювання «TLS існує рівно за рахунок CF» стояло тут до 2026-08-30 і було правдиве лише про КЛІЄНТСЬКЕ плече: воно тихо припускало, що CF→origin іде по HTTP, тобто режим `Flexible`, який цей самий док забороняє. Вимір показав `Full (strict)` на обох зонах — а він вимагає сертифіката НА ORIGIN, якого стек не має (§Сертифікат НА ORIGIN). ✅ **Fallback РАТИФІКОВАНО ⚖️ 2026-08-30 (§TLS-fallback вище):** прямий A-запис + kamal-proxy `ssl: true` (Let's Encrypt); чесна ціна — NS-пропагація годинами, на час інциденту без CDN/WAF. Передумову ВИКОНАНО: домени куплені в незалежного реєстратора, НЕ CF Registrar | 👤 залишок pre-flight → [`00_07`](00_07_Action_Plan_Tracker) `INF.4` (NS `.app` + A-записи deploy-day). Пом'якшення додаткове: `[FW.58]` re-resolve рятує від зміни A-запису, не від утрати зони |
| **Cloud SQL** (стан) | Google (у межах того ж проєкту) | 🔴 БД недосяжна → контейнер `exit 1`, `/ready` 503. ⛔ **Автоматичного експорту даних ЗА МЕЖІ GCP немає:** бекап = PITR + 30 снапшотів у тому ж Cloud SQL. Поза ним відновлювані лише (а) баланси токенів — з ланцюга (БД є проєкцією), (б) `AuditLog` — IPFS/Filecoin | ⛔ ні — це той самий контролер, що рядок 1. `deletion_protection = true`, `REGIONAL`-HA. ⚠️ DR-drill **не проводився жодного разу** ([`06_06`](06_06_Disaster_Recovery_and_Backup), `DR.1`) |
| **GCS tfstate** | Google · бакет створено поза terraform (`bootstrap.sh`) | контроль над станом інфри; ручне знищення версії CMEK-ключа робить state-версії **назавжди** нечитабельними (recovery = `terraform import` з нуля) | ⛔ ні. ⊕ **Єдиний важіль із МАШИННИМ виконавцем строку** — ротація CMEK `--rotation-period=90d`, налаштована в gcloud. Копії стану поза бакетом немає (лише 10 noncurrent-версій / 30 днів, і короткий ретеншн — свідомий: кожна версія несе секрети) |
| **GHCR** (образ для анкера) | GitHub (див. рядок 2) | зупиняє оновлення/підйом **CoAP-інтейку**: анкер тягне свій образ звідси systemd-юнітом, поза Kamal/WIF-ланцюгом і без реєстрового credential'а. ⚠️ Kamal тягне з GCP Artifact Registry — це ІНШИЙ реєстр, тож web/job тут не залежать | ⛔ ні — успадковує подію рядка 2. Пом'якшення: `PIN_ME` fail-closed + заборона `:latest` (`INF.21`) — уже завантажений образ переживе відмову, rebuild/reboot ні |
| **Alchemy** (RPC Polygon/Ethereum) | Alchemy · акаунт ще не заведено | зупиняє мінт · слешинг · confirmation · L1-якір · governance-sync · treasury-моніторинг. 🔴 **Каскад формально Є, фактично ПОРОЖНІЙ:** механізм (`Web3::ResilientClient` + `RpcConnectionPool`) живий, але при одному URL він вироджується у звичайного клієнта, а з усіх `client_for`-сайтів каскад передає **один** (`MintingRollbackService`); `INFURA_POLYGON_RPC_URL` живе лише в `.env.example` і в deploy-набір не заведений | ⛔ ні, але 🤖 **вимірна діра**: другий RPC-провайдер для Polygon/Ethereum — конфіг, не архітектура (Celo й Solana свої каскади вже мають) |
| **Upstash** (Redis ×2 інстанси: production + canopy) | Upstash · акаунт ще не заведено | `/ready` → **503 для всієї ноди** (Redis у hard-dependencies), бо на ньому Sidekiq (9 черг) · Kredis-локи мінту/бернy/nonce · Rack::Attack. ⊕ Частковий graceful-degrade є лише для nonce (fallback у Solid Cache + власна метрика й алерт) | ⛔ ні. ⚖️ **Тригер названий і вимірний:** повторюваний `m2m_nonce_fallback` день-у-день → перехід на multi-zone Upstash Global DB (рішення за прод-даними) |

🔑 **Що цей інвентар змінив у власному пункті — записано, бо клас повториться.** `ARCH.114` спирався на «виміряний інстанс, що доводить потребу»: `GCP_SA_KEY_BASE64` — довгоживучий SA-ключ із приписаною ротацією 90 днів **без виконавця**. **Цей інстанс МЕРТВИЙ**: споживача знято разом із платформою (`OPS.37`), `google_service_account_key` у дереві **нуль**, а `INF.22` і скіл `deploy` уже кажуть «WIF безвинятковий». **Вердикт (реєстр потрібен) вистояв — упала його ПІДСТАВА**, і заміняє її не риторика, а сильніший живий інстанс того самого класу Кафки: **довіра WIF ключується на ІМЕНІ GitHub-власника, стеля оголошена в самому коді, подія названа («if the repo ever changes hands») — і виконавця в неї немає так само.** Різниця в тому, що цей — не гіпотетичний і не знятий.

⛔ **Чого ця таблиця НЕ може знати, і це не пропуск інвентаря, а межа дерева:** на кого оформлені акаунти, хто платить, чи є 2FA й recovery-контакт, чи має хтось, крім власника, доступ бодай до одного важеля (`iap_admin_members` за замовчуванням порожній), і де фізично лежать `RAILS_MASTER_KEY`/`PROVISIONING_MASTER_KEY` (процедура зберігання у vault — 👤, невиконана, `DR.1`). **Ці рядки заповнює людина, і саме вони перетворюють інвентар на присуд.**

| Сервіс/Ресурс | GCP | Upstash | Grafana Cloud | Примітка |
|--------------|-----|---------|---------------|---------|
| **Rails web (Puma + Thruster)** | ✅ | — | — | Kamal `web`-роль на app-хості |
| **Sidekiq (job role)** | ✅ | — | — | Kamal `job`-роль, той самий хост |
| **Grafana Alloy (metrics agent)** | ✅ | — | — | Kamal **accessory** (`files:`-монтування `deploy/alloy/config.alloy`), скрейпить три process-таргети по стабільних DNS-аліасах ролей (`silken-web`/`-job`/`-coap` — ⚖️ [OPS.37 2026-08-30], механіка в ноті web-ролі `config/deploy.yml`); пускач = крок «Ensure Alloy accessory is running» в обох deploy-воркфлоу (boot ідемпотентний; зміна `config.alloy` → свідомий `kamal accessory reboot alloy`) |
| **CoAP UDP daemon (:5683)** | ✅ **PRIMARY** | — | — | **PRIMARY = демон на Ingress Anchor** (docker + systemd `coap-daemon`, VPC → Cloud SQL приватним IP — founder 2026-07-04); fallback = socat-релей → дормантна Kamal `coap`-роль. Свідомо НЕ puma-thread — UDP у web-процесі сплітає lifecycle (INF.17) |
| **Cloud SQL PostgreSQL 17** | ✅ | — | — | Приватна IP, БЕЗ Auth Proxy на рантайм-шляху |
| **ActionCable (Solid Cable)** | ✅ | — | — | Спільна Cloud SQL БД `cable`, **POLLING** (`polling_interval`), НЕ LISTEN/NOTIFY — механіка й наслідки для ємності в `config/cable.yml` (без sticky sessions) |
| **Redis** | — | ✅ | — | Upstash Serverless, TLS (`rediss://`) |
| **Prometheus + Grafana + Alerting** | — | — | ✅ | SaaS, Alloy → remote_write |
| **Ingress Anchor** | ✅ | — | — | `e2-small`, статична IP: CoAP-демон (PRIMARY) + HAProxy 80/443 → app-хост + socat (fallback) |
| **Artifact Registry (Docker)** | ✅ | — | — | Kamal пушить у GCP AR |
| **GHCR (Docker mirror)** | ✅ | — | — | `.github/workflows/mirror-ghcr.yml` — ПУБЛІЧНЕ дзеркало, бо анкер тягне свій образ systemd-юнітом поза Kamal/WIF-ланцюгом і не має реєстрового credential'а |

## 🔴 Redis Isolation Strategy

### Проблема

IoT-телеметрія (мільйони дерев, пакети щогодини від кожної Queen) може витіснити критичні Web3 nonce locks → EVM nonce collision → double-spend на Polygon. При масштабі мільярдів-трильйонів дерев обсяг Sidekiq-черг та rate-limit counters зростає експоненціально, і спільне Redis-сховище стає single point of contention. **Ця проблема чинна — змінився лише механізм, яким ми на неї відповідаємо.**

### Рішення: один keyspace + префікси, а ізоляція — ОКРЕМИМ ІНСТАНСОМ

🔴 **Доти тут стояло «3 Redis DB», і це було нездійсненне за побудовою.** Upstash — наш керований Redis — виставляє **рівно одну логічну базу**: `SELECT 1` віддає `ERR Only 0th database is supported!` (виміряно на власному інстансі `silkennet-canopy` 2026-08-30, командою, не документацією). Тобто нумерована ізоляція не «протухла» — вона не існувала в проді жодного дня, і деривації `/1`/`/2` не деградували, а **падали**: Kredis голосно (`Redis::CommandError` → `/ready` 503), а Rack::Attack **тихо** (`RedisCacheStore` ковтає помилку failsafe'ом і віддає `nil`, що невідрізненне від «нуль страйків»).

Чинна модель — **два яруси**, і їх не можна плутати:

1. **Розділення ІМЕН — за замовчуванням, безкоштовно.** Усі споживачі ділять один keyspace, розведені префіксом ключа: Kredis — `silken:*` (`Kredis.global_namespace`, `config/initializers/kredis.rb`), Rack::Attack — `rack-attack:*` (опція `namespace:`), Sidekiq — власні `queue:`/`retry:`/`dead`/`stat:`/`processes` **без префікса**, бо Sidekiq 7+ кидає `ArgumentError` на `namespace:` і його імена ні з чим не збігаються.
2. **Розділення ПАМʼЯТІ — deploy-часовий важіль, за потреби.** Префікс розводить імена, **ніколи не memory pressure**: під eviction-політикою флуд однаково вибиває чужі ключі незалежно від префікса. Тому справжню ізоляцію дає **окремий інстанс**, і код для цього вже готовий — `KREDIS_REDIS_URL` / `RACK_ATTACK_REDIS_URL` перекривають адресу без жодної правки. Обидві наші бази наразі створені з **вимкненим eviction**, тож витіснення не відбувається взагалі.

⚠️ **Наслідок для `Kredis.clear_all`, і він несучий:** гем гілкується на наявність namespace — без нього він робить **`FLUSHDB`**. Саме тому namespace обовʼязковий, а не косметичний: без нього зачистка між прикладами сюїти й будь-який інший `clear_all` спорожняють СПІЛЬНУ базу — з чергами Sidekiq включно. ⚠️ Той самий виклик стояв і в `config/puma.rb` на кожному `before_worker_boot`, але там він був **латентним**, не живим ([`06_05`](06_05_Puma_Configuration) — гем чистить лише ВЖЕ закешовані зʼєднання, а майстер Kredis на буті не торкається); знято до того, як озброїться.

```
┌─────────────────────────────────────────────────────────────────┐
│         Upstash Serverless Redis (TLS) — ОДНА логічна база      │
│  ┌──────────────────────┬──────────────────┬──────────────────┐ │
│  │  (без префікса)      │  silken:*        │  rack-attack:*   │ │
│  │  Sidekiq             │  Kredis          │  Rack::Attack    │ │
│  │  Job queues          │  Distributed     │  Rate-limit      │ │
│  │  Scheduler           │  locks (Web3     │  counters        │ │
│  │  9 priority queues   │  nonce mgmt,     │  per-IP/DID      │ │
│  │                      │  M2M nonce)      │  (10 min TTL)    │ │
│  └──────────────────────┴──────────────────┴──────────────────┘ │
│   ↳ окремий інстанс на споживача — через ENV-override, без коду │
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

| Підсистема | Сховище | Префікс ключів | ENV змінна | Конфігурація | TTL / Eviction |
|-----------|---------|----------------|------------|--------------|----------------|
| **Sidekiq** (9 черг, scheduler) | Upstash Redis | — (власні імена; namespace неможливий у Sidekiq 7+) | `REDIS_URL` | `config/initializers/sidekiq.rb` | Persistent (no eviction) |
| **Kredis** (distributed locks) | Upstash Redis | `silken:*` | `REDIS_URL`; override → окремий інстанс `KREDIS_REDIS_URL` [B1] | `config/redis/shared.yml` + `config/initializers/kredis.rb` | 1–300 sec (lock TTL) |
| **Rack::Attack** (rate limiting) | Upstash Redis | `rack-attack:*` | `REDIS_URL`; override → окремий інстанс `RACK_ATTACK_REDIS_URL` | `config/initializers/rack_attack.rb` | 10 min |
| **Rails.cache** (Solid Cache) | PostgreSQL | — | — | `config/cache.yml` + `config/environments/production.rb` | ⚠️ **Розмірна стеля, НЕ вікова** — живе лише `max_size` (256 MB, LRU); `max_age` у `cache.yml` закоментований, тож віку запису ніхто не обмежує |
| **ActionCable** (Solid Cable) | PostgreSQL | — | — | `config/cable.yml` | 1 day message retention |
| **Hardware Key Cache** | In-Process RAM | — | — | `config/initializers/hardware_key_cache.rb` | Process lifetime |

### ENV змінні та автоматична деривація

```bash
# Обов'язкова — одна на всіх споживачів:
REDIS_URL=rediss://default:password@endpoint.upstash.io:6379/0

# Опціональні. НЕ «auto-derive» (його більше немає) — це перемикачі на ОКРЕМИЙ інстанс,
# тобто єдиний спосіб дістати ізоляцію від memory pressure. Незадані — беруть REDIS_URL.
# ⚠️ Не оголошувати їх порожніми на деплой-поверхні: present-empty truthy для `ENV.fetch`
# і перебиває фолбек значенням «» [B1].
# KREDIS_REDIS_URL      — Kredis locks       (config/redis/shared.yml)
# RACK_ATTACK_REDIS_URL — rate-limit counters (config/initializers/rack_attack.rb)
```

⚠️ Суфікс `/0` у `REDIS_URL` — єдиний легальний індекс; будь-який інший Upstash відкидає помилкою, і `RedisCacheStore` перетворює її на тихий `nil` (гейт: `spec/initializers/rack_attack_store_spec.rb`).

### Чому саме ця архітектура

1. **Sidekiq**: Найбільший обсяг даних — мільйони телеметричних job'ів щогодини, і саме він є джерелом тиску, від якого решту треба захищати. Захист сьогодні = eviction OFF; за зростання — власний інстанс.
2. **Kredis (`silken:*`)**: Критичні distributed locks для Web3 nonce management (`BlockchainMintingService`, `BlockchainBurningService`, `CeloRewardService`), M2M nonce anti-replay. Lock TTL 30 sec = **concurrent** guard; **[ARCH.45]** durable money-path idempotency тепер тримає DB intent-marker + `BlockchainTransaction.in_flight` guard (не лише ephemeral lock) для slash/Solana payout — витіснення локу більше не єдина лінія проти double-spend ([`04_02 §4/§10`](04_02_Business_Logic_and_Services)).
3. **Rack::Attack (`rack-attack:*`)**: Rate-limit counters з TTL 10 min. Менший обсяг, але потребує ізоляції від Sidekiq, щоб counters не губились при spike-ах. 🔴 І це єдиний споживач, чия відмова **не має голосу за замовчуванням**: `RedisCacheStore` ковтає будь-який `Redis::BaseError` і віддає `nil`, тобто щит не деградує, а зникає — throttle не рахує, fail2ban не банить, лог порожній. Тому store несе `error_handler`, а той — лічильник `silkennet_rate_limit_store_errors_total` з алертом `sn-alert-rate-limit-store-errors` ([`06_03 §2.8`](06_03_Prometheus_Observability)).
4. **Solid Cache (PostgreSQL)**: Rails.cache для Web3 circuit breaker state, dashboard stats, alert silence windows. PostgreSQL гарантує durability — circuit breaker state не зникає при Redis restart.
5. **Solid Cable (PostgreSQL)**: ActionCable через PostgreSQL — zero Redis dependency, multi-replica safe без sticky sessions. ⚠️ Механізм — **опитування**, не `LISTEN/NOTIFY`: кожен web-процес тримає listener-тред, що `SELECT`-ить нові рядки кожні `polling_interval`. Три наслідки для ємності (дім — `config/cable.yml`): латентність має підлогу ~`polling_interval`; вартість опитування росте з кількістю процесів, не подій; ціна броадкасту платиться НА ЗАПИСІ, навіть за нуля підписників. ⚠️ Метод адаптера НАЗВАНИЙ `listen`, тож греп по «listen» дає хибне підтвердження pub/sub — усередині це `loop { … sleep polling_interval }`.
6. **In-Process RAM**: AES hardware keys — Zero Network Exposure. Ключі ніколи не серіалізуються і не передаються по мережі.

### Масштабування (мільйони → мільярди → трильйони дерев)

| Масштаб | Дерев | Queens | Sidekiq jobs/год | Redis-стратегія |
|---------|-------|--------|------------------|-----------------|
| **Pilot** (TRL 6-7) | ~1,000 | ~50 | ~50K | Один Upstash-інстанс, спільний keyspace, eviction OFF |
| **Regional** (TRL 8) | ~1M | ~50K | ~50M | Окремий інстанс під Sidekiq; Kredis і Rack::Attack переносяться ENV-override'ом |
| **Planetary** (TRL 9) | ~1B+ | ~50M | ~50B | Окремий інстанс/кластер **на КОЖНОГО споживача** (Sidekiq ⊥ Kredis ⊥ Rack::Attack). Або Upstash multi-region з read replicas. |

При planetary-масштабі кожен споживач потребує власного інстанса з окремим endpoint. ENV-архітектура вже це підтримує — і саме тому обидва override'и лишаються в дереві, хоча сьогодні незадані: вони і є шлях від першого рядка таблиці до третього, без жодної правки коду.

---

## 📦 Kamal — Детальний Аналіз

### Файлова структура

| Файл | Опис |
|------|------|
| `config/deploy.yml` | Production-конфіг (основний) |
| `config/deploy.canopy.yml` | Canopy-перевизначення (`-d canopy`). **Web-only СТРУКТУРНО** — `servers:` = array-форма, яку deep_merge замінює цілком (омітнута `job:`-секція НЕ прибирає роль: destination-merge = keys-union, роль успадкувалась би з base разом із money-`env.secret` → present-empty guard-crash; INF.22). ⚠️ [OPS.37] Sidekiq для Canopy тепер не їде НІДЕ — доти його ніс окремий job-сервіс знятої платформи. Відкрите рішення: дати canopy власну `job:`-роль ⊥ свідомо тримати canopy без воркерів; доти Sidekiq дебютує на production. |
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
    # KREDIS_REDIS_URL omitted — Kredis reads REDIS_URL as-is (config/redis/shared.yml). [B1]
    # --- Observability ---
    - SENTRY_DSN
    # --- Hardware provisioning gate (config/initializers/master_key_strength_check.rb) ---
    - PROVISIONING_MASTER_KEY
    # --- Money/signing-ключі НЕ ТУТ: JOB-ONLY (servers.job.env.secret вище) —
    #     п'ятірка CELO/MINTER/SLASHER + ETHEREUM_ANCHOR + SOLANA_WALLET_KEYPAIR,
    #     (legacy ORACLE_PRIVATE_KEY RETIRED — INF.22);
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
    APP_HOST: silkennet.app                   # Action Mailer host = web-host (INF.25 Опція A, 2026-08-30)
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
> | `DISABLE_SSL` | `env.clear` | `false` | Вимикає `force_ssl`/`assume_ssl`. Тільки якщо TLS термінується upstream (Cloudflare). |
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
├── compute.tf    # ДВА інстанси: Ingress Anchor (e2-small, silken-net-ingress, Static IP + CoAP-демон PRIMARY)
│                 #              + app-хост (e2-standard-2, silken-net-app — Kamal web+job+coap, приватний IP) [OPS.37]
├── database.tf   # Cloud SQL PostgreSQL 17, 3 databases (primary/cache/cable — Solid Queue pruned INF.18) + canopy-тріо, Private Service Access
├── iam.tf        # Service Account silken-net-deploy + IAM roles (deploy-SA + IAP-operator)
├── variables.tf  # Всі input variables з валідацією
└── outputs.tf    # ingress_ip, DB URL тощо
```

> **Примітка:** `redis.tf` видалено — Redis тепер обслуговується Upstash (serverless, зовнішній сервіс, не GCP). `compute.tf` містить ДВА інстанси — Ingress Anchor (`e2-small`) і app-хост (`e2-standard-2`, `google_compute_instance.app`, повернений [OPS.37] 2026-08-30; canopy-VM свідомо НЕМАЄ — це відкритий ⚖️, а не пропуск). Анкер: CoAP-демон (PRIMARY інтейк, docker + systemd, секрети в `/etc/silkennet/coap.env` 0600 — НЕ в metadata) + HAProxy 80/443 → app-хост + socat-fallback. Grafana Alloy `config.alloy` живе в `deploy/alloy/config.alloy` і монтується у контейнер accessory нативно (`files:` у `config/deploy.yml`) — base64-канал зник разом із платформою, що не вміла монтувати файли.

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
Роль ПОЗА проєктною ієрархією (разово, руками — див. блок нижче):
  - billing.costsManager      (на BILLING-акаунті, не на проєкті)
IAP-operator ролі (iam.tf, for_each `iap_admin_members` — люди-адміни, не SA):
  - compute.osAdminLogin       (sudo на анкорі через IAP-тунель, INF.20)
  - iap.tunnelResourceAccessor (відкриття IAP-тунелю)
```

> 🔴 **Грант CI-SA на BILLING-акаунті — ОБОВʼЯЗКОВИЙ перед активацією бюджету, і разовий
> founder-apply тут НЕ рятує.** Billing-ролі живуть в окремій ієрархії (проєктні ролі їх не
> покривають), а `terraform plan` **рефрешить** бюджет щоразу (`billing.budgets.get`) — тож
> наступний drift-`plan` дістає 403 і щотижнево червонить `Ops · TF Drift`. ⚠️ **Ціна цього
> абзацу ЗНИЗИЛАСЬ 2026-08-29 [INF.22], і саме тому він переписаний, а не знятий:** доти 403
> ішов у deploy-воркфлоу й через `needs: terraform` блокував ВЕСЬ ланцюг; тепер джоби
> `terraform` у деплої немає (apply — founder-local), тож наслідок звузився до сліпого
> drift-детектора. Грант лишається обовʼязковим — детектор, що завжди 403-ить, не детектор.
> Разово:
> ```bash
> gcloud billing accounts add-iam-policy-binding <ACCT_ID> \
>   --member="serviceAccount:silken-net-deploy@<project>.iam.gserviceaccount.com" \
>   --role="roles/billing.costsManager"
> ```
> ⚠️ `billingbudgets.googleapis.com` eventually-consistent — перший activation-apply може впасти
> раз; re-apply проходить. Guard: порожній `billing_account_id` (tf-var) = блок no-op; той САМИЙ
> id мусить стояти у GitHub-секреті `GCP_BILLING_ACCOUNT_ID`, який тепер читає ОДИН споживач —
> `terraform_drift.yml`. ⚠️ **Доти цей рядок казав «обидва deploy-workflow передають
> `TF_VAR_billing_account_id`… інакше наступний CI-apply знесе бюджет» — обидві половини
> застаріли 2026-08-29 [INF.22]:** джобу `terraform` знято з деплою разом із `TF_VAR_*`, тож
> CI-apply не існує, а `plan` знищити нічого не може. Розбіжність id тепер коштує ШУМУ в
> щотижневому drift-звіті (бюджет виглядатиме як зайвий ресурс), не втрати контролю витрат.
> Конфіг — `terraform/billing.tf`. ⚠️ Переїхало сюди 2026-08-29 [OPS.37] — доти точна команда й
> механіка 403 жили ТІЛЬКИ в знятому доці, а рунбук про них не знав.

### Розрахунок `max_connections` (database.tf)

Поточне значення `400`. Формула пулу — SSOT у `config/database.yml` (коментований блок): `pool = RAILS_MAX_THREADS + PUMA_MAX_IO_THREADS + 2 (Cable headroom) = 3 + 16 + 2 = 21` на процес, на кожну з 3 баз набору (primary/cache/cable — Solid Queue pruned, INF.18). IO-доданок — [INF.22]: Puma-8 `max_io_threads` дозволяє io-маркованим запитам (oracle_callbacks/provisioning) бігти ПОНАД `max_threads`, і кожен тримає DB-checkout — пул без цього доданку голодує під сплеском (`ConnectionTimeoutError`). Пул = стеля, не преалокація: з'єднання відкриваються за потребою і реляться, тож фактичне число значно нижче.

| Компонент | З'єднання (стеля checkout) |
|-----------|------------|
| Kamal web | `WEB_CONCURRENCY` (2) × pool (21) × 3 бази = **126 стеля** (факт ≪: io-burst рідкісний, idle реляться) |
| Kamal job (Sidekiq) | `:concurrency` (15) → `DB_POOL=17` (встановлено в job env, INF.13) = **~51** (17 × 3 бази) |
| admin/console (break-glass Auth Proxy з робочої станції) | **~8** |

Навіть за одночасного пікового checkout усіх пулів — нижче `400` (≈**185**); запас під read-репліки/canopy тримається на тому, що web-стеля досяжна лише при повному io-burst усіх воркерів одночасно (не steady-state). Адекватно; ревізит при `WEB_CONCURRENCY` > 4.

> ⚠️ **Друга вісь того самого бюджету — ГОРИЗОНТАЛЬНА, і після [`OPS.37`](00_07_Action_Plan_Tracker) висновок цієї нотатки ПЕРЕВЕРНУВСЯ.** Доти вона рахувала від `WEB_CONCURRENCY=4` і давала 2 × 252 + 51 + 8 = **563 > 400**, тобто «другий web-вузол не влазить». Єдиний таргет тепер пінить `WEB_CONCURRENCY=2` (`config/deploy.yml`), тож реально 2 × 126 + 51 + 8 = **311 < 400** — горизонтальне масштабування web **влазить**, і другий вузол більше не гейтований цим рядком Terraform. 🔴 Числа під цим абзацом не містили слова «Akash» УЗАГАЛІ — вони мовчки успадкували мертву четвірку, і саме тому клас міграційного залишку ([`00_06 §1`](00_06_SSOT_Documentation_Standard)) вимагає **перечитати арифметику навколо**, а не лише замінений множник. Вертикальний тригер лишається: при `WEB_CONCURRENCY > 4` на двох вузлах стеля знову перевищить 400. Важелів рівно два, і обидва вимагають рішення заздалегідь: підняти `db_max_connections` (на `db-custom-2-7680` кожне з'єднання коштує реальну пам'ять — тобто це тягне і зміну tier) **або** завести пулер, якого в репозиторії немає **ніде** (`db_read_replica_count` теж `0`). Наслідок ширший за ємність: цей самий інстанс несе primary + cache + cable + canopy-staging, тож за REGIONAL-HA байти UI-фан-ауту cable реплікуються тим самим WAL, що money-записи — один інстанс вниз = money+cable+cache+staging разом. Ревізит: **або** `WEB_CONCURRENCY > 4`, **або** web-репліка №2 — що настане раніше.

---

## 🐳 Docker — Multi-stage Build

```
Stage 1: base          — ruby:4.0.6-slim + libjemalloc2, libvips (≥ 8.13), postgresql-client
Stage 2: build         — bundle install, bootsnap, assets:precompile
Stage 3: final         — COPY gems + app, USER rails:1000, CMD: thrust ./bin/rails server
```

> **`libvips ≥ 8.13` — несуча межа, не косметика (2026-07-30).** Active Storage при буті кличе `Vips.block_untrusted(true)`, щоб вимкнути «unfuzzed» лоадери libvips (CVE-2026-66066); на старішій бібліотеці метод відсутній і Rails **не стартує взагалі** — тобто відкат base-образу на давніший Debian ламає не картинки, а весь застосунок. Той самий пакет потрібен CI-джобам, які реально ініціалізують Rails (`.github/actions/setup-rails-test` → `test`/`feature-test`); гем `ruby-vips` стоїть `require: false`, тож `bin/rails`-гейти без `:environment` (docs/i18n-смуги) його не вантажать і libvips їм не потрібна. Trixie дає 8.16.1, ubuntu-24.04 — 8.15.1, ubuntu-26.04 — 8.18.0.

---

## 🔐 TLS-термінація — Cloudflare [INF.4]

> **Архітектурне рішення ✅ ОБРАНО (founder 2026-07-03): Cloudflare Proxy для HTTPS + direct UDP
> для CoAP.** Cloudflare НЕ проксює UDP на безкоштовному/Pro тарифах — тож CoAP :5683 іде
> **окремим шляхом через Ingress Anchor** (статичний GCP IP), який і так є в архітектурі.
> ⚠️ **Переїхало сюди 2026-08-29 [`OPS.37`](00_07_Action_Plan_Tracker)** з дока про зняту платформу.
> Перевірено перед переїздом: цей чекліст був **єдиним** його домом у всьому корпусі — ані
> «Full (strict)», ані SSL Labs, ані `cf-ray` не зустрічались більше ніде, тож видалення без
> переїзду стерло б єдину 👤-процедуру дня деплою. Альтернатива, що спиралась на hostname-operator
> зниклої платформи, знята разом із нею; новий fallback ратифіковано ⚖️ founder 2026-08-30 — нижче.

### TLS-fallback при недоступності Cloudflare [INF.4, ⚖️ 2026-08-30]

**Fallback = прямий A-запис на app-хост + kamal-proxy `ssl: true` (Let's Encrypt)** — механізм
УЖЕ в стеку (`config/deploy.yml` тримає закоментований `proxy:`-блок із виписаним
`healthcheck:`-підблоком, [INF.10]), тож нове рішення не потрібне — потрібен названий шлях:

1. **NS-перемикання:** у реєстратора змінити NS із Cloudflare на DNS-провайдера, доступного
   в момент інциденту (реєстраторський дефолт достатній). ⏱ Чесна ціна: NS-пропагація —
   години, це записано, а не приховано.
2. **A-записи напряму:** `silkennet.app → <app-host IP>` · `api.silkennet.com → <Ingress-IP>`
   (CoAP і так ішов повз CF — його цей інцидент не чіпає).
3. **Увімкнути `proxy.ssl`:** розкоментувати блок у `config/deploy.yml` (значення `host:` —
   з ⚖️ INF.25, не вигадувати) → `kamal deploy` → ACME-челендж видає сертифікат на живому DNS.
4. Втрачається на час інциденту: CDN/WAF/DDoS-щит Cloudflare — прийнято як ціна fallback'у.

🔴 **Передумова, без якої кроку 1 не існує: реєстратор доменів ≠ Cloudflare Registrar.**
CF Registrar не дозволяє чужі NS — домен, куплений там, у CF-інцидент перемкнути нікуди.
Тому Фаза −1 купує домени в **незалежного реєстратора**, а Cloudflare підключається як
DNS/proxy поверх. Це рішення про купівлю, ухвалене разом із fallback'ом (⚖️ 2026-08-30).

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
         │ HTTPS → origin                       │ UDP (прямо, без CF)
         ▼                                      ▼
                  ┌─────────────────────────────────┐
                  │  App host (Kamal web-роль)      │
                  └─────────────────────────────────┘
```

### 🔴 Сертифікат НА ORIGIN — ланка, якої в цьому чеклісті не було [INF.4, виміряно 2026-08-30]

Рядок «SSL/TLS режим `Full (strict)`» нижче правильно каже, що **Cloudflare вимагає валідного
сертифіката на origin** — і ніде не казав, ЗВІДКИ той сертифікат береться. Вимір показав, що
взятись йому не було звідки, тобто це не пропуск у прозі, а мертвий шлях:

- CF стоїть у **Full (strict)** на **обох** зонах (прочитано в живому дашборді 2026-08-30, не з
  цього доку);
- HAProxy на Ingress Anchor — `mode tcp` на 80 **і** 443 (`terraform/compute.tf`), тобто чистий
  прохід: він не термінує нічого;
- `proxy:`-блок закоментований в обох маніфестах → kamal-proxy віддає простий HTTP на :80 і
  **нічого придатного на :443**.

**Отже перший же запит крізь Cloudflare відповідає 521/525** — рівно той симптом, який
таблиця траблшутингу нижче вже описує. Клас — «конфіг повний, шлях мертвий»; невидимий доти,
доки нічого не задеплоєно.

⛔ **Let's Encrypt (`ssl: true`) тут НЕ лік, і причина структурна:** під `Full (strict)`
Cloudflare ходить на origin **лише по HTTPS**, тож ACME-челендж HTTP-01 на :80 не доставляється
ніколи. Сірий хмарник на час першої видачі спрацює ОДИН раз, а поновлення тихо впаде через
90 днів. `ssl: true` лишається рівно там, де він і був, — у **TLS-fallback** без CF (вище).

✅ **Шлях, що працює — Cloudflare Origin CA:** безкоштовний сертифікат на 15 років, який
`Full (strict)` приймає за визначенням (CF довіряє власному CA). Видати на
`silkennet.app` + `*.silkennet.app` — **один сертифікат покриває і продакшен, і canopy-піддомен**.
Kamal 2.12 бере обидві половини як **імена kamal-секретів**, не шляхи
(`Kamal::Configuration::Proxy#custom_ssl_certificate?`), тож повний контракт із пʼяти ходів
виписано в самому `config/deploy.yml` над ключем `proxy:` — там дім, тут вказівник. Ходи (2) і
(3) з тих пʼяти **енфорсить** `spec/deploy/env_fetch_declaration_spec.rb`: щойно блок
розкоментують, гейт поіменно вимагає `TLS_ORIGIN_CERT_PEM`/`TLS_ORIGIN_KEY_PEM` у
`.kamal/secrets-common` і в `env:`-блоках обох deploy-воркфлоу.

⚖️ **Canopy теж отримує TLS — присуд founder 2026-08-30** («на canopy https ssl повинен бути»).
Підстава сильніша за зручність: canopy є ПЕРШИМ рендером основного Kamal-шляху
(§DEPLOY-DAY Фаза 3), тож HTTP-canopy репетирував би деплой, оминаючи саме ту ланку, яка
найімовірніше зламається; плюс `secure:`-куки сесії й локалі мовчки не тримаються, і помилки
не буде ніде. Опція «пустити куку по HTTP» ВІДКЛИКАНА, не просто програла.

**Pre-flight checklist (👤 admin):**

- [ ] 🔐 **Origin CA сертифікат випущено** (CF Dashboard → SSL/TLS → Origin Server → Create
      Certificate; hostnames `silkennet.app` + `*.silkennet.app`) і обидва PEM-блоби покладено
      в GitHub Secrets як `TLS_ORIGIN_CERT_PEM` / `TLS_ORIGIN_KEY_PEM`. ⚠️ Приватний ключ
      показується РІВНО один раз — зберегти в той самий vault, що й master-ключі ([`DR.1`](00_07_Action_Plan_Tracker)).
- [ ] **Cloudflare account** з активним Pro/Business планом (proxied CNAME + WAF rules; WebSocket
      unlimited — на Free плані Hotwire/ActionCable лімітується).
- [ ] **Домен у Cloudflare** — `silkennet.app` (web) і `silkennet.com` (його піддомен
      `api.silkennet.com` несе CoAP).
- [ ] **SSL/TLS режим `Full (strict)`** — Cloudflare→origin вимагає валідного сертифіката на
      origin. ⚠️ `Flexible` (CF→origin по HTTP) дає grade B-C на SSL Labs і фальшиве відчуття TLS.
      ✅ Виставлено на обох зонах 2026-08-30 (перевірено в дашборді) — тобто цей рядок уже
      ЗАКРИТО, і саме тому рядок про Origin CA вище є **передумовою**, а не порадою: режим
      увімкнено, сертифіката на origin ще немає, і в цьому стані web-ярус відповідає 521/525.
- [ ] **Origin відомий:** публічна адреса app-хоста (або Ingress Anchor, якщо HTTP іде через
      HAProxy — `app-host-ip`, див. §Розподіл Ресурсів).
- [ ] **DNS-запис створено:** `silkennet.app` → origin, Proxy status: 🟠 **Proxied**.
- [ ] **Ingress Anchor running** зі статичним IP (`gcloud compute addresses list`).
- [ ] 🔴 **Queens бʼють у Ingress Anchor, НЕ в Cloudflare:** firmware резолвить
      `COAP_SERVER_HOST` (`api.silkennet.com`, `firmware/queen/main.c`) → A-запис цього хоста
      МУСИТЬ бути **DNS-only (сіра хмарка)**, не proxied, і вказувати на статичний Ingress-IP.
      Fail-triggered re-resolve host-shipped [FW.58]: після N=3 flush-провалів підряд кеш
      інвалідується → A-запис-фліп підхоплюється без ребута (механізм —
      [`03_02 §4`](03_02_Queen_Gateway_Firmware); bench-verify → [`00_07` FW.58](00_07_Action_Plan_Tracker)).
- [ ] **Rails-side ENV не вимикати:** `force_ssl=true`, `assume_ssl=true`, HSTS активні. CF додає
      `X-Forwarded-Proto: https`, Rails з `assume_ssl` це поважає.
- [ ] **`DISABLE_SSL` не встановлений** у деплой-конфізі (інакше Rails сам не форсуватиме HTTPS —
      false sense of security).

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
| `curl https://… → 525 SSL handshake failed` | Cloudflare→origin не може встановити TLS | Перевірити, що origin має валідний сертифікат; CF SSL/TLS режим знизити до `Full` (без strict) на час діагностики |
| `301 → http://...` нескінченний loop | Rails бачить `X-Forwarded-Proto: http`, hot-redirect-loop | CF Page Rules — має бути `Always Use HTTPS`. У Rails — `config.force_ssl = true`, `config.ssl_options = { redirect: { exclude: ->(req) { req.path == "/up" } } }` для health-check |
| WebSocket падає одразу | Hotwire/ActionCable через CF Free плану лімітується | Upgrade до CF Pro (WebSocket unlimited) АБО Cloudflare Tunnel зі sticky origin |
| CoAP запити від Queen не доходять | A-запис `api.silkennet.com` став CF-proxied (UDP крізь CF не проходить) АБО Королева тримає застарілий DNS-пін | Повернути запис у DNS-only → Ingress-IP; Королева підхопить сама після N=3 flush-провалів підряд ([FW.58], [`03_02 §4`](03_02_Queen_Gateway_Firmware)) або post-reboot |
| TLS grade B-C на SSL Labs | CF SSL/TLS режим = `Flexible` (CF→origin по HTTP) | Перемкнути на `Full (strict)`; примусово вимкнути TLS 1.0/1.1 в CF Edge Certificates |

## 📋 DEPLOY-DAY: перший деплой фазами (Priority Order)

> Переписано 2026-07-04 після операторського red-team: старий 18-крок чеклист мав
> ordering-інверсії (Upstash після секретів, що його вимагають), фантом-кроки і
> доменні суперечності. Машинні «☑ виправлено»-пункти прибрано (вони в git/00_07 §🗄️).
> ⚠️ **[OPS.37] Шлях тепер ОДИН.** Доти тут стояли два, і перший деплой специфікувався на
> платформі без акаунта; CI `Deploy · Canopy` звався «fallback». Тепер це і є основний шлях —
> він оживе сам, щойно GitHub Secrets заповнені (тримай їх незаповненими до готовності; path-gate вже стоїть —
> деплой стріляє лише на deploy-релевантні зміни, [`06_07 §1`](06_07_CICD_and_Runbook_Index)).

**Фаза −1 — Акаунти й значення (за дні ДО дня X):**
GCP project + billing (+budget alert — OPS.11; ⚠️ грант `billing.costsManager` на BILLING-акаунті — див. §IAM) ·
**Upstash ×2** (production + canopy) → 2× `rediss://` URL · **два домени:
`silkennet.app`** (HTTPS, proxied) **та `silkennet.com`** (його піддомен `api.silkennet.com` —
CoAP DNS-only; firmware Queen хардкодить саме його, `COAP_SERVER_HOST`) — купувати в
**незалежного реєстратора, НЕ Cloudflare Registrar** (⚖️ INF.4 2026-08-30: CF Registrar не
дозволяє чужі NS, тож TLS-fallback §вище був би неможливий), Cloudflare підключити як
DNS/proxy поверх · Grafana Cloud
stack (remote_write URL/user/token) · Sentry project (DSN) · Alchemy (Polygon+ETH) +
Helius/QuickNode (Solana mainnet) RPC · 4+ Web3-гаманці (oracle/minter/slasher/anchor
+ опц. celo) + газ MATIC/ETH/SOL/CELO · SSH ed25519 keypair · згенерувати
`RAILS_MASTER_KEY`-бекап + `PROVISIONING_MASTER_KEY` → **vault + offline-копія (DR.1)** ·
🔏 **підпис концентрації [ARCH.114]** (⚖️ момент ратифіковано founder 2026-08-30 — САМЕ тут,
бо три його рядки народжуються цією фазою): прийняти концентрацію GCP явно, текстом, разом
із трьома рядками — (1) на кого оформлені девʼять важелів §«Хто може вимкнути НАС» і хто
платить, (2) другий власник / recovery-контакт бодай на один важіль (`iap_admin_members`),
(3) де фізично лежать обидва master-ключі. Доки три рядки порожні — підпис не ставиться.

**Фаза 0 — Bootstrap інфри:**
`terraform/bootstrap.sh` (GCS state-bucket + CMEK-латч [SEC.22]: keyring `silken-tfstate-ew1`,
PAP, retention 10в/30д; має разовий 30s IAM-sleep — не переривай) → `terraform.tfvars` (project_id, db_password,
`ssh_source_ranges=[<твій реальний CIDR>]` — приклад у tfvars = TEST-NET-3, НЕ лишай!) →
GitHub Secrets **Batch A** (pre-infra: `GCP_PROJECT_ID`, `POSTGRES_PASSWORD`,
`RAILS_MASTER_KEY`, `PROVISIONING_MASTER_KEY`, `ACTIVE_RECORD_ENCRYPTION_*`×3
(`db:encryption:init`; boot-critical [SEC.22] — verify-secrets гейтить) — SA-JSON
`GCP_SA_KEY` більше НЕ потрібен: CI keyless через WIF, INF.22) → tfvars: `iap_admin_members`
(твій e-mail) + [INF.21] `coap_daemon_image` = іммутабельний `sha-<commit>` →
`terraform init && plan && apply` (⛔ **apply — ЗАВЖДИ локально твоїм ADC, не лише перший**:
⚖️ founder 2026-08-29 [INF.22] — джобу `terraform` знято з обох deploy-воркфлоу, бо CI-apply
вимагав би видати deploy-SA чотири GCP-адмін-ролі, тобто god-credential проти самої мети
keyless-WIF. Доти тут стояло «перший apply», і слово «перший» звужувало присуд до дебюту —
читач мав право чекати, що далі apply підхопить CI, а він не підхопить ніколи. Локальний
apply створює WIF-pool, тож CI не потребує ключа з дебюту; у CI лишається `kamal deploy`,
drift стереже щотижневий `Ops · TF Drift`) → зчитати outputs (`ingress_ip`, `database_private_ip`,
`artifact_registry_url` + `workload_identity_provider`/`service_account_email` → repo
**Variables** `GCP_WORKLOAD_IDENTITY_PROVIDER`/`GCP_SERVICE_ACCOUNT`, після чого CI-деплой keyless). **SSH на анкор = IAP-тунель + OS Login (INF.20 (в), wired):**
`gcloud compute ssh silken-net-ingress --tunnel-through-iap --zone europe-west1-b` —
порт 22 в інтернет не відкритий, ключі keyless (керує OS Login); 🔴 **[OPS.37] Kamal-нога (б)-клею (`ssh.proxy_command` через `start-iap-tunnel` + SA-ролі)
більше НЕ опційна:** доти перший деплой ішов повз SSH, тепер він іде Kamal'ом, тобто
SSH-модель стоїть на критичному шляху.

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
(DNS-only, сіра хмарка!)** + `silkennet.app` → app-хост (proxied, після Фази 3) →
Kamal-плейсхолдери: `image:` AR-шлях, servers-IP, `POSTGRES_HOST` (S1.5/INF.15) →
**заповнити `/etc/silkennet/coap.env` на анкорі** (7 значень: `POSTGRES_PASSWORD`/
`REDIS_URL`/`RAILS_MASTER_KEY`/`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`/`_DETERMINISTIC_KEY`/
`_KEY_DERIVATION_SALT`/`SENTRY_DSN`; **НЕ** `PROVISIONING_MASTER_KEY` — coap лише
enqueue-ить, `master_key_strength_check` його `$PROGRAM_NAME`-skip-ає [SEC.22]; AR-encryption
×3 = boot-critical, guard fail-closed без них; Postgres-host уже впечатаний terraform'ом) →
`systemctl restart coap-daemon` → `bin/coap_smoke --host <ingress_ip>`.

🔴 **Фаза 2t — TESTNET-контракти (передує Фазі 3; це НЕ опція) [OPS.37 / `INF.27`]:**
`forge script contracts/script/Deploy.s.sol --broadcast` на **Amoy + Sepolia** — EVM-ланки; ⚠️
**Devnet-ланка `forge`-ом НЕ робиться**: Solana-програми в репо немає, це SPL-mint + fee-payer
ATA руками. `REQUIRE_SAFE_ADMIN` лишається **unset/false** (Safe-гейти mainnet-only — скрипт
тоді лише WARN'ає замість revert), але **шість ENV `run()` вимагає й на dry-run**:
`ADMIN_ADDRESS` · `DAO_TREASURY_ADDRESS` · `MINTER_ORACLE` · `SLASHER_ORACLE` · `ANCHOR_ORACLE`
· `DEPLOYER_PRIVATE_KEY` (на testnet перші дві — операторські EOA, і `DAO_TREASURY_ADDRESS` є
ВХОДОМ скрипта, не його виходом) → зібрати адреси → **пʼять рухів одним заходом** (повний
перелік і його пастки — у самому `config/deploy.canopy.yml`, там же й нагадування, що
`env:`-блок `deploy.yml` мусить дзеркалити глобальний `env.secret`, інакше змінна інжектиться
ПОРОЖНЬОЮ). Оголошення є ТВЕРДЖЕННЯМ про проводку, тож будь-які чотири з пʼяти дають гучну
відмову буту. ⊕ Не плутати з deploy-smoke [`06_08 §4.5`](06_08_Resilience_and_Failover_Policy):
той — одноразова Amoy-репетиція ПЕРЕД mainnet, ця фаза — **постійні** стейджингові контракти,
чиї адреси живуть у canopy `env.clear`.
⚠️ **Чому це окрема фаза, а не примітка:** рядок нижче казав «можна паралельно з Фазою 3», і
це було неправдою про власний рунбук — формат-гілка `address_violations` не скоуплена процесом,
тож три плейсхолдери контракт-адрес валять бут **будь-якого** контейнера. Тобто Фаза 3 без
адрес не піднімається взагалі, а з mainnet-адресами вона перестала б бути стейджингом:
[`00_03 §3.3`](00_03_TRL_Matrix_HIL_and_Beyond) робить реальний testnet-пайплайн умовою
Software TRL 7-8, а mainnet — питанням TRL 9. Порядок несучий в обидва боки.

**Фаза 2 — MAINNET-контракти (до першого mint; передує production-рендеру Фази 5):**
fund deployer wallet → export 6 ENV (`DEPLOYER_PRIVATE_KEY`/`ADMIN_ADDRESS`/`MINTER_ORACLE`/`SLASHER_ORACLE`/`ANCHOR_ORACLE`/`DAO_TREASURY_ADDRESS`) + `REQUIRE_SAFE_ADMIN=true` (mainnet-гейти: ADMIN+TREASURY = Safe-контракти, `MINTER != SLASHER` E.2) → `forge script contracts/script/Deploy.s.sol --broadcast --verify`
(ordered SCC→SFC→Anchor→Timelock→Governor→ProtocolParameters — [`05_03`](05_03_Tokenomics_SCC_and_SFC)) →
зібрати 9 адрес → вписати у `config/deploy.yml` env.clear (INF.12) → redeploy job.
(`WEB3_CHAIN_ENV` у базовому манифесті лишається `mainnet` — це і є та вісь, яку testnet-слот
перевизначає, і жодна з двох сторін не «вимикає» гард: обидві є твердженнями.)

**Фаза 3 — ПЕРШИЙ деплой = CANOPY (Kamal/GCP), і лише потім production** (founder 2026-07-04
про принцип; ціль переспецифіковано [`OPS.37`](00_07_Action_Plan_Tracker) 2026-08-29):
`kamal deploy -d canopy` на app-хост → ізольований DB-set `silken_net_canopy` (INF.16) →
`gcloud compute instances add-metadata silken-net-ingress --metadata app-host-ip=<APP_HOST_IP>`
+ `reset` (Pre-Flight #10). Принцип лишається: найризикованіший шлях не дебютує на production.
⚠️ **Але canopy web-only СТРУКТУРНО** (масив-форма `servers:` у `config/deploy.canopy.yml`,
яку стереже `deploy_secret_scan` інваріант B3), тож фонових джоб у ньому немає — доти їх ніс
окремий `job`-сервіс зовнішньої платформи, і після зрізу воркерів у canopy-леґа немає ніде.
Це не дефект рендера, а **відкрите рішення**: дати canopy власну `job:`-роль ⊥ свідомо
тримати canopy без воркерів. Доти canopy перевіряє web-половину, а Sidekiq дебютує на
production — і це мусить бути сказано вголос, бо «canopy зелений» інакше читається як
перевірка всієї системи.

**Фаза 4 — Верифікація (єдиний post-deploy список):**
`db:prepare` пройшов усі 3 бази (INF.16) · `curl https://silkennet.app/up` → 200 +
`/ready` → 200 (DB+Redis+Kredis) · `coap_smoke` зелений + задати repo Variables
`CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` (INF.6) · метрики: 3 process-таргети живі,
job-серії ≠ 0 (S2.4/INF.14) · Grafana-сесія: `deploy/grafana/import.rb` (dashboards+alerts+contact point)
+ contact point (S2.4 — дашборд і правила вже в стеку з 2026-08-29, лишився КАНАЛ) · `/sidekiq` під admin-сесією → 200, під анонімом → 404
(ARCH.61 route-constraint — ops-інструмент DeadSet-runbook'ів живий і закритий) ·
`ss -tlnp | grep 3000` IPv6 (PUMA-IPV6-1) · money fail-closed
(INF.11) · Sentry release (S5.2) · mailer/DB_POOL/entrypoint (INF.13) · гаманці з газом
(Pre-Flight #3).

**Фаза 5 — Production-render + hardening:**
⏱️ [INF.22] Перший release-run **зависне ~10 хв PENDING ×2** (environment wait-timer,
per-job: перед `verify-secrets` і перед `deploy`) — це НЕ зависання, НЕ скасовуй run;
вікно = навмисний solo-approval-substitute ([`06_04 §1`](06_04_Secrets_Checklist)).
`kamal deploy` production → повтор Фази 4 → `RAILS_ALLOWED_HOSTS=
silkennet.app,api.silkennet.com` у env.clear (S6.18 — ОБИДВА легітимні хости:
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
  Queen → CoAP/UDP → lib/daemons/coap_listener → Sidekiq → Rails

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
| CoAP Listener | `lib/daemons/coap_listener` (Ruby) | Достатньо до ~10k вузлів (оцінка E.5, гарнес-обґрунтування `lib/silken_net/load_test/README.md`; фактична стеля — лише staging із prod-adapters, INF.23) |
| Ingress Anchor (`e2-small`) | ✅ Виправлено (`terraform/compute.tf`) | Bottleneck при >10M дерев — див. нижче |
| Ingress Proxy (Rust/Go) | 🔴 Не реалізовано | Series D milestone |
| Kafka / Pub-Sub | 🔴 Не реалізовано | Series D milestone |
| Read-Only Replicas | 🔴 Не налаштовано | Terraform: `google_sql_database_instance` replica |
| conntrack + UDP rate limit | ✅ Виправлено | `terraform/compute.tf` startup_script |

#### 🌍 Front-Door Bottleneck — Ingress Anchor на `e2-small` (Series D)

**Проблема.** Ingress Anchor (`compute.tf`, `silken-net-ingress`) — це один `e2-small` (2 vCPU shared, 2 GB RAM, обмежений egress). CoAP-демон приймає UDP/5683 прямо на ньому (PRIMARY, INF.17); HAProxy проксює 80/443 на app-хост. При >10M дерев → мільйони Queens → один VM стає вузьким горлом для CoAP/UDP (демонова стеля ~10k вузлів — E.5, оцінка з гарнеса `load_test`, не вимір — настане раніше за мережеву; фактичне число дасть лише staging-прогін INF.23).

**Опції еволюції (упорядковані за зростанням інвазивності):**

| # | Підхід | Що дає | Що потрібно |
|---|--------|--------|-------------|
| 1 | **GCP L4 Network Load Balancer + MIG `e2-small`** | Горизонтальний autoscaling, безмежний throughput, та сама статична IP (forwarding rule) | Terraform: `google_compute_forwarding_rule` (L4 UDP) + `google_compute_region_instance_group_manager` з autoscaler; стартап-скрипт ідентичний існуючому (CoAP-демон на кожному інстансі MIG; за стелею демона — ARCH.2 Rust/Go proxy). DNS A не змінюється. |
| 2 | **Cloudflare Spectrum (UDP forwarding)** | Глобальний anycast → найближча PoP-нода, DDoS-фільтрація, без власної VM-інфраструктури | Cloudflare Enterprise (Spectrum — paid add-on); CNAME `api.silkennet.com` на Spectrum endpoint; whitelist origin IP app-хоста. GCP Ingress Anchor можна вимкнути. |
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
