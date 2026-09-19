---
name: deploy
description: "Use when deploying or operating silken_net infrastructure — Kamal/Terraform GCP, secrets, observability (Grafana Alloy → Grafana Cloud), disaster-recovery, CI/CD, resilience/failover. This is Module 06 'The Matrix'. Routes to the 06_xx canon docs; does not restate them. The load-bearing invariants and the verified gotchas are indexed here one line each and written in full in invariants.md and gotchas.md, which load on demand — open invariants.md before changing infra, a secret, a boot guard, a metric or an alert, and gotchas.md before running a deploy, an import, a drift plan or a probe on a live slot."
---

# Deploy & Infrastructure (Module 06 — The Matrix)

DevOps/Infra шар: Rails на **GCP** (Kamal-деплой УСЕРЕДИНІ VPC; Cloud SQL
private-only, Redis — production: зовнішній **Upstash** Serverless TLS, canopy: self-hosted Kamal-accessory на app-хості з 09-03). IaC через
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
| **Resilience** — Queen failover (4 рівні) + Per-Chain Fallback Matrix (✅ **у маніфестах з 2026-09-02, виміряно на canopy** — keyless публічні фолбеки PublicNode/dRPC/офіційний Solana в `env.clear` обох маніфестів, canopy — testnet-двійники; чейн фолбеків судить гард `RPC_FALLBACK_URL_ENVS`; `ARCH.114` ⚖️ founder: акаунтний вендор лише якщо вкусять rate-limit-и) + **топологія черг Sidekiq** (`§2.5` — anti-starvation через ізоляцію ПРОЦЕСІВ, не перестановку черг; flip = `sidekiq -q`-прапори в deploy-конфізі, тобто deploy-рішення, НЕ код) | `06_08` |

## Несучі інваріанти (не очевидні з коду)

**Тіла — у [`invariants.md`](invariants.md); відкрий його, перш ніж міняти інфру, секрет, boot-гард,
метрику чи алерт.** Нижче — один згенерований рядок на інваріант: рядок є НОСІЄМ, що має спинити
посеред дії; механізм, інцидент і межі — у companion. Нумерація append-only з 2026-09-19 — цитуй
`deploy §Інваріанти #N`.

