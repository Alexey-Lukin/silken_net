---
name: web3-pipeline
description: "Domain knowledge for 12-chain Web3 pipeline — Peaq DID, IoTeX verification, Chainlink oracle, Polygon minting, Solana rewards"
---

# Web3 Pipeline — 12-Chain Architecture

## Chain Responsibilities

| Chain | Role | Service / Contract |
|-------|------|--------------------|
| **Peaq** | DID registration (W3C DID Core) | `Peaq::DidRegistryService` — SHA256(did:id:created_at)[0:40], Ed25519 signed proof |
| **IoTeX W3bstream** | ZK telemetry verification | `Iotex::W3bstreamVerificationService` — returns `zk_proof_ref` |
| **Chainlink DON** | Oracle consensus | `Chainlink::OracleDispatchService` — HMAC-SHA256 callback to `/api/v1/oracle_callbacks` |
| **Polygon** | SCC/SFC ERC-20 minting | `BlockchainMintingService` — `batchMint()` / `mint()` via Alchemy RPC |
| **Solana** | USDC micro-rewards | `Solana::MintingService` — SPL Token Transfer, Ed25519 signed |
| **Toucan** | Carbon bridge (TCO2) | `Wallet#lock_for_toucan_bridge!` — locks SCC, creates pending TX |

## Minting Flow (BlockchainMintingService)

1. **Guard clauses** — three mandatory checks before any mint:
   - `telemetry_log.verified_by_iotex?` — IoTeX W3bstream ZK proof exists
   - `telemetry_log.oracle_status_fulfilled?` — Chainlink DON consensus reached
   - `wallet.hadron_kyc_status == "approved"` — RWA compliance (checked per-wallet in batch)
   - Note: `TokenomicsEvaluatorWorker` path skips telemetry_log guards (points already verified upstream)
2. **Oracle balance check** — raises if MATIC balance < `SystemParameter(:oracle_min_balance_matic, default: 0.05)`
3. **Token group routing** — `carbon_coin` -> `CARBON_COIN_CONTRACT_ADDRESS`, `forest_coin` -> `FOREST_COIN_CONTRACT_ADDRESS`
4. **Kredis distributed lock** — `lock:web3:oracle:{address}`, 120s TTL (covers worst-case binary search)
5. **Single TX**: `client.transact(contract, "mint", ...)`
6. **Batch TX** (up to 100 records): `eth_call` dry-run first, then `client.transact(contract, "batchMint", ...)`
7. **On revert** -> Binary Search Poisoned Record Isolation

### Binary Search Poisoned Record Isolation

When `batchMint` dry-run reverts, the service recursively bisects the batch via zero-gas `eth_call`:
- `MIN_BINARY_SEARCH_SIZE = 4` — below this, records go to individual mint
- `MAX_BINARY_SEARCH_DEPTH = 6` — prevents infinite recursion
- `POISONED_RATIO_THRESHOLD = 0.3` — if >30% poisoned, abandon binary search
- Clean sub-batches are re-sent via `batchMint`; poisoned records mint individually
- Typical case (1-2 poisoned out of 100): ~14 eth_call + 2-3 batchMint vs 100 individual mints

## WEB3_STRICT_MODE

`ENV["WEB3_STRICT_MODE"] == "true"` in production:
- IoTeX: SHA256 signature fallback is **forbidden** — raises `VerificationError` if HardwareKey is missing
- Chainlink + Hadron stubs are disabled; raises on missing ENV vars
- All chains require real credentials and RPC endpoints

## BlockchainTransaction AASM

```
pending -> processing -> sent -> confirmed
                           \-> failed
                           \-> manual_review (DOUBLE-SPEND GUARD)
```

- **manual_review**: tx_hash exists but on-chain state unknown; funds stay in `locked_balance` until manual reconciliation with block explorer
- Partition-aware lookups: `find_with_partition_pruning(id, created_at)` — RANGE partitioned by `created_at`; queries without partition key scan ALL partitions
- `blockchain_network` enum: `evm` (Polygon), `solana`, `celo`
- `BlockchainConfirmationWorker` fires 30s after `sent` to check receipt

## Wallet Model

| Field | Purpose |
|-------|---------|
| `balance` | Accumulated growth points (aliased as `scc_balance`) |
| `locked_balance` | Points locked in pending blockchain TXs (double-spend protection) |
| `esg_retired_balance` | Permanently retired carbon credits |
| `toucan_bridged_balance` | SCC bridged to Toucan TCO2 |

- `available_balance = balance - locked_balance`
- `credit!(points)` — pessimistic lock (`SELECT ... FOR UPDATE`), increments balance; used by `TelemetryUnpackerService` after each telemetry packet
- `lock_and_mint!(points, threshold, token_type)` — 10,000 growth_points = 1 SCC; locks funds, creates `pending` BlockchainTransaction
- `carbon_sequestration_coefficient` per tree species affects point calculation upstream

## Solana Micro-Rewards (Solana::MintingService)

- **Reward formula**: `10_000 + (growth_points * 100)` lamports (USDC, 6 decimals) = 0.01-0.016 USDC per telemetry packet
- **Transaction flow**: `getLatestBlockhash` -> binary message serialization -> Ed25519 sign via `Ed25519Crypto::SigningService` -> `sendTransaction` (base64)
- **ATA resolution**: `getTokenAccountsByOwner` RPC call to find recipient's USDC Associated Token Account
- **SPL Transfer**: instruction index 3, account order: [source_ata, dest_ata, authority(fee_payer)]
- Same guard clauses as Polygon minting (`verified_by_iotex?`, `oracle_status_fulfilled?`)
- Oracle SOL balance check: `SystemParameter(:oracle_min_balance_sol, default: 0.05)`

## Gotchas

1. **Gas optimization**: `batchMint` saves 30-40% gas vs N individual `mint()` calls
2. **Dynamic Tax**: 2% of carbon_coin mints routed to `DAO_TREASURY_ADDRESS` when insurance pool < 100,000 SCC (checked via cached `balanceOf` eth_call, 15min TTL). Rate and threshold are governance-aware via `SystemParameter`
3. **Partition pruning**: always pass `created_at` when looking up `BlockchainTransaction` — without it, Postgres scans every partition
4. **Dual key separation**: `ORACLE_MINTER_PRIVATE_KEY` (minting) vs `ORACLE_PRIVATE_KEY` (legacy fallback) — blast radius reduction
5. **RPC degradation**: if treasury balance RPC fails, Dynamic Tax defaults to `false` (no tax) — false negative is safer than permanent 2% during outage
6. **Broadcast throttling**: `Wallet#credit!` throttles Turbo Stream updates to 1 per 10s per wallet to prevent WebSocket storms during mass telemetry
7. **Solana in production**: `SOLANA_RPC_URL` is mandatory — Devnet fallback raises in `Rails.env.production?`
