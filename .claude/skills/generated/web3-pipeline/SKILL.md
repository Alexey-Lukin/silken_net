---
name: web3-pipeline
description: "Navigation + gotchas for 12-chain Web3 pipeline. Read SSOT docs first."
---

# Web3 Pipeline

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §11` | 12-chain overview, guard clauses, batchMint, Solana |
| `docs/05_01_Tokenomics_Proof_of_Growth.md` | SCC tokenomics, Proof of Growth, slashing |
| `docs/05_02_Pipeline_Sequence.md` | Minting sequence, oracle callbacks |
| `docs/06_01_Smart_Contracts.md` | Solidity contracts (SCC, SFC, DAO Treasury) |
| `docs/03_05_Security_Architecture.md §6` | WEB3_STRICT_MODE, key management |

## Gotchas Not Obvious From Docs

1. **WEB3_STRICT_MODE=true in production** — disables ALL stubs (Chainlink, Hadron). Missing ENV vars raise immediately. Dev/test uses stubs by default.
2. **manual_review state** — `BlockchainTransaction` AASM has a `manual_review` state = DOUBLE-SPEND GUARD. tx_hash exists but outcome unknown → funds locked until manual check. Don't auto-resolve.
3. **batchMint Binary Search** — on dry-run revert, `BlockchainMintingService` bisects the batch to isolate poisoned records (MAX_DEPTH=6). Don't bypass the dry-run step.
4. **Dynamic Tax** — 2% to DAO_TREASURY when `insurance_pool < 100,000 SCC`. Checked at mint time, not configurable.
5. **Solana reward formula** — `10,000 + growth_points * 100` lamports. ATA resolved via `getTokenAccountsByOwner`. Ed25519 signing (not secp256k1).
6. **Partition-aware BlockchainTransaction** — RANGE partitioned. Use `find_with_partition_pruning(id, created_at)`.

## Common Tasks

- **Add new chain integration**: service in `app/services/`, worker, ENV vars, guard clause check → update `docs/05_02` + `CLAUDE.md §11`
- **Change minting threshold**: `Wallet#lock_and_mint!` (10k points = 1 SCC) → update `docs/05_01`
