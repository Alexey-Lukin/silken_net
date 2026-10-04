# Defensive Disclosure — SilkenNet self-powered tree-health monitor (prior art)

> **Author / discloser:** Oleksii Lukin (SilkenNet) · **Public repository:** `github.com/Alexey-Lukin/silken_net`
> **First published in the public repository:** 2026-06-07 (commit `b0546460`) · **This revision:** 2026-10-04
> **First published on 2026-10-04:** §2.1 and §3.1 in full, and every passage or table entry marked
> «added 2026-10-04» or «corrected 2026-10-04».
> **Status:** disclosure-ready for submission to Technical Disclosure Commons.
>
> **What this is:** a deliberate **public technical disclosure** of the inventive core of SilkenNet,
> published **as prior art**. The goal is the opposite of a patent: to place the invention in the public
> record so that (a) it stays **free for every forest and community** to use, and (b) a third party cannot
> obtain valid claims over it and lock the network out. This is the honest execution of a
> **defensive-publication-first** posture.
>
> **Why publish rather than patent:** for a mission-first project with a public repository, the
> enforcement reality of a solo Ukrainian rights-holder, and open/DePIN DNA, defensive publication
> achieves anti-capture without the cost and exclusivity of a patent. Disclosure posture is owned by
> [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md); novelty landscape →
> [`prior_art_landscape.md`](prior_art_landscape.md); technical canon →
> [`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (EBFC) ·
> [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (gyroid).
>
> **Language note.** This document is written wholly in English, unlike the rest of this repository.
> That is deliberate: prior art only defeats a later claim if an examiner actually **finds** it, and
> patent examination is conducted through English full-text and CPC classification search. A disclosure
> nobody retrieves is legally public and practically useless. State home → [`00_07`](../../00_07_Action_Plan_Tracker.md) (disclosure execution).

---

## 1. Inventive core — three synergies

Every component **taken separately** — gyroid titanium implant, FAD-GDH/Os enzymatic biofuel cell,
laccase/ZIF cathode, LoRa networking, blockchain-anchored MRV — already has prior art
([`prior_art_landscape.md`](prior_art_landscape.md)). The substance of this disclosure is therefore **not
the components but three synergies that no single source teaches**, and it is precisely those that are
placed here into the public record:

- **SYNERGY A — dual-function EBFC.** One and the same enzymatic biofuel cell **simultaneously**
  (a) powers the electronics *and* (b) acts as the biosensor with **zero instrumental noise**: the
  supercapacitor charge time `delta_t` **is itself** the measurement of tree physiology. Because there is
  no separate sensor, there is no separate sensor noise, sensor power draw, or sensor drift. Conventional
  engineering *adds* a sensor; here the sensor is *eliminated*. ⚠️ **Scope note, added 2026-10-04:**
  «zero instrumental noise» means that no separate transducer adds its own noise, power draw or drift.
  It does not mean that `delta_t` is free of confounders: an ageing energy store, an ageing anchor and the
  weather also lengthen `delta_t`, and §2.1(8) and §2.1(9) disclose how the reference design sets out to
  tell them apart from the tree ([`02_03 §12.4.2`](../../02_03_BQ25570_MPPT_Nano_Power.md) · [`02_01 §3.4`](../../02_01_Hardware_Architecture_and_BOM.md)).
- **SYNERGY B — triple-function gyroid.** A single triply-periodic-minimal-surface (gyroid) geometry
  **simultaneously** (a) admits xylem sap into its porous volume, (b) reduces the modulus mismatch with
  living wood, and (c) forms the metal↔xylem interface electrode of that same EBFC.
- **SYNERGY C — the chaotic transform as an INTEGRITY SEAL, not a sensor.** The same non-linear
  (Lorenz) transform is evaluated **twice and independently**: once on the constrained node, from a
  per-device secret seed provisioned at manufacture, and once on the verifying server from that same
  seed — and the two results must agree **categorically**. Because a chaotic map amplifies any
  divergence in inputs or initial state exponentially, a party not holding the seed cannot fabricate a
  telemetry frame whose reported measurements and reported transform result are mutually consistent.
  The measurement is thereby rendered **self-authenticating without a separate secure element or
  per-frame signature**: forgery is defeated by the sensitivity of the dynamics themselves.
  Conventional engineering *signs* the message; here the message **cannot be constructed at all**
  without the secret. ⚠️ This synergy — not the health interpretation below — is the non-obvious
  teaching of the chaotic layer, and it is placed on the public record here for the first time.
  ⚠️ **Scope note, added 2026-10-04:** agreement may be judged categorically — on a status the node
  derives from the transform result — or numerically, on the transform value itself within a tolerance.
  The reference implementation judges categorically today, and a categorical comparison misses a forged
  frame whose reported status happens to coincide with the recomputed one; the numeric comparison, which
  closes that gap, is implemented but not yet enabled, because the frame revision that carries the node's
  own transform value is not yet enabled ([`03_04 §7.1`](../../03_04_mruby_Lorenz_Attractor.md)). How the
  two sides agree when the node may hold one of several status bands is disclosed in §2.1(10).

---

## 2. Disclosed system (description, not claims)

A self-powered device for *in-situ* monitoring of the physiological state of living woody tissue,
comprising:

- **(a) a porous metal anchor** of an additively manufactured biocompatible metal — baseline Ti-6Al-4V
  (ASTM F2924), and equally Ti-6Al-7Nb, commercially pure titanium, tantalum, other niobium- or
  zirconium-bearing biocompatible alloys, and noble-metal-coated variants of any of these — with a **gyroid**
  (TPMS) architecture, for implantation into the xylem of a living tree, wherein the gyroid
  **simultaneously** (i) admits xylem sap into the porous volume, (ii) provides a stiffness gradient that
  REDUCES the modulus mismatch with living wood, and (iii) constitutes the metal↔xylem interface electrode
  (porosity nominally 65 % within an acceptance band of 60–70 % for the whole part, either uniform or
  graded radially — in one graded embodiment from 60.8 % in the innermost shell to 72.5 % in the rim
  shell at 68.7 % overall; pore size graded radially from 300–500 µm at the centre through 150–300 µm to
  100–150 µm at the periphery that meets the callus, a biological target that current powder-bed printing
  reaches only in part; a network gyroid — a single connected labyrinth of pore space — in the reference
  design, the sheet gyroid disclosed, not practised; the unit cell in ANY orientation, the structure
  being bicontinuous and therefore permeable along every axis) — ⚠️ **corrected 2026-10-04:** earlier
  revisions gave a single «≈65%» porosity ([`01_01 §5.2`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) ·
  [`01_01 §5.5`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md));
- **(b) an enzymatic biofuel cell (EBFC)** at that interface: an anode carrying an immobilised
  flavin-dependent oxidoreductase (deglycosylated FAD-dependent glucose dehydrogenase, dgrFAD-GDH; its
  gene-level variant is disclosed in §2.1(5)) that oxidises xylem glucose via a redox mediator (an osmium
  bis-bipyridyl polyvinylimidazole complex in a genipin-crosslinked chitosan/cellulose-nanocrystal matrix);
  and an oxygen-reduction cathode at the bark–air boundary, fed with atmospheric oxygen — in the reference
  design a hybrid of laccase (*Trametes versicolor*) immobilised in the pores of a multimetallic,
  laccase-mimicking zeolitic-imidazolate-framework nanozyme (Cu-Ce-Au or Co-Cu-Ce: nCuCeAuZIF/Lac or
  nCoCuCeZIF/Lac) on functionalised multi-walled carbon nanotubes, the nanozyme acting at once as
  co-catalyst, as the bridge for direct electron transfer to the laccase's T1 copper centre, and as a
  protective scaffold that keeps catalysing if the enzyme denatures; laccase alone, or a trimetallic
  Cu-Co-Ce zeolitic-imidazolate-framework nanozyme alone operating by direct electron transfer, are
  disclosed, not practised — ⚠️ **corrected 2026-10-04:** earlier revisions named only these two
  single-catalyst forms ([`01_03 §1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) ·
  [`01_03 §2.2`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md));
