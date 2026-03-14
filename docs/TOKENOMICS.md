# Tokenomics — Gaia 2.0 Multichain Economy

## Dual Token System (Polygon — Primary Chain)

| Token | Full Name | Standard | Purpose |
|-------|-----------|----------|---------|
| **SCC** | Silken Carbon Coin | ERC-20 + AccessControl + Pausable | Utility token representing verified carbon sequestration |
| **SFC** | Silken Forest Coin | ERC-20 + Votes + Permit | Governance/DAO token with gasless approvals (EIP-712) |

## "Proof of Growth" Consensus (Trustless Verification)

Trees earn growth points by maintaining biological homeostasis. In Gaia 2.0, this process is verified through a three-layer trustless pipeline:

1. **Sensor data** collected by Soldier (impedance, temperature, acoustics, voltage)
2. **Lorenz attractor** computed on-device (mruby) and verified on server (Ruby, BigDecimal 18-digit precision)
3. **Z-value** compared against per-species thresholds (`TreeFamily.critical_z_min` / `critical_z_max`)
4. **peaq DID verification** — machine passport confirms this is a specific living organism (`did:peaq:0x...`)
5. **IoTeX W3bstream ZK-proof** — zero-knowledge proof confirms data originated from real silicon hardware
6. **Chainlink oracle dispatch** — decentralized oracle bridges verified proof to blockchain (guard clause: requires IoTeX verification)
7. **Hadron KYC check** — wallet's `hadron_kyc_status` must be `approved` before institutional minting (ERC-3643 compliance)
8. **Growth points** awarded if tree is in homeostasis (Z within critical bounds)
9. **Points accumulate** in the tree's `Wallet.balance`

## Minting Flow (Polygon)

```
Sensor Data → Lorenz Z → growth_points → Wallet.balance
                                              ↓
                              TokenomicsEvaluatorWorker (hourly)
                                              ↓
                              balance >= 10,000? → lock_and_mint!
                                              ↓
                              BlockchainTransaction (pending)
                                              ↓
                              MintCarbonCoinWorker → BlockchainMintingService
                                              ↓
                              Guard: verified_by_iotex? + oracle_status + hadron_kyc_status
                                              ↓
                              Polygon: mint(to_address, amount, tree_did)
                                              ↓
                              BlockchainConfirmationWorker → confirm! (tx_hash)
                                              ↓
                              The Graph: CarbonMintEvent indexed (GraphQL)
```

**Conversion rate:** 10,000 growth points = 1 SCC

**Energy budget impact:** At 44mV bio-potential input, a Soldier can transmit approximately 1 LoRa message per hour, yielding ~1 growth_point cycle per hour, ~24 points per day per tree.

## Parallel Financial Rails (Multichain)

### Solana — Micro-Rewards (Instant)

`SolanaMicroRewardWorker` → `Solana::MintingService`

- **Purpose:** Instant USDC micro-payments (0.01–0.1 USDC per telemetry packet) for tree owners
- **Speed:** Solana confirmation in ~400ms (vs Polygon ~2s)
- **Independence:** Operates in parallel with Polygon minting — no dependency
- **Network:** Devnet (development) → Mainnet (production)

### Celo — Community ReFi Rewards

`CeloRewardWorker` → `Celo::CommunityRewardService`

- **Purpose:** Regenerative Finance (ReFi) incentive for local communities
- **Trigger:** Cluster passes daily health check (`stress_index ≤ 0.2`)
- **Amount:** 5 cUSD per healthy cluster per day
- **Target:** Organization's registered cUSD wallet on Celo network
- **Network:** Alfajores (testnet) → Mainnet

### KlimaDAO — ESG Carbon Retirement

`KlimaRetirementWorker` → `KlimaDao::RetirementService`

- **Purpose:** Corporations retire SCC tokens via KlimaDAO to offset carbon footprint for ESG reporting
- **Flow:** Approve → Retire (two-step atomic transaction)
- **Effect:** Tokens moved to `esg_retired_balance` on wallet (irreversible)
- **Protection:** Pessimistic locking prevents double-spend

### Polygon Hadron — Institutional RWA Compliance

`HadronAssetRegistrationWorker` → `Polygon::HadronComplianceService`

- **Purpose:** KYC/KYB verification for institutional investors (ERC-3643 compliance)
- **Two flows:**
  1. `verify_investor!` — wallet KYC approval via Hadron Identity Platform
  2. `register_asset!` — forest plot registration as Real World Asset (RWA)
- **Guard:** `hadron_kyc_status == "approved"` required before SCC/SFC minting

## Slashing Protocol (Sovereign Justice)

Daily integrity audit of NaaS contracts with multichain consequences:

1. `DailyAggregationWorker` (01:00 UTC) triggers `InsightGeneratorService` → creates `AiInsight` per tree (includes AI Fraud Guard)
2. `ClusterHealthCheckWorker` (02:00 UTC) iterates active `NaasContract` records
3. `NaasContract#check_cluster_health!` counts trees with `stress_index >= 1.0`
4. If >20% of cluster trees are anomalous → `activate_slashing_protocol!`
5. Contract status → `:breached`
6. `BurnCarbonTokensWorker` → `BlockchainBurningService` → Polygon `slash(investor, amount)`
7. `EwsAlert` + `MaintenanceRecord` created for audit trail
8. `AuditLogWorker` → `FilecoinArchiveWorker` → permanent IPFS/Filecoin record

