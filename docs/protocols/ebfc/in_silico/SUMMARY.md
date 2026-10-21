# In Silico Pipeline Summary — EBFC Gen 2.0 Zero-Lab Proof

> **Date:** 2026-05-28 | **TRL Gate 3→4:** ✅ PASSED (2026-05-25)
> **Purpose:** Computational proof that EBFC Gen 2.0 is thermodynamically viable, mechanically stable, and kinetically functional — BEFORE ordering any Ti-coin prototypes.
>
> 🟢 **CANONICAL SOURCE (SSOT).** This file + [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md) are the **single source of truth** for in-silico results (this = results, PIPELINE_STATUS = per-script/operational status). All other docs (01_03, 00_02, 00_01, READMEs) must **link here, not duplicate numbers**. When a result changes, update here + PIPELINE_STATUS only. Volatile counts (script/test totals) live in PIPELINE_STATUS exclusively.

---

## Executive Summary

The 4-level Zero-Lab pipeline validates the Gen 2.0 EBFC design entirely in silico:

| Level | Question | Method | Verdict |
|-------|----------|--------|---------|
| **L1** | Does deglycosylated FAD-GDH fold correctly? | AlphaFold 3 | ✅ d_FAD = 15.998 Å burial depth — below the ≈20 Å single-step ceiling (a lower bound on the D–A separation; the flavin→mediator coupling is not computed — §Electron Tunneling Route) |
| **L2** | Does the full matrix denature the protein? | OpenMM MD (481k atoms) | ✅ RMSD 1.22 Å (100ps), Rg stable at 10ns |
| **L3** | Does electron cascade FAD→Os flow downhill? | PySCF DFT (66 atoms, dimethyl) | ✅ Downhill (verified +574 mV); raw DFT on the 1,5-dihydro donor gives one-electron readings of both directions — downhill: the B3LYP-Koopmans offset (Δε +0.07 eV on the programmatic geometry, ≈ 0 on Os(III)'s own minimum); uphill: the adiabatic ΔSCF (ΔG +0.05 eV), the vertical ΔSCF (ΔG +0.39) and PCET (ΔG +0.61 eV) — none like-for-like with the verified 2e⁻/2H⁺ cascade, and no conclusion is drawn from their sign; **like for like (`95`) the cascade is downhill in every Os form at every donor level (smallest +218.5 mV) within the protocol (spin–orbit coupling on Os reverses the device couple on one flavin level at ref 63's [Os(bpy)₃] size), its magnitude method-dependent** |
| **L3b** | Is DET through ZIF nanozyme fast enough? | PySCF two-state diabatisation + Marcus | 🔴 **conditional on λ(Co)** (FO-DFT coupling; bracket over the gap sign × the λ(Cu) reading): rate-limiting at the computed λ(Co) 3.09 eV (×1.9×10⁻⁵…×0.17), straddles turnover only at the assumed literature 1.4 eV (×0.081…×730) — NOT the old ×10⁵ (see §Cathode) |
| **L4** | Does BASELINE_DELTA_T_S = 60s make physical sense? | Analytical MM+Arrhenius | 🟡 **No — and the old ✅ was a model artifact:** healthy 135.2 s / stressed 732.7 s even at the pH-7.4 lab ceiling on the 2 cm² coupon, on the node chain without inference since the piezo cut (2026-09-29). The former 19.9 / 100.7 s rested on a 5 mJ cycle-cost placeholder with no sleep term, 8.5× below the chain as it then stood (E.63, 2026-09-27); the recharge-kinetics model itself stands (§L4) |

**Bottom line:** the design is ready for physical prototyping (Ti-coin Stage 2) — but not because every check passes: L3b and L4 carry the named caveats in the table above, and the coin is where both get measured.

---

## L1 — Protein Architecture (AlphaFold 3)

**Input:** FAD-GDH from *Glomerella cingulata* (UniProt G8E4B5, 600 aa)
**Deglycosylation:** 11 N-X-S/T sites removed (N→Q point mutation) via `deglycosylate.rb`
**Folding:** AlphaFold 3 Server with native FAD cofactor

| Metric | Value |
|--------|-------|
| ipTM (protein↔FAD interface) | 0.99 |
| pTM (global fold confidence) | 0.93 |
| **FAD N5 → surface (Tyr90 OH)** | **15.998 Å** |
| Single-step tunnelling ceiling through protein, centre-to-centre (Gray & Winkler 2005, PMC553296) | ≈20 Å |

**Conclusion:** d_FAD is a burial depth — a lower bound on the donor–acceptor separation, below the ≈20 Å single-step ceiling — so the distance does not exclude MET and does not prove it; the flavin→mediator coupling that would carry the MET argument is not computed — script 28 is a contact-graph search, not a pathway analysis (§Electron Tunneling Route).

---

## L2 — Molecular Dynamics Stability

### Baseline (genipin only)
| Parameter | Value |
|-----------|-------|
| System | dgrGcGDH + FAD + 10×genipin in TIP3P-FB/NaCl |
| Atoms | 473,607 |
| **Backbone RMSD** | **1.197 ± 0.308 Å (max 1.575)** ✅ (correct C₁₁ genipin, rerun 2026-05-26) |
| Speed | 8.39 ns/day (Apple OpenCL) |

### Extended (full Gen 2.0 matrix)
| Parameter | Value |
|-----------|-------|
| System | + 5×chitosan trimer + 8×cellobiose (CNC proxy) |
| Atoms | 481,804 |
| Matrix atoms | 1005 (300 GEN + 345 CSO + 360 CLB) |
| **Backbone RMSD** | **1.215 ± 0.327 Å (max 1.665)** ✅ (correct C₁₁ genipin, rerun 2026-05-27) |
| Speed | 7.72 ns/day |

### Extended 10 ns (long-timescale validation)
| Parameter | Value |
|-----------|-------|
| System | same as extended (FAD + 10×GEN + 5×CSO + 8×CLB) |
| Atoms | 474,849 |
| Production | 10 ns @ 298 K, 1 atm |
| Speed | 8.94 ns/day (Apple OpenCL) |
| **Backbone RMSD (all)** | **4.022 ± 0.819 Å (max 5.395)** |
| **Core RMSD (res 50-500)** | **4.640 ± 0.168 Å (last 2 ns)** |
| **Radius of gyration** | **84.46 → 84.38 Å (-0.1%)** — stable |
| Energy drift | 0.044% — fully converged |

**Interpretation:** RMSD > 3 Å but Rg is rock-stable (-0.1%) — the protein is NOT denaturing. This is **conformational relaxation** from the AF3-predicted structure to the MD force-field equilibrium. AF3 structures typically show 3-5 Å RMSD drift under AMBER ff14SB for large enzymes (600 aa). The protein maintains its global fold (constant Rg) while internal loops rearrange. RMSD has not yet plateaued at 10 ns — full equilibration of a 600-residue enzyme requires 20-50 ns.

**Conclusion:** Protein fold INTACT (Rg stable). The 3 Å threshold from the 100 ps run was too optimistic for the timescale — longer runs reveal normal conformational dynamics. Matrix is mechanically compatible.

> **Note:** Genipin SMILES corrected (C₁₀→C₁₁, 2026-05-25). Scripts 10+11 rerun ✅ (RMSD 1.20 / 1.22 Å).

### Temperature Sweep (script 12)
| Temperature | RMSD (Å) | Verdict |
|-------------|----------|---------|
| 263 K (-10°C) | 0.76 (max 0.95) | ✅ STABLE |
| 278 K (5°C) | 0.87 (max 1.13) | ✅ STABLE |
| 298 K (25°C) | 0.90 (max 1.11) | ✅ STABLE |
| 313 K (40°C) | 1.47 (max 2.23) | ✅ STABLE |

**Conclusion:** Protein stable across the full -10°C to +40°C range (covers all temperate/boreal forests + extreme summer heat). RMSD rises with temperature as expected (more thermal motion); even 313K stays well below the 3 Å denaturation threshold. The earlier 313K NaN (ligand-placement clash) was fixed with 10k-step minimization + 1000-step low-T pre-relaxation. **4/4 STABLE.**

### PSBMA Glucose Diffusion (script 13)
| Parameter | Value |
|-----------|-------|
| D_eff (simulated) | 5.1×10⁻⁴ cm²/s |
| D_eff (literature, chitosan gel) | ~2×10⁻⁶ cm²/s |
| Ratio | 255× (expected — monomers, not polymerized chains) |

**Note:** SBMA monomers don't form dense membrane in 200 ps MD. L4 kinetics correctly uses literature D_eff.

### Xylem Sap Cross-Species Stability (script 14)

| Species | pH | RMSD (Å) | Verdict |
|---------|-----|----------|---------|
| Pinus sylvestris (summer) | 5.0 | 1.026 ± 0.244 (max 1.316) | ✅ STABLE |
| Pinus sylvestris (winter) | 4.5 | 1.030 ± 0.260 (max 1.340) | ✅ STABLE |
| Picea abies (spruce) | 4.2 | 1.090 ± 0.269 (max 1.420) | ✅ STABLE |
| Quercus robur (oak) | 5.5 | 1.045 ± 0.288 (max 1.428) | ✅ STABLE |
| Fagus sylvatica (beech) | 6.0 | 0.984 ± 0.244 (max 1.322) | ✅ STABLE |
| Generic simplified | 4.5 | 1.052 ± 0.268 (max 1.426) | ✅ STABLE |

**Conclusion:** dgrGcGDH + Gen 2.0 matrix stable across the tested pH window 4.2–6.0. Lowest RMSD at pH 6.0 — less acidic = gentler; highest at pH 4.2, still well within threshold. ⛔ **What this validates is pH tolerance inside 4.2–6.0, not cross-species deployment** (the line that stood here said the latter). The species names label PROFILES, and every profile pH is an assumption (`lib/xylem_sap.py`; no *P. sylvestris* measurement exists in the tree, 00_07 HW.3); script 14 also builds the box from pH and ionic strength alone, with Na⁺/Cl⁻. Measured conifer sap sits largely ABOVE this window — *Picea abies* 5.4 in spring and 6.9 in winter, *Pinus cembra* 6.1 / 6.8 (Pramsohler 2022, doi:10.3390/plants11152058) — and the seasonal direction the two pine rows encode (winter 4.5 below summer) is the reverse of what was measured, so the winter end of real sap was never simulated.

### Parameterized Ligands

