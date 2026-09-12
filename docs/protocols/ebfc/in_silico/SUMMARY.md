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
| **L4** | Does BASELINE_DELTA_T_S = 60s make physical sense? | Analytical MM+Arrhenius | ✅ Healthy 44.7s / Stressed 237.5s (η_BQ 0.68 post-HW.47) |

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

**Conclusion:** dgrGcGDH + Gen 2.0 matrix stable across all tested tree species (pH 4.2-6.0). Lowest RMSD at pH 6.0 (beech) — less acidic = gentler. Highest at pH 4.2 (spruce) — most acidic, still well within threshold. **Cross-species deployment validated.**

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
| j_max(25°C) | 494 µA/cm² | Zafar 2012 (PMC3275720) |
| Km(glucose) | 20 mM | Estimated (GcGDH) |
| Ea | 40 kJ/mol | Typical FAD enzyme |
| V_op | 0.5 V | EBFC under load |
| A_electrode | 2 cm² | Conservative gyroid area |
| η_BQ | 0.68 | BQ25570 datasheet (SLUSBH2G Fig.6-7, low-I_IN; [HW.47]) |
| E_cycle | 5 mJ | STM32 sense+LoRa TX |

### delta_t Predictions

| Scenario | [glucose] | T(°C) | delta_t (s) | vs 60s baseline |
|----------|-----------|-------|-------------|-----------------|
| Healthy summer | 10 mM | 25°C | **44.7** | < 60s → GP↑ [E.63] |
| Active growth | 20 mM | 30°C | **22.8** | < 60s → GP↑ [E.63] |
| Moderate spring | 15 mM | 20°C | **45.7** | < 60s → GP↑ [E.63] |
| Cold winter | 5 mM | 5°C | **237.5** | > 60s → GP↓ [E.63] |
| Severe stress | 3 mM | 0°C | **499.7** | > 60s → GP↓ [E.63] |

**Conclusion:** BASELINE_DELTA_T_S = 60s is physically justified. EBFC discriminates healthy vs stressed trees. Diffusion NOT rate-limiting (j_kinetic ≪ j_diffusion).

### EIS Predictions (for Ti-coin Stage 2)

| Parameter | Predicted | Literature Range |
|-----------|-----------|-----------------|
| Rct (charge transfer) | 130 Ω | 100-500 Ω |
| Rs (solution) | 100 Ω | 50-200 Ω |
| Cdl (double layer) | 50 µF/cm² | 20-100 µF/cm² |
| Time constant τ | 13 ms | — |
| Warburg region | < 12 Hz | — |

The 130 Ω Rct above is the **anode** charge-transfer (enzyme→Os, from j_max; script 31). The
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
| Sealing | elastomer **O-ring = ESSENTIAL** (at MIN fit relaxed P_c ≤ sap 0.5); PEEK = isolator + backup P_c (max fit); barbs = axial only |
| Winter | inner interface tightens; outer = tree (not a Ti shell) → old cold-leak was a baseline artifact |
| **Verdict** | ✅ Ti↔PEEK press-fit survives 20+ years (combined SF 5.6× margin + O-ring seal; **HW.3.IS unified Lamé 2026-06-22**) |

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
(`01_01 §1.4`). A **Cu** bus dominates the Zone-2 PEEK break (G_anchor 9.3× a Ti bus, ×18.2 vs no bus;
λ_Cu ~1600× PEEK) → drags the Zone-1 anode pocket to **−12.8 °C** (14.8° below the +2 °C core → living-sapwood
freeze-risk) at −30 °C air / +2 °C core. A bus **monolithic with the anode** (= the anode alloy) is
thermally near-invisible (**−0.70 °C**, ×1.95 vs no bus). Per bake-off alloy: alloyed α+β Ti
(4V/7Nb/β/15Zr, λ≈7) −0.70…−0.91 °C; CP-Ti (λ17) −2.21; Ta (λ57, benchmark) −5.63 — **all ≪ Cu**, and
the −2 °C freeze gate still separates the four α+β Ti (safe) from CP-Ti and Ta (freeze). Electrically
free at µA (Ti 11.3 µV at 100 µA, 4×10⁴ below the 500 mV reference).
(`mechanical/anchor_thermal_bridge.json`)
> ⚖️ **Re-run landed 2026-09-10 at the canon rod Ø1.0** (`00_07` HW.34) — the numbers above are the new ones. What the diameter move cost on THIS side: the bus area shrinks ×1.69 (A ∝ d²), so the bridge looks *better*, i.e. the old figures were conservative and both load-bearing verdicts survived (Cu ×24.3 → ×18.2 vs no-bus, Cu/Ti ratio 9.57 → 9.31; monolithic Ti −1.43 → −0.70 °C). Exactly **one** cached boolean flipped — `cell_freeze_risk["316SS"]` true → false (−3.16 → −1.94 °C against the −2.0 gate) — and 316SS is the superseded pre-monolithic alternative, not a bake-off candidate; all six HW.24 alloys kept their verdicts. The one **anti-conservative** axis was electrical (R ∝ 1/A → IR drop was understated ×1.69, Ti 6.7 → 11.3 µV at 100 µA). ⛔ The direction here is OPPOSITE to script 55 below — never read one diameter caveat as covering both.

