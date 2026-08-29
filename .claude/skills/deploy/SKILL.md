---
name: deploy
description: "Use when deploying or operating silken_net infrastructure — Kamal/Terraform GCP, secrets, observability (Grafana Alloy → Grafana Cloud), disaster-recovery, CI/CD, resilience/failover. This is Module 06 'The Matrix'. Routes to the 06_xx canon docs and the load-bearing infra invariants; does not restate them."
---

# Deploy & Infrastructure (Module 06 — The Matrix)

DevOps/Infra шар: Rails на **GCP** (Kamal-деплой УСЕРЕДИНІ VPC; Cloud SQL
private-only, Redis — зовнішній **Upstash** Serverless TLS). IaC через
**Terraform**, спостережуваність через **Grafana Alloy → Grafana Cloud**.
⚠️ **Akash-платформу зрізано 2026-08-29 (`OPS.37`) з усіх поверхонь — акаунта
не існувало, деплою на неї не було НІКОЛИ.**

## Канон — читати ПЕРЕД зміною інфри/секретів/метрик

SSOT One-Home: цей skill лише **маршрутизує**; факти живуть у `docs/` + config-SSOT.
Не дублюй сюди значення/інвентар і **не хардкодь `file:line`** (дрейфує — стале вже за
комітом). Посилайся на стабільні якорі: канон-§ + імена символів/шляхів.

| Що треба | Канон-дім |
|---|---|
| Деплой **Kamal + Terraform GCP**, Canopy vs Production | `06_01` ← read-first для деплою |
| **Observability** — метрики / Alloy → Grafana Cloud / alerting | `06_03` (реєстр метрик — `06_03 §2.8`) |
| **Секрети** — інвентар + checklist (GitHub / Kamal / Terraform) | `06_04` (canonical = `config/deploy.yml env.secret`) |
| **Puma 8** config + cluster hooks + runbook'и | `06_05` |
| **Disaster Recovery** / backup / RTO-RPO / master-key | `06_06` (config SSOT = `terraform/database.tf`) |
| **CI/CD** workflows + єдиний operations runbook-індекс | `06_07` |
| **Resilience** — Queen failover (4 рівні) + Per-Chain Fallback Matrix + **топологія черг Sidekiq** (`§2.5` — anti-starvation через ізоляцію ПРОЦЕСІВ, не перестановку черг; flip = `sidekiq -q`-прапори в deploy-конфізі, тобто deploy-рішення, НЕ код) | `06_08` |

## Несучі інваріанти (не очевидні з коду)

Будь-хто, хто чіпає деплой, МУСИТЬ це знати (суть тут, механіка — за canon-§):

- **CoAP-інтейк: PRIMARY = демон на Ingress Anchor** (docker+systemd, приватний IP Cloud SQL
  БЕЗ Auth Proxy; секрети `/etc/silkennet/coap.env`, НЕ metadata). Kamal `coap`-роль
  (`config/deploy.yml`) = дормантний **fallback** (перемикання 2×systemctl); money/web
  лишаються на Kamal/GCP. **coap.env** = окрема boot-contract поверхня (pure UDP glue,
  нуль key-derivation → несе AR-encryption-трійку, **НЕ** `PROVISIONING_MASTER_KEY`;
  guard `spec/deploy/anchor_coap_env_spec.rb`). → `06_01` / `06_04 §5.7`.
- **Cloud SQL Auth Proxy авторизує через Google API — це ОРТОГОНАЛЬНО мережевій
  досяжності, не заміняє її.** Обидва інстанси `terraform/database.tf` тепер
  `ipv4_enabled = false` (private-only). Kamal деплоїть УСЕРЕДИНІ GCP VPC, тож
  з'єднання йде на **приватний IP напряму**, без проксі. Сам `cloud-sql-proxy`
  знято з рантайму (`Dockerfile` + `bin/docker-entrypoint`, `OPS.37`) — сьогодні
  він лишається лише **break-glass**-інструментом із робочої станції (👤;
  IAM-авторизація й мережева досяжність там — досі дві окремі речі).
  → `terraform/database.tf` at-use.
