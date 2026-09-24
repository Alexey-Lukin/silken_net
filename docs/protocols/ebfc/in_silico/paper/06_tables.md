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
| DET coupling | ΔSCF-UKS energy-splitting (24); FO-DFT two-state Mulliken–Hush (24b) | none (gas phase) | ZIF inter-metal t_ij |

*Reproducibility: deterministic scripts in `tools/in_silico`; every DFT cache computed with PySCF 2.11.0 (the recorded environment — §2.7).*

## Table 2. Anode→mediator cascade ΔG per electron, all methods

| Method | ΔG/e⁻ (eV) | Direction | vs verified −0.574 eV |
|---|---|---|---|
| Koopmans ωB97X (orbital offset) | +6.020 | uphill | range-separation artefact — *never use* |
| ΔSCF ωB97X (vertical) | +1.395 | uphill | +1.97 |
| **ΔSCF ωB97X (adiabatic)** | **+1.034** | uphill | +1.61 |
| B3LYP Koopmans «corrected» | -0.07 | — | **withdrawn** (tuned to the wrong −0.14) |
| **Experiment (verified E°s)** | **-0.57** | **downhill** | reference |

*The raw uphill ΔG is the implicit-solvation method limit (differential PCM solvation, chloro↔bis-Im bracket + the 4,4′-dimethyl substituent, Fig 5 / ②); the verified +574 mV / −0.574 eV is E°(Os) +309 − E°(FAD-GDH) −265 mV vs SHE.*

## Table 3. Cathode DET hops, couplings and reorganisation energies

| Hop | t_ij ΔSCF (eV) | t_ij FO-DFT (eV) | λ_hop lit (eV) | λ_hop computed (eV) |
|---|---|---|---|---|
| **Cu–Co** (T1↔node, bottleneck) | 0.00128 | 0.00546 | 1.70–1.90 | 2.55–2.75 |
| Co–Ce (node↔vacancy) | 0.00687 | — | 1.20 | 1.98 |
| Ce–graphene (vacancy↔MWCNT) | 0.11294 | — | — | — |

**Cu–Co bottleneck margin vs enzymatic turnover (10³ s⁻¹), by λ scenario** — each a bracket over the sign of the computed site-energy gap and the λ(Cu) reading; the consumer reading is the ADVERSE corner:

| λ scenario | adverse corner | ΔG = 0 (default, not a measurement) | favourable corner |
|---|---|---|---|
| canon λ=0.7 (old, withdrawn) | ×6.5e+02 | ×3.6e+04 | ×8e+05 |
| **literature λ** (Cu 2.0–2.4 / Co 1.4 / Ce 1.0) | **×0.0045** | ×1.4 | ×40 |
| computed λ (B3LYP, Co over-est; Cu literature) | ×1e-06 | ×0.0003 | ×0.0092 |
| Ru-swap (Co→Ru, computed λ 0.78) — *spread is λ(Cu) only: the Cu–Ru site gap is not obtainable from the minimal cluster, so every column is ΔG = 0* | ×4.2 | ×31 | ×31 |
| FO-DFT rigorous coupling (literature λ) | ×0.081 | ×25 | ×732 |

*Inner-sphere λ via Nelsen 4-point on [M(H₂O)₆] (35) for Co, Ce and Ru; λ(Cu) is a literature bracket of two solution readings — 2.0 eV (textbook value, source not found) and 2.4 eV (Cu(phen)₂²⁺/⁺ self-exchange, Gray & Winkler) — a Cu(I) d¹⁰ hexa-aqua optimisation being unphysical, so λ_hop(Cu–Co) is half computed and half cited. Both readings are unconstrained solution couples; a framework-held Cu–N₄ site can lie below both (0.7 eV in azurin, same source), so the favourable corner is no floor. B3LYP over-estimates the first-row λ (Co spin-crossover) → the literature row is the honest estimate. The adverse corner is the uphill gap sign at the higher λ(Cu). Cathode: rate-limiting at the adverse corner, above turnover at the favourable one — the bracket straddles turnover.*

## Table 4. Osmium mediator series — E° and cascade-Δ vs Hammett σ (①)

cis-[Os(4,4′-X-bpy)₂(1-MeIm)Cl]⁺/²⁺ at constant charge; B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF.

| 4,4′-X | σ_para | ΔE_red(III→II) (eV) | Os(III) LUMO (eV) | cascade Δ (eV) | note |
|---|---|---|---|---|---|
| NMe₂ | -0.83 | -3.910 | -3.636 | -1.5013 | donor saturation |
| NH₂ | -0.66 | -3.905 | -3.637 | -1.4997 |  |
| OMe | -0.27 | -4.286 | -4.002 | -1.1355 |  |
| Me | -0.17 | -4.381 | -4.086 | -1.0514 |  |
| H | +0.00 | -4.530 | -4.228 | -0.9093 | reference |
| COOH | +0.45 | -4.936 | -4.595 | -0.5424 |  |
| CF₃ | +0.54 | -4.957 | -4.635 | -0.5023 | inert option |
| NO₂ | +0.78 | -5.262 | -4.905 | -0.2319 | unstable on cycling |
| SO₂CF₃ | +0.96 | -5.256 | -4.910 | -0.2269 | realistic optimum (inert) |

*Design rule: cascade Δ rises monotonically with σ (−1.50 NMe₂ → −0.23 SO₂CF₃); ΔE_red LFER slope ≈ −0.92 eV/σ over OMe→NO₂ (Fig 3b). Higher E°(Os) lowers OCV, so the cell optimum (~+309 mV) balances driving force vs overpotential.*

