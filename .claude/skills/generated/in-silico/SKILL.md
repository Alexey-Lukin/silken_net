---
name: in-silico
description: "Domain knowledge for EBFC in-silico validation pipeline — L1-L4 levels, script dependencies, DFT/MD gotchas, rerun rules"
---

# In-Silico Pipeline (EBFC Gen 2.0 Zero-Lab Proof)

## Purpose

Computationally prove the EBFC works BEFORE ordering Ti-coin prototypes.
Four levels: L1 protein → L2 stability → L3 electron cascade → L4 kinetics.

## Architecture

```
tools/in_silico/
  lib/          ← shared constants, geometry, utils, xylem_sap, dft_utils, md_utils
  scripts/      ← 01-40 numbered scripts (run in order within each level)
  cache/        ← gaff_cache.json, dft/*.json, kinetics/*.json, runs/ (gitignored)
  tests/        ← test_cache_integrity.py (68 tests)
  environment.yml ← conda env "silken_md" (Python 3.12)
docs/protocols/ebfc/in_silico/
  ligands/      ← SDF/XYZ files (committed, small)
  *.md          ← L1/L3 details, PIPELINE_STATUS, SUMMARY
```

## Script Dependency Graph

```
Parameterization (CPU, ~minutes):
  02 (FAD) ──┐
  03 (GEN) ──┼── 10 (baseline MD) ── 11 (full matrix) ── 12 (temp sweep)
  04 (CSO) ──┤                                           14 (xylem sap)
  05 (CLB) ──┘
  06 (PPy) ── future
  07 (PVI) ── future
  08 (SBMA) ─── 13 (PSBMA diffusion)

DFT (CPU, hours):
  20 (FAD) ──┐
  21b (Os)  ─┼── 22 (cascade verdict)
  21d (ωB97X)┘
  23 (ZIF clusters) → 24 (hopping integrals)

Kinetics (CPU, seconds):
  30 (delta_t) → 30b (Monte Carlo) → 31 (EIS) → 40 (validation)
```

## Critical Rules

1. **Shared lib is SSOT** — all constants, paths, banner() come from `lib/`. Never redefine locally.
2. **GAFF cache is append-only** — `cache/gaff_cache.json` grows as new ligands are parameterized. Don't delete entries.
3. **SMILES fixes require cascade reruns** — if you fix a SMILES in scripts 02-08, ALL downstream MD scripts using that ligand must rerun.
4. **DFT jobs are CPU-bound** — NEVER run two DFT scripts on same machine simultaneously (cache thrashing makes both 2× slower).
5. **MD trajectories are gitignored** — only JSON summaries in `cache/dft/` and `cache/kinetics/` are committed.
6. **CI smoke test** — `in_silico_smoke.yml` runs script 01 with `SILKEN_FORCE_PLATFORM=CPU`, padding 0.5nm, 1000 min iterations.

## DFT Gotchas

- **PySCF has no SDD basis** — use `lanl2dz` for Cu/Co, `stuttgart_rsc` for Ce
- **wb97x-d not supported** — PySCF dispersion module lacks it; use `wb97x` (range separation is the main fix)
- **UKS convergence** — open-shell transition metals need `level_shift=0.3` to avoid SCF oscillation
- **Geometry optimization** — Cl atom on flat PES never converges GAU displacement criterion; programmatic geometry sufficient
- **Spin parity** — odd electrons requires odd spin (2S); even electrons requires even spin. Auto-detect with fallback.

## MD Gotchas

- **OpenMM NaN** — usually insufficient minimization. Floor at 500 iterations for any box.
- **GAFF matching** — `GAFFTemplateGenerator` matches by graph structure, not by name. One `Molecule` per unique species.
- **Fibonacci sphere** — ligand placement uses deterministic Fibonacci sphere + tiny jitter (seed=42).
- **Temperature ramp** — NVT equilibration ramps 100K → 298K in 5K steps with protein heavy-atom restraints.

## Xylem Sap Configurator

`lib/xylem_sap.py` has 7 profiles (Pinus summer/winter, Picea, Quercus, Fagus, generic).
Each profile: pH, glucose_mM, ionic_strength, ions dict. Used by script 14.

## When Modifying

- **Adding a new ligand**: create parameterize script (0N), add to gaff_cache, add SDF to ligands/, add test
- **Adding a sensor field**: update packet format in CLAUDE.md §3, update TelemetryUnpackerService, update firmware
- **Changing a constant**: update `lib/constants.py` ONLY, check which scripts use it, verify cached results still valid
- **After any script change**: run `pytest tools/in_silico/tests/` to verify 68 tests pass