<!-- DEPLOY-INVARIANTS-INDEX:AUTO — generated from invariants.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. Redis має два доми за слотом — production = Upstash, canopy = Kamal-accessory на app-хості — і Free-межа Upstash рахує КОМАНДИ, тож її зʼїдає навіть порожній Sidekiq
2. `gcloud` — передумова ШЕСТИ кроків дня, а не першого; і до 2026-08-31 її не називала ЖОДНА фаза
3. `§Quickstart` у `06_01` БІЛЬШЕ НЕ ІСНУЄ — не шли туди нікого
4. CoAP-інтейк: PRIMARY = демон на Ingress Anchor, а Kamal-роль `coap` — лише дормантний fallback
5. Cloud SQL Auth Proxy авторизує через Google API — це ОРТОГОНАЛЬНО мережевій досяжності, не заміняє її
6. `deletion_protection` — ДВА РІЗНІ ЗАХИСТИ ПІД ОДНИМ СЛОВОМ, і на Cloud SQL стояв лише один
7. Observability = Alloy → Grafana Cloud SaaS; self-hosted Prometheus НЕ потрібен (OBS.1)
8. ALLOY-КОНТЕЙНЕР ОДИН НА ДВА СЛОТИ — тож `accessory boot` НІКОЛИ не беруть із `-d <destination>`
9. `BOOT_CRITICAL` — це єдине місце, де порожній секрет стає ГУЧНИМ; ланцюг `secrets-common` + workflow-`env:` доводить лише, що ІМʼЯ резолвиться
10. Що метрика ОЗНАЧАЄ, вирішує її СПОЖИВАЧ, а не докстрінг
11. Перш ніж лагодити підозрілу метрику, спитай не «чи форма підозріла», а «що ця величина МОЖЕ виражати» — двічі поспіль відповідь дала СХЕМА, а не код
12. Розбираючи «алертів туча» — спершу РОЗДІЛИ стан і сповіщення, і ЗМІРЯЙ, а не вір відчуттю
13. DEFAULT-партиція є єдиною, чия НЕПОРОЖНІСТЬ ламає обслуговування незворотно
14. `production` НЕ є відповіддю на питання «до якого чейну слот має право торкатись» — осей ДВІ [OPS.37, 2026-08-30]
15. «TLS термінує Cloudflare» — правда про КЛІЄНТСЬКЕ плече й пастка про друге [INF.4, виміряно 2026-08-30]
16. `DEPLOYMENT_SLOT` — третя вісь поруч із `WEB3_STRICT_MODE` і `WEB3_CHAIN_ENV`, і питання в неї власне: «який це ДЕПЛОЙ» [INF.27, 2026-08-30]
17. Інтейк: анкер ОДИН, демон ОДИН, слот = три рядки `coap.env` + `systemctl restart coap-daemon` [OPS.37 ⚖️ founder 2026-09-02]
18. `${VAR}` в `env.clear` = ПОРОЖНІЙ рядок у контейнері, не значення
19. `egress-policy: block` живе ЛИШЕ на трьох джобах `deploy.yml`, і allowlist там ВИМІРЯНА, не написана
20. Секрети One-Home: канонічний дім — `config/deploy.yml env.secret`; повний інвентар + checklist — `06_04`
21. SSH на ОБИДВІ машини = IAP-тунель + OS Login, keyless (INF.20 (в))
22. CI→GCP auth = keyless WIF (INF.22) — без довгоживучого `GCP_SA_KEY` JSON
23. Додав boot-гард на ENV — мусиш пройти фан-аут поверхонь нижче і ДВА процеси, інакше ти щойно зробив деплой неможливим
24. Money/signing-п'ятірка = JOB-ONLY: ключі підпису живуть лише в job-ролі, ніколи в глобальному `env.secret`
25. SEC.22 latch: at-rest ≠ runtime — провайдер читає `/proc/environ`, тож жоден секрет не сміє жити лише за `RAILS_MASTER_KEY`-vault у runtime
26. Secrets-at-rest = три ЖИВІ ISOLATED KMS-keyring'и — і ЧЕТВЕРТИЙ спроєктований
27. Deploy/release ланцюг: Canopy = continuous push у `main` після CI; Production = GitHub Release
28. GH Environment `production` = дім money-п'ятірки (INF.22) — environment-scoped, НЕ repo-level

<!-- /DEPLOY-INVARIANTS-INDEX -->

## Карта коду / конфігів

