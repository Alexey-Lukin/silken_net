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
| **Resilience** — Queen failover (4 рівні) + Per-Chain Fallback Matrix (✅ **у маніфестах з 2026-09-02, виміряно на canopy** — keyless публічні фолбеки PublicNode/dRPC/офіційний Solana в `env.clear` обох маніфестів, canopy — testnet-двійники; чейн фолбеків судить гард `RPC_FALLBACK_URL_ENVS`; `ARCH.114` ⚖️ founder: акаунтний вендор лише якщо вкусять rate-limit-и) + **топологія черг Sidekiq** (`§2.5` — anti-starvation через ізоляцію ПРОЦЕСІВ, не перестановку черг; flip = `sidekiq -q`-прапори в deploy-конфізі, тобто deploy-рішення, НЕ код) | `06_08` |

## Несучі інваріанти (не очевидні з коду)

Будь-хто, хто чіпає деплой, МУСИТЬ це знати (суть тут, механіка — за canon-§):

- 🔴 **Redis = Upstash, ОДИН інстанс на слот, регіон обирається ПРИ СТВОРЕННІ й ніколи потім** (`silkennet-canopy` у `europe-west1`; production-інстанс ще не існує — упирається в тариф, і межа Free — за КОМАНДАМИ, не інстансами: 500 k/міс проти ≈12.7 M/міс ПОРОЖНЬОГО Sidekiq `-c 4` — brpop/heartbeat/poll самого Sidekiq, виміряно 09-02, 00_07 `INF.28`; job-роль на Free вмирає за ~1.2 доби з `ERR max daily request limit exceeded`, і `/ready` → 503 для ноди). Multi-zone Global DB — НЕ план, а ескалація з названим тригером: повторюваний день-у-день `sn-alert-m2m-nonce-fallback`/`-qatt-` на production (разовий blip = ні). Дім тригера й критерію — [`06_01`](../../../docs/06_01_Deployment_Kamal_Terraform.md) рядок Upstash у §«Хто може вимкнути НАС» + [`04_03 §5.15`](../../../docs/04_03_REST_API_v1_Reference.md); провенанс — `00_07` S6.1 §🗄️. Той, хто його закриє, читає ЦЕЙ скіл, а не §04 — тому вказівник стоїть тут.
- 🧰 **`gcloud` — передумова ШЕСТИ кроків дня, а не першого; і до 2026-08-31 її не називала
  ЖОДНА фаза.** Виміряно того дня: SDK на машині власника не було взагалі, а Фаза −1 перелічує
  **акаунти** (те, що заводять у браузері) — рунбук же говорить із **CLI**, і різницю видно
  лише коли впираєшся. Залежні кроки: `terraform/bootstrap.sh` · ADC для `terraform apply` ·
  SSH на анкер для `coap.env` · `add-metadata`+`reset` · AR-токен для `kamal` push
  (`gcloud auth print-access-token`) · `ssh.proxy_command` IAP-тунелю, без якого `kamal deploy`
  **фізично не досягає** app-хоста без зовнішньої IP. 🔑 **І логінів ДВА, вони НЕ дубль:**
  `gcloud auth login` кладе user-credentials (їх уживає сам gcloud), `gcloud auth
  application-default login` кладе **ADC** — і terraform читає ЛИШЕ другий. Доти `bootstrap.sh`
  перевіряв ПЕРШИЙ, а радив ДРУГИЙ, тобто його ✅ проходив на креденшелі, який наступний крок
  не вживає; тепер пінить обидва окремо. Перелік тулчейну (+ ланки з ВЛАСНИМ: `solana`/
  `spl-token` для Devnet, `arm-none-eabi`/`STM32_Programmer_CLI` для Фази 6) — [`06_01
  §DEPLOY-DAY`](../../../docs/06_01_Deployment_Kamal_Terraform.md) Фаза −1а.
- ⛔ **`§Quickstart` у `06_01` БІЛЬШЕ НЕ ІСНУЄ — не шли туди нікого** (⚖️ 2026-08-31). Це була
  ТРЕТЯ копія процедури, і саме вона протухла, при цьому читалась першою: наказувала класти
  `POSTGRES_HOST`/`POSTGRES_USER` у `secrets-common`, де їх немає; пропускала девʼять із 32
  імен (серед них `CANOPY_REDIS_URL`, без якого canopy сідає на невалідний Redis при ЗЕЛЕНОМУ
  деплої); не мала фаз контрактів узагалі — тобто послідовність гарантовано давала впалий бут.
  **Єдиний носій — `§DEPLOY-DAY`**; його ж називає `DEPLOY-1` («ОДИН носій верифікацій»).
- **CoAP-інтейк: PRIMARY = демон на Ingress Anchor** (docker+systemd, приватний IP Cloud SQL
  БЕЗ Auth Proxy; секрети `/etc/silkennet/coap.env`, НЕ metadata). Kamal `coap`-роль
  (`config/deploy.yml`) = дормантний **fallback** (перемикання 2×systemctl); money/web
  лишаються на Kamal/GCP. **coap.env** = окрема boot-contract поверхня (pure UDP glue,
  нуль key-derivation → несе AR-encryption-трійку, **НЕ** `PROVISIONING_MASTER_KEY`;
  guard `spec/deploy/anchor_coap_env_spec.rb`). ⚠️ **Це твердження про АНКЕРНУ поверхню, не про «coap» узагалі** — дормантна Kamal-роль `coap` вище не має `env:`-оверрайду, тож успадковує ГЛОБАЛЬНИЙ `env.secret` РАЗОМ із `PROVISIONING_MASTER_KEY` (per-role secret-exclude у Kamal немає; названо й прийнято над самою роллю в `config/deploy.yml`). Ризик відкривається лише активацією fallback-ролі — але читач, що бачить у цьому ж пункті ОБИДВІ coap-поверхні й одне PROVISIONING-твердження, узагальнить його на обидві. → `06_01` / `06_04 §5.7`.
- **Cloud SQL Auth Proxy авторизує через Google API — це ОРТОГОНАЛЬНО мережевій
  досяжності, не заміняє її.** Обидва інстанси `terraform/database.tf` тепер
  `ipv4_enabled = false` (private-only). Kamal деплоїть УСЕРЕДИНІ GCP VPC, тож
  з'єднання йде на **приватний IP напряму**, без проксі. Сам `cloud-sql-proxy`
  знято з рантайму (`Dockerfile` + `bin/docker-entrypoint`, `OPS.37`) — сьогодні
  він лишається лише **break-glass**-інструментом із робочої станції (👤;
  IAM-авторизація й мережева досяжність там — досі дві окремі речі).
  → `terraform/database.tf` at-use.
- 🔴 **`deletion_protection` — ДВА РІЗНІ ЗАХИСТИ ПІД ОДНИМ СЛОВОМ, і на Cloud SQL стояв лише
  один** [DR.1, виміряно на ЖИВОМУ інстансі 2026-08-31]. На `google_sql_database_instance`
  однойменний аргумент є **мета-аргументом TERRAFORM**: спиняє лише `terraform destroy` і про
  GCP не знає нічого. Окремий `settings.deletion_protection_enabled` — **API-прапорець самого
  Cloud SQL**, і ЛИШЕ він спиняє `gcloud sql instances delete`, кнопку в консолі й прямий
  виклик. Живий інстанс ніс перший і не ніс другого: база з усіма продовими даними знімалась
  однією командою за бездоганним конфігом, а канон описував захист як наявний — бо описував
  ІНШИЙ із двох. ⊥ **На `google_compute_instance` слово те саме, а механізм ІНШИЙ:** там
  аргумент мапиться прямо в API, тож один прапорець покриває обидва шляхи (обидві VM теж
  стояли на провайдерському дефолті `false`). Усі чотири ресурси тепер на
  `var.enable_deletion_protection`; носій — `spec/deploy/database_dr_posture_spec.rb`.
  ✅ **ЗАСТОСОВАНО й звірено на ЖИВОМУ API 2026-09-01**, не заявою terraform
  (`settings.deletionProtectionEnabled` + `deletionProtection` віддають `True`).
  ⚠️ «Чотири» лічить КОНФІГ — живих **три**: репліка умовна (`db_read_replica_count = 0`)
  і в стейті її немає, тож диф «конфіг 4 ⊥ план 3» не є пропущеним ресурсом.
  ⚠️ Із задокументованою економією (Фаза ∅) не конфліктує: та ЗУПИНЯЄ компʼют
  (`activation_policy=NEVER` / `desired_status=TERMINATED`), вона нічого не видаляє.
  🔑 **Рефлекс, ширший за випадок: побачив прапорець безпеки — питай не «чи він увімкнений»,
  а «скільки їх під цим іменем і на який із них я зараз дивлюсь».** → [`06_06`](../../../docs/06_06_Disaster_Recovery_and_Backup.md) §Posture-guard.
