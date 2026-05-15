# Copilot Instructions — SilkenNet (Gaia 2.0)

## SSOT — читати перед будь-якими архітектурними рішеннями
1. GitHub Wiki: https://github.com/Alexey-Lukin/silken_net/wiki
2. `docs/00_00_SSOT_Index.md` -> `docs/08_07_SEU_Economics_and_Legal_Integration.md` (повна послідовність пронумерованих docs)
3. `README.md`

При конфліктах між джерелами: пріоритет мають нові пронумеровані docs (`00_00` -> `08_07`), потім Wiki.

---

## 1. Знімок проєкту

**SilkenNet / Gaia 2.0** — планетарна Bio-IoT D-MRV (Digital Measurement, Reporting, Verification) платформа для моніторингу лісів.

### Апаратний стек (Edge)
- **Soldier вузол:** STM32WLE5JC + SX1262 LoRa. Ti-6Al-4V гіроїдний анкер (3D DMLS, пористість 65%, діапазон 60-70%) вживляється в дерево. EBFC (Enzymatic Bio-Fuel Cell) генерує ~500 мВ з ксилемного соку. BQ25570 MPPT -> EDLC суперконденсатор 0.47F/5.5V -> 3.3V для MCU.
- **Queen шлюз:** STM32WLE5JC + SIM7070G (LTE-M/NB-IoT або Starlink DTC через Київстар). CIFO EdgeCache 50 слотів. Flush щогодини через CoAP PUT на порт 5683. CoAP batch шифрується AES-256-CBC (HRNG IV).
- **LoRa протокол:** 868 МГц, TTL-based mesh (DEFAULT_TTL=3, PANIC_TTL=5). Anti-pingpong у RTC Backup Registers (8 слотів).
- **Packet format (21 байт):** `[DID:4][RSSI:1][AES-256-ECB payload:16]`. Payload: `[Vcap:2][Temp:1][Acoustic:1][dT:2][StatusByte:1][TTL:1][FW:2][PAD:2]`. `StatusByte = [bio_status:2 | growth_points:6]`.

### Backend стек
- **Ruby 4.0.2** (path: `/opt/hostedtoolcache/Ruby/4.0.2/x64/bin`)
- **Rails 8.1** — thin controllers, бізнес-логіка тільки в services/workers
- **PostgreSQL multi-DB** — `db/structure.sql` (не `schema.rb`), партиціювання RANGE по `created_at` для `telemetry_logs`, `gateway_telemetry_logs`, `blockchain_transactions`
- **Sidekiq** strict-priority, 9 черг (суворий порядок дренування):

| Черга | Пріоритет | Призначення |
|-------|-----------|-------------|
| `uplink` | 1 (найвищий) | CoAP телеметрія -> `UnpackTelemetryWorker` |
| `alerts` | 2 | EWS тривоги, `DclimateVerificationWorker` |
| `critical` | 3 | Slashing, страхові виплати, `EcosystemHealingWorker` |
| `downlink` | 4 | OTA прошивки, команди актуаторів |
| `default` | 5 | Агрегація, health checks, токеноміка |
| `web3_critical` | 6 | Мінтинг SCC, IoTeX ZK, Chainlink Oracle |
| `web3` | 7 | peaq DID, Celo, Solana, Puro.earth |
| `web3_low` | 8 | Ethereum L1 anchoring, KlimaDAO, Hadron |
| `low` | 9 (найнижчий) | Audit, Filecoin, Streamr broadcast |

- **CoAP daemon** — UDP порт 5683 (`lib/daemons/`), тригерить `UnpackTelemetryWorker`
- **Phlex + Turbo** — UI компоненти (не ERB/partials). Читати `docs/04_04_Phlex_UI_and_Tailwind.md` перед будь-яким фронтенд-завданням.
- **ActionCable (Solid Cable)** — WebSocket для live telemetry, wallet balance, OTA progress.

### Web3 стек (12 мереж)

