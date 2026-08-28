---
name: deploy
description: "Use when deploying or operating silken_net infrastructure — Kamal/Terraform GCP, Akash decentralized cloud, secrets, observability (Grafana Alloy → Grafana Cloud), disaster-recovery, CI/CD, resilience/failover. This is Module 06 'The Matrix'. Routes to the 06_xx canon docs and the load-bearing infra invariants; does not restate them."
---

# Deploy & Infrastructure (Module 06 — The Matrix)

DevOps/Infra шар: Rails на **Akash** (децентралізовано, цензуростійко) +
**GCP** (Cloud SQL / Redis / failover). Деплой через **Kamal**, IaC через
**Terraform**, спостережуваність через **Grafana Alloy → Grafana Cloud**.

## Канон — читати ПЕРЕД зміною інфри/секретів/метрик

SSOT One-Home: цей skill лише **маршрутизує**; факти живуть у `docs/` + config-SSOT.
Не дублюй сюди значення/інвентар і **не хардкодь `file:line`** (дрейфує — стале вже за
комітом). Посилайся на стабільні якорі: канон-§ + імена символів/шляхів.

| Що треба | Канон-дім |
|---|---|
| Деплой **Kamal + Terraform GCP**, Canopy vs Production | `06_01` ← read-first для деплою |
| **Akash** SDL (`web` + `job` + `coap` + `alloy`), multi-provider failover | `06_02` |
| **Observability** — метрики / Alloy → Grafana Cloud / alerting | `06_03` (реєстр метрик — `06_03 §2.8`) |
| **Секрети** — інвентар + checklist (GitHub / Kamal / Akash / Terraform) | `06_04` (canonical = `config/deploy.yml env.secret`) |
| **Puma 8** config + cluster hooks + runbook'и | `06_05` |
| **Disaster Recovery** / backup / RTO-RPO / master-key | `06_06` (config SSOT = `terraform/database.tf`) |
| **CI/CD** workflows + єдиний operations runbook-індекс | `06_07` |
| **Resilience** — Queen failover (4 рівні) + Per-Chain Fallback Matrix + **топологія черг Sidekiq** (`§2.5` — anti-starvation через ізоляцію ПРОЦЕСІВ, не перестановку черг; flip = `sidekiq -q`-прапори в deploy-конфізі, тобто deploy-рішення, НЕ код) | `06_08` |

## Несучі інваріанти (не очевидні з коду)

Будь-хто, хто чіпає деплой, МУСИТЬ це знати (суть тут, механіка — за canon-§):

- **Akash + GCP — failover, не «або-або».** Rails-ворклоад на Akash; GCP тримає
  Cloud SQL + є failover-ціллю (Redis — зовнішній **Upstash** Serverless TLS, не GCP). → `06_01` / `06_02`.
- **CoAP-інтейк: PRIMARY = демон на Ingress Anchor** (docker+systemd, приватний IP Cloud SQL
  БЕЗ Auth Proxy; секрети `/etc/silkennet/coap.env`, НЕ metadata). Akash `coap` = idle-**fallback**
  за socat (перемикання 2×systemctl); money/web лишаються на Akash. **coap.env** = 3-тя
  boot-contract поверхня поза `sdl_consistency` (pure UDP glue, нуль key-derivation → несе
  AR-encryption-трійку, **НЕ** `PROVISIONING_MASTER_KEY`; guard `spec/deploy/anchor_coap_env_spec.rb`).
  → `06_01` / `06_02` / `06_04 §5.7`.
- **Cloud SQL Auth Proxy авторизує через Google API, але СОКЕТ іде на IP інстанса** —
  з Akash (поза VPC) досяжний лише ПУБЛІЧНИЙ IP → `ipv4_enabled = true` обов'язковий
  (authorized_networks порожній — доступ тільки IAM-proxy; ENCRYPTED_ONLY). private-only
  = crash-loop усіх сервісів. Проксі активується **лише** коли `CLOUD_SQL_INSTANCE_CONNECTION_NAME`
  заданий; Kamal-шлях (у VPC) — приватний IP напряму. → `06_02` (+ `terraform/database.tf` at-use).
- **Observability = Alloy → Grafana Cloud SaaS; self-hosted Prometheus НЕ потрібен (OBS.1).**
  Реєстр **in-process** → web:80 НЕ бачить job/coap-інкрементів напряму → Alloy скрейпить
  **три таргети** (`web:80`+`job:9394`+`coap:9395`, лейбл `process`). Топологія/стелі → `06_03 §2.9`;
  реєстр+кількість метрик → `06_03 §2.8` (**не хардкодь**).
