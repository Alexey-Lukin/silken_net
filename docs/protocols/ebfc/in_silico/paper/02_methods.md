# 2. Computational Methods — draft (Стаття 1)

> **Draft section.** Prose for the paper's Methods (§2 of [`00_OUTLINE.md`](00_OUTLINE.md)). All
> numeric results are referenced from [`SUMMARY.md`](../SUMMARY.md) (One-Home) — this draft
> describes the *methods*, the Results sections report the *numbers*. EN (target = J. Phys. Chem. B).
> Status: first pass, founder to refine (depth, journal house style). Citations: ACS superscripts →
> [`09_references.md`](09_references.md); `[CITATION NEEDED]` marks a claim with no verified source yet.

## 2.1 Structure prediction and active-site models

The deglycosylated FAD-dependent glucose dehydrogenase (*Glomerella cingulata*, GcGDH)<sup>7</sup> was
modelled with **AlphaFold 3**,<sup>27</sup> with the eleven N-glycosylation sequons (N–X–S/T, X≠P) mutated
to glutamine to give the aglycosylated variant used throughout. (The gene ordered for expression
carries three further surface substitutions chosen after this modelling; the structure and every
number below stand on the eleven-substitution sequence as modelled.) The FAD cofactor was
placed from the AF3 complex prediction; the cofactor-to-surface depth and the electron-exit
region were measured in ChimeraX.<sup>28,29</sup> The flavin redox and proton-coupled energetics (§2.3,
§2.4) were computed on **lumiflavin** (7,8,10-trimethylisoalloxazine), the canonical truncation of the
isoalloxazine redox core, in the continuum of §2.2 — without protein residues. An active-site cluster
(isoalloxazine ring plus the H-bonding and charged residues within ≈5 Å, retaining backbone amide caps)
was defined from the predicted structure for the explicit-solvent QM/MM follow-up (§3.6); no energy
reported here is computed on it.

## 2.2 Electronic-structure setup

All density-functional calculations used **PySCF**<sup>30,31</sup> (version 2.11.0, with geomeTRIC 1.1 for
geometry optimisation; §2.7). Two functionals were employed: **B3LYP**<sup>32–34</sup> (the PySCF/libxc `B3LYP`, i.e. with the VWN RPA local-correlation
term<sup>35</sup> of the Gaussian convention, not the VWN5 variant) for the orbital-resolved and ΔSCF
energetics, and the range-separated hybrid **ωB97X**<sup>36</sup> for a higher-rung adiabatic cross-check. The
basis was **6-31G(d)**<sup>37–39</sup> on all non-metal atoms, with the **LANL2DZ** effective-core potential
and basis<sup>40</sup> on the transition metals (Os, Cu, Co, Ru) and the **Stuttgart RSC** ECP/basis on cerium.<sup>41</sup> The
adiabatic ωB97X cross-check (§2.3) replaced 6-31G(d) by **def2-TZVP**<sup>42</sup> on the non-metal atoms, keeping LANL2DZ
on osmium; the ωB97X speciation cross-check kept the 6-31G(d)/LANL2DZ basis of the B3LYP tier. Aqueous
solvation was treated with the **C-PCM** continuum<sup>43,44</sup> (ε = 78.3553) for the redox, speciation and
reorganisation-energy calculations, on PySCF's default cavity — modified-Bondi radii scaled by 1.2, 302 Lebedev
points per atomic sphere, and a 2.0 Å placeholder radius for Os, Co, Ru and Ce, which the radius table lacks (how
the recorded version switches the surface of an atom that carries an ECP is stated in §2.7); the ZIF-cluster
couplings and the molecular-dynamics snapshot orbitals (§2.5) were computed in the gas phase, without a continuum.
SCF energies were converged to 10⁻⁶ E_h (10⁻⁷ E_h for the lumiflavin redox pair, 10⁻⁵ E_h for the
charge-localised ΔSCF couplings of the ZIF clusters). A level shift stabilised the open-shell UKS SCF where it
oscillated — 0.3 E_h on the Os(III) states of the speciation series and of the ωB97X tier and in the Co/Ce/Ru
reorganisation and ZIF-cluster calculations (0.5 E_h to reach the second charge-localised state of a cluster
pair), 0.2 E_h on the open-shell flavin species — and wherever it was applied, total energies, not the
(shift-biased) virtual orbital energies, were used for any energy difference. The B3LYP osmium couples whose
Os(III) LUMO is reported (the device mediator and the Hammett series) were converged without a shift, a
second-order (Newton) solver taking over where DIIS stalled. Heavy-metal `density_fit` was *not* used
(the auto-generated auxiliary basis is slower for Os/Ce than the exact integrals).

