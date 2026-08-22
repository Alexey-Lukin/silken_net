# SilkenNet — контекст для Claude (orientation + routing)

> **Цей файл prepend-иться в КОЖЕН промпт — він тугий orientation, НЕ manual.** Глибина живе в `docs/` (canon, `00_00`→`06_08`) + скілах (авто-інвокуються). Один факт — один дім (`00_06 §2`): тут — філософія, навігація, критичні інваріанти, крос-доменні пастки; решта — pointers. Конфлікт із `docs/` → **canon WINS**.

## 1. Що це

Планетарна Bio-IoT **D-MRV** платформа моніторингу лісів: Ti-6Al-4V гіроїдний анкер + **EBFC** (≈500 мВ з ксилеми, «zero-grid») → STM32 **«Soldier»** (sense→TinyML→Lorenz→encrypt→LoRa 868) → **«Queen»** gateway (CoAP) → Rails 8.1 / Ruby 4.0.6 / Postgres / Sidekiq → 12-chain Web3 **Proof-of-Growth** → mint SCC (**10 000 growth_points = 1 SCC**, Polygon ERC-20; слешинг при деградації).

**Чесний стан** (TRL-дім `docs/00_03`; числа pipeline — `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`): firmware **TRL 6** · backend **TRL 8** · anchor/EBFC **TRL 3** (in-silico Zero-Lab ✅; фізичний TRL 4 = in-vitro Ti-coin pending — **in-silico ≠ TRL 4** за NASA/ISO). **System TRL = 3** (gated by anchor/EBFC). **Polyglot:** Rails (Ruby) · firmware-C (STM32) · mruby (`bio_contract`) · Solidity (Foundry) · in-silico Python (DFT/MD) · .NET C# (PicoGK CAD).

## 2. Як тут працювати

**Скіли авто-інвокуються за доменом і маршрутизують у точний canon-doc. НЕ читай усі docs наосліп — дай скілу привести тебе.** Канон-bird's-eye (🎯/TRL/секції 00→06, без читання всього) → `ruby scripts/doc_structure_map.rb`.

| Домен | Скіл (авто) | Дім-canon |
|-------|-------------|-----------|
| STM32 firmware (Soldier/Queen, mruby, `firmware/common`) | `firmware` | `03_01`–`03_05` |
| Factory-flashing (per-device key provisioning at manufacture, SEC.3) | `factory-flashing` | `03_06` |
| Web3 / контракти / minting / slashing | `web3-pipeline` | `05_01`–`05_06` |
| Telemetry / Proof-of-Growth / Sidekiq-черги | `telemetry-pipeline` | `05_02` (+§5) |
| Frontend (Phlex / Tailwind v4 / Stimulus / Turbo) | `frontend` | `04_04` (+`04_06 §A`) |
| Backend Web2-core (моделі · REST API v1 · auth/RBAC · non-money сервіси·воркери · MaintenanceRecord) | `backend` | `04_01`–`04_03` (+`04_06`) |
| TinyML / log-mel / INT8 | `ml-engineering` | `03_03` + `tools/ml` |
| EBFC DFT/MD in-silico | `in-silico` | `01_03` + `protocols/ebfc/in_silico` |
| Code-as-CAD (анкер/coin/radome) | `picogk` | `01_01/01_02/02_01/02_02` + `tools/cad` |
| Hardware §02 (BOM · BQ25570-power · pogo-механіка · Queen-HW) | — (bench-важка, скілу НЕМА) · machine-half: механіка→`in-silico` (5x-скрипти), CAD→`picogk`, energy/SCC-гейти `tools/firmware/*.rb`; bench-збірка → `02_04`; BOM-рол-ап/юніт-економіка → `02_06` (дім у скіла `legal-business`) | `02_01`–`02_05` |
| Деплой / Akash / Kamal / observability | `deploy` | `06_01`–`06_08` |
| Юр/бізнес/академ/IP (NaaS-умови · юніт-економіка · партнер-реєстр · IP-постава й бренд · робочі чернетки `protocols/{legal,business,outreach,research}`) | `legal-business` | `00_04` · `00_02` · `02_06` (юніт-економіка/BOM-рол-ап) (+ стан `00_07 §00b`) |
| Оновлення залежностей (будь-який домен) | `dependency-update` | (polyglot) |
| SSOT-доки / drift-hunt / wiki-sync | `ssot-maintenance` | `00_06` |
| **Подія, а не домен:** будуєш ГЕЙТ · питаєш «чи ця спека ВЗАГАЛІ здатна впасти» · масово ВИДАЛЯЄШ · ЗВУЖУЄШ правило · ведеш КАМПАНІЮ | `ssot-maintenance` → **`guard-craft.md`** (on-demand). ⊥ **ФОРМА** спеки (конвенції · фікстури · покриття · тріаж) — це інше питання й інший дім: `04_06` | `00_06 §3` |
| Персистентна пам'ять | `memory-maintenance` | `memory/` |

