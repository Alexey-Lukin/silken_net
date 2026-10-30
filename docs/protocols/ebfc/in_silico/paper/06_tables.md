# Tables — Стаття 1 (EBFC quantum chemistry)

> **Generated** by [`tools/in_silico/scripts/61_paper_tables.py`](../../../../tools/in_silico/scripts/61_paper_tables.py) from the result caches (drift-safe: every headline number is asserted against [`SUMMARY.md`](../SUMMARY.md) at build). **Do not hand-edit** — change SUMMARY/the cache and re-run. Re-run: `mamba run -n silken_md python tools/in_silico/scripts/61_paper_tables.py`.

## Table 1. Levels of theory

| Tier | Functional | Basis / ECP | Solvent | Used for |
|---|---|---|---|---|
| Cascade like for like · series · speciation | B3LYP | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | frontier orbitals, ΔSCF redox, the like-for-like cascade (Table 2), mediator series (①), speciation (②) |
| Thermochemistry | B3LYP + analytic C-PCM Hessian; RRHO at 298.15 K | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | the flavin E° at four levels (32b); the Os couple's zero-point energy, one form (96) |
| ωB97X one-electron readings | ωB97X single points (FAD geometries B3LYP/def2-SVP for the ΔSCF, B3LYP/6-31G(d) for the proton-coupled route) | def2-TZVP; LANL2DZ (Os) | C-PCM (water) | vertical and adiabatic ΔSCF of the first oxidation; the proton-coupled one-electron route with the proton reference (Table 2b) |
| Publication — speciation | ωB97X | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | speciation functional-robustness (②) |
| PCET | B3LYP + thermodynamic proton reference (Isse–Gennaro) | 6-31G(d) | C-PCM (water) | the 2e⁻/2H⁺ FAD E° (32, 32b) |
| PCET — basis and functional | B3LYP, then ωB97X, single points on 32b's minima + the same proton reference | def2-TZVP | C-PCM (water) | the 2e⁻/2H⁺ FAD E° one knob at a time (112); with the device couple's ωB97X energies (def2-TZVP; LANL2DZ (Os)) the device cascade at that tier (95, Table 2 footnote) |
| Reorganisation λ | B3LYP; Nelsen 4-point (29b, 35) | def2-SVP (29b, flavin); 6-31G(d) + LANL2DZ (Co, Ru) / stuttgart_rsc (Ce) (35) | C-PCM (water) | inner-sphere λ_i of the flavin semiquinone couple and of Co, Ce and Ru; + Marcus two-sphere outer-sphere λ_o for the flavin (29c, analytical) |
| DET coupling | B3LYP; ΔSCF-UKS energy-splitting (24); two-state orbital diabatisation, FO-DFT label (24b; the Ru swap 24c/24d) | 6-31G(d); LANL2DZ (Cu, Co, Ru); stuttgart_rsc (Ce) | none (gas phase) | ZIF inter-metal t_ij and the site-energy gap |

*Reproducibility: scripted, fixed-seed DFT in `tools/in_silico`; every DFT cache behind these tables computed with PySCF 2.11.0 (the recorded environment — §2.7; the lock re-runs are separate records, SI S3).*

## Table 2. The anode→mediator cascade like for like — the 2e⁻/2H⁺ flavin couple against each Os(III/II) form on one SHE scale