- **Observability = Alloy → Grafana Cloud SaaS; self-hosted Prometheus НЕ потрібен (OBS.1).**
  Реєстр **in-process** → web:80 НЕ бачить job/coap-інкрементів напряму → Alloy МУСИТЬ
  скрейпити **три таргети, по одному на процес** (web/job/coap, лейбл `process`) — цей
  КОНТРАКТ незмінний і далі так. ⚠️ **Post-`OPS.37` АДРЕСИ до них — ВІДКРИТЕ питання, не
  факт**: Kamal 2.12 не дає sibling-контейнеру стабільної адреси (версійовані імена, без
  network-аліасу), а host-loopback `options.publish` (форма в `config.alloy` сьогодні —
  ЛИШЕ ШЕЙП, не рішення) ламає роллінг-деплой (виміряно й відкочено 2026-08-29); альтернатива
  (`discovery.docker` по мітках) вимагає docker-socket = root-еквівалентний грант. Дім
  рішення → `00_07` (нога `OPS.37`); `spec/deploy/alloy_scrape_topology_spec.rb` пінить
  сьогодні лише КОНТРАКТ (3 різні адреси, мітки `web`/`job`/`coap`), не самі адреси.
  Топологія/стелі → `06_03 §2.9`; реєстр+кількість метрик → `06_03 §2.8` (**не хардкодь**).
- 🔴 **Що метрика ОЗНАЧАЄ, вирішує її СПОЖИВАЧ, а не докстрінг** (INF.26, 2026-08-13).
  Питання «`by:` чи голий `.increment`» нерозвʼязне з коду й розвʼязне з панелі: `SCC_MINTED_TOTAL`
  і `SCC_SLASHED_TOTAL` живуть на ОДНІЙ панелі «SCC Minted vs Slashed», на одній осі — тож
  поки перший лічив транзакції, а другий токени, графік віднімав монети від штук.
  **Рефлекс: перш ніж судити метрику, знайди її `expr` у `deploy/grafana/` і прочитай ЗАГОЛОВОК
  панелі — саме він каже, що з нею роблять.** ⚠️ **І перш ніж шукати `expr`, глянь у ДОКСТРІНГ:
  метрика могла оголосити ярус.** ⊕ Дзеркало: **чимало метрик споживача не мають ЗОВСІМ**, і для
  них «полагодити» — ратчет, а не ремонт; ціна інша, питання теж. 🔴 **Гілок ТРИ, не дві, з
  ⚖️ 2026-08-29 (INF.26): дротувати правило · дротувати панель · ОГОЛОСИТИ діагностичний ярус**
  (`[<ID>; diagnostic tier: <подія дротування>]` у докстрінгу). Декларація перетворює «без
  споживача» з дефекту на оголошений стан, і відтоді гейт судить наявність ДЕКЛАРАЦІЇ, а не
  наявність алерту — політика й межі `06_03 §2.8`, носій `spec/quality/metric_registry_doc_sync_spec.rb`.
  ⛔ Але вона енфорсить паритет, ніколи законність: на грошовому, слешинговому, MRV-доказовому
  чи безпековому шляху «діагностична» УЗАКОНЮЄ діру. Виміряно тим самим проходом — `lineage_root_failures_total`
  і `fw2_fc_degraded_reports_total` обидва спокусливо читались діагностичними, і обидва
  дістали споживача. Money-половину цього дзеркала закрито 2026-08-25
  дротуванням алертів (`sn-alert-mint-stall-depth` · `sn-alert-slashing-event`), і тим самим
  ходом 08-25 — `sn-alert-treasury-check-errors`. 🔑 **Той третій вартий окремого рядка, бо
  показав, ЩО САМЕ купує дротування метрики без споживача: воно дає ТИШІ ГОЛОС.**
  `ORACLE_BALANCE_RATIO` писав `0.0` з `rescue`, невідрізнимий від «оракул порожній», тож
  один RPC-таймаут пейджив ДВОМА balance-правилами на гаманці, що міг бути повний. Лік —
  гард на запис (тепер gauge при збої ЗАВМИРАЄ на останньому відомому), але сам по собі він
  проміняв би гучну брехню на тиху; чесним його робить рівно те, що «не змогли прочитати»
  дістало власний канал. **Рефлекс: замовчуючи метрику на збої, спитай, ЩО тепер кричить
  замість неї — інакше ти прибрав не помилку, а сигнал.**
  ⚠️ Гейт на цей клас НЕ будується наївно: «подієвий не має вживати `by:`» спростовує
  `FILECOIN_REPIN_TOTAL` (`by: ids.size` — батч подій, коректно). Наявний `grafana_alerts_spec`
  звіряє ІСНУВАННЯ метрики в alert-expr, ніколи семантику — не цитуй його зелене як доказ.
