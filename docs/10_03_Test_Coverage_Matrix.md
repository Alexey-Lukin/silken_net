# 10_03 — Test Coverage Matrix & Gap Analysis

> Карта покриття тестами SilkenNet Gaia 2.0 — усі шари (RSpec, Firmware C, Foundry Solidity).
> Оновлюється при додаванні нових сервісів, воркерів або смарт-контрактів.

---

## ✅ Статус

- **Поточний TRL:** TRL 8
- **Дата аудиту:** 2026-04-26
- **Кількість тестів:**
  - RSpec (Ruby): ~290+ spec files, ~49,000+ lines
  - Firmware (C): 247 tests (79 soldier + 92 queen + 33 bio-contract + 25 tinyml + 18 encryption)
  - Foundry (Solidity): 6 test suites, ~115+ tests

---

## 🗺️ 1. RSpec Coverage Matrix

### 1.1 Models (32 spec files)

| Модель | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| Tree | ✅ 395L | 🟢 Повне | AASM, scopes, associations, bio_status enum |
| Wallet | ✅ 507L | 🟢 Повне | lock_and_mint!, credit!, pessimistic lock |
| BlockchainTransaction | ✅ 533L | 🟢 Повне | AASM transitions, partition pruning |
| User | ✅ 543L | 🟢 Повне | Argon2, roles, OAuth, MFA |
| Gateway | ✅ 394L | 🟢 Повне | AASM, mark_seen!, online? |
| HardwareKey | ✅ 295L | 🟢 Повне | AES key encryption, LRU cache |
| EwsAlert | ✅ 669L | 🟢 Повне | Alert types, severity levels |
| TelemetryLog | ✅ 320L+ | 🟢 **Повне** | **oracle_status enum, associations, in_timeframe/vandalized scopes, bio_status enum** |
| Cluster | ✅ 380L+ | 🟢 **Повне** | **Associations, store_accessor validations, recalculate_health_index! with AiInsight, alphabetical scope** |
| AuditLog | ✅ 400L+ | 🟢 **Повне** | **chain_payload determinism, metadata ordering, tamper detection, deleted record chain break, bulk advisory lock** |
| **Firmwareable (concern)** | ✅ 230L+ | 🟢 **Повне** | **AASM transitions тестуються: всі 7 подій, invalid transitions, lifecycle** |

### 1.2 Services (43 spec files)

| Сервіс | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| BlockchainMintingService | ✅ 1092L | 🟢 Повне | batchMint, guard clauses, binary search |
| TelemetryUnpackerService | ✅ 550L+ | 🟢 **Повне** | **check_z_divergence!, update_health_streak!, boundary sensors, acoustic overflow** |
| InsightGeneratorService | ✅ 670L | 🟢 Повне | Fraud guard, cleanup_old_logs! |
| SilkenNet::Attractor | ✅ 218L | 🟢 Повне | Float precision, deterministic chaos |
| BlockchainBurningService | ✅ 420L+ | 🟢 **Повне** | **SLASHER_KEY fallback (E.2), Prometheus SCC_SLASHED_TOTAL, AiInsight+source_tree combined ratio, damage_ratio cap** |
| Treasury::MonitorService | ✅ 330L+ | 🟢 **Повне** | **build_config, missing credentials, humanize edge cases, multiple alerts** |
| TreeChronicleService | ✅ 350L+ | 🟢 **Повне** | **Pagination edges, nil wallet, boundary stress_index, mixed sources** |
| Chainlink::OracleDispatchService | ✅ 240L+ | 🟢 **Повне** | **WEB3_STRICT_MODE, missing DON_ID, nil payload fields, ABI validation** |
| AlertDispatchService | ✅ 420L+ | 🟢 **Повне** | **Adaptive thresholds, silence keys, rate limiting (SEC.10), voltage/fire boundaries, EmergencyResponseService call** |
| HardwareKeyService | ✅ 280L+ | 🟢 **Повне** | **HKDF SHA256/info/salt params, key length, derive_device_key logging, provision conflict** |
| MintingRollbackService | ✅ 400L+ | 🟢 **Повне** | **Solana tx status, receipt edge cases, Celo routing, locked_points nil fallback, invalid ISO8601** |
| EmergencyResponseService | ✅ 350L+ | 🟢 **Повне** | **Mixed valve+siren fire response, command attributes (org_id, idempotency, priority, expires_at), online/offline gateway filter** |
| OtaPackagerService | ✅ 230L+ | 🟢 **Повне** | **LoRa MTU chunks, single-byte payload, exact block-size, CRC16 known vectors, manifest format** |
| Etherisc::ClaimService | ✅ 120L+ | 🟢 **Повне** | **nil policy_id, missing ENV keys, ABI validation** |
| Ed25519Crypto::SigningService | ✅ 270L+ | 🟢 **Повне** | **Empty/large messages, hex validation edges, uppercase hex, nil/integer message coercion** |

