# The Forest Has Something to Say

## A Manifesto for Cyber-Physical D-MRV and the End of the Green Pixel

*From the Silken Net research collective.*

---

### 1. The Paradigmatic Crisis of Modern Ecological Monitoring

The global Voluntary Carbon Market (>$2B annually) currently rests on a single, increasingly untenable assumption: that the **presence of biomass**, as inferred remotely from satellite multispectral indices (NDVI, EVI, LAI, SAR backscatter), is a sufficient proxy for **ecosystem function**.

It is not.

A "green pixel" cannot distinguish:

- a living, transpiring, carbon-fixing canopy from a senescent monoculture entering chronic decline;
- a healthy mixed-species stand from a plantation already cavitating under drought-induced hydraulic stress;
- a recovering ecosystem from one whose mycorrhizal substrate has collapsed;
- a real forest from a forest that *was* photographed on a single cloud-free day in 2019 and has since been quietly logged.

The result is a Measurement, Reporting, and Verification (MRV) regime that is **slow, expensive, manually audited, structurally vulnerable to double-counting, and trivially gameable by greenwashing**. Every credible exposé of the carbon-credit industry over the past three years has hit the same underlying nerve: there is no continuous, tamper-evident, **physical** ground truth between the satellite and the smart contract.

We cannot fix the carbon market by tightening the auditor's checklist. The instrumentation itself is wrong.

---

### 2. The Autonomous Metabolic Oracle (Silken Net)

Silken Net proposes a paradigm inversion: from **external deduction** (we look at the forest from orbit) to **internal induction** (the forest tells us how it feels, continuously, in cryptographically signed packets).

Each node in the network is an **Autonomous Metabolic Oracle** — a sensor surgically integrated with the vascular system of a single tree, performing in-situ measurement of physiological state at the metabolic level. The architecture rests on four load-bearing innovations: a power source that draws from tree metabolism, a surgical interface that the tree accepts rather than rejects, a chaotic transform that makes each reading **unforgeable** on a microwatt budget, and an Edge-AI acoustic layer that lets the forest call for help.

#### 2.1. Energetic Autonomy via Enzymatic Bio-Fuel Cells (EBFC, Gen 2.0)

The node is **powered by the tree itself**. No batteries, no solar harvesters, no grid — and no scheduled maintenance for the operational lifetime of the host organism (20–25 years).

The power source is a **tri-zone coaxial anchor** manufactured from Ti-6Al-4V via DMLS (Direct Metal Laser Sintering) with HIP post-processing. The geometry is not arbitrary:

- **Zone 1 (anode, gyroid lattice in the sapwood):** an open triply-periodic minimal surface (~65% porosity) implanted in the xylem-conducting layer. Its catalytic surface carries **deglycosylated FAD-dependent glucose dehydrogenase (dgrFAD-GDH)** expressed recombinantly in *Pichia pastoris* and post-translationally deglycosylated to shorten the electron-transfer distance to an osmium-bipyridyl redox polymer mediator. We deliberately do *not* use GOx — its H₂O₂ byproduct triggers the tree's CODIT defense cascade and shortens lifetime to 3–5 years. FAD-GDH produces **no peroxide, no oxygen dependence, no immunological signal**.
- **Zone 2 (PEEK thermal break):** an insulating polymer interlayer that prevents short-circuiting between anode and cathode and breaks the bulk thermal bridge that would otherwise carry boundary-layer condensation deep into the trunk (a thin residual remains via the central bus — minimized by a monolithic low-λ conductor; spec 01_01 §1.4).
- **Zone 3 (cathode flange, bark–air interface):** a Laccase / nCoCuCeZIF hybrid bio-inorganic catalyst performing four-electron oxygen reduction (ORR) on atmospheric O₂, gated by a PTFE gas-diffusion layer. The ZIF nanozyme component is **chloride-tolerant** (laccase alone loses 41.7% activity at 0.25 M NaCl; the hybrid *gains* 7.5%) and continues to function as a non-enzymatic backup catalyst should the natural enzyme denature after a decade in service.

The enzymatic stack is immobilized in a **Genipin-crosslinked chitosan-CNC matrix** — genipin being a natural aglycone from *Gardenia jasminoides* that replaces glutaraldehyde, whose trace leachate induces local parenchyma necrosis and triggers the very immune cascade the geometry is engineered to avoid. The whole assembly is protected by a **Nafion-g-PSBMA zwitterionic anti-fouling membrane** synthesized via surface-initiated ATRP grafting.

