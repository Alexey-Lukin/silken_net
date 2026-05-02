# 10_03 — Test Coverage Matrix & Gap Analysis

> Карта покриття тестами SilkenNet Gaia 2.0 — усі шари (RSpec, Firmware C, Foundry Solidity).
> Оновлюється при додаванні нових сервісів, воркерів або смарт-контрактів.

---

## ✅ Статус

- **Поточний TRL:** TRL 8
- **тести:**
  - RSpec (Ruby)
  - Firmware (C)
  - Foundry (Solidity)

---

## 🗺️ 1. RSpec Coverage Matrix

### 1.1 Models

| Модель | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| Tree | ✅ 395L | 🟢 Повне | AASM, scopes, associations, bio_status enum |
| Wallet | ✅ 507L | 🟢 Повне | lock_and_mint!, credit!, pessimistic lock |
| BlockchainTransaction | ✅ 533L | 🟢 Повне | AASM transitions, partition pruning |
| User | ✅ 543L | 🟢 Повне | Argon2, roles, OAuth, MFA |
| Gateway | ✅ 394L | 🟢 Повне | AASM, mark_seen!, online? |
| HardwareKey | ✅ 295L | 🟢 Повне | AES key encryption, LRU cache, **[SEC.11] `lorenz_seed_hex` validation, `binary_lorenz_seed` AR Encryption non-deterministic** |
| EwsAlert | ✅ 669L | 🟢 Повне | Alert types, severity levels |
| TelemetryLog | ✅ 320L+ | 🟢 **Повне** | **oracle_status enum, associations, in_timeframe/vandalized scopes, bio_status enum** |
| TreeFamily | ✅ 290L+ | 🟢 **Повне** | **attractor_thresholds (optimal key FW.8), effective_optimal_z_target, biological_properties** |
| Cluster | ✅ 380L+ | 🟢 **Повне** | **lorenz_overrides_by_species validation (FW.8), lorenz_overrides_for, Associations, store_accessor validations, recalculate_health_index! with AiInsight, alphabetical scope** |
| AuditLog | ✅ 400L+ | 🟢 **Повне** | **chain_payload determinism, metadata ordering, tamper detection, deleted record chain break, bulk advisory lock** |
| **Firmwareable (concern)** | ✅ 230L+ | 🟢 **Повне** | **AASM transitions тестуються: всі 7 подій, invalid transitions, lifecycle** |

### 1.2 Services