- **Observability = Alloy → Grafana Cloud SaaS; self-hosted Prometheus НЕ потрібен (OBS.1).**
  Реєстр **in-process** → web:80 НЕ бачить job/coap-інкрементів напряму → Alloy МУСИТЬ
  скрейпити **три таргети, по одному на процес** (web/job/coap, лейбл `process`) — цей
  КОНТРАКТ незмінний. ⚖️ **Адресацію РАТИФІКОВАНО [OPS.37 2026-08-30]: per-role
  `network-alias` у спільній docker-мережі `kamal`** (`silken-web:80`/`silken-job:9394`/
  `silken-coap:9395`; `servers.<role>.options` ідуть дослівно в `docker run`, accessory в
  тій самій мережі за замовчуванням). Алias — не порт: у роллінг-вікні обидві версії ділять
  його легально (виміряно), тож клас «publish ламає роллінг» сюди не переноситься; canopy
  скрейплених аліасів НЕ має за побудовою (власні `canopy-*`, дизʼюнктні — OPS.37 09-02), тож у прод-серії
  не вливається. ⛔ Відхилено з виміром: `options.publish` (зламав роллінг, відкочено
  08-29) ⊥ docker-socket прямий чи через socket-proxy (haproxy-шаблон гейтить весь
  `/containers` одним regex → inspect із `Config.Env` нероздільний від list = env-read
  money-квінтета job-ролі). Обидві половини стереже крос-файловий пін
  `spec/deploy/alloy_scrape_topology_spec.rb`; пускач accessory = крок «Ensure Alloy
  accessory is running» в обох deploy-воркфлоу (`kamal accessory boot` ідемпотентний;
  зміна `config.alloy` → свідомий `kamal accessory reboot alloy`).
- 🔴 **ALLOY-КОНТЕЙНЕР ОДИН НА ДВА СЛОТИ — тож `accessory boot` НІКОЛИ не беруть із
  `-d <destination>`** (⚖️ 2026-08-31; звірено з джерелом kamal 2.12, не виведено).
  `Kamal::Configuration::Accessory#service_name` = `"#{config.service}-#{name}"`, а
  `config.service` **не несе destination** (`service_and_destination` існує, але вживається
  лише для каталогу застосунку) ⇒ обидва призначення дають `silken_net-alloy`; canopy
  перевизначав лише `env.clear`, тож `host` лишався базовим ⇒ той самий контейнер на тому
  самому хості. А `kamal accessory boot` ідемпотентний **ПРОПУСКОМ** («Skipping … a container
  already exists», жовтим, exit 0) ⇒ мітку `DEPLOYMENT_SLOT` вигравав слот, що встиг ПЕРШИМ
  (canopy на кожен push проти релізу), тобто продові серії їхали б із `slot="canopy"`.
  🔑 І це була чиста втрата: canopy скрейпу не має — до 2026-09-02 alias-less (масив-форма
  `servers:`), відтоді його ролі несуть ВЛАСНІ аліаси `canopy-web`/`canopy-job`, **дизʼюнктні**
  зі скрейпленими (`alloy_scrape_topology_spec`, OPS.37). ⛔ Не «полагодити» це
  окремим `service:` для canopy — два агенти скрейпили б ТІ САМІ продові аліаси й дали
  подвійні серії з різними мітками. ⚠️ Залишок названо: canopy не може «не оголосити»
  успадкований accessory (deep_merge = keys-UNION), тож `kamal setup -d canopy` підняв би
  його — Фаза 3 свідомо каже `kamal deploy -d canopy` (той accessories не чіпає,
  `boot_accessories: false`). Носій — `alloy_scrape_topology_spec` §«the ONE-Alloy invariant».
