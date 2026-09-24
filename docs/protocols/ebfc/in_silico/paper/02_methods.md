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
region were measured in ChimeraX.<sup>28,29</sup> Active-site clusters for the redox and proton-coupled
calculations were carved from the predicted structure (isoalloxazine ring plus the H-bonding and
charged residues within ≈5 Å), retaining backbone amide caps.

## 2.2 Electronic-structure setup

All density-functional calculations used **PySCF**<sup>30,31</sup> (version pinned in the repository
environment, §2.7). Two functionals were employed: **B3LYP**<sup>32–34</sup> (the PySCF/libxc `B3LYP`, i.e. with the VWN RPA local-correlation
term<sup>35</sup> of the Gaussian convention, not the VWN5 variant) for the orbital-resolved and ΔSCF
energetics, and the range-separated hybrid **ωB97X**<sup>36</sup> for a higher-rung adiabatic cross-check. The
basis was **6-31G(d)**<sup>37–39</sup> on all non-metal atoms, with the **LANL2DZ** effective-core potential
and basis<sup>40</sup> on the transition metals (Os, Cu, Co, Ru) and the **Stuttgart RSC** ECP/basis on cerium.<sup>41</sup> The
adiabatic ωB97X cross-check (§2.3) replaced 6-31G(d) by **def2-TZVP**<sup>42</sup> on the non-metal atoms, keeping LANL2DZ
on osmium; the ωB97X speciation cross-check kept the 6-31G(d)/LANL2DZ basis of the B3LYP tier. Aqueous
solvation was treated with the **C-PCM** continuum<sup>43,44</sup> (ε = 78.36) for the redox, speciation and
reorganisation-energy calculations; the ZIF-cluster couplings and the molecular-dynamics snapshot orbitals
(§2.5) were computed in the gas phase, without a continuum. For open-shell transition-metal states (Os(III), the Cu/Co/Ce hops) a level shift of
0.3 was applied to stabilise the UKS SCF, and total energies — not the (shift-biased) virtual
orbital energies — were used for any energy difference. Heavy-metal `density_fit` was *not* used
(the auto-generated auxiliary basis is slower for Os/Ce than the exact integrals).

## 2.3 Redox energetics: ΔSCF and the FAD→Os cascade

The mediator (Os(III)/Os(II)) and flavin redox energies were obtained by **ΔSCF**, i.e. as the
total-energy difference between the two charge/spin states at a fixed (vertical) geometry, rather
than from Koopmans orbital energies; an **adiabatic** ΔSCF (geometry optimised at B3LYP/def2-SVP,
single point at ωB97X/def2-TZVP) was computed for the cascade as a composite cross-check. The
osmium mediator was built as the full cis-[Os(bpy)₂(L)(X)]ⁿ⁺ octahedron by rigid-body placement
of MMFF94s-optimised<sup>45,46</sup> ligands onto crystallographic Os–ligand bond lengths [CITATION NEEDED]
(RDKit<sup>47</sup> cannot embed an octahedral metal centre); a shared parameterised builder generated the single-complex reference,
the 4,4′-substituent **Hammett series**<sup>22</sup> [CITATION NEEDED: σ_para values], and the chloro / aqua / bis-imidazole **speciation**
forms from one source.

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
coupling was recomputed by a two-state fragment-orbital (FO-DFT) diabatisation [CITATION NEEDED]: from one UKS
SCF of the Cu–Co cluster, the two frontier orbitals with the largest combined Cu-d + Co-d character were
rotated into the basis that diagonalises their Cu-projected Mulliken population (a Mulliken–Hush-style
population diabatisation), leaving one orbital on each metal; t_ij is the off-diagonal Fock element in that
basis, and the difference of the two diagonal elements is the site-energy gap carried as the hop's driving
force. A physicality check — the two localised orbitals on distinct metals, t_ij inside a physical band —
flags a non-physical pair instead of reporting it. Hopping rates followed the
**Marcus** expression<sup>13</sup> with the reorganisation energy computed (below), not assumed; the total DET
rate is the series combination of the three hops.

**Reorganisation energies (Nelsen 4-point).** Inner-sphere λ was computed by the four-point method<sup>15</sup>
(two relaxed geometries + two cross single-points seeded from the diagonal density). For the
cathode this was applied to the well-behaved mixed-valence metal couples — **Co, Ce and Ru; Cu(II/I)
was not computed**, a d¹⁰ Cu(I) hexa-aqua optimisation being unphysical in implicit solvent, so λ(Cu)
enters as the literature value [CITATION NEEDED] and λ_hop(Cu–Co) is half computed and half cited; for the anode the
physically-correct **FADH⁻/FADH• (deprotonated semiquinone) couple** was used — the naïve
FADH₂/FADH₂•⁺ radical-cation is geometrically pathological in implicit solvent and does not yield
a meaningful λ. Reported λ are inner-sphere; the Marcus outer-sphere term adds on top.

**Thermal ensemble.** Frames were taken from a separate explicit-solvent molecular-dynamics production
trajectory of the enzyme in its immobilisation matrix, run with OpenMM<sup>48</sup> using Amber ff14SB<sup>49</sup> for
the protein, GAFF2 parameters<sup>50</sup> for the FAD cofactor and the matrix components, and TIP3P-FB water<sup>51</sup>
(scripts in the Supporting Information). Periodic images were re-assembled with MDTraj<sup>52</sup> so that the
protein is whole and the non-covalently bound FAD lies in the same image, and the Beratan–Onuchic analysis
was replayed on 15 frames; the ensemble rate enters through the conformational-gating factor
⟨exp(−2β·d)⟩/exp(−2⟨β·d⟩). For the flavin frontier orbital, the hydrogen-capped isoalloxazine ring was cut
from MD snapshots and evaluated by gas-phase B3LYP/6-31G(d) single points.

## 2.6 Cluster-continuum micro-solvation

To probe the implicit-solvation limit on the charge-changing octahedral couples, explicit
first/second-shell waters were added around the redox centre and the chloride ligand and the ΔSCF
redox energy re-evaluated as a function of shell size,<sup>17,53</sup> benchmarked on the [Os(H₂O)₆]³⁺/²⁺ couple
(the literature group-8 ~1 V PCM error<sup>19</sup>). The residual cascade gap was decomposed into a
chloro↔bis-imidazole differential-solvation bracket and a 4,4′-dimethyl substituent term.

## 2.7 Reproducibility

The pipeline is fully scripted and deterministic (fixed RDKit embedding seeds, a shared geometry
/ DFT-runner library, committed cache JSONs) and runs in a **conda-lock-pinned** environment;
every figure/number traces to a numbered script under `tools/in_silico/`. The scripts and golden
reference outputs are provided as Supporting Information.