- 🔴 **Що метрика ОЗНАЧАЄ, вирішує її СПОЖИВАЧ, а не докстрінг** (INF.26, 2026-08-13).
  Питання «`by:` чи голий `.increment`» нерозвʼязне з коду й розвʼязне з панелі: `SCC_MINTED_TOTAL`
  і `SCC_SLASHED_TOTAL` живуть на ОДНІЙ панелі «SCC Minted vs Slashed», на одній осі — тож
  поки перший лічив транзакції, а другий токени, графік віднімав монети від штук.
  **Рефлекс: перш ніж судити метрику, знайди її `expr` у `deploy/grafana/` і прочитай ЗАГОЛОВОК
  панелі — саме він каже, що з нею роблять.** ⊕ Дзеркало: **чимало метрик споживача не мають
  ЗОВСІМ** (живий перелік — `00_07` INF.26, числа сюди не копіюємо), і для них «полагодити» —
  ратчет, а не ремонт; ціна інша, питання теж. Money-половину цього дзеркала закрито 2026-08-25
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
- **Секрети One-Home:** канонічний дім — `config/deploy.yml env.secret`; повний
  інвентар + checklist — `06_04`. CI-гейт `verify-secrets`.
- **SSH на Ingress Anchor = IAP-тунель + OS Login, keyless (INF.20 (в)).** Порт 22 в інтернет
  НЕ відкритий; SSH-секретів у deploy-наборі НЕМАЄ; вхід `gcloud compute ssh silken-net-ingress
  --tunnel-through-iap` (доступ = tf-var `iap_admin_members`). Команда/роль-модель/(б)-клей → `06_01` / 00_07 INF.20.
- **CI→GCP auth = keyless WIF (INF.22)** — без довгоживучого `GCP_SA_KEY` JSON (GitHub OIDC →
  GCP STS → impersonated deploy-SA). Provider+SA email = repo **Variables** (presence = deploy-gate).
  Виняток = Akash `GCP_SA_KEY_BASE64` (зовн. провайдер не досягає GitHub-issuer'а).
  **Механіка/case-safety → `06_07 §1a`** (`attribute_condition` owner-рівня ОБОВʼЯЗКОВИЙ +
  owner-case нормалізовано `lowerAscii()`); реєстр самого секрету → `06_04 §1.1`;
  виняток Akash → `06_02 §Security Exception`. ⚠️ Адреси РІЗНІ: обидві резолвляться, тож
  `code_doc_section_refs` зелений і на хибній — механіка в реєстрі секретів не живе.
- 🔴 **Додав boot-гард на ENV — мусиш пройти ВІСІМ поверхонь і ДВА процеси, інакше ти щойно
  зробив деплой неможливим** (2026-08-14; ⛔ НЕ цитуй сюди tracker-ID: цей наратив стояв під `ARCH.60`, а той пункт 2026-08-21 поглинув інші й тепер цілком про доставку сповіщень — ID резолвився, тож жоден гейт не почервонів. Механізм живе в каноні: `03_05 §…` boot-guard, `03_06 §…` fail-closed, `04_02 §…` інвокери, `06_04 §5.7` coap-виняток). Поверхні: `config/deploy.yml` **env.clear**
  (не-секрети) + **env.secret** → `.kamal/secrets-common` (`$VAR`) → `env:`-блок КОЖНОГО
  deploy-воркфлоу (`deploy.yml` canopy + `deploy-production.yml`) → Akash SDL **web І job** у
  **обох** маніфестах (`deploy.yaml` статичний + `.tpl`) → terraform `variables.tf` +
  `main.tf` templatefile-мапа. Ланцюг секретів енфорсить `spec/deploy/env_fetch_declaration_spec.rb`
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
- **Akash SDL ENV = plaintext, видимий провайдеру.** Реальні ключі **ніколи** в `deploy.yaml` —
  інжект через Console/`env.secret`. **Money/signing-п'ятірка = JOB-ONLY** (`ORACLE_MINTER/SLASHER/CELO`
  + `ETHEREUM_ANCHOR` + `SOLANA_WALLET_KEYPAIR`); legacy `ORACLE_PRIVATE_KEY` **RETIRED** (guard-tripwire).
  Web/coap keyless (guard scoped `signer_process: Sidekiq.server?`). Mitigation/aux-gated → `06_02` / `06_04 §1.1`.
- **SEC.22 latch: at-rest ≠ runtime** — провайдер читає `/proc/environ`, тож жоден секрет не сміє
  жити лише за `RAILS_MASTER_KEY`-vault у runtime. credentials→ENV (8 сервісів + `storage.yml`);
  AR-encryption ключі = ENV (boot-guard fail-closed, були DEAD-in-prod). Механіка/Phase-2-drop →
  `06_04 §5.7` / 00_07 SEC.22.
