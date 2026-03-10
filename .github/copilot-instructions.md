# Copilot Instructions — SilkenNet

## Project Overview

SilkenNet is a bio-IoT platform that monitors forest health using titanium gyroid anchors embedded in trees. Each anchor contains an STM32WLE5JC microcontroller that harvests energy from the tree's streaming potential (≈44 mV) via a piezoelectric element and supercapacitor (ionistor 0.47 F). The system forms a LoRa mesh network where "soldier" nodes collect sensor data, relay it through peer soldiers to a "queen" gateway, which transmits batched telemetry to the cloud backend via Starlink Direct-to-Cell or LTE (SIM7070G). The backend processes telemetry, runs AI analysis (Lorenz attractor), manages a dual-token crypto economy on Polygon, and provides a REST API + real-time dashboard.

## Scale

The system is designed to scale to **millions → billions → trillions** of trees worldwide. Every architectural decision — database schema, telemetry ingestion pipeline, queue throughput, API pagination, blockchain tokenomics — must account for this scale. Avoid naive solutions that work for thousands of records but collapse at planetary scale. Think about partitioning, sharding, batch processing, streaming, and horizontal scalability from day one.

## Architecture (4 Layers)

```
[Blockchain Layer] Polygon — SilkenCarbonCoin (SCC, utility) + SilkenForestCoin (SFC, governance)
        ↕
[Backend Layer]    Rails 8.1 API — PostgreSQL, Sidekiq, Solid Queue/Cache/Cable
        ↕
[Network Layer]    LoRa 868 MHz mesh — CoAP/UDP — Queen gateways — Starlink/LTE
        ↕
[Edge Layer]       STM32WLE5JC soldiers — energy harvesting — mruby VM — TinyML
```

## Tech Stack

| Layer      | Technology                                                        |
|------------|-------------------------------------------------------------------|
| Language   | Ruby 4.0.1                                                        |
| Framework  | Rails 8.1.2 (API + Hotwire/Turbo 8/Stimulus, Phlex, Tailwind)    |
| Database   | PostgreSQL (3 databases: primary, cache, queue)                   |
| Jobs       | Sidekiq (16 workers, 7 priority queues) + Solid Queue             |
| Cache      | Solid Cache                                                       |
| WebSocket  | Solid Cable (ActionCable)                                         |
| Blockchain | Solidity on Polygon, `eth` gem for RPC                            |
| Serializer | Blueprinter                                                       |
| Pagination | Pagy + Groupdate                                                  |
| IoT        | CoAP/UDP listener daemon, LoRaWAN 868 MHz                        |
| Firmware   | C (STM32 HAL) + mruby VM + TinyML (CMSIS-NN)                     |
| Deploy     | Kamal (Docker), Terraform (GCP), Thruster (HTTP/2)               |
| Testing    | RSpec, FactoryBot, Capybara, Selenium, SimpleCov                  |
| Security   | Brakeman, bundler-audit, bcrypt, AES-256 hardware-bound keys      |
| Storage    | Active Storage (S3 / Google Cloud Storage)                        |

## Directory Structure

```
app/
  controllers/api/v1/   # 26 RESTful API controllers (inherit BaseController)
  models/               # 25 ActiveRecord models
  services/             # 12 service objects (business logic)
  workers/              # 16 Sidekiq background workers
  blueprints/           # Blueprinter JSON serializers
  views/                # Phlex components + ERB layouts
contracts/              # Solidity: SilkenCarbonCoin.sol, SilkenForestCoin.sol
firmware/
  soldier/main.c        # Tree sensor node firmware (STM32, 648 lines)
  queen/main.c          # LoRa gateway firmware (STM32 + SIM7070G, 550 lines)
  bio_contracts/        # mruby bytecode (Lorenz attractor on-device)
lib/daemons/            # CoAP UDP listener
spec/                   # RSpec tests (~101 files)
docs/                   # Comprehensive .md documentation (12 files)
terraform/              # GCP infrastructure-as-code
config/
  sidekiq.yml           # Queue priorities & cron scheduler
  database.yml          # PostgreSQL multi-database config
  routes.rb             # API routes (namespace api/v1)
```