**Mechanical (script 55)** — slender-beam closed form, at the canon rod **Ø1.0**, and since the
fabrication verdict it reports **two branches**: `printed` (superseded) and `welded` (SHIPPED, ⚖️
2026-09-10, cold-drawn wire, no as-built knockdown). Buckling SF **10×** (1 N pogo) even unsupported →
still a non-issue in both. Sway fatigue: the bore **liner** (= the short-circuit insulation) doubles as
lateral support → infinite life for **every** alloy in both branches (SF 4.2–11.7× printed, 8.5–23.3×
welded). 🔴 **Bare, the fabrication choice decides — and it decides two different verdicts.** Printed:
NOT ONE of the six reaches infinite life (SF 0.71–1.94×), a predicted fatigue **failure** for Ta (0.71)
and CP-Ti (0.98). Welded: every SF doubles, so predicted failures drop to **none** — but infinite life
is reached by only **4 of 6** (SF 1.41–3.89×), with Ta (**1.41**) and CP-Ti (**1.96**) still under the
SF-2 line. Per-alloy margin tracks yield = SAME ranking as the thermal side → leading HW.24 candidates
win on both. (`mechanical/bus_mechanical.json`)
> ⚖️ **Re-run landed 2026-09-10 at the canon rod Ø1.0** (`00_07` HW.34) — and here the diameter move changed the CONCLUSION, not just the digits (σ ∝ 1/d³, SFs fall ×2.2). The unsupported branch did not thin out, it crossed the line: Ta 1.55 → **0.71**, CP-Ti 2.16 → **0.98**, and the four alloyed Ti dropped 3.8–4.3 → **1.74–1.94**, i.e. `unsupported_infinite_life` went **true → false for all six** (⚠️ that per-alloy boolean is now branch-suffixed — `unsupported_infinite_life_printed` / `_welded`; the bare name survives in `fabrication_branches` but as a LIST of alloys, so it resolves and no longer means the same thing). 🔑 **So lateral support is not a soft-alloy mitigation, it is a requirement for every candidate** — which is the input the open HW.34 lining verdict was missing: a film that does not touch the rod (Parylene ~10 µm, anodised TiO₂ ≤10 µm in a sub-mm channel) insulates without supporting. ⚠️ The clause that stood here — «the model has no liner stiffness to give it credit for» — was true of that day's model and is not true now: since the clearance verdict the script computes the rod-plus-tube composite EI and reports both bounds, so a branch is no longer credited or denied support by omission.
> ⚖️ **Fabrication branch added 2026-09-11** (`00_07` HW.34) — the welded verdict re-opened the lining one, so the script now emits both columns. **The re-run narrowed the support motive without retiring it:** dropping the as-printed derate lifts Ta and CP-Ti out of predicted failure (0.71→1.41, 0.98→1.96) and **not** over the infinite-life line, so bare-rod infinite life goes 0/6 → **4/6**, not 6/6. 🔴 **The tracker verdict's stated ground said "all six" and its own adjacent table did not** — the arithmetic there was right (every SF doubles) and only the conclusion was wrong; corrected in `00_07`. ⛔ And the doubling belongs to the WIRE: the model is a homogeneous cantilever, while the ratified joint sits in the root, at peak bending moment. ⚠️ That sentence stays true about the wire; what changed 2026-09-12 is that the seam is no longer UNPRICED — see the next note, and read `fatigue_model.weld_seam_geometry_modelled` beside `…_sensitivity_modelled` rather than the single boolean this line used to cite.
> 🔴 **Clearance regime added 2026-09-11, and it RETIRES the fatigue ground rather than narrowing it further** (`00_07` HW.34, ⚖️ founder). Both `L_FREE_*` columns are FREE cantilevers — no wall anywhere — while the rod threads the cathode bore. At the ~165 µm radial play a 10 µm conformal film leaves, the rod takes up that play and **bears on the wall 4.5–11.1 mm inside the bore on every µ the script sweeps** (first contact 10.47–17.15 mm from the root). So the unsupported SF is a number for a configuration that does not exist, and the liner’s structural ground moved from FATIGUE to WEAR: a 10 µm film asked to be a bearing under a beam reaction in a blind bore of `L/D` ≈ 12.6, whose wear-through is a ~0.5 V anode↔cathode short. (`mechanical/bus_mechanical.json` §`clearance_regime`; the verdict line is DERIVED from `gap_limited_branches`, never typed)
> 🔴 **And the clearance verdict of the same day moved this section's OWN numbers — branch (в), channel Ø1.30 → Ø1.35, applied 2026-09-11.** Two things changed and only the second is a digit. **(1) The model can now say WHICH SIDE the leftover play sits on**, which it could not before: a conformal film is bonded to the rod, so its play is on the ROD side and the bending member is the bare wire; the ratified liner is tight on the wire and enters the blind bore as one body, so its play is on the CHANNEL side and the member is the rod-plus-tube composite (both stiffness bounds computed, `ei_Nm2_bare_rod` ⊥ `ei_Nm2_bonded`). **(2) The "hundredfold reduction of free travel" this page fed into canon was a ROD-SIDE number and is gone: the measured factor is `play_reduction.factor` ≈ 6.8×** (170 → 25 µm). ⚠️ The conclusion it supported survives with a named error bar rather than intact: the liner no longer bears exactly AT the mouth but **0.51 mm past it** (deepest first contact 6.51 mm vs the assumed 6.0 span), so the supported-column root stress is **understated by 8.5 %** — `supported_span_check` in the cache, derived. SF stays an order above the SF-2 line, so nothing is overturned; the point is that `L_FREE_SUP = 6 mm` is now MEASURED against the contact it assumes instead of asserting it.
> 🔴 **Weld seam BOUNDED 2026-09-12 (`00_07` HW.34) — and what makes it a measurement rather than a guess is that the input stays missing.** Canon ([`01_01 §1.4`](../../../01_01_Coaxial_Gyroid_Topology_and_PEEK.md) and the factory protocol `§3` step 1) had been sending the reader here for this state while nothing here held it. The seam's fatigue-strength knockdown `k` is in **no** canon row, **no** vendor answer and **no** experiment, so `weld_seam.knockdown_k_measured` stays `null` and the model bounds `k` instead: the seam sits at the root, the root is where this model's moment peaks, therefore `SF_seam = k · SF_wire` and the break-even `k` follows by inversion. **Priced on the SUPPORTED span only** — the free-cantilever column describes no branch that bears on the wall, so a seam tolerance computed on it would price a configuration that does not exist. Conservatism comes instead from two corrections that belong to the real span: the worst friction the load sweep carries (µ 0.5) and the **8.5 %** span-optimism measured one note above. **Result — the binding candidate is `Ta`**, and ⛔ **the result is NOT quotable as a single number: it FLIPS on a constant the tracker already records as wrong.** The conservatism term is the span optimism, and that is measured along `L_FREE_UNSUP = 36` — a protrusion whose third component («flange/pad standoff ~16 mm») cites nothing, while the CEM stack gives **23 mm** and the pad is the rod's own end face (`00_07` HW.34). So the model emits BOTH spans and derives the flip (`weld_seam.protrusion_sensitivity`, `verdict_flips_on_it: true`):

