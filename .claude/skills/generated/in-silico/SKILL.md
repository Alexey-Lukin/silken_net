---
name: in-silico
description: "Navigation + gotchas for EBFC in-silico pipeline (L1-L4 MD+DFT). Read SSOT docs first."
---

# In-Silico Pipeline (EBFC Gen 2.0 Zero-Lab Proof)

## SSOT Documents — Read These First

| Document | What it covers |
|----------|---------------|
| `docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md §3.4` | Pipeline spec, TRL gate, L1-L4 definitions, artifact table |
| `docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md` | Live status: running/queued/completed scripts, decision matrix |
| `docs/protocols/ebfc/in_silico/SUMMARY.md` | All L1-L4 results in one page |
| `docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md` | DFT details, cascade methods comparison, ΔSCF, L3b cathode |
| `docs/protocols/ebfc/in_silico/L1_protein_architecture.md` | AlphaFold 3 results, d_FAD distance |
| `docs/08_01_University_R_and_D_Protocols.md` | Мінаєв collaboration, xylem sap protocols |
| `docs/08_03_Joint_Publications_and_IP_Strategy.md` | Publication plan, Стаття 28 baseline |
| `docs/08_06_CHMA_Biomedical_Integration.md` | ЧМА collaboration, Бушуєва EIS predictions |
| `docs/00_07_Action_Plan_Tracker.md` | HW.5.IS section — operational task status |
| `tools/in_silico/README.md` | Setup, quickstart, GPU notes, GAFF explanation |

**After completing ANY task in this pipeline — update ALL the SSOT docs above.**

## Script Dependency Graph

```
Parameterization (CPU, ~minutes):
  02 FAD → 03 GEN → 04 CSO → 05 CLB → 06 PPy → 07 PVI → 08 SBMA
           ↓
L2 MD (GPU):            ↓ SMILES change → rerun ALL downstream
  10 (baseline) ← 02,03
  11 (full matrix) ← 02-05    → 11* (10ns extended)
  12 (temp sweep) ← 02-05     → 4 temperatures
  13 (PSBMA diffusion) ← 08   → D_eff
  14 (xylem sap) ← 02-05      → 6 species

L3 DFT anode (CPU):
  20 (FAD) ──┐
  21b (Os B3LYP) ─┼── 22 (cascade verdict) ← rerun after 21d
  21d (Os ωB97X) ──┘
  28 (tunneling pathway) ← PDB only, no DFT deps
  29 (Nelsen λ) ← standalone

L3b DFT cathode (CPU):
  23 (ZIF clusters) → 24 (hopping integrals, 3 pairs)

L4 Kinetics (CPU, seconds):
  30 (delta_t) → 30b (Monte Carlo) → 31 (EIS) → 40 (validation)

Bridge:
  27 (MD→DFT ensemble) ← 11 (DCD trajectory) + DFT
```

## Critical Rules

1. **Shared lib is SSOT** — all constants, paths, banner() from `lib/`. Never redefine locally (19 local banners eliminated in refactoring).
2. **SMILES fixes cascade** — fixing a SMILES in 02-08 → rerun ALL downstream MD using that ligand. Check GAFF cache too.
3. **DFT: NEVER two heavy jobs on same CPU** — cache thrashing makes both 2× slower. Small molecules (H₂O, lumiflavin) OK to parallelize.
4. **No density_fit() for Os/Ce** — auto-generated aux basis for heavy metals is 3× SLOWER than standard integrals.
5. **level_shift=0.3 for open-shell transition metals** — UKS on Os(III), Co-Ce, Ce without it → SCF oscillates forever (60h+ observed).
6. **MD NaN at NVT ramp** — 10K pre-relaxation (1000 steps at 10K) + start NVT from 50K + ramp step 10K (not 5K). Especially at high T (313K) and with many ligands. Use `maxIterations=10000` for minimization.
7. **MD trajectories gitignored** — only JSON/PNG summaries in `cache/dft/` and `cache/kinetics/` committed.
8. **CI smoke test** — `in_silico_smoke.yml`: CPU-only, padding 0.5nm, 500 min iterations, 30 min timeout.

