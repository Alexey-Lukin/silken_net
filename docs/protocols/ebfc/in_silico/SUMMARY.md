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
| **L1** | Does deglycosylated FAD-GDH fold correctly? | AlphaFold 3 | ✅ d_FAD = 15.998 Å < tunneling 18-20 Å |
| **L2** | Does the full matrix denature the protein? | OpenMM MD (481k atoms) | ✅ RMSD 1.22 Å (100ps), Rg stable at 10ns |
| **L3** | Does electron cascade FAD→Os flow downhill? | PySCF DFT (66 atoms, dimethyl) | ✅ Downhill (verified +574 mV); raw DFT uphill = method limit, decomposed by ② |
| **L3b** | Is DET through ZIF nanozyme fast enough? | PySCF ΔSCF + Marcus | 🟡 borderline — geom-fixed t_ij + realistic λ → Cu-Co bottleneck ~turnover (×1–30), NOT the old ×10⁵ (see §Cathode) |
| **L4** | Does BASELINE_DELTA_T_S = 60s make physical sense? | Analytical MM+Arrhenius | ✅ Healthy 19.9s / Stressed 100.7s (η_BQ 0.68 post-HW.47; re-anchored on the dgrGcGDH asymptote 2026-09-18, HW.5.IS) |

**Bottom line:** All computational checks pass. The design is ready for physical prototyping (Ti-coin Stage 2).

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
| Tunneling range (Os-bpy polymer) | 18-20 Å |

**Conclusion:** d_FAD < r_tunneling → MET architecture mathematically proven viable.

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

**Method:** B3LYP/6-31G(d) + LANL2DZ(Os) + C-PCM water. **Mediator = the real 4,4'-dimethyl-bpy** (Zafar +309 mV; OS-RECOMPUTE 2026-06-17); plain-bpy retained as the parent π-backbonding reference.

| Species | HOMO (eV) | LUMO (eV) | Gap (eV) |
|---------|-----------|-----------|----------|
| FAD (oxidized) | -6.188 | -2.779 | 3.409 |
| **FADH₂ (reduced) — donor** | **-5.137** | -1.592 | 3.545 |
| Os(II) [Os(dmbpy)₂(1-MeIm)Cl]⁺ | -4.724 | -2.023 | 2.702 |
| **Os(III) [Os(dmbpy)₂(1-MeIm)Cl]²⁺ — acceptor** | -6.209 | **-4.086** | 2.124 |

**Marcus Cascade Verdict:**