## 2.3 Redox energetics: ΔSCF and the FAD→Os cascade

The mediator (Os(III)/Os(II)) and flavin redox energies were obtained by **ΔSCF**, i.e. as the
total-energy difference between the two charge/spin states at a fixed (vertical) geometry, rather
than from Koopmans orbital energies; an **adiabatic** ΔSCF (geometry optimised at B3LYP/def2-SVP,
single point at ωB97X/def2-TZVP) was computed for the cascade as a composite cross-check — the flavin
geometries relaxed and the osmium couple kept vertical, since no osmium geometry is optimised in this work. The
osmium mediator was built as the full cis-[Os(bpy)₂(L)(X)]ⁿ⁺ octahedron by rigid-body placement
of MMFF94s-optimised<sup>45,46</sup> ligands (RDKit<sup>47</sup> cannot embed an octahedral metal centre) onto assumed
target distances — Os–N(bpy) 2.06 Å at a 78° bite, Os–N(L) and Os–O 2.10 Å, Os–Cl 2.38 Å — for which no primary
source is used in this work; a shared parameterised builder generated the single-complex reference,
the 4,4′-substituent **Hammett series**<sup>22</sup> (its σ_para values are the conventional tabulated constants, taken as an ASSUMED input that this work did not check against a primary compilation — the fitted slope inherits them, while the series ORDER, which the design rule uses, is not moved by a revision of a few hundredths), and the chloro / aqua / bis-imidazole **speciation**
forms from one source. The monodentate distances are realised as targeted, the rigid chelate is not: the realised
geometry has Os–N(bpy) 2.091–2.099 Å and a bite angle of 80.1–80.6° across the series. For comparison only — no
crystal structure of this complex class was found — related osmium centres in the Crystallography Open Database
(COD) give Os(II)–N(bpy) 2.056–2.066 Å with a 77.8–78.3° bite in [Os(bpy)₃]²⁺ (COD 4115954); Os–Cl 2.36–2.38 Å
in Os(III) chloro-imidazole complexes (COD 4305719, 4305720, 4341249) and 2.40–2.44 Å in Os(II) polypyridyl
complexes (COD 1544713, 4320705, 4335836); and Os–N 2.05–2.11 Å and Os–O 2.10–2.13 Å to imidazole, pyridine and
aqua or hydroxo ligands across the two oxidation states (COD 4305719, 4305720, 4341249, 7718102, 7718103). The bpy
targets thus sit inside the [Os(bpy)₃]²⁺ ranges, the Cl target at the top of the Os(III) range and below the
Os(II) one, and the monodentate N and O targets inside the related ranges, while the realised chelate is up to 0.04 Å longer and
3° wider than in [Os(bpy)₃]²⁺. The same geometry is used for both oxidation states and for every member of the
substituent and speciation series, so an error in it is largely common to the points of a series; we expect it
to bear more on absolute redox energies than on within-series trends. Its size on an absolute number was computed
for the device couple: closing both chelates onto the targets — each bipyridine re-optimised (MMFF94s) with its
N···N held at the spacing the two targets imply, which realises Os–N(bpy) 2.060 Å at a 78.0° bite — lowers the
Os(II) state by 0.069 eV and the Os(III) state by 0.044 eV and so moves the vertical ΔE_red(III→II) by −0.026 eV
(B3LYP/6-31G(d)/LANL2DZ in C-PCM, computed in the conda-lock environment against the lock re-run of the same
couple, §2.7; record `cache/reproduction/os_chelate_sensitivity.json`). The other members of the class were not
recomputed.

## 2.4 Proton-coupled electron transfer (PCET)

The FAD/FADH₂ potential is a 2 e⁻/2 H⁺ process, so the proton was handled by a **thermodynamic
proton reference** (the experimental aqueous proton free energy<sup>16</sup>) rather than by an explicit
hydronium ion — implicit solvent over-stabilises small cations such as H₃O⁺ by several eV and is
unsuitable for proton-transfer corrections. The same reference was used to test whether a
proton-coupled re-framing of the first anode oxidation (FADH₂ → FADH• + H⁺ + e⁻) alters the
cascade thermodynamics.

## 2.5 Electron-transfer kinetics

**Anode tunnelling pathway.** The through-bond donor→acceptor coupling decay was evaluated with the
**Beratan–Onuchic** pathway model<sup>14</sup> over the AF3 structure (per-step σ/H-bond/through-space decay
factors), reporting the dominant path and its β·d.