- 🔴 **Перш ніж лагодити підозрілу метрику, спитай не «чи форма підозріла», а «що ця величина
  МОЖЕ виражати» — двічі поспіль відповідь дала СХЕМА, а не код** (INF.26, 2026-08-25): `.to_i`
  над `bigint`-колонкою є no-op (підозра «зрізає дробові» стосувалась сусідньої `numeric`-шкали),
  а `nil` від `MerkleTree.root([])` — задокументований дизайн, не збій обчислення.
  ⊕ **Четвертий рід, доданий 2026-08-25 і найтихіший: величина ПРАВИЛЬНА, а лічильник
  бере лише ОДИН із її станів.** `ANCHOR_MISSED_WEEKS_TOTAL` рахував спрацювання детектора,
  тоді як `missed_weeks` уже було обчислене рядком вище — пʼятитижнева прогалина важила як
  одна, і недолік НЕЗВОРОТНИЙ (наступного тижня `last_anchor` свіжий, детекція мовчить).
  ⚠️ Вердикт алерту при цьому не мінявся (гейт на `> 0`) — мінялась придатність ЧИСЛА до
  питання «наскільки довго», яке людина й ставить, побачивши алерт. **Тож перш ніж назвати
  розходження косметичним, спитай не «чи зміниться вердикт», а «чи хтось ЧИТАЄ значення».**
  ⊕ Пʼятий, дзеркальний: гістограма, чий `.observe` стоїть ПІСЛЯ блоку, міряє латентність
  лише того, що ВДАЛОСЬ (`ORACLE_DISPATCH_DURATION` — survivorship bias: деградований оракул
  не додавав до p99 нічого). ⊥ Але «спостерігати завжди» тут протилежна помилка: наш власний
  circuit-breaker відмовляє за мікросекунди й ЗАНИЗИВ би p99. Межа — `ensure` ВСЕРЕДИНІ
  breaker-блоку, і обидві половини пінуються окремо. ⊕ І тримай у
  полі зору третій рід, який лікується СЛОВОМ, а не кодом: **сайт коректний, бреше ПІДПИС** —
  `W3BSTREAM_SIGNATURE_FALLBACK_TOTAL` рахує ПЕРЕДУМОВУ (немає придатного `HardwareKey`), що
  правда в обох режимах, а «using fallback» хибне в проді, де шлях завершується fail-closed
  відмовою; перенесення інкременту «туди, де ім'я стає правдою», осліпило б прод саме там, де
  сигнал найпотрібніший. **Фікс сайту буває дорожчим за дефект — спершу спитай, що зникне.**
- 🔴 **DEFAULT-партиція є єдиною, чия НЕПОРОЖНІСТЬ ламає обслуговування незворотно** (ARCH.70, виміряно експериментом 2026-08-28). Щойно в DEFAULT-лист осів рядок місяця N, `CREATE TABLE IF NOT EXISTS … PARTITION OF` для місяця N падає `PG::CheckViolation` НАЗАВЖДИ, повідомлення НЕ містить `already exists` → `PartitionMaintenanceWorker` re-raise, і **ретраї не лікують**, бо стан сам не змінюється. Каскад: прохід падає на першій таблиці, решта не дістає партицій НАСТУПНОГО місяця, а семпл гейджів стоїть ПІСЛЯ циклу — три ARCH.70-алерти замерзають разом. Прилад-попередження `silkennet_partition_default_occupied` (0/1, `EXISTS` а не `count` — рішення оператора від кількості не залежить, а скан розрослого DEFAULT коштував би саме в інциденті) + `sn-alert-partition-default-occupied`; **рунбук із точними SQL-кроками — [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup), і порядок там несучий** (створити партицію ДО `DETACH` неможливо — це і є сам дефект). ⚠️ Сусідній `silkennet_partitions` лічить ЛИСТИ, а не «місяці історії»: серед них завжди DEFAULT і створений наперед наступний місяць, тож число більше на 1-2 — поправка в [`06_03 §2.8`](06_03_Prometheus_Observability), і саме на цьому числі стоїть ⚖️ ширини вікна ретеншну.
- **Секрети One-Home:** канонічний дім — `config/deploy.yml env.secret`; повний
  інвентар + checklist — `06_04`. CI-гейт `verify-secrets`.
