# Gaia 2.0 — Повний контекст для Claude

## Порядок читання (обов'язково)
1. Wiki SSOT: https://github.com/Alexey-Lukin/silken_net/wiki
2. `docs/00_00_...` -> `docs/08_07_...` (всі файли, не лише заголовки)
3. `README.md`

---

## 1. Що таке SilkenNet

SilkenNet / Gaia 2.0 — планетарна кіберфізична платформа для моніторингу здоров'я лісів. Система поєднує:
- **Hardware edge**: Ti-6Al-4V гіроїдний анкер (DMLS, пористість 65%, діапазон 60-70%) вживляється в дерево. EBFC (Enzymatic Bio-Fuel Cell) на межі метал-ксилема генерує ~500 мВ. BQ25570 MPPT -> EDLC суперконденсатор 0.47F/5.5V -> MCU 3.3V. Принцип "zero grid" — дерево живить власний монітор.
- **Firmware**: Soldier (STM32WLE5JC) збирає дані, запускає mruby Lorenz attractor, упаковує 21-байтний пакет, шифрує AES-256-ECB, відправляє LoRa 868 МГц.
- **Backend**: Rails 8.1 / Ruby 4.0.2 / PostgreSQL / Sidekiq — декодує, верифікує через 12-chain Web3 pipeline, мінтить SCC.
- **Tokenomics**: Proof of Growth — 10,000 growth_points = 1 SCC (Polygon ERC-20). Слешинг при деградації лісу.

**Поточний TRL**: firmware TRL 6, backend TRL 8, hardware capsule TRL 6, anchor/EBFC TRL 3.

---

## 2. Середовище розробки

```bash
ruby --version  # must show 4.0.2
bundle exec rubocop
bundle exec rspec
bundle exec brakeman
bundle exec bundler-audit check
# Firmware tests (host-based, x86):
make -C firmware/test
```

---

## 3. Апаратна архітектура

### Soldier (STM32WLE5JC)
**Файл**: `firmware/soldier/main.c` (771 рядків C)

Цикл пробудження (STOP2 -> active -> STOP2):
1. **SENSE**: ADC читає Vcap (uint16 мВ), internal temp (int8 °C). DMA 16 кГц -> 512 ADC samples для TinyML.
2. **TinyML**: CMSIS-NN акустичний inference (4 класи: silence/wind/cavitation/chainsaw). **BLOCKER: `Run_Inference()` закоментована** (main.c:413). `silken_net_audio_model.h` відсутній.
3. **mruby BioContract** (`firmware/bio_contracts/bio_contract.rb`): Lorenz attractor 250 ітерацій (Euler, **Float** — не BigDecimal!). Входи: `chaos_seed` (HRNG), `temp`, `acoustic`. Виходи: `z_val` -> `status` + `growth_points`. Пакує в 1 байт: `[status:2|growth_points:6]`.

   Firmware Lorenz константи:
   ```ruby
   BASE_SIGMA = 10.0;  BASE_RHO = 28.0;  BASE_BETA = 8.0 / 3.0  # Float!
   DT = 0.01;  ITERATIONS = 250
   SIGMA_LIMITS = (5.0..30.0);  RHO_LIMITS = (10.0..50.0)
   ```
   Формула growth_points:
   ```ruby
   # CRITICAL_Z_MIN=2.0, CRITICAL_Z_MAX=45.0, OPTIMAL_Z_TARGET=29.0
   if z_val < 2.0  then status=1, growth_points=1   # stress
   elsif z_val > 45.0 then status=2, growth_points=0  # anomaly
   else  status=0; growth_points = clamp(50 - deviation.to_i, 10, 63)  # homeostasis
   end
   payload_byte = (status << 6) | growth_points  # C entry: calculate_state → uint8_t
   ```
   **Важливо [FIX FW.7]:** Backend переведено з BigDecimal на **Float (IEEE 754 double)** — ідентично firmware mruby. Раніше `("8.0".to_d / "3.0".to_d).round(18)` давав інший результат після 250 ітерацій; зараз обидві сторони використовують `8.0/3.0` → `2.6666666666666665` і Z **бітово ідентичний** (верифіковано 50,000 random parity-тестами). Майбутній hardening через integer/fixed-point Q-format — `[FW.45]`, deferred до ZK-circuit milestone (див. `docs/03_04_mruby_Lorenz_Attractor.md`).

