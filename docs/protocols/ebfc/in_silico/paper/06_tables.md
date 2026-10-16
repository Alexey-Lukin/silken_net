# Tables — Стаття 1 (EBFC quantum chemistry)

> **Generated** by [`tools/in_silico/scripts/61_paper_tables.py`](../../../../tools/in_silico/scripts/61_paper_tables.py) from the result caches (drift-safe: every headline number is asserted against [`SUMMARY.md`](../SUMMARY.md) at build). **Do not hand-edit** — change SUMMARY/the cache and re-run. Re-run: `mamba run -n silken_md python tools/in_silico/scripts/61_paper_tables.py`.

## Table 1. Levels of theory

| Tier | Functional | Basis / ECP | Solvent | Used for |
|---|---|---|---|---|
| Screening | B3LYP | 6-31G(d); LANL2DZ (Os, Cu, Co); stuttgart_rsc (Ce) | C-PCM (water) | frontier orbitals, ΔSCF redox, mediator series (①), speciation (②) |
| Publication — cascade | ωB97X (FAD geometries B3LYP/def2-SVP) | def2-TZVP; LANL2DZ (Os) | C-PCM (water) | adiabatic ΔSCF cross-check |
| Publication — speciation | ωB97X | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | speciation functional-robustness (②) |
| PCET | B3LYP/6-31G(d) + thermodynamic proton reference (Isse–Gennaro) | — | PCM | FAD E°; semiquinone cascade |
| Reorganisation λ | B3LYP/def2-SVP (29b), 6-31G(d)+LANL2DZ/stuttgart_rsc (35); Nelsen 4-point | C-PCM | inner-sphere λ_i; + Marcus two-sphere outer-sphere λ_o (29c, analytical) |
| DET coupling | ΔSCF-UKS energy-splitting (24); two-state orbital diabatisation, FO-DFT label (24b) | none (gas phase) | ZIF inter-metal t_ij |

*Reproducibility: scripted, fixed-seed DFT in `tools/in_silico`; every DFT cache behind these tables computed with PySCF 2.11.0 (the recorded environment — §2.7; the lock re-runs are separate records, SI S3).*

## Table 2. Anode→mediator cascade ΔG per electron, all methods

| Method | ΔG/e⁻ (eV) | Direction | vs verified −0.574 eV |
|---|---|---|---|
| Koopmans ωB97X (orbital offset) | +4.826 | uphill | range-separation artefact — *never use* |
| ΔSCF ωB97X (vertical) | +0.095 | uphill | +0.67 |
| **ΔSCF ωB97X (adiabatic)** | **−0.079** | downhill | +0.49 |
| B3LYP Koopmans «corrected» | −0.07 | — | **withdrawn** (tuned to the wrong −0.14) |
| **Experiment (verified E°s)** | **−0.57** | **downhill** | reference |

*FADH₂ = the 1,5-dihydro tautomer. [finalise — revision step 3, 00_07 HW.5.IS: these rows are one-electron readings, not like-for-like with the verified value, so the difference column and the table are rebuilt like-for-like in step 3.] The verified +574 mV / −0.574 eV is E°(Os) +309 − E°(FAD-GDH) −265 mV vs SHE.*

## Table 3. Cathode DET hops, couplings and reorganisation energies

| Hop | t_ij used (eV) | crude ΔSCF t_ij (eV) | crude ΔE ÷ SCF tolerance | λ_hop lit (eV) | λ_hop computed (eV) |
|---|---|---|---|---|---|
| **Cu–Co** (T1↔node, bottleneck) | **0.00546** (FO-DFT) | 0.00128 | 9.4 | 1.70–1.90 | 2.55–2.75 |
| Co–Ce (node↔vacancy) | 0.00687 (crude) | 0.00687 | 50 | 1.20 | 1.98 |
| Ce–graphene (vacancy↔MWCNT) | 0.11294 (crude) | 0.11294 | 830 | — | — |

**Cu–Co bottleneck margin vs enzymatic turnover (10³ s⁻¹), by λ scenario, on the FO-DFT coupling** — each a bracket over the sign of the computed site-energy gap and the λ(Cu) reading; the consumer reading is the ADVERSE corner:

| λ scenario | adverse corner | ΔG = 0 (default, not a measurement) | favourable corner |
|---|---|---|---|
| canon λ=0.7 (old, withdrawn) | ×1.2e+04 | ×6.6e+05 | ×1e+06 |
| **literature λ** (Cu 2.0–2.4 / Co 1.4, assumed / Ce 1.0) | **×0.081** | ×25 | ×7.3e+02 |
| **computed λ** (B3LYP: Co 3.09; Cu literature) | **×1.9e-05** | ×0.0054 | ×0.17 |
| Ru-swap (Co→Ru, computed λ 0.78) — *indicative: λ(Ru) sums Nelsen halves -0.26 and +1.04 eV; the Cu–Ru coupling and gap are not obtainable from the minimal cluster, so it borrows the Cu–Co coupling and every column is ΔG = 0* | ×76 | ×5.7e+02 | ×5.7e+02 |
| crude ΔSCF coupling, literature λ — *superseded record* | ×0.0045 | ×1.4 | ×40 |

*Inner-sphere λ via Nelsen 4-point (35) on [Co(NH₃)₆] for Co and on [M(H₂O)₆] for Ce and Ru; λ(Cu) is a literature bracket of two solution readings — 2.0 eV (textbook value, source not found) and 2.4 eV (Cu(phen)₂²⁺/⁺ self-exchange, Gray & Winkler) — a Cu(I) d¹⁰ hexa-aqua optimisation being unphysical, so λ_hop(Cu–Co) is half computed and half cited. Both readings are unconstrained solution couples; a framework-held Cu–N₄ site can lie below both (0.7 eV in azurin, same source), so the favourable corner is no floor. The adverse corner is the uphill gap sign at the higher λ(Cu). The crude ΔSCF couplings are half the energy difference of two unconstrained SCF solutions from one start; for Cu–Co that difference is a single-digit multiple of the SCF tolerance, so the margins use the two-state diabatisation (FO-DFT label, Methods §2.5). The verdict is conditional on λ(Co): turnover needs λ(Co) ≲ 2.0 eV at ΔG = 0 on the 2.0 eV λ(Cu) reading and ≲ 0.9 eV at the adverse corner; the computed 3.09 eV puts the cathode below turnover at every corner, the assumed 1.4 eV (no primary) across it.*

## Table 4. Osmium mediator series — E° and cascade-Δ vs Hammett σ (①)

cis-[Os(4,4′-X-bpy)₂(1-MeIm)Cl]⁺/²⁺ at constant charge; B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF; last column — the same ΔSCF at ωB97X/def2-TZVP on the same geometry, minus the B3LYP value.

| 4,4′-X | σ_para | ΔE_red(III→II) (eV) | Os(III) LUMO (eV) | cascade Δ (eV) | note | ω−B3 (eV) |
|---|---|---|---|---|---|---|
| NMe₂ | -0.83 | -3.910 | -3.636 | -0.3823 | donor saturation | +0.055 |
| NH₂ | -0.66 | -3.905 | -3.637 | -0.3807 |  | +0.055 |
| OMe | -0.27 | -4.286 | -4.002 | -0.0165 |  | — |
| Me | -0.17 | -4.381 | -4.086 | +0.0676 |  | +0.138 |
| H | +0.00 | -4.530 | -4.228 | +0.2097 | reference | +0.137 |
| Cl | +0.23 | -4.697 | -4.385 | +0.3674 |  | — |
| COOH | +0.45 | -4.936 | -4.595 | +0.5766 |  | — |
| CF₃ | +0.54 | -4.957 | -4.635 | +0.6167 | inert option | — |
| NO₂ | +0.78 | -5.262 | -4.905 | +0.8871 | unstable on cycling | +0.263 |
| SO₂CF₃ | +0.96 | -5.256 | -4.910 | +0.8921 | inert; order vs NO₂ open | +0.184 |

*Design rule: cascade Δ rises with σ (−0.38 NMe₂ → +0.89 SO₂CF₃); the order of NO₂→SO₂CF₃ (+5.0 meV) is not decided — relaxing NO₂ alone moves NO₂'s own cascade Δ by −198 meV with Os(III) on its own minimum and +102 meV with Os(III) vertical, and SO₂CF₃ was not relaxed; ΔE_red LFER slope ≈ −0.92 eV/σ over OMe→NO₂ (Fig 3b). Higher E°(Os) lowers OCV, so the cell optimum (~+309 mV) balances driving force vs overpotential. ωB97X/def2-TZVP cross-check: over Me, H, NO₂ the slope is −0.79 against −0.93 eV/σ at B3LYP (×0.85, resting on the one acceptor point of that set, NO₂; outside the fit, SO₂CF₃ carries ω−B3 +0.184); at Me/H, where ωB97X also exists with 6-31G(d), the local slope runs −0.876 → −0.800 → −0.878 eV/σ, i.e. the functional and the basis change pull opposite ways; with ωB97X also at 6-31G(d) on every point of Me, H, NO₂, the slope runs −0.931 → −0.789 → −0.791 eV/σ — functional ×0.85, basis ×1.00.*