| Сервіс | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| BlockchainMintingService | ✅ 1092L | 🟢 Повне | batchMint, guard clauses, binary search |
| TelemetryUnpackerService | ✅ 560L+ | 🟢 **Повне** | **check_z_divergence! (effective_lorenz_thresholds FW.8), update_health_streak!, boundary sensors, acoustic overflow, [FW.5] delta_t/vcap β-perturbation, [SEC.11] per-tree warm/cold dispatch, lorenz_state persist, MissingLorenzSeedError, cold_start_flag, [FW.31] numeric tolerance band feature-flag (6 examples: toggle off / within ε / drift > ε / default ε constant / malformed ENV fallback / device_z absent)** |
| InsightGeneratorService | ✅ 670L | 🟢 Повне | Fraud guard, cleanup_old_logs! |
| SilkenNet::Attractor | ✅ 310L+ | 🟢 Повне | Float precision, deterministic chaos, **[FW.5] perturb_beta, parity-fuzz 500 cases (0 mismatches), [SEC.11] sole `calculate_z_from_state` API (legacy `calculate_z(seed,…)` removed)** |
| **SilkenNet::SeedDerivation** [SEC.11] | ✅ 16 examples | 🟢 **Нове** | **HKDF-SHA256 (RFC 5869) + HMAC-SHA256 + signed-unit-float unpack; raises `SecurityError` без `PROVISIONING_MASTER_KEY`; firmware-equivalence vectors з `firmware/test/test_seed_derivation.c`; daily epoch_day rotation; (x₀,y₀,z₀) ∈ [-1,+1]³ deterministic** |
| BlockchainBurningService | ✅ 420L+ | 🟢 **Повне** | **SLASHER_KEY fallback (E.2), Prometheus SCC_SLASHED_TOTAL, AiInsight+source_tree combined ratio, damage_ratio cap** |
| Treasury::MonitorService | ✅ 330L+ | 🟢 **Повне** | **build_config, missing credentials, humanize edge cases, multiple alerts** |
| TreeChronicleService | ✅ 350L+ | 🟢 **Повне** | **Pagination edges, nil wallet, boundary stress_index, mixed sources** |
| Chainlink::OracleDispatchService | ✅ 240L+ | 🟢 **Повне** | **WEB3_STRICT_MODE, missing DON_ID, nil payload fields, ABI validation, [S6.15] Web3::ChainlinkRouterVersion delegation + bytecode probe + graceful fallback + probe-disabled mode (5 examples)** |
| **Web3::ChainlinkRouterVersion** [S6.15] | ✅ 17 examples | 🟢 **Нове** | **active_version (default v1, blank ENV, unsupported raise), abi_for(:v1) shape + 5 inputs, selector_for(:v1) = `0x461d2762`, signature_for canonical, fallback_for(:v1) = nil (oldest), selector_present_in_code? (case-insensitive substring, blank/nil tolerant), supported?** |
| AlertDispatchService | ✅ 420L+ | 🟢 **Повне** | **Adaptive thresholds, silence keys, rate limiting (SEC.10), voltage/fire boundaries, EmergencyResponseService call** |
| HardwareKeyService | ✅ 280L+ | 🟢 **Повне** | **HKDF SHA256/info/salt params, key length, derive_device_key logging, provision conflict** |
| MintingRollbackService | ✅ 400L+ | 🟢 **Повне** | **Solana tx status, receipt edge cases, Celo routing, locked_points nil fallback, invalid ISO8601** |
| EmergencyResponseService | ✅ 350L+ | 🟢 **Повне** | **Mixed valve+siren fire response, command attributes (org_id, idempotency, priority, expires_at), online/offline gateway filter** |
| OtaPackagerService | ✅ 415L+ | 🟢 **Повне** | **[FW.8] build_threshold_config_block (CMD_SET_THRESHOLDS 0x9A, CRC16, species_id, effective_lorenz_thresholds); [FW.23] compute_hmac_tag (deterministic + anti-replay через version_id + anti-truncation через total_chunks + per-cluster K_ota isolation), build_hmac_trailer_chunks (3× 16-byte LoRa-формат, 0x9B marker, seg_idx 1/2/3 BE, payload reconstructs 32-byte HMAC), prepare(cluster_id:) opt-in (3 trailer chunks appended, manifest exposes lora_total_chunks/hmac_signed/hmac_cluster_id, backward-compat без cluster_id); LoRa MTU chunks, single-byte payload, exact block-size, CRC16 known vectors, manifest format** |
| **OtaHmacKeyService [FW.23]** | ✅ 9 examples | 🟢 **Нове** | **HKDF-SHA256 derivation з info `"silken-ota-hmac-v1"` (domain separation від HardwareKeyService AES key); deterministic per cluster_id; ArgumentError на blank cluster_id; SecurityError без `PROVISIONING_MASTER_KEY` (SEC.11 hard cutover, no SecureRandom fallback); fetch_binary_for повертає 32-byte ASCII-8BIT** |
| Etherisc::ClaimService | ✅ 120L+ | 🟢 **Повне** | **nil policy_id, missing ENV keys, ABI validation** |
| Ed25519Crypto::SigningService | ✅ 270L+ | 🟢 **Повне** | **Empty/large messages, hex validation edges, uppercase hex, nil/integer message coercion** |

### 1.3 Workers

| Воркер | Спека | Покриття | Примітки |
|--------|-------|----------|----------|
| UnpackTelemetryWorker | ✅ 430L+ | 🟢 **Повне** | **Sentry tags, broadcast_raw_hex format, gateway.mark_seen! IP/timestamp, sidekiq config** |
| Governance::ParameterSyncWorker | ✅ 450L | 🟢 Повне | |
| InsurancePayoutWorker | ✅ 340L+ | 🟢 **Повне** | **Sidekiq config, satellite mixed alert types, severe_drought block, Etherisc recovery** |
| ActuatorCommandWorker | ✅ 320L+ | 🟢 **Повне** | **dispatch! AASM transition, mark_active!, encryption roundtrip, ResetActuatorStateWorker scheduling, sidekiq config** |
| **Web3CircuitBreaker (concern)** | ✅ 320L+ | 🟢 **Повне** | **transient_cause?, reset_circuit!, remaining_open_seconds, all error types, record_failure! threshold** |
| **CoapEncryption (concern)** | ✅ 175L+ | 🟢 **Повне** | **[FW.20] TIME_SYNC envelope (0x9C marker + ts:4 big-endian), All mod-16 payload sizes (1,15,17,31,32,33), binary data, null-byte padding, IV uniqueness** |