## DFT Gotchas (Hard-Won Lessons)

- **PySCF no SDD** — use `lanl2dz` for Cu/Co, `stuttgart_rsc` for Ce (Ce not in lanl2dz)
- **wb97x-d not supported** — use `wb97x` (range separation is the main fix, dispersion ~0.05 eV)
- **ωB97X Koopmans orbital energies ≠ redox potentials** — RSH gives accurate IPs but LUMO systematically too high for inter-molecular comparisons. Use ΔSCF (total energies) instead. B3LYP Koopmans works better due to error cancellation.
- **Adiabatic ΔSCF** — composite approach: geom opt at B3LYP/def2-SVP, SP at ωB97X/def2-TZVP. Saves orders of magnitude vs full ωB97X opt.
- **Cl on flat PES** — geometry optimization never converges GAU displacement criterion for Cl in Os complex. Programmatic octahedral geometry sufficient (LUMO diff < 0.002 eV after 30 cycles).
- **Spin parity** — odd electrons → odd spin (2S). Auto-detect: `spin = mol.nelectron % 2` as fallback.
- **PCET with H₃O⁺/PCM** — PCM oversolvates small ions (H₃O⁺ by ~7 eV). Don't use for proton transfer corrections. Need explicit water for meaningful PCET.
- **FAD in MD topology** — GAFF renames FAD to "UNK", all atoms have "x" suffix. 86 atoms total, 53 heavy. Full FAD has odd electron count — set charge=1 for even.

## MD Gotchas (Hard-Won Lessons)

- **10K pre-relaxation mandatory** — 500-1000 steps at 10K before NVT ramp. Without it → NaN on ~50% of runs with multiple ligands.
- **Fibonacci sphere placement** — deterministic (seed=42) but can create bad contacts at specific positions. 313K (40°C) particularly vulnerable — skip if NaN persists after 3 attempts (3/4 temps sufficient).
- **GAFF matching** — `GAFFTemplateGenerator` matches by graph structure. One `Molecule` per unique chemical species is enough.
- **L2 10ns RMSD ~4 Å is normal** — AF3 structures relax 3-5 Å under AMBER ff14SB for large enzymes. Check **Rg** (radius of gyration) — if stable → protein folded, RMSD is just conformational relaxation. Full equilibration needs 20-50 ns.
- **25GB DCD files** — use `stride=10` or `stride=100` when loading with mdtraj. Full load kills memory.

## Cascade Verdict Summary

| Method | ΔG/e⁻ (eV) | vs Exp (-0.14) | Use for |
|--------|-----------|----------------|---------|
| B3LYP Koopmans (corrected) | -0.07 | 0.21 eV | **Best estimate** |
| ΔSCF ωB97X (adiabatic) | +0.884 | 1.02 eV | Independent validation |
| ΔSCF ωB97X (vertical) | +0.998 | 1.14 eV | Baseline |
| Koopmans ωB97X | +5.884 | 6.02 eV | **Never use** (RSH artifact) |

Residual ~0.9 eV gap = PCM solvation limit (not chemistry error).

## When Modifying

- **Adding a ligand**: script 0N (parameterize) → add to gaff_cache → SDF to ligands/ → add test → rerun downstream MD
- **Changing a constant**: `lib/constants.py` ONLY → check which cached JSON uses it
- **After any change**: `pytest tools/in_silico/tests/` → commit → update all the SSOT docs above
- **New DFT script**: import from `lib.constants` + `lib.utils` + `lib.dft_utils`. Use `level_shift=0.3` for UKS. No density_fit for heavy metals.
- **New MD script**: import from `lib.constants` + `lib.geometry` + `lib.utils`. Use 10K pre-relaxation + 10K ramp step + `maxIterations=10000`.