| Os form (B3LYP/6-31G(d)+LANL2DZ(Os)/C-PCM) | E°(Os) vs SHE, mV | acceptor side, mV | cascade, flavin MMFF el. | cascade, flavin relaxed el. | cascade, flavin + ZPE ¹ | cascade, flavin + RRHO ¹ |
|---|---|---|---|---|---|---|
| *flavin: E°(FAD/FADH₂) at pH 7, mV (donor side)* | | | *−155.4 (+64.6)* | *−118.7 (+101.3)* | *−429.5 (−209.5)* | *−419.0 (−199.0)* |
| chloro (device, programmatic) | +99.8 | +209.2 | +255.2 | +218.5 | +529.3 | +518.8 |
| chloro + 1 H₂O on Cl⁻ | +163.2 | +145.8 | +318.6 | +281.9 | +592.7 | +582.2 |
| chloro + 2 H₂O on Cl⁻ | +235.4 | +73.6 | +390.8 | +354.1 | +664.9 | +654.4 |
| chloro + 3 H₂O on Cl⁻ | +302.0 | +7.0 | +457.4 | +420.7 | +731.5 | +721.0 |
| chloro, Os(II) relaxed, Os(III) vertical | +212.4 | +96.6 | +367.8 | +331.1 | +641.9 | +631.4 |
| chloro, both states relaxed (adiabatic) | +126.3 | +182.7 | +281.7 | +245.0 | +555.8 | +545.3 |
| aqua (methodological reference) | +539.1 | −230.1 | +694.5 | +657.8 | +968.6 | +958.1 |
| bis-imidazole (brush-presented, hypothetical) | +632.6 | −323.6 | +788.0 | +751.3 | +1062.1 | +1051.6 |
| chloro, both states relaxed (adiabatic), Os side with its own ZPE ² | +126.3 el. / +166.8 + ZPE | +182.7 el. / +142.2 + ZPE | — | +245.0 | +596.3 | not comparable ³ |
| **Measured (free flavin; film-bound mediator, pH 7.4)** | **+309** | | **+529** | **+529** | **+529** | **+529** |

*Cascade = E°(Os) − E°(FAD/FADH₂, pH 7) in mV, > 0 = downhill; every cell at this tier (B3LYP/6-31G(d)) is downhill (smallest +218.5 mV). Donor side = computed − measured free flavin (−220 mV); acceptor side = measured (+309 mV) − computed Os; their sum is the gap to the measured +529 mV (the free flavin against the film-bound mediator, whose preparation moves its E°′ by 135 mV, §3.3; the flavin at pH 7, the film at pH 7.4). The device's +574 mV adds the measured protein shift of the bound cofactor (−45 mV), which is not computed here. The flavin levels: MMFF geometries (script 32), relaxed (32b), + its zero-point energy, + its RRHO free energy. ¹ One-sided: these levels correct the flavin only — every Os form stays at its electronic energy, except the row marked ². ² Both Os states relaxed and given their own zero-point energy (script 96). ³ The two Os states' soft-mode censuses differ, so their RRHO free energies are not compared. Every cell shares one functional, one continuum, one absolute-SHE convention (4.281 V) and a scalar-relativistic osmium, which the cells do not test: spin–orbit coupling on osmium, omitted, reverses a cell beyond 218.5 mV; at the size ref 63 computes for [Os(bpy)₃] (−250 mV) it turns 2 of the 32 cells uphill, 5 at the octahedral summary of ref 63's abstract (−300 mV) and up to 10 at the larger rows of its Table S2 (−400 mV), while against the measured flavin the device couple keeps +69.8 mV at the [Os(bpy)₃] value and turns uphill past −319.8 mV; the alternative 4.44 V convention (−159 mV) turns none, with spin–orbit coupling 10 and 12 (§3.5). At ωB97X/def2-TZVP on both sides — the device form only, the one osmium form computed at that tier, against the flavin re-read at it on 32b's geometries (script 112) — the device cascade is −136.7 mV on the relaxed electronic flavin level (uphill) and +174.0 / +163.5 mV with the flavin's zero-point / RRHO terms (one-sided; single points — the osmium programmatic, vertical and LANL2DZ, the flavin's geometry and thermal terms B3LYP; at the [Os(bpy)₃] spin–orbit size the zero-point / RRHO cells read −76.0 / −86.5 mV; §3.5). Agreements by cancellation, not validations — thresholds ours (|gap| ≤ 50 mV while each side is ≥ 100 mV off): chloro (device, programmatic) at relaxed + ZPE (−0.3 mV = donor −209.5 + acceptor +209.2); chloro (device, programmatic) at relaxed + RRHO free energy (+10.2 mV = donor −199.0 + acceptor +209.2); chloro, both states relaxed (adiabatic) at relaxed + ZPE (−26.8 mV = donor −209.5 + acceptor +182.7); chloro, both states relaxed (adiabatic) at relaxed + RRHO free energy (−16.3 mV = donor −199.0 + acceptor +182.7).*

