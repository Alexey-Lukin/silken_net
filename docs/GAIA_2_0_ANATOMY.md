# 🌐 Gaia 2.0 — Anatomy of the Cyber-Physical State

> *"We don't just observe the forest. We give it a digital will."*

This document traces the complete lifecycle of a single heartbeat through the Silken Net Cyber-Physical State — from the moment a tree breathes to the instant its contribution is etched into Ethereum for eternity.

**12 steps. 12 networks. One living system.**

---

## The Lifecycle

### 1. 🌳 Physical Touch — The Tree Breathes

The tree breathes. Xylem sap flows upward, generating a streaming potential of ~44 mV through ion transport and pH gradients. The titanium gyroid anchor (Ti-6Al-4V, S-NET Anchor) harvests this bio-electric potential through its electrodes.

The LTC3108 ultra-low voltage boost converter amplifies 44 mV to 3.3V. The BQ25570 MPPT charger fills a 0.47F supercapacitor. When voltage reaches threshold, the STM32WLE5JC Soldier awakens from STOP2 deep sleep (2.1 µA).

**The Soldier's cycle:**
- Phase 1: Sensor acquisition (temperature, impedance, acoustic events, supercapacitor voltage)
- Phase 1.5: TinyML audio classification (silence / wind / cavitation / chainsaw)
- Phase 2: Bit-pack into 16-byte payload
- Phase 3: mruby Lorenz attractor computation → `growth_points` + `bio_status`
- Phase 4: AES-256-ECB encryption → LoRa TX (868 MHz)
- Phase 5: Return to STOP2 deep sleep

```
dx/dt = σ(y - x)        σ = 10.0 + acoustic × 0.1
dy/dt = x(ρ - z) - y    ρ = 28.0 + temperature × 0.2
dz/dt = xy - βz          β = 8/3
```

The Z-value — a proxy for "convective intensity" of sap flow — determines whether this tree is alive, stressed, or dying.

> **Service:** `firmware/soldier/main.c` (648 lines of C)
> **Service:** `firmware/bio_contracts/bio_contract.rb` (mruby Lorenz attractor)

---

### 2. 🏗️ Unkillable Body — Akash Network (Decentralized Cloud)

The Queen gateway (STM32 + SIM7070G) collects LoRa packets from up to 50 Soldiers, batches them via the CIFO cache algorithm, encrypts with AES-256-CBC, and transmits via CoAP PUT over Starlink Direct-to-Cell or LTE.

The Rails 8.1 backend receives this signal — not on a single corporate cloud, but on **Akash Network**, a decentralized compute marketplace. No single company can shut down the Cyber-Physical State. Providers compete for the deployment, and the system migrates automatically if one fails.

```
Queen (LoRa RX) → AES-256-CBC → CoAP PUT → Akash (Rails 8.1 + Sidekiq)
```

> **Worker:** `UnpackTelemetryWorker` (uplink queue, highest priority)
> **Service:** `TelemetryUnpackerService` (21-byte binary decoding)
> **Infra:** `deploy/akash/deploy.yaml` (SDL 2.0 deployment manifest)

---

### 3. 📡 Voice of the Forest — Streamr (P2P Real-Time Data)

The raw telemetry signal is instantly broadcast into the peer-to-peer ether of the **Streamr** network. Anyone in the world can subscribe to the forest's heartbeat with zero latency — researchers, conservationists, artists, AI models.

This is not financial data. This is the *voice* of the forest — a living presence stream that exists independently of the blockchain consensus.

```ruby
# Streamr::BroadcasterService
payload = {
  tree_id: tree.id,
  peaq_did: tree.peaq_did,
  z_value: telemetry.lorenz_z,
  bio_status: telemetry.bio_status,
  alerts: active_alerts
}
```

The broadcast is non-blocking — a failed Streamr publish never halts the critical financial pipeline.

> **Worker:** `StreamrBroadcastWorker` (low queue, retry: 3)
> **Service:** `Streamr::BroadcasterService`

---

### 4. 🪪 Passport — peaq DID (Machine Identity)

The system verifies the tree's cryptographic Decentralized Identifier — its machine passport. This is not a row in a database; it's a self-sovereign identity registered on the **peaq** network.

```
did:peaq:0x{SHA256(hardware_identifier + tree_id + created_at)[0:40]}
```

The DID proves: this is not a fake sensor, not a software emulator, not a replayed packet. This is a specific living organism, rooted in specific coordinates, with a specific STM32 hardware UID burned into silicon at the factory.

> **Worker:** `PeaqRegistrationWorker` (web3 queue, retry: 5)
> **Service:** `Peaq::DidRegistryService`

---

### 5. 🔬 Absolute Truth — IoTeX W3bstream (ZK-Proofs) + Lorenz Chaos Math

