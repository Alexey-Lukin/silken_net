# SilkenNet — Повний контекст для Claude

## Порядок читання (обов'язково)
1. Wiki SSOT: https://github.com/Alexey-Lukin/silken_net/wiki
2. `docs/00_00_...` -> `docs/08_03_...` (всі файли, не лише заголовки; Фундамент 00 [read-first], Tier I 01–06, Tier II 07–08)
3. `README.md`

> **Робота над SSOT-документами** (`docs/NN_NN_*.md`) — редагування канону, полювання на SSOT-drift, додавання doc-лінтерів, публікація на Wiki — веди через скіл **`ssot-maintenance`** (операційний playbook: `docs:check_refs` / `docs:toc` / `tracker:check` / `wiki:sync`). Сам стандарт живе в `00_02` + `00_06`, стан — у пам'яті; скіл їх не дублює. Він спроєктований авто-спрацьовувати за описом — ця згадка лише підстраховка.

---

## 1. Що таке SilkenNet

SilkenNet — планетарна кіберфізична платформа для моніторингу здоров'я лісів. Система поєднує:
- **Hardware edge**: Ti-6Al-4V гіроїдний анкер (DMLS, пористість 65%, діапазон 60-70%) вживляється в дерево. EBFC (Enzymatic Bio-Fuel Cell) на межі метал-ксилема генерує ~500 мВ. BQ25570 MPPT -> EDLC суперконденсатор 0.47F/5.5V -> MCU 3.3V. Принцип "zero grid" — дерево живить власний монітор.
- **Firmware**: Soldier (STM32WLE5JC) збирає дані, запускає mruby Lorenz attractor, упаковує 21-байтний пакет (FW.2 target: 28B wire-rev2 з CCM MIC), шифрує **AES-128-ECB** (transitional після ARCH.42 Variant B; target — AES-128-CCM), відправляє LoRa 868 МГц.
- **Backend**: Rails 8.1 / Ruby 4.0.5 / PostgreSQL / Sidekiq — декодує, верифікує через 12-chain Web3 pipeline, мінтить SCC.
- **Tokenomics**: Proof of Growth — 10,000 growth_points = 1 SCC (Polygon ERC-20). Слешинг при деградації лісу.

**Поточний TRL**: firmware TRL 6, backend TRL 8, hardware capsule TRL 6, anchor/EBFC **TRL 3** (Zero-Lab in-silico L1-L4 ✅ 2026-05-25 = аналітичний PoC; фізичний TRL 4 = in-vitro Ti-coin, Stage 2 pending — in-silico ≠ TRL 4 за NASA/ISO 16290). **System TRL = 3** (gated by anchor/EBFC). Поточні числа pipeline — `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md`.

---

## 2. Середовище розробки

```bash
ruby --version  # must show 4.0.5
bundle exec rubocop
bundle exec rspec
bundle exec brakeman
bundle exec bundler-audit check
# Firmware tests (host-based, x86):
make -C firmware/test
```

---

## 2а. Стиль коду: драбинка «лінивого сеньйора» (YAGNI-first)

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

---

## 3. Апаратна архітектура

### Soldier (STM32WLE5JC)
**Файл**: `firmware/soldier/main.c`

