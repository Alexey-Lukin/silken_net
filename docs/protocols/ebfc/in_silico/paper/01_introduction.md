# 1. Introduction — draft (Стаття 1)

> **Draft section** (§1 of [`00_OUTLINE.md`](00_OUTLINE.md)). Voice per
> [`00_WRITING_GUIDE.md`](00_WRITING_GUIDE.md) §Voice. Funnel: field → system → gap → contribution.
> Citations are **ACS-numbered superscripts** (`<sup>n</sup>`), numbered by first appearance across the
> assembled paper (§1 → §2 → §3, captions included); the numbered, Crossref-verified list lives in
> [`09_references.md`](09_references.md). Founder's final reference-manager pass still applies.

## Why autonomous biofuel-cell sensing

Enzymatic biofuel cells (EBFCs) convert the chemical energy of a fuel such as glucose directly into
electricity using redox enzymes as catalysts, operating at ambient temperature and physiological pH.<sup>1,2</sup>
Their power density is modest by comparison with
abiotic fuel cells, which excludes them from bulk power generation but suits a niche that conventional
batteries serve poorly: self-powered, implantable or environmentally-embedded sensors that must run
unattended for years on a fuel drawn from their surroundings.<sup>3,4</sup>
The work reported here is motivated by one such application — a tree-integrated sensor that would draw
its power from a cell at the titanium–xylem interface, with the dilute sugars of sap as the local fuel — but the electron-transfer
questions it raises are generic to the EBFC anode→mediator→cathode chain and, we argue, are best posed
at the level of electronic structure.

## The FAD-GDH / osmium / laccase-ZIF system

The architecture modelled here, representative of the high-performance mediated designs in the
literature, pairs an FAD-dependent glucose dehydrogenase (FAD-GDH) anode with an osmium redox-polymer
mediator and an oxygen-reducing cathode.<sup>5,6</sup> FAD-GDH is the
enzyme of choice for the anode because, unlike the classical glucose oxidase, it does not react with oxygen,
while remaining glucose-specific<sup>7</sup>; but its catalytic flavin sits roughly 1.6 nm below the protein surface — too
far for efficient direct electron transfer — so an electron relay is required. The osmium
poly(vinylimidazole) (PVI) redox polymer fills that role, its redox potential tuned empirically across a wide range
(≈ +15 to +489 mV vs NHE, optimum near +0.3 V) to balance the driving force handed to the cascade
against the open-circuit voltage it costs the cell.<sup>8</sup> On the cathode side, a
Co–Cu–Ce zeolitic-imidazolate-framework (ZIF) nanozyme that mimics the multicopper centres of laccase can
replace the second enzyme altogether, trading turnover for robustness;<sup>9,10</sup> in the device modelled
here it hosts the laccase and relays electrons to its T1 copper, and the step computed below is the hop from a framework
copper, standing in for the enzyme's T1 site, to the cobalt node (§3.4). Cluster-model computations of laccase redox potentials exist<sup>11</sup>. The recurring
engineering challenges of such cells — interfacial electron-transfer efficiency, direct-electron-transfer
kinetics at the cathode, multi-year enzyme and mediator stability, and metal-ion leaching from the
support — are, at root, the same question asked four ways: how an electron moves, and how the molecular
environment governs that motion.<sup>12</sup>

## The gap: an electronic-structure account is missing

Despite that, the EBFC literature addresses these questions almost entirely at the experimental and
macro-kinetic level — cyclic voltammetry, electrochemical impedance spectroscopy (EIS), and
reaction–diffusion modelling — and only rarely at the level of electronic structure. The toolbox to do
so is mature and was built for exactly this purpose: Marcus theory relates electron-transfer rates to a
driving force and a reorganization energy<sup>13</sup>; the Beratan–Onuchic pathway model
estimates electronic coupling through a protein from its covalent and hydrogen-bonded connectivity<sup>14</sup> (not applied here);
the Nelsen four-point scheme computes reorganization energies from first
principles<sup>15</sup>; ΔSCF total-energy differences give redox energetics where
frontier-orbital (Koopmans) estimates fail; a thermodynamic proton reference handles proton-coupled
electron transfer without the pathologies of an explicit hydronium ion in continuum solvent<sup>16</sup>;
and cluster-continuum micro-solvation corrects the well-known shortcomings of pure
implicit solvent on small, charged species.<sup>17</sup> Individually these methods are
standard. What is missing is their application to the links of one realistic EBFC chain in one protocol — the redox
potentials, the reorganization energies and an inter-metal coupling that govern the cascade, computed for the same
system (the flavin→mediator coupling and the protein-bound flavin potential are not among them). That is the gap this paper
addresses; model-driven mediator design at this level has begun for glucose oxidase<sup>18</sup> but
not for the FAD-GDH/Os/ZIF system.