- 🔴 **`BOOT_CRITICAL` — це єдине місце, де порожній секрет стає ГУЧНИМ; ланцюг `secrets-common`
  + workflow-`env:` доводить лише, що ІМʼЯ резолвиться** [INF.4, 2026-08-31]. Виміряний
  інстанс — пара `TLS_ORIGIN_{CERT,KEY}_PEM`: `secrets-common` її оголошує, тож
  `Kamal::Secrets#[]` не кидає «Secret not found», а віддає **порожній рядок**;
  `Kamal::Cli::App::SslCertificates#run` гардить формою `if cert_content = …`, а `""` у Ruby
  **істинний** ⇒ kamal завантажує ПОРОЖНІ `cert.pem`/`key.pem` (0644), проксі не віддає TLS,
  CF у `Full (strict)` відповідає 521/525 — **за цілком зеленим деплоєм**. **Рефлекс: додаючи
  секрет, чия ВІДСУТНІСТЬ ламає рантайм тихо, клади його в `BOOT_CRITICAL`, а не лише в
  ланцюг** — інакше він не дає навіть `::warning::`.
  🔴 **ВИДІВ ЦЬОГО КЛАСУ ДВА, і рефлекс вище лікує лише ПЕРШИЙ — виміряно другим інстансом
  2026-09-01 (`TURBO_SIGNED_STREAM_KEY`, [SEC.25 Ф3], S1.1).** Розрізняє їх те, що робить
  ВІДСУТНІСТЬ значення: **(і) бут падає гучно** (пара `TLS_ORIGIN_*` вище) ⇒ лік = `BOOT_CRITICAL`;
  **(іі) не падає нічого, фіча тихо деградує** — `turbo_stream_verifier.rb` читає `ENV[…].presence`
  і за `nil` деривує ключ із `secret_key_base`, тож застосунок працює, а важіль відкликання просто
  не існує. ⛔ Для (іі) `BOOT_CRITICAL` НЕ є ліком: гучним робити нема чого, бут коректний.
  Лік — статичний CI-гейт, скоуплений на КРОК доставки (`env_fetch_declaration_spec`, приклад
  «delivery half»: глобальний `env.secret` ⊆ `env:` кроку `kamal deploy`, ПО КОЖНОМУ воркфлоу).
  🔑 **Отже питання при заведенні секрета не «класти в `BOOT_CRITICAL`?», а спершу «що станеться,
  якщо значення НЕ доїде» — і лише відповідь обирає носія.** Другий інстанс прожив за зеленим
  ланцюгом рівно тому, що ланцюг питав «змаплено хоч ДЕСЬ», а не «доїжджає до контейнера»:
  мапінг у джобі `verify-secrets` задовольняв його за спиною кроку, що доставляє.
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
  чи безпековому шляху «діагностична» УЗАКОНЮЄ діру. Виміряно тим самим проходом — три
  діри спокусливо читались діагностичними, і всі три дістали споживача: `lineage_root_failures_total`
  (кредит виданий, witness-корінь NULL) · `fw2_fc_degraded_reports_total` (nonce-гарантія
  вузла відпала, прошивка передає далі) · `telemetry_archive_unpinned_depth` (таймер до
  незворотної втрати MRV-доказу). Money-половину цього дзеркала закрито 2026-08-25
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
- 🔴 **DEFAULT-партиція є єдиною, чия НЕПОРОЖНІСТЬ ламає обслуговування незворотно** (ARCH.70, виміряно експериментом 2026-08-28). Щойно в DEFAULT-лист осів рядок місяця N, `CREATE TABLE IF NOT EXISTS … PARTITION OF` для місяця N падає `PG::CheckViolation` НАЗАВЖДИ, повідомлення НЕ містить `already exists` → `PartitionMaintenanceWorker` re-raise, і **ретраї не лікують**, бо стан сам не змінюється. Каскад: прохід падає на першій таблиці, решта не дістає партицій НАСТУПНОГО місяця, а семпл гейджів стоїть ПІСЛЯ циклу — три ARCH.70-алерти замерзають разом. Прилад-попередження `silkennet_partition_default_occupied` (0/1, `EXISTS` а не `count` — рішення оператора від кількості не залежить, а скан розрослого DEFAULT коштував би саме в інциденті) + `sn-alert-partition-default-occupied`; **рунбук із точними SQL-кроками — [`06_06 §5.5`](06_06_Disaster_Recovery_and_Backup), і порядок там несучий** (створити партицію ДО `DETACH` неможливо — це і є сам дефект). ⚠️ Сусідній `silkennet_partitions` лічить ЛИСТИ, а не «місяці історії»: серед них завжди DEFAULT плюс УСЕ вікно воркера, а те з 2026-09-01 накриває попередній+поточний+наступний — тобто поправка зросла (доти тут стояло «на 1-2», при вікні `current+next`). ⛔ Числа не переписуй — бери вікно з `PartitionMaintenanceWorker#perform`, бо воно вже одного разу змінилось: попередній місяць додано тому, що `db:seed` (`73.hours.ago`) і load-test датують записи минулим, і 1-3 числа вони цілили в місяць, якого вікно не накривало. Поправка — [`06_03 §2.8`](06_03_Prometheus_Observability), і саме на цьому числі стоїть ⚖️ ширини вікна ретеншну.
- 🔑 **`production` НЕ є відповіддю на питання «до якого чейну слот має право торкатись» — осей ДВІ [OPS.37, 2026-08-30].** Токен ніс одночасно «загартований рантайм» і «це справжні гроші», а стейджинг потребує ПЕРШОГО БЕЗ ДРУГОГО (canopy біжить під `RAILS_ENV=production` свідомо). Розщеплення мусило торкнутись **ОБОХ плечей** `Rails.env.production? ∨ WEB3_STRICT_MODE`: тригер загартування лишився на парі, гроші поїхали на нову вісь `WEB3_CHAIN_ENV` ∈ `mainnet`/`testnet` усередині `Web3NetworkGuard` (поруч із `signer_process:`, скоупить рівно `chain_violations`). ⛔ **Не bypass:** значення є дзеркальними ТВЕРДЖЕННЯМИ про проводку — testnet-слот на mainnet-ендпоінті падає так само гучно, як навпаки; відсутнє → `mainnet`; нерозпізнане → власне порушення. Дім механіки `04_02 §Web3NetworkGuard`, змінної — `06_04 §2.1`, стану testnet-слоту — 00_07 `INF.27`. ⚠️ **Наслідок для деплой-дня, який доти суперечив сам собі:** гард судить адреси там, де їх ЧИТАЮТЬ — presence і формат однаково, по-змінному через три класи (з 2026-09-02, [INF.27] Q3: web валить бут на плейсхолдері SCC, бо СПРАВДІ читає її через `ChainAuditService`; job — на будь-якій із трьох; дормантна `coap`-роль — на жодній) → контракти деплояться ПЕРЕД першим підйомом слоту, на чейні, який слот оголошує (`06_01 §DEPLOY-DAY` Фаза 2t/2). Рунбук доти звав Фазу 2 «паралельною до Фази 3». ✅ **Canopy оголошено `testnet` 2026-09-02 (Amoy-адреси в маніфесті, RPC-квартет ремаплено з `CANOPY_*`-двійників формою B4 — `deploy_secret_scan` судить усі пʼять ремапів).** ⊕ RPC-сестра адрес — `SILENT_RPC_ENVS` (`[rpc]`, [INF.27] Q1): `ALCHEMY_POLYGON_RPC_URL` presence на job і web, бо `ChainAuditService` ковтає її відсутність у той самий rescue.
- 🔴 **«TLS термінує Cloudflare» — правда про КЛІЄНТСЬКЕ плече й пастка про друге [INF.4, виміряно 2026-08-30].**
  CF стоїть у **`Full (strict)`** на обох зонах (прочитано в живому дашборді), а той вимагає
  **валідного сертифіката НА ORIGIN**. Origin його не має: HAProxy анкера — `mode tcp` на 80 і
  443 (чистий прохід, нічого не термінує), а `proxy:`-блок був закоментований в обох
  маніфестах → перший же запит крізь CF дав би **521/525**. ⚠️ **521 має й ДРУГУ причину, виміряну 2026-09-02, коли пара вже була заведена: анкер БЕЗ HAProxy** (startup-script помер на sysctl → whiptail → dpkg-interrupted; три ланки — `06_01` крок 10) — тож 521 читай спершу як «origin не існує», і лише потім як «сертифікат». ⊕ Рефлекс оцінки ЧУЖОГО числа (план CF, 2026-09-01): величина, чиї циркулюючі версії розходяться на три порядки («ліміти Free»: 100 ⊥ 100 000), є фольклором, а не виміром — присуд виносить ВІДСУТНІСТЬ механізму (WS-стелі як категорії в доках CF немає), а не порівняння з профілем. ✅ **Сертифікатну діру закрито 2026-08-31:**
  `proxy:` живий в обох, пара Origin CA стоїть у базовому маніфесті, canopy успадковує `ssl:`
  deep-merge-ом (вайлдкард `*.silkennet.app` покриває обидва слоти), обидва секрети заведено.
  ⚠️ Час минулий тут несучий — механізм лишається чинним застереженням, стан ні. ⛔ **Let's Encrypt не лік і це структурно:** під
  `Full (strict)` CF ходить на origin ЛИШЕ по HTTPS, тож HTTP-01 не доставляється; сірий
  хмарник спрацює один раз, а поновлення тихо впаде через 90 днів — `ssl: true` лишається
  шляхом TLS-fallback БЕЗ CF. ✅ Лік — **Cloudflare Origin CA** (15 років, `Full (strict)`
  приймає за визначенням), один wildcard `silkennet.app` + `*.silkennet.app` на обидва слоти;
  kamal 2.12 бере пару як **імена kamal-секретів** у `proxy.ssl.{certificate_pem,private_key_pem}`,
  не шляхи. Пʼятиходовий контракт виписано над ключем `proxy:` у `config/deploy.yml` (там дім —
  бо крос-реф не можна розкоментувати), ходи (2)+(3) енфорсить `env_fetch_declaration_spec`.
  🔑 **ФОРМА випуску важливіша за сам випуск, і дефолт CF тут гірший:** «Generate private key and
  CSR with Cloudflare» родить приватний ключ **на серверах вендора**; бери «Use my private key and
  CSR» — `openssl req` локально, CF підписує лише CSR, ключ машину не покидає. ✅ Випущено
  2026-08-31 у цій формі. **Приймальна перевірка — збіг МОДУЛЯ** (`x509 -modulus` ⟷ `rsa -modulus`,
  обидва через `sha256`), а не «виглядає як сертифікат»: підпис ЧУЖОГО CSR інакше виявиться аж на
  першому рукостисканні. Сертифікат ПУБЛІЧНИЙ за природою — секрет лише як форма доставки; ключ
  має НИЖЧУ планку зберігання за master-ключі (перевидається безкоштовно) → `06_01 §Сертифікат НА ORIGIN`.
  ⚖️ **Canopy теж на TLS** (founder 2026-08-30) — він ПЕРШИЙ рендер основного шляху, тож
  HTTP-слот репетирував би деплой повз зламану ланку; опція «кука по HTTP» ВІДКЛИКАНА.
  → `06_01 §Сертифікат НА ORIGIN` / `06_04 §2.1` / 00_07 `INF.4`.
- 🔑 **`DEPLOYMENT_SLOT` — третя вісь поруч із `WEB3_STRICT_MODE` і `WEB3_CHAIN_ENV`, і питання в неї власне: «який це ДЕПЛОЙ» [INF.27, 2026-08-30].**
  Обидва слоти біжать `RAILS_ENV=production` (canopy свідомо), тож `Rails.env` слотів НЕ
  розводить, і кожна поверхня, що ним МІТИТЬ спільний зовнішній ресурс, штампувала `production`
  двічі — **хибна мітка, не порожня**. Змінна не нова (народилась для accessory Alloy); тепер
  вона й у глобальному `env.clear`, читач One-Home — `config/deployment_slot.rb` (фолбек
  `Rails.env`, тож dev/test чесні). Споживачі: Sentry-`environment` · namespace кешу · обидва
  бакети ActiveStorage · поле `slot` JSON-логу · два boot-гарди. ⛔ Ніколи голим
  `ENV.fetch("DEPLOYMENT_SLOT")` — шаблон `coap.env` анкера несе її лише з 09-02, а файл
  створюється РАЗ (заповнений раніше анкер = фолбек `production` мовчки). Носій —
  `spec/deploy/deployment_slot_axis_spec.rb`. → `06_04 §2.1` / `06_03 §2.9`.