- **SSH на Ingress Anchor = IAP-тунель + OS Login, keyless (INF.20 (в)).** Порт 22 в інтернет
  НЕ відкритий; SSH-секретів у deploy-наборі НЕМАЄ; вхід `gcloud compute ssh silken-net-ingress
  --tunnel-through-iap` (доступ = tf-var `iap_admin_members`). Команда/роль-модель/(б)-клей → `06_01` / 00_07 INF.20.
- **CI→GCP auth = keyless WIF (INF.22)** — без довгоживучого `GCP_SA_KEY` JSON (GitHub OIDC →
  GCP STS → impersonated deploy-SA). Provider+SA email = repo **Variables** (presence = deploy-gate).
  **Keyless БЕЗ винятків** — `GCP_SA_KEY_BASE64` не існує ніде (`OPS.37` зняв єдиний виняток
  разом із платформою, що його вимагала). **Механіка/case-safety → `06_07 §1a`**
  (`attribute_condition` owner-рівня ОБОВʼЯЗКОВИЙ + owner-case нормалізовано `lowerAscii()`);
  реєстр самого секрету → `06_04 §1.1`.
- 🔴 **Додав boot-гард на ENV — мусиш пройти фан-аут поверхонь нижче і ДВА процеси, інакше ти
  щойно зробив деплой неможливим** (2026-08-14; ⛔ НЕ цитуй сюди tracker-ID: цей наратив стояв під `ARCH.60`, а той пункт 2026-08-21 поглинув інші й тепер цілком про доставку сповіщень — ID резолвився, тож жоден гейт не почервонів. Механізм живе в каноні: `03_05 §…` boot-guard, `03_06 §…` fail-closed, `04_02 §…` інвокери, `06_04 §5.7` coap-виняток). Поверхні: `config/deploy.yml` **env.clear**
  (не-секрети) + **env.secret** → `.kamal/secrets-common` (`$VAR`) → `env:`-блок КОЖНОГО
  deploy-воркфлоу (`deploy.yml` canopy + `deploy-production.yml`) → кожен Kamal-роль+accessory
  env-блок (`servers.{web,job,coap}` + `accessories.alloy` у `config/deploy.yml`) і його
  `config/deploy.canopy.yml`-оверрайд (B3: `servers:` там лишається МАСИВОМ — інакше
  deep_merge юнітить job-квінтет у канопі) → ⚠️ **terraform `variables.tf` — але вже НЕ як крок того самого воркфлоу**: [INF.22] зняв джобу `terraform` із деплою (apply founder-local), тож `TF_VAR_` у `deploy*.yml` більше не додають — інакше повертаєш рівно те, що коміт зняв, і оживляєш `terraform_workflow_var_parity` на воркфлоу, який terraform не запускає. Ланцюг закінчується Kamal-поверхнями; tf-змінні заводить founder локально +
  `main.tf`/`compute.tf` templatefile-мапа. Ланцюг секретів енфорсить `spec/deploy/env_fetch_declaration_spec.rb`
  — ⚠️ але **лише для `ENV.fetch("X")` БЕЗ дефолту в `app/`+`lib/`**, тож змінна, прочитана в
  `config/environments/*.rb` або з дефолтом, для нього **не існує** (мій випадок: жодного хіта).
  🔴 **Процеси — окрема вісь, і саме там ламається тихо:** `after_initialize` біжить у КОЖНОМУ,
  хто вантажить середовище. `canopy` = web-only (масив-форма `servers:`, Sidekiq немає взагалі →
  доставки пошти теж) і `coap_listener` = UDP-клей, що вантажить усі ініціалізатори. Обидва
  вимагали б можливості, якої не мають. Платформа має ДВА зразки звільнення — видати змінні
  процесу (AR-ключі на coap) або **пропустити сам процес** (`next if $PROGRAM_NAME.include?("coap_listener")`
  у `master_key_strength_check`); бери другий, коли шляху до фічі з процесу немає взагалі.
  ⚠️ І плейсхолдер `REQUIRED_SECRET_NOT_SET` присутність-гард **проходить** — форматну перевірку
  див. `.claude/skills/ssot-maintenance/guard-craft.md` #58.