| # | Мережа | Роль | Черга |
|---|--------|------|-------|
| 1 | Streamr | P2P real-time broadcast | `low` |
| 2 | Filecoin/IPFS | Immutable archive (Pinata) | `low` |
| 3 | peaq network | Machine DID реєстрація | `web3` |
| 4 | IoTeX W3bstream | ZK-proof верифікація | `web3_critical` |
| 5 | The Graph | Decentralized indexing (read-only) | — |
| 6 | Polygon | Primary EVM — SCC/SFC мінтинг, slashing | `web3_critical` |
| 7 | Polygon Hadron | KYC/Compliance (ERC-3643) | `web3_low` |
| 8 | Solana | USDC мікро-винагороди (Ed25519) | `web3` |
| 9 | Celo | ReFi community rewards (cUSD) | `web3` |
| 10 | KlimaDAO | ESG carbon retirement | `web3_low` |
| 11 | Chainlink DON | Oracle dispatch -> мінтинг trigger | `web3_critical` |
| 12 | Ethereum L1 | Weekly state root anchoring (SHA-256) | `web3_low` |

---

## 2. Незмінні правила розробки

### Ruby / Rails
- Ruby **4.0.2** — єдина версія. Перевірте: `ruby --version`.
- `db/structure.sql` — ніколи `schema.rb`.
- Контролери тонкі: лише параметри, авторизація, рендеринг. Вся логіка — у `app/services/` або `app/workers/`.
- RBAC через Pundit. Ролі: `investor(0) < forester(1) < admin(2) < super_admin(3)`.
- `User.oracle_executioner` — системний бот (super_admin, без org). Тільки для автоматичних операцій.

### Бізнес-критичні моделі
- **`TelemetryLog`** — партиціонована таблиця. Завжди передавати `created_at_iso` у воркери для partition pruning (`find_with_partition_pruning`).
- **`HardwareKey`** — кеш через `versioned_cache_key = "#{device_uid}:v:#{updated_at.to_f}"`. Ключі не залишають Ruby-процес (немає Redis-serialize). `binary_key` для AES-256-CBC розшифрування batch.
- **`Wallet#lock_and_mint!`** — 10,000 growth_points = 1 SCC. Атомарна операція з pessimistic lock.
- **`BlockchainTransaction`** — AASM: `pending -> processing -> sent -> confirmed/failed/manual_review`.
- **`oracle_status`** enum (prefix: `oracle_status_`): `pending / dispatched / fulfilled / failed`. Методи: `oracle_status_fulfilled?` тощо.

### Proof of Growth Pipeline (суворий порядок)
```
Soldier -> LoRa -> Queen -> CoAP UDP:5683 -> UnpackTelemetryWorker -> TelemetryUnpackerService
 -> IotexVerificationWorker (web3_critical)
 -> ChainlinkDispatchWorker (web3_critical)
 -> POST /api/v1/oracle_callbacks (Chainlink callback, HMAC-SHA256)
 -> MintCarbonCoinWorker + SolanaMicroRewardWorker
```
Guard clauses для мінтингу (oracle-driven): `verified_by_iotex? && oracle_status_fulfilled? && hadron_kyc_status == "approved"`.

Dual Computation Integrity: server Z vs device Z (SilkenNet::Attractor). Divergence > 30% -> fraud flag.

### Безпека та AES
- LoRa Soldier->Queen: **AES-256-ECB** (1 блок = 16 байт, без IV).
- CoAP batch uplink Queen->Rails: **AES-256-CBC** (HRNG IV).
- CoAP downlink Rails->Queen: **AES-256-CBC**.
- **BLOCKER (відкрито):** Hardcoded AES key у Flash всіх вузлів. Не вважати "виправленим" без коміту в firmware!
- Provisioning: HKDF-SHA256 (`PROVISIONING_MASTER_KEY`). AES key НІКОЛИ не передається по мережі в production.
- `WEB3_STRICT_MODE=true` -> всі Web3 стаби вимикаються (Chainlink, Hadron).
- `oracle_callbacks` endpoint: HMAC-SHA256 `X-Chainlink-Signature` header.

### Frontend (Phlex + Tailwind v4)
- Всі UI компоненти успадковують від `ApplicationComponent < Phlex::HTML`.
- Дизайн-токени ЗАВЖДИ: `bg-gaia-surface`, `text-gaia-text`, `border-gaia-border`, `bg-status-danger text-status-danger-text` etc.
- НІКОЛИ в shared компонентах: `bg-white`, `text-gray-900`, `bg-red-100`, `text-emerald-400`.
- `tokens(*static, **conditional)` — метод TailwindMerge для складання класів.
- `config/tailwind.config.js` видалено — SSOT тільки в `app/assets/tailwind/application.css` (`@theme` блок).
- Turbo Frames для lazy-load. Turbo Streams для live updates. Stimulus: `theme`, `clipboard`, `map`, `matrix-rain`.
- Accessibility: `focus-visible:ring-2 focus-visible:ring-gaia-primary` на всіх інтерактивних елементах.

