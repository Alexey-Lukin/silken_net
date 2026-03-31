# Gaia 2.0 Guide for Claude

## Project Context

Silken Net (Gaia 2.0) is a bio-IoT D-MRV platform for planetary-scale forest monitoring. Trees generate energy via EBFC (Enzymatic Bio-Fuel Cell, >500 mV from glucose metabolism), powering STM32WLE5JC sensor nodes that form a LoRa mesh network. Data flows through queen gateways to a Rails 8.1 backend, which runs Lorenz attractor analysis and manages a 12-chain blockchain economy (Polygon, Ethereum L1, Solana, Celo, peaq, IoTeX, Chainlink, KlimaDAO, Streamr, Filecoin, The Graph, Polygon Hadron).

**Single Source of Truth:** The [GitHub Wiki](https://github.com/Alexey-Lukin/silken_net/wiki) is the architectural SSOT. Local `docs/` folder contains complementary reference documentation. Always consult `.cursorrules` for AI behavior rules.

## Environment Setup

**Ruby 4.0.2 is mandatory.** The system Ruby may differ. Always set PATH first:

```bash
export PATH="/opt/hostedtoolcache/Ruby/4.0.2/x64/bin:$PATH"
ruby --version  # Must output: ruby 4.0.2
```

## Frequent Commands

```bash
# Server & development
bundle exec rails s                           # Start Rails server
bin/dev                                       # Start all processes (Rails, Sidekiq, Tailwind, CoAP)
bundle exec sidekiq -C config/sidekiq.yml     # Start Sidekiq worker

# Testing
bundle exec rspec                             # Run full test suite
bundle exec rspec spec/models/tree_spec.rb    # Run specific test file
bundle exec rspec spec/services/              # Run all service tests

# Linting & security (MANDATORY before finishing)
bundle exec rubocop -A                        # Auto-correct RuboCop offenses
bundle exec brakeman                          # Static security analysis
bundle exec bundler-audit check               # Dependency vulnerability scan

# Database (uses structure.sql, NOT schema.rb)
bundle exec rails db:migrate                  # Run migrations (regenerates structure.sql)
bundle exec rails db:test:prepare             # Prepare test database

# Firmware (pure C, not managed by Bundler)
cd firmware && make test                      # Run host-based firmware tests
```

## Coding Standards

- **Language:** English (code, API, variable names). Ukrainian (documentation, comments, README).
- **Framework:** Rails 8.1 Omakase + Phlex UI components + Tailwind CSS (dark-first `gaia-*` design tokens).
- **Architecture pattern:** Thin controllers → Service objects (`app/services/`) → Sidekiq workers (`app/workers/`). No business logic in models.
- **Serialization:** Blueprinter (`app/blueprints/`), not JBuilder or ActiveModelSerializers.
- **Auth:** Token-based (Bearer), argon2id for password hashing, Pundit for authorization.
- **Database:** PostgreSQL with 4 separate databases (primary, cache, queue, cable). Always use `structure.sql`.
- **Background jobs:** 9 strict-priority queues — assign the correct queue: `uplink` > `alerts` = `critical` > `downlink` > `default` > `web3_critical` > `web3` > `web3_low` > `low`.
- **Testing:** RSpec, `let`/`let!`, FactoryBot factories in `spec/factories/`. Capybara + Cuprite for feature tests.
- **Frontend:** Read `docs/FRONTEND_GUIDELINES.md` before any UI work. Use semantic color tokens (`gaia-*`, `status-*`, `token-*`), never raw Tailwind colors in shared components.

## Key Domain Concepts

| Concept | Description |
|---------|-------------|
| **EBFC** | Enzymatic Bio-Fuel Cell — harvests >500 mV from tree glucose via GOx/Laccase enzymes |
| **Soldier** | Tree-mounted STM32WLE5JC sensor node (LoRa, mruby VM, TinyML) |
| **Queen** | LoRa gateway (STM32 + SIM7070G modem) — aggregates and relays to backend |
| **Lorenz Attractor** | σ=10, ρ=28, β=8/3 — 250 iterations, BigDecimal(18) — models tree homeostasis |
| **Proof of Growth** | 10,000 growth_points = 1 SCC token (verified via peaq DID → IoTeX ZK → Chainlink → Polygon) |
| **Slashing** | Auto token burn if >20% cluster trees breach critical_z_min threshold |
| **NaaS** | Nature-as-a-Service — subscription model for forest monitoring contracts |
| **TRL** | Technology Readiness Level (1–9) — NASA standard, used as the sole progress metric |

## Architecture (8 Layers per Wiki SSOT)

```
L8  Ethereum L1          Weekly State Root anchoring (32-byte SHA-256 hash)
L7  Polygon + DeFi       SCC/SFC minting, Solana micro-rewards, Celo ReFi, KlimaDAO ESG
L6  Verification          peaq DID, IoTeX ZK-proofs, Streamr P2P, Filecoin/IPFS archive
L5  Rails Backend         Rails 8.1 API, PostgreSQL, Sidekiq (31+ workers), Prometheus
L4  LoRa Network          868 MHz mesh, CoAP/UDP, Queen gateways, Starlink/LTE
L3  Firmware & Edge AI    STM32WLE5JC, TinyML (CMSIS-NN), mruby Lorenz, AES-256
L2  Hardware Capsule      BQ25570 MPPT, 0.47F EDLC supercapacitor, Pogo Pin blind-mate
L1  Biophysics            Ti-6Al-4V gyroid anchor, EBFC (GOx anode + Laccase cathode)
```

## Documentation Index

| File | Content |
|------|---------|
| `docs/ARCHITECTURE.md` | System layers, data flow, multichain integration |
| `docs/API.md` | 28 REST API endpoints reference (v1) |
| `docs/MODELS.md` | 25 data entity models and relationships |
| `docs/LOGIC.md` | 29+ services & 31+ workers with queue assignments |
| `docs/FIRMWARE.md` | STM32 firmware specs, binary packet format, mesh protocol |
| `docs/HARDWARE.md` | Energy harvesting BOM, EBFC, schematics |
| `docs/TOKENOMICS.md` | SCC/SFC dual-token economy, Proof of Growth |
| `docs/BLOCKCHAIN_DEVELOPMENT.md` | Web3 dev guide, 12-chain architecture, Foundry |
| `docs/FRONTEND_GUIDELINES.md` | Phlex components, Tailwind design system, accessibility |
| `docs/COMPONENTS.md` | Shared UI component catalog + Lookbook previews |
| `docs/OBSERVABILITY.md` | Prometheus metrics, Grafana, health checks |
| `docs/DEPLOYMENT.md` | Kamal, Terraform, Akash Network, infrastructure |
| `docs/GAIA_2_0_ANATOMY.md` | 12-step cyber-physical state anatomy |
| `docs/VISION.md` | Mission, science, roadmap (2026–2030) |