- **Money/signing-п'ятірка = JOB-ONLY** (`ORACLE_MINTER/SLASHER/CELO` + `ETHEREUM_ANCHOR` +
  `SOLANA_WALLET_KEYPAIR`) — least-privilege, і post-`OPS.37` підстава ширша: `config/deploy.yml`
  глобальний `env.secret` успадковують УСІ ролі (включно з `coap`), тож квінтет живе ЛИШЕ в
  `servers.job.env.secret`, ніколи в глобальному блоці (`scripts/deploy_secret_scan.rb`
  інваріант B). legacy `ORACLE_PRIVATE_KEY` **RETIRED** (guard-tripwire). Web/coap keyless
  (guard scoped `signer_process: Sidekiq.server?`). Mitigation/aux-gated → `06_04 §1.1`.
- **SEC.22 latch: at-rest ≠ runtime** — провайдер читає `/proc/environ`, тож жоден секрет не сміє
  жити лише за `RAILS_MASTER_KEY`-vault у runtime. credentials→ENV (8 сервісів + `storage.yml`);
  AR-encryption ключі = ENV (boot-guard fail-closed, були DEAD-in-prod). Механіка/Phase-2-drop →
  `06_04 §5.7` / 00_07 SEC.22.
- **Secrets-at-rest = три ISOLATED KMS-keyring'и** (`silken-disk-ew1` boot-disk CMEK ·
  `silken-sign-ew1` money-signing SEC.17 pre-mainnet · `silken-tfstate-ew1` bootstrap-owned) —
  key-level IAM бар'єр, **НЕ** generic keyring (merge-trap). ⚠️ Money-квінтет лишається plaintext
  у deploy-ENV до `SEC.17` (`KmsSigner` HSM-custody, pre-mainnet-gated) — поточний масштаб цієї
  діри пост-`OPS.37` переоцінює сам `SEC.17`, тут не вгадуємо. Grantee/purpose/boot-dep → `06_04 §5.6`.
- **Deploy/release ланцюг:** Canopy = continuous push у `main` після CI; Production = GitHub Release
  (release-please: semver+CHANGELOG); GHCR-mirror пушить SLSA provenance+SBOM. `main` branch-protected
  (`CI passed`+`Docs passed`, owner пушить напряму). Діаграма/гейти → `06_07 §1`/`§2`.
- **GH Environment `production` = дім money-п'ятірки (INF.22)** — environment-scoped, НЕ repo-level;
  Canopy money-ключі структурно не споживає (`deploy.canopy.yml` `servers:` array-form → Kamal
  deep_merge keys-union). Wait-timer-per-job / Kamal-secrets-chain (`.kamal/secrets-common`) → `06_04 §1` / `06_07 §1`.

## Карта коду / конфігів

