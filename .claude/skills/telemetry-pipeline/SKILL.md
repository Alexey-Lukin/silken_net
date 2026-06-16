---
name: telemetry-pipeline
description: "Use when working on the silken_net telemetry / Proof-of-Growth pipeline — the uplink→verification→minting flow (CoAP intake → UnpackTelemetryWorker / TelemetryUnpackerService → IoTeX verify → Chainlink oracle → mint), the Sidekiq strict-priority queues, TelemetryLog (RANGE-partitioned, KENOSIS — validations live in valid_sensor_data?, not the model), and the dual-computation integrity (server Float Lorenz ≡ firmware mruby). Knows the gotchas — Queen Sentinel DID 0x0 → GatewayTelemetryWorker, oracle_status_*? enum methods, strict queue drain (uplink fully before alerts), find_with_partition_pruning. Routes to CLAUDE.md §5/§6 + the 05_02 canon, does not restate. Examples: \"add a telemetry field\", \"change minting logic / guards\", \"why is an alert delayed\", \"decode the uplink packet\", \"why does server Z differ from device Z\"."
---

# Telemetry Pipeline

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §5` | Proof of Growth pipeline — full A→D flow |
| `CLAUDE.md §6` | Sidekiq queue priority (strict, not weighted) |
| `docs/05_01_Tokenomics_Proof_of_Growth.md` | Growth points, SCC minting, slashing |
| `docs/05_02_Pipeline_Sequence.md` | Exact worker ordering with queue assignments |
| `docs/03_05_Security_Architecture.md §3` | AES decrypt chain, key management |

## Gotchas Not Obvious From Docs

1. **Queen Sentinel** — DID `0x00000000` routes to `GatewayTelemetryWorker`, NOT `TelemetryLog`. Easy to miss when adding telemetry processing logic.
2. **oracle_status prefix** — call `log.oracle_status_fulfilled?` not `log.oracle_status == "fulfilled"`. String-backed enum with `oracle_status_` prefix.
3. **Dual computation** — server Lorenz (Float) must match firmware mruby (Float). Was BigDecimal before FW.7 — old `to_d` code is a bug now.
4. **Queue drain is strict** — `uplink` (#1) drains COMPLETELY before `alerts` (#2). Telemetry flood blocks alerts. By design.
5. **Validations removed from TelemetryLog** — KENOSIS TITAN. Check is in `TelemetryUnpackerService.valid_sensor_data?`. Don't add validations back to model.
6. **Partition-aware lookups** — `TelemetryLog` RANGE-partitioned by `created_at`. Always use `find_with_partition_pruning(id, created_at)`.

## Common Tasks

- **Add telemetry field**: firmware pack → `TelemetryUnpackerService` unpack → DB migration → Phlex dashboard component → update `docs/05_02`
- **Change minting logic**: `BlockchainMintingService` → check 3 guards (IoTeX + Chainlink + Hadron) → update `docs/05_01`
