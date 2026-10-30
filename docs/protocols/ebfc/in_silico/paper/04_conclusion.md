# 4. Conclusions and Outlook — draft (Стаття 1)

> **Draft section** (§4 of [`00_OUTLINE.md`](00_OUTLINE.md)). Voice per
> [`00_WRITING_GUIDE.md`](00_WRITING_GUIDE.md) §Voice; numbers → [`SUMMARY.md`](../SUMMARY.md). Short.

**Scope and limits.** Everything below is computed in one affordable protocol — B3LYP with a C-PCM continuum for the redox and
reorganisation energies and the gas phase for the cathode coupling, one absolute-SHE convention and a scalar-relativistic osmium,
with ωB97X cross-checks — on component models: lumiflavin without its protein, the osmium complexes as isolated molecules (eight
forms of the device complex, ten substituents, programmatic and relaxed geometries), and a minimal coplanar Cu–Co cluster of the
framework computed as a +1 cation, two units below the +3 of the physical hop (§2.5), the Co–Ce and Ce–graphene hops carrying
only the crude two-solution estimate. Spin–orbit coupling on osmium is not computed; no explicit water surrounds the flavin,
the osmium forms of Table 2 carry at most three on the chloride (the 6–18-water second shell is a benchmark on [Os(H₂O)₆]
alone, §3.5), and nothing is sampled explicitly; the
flavin→mediator coupling and the protein-bound flavin potential are not computed, and the osmium reorganisation energy only on
one leg (λ_III 86–150 meV over five complexes, §3.3), with no outer-sphere term; the cathode reorganisation energy for cobalt comes from an octahedral ammine proxy with no benchmark,
and its kinetics assume an oriented enzyme–framework contact; four ωB97X end-point values are transcribed from run logs that are
not deposited; nothing here is measured, and no cell-level quantity — open-circuit voltage, current, power, lifetime — is
computed. Within those limits, we have computed the electron-transfer energetics of three steps of a FAD–osmium enzymatic
biofuel cell from first principles. Four findings, each with its stated limit. The **PCET potential of the FAD cofactor** becomes computable with implicit solvation once the proton
is treated thermodynamically — at the screening level 65 mV from experiment, with relaxed geometries and the
zero-point energy ≈210 mV more negative, so no level validates it — and the anode reorganisation energy is obtained
from the physically correct deprotonated semiquinone couple rather than assumed. A **Hammett trend** for the osmium
mediator agrees in direction with three measured series, with mixed donor-side magnitudes and a 1.2- to 3-fold acceptor-side
overshoot — a ωB97X/def2-TZVP
cross-check keeps its donor plateau and makes its slope ≈15 % shallower, and relaxing both osmium oxidation states moves
its donor pairs by up to 20.1 mV per substituent, so the magnitude of its donor part rests on the geometry as well as
the functional — and is consistent with the
trade-off behind the experimental optimum, which it does not locate, while making explicit that the cascade-thermodynamic
optimum is not the cell-voltage optimum. The **direct electron transfer** through the Co–Cu–Ce ZIF cathode is, on a
clash-free geometry, with reorganisation energies computed for Co, Ce and Ru (λ(Cu) cited), and with a framework copper standing in
for the enzyme's T1 site beside the cobalt node (§3.4), a process whose verdict is conditional on the Co reorganisation energy:
*rate-limiting* at every corner of its bracket at the computed λ(Co), straddling turnover only at an assumed
literature value (turnover needs λ(Co) ≲ 2.0 eV at zero driving force on the 2.0 eV λ(Cu) reading, and ≲ 0.9 eV at the
adverse corner) — a conditional, quantitative finding (the λ(Co) thresholds on a minimal-cluster coupling) that motivates a
low-reorganisation-energy metal, computed indicatively, and names conductive-MOF band transport and an acid-stable enzyme-free
catalyst as levers not computed here.

The paper's methodological core is the like-for-like treatment of the cascade. Set like for like — the two-electron,
two-proton flavin couple against each one-electron osmium couple on one SHE scale — the computed cascade is
downhill in every osmium form at every level of the flavin treatment, consistent with the measured direction; but that
holds within one functional, one continuum, one absolute-SHE convention and a scalar-relativistic osmium. Re-reading both
sides' energies at ωB97X/def2-TZVP (single points; the osmium geometry programmatic and vertical with LANL2DZ on osmium as in
every cell, the flavin's geometry and thermal terms from B3LYP, the ωB97X Os(III) accepted on convergence alone, §2.2) turns the device
cell on the relaxed electronic
flavin level uphill (−136.7 mV); the device couple's cells with the flavin's zero-point and RRHO terms stay downhill until the
spin–orbit shift passes −174.0 and −163.5 mV respectively — at the [Os(bpy)₃] size they read −76.0 and −86.5 mV, and on the
4.44 V convention they keep +15.0 and +4.5 mV (§3.5).
Spin–orbit coupling on osmium, of known sign and omitted here, turns 2 of the 32 cells uphill at the size the literature computes for
homoleptic [Os(bpy)₃] and more at the larger shifts the same source computes for other ligand sets (§3.5) (7 at −333 mV, 10 at −400 mV —
hexacyano and hexachloro) — the device couple on flavin levels that lie above the measured flavin among them — while against
the measured flavin the device couple keeps +69.8 mV at the [Os(bpy)₃] value, less than the protocol's own choices move it, and
turns uphill past −320 mV; at any of those values the protocol does not determine the sign,
and the direction rests on the protocol rather than being established by it. The finding is how far its magnitude, and where the remaining gap sits, move with the protocol — by
hundreds of millivolts — so we report them as method-dependent and attribute the gap to neither side. Where a computed value
lands within millivolts of the measured one, both sides are large and opposite, and we name the agreement a
cancellation rather than a validation. One-electron readings of the same step — orbital offsets, ΔSCF energies and
the proton-coupled route — are not like-for-like with that driving force and carry no conclusion here. Closing the
magnitude takes explicit-water QM/MM of the chloro species and of the reduced flavin, spin–orbit coupling on osmium
and a model of the mediator film.

The immediate experimental test is the EIS of the forthcoming Ti-coin half-cell, for which
the present work supplies the bracket the measurement must narrow — the cathode charge-transfer resistance spans ≈ 9.6 decades
(0.002 Ω to 7 MΩ) over λ(Co), the sign of the site-energy gap, the λ(Cu) reading and the unknown coverage, and the two λ(Co)
branches overlap between ≈ 8 Ω and ≈ 1.6 kΩ, so only an arc outside that window excludes one of them; the QM/MM treatment of the cascade with spin–orbit coupling on osmium,
and the protein-bound cofactor potential, are the natural next computational steps. The broader message is that the
electronic-structure level — under-used in the biofuel-cell literature relative to experimental and
reaction-diffusion modelling — yields both mechanistic findings with their limits and a measured account of how far
one affordable protocol can be read. Three cautions transfer: a coupling taken as half the difference of two unconstrained SCF
solutions must be read against the SCF tolerance; a planar start for the reduced flavin converges to a saddle that only a Hessian
catches; and PySCF below 2.13 switched the continuum sphere of an ECP atom with the wrong radius.
