# System Architecture

## System Layers

```
┌─────────────────────────────────────────────────────────────┐
│  BLOCKCHAIN (Polygon)                                       │
│  SilkenCarbonCoin.sol / SilkenForestCoin.sol (ERC-20)       │
├─────────────────────────────────────────────────────────────┤
│  BACKEND (Rails 8.1 + Sidekiq + PostgreSQL)                 │
│  14 API Controllers · 8 Services · 12 Workers               │
├─────────────────────────────────────────────────────────────┤
│  NETWORK (LoRa 868 MHz + CoAP/UDP over LTE/Starlink)        │
├─────────────────────────────────────────────────────────────┤
│  EDGE (STM32WLE5JC Soldiers + Queens)                       │
│  TinyML · mruby VM · AES-256 · Mesh TTL routing             │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **Sensor Acquisition** - Soldier reads impedance (EIS), temperature, acoustic events (piezo), and supercapacitor voltage
2. **TinyML Audio Classification** - On-device neural network classifies audio: silence / wind / cavitation / chainsaw
3. **mruby Bio-Contract** - Lorenz attractor computation on-device produces `growth_points` and `bio_status`
4. **Bit-Packing & Encryption** - 16-byte payload packed, AES-256-ECB encrypted, transmitted via LoRa
5. **Queen Reception** - Queen decrypts, caches via CIFO (Closest In, Farthest Out), batches up to 50 trees
6. **CoAP Uplink** - Queen sends binary batch via CoAP PUT over LTE/Starlink to Rails backend
7. **Backend Unpacking** - `UnpackTelemetryWorker` → `TelemetryUnpackerService` decodes, normalizes via `DeviceCalibration`, stores `TelemetryLog`
8. **Server-Side Lorenz Verification** - `SilkenNet::Attractor.calculate_z` verifies device-computed Z-value (dual computation integrity)
9. **Alert Dispatch** - `AlertDispatchService` checks 5 threat categories → `EmergencyResponseService` dispatches actuators (water valves, fire sirens, seismic beacons)
10. **Tokenomics Evaluation** - `TokenomicsEvaluatorWorker` (hourly): 10,000 growth_points = 1 SCC → `MintCarbonCoinWorker` → `BlockchainMintingService` → Polygon
11. **Daily Aggregation** - `DailyAggregationWorker` → `InsightGeneratorService` → `ClusterHealthCheckWorker` → Slashing Protocol (if >20% trees anomalous)

## Domain Model

### Core Entities (22 models)

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
| `uplink` | 5 (highest) | UnpackTelemetryWorker |
| `alerts` | 4 | AlertNotificationWorker |
| `downlink` | 3 | ActuatorCommandWorker, OtaTransmissionWorker, ResetActuatorStateWorker |
| `default` | 2 | DailyAggregationWorker, ClusterHealthCheckWorker, TokenomicsEvaluatorWorker, GatewayTelemetryWorker |
| `web3` | 1 | MintCarbonCoinWorker, BurnCarbonTokensWorker, InsurancePayoutWorker |
| `low` | 1 | DailyAggregationWorker |

## AI Oracle (Lorenz Attractor)

The Lorenz attractor serves as a nonlinear transform of multi-sensor data into a single homeostasis indicator (Z-value).

**Equations:**
```
dx/dt = σ(y - x)
dy/dt = x(ρ - z) - y
dz/dt = xy - βz
```

**Constants:** σ = 10.0, ρ = 28.0, β = 8/3

**Perturbation:** Acoustic events shift σ (coupling), temperature shifts ρ (energy). The DID of each tree seeds unique initial conditions, creating a per-tree "chaotic fingerprint."

**Homeostasis check:** Z-value compared against per-species thresholds from `TreeFamily` (`critical_z_min` / `critical_z_max`). Trees within bounds earn growth points; trees outside bounds trigger drought/pest alerts.

## Security Model

- **Zero-Trust Architecture** - Every device has a unique AES-256 key stored in `HardwareKey` (encrypted at rest via ActiveRecord Encryption)
- **DID-Based Identity** - Each Soldier generates a DID from STM32 factory UID XOR'd with TRNG, locked in RTC backup registers
- **Token Authentication** - Rails 8 `generates_token_for :api_access` for API, session-based for dashboard
- **RBAC** - Three roles: `investor` (read-only), `forester` (field operations), `admin` (full control)
- **Encrypted Payloads** - AES-256-ECB for all LoRa and CoAP transmissions
- **Key Rotation** - `HardwareKeyService.rotate` generates new key + OTA downlink
