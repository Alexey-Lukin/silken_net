# SilkenNet — контекст для Claude (orientation + routing)

> **Цей файл prepend-иться в КОЖЕН промпт — він тугий orientation, НЕ manual.** Глибина живе в `docs/` (canon, `00_00`→`08_03`) + скілах (авто-інвокуються). Один факт — один дім (`00_06 §2`): тут — філософія, навігація, критичні інваріанти, крос-доменні пастки; решта — pointers. Конфлікт із `docs/` → **canon WINS**.

## 1. Що це

Планетарна Bio-IoT **D-MRV** платформа моніторингу лісів: Ti-6Al-4V гіроїдний анкер + **EBFC** (≈500 мВ з ксилеми, «zero-grid») → STM32 **«Soldier»** (sense→TinyML→Lorenz→encrypt→LoRa 868) → **«Queen»** gateway (CoAP) → Rails 8.1 / Ruby 4.0.5 / Postgres / Sidekiq → 12-chain Web3 **Proof-of-Growth** → mint SCC (**10 000 growth_points = 1 SCC**, Polygon ERC-20; слешинг при деградації).

**Чесний стан** (TRL-дім `docs/00_03`; числа pipeline — `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`): firmware **TRL 6** · backend **TRL 8** · anchor/EBFC **TRL 3** (in-silico Zero-Lab ✅; фізичний TRL 4 = in-vitro Ti-coin pending — **in-silico ≠ TRL 4** за NASA/ISO). **System TRL = 3** (gated by anchor/EBFC). **Polyglot:** Rails (Ruby) · firmware-C (STM32) · mruby (`bio_contract`) · Solidity (Foundry) · in-silico Python (DFT/MD) · .NET C# (PicoGK CAD).

## 2. Як тут працювати

**Скіли авто-інвокуються за доменом і маршрутизують у точний canon-doc. НЕ читай усі docs наосліп — дай скілу привести тебе.** Канон-bird's-eye (🎯/TRL/секції 00→08, без читання всього) → `ruby scripts/doc_structure_map.rb`.

| Домен | Скіл (авто) | Дім-canon |
|-------|-------------|-----------|
| STM32 firmware (Soldier/Queen, mruby, `firmware/common`) | `firmware` | `03_01`–`03_05` |
| Web3 / контракти / minting / slashing | `web3-pipeline` | `05_01`–`05_06` |
| Telemetry / Proof-of-Growth / Sidekiq-черги | `telemetry-pipeline` | `05_02` (+§5) |
| Frontend (Phlex / Tailwind v4 / Stimulus / Turbo) | `frontend` | `04_04` (+`04_06 §A`) |
| TinyML / log-mel / INT8 | `ml-engineering` | `03_03` + `tools/ml` |
| EBFC DFT/MD in-silico | `in-silico` | `01_03` + `protocols/ebfc/in_silico` |
| Code-as-CAD (анкер/coin/radome) | `picogk` | `01_01/01_02/02_01/02_02` + `tools/cad` |
| Деплой / Akash / Kamal / observability | `deploy` | `06_01`–`06_08` |
| Оновлення залежностей (будь-який домен) | `dependency-update` | (polyglot) |
| SSOT-доки / drift-hunt / wiki-sync | `ssot-maintenance` | `00_02` + `00_06` |
| Персистентна пам'ять | `memory-maintenance` | `memory/` |
| Навігація коду / impact / blast-radius | `gitnexus` (MCP — блок наприкінці) | — |

**SSOT one-home (`00_06 §2`):** `docs/NN_NN_*.md` = canon; **`docs/00_07` = дім УСІХ відкритих робіт + блокерів** — ніколи не вважай «resolved» без реального code+canon (не вір TODO/коментарю). Канон / drift / wiki — лише через `ssot-maintenance`. Не дублюй факти між домами.

**Verify / commit:** тести (§3) перед коммітом, full-suite перед push. `db/structure.sql` (НЕ `schema.rb`); dump потребує **pg17 `pg_dump`** + **strip pg17-only `transaction_timeout` рядок** (CI-Postgres <17 інакше падає). Коміт-меседж → `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`; гілка від `main` лише якщо просять. gitnexus: `impact` перед edit символу, `detect_changes` перед commit.

## 3. Середовище