## Table 2b. One-electron readings of the same step — not like-for-like with the 2e⁻/2H⁺ driving force

| Reading (ωB97X/def2-TZVP, the device dimethyl mediator) | ΔE/e⁻ (eV), > 0 = uphill |
|---|---|
| ΔSCF, vertical | +0.387 |
| ΔSCF, adiabatic (FAD side relaxed; Os vertical) | +0.048 |
| Proton-coupled route FADH₂ → FADH• + H⁺ + e⁻ (proton reference, 1 M H⁺ — pH 0; B3LYP/6-31G(d) geometries) | +0.610 |
| the same route at pH 7 (Nernst term, −0.414 eV) | +0.196 |
| the same route at pH 7 with the flavin zero-point energies (B3LYP harmonic, −0.320 eV) ⁴ | −0.125 |

*Electronic energy differences per electron transferred (the proton-coupled route adds the proton reference). The ωB97X Koopmans offset, Δε = ε_HOMO(FADH₂) − ε_LUMO(Os(III)) = −4.826 eV in Table 4's sign (> 0 = downhill), is a range-separation artefact and is not used. FADH₂ = the 1,5-dihydro tautomer; the flavin geometries are minima by their Hessians, the osmium side vertical on its programmatic geometry. These are one-electron quantities set against no two-electron value here, and no conclusion is drawn from their sign; the B3LYP orbital offset is in Table 4 (Me row). ⁴ Mixed tiers — ωB97X/def2-TZVP electronic energies with the B3LYP/6-31G(d) zero-point energies of the two flavin states (script 33's Hessians); the osmium side carries no thermochemistry here.*

## Table 3. Cathode DET hops, couplings and reorganisation energies

| Hop | t_ij used (eV) | crude ΔSCF t_ij (eV) | crude ΔE ÷ SCF tolerance | λ_hop lit (eV) | λ_hop computed (eV) |
|---|---|---|---|---|---|
| **Cu–Co** (T1↔node, bottleneck) | **0.00546** (FO-DFT) | 0.00128 | 9.4 | 1.70–1.90 | 2.55–2.75 |
| Co–Ce (node↔vacancy) | 0.00687 (crude) | 0.00687 | 50 | 1.20 | 1.98 |
| Ce–graphene (vacancy↔MWCNT, multi-walled carbon nanotube) | 0.11294 (crude) | 0.11294 | 830 | — | — |

**Cu–Co bottleneck margin vs enzymatic turnover (10³ s⁻¹), by λ scenario, on the FO-DFT coupling** — each a bracket over the sign of the computed site-energy gap and the λ(Cu) reading; the consumer reading is the ADVERSE corner:

| λ scenario | adverse corner | ΔG = 0 (default, not a measurement) | favourable corner |
|---|---|---|---|
| **literature λ** (Cu 2.0–2.4 / Co 1.4, assumed / Ce 1.0) | **×0.081** | ×25 | ×7.3e+02 |
| **computed λ** (B3LYP: Co 3.09; Cu literature) | **×1.9e-05** | ×0.0054 | ×0.17 |
| Ru-swap (Co→Ru, computed λ 0.78) — *indicative: λ(Ru) sums Nelsen halves -0.26 and +1.04 eV; the Cu–Ru coupling and gap are not obtainable from the minimal cluster, so it borrows the Cu–Co coupling and every column is ΔG = 0* | ×76 | ×5.7e+02 | ×5.7e+02 |

