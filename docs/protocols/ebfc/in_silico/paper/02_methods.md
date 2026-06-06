# 2. Computational Methods — draft (Стаття 1)

> **Draft section.** Prose for the paper's Methods (§2 of [`00_OUTLINE.md`](00_OUTLINE.md)). All
> numeric results are referenced from [`SUMMARY.md`](../SUMMARY.md) (One-Home) — this draft
> describes the *methods*, the Results sections report the *numbers*. EN (target = J. Phys. Chem. B).
> Status: first pass, founder to refine (depth, journal house style, ref formatting).

## 2.1 Structure prediction and active-site models

The deglycosylated FAD-dependent glucose dehydrogenase (*Glomerella cingulata*, GcGDH) was
modelled with **AlphaFold 3**, with the eleven N-glycosylation sequons (N–X–S/T, X≠P) mutated
to glutamine to give the aglycosylated production variant used throughout. The FAD cofactor was
placed from the AF3 complex prediction; the cofactor-to-surface depth and the electron-exit
region were measured in ChimeraX. Active-site clusters for the redox and proton-coupled
calculations were carved from the predicted structure (isoalloxazine ring plus the H-bonding and
charged residues within ≈5 Å), retaining backbone amide caps.

## 2.2 Electronic-structure setup

All density-functional calculations used **PySCF** (version pinned in the repository
environment, §2.6). Two functionals were employed: **B3LYP** for the orbital-resolved and ΔSCF
energetics, and the range-separated hybrid **ωB97X** for a higher-rung adiabatic cross-check. The
basis was **6-31G(d)** on C/H/N/O/first-row metals with the **LANL2DZ** effective-core potential
and basis on osmium (and Cu/Co), and the **Stuttgart RSC** ECP/basis on cerium; the publication
cross-checks used **def2-TZVP**. Aqueous solvation was treated with the **C-PCM** continuum
(ε = 78.36). For open-shell transition-metal states (Os(III), the Cu/Co/Ce hops) a level shift of
0.3 was applied to stabilise the UKS SCF, and total energies — not the (shift-biased) virtual
orbital energies — were used for any energy difference. Heavy-metal `density_fit` was *not* used
(the auto-generated auxiliary basis is slower for Os/Ce than the exact integrals).

## 2.3 Redox energetics: ΔSCF and the FAD→Os cascade

The mediator (Os(III)/Os(II)) and flavin redox energies were obtained by **ΔSCF**, i.e. as the
total-energy difference between the two charge/spin states at a fixed (vertical) geometry, rather
than from Koopmans orbital energies; an **adiabatic** ΔSCF (geometry optimised at B3LYP/def2-SVP,
single point at ωB97X/def2-TZVP) was computed for the cascade as a composite cross-check. The
osmium mediator was built as the full cis-[Os(bpy)₂(L)(X)]ⁿ⁺ octahedron by rigid-body placement
of MMFF-optimised ligands onto crystallographic Os–ligand bond lengths (RDKit cannot embed an
octahedral metal centre); a shared parameterised builder generated the single-complex reference,
the 4,4′-substituent **Hammett series**, and the chloro / aqua / bis-imidazole **speciation**
forms from one source.

## 2.4 Proton-coupled electron transfer (PCET)

The FAD/FADH₂ potential is a 2 e⁻/2 H⁺ process, so the proton was handled by a **thermodynamic
proton reference** (the experimental aqueous proton free energy) rather than by an explicit
hydronium ion — implicit solvent over-stabilises small cations such as H₃O⁺ by several eV and is
unsuitable for proton-transfer corrections. The same reference was used to test whether a
proton-coupled re-framing of the first anode oxidation (FADH₂ → FADH• + H⁺ + e⁻) alters the
cascade thermodynamics.

## 2.5 Electron-transfer kinetics

**Anode tunnelling pathway.** The through-bond donor→acceptor coupling decay was evaluated with the
**Beratan–Onuchic** pathway model over the AF3 structure (per-step σ/H-bond/through-space decay
factors), reporting the dominant path and its β·d.

**Cathode direct electron transfer (DET).** Inter-metal electronic couplings t_ij in the bimetallic
Cu–Co–Ce ZIF nanozyme were obtained from **charge-localised ΔSCF-UKS** energy splittings on
clash-free cluster geometries (a bridging imidazole N–H that collided with the second metal was
deprotonated to the imidazolate, restoring physical coordination). Hopping rates followed the
**Marcus** expression with the reorganisation energy computed (below), not assumed; the total DET
rate is the series combination of the three hops.

**Reorganisation energies (Nelsen 4-point).** Inner-sphere λ was computed by the four-point method
(two relaxed geometries + two cross single-points seeded from the diagonal density). For the
cathode this was applied to the well-behaved mixed-valence metal couples; for the anode the
physically-correct **FADH⁻/FADH• (deprotonated semiquinone) couple** was used — the naïve
FADH₂/FADH₂•⁺ radical-cation is geometrically pathological in implicit solvent and does not yield
a meaningful λ. Reported λ are inner-sphere; the Marcus outer-sphere term adds on top.

## 2.6 Cluster-continuum micro-solvation

To probe the implicit-solvation limit on the charge-changing octahedral couples, explicit
first/second-shell waters were added around the redox centre and the chloride ligand and the ΔSCF
redox energy re-evaluated as a function of shell size, benchmarked on the [Os(H₂O)₆]³⁺/²⁺ couple
(the literature group-8 ~1 V PCM error). The residual cascade gap was decomposed into mediator
speciation and differential solvation contributions.

## 2.7 Reproducibility

The pipeline is fully scripted and deterministic (fixed RDKit embedding seeds, a shared geometry
/ DFT-runner library, committed cache JSONs) and runs in a **conda-lock-pinned** environment;
every figure/number traces to a numbered script under `tools/in_silico/`. The scripts and golden
reference outputs are provided as Supporting Information.
