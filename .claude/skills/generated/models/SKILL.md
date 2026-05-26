---
name: models
description: "Domain knowledge for core ActiveRecord models — Tree/Gateway AASM states, HardwareKey dual-key rotation, partitioned tables, Wallet tokenomics"
---

# Core Domain Models

## Tree (Soldier node — STM32WLE5JC)
- **DID format**: `SNET-XXXXXXXX` (8 hex digits), validated by `/\ASNET-[0-9A-F]{8}\z/`
- **peaq_did**: `"did:peaq:0x{40hex}"` — Web3 DID registered via `PeaqRegistrationWorker`
- **Includes**: `AASM`, `Firmwareable`, `GeoLocatable`, `NormalizeIdentifier`
- **AASM states** (column: `status`, enum-backed):
  - `active` (initial) -> `dormant` (suspend/reactivate) -> `removed` | `deceased`
  - `decommission` from active/dormant -> removed; `declare_deceased` from active/dormant -> deceased
- **bio_status** lives on `TelemetryLog`, NOT on Tree. Tree.status is lifecycle state.
- `mark_seen!(voltage_mv)` — `GREATEST(COALESCE(...))` atomic UPDATE, no callbacks, hot-path safe
- `effective_lorenz_thresholds` — 3-level priority: cluster per-species override > TreeFamily > global defaults (Z_MIN=2.0, Z_MAX=45.0, Z_OPTIMAL=29.0)
- `after_create` builds Wallet and DeviceCalibration automatically
- `trigger_slashing_protocol` fires `BurnCarbonTokensWorker` when tree becomes removed/deceased

## Gateway (Queen — STM32WLE5JC + SIM7070G)
- **UID format**: `SNET-Q-XXXXXXXX`, validated by `/\ASNET-Q-[0-9A-F]{8}\z/`
- **AASM states** (column: `state`, enum-backed):
  - `idle` (initial) <-> `active` (wake/sleep)
  - `idle`/`active` -> `updating` (begin_update) -> `idle` (finish_update)
  - `idle`/`active`/`faulty` -> `maintenance` (enter/exit_maintenance)
  - any operational state -> `faulty` (report_fault)
- `mark_seen!(new_ip:, voltage_mv:)` — same GREATEST atomic pattern as Tree
- `online?` = `last_seen_at >= (config_sleep_interval_s * 1.2).seconds.ago` — dynamic per-gateway threshold
- `scope :online` uses PostgreSQL `make_interval(secs => ...)` for DB-side check

## HardwareKey (AES key store)
- **Conditional key size** (post-ARCH.42): Tree = 32 hex (AES-128 LoRa), Gateway = 64 hex (AES-256 CoAP)
- **AR Encryption**: `encrypts :aes_key_hex, :previous_aes_key_hex, :lorenz_seed_hex` — non-deterministic
- **LRU cache**: `SinLruRedux::ThreadSafeCache` (10K entries), keys never leave Ruby process (no Redis)
- **Cache key versioning**: `"#{device_uid}:v:#{updated_at.to_f}"` — self-invalidating on any update
- **Dual-Key Grace Period**: `previous_aes_key_hex` kept after rotation until device confirms sync via `clear_grace_period!`
- **HKDF domain separation**: `"silken-aes-128-lora-key"` (Tree) vs `"silken-aes-256-device-key"` (Gateway)
- `owner` returns `tree || gateway` — polymorphic via `device_uid` FK
- `rotate_key!` is DEPRECATED — use `HardwareKeyService.rotate(device_uid)` for full rotation with downlink
- `lorenz_seed_hex`: 64 hex (32 bytes), required, used by `SilkenNet::SeedDerivation`

## TelemetryLog (partitioned)
- **RANGE-partitioned by `created_at`** — always use `find_with_partition_pruning(id, created_at)` to avoid full-partition scan
- **bio_status enum**: `homeostasis(0)`, `stress(1)`, `anomaly(2)`, `tamper_detected(3)` — prefix: `bio_status_`
- **oracle_status enum** (string-backed): `pending`, `dispatched`, `fulfilled`, `failed` — prefix: `oracle_status_`
- **KENOSIS TITAN**: ALL validations removed from model hot path. Data validated upstream in `TelemetryUnpackerService.valid_sensor_data?` before INSERT. Do NOT add ActiveRecord validations here.
- `recovery_confirmed?` reads denormalized `tree.health_streak >= 3` (no N+1)

## BlockchainTransaction (partitioned)
- **RANGE-partitioned by `created_at`**, composite PK `(id, created_at)`, `self.primary_key = "id"`
- **Always use** `find_with_partition_pruning(id, created_at)` — plain `find(id)` scans ALL partitions
- **AASM states**: `pending -> processing -> sent -> confirmed` | `failed` | `manual_review`
- **manual_review = DOUBLE-SPEND GUARD**: tx_hash exists but on-chain state unknown; funds stay in `locked_balance` until manual reconciliation
- `mark_as_sent(hash)` sets `tx_hash` + `sent_at`; `confirm(block_num, gas_cost)` sets finality fields
- **token_type**: `carbon_coin(0)`, `forest_coin(1)`, `cusd(2)`
- **blockchain_network**: `evm` | `solana` | `celo` — address validation differs per network

## Wallet (tokenomics)
- `credit!(points)` — pessimistic lock (`with_lock`), increments balance, broadcast-throttled (10s)
- `lock_and_mint!(points, threshold, token_type)` — 10,000 growth_points = 1 SCC. Checks `tree.active?`, resolves target address (wallet -> org fallback), creates `BlockchainTransaction(:pending)`
- `available_balance` = `balance - locked_balance` — double-spend protection
- `lock_funds!` / `release_locked_funds!` / `finalize_spend!` — all use `with_lock` for TOCTOU safety
- `lock_for_toucan_bridge!(amount)` — bridges SCC to TCO2 via Toucan Protocol

## Cluster (forest sector)
- `belongs_to :organization`; `has_many :trees, :gateways`
- `active_trees_count` — denormalized counter cache maintained by Tree callbacks (atomic SQL increment/decrement)
- `lorenz_overrides_for(scientific_name)` — per-species Lorenz Z thresholds stored in JSONB `lorenz_overrides_by_species`
- `health_index` — cached Float updated by `ClusterHealthCheckWorker`, formula: `1.0 - stress_index`
- `local_yesterday` — timezone-aware date using cluster's configured timezone (UTC fallback)
- PostGIS: `geo_boundary` column with GIST index, `containing_point(lat, lng)` scope

## Gotchas

1. **DID format**: peaq DID is `"did:peaq:0x{40hex}"`, hardware DID is `"SNET-XXXXXXXX"` — do not confuse
2. **Partitioned tables**: TelemetryLog and BlockchainTransaction require `created_at` in WHERE clauses for partition pruning. Never use bare `find(id)`.
3. **TelemetryLog validations**: removed by design (KENOSIS TITAN). Do NOT re-add — data is validated in the service layer before insert_all
4. **Tree.status vs TelemetryLog.bio_status**: Tree status is lifecycle (active/dormant/removed/deceased); bio_status is per-reading health (homeostasis/stress/anomaly/tamper)
5. **HardwareKey key length**: 32 hex = AES-128 (Tree/LoRa), 64 hex = AES-256 (Gateway/CoAP). Custom validators enforce owner-type consistency.
6. **Wallet locking**: all balance mutations use `with_lock` (SELECT FOR UPDATE). Never modify balance/locked_balance outside these methods.
7. **Gateway online?**: threshold is dynamic per-device (`config_sleep_interval_s * 1.2`), not a global constant