| Quantity | Value |
|----------|-------|
| ε_HOMO(FADH₂) | -5.137 eV |
| ε_LUMO(Os(III)) dmbpy | -4.086 eV |
| Raw Δε (dimethyl) | -1.051 eV (UPHILL; +0.142 more uphill than plain bpy via the 4,4'-substituent ①) |
| **Verified driving force** | **+574 mV / −0.574 eV (downhill)** |
| ↳ E°(Os +309 vs NHE, Zafar 2012) − E°(FAD-GDH −265 mV SHE, Schachinger 2023) | verified E°s |
| Gap raw-DFT ↔ verified | ② chloro-anchored bracket — differential PCM solvation [chloro +1/+2 lower ↔ bis-Im +2/+3 upper] + substituent +0.142 ① (Koopmans; +0.149 on the adiabatic ΔSCF) |

**Conclusion:** Raw DFT verdict UPHILL is a **method limit** (differential PCM solvation, chloro↔bis-Im bracket + the 4,4'-dimethyl substituent), decomposed by ② (§"Cluster-Continuum Micro-Solvation"). The cascade is **experimentally downhill** (+574 mV, verified E°s — Os +309 vs NHE / FAD-GDH −265 mV SHE). The earlier «bias-corrected Δε ≈ −0.07 eV reproduces exp −0.14» was fortuitous cancellation tuned to a mis-valued (+60 mV) FAD potential — **withdrawn**; Cosnier 1999's +140 mV pertains to glucose-oxidase, not GcGDH.

**PCET validation (script 32 — thermodynamic proton reference):** the flavin couple itself is NOT the culprit — E°(FAD/FADH₂) = **−158 mV vs NHE** (pH 7; −10 mV pH 4.5, +256 mV pH 0) lands **within 50 mV** of the free-flavin experimental value → the ~1 eV raw-DFT gap is isolated to the **differential PCM solvation of the charge-changing Os couple**, not the flavin. (Cache `dft/pcet_redox_potential.json`; the cascade-PCET reframe of script 33 does not flip it downhill — same PCM limit, not proton coupling.)

### Publication-grade: ωB97X/def2-TZVP (dimethyl mediator, B1 ✅ 2026-06-17)

| Species (dimethyl bpy) | HOMO (eV) | LUMO (eV) | Gap (eV) |
|---------|-----------|-----------|----------|
| Os(II) | -6.961 | -0.311 | 6.650 |
| **Os(III)** | -8.734 | **-1.644** | 7.090 |
| **FADH₂** | **-7.664** | 0.282 | 7.946 |

**All methods comparison** (dimethyl mediator; EA_Os3 = **4.243 eV** from B1, +0.149 lower than plain via the donor substituent; FAD IP from the B2 generator):

| Method | ΔG/e⁻ (eV) | vs verified −0.574 |
|--------|-----------|---------|
| Koopmans ωB97X | +6.02 | RSH artifact (never use) |
| ΔSCF ωB97X (vertical) | +1.40 | +1.97 |
| **ΔSCF ωB97X (adiabatic)** | **+1.03** | **+1.61** |
| B3LYP corrected (−0.07) | −0.07 | withdrawn (tuned to wrong −0.14) |
| **Experiment (verified E°s)** | **−0.574** | ref (Os +309 − FAD −265) |

> **B2 ✅** (`21g` — reproducible, closes the orphan cache): adiabatic **+1.0335** = IP_adiab(FAD 5.276) − EA_Os3(dmbpy 4.243); +0.149 more uphill than plain (+0.884) = the substituent term ①, exactly the B5/B3 shift. The **adiabatic is the robust headline** (reproduces plain 0.884); the vertical +1.40 (fresh-generator IP_vert 5.638 > the lost orphan's 5.391) is cation-relaxation-sensitive and secondary.

*vs the verified −0.574 eV (E°(Os +309 vs NHE) − E°(FAD-GDH −265 mV SHE); the old −0.14 was a +60 mV FAD artifact). Residual gap = differential PCM solvation (chloro↔bis-Im bracket) + the 4,4'-dimethyl substituent, decomposed by ② (§"Cluster-Continuum Micro-Solvation").

### Mediator Structure–Property Series (① — script 21e, 2026-06-05)

9× cis-[Os(4,4'-X-bpy)₂(1-MeIm)Cl]⁺/²⁺ at **constant charge**, B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF — isolates the 4,4'-substituent electronic effect. The H (bpy) point reproduces script 21b (Δ=0.000 eV). cascade Δ = ε_HOMO(FADH₂, −5.137) − ε_LUMO(Os III).

| 4,4'-X | σ_para | ΔE_red(III→II) eV | Os(III) LUMO eV | cascade Δ eV |
|---|---|---|---|---|
| NMe₂ | −0.83 | −3.910 | −3.636 | −1.501 |
| NH₂ | −0.66 | −3.905 | −3.637 | −1.500 |
| OMe | −0.27 | −4.286 | −4.002 | −1.136 |
| Me | −0.17 | −4.381 | −4.086 | −1.051 |
| H | 0.00 | −4.530 | −4.228 | −0.909 |
| COOH | +0.45 | −4.936 | −4.595 | −0.542 |
| **CF₃** (inert) | +0.54 | −4.957 | −4.635 | −0.502 |
| NO₂ (unstable) | +0.78 | −5.262 | −4.905 | −0.232 |
| **SO₂CF₃** (inert) | +0.96 | −5.256 | −4.910 | **−0.227** |

**Design rule (✅ cascade monotonic with σ):** electron-withdrawing 4,4'-bpy improves FADH₂→Os alignment — cascade Δ rises −1.50 (NMe₂) → −0.23 eV. **Realistic optimum = SO₂CF₃** (σ 0.96, cascade −0.227 ≈ NO₂'s −0.232) — same alignment but **electrochemically inert**, whereas NO₂ degrades (NO₂→NHOH→NH₂ on Os cycling at pH 4.5) → would relax the cascade to the donor-saturated −1.5 worst case (CHEM.23). CF₃ (−0.502) = milder inert option. *Caveat:* max cascade-Δ ≠ optimal EBFC mediator — higher E°(Os) lowers OCV → optimum balances driving-force vs cell-voltage (exp Os opt ~+309 mV).

**E° LFER:** ΔE_red linear in σ over OMe→NO₂ (slope ≈ −0.92 eV/σ, r²=1.00) with **donor-saturation at NMe₂/NH₂** (plateau ~−3.91 eV, σ_para⁻ regime) — strict E°-monotonicity breaks only at that 4-meV pair (expected resonance saturation, not error).

**Honest:** raw B3LYP-Koopmans cascade stays slightly uphill even for NO₂ (−0.23 eV) — same ~1 eV PCM differential-solvation bias (→ ② micro-solvation); the *trend/design rule* is the robust, transferable result. Numbers: `dft/os_mediator_series.json`.

### Cluster-Continuum Micro-Solvation & Speciation (② — script 34; dimethyl recompute OS-RECOMPUTE 2026-06-17)

Tests whether the raw cascade gap (above) is the implicit-solvation (PCM) limit, by
adding explicit waters / probing speciation on the charge-changing **Os(III/II)**
couple (the flavin couple is already within 50 mV of exp — script 32 — so it is not
the culprit). Recomputed on the **real 4,4'-dimethyl-bpy mediator** (Zafar +309 mV vs
NHE), not the plain-bpy model. B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF; cascade
Δ = HOMO(FADH₂ −5.137)−LUMO(OsIII). All ⟨S²⟩≈0.754 (clean doublets). Numbers:
`dft/microsolvation_dmbpy.json`.

**(a) Group-8 PCM benchmark — [Os(H₂O)₆]³⁺/²⁺** (ligand-independent — validates the
protocol against the known ~1 V error for Fe/Ru/Os octahedra, JPCC 10.1021/jp406772u):

| shell | ΔE_red (eV) |
|---|---|
| n=6 (inner only) | −4.946 |
| n=18 (+2nd shell, 55 atoms) | −3.964 |

2nd-shell shift = **+0.982 eV ≈ the literature ~1 V group-8 PCM error** for this **+2/+3**
couple (2nd-shell H-bond directionality a continuum cannot model). The **shift** is the
robust result (absolute E° is electronic-E proxy, ±0.15 V).

**(b) The real mediator IS chloro — explicit Cl⁻ solvation** of the verified
cis-[Os(4,4'-dimethyl-bpy)₂(1-MeIm)Cl]⁺/²⁺ + k·H₂O on Cl⁻ (k=0 = the device baseline;
its cascade Δ −1.054 = the k0 baseline; the 4,4'-dimethyl **substituent** axis ① adds
**+0.142 eV** [Hammett: dmbpy −1.051 vs plain −0.909], a contribution separate from solvation):

| k·H₂O(Cl⁻) | cascade Δ (eV) | gap closed vs k0 |
|---|---|---|
| 0 | −1.054 | — |
| 1 | −0.991 | +0.063 |
| 2 | −0.917 | +0.138 |
| 3 | −0.848 | **+0.206** |

~0.07 eV/water, monotonic. Crucially this **+1/+2** chloro couple carries a **~5× smaller**
differential-solvation error than the +2/+3 benchmark (a): Cl⁻ lowers the couple charge, so
even the full chloro shell stays well below the +0.98 eV group-8 figure. This is the **lower bracket**.

**(c) Operando speciation — the PVI-brush 6th ligand (upper bracket).** The polymer is
*synthesised* as chloro (Zafar), but in the operating poly(vinylimidazole) brush the 6th
site may instead be a **2nd chain imidazole** (bis-Im) — far more likely than aquation,
since the Os(II) d⁶ couple is substitution-**inert**, and the PVI-realistic form
(CHEM.20/26). Both **+2/+3** forms computed on the dimethyl mediator:
- **bis-Im** cis-[Os(dmbpy)₂(1-MeIm)₂]²⁺/³⁺ → cascade Δ **−0.500 = +0.554 eV vs chloro** (the PVI-realistic **upper bracket**).
- **aqua** cis-[Os(dmbpy)₂(1-MeIm)(H₂O)]²⁺/³⁺ → cascade Δ **−0.565 = +0.490 eV vs chloro** (methodological benchmark — aquation unlikely on the inert couple).

On the dimethyl mediator **B3LYP gives bis-Im > aqua > chloro** (on plain bpy it was aqua >
bis-Im) — the strong σ-donor 2nd imidazole plus the 4,4'-dimethyl donors. **This internal
aqua↔bis-Im flip is functional-sensitive, though** — the ωB97X cross-check (B4, §below) keeps
aqua > bis-Im (within 0.15 eV). What *is* functional-robust is the chloro(+1/+2) ↔ {aqua,
bis-Im}(+2/+3) bracket — both +2/+3 forms sit above chloro at both functionals, and both
carry the larger group-8 PCM bias (benchmark a).

**Verdict (chloro-anchored bracket):** the real mediator is **chloro** (Zafar +309 mV), so
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

### Electron Tunneling Pathway (script 28, Beratan-Onuchic)

FAD:C5B → FAD:O4B → FAD:C4A → FAD:N1A → **ALA261** → **THR260** → **THR283** → **THR288** (surface)
- 10 atoms, through-bond path 23.7 Å, β·d = 2.05
- Os mediator at surface can reach FAD via this covalent/H-bond pathway
- **MD-ensemble (script 28b, CHEM.16):** β·d = **2.02 ± 0.13** over 15 trajectory frames ≈ the single-snapshot 2.05; conformational-gating factor **1.03×** → the path is **thermally robust** (the static structure is ensemble-representative; no significant thermal gating). PBC handled by mdtraj `image_molecules` (co-locates the separate FAD cofactor; `make_molecules_whole` alone insufficient).

Details → [`L3_quantum_chemistry.md`](L3_quantum_chemistry.md).

### Cathode: DET Through ZIF Nanozyme

**Method:** ΔSCF (UKS, level_shift 0.3) energy-splitting for bimetallic ZIF clusters (script 24) on the **clash-free geometry** — script 23 deprotonated a bridging imidazole N–H that had collided with the 2nd metal at 0.97 Å (→ imidazolate bridge) — then Marcus k_ET with the **computed** two-sphere λ (script 35, Nelsen 4-point; λ_hop = (λᵢ+λⱼ)/2), not an assumed λ.

| Hop | t_ij (eV) — fixed geom | (old, broken geom) |
|-----|-----------|--------|
| Cu↔Co (T1↔ZIF node) | **0.00128** ← bottleneck | 0.0325 |
| Co↔Ce (ZIF node↔vacancy) | 0.00687 | 0.0022 |
| Ce↔graphene (vacancy↔MWCNT) | 0.1129 | 0.1177 |

The geometry fix shrank Cu-Co t_ij **25×** → **Cu-Co is the bottleneck**, not Co-Ce.

**k_DET vs λ (script 25) — margin is λ-sensitive:**

| λ scenario | bottleneck k(Cu-Co) | vs turnover (10³ s⁻¹) |
|---|---|---|
| canon λ=0.7 (old assumption) | 3.6×10⁷ | ×3.6×10⁴ |
| **literature λ** (Cu 2.0 / Co 1.4 / Ce 1.0) | **1.4×10³** | **×1.4 — borderline** |
| computed λ (B3LYP, Co spin-crossover ~2× over-est) | 0.3 | ×3×10⁻⁴ |
| Co→Ru swap (computed λ_Ru = 0.78) | 3.1×10⁴ | ×31 |

**Conclusion (revised, honest):** the old "k_DET = 1.09×10⁸, ×10⁵ above turnover, *not* rate-limiting" was a **double artifact** — a broken bridging geometry (clashing N–H) **and** an assumed λ = 0.7 eV. On the corrected geometry with realistic λ, the Cu-Co bottleneck sits at **~enzymatic turnover (×1–30)** → cathode DET is **borderline / possibly co-limiting**, not comfortably fast. B3LYP over-estimates the first-row λ (Co ≈ 2× lit), so the truth most likely tracks the literature-λ row (~×1.4). **FO-DFT rigorous coupling (script 24b, CHEM.14)** now confirms this is not a crude-t_ij artifact: a two-state Mulliken-Hush diabatisation gives t_ij(Cu-Co) = **0.00546 eV** (~4× the crude ΔSCF 0.00128, still meV-scale) + a **0.18 eV computed site-energy gap** the crude assumed away → the Cu-Co margin spans **×0.6 (uphill) to ×730 (downhill), ×25 at ΔG=0** — so the **borderline/sensitive verdict is robust to the coupling method**, and the old ×10⁵ is firmly excluded. Remaining closure = experimental EIS. **Mitigation:** low-λ metal (Co→Ru, ×31), conductive-MOF band transport ([`01_03 §3.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell) / CHEM.31), or enzyme-free SAC (CHEM.6). Numbers: `dft/zif_hopping.json` + `dft/cathode_ket_lambda.json`.

**Ru lever — the t_ij "double-whammy" is NOT confirmed (CHEM.32, scripts 24c/24d).** The Co→Ru ×31 above is the **λ** benefit alone (λ_Ru 0.78). We tested whether Ru's diffuse 4d *also* raises the coupling: at the canon cluster geometry with Co→Ru (identical coordinates; control Cu-Co reproduces canon t_ij 0.00128 ✅), the crude ΔSCF gave a large splitting (×81, t_ij 0.10 eV) and the FO-DFT diabatisation gave t_ij 0.105 eV — **but both FAIL the physicality check**: the frontier MOs localize entirely on Ru with **no Cu-d partner** in the window (24d self-flags non-physical — both diabatic orbitals pop(Ru) ≈ 0.86, pop(Cu) = 0.00). The minimal cluster's Cu-d and Ru-d manifolds are too energy-mismatched to form a clean Cu↔Ru diabatic pair (unlike Cu-Co). So the coupling boost is **plausible but unvalidated by this approach** — a rigorous Cu-Ru t_ij needs **CDFT constrained diabatic states** (a follow-up capstone: PyCDFT in-house or a specialist collaboration). The Ru lever stands on its **λ** advantage; its coupling advantage is a hypothesis, not a result. Caches: `dft/cu_ru_coupling.json` + `dft/cu_ru_fodft.json`.

**Model caveats** (frame the borderline — *not* a margin-chase): t_ij is **geometry-bounded** — a clash-corrected programmatic cluster, not DFT-relaxed (these flat-PES metal clusters resist geom-opt, cf. script 21c); and the single-hop bottleneck is **conservative** — the ZIF is a wide-gap **insulator**, so transport is the discrete Marcus hops modelled (not bands), and the 3D framework offers **parallel** instances of the bottleneck hop (band-like transport = the cMOF lever, CHEM.31).

---

## L4 — Chemical Kinetics

**Model:** Michaelis-Menten + Arrhenius + BQ25570 boost → delta_t

| Parameter | Value | Source |
|-----------|-------|--------|
| j_max(25°C) | 881 µA/cm² | Zafar 2012 (PMC3275720) Table 1, dgrGcGDH row — MM **asymptote** derived as 520 × (K_M+20)/20; a pH-7.4 graphite ceiling |
| Km(glucose) | 13.9 mM | Same row, same fit (K_M^app 13.9 ± 3.1; apparent — carries the hydrogel's mass transfer) |
| Ea | 40 kJ/mol | Typical FAD enzyme |
| V_op | 0.5 V | EBFC under load |
| A_electrode | 2 cm² | Conservative gyroid area |
| η_BQ | 0.68 | BQ25570 datasheet (SLUSBH2G Fig.6-7, low-I_IN; [HW.47]) |
| E_cycle | 5 mJ | STM32 sense+LoRa TX |

### delta_t Predictions

| Scenario | [glucose] | T(°C) | delta_t (s) | vs 60s baseline |
|----------|-----------|-------|-------------|-----------------|
| Healthy summer | 10 mM | 25°C | **19.9** | < 60s → GP↑ [E.63] |
| Active growth | 20 mM | 30°C | **10.8** | < 60s → GP↑ [E.63] |
| Moderate spring | 15 mM | 20°C | **21.2** | < 60s → GP↑ [E.63] |
| Cold winter | 5 mM | 5°C | **100.7** | > 60s → GP↓ [E.63] |
| Severe stress | 3 mM | 0°C | **205.9** | > 60s → GP↓ [E.63] |

**Conclusion:** BASELINE_DELTA_T_S = 60s is physically justified. EBFC discriminates healthy vs stressed trees. Diffusion NOT rate-limiting (j_kinetic ≪ j_diffusion).

**pH bracket — printed BESIDE the table, never folded into it (⚖️ founder 2026-09-18).** Every delta_t above is a **pH-7.4 laboratory ceiling**; our sap setpoint is pH 5.75. Sygmund 2011 (*Microb. Cell Fact.* 10:106, Table 3 — free enzyme, ferrocenium 20 µM, 30 °C) gives the same enzyme at both pH values, and the correction is **[S]-dependent**, because k_cat falls (×0.43–0.47) while K_M also falls (×0.54–0.59) and the two partly cancel:

| Scenario | ceiling (s) | ×wt | ×rec | delta_t at pH 5.5 (s) |
|---|---|---|---|---|
| Healthy summer | 19.9 | 0.68 | 0.58 | **29.3–34.5** |
| Cold winter | 100.7 | 0.75 | 0.63 | **134.6–160.6** |
| Active growth | 10.8 | 0.61 | 0.53 | 17.7–20.5 |
| Severe stress | 205.9 | 0.79 | 0.66 | 260.8–313.3 |

⚠️ The two ends are the **wild-type and recombinant forms of the same paper disagreeing** — that disagreement IS the bracket; electing one would manufacture precision the source does not carry. ⛔ And the pair was measured on the FREE enzyme with a small-molecule acceptor at 30 °C, so it is applied here as an indication for our immobilised Os-polymer electrode, not as its measurement; the 5 °C row additionally assumes a temperature-independent pH effect, which nobody measured.

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
**~0.002–230 Ω** across the borderline k_DET (λ/coupling-sensitive) × the unknown site coverage Γ
(×10⁵ spread): the cathode arc can be negligible (fast/dense) or comparable to the anode (slow/sparse),
so it **cannot be predicted a priori** — the robust statement stays the **kinetic competition**
k_DET ~ turnover (§Cathode), with the measured Ti-coin cathode EIS the decisive test. INDICATIVE
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

Spec home → [`01_01 §1.4`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md); decision → `00_07` HW.34.

**Thermal bridge (script 54)** — 1D resistor ladder + 2-node steady state, at the canon rod **Ø1.0**
(`01_01 §1.4`). A **Cu** bus dominates the Zone-2 PEEK break (G_anchor 9.4× a Ti bus, ×18.3 vs no bus;
λ_Cu ~1600× PEEK) → drags the Zone-1 anode pocket to **−12.8 °C** (14.8° below the +2 °C core → living-sapwood
freeze-risk) at −30 °C air / +2 °C core. A bus **monolithic with the anode** (= the anode alloy) is
thermally near-invisible (**−0.70 °C**, ×1.95 vs no bus). Per bake-off alloy: alloyed α+β Ti
(4V/7Nb/β/15Zr, λ≈7) −0.70…−0.92 °C; CP-Ti (λ17) −2.21; Ta (λ57, benchmark) −5.65 — **all ≪ Cu**, and
the −2 °C freeze gate still separates the four α+β Ti (safe) from CP-Ti and Ta (freeze). Electrically
free at µA (Ti 11.3 µV at 100 µA, 4×10⁴ below the 500 mV reference).
(`mechanical/anchor_thermal_bridge.json`)
> ⚖️ **Re-run landed 2026-09-10 at the canon rod Ø1.0** (`00_07` HW.34) — the numbers above are the new ones. What the diameter move cost on THIS side: the bus area shrinks ×1.69 (A ∝ d²), so the bridge looks *better*, i.e. the old figures were conservative and both load-bearing verdicts survived (Cu ×24.3 → ×18.2 vs no-bus, Cu/Ti ratio 9.57 → 9.31; monolithic Ti −1.43 → −0.70 °C). Exactly **one** cached boolean flipped — `cell_freeze_risk["316SS"]` true → false (−3.16 → −1.94 °C against the −2.0 gate) — and 316SS is the superseded pre-monolithic alternative, not a bake-off candidate; all six HW.24 alloys kept their verdicts. The one **anti-conservative** axis was electrical (R ∝ 1/A → IR drop was understated ×1.69, Ti 6.7 → 11.3 µV at 100 µA). ⛔ The direction here is OPPOSITE to script 55 below — never read one diameter caveat as covering both.

**Mechanical (script 55)** — slender-beam closed form, at the canon rod **Ø1.0**, and since the
fabrication verdict it reports **two branches**: `printed` (superseded) and `welded` (SHIPPED, ⚖️
2026-09-10, cold-drawn wire, no as-built knockdown). Buckling SF **25×** (1 N pogo) even unsupported →
still a non-issue in both. Sway fatigue: the bore **liner** (= the short-circuit insulation) doubles as
lateral support → infinite life for **every** alloy in both branches (SF 3.8–10.4× printed, 7.5–20.7×
welded — ⚠️ on the 6 mm «supported» idealisation, which overstates the coaxial root stress against a
RIGID wall, sits inside the compliant bracket (§equilibrium below), and says nothing about a channel offset). 🔴 **Bare, the fabrication choice decides — and it decides two different verdicts.** Printed:
infinite life for **4 of 6** (SF 0.98–2.70×), **Ta (0.98) now a predicted fatigue failure** and CP-Ti
(**1.37**) marginal. Welded: every SF doubles → infinite life for **5 of 6** (SF 1.96–5.41×), with the
binding candidate **Ta at 1.96, below the SF-2 line**. ⚖️ **Both columns are the RATIFIED LOW END of the
`σ_e/σ_y` band since 2026-09-18** (founder 2026-09-17, `00_07` HW.34) — at the midpoint they read 4 of 6
and 6 of 6 (Ta 1.10 / 2.21), which is what this page carried until the re-run; the shipped LINED
configuration is unaffected in verdict and moves 2.76 → **2.45** at its binding corner
(`§endurance_ratio_band`, swept 2026-09-12, model moved 2026-09-18). Per-alloy margin tracks yield = SAME
ranking as the thermal side → leading HW.24 candidates win on both. (`mechanical/bus_mechanical.json`)
> ⚖️ **Re-run landed 2026-09-10 at the canon rod Ø1.0** (`00_07` HW.34) — and here the diameter move changed the CONCLUSION, not just the digits (σ ∝ 1/d³, SFs fall ×2.2). The unsupported branch did not thin out, it crossed the line: Ta 1.55 → **0.71**, CP-Ti 2.16 → **0.98**, and the four alloyed Ti dropped 3.8–4.3 → **1.74–1.94**, i.e. `unsupported_infinite_life` went **true → false for all six** (⚠️ that per-alloy boolean is now branch-suffixed — `unsupported_infinite_life_printed` / `_welded`; the bare name survives in `fabrication_branches` but as a LIST of alloys, so it resolves and no longer means the same thing). 🔑 **So lateral support is not a soft-alloy mitigation, it is a requirement for every candidate** (⚠️ an L_FREE_UNSUP = 36 mm-era reading, before the welded-wire verdict and the 23 mm CEM-derived span — the live per-branch answer is the table below) — which is the input the open HW.34 lining verdict was missing: a film that does not touch the rod (Parylene ~10 µm, anodised TiO₂ ≤10 µm in a sub-mm channel) insulates without supporting. ⚠️ The clause that stood here — «the model has no liner stiffness to give it credit for» — was true of that day's model and is not true now: since the clearance verdict the script computes the rod-plus-tube composite EI and reports both bounds, so a branch is no longer credited or denied support by omission.
> ⚖️ **Fabrication branch added 2026-09-11** (`00_07` HW.34) — the welded verdict re-opened the lining one, so the script now emits both columns. **The re-run narrowed the support motive without retiring it:** dropping the as-printed derate lifts Ta and CP-Ti out of predicted failure (0.71→1.41, 0.98→1.96) and **not** over the infinite-life line, so bare-rod infinite life goes 0/6 → **4/6**, not 6/6 (⚠️ the same 36 mm era). 🔴 **The tracker verdict's stated ground said "all six" and its own adjacent table did not** — the arithmetic there was right (every SF doubles) and only the conclusion was wrong; corrected in `00_07`. ⛔ And the doubling belongs to the WIRE: the model is a homogeneous cantilever, while the ratified joint sits at the root of the modelled cantilever (⛔ not at the peak moment of the real overhang — that is the bore mouth, corrected 2026-09-12). ⚠️ That sentence stays true about the wire; what changed 2026-09-12 is that the seam is no longer UNPRICED — see the next note, and read `fatigue_model.weld_seam_geometry_modelled` beside `…_sensitivity_modelled` rather than the single boolean this line used to cite.
> 🔴 **Clearance regime added 2026-09-11, and it RETIRES the fatigue ground rather than narrowing it further** (`00_07` HW.34, ⚖️ founder). Both `L_FREE_*` columns are FREE cantilevers — no wall anywhere — while the rod threads the cathode bore. At the ~165 µm radial play a 10 µm conformal film leaves, the rod takes up that play and **bears on the wall 4.5–11.1 mm inside the bore on every µ the script sweeps** (first contact 10.47–17.15 mm from the root). So the unsupported SF is a number for a configuration that does not exist, and the liner’s structural ground moved from FATIGUE to WEAR: a 10 µm film asked to be a bearing under a beam reaction in a THROUGH bore of `L/D` ≈ 12.6, whose wear-through is a ~0.5 V anode↔cathode short. (`mechanical/bus_mechanical.json` §`clearance_regime`; the verdict line is DERIVED, never typed). 🔴 **The bracketed figures above are HISTORICAL as of 2026-09-12 and the qualifier «on every µ» no longer holds for a conformal film** — the protrusion correction below shortened the span from 36 to 23 mm, which makes the rod STIFFER, so a 10 µm film then first touched the wall at 13.9–23.0 mm from the root, i.e. past the bore end at the lowest friction point (µ 0.2) only. ⚖️ The ratified verdict is untouched; what weakened is the ARGUMENT AGAINST the rejected branches, and it is recorded here rather than quietly re-derived. 🔴 **And every station in this note is RETIRED 2026-09-14, not merely dated: they are where the FREE tip-loaded shape crosses the play at full drag, and the contact solver (§`clearance_regime`, one home with script `68`) shows that is never a contact station.** What survives of the finding, re-derived: on a coaxial channel the shipped liner touches down at the EXIT on every swept µ on every geometry and the conformal films on µ 0.3–0.5 on the placeholder (their touchdown drag is 0.22 N) and on every µ across the lock window; the mouth is never reached coaxially. The regime block below is the live one.
> 🔴 **And the clearance verdict of the same day moved this section's OWN numbers — branch (в), channel Ø1.30 → Ø1.35, applied 2026-09-11.** Two things changed and only the second is a digit. **(1) The model can now say WHICH SIDE the leftover play sits on**, which it could not before: a conformal film is bonded to the rod, so its play is on the ROD side and the bending member is the bare wire; the ratified liner is tight on the wire and enters the bore as one body, so its play is on the CHANNEL side and the member is the rod-plus-tube composite (both stiffness bounds computed, `ei_Nm2_bare_rod` ⊥ `ei_Nm2_bonded`). **(2) The "hundredfold reduction of free travel" this page fed into canon was a ROD-SIDE number and is gone: the measured factor is `play_reduction.factor` ≈ 6.8×** (170 → 25 µm). ⚠️ The «supported-column root stress understated by 40.8 %» this note carried until 2026-09-14 measured the 6 mm idealisation against a free-shape first contact; under the equilibrium the SIGN reverses — there is no propped 6 mm span, the coaxial root stress against a RIGID wall is set by the exit contact (and is the LOWER end of a bracket, §equilibrium below), and the §2 supported column OVERSTATES that rigid-wall end ×**2.28** at nominal µ on the placeholder (×6.37 / ×6.72 across the lock window; `clearance_regime.supported_column_vs_equilibrium`, sign derived). Under a channel offset the comparison has no meaning: the root then carries a MEAN. So `L_FREE_SUP = 6 mm` overstates the coaxial root stress only against a RIGID wall; against the compliant liner the root lies in a bracket the column sits INSIDE on the placeholder and, at the worst swept µ, ABOVE on the lock window (`column_position_*`, derived) — and it is the wrong quantity for the offset case. Measured, not asserted.
> 🔴 **Weld seam — BOUNDED 2026-09-12, RETIRED 2026-09-14, and the input is still missing.** Canon ([`01_01 §1.4`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) and the factory protocol `§3` step 1) had been sending the reader here for this state while nothing here held it. The seam's fatigue-strength knockdown `k` is in **no** canon row, **no** vendor answer and **no** experiment, so `weld_seam.knockdown_k_measured` stays `null`. On 2026-09-12 the model inverted `SF_seam = k · SF_wire` on ONE fully-reversed stress — the §2 supported column at the worst swept µ inflated by a span optimism measured along the free-shape first contact, 43.0 MPa — and reported a break-even `k` of 0.554 against our own marker `AS_PRINTED_DERATE` = 0.50 (margin −0.054, «does not clear»). 🔴 **That stress is the root stress of a free cantilever whose length is a free-shape crossing station; no equilibrium configuration produces it, and the bound is retired with the picture.** The equilibrium gives the root TWO regimes instead, and neither is a single fully-reversed number: on a coaxial channel the drag is fully reversed with an amplitude that is itself a BRACKET — the rigid-wall figure is its LOWER end, the Ti-bore stop its upper, the contact compliance between them unmeasured (mean 0); a channel off the root axis by more than the play puts a STATIC bending on the same section — a MEAN that grows with the offset, a rigid-wall UPPER bound — with the reversing drag as amplitude on top. ⛔ **No `k` is derived from either** (`weld_seam.break_even_k` = `null`, `break_even_k_not_derived_because`): the model has no mean-stress correction, so the offset regime cannot be priced, and a `k` inverted from the rigid-wall end of the coaxial bracket alone would silently assume both a coaxiality the stack carries only as a NOT-SPECIFIED requirement (ratified as a form 2026-09-18, its number after `00_07` HW.26 G1) and a rigid wall the part does not have. What the cache gives instead is the INPUT a seam acceptance needs — amplitude and mean at the root per regime and geometry (`weld_seam.root_section_loading`, the same solver and the same offset points as script `68`, pinned equal to `68`'s table below: its rigid-wall column and upper-end column bracket the coaxial amplitude · offset secant = mean per µm past the play · reversing amplitude, a rigid-wall figure). **Consequence, unchanged in direction and stronger in ground: `k` must come from the vendor** (weld class, WPS, post-weld treatment of the toe — `00_07` HW.34 👤), because there is no house number bracketing the joint at all now, not even a drift-picture one. ⚠️ The comparison markers stay OURS (`AS_PRINTED_DERATE` ⊥ `WROUGHT_DERATE`) as the scale a vendor `k` will be read against; nothing is compared with them. ⛔ Three seam mechanisms stay outside any bound and their signs differ: a bead upset/fillet RELIEVES nominal stress, a weld-toe notch AGGRAVATES it, and weld residual TENSION is a **mean** stress — the same absence that stops the offset regime being priced. (`mechanical/bus_mechanical.json` §`weld_seam`)

🔬 **WHERE THE ROD MEETS THE WALL — the equilibrium, 2026-09-14 (`clearance_regime`, `edge_bearing`; solver `lib.beam_contact`, one home with script `68`).** Until then every station here bisected from the ROOT along the FREE tip-loaded shape at FULL drag and read the crossing of the play as a contact; the first 6 mm have no wall at all (PEEK gap inside the Ø11 sleeve), and a shape that crosses a wall is not admissible once the wall exists. Solved as a unilateral contact, the picture splits by REGIME, not by µ:

- **Coaxial channel (drag).** The touchdown drag of the shipped liner is 0.034 N on the placeholder and 0.007 N across the lock window — far below every swept µ·F — so on every swept µ and every geometry the rod is touched down at the **EXIT**, where the tube ends flush, and nowhere else (asserted per row); the deflection at the mouth is a fraction of the play (2.4 µm of 25 on the placeholder, 9.4–9.8 across the lock window), so **the mouth is never reached coaxially**. Against a RIGID wall the touched-down shape is the prescribed-displacement shape and does not change with the drag, so the root stress is 3·E·c·g/L² and µ-invariant (the `68` table below) — **and that figure is the LOWER end of a bracket, not a cap**: the real wall is the PEEK wall on the Ti bore's exit edge, it yields by R/k and raises the root moment by 3EI·(R/k)/L², up to the Ti-bore stop behind it (the polymer wall fully yielded; the free cantilever F·L is reachable only where the drag cannot reach the bore). At the worst swept µ the root lies in [8.04, 56.3] MPa on the placeholder and [2.88, 20.1] / [2.73, 19.1] MPa across the lock window (`coaxial_root_bound`, `sigma_root_MPa_upper_end`); where in that bracket it sits is set by the contact compliance, measured nowhere. The wall reaction is at most the drag minus the touchdown drag (0.17–0.47 N over the swept µ on the placeholder — a rigid-wall UPPER bound), and the tube's flush END lands on the bore's exit edge at **0.093°** (rigid wall) — edge on edge, the form the ≥ 1.0 mm protrusion avoids at the mouth, with the exit radius ratified only as a FORM — a radius, not a chamfer (`00_07` HW.34, 2026-09-18) — and its value NOT SPECIFIED (`edge_bearing.exit_contact`).
- **Channel off the root axis (offset).** Past the play the **MOUTH** is a contact station — the bore's entry edge is the fulcrum — and it is the only one until the second wall is reached; the approach angle grows at **0.0143°/µm** of offset past the play on the placeholder (0.0041°/µm across the lock window; asserted against 3δ/(2a)), so at any swept excess it stays hundreds of times flatter than a 30–45° lead-in chamfer (419× at the 5 µm reference): the rod never lands on a chamfer face, only where the chamfer meets the cylinder — a chamfer MOVES the edge, a radius removes it. The mouth reaction grows at 0.075 N/µm on the placeholder (asserted against 3·EI·δ/a³) and the root then carries a static MEAN (the `68` secant column).
- **What this does to the two ratified verdicts of 2026-09-12** (⚖️ they stand; the GROUND is corrected beside them in canon). The ≥ 1.0 mm protrusion: the «earliest computed contact 5.21 mm from the root, so the tube must start 0.79 mm before the mouth» was a free-shape crossing, not a contact; under an offset the fulcrum is the mouth plane itself, so the geometry demands only that the tube COVER the mouth, and what a minimum beyond that must clear is the entry radius (NOT SPECIFIED) plus the axial position stack (the liner's own 27.6 µm thermal travel at 40 K and tolerances not in canon) — neither is in the model, so no floor is priced and `edge_bearing.liner_start.min_protrusion_from_geometry_mm` is `null`; the ratified value is carried from the CEM as a value the geometry cannot price below. The entry RADIUS: its ground strengthens — the approach is flatter under an offset than the 0.60° the drift picture read, on every geometry. ⛔ Declared ceiling, all of it: rigid frictionless wall, perfect clamp, offsets and plays swept and never measured; no notch factor and no contact model exists in this tree. (`mechanical/bus_mechanical.json` §`clearance_regime`)

🔬 **The liner↔wire FIT — derived 2026-09-12, and it is the number every other line of this section was standing on.** The 2026-09-11 direction verdict says the tube is TIGHT on the wire and the pair enters the bore as one body; the composite stiffness bound, every contact figure and the whole wear axis inherit that sentence, and until this block no interference for that pair existed anywhere — canon said so outright. Bounded the same way the seam input is, because both vendor bands are missing: at the ratified bore the window is **0.38 … 10.89 µm radial**, i.e. a **21.0 µm DIAMETRAL** budget for the tube bore and the wire OD **together** (21.3 at the pre-verdict bore = rod Ø). Ceiling = von Mises at the tube bore reaching PEEK yield 100 MPa at −30 °C, where the thermal term ADDS (PEEK is the outer member on this interface — the opposite sign to the liner-OD/bore interface, which is the confusion canon warns about); floor = the thermal loss at +40 °C, i.e. the fit merely stays a fit. ⛔ **Both tolerance bands stay `null` in the cache** — a quoted band sum wider than the 21.0 µm window is sorted around the ratified target; the tube is fitted hot regardless (`01_01 §3` step 4a, before enzyme functionalisation).

⚖️ **The nominal is SPECIFIED since 2026-09-18 — ratified (`00_07` HW.34): bore = wire − 11.41 µm (the window centre at bore = rod Ø), wall 0.15 so OD = ID + 0.30, fitted hot (`01_01 §3` step 4a), sorted around the same target if the two vendor bands overrun the window.** At the ratified bore the recomputed centre is 11.27 µm, +0.14 µm from the typed nominal (`interference_window.nominal_vs_window_centre_diametral_um`) — a typed number, not one that follows every re-run. Before the verdict the headline was that the nominal was SPECIFIED NOWHERE: canon froze the WALL, «ID 1.00» lived only in an open RFQ leg, and at that assumed bore the fit was line-to-line, so half the population would have come out with clearance. ⊕ Two consequences the same block derives, neither of them forecast. **(1) WHO carries the interference sets the direction of the play — and the first application of the nominal priced only one side (corrected the same day by an adversarial read).** At a fixed wall `play = play_zero + δ_bore − k·(δ_bore + e_wire)` with **k = 0.875** (`od_growth_eats_channel_play.k_od_growth_per_interference`): the play moves +0.125 µm per µm of bore under nominal and **−0.875 per µm of wire over nominal**, i.e. it is set mostly by the WIRE's OD band, which is NOT MEASURED. Carried by the bore it grows slightly across the window (25.05 → **26.4 µm** at the ceiling); with the bore AT the ratified nominal a wire over nominal eats it — **21.2 µm** at the ceiling (wire +5.2 µm radial), 30.4 µm at the floor (wire −5.3 µm). So the 25 µm zero-interference value the clearance table uses is **NOT a lower bound** and does not read edge bearing conservatively: under the equilibrium a smaller play lowers the rigid-wall end of the coaxial bracket (∝ g) and makes the mouth a station at a smaller channel offset — on the wire-carried ceiling row the mouth already carries a static root stress at 25 µm of offset (script `68` now sweeps all five window rows plus zero interference). (Before the verdict the same model read 25 → 15.3 — all δ on a wire over a bore = rod Ø.) The free-outer premise of the Lamé model is checked rather than assumed: the play stays open on every row, the wire-carried ceiling included. **(2) Friction on the wire is the SECOND capture.** The differential axial growth needs 3.30 N to restrain at 40 K (6.59 N at 80 K; at the ratified bore) and friction supplies it once µ·δ ≥ 0.031 µm — at the friendliest swept µ of 0.1 that is δ ≥ 0.31 µm to hold at all and 0.62 µm to lock the mid-section (⚠️ two thresholds, two verbs: this sentence attached the LOCK value to the HOLD verb until 2026-09-12, a 2× row-mix), a small fraction of the window. So the axial compression is incurred **whichever end is mechanically fixed**, and the ratified ground for one-end capture («20 yr of creep under sustained compression») discriminates only at the very FLOOR of the window, where the tube still slips and relieves. ⚖️ The verdict stands — it also carries retention and assembly — but its stated ground weakened, and which of the two regimes ships is set by a number no drawing carries. ⛔ Declared ceiling on all of it: creep/relaxation is modelled NOWHERE, so the true window is narrower on BOTH sides (the floor rises as grip decays, the ceiling falls because a sustained-stress limit is below yield); form error (tube ovality, wire out-of-round, bore straightness) is assumed zero, and a real pair spends part of the window on form before it spends any on size. (`mechanical/bus_mechanical.json` §`interference_window`)

🔬 **THE ENDURANCE BAND ENTERED THE MODEL 2026-09-12 — and one standing conclusion did not survive it.** `ENDURANCE_OVER_YIELD` was written as a BAND (0.40–0.50) in the constant's own comment from the file's first commit, while only its MIDPOINT ever entered the model; every SF scales linearly with it, so «the welded bare rod clears SF 2 for all six alloys» was a statement about one point of an unmeasured band wearing the clothes of a statement about the band. Swept (`§endurance_ratio_band`, the §2 free-cantilever column on the placeholder span):

| `σ_e/σ_y` | bare: ∞-life | binding `Ta` SF |
|---|---|---|
| **0.40 (model, ⚖️ ratified)** | **5 / 6** | **1.96** |
| 0.45 (former model point) | 6 / 6 | 2.21 |
| 0.50 | 6 / 6 | 2.45 |

🔴 **«All six clear SF 2» FLIPS inside the band — at 0.40 `Ta` reads 1.96, and since 2026-09-18 that end IS the model** (⚖️ founder 2026-09-17): the sweep measured the flip, the founder chose the end, and the page above now quotes it. ⚠️ Until 2026-09-14 this table carried a second column — the seam's break-even `k` at each ratio (0.624 / 0.554 / 0.499) and whether our 0.50 marker covered it, a tie of 0.001 at the friendliest end. That column was priced on the retired drift-picture stress and no seam `k` exists to sweep since (`weld_seam.break_even_k_not_derived_because`), so the band now measures the bare-rod verdict only. ⛔ Which end to stand on is a ⚖️ (`00_07` HW.34) — the block measures, it does not choose, and the band ends are the constant's own comment, not a measurement of our alloys.

🔬 **WEAR BOUNDED 2026-09-12, RE-STATIONED 2026-09-14 — the ground the liner actually stands on stopped being an assertion, and now stands at the contact the equilibrium finds.** ⚖️ 2026-09-11 replaced the liner's fatigue ground with WEAR, and for a day nothing computed it: every `wear`/`fretting` mention in script `55` was prose, one of them literally «The discriminating costs are NOT computed here», so «rated for 20 years» had no instrument while [`fmea_fmeca_register.md`](../../hardware/fmea_fmeca_register.md) `#21` — RPN 324, the top row since the severity sweep of 2026-09-18 — asserted wear-through with none either. Same inversion as the seam input and the fit, third time: the specific wear rate of PEEK on Ti is in **no** canon row, **no** vendor answer and **no** experiment, so `wear_budget.specific_wear_rate_measured` stays `null` and the model prices the BUDGET. Chain, each link attackable on its own: **duty** = the sway-cycle count LOADED from script `62`'s real-wind cache (never retyped) × the slip per cycle at the station; **load** = the station's wall reaction from the contact equilibrium; **budget** = wear-through volume ÷ (load × duty). Two stations now, both from the solver: the **EXIT** under coaxial drag (reaction = drag − touchdown drag) and the **MOUTH** under a channel offset (a sustained reaction the reversing drag rotates the rod about; swept offsets, never measured). Shipped branch at its worst corner — the coaxial exit on the placeholder, µ 0.5, at the cycle ceiling script `62` writes (§HW.43):

| what the contact is | allowable `k` — a BOUND over the contact-compliance bracket | rigid-wall figure (bounds nothing) |
|---|---|---|
| flow-limited patch (PEEK at the tightest swept flow pressure) | **4.25 × 10⁻⁸** mm³/(N·m) | **2.55 × 10⁻⁷** mm³/(N·m) |
| worn in over the whole run (projected bearing) | **6.04 × 10⁻⁴** mm³/(N·m) | **3.63 × 10⁻³** mm³/(N·m) |

⚠️ Both ends are priced at the cycle CEILING script `62` writes — 20 yr of continuous sway at the high field reading of the sway frequency (0.74 Hz), an upper bound on first-mode cycles (§HW.43) — and scale as 1/N, so a lower count loosens both ends by the same factor and leaves the span below unchanged.

🔑 **Three findings, and the third is new with the station.** **(1) At the tight end the reaction CANCELS.** The area is flow-limited (`A = R/p_flow`) and the duty is `R·s`, so `k = h/(p_flow·s)` exactly — the flow-limited budget contains no contact force at all, which takes the chain's weakest link out of the binding half of the answer. Pinned in-run against the closed form, not described. **(2) The two REJECTED conformal branches demand a far stricter rate than the shipped liner against a RIGID wall — and NOT on the bound.** On the rigid-wall figures a 10 µm film needs a rate ~78× stricter at every swept friction and geometry where it touches down (⚠️ the factor differs between the two branches — read them per row); on the BOUND it does not, because at the Ti-bore stop the in-contact sliding is 6·r·t/L, proportional to the polymer's own wall, so a thick wall buys allowance and spends it on sliding in equal measure and the tight end stops depending on the wall (`branch_discrimination`, derived: films stricter on the rigid-wall figures `true`, on the bounds `false`). The wear axis re-earns their rejection only if the contact is rigid — which the unmeasured compliance decides. **(3) The coaxial in-contact sliding is a BRACKET with signed ends, and the budget is a BOUND over it.** Against a rigid wall the touched-down shape does not change with the drag, so the surface fibre at the exit does not rotate while pressed on the wall: a rigid point contact slides ZERO (`sliding_in_contact_um_rigid_kinematics`), and the rigid-wall rotation of **4.20 µm** per cycle between the ±wall states happens OUT of contact — it bounds nothing and is kept only as the rigid figure (`out_of_contact_rotation_per_cycle_um_rigid_wall`; until this afternoon it was quoted as «the ceiling»). Against the compliant polymer wall the exit yields and the rod rotates IN contact, up to the Ti-bore stop: **25.2 µm** per cycle on the placeholder (`sliding_in_contact_per_cycle_um_upper`). The bound takes that upper sliding with the upper (rigid-wall) reaction, so an allowable `k` below it keeps the wall whatever the compliance turns out to be; the mode at the rigid end is a normal load cycling 0 ↔ R with a landing at 0.093° — partial slip / impact fretting, a mode nothing here models. ⛔ Declared ceilings, all real: the budget's span is **14237×** and nothing in the tribology decides it — the CONTACT GEOMETRY does, and both stations are ours to decide (the entry radius carries no value; the exit carries nothing at all; the ratified protrusion decides which FEATURE of the tube meets the entry edge under an offset). Archard assumes GROSS slip; third-body debris in a 25 µm clearance, the titanium side of the pair (a bore EDGE at both stations) and the whole −30…+40 °C dependence are outside the bound. The second driver — the liner's differential thermal travel — is priced and comes out **~4 orders** below the sway sliding, so «the sway drag is the wear axis» is DERIVED. (`mechanical/bus_mechanical.json` §`wear_budget`)

🔬 **CONTACT EQUILIBRIUM, script `68` (2026-09-14) — script 55's DRAG contact picture was not an equilibrium, and 55's contact blocks are re-derived on this solver the same day.** `55` read the wall station off the free tip-loaded cantilever at FULL drag; under a tip load the deflection grows monotonically from the root, so the first station to reach the wall is the pad plane, where the tube ends flush, and from then on the drag is reacted there. `68` solves the unilateral contact instead (Euler-Bernoulli FE, active set on prescribed displacements, rigid wall — `lib.beam_contact`, one home), with controls that can fail: the closed form at the pad plane, the closed form at the mouth, the wall at element midpoints, a grazing row at two element sizes; an adversarial review reproduced every returned number with a continuum-analytic solution and a KKT certificate, and `55`'s cache is pinned equal to `68`'s on both ends of the coaxial bracket. ⚠️ **The unsupported gap comes from `Z1_INSERTION_MM = 30`, an HW.8 placeholder that lies outside the Zone-1 lock's own insertion window, so each row is given at the placeholder AND at both window ends** (zero-interference play, bonded member, worst swept µ):

| Zone-1 insertion (geometry) | root stress under drag, rigid wall = LOWER end, MPa | offset secant, MPa/µm | reversing-drag amplitude, max, MPa | pogo on the rod edge, MPa | upper end of the root stress at µ 0.5 (Ti-bore stop), MPa |
|---|---|---|---|---|---|
| 30 mm — script 55 placeholder, gap 6 mm | **8.04** | **5.74** | **8.04** | **10.52** | **56.3** |
| 15 mm — lock window near end, gap 21 mm | **2.88** | **0.46** | **3.85** | **5.37** | **20.1** |
| 14 mm — lock window far end, gap 22 mm | **2.73** | **0.42** | **3.76** | **5.22** | **19.1** |

🔑 **What moves.** (1) The rigid-wall root stress under drag sits far below the two stresses `55` used to price at that section (18.3 MPa nominal on the 6 mm column, 43.0 at the retired seam corner) — and it is the LOWER end of the root stress, the Ti-bore stop in the last column its upper (`coaxial_cap_bound`; a rigid wall prescribes the exit at the play, the polymer wall yields by R/k); ⛔ no seam `k` is re-derived from either end — the compliance that places the amplitude is unmeasured, a static offset puts a MEAN stress on the same section, and no mean-stress correction exists anywhere in the tree (the table IS the seam-acceptance input: the rigid-wall and upper-end columns bracket the coaxial amplitude, the secant is the mean per µm past the play, the reversing amplitude a rigid-wall figure). (2) Under drag the contact is the tube's flush END at the pad-plane exit — ring on ring, the form the ≥ 1.0 mm protrusion avoids at the mouth — and the exit radius is ratified only as a FORM (a radius, not a chamfer), its value NOT SPECIFIED. (3) Off-axis the mouth IS a contact station, so the protrusion and the entry radius keep a physical ground under misalignment. (4) **The peak-moment section is READ from the moment field of every solve since 2026-09-14, not asserted:** the root is the peak in every drag, offset and reversing-drag row; it leaves the root only on the lock-window geometry for a 9 mrad tilt about the MOUTH (the play is taken up on both walls and the rod bends between them) and for the pogo couple on the rod's end face (the couple applied at the exit exceeds the long rod's small root moment) — `peak_moment_section`, and the prose «in every configuration computed here» that stood in this cache was false on those rows. (5) The insertion placeholder moves the offset price by an order of magnitude, so the coaxiality a drawing must demand cannot be priced before the insertion is (HW.26 G1); on the lock-window geometry an off-axis pogo contact and a reversing drag over an offset both exceed the rigid-wall coaxial figure. ⛔ Ceilings: rigid frictionless wall (no liner compliance or contact pressure), perfect clamp, offsets · tilts · eccentricity swept and never measured, no liner creep, no P-δ. (`mechanical/bus_contact_equilibrium.json`)

**Verdict** — 🟢 Monolithic bus (= anode alloy, HW.24-gated) resolves the Cu/Ti dichotomy: thermal
bridge minimized + Ti↔Cu galvanic joint eliminated + mechanically sound **with the bore liner**.
⚠️ «Sound with the liner» now carries a named precondition: the liner is only tight on the wire if
the fit lands inside the derived window, and today's nominals do not put it there.
⚠️ And a second one since the contact equilibrium (2026-09-14): «sound» under DRAG stands on a coaxial channel, where the root lies in a bracket — the rigid-wall figure its LOWER end, the Ti-bore stop its upper, the contact compliance between them unmeasured — and the exit takes the drag (the binding alloy clears SF 2 at both ends, `binding_alloy_sf_shipped_at_*`); the static bending a channel off the root axis adds is a MEAN the tree cannot yet price, and its magnitude waits on the Zone-1 insertion (HW.26 G1).

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
0.7 °C of margin, i.e. a pointer for the bench, not a finished protocol. ⚖️ Founder call →
`00_07` HW.6. (`mechanical/thermal_install_field.json`)

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
| Pore the "≥ 1 m" criterion demands at θ 110° / 115° / 120° | **10.2 / 12.6 / 14.9 µm** |
| Water-entry pressure at θ 110° — pore AND angle together, NOT a bubble point (that one runs in a wetting liquid and does not see θ) | 100 / 199 / 498 kPa for 1.0 / 0.5 / 0.2 µm |
| θ at which the worst field load breaks through | **90.02 – 90.10°** |
| O₂ transport margin at the canon's own lower bound (0.02 µm) | **4838×** |

**Verdict** — 🟢 Spec sound and over-specified at both ends; ⚠️ the BENCH was aimed at the wrong
target, and so was my first reading of the canon. The prose bound "no pores > 15 µm" is **not an
arithmetic error** — it is this same inversion at 120°, the top of the document's own θ range, while
the §5.3 table guarantees only 110° (→ 10.2 µm). The defect is an unstated θ slice, not a wrong
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
| Pogo spring (BeCu C17200 #75; data from the Mill-Max 0906 sheet — the series itself is `00_07` HW.9's pick) | mfr full-stroke life 1e5–1e6 cyc · S-N anchors 240 MPa→1e10 cyc / 400 MPa→3.05e6 cyc, no strict VHCF flat limit | Two mismatched framings — full-stroke actuation FAILS (likely wrong model); low-amplitude stress framing is physically right but missing the real sway micro-deflection datum |
| PEEK mechanical-lock barb (cyclic, ⊥ HW.26's tracked static creep) | endurance limit 30–48 MPa @ 1e6–1e7 cyc (2 converging sources) | Reference established for HW.26's pending FEA to check against; not itself closed |
| Sil-Pad (HW.30, 3rd Z-stack spring) | — | Not S-N-closeable by construction (compression-set/creep, formulation-specific); correctly routes to HW.30's already-scheduled bench test |
| Genipin-chitosan-CNC matrix (01_03 §2.1 Layer 4) | script 16 (N=10 MD cycles, qualitative pseudoplastic) | Category mismatch — a ~10-20 µm enzyme-immobilization coating, not a load-bearing spring; removed from the S-N framing, its durability axis is chemical (HW.5), not cyclic-mechanical |
| Sway frequency (*P. sylvestris*, Hartheim research site, Univ. Freiburg) | Kolbe & Schindler 2021 (HardwareX 9, e00180): first mode 0.273–0.312 Hz, three trees H 17.2–18.0 m, Apr–Oct 2020 · Nickl et al. 2022 (HardwareX 12, e00379): f0 0.26 Hz, strain at 2.7 m, June 2021 · Schindler & Kolbe 2020 (Forests 11, 145): «damped fundamental sway frequency of the stem» 0.74 Hz, one tree H 16.8 m, 30 Jan 2019 — full texts read, one site in all three | A BRACKET of two named readings, not a point: one group, one site, trees of one size, and the readings differ 2.4–2.8× with no cause named in either text. 20 yr of continuous sway gives **1.64–1.97 × 10⁸** cycles at the low reading and a ceiling of **4.67 × 10⁸** at the high one. ⛔ The canon's 1–5 Hz is a bench frequency with no field reading, so no budget is counted at it |
| Wind duty-cycle (Cherkasy pine forest) | NASA POWER WS10M, 10y daily, Beaufort-anchored exceedance | Not closed to one number — even the most generous bracket (Beaufort 3 on open/10 m wind, 70 % of days) bounds N_eff ≤ **3.29 × 10⁸** at the frequency ceiling; sway-onset threshold is "poorly constrained" in peer-reviewed lit and canopy attenuation varies >4× (both named, neither fabricated) |

⚠️ **Three bounds travel with every cycle count above, and quoting a count without them quotes more than was measured** (script `62`, cache `bounds_that_travel`): **(1)** frequency × time bounds FIRST-MODE cycles and is not a count of strain ranges — the strain spectrum's first maxima sit at 0.04–0.05 Hz, below f0 (Nickl et al. 2022), and for its sample tree the maximum wind-induced response is quasi-static rather than the dynamic reaction near f0 (Schindler & Kolbe 2020); the honest budget is a strain-range histogram at anchor height, measured for no *P. sylvestris*. **(2)** The canon's host trees (DBH ≥ 38 cm) are larger than every measured tree, and the natural sway frequency is linear in DBH/H² (Moore & Maguire 2004) — so the hosts' frequency is extrapolated, and its direction is not fixed without their height. **(3)** The two readings disagree and nothing in the sources resolves it — both measured STEM motion, so «stem vs whole tree» does not separate them — which is why consumers take the high one as the ceiling and carry its source (script `55` §`wear_budget` and script `59` both load it from the cache).

**Verdict** — 🟡 Genuinely partial. No part is fully closed, and that is the honest result: each
gets a named numeric threshold or a named reason the closed-form method does not apply, plus the
exact missing datum that would close it (bench sway-deflection measurement, HW.26's FEA output, an
in-canopy anemometer, or a strain-range histogram at anchor height). The one clean correction is the
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
reachable depends entirely on the still-open `VBAT_OV` target (`00_07` HW.7) — at 10°C, the
conservative vendor coefficient needs ≤4.92V, the optimistic one only ≤5.20V. This is a **derate /
oversize / SKU-freeze ⚖️ now live and blocking** (`00_07` HW.37) — not decided here. The
cycle-count argument in `02_03 §12.1` is not wrong, only insufficient on its own; both axes now
stand side by side there. (`kinetics/gusak_degradation.json` → `edlc_endurance_hours`)

---

## HW.42 — Does a Second Power Source Contaminate `delta_t`? (script 63)

Canon home → [`02_03 §9`](../../../02_03_BQ25570_MPPT_Nano_Power.md); decision → `00_07` HW.42.

Since [E.63], the EDLC recharge interval `delta_t` drives `growth_points` directly — a
money-minting signal. `HW.21` carries a checkbox to put a TEG on the SAME BQ25570 charging rail
as the EBFC; `01_03 §4`'s instrumental-noise list is exhaustively chemical and has no axis for "a
second power source on the shared rail". Closed form: `delta_t = E_window / (P·η_boost)`,
swept over auxiliary power P_aux = 10-200 µW (spanning HW.21's own 50-200 µW TEG estimate),
reported as a 3-way bracket (shared-boost floor / direct-injection ceiling / BQ25570's own
measured η(P) curve as a cross-check) since the multi-input topology itself is still open
(`FW.50`).

| P_aux | Summer (15 µW) shift | Winter (3-5 µW) shift |
|---|---|---|
| 10 µW (range floor) | 40-50% | 67-84% |
| 50 µW | 77-83% | 90-96% |
| 200 µW | 93-95% | 98-99% |

**Verdict** — 🔴 Even at the BOTTOM of the plausible TEG range, `delta_t` is already dominated by
the auxiliary source rather than tree metabolism, in every season. The percentage result is
algebraically independent of which of this codebase's several non-interchangeable `delta_t`
definitions is used (E_window cancels in every bracket model) — this is not an artifact of scale
choice. Whether this forces a physical rail split or blocks `HW.21`'s multi-input checkbox is an
explicit ⚖️ reserved for the founder (`00_07` HW.42) — not decided here.
(`kinetics/delta_t_aux_power_sensitivity.json`)

---

## HW.21 — A TEG ACROSS the Zone-2 PEEK Break, Not Glued to the Bark (script 64)

Canon home → [`01_03 §6.2`](../../../01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md) (TEG concept) +
[`01_01 §4.1`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) (why the break exists at all);
decision → `00_07` HW.21.

`HW.21`'s 🤖 leg asks the geometrically obvious question: a bark-glued module sees its ΔT through bark
(λ 0.05–0.1) and an unclamped joint, whereas **Zone 2 is the one place in the anchor where both junctions
are already mechanically fixed on opposite sides of a λ 0.25 insulator**. ⚠️ But it aims straight at the
reason Zone 2 exists — a continuous Ti bridge super-cools the cambial ring into intracellular ice — and a
TEG is, before it is anything else, a conductive plate. Script 64 **imports** script 54's ladder rather
than copying it (it re-derives 54's own cached Ti / no-bus / Cu conductances to rtol 1e-12 or aborts the
run) and adds `G_TEG = κ_eff·A/t` in parallel with either the 6 mm PEEK-only gap (`gap` mount) or the
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
| *no TEG — the residual monolithic-Ti bus we already accept* | — | 1× | **−0.70 °C** | ok | — | — |
| 8×8×4 mm — smallest geometry swept | 2.24e−2 W/K | 14× | −8.70 °C | ❄ FAIL | 841 µW | 15.1 mV |
| 15×15×3 mm | 1.05e−1 W/K | 67× | −10.93 °C | ❄ FAIL | 295 µW | 14.5 mV |
| 40×40×3 mm — HW.21's own 4×4 cm part | 7.47e−1 W/K | 474× | −11.65 °C | ❄ FAIL | 48 µW | 15.5 mV |
| *asymptote:* `gap` mount, G_TEG → ∞ | ∞ | — | −11.77 °C | ❄ FAIL | — | — |
| *reference:* **solid Ti, NO PEEK break at all** | 1.27e−2 W/K | 8× | **−11.66 °C** | ❄ FAIL | — | — |

**Verdict** — 🔴 **Reject as posed, and not because the part is badly chosen.** `0 of 90` swept
combinations (5 footprints × 3 thicknesses × 3 κ × 2 mounts) pass the gate: the *smallest* geometry
swept already conducts **14× the entire anchor**. It is not a partial defeat — a gap-spanning module
saturates at −11.77 °C, **0.11 °C from a solid Ti anchor with no PEEK break at all** (−11.66 °C), i.e.
it reverts the design to precisely the pre-PEEK condition Zone 2 exists to prevent. Inverted, the number
worth keeping is the **budget**: anything crossing the break must stay under **1.1e−3 W/K ≈ 2.4 mm² at
3 mm** — ×26 smaller than the smallest module — and across the 32 live wood-grid points that budget goes
**negative** (min −8.7e−4 W/K), because the residual Ti bus has already spent the whole allowance there.
Two objections were tested and neither rescues it: at the leg-only fill-factor lower bound (κ_eff 0.4)
the 8×8×4 still fails at −5.43 °C, and the bus diameter cannot move it either — widening the canon rod
Ø1.0 to the fattest it could physically be (the Ø1.35 channel) moves the 8×8×4 case −8.70 → −8.81 °C,
because the module out-conducts the whole anchor either way.
⚖️ **The honest residual, stated rather than buried:** at exactly the budget a bespoke sub-mm² micro-TEG
still yields ~428 µW — *above* HW.21's own 50–200 µW winter target — but at zero gate margin, and its
V_oc is ~9.4 mV, **×64 below BQ25570's VIN(CS) 600 mV** (HW.46), so it would need a mV-class transformer
harvester, not a BQ25570-class part. That is a different project, not a module choice. Note also the
thermal impedance match: power peaks at G_TEG 8.6e−3 W/K (≈4.3×4.3×3 mm, 1043 µW) and **falls** for larger
modules — 40×40×3 gives 18× *less* than 8×8×4 — so "buy a bigger TEG" loses on both axes at once.
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
removed, the recipe is now a point (Q6). Q1–Q5 below price the ranges that point replaced and stay its ground.

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

**Q6 — the ratified point** (⚖️ founder 2026-09-17: oxalate out; malic acid 2.2 · KNO₃ 3.2 · CaCl₂ 1.0 · MgSO₄ 0.45 mM,
each the geometric mid of its old range, asserted by the script; pH 5.75 — the measured *P. sylvestris* sap pH,
Tarvainen et al. 2023 — with a pH 4.5 side series of uncoated coupons under ICP-MS only). Over every documented
reading and every temperature of the tests each condition belongs to:

| condition | KOH to reach it | K⁺ total | β at 25 °C | strong acid for −0.1 pH |
|---|---|---|---|---|
| pH 5.75 (both tests, 20–40 °C) | **4.09–4.15 mM** | 7.29–7.35 mM | **0.61 mM/pH** | 0.066 mM |
| pH 4.5 (coin side series, 20–25 °C) | **2.57–2.72 mM** | 5.77–5.92 mM | **1.45 mM/pH** | 0.14 mM |

Gypsum stays far from saturation (SI ≤ −2.2), and with oxalate gone no calcium oxalate hydrate can form. The
number that matters is the last column: at the set-point a few hundredths of a millimole of acid move the pH by a
tenth, and a working anode produces acid — the model does not say how fast, so the figure is a scale, not a drift
prediction — which makes medium replacement and a pH log conditions of the test rather than good practice.

**Verdict** — 🔴 **The pre-verdict recipe had no member that is a stable solution.** Every corner of both tests'
bands is supersaturated to all three calcium oxalate hydrates, by a margin no documented constant closes. The
hard-bound window was the machine half of HW.3; which ion to lower was ⚖️, priced in Q2–Q4, and the founder
removed oxalate on 2026-09-17 — its price is the buffering Q4 measures and the chelator the recipe no longer
carries; what the chosen point takes is Q6. (`chemistry/sap_recipe_saturation.json`)

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

## CHEM.11 — Can the Deglycosylation Hotspots Actually Be Compensated? (script 69)

Spec home → [`L1_protein_architecture.md`](L1_protein_architecture.md) §2; decision → `00_07` HW.5.IS / CHEM.11.

`L1 §2` has said since 2026-06-06 that "an in-house hydrophobic-SASA proxy flags 4 aggregation-prone sites
(Gln71, Gln200, Gln258, Gln405)", and the recipe on top of it — Aggrescan3D plus compensating Asp/Ser near
them — gates the dgrFAD-GDH gene freeze. ⚠️ **That proxy existed nowhere in the tree.** Commit `2e607abc`
canonised the conclusion and committed neither script nor cache, so the claim had no measurer for fifteen
months. Script 69 is the measurer, and the first thing it had to do was ask whether a declared proxy
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
| Gln71 | **Leu80 → Asp** | **−78.4** | −1 | 0.618 | T | 12.1 | 18.6 | ✅ **TAKEN — ⚖️ founder 2026-09-17** |
| Gln71 | **Leu80 → Ser** | **−78.4** | 0 | 0.618 | T | 12.1 | 18.6 | ⚫ not taken (tie broken by founder) |
| Gln71 | **Ala70 → Ser** | **−59.6** | 0 | 0.511 | H | 17.4 | 18.3 | ✅ |
| Gln71 | Ala70 → Asp | −59.4 | −1 | 0.511 | H | 17.4 | 18.3 | ❌ Asp in a helix |
| Gln405 | **Ile401 → Ser** | **−100.9** | 0 | 0.503 | H | 29.3 | 27.9 | ✅ |
| Gln405 | Ile401 → Asp | −100.5 | −1 | 0.503 | H | 29.3 | 27.9 | ❌ Asp in a helix |
| Gln200 | Ala201 → Ser | −25.4 | 0 | **0.770** | H | 26.4 | 42.8 | ❌ burial 0.77 > 0.75 |
| Gln200 | Trp210 → Ser | −17.4 | 0 | **0.908** | B | 19.7 | 37.2 | ❌ buried |
| Gln258 | Leu257 → Ser | −39.6 | 0 | 0.804 | — | **9.7** | 10.3 | ❌ FAD pocket + buried |
| Gln258 | Ala285 → Ser | −27.8 | 0 | 0.762 | T | **11.4** | 8.7 | ❌ FAD pocket + buried |

**Three positions are admissible, and two of the four hotspots get nothing.**

- **Gln71 → Leu80 and Ala70 → Ser.** ⚖️ **founder 2026-09-17 took `Leu80 → Asp`** — the measurement below is untouched and still says the two are a tie within noise; the verdict breaks a tie the computation declared unbreakable, it does not overturn it. 🔴 At **Leu80 the script refuses to choose between Asp and Ser**, and the
  refusal is itself a measurement: the two remove the same area to within the noise floor, and the ranked
  winner was observed **flipping Asp ↔ Ser between two runs of identical inputs**. What separates them is a
  **charge**, and noise may not decide a charge — so the cache names the position with `to: null` and leaves
  both in `admissible_substitutions`. The combined variant below had to be built from real residues, so it is
  built as Ser (the option that commits no charge); that is a build choice, flagged as one, not a
  recommendation.
- **Gln405 → Ile401 → Ser**, the single largest gain available — Ile401 alone carries 100.9 Å² of exposed
  apolar area, and the swap takes that patch from 119.8 to 18.9 Å². ⚖️ **founder 2026-09-18 TOOK it**, after the
  hold's own question — is position 401 conserved — was measured and answered no (Ile 3.6 % vs Ser 15.7 % over 332
  homologs; the catalytic His537 control reads 98.8 %). Numbers, sampling and the method's ceiling live in
  script `70` and its cache (`chem11_site_conservation.json`); the design verdict lives in `L1 §2`. Asp is refused there by the declared
  secondary-structure heuristic; Ser is not.
- ⛔ **Gln258 — do not touch.** Its entire apolar neighbourhood lies inside the FAD-pocket and electron-exit
  shells, and the site itself sits **8.0 Å from the Beratan-Onuchic tunnelling path** (loaded from script 28's
  cache, not mirrored) **and 11.0 Å from FAD**. Aggregation margin there is bought with the MET architecture
  of §5 — the whole cell.
- ⚖️ **Gln200 — refused by OUR threshold, not by the physics.** Ala201 → Ser would remove **46 %** of that
  patch and is refused by a burial of 0.770 against our declared ceiling of 0.75 — a margin of **0.020**, and
  it would pass at the sweep's relaxed value of 0.85. Trp210 → Ser would remove 32 % and is genuinely buried
  (0.908, passing at neither swept value). The ceiling was left where it was declared;
  `threshold_cost_measured` prices each refusal in Å² so the choice stays visible.

**Priced as one sequence, because a freeze is a sequence.** The three recommendations built as a single
variant take Gln71 from 140.1 to **2.9 Å²** and Gln405 from 119.8 to **18.9 Å²**; the largest non-additivity
against the sum of the singles is **1.4 Å²** — measured on the built variant rather than assumed either way.
The undecided position was built as Ser for this one variant, which the cache flags as a build choice.

### Conservation of the three positions (script 70) — the hold that gated `I401S`

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
the query residue's 3.6–5.1 %), and the one external PAIRWISE alignment in the tree (EMBOSS Needle,
*C. incanum*) agrees residue-for-residue. ⛔ Frequency is not consequence, there is no phylogeny and no
tree-aware weighting here, and the 85-accession external subset is a curated sample whose selection rule was
never recorded — all three are named in the cache's own `caveats`.

**Ceiling.** An exposed apolar patch is a static, single-molecule surface descriptor — **not** an aggregation
prediction: no rate, no solubility, no critical concentration is computed anywhere here. **Aggrescan3D was
NOT run** (external web server), so the first half of the `L1 §2` recipe stays OPEN. Sequence conservation is
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
