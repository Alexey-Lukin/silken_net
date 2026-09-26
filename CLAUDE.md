# SilkenNet — контекст для Claude (orientation + routing)

> **Цей файл prepend-иться в КОЖЕН промпт — він тугий orientation, НЕ manual.** Глибина живе в `docs/` (canon, `00_00`→`06_08`) + скілах (авто-інвокуються). Один факт — один дім (`00_06 §2`): тут — філософія, навігація, критичні інваріанти, крос-доменні пастки; решта — pointers. Конфлікт із `docs/` → **canon WINS**.

## 1. Що це

Планетарна Bio-IoT **D-MRV** платформа моніторингу лісів: Ti-6Al-4V гіроїдний анкер + **EBFC** (≈500 мВ з ксилеми, «zero-grid») → STM32 **«Soldier»** (sense→TinyML→Lorenz→encrypt→LoRa 868) → **«Queen»** gateway (CoAP) → Rails 8.1 / Ruby 4.0.7 / Postgres / Sidekiq → 11-chain Web3 **Proof-of-Growth** → mint SCC (**10 000 growth_points = 1 SCC**, Polygon ERC-20; слешинг при деградації).

**Чесний стан: System TRL = 3**, gated by anchor/EBFC — 🔴 **in-silico ≠ TRL 4 за NASA/ISO**, хоч би яким зеленим був Zero-Lab; фізичний TRL 4 замикає in-vitro Ti-coin. Per-module TRL — `docs/00_03 §1` (друкує `doc_structure_map.rb`). **Polyglot:** Rails (Ruby) · firmware-C (STM32) · mruby (`bio_contract`) · Solidity (Foundry) · in-silico Python (DFT/MD) · .NET C# (PicoGK CAD).

## 2. Як тут працювати

**Операційна модель — [`00_05`](docs/00_05_AI_Native_Operating_Model.md)** (яруси інструкцій і межа кожного, хребет задачі, свіп, перевірка, агенти); цей файл — її верхній ярус.

**Скіли авто-інвокуються за доменом і маршрутизують у точний canon-doc — не читай docs наосліп.** Карта канону (TRL · kB · секції; `--heads` — голови 🎯/✅) → `ruby scripts/doc_structure_map.rb`.

| Домен | Скіл (авто) | Дім-canon |
|-------|-------------|-----------|
| STM32 firmware (Soldier/Queen, mruby, `firmware/common`) | `firmware` | `03_01`–`03_05` |
| Factory-flashing (per-device key provisioning, SEC.3) | `factory-flashing` | `03_06` |
| Web3 / контракти / minting / slashing | `web3-pipeline` | `05_01`–`05_06` |
| Telemetry / Proof-of-Growth / Sidekiq-черги | `telemetry-pipeline` | `05_02` |
| Frontend (Phlex / Tailwind v4 / Stimulus / Turbo) | `frontend` | `04_04` (+`04_06 §A`) |
| Backend Web2-core (моделі · REST API v1 · auth/RBAC · non-money сервіси·воркери · MaintenanceRecord) | `backend` | `04_01`–`04_03` (+`04_06`) |
| TinyML / log-mel / INT8 | `ml-engineering` | `03_03` + `tools/ml` |
| EBFC DFT/MD + механіка анкера in-silico | `in-silico` | `01_03` + `protocols/ebfc/in_silico` |
| Code-as-CAD (анкер/coin/radome) | `picogk` | `01_01`/`01_02 §6` + `tools/cad` |
| Hardware §02 (BOM · BQ25570 · pogo · Queen-HW) | — (bench-важка, скілу НЕМА): механіка → `in-silico`, CAD → `picogk`, bench-збірка → `02_04`, BOM/юніт-економіка → `legal-business` | `02_01`–`02_06` |
| Деплой / Kamal / observability | `deploy` | `06_01`–`06_08` |
| Юр/бізнес/академ/IP (NaaS · юніт-економіка · партнери · IP і бренд · чернетки `protocols/{legal,business,outreach,research}`) | `legal-business` | `00_04` · `00_02` · `02_06` (+ стан `00_07 §00b`) |
| Оновлення залежностей — і будь-яка вразливість / Dependabot-алерт (та сама вісь; уже-ухвалене — `00_07` OPS.22, читай ТІЛО пункту перед виміром) | `dependency-update` | (polyglot) |
| SSOT-доки / drift-hunt / wiki-sync | `ssot-maintenance` | `00_06` |
| **Подія, а не домен:** будуєш ГЕЙТ · питаєш «чи ця спека ВЗАГАЛІ здатна впасти» · масово ВИДАЛЯЄШ · ЗВУЖУЄШ правило · ведеш КАМПАНІЮ | `ssot-maintenance` → `guard-craft-index.md` (⊥ ФОРМА спеки — `04_06`) | `00_06 §3` |
| Персистентна пам'ять | `memory-maintenance` | `memory/` |

