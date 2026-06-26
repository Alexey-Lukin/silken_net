---
name: web3-pipeline
description: "Use when working on the silken_net Web3 / on-chain surface — the 12-chain Proof-of-Growth pipeline (app/services/ + workers): SCC/SFC Solidity contracts, batchMint + Binary-Search poisoned-record isolation, the BlockchainTransaction AASM (incl. manual_review double-spend guard), minting guard-clauses (IoTeX / Chainlink / Hadron KYC), Dynamic Tax, slashing / penalty-factor de-correlation, Solana micro-rewards (Ed25519, batch payouts), DAO / Governor / Timelock, WEB3_STRICT_MODE. Routes to CLAUDE.md §11 + the 05_01..05_06 canon (solc One-Home = 05_03), does not restate. Examples: \"add a chain integration\", \"change the minting threshold\", \"why is a tx stuck in manual_review\", \"batchMint reverts on dry-run\", \"edit the slashing penalty\", \"Solana reward formula / batch payout\"."
---

# Web3 Pipeline

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `CLAUDE.md §11` | 12-chain overview, guard clauses, batchMint, Solana |
| `docs/05_01_Multichain_Architecture.md` | DePIN core/expansion stack, multichain rails, Solana, WEB3_STRICT_MODE (§10) |
| `docs/05_02_Proof_of_Growth_Pipeline.md` | Minting sequence, oracle callbacks, Dynamic Tax |
| `docs/05_03_Tokenomics_SCC_and_SFC.md` | Solidity contracts (SCC ERC-20, SFC), roles, batchMint |
| `docs/05_04_Ethereum_L1_State_Anchor.md` | Weekly SHA-256 state-root → Ethereum L1; `StateRootAnchor` + the DOUBLE-ANCHOR intent-marker pattern that ARCH.45 idempotency reuses; ARCH.13 EigenLayer-AVS cost-opt |
| `docs/05_05_Slashing_and_Risk_Policy.md` | Slashing/risk: cause A/B/C, positive-A evidence gate, convex penalty formula + `penalty_factor` de-correlation, insurance |
| `docs/05_06_Governance_and_DAO.md` | DAO Treasury, SilkenGovernor / Timelock, ProtocolParameters |
| `docs/03_05_Hardware_Symmetric_Crypto_and_Security.md` | Edge AES key management / HKDF; AES channel table (§6) |

## Gotchas Not Obvious From Docs

1. **WEB3_STRICT_MODE=true in production** — disables ALL stubs (Chainlink, Hadron). Missing ENV vars raise immediately. Dev/test uses stubs by default.
2. **manual_review state** — `BlockchainTransaction` AASM has a `manual_review` state = DOUBLE-SPEND GUARD. tx_hash exists but outcome unknown → funds locked until manual check. Don't auto-resolve.
3. **batchMint Binary Search** — on dry-run revert, `BlockchainMintingService` bisects the batch to isolate poisoned records (MAX_DEPTH=6). Don't bypass the dry-run step.
4. **Dynamic Tax** — 2% to DAO_TREASURY when `insurance_pool < 100,000 SCC`. Checked at mint time, not configurable.
5. **Solana reward formula** — `10,000 + growth_points * 100` lamports. ATA resolved via `getTokenAccountsByOwner`. Ed25519 signing (not secp256k1).
6. **Partition-aware BlockchainTransaction** — RANGE partitioned. Use `find_with_partition_pruning(id, created_at)`.
7. **Solana batch payouts [E.61]** — when `solana_batch_threshold_usdc` (SystemParameter) > 0, `SolanaMicroRewardWorker` accumulates rewards per-wallet in Kredis instead of sending per-event; hourly `SolanaBatchPayoutWorker` pays the lot via `transferChecked`. Threshold 0 → per-event (default). Rationale: `docs/05_01 §8`.
8. **Slashing fires ONLY on positive Cat-A evidence [SLASH-1 §3.2]** — irreversible `slash()` in `BlockchainBurningService` requires DIRECT tamper proof via `Slashing::CauseEvidence#positive_a?`; absent it → `:frozen` + Field Audit (the Cat-C indeterminate default §2), NOT a burn. Closed 3 false-slash holes (natural fire / drought-as-"fraud" / planned decommission) + the latent "daily never burned" bug. The Cat-A set is deliberately tamper-only — widening it (scoped-unmaintained / chainsaw signal) is a 👤 DAO/founder pre-mainnet call. Don't make slash fire on indirect/indeterminate signals. Canon: `docs/05_05 §3.2`.
9. **Slashing penalty de-correlation [SLASH-1 §6]** — cause-driven `penalty_factor` uplift in `BlockchainBurningService#calculate_penalty_factor` combines *correlated* comms-loss signals (no-ack, Streamr gap — shared "node offline" root-cause) via `max()`, NOT sum (summing double-counts one outage). Independent physical negligence (unmaintained critical alert) is additive. **INERT by default** behind `SystemParameter :slash_cause_uplift_enabled` (off until DAO-confirm) — don't expect live uplift. Cluster-wide blackout is diverted to Field Audit (`ContractHealthCheckService#flag_data_blackout!`), never burned. Canon: `docs/05_05 §3/§6`.
10. **Money-path crash-window idempotency [ARCH.45]** — the on-chain↔DB crash-window (broadcast succeeds, DB-write crashes) is a DISTINCT class from `retries_exhausted`→rollback (cron already self-heals stranded *pending* tx via `mint_batch_collector`/`insurance_payout_recovery`). Close it with the EthereumAnchor DOUBLE-ANCHOR pattern: a durable intent-marker `BlockchainTransaction` created BEFORE broadcast (Solana: signature computed pre-broadcast via `encode_base58`; burn: intent before `slash()`, AFTER the positive-A gate — not on `:frozen`), then a recent-window guard reconciles on-chain instead of blind re-pay/re-slash — `BlockchainTransaction.in_flight` (burn, 2h) / `unsettled_within(window)` (Solana payout + Etherisc, 7d; includes `:manual_review`; `created_at`-bound prunes RANGE partitions). On-chain `:not_found` is NOT authoritative (RPC lag/retention) → escalate `manual_review`, never auto-re-pay. Schedule `BlockchainConfirmationWorker` immediately after `mark_as_sent` (before any later DB write that could crash). Slash/payout success-rate SLO + `silkennet_sidekiq_dead_set_size` gauge observe it. Canon: `docs/04_02 §4/§10`.

## Common Tasks

- **Add new chain integration**: service in `app/services/`, worker, ENV vars, guard clause check → update `docs/05_02` + `CLAUDE.md §11`
- **Change minting threshold**: `Wallet#lock_and_mint!` (10k points = 1 SCC) → update `docs/05_01`
- **Edit / test a contract (`contracts/*.sol`)**: Foundry conventions + invariant gates → `CLAUDE.md §8`; spec/roles → `docs/05_03`. The CI audit gates (all **gating**) live in `.github/workflows/solidity_audit.yml`: Slither + Aderyn (static) · Halmos (symbolic, `test/symbolic/` `check_`) · Medusa + Foundry (fuzz/invariant, `test/medusa/` `property_` + `test/invariant/` `invariant_`). Tooling detail / gotchas → `reference_solidity_audit_stack` memory.