**SSOT one-home (`00_06 §2`):** `docs/NN_NN_*.md` = canon; **`docs/00_07` = дім УСІХ відкритих робіт + блокерів** — ніколи не вважай «resolved» без реального code+canon (не вір TODO/коментарю); **дзеркально — тоншаючи/архівуючи пункт, ПЕРШ прочитай повну канон-секцію: grep-hit ≠ канонізовано** (гейти самі grep-based → тиха втрата факту проходить зеленою); ⊕ **і БЕРУЧИ пункт у роботу — читай його тіло ЦІЛКОМ (`####`→`####`): ⛔/⚖️ всередині = гейт, не примітка, grep-hit мандату не дає.** Канон / drift / wiki — лише через `ssot-maintenance`. Не дублюй факти між домами.

**Verify / commit:** тести (§3) перед коммітом, full-suite перед push. `db/structure.sql` (НЕ `schema.rb`); dump потребує **pg17 `pg_dump`** (dev-сервер pg17, а PATH віддає 16 → `POSTGRES_BIN_PATH=/opt/homebrew/opt/postgresql@17/bin`). ⚠️ Стрипати `transaction_timeout` більше НЕ треба — CI піднято на pg17 до паритету з продом (OPS.27); паритет CI⟷terraform гейтований. Коміт-меседж → `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>` (trailer = поточна модель сесії — звіряй, не хардкодь наосліп); гілка від `main` лише якщо просять. Перед edit широко-вживаного символу — простеж викликачів/blast-radius (auth/money = критичний шлях); перед commit — звір scope діфу проти очікуваного (не find-replace-rename наосліп).

## 3. Середовище

```bash
ruby --version            # 4.0.6
bin/rubocop -a            # lint (binstub; -a = автофікс)
bin/rspec                 # backend suite (binstub; full ~1.5min)
bin/brakeman              # security
bin/bundler-audit check
make -C firmware/test     # firmware host-tests (x86, без ARM)
make -C firmware/test asan # + ASan/UBSan memory-safety смуга (TEST.5)
cd contracts && forge test -vvv --gas-report   # Solidity (Foundry; §8)
ruff check                # Python (in-silico/ml), root ruff.toml
bundle exec i18n-tasks missing   # i18n-парність (+`check-consistent-interpolations`, `check-normalized`)
```

**Носій ≠ список команд.** Смуга `Docs` = `ruby scripts/docs_band.rb` (кроки читаються з `docs.yml`, не з голови). **i18n-трійка вище вже стоїть на `.githooks/pre-push`** разом із DCO — тобто спрацьовує, навіть якщо про неї не згадати (I18N.4); поріг хука — ЦІНА (~4 с виміряно), не кількість перевірок, тож повна сюїта туди не їде. Усі три дискримінують exit-кодом; «`check-normalized` завжди 0» — мертве твердження (гем 1.1.2).

## 4. Стиль коду: драбинка «лінивого сеньйора» (YAGNI-first)

Найкращий код — той, що не написано. Лінивий = ефективний, не недбалий. **Перед тим як писати код, спинись на першій сходинці, що тримає:**