Result: a sustained open-circuit voltage above 500 mV, sufficient to feed a TI BQ25570 nano-power MPPT harvester (cold-start threshold 330 mV) buffering into a 0.47 F supercapacitor — which in turn drives an STM32WLE5JC microcontroller running an mruby virtual machine in STOP2 mode at single-digit microamps.

The forest powers its own observation.

#### 2.2. Xylemointegration: The Tree Accepts the Implant

Trees do not heal wounds — they wall them off. The CODIT response (Compartmentalization of Decay In Trees) is a four-barrier reflex that surrounds any foreign body in resin, phenolics, and necrotic tissue until it is mechanically extruded over years. A conventional probe screwed into a trunk is a probe with a five-year warranty at best, after which it is suffocating in resinosis.

Silken Net is designed for the inverse outcome — **xylemointegration**, the botanical analogue of osseointegration. The macroporous gyroid (60–70% void fraction, ~300–500 µm pore size in pine) is not a barrier; it is a *scaffold*. After an initial defense phase, undifferentiated callus cells migrate *into* the lattice. Within 1–3 years they differentiate into functional xylem and phloem, and sap begins to flow *through* the implant by natural capillarity. The tree no longer treats the anchor as a foreign body. It treats it as a mineralized knot.

Two physical details make this possible:

- **Flush Mount + Microfrezing surgical installation:** the cathode flange is recessed flush with the bark surface using step-drilled microfresing — not auger-bit drilling. Augers *tear* the cambium and trigger massive resinosis; precision microfresing *cuts*, preserving the living tissue layer. The cambium is never compromised, and there is no protruding hardware to act as a moment arm in high wind.
- **Anti-overgrowth shield over the cathode:** Zone 1 (the anode) must be overgrown — that is how sap reaches the enzymes. Zone 3 (the cathode), however, requires permanent atmospheric O₂ access for the four-electron ORR reaction. A physical anti-overgrowth shield prevents callus from sealing the gas-diffusion layer. The forest grows around the implant, but never closes the window.

This is what we mean when we say the architecture is **symbiotic** rather than **invasive**: we are not extracting from the tree. We are joining its vascular system on terms it accepts.

#### 2.3. The Lorenz Attractor — an Integrity Seal, not a Diagnosis

A reading is worth nothing if it can be forged. The hardest problem in monitoring a forest is not reading the tree — it is **proving that the reading came from the tree**, and that nobody rewrote it on the way.

On-device, an **mruby Bio-Contract** integrates a Lorenz attractor for 250 Euler steps at every wake-up cycle. The Lorenz parameters **σ and ρ** are **parametrically perturbed by physiologically meaningful inputs** (β stays fixed — see below):

- **σ** is modulated by the TinyML acoustic event score,
- **ρ** by the xylem temperature gradient,
- **β** is FIXED at `8/3` ([E.63] — β no longer carries metabolism: it does not move the Lorenz z-fixed-point `z_eq=ρ−1`, so the old `delta_t`/`vcap`→β coupling proved economically null/inverted). EBFC metabolic vigor (`delta_t_s` recharge time) now drives `growth_points` **directly** via a monotonic `metabolic_health(delta_t)` (03_04 §4.3), decoupled from the chaotic attractor.

The Z-coordinate of the final point gates the tree into one of three homeostatic regimes — a *status* classifier, not a reward function:

| Z range | Homeostatic status |
|---|---|
| Z < 2 | stress (turgor collapse) |
| 2 ≤ Z ≤ ρ-relative ceiling (≈ 45 at ρ = 28) | homeostasis |
| Z > ceiling | anomaly |

Token magnitude is deliberately **decoupled** from this chaotic classifier. In homeostasis, `growth_points` scale with a monotonic function of EBFC metabolic vigor — the `delta_t` supercapacitor recharge time, a direct physical proxy for xylem metabolism — not with Z; stress caps emission at the floor, anomaly zeroes it. ⚠️ **What the attractor does *not* do is diagnose.** An earlier revision of this manifesto said it decides *whether* a tree is healthy. We measured that claim and withdrew it on 2026-09-05: the transform is a deterministic function of inputs the verifier already holds, so by the data-processing inequality it cannot carry information about physiology beyond them. Health must come from **direct** signals — metabolic recharge time, sap flow, vapour-pressure deficit, acoustics. Where we do not yet have the instrument, we say so plainly rather than let the mathematics stand in for it: today the drought peril has **no automatic machine witness at all**, and an empty screen means *nobody measured*, never *nothing is wrong*. (An earlier design keyed emission magnitude to Z directly; empirical testing on the real bio-contract showed that path economically degenerate and temperature-confounded — so the attractor was narrowed to the one role it does load-bearingly well: Dual Computation Integrity, below. The anomaly ceiling is likewise ρ-relative, so a warm day no longer trips a false anomaly.)

