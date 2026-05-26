---
name: telemetry-pipeline
description: "Domain knowledge for the uplink->verification->minting pipeline -- decrypt chain, Lorenz parity, oracle flow, queue priority"
---

# Telemetry Pipeline (CoAP -> Mint)

## Uplink Chain (strict order)

1. **CoAP PUT** `/telemetry/batch/<QUEEN_UID>` (UDP:5683) -- binary payload, Base64-encoded into Sidekiq arg.
2. **UnpackTelemetryWorker** (queue: `uplink`, retry: 3, expires_in: 5min):
   - Resolves Gateway by `uid` (priority) or `ip_address` (fallback).
   - Fetches `HardwareKey` for the Gateway. Dual-Key Grace Period: tries current key first, falls back to `binary_previous_key` during rotation. Successful decrypt with new key calls `clear_grace_period!`.
   - **AES-256-CBC** decrypt (Gateway CoAP key, 256-bit). Format: `[IV:16][ciphertext:N*16]`, zero-padding (not PKCS7).
   - Passes decrypted binary batch to `TelemetryUnpackerService.call(binary, gateway_id)`.
3. **TelemetryUnpackerService** (called inline, not async):
   - Splits batch into 21-byte chunks (ECB) or 25-byte chunks (CCM, behind `TELEMETRY_CCM_ENABLED` ENV).
   - Per chunk: extracts `DID(4) + RSSI(1) + Payload(16)`. Inner Soldier payload was **AES-128-ECB** encrypted on LoRa (Queen already decrypted before batching).
   - Preloads all Trees by DID with `includes(:wallet, :device_calibration, :tree_family, :hardware_key)` -- eliminates N+1.
   - Runs server-side Lorenz attractor (`SilkenNet::Attractor.calculate_z_from_state`), persists `lorenz_state_x/y/z` for warm-start chaining.
   - Commits `TelemetryLog`, then **outside the transaction**: enqueues `IotexVerificationWorker` and `StreamrBroadcastWorker`, credits wallet.

## Queen Sentinel

DID == `0x00000000` -> `GatewayTelemetryWorker.perform_async(queen_uid, stats_hash)` (queue: `uplink`, retry: 2). Creates `GatewayTelemetryLog` (NOT `TelemetryLog`). Reuses the Acoustic field as `cellular_signal_csq`. Checks critical faults (low battery, overheat, freeze, weak signal) and creates `EwsAlert` if needed.

## Dual Computation Integrity

- **Both sides use Float (IEEE 754 double)**. Server was BigDecimal until FW.7 -- now Float, bit-identical with firmware mruby.
- Initial state `(x0, y0, z0)` derived from per-tree `K_seed` via `SilkenNet::SeedDerivation` (HKDF-SHA256). DID is NOT an attractor input.
- `check_z_divergence!` compares categorical agreement (device bio_status vs server Z within species thresholds from `tree.effective_lorenz_thresholds`).
- Divergence = fraud flag + `TELEMETRY_FRAUD_DETECTED_TOTAL` Prometheus counter.
- Numeric drift check (`|server_z - device_z| > epsilon`) is feature-flagged behind `GAIA_DCI_NUMERIC_TOLERANCE=true` -- currently off because LoRa packet does not carry raw Z.
- ARCH.41 time-sync recovery: on mismatch, tries 3 epoch_day candidates (today, yesterday, firmware RTC default 10951) before flagging fraud. Enqueues `TimeSyncDownlinkWorker` on match.

## Oracle Flow

```
IotexVerificationWorker (web3_critical, retry 5)
  -> Iotex::W3bstreamVerificationService.verify!
  -> log.update!(verified_by_iotex: true, zk_proof_ref: ...)
  -> ChainlinkDispatchWorker.perform_async(log_id, created_at_iso)

ChainlinkDispatchWorker (web3_critical, retry 5)
  -> Chainlink::OracleDispatchService.dispatch!
  -- waits for external Chainlink DON callback --

POST /api/v1/oracle_callbacks (public, NO Bearer, HMAC-SHA256 verified)
  -> log.oracle_status = "fulfilled"
  -> MintCarbonCoinWorker.perform_async(log_id, created_at_iso)
  -> SolanaMicroRewardWorker.perform_async(...)
```

Both IoTeX and Chainlink workers use `Web3CircuitBreaker` (circuit-open raises, Sidekiq retries later).

## Minting Guards (BlockchainMintingService)

Three hard gates checked in `perform` before any on-chain call:
1. `@telemetry_log.verified_by_iotex?` -- IoTeX W3bstream ZK proof exists.
2. `@telemetry_log.oracle_status_fulfilled?` -- Chainlink DON confirmed. **NOTE**: `oracle_status` is a string-backed enum with method prefix `oracle_status_` (e.g., `oracle_status_fulfilled?`, NOT `fulfilled?`).
3. `wallet.hadron_kyc_status == "approved"` -- RWA compliance per wallet.

When called without `telemetry_log` (cron/TokenomicsEvaluator flow), guards are skipped -- growth_points were already credited through the verified pipeline.

## Sidekiq Queue Priority (strict, NOT weighted)

```
uplink(1) > alerts(2) > critical(3) > downlink(4) > default(5)
> web3_critical(6) > web3(7) > web3_low(8) > low(9)
```

`uplink` drains **completely** before `alerts` is polled. UnpackTelemetryWorker and GatewayTelemetryWorker both run on `uplink`. IoTeX/Chainlink/Mint workers run on `web3_critical`.

## Gotchas

- **Composite PK partition pruning**: `TelemetryLog` is range-partitioned by `created_at`. All find calls pass `(id, created_at)` pair via `find_telemetry_log_with_pruning` for O(log N) instead of O(P * log N).
- **Sidekiq jobs OUTSIDE transaction**: `IotexVerificationWorker`, `StreamrBroadcastWorker`, and `wallet.credit!` are enqueued/called AFTER the `commit_telemetry` transaction commits. Prevents phantom jobs on rollback.
- **Dual-Key Grace Period**: During key rotation, `HardwareKey.previous_aes_key_hex` stays active. `clear_grace_period!` is called only after successful decrypt with the new key.
- **Status byte wire format (FW.29)**: `[PanicFlag:1 | Status:2 | GrowthPoints:5]`. Wire growth_points (0..31) are `*2` to restore 0..62 range.
- **Panic anti-replay**: SEC.10 uses Redis SETNX with 25h TTL per `(DID, panic_frame_counter)` pair.
- **CCM path** (FW.2, not yet live): 25-byte chunks, per-Soldier AES-128-CCM decrypt with 8-byte MIC, frame counter anti-replay via Redis SETNX. Enabled by `TELEMETRY_CCM_ENABLED=true`.
- **MintCarbonCoinWorker.sidekiq_retries_exhausted**: triggers `MintingRollbackService` to unlock frozen capital.

## Common Tasks

**Adding a new telemetry field**:
1. Update firmware packet format (soldier `main.c` + `PAYLOAD_FORMAT` constant in `TelemetryUnpackerService`).
2. Add DB migration to `telemetry_logs` (partitioned table -- test partition creation).
3. Update `process_chunk` / `process_ccm_chunk` unpacking and `log_attributes` hash.
4. Update `valid_sensor_data?` bounds if the field has physical limits.
5. Update Phlex dashboard components (`Telemetry::LogEntry`, detail views).
6. If the field affects Lorenz: update `SilkenNet::Attractor` and `bio_contract.rb` in firmware.
7. Run `gitnexus_detect_changes()` before committing to verify blast radius.
