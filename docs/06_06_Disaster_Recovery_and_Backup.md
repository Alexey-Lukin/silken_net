# 06_06: Disaster Recovery & Backup

## 🎯 Мета

Зафіксувати backup-постуру SilkenNet, цілі відновлення (RTO/RPO) та **restore-runbook'и** для кожного класу втрати: пошкодження даних, втрата інстансу/регіону, втрата Terraform-state, втрата незамінних master-ключів. Документ — SSOT для DR-аудиту перед mainnet.

> **Принцип:** бекап, який ніколи не відновлювали в навчанні — це **не бекап**. Кожен runbook нижче має бути проганяний у DR-drill (див. §6).

---

## ✅ Статус

- **Поточний TRL:** TRL 5 — backup-конфіг IaC присутній і ввімкнений (Cloud SQL PITR + deletion_protection; **HA — `REGIONAL` у дефолті, але чинний деплой `ZONAL` оверрайдом**, §нижче), §5.1 + половина §5.2 прогнані в першому drill 2026-09-02 (RTO 11:00 на staging — §6), master-key backup — операційна задача.
- **Відкрите:** квартальний ритм drill (наступний — з §5.2 у повній формі) + master-key backup **половинчастий**: `PROVISIONING_MASTER_KEY` + AR-трійка у vault + offline з 2026-09-01, `RAILS_MASTER_KEY` — нуль копій поза GitHub Secrets і однією машиною (§Gaps) → [`00_07`](00_07_Action_Plan_Tracker) (DR.1, S5.6).

---

## 🔗 Cross-references

| Ресурс | Зв'язок |
|---|---|
| `terraform/database.tf` | Cloud SQL backup + read replica (SSOT). ⚠️ HA-вісь читається НЕ звідси: `availability_type` оверрайднуто в **коміченому** `terraform/posture.auto.tfvars` (⚠️ НЕ в gitignored `terraform.tfvars` — той несе рівно три ключі: `project_id`·`billing_account_id`·`db_password`; врізка §2) |
| `terraform/main.tf` | GCS state backend (`silken-net-terraform-state`) |
| [`06_01` — Deployment Kamal Terraform](06_01_Deployment_Kamal_Terraform) | `terraform apply`, Ingress Anchor, deploy-flow |
| [`06_04` — Secrets Checklist](06_04_Secrets_Checklist) | master-ключі, ротація (§5.2), revocation (§5.4) |
| [`06_08` — Resilience and Failover Policy](06_08_Resilience_and_Failover_Policy) | runtime failover (не backup) |
| [`00_07` — Action Plan Tracker](00_07_Action_Plan_Tracker) | DR.1 (drill + master-key backup), S5.6 |

## 📑 Зміст

