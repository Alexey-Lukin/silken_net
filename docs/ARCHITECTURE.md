# System Architecture — Gaia 2.0 (The Cyber-Physical State)

## System Layers

```
┌─────────────────────────────────────────────────────────────────────────┐
│  FINALITY (Ethereum L1)                                                 │
│  Weekly State Root Anchoring — 32-byte SHA-256 hash (rollup finality)   │
├─────────────────────────────────────────────────────────────────────────┤
│  BLOCKCHAIN (Polygon EVM — Primary Chain)                               │
│  SilkenCarbonCoin.sol / SilkenForestCoin.sol (ERC-20)                   │
│  Polygon Hadron (KYC/ERC-3643) · Chainlink Functions DON                │
├─────────────────────────────────────────────────────────────────────────┤
│  MULTICHAIN (Parallel Financial Rails)                                  │
│  Solana (micro-rewards) · Celo (cUSD ReFi) · KlimaDAO (ESG retirement) │
├─────────────────────────────────────────────────────────────────────────┤
│  VERIFICATION (Trustless Proofs)                                        │
│  IoTeX W3bstream (ZK-proofs) · peaq (Machine DID) · The Graph (Index)   │
├─────────────────────────────────────────────────────────────────────────┤
│  DATA (Decentralized Streams & Storage)                                 │
│  Streamr (P2P real-time) · Filecoin/IPFS (immutable archive)            │
├─────────────────────────────────────────────────────────────────────────┤
│  BACKEND (Rails 8.1 + Sidekiq + PostgreSQL)                             │
│  24 API Controllers · 29 Services · 26 Workers                          │
├─────────────────────────────────────────────────────────────────────────┤
│  INFRA (Akash Network — Decentralized Cloud)                            │
│  Containerized Rails deployment on Akash marketplace                    │
├─────────────────────────────────────────────────────────────────────────┤
│  NETWORK (LoRa 868 MHz + CoAP/UDP over LTE/Starlink)                    │
├─────────────────────────────────────────────────────────────────────────┤
│  EDGE (STM32WLE5JC Soldiers + Queens)                                   │
│  TinyML · mruby VM · AES-256 · Mesh TTL routing                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Multichain Integration Matrix

| Chain / Protocol | Purpose | Service | Worker | Critical Path |
|---|---|---|---|---|
| **Polygon EVM** | SCC/SFC minting, slashing, price oracle | `BlockchainMintingService`, `BlockchainBurningService`, `ChainAuditService`, `PriceOracleService` | `MintCarbonCoinWorker`, `BurnCarbonTokensWorker`, `BlockchainConfirmationWorker` | ✅ Yes |
| **Polygon Hadron** | KYC/KYB compliance, RWA (ERC-3643) | `Polygon::HadronComplianceService` | `HadronAssetRegistrationWorker` | ✅ Yes |
| **Ethereum L1** | Weekly state root anchoring (finality) | `Ethereum::StateAnchorService` | `EthereumAnchorWorker` | ✅ Yes |
| **Chainlink** | Decentralized oracle (guard clause before mint) | `Chainlink::OracleDispatchService` | `ChainlinkDispatchWorker` | ✅ Yes |
| **IoTeX W3bstream** | ZK-proof generation (hardware verification) | `Iotex::W3bstreamVerificationService` | `IotexVerificationWorker` | ✅ Yes |
| **peaq** | Machine DID (self-sovereign tree identity) | `Peaq::DidRegistryService` | `PeaqRegistrationWorker` | ✅ Yes |
| **Solana** | Micro-rewards (parallel USDC payments) | `Solana::MintingService` | `SolanaMicroRewardWorker` | Optional |
| **Celo** | Community ReFi rewards (cUSD) | `Celo::CommunityRewardService` | `CeloRewardWorker` | Optional |
| **KlimaDAO** | ESG carbon credit retirement | `KlimaDao::RetirementService` | `KlimaRetirementWorker` | Optional |
| **Streamr** | P2P real-time telemetry broadcast | `Streamr::BroadcasterService` | `StreamrBroadcastWorker` | Optional |
| **Filecoin/IPFS** | Immutable audit log archive (CID) | `Filecoin::ArchiveService`, `Filecoin::VerificationService` | `FilecoinArchiveWorker` | ✅ Yes |
| **The Graph** | Subgraph indexing (GraphQL) | `TheGraph::QueryService` | — | Read-only |
| **Akash Network** | Decentralized cloud deployment | — (infrastructure) | — | Infrastructure |

## Data Flow (Gaia 2.0 Pipeline)

1. **Sensor Acquisition** — Soldier reads impedance (EIS), temperature, acoustic events (piezo), and supercapacitor voltage.
2. **TinyML Audio Classification** — On-device neural network classifies audio: silence / wind / cavitation / chainsaw.
3. **mruby Bio-Contract** — Lorenz attractor computation on-device produces `growth_points` and `bio_status`.
4. **Bit-Packing & Encryption** — 16-byte payload packed, AES-256-ECB encrypted, transmitted via LoRa.
5. **Queen Reception** — Queen decrypts, caches via CIFO (Closest In, Farthest Out), batches up to 50 trees.
6. **CoAP Uplink** — Queen sends binary batch via CoAP PUT over LTE/Starlink to Rails backend (Akash or GCP).
7. **Backend Unpacking** — `UnpackTelemetryWorker` → `TelemetryUnpackerService` decodes, normalizes via `DeviceCalibration`, stores `TelemetryLog`.
8. **Streamr Broadcast** — `StreamrBroadcastWorker` publishes raw telemetry to Streamr P2P network (non-blocking, real-time forest pulse).
9. **peaq DID Verification** — `Peaq::DidRegistryService` verifies the tree's cryptographic machine passport (`did:peaq:0x...`).
10. **Server-Side Lorenz Verification** — `SilkenNet::Attractor.calculate_z` (BigDecimal, 18-digit precision) verifies device-computed Z-value (dual computation integrity).
11. **IoTeX ZK-Proof** — `IotexVerificationWorker` → `Iotex::W3bstreamVerificationService` generates a zero-knowledge proof confirming data origin from real silicon.
12. **Chainlink Oracle Dispatch** — `ChainlinkDispatchWorker` → `Chainlink::OracleDispatchService` bridges the ZK-verified proof to the blockchain via Chainlink Functions DON (guard clause: requires IoTeX verification first).
13. **Alert Dispatch** — `AlertDispatchService` checks 5 threat categories → `EmergencyResponseService` dispatches actuators (water valves, fire sirens, seismic beacons).
14. **Tokenomics Evaluation** — `TokenomicsEvaluatorWorker` (hourly): 10,000 growth_points = 1 SCC → `MintCarbonCoinWorker` → `BlockchainMintingService` → Polygon (Hadron KYC guard).
15. **Parallel Rewards** — `SolanaMicroRewardWorker` sends instant USDC micro-payments on Solana; `CeloRewardWorker` deposits cUSD community rewards on Celo.
16. **The Graph Indexing** — Every SCC mint event is indexed by The Graph subgraph, updating global carbon statistics via GraphQL.
17. **Daily Aggregation** — `DailyAggregationWorker` → `InsightGeneratorService` → `ClusterHealthCheckWorker` → Slashing Protocol (if >20% trees anomalous) or `CeloRewardWorker` (if cluster healthy).
18. **KlimaDAO Retirement** — `KlimaRetirementWorker` retires SCC tokens via KlimaDAO for ESG carbon offset reporting.
19. **Filecoin Archive** — `FilecoinArchiveWorker` archives AuditLog to IPFS/Filecoin — immutable, decentralized, forever.
20. **Ethereum L1 Anchor** — `EthereumAnchorWorker` (weekly, Monday 03:00 UTC): SHA-256 state root (total_scc + chain_hash + timestamp) anchored to Ethereum Mainnet for ultimate finality.

## Domain Model

### Core Entities (24 models)

```
Organization ──has_many──→ Users
             ──has_many──→ NaasContracts
             ──has_many──→ Clusters
             ──has_many──→ ParametricInsurances