- 🎰 **Інтейк: анкер ОДИН, демон ОДИН, слот = три рядки `coap.env` + `systemctl restart coap-daemon`
  [OPS.37 ⚖️ founder 2026-09-02].** `DEPLOYMENT_SLOT` · `POSTGRES_DATABASE` · `REDIS_URL`; решта
  значень слот-інваріантна. До першого production-деплою демон годує canopy — і це виконуване
  сьогодні, бо кожне canopy-значення вже існує. ⛔ Другого publisher-а UDP 5683 (canopy `coap`-роль
  на спільному хості) НЕ підіймати; ⚫ тумблери super_admin для CoAP/симулятора — won't-do роду
  КОНСТРУКЦІЯ: обидва — процеси на ІНШИХ машинах (systemd-unit анкера · foreground-скрипт у
  job-контейнері), web-процес актуатора над ними не має, а прапор без актуатора = самосвідчення.
  Приймальний рядок демона — `Listening on coap://0.0.0.0:5683 slot=<слот>` (до 09-02 рунбук
  цитував рядок, якого код не друкував); доказ слоту — рядок у БД ТОГО слоту, не лог. Симулятор
  (`bin/forest_simulator` = емулятор Королеви, ключі з БД слоту) — з будь-якого контейнера canopy
  (web, доки job-роль не піднята) на `ingress_private_ip` через `SIMULATOR_COAP_URL`. → `06_01 §DEPLOY-DAY` Фаза 1/4 · 00_07 `INF.17`.
- 🔴 **`${VAR}` в `env.clear` = ПОРОЖНІЙ рядок у контейнері, не значення** [S2.4/DEPLOY-1 Ф4, виміряно на canopy 2026-09-02]. Kamal не інтерполює `env.clear` — він емітить `--env VAR="${VAR}"` усередині `docker run`, який виконує ЧЕРЕЗ SSH, тож розгортає ВІДДАЛЕНИЙ shell на хості, де змінної нема. Так `RELEASE_VERSION` приїжджав `""`, Sentry відкидав release на кожній події, а маніфест, обидва воркфлоу й канон казали «CI-set». Значення з shell, що деплоїть, іде лише ERB-ом (`<%= ENV[...] %>`); версію контейнера Kamal дає сам (`KAMAL_VERSION`, `KAMAL_CONTAINER_NAME`, `KAMAL_HOST`) — читай її, не обіцяй свою. Носій — `spec/deploy/kamal_config_validity_spec.rb` («жодного `${` в env.clear»). ⊕ Той самий рід, що present-but-empty вище: `.presence` на читачі обовʼязковий, бо порожнє «є» істинне.
- 🔴 **`egress-policy: block` живе ЛИШЕ на трьох джобах `deploy.yml`, і allowlist там ВИМІРЯНА, не написана** [OPS.36, 2026-09-02]: StepSecurity дає рекомендовану політику per-job із baseline реальних прогонів (сторінка insights прогону → Recommendations), і саме вона стоїть у воркфлоу з поясненням кожного імені. Новий endpoint валить крок ГУЧНО — лік = рядок в allowlist, ніколи відкат в `audit`. Production фліпає після ВЛАСНОГО першого деплою (правило INF.10). ⚠️ Агент harden-runner уміє не дописати baseline (`TimeoutError` до `agent.api.stepsecurity.io`) — «Insights not generated» на сторінці прогону означає рівно це, не «ще рахує». → `06_07 §1a`.
- **Секрети One-Home:** канонічний дім — `config/deploy.yml env.secret`; повний
  інвентар + checklist — `06_04`. CI-гейт `verify-secrets`. ⚠️ **Але «env.secret» — не весь
  ланцюг:** `registry.password` і `proxy.ssl.{certificate_pem,private_key_pem}` теж є іменами
  kamal-секретів і теж потребують `$VAR` у `secrets-common` + ключа в `env:` обох воркфлоу.
- **SSH на ОБИДВІ машини = IAP-тунель + OS Login, keyless (INF.20 (в)).** Порт 22 в інтернет
  НЕ відкритий; SSH-секретів у deploy-наборі НЕМАЄ; вхід `gcloud compute ssh silken-net-ingress
  --tunnel-through-iap` (доступ = tf-var `iap_admin_members`). 🔴 **Для app-хоста це не «теж», а
  ЄДИНИЙ шлях** (post-`OPS.37`): він без зовнішньої IP, і тег `web-nodes` на ньому стоїть рівно
  заради `allow_iap_ssh`. ⚠️ Тут висить Kamal-нога (б)-клею, і ходів у ній **ПʼЯТЬ**, не чотири —
  повний контракт виписано БАЙТАМИ над ключем `ssh:` у `config/deploy.yml` (не рефом: крос-реф
  не можна розкоментувати). ✅ **УСІ ПʼЯТЬ ХОДІВ ДОВЕДЕНІ ЖИВИМ `kamal deploy` 2026-09-01; 2026-09-02 доведено й сам БУТ, холодний `db:prepare` на трьох базах і шлях крізь Cloudflare (`00_07` DEPLOY-1)** (серія прогонів `Deploy · Canopy`; розбір — [`00_07`](../../../docs/00_07_Action_Plan_Tracker.md) §🗄️ `INF.20`). 🔑 **Пʼятий не називав ЖОДЕН дім: реєстрація ефемерного SSH-ключа в OS Login.** Той пускає за ключем в АКАУНТ-ПРОФІЛІ, не в metadata; `gcloud compute ssh` мінтить і реєструє його сам, а kamal іде звичайним ssh крізь ProxyCommand і не несе нічого. ⛔ `gcloud compute os-login ssh-keys add` під WIF **не працює** — CLI виводить адресата з креденшела, а федеративний його не має (`Request for user [None]`); лік = REST `oslogin.googleapis.com/v1/users/<SA_EMAIL>:importSshPublicKey`, і адресат саме **email**, бо числовий `unique_id` дає 403, ПОПРИ те що вірний. 🔴 **Дві різні ідентичності того самого SA у двох сусідніх викликах:** `ssh.user` = `sa_<unique_id>`, адресат API = email. ⊕ І ще два кроки, без яких ланцюг не доходить: мережа `kamal` не існує (її створює `kamal setup`, якого ми свідомо не ганяємо), а `Reboot Kamal Proxy` потребує ВЛАСНОГО `env:` із `GCP_ARTIFACT_REGISTRY_KEY` — він тягне образ проксі з приватного AR, і без пароля `docker login` іде з порожнім `-p` (exit 125). ⚠️ Кроки CI **не успадковують** `env:` один одного, а сусідній блок виглядає як відповідь. Доти цей рядок казав «ЗАДРОТОВАНІ», і різниця між «задротовано» й «працює» коштувала пʼять із девʼяти прогонів. Спершу в креслення, бо
  машини ще не було:** (4) `roles/iap.tunnelResourceAccessor` **на deploy-SA**
  (`google_project_iam_member.deploy_iap_tunnel` — доти роль ішла ЛИШЕ людям через
  `for_each = toset(var.iap_admin_members)`, тож `proxy_command` віддавав би **403**, і помилка
  називає IAP, не kamal); (3) docker-група — startup-скрипт `google_compute_instance.app`
  дописує `sa_<unique_id>` у `/etc/group`, бо акаунта до першого OS Login ще НЕ ІСНУЄ, а
  `usermod`/`gpasswd` відмовляють невідомому користувачу. ⛔ **Підвищення SA до `osAdminLogin`
  відхилено виміром, не смаком:** воно дало б CI root на хості, де в ENV job-ролі лежить
  money-квінтет (`/proc/environ`), і скасувало б підставу, з якою docker передвстановлено.
  ✅ (1)+(2) дописано одразу після першого `apply`, який їхні значення й мінтить:
  `ssh.user` = `sa_<unique_id>` + `proxy_command` через `start-iap-tunnel`. ⚠️ **Імя ДЕРИВОВАНЕ,
  не прочитане:** `os-login describe-profile` через імперсонацію віддає PERMISSION_DENIED
  (власник не має TokenCreator на цьому SA), тож узято ту саму формулу, що й
  стартап-скрипт. ✅ **ДЕРИВАЦІЮ ПІДТВЕРДЖЕНО 2026-09-01 живим API:** відповідь OS Login на `importSshPublicKey` несе `posixAccounts[].username = sa_100772929234285228842` — третє, незалежне джерело. Формула кінцева. ⚠️ Історичне застереження лишається як КЛАС: 🔴 **збіг із `/etc/group` НЕ був незалежним підтвердженням** —
  обидва боки деривують із `unique_id`; чи OS Login справді ПРИЗНАЧАЄ цей posix-логін,
  доведе лише перший SSH ПІД САМИМ SA, тобто `kamal deploy`. ⊕ Третя опція ходу (3),
  ACL на сам сокет, не знадобилась.
  Команда/роль-модель → `06_01` / 00_07 `INF.20` (**архівовано ✅ 2026-09-01** — рядок §🗄️, не `####`-секція). 🔴 **І SSH-ціль kamal — ІМʼЯ інстансу (`silken-net-app`), не IP:** `proxy_command` годує `%h` у `start-iap-tunnel`, який бере імʼя, тож адреса дає `4047: Failed to lookup instance` на всіх пʼятьох цілях.
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
  `config/deploy.canopy.yml`-оверрайд (B3, звужено 09-02: `servers:` там — hash-форма з ВЛАСНИМ
  квінтет-масивом job-ролі; заборонена лише форма, що успадкувала б продовий квінтет через deep_merge) → ⚠️ **terraform `variables.tf` — але вже НЕ як крок того самого воркфлоу**: [INF.22] зняв джобу `terraform` із деплою (apply founder-local), тож `TF_VAR_` у `deploy*.yml` більше не додають — інакше повертаєш рівно те, що коміт зняв, і оживляєш `terraform_workflow_var_parity` на воркфлоу, який terraform не запускає. Ланцюг закінчується Kamal-поверхнями; tf-змінні заводить founder локально +
  `main.tf`/`compute.tf` templatefile-мапа. Ланцюг секретів енфорсить `spec/deploy/env_fetch_declaration_spec.rb`
  — ⚠️ але **лише для `ENV.fetch("X")` БЕЗ дефолту в `app/`+`lib/`**, тож змінна, прочитана в
  `config/environments/*.rb` або з дефолтом, для нього **не існує** (мій випадок: жодного хіта).
  🔴 **Процеси — окрема вісь, і саме там ламається тихо:** `after_initialize` біжить у КОЖНОМУ,
  хто вантажить середовище. `canopy` з 2026-09-02 має ВЛАСНУ `job`-роль (hash-форма з власним
  квінтет-масивом, testnet-двійники `CANOPY_*` — OPS.37; доти був web-only) і `coap_listener` =
  UDP-клей, що вантажить усі ініціалізатори. Обидва
  вимагали б можливості, якої не мають. Платформа має **ТРИ** зразки звільнення — видати змінні
  процесу (AR-ключі на coap) · **пропустити сам процес** (`next if $PROGRAM_NAME.include?("coap_listener")`
  у `master_key_strength_check`) · 🆕 **скоупити ВИМОГУ пер-змінною по процес-класах усередині
  самого гарда** (`web:` у `SILENT_ADDRESS_ENVS` + kwarg `web_process:`; ініціалізатор деривує
  job/web/coap із `Sidekiq.server?` ⊕ `$PROGRAM_NAME` — [`04_02 §Web3NetworkGuard`](../../../docs/04_02_Business_Logic_and_Services.md),
  2026-09-01). Другий бери, коли шляху до фічі з процесу немає взагалі; **третій — коли ту саму
  змінну читають РІЗНІ класи з різними правами**, бо там перші два обидва брешуть: видача
  розкидає секрет ширше за потребу, а пропуск процесу звільняє й тих, хто змінну справді читає.
  ⚠️ І плейсхолдер `REQUIRED_SECRET_NOT_SET` присутність-гард **проходив** до 2026-09-02 — тепер presence-гілки
  гарда несуть `_NOT_SET`-tripwire (`PLACEHOLDER_SUFFIX`), скоуплений як сама presence-вимога; форматну
  перевірку див. `.claude/skills/ssot-maintenance/guard-craft.md` #58. 🔴 **Двійникове імʼя ніколи не lazy:**
  оверлей `.kamal/secrets.canopy` перетворює ВІДСУТНІЙ `CANOPY_*` на ПРИСУТНІЙ плейсхолдер, тож «warn і
  деплой» для нього = зелений verify + мертвий job-контейнер — усі вісім = `JOB_CRITICAL`, і гейт per-ROLE
  (`roles=web|web,job` → `kamal deploy --roles`), не per-slot: вимога ролі не блокує web. 🔴 **«kamal deploy
  зелений» для non-proxy ролі = 7-с poll `.State.Status`** (HEALTHCHECK в образі нема) — crash-loop після
  ~10-с буту Rails проходить; носій = пост-деплойна 45-с uptime-проба job-ролі в ОБОХ воркфлоу, і на
  canopy вона була єдиною до 2026-09-03 (слот тепер скрейпиться — `00_07` OPS.37, розкатка accessory відкрита).