### 1.4 Controllers

Усі API v1 контролерів мають відповідні request spec файли. Покриття: 🟢 Повне.

### 1.5 Policies

Усі Pundit policies покриті. Покриття: 🟢 Повне.

### 1.6 Views

Усі Phlex-компоненти покриті згідно з `docs/10_01_View_Component_Testing_Guide.md`.

### 1.7 Integration Tests

| Тест | Покриття | Критичність |
|------|----------|------------|
| telemetry_ingestion_pipeline | 🟢 | Proof of Growth uplink |
| blockchain_minting_burning_flow | 🟢 | SCC minting + slashing |
| wallet_tokenomics_flow | 🟢 | Growth points → SCC |
| proof_of_growth_chaos_engineering | 🟢 | Fault tolerance |
| ota_firmware_flow | 🟢 | OTA lifecycle + **[FW.23] e2e dual-gate** (7 нових: backend-signs trailer chunks, manifest lora_total_chunks cross-check, HMAC reconstruct backend↔soldier match, magic+hmac both-pass acceptance, anti-tamper bytecode flip rejection, anti-replay version_id mismatch, anti-truncation total_chunks mismatch) |
| gateway_lifecycle | 🟢 | Gateway AASM |
| user_auth_lifecycle | 🟢 | Auth + MFA + OAuth |
| emergency_response_flow | 🟢 | EWS pipeline |
| audit_log_chain_integrity | 🟢 | Audit tamper detection |
| **fw8_threshold_governance** [FW.8] | 🟢 **Нове** | **3-tier effective_lorenz_thresholds, cluster override > tree_family > global, build_threshold_config_block CRC16, lorenz_overrides_by_species validation, coap_encryption FW.20 envelope — 18 examples** |
| **provisioning_e2e** [FW.1] | 🟢 **Нове** | **HKDF determinism (firmware-equivalence), atomic Tree/HardwareKey/MaintenanceRecord, Ed25519 persist, TRL4 vs HKDF response shape, SEC.11 production guard, FW.24 magic guard, duplicate UID — 8 examples без mocks `HardwareKeyService`** |

---

## 🔧 2. Firmware Test Coverage

### 2.1 Soldier (test_soldier_logic.c)

| Область | Тести | Покриття |
|---------|-------|----------|
| Payload Pack/Unpack | 20+ | 🟢 Повне |
| Mesh Dedup (Anti-pingpong, 3-slot FW.21) | 8 | 🟢 Повне |
| OTA Chunk Assembly + CRC32 | 15+ | 🟢 Повне |
| Bio-Contract Byte Parse | 8+ | 🟢 Повне |
| Panic Payload | 6 | 🟢 Повне — **[FW.29]** `test_panic_flag_set_in_emergency_payload`, `test_normal_payload_panic_flag_clear` |
| OnRxDone Size Validation | 5 | 🟢 Повне |
| Lorenz State Persistence (FW.6) | 9 | 🟢 Повне |
| Acoustic Saturating Increment (FW.22) | 6 | 🟢 Повне — включаючи atomic snapshot (FW.28) |
| RSSI Clamping | 7 | 🟢 Повне |
| EMA Filter (FW.21) | 10 | 🟢 Повне |
| **[FW.5 B+] EMA → mruby args[5..6]** | **6** | 🟢 **Нове** — cold-boot baseline defaults (60 s / 3300 mV), warmup-phase defaults, post-warmup EMA forwarding, boundary clamps (vcap=5500, dt=1, zero-input) |
| DID Generation (FW.24) | 5 | 🟢 Повне — **[FW.24]** `test_did_hrng_fallback_not_magic` |
| **[FW.1] Flash Key Loading** | **8** | 🟢 **Нове** | `Load_AES_Key()` magic check, key-not-provisioned → Error_Handler, FLASH_KEY_ADDR 0x0803E000 |
| **[SEC.11 / FW.30] Flash Seed Loading** | **6** | 🟢 **Нове** — `Load_Lorenz_Seed()` magic check ("LSED"), provisioned/unprovisioned/wrong magic/zero seed, non-fatal (без Error_Handler) |
| **[SEC.11 / FW.30] Cold-Start Derivation** | **4** | 🟢 **Нове** — `Derive_Cold_Start_State()` coordinates ∈ [-1,+1], deterministic, date-sensitive, seed-sensitive |
| **[FW.30] C-Bridge 7-Arg Signature** | **1** | 🟢 **Нове** — Lorenz iteration з 7-arg сигнатурою produces finite coords |