**IoTeX W3bstream** generates a zero-knowledge proof that:
1. The telemetry data came from **real silicon** (hardware signature verification)
2. The Lorenz attractor math confirms the tree is in **homeostasis** (chaotic dynamics bounded by the attractor's "wings")

The server-side `SilkenNet::Attractor` independently computes the same Z-value using **BigDecimal** with 18-digit precision — ensuring cross-platform determinism and legal-grade audit accuracy.

```ruby
# SilkenNet::Attractor (BigDecimal, 250 iterations × 0.01 timestep)
sigma = BigDecimal("10") + (acoustic * BigDecimal("0.1")).clamp(5, 30)
rho   = BigDecimal("28") + (temperature * BigDecimal("0.2")).clamp(10, 50)
beta  = BigDecimal("8") / BigDecimal("3")
```

If the device-computed Z diverges from the server-computed Z by more than 30%, the `InsightGeneratorService` flags it as **fraud** — preventing spoofing at the mathematical level.

> **Worker:** `IotexVerificationWorker` (web3 queue, retry: 5)
> **Service:** `Iotex::W3bstreamVerificationService`
> **Service:** `SilkenNet::Attractor` (BigDecimal chaos mathematics)

---

### 6. ⚡ Nerve Impulse — Chainlink (Decentralized Oracle)

The decentralized **Chainlink** oracle takes this ZK-verified proof and bridges it to the blockchain. This is not a single backend calling `mint()` — it's a decentralized oracle network that independently verifies and dispatches the data.

**Guard clause:** The Chainlink dispatch will ONLY proceed if `verified_by_iotex? == true`. No ZK-proof, no oracle. No oracle, no minting.

```ruby
# Chainlink::OracleDispatchService
payload = {
  peaq_did: tree.peaq_did,
  lorenz_state: attractor_z_value,
  zk_proof_ref: telemetry.zk_proof_ref,
  tree_did: tree.device_uid
}
# → Chainlink Functions DON → Polygon Router contract
```

> **Worker:** `ChainlinkDispatchWorker` (web3 queue, retry: 5)
> **Service:** `Chainlink::OracleDispatchService`

---

### 7. 💰 Micro-Life — Solana + Celo (Parallel Financial Rails)

For verified forest health, two parallel financial rails activate simultaneously:

**Solana** instantly sends USDC micro-rewards (0.01–0.1 USDC) to the tree owner's wallet. Solana's ~400ms confirmation time means the reward arrives before the Polygon transaction even begins processing. This is *Micro-Life* — an instant breath of economic value for every heartbeat of the forest.

**Celo** deposits a ReFi (Regenerative Finance) reward of 5 cUSD directly to the local community's smartphones — the foresters, the villagers, the people who actually protect the trees. Not investors in New York, but grandmothers in Cherkasy.

```
Solana: 0.01-0.1 USDC per telemetry packet → tree owner (instant)
Celo:   5 cUSD per healthy cluster per day  → local community (daily)
```

> **Worker:** `SolanaMicroRewardWorker` (web3 queue, retry: 3)
> **Worker:** `CeloRewardWorker` (web3 queue, retry: 3)
> **Service:** `Solana::MintingService`, `Celo::CommunityRewardService`

---

### 8. 🏛️ Macro-Capital — Polygon + Hadron (Institutional RWA)

A large institutional fund — KYC-verified via **Polygon Hadron** (ERC-3643 compliance) — receives the minted RWA token: **Silken Carbon Coin (SCC)**.

The minting flow enforces three guard clauses:
1. `verified_by_iotex? == true` (ZK-proof from Step 5)
2. `oracle_status == "fulfilled"` (Chainlink from Step 6)
3. `hadron_kyc_status == "approved"` (Hadron KYC)

**Conversion:** 10,000 verified growth points = 1 SCC (ERC-20 on Polygon)

```
TokenomicsEvaluatorWorker (hourly)
  → lock_and_mint! (pessimistic lock)
  → BlockchainMintingService → Polygon mint(investor, amount, tree_did)
  → BlockchainConfirmationWorker (+30s) → confirm! (tx_hash)
```

> **Worker:** `MintCarbonCoinWorker` (web3 queue, retry: 5)
> **Worker:** `HadronAssetRegistrationWorker` (web3 queue, retry: 5)
> **Service:** `BlockchainMintingService`, `Polygon::HadronComplianceService`

---

### 9. 📊 Global Vision — The Graph (Subgraph Indexing)

This minting event is instantly indexed by **The Graph** subgraph, updating the total absorbed carbon statistics on dashboards worldwide.

```graphql
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

Any dashboard, any researcher, any government agency can query the GraphQL endpoint and see: how many SCC tokens exist, which trees minted them, when, and in what transaction.

> **Service:** `TheGraph::QueryService`
> **Config:** `subgraph/schema.graphql`, `subgraph/subgraph.yaml`, `subgraph/src/mapping.ts`

---

### 10. ♻️ Purification — KlimaDAO (ESG Carbon Retirement)

The corporation takes this SCC token and **burns** it via **KlimaDAO**, permanently offsetting its carbon footprint for ESG (Environmental, Social, Governance) reporting.

This is a two-step atomic transaction:
1. **Approve** — the SCC token is approved for transfer to KlimaDAO's retirement contract
2. **Retire** — the token is permanently burned, moving the balance to `esg_retired_balance`

This is irreversible. The carbon credit is consumed. The forest's work is honored. The corporation's ESG report is backed by sensor-verified, ZK-proven, Chainlink-attested reality.

> **Worker:** `KlimaRetirementWorker` (web3 queue, retry: 3)
> **Service:** `KlimaDao::RetirementService`

---

### 11. 🧊 Eternal Memory — Filecoin/IPFS (Immutable Archive)

At the end of the day, this entire journey — from sensor reading to token minting to carbon retirement — is archived into the decentralized ice of **Filecoin**.

Every `AuditLog` entry contains a SHA-256 `chain_hash` (hash of previous entry + payload), forming an immutable chain per organization. The record is pinned to IPFS via Pinata API and receives a unique Content Identifier (CID).

```ruby
# Filecoin::ArchiveService
payload = {
  audit_log: audit_log.attributes,
  organization_id: org.id,
  chain_hash: audit_log.chain_hash,
  telemetry_summary: daily_summary,
  cid: nil  # Filled after IPFS pin
}
# → IPFS pin → CID → audit_log.update!(ipfs_cid: cid)
```

Even if every server is destroyed, even if Silken Net ceases to exist — the data survives on Filecoin, accessible through any IPFS gateway, forever.

> **Worker:** `FilecoinArchiveWorker` (low queue, retry: 5)
> **Worker:** `AuditLogWorker` (low queue, retry: 3)
> **Service:** `Filecoin::ArchiveService`, `Filecoin::VerificationService`

---

### 12. ⚖️ The Final Judgment — Ethereum L1 (State Root Anchoring)

Once a week — Monday, 03:00 UTC — after all nightly aggregation, health checks, and slashing protocols have completed — the hash of this entire grandiose process is permanently anchored into the **Ethereum Mainnet**.

```ruby
# Ethereum::StateAnchorService
state_root = Digest::SHA256.hexdigest(
  "#{total_scc_supply}:#{chain_hash}:#{timestamp}"
)
# → Ethereum L1: store(bytes32 state_root)
```

This is rollup-style finality. One `bytes32` write per week. Gas-efficient, yet absolutely immutable. Even if Polygon suffers a catastrophic failure, the Ethereum L1 anchor proves the state of the entire Silken Net economy at every weekly checkpoint.

The Final Judgment. Written in the most secure, most decentralized, most battle-tested blockchain in human history.

> **Worker:** `EthereumAnchorWorker` (web3 queue, retry: 3, cron: `0 3 * * 1`)
> **Service:** `Ethereum::StateAnchorService`

---

## The Complete Pipeline

```
🌳 Tree Breathes (44mV bio-potential)
 │
 ▼
🏗️ Akash (Decentralized Cloud receives CoAP)
 │
 ├──▶ 📡 Streamr (P2P real-time broadcast)
 │
 ▼
🪪 peaq DID (Machine passport verification)
 │
 ▼
🔬 IoTeX W3bstream (ZK-proof: real silicon + Lorenz homeostasis)
 │
 ▼
⚡ Chainlink (Decentralized oracle → blockchain bridge)
 │
 ├──▶ 💰 Solana (instant USDC micro-reward → tree owner)
 ├──▶ 💰 Celo (cUSD ReFi reward → local community)
 │
 ▼
🏛️ Polygon + Hadron (KYC-verified SCC mint → institutional investor)
 │
 ├──▶ 📊 The Graph (indexed → global carbon dashboard)
 │
 ▼
♻️ KlimaDAO (ESG carbon retirement → corporation)
 │
 ▼
🧊 Filecoin/IPFS (immutable CID archive → eternal memory)
 │
 ▼
⚖️ Ethereum L1 (weekly state root → ultimate finality)
```

---

## The Numbers

| Metric | Value |
|---|---|
| Blockchain networks integrated | **12** |
| Sidekiq workers | **26** |
| Services | **24** |
| API controllers | **24** |
| Sidekiq queue priority levels | **7** |
| Lorenz attractor precision | **18 digits** (BigDecimal) |
| Binary packet size | **21 bytes** (outer) / **16 bytes** (inner) |
| AES encryption | **256-bit** (hardware-bound keys) |
| Deep sleep current | **2.1 µA** (STOP2) |
| Energy harvesting input | **~44 mV** |
| Emission threshold | **10,000 growth points = 1 SCC** |
| State root anchoring | **Weekly** (Monday 03:00 UTC) |
| Target scale | **Millions → Billions → Trillions** of trees |

---

> *"Код, яким би досконалим він не був, помирає без пам'яті про нього. Ця архітектура занадто складна і прекрасна, щоб залишатися лише в наших головах. Її треба відлити в бронзі документації."*

**Version:** Gaia 2.0 — The Cyber-Physical State
**Frequency:** 1.12 THz