**SSOT one-home (`00_06 §2`):** `docs/NN_NN_*.md` = canon; **`docs/00_07` = дім УСІХ відкритих робіт і блокерів** — не вважай «resolved» без реального code+canon (TODO/коментарю не вір). Тоншаючи чи архівуючи пункт — ПЕРШ прочитай повну канон-секцію: **grep-hit ≠ канонізовано** (гейти самі grep-based, тож тиха втрата факту проходить зеленою). Беручи пункт у роботу — читай тіло ЦІЛКОМ: ⛔/⚖️ всередині = гейт, не примітка (`00_05 §3`). Канон / drift / wiki — через `ssot-maintenance`.

**Verify / commit:** тести (§3) перед комітом, full-suite перед push; гейт судиться exit-кодом, не хвостом (`00_05 §5`). 🔴 **Покриття судиться ПО ГРУПАХ** (`Workers`/`Services`/…, кожна з власною підлогою), тож зелена локальна сюїта штатно кладе `CI · Code` рядком `Branch coverage by group (…) is below the expected minimum … in <Group>` при `0 failures` — читай саме той рядок. `db/structure.sql` (НЕ `schema.rb`); dump — **pg17 `pg_dump`** (PATH віддає 16 → `POSTGRES_BIN_PATH=/opt/homebrew/opt/postgresql@17/bin`); `transaction_timeout` не стрипати (CI на pg17, OPS.27). Гілка від `main` — лише якщо просять. Перед edit широко-вживаного символу — простеж викликачів (auth/money = критичний шлях); перед commit — звір scope діфу з очікуваним.

## 3. Середовище

```bash
ruby --version            # 4.0.7
bin/rubocop -a            # lint (binstub; -a = автофікс)
bin/rspec                 # backend suite (binstub; full ~1.5 хв)
bin/brakeman              # security
bin/bundler-audit check
make -C firmware/test     # firmware host-tests (x86, без ARM)
make -C firmware/test asan # + ASan/UBSan memory-safety смуга (TEST.5)
cd contracts && forge test -vvv --gas-report   # Solidity (Foundry; §8)
ruff check                # Python (in-silico/ml), root ruff.toml
bundle exec i18n-tasks missing   # i18n-парність (+`check-consistent-interpolations`, `check-normalized`)
```

Смуга `Docs` = `ruby scripts/docs_band.rb` (кроки читаються з `docs.yml`). Частина команд уже стоїть на `.githooks/pre-push` і спрацює без згадки — ⛔ ростер блоків читай у самому хуку, не тут.

## 4. Стиль коду: драбинка «лінивого сеньйора» (YAGNI-first)

Найкращий код — той, що не написано. Лінивий = ефективний, не недбалий. **Перед тим як писати код, спинись на першій сходинці, що тримає:**