### 1.3 Workers (41 spec files)

| Воркер | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| UnpackTelemetryWorker | ✅ 430L+ | 🟢 **Повне** | **Sentry tags, broadcast_raw_hex format, gateway.mark_seen! IP/timestamp, sidekiq config** |
| Governance::ParameterSyncWorker | ✅ 450L | 🟢 Повне | |
| InsurancePayoutWorker | ✅ 340L+ | 🟢 **Повне** | **Sidekiq config, satellite mixed alert types, severe_drought block, Etherisc recovery** |
| ActuatorCommandWorker | ✅ 320L+ | 🟢 **Повне** | **dispatch! AASM transition, mark_active!, encryption roundtrip, ResetActuatorStateWorker scheduling, sidekiq config** |
| **Web3CircuitBreaker (concern)** | ✅ 320L+ | 🟢 **Повне** | **transient_cause?, reset_circuit!, remaining_open_seconds, all error types, record_failure! threshold** |
| CoapEncryption (concern) | ✅ 150L+ | 🟢 **Повне** | **All mod-16 payload sizes (1,15,17,31,32,33), binary data, null-byte padding, IV uniqueness** |

### 1.4 Controllers (30 spec files)

Усі 30 API v1 контролерів мають відповідні request spec файли. Покриття: 🟢 Повне.

### 1.5 Policies (14 spec files)

Усі 14 Pundit policies покриті. Покриття: 🟢 Повне.

### 1.6 Views (85 spec files)

Усі Phlex-компоненти покриті згідно з `docs/10_01_View_Component_Testing_Guide.md`.

### 1.7 Integration Tests (23 spec files)

| Тест | Покриття | Критичність |
|------|----------|------------|
| telemetry_ingestion_pipeline | 🟢 | Proof of Growth uplink |
| blockchain_minting_burning_flow | 🟢 | SCC minting + slashing |
| wallet_tokenomics_flow | 🟢 | Growth points → SCC |
| proof_of_growth_chaos_engineering | 🟢 | Fault tolerance |
| ota_firmware_flow | 🟢 | OTA lifecycle |
| gateway_lifecycle | 🟢 | Gateway AASM |
| user_auth_lifecycle | 🟢 | Auth + MFA + OAuth |
| emergency_response_flow | 🟢 | EWS pipeline |
| audit_log_chain_integrity | 🟢 | Audit tamper detection |

---

## 🔧 2. Firmware Test Coverage

### 2.1 Soldier (test_soldier_logic.c — 92 tests)

| Область | Тести | Покриття |
|---------|-------|----------|
| Payload Pack/Unpack | 20+ | 🟢 Повне |
| Mesh Dedup (Anti-pingpong) | 8 | 🟢 Повне |
| OTA Chunk Assembly + CRC32 | 15+ | 🟢 Повне |
| Bio-Contract Byte Parse | 8+ | 🟢 Повне |
| Panic Payload | 4 | 🟢 Повне |
| OnRxDone Size Validation | 5 | 🟢 Повне |
| Lorenz State Persistence (FW.6) | 9 | 🟢 Повне |
| Acoustic Saturating Increment (FW.22) | 6 | 🟢 Повне |
| RSSI Clamping | 7 | 🟢 Повне |

### 2.2 Queen (test_queen_logic.c — 79 tests)

| Область | Тести | Покриття |
|---------|-------|----------|
| DJB2 Hash | 7 | 🟢 Повне |
| Command Dedup (Ring Buffer) | 7 | 🟢 Повне |
| CIFO EdgeCache | 14 | 🟢 Повне |
| Binary Batch Packing | 7 | 🟢 Повне |
| OTA Chunk Assembly + Bitmap | 15 | 🟢 Повне |
| Queen UID Flash Read | 8+ | 🟢 Повне |
| RSSI Clamping | 7 | 🟢 Повне |

### 2.3 Bio-Contract (test_bio_contract.c — 33 tests)

| Область | Тести | Покриття |
|---------|-------|----------|
| Sigma/Rho Clamping | 5 | 🟢 Повне |
| Z-Axis Lorenz | 5 | 🟢 Повне |
| Constants Verification | 3 | 🟢 Повне |
| StatusByte Encoding | 2 | 🟢 Повне |
| Growth Points Logic | 7 | 🟢 Повне |
| Evaluate & Pack Integration | 2 | 🟢 Повне |
| **Boundary Conditions** | **5** | 🟢 **Нове** |

