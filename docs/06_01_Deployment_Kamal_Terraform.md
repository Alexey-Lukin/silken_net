# 06_01: Розгортання Kamal & Terraform (Canopy vs Production)

## 🎯 Мета

Зафіксувати повний стан конфігурацій розгортання та інфраструктури як коду (IaC). Документ відповідає на три ключові питання:

1. Чим відрізняються середовища **Canopy** (Staging) та **Production**?
2. Що розгортається в **GCP**, а що — у зовнішніх SaaS (Upstash, Grafana Cloud, GHCR)?
3. Які **API-ключі, секрети та сертифікати** потрібні для першого реального деплою?

---

## ✅ Статус

- **Поточний TRL:** TRL 4 — інфраструктура РОЗГОРНУТА (перший `terraform apply` 56/56, 2026-08-31), а **`kamal deploy` ПРОВОДИВСЯ й провів увесь ланцюг до запущеного контейнера** (2026-09-01: WIF → AR → OS Login → IAP → SSH-під-SA → мережа → proxy → build/push/pull → старт → Rails-бут). 🔑 **Точне формулювання несуче в обидва боки, і доти цей рядок брехав у бік бідності — а цитували його як «дім факту» щонайменше чотири інші сторінки:** «деплою не було» БІЛЬШЕ НЕ ПРАВДА, «застосунок працює» — ЩЕ НЕ ПРАВДА. Бут не завершується (`web3_network_guard` на незаведених адресах слоту), тож **трафіку не обслуговувано жодного разу**, і саме це, а не відсутність деплою, робить інертними всі console-рецепти репо.
- **Відкрите:** deploy-readiness (акаунт GCP, Ingress IP, GitHub Secrets) → [`00_07`](00_07_Action_Plan_Tracker) (S1.1, INF.4; INF.6 і S5.6 — у §🗄️).

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
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | S1.1, S1.5, INF.4 (INF.6 · S5.6 → §🗄️) |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Pre-Flight Checklist (до першого фізичного деплою)](#-pre-flight-checklist-до-першого-фізичного-деплою)
- [Перший деплой — один носій](#-перший-деплой--один-носій)
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
| **1** | **DNS / TLS до першого деплою** | Після `terraform apply` скопіюй IP та створи A-запис (`api.silkennet.com → <ingress_ip>`). Дочекайся: `dig api.silkennet.com` → правильний IP. **Тільки тоді** деплой. 🔴 **Ця клітинка до 2026-08-31 суперечила сама собі, і голова читалась першою:** вона казала «при ввімкненому `proxy.ssl` (зараз **закоментований** у `config/deploy.yml`) kamal-proxy робить Let's Encrypt ACME-challenge», тоді як хвіст тієї ж клітинки вже називав правильний стан — Origin CA, не ACME. Обидві половини писались у різні дні, дужка-стан зайшла 2026-06-23 і померла 08-31 о 09:37 (`fc4083c5` увімкнув блок). **Чинний стан: `proxy.ssl` УВІМКНЕНО з Origin CA-парою в обох маніфестах**, тож ACME тут не відбувається взагалі, а крок залежить від DNS (маршрутизація) **і** від секретів `TLS_ORIGIN_*` — обидва тепер у `BOOT_CRITICAL` обох воркфлоу, бо порожнє значення дає ПОРОЖНІЙ сертифікат мовчки (§Сертифікат НА ORIGIN). ACME-передумова лишається чинною **лише** для TLS-fallback без CF. ⚠️ Підстава, чому саме Origin CA, а не Let's Encrypt (CF у `Full (strict)` вимагає сертифіката НА ORIGIN і ходить туди ЛИШЕ по HTTPS, тож HTTP-01 не доставляється) живе одним домом у §Сертифікат НА ORIGIN — тут не переказується, бо переказ уже двічі протух саме в цій клітинці. DNS усе одно потрібен для маршрутизації трафіку. |
| **2** | **`.kamal/secrets-common` файл існує + повний** | Kamal читає секрети з `.kamal/secrets-common` (не з environment). Заповни **усі** змінні з `config/deploy.yml env.secret` (drift = boot crash або silent Web3 failure): **(a) Application core:** `RAILS_MASTER_KEY`, `SECRET_KEY_BASE` (boot-critical — [`06_04 §1.1`](06_04_Secrets_Checklist)), `POSTGRES_PASSWORD` (host/user/database — non-secret `env.clear`, component style `config/database.yml`), `REDIS_URL`, `GCP_ARTIFACT_REGISTRY_KEY` (registry pull). `KREDIS_REDIS_URL` — **не** додавати: Kredis читає `REDIS_URL` як є (`config/redis/shared.yml`), а порожній інжект перебив би це значенням «» [B1]; задавати лише щоб вивести локи на ОКРЕМИЙ інстанс. **(b) 🛑 Boot-critical:** `PROVISIONING_MASTER_KEY` (`master_key_strength_check.rb` raises `SecurityError` без неї) + `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`/`_DETERMINISTIC_KEY`/`_KEY_DERIVATION_SALT` ([SEC.22] `active_record_encryption_keys_check.rb` fail-closed; `db:encryption:init`). **(c) Observability:** `SENTRY_DSN`. **(d) Web3 oracle keys:** `ORACLE_MINTER_PRIVATE_KEY`, `ORACLE_SLASHER_PRIVATE_KEY`, `ETHEREUM_ANCHOR_PRIVATE_KEY` — legacy `ORACLE_PRIVATE_KEY` **RETIRED повністю** (INF.22: жоден код не читає, guard-tripwire відмовляє значенню під цим ім'ям); CI-джерело money-п'ятірки (ці три + `SOLANA_WALLET_KEYPAIR`, `ORACLE_CELO_PRIVATE_KEY`) = GH Environment `production`, НЕ repo-secrets (INF.22 → [`06_04 §1`](06_04_Secrets_Checklist)). **(e) RPC endpoints:** `ALCHEMY_POLYGON_RPC_URL`, `ALCHEMY_ETHEREUM_RPC_URL`, `SOLANA_RPC_URL`. **(f) Solana minting:** `SOLANA_WALLET_KEYPAIR`, `SOLANA_FEE_PAYER_PUBKEY`, `SOLANA_FEE_PAYER_TOKEN_ACCOUNT`, `SOLANA_USDC_MINT_ADDRESS`. **(g) Chainlink:** `CHAINLINK_HMAC_SECRET` (лише callback-endpoint; dispatch-секрети вилучено — ARCH.53). |
| **3** | **Gas на Web3-гаманцях** | Воркери потребують нативної крипто: **MATIC** (Polygon), **ETH** (L1), **SOL** (Solana), **CELO** (Celo). Без газу → "Insufficient Funds" на кожній транзакції → Sidekiq потоне у ретраях. |
| **4** | **LoRa-антена підключена** | **КРИТИЧНО.** Ніколи не подавай живлення без антени на SMA/U.FL порту. SX1262 відбиває RF назад у чип (high VSWR) — радіотракт згоряє за мілісекунди. Незворотно. Правило: антена → живлення. |
| **5** | **HKDF AES-ключів (post-FW.1 + ARCH.42 + FW.2 (в))** | Кожен Soldier має **per-device session AES-128 LoRa ключ** (`aes_key[4]`, 16 bytes) + **cluster control-plane KEYB** (`bcast_key[4]`, 16 bytes — двоключова модель [`03_05 §3.1`](03_05_Hardware_Symmetric_Crypto_and_Security)); Queen — той самий KEYB як єдиний LoRa-ключ + окремий **AES-256 CoAP ключ** (`coap_key[8]`, 32 bytes). Усі деривуються з `PROVISIONING_MASTER_KEY` через HKDF з domain-separated info-strings (`"silken-aes-128-lora-key"` / `"silken-aes-128-broadcast-key"` / `"silken-aes-256-device-key"`). Перевіряй на factory bench, що backend і firmware повертають той самий байтовий ключ за тим самим salt. Симптом mismatch: сміття після декрипту (телеметрія на Rails / downlink на Солдаті). Детальніше: [`03_06 §2`](03_06_Factory_Flashing_and_Key_Provisioning). |
| **6** | **CoAP UDP smoke test через Ingress Anchor** | **[INF.6]** Перевір end-to-end UDP-шлях `Queen → Ingress Anchor → CoAP daemon` (PRIMARY: демон бере UDP прямо на анкорі — INF.17 2026-07-04; FALLBACK: socat-релей → дормантна Kamal `coap`-роль) ПЕРЕД першим прошиванням Queen. Без цього silent UDP failure не помітний з HTTP-only health checks. **Автоматизовано:** `.github/workflows/coap_smoke.yml` (`workflow_dispatch` для ad-hoc запуску; `workflow_call` — заведений post-deploy gate'ом у `deploy.yml`/`deploy-production.yml`, job `coap-smoke`, активується repo Variable `CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST`); inputs: `host` / `port` (default `5683`) / `timeout_seconds` (default `10`) / `retries` (default `3`). **Ручна команда (з машини за межами VPC, що імітує Queen; stdlib-only Ruby, без libcoap):** <br>`bin/coap_smoke --host api.silkennet.com` <br>Зонди = freeze-contract FW.56 (точні байти: RST на сміття, `4.04` на невідомий маршрут з 0xFF-MID-піном, `2.04` лише після enqueue батча — НЕ generic liveness; семантика — [`03_02 §4`](03_02_Queen_Gateway_Firmware)). Якщо timeout: перевір (a) GCP firewall `allow-coap` UDP 5683 = `0.0.0.0/0`; (b) на анкорі `systemctl status coap-daemon` (PRIMARY; env-file `/etc/silkennet/coap.env` заповнений?) АБО, у fallback-режимі, `coap-relay` (socat → app-хост) + (c) Kamal `coap`-роль публікує `5683/udp`; (d) rescue-логи демона: `docker logs silkennet-coap`. Швидка перевірка «чи взагалі слухає UDP» через `nc`: `echo -ne '\x40\x02\x00\x01' \| nc -u -w2 api.silkennet.com 5683 \| xxd` — повертає бінарний CoAP response якщо daemon приймає UDP. |
| **7** | **Schema bootstrap від squashed init_consolidated** | **[INF.7 — Phase 7]** На свіжій базі деплой **НЕ `db:setup`**, а кроки ОКРЕМО: `bin/rails db:create db:schema:load` → **прогін `PartitionMaintenanceWorker` (крок 8)** → bootstrap даних. ⚠️ `db:schema:load` у `:sql`-форматі вантажить `db/structure.sql` І `db/{cache,cable}_structure.sql` — по одному на конфіг (деривація `HashConfig#schema_dump`; носій `spec/db/solid_structure_files_spec.rb`): до 2026-09-02 у репо лежали лише інсталерні `*_schema.rb`, і обидві Solid-бази створювались ПОРОЖНІМИ. ⛔ **І bootstrap на `production` — це НЕ `db:seed`:** [`lib/tasks/governance.rake`](../lib/tasks/governance.rake) від народження каже «db/seeds.rb is destructive … Production must NOT call it under any circumstance», а цей крок доти приписував `db:setup`, який `db:seed` у себе ВКЛЮЧАЄ — два доми канону стверджували протилежне, і в день деплою переміг би рунбук. 🔴 Ціна асиметрична, бо захищена НЕ ТА половина: `db:schema:load` оголошено як `task load: [:load_config, :check_protected_environments]` і на продовій базі воно впаде, а `db:seed` оголошено як `task seed: :load_config` — без гарда взагалі (перевірено в `activerecord/lib/active_record/railties/databases.rake`; цитуємо ІМЕНА задач, не рядки — ті їдуть із версією гему) — тобто `delete_all` по 27 моделях пройде без жодного запитання. Слот `canopy` — навпаки, повна сівба доречна (staging із populated UI). Склад продового bootstrap лишається відкритим — дім [`00_07`](00_07_Action_Plan_Tracker). 🔴 **Порядок несучий, і `db:setup` його порушує за побудовою:** він склеює `schema:load` і `seed` в одну команду, не лишаючи місця для воркера між ними, — а `db/seeds.rb` датує «мовчунку» `73.hours.ago`, тож на деплої 1-3 числа цей рядок цілить у ПОПЕРЕДНІЙ місяць. Якщо дамп його вже не несе, рядок тихо осідає в `_default` і незворотно блокує партицію того місяця (виміряно відтворенням 2026-09-01 — `PG::CheckViolation`; рунбук [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup)). Ми **НЕ** використовуємо `db:migrate` в продакшні до першого деплою — всі pre-launch міграції згорнуті в єдиний `db/migrate/*_init_consolidated.rb` (**timestamp свідомо НЕ називається — бери з `ls db/migrate/`**: він міняється при кожному re-squash, і саме цей рядок уже двічі протухав на ньому), а схема живе в `db/structure.sql` (включно з усіма 3 RANGE-партиційними таблицями + початковими партиціями `_default` + поточним вікном). `schema_migrations` містить анкер **плюс кожну інкрементальну, додану після нього** — рівна кількість тут свідомо не називається, бо вона росте між сквошами; джерело істини — INSERT-блок у кінці `db/structure.sql`. Якщо хтось додає incremental міграцію після цього — `StrongMigrations.start_after` (стоїть на живому анкері — звіряй із `config/initializers/strong_migrations.rb`, ніколи з цього рядка) змусить її пройти всі checks. ⊕ **З 2026-08-23 воно ВИВОДИТЬСЯ з імені файлу анкера** [OPS.24], тож re-squash більше не має кроку «bump start_after» — а разом із ним зник і єдиний мовчазний спосіб зіпсувати процедуру (значення нижче за живий анкер знімало перевірки з уже застосованих міграцій, і ніщо не червоніло). **НЕ** робіть squash повторно після першого деплою (втратите history) без zero-downtime плану. |
| **8** | **PartitionMaintenanceWorker cron у Sidekiq** | `30 0 * * *` UTC, `PARTITIONED_TABLES = %w[telemetry_logs gateway_telemetry_logs blockchain_transactions]`. 🔴 **Перевіряй НЕ «чи впаде `INSERT`» — він НЕ впаде, і саме тому цей крок небезпечний.** Усі три таблиці мають `_default`-лист, тож рядок місяця без партиції тихо осідає ТУДИ; краху, за яким оператор помітив би проблему, не станеться взагалі. Ціна приходить наступним проходом воркера: `CREATE … PARTITION OF` для того ж місяця падає `PG::CheckViolation` **назавжди** (переміряно 2026-08-28 — [`ARCH.70`](00_07_Action_Plan_Tracker), рунбук [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup)). ⛔ **Тому на свіжій базі воркера ганяють ДО першого трафіку, а не чекають на cron:** `db/structure.sql` несе календар, застиглий на момент дампу, і якщо деплой-день пізніший за останній місяць у ньому — перший же рядок телеметрії зупиняє обслуговування назавжди, ще до першого спрацювання розкладу. Команда: `bin/rails runner 'PartitionMaintenanceWorker.new.perform'` — **між `db:schema:load` і `db:seed`** (крок 7), і в будь-якому разі ДО впуску трафіку. ⚠️ **«ПІСЛЯ кроку 7» тут стояло до 2026-09-01 і було ПІЗНО:** крок 7 тоді приписував `db:setup`, який сіє всередині себе, тож воркер приходив уже після того, як `db:seed` заселив `_default`. Вікно воркера накриває попередній місяць саме тому, що сівба туди пише. Аж тоді перевіряй `psql -c "\d+ telemetry_logs"`, що партиція наступного місяця є. Якщо worker silent-fails — перевір Sentry alert (Phase 7 додав `Sentry.capture_exception` у rescue блок). |
| **9** | **Kamal-цілі → ІМʼЯ інстансу APP-ХОСТА (не IP і не анкер!)** | **[S1.5]** Усі пʼять kamal-SSH-цілей несуть `silken-net-app` — рядок-ІМʼЯ, не адресу: ролі web/job/coap **і** `accessories.alloy.host` у `config/deploy.yml` (одна машина: Alloy дістає таргети через docker-мережу `kamal`) плюс `servers:` у `config/deploy.canopy.yml`; окремо `image:` → повний AR-шлях із `terraform output artifact_registry_url` [INF.15]. 🔴 **ТРЕТЯ редакція цього рядка, і причина щоразу інша — тут вона в тому, що IP був СИНТАКСИЧНО не тим типом.** `ssh.proxy_command` годує `%h` у `gcloud compute start-iap-tunnel`, а той першим аргументом приймає ІМʼЯ інстансу: з адресою він віддає `4047: Failed to lookup instance`, тобто `kamal deploy` не досягає хоста ЖОДНОГО разу. Виміряно першим в історії проєкту прогоном (2026-09-01, run 33495882870) — доти рядок був незаперечним, бо його ніхто не ВИКОНУВАВ. ⛔ Тому `terraform output -raw app_host_ip` сюди БІЛЬШЕ НЕ ПІДСТАВЛЯЮТЬ: приватна адреса лишається значенням для `POSTGRES_HOST`-класу й для метадати рядка **10**, але не для kamal. 🔴 **Цей рядок до 2026-08-31 казав `ingress_ip`, і це вело б увесь стек на НЕ ТУ МАШИНУ.** Він зайшов 2026-07-04, коли app-хоста не існувало (видалений півотом 04-19), тож анкер справді був єдиною машиною — твердження було правдиве й померло 08-30, коли [`OPS.37`](00_07_Action_Plan_Tracker) повернув `google_compute_instance.app`. Рядок **10** тієї ж таблиці тоді оновили, цей — ні; дві сусідні клітинки одного чек-листа розійшлись про те, на якій машині живе застосунок. Ціна не теоретична: Rails+Sidekiq+coap (~3.5 ГБ у стійкому стані, більше в роллінг-вікні) поїхали б на **e2-small (2 ГБ)**, який уже несе CoAP-демон і HAProxy, а `silken-net-app` не дістав би нічого — при цьому HAProxy анкера проксіював би 80/443 на порожній хост. ⚠️ Анкер лишається адресою для **DNS** (він єдиний має зовнішню IP) — це рядок Фази 1, не цей. Без підстановки `kamal deploy` б'є в приватний RFC-1918 нікуди. |
| **10** | **`app-host-ip` metadata після провіжну app-хоста** | **[S1.5]** Після того, як app-хост існує: `gcloud compute instances add-metadata silken-net-ingress --metadata app-host-ip=<APP_HOST_IP> --zone <zone>` + `reset`. Живить HAProxy 80/443 → app-хост і socat-**fallback**; PRIMARY CoAP-демон (INF.17) від metadata НЕ залежить. Поки unset — обидва юніти чесно логують skip (sentinel-guard), HAProxy не стартує. ⚠️ **Виміряно 2026-09-02: на живому анкері HAProxy не «не стартував», а НЕ БУВ ВСТАНОВЛЕНИЙ** — startup-script помер на першому рядку (`sysctl net.netfilter.nf_conntrack_max` без завантаженого модуля, `set -e`) і до кроку встановлення не дійшов, а юніт `google-startup-scripts` рапортував `Finished`; CF два дні відповідав `521` за healthy-контейнером. Фікс — `modprobe nf_conntrack` перед sysctl у `compute.tf` ПЛЮС `export DEBIAN_FRONTEND=noninteractive` на початку скрипта: після modprobe він дійшов до `apt-get install iptables-persistent` і завис у whiptail-діалозі debconf (дерево процесів на живому анкері, startup-юніт `activating` 10+ хв). Третя ланка того ж дня — `dpkg --configure -a || true` перед першим apt: reset посеред `dpkg --configure` лишає dpkg «перерваним», і кожен наступний `apt-get` виходить із кодом 100. Потребує `terraform apply` + цього кроку 10 + `reset`; 2026-09-02 живі метадані оновлено тим самим текстом напряму (план після apply — порожній). ⚠️ [OPS.37] App-хост є в `terraform/` з 2026-08-30 (`google_compute_instance.app`), тож крок гейтований уже не його відсутністю, а самим `apply`; IP беруть командою, не очима: `terraform output -raw app_host_ip`. |

### Менеджер Секретів (Рекомендація)

З десятками API-ключів (12 блокчейнів, GCP, Starlink, DB, Redis, GitHub) критично мати єдине захищене сховище:

- **Bitwarden** (open-source, self-hostable) або **1Password** — один vault per середовище (canopy / production)
- Зберігай кожен токен, приватний ключ та credential там **до** заповнення shell-ENV перед `kamal deploy`
- Ніколи не комітити у git RAW-значення: `.env`, `terraform.tfvars`. Сам `.kamal/secrets-common` **закомічений свідомо** — він містить лише `$VAR`-посилання на shell-ENV (safe-for-git за дизайном Kamal), не значення; не виривай його з git

---

## 🚀 Перший деплой — один носій

⛔ **Тут була §Quickstart: сім bash-кроків, і вони були ТРЕТЬОЮ копією процедури деплою.
Знято 2026-08-31 (⚖️ founder), бо копія протухла, а читалась першою — вона стоїть вище за
§DEPLOY-DAY у цьому ж документі.** Виміряні розходження, кожне з яких оператор виконав би
дослівно: секрети `POSTGRES_HOST`/`POSTGRES_USER` наказувалось класти в
`.kamal/secrets-common`, де їх немає й не має бути (Pre-Flight #2 того ж документа казав
правильно — `env.clear`) · із 32 імен `secrets-common` бракувало девʼяти, серед них
`CANOPY_REDIS_URL`, без якого локальний `kamal deploy -d canopy` мовчки сідає на невалідний
Redis при ЗЕЛЕНОМУ деплої · перелік `terraform output` називав два значення з пʼяти · крок
`coap_daemon_image` був відсутній, тож анкер тягнув би `:PIN_ME` · фаз контрактів не було
ЗОВСІМ, а без адрес бут падає на девʼяти плейсхолдерах. **Тобто послідовність, названа
«Покрокова послідовність першого реального деплою», гарантовано давала впалий бут.**

🔑 **Це рівно той урок, який [`DEPLOY-1`](00_07_Action_Plan_Tracker) записав про себе** —
«копій виявилось не дві, а ТРИ» — тільки там колапс зробили в трекері, а тут третю копію
лишили стояти. Носій правила мусить стояти там, де стоїть ВИКОНАВЕЦЬ, і виконавець у день
деплою читає фази, а не швидкий вхід.

➡️ **Єдиний носій — §DEPLOY-DAY нижче** (Фази −1а → 6), а передумови, що можуть мовчки
зламати день, — §Pre-Flight вище. Два факти, які жили ЛИШЕ в знятій секції, мігровано ПЕРЕД
зрізом, не після: заборона `CLOUD_SQL_INSTANCE_CONNECTION_NAME`/`GCP_SA_KEY_BASE64` →
[`06_04 §2`](06_04_Secrets_Checklist), приймальний рядок `Listening on coap://0.0.0.0:5683`
→ Фаза 4.

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
| **GCP ресурси** | Cloud SQL (спільна або окрема БД) + Ingress Anchor (`e2-small`) | Cloud SQL (⚠️ HA — ЦІЛЬ; чинний деплой `ZONAL`, [`06_06 §2`](06_06_Disaster_Recovery_and_Backup)) + Ingress Anchor (`e2-small`, CoAP-демон PRIMARY — INF.17) |
| **Redis** | Upstash Serverless Redis (TLS, `rediss://`) | Upstash Serverless Redis (TLS, `rediss://`) |
| **SSL/HTTPS** | ✅ `force_ssl` + HSTS (1рік, subdomains, preload). `DISABLE_SSL=true` для override | ✅ `force_ssl` + HSTS (1рік, subdomains, preload) |
| **DB** | `silken_net_canopy*` — ізольований набір на тому ж Cloud SQL інстансі (`POSTGRES_DATABASE` override; INF.16) | `silken_net_production` (⚠️ HA — ціль, чинний деплой `ZONAL`) |
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
│  │  Cloud SQL PG17 (3 бази, ZONAL*, ПРИВАТНА IP —      │   │
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
> назвали»**. ⚠️ Дім самої ВІДПОВІДІ — таблиця важелів нижче в цій секції разом із ⛔-блоком «чого дерево знати не може»; [`00_07`](00_07_Action_Plan_Tracker) `ARCH.114` тримає лише те, що ще ВІДКРИТЕ (момент підпису у Фазі −1 + другий RPC-провайдер). Розрізняти несуче: інакше вказівник замикається в кільце — канон шле в трекер, трекер назад у канон.

### 🔌 Хто може вимкнути НАС — інфра-половина реєстру стоячих повноважень [ARCH.114]

**Питання цієї таблиці — не «які секрети ми тримаємо»** (це інвентар [`06_04 §1`](06_04_Secrets_Checklist), і множина інша), **а «який зовнішній контролер здатен ОДНООСІБНО зупинити платформу, і чи є подія, після якої це право має бути розподілене».** Форма й підстава — дзеркало on-chain половини ([`05_03` — Стоячі повноваження](05_03_Tokenomics_SCC_and_SFC) [ARCH.112]): там ролі, тут вендори, питання те саме. Провенанс форми — [`00_05 §7`](00_05_AI_Native_Operating_Model): Толкін («захоплення АДМІНІСТРАТИВНЕ, не видовищне») + Пінчон («картель складається сам, діяча немає» — тобто реєстр виправданий ІНВЕНТАРЕМ, а не гіпотезою про зловмисника) + амана («право без названого строку перестає бути довіреним»).

🔑 **Формулювання, яким власник розвʼязав це питання, і воно тут не як цитата, а як ФОРМА присуду:** таблиця виникла з питання «чи потрібен нам взагалі другий хмарний провайдер», і те питання було **нерозвʼязне, доки концентрацію не названо**. Чесний присуд формулюється не «який вендор безпечніший», **а «назвати концентрацію, яку ми ПРИЙНЯЛИ, а не ту, від якої втекли»**. ⊕ Наслідок несучий: втеча до другого вендора дає ДВІ концентрації замість однієї й жодного розподіленого права, тоді як названа концентрація дає рівно те, чого вимагає амана — предмет, на який можна поставити строк.

⚠️ **Читай таблицю разом із цим рядком, і саме він змінився 2026-08-31: більшість важелів уже ДІЮЧІ.** Живі — GCP+білінг · GitHub · реєстратор · Cloudflare · Cloud SQL · GCS tfstate (перший `terraform apply` пройшов того дня); Alchemy (заведено того ж дня); напів-живі — GHCR (образу ще нема) і Upstash (`silkennet-canopy` є, production упирається в тариф). **Суто проєктних не лишилось ЖОДНОГО** — усі девʼять важелів або діють, або мають заведений акаунт. ⛔ **Три підстави, на яких стояв попередній рядок, мертві всі:** «акаунтів не створено» — створено сім із девʼяти · «деплою не було» — інфра-`apply` БУВ (⚠️ **і з 2026-09-01 деплой ЗАСТОСУНКУ теж був** — див. §Статус на початку файлу; подій тут ТРИ, які легко склеїти: `terraform apply` ⊥ `kamal deploy` ⊥ ЗАВЕРШЕНИЙ бут, і сьогодні не сталась лише третя) · «жоден важіль ще нікому не відданий» — `iap_admin_members` у `posture.auto.tfvars` уже роздає `osAdminLogin` + IAP-тунель. 🔑 **Отже підпис ставиться не «поки дешево», а тому, що концентрація вже РЕАЛЬНА** — і це посилює привід, а не послаблює: реєстр тепер описує стан, а не намір. 🔏 Підпис прийняття цієї концентрації ставиться у **Фазі −1** рунбука нижче, разом із трьома рядками, які знає лише людина (момент ратифіковано ⚖️ founder 2026-08-30 — `ARCH.114`).

| Важіль | Тримач | Що дає ОДНООСІБНО | Розподіляється на події? |
|---|---|---|---|
| **GCP-проєкт + білінг** | Google · платник — **особиста картка засновника** (`terraform/billing.tf` — «the solo founder IS the billing admin») | 🔴 **вимкнути все.** У GCP живуть web · job · Alloy · **CoAP-демон PRIMARY** на Ingress Anchor · Cloud SQL (усі бази, вкл. `cache`/`cable`/canopy) · Artifact Registry · статична IP. Поза ним — рівно три сервіси (Upstash · Grafana Cloud · GHCR) | ⛔ **ні, і це ПРИЙНЯТА концентрація, не пропуск** — другої ноги немає й вона свідомо не будується ([`06_08 §1`](06_08_Resilience_and_Failover_Policy); подвійний рахунок одного контролера — [`00_05 §7`](00_05_AI_Native_Operating_Model)). Бюджет-алерти 50/90/100% ловлять ВИТРАТИ, не втрату доступу |
| **GitHub-акаунт** (репо · Actions · Secrets · GHCR · релізи) | GitHub · особистий акаунт `Alexey-Lukin` | 🔴 **більше, ніж здається, і саме тому він тут ДЕВʼЯТИМ:** через нього йде (1) ЄДИНА ідентичність CI→GCP (WIF довіряє GitHub-OIDC; іншого credential не існує), (2) СХОВИЩЕ всіх deploy-секретів + GH Environment `production`, (3) образ для анкера (GHCR), (4) реліз-ланцюг, (5) merge-gate (branch protection живе на GitHub-стороні, не в дереві), (6) підпис образів (Sigstore-ідентичність = сам workflow) | ⚖️ **подія НАЗВАНА, виконавця немає** — `terraform/wif.tf` дослівно: довіра ключується на **ІМʼЯ** власника (`assertion.repository_owner`), не на незмінний `repository_owner_id`, і стеля оголошена там же: «harden to numeric `*_id` **if the repo ever changes hands**». Тобто зміна власника/організації = обовʼязковий перехід на числовий id |
| **Реєстратор домену** (`silkennet.com` · `.app`) | **GoDaddy — ОБИДВА домени куплено founder-ом 2026-08-30** (по 1 року; незалежний реєстратор — сумісний із TLS-fallback, чужі NS дозволені; ⚠️ цей рядок казав «.app ще НЕ куплено» рівно годину — друга купівля відбулась тим самим вечором, і таблиця важелів свіпається після КОЖНОГО заведення) | 🔴 **єдиний важіль, чия відмова вимагає ФІЗИЧНОЇ експедиції до заліза:** `COAP_SERVER_HOST "api.silkennet.com"` — `#define` у прошивці Королеви (`firmware/queen/main.c`), тож втрата зони = пере-прошити ВЕСЬ флот; зона тепер наша, а не гіпотетична. Гейт `spec/deploy/coap_host_consistency_spec.rb` стереже firmware↔host | 👤 подія настала: реєстратора й власника обрано (особистий акаунт founder-а, GoDaddy 2FA — його рука); лишились NS `.app` → CF (зона провіжниться) + дата продовження в календарі власника |
| **Cloudflare** (TLS + DNS) | Cloudflare · **акаунт живий 2026-08-30** (⚠️ на пошті SHARED-компанії `@active-bridge.com` — рядок «на кого оформлено» підпису ARCH.114 має що записати); обидві зони заведені (Free), SSL = **Full (strict)** на обох, NS `silkennet.com` уже перемкнуто на CF | 🔴 знімає HTTPS усього web-ярусу **і** DNS для CoAP-хоста. ⚠️ Формулювання «TLS існує рівно за рахунок CF» стояло тут до 2026-08-30 і було правдиве лише про КЛІЄНТСЬКЕ плече: воно тихо припускало, що CF→origin іде по HTTP, тобто режим `Flexible`, який цей самий док забороняє. Вимір показав `Full (strict)` на обох зонах — а він вимагає сертифіката НА ORIGIN, якого стек **не мав до 2026-08-31** (§Сертифікат НА ORIGIN; Origin CA випущено, `proxy.ssl` живий в обох маніфестах, ⚠️ тут до 2026-09-01 стояло «відкритим лишається один секрет `TLS_ORIGIN_KEY_PEM`» — **ОБИДВА заведено ще 08-31** (звірено `gh secret list`), тобто рядок старів у бік бідності рівно ту добу, поки таблицю не свіпнули; обидва в `BOOT_CRITICAL` обох воркфлоу, бо порожнє значення давало ПОРОЖНІЙ сертифікат мовчки). ✅ **Fallback РАТИФІКОВАНО ⚖️ 2026-08-30 (§TLS-fallback вище):** прямий A-запис + kamal-proxy `ssl: true` (Let's Encrypt); чесна ціна — NS-пропагація годинами, на час інциденту без CDN/WAF. Передумову ВИКОНАНО: домени куплені в незалежного реєстратора, НЕ CF Registrar | 👤 залишок pre-flight → [`00_07`](00_07_Action_Plan_Tracker) `INF.4` — ✅ **NS і всі три A-записи ЗАКРИТО 2026-09-01** (звірено `dig` проти зовнішнього резолвера; Pre-Flight #6/#7/#8 нижче в цьому ж файлі стоять `[x]`). Доти цей рядок називав їх залишком, суперечачи власній секції. Відкрита в `INF.4` рівно одна нога — **вісім верифікацій деплой-дня**. Пом'якшення додаткове: `[FW.58]` re-resolve рятує від зміни A-запису, не від утрати зони |
| **Cloud SQL** (стан) | Google (у межах того ж проєкту) | 🔴 БД недосяжна → контейнер `exit 1`, `/ready` 503. ⛔ **Автоматичного експорту даних ЗА МЕЖІ GCP немає:** бекап = PITR + 30 снапшотів у тому ж Cloud SQL. Поза ним відновлювані лише (а) баланси токенів — з ланцюга (БД є проєкцією), (б) `AuditLog` — IPFS/Filecoin | ⛔ ні — це той самий контролер, що рядок 1. `deletion_protection = true`; ⚠️ **HA — `REGIONAL` лише в коміченому дефолті, чинний деплой `ZONAL`** ([`06_06 §2`](06_06_Disaster_Recovery_and_Backup) — подія повернення названа). ⚠️ DR-drill **не проводився жодного разу** ([`06_06`](06_06_Disaster_Recovery_and_Backup), `DR.1`) |
| **GCS tfstate** | Google · бакет створено поза terraform (`bootstrap.sh`) | контроль над станом інфри; ручне знищення версії CMEK-ключа робить state-версії **назавжди** нечитабельними (recovery = `terraform import` з нуля) | ⛔ ні. ⊕ **Єдиний важіль із МАШИННИМ виконавцем строку** — ротація CMEK `--rotation-period=90d`, налаштована в gcloud. Копії стану поза бакетом немає (лише 10 noncurrent-версій / 30 днів, і короткий ретеншн — свідомий: кожна версія несе секрети) |
| **GHCR** (образ для анкера) | GitHub (див. рядок 2) | зупиняє оновлення/підйом **CoAP-інтейку**: анкер тягне свій образ звідси systemd-юнітом, поза Kamal/WIF-ланцюгом і без реєстрового credential'а. ⚠️ Kamal тягне з GCP Artifact Registry — це ІНШИЙ реєстр, тож web/job тут не залежать | ⛔ ні — успадковує подію рядка 2. Пом'якшення: `PIN_ME` fail-closed + заборона `:latest` (`INF.21`) — уже завантажений образ переживе відмову, rebuild/reboot ні |
| **Alchemy** (RPC Polygon/Ethereum) | Alchemy · **акаунт заведено 2026-08-31**, free-план, один app на команду. Модель ключа: ОДИН API-key на app, мережі перемикаються ПІДДОМЕНОМ і вмикаються поштучно — увімкнено 16, і вони покривають наш стек цілком: `eth-mainnet` · `polygon-mainnet` (прод) · `polygon-amoy` + `eth-sepolia` (рівно та пара, що потрібна Фазі 2t) · `solana-mainnet`/`solana-devnet` · **`celo-mainnet`/`celo-sepolia`**. Значень у deploy-набір ще НЕ заведено | зупиняє мінт · слешинг · confirmation · L1-якір · governance-sync · treasury-моніторинг. 🔴 **Каскад формально Є, фактично ПОРОЖНІЙ:** механізм (`Web3::ResilientClient` + `RpcConnectionPool`) живий, але при одному URL він вироджується у звичайного клієнта, а з усіх `client_for`-сайтів каскад передає **один** (`MintingRollbackService`); `INFURA_POLYGON_RPC_URL` живе лише в `.env.example` і в deploy-набір не заведений | ⛔ ні, але 🤖 **вимірна діра**: другий RPC-провайдер для Polygon/Ethereum — конфіг, не архітектура. 🔴 **Дужка тут доти казала «Celo й Solana свої каскади вже мають», і це хибно на ЯРУСІ, який має значення** (переміряно 2026-09-01): `CELO_RPC_URL_FALLBACK_1/2` і `SOLANA_RPC_URL_FALLBACK_1/2` заповнені в `.env.example` і мають **нуль** входжень у `config/deploy*.yml`, `.kamal/**` та обох воркфлоу — тобто в контейнер не доїжджають, і порожні в проді УСІ ТРИ каскади, не лише Polygon-ів. Клас той самий, що [`S1.1`](00_07_Action_Plan_Tracker) `TURBO_SIGNED_STREAM_KEY`: значення живе на одному ярусі ланцюга й читається як заведене |
| **Upstash** (Redis ×2 інстанси: production + canopy) | Upstash · акаунт заведено, `silkennet-canopy` живий (виміряно 2026-08-30); **production-інстанс ще ні — упирається в ТАРИФ, не в роботу** (Free = рівно 1 інстанс/акаунт) → [`00_07`](00_07_Action_Plan_Tracker) Фаза −1 | `/ready` → **503 для всієї ноди** (Redis у hard-dependencies), бо на ньому Sidekiq (9 черг) · Kredis-локи мінту/берну/nonce · Rack::Attack. ⊕ Частковий graceful-degrade є лише для nonce (fallback у Solid Cache + власна метрика й алерт) | ⛔ ні. ⚖️ **Тригер названий і вимірний:** повторюваний `m2m_nonce_fallback` день-у-день → перехід на multi-zone Upstash Global DB (рішення за прод-даними) |

🔑 **Що цей інвентар змінив у власному пункті — записано, бо клас повториться.** `ARCH.114` спирався на «виміряний інстанс, що доводить потребу»: `GCP_SA_KEY_BASE64` — довгоживучий SA-ключ із приписаною ротацією 90 днів **без виконавця**. **Цей інстанс МЕРТВИЙ**: споживача знято разом із платформою (`OPS.37`), `google_service_account_key` у дереві **нуль**, а `INF.22` і скіл `deploy` уже кажуть «WIF безвинятковий». **Вердикт (реєстр потрібен) вистояв — упала його ПІДСТАВА**, і заміняє її не риторика, а сильніший живий інстанс того самого класу Кафки: **довіра WIF ключується на ІМЕНІ GitHub-власника, стеля оголошена в самому коді, подія названа («if the repo ever changes hands») — і виконавця в неї немає так само.** Різниця в тому, що цей — не гіпотетичний і не знятий.

⛔ **Чого ця таблиця НЕ може знати, і це не пропуск інвентаря, а межа дерева:** на кого оформлені акаунти, хто платить, чи є 2FA й recovery-контакт, чи має хтось, крім власника, доступ бодай до одного важеля (`iap_admin_members` за замовчуванням порожній), і де фізично лежать `RAILS_MASTER_KEY`/`PROVISIONING_MASTER_KEY` (процедура зберігання у vault — 👤, невиконана, `DR.1`). **Ці рядки заповнює людина, і саме вони перетворюють інвентар на присуд.**
⛔ **І сам підпис має ЗАБОРОНЕНУ форму: концентрацію не можна ухвалити ЗА ЗАМОВЧУВАННЯМ.** «Лишити як сконфігуровано» вибором **не є** — прийняття пишеться ТЕКСТОМ, явно, інакше запису про рішення не існує, і через рік нема чого перечитати: мовчазна згода й недогляд виглядають однаково. 🔑 Момент теж ратифіковано (⚖️ 2026-08-30): підпис ставиться у **Фазі −1** рунбука разом із трьома рядками вище — **не раніше** (тоді він був би про майбутнє: акаунти саме там і створюються) і **не окремо** (тоді він прийняв би й те, чого не назвав, — зокрема стан, у якому при втраті ОДНОГО акаунта не існує другої пари рук).

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
| **Ingress Anchor** | ✅ | — | — | `e2-small`, статична IP: CoAP-демон (PRIMARY) + HAProxy 80/443 → app-хост + socat (fallback) — ✅ HAProxy живий з 2026-09-02 після трьох фіксів startup-скрипта (крок 10) |
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
    - silken-net-app         # ІМʼЯ інстансу, НЕ IP — %h іде в start-iap-tunnel
  job:
    hosts:
      - silken-net-app       # те саме імʼя: одна машина, п'ять kamal-цілей
    cmd: bundle exec sidekiq -C config/sidekiq.yml
    env:
      secret:                       # Money/signing-ключі = JOB-ONLY (п'ятірка:
        - ORACLE_MINTER_PRIVATE_KEY #  MINTER/SLASHER/CELO + ETHEREUM_ANCHOR +
        - …                         #  SOLANA_WALLET_KEYPAIR; legacy ORACLE_PRIVATE_KEY
                                    #  RETIRED — INF.22) — web/coap бутяться keyless;
                                    #  guard scoped signer_process for KEYS; ADDRESS presence is
                                    #  per-variable across job/web/coap [2026-09-01]
  coap:
    cmd: bundle exec ruby lib/daemons/coap_listener
    options:
      publish: ["5683:5683/udp"]   # UDP повз kamal-proxy (він HTTP-only)

# ⛔ `boot.proxy` ТУТ БІЛЬШЕ НЕМА, і це не скорочення ілюстрації [INF.13, 2026-08-31].
# Цей рендер показував блок `boot: {proxy: {publish: ["80:80","443:443"]}}` — а
# `Kamal::Configuration::Boot` приймає РІВНО `limit`/`wait`/`parallel_roles`, тож він робив
# КОЖНУ команду kamal неможливою (`boot: unknown key: proxy`); знято з живого конфіга
# `2ee4ecae`. Оголошена стеля цього рендера («ілюстрація структури, повний інвентар — 06_04»)
# ліцензує ПРОПУСКИ, а не позитивне твердження про ключ: оператор, що звіряв би маніфест із
# каноном, повернув би чотири рядки й дістав деплой, який не доходить навіть до SSH.
# Порти проксі взагалі не є ключем `deploy.yml` — це CLI-опції `kamal proxy boot`, чиї
# дефолти дорівнюють 80/443; легальний конфіг-шлях — `proxy.http_port`/`proxy.https_port`.

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
    - SECRET_KEY_BASE
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
    #     web/coap бутяться keyless щодо КЛЮЧІВ; presence АДРЕС із 2026-09-01
    #     скоуплена пер-змінною по трьох процес-класах (04_02 §Web3NetworkGuard) ---
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
    # RELEASE_VERSION — НЕ env.clear: Sentry-release читає `KAMAL_VERSION`, який Kamal інжектить сам (06_03 §1.2)
    # RAILS_ALLOWED_HOSTS: …  # ⚠️ operator-set, НЕ комітити (хибне значення = 403 block-all; S6.18 + INF.4); ⚖️ 2026-09-02: для CANOPY закомічено `canopy.silkennet.app` в `deploy.canopy.yml` — значення = `proxy.host`, що й так у маніфесті; production лишається операторським
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
# ⚠️ [OPS.20, виміряно 2026-09-02] З НОУТБУКА ОПЕРАТОРА `kamal app exec` НЕ ПРАЦЮЄ:
#   `Net::SSH::AuthenticationFailed for user sa_…` — `ssh.user` у deploy.yml = posix-акаунт
#   SA (OS Login), ключ під який реєструє лише CI; локальна gcloud-ідентичність мапиться на
#   ВЛАСНИЙ posix-акаунт. `kamal app exec` лишається ЧИННИМ рецептом для CI-half — там ключ під
#   SA реєструє сам воркфлоу (INF.20 хід 5). Робоча дорога з ноутбука (read-only `rails runner`
#   і `db:drop` виконано так 2026-09-02):
gcloud compute ssh silken-net-app --tunnel-through-iap --zone europe-west1-d --project silkennet \
  --command 'C=$(sudo docker ps --format "{{.Names}}" | grep web-canopy | head -1); sudo docker exec -it "$C" bin/rails console'
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
| Zone | `europe-west1-d` |
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
  - iap.tunnelResourceAccessor (відкриття IAP-тунелю для `kamal deploy` — INF.20 хід (4),
                               `deploy_iap_tunnel`; НАЙВУЖЧА: тунель БЕЗ шелу)
Роль ПОЗА проєктною ієрархією (разово, руками — див. блок нижче):
  - billing.costsManager      (на BILLING-акаунті, не на проєкті)
IAP-operator ролі ЛЮДЕЙ (iam.tf, for_each `iap_admin_members`):
  - compute.osAdminLogin       (sudo на анкорі через IAP-тунель, INF.20)
  - iap.tunnelResourceAccessor (відкриття IAP-тунелю)
⚠️  Ця роль стоїть у ДВОХ НЕЗАЛЕЖНИХ біндингах — людям (тут) і deploy-SA (вище).
    Розводить їх sudo: шел і sudo лишаються ЗА ЛЮДЬМИ, SA має лише тунель.
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

> ⚠️ **Друга вісь того самого бюджету — ГОРИЗОНТАЛЬНА, і після [`OPS.37`](00_07_Action_Plan_Tracker) висновок цієї нотатки ПЕРЕВЕРНУВСЯ.** Доти вона рахувала від `WEB_CONCURRENCY=4` і давала 2 × 252 + 51 + 8 = **563 > 400**, тобто «другий web-вузол не влазить». Єдиний таргет тепер пінить `WEB_CONCURRENCY=2` (`config/deploy.yml`), тож реально 2 × 126 + 51 + 8 = **311 < 400** — горизонтальне масштабування web **влазить**, і другий вузол більше не гейтований цим рядком Terraform. 🔴 Числа під цим абзацом не містили слова «Akash» УЗАГАЛІ — вони мовчки успадкували мертву четвірку, і саме тому клас міграційного залишку ([`00_06 §1`](00_06_SSOT_Documentation_Standard)) вимагає **перечитати арифметику навколо**, а не лише замінений множник. Вертикальний тригер лишається: при `WEB_CONCURRENCY > 4` на двох вузлах стеля знову перевищить 400. Важелів рівно два, і обидва вимагають рішення заздалегідь: підняти `db_max_connections` (на `db-custom-2-7680` кожне з'єднання коштує реальну пам'ять — тобто це тягне і зміну tier; 🔴 **і вся арифметика цієї секції писана проти 7680 МБ, тоді як pre-fleet деплой стоїть на `db-custom-1-3840` — при поверненні до прод-навантаження переміряти, а не переносити висновок «адекватно»**) **або** завести пулер, якого в репозиторії немає **ніде** (`db_read_replica_count` теж `0`). Наслідок ширший за ємність: цей самий інстанс несе primary + cache + cable + canopy-staging, тож за REGIONAL-HA байти UI-фан-ауту cable реплікуються тим самим WAL, що money-записи — один інстанс вниз = money+cable+cache+staging разом. Ревізит: **або** `WEB_CONCURRENCY > 4`, **або** web-репліка №2 — що настане раніше.

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

**Fallback = прямий A-запис на Ingress Anchor + kamal-proxy `ssl: true` (Let's Encrypt)** —
механізм УЖЕ в стеку (kamal-proxy вміє ACME; `proxy:`-блок живий у `config/deploy.yml`), тож
нове рішення не потрібне — потрібен названий шлях:

🔴 **Два твердження цього рецепта протухли 2026-08-31, і обидва саме тим боком, що робить його
НЕВИКОНУВАНИМ у день інциденту** — а це єдиний день, коли його відкривають. (1) «прямий A-запис
на **app-хост**»: у того немає зовнішньої IP за побудовою, тож запис можливий лише на анкер.
(2) «`config/deploy.yml` тримає **закоментований** `proxy:`-блок» + крок 3 «**розкоментувати**
блок»: блок УВІМКНЕНО (`fc4083c5`), і `ssl: true` більше не існує в дереві ніде — його замінила
пара Origin CA, тобто ІНШИЙ механізм, а не інше значення. **Найдорожче тут не «крок no-op», а
те, що станеться, якщо зробити лише кроки 1–2:** origin віддаватиме браузерам **Cloudflare
Origin CA** — CA, якого немає в жодному публічному сховищі довіри, — тож кожен відвідувач
дістане повносторінкову інтерстиційну помилку замість сайту.

1. **NS-перемикання:** у реєстратора змінити NS із Cloudflare на DNS-провайдера, доступного
   в момент інциденту (реєстраторський дефолт достатній). ⏱ Чесна ціна: NS-пропагація —
   години, це записано, а не приховано.
   🔴 **Пастка UI GoDaddy, яка РОЗЗБРОЮЄ саме цей крок:** вкладка `DNS` у портфоліо стоїть за
   один промах від модалки **«Edit organization Info»** — форми зміни РЕЄСТРАНТА, яка блокує
   трансфер домену на **60 днів**. Тобто одне випадкове натискання робить крок 1 неможливим
   рівно тоді, коли він потрібен. ⛔ Заходити прямим URL `?tab=dns&subtab=nameservers`, ніколи
   кліками через портфоліо.
   ⚠️ **І «ще не пропагувалось» на ОДНОМУ резолвері не є вердиктом** — публічні резолвери
   кешують делегацію незалежно: виміряно 2026-08-30, `8.8.8.8` віддавав старі NS, коли
   `1.1.1.1` уже віддавав нові. Мірка — або ДРУГИЙ резолвер, або статус зони в консолі
   провайдера; інакше в оператора неспростовна умова зупинки посеред інциденту.
   ⊕ Заводячи нову зону: пару NS звіряй **у самій зоні**, не за аналогією з сусідньою —
   Cloudflare не гарантує однакову пару для різних зон одного акаунта.
2. **A-записи напряму:** `silkennet.app → <ingress_ip>` · `canopy.silkennet.app → <ingress_ip>`
   · `api.silkennet.com → <ingress_ip>` (CoAP і так ішов повз CF — його цей інцидент не чіпає).
   ⚠️ Усі три на анкер: він єдиний має зовнішню адресу, 80/443 доходять його HAProxy (`mode tcp`).
   🔴 **І ЗВІДКИ міряти — несуче (2026-09-02):** ноутбук із корпоративним TLS-перехопленням (Zscaler)
   підміняє сертифікат і резолвить хост сам, тож `curl --resolve`/`nc`/`openssl` на IP анкера НЕ є
   прямими пробами origin (`nc :443` «успішний» рукостисканням проксі). Чесні виміри — лише з VM
   (`gcloud compute ssh --tunnel-through-iap`) або з CI.
3. **Замінити Origin CA на ACME:** у `config/deploy.yml` замінити блок
   `proxy.ssl: {certificate_pem: …, private_key_pem: …}` на `proxy.ssl: true` (значення `host:`
   не чіпати — воно з ⚖️ INF.25) → `kamal deploy` → HTTP-01 видає публічно довірений сертифікат.
   🔑 Чому ACME тут раптом працює, хоч під CF не працював: `Full (strict)` ходить на origin
   ЛИШЕ по HTTPS, тож челендж не доставлявся; **без CF у шляху** :80 доходить напряму крізь
   HAProxy, і передумова зникає разом із Cloudflare. Саме тому це заміна, а не увімкнення.
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
- `proxy:`-блок **був закоментований** в обох маніфестах → kamal-proxy віддавав простий HTTP на
  :80 і **нічого придатного на :443**.

**Отже перший же запит крізь Cloudflare відповів би 521/525** — рівно той симптом, який
таблиця траблшутингу нижче вже описує. Клас — «конфіг повний, шлях мертвий»; невидимий доти,
доки нічого не задеплоєно. ✅ **ЗАКРИТО 2026-08-31 (`fc4083c5`): `proxy:` живий в обох
маніфестах із парою Origin CA**, тож абзац вище описує стан ДО фіксу — час минулий тут несучий,
бо доти ці три тире стояли в теперішньому й суперечили ✅-рядку за сорок рядків нижче в цій самій
секції. ✅ **Відкритим не лишилось нічого: ОБИДВА секрети заведено 2026-08-31**
([`00_07`](00_07_Action_Plan_Tracker) INF.4). Порожнє значення давало б ПОРОЖНІЙ сертифікат
мовчки — саме тому обидва імені стоять у `BOOT_CRITICAL` обох воркфлоу, і саме тому
присутність у `secrets-common` доказом НЕ є: ланцюг доводить, що імʼя резолвиться,
а питання було про ЗНАЧЕННЯ.

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

- [x] 🔐 **Origin CA сертифікат випущено 2026-08-31 — і форма важливіша за сам крок.** ⛔ **НЕ
      «хай CF згенерує пару»:** той шлях родить приватний ключ **на серверах вендора** й показує
      його один раз у браузері. Канонічна форма — **власний CSR**, ключ не покидає машину:
      ```
      openssl req -new -newkey rsa:2048 -nodes -keyout origin.key.pem -out origin.csr.pem \
        -subj "/CN=silkennet.app" -addext "subjectAltName=DNS:silkennet.app,DNS:*.silkennet.app"
      chmod 600 origin.key.pem
      ```
      → CF Dashboard → SSL/TLS → Origin Server → Create Certificate → **«Use my private key and
      CSR»** → вставити CSR → 15 років. Вайлдкард покриває `canopy.silkennet.app`, тож
      сертифікат ОДИН на обидва слоти; `api.silkennet.com` його не потребує взагалі (DNS-only,
      CoAP/UDP — TLS там немає).
      🔑 **Приймальна перевірка — не «сертифікат виглядає як сертифікат», а збіг МОДУЛЯ:**
      `openssl x509 -in origin.crt.pem -noout -modulus | openssl sha256` мусить дорівнювати
      `openssl rsa -in origin.key.pem -noout -modulus | openssl sha256`. Розбіжність означає, що
      підписано ЧУЖИЙ CSR, і виявиться це інакше аж на першому TLS-рукостисканні.
- [x] 🔐 **Обидва секрети в GitHub Secrets — заведено 2026-08-31** (`TLS_ORIGIN_CERT_PEM` 06:03Z,
      `TLS_ORIGIN_KEY_PEM` 06:07Z, форма `gh secret set … < origin.key.pem` — редирект тримає
      значення поза екраном і поза історією shell). Сертифікат ПУБЛІЧНИЙ за природою — секретом
      він є лише формою доставки Kamal'ом; ключ у vault, але планка НИЖЧА за master-ключі: втрата
      не незворотна (Origin CA перевидається безкоштовно), витік — дає видати себе за наш origin
      перед CF ([`DR.1`](00_07_Action_Plan_Tracker)).
- [x] **Cloudflare account** — акаунт живий, обидві зони на плані `Free`, і цього ДОСИТЬ.
      ⚖️ **Вимогу «Pro/Business» ЗНЯТО 2026-09-01 як СПРОСТОВАНУ — не пом'якшено, а спростовано,
      бо впав сам механізм.** Рядок стояв на «WebSocket-стелі Free плану»; доки Cloudflare
      ([network/websockets](https://developers.cloudflare.com/network/websockets/), last updated
      2026-08-14) кажуть дослівно **«WebSockets are supported on all Cloudflare plans»**.
      ⚠️ **Підстава тут звужена після адверсарного ревʼю того ж дня, і звуження несуче.** Доти
      рядок доводив тезу мовчанням чужого документа («у їхньому домі per-limit чисел немає
      WebSocket-концюрентності як КАТЕГОРІЇ») — а це (а) **аргумент від мовчання**, тобто
      відсутність ДОКУМЕНТА, не механізму, і (б) взято не той дім: **сама WS-сторінка має власний
      розділ `Connection limits`**, і в ньому два підрозділи (idle timeout · session affinity).
      ⊕ Друге самозаперечення: «стеля plan-незалежна (кастомізує лише Enterprise)» — якщо
      Enterprise її кастомізує, вона рівно для нього plan-ЗАЛЕЖНА; сама тривалість CF не публікує.
      🔑 **Тож несуча підстава — НАШ ПРОФІЛЬ, а не відсутність механізму:** `turbo-rails` мемоїзує
      `consumer` на рівні модуля (`app/javascript/turbo/cable.js` **у гемі `turbo-rails`, не в
      нашому дереві** — у нас importmap-пін на `turbo.min.js`), тож підписки вкладки
      мультиплексуються в **ОДИН** сокет. ⚠️ І «десять `turbo_stream_from`» лічить САЙТИ в коді, а
      не підписки: два з них у циклах (`dashboard/home` розгортає три `FEED_DOMAINS`,
      `firmwares/index` — по одному на шлюз з АКТИВНОЮ або запланованою OTA-кампанією в межах ОДНІЄЇ організації, і секція взагалі не рендериться, коли їх нема; «необмежено» правдиве лише в сенсі «нема `.limit`») — саме тому мультиплексування тут
      і є аргументом. `ApplicationCable::Connection` пускає лише автентифікований браузер
      (Bearer-шляху немає свідомо), тож флот з'єднань не додає: Queen ходить CoAP/UDP повз CF.
      ⚠️ **Числа профілю тут свідомо НЕ називаємо, і це поправка після адверсарного ревʼю:**
      попередня редакція казала «реалістична стеля — десятки сокетів», а це ПРОГНОЗ ПОПИТУ, не вимір,
      і він двічі занижував — одиниця тут **ВКЛАДКА**, не користувач, а перша стеля, в яку впирається
      цей тракт, узагалі не в Cloudflare: ActionCable ділить бюджет із Puma, тобто НАШ ярус нижчий за
      будь-яке циркулююче CF-число. Перенесення розмови на CF-число тихо знімало саме це. ⛔ **Дзеркальна пастка: платні фічі тут уміють ЛАМАТИ, а не
      розблоковувати** — таблиця сумісності CF ставить `Argo | No` проти WebSockets. ⚠️ Ми звузили
      це до «Argo Smart Routing»; CF пише парасольковий бренд **Argo**, і сторінка самого
      Smart Routing WebSockets не згадує — тобто звуження правдоподібне, але НЕ документоване. Реальні ризики тракту plan-незалежні (idle timeout →
      heartbeat; рестарти CF рвуть сокети → реконект), і жоден із них апгрейдом не лікується.
- [x] **Домен у Cloudflare** — `silkennet.app` (web) і `silkennet.com` (його піддомен
      `api.silkennet.com` несе CoAP). ✅ Обидві зони `Active` (виміряно в дашборді 2026-08-31).
      ⚠️ Зона активна ≠ трафік ходить, і саме цей рядок довго був носієм: доки записів нуль,
      Active означає лише «CF відповідає за зону». ✅ **Три A-записи заведено 2026-09-01**,
      тож стан пройдено — перевіряй його `dig`-ом, не дашбордом (форма нижче).
- [x] **SSL/TLS режим `Full (strict)`** — Cloudflare→origin вимагає валідного сертифіката на
      origin. ⚠️ `Flexible` (CF→origin по HTTP) дає grade B-C на SSL Labs і фальшиве відчуття TLS.
      ✅ Виставлено на обох зонах 2026-08-30 і **переперевірено 2026-08-31** (обидві зони
      `Full (strict)`, мітка «Mode last changed · 1 day ago» збігається). Пара Origin CA до
      нього тепер теж на місці, тож стан «режим увімкнено, сертифіката немає» — за яким web-ярус
      віддавав би 521/525 — **пройдено**, а не чинний.
- [x] **Origin відомий:** `terraform output -raw ingress_ip` — **Ingress Anchor, і альтернативи
      немає**. Рядок доти пропонував «публічну адресу app-хоста (або Ingress Anchor…)», тобто
      розвилку з неіснуючою першою гілкою: у app-хоста зовнішньої IP немає за побудовою
      (`terraform/compute.tf` — «NO PUBLIC IP, on purpose»), а 80/443 доходять до нього
      HAProxy'єм анкера (`mode tcp`). Дивись §Розподіл Ресурсів.
- [x] **DNS-записи створено:** `silkennet.app` → `ingress_ip`, Proxy status: 🟠 **Proxied**
      · **`canopy.silkennet.app` → `ingress_ip`, 🟠 Proxied** — ⚠️ без нього Фаза 3 підіймає
      canopy зеленим, а `proxy.host` не резолвиться, тобто репетиція основного шляху тихо не
      відбувається (`config/deploy.canopy.yml` вимагає цього запису, а чек-лист його не мав).
- [x] **Ingress Anchor running** зі статичним IP (`gcloud compute addresses list`).
- ✅ **Три рядки вище ЗАКРИТО 2026-09-01, і закрито ЖИВИМ виміром, не дашбордом** — вони стояли
      відкритими на вже зробленій роботі, тобто чек-лист деплой-дня брехав операторові в бік
      «ще не зроблено» (той самий клас, що вже коштував тут добу на A-записах). Доказ, і саме в
      цій формі: `dig +short @1.1.1.1` віддає для `silkennet.app` і `canopy.silkennet.app`
      **anycast Cloudflare** (`188.114.96.11`/`.97.11` — помаранчева хмарка стоїть, origin
      схований), а для `api.silkennet.com` — **саму** `34.76.16.254`, тобто сіра хмарка справді
      сіра. 🔴 **МЕЖА ЦЬОГО ДОКАЗУ, названа після адверсарного ревʼю 2026-09-01 — доти тут стояло
      «одна команда дискримінує ОБИДВІ половини», і це було перебільшенням, яке ховалось за
      власним поясненням.** `dig` за помаранчевою хмаркою повертає anycast CF **саме тому, що
      origin схований** — отже він доводить **СТАТУС ПРОКСІ**, але про **ЦІЛЬ запису** не каже
      нічого: за хмаркою може стояти хибна origin-IP, і відповідь буде та сама. Це не гіпотетика —
      рівно той сценарій дає `522`, і він названий двома абзацами нижче. 🔴 **А ось чим її доводити — я спершу назвав НЕ ТЕ, і це та сама фігура вдруге.** Крок 2
      §Verification (`curl` → `200`) доводить КОНʼЮНКЦІЮ «правильна ціль ∧ живий origin», а не-`200`
      не каже, яка з половин упала — тобто рівно та властивість, яку я щойно відібрав у `dig`. Ба
      більше: сьогодні той крок віддасть 521/522 **при цілком правильному A-записі**, бо бут не
      завершується. ✅ **Ціль проксованого запису читається ПРЯМО ЗАРАЗ із боку CF** —
      `GET /zones/{id}/dns_records`, поле `content`. Дашборд я відкинув гуртом («показує НАМІР»),
      і це правда про ПОШИРЕННЯ й неправда про ЗНАЧЕННЯ поля: за помаранчевою хмаркою CF-сторона є
      єдиним джерелом істини про ціль, бо DNS її ховає за побудовою. ⚠️ Отже `dig` лишається правильним інструментом для ХМАРКИ й хибним для
      адреси; чекбокс закрито на першій половині свідомо, друга чекає деплою.
      `gcloud compute addresses list` → `silken-net-ingress-ip` = `34.76.16.254`,
      `IN_USE`, `europe-west1`; обидві VM `RUNNING`, у `silken-net-app` NAT-IP порожній — як і
      вимагає конструкція. ⚠️ Перевіряй саме `dig`-ом проти зовнішнього резолвера: дашборд CF
      показує НАМІР запису, а не те, що віддає світ.
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
INGRESS_IP=$(gcloud compute addresses describe silken-net-ingress-ip --region europe-west1 --format='value(address)')
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
| `curl https://… → 521 Web server is down` (без 525) | Cloudflare не дістає origin ВЗАГАЛІ — не сертифікат: анкер без HAProxy (startup-script помер — Pre-Flight крок 10) або мертвий бекенд `10.0.0.3:443`; виміряно 2026-09-02 при заведеній парі Origin CA | `gcloud compute ssh silken-net-ingress --tunnel-through-iap …` → `systemctl is-active haproxy` + `journalctl -u google-startup-scripts -b`; origin з ноутбука не пробити (Zscaler/CF) — міряти з VM або CI |
| `301 → http://...` нескінченний loop | Rails бачить `X-Forwarded-Proto: http`, hot-redirect-loop | CF Page Rules — має бути `Always Use HTTPS`. У Rails — `config.force_ssl = true`, `config.ssl_options = { redirect: { exclude: ->(req) { req.path == "/up" } } }` для health-check |
| WebSocket падає одразу | ⛔ **НЕ план** — «CF Free лімітує WebSocket» спростовано 2026-09-01 (Pre-Flight #3: доки CF кажуть «supported on all plans»). Дивись на plan-незалежні причини: idle timeout без heartbeat · рестарт CF-серверів рве сокети · увімкнений **Argo Smart Routing** (документовано НЕсумісний із WebSockets) · `/cable` не проходить проксі анкера | Heartbeat/реконект на клієнті; вимкнути Argo, якщо вмикали; перевірити 101 крізь проксі кроком 6 вище. ⛔ Апгрейд плану тут не лік — він не купує нічого з переліченого |
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

🧰 **Фаза −1а — ТУЛЧЕЙН на машині оператора (передумова, спільна для всього дня).**
Виміряно 2026-08-31: `gcloud` не був установлений, і жодна фаза цього не казала —
фаза −1 перелічувала АКАУНТИ, тобто те, що заводять у браузері, а рунбук говорить із
**CLI**. Це різні речі, і різницю видно лише коли впираєшся. 🔴 `gcloud` стоїть не на
одному кроці, а на **шести**: `bootstrap.sh` · ADC для `terraform apply` · SSH на анкер
для `coap.env` · `add-metadata`+`reset` · AR-токен для `kamal` push
(`.kamal/secrets-common` → `gcloud auth print-access-token`) · і `ssh.proxy_command`
IAP-тунелю, без якого `kamal deploy` **фізично не досягне** app-хоста без зовнішньої IP.

```bash
# Обовʼязкові — деплой без них не стартує:
gcloud --version      # + gsutil у комплекті; macOS: brew install --cask google-cloud-sdk
terraform --version   # ≥1.15
kamal version
docker --version      # + buildx з linux/amd64 (builder.arch = amd64, машина arm64 → емуляція)
gh --version          # авторизований, scope repo
forge --version       # Фази 2t/2
openssl version; dig -v; jq --version; ruby --version   # ≥4.0.6
# Ланки, що мають ВЛАСНИЙ тулчейн і НЕ покриваються нічим вище:
#   Devnet (Фаза 2t) — solana + spl-token CLI (Solana-програми в репо немає, це руками)
#   Фаза 6           — arm-none-eabi-* + STM32_Programmer_CLI (прошивка Королев)
# 🔴 Корпоративне TLS-перехоплення ЛАМАЄ саме gcloud, і не ламає сусідів — виміряно
#    2026-08-31 на машині власника: `gcloud auth login` віддає SSLError
#    «unable to get local issuer certificate», і ОБИДВА логіни не лягають, попри
#    сторінку браузера «You are now authenticated» — тобто `gcloud auth list`
#    лишається порожнім, а помилка приходить з обміну токеном.
#    Причина розколу: `gh`/`git`/`terraform` на Go читають СИСТЕМНИЙ trust store
#    (корінь проксі там є) → працюють; gcloud тягне ВЛАСНИЙ certifi-бандл → падає.
#    ⛔ Корінь із кейчейна не рятує: у нашому випадку він самопідписаний із
#    basicConstraints БЕЗ critical, і OpenSSL 3 відхиляє його вже іншою помилкою
#    («Basic Constraints of CA cert not marked critical») — зміна виглядає як фікс,
#    а лише переставляє помилку. Робоча форма — заякоритись на ПРОМІЖНОМУ
#    (у нас critical стоїть): certifi-бандл + проміжний → `custom_ca_certs_file`.
#      openssl s_client -connect oauth2.googleapis.com:443 -showcerts   # взяти проміжний
#      cat <sdk>/lib/third_party/certifi/cacert.pem inter.pem > ~/.config/gcloud/ca.pem
#      gcloud config set core/custom_ca_certs_file ~/.config/gcloud/ca.pem
#    ⚠️ Проміжний привʼязаний до хмари проксі й РОТУЄТЬСЯ — це обхід зі строком
#    придатності; довговічний лік = conformant корінь від IT.
#    🔑 Перевіряй ДИСКРИМІНУЮЧИМ тестом, не `curl --cacert`: системний curl на macOS
#    бере системний trust store і проходить ОБОМА бандлами, тобто нічого не доводить.
#    Годиться python-ssl із явним cafile — контроль (гола certifi) МУСИТЬ упасти.
```
⛔ **`ss` до цього переліку НЕ додавай** — крок Фази 4, що його вимагав, замінено (див. там же).

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
🔑 **Спершу ДВА логіни й один export — вони жили тільки в шапці `bootstrap.sh`, а не в цій фазі,
і різниця між ними несуча:**
```bash
gcloud auth login                      # для самого gcloud (bootstrap.sh, ssh, add-metadata)
gcloud auth application-default login  # ADC — саме це читає TERRAFORM; окремий креденшел
gcloud config set project <PROJECT_ID>
export GCP_PROJECT_ID=<PROJECT_ID>     # bootstrap.sh hard-fail'ить без нього (`:?`)
```
⚠️ **Два логіни — не дубль:** `gcloud auth login` кладе user-credentials, `application-default`
кладе ADC-файл, і terraform читає ЛИШЕ другий. Доти `bootstrap.sh` перевіряв ПЕРШИЙ, а радив
другий — тобто його «✅» проходив на креденшелі, який наступному кроку не годиться (виправлено
2026-08-31: скрипт тепер пінить обидва). Далі —
`terraform/bootstrap.sh` (GCS state-bucket + CMEK-латч [SEC.22]: keyring `silken-tfstate-ew1`,
PAP, retention 10в/30д; має разовий 30s IAM-sleep — не переривай) → `terraform.tfvars` (project_id, db_password,
`iap_admin_members=["user:<твій e-mail>"]`; ⛔ **`ssh_source_ranges` лишається `[]`**) → 🔴 **Цей
рядок до 2026-08-31 велів `ssh_source_ranges=[<твій реальний CIDR>]` і стверджував «приклад у
tfvars = TEST-NET-3, НЕ лишай!» — обидві половини хибні, і кожна по-своєму.** У
`terraform/terraform.tfvars.example` там `[]` із приміткою «Optional break-glass DIRECT ssh
(bypasses IAP). **Normally keep []**», тобто твердження про ЧУЖИЙ файл було вигадане ([`00_05
§4`](00_05_AI_Native_Operating_Model) — «реф, що СТВЕРДЖУЄ про чужий документ»); а сама
інструкція наказувала **відкрити :22 в інтернет** повз ратифіковану IAP-модель INF.20 (в), що
їй суперечить і таблиця фаєрволу §Firewall («break-glass-only; normally `[]` → правило не
створюється») двома сторінками вище. Канонічний вхід — `gcloud compute ssh … --tunnel-through-iap`,
а доступ дає `iap_admin_members`, не CIDR →
GitHub Secrets **Batch A** (pre-infra: `GCP_PROJECT_ID`, `POSTGRES_PASSWORD`,
`RAILS_MASTER_KEY`, `SECRET_KEY_BASE` (= поточне `credentials.secret_key_base`; boot-critical,
причина — [`06_04 §1.1`](06_04_Secrets_Checklist); існує до `apply`, тому Batch A),
`PROVISIONING_MASTER_KEY`, `ACTIVE_RECORD_ENCRYPTION_*`×3
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
`artifact_registry_url`, **`app_host_ip`** + `workload_identity_provider`/`service_account_email` → repo
**Variables** `GCP_WORKLOAD_IDENTITY_PROVIDER`/`GCP_SERVICE_ACCOUNT`, після чого CI-деплой keyless).
🔴 **`app_host_ip` — шостий, і його споживач ЗВУЗИВСЯ 2026-09-01: він іде в `add-metadata` Фази 3,
але НЕ в `servers:`.** Kamal-цілі несуть **імʼя** інстансу (`silken-net-app`), бо `ssh.proxy_command`
годує `%h` у `gcloud compute start-iap-tunnel`, а той приймає імʼя, не адресу — з IP він віддає
`4047: Failed to lookup instance`, тобто деплой не досягає хоста взагалі (виміряно першим прогоном,
run 33495882870). ⛔ Не «полагодити» це поверненням IP: обидва твердження — «підстав `app_host_ip`»
і «тунель бере імʼя» — окремо правильні, і саме тому їхня несумісність прожила до першого ВИКОНАННЯ.
⚠️ Це **приватна** адреса (`google_compute_instance.app` не має `access_config` за побудовою) —
А-запис на неї дав би CF `522`; у DNS йде `ingress_ip`, ніколи цей. **SSH на анкор = IAP-тунель + OS Login (INF.20 (в), wired):**
`gcloud compute ssh silken-net-ingress --tunnel-through-iap --zone europe-west1-d` —
порт 22 в інтернет не відкритий, ключі keyless (керує OS Login); 🔴 **[OPS.37] Kamal-нога (б)-клею (`ssh.proxy_command` через `start-iap-tunnel` + SA-ролі)
більше НЕ опційна:** доти перший деплой ішов повз SSH, тепер він іде Kamal'ом, тобто
SSH-модель стоїть на критичному шляху.

**Фаза 1 — Дротування post-infra:**
🔑 **Звідки беруться ДВА Redis-URL, бо консоль Upstash за замовчуванням показує НЕ ТЕ**
(виміряно 2026-09-01 на живій `silkennet-canopy`): у картці бази секція **Connect** має дві
вкладки, і відкрита першою — **REST**, яка віддає `UPSTASH_REDIS_REST_URL` плюс окремий токен,
тобто HTTP-API, якого наш Rails не вживає ЗОВСІМ. Потрібна сусідня **TCP**, і рівно вона дає
`rediss://default:<пароль>@<endpoint>:6379`. ⛔ Третій рядок на тій же сторінці —
`redis-cli --tls -u redis://…` — несе `redis://` з ОДНИМ `s`: скопійований дослівно, він дає
з'єднання без TLS до бази, у якій лежать сесії й nonce-и. **Три схожі рядки, з них правильний
один, і дефолтна вкладка не він.** ⊕ Заразом перевір `Settings → Eviction = OFF` — властивість
без ЖОДНОГО детектора ([`00_07`](00_07_Action_Plan_Tracker) `INF.22`), і питати її треба ПРИ
СТВОРЕННІ кожної бази, бо живе вона в дропдауні вендора. ✅ На `silkennet-canopy` перевірено
2026-09-01: eviction OFF, primary `europe-west1` (same-region із Cloud SQL).

GitHub Secrets **Batch B** — ДВА доми [INF.22]: repo-level = `REDIS_URL`,
`CANOPY_REDIS_URL`, RPC×5, Solana-public×3, `SENTRY_DSN`, `CHAINLINK_HMAC_SECRET`,
`HELIUM_WEBHOOK_SECRET`; **money-п'ятірка (`ORACLE_MINTER/SLASHER/CELO` +
`ETHEREUM_ANCHOR_PRIVATE_KEY` + `SOLANA_WALLET_KEYPAIR`) = ЛИШЕ environment
`production`** (`gh secret set <NAME> --env production`; environment уже створений API з
wait-timer + ref-policy — [`06_04 §1`](06_04_Secrets_Checklist)). ⚠️ Пастка wrong-home:
покладеш п'ятірку repo-level — деплой лишиться ЗЕЛЕНИМ (environment-jobs бачать
repo-секрети як fallback), але ізоляція тихо знульована, а реверс = ручне повторне
введення значень (GitHub секретів назад не віддає) → **verify scope ДО деплою:** `ruby scripts/audit_deploy_secret_scope.rb` (S1.1 — read-only `gh`-preflight: money-квінтет ∈ env `production` ТІЛЬКИ (не repo), WIF-ids = Variables, retired ∉; ловить wrong-home перш ніж деплой його замаскує) → DNS: `api.silkennet.com` **A → ingress_ip
(DNS-only, сіра хмарка!)** + `silkennet.app` → **ingress_ip** (proxied, після Фази 3)
+ **`canopy.silkennet.app` → ingress_ip** (proxied — Фаза 3 підіймає canopy першим, а без цього
запису `proxy.host` не резолвиться й репетиція основного шляху тихо не відбувається). 🔴 **Тут
до 2026-08-31 стояло «`silkennet.app` → app-хост», і це ФІЗИЧНО неможливо:** у
`google_compute_instance.app` немає `access_config` за побудовою («NO PUBLIC IP, on purpose» —
шапка `terraform/compute.tf`), тож `terraform output -raw app_host_ip` віддає **приватну** адресу,
і A-запис на неї під помаранчевою хмаркою дає CF `522` на кожен запит. Єдина зовнішня адреса —
анкер; 80/443 доходять до застосунку його HAProxy. ⚠️ Дзеркальна половина цієї ж пари живе в
Pre-Flight #9 і показувала рівно навпаки (kamal-ролі на анкер) — обидві клітинки успадкували
світ до повернення app-хоста [`OPS.37`](00_07_Action_Plan_Tracker) →
Kamal-плейсхолдери: `image:` AR-шлях, servers-IP, `POSTGRES_HOST` (S1.5/INF.15) →
**заповнити `/etc/silkennet/coap.env` на анкорі** (7 значень: `POSTGRES_PASSWORD`/
`REDIS_URL`/`RAILS_MASTER_KEY`/`ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`/`_DETERMINISTIC_KEY`/
`_KEY_DERIVATION_SALT`/`SENTRY_DSN`; **НЕ** `PROVISIONING_MASTER_KEY` — coap лише
enqueue-ить, `master_key_strength_check` його `$PROGRAM_NAME`-skip-ає [SEC.22]; AR-encryption
×3 = boot-critical, guard fail-closed без них; Postgres-host уже впечатаний terraform'ом) →
`systemctl restart coap-daemon` → `bin/coap_smoke --host <ingress_ip>`.

🔴 ⚠️ **Стан змінився 2026-09-01: порядок нижче БІЛЬШЕ НЕ ПОРАДА.** Доки canopy-набір секретів був неповний, `Deploy · Canopy` скіпав чисто — і саме той скіп, а не дисципліна, тримав порядок. Набір закрито, тож кожен deploy-релевантний коміт у `main` запускає справжній `kamal deploy -d canopy`, і без адрес Фази 2t він доходить до ЗАПУЩЕНОГО контейнера й гине в `web3_network_guard`. **Порядок став властивістю CI.**

**Фаза 2t — TESTNET-контракти (передує Фазі 3; це НЕ опція) [OPS.37 / `INF.27`]:**
```bash
cd contracts && forge script script/Deploy.s.sol --rpc-url "$AMOY_RPC_URL" \
  --broadcast --legacy --with-gas-price 30gwei   # ⚠️ ОБИДВА прапорці, див. нижче
cd contracts && forge script script/Deploy.s.sol --rpc-url "$SEPOLIA_RPC_URL" --broadcast
```
🔴 **`--legacy` тут НЕ стиль, а умова відправки — виміряно живим прогоном 2026-09-01, і без нього деплой падає, НЕ витративши газу.** Сам `--with-gas-price` ставить лише `maxFeePerGas`; `maxPriorityFeePerGas` forge далі бере з МЕРЕЖІ (того дня ~60 gwei), тож виходить `priority > max`, і RPC відхиляє запит рядком `-32000: max priority fee per gas higher than max fee per gas` **ще до броадкасту**. ⚠️ Діагностика підступна тим, що forge встигає надрукувати повний перелік адрес «deployed at …» — це ПЕРЕДБАЧЕННЯ симуляції, не факт; `nonce` деплоєра лишається 0, байткоду за адресами немає. **Тож ніколи не читай ті рядки як результат — перевіряй `cast code <адреса>` і `cast nonce`.** ⊕ `--legacy` робить транзакцію type-0 з ОДНІЄЮ ціною, і тоді пін означає рівно те, що обіцяє. Дзеркальний бік тієї ж осі того ж дня: MetaMask пропонував priority-fee **1.5 gwei** там, де сам показував діапазон мережі `25-600` — тобто нижче полиці, і кадри так само не бралися. **Полиця Amoy ≈25 gwei є спільною причиною обох відмов.**
🔴 **Пін газу на Amoy купує ЗДІЙСНЕННІСТЬ у межах крана — але величин тут ДВІ, і плутати їх
коштувало хибного канону в перший же день.** Σ **ЛІМІТІВ** = скільки треба МАТИ на балансі
(перевіряється при сабміті кожного кадру); Σ **ВИТРАЧЕНОГО** = скільки насправді списано.
⛔ **Адреси Amoy живуть ТУТ, бо `contracts/broadcast/` у `.gitignore`** — інакше єдиний їх слід поза ланцюгом зник би з деревом: Timelock `0xC2E8d2120aD3576b03d32211c918b6D434b91c8f` · **`CARBON_COIN_CONTRACT_ADDRESS` `0x18a8A50e0DC0103aA94de51b78f352E2d26E1b22`** · **`FOREST_COIN_CONTRACT_ADDRESS` `0x9366a4CbA0461E150A3409CD2767Ff7b8db6d4b7`** · StateRootAnchor `0x9F70c79786130b2861ccd0947F0b7f482E3CE02C` · Governor `0x503C216A33f9A9f2bd2967d11Ae2D3159dc9902F` · ProtocolParameters `0x1F20032142C98BBcfD3DcB115f62Ae1230802Be2`; `DAO_TREASURY_ADDRESS` = операторська EOA (ВХІД скрипта, не вихід), чотири ENV-адреси продубльовані в `config/deploy.canopy.yml`. ⛔ Amoy-`StateRootAnchor` НЕ є `ETHEREUM_ANCHOR_CONTRACT` (той — Sepolia, [`00_07`](00_07_Action_Plan_Tracker) INF.27). Усі пройшли boot-предикат `EthAddressValidatable.eip55_valid?`.

Живі квитанції broadcast'у 2026-09-01 (`contracts/broadcast/Deploy.s.sol/80002/run-latest.json`,
12 квитанцій, усі `status: 0x1`, `effectiveGasPrice` рівно `0x6fc23ac00` = 30 gwei):

| | Σ лімітів | Σ витрачено | @30 gwei |
|---|---|---|---|
| потрібно на балансі | **16 663 812** | — | **0.49991436 POL** |
| фактично сплачено | — | **12 935 822** | **0.38807466 POL** |

⛔ **«ВИТРАТА фіксована байткодом» хибне рівно ОДНИМ словом: `16 663 812` є сумою ЛІМІТІВ**, тобто
forge-оцінкою з множником ≈1.29 (`used/limit` = 0.773–0.823 поконтрактно, загальний 1.2882) — не
витратою. 🔴 **А ось «не фіксована» було МОЇМ спростуванням, і воно НЕВАЛІДНЕ — знято 2026-09-01
тим самим днем.** Я вказав на dry-run із `16 215 803` як на контрприклад; насправді той прогін ішов
під **`FOUNDRY_PROFILE=production`** (`optimizer_runs` 1000 ⊥ 200, `via_ir` true ⊥ false), тобто мав
ІНШИЙ БАЙТКОД. Пʼять like-for-like прогонів плюс обидва broadcast'и дають рівно `16 663 812`, а хеші
init-коду в них тотожні. **Газ таки є властивістю байткоду — я скасував правду.**
🔑 **І під хибним спростуванням лежала СПРАВЖНЯ знахідка, гостріша за нього: байткод фіксований
ПРОФІЛЕМ, а профіль у рунбуці не запінений.** Команда вище профіль не задає, тоді як докстрінг
самого скрипта (`contracts/script/Deploy.s.sol`) документує `FOUNDRY_PROFILE=production forge script …`
як штатну форму — тобто оператор, що піде за докстрінгом контракту, задеплоїть **не той байткод**,
що зараз живий на Amoy, і не ту вимогу до балансу (`16 215 803` ⊥ `16 663 812`).
🔑 **Чому вимогою є саме Σ ЛІМІТІВ — і механізм тут НЕ той, що напрошується.** Пер-кадрова перевірка
EVM (`gasLimit × gasPrice + value ≤ balance`) дала б лише ПІК одного кадру: `12 962 588` = **0.3889 POL**.
Σ лімітів стає вимогою тому, що `forge` без `--slow` кладе всі 12 кадрів у мемпул ОДРАЗУ, а txpool
перевіряє **сукупну** вартість pending-черги акаунта. ⊕ **Отже `--slow` є важелем: він знижує вимогу
до балансу з 0.4999 до ≈0.389 POL** ціною послідовного майнінгу.
🔑 Кран Chainlink: **Дискримінатор не «який кран», а «чи тримаємо ми будь-що на будь-якому мейннеті»: одна купівля відчиняє кілька каналів одразу й назавжди. ⚠️ І кулдаун крана Chainlink **ГЛОБАЛЬНИЙ на акаунт, не per-network** (виміряно: після POL той самий акаунт дістав `rate limit 24 hours` на Sepolia) — тобто нативний дрип там один на добу, попри те що UI показує мережі окремо. 🔑 **Форма запиту: перевірка LINK іде проти ПІДКЛЮЧЕНОГО гаманця, а адреса призначення — окреме поле**, тож наступні дрипи цілити ОДРАЗУ в деплоєра, і переказ із гаманця не потрібен узагалі.

🔴 **ЗАПАС НАЗВАТИ ОБОВʼЯЗКОВО, бо його практично немає, і мовчання тут коштує дорожче за
перебільшення.** Стеля одного заходу крана Chainlink — `0.50000000`; вимога Σ лімітів @30 gwei —
`0.49991436`; **запас = `0.00008564` POL, тобто 0.017%.** Тобто «одного заходу крана вистачає» —
правда з точністю до сотих часток відсотка, і будь-яка зміна байткоду (профіль! див. вище) або
полиці ціни її ламає. ⚠️ Ціна ж рухається незалежно: `forge` того дня оцінював **48.24 gwei**,
`cast gas-price` давав 30.00, 44.10 і 130.25 у різні години. ⚠️ Формулювання «без піна кран не
покриває фазу ВЗАГАЛІ» було перебільшенням — за реальною витратою @48 gwei вийшло б ≈0.62 POL проти
0.6 доступних (0.5 з одного заходу Chainlink + 0.1/добу з офіційного крана Polygon — ⚠️ це виведення
стояло в попередній редакції абзацу й було зрізане разом із нею, лишивши число без джерела); бракує 0.02, тобто ще одного заходу, **а не хвилини: кулдаун крана Chainlink
глобальний на акаунт і становить 24 години**. ⚠️ І не бери одну цифру ціни:
того ж дня `eth_maxPriorityFeePerGas` віддавав **200 gwei**, а `cast gas-price` напередодні —
30.00 і 44.10. 🔑 **Чому пін при цьому безпечний, і це вимір, а не оптимізм:** вісім блоків Amoy
поспіль заповнені на **0.00–0.19%** (максимум 266 850 газу при ліміті 140 000 000), тобто
priority fee тут є перевіркою ПОЛИЦІ, а не аукціоном — 200–300 gwei платять боти в порожні
блоки, за місце ніхто не конкурує. ⛔ Пін робить вартість детермінованою, не транзакцію
гарантованою: якщо мережа підніме саму полицю вище за пін, кадри просто не змайняться.
⊕ **Sepolia-нога дешева й у бюджет влазить із запасом ×15** (`0.0330 ETH` проти 0.5 з крана),
але вона деплоїть УСІ ШІСТЬ контрактів, тоді як бекенд читає звідти рівно один КОНТРАКТ — ⚠️ **але СПОЖИВАЧІВ у нього ДВА, і другий тихий**
— `ETHEREUM_ANCHOR_CONTRACT` читають `Ethereum::StateAnchorService` (гучно: `ENV.fetch` віддає
плейсхолдер-РЯДОК успішно, а падає вже `Eth::Address` із `CheckSumError`) **і** `Mrv::LineageReportService`
(**тихо**: `ENV[...]` без дефолту, і значення їде прямо в ключ `anchor_contract` MRV-lineage звіту —
доказової поверхні ISO 14064/Verra). ⛔ **Тобто це дослівно клас `SILENT_ADDRESS_ENVS`, і змінної в
гарді НЕМА** — розбір і чому наявна loudness-модель його не виражає (одна змінна = одна історія
гучності, тож гучний сайт «покриває» тихий) → [`00_07`](00_07_Action_Plan_Tracker) `INF.27`.
`Deploy.s.sol` гілок по чейнах не має. Сьогодні це не блокер, а надлишок; ставатиме питанням,
якщо Sepolia-газ подорожчає.
🔴 **Форма команди виміряна прогоном 2026-08-31, бо доти рядок був невиконуваний ОБОМА
прочитаннями.** Тут стояло `forge script contracts/script/Deploy.s.sol --broadcast`: із
`contracts/` це віддає `Error: contract source info format must be '<path>:<contractname>'`
(такого шляху там немає — `foundry.toml` живе В `contracts/` і має `script = "script"`), а з
кореня репо немає ані `foundry.toml`, ані ремапінгів на `node_modules/@openzeppelin`. Правильна
форма компілюється й падає рівно там, де має: `vm.envAddress: "ADMIN_ADDRESS" not found`.
⊕ **`--rpc-url` теж бракувало, і мовчки:** без нього `forge script --broadcast` іде на
`http://localhost:8545`, а `[rpc_endpoints]` у `contracts/foundry.toml` немає — тобто «на Amoy +
Sepolia» жило в прозі й не жило в команді. URL беруться з тих самих testnet-RPC, що поїдуть у
`.kamal/secrets.canopy` ([`INF.27`](00_07_Action_Plan_Tracker)). ⚠️
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
це було неправдою про власний рунбук — гард судить адреси там, де їх ЧИТАЮТЬ (presence і формат
однаково, по-змінному через три класи процесів з 2026-09-02, [`00_07`](00_07_Action_Plan_Tracker) `INF.27` Q3), а web читає SCC-адресу,
тож її плейсхолдер валить бут web-контейнера — тобто першого рендера цієї ж Фази 3. Тобто Фаза 3 без
адрес не піднімається взагалі, а з mainnet-адресами вона перестала б бути стейджингом:
[`00_03 §3.3`](00_03_TRL_Matrix_HIL_and_Beyond) робить реальний testnet-пайплайн умовою
Software TRL 7-8, а mainnet — питанням TRL 9. Порядок несучий в обидва боки.

**Фаза 2 — MAINNET-контракти (до першого mint; передує production-рендеру Фази 5):**
fund deployer wallet → export 6 ENV (`DEPLOYER_PRIVATE_KEY`/`ADMIN_ADDRESS`/`MINTER_ORACLE`/`SLASHER_ORACLE`/`ANCHOR_ORACLE`/`DAO_TREASURY_ADDRESS`) + `REQUIRE_SAFE_ADMIN=true` (mainnet-гейти: ADMIN+TREASURY = Safe-контракти, `MINTER != SLASHER` E.2) →
`cd contracts && forge script script/Deploy.s.sol --rpc-url "$POLYGON_RPC_URL" --broadcast --verify`
(**ТА САМА виправлена форма, що у Фазі 2t** — шлях відносно `contracts/`, `--rpc-url` явно;
`--verify` додатково потребує `ETHERSCAN_API_KEY` у середовищі, бо `[etherscan]`-блоку в
`contracts/foundry.toml` немає) ·
(ordered SCC→SFC→Anchor→Timelock→Governor→ProtocolParameters — [`05_03`](05_03_Tokenomics_SCC_and_SFC)) →
зібрати 9 адрес → вписати у `config/deploy.yml` env.clear (INF.12) → redeploy job.
(`WEB3_CHAIN_ENV` у базовому манифесті лишається `mainnet` — це і є та вісь, яку testnet-слот
перевизначає, і жодна з двох сторін не «вимикає» гард: обидві є твердженнями.)

**Фаза 3 — ПЕРШИЙ деплой = CANOPY (Kamal/GCP), і лише потім production** (founder 2026-07-04
про принцип; ціль переспецифіковано [`OPS.37`](00_07_Action_Plan_Tracker) 2026-08-29):
✅ **Canopy оголошено TESTNET-слотом 2026-09-02** — усі пʼять рухів [`INF.27`](00_07_Action_Plan_Tracker) у дереві: `WEB3_CHAIN_ENV: testnet`
+ чотири Amoy-адреси в `config/deploy.canopy.yml`, RPC-квартет ремаплено з `CANOPY_*`-двійників
(`.kamal/secrets.canopy`, гейт B4), дзеркало в кроці `Kamal Deploy to Canopy` і в `BOOT_CRITICAL`. Поки
двійники не заведені в GitHub Secrets, `Deploy · Canopy` скіпає чисто — це fail-safe, не збій.
✅ **Двійники заведено і перший бут canopy ВІДБУВСЯ 2026-09-02 06:16Z** (`workflow_dispatch`, `First web
container is healthy`, 286 с): гард прийняв testnet+Amoy. ⚠️ Але «healthy» = `/up`, і за ним стояли три
дефекти, невидимі жодному гейту: bash-дефолт у `.kamal/secrets*`, який Dotenv Kamal'а калічив у
`<value>:-…}` (Redis · чотири RPC · `RAILS_MASTER_KEY`; форма й носій — [`06_04 §1.1`](06_04_Secrets_Checklist)),
порожні cache/cable-бази (крок 7 Pre-Flight + [`06_06 §5.6`](06_06_Disaster_Recovery_and_Backup)) і `521` від анкера
без HAProxy (крок 10). Стан → [`DEPLOY-1`](00_07_Action_Plan_Tracker).
🔑 **ДВІ передумови цієї команди жили лише в артефактах, а не тут — і обидві мовчазні:**
```bash
git status --porcelain    # МУСИТЬ бути порожньо: .kamal/hooks/pre-build — крок ЗЕРО
                          # `kamal deploy` — abort'ить «Git checkout is not clean»
export CANOPY_REDIS_URL=rediss://…   # .kamal/secrets.canopy ремапить у REDIS_URL
export GCP_ARTIFACT_REGISTRY_KEY=$(gcloud auth print-access-token)   # ~60 хв життя
```
⚠️ **`CANOPY_REDIS_URL` — не оздоба:** без нього overlay віддає гучний плейсхолдер, тобто
canopy сідає на невалідний Redis. Гучним він є для КОНТЕЙНЕРА (Redis-клієнт падає, `/ready`
503-ить), але дефолтний `proxy.healthcheck` — це `/up`, який Redis не чіпає, тож **сам деплой
лишається зеленим** — рівно доти, доки слот не фліпнуто на `/ready`: canopy фліпнуто 2026-09-02 (Фаза 5),
тож там плейсхолдер тепер валить і сам деплой; production — після ВЛАСНОГО першого деплою.
⚠️ **AR-токен живе ~годину, а `builder.arch: amd64` на arm64-машині означає ЕМУЛЯЦІЮ** — на
довгій збірці токен може протухнути ВСЕРЕДИНІ одного `kamal deploy`; тоді перевидати й
повторити (це не збій конфігу).

`kamal deploy -d canopy` на app-хост → ізольований DB-set `silken_net_canopy` (INF.16) →
`gcloud compute instances add-metadata silken-net-ingress --metadata app-host-ip=<APP_HOST_IP>`
+ `reset` (Pre-Flight #10). Принцип лишається: найризикованіший шлях не дебютує на production.
⚠️ **Але canopy web-only СТРУКТУРНО** (масив-форма `servers:` у `config/deploy.canopy.yml`,
яку стереже `deploy_secret_scan` інваріант B3), тож фонових джоб у ньому немає — доти їх ніс
окремий `job`-сервіс зовнішньої платформи, і після зрізу воркерів у canopy-леґа немає ніде.
Це не дефект рендера, а **відкрите рішення** — але ⚠️ **вже НЕ симетрична пара, і ПОРЯДОК
зняття ухвалено** (⚖️ founder 2026-09-01, [`00_07`](00_07_Action_Plan_Tracker) OPS.37): спершу
testnet-ключі формою B4, і аж тоді роль `job`; зворотний порядок дав би стейджингу підпис на
mainnet сьогоднішніми спільними ключами. Ціна теперішньої форми виміряна й вона не «половина»:
мертві **60 воркерів і 22 cron-задачі**, серед них dead-man switch Королев, sweep застряглих
коштів, actuator-safety і treasury-monitor. ⛔ Найнезворотніше — `PartitionMaintenanceWorker`:
без нього canopy МОВЧКИ накопичує заселений `_default`, який назавжди блокує партицію свого
місяця ([`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup)), і побачити це нікому — гейджів у
job-процесі там немає. Доти canopy перевіряє web-половину, а Sidekiq дебютує на production —
і це мусить бути сказано вголос, бо «canopy зелений» інакше читається як перевірка всієї системи.

**Фаза 4 — Верифікація (єдиний post-deploy список):**
🌲 **Приймальний рядок інтейку — `Listening on coap://0.0.0.0:5683` у логах демона**
(`docker logs silkennet-coap` на анкері). Коли він зʼявився — **ліс може говорити.**
⚠️ Це НЕ дублює `coap_smoke` нижче, а передує йому: рядок каже, що сокет піднято, smoke —
що байти правильні; демон із неповним `coap.env` мовчить, а `systemctl status` рапортує
активність через `Restart=always`. Далі —
`db:prepare` пройшов усі 3 бази І три схеми — `SolidCache::Entry.table_exists?` + `SolidCable::Message.table_exists?`
через runner (INF.16; ⚠️ 2026-09-02 `db:prepare` був «зелений» на ПОРОЖНІХ cache/cable: у `:sql`-форматі він вантажить
`db/{cache,cable}_structure.sql`, яких у репо не було; ✅ 2026-09-02 після дропу трьох баз холодний шлях пройшов повністю — `Created database` ×3, сід до кінця, кеш-таблиця жива) · `curl https://silkennet.app/up` → 200 +
`/ready` → 200 (DB+Redis+Kredis) · `coap_smoke` зелений + задати repo Variables
`CANOPY_COAP_HOST`/`PRODUCTION_COAP_HOST` (INF.6) · метрики: 3 process-таргети живі,
job-серії ≠ 0 (S2.4/INF.14) · Grafana-сесія: `deploy/grafana/import.rb` (dashboards+alerts+contact point)
+ contact point (S2.4 — дашборд і правила вже в стеку з 2026-08-29, лишився КАНАЛ). 🔑 **`import.rb` бере ІНШИЙ креденшел, ніж Alloy, і Фаза −1 називала лише Alloyʼвий:** `GRAFANA_REMOTE_WRITE_{URL,USERNAME,TOKEN}` — це push метрик, а скрипт ходить в **адмін-API** й hard-fail'ить без `GRAFANA_URL` + `GRAFANA_API_TOKEN` (service-account, роль Editor+). ⚠️ І дзеркально: `ALERT_CONTACT_EMAIL` / `ALERT_CONTACT_TELEGRAM_{TOKEN,CHATID}` — **off-by-default**, тож без них скрипт contact point просто ПРОПУСКАЄ, лишаючись зеленим. Верифікаційний крок, який не може провалитись, верифікацією не є: якщо канал уже задротований (08-30), пінь його ЧИТАННЯМ (`--verify`), а не мовчазним успіхом імпорту · `/sidekiq` під admin-сесією → 200, під анонімом → 404
(ARCH.61 route-constraint — ops-інструмент DeadSet-runbook'ів живий і закритий) ·
Puma dual-stack (PUMA-IPV6-1) — `kamal app exec -i "curl -sf -o /dev/null -w '%{http_code}\n' http://[::1]:3000/up"` → `200`. 🔴 **Тут стояло `ss -tlnp | grep 3000`, і жодне з трьох прочитань кроку не виконується (виміряно 2026-08-31):** на машині оператора `ss` немає (Linux-утиліта), на app-хості порт 3000 не опублікований (ролі мають `network-alias`, не `publish` — див. §Kamal), а в контейнері `ss` не встановлений (`Dockerfile` ставить рівно `curl libjemalloc2 libvips postgresql-client`; `iproute2` немає). ⚠️ ОЧІКУВАНЕ значення при цьому чинне й переміряне проти самого гема: `puma-8.0.2` `Configuration.default_tcp_host` = `ipv6_interface_available? ? '::' : '0.0.0.0'` — тобто `[::]:3000` правдиве, зламана була лише проба. `curl` тут і є доказом: відповідь на **IPv6-loopback** можлива лише при bind на `::`, а `/up` виключений з `force_ssl`-редиректу й з `host_authorization` (`probe_paths`, `production.rb`), тож 200 не маскується ані 301, ані 403. Без будь-яких пакетів той самий факт дає `kamal app exec -i "grep -i ':0BB8 ' /proc/net/tcp6"` · money fail-closed
(INF.11) · Sentry release (S5.2) · **mailer = reset-лінк реально долітає й не 403-иться** (хост у тілі листа = `APP_HOST` → web-хост, домен резолвиться, `RAILS_ALLOWED_HOSTS` пропускає — ex-INF.25/INF.13 §🗄️; ⚠️ canopy пошту скіпає свідомо, `SILKENNET_SKIP_MAIL_TRANSPORT_CHECK=1`, тож ця перевірка = PRODUCTION) · `DB_POOL` job-ролі (лише там, на canopy job-ролі нема) · entrypoint fail-loud (✅ canopy 2026-09-02: контейнер вийшов під `-e` на впалому сіді — так і знайдено неатомарність `db:prepare`, [`06_06 §5.6`](06_06_Disaster_Recovery_and_Backup)) · гаманці з газом
(Pre-Flight #3).

**Фаза 5 — Production-render + hardening:**
⏱️ [INF.22] Перший release-run **зависне ~10 хв PENDING ×2** (environment wait-timer,
per-job: перед `verify-secrets` і перед `deploy`) — це НЕ зависання, НЕ скасовуй run;
вікно = навмисний solo-approval-substitute ([`06_04 §1`](06_04_Secrets_Checklist)).
`kamal deploy` production → повтор Фази 4 → `RAILS_ALLOWED_HOSTS=
silkennet.app,canopy.silkennet.app,api.silkennet.com` у env.clear (S6.18 — ТРИ легітимні
хости: app = Cloudflare-HTTPS, canopy = стейджинговий рендер того самого шляху,
api = анкор-шлях). 🔴 **Канон-пара тут була ДВОМА хостами до 2026-08-31, і третій бракував
саме той, що вже живий:** canopy успадковує `env.clear` бази (destination deep_merge = keys-UNION),
`config.hosts` матчить рядок БЕЗ провідної крапки як ТОЧНУ рівність
(`ActionDispatch::HostAuthorization::Permissions#sanitize_string` → `/\A<host>(?::\d+)?\z/i`),
тож `canopy.silkennet.app` ∉ пари ⇒ **403 «Blocked hosts» на КОЖЕН запит canopy** із
наступного ж безперервного деплою — і мовчки, бо `/up`/`/ready` виключені з
`host_authorization`, тож healthcheck лишається зеленим і деплой рапортує успіх.
⊕ Легальна альтернатива, якщо слотів побільшає: провідна крапка `.silkennet.app` покриває
І apex, І один рівень піддомену (субдоменна група в тому регексі опційна) — але вона
ліцензує будь-який майбутній піддомен мовчки, тож поіменний перелік обрано свідомо → [INF.10] фліп `proxy.healthcheck.path: /ready` ✅ canopy фліпнуто 2026-09-02 (передумова `/ready→200` виміряна крізь CF); production — після власного першого деплою.
у `config/deploy.yml` **І** `config/deploy.canopy.yml` — підблок виписаний байтами в ОБОХ,
бо крос-реф не можна розкоментувати, — і КОЖЕН слот фліпається ЛИШЕ після ВЛАСНОГО
`/ready`→200, тобто canopy раніше за production — він деплоїться Фазою 3
(на холодному старті /ready 503-ить →
kamal-proxy довбе до deploy_timeout → rollback; дефолт /up прощає bring-up; повільний
cold-start → підняти deploy_timeout; проба = ReadinessController, [`06_05`](06_05_Puma_Configuration)) →
CSP burn-in 1-2 тижні → `CSP_ENFORCE=true`.

**Фаза 6 — Залізо (Pre-Flight #4/#5):**
антена ДО живлення · AES-парність Soldier↔Queen побітово · прошивка Queens
(`COAP_SERVER_HOST=api.silkennet.com`) · перший boundary-smoke з Queen/`bin/forest_simulator`.

**💰 Фаза ∅ — ЗУПИНКА між сесіями верифікації (⚖️ founder 2026-08-31):**
Pre-fleet стек не має обовʼязку бути піднятим: Фази 3-5 доводять ШЛЯХ, а не обслуговують
трафік, тож репетиція є **подією, а не станом**. Зупинка знімає компʼют і НЕ втрачає нічого —
дані, бекапи й `deletion_protection` лишаються (~$106/міс → ~$20: диски, IP, KMS, AR).

```bash
# у terraform/posture.auto.tfvars — і саме ТАМ, не кліком у консолі:
#   db_activation_policy   = "NEVER"       # Cloud SQL: компʼют не тарифікується
#   compute_desired_status = "TERMINATED"  # обидві VM: vCPU/RAM не тарифікуються
terraform apply    # підняття назад — ті самі два значення в ALWAYS/RUNNING
```

⛔ **Не зупиняти через `gcloud`/консоль.** Обидва поля в схемі провайдера `optional` і НЕ
`computed`, тож позаоблікова зупинка ризикує читатись як ДРЕЙФ, а `Ops · TF Drift` робить
weekly `plan` із рефрешем — джоба стала б щотижня червоною, тобто рівно тим гейтом, який
привчають гортати ([`00_07`](00_07_Action_Plan_Tracker) INF.22 відхилив цю форму поіменно).
Через змінну зупинка є **записаним рішенням**, і CI бачить її разом із тобою — файл
комічений саме для цього.
⚠️ Зупинка **подорожчує** статичну IP: зарезервована й невживана коштує вдвічі за вживану
($0.010 проти $0.005/год). Різниця мала, але це та сама вісь, якою економія тихо зʼїдається.
⚠️ Анкер зупиняється разом з усім — тобто CoAP-інтейк мовчить; до Фази 6 це безкоштовно, після
неї подумай двічі.

---

## 🌐 Масштабування до Планетарного Рівня — CoAP/UDP та Ingress

> Цей розділ описує архітектурні ризики та рекомендації для переходу від сотень до **мільйонів** вузлів. Поточна архітектура (CoAP прямо в Rails) є коректною для TRL 5–6, але потребує еволюції перед Series D.

### ✅ Ризик-1 & Ризик-2 — Conntrack + UDP Rate Limiting (Виправлено)

Обидва ризики вирішені в `terraform/compute.tf` (`startup-script` Ingress Anchor):
- **conntrack**: `nf_conntrack_max=2000000`, `nf_conntrack_udp_timeout=30s` — 2M entries замість 65K дефолт. ⚠️ `nf_conntrack` — МОДУЛЬ: на свіжому буті він ще не завантажений, `sysctl` на відсутньому ключі виходить 1, і під `set -e` скрипт помирає на першому рядку (виміряно 2026-08-31/09-02) → `modprobe nf_conntrack` + `/etc/modules-load.d/` стоять ПЕРЕД sysctl.
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

> **One-home:** повний інвентар Web3/мультичейн ENV — secret + clear, RPC (`ALCHEMY_*` + окремий `CELO_RPC_URL`), контракт-адреси (post-`forge deploy` placeholders), Solana/Chainlink, Active-Storage `aws`/`gcs` + credentials-only ключі (peaq/iotex/streamr/the_graph/hadron/filecoin) — живе в [`06_04 §2.1`](06_04_Secrets_Checklist) (+ §2.2 credentials), НЕ дублюється тут. ⚠️ `CELO_RPC_URL` **обовʼязковий, фолбека немає** — порожній дає `KeyError` на кожному Celo-виклику (E.49, ⚖️ 2026-08-31); контракт-адреси відомі лише після `forge deploy`.

### Деплой контрактів (Foundry)

```bash
# Встановіть Foundry (https://book.getfoundry.sh/)
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

> **Канонічний деплой — `contracts/script/Deploy.s.sol`** (усі 6 контрактів у правильному порядку SCC→SFC→StateRootAnchor→Timelock→Governor→ProtocolParameters + Gnosis-Safe admin guard `REQUIRE_SAFE_ADMIN`). Точні команди (`forge script … --broadcast --verify`) та ENV — [`05_03`](05_03_Tokenomics_SCC_and_SFC) (§Smart Contract Audit Roadmap). **НЕ** деплоїти контракти поштучно через `forge create` — це пропускає admin-setup, ordered dependencies й 4 з 6 контрактів.
