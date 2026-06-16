---
name: in-silico
description: "Use when working on the silken_net in-silico surface — the EBFC Gen 2.0 Zero-Lab DFT+MD pipeline (tools/in_silico/, silken_md conda env): L1 AlphaFold-3 protein architecture, L2 OpenMM MD, L3 PySCF quantum-chemistry (ΔSCF redox cascade, Hammett mediator series, ZIF-cathode DET, cluster-continuum solvation), L4 kinetics/EIS, plus the Стаття 1 computes. Operational playbook — the script dependency graph, the hard-won DFT/MD gotchas (no density_fit for Os/Ce, level_shift=0.3 for open-shell metals, never two heavy DFT jobs per CPU, 10K MD pre-relaxation, thermodynamic proton reference for PCET), the conda-lock env, and the cache-is-SSOT discipline; routes to the 01_03 §3.4 + protocols/ebfc/in_silico canon, does not restate results. Examples: \"run or add a DFT/MD script\", \"why does the Os(III) SCF oscillate forever\", \"the FADH2->Os cascade comes out uphill\", \"set up the in-silico env\", \"why is density_fit slower for Ce\", \"add a ligand to the pipeline\", \"check the cascade verdict\"."
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
| `docs/08_02_Academic_Institutions_Registry.md` | Мінаєв (DFT) + ЧМА Бушуєва (enzymes/EIS) validation; xylem sap (bio hub) |
| `docs/08_01_Joint_Publications_and_IP_Strategy.md` | Publication plan — Стаття 1 (honest reframe 2026-06-05) |
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
  29 (Nelsen λ) ← standalone (FADH₂•⁺ pathological → metal hops = ③) · 29b ← rescues 29 (FADH⁻/FADH• couple → anode inner-sphere λ_i 0.39 eV)
  21e (Os mediator Hammett series ①) ← 21b geometry
  32 (PCET E°) → 33 (PCET cascade) ← lumiflavin
  34 (micro-solvation ② cluster-continuum) ← 21b geom + hexaaqua + aqua/bis-Im speciation → 34b (ωB97X ΔSCF cross-check)

L3b DFT cathode (CPU):
  23 (ZIF clusters) → 24 (hopping t_ij, 3 pairs) → 25 (k_ET vs λ ③) ← 35 (metal λ, Nelsen 4-pt)
  24b (FO-DFT two-state coupling) = rigor upgrade of 24's crude t_ij → re-ran 25 [CHEM.14 ✅: t_ij 0.00546 eV + 0.18 eV site-gap → borderline robust to coupling, ×10⁵ excluded]

L4 Kinetics (CPU, seconds):
  30 (delta_t) → 30b (Monte Carlo) → 31 (EIS) → 40 (validation)

Bridge:
  27 (MD→DFT ensemble, FAD HOMO) ← 11 (DCD trajectory) + DFT
  28b (CHEM.16 tunneling ensemble ✅) ← 11 (DCD) + 28 (Beratan-Onuchic over frames) → β·d 2.02±0.13, thermally robust
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
- **Os mediator speciation matters (② / script 34)** — chloro vs aqua vs bis-imidazole shifts E°(Os III/II) by ~0.5 eV (cascade Δ −0.91 chloro → −0.61 bis-Im → −0.40 aqua, all computed; stronger σ-donor → lower E° → worse acceptor); the experiment (+200 mV) + real Os-PVI polymer likely measure the **aqua / bis-Im** form, not the chloro complex. The aqua couple is +2/+3 → larger group-8 PCM differential-solvation bias (benchmark [Os(H₂O)₆] n6→n18 +0.98 eV). Decompose the cascade gap into speciation + solvation; don't lump it. No `density_fit` for Os, `level_shift=0.3` for the Os(III) UKS doublet. **Functional-robust** — ωB97X (34b) reproduces the aqua>bis-Im>chloro ordering.
- **lo.PM / lo.Boys crash (PySCF `lib.einsum` version bug)** — `ValueError: not enough values to unpack (expected 4, got 3)` in `pipek.py`. For the 2-orbital FO-DFT localisation (24b) skip PySCF `lo` entirely: diagonalise the metal-projected 2×2 Mulliken population matrix in the {i,j} MO basis → rotation `R` → `H_ab` = off-diagonal of `Rᵀ·diag(εᵢ,εⱼ)·R` (Mulliken-Hush diabatisation, pure numpy; F is diagonal = ε in the orthonormal MO basis).