**Healthy cluster path:**
- `CeloRewardWorker` sends 5 cUSD to organization (ReFi community incentive)
- Optional: `KlimaRetirementWorker` for ESG carbon retirement

## NaaS Contract Lifecycle

```
Organization funds cluster → NaasContract (draft)
         ↓
Contract activated → Trees earn growth points → SCC minted
         ↓
Daily health checks pass → Contract remains active
         ↓
>20% trees anomalous → SLASHING PROTOCOL → Tokens burned, contract breached
```

## Parametric Insurance

Threshold-based automatic payouts for catastrophic events:

- **Trigger events:** `critical_fire`, `extreme_drought`, `insect_epidemic`
- **Threshold:** Configurable percentage of anomalous `AiInsight` records
- **Payout flow:** `ParametricInsurance#evaluate_daily_health!` → `InsurancePayoutWorker` → `BlockchainTransaction`

## Afterlife Economy — Puro.earth Biochar Integration

When a tree dies (biological death or catastrophic event), its biomass retains economic value through Biochar carbon removal credits (CORCs) on the [Puro.earth](https://puro.earth) registry.

### Flow

```
Tree dies → Forester extracts dead wood → MaintenanceRecord (biomass_extraction)
         ↓
EcosystemHealingWorker → Tree status → :deceased
         ↓
PuroEarthPassportWorker → D-MRV "Biomass Passport" generated
         ↓
Payload: { tree_did, biomass_yield_kg, extraction_date, gps_coordinates, lifetime_telemetry_hash }
         ↓
Blockchain anchoring → biomass_passport_tx_hash stored on MaintenanceRecord
         ↓
Puro.earth registry → Biochar CORC issuance (future integration)
```

### D-MRV Biomass Passport

The Digital Measurement, Reporting and Verification (D-MRV) passport provides tamper-proof provenance for extracted biomass:

| Field | Source | Purpose |
|-------|--------|---------|
| `tree_did` | Tree.did (SNET-XXXXXXXX) | Unique hardware identity of the source tree |
| `biomass_yield_kg` | MaintenanceRecord | Weight of extracted dead wood |
| `extraction_date` | MaintenanceRecord.performed_at | Timestamp of physical extraction |
| `gps_coordinates` | MaintenanceRecord or Tree | Geographic proof of origin |
| `lifetime_telemetry_hash` | SHA-256 of telemetry history | Tamper-proof link to tree's sensor data |

### Economic Impact

- Dead trees continue generating value through Biochar CORCs instead of being waste
- Each CORC represents verified carbon removal (Puro Standard methodology)
- Lifetime telemetry hash ensures the biomass originated from a monitored, verified tree
- GPS coordinates prevent double-counting across forest plots

## Smart Contracts

### SilkenCarbonCoin.sol (Polygon)

- ERC-20 with `AccessControl` and `Pausable`
- `MINTER_ROLE` - Backend oracle mints SCC for verified growth
- `SLASHER_ROLE` - Backend oracle burns SCC when contracts are breached
- `mint(address to, uint256 amount, string treeDid)` - Mints tokens with tree DID attestation
- `batchMint(address[] to, uint256[] amounts, string[] treeDids)` - Gas-efficient batch minting (≤200 per call)
- `slash(address investor, uint256 amount)` - Burns investor tokens on contract breach

### SilkenForestCoin.sol (Polygon)

- ERC-20 with `Votes` and `Permit` extensions
- Gasless approvals via EIP-712 signatures
- DAO governance voting power
- Used for protocol-level decisions (parameter changes, new cluster approvals)

## State Anchoring (Ethereum L1)

`EthereumAnchorWorker` (weekly, Monday 03:00 UTC) → `Ethereum::StateAnchorService`

Every week, the entire state of the Gaia 2.0 economy is compressed into a single 32-byte SHA-256 hash and permanently written to Ethereum Mainnet:

```
state_root = SHA256(total_scc_supply + chain_hash + timestamp)
```

This provides rollup-style finality: even if Polygon suffers a catastrophic failure, the Ethereum L1 anchor proves the state at every weekly checkpoint. Gas-efficient: only 1 `bytes32` write per week.

## The Graph — Carbon Index (Subgraph)

The Graph subgraph (defined in `subgraph/schema.graphql`) indexes every `CarbonMinted` event on Polygon, creating a queryable GraphQL API for global carbon statistics:

```graphql
# subgraph/schema.graphql
type CarbonMintEvent @entity {
  id: ID!
  to: Bytes!
  amount: BigInt!
  treeDid: String!
  timestamp: BigInt!
  blockNumber: BigInt!
  transactionHash: Bytes!
}
```

`TheGraph::QueryService` fetches `total_carbon_minted` for dashboards and third-party integrations.
