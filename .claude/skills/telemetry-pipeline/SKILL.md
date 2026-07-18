---
name: telemetry-pipeline
description: "Use when working on the silken_net telemetry / Proof-of-Growth pipeline — the uplink→verification→minting flow (CoAP intake → UnpackTelemetryWorker / TelemetryUnpackerService → IoTeX verify → Chainlink oracle → mint), the Sidekiq strict-priority queues, TelemetryLog (RANGE-partitioned, KENOSIS — validations live in valid_sensor_data?, not the model), and the dual-computation integrity (server Float Lorenz ≡ firmware mruby). Knows the gotchas — DID=0 in a batch is DEAD (ARCH.54: Queen pulse rides the signed QATT-v2 header → enqueue_envelope_health, both eras drop DID=0), oracle_status_*? enum methods, strict queue drain (uplink fully before alerts), find_with_partition_pruning. Routes to CLAUDE.md §5/§6 + the 05_02 canon, does not restate. Examples: \"add a telemetry field\", \"change minting logic / guards\", \"why is an alert delayed\", \"decode the uplink packet\", \"why does server Z differ from device Z\"."
---

# Telemetry Pipeline

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §1` | Proof of Growth pipeline — full A→D flow (sense→…→mint SCC) |
| `CLAUDE.md §5` | Sidekiq strict-priority queues + Lorenz/StatusByte + AES invariants |
| `CLAUDE.md §6` | Telemetry cross-domain gotchas (oracle_status prefix · KENOSIS · partitions) |
| `docs/05_02_Proof_of_Growth_Pipeline.md` | Exact worker ordering with queue assignments |
| `docs/05_03_Tokenomics_SCC_and_SFC.md` | Growth points, SCC minting (slashing → `05_05`) |
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md §3` | AES decrypt chain, key management |

## Gotchas Not Obvious From Docs

1. **DID `0x00000000` in a batch is DEAD (ARCH.54, 2026-07-03)** — the old Queen-Sentinel pseudo-tree is dropped on BOTH paths (ECB and CCM): the pulse rides the SIGNED QATT-v2 envelope header (8B health block, `firmware/common/queen_attest.h`) → `UnpackTelemetryWorker#enqueue_envelope_health` → `GatewayTelemetryWorker`. Never re-add gateway metrics as a fake tree — it eats a CIFO slot, breaks the CCM stride, and health without a valid Ed25519 must not exist (masking-attack). Canon: `03_02 §7` + `06_08 §1.3`.
2. **oracle_status prefix** — call `log.oracle_status_fulfilled?` not `log.oracle_status == "fulfilled"`. String-backed enum with `oracle_status_` prefix.
3. **Dual computation** — server Lorenz (Float) must match firmware mruby (Float). Was BigDecimal before FW.7 — old `to_d` code is a bug now.
4. **Queue drain is strict** — `uplink` (#1) drains COMPLETELY before `alerts` (#2). Telemetry flood blocks alerts. By design.
5. **Validations removed from TelemetryLog** — KENOSIS TITAN. Check is in `TelemetryUnpackerService.valid_sensor_data?`. Don't add validations back to model.
6. **Partition-aware lookups** — `TelemetryLog` RANGE-partitioned by `created_at`. Always use `find_with_partition_pruning(id, created_at)`.
7. **«Wire = вхід GP» contract (E.63 (г), wire-rev2.1)** — the CCM frame carries BOTH dT fields: raw (bytes 12..13, diagnostics/server-EMA) and `ema_delta_t_s` (bytes 20..21) = the EXACT number `metabolic_health` consumed on the device → `check_metabolic_divergence!` recomputes GP statelessly via `Attractor.expected_homeostasis_gp(ema)` (byte-identical mirror of `bio_contract.rb` §4.3 — edit the formula/thresholds THERE first, mirror second, regen `lorenz_bytecode.h`). The branch is **observational** (warn+metric) until the bench calibrates `DELTA_T_FAST_S`/`DELTA_T_SLOW_S`; `ema_delta_t_s` is transient (stripped pre-persist, like `lorenz_temperature_c`/`device_z`). ECB frames carry no ema → branch honestly skips. Canon: `03_04 §4.3` + `03_01 §13.6`.

8. **`firmware_version_id` = wire-ЗВІТ, не FK (SEC.20, 2026-07-12)** — post-SEC.20 семантика `[semantic:1|reverted:1|contract_id&0x3FFF]` (дзеркало `firmware/common/fw_report.h`): читай через `TelemetryLog#firmware_report_semantic?/reverted?/contract_id` (id ПО МОДУЛЮ 14 біт — НЕ join і не пряме порівняння з `BioContractFirmware.id`); legacy-кадри (без semantic-біта) несуть C-image константу — contract-версії НЕ мають. `reverted?` → `EwsAlert firmware_reverted` (термінальний: re-issue лише версією > спаленої — 03_06 §4 bump-інваріант).

9. **Device-event 0x57 = ОКРЕМИЙ L1-канал, не телеметрія (SEC.21, 2026-07-12)** — рідкісні security-події (canary-trip) НЕ їдуть телеметрійним трактом: окремий CoAP `PUT device/event/<uid>` → `DeviceEventWorker` (не `UnpackTelemetryWorker`). Королева підписує cleartext-конверт власним EDSK (тег `SLKN-QEVT1`, окремий від QATT2) → worker **verify gateway-origin** (`HardwareKey.ed25519_public_key_hex`, як QATT-батч), Rails LoRa-ключа НЕ торкається. Не плутай з CCM blind-courier телеметрії (там per-DID decrypt на Rails); тут — L1-підпис Королеви. Trust L1-observational, НІКОЛИ не money-path. Дім `03_05 §2.2а` + `03_02 §7а`.

## Common Tasks

- **Add telemetry field**: firmware pack → `TelemetryUnpackerService` unpack → DB migration → Phlex dashboard component → update `docs/05_02`
- **Change minting logic**: `BlockchainMintingService` → the **2-guard oracle chain (IoTeX + oracle_status)** protects PATH 1 only (latent — ARCH.53: dispatch = local marker, DON-callback unwired); **KYC (Hadron) guards ALL paths and is the sole PATH-2 perimeter** (live PATH 2 mint = optimistic, KYC-only; L0-custodial + ex-post clawback). Service-home = `04_02 §4`; tokenomics course → `05_03` (see `web3-pipeline` skill)
