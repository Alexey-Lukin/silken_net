# Silken Net — Gaia 2.0: The Cyber-Physical State

**Nature-as-a-Service (NaaS) / D-MRV Platform — 12-Chain Multichain Architecture**

Silken Net is a trustless Digital Measurement, Reporting, and Verification (D-MRV) platform that integrates forest biological homeostasis with IoT sensor networks and a 12-chain decentralized infrastructure. Trees become sovereign digital citizens with machine passports (peaq DID), ZK-verified telemetry (IoTeX W3bstream), and token rewards across Polygon, Solana, Celo, and Ethereum.

## The Core Idea

Trees generate streaming potentials (40-100mV) from xylem ion transport and pH gradients. Silken Net harvests this bio-potential to power autonomous sensor nodes (Soldiers) implanted in trees. Each tree becomes a self-powered monitoring station that continuously reports its health to the blockchain, earning carbon credit tokens for verified growth.

## Architecture (Gaia 2.0 — 12-Chain Integration)

| Layer | Components | Role |
|-------|-----------|------|
| **Edge** | STM32WLE5JC Soldiers + Queens | Sensor acquisition, TinyML audio classification, mruby Lorenz attractor bio-contracts, AES-256 encrypted LoRa mesh |
| **Infra** | Akash Network (Decentralized Cloud) | Unkillable body — no single cloud provider can shut down the system |
| **Backend** | Rails 8.1 + Sidekiq + PostgreSQL | Telemetry unpacking, AI Oracle (Lorenz BigDecimal), alert dispatch, tokenomics evaluation |
| **Verification** | IoTeX W3bstream + Chainlink + peaq | ZK-proofs, decentralized oracle, machine DID (trustless verification layer) |
| **Data** | Streamr + Filecoin/IPFS | P2P real-time forest pulse + immutable audit archive |
| **Blockchain** | Polygon + Hadron + Solana + Celo + KlimaDAO + The Graph | Multi-token economy, RWA compliance, micro-rewards, ESG retirement, indexing |
| **Finality** | Ethereum L1 | Weekly state root anchoring (ultimate immutability) |

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | Ruby 4.0.1 |
| Framework | Rails 8.1.2 (Omakase) |
| Database | PostgreSQL + Solid Cache + Solid Cable + Solid Queue |
| Background Jobs | Sidekiq + sidekiq-scheduler (7 priority queues, 26 workers) |
| Frontend | Hotwire (Turbo 8, Stimulus), Tailwind CSS, Phlex |
| Serialization | Blueprinter (JSON blueprints) |
| Pagination | Pagy + Groupdate (time-series) |
| Blockchain | Polygon, Ethereum, Solana, Celo (multi-chain), Solidity, eth gem |
| Verification | IoTeX W3bstream (ZK-proofs), Chainlink (Oracle), peaq (DID) |
| DeFi | KlimaDAO (ESG), Polygon Hadron (RWA/KYC) |
| Data Streams | Streamr (P2P), The Graph (Subgraph), Filecoin/IPFS (Archive) |
| IoT Protocol | LoRa (868 MHz), CoAP/UDP |
| MCU | STM32WLE5JC (ARM Cortex-M4 + LoRa SoC) |
| Edge Runtime | mruby (bio-contracts), TinyML (pest detection) |
| Deployment | Kamal (Docker), Akash Network (Decentralized Cloud), Thruster (HTTP/2) |

## Quick Start

```bash
git clone https://github.com/Alexey-Lukin/silken_net.git
cd silken_net
bundle install
bin/rails db:prepare
bin/dev
```

## Documentation

- **[🌐 Gaia 2.0 Anatomy](GAIA_2_0_ANATOMY.md)** — The 12-step lifecycle of the Cyber-Physical State
- [Architecture](ARCHITECTURE.md) — System layers, multichain data flow, domain model, AI Oracle
- [Models](MODELS.md) — All domain models with relationships
- [Logic](LOGIC.md) — Services (24) and Workers (26) reference
- [Tokenomics](TOKENOMICS.md) — Multichain token economy, Proof of Growth, slashing protocol
- [API Reference](API.md) — All 24 API controllers with endpoints and parameters
- [Firmware](FIRMWARE.md) — Soldier/Queen lifecycle, binary protocol, mruby bio-contracts
- [Hardware](HARDWARE.md) — Energy harvesting stack, BOM, energy budget
- [Blockchain Development](BLOCKCHAIN_DEVELOPMENT.md) — 12-chain Web3 setup, minting/slashing flows
- [Deployment](DEPLOYMENT.md) — Kamal + Akash + Terraform infrastructure
- [Vision](VISION.md) — Project vision, science, Titan's Roadmap

## License

See [LICENSE](../LICENSE) for details.