- **(c) an energy store** (supercapacitor) charged by the EBFC and powering the electronics;
- **(d) a compute node** that derives a health signal **from the charge dynamics of that energy store
  itself** — so that the EBFC **simultaneously** powers the device and serves as its sensor, with no
  separate measurement transducer;

wherein the **time `delta_t`** required by the EBFC to charge the energy store across a defined voltage
window is treated as the **primary physiological indicator**, from which physiological state is derived by a
**direct monotonic mapping** of that interval — in the reference implementation a shorter interval earns a
larger growth reward (growth points), linearly between two calibration thresholds that await a measured
recharge curve, and an interval not yet measured earns none; and wherein a **deterministic Lorenz
attractor**, perturbed by temperature and — in variants that carry an acoustic sensor — acoustic emission
(the reference node carries none since 2026-09-29 and feeds zero for that input; the input is disclosed,
not practised), is computed alongside as the **integrity seal of SYNERGY C** (dual independent
recomputation), and not as a validated health classifier. ⚠️ **Corrected 2026-10-04:** earlier revisions said that
a series of `delta_t` intervals itself parameterises the attractor. In the reference implementation it
does not: `delta_t` is mapped to the reward directly and leaves the attractor untouched. The variant in
which `delta_t` perturbs a parameter of the attractor — practised in an earlier revision through the
parameter β, and withdrawn because β does not move the attractor's fixed point in z — remains **disclosed,
not practised** ([`03_04 §2.2`](../../03_04_mruby_Lorenz_Attractor.md) ·
[`03_04 §4.3`](../../03_04_mruby_Lorenz_Attractor.md)). ⚠️ **Truthfulness note, added 2026-09-05:** an
earlier revision stated that health state is *classified from* those chaotic dynamics. The implementation
was measured and that interpretation withdrawn — the transform is a deterministic function of inputs the
verifier already holds, so by the data-processing inequality it adds no predictive information about
physiology beyond them. The chaotic-classification variant **remains disclosed** here, so that it stays
unpatentable by others; it is simply **not asserted as validated, and not practised**
([`03_04`](../../03_04_mruby_Lorenz_Attractor.md)). ⚠️ **Corrected 2026-10-04:** «not practised» in the
note above is too strong. The reference node still bins the attractor's state into a categorical status —
homeostasis, stress or anomaly — and uses it as a gate: a stress status replaces the metabolic reward by a
fixed minimum, an anomaly status replaces it by zero, and a stress status can, rarely, raise a drought
alert. What stays withdrawn is the claim that this status measures tree health, which remains an
unvalidated hypothesis ([`03_04 §4.2`](../../03_04_mruby_Lorenz_Attractor.md) ·
[`03_04 §5.3`](../../03_04_mruby_Lorenz_Attractor.md)).