1. Чи це взагалі треба будувати? (YAGNI — якщо ні, пропусти)
2. Чи це вже робить кремній / stdlib? (firmware: HAL CRYP/RNG/RTC, CMSIS; Rails 8: `generates_token_for`, AASM, Solid*, ActiveSupport; Postgres: партиції, GREATEST, JSONB) — використай.
3. Чи покриває нативна платформа? (фронт: HTML/Turbo/Phlex *до* Stimulus; on-chain: OpenZeppelin *до* власного) — використай.
4. Чи вже встановлена залежність це вирішує? — так; нову залежність лише якщо неминуче (→ скіл `dependency-update`).
5. Можна одним рядком? — зроби одним рядком.
6. Лише тоді — мінімум коду, що працює.

Той самий етос, що **Ruthless Pruning** (`00_06 §4`) і **KENOSIS TITAN** hot-path: видалення > додавання, нудне > розумне, жодних незапитаних абстракцій, найменше файлів.

**НЕ лінуватися (тут несуче):** валідація на межах довіри (виняток — hot-path телеметрії свідомо без неї, KENOSIS → `TelemetryUnpackerService.valid_sensor_data?`); безпека/Zero-Trust (AES, HMAC, Argon2id); error-handling проти втрати коштів (`manual_review` double-spend guard); **чесність про залізо: платформа ≠ ідеал специфікації (годинник дрейфує, сенсор бреше, in-silico ≠ TRL).** Енерго/RAM/газ-бюджет — теж не місце для «розумного»: лінивий = менший .bss/Flash/цикли/gas.

Свідоме спрощення → познач **наявною** конвенцією (`[FW.N]` · `[transitional]` · `target FW.2` · `bench-gated` · `→ 00_07 <ID>`), що називає стелю й шлях апгрейду. Без позначеної стелі спрощення = недороблене: нетривіальна логіка лишає ОДНУ runnable-перевірку (assert-демо чи один тест); тривіальний однорядковик — ні.

## 5. Критичні інваріанти (тримай інлайн; точна деталь — за pointer)

**Sidekiq strict-priority** (`:strict: true` — послідовний дренаж згори-вниз, НЕ зважений; дім `04_02`). Не міняй чергу воркера без обґрунтування:
```
uplink(1) > alerts(2) > critical(3) > downlink(4) > default(5) > web3_critical(6) > web3(7) > web3_low(8) > low(9)
```
⚠️ **Правило — про ВОРКЕРІВ; ActiveJob-джоби з гемів приходять БЕЗ `queue_as`, і `default`(5) їм призначає фреймворк** (ARCH.60). Довговічний канал несе пріоритет своєї події, ефемерний — ні (`AlertMailer`→`alerts`; `PasswordMailer` і Turbo-редрави свідомо `default`). Носій — `spec/quality/activejob_queue_declaration_spec.rb`; ⛔ черга поза `sidekiq.yml` не слухається жодним процесом → джоби тонуть мовчки. Механізм — `backend`-скіл #72.

**AES-режими + двоключова модель** (post-FW.2 (в), 2026-07-03; дім `03_05 §3.1`+`§6`):