### Деплой
- **Kamal** (production/canopy) + **Terraform/GCP** (infrastructure, `europe-west1`).
- CoAP UDP порт 5683 пробрасується у Kamal та Akash SDL.
- Docker: `ruby:4.0.1-slim`, multi-stage build, `USER rails:1000`, CMD: `thrust ./bin/rails server`.
- Canopy: staging, auto-deploy після push в `main`. Production: після GitHub Release (`v*.*.*`).

---

## 3. API `/api/v1` — 82 унікальні ендпоінти

Повна таблиця: `docs/04_03_REST_API_v1_Reference.md`. Ключові:
- `POST /login` -> Bearer token (rate limit: 5 req/min)
- `POST /auth/m2m_token` -> Ed25519-підпис DID для Gateway (без логіна/пароля)
- `POST /provisioning/register` -> HKDF деривація ключа, повертає DID (`"SNET-XXXXXXXX"`)
- `POST /oracle_callbacks` -> Chainlink callback (публічний, HMAC-SHA256)
- `GET /system_health` -> стан CoAP/Sidekiq/DB (admin only)
- `POST /firmwares/:id/deploy` -> OTA розгортання (admin only)
- `POST /actuators/:id/execute` -> команда актуатору (forester+, `Idempotency-Key` обов'язковий для JSON)

---

## 4. Ключові сервіси та де шукати логіку

| Домен | Головний сервіс | Файл |
|-------|----------------|------|
| Uplink | `TelemetryUnpackerService` | `app/services/telemetry_unpacker_service.rb` |
| Minting | `BlockchainMintingService` | `app/services/blockchain_minting_service.rb` |
| Slashing | `BlockchainBurningService` | `app/services/blockchain_burning_service.rb` |
| ZK-proof | `Iotex::W3bstreamVerificationService` | `app/services/iotex/` |
| Oracle | `Chainlink::OracleDispatchService` | `app/services/chainlink/` |
| Key mgmt | `HardwareKeyService` | `app/services/hardware_key_service.rb` |
| OTA | `OtaPackagerService` | `app/services/ota_packager_service.rb` |
| Lorenz | `SilkenNet::Attractor` | `app/services/silken_net/attractor.rb` |
| Emergency | `EmergencyResponseService` | `app/services/emergency_response_service.rb` |
| Satellite | `Dclimate::VerificationService` | `app/services/dclimate/` |

---

## 5. Активні BLOCKER'и (не закривати без підтвердження в коді + docs)

| ID | Локація | Суть |
|----|---------|------|
| HW-AES-KEY | `firmware/*/main.c:65-66` | Hardcoded AES-256 key — єдиний ключ на всю мережу |
| AES-ECB | `firmware/soldier/main.c:747` | ECB без MAC -> replay/bit-flip attack |
| TINYML | `firmware/soldier/main.c:355` | `Run_Inference()` закоментована; `.h` відсутній |
| LORENZ-INPUTS | `firmware/bio_contracts/bio_contract.rb` | `delta_t`/`vcap` не передаються в `calculate_state` |
| LORENZ-STATE | firmware | Стан (x,y,z) не зберігається між циклами STOP2 |
| QUEEN-UID | `firmware/queen/main.c` | `QUEEN-001` hardcoded |
| OTA-LOOP | `firmware/queen/main.c` | `ota_is_active` ніколи не скидається |
| BQ25570-R | `docs/02_03` | Резистори VBAT_OV не верифіковані (Li-Po дефолт 4.2V замість 5.5V для supercap) |
| PROMETHEUS | `terraform/` | Prometheus Server відсутній у інфраструктурі |
| SENTRY-DSN | `.kamal/secrets` | `SENTRY_DSN` відсутній — Sentry інертний у production |
| QUEEN-BLIND | `firmware/queen/main.c:542` | AT command blocking ~25 сек під час CoAP flush |

---

## 6. Фізична модель (контекст для розуміння)

- 1 SCC = 10,000 growth_points (ERC-20, Polygon, MAX_SUPPLY = 1B SCC)
- `bio_status`: 0=homeostasis, 1=stress, 2=anomaly, 3=tamper_detected
- Lorenz Z: OPTIMAL_Z_TARGET=29.0, CRITICAL_Z_MIN=2.0, CRITICAL_Z_MAX=45.0
- EDLC `delta_t` = час заряду іоністора = швидкість метаболізму EBFC = індикатор здоров'я дерева
- TRL поточний: firmware TRL 6, backend TRL 8, hardware TRL 4-5

---

## 7. Команди валідації

```bash
export PATH="/opt/hostedtoolcache/Ruby/4.0.2/x64/bin:$PATH"
bundle exec rubocop
bundle exec rspec
bundle exec brakeman
bundle exec bundler-audit check
# Firmware (x86, без ARM toolchain):
make -C firmware/test          # всі 137 тестів
make -C firmware/test soldier  # тільки Soldier
make -C firmware/test queen    # тільки Queen (59 тестів)
# Solidity (Foundry):
cd contracts && npm ci
forge build --sizes            # компіляція + розмір контрактів
forge test -vvv --gas-report   # тести з газовим звітом
forge coverage --report summary # покриття (аналог SimpleCov)
forge coverage --report lcov   # lcov.info для CI/Codecov
```

---

## 8. Solidity / Foundry Best Practices

### Конфігурація
- **`contracts/foundry.toml`** — SSOT конфігурація Foundry. Профілі: `default`, `ci`, `production`.
- **`contracts/test/*.t.sol`** — тести для кожного контракту. Naming: `{ContractName}.t.sol`.
- **`forge-std`** — Foundry test library. Встановлюється через `npm ci` (devDependency).
- **Coverage**: `forge coverage --report lcov` → `lcov.info`. CI завантажує як artifact.

### Правила тестування
1. **Naming**: `test_` (happy path), `testRevert_` (expected revert), `testFuzz_` (fuzz/property-based).
2. **Addresses**: `makeAddr("descriptive-name")` — labeled, deterministic, readable в trace output.
3. **Caller isolation**: `vm.prank(caller)` для кожного виклику. НЕ `vm.startPrank` без `vm.stopPrank`.
4. **Error matching**: `vm.expectRevert("SCC: zero recipient")` — exact error string, не `vm.expectRevert()`.
5. **Event verification**: `vm.expectEmit(true, true, false, true)` + `emit Event(...)` перед викликом.
6. **Fuzz**: `bound(value, min, max)` замість `vm.assume(value > 0)` — менше відхилень, кращий coverage.
7. **Time**: `vm.warp(block.timestamp + N)` для time-dependent логіки (timelock, anchor intervals).
8. **Blocks**: `vm.roll(block.number + N)` для snapshot-based voting power (ERC20Votes checkpoints).
9. **Gas**: `forge test --gas-report` в CI. `forge build --sizes` для EIP-170 (24KB) перевірки.
10. **Admin protection**: кожен контракт з AccessControl тестує `testRevert_cannotRemoveLastAdmin`.
11. **Pause bypass**: SCC/SFC `slash()` працює під pause (B-07). Обов'язковий тест: `test_pause_allowsSlash`.
12. **Invariant**: `totalSupply() <= MAX_SUPPLY` після будь-якої послідовності операцій.

### Контракти та їх тести
| Контракт | Файл | Тест |
|----------|------|------|
| SCC | `contracts/SilkenCarbonCoin.sol` | `contracts/test/SilkenCarbonCoin.t.sol` |
| SFC | `contracts/SilkenForestCoin.sol` | `contracts/test/SilkenForestCoin.t.sol` |
| StateRootAnchor | `contracts/StateRootAnchor.sol` | `contracts/test/StateRootAnchor.t.sol` |
| ProtocolParameters | `contracts/ProtocolParameters.sol` | `contracts/test/ProtocolParameters.t.sol` |
| SilkenGovernor | `contracts/SilkenGovernor.sol` | `contracts/test/SilkenGovernor.t.sol` |
| SilkenTimelock | `contracts/SilkenTimelock.sol` | `contracts/test/SilkenTimelock.t.sol` |