<!-- TOC:AUTO:START -->
- [Gaps (→ 00_07)](#-gaps--00_07)
- [1. Інвентар: що захищаємо](#1-інвентар-що-захищаємо)
- [2. Cloud SQL — backup + HA (фактична конфігурація)](#2-cloud-sql--backup--ha-фактична-конфігурація)
- [3. RTO / RPO targets](#3-rto--rpo-targets)
- [4. Незамінні master-ключі (НЕ в Cloud SQL backup!)](#4-незамінні-master-ключі-не-в-cloud-sql-backup)
- [5. Restore Runbooks](#5-restore-runbooks)
- [6. DR Drill (👤, DR.1 — обов'язково перед mainnet)](#6-dr-drill--dr1--обовязково-перед-mainnet)
<!-- TOC:AUTO:END -->

---

## 🛑 Gaps (→ 00_07)

- 🟡 **DR-drill прогнано ОДИН раз** (2026-09-02, staging — §6): §5.1 верифіковано реальним PITR-клоном, §5.2 — лише половиною «витягти версію» (без `terraform apply` з неї), §5.3–5.6 не проганялися. Ритм квартальний. `DR.1`.
- 🟡 **Master-key backup — операційна задача, і вона ПОЛОВИНЧАСТА з 2026-09-01.** ✅ `PROVISIONING_MASTER_KEY` **та AR-encryption трійка** — у vault + offline (згенеровані того дня; кожен пройшов `EncryptionKeyGuard`+`WeakKeyDetector` ДО заведення, тобто перевірку зроблено НА ГЕНЕРАЦІЇ, а не на першому буті). 🔴 **`RAILS_MASTER_KEY` — ні, і його стан гірший, ніж читається поруч із закритим сусідом:** він живе в GitHub Secrets (значень не віддають) і в `config/master.key` на ОДНІЙ машині, gitignored — офлайн-копії немає ЖОДНОЇ, тож втрата ноутбука робить `credentials.yml.enc` нечитним назавжди. ⚠️ Два ключі різного походження (один згенеровано 09-01, другий живе з першого дня репо), тому «master-ключі збережено» правдиве рівно наполовину — і саме тому вони РОЗВЕДЕНІ. `DR.1`.
- 🟡 **GCS state bucket + versioning** — `S5.6` (chicken-and-egg при першому `terraform init`).

---

## 1. Інвентар: що захищаємо

| Актив | Сховище | Backup-механізм | Втрата = |
|---|---|---|---|
| **PostgreSQL production** (`trees`, `wallets`, `blockchain_transactions`, `telemetry_logs`-партиції) | Cloud SQL `silken-db` | PITR + 30×daily snapshot (§2) | 🔴 Критично — але **канонічний баланс токенів живе on-chain** (Polygon), БД — проєкція |
| Solid **Cache/Cable** БД (`*_cache/_cable` — Solid Queue pruned, INF.18) | Cloud SQL (той самий інстанс) | той самий backup | 🟢 Низько — регенеровні (cache transient, cable ephemeral; черги живуть у Redis — рядок нижче) |
| **Terraform state** | GCS `silken-net-terraform-state` (CMEK `silken-tfstate-ew1`, [SEC.22] → [`06_04 §5.6`](06_04_Secrets_Checklist)) | bucket versioning, 10 версій/30д (`S5.6`) | 🟡 Високо — infra drift/lock; відновлюється з версій (усі noncurrent = plaintext-копії секретів, тому retention свідомо короткий) |
| **`RAILS_MASTER_KEY`** (`config/master.key`) | git-ignored + GitHub Secrets · ⛔ **vault-копії НЕМАЄ** (станом на 2026-09-01) | ручний (password manager) — **не виконано** | 🔴 **Незамінний** — `credentials.yml.enc` без нього не розшифрувати, а GitHub значень назад не віддає |
| **AR-encryption трійка** (`ACTIVE_RECORD_ENCRYPTION_*`) | ENV + vault + offline ✅ 2026-09-01 | ручний (password manager) | 🔴 **Незамінна третім класом** — без неї `hardware_keys` (device AES / Lorenz-seed) і `users.otp_secret` нечитні назавжди; доти інвентар називав незамінними лише два master-ключі |
| **`PROVISIONING_MASTER_KEY`** | secrets store | ручний | 🔴 **Незамінний** — без нього не деривувати нові per-device ключі (вже прошиті пристрої працюють; нове provisioning — ні) |
| **On-chain state** (SCC/SFC баланси, slashing, anchors) | Polygon / Ethereum L1 | сам блокчейн = immutable backup | 🟢 N/A — мережа є джерелом правди |
| Oracle/anchor private keys, contract addresses | secrets ([`06_04`](06_04_Secrets_Checklist)) | ручний | 🟡 Високо — redeployable, але disruptive (revoke+redeploy) |
| **KMS `anchor-boot` key** (disk-CMEK, [`06_04 §5.6`](06_04_Secrets_Checklist)) | Cloud KMS `silken-disk-ew1` | `prevent_destroy` + 30-day restore-grace; **undeletable** | 🟠 Availability-critical — anchor boot-disk unbootable без key (key-**not**-data → не в backup; сам disk = cattle, rebuild з IaC + operator-injected `coap.env`). ⚠️ snapshot НЕ inherit'ить CMEK → майбутній anchor-snapshot потребує `--kms-key` |
| **KMS `app-boot` key** (disk-CMEK, [`06_04 §5.6`](06_04_Secrets_Checklist)) | Cloud KMS `silken-disk-ew1` | ідентична постанова: `prevent_destroy` + 30-day restore-grace, 90d rotation; **undeletable** | 🔴 Availability-critical **і ставка ВИЩА за anchor-boot**: без ключа не бутиться машина, що тримає money-квінтет at-rest (kamal вивантажує його в `env/roles/job.env` 0600 — [`06_04 §5.6`](06_04_Secrets_Checklist)). Disk = cattle, rebuild з IaC; але доти вся Kamal-половина платформи стоїть, не лише інтейк. Заведено 2026-08-30 разом з app-хостом [OPS.37] |
| **KMS `tfstate` key** (state-bucket CMEK, [SEC.22] → [`06_04 §5.6`](06_04_Secrets_Checklist)) | Cloud KMS `silken-tfstate-ew1` (bootstrap-owned, поза terraform) | KMS-версії undeletable без явного destroy; rotation 90d = нова PRIMARY, старі версії decrypt-capable | 🟠 Availability-critical для infra-ops — ручний destroy key-версії робить state-версії під нею назавжди нечитабельними (recovery = `terraform import` живих ресурсів з нуля, болісно але можливо; дані НЕ втрачаються — лише їх infra-проєкція) |
| **Redis** (Sidekiq queue, Kredis locks, Rack::Attack) | Upstash (managed) | managed durability; **app-tolerant** | 🟢 Низько — jobs re-enqueue, locks re-acquire, rate-limit лічильники не критичні |
| Schema | `db/structure.sql` (git) | git | 🟢 Низько — у репозиторії |

---

## 2. Cloud SQL — backup + HA (фактична конфігурація)

З `terraform/database.tf` + `variables.tf` (defaults):

| Параметр | Значення | DR-роль |
|---|---|---|
| `point_in_time_recovery_enabled` | `true` | Відновлення на будь-яку секунду в межах вікна WAL |
| `transaction_log_retention_days` | `7` **(pre-fleet)** · ціль `30` | Глибина ПОСЕКУНДНОГО PITR. ⚠️ Значення привʼязане до **едиції**, а не до нашої планки: `ENTERPRISE` приймає 1–7 (API: «must be between 1 and 7»), 30 днів існують лише на `ENTERPRISE_PLUS`, що приймає виключно `db-perf-optimized-*` тири (~4× ціна). Едиція підвищується **на місці**, тож ціль не скасована — вона gated. Покриття 30 днів дає рядок нижче й воно НЕ рухається |
| daily backup `start_time` | `03:00` | Щоденний snapshot |
| `retained_backups` | `30` (COUNT) | 30 останніх snapshot'ів |
| `availability_type` | `REGIONAL` (default) | **HA з автоматичним failover** між зонами |
| `deletion_protection` | `true` (default) | 🔴 **Захистів ДВА під одним словом, і цей рядок роками описував лише перший.** (1) мета-аргумент Terraform на `google_sql_database_instance` — спиняє **виключно** `terraform destroy`, про GCP не знає нічого; (2) `settings.deletion_protection_enabled` — API-рівневий прапорець Cloud SQL, і **лише він** спиняє `gcloud sql instances delete`, кнопку в консолі та прямий виклик API. Виміряно на живому інстансі 2026-08-31: другий стояв `false`, тобто база з усіма продовими даними знімалась однією командою при бездоганному першому. Обидва тепер на `var.enable_deletion_protection`. ⊥ **На `google_compute_instance` слово те саме, а механізм ІНШИЙ:** там аргумент мапиться прямо в API, тож один прапорець покриває обидва шляхи — обидві VM теж стояли `false` і тепер закриті. ⚠️ Із Фазою ∅ не конфліктує: та ЗУПИНЯЄ компʼют, не видаляє |
| `read_replica_count` | `0` (default) | Read-репліки вимкнені (увімкнути для read-scaling, не для DR) |
| `disk_autoresize` | `true` | Запобігає full-disk outage |

> **Наслідок (ЦІЛЬ, не чинний деплой — обидві осі оверрайднуті, врізки нижче):** production має zone-failure resilience (REGIONAL auto-failover, ~хвилини) + 30-денне вікно PITR. ⚠️ Застереження «на default-конфігу» тут НЕ рятує: `transaction_log_retention_days` зашито в `database.tf`, тож 7 днів є і дефолтом теж. Read-репліка (`failover_target = false`) — НЕ для DR, лише read-scaling.

> ⚖️ **ЧИННА ЕДИЦІЯ — `ENTERPRISE`, і обіцянка 30 днів НЕ знята, а РОЗВЕДЕНА ЗА ФАЗОЮ** (founder 2026-08-31). Формулювання власника: «на production і canopy якщо буде по-різному, то обіцянку в DR ми не порушимо». ⚠️ Поправка від заліза, без якої це нездійсненне: інстанс Cloud SQL **ОДИН** на обидва слоти (він несе `production` + `canopy` + cache/cable — [`06_01`](06_01_Deployment_Kamal_Terraform)), а `edition`, тир і глибина PITR є властивістю **ІНСТАНСУ**, не бази. Отже «по-різному» досяжне не одночасно, а **в часі**. 🔑 Тому це НЕ пониження планки: `30` лишається ціллю для проду З ДАНИМИ, а `7` є оголошеним pre-fleet-станом при нулі дерев і нулі користувачів. ⛔ **Подія підвищення названа й та сама, що в ZONAL-врізці — перший живий аплінк**: до нього посекундне вікно захищає порожню базу. Хід: `edition = ENTERPRISE_PLUS` + тир `db-perf-optimized-*` (підвищення на місці, з рестартом) → `transaction_log_retention_days = 30` → підняти поріг гейта назад. Стан і виконавець — [`00_07`](00_07_Action_Plan_Tracker) `DR.1`. ⊕ **Що НЕ втрачено вже сьогодні:** `retained_backups = 30` не рухається, тобто 30 днів точок відновлення є; коротшає лише вікно, в якому відновлення посекундне.

> ⚖️ **ЧИННИЙ ДЕПЛОЙ — `ZONAL`, оверрайдом у **комічений** `terraform/posture.auto.tfvars` (founder 2026-08-31).** Дефолт у `variables.tf` лишається `REGIONAL`, тож `database_dr_posture_spec` зелений за побудовою — він судить КОМІЧЕНУ поставу, і сам оголошує оверрайд «an explicit operator act». 🔑 **Розділення, на якому стоїть присуд: `availability_type` купує БЕЗПЕРЕРВНІСТЬ, а не збереження.** Проти ВТРАТИ стоїть `backup_configuration` — PITR, 30-денні транзакційні логи, 30 щоденних бекапів — і жодного з них цей оверрайд не торкається. Підстава: при нулі підключених вузлів і нулі користувачів авто-failover захищає нікого, а коштує ~$115/міс (виміряно проти прайс-листа: REGIONAL подвоює і vCPU/RAM, і диск). ⛔ **Подія повернення названа, і це ПОДІЯ, не дата — перший живий аплінк із реального заліза:** саме тоді простій уперше починає коштувати не нашого часу, а свідчення дерева. Строк тут несучий за тією ж підставою, що й у [`05_03` — Admin-Role Split](05_03_Tokenomics_SCC_and_SFC): право без названого строку повернення перестає бути довіреним ([`00_05 §7`](00_05_AI_Native_Operating_Model), амана). Стан і виконавець — [`00_07`](00_07_Action_Plan_Tracker) `DR.1`.

> **Posture-guard [DR.1]:** `spec/deploy/database_dr_posture_spec.rb` стверджує ці мінімуми (PITR=true · WAL ≥ 7 [pre-fleet-підлога, ціль 30 — див. врізку] · retained ≥ 30 · дефолт `db_availability_type` не-ZONAL) проти `terraform/database.tf` у CI — тихе пониження DR-постури (disable PITR / cut retention / ZONAL) падає до деплою, а не спливає постінцидентно; live-vs-tf дрейф ловить окремий `Ops · TF Drift`.

---

## 3. RTO / RPO targets

| Сценарій | RPO (макс. втрата даних) | RTO (час відновлення) |
|---|---|---|
| Zone failure (1 зона GCP) | 0 | ~хвилини (REGIONAL auto-failover) — ⚠️ **лише за REGIONAL; чинний деплой ZONAL, тож тут RTO = час ручного відновлення з бекапа**, див. врізку нижче |
| Data corruption / bad migration | ≤ 5 хв (PITR WAL) | ≤ 1 год (PITR restore + redeploy) |
| Instance loss | ≤ 5 хв (PITR) | ≤ 1 год |
| Region loss (вся `europe-west1`) | ≤ 24 год (останній snapshot, якщо WAL у тому ж регіоні) | ≤ 4 год (restore у новий регіон + `terraform apply` + redeploy) |
| On-chain token state | 0 (immutable) | N/A |

> Token-баланси завжди відновлювані з блокчейну незалежно від стану БД — backend re-індексує on-chain події. БД-втрата впливає на **телеметрію/аналітику**, не на кошти.

---

## 4. Незамінні master-ключі (НЕ в Cloud SQL backup!)

`RAILS_MASTER_KEY` та `PROVISIONING_MASTER_KEY` **не зберігаються** у жодному автоматичному backup (git-ignored, не в БД). Їх втрата незворотна:

- **`RAILS_MASTER_KEY`** → `config/credentials.yml.enc` (усі Web3-ключі, HMAC-секрети) стає нечитабельним. Recovery: НЕМАЄ — лише повна ротація всіх credentials + re-encrypt.
- **`PROVISIONING_MASTER_KEY`** → HKDF-корінь per-device AES. Втрата: вже прошиті Soldier/Queen працюють (ключі у Flash), але **нове provisioning неможливе** і backend не деривує ключі для replay-перевірки нових пристроїв.

**Процедура (👤, DR.1):** обидва ключі — у password manager / Vault (offline-копія в сейфі для founder-level). Ротація — [`06_04 §5.2`](06_04_Secrets_Checklist).

---

## 5. Restore Runbooks

### 5.1 Point-in-time restore (corruption / bad migration)
```bash
# Відновити у НОВИЙ інстанс на момент ДО інциденту (не перезаписує prod):
gcloud sql instances clone silken-db silken-db-restored \
  --point-in-time '2026-05-29T02:55:00Z'
# Перевірити дані → за потреби оновити `POSTGRES_HOST` (GitHub secret / env.clear) на приватний IP restored-інстансу → redeploy (component style, config/database.yml).
```

### 5.2 Terraform state recovery
```bash
# State у GCS з versioning (S5.6). Відкат до попередньої версії:
# ⚠️ `gcloud storage`, не `gsutil`: під корпоративним TLS-проксі gsutil зависає мовчки (свій CA-стор, drill 2026-09-02)
gcloud storage ls -a 'gs://silken-net-terraform-state/**'   # знайти попередній generation (стан лежить під prefix terraform/state/)
gcloud storage cp 'gs://silken-net-terraform-state/terraform/state/default.tfstate#<GEN>' \
          gs://silken-net-terraform-state/terraform/state/default.tfstate
# Або terraform state pull/push. Lock: terraform force-unlock <LOCK_ID> при stuck lock.
```

### 5.3 Region loss (full rebuild)
1. `terraform apply` у новому регіоні (`var.region`) — підніме Cloud SQL + Ingress Anchor + **app-хост** (`silken-net-app`; без нього крок 4 не має куди їхати — [OPS.37] 2026-08-30).
2. Restore Cloud SQL з backup у новий регіон (`gcloud sql backups restore`).
3. Відновити секрети ([`06_04`](06_04_Secrets_Checklist)) + master-ключі (§4) у CI та `.kamal/secrets-common`.
4. `kamal deploy` (production).
5. Backend re-індексує on-chain стан (баланси самовідновлюються з Polygon).
6. Оновити DNS A-запис → новий `ingress_ip`.

### 5.4 Redis (Upstash) loss
Не потребує restore: Sidekiq jobs re-enqueue з БД-стану, Kredis locks re-acquire, Rack::Attack лічильники скидаються. Достатньо вказати новий `REDIS_URL` + redeploy (Kredis читає його як є — `config/redis/shared.yml`; `KREDIS_REDIS_URL` окремо **не** задавати, перебило б фолбек). ⚠️ Новий інстанс заводь у `europe-west1` — same-region із Cloud SQL є чинною властивістю, і втратити її можна мовчки ([`06_01 §Redis Isolation Strategy`](06_01_Deployment_Kamal_Terraform)).

### 5.5 DEFAULT-партиція заблокувала обслуговування (`PartitionMaintenanceWorker` падає щодня)

**Симптом:** `sn-alert-partition-default-occupied` (`silkennet_partition_default_occupied > 0`) АБО `sn-alert-partition-maintenance-failed` разом із логом «DEFAULT-лист уже тримає рядки цього місяця». У Sentry — `PG::CheckViolation: updated partition constraint for default partition … would be violated by some row`.

🔴 **Ретраї цього НЕ виправляють, і в цьому вся різниця з рештою збоїв воркера.** Щойно в DEFAULT-лист осів рядок місяця N, `CREATE TABLE … PARTITION OF … FOR VALUES` для місяця N падає **назавжди**: нова партиція звузила б constraint DEFAULT-листа, а той уже містить рядок, який туди не влізе. Стан сам не змінюється, тож кожен добовий прогін падає на тому самому місці. **Каскад:** прохід зупиняється на першій проблемній таблиці, отже партиції НАСТУПНОГО місяця для решти таблиць теж не створюються — і наступного місяця вони почнуть писати в свій DEFAULT так само; а `sample_growth_gauges!` стоїть після циклу, тож [`06_03`](06_03_Prometheus_Observability)-гейджі росту ЗАМЕРЗАЮТЬ (їх свіжість стереже `sn-alert-partition-sampler-stale`).

⛔ **Порядок несучий:** створити партицію ДО `DETACH` неможливо — це і є сам дефект.

```sql
-- 1. Які місяці осіли (partition key = created_at). Повторити для кожної
--    таблиці, чий гейдж = 1: telemetry_logs · gateway_telemetry_logs · blockchain_transactions
SELECT date_trunc('month', created_at) AS month, count(*)
FROM telemetry_logs_default GROUP BY 1 ORDER BY 1;

-- 2. Відчепити DEFAULT. ⚠️ Бере ACCESS EXCLUSIVE на БАТЬКА — короткий стоп записів
--    у цю таблицю. На pg17 доступний DETACH ... CONCURRENTLY (не можна в транзакції).
ALTER TABLE telemetry_logs DETACH PARTITION telemetry_logs_default;

-- 3. Створити відсутні місяці — по одному на КОЖЕН рядок кроку 1
CREATE TABLE telemetry_logs_y2026m09 PARTITION OF telemetry_logs
  FOR VALUES FROM ('2026-09-01 00:00:00') TO ('2026-10-01 00:00:00');

-- 4. Перелити й спорожнити відчеплений лист
INSERT INTO telemetry_logs SELECT * FROM telemetry_logs_default;
DELETE FROM telemetry_logs_default;

-- 5. Причепити назад — інакше наступний INSERT поза відомими місяцями впаде
--    з «no partition of relation … found for row»
ALTER TABLE telemetry_logs ATTACH PARTITION telemetry_logs_default DEFAULT;
```

⚠️ **`DELETE` кроку 4 не є порушенням [DOC.8]** ([`04_01 §3`](04_01_Data_Models_and_Entities), картка `TelemetryLog` — «ретеншн робить ВИКЛЮЧНО дроп партицій»): рядки не зникають, вони переїхали на крок раніше, а таблиця на цьому кроці вже **відчеплена** від `telemetry_logs`. Заборона стосується ретеншну за ВІКОМ, а не переливання.

⊕ **Швидший шлях, коли крок 1 дав рівно ОДИН місяць:** відчеплений лист можна не переливати, а перейменувати й причепити як місячну партицію (`ALTER TABLE … RENAME TO telemetry_logs_y2026m09` → `ATTACH PARTITION … FOR VALUES FROM … TO …`), тоді ж створивши новий порожній DEFAULT. Дешевше на великому обсязі; на мішанині місяців незастосовне.

**Профілактика — прилад, а не пильність:** `silkennet_partition_default_occupied` світиться ще ДО того, як настане місяць заблокованої партиції, тобто дає вікно на реакцію. Дім гейджа — [`06_03 §2.8`](06_03_Prometheus_Observability), причина існування — [`00_07`](00_07_Action_Plan_Tracker) ARCH.70.

### 5.6 Напівзасіяний слот після впалого `db:prepare` (create → schema:load → seed НЕ атомарні)

Виміряно на першому буті canopy 2026-09-02: сід упав (порожня cache-база — [`06_01`](06_01_Deployment_Kamal_Terraform) Pre-Flight крок 7), контейнер під `set -e` вийшов, Docker (`unless-stopped`) перезапустив його, і друга спроба застала базу «існуючою» — лише міграції, без сіду й без schema:load: `SystemParameter`=1, `User`=0, kamal-proxy healthy на `/up`. Такий слот ЗАВЖДИ здоровий для healthcheck'а і ніколи не досіється сам.

**Відновлення (staging — canopy):** чесний холодний шлях — скинути ТРИ бази й редеплоїти:

```bash
gcloud compute ssh silken-net-app --tunnel-through-iap --zone europe-west1-d --project silkennet \
  --command 'C=$(sudo docker ps --format "{{.Names}}" | grep web-canopy | head -1); \
             sudo docker exec -e DISABLE_DATABASE_ENVIRONMENT_CHECK=1 "$C" bin/rails db:drop'
gh workflow run deploy.yml        # entrypoint: create → structure.sql ×3 → seed
```

Альтернатива без дропу — `db:schema:load:cache db:schema:load:cable db:seed` у тому ж контейнері (сід починається з Кенозису, тож дані однаково перезаписуються). **Production:** рецепт НЕ застосовний — `db/seeds.rb` там fail-closed, bootstrap = [`OPS.38`](00_07_Action_Plan_Tracker).

---

## 6. DR Drill (👤, DR.1 — обов'язково перед mainnet)

Щоквартально проганяти §5.1 (PITR clone у throwaway-інстанс) + §5.2 (state-version rollback) на staging. Фіксувати фактичні RTO/RPO vs цілі §3. Неперевірений backup = відсутній backup.

**Drill #1 — 2026-09-02, staging (canopy-дані у тому ж `silken-db`):**
- §5.1: `gcloud sql instances clone silken-db silken-db-drill --point-in-time=<now−10 хв>` → операція `CLONE` 15:57:44Z → 16:08:44Z, тобто **RTO 11:00 до `RUNNABLE`** (тир `db-custom-1-3840`, ZONAL) проти цілі §3 «≤ 1 год»; у клоні всі шість баз, парність рядків із живим інстансом точна (`users`/`trees`/`system_parameters` і той самий `max(created_at)`), тобто **RPO на обраній точці = 0**. Клон успадковує `deletionProtectionEnabled=true` — зняття = `patch --no-deletion-protection`, потім `delete` (зроблено того ж вечора; сумарний слід у білінгу ≈ 2 год тиру `db-custom-1-3840`).
- ⚠️ `gcloud sql instances clone` після ~10 хв друкує «**failed** … taking longer than expected» — це клієнтський таймаут, операція живе; вердикт і RTO читай із `gcloud sql operations describe <op>` (`status`/`startTime`/`endTime`), не з CLI.
- §5.2 — половина: versioning увімкнено фактично (десять версій `terraform/state/default.tfstate`), передостання витягується `gcloud storage cp 'gs://…/default.tfstate#<generation>'` і парситься валідним стейтом (`serial`, той самі 58 ресурсів). **Витягти ≠ відкотити:** `terraform apply` із витягнутої версії не проганявся — наступний drill робить його на throwaway-стеку. `gsutil` під корпоративним TLS-проксі зависає (не читає CA-конфіг gcloud) — бери `gcloud storage`.
