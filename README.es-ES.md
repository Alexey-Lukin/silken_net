

# 🌿 Silken Net

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/13358/badge)](https://www.bestpractices.dev/projects/13358)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/Alexey-Lukin/silken_net/badge)](https://securityscorecards.dev/viewer/?uri=github.com/Alexey-Lukin/silken_net)

<!-- hero: un representante de cada capa macro, de abajo hacia arriba (árbol → blockchain) -->
<p align="center">
  <a href="docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md"><img alt="EBFC >500mV (L1 biofísica)" src="https://img.shields.io/badge/EBFC%20%3E500mV-2E7D32?style=flat-square"></a>
  <a href="docs/02_03_BQ25570_MPPT_Nano_Power.md"><img alt="BQ25570 MPPT (L2 alimentación)" src="https://img.shields.io/badge/BQ25570-CC0000?style=flat-square"></a>
  <a href="https://www.st.com/en/microcontrollers-microprocessors/stm32wle5jc.html"><img alt="STM32WLE5JC (L3 firmware)" src="https://img.shields.io/badge/STM32WLE5-03234B?style=flat-square&logo=stmicroelectronics&logoColor=white"></a>
  <a href="https://lora-alliance.org/"><img alt="LoRa 868 (L4 red)" src="https://img.shields.io/badge/LoRa%20868-5BC236?style=flat-square"></a>
  <a href="https://rubyonrails.org/"><img alt="Rails 8.1 (L5 backend)" src="https://img.shields.io/badge/Rails%208.1-D30001?style=flat-square&logo=rubyonrails&logoColor=white"></a>
  <a href="https://www.peaq.xyz/"><img alt="peaq DID (L6 identidad)" src="https://img.shields.io/badge/peaq%20DID-FF00A8?style=flat-square"></a>
  <a href="https://polygon.technology/"><img alt="Polygon (L7 mint)" src="https://img.shields.io/badge/Polygon-7B3FE4?style=flat-square&logo=polygon&logoColor=white"></a>
  <a href="https://solana.com/"><img alt="Solana (L7 micro-recompensas)" src="https://img.shields.io/badge/Solana-9945FF?style=flat-square&logo=solana&logoColor=white"></a>
  <a href="https://ethereum.org/"><img alt="Ethereum L1 (L8 finalización)" src="https://img.shields.io/badge/Ethereum%20L1-3C3C3D?style=flat-square&logo=ethereum&logoColor=white"></a>
</p>

**Silken Net** es la primera plataforma D-MRV (Medición, Informe y Verificación Digital) *trustless* del mundo para el monitoreo de la salud de los bosques a escala planetaria. Cada árbol obtiene un pasaporte máquina (peaq DID), se convierte en un agente económico y gana tokens de carbono (SCC) por el crecimiento verificado de biomasa.

> *"No solo observamos el bosque. Le otorgamos una voluntad digital."*

---

## 🌐 Resumen

**Silken Net** es la primera plataforma **D-MRV** (Medición, Informe y Verificación Digital) *trustless* del mundo para el monitoreo de la salud de los bosques a escala planetaria. Cada árbol obtiene una identidad de máquina (peaq DID), se convierte en un agente económico y gana tokens de carbono (**SCC**) por el crecimiento verificado de biomasa. Un ancla gyroid de titanio con una celda de combustible bioenzimática (EBFC — "cero red", >500 mV desde la savia del xilema) alimenta un nodo *Soldier* STM32 que capta → ejecuta TinyML → computa una señal homeostática del atractor de Lorenz → cifra → transmite a través de LoRa 868 MHz a una pasarela *Queen*, que reenvía vía CoAP a un backend Rails 8 / PostgreSQL / Sidekiq y una *pipeline* Web3 de 12 cadenas *Proof-of-Growth* (10,000 growth_points = 1 SCC). El resto de este README y el canon de `docs/` se presentan originalmente en ucraniano — los colaboradores en inglés deberían comenzar con [`CONTRIBUTING.md`](CONTRIBUTING.md) y [`SECURITY.md`](SECURITY.md), y son bienvenidos a abrir issues y pull requests en inglés.

---

## 🏛️ Arquitectura (8 Niveles de SilkenNet)

```
L8  Ethereum L1       State root SHA-256 semanal (finalización)
L7  Polygon + DeFi    Ac mintado SCC/SFC, recompensas Solana, Celo ReFi, KlimaDAO ESG
L6  Verificación       peaq DID, pruebas ZK de IoTeX, Streamr P2P, Filecoin/IPFS
L5  Backend Rails     API Rails 8.1, PostgreSQL, Sidekiq (50+ workers)
L4  Red LoRa       868 MHz star-only, CoAP/UDP, pasarelas Queen, Starlink/LTE
L3  Firmware + IA     STM32WLE5JC, TinyML (INT8 pure-C + CMSIS-DSP log-mel), mruby Lorenz, AES-128-ECB/CCM
L2  Cápsula Hardware  BQ25570 MPPT, supercondensador 0.47F, Pogo Pin
L1  Biofísica         Ancla gyroid Ti-6Al-4V, EBFC Gen 2.0 (ánodo dgrFAD-GDH + cátodo Laccase/ZIF-nanozyme)
```

Cada nodo ("Soldier") es un STM32WLE5JC, integrado en un ancla gyroid de titanio dentro del tronco del árbol. La celda de combustible bioenzimática (EBFC) convierte la glucosa de la savia del xilema en >500 mV. La energía carga un supercondensador de 0.47F, que alimenta el microcontrolador. El Soldier clasifica sonidos (TinyML de 5 clases: silencio / viento / sierra / fauna / proxy de estrés hídrico), computa la homeostasis del árbol mediante el Atractor de Lorenz (mruby) y envía paquetes AES-128 de 21 bytes a través de LoRa 868 MHz (star-only — la retransmisión mesh está gateada en la era CCM, el retorno = ARCH.43) a la pasarela "Queen" (el lote CoAP a la nube ya viaja bajo AES-256-CBC).

---

## 🌐 Stack Multicadena (12 Redes)

| Rol | Red | Función |
|------|--------|---------|
| **Identidad** | peaq | Pasaporte Machine DID del árbol |
| **Verificación** | IoTeX W3bstream | Prueba ZK de integridad del pipeline + peaq-DID (L0-custodial; silicon-origin = North-Star) |
| **Oráculo** | Chainlink | CCIP/Functions: Rails → Polygon/Solana |
| **Tokens** | Polygon | SCC (utilitario) + SFC (governance DAO) |
| **Micropagos** | Solana | Recompensas USDC para guardabosques |
| **ReFi** | Celo | Recompensas para comunidades (cUSD) |
| **ESG** | KlimaDAO | Retiro de carbono |
| **KYC/RWA** | Polygon Hadron | Cumplimiento ERC-3643 |
| **Finalización** | Ethereum L1 | State root semanal |
| **Indexación** | The Graph | Subgrafo GraphQL para eventos SCC |
| **Datos P2P** | Streamr | Transmisión en tiempo real de telemetría |
| **Archivo** | Filecoin/IPFS | Almacenamiento perpetuo de logs de auditoría |

---

## 🔗 Proof of Growth — Pipeline

```
EBFC (árbol) → delta_t → Lorenz Z → growth_points → TelemetryLog
    ↓
peaq DID → IoTeX ZK-proof → Chainlink Oracle → Polygon mint(SCC)
    ↓
10 000 growth_points = 1 token SCC
Slashing: solo por negligencia comprobada (cause-gate A/B/C; fuerza mayor → seguro) — 05_05
```

---

## 📖 Capa Lore (Codex)

Sobre el stack operativo funciona **Codex** — una capa narrativa que vincula cada árbol, clúster, alerta y transacción con arquetipos (4 Realms × 79 Nodes), permite a los guardabosques elegir una fracción (`Codex::Fraction`), votar en Battle Arena (Elo) y descubrir Discoveries a medida que el bosque crece. Las reglas de desbloqueo gestionadas por DAO viven en `codex_discovery_rules` y cambian sin redimensionamiento/redeploy. Ningún worker de Codex toca las colas `uplink/alerts/critical/downlink/web3_critical` — la gamificación nunca desprovee de telemetría (ADR-CDX-4). Detalles: [`docs/04_05_Codex_Lore_Module.md`](docs/04_05_Codex_Lore_Module.md).

---

## 🌐 Stakeholders Externos

Además de los socios académicos ([`07_03`](docs/07_03_Academic_Integration_and_IP.md)), el proyecto depende de **stakeholders no operativos** externos: Gatekeepers B2G (el silvicultor Dziubenko, el conservacionista Segeda) — notas en [`07_03`](docs/07_03_Academic_Integration_and_IP.md); metrología (Chorney — certificación SCC) — [`00_07`](docs/00_07_Action_Plan_Tracker.md) § STK.5; capa cultural (artistas de nivel nacional/local para Genesis NFT + Sonificación de Datos) — `docs/cultural_layer.md`. Ninguno de estos registros bloquea un merge — es un pool de outreach que se activa mediante triggers de TRL.

---

## 🧬 Stack Tecnológico — corte vertical del tronco

_De abajo hacia arriba, como la savia en el xilema: desde la raíz en un árbol vivo (**L1**) hasta la finalización en Ethereum (**L8**) — el mismo flujo de datos árbol → blockchain que la [constitución de 8 niveles](#🏛️-архітектура-8-рівнів-silkennet) anterior. La etiqueta `TRL` de cada nivel dice la verdad sobre la madurez del hardware, y no solo «usamos X»._

| Nivel / Capa | Stack / Tecnología |
|:---|:---|
| **L1 · RAÍZ**<br><sub>Biofísica · `TRL 3`</sub> | ![Ti-6Al-4V](https://img.shields.io/badge/Ti--6Al--4V-8A8D8F?style=flat-square) ![Gyroid TPMS](https://img.shields.io/badge/Gyroid%20TPMS-556B2F?style=flat-square) ![EBFC >500mV](https://img.shields.io/badge/EBFC%20%3E500mV-2E7D32?style=flat-square) ![PicoGK](https://img.shields.io/badge/PicoGK-6E4B9E?style=flat-square) ![.NET 9](https://img.shields.io/badge/.NET%209-512BD4?style=flat-square&logo=dotnet&logoColor=white) ![AlphaFold 3](https://img.shields.io/badge/AlphaFold%203-2E6FF2?style=flat-square) ![OpenMM](https://img.shields.io/badge/OpenMM-3B7DD8?style=flat-square) ![PySCF](https://img.shields.io/badge/PySCF-1E5C97?style=flat-square) |
| **L2 · CÁPSULA**<br><sub>Hardware · `TRL 6`</sub> | ![BQ25570](https://img.shields.io/badge/BQ25570-CC0000?style=flat-square) ![Supercap 0.47F](https://img.shields.io/badge/Supercap%200.47F-5A6B7B?style=flat-square) ![SIM7070G](https://img.shields.io/badge/SIM7070G-1E88E5?style=flat-square) ![W25Q32](https://img.shields.io/badge/W25Q32-004B87?style=flat-square) ![SE051](https://img.shields.io/badge/SE051-0A6EBD?style=flat-square) |
| **L3 · CEREBRO**<br><sub>Firmware + Edge-AI · `TRL 6`</sub> | ![STM32WLE5](https://img.shields.io/badge/STM32WLE5-03234B?style=flat-square&logo=stmicroelectronics&logoColor=white) ![SX1262](https://img.shields.io/badge/SX1262-00A3E0?style=flat-square) ![C](https://img.shields.io/badge/C-A8B9CC?style=flat-square&logo=c&logoColor=white) ![mruby](https://img.shields.io/badge/mruby-4A4A4A?style=flat-square) ![Arm CMSIS](https://img.shields.io/badge/Arm%20CMSIS-0091BD?style=flat-square&logo=arm&logoColor=white) ![TensorFlow](https://img.shields.io/badge/TensorFlow-FF6F00?style=flat-square&logo=tensorflow&logoColor=white) ![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white) |
| **L4 · FIBRAS**<br><sub>Red</sub> | ![LoRa 868](https://img.shields.io/badge/LoRa%20868-5BC236?style=flat-square) ![LoRaWAN 1.0.4](https://img.shields.io/badge/LoRaWAN%201.0.4-00295B?style=flat-square) ![CoAP](https://img.shields.io/badge/CoAP-2CA5E0?style=flat-square) ![Helium](https://img.shields.io/badge/Helium-0ACF83?style=flat-square&logo=helium&logoColor=white) |
| **L5 · MADRE**<br><sub>Backend · `TRL 8`</sub> | ![Ruby](https://img.shields.io/badge/Ruby-CC342D?style=flat-square&logo=ruby&logoColor=white) ![Rails](https://img.shields.io/badge/Rails-D30001?style=flat-square&logo=rubyonrails&logoColor=white) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=flat-square&logo=postgresql&logoColor=white) ![PostGIS](https://img.shields.io/badge/PostGIS-336791?style=flat-square) ![Sidekiq](https://img.shields.io/badge/Sidekiq-B1003E?style=flat-square&logo=sidekiq&logoColor=white) ![Puma](https://img.shields.io/badge/Puma-343A40?style=flat-square) ![Redis](https://img.shields.io/badge/Redis-FF4438?style=flat-square&logo=redis&logoColor=white) ![Kredis](https://img.shields.io/badge/Kredis-D92D2D?style=flat-square) ![Phlex](https://img.shields.io/badge/Phlex-F0453A?style=flat-square) ![Turbo](https://img.shields.io/badge/Turbo-5CD8E5?style=flat-square&logo=turbo&logoColor=white) ![Stimulus](https://img.shields.io/badge/Stimulus-77E8B9?style=flat-square&logo=stimulus&logoColor=white) ![Tailwind CSS](https://img.shields.io/badge/Tailwind-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white) |
| ⛓ **L6 · CÁMBIO**<br><sub>Verificación</sub> | ![peaq](https://img.shields.io/badge/peaq-FF00A8?style=flat-square) ![IoTeX](https://img.shields.io/badge/IoTeX-00C1D4?style=flat-square) ![Streamr](https://img.shields.io/badge/Streamr-FF5C00?style=flat-square) ![Filecoin](https://img.shields.io/badge/Filecoin-0090FF?style=flat-square) ![IPFS](https://img.shields.io/badge/IPFS-65C2CB?style=flat-square&logo=ipfs&logoColor=white) ![The Graph](https://img.shields.io/badge/The%20Graph-6F4CFF?style=flat-square) |
| ⛓ **L7 · CROWNA**<br><sub>Finanzas</sub> | ![Polygon](https://img.shields.io/badge/Polygon-7B3FE4?style=flat-square&logo=polygon&logoColor=white) ![Solana](https://img.shields.io/badge/Solana-9945FF?style=flat-square&logo=solana&logoColor=white) ![Celo](https://img.shields.io/badge/Celo-FCFF52?style=flat-square) ![Chainlink](https://img.shields.io/badge/Chainlink-375BD2?style=flat-square&logo=chainlink&logoColor=white) ![KlimaDAO](https://img.shields.io/badge/KlimaDAO-0AA152?style=flat-square) ![Hadron](https://img.shields.io/badge/Polygon%20Hadron-7B3FE4?style=flat-square) ![Uniswap V3](https://img.shields.io/badge/Uniswap%20V3-FF007A?style=flat-square) ![Gnosis Safe](https://img.shields.io/badge/Gnosis%20Safe-12FF80?style=flat-square) |
| ⛓ **L8 · VÉRTICE**<br><sub>Finalización</sub> | ![Ethereum L1](https://img.shields.io/badge/Ethereum%20L1-3C3C3D?style=flat-square&logo=ethereum&logoColor=white) ![Solidity](https://img.shields.io/badge/Solidity-363636?style=flat-square&logo=solidity&logoColor=white) ![Foundry](https://img.shields.io/badge/Foundry-FF8C00?style=flat-square) ![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-4E5EE4?style=flat-square&logo=openzeppelin&logoColor=white) |
| 🌍 **SUELO**<br><sub>DevOps · CI · Observabilidad</sub> | ![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white) ![Kamal](https://img.shields.io/badge/Kamal-0E4B6E?style=flat-square) ![Terraform](https://img.shields.io/badge/Terraform-844FBA?style=flat-square&logo=terraform&logoColor=white) ![Google Cloud](https://img.shields.io/badge/Google%20Cloud-4285F4?style=flat-square&logo=googlecloud&logoColor=white) ![Akash](https://img.shields.io/badge/Akash-FF414D?style=flat-square) ![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-2088FF?style=flat-square&logo=githubactions&logoColor=white) ![Sigstore](https://img.shields.io/badge/Sigstore%2FSLSA-003399?style=flat-square) ![Prometheus](https://img.shields.io/badge/Prometheus-E6522C?style=flat-square&logo=prometheus&logoColor=white) ![Grafana](https://img.shields.io/badge/Grafana-F46800?style=flat-square&logo=grafana&logoColor=white) ![Sentry](https://img.shields.io/badge/Sentry-362D59?style=flat-square&logo=sentry&logoColor=white) ![RSpec](https://img.shields.io/badge/RSpec-E12C3E?style=flat-square) ![RuboCop](https://img.shields.io/badge/RuboCop-000000?style=flat-square&logo=rubocop&logoColor=white) ![Brakeman](https://img.shields.io/badge/Brakeman-FF6600?style=flat-square) ![Slither](https://img.shields.io/badge/Slither-3B3B3B?style=flat-square) ![Halmos](https://img.shields.io/badge/Halmos-5A4FCF?style=flat-square) |

---

## 🚀 Inicio Rápido

### 0. Dependencias del sistema

Antes de `bundle install`, instale los paquetes del sistema.

#### PostGIS (obligatorio para consultas espaciales de clústeres)

**Ubuntu / Debian:**
```bash
sudo apt-get update
sudo apt-get install -y postgresql-16-postgis-3 postgresql-16-postgis-3-scripts
```

**macOS (Homebrew):**
```bash
brew install postgis
```

Tras la instalación, la extensión de PostgreSQL se activa automáticamente a través de `structure.sql` (`CREATE EXTENSION IF NOT EXISTS postgis`). Si crea la base manualmente, ejecute en psql:
```sql
CREATE EXTENSION IF NOT EXISTS postgis;
```

#### numo-narray (gem nativo, requiere compilador)

`rumale` (servicios ML) depende de `numo-narray-alt` — un fork actual de `numo-narray`. La declaración explícita `gem "numo-narray"` **se eliminó** del Gemfile, ya que instalar ambos simultáneamente provoca un conflicto y una advertencia en tiempo de ejecución:

> *'numo-narray-alt' es una implementación alternativa de 'numo-narray'. Tener ambos gems instalados puede provocar conflictos.*

`numo-narray-alt` proporciona una API idéntica (`Numo::DFloat`, `Numo::NArray`, etc.), por lo que no es necesario cambiar nada en el código.

Ambos gems compilan extensiones C nativas, por lo que se necesitan herramientas de compilación:

**Ubuntu / Debian:**
```bash
sudo apt-get install -y build-essential ruby-dev
```

**macOS (Homebrew):**
```bash
xcode-select --install   # o: brew install gcc
```

Tras esto, un `bundle install` normal funcionará sin errores.

---

### 1. Clonación y configuración

```bash
git clone https://github.com/Alexey-Lukin/silken_net.git
cd silken_net
bundle install
bin/rails db:prepare
```

### 2. Variables de entorno (`.env`)

Antes del primer inicio, copie la plantilla y complete los valores necesarios:

```bash
cp .env.example .env
```

Para desarrollo local y simulación de telemetría, es suficiente dejar la mayoría de los campos vacíos — conjunto mínimo:

| Variable | Descripción |
|--------|------|
| `REDIS_URL` | `redis://localhost:6379/0` (Sidekiq, ya está en la plantilla) |
| `WEB3_STRICT_MODE` | `false` — establos Web3 activos, no se necesitan claves reales |

Para un stack Web3 completo (mintado SCC, oráculo Chainlink, micropagos Solana) es necesario completar:
`CHAINLINK_FUNCTIONS_ROUTER`, `CHAINLINK_HMAC_SECRET`, `CHAINLINK_SUBSCRIPTION_ID`, `SOLANA_WALLET_KEYPAIR`, `PROVISIONING_MASTER_KEY`.
Detalles en [`docs/06_01_Deployment_Kamal_Terraform.md`](docs/06_01_Deployment_Kamal_Terraform.md).

### 3. Inicio

```bash
bin/dev   # Rails + Sidekiq + Tailwind CSS + listener CoAP
```

### 4. Simulación de telemetría (sin hardware físico)

```bash
bin/rails db:seed      # Gateway, Tree, HardwareKey, TreeFamily
bin/forest_simulator   # Genera paquetes CoAP de 5–15 Soldiers cada 3–8 seg
```

Monitoreo del pipeline:
```bash
rails runner "puts TelemetryLog.count"
open http://localhost:3000/sidekiq
tail -f log/development.log | grep -i telemetry
```

### 5. Pruebas y calidad

```bash
bundle exec rspec                # Conjunto completo de pruebas
bundle exec rubocop -A           # Linter (obligatorio antes de commit)
bundle exec brakeman             # Análisis estático de seguridad
bundle exec bundler-audit check  # Vulnerabilidades de dependencias
```

### 5.1. Smart Contracts (Foundry)

```bash
cd contracts
npm ci                           # Instalar OZ + forge-std
forge build --sizes              # Compilación + tamaño de contratos
forge test -vvv --gas-report     # Pruebas con reporte de gas
forge coverage --report summary  # Cobertura (análogo a SimpleCov)
forge coverage --report lcov     # lcov.info (artefacto coverage de CI, ≥90% floor)
```

Archivos de prueba: `contracts/test/*.t.sol` (6 contratos; unit + Halmos symbolic + Medusa fuzz + Foundry invariant, ≥90% coverage-floor).

### 6. Despliegue (Kamal)

```bash
kamal setup
kamal deploy
```

> 🔏 **Lanzamientos firmados:** la imagen de producción espejada en GHCR lleva una certificación de procedencia de compilación SLSA firmada por Sigstore: verifíquela antes de hacer pull según [`SECURITY.md`](SECURITY.md) (`gh attestation verify oci://ghcr.io/alexey-lukin/silken_net:<tag> --owner Alexey-Lukin`).

---

## 📡 Identificadores de Nodos

| Tipo | Formato | Ejemplo |
|-----|--------|---------|
| Soldier (Tree DID) | `SNET-XXXXXXXX` | `SNET-1A2B3C4D` |
| Queen (Gateway UID) | `SNET-Q-XXXXXXXX` | `SNET-Q-5E6F7A8B` |

---

## ⛓️ Tokenomics

**SCC (Silken Carbon Coin)** — token ERC-20 utilitario por secuestro de CO₂ verificado.
- 10 000 `growth_points` = 1 SCC
- Slashing: por degradación por **negligencia** (cause-gate A/B/C — la fuerza mayor está cubierta por seguro); cluster-trigger >20% de árboles con `stress_index ≥ 1.0`. Política → [`05_05`](docs/05_05_Slashing_and_Risk_Policy.md)
- MAX_SUPPLY: 1 mil millones de SCC

**SFC (Silken Forest Coin)** — ERC-20 de governance + Votes (EIP-712) para votación DAO.
- MAX_SUPPLY: 100 millones de SFC
- Soporta transacciones sin gas mediante permit EIP-712

**Governance DAO** ([`05_06`](docs/05_06_Governance_and_DAO.md)) — los holders de SFC votan cambios en los parámetros del protocolo:
- `SilkenGovernor.sol` — OZ Governor + GovernorVotes (defensa snapshot) + 48h Timelock
- `SilkenTimelock.sol` — TimelockController con un retraso mínimo de 48h
- `ProtocolParameters.sol` — registro on-chain (17 claves well-known: 8 Lorenz DCI-locked + 9 económicas tokenomics/slashing)
- `StateRootAnchor.sol` — finalización semanal del state root en Ethereum L1

Todos los contratos: `contracts/*.sol`, pruebas: `contracts/test/*.t.sol` (Foundry)

---

## 🔐 Seguridad del Firmware

- **RDP (Readout Protection):** objetivo **Nivel 2** — bloqueo hardware irreversible de la memoria STM32, paso final antes del primer lote en el bosque; estado actual = Nivel 0 (desarrollo), seguimiento `SEC.2`
- **AES-128 (transicional ECB → CCM):** **telemetría LoRa** cifrada con clave de sesión per-device (KEYL, HKDF); **control-plane** (downlink OTA/beacon/CMD) — con clave de clúster compartida KEYB. Magistral CoAP Queen↔Rails — AES-256-CBC.
- **Claves Zero-Trust:** todas las claves AES se derivan vía HKDF desde el master-seed de Protected-Flash y **no salen del proceso Ruby** en texto claro (LRU in-process, sin serialización Redis)
- **Actualizaciones OTA:** paquetes de firmware (512 bytes/chunk) se segmentan + CRC16/32 + HMAC-SHA256 en `OtaPackagerService`, cifrados con AES-256-CBC en `OtaTransmissionWorker`

---

## 📚 Documentación

Documentación detallada en el directorio [`docs/`](docs/):

### 🧭 Módulo 00 — Fundación (Foundation: Visión + Método — leer primero)
- [`00_00`](docs/00_00_SSOT_Index.md) — índice SSOT + mapa del sistema (8 niveles de ciberfísica) + orden de lectura
- [`00_01`](docs/00_01_Vision_Mission_and_Roadmap.md) — visión, misión, hoja de ruta, NaaS, Proof-of-Growth (Slashing → [`05_05`](docs/05_05_Slashing_and_Risk_Policy.md))
- [`00_02`](docs/00_02_AI_Native_Engineering_and_TRL.md) — filosofía AI-Native: TRL de NASA, Intent-First, Wiki-First, Validation Gate
- [`00_03`](docs/00_03_TRL_Matrix_HIL_and_Beyond.md) — matriz TRL por módulo + TRL por dominio + simuladores HIL (Beyond-TRL-9 → `00_08`)
- [`00_04`](docs/00_04_Shape_Up_Operations_and_RnD_Clusters.md) — ciclos Shape Up 6+2, 4 clústeres R&D, Betting Table, Async-Review
- [`00_05`](docs/00_05_GitHub_Projects_and_IaC_Automation.md) — Projects V2 + Labels-as-Code + workflows GitHub Actions
- [`00_06`](docs/00_06_SSOT_Documentation_Standard.md) — estándar de docs canónicos (esqueleto + registro doméstico + herramientas de drift + método de reestructuración)
- [`00_07`](docs/00_07_Action_Plan_Tracker.md) — 🔴 tracker vivo de tareas pendientes (auditoría DOC/SW/SEC/ARCH/UNI)
- [`00_08`](docs/00_08_Beyond_TRL9_Planetary_Roadmap.md) — Beyond TRL 9: Brechas de Inteligencia Planetaria + topología de red fractal (I+D de horizonte lejano 2026–2040+)

### 🏛️ Tier I — Sistema (01–06)

**Biomecánica y Química (Módulo 01)**
- [`01_01`](docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md) — ancla Ti-6Al-4V de 3 componentes
- [`01_02`](docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) — metalurgia Ti-6Al-4V, DMLS y biocompatibilidad
- [`01_03`](docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) — EBFC Gen 2.0: >500 mV de la glucosa del árbol (dgrFAD-GDH + Laccase/ZIF + Genipin + PSBMA, 20–25 años)
- [`01_04`](docs/01_04_CODIT_and_Xylemointegration.md) — CODIT y xilemointegración

**Hardware (Módulo 02)**
- [`02_01`](docs/02_01_Hardware_Architecture_and_BOM.md) — BOM y arquitectura del Soldier
- [`02_02`](docs/02_02_Blind_Mate_Pogo_Pin_Interface.md) — conector ciego Pogo Pin
- [`02_03`](docs/02_03_BQ25570_MPPT_Nano_Power.md) — BQ25570 MPPT, gestión de energía nano + búfer EDLC 0.47F (§12)
- [`02_04`](docs/02_04_Bench_Build_Guide.md) — 🔧 Guía de Construcción y Prueba en Banco (Soldier+Queen por bloques en protoboard)
- [`02_05`](docs/02_05_Queen_Hardware_and_Starlink.md) — pasarela Queen + Starlink/LTE

**Firmware y Edge AI (Módulo 03)**
- [`03_01`](docs/03_01_Firmware_Lifecycle_and_DMA.md) — ciclo del Soldier: STOP2 → sensores → TX LoRa
- [`03_02`](docs/03_02_Queen_Gateway_Firmware.md) — firmware de la pasarela Queen (RX LoRa → CIFO → CoAP)
- [`03_03`](docs/03_03_TinyML_Acoustic_Inference.md) — TinyML: clasificación acústica de sierras
- [`03_04`](docs/03_04_mruby_Lorenz_Attractor.md) — mruby Atractor de Lorenz (homeostasis del árbol)
- [`03_05`](docs/03_05_Hardware_Symmetric_Crypto_and_Security.md) — cifrado simétrico por hardware (LoRa AES-128-CCM, CoAP AES-256-CBC) y hoja de ruta migración PQC
- [`03_06`](docs/03_06_Factory_Flashing_and_Key_Provisioning.md) — Flashing de fábrica y aprovisionamiento de claves (HKDF · K_seed · OTA-HMAC · seguridad factory-ops)

**Núcleo Servidor (Módulo 04)**
- [`04_01`](docs/04_01_Data_Models_and_Entities.md) — modelos ActiveRecord, esquema PostgreSQL, particionamiento
- [`04_02`](docs/04_02_Business_Logic_and_Services.md) — Service Objects + workers Sidekiq, Web3CircuitBreaker
- [`04_03`](docs/04_03_REST_API_v1_Reference.md) — REST API v1 (Pagy, Idempotency-Key, RBAC)
- [`04_04`](docs/04_04_Phlex_UI_and_Tailwind.md) — sistema de diseño Phlex + Tailwind
- [`04_05`](docs/04_05_Codex_Lore_Module.md) — Codex — capa narrativa read-only opcional sobre telemetría (fixado por ADR, fuera del hot-path)
- [`04_06`](docs/04_06_Testing_Guide_and_Coverage.md) — Guía de pruebas (mejores prácticas RSpec/Phlex) + Análisis de Brechas (limitaciones conocidas + recomendaciones)

**Web3 y Economía (Módulo 05)**
- [`05_01`](docs/05_01_Multichain_Architecture.md) — Core DePIN (peaq/IoTeX/Chainlink/Polygon) + ecosistema de expansión
- [`05_02`](docs/05_02_Proof_of_Growth_Pipeline.md) — pipeline completo de Proof of Growth
- [`05_03`](docs/05_03_Tokenomics_SCC_and_SFC.md) — tokenomics SCC/SFC
- [`05_04`](docs/05_04_Ethereum_L1_State_Anchor.md) — finalización semanal en Ethereum L1
- [`05_05`](docs/05_05_Slashing_and_Risk_Policy.md) — política de penalizaciones y riesgos (negligencia/fuerza mayor + fórmula + seguro + anti-fraude + de-risk multi-signal)
- [`05_06`](docs/05_06_Governance_and_DAO.md) — governance on-chain (SilkenGovernor + Timelock + ProtocolParameters + protección Flash-Loan + Auto-Immune Sentinel)

**Despliegue e Infraestructura (Módulo 06)**
- [`06_01`](docs/06_01_Deployment_Kamal_Terraform.md) — Kamal + Terraform (GCP) + ENV Web3
- [`06_02`](docs/06_02_Akash_Network_Integration.md) — nube descentralizada Akash
- [`06_03`](docs/06_03_Prometheus_Observability.md) — Prometheus + Grafana + Sentry
- [`06_04`](docs/06_04_Secrets_Checklist.md) — inventario de secretos (GitHub Secrets, Kamal, Akash, Terraform)
- [`06_05`](docs/06_05_Puma_Configuration.md) — Puma 8: pool de hilos IO-bound, debug de apagado, hooks de clúster
- [`06_06`](docs/06_06_Disaster_Recovery_and_Backup.md) — Recuperación ante Desastres + postura de backup + RTO/RPO + runbooks de restauración
- [`06_07`](docs/06_07_CICD_and_Runbook_Index.md) — workflows CI/CD + índice unificado de runbooks de operaciones
- [`06_08`](docs/06_08_Resilience_and_Failover_Policy.md) — failover Queen 4 niveles + Matriz Fallback por Cadena

### 🌿 Tier II — Programa (07)

**Ecosistema y Partnerships / Ecosystem & Partnerships (Módulo 07)**
- [`07_01`](docs/07_01_Nature_as_a_Service_Contracts.md) — Contratos NaaS y seguros
- [`07_02`](docs/07_02_Unit_Economics_and_BOM.md) — economía unitaria y ROI vía SCC
- [`07_03`](docs/07_03_Academic_Integration_and_IP.md) — Integración académica: registro de 5 universidades + publicaciones conjuntas + postura IP + marca

---

## 📊 Estado Actual (Matriz TRL)

| Subsistema | TRL | Estado |
|------------|-----|--------|
| Backend Rails (API, servicios, workers) | 8 | Production Ready |
| Smart Contracts (SCC/SFC) | 8 | Listo para TRL 9 (Slither/Halmos/Medusa limpios; despliegue mainnet pendiente) |
| Tokenomics y Proof of Growth | 8 | Production Ready |
| REST API (82 endpoints) | 8 | Production Ready |
| UI Phlex + sistema de diseño Tailwind | 8 | Production Ready |
| Firmware Soldier (C + mruby + TinyML) | 6 | Pruebas basadas en host aprobadas |
| Firmware Queen (C + SIM7070G) | 6 | Pruebas basadas en host aprobadas |
| Cápsula hardware (BOM, MPPT) | 6 | Arquitectura congelada |
| Ancla gyroid Ti-6Al-4V | 3 | In-silico: generación PicoGK Code-as-CAD + ajuste por presión Lamé (seguridad 9.9×; nTop = referencia opcional); lote físico DMLS = TRL 4 |
| EBFC Gen 2.0 (dgrFAD-GDH + Laccase/ZIF) | 3 | **Zero-Lab L1-L4 PASSED** (in-silico = TRL 3; physical TRL 4 = in-vitro Ti-coin; ver `docs/protocols/ebfc/in_silico/SUMMARY.md`) |
| Red académica (ЧНУ+ФОТІУС/ЧДТУ/ЧІПБ/ЧМА/СЄУ) | 2 | 5 universidades socio, 8 artículos Q1 activos (portafolio UNI.19) |
| Despliegue GCP + Kamal | 4 | El código existe, el deploy no se ha realizado |

---

## 🌍 Escala

El sistema está diseñado para **millones → miles de millones → billones** de árboles en todo el mundo. Cada decisión arquitectónica — desde el particionamiento de PostgreSQL hasta las colas de Sidekiq — está calculada para escala planetaria.

---

## 🤝 Contribuciones (Contributing)

Errores y sugerencias a través de [GitHub Issues](https://github.com/Alexey-Lukin/silken_net/issues); vulnerabilidades de forma privada según [`SECURITY.md`](SECURITY.md). El proceso de contribución (fork → branch → PR), verificaciones locales y requisitos de código están en [`CONTRIBUTING.md`](CONTRIBUTING.md).

---

## 📜 Licencia y Postura IP

SilkenNet es **mission-first, defensive-publication-first**: **no patentamos** este trabajo, sino que lo publicamos como prior art para que permanezca libre para todos los bosques y **no pueda ser capturado**. La postura canónica — [`07_03 §3`](docs/07_03_Academic_Integration_and_IP.md); mapa completo de zonas y excepciones — [`NOTICE`](NOTICE).

| Zona | Licencia | Archivo |
|------|----------|------|
| **Código** (backend / firmware / tooling / IaC) | **GNU AGPL-3.0-or-later** — SPDX por archivo | [`LICENSE`](LICENSE) |
| **Smart Contracts** (`contracts/*.sol`) | **MIT** — SPDX por archivo (composabilidad on-chain / herramientas de auditoría; ratificado DOC-T.47) | [`LICENSE`](LICENSE) |
| **Hardware** (gyroid / EBFC / diseño PCB) | **CERN-OHL-S-2.0** | [`LICENSE-HARDWARE.txt`](LICENSE-HARDWARE.txt) |
| **Documentación** (`docs/**`) | **CC-BY-SA-4.0** | [`LICENSE-DOCS.txt`](LICENSE-DOCS.txt) |

- **Compromiso de no assertación de patentes:** no presentamos ni assertamos patentes; el núcleo inventivo se publica como defensive disclosure — [`docs/protocols/anchor/defensive_disclosure.md`](docs/protocols/anchor/defensive_disclosure.md).
- **Excepciones de terceros:** salidas de AlphaFold 3 (`docs/protocols/ebfc/in_silico/alphafold3/**` + `dgrGcGDH_AF3.pdb`) — bajo sus propios Términos **non-commercial** de AF3, **no** CC-BY-SA (ver [`NOTICE`](NOTICE)). Inventario completo de dependencias — `THIRD_PARTY_NOTICES`.
- **Marcas comerciales** SilkenNet™ / GaiaNexus™ / SCC™ — reservadas (protección de marca), no se licencian arriba.