4. **PACK**: 16-байтний payload.
5. **ENCRYPT**: AES-256-ECB (апаратний CRYP модуль, без IV). 1 блок = 1 AES operation.
6. **TX**: `Radio.Send(21 bytes)`. Mesh TTL-based. Emergency TX при chainsaw detection (PANIC_TTL=5).

**21-байтний packet format**:
```
[DID:4][RSSI:1] | [Vcap:2][Temp:1][Acoustic:1][dT:2][StatusByte:1][TTL:1][FW:2][PAD:2]
  unencrypted   |  AES-256-ECB encrypted (16 bytes = 1 block)
```
Ruby unpack: `"N n c C n C C a4"`.

### Queen (STM32WLE5JC + SIM7070G)
**Файл**: `firmware/queen/main.c` (550 рядків C)

- LoRa RX -> AES-256-ECB decrypt -> CIFO EdgeCache (50 slots, дедуплікація за DID).
- **Queen Sentinel:** `DID == 0x00000000` → власна телеметрія Королеви → `GatewayTelemetryWorker` (не `TelemetryLog`).
- Flush trigger: >= 45 entries OR 1 година + HRNG jitter (0-60 сек).
- Flush process: CBC encrypt (HRNG IV) -> AT+CCOAPSEND -> CoAP PUT `/telemetry/batch/<QUEEN_UID>` -> SIM7070G.
- **BLOCKER: ECB restore** після CBC flush — якщо не відновити, наступні LoRa decrypt ламаються.
- **BLOCKER: `QUEEN-001` hardcoded** UID -> неможливий уніфікований флешинг.
- **BLOCKER: AT command blind delay ~25 sec** під час flush (немає парсингу відповіді модему).
- OTA downlink: CoAP -> RAM assembly (`pending_ota_bytecode[8192]`) -> reflex broadcast chunk by chunk (TTL).
  - Chunk format: `[0x99][index:2][total:2][bytecode:11]`, AES-256-CBC, pacing 60ms між чанками.
  - `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`. Magic check: `0x45544952 ("RITE")` → load OTA bytecode, else → load embedded `lorenz_bytecode[]`.

### AES режими
| Напрямок | Режим | IV |
|----------|-------|-----|
| Soldier -> Queen (LoRa) | AES-256-ECB | немає |
| Queen -> Rails (CoAP batch) | AES-256-CBC | HRNG |
| Rails -> Queen (downlink) | AES-256-CBC | з payload |

**BLOCKER**: ECB без MAC/IV -> вразливість replay attack, bit-flip, chosen plaintext. Потрібен AES-256-GCM.

---

## 4. Backend — модель даних

### Ключові entities (04_01)

**`Tree`** (Soldier):
- `did`: `"SNET-XXXXXXXX"` (апаратний UID)
- `peaq_did`: `"did:peaq:0x{40hex}"` (Web3 DID)
- `bio_status`: enum (homeostasis/stress/anomaly/deceased/removed)
- `health_streak`: скільки днів поспіль homeostasis
- Includes: `AASM`, `GeoLocatable`, `Firmwareable`, `OtaChunkable`

**`Gateway`** (Queen):
- `uid`: `"SNET-Q-[8 HEX]"`
- `state`: AASM (idle/active/updating/maintenance/faulty)
- `mark_seen!(new_ip:, voltage_mv:)` — GREATEST атомарне оновлення
- `online?` = `last_seen_at >= (sleep_interval * 1.2).seconds.ago`

