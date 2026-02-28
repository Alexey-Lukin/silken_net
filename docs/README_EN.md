# Silken Net: Digital Ecosystem of Cherkasy Pine Forest

**Nature-as-a-Service (NaaS) / D-MRV Platform**

Silken Net is a titanium-level Digital Measurement, Reporting, and Verification (D-MRV) platform that unites forest biological homeostasis with IoT sensor networks and decentralized finance on Polygon blockchain.

## The Core Idea

Trees generate streaming potentials (40-100mV) from xylem ion transport and pH gradients. Silken Net harvests this bio-potential to power autonomous sensor nodes (Soldiers) implanted in trees. Each tree becomes a self-powered monitoring station that continuously reports its health to the blockchain, earning carbon credit tokens for verified growth.

## Three-Tier Architecture

| Layer | Components | Role |
|-------|-----------|------|
| **Edge** | STM32WLE5JC Soldiers + Queens | Sensor acquisition, TinyML audio classification, mruby Lorenz attractor bio-contracts, AES-256 encrypted LoRa mesh |
| **Backend** | Rails 8.1 + Sidekiq + PostgreSQL | Telemetry unpacking, AI Oracle (Lorenz verification), alert dispatch, tokenomics evaluation |
| **Blockchain** | Polygon (ERC-20) | SCC/SFC token minting, "Proof of Growth" consensus, slashing protocol, parametric insurance |

## Tech Stack

| Category | Technology |
|----------|-----------|
| Language | Ruby 3.4.1 |
| Framework | Rails 8.1.2 (Omakase) |
| Database | PostgreSQL + Solid Cache + Solid Cable |
| Background Jobs | Sidekiq (6 priority queues) |
| Frontend | Hotwire (Turbo 8, Stimulus), Tailwind CSS |
| Blockchain | Polygon, Solidity (ERC-20 + Votes + Permit) |
| IoT Protocol | LoRa (868 MHz), CoAP/UDP |
| MCU | STM32WLE5JC (ARM Cortex-M4 + LoRa SoC) |
| Edge Runtime | mruby (bio-contracts), TinyML (pest detection) |
| Deployment | Kamal (Docker) |

## Quick Start

```bash
git clone https://github.com/Alexey-Lukin/silken_net.git
cd silken_net
bundle install
bin/rails db:prepare
bin/dev
```

## Documentation

- [Architecture](ARCHITECTURE.md) - System layers, data flow, domain model, AI Oracle
- [Tokenomics](TOKENOMICS.md) - Dual token economy, Proof of Growth, slashing protocol
- [API Reference](API.md) - All 14 API controllers with endpoints and parameters
- [Firmware](FIRMWARE.md) - Soldier/Queen lifecycle, binary protocol, mruby bio-contracts
- [Hardware](HARDWARE.md) - Energy harvesting stack, BOM, energy budget
- [Vision](VISION.md) - Project vision, science, Titan's Roadmap

## License

See [LICENSE](../LICENSE) for details.