The choice of a deterministic chaotic system is not aesthetic. It is the **smallest mathematical object whose output is highly sensitive to physiological inputs yet computationally tractable on a sub-mW microcontroller**, and whose trajectory between cycles can be **continued losslessly** through STOP2 sleep via three RTC backup registers. Server-side, the same `SilkenNet::Attractor` mirror computes Z in IEEE-754 float — bit-identical to firmware across 10,000 coupled mruby-VM↔CRuby parity cases, with the ARM leg closed by QEMU byte-parity. Initial state on cold start is derived from a per-device `K_seed` via HKDF + HMAC-SHA256, eliminating the "identifier-as-key" antipattern; warm continuation reads `(x, y, z)` from the previous packet's persisted tail.

Any divergence between device-computed Z and server-recomputed Z raises a fraud flag. We call this **Dual Computation Integrity**. Today the categorical check is live; the numeric tolerance band (an absolute ε, not a percentage) ships feature-flagged off until the wire carries raw device-Z, and minting is deliberately optimistic. The designed enforcement arm is ex-post reconciliation and clawback — and it is **not built yet**; what actually limits the blast radius today is an aggregate mint-volume detector. We say this plainly because the distinction between *built* and *designed* is the whole point of §5, and it would be self-refuting to blur it here.

#### 2.4. Acoustic Biodiversity Diagnostics (Edge AI)

A piezoelectric pickup mounted on the trunk and sampled at 16 kHz via DMA feeds a classifier through a CMSIS-DSP log-mel front-end. What actually landed is not the convolutional network the literature would reach for: it is a per-frame INT8 fully-connected net, 40 log-mel bins → 16 hidden → 5 classes, running as a self-contained integer forward pass with no TFLite-Micro and no CMSIS-NN. Its weights occupy under a kilobyte of Flash and its activations 76 bytes of stack — against the ~16 KB tensor arena a textbook ESC-CNN would demand, which at this power and RAM budget does not physically deploy. We report the architecture we shipped rather than the one that would sound more impressive. The model discriminates between **anthropogenic threat signatures** (chainsaw, vehicle ingress), the **faunal soundscape** (a proxy for biodiversity), a low-frequency **water-stress proxy**, and silence. (True ultrasonic acoustic-emission detection of xylem cavitation — physically 25–150 kHz, Tyree & Dixon 1983 — is a roadmap item requiring a dedicated high-rate channel, not the current 16 kHz audible chain; the water-stress class today is a low-frequency structural proxy, not the ultrasonic AE signal itself.)

Raw audio never leaves the device. Only the classification label and confidence — a single byte — is packed into the LoRa frame. A chainsaw class above the OTA-tunable confidence threshold triggers an **emergency panic frame** that jumps the network's normal duty cycle: the node transmits immediately rather than waiting hours for its next scheduled wake. The topology is deliberately **star-only** — every Soldier speaks straight to its Queen gateway. The multi-hop TTL flood the panic frame still carries in its header (`PANIC_TTL = 5`) is a road not taken: it belongs to the transitional ECB era, and the CCM cutover lands before first field deployment, so no forest will run it. Neighbour-relayed alerts (and the Queen-to-Queen backhaul) are roadmap, not shipping.

This is what we mean by *cyber-physical symbiosis*: the forest is not merely measured — it can **call for help**.

---

### 3. Cryptographic Integrity: Decentralized MRV as a 11-Chain DePIN Stack

To eliminate double-counting, replay attacks, and oracle manipulation, Silken Net implements a **zero-trust** pipeline that runs from the silicon at the trunk to the smart contract on Polygon. The architecture is deliberately modular: no single network is asked to do more than it does well.

```
1.  Identity      peaq         — WHO is this?      (machine DID, tree passport)
2.  Verification  IoTeX        — is it TRUE?       (W3bstream ZK-proof of pipeline integrity)
3.  Oracle/Bridge Chainlink    — to CONNECT        (DON consensus, CCIP cross-chain delivery)
4.  Execution     Solana       — to PAY            (Ed25519 micro-rewards, high TPS)
5.  Memory        Filecoin     — to REMEMBER       (immutable raw-telemetry archive)
6.  Finality      Polygon + L1 — to LEGALLY FIX    (SCC mint, weekly SHA-256 anchor to Ethereum)
```

Concretely:

- **Hardware authentication:** every LoRa frame is encrypted on the STM32's CRYP module with hardware **AES-128**. The shipping build is transitional ECB; the migration target is **AES-128-CCM** — the same AEAD construction standardized by IEEE 802.15.4, Zigbee, Thread, and BLE for low-power constrained-radio links, delivering confidentiality, integrity, and replay resistance in a single hardware-accelerated primitive at costs appropriate to a sub-milliwatt budget and a sub-30-byte LoRa frame. The CCM two-key path is fully integrated behind a bench-attestation gate (§5 names it among the firmware's honest open blockers). Per-device keys are derived via HKDF from a Protected-Flash master seed and never leave the Ruby process boundary in plaintext.
- **Machine identity:** at provisioning, every Soldier is registered on **peaq** as a Substrate-native DID (`did:peaq:0x{40 hex}`), Ed25519-signed by the deployment operator. The DID is the canonical machine passport across all eleven networks.
- **Zero-knowledge verification:** each batch of telemetry is **designed to be** verified by an **IoTeX W3bstream** ZK circuit (⚠️ activation-gated — the leg is not live today, and `verified_by_iotex` is honestly `false` until it is), which proves the batch passed unaltered through the registered pipeline and binds it to the machine's on-chain DID — *without* revealing the raw sensor stream. (Cryptographic proof of *physical origin* — that this exact silicon signed its own data — is the true-DePIN North-Star we are climbing toward; today that origin is custodially attested, with metrological ground-truth complementing it.) The proof reference is anchored back into the telemetry log as `zk_proof_ref`.
- **Oracle consensus (retired vision):** a **Chainlink DON** cross-validation stage was designed here, then demoted to honesty — on-chain dispatch is a local correlation marker today, and closing that path has been refused outright in favour of something stronger: **Merkle-lineage proofs** that let an auditor verify every credit against its anchored measurements offline, no oracle trust required. What remains live is the hardened callback door: it carries an HMAC-SHA256 signature verified by timing-safe comparison, and replay protection is DB-atomic rather than nonce-based — a callback is only honoured against a row still marked `dispatched`, so a replay updates zero rows and is refused outright.
- **Permanent memory:** raw telemetry is daily archived to **Filecoin/IPFS** so that ten years from now, any institutional holder of an SCC can audit the full recorded physiological history of the tree their token represents.

Together this pipeline is the substrate of **Proof of Growth** — a consensus mechanism in which token emission is collateralized not by stake, not by computational waste, but by *measured biological flux — custodially attested today, with every credit's measurement lineage being anchored for independent offline audit*. If a tree dies, emission stops, instantly and automatically.

---

### 4. Tokenomics: A Dual-Token System with Adversarial-Resistant Slashing

The protocol mints two tokens, both ERC-20 on Polygon (anchored weekly to Ethereum L1 via SHA-256 state-root storage):

- **SCC (Silken Carbon Coin)** — utility token, max supply 1,000,000,000. Minted at the rate of **10,000 verified growth_points = 1 SCC**, with a species-specific carbon-sequestration coefficient applied per credit. EIP-2612 gasless approvals; ReentrancyGuard; `MINTER_ROLE` and `SLASHER_ROLE` are separated by design.
- **SFC (Silken Forest Coin)** — governance token, max supply 100,000,000, ERC-20Votes. Holders vote on protocol parameters — slashing ratios, insurance-pool thresholds, dynamic-tax rate — through a Governor + Timelock setup with a 48-hour delay and a quorum of 4% **of max supply** — 4,000,000 SFC, fixed rather than a fraction of circulating supply, so the first recipient of an emission cannot carry a vote alone. The trade is deliberate: a DAO that sleeps until real distribution is a postponed event, a DAO captured at genesis is unrecoverable, because both tuning levers are themselves `onlyGovernance` and there is no proxy.

Crucially, **slashing is not collective punishment**. Our v2 policy categorizes every degradation event:

- **Category A (Negligence / operator fault)** — unauthorized logging, ignored alerts, hardware tampering. Slashing is active, scaled by a **convex** curve (`damage_ratio^γ × penalty_factor`, γ = 1.3) that reaches 100% at total loss — an earlier flat 40% ceiling was removed precisely because it made catastrophic and moderate damage cost the same. Because the burn is irreversible, it fires only on *direct* evidence of tampering; every other trigger routes to a freeze plus field audit, and the evidence set that qualifies is still being populated — so in practice today the mechanism is freeze-first by construction.
- **Category B (Force majeure / acts of nature)** — lightning, wildfire of natural origin, severe drought (dClimate drought-index — specified, routed through Field Audit today), earthquake (NOAA ≥ M6 — a feed we have specified but not yet wired). Slashing is **disabled**. Funds are frozen and an **Etherisc parametric-insurance payout** is dispatched to the wallet. The insurance pool is replenished by a 2% Dynamic Tax on minting whenever its balance falls below 100,000 SCC.
- **Category C (Indeterminate)** — connectivity loss, insufficient sample. Funds are frozen pending a 30-day DAO peer-review window; if the DAO does not vote, they **stay** frozen and the cluster escalates to field audit. An earlier draft auto-thawed on timeout, and that was an attack surface, not a safety bias: jam the radio, and deliberate fraud (A) launders itself into "no data" (C), then waits out a quorum that voter fatigue guarantees will never arrive. Presumption of innocence is not auto-release in the absence of telemetry.

This matters. A protocol that burns its clients' tokens because lightning struck the cluster is a protocol that has no clients. We treat slashing as the cryptoeconomic instrument it is: a punishment for malice and inaction, *not* a tax on geographic risk.

---

### 5. Where the Work Actually Is

We are not announcing a finished product. We are announcing an architecture in which each layer is honestly readable on the NASA Technology Readiness Level scale:

- **Backend (Rails 8.1, Sidekiq, 11-chain orchestration, dual-token contracts):** TRL 8. Production-grade, RSpec-covered; the Solidity contracts are code-complete and pass a CI audit-stack (Slither, Aderyn, Halmos, Medusa), Polygon-targeted and pre-mainnet (external audit + mainnet deployment are the TRL-9 gate).
- **Firmware (STM32WLE5JC Soldier, mruby Lorenz Bio-Contract, star-topology LoRa, Queen gateway):** TRL 6. Running on hardware, parity-verified server-side, with named open blockers — AES-CCM migration and an OTA-deployable acoustic model. (The TinyML inference call-site was one of these until a self-owned baseline landed; we cross it off rather than keep it as decoration.)
- **Hardware capsule:** TRL 6 — specified, prototyped, pre-flight checklists drafted. **BQ25570 MPPT power chain and EDLC buffer:** TRL 4 — breadboard-tested on a CJMCU-2557, not yet in the capsule. The capsule's architecture is ahead of the power chain that must feed it, and the module reads at the lower number, not the higher one.
- **Tri-zone coaxial anchor and Gen-2.0 EBFC enzymatic stack:** TRL 3. Zero-Lab in-silico pipeline (L1-L4) PASSED 2026-05-25 — validated protein architecture, matrix stability (6 tree species), electron cascade, and kinetics entirely in silico (analytical PoC; per NASA/ISO 16290 in-silico = TRL 3). Next (physical TRL 4): in-vitro titanium-coin biochemistry in synthetic xylem sap, then full SLM-printed anchors.

We name this matrix on purpose. Anyone proposing to issue tokenized claims on real-world biology owes that level of transparency to anyone considering holding those tokens.

---

### 6. Toward Planetary Intelligence

Silken Net is not, in the end, a sensor network. It is an attempt to give a non-trivial fraction of the Earth's biosphere a **legible economic voice** — to convert biological flux into a cryptographic primitive that a smart contract can reason about.

The infrastructure to do this is no longer speculative. Macroporous titanium gyroids print on commercial DMLS platforms. Deglycosylated FAD-GDH expresses in *Pichia pastoris* at characterized current densities. STM32WLE5JC microcontrollers compute Lorenz attractors on sub-milliwatt power budgets. The peaq, IoTeX, Chainlink, Polygon, Solana, Filecoin, and Ethereum stacks compose, through open SDKs, without permission.

What is missing is a willingness to stop pretending that a green pixel is enough.

We propose an instrumentation in which a forest is not a passive object of exploitation, not a remote-sensed asset, not a CSR talking point — but a **first-class participant in the climate financial system**, with its own DID, its own wallet, its own cryptographically signed metabolic record, and its own automated insurance against the lightning bolt that the operator could not have stopped.

This is the architecture of a symbiotic interface between humanity and the biosphere. It is a foundation for a planetary intelligence in which technology functions not as a tool of extraction but as a **nervous system shared with the living world**.

The trees, as it turns out, have a great deal to say. We have simply not, until now, built the instruments capable of listening.

---

*Silken Net is an open research and engineering program. Hardware specifications, firmware, smart contracts, and the full 11-chain backend live in the project repository. We invite collaboration from the ReFi, DePIN, climate-tech, and dynamical-systems communities — and pointed questions from everyone else.*