## A methodological hazard worth naming up front

A complete electronic-structure account of this chain must cross a known hazard: implicit-solvation DFT
systematically misestimates the reduction potentials of small, highly charged transition-metal complexes,
with errors of ~1 V reported for [Ru(H₂O)₆]²⁺ under PCM-type models, because a continuum cannot reproduce the
directional second-shell hydrogen bonding around a +2/+3 couple (a COSMO-RS treatment largely removes that
error).<sup>19</sup>
The osmium mediator at the centre of this device is related to such couples, and how far its own computed potential
moves is part of what §3.5 measures.
Rather than treat this as a nuisance to be absorbed into an empirical correction, we make it part of the
result — comparing the cascade like for like on one scale and measuring how far its magnitude moves with the
protocol, rather than decomposing the discrepancy into contributions. Reproducibility is treated with the same seriousness: every calculation is
scripted and run from a recorded, version-exact environment, and the reporting follows best-practice
recommendations<sup>20,21</sup> where one affordable tier allows (the choices that depart — one functional tier, no dispersion
correction, no spin-contamination record for the B3LYP series — are named in §2); the electronic-structure scripts use fixed seeds, and the molecular dynamics are stochastic.

## Contribution

We report a first-principles, electronic-structure account of the electron-transfer energetics of
component models of a Gen-2.0 EBFC chain, and — equally — a measurement of how far one affordable
PCM-DFT protocol can be read on this problem. Specifically, we (i)
apply the standard thermodynamic proton reference to the proton-coupled flavin potential and measure how far its
agreement with experiment survives relaxed geometries and zero-point energy; (ii)
compute a Hammett<sup>22</sup> trend for the osmium mediator whose direction agrees with every measured pair in three series and which
alone covers the acceptors beyond Cl, where its magnitude is unvalidated (its slope moves by ≈15 % between two method tiers on three shared points, one of them an acceptor) — ligand-additive and Hammett rules for such potentials are established practice,<sup>23,24</sup> and the empirical optimum is ref 8's own<sup>8</sup>; (iii) compute the
Co–Cu–Ce-ZIF cathode direct-electron-transfer kinetics with first-principles reorganization energies,
finding a margin conditional on the Co reorganisation energy — below enzymatic turnover at the computed λ(Co),
straddling it only at an assumed literature value — together with the levers it suggests (a low-reorganization metal, computed indicatively;
conductive-MOF band transport and an acid-stable enzyme-free catalyst, named but not computed); and (iv) compare the anode→mediator
cascade like for like — the two-electron, two-proton flavin couple against each one-electron osmium couple on one
SHE scale — finding it downhill in every osmium form at every level of the flavin treatment within one protocol, a direction
that spin–orbit coupling on osmium, which the protocol omits, reverses for the device couple on one flavin level at
the literature size for homoleptic [Os(bpy)₃] and in more cells at the larger shifts the same source computes for other
ligand sets (§3.5) — against the measured flavin the device couple keeps +69.8 mV at the [Os(bpy)₃] size, less than the
protocol's own choices move it, and turns uphill past −320 mV, so the protocol does not determine the sign — while its magnitude
stays method-dependent, and naming the near-exact agreements that arise from cancelling deviations. The flavin redox tuning by the
protein environment is taken from experiment;<sup>25,26</sup> computing it is a follow-up.

The contribution is therefore both a set of mechanistic findings, each with its limit, and a transferable methodological
lesson; it is explicitly *not* a re-confirmation of the experimentally known cascade. The scope is the
electron-transfer energetics — protein architecture and tunnelling distance, the anode redox and
reorganization energetics, the cathode direct-electron-transfer kinetics, the mediator Hammett
series, and the solvation methodology; long-timescale matrix stability and the device-level
recharge and impedance behaviour are deferred to future work; the cathode charge-transfer resistance is bracketed
here, not predicted, for the forthcoming titanium-coin (Ti-coin) half-cell measurements. No cell of this design has been built or
measured here: 'device' denotes the specified design, and no cell-level quantity (open-circuit voltage, current, power,
lifetime) is computed. All calculations are scripted; every result cache
outside the reproduction records was computed in one recorded environment, and §2.7 states what a re-run under a newer
PySCF reproduces and what it moves.