**Extensions.** A LoRa network of such nodes — in the reference design a star per cluster, in which every
sensing node is powered **solely by its own EBFC** while the cluster gateway runs on a solar panel and a
LiFePO4 battery; a mesh in which every node, gateways included, is powered solely by its own EBFC is
disclosed, not practised (⚠️ **corrected 2026-10-04:** earlier revisions described only that mesh;
[`00_01 §3`](../../00_01_Vision_Mission_and_Roadmap.md) · [`02_05 §3`](../../02_05_Queen_Hardware_and_Starlink.md));
classifications committed to a distributed ledger as the verification layer of a
measurement-reporting-verification system; and a **zonal coating rule** under which no dielectric layer is
ever placed on an enzyme-bearing active surface — the anode's gyroid wall or the cathode's catalytic face —
whatever lies there being electronically conductive, ion-conductive, or absent, so as not to passivate the
EBFC interface. ⚠️ **Corrected 2026-10-04:** in the reference design the only coating outside the active
surfaces is a biomimetic zinc-doped hydroxyapatite/chitosan layer (5–15 µm) on the callus-facing periphery
of the anode zone, optionally with a PEDOT:PSS hydrogel in the peripheral pores; protective coatings
applied to surfaces other than the enzyme-bearing walls — such as a zinc- and tantalum-bearing oxide grown
by plasma electrolytic oxidation, or a self-healing coating carrying corrosion-inhibitor microcapsules —
are disclosed, not practised: both were removed from the reference protocol on 2026-10-04
([`01_02 §3.6`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) ·
[`01_04 §4.2`](../../01_04_CODIT_and_Xylemointegration.md)).

### 2.1 Further disclosed features (added 2026-10-04)

Each feature below is disclosed both as part of the system of §2 and in its own right. Status words:
**practised** — part of the current reference design in the public repository; because the system as a
whole stands at TRL 3 (its anchor and biofuel cell are designed and modelled in silico but not yet
validated in a physical test, [`00_03 §1`](../../00_03_TRL_Matrix_HIL_and_Beyond.md)), «practised» never
means field-proven. **Disclosed, not practised** — described only so that it stays unpatentable by others,
and absent from the reference design.