## Domain Model (Key Entities)

- **User / Organization / Session / Identity** — authentication, multi-tenant
- **Tree / TreeFamily / Cluster** — biological entities, grouped by species and geography
- **Gateway (Queen) / HardwareKey / DeviceCalibration** — IoT hardware registration
- **TelemetryLog / GatewayTelemetryLog** — raw sensor data (21-byte binary packets)
- **AiInsight / TinyMlModel / BioContractFirmware** — AI analysis, OTA firmware
- **Wallet / NaasContract / ParametricInsurance / BlockchainTransaction** — crypto economy
- **EwsAlert / MaintenanceRecord / AuditLog** — alerts, maintenance, audit trail
- **Actuator / ActuatorCommand** — remote hardware control

## Coding Conventions

### Ruby / Rails
- Follow `.rubocop.yml` (inherits `rubocop-rails-omakase`)
- Controllers: thin, delegate to services. Pattern: `Api::V1::<Resource>Controller < Api::V1::BaseController`
- Services: `app/services/`, plain Ruby classes with `call` or `perform` methods
- Workers: `app/workers/`, Sidekiq workers with `include Sidekiq::Worker` and `perform` method
- Serializers: `app/blueprints/`, Blueprinter classes (`<Model>Blueprint < Blueprinter::Base`)
- Models: validations, associations, scopes. No business logic in models — use services
- Tests: RSpec, use `let` / `let!`, FactoryBot factories in `spec/factories/`
- Background job queues (priority order): `uplink` > `alerts` = `critical` > `downlink` > `default` > `web3` = `low`

### Firmware (C)
- STM32 HAL library, CMSIS headers
- Soldier lifecycle: sense → TinyML → mruby → pack+encrypt → TX + sleep
- Queen lifecycle: LoRa RX → AES decrypt → CIFO cache → CoAP batch PUT → OTA broadcast
- Binary packet format: 21 bytes (1 header + 4 DID + 8 sensor + 4 Lorenz + 2 TinyML + 2 CRC)
- Encryption: AES-128/256 with hardware-bound keys provisioned via `/api/v1/provisioning`
- Mesh: TTL-based multi-hop routing, anti-pingpong via seen-set

### Solidity
- OpenZeppelin base contracts (ERC-20, AccessControl, Pausable, Votes, Permit)
- Polygon network (Amoy testnet → Mainnet)
- Foundry toolchain for deployment and testing

## Key Domain Concepts

- **Streaming Potential**: bio-electric potential (~44 mV) generated by sap flow in trees; harvested by LTC3108 ultra-low voltage boost converter to charge a 0.47 F supercapacitor
- **Soldier**: tree-mounted STM32WLE5JC sensor node with LoRa radio, runs mruby VM and TinyML
- **Queen**: gateway device (STM32 + SIM7070G modem) that collects soldier data and relays to backend via Starlink Direct-to-Cell or LTE
- **Lorenz Attractor**: chaotic dynamical system (σ, ρ, β parameters) used to model tree homeostasis; computed both on-device (mruby) and backend (Ruby) for dual verification
- **DID (Device ID)**: 4-byte hardware identity derived from STM32 UID, provisioned via API
- **Proof of Growth**: consensus mechanism — trees earn SilkenCarbonCoin (SCC) for verified biomass growth (10,000 growth_points = 1 SCC)
- **Slashing**: automatic token burning if >20% of cluster trees show stress signals
- **NaaS (Nature-as-a-Service)**: business model where organizations subscribe to forest monitoring
- **Parametric Insurance**: automated payouts triggered by catastrophic events (fire >60°C, drought, pest detection)
- **OTA**: over-the-air firmware updates, chunked (512 bytes/chunk, 0.4s pacing), broadcast from queen to soldiers
- **CIFO Cache**: queen-side circular buffer for telemetry batching before CoAP transmission
- **TinyML**: on-device audio classification (chainsaw, fire, woodpecker) using CMSIS-NN, 6-class output