Цикл пробудження (STOP2 -> active -> STOP2):
1. **SENSE**: ADC читає Vcap (uint16 мВ), internal temp (int8 °C). DMA 16 кГц -> 512 ADC samples -> `Compute_LogMel` -> 40 log-mel ознак (Path B, FW.25).
2. **TinyML**: log-mel фронтенд `Compute_LogMel` ✅ (FW.25 — `firmware/common/logmel.c` + `tools/ml` `silken_ml`, golden-vector parity) -> INT8 forward-pass inference (5 класів: silence/wind/cavitation/chainsaw/fauna). ✅ **FW.4 (2026-06-12):** self-owned baseline (ESC-50; wind/chainsaw реальні, fauna interim-проксі, **silence+cavitation синтетичні placeholder'и — польова валідність pending**, `03_03 §4.2`) → `silken_net_audio_model.h` (gemmlowp pure-C, **972 B Flash-ваги** + код/libm=ARM-size deferred, 0 .bss, 76 B стек), call-site розкоментований; stub — fallback через `__has_include`. Runtime = fixed-topology forward pass, **НЕ** TFLM-інтерпретатор (TFLM делегує в CMSIS-NN; примирення — `03_03 §4.1`).
3. **mruby BioContract** (`firmware/bio_contracts/bio_contract.rb`): Lorenz attractor 250 ітерацій (Euler, **Float** — не BigDecimal!). Входи: `(x_prev,y_prev,z_prev)` (RTC continuation, інакше SEC.11 K_seed cold-start), `temp`, `acoustic`, `delta_t_s`, `vcap_mv`. Виходи: `z_val` -> `status` + `growth_points`. Пакує у StatusByte (байт 10): `[PanicFlag:1|status:2|growth_points:5]` (FW.29-PACK; до FW.29 — `status:2|growth_points:6`).

   Firmware Lorenz константи:
   ```ruby
   BASE_SIGMA = 10.0;  BASE_RHO = 28.0;  BASE_BETA = 8.0 / 3.0  # Float!
   DT = 0.01;  ITERATIONS = 250
   SIGMA_LIMITS = (5.0..30.0);  RHO_LIMITS = (10.0..50.0)
   ```
   Формула growth_points [E.63 — Лоренц гейтить СТАТУС, метаболізм задає БАЛИ]:
   ```ruby
   # CRITICAL_Z_MIN=2.0 (stress, absolute); anomaly_ceiling = ρ + (CRITICAL_Z_MAX−BASE_RHO) [E.64 ρ-relative, =45 при ρ=28]
   if z_val < 2.0  then status=1, growth_points=1   # stress (колапс конвекції)
   elsif z_val > anomaly_ceiling then status=2, growth_points=0  # anomaly (E.64: ρ-relative — ambient-temp не тригерить хибну)
   else  status=0  # homeostasis: growth_points = метаболічна жвавість m(delta_t), НЕ |29-z|
     growth_points = metabolic_health_points(delta_t_s)  # монотонно: швидший перезаряд → більше
   end
   # StatusByte байт 10: [PanicFlag:1(bit7) | status:2 | growth_points:5]; status 0-3 (3=tamper); PanicFlag — C-side
   payload_byte = (status << 5) | growth_points  # C entry: calculate_state → uint8_t
   # β = BASE_BETA фіксований (E.63: метаболізм НЕ через β). Формула m(delta_t) + калібрування — SSOT 03_04 §4.3 (One-Home).
   ```
   **Важливо [FIX FW.7]:** Backend переведено з BigDecimal на **Float (IEEE 754 double)** — ідентично firmware mruby. Раніше `("8.0".to_d / "3.0".to_d).round(18)` давав інший результат після 250 ітерацій; зараз обидві сторони використовують `8.0/3.0` → `2.6666666666666665`. Z: **категорично** ідентичний (status/growth_points/payload_byte — бітово), raw Z — у межах numeric-tolerance (реальний mruby 4.0.0 VM ↔ CRuby ~1e-14, хаотична ULP-амплітудизація; FW.31 ε=0.001 band; перша VM-перевірка + деталі — `docs/03_04`). Майбутній hardening через integer/fixed-point Q-format — `[FW.45]`, deferred до ZK-circuit milestone (див. `docs/03_04_mruby_Lorenz_Attractor.md`).

4. **PACK**: 16-байтний payload (FW.2 target: 12-byte sensor payload у 28B AES-128-CCM frame, wire-rev2 — 03_05 §2.1 + wire-budget ledger).
5. **ENCRYPT**: **AES-128-ECB** transitional (апаратний CRYP модуль, без IV) — ARCH.42 Variant B з 2026-05-23. 1 блок = 1 AES operation. Target FW.2: AES-128-CCM 28B (wire-rev2): 8-byte MIC + 24-bit FC + gossip-байт у AAD + device_z/diag/vpd у payload.
6. **TX**: `Radio.Send(21 bytes)`. Mesh TTL-based. Emergency TX при chainsaw detection (PANIC_TTL=5).

**21-байтний packet format** (transitional; FW.2 target — 28-byte CCM wire-rev2):
```
[DID:4][RSSI:1] | [Vcap:2][Temp:1][Acoustic:1][dT:2][StatusByte:1][TTL:1][FW:2][PAD:2]
  unencrypted   |  AES-128-ECB encrypted (16 bytes = 1 block)
```
Ruby unpack: `"N n c C n C C a4"`.

### Queen (STM32WLE5JC + SIM7070G)
**Файл**: `firmware/queen/main.c`

- LoRa RX -> **AES-128-ECB** decrypt (per-Soldier 128-bit key) -> CIFO EdgeCache (50 slots, дедуплікація за DID).
- **Queen Sentinel:** `DID == 0x00000000` → власна телеметрія Королеви → `GatewayTelemetryWorker` (не `TelemetryLog`).
- Flush trigger: >= 45 entries OR 1 година + HRNG jitter (0-60 сек).
- Flush process: **AES-256-CBC** encrypt (CoAP key, окремий MX_CRYP re-init на `CRYP_KEYSIZE_256B`, HRNG IV) -> **[L1 QATT]** Ed25519-підпис батча, якщо EDSK-сім'я прошита (Monocypher; wire-дім `03_05 §2.2`, розкладка `firmware/common/queen_attest.h`; бекенд верифікує ДО decrypt, legacy без підпису = L0) -> CoAP PDU будує **хост** (FW.56: SIMCom = UDP-труба) -> `AT+CCOAPSEND=<cid>,<len>,"<hex PDU>"` -> CoAP PUT `/telemetry/batch/<QUEEN_UID>` -> SIM7070G; доставка = URC `+CCOAPNMI` класу 2.xx.
- **BLOCKER: ECB restore** після CBC flush — якщо не відновити (`CRYP_KEYSIZE_128B` + LoRa key), наступні LoRa decrypt ламаються. (FW.3: restore тепер одразу після encrypt, ДО модемної розмови.)
- **BLOCKER: `QUEEN-001` hardcoded** UID -> неможливий уніфікований флешинг.
- ✅ AT blind delay закрито (FW.3/FW.56, 2026-06-07): `at_engine.h`/`coap_pdu.h`/`sim7070_coap.h` — байтовий токенайзер з early-exit, hex чанками; residual: UART DMA RX + verbatim-звірка SIM7070-ноти (bench). Канон: `03_02 §4`.
- OTA downlink: CoAP -> RAM assembly (`pending_ota_bytecode[8192]`) -> reflex broadcast chunk by chunk (TTL).
  - Chunk format: `[0x99][index:2][total:2][bytecode:11]`, **AES-128-ECB** (LoRa key, як інші Soldier-frames), pacing 60ms між чанками. (Queen→Rails CoAP transport — AES-256-CBC; Queen→Soldier OTA reflex — AES-128.)
  - `MRUBY_CONTRACT_FLASH_ADDR = 0x0803F000`. Magic check: `0x45544952 ("RITE")` → load OTA bytecode, else → load embedded `lorenz_bytecode[]`.

### AES режими (post-ARCH.42, 2026-05-23)
| Напрямок | Режим | Key size | IV |
|----------|-------|----------|-----|
| Soldier -> Queen (LoRa) | AES-128-ECB [transitional] → AES-128-CCM [FW.2 target] | 128 bit | немає (ECB) / CCM B0 nonce (FW.2) |
| Queen -> Soldier (OTA reflex) | AES-128-ECB | 128 bit | немає |
| Queen -> Rails (CoAP batch) | AES-256-CBC | 256 bit | HRNG |
| Rails -> Queen (downlink) | AES-256-CBC | 256 bit | з payload |

**BLOCKER (LoRa channel)**: ECB без MAC/IV -> вразливість replay attack, bit-flip, chosen plaintext. Закривається переходом на **AES-128-CCM** (FW.2; апаратно `CRYP_AES_CCM` у HAL — потребує STM32 bench для верифікації). PQC roadmap — `docs/03_05 §10`.

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

**`HardwareKey`** (conditional by device_type після ARCH.42):
- `aes_key_hex`: **32 HEX символи** для Tree (AES-128 LoRa) / **64 HEX символи** для Gateway (AES-256 CoAP). AR Encryption non-deterministic. Domain separation у HKDF: info `"silken-aes-128-lora-key"` (Tree) vs `"silken-aes-256-device-key"` (Gateway).
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
   -> TelemetryUnpackerService: AES-256-CBC decrypt CoAP batch (Gateway key) → inner 21-byte records приходять ПЛЕЙНТЕКСТОМ (Queen вже зняв LoRa AES-128-ECB), 21-byte decode, Lorenz server-side. (Per-Soldier LoRa-ключ реальний лише у FW.2 CCM-шляху `process_ccm_chunk`, де DID/FC — cleartext AAD; в ECB-транзиті кластер де-факто на спільному ключі — chicken-and-egg, 03_05 §ECB)
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

**Dual Computation Integrity**: SilkenNet::Attractor (**Float, IEEE 754 double** — категорично ідентично firmware mruby (raw Z у межах tolerance ~1e-14) після [FIX FW.7], НЕ BigDecimal; див. §3) розраховує Z server-side. Divergence > 30% між device Z і server Z -> fraud flag.

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

**i18n** (04_04 §12):
- 4 мови: `en` (default), `uk`, `lv`, `lt`. Конфіг:
  ```ruby
  config.i18n.available_locales = %i[uk en lv lt]
  config.i18n.default_locale    = :en
  config.i18n.fallbacks         = { uk: %i[uk en], en: %i[en], lv: %i[lv en], lt: %i[lt en] }
  ```
- Resolution priority: `params[:locale]` → `cookies[:locale]` → `Accept-Language` header → `default_locale (:en)`.
- `Accept-Language` auto-detects `uk`/`lv`/`lt` для відповідних браузерів; решта — English.
- Locale files: `config/locales/<domain>/{uk,en,lv,lt}.yml` — 34 домени.
- `t(".key")` у Phlex autoscope до `<namespace>.<component>.<key>`. CI-гейти: `i18n-tasks missing`, `check-consistent-interpolations`, `check-normalized`.
- Тести за замовчуванням — English (`default_locale = :en`). Перевірка Ukrainian/LV/LT — явно через `I18n.with_locale(:uk) { ... }`.

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

- **GCP** `europe-west1` (GDPR): Cloud SQL PostgreSQL 17, Memorystore Redis 7.0, GCE instances.
- **Kamal**: production + canopy. SSH deploy, Traefik reverse proxy, Let's Encrypt SSL.
- **Akash Network**: децентралізована хмара (ЄС, цензуростійкість). SDL в `deploy/akash/`: `web` + `job` (Sidekiq) + `alloy` сервіси.
- **Docker**: `ruby:4.0.5-slim`, multi-stage, `thrust ./bin/rails server`.
- **Observability**: `/metrics` endpoint (custom business-метрики — реєстр + кількість SSOT: `06_03 §2.8`) скрейпиться **Grafana Alloy** sidecar (Akash SDL) → `remote_write` → **Grafana Cloud** (Prometheus storage + dashboards + alerting, SaaS). Self-hosted Prometheus НЕ потрібен (Rails на Akash, не GCP).
- **Sentry** 6.5.0: налаштований; `SENTRY_DSN` у `.kamal/secrets` (значення задається при деплої).
- **Pre-flight**: антена ПЕРЕД живленням на SX1262 (згорить без антени). Per-device унікальні AES ключі через HKDF (LoRa AES-128 для Tree+Queen LoRa-сесії, CoAP AES-256 для Queen↔Rails).
- **Bench-день скриптовано**: `firmware/scripts/bench/RUNBOOK.md` — вичерпний клас C (те, що може відповісти лише кремній) + скрипти `--plan`/`--execute`; метод A/B/C — `docs/00_03 §3.5`; QEMU-M4 parity lane — `docs/03_01 §12.7`.

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
| HW-AES-KEY | `firmware/soldier/main.c:66-67`, `firmware/queen/main.c:81-82` | ✅ Firmware CLOSED (FW.1, 2026-05-02): `Load_AES_Key()` + per-device HKDF + Protected Flash. SEC.3 Factory Flashing Pipeline tool — ✅ Rake CLI dry-run (2026-05-24, `app/services/factory_flashing/*`, threat model: `03_05 §3.4г`). 👤 Залишається: real `STM32_Programmer_CLI` execution на bench + RDP Level 2 (SEC.2) |
| ARCH.42 LoRa AES-size | `firmware/soldier/main.c` MX_CRYP_Init, `firmware/queen/main.c` MX_CRYP_Init | ✅ DECIDED 2026-05-23 (Variant B = AES-128 LoRa + ATECC608B SE). LoRa channel: `CRYP_KEYSIZE_128B`, `aes_key[4]`; CoAP канал залишається AES-256. Деталі — `docs/03_05 §3.7` |
| AES-ECB | `firmware/soldier/main.c` (MX_CRYP_Init) | 🟡 Transitional AES-128-ECB після ARCH.42; повне закриття через FW.2 (AES-128-CCM, 28B wire-rev2 packet, 8B MIC, Frame Counter). Hardware bench needed для `CRYP_AES_CCM` HAL верифікації |
| TINYML-COMMENT | `firmware/soldier/main.c` (Phase 1.5) | ✅ ЗАКРИТО (FW.4, 2026-06-12): self-owned ESC-50 baseline → `silken_net_audio_model.h` (INT8 forward-pass), call-site розкоментований, host-тест `test_audio_model`. Residual: ARM `arm-none-eabi-size` (CI hal_check) + bench |
| LORENZ-INPUTS | `firmware/bio_contracts/bio_contract.rb` | 🔄 [E.63, 2026-06-08] FW.5 β-пертурбація **РЕВЕРСОВАНА** — delta_t/vcap→β виявилась економічно нульовою (delta_t) / інвертованою (vcap) на paired-ensemble. Тепер β=`BASE_BETA` фікс; `delta_t`→`growth_points` НАПРЯМУ (метаболічна `m(delta_t)`, `03_04 §4.3`); vcap reserved. DCI parity 200-case fuzz 0-mismatch |
| LORENZ-STATE | firmware | ✅ Виправлено: Стан (x,y,z) зберігається в RTC DR16-DR18 + magic marker `0x4C5A5354` (`"LZST"` = "Lorenz State"). Підтверджено в `firmware/soldier/main.c:239-249,746-749` |
| OPTIMAL-Z | `bio_contract.rb:99` | ✅ Виправлено (2026-05-17): `OPTIMAL_Z_TARGET = 29.0` — коментар та константа узгоджені. Обґрунтування: +2 зміщення від z_eq=27.0 для кращої розрізненності класів. Задокументовано у `docs/03_04 §BLOCKER` |
| QUEEN-UID | `firmware/queen/main.c` | ✅ Виправлено (PLAN 2.4): Flash-based UID з fallback |
| QUEEN-OTA-LOOP | `firmware/queen/main.c` | ✅ Виправлено (PLAN 2.5): `ota_is_active` скидається після повного циклу |
| QUEEN-AT-BLIND | `firmware/queen/{at_engine,coap_pdu,sim7070_coap}.h` | ✅ Закрито архітектурно (FW.3/FW.56, 2026-06-07): early-exit токенайзер + host-built CoAP PDU + доставка по `+CCOAPNMI` 2.xx; host-тести `test_at_engine.c`. 👤 Residual: UART DMA RX + verbatim SIM7070-нота V1.03 на bench |
| HRNG-IV-REUSE | `firmware/queen/coap_iv.h` | ✅ Harden (2026-05-29): fallback IV винесено у pure `coap_fallback_iv_word` (uid_hash×device + queen_unix_ts×reboot + coap_flush_seq×flush) + 4 host-тести → **reuse закрито** (унікальність across device/reboot/flush). 🟡 Residual: IV передбачуваний на fallback-шляху — **low-severity** (CoAP-батч без chosen-plaintext вектора; uniqueness = операційна вимога тут, `03_05 §HRNG Fallback`); повна unpredictability = key-derived `E_key(ctr)`, bench-gated |
| BQ25570-R | `docs/02_03` | VBAT_OV резистори не верифіковані |
| PROMETHEUS | `deploy/akash/config.alloy` | ✅ Вирішено (OBS.1): Grafana Alloy → Grafana Cloud SaaS (remote_write); self-hosted не потрібен. Залишок 👤: import dashboards (S2.2) + verify post-deploy — `06_03` |
| SENTRY-DSN | `.kamal/secrets` | ✅ Додано: `SENTRY_DSN=$SENTRY_DSN` (потребує ENV at deploy time) |
| AKASH-SIDEKIQ | `deploy/akash/deploy.yaml` | ✅ Виправлено (PLAN 5.8): `job:` service з Sidekiq entrypoint додано |

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **silken_net**. Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

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