## MD Gotchas (Hard-Won Lessons)

- **10K pre-relaxation mandatory** — 500-1000 steps at 10K before NVT ramp. Without it → NaN on ~50% of runs with multiple ligands.
- **Fibonacci sphere placement** — deterministic (seed=42) but can create bad contacts at specific positions. 313K (40°C) particularly vulnerable — skip if NaN persists after 3 attempts (3/4 temps sufficient).
- **GAFF matching** — `GAFFTemplateGenerator` matches by graph structure. One `Molecule` per unique chemical species is enough.
- **L2 10ns RMSD ~4 Å is normal** — AF3 structures relax 3-5 Å under AMBER ff14SB for large enzymes. Check **Rg** (radius of gyration) — if stable → protein folded, RMSD is just conformational relaxation. Full equilibration needs 20-50 ns.
- **25GB DCD files** — use `stride=10` or `stride=100` when loading with mdtraj. Full load kills memory.
- **PBC unwrap for ensemble graph analysis (CHEM.16 / 28b)** — a PBC-wrapped protein/cofactor splits a contact graph (artificial >cutoff gaps) → Dijkstra returns NaN. `make_molecules_whole()` makes each molecule whole but leaves a SEPARATE non-covalent cofactor (FAD) in a *different periodic image* → still disconnected (verified 1/15 frames). Use `traj.image_molecules(inplace=True)` (default anchor = largest molecule = protein) to co-locate everything into the protein's image (15/15 frames). Apply on the FULL topology, before `atom_slice`.

## Cascade Verdict Summary

Verified cascade = **+465 mV / −0.47 eV downhill** (E°(Os +200) − E°(FAD-GDH −265 mV SHE), Schachinger, Ma & Ludwig 2022; numbers mirror SUMMARY — edit there). Raw DFT is uphill in every method (numbers → SUMMARY / L3):

| Method | ΔG/e⁻ (eV) | vs verified −0.47 | Use for |
|--------|-----------|----------------|---------|
| ΔSCF ωB97X (adiabatic) | +0.884 | 1.35 eV | raw DFT (uphill) |
| ΔSCF ωB97X (vertical) | +0.998 | 1.47 eV | baseline |
| Koopmans ωB97X | +5.884 | 6.35 eV | **never use** (RSH artifact) |
| B3LYP Koopmans «corrected» −0.07 | −0.07 | withdrawn | tuned to the wrong −0.14 (+60 mV FAD) — do NOT cite |

~1.3 eV gap = mediator **speciation** (chloro→aqua +0.51) + **PCM differential solvation** (+0.20/3 H₂O → full shell), decomposed by ② (script 34); [Os(H₂O)₆] benchmark +0.98 eV. Rigorous closure = QM/MM (Мінаєв).

## When Modifying

- **Adding a ligand**: script 0N (parameterize) → add to gaff_cache → SDF to ligands/ → add test → rerun downstream MD
- **Changing a constant**: `lib/constants.py` ONLY → check which cached JSON uses it
- **After any change**: `pytest tools/in_silico/tests/` → commit → update all the SSOT docs above
- **Drift-proof comments/constants** — never hardcode a mirror of another script's result (crude t_ij, single-snapshot β·d, an E°); LOAD it from that script's cache JSON at runtime (24b/28b do this) so it can't silently diverge
- **Verify a doc value against its cache** — the cache JSON is ground truth; any computed number in SUMMARY/PIPELINE/01_03 must match it (caught SUMMARY §Cathode "Ce 0.87" = the *computed* λ, lit = 1.0)
- **Script-list One-Home** — README = inventory (what + cost) · SUMMARY = results · PIPELINE_STATUS = per-script status + volatile counts. Update the RIGHT one; never mirror numbers across them (a past drift source: README ↔ SUMMARY both listed scripts)
- **Don't `git add -A` a still-warm background-compute output** — read + sanity-check it first (physical? expected range? n_valid? ≈ a reference?) before staging
- **New DFT script**: import from `lib.constants` + `lib.utils` + `lib.dft_utils`. Use `level_shift=0.3` for UKS. No density_fit for heavy metals.
- **New MD script**: import from `lib.constants` + `lib.geometry` + `lib.utils`. Use 10K pre-relaxation + 10K ramp step + `maxIterations=10000`.