**Cathode direct electron transfer (DET).** Inter-metal electronic couplings t_ij in the bimetallic
Cu–Co–Ce ZIF nanozyme were obtained from **charge-localised ΔSCF-UKS** energy splittings on
clash-free cluster geometries (a bridging imidazole N–H that collided with the second metal was
deprotonated to the imidazolate, restoring physical coordination). For the rate-limiting Cu–Co hop the
coupling was recomputed by a two-state orbital diabatisation of our own construction, labelled FO-DFT in the tables and figures (it is neither the fragment-orbital basis of textbook FO-DFT nor the dipole-based generalised Mulliken–Hush scheme, and no published implementation is claimed for it): from one UKS
SCF of the Cu–Co cluster, the two frontier orbitals with the largest combined Cu-d + Co-d character were
rotated into the basis that diagonalises their Cu-projected Mulliken population (a population-based
localisation), leaving one orbital on each metal; t_ij is the off-diagonal Fock element in that
basis, and the difference of the two diagonal elements is the site-energy gap carried as the hop's driving
force. A physicality check — the two localised orbitals on distinct metals, t_ij inside a physical band —
flags a non-physical pair instead of reporting it. Hopping rates followed the
**Marcus** expression<sup>13</sup> with the reorganisation energy computed (below), not assumed; the total DET
rate is the series combination of the three hops.

**Reorganisation energies (Nelsen 4-point).** Inner-sphere λ was computed by the four-point method<sup>15</sup>
(two relaxed geometries + two cross single-points seeded from the diagonal density). For the
cathode this was applied to the well-behaved mixed-valence metal couples — **Co, Ce and Ru; Cu(II/I)
was not computed**, a d¹⁰ Cu(I) hexa-aqua optimisation being unphysical in implicit solvent, so λ(Cu)
enters as a bracket of two literature readings of Cu(II/I) self-exchange — an **assumed** textbook value of
2.0 eV, for which no primary source is cited here, and 2.4 eV, the value for Cu(phen)₂²⁺/⁺<sup>48</sup> —
judged at its adverse end (§3.4), and λ_hop(Cu–Co) is half
computed and half cited. The literature-λ scenario of §3.4 and Table 3 pairs that bracket with **assumed**
textbook values at the remaining nodes (Co 1.4, Ce 1.0 and Ru 0.8 eV), likewise without a cited primary;
both assumptions are labelled as such in the scripts that consume them, and the scenario is read at its
adverse corner rather than as a measurement. For the anode the
physically-correct **FADH⁻/FADH• (deprotonated semiquinone) couple** was used — the naïve
FADH₂/FADH₂•⁺ radical-cation is geometrically pathological in implicit solvent and does not yield
a meaningful λ. Reported λ are inner-sphere; the Marcus outer-sphere term adds on top.

**Thermal ensemble.** Frames were taken from a separate explicit-solvent molecular-dynamics production
trajectory of the enzyme in its immobilisation matrix, run with OpenMM<sup>49</sup> using Amber ff14SB<sup>50</sup> for
the protein, GAFF2 parameters<sup>51</sup> for the FAD cofactor and the matrix components, and TIP3P-FB water<sup>52</sup>
(scripts in the Supporting Information). Periodic images were re-assembled with MDTraj<sup>53</sup> so that the
protein is whole and the non-covalently bound FAD lies in the same image, and the Beratan–Onuchic analysis
was replayed on 15 frames; the ensemble rate enters through the conformational-gating factor
⟨exp(−2β·d)⟩/exp(−2⟨β·d⟩). For the flavin frontier orbital, the hydrogen-capped isoalloxazine ring was cut
from MD snapshots and evaluated by gas-phase B3LYP/6-31G(d) single points.

## 2.6 Cluster-continuum micro-solvation

To probe the implicit-solvation limit on the charge-changing octahedral couples, explicit
first/second-shell waters were added around the redox centre and the chloride ligand and the ΔSCF
redox energy re-evaluated as a function of shell size,<sup>17,54</sup> benchmarked on the [Os(H₂O)₆]³⁺/²⁺ couple
(the literature group-8 ~1 V PCM error<sup>19</sup>). The residual cascade gap was decomposed into a
chloro↔bis-imidazole differential-solvation bracket and a 4,4′-dimethyl substituent term.

## 2.7 Reproducibility

