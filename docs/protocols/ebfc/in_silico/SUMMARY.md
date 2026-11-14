# In Silico Pipeline Summary — EBFC Gen 2.0 Zero-Lab Proof

> **Date:** 2026-05-28 | **TRL Gate 3→4:** ✅ PASSED (2026-05-25)
> **Purpose:** Computational account of whether EBFC Gen 2.0 is thermodynamically viable, mechanically stable and kinetically functional — with the named caveats of the table below (L3b conditional on λ(Co) and λ(Cu); L4 recharge model) — BEFORE ordering any Ti-coin prototypes.
>
> 🟢 **CANONICAL SOURCE (SSOT).** This file + [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md) are the **single source of truth** for in-silico results (this = results, PIPELINE_STATUS = per-script/operational status). All other docs (01_03, 00_02, 00_01, READMEs) must **link here, not duplicate numbers**. When a result changes, update here + PIPELINE_STATUS only. Volatile counts (script/test totals) live in PIPELINE_STATUS exclusively.

---

## Executive Summary

The 4-level Zero-Lab pipeline examines the Gen 2.0 EBFC design entirely in silico (no level is a validation — bottom line below):

| Level | Question | Method | Verdict |
|-------|----------|--------|---------|
| **L1** | Does deglycosylated FAD-GDH fold correctly? | AlphaFold 3 | ✅ d_FAD = 15.998 Å burial depth — below the ≈20 Å single-step ceiling (a lower bound on the D–A separation; the flavin→mediator coupling is not computed — §Electron Tunneling Route) |
| **L2** | Does the full matrix denature the protein? | OpenMM MD (481k atoms) | ✅ RMSD 1.22 Å (100ps), Rg stable at 10ns |
| **L3** | Does electron cascade FAD→Os flow downhill? | PySCF DFT (66 atoms, dimethyl) | ✅ Downhill (measured E°s, +574 mV); raw DFT on the 1,5-dihydro donor gives one-electron readings of both directions — downhill: the B3LYP-Koopmans offset (Δε +0.07 eV on the programmatic geometry, ≈ 0 on Os(III)'s own minimum); uphill: the adiabatic ΔSCF (ΔG +0.05 eV), the vertical ΔSCF (ΔG +0.39) and PCET (ΔG +0.61 eV) — none like-for-like with the verified 2e⁻/2H⁺ cascade, and no conclusion is drawn from their sign; **like for like (`95`) the cascade is downhill in every Os form at every donor level (smallest +218.5 mV) at B3LYP/6-31G(d), and at ωB97X/def2-TZVP on both sides the device cell on the relaxed electronic flavin level is uphill (spin–orbit coupling on Os reverses the device couple on one flavin level at ref 63's [Os(bpy)₃] size), its magnitude method-dependent** |
| **L3b** | Is DET through ZIF nanozyme fast enough? | PySCF two-state diabatisation + Marcus | 🔴 **conditional on λ(Co) and λ(Cu)** (⚖️ 2026-11-01; FO-DFT coupling; bracket over the gap sign × the λ(Cu) reading): rate-limiting at the computed λ(Co) 3.09 eV (×4.1×10⁻⁶…×4.6×10⁻³), straddles turnover at the assumed literature 1.4 eV (×0.018…×21), both on the two λ(Cu) readings; at the computed λ(Co) turnover needs λ(Cu) ≲ 0.43 eV at ΔG = 0 (`copper_lambda_condition`), and for λ(Cu) ≲ 0.92 eV the computed case straddles it on the shipped Co–Ce coupling (×0.019…×2.4 at azurin's protein-held 0.7 eV) — NOT the old ×10⁵ (see §Cathode) |
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
| **Measured driving force** | **+574 mV / −0.574 eV (downhill)** |
| ↳ E°(Os +309 vs NHE, Zafar 2012) − E°(FAD-GDH −265 mV SHE, Schachinger 2023) | verified E°s |
| Like-for-like cascade (`95`) | downhill in every Os form at every donor level (smallest +218.5 mV) at B3LYP/6-31G(d) (spin–orbit coupling on Os reverses the device couple on one flavin level at ref 63's [Os(bpy)₃] size; at ωB97X/def2-TZVP on both sides the device cell on the relaxed electronic flavin level is uphill — `95` `higher_tier`, ⊕ 2026-10-30 below); magnitude method-dependent, the gap attributed to no side — the block «Like-for-like cascade» below; the former «gap = chloro↔bis-Im bracket + substituent +0.142 ①» decomposition is withdrawn |

⊕ **Revised 2026-10-19 (the like-for-like revision, `00_07` HW.5.IS):** the Conclusion below, the table row above and the paragraphs that follow now read like for like; what stood on the superseded 4a,5-dihydro numbers and on one-electron readings set against the 2e⁻/2H⁺ value — «raw DFT verdict UPHILL», «the ~1 eV gap» and its attribution — is withdrawn, marked where it stood.

**Conclusion:** The cascade is **experimentally downhill** (+574 mV, measured E°s — Os +309 vs NHE / FAD-GDH −265 mV SHE) and **downhill like for like in every computed Os form at every donor level** (the block «Like-for-like cascade» below; smallest +218.5 mV) — within one protocol, B3LYP/6-31G(d) (at ωB97X/def2-TZVP on both sides the device cell on the relaxed electronic flavin level is uphill — the block below): every cell shares B3LYP, C-PCM, |SHE_abs| = 4.281 V and a scalar-relativistic Os, which the cells cannot test. The one omitted term of known sign, spin–orbit coupling on Os (≈ −300 mV at its octahedral value — Srnec et al. 2008 and Rulíšek 2013, paper refs 63 · 19; not computed, and quenched by a lower symmetry), reverses a cell beyond **+218.5** mV; at the size ref 63 computes for [Os(bpy)₃] itself (**−250** mV, its SI Table S2 — the reading taken, ⚖️ founder 2026-10-20) it turns **2** of the 32 uphill, the device form among them, at the octahedral summary of ref 63's abstract (−300 mV) **5**, and at the larger rows of the same table — [Os(CN)₆] −333, [Os(NH₃)₆] −362, [OsCl₆] −400 mV — **7 · 8 · 10** (`95` `shared_shifts.ref63_table_s2_rows`); every flip sits on the two electronic donor levels, which lie 65 and 101 mV above the measured flavin and omit its ZPE term (§3.2); against the measured free flavin the shifted device couple keeps **+69.8** mV at the [Os(bpy)₃] value, **+19.8** at −300, and turns uphill past **−319.8** mV (−13 · −42 · −80 mV at the three larger rows) — less than the protocol's own conventions move it (159 · 138 mV) — so at any of those sizes the protocol does not determine the device sign (`94`'s one-hole model on the found analogues gives −0.32…−0.36 V; «upper count» for −300 withdrawn — ⚖️ founder 2026-10-23, П2). Three alternative choices lower E°(Os) relative to ours without being errors of known sign — the 4.44 V convention (−159 mV; alone no cell, with the spin–orbit shift **10** ⊥ **12** at the [Os(bpy)₃] ⊥ octahedral size), def2-TZVP on Os (`os_basis_def2`, −65.1 mV; alone no cell) and ωB97X on the device couple's Os side (138 mV) — and the terms that raise it (the Os ZPE, the waters on Cl⁻, the protein shift) are not netted (`95` `shared_shifts`). The direction rests on the protocol, which does not establish it. How far the computed cascade lies from the measured one, and on which side, is **method-dependent** (donor side +65 → −210 mV over the flavin levels, acceptor side +209 … −324 mV over the Os forms) and is attributed to no side; near-exact agreements are cancellations, named by `95` (⚖️ founder 2026-10-16, «напрямок + таблиця»). The former «raw DFT verdict UPHILL is a method limit, decomposed by ② into a chloro↔bis-Im bracket + the 4,4'-dimethyl substituent» stood on 4a,5-dihydro one-electron readings and is **withdrawn** (self-review round 1, clusters 2–3). The earlier «bias-corrected Δε ≈ −0.07 eV reproduces exp −0.14» was fortuitous cancellation tuned to a mis-valued (+60 mV) FAD potential — **withdrawn**; Cosnier 1999's +140 mV pertains to glucose-oxidase, not GcGDH.

**PCET potential (script 32 — thermodynamic proton reference):** E°(FAD/FADH₂) = **−155 mV vs NHE** (pH 7; −7.5 mV pH 4.5, +259 mV pH 0) lands **65 mV** from the free-flavin experimental value (−220 mV, the paper's ref 25; the unsourced −208 end of the former bracket was dropped ⚖️ founder 2026-10-02) at the MMFF electronic level — a proximity that does not survive relaxed geometries and the ZPE (`32b`, the block below: −430 mV, ≈ 210 mV beyond), so the flavin is not exonerated: both sides carry errors of the same order. (Cache `dft/pcet_redox_potential.json`; script 33's PCET route is a one-electron reading, not like-for-like.) ⊕ 2026-10-19: this paragraph was headed «PCET validation» and read «the flavin couple itself is NOT the culprit» — both withdrawn.

**Like-for-like cascade (scripts `32b` + `95`, 2026-10-16) — the cascade verdict's data (⚖️ founder 2026-10-16 «напрямок + таблиця»; paper §3.5, Table 2, Fig 4).** Both halves at one tier (B3LYP/6-31G(d)+C-PCM, LANL2DZ on Os), on one SHE scale (32's Isse–Gennaro convention), 2e⁻/2H⁺ flavin against each one-electron Os couple. The flavin at pH 7, one knob at a time (`32b`): **−155.4** mV on the MMFF geometries (32's protocol — the control) · **−118.7** mV relaxed · **−429.5** mV + ZPE · **−419.0** mV + RRHO free energy, against −220 mV measured. The zero-point energy is the term the electronic levels omit while pairing the flavin with a proton FREE energy (the reduced state carries two more N–H bonds; ΔZPE +0.62 eV for the two-electron couple moves E° by −311 mV) — so the 65 mV of the paragraph above does not survive it: the corrected level lies ~200 mV more negative, and that overshoot is not attributed (lumiflavin for FAD, basis, functional, protonation at pH 7, harmonic soft modes, the SHE convention and the missing explicit water are candidates; paper §3.2 — the basis and the functional are sized by `112`, ⊕ 2026-10-30 below). Relaxed FADH₂ is the butterfly minimum (0 imaginary modes); the planar RDKit/MMFF start converged first to the planar saddle (255i · 66i cm⁻¹) **117.5** meV above it, and the step-2 flavin chain (`21g` · `33` · `29b`) optimised from that same planar start until its re-run from the minimum (2026-10-18/19): FADH₂'s saddle lay 65.4 meV above its own minimum on `21g`'s def2-SVP and 117.6 meV on `33`'s 6-31G(d), every other species of the chain was a minimum already (`PIPELINE_STATUS`, banner 2026-10-19).

| Os form (B3LYP/C-PCM, `95`) | E°(Os) vs SHE, mV | acceptor side, mV | cascade, MMFF el. (`32`) | relaxed el. | + ZPE ¹ | + RRHO ¹ |
|---|---|---|---|---|---|---|
| chloro (device, programmatic) | +99.8 | +209.2 | +255.2 | +218.5 | +529.3 | +518.8 |
| chloro + 1 H₂O on Cl⁻ | +163.2 | +145.8 | +318.6 | +281.9 | +592.7 | +582.2 |
| chloro + 2 H₂O on Cl⁻ | +235.4 | +73.6 | +390.8 | +354.1 | +664.9 | +654.4 |
| chloro + 3 H₂O on Cl⁻ | +302.0 | +7.0 | +457.4 | +420.7 | +731.5 | +721.0 |
| chloro, Os(II) relaxed, Os(III) vertical | +212.4 | +96.6 | +367.8 | +331.1 | +641.9 | +631.4 |
| chloro, both states relaxed (adiabatic) | +126.3 | +182.7 | +281.7 | +245.0 | +555.8 | +545.3 |
| aqua (methodological reference) | +539.1 | −230.1 | +694.5 | +657.8 | +968.6 | +958.1 |
| bis-imidazole (brush-presented, hypothetical) | +632.6 | −323.6 | +788.0 | +751.3 | +1062.1 | +1051.6 |

Measured, free flavin against the film-bound mediator: **+529** mV (Os +309 vs NHE − free FAD −220 at pH 7; the Os measured as a PVI film at pH 7.4, whose preparation moves it by 135 mV — not the free molecule the computation models); the device's +574 mV adds the protein shift of the bound cofactor (−45 mV, measured, not computed). ¹ One-sided — every cell of these two columns, the adiabatic chloro row included: the Os side carries no thermochemistry here. Script `96` (2026-10-18) gives that one form's Os couple its own — analytic C-PCM Hessians of both relaxed states; the ZPE moves E°(Os) by **+40.6** mV — so with both sides relaxed its cascade is the table's **+245.0** mV on the electronic level (no thermochemistry on either side there) and **+596.3** mV with the ZPE on both sides, against +555.8 one-sided (`95`'s `both_sided` row). That is **67** mV over the measured +529 — not a near-match but the remainder of two large opposite errors, the acceptor side +142 and the donor side −210 mV. Its RRHO level is not comparable: the two Os states' soft-mode censuses differ — Os(III) drops two imaginary modes, both methyl torsions by the ⚖️ delegated rule of 2026-10-16 (22.8i and 14.2i cm⁻¹, methyl shares 0.999 and 0.998; `96` books the second as a tolerated soft mode because it lies under 20 cm⁻¹ — either way it leaves the ZPE and G), Os(II) none — so the both-sided row stops at the ZPE. That correction moves one form; `95` does not carry its increment to the others. **Every form is downhill at every donor level** within the protocol, B3LYP/6-31G(d) — spin–orbit coupling on Os reverses the device couple on one flavin level at the literature size for homoleptic [Os(bpy)₃], Conclusion above — (smallest: **+218.5** mV, the device form on the relaxed electronic level). ⚠️ **Agreement by cancellation, named by `95` itself (`cancellations`: |gap| ≤ 50 mV while each side is ≥ 100 mV off):** the device cascade at + ZPE lands **0.3** mV from the measured +529 only because a −210 mV donor error and a +209 mV acceptor error annihilate — likewise at + RRHO (+10 mV) and the adiabatic chloro form at both levels (−27 · −16 mV, one-sided — with the ZPE on both sides that form lands −67 mV off, footnote ¹). None of the four is a validation. (Caches `dft/pcet_redox_potential_thermo.json` · `dft/cascade_like_for_like.json`.)

⊕ **2026-10-23 (self-review round 2, applied):** two more device-row alternative choices now sit in `95` `shared_shifts` — the cavity radii (`cavity_uff`, UFF ×1.1 with a sphere on every hydrogen: **+122.4** mV on E°(Os), raising, listed with the raising terms and not netted; under them the device relaxed-electronic cell keeps **+90.9** mV at the [Os(bpy)₃] shift and **+40.9** at −300, so the sign of the device cascade depends on the cavity too) and def2-TZVP on Os (`os_basis_def2`: **−65.1** mV, lowering; alone it flips no cell). The one-electron proton-coupled route of Table 2b (`33`) is computed at 1 M H⁺ (pH 0); at pH 7 by the same Nernst term the 2e⁻/2H⁺ couple carries it reads **+0.196** eV, and with the B3LYP zero-point energies of the two flavin states **−0.125** eV (mixed tiers; the osmium side carries no thermochemistry) — a one-electron reading from which no conclusion is drawn (⚖️ D 2026-10-19). «Error» for the donor and acceptor sides reads «deviation» from here on: the references themselves carry a 135 mV film spread and a lumiflavin-for-FAD substitution.

⊕ **2026-10-30 — the donor side's basis and functional, and the device cell at ωB97X/def2-TZVP on both sides (script `112`, then `95` `higher_tier`; self-review round 2, П4(a), ⚖️ founder 2026-10-23 «both»; the cell composed and printed — ⚖️ founder 2026-10-30 (a)).** On `32b`'s B3LYP/6-31G(d)+C-PCM minima, one knob at a time (control: `32b`'s tier reproduces `32b`'s energies within 5e-9 Ha; the ωB97X FADH₂ lies 6.6e-5 Ha from `33`'s, the same minimum by `33`'s own control): def2-TZVP moves E°(FAD/FADH₂, pH 7) by **+126.6** mV (−118.7 → **+7.9**) and ωB97X/def2-TZVP by **+90.8** mV more (→ **+98.7**), **+217.4** together. With `32b`'s B3LYP thermal terms the donor side reads **+318.7 · +8.0 · +18.5** mV at ωB97X/def2-TZVP (relaxed electronic · + ZPE · + RRHO), against +101.3 · −209.5 · −199.0 at B3LYP/6-31G(d) — one step of each knob, not an error bar; the + ZPE level's 8 mV is a near-agreement on one side, not a validation. B1 holds the device couple's osmium side at the same tier (ωB97X/def2-TZVP, LANL2DZ on Os, C-PCM: E°(Os) **−38.0** mV, `functional_os_side` −137.8 mV), so the two halves compose: the device cascade is **−136.7** mV on the relaxed electronic flavin level — **uphill** — and **+174.0 · +163.5** mV with the flavin's ZPE · RRHO terms (one-sided), against +218.5 · +529.3 · +518.8 at B3LYP/6-31G(d). Both halves lower the cascade, so the device cell on the relaxed electronic level does not keep its direction at that tier. Limits: B1's Os(III) record carries no ⟨S²⟩ and no `rescued` flag (an earlier code path; its gap and its ω−B3 shift sit with the ωB97X family, whose nearest member, bpy, has no ⟨S²⟩ either) — a wrongly excited Os(III) would RAISE E°(Os), so against this record's state the electronic cell's «uphill» is the side it cannot flip and the + ZPE/RRHO «downhill» the side it can (terms that raise E°(Os) — the Os zero-point energy, the UFF radii — are another matter, paper §3.5); the osmium geometry programmatic and vertical, the flavin's from B3LYP, the device form the only one with an ωB97X osmium side, spin–orbit coupling on Os omitted as in every cell (the + ZPE / RRHO cells stay downhill until the spin–orbit shift passes **−174.0** / **−163.5** mV — at ref 63's [Os(bpy)₃] size the + ZPE cell would read **−76.0** mV and the RRHO cell **−86.5**; on the 4.44 V convention they keep **+15.0** / **+4.5** mV). Records `cache/dft/pcet_donor_basis_functional.json` · `cache/dft/cascade_like_for_like.json` `higher_tier`; paper §3.2 · §3.5 · Table 2.

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
| **CF₃** (assumed inert, not tested) | +0.54 | −4.957 | −4.635 | +0.617 |
| NO₂ (unstable) | +0.78 | −5.262 | −4.905 | +0.887 |
| **SO₂CF₃** (assumed inert, not tested) | +0.96 | −5.256 | −4.910 | **+0.892** |

**Koopmans trend (✅ cascade monotonic with σ on the programmatic geometry; with relaxation the NO₂→SO₂CF₃ step is not decided):** electron-withdrawing 4,4'-bpy improves FADH₂→Os alignment — cascade Δ rises −0.38 (NMe₂) → +0.89 eV. **SO₂CF₃ — the strongest candidate assumed inert (not tested), not a computed optimum** (σ 0.96, cascade +0.892 ≈ NO₂'s +0.887 on the programmatic geometry; with NO₂ relaxed the order is not decided and SO₂CF₃ is not relaxed — ⚖️ founder 2026-10-15, limit (3)) — same alignment there but **assumed electrochemically inert (not tested)**, whereas NO₂ degrades (NO₂→NHOH→NH₂ on Os cycling at pH 4.5) → would relax the cascade to the donor-saturated −0.38 worst case (CHEM.23). CF₃ (+0.617) = milder option, assumed inert. *Caveat:* max cascade-Δ ≠ optimal EBFC mediator — higher E°(Os) lowers OCV → optimum balances driving-force vs cell-voltage (exp Os opt ~+309 mV).

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

⚠️ **Limits, each load-bearing.** (1) **The functional/basis split exists at the centre (Me, H) and at two ends (NH₂, NO₂) only** — NMe₂, SO₂CF₃, CF₃, OMe and COOH have no small-basis ωB97X point (NH₂ has had one since 2026-10-09, NO₂ only since 2026-10-11 — until then the ×0.85 could not be attributed). (2) **Three measured series, Cl in two of them** — script `83` compares the computed shifts (`21e`; the ωB97X Me/H points from `21f`/`21d`) with (a) **paper ref 8's own series, our core with the imidazole N-donor** — Zafar 2012, *Anal. Chem.*, Table 1, [Os(X2-bpy)2(PVI)Cl]⁺ films at one loading, pH 7.4, X = OMe · Me · H · Cl: per substituent OMe−H ×0.87, Me−H ×1.34, Cl−H ×2.43; the measured sensitivity falls from donor to acceptor (pairwise 0.42 → 0.16 → 0.075 V/σ per substituent), ours much less (0.24 → 0.22 → 0.18), and the aqueous series (c) falls the same way; the same Me complex from another source at another loading sits +135 mV away — more than all four Me → H (film and preparation > the pairs compared); (b) the homoleptic MeCN series a ChemRxiv search returned (Goldschmid 2021; donors only): OMe agrees (B3LYP — no ωB97X OMe point), Me does not in either tier; and (c) an aqueous series of our own bis-bpy chloro core (Montón-Vicente 2026, *Langmuir*; X = OMe · Me · Cl, the axial N-donor pyridine instead of 1-MeIm), against a computed Cl point added to `21e` 2026-10-11: per substituent, OMe−Me ×0.59, Cl−Me ×2.18, Cl−OMe ×1.35 — the two pairs taken to Me share our Me excess, which the MeCN series shows too; the source's own B3LYP (both states optimised, ΔG) gives ×1.01, ×1.45, ×1.22, and its functional is ours, so the gap on OMe−Me is our protocol, not the functional (which point carries it this series cannot say — it has no H; in (a) it splits about evenly, OMe−H 9.1 mV short and Me−H 9.5 mV over, in (b) it lies on Me) — not the Os basis/ECP (`21e … b3lyp-osdef2`, 2026-10-11: def2-TZVP/ECP moves every point by +62…+65 meV and every pair by ≤ 0.8 mV per substituent); the ligand basis is bounded on Me−H only (ωB97X at 6-31G(d), then def2-TZVP: +3.2, then −3.3 mV per substituent — our two tiers agree there by cancellation, and no OMe point exists at def2-TZVP); nor the continuum's formulation or radii (`21e … b3lyp-iefpcm` · `b3lyp-uffcavity`, same day, each the series protocol with one knob changed: on OMe−Me, whose computed excess over the measured is +16.1 mV per substituent, IEF-PCM for C-PCM moves the pair by +0.1 mV and UFF ×1.1 radii with a sphere on every H by −1.1 mV, every pair by ≤ 0.6 / ≤ 4.7 mV; removing the continuum, `b3lyp-gas` — a bound, not a candidate — moves it by −29.0 mV: the continuum attenuates the pair, and neither variant closes a tenth of the excess; the UFF radii do move every absolute point, by −118…−137 meV — the pairs survive this change of cavity, the absolute values do not), nor the axial N-donor (`21e … b3lyp-pyaxial`, 2026-10-12: pyridine for 1-MeIm moves OMe−Me by +0.9 mV — away from the measured — and every pair by ≤ 3.6 mV per substituent), so A1′ holds for the pair; **relaxing the Os(II) geometry closes it and brings every recomputed donor pair of our own core closer to the measured** (`21e … b3lyp-relaxed-os2`, 2026-10-12: OMe, Me and H relaxed with the same protocol, Os(III) vertical on them (Cl, relaxed with the acceptors, below) — OMe−Me moves by −18.2 mV per substituent, to −41.9 against −39.8 mV measured, ×1.05 against the source's optimised ×1.01; ref 8 OMe−Me ×0.56 → ×0.99, and its two pairs against H closer by ~3 mV per substituent each, OMe−H ×0.87 → ×1.08, Me−H ×1.34 → ×1.23 (of the three donor pairs two are independent); Me falls weak against the H–OMe line as measured, r² of the three donors 0.9996 → 0.957; only the homoleptic MeCN OMe−H moves away, ×0.99 → ×1.23; the computed pairs change by −9 % (Me−H) to +77 % (OMe−Me), up to 73 meV a complex — as much as the points, whose relaxed shifts are −40 (OMe), −100 (H) and −113 meV (Me) — and the three-point donor slope rises by +21 %; the relaxed chelate comes closer to the crystal ranges of paper §2.3 — bite 77.5–78.2° against 80.5–80.6°, Os–N(bpy) 2.05–2.09 against 2.10 Å — while Os–N(L) lengthens to 2.14 Å and Os–Cl to 2.52–2.53 Å, 0.08–0.09 Å over the Os(II) range (2.40–2.44 Å) and 0.14–0.15 Å over the Os(III) one, on which Os(III) is computed vertically; `83` `relaxation_check` · `relaxed_geometry_check`) — so the programmatic geometry is load-bearing for the pairs themselves, and the relaxed one agrees better with the donor pairs of our core (its Cl pairs move away — below); **relaxing Os(III) as well** (`21e … b3lyp-relaxed-os3`, leg (3б), landed 2026-10-13: each Os(III) from its relaxed Os(II), adiabatic ΔSCF, λ_III 86 · 94 · 110 meV for Me · OMe · H) moves the two independent donor pairs toward the measured in both series that have H (against Os(III) vertical, OMe−H +4.2 and Me−H +6.1 mV per substituent) and their difference OMe−Me away in both series that measure it (−1.9 mV) — the six shared rows rest on three computed pairs, two of them independent; against the programmatic geometry Me−H and OMe−Me come closer in every series that has them and OMe−H closer to ref 8 and away from MeCN (×0.99 → ×1.16); ref 8's three then lie within 1.7 mV per substituent (OMe−H ×1.02, Me−H ×1.01, OMe−Me ×1.04), MeCN Me−H stays ×1.86, the aqueous OMe−Me ends ×1.10 (×1.05 with Os(III) vertical); r² of the three donors → 0.926, the donor slope +13 % against the programmatic; from the programmatic geometry the pairs move by up to 20.1 mV per substituent (OMe−Me, 80 meV a complex) and the points by −26…+54 meV, and on its own minimum Os(III) takes Os–Cl back to 2.42–2.43 Å, 0.04–0.05 Å over the Os(III) range (`83` `relaxed_geometry_check.adiabatic`); **relaxing Cl in both states** (`21e … b3lyp-relaxed-os2` · `b3lyp-relaxed-os3` on Cl, the acceptors run of 2026-10-14; λ_III 94 meV) **brings none of its pairs closer than the programmatic geometry did** — five rows on three computed pairs, which over the donors add one point: ref 8 Cl−H ×2.43 → ×2.81 → ×3.04, Cl−Me ×1.76 → ×1.83 → ×1.79, Cl−OMe ×1.18 → ×1.42 → ×1.42, aqueous Cl−Me ×2.18 → ×2.27 → ×2.22, Cl−OMe ×1.35 → ×1.64 → ×1.63 (programmatic → Os(II) relaxed → both relaxed); the Os(III) step alone brings Cl−Me and Cl−OMe back by 2.0 and 0.2 mV per substituent and takes Cl−H 4.0 mV further; its Os–Cl is 2.51 Å on the Os(II) minimum and 2.41 Å on Os(III)'s own, 0.07 and 0.03 Å over the two crystal ranges — the geometry carries these pairs too (Cl−OMe moves by 21.4 mV per substituent), but away from experiment and, on the aqueous pairs, away from the source's own optimised B3LYP (×1.45, ×1.22), so the acceptor excess is not an artefact of the programmatic geometry: our relaxation enlarges it, and what the source's computation has and ours lacks (ΔG among it) is untested on it (`83` `relaxed_geometry_check.acceptors`); **NO₂, relaxed the same way** (λ_III 150 meV, the largest of the five relaxed points; Os–Cl 2.49 and 2.41 Å on the two minima, 0.05 and 0.03 Å over the crystal ranges), has no measured counterpart in any of the three series, so it adds no row and the acceptor excess rests on Cl alone; left untested under A2′ are ΔG and PySCF's own discretisation of the cavity; the measured shifts are not linear in σp, so no slope is read from them; beyond Cl the acceptor side has no measured point, so the Lever/experiment triangulation withdrawn from the paper 2026-09-25 (`paper/09_references.md`, §3.3 line) stays withdrawn — Lever's half now exists (⊕ below): at the report's own ±20 mV it separates only our NO₂ − H, and finer, the side of the Cl pairs depends on which of its two lines applies; the ωB97X cross-check does not restore it either — a second method is not a measurement. (3) **The acceptor end has two ωB97X points, NO₂ and SO₂CF₃, and they disagree with B3LYP on their order** (↑) — «SO₂CF₃ ≈ NO₂» is a B3LYP statement (at ωB97X SO₂CF₃'s ΔE_red is 72 meV more negative than NO₂'s) and one of the programmatic geometry — relaxing NO₂ in both states moves its own Koopmans cascade Δ by −0.198 eV (+0.102 with Os(III) vertical), 20–40 times the 5.0 meV between them, with SO₂CF₃ not relaxed (`83` `acceptors`); CF₃, OMe and COOH have no ωB97X point. (4) **Vertical ΔSCF on one programmatic geometry, chloro form only**, in the recorded PySCF 2.11.0 with its ECP-in-PCM cavity convention (paper §2.7); the ωB97X series cache records that version, while the B3LYP series and the 21d/21f caches record none — so the comparison holds only while every point stays in the recorded environment, and a re-run of one side alone would mix two cavity conventions silently. ⊕ 2026-10-12 (read across the three series 2026-10-13): the programmatic geometry is load-bearing for the substituent pairs themselves — relaxing Os(II) changes them by −9…+77 % and brings the donor pairs of our own core closer to experiment and its Cl pairs away (limit (2)), while its Os–Cl overshoots the crystal range on the Os(II) minimum and comes back to 0.04–0.05 Å over the Os(III) range on Os(III)'s own (3б, the three donors; NO₂ 0.03 Å; Cl 0.03 Å); the Os basis, the continuum's formulation and radii and the axial donor do not move the pairs, the ligand basis is bounded on Me−H only; the flavin does not depend on the Os geometry, so each printed cascade number inherits whatever the relaxation does to ITS Os side: the B3LYP Koopmans offset (−1.05 eV) moves by +0.098 eV, its ε_LUMO(Os III) taken on the relaxed Os(II) geometry, and by −0.070 eV on Os(III)'s own minimum (paper §3.5 prints both) [⊕ 2026-10-16: −1.05 here and +1.03 below are 4a,5-dihydro levels; on the 1,5-dihydro donor the current ones are Table 4's Me row and Table 2, and the moves stand]; the ΔSCF cascade (+1.03 eV) takes its Os side from ωB97X/def2-TZVP, whose geometry sensitivity is not computed — the B3LYP ΔE_red of the Me point (−0.113 eV vertical, −0.026 eV adiabatic) is its nearest proxy — and with (3б)'s Me point in, that proxy stays under D's first trigger by its letter, so (3а) and the Me point of (3б) are not a trigger of D — ome and bpy met the same letter 2026-10-14: with both states relaxed their substituent pairs (≤ 80 meV a complex) and points (≤ 54 meV) stay under it (D's letter as narrowed 2026-10-08, pairs per complex as applied 2026-10-12), while the Koopmans cascade Δ of OMe moves by −0.142 eV with Os(III) on its own minimum (H −0.091, Me −0.070 eV) and the slope ①, extrapolated from the donors' +13 % over the fit set's span, by ≈ 0.13 eV — the first at the threshold by the letter, the second there only by extrapolation (as the 2026-10-13 submission priced (3а) at ≈ 0.17–0.2 eV), and neither is a trigger (⚖️ founder 2026-10-14, «так, так»: «carries a conclusion» read as what the paper concludes from the difference; the full form — `PIPELINE_STATUS`, D) (the rule ⚖️ founder 2026-10-13; its transfer to ωB97X is not computed, D's referee trigger stands; the numbers — `PIPELINE_STATUS`, D). ⊕ 2026-10-15: the condition of the 2026-10-14 verdict fired on Cl — its own Koopmans cascade Δ moves by +0.118 eV with Os(III) vertical on the relaxed Os(II) (−0.066 eV on its own minimum), the column staying monotonic over the relaxed members — so (а) and (б) go back to the founder, with NO₂'s numbers: NO₂ (landed the same day) gives (б) a computation — over OMe · Me · H · NO₂, four of the five fit-set members (COOH not relaxed), the slope moves −0.930 → −0.897 eV/σ, 0.034 eV over the span, shallower with both states relaxed where the donors alone extrapolated +13 % to ≈ 0.13 eV, and the slope §3.3 sets against ωB97X, over Me · H · NO₂ — all three relaxed — moves −0.931 → −0.859 eV/σ, 0.069 eV over its span, about 1.5 times under D's threshold; its own Koopmans cascade Δ moves by −0.198 eV on its own minimum (+0.102 with Os(III) vertical), the column staying monotonic over all five relaxed members on all three geometries, and NO₂/SO₂CF₃ (5.0 meV) is not decidable with SO₂CF₃ unrelaxed — re-ratified by the founder 2026-10-15: (а) and (б) are not D triggers, SO₂CF₃ is not measured, ΔG stays off (`83` `relaxed_geometry_check.acceptors`, `slopes`, `verdict_condition`; `PIPELINE_STATUS`, D).

⊕ **2026-10-30 — Lever's half of that triangulation, on four pairs (script `113`, `dft/os_series_vs_lever.json`; Стаття 1 self-review round 2, П4 (г)).** Read from the page images of the Office of Naval Research report that is the submitted manuscript of paper ref 23 — the version of record was not read, so the numbers are the report's: E_L per donor site, each bipyridine counting twice (report p. 4), and two Os(III)/Os(II) lines — organic S_M 1.01 (in organic solvents «generally insensitive to the net charge», the report's abstract; for an aqueous reading a solvent transfer, since «the slope is also influenced by the solvent», p. 10) and water S_M 1.61, defined only for net-charge 2+ species while every aqueous reading here (ours, ref 8's, the ampy series') is a +1 complex (L3). Of our series Table 1 holds the 4,4'-Me₂ row only; Cl is read through 4,4'-Br₂ (L2: a halogen of the same σp — Br's unchecked — not Cl's own value) and NO₂ through the mono-nitro ligand (L1: additivity within the ligand); all three rows come from 1–3 complexes. **At the report's own resolution — one ligand's values from different complexes «usually do not differ by more than 20mV» — every reading sits inside on both lines except ours on NO₂ − H, the **1** reading left outside, on the organic line** — of the programmatic readings: the relaxed and adiabatic Cl − H rows of `83` (48.4 · 52.5 mV) lie above the organic line's band as well, which `113` does not tabulate per band. Read finer, a row from 1–3 complexes typically within ±10 mV of its average and bpy (94 complexes) held at its rounding, the side of the Cl pairs is set by the line: on the organic line ours lies above on both (Cl − Me: Lever **+50.5**, ours **+79.1**) while the **3** measured Cl readings sit inside; on the water line ours sits inside on both (Cl − Me: Lever **+80.5**) while the measured fall below it on Cl − Me. The measured readings separate the lines themselves: all **4** aqueous measured readings sit inside the organic line, **3** of them outside the water one. At ±10 mV NO₂ − H puts ours above both lines (**+183.1** against **+82.8** organic and **+132.0** water). On Me − H both lines predict a larger donor shift than the MeCN series' **−15.0**. «Ours» is the programmatic vertical B3LYP shift; of 83's relaxed rows only the adiabatic Cl − H (**+52.5**) passes the water line's ±10 mV edge (**+50.7**), and the relaxed NO₂ row is not read. Every ±10 mV side here holds with bpy at its rounding: how far our own complexes depart from additivity is in no band, and with ±10 mV on bpy too the Cl pairs keep their line split while **4** sides move inside — ours on NO₂ − H (water line), the MeCN Me − H on both lines, ref 8's Me − H on the water one — and the adiabatic Cl − H with them. In no band: S_M's standard error, the water data's scatter about their line (p. 10), and the measured series' own errors (ref 8's Me complex at a second loading, from another source as well, differs by **135** mV per complex). Table 1 has no row for our other substituents (Masui & Lever 1993's E_L–σ relation would cover them; not read).

**Honest:** on the 1,5-dihydro donor the raw B3LYP-Koopmans cascade (programmatic geometry) runs −0.38 (NMe₂) → +0.89 eV (SO₂CF₃), crossing zero near OMe — a one-electron offset, no direction read from its sign; its absolute level carries the donor HOMO's method error (how far a donor level moves with the protocol is what the block «Like-for-like cascade» measures), while the *trend/design rule* is the robust, transferable result. Numbers: `dft/os_mediator_series.json`.

### Cluster-Continuum Micro-Solvation & Speciation (② — script 34; dimethyl recompute OS-RECOMPUTE 2026-06-17)

> ⊕ **2026-10-19 (the like-for-like revision) — how to read this block now.** Its «bracket» (lower/upper), «group-8 PCM bias» and «gap closed» vocabulary belongs to the withdrawn decomposition of a one-electron gap. What stands is each form's ΔE_red, which enters the like-for-like cascade (block above) as an Os form. The hexa-aqua second shell (a) LOWERS E° by 0.98 V, the opposite of the waters on the chloride (b), which raise it — so (a) is the size of the continuum-error class on a small +2/+3 couple, not a benchmark the device couple is read against or bracketed by; the «±0.15 V» in (a) is not a sourced convention uncertainty (the like-for-like cascade uses the 159 mV between 4.281 and 4.44 V); «functional-robust» below means only that the ORDER chloro < {aqua, bis-Im} of E°(Os) holds at both functionals.

⊕ (2026-10-23: the decomposition this block set out to test is withdrawn — the banner above; the block stays as the record.) Tests whether the raw cascade gap (above) is the implicit-solvation (PCM) limit, by
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
even the full chloro shell stays well below the +0.98 eV group-8 figure. This is the **lower bracket** ⊕ (withdrawn as a bracket 2026-10-19: the +0.98 eV is the hexa-aqua second-shell shift, not a benchmark for the device couple).

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
carry the larger group-8 PCM bias (benchmark a) ⊕ (record; the «benchmark» reading withdrawn 2026-10-19).

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
`wb97x_speciation_dmbpy.json` (3/3 forms converged via Newton, ⟨S²⟩≈0.754 per the commit message of 6f2a73fd5; no cache record or run log keeps it — the paper's Methods §2.2 counts these forms as convergence-only).

### Electron Tunneling Route (script 28 — a contact-graph shortest path, NOT a pathway analysis)

FAD:C5B → FAD:O4B → FAD:C4A → FAD:N1A → **ALA261** → **THR260** → **THR283** → **THR288** (surface) — found from the first FAD atoms of the structure file (PA · O1A · O2A · O5B · C5B: the phosphate/ribose end), not from the isoalloxazine N5
- 10 atoms, 9 steps, 23.7 Å; cost 7.8 = one covalent step (0.6) + eight «hbond» steps (0.9) — in the code an «hbond» step is ANY pair within 1.8–3.5 Å that includes N, O or S (a through-space step would cost ≥ e^{1.1·1.8} ≈ 7.2 alone), so the route is a chain of contacts, not of bonds; its «β·d» 2.05 = ln 7.8 is not a Beratan–Onuchic decay. Withdrawn from the paper (self-review round 1, cluster 6, 2026-10-15; corrected the same evening by the adversary on `079b81cec`); the committed caches keep the old `method` label
- **28b (CHEM.16) is NOT the same search:** its sources are the first atoms matching script 27's GAFF-name prefixes — by the adversary's mapping of 2026-10-15 on the MD structure, adenine C2/N3/C4 and flavin N1/C2, not N5, so they even overlap 28's route at FAD:C4A, and it records no path — its ln Σw = **2.02 ± 0.13** is the cost from a different start, so it says nothing about the route above either
- the paper reports no tunnelling pathway; a Beratan–Onuchic analysis from N5 is a follow-up.
- PBC for 28b's MD frames: mdtraj `image_molecules` (co-locates the separate FAD cofactor; `make_molecules_whole` alone insufficient).

Details → [`L3_quantum_chemistry.md`](L3_quantum_chemistry.md).

### Cathode: DET Through ZIF Nanozyme

**Method:** ΔSCF (UKS, level_shift 0.3) energy-splitting for two-metal ZIF clusters (script 24) on the **clash-free geometry** — script 23 deprotonated a bridging imidazole N–H that had collided with the 2nd metal at 0.97 Å (→ imidazolate bridge) — then Marcus k_ET with a two-sphere λ (λ_hop = (λᵢ+λⱼ)/2) instead of an assumed one. 🔴 **«Computed» is only half true on the bottleneck hop, and the cache now says which half** (`cathode_ket_lambda.json` → `lambda_computed_provenance`, added 2026-09-21): Co, Ce and Ru come from script 35's Nelsen 4-point, **Cu does not** — a Cu(I) d¹⁰ hexa-aqua optimisation is unphysical, so the shipped cache of script 35 carries no Cu row and λ(Cu) = 2.0 eV is the **literature** value. 🔑 That sentence is no longer a claim this page has to keep true by hand: since 2026-09-22 script 25 **derives** its Cu provenance line from script 35's cache at every run, and names all three states apart — no row · a row flagged unphysical · a row that PASSES the physicality check, which it announces as a STALE FALLBACK. A full run of 35 emits a Cu row either way (`which = … or list(METALS)`), so the absence is a state, not a property. λ_hop(Cu-Co) is their mean, so half of the bottleneck's λ is a citation. The script's docstring always said so; the emitted key was named `lambda_computed_eV` and did not, and the cache is what this page quotes.

| Hop | t_ij (eV) — fixed geom | (old, broken geom) |
|-----|-----------|--------|
| Cu↔Co (T1↔ZIF node) | 0.00128 crude — ΔE 9.4× SCF tol, unresolved (the margins use the FO-DFT **0.001475** ↓) ← bottleneck | 0.0325 |
| Co↔Ce (ZIF node↔vacancy) | 0.00687 | 0.0022 |
| Ce↔graphene (vacancy↔MWCNT) | 0.1129 | 0.1177 |

The geometry fix shrank Cu-Co t_ij **25×** → **Cu-Co is the bottleneck**, not Co-Ce.

⊕ **2026-11-01 — the Co–Ce cluster's bridge sits on a compressed Ce–N contact** (found by the Стаття 1 text referee): `23` places the bridge from the FIRST metal's nitrogen distance and orients it by the ring's centre of mass, so the second metal's distance falls where it falls — **1.92 Å** from cerium, against **2.45 Å** from cerium's own terminal donors (and, milder, Co–N 1.95 against 2.05 Å in the Cu–Co cluster, table below). What the compression does to that hop's coupling is not computed — and the correct bridge does not fit this model: with the node distance fixed at 6.0 Å, a 2.45 Å Ce–N leaves 1.50 Å for the 2.21 Å N···N span, so the solved ring is forced over — one of its hydrogens lands 0.73 Å from cerium, which `23`'s proton filter deletes silently — and still leaves an H–H contact of 0.53 Å beside cobalt, refused. That is CHEM.35's limit plus the fixed node distance, so a 3D cluster must free that distance too (deferred, ⚖️ 2026-09-22). The claim is priced instead (`25` → `coupling_drop_for_other_hops_to_limit`, live scenarios, Co–Ce at ΔG = 0, the two λ(Cu) readings): Co–Ce would limit only were its coupling at least **17.2** times smaller at the closest corner (**22.7** at the computed λ(Co); Ru–Ce in the swap **83.3**, on the borrowed Co–Ce coupling). Both unmeasured inputs move it (`other_hops_threshold_sensitivity`): with Co–Ce uphill by a site difference the size of Cu–Co's gap it falls to **4.5** (**6.2**), and at the protein-held λ(Cu) of azurin (0.7 eV, the cu_phen2 source's own example) Co–Ce limits already at the shipped coupling (**0.66** · **0.90**) — at that λ(Cu) the computed-λ(Co) cathode straddles turnover, **×0.019 … ×2.4**, its favourable corner set by Co–Ce. The paper says so (§2.5, §3.4).

⊕ **2026-10-23 — the cluster's charge (self-review round 2, К8′ → П4(б′) stage 1; instrument `24e`, record `cache/reproduction/cluster_charge_probe_2026-10-23.json`, not a cache):** the shipped cluster is computed at charge +1 with four protonated terminal imidazoles (metals +2), while the node's physical Cu(II)/Co(II) ⇄ Cu(I)/Co(III) hop needs +3; at +3 and on the imidazolate −1 form, two spin states each, no variant yields a readable diabatic pair (the +3 picks sit at the window edge ≈ 8 eV apart, the −1 picks are unbound virtuals with mixed populations), so stage 2 — re-running 24/24b at the physical charge — did not start. The paper states the charge in §2.5 and §4; the second word (keep the +1 cluster with its disclosure ⊥ a C-PCM re-run at +3) was the author's, given 2026-10-30: keep the +1 cluster with its disclosure for the preprint, a C-PCM re-run at +3 is a journal leg (`00_07` HW.5.IS).

⊕ **2026-10-30 — the coupling's own record (self-review round 2, К8; `24b` re-run with the record of in-silico §When Modifying #49; numbers `dft/fodft_coupling.json`, `dft/cathode_ket_lambda.json`):** the shipped +1 cluster was computed as a **triplet** — 2S = 2 imposed (PySCF's `spin` is 2S), no spin scan — at ⟨S²⟩ **2.014** against a pure 2.000; t_ij, the gap and the picks reproduced exactly in every repeat at that tolerance — five runs in the recorded environment (the committed one and four on 2026-10-30) and the conda-lock re-run of 2026-10-01 — which proved the SCF's stopping point deterministic, not the coupling converged (⊕ 2026-10-31 below: the numbers in this paragraph are the converged ones). The pair is **HOMO−5 · HOMO−3** out of the fixed window HOMO−5 … LUMO+3, the first on the window's edge — the pick is the window's as much as the cluster's, and the physicality flag does not see that. The localisation turns the pair by only **2θ = 1.30°**, so the 0.130 eV «site-energy gap» is nearly the canonical ε difference of the two orbitals. The record now keeps its order — the Cu-localised orbital lies below the Co-localised one (`site_energy_cu_minus_co_eV` −0.130) — but both are occupied α orbitals of the +1 model, so the order is a gas-phase one-electron difference, not a free energy, and does not say which site donates on the cathode's path. So script 25 now states the computed-λ(Co) verdict against ΔG itself (`downhill_gap_condition`): **below turnover for any downhill ΔG smaller than 0.441 eV** on the 2.0 eV λ(Cu) reading (**0.562 eV** on the 2.4 eV one) — the computed gap sits below both.

⊕ **2026-10-31 — the coupling was not converged, and every number of this section moved with it** (Стаття 1 round 2, К8 → instrument Г; in-silico Critical Rule #47; `24b` `converge`; record `cache/reproduction/fodft_scf_resolution_2026-10-31.json`). t_ij is an off-diagonal Fock element of ONE SCF, so it carries the residual Fock error of the point that SCF stopped at — of the order of the orbital gradient there — and |g| / t_ij is its resolution. The committed caches had stopped at PySCF's default |g| < √conv_tol = 10⁻³ Ha on a coupling of ≈ 5 × 10⁻⁵ Ha: the shipped t_ij read **0.00546 eV** (gap 0.183 eV, 2θ 3.42°) from a point 5.3 × 10⁻⁵ Ha above the minimum (the off-plane probe's two such stops: 1.8 and 5.3 × 10⁻⁵), and the exact repeats reproduced that deterministic stop. `24b` now polishes the SCF without a level shift towards |g| = 3 × 10⁻⁷ Ha (the recorded stops: 2.2–3.6 × 10⁻⁷) and records |g| / t_ij beside t_ij: three routes to the shipped minimum — the default, an unshifted first stage (no Newton rescue; the default's first stage needs one), and the conda-lock — land on one energy to 10⁻⁸ Ha and on t_ij **0.001472–0.001481 eV** (|g| / t_ij 0.4–0.6 %); the committed value is **0.001475 eV**, 15 % above the crude ΔSCF 0.00128 eV, which it once exceeded ≈ 4×. Since k_ET ∝ |t_ij|², every margin read at a fixed ΔG fell ≈ ×14 (the ΔG = 0 column and the Ru swap); the bracket's ends moved ×4–36, because the gap moved too (0.183 → 0.130 eV), and the λ(Co), ΔG and λ_o thresholds moved with them; the off-plane probe (t ≈ 5 × 10⁻³ Ha) moved 1.7 % — the same gradient is harmless against a coupling a hundred times larger. ⚠️ What the polish does NOT fix: the window, the picks, the functional and the cluster's charge (above) — errors that do not scale with the gradient.

🔴 **And λ_hop is not one kind of λ** (`outer_sphere_term`): it is the Marcus cross-relation mean ½(λ_i + λ_j) of the sites' self-exchange λ as read — the computed inner-sphere Nelsen values of `35` for Co, Ce and Ru, but literature values READ AS solution self-exchange TOTALS (inner + outer sphere) for Cu and for every node of the literature scenario — only the 2.4 eV Cu(phen)₂ reading is a measured total — and no outer-sphere term for the framework is added, so for the literature scenario an added term is a sensitivity rather than a missing piece. Every applied |ΔG| (≤ 0.130 eV) lies below every live λ_hop (≥ **0.82 eV**), so an added term can only slow every hop (the other direction — a framework-held site with less outer sphere than the solution couples — is covered by no corner: the bracket bounds the readings, not the site); how much it costs is a number, not a direction (in-silico §When Modifying #40): the literature-λ(Co) favourable corner reaches turnover at **λ_o = 0.305 eV**, and the Ru swap — the mitigation below — at **λ_o = 0.170 eV** on its adverse corner and **0.370 eV** on its favourable one, while the computed-λ(Co) corners sit below turnover already. The tree's only outer-sphere estimate is the anode flavin's in its protein pocket (`29c`: **0.375–1.428 eV** over its radius × dielectric grid, **0.375–0.469 eV** at the buried, delocalised end the paper quotes for the anode) — another medium, a scale and not this hop's value — and its physical end alone (from 0.375 eV) already lies above all three thresholds, the Ru swap's favourable one by 0.005 eV. So the Ru lever's ×5.5…×41 keeps every corner above turnover only while the framework adds less than ≈ 0.17 eV of outer-sphere λ, which nothing in the tree computes — and the one outer-sphere scale the tree has, read at its physical end, would put every corner below turnover except the Ru swap's favourable one, which it meets within 0.005 eV — a tie at the precision of an indicative λ(Ru).

**k_DET vs λ AND vs the driving force (script 25) — the margin is sensitive to both:**

🔴 **Since 2026-10-15 (Стаття 1 self-review round 1, clusters 1 · 8) the table runs on the FO-DFT coupling, and the
verdict is conditional on λ(Co).** ⊕ ⚖️ **2026-11-01 (founder, за рекомендацією) — and on λ(Cu):** at a protein-held value (azurin 0.7 eV) the computed-λ(Co) case straddles turnover and Co–Ce takes the favourable corner (`other_hops_threshold_sensitivity`, below the hop table; the form of the ruling — `00_02 §2.1`). The crude t(Cu–Co) above is half the difference of two UNCONSTRAINED SCF solutions of
one cluster from one start (script 24: state B differs only in SCF settings — level shift, DIIS space, cycle cap) — not charge-localised states, and the
difference is 9.4× the SCF tolerance both were converged to (`dscf_coupling_resolution`), so it resolves no coupling; its
table survives as `scenarios_crude_dscf` (the pre-2026-10-15 published numbers were lit-λ ×0.0045…×40, ×1.4 at ΔG = 0; the field is recomputed on the current gap and now reads ×0.014…×16, ×1.4 at ΔG = 0).
λ(Co) carries the verdict: turnover needs λ(Co) ≲ 1.5 eV at ΔG = 0 on the 2.0 eV λ(Cu) reading and ≲ 0.6 eV at the
adverse corner (`cobalt_lambda_condition`); the computed 3.09 eV ([Co(NH₃)₆], LS-Co(III)/HS-Co(II) IMPOSED by script 35,
not found) is far above both, the literature 1.4 eV has no primary and sits only ≈ 0.1 eV under the first. ⛔ The earlier «B3LYP over-estimates Co ≈ 2×
(spin-crossover artefact)» is withdrawn: no benchmark in the tree supports it, and it was what let the literature row
read as «the honest estimate». ⊕ ⚖️ **2026-11-01 — λ(Cu) carries it too** (`copper_lambda_condition`): at the computed λ(Co) turnover needs λ(Cu) ≲ **0.427** eV at ΔG = 0 and ≲ **0.917** eV at the favourable corner, and no λ(Cu) ≥ 0 reaches it at the adverse corner; at the assumed λ(Co) ≲ 1.596 · 2.121 · 2.611 eV (adverse · ΔG = 0 · favourable — ΔG = 0 between the two readings). No λ(Cu) lifts the computed cathode above ×2.39: Co–Ce, which does not depend on λ(Cu), caps it (`chain_at_lambda_cu_zero`) — on its shipped coupling (crude ΔSCF, on the compressed Ce–N contact above) at an assumed ΔG = 0, so a Co–Ce coupling **1.55**× smaller, or that hop **0.045** eV uphill, keeps the computed case below turnover at every λ(Cu) (`co_ce_ceiling_that_erases_the_straddle`; at the assumed λ(Co) ×78.4 or 0.39 eV). Azurin's protein-held 0.7 eV is one value below the 0.917 eV straddle threshold, not this site's value.

🔴 **Until 2026-09-21 this table was computed at ΔG = 0 — the Marcus helper's DEFAULT, not a
measurement** — while the FO-DFT block below already carried a computed **0.130 eV** Cu–Co
site-energy gap. The gap's *magnitude* is computed; its *sign* is not fixed (the two-state orbital
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
more rigidly held copper can sit **below both** (the same paragraph gives azurin's protein-held Cu(II/I),
0.7 eV — the entatic fold; an example, not a value for the framework copper or the T1 site), so the bracket bounds the READINGS, not the site — its adverse end is a
consumer ceiling, its kind end is no floor. The ΔG = 0 column stays on the 2.0 reading so the
pre-2026-09-21 published ×1.4 remains traceable.

| λ scenario | bottleneck | **adverse (+gap)** | ΔG = 0 (assumption) | favourable (−gap) |
|---|---|---|---|---|
| canon λ=0.7 (old assumption) | Cu-Co | **×3.0×10³** | ×4.8×10⁴ | ×4.8×10⁵ |
| **literature λ** (Cu 2.0–2.4 / Co 1.4 / Ce 1.0) | Cu-Co | **×0.018** | ×1.8 | ×21 |
| computed λ (B3LYP, Co 3.09 — ammine) | Cu-Co | **×4.1×10⁻⁶** | ×3.9×10⁻⁴ | ×4.6×10⁻³ |
| Co→Ru swap (computed λ_Ru = 0.78) | **Cu-Ru** | ×5.5 | ×41 | ×41 |

⚠️ **Read the last row differently from the others: its spread is the λ(Cu) reading ALONE, and its
ΔG = 0 and favourable columns are identical, because the Cu–Ru node has NO usable gap** — script 24d returns 0.0875 eV and *self-flags it non-physical*
(`localised: false`, `physically_reasonable: false`: both diabatic orbitals sit on Ru, pop(Cu) = 0; ⊕ 2026-10-30, re-run through `24b`'s diabatisation with its record — the doublet at ⟨S²⟩ **0.92** against a pure 0.75, contaminated as well; ⊕ 2026-10-31 polished, t_ij 0.105 → 0.113 eV and the gap 0.128 → 0.0875 eV — a move the old stop's final-check bound (3·√conv_tol = 3 × 10⁻³ Ha) admits, its gradient unrecorded; and still both orbitals on Ru),
the same failure that disqualified its t_ij. So **the Ru lever's driving force has no computed value, by
construction, and its ×5.5…×41 is a ΔG = 0 reading over λ(Cu) on the BORROWED Cu–Co coupling**, not a gap bracket that happened to be flat — and λ(Ru) sums Nelsen halves −0.26 and +1.04 eV (`ru_lambda_nelsen_halves`): one negative, so one optimised geometry is not the minimum of the state evaluated on it, and the row is INDICATIVE.
⊕ The bottleneck hop is **branch-invariant in every live scenario** — on the two λ(Cu) readings (at a λ(Cu) as low as azurin's, Co–Ce takes the favourable branch: `other_hops_threshold_sensitivity`, below the hop table): Cu–Co (or Cu–Ru) limits in every ΔG branch, so the
sign question moves the margin, never the identity of what limits — and since the coupling converged (2026-10-31) the withdrawn λ = 0.7 row too, whose
favourable branch had been Co–Ce-limited.
⚠️ The adverse literature-λ figure is quoted as **×0.018** and never as its reciprocal — a
reciprocal reads as a margin ABOVE turnover and means the opposite thing.

**Conclusion (revised, honest):** the old "k_DET = 1.09×10⁸, ×10⁵ above turnover, *not* rate-limiting" was a **double artifact** — a broken bridging geometry (clashing N–H) **and** an assumed λ = 0.7 eV. Its first correction read **~turnover (×1–30) at ΔG = 0**, and carrying the computed gap and the λ(Cu) bracket put the crude-coupling adverse corner at ×0.0045 — both on a coupling that does not resolve (above). 🔴 **On the FO-DFT coupling (script 24b, CHEM.14; t_ij(Cu-Co) = **0.001475 eV** + a 0.130 eV computed site-energy gap, converged 2026-10-31) the verdict is CONDITIONAL ON λ(Co)** — ⊕ ⚖️ 2026-11-01 **and on λ(Cu)** (the figures that follow are on the two solution readings; the λ(Cu) threshold and the protein-held example — §Cathode above): at the assumed literature λ(Co) the Cu-Co margin spans **×0.13 (uphill) to ×21 (downhill), ×1.8 at ΔG=0** on the 2.0 reading, and **×0.018 at the adverse corner** of the λ(Cu) bracket; at the computed λ(Co) it is ×4.1×10⁻⁶…×4.6×10⁻³ — rate-limiting at every corner. The old ×10⁵ is firmly excluded either way. Remaining closure = experimental EIS, with Γ from the voltammetric peak, measures k_DET of the electroactive population against turnover without either λ (surface-confined model; the peak must be the enzyme-wired site's); it does not measure λ(Cu) (a λ(Co) benchmark would close only the first condition). **Mitigation:** low-λ metal (Co→Ru, ×5.5…×41, indicative, and above turnover only below ≈ 0.17 eV of framework outer-sphere λ), conductive-MOF band transport ([`01_03 §3.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell) / CHEM.31), or enzyme-free SAC (CHEM.6). Numbers: `dft/zif_hopping.json` + `dft/cathode_ket_lambda.json`.

**Ru lever — the t_ij "double-whammy" is NOT confirmed (CHEM.32, scripts 24c/24d).** The Co→Ru ×5.5…×41 above is a **ΔG = 0 reading** over λ(Cu) on the borrowed Cu–Co coupling (table note) and is the **λ** benefit alone (λ_Ru 0.78 — itself indicative, one negative Nelsen half). We tested whether Ru's diffuse 4d *also* raises the coupling: at the canon cluster geometry with Co→Ru (identical coordinates; control Cu-Co reproduces canon t_ij 0.00128 ✅), the crude ΔSCF gave a large splitting (×81, t_ij 0.10 eV) and the FO-DFT diabatisation gave t_ij 0.113 eV (0.105 before the 2026-10-31 polish) — **but both FAIL the physicality check**: the frontier MOs localize entirely on Ru with **no Cu-d partner** in the window (24d self-flags non-physical — both diabatic orbitals pop(Ru) ≈ 0.84–0.88, pop(Cu) ≤ 0.003). The minimal cluster's Cu-d and Ru-d manifolds are too energy-mismatched to form a clean Cu↔Ru diabatic pair (unlike Cu-Co). So the coupling boost is **plausible but unvalidated by this approach** — a rigorous Cu-Ru t_ij needs **CDFT constrained diabatic states** (a follow-up capstone: PyCDFT in-house or a specialist collaboration). The Ru lever stands on its **λ** advantage; its coupling advantage is a hypothesis, not a result. Caches: `dft/cu_ru_coupling.json` + `dft/cu_ru_fodft.json`.

**Model caveats** (frame the verdict — *not* a margin-chase): t_ij is **geometry-bounded** — a clash-corrected programmatic cluster, not DFT-relaxed (these flat-PES metal clusters resist geom-opt, cf. script 21c); and the single-hop bottleneck is **conservative** — the ZIF is a wide-gap **insulator**, so transport is the discrete Marcus hops modelled (not bands), and the 3D framework offers **parallel** instances of the bottleneck hop (band-like transport = the cMOF lever, CHEM.31).

🔴 **«Geometry-bounded» now carries a NUMBER (2026-09-21, CHEM.35 probe) — and what makes it matter is not its size but that nothing declared it.** The bridge ring's roll about its own N···N axis is a degree of freedom the builder never scored. Rolling it out of the metals' coordination plane — Cu **0.696 Å**, Co **1.371 Å** off-plane, everything else identical — moves the FO-DFT coupling **0.001475 → 0.1304 eV** (×88), because an out-of-plane metal stops binding through the nitrogen's in-plane lone pair and starts overlapping the ring π directly.

⛔ **It is NOT a ×|t|² story, and quoting it as one understates it ~8× and misdescribes it in kind:** the same diabatisation of the same cluster also moves the site-energy gap (0.130 → **0.026 eV**), so the consumer-rule margin goes **×0.13 → ×8.65 × 10³ — a factor of ≈ 6.5 × 10⁴ — and that CROSSES enzymatic turnover** (both on the 2.0 λ(Cu) reading — the probe prices the geometry, not λ). In other words this one construction choice does not widen ③'s verdict, it **flips** it, from «rate-limiting on the adverse reading» to «comfortably fast» (`cathode_ket_lambda.json` → `geometry_sensitivity_refused_offplane.flips_the_verdict`).

⊕ **2026-10-30 — at the COMPUTED λ(Co) too, and the probe's gap carries two figures** (self-review round 2, К8; `geometry_sensitivity_refused_offplane.by_lambda_co`). The figures above are at the assumed λ(Co); at the computed 3.09 eV the same roll moves the whole bracket from ×4.1 × 10⁻⁶ … ×4.6 × 10⁻³ to **×0.26 … ×5.1 — straddling turnover**, where it lay wholly below, so the computed-λ(Co) verdict («rate-limiting at every corner») rests on the same single criterion as the literature one. Re-run with its record, the probe's pair is HOMO−5 · HOMO−4 (again on the window's edge) and the localisation turns it by **2θ = 84.4°**: the canonical pair is nearly a full bonding/antibonding mix, and its «gap» is the residue of that mixing, not a site difference. There a 0.1° change of 2θ moves the gap by ≈ 0.0005 eV, so the probe's gap, and every margin built on it, carries two significant figures. ⊕ 2026-10-31: the 0.0004 eV drift of the 2026-10-30 re-run (0.0264 → 0.026 eV), unexplained then, sits inside the scatter of an SCF stopped at that tolerance — two runs at conv_tol 10⁻⁶ differ by 0.017 eV in gap and 3.7° in 2θ, the four at 10⁻¹⁰ (three default stops and the polish) by 0.0002 eV and 0.04° (`fodft_scf_resolution_2026-10-31.json` → `offplane_groups`).

🔑 **So read it as a LOAD-BEARING criterion, not as an uncertainty band.** The off-plane geometry is **refused** — script `23` exits 1 on it (`bridge_out_of_plane` vs `PLANARITY_TOL_A`), because a coordinating nitrogen binds through an in-plane lone pair — and the shipped cluster is correct on exactly that axis (metals **0.000 Å** from the bridge plane). ③'s verdict therefore rests on one geometric criterion being right, and until 2026-09-21 nothing in the tree named it, gated it or measured it. ⚠️ **What remains genuinely open is different and still unmeasured:** the residual spread WITHIN the in-plane family (M–N–C angles, the ring's in-plane tilt). The probe is rebuildable on purpose — `23 --solve-bridge --roll perpendicular` → `24b --geometry offplane` — so the criterion has a live instrument, not a remembered number.

**Bridge geometry — what the shipped cluster actually is** (`dft/zif_bridge_geometry.json`, script `23`):

| what was checked | result |
|---|---|
| bridge N···N span, 2-methylimidazolate ⊥ benzimidazolate | **2.213 ⊥ 2.218 Å** (Δ 0.005, ~0.2 %) — linker-INVARIANT |
| metals vs the bridge-ring plane, shipped cluster | **0.000 / 0.000 Å** — in-plane, physically right |
| Cu–N, Co–N on the bridge, shipped cluster | 2.020 / **1.946 Å** (target 2.050 — 5 % short, the price of the COM roll) |

🔑 **Three things follow, and the third closes CHEM.35.** (1) The lever's canon caveat — «a bigger ligand pushes the metals apart» — is **false on the bridge axis**: a ring fused at C4–C5 grows the ligand footprint by 0.9 Å without touching the N–C–N span that sets M···M. (2) The canon recipe «swap the linker in `23`, re-run `24`» builds a cluster with **no bridge at all** (the second N lands 3.217 Å from its metal, the N–H survives the clash filter, the charge is off by one) — `24` would still have returned a coupling. (3) A correctly-bridged ring **does not fit this model**: hold the metals in-plane and the bridge collides with the coplanar terminals (0.254 Å methylimidazolate, 0.358 Å benzimidazolate); hold the sterics and the metals leave the plane, which is the ×88 artifact above. **So the shipped geometry is the best the 2D minimal cluster can do, and CHEM.35 is unanswerable here — it needs a 3D cluster with tetrahedral terminals, an instrument change that moves every number in this section** — ⚖️ ratified (delegated) 2026-09-22: **not built now**; the return trigger is the measured cathode EIS of coin Stage 2 (verdict, price and weakest link — [`01_03 §3.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).

⊕ **Acceptance threshold for any COUPLING lever** (`dft/cathode_ket_lambda.json` → `coupling_gain_to_reach_turnover`): since `k_ET ∝ |t_ij|²`, lifting the consumer-rule (adverse) reading to enzymatic turnover needs **×7.4** on the diabatised t_ij at the ASSUMED literature λ(Co) 1.4 eV and **×495** at the computed 3.09 eV (`by_lambda_co`), or ×8.5 on the crude ΔSCF one — all at the adverse CORNER (uphill gap × higher λ(Cu)). ⚠️ The threshold is conditional on λ(Co) and λ(Cu) exactly as the verdict is; a single number here is a λ(Co) pick in disguise. ⛔ It does NOT apply to a λ lever (Co→Ru): λ sits in the Marcus exponent, not the prefactor.

---

## L4 — Chemical Kinetics

> ⚠️ Scenario labels «healthy» / «stressed» / «Active growth» name sap-glucose cases for the CELL, not states of the tree: `delta_t` measures
> the cell's power, not tree physiology ([`01_03 §4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)); the labels are pinned and kept.

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

### EIS brackets (for Ti-coin Stage 2)

| Parameter | Bracketed | Literature Range |
|-----------|-----------|-----------------|
| Rct (charge transfer) | 72.9 Ω | 100-500 Ω |
| Rs (solution) | 100 Ω | 50-200 Ω |
| Cdl (double layer) | 50 µF/cm² | 20-100 µF/cm² |
| Time constant τ | 7.3 ms | — |
| Warburg region | < 21.8 Hz | — |

The 72.9 Ω Rct above is the **anode** charge-transfer (enzyme→Os, from j_max; script 31). The
**cathode** DET Rct is *not* a single value — script 31b (Laviron, surface-confined) gives a band
**~0.06 Ω–3×10⁷ Ω** across the k_DET bracket (gap sign × λ(Cu) reading × λ(Co) value) × the unknown
site coverage Γ: the cathode arc can be negligible (fast/dense) or **exceed the anode arc
up to ~×4.5×10⁵** (adverse corner, sparse coverage; the high end moved from 3×10⁴ Ω / ×400 on 2026-10-15 with the λ(Co)
axis — the low end did not — and on 2026-10-31 both ends rose — the low ×35, the high ×4.6 — with the converged coupling and its gap), so it **cannot be predicted a priori** — the robust statement stays the **kinetic competition**
k_DET against turnover — itself conditional on λ(Co) and λ(Cu) (§Cathode) — with the measured Ti-coin cathode EIS the decisive test. INDICATIVE
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
lateral support → infinite life for **every** alloy on the shipped welded branch (SF 2.50–6.91×; the superseded
printed branch reads 1.25–3.46×, CP-Ti and Ta below SF 2) — ⚠️ both on the 18 mm «supported» idealisation, which
since G1 lies ABOVE the compliant bracket's upper end on every geometry (§equilibrium below), so for the coaxial
regime it is a conservative bound: on the bracket itself every alloy clears SF 2 (welded Ta 5.80 at the upper end;
the printed derate of 0.50 halves it, still above 2) — and it says nothing about a channel offset. 🔴 **Bare, the fabrication choice decides — and it decides two different verdicts.** Printed:
infinite life for **0 of 6** (SF 0.64–1.78×), **CP-Ti (0.90) and Ta (0.65) predicted fatigue failures**. Welded:
every SF doubles → infinite life for **4 of 6** (SF 1.29–3.56×), with CP-Ti (1.80) and the binding candidate
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
> 🔴 **And the clearance verdict of the same day moved this section's OWN numbers — branch (в), channel Ø1.30 → Ø1.35, applied 2026-09-11.** Two things changed and only the second is a digit. **(1) The model can now say WHICH SIDE the leftover play sits on**, which it could not before: a conformal film is bonded to the rod, so its play is on the ROD side and the bending member is the bare wire; the ratified liner is tight on the wire and enters the bore as one body, so its play is on the CHANNEL side and the member is the rod-plus-tube composite (both stiffness bounds computed, `ei_Nm2_bare_rod` ⊥ `ei_Nm2_bonded`). **(2) The "hundredfold reduction of free travel" this page fed into canon was a ROD-SIDE number and is gone: the measured factor is `play_reduction.factor` ≈ 6.8×** (170 → 25 µm). ⚠️ The «supported-column root stress understated by 40.8 %» this note carried until 2026-09-14 measured the 6 mm idealisation against a free-shape first contact; under the equilibrium the SIGN reverses — there is no propped 6 mm span, the coaxial root stress against a RIGID wall is set by the exit contact (and is the LOWER end of a bracket, §equilibrium below), and the §2 supported column — since G1 an 18 mm span, the whole PEEK gap — OVERSTATES that rigid-wall end ×**16.19** at nominal µ on the shipped geometry (against the shallow end's own cap ×20.16 — the column itself is computed on the shipped geometry only; ×2.28 on the retired placeholder; `clearance_regime.supported_column_vs_equilibrium`, sign derived). Under a channel offset the comparison has no meaning: the root then carries a MEAN. So `L_FREE_SUP` overstates the coaxial root stress against a RIGID wall, and since G1 against the compliant liner too: the column sits ABOVE the bracket's upper end on both geometries at both µ (`column_position_*`, derived; on the placeholder it sat inside the bracket) — and it is the wrong quantity for the offset case. Measured, not asserted.
> 🔴 **Weld seam — BOUNDED 2026-09-12, RETIRED 2026-09-14, and the input is still missing.** Canon ([`01_01 §1.4`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) and the factory protocol `§3` step 1) had been sending the reader here for this state while nothing here held it. The seam's fatigue-strength knockdown `k` is in **no** canon row, **no** vendor answer and **no** experiment, so `weld_seam.knockdown_k_measured` stays `null`. On 2026-09-12 the model inverted `SF_seam = k · SF_wire` on ONE fully-reversed stress — the §2 supported column at the worst swept µ inflated by a span optimism measured along the free-shape first contact, 43.0 MPa — and reported a break-even `k` of 0.554 against our own marker `AS_PRINTED_DERATE` = 0.50 (margin −0.054, «does not clear»). 🔴 **That stress is the root stress of a free cantilever whose length is a free-shape crossing station; no equilibrium configuration produces it, and the bound is retired with the picture.** The equilibrium gives the root TWO regimes instead, and neither is a single fully-reversed number: on a coaxial channel the drag is fully reversed with an amplitude that is itself a BRACKET — the rigid-wall figure is its LOWER end, the Ti-bore stop its upper, the contact compliance between them unmeasured (mean 0); a channel off the root axis by more than the play puts a STATIC bending on the same section — a MEAN that grows with the offset, a rigid-wall UPPER bound — with the reversing drag as amplitude on top. ⛔ **No `k` is derived from either** (`weld_seam.break_even_k` = `null`, `break_even_k_not_derived_because`): the model has no mean-stress correction, so the offset regime cannot be priced, and a `k` inverted from the rigid-wall end of the coaxial bracket alone would silently assume both a coaxiality the stack carries only as a requirement (⌀0.10 — the form ratified 2026-09-18, the number 2026-10-12, `00_07` HW.34) and a rigid wall the part does not have. What the cache gives instead is the INPUT a seam acceptance needs — amplitude and mean at the root per regime and geometry (`weld_seam.root_section_loading`, the same solver and the same offset points as script `68`, pinned equal to `68`'s table below: its rigid-wall column and upper-end column bracket the coaxial amplitude · offset secant = mean per µm past the play · reversing amplitude, a rigid-wall figure). **Consequence, unchanged in direction and stronger in ground: `k` must come from the vendor** (weld class, WPS, post-weld treatment of the toe — `00_07` HW.34 👤), because there is no house number bracketing the joint at all now, not even a drift-picture one. ⚠️ The comparison markers stay OURS (`AS_PRINTED_DERATE` ⊥ `WROUGHT_DERATE`) as the scale a vendor `k` will be read against; nothing is compared with them. ⛔ Three seam mechanisms stay outside any bound and their signs differ: a bead upset/fillet RELIEVES nominal stress, a weld-toe notch AGGRAVATES it, and weld residual TENSION is a **mean** stress — the same absence that stops the offset regime being priced. (`mechanical/bus_mechanical.json` §`weld_seam`)

🔬 **WHERE THE ROD MEETS THE WALL — the equilibrium, 2026-09-14 (`clearance_regime`, `edge_bearing`; solver `lib.beam_contact`, one home with script `68`).** Until then every station here bisected from the ROOT along the FREE tip-loaded shape at FULL drag and read the crossing of the play as a contact; the first 18 mm (6 on the retired placeholder) have no wall at all (PEEK gap inside the Ø11 sleeve), and a shape that crosses a wall is not admissible once the wall exists. Solved as a unilateral contact, the picture splits by REGIME, not by µ:

- **Coaxial channel (drag).** The touchdown drag of the shipped liner is 0.0095 N on the shipped geometry and 0.0069 N at the lock window's shallow end — far below every swept µ·F — so on every swept µ and every geometry the rod is touched down at the **EXIT**, where the tube ends flush, and nowhere else (asserted per row); the deflection at the mouth is a fraction of the play (8.3 µm of 25 on the shipped geometry, 9.8 at the shallow end), so **the mouth is never reached coaxially**. Against a RIGID wall the touched-down shape is the prescribed-displacement shape and does not change with the drag, so the root stress is 3·E·c·g/L² and µ-invariant (the `68` table below) — **and that figure is the LOWER end of a bracket, not a cap**: the real wall is the PEEK wall on the Ti bore's exit edge, it yields by R/k and raises the root moment by 3EI·(R/k)/L², up to the Ti-bore stop behind it (the polymer wall fully yielded; the free cantilever F·L is reachable only where the drag cannot reach the bore). At the worst swept µ the root lies in [3.39, 23.8] MPa on the shipped geometry and [2.72, 19.2] MPa at the shallow end (`coaxial_root_bound`, `sigma_root_MPa_upper_end`; the bracket is rounded OUTWARD from the raw `sigma_root_MPa_bonded` · `sigma_root_MPa_upper_end`, which `55` and `68` cache bit-identically — a bracket must hold its own ends, in-silico §When Modifying #43); where in that bracket it sits is set by the contact compliance, measured nowhere (⊕ 2026-10-14: MODELLED since by script `91`, block below — on an unworn wall the cycle peak sits at the rigid end within a few per cent, and the Ti-bore stop is not an elastic state: exit wear saturates the peak once the mouth engages; still not measured). The wall reaction is at most the drag minus the touchdown drag (0.191–0.491 N over the swept µ on the shipped geometry — a rigid-wall UPPER bound, each rounded up; ⊕ 2026-10-14: for a flush SHARP edge only — with a rounded edge the patch sits inside the bore and `91`'s reaction is slightly larger), and the tube's flush END lands on the bore's exit edge at **0.061°** (rigid wall) — edge on edge, the form the ≥ 1.0 mm protrusion avoids at the mouth, with the exit radius ratified only as a FORM — a radius, not a chamfer (`00_07` HW.34, 2026-09-18) — and its value NOT SPECIFIED (`edge_bearing.exit_contact`).
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

🔑 **What moves.** (1) The rigid-wall root stress under drag sits far below the two stresses `55` used to price at that section (18.3 MPa nominal on the 6 mm column, 43.0 at the retired seam corner) — and it is the LOWER end of the root stress, the Ti-bore stop in the last column its upper (`coaxial_cap_bound`; a rigid wall prescribes the exit at the play, the polymer wall yields by R/k); ⛔ no seam `k` is re-derived from either end — the compliance that places the amplitude is unmeasured, a static offset puts a MEAN stress on the same section, and no mean-stress correction exists anywhere in the tree (the table IS the seam-acceptance input: the rigid-wall and upper-end columns bracket the coaxial amplitude, the secant is the mean per µm past the play, the reversing amplitude a rigid-wall figure). (2) Under drag the contact is the tube's flush END at the pad-plane exit — ring on ring, the form the ≥ 1.0 mm protrusion avoids at the mouth — and the exit radius is ratified only as a FORM (a radius, not a chamfer), its value NOT SPECIFIED (⊕ 2026-11-02: the value is ratified since — 0.2 mm, `116` (E) below). (3) Off-axis the mouth IS a contact station, so the protrusion and the entry radius keep a physical ground under misalignment. (4) **The peak-moment section is READ from the moment field of every solve since 2026-09-14, not asserted:** the root is the peak in every drag, offset and reversing-drag row; it leaves the root only on the lock-window geometry for a 9 mrad tilt about the MOUTH (the play is taken up on both walls and the rod bends between them) and for the pogo couple on the rod's end face (the couple applied at the exit exceeds the long rod's small root moment) — `peak_moment_section`, and the prose «in every configuration computed here» that stood in this cache was false on those rows. (5) The insertion is priced since G1 (2026-10-12): on the shipped geometry the offset secant is 0.64 MPa/µm — an order of magnitude below the retired placeholder's 5.74 — so the coaxiality number a drawing must demand can now be priced (HW.34's leg; the flip condition `01_01 §1.4` «Співвісність» wrote for exactly this case has fired); on the shipped geometry an off-axis pogo contact and a reversing drag over an offset both exceed the rigid-wall coaxial figure. ⛔ Ceilings: rigid frictionless wall (no liner compliance or contact pressure), perfect clamp, offsets · tilts · eccentricity swept and never measured, no liner creep, no P-δ. (`mechanical/bus_contact_equilibrium.json`)

🔬 **COAXIALITY PRICED, script `86` (2026-10-12 — ⚖️ exception to the crown pause, `00_07` HW.34).** The condition `01_01 §1.4` «Співвісність» wrote in advance fired with G1, but a loose allocation puts a static MEAN on the root, and until this block the tree had no mean-stress correction, so the flip could not be weighed. `86` adds one — Soderberg, 1/SF = σ_a/σ_e + σ_m/σ_y: the yield line, because the tree carries no ultimate strength per alloy, and more conservative than Goodman — over `68`'s cache. The mean is the worst static root stress over the six plays `68` sweeps (a rigid-wall upper bound under an offset), the amplitude the upper end of the coaxial bracket at the worst swept µ, worst play (the Ti-bore stop — ⊕ 2026-10-14: no elastic state of the exit reaches it in `91` — the unworn coaxial peak sits at the bracket's LOWER end, and exit wear saturates the peak once the mouth engages — so this amplitude is a conservative bound whose state is unidentified; the OFFSET regime's mouth station, which this block prices, `91` does not compute), σ_e the welded branch of `55`; the seam column is the knock-down `k` a weld must carry for the joint to stay on the SF-2 line. Shipped geometry, binding alloy Ta in every branch:

| allocation (total radial offset of the channel axis from the root axis, as the ISO 1101 zone) | static mean, MPa | wire SF (rounded down) | seam `k` needed (rounded up) |
|---|---|---|---|
| tight ⌀0.04 | **0.0** | **5.63** | **0.356** |
| loose ⌀0.10 | **14.7** | **4.54** | **0.389** |
| loose ⌀0.20 | **51.6** | **3.05** | **0.507** |

🔑 **The flip is real.** The loose ⌀0.10 branch raises the `k` the seam must carry by 9.3 % and leaves the wire at SF 4.5, while the tight one needs the WHOLE stack inside 20 µm — the flange member ⌀0.05 alone already spends 25. ⌀0.20 is where the price turns: `k` 0.507 crosses our own comparison marker 0.50 (`AS_PRINTED_DERATE`, a scale, not a measured seam). At the lock window's shallow end every branch is softer (`k` 0.286 · 0.303 · 0.357). The control holds the zero-mean SF against `55` on the zero-interference play (5.804 vs 5.80); the amplitude used is the worst play, which is why the tight row reads 5.63, not 5.80. ⛔ Ceilings: weld residual TENSION is a mean this file does not carry — it raises every `k` row, so a vendor `k` must be quoted with the post-weld treatment we ship; the seam row divides the mean by the WIRE's yield, and a lower heat-affected-zone yield raises it too; Soderberg, the upper-end amplitude and the rigid-wall mean are each the conservative choice; the machining and inspection cost of tightening is not priced. ⚖️ The founder chose ⌀0.10 on 2026-10-12 (verdict, price and weakest link — `01_01 §1.4` «Співвісність»; the split of ⌀0.10 between the stack's members is the open leg, `00_07` HW.34). (`mechanical/coaxiality_allocation.json`)

🔬 **THE EXIT CONTACT AS AN ELASTIC LAYER, read over the drag CYCLE beside a rigid wall at the same edge — script `91` (2026-10-14; the `00_07` HW.34 🤖 leg «контактна модель лайнера», free since the crown pause was lifted for measurements on 2026-10-13; rebuilt twice the same day after three adversarial passes — the first version read the root at full drag, the cycle's MINIMUM, and the second attributed effects against references the elastic solve itself had chosen).** Every line above stops at the same sentence — the contact compliance that places the root inside `68`'s bracket is measured nowhere — and so does `55`'s wear budget, whose contact area spans the flow-limited patch to the whole bore run (thousands apart, `k_span_ratio`) and whose in-contact sliding spans zero to the Ti-stop rotation. `91` models the contact itself: the 0.15 mm liner as an elastic PEEK layer on the rigid wire (bonded ⊥ frictionless — the hot-mounted grip is neither), the Ti channel as an elastic half-space, the gap of a rod displaced inside a bore plus the edge's rounding, the rod as `55`/`68`'s cantilever through the exact Mohr flexibility, solved by Polonsky–Keer on a DC-FFT and read along the drag PATH from touchdown to µ·F, every figure beside a RIGID wall touching at the same edge. Controls that can fail: the layer kernel against its confined-column and half-space limits, the kernel at two periodic paddings, Hertz on the half-space, a thin bonded layer against its Winkler asymptote, the Mohr flexibility against the FE touchdown drag, the rigid limit reproducing `68`, the pad couple reproducing `68` (d), the smallest radius's edge peak at two steps, a sharp edge inside the layer growing as ρ^(−½). Still a MODEL: still not measured.

| exit edge radius r, mm | cycle peak, MPa | rigid wall at the same edge (touchdown), MPa | at µ 0.5, MPa | rigid wall at µ 0.5, MPa | sub-cycle, MPa | rigid sub-cycle, MPa | sliding at µ 0.5, µm/cycle | of it, the compliance | edge peak, worst row, MPa |
|---|---|---|---|---|---|---|---|---|---|
| 0.05 | **3.409** | **3.404** | **3.118** | **3.282** | **0.292** | **0.122** | **0.31** | **68.5 %** | **90.4** |
| 0.1 | **3.414** | **3.411** | **3.010** | **3.167** | **0.404** | **0.244** | **0.40** | **51.5 %** | **73.5** |
| 0.2 | **3.427** | **3.426** | **2.794** | **2.938** | **0.632** | **0.487** | **0.59** | **33.7 %** | **59.6** |
| 0.3 | **3.441** | **3.440** | **2.577** | **2.709** | **0.864** | **0.731** | **0.77** | **24.6 %** | **53.6** |
| 0.5 | **3.470** | **3.470** | **2.141** | **2.252** | **1.329** | **1.218** | **1.14** | **15.3 %** | **47.0** |

(shipped geometry, flush exit with a rounding, zero-interference play, bonded liner, short-term modulus; the edge peak is the worst row over base and modulus at µ 0.5 on a 1 µm step; «of it, the compliance» is the share of the sliding a rigid wall at the same edge does NOT produce)

🔑 **What it says, claim by claim.** **(A)** The liner gives **0.27–0.40 µm** at full drag against a 150 µm wall. **(B) The cycle peak sits at or just after touchdown**: **3.409–3.471** MPa, ×**1.004–1.022** of `68`'s **3.397** MPa. On a rigid wall at the same edge it is F_td·L — the edge radius lifts it by ≤ **0.074** MPa over the flush value — and while the patch is tiny the give lifts it by ≤ **0.008** MPa more (`68`'s sign). **(C) On the loaded part the sign turns**: at full drag the compliance LOWERS the root by **0.11–0.21** MPa against the rigid wall at the same edge (the patch spreads inside the bore, and that outweighs the give) and deepens the sub-cycle touchdown → full drag up to ×**2.8** of the rigid one (table). **(D) The bracket's upper end is not an elastic state**: the peak climbs ≤ **0.136** MPa per µm of exit wear — an upper bound, for a worn wall that follows the rod's touchdown shape back to the mouth; a short scar climbs less — until the mouth engages after **50** µm, and from then on the touchdown is at the mouth and the peak SATURATES at **10.24** MPa; `68`'s 23.8 needs **33** µm of MOUTH wear on top (`wear_path`). **(E)** The edge peak, resolved at a 1 µm step, stays below the 23 °C tensile yield at every swept radius (table; the 20-yr relaxed modulus LOWERS it — the anti-conservative end for the peak) — ⊕ 2026-10-15 (`92`): COAXIALLY; at the ratified ⌀0.10's offset limit (50 µm) the exit edge's cycle peak is ×**1.23–1.29** this and passes the yield at r 0.05 mm (×**1.18**), so under an offset the exit radius has a floor of **0.1** mm (the smallest swept radius that holds — shipped shank, entry radius 0.2 mm, flush exit, zero interference); the elastic patch is ×**26–39** the flow-limited area `55` binds on. **(F)** The frictionless sliding — a kinematic ceiling — is at most **1/14** of `55`'s upper end; the compliance carries **15.3–68.5** % of it against a rigid wall at the same edge (table), the edge's own geometry the rest. **(G) A pogo contact off the rod axis moves the MEAN, not the amplitude**: over a reversing drag the extremes are the two touchdown values, where elastic = rigid, so for |e| = 0.5 mm the cycle runs −5.89 … +0.96 MPa — amplitude **3.426** MPa, exactly the on-axis one, mean shifted by **2.46** MPa (`68` (d) reproduced on the rigid flush wall); the exit section then carries ≈ the couple itself, **5.1** MPa nominal — a section the wire's notch factor may govern, which nothing computes. **(H)** Lumped full-stick friction (rigid in shear: an upper estimate) opens the cycle into a loop — at r 0.05 mm, **0.41** MPa against the frictionless sub-cycle 0.29 — and at r ≤ 0.1 mm moves the peak to full drag. **(I) The ratified countersink is CONDITIONAL**: the tip passes the bore line already at touchdown (**0.8–2.6** µm; at full drag 1.7–7.0), so a PEEK ring whose bore equals the channel's is the FIRST contact — PEEK on PEEK at the rod end — which no model here has. Only for a ring that clears the tip do the rows hold: the cycle peak ×**1.031–1.103** of `68`'s figure, the full-drag moment reversing beyond e ≈ **1.29** mm, the sub-cycle up to **5.39** MPa, the sliding up to a quarter of `55`'s upper end, the reaction up to +10 % over «drag − touchdown» (that bound holds for a flush sharp edge only). **(J)** A sharp Ti edge INSIDE the layer — the countersink's, the mouth's, past which the liner continues — is a punch edge: its peak grows ×**1.41** per halving of the step (ρ^(−½)); the flush sharp corner of the shipped CAD is outside the kernel, bounded only for a frictionless contact (under stick a clamped–free 90° wedge, ≈ ρ^(−0.35)). So a radius is wanted at every Ti edge the liner bears on — and the edge radius is a trade (a larger r lowers the edge peak, lifts the cycle peak a little and raises the sliding) that neither side makes binding on these numbers (coaxially — under an offset at the ⌀0.10 limit the edge-peak side binds, ⊕ in (E)): it is weighed by a measured wear rate and slip regime (the tribo test), not by this model.

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

🔑 **What it says, claim by claim** (each asserted in-run or written from the rows). **(A)** The layer's give lowers the static root against a rigid wall at the same edges by **0.8–1.5** % on every row — `68`'s secant stands. **(B)** A larger entry radius lowers the static root and the static mouth-edge peak on every offset row; the beam's swing it moves by only **−4…+4** %, and not one way. **(C)** The drag raises the mouth-edge peak above the static one on every shipped-shank row (by **2–18** %). **WITHIN the ratified ⌀0.10 and at zero interference the mouth-edge cycle peak stays below 1·σ_y on every swept shank and entry radius — the worst ×0.93** (shank 18 mm, r_in 0.05 mm); BEYOND it, at 75–100 µm, it passes 1·σ_y on **9** rows (the largest ×**1.67**), and the smallest radius that holds at 100 µm is **0.1** · **0.2** · **0.3** mm for the mouth at 22 · 18 · 14 mm; below 3·σ_y everywhere. **(C′) Under an offset the EXIT edge is the more loaded one:** at 50 µm — on the shipped shank with entry radius 0.2 mm, the flush exit (no countersink) and zero interference — its cycle peak is ×**1.23–1.29** the coaxial, it passes 1·σ_y at r_exit 0.05 mm (×**1.18**), and the smallest swept exit radius that holds there is **0.1** mm — `91`'s «below the yield at every radius» is a coaxial reading. **(D)** Where the edges are rounded, the root's swing along the path is larger than its two ends give: the ends alone catch as little as **13** % of it (at 35 µm, where the swing itself is smallest); at the offsets `68` tabulates, its sharp-edge rows sit within **3** % of this path's swing. Against `86`'s threshold k ≥ **0.3882** (amplitude **24.51** MPa, the Ti-bore stop; mean **14.7** MPa, the worst play): at 50 µm and zero interference the root cycle runs at **13.90** ± **4.09** MPa on the shipped shank and needs k ≥ **0.065** (`86`'s formula, binding over its six alloys), **0.046–0.065** over the swept shanks — the threshold covers these cycles through its AMPLITUDE, not its mean: on the 18 mm shank the cycle midpoint, **23.89** MPa (static **20.63**), lies beyond `86`'s static mean. The cycle at the worst play and a pogo-pad couple on top of the offset are computed by no model (⊕ 2026-11-02: on the shipped shank `116` combines them — every `68` play × the pogo couple over the 50 µm offset — and the seam threshold does not move, (D) of its block below; on the other shanks still not). **(E)** From 50 µm on the wire under the MOUTH edge swings ±**7.90–8.00** MPa against the root's ±**4.21–4.27** (×**1.88**), around a mean of the opposite sign; the ratio crosses 1 at **30** µm (below it coaxially, ×**0.53**, and just past the play, ×**0.58** at 26 µm, ×**0.80** at 28) and peaks at ×**2.19** near 40 µm because the root's swing dips there (±**2.47**), not because the mouth section's grows. No notch factor under that edge is computed. **(F)** Bonded ⊥ frictionless base and the 20-year modulus move the static root by ≤ **0.03** MPa; the relaxed modulus lowers the mouth peak at the drag's ends from **46** to **33** MPa. **(G)** A mouth nearer the root makes the same offset dearer: the static root at 50 µm is **8.32** · **12.35** · **20.63** MPa for a shank of 10 · 14 · 18 mm.

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
⊕ **2026-11-02 (`116`, block below; the `92` line above not rewritten):** that 0.1 mm floor holds in `92`'s frame only — zero interference, no pad couple. On `68`'s largest play (30.37 µm) with the pogo contact 0.5 mm off the rod axis the flush exit edge reaches **105.0** MPa at r 0.1 mm, and the floor at the tolerance limit is **0.15** mm (inside the tolerance it holds on every row that solves, and part of the −µF end there does not — block below).

🔬 **THE COUNTERSUNK EXIT — the ring's bore, the exit radius's floor and what the depth costs — script `116` (2026-11-02; the 🤖 step of the `00_07` HW.34 leg «геометрія площини площадки»).** The ⚖️ (02_02 §1.2) put a PEEK ring in a countersink round the channel exit and the Ti exit edge D below the pad plane; depth, ring bore and exit radius were to be chosen together. The founder chose (2026-11-02) a ring that CLEARS the rod (a ring bored to the channel is a PEEK-on-PEEK first contact no test measures), so the model needed is the one the tree has — `92`'s two-window solve and `91`'s rod — carried to a countersunk exit and a pogo couple by two arguments that leave `92` unchanged at zero (its exit rows reproduced bit for bit; `91`'s countersink rows and closed forms, `92`'s rigid swing reproduced). The pin's tip sets only the ring's OUTER diameter and enters nothing here; the pin enters through its spring force (55's 1.0 N, the adverse end of what the tree knows). Two choices of the adverse corner were made by measurement, not by the cheap rigid model: the rigid exit REACTION peaks just past the play and is largest on the smallest play, while the elastic edge PEAK rises to the tolerance limit and is largest on the LARGEST play and the couple's + end (monotone on every sampled cell; every play × couple re-run at each depth's floor).

| Depth D (mm) | Exit-radius floor at the tolerance limit (mm) | Peak at the floor · one radius below (MPa) | Ring bore over the channel, radial, at the floor · over r 0.05–0.5 (µm) | Coaxial sub-cycle at the floor (MPa) | Slide per cycle at the floor (µm) |
|---|---|---|---|---|---|
| D 0 (flush) | **0.15** | 92.49 · 105.0 | — | 0.52 | 0.49 |
| D 0.25 | **0.15** | 93.8 · 106.58 | **2.56** · ≤ 4.38 | 1.10 | 0.96 |
| D 0.5 | **0.15** | 95.08 · 108.11 | **3.86** · ≤ 5.84 | 1.69 | 1.42 |
| D 1.0 | **0.15** | 97.54 · 110.96 | **6.81** · ≤ 9.11 | 2.88 | 2.32 |
| D 1.5 | **0.15** | 99.91 · 113.59 | **10.22** · ≤ 12.85 | 4.07 | 3.21 |
| D 2.0 | **0.2** | 93.13 · 102.16 | **14.51** · ≤ 17.07 | 5.39 | 4.15 |

(Floor: the smallest swept radius 0.05 · 0.1 · 0.15 · 0.2 · 0.3 · 0.5 below 1·σ_y = 100 MPa on both grids at the tolerance limit, on the adverse corner — largest play, couple + — verified by the full cycle. At the interior offsets 30 and 40 µm — both corners, both drag ends, the −µF end on both couples, **8** rows at each depth's floor — every row that solves stays below 1·σ_y, and on D ≤ **0.5** mm some do not solve: **3 · 3 · 2** rows at D 0 · 0.25 · 0.5, all at the −µF end (a line contact that two end windows cannot represent) — a check not made, not a pass. Ring bore: the largest excursion of the rod above the Ti edge past the bore line, rigid over offsets 0–50 µm, every play, both couples, at µ·F 0.5 N, plus the largest elastic increment measured at that depth, **0.75–0.92** µm, rounded up.)

🔑 **What it says.** **(A) The ring that clears needs micrometres, not tens:** at most **17.07** µm radially at the deepest swept countersink, **2.56–14.51** at the floor radius — within the order of a machining tolerance, so the ring's bore is a tolerance call, not a geometry change. **(B) Every rod-side cost rises with depth**: the exit edge's peak, the coaxial sub-cycle (×10 from flush to 2 mm), the slide, the ring's clearance; the coaxial full-drag root moment reverses past **1.338** mm at r 0.15 (0.988–1.438 over the radii). So the model gives no floor to the depth — the ring's own retention does, and it is not designed. **(C) The exit radius's floor is 0.15 mm on the flush exit already** once the play band and the pogo couple enter, and stays 0.15 mm to D 1.5 mm — at **99.91** MPa there, a hair under 1·σ_y — then 0.2 mm at D 2.0. **(D) The seam is not moved:** under the tolerance offset the root's cycle needs `k` ≤ **0.0856** on `86`'s own formula and alloys, against its binding **0.3882**.

⚖️ **(E) The founder set the trio by rule (2026-11-02, `00_07` HW.34; the verdict's home is `01_01 §1.4` ⊕):** the exit radius is **0.2** mm at every depth up to 2.0 mm, the depth the least the ring's retention and strength allow, the bore the channel plus twice the clearance at that depth and r 0.2 plus the ring's position tolerance and the liner's pull-back — and the elastomer closure does not sit in the ring's bore. Block (d) runs the floor's own procedure at r 0.2 on every swept depth — every play × couple (**18** cells), the full cycle on the adverse corner, the interior offsets — and r 0.2 holds on each: peak ≤ **93.13** MPa (**84.44** at the flush exit), at least **6.8** % under 1·σ_y; the −µF end leaves **2 · 2 · 1** of 8 interior rows unsolved at D 0 · 0.25 · 0.5 (3 · 3 · 2 at the floor) — a check not made, not a pass. What r 0.2 costs over the floor: the ring's clearance +0.25–0.36 µm, the coaxial sub-cycle +0.12 MPa, the slide ≤ +0.09 µm per cycle, the full-drag reversal at **1.288** mm against 1.338, the seam `k` ≤ +0.0003.

⛔ **Ceilings:** `91`'s and `92`'s (linear elasticity with the flow pressure flagged, a flat layer, bonded and short-term only, no friction in the exit block, no thermal term, no wear) · the flow pressure is 23 °C tensile yield · a PLANAR model · the ring's position tolerance on the channel and the cold liner's pull-back are NOT in (A) and add to it · the exit closure element is not modelled — in the ring's bore it would be a soft contact · the ring's retention and thickness floor are not modelled · the spring force 1.0 N (a stiffer P/N re-runs it) · inside the tolerance the floor is checked at 30 and 40 µm at the drag's ends only, and on the shallow depths not on every one of those rows (counts above). (`mechanical/countersink_ring_exit.json`)
---

## HW.43 — The Bus Wire in Its Liner: Root Load and Pad Travel (script 102)

`87` (2026-10-17) left two conclusions open behind the liner: where between `86`'s own seam requirement and the
reading at the liner wall's ceiling the real requirement lies (HW.34), and how much of the centre-pad term (C) reaches
the pin. `102` is the model it named — the wire and the liner as a shear-lag pair with Coulomb slip (`55`'s grip per
tolerance part and μ). With the flange shifted δ from the anode, the liner collects the force at its held top over a
slip zone, the pair sticks below it as a composite, and the wire carries the force through the bare run to the weld
root. The wire's own stretch is capped with the force — at most 12.9 – 29.9 µm at the wall's cap, by alloy — so the
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

| alloy | `86` alone | gentle, shares 0.25 – 1 | adverse, ¼ | adverse, ½ | wall's ceiling (`87`) | its cap clear below share (sway alone, one temperature) |
|---|---|---|---|---|---|---|
| Ti-15Zr | 0.1331 | 0.16 – 0.19 | 0.31 | 0.42 | 0.51 | 0.74 |
| β-Ti-13Nb-13Zr | 0.1408 | 0.17 – 0.20 | 0.31 | 0.42 | 0.54 | 0.82 |
| Ti-6Al-4V | 0.1441 | 0.17 – 0.21 | 0.34 | 0.47 | 0.55 | 0.71 |
| Ti-6Al-7Nb | 0.1494 | 0.18 – 0.22 | 0.35 | 0.48 | 0.57 | 0.73 |
| CP-Ti Gr4 | 0.272 | 0.32 – 0.39 | 0.63 | 0.86 | 1.03 | 0.73 |
| Ta | 0.3882 | 0.47 – 0.58 | 1.03 | 1.37 | 1.48 | 0.58 |

The requirement sits above `86`'s own k at every share above zero, even on the gentle corner, so the vendor's seam k
cannot be accepted against 0.389 on Ta in any corner with the wood imposing anything. Below the last column's share
(rounded down — an edge of the insulator's harmless region under the sway ALONE at one temperature: the hot-edge
preload below adds to it; the cap binds from the next hundredth up in every row, and `102`'s verdict prints that onset
for Ta and Ti-6Al-4V) the cap stays clear; once the ceiling binds, the liner wall reaches its 23 °C yield every sway cycle — the insulator, not only the seam (the yield and the grip are 20 °C
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
edge of 11.8 – 14.8 µm; at the hot edge a part at the window floor grips with nothing and its pad recedes 18.4 – 43.0 µm
against 17.4 – 19.4 µm to the lower edge, past the larger margin on 3 of 4 readings; on the shipped span at the capsule edge even the tightest grip
recedes 26.3 µm, past both. The smallest protrusion
comes from a reading below the wall's cap, and a capture or wall that gives way moves the pad further. **The premise decides it** (📌 2026-10-20 — not for pricing a fix: within the model the wood only shortens the thermal travel, with the flange on the bark and on a rigid Zone-3 fit (the placeholder shank) alike, `103`,
§«How Much of the Stem's Shift Reaches the Anchor?»): a bonded anode and a flange on the bark make the span follow the wood's own radial
expansion instead, and the cold result then holds while the span's effective CTE stays above 25.2 – 25.7 ppm/K by
reading (38.0 – 39.0 if a Zone-3 fit locates the flange and only the gap follows the wood), the hot one above
25.9 – 31.4 — against 47 for free PEEK, and each threshold rounded up; the wood's radial CTE is not in `102` (📌 `103`
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
stays below 10140 N/mm (cold) ⊥ 4948 N/mm (hot) at the stiff bond, and never at any bearing at the soft one; in state 3
at the stiff bond, the pad stays out only while the tie sits deeper than 9.4 mm (cold) ⊥ 14.4 mm (hot), even with no
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
| Ta's seam passes k 1 on the sway alone (adverse reversed corner) | 3606 N/mm | never |
| Ta's seam passes k 1 with `102`'s hot preload (adverse reversed corner) | 971 N/mm | 4153 N/mm |
| the centre pad's hot conclusion flips | 4948 N/mm | never |
| the centre pad's cold conclusion flips | 10140 N/mm | never |

In the mature state the tie's depth and stiffness, the anode bond and the bearing decide together, and of these only
the bearing can be measured on a log — where it no longer settles anything alone.

**The seam.** Ta on the adverse reversed corner needs 0.3882 on the sway alone in state 1 and 0.64 with `102`'s seasonal
hot preload, which is the anchor's own mismatch and acts in every state; in state 2 at the air-dry bark readings, up
to 0.72 on the sway alone and up to 1.03 with the preload; in state 3 at the stiff bond, at least 0.92 on the sway alone
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
the cold conclusion does not flip below 3357 N/mm and the hot one below 3164 N/mm, and never at the soft bond; in state 3
with no bearing the cold one holds only while the tie sits deeper than 23.8 mm on the capsule-edge reading — the
deepest tie is 24 mm, and at the anode's full bond depth not even there — and at no depth on the cambium reading, the
hot one at no depth (a hot threshold exists on the capsule-edge reading only — at the cambium the free gap does not
leave the window hot), while at the soft bond both hold at every depth. On the seam `102`'s hot preload on the fit's span is 35.9 N on Ta against 48.3 N on the 32 mm one, yet
Ta still needs 0.55 in state 1 — not acceptable against 0.389 at a share of zero — and its seam passes k 1 with the
preload in state 2 not below 1943 N/mm at the stiff bond; in state 3 it needs at least 0.92 on the sway alone and 1.18
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
re-derives `102`'s cached pad travel to 0.000 µm) and on every grip of `102`'s window — the loosest, a part at the
window floor relaxed at μ 0.1, is not among the four `102`'s heat reads, so the cold protrusion on the 18 mm span is
35.5 µm, not 34.0. The Zone-3 shank there is read bonded to the PEEK over its run (the fits' one rule; with it as Ti
the need is 22.8 µm instead of 23.7).

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
| 18 mm — the Zone-3 fit, canon's Ø11 under interference | 23.7 ⊥ 20.8 µm | 37.3 µm | 24.7 ⊥ 37.8 µm | 38.4 ⊥ 51.4 µm |
| 32 mm — the placeholder, the shank in the gap | 51.1 ⊥ 48.1 µm | 64.7 µm | 51.4 ⊥ 60.3 µm | 65.0 ⊥ 74.0 µm |

Left as is, the stroke leaves the window on both sides on the 18 mm span — 1.7 % of the stroke past 70 % and 0.6 %
under 50 % held, 2.7 ⊥ 2.2 % with the upper-whisker sway — and the low side is the canon's loss-of-force direction
(`02_02 §3.5`, «Z-стек задовгий»).

At `103`'s largest share the sway alone swings ±20.3 ⊥ ±41.3 µm on the 18 mm span (±22.4 ⊥ ±45.5 on the 32 mm one) —
past L1's smaller margin at both shift readings — so on the held + sway reading no remedy that acts on δ closes the need
by itself: the held part cannot go below zero.

What each remedy buys — the spare it leaves, a shortfall in parentheses:

| family | remedy | 18 mm: held · radome leading · + sway (median ⊥ upper whisker) · both (upper whisker) | 32 mm: held · + sway (upper whisker) |
|---|---|---|---|
| L1 residual | bayonet hard-stop (L2 — `52`'s CNC member 0.10 → 0.05 mm), +41.0 µm | 17.3 · 3.7 · 16.3 ⊥ 3.2 · (10.4) | (10.1) · (19.3) |
| | L2 with a 0.05 mm spacer step, +56.0 µm | 32.3 · 18.7 · 31.3 ⊥ 18.2 · 4.6 | 4.9 · (4.3) |
| | the CNC member at ±0.05 mm by a tolerance class | as L2, if the member is machining tolerance | as L2 |
| | a 0.05 mm spacer step ⊥ none at all, +8.0 ⊥ +12.0 µm | short | short |
| pin's window | a longer stroke, the deck re-spaced to keep 60 % nominal | from 1.637 mm · 1.773 · 1.647 ⊥ 1.778 · 1.914 | from 1.911 mm · 2.003; with L2 1.501 · 1.593 |
| δ itself | the PEEK run's length | gap ≤ 5.7 mm — the Zone-3 shank ≥ 26.3 mm — held only | run ≤ 5.8 mm, the shank cut to 4.3 — held only |
| | the PEEK run's effective CTE | ≤ 21.5 ppm/K (22.1 if the grade fills the shank's composite too) — held only | ≤ 16.4 ppm/K — held only |

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
to 0.467, and with `103`'s sway on top at its least state-3 corner on a stiff bond from at least 1.186 to 1.117 — the
sway alone asks at least 0.929 there, so Ta's seam stays past k 1 either way; at `103`'s caps the liner wall binds and the δ
routes change nothing (Ta 1.471), the length route even raising some capped corners slightly (its longer liner run
grips more); on Ti-6Al-4V no corner passes 0.528. The window side leaves the seam where it is.

**Sensitivity, and what is not priced.** The placeholder shank (HW.8.9) at `92`'s 10 ⊥ 18 mm moves the held need on
the 18 mm span to 31.6 ⊥ 15.9 µm — at the short end, past L2's radome-leading and upper-whisker spares. Not priced: the
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

## HW.23 — What the Stem's Sway Puts into the Anchor's Titanium Parts (script 105)

The S-N plan (`docs/protocols/anchor/sn_fatigue_test_plan.md` §1.3) accepts a printed part by its endurance against
`K_f · S · σ_n`, and until `105` no model gave `σ_n` for the shanks, the barbs or the flange — for the gyroid it gives a lower
bound and, beside it, a uniaxial-state reading of the ligament peak. `105` lists
every path the sway takes into them (in-silico §Critical Rules #15 — the full list, with each one's status, is the
cache's `paths`) and prices the ones a closed form reaches. The endurance markers are `55`'s and OURS (`0.40 × 0.5 × σ_y`
printed, `× 1.0` for the CNC route the flange may take — `01_02 §1.7`), not a standard; SF 2 is `55`'s line.

**The gyroid is strain-controlled.** Bonded to the wood (the callus grows into it — `01_04 §2`), it follows the stem's
longitudinal strain across its section, so its ligament stress scales with `E_s · ε`, not with a force, and the figure
of merit of its alloy is `σ_e / E_s`, not `σ_e`. An energy bound (Hill, and the macro energy at a given strain being
least in uniaxial stress) puts the ligaments' RMS stress at ≥ 0.50–0.51 `E_s · ε` on the two voxel-FE readings of the part
as shipped after the HW.33 (в) geometry (finest-step readings 0.0940 axial ⊥ 0.0910 radial of `E_s` — per axis the adverse
end of the bracket [finest unlocked step 11/180 ⊥ finest locked step `/32`] over the pinned step sweep and the HW.23
re-sweep of 2026-10-23; the two-point Richardson pair they replace — 0.0805 ⊥ 0.0811 on this geometry, 0.0942 ⊥ 0.0662
before it — extrapolated a phase-locked error: the re-sweep's two finest unlocked steps agree to a few hundredths of a percent (the coarsest sits 0.5 % under them axially) while
the locked `/16` and `/20` rows sit 1.8–2.4 % under them axially (0.7–0.9 % radially) — `01_01 §5.2`, `00_07` HW.23) — and it
is a LOWER bound: it can show a ligament binding, never safe. Neither FE reading is the in-plane traction modulus the
bound needs (the radial case is a kinematic shell loading, the axial one E[100] of a cubic lattice), so the bound holds
only while that modulus is at least the reading; a binding claim takes the lower one, read from the pair:
the radial reading is the lower, the axial above it by 3.4 % (the locked `/32` row — 0.5 % under its unlocked neighbour, which the radial case's slower step
convergence leaves inside the bracket; the axial bracket closes to 0.05 %) — a finding of the caches, not a pick; every raw row of the step ladder has the radial one lower too. The table gives the stem's surface
strain above which the bound alone puts the ligaments at SF 2, at a share of the wood's strain t_L = 1 and a peak over
RMS k_p = 1, with near-uniaxial ligaments; a peak factor above 1 — the actual state's, of which the periodic case's k_p is only the
uniaxial-state reading — lowers every cell, a share below 1 raises it (the share
itself — `106`, the next section: it lies on both sides of 1). No cell is a strain below which the gyroid is safe. **The premise, read (2026-10-28):** a named static estimate of the
part's in-plane modulus (`01_01 §5.2`, `fea --traction`) lies above both FE readings at 45°, below both at θ = 0 and
between them at 22.5° on every measured step. It is a reading, not a bound — at a fixed macro stress any non-uniform
self-equilibrated load only adds energy, so it can sit on either side of the true static modulus — and it proves the
premise at no angle; where it is not above both, this table's «binds above» is not established. `105` reads it as
this check only, not in its thresholds — whether it should is an open leg of `00_07` HW.23.

| alloy | σ_e printed, MPa | σ_e/E_s vs Ti-6Al-4V | binds above, µε: large stem (lower ⊥ higher reading: radial ⊥ axial) | DBH 38, sensor on bark ⊥ on xylem (thick bark), lower reading | any stress state, large stem, lower reading |
|---|---|---|---|---|---|
| Ta | 69.0 | 0.23 | 367 ⊥ 361 | 498 ⊥ 435 | 704 |
| CP-Ti Gr4 | 96.0 | 0.58 | 912 ⊥ 897 | 1237 ⊥ 1081 | 1750 |
| Ti-6Al-4V | 176.0 | 1.00 | 1580 ⊥ 1554 | 2144 ⊥ 1874 | 3033 |
| Ti-6Al-7Nb | 170.0 | 1.03 | 1630 ⊥ 1603 | 2212 ⊥ 1933 | 3128 |
| Ti-15Zr | 190.0 | 1.19 | 1876 ⊥ 1846 | 2546 ⊥ 2225 | 3601 |
| β-Ti-13Nb-13Zr | 180.0 | 1.41 | 2222 ⊥ 2185 | 3015 ⊥ 2635 | 4265 |

The DBH-38 columns read the gyroid's shallow end (50 mm below the seat) through linear bending, against a sensor on the
bark and on the xylem under `103`'s thick bark; they are the field sensor's numbers (`00_07` HW.43), not a transfer from
another tree. The one stem reading in the tree — `87`'s source pine (DBH 21.5 cm, one gust of one January day), 1837 µε at
its surface, which `87` refuses to carry to our stems — placed on a large stem exceeds the threshold for CP-Ti Gr4, Ta,
Ti-6Al-4V and Ti-6Al-7Nb on both readings (before the HW.33 (в) geometry Ti-6Al-4V and Ti-6Al-7Nb stayed above it on
the lower reading, 1853 ⊥ 1911 µε, and bound only on the higher; now they bind on any FE reading above 0.0673 ⊥ 0.0716
of `E_s`, which every raw reading and both finest-step readings exceed, so the baseline alloy binds on every reading in
the tree; Ti-15Zr misses on the upper whisker, ×0.980 ⊥ ×0.995 of its 1876 ⊥ 1846 µε, and stays below while the FE
reading is below 0.09487 of `E_s`, which 4 of the 22 raw readings exceed; in any stress state CP-Ti Gr4 and Ta only, on
both — on the two-point readings CP-Ti Gr4 had missed that cell by a knife-edge, and the re-sweep's readings
carry it over), and its median (918 µε) for CP-Ti Gr4 and Ta only, on both (CP-Ti Gr4's median threshold sits just under
it). This one is every large-stem SF 2 cell whose flip lies inside the span of the FE readings `105` reads — the two
finest-step readings and the 22 raw readings of the step ladder; every other such cell keeps its side on all of them. β-Ti's high figure stands on a yield the tree carries without a source. Whether a host's stem
crosses these strains often enough is the field histogram's question, not this table's.

**The ligament field, read under a uniaxial macro stress.** The periodic voxel case (`01_01 §5.2`) gives the INFINITE
lattice's in-plane modulus E*(θ) and the quantiles of its ligaments' peak over their RMS, one periodic case (six
unit-strain solves) per rung, θ measured from the cube axis across the anchor's axis — the mount angle, when the wood's
strain runs along the stem. `105` reads them on the rungs of the part's density (`106`'s rule, /24–/64) as a peak per
unit `E_s · ε` of the macro strain, `k_p · √(E*/φ)` of one rung (the energy identity (σ_W/S) · E* = √(E*/φ) holds on
every rung — the control). It is a READING, neither this bound times a peak factor — the bound stands on the uniaxial
state being the least energy at a given strain, and the peak has no such order — nor the multiaxial state of the
inclusion in the wood; no state divisor applies, since the measure already holds the ligaments' state. Two choices are
named readings, not picks: the stress measure — the largest principal stress, the bound's own criterion, ⊥ von Mises —
and the quantile — p99, the highest that holds a band over the rungs (the maximum does not converge), ⊥ p99.9. Whether
p99 sits at or below a smooth ligament's fatigue peak is not established: the staircase's outer voxel layer is a large
share of the metal at every rung, and the hottest points are not localised (`01_01 §5.2`, ceiling (3)). At p99 the peak
is 1.45–1.58 `E_s · ε` along the cube axis and 1.09–1.27 at 45° over rungs × measures; each threshold takes the lowest —
von Mises at every sampled angle — and at t_L = 1 the ligaments on a large stem reach SF 2 above:

| alloy | binds above, µε: p99, every sampled mount angle | p99, θ = 0 | p99.9, every sampled mount angle | p99, every sampled mount angle, largest principal stress alone |
|---|---|---|---|---|
| Ta | 170 | 128 | 134 | 152 |
| CP-Ti Gr4 | 422 | 318 | 332 | 377 |
| Ti-6Al-4V | 731 | 551 | 575 | 654 |
| Ti-6Al-7Nb | 754 | 568 | 593 | 674 |
| Ti-15Zr | 868 | 654 | 683 | 776 |
| β-Ti-13Nb-13Zr | 1028 | 774 | 808 | 919 |

«Every sampled mount angle» is the highest threshold over θ = 0, 22.5 and 45° — a maximum over three directions, not a
ceiling over every angle; the angle criterion is the product `k_p · √E*` with `106`'s `t_L(θ)` (the peak factor falls
toward 45° while the modulus rises — `01_01 §5.2`). On this reading the source day's median (918 µε) binds every alloy
at θ = 0, and at every sampled angle every alloy but β-Ti-13Nb-13Zr, which sits at ×0.90 of its threshold: at 45° the largest
principal stress binds it on the /24, /32 and /64 rungs and von Mises on none — a knife-edge inside the span of
readings, not a member; its upper whisker binds
every alloy at every sampled angle, and read at p99.9 so does the median. These thresholds are not the bound tightened:
they read a peak rather than an RMS, on the infinite lattice's modulus rather than the part's, and t_L, the multiaxial
state of the inclusion and the smooth-peak quantile each move them (cache: `gyroid_ligament_field_uniaxial_reading`).

**The junction is a candidate the bound cannot see.** At t_L = 1 the bonded gyroid moves with the wood while the solid
shank in the soft sleeve does not, so the first cell layer at the junction absorbs 7.4 µm of radial mismatch on the
source day (sensor on bark, DBH 38) — 2.75× the wood's strain over one 2.0 mm rim period. That is an order of the
layer's distortion, not a stress; the stress needs a junction model. The mismatch scales with t_L, so its adverse end
is the HIGHEST share (`106`, next section), not 1.

**The anode's bond force** (`103`'s closed forms, held to its cached share caps on its own depth grid; `102`'s adverse
shift): in the mature state, with the callus tie at the install-day cambium, 746 N on a stiff bond and 103 N on a soft
one; 1654 N with a rigid sleeve at `103`'s stiff bond. It loads the Zone 1 shank at 7.85 MPa (K_f at SF 2 on the printed
4V: 11.20 reversed — the tie carries both halves), the DIN-471 groove root at 8.62 (10.20), and a barb root, equal rows
taken, at 26.33 MPa (3.34). The tie reverses the force, so the outward half lands on the barbs' lead flank — the ratchet's
easy side, which `01_01 §4.3` A says nothing loads in service; a row's ratchet force is not in the tree. The gyroid
carries the same force axially at its shank end: its own lower bound gives 0.48 of the SF-2 line on 4V (0.89 on CP-Ti,
1.24 on Ta) at that force, on the higher end of the axial bracket — the locked `/32` row, 0.05 % over
the converged unlocked one (`01_01 §5.2`, `00_07` HW.23) — which the script calls its conservative end; not additive
with the in-plane bound, whose cross term has no established sign.

**The flange disc** carries the bearing force only in `103`'s state 2 here — with a callus tie and a rigid bark both
holding, a titanium run between them would carry the wood's own strain, a corner with no physical meaning, so the
mature-state disc force is not bounded. On a Zone-3 fit (HW.8.9) the pull at the shank, reacted on a rigid bark at
673 N, gives the disc as an annular Kirchhoff plate (inner edge on the shank, outer free; the closed form held to an
independent finite-difference solve at the shank root and inside the groove):

| reaction | at the shank root, MPa | across the O-ring groove (radial moment, t − 1.34 mm), MPa |
|---|---|---|
| uniform over the bark annulus (`103`'s bearing area) | 72.59 | 20.38 |
| at the rim only (a dished seat — adverse) | 97.11 | 68.60 |
| at the channel's edge only | 37.65 | 2.60 |

On the adverse seat, one-sided (a bearing without preload), the shank root reaches SF 2 at K_f 1.51 printed ⊥ 2.58 on the
CNC route; the same number is its un-notched SF when a preload at least the force carries both halves — the only way a
bearing reacts both. On `103`'s air-dry bark reading the force is 65.8 N, an order lower: the bark bearing
decides the disc. With the flange on the bark (`103`'s premise (a)) the disc carries the force only through a preloaded
bearing, pressed by the sleeve's top face (31.9–49.1 MPa at 473 N). The Zone 3 shank carries 10.83 MPa and its barb root
38.72 MPa (K_f at SF 2 one-sided 3.78 printed ⊥ 6.49 CNC). The capsule's mass on its lever arm stays below 0.33 MPa.

⚠️ **Bounds.** The shank's nominal is its axial term only: the pin's bending by the stem's transverse shear and its
anticlastic curvature (S5) is not computed. E_z* and k_p of the INFINITE lattice are read from the periodic voxel case only as the
uniaxial-state reading above, never as a multiplier of this bound; the inclusion's field under the wood's multiaxial strain is not in that cache (its cases are uniaxial), the field under traction has no case, and the junction's stress needs a
junction model (gyroid + solid + sleeve end + wood); t_L is `106`'s (next section) and hangs on the tissue in the pores,
the wood's reading and moisture, and off the cube axis on the lattice's shear modulus; the callus annulus's stiffness is unknown. `62` counts first-mode cycles,
not strain ranges, so no amplitude here is paired with a count — the field record does that. No K_t (barb root, groove,
the disc's fillet, the groove's corners), no barb rows' split, no static mean (the PEEK's cold pull, heat, the bark's
growth preload and humidity strain — printed instead: the mean at which each member reaches SF 2). Ice, the collar and
the lug root (`73`/`89`), the printed face under the weld (`102`'s seam), the PEEK side of the barbs (HW.26's FEA), the
storm's few cycles and the daily heat are other forms. A bearing that reacts both halves of a cycle needs the growth
preload at least the force — `103`'s linear bearing presumes the contact holds. Cache:
`mechanical/printed_part_sway_stress.json`.

---

## HW.23 — How Much of the Wood's Strain the Bonded Gyroid Takes (script 106)

`105`'s gyroid bound takes the bonded lattice to follow the wood's longitudinal strain exactly, t_L = 1, and the bound
reads σ_RMS ≥ √(E_s·E_z*/φ)·t_L·ε — so a binding claim stands on t_L and on the lattice's in-plane modulus E_z* of the
SAME cell. `106` computes the share as an Eshelby inclusion: the Ø11 gyroid as a circular cylinder along the stem's
radius, bonded in Scots pine sapwood under the stem's bending stress, on the measured constants of Güntekin & Akar 2019
(*Drewno* 62(204):41–53, compression, four moisture groups at 45–95 % RH — the paper's own rows; its printed aggregates
hold ratios of the E and G rows of 45, 65 and 95 % RH to the printed digit, while the Poisson ratios and the 85 % RH row were read
off the tables only). Its compliances are not symmetric, so each pair's coupling is read three ways — from the test
loaded along the pair's stiffer axis, along its softer one, or the mean — and the softer-axis reading is not a material
at 65 and 95 % RH. The lattice's C11 and C12 come from reading `105`'s two voxel-FE ratios of the part as shipped after the
HW.33 (в) geometry (per axis the claim-adverse end of the finest-step bracket — previous section, `01_01 §5.2`) as one homogeneous cubic body
(ν* 0.336; the other root breaks the Voigt bound) — read as kinematic-side, i.e. possibly stiffer than the finite part under
traction; against the INFINITE lattice of the periodic case (`01_01 §5.2`), on the two finest-step rows as bases, its in-plane
dilatational term C11 + C12 is higher on every density-matched pairing of basis and rung (by 3–4 %) and its deviatoric term
C11 − C12 lower (by 4–7 %) — but the cube's rungs are phase-locked and scatter by the order of the smallest gap, so no
stiffness ordering between the two is established.
C44 is swept up to Voigt's ceiling φ·μ_s (a Zener ratio of at most 3.755) and, apart from the sweep, read from the
periodic case's measured tensor of the infinite lattice (below). The cube's angle θ to the stem's axis is the anchor's rotation at install, swept 0–45°. The pores take three
readings: nothing (the bare lattice — the composite's lower stiffness end), Voigt's
phase bound φ·C_Ti + (1 − φ)·C_wood (its upper stiffness end, if the tissue in the pores — Phase 3's xylem — is no
stiffer than the host's sapwood in every direction, which nothing measures), and the additive C_lattice + (1 − φ)·C_wood
— a reading, not a bound. Above fibre saturation `106` reads, as a separate group, green sets of four other Pinaceae
(«Green wood» below); every sentence before that paragraph is about the Scots pine group.

**The share lies on both sides of 1.** At θ = 0 — a cube axis on the stem's axis — it does not depend on C44, and which
side of 1 it takes depends on the pore reading (on the stiffer-axis reading it crosses 1 between the bare lattice and the
Voigt phase bound on every alloy but Ta in every moisture group) and on the symmetrisation
reading (Ta, 95 % RH, bare lattice: 0.683 on the stiffer-axis reading, 1.242 on the mean one) — for Ta the symmetrisation
reading alone decides it on the re-sweep's readings: its bare lattice is below 1 in every moisture group on the stiffer-axis
reading, and on the mean reading Ta's bare lattice is above 1 in every moisture group. On the two-point readings after the HW.33 (в) geometry Ta's bare
lattice rose above 1 at 45 and 65 % RH on the stiffer-axis reading, and before that geometry the moisture group moved its
side on the mean reading instead (below 1 at 85 % RH only) — both dated records. Off the axis C44 enters too: the share falls as C44 rises, and at θ = 45°
it crosses 1 inside the admissible C44 in 90 of the 120 cells the lattice's C44 enters.

| alloy | t_L at θ = 0, 95 % RH, stiffer-axis reading: pores carry nothing ⊥ additive ⊥ Voigt phase bound | highest θ = 0 share over the modelled set (no green reading raises it) | binds above, µε, SF 2, near-uniaxial ligaments, large stem, at the Scots pine group's lowest θ = 0 share: this tensor's E[100] (`105`'s axial reading) ⊥ `105`'s radial reading (its lower one) |
|---|---|---|---|
| Ta | 0.683 ⊥ 0.525 ⊥ 0.267 | 1.301 | 1349 ⊥ 1371 |
| CP-Ti Gr4 | 1.046 ⊥ 0.697 ⊥ 0.355 | 1.739 | 2527 ⊥ 2570 |
| Ti-6Al-4V | 1.004 ⊥ 0.679 ⊥ 0.343 | 1.691 | 4534 ⊥ 4610 |
| Ti-6Al-7Nb | 1.053 ⊥ 0.700 ⊥ 0.351 | 1.748 | 4568 ⊥ 4645 |
| Ti-15Zr | 1.076 ⊥ 0.709 ⊥ 0.360 | 1.774 | 5123 ⊥ 5209 |
| β-Ti-13Nb-13Zr | 1.265 ⊥ 0.780 ⊥ 0.405 | 1.982 | 5389 ⊥ 5479 |

The lowest θ = 0 share over the Scots pine group is, for every alloy, the Voigt-phase-bound cell of the stiffer-axis
reading at 95 % RH; the highest is the bare lattice on the driest softer-axis
reading (rounded up). The stiffness ends do NOT bracket the share: the additive reading falls outside the two ends'
shares in 9 cell-fields (2 on the green group), so the lowest share is the minimum of what is computed, never a floor.

**For `105`'s binding sentences the only C44-free figure is at θ = 0**, where the same tensor gives E_z* = E[100]
(filling the pores leaves the skeleton's energy at a given boundary strain at least the bare skeleton's): the bound alone
binds above `105`'s threshold over t_L, at the Scots pine group's lowest θ = 0 share — the table's right column, on this tensor's own
E[100] (`105`'s axial reading) and on `105`'s radial reading (`105`'s rule takes the lower of its two for a binding claim,
and since the HW.23 re-sweep that is the radial one — the tensor's E[100] sits above it by 3.4 %, so the radial column is the
conservative side of a binding sentence; it was the lower one before the HW.33 (в) geometry too, and on that geometry's
two-point readings the two had coincided within the extrapolation — `00_07` HW.23); rounded up from `105`'s unrounded
threshold. On a large stem the source day's upper whisker then exceeds the threshold for Ta only
on both readings (×1.36 ⊥ ×1.33 over it), and its median for none; at t_L = 1 on both readings the upper whisker
exceeded it for CP-Ti Gr4, Ta, Ti-6Al-4V and Ti-6Al-7Nb and the median for CP-Ti Gr4 and Ta. The column's ratios across
alloys are the gyroid's figure of merit with the share — σ_e/(E_s·t_L), with t_L depending on the alloy (its E_s, and its ν
in the Voigt phase bound) — not σ_e/E_s alone. Off the axis E[110] falls with C44 while the share stays finite, so the threshold has no ceiling as C44
falls and no binding figure exists there without C44; at θ = 45° E[110] falls under `105`'s radial reading below a Zener
ratio of 0.951 (under the axial one below 1.000, where E[110] = E[100]).

**On the measured C44 the threshold has a ceiling off the axis, and with the install angle free it does not rise above
the θ = 0 figure** (2026-10-27, `00_07` HW.23). The periodic voxel case gives the infinite lattice's whole cubic tensor
(`01_01 §5.2`); `106` reads its four rungs of the part's density (period/24–/64; period/16 sits 1.6 pp off the part's
porosity), each rung its own tensor (C44 0.42–0.44 of Voigt's ceiling on the rung's own solid fraction, a Zener ratio of
1.49–1.55). The part body has no
C44 of its own, so carrying one onto it is an assumption, and its form is a reading — the absolute modulus (a Zener
ratio of 1.60–1.62 on the body's own C11 − C12) ⊥ the measured Zener ratio itself (1.49–1.55); beside them the material
tensor read whole on its own solid fraction. On each reading one cell gives the share and E_z*(θ) of one tensor, and
in 144 of the 144 combinations of reading, rung, alloy and group the highest threshold over the modelled cells and every
angle is the θ = 0 one: for Ti-6Al-4V on the Scots pine group the gyroid binds above 4534 µε at most on the tensor's own
E_z*(θ) (4502 on the lowest reading — the material tensor, stiffer along its cube axis — each reading at its adverse
rung), and on `105`'s radial reading — the
table's conservative column, which has no off-axis counterpart — its θ = 0 figure, 4610 µε, stands. The binding cell explains it: it sits under the Voigt phase bound, whose share does not
depend on θ, while above a Zener ratio of 1 the lattice's in-plane modulus rises off the axis, so there the threshold is
highest at θ = 0. Over the cells the lattice's C44 enters alone the highest threshold rises off the axis in 120 of the 144
combinations, always at θ = 45°, by at most 3.5 % over its θ = 0 one (on the Scots pine group and the part body, Ti-6Al-4V 2288 → 2334 µε) — below the
binding cell. On the part body the tensor's θ = 0 end is `105`'s axial
reading; the material tensor's is its own E[100]. At θ = 45° the share exceeds 1 in 47–49 of
the 120 cells C44 enters.

**Green wood — a separate group of other Pinaceae** (⚖️ founder 2026-10-22, `00_07` HW.23, option (Б) by
recommendation). No open primary gives a full Scots pine set above fibre saturation (the search and its positive
controls — `00_07` HW.23), so `106` reads named green sets of four other Pinaceae (three sources) as a bracket of named readings, never
merged with the Scots pine group; each carries its doi, table, column, species, moisture and loading mode in the script:

- *P. radiata*, Davies et al. 2016 (*N.Z. J. For. Sci.* 46:19): four boards — stiff and non-stiff outerwood and
  corewood, told apart by ring width and curvature (sapwood or heartwood not reported; one board per type, so type and
  board are confounded) — each read as its Table 2 ⊥ its ESM 2/3 raw means by the paper's p. 4 rule as we read it. The
  paper states (Eq. 2) that Table 2 is a CI-weighted L1 symmetrisation's output; the open text does not reproduce it.
  Table 2 is symmetric by construction to its printed digits; against the raw means its E_L is ×0.52 in stiff outerwood
  and non-stiff corewood, and its ν_RL and ν_TL are ×0.12–0.50 of theirs in all four columns. MC is not printed;
  Table 1's densities put it at 108–139 % or more (our lower bound, per board type).
- *Larix principis-rupprechtii*, Liu et al. 2019 (*Forests* 10:456), Table 2 row P4 (sapwood): compression, all six ν;
  green logs, the trees' mean MC 95 % (discs over the whole section, heartwood included), P4's own MC not printed.
- *P. densiflora* and *P. koraiensis*, Jeong 2026 (*J. Wood Sci.*, in press, with internal contradictions; the copy
  read is pinned by its sha256 in the script, since the citation address no longer serves it — re-read Table 2 in the
  Version of Record): «green (saturated)», not stated never-dried; tension, which the author says underestimates the
  transverse moduli. It prints the stiffer-axis ratios only, so each pine takes that reading alone; that its ν_ij run
  load i, contraction j is our reading (it prints only the specimens' wider face and ν = −εx/εy). Red pine borrows ν_RT
  (measured, rejected by the author) and G_RT (not measured) — ours: ν_RT 0.94 from its own 19 % MC row,
  G_RT 74 MPa from Güntekin & Akar's 95 % RH group; Korean pine prints its ν_RT and borrows the same G_RT.

Through the same symmetrisation readings 26 green readings are materials and 3 are not (Davies' raw softer-axis
readings of stiff outerwood and of both corewoods). G_LR and G_RT do not enter the share: asserted, it does not move
(to round-off) with either scaled ×0.1 or ×10 on every live reading of both groups — so neither Davies' shear moduli
(G_LR ×5.6–18.0 and G_RT ×6.5–27.8 below Liu's; G_LT, which does enter, ×1.6–4.1 below) nor Jeong's missing G_RT moves
it. Jeong's borrowed ν_RT, swept over every measured ν_RT of the named readings (0.49–1.12), moves its θ = 0 share by
at most 0.0014 (asserted under 0.002), its off-axis cells by up to 0.351 — those stand on our value. Our arithmetic on
reciprocity: in Güntekin & Akar's four groups, Davies' raw means and Liu P4 the Poisson pairs with L break the equality,
the transverse-loaded entry the larger by ×1.89–10.25 (Liu et al. check the inequality only and state Maxwell consistency),
while the R–T pair deviates less, ×0.63–1.50 as (ν_RT/E_R)/(ν_TR/E_T); Davies' Table 2 meets it within its printed
rounding (checked).

| alloy | lowest θ = 0 share, rounded down: Scots pine group ⊥ union | binds above at the union's lowest, µε, SF 2, near-uniaxial ligaments, large stem: this tensor's E[100] (`105`'s axial reading) ⊥ `105`'s radial reading (its lower one) |
|---|---|---|
| Ta | 0.267 ⊥ 0.151 | 2383 ⊥ 2423 |
| CP-Ti Gr4 | 0.354 ⊥ 0.195 | 4594 ⊥ 4671 |
| Ti-6Al-4V | 0.342 ⊥ 0.188 | 8261 ⊥ 8400 |
| Ti-6Al-7Nb | 0.350 ⊥ 0.190 | 8400 ⊥ 8541 |
| Ti-15Zr | 0.360 ⊥ 0.197 | 9353 ⊥ 9510 |
| β-Ti-13Nb-13Zr | 0.405 ⊥ 0.221 | 9848 ⊥ 10013 |

Over the union the lowest θ = 0 share is, for every alloy, Davies' Table 2 stiff outerwood on the softer-axis reading
with the Voigt phase bound — its three symmetrisation readings differ by the printed rounding only (stiffer-axis ⊥
softer-axis ⊥ mean, Ta: 0.159 ⊥ 0.151 ⊥ 0.155). That is the adverse reading for a binding sentence and the consumer's
ceiling: there the source day's upper whisker exceeds the large-stem threshold for none of the alloys on either reading
(Ta ×0.78 ⊥ ×0.76 of it) and its median for none — against Ta on both readings on the Scots pine group, the price of
the choice. That is not a clearance: the bound is a lower one, so it can show «binds», never «safe». Without Davies' Table 2, on measured means only, the lowest moves to Davies' raw stiff corewood or non-stiff
outerwood, by alloy (Ta 0.173), and no alloy binds there either (Ta ×0.89 ⊥ ×0.87). Set by set, at each green set's
own lowest share, Ta binds on Davies' Table 2 non-stiff outerwood, Davies' raw non-stiff corewood (ESM NSC), Liu P4 and
Jeong's red pine on both readings, and on Davies' raw stiff outerwood (ESM SO) on this tensor's E[100] only; no other alloy
binds on any (on the two-point readings after the HW.33 (в) geometry Ta bound on Liu P4 and Jeong's red pine only and missed
ESM NSC by a knife-edge; before that geometry it bound on five sets on this tensor's E[100] and on Jeong's red pine alone on
the radial reading — the readings of the HW.23 re-sweep moved the knife-edges, `00_07` HW.23). On
Jeong's Korean pine Ta stays below (×0.987 ⊥ ×0.971 of it): it stays below
while ν_LR, printed 0.30 at a CV of 1.64, is below 0.308 on this tensor's E[100] (0.318 on `105`'s radial reading). Every green set but Jeong's red
pine puts the lowest share below the Scots pine group's for every alloy, Jeong's red pine above it (Ta 0.409): the
proxies do not settle the direction a green stem moves the share either — the full sets and Jeong's Korean pine lower
it, the one set with a borrowed ν_RT raises it.

**What settles the share:** the finite part's own C44 (the infinite lattice's, read above, is carried onto the part as an assumption), the tissue in the pores and the ring, which reading
of the paper's non-symmetric compliances holds, and a green Scots pine's own constants (the green group above reads other
Pinaceae). The install angle becomes a choice only
with C44 AND the tissue in the pores: at one C44 the angle that minimises the ligaments' stress factor √(E_z*(θ))·t_L(θ) — and so
raises their threshold — differs between pore readings (45° on the bare and additive readings, 0° on the Voigt phase
bound, at Ti-6Al-4V's 95 % RH stiffer-axis cell, at C44's ceiling, at 0.3 of it and on every measured reading); the junction's criterion is t_L(θ). The lowest share is the
lowest of the MODELLED set: the ring is read as the host's xylem, and a soft ring drives the share to 0 in its limit.

**The interface is a further unknown, and the model fixes it at perfect bond** (read 2026-10-22, `00_07` HW.23). `106`
has one interface — the gyroid's surface, displacement and traction continuous — and, the ring being read as the host's
xylem, the Ø15 channel wall is no interface at all. No primary in reach MEASURES the bond, or its absence, at either. The
conifer anatomy shows continuity or cell-scale interlock with the old xylem at a wound: after girdling, column-like
structures arise 5–6 cells below the wound surface from the parenchyma around axial resin ducts, show «the union zone
with the pre-wound xylem» and «anchor the healing tissue to the wound surface» (Chano et al. 2015, *Pinus canariensis*
saplings, ≤ 150 days, Fig. 8 and Conclusion); a pin in the cambium of *P. taeda* left ray parenchyma that grew into
mature tracheids and lignified early (Kuroda & Shimaji 1984, abstract) — anatomy, not a mechanical test. The beech
report takes the overgrowing callus as unbonded as the PREMISE of its study — «das im Bereich von Wunden gebildete
Kallusgewebe ist nicht mit dem überwallten Holz verbunden», the crack whose effect on growth stresses it then studies
(Götz et al. 2002, FZKA 6717, pp. 3, 35; injuries made in the 51st year of a 67-year-old beech, partly occluded) — and
measures, qualitatively, only that the occluding tissue presses on the wood («es wirkt gleichsam wie ein Druckverband»,
p. 176), while its summary still counts overgrowing callus among «rissartige Störungen». Its domain is the cambium's
occlusion of an exposed surface — in the anchor, the callus over Zone 2's outer edge (`01_04 §3.1`), not the ring
around Zone 1. None of the primaries on bodies set into living wood measures adhesion, and none is a conifer (Kane 2011
measured higher J-lag failure loads one to four years after installation, «presumably» from growth over the «J»; Ludwig
2012 reports an apparent form fit). So the bond is a reading, and its unbonded ends — slip with the normal contact kept,
and opening of a smooth envelope, which decouples the gyroid like a soft ring (what an interlock does in tension is not computed —
the leg's step (2), after `108`) — are not computed. Wang 2009 (*J. Mech. Mater. Struct.*
4:1595) shows the field inside an anisotropic circular inclusion IS uniform when the interface is homogeneously
imperfect with equal normal and in-plane tangential compliance — a sufficient condition; slip is not such an interface
and lies outside this script's uniform-strain solution.

**The junction** (`105`'s first-layer mismatch, priced at t_L = 1) grows with the share, as the ligaments' stress does;
unlike the binding sentence (a lower bound, judged at the lowest share) it is a magnitude to design against, so its adverse
end is the HIGHEST share: up to 1.982 at θ = 0 over the modelled set (no green reading raises it), and off the axis as
C44 → 0 up to 6.040 on the Scots pine group and up to 9.840 over the union — on Davies' raw stiff outerwood
(stiffer-axis reading, bare lattice, θ = 45°), our assembly of its ESM 2/3 means (E over tension and compression, ν from
compression; one board, whose softer-axis reading is not a material): Jeong's off-axis maximum stays below it with its ν_RT
anywhere in the swept span (asserted). On the published green sets alone — Davies' Table 2, Liu and Jeong, without that
assembly — it is up to 7.155, on Davies' Table 2 stiff outerwood (softer-axis reading, bare lattice, θ = 45°). Both stand
on a lattice tensor read from kinematic-side cases, so an input end, not shown to be the output's. On the measured C44 the
highest share over every angle is at θ = 0°: over the union it is at most 1.982 — the C44 → 0 supremum is the sweep's
end, which no measured reading reaches.

**Moisture.** Across the source's groups the share takes no single direction. Over the full grid of angles and C44, on
the stiffer-axis reading it falls monotonically from 45 to 95 % RH at 486 of 14022 points, rises at none and does
neither at 13536; on the mean reading 2830 fall and 11192 do neither; on the softer-axis one (45 → 85 % RH, its only
material groups) 12396 fall and 1626 rise. A living stem's sapwood is wetter than any group the source measured, and
above fibre saturation only other Pinaceae have full sets (the green group above): set beside the Scots pine groups
they confound species with moisture, so a green Scots pine stem's share is bracketed by named proxies, not measured,
and its direction with moisture is not established.

⚠️ **Bounds.** The Scots pine group: one source and one stand (Turkey), compression, below fibre saturation. The green
group: other Pinaceae, not Scots pine — four species, one board per Davies type, tension in Jeong's sets; Davies'
Table 2 is an optimiser's output whose weights the open text does not reproduce, Liu's 95 % is the trees' mean over the
whole section, and Jeong's sets are in press, red pine with two constants borrowed and Korean pine with one (ours),
Korean pine's ν_LR and ν_LT at CVs of 1.64 and 1.37. The lattice reading assumes the
two FE cases describe one homogeneous cubic body — `VoxelFea` calls its ratios «NOT a material property» — and the
shipped part is graded, so «cubic» holds at best locally — and the graded generator's phase drifts across the section — and, until the
HW.33 verdict of 2026-10-22, growing with height along the axis: a volume-keeping shear that (`01_01 §5.5`, the `cellshape`
verb) compressed the top cells of the part to 0.42–0.49 of their nominal along one axis (DA 3.3–4.3, the compressed axis
64–67° off the part axis). The verdict (option (в): one axial period, the rim's) removed the height term — the shipped part
reads DA ≤ 1.25 at every height — and this script reads the FE re-run on that geometry (2026-10-22; the `/32` fit,
which neither `105` nor `106` reads, followed 2026-10-23 — `01_01 §5.2`); Voigt's ceiling on C44 is loose (a Hashin–Shtrikman bound would narrow
the sweep). C44 is read from the periodic voxel case of the INFINITE lattice (`01_01 §5.2`) and carried onto the part body as an
assumption; the tissue in the pores
and the ring are unmeasured: the ring is read as the host's xylem (ours —
`01_04 §2`'s phases say nothing of it); the interface is perfectly bonded, a reading no primary measures, and its
slipping and opening ends are not computed (above). An infinite cylinder in an infinite matrix: the 40 mm length on Ø11, the bending
gradient along the radius, the curved rings, the bark's proximity and the transverse shear (S5) are not modelled.
Controls: Mura's tensor against the isotropic cylinder's closed form (seven entries), a hole in every live wood reading
against Lekhnitskii's K_t (the normal block — S_1212 of an anisotropic matrix has no independent closed-form check
here), its covariance under a rotation about the axis, a finite isotropic inclusion against Goodier/Muskhelishvili — each
to round-off; t_L non-increasing in C44 (asserted on the grid) and mirror-symmetric about 45° (asserted on one wood
reading at the C44 grid's ends). The green group runs the same per-reading controls and three more: each transcription
against its source's own aggregate (Davies' Table 2 rows against the ranges its ESM 1 prints and against reciprocity at
the printed rounding, Liu's four rows against its printed mean, Jeong's green E_L of both pines against the text's
retentions — red pine's 77.1 %, Korean pine's 66.9 %, which its printed means reach only within their rounding (their
quotient rounds to 66.8 %) — ESM 2/3 print none), G_LR and G_RT out of the share, and Jeong's ν_RT at θ = 0 (both above). Cache:
`mechanical/gyroid_wood_strain_share.json`.

---

## HW.23 — Can the Bonded Gyroid's Interface Stand as a Pressed Contact? (script 108)

`106` takes the gyroid's interface as perfectly bonded, and no primary in reach supports a bond there or measures one.
`108` prices that reading without new mechanics: on `106`'s bonded Eshelby solution the gyroid's stress σᴵ is uniform,
so the interface traction is exact, t(ψ) = σᴵ·n(ψ) at the angle ψ from the stem's axis — and a contact with no
adhesion, pressed by a growth pressure p₀ and held by friction, carries that field only where it stays closed (σ_n < p₀,
tension positive) and sticks (|τ| ≤ μ·(p₀ − σ_n)). `106`'s cache holds no σᴵ, so `108` recomputes it with `106`'s own
functions and holds them, exactly, to every cell of both of `106`'s wood groups — the dry Scots pine group and the green
Pinaceae group (⚖️ (Б)); a `106` group it does not read stops the run, and its cache test reds once `106` or `105`
moves a field `108` read. The stem's bending stress on the infinite cylinder puts normal traction and in-plane shear on
the interface; its axial shear is zero by the R → −R symmetry the wood, the lattice and the load share. Neither μ nor p₀
is picked: the map prints the friction needed and the p₀ each statement needs, and sets beside it two named readings of
ROOT growth pressure in one source, Bruder 1998 (FZKA 6206, doi 10.5445/IR/67698) — no primary was found for a stem
callus: the turgor of free root cells, 0.5 MPa (p. 15, his ref [27], secondary), and his own first field test, 15 spring
clamps (5–20 N/mm) on thin poplar roots read after about two years at about 2 mm of growth, «bis zu 0,72 MPa» (p. 100) —
a compliant restraint, so no stall pressure, and whether it rises further he left open.
The 2.5 MPa he also prints is not taken: Bruder uses it in two senses — on p. 15 an indirect reading on roots impeded in
their expansion, open-ended above (his ref [28]), on p. 100 the soil strength at which root growth stops (his ref [86]).
The strain is the source day's that `105` carries from `87`, 677–1837 µε at the gyroid (its median on a DBH-38 host's
bark … its upper whisker on a large stem); both halves of the sway occur as the wind turns — tension, the anchor on the
stem's windward face, and compression.

**Read as a smooth contact on the gyroid's envelope — a reading consistent only with the bare-lattice cells, 60 ⊥ 156 —
the bonded field stays closed at the source day's strain at θ = 0 only under p₀ of at least 5.39 MPa (Scots pine group)
⊥ 1.77 MPa (green group) — 7.4× ⊥ 2.4× the clamp reading — and on both named readings it is open in every bare-lattice
cell of both groups.** On the cells with tissue in the macropores — canon's own Phase 2 (`01_04 §2`), `106`'s additive
and Voigt pore readings — the same averaged traction exceeds p₀ in every cell too, but that is no opening: it is the
demand on an interlocked composite, which needs no adhesion to carry tension and for which the map has no direction.
The green headline stands on excluding Bruder's 2.5 MPa: had it been taken, at the day's 677 µε the averaged tension
traction would stay below it in 166 of the green group's 468 cells (58 of its 156 bare-lattice cells) and in 0 of the
Scots pine group's 180 — a fact about the averaged traction, no holding claim, and counts that hold while the strain moves by less than 0.023 % either way. The tension half opens the poles facing
along the stem; the compression half — where the wood's lateral expansion outruns the gyroid's — those facing around it
(in 35 bare-lattice green cells — 107 over all cells, as a demand — σᴵ stays tensile across the stem, so the averaged
compression-half traction never reaches p₀ there — no holding claim; a local opening is not excluded). The table is the
smooth contact, so its cells are the bare lattice:

| group | p₀ reading (Bruder 1998) | p₀, MPa | tension half opens above, µε | compression half at the day's two ends, 677 ⊥ 1837 µε: cells open · friction needed where closed, at least | there, the change of the day's strain below which the open count holds, % (sign: + a rise, − a fall flips first) |
|---|---|---|---|---|---|
| Scots pine, 60 bare-lattice cells | turgor of free root cells (p. 15) | 0.5 | 32–63 | 36 ⊥ 53 · 2.00–3.54 ⊥ 3.91–7.92 | −12 ⊥ −3.1 |
| Scots pine, 60 bare-lattice cells | his spring clamps on poplar roots (p. 100) | 0.72 | 46–91 | 19 ⊥ 43 · 1.58–13.20 ⊥ 3.00–24.18 | +1.9 ⊥ −0.52 |
| green, 156 bare-lattice cells | turgor of free root cells (p. 15) | 0.5 | 46–191 | 5 ⊥ 24 · 0.87–84.52 ⊥ 1.49–7.45 | +0.044 ⊥ +5.6 |
| green, 156 bare-lattice cells | his spring clamps on poplar roots (p. 100) | 0.72 | 66–275 | 0 ⊥ 16 · 0.68–3.26 ⊥ 1.24–54.49 | +29 ⊥ +0.20 |

Near a cell's opening the friction it needs diverges, as (1 − ε/ε*)^−½, so the upper ends and the open counts are values AT the stated strains, not smooth in them: the open counts hold while the strain moves by less than the last column, and the upper ends are not held even inside it: each rises with the strain while the count holds, and diverges at every flip of the count — as a closed cell nears its opening on a rise, and just after an open one closes on a fall — so a printed upper end bounds nothing at another strain. Every value of the last column lies inside the uncertainty of reading the input slope off the source's figure (±0.01 on 0.03 ⊥ 0.06 at 2 m — the median sets the day's low end, the upper whisker its high end; `87`). The lower ends move continuously.

On a smooth envelope the friction needed below the onset rises from zero with the strain, and at half the opening
strain it is already at least 0.34–0.39 on either reading (a lower bound; that ratio needs no p₀). At the source day's
strain the averaged traction exceeds p₀ over at least 55 % of the circumference in the tension half. The pole traction
is 0.74–1.24× the wood's own bending stress E_L·ε, so at θ = 0 the size of the demand does not hang on which of `106`'s
readings holds — its direction does — and the p₀ it needs scales with the wood's E_L.

**Off the cube axis C44 enters**, and the pole traction never falls as C44 rises (asserted on `106`'s grid); at C44's
Voigt ceiling no install angle on a bare-lattice cell opens the tension half later than θ = 0 does. The Zener ratio
above which a bare-lattice cell's tension-half averaged traction reaches p₀ at the source day's strain on every install
angle is at most 0.030 (on the clamp reading at the day's 677 µε), against the Voigt ceiling 3.755 — and **on `106`'s
measured C44** (read 2026-10-27: the part body's Zener ratio 1.49–1.62 on its absolute modulus ⊥ its Zener form over the
FE rungs — at least ×51 the threshold, which exists on only 401 of the 1728 cell × end × p₀ states, all bare lattice, the
rest reaching p₀ at any ratio (counts that hold while the strain moves by less than 0.068 % either way) — and the material tensor, another body off this axis, read whole on its own solid
fraction) every lattice cell of both groups — 432, 216 of them bare — has its tension half reach p₀ on every install
angle of `106`'s θ grid (0–45° in 2.5° steps) at both ends of the day on both named p₀ readings, the smallest σ₁·ε/p₀ ×2.46
(the green group; ×7.49 on Scots pine), and on all 432 the least pole traction over the angles sits, on every reading,
on the cube axis, which C44 does not enter. Off the axis a bare-lattice cell's opening — the demand, on a cell with
tissue in the pores — is therefore a finding on these readings, not a condition on C44; the measured C44 is the
infinite lattice's, carried onto the part body (`106`'s assumption).
On 12 green lattice cells the pole traction
falls to zero or below as C44 → 0 at θ = 45° — Jeong's two green sets, bare lattice, every alloy: the averaged traction
there is compressive all around, which is no holding claim — a local opening is not excluded.

**Both consumers**, read from `106`'s consumer blocks. At the cell behind `106`'s binding claim — the union's lowest
θ = 0 share, Davies' Table 2 stiff outerwood on the softer-axis reading under the Voigt phase bound, which puts tissue in
the pores, so the envelope is no contact surface there and σᴵ is a bound tensor's stress rather than an admissible
traction — the averaged envelope traction reaches p₀ 16.1× below the binding strain (Ta: 2383 µε against p₀ reached
above 103 ⊥ 148 µε), and only a p₀ of at least 11.6 MPa would offset it up to that strain: a demand on the interlocked
composite, with no direction; the Scots pine group's binding cell, printed beside it as the price, gives 22.0× and at
least 15.8 MPa. Net tension
across the envelope is carried by any load-bearing composite, bonded or interlocked, so this shows no need for adhesion.
The junction's adverse end is the highest share: at θ = 0 (the bare lattice on the driest Scots softer-axis reading) the
tension half opens above 35–44 ⊥ 50–63 µε, below the source day; at the union's C44 → 0 supremum (θ = 45°, Davies'
stiff outerwood from the raw ESM means, bare lattice) the in-plane stress is isotropic — the bending field puts no
averaged in-plane shear on the envelope there, which is no holding claim — and the tension half opens above 628 ⊥ 905
µε: at the day's median on a DBH-38 bark on the turgor reading, at its upper whisker on a large stem on both. That
supremum stands on Davies' raw ESM means, which are our assembly; over the published sets only — the companion ratified
beside it (⚖️ 2026-10-22; Davies' Table 2 stiff outerwood, softer-axis reading, bare lattice, θ = 45°) — the tension
half's averaged traction reaches p₀ above 748 ⊥ 1076 µε: at the day's median only on a large stem on the turgor reading
(below p₀ elsewhere at the median — no holding claim), at its upper whisker on both readings at both placements. So the
opening at the day's median on a DBH-38 bark is SHOWN only on our ESM assembly.
The anode's axial bond force (`105`'s S2 path, its mature and rigid-sleeve states at the source day) rides the same
envelope as a mean axial shear of 0.03–1.20 MPa over Ø11 × 40; it is not superposed point by point (its distribution
along the gyroid is a shear lag), and its effect on the friction needed has no direction here: at a fixed normal
pressure it adds axial shear, but it also moves the normal pressure through the gyroid's Poisson strain, with a sign that
alternates with the sway — not computed.

⚠️ **Bounds.** The traction is the homogenised one — the average over the cut lattice on the Ø11 envelope, where one
lattice cell spans 21–26° of ψ, so the open shares and the friction maxima carry an O(cell/radius) error that is not
quantified. The homogenised field's own curvature across one cell is taken exactly — a patch average at the pole,
c + r·sin Δ/Δ — so the unknown is what homogenisation leaves out; taken relative to the pole traction as C·Δ, the
tightest bare-lattice margin — the green group's patch need over the clamp reading at the day's 677 µε — keeps «open
in every bare-lattice cell» while C stays below 1.6 on the rim's period (the cell on the envelope) ⊥ 1.2 on the
core's (the conservative end).
Its direction holds only for a smooth contact whose local normal is the envelope's: there full stick needs
|τ| ≤ μ·(p₀ − σ_n) at every point, so the averaged ratio is a lower bound on the friction needed and an averaged opening
forces a local one — such a contact can be shown failing, never holding. A contact that is not smooth has no guaranteed
direction (an inclined facet carries averaged shear with zero friction, an undercut one averaged tension under positive
pressure), and with tissue in the pores the envelope is crossed by an interlocked composite, for which the traction is a
demand and neither failing nor holding follows; even the bare-lattice cells are smooth only while no tissue grows into
the surface relief. p₀ is a root's, read as uniform, sustained and free of shear; the further root figures on Bruder's
pages — primary growth near the root tip (his ref [85]), up to 1.45 MPa, and a bottle-neck root (his ref [87]) — all
lie below the lowest p₀ needed. The Ø15 wall (the callus against the drilled old wood) is no interface in `106`'s model
and is not computed; the finite length — the ends' axial shear — is not modelled. What opening, slip and interlock do to
the share is the leg's next step and is not computed here (a fully open smooth envelope decouples like `106`'s soft
ring; what an interlock does in tension is not computed). Controls: `106`'s cells of both groups reproduced exactly; the
projection against the isotropic closed form (Goodier/Muskhelishvili, shear excited) and against the Mohr circle on
every install-angle row; the tangent maximum against a brute force over the circle; the axial shear zero on every state;
σᴵ at θ = 0 free of C44; the pole traction never falling as C44 rises; the binding thresholds read from `106`'s consumer
block and held to its group derivation; the cache test recomputes every θ = 0 cell by another arithmetic and the
fingerprint of the `106`, `105` and CEM fields read. Cache: `mechanical/gyroid_interface_contact_map.json`.

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

## HW.6 — How Deep the Stem Shadows the Node's Radio (script 107)

The mounting-azimuth verdict (`00_07` HW.6) weighs axes that pull apart: frost ⊥ sun under the flange is computed
(`79`), while the stem's own shadow towards the gateway had only a field cut planned (`00_07` UNI.10 (b)). `107` is the
desk model of that axis: the exact two-dimensional cylindrical-wave solution for a source beside a layered lossy stem
(heartwood · sapwood · bark), the layers matched through one admittance recursion. The board lies on the bark, so the
booster's ground current runs in the plane tangent to it — along the stem (TM: an electric line along the axis, E
vertical, co-polar with the gateway's vertical antenna) or across it (TE: a line of dipoles tangential to the bark, E
horizontal). Which one, canon does not fix: the anchor rotates freely at install (its anti-rotation key is cut, `01_01
§4.3` C) and there is no layout yet (`00_07` HW.9). A vertical gateway antenna in the horizontal plane receives only the
vertical field, so the co-polar shadow of the uplink is TM's at ANY clocking — the clocking changes its level, not its
shape. What the outputs are worth splits in two. The field with the tree against the same source current without it,
read against the free source's front lobe, is exact in the horizontal plane for a short dipole along an infinite stem —
the far field at elevation θ selects the axial wavenumber β·cosθ, and at θ = 90° the problem is this two-dimensional
one — so the SHAPE of the shadow against azimuth is the horizontal cut of the 3-D problem, a gateway low over the
horizon. The same field at equal INPUT power, and the efficiency, are 2-D indicators of what the near field loses into
the stem, not the 3-D antenna efficiency (`00_07` HW.17).

Inputs, each a named reading: stems of DBH 38 · 50 · 60 cm (the smallest host, lib `DBH_MIN_CM`, and the two stems
`01_04 §3.2`'s bark table reads), with dead bark of 13.5 · 17.5 · 22 mm (the thin ends: lib's DBH-38 ridge bracket, then
that table's single bark less the ≤ 3 mm live phloem — derived); the RF deck — the booster's radiating ground — 12.85 –
16.85 mm over the bark line, which is the flange's underside (`52`'s rows of the deck over the flange's top face plus the
flange's 3.0 placeholder thickness; the low end is the named-alternative B2B 6 row — not the CAD's «antenna ↔ Ti 8.0»,
which measures the room to the cavity top); the carrier 868.2 MHz, read from the firmware's PHY; and sixteen
permittivity readings. Four are homogeneous, from Mavrovic et al. 2018 (*Geosci. Instrum. Method. Data Syst.* 7:195,
Table 3 — in situ, an L-band probe centred at 1.4 GHz): red pine thawed, the first 1 cm under the bark, 19.38 − j6.26
with ε″ carried flat ⊥ scaled to 868 MHz as if all of it were ionic (−j10.09); red spruce thawed, the table's wettest
conifer, 27.66 − j7.72; red pine frozen, the whole profile's average, 8.80 − j3.17. Twelve are layered: a dry, a wet or a
«phloem» bark (proxies: Şahin Kol 2009's dry Scots pine sapwood, El-Rayes & Ulaby 1987's poplar bark side at 1 GHz,
and their balsam-fir trunk bark of Fig. A.36 at ≈ 19.4 − j4.7, the mean of two page-image readings interpolated
between the 0.8 and 0.9 GHz markers — not measured at 868 MHz; that this bark is dominated by its wet phloem is our
hypothesis, grounded on the Franchois 1998 abstract on two other conifers, while the figure's title says only trunk
bark), then one of four interiors — the
red pines' measured radial profile (Supplement Fig. S2, 26 May: 35.2 − j10.27 at 2.5 mm, a plateau of 14.05 − j4.82
from 6 mm, no dry heartwood within the probe's reach), Scots pine's sapwood by both methods of Bieker & Rust 2010
(*Silva Fennica* 44:267, 0.3 m above ground: «Mean sapwood width from staining was 8.1 cm ± 0.6 cm and 6.1 ± 0.5 for
the tomograms» — means over 9 trees × 2 radii with an SE-like spread, while the single radii of their Fig. 2 run
≈ 4.0 – 13.4 cm by staining and ≈ 3.8 – 11.6 cm by ERT, so neither mean is an end of the width axis), or the narrowest
stem's 2.2 cm (Björklund 1999, *Silva Fennica* 33:119, Table 2 — CT of fresh logs
at 3.5–4.5 m), each sapwood around a dry heartwood proxy. The two widths at 0.3 m are two named readings, not a pick:
the source reads the gap as staining over-estimating the active sapwood («it is likely»), yet says the resistivity
boundary «is not just an effect of the higher water content in the sapwood», so neither boundary is the moisture
border a permittivity needs, and the 2 cm between them is carried wet (8.1 cm) ⊥ dry (6.1 cm). The moisture border
lies between them: Bieker & Rust (p. 270) cite Rust (1999) for a 17 % gap between computer tomography — the
moisture-border method Björklund used — and staining, ≈ 8.1/1.17 ≈ 6.9 cm if that gap carries over to these stems.
Björklund's width carries its height: «Sapwood width was biggest at the butt end of the stem, and was rather constant
above 3 m height» (read on his examples from two stands), so below 3 m a given stem's sapwood is likely, not
established, to be wider than 2.2 cm — his Introduction cites sapwood width as relatively constant along the trunk,
and canon assumes a mount height without fixing it (breast height in 03_03, ≤ 2.0 m in 01_02). No source in the tree measures any of them at 868 MHz. A.36 does not print its grid: the marker frequencies are inferred from the same session's A.38/A.39, which are
a dry branch, and the markers overlap. The figure's 0.8 GHz ε′ marker is depressed in that session (on A.38 and A.40
too), so a control in the cache re-runs the «phloem» rows at the reading that skips it, ≈ 19.63 − j4.68:
it lowers the TM floor by 0.08 dB, to 10.5 at the cache's outward rounding. Over the four single-reading interpolations (two readers,
each with ⊥ without that marker) the floors span 10.4 – 10.6 dB (TM) and 7.6 – 7.7 dB (TE): the floors printed below
hold at the mean of the two readings. The two tables below span the sixteen named readings; the swept sapwood-width
axis is in «What it says».

| polarization | behind the stem (180°), below the front | deepest null below the front, at | at 90° | within 3 dB of the front to | front field against the free front lobe, same current | 2-D efficiency |
|---|---|---|---|---|---|---|
| TM — E along the stem | 10.6 – 34.5 dB | 13.4 – 54.4 dB, 138.25 – 180° | 6.1 – 9.7 dB | 53 – 66° | −5.9 … +1.4 dB | 0.13 – 0.7 |
| TE — E horizontal, tangential dipole | 7.7 – 48 dB | 20.5 – 59.9 dB, 108.25 – 180° | 9.2 – 21.1 dB | 38 – 50° | −5.5 … +1.7 dB | 0.15 – 0.54 |

The back's depth by the stem's interior — how much of it is wet:

| interior | TM behind the stem | TE behind the stem |
|---|---|---|
| wet throughout (the four homogeneous readings and the red pines' profile under any bark) | 24.9 – 34.5 dB | 20.8 – 48 dB |
| 8.1 cm of sapwood around a dry heartwood | 23.7 – 30.6 dB | 17.3 – 33.8 dB |
| 6.1 cm of sapwood around a dry heartwood | 22 – 33.4 dB | 13.9 – 21.8 dB |
| 2.2 cm of sapwood around a dry heartwood | 10.6 – 22.2 dB | 7.7 – 17.4 dB |

**What it says.** Behind its own stem a node is weaker than when it faces the gateway on every named reading — by at least
10.6 dB with its E along the stem, the co-polar case, and by at least 7.7 dB with E horizontal — and already at 90° the
TM node is 6.1 – 9.7 dB down, staying within 3 dB of its front only to 53 – 66° either side. The horizontal node is not
the milder one: its free pattern already has a null along the bark, so at 90° it is 9.2 – 21.1 dB down; behind a wet
stem the order of the two flips with the reading, the stem and the standoff (compared pair by pair), and behind
thin sapwood over a dry core TM is the deeper one nearly everywhere. The depth behind depends on how much of the stem is wet: a wet interior — the season, the
868 MHz step and the wettest conifer all fall inside it — puts TM at 24.9 – 34.5 dB; a thin wet shell over a dry core,
under the wettest bark, brings it to 10.6 dB. On the named readings the cache names the reading at each end of every
span (`ends_by_reading`), but no named width can name a consumer's adverse end: wet sapwood resonates — its
in-medium wavelength at the carrier is ≈ 7.75 cm, so every output swings with the width about every 3.87 cm — and
named readings bracket an output only where it is monotone between them. So `107` sweeps the width over its measured
axis (`width_sweep`), 2.2 – 13.6 cm in 0.2 cm steps — Björklund's narrowest stem to past the widest radius of Bieker
& Rust's Fig. 2, ≈ 13.4 cm by staining — under every bark, stem, standoff and polarization, the named widths included.
On that axis the narrowest TM 3-dB sector is 52°, at 3.2 – 4.0 and 7.4 – 7.8 cm under the «phloem» bark (the 8.1 cm
staining mean gives 53°, the 6.1 cm tomography mean under the same bark 57°), and the widest is 71°; the largest TM
loss at 90° is 10.3 dB, at 3.4 cm; the TM floor behind is 10.2 dB at 2.8 cm — inside the axis, not at its thin end
(under the dry bark 12.8 dB at 4.0 cm, against 20.5 at 2.2) — while the TE floor stays 7.7 dB at 2.2 cm; the back
reaches ≥ 54.8 dB (TM, at 7.4 cm) and ≥ 71.0 dB (TE, at 13.0 cm) — sampled nulls — deeper than any named reading, and the deepest TM null
moves up to 52° off the straight line. No width is the conservative one for every consumer, and the mount's height
gives none of them a direction. The stem is wider than a wavelength (λ = 34.5 cm); on the named readings the deepest
null sits
up to 42° off the straight line through the stem (at 138.25 – 180°), and on most readings 180° is itself a local
maximum where the waves creeping round both sides meet in phase. The standoff sets the near-field indicator: a TM node
radiates 0.13 – 0.65 of its input power with the RF deck 12.85 mm over the bark and 0.18 – 0.7 at 16.85 mm (on the
swept axes down to 0.11).

**The stem's diameter is the second resonant axis** (`dbh_sweep`, 2026-10-23): every stem of 38 – 60 cm in 1 cm steps —
the dead bark at each stem at the THIN end of canon's table, derived by linear interpolation between its three stems (13.5 · 17.5 · 22 mm;
22 is the table's 25 mm less 3 mm of live phloem — `01_04 §3.2` names no dead-bark figure at 60) — under every width of the width axis,
every bark reading and both decks. On that grid the TM 3-dB sector's floor is 50° on the 1° grid (the −3 dB crossing's grid floor 50.35°;
a finer grid around the floor row (DBH step 0.1 cm, sapwood 0.1 cm) finds no lower node), reached at DBH 43 – 44 and 53 – 55 cm under the «phloem» bark at the 12.85 mm deck with
3.4 – 4 cm of sapwood; the named stems miss both troughs (54° at 38, 53° at 50, 52° at 60 cm); under the dry and the wet bark
the floor is 54°. So on the thin end of the bark the ratified ±50° rule holds on the 1° grid with a margin of 0.35° on the crossing (over the
four single-reading A.36 interpolations of the «phloem» bark the floor rows' crossing spans 50.22 – 50.37°) — the rule holds under all three
bark readings there, and only the «phloem» one, our hypothesis, brings it that close (the dry and the wet readings leave 4°). The standoff is not the
monotone axis it was expected to be, and the polarizations differ: TE is monotone in the crossing (the higher deck narrows its −3 dB crossing
in every one of the 4140 cells, and the integer sector in 4043 of them — the higher deck is TE's adverse end), while for TM the crossing is
narrower at the higher deck in 658 of the 4140 (stem × width × bark) cells (225 on the integer sector), and every TM row at the sector's
floor is at the low one. The TM floor behind on the stem axis is 10.2 dB (DBH 41 cm, 2.6 cm of sapwood, «phloem» bark;
10.1 – 10.3 dB over the A.36 readings); the largest TM loss at 90° is 10.4 dB (DBH 54 cm, 3.6 cm); the TE sector
narrows to 37° on 35 grid rows (33 cells; DBH 38 – 54 cm, 2.2 – 4.6 cm of sapwood, dry and «phloem» bark); the backs reach
≥ 61.7 dB (TM) and ≥ 71.7 dB (TE) on the grid — sampled nulls, so the deep end stays open.

**The dead bark is the third resonant axis** (`bark_sweep`): at the «phloem» reading the in-medium wavelength is ≈ 7.8 cm, and canon's
dead bark runs 13.5 – 21 mm at DBH 38 and 17.5 – 28 at DBH 50 (`01_04 §3.2`), so the thin end above was one end of an axis, not the
axis. Swept from the thin to the thick end in 1 mm steps (both ends derived per stem — canon states the ends at 38 and 50; the live
phloem taken off the single-bark figures is 3 mm at the thin end, as canon says, and 1 mm at the thick end, OUR reading of canon's own
pattern there, an assumption; 35 mm at DBH 60 is the table's 36 mm less that 1 mm) on the TM «phloem» stem over every stem, width and
deck, the sector's floor is 49° on the 1° grid (crossing 49.85° on the grid, at DBH 54 cm with 30.8 mm of bark and 2.4 cm of
sapwood at the 12.85 mm deck; 49.72 – 49.88° over the A.36 readings), so **the ratified ±50° rule FAILS on the 1° grid over canon's
own bark range** — it fails first at DBH 54 cm, on 8 grid rows at DBH 54 cm (bark 27.3 – 30.8 mm, sapwood 2.4 – 2.8 cm),
where the LETTER of the rule — 3 dB at ±50° — falls by hundredths of a decibel: the loss at ±50° is 3.004 – 3.018 dB over those rows,
3.018 on the crossing-floor row (3.014 – 3.033 over the A.36 readings). Three things bound that floor, and only one of them exceeds the excess. The grid minimum is an
UPPER bound on the true floor: a finer grid around the floor row (DBH step 0.1 cm, sapwood 0.1 cm, bark 0.25 mm, inside the table) finds
49.82° (DBH 53.8 cm, 30.66 mm of bark, 2.5 cm of sapwood), 0.03° below the node — a one-sided deepening of 0.003 dB.
The floor sits on the table's EDGE, not at an extremum: past the thick end the crossing falls further before it turns
(49.81° at 31.8 mm, the lowest of the probe; back above the rule from 33.8 mm — canon's ridge SD is ±4 mm, `01_04 §3.2`), another
one-sided deepening of 0.004 dB. And the deck decides whether the rule passes: it stands on the flange-thickness placeholder
(`00_07` HW.8.10), and ±1 mm of it moves the crossing by ≈ 0.2° and the loss at ±50° by ≈ 0.02 dB — more than the excess itself — so a
deck 1 mm higher returns the rule (50.04° at 13.85 mm) and 1 mm lower takes it to 49.66°. Under the dry and the wet proxies the floor is 54° at the thin end and rises to 57° at the thick
end. The TM floor behind on the bark axis is 9.9 dB (DBH 40 cm, 19.2 mm of bark, 2.2 cm of sapwood; 9.8 – 10.1 dB
over the A.36 readings) — below the diameter axis's 10.2 — and the largest TM loss at 90° there 10.6 dB; the 2-D efficiency indicator
falls to 0.11. Canon's largest host — DBH 60 cm, ratified 2026-10-24 (`01_04 §3.2`) — is where the bark table ends; a probe past the bark table, 61 – 90 cm on the TM «phloem» stem under both decks, with
the bark by three assumptions — the thin end held at 22 mm, the thin end extended by the table's 50→60 slope, the thick end extended
likewise — first breaks the rule on the 1° grid at DBH 86 / 76 / holds to 90 cm respectively.

⚠️ **Bounds.** The shape against azimuth is exact only in the horizontal plane, for an infinite round stem of uniform
isotropic layers, a node on a radius and a short dipole along or across the stem: a gateway high above the horizon
(where a dielectric stem couples TM and TE), a tapering stem, the ground and its reflection are out, and the absolute
level — G(0), the efficiency — is a 2-D indicator. The node's own body is not in the model, and its heaviest part is the
ANCHOR: the board's ground — the booster's radiator — is tied through the centre pogo to the Ø1.0 Ti bus, which runs
about 93 mm RADIALLY into the wet stem to the gyroid (`02_02 §1.2`; canon has no RF choke on that line). A radial
conductor in lossy wood is no source along or across the axis and no layer: it may move the absolute level and,
possibly, the front-to-back ratio, and nothing here bounds by how much. The Ti flange and the PEEK radome sit in the
near field too; the booster's 8 – 10 mm offset from the anchor's axis, the canopy, other stems and the forest's excess
path loss are out. The permittivities were measured in situ at the probe's 1.4 GHz centre, at the trunk's daily minimum
(15:00 – 18:00) and mostly at the end of spring; the step to 868 MHz is bracketed (flat ⊥ all-ionic; if Table 3 is a
1 – 2 GHz average the all-ionic end is ≈ 3 % higher), not measured; bark and heartwood are proxies — no pine bark or
heartwood primary near 1 GHz is in the tree — and the bark is swept from canon's thin to thick ridge end on the TM «phloem» stem only (the dry and wet proxies at the two ends); furrows have no primary. The sapwood widths are
read at their sources' heights (0.3 m; 3.5 – 4.5 m), not at the node's, which canon does not fix. Every layer is isotropic,
while a TM source sees ε along the grain and the in-situ probe read a mixed face (lab spruce puts ε′∥/ε′⊥ at 2.2 –
2.4), so the longitudinal ε may be higher than every reading here. The S2 profile is transcribed from the page image
(±0.2 on ε′, ±0.05 on ε″) and smoothed by the probe's 10 mm reach. Controls: free space (the field with every ε_r = 1
equals the free source's), lossless (P_in = P_rad — which any real admittance satisfies, so it guards the reaction and
the bookkeeping, not the matching), the energy balance on every row against the power dissipated inside — integrated
over the interior field, whose amplitudes come from value continuity, not from the exterior coefficients — and the
series' truncation, all NaN-safe and at round-off; the deepest null is searched on a 0.05° grid. Not guarded at runtime:
the far field's orientation (a swap of front and back passes every runtime gate and is caught only by the invariants
test's direct closed form), and the per-layer split of the absorbed power. Cache: `radio/stem_radio_shadow.json`.

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
| The rain/dew stand's positive control (2026-11-02, block `stand_positive_control`): the aperture above which the 50 mm phase-I layer passes at ANY θ — a meniscus pinned on a round aperture holds at most a hemisphere's 4γ/d, whatever the angle and the edge, at entry and exit alike; the bound is on the pressure difference ACROSS the hole (water 20 °C) | **> 595 µm**; the sheet's proposed Ø 1.0 mm punch ×**1.68**, passes any layer from **30** mm, and a cavity overpressure stops it at ρgh − 4γ/d of the measured aperture — ≈ **198** Pa at the nominal point (the proposed punch, clean water at 20 °C, a layer of exactly 50 mm), more on the resin arm, in warmer water, under a deeper layer or through a wider hole, near zero at the acceptance edge — so the cavity stays at chamber pressure. The pore the layer holds at one θ (110° · 120°: **203.5 · 297.5 µm**) is only the threshold for ENTRY; at the exit a meniscus nothing touches is held up to 4γ/d, so a θ-sized hole can stay silent at any θ |
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

⊕ **2026-10-13 — the transfer «stem motion → load through the pins» (script `87`, the machine leg split from the measurement leg when the crown pause was lifted for measurements; revised the same day after an adversarial pass — the first version priced one path as if it were all).** Sway reaches the pins along four paths, and the model computes two of them to a number. **(A) The rim — the premise of the rest.** The capsule rides the flange as one body only while the rim's friction (PEEK on Ti, µ from 0.1) holds the capsule's own weight (the anchor axis is near-horizontal, so the weight loads the rim sideways) plus the drag and inertia. Early in life the bayonet clamp of `52`'s requirement (≥ 157 N, sized for the pogo pair and a generous 100 N ring) gives ≈ **21.1** N of capacity against ≈ 1.2 N of demand; but that requirement is sized so the rim only just stays seated after 20 years of relaxation. A clamp at the form `52` prints for the ring's OWN reaction, (R₀ + p)/0.65, never lets the rim lift while the lift stays at its initial value, so the normal force at the end of life is at least that initial lift; a weaker clamp can let the rim lift — whether it does depends on the ring's relaxation against the PEEK's, which nothing models — and a lift is taken as not undone (conservative for (A): lifted, the normal force is L; reseated, 2C − L ≥ L), so from then on the normal force is what the ring has left. On the pogo pair alone it does not hold even the weight, and with the capsule envelope as solid copper and the canopy-top gust it needs an initial O-ring reaction ≥ **10.34** N (median reading) … 10.58 N with the clamp at `52`'s printed form, and the same 10.34–10.58 N still present after 20 years with a weaker clamp (the reaction itself — section HW.33, script `88`). Temperature is in neither: the PEEK in the clamp loop sits between two Ti faces over the same span, so cold unloads the clamp and heat raises it. Below it the capsule shifts inside the collar clearance and the pins SLIDE: `55`'s per-cycle drag premise is that regime, not a ceiling the model escapes. **(B) Stack inertia, rim holding.** Wire stress is linear in force, so for a coaxial clamp the amplitude is m·a over a mean that the static axial share of the weight (10° install angle) lowers — **0.21 % (median) … 0.42 % (whisker) per gram** is the slope at small mass, not a bound; the ratio stays below 10 % while the stack is lighter than **21.5** (whisker) … 39.3 g, and the weakest pin (60 − 20 g at mid-stroke) stays loaded while the stack is lighter than **116** (whisker) … 155 g. ⚠️ The clamp is not coaxial (two pins below, an eccentric gasket above), so a force pair m·a·h/s adds to this; h and s are layout quantities, not in the tree. **(C) The centre pad — a ceiling at the pin.** Bending's Poisson strain μ_LR·ε_L is a radial strain that varies along a radial anchor in the bending plane (wind along the anchor's azimuth; zero for an anchor at right angles to the wind), imposing up to μ_LR·ε_s·Δx between the wood at the anode and at the flange — **2.80 … 5.04 % of the working compression per 1000 µε** of stem-surface strain at the anchor's azimuth (μ_LR 0.280–0.392, nine pines at ≈ 12 % moisture, Wood Handbook 2021 Table 5–2, no P. sylvestris; Δx 70–90 mm, anode centroid to flange and the whole depth, `77`'s geometry), 2.6–9.3 % on the source day. The anchor resists it: the Zone 1↔2 press-fit with barbs ties the anode to the flange, and the liner's grip and capture tie the bus-wire tip to the flange (`01_01 §1.4`) — and the Zone 1↔2 press-fit does not have to slip for the term to load the wire and its seam, or to reach the pin as the wire slips inside the liner near the liner's held end — a local slip of the liner's grip, itself an interference fit (⊕ 2026-10-17 below). The worst cases of (A) and (C) need different wind azimuths. **(D) Thermal** cycling of the same contacts is not computed here (script `90`, ⊕ below). Stem input — Schindler & Kolbe 2020, Figure 9 read at 2.0 m (median 0.03, upper whisker 0.06 °/(m²/s²); a plot reading; a whisker is not the maximum) at the day's strongest flux, > 31 m²/s² (control, units only: that interval's 12 m slope × flux = **11.5°** against the text's 12°, the slope regressed on the same data); tilt grows monotonically with height, so for an anchor at any height ≤ 2.0 m the tilt is ≤ 0.93–1.86° and the non-oscillatory displacement ≤ 31–62 mm; the acceleration, ≈ **0.83** (median) … **1.65** m/s² (whisker), takes that whole swing as oscillating at 0.74 Hz — NOT a proven bound either way: the oscillatory share at 2 m is unpublished, at the base it carries ~40 % of the variance, and higher modes weigh as f². Flux scales as U², so a storm twice as windy multiplies the stem quantities ×4: the numbers describe that one January day of one tree smaller than the canon's hosts. The stem's mean curvature between 0.1 and 2.0 m in that interval, 8.5–17 × 10⁻³ rad/m, is ≈ 920–1840 µε at the source tree's DBH 21.5 cm (our calculation from a plot reading); stem strain at 1.3 m was found in open texts only for broadleaves — not transferred. **What it changes:** the pogo's missing half is now a set of unmeasured quantities — the clamp the bayonet delivers, over temperature, against the ring's lift (decides (A); the ring's reaction is `88`'s band), the stack's layout (B; its mass is estimated part by part, ⊕ below), the axial load at the bus wire's root and how much of (C) reaches the pin (the liner's ceiling on that load is computed, ⊕ 2026-10-17 below), the stem strain and acceleration at anchor height on host-size pines (B, C) — not a micro-deflection that only a measurement at the pin could give; that measurement now has a model to be checked against. (`mechanical/pogo_sway_transfer.json`)

⊕ **2026-10-13 — (A) against the O-ring's own reaction (script `88`, section HW.33 — the O-ring's own reaction; revised the same day after two more adversarial passes: «whatever the ring retains» held only for the clamp at `52`'s printed form, and whether a weaker clamp lifts at all depends on the ring's relaxation).** For a ring under 1″ Parker's Table 2-3 puts the load in the middle or upper third of the Figure 2-4 bar, so the ring starts at no less than **57** N at the 19 % window floor — **5.4×** the reaction (A) needs with a clamp at the form `52` prints for the ring's own reaction, (R₀ + p)/0.65, which never lets the rim lift while the lift stays at its initial value (resin swell and temperature can raise it). A weaker clamp can let the rim lift — whether it does depends on the ring's stress relaxation against the PEEK's, which the source does not give — and a lift is taken as not undone (conservative), so (A) is then judged on the ring keeping 19 % of its reaction for 20 years — of its force in the lifted state, where the ledge PEEK creeping under the lift also takes squeeze, so a constant-squeeze relaxation datum overstates what it keeps. Both hold at the assembly temperature only: the PEEK in the clamp loop sits between two Ti faces over the same span, so cold unloads the clamp and heat raises it — `89` (same day) models it: a clamp at exactly `52`'s printed form keeps the rim seated in the cold only if the loop does not feel temperature at all — at the end of life, with a ring that never relaxes and a lift that does not fall in the cold, any thermal sensitivity lets it go, while a clamp sized to `89`'s requirement holds. `02_02 §3.2`'s swell thresholds (≤ 15 % keeps EPDM, 15–25 % is the founder's call) are bench limits on FREE rings and do not bound the lift; any swell raises it. The friction bound runs through the lug ledge (the rim's share can be zero), with µ from `55`'s dry PEEK–Ti sweep, and the ring is greased. The early capacity above reads `52`'s frozen 157 N requirement; with the band the requirement moves both ways, so that figure is one reading, not a bound. (`mechanical/oring_reaction_band.json` → `rim_premise_A`)

⊕ **2026-10-13 — the stack's mass, part by part, before a scale (script `87`, `inputs.stack_parts_g`; revised the same day: solder, mask and coating, the pocket gasket and an optional desiccant joined the rest).** EDLC 1.4 g (Eaton product page) · two standoffs ≈ 1.7 g (Würth gives no mass; its geometry × steel, our calculation) · two FR-4 boards no larger than the rim cavity 2.23–2.73 g (Panasonic R-1755V/M specification sheets, 1.96–2.0 g/cm³; copper 4 × 35 µm at 30–100 % cover) · booster 0.19 g (Ignion datasheet) · B2B pair 0.04–0.25 g (the socket's 40.6 mg is a distributor's figure; the header has none) · pogo pair ≤ 0.2 g (solid-brass ceiling) · the rest 0.35–1.3 g, not from datasheets (MCU, PMIC, TCXO, inductor, sensors, passives, solder, mask and coating, the pocket gasket, an optional desiccant) — **5.96–7.77 g** (the two computed ranges — boards and stack — rounded OUTWARD, so each holds its own ends). At that mass the coaxial inertia is **1.28 %** (median, light) … **3.39 %** (whisker, heavy) of the reduced mean — about a third of the 10 % at worst, which the ratio stays below while the stack is lighter than 21.5–39.3 g; the pair factor of the layout is still unpriced, and a scale reading checks the mass. (`mechanical/pogo_sway_transfer.json` → `B_inertia_coaxial.at_estimated_stack_mass`)

⊕ **2026-10-17 — (C) behind the liner: a ceiling on the axial force at the wire's root (script `87`, `C_wire_behind_liner`, HW.43 leg (1); revised the same day after two adversarial passes — the first capped the wire at the grip's friction and set a factor taken at SF 1 on Ti-6Al-4V beside `86`'s at SF 2 on Ta; the second showed that the yield threshold left the soft liner out of the route's stiffness, so the share of the shift that yields the wall is no longer computed).** No press-fit has to slip for (C) to load the wire: the PEEK sleeve between the anode and the flange is not a rigid body, and the wire spans the same distance beside it; and the tip moves as the wire slips inside the soft liner near its held end, before any yield. What is computed is a ceiling. Every axial force on the wire crosses the liner's own wall, held at its top only (`01_01 §1.4`), so the wall caps it at **53.7** N — **68.4** MPa on the wire, PEEK's 23 °C uniaxial yield — whatever the source: this term, the sleeve's thermal growth between the anode and the flange (the part of path (D) that `90` does not price), or both. A grip that slips first caps it lower (`55`'s window floor at every swept µ; the nominal grip at µ 0.1 if it relaxes to the tree's floor, a low reading). **What it does to the seam (HW.34).** On the tensile half Soderberg weighs amplitude above mean, so for a non-negative axial mean the worst split under the ceiling is all amplitude. Set on the same section as `86`'s bending amplitude and mean at ⌀0.10, in phase, `86`'s own formula raises the seam requirement from k ≥ 0.1441 to **0.55** on Ti-6Al-4V and from 0.3882 to **1.48** on Ta, and drops the wire's SF on Ta from 4.54 to **1.39**; on CP-Ti-Gr4 (**1.03**) and Ta not even an unweakened wire keeps SF 2. The added amplitude divides by each coaxiality branch's own room, so `86`'s three branches keep their ratios, but on Ta even the tightest needs k ≥ **1.35**. **Where the ceiling is not a bound** (named, not computed): the compressive half — PEEK's compressive yield and the capture's push-out capacity are not in the tree, and the sign of the shift at a given anchor is not assigned; a parallel tie — the gap and the channel are wet by design (`02_02 §3.1`), so ice or hardened resin can tie the wire or the liner to the sleeve beside the wall; PEEK below 23 °C (the source day is in January) and a multiaxial yield under the fit's hoop tension, which move the wall's axial yield either way; the beam-column coupling of the tension with `86`'s bending (a few per cent). **Not computed, and it decides where between `86`'s own k and this reading the requirement lies:** the axial load the root actually carries and how much of (C) reaches the pin instead — a shear-lag model with Coulomb slip of the wire in the liner, fed with the share of the shift the wood imposes (the sleeve and the wire resisting in parallel) and the sleeve's thermal growth (HW.43 leg) — computed since 2026-10-20 by `102`, §«The Bus Wire in Its Liner» below. Not in either: weld residual tension, a lower fatigue limit in axial loading than in bending, 20 years of the grip's relaxation, the creep and fatigue of the liner wall itself as an insulator. (`mechanical/pogo_sway_transfer.json` → `C_wire_behind_liner`)

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

| SKU (`02_01 §3` поз.3) | Life rows | Life @ 25°C | Life @ 10°C | `VBAT_OV` for 20 yr @ 10°C, per reading |
|---|---|---|---|---|
| Eaton KR-5R5H474-R | 1000 h @ 70°C @ 5.5V · 2000 h @ 85°C @ 3.6V | 2.58 yr | 7.30 yr | lower bound (both rows, PS-5006 text 2×/10°C): ≤ 4.395 V · unsourced 0.4 V/part: ≤ 4.918 V · unsourced 0.2 V/part: ≤ 5.209 V · Figure-1 slope: the rated 5.5 V already holds |
| KEMET FG0H474ZF | 1000 h @ 70°C @ 5.5V (one row found) | 2.58 yr | 7.30 yr | the two unsourced readings only — KEMET's own coefficient and a second Life row not found in a public datasheet |

**Verdict** — 🔴 Confirmed via the actual pipeline (not hand-math): the 20-year claim at full
rated voltage does **not** hold for either SKU (2.6-7.3 yr, a 3-8× shortfall). Whether 20 years is
reachable depends on the `VBAT_OV` target. **Derate RATIFIED 2026-09-09 (`VBAT_OV` = 4.822 V) and SKU
closed 2026-09-22 (Eaton KR).** Since 2026-11-07 the voltage step is no pick from an unsourced bracket: the
datasheet's two Life rows are guaranteed minima, and under Eaton's own text rule (PS-5006 p. 2, 2× per 10 °C)
they bound the life from below — 0.76 V per doubling per part (0.38 V per cell; PS-5006's «1.8 V per
supercapacitor» at +85 °C against the row's 3.6 V makes the KR two cells, so the old «0.4 V, Eaton's points»
matches that cell step applied to the part — where the 0.4 V came from, nothing in the tree says). At 4.822 V the bound is 13.5 yr @ 10°C and 4.8 yr @ 25°C. PS-5006's
Figure 1 is steeper than its text (≈ 3× per 10 °C), and on it the same rows give 193.7 yr @ 10°C — so the cold
life is set by the vendor's thermal step, which only the vendor can settle. Figure 1's cell voltage effect, paired
with the rated 70 °C anchor, predicts the +85 °C row below its guarantee, so it is no reading of the KR. The bound's
minimum is checked by brute force across the voltage range (`bound_control`), mutation-verified; it is a bound only
while the true thermal step is no shallower than 10 K, and below row B's 3.6 V the rows give no voltage credit — so
at 25 °C no `VBAT_OV` holds 20 yr on it. Decision → `00_07` HW.37.
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
hours, T_eff = 10·log2⟨2^(T/10)⟩, with the life taken from `51`'s own readings (`readings_years`) at the
ratified `VBAT_OV` (imported, not re-implemented — the 10/25 °C reference points reproduce `51`); each reading
ages at the T_eff of ITS OWN thermal step, so the Figure-1 column is not read against the T_eff column.

| Series | T_eff | Lower bound (both Life rows) | Unsourced 0.4–0.2 V/part | Figure-1 slope |
|---|---|---|---|---|
| Open air | 13.0 °C | 11.0 yr | 19.2–62.0 yr | 112.9 yr |
| Under the radome, shaded (α 0.50/0.95 × k 0/0.1) | 14.35–17.35 °C | 8.1–10.0 yr | 14.2–56.6 yr | 64.1–95.2 yr |
| Under the radome, sunlit (α 0.50/0.95 × k 0/0.1) | 17.74–27.41 °C | 4.1–7.9 yr | 7.1–44.8 yr | 15.7–58.5 yr |

Re-run 2026-09-30 on the Ø29.8 dome (the root verdict opened the Ø25 freeze for the board, `02_01 §3.5`): the larger solar area costs ≈ 1.4 K of hot margin (7.1 → 5.7 K at α 0.95, still air) and ≈ 0.4–0.9 °C of sunlit T_eff; every verdict stands.

Cold side: the air was below the −25 °C floor for 64 hours in 30 years (9 days, coldest −27.4 °C);
the lump tracks the air at night in this model, and real sky cooling would make the capsule colder,
so the count is a LOWER bound for the capsule. With the sky it is computed by script 81 (next section).

**Verdict** — the hot side is not exceeded for any finish in the sweep, but for a DARK finish in full
sun the margin is of the order of the model's own uncertainty, while a light one keeps ≥ 15.0 K. The
aging side moves the 20-year claim: the site does not age the EDLC at the 10 °C reference point, and
at its real T_eff the vendor-grounded lower bound stays below 20 years in every case — holding 20 years
on it needs `VBAT_OV` ≤ 3.604–4.164 V where any voltage can and none can for the dark finish in full sun (below
row B's 3.6 V the rows give no voltage credit), all under the winter TX-resume threshold, so the derate lever
is spent there; on Figure 1's slope the same rows clear 20 years in every case but the dark finish in
still-air sun. The claim now rests on the vendor's thermal step (`00_07` HW.37). NOT modelled: sunlit bark heating the flange rim and
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

⊕ **2026-11-14 (`122`).** «No run crosses the capsule requirement» is about ERA5 air under Brutsaert's sky with `71`'s kernels as they are, and «ERA5 smoothing of station minima» is now counted (`121`: ERA5 has fewer cold days than the station). On MERRA-2 air under the same sky the hourly record keeps less margin to −40 °C than the shift `71`'s own ×0.7 reading of its still-air kernel makes, and the days before it pass the requirement under three readings at once — §HW.37 (script 122).

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
| 19 % — window floor | 57–119 | 3.78× … 2.46× | 0 · 0 · 0 % |
| 21.7 % — `52`'s chain, low | 74–159 | 2.85× … 1.85× | 0 · 0 · 0 % |
| 24.5 % — nominal | 96–219 | 2.07× … 1.35× | 0 · 0 · 0 % |
| 27.3 % — `52`'s chain, high | 124–301 | 1.51× … 0.98× | 0 · 2 · 2 % |
| 30 % — window top | 160–410 | 1.11× … 0.72× | 23 · 28 · 28 % |

**Verdict** — the 100 N is not an upper bound: the band's top stays below it while the squeeze is under 17.1 % and is past it from 17.2 %. With that top the lug root
(SF 2 inside; no fillet, no lug bending) carries `52`'s requirement at the nominal whatever the ring does, at the top of
the chain `52` models once the ring has lost about 2 % of its reaction, and at the window top only if it has lost about
23 % by year 2 and about 28 % already by year 5; a ring that never relaxes leaves the lug unbound while the squeeze stays below 27.1 % (26.8 at +4 % and 27.5 at −4 % of the transcription — the source cannot tell
it from the chain's top), and strength, not printability, then sizes the collar wall — at least 0.28 mm at the window top
against the 0.2 mm print floor (`52`'s form at the assembly temperature with no fit tolerance) — ratified as a conditional member of the root package (⚖️ founder 2026-10-13, `02_02 §4.4`; script 89 ↓ found that requirement itself, unrounded **0.2765** mm, is the k = 0 end — the lower bound — of a PEEK-dominated loop's wall, and the member that rounds it up a point on a curve of an unmeasured stiffness; the founder ratified it as such the same day). From below, the ring starts at no less than 57 N at the
floor: (A) holds 5.4× with a clamp at the form `52` prints for the ring's own reaction; a weaker clamp can let the rim
lift, and (A) is then judged on the ring keeping 19 % of that floor for 20 years (a lift taken as not undone). The margins say whether a bayonet that meets the
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

| Squeeze | L0 (N) | Wall (mm, a requirement — rounded up), PEEK-dominated: at k → 0 (`88`'s requirement) · k = 1 · 3 · 10 N/µm, ±0.05 mm | Force-controlled wall, zero band (mm, rounded up) | Line-contact p0 on the mean lug, PEEK-dominated load (MPa) |
|---|---|---|---|---|
| 19 % — window floor | 121 | 0.09 · 0.14 · 0.23 · 0.58 | 0.06 | 215 |
| 24.5 % — nominal | 220 | 0.15 · 0.20 · 0.30 · 0.65 | 0.10 | 291 |
| 27.3 % — `52`'s chain, high | 303 | 0.21 · 0.26 · 0.36 · 0.70 | 0.14 | 341 |
| 30 % — window top | 411 | 0.28 · 0.33 · 0.43 · 0.77 | 0.18 | 397 |

**Verdict** — in a PEEK-dominated loop every N/µm adds **0.049** mm of wall at the window top with ±0.05 mm of
interference (temperature is **11** % of it; with no tolerance **0.0055** mm, 0.0067 with a gradient), so `88`'s
requirement at the window top — the ground of the ratified member, which rounds it up to 0.28 mm (`02_02 §4.4`) — is the
k = 0 end of that line: every PEEK-dominated k needs more, which makes it the loop's lower bound, not an estimate. The
ratified member carries such a loop at the window top on every temperature reading while k stays below **0.068** N/µm
with ±0.05 mm (**0.036**–**0.892** over every reading and tolerance) — «for any k» is a property of the
requirement, not of 0.28 (`02_02 §4.4`, marked 2026-11-04). A
compliant element in series fades the relaxation and the k-terms, and the load runs continuously down to L0 — **411** N
at the window top, a **0.18** mm wall with a zero force band — so the ratified member is one point on a curve of an
unmeasured k, bounding nothing. The force-controlled end is not cheap: inside the print floor its spring must be no stiffer than **0.42** N/µm
with ±0.05 mm and zero force tolerance (so at the band's mid force every such spring deflects at least **1.01** mm; **1.95** with ±0.10), its whole force band
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
BQ25570 charging rail as the EBFC; this script supplies the axis "a second power source on the shared rail" that
the canon's list of what moves `delta_t` (`01_03 §4`) carries. Closed form: `delta_t = E_window / (P·η_boost)`, where
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
the auxiliary source rather than the EBFC cell, in every season. The percentage result is
algebraically independent of which `delta_t` definition of the form E / (P·η) is used (E_window cancels
in every bracket model) — this is not an artifact of scale choice. ⚠️ A definition WITH a sleep term —
script 30's since 2026-09-27 — gives a HIGHER percentage (sleep only raises the contamination), so the
verdict stands and is, if anything, conservative. ⚖️ The rail question this number fed is decided — **RATIFIED founder
2026-09-09** (`00_07` HW.42, [`01_03 §6.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)): a second source on the shared rail
is rejected — closed as an approach, not deferred; a TEG, if integrated at all, needs a physically separate charging path.
The ground holds while growth points are computed from `delta_t` and while the cell-state probe is read from `delta_t` — a
second source moves that probe too; it lapses only when both stop (2026-10-25,
[`01_03 §6.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).
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

**The anchor's anode — conditional on stagnant sap in its gap (2026-10-17; revised the same day after an adversarial pass — the first version read only the pine part, judged it against the coin letter's load point and called the currents upper bounds without the effects that push the other way; every number moved with the revised sap of 2026-10-18, whose buffer is a fifth of the first recipe's).** In the anchor the gyroid stands in the Ø15 bore that also takes the sleeve; on the pine part (envelope Ø11, **13.8 cm²** of side) the gap is **2.0 mm** (both from the CEMs; one sleeve manifest serves every Zone-1 part, so the gap narrows as the lattice thickens). Which of three states a living stem keeps there — sap, air or ingrown wood — is not known, and the HW.53 bench cannot say: it fills the gap with the recipe by hand, so it SETS that state rather than measuring it. With the ratified sap (the revised point, `01_02 §2.1`) lying stagnant in the gap and the bulk at the bore wall, steady radial diffusion gives a film of r_a·ln(r_b/r_a) = **1.71 mm** per unit of envelope on pine. The yardstick is the anchor's own cold-start draw, P_IN(CS)/V_IN(CS): 25.0 µA typical and **21.4** µA at the worst-case column the Stage-2 gates judge (`02_03 §1.5`). On pine the face leaves the enzyme's kinetic bracket (pH 5.5) at **1.9–5.2 µA** for the whole anode (the low end the envelope alone, the high end with the bottom cap at the envelope's flux density) — below the worst-case draw in every reading — and its stability band (pH 4.5) at **23.8–53.2 µA**, above it in every reading. By part — each in its own sap since 2026-10-18 (⚖️ founder): broadleaf and oak in the beech point of `67` Q8 (European beech at the bottom of the stem, Glavac et al. 1990; pH **5.95**, buffer **0.195** mM/pH — ×**1.48** the pine point's; nitrate **0.050** mM, the geometric mid of the dated nitrate of what is inferred to be the same stand (Glavac & Jochheim 1993; stand/date identity inferred, not printed — `01_02 §2.1` ⊕ ⚖️ 2026-10-22), on potassium as in the pine point — ⚖️ founder 2026-10-22; both as proxies — broadleaf is birch and maple, and no *Q. robur* or *petraea* trunk sap was found for oak), every other part in the pine recipe (tropical and mangrove: their own sap is not modelled). Every pine-sap part, and broadleaf, crosses pH 5.5 below the worst-case draw in every reading; oak only in some, from **6.4** µA — its upper end, **21.48** µA, now only just above the worst-case **21.43** µA, by **0.05** µA — a margin INSIDE the recipe's own read-off error on several axes (`85`'s control `oak_verdict_read_off_flip`: one dated median at a time, the rest as read, on the point's nitrate and on both its readings): oak's verdict holds while the 22 Jun 1989 potassium median (**26** mg/L, the point's potassium minimum) is read less than **0.27–0.33** mg/L lower (nitrate readings 0.051 · 0.049; by `67`'s rule, the malate to two significant figures; on the unrounded rule — malate and CaCl₂ without the two-significant-figure rounding, pH continuous — **0.14**) and the 12 Oct 1989 potassium maximum (**190** mg/L) less than **1.99–2.41** mg/L lower (unrounded, **1.05**), while the 31 Aug 1989 pH median (**5.95**) read one **0.01** step lower already flips it — against read-off errors of **±2** mg/L for potassium and **±0.03** for pH; the calcium minimum alone cannot flip it (above 9 mg/L three other dates hold the minimum). So at pH 5.5 oak sits at the worst-case draw within the read-off error — above it only at the point itself, which the error cannot tell apart. No part crosses pH 4.5 below the worst-case draw in any reading — broadleaf, the one that did in pine sap, starts at **26.4** µA in its own — and at the typical 25 µA draw pine and its two topology variants do in some. ⚠️ The beech point's malate is SOLVED from potassium less the measured nitrate, which credits the rest of it to malate — a ceiling on that side, since real sap also balances potassium with sulphate and amino acids — while calcium and magnesium sit on unbuffered chloride and sulphate and the CO₂, phosphate and amino-acid buffers are absent; so the direction of the broadleaf and oak currents' error is not established. And its one pH hides the paper's own summer dates (25 May, 6 and 20 July), when the trunk-base pH falls — coinciding, the paper says, with its highest nitrate (unpublished then; the 1993 figures — of the same stand and dates by inference, not by print — put the three highest of the 26 dates exactly there, **1.20** · **1.01** · **0.94** mM — a reading beside the point, as the pH is): medians **4.52**–**4.58**, the lowest tree **3.81** — the bulk is then below the kinetic edge and at the stability edge before any current. Oak's own trunk sap, read the same day (Van Die & Willemse 1975 — *Q. rubra*, two trees, free outflow from a stem cut, late October): pH **4.9**–**5.0** — below the kinetic edge before any current, **0.4**–0.5 above the stability edge — where beech in September–October stands at **6.15**–**6.62**; on bulk pH the beech point is the kinder reading for oak, while oak's own buffer is not known (its potassium is 2.4× Q8's, no organic acid measured), so what a current does in it is not computed. Oak stays on Q8 (⚖️ founder 2026-10-18) until *Q. robur* trunk sap or oak's organic acids are found. **Which side.** Against the enzyme inside the lattice the currents are upper bounds: protons are made inside it, which the envelope film does not see, and the wood wall adds its own resistance. Migration (a few per cent), any flow through the gap and a CO₂/HCO₃⁻ buffer the recipe lacks push the other way and are not in. In a film this thick the lactone has about an hour to hydrolyse inside it, so the n_H = 1.5 end is no longer the unlikely one it is on the coin; acid made inside the film moves the face less than acid made at it, so the truth lies between the two n_H ends. **What it says:** with stagnant sap in the gap, the anchor anode works below the pH at which its kinetics was measured already at its cold-start draw — on every part, oak in some readings — and at the worst-case draw no part reaches the acid end of its stability band; but in the beech sap both parts sit on, on its summer acid dates, the bulk itself sits at that edge with no current at all — and oak's own sap stands below the kinetic edge. Whether it stays inside the stability band after cold start depends on its working current — the EBFC's own P–V curve, which HW.13 measures. An air gap is not modelled (`84`: layer 1 then runs through contact points only), and ingrown wood is not computed (no transport data for living sapwood in the tree).

⚠️ **Hypothesis, not measurement** ([`00_06 §0`](../../../00_06_SSOT_Documentation_Standard.md)). Every shift is a
**lower bound at the enzyme**: protons are made or consumed under the anode's hydrogel and membrane and inside the
cathode's porous layer, which the outer-face film does not see. Not computed: migration (its sign helps the anode; for
the cathode it brings H⁺ in and takes hydrogen malate out), salting-out of O₂ in test D's NaCl steps (raises f), the
anode at 20 °C, and whether a face at pH 6 inactivates laccase reversibly. The letter now specifies the buffered
cathode medium, the convection and a day-0 diagnostic CV of the anode (⚖️ founder 2026-10-12,
[`01_03 §3.5`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)).

---

## HW.54 — How Much Glucose Must the Sap Bring to the Anchor's Anode? (script 109)

**The question (2026-10-26, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54).** In the state the HW.53 bench sets by hand — the gap between the gyroid and the bore wall filled with sap that does not move — glucose reaches the anode only by diffusion. Below what glucose at the bore wall can that gap not carry the node's draws, and what gives first there? The sap's own glucose is not in the tree; the logs of HW.3 read it.

**What is published, and on which side.** A NECESSARY condition — the limiting diffusion current, the leg's own words: below C = I/S, S = n·F·D·A/δ, the gap cannot carry the draw I for any enzyme, glucose being the only substrate. It is computed on the side that keeps «below X it cannot» true (`85`'s bottom cap added to the area, D at the top of its 95 % uncertainty, the draw's low end) and rounded down. It is never written as sufficient: the unpriced axes — sap more viscous than water, glucose eaten on the way, only β-D-glucose being the enzyme's substrate (Sygmund 2011), the wall's own resistance, the enzyme's ceiling on Ti in sap — raise the true threshold; xylose, the enzyme's other substrate, is the one that would lower it.

**D.** Glucose's measured infinite-dilution diffusion coefficient in water — Mogi et al. 2007, Taylor dispersion, read from the NIST ThermoML record of the paper — at 0, 20 and 25 °C, with the record's 95 % uncertainty (≈ 6.5–7.1 %, its unit read by ratio); Ribeiro et al. 2006 agrees at 25 °C within 0.3 %, and Mogi's 20/25 °C ratio (0.895) sits within 2.5 % of the Stokes–Einstein ratio from water's viscosity (0.8737). On the pine part the gap carries **98.83 – 120.33 µA per mM** at 25 °C (the envelope at D − U, then the bottom cap at D + U) — the desk estimate of 2026-10-25 (≈ 104) lies inside — **88.35 – 107.79** at 20 °C and **46.91 – 57.82** at 0 °C: D falls ×0.478 from 25 to 0 °C.

**The draws.** The BQ25570 cold start, 25.0 µA (typ) and 21.43 µA (the worst-case V_IN column). The sleep loads at VSTOR become an input current through the boost, whose efficiency `02_03 §9.1` gives only at anchors read by eye — ≈ 20–30 % at ~10 µA, then 0.68 · 0.75 · 0.82 at its table's currents, each ± its own read error (±0.15) — so the current is bracketed between the roots of the two extreme non-decreasing curves through those intervals, at V_OP 0.5 V and 0.325 V (both kept, their hull published, neither chosen): Scenario C's target 4.18 µW (`§9.6`; its mechanism refuted, the target stands) **10.07 – 46.15 µA**; the shipped STOP2, 9.26 µW (`§9.3`), **22.31 – 53.76 µA**; the shipped STOP2 plus `§9.3`'s illustration of a 1 µA EDLC leak (not a measurement) **33.16 – 79.88 µA**.

**Result — the necessary threshold** (the draw's low end), across the Zone-1 parts:

| Draw | 20 °C | 0 °C |
|---|---|---|
| Cold start, typ | 0.09 – 0.32 mM | 0.17 – 0.59 mM |
| Sleep, shipped STOP2 | 0.08 – 0.28 mM | 0.15 – 0.53 mM |
| Sleep, Scenario C target | 0.03 – 0.12 mM | 0.07 – 0.24 mM |

The low end is the tropical part (the narrowest gap), the high end the broadleaf part (the widest); pine sits at 0.23 mM for the cold start at 20 °C and 0.43 mM at 0 °C.

**First, the face leaves the enzyme's measured pH window.** In the same stagnant gap `85` prices the PROTON half of the supply: the face reaches pH 5.5 — the acid end of the enzyme's measured kinetics, not a stop — at 1.9–5.2 µA on pine, and pH 4.5 at 23.8–53.2 µA (25 °C). **31 of 35** draw×part pairs exceed the pH-5.5 current in every reading (the rest in some), and on pine the cold start reaches pH 4.5 in some readings — so sap above the glucose threshold does not by itself keep the face inside that window. An estimate in series with the enzyme (the pH-7.4 laboratory ceiling on the envelope area; Ea 19.5 kJ/mol, measured by Sygmund 2011 for the free enzyme at 26–51 °C, or 40 assumed) puts the pine cold start at 20 °C at 0.30 mM; whether the envelope area over- or understates the kinetic term is not established, so the estimate carries no direction.

**What it cannot see.** Whether a living stem keeps the gap stagnant; glucose consumed on the way; the α-anomer's mutarotation; xylose; the wall's resistance (embolised tracheids, resin); temperatures between 0 and 20 °C other than by bracketing, and the proton half below 25 °C; the enzyme's ceiling on etched Ti in sap.

## HW.54 — Could a Photovoltaic Cell on the Dome Carry the Node through Winter? (script 110)

**The question (2026-10-26, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(б)(2)).** The desk pass left PV on the capsule's dome as the only power candidate without consumables, and only as an estimate: the EDLC carries the node a few days without sun, so the measure is the worst multi-day stretch of winter light — a number the tree did not hold. How large must a cell's effective aperture be for the store never to empty over 1991–2020?

**What is published, and on which side.** A NECESSARY condition per demand: below the effective aperture A_eff = η_pv · T · A the store empties somewhere in the record. The cell enters only through that product, so its efficiency at daylight and the canopy's winter transmittance — the next legs' unknowns — stay inputs. Three demands are printed and none is picked: the Standby sleep target alone, cadence C and the shipped STOP2 sleep at cadence C. Within a demand every other input is a reading at three corners. The favourable one puts each input the specifications bound at the end of the widest band the canon carries that lowers the threshold — the capacitance's +80 % tolerance, VBAT_OV and OK_PROG at their worst-case bands on our 1 % resistors (`02_03 §4.Б`, `§4.Г`), the low end of the wake energy, no leak — and takes the boost at its `§9.1` plateau's top, **0.90**, at any input, because a PV cell's input voltage is not the EBFC's the anchors were read at; the reflected light is the brighter of `79`'s two readings, not the end of a band (brighter ground would lower the threshold). The threshold is rounded down. The store empties at OK_PROG, not at `§8`'s OK_HYST: from a full store the buck stays on down to the falling threshold, so the window to the first outage is the full one `§9.10` uses — **2.8863** J nominal, **6.1467** favourable, **1.3247** adverse. The adverse corner (the capacitance's low tolerance edge with the end-of-life loss, the least efficient boost curve through the EBFC anchors at V_OP 0.5 V, the high end of the wake energy, `§9.3`'s 1 µA leak illustration, the darker reflected light) says how high the same requirement climbs inside those bands. Neither is sufficient.

**Light.** ERA5 at the Cherkasy grid point, hourly; the face is vertical. Open field: the beam on the face plus half the diffuse and half the reflected light, four faces printed (the gateway sets the azimuth, not the sun). Closed stand: two forms, and which one fits a closed stand is not established — the desk's isotropic ½(1 + ρ)·GHI and the beam through the gaps (the open face's light) — with the canopy's T folded into A_eff either way, so the closed stand takes the lower. December's mean daily GHI comes out **651.9** Wh/m² against the desk's PVGIS-SARAH3 636 and NASA POWER 663; the worst 7-day December–January running mean of GHI is **330.5** Wh/m²/day (from 1993-12-25), the median of the season minima **400.5**, over **29** winters — the desk's 331 and 401, within 1 Wh/m²/day. Over November–March the worst single day is **87.0** Wh/m², the worst three days average **159.0**, the worst fortnight **393.1**.

**Result — the necessary effective aperture, cm²** (the closed stand's lower form; on these rows it is the beam through the gaps or a tie, so the open field's lowest face gives the same number):

| Demand | Favourable corner | Nominal, brighter light | Adverse corner |
|---|---|---|---|
| Standby sleep target alone | 0.00109 | 0.00265 | 0.0357 |
| Cadence C | 0.00427 | 0.00872 | 0.103 |
| Shipped STOP2 at cadence C | 0.00837 | 0.0242 | 0.165 |

The desk's bracket of A_eff on the dome face (6.975 cm²; η_pv 3–5 % ASSUMED, T 0.21–0.55 from Sonohat 2004) is **0.0439–0.1918** cm² under the closed stand and **0.2092–0.3487** in the open. At cadence C the favourable threshold sits 7–10 times below the closed-stand bracket's low end (the isotropic form gives the 7, the beam the 10); the adverse one, **0.103**, sits inside it — the bracket's range below it fails — and below the whole open-field bracket. The record does not rule PV on the dome out; on the adverse readings it rules out the low part of the desk's closed-stand range.

**What binds.** On the favourable readings, weeks of weak light: the store is last full on 1996-11-21 and empty on 1996-12-16 (the isotropic form; on the south face 2012-11-24 → 2012-12-13). On the adverse ones, a 41-hour overcast stretch, 2017-12-01 → 2017-12-03, with no direct beam at all — so every face and both closed-stand forms need the same aperture. Without any light the window carries cadence C **7.57** days on the favourable corner, **3.27** nominal and **0.93** adverse (the Standby sleep alone 17.01 · 7.99 · 1.76; STOP2 at cadence C 4.91 · 2.18 · 0.71; all rounded down). On `§8`'s 2.75 J window with the nominal capacitance and the 1 µA leak illustration — the reading `01_03 §4`'s desk line names — the span is **1.6–3.66** days, not «≈ 1.4–3.6».

**The threshold the winter measurement is read against (2026-10-27, before the data — [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(б)(4)).** The field sheet [`stem_face_winter_light`](../stem_face_winter_light.md) measures R, the ratio of the light on a vertical stem face at the anchor's height to an open horizontal's. Read as G = R·GHI, the canopy's T, the face's geometry and its horizon sit inside R, so the effective aperture is η·A with A the outer dome face — an upper bound on a cell's area, not a cell the dome holds: the cell sits inside the capsule behind a window, and the radome's flat crown is only Ø19.8 mm (3.08 cm²) before any glue land; a smaller cell raises R in inverse proportion to its area, and the packaged cells and die strings that fit there need more R on the adverse corner than its diffuse-only stretch gives even in the open (`01_03 §4` ⊕; the per-area thresholds and that bound are in the cache's `measured_form_r`). The harvest depends on η·A·R alone (the boost read in power, as everywhere in this model), so one bisection on GHI per lane gives the R below which the store empties at any η — a necessary condition, rounded down, R taken constant over the record — here at the two ends of the efficiency bracket `01_03 §4` carries: 3 % (a-Si's low end) and 8 % (a good c-Si cell's top, which that source reaches at 5 % of open light; at the few per cent of open light the favourable and nominal rows sit at, it gives c-Si at most 5 %, so there the 8 % column is an optimistic pairing):

| Demand (R below which the node cannot ride the record, η 3 % ⊥ 8 %) | Favourable corner | Nominal | Adverse corner |
|---|---|---|---|
| Standby sleep target alone | 0.00744 ⊥ 0.00279 | 0.0132 ⊥ 0.00495 | 0.100 ⊥ 0.0378 |
| Cadence C | 0.0218 ⊥ 0.00818 | 0.0358 ⊥ 0.0134 | 0.291 ⊥ 0.109 |
| Shipped STOP2 at cadence C | 0.0390 ⊥ 0.0146 | 0.0749 ⊥ 0.0281 | 0.466 ⊥ 0.175 |

At cadence C the binding stretches on this form run inside the sheet's window, the favourable one from its eve: on the favourable corner the store is last full on 2007-11-30 and empty on 2007-12-27, on the adverse one the same 41-hour overcast stretch as above, with no direct beam. Not every row: the Standby sleep's favourable stretch runs 1997-11-10 → 1998-01-20, so November light, which the sheet does not measure, decides that row. The sheet's silicon pyranometer weighs light roughly as a c-Si cell does; under a canopy that shifts light toward the near infrared (a sign the sheet takes from an unverified abstract) an a-Si cell's R would be lower, so against the η 3 % column the measured R is biased high. So is an R measured over a snowy winter against these bare-ground stretches, and its reference is the yard's open horizontal, not ERA5's cell; an R that moves with the day, the sky, the ground or the season is outside this form. Necessary conditions only. ⊕ 2026-11-09 (the sentences above are NOT rewritten): the measurement was narrowed to one logger on the south face against ERA5's GHI, with no yard reference ([`01_03 §4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md), ⊕ under Р3(б)(4)) — so the reference is now ERA5's cell, and with a broadband GHI in the denominator the sensor's calibration and silicon weighting no longer cancel: the «biased high against η 3 %» above was derived for silicon over silicon, and for this R its sign and size are not estimated. The thresholds themselves are unchanged: `110` already multiplies R by ERA5's GHI.

**Controls.** Each says in the script what it can and cannot catch: the store's recurrence against closed forms without harvest and after blinding hours (its ceiling), the harvest arm against a closed form on a constant field, the vector against a scalar boost curve, `79`'s sun and clock gates, the faces' orientation at the winter solstice, December's GHI against the desk's sources, the desk's 7-day number, monotone outages around every threshold.

**What it cannot see.** Snow, rime and dirt on the dome, and the dome's optics (PEEK has no optical path — PV is a radome change); the cell's temperature and its efficiency's dependence on light; the boost's dependence on its input voltage (the `§9.1` anchors are an EBFC's; a PV cell sits near its own MPP); the capacitance and the leak at frost, which the leg asks for and `§12.1` does not rate; what follows an outage — the hysteresis, the warm-up cost, a cold start below 0 °C; the canon's state-dependent winter mode (`§9.8`); winter light under a canopy on a vertical face; the canopy's own ground light (the reflected ends are open-field ones, neither an extreme); a winter worse than the record's worst.

## HW.54 — How Much Does a Dark PV Window in the Dome Heat the Capsule and the Cambium? (script 111)

**The question (2026-10-28, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, the leg «тепловий прогін `71` і `78` з α комірки на грані — дужкою, доки комірку не обрано»).** The radome's finish is specified as α ≤ 0.5 for its whole service life (`02_01 §5.2`), on two grounds: the EDLC's margin at the dark end is of the order of the model's own uncertainty (`71`), and the cambium under the flange's thinnest contact reaches its 50 °C gate past α ≈ 0.66 (`78`, interpolated on `71`'s α grid). The only PV form the desk kept is a cell inside the capsule behind a window in the crown (`01_03 §4` ⊕ Р3(б)), and `71` and `78` take the dome as one uniform finish, so neither says what a dark patch of a given area does.

**Model.** `71`'s lump and `78`'s column, imported; only the absorbed power changes. A two-zone dome — the window's dark aperture A_dark at α_c, the rest at α 0.50 — in `71`'s own worst-orientation construction (the largest projection over all beam directions, an upper bound on the direct gain): the crown projects as cos ψ, the side wall as sin ψ, and the patch sits in the crown, so the beam enters as α_beam = √((α_r·A_crown + Δα·A_dark)² + (α_r·D·H)²) / A_proj, and the diffuse as the area-weighted α_r + Δα·A_dark/A_exp. α_c = 1.00 is the bound — no surface absorbs more than all the light that reaches it, and whatever the cell exports (stored and spent by the node inside the same lump, or radiated out by the radio) can only lower the heat; 0.90 is ours. h_c is read at `71`'s two readings, nominal and × 0.7, for the capsule and the cambium alike: `71` counts that band in its own uncertainty, so a window «stays under» only on the reading named. The named areas are `110`'s, of two kinds: the package and the dies are cell outlines — a window that exposes them is at least as large, so on those rows the dark aperture is a lower bound — and the flat crown and the bore are windows. The control that can fail on the two-zone term: its closed form against a brute force over ψ, for every named area and α_c. Three plumbing identities check the wiring and nothing more — they pass for any formula that returns α_r when Δα·A_dark = 0: no window reproduces `71`'s α 0.50 row (52.9 °C) and `78`'s cambium cell on both bark sides; a uniform α 0.70 dome reproduces both α 0.70 rows; no window at h_c × 0.7 reproduces `71`'s cached sensitivity row (55.0 °C), the h_c × 0.7 path's wiring.

| window (`110`'s named area) | kind | area, cm² | α_beam ⊥ α_diffuse | capsule, °C: nominal h_c ⊥ × 0.7 | cambium at the thinnest contact, °C · hours above 50 °C in 30 years: nominal h_c ⊥ × 0.7 |
|---|---|---|---|---|---|
| one package in the crown | cell outline | 0.908 | 0.542 ⊥ 0.519 | 53.9 ⊥ 56.1 | 47.44 · 0 ⊥ 49.22 · 0 |
| four dies in the crown | cell outline | 1.44 | 0.567 ⊥ 0.530 | 54.5 ⊥ 56.8 | 47.92 · 0 ⊥ 49.78 · 0 |
| the whole flat crown | window | 3.08 | 0.648 ⊥ 0.565 | 56.4 ⊥ 59.0 | 49.45 · 0 ⊥ 51.52 · 31 |
| the whole bore | window | 5.23 | 0.757 ⊥ 0.610 | 58.9 ⊥ 61.8 | 51.47 · 26 ⊥ 53.82 · 309 |

(α_c 1.00, full sun, still air — `71`'s and `78`'s worst cell.)

**Result.** No named window brings the capsule to the EDLC's 70 °C rating on either h_c reading — the hottest hour is 58.9 °C, 61.8 °C with h_c × 0.7. The cambium is what binds, and the h_c band decides how far: on the bound the largest dark aperture that keeps the cambium under the gate is 3.66 cm² at the nominal h_c and 1.65 cm² with h_c × 0.7 (4.58 ⊥ 2.06 cm² at α_c 0.90; floored to 0.01 cm², grid 0.10 cm²). So on both readings a window clears the gate up to ≈ 1.65 cm² of dark aperture — the four dies' outlines, summed with no spacing (1.44 cm²), sit 0.21 cm² under it, while a window around a spaced string is larger and is not shown to clear with h_c × 0.7; the whole flat crown clears it at the nominal h_c only, by 0.55 K, and not with h_c × 0.7 (31 hours in 30 years); the whole bore clears it on neither (26 ⊥ 309 hours). Read the two outline rows against the crossing, not as windows. α 0.50 itself — the dome without a window — stays under the gate on both readings on the bracket's thinnest contact (46.62 ⊥ 48.29 °C); the canon's crossing at α ≈ 0.66, the headroom the ratified finish names for ageing, is a nominal-h_c number — `78`, run at h_c × 0.7 too, puts it at α ≈ 0.57 there (`01_04 §3.1` ⊕ 2026-10-28), so on that reading and that contact the headroom is 0.5 → 0.57. Above the crossings the bound does not clear the gate, which is not a crossing.

**Direction and what it cannot see.** Every term inherited from `71` and `78` pushes the temperatures up (the worst orientation over all beam directions, the adiabatic base, the flange at the capsule's temperature, the 1D column, the adiabatic inner end), and α_c = 1 does too, so every hot number is an upper bound and «stays under» is sufficient within those models on the h_c reading it names. Two terms run the other way and are named, not hidden: `71`'s own ceilings — sunlit bark around the rim conducting in, ERA5 smoothing station maxima — move the hot answer up beyond these bounds; and a window wider than the flat crown sits on the R5 edge, which `71` models as part of a flat disc — for every window in the table and every crossing (none wider than the bore) the patch is centred and its edge slopes less than 90° − ψ* at the binding angle, so a convex patch projects as its planar disc and the beam term stays the bound, while the diffuse term counts the planar disc, a few per cent less than the curved surface; near the whole crown the edge reaches 90° and the condition fails, so nothing there is quoted. Not seen: the window's optics (transmittance, its own absorption, the cavity's greenhouse — the lump is isothermal); a cell's real absorptance; whether a window meets the ratified α ≤ 0.5 at all — a verdict, not a number; the window's RF half (`01_03 §4`). Cache: `thermal/pv_window_thermal.json`.

## HW.54 — Can a Point Dendrometer Use the Anchor as Its Support? (script 114)

**The question (2026-10-30/31, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(в)).** The desk leg (`01_03 §4` ⊕ (в)) left the principle standing — a point dendrometer whose probe rests on the cleaned live bark, held by the Ti flange, its scale read through the capsule wall — and named its weakest links without numbers: the support's thermal path with PEEK in it («≈ 5–10× worse than the < 0.3 µm/K of commercial frames» — the collector's derivation, not re-read), a count that must survive a winter swing and the outages of the same nights, the energy of a read, and the travel. `114` turns each into a number from inputs the tree already holds (numbers — `cache/mechanical/dendrometer_support_budget.json`).

**(1) The support's thermal artefact.** Under a uniform ΔT the reading moves per kelvin by A = ∫₀^z_f (α_w − α_anchor) dz + (α_s − α_w)·z_t + (α_s − α_h)·h — the closure of the loop fixation → anchor → holder → scale → bark → wood. The last two terms are DESIGN terms (the scale's and the holder's material, the sensor's height), nulled in the base reading, with their sensitivity in the cache; the first is the ANCHOR's, on `103`'s sections, and it cannot be designed away until it is known where the wood holds the anchor. It is printed at named fixation depths, under both of `103`'s premises for what locates the flange — (a) the Zone-3 shank in clearance, the disc on the sleeve's top and the whole span PEEK ⊥ (b) the shank held by a Zone-3 fit — and with the Zone-1 shank read two ways: bonded by its fit (`103`'s reading) ⊥ the fit slipped and the sleeve resting on the gyroid's shoulder (the adverse end for |A| under (a), an intermediate one under (b)):

| reading (premise · Zone-1 shank) | \|A\| reaches the frames' 0.3 µm/K at z_f, mm | \|A\| with a tie at the install-day cambium, thin ⊥ thick side, µm/K | at the shank's top, µm/K | at the gyroid's bottom, µm/K (× the frames) |
|---|---|---|---|---|
| (a) flange on the bark · Zone-1 shank bonded | 7.67 | 0.443 ⊥ 0.938 | 1.251 | 1.306 (×4.4) |
| (a) flange on the bark · on its shoulder | 7.67 | 0.443 ⊥ 0.938 | 1.251 | 1.983 (×6.6) |
| (b) Zone-3 fit · Zone-1 shank bonded | 21.01 | 0.021 ⊥ 0.417 | 0.73 | 0.784 (×2.6) |
| (b) Zone-3 fit · on its shoulder | 21.01 | 0.021 ⊥ 0.417 | 0.73 | 1.462 (×4.9) |

On the one green-xylem reading the tree holds (7.9 ppm/K radial, Sevanto et al. 2005) every anchor section expands more than the wood, so the ANCHOR term is negative at every point — alone it would make the reading shrink on warming and swell on cooling, at dawn, when a stem rehydrates and the zero-growth method credits new growth. That sign rests on thin margins: the gyroid exceeds the wood's α by 0.7 ppm/K, the bonded Zone-1 composite by 1.5, the Zone-3 composite by 1.9. And it is the anchor term's, not the reading's: the design terms are nulled, not zero — each ppm/K by which the scale's α exceeds the wood's adds z_t·10⁻³ µm/K (0.008 on the thin contact, 0.021 on the thick side) and each by which it exceeds the holder's adds h·10⁻³, so a mismatch of a few tens of ppm/K matches the anchor term at a tie, and the total's sign is the design's to set. Under the frames' 0.3 µm/K the anchor term stays only for a hold shallower than **7.67 mm** below the flange seat under premise (a) — 0.652 mm above the live bark at the thin contact, so a hold that keeps the anchor term under the frames sits in the dead bark (whose α the model takes at the xylem's) — thermally only: a hold there follows the bark as the bearing below does — or is a callus tie that has climbed that high — and **21.01 mm** under (b), which leaves the wood from the install-day cambium (11.3 mm) to 21.0 mm on the thin contact and none on the thick side, where the crossing sits 0.008 mm into the live bark (the 21.01 mm rests on the cathode flange CEM's shank length, a placeholder — `00_07` HW.8.9). At the deepest hold the anchor term reaches ×2.6 … ×6.6 the frames, and above ×5 only on one reading: premise (a) with the Zone-1 fit slipped and the hold at or below the gyroid's top (×6.5 there, ×6.6 from the anode's centroid down); every bonded reading stays at or under ×4.4, the Zone-3 shoulder reading at ×4.9. So within this model the collector's «5–10×» is reached on that one reading and its upper half on none — which reading holds is a fit state and a fixation point the tree does not know. A callus tie climbs toward the flange as the stem grows, so A drifts by up to 0.20 µm/K a year at the fast end (0.03–0.20 where the tie sits in PEEK, 0.001–0.009 for a Zone-3 tie in the composite on the thin contact). With the AIR as a proxy for the stem's interior (ERA5 — not a bound: the flange runs far above the air in sun and radiates to the sky at night, `78`), the worst reading moves **12.8 ⊥ 19.4 µm** over a median growing-season day (bonded ⊥ shoulder; 18.5 ⊥ 28.2 at the 95th percentile) against the 5 µm a TreeNet record resolves, and 28.9 ⊥ 43.8 µm between the 5th and 95th percentile daily means of the unfrozen days (frozen wood's strain is not thermal expansion).

**The bark bearing** is not a thermal term: a flange that bears on the dead bark ties the reference to the surface measured. Between the deep wood (the anode bond and the sleeve in series) and the bark, the flange follows a radial change of the bark by U = (1/k_A + 1/k_s)/(1/k_A + 1/k_s + 1/k_F), and the reading loses that fraction. With the anode bonded (`103`'s state 2), on `103`'s stiffnesses under premise (b), sway and slow, U = **0.2–42 %** over the air-dry bark readings — **1.7–338 µm/yr** of the 795 µm/yr the driest sites lay down — and 100 % for a rigid bark; before the anode is bonded the deep tie is not the anode but the sleeve's grip in its Ø15 channel (and ice in the gap at the cold edge), which `103` leaves unbounded, so U there is not priced. Under premise (a) a rising bark can lift the flange off the sleeve and leave no reference at all (our reading; `103` does not model lift-off).

**(2) The scale behind the wall.** A periodically magnetised scale read by a two-axis Hall sensor (TI TMAG5273, datasheet SLYS045 §5.7 A1 and §5.11) across a gap g of at least the radome's wall (2.0 mm in its CEM, so the g 1.5 mm rows sit below it — `gap_below_radome_wall`; a sensor package and clearance add to it), in an idealised field (sinusoidal magnetisation, infinite width): a common gain — the magnet's temperature coefficient with it — cancels in the atan2; the offset drift, the axes' gain mismatch and the angle error do not. Per scale thickness t and gap g, at the period P* that minimises the offset term:

| t · g, mm | P*, mm | B_r the offset term alone needs, T: typ ⊥ max drift | field at the sensor, mT: typ ⊥ max | angle error, µm: X–Y ⊥ X–Z | gain-mismatch drift, cyclic peak over the datasheet's range, µm: X–Y ⊥ X–Z | unwrap margin across a season's outage |
|---|---|---|---|---|---|---|
| 1 · 1.5 | 6.01 | 0.2 ⊥ 0.667 | 13.5 ⊥ 45.1 | 8.3 ⊥ 16.7 | 23.9 ⊥ 71.7 | 0.871 |
| 1 · 2 | 7.64 | 0.318 ⊥ 1.059 | 17.2 ⊥ 57.3 | 10.6 ⊥ 21.2 | 30.4 ⊥ 91.2 | 1.107 |
| 1 · 3 | 10.84 | 0.631 ⊥ 2.104 | 24.4 ⊥ 81.3 | 15.1 ⊥ 30.1 | 43.1 ⊥ 129.4 | 1.571 |
| 1 · 4 | 14.02 | 1.049 ⊥ 3.498 | 31.5 ⊥ 105.2 | 19.5 ⊥ 38.9 | 55.8 ⊥ 167.4 | 2.032 |
| 2 · 1.5 | 6.96 | 0.145 ⊥ 0.484 | 15.6 ⊥ 52.2 | 9.7 ⊥ 19.3 | 27.7 ⊥ 83.1 | 1.009 |
| 2 · 2 | 8.69 | 0.217 ⊥ 0.724 | 19.5 ⊥ 65.2 | 12.1 ⊥ 24.1 | 34.6 ⊥ 103.7 | 1.259 |
| 2 · 3 | 12.03 | 0.4 ⊥ 1.334 | 27.1 ⊥ 90.2 | 16.7 ⊥ 33.4 | 47.9 ⊥ 143.6 | 1.743 |
| 2 · 4 | 15.28 | 0.636 ⊥ 2.118 | 34.4 ⊥ 114.6 | 21.2 ⊥ 42.4 | 60.8 ⊥ 182.4 | 2.214 |

The period is what makes the count recoverable without the device. The device sends the phase and the server unwraps the series — nothing is persisted on the device (the RTC backup domain does not survive an outage on our board, `03_01`) — and the unwrap holds while every change between two delivered readings stays under P/2, on four conditions the cache names (`unwrap.count_home`) and none of which exists yet: the phase needs a field on the wire; a maintenance step that moves the sensor against the scale must be marked a discontinuity by the server; the server must keep a persisted running position, not recompute over a ledger that expires; and the sensor's mount must not creep. On a declared, season-consistent basis the period must be at least **4.0** mm through a winter's frost swing, **2.9** mm over a growing month at the fast end with the daily swing, **6.9** mm across an outage that spans a season: at P* every geometry meets the first two, and the last fails only at t 1 mm on g 1.5 mm, a gap under the wall; a period above P* buys unwrap margin at a small cost to the offset term (its optimum is flat), while the angle and mismatch errors grow in proportion to P. The cross-season basis assumes an outage spans one growing month, our assumption: over two the period must reach 9.4 mm, met at P* only from g = 3 mm. A 2 mm-period encoder keeps 0.0003–0.9 % of a scale's surface field at these gaps (its own field requirement is not in the tree). What the period does NOT buy: the sensor's own error terms exceed the 5 µm resolution at every geometry (the smallest, the X–Y angle error, by ×1.7 at t 1 mm on g 1.5 mm — under the wall — and ×2.1 at the wall's 2 mm), and calibrating the angle error in place needs the scale to pass a full period — 1.2–3.1 years at the fast end, 7.5–19.1 at the slow one (`in_place_angle_calibration_yr_fast_slow`); a bench calibration of the sensor and scale before mounting is not excluded and not computed. The offset term alone asks for a remanence of 0.145–1.05 T at the datasheet's typical drift and 0.48–3.5 T at its maximum, and at the maximum the field then exceeds the sensor's ±40 mT range everywhere and its ±80 mT from g = 3 mm; the magnet families a need is held against are a mirror of the canon's desk (next paragraph), so these are what a scale NEEDS, not what a product has.

**The sensor's linear range caps the period, and the scale's thickness is a knob (2026-11-10, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54 Р3(в)).** The field the offset term needs at the sensor is P·√2·δB/(2π·0.3 µm/K) — the period alone sets it, neither the magnet nor the thickness — so the sensor's linear range caps the period: **10.66** mm inside ±80 mT at the datasheet's maximum drift (5.33 inside ±40 mT; 35.54 ⊥ 17.77 at the typical drift) — ±80 ⊥ ±40 mT, on the datasheet's one offset-drift row for both ranges (`within_sensor_linear_range`). From g = 3 mm every P* in either block lies above that cap at the maximum drift, so a scale there is read at the cap, its remanence need rises above the P* figure, and for a magnet equal to the need its angle and mismatch errors are the cap's (14.8 ⊥ 42.4 µm, X–Y) for every computed thickness — a stronger magnet reads at a shorter period, so for it these are upper bounds; at the typical drift the ±80 mT cap binds on none of these rows. A thicker scale (`scale_thickness_knob`, t 3 · 5 · 10 mm, a block of its own so the table above keeps its t 1–2 mm population) lowers the remanence at its own P* to ×0.518–0.888 of the t 2 mm row at the same gap, at a P* of 7.66–21.54 mm. The magnet families are the canon's desk ([`01_03 §4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) ⊕ (в), mirrored in the script's `MAGNET_FAMILIES_BR_T`): the range of IEC 60404-8-1 specified minima over each family's classes — RECo₅ 0.80–0.93 T, RE₂Co₁₇ 0.90–1.10 T, sintered REFeB 0.98–1.42 T — and sintered ferrite's MMPA typical 0.23–0.41 T; a family «meets» a need when some class of it reaches the need. At the maximum drift, inside the ±80 mT cap, at g 3 and 4 mm (`01_03 §4` takes 3 mm as the assumed floor of a realistic gap — the sensor package's depth is not checked):

| t · g, mm | P*, mm | B_r at P*, max drift, T | over the t 2 mm row at the same gap | inside ±80 mT: period, mm | B_r needed there, T | families with a class at or above it |
|---|---|---|---|---|---|---|
| 1 · 3 | 10.84 | 2.104 | — | 10.66 | 2.105 | none |
| 2 · 3 | 12.03 | 1.334 | — | 10.66 | 1.354 | REFeB |
| 3 · 3 | 13.04 | 1.086 | 0.814 | 10.66 | 1.13 | REFeB |
| 5 · 3 | 14.67 | 0.902 | 0.676 | 10.66 | 0.989 | RE₂Co₁₇ · REFeB |
| 10 · 3 | 17.18 | 0.793 | 0.594 | 10.66 | 0.94 | RE₂Co₁₇ · REFeB |
| 1 · 4 | 14.02 | 3.498 | — | 10.66 | 3.795 | none |
| 2 · 4 | 15.28 | 2.118 | — | 10.66 | 2.441 | none |
| 3 · 4 | 16.4 | 1.668 | 0.787 | 10.66 | 2.038 | none |
| 5 · 4 | 18.27 | 1.322 | 0.624 | 10.66 | 1.784 | none |
| 10 · 4 | 21.54 | 1.097 | 0.518 | 10.66 | 1.695 | none |

At g = 3 mm the cap raises the t 2 mm scale's need from its P* figure to 1.354 T — only sintered REFeB's strongest class reaches it, and the next class (1.35 T) misses it by 0.3 %, a margin the idealised field does not resolve — and on the computed thicknesses RE₂Co₁₇ reaches the need from t 5 mm; at g = 4 mm no computed thickness brings the need under any family's 1.42 T. These verdicts are ISOTHERMAL and read on the gap grid; the magnet's temperature and the solved limits are the next paragraph's, and on 3 mm its adverse corner overturns the t 2 mm cell. At the wall's own 2 mm the need inside the cap is 0.521–1.059 T for t 10 → 1 mm. These hold against the sensor's guaranteed (maximum) offset drift and are what a scale NEEDS: which class, its corrosion outside the radome and its temperature coefficient are the canon's to say.

**The magnet's temperature, and the limits solved (2026-11-10, `scale_magnet_temperature`, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54 Р3(в)).** The B_r coefficient cancels in the atan2 but not in the two absolute bounds, and they bind at opposite ends. With B_r(T) = B_r(T_ref)·(1 + α·(T − T_ref)) — T_ref in the (23 ± 5) °C band a unit meets its class minimum at (IEC 60404-8-1:2023 §5.2) — a period fixed for the batch must keep the weakest unit over the offset term's need at the hottest hour and the strongest inside the range at the coldest; a unit meeting its minimum at 18 °C is weaker at every temperature than one meeting it at 28 °C, so the band is a spread between units. The kind corner (a uniform batch meeting its minimum at 28 °C) takes the coefficient's smaller end, `78`'s hottest flange hour at the ratified α 0.5 (**52.9 °C**, sunlit, still air) and the record's coldest air hour (**−27.4 °C**); the adverse corner judges the need on the 18 °C unit and the cap on the 28 °C one, with the larger end, `78`'s α 0.9 hour (**63.1 °C**) and `81`'s sky-cooled capsule edge in that same hour (**−33.53 °C**). The coefficients are the 2001/AMD1:2004 tables' TYPICAL values for 20 °C to 100 °C — RECo₅ −0.04, RE₂Co₁₇ −0.03, REFeB −0.10…−0.12 %/°C (`01_03 §4` ⊕ (в)) — so below 20 °C the model extrapolates them linearly. The cap shrinks per family (kind ⊥ adverse): REFeB from 10.66 to **9.85 ⊥ 9.39** mm, RE₂Co₁₇ to **10.41 ⊥ 10.32** mm, RECo₅ to **10.32 ⊥ 10.21** mm. A family holds a cell when its strongest class reaches the minimum, over a continuous period inside its cap, of the hot-end need. The limits are solved roots, not grid rows (§When Modifying #54), at the maximum drift inside ±80 mT, by the offset and range bounds; a gap limit is rounded down and a thickness limit up, the side that keeps «holds» true:

| family (strongest class) | gap limit, mm, at t 1 · 2 · 3 · 5 · 10 mm: isothermal | kind | adverse | holds g = 3 mm from a thickness of, mm: isothermal ⊥ kind ⊥ adverse |
|---|---|---|---|---|
| REFeB (1.42 T) | 2.38 · 3.08 · 3.38 · 3.61 · 3.70 | 2.34 · 2.99 · 3.25 · 3.44 · 3.50 | 2.30 · 2.91 · 3.15 · 3.31 · 3.36 | 1.84 ⊥ 2.02 ⊥ 2.27 |
| RE₂Co₁₇ (1.10 T) | 2.04 · 2.64 · 2.95 · 3.18 · 3.26 | 2.03 · 2.63 · 2.92 · 3.13 · 3.21 | 2.02 · 2.62 · 2.91 · 3.11 · 3.19 | 3.25 ⊥ 3.45 ⊥ 3.57 |
| RECo₅ (0.93 T) | 1.84 · 2.37 · 2.66 · 2.89 · 2.98 | 1.83 · 2.35 · 2.64 · 2.84 · 2.92 | 1.82 · 2.34 · 2.62 · 2.82 · 2.89 | none ⊥ none ⊥ none |

On 3 mm the t 2 mm scale then needs **1.426 ⊥ 1.503 T** (kind ⊥ adverse), over REFeB's 1.42 T: the adverse corner carries the overturn (by 5.8 %), while the kind corner misses by 0.37 % — inside what the idealised field resolves (the 0.3 % above). It holds while the scale's hottest hour stays under **50.3 ⊥ 32.4 °C** at each corner's other inputs; `78`'s shaded flange at α 0.5 reaches 42.8 °C, under the kind threshold and over the adverse one, so shade helps at the kind corner only. REFeB holds 3 mm from a scale **2.02 ⊥ 2.27** mm thick, RE₂Co₁₇ from **3.45 ⊥ 3.57** mm, and RECo₅ at no thickness: even an infinitely thick scale needs **0.938 ⊥ 0.972 ⊥ 0.988 T** there (isothermal ⊥ kind ⊥ adverse). A unit above its class minimum shortens the cap again, as 1/(1 + s): at an assumed s of 3 ⊥ 5 % the adverse thickness limits rise to **2.38 ⊥ 2.46** mm (REFeB) and **3.82 ⊥ 4.05** mm (RE₂Co₁₇) — the standard sets no upper limit, so s is not read. At the maximum drift, by the offset and range bounds, at the wall's own 2 mm REFeB and RE₂Co₁₇ hold every computed thickness and RECo₅ every one but t 1 mm, and at 4 mm no family holds any computed thickness. Adding the period the unwrap needs across a season's outage (≥ 6.9 mm), with any class of the family's span chosen, takes REFeB out at t 5 and 10 mm on the wall at both thermal corners — even its weakest class puts more than the range on the sensor at the cold end there — and at 1.5 mm takes every family with a coefficient out at t 2 · 3 · 5 · 10 mm, and REFeB at t 1 mm at the adverse corner; from 3 mm the floor changes no verdict. The unwrap basis is itself a coupling: a TWO-month basis needs a period of 9.4 mm, over REFeB's adverse cap (9.39 mm), so on that basis REFeB holds no cell at the adverse corner, while both RECo families' caps clear it. Sintered ferrite (typical values, no coefficient in the tree) is solved isothermally: at the maximum drift it holds a gap up to 1.08–1.59 mm for t 1 → 10 mm and not the wall's 2 mm — with the unwrap floor, 1.5 mm still at t 5 and 10 mm — and at the typical drift 3 mm from a thickness of 1.92 mm and 4 mm from 4.59 mm. The cap's angle and mismatch errors shrink with the cap. What (2c) cannot see: the size validity of the minima — IEC 60404-8-1:2023 §5.2 makes them valid only for magnets of at least 5 mm in all three directions («lower values … may be obtained» otherwise), so every thickness limit here, all under 5 mm, and every pole under 5 mm (P/2 at these caps) read them outside that validity, in the optimistic direction; the scale's own temperature (the hot end is the flange's); irreversible loss at the hot end (the strongest class has the lowest coercivity, a thin multipole scale works at a low permeance); the unwrap floor's basis, a season's outage over one growing month (our assumption, above). The family maxima and minima are the 2001/AMD1:2004 values the canon read; the 2015 and 2023 editions are unread past the 2023 preview, which says only that «new and high-performance grades of REFeB and RE₂Co₁₇ sintered magnets» were added — a REFeB class whose minimum reaches 1.426 ⊥ 1.503 T would bring the t 2 mm scale on 3 mm back, a class weaker than REFeB's minimum would bring the wall's thick REFeB cells back under the unwrap floor, and each cell's `need_T` is what any class is read against.

**(3) The energy of a read** rides the node's existing wake (cadence C): 3 two-channel samples (at the needed remanence; a weaker field raises the count as (B_needed/B)²) with the core awake throughout (a ceiling) cost **192.9 µJ** from VSTOR — **0.58 %** of E_CYCLE, 0.0348 µW on average against the node's 10.2 µW; the read is not what the power budget turns on. A 2 mm-period encoder IC at its power-up would cost 1.8–2.175 mJ (5.4–6.53 %).

**(4) The travel.** Measured from the flange's top — where a flange that meets canon's band above the bark (`01_04 §3.1`) puts the outer bark at install, at the latest — the bark climbs the radome's 18 mm to the dome's top in **3.6–22.5 years** at the fastest ⊥ slowest radial rate the desk names: inside the twenty-year life at every rate above 0.9 mm/yr. With the cathode flange CEM's placeholder thickness (3.0 mm) the faced seat's deep edge already stands 2.175 mm above the flange's top at install (`78`'s facing spread) — the defect `00_07` HW.8.10 tracks (the flange must grow to the facing depth), not a property of the travel. The live bark under the probe reaches the flange seat in 1.7–10.4 years on the thin contact (4.2–26.2 on the thick side). So the travel problem of `01_04 §5.5` arrives inside the life at almost every rate the desk names; whether a scale and a probe can travel 16–100 mm past a flush capsule without a visit, this instrument does not say.

**What it cannot see.** Where the anchor is held (an axis of named points; a hold shared between bearing, tie and bond is priced only as the bearing's share, and the bearing only with the anode bonded); the dead bark's, the phloem's and the callus's α (taken at the xylem's); the temperatures (uniform ΔT; the air is a proxy, not a bound; frozen wood's strain is not thermal expansion, so the seasonal figure uses unfrozen days only); the field beyond its idealisation (finite width, pole-pitch errors, a ferromagnetic neighbour) and the magnet itself; the sensor's mismatch drift per kelvin (its datasheet gives none — the cache prints a per-kelvin figure only under an assumed linear spread); the geometry of the travel; separating reversible shrinkage from growth (the zero-growth method's job); and the instrument's whole budget — (1) and (2) each print against the frames' 0.3 µm/K alone, never as one sum, because the support's term is a maximum over unknown fixations and the sensor's offset term a design target.

**Controls.** Each says in the script what it can and cannot catch: the loop's closure with one α everywhere, unit impulses against independently derived node positions, the sections against `103`'s lengths and anode centroid, the field's optimum P* = 2πg for a thick scale and its needed-B_r by a second route, the thickness and the cap (a thicker scale needs strictly less B_r at a P* that grows toward 2πg; the field needed at the cap equals the linear range), the energy function against lib's E_CYCLE, the ERA5 hour count against `110`'s, the monotone support that makes each crossing unique, and (2c)'s: `81`'s edge and the coldest air on one hour, the window closing at the thermal cap, each corner input moved alone never lowering a need, every root returning its family's maximum, and every grid cell's «holds» against its solved limit and against a brute-force search over the period in both directions.

## HW.54 — Do Snow, Hoarfrost and the Gateway's Bearing Leave a PV Cell on the Dome Any Winter? (script 115)

**The question (2026-10-31, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(б), «сніг, іній і азимут, заданий шлюзом, а не сонцем»).** `110` gives the effective aperture A_eff below which a PV cell on the dome cannot carry the node through the worst winter of 1991–2020, with the face always clear and on four fixed faces. Two things it does not see: a covered face (hoarfrost, plastered snow) passes little or no light while the store drains, and the face's azimuth is not ours to choose — the ratified mounting rule turns the flange towards its own gateway, within ±50° of the gateway's bearing (`01_04 §3.1`, ⚖️ 2026-10-22). `115` re-runs `110`'s own machinery (fields, lanes, harvest arm, bisection — imported) on covered fields at cadence C on its three corners, on all eight faces of `79`'s 45° grid and the closed stand (numbers — `cache/kinetics/pv_face_snow_frost_azimuth.json`).

**Four readings of the cover — two named by how they are built, two by where they land, and where they land is measured below.** **Ceiling** — the face as cold as the model allows, cleared by the melt rule (no light absorbed, a clear sky every hour, still air; frost every hour below the frost point and 0 °C; plastered snow on any ≥ 2 mm rise in either reanalysis at ≤ +1 °C; a cover clears only above 0 °C). **Melt only** — a dark cell's values (α 0.9, `79`'s cloud-weighted sky, the trunk's wind k·u10 with k 0.1); snow only on ERA5-Land rises ≥ 1 cm/h (NREL's threshold for a new cover) of WET snow, −1 … +1 °C — our assumption that dry snow does not plaster a vertical face, which only removes events; the ceiling's clearing rule kept. **Vapour budget + NREL slide** (cache key `nrel_published`) — the same air, sky and wet-snow events; frost as a vapour budget on the covered face's temperature (α 0.3, also while the face is bare; deposited and sublimated at the Chilton–Colburn rate, melted above 0 °C, the face blind past 0.05 kg/m²); snow sliding off at Marion et al. 2013's rate (through pvlib `coverage_nrel`, v0.11.2 source read, at sin 90° = 1) in every hour the air is warmer than −G/80, no melt added. NREL's are the new-cover threshold (1 cm/h), the slide rate and its −G/80 condition; ours are applying that threshold to an ERA5-Land depth rise, the wet filter, the frost model, its thresholds and its α. **Favourable end** — the vapour budget + NREL slide run on the bare dark cell's temperature (α 0.9), so its frost deposits less as well as melting, and every cover clears in any hour that cell would be above 0 °C: the end most favourable to PV, never a central estimate. 🔴 **Their order is measured, not declared** (`readings_order_for_pv`, on 54 thresholds within the scan's top of 100 cm² — two «none up to the top» agree, 22 cells are that on every reading): **ceiling ≥ vapour budget + NREL slide ≥ melt only ≥ favourable end**, no pair crossing — the vapour budget is never the kinder of the two middle readings and is strictly the harsher in 14 cells, while «ceiling ≥ vapour budget» rests on 2 cells. Melt only is the harsher on frost, the vapour budget on snow: its longest snow run is at least 14.3 days on every face and ground end, melt only's at most 5.8.

**Result — the necessary A_eff at cadence C, cm², ρ low ⊥ high, by face** (— = no aperture up to 100 cm² keeps the store from emptying; five of the nine fields shown):

*Favourable corner:*

| reading | closed stand | N | E | S | W |
|---|---|---|---|---|---|
| clear face (`110`) | 0.00774 ⊥ 0.00623 | 0.00877 ⊥ 0.00739 | 0.00737 ⊥ 0.00598 | 0.00568 ⊥ 0.00427 | 0.00748 ⊥ 0.00589 |
| favourable end | 0.00774 ⊥ 0.00623 | 0.00881 ⊥ 0.00741 | 0.00737 ⊥ 0.00598 | 0.00568 ⊥ 0.00427 | 0.00748 ⊥ 0.00589 |
| melt only | — ⊥ 0.0113 | — ⊥ — | — ⊥ 0.00598 | 0.00575 ⊥ 0.00429 | — ⊥ 0.00589 |
| vapour budget + NREL slide | — ⊥ — | — ⊥ — | — ⊥ — | — ⊥ 0.00784 | — ⊥ — |
| ceiling | — ⊥ — | — ⊥ — | — ⊥ — | — ⊥ — | — ⊥ — |

*Nominal corner:*

| reading | closed stand | N | E | S | W |
|---|---|---|---|---|---|
| clear face (`110`) | 0.0127 ⊥ 0.0106 | 0.0135 ⊥ 0.0124 | 0.012 ⊥ 0.0109 | 0.01 ⊥ 0.00872 | 0.0122 ⊥ 0.0106 |
| favourable end | — ⊥ 0.0106 | — ⊥ 0.0126 | 0.012 ⊥ 0.0109 | 0.01 ⊥ 0.00872 | 0.0122 ⊥ 0.0106 |
| melt only | — ⊥ — | — ⊥ — | — ⊥ — | 0.0127 ⊥ 0.00872 | — ⊥ — |
| vapour budget + NREL slide | — ⊥ — | — ⊥ — | — ⊥ — | — ⊥ — | — ⊥ — |
| ceiling | — ⊥ — | — ⊥ — | — ⊥ — | — ⊥ — | — ⊥ — |

Counted over all nine fields × two ground ends (18): the ceiling keeps a threshold in 0 and 0 at the favourable and the nominal corner, the vapour budget + NREL slide in 2 and 0, melt only in 9 and 5, the favourable end in 18 and 14; at the **adverse** corner (`110`'s window carries cadence C 0.93 days without light) no reading keeps any. Face by face: the vapour budget + NREL slide keeps only the open south and south-east faces on bright ground at the favourable corner, at ≈ ×1.8 their clear-face value; melt only keeps the south and south-west faces at both corners on both grounds (the south at ×1.0–1.27 its clear-face value), the south-east everywhere but the nominal corner on dark ground, east, west and the closed stand only on bright ground at the favourable corner, and the north, north-east and north-west never; the favourable end keeps every face at the favourable corner within 0.5 % of the clear one and, at the nominal corner, loses the closed stand, north, north-east and north-west on dark ground.

**The gateway's bearing.** On the clear face the worst bearing a gateway can impose costs ×1.535 ⊥ ×1.719 the south face at the favourable corner, ×1.34 ⊥ ×1.422 at the nominal one and nothing at the adverse one (the window there is a 41-hour overcast, the same for every face — `110`). Under a cover the bearing decides whether a node has any face at all within its ±50° window (`azimuth[…].bearings_with_none_up_to_cm2`): under melt only a gateway due north leaves none at either corner on either ground, north-east and north-west none on dark ground at both corners and on bright at the nominal one, east none on dark ground at the nominal one; under the vapour budget + NREL slide, at the one corner it keeps (bright ground, favourable), bearings N, NE, W and NW leave none; and the favourable end leaves a gateway due north none on dark ground at the nominal corner.

**What binds — the longest covered run per winter, days, median ⊥ maximum over 29 winters (longest snow-only ⊥ frost-only run, maximum), ρ low:**

| reading | S face | N face | closed stand |
|---|---|---|---|
| ceiling | 52.5 ⊥ 116.1 (115.1 ⊥ 116.1) | 52.5 ⊥ 116.1 (115.1 ⊥ 116.1) | 52.5 ⊥ 116.1 (115.1 ⊥ 116.1) |
| vapour budget + NREL slide | 2.9 ⊥ 14.4 (14.4 ⊥ 2.7) | 4.9 ⊥ 15.0 (15.0 ⊥ 7.7) | 4.9 ⊥ 14.4 (14.4 ⊥ 7.3) |
| melt only | 1.6 ⊥ 2.9 (1.2 ⊥ 2.9) | 7.5 ⊥ 20.5 (5.8 ⊥ 20.5) | 3.5 ⊥ 20.5 (3.8 ⊥ 20.5) |
| favourable end | 0.5 ⊥ 1.2 (1.2 ⊥ 0.7) | 0.8 ⊥ 5.8 (5.8 ⊥ 3.7) | 0.6 ⊥ 3.8 (3.8 ⊥ 0.7) |

against `110`'s autonomy without light at cadence C: 7.57 · 3.27 · 0.93 days (favourable · nominal · adverse). Under the vapour budget + NREL slide the snow runs reach two weeks on every face; under melt only the frost runs reach ≈ 20 days on dark ground on the north, north-east and north-west faces and the closed stand. A run shorter than the autonomy is necessary, not sufficient, which is why the thresholds above are re-run rather than read off the runs.

**So, Р3(б)'s answer on snow and frost.** Snow and frost decide PV on the dome at the adverse corner on every reading, and on the three harsher readings they remove at least half of the face-ends at the other two corners; only the favourable end leaves the clear-face picture nearly intact, and only at the favourable corner (within 0.5 %) — at the nominal one it too loses 4 of 18 face-ends and leaves a gateway due north no face on dark ground. What decides between the readings is how a cover leaves a SMALL VERTICAL face 30 mm across — whether dry snow plasters it (three readings assume not) and whether NREL's slide rate, taken at sin 90° = 1, holds on it; neither is known. The arbiter is a winter field test of a cell on a dome (a camera and its short-circuit current), or more cheaply the `stem_face_winter_light` loggers' own record of cover episodes on their face — a proposal, not a decision. ⊕ 2026-11-01: the founder took the cheaper arbiter (⚖️, by recommendation — `01_03 §4` ⚖️ «Польова відповідь Р3(б)»): a machine reading of the cover episodes from the loggers' own record (sheet §6 ⊕), with no added visits; the dome field test (fuller, costlier) was not taken. Weakest link: the logger face is not the dome (other form and material), and a light dip does not name its cause (frost ⊥ snow ⊥ shade). Found the same day, after the ruling and not part of it: the horizontal reference is covered more often than the face, so its covered days drop out exactly when dry snow is judged, biased toward PV; the analysis (an author's choice, not the ruling) picks candidate days without the reference and judges the face against ERA5 directly (⊕ 2026-11-09: there is no horizontal reference any more — every day is judged against ERA5, so the censoring by a covered reference is gone, while the deep-dip limit stays) — which catches only a deep dip, so the reading is a LOWER bound on cover: it can refute winter PV, not confirm it. Told of this, the founder kept the loggers the same day (⚖️, by recommendation): if they show no deep episodes, the dome camera returns as a question then.

**What it cannot see.** Rime from supercooled fog (no fog or liquid-water variable in the record); the face's heat capacity and the window's conduction to and from the capsule (not one sign); wind direction for plastered snow; the ground's half of the view held at the air's temperature (snow is colder); azimuths between the 45° grid; a frost layer's partial transmission beyond the one threshold; whether dry snow plasters a small vertical face and whether NREL's slide rate transfers to it; crossings of the readings above the scan's top; the cell, the window and the efficiency (`110`'s A_eff carries them); and the radio's cost of turning the face up to 45° off its gateway, which is the mounting rule's to price.

**Controls.** Each says in the script what it can and cannot catch: uncovered, every row `110` holds for cadence C lies inside `115`'s own bracket (all 30); the sky term's sign (the cloud-weighted sky never colder than the clear one, full cloud radiating at the air's temperature); the clearing rules on synthetic records (a warm hour, NREL's slide sign at G = 100 W/m², a full cover gone in ⌈1/0.197⌉ hours, a snowfall in a warm hour leaving none); the azimuth window against an angular-distance minimum; and the measured order, which refuses to draw a line through a crossing pair (its cell-by-cell check is a test).

## HW.54 — Can the Stem-Face Cover Rules Judge a Winter at All? (script 117)

**The question (2026-11-10, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(б)(4)).** The rules the stem-face light logger will be read by ([`stem_face_winter_light`](../stem_face_winter_light.md) §6) are written before the data, so they cannot be tuned to the season afterwards. An adversary found that, as written, the candidate days (a snow event or a frost night, plus the three days after) take most of the season, so the base R — a median over the non-candidate days of the same ground state and diffuse-light tercile within ±15 days — has nothing to stand on. `117` rehearses the rules' first four steps on the ERA5 record the season will be read against — December–February of 29 full winters (1991/92 … 2019/20), with ERA5's 2 m RH standing in for the logger's own — and counts the days a version of the rules can JUDGE: a day with ΣGHI ≥ 0.1 kWh/m² and a base of at least 5 non-candidate days.

**The rules as written** make **82.77 %** of the season candidate from frost alone and **89.65 %** with snow, judge **2.6 %** of the days, and judge none in **23** winters of 29 — the adversary's measurement, reproduced (control 1). **A first rewrite the same day** — a two-branch frost rule on the morning's day only, snow on its day and the next, a base over the whole season by ground state and a fixed diffuse class with a fallback to the ground state alone — cut the candidates to **44.92 %** and judged every day of the median winter, and its adversary still rejected it: on a perfect logger with no cover the fallback days manufactured dips, the episode count did not move with cover (the ceiling, covering most of a winter, makes the fewest episodes because its cover runs together), and the frost rule missed most onset nights of `115`'s own melt-only frost. So judgeability is a necessary property, not an acceptance test: the next rewrite is judged by a perfect-logger rehearsal — the modelled face under each `115` reading's cover and under none — which `117` does not run (the requirements — the leg in `00_07` HW.54).

**Two facts no rewrite changes.** CERRA, the second source of `115`'s ceiling event, ends at this grid point at 2021-06-30T23:00 UTC (probed 2026-11-10), so the season's snow events stand on ERA5-Land alone — whose «≥ 2 mm» is «≥ 1 cm» on its 1 cm grid (control 2); in 1991–2020 CERRA's ≥ 2 mm rises added a median of **14** event days a winter to ERA5-Land's (part of them its forecast-cycle seam at local 10:00, `115`). And an adverse R for `110` — the face's light against GHI in overcast hours (diffuse share ≥ 0.9, GHI ≥ 20 W/m²) on bare ground — has at most a median of **40** such hours a winter, before any candidate or episode day is excluded; **13** winters of 29 offer fewer than 30 and **6** offer none, so in about every second winter the measurement cannot give an adverse R on any rule that needs a few dozen bare overcast hours. The same bound with intermediate ground (median **215** hours) is biased up by the light snow reflects. ERA5-Land overstates snow cover (its own note, the data README), so the yard may have more bare days than the cell.

**What it cannot see.** The logger: R itself, its dips, the false-dip rate — the rehearsal counts what rules can judge, not what they will find, and not whether they discriminate; ERA5's open-cell 2 m RH for the logger's by a trunk under a crown; a cell, not the yard; the season's clock (the committed files run on one fixed UTC+3; a query's offset is the zone's at the moment of the query, measured 2026-11-10 — the sheet's §5).

**Controls.** Each says in the script what it can and cannot catch: the rules as written reproduce the adversary's three numbers within 5 points; ERA5-Land's rises are whole centimetres; the draft's candidates are a subset of the written ones; GHI is `110`'s `irradiance`, recomputed hour by hour.

## HW.54 — How Often Can One Season of One Logger Tell the Cover Readings Apart? (script 118)

**The question (2026-11-11, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(б)(4)).** Two rewrites of the stem-face sheet's cover rules failed their adversaries, the second holding on one noise seed. Before a third is tuned, `118` measures what the truth offers to be found: on a PERFECT logger — no noise, no crown, the base known exactly, the true cover known hour by hour — in how many winters does the true reading leave at least two episodes (the sheet's p.5/p.6, no candidate restriction) that another reading does not cover? The face, the four `115` readings and the season's record (CERRA held flat) come through `115`'s `cover_readings`. ⚠️ **A measured power per test, not a ceiling on every rule:** a first version of this section called one test a ceiling, and its adversary showed that a stricter coverage test and episodes without the 0.8 merge reject more often on the same logger — coverage on «any day of the episode» weakens as episodes grow — and that the clearing decision, not modelled here, is a further channel. The three readings of the coverage test (the leg's requirement (2)) are measured side by side: **lenient** — the reading covers none of the episode's judged days; **strict** — it leaves at least one of the episode's dip days uncovered; **runs** — the lenient test on episodes that are runs of dip days only. Beside them, the sheet's p.7 as written — a **count test**: the record shows at least two more episodes than the reading gives.

**Winters of 29 (the 1992–2020 seasons) in which the reading on the right is rejectable** — the same at both reflection ends unless given as low / high:

| truth → reading | ≥ 2 misses: lenient · strict · runs | ≥ 1 miss (lenient) | count test |
|---|---|---|---|
| ceiling → melt only | **20** · **26** · **23** | 26 | 17 / 19 |
| ceiling → NREL published | **16** · **26** · **22 / 23** | 27 | 15 |
| ceiling → favourable end | **25** · **26** · **25** | 29 | 25 |
| melt only → NREL published | **10 / 5** under all three | 15 / 13 | 3 / 4 |
| melt only → favourable end | **11 / 5** under all three | 16 / 14 | 11 / 5 |
| NREL published → melt only | **11 / 10** · **14 / 12** · **11 / 10** | 26 / 24 | 6 / 7 |
| NREL published → favourable end | **13 / 11** · **14 / 12** · **13 / 11** | 27 / 25 | 13 / 11 |
| melt only → ceiling | 0 under all three | 0 | **2 / 1** |
| NREL published → ceiling | 0 under all three | 0 | **0 / 1** |

The favourable end is covered by every other reading hour by hour (as melt only is by the ceiling), so under it no coverage test can reject anything — a lower-bound reading of the record cannot reject a reading that covers MORE (the sheet's p.7); the count test is 0 there only because that truth has almost no episodes. **The count test breaks that rule in the last two rows:** a longer cover merges into fewer episodes, so it «rejects» the ceiling — which covers more light overall — in 1–2 winters under a melt-only truth and in 0–1 under an NREL truth: an artefact of counting, and the reason the leg's requirement (2) replaces the count by coverage.

**The base the record offers — and why it splits the answer.** All of the above grants an exact base. The sheet's p.4 estimates it from the record's own cover-free days (≥ 5 needed). Under a ceiling-like truth the face is covered almost all winter: a median of **4** judged days per winter are free of cover (share ≥ 0.8), **16** winters of 29 have fewer than 5, and cover alone lowers the face's mean daily transmitted share over the judged days to a winter median of **0.066** — so a base from the record fails exactly there, and the power in the table is not reachable by the episode rules (an estimated base costs missed detections, not only false rejections). Under the middle and favourable truths a median of 83–90 judged days per winter are cover-free and the share is 0.96–1.0, so a base exists.

**What it means (the machine's reading).** The two halves of the question fall to different rules. A ceiling-like truth lowers the measured R itself about fifteenfold, but the episode rules cannot reach that case, because the record holds no base for it; what can judge such a season is only the R threshold (the sheet's §6 third bullet — a `[вибір]`, a necessary condition: «below — does not hold»), and only where the measured R lands below the threshold of the reading chosen; where it does not, the season says nothing on either rule, and the ratified answer — the camera question returns, with the data — is what remains. The middle truths leave a base, and there one season shows the lighter readings in 5–14 winters of 29 under every test, so «not judged» is the likely outcome; under the favourable end nothing is rejectable, which is the reading's own lower-bound limit, not a failure. The threshold of two episodes keeps 36–69 % of the one-miss winters under the middle truths (lenient). **Depth decides the next design step:** under the ceiling and melt-only truths at least 87 % of the lenient misses, each counted by its deepest day, are covered to a transmitted share below 0.05 — a dip threshold far deeper than 0.5 would keep them while making noise and base-error dips all but impossible — but under the NREL-published truth more than half of them sit above 0.2, so a deeper threshold buys robustness at the price of that truth's power. Noise on a perfect base (independent per day, lenient test) moves no ceiling-truth count from σ 0 to 0.4, the NREL-truth counts by about one winter at two misses and by under two at one miss.

**What it cannot see.** The estimated base — both its sides: the missed detections where the record has too few cover-free days, and the false rejections where noise and base error make a TRUE reading look as if it misses — the stage that must come next, judged over seeds, timing shifts and σ to its cliff; noise splitting or merging episodes; the decisions other than coverage and count (dry snow, clearing); and everything a perfect logger is perfect at (the yard against the cell, a crown, sensor errors, the clock, fog and rime, a house's shadow). A test with high power here is necessary for the field question to be answerable through it, never sufficient.

**Controls.** The south face's light-lost shares equal `115`'s cache at both ends; GHI is `110`'s `irradiance`; the episode functions pass a synthetic winter, merged and runs; and wherever a reading covers every hour the truth covers, it misses nothing under all three readings — asserted on 232 pair-end-winter cells, of which only 38 hold a truth episode (the rest cannot fail).

## HW.54 — What Does a Second Sky Do to the Stem-Face Logger's Rules? (script 124)

**The question (2026-11-14, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(б)(4), stage 1 — the estimated base, from both sides).** Since 2026-11-09 the logger has no on-site reference: R is the face's daily light over ERA5's GHI of that day, and the verdict that set it named the price — a noisier daily R, the cell not being the yard ([`01_03 §4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)). No rehearsal of the cover rules so far could see the sky's error or the air's: `117` computes no R (it counts the days the rules can judge), and `118` grants an exact base on an ERA5-lit face, with the truth and the readings on one air. `124` puts both in as named readings. **The sky** that lights the south face is ERA5 + α · (product − ERA5), the product being the CERES SYN1deg direct-normal and diffuse fluxes NASA POWER serves hourly (2001–2020): α 1 is the product itself, α 0 ERA5, and α 1/√2 scales the difference to the standard deviation ERA5's own error would have if the two products erred independently and equally — it reproduces that variance only: a linear mix cannot take a day below 0.29 of its ERA5-lit light, so its column says nothing about dips at a threshold of 0.3 or deeper. **The air** the cover model runs on is ERA5's, or MERRA-2's 2 m temperature and humidity at the same point — **2.22** K colder on average over the seasons' winter hours. MERRA-2's humidity column is a «Dew/Frost Point» whose meaning below 0 °C its header does not settle, and the cover model reads humidity through the frost point and the vapour density at the face, so the column is carried in both readings, as `120` and `122` carry it: as a dew point over water (the moister reading) and as a frost point below 0 °C. ERA5 stays the divisor in every world, the analyst lights its readings with ERA5 (the only sky it has), the base comes from the record itself (the sheet's p.4 without its candidate-day exclusion, leave-one-out), and nineteen full Dec–Feb seasons are read. The truth's cover (`115`'s `cover_readings`) runs on the world's face light and air, so the mismatch of timing between truth and analyst is the worlds', not a synthetic shift. ⚠️ **Readings, not bounds:** the sky product is itself computed, on a coarser cell, with an hourly uncertainty of its own (its accuracy summary — the data README); MERRA-2 is a cell too, and under a crown the nights may as well be warmer than ERA5's; the yard differs from all of them.

**The sky alone.** Over the 1712 judged DJF days the daily GHI of the two products differs by a standard deviation of **0.353** in the logarithm (a robust **0.305**). On the vertical south face the same disagreement is larger, because the face takes the beam nearly head-on and the base is drawn by ERA5's diffuse fraction: a day ERA5 calls clear and the product calls overcast lands several times below its base. The cover-free face's R over the record's own base scatters by **0.622** / **0.576** in the logarithm (low / high reflection end) under the product's sky, against **0.174** / **0.148** when the face is lit by ERA5 itself.

**A cover-free face, judged by the rules — false runs of dip days per winter** (under ERA5's own sky the same code gives none at any θ of the grid):

| dip threshold θ | product's sky (α 1): false runs per winter, mean (low / high) | α 1: winters of 19 with ≥ 2 false runs | α 1/√2: winters of 19 with ≥ 2 false runs |
|---|---|---|---|
| second sky θ 0.5 — the sheet's p.5 | **9.74** / **8.32** | **19** / **19** | **17** / **13** |
| second sky θ 0.3 | **2.42** / **2.05** | **13** / **10** | **1** / **0** |
| second sky θ 0.2 | **0.84** / **0.63** | **4** / **2** | **0** / **0** |
| second sky θ 0.15 | **0.21** / **0.11** | **1** / **0** | **0** / **0** |
| second sky θ 0.1 | **0.05** / **0.05** | **0** / **0** | **0** / **0** |

**Rejections under the product's sky, ERA5 air on both sides — winters of 19 in which the reading on the right is rejected** (at least two runs it does not cover within a day either side; low / high end). A row marked «false» is a rejection the record cannot truthfully make — the reading is the truth, or covers at least as much. The other rows are «not proven false»: the flag sits on the pair, not on the run, so at the shallow thresholds most of those rejections rest on sky-made dips where the lighter reading simply has no cover (the cover-free table above), not on cover the truth made:

| truth → reading | θ 0.5 · 0.2 · 0.15 · 0.1 (product's sky) | θ 0.5 under ERA5's own sky |
|---|---|---|
| 2S none → favourable end (false) | 19 / 19 · 4 / 2 · 1 / 0 · 0 / 0 | 0 / 0 |
| 2S melt only → melt only (false) | 19 / 19 · 7 / 5 · 3 / 1 · 2 / 0 | 0 / 0 |
| 2S melt only → NREL published | 19 / 19 · 8 / 5 · 3 / 2 · 1 / 0 | 5 / 3 |
| 2S melt only → favourable end | 19 / 19 · 11 / 9 · 6 / 4 · 4 / 1 | 7 / 4 |
| 2S NREL published → NREL published (false) | 19 / 19 · 4 / 3 · 1 / 0 · 0 / 0 | 0 / 0 |
| 2S NREL published → melt only | 19 / 19 · 11 / 8 · 6 / 5 · 4 / 4 | 5 / 5 |
| 2S NREL published → favourable end | 19 / 19 · 11 / 8 · 7 / 5 · 5 / 4 | 7 / 7 |
| 2S ceiling → favourable end | 5 / 5 at every θ of the grid | 5 / 5 |

**How a season ends, by world — θ 0.1, two runs, a day's tolerance; winters of 19 with a rejection not proven false · with a false one · with none** (low / high end; the first two can fall in the same winter):

| world (sky · the truth's air · the analyst's air) | melt-only truth | NREL-published truth |
|---|---|---|
| W1 ERA5 · ERA5 · ERA5 | 4 / 3 · 0 / 0 · 15 / 16 | 1 / 0 · 0 / 0 · 18 / 19 |
| W2 α 1/√2 · ERA5 · ERA5 | 3 / 1 · 0 / 0 · 16 / 18 | 3 / 2 · 0 / 0 · 16 / 17 |
| W3 product · ERA5 · ERA5 | 4 / 1 · 2 / 0 · 15 / 18 | 5 / 4 · 0 / 0 · 14 / 15 |
| W4 product · MERRA-2 dew · ERA5 | 14 / 9 · 10 / 7 · 5 / 10 | 7 / 6 · 3 / 2 · 12 / 13 |
| W5 product · MERRA-2 dew · the same | 14 / 10 · 4 / 0 · 5 / 9 | 7 / 5 · 1 / 1 · 12 / 14 |
| W6 ERA5 · MERRA-2 dew · the same | 14 / 10 · 0 / 0 · 5 / 9 | 6 / 4 · 0 / 0 · 13 / 15 |
| W7 product · MERRA-2 frost · the same | 8 / 4 · 4 / 0 · 11 / 15 | 1 / 1 · 0 / 0 · 18 / 18 |
| W8 ERA5 · MERRA-2 frost · the same | 8 / 7 · 0 / 0 · 11 / 12 | 0 / 1 · 0 / 0 · 19 / 18 |

«MERRA-2 dew» and «MERRA-2 frost» are the two readings of its humidity column; «the same» gives the analyst the truth's air hour for hour; W2's zeros of false rejections at this threshold are its construction's (the floor of the linear mix). A rejection «not proven false» is in every such winter a rejection of the favourable end, and in most of them of the other middle reading too. Under the favourable-end truth and under no cover nothing is rejected in any world at θ 0.1 (two runs); under the ceiling truth a rejection comes in only 3–5 winters of 19 in every world — the record offers no base there (a median of no based day per winter).

**What the worlds run here show.** (1) The sheet's dip threshold of 0.5 cannot be used against ERA5: under the product's sky a face with no cover at all shows an average of eight to ten runs of dips a winter, at least four in every one, and under every truth but the ceiling every reading lighter than the ceiling is «rejected» (two runs) in all nineteen; scaled to α 1/√2 a cover-free face still shows two or more runs in 13–17 winters. (2) On a cover-free face under the product's sky the winters with two or more false runs end between θ 0.15 and θ 0.1 at the low reflection end and between θ 0.2 and θ 0.15 at the high one; a single false run survives to θ 0.1 in one winter of nineteen at either end. False two-run rejections of a TRUE reading under itself do not end on the grid: under the product's sky on ERA5's air (W3) the melt-only truth is still rejected under itself in 2 / 0 winters at θ 0.1 and at θ 0.05. The α 1/√2 column cannot answer either question (its floor). (3) In the one world run with an analyst on another air than the truth's (W4: the product's sky, the truth on MERRA-2's air with its humidity read as a dew point, the analyst on ERA5's — the sheet's p.7 as written) the true melt-only reading is rejected under itself in **7**–**10** winters (W4), against **0**–**4** with the truth's own air (W5), at θ 0.1 and two runs. W5 is a ceiling, not a sensor: it grants the analyst the truth's air exactly. An exact sky with a wrong air, and an analyst who reads the humidity column otherwise than the truth, were not run. (4) The dip threshold and the «covered» threshold coincide at 0.5: with ONE run at θ 0.5 even the ERA5-lit, ERA5-air world rejects falsely (in up to **5** winters) — consistent with a base error at the shared threshold; one run is clean there from θ 0.3 down, and at θ 0.3 it rejects in **9** / **7** winters under the melt-only truth and in **12** / **12** under the NREL one, while under the product's sky on ERA5's air (W3) one run at θ 0.1 still brings a false rejection in **8** / **5** winters under the melt-only truth and in **3** / **3** under the NREL one — more in the other product-sky worlds. (5) The dip rules do not enter the seasonal R of the measured season, which multiplies back by the same ERA5 GHI it was divided by; whether that R carries to the record's worst stretch under a second sky was not run (the per-winter ratio — below).

**What moves with inputs nobody has measured — the bracket, not a conclusion.** How often one season rejects a lighter reading (θ 0.1, two runs; the «not proven false» column above) under a melt-only truth: 4 / 3 and 4 / 1 winters of 19 on ERA5's air (W1, W3), 14 / 10 on MERRA-2's air with its humidity read as a dew point (W5, W6), 8 / 4 and 8 / 7 with the same column read as a frost point (W7, W8). Under an NREL truth: 1 / 0 to 5 / 4 on ERA5's air, 7 / 5 and 6 / 4 on the dew-point reading, 1 / 1 and 0 / 1 on the frost-point one. The reading of the humidity column alone moves the count from 8 / 7 to 14 / 10 under a melt-only truth and from 0 / 1 to 6 / 4 under an NREL one (W8 → W6); the temperature alone was not moved in any world. On ERA5's air the sky alone moves the NREL count by four winters (W1 → W3), about as far as the dew-point air does under ERA5's sky (W1 → W6); on MERRA-2's air it moves it by at most one (W6 → W5, W8 → W7). Only the colder sign was run: MERRA-2 is a cell too, and a yard under a crown beside a house may as well be warmer than ERA5's. So «nothing rejected» is the end of **14**–**19** winters of 19 in the worlds on ERA5's air (W1–W3, any truth) and of **5**–**9** under a melt-only truth on the dew-point reading (W5, W6) — whether it is the likely end of THIS season cannot be said from here, and under the ratified answer of 2026-11-01 that is the outcome that returns the camera question.

**What follows for the rules (inputs to the rewrite, not rules).** The dip threshold against ERA5 has to be deep, and the depth that suffices depends on how the two products' disagreement is split. Whether the readings gain from the logger's own air is open: W4 against W5 prices a wrong air against an EXACT one; the MX2309 records temperature and humidity beside the face, and how close that is to the air that drives the cover is not modelled here. An on-site reference: at a fixed θ 0.1 an exact sky moves the two-run counts of the two middle truths by no more than **4** winters (W1 against W3, W6 against W5, W8 against W7) — the not-proven-false count falls in 5 of the 12 cells and rises in 2 — and every false two-run rejection at θ 0.1 goes to zero under it; with it θ 0.5 carries no false two-run rejection in W1, W6 and W8. An exact sky with an analyst on the wrong air was not run; and a real horizontal reference is less than these worlds grant, since it knows the global flux only and is covered by the same snow.

**The rule of two airs (added 2026-11-14 for the rewrite of the sheet's pp. 3–7; its second version, after its adversary).** The season's analyst will hold two airs — ERA5's and the logger's own — so three rules are scored on the same records at θ 0.1 and 0.15, tol 1, k 2: reject a reading on ERA5's air alone, on the logger's alone, or only when BOTH reject; 1440 cells. The truth's air runs over ERA5's, MERRA-2's in both readings of its humidity column, and ERA5's warmed by 1 and 2 K; the logger's air is the truth's air with a sensor error on three axes — a constant offset on temperature and dew point alike (−1 … +1 K; it keeps the humidity exact), an offset on the dew point alone (−2 · −1 · +1 K), and MERRA-2's humidity column read the other way. Every axis grants that the air at the logger IS the air that drives the cover, and no cell has both airs away from it. «Both» is an intersection: per reading it never rejects in more winters than either single rule (asserted on every cell). What that buys depends on the axis — the true reading rejected under itself, worst cell at θ 0.1, on ERA5's air alone · the logger's alone · both: an offset on temperature and dew point alike **11 · 4 · 4**; on the dew point alone **11 · 13 · 10**; the other humidity reading **11 · 11 · 10**. Against an error that keeps the humidity the rule takes the self-rejections down to the logger's own level; against a dry humidity error of 2 K, or the column read the other way, it buys next to nothing: with «melt only» true on the colder air under the product's sky (low albedo end) «both» rejects it in 4 winters of 19 with no error, 7 with the dew point 1 K low, 10 with 2 K low and 10 on the other reading — against 10 on ERA5's air alone. What it costs: of the 1008 pairs of a cell and a reading not proven false at θ 0.1, «both» rejects in fewer winters than the stronger single rule in 220 and than the weaker in 33. What is left with no sensor error is not the sky's: the truth's own runs missed on both airs («melt only», the product's sky, low end) are 10–14 runs (10–16 days) per truth air; on 9–14 of those days the truth's cover takes over half the light and on none is the face free of it, while the product's sky is under half of ERA5's on 3–5 — runs of the truth's own cover that a reading lit by ERA5's sun does not place within a day. A yard warmed by 1–2 K: a true reading is rejected under itself in at most 1 · 2 · 1 winters at θ 0.1 (2 · 3 · 2 at 0.15), and on the warmed airs the readings' nesting no longer holds («NREL» inside the ceiling fails; recorded in the cache). A cover-free face is rejected in 0 winters at θ 0.1 under any rule, sky and error, at 0.15 in at most 1. ⚠️ For the rewrite: «both» is safe to adopt — it only removes rejections — but its gain is not a number to promise before the logger's humidity error is known, and «not proven false» remains an upper count of power.

**The seasonal R between the two skies.** The cover-free face's winter light under the product's sky over that under ERA5's — which is the ratio of the two seasonal R, the divisor being the same — has a median of **1.134** over the nineteen winters, from **1.007** to **1.360** (low end; high: **1.122**, **1.005**–**1.332**), while the GHI ratio itself stays within 0.91–1.15: the products split the same global flux differently into beam and diffuse (beam share of the face's winter light 0.67 under ERA5, 0.71 under the product). A measured R could therefore differ from the R the ERA5-lit model expects by a term of up to that order before any crown, of a sign not measured here — small beside the ×8–×13 between the adverse and the other readings of `110`, not small between its nominal and favourable ones (≈ ×1.6).

**What it cannot see.** The yard against any of the cells; how the two products' disagreement is split between them (and a split that gives whole days to one product or the other, which a linear mix cannot make); a warmer air and a sensor's error beyond the constant shifts of the two-air block; an analyst's air that differs from the truth's by the distance between the logger and the face; cosine and spectral errors, the logger's clock; a second wind and a second long-wave sky (the air axis swaps the 2 m temperature and humidity only); fog and rime; the hybrid reading; the decisions other than coverage (dry snow, clearing); a real on-site reference; a base other than the sheet's median, a coverage test other than runs with a day's tolerance, hourly signatures; and nineteen winters are one realisation of each mismatch, split odd ⊥ even in the cache but not resampled — «0 of 19» is compatible with a true rate of some 15 %.

**Controls.** The correlation of the two GHI series peaks at the applied one-row lag (0.955, against 0.905 and 0.896 beside it); the product's DNI · cos z + diffuse closes on its own global flux under this script's sun (median 0.994); in the ERA5-lit world the cover-free judged days per winter and truth equal `118`'s cached counts for the same seasons (152 cells) — and one code path builds every world's face from α, with the α 0 and α 1 ends bit for bit the two products; the run, base, tercile and miss functions return hand-computed answers on synthetic seasons (both windows of the base, the dark-pool and too-few-days branches); the second air correlates with ERA5's at 0.989 hour by hour.

## HW.54 — How Much Winter Light Reaches the Logger's Face in a Courtyard? (script 125)

**The question (2026-11-14, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, leg Р3(б)(4)).** The verdict that put one logger on the south face named its weakest link — a house in the southern sector shades exactly that face, and then the question returns to the founder ([`01_03 §4`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md)). The founder gave the yard twice: by word and a phone compass (open toward a true heading of 210°, «about 150°–270°», a two-storey building «about 7 m» away on the other three sides, the roof edge «about 7 m» up), then by a satellite image of the court, north up. Read by eye off that image — pixels, scaled by the «7 m» taken as the mean of the three wall distances, the trunk taken under the crown's centre: the back wall faces about 215°; the tree stands 5.2 m from it, 8.5 m from the eastern wing and 7.3 m from the western one; the opening seen from the tree is about 167°–256°, narrower than the words' 150°–270°; and beyond the opening stand trees some 10–20 m away. Those inputs put the eastern wing's end **7.7** m in front of the tree and the western one's **8.4** m, and make the wings 12.9 and 13.6 m long from the back wall — nearly equal, the one cross-check a plan read this way has inside itself. `125` takes the logger at the sheet's 1.3 m and sets the face's light in that yard against the same face standing open: the beam where the sun stands above whatever is on its bearing (a roof edge, or the opening's horizon), the diffuse flux through the face's view of the sky above that line (isotropic), and the ground-reflected light from what reaches the yard's ground — under ERA5's sky and under the CERES SYN1deg product's, over the nineteen winters both hold. ⚠️ **Not a bound in either direction.** The light the walls return is not added (it adds — the south face's view of the walls is 0.127 of its 0.5), and the base case leaves the opening's horizon EMPTY, the kind assumption.

**The roof line and the crowns against the winter sun.** Seen from the logger the roof edge stands **47.6**° up toward the back wall, **33.8**° on the eastern wall's normal, **38.0**° on the western one's and **26.5**° at the opening's eastern edge; the highest sun of the nineteen winters is **32.5**°. A crown line of trees 15–25 m tall standing 10–20 m away is at 34°–67° — at or above that sun.

**The building alone — an empty horizon in the opening; the share of the same face's open winter light** (low / high albedo end of `79`):

| face in the yard | beam kept | sky-diffuse kept | total kept, ERA5's sky | total kept, the product's sky | bracket (i) on «by eye» (total) |
|---|---|---|---|---|---|
| CY south face, 180° | **0.665** | **0.746** | **0.683** / **0.679** | **0.674** / **0.672** | **0.589**–**0.772** |
| CY face turned to the opening, 211.5° | **0.807** | **0.811** | **0.791** / **0.771** | **0.786** / **0.768** | **0.689**–**0.864** |

The beam column is ERA5's (the product's: 0.657 and 0.798). Each row is against the SAME face standing open, and an open face turned to 211.5° has less winter light than an open south face — so the two rows are not a comparison of the two orientations; that comparison is in the next part. By month the south face keeps 0.69 in December, 0.69 in January and 0.67 in February (ERA5, low end); the share of its open beam that comes from east of the opening is 0.32, 0.33 and 0.37. Three brackets on a plan read by eye, the south face's total: (i) the roof edge at 6 · 7 · 8 m, every distance times 0.85 · 1 · 1.15 and each edge of the opening 6° either way, 81 combinations — the table's last column; by axis, the roof edge alone 0.656–0.713, the scale alone 0.654–0.704, the two together 0.644–0.741, the eastern edge alone 0.630–0.728, the western edge alone 0.670–0.685 (the winter sun's westernmost bearing is 258°); (ii) the eastern edge alone, further out — the table below; (iii) the TRUNK moved in the fixed building, up to 2 m along and across the court, all three distances and both edges moving together: **0.536**–**0.799** (up to 1 m: 0.606–0.745) — lowest with the trunk 2 m nearer the eastern wing and the back wall (the opening then 181°–257°), highest 2 m the other way (153°–255°). Bracket (i) does not cover (iii): an image off nadir displaces a 25 m crown by metres against the roof edges.

| the opening's eastern edge | south face, beam kept (ERA5) | south face, total kept |
|---|---|---|
| EE 150° — the words' edge | **0.826** | **0.804**–**0.816** |
| EE 155° | **0.779** | **0.767**–**0.777** |
| EE 161° | **0.720** | **0.718**–**0.728** |
| EE 167° — the image's edge | **0.665** | **0.672**–**0.683** |
| EE 173° | **0.614** | **0.630**–**0.640** |
| EE 180° | **0.566** | **0.588**–**0.600** |
| EE 190° | **0.530** | **0.552**–**0.567** |

**What stands in the opening — a level opaque horizon inside it** (lowest–highest of both skies and both ends; the base plan). The third column is the building's share GIVEN that horizon: the yard with the building over the same horizon without it — what a measured R would have to be divided by to take the building out.

| horizon in the opening | south face, total kept (of the open face) | the building's share given that horizon | … of the sky-diffuse light alone | face turned to the opening over the south face |
|---|---|---|---|---|
| HZ 0° (the base case) | **0.672**–**0.683** | **0.672**–**0.683** | **0.746** | **1.042**–**1.051** |
| HZ 5° | **0.651**–**0.656** | **0.665**–**0.674** | **0.727** | **1.033**–**1.038** |
| HZ 10° | **0.604**–**0.614** | **0.650**–**0.658** | **0.707** | **1.013**–**1.016** |
| HZ 15° | **0.515**–**0.541** | **0.613**–**0.628** | **0.684** | **0.983**–**0.988** |
| HZ 20° | **0.314**–**0.367** | **0.491**–**0.534** | **0.658** | **0.984**–**0.988** |
| HZ 25° | **0.208**–**0.264** | **0.390**–**0.452** | **0.630** | **0.975**–**0.982** |
| HZ 30° | **0.134**–**0.188** | **0.291**–**0.370** | **0.600** | **0.973**–**0.982** |
| HZ 35° | **0.106**–**0.157** | **0.246**–**0.329** | **0.568** | **0.971**–**0.981** |
| HZ 45° | **0.088**–**0.135** | **0.213**–**0.297** | **0.502** | **0.934**–**0.958** |
| HZ 60° | **0.070**–**0.111** | **0.177**–**0.258** | **0.417** | **0.881**–**0.925** |

A level horizon moves both faces alike, so its last column cannot say whether to turn the logger. A screen in ONE half of the opening can:

| a screen inside the opening | face turned to the opening over the south face | south face, total kept |
|---|---|---|
| SC eastern half, 40° | **1.174**–**1.220** | **0.255**–**0.294** |
| SC western half, 40° | **0.943**–**0.953** | **0.516**–**0.531** |
| SC eastern half, 20° | **1.082**–**1.099** | **0.438**–**0.479** |
| SC western half, 20° | **0.971**–**0.976** | **0.550**–**0.567** |

With an empty horizon the turned face receives **1.051** / **1.044** of the south face's light under ERA5's sky and **1.048** / **1.042** under the product's; across bracket (i), **1.011**–**1.081**.

**What it means (the machine's reading, not a verdict).** (1) The building alone takes about a third of the south face's winter light — mostly the morning beam behind the eastern wing, the rest the sky the three walls close; with the plan's brackets, between 0.54 and 0.80 is kept. (2) What stands in the opening is the larger term, and the unknown one. Crown lines at 34°–67° stand above the winter sun; under a level opaque horizon of 35°–60° the face keeps 0.07–0.16 of an open face's light, and the building's share given that horizon is 0.18–0.33, not two thirds: the building and the trees take DIFFERENT sky — the building the morning, the trees the opening — so once the trees take the opening's beam the building takes the only beam left. A level opaque screen is the harsh stand-in (under high crowns a December sun 12°–17° up passes among the trunks), the empty horizon the kind one; between them the building's share runs 0.18–0.68. On an overcast stretch — the kind that binds `110`'s adverse corner — it is the sky-diffuse column that acts, and it runs narrower: 0.75 with an empty horizon, 0.42–0.57 at 35°–60°. (3) Turning the logger to the opening is not the lever: 0.88–1.05 of the south face's light under any level horizon, and with a screen in one half the sign follows the half — 1.17–1.22 when the eastern half is screened at 40°, 0.94–0.95 when the western one is. (4) For the reading of R: a «not refuted» — R above the threshold in spite of the building — stands as it is; a refutation could be the building's, so it counts only if R divided by the LOWEST defensible share of the building is still below the threshold, and a share known no better than 0.18–0.68 spreads wider than the 1.64 times between `110`'s favourable and nominal thresholds at cadence C. Whether the trees beyond the opening are a stand — the thing the measurement asks about — or one more screen is the founder's fact, not the image's; the sheet's «a yard is not a stand» is untouched. A stem standing beyond the line of the wings' ends would have the whole building on bearings the winter sun does not take (a reading of the plan, not a run).

**What a visit to the yard replaces.** The model consumes angles, so angles read on the spot replace the plan read by eye. (1) A phone's inclinometer at the trunk, 1.3 m up, on the roof edge: toward the back wall (the model: 47.6°), square to the eastern wing (33.8°), square to the western one (38.0°), and just east of the opening's eastern edge (26.5°) — this replaces the roof's height and the scale at once, and a ridge standing above the edge shows in it. (2) The compass bearings of the opening's two edges (the model: 167° and 256°, true). (3) On the bearings 170°, 190°, 210° and 230°: what stands AT THE SUN'S HEIGHT of the table below — sky, trunks, crown, shrub; evergreen or bare — and the top of the crowns separately. (4) By paces, free of the scale: how far in front of the tree the eastern wing ends, over the tree's distance from that wing — 0.90 for an eastern edge at 167°, 0.73 at 161°, 1.11 at 173°. (5) On a clear morning, the minute the sun is first seen from 1.6 m at the trunk's face — the table; earlier than printed, the eastern edge lies further east or the roof lower; later, the edge lies further west or something beyond the opening stands higher than the sun. The logger's own record carries the same step on every clear morning.

| date | the sun's bearing passes the eastern edge | first seen from 1.6 m | the sun's height at 170° · 190° · 210° · 230° |
|---|---|---|---|
| 21 November | 10:46 | 10:46 | 20° · 20° · 16° · 6° |
| 21 December | 10:55 | 10:55 | 17° · 16° · 12° · 1° |
| 21 January | 11:10 | 11:10 | 20° · 20° · 15° · 5° |
| 11 February | 11:18 | 11:18 | 26° · 26° · 21° · 12° |
| 21 February | 11:20 | 10:54 — over the roof | 29° · 29° · 25° · 16° |

Local winter time. Late in February the sun clears the eastern wing's roof before its bearing reaches the opening's edge.

**What it cannot see.** What actually stands beyond the opening (only level screens are run; a stand is neither level nor opaque); the pine's own crown and its neighbours — the thing the logger is there to measure; the plan beyond what an image read by eye gives, and an input error no control can see (the eastern and western distances swapped pass every one of them); a roof's ridge above its edge; windows, wall colour and the light the walls return; an anisotropic sky, whose circumsolar part is blocked together with the beam; the yard's own snow; the logger's height other than 1.3 m.

**Controls.** Through the function the numbers come from: with no walls it returns the open face, with the walls drawn in and no opening under a thousandth, with a level horizon all round the direct sum over the sun's samples above it and the closed form of the sky view, and at height z under a roof H the beam of height 0 under H − z. The base beam share is recomputed by a second implementation — each sun sample's ray against three wall segments laid out in plan coordinates — and agrees. The plan the inputs make is asserted to be a court (both wings end in front of the tree); the distance law is checked off a wall's normal through `math`; the clock, by solar noon at 11:30–12:10 on every printed date. Beside it: the south face's open light under ERA5 is `110`'s open face hour by hour, and the view-factor kernels return their closed forms.

## HW.54 — What Does the Rising Bark Pass on the Radome, and What Does Each Consumer Stand to Lose? (script 119)

**The question (2026-11-13, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.54, the leg «кора накриває купол»).** `114` (4) prices ONE mark — the bark climbs the radome's 18 mm to the crown's top in 3.6–22.5 years — and `01_04 §5.5` C ⊕ names consumers of that number. The marks stand at different heights, and the field product has no visit to clear them (HW.54 Р12). `119` computes the two inputs the leg asks for before a recommendation — what `107`'s radio model says once the antenna plane is under the surface, and what an allowance that keeps the marks clear costs — and the two they need to be read: the ORDER in which the surface passes the marks, and the light left at the bottom of the pit the crown ends up in (numbers — `cache/radio/bark_overgrowth_consumers.json`).

**The premise, and it is not established.** The capsule is taken to stand still against the wood it was fixed to while the stem's surface moves outward past it. `114` itself prices a flange that BEARS on the bark as following a radial change of the bark by a share U — 0.2–42.5 % over its air-dry bark readings with the anode bonded, 100 % for a rigid bark, and under its premise (a) a rising bark can lift the flange off the sleeve. That is a linear reading of small changes, far outside its travel here, so it forecasts nothing; but where the bark carries the flange the clock below runs slower, or the failure is another one — the anchor drawn from its sleeve. The table is the clock at U = 0; the stretched one sits beside it in the cache as the size of the premise.

**(A) The marks on the radome stand at different heights.** Heights over the flange's top face, where the radome's rim lands: the rim itself (the radome–flange joint — the bayonet's seam, and the edge the forester's sheet reads tissue against), the vent hole by the closed form of `Radome.VentZMm` (mirrored in Python from the same manifest fields; the crossing is pinned from the C# side, RadomeTests; one hole), the RF deck from `52` (the BOM's two rows and the named-alternative B2B 6 row below them), the crown from the radome's manifest. BELOW the flange's top, and not in this table because no height has a home yet ([`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.8.10): the cathode's catalytic band and the buffer under it on the flange's side face — on a node that carries a cathode the first surface to meet the bark (`01_04 §3.1`, ⚖️ 2026-09-18); `114` puts the live bark at the flange seat in 1.7 ⊥ 10.4 years on the thin contact.

Where the outer bark stands at install: at the flange's top «at the latest» (canon's limit — the band must stand above the bark) ⊥ the faced seat's deep edge (2.25 mm above the top) ⊥ its mid-line (0.37 mm below) ⊥ its shallow edge (the flange's underside, 3.0 mm below). **The seat's edges are azimuths, not three unknowns.** The seat is faced square to an axis tilted by the install angle (the 10° design point, recovered from `78`'s facing spread), so the bark's plane cuts the capsule obliquely: along the axis it stands highest at the deep edge, lowest at the shallow one, and on the mid-line between them sit every point of the axis and — by the mounting requirement of `02_01 §3.4` (a machine reading; the rotation mark is not ratified, so the two edges stay as its outer bracket) — the vent hole's face. All three are functions of the flange's thickness, a PLACEHOLDER that HW.8.10 must grow by the bark's rise anyway; the deep edge standing above the top is that placeholder's defect, not a property of the travel. The tilt also shortens the clock: a mark z along the axis is passed after a radial travel of z·cos 10°, 1.5 % sooner than an untilted clock; `114`, which carries no tilt, prices the crown's top at 3.6 ⊥ 22.5 years; here it is 3.5 ⊥ 22.2. The two edge columns are exact for a mark on the outer wall (the rim, the vent on that side, the crown's edge); the RF deck and the crown's flat lie inside it, so for them the edges are an outer bracket, and (B)'s after-life cells — a deck's centre is on the axis — run from the flange's top and from the mid-line only. All of it is at the 10° design point, the verdict's ceiling: at a smaller angle the edges close up and the clock lengthens. The rate is `114`'s two ends, at 5.0 ⊥ 0.8 mm/yr — the slow end a measured network minimum on other trees, the fast end the lifetime mean of the pilot's own tree from its owner's estimate, which `01_03 §4` names a ceiling.

| mark | over the flange's top, mm | years to it, fast ⊥ slow: bark at the flange's top | at the deep edge | at the mid-line | at the shallow edge | outlives 20 years while the rate stays below, mm/yr: flange's top · deep · mid-line · shallow |
|---|---|---|---|---|---|---|
| radome's rim (the joint with the flange) | 0.00 | 0.0 ⊥ 0.0 | 0.0 ⊥ 0.0 | 0.1 ⊥ 0.5 | 0.6 ⊥ 3.7 | 0.000 · 0.000 · 0.018 · 0.147 |
| vent hole, lower edge | 9.08 | 1.8 ⊥ 11.2 | 1.3 ⊥ 8.4 | 1.9 ⊥ 11.6 | 2.4 ⊥ 14.9 | 0.447 · 0.336 · 0.465 · 0.594 |
| RF deck, the named-alternative row (B2B 6) | 9.85 | 1.9 ⊥ 12.1 | 1.5 ⊥ 9.4 | 2.0 ⊥ 12.6 | 2.5 ⊥ 15.8 | 0.485 · 0.374 · 0.503 · 0.632 |
| vent hole, upper edge | 10.08 | 2.0 ⊥ 12.4 | 1.5 ⊥ 9.6 | 2.1 ⊥ 12.9 | 2.6 ⊥ 16.1 | 0.496 · 0.385 · 0.514 · 0.644 |
| RF deck, the BOM's low row | 11.85 | 2.3 ⊥ 14.6 | 1.9 ⊥ 11.8 | 2.4 ⊥ 15.0 | 2.9 ⊥ 18.3 | 0.583 · 0.472 · 0.601 · 0.731 |
| crown's edge (the wall's top) | 13.00 | 2.6 ⊥ 16.0 | 2.1 ⊥ 13.2 | 2.6 ⊥ 16.5 | 3.2 ⊥ 19.7 | 0.640 · 0.529 · 0.658 · 0.787 |
| RF deck, the BOM's high row | 13.85 | 2.7 ⊥ 17.0 | 2.3 ⊥ 14.3 | 2.8 ⊥ 17.5 | 3.3 ⊥ 20.7 | 0.681 · 0.570 · 0.700 · 0.829 |
| crown's top (`114`'s mark) | 18.00 | 3.5 ⊥ 22.2 | 3.1 ⊥ 19.4 | 3.6 ⊥ 22.6 | 4.1 ⊥ 25.9 | 0.886 · 0.775 · 0.904 · 1.034 |

Over the rim, the first opening the surface passes is the vent hole — the BME280 pocket's only opening to the outside, on an add-on canon calls optional (`02_06 §1.3`) — at half the crown's height: 1.9 ⊥ 11.6 years from the seat's mid-line. With the capsule fixed, the surface passes its lower edge inside the twenty-year life at BOTH rate ends on every install reference; that quantifier stands on the placeholder thickness ((D)) and on the premise — at `114`'s high bearing share the slow end stretches to 19.4 · 14.6 · 20.2 · 25.8 years (the flange's top · deep edge · mid-line · shallow edge). It outlives the life on every reference only while the rate stays below 0.336 mm/yr. What the bark DOES at a mark — whether tissue seals a Ø1.0 mm hole, presses the wall or leaves a gap — this instrument does not say: the table is when the surface PASSES a height, never that a function ends there.

**(B) The radio once the deck is under the surface.** `107` refuses a source inside the stem. By reciprocity it need not solve one: the far field an embedded line source sends towards an azimuth equals the field a plane wave arriving from that azimuth sets up at the source's point, and `107`'s solve already carries that interior field. Everything is at the same source CURRENT against the free source's front lobe; the stems are the named ones (DBH 38 · 50 · 60 cm) under `107`'s sixteen readings, and each span is over readings × stems, rounded outward. THE OVERGROWN STEM: with the deck under the surface a reading keeps its own bark over the source, and wood laid down over the capsule inside the life is taken as SAPWOOD — a reading with a dry heartwood core gets its sapwood wider by the depth, so the core stays behind the source. That is OUR assumption (no source in the tree gives the age at which this pine's sapwood turns to heartwood, and `107` itself reads one sapwood width at every diameter), so the other reading — the stems as they stand — is run beside it on the same grid.

| the deck against the surface, mm | E along the stem: front, dB | at ±50°, dB below the front | 2-D near-field indicator (a deck in air only) | E horizontal: front, dB | at ±50°, dB below the front |
|---|---|---|---|---|---|
| 13.85 over — the BOM's high row | −5.7 … +1.0 | 1.4–2.7 | 0.14–0.66 | −5.2 … +1.3 | 3.0–5.0 |
| 9.85 over — the named-alternative row | −6.8 … +0.3 | 1.4–2.7 | 0.11–0.61 | −6.4 … +0.7 | 2.3–4.6 |
| 5 over | −8.7 … −0.6 | 1.4–2.8 | 0.06–0.52 | −8.4 … −0.3 | 1.4–4.0 |
| 0.5 over | −9.9 … −1.7 | 1.6–3.0 | 0.03–0.43 | −10.1 … −1.3 | 1.0–3.6 |
| at the surface | −10.0 … −1.8 | 1.6–3.0 | — | −10.3 … −1.4 | 0.8–3.5 |
| 10 under | −11.0 … −3.4 | 1.5–2.6 | — | −11.2 … −3.0 | 0.8–2.8 |
| 20 under | −12.3 … −6.7 | 1.7–2.5 | — | −12.4 … −6.7 | 0.7–1.6 |
| 40 under | −15.5 … −8.6 | 1.4–2.6 | — | −15.7 … −8.7 | 0.7–1.4 |
| 60 under | −18.8 … −9.9 | 1.4–2.4 | — | −18.9 … −10.2 | 0.7–1.4 |
| 80 under | −22.0 … −11.1 | 1.3–2.4 | — | −22.2 … −11.4 | 0.6–1.6 |

After the life the surface stands over the crown only at the fast end (79.3–84.5 mm): there the front has moved by −18.5 … −7.2 dB against the same row's install day with E along the stem (−19.0 … −7.8 dB with E horizontal); with the stems as they stand the favourable end is −3.0 dB (−3.6 dB) and the weak end the same. At the slow end no cell has the surface over the crown — the deck is in a pit on every one of its 4 cells — the surface over the deck, the crown still 1.72–2.10 mm out of it. The weakest cells on the 0.5 mm grid stand −23.7 dB in front and −26.0 dB at ±50° against the free source's front lobe with E along the stem (−23.9 and −25.0 dB with E horizontal; `thawed_red_pine_ionic`, DBH 60 cm, at the grid's end). By the rule's own measure — within 3 dB of the front at ±50° — the pattern under the surface holds on every one of the grid's 8736 cells with E along the stem (the least −3 dB crossing 50.3°) and fails on 42 of 8736 with E horizontal (the least crossing 46.9°; 5 of 48 rows at the surface, 3 at 5 mm, 0 at 10 mm). **The sapwood assumption decides that count:** with the stems as they stand the rule fails on 447 of 8736 cells with E along the stem (the least crossing 39.4°) and on 108 of 8736 with E horizontal (46.9°), and the front against the overgrown stem is −5.6 … +1.1 dB at 20 mm and −3.0 … +7.1 dB at 80 mm — of either sign at both depths, by several decibels. The media's own plane-wave attenuation runs from 0.15 dB/cm (the dry bark proxy) to 1.76 dB/cm (the red pine reading with all of its loss read as ionic); with the stem wet from the surface the front stands −10.0 … −5.9 dB at the surface itself, against −9.6 … −1.8 dB under the stem's own bark (E along the stem).

**This is the propagation term alone, and it is not a link margin.** What the booster draws and loses once its ground is wrapped in wet tissue — detuning, and the power its near field leaves there — is not computed, and its direction is not established: a thin line in contact with a lossy medium is not the antenna, the radome's pocket of air and PEEK sets that loss, and a concentric two-dimensional model cannot carry a pocket. Whether tissue closes over a smooth PEEK crown at all — `01_04 §5.5` A shapes it against exactly that — is not modelled either. And canon's budget (`02_01 §5.3`) is a sum of members from different models against free space, with no excess loss of the forest and with old bark members still inside its margin, so a field against the free front lobe and that margin are not like for like in either direction. `107`'s near-field indicator, defined for a deck in air, falls on the way down (E along the stem): 0.14–0.66 at the BOM's high row, 0.11–0.61 at the named-alternative row, 0.03–0.43 with the surface 0.5 mm under the deck. ⊕ A side reading: `107`'s own standoffs (12.85 · 16.85 mm) put the surface at the flange's UNDERSIDE — the seat's shallow edge; at the flange's top the same indicator is 0.11–0.66 against 0.13–0.70 at `107`'s standoffs.

**(C) The light in the pit.** Once the surface stands p over the crown's top the crown looks out of a pit. For a straight-walled pit of the dome's own radius the share of an ISOTROPIC field in the face's hemisphere that a coaxial disc at its bottom still receives is the closed form for two parallel coaxial discs, F = ½·[S − √(S² − 4·(r₂/r₁)²)] with S = 1 + (1 + R₂²)/R₁² and R = r/p:

| disc | half is left at a pit depth of, mm | years after the crown is reached, fast ⊥ slow | share at 10 · 20 · 40 · 80 mm | after 20 years at the fast end |
|---|---|---|---|---|
| the crown's flat (Ø 19.8 mm) | 13.15 | 2.6 ⊥ 16.4 | 0.618 · 0.322 · 0.116 · 0.033 | 2.9–3.4 % |
| the dome's outline (Ø 29.8 mm — the largest disc a cell could be; its share is the least) | 10.54 | 2.1 ⊥ 13.2 | 0.517 · 0.284 · 0.110 · 0.032 | 2.9–3.3 % |

A beam reaches the disc's centre only within atan(R/p) of the face's normal — 56.1° at 10 mm, 36.7° at 20 mm, 20.4° at 40 mm. An idealisation, not a bound: the face is vertical, so its hemisphere holds the stand, not the sky, and which form the light has there `110` leaves unestablished; a lip that rolls inward (how a wound closes) lowers the share, a funnel raises it, a bright wall adds some back.

**(D) The allowance.** For the lowest opening to stay clear through the life the install-day bark must stand at least 7.17 mm below the flange's top at the slow end and 92.47 mm at the fast end; today it stands 3.0 mm below on the seat's shallow edge, 0.37 mm below on its mid-line and 2.25 mm ABOVE on its deep edge.

| the allowance that keeps the vent hole clear for 20 years | at the slow end | at the fast end |
|---|---|---|
| the install-day bark below the flange's top at the mark's azimuth, along the axis, at least, mm | 7.17 | 92.47 |
| route 1 — a thicker flange: on the seat's shallow edge ⊥ mid-line ⊥ deep edge, at least, mm (today 3.0 — a placeholder) | 7.17 ⊥ 9.80 ⊥ 12.43 | 92.47 ⊥ 95.09 ⊥ 97.72 |
| route 2 — a stack raised on the radome: lift from the flange's top · deep edge · mid-line · shallow edge, at least, mm | 7.17 · 9.43 · 6.80 · 4.17 | 92.47 · 94.72 · 92.09 · 89.47 |
| the crown's height over the flange's underside, against today's — the same on either route (shallow ⊥ mid-line ⊥ deep) | ×1.20 ⊥ ×1.32 ⊥ ×1.45 | ×5.26 ⊥ ×5.39 ⊥ ×5.51 |
| the crown's height over the rim, against today's: route 1 ×1.00; route 2 from the flange's top · deep · mid-line · shallow | ×1.40 · ×1.52 · ×1.38 · ×1.23 | ×6.14 · ×6.26 · ×6.12 · ×5.97 |

At one rate end the two routes add the SAME height, so the crown's height over the flange's underside grows by one ratio either way. They differ at the rim, the bayonet's seam: a thicker flange leaves the crown's height over it as it is and the radome's drawing untouched, a raised stack multiplies it. The flange's thickness is also where canon already takes the bark's rise as an input (HW.8.10: the buffer under the cathode band) — not yet this twenty-year allowance: at the slow end it is a thicker flange, at the fast end it is not a flange. And clearing a mark is not keeping a function: on the fast end's lift (the flange-top row) the raised deck stands 100.76 ⊥ 104.70 mm over the install-day surface and 0.76 ⊥ 4.70 mm over it after the life — with E along the stem the front goes from +0.3 … +3.4 dB to −9.9 … −0.7 dB and the 2-D indicator from 0.77–0.93 to 0.03–0.52; keeping the install-day standoff through the life is the whole travel, 101.55 mm, the crown ×6.64 as high over the rim. On the install day at the raised standoff no row with E along the stem has its −3 dB crossing under the ratified ±50° (82.5–108.1°), while with E horizontal 27 ⊥ 23 of 48 rows do (44.8–61.5°) (low ⊥ high deck row). The ratios are ratios of heights — the tree has no bayonet load model (`73`) — and a thicker flange's thermal path (`78`, `79`), the anode's depth if the sleeve is not lengthened, the titanium, and a raised stack's side load, thermal balance and interconnect are not priced.

**What it cannot see.** The premise (above). The antenna, a link margin, and whether the surface closes over the crown (above). A capsule in a PIT — the surface above the deck, the crown still open. What the bark does at the wall. The stems' histories: DBH 38 · 50 · 60 cm are three points of `107`'s resonant diameter axis as they stand when read — a stem read at 38 cm with the deck deep under its surface was not a host twenty years earlier, and beyond 60 cm the bark table ends. The pit's shape and the light's form. The rate: two ends from `114`, neither an increment measured on the pilot's tree, the fast one a lifetime mean — a mature stem's current increment is read nowhere in the tree. The angle: the 10° design point is the verdict's ceiling; at a smaller angle the seat's edges close up. The stem's curvature across the seat and the bark's relief. And everything `107` cannot see: the third dimension, the anchor's radial conductor, the permittivity at 868 MHz, a stem that is not round.

**Controls.** Each says in the script what it can and cannot catch: on a sub-grid of every row's embedded positions the source's OWN boundary-value problem (admittance carried inward from the air and outward from the axis, joined at the source by its jump) against reciprocity's coefficients — the one that can catch a wrong reciprocity factor; the embedded and the exterior formula at the surface; an embedded source in a stem of ε_r = 1 against the free source's pattern; `107`'s cache at its own standoffs (front, the rule angle, the 2-D indicator); truncation at N and N + 15; `114`'s install edges and its years for the crown, rebuilt the way `114` reads them (it subtracts a radial spread from an axial height and carries no tilt — its re-run is a leg of HW.54); the pit's closed form towards zero depth, its fall with depth and with the disc's radius, its half-depth root. The cache test adds a closed form for a source inside a HOMOGENEOUS stem that shares no code with the script — on every homogeneous row at every printed depth, at the grid's weakest cells and at the weak end of every closed after-life cell; the «stems as they stand» counts are the script's own run and no test recomputes them.

## HW.6 — Which Long-Wave Form Does the Cloudy Winter Sky Follow, and What Does the Frost Half Say under a Read Sky? (script 120)

**The question (2026-11-13, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.6).** `79` weighs real cloud through two long-wave forms that disagree under full cover — «linear» (a covered sky is black) and «B82» (clear sky × (1 + 0.22·c²)) — and says in its own ceilings that which one holds decides the sign of the shift under the flange; canon kept it open ([`01_04 §3.1`](../../../01_04_CODIT_and_Xylemointegration.md)). The forest pair of thermocouples is planned to read the SIGN at the site; by the formula of 2026-10-14 (`01_04 §3.1`) the pair alone does not separate the sky's form from α, ε, the coupling and 1D. `120` reads a sky instead of modelling one: NASA POWER serves, for the very point the ERA5 files were asked for, an hourly downward long-wave flux at the surface under the real sky and «as if clear» (the response's header names CERES SYN1deg), from 2001 (`tools/in_silico/data/power_cherkasy_longwave/`).

**A — the forms against the product.** On **31576** frost hours (ERA5's air below 0 °C) of November–March 2001–2020 the product's cloud enhancement — all-sky over clear-sky flux, a ratio no temperature enters on the product's side — has under full ERA5 cover a median of **1.255** (10th–90th percentile 1.109–1.373); `79`'s B82 form gives **1.220** and its linear form **1.476**. Part of that last gap is not the form: under full cover the linear form's enhancement is 1/ε, and ε is `79`'s clear-sky formula on ERA5; on the product's own clear-sky emissivity — which also puts the product's colder air under the cloud — the linear form gives **1.368**. By season, under ERA5 cover above 0.8, the product's night medians run **1.164–1.284** over **19** seasons, against 1.420–1.500 for the linear form (1.334–1.387 on the product's clear sky) and 1.203–1.220 for B82 — nearer B82 in 19 of 19, nearer B82 than the linear form on the product's clear sky in 19 of 19, and below B82 itself in 11 of 19. That is a statement about a covered sky. Under ERA5 cover of 0.5 or less — **18 %** of frost hours — the product's night median is above BOTH forms in 19 of 19 seasons (nearer B82 in 0) — more than a black cloud of that cover gives — so there ERA5's cover is not the product's cloud, and this class says nothing about the form: in the 0.2–0.5 bin the product's median is 1.159 against 1.175 for the linear form and 1.027 for B82, and below 0.2 it is 1.121 against 1.010 and 1.000. Under cover above 0.8 a B82-shaped form meets the product's median hour at C ≈ **0.26** (10th–90th percentile of hours 0.10–0.40) on ERA5 cover and 0.32 on the product's own cloud amount, against the model's 0.22.

**The clear sky.** On frost hours `79`'s clear-sky formula (Brutsaert 1975), fed the MERRA-2 temperature and dew point POWER serves beside the flux, is **18.2** W/m² below the product's clear-sky flux (median emissivity 0.664 against 0.724); **20.4** W/m² below it if that «dew/frost point» is a frost point under 0 °C; and **9.8** W/m² below it as `79` actually computes it, on ERA5's temperature and dew point. It is a cold-weather gap — formula minus product, on the MERRA-2 inputs and, in brackets, as `79` computes it: −30.1 (−23.5) W/m² on frost hours colder than −10 °C, −7.9 (−1.0) on winter hours above freezing, −1.0 (−1.0) in May–August.

**B — `79`'s frost half under the read sky.** The window 2001-01-02 … 2020-12-31 less `79`'s 14 days of spin-up; `79`'s own columns, thresholds and `shift_stats`, imported — the share statistic is re-typed from `79`'s `main` with the same 0.05 K band. The share of frost days on which the cambium under the flange takes a daily minimum lower than under bare bark by more than that band, as a range over wind and the two ends of the bark bracket:

| Sky | tied, no sun | tied, diffuse sun | decoupled, no sun | decoupled, diffuse sun |
|---|---|---|---|---|
| `79` linear | 27–69 % | 68–89 % | 2–11 % | 37–57 % |
| `79` B82 | 0–38 % | 10–76 % | 0–2 % | 0–22 % |
| product, «emissivity» reading | 6–58 % | 48–87 % | 0–4 % | 14–38 % |
| product, «flux» reading | 2–51 % | 33–84 % | 0–3 % | 6–30 % |
| product, «air» reading | 10–64 % | 51–88 % | 0–4 % | 16–39 % |

Each sky defines its own frost days — the bark's daily minimum under that sky is below 0 °C, as in `79` — so the five skies' shares are taken over different days: 1542 to 2813 frost days by sky and cell. The product's sky is carried in three NAMED readings because ERA5's air runs **2.22** K warmer than the product's on frost hours and nothing here says which air the product's sky belongs with: «emissivity» carries the product's sky as an emissivity on its own air temperature onto the model's; «flux» sets the product's flux as given against the model's air; «air» lets the product's own air temperature drive the column as well (ERA5 keeps the wind and the diffuse sun). `79`'s two forms are recomputed here on the same years, so they differ a little from the thirty-year figures `01_04 §3.1` quotes.

**What the table says, and what it does not.** Cell by cell, each sky over its own frost days, each reading of the read sky lies between `79`'s two forms — 48 of 48 cell-and-reading pairs, 2 of them at 0 % together with B82. `79`'s two forms themselves stand further apart: their ranges do not overlap in 2 of 4 sun-and-coupling blocks (the decoupled end without sun, 2.2–10.9 % ⊥ 0.0–1.9 %; the decoupled end with diffuse sun, 37.1–57.3 % ⊥ 0.4–21.7 %), and their median shifts have opposite signs in 4 of 8 tied cells. Reading the sky narrows that bracket without closing it: under the product's sky the median shift is −1.51…−0.06 K at the decoupled end — negative in every cell of every reading — where `79`'s linear form with diffuse sun spans −0.14…+0.22 K; at the tied end it runs −1.11…+1.04 K: of both signs across wind and bark in 4 of the 6 product skies, positive in every cell of 2 («emissivity» and «air» with diffuse sun); in 2 of 8 tied cells the sign depends on which reading is taken, against 4 of 8 between `79`'s two forms. So a read sky does not settle the sign under the flange. What the pair of thermocouples is there to resolve is not narrowed here: the coupling, the wind at the trunk, the sun on the face, α, ε and the 1D column all stay `79`'s, and the sign at the site stays the pair's.

**How the product's sky enters `79`.** `79` is not edited and its cache is not re-run: its sky input is (air temperature, dew point, cloud), and with cloud 0 its «linear» kind — the carrier used — reduces to the clear branch with no black-body cap, so an effective dew point — Magnus inverted through Brutsaert — carries any target emissivity through `79`'s own code. The product's sky is above a black body at the air temperature on 8.9 % of frost hours in the «emissivity» and «air» readings and 2.7 % in «flux» (largest emissivity 1.17); `79`'s own forms never are, and no cap is applied. Control: `79`'s native B82 sky fed through that path returns `79`'s native B82 cambium series to 10⁻¹³ K on a winter window where B82's black-sky cap never binds; «linear» cannot be reproduced that way (its cloudy term follows the substep air temperature), and the script says so.

**The clock.** POWER stamps an hourly value with the start of the hour it averages (its FAQ, quoted in the data README), and `79` applies a row to the hour ending at it, so a product hour lands one row later than its stamp. This stands on POWER's documentation; the controls are narrower. `79`'s own B82 sky sent round the product's clock returns `79`'s native B82 series to 6e-14 K — a check of the lookup against its own shift, which passes at any shift. The hour-to-hour changes of the product's air temperature correlate with ERA5's best at the pairing used (r 0.547, against 0.507 and 0.516 one row either side) — a check on MERRA-2's temperature, not on the CERES fluxes, and it does not separate half an hour. The unshifted pairing moves a share of the «flux» reading by at most 0.8 points.

**Ceilings.** How the product is computed, on what cell and how accurately at an hourly step has not been read from its primary: the numbers above compare forms, they do not calibrate `79`. The product's hourly mean temperature is paired as the temperature at the end of its hour — up to half an hour late, so in the «air» reading the column's air runs behind the flux it is paired with. ERA5 cover and the product's cloud amount disagree hour by hour (under a product cloud amount of 20–50 % the median ERA5 cover is 0.71), and in the diffuse-sun columns of the product's readings the long wave is the product's cloud while the short wave is ERA5's. `79`'s beam and ground-reflected light are not re-run under the product's sky. Sky view, wind at the trunk, sun on the face, 1D conduction and zero contact resistance are `79`'s, unchanged; the radome↔flange coupling stays unmeasured, so the table is a bracket over its two ends and no row is a forecast.

⊕ **2026-11-14 — the product's primaries, read (the paragraph above is not rewritten).** *Edition:* NASA POWER's methodology page lists CERES SYN1deg Edition 4.2 from 1 January 2001, and the product's Data Quality Summary names Edition4B, released 7 May 2025, as «Edition4.2 on the ordering tool»; the API response itself names no edition. *Cell:* at this latitude it is not 1° × 1° — the summary's nested grid has a 2° longitude extent between 45° and 70°, the 1° product grid being filled by replication, and a probe of the POWER API around the point returned one value over 49–50° N × 32–34° E, the point sitting near that cell's western edge. *Accuracy:* no validation of Edition4B is published; for Edition 4A the surface-flux summary gives the hourly gridded downward long wave an uncertainty (k = 1) of 24 W/m² over land against a mean of 333, and Rutan et al. 2015 validate Edition 3A at a 3-hourly step (standard deviation 20.4 W/m², 6.2 %, all sites); neither gives a night, winter or snow breakdown. *Night cloud:* the summaries state that night-time cloud properties differ between geostationary generations and that a satellite upgrade leaves a discontinuity in the fluxes, so the twenty winters are not one instrument — `120` does not split its seasons by that boundary. What this changes: the cell and the edition are named, and the hourly uncertainty is of the size of single-hour scatter, not a statement about a median over frost nights; the numbers above still compare forms and do not calibrate `79`. Sources and quotes — the README of `tools/in_silico/data/power_cherkasy_longwave/`.

## HW.37 — Does the Reanalysis the Cold Edge Stands On Run Warm on Cold Nights? (script 121)

**The question (2026-11-13, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.37).** Canon reads the node's cold edge — the lowest air temperature and every count of cold hours and days — off ERA5 ([`02_03 §12.1`](../../../02_03_BQ25570_MPPT_Nano_Power.md); `81`; the frost days of `79`). A desk pass found ERA5 warmer than the Cherkasy station on the coldest nights of 2000–2009. `121` asks whether that holds on another decade, how much of it is produced by choosing the days BY the station, and what a second reanalysis gives for the same edge. Two station records that share no day — GHCN-Daily 2000–2009 and the Global Summary of the Day 1991–1998, the latter split into explicit minimum reports and minima derived from the hourly reports (a ceiling on the true minimum) — against ERA5's daily minimum and MERRA-2's (`tools/in_silico/data/station_cherkasy/`).

**The gap, reanalysis minus station, conditioned three ways.** A gap measured on days chosen by one series is pulled toward that series' extremes, so the days are chosen by the station, by the reanalysis, and not at all (a bin of fewer than 5 days carries no mean); ERA5's minimum is taken over three windows, because the station's «day» is a reporting window and not a calendar day:

| Record | Reading | all winter days | station below −15 °C | reanalysis below −15 °C | station below −20 °C | reanalysis below −20 °C |
|---|---|---|---|---|---|---|
| GHCN-Daily 2000–2009 | ERA5, UTC day | +0.71 K | +4.07 K (77 d) | +2.04 K (45 d) | +5.34 K (32 d) | +2.17 K (12 d) |
| GHCN-Daily 2000–2009 | ERA5, clock day | +0.88 K | +4.01 K (77 d) | +2.26 K (42 d) | +5.31 K (32 d) | +2.18 K (12 d) |
| GHCN-Daily 2000–2009 | ERA5, night 18:00–06:00 UTC | +1.24 K | +4.16 K (77 d) | +2.77 K (40 d) | +5.47 K (32 d) | +2.51 K (12 d) |
| GHCN-Daily 2000–2009 | MERRA-2 | −1.77 K | +0.84 K (77 d) | −2.81 K (94 d) | +1.66 K (32 d) | −3.18 K (34 d) |
| GSOD 1991–1998, explicit minima | ERA5, UTC day | +0.95 K | +3.01 K (46 d) | +1.85 K (19 d) | +4.08 K (12 d) | — (3 d) |
| GSOD 1991–1998, explicit minima | ERA5, clock day | +1.04 K | +3.10 K (46 d) | +1.71 K (18 d) | +4.28 K (12 d) | — (3 d) |
| GSOD 1991–1998, explicit minima | ERA5, night 18:00–06:00 UTC | +1.13 K | +3.21 K (46 d) | +1.79 K (18 d) | +4.38 K (12 d) | — (3 d) |
| GSOD 1991–1998, explicit minima | MERRA-2 | −1.05 K | +1.48 K (46 d) | −0.87 K (38 d) | +2.59 K (12 d) | −3.46 K (10 d) |
| GSOD 1991–1998, minima derived from hourly reports | ERA5, UTC day | +0.02 K | +1.32 K (21 d) | −0.07 K (16 d) | +1.29 K (6 d) | −1.34 K (5 d) |
| GSOD 1991–1998, minima derived from hourly reports | ERA5, clock day | +0.54 K | +2.09 K (21 d) | +0.67 K (13 d) | +1.70 K (6 d) | — (4 d) |
| GSOD 1991–1998, minima derived from hourly reports | ERA5, night 18:00–06:00 UTC | +1.55 K | +3.63 K (21 d) | +0.91 K (9 d) | +2.32 K (6 d) | — (4 d) |
| GSOD 1991–1998, minima derived from hourly reports | MERRA-2 | −2.23 K | +0.07 K (21 d) | −3.61 K (30 d) | −2.82 K (6 d) | −6.54 K (7 d) |

Chosen by the station's minimum below −15 °C, ERA5 (UTC day) is +4.07 K on the 2000–2009 record and +3.01 K on the explicit minima of 1991–1998; chosen by ERA5's own minimum instead, +2.04 and +1.85 K; over the night window the same pairs are +4.16 and +3.21, +2.77 and +1.79 K. The two choices are two ends, each pulled toward the series that chose the days, not two parts of one gap. On the two records with explicit minima 36 of the 48 conditioned ERA5 cells (four thresholds × three windows × two choices × two records) carry a mean, and all 36 are positive; the three windows are readings of the same nights and the bins are nested, so the independent units are the two records. At −25 °C only the station-chosen cells of 2000–2009 carry a mean (10 days); at −20 °C chosen by ERA5, only those of 2000–2009 (12 days). On the derived record 3 of its 16 ERA5 cells with a mean are negative — UTC day, chosen by ERA5: −0.22, −0.07 and −1.34 K; a derived minimum is a ceiling on the true one, so a gap against it is a floor on the gap. MERRA-2 at −15 °C is +0.84 and +1.48 K chosen by the station and −2.81 and −0.87 K chosen by itself: its gap changes sign with the choice. With no choice at all — the low quantiles of the same winter days — ERA5 (UTC day) minus the station is +4.06 / +2.30 / +1.20 K at the 1 / 5 / 10 % quantiles on 2000–2009 and +2.66 / +3.43 / +2.50 K on the explicit minima of 1991–1998; MERRA-2: −1.60 / −1.38 / −1.35 and −0.40 / +1.93 / +0.67 K.

**With no condition — the same paired days, counted by each series.**

| Record | minimum below | station | ERA5, UTC day | MERRA-2 |
|---|---|---|---|---|
| GHCN-Daily 2000–2009 | −15 °C | 77 | 45 | 94 |
| GHCN-Daily 2000–2009 | −20 °C | 32 | 12 | 34 |
| GHCN-Daily 2000–2009 | −25 °C | 10 | 4 | 13 |
| GSOD 1991–1998, explicit minima | −15 °C | 46 | 19 | 38 |
| GSOD 1991–1998, explicit minima | −20 °C | 12 | 3 | 10 |
| GSOD 1991–1998, explicit minima | −25 °C | 1 | 1 | 2 |
| GSOD 1991–1998, minima derived from hourly reports | −15 °C | 21 | 16 | 30 |
| GSOD 1991–1998, minima derived from hourly reports | −20 °C | 6 | 5 | 7 |
| GSOD 1991–1998, minima derived from hourly reports | −25 °C | 1 | 2 | 3 |

On the same paired days the station against ERA5 (UTC day) and MERRA-2 — 2000–2009: below −15 °C 77 against 45 and 94; below −20 °C 32 against 12 and 34; below −25 °C 10 against 4 and 13; explicit minima of 1991–1998: below −15 °C 46 against 19 and 38; below −20 °C 12 against 3 and 10; below −25 °C 1 against 1 and 2. ERA5 has fewer cold days than the station in 5 of these 6 record-and-threshold cells and as many in 1; MERRA-2 has more than the station in 4 and fewer in 2; the station has more than BOTH in 2, both on the 1991–1998 record.

**The extremes.** On the paired days ERA5's lowest is −26.8 and −27.1 °C against the station's −27.5 and −27.0 °C — 0.7 K above and 0.1 K below. On the station's coldest day ERA5 read −20.7 °C on 2000–2009 (2003-02-17, 6.8 K warmer) and −27.1 °C on the explicit minima of 1991–1998 (1994-02-13 — there the coldest day of both). ERA5's own −27.4 °C of the 29 seasons fell on 1997-12-17 and 2012-02-02 — days with no explicit station minimum; the one the derived record carries reads −25.9 °C, a ceiling on the true minimum. The station does not contradict ERA5's floor and on its days does not test it. MERRA-2's lowest on the paired days is −30.95 and −32.37 °C — 3.45 and 5.37 K below the station's own lowest; on the station's coldest days it read −20.71 and −32.37 °C; and its −34.94 °C of the 29 seasons (1997-12-16) falls on a day no station record carries. On 1997-12-17, where the derived record reads −25.9 °C, MERRA-2 read −34.61 °C; a ceiling on the true minimum excludes neither reanalysis.

**The edge itself, 29 seasons 1991/92–2019/20, in the two reanalyses.**

| Reading | lowest minimum | days with minimum below −15 / −20 / −25 °C (seasons with any) | days with MAXIMUM below −15 / −20 °C (seasons with any) |
|---|---|---|---|
| ERA5, UTC day | −27.4 °C (1997-12-17, 2012-02-02) | 192 (26) / 52 (18) / 11 (4) | 14 (5) / 2 (2) |
| ERA5, clock day | −27.4 °C (1997-12-17, 2012-02-02) | 178 (26) / 48 (18) / 9 (4) | 14 (5) / 2 (2) |
| MERRA-2 | −34.9 °C (1997-12-16) | 415 (28) / 142 (21) / 52 (15) | 34 (13) / 10 (5) |

Hours below −25 °C over 2001–2020: ERA5 **38**, MERRA-2 **261**; below −20 °C — 299 and 895; below −15 °C — 1205 and 2804. The hourly MERRA-2 series is the 2 m temperature riding in `data/power_cherkasy_longwave/` — an hour's mean against ERA5's value at the hour.

**What follows.** ERA5 runs warm on cold nights against this station: on the two records with explicit minima every conditioned cell that carries a mean is positive, and with no choice of days its low winter quantiles sit 1.20–4.44 K above the station's over the three windows. It shows as cold days ERA5 does not count — fewer than the station in 5 of 6 cells — while its lowest values lie within 0.7 K of the station's; of the station's two coldest days ERA5 met one and read the other 6.8 K warmer. MERRA-2 has more cold days than the station in 4 of 6 cells and fewer in 2. The two are therefore two NAMED readings of the edge — ERA5 the smaller count in every line of the edge table and in every count of hours — and neither is shown to bound the station from above; the station is a town site, so the direction for the forest plot is not established here. Nothing here corrects either reanalysis. The node's capsule is not air: in the coldest hour of `81`'s deep edge (clear sky, no sun, calm; air −27.4 °C) the capsule sat 6.1 K below the air — the difference of that hour, not a constant: across `81`'s 12 runs it is −6.13 to +0.05 K — and `81` ran on ERA5 only, so what the colder reading means for the capsule's own floor is not computed here.

**Controls.** All six controls passed: every one of the 12 record-and-reading pairings correlates best at lag 0; the mean gap over all paired days stays inside ±3 K (the bound that would catch °F read as °C); the clock-day mean recomputed from ERA5's hourly file meets its daily-mean file within 0.067 K on all 10958 days; the GHCN-Daily quality flags dropped are exactly the file's 74 «I» and 1 «G», leaving 2483 of its 2558 minima; MERRA-2's daily minimum equals the minimum of its hourly field on all 7305 days of 2001–2020; and ERA5's hourly series, read as UTC by subtracting the file's offset, changes hour to hour in step with MERRA-2's — the correlation of first differences is highest at lag −1 h (0.55; 0.51 at lag 0, 0.41 and 0.16 at ∓3 h), inside the hour that instants against hourly means cannot resolve.

**Ceilings.** One station, and not the forest plot: a synoptic site at a town against cells of 0.25° and 0.5° × 0.625° — part of any gap is siting, not reanalysis error. The station's «day» for a reported minimum is a reporting window; the three ERA5 windows are readings of it, and the night window is this script's guess, not a station manual's. The two station records share no day, so nothing says they are one instrument. A reanalysis «daily minimum» is the lowest of 24 hourly values — instants for ERA5, hourly means for MERRA-2 — and both sit at or above the continuous minimum a thermometer reports. The coldest bins are thin.

## HW.37 — The Capsule's Cold Edge on the Colder Reading of the Air (script 122)

**The question (2026-11-14, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.37).** `81` ran the isolated capsule on ERA5 air and found no run below the capsule requirement. `121` then read the cold edge from two reanalyses — «ERA5 the smaller count in every line of the edge table and in every count of hours». `122` runs `81`'s deep edge — the isolated lump with no sun in still air — on MERRA-2's hourly air under three readings of the sky (Brutsaert's formula, as in `81`; CERES SYN1deg's clear-sky flux and its all-sky flux as NASA POWER serves them — `120`'s product — in the row the MERRA-2 air comes from), on the hours both hourly series carry, each run beside `71`'s own ×0.7 reading of its still-air kernel, and under the formula's sky at every daily minimum the daily file carries before them. This script changes nothing in `81`: it imports its lump and writes its own cache. No wind rides in the MERRA-2 hourly file, so inside the hourly record only the calm run is computed; under a clear sky every windy run of `81` is warmer than its calm one.

| Air | Sky | coldest capsule hour (UTC; the air at it) | capsule: hours below −25 °C (UTC days · longest spell) | capsule: hours below −40 °C | with `71`'s ×0.7 still-air kernel: coldest · hours below −25 / −40 °C |
|---|---|---|---|---|---|
| MERRA-2 | Brutsaert's formula (`81`'s clear sky) | −39.02 °C (2012-02-02T04; −33.15 °C) | 1059 (112 · 114 h) | 0 | −40.21 °C · 1340 / 3 |
| MERRA-2 | CERES SYN1deg clear-sky flux | −36.01 °C (2012-02-02T04; −33.15 °C) | 660 (66 · 108 h) | 0 | −36.55 °C · 771 / 0 |
| MERRA-2 | CERES SYN1deg all-sky flux | −35.19 °C (2012-02-02T05; −33.04 °C) | 462 (54 · 45 h) | 0 | −35.58 °C · 500 / 0 |
| ERA5 | Brutsaert's formula (`81`'s clear sky) | −33.45 °C (2012-02-02T07; −27.40 °C) | 399 (49 · 106 h) | 0 | −34.64 °C · 504 / 0 |

**Inside the hourly record.** Over 2001–2020, with `71`'s kernels as they are, no run crosses the requirement. On MERRA-2 air the deep edge bottoms at −39.02 °C under the formula's clear sky — 0.98 K above the requirement of −40 °C — at −36.01 °C under CERES's clear-sky flux and at −35.19 °C under its all-sky flux; on ERA5 air under the formula, at −33.45 °C. The air itself bottoms at −33.15 °C (MERRA-2) and −27.4 °C (ERA5), with 261 and 38 hours below the EDLC floor. `71` reads its still-air kernel off its home geometry at ×0.7 and prints its hot bound with that reading; run here on the cold edge, it puts the formula-sky run on MERRA-2 air at −40.21 °C, below the requirement on 3 hours, and leaves CERES's two skies 3.45 and 4.42 K above it and ERA5 under the formula at −34.64 °C.

**The sky.** The formula's sky is the coldest of the three, and at these temperatures it is an extrapolation: on MERRA-2's 200 coldest hours of 2001–2020 Brutsaert's formula gives a ratio of sky to air black-body flux of 0.49–0.55 (median 0.53) where CERES's clear-sky flux gives 0.69–0.83 (median 0.76) — on every one of those hours the formula's flux is below CERES's, by 32.0–62.0 W/m² (median 48.9). CERES's ratio is a ratio of two sources — its flux over the black-body flux of MERRA-2's air — and under its all-sky flux it reaches 1.08 on those hours. The sky product is CERES SYN1deg by the response's header, not MERRA-2: by its data-quality summary its clear-sky flux is the all-sky radiative-transfer computation with the clouds removed, on another analysis's six-hourly profiles — not a measurement, not computed on the air it shares a row with, and not a judge of the formula but a second reading of the sky. It does not reach back before the hourly record.

**The days before the hourly record.** MERRA-2's lowest daily minimum of the 29 seasons `121` reads — −34.94 °C on 1997-12-16 — lies before the hourly record (POWER serves hourly values from 2001), and so does CERES's sky. Solved under the formula's sky in still air at the minimum of each of the 3653 days of 1991–2000 the daily file carries, the lump is below the requirement on 2 of them (1997-12-16, 1997-12-17), at both ends of a dew-point sweep from 2 K above the air to 5 K below it — by 0.70–1.17 K on the first and 0.37–0.84 K on the second. The sweep is ours; it spans what MERRA-2 carries on its 200 coldest hours of 2001–2020 (from 1.29 K above the air to 1.70 K below, median 0.12 K below).

**What the crossing stands on.** On those two days the lump sits ON the requirement at a sky ratio of 0.565 and 0.535; the formula gives 0.448–0.495 across the sweep at the lower minimum, and with CERES's clear-sky ratios of its coldest hours the same lump at those minima sits at −38.74 to −36.85 °C — above the requirement, and still above it with the ×0.7 kernel (−39.48 to −37.26 °C). Still air is the other half: the lump needs a wind at the capsule of 0.016–0.029 of the daily-mean 10 m wind the daily file carries for those days (4.73 and 2.89 m/s); with `71`'s share k = 0.1 of it the lump sits at −38.03 to −37.49 °C, with k = 0.3 at −36.75 to −36.49 °C — k is ours and unmeasured, and a daily mean is not the wind at the coldest hour. The station has no row for 1997-12-16; for 1997-12-17 it carries a mean of 5 reports of −24.2 °C, a reported maximum of −17.7 °C, a minimum derived from those reports of −25.9 °C (a ceiling on the true one) and a mean wind of 1.8 m/s (the lump needs 0.035–0.047 of it), against MERRA-2's −29.46, −23.13 and −34.61 °C for the same day.

**What follows.** `81` found no run below the capsule requirement; that is a statement about ERA5 air under the formula's sky with `71`'s kernels as they are. On MERRA-2 air the hourly record keeps 0.98 K under the formula's sky and 3.99 and 4.81 K under CERES's two skies — and the first does not survive `71`'s own reading of its kernel, which takes that run below the requirement. Before the hourly record the model's lower bound passes the requirement — by at most 1.17 K — on 2 days of 1991–2000. That passing takes three readings at once — MERRA-2's air rather than ERA5's, Brutsaert's formula rather than CERES's computed flux, and air at the capsule stiller than 0.016–0.029 of the daily-mean 10 m wind — and none of them is a rare event or settled for the plot: the first two are each one of two readings of one quantity, and a clear sky and a low minimum are one weather, not two chances. Against them the same files set CERES's ratios, `71`'s k (ours, unmeasured) and, on 1997-12-17, a town station whose coldest report is 3.6 K above MERRA-2's daily mean. The hours below the EDLC floor do not share that reassurance: per year of the window 53.0 · 33.0 · 23.1 on MERRA-2 air (formula · CERES clear · CERES all-sky) against 20.0 on ERA5 air, and 18.8 a year in `81`'s 30 years (565 h) — the count the canon carries; every MERRA-2 run is above both, the all-sky one included, which is no clear-sky bound; with the ×0.7 kernel every count grows (67.0 · 38.6 · 25.0 against 25.2); and in days below −25 °C the station sits nearer MERRA-2 than ERA5 (`121`, 2000–2009: 10 station days against 13 and 4). The temperatures are a lower bound for a GIVEN air, a GIVEN form of the clear sky and a GIVEN kernel in five choices — isolated from the bark, clear every hour, no sun, still air, no heat capacity; the hour counts are an upper count in the first four only, because a heat capacity can stretch a spell as well as shave it (`81`). The sky view 0.5 and the capsule's emissivity 0.90 are `71`'s assumptions, not bounds; the half of the view that is not sky is taken at the air's temperature; and ×0.7 is `71`'s own reading of its kernel off its home geometry, not a measured band. Neither air reading is shown to bound the station in its count of cold days (`121`); which of them the plot follows is the capsule logger's to say.

**Controls.** All seven controls passed: `81`'s cached deep edge is reproduced through this script's call path, and it is the regime and wind this script names; the MERRA-2 window is one unbroken clock of 175296 hours with no missing value in any of its four columns; the ERA5 window is `121`'s UTC series hour for hour, and the air's hours below −10 · −15 · −20 · −25 °C equal `121`'s counts in both readings; MERRA-2's lowest daily minimum is a single day before the hourly record and the daily file carries it; MERRA-2's dew column sits −0.56 K from ERA5's dew point in the mean with a correlation of 0.974 (bound ±3 K, at least 0.95); CERES's clear-sky flux exceeds its all-sky flux on no hour and is below it on some; and `71`'s kernels scaled by ×0.7 make every run colder and are restored after.

**Ceilings.** One reanalysis cell, hourly means stamped at the start of the hour; a steady lump with no heat capacity. MERRA-2's «dew/frost point» sits above the air on 6145 of the 175296 hours, 4001 of them with the air at or above 0 °C; the response's header does not say which of the two it is below 0 °C, and here it is read as a dew point over water — the warmer reading of the two. Capped at the air, it moves the coldest capsule hour by −0.032 K and the hours below the floor by +0; read as a frost point over ice (`120`'s conversion), by −0.226 K and +46, still with no hour below the requirement. The dew-point sweep for the days before the hourly record is ours, not those days' weather. What the EDLC and the seal do at these temperatures is not a question this script can answer.

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

## HW.43 — Which Reanalysis of the Wind Does the Station Sit Nearer To? (script 123)

**The question (2026-11-14, [`00_07`](../../../00_07_Action_Plan_Tracker.md) HW.43).** `62` takes its duty shares from MERRA-2's daily mean wind, and `98` plans the field strain campaign on ERA5's hourly wind and counts its stop rule in hours at Beaufort 5; a desk pass found the two series an order of magnitude apart in strong-wind hours on the same point. `123` sets both against the Cherkasy station's own wind (GSOD, 1991–1998) on the quantity each script counts — the daily mean for `62`, the daily maximum that stands behind `98`'s hours — with the days chosen by the station, by the reanalysis and not at all, as `121` did for the temperature, and keeps LEVEL and RANKING apart. The station is the yardstick here, not the truth: its anemometer is not read from a station manual. It reports whole metres per second, so the threshold is read twice — as printed, and at the value a report rounds from. The thresholds are read from the two scripts' caches, not typed.

**The daily mean — the quantity `62` counts.**

| Days | Series | mean, m/s | days with mean ≥ 3.4 m/s | days with mean ≥ 5.5 m/s | days with mean ≥ 8 m/s |
|---|---|---|---|---|---|
| all paired days (1672 d) | station | 3.68 | 54.3 % | 12.6 % | 1.5 % |
| | ERA5 | 3.46 | 48.2 % | 6.0 % | 0.2 % |
| | MERRA-2 | 4.63 | 75.4 % | 27.5 % | 3.4 % |
| days with 7 or more reports (899 d) | station | 3.62 | 53.8 % | 11.5 % | 1.6 % |
| | ERA5 | 3.44 | 47.2 % | 6.2 % | 0.1 % |
| | MERRA-2 | 4.60 | 74.7 % | 26.3 % | 3.7 % |
| December–April (799 d) | station | 4.03 | 62.6 % | 17.6 % | 2.6 % |
| | ERA5 | 3.63 | 53.3 % | 8.4 % | 0.3 % |
| | MERRA-2 | 4.90 | 79.0 % | 34.7 % | 5.5 % |

On the daily mean the station lies between the two series, nearer ERA5 in level, in all three sets of days: over the 1672 paired days of 1991–1998 it is 3.68 m/s against ERA5's 3.46 and MERRA-2's 4.63 — 0.94 and 1.26 of the station's. At each of `62`'s three anchors, in each set of days, ERA5 puts fewer days at or above the anchor than the station and MERRA-2 more.

**The daily maximum — what stands behind `98`'s hours.** A day can hold a Beaufort-5 hour only if its maximum reaches it. The station's maximum is the highest of the day's reports — short means at a point; ERA5's is taken over all 24 hourly instants and over the eight synoptic ones, which is nearer the station's reporting schedule and does not equalise the support (a point against an instant of a grid-cell average); MERRA-2's is the highest of 24 hourly means. The counts are therefore not like for like, and the two paragraphs after the table say what survives that:

| Days | Reading | days at 8 m/s or more | of them the station's | the station's days it misses | at 7.5 m/s: days · the station's | minus the station, on the station's days | on its own days |
|---|---|---|---|---|---|---|---|
| all paired days (1672 d) | station, highest of the day's reports | 253 | — | — | — | — | — |
| | ERA5, highest of 24 hourly instants | 36 | 34 | 219 | 80 · 69 | −3.23 m/s | −2.14 m/s |
| | ERA5, highest of the 8 synoptic instants | 24 | 24 | 229 | 56 · 52 | −3.44 m/s | −2.58 m/s |
| | MERRA-2, highest of 24 hourly means | 353 | 175 | 78 | 462 · 197 | −0.84 m/s | +1.43 m/s |
| days with 7 or more reports (899 d) | station, highest of the day's reports | 137 | — | — | — | — | — |
| | ERA5, highest of 24 hourly instants | 19 | 17 | 120 | 47 · 39 | −3.31 m/s | −1.82 m/s |
| | ERA5, highest of the 8 synoptic instants | 12 | 12 | 125 | 32 · 29 | −3.51 m/s | −2.31 m/s |
| | MERRA-2, highest of 24 hourly means | 203 | 100 | 37 | 244 · 105 | −0.89 m/s | +1.30 m/s |
| December–April (799 d) | station, highest of the day's reports | 140 | — | — | — | — | — |
| | ERA5, highest of 24 hourly instants | 25 | 24 | 116 | 55 · 49 | −3.06 m/s | −2.76 m/s |
| | ERA5, highest of the 8 synoptic instants | 16 | 16 | 124 | 38 · 36 | −3.27 m/s | −3.39 m/s |
| | MERRA-2, highest of 24 hourly means | 201 | 110 | 30 | 255 · 122 | −0.32 m/s | +1.31 m/s |

The station reported 8 m/s or more on 253 of the 1672 days (15.1 %); ERA5's hourly maximum reaches 8 m/s on 36 days, 34 of them the station's, and MERRA-2's on 353, 175 the station's. So 219 of the station's 253 threshold days stay below 8 m/s in ERA5. Read at 7.5 m/s — the value a report of 8 rounds from — ERA5 has 80 days (69 the station's) and MERRA-2 462 (197). The station's own count moves with one whole m/s — 423 days at 7 or more, 150 at 9 or more — and ERA5's stays below it either way.

Over all paired days ERA5's daily maximum is 1.07 m/s below the station's and MERRA-2's 0.57 above. On the station's own threshold days ERA5's maximum sits 3.23 m/s below the station's report on average (median 2.39) and MERRA-2's 0.84 below (median 0.18); on the days each reanalysis itself puts at the threshold, ERA5 is still 2.14 m/s below the station and MERRA-2 1.43 above it. The two ways of choosing the days are two ends, not parts of one gap: ERA5 is below the station under both, in all three sets of days; MERRA-2 is below on the station's days and above on its own.

The upper quantiles of the daily maximum over all paired days (0.90 · 0.95 · 0.99): station 8 · 10 · 14 m/s, ERA5 6.72 · 7.41 · 8.43, MERRA-2 9.26 · 10.15 · 12.19; the highest value of each — 25, 10.64 and 15.84 m/s.

**Level and ranking, kept apart.** Both reanalyses are smoother than the station, and on the daily mean they are nearly one series at two scales. The coefficient of variation of the daily mean is 0.45 at the station, 0.35 in ERA5 and 0.37 in MERRA-2; the two reanalyses' daily means correlate at 0.97, MERRA-2's mean being 1.34 times ERA5's. Rescaled to the station's mean, ERA5's daily maximum reaches 8 m/s on 72 days and MERRA-2's on 88, against the station's 253: MERRA-2 comes nearer the station's count because it runs higher by a near-constant factor, not because it holds the station's tail.

Ranked rather than counted, the two do alike. Of ERA5's own 258 highest daily maxima (as many as the station has threshold days, 253, plus the days tied with the last of them — down to 6.25 m/s) 158 are days the station reported 8 m/s or more; of MERRA-2's 253 (down to 8.51 m/s) — 152. In December–April: 97 of 143 and 96 of 140.

**Hours, in the form the stop rule counts.** Hours at 8 m/s or more over the 19 campaign seasons 2001/02…2019/20 (1 December … 30 April; 68976 hours both series carry): ERA5 a median 29 a season (0–53), MERRA-2 287 (158–410). 519 of ERA5's 520 such hours are also MERRA-2's, out of MERRA-2's 5558; such an hour falls on 105 days in ERA5 and 657 in MERRA-2, and 8 of the 19 Januaries have none in ERA5 against 1 in MERRA-2. MERRA-2 holds 10.7 times ERA5's such hours; the mean speed over ALL hours of those seasons is 3.54 against 4.75 m/s.

**What it means for the two scripts — a machine reading, not a verdict.** `62`'s shares of days, recomputed on the daily mean over the 10957 UTC days of 1991–2020 both series carry: at 3.4 · 5.5 · 8 m/s ERA5 keeps 43.3 % · 5.0 % · 0.1 % of days, MERRA-2 70.4 % · 23.7 % · 3.0 %; `62` itself, on MERRA-2's 2015–2024, prints 70.4 % · 24.8 % · 3.5 %. For `62`: on the daily mean MERRA-2 puts more days above every anchor than the station, and ERA5 fewer. That orders the three series; whether `62`'s shares over-count the wind under a canopy — the sense in which `62` calls them upper bounds — a town station does not say. For `98`: the plan is self-consistent by construction, because the measured hours are binned, and the stop rule counted, on the series the replay ran on — so the station cannot refute it. What the station adds is that ERA5's LEVEL at strong wind is far below an anemometer's, so its «8 m/s» is not a station's 8 m/s, while it ranks windy days as MERRA-2 does. For a transfer that bins hours by the reanalysis wind the ranking is what carries: nothing here is a ground to change the series, the stop rule or the cap, and it is a ground not to read the campaign's ERA5 thresholds as Beaufort numbers on an anemometer.

**Controls.** All five controls passed: the station's daily mean correlates with each reanalysis' best at lag 0 in every set of days; every station maximum is a whole number of m/s when read as knots (worst miss 0.065 kn of the 0.08 allowed) and no day's mean exceeds its maximum by more than the print's rounding (4 days do, by at most 0.019 m/s); MERRA-2's daily mean and maximum equal the mean and maximum of its hourly field on all 7305 days (worst 0.005 m/s), and the file `62` reads — its header's time standard is LST — equals the same hourly field's mean over days of UTC + 2 h on all 2192 days they share (worst 0.005 m/s; read as UTC days it would miss by up to 0.79 m/s); this script's count of January's Beaufort-5 hours (0.198 a day, 14 of 30 Januaries without one) is `98`'s; and ERA5's hourly wind, read as UTC by subtracting the file's offset, correlates with MERRA-2's best at lag −1 h (0.913; 0.911 at lag 0), inside the hour that instants against hourly means cannot resolve.

**Ceilings.** One station, at a town, and not the forest plot: a synoptic anemometer against grid cells of 0.25° and 0.5° × 0.625°, so part of any gap is siting and exposure. The station's maximum is the highest of four to ten reports a day, each a short mean, and a reanalysis hour — an instant for ERA5, an hourly mean for MERRA-2 — is a grid-cell average that holds no gust; the anemometer's height, type and averaging time are not read from a station manual, the reports show a preference for some whole numbers, and the single highest report stands as the archive gives it. The record is dense only to 1994 and shares no year with the hours of the campaign seasons, whose median is over the seasons both hourly series carry, not over all of ERA5's. The ranking is compared at the station's count of threshold days; further into the tail it is not compared here. Nothing here corrects a reanalysis or re-plans the campaign, and nothing says how either cell's open-terrain wind relates to the wind under the canopy at anchor height — that transfer is what the campaign measures. Cache: `mechanical/wind_reanalyses_station.json`.

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
| Paper figures | `scripts/60_paper_figures.py` (cache-only, canon-asserted) → `paper/figures/` (Fig 2/3/4 + S1/S2; Fig 1 = the PyMOL render of `fig1_pymol_cartoon.py`; the TOC graphic = art, a draft) |
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