### 2.4 Encryption (test_encryption.c — 18 tests)

| Область | Тести | Покриття | ⚠️ |
|---------|-------|----------|-----|
| ECB/CBC Mode Switch | 4 | 🟢 | Mock AES (not real CRYP) |
| ECB Restore After Flush | 4 | 🟢 | |
| Error Recovery (FW.16) | 3 | 🟢 | |
| IV Handling | 3 | 🟢 | |
| Encrypt/Decrypt Verify | 3 | 🟢 | Mock HAL |

### 2.5 TinyML Pipeline (test_tinyml_pipeline.c — 25 tests)

| Область | Тести | Покриття | ⚠️ |
|---------|-------|----------|-----|
| Audio Normalization | 5 | 🟢 | |
| Confidence Threshold | 5 | 🟢 | Mock inference |
| Event Classification | 5 | 🟢 | |
| Saturation (FW.22) | 5 | 🟢 | |
| Vibration Guard (FW.11) | 5 | 🟢 | |

---

## ⛓️ 3. Solidity Test Coverage (Foundry)

| Контракт | Тестів | Покриття | Примітки |
|----------|--------|----------|----------|
| SilkenCarbonCoin (SCC) | 45 | 🟢 Повне | mint, batchMint, slash, pause bypass, MAX_SUPPLY |
| SilkenForestCoin (SFC) | 45 | 🟢 Повне | ERC20Votes, auto-delegation, nonces override |
| StateRootAnchor | 25 | 🟢 Повне | MIN_ANCHOR_INTERVAL, fuzz tests |
| ProtocolParameters | 20+ | 🟢 Повне | Governance parameter store |
| SilkenGovernor | 20+ | 🟢 Повне | Proposal lifecycle |
| SilkenTimelock | 20+ | 🟢 Повне | Delay enforcement |

---

## 🔴 4. Відомі обмеження та відкриті ризики

### 4.1 Firmware

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Mock AES | 🔴 CRITICAL | `hal_mock.h` копіює plaintext→ciphertext; реальна AES верифікація неможлива без ARM HW |
| Mock TinyML | 🟠 HIGH | `Run_Inference()` повертає фіксовані класи; реальна модель не тестується |
| AT Command UART | 🟠 HIGH | SIM7070G modem I/O не тестується (апаратна залежність) |
| DMA Audio Timing | 🟠 HIGH | 512-sample DMA transfer timing не верифікується на host |

### 4.2 Solidity

| Ризик | Серйозність | Опис |
|-------|------------|------|
| ERC20Permit | 🟡 MEDIUM | Permit/signature tests є базовими; cross-chain replay не тестується |
| Governor Integration | 🟡 MEDIUM | Governor + SCC mint interaction тестується окремо |

### 4.3 Backend

| Ризик | Серйозність | Опис |
|-------|------------|------|
| Concurrent State | 🟡 MEDIUM | Race conditions у AASM transitions не тестуються (потребують multi-thread test) |
| Live Web3 RPC | 🟡 MEDIUM | Всі Web3 виклики заглушені; live RPC тестування потребує staging env |

---

## 📊 5. Агрегована статистика

| Шар | Spec Files | Total Lines | Ratio (spec/src) |
|-----|------------|-------------|------------------|
| Models | 32 | 9,831 | ~2.2x |
| Services | 43 | 9,738 | ~1.8x |
| Workers | 41 | 6,447 | ~1.7x |
| Requests | 30 | 4,638 | ~1.9x |
| Integration | 23 | 4,986 | — |
| Views | 85 | 10,001 | ~2.0x |
| Policies | 14 | 1,416 | ~2.5x |
| Blueprints | 9 | 1,081 | ~2.0x |
| Firmware (C) | 5 | ~3,500 | 247 tests |
| Solidity | 6 | ~2,000 | 115+ tests |
| **Total** | **288+** | **~52,000+** | — |

---

## 🎯 6. Рекомендації для нових фіч

1. **Кожен новий Service/Worker** ПОВИНЕН мати spec файл з ratio ≥ 1.5x.
2. **AASM state machines** ПОВИННІ тестувати всі transitions + invalid transitions.
3. **Web3 сервіси** ПОВИННІ тестувати: stub mode, strict mode, missing credentials, RPC errors.
4. **Phlex компоненти** — слідувати `docs/10_01_View_Component_Testing_Guide.md` (min 8 examples).
5. **Firmware** — кожна нова функція потребує host-based test у `firmware/test/`.
6. **Solidity** — naming: `test_` (happy), `testRevert_` (error), `testFuzz_` (fuzz).