| Шар | Шлях |
|---|---|
| Kamal deploy | `config/deploy.yml` · `config/deploy.canopy.yml` · `.kamal/secrets-common` |
| IaC (GCP) | `terraform/` (`compute.tf` — анкор-демон systemd/env-file + boot-disk CMEK · `database.tf` · `vpc.tf` · `iam.tf` · `main.tf` · `kms.tf` — Cloud KMS keyring/IAM · `wif.tf` — keyless CI→GCP OIDC (INF.22) · `billing.tf` — OPS.11 budget-guard) |
| Observability | `config/initializers/prometheus.rb` (`SilkenNet::Metrics`) · `app/middleware/prometheus_collector.rb` · `lib/silken_net/metrics_exporter.rb` (embedded /metrics job/coap) · `deploy/alloy/config.alloy` · Grafana IaC `deploy/grafana/` (`deploy/grafana/alerts/silkennet-alerts.yaml` · `dashboards/` · `import.rb`) |
| Web-сервер | `config/puma.rb` |
| Load/throughput | `lib/silken_net/load_test/` + `bin/coap_load` (INF.23 harness: factory·flood·drain·microbench·report). ⚠️ dev-число ≠ capacity — bottleneck-class inversion (prod network-IO-bound, dev завищує 10-50×); реальна стеля лише staging з prod-adapters → `06_08 §2.4` |
| CI/CD | `.github/workflows/` (`deploy.yml` — path-gated INF.9 · `deploy-production.yml` · `coap_smoke.yml` — post-deploy gate + 30хв liveness-schedule · `iac_scan.yml` — Sec·IaC-Scan (Trivy `config`, SARIF soft-fail; baseline у `.trivyignore`) · `image_cve_scan.yml` — Sec·Image-CVE-Scan (Trivy `image` по ОПУБЛІКОВАНОМУ тегу GHCR, щоденний cron; SOFT за конструкцією — CVE базового шару лікуються бампом образу, тож HARD із народження = вічно червоний воркфлоу; ⚠️ кореневий `.trivyignore` — базлайн IaC-місконфігів і для CVE інертний, свій потрібен лише при переході в HARD) · `terraform_drift.yml` — Ops·TF-Drift (weekly `plan -detailed-exitcode`, skip-clean до 3 secrets) · `ci.yml` `terraform_validate`-job (offline `validate`+`fmt`, path-gated `terraform/**`, pre-deploy config-validity — INF.15) · `mirror-ghcr.yml` · `release-please.yml` · `ci.yml` · `docs.yml` · `ssot_guard.yml` · `subgraph.yml` — **CI · Subgraph** [OPS.34/OPS.36]: `npm ci`→`graph codegen`→`graph build`→`graph test` (matchstick — семантика мапінгу, з 2026-08-28), path-gated `subgraph/**`; merge-ADVISORY (`:flip_pending` у `workflow_gate_perimeter`), бо девʼятий required-контекст = дія над branch protection) |
| Deploy drift-guards | CI-гейти над deploy-конфігом (offline, no-creds; НЕ дублюй їх логіку — правь дім): `scripts/deploy_secret_scan.rb` (Kamal-ланцюг + anchor `COAP_ENV`-heredoc, post-`OPS.37`: no-literal + signing-quintet job-only-і-поза-ГЛОБАЛЬНИМ `env.secret` + retired-tripwire + B3 canopy `servers:`-array-form + `SUBJECT_FLOOR` проти парсер-колапсу + `.dockerignore`-exclusion + present-empty Invariant D + `_DSN` у `SECRET_NAME`) · `scripts/audit_deploy_secret_scope.rb` (S1.1 — live `gh`-scope preflight: money-quintet env-only · retired-zombie · WIF=Variables · Kredis-autoderive footgun) · `spec/deploy/*_spec.rb` (INF.16 db-config · INF.17 coap.env boot-contract · INF.4 firmware↔host · DR.1 DR-posture · INF.12 ENV.fetch↔deploy declaration + B1-chain · INF.12-behavior web3-env-loudness (кожен web3-ENV ∈ guard-set ∪ LOUD ∪ SOFT — silent-class tripwire) · SEC.22 credentials-ENV-first · S2.4 alloy-scrape-topology · S2.4 grafana-alerts↔REGISTRY-parity (silkennet_-метрика в alert-expr ∈ REGISTRY, typo→dead-alert; ⊕ **slot-ізоляція** — панель несе `{slot=~"$slot"}`, агрегація алерту `by (slot…)`; ⊕ `import.rb --verify` оголошений read-only, і це тримає спека, не обіцянка) · OPS.11 tf-workflow-var-parity) |

## Gotchas (верифіковані, не з канону)