- **Secrets-at-rest = три ISOLATED KMS-keyring'и** (`silken-disk-ew1` boot-disk CMEK ·
  `silken-sign-ew1` money-signing SEC.17 pre-mainnet · `silken-tfstate-ew1` bootstrap-owned) —
  key-level IAM бар'єр, **НЕ** generic keyring (merge-trap). ⚠️ найбільша at-rest-діра лишається
  **Akash-plaintext** (money-квінтет provider-visible) → SEC.17. Grantee/purpose/boot-dep → `06_04 §5.6`.
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
| Akash | `deploy/akash/` (`deploy.yaml` SDL · `deploy.yaml.tpl` · `config.alloy` · `encode-alloy-config.sh`); SDL-гейт `ruby scripts/sdl_consistency_check.rb` (services≡deployment, static≡tpl — CI + локально перед комітом SDL-змін) |
| Observability | `config/initializers/prometheus.rb` (`SilkenNet::Metrics`) · `app/middleware/prometheus_collector.rb` · `lib/silken_net/metrics_exporter.rb` (embedded /metrics job/coap) · `deploy/akash/config.alloy` · Grafana IaC `deploy/grafana/` (`deploy/grafana/alerts/silkennet-alerts.yaml` · `dashboards/` · `import.rb`) |
| Web-сервер | `config/puma.rb` |
| Load/throughput | `lib/silken_net/load_test/` + `bin/coap_load` (INF.23 harness: factory·flood·drain·microbench·report). ⚠️ dev-число ≠ capacity — bottleneck-class inversion (prod network-IO-bound, dev завищує 10-50×); реальна стеля лише staging з prod-adapters → `06_08 §2.4` |
| CI/CD | `.github/workflows/` (`deploy.yml` — path-gated INF.9 · `deploy-production.yml` · `coap_smoke.yml` — post-deploy gate + 30хв liveness-schedule · `akash_escrow_watch.yml` — AKT-runway вартовий OPS.11, skip-clean до `AKASH_OWNER_ADDRESS` · `iac_scan.yml` — Sec·IaC-Scan (Trivy `config`, SARIF soft-fail; baseline у `.trivyignore`) · `image_cve_scan.yml` — Sec·Image-CVE-Scan (Trivy `image` по ОПУБЛІКОВАНОМУ тегу GHCR, щоденний cron; SOFT за конструкцією — CVE базового шару лікуються бампом образу, тож HARD із народження = вічно червоний воркфлоу; ⚠️ кореневий `.trivyignore` — базлайн IaC-місконфігів і для CVE інертний, свій потрібен лише при переході в HARD) · `terraform_drift.yml` — Ops·TF-Drift (weekly `plan -detailed-exitcode`, skip-clean до 3 secrets) · `ci.yml` `terraform_validate`-job (offline `validate`+`fmt`, path-gated `terraform/**`, pre-deploy config-validity — INF.15) · `mirror-ghcr.yml` · `release-please.yml` · `ci.yml` · `docs.yml` · `ssot_guard.yml` · `subgraph.yml` — **CI · Subgraph** [OPS.34]: `graph codegen`→`graph build`, path-gated `subgraph/**`; merge-ADVISORY (`:flip_pending` у `workflow_gate_perimeter`), бо девʼятий required-контекст = дія над branch protection) |
| Deploy drift-guards | CI-гейти над deploy-конфігом (offline, no-creds; НЕ дублюй їх логіку — правь дім): `scripts/deploy_secret_scan.rb` (no-literal + signing-quintet job-only + retired-tripwire + `.dockerignore`-exclusion + present-empty Invariant D) · `scripts/sdl_consistency_check.rb` (SDL services≡deployment, static≡tpl) · `scripts/audit_deploy_secret_scope.rb` (S1.1 — live `gh`-scope preflight: money-quintet env-only · retired-zombie · WIF=Variables · Kredis-autoderive footgun) · `spec/deploy/*_spec.rb` (INF.16 db-config · INF.17 coap.env boot-contract · INF.4 firmware↔host · DR.1 DR-posture · INF.12 ENV.fetch↔deploy declaration + B1-chain · INF.12-behavior web3-env-loudness (кожен web3-ENV ∈ guard-set ∪ LOUD ∪ SOFT — silent-class tripwire) · SEC.22 credentials-ENV-first · S2.4 alloy-scrape-topology · S2.4 grafana-alerts↔REGISTRY-parity (silkennet_-метрика в alert-expr ∈ REGISTRY, typo→dead-alert) · INF.24 akash-auditor-bech32 · OPS.11 tf-workflow-var-parity) |

## Gotchas (верифіковані, не з канону)

1. **jemalloc через `LD_PRELOAD`** у Docker-образі (`libjemalloc.so`) — менше пам'яті
   й латентності. Не прибирай без бенчмарку.
2. **`SENTRY_DSN` задається at deploy time** (`.kamal/secrets-common`); без нього Sentry
   інертний — нуль crash-репортів.