**(1) Three-zone coaxial anchor with a polymer thermal break.** The anchor, about 80–120 mm long, is three
parts on one axis. *Zone 1* is the porous gyroid anode of §2(a) — Ø11 mm, 30–50 mm long — immersed
entirely in the sapwood. *Zone 2* is a machined PEEK sleeve 50 mm long with a 2.0 mm wall, whose outer
diameter of 15 mm is also the diameter of the wound; by the CODIT 4 % rule this admits host trees from
38 cm diameter at breast height. *Zone 3* is a titanium cathode flange, Ø29.8 mm, seated at the bark,
whose catalytic band on the side face stands above the bark and breathes atmospheric oxygen through a
microporous PTFE gas-diffusion membrane (pores 0.2–1.0 µm) that passes oxygen and stops liquid water;
the cathode sits at the bark–air boundary because oxygen diffuses about 10⁴ times more slowly in liquid
than in air. The sleeve receives the solid shanks of Zones 1 and 3 from opposite ends by interference fit
and does three things at once: it insulates the anode from the cathode, so that the cell current closes
only through the external circuit; it breaks the thermal path — PEEK conducts about 0.25 W/m·K, roughly
27 times less than the titanium alloy — so that winter cold is not conducted through the metal into the
living tissue around the anchor; and it damps the micro-movements of trunk sway. *Practised*
([`01_01 §1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) ·
[`01_01 §4.1`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)).

**(2) Central bus, monolithic with the anode, insulated through the cathode.** The anode current leaves
through a central conductor of the anode's own alloy: a drawn wire, Ø1.0 mm, welded to the upper face of
the anode, which is printed without a core — a cold-drawn wire carries no as-printed fatigue derating. The
wire rises along the axis through the sleeve and through a Ø1.35 mm channel in the cathode flange, and its
end face is itself the central contact pad, plated with hard gold. Being one metal with the anode, the bus
has no dissimilar-metal joint at its root, and being a low-conductivity titanium alloy rather than copper,
it does not short-circuit the thermal break (a copper conductor would dominate the break and chill the
anode pocket). Inside the cathode channel the wire is insulated by a structural PEEK liner tube 0.15 mm
thick (1.0 + 2 × 0.15 = 1.30 mm < 1.35 mm, i.e. a diametral clearance of 50 µm); the tube spans the
channel completely, is captured at its upper end and protrudes at least 1.0 mm into the sleeve gap below,
and the channel's entry and exit edges carry a radius, not a chamfer. *Practised* (the weld's place in the
process sequence and its acceptance test remain open;
[`01_01 §1.4`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)).

**(3) Annular ratchet barbs and hot press-fit.** PEEK relaxes under sustained hoop stress, and at the
lower edge of the permitted interference band the effective interference at +40 °C is zero by
construction — so retention of the interference fit cannot rest on friction. The titanium shanks of
Zones 1 and 3 therefore carry annular, asymmetric triangular barbs — height 0.25–0.4 mm, base 0.4–0.6 mm,
leading flank 30°, trailing flank 70°, the base following from the height and the two angles (working
point: height 0.28 mm, base ≈ 0.59 mm) — in 3–5 rows over the 8–15 mm PEEK contact length of the anode
shank and 3 rows on the flange shank. In each part's own frame the shallow flank faces the end that enters
the sleeve first. Printed in the same powder-bed cycle as their part, the barbs are self-supporting when
oriented with the shallow flank facing downward. The sleeve is heated to 150 °C, above the PEEK glass
transition (143 °C for the reference grade), and pressed on with a controlled force of 800–1200 N; the
softened polymer fills the space between the barbs and locks onto them as it cools. The anchor is thus assembled without adhesives,
threads or welding of dissimilar materials. The barbs give axial retention only — neither sealing nor
resistance to rotation. *Practised* (pull-out retention not yet measured;
[`01_01 §3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) ·
[`01_01 §4.3`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md)).

**(4) Dual-scale pore-wall surface and its contactless activation.** The gyroid answers two opposite needs
at two scales: macro-pores (100–500 µm as the biological ideal) carry sap, while micro-roughness of the pore
walls (0.1–10 µm) multiplies the contact area between enzyme and metal. Loose powder is removed from the
printed lattice without abrasives — by vacuum-assisted decanting and a circulating citric-acid/surfactant
flush, with ICP-MS control of residual aluminium in the drain — because abrasive blasting would introduce
foreign particles into the lattice. The pore walls are then acid-etched, after vacuum degassing in the
deaerated etchant, under two simultaneous agitation mechanisms: continuous ultrasound, which strips
hydrogen bubbles from the walls before they form gas locks in the cavities, and forced flow through the
lattice, which carries them out. A multi-stage rinse follows; a vacuum dehydrogenation bake, if one is
used, is performed on the bare part before press-fit assembly and never after it. Acceptance is by result,
not by recipe: the processor declares the etch parameters, and the internal walls must show an areal
roughness Sa of 0.5–5 µm per ISO 25178, a nano-pore depth Sv of 50–500 nm, and a specific surface area more
than ten times that of a smooth sample. *Practised* (reference manufacturing protocol; not yet performed;
[`01_02 §1.2`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) ·
[`01_02 §1.3`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)).