1. **jemalloc через `LD_PRELOAD`** у Docker-образі (`libjemalloc.so`) — менше пам'яті
   й латентності. Не прибирай без бенчмарку.
2. **`SENTRY_DSN` задається at deploy time** (`.kamal/secrets-common`); без нього Sentry
   інертний — нуль crash-репортів.
3. **Старт через Thruster** (`thrust ./bin/rails server`) за замовчуванням; overridable at runtime.
4. **WIF рантайм = ТРИ GCP API** — `iam` (default-on) + `sts` + `iamcredentials`; останні два увімкнути **ЯВНО**. Пропущений `sts.googleapis.com` → перший keyless CI-run падає `SERVICE_DISABLED` (STS робить OIDC→federated exchange ПЕРЕД impersonation), а `terraform validate`/local-apply це НЕ ловлять (STS не викликається при create pool).
5. **keyless AUTH ≠ terraform-apply CAPABILITY** — CI імперсонує least-privilege deploy-SA БЕЗ IAM/WIF/serviceusage-admin, тож рефреш IAM/WIF-ресурсів дає **403**. ✅ **Розвилку ЗАКРИТО ⚖️ founder 2026-08-29: `apply` лишається founder-local, і конфіг це виконує — джоби `terraform` у deploy-воркфлоу БІЛЬШЕ НЕМА** (разом із нею знято `TF_VAR_*` і `terraform/` з path-фільтра canopy; `deploy` висить на `needs: verify-secrets`). ⛔ Не читай цей пункт як відкрите питання «apply в CI чи ні» — SA-privesc відхилено з підставою (він вимагав би чотирьох GCP-адмін-ролей, тобто god-credential проти самої мети keyless-WIF). 🔴 **І це не було косметикою:** доти `deploy` залежав від тієї джоби через `needs:`, тож у день деплою, ЩОЙНО заведуть WIF-Variables, вона діставала б 403 і `kamal deploy` не побіг би ЖОДНОГО разу; невидиме доти лише тому, що Variables порожні. Що лишається сьогодні: 403 у **weekly `terraform_drift.yml`** (він і далі робить `plan` з рефрешем) — тобто оголошений негатив детектора, не блокер релізу. → 00_07 INF.22 · `06_07 §1` · `06_01 §IAM`/Фаза 0.
6. **`gh run watch --exit-status` бреше** (exit 0 on fail / 1 on empty) — щоб перевірити, чи Deploy·Canopy/Production реально пройшов, довіряй `gh run view --json conclusion`, не `watch`.
6a. 🔴 **`conclusion: failure` теж бреше — не про факт, а про ПРИЧИНУ, і саме ця брехня маскує справжній червоний** (OPS.23). Хрестик «джоба не добігла» (раннери не видались: «The job was not acquired by Runner of type hosted…») і хрестик «код зламано» виглядають у панелі ІДЕНТИЧНО, а перший ховає другий — виміряний випадок: інфраструктурний червоний накрив червону підлогу покриття, і її не побачив ніхто. **Рефлекс на червоний `main`: питай спершу не «що зламалось», а «чи джоба СТАРТУВАЛА»** — `gh run view <id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | {name, steps: [.steps[].name]}'`; порожній `steps` = інфраструктура → **re-run**, бо під тим хрестиком може стояти другий. Дзеркальна половина класу закрита машинно: агрегат тепер стверджує результат САМОГО path-фільтра (доти незадеклароване `skipped` резолвилось у «OK», і `CI passed` зеленів, не виконавши жодної джоби) і його помилка явно каже «infrastructure failure, not a code failure» → `06_07 §2`. Ця ж, друга, нерозрізненна за побудовою — збій передує запуску нашого коду.
7. **`gh attestation verify` рендерить TTY-only** → piped/`tail`/`grep` захоплюють ПОРОЖНЄ; довіряй **EXIT=0** або `--format json`.
9. 🔴 **Перший ЖИВИЙ прогін `import.rb` (2026-08-29) знайшов ТРИ дефекти, яких `--dry-run` не бачить ЗА ПОБУДОВОЮ** — він судить ФОРМУ артефактів, а всі три були про ФІТ із реальним API. Носія в жодного з трьох немає, тож рефлекс тут — єдиний:
   · **datasource-автовиявлення бере is-default, а за неоднозначності ВІДМОВЛЯЄТЬСЯ.** Grafana Cloud віддає кілька prometheus-джерел, і біллінгове `grafanacloud-usage` стоїть у списку ПЕРШИМ. Стара `.find` привʼязала б усі правила до бази, де `silkennet_*` не буде НІКОЛИ: резолвляться, виглядають здоровими, не спрацьовують ніколи. ⛔ Імʼя НЕ дискримінатор — денилист на `usage` протух би на першому перейменуванні вендором. **Регресія (повернення до `.find`) не ловиться жодним гейтом.**
   · **uid alert-правила ≤ 40 символів** — межа ВЕНДОРСЬКА, і відмова приходить лише з живого API (`400: UID is longer than 40 symbols`) ПОСЕРЕД черги: частина правил уже записана, решта не поїде. Тепер це валідує `--dry-run` (`RULE_UID_MAX`).
   · **`interval` групи — секунди-ЦІЛИМ в API проти рядка-тривалості (`1m`) у provisioning-файлі.** Порівняння `60 != "1m"` завжди нерівне, тож warn «інтервал не виставився» був хибною тривогою про ПРАВИЛЬНИЙ стан — і саме тому ховав справжній дрейф (`p2-info` стояв на 60 с замість 300). Тривога, що звучить завжди, не звучить ніколи.
   ⊕ **Дашборд і правила РОЗЧЕПЛЕНІ:** Grafana Cloud скоупить RBAC по теках, тож 403 на дашборді обривав імпорт до першого правила — часткові права давали НУЛЬ замість більшої половини. Тепер провал гучний і несе `exit 1`, але правила їдуть. Побачив частковий провал — це очікувана поведінка, не регресія.
   ⊕ **Звірка живого стека — `ruby deploy/grafana/import.rb --verify`** (READ-ONLY; оголошені стелі в шапці самої гілки): чи всі правила сіли · чи привʼязаний datasource · чи немає правил, СТВОРЕНИХ ПОВЗ РЕПО (зворотний дрейф, якого upsert не чіпає) · чи збігаються інтервали. ⛔ Він судить НАЯВНІСТЬ, ніколи правильність порогів, і не читає ані silences, ані contact point.