Cluster ──has_many──→ Trees
        ──has_many──→ Gateways
        ──has_many──→ EwsAlerts
        ──has_many──→ NaasContracts
        ──has_many──→ AiInsights (polymorphic)

Tree ──belongs_to──→ Cluster, TreeFamily, TinyMlModel
     ──has_one────→ Wallet, HardwareKey, DeviceCalibration
     ──has_many───→ TelemetryLogs, EwsAlerts, MaintenanceRecords, AiInsights

Gateway ──belongs_to──→ Cluster
        ──has_one────→ HardwareKey
        ──has_many───→ GatewayTelemetryLogs, Actuators

Actuator ──belongs_to──→ Gateway
         ──has_many───→ ActuatorCommands

Wallet ──belongs_to──→ Tree
       ──has_many───→ BlockchainTransactions

NaasContract ──belongs_to──→ Organization, Cluster
```

### Supporting Entities

- **TreeFamily** - Species-specific Lorenz attractor thresholds (`critical_z_min`, `critical_z_max`)
- **TinyMlModel** - Pest detection neural network weights (512-byte OTA chunks)
- **BioContractFirmware** - mruby bytecode for on-device Lorenz computation
- **HardwareKey** - AES-256 keys per device (encrypted at rest)
- **DeviceCalibration** - Per-sensor temperature/impedance/voltage offsets
- **Session / Identity** - Auth (password + OAuth via Google/Apple/LinkedIn)

## Sidekiq Queue Hierarchy

| Queue | Priority | Workers |
|-------|----------|---------|
| `uplink` | 5 (highest) | UnpackTelemetryWorker, GatewayTelemetryWorker |
| `alerts` | 4 | AlertNotificationWorker, SingleNotificationWorker |
| `critical` | 4 | BurnCarbonTokensWorker, InsurancePayoutWorker, EcosystemHealingWorker |
| `downlink` | 3 | ActuatorCommandWorker, OtaTransmissionWorker, ResetActuatorStateWorker |
| `default` | 2 | ClusterHealthCheckWorker, TokenomicsEvaluatorWorker |
| `web3` | 1 | MintCarbonCoinWorker, BlockchainConfirmationWorker, IotexVerificationWorker, ChainlinkDispatchWorker, CeloRewardWorker, SolanaMicroRewardWorker, EthereumAnchorWorker, KlimaRetirementWorker, HadronAssetRegistrationWorker, PeaqRegistrationWorker |
| `low` | 1 | DailyAggregationWorker, FilecoinArchiveWorker, AuditLogWorker, StreamrBroadcastWorker |

### Sidekiq Worker Chain (The Heartbeat)

The system operates on three time scales:

```
HOURLY (TokenomicsEvaluatorWorker)
  └→ Scan wallets ≥ 10,000 growth_points → lock_and_mint!
     └→ MintCarbonCoinWorker → BlockchainMintingService → Polygon
        └→ BlockchainConfirmationWorker (+30s) → confirm! / fail!