*Inner-sphere λ via Nelsen 4-point (35) on [Co(NH₃)₆] for Co and on [M(H₂O)₆] for Ce and Ru; λ(Cu) is a literature bracket of two solution readings — 2.0 eV (textbook value, source not found) and 2.4 eV (Cu(phen)₂²⁺/⁺ self-exchange, Gray & Winkler) — a Cu(I) d¹⁰ hexa-aqua optimisation being unphysical, so λ_hop(Cu–Co) is half computed and half cited. Both readings are unconstrained solution couples; a framework-held Cu–N₄ site can lie below both (0.7 eV in azurin, same source), so the favourable corner is no floor. The adverse corner is the uphill gap sign at the higher λ(Cu). The crude ΔSCF couplings are half the energy difference of two unconstrained SCF solutions from one start; for Cu–Co that difference is a single-digit multiple of the SCF tolerance, so the margins use the two-state diabatisation (FO-DFT label, Methods §2.5). The verdict is conditional on λ(Co): turnover needs λ(Co) ≲ 2.0 eV at ΔG = 0 on the 2.0 eV λ(Cu) reading and ≲ 0.9 eV at the adverse corner; the computed 3.09 eV puts the cathode below turnover at every corner, the assumed 1.4 eV (no primary) across it.*

## Table 4. Osmium mediator series — ΔE_red and the Koopmans offset vs Hammett σ (①)

cis-[Os(4,4′-X-bpy)₂(1-MeIm)Cl]⁺/²⁺ at constant charge; B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF; last column — the same ΔSCF at ωB97X/def2-TZVP on the same geometry, minus the B3LYP value.

| 4,4′-X | σ_para | ΔE_red(III→II) (eV) | Os(III) LUMO (eV) | Koopmans offset Δε (eV) | note | ω−B3 (eV) |
|---|---|---|---|---|---|---|
| NMe₂ | -0.83 | -3.910 | -3.636 | -0.3823 | donor saturation | +0.055 |
| NH₂ | -0.66 | -3.905 | -3.637 | -0.3807 |  | +0.055 |
| OMe | -0.27 | -4.286 | -4.002 | -0.0165 |  | — |
| Me | -0.17 | -4.381 | -4.086 | +0.0676 |  | +0.138 |
| H | +0.00 | -4.530 | -4.228 | +0.2097 | reference | +0.137 |
| Cl | +0.23 | -4.697 | -4.385 | +0.3674 |  | — |
| COOH | +0.45 | -4.936 | -4.595 | +0.5766 |  | — |
| CF₃ | +0.54 | -4.957 | -4.635 | +0.6167 | assumed inert (not tested) | — |
| NO₂ | +0.78 | -5.262 | -4.905 | +0.8871 | unstable on cycling | +0.263 |
| SO₂CF₃ | +0.96 | -5.256 | -4.910 | +0.8921 | assumed inert (not tested); order vs NO₂ open | +0.184 |

*Koopmans trend: the Koopmans offset rises with σ (−0.38 NMe₂ → +0.89 SO₂CF₃); the order of NO₂→SO₂CF₃ (+5.0 meV) is not decided — relaxing NO₂ alone moves NO₂'s own Koopmans offset by −198 meV with Os(III) on its own minimum and +102 meV with Os(III) vertical, and SO₂CF₃ was not relaxed; ΔE_red LFER slope ≈ −0.92 eV/σ over OMe→NO₂ (Fig 2). Higher E°(Os) lowers OCV, so the cell optimum (~+309 mV) balances driving force vs overpotential. ωB97X/def2-TZVP cross-check: over Me, H, NO₂ the slope is −0.79 against −0.93 eV/σ at B3LYP (×0.85, resting on the one acceptor point of that set, NO₂; outside the fit, SO₂CF₃ carries ω−B3 +0.184); at Me/H, where ωB97X also exists with 6-31G(d), the local slope runs −0.876 → −0.800 → −0.878 eV/σ, i.e. the functional and the basis change pull opposite ways; with ωB97X also at 6-31G(d) on every point of Me, H, NO₂, the slope runs −0.931 → −0.789 → −0.791 eV/σ — functional ×0.85, basis ×1.00.*