```bash
ruby --version            # 4.0.5
bin/rubocop -a            # lint (binstub; -a = автофікс)
bin/rspec                 # backend suite (binstub; full ~1.5min)
bin/brakeman              # security
bin/bundler-audit check
make -C firmware/test     # firmware host-tests (x86, без ARM)
make -C firmware/test asan # + ASan/UBSan memory-safety смуга (TEST.5)
cd contracts && forge test -vvv --gas-report   # Solidity (Foundry; §8)
ruff check                # Python (in-silico/ml), root ruff.toml
```

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

**AES-режими** (post-ARCH.42 Variant B; дім `03_05 §3.7`):

| Напрямок | Режим |
|----------|-------|
| Soldier → Queen (LoRa) | AES-**128**-ECB [transitional] → AES-128-CCM [FW.2 target] |
| Queen → Soldier (OTA) | AES-128-ECB |
| Queen → Rails (CoAP) / downlink | AES-256-CBC (HRNG IV) |

**Lorenz / StatusByte** (дім `03_04` + `firmware`-скіл — точну bit-розкладку бери ТАМ, не звідси):
- Константи (Float!): `BASE_SIGMA=10.0 · BASE_RHO=28.0 · BASE_BETA=8.0/3.0 · DT=0.01 · ITERATIONS=250 · CRITICAL_Z_MIN=2.0`; anomaly_ceiling **ρ-relative** (E.64), growth_points = метаболічна `m(delta_t)` (E.63, β фіксований).
- StatusByte (post-FW.29): `[PanicFlag:1 | status:2 | growth_points:5]`, пак `(status<<5)|gp`, маска `0x1F`. Ruby unpack 21-байт пакета: `"N n c C n C C a4"`.

## 6. Крос-доменні пастки (gotchas — найчастіші помилки)

- **Backend Lorenz = Float (IEEE 754 double)**, НЕ BigDecimal (FW.7 — бітово ≡ firmware mruby; DCI divergence>30% → fraud) → `05_02`/`03_04`.
- **ECB-restore:** Queen після CBC-flush ОБОВ'ЯЗКОВО відновлює `CRYP_KEYSIZE_128B`+LoRa-key, інакше LoRa-decrypt ламається → `firmware`-скіл.
- **`Load_AES_Key` ПЕРЕД `MX_CRYP_Init`**; **`vcap` = мВ VDDA (VREFINT-cal, FW.50), НЕ Vcap іоністора** (fauna-гейт 4500 свідомо fail-closed до Vcap-каналу); **`HAL_GetTick` заморожений у STOP2** (wall-time через RTC) → `firmware`-скіл / `03_01`.
- **KENOSIS:** `TelemetryLog` без AR-валідацій — перевірка лише в `TelemetryUnpackerService.valid_sensor_data?`; не додавай назад.
- **Queen-пульс = ПІДПИСАНИЙ QATT-v2 header (ARCH.54):** DID=0-запис у телеметрії-батчі МЕРТВИЙ обабіч (дропається) — gateway-метрики НЕ пакуються псевдодеревом; дім health = 8B-блок конверта (`queen_attest.h`) → `enqueue_envelope_health`; dead-man switch = `GatewayStalenessSweepWorker` → `06_08 §1.3` / `03_02 §7`.
- **Партиції** (`TelemetryLog` / `GatewayTelemetryLog` / `BlockchainTransaction`): завжди передавай `created_at_iso` + `find_with_partition_pruning`.
- **`oracle_status`** має prefix → `oracle_status_fulfilled?` (НЕ `fulfilled?`).
- **AES-ключі не покидають Ruby-процес** (`HardwareKey#cached_binary_key` — in-process LRU, без Redis-serialize).
- **`manual_review`** (`BlockchainTransaction` AASM) = double-spend guard (tx_hash є, стан невідомий, кошти заблоковані); не авто-резолвити.
- **Мінтинг guard-clauses:** `verified_by_iotex? && oracle_status_fulfilled? && hadron_kyc_status == "approved"`; `WEB3_STRICT_MODE=true` (prod) → стаби-raises (lazy at-call; IoTeX-fallback + Solana-creds raise у prod незалежно від прапора) → `05_02` / `web3-pipeline`.
- **SLASH-1 positive-A gate:** необоротний `slash()` (`BlockchainBurningService`) лише за прямого доказу Кат-A (tamper, `Slashing::CauseEvidence#positive_a?`), інакше `:frozen` + Field-Audit → `05_05 §3.2`.
- **Frontend:** лише дизайн-токени (`bg-gaia-surface`…) у shared-компонентах, `tokens(...)`, без DB у Phlex `initialize`, `focus-visible:` → `04_04`.
- **Thin controllers** — логіка в `app/services/` / `app/workers/` (контролер = params + authz + render).