### 2.2 Queen (test_queen_logic.c)

| Область | Тести | Покриття |
|---------|-------|----------|
| DJB2 Hash | 7 | 🟢 Повне |
| Command Dedup (Ring Buffer) | 7 | 🟢 Повне |
| CIFO EdgeCache | 14 | 🟢 Повне |
| Binary Batch Packing | 7 | 🟢 Повне |
| OTA Chunk Assembly + Bitmap | 15 | 🟢 Повне |
| Queen UID Flash Read | 8+ | 🟢 Повне |
| RSSI Clamping | 7 | 🟢 Повне |
| ECB/CBC Restoration | 3 | 🟢 Повне |
| HRNG IV Generation | 5 | 🟢 Повне |
| **CoAP Retry (FW.9)** | **4** | 🟢 **Нове** — `test_coap_retry_constants`, константи `COAP_MAX_RETRIES`, `UART_RX_BUF_SIZE` |
| **[FW.1] Flash Key Loading** | **8** | 🟢 **Нове** | `Load_AES_Key()` magic check, key-not-provisioned → Error_Handler, FLASH_KEY_ADDR 0x0803E000 |
| **[FW.3] LoRa RX Ring Buffer** | **13** | 🟢 **Нове** (2026-05-02) — single-producer FIFO, capacity 15, переповнення → drop counter (existing voices preserved), drain+refill wraps, RSSI passthrough, ISR simulator size/RSSI clamp, **25-сек flush сценарій** (30 ISR пакетів → 15 уцілілих + 15 видимих втрат). Закриває BLOCKER-2 part-1: `incoming_lora_payload`+`lora_rx_flag` → ring. |

### 2.3 Bio-Contract (test_bio_contract.c)

| Область | Тести | Покриття |
|---------|-------|----------|
| Sigma/Rho Clamping | 5 | 🟢 Повне |
| Z-Axis Lorenz | 5 | 🟢 Повне |
| Constants Verification | 3 | 🟢 Повне |
| StatusByte Encoding | 2 | 🟢 Повне |
| Growth Points Logic | 7 | 🟢 Повне |
| Evaluate & Pack Integration | 2 | 🟢 Повне |
| Boundary Conditions | 5 | 🟢 Повне |
| **[FW.5] β-Perturbation** | **4** | 🟢 **Нове** — `test_beta_nominal_no_perturbation`, `test_beta_fast_charge_increases_beta`, `test_beta_high_vcap_increases_beta`, `test_beta_clamp_upper_limit` |

### 2.4 Encryption (test_encryption.c)

| Область | Тести | Покриття | ⚠️ |
|---------|-------|----------|-----|
| ECB/CBC Mode Switch | 4 | 🟢 | Mock AES (not real CRYP) |
| ECB Restore After Flush | 4 | 🟢 | |
| Error Recovery (FW.16) | 3 | 🟢 | |
| IV Handling | 3 | 🟢 | |
| Encrypt/Decrypt Verify | 3 | 🟢 | Mock HAL |
| **[FW.1] Flash Key Integration** | **3** | 🟢 **Нове** | `Load_AES_Key()` → CRYP init integration, key-zero rejection, magic validation |

### 2.6 Seed Derivation Host-Parity (test_seed_derivation.c) [SEC.11] 🆕

