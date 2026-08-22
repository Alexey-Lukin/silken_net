# 🌿 Silken Net

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/13358/badge)](https://www.bestpractices.dev/projects/13358)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/Alexey-Lukin/silken_net/badge)](https://securityscorecards.dev/viewer/?uri=github.com/Alexey-Lukin/silken_net)

<!-- hero: one representative per macro-layer, bottom-up (tree → blockchain) -->
<p align="center">
  <a href="docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md"><img alt="EBFC >500mV" src="https://img.shields.io/badge/EBFC%20%3E500mV-2E7D32?style=flat-square"></a>
  <a href="docs/02_03_BQ25570_MPPT_Nano_Power.md"><img alt="BQ25570" src="https://img.shields.io/badge/BQ25570-CC0000?style=flat-square"></a>
  <a href="https://www.st.com/en/microcontrollers-microprocessors/stm32wle5jc.html"><img alt="STM32WLE5" src="https://img.shields.io/badge/STM32WLE5-03234B?style=flat-square&logo=stmicroelectronics&logoColor=white"></a>
  <a href="https://lora-alliance.org/"><img alt="LoRa 868" src="https://img.shields.io/badge/LoRa%20868-5BC236?style=flat-square"></a>
  <a href="https://rubyonrails.org/"><img alt="Rails 8.1" src="https://img.shields.io/badge/Rails%208.1-D30001?style=flat-square&logo=rubyonrails&logoColor=white"></a>
  <a href="https://www.peaq.xyz/"><img alt="peaq DID" src="https://img.shields.io/badge/peaq%20DID-FF00A8?style=flat-square"></a>
  <a href="https://polygon.technology/"><img alt="Polygon" src="https://img.shields.io/badge/Polygon-7B3FE4?style=flat-square&logo=polygon&logoColor=white"></a>
  <a href="https://solana.com/"><img alt="Solana" src="https://img.shields.io/badge/Solana-9945FF?style=flat-square&logo=solana&logoColor=white"></a>
  <a href="https://ethereum.org/"><img alt="Ethereum L1" src="https://img.shields.io/badge/Ethereum%20L1-3C3C3D?style=flat-square&logo=ethereum&logoColor=white"></a>
</p>

**Silken Net** is the world's first trustless **D-MRV** (Digital Measurement, Reporting & Verification) platform for planetary-scale forest-health monitoring. Each tree gets a machine identity (peaq DID), becomes an economic agent, and earns carbon tokens (**SCC**) for verified biomass growth.

A titanium gyroid anchor with an enzymatic biofuel cell (EBFC — "zero-grid", >500 mV from xylem sap) powers an STM32 *Soldier* node that senses → runs TinyML → computes a Lorenz-attractor homeostasis signal → encrypts → transmits over LoRa 868 MHz to a *Queen* gateway, which relays via CoAP to a Rails 8 / PostgreSQL / Sidekiq backend and a 12-chain Web3 *Proof-of-Growth* pipeline.

> *"We do not merely watch the forest. We give it a digital will."*

**A note on language.** This README, [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md) are in English; the `docs/` canon is written in Ukrainian, because it is where the engineering thinking actually happens and translating it would put a lossy layer between the author and the decisions. Issues and pull requests in English are welcome.

---

## 📚 Documentation

The canon lives in [`docs/`](docs/) as SSOT documents grouped into modules 00–07, and is mirrored to the GitHub wiki on every push to `main`.

> **Start at [`docs/00_00` — SSOT Index](docs/00_00_SSOT_Index.md):** reading order, the eight-layer system map, and a one-line description of every document. That index is the **single home of the list** — it is deliberately not restated here, so it cannot drift in two places.

- **Module 00 — foundation** (read first): vision and roadmap · AI-native method and NASA TRL · the TRL matrix with HIL simulators · the SSOT documentation standard · the beyond-TRL-9 agenda
- **Modules 01–06 — the system:** anchor and biofuel cell · capsule and gateway hardware · firmware and edge AI · the Rails core · Web3 and economics · deploy and observability
- **Module 07 — the programme:** Nature-as-a-Service contracts · unit economics · academic integration and IP posture

🔴 **Everything still unfinished — including the honest blockers — lives in [`docs/00_07` — Action Plan Tracker](docs/00_07_Action_Plan_Tracker.md).** It is a working document, not a highlight reel: open defects, refused proposals and named ceilings are in it on purpose.

---

## 🌍 The scale we build for

**One trillion trees.** Not "planetary" as a figure of speech — planetary as an order of magnitude: Earth carries roughly three trillion trees, and the design target is that any one of them can hold a machine identity, report on itself, and be paid for verified growth.

That number is a design constraint, not a boast. It is the denominator every architectural decision is divided by — RANGE-partitioned telemetry, strict-priority job queues, per-stream broadcast granularity, the bill of materials for a single node, the energy budget of a sensor that must run for two decades without a wire. A choice that is merely *fine* at ten thousand nodes and quietly quadratic at 10¹² is a defect here, even while it passes every test.

**And the honest half:** today the system stands at **TRL 3**, gated by the anchor and the biofuel cell — in-silico validated, not yet in-vitro; zero nodes in a forest. The trillion is what we are building *toward* and measuring *against*, never a claim about what runs today. Current per-module readiness lives in [`docs/00_03 §1`](docs/00_03_TRL_Matrix_HIL_and_Beyond.md); the scaling phases in [`docs/00_01 §4`](docs/00_01_Vision_Mission_and_Roadmap.md); the beyond-TRL-9 agenda in [`docs/00_01 §4`](docs/00_01_Vision_Mission_and_Roadmap.md).

---

## 🧬 Technology stack — a vertical cut through the trunk

_Bottom-up, the way sap climbs the xylem: from the root inside a living tree (**L1**) to finalisation on Ethereum (**L8**). What each layer means and what gates it — [`docs/00_00` § System Map](docs/00_00_SSOT_Index.md); the current readiness of each module — [`docs/00_03 §1`](docs/00_03_TRL_Matrix_HIL_and_Beyond.md), its single home, deliberately not restated here._

| Layer | Stack |
|:---|:---|
| **L1 · ROOT**<br><sub>Biophysics</sub> | ![Ti-6Al-4V](https://img.shields.io/badge/Ti--6Al--4V-8A8D8F?style=flat-square) ![Gyroid TPMS](https://img.shields.io/badge/Gyroid%20TPMS-556B2F?style=flat-square) ![EBFC >500mV](https://img.shields.io/badge/EBFC%20%3E500mV-2E7D32?style=flat-square) ![PicoGK](https://img.shields.io/badge/PicoGK-6E4B9E?style=flat-square) ![.NET 9](https://img.shields.io/badge/.NET%209-512BD4?style=flat-square&logo=dotnet&logoColor=white) ![AlphaFold 3](https://img.shields.io/badge/AlphaFold%203-2E6FF2?style=flat-square) ![OpenMM](https://img.shields.io/badge/OpenMM-3B7DD8?style=flat-square) ![PySCF](https://img.shields.io/badge/PySCF-1E5C97?style=flat-square) |
| **L2 · CAPSULE**<br><sub>Hardware</sub> | ![BQ25570](https://img.shields.io/badge/BQ25570-CC0000?style=flat-square) ![Supercap 0.47F](https://img.shields.io/badge/Supercap%200.47F-5A6B7B?style=flat-square) ![SIM7070G](https://img.shields.io/badge/SIM7070G-1E88E5?style=flat-square) ![W25Q32](https://img.shields.io/badge/W25Q32-004B87?style=flat-square) ![SE051](https://img.shields.io/badge/SE051-0A6EBD?style=flat-square) |
| **L3 · BRAIN**<br><sub>Firmware + edge AI</sub> | ![STM32WLE5](https://img.shields.io/badge/STM32WLE5-03234B?style=flat-square&logo=stmicroelectronics&logoColor=white) ![SX1262](https://img.shields.io/badge/SX1262-00A3E0?style=flat-square) ![C](https://img.shields.io/badge/C-A8B9CC?style=flat-square&logo=c&logoColor=white) ![mruby](https://img.shields.io/badge/mruby-4A4A4A?style=flat-square) ![Arm CMSIS](https://img.shields.io/badge/Arm%20CMSIS-0091BD?style=flat-square&logo=arm&logoColor=white) ![TensorFlow](https://img.shields.io/badge/TensorFlow-FF6F00?style=flat-square&logo=tensorflow&logoColor=white) ![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white) |
| **L4 · VESSELS**<br><sub>Network</sub> | ![LoRa 868](https://img.shields.io/badge/LoRa%20868-5BC236?style=flat-square) ![LoRaWAN 1.0.4](https://img.shields.io/badge/LoRaWAN%201.0.4-00295B?style=flat-square) ![CoAP](https://img.shields.io/badge/CoAP-2CA5E0?style=flat-square) ![Helium](https://img.shields.io/badge/Helium-0ACF83?style=flat-square&logo=helium&logoColor=white) |
| **L5 · HEARTWOOD**<br><sub>Backend</sub> | ![Ruby](https://img.shields.io/badge/Ruby-CC342D?style=flat-square&logo=ruby&logoColor=white) ![Rails](https://img.shields.io/badge/Rails-D30001?style=flat-square&logo=rubyonrails&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white) ![PostGIS](https://img.shields.io/badge/PostGIS-336791?style=flat-square) ![Sidekiq](https://img.shields.io/badge/Sidekiq-B1003E?style=flat-square&logo=sidekiq&logoColor=white) ![Puma](https://img.shields.io/badge/Puma-343A40?style=flat-square) ![Redis](https://img.shields.io/badge/Redis-FF4438?style=flat-square&logo=redis&logoColor=white) ![Kredis](https://img.shields.io/badge/Kredis-D92D2D?style=flat-square) ![Phlex](https://img.shields.io/badge/Phlex-F0453A?style=flat-square) ![Turbo](https://img.shields.io/badge/Turbo-5CD8E5?style=flat-square&logo=turbo&logoColor=white) ![Stimulus](https://img.shields.io/badge/Stimulus-77E8B9?style=flat-square&logo=stimulus&logoColor=white) ![Tailwind CSS](https://img.shields.io/badge/Tailwind-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white) |
| ⛓ **L6 · CAMBIUM**<br><sub>Verification</sub> | ![peaq](https://img.shields.io/badge/peaq-FF00A8?style=flat-square) ![IoTeX](https://img.shields.io/badge/IoTeX-00C1D4?style=flat-square) ![Streamr](https://img.shields.io/badge/Streamr-FF5C00?style=flat-square) ![Filecoin](https://img.shields.io/badge/Filecoin-0090FF?style=flat-square) ![IPFS](https://img.shields.io/badge/IPFS-65C2CB?style=flat-square&logo=ipfs&logoColor=white) ![The Graph](https://img.shields.io/badge/The%20Graph-6F4CFF?style=flat-square) |
| ⛓ **L7 · CROWN**<br><sub>Finance</sub> | ![Polygon](https://img.shields.io/badge/Polygon-7B3FE4?style=flat-square&logo=polygon&logoColor=white) ![Solana](https://img.shields.io/badge/Solana-9945FF?style=flat-square&logo=solana&logoColor=white) ![Celo](https://img.shields.io/badge/Celo-FCFF52?style=flat-square) ![Chainlink](https://img.shields.io/badge/Chainlink-375BD2?style=flat-square&logo=chainlink&logoColor=white) ![KlimaDAO](https://img.shields.io/badge/KlimaDAO-0AA152?style=flat-square) ![Hadron](https://img.shields.io/badge/Polygon%20Hadron-7B3FE4?style=flat-square) ![Uniswap V3](https://img.shields.io/badge/Uniswap%20V3-FF007A?style=flat-square) ![Gnosis Safe](https://img.shields.io/badge/Gnosis%20Safe-12FF80?style=flat-square) |
| ⛓ **L8 · CANOPY TOP**<br><sub>Finalisation</sub> | ![Ethereum L1](https://img.shields.io/badge/Ethereum%20L1-3C3C3D?style=flat-square&logo=ethereum&logoColor=white) ![Solidity](https://img.shields.io/badge/Solidity-363636?style=flat-square&logo=solidity&logoColor=white) ![Foundry](https://img.shields.io/badge/Foundry-FF8C00?style=flat-square) ![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=flat-square&logo=openzeppelin&logoColor=white) |
| 🌍 **SOIL**<br><sub>DevOps · CI · observability</sub> | ![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white) ![Kamal](https://img.shields.io/badge/Kamal-0E4B6E?style=flat-square) ![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=flat-square&logo=terraform&logoColor=white) ![Google Cloud](https://img.shields.io/badge/Google%20Cloud-4285F4?style=flat-square&logo=googlecloud&logoColor=white) ![Akash](https://img.shields.io/badge/Akash-FF414D?style=flat-square) ![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white) ![Sigstore](https://img.shields.io/badge/Sigstore%2FSLSA-003399?style=flat-square) ![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white) ![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white) ![Sentry](https://img.shields.io/badge/Sentry-362D59?style=flat-square&logo=sentry&logoColor=white) ![RSpec](https://img.shields.io/badge/RSpec-E12C3E?style=flat-square) ![RuboCop](https://img.shields.io/badge/RuboCop-000000?style=flat-square&logo=rubocop&logoColor=white) ![Brakeman](https://img.shields.io/badge/Brakeman-FF6600?style=flat-square) ![Slither](https://img.shields.io/badge/Slither-3B3B3B?style=flat-square) ![Halmos](https://img.shields.io/badge/Halmos-5A4FCF?style=flat-square) |

---

## 🚀 Quick start

### 0. System dependencies

Install these before `bundle install`.

**PostGIS** (required — cluster geometry lives in the database):

```bash
sudo apt-get install -y postgresql-17-postgis-3 postgresql-17-postgis-3-scripts   # Ubuntu / Debian
brew install postgis                                                             # macOS
```

The extension is enabled by `structure.sql` (`CREATE EXTENSION IF NOT EXISTS postgis`), so a normal `db:prepare` needs no manual step.

**A C toolchain** — `rumale` pulls `numo-narray-alt`, which compiles a native extension:

```bash
sudo apt-get install -y build-essential ruby-dev   # Ubuntu / Debian
xcode-select --install                             # macOS
```

### 1. Clone and set up

```bash
git clone https://github.com/Alexey-Lukin/silken_net.git
cd silken_net
bundle install
bin/rails db:prepare
```

### 2. Environment (`.env`)

```bash
cp .env.example .env
```

For local development and simulated telemetry most fields can stay empty — `REDIS_URL` (already in the template) and `WEB3_STRICT_MODE=false` are enough, the latter activating the Web3 stubs so no real keys are needed. Running the full Web3 stack (SCC minting, the Chainlink oracle, Solana micro-payments) needs real credentials; the inventory of which, and where each comes from, is [`docs/06_04` — Secrets Checklist](docs/06_04_Secrets_Checklist.md).

### 3. Run

```bash
bin/dev   # Rails + Sidekiq + Tailwind CSS + CoAP listener
```

### 4. Simulate telemetry (no physical hardware)

```bash
bin/rails db:seed      # Gateway, Tree, HardwareKey, TreeFamily
bin/forest_simulator   # CoAP packets from 5–15 Soldiers every 3–8 s
```

Watch the pipeline:

```bash
bin/rails runner "puts TelemetryLog.count"
open http://localhost:3000/sidekiq
tail -f log/development.log | grep -i telemetry
```

### 5. Tests and quality

```bash
bin/rspec                # full suite
bin/rubocop -a           # linter, safe autocorrect — run before every commit
bin/brakeman             # static security analysis
bin/bundler-audit check  # dependency advisories
```

Smart contracts (Foundry):

```bash
cd contracts
npm ci                           # OpenZeppelin + forge-std
forge build --sizes              # compile, report EIP-170 size
forge test -vvv --gas-report
forge coverage --report lcov     # ≥90% floor, enforced in CI
```

Suites live in `contracts/test/*.t.sol` — unit, Halmos symbolic proofs, Medusa property fuzzing and Foundry stateful invariants. All of them gate merges into `main`.

### 6. Deploy (Kamal)

```bash
kamal setup
kamal deploy
```

> 🔏 **Signed releases.** The production image mirrored to GHCR carries a Sigstore-signed SLSA build-provenance attestation — verify it before pulling, per [`SECURITY.md`](SECURITY.md): `gh attestation verify oci://ghcr.io/alexey-lukin/silken_net:<tag> --owner Alexey-Lukin`.

---

## 🤝 Contributing

Bugs and proposals go through [GitHub Issues](https://github.com/Alexey-Lukin/silken_net/issues); vulnerabilities go **privately**, per [`SECURITY.md`](SECURITY.md) — please do not open a public issue for those. The contribution process (fork → branch → PR), the local checks to run before pushing, and the code requirements are in [`CONTRIBUTING.md`](CONTRIBUTING.md). Issues and pull requests in English are welcome even though the canon is Ukrainian.

---

## 📜 Licence and IP posture

SilkenNet is **mission-first and defensive-publication-first**: we deliberately **do not patent** this work. We publish it as prior art so that it stays free for every forest and **cannot be enclosed** by anyone — including us. The canonical statement of that posture is [`00_01 §8`](docs/00_01_Vision_Mission_and_Roadmap.md); the full map of zones and exceptions is [`NOTICE`](NOTICE).

| Zone | Licence | File |
|------|---------|------|
| **Code** (backend / firmware / tooling / IaC) | **GNU AGPL-3.0-or-later** — per-file SPDX | [`LICENSE`](LICENSE) |
| **Smart contracts** (`contracts/*.sol`) | **MIT** — per-file SPDX (on-chain composability and audit tooling) | [`LICENSE`](LICENSE) |
| **Hardware** (gyroid anchor / EBFC / PCB design) | **CERN-OHL-S-2.0** | [`LICENSE-HARDWARE.txt`](LICENSE-HARDWARE.txt) |
| **Documentation** (`docs/**`) | **CC-BY-SA-4.0** | [`LICENSE-DOCS.txt`](LICENSE-DOCS.txt) |

- **Patent non-assertion pledge.** We neither file nor assert patents; the inventive core is published as a defensive disclosure — [`docs/protocols/anchor/defensive_disclosure.md`](docs/protocols/anchor/defensive_disclosure.md).
- **Third-party exceptions.** AlphaFold 3 outputs (`docs/protocols/ebfc/in_silico/alphafold3/**` and `dgrGcGDH_AF3.pdb`) fall under AF3's own **non-commercial** Terms, **not** CC-BY-SA — see [`NOTICE`](NOTICE). The full dependency inventory is in `THIRD_PARTY_NOTICES`.
- **Trademarks.** SilkenNet™ / GaiaNexus™ / SCC™ are reserved for brand protection and are **not** licensed by any of the above.