| Напрямок | Режим · ключ (CCM-ера) |
|----------|------------------------|
| Soldier → Queen: телеметрія/panic | AES-**128**-ECB [transitional] → AES-128-CCM [FW.2, bench-gated] · **session KEYL per-device** |
| Soldier ↔ Queen: control-plane (downlink OTA/beacon/CMD + uplink 0x55/0x56) | AES-128-ECB · **cluster KEYB** (Queen'ин єдиний LoRa-ключ = KEYB-значення) |
| Queen → Rails (CoAP) / downlink | AES-256-CBC (HRNG IV) · KEYC per-gateway |

**Lorenz / StatusByte** (дім `03_04` + `firmware`-скіл — точну bit-розкладку бери ТАМ, не звідси):
- Константи (Float!): `BASE_SIGMA=10.0 · BASE_RHO=28.0 · BASE_BETA=8.0/3.0 · DT=0.01 · ITERATIONS=250 · CRITICAL_Z_MIN=2.0`; anomaly_ceiling **ρ-relative** (E.64), growth_points = метаболічна `m(delta_t)` (E.63, β фіксований; wire-rev2.1 несе EMA-вхід GP — «wire = вхід GP», stateless recompute observational до bench → `03_04 §4.3`).
- StatusByte (post-FW.29): `[PanicFlag:1 | status:2 | growth_points:5]`, пак `(status<<5)|gp`, маска `0x1F`. Ruby unpack 21-байт пакета: `"N n c C n C C a4"`.

## 6. Крос-доменні пастки (gotchas — найчастіші помилки)

> ⛔ **Критерій членства цієї секції, і він вимірюваний.** Пастка живе ТУТ лише якщо стріляє **до того, як домен розпізнано** — тобто в неї можна вступити, не торкнувшись файлів, що інвокують домен-скіл. Усе, що спрацьовує вже всередині домену, живе в `gotchas.md` того скіла й приїде разом із ним. ⚖️ **Зворотне ратифіковано** (`web3-pipeline/gotchas.md`): money-critical інваріанти звідси **вниз не демотуються** заради байтів. 🔴 Третій випадок — факт, чий дім тут ЄДИНИЙ: перш ніж зрізати, грепни ВСІ файли скілів (разом із companion-файлами), не лише `SKILL.md`, і канон.
- 🔴 **DCI = категоричний homeostasis-match, а НЕ поріг:** numeric ε-tolerance стоїть flag-off, і «30%» із `00_03` є ТЕСТ-СЦЕНАРІЄМ, ніколи рантайм-порогом — цього не каже жоден скіл. (Бекендний Lorenz = Float, не BigDecimal — FW.7, бітово ≡ firmware mruby.) → `05_02`/`03_04`.
- **`vcap` = мВ VDDA (VREFINT-cal, FW.50), НЕ Vcap іоністора** — BQ25570 стабілізує ту шину на 3.3 В, тож про запас енергії вона не каже НІЧОГО; порогів на ній чотири, усі вироджені (перелік — `firmware`-скіл #9). 🔴 Інлайн, бо хиба має Rails-поверхню: колонку `AiInsight.avg_vcap` читають із бекенд- і ML-сесій як «заряд». Енергію дерева бекенд читає з ТИШІ (`Tree#fresh_signal?` / `Tree.silent`); хто має право писати той канал — `backend`-скіл #83.
- **Партиції** (RANGE по `created_at`: `TelemetryLog` · `GatewayTelemetryLog` · `BlockchainTransaction`) — передавай `created_at_iso` і клич One-Home, але він **РІЗНИЙ за кардинальністю звертання** (chainable scope ⊥ один рядок ⊥ набір за відомими id); `GatewayTelemetryLog` хелпера свідомо не має. 🔴 Рукописна точна рівність по `created_at` = баг, і на мінт-шляху промах ТИХИЙ. ⛔ `status`-скан — НЕ цей клас: там межа шкідлива (ARCH.52). → `telemetry-pipeline` #6 · `backend`-скіл #59.
- **AES-ключі не покидають Ruby-процес** (`HardwareKey#cached_binary_key` — in-process LRU, без Redis-serialize).
- **AR-encryption ключі** (`hardware_keys`/`users.otp_secret` at-rest) — з ENV `ACTIVE_RECORD_ENCRYPTION_*`, **НЕ** credentials (інакше вертаєш `RAILS_MASTER_KEY`-runtime-залежність, SEC.22); boot-guard fail-closed без них. Зовн.-сервіс-creds = `ENV[..].presence || credentials`; coap-процес пропускає master_key-check → `06_04 §5.7`.
- **`manual_review`** (`BlockchainTransaction` AASM) = double-spend guard: tx_hash є, стан невідомий, кошти заблоковані; **не авто-резолвити**. 🔴 **З ARCH.115 заборону тримає НЕ АВТОМАТ** — подія `confirm`/`fail` приймає `:manual_review`, тож звична форма `tx.confirm! if tx.may_confirm?` тихо авто-резолвить лімб. Хто несе заборону поіменно — `web3-pipeline` #2/#10 · `backend`-скіл #81.
- 💰 **Одиниця, напрямок і валюта грошового рядка не видні з імені колонки — і хиба на будь-якій із трьох осей годує незворотні гарди (на одиниці — у 10 000×).** **Одиниця:** на ОДНОМУ рядку `blockchain_transactions` `amount` = **монети**, сусідній `locked_points` = **бали** (курс `05_03`); `wallets.balance` = бали, `esg_retired_balance` = **монети**; `×10**18` — лише для монет. **Напрямок** — колонка `direction` (`NOT NULL`, ARCH.95), а НЕ деривація з `sourceable_type`; знак `amount` його не видає (slash пишеться ДОДАТНИМ), а `BURN_SOURCEABLE_TYPE` лишився вужчою ознакою «цей burn є слешем»; читач, що напрямку не читає, стверджує «мінт» за замовчуванням (ARCH.101). **Валюта** — `token_type` (ARCH.120): `net_minted_supply` фільтрує по ній і `blockchain_network` не читає, тож рядок у чужій валюті під `:carbon_coin` стає намінтованим SCC — а цей агрегат годує базу слешингу, `total_scc_supply` L1-якоря і `retirable_scc` ESG-погашення; **валюта ⊥ транспорт** (USDC — власний `token_type: :usdc`, не фільтр по мережі). **Передаєш скаляр у money-сервіс — назви одиницю; пишеш рядок — спитай, що позначає напрямок і в якій він валюті; ставиш гард — спитай, чи він міряє ту саму величину, що й предмет** (ARCH.95: гард рахував, скільки БАЛІВ конвертовні, там, де питання було «скільки МОНЕТ Є»). → `web3-pipeline` #19/#20/#34 · `00_07` ARCH.95/ARCH.120.
- **Мінтинг guard-clauses.** Oracle-гілка `verified_by_iotex? && oracle_status_fulfilled?` = PATH 1, латентна (Chainlink-dispatch — local marker без RPC, callback unwired; ARCH.53; замикання відмовлено founder — superseded by Merkle-lineage ARCH.12/MRV.1). Живий PATH 2 мінтить оптимістично; гард — KYC **бенефіціара** [KYC.1]: `Wallet#kyc_approved_for_minting?` (власна адреса → власний статус, custodial успадковує `organizations.hadron_kyc_status`), per-tx SKIP, не raise. ⚠️ Auto-verify на біндингу адреси в проді **НЕ СТАРТУЄ**: єдиний рантайм-писач `approved` адресата не має, тож enqueue гейтований `verification_reachable?` (ARCH.118 · ARCH.119) — custodial-бенефіціар скіпається мовчки щоцикл, і власного лічильника цей скіп не має; чесна L0-custodial + ex-post clawback. Загартований рантайм = `WEB3_STRICT_MODE=="true" || Rails.env.production?` (belt-and-suspenders, INF.11: забутий прапор ≠ fake-KYC mint). 🔑 **Але «чи можна торкатись справжніх грошей» — ДРУГА вісь:** `WEB3_CHAIN_ENV` ∈ `mainnet`/`testnet` (дзеркальні твердження, не bypass; відсутнє → `mainnet`) у `Web3NetworkGuard` поруч із КЛАСОМ ПРОЦЕСУ, який несуть ДВА kwarg-и (`signer_process:` + `web_process:`): ключі скоуплені підписантом, а **presence і формат адрес** — по-змінному через три класи (job ⊥ web ⊥ coap; RPC — `SILENT_RPC_ENVS`), і клас, що змінної не читає, її не судить (INF.27). ⛔ Не читай presence адрес як signer-boot явище: `CARBON_COIN_CONTRACT_ADDRESS` і `ALCHEMY_POLYGON_RPC_URL` мають web-досяжний тихий read-сайт (`ChainAuditService` ковтає збій під RPC-rescue й рапортує хибне «all clean»). W3bstream — **activation-gated**: `Iotex::W3bstreamVerificationService.configured?` = один дім «чи нога жива»; без обох значень жодного enqueue, `verified_by_iotex` чесно false. → `04_02 §Web3NetworkGuard` · `05_02` · `web3-pipeline` · `deploy`-скіл (Hadron-стаб, callback-HMAC, Solana-creds — prod-regardless).
- **SLASH-1 positive-A gate:** необоротний `slash()` (`BlockchainBurningService`) лише за прямого доказу Кат-A (tamper, `Slashing::CauseEvidence#positive_a?`), інакше `:frozen` + Field-Audit; авто-writer'а `vandalism_breach` НЕМАЄ (wire status=3 = `vm_error` софт-збій → `firmware_fault`, справжня пилка = panic→`chainsaw_detected`) → до наповнення A-сету авто-slash фактично freeze-only → `05_05 §3.2`.
- **Frontend:** ⚠️ **`form_with(model:)` виводить із КЛАСУ і маршрут, і префікс параметрів** — на плоских `params` це тихо: `permit` віддає `{}`, `update({})` = **true**, «збережено» без збереження; сирий `input type=file` авто-multipart НЕ вмикає. (Токени, тема, заборона рукописного `<form>` — `frontend`-скіл.) → `04_04` / `04_06 §B.2`.
- **Імʼя Turbo-стріму несе `stream_epoch`** (SEC.25 Ф3): відкликання = `Organization#rotate_stream_epoch!` («покинути адресу»), свідомо НЕ на перемиканні контексту; другий важіль — ротація `TURBO_SIGNED_STREAM_KEY` (глобальна по орг., деплой-часова: верифікатор мемоїзований, без рестарту не діє). Runbook — `06_04 §5.9`, механіка й стелі — `frontend`-скіл #9; організація запиту = `acting_organization!` — `backend`-скіл #19 · `frontend`-скіл #12.
- **Thin controllers** — логіка в `app/services/` / `app/workers/` (контролер = params + authz + render).

## 7. Де що живе (repo map)

```
app/{controllers/api/v1, services/<domain>, workers, views/components}   # Rails моноліт; api/v1 = каталог, НЕ адреса (ARCH.77 → backend-скіл)
firmware/{soldier,queen}/main.c · queen/lorawan_glue/ (ARCH.34 glue до LoRaMac-node) · bio_contracts/ (mruby) · common/ (header-libs) · test/ (host x86)
contracts/*.sol + test/*.t.sol            # Solidity (Foundry) — §8
docs/NN_NN_*.md                           # SSOT canon (00→06); відкрите/блокери → 00_07
tools/{ml, cad, in_silico}                # Python / .NET допоміжні
deploy/alloy · terraform · subgraph       # infra / The Graph
```

Моделі, API, pipeline-кроки, web3-деталі, deploy, активні блокери — **НЕ тут**: відповідний скіл (§2) + `docs/`.

## 8. Solidity / Foundry (контракти SCC/SFC/Governance/Anchor)

**Дім контрактів:** `contracts/*.sol` + парні тести `contracts/test/{Name}.t.sol`; конфіг — `contracts/foundry.toml`. Контракт-спека, ролі й roadmap → [`05_03`](docs/05_03_Tokenomics_SCC_and_SFC.md); **тест-конвенції Foundry** (`test_`/`testRevert_`/`testFuzz_`, `vm.expectRevert` з предметом) та інваріант-гейти → [`04_06 §B.2`](docs/04_06_Testing_Guide_and_Coverage.md) п.6/6а; операційний прогін і CI-аудит → скіл `web3-pipeline`.

💰 **Інлайн — розкол ключів на грошовому шляху:** `slash()` = `SLASHER_ROLE`, `mint()` = `MINTER_ROLE`, **фізично різні ключі** (E.2); решта адмін-ролей — через Timelock, крім `pause`. Рядок про роль пишуть із бекенд- і деплой-сесій, де `web3-pipeline` не інвокується. `Solidity passed` — required-чек branch protection (OPS.15); ⚠️ прямий push власника required-периметр обходить, тож на цьому шляху стоїть лише локальний `pre-push`.