| Область | Тести | Покриття |
|---------|-------|----------|
| HKDF-SHA256 RFC 5869 known-vector (simple UID) | 1 | 🟢 OpenSSL ↔ mbedTLS байт-ідентично |
| `derive_initial_state` bounds (x₀,y₀,z₀ ∈ [-1,+1]) | 3 | 🟢 По кожній координаті окремо |
| Epoch rotation (`epoch_day +1` змінює всі координати) | 1 | 🟢 Forward secrecy ≤ 24 год |
| Determinism (same `K_seed`, same `epoch_day` → bit-identical state) | 1 | 🟢 Повторювальність |
| `bytes_to_signed_unit_float` boundary (zero → -1, max → +1, mid → ~0) | 3 | 🟢 IEEE-754 unpack |
| Mixed-seed shape (різні `K_seed` → різні координати) | 1 | 🟢 Distinct seeds → distinct trajectories |
| Initial state shape для відомого `(K_seed, epoch_day)` (mixed seed) | 3 | 🟢 Backend-firmware parity vector |

### 2.5 TinyML Pipeline (test_tinyml_pipeline.c)

| Область | Тести | Покриття | ⚠️ |
|---------|-------|----------|-----|
| Audio Normalization | 5 | 🟢 | |
| Confidence Threshold (legacy 0.80 binary) | 5 | 🟢 | Mock inference |
| Event Classification | 5 | 🟢 | |
| Saturation (FW.22) | 5 | 🟢 | |
| Vibration Guard (FW.11) | 5 | 🟢 | |
| **[FW.18] Dual-Threshold Zones** | **9** | 🟢 **Нове** | SILENCE/WARNING/CRITICAL + escalation 3× для chainsaw, no-escalation для cavitation, counter reset |
| **[FW.18] Threshold Validation & RTC Roundtrip** | **10** | 🟢 **Нове** | range/NaN/cold-boot/inversion fallbacks + IEEE 754 bit-exact roundtrip через DR13/DR14 |
| **[FW.18] OTA CMD dispatcher (`0x9D`)** | **7** | 🟢 **Нове** | downlink-CMD framework на Soldier'і — frame layout / CRC16 / range / inversion / short_frame; опкод-карта `0x99=OTA / 0x9A=Lorenz Z / 0x9B=HMAC trailer / 0x9C=TIME_SYNC / 0x9D=audio thresholds` |
| **[FW.27-B] Magic Re-Request — Soldier bitmap** | **12** | 🟢 **Нове** | Build_OTA_ReRequest_Payload: full/partial/edge/cap@72 + DID/total BE-pack + 5-хв timeout trigger |
| **[FW.27-B] Magic Re-Request — Queen handler** | **10** | 🟢 **Нове** | Process_LoRa_RX accepts/rejects; cmd_dedup_ring replay-protection; різні bitmap'и не дедуплюються (`djb2_hash_bytes` length-strict NUL-safe); REREQUEST не потрапляє у CIFO/CoAP path; total_chunks mismatch reject |
| **[FW.23] HMAC trailer parser + dual-gate (Soldier)** | **13** | 🟢 **Нове** | 3-чанковий збір печатки (in-order/out-of-order), reject seg_idx>3/wrong marker/short, dual-gate: magic-fail / hmac-fail / both-pass / cleanup-on-failure / constant-time first-byte / constant-time last-byte |
| **[FW.23] HMAC trailer relay (Queen)** | **4** | 🟢 **Нове** | 3 segments assemble, seg_idx=4 reject, wrong marker reject, overwrite same segment |

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
| AT Command UART | 🟡 MEDIUM | SIM7070G modem I/O не тестується повністю (апаратна залежність). Константи retry та таймаутів верифіковані `test_coap_retry_constants` (FW.9) |
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

## 🎯 6. Рекомендації для нових фіч

1. **Кожен новий Service/Worker** ПОВИНЕН мати spec файл з ratio ≥ 1.5x.
2. **AASM state machines** ПОВИННІ тестувати всі transitions + invalid transitions.
3. **Web3 сервіси** ПОВИННІ тестувати: stub mode, strict mode, missing credentials, RPC errors.
4. **Phlex компоненти** — слідувати `docs/10_01_View_Component_Testing_Guide.md` (min 8 examples).
5. **Firmware** — кожна нова функція потребує host-based test у `firmware/test/`.
6. **Solidity** — naming: `test_` (happy), `testRevert_` (error), `testFuzz_` (fuzz).