The pipeline is fully scripted (fixed RDKit embedding seeds, a shared geometry / DFT-runner library, committed
cache JSONs) and was run in one **recorded** environment (PySCF 2.11.0, geomeTRIC 1.1, Python 3.12; the exact
package list with checksums is in the Supporting Information). Repeated calculations return their energies within
the SCF tolerance, with one exception: the open-shell Os(III) of the [Os(H₂O)₆]³⁺/²⁺ benchmark can converge to
different SCF solutions — two committed runs of that couple in the recorded environment differ by 2.4 meV in
ΔE_red, and the second-shell shift (§3.5) is quoted from one of them. That environment was installed from
conda-forge on 2026-05-24 with PySCF unpinned, when 2.11.0 was the newest osx-arm64 build there. The repository's
conda-lock file was generated after the calculations and resolves PySCF 2.13.1, so a re-run under it is a
reproduction attempt, not a replay of the environment the numbers came from. The size of that gap was measured
rather than assumed: re-running the flavin single points (script 20) and the derived E°(FAD/FADH₂) (script 32)
under the lock (PySCF 2.13.1, geomeTRIC 1.1.1, Python 3.12, osx-arm64) reproduced the committed caches
to within 4 × 10⁻¹⁰ Ha in total electronic energy and 10⁻¹⁰ eV in orbital energies, with every reported (rounded) quantity
identical; the field-by-field record is committed beside the caches
(`cache/reproduction/lock_rerun_2026-09-30.json`). The two heavier caches re-run under the lock
(`cache/reproduction/lock_rerun_2026-10-01.json`) behave differently from each other: the gas-phase FO-DFT Cu–Co
coupling (script 24b) reproduces every reported field exactly at printed precision, whereas the B3LYP osmium
couple (script 21f), converged on the same geometry in both environments (identical RDKit version), differs by
5 × 10⁻⁵ to 2 × 10⁻⁴ Ha — far above its 10⁻⁶ Ha SCF tolerance — and under the lock (PySCF 2.13.1) gives
ΔE_red(III→II) = −4.3841 eV against the committed −4.3808 eV, with the Os(III) LUMO 10 meV lower.

The cause is a change of the cavity, not of the numerics. PySCF 2.13.0 fixed a bug in which its PCM module
assigned incorrect radii to ECP atoms (PySCF 2.13.0 release notes; pull request 3159 of the PySCF repository): up
to 2.12 the switching function of each atomic sphere took its radius at the core-reduced nuclear charge, so
osmium under the LANL2DZ ECP (effective charge 16) was switched with the radius of sulfur while its surface
points sat on its own. The fixed build reached conda-forge for osx-arm64 on 2026-05-27. Emulating the fix in the
recorded environment (script 75; record `cache/reproduction/pcm_ecp_radius_attribution.json`) reproduces the lock
values of the device couple to 5.4 × 10⁻¹⁰ Ha in both oxidation states, and those of the closed-shell
[Os(H₂O)₆]²⁺ to 2.1 × 10⁻¹² Ha; for the open-shell [Os(H₂O)₆]³⁺ the emulated and lock runs meet as well
(6.4 × 10⁻¹⁰ Ha), but the recorded run lies 20 meV away — some thirty times the closed-shell effect of the fix,
far beyond a change of cavity — which points to a different SCF solution rather than to the cavity, so that state
is not attributed (2.13.0 also changed SCF defaults). The bug acts on every calculation with an ECP metal in the
continuum — both tiers of the osmium couples, the Hammett, speciation and micro-solvation series and the Co/Ce/Ru
reorganisation energies — and on the quantities derived from them (the Koopmans offset and the adiabatic ΔSCF of
Table 2, the PCET cascade, the cathode λ); the flavin chain (no ECP) and the gas-phase ZIF couplings lie outside it
by construction, which is why scripts 20, 32 and 24b reproduced exactly. Of the committed caches in that class only
the B3LYP device couple was re-run under the lock; for the others the size of the gap is bounded by this argument
and by the device and closed-shell measurements above, not measured.

What moves is the third decimal of ΔE_red and the second decimal of the Os(III) LUMO and of the orbital offset
built on it: on the device couple (identical to the Me row of Table 4), ΔE_red −4.381 eV, LUMO −4.086 eV and
offset −1.0514 eV in the recorded environment read −4.384, −4.096 and −1.0411 eV under the lock, so the Koopmans
offset of §3.5 and Fig 3 becomes −1.04 eV. The shift is far below the ~1 eV continuum-solvation limit that the
osmium results are themselves reported against, so it changes no conclusion drawn here, and the points of each
series share one cavity convention. The committed caches — the recorded-environment numbers — are what the paper
quotes. Every figure/number traces to a numbered script under `tools/in_silico/`. The scripts and golden
reference outputs are provided as Supporting Information.
