---
name: models
description: "Navigation + gotchas for core AR models. Read SSOT docs first."
---

# Models

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §4` | All key entities: Tree, Gateway, HardwareKey, TelemetryLog, Wallet, BlockchainTransaction |
| `docs/04_01_Data_Model.md` | Full schema, relationships, enums, indexes |
| `docs/04_02_Database_Architecture.md` | Partitioning strategy, RANGE by created_at |
| `docs/05_01_Tokenomics_Proof_of_Growth.md` | Wallet balance model, lock_and_mint, slashing |
| `docs/03_05_Security_Architecture.md §3` | HardwareKey encryption, HKDF, Dual-Key Grace Period |

## Gotchas Not Obvious From Docs

1. **DID format confusion** — Tree `did` is `"SNET-XXXXXXXX"` (hardware UID), `peaq_did` is `"did:peaq:0x{40hex}"` (Web3). Don't mix them.
2. **HardwareKey key length** — 32 hex chars = AES-128 (Tree LoRa), 64 hex chars = AES-256 (Gateway CoAP). Conditional by `device_type` after ARCH.42. Domain separation: HKDF info `"silken-aes-128-lora-key"` vs `"silken-aes-256-device-key"`.
3. **Gateway online? is dynamic** — `last_seen_at >= (sleep_interval * 1.2).seconds.ago`. The threshold changes per gateway config, not a fixed constant.
4. **TelemetryLog has NO validations** — KENOSIS TITAN. Validation is in `TelemetryUnpackerService.valid_sensor_data?`. Adding model validations will break the hot path.
5. **Partition-aware queries required** — Both `TelemetryLog` and `BlockchainTransaction` are RANGE-partitioned. Always include `created_at` in lookups.
6. **Wallet locking** — `credit!` uses pessimistic lock. `lock_and_mint!` threshold is 10,000 points = 1 SCC. `carbon_sequestration_coefficient` varies by tree species.
7. **Dual-Key Grace Period** — `HardwareKey.previous_aes_key_hex` stays active until device confirms sync. Don't clear it prematurely.