## Sidekiq Queue Hierarchy

| Priority | Queue      | Purpose                                       |
|----------|------------|-----------------------------------------------|
| 5        | uplink     | Telemetry ingestion (UnpackTelemetryWorker)   |
| 4        | alerts     | EWS alerts, notifications                     |
| 4        | critical   | Ecosystem healing, insurance payouts          |
| 3        | downlink   | OTA transmission, actuator commands           |
| 2        | default    | Aggregation, health checks                    |
| 1        | web3       | Blockchain minting, burning, confirmations    |
| 1        | low        | Audit logging                                 |

## API Structure

All endpoints are under `/api/v1/` namespace, JSON responses, token-based auth (Bearer).
See `docs/API.md` for the full 24-endpoint reference.

## Testing

- Run all tests: `bundle exec rspec`
- Run specific: `bundle exec rspec spec/models/tree_spec.rb`
- Linting: `bundle exec rubocop`
- Security: `bundle exec brakeman` and `bundle exec bundler-audit check`
- Feature tests: Capybara + Selenium (headless Chrome)

## Documentation Index

| File                          | Content                                     |
|-------------------------------|---------------------------------------------|
| `README.md`                   | Project overview (Ukrainian)                |
| `docs/README_EN.md`           | Project overview (English)                  |
| `docs/ARCHITECTURE.md`        | System layers, data flow, domain model      |
| `docs/API.md`                 | 24 REST API endpoints reference             |
| `docs/MODELS.md`              | All 25 data models with fields              |
| `docs/LOGIC.md`               | Services & workers reference                |
| `docs/FIRMWARE.md`            | STM32 firmware specs, packet format, mesh   |
| `docs/HARDWARE.md`            | Energy harvesting BOM, schematics           |
| `docs/TOKENOMICS.md`          | SCC/SFC token economy, Proof of Growth      |
| `docs/BLOCKCHAIN_DEVELOPMENT.md` | Web3 dev guide, Foundry, Polygon         |
| `docs/DEPLOYMENT.md`          | Kamal, Terraform, infrastructure            |
| `docs/VISION.md`              | Mission, science, roadmap (2026–2030)       |

## Environment Setup

- **Ruby 4.0.1** is located at `/opt/hostedtoolcache/Ruby/4.0.1/x64/bin`. Add it to PATH before running any Ruby/Bundle commands:
  ```bash
  export PATH="/opt/hostedtoolcache/Ruby/4.0.1/x64/bin:$PATH"
  ```
- Always verify with `ruby --version` before running `bundle install`, `bundle exec rspec`, etc.
- **Migrations**: When creating or modifying migrations, always run them against the **development** database and commit the updated `db/structure.sql`:
  ```bash
  bundle exec rails db:migrate
  ```
  This regenerates `db/structure.sql`. The updated `structure.sql` **must** be committed alongside the migration file.

## Important Notes for Copilot

- This is a **Ukrainian-founded** project; comments and README may be in Ukrainian, but code and API are in English.
- Ruby version is **4.0.1** — use modern Ruby syntax (pattern matching, numbered block params, etc.).
- Rails version is **8.1.2** — use Rails 8 conventions (Solid Queue/Cache/Cable, no Redis dependency for queue/cache).
- The project uses **3 separate PostgreSQL databases** (primary, cache, queue) — be aware of `connects_to` in models.
- Firmware files in `firmware/` are plain C with STM32 HAL — not managed by Bundler or Rails.
- Solidity contracts in `contracts/` use Foundry toolchain — not managed by Bundler.
- When working with telemetry, remember the **21-byte binary packet format** and AES encryption.
- Background jobs have strict **queue priority** — always assign the correct queue to new workers.
- The Lorenz attractor math is critical — σ=10, ρ=28, β=8/3 are defaults, perturbed by sensor readings.
