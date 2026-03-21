# Copilot Instructions — SilkenNet

## SSOT Reference

The [GitHub Wiki](https://github.com/Alexey-Lukin/silken_net/wiki) is the Single Source of Truth (SSOT) for the Gaia 2.0 architecture. It defines the 8-layer cyber-physical system across 9 modules. Always consult it for architectural decisions. See also `.cursorrules` and `CLAUDE.md` for complementary AI guidance.

## Project Overview

SilkenNet (Gaia 2.0) is a bio-IoT D-MRV platform that monitors forest health at planetary scale using titanium gyroid anchors (Ti-6Al-4V) embedded in trees. Each anchor contains an EBFC (Enzymatic Bio-Fuel Cell) that harvests >500 mV from tree glucose metabolism via GOx/Laccase enzymes, powering a BQ25570 MPPT and 0.47 F EDLC supercapacitor. An STM32WLE5JC microcontroller runs TinyML acoustic classification and mruby Lorenz attractor computation. The system forms a LoRa mesh network where "soldier" nodes collect sensor data, relay it through peer soldiers to a "queen" gateway, which transmits batched telemetry to the cloud backend via Starlink Direct-to-Cell or LTE (SIM7070G). The backend processes telemetry, runs AI analysis (Lorenz attractor with BigDecimal precision), manages a 12-chain crypto economy anchored on Polygon, and provides a REST API + real-time Phlex/Turbo dashboard.

## Scale

The system is designed to scale to **millions → billions → trillions** of trees worldwide. Every architectural decision — database schema, telemetry ingestion pipeline, queue throughput, API pagination, blockchain tokenomics — must account for this scale. Avoid naive solutions that work for thousands of records but collapse at planetary scale. Think about partitioning, sharding, batch processing, streaming, and horizontal scalability from day one.

## Architecture (8 Layers per Wiki SSOT)

```
L8  Ethereum L1          Weekly State Root anchoring (32-byte SHA-256 finality)
L7  Polygon + DeFi       SCC/SFC minting, Solana micro-rewards, Celo ReFi, KlimaDAO ESG
L6  Verification          peaq DID, IoTeX ZK-proofs, Streamr P2P, Filecoin/IPFS archive
L5  Rails Backend         Rails 8.1 API, PostgreSQL, Sidekiq (31+ workers), Prometheus
L4  LoRa Network          868 MHz mesh, CoAP/UDP, Queen gateways, Starlink/LTE
L3  Firmware & Edge AI    STM32WLE5JC, TinyML (CMSIS-NN), mruby Lorenz, AES-256
L2  Hardware Capsule      BQ25570 MPPT, 0.47F EDLC supercapacitor, Pogo Pin blind-mate
L1  Biophysics            Ti-6Al-4V gyroid anchor, EBFC (GOx anode + Laccase cathode)
```

## Tech Stack

| Layer      | Technology                                                        |
|------------|-------------------------------------------------------------------|
| Language   | Ruby 4.0.1                                                        |
| Framework  | Rails 8.1.2 (API + Hotwire/Turbo 8/Stimulus, Phlex, Tailwind)    |
| Database   | PostgreSQL (4 databases: primary, cache, queue, cable)            |
| Jobs       | Sidekiq (31+ workers, 9 strict-priority queues) + Solid Queue    |
| Cache      | Solid Cache                                                       |
| WebSocket  | Solid Cable (ActionCable)                                         |
| Blockchain | 12-chain: Polygon (primary), Ethereum L1, Solana, Celo, peaq, IoTeX, Chainlink, KlimaDAO, Streamr, Filecoin, The Graph, Polygon Hadron |
| Serializer | Blueprinter                                                       |
| Pagination | Pagy + Groupdate                                                  |
| IoT        | CoAP/UDP listener daemon, LoRaWAN 868 MHz                        |
| Firmware   | C (STM32 HAL) + mruby VM + TinyML (CMSIS-NN)                     |
| Deploy     | Kamal (Docker), Terraform (GCP), Akash Network, Thruster (HTTP/2)|
| Testing    | RSpec, FactoryBot, Capybara, Cuprite, SimpleCov                   |
| Security   | Brakeman, bundler-audit, argon2id, Pundit, rack-attack, AES-256  |
| Monitoring | Prometheus, Sentry, Grafana                                       |
| Storage    | Active Storage (S3 / Google Cloud Storage)                        |

## Directory Structure

```
app/
  controllers/api/v1/   # 28 RESTful API controllers (inherit BaseController)
  models/               # 25 ActiveRecord models
  services/             # 20+ service namespaces (incl. multichain Web3 integrations)
  workers/              # 31+ Sidekiq background workers
  blueprints/           # 8 Blueprinter JSON serializers
  views/components/     # 29 Phlex domain component directories
  views/shared/         # Shared UI (StatusBadge, DataTable, etc.), Web3, IoT components
contracts/              # Solidity: SilkenCarbonCoin.sol, SilkenForestCoin.sol
firmware/
  soldier/main.c        # Tree sensor node firmware (STM32, 648 lines)
  queen/main.c          # LoRa gateway firmware (STM32 + SIM7070G, 550 lines)
  bio_contracts/        # mruby bytecode (Lorenz attractor on-device)
  test/                 # 112 host-based firmware C tests
lib/daemons/            # CoAP UDP listener (port 5683)
spec/                   # RSpec tests (100+ files across 20 directories)
docs/                   # 15 comprehensive .md documentation files
subgraph/               # The Graph subgraph (GraphQL indexing for SCC events)
deploy/                 # Kamal & Akash Network deployment configs
terraform/              # GCP infrastructure-as-code
config/
  sidekiq.yml           # 9 strict-priority queues & cron scheduler
  database.yml          # PostgreSQL multi-database config (4 DBs)
  routes.rb             # API routes (namespace api/v1, 28+ endpoints)
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
- Background job queues (strict priority order): `uplink` > `alerts` = `critical` > `downlink` > `default` > `web3_critical` > `web3` > `web3_low` > `low`

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

- **EBFC (Enzymatic Bio-Fuel Cell)**: harvests >500 mV from tree glucose metabolism via GOx (anode) and Laccase (cathode) enzymes immobilized on Ti-6Al-4V gyroid anchor; powers BQ25570 MPPT → 0.47 F EDLC supercapacitor. The charge time (`delta_t`) is the primary health sensor input to the Lorenz attractor.
- **Soldier**: tree-mounted STM32WLE5JC sensor node with LoRa radio, runs mruby VM and TinyML
- **Queen**: gateway device (STM32 + SIM7070G modem) that collects soldier data and relays to backend via Starlink Direct-to-Cell or LTE
- **Lorenz Attractor**: chaotic dynamical system (σ, ρ, β parameters) used to model tree homeostasis; computed both on-device (mruby) and backend (Ruby) for dual verification
- **DID (Device ID)**: 4-byte hardware identity derived from STM32 UID, provisioned via API
- **Proof of Growth**: trustless consensus pipeline — peaq DID verification → IoTeX W3bstream ZK-proof → Chainlink Oracle → Polygon mint. Trees earn SilkenCarbonCoin (SCC) for verified biomass growth (10,000 growth_points = 1 SCC)
- **Slashing**: automatic token burning if >20% of cluster trees show stress signals
- **NaaS (Nature-as-a-Service)**: business model where organizations subscribe to forest monitoring
- **Parametric Insurance**: automated payouts triggered by catastrophic events (fire >60°C, drought, pest detection)
- **OTA**: over-the-air firmware updates, chunked (512 bytes/chunk, 0.4s pacing), broadcast from queen to soldiers
- **CIFO Cache**: queen-side circular buffer for telemetry batching before CoAP transmission
- **TinyML**: on-device audio classification (chainsaw, fire, woodpecker) using CMSIS-NN, 6-class output

## Sidekiq Queue Hierarchy

| Priority | Queue          | Purpose                                                   |
|----------|----------------|-----------------------------------------------------------|
| 9        | uplink         | Telemetry ingestion (UnpackTelemetryWorker)               |
| 8        | alerts         | EWS alerts, notifications                                 |
| 7        | critical       | Slashing protocol, ecosystem healing, insurance payouts   |
| 6        | downlink       | OTA transmission, actuator commands                       |
| 5        | default        | Aggregation, health checks, standard tasks                |
| 4        | web3_critical  | Time-sensitive blockchain: TX confirmations, minting, Oracle dispatch, ZK verification |
| 3        | web3           | Standard Web3: Celo, Solana, peaq DID                     |
| 2        | web3_low       | Non-critical Web3: L1 anchoring (weekly), KlimaDAO, Hadron|
| 1        | low            | Audit logging, heavy analytics (InsightGenerator)         |

## API Structure

All endpoints are under `/api/v1/` namespace, JSON responses, token-based auth (Bearer).
See `docs/API.md` for the full 28-endpoint reference.

## Testing

- Run all tests: `bundle exec rspec`
- Run specific: `bundle exec rspec spec/models/tree_spec.rb`
- Linting: `bundle exec rubocop`
- Security: `bundle exec brakeman` and `bundle exec bundler-audit check`
- Feature tests: Capybara + Cuprite (headless Chrome)

### ⚠️ MANDATORY: Run RuboCop Before Finishing

**Before completing ANY session, ALWAYS run `bundle exec rubocop` and fix all offenses.**
CI will fail if RuboCop reports any violations. This includes:
- `Layout/SpaceInsideArrayLiteralBrackets` — use `[ item ]` not `[item]`
- `Bundler/OrderedGems` — gems must be sorted alphabetically within each group
- `RSpec/ContextWording` — context descriptions must start with `when`, `with`, or `without`
- `RSpec/DescribeClass` — top-level `describe` must reference a class/module, not a string

Run with auto-correct where possible:
```bash
bundle exec rubocop -A
```

## Documentation Index

| File                             | Content                                              |
|----------------------------------|------------------------------------------------------|
| `README.md`                      | Project overview (Ukrainian)                         |
| `docs/README_EN.md`              | Project overview (English)                           |
| `docs/ARCHITECTURE.md`           | System layers, data flow, multichain integration     |
| `docs/API.md`                    | 28 REST API endpoints reference (v1)                 |
| `docs/MODELS.md`                 | All 25 data models with fields and relationships     |
| `docs/LOGIC.md`                  | 29+ services & 31+ workers reference                 |
| `docs/FIRMWARE.md`               | STM32 firmware specs, binary packet format, mesh     |
| `docs/HARDWARE.md`               | Energy harvesting (EBFC), BOM, schematics            |
| `docs/TOKENOMICS.md`             | SCC/SFC dual-token economy, Proof of Growth          |
| `docs/BLOCKCHAIN_DEVELOPMENT.md` | Web3 dev guide, 12-chain architecture, Foundry       |
| `docs/DEPLOYMENT.md`             | Kamal, Terraform, Akash Network, infrastructure      |
| `docs/VISION.md`                 | Mission, science, roadmap (2026–2030)                |
| `docs/FRONTEND_GUIDELINES.md`    | Phlex components, Tailwind design tokens, Stimulus, accessibility |
| `docs/COMPONENTS.md`             | Shared UI component catalog + Lookbook previews      |
| `docs/OBSERVABILITY.md`          | Prometheus metrics, Grafana dashboards, health checks|
| `docs/GAIA_2_0_ANATOMY.md`      | 12-step cyber-physical state anatomy                 |

### ⚠️ MANDATORY: Read `docs/FRONTEND_GUIDELINES.md` for Frontend Tasks

**When working on ANY frontend task** (Phlex components, Tailwind styling, Stimulus controllers, Turbo integration, view specs), **ALWAYS read `docs/FRONTEND_GUIDELINES.md` first.** It defines:
- Dark-first semantic color tokens (`gaia-*`, `status-*`, `token-*`) — never use raw Tailwind colors in shared UI components
- Phlex component architecture and naming conventions
- TailwindMerge `tokens()` usage pattern
- Typography scale (`text-micro`, `text-mini`, `text-tiny`, `text-compact`)
- Accessibility checklist (roles, aria-labels, focus-visible)
- Lookbook preview conventions

## Environment Setup

### Ruby 4.0.1 (CRITICAL)

The system Ruby in this environment is **NOT** 4.0.1. Ruby 4.0.1 is pre-installed via **hostedtoolcache** at:

```
/opt/hostedtoolcache/Ruby/4.0.1/x64/bin
```

**You MUST add it to PATH before running ANY Ruby, Bundler, Rails, or RSpec command:**

```bash
export PATH="/opt/hostedtoolcache/Ruby/4.0.1/x64/bin:$PATH"
```

Always verify with `ruby --version` — it must output `ruby 4.0.1`. If it shows any other version (e.g. 3.2.x), the PATH is not set correctly and `bundle install` / `bundle exec rspec` will fail with version mismatch errors.

### Migrations & structure.sql

This project uses `db/structure.sql` (not `schema.rb`) because PostgreSQL-specific features (partitioning, PostGIS, triggers) cannot be represented in Ruby DSL.

**When creating or modifying migrations, you MUST:**

1. Run the migration against the **development** database:
   ```bash
   export PATH="/opt/hostedtoolcache/Ruby/4.0.1/x64/bin:$PATH"
   bundle exec rails db:migrate
   ```
2. This regenerates `db/structure.sql`.
3. **Commit `db/structure.sql` alongside the migration file** — CI will fail if structure.sql is out of sync with migrations.

## Important Notes for Copilot

- This is a **Ukrainian-founded** project; comments and README may be in Ukrainian, but code and API are in English.
- The **GitHub Wiki** is the SSOT — consult it for architectural decisions before making changes.
- Ruby version is **4.0.1** — use modern Ruby syntax (pattern matching, numbered block params, `it` keyword, etc.).
- Rails version is **8.1.2** — use Rails 8 conventions (Solid Queue/Cache/Cable, no Redis dependency for queue/cache).
- The project uses **4 separate PostgreSQL databases** (primary, cache, queue, cable) — be aware of `connects_to` in models.
- The **12-chain blockchain architecture** spans Polygon, Ethereum L1, Solana, Celo, peaq, IoTeX, Chainlink, KlimaDAO, Streamr, Filecoin, The Graph, and Polygon Hadron. Web3 services are namespaced under `app/services/`.
- Firmware files in `firmware/` are plain C with STM32 HAL — not managed by Bundler or Rails.
- Solidity contracts in `contracts/` use Foundry toolchain — not managed by Bundler.
- When working with telemetry, remember the **21-byte binary packet format** and AES-256 encryption.
- Background jobs have strict **9-queue priority** — always assign the correct queue to new workers.
- The Lorenz attractor math is critical — σ=10, ρ=28, β=8/3 are defaults, perturbed by sensor readings. BigDecimal with 18-digit precision for legal/financial determinism.