DAILY (01:00–02:00 UTC)
  DailyAggregationWorker (01:00)
    └→ InsightGeneratorService → AiInsight per tree (stress_index, fraud_detected)
       └→ ClusterHealthCheckWorker (02:00)
          ├→ Healthy cluster: CeloRewardWorker (5 cUSD) + optional KlimaRetirement
          └→ Breached cluster: BurnCarbonTokensWorker → Sovereign Slashing

WEEKLY (Monday 03:00 UTC)
  EthereumAnchorWorker
    └→ Ethereum::StateAnchorService → SHA-256 state root → Ethereum L1
```

## AI Oracle (Lorenz Attractor + ZK Verification)

The Lorenz attractor serves as a nonlinear transform of multi-sensor data into a single homeostasis indicator (Z-value). In Gaia 2.0, this is combined with IoTeX W3bstream ZK-proofs for trustless verification.

**Equations:**
```
dx/dt = σ(y - x)
dy/dt = x(ρ - z) - y
dz/dt = xy - βz
```

**Constants:** σ = 10.0, ρ = 28.0, β = 8/3 (all BigDecimal, 18-digit precision)

**Perturbation:** Acoustic events shift σ (coupling, clamped 5–30), temperature shifts ρ (energy, clamped 10–50). The DID of each tree seeds unique initial conditions, creating a per-tree "chaotic fingerprint."

**Homeostasis check:** Z-value compared against per-species thresholds from `TreeFamily` (`critical_z_min` / `critical_z_max`). Trees within bounds earn growth points; trees outside bounds trigger drought/pest alerts.

**Dual Computation Integrity:** The same Lorenz equations run on-device (mruby, `firmware/bio_contracts/bio_contract.rb`) and on-server (`SilkenNet::Attractor`, BigDecimal). Divergence triggers fraud detection in `InsightGeneratorService`.

**Trustless Verification Pipeline:**
```
Lorenz Z-value (server) + hardware signature
    → Iotex::W3bstreamVerificationService (ZK-proof generation)
    → Chainlink::OracleDispatchService (decentralized bridge to blockchain)
    → BlockchainMintingService (guard: verified_by_iotex? + oracle_status == "fulfilled")