**`HardwareKey`**:
- `aes_key_hex`: 64 HEX символи (AES-256), AR Encryption non-deterministic
- `cached_binary_key`: in-process LRU (SinLruRedux), versioned_cache_key = `"#{device_uid}:v:#{updated_at.to_f}"`
- Ключі не залишають Ruby-процес (немає Redis-serialize). Self-invalidation через `updated_at`.
- Dual-Key Grace Period при ротації: `previous_aes_key_hex` активний поки не підтверджена синхронізація.

**`TelemetryLog`** (partitioned, RANGE по created_at):
- `bio_status` enum, `z_value`, `growth_points`, `acoustic_events`, `oracle_status`
- `oracle_status` (string-backed enum, prefix: `oracle_status_`): `pending/dispatched/fulfilled/failed`
- `verified_by_iotex`: bool, `zk_proof_ref`: string
- Валідації видалені з hot path (KENOSIS TITAN). Перевірка в `TelemetryUnpackerService.valid_sensor_data?`.

**`Wallet`**:
- `balance`, `locked_balance`, `esg_retired_balance`, `toucan_bridged_balance`
- `lock_and_mint!(points, threshold, token_type)` — 10,000 points = 1 SCC
- `credit!(points)` враховує `carbon_sequestration_coefficient` породи дерева

**`BlockchainTransaction`** (partitioned):
- AASM: `pending -> processing -> sent -> confirmed / failed / manual_review`
- `find_with_partition_pruning(id, created_at)` — partition-aware O(log N) lookup
- `manual_review` — DOUBLE-SPEND GUARD: tx_hash є але стан невідомий, кошти заблоковані до ручної звірки.

---

## 5. Proof of Growth Pipeline

**Суворий порядок** (05_02):
```
A. Provisioning: POST /provisioning/register
   -> PeaqRegistrationWorker -> Peaq::DidRegistryService
   -> DID = "did:peaq:0x{SHA256(did:id:created_at)[0:40]}"
   -> Ed25519 підпис (Ed25519Crypto::SigningService)

B. Uplink: CoAP PUT UDP:5683
   -> UnpackTelemetryWorker (queue: uplink #1)
   -> TelemetryUnpackerService: AES-256-CBC decrypt, 21-byte decode, Lorenz server-side
   -> IotexVerificationWorker (queue: web3_critical #6)
   -> Iotex::W3bstreamVerificationService: POST /verify
   -> log.update!(verified_by_iotex: true, zk_proof_ref: ...)
   -> ChainlinkDispatchWorker (queue: web3_critical #6)

C. Oracle: POST /api/v1/oracle_callbacks (Chainlink DON, HMAC-SHA256)
   -> log.oracle_status = "fulfilled"
   -> MintCarbonCoinWorker + SolanaMicroRewardWorker

D. Minting (BlockchainMintingService):
   Guards: verified_by_iotex? && oracle_status_fulfilled? && hadron_kyc_status=="approved"
   batchMint dry-run (eth_call) -> Binary Search isolation при revert
   Dynamic Tax: 2% до DAO_TREASURY якщо insurance_pool < 100,000 SCC
```

**Dual Computation Integrity**: SilkenNet::Attractor (BigDecimal, 18-digit) розраховує Z server-side. Divergence > 30% між device Z і server Z -> fraud flag.

---

## 6. Sidekiq черги (суворий пріоритет, `:strict: true`)

```
uplink(1) > alerts(2) > critical(3) > downlink(4) > default(5)
> web3_critical(6) > web3(7) > web3_low(8) > low(9)
```

Числа — порядок дренування. Sidekiq NOT зважений, а строго послідовний. `uplink` повністю дренується перед `alerts`.

---

## 7. Frontend — Phlex + Tailwind v4

