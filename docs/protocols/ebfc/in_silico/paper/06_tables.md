# Tables — Стаття 1 (EBFC quantum chemistry)

> **Generated** by [`tools/in_silico/scripts/61_paper_tables.py`](../../../../tools/in_silico/scripts/61_paper_tables.py) from the result caches (drift-safe: every headline number is asserted against [`SUMMARY.md`](../SUMMARY.md) at build). **Do not hand-edit** — change SUMMARY/the cache and re-run. Re-run: `mamba run -n silken_md python tools/in_silico/scripts/61_paper_tables.py`.

## Table 1. Levels of theory

| Tier | Functional | Basis / ECP | Solvent | Used for |
|---|---|---|---|---|
| Screening | B3LYP | 6-31G(d); LANL2DZ (Os, Cu, Co); stuttgart_rsc (Ce) | C-PCM (water) | frontier orbitals, ΔSCF redox, mediator series (①), speciation (②) |
| Publication | ωB97X | def2-TZVP; LANL2DZ (Os) | C-PCM (water) | adiabatic ΔSCF cross-check; speciation functional-robustness |
| PCET | B3LYP/6-31G(d) + thermodynamic proton reference (Isse–Gennaro) | — | PCM | FAD E°; semiquinone cascade |
| Reorganisation λ | B3LYP/def2-SVP (29b), 6-31G(d)+LANL2DZ/stuttgart_rsc (35); Nelsen 4-point | C-PCM | inner-sphere λ_i; + Marcus two-sphere outer-sphere λ_o (29c, analytical) |
| DET coupling | ΔSCF-UKS energy-splitting (24); FO-DFT two-state Mulliken–Hush (24b) | C-PCM | ZIF inter-metal t_ij |

*Reproducibility: deterministic scripts in `tools/in_silico`, version-pinned conda-lock env.*

## Table 2. Anode→mediator cascade ΔG per electron, all methods

| Method | ΔG/e⁻ (eV) | Direction | vs verified −0.47 eV |
|---|---|---|---|
| Koopmans ωB97X (orbital offset) | +5.884 | uphill | range-separation artefact — *never use* |
| ΔSCF ωB97X (vertical) | +0.998 | uphill | +1.47 |
| **ΔSCF ωB97X (adiabatic)** | **+0.884** | uphill | +1.35 |
| B3LYP Koopmans «corrected» | -0.07 | — | **withdrawn** (tuned to the wrong −0.14) |
| **Experiment (verified E°s)** | **-0.47** | **downhill** | reference |

*The raw uphill ΔG is the implicit-solvation method limit (mediator speciation + PCM differential solvation, Fig 5 / ②); the verified +465 mV / −0.47 eV is E°(Os) +200 − E°(FAD-GDH) −265 mV vs SHE.*

## Table 3. Cathode DET hops, couplings and reorganisation energies

| Hop | t_ij ΔSCF (eV) | t_ij FO-DFT (eV) | λ_hop lit (eV) | λ_hop computed (eV) |
|---|---|---|---|---|
| **Cu–Co** (T1↔node, bottleneck) | 0.00128 | 0.00546 | 1.70 | 2.55 |
| Co–Ce (node↔vacancy) | 0.00687 | — | 1.20 | 1.98 |
| Ce–graphene (vacancy↔MWCNT) | 0.11294 | — | — | — |

**Cu–Co bottleneck margin vs enzymatic turnover (10³ s⁻¹), by λ scenario:**

| λ scenario | margin |
|---|---|
| canon λ=0.7 (old, withdrawn) | ×3.63e+04 |
| **literature λ** (Cu 2.0/Co 1.4/Ce 1.0) | **×1.38** (borderline) |
| computed λ (B3LYP, Co over-est) | ×0.000298 |
| Ru-swap (Co→Ru, computed λ 0.78) | ×31 |
| FO-DFT rigorous (ΔG −/0/+gap) | ×0.59 – ×732 (×25 at ΔG=0) |

*Inner-sphere λ via Nelsen 4-point on [M(H₂O)₆] (35); B3LYP over-estimates the first-row λ (Co spin-crossover) → the literature row is the honest estimate. Cathode is borderline / possibly co-limiting (k_DET ~ turnover).*

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