- **Money/signing-п'ятірка = JOB-ONLY** (`ORACLE_MINTER/SLASHER/CELO` + `ETHEREUM_ANCHOR` +
  `SOLANA_WALLET_KEYPAIR`) — least-privilege, і post-`OPS.37` підстава ширша: `config/deploy.yml`
  глобальний `env.secret` успадковують УСІ ролі (включно з `coap`), тож квінтет живе ЛИШЕ в
  `servers.job.env.secret`, ніколи в глобальному блоці (`scripts/deploy_secret_scan.rb`
  інваріант B). legacy `ORACLE_PRIVATE_KEY` **RETIRED** (guard-tripwire). Web/coap keyless
  (guard scoped `signer_process: Sidekiq.server?` — ⚠️ **це вірно про КЛЮЧІ й хибно як узагальнення
  з 2026-09-01:** гард тепер рахує ТРИ процес-класи, і presence **АДРЕС** скоуплена пер-змінною
  (`web:` у `SILENT_ADDRESS_ENVS`), тож web-контейнер ВИМАГАЄ `CARBON_COIN_CONTRACT_ADDRESS`.
  Дім — [`04_02 §Web3NetworkGuard`](../../../docs/04_02_Business_Logic_and_Services.md)).
  Mitigation/aux-gated → `06_04 §1.1`.
- **SEC.22 latch: at-rest ≠ runtime** — провайдер читає `/proc/environ`, тож жоден секрет не сміє
  жити лише за `RAILS_MASTER_KEY`-vault у runtime. credentials→ENV (8 сервісів + `storage.yml`);
  AR-encryption ключі = ENV (boot-guard fail-closed, були DEAD-in-prod). ✅ Phase-2 drop
  ВІДВАНТАЖЕНО 09-02: master-key не їде в ЖОДЕН процес (образ без `credentials.yml.enc`, vault =
  лише `secret_key_base`, який їде окремим `SECRET_KEY_BASE`); ратчет — `kamal_secrets_parse_spec` +
  `anchor_coap_env_spec`. 🔴 Той самий вимір: heredoc `coap.env` ніс master-key і НЕ ніс
  `SECRET_KEY_BASE` — `active_storage.verifier` кличе `message_verifier` при буті будь-якого
  Rails-процесу, тож демон помер би «Missing secret_key_base» на першому старті. Незамінний
  DR-ключ тепер `SECRET_KEY_BASE` (DR.1). Механіка → `06_04 §5.7` / 00_07 SEC.22.
  🔴 **І `storage.yml` тут не деталь переліку, а ПАСТКА з незворотною ціною — читай `06_04 §2.1`,
  НЕ лише §5.7 (перелік є в обох, зуби лише в §2.1).** Механізм після 09-02 названо чесно: у
  контейнері credentials-фолбек `storage.yml` був `nil` ЗАВЖДИ (образ без vault), тож Phase-2 нічого
  не «зламав» — але вимога та сама й живе в S1.1: AWS/GCS-пара в ENV production ДО першого блоба,
  інакше фотодокази `MaintenanceRecord` — ЄДИНА людська доказова поверхня — тихо мертві, і після
  першого блоба крок незворотний для вже завантажених.
  ⚠️ Рядок дописано 2026-09-01: доти скіл називав `storage.yml` без жодного застереження й посилав
  саме в §5.7 — тобто на deploy-day читач із самим скілом у руках проходив повз пастку, маючи
  формально правдивий текст.
- **Secrets-at-rest = три ISOLATED KMS-keyring'и** (`silken-disk-ew1` boot-disk CMEK ·
  `silken-sign-ew1` money-signing SEC.17 pre-mainnet · `silken-tfstate-ew1` bootstrap-owned) —
  key-level IAM бар'єр, **НЕ** generic keyring (merge-trap). ⚠️ Money-квінтет лишається plaintext
  у deploy-ENV до `SEC.17` (`KmsSigner` HSM-custody, pre-mainnet-gated) — поточний масштаб цієї
  діри пост-`OPS.37` переоцінює сам `SEC.17`, тут не вгадуємо. Grantee/purpose/boot-dep → `06_04 §5.6`.
- **Deploy/release ланцюг:** Canopy = continuous push у `main` після CI; Production = GitHub Release
  (release-please: semver+CHANGELOG); GHCR-mirror пушить SLSA provenance+SBOM. `main` branch-protected
  (`CI passed`+`Docs passed`, owner пушить напряму). Діаграма/гейти → `06_07 §1`/`§2`.
