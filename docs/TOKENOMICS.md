# Tokenomics

## Dual Token System

| Token | Full Name | Standard | Purpose |
|-------|-----------|----------|---------|
| **SCC** | Silken Carbon Coin | ERC-20 + AccessControl + Pausable | Utility token representing verified carbon sequestration |
| **SFC** | Silken Forest Coin | ERC-20 + Votes + Permit | Governance/DAO token with gasless approvals (EIP-712) |

## "Proof of Growth" Consensus

Trees earn growth points by maintaining biological homeostasis. The Lorenz attractor Z-value serves as a proxy for metabolic health:

1. **Sensor data** collected by Soldier (impedance, temperature, acoustics, voltage)
2. **Lorenz attractor** computed on-device (mruby) and verified on server (Ruby)
3. **Z-value** compared against per-species thresholds (`TreeFamily.critical_z_min` / `critical_z_max`)
4. **Growth points** awarded if tree is in homeostasis (Z within critical bounds)
5. **Points accumulate** in the tree's `Wallet.balance`

## Minting Flow

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
                              Polygon: mint(to_address, amount, tree_did)
                                              ↓
                              BlockchainTransaction (confirmed, tx_hash)
```

**Conversion rate:** 10,000 growth points = 1 SCC

**Energy budget impact:** At 44mV bio-potential input, a Soldier can transmit approximately 1 LoRa message per hour, yielding ~1 growth_point cycle per hour, ~24 points per day per tree.

## Slashing Protocol

Daily integrity audit of NaaS contracts:

1. `DailyAggregationWorker` triggers `InsightGeneratorService` → creates `AiInsight` per tree
2. `ClusterHealthCheckWorker` iterates active `NaasContract` records
3. `NaasContract#check_cluster_health!` counts trees with `stress_index >= 1.0`
4. If >20% of cluster trees are anomalous → `activate_slashing_protocol!`
5. Contract status → `:breached`
6. `BurnCarbonTokensWorker` → `BlockchainBurningService` → Polygon `slash(investor, amount)`

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

## Smart Contracts

### SilkenCarbonCoin.sol

- ERC-20 with `AccessControl` and `Pausable`
- `MINTER_ROLE` - Backend oracle mints SCC for verified growth
- `SLASHER_ROLE` - Backend oracle burns SCC when contracts are breached
- `mint(address to, uint256 amount, string treeDid)` - Mints tokens with tree DID attestation
- `slash(address investor, uint256 amount)` - Burns investor tokens on contract breach

### SilkenForestCoin.sol

- ERC-20 with `Votes` and `Permit` extensions
- Gasless approvals via EIP-712 signatures
- DAO governance voting power
- Used for protocol-level decisions (parameter changes, new cluster approvals)