| protrusion | span optimism | σ worst corner | `Ta` `k` → SF-2 | vs our own marker `AS_PRINTED_DERATE` = 0.50 |
|---|---|---|---|---|
| 36 mm (shipped constant) | 8.2 % | 33.1 MPa | **0.426** | CLEARS by +0.074 |
| 23 mm (CEM-derived) | 40.0 % | 42.8 MPa | **0.551** | **DOES NOT CLEAR**, −0.051 |

⚠️ **The comparison drawn is against OUR OWN marker, never a borrowed weld figure** — `k` = `AS_PRINTED_DERATE` is «the joint is as bad as an as-built SLM surface», the point where welding buys nothing *where the part breaks*. 🔴 **And the sentence this paragraph used to carry — «priced on the supported span only, so the protrusion dispute does not reach it» — was FALSE**: the span-optimism term is computed from first contact along the protrusion, so the disputed constant entered through the back door. Caught by adversarial review the same day; the declared exclusion was never executed by the code. ⛔ Three seam mechanisms stay outside even this bound and their signs differ: a bead upset/fillet RELIEVES nominal stress, a weld-toe notch AGGRAVATES it, and weld residual TENSION is a **mean** stress that this script never carries at all — its endurance ratio is fully-reversed by construction, so even `k` = 1 would understate. (`mechanical/bus_mechanical.json` §`weld_seam`; every number derived, the binding candidate picked by the model and not by hand)