| Шар | Шлях |
|---|---|
| Kamal deploy | `config/deploy.yml` · `config/deploy.canopy.yml` · `.kamal/secrets-common` |
| IaC (GCP) | `terraform/` (`compute.tf` — **ДВА інстанси**: анкор (systemd/env-file + boot-disk CMEK) і app-хост `google_compute_instance.app` (Kamal web+job+coap; повернений OPS.37 2026-08-30 — приватний IP, Docker передвстановлений, бо наш deploy-SA не має sudo й `kamal server bootstrap` тут RAISE'ить; власної canopy-VM НЕМАЄ, і це ⚖️ **РАТИФІКОВАНО 2026-09-03**, не відкрите питання: спільний хост лишається, а нову машину при розділенні дістає PRODUCTION (тригер — перший production-рендер; повний присуд і вимір по SKU — шапка `config/deploy.canopy.yml`)) · `database.tf` · `vpc.tf` · `iam.tf` · `main.tf` · `kms.tf` — Cloud KMS keyring/IAM (два disk-ключі: `anchor-boot` · `app-boot`) · `wif.tf` — keyless CI→GCP OIDC (INF.22) · `billing.tf` — OPS.11 budget-guard · **`.terraform.lock.hcl` — КОМІЧЕНИЙ з 2026-09-06**: точна версія провайдера + per-platform хеші. ⛔ Оновлювати ЛИШЕ `terraform providers lock -platform=linux_amd64 -platform=darwin_arm64`, ніколи простим `init -upgrade`: той пише хеші лише для платформи прогону, а `terraform init` їде на linux_amd64 у ДВОХ місцях (`ci.yml` + `terraform_drift.yml`) — однопlatформний лок кладе обидва; підстава → `06_07 §1a`) |
| Observability | `config/initializers/prometheus.rb` (`SilkenNet::Metrics`) · `app/middleware/prometheus_collector.rb` · `lib/silken_net/metrics_exporter.rb` (embedded /metrics job/coap) · `deploy/alloy/config.alloy` · Grafana IaC `deploy/grafana/` (`deploy/grafana/alerts/silkennet-alerts.yaml` · `dashboards/` · `import.rb`) |
| Web-сервер | `config/puma.rb` |
| Load/throughput | `lib/silken_net/load_test/` + `bin/coap_load` (INF.23 harness: factory·flood·drain·microbench·report). ⚠️ dev-число ≠ capacity — bottleneck-class inversion (prod network-IO-bound, dev завищує 10-50×); реальна стеля лише staging з prod-adapters → `06_08 §2.4` |
| CI/CD | `.github/workflows/` (`deploy.yml` — path-gated INF.9 · `deploy-production.yml` · `coap_smoke.yml` — post-deploy gate + 30хв liveness-schedule · `iac_scan.yml` — Sec·IaC-Scan (Trivy `config`, **HARD**: `exit-code: 1`, базлайн зведено до нуля; винятки — `.trivyignore` з підставою на кожен AVD-ID). 🔴 **Доти цей рядок казав «SARIF soft-fail» — ХИБНО, і воно коштувало:** `IaC passed` є required-чеком, а скіл, який читають ПЕРЕД роботою з інфрою, оголошував гейт мʼяким. Виміряно 2026-09-06: правка `Dockerfile` поїхала в `main` без локальної перевірки саме тому — обійшлось. Лік поставлено обабіч: рядок виправлено, і заведено локальний пре-фрайт у `.githooks/pre-push` (`trivy config` над `Dockerfile` + `terraform/`, ⛔ судить ПІДМНОЖИНУ гейта, тож його зелене не є вердиктом про `IaC passed`) · `image_cve_scan.yml` — Sec·Image-CVE-Scan (Trivy `image` по ОПУБЛІКОВАНОМУ тегу GHCR, щоденний cron; SOFT, і причину ПЕРЕПИСАНО 2026-09-06: доти тут стояло «CVE базового шару лікуються бампом образу» — це знято, бо OS-шар тепер патчимо МИ (base-стадійний `RUN`: `upgrade` — пакети самої бази, свіжий `install` — те, що тягнуть наші пакети; і це діє лише тому, що публікуюча збірка layer-кешу не читає: ⛔ `mirror-ghcr.yml` `no-cache: true`, а `no-cache-filters: base` на BuildKit ≥ v0.32 не каскадує → `06_07 §1a`). Присуд won't-do на HARD вистояв на ІНШІЙ нозі — `exit-code` сканера про GitHub-dismissal не знає, тож HARD вимагав би ignore-файлу, що дублює вже ратифіковані dismissal'и; повний присуд і ціна відмови → `06_07 §1a`; ⚠️ кореневий `.trivyignore` — базлайн IaC-місконфігів і для CVE інертний, свій потрібен лише при переході в HARD) · `terraform_drift.yml` — Ops·TF-Drift (weekly `plan -detailed-exitcode`, skip-clean до 3 secrets) · `ci.yml` `terraform_validate`-job (offline `validate`+`fmt`, path-gated `terraform/**`, pre-deploy config-validity — INF.15) · `mirror-ghcr.yml` · `release-please.yml` · `ci.yml` · `docs.yml` · `ssot_guard.yml` · `subgraph.yml` — **CI · Subgraph** [OPS.34/OPS.36]: `npm ci`→`graph codegen`→`graph build`→`graph test` (matchstick — семантика мапінгу, з 2026-08-28), path-gated через джобу `changes` (НЕ `on.pull_request.paths` — та форма вішала б required-чек «Expected» назавжди); **required-контекст «Subgraph passed» — девʼятий** (фліп 2026-08-30, `:required` у `workflow_gate_perimeter`)) |
| Deploy drift-guards | ⚠️ **`deploy_secret_scan` до 2026-08-30 був декоративним ЗА ВХОДОМ:** path-фільтр джоби (`alloy` в `ci.yml`) і `pre-push` (`^deploy/`) не містили ані `config/deploy*.yml`, ані `.kamal/**`, ані `terraform/compute.tf` — тобто **чотирьох із пʼяти власних предметів**, і config-only діф проходив із зеленим `CI passed`, не судивши нічого. Обидва носії розширено; **тримай перелік ≡ subject-сету в шапці скрипта**. CI-гейти над deploy-конфігом (offline, no-creds; НЕ дублюй їх логіку — правь дім): `scripts/deploy_secret_scan.rb` (Kamal-ланцюг + anchor `COAP_ENV`-heredoc, post-`OPS.37`: no-literal + signing-quintet job-only-і-поза-ГЛОБАЛЬНИМ `env.secret` + retired-tripwire + B3 canopy без успадкування квінтету (array-form, АБО hash із ВЛАСНИМ квінтет-масивом точного складу й безхостовим `coap` — з 2026-09-02, OPS.37) + `SUBJECT_FLOOR` проти парсер-колапсу + інваріант C над **ДВОМА** ignore-файлами (`.dockerignore` тримає секрет поза публічним ОБРАЗОМ, `.gitignore` — поза публічною ІСТОРІЄЮ; другий додано 2026-09-01 [S1.1] заради `gha-creds-*.json`, тобто ЖИВОГО WIF-креденшела, і пара не надлишкова: build-контекст І Є робочим деревом, тож жоден із двох не імплікує іншого) + present-empty Invariant D + `_DSN` у `SECRET_NAME` + **B5 [INF.27, 2026-09-02]: голий bash-дефолт `${VAR:-…}` заборонений в обох `.kamal/secrets*` — Kamal парсить їх Dotenv'ом, який калічить його в `<value>:-…}`; A приймає лише `LOUD_REF`-форму `$(printf '%s' "\${VAR:-MARKER}")`. ⚠️ Текстовий B5 — лише tripwire: парсер-виконаний носій — `spec/deploy/kamal_secrets_parse_spec.rb` (обидва файли через `Kamal::Secrets`, set/unset), і саме тому `.kamal/**` додано в `ruby`-фільтр `ci.yml`**) · `spec/db/solid_structure_files_spec.rb` (`:sql`-деривація `db/{cache,cable}_structure.sql` + раунд-тріп через `psql`; до 2026-09-02 обидві Solid-бази створювались ПОРОЖНІМИ) · `scripts/audit_deploy_secret_scope.rb` (S1.1 — live `gh`-scope preflight: money-quintet env-only · retired-zombie · WIF=Variables · Kredis instance-override footgun — present-empty глушить фолбек на `REDIS_URL`) · `spec/deploy/*_spec.rb` (INF.16 db-config · INF.17 coap.env boot-contract · INF.4 firmware↔host · DR.1 DR-posture · INF.12 ENV.fetch↔deploy declaration + B1-chain · INF.12-behavior web3-env-loudness (кожен web3-ENV ∈ guard-set ∪ LOUD ∪ SOFT — silent-class tripwire) · SEC.22 credentials-ENV-first · S2.4 alloy-scrape-topology · S2.4 grafana-alerts↔REGISTRY-parity (silkennet_-метрика в alert-expr ∈ REGISTRY, typo→dead-alert; ⊕ **slot-ізоляція** — панель несе `{slot=~"$slot"}`, агрегація алерту `by (slot…)`; ⊕ `import.rb --verify` оголошений read-only, і це тримає спека, не обіцянка) · OPS.11 tf-workflow-var-parity · **S1.1 deploy-workflow-parity** — механізм-паритет двох deploy-воркфлоу: ПОСЛІДОВНІСТЬ кроків джоби `Kamal Deploy (…)` + `env:`-ключі спільних кроків, із поіменним винятком на сам крок `Kamal Deploy` (там розходження законне — money-квінтет; його ланцюг судить `env_fetch_declaration` прикладом «delivery half»). Заведено після того, як фікс трьох механізм-кроків поїхав в ОДИН воркфлоу з двох) · 🆕 **OPS.28 `scripts/shell_parse_check.rb`** — `bash -n` над КОЖНИМ shell-артефактом дерева, включно з шеллом усередині terraform-heredoc-ів (`terraform validate` бачить тіло як непрозорий рядок, `actionlint` читає лише `run:` у воркфлоу). Субʼєкти ВІДКРИВАЮТЬСЯ (git + shebang), не перелічуються. HARD у `ci.yml` (джоба `shell_parse`) **і** в `.githooks/pre-push`. ⛔ Оголошено РАТЧЕТОМ: улов на момент побудови НУЛЬ, зелене НЕ означає «шелл коректний» — лише «bash його розбирає»; семантика, `sh`-vs-bash і вміст `${…}` поза ним. Несе власну батарею `--selftest`, і вона не оздоба — дві його трансформації не мають свідка в живому корпусі, обидві були зламані при написанні, і корпусний прогін мовчав |

## Gotchas (верифіковані, не з канону)

**Тіла — у [`gotchas.md`](gotchas.md); відкрий його, перш ніж запускати деплой, імпорт, drift-план,
консольний зонд чи прилад на живому слоті.** Один згенерований рядок на гочу; номери — адреси
(`6a` — окремий пункт), цитуй `deploy §Gotchas #N`.

<!-- DEPLOY-GOTCHAS-INDEX:AUTO — generated from gotchas.md by `ruby scripts/guard_craft_index.rb --write`; edit rules THERE, never here -->

1. jemalloc через `LD_PRELOAD` у Docker-образі не прибирай без бенчмарку
2. `SENTRY_DSN` задається at deploy time, і без нього Sentry інертний — нуль crash-репортів
3. Старт через Thruster — дефолт, і він overridable at runtime
4. WIF рантайм = ТРИ GCP API, і `sts` та `iamcredentials` вмикаються лише ЯВНО
5. keyless AUTH ≠ terraform-apply CAPABILITY — CI імперсонує least-privilege deploy-SA БЕЗ IAM/WIF/serviceusage-admin, тож рефреш IAM/WIF-ресурсів дає 403
6. `gh run watch --exit-status` бреше (exit 0 on fail / 1 on empty) — щоб перевірити, чи Deploy·Canopy/Production реально пройшов, довіряй `gh run view --json conclusion`, не `watch`
6a. `conclusion: failure` теж бреше — не про факт, а про ПРИЧИНУ, і саме ця брехня маскує справжній червоний
7. `gh attestation verify` рендерить TTY-only → piped/`tail`/`grep` захоплюють ПОРОЖНЄ; довіряй EXIT=0 або `--format json`
8. Живі прогони `import.rb` знайшли вже ШІСТЬ дефектів, яких `--dry-run`/`--verify` не бачать ЗА ПОБУДОВОЮ
9. `terraform fmt -diff` РЕНДЕРИТЬ `terraform.tfvars` — тобто друкує `db_password` у відкритому вигляді
10. Console-доступ: дорогу ВИМІРЯНО 2026-09-02 — read-only `rails runner` через `gcloud compute ssh --tunnel-through-iap` + `sudo` `docker exec` працює з ноутбука, `kamal app exec` звідти падає на posix-акаунті SA (`06_01` ops-блок); інтерактивна консоль ще не виконувалась
11. `gcloud sql instances clone` після ~10 хв друкує «failed … taking longer than expected» — це клієнтський таймаут, не вердикт
12. Скрипт анкера живе в `metadata.startup-script` з 2026-09-03 (⚖️ founder B, INF.17): зміна скрипта чи піна образу відтоді in-place + `reset`
13. Детектор «чи змінилось релевантне» судить БАЗУ, не HEAD — і в ОБОХ воркфлоу
14. Три deploy-day факти, кожен виміряний 2026-09-03, і жоден не видно з зеленого воркфлоу
15. Чотири гейти дня 2026-09-03 були зелені на речі НЕ ТОГО РОДУ — і кожен закрито формою, не значенням
16. `spl-token` фізично не працює за TLS-перехоплювальним проксі, і це властивість БІНАРЯ, не мережі — а сусідні інструменти в тій самій оболонці працюють, тож симптом читається як «зламався Solana»
17. Діагностичний зонд через `bin/rails runner` на ЖИВОМУ слоті не є read-only щодо каналу помилок: його raise стає issue в Sentry під ПРОДОВИМ тегом релізу
18. Двічі поспіль я міряв cron не тим приладом, і обидва рази отримав хибне «немає»
19. Рунбук може бути роззброєний власним ЗАГАРТУВАННЯМ, і тоді він бреше саме в аварії
20. `import.rb --verify` судив НАЯВНІСТЬ правильно, але текст навколо неї брехав про ПОХОДЖЕННЯ — і не міг інакше, бо імпорт ОДНОСТОРОННІЙ
21. Після `drop` + `reseed` УВЕСЬ DeadSet стає недійсним ЗА ПОБУДОВОЮ, і «Retry All» перетворюється з марного на ШКІДЛИВИЙ
22. `gh secret set` доїжджає НІКУДИ, доки змінна не проведена ПʼЯТЬМА поверхнями — і три з них знаходить гейт, не автор
23. `timeout N docker exec …` НЕ ставить стелі процесу — вона вбиває КЛІЄНТА, а робота всередині контейнера їде далі
24. «Тривога, що звучить ЗАВЖДИ, не звучить ніколи» — і на демо-слоті це не метафора, а щоденний механізм
25. Діф каже «розбіжність у 100 % елементів» → підозрюй ПАРСЕР, а не предмет
26. Ключ ≠ баланс: presence-чек секрету зелений при непрацездатній нозі
27. Мертвий писач НЕ прибирає ряд — він його МОРОЗИТЬ, тож «серія є» ніколи не є доказом живого приладу
28. Вимикаєш ногу свідомо — перечитай ОПИСИ її алертів: вони написані для світу, де вимкнення є ІНЦИДЕНТОМ, і накажуть оператору скасувати щойно ухвалене рішення

<!-- /DEPLOY-GOTCHAS-INDEX -->

## Робочі правила

1. **Docs-first.** Прочитай `06_0N` (саме *чому* + поточний стан/TRL) перед зміною
   деплою, секрету чи метрики — кожен 06-док несе власний member-TRL у ✅ Статус.
2. **SSOT One-Home.** Правиш факт — правь у його домі (`06_04` секрети, `06_03 §2.8`
   метрики, `terraform/` config), не тут. Skill лишається тонким маршрутом.
3. **Гейти.** Після правок канону — `bin/rails docs:check_refs` зелений; робота над
   SSOT-доками 06_xx — через skill `ssot-maintenance`.
