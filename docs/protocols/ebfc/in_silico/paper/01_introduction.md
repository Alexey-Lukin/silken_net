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
The work reported here is motivated by one such application — a tree-integrated sensor powered at the
titanium–xylem interface, where the dilute sugars of sap are the local fuel — but the electron-transfer
questions it raises are generic to the EBFC anode→mediator→cathode chain and, we argue, are best posed
at the level of electronic structure.

## The FAD-GDH / osmium / laccase-ZIF system

The architecture modelled here, representative of the high-performance mediated designs in the
literature, pairs an FAD-dependent glucose dehydrogenase (FAD-GDH) anode with an osmium redox-polymer
mediator and an oxygen-reducing cathode.<sup>5,6</sup> FAD-GDH is the
enzyme of choice for the anode because it is oxygen-insensitive and glucose-specific, unlike the
classical glucose oxidase<sup>7</sup>; but its catalytic flavin sits roughly 1.6 nm below the protein surface — too
far for efficient direct electron transfer — so an electron relay is required. The osmium
poly(vinylimidazole) polymer fills that role, its redox potential tuned empirically across a wide range
(≈ +15 to +489 mV vs NHE, optimum near +0.3 V) to balance the driving force handed to the cascade
against the open-circuit voltage it costs the cell.<sup>8</sup> On the cathode side, direct
electron transfer to a bimetallic zeolitic-imidazolate-framework (ZIF) nanozyme that mimics the
multicopper centres of laccase removes a second fragile enzyme from the device, trading turnover for
robustness<sup>9,10</sup> (cf. ref 11). The recurring
engineering challenges of such cells — interfacial electron-transfer efficiency, direct-electron-transfer
kinetics at the cathode, multi-year enzyme and mediator stability, and metal-ion leaching from the
support — are, at root, the same question asked four ways: how an electron moves, and how the molecular
environment governs that motion.<sup>12</sup>

## The gap: an electronic-structure account is missing

Despite that, the EBFC literature addresses these questions almost entirely at the experimental and
macro-kinetic level — cyclic voltammetry, electrochemical impedance spectroscopy, and
reaction–diffusion modelling — and only rarely at the level of electronic structure. The toolbox to do
so is mature and was built for exactly this purpose: Marcus theory relates electron-transfer rates to a
driving force and a reorganization energy<sup>13</sup>; the Beratan–Onuchic pathway model
estimates electronic coupling through a protein from its covalent and hydrogen-bonded connectivity<sup>14</sup>;
the Nelsen four-point scheme computes reorganization energies from first
principles<sup>15</sup>; ΔSCF total-energy differences give redox energetics where
frontier-orbital (Koopmans) estimates fail; a thermodynamic proton reference handles proton-coupled
electron transfer without the pathologies of an explicit hydronium ion in continuum solvent<sup>16</sup>;
and cluster-continuum micro-solvation corrects the well-known shortcomings of pure
implicit solvent on small, charged species.<sup>17</sup> Individually these methods are
standard. What is missing is their *integrated* application to a complete, realistic EBFC chain — the
redox potentials, reorganization energies, electronic couplings and solvation responses that actually
govern the cascade, computed for the same system, end to end. That integration is the gap this paper
addresses; model-driven mediator design at this level has begun for glucose oxidase<sup>18</sup> but
not for the FAD-GDH/Os/ZIF system.

## A methodological hazard worth naming up front

A complete electronic-structure account of this chain must cross a known hazard: implicit-solvation DFT
systematically misestimates the reduction potentials of small, highly charged transition-metal complexes,
with errors approaching ~1 V for group-8 (Fe/Ru/Os) octahedra because a continuum cannot reproduce the
directional second-shell hydrogen bonding around a +2/+3 couple.<sup>17,19</sup>
The osmium mediator at the centre of this device is precisely such a couple.
Rather than treat this as a nuisance to be absorbed into an empirical correction, we make it part of the
result — quantifying the error on a clean benchmark and decomposing the device-level discrepancy into its
physical contributions. Reproducibility is treated with the same seriousness: every calculation is
scripted, seeded, and run from a version-pinned environment, in line with current best-practice DFT
reporting.<sup>20,21</sup>

## Contribution

We report a first-principles, electronic-structure account of the electron-transfer energetics of a
complete Gen-2.0 EBFC chain, and — equally — an honest assessment of where affordable
implicit-solvation density-functional theory reaches its limit on this problem. Specifically, we (i)
reproduce the proton-coupled FAD redox potential to within 50–62 mV of experiment using a thermodynamic
proton reference, isolating the cascade discrepancy to the mediator rather than the flavin; (ii)
establish a Hammett<sup>22</sup> structure–activity relationship for the osmium mediator that is predictive and
rationalizes the empirically observed optimum<sup>23,24</sup>; (iii) compute the
bimetallic-ZIF cathode direct-electron-transfer kinetics with first-principles reorganization energies,
finding a borderline, λ-limited margin — a corrected finding, not the orders-of-magnitude artefact an
earlier geometry-and-λ error had implied — together with the design levers (a low-reorganization metal,
conductive-MOF band transport, or an acid-stable enzyme-free catalyst) that relieve it; and (iv) show
that the apparent uphill cascade is a *quantified* limitation of continuum solvation on charged
transition-metal couples — decomposed into a chloro↔bis-imidazole differential-solvation bracket and a
4,4′-dimethyl substituent term, benchmarked against the known group-8 error — rather than a failure of the chemistry. The flavin redox tuning by the
protein environment is computed in the same spirit.<sup>25,26</sup>

The contribution is therefore both a set of mechanistic design rules and a transferable methodological
lesson; it is explicitly *not* a re-confirmation of the experimentally known cascade. The scope is the
electron-transfer energetics — protein architecture and tunnelling distance, the anode redox and
reorganization energetics, the cathode direct-electron-transfer kinetics, the mediator structure–activity
series, and the solvation methodology; long-timescale matrix stability and the device-level
delta-t/impedance behaviour are deferred to companion work and enter here only as experimental-closure
predictions for the forthcoming titanium-coin measurements. All calculations are reproducible from the
accompanying version-pinned scripts.

---

## References

The numbered list (ACS, by first appearance across the assembled paper) and its Crossref provenance
live in [`09_references.md`](09_references.md).