3. **Старт через Thruster** (`thrust ./bin/rails server`) за замовчуванням; overridable at runtime.
4. **WIF рантайм = ТРИ GCP API** — `iam` (default-on) + `sts` + `iamcredentials`; останні два увімкнути **ЯВНО**. Пропущений `sts.googleapis.com` → перший keyless CI-run падає `SERVICE_DISABLED` (STS робить OIDC→federated exchange ПЕРЕД impersonation), а `terraform validate`/local-apply це НЕ ловлять (STS не викликається при create pool).
5. **keyless AUTH ≠ terraform-apply CAPABILITY** — CI імперсонує least-privilege deploy-SA БЕЗ IAM/WIF/serviceusage-admin → CI `terraform apply`/drift-`plan` рефреш IAM/WIF-ресурсів = **403**. Модель: `apply` founder-local (рек.) АБО SA-privesc (god-credential concern). → 00_07 INF.22.
6. **`gh run watch --exit-status` бреше** (exit 0 on fail / 1 on empty) — щоб перевірити, чи Deploy·Canopy/Production реально пройшов, довіряй `gh run view --json conclusion`, не `watch`.
6a. 🔴 **`conclusion: failure` теж бреше — не про факт, а про ПРИЧИНУ, і саме ця брехня маскує справжній червоний** (OPS.23). Хрестик «джоба не добігла» (раннери не видались: «The job was not acquired by Runner of type hosted…») і хрестик «код зламано» виглядають у панелі ІДЕНТИЧНО, а перший ховає другий — виміряний випадок: інфраструктурний червоний накрив червону підлогу покриття, і її не побачив ніхто. **Рефлекс на червоний `main`: питай спершу не «що зламалось», а «чи джоба СТАРТУВАЛА»** — `gh run view <id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | {name, steps: [.steps[].name]}'`; порожній `steps` = інфраструктура → **re-run**, бо під тим хрестиком може стояти другий. Дзеркальна половина класу закрита машинно: агрегат тепер стверджує результат САМОГО path-фільтра (доти незадеклароване `skipped` резолвилось у «OK», і `CI passed` зеленів, не виконавши жодної джоби) і його помилка явно каже «infrastructure failure, not a code failure» → `06_07 §2`. Ця ж, друга, нерозрізненна за побудовою — збій передує запуску нашого коду.
7. **`gh attestation verify` рендерить TTY-only** → piped/`tail`/`grep` захоплюють ПОРОЖНЄ; довіряй **EXIT=0** або `--format json`.
8. 🔴 **Console-доступ задокументований лише для FALLBACK-таргета** (виміряно 2026-07-29). `06_01` дає Kamal-шлях (`kamal app exec --interactive --reuse "bin/rails console"`); для Akash — а це **живий** шлях, так його називає `config/database.yml` — з 2026-08-28 є **рецепт-КАНДИДАТ** `06_02 §4.5` (доти еквівалента не було взагалі). Наслідок несе не той документ, де діра: **інертними стають усі console-рецепти репо**, зокрема два money-path (`manual_review`-резолюція та ескалація Field-Audit C→A, що відчиняє ворота необоротного слешингу). Тож пишучи новий рецепт «виконай у консолі», не вважай доступ вирішеним питанням; спільна нота стоїть одним домом у шапці `06_07 §3`. ✅ **Ключова технічна умова ВІДПОВІЛАСЬ нашим кодом, не чужою документацією:** проксі стартує фоновим процесом усередині ТОГО САМОГО контейнера (`bin/docker-entrypoint`), а не окремим Akash-сервісом, тож шелл у `web`/`job` ділить мережевий неймспейс; сильніше — PID 1 наглядає за проксі й виходить, щойно той помер (INF.22), а Akash перезапускає контейнер лише на виході PID 1, отже **контейнер, у який вдалося зайти, за побудовою має живий проксі**. ⏳ Лишається КАНДИДАТОМ сам механізм входу (`provider-services lease-shell`), і найважливіша межа названа: апстрім віддає `remote server returned 404` після рестарту сервісу провайдера — тобто інструмент може бути недоступним САМЕ в інциденті, а плану Б немає. ⛔ `coap` для консолі не брати (звільнений від master-key-перевірки). → `00_07` OPS.20.

## Робочі правила

1. **Docs-first.** Прочитай `06_0N` (саме *чому* + поточний стан/TRL) перед зміною
   деплою, секрету чи метрики — кожен 06-док несе власний member-TRL у ✅ Статус.
2. **SSOT One-Home.** Правиш факт — правь у його домі (`06_04` секрети, `06_03 §2.8`
   метрики, `terraform/` config), не тут. Skill лишається тонким маршрутом.
3. **Гейти.** Після правок канону — `bin/rails docs:check_refs` зелений; робота над
   SSOT-доками 06_xx — через skill `ssot-maintenance`.