1. Чи це взагалі треба будувати? (YAGNI — якщо ні, пропусти)
2. Чи це вже робить кремній / stdlib? (firmware: HAL CRYP/RNG/RTC, CMSIS; Rails 8: `generates_token_for`, AASM, Solid*, ActiveSupport; Postgres: партиції, GREATEST, JSONB) — використай.
3. Чи покриває нативна платформа? (фронт: HTML/Turbo/Phlex *до* Stimulus; on-chain: OpenZeppelin *до* власного) — використай.
4. Чи вже встановлена залежність це вирішує? — так; нову залежність лише якщо неминуче (домен-валідація → скіл `dependency-update`).
5. Можна одним рядком? — зроби одним рядком.
6. Лише тоді — мінімум коду, що працює.

Це той самий етос, що **Ruthless Pruning** (`00_06 §4`), comment-hygiene і **KENOSIS TITAN** hot-path; драбинка лише форсує його *до* написання: видалення > додавання, нудне > розумне, жодних незапитаних абстракцій, найменше файлів.

**НЕ лінуватися (тут несуче):** валідація на межах довіри (виняток — hot-path телеметрії свідомо без неї, KENOSIS → `TelemetryUnpackerService.valid_sensor_data?`); безпека/Zero-Trust (AES, HMAC, Argon2id); error-handling проти втрати коштів (`manual_review` double-spend guard); **і головне для нас — чесність про залізо: платформа ≠ ідеал специфікації (годинник дрейфує, сенсор бреше, in-silico ≠ TRL).** Енерго/RAM/газ-бюджет — теж не місце для «розумного»: лінивий = менший .bss/Flash/цикли/gas.

Свідоме спрощення → познач **наявною** конвенцією (`[FW.N]` · `[transitional]` · `target FW.2` · `bench-gated` · `→ 00_07 <ID>`), що називає стелю (global lock, O(n²), наївна евристика) і шлях апгрейду. Без позначеної стелі спрощення = недороблене: нетривіальна логіка лишає ОДНУ runnable-перевірку (assert-демо чи один тест); тривіальний однорядковик — ні.

## 5. Критичні інваріанти (тримай інлайн; точна деталь — за pointer)

**Sidekiq strict-priority** (`:strict: true` — послідовний дренаж згори-вниз, НЕ зважений; дім `04_02`). Не міняй чергу воркера без обґрунтування:
```
uplink(1) > alerts(2) > critical(3) > downlink(4) > default(5) > web3_critical(6) > web3(7) > web3_low(8) > low(9)
```

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