**(5) Gene-level deglycosylated glucose dehydrogenase, frozen sequence.** The anode enzyme is the
FAD-dependent glucose dehydrogenase of *Glomerella cingulata* (UniProt G8E4B5, a 600-residue translation
product), deglycosylated in the gene rather than by enzymatic treatment: all eleven N-X-S/T sequons are
removed by Asn→Gln substitution — N71Q, N100Q, N192Q, N200Q, N249Q, N258Q, N271Q, N355Q, N380Q, N405Q
and N463Q (numbering of the 600-residue translation product) — so that the *Pichia pastoris* expression
host cannot glycosylate those sites, and an enzymatic deglycosylation step (PNGase F or Endo H) is kept
only as a fallback. Gln, unlike the Asp left behind by PNGase F, keeps the surface charge neutral. Three
compensating substitutions reduce the apolar surface the removed glycans expose: L80D and A70S at the
Gln71 patch, and I401S, the only compensation of the Gln405 patch. The ordered sequence was frozen on
2026-10-04 with exactly these substitutions — the eleven N→Q and the three compensations. The secretion
leader is deliberately left to the expression provider — the native 16-residue signal peptide, which
gives a 584-residue mature chain, or the provider's own leader — provided that the mature N-terminus is
declared and its cleavage confirmed by intact-mass mass spectrometry. A further variant, in which Lys109
and Lys262 at the electron exit are replaced by Arg so that the genipin cross-linker of the protective
matrix cannot knot at them and block mediator docking, is disclosed, not practised (it is not in the frozen
sequence). ⚠️ The rate benefit of deglycosylation was measured on enzymatically deglycosylated enzyme; its
transfer to this gene-level construct is an assumption, not a measurement. *Practised* (the frozen
sequence of the reference design; not yet expressed;
[`L1_protein_architecture.md`](../ebfc/in_silico/L1_protein_architecture.md) §2 ·
[`ebfc_chem_rfq.md`](../procurement/ebfc_chem_rfq.md) Spec A).

**(6) Several anchors on one node: parallel within a trunk, series only between trunks.** Several anchors
may feed one node's charger. Within one trunk they are connected only in parallel. Series connection within
one trunk is excluded: the xylem sap is a shared, continuous electrolyte, so a series stack inside one trunk
drives a parasitic ionic current back through the living tissue from the more positive anode — collapsing
the potentials of the cascade and electrolysing the sap into gas plugs that embolise the vessels. In
parallel, the residual voltage between anodes never exceeds the open-circuit voltage of one anchor (about
0.5–0.7 V), below the 1.23 V thermodynamic threshold of water splitting (1.6–2.0 V on real electrodes with
overpotential), so parallel connection is safe for the tree at any spread between anchors; it divides the
internal resistance (two anchors → R_int/2) and adds current, but does not raise the open-circuit voltage,
and its efficiency cost through the same shunt path is not yet measured. Series connection, which does raise
the open-circuit voltage, is used only between anchors in different trees, joined by wires. Any number of
anchors on one node remains one device identity, because identity derives from the node's silicon and the
anchors are passive. *Status:* the baseline node uses one anchor; parallel anchors within a trunk are the
reference design's conditional mitigation, used only when a measured internal resistance calls for it;
series between trees is disclosed, not practised
([`01_03 §6.1`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) ·
[`02_03 §1.5`](../../02_03_BQ25570_MPPT_Nano_Power.md)).