8. 🔴 **Console-доступ задокументований, але жодного разу не виконаний на живому контейнері — бо не задеплоєно нічого й ніде** (виміряно 2026-07-29; природа зафіксована `OPS.37` 2026-08-29). Доти діра читалась як «рецепт для НЕ-ТОГО таргета» (Kamal задокументований, живим вважався Akash); з платформою знято й Akash-таргет — **тепер таргет один, рецепт один** (`kamal app exec --interactive --reuse "bin/rails console"`, `06_01 §DEPLOY-DAY`), а асиметрія не закрилась — вона змінила ПРИРОДУ: лайв-прогону не було НІКОЛИ. Наслідок несе не той документ, де діра: **інертними лишаються всі console-рецепти репо**, зокрема два money-path (`manual_review`-резолюція та ескалація Field-Audit C→A, що відчиняє ворота необоротного слешингу). Тож пишучи новий рецепт «виконай у консолі», не вважай доступ вирішеним питанням; спільна нота стоїть одним домом у шапці `06_07 §3` — читай і вирівнюй, не пиши третю редакцію. ⛔ `coap` для консолі не брати (звільнений від master-key-перевірки). → `00_07` OPS.20.

## Робочі правила

1. **Docs-first.** Прочитай `06_0N` (саме *чому* + поточний стан/TRL) перед зміною
   деплою, секрету чи метрики — кожен 06-док несе власний member-TRL у ✅ Статус.
2. **SSOT One-Home.** Правиш факт — правь у його домі (`06_04` секрети, `06_03 §2.8`
   метрики, `terraform/` config), не тут. Skill лишається тонким маршрутом.
3. **Гейти.** Після правок канону — `bin/rails docs:check_refs` зелений; робота над
   SSOT-доками 06_xx — через skill `ssot-maintenance`.