| Ligand | Script | Atoms | GAFF Cache |
|--------|--------|-------|------------|
| FAD (from AF3 pose) | 02 | 86 | ✅ |
| Genipin (PubChem 442424) | 03 | 30 | ✅ |
| Chitosan trimer (3×GlcN) | 04 | 69 | ✅ |
| Cellobiose (CNC proxy) | 05 | 45 | ✅ |
| Polypyrrole pentamer (α,α') | 06 | 42 | ✅ |
| Poly(1-vinylimidazole) trimer | 07 | 44 | ✅ |
| SBMA monomer (zwitterionic) | 08 | 39 | ✅ |

---

## L3 — Quantum Chemistry (DFT)

### Anode: FAD → Os Cascade

**Method:** B3LYP/6-31G(d) + LANL2DZ(Os) + C-PCM water. **Mediator = the real 4,4'-dimethyl-bpy** (Zafar +309 mV; OS-RECOMPUTE 2026-06-17); plain-bpy retained as the parent π-backbonding reference. **Donor = the 1,5-dihydro FADH₂** (recomputed 2026-10-15, `00_07` HW.5.IS; in-silico §Critical Rules #16).

| Species | HOMO (eV) | LUMO (eV) | Gap (eV) |
|---------|-----------|-----------|----------|
| FAD (oxidized) | -6.188 | -2.779 | 3.409 |
| **FADH₂ (reduced) — donor** | **-4.018** | -0.626 | 3.392 |
| Os(II) [Os(dmbpy)₂(1-MeIm)Cl]⁺ | -4.724 | -2.023 | 2.702 |
| **Os(III) [Os(dmbpy)₂(1-MeIm)Cl]²⁺ — acceptor** | -6.209 | **-4.086** | 2.124 |

**Marcus Cascade Verdict:**

| Quantity | Value |
|----------|-------|
| ε_HOMO(FADH₂) | -4.018 eV |
| ε_LUMO(Os(III)) dmbpy | -4.086 eV |
| Raw Δε (dimethyl) | +0.068 eV (downhill on the programmatic geometry, −0.003 on Os(III)'s own minimum; 0.142 eV less favourable than plain bpy via the 4,4'-substituent ①) |
| **Verified driving force** | **+574 mV / −0.574 eV (downhill)** |
| ↳ E°(Os +309 vs NHE, Zafar 2012) − E°(FAD-GDH −265 mV SHE, Schachinger 2023) | verified E°s |
| Like-for-like cascade (`95`) | downhill in every Os form at every donor level (smallest +218.5 mV) within the protocol (spin–orbit coupling on Os reverses the device couple on one flavin level at ref 63's [Os(bpy)₃] size); magnitude method-dependent, the gap attributed to no side — the block «Like-for-like cascade» below; the former «gap = chloro↔bis-Im bracket + substituent +0.142 ①» decomposition is withdrawn |

⊕ **Revised 2026-10-19 (the like-for-like revision, `00_07` HW.5.IS):** the Conclusion below, the table row above and the paragraphs that follow now read like for like; what stood on the superseded 4a,5-dihydro numbers and on one-electron readings set against the 2e⁻/2H⁺ value — «raw DFT verdict UPHILL», «the ~1 eV gap» and its attribution — is withdrawn, marked where it stood.

**Conclusion:** The cascade is **experimentally downhill** (+574 mV, verified E°s — Os +309 vs NHE / FAD-GDH −265 mV SHE) and **downhill like for like in every computed Os form at every donor level** (the block «Like-for-like cascade» below; smallest +218 mV) — within one protocol: every cell shares B3LYP, C-PCM, |SHE_abs| = 4.281 V and a scalar-relativistic Os, which the cells cannot test. The one omitted term of known sign, spin–orbit coupling on Os (≈ −300 mV at its octahedral value — Srnec et al. 2008 and Rulíšek 2013, paper refs 63 · 19; not computed, and quenched by a lower symmetry), reverses a cell beyond **+218.5** mV; at the size ref 63 computes for [Os(bpy)₃] itself (**−250** mV, its SI Table S2 — the reading taken, ⚖️ founder 2026-10-20) it turns **2** of the 32 uphill, the device form among them, and at the full octahedral value up to **5** — the device form on both electronic donor levels among them, levels that lie 65 and 101 mV above the measured flavin; against the measured free flavin the shifted device couple lies at **+69.8** ⊥ **+19.8** mV, so at either value the protocol does not determine the device sign (a shift quenched below +218.5 mV would need the device complex's hole on a single orbital split by ≥ 0.40 eV, beyond every analogue found — `94`). Two alternative choices lower E°(Os) relative to ours without being errors of known sign — the 4.44 V convention (−159 mV; alone no cell, with the spin–orbit shift **10** ⊥ **12** at the [Os(bpy)₃] ⊥ octahedral size) and ωB97X on the device couple's Os side (138 mV) — and the terms that raise it (the Os ZPE, the waters on Cl⁻, the protein shift) are not netted (`95` `shared_shifts`). The direction rests on the protocol, which does not establish it. How far the computed cascade lies from the measured one, and on which side, is **method-dependent** (donor side +65 → −210 mV over the flavin levels, acceptor side +209 … −324 mV over the Os forms) and is attributed to no side; near-exact agreements are cancellations, named by `95` (⚖️ founder 2026-10-16, «напрямок + таблиця»). The former «raw DFT verdict UPHILL is a method limit, decomposed by ② into a chloro↔bis-Im bracket + the 4,4'-dimethyl substituent» stood on 4a,5-dihydro one-electron readings and is **withdrawn** (self-review round 1, clusters 2–3). The earlier «bias-corrected Δε ≈ −0.07 eV reproduces exp −0.14» was fortuitous cancellation tuned to a mis-valued (+60 mV) FAD potential — **withdrawn**; Cosnier 1999's +140 mV pertains to glucose-oxidase, not GcGDH.

**PCET potential (script 32 — thermodynamic proton reference):** E°(FAD/FADH₂) = **−155 mV vs NHE** (pH 7; −7.5 mV pH 4.5, +259 mV pH 0) lands **65 mV** from the free-flavin experimental value (−220 mV, the paper's ref 25; the unsourced −208 end of the former bracket was dropped ⚖️ founder 2026-10-02) at the MMFF electronic level — a proximity that does not survive relaxed geometries and the ZPE (`32b`, the block below: −430 mV, ≈ 200 mV beyond), so the flavin is not exonerated: both sides carry errors of the same order. (Cache `dft/pcet_redox_potential.json`; script 33's PCET route is a one-electron reading, not like-for-like.) ⊕ 2026-10-19: this paragraph was headed «PCET validation» and read «the flavin couple itself is NOT the culprit» — both withdrawn.

**Like-for-like cascade (scripts `32b` + `95`, 2026-10-16) — the cascade verdict's data (⚖️ founder 2026-10-16 «напрямок + таблиця»; paper §3.5, Table 2, Fig 5).** Both halves at one tier (B3LYP/6-31G(d)+C-PCM, LANL2DZ on Os), on one SHE scale (32's Isse–Gennaro convention), 2e⁻/2H⁺ flavin against each one-electron Os couple. The flavin at pH 7, one knob at a time (`32b`): **−155.4** mV on the MMFF geometries (32's protocol — the control) · **−118.7** mV relaxed · **−429.5** mV + ZPE · **−419.0** mV + RRHO free energy, against −220 mV measured. The zero-point energy is the term the electronic levels omit while pairing the flavin with a proton FREE energy (the reduced state carries two more N–H bonds; ΔZPE +0.62 eV for the two-electron couple moves E° by −311 mV) — so the 65 mV of the paragraph above does not survive it: the corrected level lies ~200 mV more negative, and that overshoot is not attributed (lumiflavin for FAD, basis, functional, protonation at pH 7, harmonic soft modes, the SHE convention and the missing explicit water are candidates; paper §3.2). Relaxed FADH₂ is the butterfly minimum (0 imaginary modes); the planar RDKit/MMFF start converged first to the planar saddle (255i · 66i cm⁻¹) **117.5** meV above it, and the step-2 flavin chain (`21g` · `33` · `29b`) optimised from that same planar start until its re-run from the minimum (2026-10-18/19): FADH₂'s saddle lay 65.4 meV above its own minimum on `21g`'s def2-SVP and 117.6 meV on `33`'s 6-31G(d), every other species of the chain was a minimum already (`PIPELINE_STATUS`, banner 2026-10-19).

| Os form (B3LYP/C-PCM, `95`) | E°(Os) vs SHE, mV | acceptor side, mV | cascade, MMFF el. (`32`) | relaxed el. | + ZPE ¹ | + RRHO ¹ |
|---|---|---|---|---|---|---|
| chloro (device, programmatic) | +99.8 | +209.2 | +255.2 | +218.5 | +529.3 | +518.8 |
| chloro + 1 H₂O on Cl⁻ | +163.2 | +145.8 | +318.6 | +281.9 | +592.7 | +582.2 |
| chloro + 2 H₂O on Cl⁻ | +235.4 | +73.6 | +390.8 | +354.1 | +664.9 | +654.4 |
| chloro + 3 H₂O on Cl⁻ | +302.0 | +7.0 | +457.4 | +420.7 | +731.5 | +721.0 |
| chloro, Os(II) relaxed, Os(III) vertical | +212.4 | +96.6 | +367.8 | +331.1 | +641.9 | +631.4 |
| chloro, both states relaxed (adiabatic) | +126.3 | +182.7 | +281.7 | +245.0 | +555.8 | +545.3 |
| aqua (methodological reference) | +539.1 | −230.1 | +694.5 | +657.8 | +968.6 | +958.1 |
| bis-imidazole (operando form) | +632.6 | −323.6 | +788.0 | +751.3 | +1062.1 | +1051.6 |

Measured, free flavin against the film-bound mediator: **+529** mV (Os +309 vs NHE − free FAD −220 at pH 7; the Os measured as a PVI film at pH 7.4, whose preparation moves it by 135 mV — not the free molecule the computation models); the device's +574 mV adds the protein shift of the bound cofactor (−45 mV, measured, not computed). ¹ One-sided — every cell of these two columns, the adiabatic chloro row included: the Os side carries no thermochemistry here. Script `96` (2026-10-18) gives that one form's Os couple its own — analytic C-PCM Hessians of both relaxed states; the ZPE moves E°(Os) by **+40.6** mV — so with both sides relaxed its cascade is the table's **+245.0** mV on the electronic level (no thermochemistry on either side there) and **+596.3** mV with the ZPE on both sides, against +555.8 one-sided (`95`'s `both_sided` row). That is **67** mV over the measured +529 — not a near-match but the remainder of two large opposite errors, the acceptor side +142 and the donor side −210 mV. Its RRHO level is not comparable: the two Os states' soft-mode censuses differ — Os(III) drops two imaginary modes, both methyl torsions by the ⚖️ delegated rule of 2026-10-16 (22.8i and 14.2i cm⁻¹, methyl shares 0.999 and 0.998; `96` books the second as a tolerated soft mode because it lies under 20 cm⁻¹ — either way it leaves the ZPE and G), Os(II) none — so the both-sided row stops at the ZPE. That correction moves one form; `95` does not carry its increment to the others. **Every form is downhill at every donor level** within the protocol — spin–orbit coupling on Os reverses the device couple on one flavin level at the literature size for homoleptic [Os(bpy)₃], Conclusion above — (smallest: **+218.5** mV, the device form on the relaxed electronic level). ⚠️ **Agreement by cancellation, named by `95` itself (`cancellations`: |gap| ≤ 50 mV while each side is ≥ 100 mV off):** the device cascade at + ZPE lands **0.3** mV from the measured +529 only because a −210 mV donor error and a +209 mV acceptor error annihilate — likewise at + RRHO (+10 mV) and the adiabatic chloro form at both levels (−27 · −16 mV, one-sided — with the ZPE on both sides that form lands −67 mV off, footnote ¹). None of the four is a validation. (Caches `dft/pcet_redox_potential_thermo.json` · `dft/cascade_like_for_like.json`.)

**Geometry sensitivity — C-min (script 76, 2026-10-02):** the Os geometry is programmatic, not optimised, and its rigid chelate does not reach the assumed targets (paper §2.3). Closing both chelates of the device complex onto 2.060 Å / 78.0° moves its vertical ΔE_red(III→II) by **−0.026 eV** (Os(II) −0.069 · Os(III) −0.044 eV), computed under the conda-lock against the lock re-run of the same couple — below the 0.1 eV that would have re-run the aqua and bis-Im forms, and far inside the protocol dependence of the like-for-like cascade (hundreds of mV, the block «Like-for-like cascade» above). Record `cache/reproduction/os_chelate_sensitivity.json`; conditions and verdict — [`paper/09_references.md`](paper/09_references.md), the §2.3 line.

### Publication-grade: ωB97X/def2-TZVP (dimethyl mediator, B1 ✅ 2026-06-17)

| Species (dimethyl bpy) | HOMO (eV) | LUMO (eV) | Gap (eV) |
|---------|-----------|-----------|----------|
| Os(II) | -6.961 | -0.311 | 6.650 |
| **Os(III)** | -8.734 | **-1.644** | 7.090 |
| **FADH₂** | **-6.470** | 1.204 | 7.674 |

**All methods comparison** (dimethyl mediator; EA_Os3 = **4.243 eV** from B1, +0.149 lower than plain via the donor substituent; FAD IP from the B2 generator):

| Method | ΔG/e⁻ (eV) | vs verified −0.574 |
|--------|-----------|---------|
| Koopmans ωB97X | +4.83 | RSH artifact (never use) |
| ΔSCF ωB97X (vertical) | +0.387 | +0.96 |
| **ΔSCF ωB97X (adiabatic)** | **+0.048** | **+0.62** |
| B3LYP corrected (−0.07) | −0.07 | withdrawn (tuned to wrong −0.14) |
| **Experiment (verified E°s)** | **−0.574** | ref (Os +309 − FAD −265) |

> **B2 ✅** (`21g` — reproducible, closes the orphan cache; on the 1,5-dihydro donor since 2026-10-15): adiabatic **+0.0482** = IP_adiab(FAD 4.291) − EA_Os3(dmbpy 4.243); 0.149 eV less favourable than plain (−0.101 — derived from the same IP and 21d's EA, since `21g --plain` writes into this same path and the plain number has no cache of its own) = the substituent term ①, exactly the B5/B3 shift. The vertical +0.387 (IP_vert 4.630; cation relaxation −0.339 eV) is cation-relaxation-sensitive. Neither is a headline: both are one-electron readings, not like-for-like, and no conclusion is drawn from their sign (⚖️ founder 2026-10-19, D) — the cascade verdict is the block «Like-for-like cascade». The 4a,5-dihydro values these rows carried (+1.0335 · +1.40 · plain +0.884) live in git only — the cache's `superseded_4a5_dihydro` block holds the hand-added orphan pair (IP 5.391, dG 0.998), not these. ⊕ (2026-10-19) on the butterfly minimum — `21g` re-run through lib `relax_checked` (⚖️ founder 2026-10-16 — its text in `PIPELINE_STATUS`, banner 2026-10-19): the planar start had converged first to a saddle (95i · 28i cm⁻¹) **65.4** meV above the minimum on B3LYP/def2-SVP, the cation to a minimum; on the minimum IP_adiab rose 4.164 → 4.291 eV and the adiabatic ΔG crossed zero, −0.079 → +0.048 eV (uphill), the vertical +0.095 → +0.387 eV.

*vs the verified −0.574 eV (E°(Os +309 vs NHE) − E°(FAD-GDH −265 mV SHE); the old −0.14 was a +60 mV FAD artifact). The «vs verified» column sets one-electron readings against a 2e⁻/2H⁺ value — not like-for-like, kept as the record; the former «residual gap = solvation bracket + substituent» decomposition is withdrawn (Conclusion above).

### Mediator Structure–Property Series (① — script 21e, 2026-06-05)

10× cis-[Os(4,4'-X-bpy)₂(1-MeIm)Cl]⁺/²⁺ at **constant charge**, B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF — isolates the 4,4'-substituent electronic effect. The H (bpy) point reproduces script 21b (Δ=0.000 eV). cascade Δ = ε_HOMO(FADH₂, −4.018) − ε_LUMO(Os III).

| 4,4'-X | σ_para | ΔE_red(III→II) eV | Os(III) LUMO eV | cascade Δ eV |
|---|---|---|---|---|
| NMe₂ | −0.83 | −3.910 | −3.636 | −0.382 |
| NH₂ | −0.66 | −3.905 | −3.637 | −0.381 |
| OMe | −0.27 | −4.286 | −4.002 | −0.016 |
| Me | −0.17 | −4.381 | −4.086 | +0.068 |
| H | 0.00 | −4.530 | −4.228 | +0.210 |
| Cl | +0.23 | −4.697 | −4.385 | +0.367 |
| COOH | +0.45 | −4.936 | −4.595 | +0.577 |
| **CF₃** (inert) | +0.54 | −4.957 | −4.635 | +0.617 |
| NO₂ (unstable) | +0.78 | −5.262 | −4.905 | +0.887 |
| **SO₂CF₃** (inert) | +0.96 | −5.256 | −4.910 | **+0.892** |

**Design rule (✅ cascade monotonic with σ on the programmatic geometry; with relaxation the NO₂→SO₂CF₃ step is not decided):** electron-withdrawing 4,4'-bpy improves FADH₂→Os alignment — cascade Δ rises −0.38 (NMe₂) → +0.89 eV. **SO₂CF₃ — the strongest inert candidate, not a computed optimum** (σ 0.96, cascade +0.892 ≈ NO₂'s +0.887 on the programmatic geometry; with NO₂ relaxed the order is not decided and SO₂CF₃ is not relaxed — ⚖️ founder 2026-10-15, limit (3)) — same alignment there but **electrochemically inert**, whereas NO₂ degrades (NO₂→NHOH→NH₂ on Os cycling at pH 4.5) → would relax the cascade to the donor-saturated −0.38 worst case (CHEM.23). CF₃ (+0.617) = milder inert option. *Caveat:* max cascade-Δ ≠ optimal EBFC mediator — higher E°(Os) lowers OCV → optimum balances driving-force vs cell-voltage (exp Os opt ~+309 mV).

**E° LFER:** ΔE_red linear in σ over OMe→NO₂ (B3LYP slope ≈ −0.92 eV/σ, r²=1.00; the ωB97X reading ↓) with **donor-saturation at NMe₂/NH₂** (plateau ~−3.91 eV, σ_para⁻ regime) — strict E°-monotonicity breaks at two pairs: that 4-meV donor pair (expected resonance saturation, not error) and, at B3LYP, the NO₂/SO₂CF₃ acceptor pair (6 meV, which ωB97X puts back in σ order ↓).

🔬 **Functional sensitivity of the LFER — ωB97X on BOTH ends of the σ-axis and on its centre** (`00_07` HW.5.IS). The centre pair was bounded 2026-09-22 from caches already on disk; the ends were computed by `21e … wb97x` one point per night (NH₂ 2026-10-03 · NO₂ 2026-10-05 · NMe₂ 2026-10-08 · SO₂CF₃ 2026-10-10), NH₂ and NO₂ also with the small basis (`21e … wb97x-631gd`, 2026-10-09/11). Every number below is the `vs_b3lyp` block of `dft/os_mediator_series_wb97x.json`: 21e derives it at full precision from the six pairs and refuses to write it unless each pair sits on one geometry (the series point is rebuilt and compared with the xyz its B3LYP row wrote; the centre files with the series files — all within 5e-7 Å).

| 4,4'-X | σ_para | B3LYP/6-31G(d) ΔE_red | ωB97X/def2-TZVP ΔE_red | ω−B3 |
|---|---|---|---|---|
| NMe₂ | −0.83 | −3.9096 | −3.8547 | **+0.0549** |
| NH₂ | −0.66 | −3.9052 | −3.8506 | **+0.0545** |
| Me (dmbpy) | −0.17 | −4.3808 | −4.2430 (`os_complex_wb97xd_dmbpy.json`, 21f) | **+0.1378** |
| H (bpy) | 0.00 | −4.5297 | −4.3923 (`os_complex_wb97xd.json`, 21d) | **+0.1374** |
| NO₂ | +0.78 | −5.2620 | −4.9993 | **+0.2626** |
| SO₂CF₃ | +0.96 | −5.2558 | −5.0716 | **+0.1842** |

**The offset is not rigid.** It is flat within each of the two σ-near pairs, NMe₂/NH₂ and Me/H (≤ 0.5 meV), steps up between them and to NO₂, and falls back at SO₂CF₃. ωB97X keeps the donor plateau — the nme2 − nh2 gap is −4.4 meV at B3LYP ⊥ −4.0 meV at ωB97X, same sign — and the one pair that DOES reorder is the acceptor pair: SO₂CF₃'s ΔE_red is 6.2 meV less negative than NO₂'s at B3LYP (a lower E°, out of σ order) and 72.2 meV more negative at ωB97X (in σ order) (`order_swaps`, `acceptor_gap_so2cf3_minus_no2_eV`). It does not keep the MAGNITUDE: over the points of the canonical fit-set that both tiers have (Me · H · NO₂) the ωB97X slope is **−0.791 against −0.931 eV/σ at B3LYP (×0.85)**, a ratio that rests on ONE acceptor point, since Me and H sit 0.17 apart near σ ≈ −0.1 — and the second acceptor, SO₂CF₃, lies outside the fit set and carries a SMALLER offset (+0.184 against +0.263 eV), so the offset is not monotone along σ at the acceptor end and the ratio belongs to the NO₂ point, not to «the acceptor end»; the span NMe₂→NO₂ shrinks alike (−1.352 → −1.145 eV). 🔑 **So the slope is method-dependent — −0.93 against −0.79 eV/σ over the same three points — and the true slope need not lie between them.** On the acceptor side the measured series put it lower: from H to Cl in paper ref 8's own series the computed sensitivity is ×2.43 the measured (a B3LYP pair ratio, not a slope; limit 2), and Cl against OMe in a second aqueous series is ×1.35 (the source's relaxed B3LYP ×1.22); the robust content of the design rule is its DIRECTION and its donor plateau.

🔬 **At the centre the change splits — and its two parts pull opposite ways.** ωB97X with the SMALL basis exists for Me and H (the chloro form of `34b`, rebuilt with 34b's own call onto the same geometry): the functional alone moves ΔE_red by +0.134 (Me) / +0.147 eV (H) and the basis change by +0.004 / −0.010 eV, so the local slope runs **−0.876 (B3LYP) → −0.800 (ωB97X, 6-31G(d)) → −0.878 eV/σ (ωB97X, def2-TZVP)**. The centre agreement of the two published tiers is therefore a CANCELLATION of two effects of ≈ 9–10 %, not robustness: the 2026-09-22 bound read it as «the functional moves the intercept and leaves the local slope», while warning in its own limits that a Δσ = 0.17 lever «says nothing about curvature at either end». Numbers — `centre_decomposition` of the same block.

🔬 **At the ends the change splits too (2026-10-11) — and there it is the functional's.** ωB97X with the small basis on NH₂ and NO₂ (`21e … wb97x-631gd`; NO₂ Os(III) re-run from a doublet start after the first run's second-order solver had landed on a spin-contaminated state — `PIPELINE_STATUS` §Future): the functional moves ΔE_red by +0.077 (NH₂) / +0.265 eV (NO₂) and the basis by −0.022 / −0.003 eV, so over Me · H · NO₂ the slope runs **−0.931 (B3LYP) → −0.789 (ωB97X at 6-31G(d)) → −0.791 eV/σ (def2-TZVP)**: the change is the functional's (×0.85), the basis ×1.00 — at ωB97X; no B3LYP/def2-TZVP point exists, so whether the larger basis would move the B3LYP slope itself is not measured. ⚠️ That three-point slope leans on the NO₂ point's leverage, and at the centre the two parts still pull opposite ways (↑) — a statement about these points, not a rule. Numbers — `ends_decomposition` of the same block.

⚠️ **Limits, each load-bearing.** (1) **The functional/basis split exists at the centre (Me, H) and at two ends (NH₂, NO₂) only** — NMe₂, SO₂CF₃, CF₃, OMe and COOH have no small-basis ωB97X point (NH₂ has had one since 2026-10-09, NO₂ only since 2026-10-11 — until then the ×0.85 could not be attributed). (2) **Three measured series, Cl in two of them** — script `83` compares the computed shifts (`21e`; the ωB97X Me/H points from `21f`/`21d`) with (a) **paper ref 8's own series, our core with the imidazole N-donor** — Zafar 2012, *Anal. Chem.*, Table 1, [Os(X2-bpy)2(PVI)Cl]⁺ films at one loading, pH 7.4, X = OMe · Me · H · Cl: per substituent OMe−H ×0.87, Me−H ×1.34, Cl−H ×2.43; the measured sensitivity falls from donor to acceptor (pairwise 0.42 → 0.16 → 0.075 V/σ per substituent), ours much less (0.24 → 0.22 → 0.18), and the aqueous series (c) falls the same way; the same Me complex from another source at another loading sits +135 mV away — more than all four Me → H (film and preparation > the pairs compared); (b) the homoleptic MeCN series a ChemRxiv search returned (Goldschmid 2021; donors only): OMe agrees (B3LYP — no ωB97X OMe point), Me does not in either tier; and (c) an aqueous series of our own bis-bpy chloro core (Montón-Vicente 2026, *Langmuir*; X = OMe · Me · Cl, the axial N-donor pyridine instead of 1-MeIm), against a computed Cl point added to `21e` 2026-10-11: per substituent, OMe−Me ×0.59, Cl−Me ×2.18, Cl−OMe ×1.35 — the two pairs taken to Me share our Me excess, which the MeCN series shows too; the source's own B3LYP (both states optimised, ΔG) gives ×1.01, ×1.45, ×1.22, and its functional is ours, so the gap on OMe−Me is our protocol, not the functional (which point carries it this series cannot say — it has no H; in (a) it splits about evenly, OMe−H 9.1 mV short and Me−H 9.5 mV over, in (b) it lies on Me) — not the Os basis/ECP (`21e … b3lyp-osdef2`, 2026-10-11: def2-TZVP/ECP moves every point by +62…+65 meV and every pair by ≤ 0.8 mV per substituent); the ligand basis is bounded on Me−H only (ωB97X at 6-31G(d), then def2-TZVP: +3.2, then −3.3 mV per substituent — our two tiers agree there by cancellation, and no OMe point exists at def2-TZVP); nor the continuum's formulation or radii (`21e … b3lyp-iefpcm` · `b3lyp-uffcavity`, same day, each the series protocol with one knob changed: on OMe−Me, whose computed excess over the measured is +16.1 mV per substituent, IEF-PCM for C-PCM moves the pair by +0.1 mV and UFF ×1.1 radii with a sphere on every H by −1.1 mV, every pair by ≤ 0.6 / ≤ 4.7 mV; removing the continuum, `b3lyp-gas` — a bound, not a candidate — moves it by −29.0 mV: the continuum attenuates the pair, and neither variant closes a tenth of the excess; the UFF radii do move every absolute point, by −118…−137 meV — the pairs survive this change of cavity, the absolute values do not), nor the axial N-donor (`21e … b3lyp-pyaxial`, 2026-10-12: pyridine for 1-MeIm moves OMe−Me by +0.9 mV — away from the measured — and every pair by ≤ 3.6 mV per substituent), so A1′ holds for the pair; **relaxing the Os(II) geometry closes it and brings every recomputed donor pair of our own core closer to the measured** (`21e … b3lyp-relaxed-os2`, 2026-10-12: OMe, Me and H relaxed with the same protocol, Os(III) vertical on them (Cl, relaxed with the acceptors, below) — OMe−Me moves by −18.2 mV per substituent, to −41.9 against −39.8 mV measured, ×1.05 against the source's optimised ×1.01; ref 8 OMe−Me ×0.56 → ×0.99, and its two pairs against H closer by ~3 mV per substituent each, OMe−H ×0.87 → ×1.08, Me−H ×1.34 → ×1.23 (of the three donor pairs two are independent); Me falls weak against the H–OMe line as measured, r² of the three donors 0.9996 → 0.957; only the homoleptic MeCN OMe−H moves away, ×0.99 → ×1.23; the computed pairs change by −9 % (Me−H) to +77 % (OMe−Me), up to 73 meV a complex — as much as the points, whose relaxed shifts are −40 (OMe), −100 (H) and −113 meV (Me) — and the three-point donor slope rises by +21 %; the relaxed chelate comes closer to the crystal ranges of paper §2.3 — bite 77.5–78.2° against 80.5–80.6°, Os–N(bpy) 2.05–2.09 against 2.10 Å — while Os–N(L) lengthens to 2.14 Å and Os–Cl to 2.52–2.53 Å, 0.08–0.09 Å over the Os(II) range (2.40–2.44 Å) and 0.14–0.15 Å over the Os(III) one, on which Os(III) is computed vertically; `83` `relaxation_check` · `relaxed_geometry_check`) — so the programmatic geometry is load-bearing for the pairs themselves, and the relaxed one agrees better with the donor pairs of our core (its Cl pairs move away — below); **relaxing Os(III) as well** (`21e … b3lyp-relaxed-os3`, leg (3б), landed 2026-10-13: each Os(III) from its relaxed Os(II), adiabatic ΔSCF, λ_III 86 · 94 · 110 meV for Me · OMe · H) moves the two independent donor pairs toward the measured in both series that have H (against Os(III) vertical, OMe−H +4.2 and Me−H +6.1 mV per substituent) and their difference OMe−Me away in both series that measure it (−1.9 mV) — the six shared rows rest on three computed pairs, two of them independent; against the programmatic geometry Me−H and OMe−Me come closer in every series that has them and OMe−H closer to ref 8 and away from MeCN (×0.99 → ×1.16); ref 8's three then lie within 1.7 mV per substituent (OMe−H ×1.02, Me−H ×1.01, OMe−Me ×1.04), MeCN Me−H stays ×1.86, the aqueous OMe−Me ends ×1.10 (×1.05 with Os(III) vertical); r² of the three donors → 0.926, the donor slope +13 % against the programmatic; from the programmatic geometry the pairs move by up to 20.1 mV per substituent (OMe−Me, 80 meV a complex) and the points by −26…+54 meV, and on its own minimum Os(III) takes Os–Cl back to 2.42–2.43 Å, 0.04–0.05 Å over the Os(III) range (`83` `relaxed_geometry_check.adiabatic`); **relaxing Cl in both states** (`21e … b3lyp-relaxed-os2` · `b3lyp-relaxed-os3` on Cl, the acceptors run of 2026-10-14; λ_III 94 meV) **brings none of its pairs closer than the programmatic geometry did** — five rows on three computed pairs, which over the donors add one point: ref 8 Cl−H ×2.43 → ×2.81 → ×3.04, Cl−Me ×1.76 → ×1.83 → ×1.79, Cl−OMe ×1.18 → ×1.42 → ×1.42, aqueous Cl−Me ×2.18 → ×2.27 → ×2.22, Cl−OMe ×1.35 → ×1.64 → ×1.63 (programmatic → Os(II) relaxed → both relaxed); the Os(III) step alone brings Cl−Me and Cl−OMe back by 2.0 and 0.2 mV per substituent and takes Cl−H 4.0 mV further; its Os–Cl is 2.51 Å on the Os(II) minimum and 2.41 Å on Os(III)'s own, 0.07 and 0.03 Å over the two crystal ranges — the geometry carries these pairs too (Cl−OMe moves by 21.4 mV per substituent), but away from experiment and, on the aqueous pairs, away from the source's own optimised B3LYP (×1.45, ×1.22), so the acceptor excess is not an artefact of the programmatic geometry: our relaxation enlarges it, and what the source's computation has and ours lacks (ΔG among it) is untested on it (`83` `relaxed_geometry_check.acceptors`); **NO₂, relaxed the same way** (λ_III 150 meV, the largest of the five relaxed points; Os–Cl 2.49 and 2.41 Å on the two minima, 0.05 and 0.03 Å over the crystal ranges), has no measured counterpart in any of the three series, so it adds no row and the acceptor excess rests on Cl alone; left untested under A2′ are ΔG and PySCF's own discretisation of the cavity; the measured shifts are not linear in σp, so no slope is read from them; beyond Cl the acceptor side has no measured point, so the Lever/experiment triangulation withdrawn from the paper 2026-09-25 (`paper/09_references.md`, §3.3 line) stays withdrawn; the ωB97X cross-check does not restore it either — a second method is not a measurement. (3) **The acceptor end has two ωB97X points, NO₂ and SO₂CF₃, and they disagree with B3LYP on their order** (↑) — «SO₂CF₃ ≈ NO₂» is a B3LYP statement (at ωB97X SO₂CF₃'s ΔE_red is 72 meV more negative than NO₂'s) and one of the programmatic geometry — relaxing NO₂ in both states moves its own Koopmans cascade Δ by −0.198 eV (+0.102 with Os(III) vertical), 20–40 times the 5.0 meV between them, with SO₂CF₃ not relaxed (`83` `acceptors`); CF₃, OMe and COOH have no ωB97X point. (4) **Vertical ΔSCF on one programmatic geometry, chloro form only**, in the recorded PySCF 2.11.0 with its ECP-in-PCM cavity convention (paper §2.7); the ωB97X series cache records that version, while the B3LYP series and the 21d/21f caches record none — so the comparison holds only while every point stays in the recorded environment, and a re-run of one side alone would mix two cavity conventions silently. ⊕ 2026-10-12 (read across the three series 2026-10-13): the programmatic geometry is load-bearing for the substituent pairs themselves — relaxing Os(II) changes them by −9…+77 % and brings the donor pairs of our own core closer to experiment and its Cl pairs away (limit (2)), while its Os–Cl overshoots the crystal range on the Os(II) minimum and comes back to 0.04–0.05 Å over the Os(III) range on Os(III)'s own (3б, the three donors; NO₂ 0.03 Å; Cl 0.03 Å); the Os basis, the continuum's formulation and radii and the axial donor do not move the pairs, the ligand basis is bounded on Me−H only; the flavin does not depend on the Os geometry, so each printed cascade number inherits whatever the relaxation does to ITS Os side: the B3LYP Koopmans offset (−1.05 eV) moves by +0.098 eV, its ε_LUMO(Os III) taken on the relaxed Os(II) geometry, and by −0.070 eV on Os(III)'s own minimum (paper §3.5 prints both) [⊕ 2026-10-16: −1.05 here and +1.03 below are 4a,5-dihydro levels; on the 1,5-dihydro donor the current ones are Table 4's Me row and Table 2, and the moves stand]; the ΔSCF cascade (+1.03 eV) takes its Os side from ωB97X/def2-TZVP, whose geometry sensitivity is not computed — the B3LYP ΔE_red of the Me point (−0.113 eV vertical, −0.026 eV adiabatic) is its nearest proxy — and with (3б)'s Me point in, that proxy stays under D's first trigger by its letter, so (3а) and the Me point of (3б) are not a trigger of D — ome and bpy met the same letter 2026-10-14: with both states relaxed their substituent pairs (≤ 80 meV a complex) and points (≤ 54 meV) stay under it (D's letter as narrowed 2026-10-08, pairs per complex as applied 2026-10-12), while the Koopmans cascade Δ of OMe moves by −0.142 eV with Os(III) on its own minimum (H −0.091, Me −0.070 eV) and the slope ①, extrapolated from the donors' +13 % over the fit set's span, by ≈ 0.13 eV — the first at the threshold by the letter, the second there only by extrapolation (as the 2026-10-13 submission priced (3а) at ≈ 0.17–0.2 eV), and neither is a trigger (⚖️ founder 2026-10-14, «так, так»: «carries a conclusion» read as what the paper concludes from the difference; the full form — `PIPELINE_STATUS`, D) (the rule ⚖️ founder 2026-10-13; its transfer to ωB97X is not computed, D's referee trigger stands; the numbers — `PIPELINE_STATUS`, D). ⊕ 2026-10-15: the condition of the 2026-10-14 verdict fired on Cl — its own Koopmans cascade Δ moves by +0.118 eV with Os(III) vertical on the relaxed Os(II) (−0.066 eV on its own minimum), the column staying monotonic over the relaxed members — so (а) and (б) go back to the founder, with NO₂'s numbers: NO₂ (landed the same day) gives (б) a computation — over OMe · Me · H · NO₂, four of the five fit-set members (COOH not relaxed), the slope moves −0.930 → −0.897 eV/σ, 0.034 eV over the span, shallower with both states relaxed where the donors alone extrapolated +13 % to ≈ 0.13 eV, and the slope §3.3 sets against ωB97X, over Me · H · NO₂ — all three relaxed — moves −0.931 → −0.859 eV/σ, 0.069 eV over its span, about 1.5 times under D's threshold; its own Koopmans cascade Δ moves by −0.198 eV on its own minimum (+0.102 with Os(III) vertical), the column staying monotonic over all five relaxed members on all three geometries, and NO₂/SO₂CF₃ (5.0 meV) is not decidable with SO₂CF₃ unrelaxed — re-ratified by the founder 2026-10-15: (а) and (б) are not D triggers, SO₂CF₃ is not measured, ΔG stays off (`83` `relaxed_geometry_check.acceptors`, `slopes`, `verdict_condition`; `PIPELINE_STATUS`, D).

**Honest:** on the 1,5-dihydro donor the raw B3LYP-Koopmans cascade (programmatic geometry) runs −0.38 (NMe₂) → +0.89 eV (SO₂CF₃), crossing zero near OMe — a one-electron offset, no direction read from its sign; its absolute level carries the donor HOMO's method error (how far a donor level moves with the protocol is what the block «Like-for-like cascade» measures), while the *trend/design rule* is the robust, transferable result. Numbers: `dft/os_mediator_series.json`.

### Cluster-Continuum Micro-Solvation & Speciation (② — script 34; dimethyl recompute OS-RECOMPUTE 2026-06-17)

> ⊕ **2026-10-19 (the like-for-like revision) — how to read this block now.** Its «bracket» (lower/upper), «group-8 PCM bias» and «gap closed» vocabulary belongs to the withdrawn decomposition of a one-electron gap. What stands is each form's ΔE_red, which enters the like-for-like cascade (block above) as an Os form. The hexa-aqua second shell (a) LOWERS E° by 0.98 V, the opposite of the waters on the chloride (b), which raise it — so (a) is the size of the continuum-error class on a small +2/+3 couple, not a benchmark the device couple is read against or bracketed by; the «±0.15 V» in (a) is not a sourced convention uncertainty (the like-for-like cascade uses the 159 mV between 4.281 and 4.44 V); «functional-robust» below means only that the ORDER chloro < {aqua, bis-Im} of E°(Os) holds at both functionals.

Tests whether the raw cascade gap (above) is the implicit-solvation (PCM) limit, by
adding explicit waters / probing speciation on the charge-changing **Os(III/II)**
couple (the flavin couple is already within 65 mV of exp — script 32 — so it is not
the culprit [⊕ 2026-10-16: at the MMFF level only — with the ZPE on `32b`'s minimum the donor sits −210 mV off, the same order as the acceptor side, so this conclusion does not survive it either; ⊕ 2026-10-19 — withdrawn, Conclusion above]). Recomputed on the **real 4,4'-dimethyl-bpy mediator** (Zafar +309 mV vs
NHE), not the plain-bpy model. B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF; cascade
Δ = HOMO(FADH₂ −4.018)−LUMO(OsIII). All ⟨S²⟩≈0.754 (clean doublets). Numbers:
`dft/microsolvation_dmbpy.json`.

**(a) Aqua-couple PCM benchmark — [Os(H₂O)₆]³⁺/²⁺** (ligand-independent — sets the protocol beside the
~1 V error Rulíšek 2013 (JPCC 10.1021/jp406772u) reports for [Ru(H₂O)₆]²⁺ under PCM-type models — a COSMO-RS treatment largely removes it there, and Os carries a further ~0.3 V spin–orbit term; ⚠️ a single Ru couple, not a measured group-wide constant; ⊕ 2026-10-19: the second shell lowers this couple's E° — the opposite direction to the waters on the chloride of the device couple, which raise its E° (an unconverged series, not a closure) — so it is the size of the error class, not a correction or a validation, paper §3.5):

| shell | ΔE_red (eV) |
|---|---|
| n=6 (inner only) | −4.946 |
| n=18 (+2nd shell, 55 atoms) | −3.964 |

(The rows and the shift are `dft/microsolvation.json`. A second committed run of n=6, in `microsolvation_dmbpy.json`,
reads −4.943 eV — the same environment, Os(II) equal within 2e-8 Ha, the open-shell Os(III) in a different SCF
solution 2.4 meV away; paper §2.7.)

2nd-shell shift = **+0.982 eV ≈ the ~1 V reported for [Ru(H₂O)₆]²⁺ under PCM-type models** for this **+2/+3**
couple (2nd-shell H-bond directionality a continuum cannot model). The **shift** is the
robust result (absolute E° is electronic-E proxy, ±0.15 V).

**(b) The real mediator IS chloro — explicit Cl⁻ solvation** of the verified
cis-[Os(4,4'-dimethyl-bpy)₂(1-MeIm)Cl]⁺/²⁺ + k·H₂O on Cl⁻ (k=0 = the device baseline;
its cascade Δ +0.065 = the k0 baseline; the 4,4'-dimethyl **substituent** axis ① adds
**+0.142 eV** [Hammett: dmbpy +0.068 vs plain +0.210], a contribution separate from solvation):

| k·H₂O(Cl⁻) | cascade Δ (eV) | gap closed vs k0 |
|---|---|---|
| 0 | +0.065 | — |
| 1 | +0.128 | +0.063 |
| 2 | +0.202 | +0.138 |
| 3 | +0.271 | **+0.206** |

~0.07 eV/water, monotonic. Crucially this **+1/+2** chloro couple carries a **~5× smaller**
differential-solvation error than the +2/+3 benchmark (a): Cl⁻ lowers the couple charge, so
even the full chloro shell stays well below the +0.98 eV group-8 figure. This is the **lower bracket**.

**(c) Operando speciation — the PVI-brush 6th ligand (upper bracket).** The polymer is
*synthesised* as chloro (Zafar), but in the operating poly(vinylimidazole) brush the 6th
site may instead be a **2nd chain imidazole** (bis-Im) — far more likely than aquation,
since the Os(II) d⁶ couple is substitution-**inert**, and the PVI-realistic form
(CHEM.20/26). Both **+2/+3** forms computed on the dimethyl mediator:
- **bis-Im** cis-[Os(dmbpy)₂(1-MeIm)₂]²⁺/³⁺ → cascade Δ **+0.619 = +0.554 eV vs chloro** (the PVI-realistic **upper bracket**).
- **aqua** cis-[Os(dmbpy)₂(1-MeIm)(H₂O)]²⁺/³⁺ → cascade Δ **+0.554 = +0.490 eV vs chloro** (methodological benchmark — aquation unlikely on the inert couple).

On the dimethyl mediator **B3LYP gives bis-Im > aqua > chloro** (on plain bpy it was aqua >
bis-Im) — the strong σ-donor 2nd imidazole plus the 4,4'-dimethyl donors. **This internal
aqua↔bis-Im flip is functional-sensitive, though** — the ωB97X cross-check (B4, §below) keeps
aqua > bis-Im (within 0.15 eV). What *is* functional-robust is the chloro(+1/+2) ↔ {aqua,
bis-Im}(+2/+3) bracket — both +2/+3 forms sit above chloro at both functionals, and both
carry the larger group-8 PCM bias (benchmark a).

**Verdict (chloro-anchored bracket):** ⊕ 2026-10-19 — the reading below was written for the 4a,5-dihydro numbers; its shifts stand (they enter the like-for-like cascade as Os forms), its gap and attribution are withdrawn (Conclusion above). The real mediator is **chloro** (Zafar +309 mV), so
the raw-DFT↔exp gap is differential PCM solvation **bracketed** between the as-synthesised
**chloro (+1/+2, lower — +0.21 eV/3 waters, trending to a sub-1-eV full shell)** and the
operando **bis-Im (+2/+3, upper — +0.55 eV B3LYP / +0.27 ωB97X, PVI-realistic)**, plus the **4,4'-dimethyl
substituent** (+0.142 eV Koopmans ①, a separate axis). aqua is a methodological benchmark, **not**
"what the experiment measures" — the earlier "exp = aqua" framing is **withdrawn** (Zafar's
polymer is explicitly chloro). The gap is a **quantified method limit**, not a chemistry
failure; rigorous closure = QM/MM of the **chloro** species (follow-up: own PySCF or a specialist computational-electrochemistry collaboration).

**ωB97X cross-check (script 34b ✅ B4):** on the dimethyl mediator ωB97X ΔSCF puts **both
aqua (+0.42) and bis-Im (+0.27 eV vs chloro) above the as-synthesised chloro** — so the
chloro↔+2/+3 **bracket is functional-robust**. The internal aqua↔bis-Im order is **not**:
ωB97X keeps **aqua > bis-Im** (the plain-bpy order), whereas B3LYP-dimethyl uniquely flipped
to bis-Im > aqua (the two within <0.15 eV). Since aqua is only a methodological benchmark,
the operando **chloro↔bis-Im bracket holds at both functionals**. Cache
`wb97x_speciation_dmbpy.json` (3/3 forms converged via Newton, ⟨S²⟩≈0.754).

### Electron Tunneling Route (script 28 — a contact-graph shortest path, NOT a pathway analysis)

FAD:C5B → FAD:O4B → FAD:C4A → FAD:N1A → **ALA261** → **THR260** → **THR283** → **THR288** (surface) — found from the first FAD atoms of the structure file (PA · O1A · O2A · O5B · C5B: the phosphate/ribose end), not from the isoalloxazine N5
- 10 atoms, 9 steps, 23.7 Å; cost 7.8 = one covalent step (0.6) + eight «hbond» steps (0.9) — in the code an «hbond» step is ANY pair within 1.8–3.5 Å that includes N, O or S (a through-space step would cost ≥ e^{1.1·1.8} ≈ 7.2 alone), so the route is a chain of contacts, not of bonds; its «β·d» 2.05 = ln 7.8 is not a Beratan–Onuchic decay. Withdrawn from the paper (self-review round 1, cluster 6, 2026-10-15; corrected the same evening by the adversary on `079b81cec`); the committed caches keep the old `method` label
- **28b (CHEM.16) is NOT the same search:** its sources are the first atoms matching script 27's GAFF-name prefixes — by the adversary's mapping of 2026-10-15 on the MD structure, adenine C2/N3/C4 and flavin N1/C2, not N5, so they even overlap 28's route at FAD:C4A, and it records no path — its ln Σw = **2.02 ± 0.13** is the cost from a different start, so it says nothing about the route above either
- the paper reports no tunnelling pathway; a Beratan–Onuchic analysis from N5 is a follow-up.
- PBC for 28b's MD frames: mdtraj `image_molecules` (co-locates the separate FAD cofactor; `make_molecules_whole` alone insufficient).

Details → [`L3_quantum_chemistry.md`](L3_quantum_chemistry.md).

### Cathode: DET Through ZIF Nanozyme

**Method:** ΔSCF (UKS, level_shift 0.3) energy-splitting for bimetallic ZIF clusters (script 24) on the **clash-free geometry** — script 23 deprotonated a bridging imidazole N–H that had collided with the 2nd metal at 0.97 Å (→ imidazolate bridge) — then Marcus k_ET with a two-sphere λ (λ_hop = (λᵢ+λⱼ)/2) instead of an assumed one. 🔴 **«Computed» is only half true on the bottleneck hop, and the cache now says which half** (`cathode_ket_lambda.json` → `lambda_computed_provenance`, added 2026-09-21): Co, Ce and Ru come from script 35's Nelsen 4-point, **Cu does not** — a Cu(I) d¹⁰ hexa-aqua optimisation is unphysical, so the shipped cache of script 35 carries no Cu row and λ(Cu) = 2.0 eV is the **literature** value. 🔑 That sentence is no longer a claim this page has to keep true by hand: since 2026-09-22 script 25 **derives** its Cu provenance line from script 35's cache at every run, and names all three states apart — no row · a row flagged unphysical · a row that PASSES the physicality check, which it announces as a STALE FALLBACK. A full run of 35 emits a Cu row either way (`which = … or list(METALS)`), so the absence is a state, not a property. λ_hop(Cu-Co) is their mean, so half of the bottleneck's λ is a citation. The script's docstring always said so; the emitted key was named `lambda_computed_eV` and did not, and the cache is what this page quotes.

| Hop | t_ij (eV) — fixed geom | (old, broken geom) |
|-----|-----------|--------|
| Cu↔Co (T1↔ZIF node) | 0.00128 crude — ΔE 9.4× SCF tol, unresolved (the margins use the FO-DFT **0.00546** ↓) ← bottleneck | 0.0325 |
| Co↔Ce (ZIF node↔vacancy) | 0.00687 | 0.0022 |
| Ce↔graphene (vacancy↔MWCNT) | 0.1129 | 0.1177 |

The geometry fix shrank Cu-Co t_ij **25×** → **Cu-Co is the bottleneck**, not Co-Ce.

**k_DET vs λ AND vs the driving force (script 25) — the margin is sensitive to both:**

🔴 **Since 2026-10-15 (Стаття 1 self-review round 1, clusters 1 · 8) the table runs on the FO-DFT coupling, and the
verdict is conditional on λ(Co).** The crude t(Cu–Co) above is half the difference of two UNCONSTRAINED SCF solutions of
one cluster from one start (script 24: state B differs only in SCF settings — level shift, DIIS space, cycle cap) — not charge-localised states, and the
difference is 9.4× the SCF tolerance both were converged to (`dscf_coupling_resolution`), so it resolves no coupling; its
table survives as `scenarios_crude_dscf` (the pre-2026-10-15 published numbers: lit-λ ×0.0045…×40, ×1.4 at ΔG = 0).
λ(Co) carries the verdict: turnover needs λ(Co) ≲ 2.0 eV at ΔG = 0 on the 2.0 eV λ(Cu) reading and ≲ 0.9 eV at the
adverse corner (`cobalt_lambda_condition`); the computed 3.09 eV ([Co(NH₃)₆], LS-Co(III)/HS-Co(II) IMPOSED by script 35,
not found) is far above both, the literature 1.4 eV has no primary. ⛔ The earlier «B3LYP over-estimates Co ≈ 2×
(spin-crossover artefact)» is withdrawn: no benchmark in the tree supports it, and it was what let the literature row
read as «the honest estimate».

🔴 **Until 2026-09-21 this table was computed at ΔG = 0 — the Marcus helper's DEFAULT, not a
measurement** — while the FO-DFT block below already carried a computed **0.183 eV** Cu–Co
site-energy gap. The gap's *magnitude* is measured; its *sign* is not (the two-state orbital
diabatisation of `24b` returns |ΔE| and does not say which site is the donor on the cathode's path), so
every row is now a **bracket**, and the consumer's ceiling is the **adverse** end, cited
(`in-silico` §When Modifying #11).

🔴 **Since 2026-09-24 the bracket has a SECOND axis — the λ(Cu) reading.** λ(Cu) was one unsourced
textbook number (2.0 eV); the one open primary found, Gray & Winkler, *PNAS* 2005 (PMC553296), gives
**≈2.4 eV for Cu(phen)₂²⁺/⁺ self-exchange** — ⚠️ the species is an inline formula IMAGE that the
page's text layer drops, and it had been carried as «aqueous Cu(II/I)»; read from the image, it is a
bis-phenanthroline N₄ chelate. Both readings stay in the bracket (the unsourced end keeps
`[CITATION NEEDED]`), and the adverse column is the worst **corner** (uphill gap × higher λ(Cu)),
computed over all six cells, not assumed. ⛔ Both are **unconstrained solution couples**: a
framework-held Cu–N₄ node can sit **below both** (the same paragraph gives Cu(II/I) in azurin
0.7 eV — the entatic fold), so the bracket bounds the READINGS, not the site — its adverse end is a
consumer ceiling, its kind end is no floor. The ΔG = 0 column stays on the 2.0 reading so the
pre-2026-09-21 published ×1.4 remains traceable.

| λ scenario | bottleneck | **adverse (+gap)** | ΔG = 0 (assumption) | favourable (−gap) |
|---|---|---|---|---|
| canon λ=0.7 (old assumption) | Cu-Co (Co-Ce at −gap) | **×1.2×10⁴** | ×6.6×10⁵ | ×1.0×10⁶ |
| **literature λ** (Cu 2.0–2.4 / Co 1.4 / Ce 1.0) | Cu-Co | **×0.081** | ×25 | ×730 |
| computed λ (B3LYP, Co 3.09 — ammine) | Cu-Co | **×1.9×10⁻⁵** | ×5.4×10⁻³ | ×0.17 |
| Co→Ru swap (computed λ_Ru = 0.78) | **Cu-Ru** | ×76 | ×570 | ×570 |

⚠️ **Read the last row differently from the others: its spread is the λ(Cu) reading ALONE, and its
ΔG = 0 and favourable columns are identical, because the Cu–Ru node has NO usable gap** — script 24d returns 0.128 eV and *self-flags it non-physical*
(`localised: false`, `physically_reasonable: false`: both diabatic orbitals sit on Ru, pop(Cu) = 0),
the same failure that disqualified its t_ij. So **the Ru lever's driving force is unmeasured by
construction, and its ×76…×570 is a ΔG = 0 reading over λ(Cu) on the BORROWED Cu–Co coupling**, not a gap bracket that happened to be flat — and λ(Ru) sums Nelsen halves −0.26 and +1.04 eV (`ru_lambda_nelsen_halves`): one negative, so one optimised geometry is not the minimum of the state evaluated on it, and the row is INDICATIVE.
⊕ The bottleneck hop is **branch-invariant in every live scenario**: Cu–Co (or Cu–Ru) limits in every ΔG branch, so the
sign question moves the margin, never the identity of what limits — only the withdrawn λ = 0.7 row's favourable branch is
Co–Ce-limited on the FO-DFT coupling.
⚠️ The adverse literature-λ figure is quoted as **×0.081** and never as its reciprocal — a
reciprocal reads as a margin ABOVE turnover and means the opposite thing.

**Conclusion (revised, honest):** the old "k_DET = 1.09×10⁸, ×10⁵ above turnover, *not* rate-limiting" was a **double artifact** — a broken bridging geometry (clashing N–H) **and** an assumed λ = 0.7 eV. Its first correction read **~turnover (×1–30) at ΔG = 0**, and carrying the measured gap and the λ(Cu) bracket put the crude-coupling adverse corner at ×0.0045 — both on a coupling that does not resolve (above). 🔴 **On the FO-DFT coupling (script 24b, CHEM.14; t_ij(Cu-Co) = **0.00546 eV** + a 0.18 eV computed site-energy gap) the verdict is CONDITIONAL ON λ(Co):** at the assumed literature λ(Co) the Cu-Co margin spans **×0.6 (uphill) to ×730 (downhill), ×25 at ΔG=0** on the 2.0 reading, and **×0.081 at the adverse corner** of the λ(Cu) bracket; at the computed λ(Co) it is ×1.9×10⁻⁵…×0.17 — rate-limiting at every corner. The old ×10⁵ is firmly excluded either way. Remaining closure = a λ(Co) benchmark and experimental EIS. **Mitigation:** low-λ metal (Co→Ru, ×76…×570, indicative), conductive-MOF band transport ([`01_03 §3.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell) / CHEM.31), or enzyme-free SAC (CHEM.6). Numbers: `dft/zif_hopping.json` + `dft/cathode_ket_lambda.json`.

**Ru lever — the t_ij "double-whammy" is NOT confirmed (CHEM.32, scripts 24c/24d).** The Co→Ru ×76…×570 above is a **ΔG = 0 reading** over λ(Cu) on the borrowed Cu–Co coupling (table note) and is the **λ** benefit alone (λ_Ru 0.78 — itself indicative, one negative Nelsen half). We tested whether Ru's diffuse 4d *also* raises the coupling: at the canon cluster geometry with Co→Ru (identical coordinates; control Cu-Co reproduces canon t_ij 0.00128 ✅), the crude ΔSCF gave a large splitting (×81, t_ij 0.10 eV) and the FO-DFT diabatisation gave t_ij 0.105 eV — **but both FAIL the physicality check**: the frontier MOs localize entirely on Ru with **no Cu-d partner** in the window (24d self-flags non-physical — both diabatic orbitals pop(Ru) ≈ 0.86, pop(Cu) = 0.00). The minimal cluster's Cu-d and Ru-d manifolds are too energy-mismatched to form a clean Cu↔Ru diabatic pair (unlike Cu-Co). So the coupling boost is **plausible but unvalidated by this approach** — a rigorous Cu-Ru t_ij needs **CDFT constrained diabatic states** (a follow-up capstone: PyCDFT in-house or a specialist collaboration). The Ru lever stands on its **λ** advantage; its coupling advantage is a hypothesis, not a result. Caches: `dft/cu_ru_coupling.json` + `dft/cu_ru_fodft.json`.

**Model caveats** (frame the verdict — *not* a margin-chase): t_ij is **geometry-bounded** — a clash-corrected programmatic cluster, not DFT-relaxed (these flat-PES metal clusters resist geom-opt, cf. script 21c); and the single-hop bottleneck is **conservative** — the ZIF is a wide-gap **insulator**, so transport is the discrete Marcus hops modelled (not bands), and the 3D framework offers **parallel** instances of the bottleneck hop (band-like transport = the cMOF lever, CHEM.31).

🔴 **«Geometry-bounded» now carries a NUMBER (2026-09-21, CHEM.35 probe) — and what makes it matter is not its size but that nothing declared it.** The bridge ring's roll about its own N···N axis is a degree of freedom the builder never scored. Rolling it out of the metals' coordination plane — Cu **0.696 Å**, Co **1.371 Å** off-plane, everything else identical — moves the FO-DFT coupling **0.00546 → 0.1327 eV** (×24.3), because an out-of-plane metal stops binding through the nitrogen's in-plane lone pair and starts overlapping the ring π directly.

⛔ **It is NOT a ×|t|² story, and quoting it as one understates it ~25× and misdescribes it in kind:** the same diabatisation of the same cluster also moves the site-energy gap (0.183 → **0.0264 eV**), so the consumer-rule margin goes **×0.59 → ×8855 — a factor of ×15 008 — and that CROSSES enzymatic turnover** (both on the 2.0 λ(Cu) reading — the probe prices the geometry, not λ). In other words this one construction choice does not widen ③'s verdict, it **flips** it, from «rate-limiting on the adverse reading» to «comfortably fast» (`cathode_ket_lambda.json` → `geometry_sensitivity_refused_offplane.flips_the_verdict`).

🔑 **So read it as a LOAD-BEARING criterion, not as an uncertainty band.** The off-plane geometry is **refused** — script `23` exits 1 on it (`bridge_out_of_plane` vs `PLANARITY_TOL_A`), because a coordinating nitrogen binds through an in-plane lone pair — and the shipped cluster is correct on exactly that axis (metals **0.000 Å** from the bridge plane). ③'s verdict therefore rests on one geometric criterion being right, and until 2026-09-21 nothing in the tree named it, gated it or measured it. ⚠️ **What remains genuinely open is different and still unmeasured:** the residual spread WITHIN the in-plane family (M–N–C angles, the ring's in-plane tilt). The probe is rebuildable on purpose — `23 --solve-bridge --roll perpendicular` → `24b --geometry offplane` — so the criterion has a live instrument, not a remembered number.

**Bridge geometry — what the shipped cluster actually is** (`dft/zif_bridge_geometry.json`, script `23`):

| what was checked | result |
|---|---|
| bridge N···N span, 2-methylimidazolate ⊥ benzimidazolate | **2.213 ⊥ 2.218 Å** (Δ 0.005, ~0.2 %) — linker-INVARIANT |
| metals vs the bridge-ring plane, shipped cluster | **0.000 / 0.000 Å** — in-plane, physically right |
| Cu–N, Co–N on the bridge, shipped cluster | 2.020 / **1.946 Å** (target 2.050 — 5 % short, the price of the COM roll) |

🔑 **Three things follow, and the third closes CHEM.35.** (1) The lever's canon caveat — «a bigger ligand pushes the metals apart» — is **false on the bridge axis**: a ring fused at C4–C5 grows the ligand footprint by 0.9 Å without touching the N–C–N span that sets M···M. (2) The canon recipe «swap the linker in `23`, re-run `24`» builds a cluster with **no bridge at all** (the second N lands 3.217 Å from its metal, the N–H survives the clash filter, the charge is off by one) — `24` would still have returned a coupling. (3) A correctly-bridged ring **does not fit this model**: hold the metals in-plane and the bridge collides with the coplanar terminals (0.254 Å methylimidazolate, 0.358 Å benzimidazolate); hold the sterics and the metals leave the plane, which is the ×24 artifact above. **So the shipped geometry is the best the 2D minimal cluster can do, and CHEM.35 is unanswerable here — it needs a 3D cluster with tetrahedral terminals, an instrument change that moves every number in this section** — ⚖️ ratified (delegated) 2026-09-22: **not built now**; the return trigger is the measured cathode EIS of coin Stage 2 (verdict, price and weakest link — [`01_03 §3.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).

⊕ **Acceptance threshold for any COUPLING lever** (`dft/cathode_ket_lambda.json` → `coupling_gain_to_reach_turnover`): since `k_ET ∝ |t_ij|²`, lifting the consumer-rule (adverse) reading to enzymatic turnover needs **×3.5** on the diabatised t_ij at the ASSUMED literature λ(Co) 1.4 eV and **×231** at the computed 3.09 eV (`by_lambda_co`), or ×14.9 on the crude ΔSCF one — all at the adverse CORNER (uphill gap × higher λ(Cu)). ⚠️ The threshold is conditional on λ(Co) exactly as the verdict is; a single number here is a λ(Co) pick in disguise. ⛔ It does NOT apply to a λ lever (Co→Ru): λ sits in the Marcus exponent, not the prefactor.

---

## L4 — Chemical Kinetics

**Model:** Michaelis-Menten + Arrhenius + BQ25570 boost − sleep drain → delta_t = E_cycle / (P_ebfc · η_BQ − P_sleep) — the same form as the canon's H = E_active / (E_gen − E_sleep) ([`02_03 §9.6`](../../../02_03_BQ25570_MPPT_Nano_Power.md)), with the same cycle cost and sleep drain since 2026-09-27

| Parameter | Value | Source |
|-----------|-------|--------|
| j_max(25°C) | 881 µA/cm² | Zafar 2012 (PMC3275720) Table 1, dgrGcGDH row — MM **asymptote** derived as 520 × (K_M+20)/20; a pH-7.4 graphite ceiling |
| Km(glucose) | 13.9 mM | Same row, same fit (K_M^app 13.9 ± 3.1; apparent — carries the hydrogel's mass transfer) |
| Ea | 40 kJ/mol | Typical FAD enzyme |
| V_op | 0.5 V | EBFC under load |
| A_electrode | 2 cm² | ONE face of the Ø16 Ti-coin COUPON — never the anchor (`lib/constants.py A_ELECTRODE`; the gyroid anode differs by 30–60×) |
| η_BQ | 0.68 | BQ25570 datasheet (SLUSBH2G Fig.6-7, low-I_IN; [HW.47]) — ⚠️ the 15 µW point, applied here at ≈369 µW: the `02_03 §9.1` table has η rising to 0.82 by 100 µW, which would shorten every `delta_t` by ~17 % (healthy 135.2 → 111.8 s). A named model axis, not folded in (the table tops out below this power) |
| E_cycle | 33.33 mJ | `E_active_from_VSTOR` of the node chain — a MIRROR of [`02_03 §9.6`](../../../02_03_BQ25570_MPPT_Nano_Power.md) Scenario C (ECB 16 B frame, SF9, +14 dBm; home `tools/firmware/tx_cadence_budget.rb`), pinned to that canon line. No inference term since the piezo cut ([`02_01 §6`](../../../02_01_Hardware_Architecture_and_BOM.md), 2026-09-29). Until 2026-09-27 a 5 mJ placeholder ([`00_07`](../../../00_07_Action_Plan_Tracker.md) E.63) |
| P_sleep | 4.18 µW | Sleep drain from VSTOR between cycles, same chain (300 nA sleep — the Standby-class target, not the shipped STOP2, `00_07` FW.54 — + BQ I_Q) — subtracted from the boosted power; it was absent before 2026-09-27 |

### delta_t Predictions

| Scenario | [glucose] | T(°C) | delta_t (s) | vs 60 s (legacy baseline) |
|----------|-----------|-------|-------------|-----------------|
| Healthy summer | 10 mM | 25°C | **135.2** | > 60 s |
| Active growth | 20 mM | 30°C | **72.9** | > 60 s |
| Moderate spring | 15 mM | 20°C | **143.7** | > 60 s |
| Cold winter | 5 mM | 5°C | **732.7** | > 60 s |
| Severe stress | 3 mM | 0°C | **1657.8** | > 60 s |

**Conclusion (revised 2026-09-27, [`00_07`](../../../00_07_Action_Plan_Tracker.md) E.63):** 🔴 the former «BASELINE_DELTA_T_S = 60s is physically justified» does not survive the node chain's own cycle cost — with 33.33 mJ and the sleep drain, even this lab ceiling gives 72.9–1657.8 s, and the iso-60 s contour is not reached at 5, 15 or 25 °C anywhere in 1–30 mM. The 60 s figure survives only as a default argument of the chaos half, not as a physics claim; growth points read `delta_t` through the field-scale band `DELTA_T_FAST_S`/`SLOW_S`, which these coupon numbers must not calibrate. ⚠️ Scoped: this is the five deterministic scenarios; the model's own grid dips below 60 s from ≈ 31 °C with high glucose (minimum 37.8 s at 40 °C / 30 mM), and so does the MC band's lower tail. What does survive: `delta_t` still moves with the tree's conditions — ×5.4 between healthy summer and cold winter, but 71 % of that (in log terms) is the 25 → 5 °C Arrhenius step (×3.31 at 10 mM), and at equal temperature 10 → 5 mM gives only ×1.60: the model separates SEASONS more than it separates STRESS. Diffusion is still NOT rate-limiting (j_kinetic ≪ j_diffusion). The multiplier from here to the canon's 1.54 h is named in [`02_03 §9.1`](../../../02_03_BQ25570_MPPT_Nano_Power.md).

**pH bracket — printed BESIDE the table, never folded into it (⚖️ founder 2026-09-18).** Every delta_t above is a **pH-7.4 laboratory ceiling**; our sap setpoint is pH 5.75. Sygmund 2011 (*Microb. Cell Fact.* 10:106, Table 3 — free enzyme, ferrocenium 20 µM, 30 °C) gives the same enzyme at both pH values, and the correction is **[S]-dependent**, because k_cat falls (×0.43–0.47) while K_M also falls (×0.54–0.59) and the two partly cancel:

| Scenario | ceiling (s) | ×wt | ×rec | delta_t at pH 5.5 (s) |
|---|---|---|---|---|
| Healthy summer | 135.2 | 0.68 | 0.58 | **200.4–237.2** |
| Cold winter | 732.7 | 0.75 | 0.63 | **1010.9–1236.6** |
| Active growth | 72.9 | 0.61 | 0.53 | 119.9–139.3 |
| Severe stress | 1657.8 | 0.79 | 0.66 | 2223.1–2830.2 |

⚠️ The two ends are the **wild-type and recombinant forms of the same paper disagreeing** — that disagreement IS the bracket; electing one would manufacture precision the source does not carry. ⛔ And the pair was measured on the FREE enzyme with a small-molecule acceptor at 30 °C, so it is applied here as an indication for our immobilised Os-polymer electrode, not as its measurement; the 5 °C row additionally assumes a temperature-independent pH effect, which nobody measured. 🔑 Since 2026-09-27 the pH column is computed with the CURRENT scaled by the ratio, not as the ceiling divided by it: the sleep drain does not shrink with the current, so the penalty lengthens delta_t by MORE than 1/ratio — most at the stressed end, where sleep is the larger share (E.63).

**The Monte-Carlo band carries the same condition — applied 2026-09-21, and it had been missing.**
`30b` samples Km, Ea, j_max, area and E_cycle and reports a 90 % CI (E_cycle over the node chain's own
bracket, ≈ 28.8–43.2 mJ, every end a term `02_03 §9.4` names — since 2026-09-29 without the inference term, which left the cycle with the piezo). 🔴 **That CI is also a
pH-7.4 figure**, because the sampled j_max is centred on the same laboratory ceiling — and until
2026-09-21 nothing in `30b` said so, while its sibling `30` had carried the ratified «print the
bracket beside» shape since ⚖️ 2026-09-18. A verdict ratified for one leg does not reach its sister
by itself ([`00_05 §4`](../../../00_05_AI_Native_Operating_Model)); this is that transfer.

| Scenario | 90 % CI at the ceiling (s) | median | **90 % CI at pH 5.5 (s)** | median at pH 5.5 | vs 60 s baseline |
|---|---|---|---|---|---|
| Healthy summer | 69.3–462.9 | 163.1 | **102.4–835.5** | 242.0–286.6 | > baseline |
| Active growth | 36.6–211.4 | 77.6 | **60.0–408.9** | 127.7–148.3 | > baseline |
| Cold winter | 351.6–3664.1 | 998.8 | **477.0–7720.6** | 1390.5–1715.9 | > baseline |
| Severe stress | 747.8–16744.4 | 2482.6 | **972.8–∞** | 3410.0–4442.8 | > baseline |

`∞` = the percentile lands on samples whose boosted power does not exceed the sleep drain: the node never
gathers a cycle there (the canon's H = ∞). It is ONE end of the pH bracket, not the band: at pH 5.5 the
recombinant form leaves 5.11 % of severe-stress samples «never» and the wild type 2.48 %; at the ceiling it is
0.8 % (`never_gathers_cycle_pct`). ⚠️ Two things drive that tail and neither is the tree: the sampled area
(U(1, 5) cm²) reaches below the coupon's 2 cm² face — at the ceiling every «never» sample has A ≤ 1.49 cm²,
at pH 5.5 up to 2.42 cm² (`never_max_area_cm2`); and EDLC self-discharge is in neither this model nor the
chain (no number yet, `02_03 §9.3`), though +1 µA (≈ 4.5 µW) would outweigh the whole 4.18 µW sleep and
dominate the stressed tail. Until 2026-09-27 `30b` capped every sample at 3600 s BEFORE the percentiles;
harmless on the placeholder scale, it would now have printed that tail as «3600 s».

⚠️ The right-hand columns are the **same distribution transported**, not a wider CI: every sample's
current is scaled by the [S]-dependent ratio and the percentiles are recomputed, so the band moves rather than spreads. The ratio
carries the *source's* K_M shift while the sampled `km` spread is about *our* apparent constant —
related axes, deliberately not summed (`conditional_on` in the cache says so).
🔑 **What the transport does and does not change:** every median sits above 60 s in both media (the
lower tails do not — Active growth's ceiling p5 is 36.6 s), so since 2026-09-27 there is no median
crossing left for the sap-pH penalty to threaten. What it still moves is the **upper decile** of the healthy
band, which moves from 463 s to about 836 s; a claim that quotes 69–463 s without naming pH 7.4 is quoting
a medium we do not deploy in — and at the stressed
end the transport no longer just shifts the band, it opens the «never» tail above.

### EIS Predictions (for Ti-coin Stage 2)

| Parameter | Predicted | Literature Range |
|-----------|-----------|-----------------|
| Rct (charge transfer) | 72.9 Ω | 100-500 Ω |
| Rs (solution) | 100 Ω | 50-200 Ω |
| Cdl (double layer) | 50 µF/cm² | 20-100 µF/cm² |
| Time constant τ | 7.3 ms | — |
| Warburg region | < 21.8 Hz | — |

The 72.9 Ω Rct above is the **anode** charge-transfer (enzyme→Os, from j_max; script 31). The
**cathode** DET Rct is *not* a single value — script 31b (Laviron, surface-confined) gives a band
**~0.002 Ω–7×10⁶ Ω** across the k_DET bracket (gap sign × λ(Cu) reading × λ(Co) value) × the unknown
site coverage Γ: the cathode arc can be negligible (fast/dense) or **exceed the anode arc
up to ~×10⁵** (adverse corner, sparse coverage; the high end moved from 3×10⁴ Ω / ×400 on 2026-10-15 with the λ(Co)
axis — the low end did not), so it **cannot be predicted a priori** — the robust statement stays the **kinetic competition**
k_DET against turnover — itself conditional on λ(Co) (§Cathode) — with the measured Ti-coin cathode EIS the decisive test. INDICATIVE
(`kinetics/cathode_det_rct.json`).

---

## HW.3.IS — Mechanical Integrity

### Thermal Stress + Stress Relaxation (scripts 50 + 56, thick-wall Lamé + relaxation)
| Parameter | Value |
|-----------|-------|
| Worst-case stress | **combined** (−30°C + s6-max, unified thick-wall Lamé, script 56): σ_t **17.9 MPa**, SF **5.6×** (von Mises 4.7×); thermal-only 14.6× (frozen Ø11/2 mm) |
| Press-fit P_c (H7/s6 band, bug-fixed) | **0.49-3.32 → 0.32-2.16 MPa** over 20 yr (was a buggy 34.7→22.6 — `THERMAL_STRESS_REPORT.md` Correction B) |
| Sealing | the Ti↔PEEK fit cannot seal at MIN fit (relaxed P_c ≤ sap 0.5) and is not asked to: ⚖️ the path is NOT sealed by design (`00_07` HW.34, 2026-09-18) — wet PEEK gap; the bus channel is to be closed at its exit (required 2026-09-18 — geometry after the pogo pin P/N, `00_07` HW.9; not in any drawing yet); the one O-ring seals the radome joint (`00_07` HW.33); PEEK = structural isolator + residual P_c (retention, not sealing); barbs = axial only |
| Winter | inner interface tightens; outer = tree (not a Ti shell) → old cold-leak was a baseline artifact |
| **Verdict** | ✅ Ti↔PEEK press-fit survives 20+ years on STRESS (combined SF 5.6× margin; **HW.3.IS unified Lamé 2026-06-22**) — the path is unsealed by design (row above). ⚠️ Not on RETENTION at the band's MIN: at +40 °C the 5 µm minimum opens (`press_fit_separates`), i.e. 5–34's MIN lies below the window floor (`00_07` HW.3, 2026-09-18) |

### Cyclic Strain (script 16, ±5% × 10 cycles)
| Parameter | Value |
|-----------|-------|
| Stretch PE | -60,821 ± 182 kJ/mol |
| Compress PE | -61,608 ± 236 kJ/mol (absorbs energy) |
| PE drift | 1.0% (borderline, small box) |
| **Verdict** | 🟢 Pseudoplastic — compress < stretch = energy absorption |

---

## HW.34 — Central Bus Conductor (monolithic; thermal + mechanical)

Spec home and every ratified decision → [`01_01 §1.4`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md); what is still open → `00_07` HW.34.

**Thermal bridge (script 54)** — 1D resistor ladder + 2-node steady state, at the canon rod **Ø1.0**
(`01_01 §1.4`), on the shipped insertion (the whole Zone-1 lock shank, ⚖️ `00_07` HW.26 G1 2026-10-12 — an
18 mm PEEK-only gap). A **Cu** bus dominates the Zone-2 PEEK break (G_anchor **13.2×** a Ti bus, ×20.1 vs no bus;
λ_Cu ~1600× PEEK) → drags the Zone-1 anode pocket to **−10.5 °C** (12.5° below the +2 °C core → living-sapwood
freeze-risk) at −30 °C air / +2 °C core. A bus **monolithic with the anode** (= the anode alloy) is
thermally near-invisible (**+0.52 °C**, ×1.52 vs no bus). Per bake-off alloy: alloyed α+β Ti
(4V/7Nb/β/15Zr, λ≈7) **+0.52…+0.43 °C**; CP-Ti (λ17) **−0.17**; Ta (λ57, benchmark) **−2.35** — **all ≪ Cu**, and
the −2 °C freeze gate now separates **five** candidates (safe) from **Ta alone** (freeze). Electrically
free at µA (Ti 11.3 µV at 100 µA, 4×10⁴ below the 500 mV reference).
(`mechanical/anchor_thermal_bridge.json`)
> ⚖️ **The gap moved, and one gate verdict moved with it — 2026-10-12, `00_07` HW.26 G1 (А).** Until then the
> Zone-1 insertion was a typed placeholder of 30 mm, leaving a 6 mm PEEK-only gap; the ratified insertion is the
> whole lock shank (18 mm), so the gap is 18 mm and every pocket warms (Cu −12.8 → −10.5 °C, monolithic Ti
> −0.70 → +0.52, Ta −5.65 → −2.35). 🔴 **`cell_freeze_risk["CP-Ti-Gr4"]` flipped true → false (−2.21 → −0.17 °C)**:
> the frost gate of this model no longer stands against CP-Ti — what still ranks it below the α+β four is the
> bare-wire fatigue column of `55` (§Mechanical below), not this one. Ta stays below the gate by 0.35 °C — about a
> quarter of the 1.37 °C the same ladder's `robustness_sweep` spans for a Ti bus at the gate's own −30 / +2 °C boundary
> over wood conductivity and reservoir radius alone (−0.16…+1.21 °C), so read it as «marginal», never as a measured freeze.
> ⚖️ **Re-run landed 2026-09-10 at the canon rod Ø1.0** (`00_07` HW.34) — the figures in this note are that day's, at the 6 mm gap; the live ones are above. What the diameter move cost on THIS side: the bus area shrinks ×1.69 (A ∝ d²), so the bridge looks *better*, i.e. the old figures were conservative and both load-bearing verdicts survived (Cu ×24.3 → ×18.2 vs no-bus, Cu/Ti ratio 9.57 → 9.31; monolithic Ti −1.43 → −0.70 °C). Exactly **one** cached boolean flipped — `cell_freeze_risk["316SS"]` true → false (−3.16 → −1.94 °C against the −2.0 gate) — and 316SS is the superseded pre-monolithic alternative, not a bake-off candidate; all six HW.24 alloys kept their verdicts. The one **anti-conservative** axis was electrical (R ∝ 1/A → IR drop was understated ×1.69, Ti 6.7 → 11.3 µV at 100 µA). ⛔ The direction here is OPPOSITE to script 55 below — never read one diameter caveat as covering both.

**Mechanical (script 55)** — slender-beam closed form, at the canon rod **Ø1.0**, on the shipped insertion
(the whole Zone-1 lock shank, ⚖️ `00_07` HW.26 G1 2026-10-12: free length 35 mm, PEEK gap 18 mm), and since the
fabrication verdict it reports **two branches**: `printed` (superseded) and `welded` (SHIPPED, ⚖️
2026-09-10, cold-drawn wire, no as-built knockdown). Buckling SF **11×** (1 N pogo) even unsupported →
still a non-issue in both. Sway fatigue: the bore **liner** (= the short-circuit insulation) doubles as
lateral support → infinite life for **every** alloy on the shipped welded branch (SF 2.5–6.9×; the superseded
printed branch reads 1.25–3.45×, CP-Ti and Ta below SF 2) — ⚠️ both on the 18 mm «supported» idealisation, which
since G1 lies ABOVE the compliant bracket's upper end on every geometry (§equilibrium below), so for the coaxial
regime it is a conservative bound: on the bracket itself every alloy clears SF 2 (welded Ta 5.80 at the upper end;
the printed derate of 0.50 halves it, still above 2) — and it says nothing about a channel offset. 🔴 **Bare, the fabrication choice decides — and it decides two different verdicts.** Printed:
infinite life for **0 of 6** (SF 0.65–1.78×), **CP-Ti (0.90) and Ta (0.65) predicted fatigue failures**. Welded:
every SF doubles → infinite life for **4 of 6** (SF 1.29–3.55×), with CP-Ti (1.80) and the binding candidate
**Ta at 1.29 below the SF-2 line**. ⚖️ **Both columns are the RATIFIED LOW END of the
`σ_e/σ_y` band since 2026-09-18** (founder 2026-09-17, `00_07` HW.34) — at the midpoint the welded column reads
5 of 6 (Ta 1.45); the shipped LINED configuration is unaffected in verdict and its binding corner is Ta **5.80**
at the upper end of the coaxial bracket (2.45 on the retired placeholder, 2.76 at the band's midpoint there)
(`§endurance_ratio_band`, swept 2026-09-12, model moved 2026-09-18). Per-alloy margin tracks yield = SAME
ranking as the thermal side → leading HW.24 candidates win on both. (`mechanical/bus_mechanical.json`)
> ⚖️ **G1 moved the bare column and the lined rod in OPPOSITE directions — 2026-10-12, `00_07` HW.26 G1 (А).** The
> whole-shank insertion lowers the anode's top, so the rod from its root to the pad plane grows 23 → 35 mm and every
> free-cantilever SF falls ×0.66 (σ ∝ L): welded 5 → 4 of 6 (Ta 1.96 → 1.29, CP-Ti 2.73 → 1.80), printed 4 → 0 of 6
> with CP-Ti joining Ta in predicted failure, buckling 25 → 11×. ⛔ That does NOT revive the fatigue ground for
> support: the column describes a rod with no wall anywhere, and the rod threads a bore (⚖️ 2026-09-11, the
> clearance regime below). On the equilibrium the shipped LINED rod got SAFER at the same time (binding corner
> 2.45 → 5.80), because the same longer span is a softer member against the exit contact. One input, two readings
> moving apart — and the one that moved the wrong way is the configuration that does not exist.
> ⚖️ **Re-run landed 2026-09-10 at the canon rod Ø1.0** (`00_07` HW.34) — and here the diameter move changed the CONCLUSION, not just the digits (σ ∝ 1/d³, SFs fall ×2.2). The unsupported branch did not thin out, it crossed the line: Ta 1.55 → **0.71**, CP-Ti 2.16 → **0.98**, and the four alloyed Ti dropped 3.8–4.3 → **1.74–1.94**, i.e. `unsupported_infinite_life` went **true → false for all six** (⚠️ that per-alloy boolean is now branch-suffixed — `unsupported_infinite_life_printed` / `_welded`; the bare name survives in `fabrication_branches` but as a LIST of alloys, so it resolves and no longer means the same thing). 🔑 **So lateral support is not a soft-alloy mitigation, it is a requirement for every candidate** (⚠️ an L_FREE_UNSUP = 36 mm-era reading, before the welded-wire verdict and the 23 mm CEM-derived span — the live per-branch answer is the table below) — which is the input the open HW.34 lining verdict was missing: a film that does not touch the rod (Parylene ~10 µm, anodised TiO₂ ≤10 µm in a sub-mm channel) insulates without supporting. ⚠️ The clause that stood here — «the model has no liner stiffness to give it credit for» — was true of that day's model and is not true now: since the clearance verdict the script computes the rod-plus-tube composite EI and reports both bounds, so a branch is no longer credited or denied support by omission.
> ⚖️ **Fabrication branch added 2026-09-11** (`00_07` HW.34) — the welded verdict re-opened the lining one, so the script now emits both columns. **The re-run narrowed the support motive without retiring it:** dropping the as-printed derate lifts Ta and CP-Ti out of predicted failure (0.71→1.41, 0.98→1.96) and **not** over the infinite-life line, so bare-rod infinite life goes 0/6 → **4/6**, not 6/6 (⚠️ the same 36 mm era). 🔴 **The tracker verdict's stated ground said "all six" and its own adjacent table did not** — the arithmetic there was right (every SF doubles) and only the conclusion was wrong; corrected in `00_07`. ⛔ And the doubling belongs to the WIRE: the model is a homogeneous cantilever, while the ratified joint sits at the root of the modelled cantilever (and the root IS the peak-moment section in every drag and offset configuration the equilibrium solves, except the lock-window geometry at a 9 mrad tilt about the mouth and a pogo eccentricity at the rod tip — `68` §`peak_moment_section`, 2026-09-14; the «peak is at the bore mouth» correction of 2026-09-12 described the retired drift picture). ⚠️ That sentence stays true about the wire; what changed 2026-09-12 is that the seam is no longer UNPRICED — see the next note, and read `fatigue_model.weld_seam_geometry_modelled` beside `…_sensitivity_modelled` rather than the single boolean this line used to cite.
> 🔴 **Clearance regime added 2026-09-11, and it RETIRES the fatigue ground rather than narrowing it further** (`00_07` HW.34, ⚖️ founder). Both `L_FREE_*` columns are FREE cantilevers — no wall anywhere — while the rod threads the cathode bore. At the ~165 µm radial play a 10 µm conformal film leaves, the rod takes up that play and **bears on the wall 4.5–11.1 mm inside the bore on every µ the script sweeps** (first contact 10.47–17.15 mm from the root). So the unsupported SF is a number for a configuration that does not exist, and the liner’s structural ground moved from FATIGUE to WEAR: a 10 µm film asked to be a bearing under a beam reaction in a THROUGH bore of `L/D` ≈ 12.6, whose wear-through is a ~0.5 V anode↔cathode short. (`mechanical/bus_mechanical.json` §`clearance_regime`; the verdict line is DERIVED, never typed). 🔴 **The bracketed figures above are HISTORICAL as of 2026-09-12 and the qualifier «on every µ» no longer holds for a conformal film** — the protrusion correction below shortened the span from 36 to 23 mm, which makes the rod STIFFER, so a 10 µm film then first touched the wall at 13.9–23.0 mm from the root, i.e. past the bore end at the lowest friction point (µ 0.2) only. ⚖️ The ratified verdict is untouched; what weakened is the ARGUMENT AGAINST the rejected branches, and it is recorded here rather than quietly re-derived. 🔴 **And every station in this note is RETIRED 2026-09-14, not merely dated: they are where the FREE tip-loaded shape crosses the play at full drag, and the contact solver (§`clearance_regime`, one home with script `68`) shows that is never a contact station.** What survives of the finding, re-derived: on a coaxial channel the shipped liner touches down at the EXIT on every swept µ on every geometry, and since G1 so do the conformal films (touchdown drag 0.06 N on the shipped geometry; on the retired placeholder only µ 0.3–0.5, at 0.22 N); the mouth is never reached coaxially. The regime block below is the live one.
> 🔴 **And the clearance verdict of the same day moved this section's OWN numbers — branch (в), channel Ø1.30 → Ø1.35, applied 2026-09-11.** Two things changed and only the second is a digit. **(1) The model can now say WHICH SIDE the leftover play sits on**, which it could not before: a conformal film is bonded to the rod, so its play is on the ROD side and the bending member is the bare wire; the ratified liner is tight on the wire and enters the bore as one body, so its play is on the CHANNEL side and the member is the rod-plus-tube composite (both stiffness bounds computed, `ei_Nm2_bare_rod` ⊥ `ei_Nm2_bonded`). **(2) The "hundredfold reduction of free travel" this page fed into canon was a ROD-SIDE number and is gone: the measured factor is `play_reduction.factor` ≈ 6.8×** (170 → 25 µm). ⚠️ The «supported-column root stress understated by 40.8 %» this note carried until 2026-09-14 measured the 6 mm idealisation against a free-shape first contact; under the equilibrium the SIGN reverses — there is no propped 6 mm span, the coaxial root stress against a RIGID wall is set by the exit contact (and is the LOWER end of a bracket, §equilibrium below), and the §2 supported column — since G1 an 18 mm span, the whole PEEK gap — OVERSTATES that rigid-wall end ×**16.18** at nominal µ on the shipped geometry (against the shallow end's own cap ×20.15 — the column itself is computed on the shipped geometry only; ×2.28 on the retired placeholder; `clearance_regime.supported_column_vs_equilibrium`, sign derived). Under a channel offset the comparison has no meaning: the root then carries a MEAN. So `L_FREE_SUP` overstates the coaxial root stress against a RIGID wall, and since G1 against the compliant liner too: the column sits ABOVE the bracket's upper end on both geometries at both µ (`column_position_*`, derived; on the placeholder it sat inside the bracket) — and it is the wrong quantity for the offset case. Measured, not asserted.
> 🔴 **Weld seam — BOUNDED 2026-09-12, RETIRED 2026-09-14, and the input is still missing.** Canon ([`01_01 §1.4`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) and the factory protocol `§3` step 1) had been sending the reader here for this state while nothing here held it. The seam's fatigue-strength knockdown `k` is in **no** canon row, **no** vendor answer and **no** experiment, so `weld_seam.knockdown_k_measured` stays `null`. On 2026-09-12 the model inverted `SF_seam = k · SF_wire` on ONE fully-reversed stress — the §2 supported column at the worst swept µ inflated by a span optimism measured along the free-shape first contact, 43.0 MPa — and reported a break-even `k` of 0.554 against our own marker `AS_PRINTED_DERATE` = 0.50 (margin −0.054, «does not clear»). 🔴 **That stress is the root stress of a free cantilever whose length is a free-shape crossing station; no equilibrium configuration produces it, and the bound is retired with the picture.** The equilibrium gives the root TWO regimes instead, and neither is a single fully-reversed number: on a coaxial channel the drag is fully reversed with an amplitude that is itself a BRACKET — the rigid-wall figure is its LOWER end, the Ti-bore stop its upper, the contact compliance between them unmeasured (mean 0); a channel off the root axis by more than the play puts a STATIC bending on the same section — a MEAN that grows with the offset, a rigid-wall UPPER bound — with the reversing drag as amplitude on top. ⛔ **No `k` is derived from either** (`weld_seam.break_even_k` = `null`, `break_even_k_not_derived_because`): the model has no mean-stress correction, so the offset regime cannot be priced, and a `k` inverted from the rigid-wall end of the coaxial bracket alone would silently assume both a coaxiality the stack carries only as a requirement (⌀0.10 — the form ratified 2026-09-18, the number 2026-10-12, `00_07` HW.34) and a rigid wall the part does not have. What the cache gives instead is the INPUT a seam acceptance needs — amplitude and mean at the root per regime and geometry (`weld_seam.root_section_loading`, the same solver and the same offset points as script `68`, pinned equal to `68`'s table below: its rigid-wall column and upper-end column bracket the coaxial amplitude · offset secant = mean per µm past the play · reversing amplitude, a rigid-wall figure). **Consequence, unchanged in direction and stronger in ground: `k` must come from the vendor** (weld class, WPS, post-weld treatment of the toe — `00_07` HW.34 👤), because there is no house number bracketing the joint at all now, not even a drift-picture one. ⚠️ The comparison markers stay OURS (`AS_PRINTED_DERATE` ⊥ `WROUGHT_DERATE`) as the scale a vendor `k` will be read against; nothing is compared with them. ⛔ Three seam mechanisms stay outside any bound and their signs differ: a bead upset/fillet RELIEVES nominal stress, a weld-toe notch AGGRAVATES it, and weld residual TENSION is a **mean** stress — the same absence that stops the offset regime being priced. (`mechanical/bus_mechanical.json` §`weld_seam`)

🔬 **WHERE THE ROD MEETS THE WALL — the equilibrium, 2026-09-14 (`clearance_regime`, `edge_bearing`; solver `lib.beam_contact`, one home with script `68`).** Until then every station here bisected from the ROOT along the FREE tip-loaded shape at FULL drag and read the crossing of the play as a contact; the first 18 mm (6 on the retired placeholder) have no wall at all (PEEK gap inside the Ø11 sleeve), and a shape that crosses a wall is not admissible once the wall exists. Solved as a unilateral contact, the picture splits by REGIME, not by µ:

- **Coaxial channel (drag).** The touchdown drag of the shipped liner is 0.0095 N on the shipped geometry and 0.0069 N at the lock window's shallow end — far below every swept µ·F — so on every swept µ and every geometry the rod is touched down at the **EXIT**, where the tube ends flush, and nowhere else (asserted per row); the deflection at the mouth is a fraction of the play (8.3 µm of 25 on the shipped geometry, 9.8 at the shallow end), so **the mouth is never reached coaxially**. Against a RIGID wall the touched-down shape is the prescribed-displacement shape and does not change with the drag, so the root stress is 3·E·c·g/L² and µ-invariant (the `68` table below) — **and that figure is the LOWER end of a bracket, not a cap**: the real wall is the PEEK wall on the Ti bore's exit edge, it yields by R/k and raises the root moment by 3EI·(R/k)/L², up to the Ti-bore stop behind it (the polymer wall fully yielded; the free cantilever F·L is reachable only where the drag cannot reach the bore). At the worst swept µ the root lies in [3.40, 23.8] MPa on the shipped geometry and [2.73, 19.1] MPa at the shallow end (`coaxial_root_bound`, `sigma_root_MPa_upper_end`); where in that bracket it sits is set by the contact compliance, measured nowhere (⊕ 2026-10-14: MODELLED since by script `91`, block below — on an unworn wall the cycle peak sits at the rigid end within a few per cent, and the Ti-bore stop is not an elastic state: exit wear saturates the peak once the mouth engages; still not measured). The wall reaction is at most the drag minus the touchdown drag (0.19–0.49 N over the swept µ on the shipped geometry — a rigid-wall UPPER bound; ⊕ 2026-10-14: for a flush SHARP edge only — with a rounded edge the patch sits inside the bore and `91`'s reaction is slightly larger), and the tube's flush END lands on the bore's exit edge at **0.061°** (rigid wall) — edge on edge, the form the ≥ 1.0 mm protrusion avoids at the mouth, with the exit radius ratified only as a FORM — a radius, not a chamfer (`00_07` HW.34, 2026-09-18) — and its value NOT SPECIFIED (`edge_bearing.exit_contact`).
- **Channel off the root axis (offset).** Past the play the **MOUTH** is a contact station — the bore's entry edge is the fulcrum — and it is the only one until the second wall is reached; the approach angle grows at **0.0048°/µm** of offset past the play on the shipped geometry (0.0039°/µm at the shallow end; 0.0143 on the retired placeholder; asserted against 3δ/(2a)), so at any swept excess it stays hundreds of times flatter than a 30–45° lead-in chamfer (1257× at the 5 µm reference): the rod never lands on a chamfer face, only where the chamfer meets the cylinder — a chamfer MOVES the edge, a radius removes it. The mouth reaction grows at 0.0028 N/µm on the shipped geometry (asserted against 3·EI·δ/a³) and the root then carries a static MEAN (the `68` secant column).
- **What this does to the two ratified verdicts of 2026-09-12** (⚖️ they stand; the GROUND is corrected beside them in canon). The ≥ 1.0 mm protrusion: the «earliest computed contact 5.21 mm from the root, so the tube must start 0.79 mm before the mouth» was a free-shape crossing, not a contact; under an offset the fulcrum is the mouth plane itself, so the geometry demands only that the tube COVER the mouth, and what a minimum beyond that must clear is the entry radius (NOT SPECIFIED) plus the axial position stack (the liner's own 27.6 µm thermal travel at 40 K and tolerances not in canon) — neither is in the model, so no floor is priced and `edge_bearing.liner_start.min_protrusion_from_geometry_mm` is `null`; the ratified value is carried from the CEM as a value the geometry cannot price below. The entry RADIUS: its ground strengthens — the approach is flatter under an offset than the 0.60° the drift picture read, on every geometry. ⛔ Declared ceiling, all of it: rigid frictionless wall, perfect clamp, offsets and plays swept and never measured; no notch factor and no contact model exists in this tree (⊕ 2026-10-14: a contact model of the EXIT exists since — script `91`, block below; the mouth's and the wire's notch factor still do not). (`mechanical/bus_mechanical.json` §`clearance_regime`)

🔬 **The liner↔wire FIT — derived 2026-09-12, and it is the number every other line of this section was standing on.** The 2026-09-11 direction verdict says the tube is TIGHT on the wire and the pair enters the bore as one body; the composite stiffness bound, every contact figure and the whole wear axis inherit that sentence, and until this block no interference for that pair existed anywhere — canon said so outright. Bounded the same way the seam input is, because both vendor bands are missing: at the ratified bore the window is **0.38 … 10.89 µm radial**, i.e. a **21.0 µm DIAMETRAL** budget for the tube bore and the wire OD **together** (21.3 at the pre-verdict bore = rod Ø). Ceiling = von Mises at the tube bore reaching PEEK yield 100 MPa at −30 °C, where the thermal term ADDS (PEEK is the outer member on this interface — the opposite sign to the liner-OD/bore interface, which is the confusion canon warns about); floor = the thermal loss at +40 °C, i.e. the fit merely stays a fit. ⛔ **Both tolerance bands stay `null` in the cache** — a quoted band sum wider than the 21.0 µm window is sorted around the ratified target; the tube is fitted hot regardless (`01_01 §3` step 4a, before enzyme functionalisation).

⚖️ **The nominal is SPECIFIED since 2026-09-18 — ratified (`00_07` HW.34): bore = wire − 11.41 µm (the window centre at bore = rod Ø), wall 0.15 so OD = ID + 0.30, fitted hot (`01_01 §3` step 4a), sorted around the same target if the two vendor bands overrun the window.** At the ratified bore the recomputed centre is 11.27 µm, +0.14 µm from the typed nominal (`interference_window.nominal_vs_window_centre_diametral_um`) — a typed number, not one that follows every re-run. Before the verdict the headline was that the nominal was SPECIFIED NOWHERE: canon froze the WALL, «ID 1.00» lived only in an open RFQ leg, and at that assumed bore the fit was line-to-line, so half the population would have come out with clearance. ⊕ Two consequences the same block derives, neither of them forecast. **(1) WHO carries the interference sets the direction of the play — and the first application of the nominal priced only one side (corrected the same day by an adversarial read).** At a fixed wall `play = play_zero + δ_bore − k·(δ_bore + e_wire)` with **k = 0.875** (`od_growth_eats_channel_play.k_od_growth_per_interference`): the play moves +0.125 µm per µm of bore under nominal and **−0.875 per µm of wire over nominal**, i.e. it is set mostly by the WIRE's OD band, which is NOT MEASURED. Carried by the bore it grows slightly across the window (25.05 → **26.4 µm** at the ceiling); with the bore AT the ratified nominal a wire over nominal eats it — **21.2 µm** at the ceiling (wire +5.2 µm radial), 30.4 µm at the floor (wire −5.3 µm). So the 25 µm zero-interference value the clearance table uses is **NOT a lower bound** and does not read edge bearing conservatively: under the equilibrium a smaller play lowers the rigid-wall end of the coaxial bracket (∝ g) and makes the mouth a station at a smaller channel offset — on the wire-carried ceiling row the mouth already carries a static root stress at 25 µm of offset (script `68` now sweeps all five window rows plus zero interference). (Before the verdict the same model read 25 → 15.3 — all δ on a wire over a bore = rod Ø.) The free-outer premise of the Lamé model is checked rather than assumed: the play stays open on every row, the wire-carried ceiling included. **(2) Friction on the wire is the SECOND capture.** The differential axial growth needs 3.30 N to restrain at 40 K (6.59 N at 80 K; at the ratified bore) and friction supplies it once µ·δ ≥ 0.031 µm — at the friendliest swept µ of 0.1 that is δ ≥ 0.31 µm to hold at all and 0.62 µm to lock the mid-section (⚠️ two thresholds, two verbs: this sentence attached the LOCK value to the HOLD verb until 2026-09-12, a 2× row-mix), a small fraction of the window. So the axial compression is incurred **whichever end is mechanically fixed**, and the ratified ground for one-end capture («20 yr of creep under sustained compression») discriminates only at the very FLOOR of the window, where the tube still slips and relieves. ⚖️ The verdict stands — it also carries retention and assembly — but its stated ground weakened, and which of the two regimes ships is set by a number no drawing carries. ⛔ Declared ceiling on all of it: creep/relaxation is modelled NOWHERE, so the true window is narrower on BOTH sides (the floor rises as grip decays, the ceiling falls because a sustained-stress limit is below yield); form error (tube ovality, wire out-of-round, bore straightness) is assumed zero, and a real pair spends part of the window on form before it spends any on size. (`mechanical/bus_mechanical.json` §`interference_window`)

🔬 **THE ENDURANCE BAND ENTERED THE MODEL 2026-09-12 — and one standing conclusion did not survive it.** `ENDURANCE_OVER_YIELD` was written as a BAND (0.40–0.50) in the constant's own comment from the file's first commit, while only its MIDPOINT ever entered the model; every SF scales linearly with it, so «the welded bare rod clears SF 2 for all six alloys» was a statement about one point of an unmeasured band wearing the clothes of a statement about the band. Swept (`§endurance_ratio_band`, the §2 free-cantilever column on the shipped span — 35 mm since ⚖️ `00_07` HW.26 G1):

| `σ_e/σ_y` | bare: ∞-life | binding `Ta` SF |
|---|---|---|
| **0.40 (model, ⚖️ ratified)** | **4 / 6** | **1.29** |
| 0.45 (former model point) | 5 / 6 | 1.45 |
| 0.50 | 5 / 6 | 1.61 |

🔴 **«All six clear SF 2» FLIPPED inside the band on the 23 mm span — and since G1 it is false on the WHOLE band** (`bare_infinite_life_for_all_is_invariant` = `true`, the invariant now being the negative). On the 23 mm span of the retired placeholder the band read 5 / 6 · 6 / 6 · 6 / 6 (Ta 1.96 / 2.21 / 2.45): at 0.40 `Ta` fell below the line, and since 2026-09-18 that end IS the model (⚖️ founder 2026-09-17) — the sweep measured the flip, the founder chose the end. The 35 mm span takes the flip away by taking the line away from every point of the band; ⛔ it describes the bare free cantilever only, a configuration the rod in its bore does not have (the note under §Mechanical above). ⚠️ Until 2026-09-14 this table carried a second column — the seam's break-even `k` at each ratio (0.624 / 0.554 / 0.499) and whether our 0.50 marker covered it, a tie of 0.001 at the friendliest end. That column was priced on the retired drift-picture stress and no seam `k` exists to sweep since (`weld_seam.break_even_k_not_derived_because`), so the band now measures the bare-rod verdict only. ⚖️ The founder chose the LOW end (0.40, 2026-09-17) — the block measures, it did not choose, and the band ends are the constant's own comment, not a measurement of our alloys.

🔬 **WEAR BOUNDED 2026-09-12, RE-STATIONED 2026-09-14 — the ground the liner actually stands on stopped being an assertion, and now stands at the contact the equilibrium finds.** ⚖️ 2026-09-11 replaced the liner's fatigue ground with WEAR, and for a day nothing computed it: every `wear`/`fretting` mention in script `55` was prose, one of them literally «The discriminating costs are NOT computed here», so «rated for 20 years» had no instrument while [`fmea_fmeca_register.md`](../../hardware/fmea_fmeca_register.md) `#21` — RPN 324, the top row from the severity sweep of 2026-09-18 until `#26` (504, frost-wedging) was entered on 2026-09-24 — asserted wear-through with none either. Same inversion as the seam input and the fit, third time: the specific wear rate of PEEK on Ti is in **no** canon row, **no** vendor answer and **no** experiment, so `wear_budget.specific_wear_rate_measured` stays `null` and the model prices the BUDGET. Chain, each link attackable on its own: **duty** = the sway-cycle count LOADED from script `62`'s real-wind cache (never retyped) × the slip per cycle at the station; **load** = the station's wall reaction from the contact equilibrium; **budget** = wear-through volume ÷ (load × duty). Two stations now, both from the solver: the **EXIT** under coaxial drag (reaction = drag − touchdown drag) and the **MOUTH** under a channel offset (a sustained reaction the reversing drag rotates the rod about; swept offsets, never measured). Shipped branch at its worst corner — the coaxial exit on the shipped geometry, µ 0.5, at the cycle ceiling script `62` writes (§HW.43):

| what the contact is | allowable `k` — a BOUND over the contact-compliance bracket | rigid-wall figure (bounds nothing) |
|---|---|---|
| flow-limited patch (PEEK at the tightest swept flow pressure) | **6.46 × 10⁻⁸** mm³/(N·m) | **3.87 × 10⁻⁷** mm³/(N·m) |
| worn in over the whole run (projected bearing) | **8.73 × 10⁻⁴** mm³/(N·m) | **5.24 × 10⁻³** mm³/(N·m) |

⚠️ Both ends are priced at the cycle CEILING script `62` writes — 20 yr of continuous sway at the high field reading of the sway frequency (0.74 Hz), an upper bound on first-mode cycles (§HW.43) — and scale as 1/N, so a lower count loosens both ends by the same factor and leaves the span below unchanged.

🔑 **Three findings, and the third is new with the station.** **(1) At the tight end the reaction CANCELS.** The area is flow-limited (`A = R/p_flow`) and the duty is `R·s`, so `k = h/(p_flow·s)` exactly — the flow-limited budget contains no contact force at all, which takes the chain's weakest link out of the binding half of the answer. Pinned in-run against the closed form, not described. **(2) The two REJECTED conformal branches demand a far stricter rate than the shipped liner against a RIGID wall — and NOT on the bound.** On the rigid-wall figures a 10 µm film needs a rate ~78× stricter at every swept friction and geometry where it touches down (⚠️ the factor differs between the two branches — read them per row); on the BOUND it does not, because at the Ti-bore stop the in-contact sliding is 6·r·t/L, proportional to the polymer's own wall, so a thick wall buys allowance and spends it on sliding in equal measure and the tight end stops depending on the wall (`branch_discrimination`, derived: films stricter on the rigid-wall figures `true`, on the bounds `false`). The wear axis re-earns their rejection only if the contact is rigid — which the unmeasured compliance decides. (⊕ 2026-10-14: `91` models the liner's contact, not the films', so this branch question stays open.) **(3) The coaxial in-contact sliding is a BRACKET with signed ends, and the budget is a BOUND over it.** Against a rigid wall the touched-down shape does not change with the drag, so the surface fibre at the exit does not rotate while pressed on the wall: a rigid point contact slides ZERO (`sliding_in_contact_um_rigid_kinematics`), and the rigid-wall rotation of **2.76 µm** per cycle between the ±wall states happens OUT of contact — it bounds nothing and is kept only as the rigid figure (`out_of_contact_rotation_per_cycle_um_rigid_wall`; until this afternoon it was quoted as «the ceiling»). Against the compliant polymer wall the exit yields and the rod rotates IN contact, up to the Ti-bore stop: **16.6 µm** per cycle on the shipped geometry (`sliding_in_contact_per_cycle_um_upper`). The bound takes that upper sliding with the upper (rigid-wall) reaction, so an allowable `k` below it keeps the wall whatever the compliance turns out to be; the mode at the rigid end is a normal load cycling 0 ↔ R with a landing at 0.061° — partial slip / impact fretting, a mode nothing here models. ⛔ Declared ceilings, all real: the budget's span is **13517×** and nothing in the tribology decides it — the CONTACT GEOMETRY does, and both stations are ours to decide (the entry radius carries no value; the exit carries nothing at all; the ratified protrusion decides which FEATURE of the tube meets the entry edge under an offset). Archard assumes GROSS slip; third-body debris in a 25 µm clearance, the titanium side of the pair (a bore EDGE at both stations) and the whole −30…+40 °C dependence are outside the bound. The second driver — the liner's differential thermal travel — is priced and comes out **~4 orders** below the sway sliding, so «the sway drag is the wear axis» is DERIVED. (`mechanical/bus_mechanical.json` §`wear_budget`)

🔬 **CONTACT EQUILIBRIUM, script `68` (2026-09-14) — script 55's DRAG contact picture was not an equilibrium, and 55's contact blocks are re-derived on this solver the same day.** `55` read the wall station off the free tip-loaded cantilever at FULL drag; under a tip load the deflection grows monotonically from the root, so the first station to reach the wall is the pad plane, where the tube ends flush, and from then on the drag is reacted there. `68` solves the unilateral contact instead (Euler-Bernoulli FE, active set on prescribed displacements, rigid wall — `lib.beam_contact`, one home), with controls that can fail: the closed form at the pad plane, the closed form at the mouth, the wall at element midpoints, a grazing row at two element sizes; an adversarial review reproduced every returned number with a continuum-analytic solution and a KKT certificate, and `55`'s cache is pinned equal to `68`'s on both ends of the coaxial bracket. ⚠️ **The unsupported gap comes from `Z1_INSERTION_MM` — since ⚖️ `00_07` HW.26 G1 (2026-10-12) the whole Zone-1 lock shank, the deep end of the lock's own insertion window; each row is given there AND at the window's shallow end** (the least insertion that keeps the lock's whole PEEK contact zone engaged; zero-interference play, bonded member, worst swept µ). Until G1 the table led with a placeholder row of 30 mm outside the window (8.04 · 5.74 · 8.04 · 10.52 · 56.3), retired with it:

| Zone-1 insertion (geometry) | root stress under drag, rigid wall = LOWER end, MPa | offset secant, MPa/µm | reversing-drag amplitude, max, MPa | pogo on the rod edge, MPa | upper end of the root stress at µ 0.5 (Ti-bore stop), MPa |
|---|---|---|---|---|---|
| 18 mm — shipped, the whole lock shank, gap 18 mm | **3.40** | **0.64** | **4.15** | **5.88** | **23.8** |
| 14 mm — lock window shallow end, gap 22 mm | **2.73** | **0.42** | **3.76** | **5.22** | **19.1** |

⛔ **Since G1 the shipped figure is the window's DEEP end (18 mm) — quote it as THE design figure, and the shallow end (14 mm) only beside it, as an assembly bound, never in its place:** the shallow end understates the shipped offset secant by a third (0.42 vs 0.64 MPa/µm). Until G1 the rule here was the opposite one — «quote the window as a PAIR, never one number», because nothing chose an end; the tracker broke it once (HW.34 «≈0.4 МПа/мкм», fixed 2026-09-26) by quoting the end that is now the WRONG one, so the trap outlives the rule.

🔑 **What moves.** (1) The rigid-wall root stress under drag sits far below the two stresses `55` used to price at that section (18.3 MPa nominal on the 6 mm column, 43.0 at the retired seam corner) — and it is the LOWER end of the root stress, the Ti-bore stop in the last column its upper (`coaxial_cap_bound`; a rigid wall prescribes the exit at the play, the polymer wall yields by R/k); ⛔ no seam `k` is re-derived from either end — the compliance that places the amplitude is unmeasured, a static offset puts a MEAN stress on the same section, and no mean-stress correction exists anywhere in the tree (the table IS the seam-acceptance input: the rigid-wall and upper-end columns bracket the coaxial amplitude, the secant is the mean per µm past the play, the reversing amplitude a rigid-wall figure). (2) Under drag the contact is the tube's flush END at the pad-plane exit — ring on ring, the form the ≥ 1.0 mm protrusion avoids at the mouth — and the exit radius is ratified only as a FORM (a radius, not a chamfer), its value NOT SPECIFIED. (3) Off-axis the mouth IS a contact station, so the protrusion and the entry radius keep a physical ground under misalignment. (4) **The peak-moment section is READ from the moment field of every solve since 2026-09-14, not asserted:** the root is the peak in every drag, offset and reversing-drag row; it leaves the root only on the lock-window geometry for a 9 mrad tilt about the MOUTH (the play is taken up on both walls and the rod bends between them) and for the pogo couple on the rod's end face (the couple applied at the exit exceeds the long rod's small root moment) — `peak_moment_section`, and the prose «in every configuration computed here» that stood in this cache was false on those rows. (5) The insertion is priced since G1 (2026-10-12): on the shipped geometry the offset secant is 0.64 MPa/µm — an order of magnitude below the retired placeholder's 5.74 — so the coaxiality number a drawing must demand can now be priced (HW.34's leg; the flip condition `01_01 §1.4` «Співвісність» wrote for exactly this case has fired); on the shipped geometry an off-axis pogo contact and a reversing drag over an offset both exceed the rigid-wall coaxial figure. ⛔ Ceilings: rigid frictionless wall (no liner compliance or contact pressure), perfect clamp, offsets · tilts · eccentricity swept and never measured, no liner creep, no P-δ. (`mechanical/bus_contact_equilibrium.json`)

🔬 **COAXIALITY PRICED, script `86` (2026-10-12 — ⚖️ exception to the crown pause, `00_07` HW.34).** The condition `01_01 §1.4` «Співвісність» wrote in advance fired with G1, but a loose allocation puts a static MEAN on the root, and until this block the tree had no mean-stress correction, so the flip could not be weighed. `86` adds one — Soderberg, 1/SF = σ_a/σ_e + σ_m/σ_y: the yield line, because the tree carries no ultimate strength per alloy, and more conservative than Goodman — over `68`'s cache. The mean is the worst static root stress over the six plays `68` sweeps (a rigid-wall upper bound under an offset), the amplitude the upper end of the coaxial bracket at the worst swept µ, worst play (the Ti-bore stop — ⊕ 2026-10-14: no elastic state of the exit reaches it in `91` — the unworn coaxial peak sits at the bracket's LOWER end, and exit wear saturates the peak once the mouth engages — so this amplitude is a conservative bound whose state is unidentified; the OFFSET regime's mouth station, which this block prices, `91` does not compute), σ_e the welded branch of `55`; the seam column is the knock-down `k` a weld must carry for the joint to stay on the SF-2 line. Shipped geometry, binding alloy Ta in every branch:

| allocation (total radial offset of the channel axis from the root axis, as the ISO 1101 zone) | static mean, MPa | wire SF | seam `k` needed |
|---|---|---|---|
| tight ⌀0.04 | **0.0** | **5.63** | **0.355** |
| loose ⌀0.10 | **14.7** | **4.54** | **0.388** |
| loose ⌀0.20 | **51.6** | **3.06** | **0.507** |

🔑 **The flip is real.** The loose ⌀0.10 branch raises the `k` the seam must carry by 9 % and leaves the wire at SF 4.5, while the tight one needs the WHOLE stack inside 20 µm — the flange member ⌀0.05 alone already spends 25. ⌀0.20 is where the price turns: `k` 0.507 crosses our own comparison marker 0.50 (`AS_PRINTED_DERATE`, a scale, not a measured seam). At the lock window's shallow end every branch is softer (`k` 0.285 · 0.303 · 0.356). The control holds the zero-mean SF against `55` on the zero-interference play (5.803 vs 5.80); the amplitude used is the worst play, which is why the tight row reads 5.63, not 5.80. ⛔ Ceilings: weld residual TENSION is a mean this file does not carry — it raises every `k` row, so a vendor `k` must be quoted with the post-weld treatment we ship; the seam row divides the mean by the WIRE's yield, and a lower heat-affected-zone yield raises it too; Soderberg, the upper-end amplitude and the rigid-wall mean are each the conservative choice; the machining and inspection cost of tightening is not priced. ⚖️ The founder chose ⌀0.10 on 2026-10-12 (verdict, price and weakest link — `01_01 §1.4` «Співвісність»; the split of ⌀0.10 between the stack's members is the open leg, `00_07` HW.34). (`mechanical/coaxiality_allocation.json`)

🔬 **THE EXIT CONTACT AS AN ELASTIC LAYER, read over the drag CYCLE beside a rigid wall at the same edge — script `91` (2026-10-14; the `00_07` HW.34 🤖 leg «контактна модель лайнера», free since the crown pause was lifted for measurements on 2026-10-13; rebuilt twice the same day after three adversarial passes — the first version read the root at full drag, the cycle's MINIMUM, and the second attributed effects against references the elastic solve itself had chosen).** Every line above stops at the same sentence — the contact compliance that places the root inside `68`'s bracket is measured nowhere — and so does `55`'s wear budget, whose contact area spans the flow-limited patch to the whole bore run (thousands apart, `k_span_ratio`) and whose in-contact sliding spans zero to the Ti-stop rotation. `91` models the contact itself: the 0.15 mm liner as an elastic PEEK layer on the rigid wire (bonded ⊥ frictionless — the hot-mounted grip is neither), the Ti channel as an elastic half-space, the gap of a rod displaced inside a bore plus the edge's rounding, the rod as `55`/`68`'s cantilever through the exact Mohr flexibility, solved by Polonsky–Keer on a DC-FFT and read along the drag PATH from touchdown to µ·F, every figure beside a RIGID wall touching at the same edge. Controls that can fail: the layer kernel against its confined-column and half-space limits, the kernel at two periodic paddings, Hertz on the half-space, a thin bonded layer against its Winkler asymptote, the Mohr flexibility against the FE touchdown drag, the rigid limit reproducing `68`, the pad couple reproducing `68` (d), the smallest radius's edge peak at two steps, a sharp edge inside the layer growing as ρ^(−½). Still a MODEL: still not measured.

| exit edge radius r, mm | cycle peak, MPa | rigid wall at the same edge (touchdown), MPa | at µ 0.5, MPa | rigid wall at µ 0.5, MPa | sub-cycle, MPa | rigid sub-cycle, MPa | sliding at µ 0.5, µm/cycle | of it, the compliance | edge peak, worst row, MPa |
|---|---|---|---|---|---|---|---|---|---|
| 0.05 | **3.409** | **3.404** | **3.118** | **3.282** | **0.292** | **0.122** | **0.31** | **68.5 %** | **90.4** |
| 0.1 | **3.414** | **3.411** | **3.010** | **3.167** | **0.404** | **0.244** | **0.40** | **51.5 %** | **73.5** |
| 0.2 | **3.427** | **3.426** | **2.794** | **2.938** | **0.632** | **0.487** | **0.59** | **33.7 %** | **59.6** |
| 0.3 | **3.441** | **3.440** | **2.577** | **2.709** | **0.864** | **0.731** | **0.77** | **24.6 %** | **53.6** |
| 0.5 | **3.470** | **3.470** | **2.141** | **2.252** | **1.329** | **1.218** | **1.14** | **15.3 %** | **47.0** |

(shipped geometry, flush exit with a rounding, zero-interference play, bonded liner, short-term modulus; the edge peak is the worst row over base and modulus at µ 0.5 on a 1 µm step; «of it, the compliance» is the share of the sliding a rigid wall at the same edge does NOT produce)

🔑 **What it says, claim by claim.** **(A)** The liner gives **0.27–0.40 µm** at full drag against a 150 µm wall. **(B) The cycle peak sits at or just after touchdown**: **3.409–3.471** MPa, ×**1.003–1.021** of `68`'s figure. On a rigid wall at the same edge it is F_td·L — the edge radius lifts it by ≤ **0.074** MPa over the flush value — and while the patch is tiny the give lifts it by ≤ **0.008** MPa more (`68`'s sign). **(C) On the loaded part the sign turns**: at full drag the compliance LOWERS the root by **0.11–0.21** MPa against the rigid wall at the same edge (the patch spreads inside the bore, and that outweighs the give) and deepens the sub-cycle touchdown → full drag up to ×**2.8** of the rigid one (table). **(D) The bracket's upper end is not an elastic state**: the peak climbs ≤ **0.136** MPa per µm of exit wear — an upper bound, for a worn wall that follows the rod's touchdown shape back to the mouth; a short scar climbs less — until the mouth engages after **50** µm, and from then on the touchdown is at the mouth and the peak SATURATES at **10.24** MPa; `68`'s 23.8 needs **33** µm of MOUTH wear on top (`wear_path`). **(E)** The edge peak, resolved at a 1 µm step, stays below the 23 °C tensile yield at every swept radius (table; the 20-yr relaxed modulus LOWERS it — the anti-conservative end for the peak) — ⊕ 2026-10-15 (`92`): COAXIALLY; at the ratified ⌀0.10's offset limit (50 µm) the exit edge's cycle peak is ×**1.23–1.29** this and passes the yield at r 0.05 mm (×**1.18**), so under an offset the exit radius has a floor of **0.1** mm (the smallest swept radius that holds — shipped shank, entry radius 0.2 mm, flush exit, zero interference); the elastic patch is ×**26–39** the flow-limited area `55` binds on. **(F)** The frictionless sliding — a kinematic ceiling — is at most **1/14** of `55`'s upper end; the compliance carries **15.3–68.5** % of it against a rigid wall at the same edge (table), the edge's own geometry the rest. **(G) A pogo contact off the rod axis moves the MEAN, not the amplitude**: over a reversing drag the extremes are the two touchdown values, where elastic = rigid, so for |e| = 0.5 mm the cycle runs −5.89 … +0.96 MPa — amplitude **3.426** MPa, exactly the on-axis one, mean shifted by **2.46** MPa (`68` (d) reproduced on the rigid flush wall); the exit section then carries ≈ the couple itself, **5.1** MPa nominal — a section the wire's notch factor may govern, which nothing computes. **(H)** Lumped full-stick friction (rigid in shear: an upper estimate) opens the cycle into a loop — at r 0.05 mm, **0.41** MPa against the frictionless sub-cycle 0.29 — and at r ≤ 0.1 mm moves the peak to full drag. **(I) The ratified countersink is CONDITIONAL**: the tip passes the bore line already at touchdown (**0.8–2.6** µm; at full drag 1.7–7.0), so a PEEK ring whose bore equals the channel's is the FIRST contact — PEEK on PEEK at the rod end — which no model here has. Only for a ring that clears the tip do the rows hold: the cycle peak ×**1.030–1.102** of `68`'s figure, the full-drag moment reversing beyond e ≈ **1.29** mm, the sub-cycle up to **5.39** MPa, the sliding up to a quarter of `55`'s upper end, the reaction up to +10 % over «drag − touchdown» (that bound holds for a flush sharp edge only). **(J)** A sharp Ti edge INSIDE the layer — the countersink's, the mouth's, past which the liner continues — is a punch edge: its peak grows ×**1.41** per halving of the step (ρ^(−½)); the flush sharp corner of the shipped CAD is outside the kernel, bounded only for a frictionless contact (under stick a clamped–free 90° wedge, ≈ ρ^(−0.35)). So a radius is wanted at every Ti edge the liner bears on — and the edge radius is a trade (a larger r lowers the edge peak, lifts the cycle peak a little and raises the sliding) that neither side makes binding on these numbers (coaxially — under an offset at the ⌀0.10 limit the edge-peak side binds, ⊕ in (E)): it is weighed by a measured wear rate and slip regime (the tribo test), not by this model.

⛔ **Ceilings — read before quoting:** linear elasticity (a peak above the flow pressure would be flagged against `55`'s 1·σ_y ⊥ 3·σ_y) · a FLAT uniform layer (the tube's curvature t/R ≈ 0.23 — the give may be ~14 % low — and its free end at the pad plane are not modelled; rows with r < t sit nearest that end) · bonded ⊥ frictionless and short-term ⊥ 20-yr relaxed modulus are brackets · friction only as the lumped full-stick bracket, the sliding frictionless · no thermal term (the cold liner's ≈ 1 µm radial pull-back moves `68`'s lower end by about the whole full-drag compliance shift), no P-δ, no wear in the contact solve · the countersink's PEEK ring and the exit closure element are not modelled · the pad couple's path between the two touchdowns, with the opposite wall in play, is not solved · the MOUTH is not computed. **No radius is proposed.** (`mechanical/liner_exit_contact.json`)

🔬 **THE MOUTH UNDER AN AXIS OFFSET — two elastic patches on the rod, read over the drag CYCLE beside a rigid wall at the same edges — script `92` (2026-10-14/15; the `00_07` HW.34 🤖 leg «контактна модель лайнера на ГИРЛІ»; rebuilt after two adversarial passes — the first version read the edge peak statically and on one shank, the mouth section's swing from two saturated offsets, and the cycle on nine drag points that missed its contact kinks; the second pass found the radius read at an offset the ratified tolerance excludes and the exit edge left unreported).** `68` (b): past the play a static offset of the channel axis makes the mouth edge a station, the root grows **0.64** MPa/µm against a rigid wall, and `68` warns that the edge may overload the PEEK at the larger offsets; `91` modelled the exit only, coaxially. `92` puts `91`'s elastic layer at both stations at once — the mouth edge on the offset side, the exit on whichever side the drag sends the rod — coupled through the rod's exact Mohr flexibility, solved as a Newton on the rod's pose at each window. The drag path carries every change of contact (a mouth lifting off, an exit touching down), found and bisected on the rigid same-edge model and taken at the kink and either side of it. **The decision frame is the ratified coaxiality ⌀0.10 (`01_01 §1.4` «Співвісність»): it admits offsets up to 50 µm; rows at 75–100 µm are the margin beyond it, not the ground of a verdict.** Controls that can fail: the rigid point model reproduces `68`'s offset and reversing tables (≤ 0.05 MPa); with no offset the two-window solve gives `91`'s exit row exactly (**2.794** / **2.938** MPa — the mouth window carries nothing there, so this controls the exit side only), and the exit edge's cycle peak gives `91`'s edge peak at every exit radius (within **0.9** %); with every contact compliance ×10⁻² the solve meets the rigid same-edge model to ≤ **0.13** % under no drag and under the drag either way (the drag toward the wall loads both windows — the coupling control); the edge peaks on two square grids, a third where they differ by more than 30 %, each verdict against the flow pressure the same on every grid. Still a MODEL; the offset is swept, never measured.

| offset past the root axis, µm | r_in 0.05 mm | r_in 0.1 mm | r_in 0.2 mm | r_in 0.3 mm | r_in 0.5 mm | root, elastic (r_in 0.2), MPa | rigid wall, same edges, MPa | `68` rigid sharp, MPa |
|---|---|---|---|---|---|---|---|---|
| 30 | **30.8** (×0.31) | **24.4** (×0.24) | **18.1** (×0.18) | **15.4** (×0.15) | **13.0** (×0.13) | **2.46** | **2.49** | **2.5** |
| 40 | **56.6** (×0.57) | **39.2** (×0.39) | **30.8** (×0.31) | **27.1** (×0.27) | **22.6** (×0.23) | **7.40** | **7.47** | **7.6** |
| 50 | **66.8** (×0.67) | **50.2** (×0.50) | **40.2** (×0.40) | **34.8** (×0.35) | **29.2** (×0.29) | **12.35** | **12.45** | **12.7** |
| 75 | **99.2** (×0.99) | **79.6** (×0.80) | **62.5** (×0.62) | **54.4** (×0.54) | **45.3** (×0.45) | **27.64** | **28.06** | **28.9** |
| 100 | **129.0** (×1.29) | **102.0** (×1.02) | **80.9** (×0.81) | **70.5** (×0.70) | **59.1** (×0.59) | **45.71** | **46.37** | **47.5** |

(the STATIC mouth-edge peak, MPa (×1·σ_y = 100 MPa, 23 °C tensile, `55`'s flow pressure at its lower constraint factor); shipped geometry, zero-interference play, bonded liner, short-term modulus, exit rounding 0.2 mm; the largest of the square grids)

| Zone-3 shank (mouth station), offset | r_in 0.05 mm | r_in 0.1 mm | r_in 0.2 mm | r_in 0.3 mm | r_in 0.5 mm | smallest r_in below 1·σ_y |
|---|---|---|---|---|---|---|
| 10 mm (22 mm), 50 µm | **66.2** (×0.66) | **49.7** (×0.50) | **40.1** (×0.40) | **34.8** (×0.35) | **29.4** (×0.29) | **0.05** mm |
| 10 mm (22 mm), 75 µm | **89.5** (×0.90) | **71.4** (×0.71) | **56.7** (×0.57) | **49.7** (×0.50) | **42.0** (×0.42) | **0.05** mm |
| 10 mm (22 mm), 100 µm | **108.5** (×1.08) | **86.7** (×0.87) | **69.2** (×0.69) | **60.4** (×0.60) | **51.2** (×0.51) | **0.1** mm |
| 14 mm shipped (18 mm), 50 µm | **74.7** (×0.75) | **58.4** (×0.58) | **46.6** (×0.47) | **40.8** (×0.41) | **34.5** (×0.34) | **0.05** mm |
| 14 mm shipped (18 mm), 75 µm | **105.3** (×1.05) | **84.4** (×0.84) | **67.1** (×0.67) | **58.5** (×0.58) | **49.4** (×0.49) | **0.1** mm |
| 14 mm shipped (18 mm), 100 µm | **131.5** (×1.31) | **104.1** (×1.04) | **83.0** (×0.83) | **72.5** (×0.72) | **61.2** (×0.61) | **0.2** mm |
| 18 mm (14 mm), 50 µm | **92.5** (×0.93) | **73.8** (×0.74) | **58.5** (×0.58) | **51.2** (×0.51) | **43.0** (×0.43) | **0.05** mm |
| 18 mm (14 mm), 75 µm | **134.1** (×1.34) | **106.2** (×1.06) | **84.5** (×0.84) | **73.7** (×0.74) | **62.0** (×0.62) | **0.2** mm |
| 18 mm (14 mm), 100 µm | **166.7** (×1.67) | **132.4** (×1.32) | **104.7** (×1.05) | **91.5** (×0.92) | **77.0** (×0.77) | **0.3** mm |

(the MOUTH-edge peak OVER THE DRAG CYCLE, MPa (×1·σ_y) — the decision quantity: located on the working grid along the path where the mouth carries load, refined at that drag; the Zone-3 shank is a placeholder (`00_07` HW.8.9) and moves the mouth station; the 50 µm rows are the ratified tolerance's limit)

| offset, µm | r_exit 0.05 mm | r_exit 0.1 mm | r_exit 0.2 mm | r_exit 0.3 mm | r_exit 0.5 mm |
|---|---|---|---|---|---|
| 0 | **91.2** (×0.91) | **73.7** (×0.74) | **59.9** (×0.60) | **53.6** (×0.54) | **47.0** (×0.47) |
| 50 | **117.5** (×1.18) | **94.3** (×0.94) | **76.0** (×0.76) | **67.1** (×0.67) | **57.7** (×0.58) |

(the EXIT-edge peak over the drag cycle by exit radius, MPa (×1·σ_y), entry radius 0.2 mm, shipped geometry — coaxially (`91`'s problem, the control) and at the tolerance's 50 µm limit)

| offset, µm | root: mean, MPa | root: swing, MPa | the path's two ends, MPa | wire at the mouth edge: mean, MPa | wire at the mouth edge: swing, MPa | mouth edge ÷ root |
|---|---|---|---|---|---|---|
| 0 | **0.00** | **3.43** | **2.94** | **0.00** | **1.81** | ×**0.53** |
| 10 | **1.37** | **3.43** | **2.94** | **0.61** | **1.81** | ×**0.53** |
| 26 | **3.69** | **3.29** | **2.94** | **1.49** | **1.92** | ×**0.58** |
| 28 | **4.23** | **3.03** | **2.36** | **1.11** | **2.42** | ×**0.80** |
| 30 | **4.77** | **2.76** | **1.77** | **0.73** | **2.92** | ×**1.06** |
| 35 | **6.12** | **2.10** | **0.28** | **−0.21** | **4.17** | ×**1.98** |
| 40 | **8.50** | **2.47** | **1.21** | **−1.15** | **5.42** | ×**2.19** |
| 45 | **11.33** | **3.30** | **2.69** | **−2.09** | **6.67** | ×**2.02** |
| 50 | **14.08** | **4.21** | **4.14** | **−3.05** | **7.90** | ×**1.88** |
| 60 | **21.34** | **4.27** | **4.14** | **−7.32** | **8.00** | ×**1.88** |
| 75 | **32.31** | **4.27** | **4.14** | **−13.89** | **8.00** | ×**1.88** |
| 100 | **50.61** | **4.27** | **4.14** | **−24.84** | **8.00** | ×**1.88** |

(the beam's swing under a reversing drag ±µ·F, µ 0.5, entry radius 0.2 mm, on the RIGID same-edge model along the path with its kinks; «the path's two ends» is what reading only ±µ·F gives. The elastic path, computed where it is cheap (0 · 10 · 50 · 75 · 100 µm; nearer the play a point costs minutes as the patches grow long), moves the root's swing by −2.9…+0.0 % and the mouth section's by −0.8…−0.3 % from 50 µm on and by +7.8 / +8.3 % at 0 / 10 µm; **5** of **882** elastic path points could not be represented by two end windows and are excluded, not replaced)

🔑 **What it says, claim by claim** (each asserted in-run or written from the rows). **(A)** The layer's give lowers the static root against a rigid wall at the same edges by **0.8–1.5** % on every row — `68`'s secant stands. **(B)** A larger entry radius lowers the static root and the static mouth-edge peak on every offset row; the beam's swing it moves by only **−4…+4** %, and not one way. **(C)** The drag raises the mouth-edge peak above the static one on every shipped-shank row (by **2–18** %). **WITHIN the ratified ⌀0.10 and at zero interference the mouth-edge cycle peak stays below 1·σ_y on every swept shank and entry radius — the worst ×0.93** (shank 18 mm, r_in 0.05 mm); BEYOND it, at 75–100 µm, it passes 1·σ_y on **9** rows (the largest ×**1.67**), and the smallest radius that holds at 100 µm is **0.1** · **0.2** · **0.3** mm for the mouth at 22 · 18 · 14 mm; below 3·σ_y everywhere. **(C′) Under an offset the EXIT edge is the more loaded one:** at 50 µm — on the shipped shank with entry radius 0.2 mm, the flush exit (no countersink) and zero interference — its cycle peak is ×**1.23–1.29** the coaxial, it passes 1·σ_y at r_exit 0.05 mm (×**1.18**), and the smallest swept exit radius that holds there is **0.1** mm — `91`'s «below the yield at every radius» is a coaxial reading. **(D)** Where the edges are rounded, the root's swing along the path is larger than its two ends give: the ends alone catch as little as **13** % of it (at 35 µm, where the swing itself is smallest); at the offsets `68` tabulates, its sharp-edge rows sit within **3** % of this path's swing. Against `86`'s threshold k ≥ **0.3883** (amplitude **24.51** MPa, the Ti-bore stop; mean **14.7** MPa, the worst play): at 50 µm and zero interference the root cycle runs at **13.90** ± **4.09** MPa on the shipped shank and needs k ≥ **0.064** (`86`'s formula, binding over its six alloys), **0.046–0.064** over the swept shanks — the threshold covers these cycles through its AMPLITUDE, not its mean: on the 18 mm shank the cycle midpoint, **23.89** MPa (static **20.63**), lies beyond `86`'s static mean. The cycle at the worst play and a pogo-pad couple on top of the offset are computed by no model. **(E)** From 50 µm on the wire under the MOUTH edge swings ±**7.90–8.00** MPa against the root's ±**4.21–4.27** (×**1.88**), around a mean of the opposite sign; the ratio crosses 1 at **30** µm (below it coaxially, ×**0.53**, and just past the play, ×**0.58** at 26 µm, ×**0.80** at 28) and peaks at ×**2.19** near 40 µm because the root's swing dips there (±**2.47**), not because the mouth section's grows. No notch factor under that edge is computed. **(F)** Bonded ⊥ frictionless base and the 20-year modulus move the static root by ≤ **0.03** MPa; the relaxed modulus lowers the mouth peak at the drag's ends from **46** to **33** MPa. **(G)** A mouth nearer the root makes the same offset dearer: the static root at 50 µm is **8.32** · **12.35** · **20.63** MPa for a shank of 10 · 14 · 18 mm.

⛔ **Ceilings — read before quoting:** linear elasticity (a flagged peak is not what the PEEK carries, and the root beside it stands on a layer that has yielded) · `91`'s flat uniform layer and its brackets · no friction at either patch, no pad couple, no wear · the zero-interference play only · the wire RIGID in the contact kernel — the section figures are NOMINAL, and the notch factor under either edge needs an elastic wire under the layer or the S-N plan's acceptance on the real part (the stations: `97`, below — the liner's end on the wire stays open) · the beam's swing on the rigid same-edge model (the elastic correction measured beside it, not applied, and not measured between 10 and 50 µm) · near the play, under the drag toward the wall, the rod nears a line contact along the channel that two end windows cannot represent · on a sharp entry at the smaller offsets the static peak scatters with the grid (its flow verdict does not) · the exit peak is read at entry radius 0.2 mm, on the shipped shank and the flush exit only · the offset swept, never measured · no verdict.

🔬 **THE WIRE UNDER THE LINER'S EDGES, script `97` (2026-10-16 — the leg «notch-фактор», `00_07` HW.34).** `91`/`92` keep the wire RIGID in the contact kernel, so their section figures are nominal (the ceiling above). `97` carries each point's contact pressure through the PEEK layer (h 0.15 mm, bonded ⊥ frictionless base) onto an ELASTIC Ti half-space (Navier modes of the layer, 6×6 boundary system; controls: the kh → 0 limit, the homogeneous closed form, the rigid-base limit against `91`'s Φ, two paddings, and `92`'s own window side against its rod — `92`'s sign, not `97`'s face assembly, which was checked by hand), adds the surface σ_ss to the wire's nominal fibre stress along `92`'s own drag path, face by face, and reads every surface point on `86`'s Soderberg line: drawn wire at the stations, the welded root with its seam knock-down `k` (`k_x` = the `k` below which the root keeps the lower SF). Baseline alloy; the root is `92`'s own (its 50 µm shank row reproduced to its rounding).

| base | offset, µm | root SF (k = 1 · 0.388) | mouth: worst SF (face) · lowest k_x | exit: worst SF (face) · lowest k_x | liner end, nominal SF |
|---|---|---|---|---|---|
| bonded | 0 | 102.7 · 39.9 | 179.0 (plus) · 1.74 | 172.5 (plus) · 1.67 | 165.1 |
| bonded | 30 | 75.3 · 39.0 | 106.5 (minus) · 1.98 | 164.2 (plus) · 11.77 | 100.5 |
| bonded | 35 | 77.3 · 44.7 | 82.1 (minus) · 1.14 | 165.4 (plus) · — | 81.6 |
| bonded | 40 | 61.4 · 37.1 | 60.8 (plus) · 0.97 | 166.5 (plus) · — | 64.9 |
| bonded | 45 | 46.0 · 27.8 | 47.7 (plus) · 1.09 | 167.4 (plus) · — | 51.4 |
| bonded | 50 | 36.5 · 21.9 | 39.2 (plus) · 1.19 | 168.2 (plus) · — | 42.5 |
| bonded | 75 | 20.8 · 14.9 | 26.3 (plus) · 6.72 | 166.2 (plus) · — | 28.9 |
| bonded | 100 | 14.5 · 11.4 | 19.9 (plus) · — | 162.8 (plus) · — | 22.0 |
| frictionless | 0 | 102.7 · 39.9 | 178.2 (plus) · 1.73 | 71.7 (plus) · 0.69 | 164.4 |
| frictionless | 30 | 75.3 · 39.0 | 100.7 (minus) · 1.74 | 63.4 (plus) · 0.75 | 100.4 |
| frictionless | 35 | 77.3 · 44.7 | 70.8 (minus) · 0.83 | 62.8 (plus) · 0.66 | 81.6 |
| frictionless | 40 | 61.4 · 37.2 | 53.2 (minus) · 0.72 | 62.4 (plus) · 1.03 | 65.0 |
| frictionless | 45 | 46.0 · 27.9 | 42.6 (minus) · 0.83 | 62.0 (plus) · 2.65 | 51.4 |
| frictionless | 50 | 36.5 · 21.9 | 35.5 (minus) · 0.93 | 61.8 (plus) · 29.29 | 42.5 |
| frictionless | 75 | 20.8 · 14.9 | 26.4 (plus) · 6.76 | 58.2 (plus) · — | 29.0 |
| frictionless | 100 | 14.6 · 11.4 | 19.9 (plus) · — | 56.3 (plus) · — | 22.0 |

(«—» = no face crosses: the root out-ranks the station at every `k`; `k_x` rounded down; ⌀0.10 admits offsets up to 50 µm, the rows beyond are the margin.)

🔑 **What it says.** **(A) What the contact through the layer does to the wire's tension depends on the base.** Read pointwise, the largest tension the contact alone puts on the wire beside a patch is **+0.55** MPa on the frictionless base (100 µm, mouth) and under **0.001** MPa on the bonded one, where at 75 and 100 µm it compresses the whole mouth station on the face every path point touches. Its weight on a station's worst 1/SF is largest — ×**3.66** — where the governing cycle's mean is compressive: `86`'s line counts a compressive swing as amplitude without crediting the mean, the conservative reading; where the governing mean is tensile it raises 1/SF by at most ×**1.07** (frictionless, 30 µm, SF 100.7). **(B) Inside ⌀0.10 the welded root stays the critical section for every seam with `k` < 0.97 on the bonded base** (lowest at the mouth, 40 µm — the contact weighs ×1.00 there: NOMINAL bending, the mouth section out-swinging the root as `92`'s swing ratio already showed) **and `k` < 0.66 on the frictionless base** (the exit, 35 µm — a contact swing about a compressive mean, (A)); the lowest drawn-wire SF under either edge inside ⌀0.10 is **35.5**. ⚠️ The frictionless threshold is an ESTIMATE, not a bound: it is contact-dominated (×3.03 on 1/SF), and two declared ceilings act on exactly that term in opposite directions — the half-space spreads the traction over the layer's arc, ≈ ×1.3 wider than the wire's, which alone would put it at **0.43–0.49** (amplitudes taken as additive, the nominal share at the point bounded over the face; out of phase it would sit lower still), and the exit patch sits ≈ 0.2 mm from the rod's end face, where σ_ss must vanish and the half-space does not know it (over-stated, not sized). Both thresholds are minima over a 5 µm grid of curves not monotone in the offset — between grid points they can sit lower. **(C) The liner's lower end on the wire stays OPEN, and it is the real candidate:** the edge of a full contact with an elastic mismatch, which `97` does not model — its corner stays below every modelled section while it concentrates the bare-side nominal by less than ×**1.05** (bonded, perfect seam, 35 µm) / ×**1.19** (frictionless, 50 µm), or ×**1.74** with `k` 0.388 (40 µm), and beyond that can out-rank them — a factor of the same order as the liner's own stiffening of the wire (×1.067), so not bounded here. **(D)** One drag point of 18 at 30 µm (bonded) is refused by `92` (a line contact two end windows cannot hold, at −0.0117 N of ±0.500 N, inside the path): that cycle omits it, so its root and station amplitudes are both lower bounds and the `k_x` there has no known direction.

⛔ **Ceilings:** a half-space for the Ø1.0 wire under a 0.15 mm layer (its curvature and the opposite face's free surface ignored; the traction's arc on the layer's radius, ×1.3 wider than the wire's — (B)) · `92`'s pressure solved with the wire rigid, one-way coupled · linear elasticity · the two bounding bases, no friction between them · σ_ss alone (the bonded interface's shear on the Ti and a multiaxial amplitude at a patch edge are not read) · ONE geometry — the shipped shank, zero interference (`92`'s sweep moves the root's required `k` with the shank) · the short-term PEEK modulus (the 20-year relaxed one is not run) · NO pad couple: pogo off the axis is not in `92`'s path, so the exit under eccentricity — where `68` (d) moves the peak off the root — is not here · the drawn wire's endurance on the BASELINE alloy: `86` binds on Ta, whose σ_e is far lower, and the SF here does not carry over · `86`'s line with the compressive mean not credited · the offsets a 5 µm grid · the liner end's corner, the seam `k` and its own stress field, and the vendor's tube grade and channel surface — inputs no script here carries. (`mechanical/wire_under_liner_edges.json`)

**Verdict** — 🟢 Monolithic bus (= anode alloy, HW.24-gated) resolves the Cu/Ti dichotomy: thermal
bridge minimized + Ti↔Cu galvanic joint eliminated + mechanically sound **with the bore liner**.
⚠️ «Sound with the liner» now carries a named precondition: the liner is only tight on the wire if
the fit lands inside the derived window. The nominal that puts it there is ratified (⚖️ 2026-09-18: tube
ID = wire Ø − 11.41 µm, hot-mounted, `01_01 §1.4`); whether the bought tube and wire bands fit the ≈21 µm
window is what the two RFQs answer — wider means sorting around the same target.
⚠️ And a second one since the contact equilibrium (2026-09-14): «sound» under DRAG stands on a coaxial channel, where the root lies in a bracket — the rigid-wall figure its LOWER end, the Ti-bore stop its upper, the contact compliance between them unmeasured — and the exit takes the drag (the binding alloy clears SF 2 at both ends, `binding_alloy_sf_shipped_at_*`); the static bending a channel off the root axis adds is a MEAN the tree cannot yet price; its magnitude no longer waits on the Zone-1 insertion (HW.26 G1, 2026-10-12: 0.64 MPa per µm past the play on the shipped geometry), only on the coaxiality number (HW.34) and a mean-stress correction. ⊕ 2026-10-14 (`91`, the text above NOT rewritten): the bracket's position is now MODELLED for the drag regime on an unworn wall — the cycle peak at the rigid end within a few per cent, the Ti-bore stop not an elastic state (exit wear saturates once the mouth engages) — and «the binding alloy clears SF 2 at both ends» holds per play on an unworn wall; the compliance is still measured nowhere.

⊕ **2026-10-14/15 (`92`):** within the ratified ⌀0.10 the mouth edge keeps the PEEK below its flow pressure over the cycle on every swept shank and entry radius, but the EXIT edge passes 1·σ_y at r 0.05 mm (×1.18 at 50 µm; below 3·σ_y) — under an offset the exit radius has a floor of 0.1 mm (shipped shank, entry radius 0.2 mm, flush exit, zero interference); and from ≈ 30 µm the wire under the mouth edge swings more than the root (×1.88 once the mouth stays loaded) — «sound» in that regime needs that section's notch factor, which no model here gives.
---

## HW.43 — The Bus Wire in Its Liner: Root Load and Pad Travel (script 102)

`87` (2026-10-17) left two conclusions open behind the liner: where between `86`'s own seam requirement and the
reading at the liner wall's ceiling the real requirement lies (HW.34), and how much of the centre-pad term (C) reaches
the pin. `102` is the model it named — the wire and the liner as a shear-lag pair with Coulomb slip (`55`'s grip per
tolerance part and μ). With the flange shifted δ from the anode, the liner collects the force at its held top over a
slip zone, the pair sticks below it as a composite, and the wire carries the force through the bare run to the weld
root. The wire's own stretch is capped with the force — at most 12.8 – 29.9 µm at the wall's cap, by alloy — so the
rest of any shift goes into the pad's travel: the liner only chooses how much of δ the seam takes. A reversal follows
the virgin curve doubled (Masing); the seasonal heat enters as a slow preload on the relaxed liner with the sway cycle
on top. The share of `87`'s shift the wood imposes on the anchor is the free variable: 0 with the anode not bonded, 1
with all of it imposed — the bound; the sleeve is 12× stiffer axially than the wire at that bound and 4.0× at the first micron, so the
wire adds between a twelfth and a quarter to the anchor's stiffness and does not set the share. An independent finite-element solve reproduces
the closed form and its Masing loop to 0.2 %; the stick compliance the closed form leaves out makes it overstate the
force and understate the pad's travel — by up to 6.3 % and 28.4 % at a 5 µm shift on the tightest grip, by at most
1.0 % at 30 µm — the conservative side for the seam and the pad's travel (the CTE thresholds below move with it by a
fraction of a ppm/K).

**The seam (HW.34).** `86`'s requirement with the root's axial force on top, rounded up. Adverse corner: the tightest
part at μ 0.4, `87`'s upper-whisker shift reversed; gentle corner: the nominal part after creep at μ 0.1, the median
shift one-sided.

| alloy | `86` alone | gentle, shares 0.25 – 1 | adverse, ¼ | adverse, ½ | wall's ceiling (`87`), binds from share |
|---|---|---|---|---|---|
| Ti-15Zr | 0.1331 | 0.16 – 0.19 | 0.31 | 0.42 | 0.51 from 0.75 |
| β-Ti-13Nb-13Zr | 0.1408 | 0.17 – 0.20 | 0.31 | 0.42 | 0.54 from 0.83 |
| Ti-6Al-4V | 0.1441 | 0.17 – 0.21 | 0.34 | 0.47 | 0.55 from 0.72 |
| Ti-6Al-7Nb | 0.1493 | 0.18 – 0.22 | 0.35 | 0.48 | 0.57 from 0.74 |
| CP-Ti Gr4 | 0.272 | 0.32 – 0.39 | 0.63 | 0.86 | 1.03 from 0.74 |
| Ta | 0.3883 | 0.47 – 0.58 | 1.03 | 1.37 | 1.48 from 0.59 |

The requirement sits above `86`'s own k at every share above zero, even on the gentle corner, so the vendor's seam k
cannot be accepted against 0.388 on Ta in any corner with the wood imposing anything. Once the ceiling binds, the
liner wall reaches its 23 °C yield every sway cycle — the insulator, not only the seam (the yield and the grip are 20 °C
figures, the sway source day a January one). Above k 1 not even an unweakened wire keeps SF 2: Ta is past it at a
quarter of the shift on the adverse corner. A seasonal preload at the hot edge (55 °C) on the relaxed liner adds
15.1 – 48.4 N of mean on Ta (gentle to adverse grip) — up to 91 % of the wall's 23 °C yield, where creep is not
modelled, so the upper end is a ceiling — and lifts its requirement to 0.64 with no sway at all.

**The pin (sway).** At the share-1 bound, 67 – 88 % of a sway shift reaches the centre pad on a part that grips and
92 – 99 % on a part at the window floor — 6.2 – 9.2 % of the pin's minimum preload.

**The pin (heat) — on the free-sleeve reading the centre pad leaves the window.** With the PEEK sleeve growing freely
(the wood holding nothing), it outgrows the Ti wire by 0.69 – 1.23 µm/K (the gap alone ⊥ the gap plus the Zone-3
shank, which is the span while the shank sits in clearance). At the cold edge the pad protrudes at least 20.0 µm on
every part and grip — the tightest part at μ 0.4 included — against `90`'s isothermal L1 margin to the window's upper
edge of 11.8 – 14.8 µm; at the hot edge a part at the window floor grips with nothing and its pad recedes 18.4 – 43.1 µm
against 17.4 – 19.3 µm to the lower edge, past the larger margin on 3 of 4 readings; on the shipped span at the capsule edge even the tightest grip
recedes 26.3 µm, past both. The smallest protrusion
comes from a reading below the wall's cap, and a capture or wall that gives way moves the pad further. **The premise decides it** (📌 2026-10-20 — not for pricing a fix: within the model the wood only shortens the thermal travel, with the flange on the bark and on a rigid Zone-3 fit (the placeholder shank) alike, `103`,
§«How Much of the Stem's Shift Reaches the Anchor?»): a bonded anode and a flange on the bark make the span follow the wood's own radial
expansion instead, and the cold result then holds while the span's effective CTE stays above 25.2 – 25.8 ppm/K by
reading (38.1 – 39.1 if a Zone-3 fit locates the flange and only the gap follows the wood), the hot one above
25.9 – 31.3 — against 47 for free PEEK, and each threshold rounded up; the wood's radial CTE is not in `102` (📌 `103`
takes xylem's). So
where L1 keeps the outer pins in their window — isothermally; at the same edges the radome-leads reading breaks it
(`90`) — it keeps the centre one only if the wood holds the span below those thresholds.

⚠️ **Bounds.** The share at any bond state is not computed here (the wood–anode coupling is not in `102`) — for the
sway and for the heat alike; 📌 `103` computes it per state, conditional on the bark's bearing, the anode bond and the sleeve's tie — its depth and stiffness. The compressive half is taken symmetric (PEEK's compressive yield and the capture's push-out are
not in the tree). Not modelled: a tie of ice or resin in the wet gap or channel; the capture's strength and form (taken
as seizing the liner's top); the wall's creep under a sustained load, its fatigue as an insulator and its plastic strain
past the cap; the liner's own expansion over its run (it would lower the force and raise the pad's travel a little);
the weld's residual tension and HAZ; a temperature profile along the span (one temperature for the whole span — the
capsule's is a ceiling); the anode face moving inside its own press-fit; the placeholder Zone-3 shank (HW.8.9). The
sway shift is one January day of one smaller pine (`87`) — a storm twice as windy roughly quadruples it. Cache:
`mechanical/wire_liner_shear_lag.json`.

---

## HW.43 — How Much of the Stem's Shift Reaches the Anchor? (script 103)

`102` leaves the share of the stem's shift the wood imposes on the anchor free, and prices the heat on the PEEK
sleeve's free growth. `103` takes the share per bond state from what canon says holds each place the wood touches the
anchor (`01_04 §2`, `§3.1`, `§3.3`): the anode, a Ø11 gyroid in the Ø15 channel, free until the callus fills it and
bonded after; the sleeve, snug in the same channel and later tied by a callus ring that grows over Zone 2's outer edge;
the flange, seated on faced dead bark that rises against it as the stem grows. One solver carries every state — the
sleeve as two segments on three nodes, with the bark bearing at the flange, the tie below it and the anode bond at the
anode's depth — and controls hold it to the closed forms of the simpler states. The anode bond is a shear lag in both
radius-normal planes at once (G_eff = √(G_LR·G_RT): about 24 MPa for green *P. radiata* ⊥ 234 MPa for *P.
sylvestris* at 22.8 % MC); the seam at each share is `102`'s own closed form, held to `102`'s cached grid by a control.
No stiffness constant here is a green value for *P. sylvestris* (Bounds).

| state | what reaches the anchor | share of the sway shift |
|---|---|---|
| 1 — anode not bonded | nothing at the anode end: 2 mm of radial clearance around the gyroid | 0, unless the channel grips the sleeve or ice fills the gap |
| 2 — anode bonded, sleeve free below the bark | the anode bond, the sleeve and the bark bearing in series | 0.00 – 0.10 at the air-dry bark readings; the anode bond caps it at 0.72 (stiff) ⊥ 0.15 (soft) |
| 3 — a rigid callus tie of the sleeve, the bark bearing acting too (canon's mature state) | the segment above the tie follows the wood through the bark, the one below through the anode bond | 0.02 – 0.71 over the tie's depth with no bearing, up to 0.72 ⊥ 0.30 at a rigid bark |

**The tie's depth is an axis.** Callus grows from the cambium outward, and the stem's growth carries new wood along the
sleeve toward the flange, so the tie sits anywhere between the flange and the install-day cambium — 11.3 ⊥ 24 mm below
the flange seat on the thin ⊥ thick bark, the deepest it can be.

**The heat: within the model, the wood only shortens the centre pad's thermal travel.** Every fit of the anchor is read
by one rule — bonded over its run (`lib.mechanics`), the adverse end of its thermal reading, since the interference sits
on the barbed zone only — so the anode's 18 mm shank in the sleeve's bottom grows at 9.36 ppm/K, not at the Ti's 8.6.
Holding the span lowers its effective CTE, but over every state, bond, bearing and tie depth the model spans never below
12.05 ppm/K (a rigid bark and the deepest tie at the stiff bond) — above the 8.6 ppm/K at which the pad's travel
changes sign on `102`'s span, and on `102`'s own wire–liner pair the travel never falls as the shift grows (a control
checks it). So, with the wood side at xylem's CTE, the free-sleeve reading `102` prices is the adverse end of the pad's
thermal travel in every state, and a fix priced against it holds whatever the bond and the tie — while xylem's radial
CTE stays above 5.95 ppm/K: below it the deepest tie at a rigid bark can reverse the travel, and the one reading taken
is 7.9. A channel grip — a deeper tie of the same kind, not computed — reaches the sign change only within 0.75 mm of
the anode face (a rigid tie 31.25 mm below the flange seat, at a rigid bark and the stiff bond), and even then, with the
wood side at xylem's CTE, the CTE cannot fall below 6.20 ppm/K, the span following the wood outright, so a reversed
shift per kelvin stays under 6.3 % of the free sleeve's. Not in the tree, and of unsettled sign — able to lengthen the travel or to reverse it further: the bark's own
thermal and humidity strain, its growth preload and frost. Whether the wood brings the pad back inside L1 stays open: in state 2, not while the bearing
stays below 10091 N/mm (cold) ⊥ 4984 N/mm (hot) at the stiff bond, and never at any bearing at the soft one; in state 3
at the stiff bond, the pad stays out only while the tie sits deeper than 9.5 mm (cold) ⊥ 14.4 mm (hot), even with no
bearing, and at the soft bond with no bearing it stays out at every depth. Here the flange is located by the bark; a
Zone-3 fit locating it is the paragraph below the seam.

**The bearing settles state 2 only.** The bark enters state 2 only as the bearing's stiffness k_F = E·A/t over the
flange's annulus (A = 520.8 mm²) — what a flange mock pressed on faced bark measures as force over settlement. No
green value of the bark's modulus was found, and the two air-dry readings — 0.87 MPa (giant sequoia, whole bark) and
18 MPa (*P. taeda* outer bark, read off a load cell's travel) — give 21 – 1126 N/mm and bound the green bearing in
neither direction: green bark is softer than air-dry, and the paper's own wood cube suggests the load-cell reading
understates thin blocks by under 2×. The share rises with the bearing and the bond, so each state-2 conclusion has a
bearing below which it does not happen at the stiff bond — hence at any bond — and, where the soft bond reaches it, one
above which it happens at any bond:

| what happens in state 2 | not below (stiff bond) | at any bond above |
|---|---|---|
| the share reaches `102`'s 0.25 row | 3927 N/mm | never |
| Ta's seam passes k 1 on the sway alone (adverse reversed corner) | 3604 N/mm | never |
| Ta's seam passes k 1 with `102`'s hot preload (adverse reversed corner) | 970 N/mm | 4137 N/mm |
| the centre pad's hot conclusion flips | 4984 N/mm | never |
| the centre pad's cold conclusion flips | 10091 N/mm | never |

In the mature state the tie's depth and stiffness, the anode bond and the bearing decide together, and of these only
the bearing can be measured on a log — where it no longer settles anything alone.

**The seam.** Ta on the adverse reversed corner needs 0.3883 on the sway alone in state 1 and 0.64 with `102`'s seasonal
hot preload, which is the anchor's own mismatch and acts in every state; in state 2 at the air-dry bark readings, up
to 0.72 on the sway alone and up to 1.03 with the preload; in state 3 at the stiff bond, at least 0.93 on the sway alone
and 1.18 with the preload whatever the tie's depth and the bearing (0.48 ⊥ 0.79 at the soft one) — past k 1 with the
preload at the stiff bond, which is the moist-Scots-pine end of G, an upper end for green wood. Ti-6Al-4V needs at most
0.55 at any share — the same as `102` gives at a share of 1, since the liner's wall caps it.

**A Zone-3 fit locating the flange.** Canon puts the Zone-3 shank in the sleeve under interference (Ø11, `01_01 §1`),
while the CEM still carries a Ø9 placeholder in clearance (HW.8.9); `103` reads the placeholder and takes the fit as
rigid — a fit that slips gives back the bark reading — and bonded over its 14 mm by the same rule as the anode's: the
Ti shank with the PEEK around it grows at 9.76 ppm/K, so only the 18 mm gap below it is PEEK, and the effective CTE is
read on that gap in `102`'s convention (the shank's run at the Ti's 8.6). The sway share falls — state 2 capped at 0.60
(stiff bond) ⊥ 0.10 (soft), state 3 with no bearing 0.02 – 0.59 — and the heat keeps its direction: over every state,
bond, bearing and tie depth the gap's CTE never falls below 14.73 ppm/K, above 8.6 ppm/K, where the pad's travel changes
sign on the gap-only span. So within the model, with the wood side at xylem's CTE above the same 5.95 ppm/K, the free
sleeve is the adverse end of the thermal travel under either premise — the deciding corner, a rigid tie at the thick
bark's install-day cambium, sits below the shank, so the two premises share that margin. On the fit the free gap grows
at 47.9 ppm/K, 0.9 above `102`'s gap-only reading — about 2 % more travel per kelvin — so a fix priced on that span
carries the offset. The gap following the wood outright gives 4.33 ppm/K, a reversed shift per kelvin under 10.9 % of
the free sleeve's. At the stiff bond the wood brings the pad back inside L1 more readily than on the bark: in state 2
the cold conclusion does not flip below 3324 N/mm and the hot one below 3223 N/mm, and never at the soft bond; in state 3
with no bearing the cold one holds only while the tie sits deeper than 23.8 mm on the capsule-edge reading — the
deepest tie is 24 mm, and at the anode's full bond depth not even there — and at no depth on the cambium reading, the
hot one at no depth (a hot threshold exists on the capsule-edge reading only — at the cambium the free gap does not
leave the window hot), while at the soft bond both hold at every depth. On the seam `102`'s hot preload on the fit's span is 35.9 N on Ta against 48.3 N on the 32 mm one, yet
Ta still needs 0.55 in state 1 — not acceptable against 0.388 at a share of zero — and its seam passes k 1 with the
preload in state 2 not below 1940 N/mm at the stiff bond; in state 3 it needs at least 0.93 on the sway alone and 1.18
with the preload at the stiff bond (the deepest tie sits below the shank, and with the preload the wall's cap binds),
0.48 and 0.68 at the soft one.

⚠️ **Bounds.** The bark's growth preload against the flange and its humidity strain are not in the tree, and the span's
wood side is taken at green pine xylem's 7.9 ppm/K. Frost is not a coefficient, and even its sign at a tie in the
wound's reaction zone is not settled (green-wood specimens frost-shrink, heat-killed xylem swelled); ice in the anode's
gap ties it at the cold edge with an unknown strength, and a channel grip is a deeper tie of the same kind, not
computed. G is a green-radiata ⊥ moist-Scots-pine bracket (the radiata values carry one significant figure) and the
anode bond our order-of-magnitude form with a bracket on its log term; for the slow heat the PEEK is relaxed and the
bark and wood are not. The tie is rigid — on the Ti-reinforced run of a Zone-3 fit a bound further still from the
wood's own stiffness. Every fit is read bonded over its run, the adverse end; with the anode's shank held at its end
(Ti alone) the CTE floor is 12.26 ppm/K on the bark and 15.11 on the fit, and the span following the wood outright
gives 6.63 and 5.10. The heat's direction stands on one reading of xylem's radial CTE (Sevanto et al. 2005's Scots
pine mean). The Zone-3 reading stands on the CEM's placeholder shank and a rigid fit, whose holding force is
not in the tree; it re-runs when HW.8.9 fixes the shank's diameter and length. Cache: `mechanical/anchor_wood_share.json`.

---

## HW.43 — What Each Remedy for the Centre Pad's Travel Buys and Costs (script 104)

`102` leaves the centre pad outside `90`'s isothermal L1 margin on the free-sleeve reading, and `103` shows that within
its model the wood only shortens that thermal travel. `104` prices each remedy, on both of `102`'s spans, in
micrometres against the margin and in load on the bus wire's seam, on `102`'s own wire–liner pair (a control
re-derives `102`'s cached pad travel to 0.005 µm) and on every grip of `102`'s window — the loosest, a part at the
window floor relaxed at μ 0.1, is not among the four `102`'s heat reads, so the cold protrusion on the 18 mm span is
35.5 µm, not 34.0. The Zone-3 shank there is read bonded to the PEEK over its run (the fits' one rule; with it as Ti
the need is 22.9 µm instead of 23.7).

**Two readings, both priced.** *Held:* the seasonal edges alone — the whole travel in state 1, the anchor's first
winter before the callus, where `103`'s share is 0 (unless ice in the gap ties the anode at the cold edge — not
bounded). *Held + sway:* once the wood holds the anchor, the stem's sway rides on the seasonal position — unlike `90`'s
daily swing, which lies inside the seasonal edges `90` already judges — so the window takes their sum: the held part
at a state's effective CTE (the wood shortens it) and the sway at the same state's share, both read off `103`'s
(CTE, share) front. The sway's increment is bounded by its own shift — the pad travel is the shift less the wire's
stretch, which never falls as the shift grows — so the sum is an upper end: the coincidence of the seasonal edge with
`87`'s shift at its high end.

| span | held (high ⊥ low stack) | held, radome leading | held + sway (`87`'s median ⊥ upper whisker) | held + sway, radome leading |
|---|---|---|---|---|
| 18 mm — the Zone-3 fit, canon's Ø11 under interference | 23.7 ⊥ 20.7 µm | 37.3 µm | 24.8 ⊥ 37.8 µm | 38.4 ⊥ 51.4 µm |
| 32 mm — the placeholder, the shank in the gap | 51.1 ⊥ 48.1 µm | 64.7 µm | 51.4 ⊥ 60.4 µm | 65.0 ⊥ 74.0 µm |

Left as is, the stroke leaves the window on both sides on the 18 mm span — 1.7 % of the stroke past 70 % and 0.6 %
under 50 % held, 2.7 ⊥ 2.2 % with the upper-whisker sway — and the low side is the canon's loss-of-force direction
(`02_02 §3.5`, «Z-стек задовгий»).

At `103`'s largest share the sway alone swings ±20.3 ⊥ ±41.3 µm on the 18 mm span (±22.4 ⊥ ±45.5 on the 32 mm one) —
past L1's smaller margin at both shift readings — so on the held + sway reading no remedy that acts on δ closes the need
by itself: the held part cannot go below zero.

What each remedy buys — the spare it leaves, a shortfall in parentheses:

| family | remedy | 18 mm: held · radome leading · + sway (median ⊥ upper whisker) · both (upper whisker) | 32 mm: held · + sway (upper whisker) |
|---|---|---|---|
| L1 residual | bayonet hard-stop (L2 — `52`'s CNC member 0.10 → 0.05 mm), +41.0 µm | 17.3 · 3.7 · 16.2 ⊥ 3.2 · (10.4) | (10.1) · (19.4) |
| | L2 with a 0.05 mm spacer step, +56.0 µm | 32.3 · 18.7 · 31.2 ⊥ 18.2 · 4.6 | 4.9 · (4.4) |
| | the CNC member at ±0.05 mm by a tolerance class | as L2, if the member is machining tolerance | as L2 |
| | a 0.05 mm spacer step ⊥ none at all, +8.0 ⊥ +12.0 µm | short | short |
| pin's window | a longer stroke, the deck re-spaced to keep 60 % nominal | from 1.637 mm · 1.773 · 1.648 ⊥ 1.778 · 1.914 | from 1.911 mm · 2.004; with L2 1.501 · 1.594 |
| δ itself | the PEEK run's length | gap ≤ 5.6 mm — the Zone-3 shank ≥ 26.4 mm — held only | run ≤ 5.8 mm, the shank cut to 4.3 — held only |
| | the PEEK run's effective CTE | ≤ 21.5 ppm/K (22.1 if the grade fills the shank's composite too) — held only | ≤ 16.3 ppm/K — held only |

**The window side is one member, and it lifts the outer pad too.** `52`'s residual is rss(CNC member, spacer
half-step), carried to the micrometre as `52`'s cache and `90` carry it. The CNC member dominates: the spacer step
alone cannot reach the 18 mm need even at zero, while the bayonet hard-stop halves the member as `52` models
deterministic engagement (L2, already in `52` and `90`). A tolerance class reaches the same number only if the member
is machining tolerance — `52` names it engagement, whose play a hard-stop removes. Every window remedy moves `90`'s
margins for the outer pad as well (L2 lifts its radome-leading upper margin from −1.8 µm to 39.2). A longer stroke
stands on no part of `52`'s residual; it moves the margins by the window's half-width only if the deck is re-spaced to
keep the nominal at 60 % — at today's gap −0.5 ⊥ +0.7 µm per µm of stroke. L2 with the finer step closes every reading
on the 14 mm placeholder shank, the worst — the radome leading with the upper-whisker sway — by 4.6 µm, which holds while
the shank stays above about 11.7 mm: the held reading's slope with the shank, 2.0 µm per mm, carried over as an estimate,
since `103`'s front moves with the shank too.

**The seam does not choose between the δ routes — closing the need does.** Where the wire–liner pair stays as it is — both CTE routes
and the length route on 18 mm — it fixes the shift per kelvin and with it one hot preload, 20.9 N on Ta; the length
route on 32 mm cuts the shank and the liner run with it and lands at 22.3 N — against 35.9 N today on the 18 mm span and
48.4 N on the 32 mm one. `86`'s seam requirement on 18 mm with no sway falls from k 0.547
to 0.467, and with `103`'s sway on top at its least state-3 corner on a stiff bond from at least 1.187 to 1.120 — the
sway alone asks 0.931 there, so Ta's seam stays past k 1 either way; at `103`'s caps the liner wall binds and the δ
routes change nothing (Ta 1.471), the length route even raising some capped corners slightly (its longer liner run
grips more); on Ti-6Al-4V no corner passes 0.528. The window side leaves the seam where it is.

**Sensitivity, and what is not priced.** The placeholder shank (HW.8.9) at `92`'s 10 ⊥ 18 mm moves the held need on
the 18 mm span to 31.7 ⊥ 16.0 µm — at the short end, past L2's radome-leading and upper-whisker spares. Not priced: the
pin's own height — the datasheet's ±0.127 mm on its travel, which, as far as it is the plunger's free length, moves the
compression at a fixed gap by its whole size, past every spare here — has no member in `52`'s chain (HW.8.7).

⚠️ **Bounds.** No grade's CTE or modulus is in the tree: the CTE route is a threshold, and a filled grade also moves the
Zone 1↔2 press-fit (`50`/`51`/`56` and its ratified band) and the liner's thermal grip. Whether the hard-stop acts under
branch (а) is `52`'s rerun at the root move. A longer pin's own free length moves `90`'s thermal term (up to 1.1 µm per
mm of extra free length at the far edge). The gap has other duties — it is the thermal break G1 set at 18 mm (⚖️
2026-10-12, `54`'s frost gate) and the wire's unsupported run — and a shank beyond `92`'s 10–18 mm sweep loses that
script's contact results: the length routes price length only. The held + sway sum is the coincidence of the seasonal
edge with the sway at its high end, and both readings carry `103`'s bounds: the wood «only shortens» while xylem's
radial CTE stays above 5.95 ppm/K, and the bark's own strain, growth preload and frost are out of the model. Cache:
`mechanical/pad_travel_remedies.json`.

---

## HW.26 — How Far Can the Bus Wire Twist? (script 101)

Once HW.8.9 makes the Zone-3 shank a fit, an event torque on the flange (the bayonet, a branch, an animal) reacts
through the Zone-1 shank's friction too, and slip under force means rotation without a bound — and with it the bus
twists (`01_01 §4.3` C, «Межі присуду»). `101` gives the angle and the torque at which the Ø1.0 wire's surface first
yields, per candidate alloy, over the run from the weld root to the pad plane: 17 mm of bare wire in the PEEK gap
plus 18 mm under the liner, 35 mm in all (`55`'s spans, from the CEMs; the Zone-3 shank length in them is still a
placeholder, HW.8.9). Two readings make each range: von Mises ⊥ Tresca, and the run twisting as bare wire (which needs
a capture that clamps the wire itself) ⊥ the liner bonded to it as a parallel tube (the stiff bound, which pushes
more of the angle into the bare run). Angles and margins are rounded down, torque ranges outward.

| alloy | σ_y, MPa | elastic below | yield torque, N·mm | × the wind's rotation |
|---|---|---|---|---|
| Ta | 345 | 9.7 – 11.5° | 33.8 – 39.2 | ≥ 62 |
| CP-Ti Gr4 | 480 | 24.0 – 28.6° | 47.1 – 54.5 | ≥ 152 |
| Ti-6Al-4V | 880 | 41.3 – 49.2° | 86.3 – 99.8 | ≥ 262 |
| Ti-6Al-7Nb | 850 | 41.9 – 50.0° | 83.4 – 96.4 | ≥ 266 |
| Ti-15Zr | 950 | 49.0 – 58.5° | 93.2 – 107.7 | ≥ 311 |
| β-Ti-13Nb-13Zr | 900 | 57.5 – 69.2° | 88.3 – 102.1 | ≥ 365 |

**What turns the wire's top gives way first.** The wire's top end is the contact pad, and nothing in the tree holds
it but the PEEK liner, captured at the pad plane by a feature not yet designed — a series, so the wire twists to its
yield only if every link carries its yield torque (in-silico §When Modifying #44). The liner tube first yields in
torsion at 13.7 – 15.9 N·mm, below the wire on every alloy; its grip on the wire carries 30.3 – 121.1 N·mm at the
nominal fit (μ swept 0.1 – 0.4, 20 °C) and no less than 19.7 N·mm after creep, so the tube goes before the grip —
except at the fit's floor (+40 °C), where the grip is zero and slips at once. With the tree's holder an unbounded
event slip therefore yields or slips the liner, or slips the capture. That is not a soft outcome: the liner is the
channel's insulation through the cathode (`01_01 §1.4`), in the pad plane today's flange has no other dielectric
between the bus end and the cathode metal (`02_02 §1.2`; the ratified PEEK ring is built after the HW.9 pin), and any
rotation there loads the channel closure (a requirement, not yet drawn). The FMEA row is about that insulation, not
about the bus as a conductor. The wire itself yields only if another link carries its torque: a capture that clamps
the wire, or a parallel tie of ice or hardened resin in the wet gap or channel (`87`), which can feed torque into the
wire through the grip without crossing the tube's top — no number in the tree bounds such a tie. The order holds for
any wire yield above 162 MPa; tantalum, the weakest, keeps it while its weld root keeps at least 47 % of the table's
yield.

The wind's rotation at the sleeve's bark end, where the flange sits (`77` × its rigid-gyroid bark-end factor), is at
most 2.75 mrad and forces at most 0.55 N·mm through the wire — far below the tube's yield and the wire's budget on
any alloy.

⚠️ **Bounds.** First yield, not fracture: plastic twisting and the turns a drawn wire survives are not in the tree.
The wire's yield is `lib.constants` ALLOY_PROPERTIES, as in `86` — a drawn wire's own yield is not there, β-Ti's has no
source, and the weld root's heat-affected-zone yield is not in the tree (the 162 MPa threshold stands in for it). The
tube's figure is first yield of a free tube: the fit's own stress, +40 °C and creep each lower it — safe for the
order, but not the torque the liner survives. The capture is not designed; the order assumes one that seizes the
liner's top end, while one that clamps the liner's OD over the flange disc passes torque through the wall into the
grip. No rotation at which the liner gives way is given — it needs the liner's own compliance with Coulomb slip, so
that switch is cut. Whether an event slips the flange at all is the event-torque verdict's question. Cache:
`mechanical/bus_torsion_budget.json`.

---

## HW.6 — Thermal install: the radial field the 1D estimate could not see (script 58)

⚖️ **Процедуру ЗНЯТО founder'ом 2026-09-09** — канон [`01_04 §3.5`](../../../01_04_CODIT_and_Xylemointegration.md)
несе саму заборону з підставою, а ця секція є її ДОКАЗОМ і One-Home числами; стан → `00_07` HW.6.
⛔ Не читати як опис доступної процедури.

2D axisymmetric transient FVM over the real three-zone anchor plus bark / phloem / cambium /
sapwood, with an **effective** gyroid λ (connected-skeleton estimator, 0.80 W/m·K vs 6.7 bulk Ti).

🔴 **Direction of the bound, first, because it decides what the model may claim.** Conduction only,
zero contact resistance — every omission pushes tissue temperature UP, so these are UPPER bounds.
An upper bound establishes "not shown to be safe", never "the tissue dies". The verdict holds on
the **margin**: the cambium sits 68 °C above the 50 °C gate and stays above it on all 15 sweep
points (107.8–146.7 °C). Damage is scored as an ISOTHERM, not a time-temperature dose (we have no
Arrhenius parameters for pine cambium and will not invent them), and carrying the 4 % CODIT wound
rule from a drilled wound to a thermal ring is an assumption, not a measurement.

**Solver verified on four independent axes** — the first two do not touch what carries the wound
diameter: closed-box enthalpy drift `0.0` · independent 1D march `0.001 °C` · **steady radial
annulus vs the analytic log law `0.071 °C`** · **two-layer slab vs series resistance `0.000 °C`**.

| Heating variant | cambium peak | >50 °C at | killed LIVING tissue | min DBH | wall >150 °C | heater |
|---|---|---|---|---|---|---|
| **Canon as written** — uniform induction of all Ti to 200 °C | **117.9 °C** | 111 s | **Ø47.5 mm** | **111 cm** | 5 s | 20 W |
| Low end of the same window — 150 °C | 90.7 °C | 162 s | Ø41.5 mm | 94 cm | never | 15 W |
| Only the accessible metal (flange + Zone-3 shank) | 98.5 °C | 113 s | Ø38.5 mm | 91 cm | never | 4 W |
| Selective deep heating of Zone 1, flange at ambient | **48.1 °C** | never | **Ø47.5 mm** | — | 5 s | 17 W |
| Canon + a 2 mm still-air isolator under the flange | 109.1 °C | 134 s | Ø47.5 mm | 101 cm | 5 s | 20 W |
| Pre-heated outside the tree, then inserted | 44.1 °C | never | Ø17.5 mm | — | never | — |

> ⚠️ Geometry of every row above: flange Ø25 seated 3 mm deep IN the bark — the premise predates `01_04 §3.1` (flange over the bark) and the root of 2026-09-30 (Ø29.8); the cache is deliberately NOT re-run. The ratified seat (⚖️ 2026-10-03, `01_04 §3.1`: a shallow facing of the DEAD bark) leaves more dead bark under the flange than this model — and the cache's own bark sweep (dead bark 4–20 mm, i.e. 1–17 under the flange) spans the thin end of it (8.3–17 of the 8.3–21 mm at DBH 38): the killed diameter is the same at every point, because the sapwood path from the hot shank sets it, not the flange. So the rejection holds for the ratified seat by measurement up to 17 mm and by that same insensitivity beyond it (to 21 mm at DBH 38, 28 at DBH 50); the larger Ø29.8 is not evaluated — header of `58_thermal_install_field.py`, `00_07` HW.6. ⊕ **A second pre-verdict premise, same treatment (2026-10-12):** the Zone-1 insertion here is the placeholder 30 mm that ⚖️ `00_07` HW.26 G1 replaced with the whole lock shank (18 mm). Not re-run either — a run moving only that input would describe neither this record nor the part — but its SIGN is measured, at 18, by the same model in a separate run (`58 --insertion-from-lock` → `mechanical/thermal_install_field.g1_insertion.json`, never this record): every cambium figure FALLS (canon row 117.9 → 104.1 °C, cambial ring Ø44.5 → Ø39.5, min DBH 111 → 99 cm; the 10 s pulse 49.3 → 47.6 °C), so the record is the conservative side of both halves of the verdict (`58`'s `L_A_INSERT`).

> 🔴 The killed-LIVING column replaced a cambium-plane-only metric that had scored the selective
> variant a clean "—". It kills the same Ø47.5 mm, just not in the plane the metric watched.

| Hold, then release | cambium peak | killed living | wall coagulation |
|---|---|---|---|
| 5 s | 47.5 °C | Ø19.5 mm | 1.3 s |
| **10 s** | **49.3 °C** | Ø20.5 mm | **8.0 s** |
| 30 s | 54.2 °C | Ø22.5 mm | 33.9 s |
| 120 s | 67.8 °C | Ø27.5 mm | 138.4 s |

**Verdict** — 🔴 As written the procedure kills living tissue out to Ø47.5 mm, cambial ring
**Ø44.5 mm**, so the same 4 % CODIT rule that turns the mechanical Ø15 wound into "DBH ≥ 38 cm" would
demand **DBH ≥ 111 cm**. Heating the only reachable metal never reaches the anode — the 50 mm PEEK
break does exactly what [`01_01 §4.1`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) designed
it to do, which the 1D estimate could not see **by construction** because it modelled a solid Ti rod
— and not because it predated the pivot: the three-zone anchor was canon 12 days BEFORE that cache
([`01_01`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) 2026-05-15 vs 2026-05-27).
✅ **The constructive half: the error is DURATION, not temperature.** The wall passes 150 °C at 5 s
and the cambium 50 °C at 111 s; a 10 s pulse coagulates for 8 s and leaves the cambium at 49.3 °C —
0.7 °C of margin, i.e. a pointer for the bench, not a finished protocol. ⚖️ Founder call — made 2026-09-09: the procedure
was rejected (`01_04 §3.5`). (`mechanical/thermal_install_field.json`)

⊕ **The 1D orphan cache now has a generator.** Script 58 reproduces `kinetics/thermal_penetration.json`
inside its pinned tolerance (Δt 0.014 s, Δα 0, max milestone error 0.009 °C). Its grid puts the last
node at 79.6 mm rather than 80.0, so the record solved a 79.6 mm rod; the **+1.008 %** is now
computed rather than asserted, and the record is not rewritten
([`00_05 §7`](../../../00_05_AI_Native_Operating_Model.md)).

## HW.25 — PTFE-GDL: breakthrough pressure and the O₂ budget (script 57)

Canon home → [`01_04 §5.3/§5.6`](../../../01_04_CODIT_and_Xylemointegration.md); decision → `00_07` HW.25.

Closed form, no fitted parameters: Young–Laplace liquid entry `ΔP = −4γcosθ/d` (γ 0.0728 N/m at 20 °C)
plus a Bosanquet (bulk + Knudsen) steady-diffusion O₂ budget against `J_MAX_25C` at 4 e⁻/O₂.

| Question | Answer |
|---|---|
| Head the spec window holds (0.2–1.0 µm, θ 110–120°) | **10.2 – 74.4 m H₂O** |
| Hand-set field loads (dew film · droplet · 20 m/s air stagnation · 50 mm submersion) | 10 – 489 Pa |
| Pore the prescribed 30 cm column can fail | **33.9 µm** |
| Pore the acceptance criterion demands at θ 110° / 115° / 120° — "≥ 1.5 m" since 2026-09-26 (derived from the IP68 depth, founder-ratified; the old "≥ 1 m" gave 10.2 / 12.6 / 14.9) | **6.78 / 8.38 / 9.92 µm** |
| Water-entry pressure at θ 110° — pore AND angle together, NOT a bubble point (that one runs in a wetting liquid and does not see θ) | 100 / 199 / 498 kPa for 1.0 / 0.5 / 0.2 µm |
| θ at which the worst field load breaks through | **90.02 – 90.10°** |
| Ratified flood — capsule IP68 immersion 1.5 m / 30 min ([`02_02 §3.3`](../../../02_02_Blind_Mate_Pogo_Pin_Interface.md)); NOT one of the four hand-set loads, so it has its own cache block and the row above does not move | **14.7 kPa**, breaking through at θ **90.58 / 91.44 / 92.89°** for 0.2 / 0.5 / 1.0 µm; the widest spec pore at 110° holds it **6.8×** — and since 2026-09-26 the acceptance criterion is DERIVED from this head ("≥ 1.5 m H₂O", `01_04 §5.6`, founder-ratified) — until then "≥ 1 m" lay below it, so a membrane entering between 1 and 1.5 m passed acceptance and flooded; the flood is now a load of the membrane, and its 92.89° is the stand threshold |
| O₂ transport margin at the canon's own lower bound (0.02 µm) | **4838×** |

**Verdict** — 🟢 Spec sound and over-specified at both ends; ⚠️ the BENCH was aimed at the wrong
target, and so was my first reading of the canon. The prose bound "no pores > 15 µm" is **not an
arithmetic error** — it is this same inversion at 120°, the top of the document's own θ range, while
the §5.3 table guarantees only 110° (→ 10.2 µm under the 1 m criterion of the day; 6.78 µm under the 1.5 m one ratified 2026-09-26). The defect is an unstated θ slice, not a wrong
number. Against the four hand-set loads the nominal pore is not the limit by 2–3 orders, but that is
an ELIMINATION: neither a web/seam defect nor loss of hydrophobicity is computed by this formula.
🔑 The design's real exposure is θ — and this document is about RESIN, whose acids are surfactants —
so the useful output is the degradation threshold (θ ≈ 90°), which gives the 12-week rain/dew test a
number to accept against instead of a pass/fail with no criterion. The 0.02 µm lower bound survives
as a wetting/manufacturing caution, **not** as the transport limit the canon claimed.
(`kinetics/gdl_breakthrough.json`)

---

## HW.43 — Cyclic Budget Acceptance Units (scripts 59 + 62)

Canon home → [`01_02 §2.2`](../../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md) / [`01_01 §1.4`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md); decision → `00_07` HW.43.

The item asked for an ACCEPTANCE UNIT per part, not a rubber-stamped pass — literature-cited
endurance/fatigue-limit review (script 59) plus a real-data wind-climatology bound (script 62),
no FEA, no fabricated numbers where the open literature genuinely does not have one.

| Part | Reference found | Verdict |
|---|---|---|
| Pogo spring (BeCu C17200 #75; data from the Mill-Max 0906 sheet — the series itself is `00_07` HW.9's pick) | mfr full-stroke life 1e5–1e6 cyc · S-N anchors 240 MPa→1e10 cyc / 400 MPa→3.05e6 cyc, no strict VHCF flat limit | Two mismatched framings — full-stroke actuation FAILS (likely wrong model); low-amplitude stress framing is physically right but missing three data (cache `missing_datum`): the vendor spring drawing (wire Ø, mean coil Ø, active coils, rate — asked first, ⚖️ 2026-09-22), a torsional S-N reference for C17200 (both anchors are normal-stress data, and an open search on 2026-10-01 found no torsional curve — [`02_02 §2.2`](../../../02_02_Blind_Mate_Pogo_Pin_Interface.md)), and the real sway micro-deflection amplitude |
| PEEK mechanical-lock barb (cyclic, ⊥ HW.26's tracked static creep) | endurance limit 30–48 MPa @ 1e6–1e7 cyc (2 converging sources) | Reference established for HW.26's pending FEA to check against; not itself closed |
| Genipin-chitosan-CNC matrix (01_03 §2.1 Layer 4) | script 16 (N=10 MD cycles, qualitative pseudoplastic) | Category mismatch — a ~10-20 µm enzyme-immobilization coating, not a load-bearing spring; removed from the S-N framing, its durability axis is chemical (HW.5), not cyclic-mechanical |
| Sway frequency (*P. sylvestris*, Hartheim research site, Univ. Freiburg) | Kolbe & Schindler 2021 (HardwareX 9, e00180): first mode 0.273–0.312 Hz, three trees H 17.2–18.0 m, Apr–Oct 2020 · Nickl et al. 2022 (HardwareX 12, e00379): f0 0.26 Hz, strain at 2.7 m, June 2021 · Schindler & Kolbe 2020 (Forests 11, 145): «damped fundamental sway frequency of the stem» 0.74 Hz, one tree H 16.8 m, 30 Jan 2019 — full texts read, one site in all three | A BRACKET of two named readings, not a point: one group, one site, trees of one size, and the readings differ 2.4–2.8× with no cause named in either text. 20 yr of continuous sway gives **1.64–1.97 × 10⁸** cycles at the low reading and a ceiling of **4.67 × 10⁸** at the high one. ⛔ The canon's 1–5 Hz is a bench frequency with no field reading, so no budget is counted at it |
| Wind duty-cycle (Cherkasy pine forest) | NASA POWER WS10M, 10y daily, Beaufort-anchored exceedance | Not closed to one number — even the most generous bracket (Beaufort 3 on open/10 m wind, 70 % of days) bounds N_eff ≤ **3.29 × 10⁸** at the frequency ceiling; sway-onset threshold is "poorly constrained" in peer-reviewed lit and canopy attenuation varies >4× (both named, neither fabricated) |

⊕ **2026-09-29 (HW.30): the acoustic-pad row left with the piezo** (⚖️ founder, [`02_01 §6`](../../../02_01_Hardware_Architecture_and_BOM.md)). It was a MODELLED compliant layer, never a chosen part, and its only route — a bench creep test — went with it; script 59 no longer prices it, and no other row read it (the cache lost exactly that block).

⚠️ **Three bounds travel with every cycle count above, and quoting a count without them quotes more than was measured** (script `62`, cache `bounds_that_travel`): **(1)** frequency × time bounds FIRST-MODE cycles and is not a count of strain ranges — the strain spectrum's first maxima sit at 0.04–0.05 Hz, below f0 (Nickl et al. 2022), and for its sample tree the maximum wind-induced response is quasi-static rather than the dynamic reaction near f0 (Schindler & Kolbe 2020); the honest budget is a strain-range histogram at anchor height, measured for no *P. sylvestris*. **(2)** The canon's host trees (DBH ≥ 38 cm) are larger than every measured tree, and the natural sway frequency is linear in DBH/H² (Moore & Maguire 2004) — so the hosts' frequency is extrapolated, and its direction is not fixed without their height. **(3)** The two readings disagree and nothing in the sources resolves it — both measured STEM motion, so «stem vs whole tree» does not separate them — which is why consumers take the high one as the ceiling and carry its source (script `55` §`wear_budget` and script `59` both load it from the cache).

⊕ **2026-10-13 — the transfer «stem motion → load through the pins» (script `87`, the machine leg split from the measurement leg when the crown pause was lifted for measurements; revised the same day after an adversarial pass — the first version priced one path as if it were all).** Sway reaches the pins along four paths, and the model computes two of them to a number. **(A) The rim — the premise of the rest.** The capsule rides the flange as one body only while the rim's friction (PEEK on Ti, µ from 0.1) holds the capsule's own weight (the anchor axis is near-horizontal, so the weight loads the rim sideways) plus the drag and inertia. Early in life the bayonet clamp of `52`'s requirement (≥ 157 N, sized for the pogo pair and a generous 100 N ring) gives ≈ **21.2** N of capacity against ≈ 1.1 N of demand; but that requirement is sized so the rim only just stays seated after 20 years of relaxation. A clamp at the form `52` prints for the ring's OWN reaction, (R₀ + p)/0.65, never lets the rim lift while the lift stays at its initial value, so the normal force at the end of life is at least that initial lift; a weaker clamp can let the rim lift — whether it does depends on the ring's relaxation against the PEEK's, which nothing models — and a lift is taken as not undone (conservative for (A): lifted, the normal force is L; reseated, 2C − L ≥ L), so from then on the normal force is what the ring has left. On the pogo pair alone it does not hold even the weight, and with the capsule envelope as solid copper and the canopy-top gust it needs an initial O-ring reaction ≥ **10.34** N (median reading) … 10.57 N with the clamp at `52`'s printed form, and the same 10.3–10.6 N still present after 20 years with a weaker clamp (the reaction itself — section HW.33, script `88`). Temperature is in neither: the PEEK in the clamp loop sits between two Ti faces over the same span, so cold unloads the clamp and heat raises it. Below it the capsule shifts inside the collar clearance and the pins SLIDE: `55`'s per-cycle drag premise is that regime, not a ceiling the model escapes. **(B) Stack inertia, rim holding.** Wire stress is linear in force, so for a coaxial clamp the amplitude is m·a over a mean that the static axial share of the weight (10° install angle) lowers — **0.21 % (median) … 0.42 % (whisker) per gram** is the slope at small mass, not a bound; 10 % is reached at **21.5** (whisker) … 39.4 g, and the weakest pin (60 − 20 g at mid-stroke) unloads at **117** (whisker) … 155 g. ⚠️ The clamp is not coaxial (two pins below, an eccentric gasket above), so a force pair m·a·h/s adds to this; h and s are layout quantities, not in the tree. **(C) The centre pad — a ceiling at the pin.** Bending's Poisson strain μ_LR·ε_L is a radial strain that varies along a radial anchor in the bending plane (wind along the anchor's azimuth; zero for an anchor at right angles to the wind), imposing up to μ_LR·ε_s·Δx between the wood at the anode and at the flange — **2.80 … 5.04 % of the working compression per 1000 µε** of stem-surface strain at the anchor's azimuth (μ_LR 0.280–0.392, nine pines at ≈ 12 % moisture, Wood Handbook 2021 Table 5–2, no P. sylvestris; Δx 70–90 mm, anode centroid to flange and the whole depth, `77`'s geometry), 2.6–9.3 % on the source day. The anchor resists it: the Zone 1↔2 press-fit with barbs ties the anode to the flange, and the liner's grip and capture tie the bus-wire tip to the flange (`01_01 §1.4`) — and the Zone 1↔2 press-fit does not have to slip for the term to load the wire and its seam, or to reach the pin as the wire slips inside the liner near the liner's held end — a local slip of the liner's grip, itself an interference fit (⊕ 2026-10-17 below). The worst cases of (A) and (C) need different wind azimuths. **(D) Thermal** cycling of the same contacts is not computed here (script `90`, ⊕ below). Stem input — Schindler & Kolbe 2020, Figure 9 read at 2.0 m (median 0.03, upper whisker 0.06 °/(m²/s²); a plot reading; a whisker is not the maximum) at the day's strongest flux, > 31 m²/s² (control, units only: that interval's 12 m slope × flux = **11.5°** against the text's 12°, the slope regressed on the same data); tilt grows monotonically with height, so for an anchor at any height ≤ 2.0 m the tilt is ≤ 0.93–1.86° and the non-oscillatory displacement ≤ 31–62 mm; the acceleration, ≈ **0.83** (median) … **1.65** m/s² (whisker), takes that whole swing as oscillating at 0.74 Hz — NOT a proven bound either way: the oscillatory share at 2 m is unpublished, at the base it carries ~40 % of the variance, and higher modes weigh as f². Flux scales as U², so a storm twice as windy multiplies the stem quantities ×4: the numbers describe that one January day of one tree smaller than the canon's hosts. The stem's mean curvature between 0.1 and 2.0 m in that interval, 8.5–17 × 10⁻³ rad/m, is ≈ 920–1840 µε at the source tree's DBH 21.5 cm (our calculation from a plot reading); stem strain at 1.3 m was found in open texts only for broadleaves — not transferred. **What it changes:** the pogo's missing half is now a set of unmeasured quantities — the clamp the bayonet delivers, over temperature, against the ring's lift (decides (A); the ring's reaction is `88`'s band), the stack's layout (B; its mass is estimated part by part, ⊕ below), the axial load at the bus wire's root and how much of (C) reaches the pin (the liner's ceiling on that load is computed, ⊕ 2026-10-17 below), the stem strain and acceleration at anchor height on host-size pines (B, C) — not a micro-deflection that only a measurement at the pin could give; that measurement now has a model to be checked against. (`mechanical/pogo_sway_transfer.json`)

⊕ **2026-10-13 — (A) against the O-ring's own reaction (script `88`, section HW.33 — the O-ring's own reaction; revised the same day after two more adversarial passes: «whatever the ring retains» held only for the clamp at `52`'s printed form, and whether a weaker clamp lifts at all depends on the ring's relaxation).** For a ring under 1″ Parker's Table 2-3 puts the load in the middle or upper third of the Figure 2-4 bar, so the ring starts at no less than **58** N at the 19 % window floor — **5.5×** the reaction (A) needs with a clamp at the form `52` prints for the ring's own reaction, (R₀ + p)/0.65, which never lets the rim lift while the lift stays at its initial value (resin swell and temperature can raise it). A weaker clamp can let the rim lift — whether it does depends on the ring's stress relaxation against the PEEK's, which the source does not give — and a lift is taken as not undone (conservative), so (A) is then judged on the ring keeping 18 % of its reaction for 20 years — of its force in the lifted state, where the ledge PEEK creeping under the lift also takes squeeze, so a constant-squeeze relaxation datum overstates what it keeps. Both hold at the assembly temperature only: the PEEK in the clamp loop sits between two Ti faces over the same span, so cold unloads the clamp and heat raises it — `89` (same day) models it: a clamp at exactly `52`'s printed form keeps the rim seated in the cold only if the loop does not feel temperature at all — at the end of life, with a ring that never relaxes and a lift that does not fall in the cold, any thermal sensitivity lets it go, while a clamp sized to `89`'s requirement holds. `02_02 §3.2`'s swell thresholds (≤ 15 % keeps EPDM, 15–25 % is the founder's call) are bench limits on FREE rings and do not bound the lift; any swell raises it. The friction bound runs through the lug ledge (the rim's share can be zero), with µ from `55`'s dry PEEK–Ti sweep, and the ring is greased. The early capacity above reads `52`'s frozen 157 N requirement; with the band the requirement moves both ways, so that figure is one reading, not a bound. (`mechanical/oring_reaction_band.json` → `rim_premise_A`)

⊕ **2026-10-13 — the stack's mass, part by part, before a scale (script `87`, `inputs.stack_parts_g`; revised the same day: solder, mask and coating, the pocket gasket and an optional desiccant joined the rest).** EDLC 1.4 g (Eaton product page) · two standoffs ≈ 1.7 g (Würth gives no mass; its geometry × steel, our calculation) · two FR-4 boards no larger than the rim cavity 2.24–2.72 g (Panasonic R-1755V/M specification sheets, 1.96–2.0 g/cm³; copper 4 × 35 µm at 30–100 % cover) · booster 0.19 g (Ignion datasheet) · B2B pair 0.04–0.25 g (the socket's 40.6 mg is a distributor's figure; the header has none) · pogo pair ≤ 0.2 g (solid-brass ceiling) · the rest 0.35–1.3 g, not from datasheets (MCU, PMIC, TCXO, inductor, sensors, passives, solder, mask and coating, the pocket gasket, an optional desiccant) — **5.97–7.76 g**. At that mass the coaxial inertia is **1.29 %** (median, light) … **3.38 %** (whisker, heavy) of the reduced mean — about a third of the 10 % at worst, the stack reaches only at 21.5–39.4 g; the pair factor of the layout is still unpriced, and a scale reading checks the mass. (`mechanical/pogo_sway_transfer.json` → `B_inertia_coaxial.at_estimated_stack_mass`)

⊕ **2026-10-17 — (C) behind the liner: a ceiling on the axial force at the wire's root (script `87`, `C_wire_behind_liner`, HW.43 leg (1); revised the same day after two adversarial passes — the first capped the wire at the grip's friction and set a factor taken at SF 1 on Ti-6Al-4V beside `86`'s at SF 2 on Ta; the second showed that the yield threshold left the soft liner out of the route's stiffness, so the share of the shift that yields the wall is no longer computed).** No press-fit has to slip for (C) to load the wire: the PEEK sleeve between the anode and the flange is not a rigid body, and the wire spans the same distance beside it; and the tip moves as the wire slips inside the soft liner near its held end, before any yield. What is computed is a ceiling. Every axial force on the wire crosses the liner's own wall, held at its top only (`01_01 §1.4`), so the wall caps it at **53.6** N — **68.3** MPa on the wire, PEEK's 23 °C uniaxial yield — whatever the source: this term, the sleeve's thermal growth between the anode and the flange (the part of path (D) that `90` does not price), or both. A grip that slips first caps it lower (`55`'s window floor at every swept µ; the nominal grip at µ 0.1 if it relaxes to the tree's floor, a low reading). **What it does to the seam (HW.34).** On the tensile half Soderberg weighs amplitude above mean, so for a non-negative axial mean the worst split under the ceiling is all amplitude. Set on the same section as `86`'s bending amplitude and mean at ⌀0.10, in phase, `86`'s own formula raises the seam requirement from k ≥ 0.1441 to **0.55** on Ti-6Al-4V and from 0.3883 to **1.48** on Ta, and drops the wire's SF on Ta from 4.54 to **1.39**; on CP-Ti-Gr4 (**1.03**) and Ta not even an unweakened wire keeps SF 2. The added amplitude divides by each coaxiality branch's own room, so `86`'s three branches keep their ratios, but on Ta even the tightest needs k ≥ **1.35**. **Where the ceiling is not a bound** (named, not computed): the compressive half — PEEK's compressive yield and the capture's push-out capacity are not in the tree, and the sign of the shift at a given anchor is not assigned; a parallel tie — the gap and the channel are wet by design (`02_02 §3.1`), so ice or hardened resin can tie the wire or the liner to the sleeve beside the wall; PEEK below 23 °C (the source day is in January) and a multiaxial yield under the fit's hoop tension, which move the wall's axial yield either way; the beam-column coupling of the tension with `86`'s bending (a few per cent). **Not computed, and it decides where between `86`'s own k and this reading the requirement lies:** the axial load the root actually carries and how much of (C) reaches the pin instead — a shear-lag model with Coulomb slip of the wire in the liner, fed with the share of the shift the wood imposes (the sleeve and the wire resisting in parallel) and the sleeve's thermal growth (HW.43 leg) — computed since 2026-10-20 by `102`, §«The Bus Wire in Its Liner» below. Not in either: weld residual tension, a lower fatigue limit in axial loading than in bending, 20 years of the grip's relaxation, the creep and fatigue of the liner wall itself as an insulator. (`mechanical/pogo_sway_transfer.json` → `C_wire_behind_liner`)

⊕ **2026-10-13 — the gap's thermal travel (script `90`, path (D) of `87`; re-run 2026-10-18 with the pin body and the FR-4 sheets' own CTEs).** `52` budgets the pins' gap at one temperature, and the gap is the radome's PEEK column (11.85 mm to the pocket floor, a placeholder) minus the board stack hanging from it (two FR-4 decks, Z 40–44 ppm/K — Panasonic R-1755M / R-1755V data sheets, Jul. 2019, the range taking R-1755V's 44 over the 43 of a 2018 Panasonic specification sheet; steel standoffs, 12–17 ppm/K — Parker Table 2-5): it moves by **0.28–0.33** µm/K with both together and **0.56** µm/K when the radome leads, i.e. over the capsule requirement it closes by up to **20** µm in the cold and opens by **22** µm in the heat (**33** / **36** µm when the radome leads — a reading, not a bound: the floor hangs from the dome top through ~3 mm of chamber wall). The pins follow the working stroke — the gap less the growth of their own brass body (C36000, 20.5 ppm/K, Copper Development Association; **0.031** µm/K over the pin's **1.49** mm free length — the stroke is the free length less the gap, so the whole free length moves the tip): **0.25–0.30** µm/K together, the radome's 0.56 µm/K when it leads (the stack and the pin then stay put). Added linearly to `52`'s residual, its L1 (spacer only, ±0.112 mm, which leaves 28 µm to each edge of the 50–70 % window) holds isothermally with **8.4–9.9** µm to spare and breaks under the radome-leads reading (−8 / −5 µm) — it tolerates a radome leading the stack by about **33** K at the extremes, and its isothermal margin reaches zero only for a spacing member of CTE **−4.0…−5.6** ppm/K (should the B2B body, not the steel standoff, set the deck spacing — its LCP CTE is not in the tree) — all against `52`'s RSS residual; a linear sum of the same two terms (±0.15 mm) leaves no room even at the assembly temperature. This is the OUTER pad with the rim and the stack seated (the stack in fact floats on the pogo pair against the pocket gasket, springs of one order); the centre pad's axial position rides on the wire path (HW.34); only `52`'s L1 is judged here — the design's minimal mitigation since ⚖️ 2026-10-21 is L3, the bayonet hard-stop with a 0.05 mm spacer step (`52`'s ladder, its margins in `90`'s cache; why — §«What Each Remedy for the Centre Pad's Travel Buys and Costs»), and whether the hard-stop acts under branch (а) is `52`'s question (canon keeps it live). Daily, `71`'s capsule (a reading whose error on the range has no known sign — it takes the worst sun gain and omits the night sky — and, as one lump, no shell/stack lag) swings by a median **14.5** K and a 95th percentile **24.9** K — a pin stroke of **3.6–13.8** µm, **0.5–2.0** % of the minimum preload once a day (the ratio takes the force as the stroke times a fixed spring rate; the BeCu spring's modulus falls with temperature, and no figure for it is in the tree) — and, if the radome holds the stack in-plane, a pin at radius r slides by **0.95–1.17** µm per mm of r on a 95th-percentile day, **0.06–0.37** µm if the pins follow the board's own in-plane expansion instead (FR-4 11–15 ppm/K in-plane, the same Panasonic sheets); the centre pad, at r = 0, does not. The one axial term not computed, the pocket gasket (a placeholder), shrinks the swing — it expands with the PEEK and pushes the stack back — so, for a given temperature field and the seated premises, leaving it out keeps the stroke an upper estimate. Not computed: what centres the stack, the outer pad's radius (layout, HW.9), the centre pad's wire path inside the sleeve (HW.34) — computed since 2026-10-20 by `102`, §«The Bus Wire in Its Liner». (`mechanical/pogo_thermal_gap.json`)

⊕ **2026-10-18 — how long the field strain campaign must run (script `98`).** The instrument sheet proposes carrying the field leg's strain-range histogram in time at the site by binning its hours by the same hour's ERA5 10 m wind and weighting by the 30-year climatology (a method the founder ratified on 2026-10-18, `01_02 §2.2`), so the campaign needs strong-wind hours — and they come in storms: **14** of 30 Januaries have no hour ≥ 8 m/s (Beaufort 5) at all. Replayed year by year to 10 such hours (ours), a campaign takes a median **72** days from 1 December (p75 **144**); the December–March starts lie within the scatter of 30 years of each other, a June start takes more than half a year, and the tail is long — in about one year in ten the target comes only in August–November (p90 **252** days from 1 December). So the campaign runs to a stop rule capped at 1 May (ratified 2026-10-18): from 1 December **79** % of seasons reach the target by then. Two strain sensors at right angles and one tilt sensor on one receiver (0.213 A, the receiver more than half of it) cost **5** trips on 100 Ah at the median from December, more in a quiet winter; the ratified set adds a third strain sensor opposite one of the pair (common mode and redundancy), at most **10** trips under the cap, and the trips are a floor (the full battery rating in winter cold). The forest access application promised only a quarterly visit, which no battery of sensible size meets — the same verdict wrote the campaign's visits into it. An earlier draft of this paragraph took the month's 30-year mean rate as the campaign length (≈ 50 days from January) — the adversary caught it before push. The instrument sheet — `docs/protocols/anchor/field_strain_sensor_sheet.md`; the ratified window, power and visits — `01_02 §2.2`. (`mechanical/field_strain_campaign.json`)

⊕ **2026-10-19 — the campaign battery's type and its swap calendar (script `98` §5, the desk leg of HW.43).** For the ratified set (0.2389 A, ≈ C/419 of 100 Ah) over the capped 1 December campaign of each of 29 seasons, with the ERA5 2 m air as the battery temperature (hourly and as a 24-hour mean; that a box on the ground is no colder than this air is an assumption): an AGM battery weighs 27–28 kg, a LiFePO4 one 9.7–14 kg, carried in and out at every swap — the ground of the choice. An AGM's electrolyte freezes at a temperature set by its state of charge (Concorde Lifeline Technical Manual, Table 6-2), which falls with the ampere-hours drawn: swapped every 14 days it is at 19.7 % by then, where the point is −11.5 °C, and the air goes below the point of its current charge in **7–12** of 29 campaigns on the 24-hour mean (**10–16** hour by hour) as the first swap moves over the cycle, against **0–2** for swaps every 10 days; the same maker calls AGM resistant to freezing damage against flooded batteries but tells the user to keep the charge at a maximum in the cold. LiFePO4 holds no water; its sheets allow discharge to −20 °C, which the air crosses in **4** / **12** campaigns, the coldest air in any Beaufort-5 hour is −9.0 °C, and its sheet's humidity ends at 80 % RH, which the air exceeds in **66 %** of the campaign hours. Cold capacity at OUR current no sheet measures and no reading is a proven floor there (a C/20 curve that its own manual's text undercuts, a nominal stated for any current up to 1C, a sheet with no current, a cell minimum to a cut-off below a pack's), so the readings do not rank the chemistries. On them a 100 Ah battery lasts **12.9–14.1** days (AGM) and **11.8–12.2** (LiFePO4) in the median season's coldest fortnight, **10.9–12.4** and **9.5–10.3** in the coldest of 29, and under the ratified min(14 days, resource) a LiFePO4 campaign costs **7** trips at the median and up to **13–14**. Against the LiFePO4 readings (a battery empty at least an hour before its swap): the ratified rule run on the Victron reading with the interval's mean temperature known costs **7** trips at the median and up to **14** with cut-offs in **1** / **0** campaigns; swapping every 14 days, in **26** / **25**; every 10 days from December to March and 14 otherwise, in **0** / **2** for **8** trips at the median and up to **16** — all on readings not measured at our current, so the table reorders rules rather than ranks them. LiFePO4 was ratified by the founder on 2026-10-19 on the recommendation — the full form and its post-«так» corrections in `01_02 §2.2`; the freezer measurement, ratified by the founder 2026-10-19 on the recommendation (full form `01_02 §2.2`; procedure — the sheet §3), is a pass/fail test at our current — stop at **81** Ah (14 days of the primaries' current, rounded up) at a mean of −20…−18 °C (colder than the coldest 10- and 14-day means of the record, warmer than its coldest 3–7-day means): at ≥ 81 % the ratified rule gives no interval shorter than 14 days in any season (**6** trips at the median and up to **12**), at 58 % it costs **7** and **14** on a measured-point curve that is ours. (`mechanical/field_strain_campaign.json`, `battery_type`)

**Verdict** — 🟡 Genuinely partial. No part is fully closed, and that is the honest result: each
gets a named numeric threshold or a named reason the closed-form method does not apply, plus the
exact missing datum that would close it (for the pogo spring the vendor spring drawing first, ⚖️ 2026-09-22, then a
torsional S-N reference and the inputs script `87` names for the sway transfer — the clamp the bayonet delivers over temperature against the ring's lift, the O-ring force, the stack's mass and layout, the axial load at the bus wire's root and the share of the centre-pad term that reaches the pin (since 2026-10-17 in place of the press-fit and liner-grip capacities; since 2026-10-20 computed by `102` as a function of the share the wood imposes, and that share by `103`, conditional on the bark's bearing, the anode bond and the sleeve's tie), and the stem strain and acceleration at anchor height; HW.26's FEA output for the barb; and for the cycle budget a
strain-range histogram at anchor height from a strain gauge on the trunk — not an anemometer, whose wind would still
pass two unmeasured multipliers, ⚖️ 2026-09-23, [`01_02 §2.2`](../../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)). The one clean correction is the
genipin-matrix removal from the checkbox's own S-N framing — the durability question that actually
matters for it lives in HW.5.
(`mechanical/contact_endurance_check.json`, `mechanical/wind_duty_cycle.json`)

---

## HW.37 — EDLC Endurance-Hours: Temperature + Voltage (script 51, generalized)

Canon home → [`02_03 §12.1`](../../../02_03_BQ25570_MPPT_Nano_Power.md); decision → `00_07` HW.37.

`02_03 §12.1` justified a 20-year EDLC claim via >500,000 cycles (vendor marketing), but the
node only does ~99k cycles/20yr — cycle-count is not the binding constraint. Real end-of-life is
temperature+voltage **endurance-hours** (electrolyte dry-out / ESR-rise). `arrhenius_aging()`
(HW.3's Ti-corrosion kernel) was hardcoded to Ti constants; generalized 2026-09-09 to accept
T_field/T_lab/Ea as parameters (Ti numbers verified byte-identical after the refactor), and a
sibling `capacitor_life_hours()` added for the vendor temperature+voltage doubling rule.

| SKU (`02_01 §3` поз.3) | Rated point | Life @ 25°C | Life @ 10°C | 20-yr voltage-derating bracket @10°C |
|---|---|---|---|---|
| Eaton KR-5R5H474-R | 1000 h @ 70°C @ 5.5V | 2.58 yr | 7.30 yr | optimistic (0.2V/2×): 5.20V→20.7yr · conservative (0.4V/2×): needs ≤4.92V |
| KEMET FG0H474ZF | 1000 h @ 70°C @ 5.5V (same rated point) | 2.58 yr | 7.30 yr | **same bracket as Eaton** — KEMET's own voltage coefficient not found in a public datasheet; reported as sensitivity, not a false-precise number |

**Verdict** — 🔴 Confirmed via the actual pipeline (not hand-math): the 20-year claim at full
rated voltage does **not** hold for either SKU (2.6-7.3 yr, a 3-8× shortfall). Whether 20 years is
reachable depended on the `VBAT_OV` target — at 10°C the conservative vendor coefficient needs
≤4.92V, the optimistic one only ≤5.20V. **Derate RATIFIED 2026-09-09 (`VBAT_OV` = 4.822 V) and SKU
closed 2026-09-22 (Eaton KR):** at the ratified point the same pipeline gives 23.6–76.5 yr @ 10°C and
8.4–27.1 yr @ 25°C (conservative–optimistic), so 20 years holds at 10°C across the bracket and at 25°C
only at its optimistic end; the bracket itself is the open vendor voltage coefficient (FAE, `00_07` HW.37).
The
cycle-count argument in `02_03 §12.1` is not wrong, only insufficient on its own; both axes now
stand side by side there. (`kinetics/gusak_degradation.json` → `edlc_endurance_hours`)

---

## HW.37 — Capsule Thermal Envelope vs the EDLC Rating (script 71)

Canon home → [`02_03 §12.1`](../../../02_03_BQ25570_MPPT_Nano_Power.md); decision → `00_07` HW.37.

The surviving EDLC (`KR-5R5H474-R`) is rated −25…70 °C, while `02_02 §2.1` gives the capsule
−40…+85 °C. Script 71 asks the BOUND question — does any hour of thirty Cherkasy years put the
capsule above the rating? — on ERA5 hourly 1991–2020 (`tools/in_silico/data/era5_cherkasy/`,
provenance in its README) with one isothermal lump per hour: the beam on the LARGEST projection of
the exposed radome over all directions plus diffuse on half a sky, lost by the larger of natural and
forced convection and by linearised long-wave exchange with surroundings at air temperature, on an
adiabatic base (the Zone-2 PEEK break). Absorptance α is swept 0.50–0.95 as a bracket (written as
«canon does not specify the radome finish», which was false — the spec named «brown or RAL 8007»;
the sweep became the basis of the delegated verdict 2026-09-27 that specifies α ≤ 0.5, `02_01 §5.2`); trunk-level wind is k·u10 with k = 0 (the bound), 0.1 and 0.3.

| Hottest hour, still air | α 0.50 | α 0.95 | Margin to 70 °C at α 0.95 |
|---|---|---|---|
| Sunlit (the beam reaches the capsule) | 52.9 °C | 64.3 °C | 5.7 K |
| Sunlit, h_c × 0.7 (the correlation off its home geometry) | 55.0 °C | 68.0 °C | 2.0 K |
| Shaded (open-sky diffuse only — an upper bound under a crown) | 42.8 °C | 49.1 °C | 20.9 K |

The second output is the temperature the EDLC AGES at: the vendor's doubling rule averaged over the
hours, T_eff = 10·log2⟨2^(T/10)⟩, with the life taken from `51`'s own `capacitor_life_hours` at the
ratified `VBAT_OV` (imported, not re-implemented — the 10/25 °C reference points reproduce `51`).

| Series | T_eff | Life, conservative–optimistic |
|---|---|---|
| Open air | 13.0 °C | 19.1–62.0 yr |
| Under the radome, shaded (α 0.50/0.95 × k 0/0.1) | 14.35–17.35 °C | 14.2–56.6 yr |
| Under the radome, sunlit (α 0.50/0.95 × k 0/0.1) | 17.74–27.41 °C | 7.1–44.8 yr |

Re-run 2026-09-30 on the Ø29.8 dome (the root verdict opened the Ø25 freeze for the board, `02_01 §3.5`): the larger solar area costs ≈ 1.4 K of hot margin (7.1 → 5.7 K at α 0.95, still air) and ≈ 0.4–0.9 °C of sunlit T_eff; every verdict stands.

Cold side: the air was below the −25 °C floor for 64 hours in 30 years (9 days, coldest −27.4 °C);
the lump tracks the air at night in this model, and real sky cooling would make the capsule colder,
so the count is a LOWER bound for the capsule. With the sky it is computed by script 81 (next section).

**Verdict** — the hot side is not exceeded for any finish in the sweep, but for a DARK finish in full
sun the margin is of the order of the model's own uncertainty, while a light one keeps ≥ 15.0 K. The
aging side moves the 20-year claim: the site does not age the EDLC at the 10 °C reference point, and
at its real T_eff the conservative voltage coefficient stays below 20 years in every case while the
optimistic one stays above it in every case — so the claim now rests on the vendor voltage
coefficient alone, which the FAE letter asks. NOT modelled: sunlit bark heating the flange rim and
ERA5 smoothing of station maxima (both move the hot answer UP), canopy transmittance (the shaded case
is an upper bound under a crown), sky cooling at night (the cold count is a lower bound).
(`thermal/capsule_envelope.json` → `hot_bound`, `hot_bound_h_c_sensitivity`, `aging`,
`cold_hours_below_edlc_floor`)

---

## HW.37 — The Capsule's Cold Edge with the Night Sky (script 81)

Canon home → [`02_03 §12.1`](../../../02_03_BQ25570_MPPT_Nano_Power.md); decision → `00_07` HW.37.

Script 71 leaves the cold side as a lower bound on purpose: its lump has no sky, so every hour without sun returns
the air. Script 79 has the sky but ties the capsule to the bark through the flange, and gives the isolated capsule
at one reference hour only. Script 81 runs 71's isolated lump hourly over the same thirty ERA5 years with 79's sky
term (Brutsaert clear-sky emissivity from the ERA5 dew point), natural convection called with |ΔT| and long-wave at
full T⁴, bracketed by sky (clear every hour ⊥ overcast every hour), sun (none ⊥ ERA5 diffuse on half a sky at the
lightest specified α 0.50, no beam) and trunk wind (u = k·u10, k = 0 / 0.1 / 0.3). Four controls can fail: 79's
reference hour, overcast with no sun returning the air EXACTLY on every hour, the air count equal to 71's, and an
unbroken hourly clock. The second earned its keep on the first run: ERA5 air comes in 0.1 K steps, so hours sit ON
the floor, and a root within the bisection tolerance tipped two of them below it — the solver now returns the air
exactly where no gain meets no deficit.

| Below −25 °C in 30 years: hours (days · longest spell) | Still air | u = 0.1·u10 | u = 0.3·u10 |
|---|---|---|---|
| Clear sky, no sun | 565 h (63 d · 106 h) | 251 h (26 d · 44 h) | 155 h (18 d · 29 h) |
| Clear sky, diffuse sun | 509 h (61 d · 59 h) | 225 h (25 d · 22 h) | 144 h (17 d · 20 h) |
| Overcast, no sun — the air itself | 64 h (9 d · 10 h) | 64 h (9 d · 10 h) | 64 h (9 d · 10 h) |
| Overcast, diffuse sun | 57 h (7 d · 10 h) | 61 h (8 d · 10 h) | 62 h (8 d · 10 h) |

Which end the site leans to near the floor is read on ERA5's own sky: on the winter days the air falls below −25 °C,
0.84 of the daylight hours are sunny (direct normal irradiance ≥ 120 W/m², the WMO threshold) against 0.32 for every
winter day — the day's sky as the night's proxy — while the 10-m wind in the hours below the floor has a median of
3.3 m/s against 3.5 m/s for every winter hour. The sky near the floor is clear; the air is not calm.

**Verdict** — the isolated capsule spends between 57 h (7 days) and 565 h (63 days) in 30 years below the EDLC
floor, against the air's 64 h; the longest spell below it is up to 106 h and the coldest capsule hour −33.5 °C; no
run crosses the capsule requirement −40 °C. Near the floor the site leans to the clear end, while the still-air
column is a bound rather than the typical case — so the clear rows with wind are the nearest the tree comes to a
typical winter, with k itself ours. NOT modelled: the bark's heat through the flange and the capsule's heat capacity
(the first makes it warmer, the second raises its minimum), ERA5 smoothing of station minima (moves the edge DOWN),
snow or rime on the radome; the temperature INSIDE the capsule is the thermocouple leg of HW.37.
(`thermal/capsule_cold_edge_sky.json` → `runs`, `edges`, `sky_on_cold_days`, `controls`)

---

## HW.33 — The Bayonet Collar's Running Clearance (script 82)

Canon home → [`02_02 §4.4`](../../../02_02_Blind_Mate_Pogo_Pin_Interface.md); decision → `00_07` HW.33 / HW.9 root package.

The collar that carries the bayonet lugs grows on the Ti flange inside the radome's socket band, and the radial gap
between its outer face and the PEEK band's inner wall is the one member of the board's radial chain no artefact
numbered: `52` puts the socket's 0.3 mm slot clearance there because nothing states it. Script 82 computes it under
the crown-pause exception granted 2026-10-05. The PEEK band lies OUTSIDE the Ti collar on Ø26.2 (from `73`'s
socket band), so the cold edge closes the gap and the hot edge opens it. The physics floor is 30 µm per side at
the capsule requirement of −40 °C with both parts at it, 37 µm if the Ti stays at 20 °C while the PEEK reaches
−40 °C (27 µm at `81`'s modelled cold edge). Everything above the floor is manufacturing tolerance: ISO 286 grades
computed from the standard's formula (a control holds them against the published 18–30 mm table), three routes
that are ours until the vendors answer.

| Route | Design clearance (mm) | Board ceiling at the 0.2 mm wall (mm) |
|---|---|---|
| Machined collar · machined band (IT7 · IT9) | 0.082–0.088 | 19.79–19.81 |
| Machined collar · moulded band (IT7 · IT11) | 0.141–0.147 | 19.68–19.69 |
| Coarse: IT8 collar · IT12 moulded band | 0.212–0.218 | 19.53–19.55 |

**Verdict** — every route stays below the 0.3 mm placeholder, so the board ceiling at the print-floor wall falls to
19.53–19.81 mm rather than 19.37 (19.97 with no clearance). The row is the drawing's fit; the route that pins it is
the vendors'; the root is not moved by this script. NOT modelled: capillary water held in a narrow gap and its ice
(a tighter gap holds water higher — the drainage requirement governs it), friction and wear of the turning fit,
creep of the band. (`mechanical/collar_running_clearance.json` → `thermal_closing_mm`, `routes`, `controls`)

---

## HW.33 — The O-ring's Own Reaction: Parker's Band over the Squeeze Window (script 88)

Canon home → [`02_02 §3.2`](../../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (the band); consequences → `02_02 §3.5` (rim
clamp) and `02_02 §4.4` (collar wall); decision → `00_07` HW.33.

Canon had no O-ring compression force: `52` sized the rim clamp with a «deliberately generous» 100 N, `73` judged the
collar wall against that bound, and `87`'s premise (A) needs a reaction from below. Script 88 reads Parker ORD 5700
Figure 2-4 (.070 section, 70 Shore A) from the vector paths of the PDF page (≈ ±4 % in load from the plot's own
gridlines), keeps the part of the bar Table 2-3 gives a ring under 1″ (the middle or upper third — never the lower,
taken in the log scale the bar is drawn on), interpolates log-load linearly in squeeze between the chart's rows (our
assumption), and puts it on the 71.5 mm seal length of the AS568-019 ring on the groove's inner wall. Both the clamp and
the ring relax, so `52`'s requirement lies between R + p at assembly and (R + p) / 0.65 for a ring that never relaxes —
the form `52` prints; the clamp's PEEK reaches its floor within a few years (`52`'s f(t)), so the ring's loss is due early,
and Parker gives compression set, not stress relaxation, so the share the ring loses is a vendor datum.

| Squeeze | Reaction (N) | Lug root at the print floor: at assembly … ring never relaxes | Ring must have lost (for SF 2) by year 2 · 5 · 20 |
|---|---|---|---|
| 19 % — window floor | 58–119 | 3.78× … 2.46× | 0 · 0 · 0 % |
| 21.7 % — `52`'s chain, low | 74–158 | 2.85× … 1.85× | 0 · 0 · 0 % |
| 24.5 % — nominal | 96–218 | 2.08× … 1.35× | 0 · 0 · 0 % |
| 27.3 % — `52`'s chain, high | 125–300 | 1.51× … 0.98× | 0 · 1 · 2 % |
| 30 % — window top | 160–409 | 1.11× … 0.72× | 23 · 28 · 28 % |

**Verdict** — the 100 N is not an upper bound: the band's top passes it from 17.1 % squeeze. With that top the lug root
(SF 2 inside; no fillet, no lug bending) carries `52`'s requirement at the nominal whatever the ring does, at the top of
the chain `52` models once the ring has lost about 2 % of its reaction, and at the window top only if it has lost about
23 % by year 2 and about 28 % already by year 5; a ring that never relaxes binds the lug from 27.1 % (26.8–27.5 % over the transcription — the source cannot tell
it from the chain's top), and strength, not printability, then sizes the collar wall — at least 0.28 mm at the window top
against the 0.2 mm print floor (`52`'s form at the assembly temperature with no fit tolerance) — ratified as a conditional member of the root package (⚖️ founder 2026-10-13, `02_02 §4.4`; script 89 ↓ found it is the lower bound of a PEEK-dominated loop and a point on a curve of an unmeasured stiffness, and the founder ratified it as such the same day). From below, the ring starts at no less than 58 N at the
floor: (A) holds 5.5× with a clamp at the form `52` prints for the ring's own reaction; a weaker clamp can let the rim
lift, and (A) is then judged on the ring keeping 18 % of that floor for 20 years (a lift taken as not undone). The margins say whether a bayonet that meets the
requirement can exist; the lug carries the clamp it actually delivers. NOT modelled: the compound's own curve and its
stress relaxation (questions in the O-ring letter); temperature — every margin here holds at the assembly temperature,
while the PEEK in the clamp loop sits between two Ti faces over the same span, so cold unloads the clamp and heat raises
the lug's load, and the ring's own contraction takes squeeze in the cold (`89` ↓); resin swell, which raises the reaction; confinement near a full gland; the PEEK ledge under the lug, which carries the same load. (`mechanical/oring_reaction_band.json` → `band`, `inversion`, `rim_premise_A`)

---

## HW.33 — The Bayonet Clamp over Its Fit and Temperature (script 89)

Canon home → [`02_02 §4.4`](../../../02_02_Blind_Mate_Pogo_Pin_Interface.md) (the conditional root-package member
«collar wall by strength», ⚖️ founder 2026-10-13 — returned the same day and ratified as a lower bound, with a flat lug
contact and a numbered interference tolerance required before the collar is drawn); open work → `00_07` HW.33 · HW.8.

The bayonet is deflection-controlled: the clamp is the elastic squeeze of the loop lug → groove ledge → radome → rim →
flange face → collar, C = k·(interference). Two displacements move it through the same loop stiffness k: the TOLERANCE
of the interference (±δ — the lock-groove Z and the lug Z, neither specified; read at 0 · 0.05 — the class the shop is
asked for a machined groove depth, borrowed for one Z dimension — · 0.10 mm, both summed; the face flatness of `52` is in
neither) and TEMPERATURE (the PEEK sits between two Ti faces over one span, so cold unloads the clamp and heat loads the
lug; a Ti–PEEK gradient makes it worse). In a PEEK-dominated loop (k = k_PEEK, the PEEK relaxing by `52`'s f, the summer
increment relaxing too before the winter) the lug must carry L0/f + k·[2δ + Δα·L·((ΔT_c + (1 − f)·ΔT_h)/f + ΔT_h)]; a
spring in series makes f_eff = f/(f + φ(1 − f)) with φ the PEEK's share of the compliance, so the load runs continuously
down to L0 (force control). Readings: the capsule requirement (−40…85 °C) and the models' edges (−33.5 °C from `81`;
55.0 °C from `71` for the canon finish α ≤ 0.5 — a lumped capsule mean); L0 at `88`'s band top, the ring never relaxing;
the span 1.7 mm, a placeholder. The lug is a radial pin R1.5 on the groove's flat ledge — a line contact.

| Squeeze | L0 (N) | Wall (mm), PEEK-dominated: lower bound · k = 1 · 3 · 10 N/µm, ±0.05 mm | Force-controlled wall, zero band (mm) | Line-contact p0 on the mean lug, PEEK-dominated load (MPa) |
|---|---|---|---|---|
| 19 % — window floor | 121 | 0.08 · 0.13 · 0.23 · 0.57 | 0.05 | 215 |
| 24.5 % — nominal | 220 | 0.15 · 0.20 · 0.30 · 0.64 | 0.10 | 291 |
| 27.3 % — `52`'s chain, high | 302 | 0.20 · 0.25 · 0.35 · 0.70 | 0.13 | 341 |
| 30 % — window top | 411 | 0.28 · 0.33 · 0.42 · 0.77 | 0.18 | 397 |

**Verdict** — in a PEEK-dominated loop every N/µm adds **0.049** mm of wall at the window top with ±0.05 mm of
interference (temperature is **11** % of it; with no tolerance **0.0055** mm, 0.0067 with a gradient), so such a loop
needs more than the ratified 0.28 mm for any k — that number is its lower bound, not an estimate. A compliant element in
series fades the relaxation and the k-terms, and the load runs continuously down to L0 — **411** N at the window top, a
**0.18** mm wall with a zero force band — so the ratified number is one point on a curve of an unmeasured k, bounding
nothing. The force-controlled end is not cheap: inside the print floor its spring must be no stiffer than **0.42** N/µm
with ±0.05 mm and zero force tolerance (≈ **1.0** mm of working deflection; 2.0 mm with ±0.10), its whole force band
fits ±**5.3** % at the window top, and a soft clamp leaves the rim almost no stiffness against tipping. Separately, the
radial-pin lug on a flat ledge (engaged 1.3 mm) peaks on the mean lug at **397** MPa at the window top (215 at the window
floor; 320 at the top even under the force-controlled L0) against **167** MPa for first yield at the PEEK's tensile yield
(the compressive yield is higher and not in the tree): it exceeds first yield — below the surface, contained — across
the window, and local creep beyond `52`'s f is expected, not computed; a flat contact would remove that, but the line
contact is likely the loop's softest member, so removing it raises k. Unequal lugs carry more than the mean. k, δ and the PEEK's share of the compliance are not
computed — the lug geometry and both Z tolerances are placeholders; the founder ratified the member as a lower bound (`02_02 §4.4`,
`00_07` HW.8.8). NOT modelled either: the PEEK at the sunlit base — the model takes `71`'s lumped capsule mean, which is
NOT conservative (the ledge sits at the sunlit outer diameter while the Ti is tied to the stem, so a gradient adds to the
mismatch); the ring's force below room temperature; resin swell; ratcheting beyond one summer.
(`mechanical/bayonet_thermal_clamp.json`)

---

## HW.42 — Does a Second Power Source Contaminate `delta_t`? (script 63)

Canon home → [`02_03 §9`](../../../02_03_BQ25570_MPPT_Nano_Power.md); decision → `00_07` HW.42.

Since [E.63], the EDLC recharge interval `delta_t` drives `growth_points` directly — a
money-minting signal. `HW.21` carried (until the 2026-09-09 verdict below) a checkbox to put a TEG on the SAME
BQ25570 charging rail as the EBFC; `01_03 §4`'s instrumental-noise list is exhaustively chemical and has no axis for "a
second power source on the shared rail". Closed form: `delta_t = E_window / (P·η_boost)`, where
`E_window` is the EDLC window ON VSTOR at the ratified `VBAT_OV` (`02_03 §8`, doc↔cache-pinned — the
energy the boost puts in; the post-buck figure is the discharge side and never a charging time),
swept over auxiliary power P_aux = 10-200 µW (spanning HW.21's own 50-200 µW TEG estimate),
reported as a 3-way bracket (shared-boost floor / direct-injection ceiling / BQ25570's own
measured η(P) curve as a cross-check) — a bracket because the multi-input topology was still open
when it was set, before the 2026-09-09 verdict below closed the shared rail as an approach (the
cache's `model` string said «still open (FW.50)» until 63 was re-run on 2026-10-02 with the numbers
unchanged; `FW.50` is the Vcap-ADC item — its own topology fork was the Vcap-sense divider, never
the multi-input).

| P_aux | Summer (15 µW) shift | Winter (3-5 µW) shift |
|---|---|---|
| 10 µW (range floor) | 40-50% | 67-84% |
| 50 µW | 77-83% | 90-96% |
| 200 µW | 93-95% | 98-99% |

**Verdict** — 🔴 Even at the BOTTOM of the plausible TEG range, `delta_t` is already dominated by
the auxiliary source rather than tree metabolism, in every season. The percentage result is
algebraically independent of which `delta_t` definition of the form E / (P·η) is used (E_window cancels
in every bracket model) — this is not an artifact of scale choice. ⚠️ A definition WITH a sleep term —
script 30's since 2026-09-27 — gives a HIGHER percentage (sleep only raises the contamination), so the
verdict stands and is, if anything, conservative. ⚖️ The rail question this number fed is decided — **RATIFIED founder
2026-09-09** (`00_07` HW.42, [`01_03 §6.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): a second source on the shared rail
is rejected — closed as an approach, not deferred; a TEG, if integrated at all, needs a physically separate charging path.
(`kinetics/delta_t_aux_power_sensitivity.json`)

---

## HW.21 — A TEG ACROSS the Zone-2 PEEK Break, Not Glued to the Bark (script 64)

Canon home → [`01_03 §6.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (TEG concept) +
[`01_01 §4.1`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (why the break exists at all);
decision → `00_07` HW.21.

`HW.21`'s 🤖 leg asked (closed 2026-09-10 on this script's result — now a ⛔ entry in HW.21) the
geometrically obvious question: a bark-glued module sees its ΔT through bark
(λ 0.05–0.1) and an unclamped joint, whereas **Zone 2 is the one place in the anchor where both junctions
are already mechanically fixed on opposite sides of a λ 0.25 insulator**. ⚠️ But it aims straight at the
reason Zone 2 exists — a continuous Ti bridge super-cools the cambial ring into intracellular ice — and a
TEG is, before it is anything else, a conductive plate. Script 64 **imports** script 54's ladder rather
than copying it (it re-derives 54's own cached Ti / no-bus / Cu conductances to rtol 1e-12 or aborts the
run) and adds `G_TEG = κ_eff·A/t` in parallel with either the 18 mm PEEK-only gap (`gap` mount — the whole
Zone-1 lock shank inserted, ⚖️ `00_07` HW.26 G1; 6 mm at the placeholder insertion until 2026-10-12) or the
whole 50 mm sleeve (`sleeve` mount), judged against the same −2.0 °C cambium gate and the same
wood-reservoir sweep. Straps and collars are modelled as **ideal**, which overstates the thermal harm AND
the electrical output — both biases favour the idea under test, so a rejection under them is robust.
Output is taken at the ΔT that *survives the module's own installation*:
`P_max = (ZT/T̄)·G_TEG·ΔT²/4` (≡ `S²ΔT²/4R`, since `Z = S²/(R·K)` at module level), with κ_eff
1.2–1.6 W/(m·K) and ZT 0.7 from Bi₂Te₃ literature — Poudel *et al.*, *Science* **320**(5876) 634–638
(2008), [doi:10.1126/science.1156446](https://doi.org/10.1126/science.1156446); Goldsmid,
*Introduction to Thermoelectricity* 2nd ed., Springer Series in Materials Science (2016),
[doi:10.1007/978-3-662-49256-7](https://doi.org/10.1007/978-3-662-49256-7) — both Crossref-verified.

| Case (κ_eff 1.4, `gap` mount) | G_TEG | × whole anchor | T_anode | gate | P at surviving ΔT | V_oc |
|---|---|---|---|---|---|---|
| *no TEG — the residual monolithic-Ti bus we already accept* | — | 1× | **+0.52 °C** | ok | — | — |
| 8×8×4 mm — smallest geometry swept | 2.24e−2 W/K | 27× | −9.75 °C | ❄ FAIL | 1102 µW | 17.3 mV |
| 15×15×3 mm | 1.05e−1 W/K | 127× | −12.71 °C | ❄ FAIL | 392 µW | 16.7 mV |
| 40×40×3 mm — HW.21's own 4×4 cm part | 7.47e−1 W/K | 903× | −13.66 °C | ❄ FAIL | 63 µW | 17.9 mV |
| *asymptote:* `gap` mount, G_TEG → ∞ | ∞ | — | −13.83 °C | ❄ FAIL | — | — |
| *reference:* **solid Ti, NO PEEK break at all** | 1.27e−2 W/K | 15× | **−11.66 °C** | ❄ FAIL | — | — |

**Verdict** — 🔴 **Reject as posed, and not because the part is badly chosen.** `0 of 90` swept
combinations (5 footprints × 3 thicknesses × 3 κ × 2 mounts) pass the gate: the *smallest* geometry
swept already conducts **27× the entire anchor**. It is not a partial defeat — a gap-spanning module
saturates at −13.83 °C, **2.17 °C COLDER than a solid Ti anchor with no PEEK break at all** (−11.66 °C),
i.e. it goes BEYOND the pre-PEEK condition Zone 2 exists to prevent: a shorted gap leaves only the two
shanks (32 of the 50 mm sleeve) in series, where the solid rod would put all 50 (the sign is derived in `64`,
not typed). Inverted, the number worth keeping is the **budget**: anything crossing the break must stay
under **1.9e−3 W/K ≈ 4.1 mm² at 3 mm** — ×16 smaller than the smallest module — and across the 32 live
wood-grid points that budget goes **negative** at one (min −1.3e−5 W/K) — the cold-soaked-core point where
the residual Ti bus has already spent the whole allowance by itself.
Two objections were tested and neither rescues it: at the leg-only fill-factor lower bound (κ_eff 0.4)
the 8×8×4 still fails at −5.49 °C, and the bus diameter cannot move it either — widening the canon rod
Ø1.0 to the fattest it could physically be (the Ø1.35 channel) moves the 8×8×4 case −9.75 → −9.82 °C,
because the module out-conducts the whole anchor either way.
⚖️ **The honest residual, stated rather than buried:** at exactly the budget a bespoke sub-mm² micro-TEG
still yields ~774 µW — *above* HW.21's own 50–200 µW winter target — but at zero gate margin, and its
V_oc is ~9.8 mV, **×61 below BQ25570's VIN(CS) 600 mV** (HW.46), so it would need a mV-class transformer
harvester, not a BQ25570-class part. That is a different project, not a module choice. Note also the
thermal impedance match: power peaks at G_TEG 9.0e−3 W/K (≈4.4×4.4×3 mm, 1347 µW) and **falls** for larger
modules — 40×40×3 gives 17× *less* than 8×8×4 — so "buy a bigger TEG" loses on both axes at once.
> ⚖️ **Re-run 2026-10-12 on the ratified insertion (`00_07` HW.26 G1, gap 6 → 18 mm) — the verdict held and
> STRENGTHENED in its one qualitative clause.** At the 6 mm gap the asymptote sat 0.11 °C from the solid
> reference («reverts to precisely pre-PEEK»); at 18 mm it is past it. The wider gap also lowered the
> baseline every module adds to (Ti bus −0.70 → +0.52 °C), which is why the budget and the micro-TEG yield
> both GREW (1.1e−3 → 1.9e−3 W/K, 428 → 774 µW) and the negative-budget points fell from 6 to 1 — none of it
> moves the verdict, because the smallest catalogue part still conducts ×16 the budget.
This is the same structural shape as the already-ratified `HW.42`: there the power that helps is the
power that poisons `delta_t`; here **the conductance that harvests is the conductance that kills the
break**. Neither is a budget problem, so no number moves either.

⚠️ **Hypothesis, not measurement** ([`00_06 §0`](../../../00_06_SSOT_Documentation_Standard.md) Validation
Gate). What the 1D ladder structurally cannot see: **3-D spreading** (a flat plate on a Ø11–15 mm
cylinder — the ladder assumes the whole footprint is thermally engaged, overstating G_TEG, and equally
misses the lateral bark/air bypass); **contact resistance** (collars, straps, TIM and both alumina faces
are all zero here — a real 50 mm Al strap is ~0.08 W/K, the same order as the module, so the `sleeve`
mount especially is an idealisation; adding them shrinks *both* sides of the trade rather than rescuing
it); **the module's own leg geometry** (fill factor, leg aspect ratio, ceramics and the Peltier/Thomson
back-reaction under load are folded into one κ_eff and one ZT); and **transients / seasonal reversal**
(steady state only — the summer inward-heat desiccation of `01_01 §4.1` and freeze-thaw cycling are
invisible, and a permanently installed conductive plate makes both worse). 16 of the 48 grid points are
degenerate (reservoir at or below the gate). Bench (Cherkasy winter) + conjugate 3-D FEA remain the only
things that can turn any of this into a measurement. (`mechanical/teg_across_peek_break.json`)

---

## HW.22 — Does the ZIF Nanozyme Radiosensitise the Enzymes under Co-60? (script 65)

Spec home → [`01_04 §6.2`/`§6.3`](../../../01_04_CODIT_and_Xylemointegration.md); decision → `00_07` HW.22.

The low-dose gamma row of the sterilisation matrix carried an open blocker: heavy metals (Ce/Co/Cu) are
radiosensitisers, so the ZIF nanozyme might make radiation damage **worse**, and if so the enzymes must
be loaded aseptically **after** the Co-60 pass. That is a factory-flow decision, not a parameter — Гілка
A currently sterilises the **loaded** anchor. Closed-form transport answers it without a lab slot.

**Q1 — the deposition is not local.** At 1.25 MeV the interaction is Compton; integrating the
Klein–Nishina differential cross-section gives a mean energy-transfer fraction
0.471, i.e. a **588 keV** secondary electron whose CSDA range
(Katz–Penfold) is **2.05 mm** at unit density. Every layer in the stack — an 80 nm ZIF
nanocrystal, a 1 µm aggregated film, the whole 20 µm membrane — is at most **1 %** of that range, i.e. a
Bragg–Gray cavity whose dose is imposed by the electron fluence arriving from the surrounding medium. A
local excess of photon interactions inside the film **cannot** raise the dose there.

**Q2 — and the coefficient moves the wrong way anyway.** Per unit *mass*, Compton absorption tracks the
electron density `<Z/A>·N_A`, and `<Z/A>` **falls** with atomic number. Canon does not fix the node
stoichiometry of `nCoCuCeZIF`, so the sweep brackets it rather than inventing one — the all-Ce node is
the physical upper bound on `<Z>` for anything the name can mean.

| material | `<Z/A>` | `<Z>` | DEF vs water | verdict |
|---|---|---|---|---|
| water (dose reference) | 0.5551 | 7.2 | **1.000×** | no enhancement |
| protein (laccase, avg. residue) | 0.5344 | 6.4 | **0.963×** | no enhancement |
| MWCNT support | 0.4995 | 6.0 | **0.900×** | no enhancement |
| ZIF-8 (Zn node, parent framework) | 0.5097 | 12.9 | **0.918×** | no enhancement |
| ZIF (Co node) | 0.5110 | 11.6 | **0.921×** | no enhancement |
| ZIF (Cu node) | 0.5094 | 12.5 | **0.918×** | no enhancement |
| nCoCuCeZIF (equimolar Co/Cu/Ce nodes) | 0.4965 | 19.4 | **0.894×** | no enhancement |
| ZIF (all-Ce node — UPPER BOUND) | 0.4763 | 30.1 | **0.858×** | no enhancement |
| Ti-6Al-4V substrate (context) | 0.4596 | 22.0 | **0.828×** | no enhancement |

**Q3 — the falsification margin.** The photoelectric and pair channels are Z-dependent and are *not*
computed. Rather than assert they are negligible, invert: at the 0.858× upper bound a
non-Compton channel would have to supply **14.2 %** of the ZIF's total mass energy absorption
(and ~0 % in water) merely to reach DEF 1.0 — and would then still have to beat Q1, which is geometric
and indifferent to any coefficient. 🔑 **The BINDING figure is tighter than the bound, because a lab
measures the real nanozyme:** for the material canon actually names (`nCoCuCeZIF`, DEF 0.895) the bar
is **10.6 %**, and that is the number a lab check of this caveat must exceed.

**Q4 — why the kV literature does not transfer.** A 50 keV photoelectron ranges **40 µm** —
the scale of the structure being protected, so energy released at the metal centre is deposited on it.
At 1.25 MeV the range is **×52** larger, smearing the same energy over ×1e+05 the volume.
Dose enhancement is a **locality** phenomenon and Co-60 destroys the locality.

**Verdict** — 🟢 **Physical radiosensitisation rejected; `01_04 §6.3` Гілка A stands as written** (gamma on
the loaded anchor). ⚠️ **The residual is chemical, not dosimetric:** redox-active Ce/Cu/Co can turn
radiolytic H₂O₂ into hydroxyl radicals by a Fenton-like route, no photon-transport argument touches it,
and its **sign is open** — the same nanozyme is chosen for SOD/catalase-like activity (`01_03 §2.2`), so
it may scavenge as readily as amplify. It is measured directly by the Гілка A activity assay already in
the plan, which `§6.5` now requires to be run **with and without the ZIF**. (`kinetics/zif_radiosensitization.json`)

⚠️ **Hypothesis, not measurement** ([`00_06 §0`](../../../00_06_SSOT_Documentation_Standard.md)). Structurally
blind to: the chemical channel above, dose-rate effects, and the packaging environment (blister, N₂) that
sets how much water is there to radiolyse.

---

## HW.3 — Does the Synthetic Xylem Sap Precipitate Its Own Chelator? (script 67)

Spec home → [`01_02 §2.1`](../../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md); decision ⚖️ founder 2026-09-17 — oxalate
removed, the recipe is now a point (Q6); ⚖️ founder 2026-10-18 — that point revised onto measured conifer sap (Q7, the
live recipe). Q1–Q5 below price the ranges the first point replaced and stay its ground; Q6 stays as the price the
revision is read against.

The recipe was written as ranges until then — malic acid 1–5, oxalic acid 0.5–2, KNO₃ 2–5, CaCl₂ 0.5–2, MgSO₄ 0.2–1 mM —
and two tests run in it: the Stage-2 coin electrochemistry (pH 4.5–5.5, 20–25 °C,
[`01_03 §3.5`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md); the lab letter names the union of canon's two pH
bands) and the 12-week accelerated corrosion test (pH 5.0–5.5, 20–40 °C cycle). A range is a claim about a
set of solutions, and calcium oxalate is among the least soluble salts in biology, so the set was checked for
members that exist: speciation at fixed pH with the neutralising base as an unknown, Davies activities, every
corner of the ranges × each test's pH and temperature band.

**Constants — each read from its primary, and pinned where it can be misread.** Oxalate protonation, the Ca/Mg
oxalate complexes and the three calcium oxalate hydrates: NEA-TDB Vol. 9 (Hummel et al. 2005), selected values
plus their documented spread (the accepted determinations of Table VI-18 where NEA lists several, the stated
uncertainty otherwise). Malic acid: the Eden & Bates (1959) temperature equations — the scan's text layer reads
1355.85 / 1655.53 for 1358.85 / 1658.53, a 0.01 error in pK₁, so the script holds both equations to the 25 °C
constants printed beside them. Sulfate ion pairs and gypsum: WATEQ4F as distributed in PHREEQC `wateq4f.dat`,
each analytic expression checked against its own `log_k` line. A(T) for Davies: NEA TDB-2 Table 2. The solver
matches a closed-form reduced system to machine precision.

**The constant that does not exist.** No open primary gives the calcium or magnesium malate complex at I = 0.
The only measured values are **apparent** constants (Günzel, McGuigan & Schlue 2005: Kapp 10.32 mM for Ca at
I = 0.124 and 15.85 mM for Mg at I = 0.104, Na⁺ medium, pHa 7.4) — log K′ 1.99 / 1.80, or 2.90 / 2.67 after a
Davies correction to I = 0 that the script derives from beyond that equation's stated range. None is elected.
The sign of each effect needs no value, but it has to be followed through **both** channels a complex acts on —
the first draft of this argument followed only one, and review caught the other. By mass action a calcium ligand
lowers free calcium (SI down) while a magnesium ligand frees oxalate (SI up); by ionic strength a neutral complex
takes two divalent ions out of solution and raises the activity coefficients of Ca²⁺ and ox²⁻ (SI up). For
calcium the first channel wins; for magnesium both push the same way and peak together when every magnesium ion
is held as a neutral complex that binds no oxalate. So the **hard bound** — no calcium malate, magnesium
sequestered and oxalate-inert, every oxalate constant at its SI-raising end — bounds the SI from above whatever
the malate constants are. That is asserted rather than argued: at every corner, against every documented reading
(margin ≥ 0.015) and against calcium and magnesium malate swept from log K 1 to 8, and its window is asserted the
narrowest. The readings then price the missing constant instead of hiding it. ⚠️ Not covered: background ion
pairs with no constant in the sources used (K⁺ or Na⁺ with malate, KNO₃(aq)) lower the ionic strength too.

**Q1 — every canon corner is supersaturated.** SI of whewellite over all corners of the recipe:

| test (its band) | NEA-selected constants | SI-lowest documented reading | hard bound |
|---|---|---|---|
| coin (pH 4.5–5.5, 20–25 °C) | **+1.19** … +2.49 | +0.90 … +2.35 | +1.48 … +2.64 |
| accelerated (pH 5.0–5.5, 20–40 °C) | **+1.03** … +2.49 | **+0.72** … +2.35 | +1.33 … +2.64 |

Weddellite and caoxite are supersaturated at every corner under every reading too; gypsum is not (SI ≤ −1.6).
Under the NEA-selected constants the least-supersaturated corner is malic 5 · oxalic 0.5 · KNO₃ 5 · CaCl₂ 0.5 ·
MgSO₄ 1 mM at the band's lowest pH and warmest temperature; the most, malic 1 · oxalic 2 · KNO₃ 2 · CaCl₂ 2 ·
MgSO₄ 0.2 mM at pH 5.5, 20 °C.
**How wrong the constants would have to be:** with every oxalate constant at its SI-lowering end, a corner turns
undersaturated only if whewellite log Ks at 25 °C reaches **−7.95** (NEA selects −8.73 ± 0.06), or calcium malate
log K° reaches **3.98** — 1.09 above the strongest documented reading, which is itself derived — with malate then
holding 90 % of the calcium (accelerated test; the coin test needs 4.17 and 94 %).

**Q2 — the admissible window.** For each canon level of one ion, the largest total of the other with
SI(whewellite) ≤ 0 in every condition of the test's band, worst case over the other three components:

| held at a canon level | **hard bound** (needs no malate constant) | NEA-selected, no malate complexes | NEA-selected + Günzel at I = 0 (derived) |
|---|---|---|---|
| Ca 0.5 mM → total oxalate ≤ | **7.3 µM** | 11.6 µM | 13.4 µM |
| Ca 1 mM → total oxalate ≤ | **4.7 µM** | 7.3 µM | 8.1 µM |
| Ca 2 mM → total oxalate ≤ | **3.3 µM** | 5.1 µM | 5.4 µM |
| oxalate 0.5 mM → total Ca ≤ | **7.4 µM** | 10.6 µM | 12.6 µM |
| oxalate 1 mM → total Ca ≤ | **4.7 µM** | 6.5 µM | 7.5 µM |
| oxalate 2 mM → total Ca ≤ | **3.3 µM** | 4.7 µM | 5.1 µM |

For the hard bound and the NEA-selected column the binding condition is malic 1 · KNO₃ 2 · MgSO₄ 0.2 mM at pH 5.5
and 20 °C — inside **both** bands, so the two tests share one window (the Günzel column binds at pH 5.0 in most
slots). Whichever ion is held, the other lands ×68–151 below its canon floor; the boundary between the two
directions is a continuum (`cache/chemistry/sap_recipe_saturation.png`). **This chemistry prices the pH verdict
rather than forcing it:** held at ONE set-point over every test temperature, the hard-bound window is at pH 4.5
×1.13–1.23 wider and at pH 5.0 ×1.03–1.05 wider than the both-tests window above, which pH 5.5 sets. ⚠️ A window
edge is the saturation point itself, not a margin.

**Q3 — the base the recipe does not name.** Reaching the set-point takes **2.0–13.0 mM** of strong base; as KOH
it makes K⁺ **4.0–18.0 mM**, against the 2–5 mM KNO₃ the table calls the dominant cation. Its identity barely
touches saturation (NaOH instead of KOH moves SI by < 0.0005), but at its upper end it is the largest ionic
ingredient of the medium, so a confirmed recipe has to name it.

**Q4 — what cutting oxalate costs in buffering.** Buffer capacity β (mM per pH unit) at 25 °C, KNO₃ 2 · CaCl₂ 0.5 ·
MgSO₄ 0.2 mM, at pH 4.5 / 5.0 / 5.5:

| malic acid | oxalate 0.5 mM (canon) | oxalate 2 mM (canon) | oxalate 7.3 µM (window) | no oxalate |
|---|---|---|---|---|
| 1 mM | 0.88 / 0.75 / 0.46 | 1.52 / 1.05 / 0.56 | 0.69 / 0.67 / 0.44 | 0.68 / 0.67 / 0.44 |
| 5 mM | 3.43 / 3.34 / 2.04 | 4.09 / 3.61 / 2.10 | 3.23 / 3.26 / 2.02 | 3.23 / 3.26 / 2.02 |

A window-level oxalate buffers like none at all, so cutting it costs **0.9–55 %** of β — least at malic 5 mM with
0.5 mM oxalate at pH 5.5, most at malic 1 mM with 2 mM oxalate at pH 4.5 — and removes the chelator the recipe
lists as "active at pH 5.0" as a reagent. **Cutting calcium instead** puts the recipe's "structural cation of the
cell wall" at micromolar, and keeps a second solid in play: with oxalate at 2 mM and MgSO₄ at 1 mM, magnesium
oxalate reaches SI **−0.37** at the window edge against NEA's scoping solubility product (−6.4 ± 0.2, for which
"no value is recommended") — undersaturated on the only number available, by less than twice its stated
uncertainty.

**Q5 — how far the constants move the window.** Each reading's partner maximum over the hard bound's, across both
tests, both directions and all three levels:

| reading | window ÷ hard bound |
|---|---|
| NEA-selected, no malate complexes | ×1.40–1.58 |
| + Günzel apparent constants read as I = 0 | ×1.42–1.62 |
| + Günzel constants corrected to I = 0 (derived) | ×1.55–1.82 |
| oxalate constants at their SI-raising end, no malate | ×1.04–1.21 |
| oxalate constants at their SI-lowering end, no malate | ×1.74–1.97 |
| SI-highest documented reading (SI-raising oxalate ends + Günzel magnesium malate at I = 0) | ×1.04–1.18 |

The rows bundle effects, so the malate readings' OWN share is taken against the NEA-selected window they are added
to: the apparent constants add ×1.01–1.03 and the I = 0 constants ×1.06–1.19, while the documented spread of the
oxalate constants, end to end, moves it ×1.54–1.77 — **the missing constant matters less than the constants we
already have**, so chasing it is not what would widen the recipe. No reading comes within an order of magnitude of the canon ranges.

**Q6 — the point of 2026-09-17, superseded 2026-10-18 by Q7** (⚖️ founder 2026-09-17: oxalate out; malic acid 2.2 · KNO₃ 3.2 · CaCl₂ 1.0 · MgSO₄ 0.45 mM,
each the geometric mid of its old range, asserted by the script; pH 5.75 — the measured *P. sylvestris* sap pH,
Tarvainen et al. 2023 — with a pH 4.5 side series of uncoated coupons under ICP-MS only). Over every documented
reading and every temperature of the tests each condition belongs to:

| condition | KOH to reach it | K⁺ total | β at 25 °C | strong acid for −0.1 pH |
|---|---|---|---|---|
| pH 5.75 (coin 20–25 °C · accelerated — 40 °C isotherm, ⚖️ 2026-09-24) | **4.09–4.15 mM** | 7.29–7.35 mM | **0.61 mM/pH** | 0.066 mM |
| pH 4.5 (coin side series, 20–25 °C) | **2.57–2.72 mM** | 5.77–5.92 mM | **1.45 mM/pH** | 0.14 mM |

Gypsum stays far from saturation (SI ≤ −2.2), and with oxalate gone no calcium oxalate hydrate can form. The
number that matters is the last column: at the set-point a few hundredths of a millimole of acid move the pH by a
tenth, and a working anode produces acid — the model does not say how fast, so the figure is a scale, not a drift
prediction — which makes medium replacement and a pH log conditions of the test rather than good practice.

**Q7 — the revised point, the live recipe** (⚖️ founder 2026-10-18, refined the same day): calcium, magnesium and
potassium at the geometric mid of measured Norway-spruce sap at the BOTTOM OF THE STEM, natural stands — every
«bottom of the stem» row of Dambrine et al. 1995, Table 1, except the fertilized plot; nitrate at the mid of the
Scots-pine shoot-sap range read off Henriksson 2012, Fig. 1; malic acid not measured but solved, so that KOH to pH 5.75
(at 25 °C, on the selected constant readings) plus the potassium of KNO₃ gives the measured-mid potassium. Malic acid **0.40** · KNO₃ **0.0049** · CaCl₂ **0.18** · MgSO₄ **0.062** mM, the
derivation asserted by the script:

| Q7 condition | KOH to reach it | K⁺ total | β at 25 °C | strong acid for −0.1 pH |
|---|---|---|---|---|
| Q7 · pH 5.75 (coin 20–25 °C · accelerated — 40 °C isotherm) | **0.730–0.738 mM** | 0.735–0.743 mM | **0.13 mM/pH** | 0.014 mM |
| Q7 · pH 4.5 (coin side series, 20–25 °C) | **0.424–0.433 mM** | 0.429–0.438 mM | **0.31 mM/pH** | 0.032 mM |

Against Q6 at the set-point: ionic strength **×0.135**, buffer capacity **×0.22**, potassium **×0.10**. Two things the
table does not say. The first point's ionic strength was about seven and a half times higher, so every reading of
solution resistance — the coin test's `R_int` gate and the R_Ω bench that fills the anode gap with this sap — read
optimistic on exactly the gated numbers. And the buffer is now four to five times weaker, so a working anode acidifies
its medium faster (script `85` moved with it). ⚠️ The ions are Norway spruce's, not Scots pine's, and in which direction spruce errs for pine
on sand is not established — in Dambrine's table only the fertilized plot, now excluded, runs higher — and dissolved
CO₂, a buffer real sap may carry, is not in the recipe; the remedy is measuring the sap of our own pine logs
(`00_07` HW.3). The recipe stands on pine data; since 2026-10-18 the broadleaf and oak anchor parts are computed on the beech point Q8 instead (§HW.5.IS, the anchor anode — both as proxies), and the wet tests stay on pine.

**Verdict** — 🔴 **The pre-verdict recipe had no member that is a stable solution.** Every corner of both tests'
bands is supersaturated to all three calcium oxalate hydrates, by a margin no documented constant closes. The
hard-bound window was the machine half of HW.3; which ion to lower was ⚖️, priced in Q2–Q4, and the founder
removed oxalate on 2026-09-17 — its price is the buffering Q4 measures and the chelator the recipe no longer
carries; what that point took is Q6, and what the revised point takes is Q7. (`chemistry/sap_recipe_saturation.json`)

⚠️ **Hypothesis, not measurement** ([`00_06 §0`](../../../00_06_SSOT_Documentation_Standard.md)). Structurally
blind to: precipitation kinetics and the metastable zone — a supersaturated flask that has not clouded yet is
exactly the case this criterion exists to reject; the composition of real *Pinus sylvestris* sap (no primary
measurement in the tree); phytosiderophores and calcium malate as a solid (no constants in the sources used) and
atmospheric CO₂ (not in the constant sets); background ion pairs with no constant, whose ionic-strength channel
the hard bound does not cover; and the Davies activity model, although the largest ionic strength met,
0.030 mol/L, sits well inside its stated range. The MD sap profiles in `lib/xylem_sap.py` list the same
calcium/oxalate pair at millimolar levels, but script 14 builds its box from a profile's pH and ionic strength alone,
filling it with Na⁺/Cl⁻ — the pair never entered a simulation, and a profile is not a medium anyone can prepare.
⚠️ Those profiles' seasonal pH course (winter 4.5 → summer 5.5) also runs OPPOSITE to the measured conifer course —
sap turns more alkaline in winter (Pramsohler 2022; Losso 2018) — so any pH-dependent MD read off them inherits
the inverted season; the recipe's set-point no longer rests on them (`01_02 §2.1`).

---

## HW.5.IS — The pH at the Coin Electrodes' Faces under Their Own Current (script 85)

Leg → [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.5.IS, «оцінка інтерфейсного ΔpH на катоді» — its **coin
half**; the anchor cathode waits on HW.53, which decides what electrolyte it sees at all. One anchor number is here,
conditional — the anode with sap in its gap (the leg «pH на грані АНОДА в анкері», paragraph below). Mechanism →
[`01_03 §3.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md), the BOD row: laccase in ZIF inactivates at pH ≥ 6.

⚖️ **Decided since 2026-10-12 — the founder ratified the buffered medium** (sap salts with malic acid at 10 mM, pH 4.5,
in the cathode's own compartment; convection named by the laboratory; verdict, price and weakest link —
[`01_03 §3.5`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)), and the letter now names it. The paragraph below is the
question as this script priced it, kept as the ground of that verdict.

**What the letter left open (until 2026-10-12).** The Stage-2 letter said «Cathode medium: pH 4.5, air-exposed.» and named no
composition; the ratified sap is 5.75 for the electrode tests and 4.5 only for the uncoated ICP-MS series
([`01_02 §2.1`](../../../01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md)). Nor does the letter fix the convection. The laboratory
chooses, and the script prices three choices: the sap brought to 4.5; the sap at 5.75, which is where the cathode sits in
a one-compartment cell; and a buffered cathode medium — the sap's salts with malic acid at 10 mM, pH 4.5. A standard
laccase buffer (citrate or acetate near 0.1 M) is not computed.

**The equation (the leg forbids reproducing the FEM of its source).** A steady Nernst layer, acid–base equilibrium
everywhere, no migration: the proton flux a face at pH_s receives is Σ D_k·Δc_k/δ over the bound protons (67's own
speciation, every documented malate reading) and free H⁺. The ORR consumes one proton per electron; FAD-GDH through the
Os polymer releases one (1.5 only if the gluconolactone hydrolyses inside the layer — the unlikely end). **Control** —
Liu … Mazurenko (*J. Am. Chem. Soc.* 2026, doi:10.1021/jacs.6c15657), whose SI gives one interfacial pH at a stated
current, read off the axes of Fig. S4: ≈ 5.59 at the centre of a 300 µm bilirubin-oxidase disk at ≈ 65.6 µA/cm², 10 mM
citrate pH 5.4, air. A film with their constants and zero net citrate flux gives **5.604**, and the single-D form used
below, run at their lowest and highest species D, brackets it (5.556–5.647). The control's resolving power is that a
±0.05 pH band holds δ between 0.69 and 1.18 of the radius — it rules out a missing buffer term or a factor-2 error, not
a 20 % one — and it is the linear regime only: in their 1 mM buffer the FEM redistributes current over the disk.

**Constants — read, not typed.** H⁺ and the succinate stand-in from limiting conductances (Apelblat & Barthel
1991/1992, Nernst–Einstein); O₂ diffusion from the formula in Han & Bartels 1996 — its abstract, the one reading in
hand; O₂ at air saturation from the USGS table on Benson & Krause. **Malate's own D was not found**: it is bracketed
between hydrogen citrate (larger anion, as Liu model it) and hydrogen succinate (smaller). The succinate value is a
best-fit its source flags and likely high — and it is the end that delays the cathode face's crossing of pH 6, so the bracket
errs toward «less risk». Unstirred aqueous layers are 150–1000 µm (Katona et al. 2021's review).

**Cathode — a fraction of its own O₂ limit.** O₂ crosses the same layer, so the fraction f of the O₂ transport limit at
which the face reaches pH 6 depends on the hydrodynamics only through the exponent of D in each flux — stagnant,
convective or transient (a CV, a recessed window's first hours) moves the low corner 0.22 → 0.20 → 0.21 in the sap at
4.5 — out of order there, because with so little malate free H⁺, which diffuses faster than O₂, carries most of
the supply (62 % at the low-D corner; in the buffered medium, where malate carries the protons, the order holds) — and far more on malate's D, which
nobody has measured:

| cathode medium | f at pH 6 | at the O₂ limit |
|---|---|---|
| the sap brought to 4.5 | **0.20–0.33** · citrate-like D 0.20–0.23, succinate-like 0.27–0.33 | crosses pH 6 first in 84 of 84 corners, and in 84 corners the malate is spent first — no corner reaches the O₂ limit inside the model |
| the sap at 5.75 (one compartment) | **0.01–0.02** | crosses pH 6 first in every corner |
| buffered: malic acid 10 mM, pH 4.5 | **2.09–5.67** | never crosses; the face is at pH 4.7–5.0 |

So in the sap at 4.5 the face crosses pH 6 at a fifth to a third of the O₂ transport limit whatever malate's D — the
revised sap (⚖️ 2026-10-18, a fifth of the old buffer) took the margin the first recipe left at the succinate-like
end; whether a given cathode draws even that much is its own kinetics — a CV plateau can be enzyme-limited. In a
one-compartment cell the face crosses at 1–2 % of the limit; the buffered medium keeps it about 1 pH unit below. The
cold-start load B (25 µA on the 2 cm² face) reaches pH 6 in the sap at 4.5 once δ ≥ 0.33–0.52 mm — inside the range of
unstirred layers.

**Anode — a thickness.** At L4's predicted current for the hold (369 µA/cm², the pH-7.4 laboratory ceiling `J_MAX_25C`)
its face leaves the acid end of the enzyme's measured stability band (pH 4.5, Sygmund 2011) once δ exceeds
**8–17 µm** (12–17 µm at one proton per electron); at the pH bracket printed beside that ceiling (213–251 µA/cm²) once δ
exceeds **12–29 µm**. Unstirred layers are 150–1000 µm. The face drops below 5.5 — the acid end of the only measured pH
pair of the enzyme's kinetics, i.e. out of the L4 bracket itself — once δ exceeds 0.6–2.8 µm. Glucose transport, not
computed here, may cap the current in thick layers first; either way an unstirred cell cannot carry the ceiling current
with the face inside the band. If the anode does approach that current, A's glucose series and C's hold measure the
medium's buffer together with the enzyme. The coatings' own transport resistance comes on top, and stirring cannot
remove it.

**The anchor's anode — conditional on stagnant sap in its gap (2026-10-17; revised the same day after an adversarial pass — the first version read only the pine part, judged it against the coin letter's load point and called the currents upper bounds without the effects that push the other way; every number moved with the revised sap of 2026-10-18, whose buffer is a fifth of the first recipe's).** In the anchor the gyroid stands in the Ø15 bore that also takes the sleeve; on the pine part (envelope Ø11, **13.8 cm²** of side) the gap is **2.0 mm** (both from the CEMs; one sleeve manifest serves every Zone-1 part, so the gap narrows as the lattice thickens). Which of three states a living stem keeps there — sap, air or ingrown wood — is not known, and the HW.53 bench cannot say: it fills the gap with the recipe by hand, so it SETS that state rather than measuring it. With the ratified sap (the revised point, `01_02 §2.1`) lying stagnant in the gap and the bulk at the bore wall, steady radial diffusion gives a film of r_a·ln(r_b/r_a) = **1.71 mm** per unit of envelope on pine. The yardstick is the anchor's own cold-start draw, P_IN(CS)/V_IN(CS): 25.0 µA typical and **21.4** µA at the worst-case column the Stage-2 gates judge (`02_03 §1.5`). On pine the face leaves the enzyme's kinetic bracket (pH 5.5) at **1.9–5.2 µA** for the whole anode (the low end the envelope alone, the high end with the bottom cap at the envelope's flux density) — below the worst-case draw in every reading — and its stability band (pH 4.5) at **23.8–53.2 µA**, above it in every reading. By part — each in its own sap since 2026-10-18 (⚖️ founder): broadleaf and oak in the beech point of `67` Q8 (European beech at the bottom of the stem, Glavac et al. 1990; pH **5.95**, buffer **0.202** mM/pH — ×**1.53** the pine point's; both as proxies — broadleaf is birch and maple, and no *Q. robur* or *petraea* trunk sap was found for oak), every other part in the pine recipe (tropical and mangrove: their own sap is not modelled). Every pine-sap part, and broadleaf, crosses pH 5.5 below the worst-case draw in every reading; oak only in some, from **6.5** µA. No part crosses pH 4.5 below the worst-case draw in any reading — broadleaf, the one that did in pine sap, starts at **26.9** µA in its own — and at the typical 25 µA draw pine and its two topology variants do in some. ⚠️ The beech point's malate is SOLVED from potassium, which credits all of it to malate — a ceiling on that side, since real sap also balances potassium with nitrate, sulphate and amino acids — while calcium and magnesium sit on unbuffered chloride and sulphate and the CO₂, phosphate and amino-acid buffers are absent; so the direction of the broadleaf and oak currents' error is not established. And its one pH hides the paper's own summer dates (25 May, 6 and 20 July), when the trunk-base pH falls — coinciding, the paper says, with its highest nitrate (unpublished): medians **4.52**–**4.58**, the lowest tree **3.81** — the bulk is then below the kinetic edge and at the stability edge before any current. Oak's own trunk sap, read the same day (Van Die & Willemse 1975 — *Q. rubra*, two trees, free outflow from a stem cut, late October): pH **4.9**–**5.0** — below the kinetic edge before any current, **0.4**–0.5 above the stability edge — where beech in September–October stands at **6.15**–**6.62**; on bulk pH the beech point is the kinder reading for oak, while oak's own buffer is not known (its potassium is 2.4× Q8's, no organic acid measured), so what a current does in it is not computed. Oak stays on Q8 (⚖️ founder 2026-10-18) until *Q. robur* trunk sap or oak's organic acids are found. **Which side.** Against the enzyme inside the lattice the currents are upper bounds: protons are made inside it, which the envelope film does not see, and the wood wall adds its own resistance. Migration (a few per cent), any flow through the gap and a CO₂/HCO₃⁻ buffer the recipe lacks push the other way and are not in. In a film this thick the lactone has about an hour to hydrolyse inside it, so the n_H = 1.5 end is no longer the unlikely one it is on the coin; acid made inside the film moves the face less than acid made at it, so the truth lies between the two n_H ends. **What it says:** with stagnant sap in the gap, the anchor anode works below the pH at which its kinetics was measured already at its cold-start draw — on every part, oak in some readings — and at the worst-case draw no part reaches the acid end of its stability band; but in the beech sap both parts sit on, on its summer acid dates, the bulk itself sits at that edge with no current at all — and oak's own sap stands below the kinetic edge. Whether it stays inside the stability band after cold start depends on its working current — the EBFC's own P–V curve, which HW.13 measures. An air gap is not modelled (`84`: layer 1 then runs through contact points only), and ingrown wood is not computed (no transport data for living sapwood in the tree).

⚠️ **Hypothesis, not measurement** ([`00_06 §0`](../../../00_06_SSOT_Documentation_Standard.md)). Every shift is a
**lower bound at the enzyme**: protons are made or consumed under the anode's hydrogel and membrane and inside the
cathode's porous layer, which the outer-face film does not see. Not computed: migration (its sign helps the anode; for
the cathode it brings H⁺ in and takes hydrogen malate out), salting-out of O₂ in test D's NaCl steps (raises f), the
anode at 20 °C, and whether a face at pH 6 inactivates laccase reversibly. The letter now specifies the buffered
cathode medium, the convection and a day-0 diagnostic CV of the anode (⚖️ founder 2026-10-12,
[`01_03 §3.5`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).

---

## HW.5.IS — How Hard Does the Cathode Medium's Malate Pull on the Nanozyme's Metals? (script 93)

The buffered cathode medium (malic acid 10 mM in the sap's salts, pH 4.5 — ⚖️ founder 2026-10-12, `01_03 §3.5`) carried
a weakest link with no number: malate chelates the ZIF's metals. `93` computes the **side-reaction coefficient α** of a
trace metal in that medium — how many times the malate raises the dissolved metal over a non-complexing buffer at the
same pH and ionic strength — from every constant set read in its source (NIST SRD 46 critically selected values ·
Zabiszak 2021 · Buzko 2004, plus the questionable β₂ of Ce's La/Pr neighbours and the secondary Ce values Buzko cites),
with pH 4.5 read three ways (p[H] and activity at the source's I, activity in the medium itself from `67`'s speciation of
`85`'s medium) and over every documented Ca/Mg–malate reading.

| metal | α (all readings) | of which |
|---|---|---|
| Co(II) | **3.6 – 15** | weakest in every reading |
| Cu(II) | **10 – 280** | NIST 46 critical: 10 – 32; the top is Zabiszak 2021's model (no CuL) |
| Ce(III) | **60 – 3200** | the one read measurement (Buzko, no β₂): 60 – 230; with the neighbours' questionable β₂ to ≈ 2800; the secondary 5.23 to ≈ 3200 |

So malate pulls hardest on **Ce**, the metal the verdict's weakest link did not name; the Cu and Ce brackets overlap.
Competition barely moves it: the Ca/Mg–malate readings shift free malate by ≤ 1.1 %, K–malate (not in `67`) by ≈ 2 %. (Numbers on the salts of the revised sap, 2026-10-18 — the lower ionic strength raised the α read at the medium's own I by 10–34 % and the per-metal maxima by 10–28 %; the readings at the source's I are unchanged.) The
Davies step to the medium's I is derived and checked on NIST's own I = 0 rows (worst miss 0.08 over 0.1 → 0; the medium
step is 0.50 of that).

⚠️ **Bounds.** α is an equilibrium, not a leaching rate: the framework's solubility, its proton-driven breakdown and
the imidazole it releases are outside it. It is the trace-metal limit — the Cu dimer (NIST 46) reaches 10 % of CuL at
≈ 13 µM free Cu (≈ 15 mg/L dissolved). Constants keep their source's temperature (no ΔH). Cache:
`chemistry/malate_metal_chelation.json`.

---

## HW.24 — How Many Replicate Coupons per Arm? (script 100)

`01_03 §3.5` leaves the number of replicate coupons per arm «after the lab's prices». `100` turns it into a choice of a
row by price, under an **assumed** coupon-to-coupon spread: log-normal, one CV in every arm, power and pass probability
0.80, two-sided α 0.05. No coin has been measured; the lab's stated repeatability of repeated scans on one coupon
(test A) is a floor on the CV, not its value. Where the spread is estimated is itself a bracket of two readings:
**own** — from the coupons of the contrast or the arm (robust if the arms' spreads differ) ⊥ **pooled** — over every arm
that measures the same quantity (the eight arms of the hold C for the 30-day retention, the seven titanium-cathode arms
for a day-0 cathode current), valid only if they share one CV. Ratios below are rounded up (a contrast is detected
only above it), CV ceilings and probabilities down. A seeded Monte Carlo of the same decision rules checks every
closed form in both readings.

**Two arms** — a two-sample t-test on log values (the matched ZIF pair on Ti-6Al-4V · two alloys · the cathode on gold
against titanium): the smallest ratio of the two arms' geometric means it detects, own ⊥ pooled.

| n per arm | CV 10 % | CV 20 % | one coupon against n, CV 10 % | CV 20 % |
|---|---|---|---|---|
| 2 | ×1.76 ⊥ ×1.38 | ×3.07 ⊥ ×1.89 | ×7.36 ⊥ ×1.50 | ×52.56 ⊥ ×2.22 |
| 3 | ×1.36 ⊥ ×1.28 | ×1.84 ⊥ ×1.63 | ×1.92 ⊥ ×1.42 | ×3.65 ⊥ ×2.00 |
| 4 | ×1.27 ⊥ ×1.23 | ×1.61 ⊥ ×1.51 | ×1.61 ⊥ ×1.39 | ×2.57 ⊥ ×1.92 |
| 5 | ×1.23 ⊥ ×1.20 | ×1.50 ⊥ ×1.44 | ×1.51 ⊥ ×1.38 | ×2.27 ⊥ ×1.88 |
| 6 | ×1.20 ⊥ ×1.18 | ×1.43 ⊥ ×1.39 | ×1.47 ⊥ ×1.37 | ×2.13 ⊥ ×1.86 |

A smaller difference reads «≈» by default, not by measurement — and the cathode-lever rule (`01_03 §3.2`) acts on
«≈»: branch (3) on «the nanozyme arm ≈ the arm without it», branches (1)/(2) on «the cathode on gold ≈ on titanium».
The gold coupon is single by the coupon letter, and a single coupon's own spread never averages out: with any number of
titanium coupons against it and the spread known exactly, its contrast stays above ×1.32 at CV 10 % (×1.74 at CV 20 %).

**Gates C · D · E** — three readings of «≥ threshold»: the arm's geometric mean · its one-sided 95 % lower confidence
bound · every coupon. Canon judges by the arm mean with the bound printed beside it (⚖️ 2026-10-20, `01_03 §3.5`); all
three stay here because the choice was priced on them. The three readings move apart with n — the margin a good arm needs shrinks under
the first two and grows under the third — so the replicate count and the reading are one decision. The largest CV at
which a gate's best case still passes with P 0.80 (C: an arm that loses nothing, ×1.25 above 80 %; D: an arm on its
own +7.5 % target against −10 %; D is measured on its own arm only, so its bound has no pooled row):

| gate · reading | n = 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|
| C · arm mean | 38.8 % | 48.4 % | 56.9 % | 64.8 % | 72.4 % |
| C · lower bound | 3.8 % | 9.7 % | 13.5 % | 16.5 % | 18.9 % |
| C · lower bound, pooled | 11.6 % | 14.9 % | 17.5 % | 19.8 % | 21.8 % |
| C · every coupon | 17.9 % | 15.3 % | 13.9 % | 13.1 % | 12.4 % |
| D · arm mean | 30.5 % | 37.8 % | 44.1 % | 49.9 % | 55.3 % |
| D · lower bound | 3.0 % | 7.7 % | 10.8 % | 13.1 % | 15.0 % |
| D · every coupon | 14.2 % | 12.1 % | 11.1 % | 10.4 % | 9.9 % |

Under «every coupon» each added replicate fails a good arm more often: at CV 20 % an electrode exactly on D's target
passes with probability 0.66 at n = 2 and 0.29 at n = 6. Under the arm mean an arm sitting exactly at its threshold
passes half the time at every n. **E has no row:** its threshold is full recovery, so an electrode recovering exactly
100 % passes with probability 0.5 (arm mean), 0.05 (lower bound) or 0.5ⁿ (every coupon) whatever the spread; only a
recovery above 100 % (drift, rehydration — not a design state, and this model caps the best case there) would pass more
often. Canon therefore judges E against 100 % minus the instrument's repeatability band (⚖️ 2026-10-20).

**Selection** among the four Zone-1 candidates (Ti-6Al-4V is the control; Ta is the coin-only bioinertness benchmark —
its manifest and the coupon letter, while `01_02 §2.5` rule (в) still lists its σ_e among the V-free candidates): for
the highest sample mean to pick the best 4 times in 5 it must lead the others by ×1.12 at n = 3 and CV 10 % (×1.25 at
CV 20 %) — conditional on one current metric deciding, since canon names no rule that combines current, retention and
the ICP-MS rank.

**Budget.** At the coupon letter's quote point (12 per alloy, 3 of them electrode coupons; 19 for Ti-6Al-4V) the control
carries n = 2 and CP-Ti n = 3, while the four alloys with an anode and a cathode arm (Ti-6Al-7Nb · Ti-13Nb-13Zr · Ta ·
Ti-15Zr) carry 2 + 1, one arm on a single replicate; the PO puts n coupons on every comparative arm, the gold coupon and
the day-0 cathodes included (⚖️ delegated 2026-10-20, `01_03 §3.5`). Coupons per alloy = electrode arms × n + 3 uncoated (ICP-MS) + 6
reserve: the two-arm alloys need 13 at n = 2 and 15 at n = 3, Ti-6Al-4V 19 and 24. The 30-day hold C on the anodes
and the Ti-6Al-4V pair runs 480 channel-days at n = 2 and 720 at n = 3 — a floor, since the ratified channel order ends
in «→ the rest», which names no arm.

⚠️ **Bounds.** The CV is assumed, and which spread reading holds is itself measured only by the coin; a metric whose
spread is not log-normal is outside the model. For C · D · E the compared quantity is a ratio on one coupon, whose
spread is the coupons' different RESPONSE plus two scans' repeatability — not the loading spread of `j_max`, so its CV
row may sit lower. The ICP-MS series (3 per alloy by the letter) and test H are not covered. The model counts the
priced units; the quote prices them. Cache: `kinetics/coin_replicate_power.json`.
---

## CHEM.11 — Can the Deglycosylation Hotspots Actually Be Compensated? (scripts 69 · 80)

Spec home → [`L1_protein_architecture.md`](L1_protein_architecture.md) §2 (also the home of the freeze verdict, ⚖️ 2026-10-04); open legs → `00_07` HW.5.IS / CHEM.11.

`L1 §2` has said since 2026-06-06 that "an in-house hydrophobic-SASA proxy flags 4 aggregation-prone sites
(Gln71, Gln200, Gln258, Gln405)", and the recipe on top of it — Aggrescan3D plus compensating Asp/Ser near
them — gated the dgrFAD-GDH gene freeze. Since 2026-09-18 the compensations are ratified and written
into the order (three positions, all taken); the recipe's OTHER half — the Aggrescan3D run — gated the
freeze until **2026-10-04, when it was run and the founder ratified the freeze** (second-instrument
section below). ⚠️ **That proxy existed nowhere in the tree.** Commit `2e607abc`
canonised the conclusion and committed neither script nor cache, so the claim had no measurer until
2026-09-17. Script 69 is the measurer, and the first thing it had to do was ask whether a declared proxy
re-selects the published four.

**The declared proxy.** For each site, the solvent-exposed **apolar** (side-chain C/S) SASA carried by
aggregation-prone side chains whose own centroid lies within a **7 Å contact shell** of the site's. The
residue set is Kyte-Doolittle hydropathy > 0 (Kyte & Doolittle 1982, *J. Mol. Biol.* **157**(1):105-132,
doi:10.1016/0022-2836(82)90515-0) **plus the aromatics W and Y** — the aromatic addition is ours, not
theirs. A buried member contributes ≈ 0 area by construction, so members need no separate exposure filter,
and no external maximum-ASA table enters: burial is computed here as `1 − SASA_in_protein / SASA_isolated`
for the same side chain in the same conformation. Every other threshold is ours too and each carries a
sweep in the cache.

**It re-selects the four — inside a shell, and not outside it.**

| # | site | patch (Å²) | burial | percentile of the protein's OWN 600 residues | pLDDT (CA) | d(FAD) Å | d(e⁻ path) Å |
|---|---|---|---|---|---|---|---|
| 1 | **Gln71** | **138.1** | 0.689 | 98.2 | 96.82 | 13.2 | 14.5 |
| 2 | **Gln405** | **119.8** | 0.597 | 96.2 | 96.92 | 28.8 | 28.5 |
| 3 | **Gln258** | **68.1** | 0.598 | 86.7 | 97.69 | 11.0 | **8.0** |
| 4 | **Gln200** | **53.7** | **0.847** | 77.5 | 95.72 | 22.5 | 39.8 |
| 5 | Gln100 | 33.6 | — | — | — | — | — |

The 4th-to-5th gap is **20.1 Å²** and five of the eleven sites score exactly **0.0**, so the cut at four is
not arbitrary. But membership is **radius-dependent**: the published set is reproduced at **6.5, 7.0 and
7.5 Å only** — at 6 Å and at 8 Å and beyond, Gln100 displaces Gln200 — and **never** with the aromatics
removed, because Gln200's patch is held up by Trp210. The four is one definition's answer.

🔴 **And "hotspot" is a ranking among the eleven deglycosylation sites, not an absolute risk.** The same
proxy over all 600 residues gives a median of 24.5 and a p90 of 77.6 Å², with a maximum of **282.9 Å² at
Thr12** — **2.0×** Gln71's patch. Gln200 sits at the 77.5th percentile: some 135 residues of this protein
present a larger apolar contact patch than the site the recipe wants compensated.

**Compensation, built and measured.** Every candidate was mutated with `pdbfixer.applyMutations`, protonated
at pH 4.5, and minimised **side chains only** (ff14SB + GBn2 implicit, backbone mass 0, 500 iterations); the
FAD coordinates are re-attached afterwards, which is legitimate because the frozen backbone leaves the global
frame untouched (measured CA drift **0.0000 Å**). The reference goes through the identical pipeline, so the
Δ measures the mutation and not the relaxation. The noise floor comes from **four** reference replicates:
two-run estimates of it gave 2.52 and 0.25 Å² on successive attempts, so a single pairwise difference was
under-estimating its own spread.

| hotspot | mutation | ΔSASA patch (Å²) | Δq surface | burial | DSSP | d(FAD) Å | d(e⁻ path) Å | recommended |
|---|---|---|---|---|---|---|---|---|
| Gln71 | **Leu80 → Asp** | **−78.1** | −1 | 0.618 | T | 12.1 | 18.6 | ✅ **TAKEN — ⚖️ founder 2026-09-17** |
| Gln71 | **Leu80 → Ser** | **−78.1** | 0 | 0.618 | T | 12.1 | 18.6 | ⚫ not taken (tie broken by founder) |
| Gln71 | **Ala70 → Ser** | **−58.9** | 0 | 0.511 | H | 17.4 | 18.3 | ✅ |
| Gln71 | Ala70 → Asp | −58.9 | −1 | 0.511 | H | 17.4 | 18.3 | ❌ Asp in a helix |
| Gln405 | **Ile401 → Ser** | **−101.0** | 0 | 0.503 | H | 29.3 | 27.9 | ✅ |
| Gln405 | Ile401 → Asp | −100.5 | −1 | 0.503 | H | 29.3 | 27.9 | ❌ Asp in a helix |
| Gln200 | Ala201 → Ser | −25.7 | 0 | **0.770** | H | 26.4 | 42.8 | ❌ burial 0.77 > 0.75 |
| Gln200 | Trp210 → Ser | −16.0 | 0 | **0.908** | B | 19.7 | 37.2 | ❌ buried |
| Gln258 | Leu257 → Ser | −42.6 | 0 | 0.804 | — | **9.7** | 10.3 | ❌ FAD pocket + buried |
| Gln258 | Ala285 → Ser | −31.8 | 0 | 0.762 | T | **11.4** | 8.7 | ❌ FAD pocket + buried |

**Three positions are admissible, and two of the four hotspots get nothing.**

- **Gln71 → Leu80 and Ala70 → Ser.** ⚖️ **founder 2026-09-17 took `Leu80 → Asp`** — the measurement below is untouched and still says the two are a tie within noise; the verdict breaks a tie the computation declared unbreakable, it does not overturn it. 🔴 At **Leu80 the script refuses to choose between Asp and Ser**, and the
  refusal is itself a measurement: the two remove the same area to within the noise floor, and the ranked
  winner was observed **flipping Asp ↔ Ser between two runs of identical inputs**. What separates them is a
  **charge**, and noise may not decide a charge — so the cache names the position with `to: null` and leaves
  both in `admissible_substitutions`. The combined variant below had to be built from real residues, so it is
  built as Ser (the option that commits no charge); that is a build choice, flagged as one, not a
  recommendation.
- **Gln405 → Ile401 → Ser**, the single largest gain available — Ile401 alone carries 101.0 Å² of exposed
  apolar area, and the swap takes that patch from 119.8 to 19.4 Å². ⚖️ **founder 2026-09-18 TOOK it**, after the
  hold's own question — is position 401 conserved — was measured and answered no (Ile 3.6 % vs Ser 15.7 % over 332
  homologs; the catalytic His537 control reads 98.8 %). Numbers, sampling and the method's ceiling live in
  script `70` and its cache (`chem11_site_conservation.json`); the design verdict lives in `L1 §2`. Asp is refused there by the declared
  secondary-structure heuristic; Ser is not.
- ⛔ **Gln258 — do not touch.** Its entire apolar neighbourhood lies inside the FAD-pocket and electron-exit
  shells, and the site itself sits **8.0 Å from the script-28 tunnelling route** (a shortest-path heuristic, not a Beratan–Onuchic path; loaded from script 28's
  cache, not mirrored) **and 11.0 Å from FAD**. ⚖️ **2026-10-15 — the refusal stands on the FAD shell ALONE**
  (11.0 against the declared 12.0 Å; founder, on the recommendation): the route is script 28's heuristic, so
  «aggregation margin there is bought with the MET architecture of §5» is WITHDRAWN as a physical argument and
  the `d(e⁻ path)` column above is keep-out bookkeeping, not a coupling axis (`L1 §2`; script `69`'s header
  carries the same caveat, and its committed cache prose still reads the old label by design — re-running a
  stochastic script to re-word prose would be a new sample over a ratified freeze).
- ⚖️ **Gln200 — refused by OUR threshold, not by the physics.** Ala201 → Ser would remove **48 %** of that
  patch and is refused by a burial of 0.770 against our declared ceiling of 0.75 — a margin of **0.020**, and
  it would pass at the sweep's relaxed value of 0.85. Trp210 → Ser would remove 30 % and is genuinely buried
  (0.908, passing at neither swept value). ⚖️ **The ceiling was RATIFIED at 0.75 by the founder on
  2026-09-21**, so the gene does not take a fourth compensation; `threshold_cost_measured` keeps
  pricing each refusal in Å² so the choice stays visible, and the ruling with its ground, its
  named price and its weakest link lives in [`L1_protein_architecture.md`](L1_protein_architecture.md) §2.
  🔬 **And the second axis was measured 2026-09-21 — it does NOT support the refusal.** `I401S`'s hold was
  lifted by conservation, so refusing `Ala201` on geometry alone would judge the two positions by different
  evidence; script 70 now carries 201 as a `refused_candidate`. It reads **Ala 22.0 % ⊥ Ser 8.7 %** over the
  same 332 homologs (anchored n = 74: 29.7 % ⊥ 10.8 %) — more conserved than the **ratified** `A70S` position
  (14.2 % ⊥ 5.1 %) but nowhere near the His537 control's 98.8 %, and Ser is a real occupant of the column.
  **So the refusal of Ala201 rests on the burial ceiling alone**, a declared value of ours with a 0.020
  margin; the conservation axis is neutral-to-mildly-cautionary, not a second leg. The threshold's standing
  and the decision it gates live in [`L1_protein_architecture.md`](L1_protein_architecture.md) §2.

**Priced as one sequence, because a freeze is a sequence.** The three recommendations built as a single
variant take Gln71 from 139.9 to **2.9 Å²** and Gln405 from 119.8 to **19.4 Å²**; the largest non-additivity
against the sum of the singles is **3.1 Å²** — measured on the built variant rather than assumed either way.
The undecided position was built as Ser for this one variant, which the cache flags as a build choice.

**And the ORDERED gene itself, measured 2026-09-21** (`69 --ratified` → `chem11_ratified_gene.json`).
The row above is the **Ser** build; the sequence the CRO receives carries `L80D`. Because
`addMissingHydrogens` is non-deterministic, a number from one run and a number from another are two
samples — so this mode takes its **own** four reference replicates and builds **both** variants inside
that one sample, and only their difference is read across.

🔑 **A hotspot answers the question only if a mutated position lies inside its patch.** The two builds
differ at position **80** alone, so Gln71 (positions 70 · 80) and Gln405 (position 401) measure the
*substitution*, while Gln200 and Gln258 — which neither build compensates — measure the *pipeline*.
The table keeps them apart, because a difference at an untouched patch read as «the cost of the
substitution» is a mis-attribution, not a finding.

| build | **Gln71** (acts) | **Gln405** (acts) | Gln200 (idle) | Gln258 (idle) | surface net formal charge |
|---|---|---|---|---|---|
| reference (this run) | 140.0 | 119.8 | 56.4 | 70.8 | **−15** |
| **ratified `L80D · A70S · I401S`** | **2.9** | **18.9** | 56.5 | 71.2 | **−16** |
| published build `L80S · A70S · I401S` | 2.9 | 18.9 | 54.0 | 67.9 | −15 |
| ratified − published (ΔΔ) | **+0.0** | **+0.0** | +2.5 | +3.3 | **−1** |

**Both acting hotspots come out at ΔΔ = 0.0 Å² — the two builds are indistinguishable exactly where
the substitution acts.** The idle pair spreads by up to **3.3 Å²**, and that spread is the honest
yardstick: it exceeds this run's **2.52 Å²** four-replicate floor, so *the replicate floor
under-estimates this pipeline's own scatter* and the cache says so in `spread_estimates`. 🔑 **So the
substitution the founder chose by charge costs no measurable apolar area, and the only axis on which
the two builds differ is the charge itself (−15 → −16)** — precisely the quantity the tie was decided
on. The headline «Gln71 → 2.9 Å²» is therefore true of the gene that was ordered, not only of the
variant that was convenient to build. ⚠️ Absolute Å² across the two caches are **not** comparable cell
by cell (different samples); backbone CA drift is 0.0000 Å in both builds. ⛔ This says the Asp build
removes the same area — **not** that it folds, expresses or yields the same: no MD, no ΔΔG of folding.

### Conservation at the freeze positions (script 70) — the hold that gated `I401S`

The patch score above says how much apolar area a swap removes; it says nothing about whether the position
is allowed to change. That second question held `Ile401 → Ser` back, and its answer arrived on 2026-09-18
from scripts in a session scratchpad — the same shape as the missing proxy this whole section is about.
Script 70 is that answer in the tree: **332** homologs from **98** genera (four committed FASTA sources →
quality filter → 90 % de-duplication, all re-run from the inputs), a query-anchored Gotoh/BLOSUM62
projection, and the catalytic His537 as the instrument's own control.

| position | query residue | frequency of it | Ser | anchored subset | anchored: query ⊥ Ser |
|---|---|---|---|---|---|
| **401** (compensates Gln405) | Ile | **3.6 %** | **15.7 %** | n = 103 | **6.8 % ⊥ 39.8 %** |
| 70 (ratified `A70S`) | Ala | 14.2 % | 5.1 % | n = 266 | 15.0 % ⊥ 5.3 % |
| 80 (ratified `L80D`) | Leu | 41.9 % | 2.1 % | n = 244 | 47.1 % ⊥ 1.2 % |
| **201** — refused candidate (Gln200's only lever) | Ala | 22.0 % | 8.7 % | n = 74 | 29.7 % ⊥ 10.8 % |
| **537 — positive control** | His | **98.8 %** | 0 % | n = 241 | **100 % ⊥ 0 %** |
| 580 — second control | His | 91.9 % | 0 % | n = 294 | 98.0 % ⊥ 0 % |

**What the instrument added that the hold's answer did not carry.** The four homologs closest to us all
keep Ile — *C. gloeosporioides* `G8E4B4` (99.8 %) and three *Cytospora* spp. (79.0–81.3 %), each at a 90 %
local anchor — while the Ser carriers begin one step further out (*Gnomoniopsis smithogilvyi* 75.9 %, then
the *Colletotrichum* set at ≈ 62–64 %). So «variable» is a statement about the family; our immediate
neighbourhood keeps the residue being replaced. The verdict stands, its ground is narrower than it read.

**Independence, measured rather than asserted.** The same column read from an EXTERNAL Clustal Omega
alignment (EBI job, 85 accessions committed with the data) gives **61.9 % gaps** — the 398–406 stretch is
indel-rich — and per-sequence agreement with our aligner of **33.3 %** raw, **71.8 %** once the cells where
the external alignment places no residue at all are excluded (45 of 84 are exactly that; 9 more carry a
residue in both and differ). The finding survives the gap-penalty sweep in direction (Ser 15.7–17.5 % against
the query residue's 3.6–5.1 %), and **all eight** external PAIRWISE alignments in the tree (EMBOSS Needle,
completed 2026-09-21) agree residue-for-residue — **8 of 8 read Ser at query 401**. The eight are exactly the
anchored Ser-carriers of our own clade (seven *Colletotrichum* + *G. smithogilvyi*), and **not one of them sits
in the curated 85-accession MSA subset**, so each is an independent reading rather than a second look at the
same cell — which is what makes them a real check on the 61.9 % gap fraction above. ⛔ Frequency is not consequence, there is no phylogeny and no
tree-aware weighting here, and the 85-accession external subset is a curated sample whose selection rule was
never recorded — all three are named in the cache's own `caveats`.

**Ceiling.** An exposed apolar patch is a static, single-molecule surface descriptor — **not** an aggregation
prediction: no rate, no solubility, no critical concentration is computed anywhere here. **Aggrescan3D is a
SECOND instrument, not a check on this one** — it was run 2026-10-04 (licence posture a /NOTICE line in the
AF3 form; state → 00_07 HW.5.IS) and its reading is the section below, ⚠️ but both are of the SAME FAMILY
(exposure-weighted neighbourhood hydrophobicity), so neither validates the other. Sequence conservation is
NOT consulted by THIS script — it is measured separately (script 70, below) and read beside this score, never
merged into it — no mutant was run in MD, and no ΔΔG of folding was computed — burial and DSSP are geometric
*proxies* for that risk. One AF3 model, one conformation. No catalytic-residue list exists in our canon for
GcGDH, so catalysis is guarded only by the FAD-pocket shell, a geometric stand-in whose radius is ours. And
the reference state is the **aglycosylated** mutant: what the removed glycans were shielding is not measured
here, so the "newly exposed" framing of `L1 §2` is not tested by this script. The final choice of mutations is
the founder's presumption; this is its evidence base.

> 📐 **pLDDT convention.** Per-residue pLDDT is the **CA atom's** `B_iso` in the AF3 CIF — the statistic
> `L1 §4` already publishes (Tyr90 CA = 98.71; the residue *mean* is 98.23). The canonical
> `dgrGcGDH_AF3.pdb` is **not** a source for it: OpenMM wrote that file and zeroed the B-factor column.


### The second instrument — Aggrescan3D, run 2026-10-04 (script 80)

`L1 §2`'s recipe had two halves and only one was built: this proxy, plus **an Aggrescan3D run** that
stayed open for months because the hosted servers need an account. The standalone release was installed
and run on 2026-10-04 (posture and the two disagreeing upstream licence texts → [`/NOTICE`](../../../../NOTICE);
permission, recipe and the full verdict → [`L1 §2`](L1_protein_architecture.md)). ⚠️ **Its output is
third-party and EXCLUDED from this repository's CC-BY-SA-4.0 grant**; the reading of it is ours.

🔑 **The recipe's own criterion could not be applied as written.** It asked whether A3D flags the same
Gln quartet. A3D's propensity matrix is signed and **Gln's value is −1.1394**, so an exposed Gln scores
negative unless ringed by exposed hydrophobics — the question measures the matrix, not the protein. The
answerable form is the one this proxy already uses: **the flag lives at the NEIGHBOUR.**

| Site | A3D at the site | Best *measured positive* neighbour within 7 Å | This proxy's patch |
|---|---|---|---|
| **Gln71** | −0.523 | **Leu80 +1.134** — rank **2** of the mature chain's 37 positive residues · a ratified compensation | 138.1 Å² |
| **Gln405** | −1.247 | **Ile401 +1.025** — rank **4** · a ratified compensation | 119.8 Å² |
| Gln258 | −1.484 | Val256 +0.102 — an order of magnitude weaker, **not** compensated | 68.1 Å² |
| Gln200 | −0.462 | none measured — ⚠️ 5 of its 10 shell neighbours are gated, 3 of them hydrophobic (Leu199 · Tyr203 · Phe222) | 53.7 Å² |
| the other seven | all negative | none measured (gated neighbours at Gln380 · Gln405 · Gln463 too) | ≤ 33.6 Å² |

So the second instrument puts its two strongest site-adjacent flags on the two positions the ratified
gene substitutes, and flags **no site the gene does not already act at**. ⚠️ Three qualifications the
cache carries and this sentence must not swallow. (i) Gln258 **is** flagged, only an order of magnitude
weaker and uncompensated — "no new site" is the shell's verdict, not the protein's. (ii) The count is
**shell-specific**: at 7.5 Å — still inside the band where script 69's own four-site selection holds —
a fourth appears, Gln100 → Tyr97 **+0.131**, i.e. *stronger* than Val256. (iii) Every "none measured"
above means the instrument is **silent**, not that the neighbourhood is clean: the gated neighbours are
counted in the cache, never aggregated away. The third compensation **A70S** sits on a residue A3D
scores **−0.592** — and A3D structurally cannot flag an Ala either way (its matrix value **+0.056** is
the smallest positive of the twenty), which is a property of the scale, not a verdict about the
position; script 69 meanwhile ranks Ala70 the **second-largest** apolar contributor to the Gln71 patch
(59.0 Å² against Leu80's 76.4) and places it **closer** to the site (CA-CA 3.86 Å vs 5.46). Its ground
was charge-neutral patch reduction, not A3D.

🔴 **Three limits, each of which shrinks that to its true size.**
1. **Same family, not a different kind of method.** Both are exposure-weighted neighbourhood
   hydrophobicity. They differ in every detail — CA-CA vs side-chain centroid, a 10 Å exponential kernel
   vs a flat 7 Å shell, A3D's signed matrix vs Kyte-Doolittle>0 plus aromatics, freesasa RSA vs mdtraj
   SASA — so this is corroboration, never independent confirmation.
2. 🔴 **A3D's `0.000` is an exposure-gate SENTINEL, not a measured zero.** Below **10** % RSA the tool
   forces the score to exactly `0.0` (`min_surf`, read in the installed source). ⚠️ What we can measure
   in the tree is the *symptom*, not the cause: **253 of 600 rows carry an exact `0.0` (42 %), 161 of them
   hydrophobic by A3D's own matrix** — the RSA column itself is not committed, so the identification is an
   inference from an exact zero in a signed continuous score, which is near-certain but not a reading. They
   are written in the same column and format as a real value, so a buried hydrophobic patch and «nothing
   here» are indistinguishable. The **first** reading of this very run aggregated them, which produced a
   tidy «no positive neighbour at Gln258» and hid Val256. Script 80 excludes and counts them; any other
   consumer of `A3D.csv` must too.
3. **The model is not the protein being ordered.** A3D read only `ATOM` records and dropped the FAD
   silently (no warning in its log), so exposure near the flavin pocket is over-stated; and the structure
   is the **uncompensated** mutant, since no AF3 re-prediction on the compensated sequence exists.

⊕ **And a finding neither instrument was aimed at, which belongs to the ORDER rather than the model:**
residues **1–16 hold 13 of the construct's 50** positively-scoring residues — the hottest stretch of the
sequence being ordered is the **signal peptide**, which secretion is supposed to remove (UniProt
`G8E4B5` Signal 1-16 / Chain 17-600, evidence `ECO:0000256` — an **automatic** annotation, not an
experiment). Every **A3D** ranking above therefore starts at residue 17 — ⚠️ but script 69's
protein-wide maximum does **not**: its 282.9 Å² is **Thr12, inside that same signal peptide**, and
excluding 1–16 the maximum is Ser164 at 202.4 Å² (1.5× Gln71, not 2.0×).

🔴 **And the honest ground of this finding is weaker than the number looks, in exactly the way this
whole section condemns elsewhere.** Measured on the committed structure: residues 1–16 carry **3–6 CA
neighbours within 10 Å (mean 5.6)** against the mature chain's **19.7**, and sit **67.6 Å from the
chain centroid (max 87.0)** against 22.4 Å — AF3 models the signal peptide as a **detached, extended,
fully solvent-exposed tail** hanging off the globule. So RSA there is ≈ 100 % *by construction*, the
exposure gate never fires on any of the sixteen (**zero sentinels in 1–16**, against 253 over the
chain), and A3D's score collapses to matrix × exp(0.0521·RSA) — which is why the construct's global
maximum is Leu7 (+2.737). ⊕ Script 69's cache also names residue 23 as the model's **lowest-pLDDT**
(26.43), i.e. this is the least reliable region of the prediction. **Hence the QC line is bought by the
BIOLOGY of secretion — a hydrophobic leader that must be cleaved — and not by this score**, which is the
same "measures the scale, not the molecule" artefact as the Gln case, pointing the other way.

> 📐 **Determinism, and what it does not buy.** The run was repeated on the identical input and `A3D.csv`
> came back **byte-identical** — unlike this proxy, whose pdbfixer step carries a measured 3.77 Å² noise
> floor. ⚠️ This is an **attestation, not a measurement in the tree**: one `A3D.csv` is committed and the
> committed log is the *second* run's (it carries A3D's own «Working directory already exists» warning),
> so the byte-comparison itself is unrecorded — the cache files it under `provenance_attested`, not under
> `controls`. And a reproducible instrument can still be the wrong instrument, so determinism says
> nothing about the *physics*.
>
> 📐 **Two totals that deliberately DO admit the sentinel.** `sum_of_scores` (−274.17) and `mean_score`
> (−0.457) divide by all **600** rows, because that is what A3D itself reports — so «no statistic admits
> the sentinel» is true of every ranking, maximum, minimum and neighbour search here and **false of those
> two by design**. Over the 347 measured rows the mean is **−0.790**; quoting the 600-row figure as the
> protein's surface understates it by nearly half, which is why the cache now carries both.

---

## Infrastructure

| Component | Location |
|-----------|----------|
| Scripts | `tools/in_silico/scripts/` (count + per-script status → [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md)) |
| Shared lib | `tools/in_silico/lib/` (constants, geometry, utils, xylem_sap, dft_utils, md_utils) |
| Ligand SDF files | `docs/protocols/ebfc/in_silico/ligands/` |
| GAFF parameter cache | `tools/in_silico/cache/gaff_cache.json` |
| DFT results | `tools/in_silico/cache/dft/` |
| Kinetics results | `tools/in_silico/cache/kinetics/` |
| Mechanical and solution-chemistry results | `tools/in_silico/cache/mechanical/` · `tools/in_silico/cache/chemistry/` |
| MD trajectories | `tools/in_silico/cache/runs/` (gitignored) |
| Paper figures | `scripts/60_paper_figures.py` (cache-only, canon-asserted) → `paper/figures/` (Fig 3/4/5 + S1; Fig 1/2 = molecular/art, pending) |
| Conda environment | `tools/in_silico/environment.yml` (silken_md) |
| CI gate | `.github/workflows/in_silico_smoke.yml` |

---

## Milestone Tasks — all closed (per-script status → PIPELINE_STATUS, One-Home)

> Every L1–L4 script is complete or closed. The **per-script status table** (results + caches + dependency graph) lives **only** in [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md) — this results page no longer mirrors it (was a drift source: README inventory ↔ this status table ↔ PIPELINE). Nothing pending.

---

## Cross-References

- EBFC architecture → `docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md`
- Action plan tracker → `docs/00_07_Action_Plan_Tracker.md`
- L1 protein details → `docs/protocols/ebfc/in_silico/L1_protein_architecture.md`
- L3 DFT details → `docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md`
- Academic R&D partners → `docs/00_02_Academic_Integration_and_IP.md`
- Publication strategy → `docs/00_02_Academic_Integration_and_IP.md`