- **GH Environment `production` = дім money-п'ятірки (INF.22)** — environment-scoped, НЕ repo-level;
  Canopy ПРОДОВІ money-ключі не споживає структурно: з 2026-09-02 (OPS.37) його власна `job`-роль
  читає repo-level testnet-двійники `CANOPY_*` через overlay `.kamal/secrets.canopy` (B4), а RHS
  кроку деплою пінить `env_fetch_declaration_spec`. Wait-timer-per-job / Kamal-secrets-chain (`.kamal/secrets-common`) → `06_04 §1` / `06_07 §1`.

## Карта коду / конфігів

| Шар | Шлях |
|---|---|
| Kamal deploy | `config/deploy.yml` · `config/deploy.canopy.yml` · `.kamal/secrets-common` |
| IaC (GCP) | `terraform/` (`compute.tf` — **ДВА інстанси**: анкор (systemd/env-file + boot-disk CMEK) і app-хост `google_compute_instance.app` (Kamal web+job+coap; повернений OPS.37 2026-08-30 — приватний IP, Docker передвстановлений, бо наш deploy-SA не має sudo й `kamal server bootstrap` тут RAISE'ить; canopy-VM свідомо НЕМАЄ — відкритий ⚖️) · `database.tf` · `vpc.tf` · `iam.tf` · `main.tf` · `kms.tf` — Cloud KMS keyring/IAM (два disk-ключі: `anchor-boot` · `app-boot`) · `wif.tf` — keyless CI→GCP OIDC (INF.22) · `billing.tf` — OPS.11 budget-guard) |
| Observability | `config/initializers/prometheus.rb` (`SilkenNet::Metrics`) · `app/middleware/prometheus_collector.rb` · `lib/silken_net/metrics_exporter.rb` (embedded /metrics job/coap) · `deploy/alloy/config.alloy` · Grafana IaC `deploy/grafana/` (`deploy/grafana/alerts/silkennet-alerts.yaml` · `dashboards/` · `import.rb`) |
| Web-сервер | `config/puma.rb` |
| Load/throughput | `lib/silken_net/load_test/` + `bin/coap_load` (INF.23 harness: factory·flood·drain·microbench·report). ⚠️ dev-число ≠ capacity — bottleneck-class inversion (prod network-IO-bound, dev завищує 10-50×); реальна стеля лише staging з prod-adapters → `06_08 §2.4` |
| CI/CD | `.github/workflows/` (`deploy.yml` — path-gated INF.9 · `deploy-production.yml` · `coap_smoke.yml` — post-deploy gate + 30хв liveness-schedule · `iac_scan.yml` — Sec·IaC-Scan (Trivy `config`, SARIF soft-fail; baseline у `.trivyignore`) · `image_cve_scan.yml` — Sec·Image-CVE-Scan (Trivy `image` по ОПУБЛІКОВАНОМУ тегу GHCR, щоденний cron; SOFT за конструкцією — CVE базового шару лікуються бампом образу, тож HARD із народження = вічно червоний воркфлоу; ⚠️ кореневий `.trivyignore` — базлайн IaC-місконфігів і для CVE інертний, свій потрібен лише при переході в HARD) · `terraform_drift.yml` — Ops·TF-Drift (weekly `plan -detailed-exitcode`, skip-clean до 3 secrets) · `ci.yml` `terraform_validate`-job (offline `validate`+`fmt`, path-gated `terraform/**`, pre-deploy config-validity — INF.15) · `mirror-ghcr.yml` · `release-please.yml` · `ci.yml` · `docs.yml` · `ssot_guard.yml` · `subgraph.yml` — **CI · Subgraph** [OPS.34/OPS.36]: `npm ci`→`graph codegen`→`graph build`→`graph test` (matchstick — семантика мапінгу, з 2026-08-28), path-gated через джобу `changes` (НЕ `on.pull_request.paths` — та форма вішала б required-чек «Expected» назавжди); **required-контекст «Subgraph passed» — девʼятий** (фліп 2026-08-30, `:required` у `workflow_gate_perimeter`)) |
| Deploy drift-guards | ⚠️ **`deploy_secret_scan` до 2026-08-30 був декоративним ЗА ВХОДОМ:** path-фільтр джоби (`alloy` в `ci.yml`) і `pre-push` (`^deploy/`) не містили ані `config/deploy*.yml`, ані `.kamal/**`, ані `terraform/compute.tf` — тобто **чотирьох із пʼяти власних предметів**, і config-only діф проходив із зеленим `CI passed`, не судивши нічого. Обидва носії розширено; **тримай перелік ≡ subject-сету в шапці скрипта**. CI-гейти над deploy-конфігом (offline, no-creds; НЕ дублюй їх логіку — правь дім): `scripts/deploy_secret_scan.rb` (Kamal-ланцюг + anchor `COAP_ENV`-heredoc, post-`OPS.37`: no-literal + signing-quintet job-only-і-поза-ГЛОБАЛЬНИМ `env.secret` + retired-tripwire + B3 canopy без успадкування квінтету (array-form, АБО hash із ВЛАСНИМ квінтет-масивом точного складу й безхостовим `coap` — з 2026-09-02, OPS.37) + `SUBJECT_FLOOR` проти парсер-колапсу + інваріант C над **ДВОМА** ignore-файлами (`.dockerignore` тримає секрет поза публічним ОБРАЗОМ, `.gitignore` — поза публічною ІСТОРІЄЮ; другий додано 2026-09-01 [S1.1] заради `gha-creds-*.json`, тобто ЖИВОГО WIF-креденшела, і пара не надлишкова: build-контекст І Є робочим деревом, тож жоден із двох не імплікує іншого) + present-empty Invariant D + `_DSN` у `SECRET_NAME` + **B5 [INF.27, 2026-09-02]: голий bash-дефолт `${VAR:-…}` заборонений в обох `.kamal/secrets*` — Kamal парсить їх Dotenv'ом, який калічить його в `<value>:-…}`; A приймає лише `LOUD_REF`-форму `$(printf '%s' "\${VAR:-MARKER}")`. ⚠️ Текстовий B5 — лише tripwire: парсер-виконаний носій — `spec/deploy/kamal_secrets_parse_spec.rb` (обидва файли через `Kamal::Secrets`, set/unset), і саме тому `.kamal/**` додано в `ruby`-фільтр `ci.yml`**) · `spec/db/solid_structure_files_spec.rb` (`:sql`-деривація `db/{cache,cable}_structure.sql` + раунд-тріп через `psql`; до 2026-09-02 обидві Solid-бази створювались ПОРОЖНІМИ) · `scripts/audit_deploy_secret_scope.rb` (S1.1 — live `gh`-scope preflight: money-quintet env-only · retired-zombie · WIF=Variables · Kredis instance-override footgun — present-empty глушить фолбек на `REDIS_URL`) · `spec/deploy/*_spec.rb` (INF.16 db-config · INF.17 coap.env boot-contract · INF.4 firmware↔host · DR.1 DR-posture · INF.12 ENV.fetch↔deploy declaration + B1-chain · INF.12-behavior web3-env-loudness (кожен web3-ENV ∈ guard-set ∪ LOUD ∪ SOFT — silent-class tripwire) · SEC.22 credentials-ENV-first · S2.4 alloy-scrape-topology · S2.4 grafana-alerts↔REGISTRY-parity (silkennet_-метрика в alert-expr ∈ REGISTRY, typo→dead-alert; ⊕ **slot-ізоляція** — панель несе `{slot=~"$slot"}`, агрегація алерту `by (slot…)`; ⊕ `import.rb --verify` оголошений read-only, і це тримає спека, не обіцянка) · OPS.11 tf-workflow-var-parity · **S1.1 deploy-workflow-parity** — механізм-паритет двох deploy-воркфлоу: ПОСЛІДОВНІСТЬ кроків джоби `Kamal Deploy (…)` + `env:`-ключі спільних кроків, із поіменним винятком на сам крок `Kamal Deploy` (там розходження законне — money-квінтет; його ланцюг судить `env_fetch_declaration` прикладом «delivery half»). Заведено після того, як фікс трьох механізм-кроків поїхав в ОДИН воркфлоу з двох) · 🆕 **OPS.28 `scripts/shell_parse_check.rb`** — `bash -n` над КОЖНИМ shell-артефактом дерева, включно з шеллом усередині terraform-heredoc-ів (`terraform validate` бачить тіло як непрозорий рядок, `actionlint` читає лише `run:` у воркфлоу). Субʼєкти ВІДКРИВАЮТЬСЯ (git + shebang), не перелічуються. HARD у `ci.yml` (джоба `shell_parse`) **і** в `.githooks/pre-push`. ⛔ Оголошено РАТЧЕТОМ: улов на момент побудови НУЛЬ, зелене НЕ означає «шелл коректний» — лише «bash його розбирає»; семантика, `sh`-vs-bash і вміст `${…}` поза ним. Несе власну батарею `--selftest`, і вона не оздоба — дві його трансформації не мають свідка в живому корпусі, обидві були зламані при написанні, і корпусний прогін мовчав |

## Gotchas (верифіковані, не з канону)

1. **jemalloc через `LD_PRELOAD`** у Docker-образі (`libjemalloc.so`) — менше пам'яті
   й латентності. Не прибирай без бенчмарку.
2. **`SENTRY_DSN` задається at deploy time** (`.kamal/secrets-common`); без нього Sentry
   інертний — нуль crash-репортів.
3. **Старт через Thruster** (`thrust ./bin/rails server`) за замовчуванням; overridable at runtime.
4. **WIF рантайм = ТРИ GCP API** — `iam` (default-on) + `sts` + `iamcredentials`; останні два увімкнути **ЯВНО**. Пропущений `sts.googleapis.com` → перший keyless CI-run падає `SERVICE_DISABLED` (STS робить OIDC→federated exchange ПЕРЕД impersonation), а `terraform validate`/local-apply це НЕ ловлять (STS не викликається при create pool).
5. **keyless AUTH ≠ terraform-apply CAPABILITY** — CI імперсонує least-privilege deploy-SA БЕЗ IAM/WIF/serviceusage-admin, тож рефреш IAM/WIF-ресурсів дає **403**. ✅ **Розвилку ЗАКРИТО ⚖️ founder 2026-08-29: `apply` лишається founder-local, і конфіг це виконує — джоби `terraform` у deploy-воркфлоу БІЛЬШЕ НЕМА** (разом із нею знято `TF_VAR_*` і `terraform/` з path-фільтра canopy; `deploy` висить на `needs: verify-secrets`). ⛔ Не читай цей пункт як відкрите питання «apply в CI чи ні» — SA-privesc відхилено з підставою (він вимагав би чотирьох GCP-адмін-ролей, тобто god-credential проти самої мети keyless-WIF). 🔴 **І це не було косметикою:** доти `deploy` залежав від тієї джоби через `needs:`, тож у день деплою, ЩОЙНО заведуть WIF-Variables, вона діставала б 403 і `kamal deploy` не побіг би ЖОДНОГО разу; невидиме доти лише тому, що Variables порожні. Що лишається сьогодні: 403 у **weekly `terraform_drift.yml`** (він і далі робить `plan` з рефрешем) — тобто оголошений негатив детектора, не блокер релізу. → 00_07 INF.22 · `06_07 §1` · `06_01 §IAM`/Фаза 0.
6. **`gh run watch --exit-status` бреше** (exit 0 on fail / 1 on empty) — щоб перевірити, чи Deploy·Canopy/Production реально пройшов, довіряй `gh run view --json conclusion`, не `watch`. ⊕ `gh run list --commit` матчить лише ПОВНИЙ SHA — короткий віддає ∅ мовчки (09-02). ⊕ І детектор INF.9 (`Deploy · Canopy` → джоба `changes`) до 2026-09-02 судив файли ОДНОГО HEAD-коміту, не пушу: чотирикомітний пуш із docs-хвостом скіпнув деплой коду за зеленим `success`; тепер база = SHA останнього успішного `Kamal Deploy (Canopy)` (compare API), а «що зараз ЖИВЕ» — саме те питання, яке цей фільтр і має ставити.
6a. 🔴 **`conclusion: failure` теж бреше — не про факт, а про ПРИЧИНУ, і саме ця брехня маскує справжній червоний** (OPS.23). Хрестик «джоба не добігла» (раннери не видались: «The job was not acquired by Runner of type hosted…») і хрестик «код зламано» виглядають у панелі ІДЕНТИЧНО, а перший ховає другий — виміряний випадок: інфраструктурний червоний накрив червону підлогу покриття, і її не побачив ніхто. **Рефлекс на червоний `main`: питай спершу не «що зламалось», а «чи джоба СТАРТУВАЛА»** — `gh run view <id> --json jobs --jq '.jobs[] | select(.conclusion=="failure") | {name, steps: [.steps[].name]}'`; порожній `steps` = інфраструктура → **re-run**, бо під тим хрестиком може стояти другий. Дзеркальна половина класу закрита машинно: агрегат тепер стверджує результат САМОГО path-фільтра (доти незадеклароване `skipped` резолвилось у «OK», і `CI passed` зеленів, не виконавши жодної джоби) і його помилка явно каже «infrastructure failure, not a code failure» → `06_07 §2`. Ця ж, друга, нерозрізненна за побудовою — збій передує запуску нашого коду.
7. **`gh attestation verify` рендерить TTY-only** → piped/`tail`/`grep` захоплюють ПОРОЖНЄ; довіряй **EXIT=0** або `--format json`.
8. 🔴 **Живі прогони `import.rb` знайшли вже ПʼЯТЬ дефектів, яких `--dry-run`/`--verify` не бачать ЗА ПОБУДОВОЮ** — вони судять ФОРМУ артефактів, а всі пʼять були про ФІТ із реальним API. Четвертий і пʼятий (2026-08-30) — ОДИН клас, найпідступніший, бо його не бачить навіть УСПІШНИЙ імпорт: **Ruler API ЗБЕРІГАЄ правило, яке Mimir потім відмовиться рахувати** (валідація запису слабша за evaluation). (4) SSE-вираз не парситься: `type: threshold`-model без ключа `expression: "A"` (classic-форма `conditions.query.params` його НЕ заміняє) — 57 правил сіли зеленими, перший тік дав `[FIRING:57] DatasourceError` у щойно задротований contact point. (5) `relativeTimeRange` > ~45 год пробиває Mimir-ліміт 11 000 точок/серію — лік: довгий lookback живе в PromQL (`increase(x[30d])`), вікно запиту 600s; гейт вікон тепер у `grafana_alerts_spec`. **Рефлекс: після імпорту дивись не на успіх POST, а на стан правил за хвилину-дві — і мірка = ВСІ оцінені (`lastEvaluation` != нульового) І нуль error: health свіжозбереженого правила до першого тіку стоїть «ok» порожнім дефолтом, і двоє таких «ok» ховали майбутні DatasourceError.** Решта три (2026-08-29):
   · **datasource-автовиявлення бере is-default, а за неоднозначності ВІДМОВЛЯЄТЬСЯ.** Grafana Cloud віддає кілька prometheus-джерел, і біллінгове `grafanacloud-usage` стоїть у списку ПЕРШИМ. Стара `.find` привʼязала б усі правила до бази, де `silkennet_*` не буде НІКОЛИ: резолвляться, виглядають здоровими, не спрацьовують ніколи. ⛔ Імʼя НЕ дискримінатор — денилист на `usage` протух би на першому перейменуванні вендором. **Регресія (повернення до `.find`) не ловиться жодним гейтом.**
   · **uid alert-правила ≤ 40 символів** — межа ВЕНДОРСЬКА, і відмова приходить лише з живого API (`400: UID is longer than 40 symbols`) ПОСЕРЕД черги: частина правил уже записана, решта не поїде. Тепер це валідує `--dry-run` (`RULE_UID_MAX`).
   · **`interval` групи — секунди-ЦІЛИМ в API проти рядка-тривалості (`1m`) у provisioning-файлі.** Порівняння `60 != "1m"` завжди нерівне, тож warn «інтервал не виставився» був хибною тривогою про ПРАВИЛЬНИЙ стан — і саме тому ховав справжній дрейф (`p2-info` стояв на 60 с замість 300). Тривога, що звучить завжди, не звучить ніколи.
   ⊕ **Дашборд і правила РОЗЧЕПЛЕНІ:** Grafana Cloud скоупить RBAC по теках, тож 403 на дашборді обривав імпорт до першого правила — часткові права давали НУЛЬ замість більшої половини. Тепер провал гучний і несе `exit 1`, але правила їдуть. Побачив частковий провал — це очікувана поведінка, не регресія.
   ⊕ **Звірка живого стека — `ruby deploy/grafana/import.rb --verify`** (READ-ONLY; оголошені стелі в шапці самої гілки): чи всі правила сіли · чи привʼязаний datasource · чи немає правил, СТВОРЕНИХ ПОВЗ РЕПО (зворотний дрейф, якого upsert не чіпає) · чи збігаються інтервали. ⛔ Він судить НАЯВНІСТЬ, ніколи правильність порогів, і не читає ані silences, ані contact point.
9. 🔴 **`terraform fmt -diff` РЕНДЕРИТЬ `terraform.tfvars` — тобто друкує `db_password` у відкритому вигляді.** Спіймано на собі 2026-08-31, за хвилини до першого `apply`. Форма підступна тим, що команда виглядає як лінтер: думаєш «перевіряю відступи», а отримуєш вміст файлу, який навмисно тримають поза git. **`.gitignore` тут не захищає — він стереже РЕПОЗИТОРІЙ, а витік іде в ЛОГ/транскрипт/CI-вивід**, тобто в поверхню, про яку gitignore нічого не знає. ⚠️ І це не про terraform: клас — будь-яка команда, що рендерить ВМІСТ файлу з секретами (`fmt -diff` · `diff` · `cat` · `plan` з `-var-file` у verbose). **Рефлекс: перш ніж запускати щось із `-diff`/`--show`/`cat` у каталозі, де лежить tfvars або env-file, скоупни ціль явно — `terraform fmt *.tf`, не `terraform fmt`.** 🔑 Дешевий лік, коли вже сталось: якщо `apply` ще не було, ротуй значення — воно ще не є креденшелом ні до чого, і ротація коштує один рядок; після `apply` це вже зміна пароля живої БД.
10. 🔴 **Console-доступ: дорогу ВИМІРЯНО 2026-09-02 — read-only `rails runner` через `gcloud compute ssh --tunnel-through-iap` + `docker exec` працює з ноутбука, `kamal app exec` звідти падає на posix-акаунті SA (`06_01` ops-блок); інтерактивна консоль ще не виконувалась** — історія нижче лишається як підстава: 🔴 і преміса ЗВУЗИЛАСЬ 2026-08-31: «не задеплоєно нічого й ніде» більше не так (інфра розгорнута), 🔴 **а 2026-09-01 звузилась ВТРЕТЄ: застосунок ДЕПЛОЇВСЯ** (девʼять прогонів; контейнер стартував і почав Rails-бут), тож контейнера, у якому виконують консоль, не існувало до 2026-09-02 (виміряно 2026-07-29; природа зафіксована `OPS.37` 2026-08-29). Доти діра читалась як «рецепт для НЕ-ТОГО таргета» (Kamal задокументований, живим вважався Akash); з платформою знято й Akash-таргет — **тепер таргет один, рецепт один** (`kamal app exec --interactive --reuse "bin/rails console"`, `06_01 §DEPLOY-DAY`), а асиметрія не закрилась — вона змінила ПРИРОДУ: контейнер тепер СТАРТУЄ, але не ЛИШАЄТЬСЯ живим — `web3_network_guard` валить бут, тож консоль інертна не через відсутність деплою. 🔴 **Преміса звузилась УЧЕТВЕРТЕ 2026-09-01, і цього разу атрибуція теж зсунулась: Фаза 2t ВИКОНАНА** (шість контрактів живі на Amoy), тож тримали консоль уже не невиконана фаза, а **незаведені в env слоту адреси** — пʼятирухова нога `INF.27`, закрита 2026-09-02 (§🗄️): canopy бутнувся й живе, і саме на ньому цю дорогу виміряно. ⚠️ І «на плейсхолдерах» тепер занижує гард: після фіксу того ж дня ЗНЯТА змінна відмовляє бут так само, тобто прибирання плейсхолдерів більше не купує чистий бут — рівно той важіль, який фікс і знешкодив. Наслідок несе не той документ, де діра: **інертними лишаються всі console-рецепти репо**, зокрема два money-path (`manual_review`-резолюція та ескалація Field-Audit C→A, що відчиняє ворота необоротного слешингу). Тож пишучи новий рецепт «виконай у консолі», не вважай доступ вирішеним питанням; спільна нота стоїть одним домом у шапці `06_07 §3` — читай і вирівнюй, не пиши третю редакцію. ⛔ `coap` для консолі не брати (звільнений від master-key-перевірки). → `00_07` OPS.20. ⊕ **КЛАС, що пережив і платформу, і рецепт (00_07 §🗄️ OPS.20):** «інструмент доступу недоступний саме в ІНЦИДЕНТІ — рестарт/краш-луп, — коли він потрібен» — платформо-незалежний; з ноутбука `kamal app exec` недоступний ЗАВЖДИ, не лише в інциденті (posix-акаунт SA), тож дорога = `gcloud compute ssh --tunnel-through-iap` + `docker exec`, а надійність саме ЦІЄЇ дороги в краш-лупі не міряна — тригер: перший рестарт під навантаженням.
11. 🔴 **`gcloud sql instances clone` після ~10 хв друкує «failed … taking longer than expected» — це клієнтський таймаут, не вердикт:** операція живе (DR-drill 2026-09-02: `CLONE` 15:57→16:08Z, RTO 11:00 до RUNNABLE), тож судити `gcloud sql operations describe <op>` (`status`/`startTime`/`endTime`) — саме ця пара і є RTO. Сусідня брехня того ж роду: `gsutil` під корпоративним TLS-проксі зависає мовчки (свій CA-стор, не gcloud-конфіг) → `gcloud storage ls/cp` (з `#<generation>` для версій стану). Клон успадковує `deletionProtectionEnabled` — видалення = `patch --no-deletion-protection` + `delete`.
12. 🔴 **Скрипт анкера живе в `metadata.startup-script` з 2026-09-03 (⚖️ founder B, INF.17): зміна скрипта чи піна образу відтоді in-place + `reset`.** Доти він був `metadata_startup_script` (ForceNew у google-провайдері), і кожна правка = replace VM (`1 add / 1 destroy`) — саме тому фікси 09-02 на VM не доїхали, а крок рунбука «apply оновлює startup-script» був мертвий; урок: крок IaC-рунбука судить `terraform plan`, не читання HCL. Сама міграція коштує один останній replace (атрибут іде в null) у вікні `terraform apply -var=anchor_replace_window=true` — прапор знімає захист ЛИШЕ з анкера, бо спільний `enable_deletion_protection` стереже ще й Cloud SQL; після replace `app-host-ip` знову сентинел → `add-metadata` + `sudoedit coap.env` + `reset`. Пін `coap_daemon_image` у tfvars — лише у вікні replace, інакше кожен apply спотикається.
13. 🔴 **Детектор «чи змінилось релевантне» судить БАЗУ, не HEAD — і в ОБОХ воркфлоу:** `deploy.yml` (INF.9, 09-02) і `mirror-ghcr.yml` (INF.17, 09-03) читали `commits/${HEAD_SHA}` = файли ОСТАННЬОГО коміту пушу; база = head останнього успішного `Kamal Deploy (Canopy)` / `Build & Push to GHCR` через compare API, носії `deploy_relevance_base_spec` / `mirror_relevance_base_spec`. Симптом mirror-діри: живий коміт canopy без `sha-<7>` тега — пінити нема що; закрита вісь у сусідньому воркфлоу = перший кандидат на ту саму діру. ⊕ Grafana «горить»: читай `alerting/history`, не список правил — 30.08 усі правила пройшли NoData/Error у день імпорту (мітки `datasource_uid`/`ref_id` = підпис цього стану), а canopy-дашборд «No data» був ціною присуду OPS.37 до 2026-09-03 — відтоді `config.alloy` несе два canopy-таргети зі `slot` НА ТАРГЕТІ, лишилась розкатка `kamal accessory reboot alloy`.
14. 🔴 **Три deploy-day факти, кожен виміряний 2026-09-03, і жоден не видно з зеленого воркфлоу:** (а) `kamal deploy` НЕ стрімить stdout post-deploy хука — exit 0 і є весь вердикт про склад `governance:bootstrap`, тож «зелений деплой» про bootstrap не свідчить (OPS.38); (б) `db:prepare` сіє лише ПОРОЖНЮ базу — фікс сіда не доходить до живого слоту без дропу трьох баз (`06_06 §5.6`), і canopy добу малював старий сід після виправлених координат (ex-UI.19); (в) крок рунбука, виконаний РУКАМИ (бакет для дампів, DR.1), тим самим проходом оновлює рядок рунбука — інакше наступний читач створює ДРУГИЙ ресурс або, гірше, вірить опису, що розійшовся з реальністю (трекер писав «EU multi-region», `buckets describe` сказав `europe-west1`).

## Робочі правила

1. **Docs-first.** Прочитай `06_0N` (саме *чому* + поточний стан/TRL) перед зміною
   деплою, секрету чи метрики — кожен 06-док несе власний member-TRL у ✅ Статус.
2. **SSOT One-Home.** Правиш факт — правь у його домі (`06_04` секрети, `06_03 §2.8`
   метрики, `terraform/` config), не тут. Skill лишається тонким маршрутом.
3. **Гейти.** Після правок канону — `bin/rails docs:check_refs` зелений; робота над
   SSOT-доками 06_xx — через skill `ssot-maintenance`.