- **Backend Lorenz = Float (IEEE 754 double)**, НЕ BigDecimal (FW.7 — бітово ≡ firmware mruby; DCI = категоричний homeostasis-match, numeric ε-tolerance flag-off — «30%» = тест-сценарій `00_03`, НЕ рантайм-поріг) → `05_02`/`03_04`.
- **ECB-restore:** Queen після CBC-flush ОБОВ'ЯЗКОВО відновлює `CRYP_KEYSIZE_128B`+LoRa-key, інакше LoRa-decrypt ламається → `firmware`-скіл.
- **Key-scoping CCM-ери (FW.2 (в)):** амбієнтний `hcryp` Солдата = **KEYB** (control-plane); session KEYL живе ЛИШЕ в CCM-скоупі — `MX_CRYP_Init_CCM` ставить `pKey` ЯВНО, Restore повертає KEYB (липкий session = Rails MIC-fail'ить кожен кадр). Ратчет FW.17 ротує лише session. Mesh-Сценарій Б у CCM-збірці гейтовано геть (star-only) → `firmware`-скіл / `03_05 §3.1`.
- **`Load_AES_Key` ПЕРЕД `MX_CRYP_Init`**; **`vcap` = мВ VDDA (VREFINT-cal, FW.50), НЕ Vcap іоністора** — BQ25570 стабілізує ту шину на 3.3 В, тож вона про запас енергії не каже НІЧОГО, і порогів на ній **чотири**, усі вироджені (перелік + які саме — `firmware`-скіл #9; ARCH.99: доти канон називав три з чотирьох, а `Should_Defer_TX` тихо звівся до самої температури). Backend-шкали заряду більше не існує — енергія дерева читається з ТИШІ (`Tree#fresh_signal?` / `Tree.silent`); **`HAL_GetTick` заморожений у STOP2** (wall-time через RTC) → `firmware`-скіл / `03_01`.
- **KENOSIS:** `TelemetryLog` без AR-валідацій — перевірка лише в `TelemetryUnpackerService.valid_sensor_data?`; не додавай назад.
- **Queen-пульс = ПІДПИСАНИЙ QATT-v2 header (ARCH.54):** DID=0-запис у телеметрії-батчі МЕРТВИЙ обабіч (дропається) — gateway-метрики НЕ пакуються псевдодеревом; дім health = 8B-блок конверта (`queen_attest.h`) → `enqueue_envelope_health`; dead-man switch = `GatewayStalenessSweepWorker` → `06_08 §1.3` / `03_02 §7`.
- **Партиції** (RANGE по `created_at`; моделей **три** — `TelemetryLog`/`GatewayTelemetryLog`/`BlockchainTransaction`): завжди передавай `created_at_iso`, і клич One-Home — але він **РІЗНИЙ**: `TelemetryLog.partition_pruned(iso, metric_caller:)` (chainable scope) ⊥ `BlockchainTransaction.find_with_partition_pruning(id, created_at, metric_caller:)` (ОДИН рядок) ⊥ `BlockchainTransaction.where_ids_pruned(ids, span, metric_caller:)` (НАБІР за відомими id — мінт-тракт працює батчами); `GatewayTelemetryLog` хелпера не має, і це свідомо (нуль id-звертань). 🔴 Рукописна точна рівність по `created_at` = баг (ISO несе секунди, колонка мікросекунди — хелпери тримають 1-с вікно саме тому), і на мінт-шляху промах ТИХИЙ. ⛔ **`status`-скан — НЕ цей клас: там межа ШКІДЛИВА** (reset-to-pending тримає старий `created_at` → осиротить застряглі кошти; важіль = partial index, ARCH.52). Правило: **вікно прунить звертання за ВІДОМИМ рядком; множину невідомого розміру прунить індекс.** Носій — `spec/quality/partition_key_discipline_spec.rb` (декларація на кожен `.reload` і на кожне id-звертання).
- 📅 **Доба денного інсайту = ОДИН дім `AiInsight.reporting_date`** (ARCH.100): писач штампує UTC-добу, `for_date` шукає ТОЧНОЮ рівністю — тож власний вираз дати у читача = промах, і він ТИХИЙ (порожня вибірка не є помилкою). Пер-орендарський `local_yesterday` розходився з писачем для всіх поясів західніше UTC−2, і одна вигадана порожнеча давала ЧОТИРИ вироки протилежного знаку: `health_index` 1.0 «здоровий» ⊥ `:blackout` → Field Audit + невиплачена Celo ⊥ страховий no-data ⊥ `:frozen` на слешингу. Гейт `reporting_date_home_spec` стереже дві відомі форми, третю (`1.day.ago.to_date`…) статично не видно → `backend` #36 / `web3-pipeline` #8 / `04_01 §7`.
- **`oracle_status`** має prefix → `oracle_status_fulfilled?` (НЕ `fulfilled?`).
- **AES-ключі не покидають Ruby-процес** (`HardwareKey#cached_binary_key` — in-process LRU, без Redis-serialize).
- **AR-encryption ключі** (`hardware_keys`/`identities` at-rest) — з ENV `ACTIVE_RECORD_ENCRYPTION_*`, **НЕ** credentials (інакше вертаєш `RAILS_MASTER_KEY`-runtime-залежність, SEC.22); boot-guard fail-closed без них. Зовн.-сервіс-creds = `ENV[..].presence || credentials`; coap-процес пропускає master_key-check → `06_04 §5.7`.
- **`manual_review`** (`BlockchainTransaction` AASM) = double-spend guard (tx_hash є, стан невідомий, кошти заблоковані); не авто-резолвити.
- 💰 **Одиниця й напрямок грошового рядка не видні з імені колонки, і обидва коштують 10 000×.** На ОДНОМУ рядку `blockchain_transactions`: `amount` = **монети**, сусідній `locked_points` = **бали** (курс `05_03`); `wallets.balance` = бали, `×10**18` застосовне лише до монет. Мінт/burn теж не поле, а ДЕРИВАЦІЯ — дім значення `BURN_SOURCEABLE_TYPE`, читають ОБИДВА споживачі (SQL-агрегат `net_minted_supply` ⊥ рядковий предикат `#burn?`; знак `amount` напрямку не видає — slash пишеться ДОДАТНИМ). Burn-подібний рядок без цього sourceable рахується як емісія в One-Home, а той годує L1-якір і базу слешингу; **дзеркально — читач, що напрямку не деривує, стверджує «мінт» за замовчуванням** (стрічка дашборда роками друкувала спалення емісією, приписаною дереву за DID → ARCH.101). Канон-формула `05_05 §3` роками звала базою `locked_balance` (бали!) — буквальна реалізація палила б у 10 000× більше. **Передаєш скаляр у money-сервіс — назви одиницю; пишеш рядок — спитай, що позначає напрямок** → `web3-pipeline` #20 / `00_07` ARCH.95 (⚖️, тракт fail-closed).
- **Мінтинг guard-clauses:** oracle-гілка `verified_by_iotex? && oracle_status_fulfilled?` = PATH 1 (latent — ARCH.53 §🗄️: Chainlink-dispatch = local marker без RPC, callback unwired; замикання PATH 1 відмовлено founder 2026-07-19 — superseded by Merkle-lineage ARCH.12/MRV.1); живий PATH 2 мінтить оптимістично (guard = KYC **бенефіціара** [KYC.1]: `Wallet#kyc_approved_for_minting?` — власна адреса → власний статус, custodial успадковує `organizations.hadron_kyc_status`; per-tx SKIP, не raise; auto-verify на біндингу адреси; чесна L0-custodial + ex-post clawback). `WEB3_STRICT_MODE=="true" || Rails.env.production?` (belt-and-suspenders — Hadron був ЄДИНИЙ flag-only, hardened INF.11 2026-07-10; забутий прапор ≠ fake-KYC mint) → Hadron-стаб + callback-HMAC + W3bstream raise на missing-creds (lazy at-call; IoTeX-fallback + Solana-creds теж prod-regardless) → `05_02` / `web3-pipeline`.
- **SLASH-1 positive-A gate:** необоротний `slash()` (`BlockchainBurningService`) лише за прямого доказу Кат-A (tamper, `Slashing::CauseEvidence#positive_a?`), інакше `:frozen` + Field-Audit; авто-writer'а `vandalism_breach` НЕМАЄ (wire status=3 = `vm_error` софт-збій → `firmware_fault`, справжня пилка = panic→`chainsaw_detected`) → до наповнення A-сету авто-slash фактично freeze-only → `05_05 §3.2`.
- **Frontend:** лише дизайн-токени (`bg-gaia-surface`…) — HARD-гейт на `shared/` + зміряно-чисті домени (дім периметра = `default_scopes` у `gaia_lint.rake`, не тут), але **правило ширше за периметр гейта** (⚖️ 08-07 «світла тема ПІДТРИМУВАНА» + ⚖️ 08-08 «тумблер знято, тему обирає **ОС**, палітри лишаються — вони mutation-тест дизайн-системи; токен-шар обовʼязковий, і його легалізація = єдина незворотна дія»): сира палітра легальна лише тем-інваріантна **й оголошена**, інакше це дефект теми, не естетика (`04_04 §3.5`); однотемний екран — лише ОГОЛОШЕНИЙ, але живих екземплярів у дереві **нуль** (хардкод `AuthLayout` знято разом із тумблером — він лишався єдиним, що опиралось середовищу). ⚠️ Демонтаж ШИПНУТО 08-08: тема = `@media screen and (prefers-color-scheme: dark)`, класу `.dark` і JS у цьому ланцюгу немає взагалі; `screen and` несуче — без нього `dark:`-утиліти лишаються темними на ДРУЦІ (`04_04 §1`/`§3`). `tokens(...)`, без DB у Phlex `initialize`, `focus-visible:` → `04_04`. **Дію рендери через `button_to`/`form_with`, ніколи рукописним `<form>`** (UI.7) — ✅ **HARD, нульовий виняток** (`phlex_no_handwritten_form_spec`, ⚖️ 08-15, 11→0): той не несе CSRF-токена, а `method="delete"` — невалідне значення; і НЕ рендер `button_to`-нащадка всередині `form_with` (парсер переносить його `_method` у зовнішню форму). ⚠️ `form_with(model:)` виводить із КЛАСУ і маршрут, і префікс параметрів — на плоских `params` це тихо: `permit` віддає `{}`, `update({})` = **true**, «збережено» без збереження; сирий `input type=file` авто-multipart НЕ вмикає. **Компонентна спека сліпа по двох осях одразу — вона рендерить повз маршрутизатор І повз викликача**, тож хибну ціль дії та вигаданий — чи навпаки ВІДСУТНІЙ — у фікстурі ключ/шкалу ловить лише request-приклад → `04_06 §B.2` BP #14.
- **Організація запиту = `acting_organization!`, НЕ `current_user.organization`** (SEC.25 Ф2): super_admin працює в контексті ОДНІЄЇ організації за раз і перемикає її (`session[:acting_org_id]`); Pundit дістає `UserContext` (несе лише org — `delegate_missing_to` там fail-OPEN на `present?`); політику звужуй ПАРОЮ `Scope`+предикат. ⚖️ **Але Pundit тут НЕ основний носій ізоляції:** асоціативний скоуп — архітектура, не борг (ратифіковано 07-31 → 10 мертвих політик знято, `verify_authorized` = won't-do), тож «уніфікувати все на Pundit» — вже відхилена пропозиція, `04_03 §3`. **Дзеркало цього в UI:** компонент, що рендерить гейтовану дію, мусить ПРИЙМАТИ актора, дефолт fail-closed (UI.5/UI.6 → `04_04 §6.4`). Броадкаст натомість іде в org **власника** ресурсу, не глядача → `04_01 §5`. Ім'я Turbo-стріму несе `stream_epoch` (Ф3) — відкликання = `Organization#rotate_stream_epoch!` («покинути адресу»), і воно СВІДОМО не спрацьовує на перемиканні контексту; другий важіль — ротація `TURBO_SIGNED_STREAM_KEY` (глобальна по орг., **деплой-часова**: верифікатор мемоїзований, тож без рестарту не діє).
- **Thin controllers** — логіка в `app/services/` / `app/workers/` (контролер = params + authz + render).

## 7. Де що живе (repo map)

```
app/{controllers/api/v1, services/<domain>, workers, views/components}   # Rails моноліт; api/v1 = каталог, НЕ адреса (ARCH.77 → backend-скіл)
firmware/{soldier,queen}/main.c · queen/lorawan_glue/ (ARCH.34 glue до LoRaMac-node) · bio_contracts/ (mruby) · common/ (header-libs) · test/ (host x86)
contracts/*.sol + test/*.t.sol            # Solidity (Foundry) — §8
docs/NN_NN_*.md                           # SSOT canon (00→06); відкрите/блокери → 00_07
tools/{ml, cad, in_silico}                # Python / .NET допоміжні
deploy/akash · terraform · subgraph       # infra / The Graph
```

Моделі, API, pipeline-кроки, web3-деталі, deploy, активні блокери — **НЕ тут**: відповідний скіл (§2) + `docs/`. Відкрите/блокери = `docs/00_07`.

## 8. Solidity / Foundry (контракти SCC/SFC/Governance/Anchor)

**Дім контрактів:** `contracts/*.sol` + парні тести `contracts/test/{Name}.t.sol`. Конфіг — `contracts/foundry.toml` (профілі `default`/`production`); `forge-std` через `npm ci`. Контракт-спека + ролі → `docs/05_03`; тест-методологія всіх шарів → `docs/04_06 §B`.

**Конвенції тестів (must):**
- Naming: `test_` (happy-path) · `testRevert_` (expected revert) · `testFuzz_` (property/fuzz) · `check_` (Halmos symbolic, `test/symbolic/`) · `property_` (Medusa fuzz, `test/medusa/`) · `invariant_` (Foundry stateful, `test/invariant/`).
- `makeAddr("name")` (НЕ `address(0xN)`) · `vm.prank(caller)` на КОЖЕН виклик (НЕ `startPrank` без `stopPrank`).
- `vm.expectRevert` — завжди з предметом, ніколи голий. 🔴 **Чому це не косметика:** голий проходить при реверті з **будь-якої** причини, а наші revert-тести майже всі стережуть `AccessControl`/`Pausable` — тож регресія, що зламає `onlyRole(MINTER_ROLE)` так, що реверт лишиться (напр. арифметика падає раніше по шляху), пройде **зеленою на тесті, названому саме за цю властивість**. **Ідіом залежить від джерела реверту:** наш `require(cond, "рядок")` → `vm.expectRevert("exact error string")`; **OZ 5.7 кидає custom errors** (`AccessControlUnauthorizedAccount` · `EnforcedPause` · Timelock/Governor) → `vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, actor, role))`, а якщо аргумент непередбачуваний (recovered signer) → `vm.expectPartialRevert(selector)`. ⚠️ Власних custom errors наші контракти не мають — тож «exact string» застосовний ЛИШЕ до `require`-рядків. Голих `expectRevert()` у дереві **нуль** (25 ретрофітнуто 2026-08-09, TEST.14); гейта на цю вісь нема — її тримає ревʼю, бо голий виклик неможливо відрізнити від легітимного «будь-який реверт» статично.
- `vm.expectEmit(...) + emit Event(...)` ПЕРЕД викликом · `bound(x,min,max)` > `vm.assume`.
- `vm.warp` / `vm.roll` для timelock / ERC20Votes-checkpoint (snapshot voting) логіки.

**Інваріант-гейти (обов'язкові тести):**
- `testRevert_cannotRemoveLastAdmin` — кожен контракт з `AccessControl` (`_adminCount` guard); **enforced** кроком `solidity_audit.yml` (патерн без префікса — той гейт стереже наявність тесту, НЕ конвенцію імені). Конвенцію імені стереже **окремий** гейт (`scripts/solidity_test_naming_check.rb`, HARD там само): тіло з `expectRevert` ⊥ ім'я `test_*` → RED. Дві осі свідомо роз'єднані — злиття їх в одну умову вимагало б переіменувань, а імена ключують `.gas-snapshot`. 🔴 **Тому переіменування revert-тесту НЕ буває окремим комітом:** воно міняє й ключі, й газ сусідів (ім'я → селектор → порядок диспетчера), тож їде разом із `forge snapshot --no-match-test "invariant_|testFuzz_"`.
- `test_pause_allowsSlash` — SCC/SFC `slash()` ОБОВ'ЯЗКОВО працює під `pause()` (B-07).
- `totalSupply() <= MAX_SUPPLY` (1B SCC) після будь-якої послідовності операцій.
- Усі 3 **доведені Halmos** (`check_*` у `test/symbolic/` — symbolically, не семпл; loop-bound `--loop 3`). ⚠️ **Medusa-фаз покриває з них ЛИШЕ supply-cap** (`property_totalSupplyWithinCap`): гарнеси не мають обгорток `pause`/ролей взагалі, тож `property_`-дзеркал для last-admin і pause-allows-slash **не існує** — дім діри `00_07` CONTRACT.2.

**Команди + ролі:** `forge test -vvv --gas-report` · `forge build --sizes` (ліміт EIP-170 = 24KB) · `forge coverage --report lcov` (→ CI lcov-артефакт, ≥90% floor). **CI-аудит** (`solidity_audit.yml`, CI-gated не локально): Slither + `aderyn .` **gate-на-high** (static); `halmos --function "^check_"` (symbolic) + `medusa fuzz --config medusa-{scc,sfc}.json` (fuzz) — усі **fail-on** у своєму job + `Solidity passed` aggregate = **merge-required** branch-protection check (OPS.15, 2026-07-19; money-path більше не мерджиться червоним). On-chain адмін-ролі → Timelock (крім `pause`); `slash()` = `SLASHER_ROLE`, `mint()` = `MINTER_ROLE` (фізично розділені ключі, E.2).