**Правила** (04_04):
- `ApplicationComponent < Phlex::HTML` — базовий клас. Без DB-запитів у `initialize`.
- `tokens(*static, **conditional)` — TailwindMerge composit method.
- Дизайн-токени ТІЛЬКИ: `bg-gaia-surface`, `text-gaia-text`, `bg-status-danger text-status-danger-text` тощо.
- Raw Tailwind (`bg-red-100`) — заборонено в shared components, дозволено в domain-specific page components.
- `config/tailwind.config.js` ВИДАЛЕНО — SSOT тільки у `application.css` (`@theme` блок).
- Типографіка: `text-micro(8px)`, `text-mini(9px)`, `text-tiny(10px)`, `text-compact(11px)` — кастомна шкала.
- CUSTOM_TEXT_SCALE реєструється в ApplicationComponent — TailwindMerge знає що це font-size, не color.

**Turbo**:
- Streams: `"telemetry_stream"`, `[@wallet, :transactions]`, `"alert_badge_{id}"`, `"ota_progress_{uid}"`
- Frames lazy: `wallet_balance_frame_{id}`, `wallet_metadata_frame_{id}`, `tree_chronicle_{id}`

**Stimulus**: `theme`, `clipboard`, `map` (Leaflet CartoDB Dark Matter), `matrix-rain` (Canvas hex rain, ~16fps, GPU-compositing).

---

## 8. API — ключові ендпоінти

82 унікальні ендпоінти, всі під `/api/v1`. Деталі: `docs/04_03_REST_API_v1_Reference.md`.

Ролі: `investor(0) < forester(1) < admin(2) < super_admin(3)`. `patrol` = синонім `forester`.

Пагінація: Pagy, `?page=N&limit=21` (default 21, крім maintenance_records: 50/6).

Ключові особливості:
- `POST /actuators/:id/execute`: `Idempotency-Key` header обов'язковий для JSON запитів.
- `GET /wallets/:id/balance` і `/metadata`: повертають Phlex Turbo Frame (HTML only, не JSON).
- `POST /oracle_callbacks`: публічний ендпоінт (без Bearer), HMAC-SHA256 захист.
- `POST /auth/m2m_token`: Ed25519-підпис DID. Replay protection через Redis nonce (SHA256 підпису, TTL 10 хв).

---

## 9. Безпека

- Паролі: Argon2id (`HasArgon2Password`).
- API tokens: Rails 8 `generates_token_for` (TTL: password_reset 15хв, email_verify 24г, api_access 30д).
- MFA: TOTP + recovery codes (10 штук).
- OAuth2: google, facebook, linkedin, twitter. Lock/unlock identity.
- `send_default_pii: false` в Sentry (Zero-Trust).
- AES keys шифруються AR Encryption non-deterministic в БД.
- Chainlink HMAC перевірка: `ActiveSupport::SecurityUtils.secure_compare` (timing-safe).

---

## 10. Деплой та інфраструктура

- **GCP** `europe-west1` (GDPR): Cloud SQL PostgreSQL 16, Memorystore Redis 7.0, GCE instances.
- **Kamal**: production + canopy. SSH deploy, Traefik reverse proxy, Let's Encrypt SSL.
- **Akash Network**: децентралізована хмара (ЄС, цензуростійкість). SDL в `deploy/akash/`. **BLOCKER: Sidekiq відсутній в Akash SDL**.
- **Docker**: `ruby:4.0.1-slim`, multi-stage, `thrust ./bin/rails server`.
- **Prometheus** (`/metrics` endpoint): 20 метрик (10 counters + 8 gauges + 2 histograms). **BLOCKER: Prometheus Server відсутній у Terraform**.
- **Sentry** 6.5.0: налаштований, але **`SENTRY_DSN` відсутній у `.kamal/secrets`**.
- **Pre-flight**: антена ПЕРЕД живленням на SX1262 (згорить без антени). AES ключ симетричний на всіх вузлах.

---

## 11. 12-Chain Web3 деталі

Усі сервіси в `app/services/`. Guard clause для мінтингу:
```ruby
raise "IoTeX" unless log.verified_by_iotex?
raise "Chainlink" unless log.oracle_status_fulfilled?   # enum method
raise "Hadron KYC" unless wallet.hadron_kyc_status == "approved"
```