**Verdict** — 🟢 Monolithic bus (= anode alloy, HW.24-gated) resolves the Cu/Ti dichotomy: thermal
bridge minimized + Ti↔Cu galvanic joint eliminated + mechanically sound **with the bore liner**.

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
| Bubble-point pressure to challenge the spec at θ 110° | 100 / 199 / 498 kPa for 1.0 / 0.5 / 0.2 µm |
| θ at which the worst field load breaks through | **90.02 – 90.10°** |
| O₂ transport margin at the canon's own lower bound (0.02 µm) | **8627×** |

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
| Pogo spring (Mill-Max 0906, BeCu C17200) | mfr full-stroke life 1e5–1e6 cyc · S-N anchors 240 MPa→1e10 cyc / 400 MPa→3.05e6 cyc, no strict VHCF flat limit | Two mismatched framings — full-stroke actuation FAILS (likely wrong model); low-amplitude stress framing is physically right but missing the real sway micro-deflection datum |
| PEEK mechanical-lock barb (cyclic, ⊥ HW.26's tracked static creep) | endurance limit 30–48 MPa @ 1e6–1e7 cyc (2 converging sources) | Reference established for HW.26's pending FEA to check against; not itself closed |
| Sil-Pad (HW.30, 3rd Z-stack spring) | — | Not S-N-closeable by construction (compression-set/creep, formulation-specific); correctly routes to HW.30's already-scheduled bench test |
| Genipin-chitosan-CNC matrix (01_03 §2.1 Layer 4) | script 16 (N=10 MD cycles, qualitative pseudoplastic) | Category mismatch — a ~10-20 µm enzyme-immobilization coating, not a load-bearing spring; removed from the S-N framing, its durability axis is chemical (HW.5), not cyclic-mechanical |
| Wind duty-cycle (Cherkasy pine forest) | NASA POWER WS10M, 10y daily, Beaufort-anchored exceedance | Confirms 6.3e8 is an overcount (Beaufort-3 bracket bounds N_eff ≤ 4.4e8 even on open/10m wind) but not closed to one number — sway-onset threshold is "poorly constrained" in peer-reviewed lit and canopy attenuation varies >4× (both named, neither fabricated) |

**Verdict** — 🟡 Genuinely partial. No part is fully closed, and that is the honest result: each
gets a named numeric threshold or a named reason the closed-form method does not apply, plus the
exact missing datum that would close it (bench sway-deflection measurement, HW.26's FEA output, or
an in-canopy anemometer). The one clean correction is the genipin-matrix removal from the checkbox's
own S-N framing — the durability question that actually matters for it lives in HW.5.
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
| 8×8×4 mm — smallest geometry swept | 2.24e−2 W/K | 14× | −8.65 °C | ❄ FAIL | 832 µW | 15.0 mV |
| 15×15×3 mm | 1.05e−1 W/K | 67× | −10.86 °C | ❄ FAIL | 291 µW | 14.4 mV |
| 40×40×3 mm — HW.21's own 4×4 cm part | 7.47e−1 W/K | 474× | −11.56 °C | ❄ FAIL | 47 µW | 15.4 mV |
| *asymptote:* `gap` mount, G_TEG → ∞ | ∞ | — | −11.68 °C | ❄ FAIL | — | — |
| *reference:* **solid Ti, NO PEEK break at all** | 1.25e−2 W/K | 8× | **−11.49 °C** | ❄ FAIL | — | — |

**Verdict** — 🔴 **Reject as posed, and not because the part is badly chosen.** `0 of 90` swept
combinations (5 footprints × 3 thicknesses × 3 κ × 2 mounts) pass the gate: the *smallest* geometry
swept already conducts **14× the entire anchor**. It is not a partial defeat — a gap-spanning module
saturates at −11.68 °C, **0.19 °C from a solid Ti anchor with no PEEK break at all** (−11.49 °C), i.e.
it reverts the design to precisely the pre-PEEK condition Zone 2 exists to prevent. Inverted, the number
worth keeping is the **budget**: anything crossing the break must stay under **1.1e−3 W/K ≈ 2.5 mm² at
3 mm** — ×26 smaller than the smallest module — and across the 32 live wood-grid points that budget goes
**negative** (min −8.7e−4 W/K), because the residual Ti bus has already spent the whole allowance there.
Two objections were tested and neither rescues it: at the leg-only fill-factor lower bound (κ_eff 0.4)
the 8×8×4 still fails at −5.40 °C, and the bus diameter cannot move it either — widening the canon rod
Ø1.0 to the fattest it could physically be (the Ø1.35 channel) moves the 8×8×4 case −8.65 → −8.75 °C,
because the module out-conducts the whole anchor either way.
⚖️ **The honest residual, stated rather than buried:** at exactly the budget a bespoke sub-mm² micro-TEG
still yields ~428 µW — *above* HW.21's own 50–200 µW winter target — but at zero gate margin, and its
V_oc is ~9.4 mV, **×64 below BQ25570's VIN(CS) 600 mV** (HW.46), so it would need a mV-class transformer
harvester, not a BQ25570-class part. That is a different project, not a module choice. Note also the
thermal impedance match: power peaks at G_TEG 8.6e−3 W/K (≈4.3×4.3×3 mm, 1035 µW) and **falls** for larger
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

## Infrastructure

| Component | Location |
|-----------|----------|
| Scripts | `tools/in_silico/scripts/` (count + per-script status → [`PIPELINE_STATUS.md`](PIPELINE_STATUS.md)) |
| Shared lib | `tools/in_silico/lib/` (constants, geometry, utils, xylem_sap, dft_utils, md_utils) |
| Ligand SDF files | `docs/protocols/ebfc/in_silico/ligands/` |
| GAFF parameter cache | `tools/in_silico/cache/gaff_cache.json` |
| DFT results | `tools/in_silico/cache/dft/` |
| Kinetics results | `tools/in_silico/cache/kinetics/` |
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