```

## Security Model

- **Zero-Trust Architecture** — Every device has a unique AES-256 key stored in `HardwareKey` (encrypted at rest via ActiveRecord Encryption)
- **DID-Based Identity** — Each Soldier generates a DID from STM32 factory UID XOR'd with TRNG, locked in RTC backup registers. Registered as `did:peaq:0x...` via `Peaq::DidRegistryService` (self-sovereign machine passport)
- **ZK-Proof Verification** — IoTeX W3bstream validates that telemetry originated from real silicon hardware, not a software emulator
- **Chainlink Guard Clauses** — Decentralized oracle verification required before any token minting (prevents single-point-of-failure in the oracle layer)
- **Hadron KYC Compliance** — Polygon Hadron verifies investor KYC/KYB status before RWA token operations (ERC-3643)
- **Token Authentication** — Rails 8 `generates_token_for :api_access` for API, session-based for dashboard
- **RBAC** — Four roles: `investor` (read-only), `forester` (field operations), `admin` (full control), `super_admin` (system-level)
- **Encrypted Payloads** — AES-256-ECB for all LoRa and CoAP transmissions
- **Key Rotation** — `HardwareKeyService.rotate` generates new key + OTA downlink (Dual-Key Handshake with Grace Period)
- **Immutable Audit Trail** — SHA-256 chain_hash per organization → Filecoin/IPFS archive (CID) → weekly Ethereum L1 state root
- **BigDecimal Precision** — All financial and Lorenz calculations use 18-digit BigDecimal to ensure cross-platform determinism and legal-grade Web3 audit accuracy

## Shared Infrastructure Layer

### Base Classes

| Class | Purpose |
|---|---|
| **`ApplicationService`** | Base class for all services. Provides `.call(...)` → `#perform` template pattern |
| **`ApplicationWeb3Worker`** | Base module for blockchain workers. Standardized RPC error handling, structured logging, partition-pruned lookup |

### Web3 Utility Layer (`app/services/web3/`)

| Utility | Purpose |
|---|---|
| **`Web3::HttpClient`** | Centralized HTTP client for all external APIs (IPFS, IoTeX, Streamr, Hadron, The Graph, peaq, Solana). Unified timeouts, auto SSL, lazy JSON parsing via `Response` wrapper |
| **`Web3::RpcConnectionPool`** | Thread-safe `Eth::Client` caching per Sidekiq thread. Prevents repeated TCP/TLS handshakes. Supports `fallback:` URL for testnet |
| **`Web3::WeiConverter`** | BigDecimal-based conversion between human-readable and wei (ERC-20, 18 decimals). Prevents precision loss in financial operations |

### Model Concerns

| Concern | Models | Purpose |
|---|---|---|
| **`GeoLocatable`** | Tree, Gateway, MaintenanceRecord | Unified WGS-84 coordinate validation (latitude -90..90, longitude -180..180) |
| **`NormalizeIdentifier`** | Tree, Gateway, HardwareKey | UID/DID normalization via Rails `normalizes` DSL (strip + upcase) |
| **`CoapEncryption`** | Downlink workers | Centralized AES-256-CBC encryption for CoAP packets with random IV |

### Extracted Domain Services

| Service | Extracted From | Purpose |
|---|---|---|
| **`ContractHealthCheckService`** | NaasContract model | Cluster health check against NaasContract threshold (20% critical trees). Initiates Slashing Protocol on breach |
| **`ContractTerminationService`** | NaasContract model | Early NaasContract termination with proportional refund and penalty calculation |