`WEB3_STRICT_MODE=true` у production -> Chainlink та Hadron стаби вимикаються, raises при відсутності ENV.

batchMint (100 записів): ~30-40% газу vs 100x mint(). Binary Search Poisoned Record Isolation при dry-run revert (Divide & Conquer, MAX_DEPTH=6).

Solana: Ed25519 підпис, SPL Token Transfer, ATA резолюція через `getTokenAccountsByOwner`. Мікро-винагорода: 10,000 + growth_points*100 lamports (0.01-0.016 USDC).

---

## 12. Активні BLOCKER'и (MUST NOT treat as resolved)

| BLOCKER | Файл | Суть |
|---------|------|------|
| HW-AES-KEY | `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:81-82` | ✅ Firmware CLOSED (FW.1, 2026-05-02): `Load_AES_Key()` + per-device HKDF + Protected Flash. Залишається: Factory Flashing Pipeline (SEC.3, threat model: `03_05 §3.4г`) + RDP Level 2 (SEC.2) |
| AES-ECB | `firmware/soldier/main.c:747` | ECB без MAC -> replay/bit-flip attacks |
| TINYML-COMMENT | `firmware/soldier/main.c:413` | `Run_Inference()` закоментована; model header відсутній |
| LORENZ-INPUTS | `firmware/bio_contracts/bio_contract.rb` | ✅ Виправлено (FW.5 B+, 2026-05-02): `delta_t_s`/`vcap_mv` передаються як β-пертурбація через `BETA_DELTA_T_COEFF`/`BETA_VCAP_COEFF`; EMA-згладжені значення з firmware. 500-case parity fuzz — 0 mismatches |
| LORENZ-STATE | firmware | ✅ Виправлено: Стан (x,y,z) зберігається в RTC DR16-DR18 + magic marker `0x4C5A5354` (`"LZST"` = "Lorenz State"). Підтверджено в `firmware/soldier/main.c:239-249,746-749` |
| OPTIMAL-Z | `bio_contract.rb:99` | ✅ Виправлено (2026-05-17): `OPTIMAL_Z_TARGET = 29.0` — коментар та константа узгоджені. Обґрунтування: +2 зміщення від z_eq=27.0 для кращої розрізненності класів. Задокументовано у `docs/03_04 §BLOCKER` |
| QUEEN-UID | `firmware/queen/main.c` | ✅ Виправлено (PLAN 2.4): Flash-based UID з fallback |
| QUEEN-OTA-LOOP | `firmware/queen/main.c` | ✅ Виправлено (PLAN 2.5): `ota_is_active` скидається після повного циклу |
| QUEEN-AT-BLIND | `firmware/queen/main.c:542` | ~25 сек blind wait під час CoAP flush |
| HRNG-IV-REUSE | `firmware/queen/main.c:588` | ⚠️ Покращено (PLAN 2.7): djb2 fallback замість IV=0, але djb2 НЕ криптографічний PRNG — CBC IV залишається передбачуваним при HRNG failure |
| BQ25570-R | `docs/02_03` | VBAT_OV резистори не верифіковані |
| PROMETHEUS | `terraform/` | Prometheus Server відсутній |
| SENTRY-DSN | `.kamal/secrets` | ✅ Додано: `SENTRY_DSN=$SENTRY_DSN` (потребує ENV at deploy time) |
| AKASH-SIDEKIQ | `deploy/akash/deploy.yaml` | ✅ Виправлено (PLAN 5.8): `job:` service з Sidekiq entrypoint додано |

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **silken_net** (9321 symbols, 17542 relationships, 300 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> If any GitNexus tool warns the index is stale, run `npx gitnexus analyze` in terminal first.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `gitnexus_impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `gitnexus_detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `gitnexus_query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `gitnexus_context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `gitnexus_impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `gitnexus_rename` which understands the call graph.
- NEVER commit changes without running `gitnexus_detect_changes()` to check affected scope.

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