**(7) Blind-mate coaxial spring-pin interface.** The electronics capsule mates with the anchor blind, through
two spring-loaded pins (pogo pins) mounted on the capsule's circuit board and travelling axially onto the
flange's capsule-facing face, laid out like a coaxial connector. The centre pad — the end face of the
anode bus — is the negative terminal (anode → circuit ground); an insulating PEEK ring set flush in a
counterbore around the channel exit, Ø ≥ 4.0 mm, keeps at least 1.5 mm of insulation between the Ø1.0 mm
centre pad and the surrounding flange metal; and the outer ring of the cathode flange is the positive
terminal (cathode → the charger's input). Both contact areas carry hard gold, so that the gold-plated pins
never press on bare titanium. A polarisation key — a physical asymmetry of the housing — prevents wrong
mating. The capsule is retained by a quarter-turn bayonet — inserted straight down, which compresses the
pins and makes contact, then turned 90° so that its lug locks — operable with one gloved hand while the
other holds the tree, with no thread and no cable entering the enclosure; a single EPDM O-ring in a groove
on the flange's capsule-facing face, compressed by the radome's flat rim, seals the electronics. A variant
retained or aligned by magnets, alone or together with the bayonet, is disclosed, not practised.
*Practised* (the pin part number, the plating route of the pads and the final geometry of the insulating
ring remain open; [`02_02 §1.2`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) ·
[`02_02 §4.3`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md)).

**(8) Open-circuit voltage read through the harvester's own MPPT window, used to exclude
hardware-confounded trees.** An ailing tree and an ageing energy store look the same in `delta_t`: both
lengthen it. The open-circuit voltage of the biofuel cell, V_OC, separates them — if V_OC holds on the
node's own baseline while `delta_t` grows, the hardware is ageing; if V_OC falls with `delta_t`, the tree is
under stress. The node reads V_OC without any added switch: the maximum-power-point tracker of the harvesting
boost charger itself disconnects its input periodically to sample V_OC (in the reference design a Texas
Instruments BQ25570, for 256 ms every 16 s, between which the input sits at the operating point of
0.65 × V_OC). An ADC channel on the charger's input, sampled with max-hold over a collection window of at
least 16.3 s and at steps of at most 128 ms — half the open window, so that at least one sample falls in its
second half, closest to V_OC — returns V_OC directly (0.5–0.8 V lies below the 3.3 V reference, so no
divider is needed). A gap longer than the step, or time running backwards, yields a «not measured»
sentinel instead of a value, because a missed window would return the operating point disguised as V_OC.
The reading is rare — about once a day — and travels as a field of the ordinary telemetry frame, in a slot
left without a writer, rather than as an extra frame or byte. It is used at the slashing-decision layer and
never inside the integrity seal (fed into the transform, it would make the verifier's recomputation diverge
from the node's): a tree whose V_OC is stable on its own baseline while `delta_t` degrades is classed as
hardware-confounded and excluded from the slashing count. ⚠️ The max-hold reading under-reads V_OC by an
offset that grows with the cell's internal resistance as the anchor ages, which would mimic a falling V_OC;
the two states must be separated before this feature becomes a slashing input. *Practised* as far as the
acquisition arithmetic, which is implemented and host-tested (`firmware/common/voc_maxhold.h`); on-board
acquisition, the frame field and the slashing-layer exclusion are designed but not yet implemented, and the
physics awaits bench confirmation ([`02_03 §3.2`](../../02_03_BQ25570_MPPT_Nano_Power.md) ·
[`02_03 §12.4.2`](../../02_03_BQ25570_MPPT_Nano_Power.md) ·
[`03_05 §2.1`](../../03_05_Hardware_Symmetric_Crypto_and_Security.md)).

**(9) Sealed sensor micro-pocket, vented through an adhesive ePTFE vent mounted inside the radome, as a
weather gate.** A `delta_t` lengthened during rain or fog, at a relative humidity near 100 %, is weather,
not disease. The node therefore carries a combined air-temperature, relative-humidity and pressure sensor
(in the reference design a Bosch BME280), computes the vapour-pressure deficit (VPD) with the FAO-56
(Tetens) saturation formula, and sends it as a one-byte index in steps of 0.02 kPa, the value 0 being
reserved for «no sensor». VPD is used only at the confounder and slashing layer, to explain a `delta_t`
excursion by weather; it never enters the integrity seal. So that the sensor answers in seconds rather
than minutes without breaking the enclosure's immersion rating, the sensor sits in its own pocket sealed
to a single through-hole in a flat face on the inner side of the radome's vertical wall, and that hole is
covered from the inside by an adhesive-backed protective expanded-PTFE vent rated IP68 when mounted from
the inside (in the reference design: hole Ø1.0 mm under the membrane's Ø2.0 mm active area; pocket air
volume ≈ 89 mm³, diffusion time constant estimated at ≈ 12 s). A vent into the whole capsule (about
5 cm³) would respond in minutes rather than the seconds of a pocket of at most 0.3 cm³, and would keep
saturating the capsule's desiccant with forest air. The PEEK bonding face is plasma-treated to a surface
energy of at least 55 mN/m, and the vent is bonded before the sensor is installed. *Practised* at CAD level;
the vent, the pocket and the sensor await bench validation, and no manufacturer has qualified the vent's
adhesive on treated PEEK for long service ([`02_01 §3.4`](../../02_01_Hardware_Architecture_and_BOM.md)).

**(10) Band-set self-attestation of the integrity seal, with a narrowing-only guard.** The node bins the
attractor's state into its categorical status with a threshold band: a lower and an upper bound on the
attractor coordinate z, the upper bound applied relative to the temperature-shifted ρ (in the reference
node 2.0 and 45.0, the upper bound applied as ρ + 17). The verifier may later send the node a different
band, for example one fitted to a species, yet the uplink carries no acknowledgement of which band the
node applies. The verifier therefore judges each frame against the SET of bands the node may hold — the
factory band always, plus the bands issued to it that evidence has not yet excluded — and accepts the
frame if any candidate band reproduces its reported status. The frame thereby attests the band itself,
with no added byte and no added firmware: whenever the recomputed coordinate falls where candidate bands
give different statuses, the reported status names the band in force; such a frame is recorded as
evidence, and frames that keep showing the old band after a delivery window raise a field audit. A
**narrowing-only guard** admits only bands lying within the node's factory band, so that the status of a
narrower band where the bands diverge yields no more reward than the factory band would — save one named
corner, a frame whose metabolism is not yet measured, where the gain is at most one growth point per
frame. Without the guard the band would be a silent reward lever — a wider band, fewer anomalies, more
reward — invisible to the integrity seal, because the node genuinely computes with it. A band wider than
the factory band cannot be sent at all; it requires a change of the node's firmware default. *Practised*
(the verifier side is implemented; issuing bands stays disabled until the node-side band receiver, already
built, is enabled on hardware; [`03_04 §5.3`](../../03_04_mruby_Lorenz_Attractor.md)).

---

## 3. Disclosed method (description)

A method of monitoring the health of a living tree: implanting into its xylem a porous gyroid anchor of a
biocompatible metal (as in §2(a) — not limited to titanium alloys) that **simultaneously** integrates with sap flow, reduces the elastic-modulus mismatch with the
surrounding wood, and forms the metal↔xylem electrode of an enzymatic biofuel cell; generating electrical energy from xylem
glucose at that cell; storing that energy in an energy store; and deriving a health signal **from the
charge-time dynamics of that same cell** — such that a single enzymatic biofuel cell both powers the
monitoring and constitutes its sensor, with zero instrumental noise in the sense set out under SYNERGY A.

### 3.1 Implantation (added 2026-10-04)

The anchor is implanted through a stepped cut rather than driven in or bored with an auger drill.
(i) **The channel is milled, not augered:** by a sharp, single-use cutter of positive rake geometry run at
a chip load within its maker's range, in peck cycles, with air or minimal sterile-mist cooling, under
temperature control by one probe at the channel tip and — mandatorily — a second on the cambium beyond the
wound edge, against a 50 °C cambium threshold, because modelling shows the cambium crossing that threshold
long before the tip does. (ii) **The wide step only shallowly faces the dead outer bark (periderm)** — a few
millimetres, never down to the living bark — to give the flange a flat seat perpendicular to the anchor
axis; the narrow step cuts the channel into the sapwood for the anode and the sleeve. The flange seats on
the faced dead bark, cutting into neither the living bark nor the xylem, with its catalytic band standing
above the bark, and the wound is closed by callus growing over the outer edge of the sleeve, not by an
elastomer seal. (iii) **The channel rises at most 10° above horizontal, with 10° as the design point**, so
that excess resin drains downward and frees the anode's upper pores for sap; at 10° the facing depth
differs by about 5.2 mm between the flange's upper and lower edges, within the thinnest dead-bark estimate
for eligible trees. The benefit of any installation angle has not been measured. (iv) **Planned
installation falls in the cambial dormancy window**, bounded in autumn by the date on which mean daily air
temperature stably leaves ≥ 8 °C (taken at the 90th percentile across years) and in spring by the date on
which soil at 7–28 cm stably warms through 3.5 °C (taken at the 10th percentile) — at the reference site,
Cherkasy (ERA5, 1991–2020), from the end of October to mid-March. ⚠️ That resin pressure is lowest during
dormancy is a hypothesis: the one seasonal primary source found ties oleoresin pressure to daily
temperature rather than to the season, so the window rests on thresholds of cambial activity. *Practised*
(reference installation protocol; not yet performed on a tree;
[`01_04 §3.1`](../../01_04_CODIT_and_Xylemointegration.md) ·
[`01_04 §3.2`](../../01_04_CODIT_and_Xylemointegration.md) ·
[`01_04 §3.3`](../../01_04_CODIT_and_Xylemointegration.md) ·
[`01_04 §3.5`](../../01_04_CODIT_and_Xylemointegration.md)).

---

## 4. Enablement and incorporation by reference

This document discloses the **combination**. The quantitative and procedural detail that makes it
reproducible by a person skilled in the art — enzyme loading and immobilisation protocol, mediator
synthesis, gyroid wall parameter and unit-cell period, the defined charge voltage window, energy-store
capacitance, the Lorenz parameterisation and status thresholds, the mapping of `delta_t` to the growth
reward, and the detail behind each feature of §2.1 and §3.1 — is **published in the same public
repository, on and since the dates above**, and is incorporated here by reference:

| Referenced disclosure | Supplies |
|---|---|
| [`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) | EBFC chemistry: enzyme, mediator, matrix, membrane, cathode; added 2026-10-04: connection of several anchors (§6.1) |
| [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | Gyroid geometry, porosity, zonal architecture; added 2026-10-04: central bus, interference fit and barbs (§1.4, §3, §4) |
| [`03_04`](../../03_04_mruby_Lorenz_Attractor.md) | Lorenz integrity seal: parameters, perturbation, dual recomputation and status bands (§5); the `delta_t` → reward mapping (§4.3) — corrected 2026-10-04 |
| [`02_03`](../../02_03_BQ25570_MPPT_Nano_Power.md) | Energy-store charging path and voltage window; added 2026-10-04: open-circuit voltage through the MPPT window (§12.4.2) |
| [`01_02`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) | Dual-scale surface and its activation (§1); zonal coating map (§3.6) — added 2026-10-04 |
| [`01_04`](../../01_04_CODIT_and_Xylemointegration.md) | Implantation (§3); biomimetic coating (§4) — added 2026-10-04 |
| [`02_01`](../../02_01_Hardware_Architecture_and_BOM.md) | Climate sensor, VPD index and vented sensor pocket (§3.4) — added 2026-10-04 |
| [`02_02`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) | Blind-mate coaxial interface and bayonet retention (§1, §4) — added 2026-10-04 |
| [`02_05`](../../02_05_Queen_Hardware_and_Starlink.md) | Cluster gateway and its solar-and-battery power (§3) — added 2026-10-04 |
| [`L1_protein_architecture.md`](../ebfc/in_silico/L1_protein_architecture.md) | Gene-level deglycosylated enzyme: sites, substitutions, sequence (§2) — added 2026-10-04 |

Those documents are part of the same dated, publicly accessible repository; together with this disclosure
they constitute an enabling publication of the combination described in §2 and §3.

---

## 5. Publication anchors

- **Technical Disclosure Commons** — a no-fee defensive-publication venue whose records are indexed and
  consulted by patent offices.
- **The public SilkenNet git repository** — this file, with a verifiable commit date.
- **A preprint of Article 1** ([`00_02 §2.1`](../../00_02_Academic_Integration_and_IP.md)) — **planned, not
  yet deposited**: a computational study of the cell's electron-transfer energetics, to be deposited on
  ChemRxiv under CC BY 4.0 together with a Zenodo snapshot of the tagged repository. It is not prior art
  until it is deposited, and it will document the electron-transfer chemistry of the cell, not the
  synergies of §1. ⚠️ **Corrected 2026-10-04:** earlier revisions called it a peer-reviewed article; the
  journal route is dormant, and nothing has yet been deposited
  ([`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md)).

Together the first two create **citable prior art** for the combination disclosed above (the preprint, once
deposited, adds an independently dated record for the cell chemistry), which should prevent a
third party from obtaining *valid* claims over it and keep it free for use in forest-health monitoring.
Stated precisely, and deliberately not more strongly than is true: prior art does not make patenting
impossible — an application may still issue if the art is never retrieved, and defeating it then requires
opposition or invalidation. That is exactly why the venue, the English text and the indexed commit date
matter, and why the anti-capture search remains a separate open task
([`00_07`](../../00_07_Action_Plan_Tracker.md), disclosure execution).

**Non-assertion.** SilkenNet files no patents on this technology; should any ever be obtained
defensively, an irrevocable non-assertion pledge applies to all good-faith users — see `/NOTICE` and
[`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md).

---

## 6. Cross-references

| Resource | Role |
|---|---|
| [`00_01 §8`](../../00_01_Vision_Mission_and_Roadmap.md) | **owner** of the IP posture (defensive-publication-first, licences, pledge) |
| [`prior_art_landscape.md`](prior_art_landscape.md) | novelty landscape and anti-capture (FTO-lite) scan plan |
| [`01_03`](../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) · [`01_01`](../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) | EBFC / gyroid technical canon |
| [`01_02`](../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) · [`01_04`](../../01_04_CODIT_and_Xylemointegration.md) | anchor surface, coatings and implantation canon |
| [`02_01`](../../02_01_Hardware_Architecture_and_BOM.md) · [`02_02`](../../02_02_Blind_Mate_Pogo_Pin_Interface.md) · [`02_03`](../../02_03_BQ25570_MPPT_Nano_Power.md) · [`02_05`](../../02_05_Queen_Hardware_and_Starlink.md) | node, interface, power and gateway canon |
| [`03_04`](../../03_04_mruby_Lorenz_Attractor.md) | Lorenz integrity seal and its status bands; the `delta_t` → reward mapping — corrected 2026-10-04 |
| [`L1_protein_architecture.md`](../ebfc/in_silico/L1_protein_architecture.md) | the deglycosylated enzyme sequence |
| [`00_07`](../../00_07_Action_Plan_Tracker.md) | state: disclosure execution, trademark timing |