## 7. Де що живе (repo map)

```
app/{controllers/api/v1, services/<domain>, workers, views/components}   # Rails моноліт
firmware/{soldier,queen}/main.c · bio_contracts/ (mruby) · common/ (header-libs) · test/ (host x86)
contracts/*.sol + test/*.t.sol            # Solidity (Foundry) — §8
docs/NN_NN_*.md                           # SSOT canon (00→08); відкрите/блокери → 00_07
tools/{ml, cad, in_silico}                # Python / .NET допоміжні
deploy/akash · terraform · subgraph       # infra / The Graph
```

Моделі, API, pipeline-кроки, web3-деталі, deploy, активні блокери — **НЕ тут**: відповідний скіл (§2) + `docs/`. Відкрите/блокери = `docs/00_07`.

## 8. Solidity / Foundry (контракти SCC/SFC/Governance/Anchor)

**Дім контрактів:** `contracts/*.sol` + парні тести `contracts/test/{Name}.t.sol`. Конфіг — `contracts/foundry.toml` (профілі `default`/`ci`/`production`); `forge-std` через `npm ci`. Контракт-спека + ролі → `docs/05_03`; тест-методологія всіх шарів → `docs/04_06 §B`.

**Конвенції тестів (must):**
- Naming: `test_` (happy-path) · `testRevert_` (expected revert) · `testFuzz_` (property/fuzz) · `check_` (Halmos symbolic, `test/symbolic/`) · `property_` (Medusa fuzz, `test/medusa/`) · `invariant_` (Foundry stateful, `test/invariant/`).
- `makeAddr("name")` (НЕ `address(0xN)`) · `vm.prank(caller)` на КОЖЕН виклик (НЕ `startPrank` без `stopPrank`).
- `vm.expectRevert("exact error string")` — точний рядок, не голий `expectRevert()`.
- `vm.expectEmit(...) + emit Event(...)` ПЕРЕД викликом · `bound(x,min,max)` > `vm.assume`.
- `vm.warp` / `vm.roll` для timelock / ERC20Votes-checkpoint (snapshot voting) логіки.

**Інваріант-гейти (обов'язкові тести):**
- `testRevert_cannotRemoveLastAdmin` — кожен контракт з `AccessControl` (`_adminCount` guard).
- `test_pause_allowsSlash` — SCC/SFC `slash()` ОБОВ'ЯЗКОВО працює під `pause()` (B-07).
- `totalSupply() <= MAX_SUPPLY` (1B SCC) після будь-якої послідовності операцій.
- Ці 3 гейти **доведені Halmos** (`check_*` у `test/symbolic/` — symbolically, не семпл; loop-bound `--loop 3`) + **fuzz-Medusa** (`property_*` у `test/medusa/`), не лише unit-тести.

**Команди + ролі:** `forge test -vvv --gas-report` · `forge build --sizes` (ліміт EIP-170 = 24KB) · `forge coverage --report lcov` (→ CI Codecov). **CI-аудит** (`solidity_audit.yml`, CI-gated не локально): Slither + `aderyn .` **gate-на-high** (static); `halmos --function "^check_"` (symbolic) + `medusa fuzz --config medusa-{scc,sfc}.json` (fuzz) — усі **gating** (fail-on). On-chain адмін-ролі → Timelock (крім `pause`); `slash()` = `SLASHER_ROLE`, `mint()` = `MINTER_ROLE` (фізично розділені ключі, E.2).

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **silken_net**. Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/silken_net/context` | Codebase overview, check index freshness |
| `gitnexus://repo/silken_net/clusters` | All functional areas |
| `gitnexus://repo/silken_net/processes` | All execution flows |
| `gitnexus://repo/silken_net/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
