# Project Vision & Roadmap

## Mission

Build a D-MRV (Digital Measurement, Reporting, and Verification) platform that gives forests "digital will" -- real-time, sensor-verified, cryptographically-attested proof of ecosystem health. Replace manual carbon credit auditing with continuous, autonomous, tamper-proof monitoring.

## The Science

### Tree Bio-Potential

Trees generate streaming potentials of 40-100mV through xylem ion transport and pH gradients. This electrochemical signal is a byproduct of sap flow -- the fundamental life process of the tree. Silken Net harvests this energy to power sensors, making each tree a self-sustaining monitoring node.

### S-NET Anchor

The physical interface between technology and tree:

- **Material:** Ti-6Al-4V Grade 5 titanium
- **Topology:** Gyroid structure (triply periodic minimal surface) for xylem integration
- **Design philosophy:** Works with the CODIT (Compartmentalization of Decay in Trees) immune response rather than against it
- **Purpose:** Houses electrodes for bio-potential harvesting and EIS measurement

### S-NET Head

The external computing module attached to the Anchor:

- **MCU:** STM32WLE5JC (ARM Cortex-M4 + LoRa SoC)
- **Capabilities:** EIS measurement, TinyML edge processing, LoRa mesh communication
- **Power:** Fed by energy harvesting chain (LTC3108 + BQ25570 + supercapacitor)

### Electrical Impedance Spectroscopy (EIS)

Multi-frequency impedance measurements reveal tree internal state:

- **Xylem sap flow** - Impedance changes correlate with transpiration rate
- **Drought stress** - Increased impedance from air embolism in xylem vessels
- **Pathogen invasion** - Impedance anomalies from fungal colonization
- **Measurement:** Swept-frequency AC excitation through Anchor electrodes

### Lorenz Attractor for Homeostasis

The Lorenz attractor serves as a nonlinear transform of multi-sensor data:

- **Input:** Temperature, acoustic events, impedance (via DID seed)
- **Output:** Z-value as proxy for "convective intensity" (sap flow metabolism)
- **Calibration:** Per-species thresholds stored in `TreeFamily` (`critical_z_min` / `critical_z_max`)
- **Mathematical properties:** Sensitive to initial conditions (chaos theory), but bounded by the attractor shape -- healthy trees remain within the attractor's "wings"

The fine structure constant (1/137) appears as a design parameter, reflecting the project's philosophy that fundamental physical constants should guide engineering decisions.

## Network Topology

```
Soldier (Tree)         Soldier (Tree)         Soldier (Tree)
      │ LoRa                │ LoRa mesh            │ LoRa
      ▼                     ▼                      ▼
   Queen (Gateway) ◄──── Mesh Relay ────► Queen (Gateway)
      │ LTE/Starlink                          │ LTE/Starlink
      ▼                                       ▼
   ┌──────────────────────────────────────────────┐
   │  Rails Backend (CoAP Listener + Sidekiq)     │
   │  TelemetryUnpackerService                    │
   │  AlertDispatchService                        │
   │  InsightGeneratorService                     │
   │  TokenomicsEvaluatorWorker                   │
   └──────────────────┬───────────────────────────┘
                      │ Eth RPC
                      ▼
   ┌──────────────────────────────────────────────┐
   │  Polygon Blockchain                          │
   │  SilkenCarbonCoin.sol (mint / slash)          │
   │  SilkenForestCoin.sol (governance)            │
   └──────────────────────────────────────────────┘
```

## Nature-as-a-Service (NaaS) Business Model

1. **Organizations fund forest clusters** via NaaS contracts (`NaasContract`)
2. **Trees earn growth points** through verified biological homeostasis
3. **Points convert to SCC tokens** on Polygon (10,000 points = 1 SCC, valued at ~$25.5)
4. **Investors receive tokens** proportional to their funded cluster's performance
5. **If forest degrades** (>20% trees anomalous), tokens are slashed (burned)
6. **Parametric insurance** provides automatic payouts for catastrophic events

This creates an economic feedback loop: investors are incentivized to ensure forest health, not just claim carbon credits.

## "Proof of Growth" Consensus

Unlike Proof of Work (energy waste) or Proof of Stake (capital concentration), Proof of Growth ties token minting to verified biological processes:

- Every SCC token is backed by sensor-verified photosynthesis and carbon sequestration
- On-device computation (mruby) prevents spoofing at the hardware level
- Server-side verification (Ruby) provides redundant integrity checking
- Slashing protocol ensures economic consequences for forest degradation

## Titan's Roadmap

### Phase 1: Cherkasy Forest Pilot (2026)

- Deploy first cluster of 50 Soldier nodes in Cherkasy pine forest
- Validate energy harvesting at 44mV bio-potential
- First SCC minting on Polygon testnet
- Iterate on S-NET Anchor design (CODIT compatibility)

### Phase 2: Regional Expansion (2027-2028)

- Scale to 10+ clusters across Ukrainian forests
- Mainnet deployment on Polygon
- First NaaS contracts with corporate investors
- SFC governance token launch
- Mobile app for foresters (React Native)

### Phase 3: Global Deployment (2029-2030)

- International forest partnerships
- Multi-species TreeFamily calibration database
- Satellite backhaul integration (Starlink)
- DAO governance via SFC voting
- Target: 1 million monitored trees

## Market Opportunity

The voluntary carbon credit market ($2B+ and growing) is plagued by:

- **Manual auditing** - Expensive, infrequent, error-prone
- **Double counting** - Same forest claimed by multiple parties
- **Permanence risk** - No monitoring after credit issuance
- **Fraud** - Phantom forests, inflated sequestration claims

Silken Net's sensor-verified D-MRV solves all four problems with continuous, autonomous, cryptographically-attested monitoring. Each SCC token represents real, verified, ongoing carbon sequestration -- not a one-time estimate.
