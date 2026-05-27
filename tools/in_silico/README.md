# `tools/in_silico/` — Zero-Lab Computational Stack (L1 → L4)

This directory hosts the **Python-based simulation environment** for the EBFC
in-silico validation pipeline described in
[`docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md §3.4`](../../docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).

| Level | Tool | What we model |
|-------|------|---------------|
| **L1** | AlphaFold 3 / ESMFold | Protein architecture — ✅ Passed 2026-05-24 (`d_FAD = 15.998 Å`) |
| **L2** | **OpenMM** (Python API) | Molecular dynamics — water box, pH 4.5, genipin/Os-polymer/CNC stability |
| **L3** | PySCF | DFT — HOMO/LUMO of Os redox polymer vs FAD cofactor + cathode DET hopping |
| **L4** | Python (scipy/numpy) | Reaction kinetics + EIS impedance → `delta_t` + Nyquist predictions |

SSOT artifacts (PDB structures, validation results, papers) live in
`docs/protocols/ebfc/in_silico/`. Scripts live in `scripts/` here.

## Scripts in `scripts/` (ordered)

| # | Script | What it does | Cost |
|---|--------|--------------|------|
| 01 | `01_smoke_test_water_box.py` | Engine sanity check — load protein, water box, 1000 steps | ~30 s |
| 02 | `02_parameterize_fad.py` | AF3 PDB + CCD SMILES → `FAD.sdf` + cached GAFF params | ~4 min |
| 03 | `03_parameterize_genipin.py` | SMILES → `genipin.sdf` + cached GAFF params | ~7 s |
| 04 | `04_parameterize_chitosan.py` | Chitosan trimer (3×GlcN) → `chitosan_trimer.sdf` + GAFF cache | ~43 s |
| 05 | `05_parameterize_cnc.py` | Cellobiose (CNC proxy) → `cellobiose.sdf` + GAFF cache | ~15 s |
| 06 | `06_parameterize_ppy.py` | Polypyrrole pentamer (conductive copolymer) → GAFF cache | ~49 s |
| 07 | `07_parameterize_pvi.py` | Poly(vinylimidazole) trimer (Os-polymer backbone, no metal) → GAFF cache | ~106 s |
| 08 | `08_parameterize_sbma.py` | SBMA monomer (zwitterionic anti-biofouling) → GAFF cache | ~1 min |
| 10 | `10_genipin_stability_md.py` | Full L2 stability MD: protein + FAD + N×genipin in water, RMSD analysis | varies |
| 11 | `11_full_matrix_md.py` | L2-extended: protein + FAD + genipin + chitosan + CNC full matrix MD | varies |
| 12 | `12_temperature_sweep_md.py` | L2: full matrix at -10, 5, 25, 40°C → RMSD(T) curve | ~2.5 h GPU |
| 13 | `13_psbma_diffusion_md.py` | L2: glucose diffusion through SBMA slab → D_eff from MSD | ~1-2 h GPU |
| 14 | `14_xylem_sap_sweep_md.py` | L2: enzyme stability across 6 tree species (different pH/ions) | ~3-4 h GPU |
| 20 | `20_dft_lumiflavin.py` | L3 DFT: FAD/FADH₂ frontier orbitals (B3LYP/6-31G(d)+PCM) | ~2 min |
| 21 | `21_dft_os_bipy_complex.py` | L3 DFT: Os mediator — NH₃ surrogate (baseline, superseded by 21b) | ~30 s |
| 21b | `21b_dft_os_bpy_full.py` | L3 DFT: Os mediator — full [Os(bpy)₂(1-MeIm)Cl] with π-backbonding | ~15-30 min |
| 21c | `21c_dft_os_bpy_geomopt.py` | L3 DFT: Os mediator — geometry optimization via PySCF + geomeTRIC | ~6-12 h |
| 22 | `22_compare_homo_lumo.py` | L3 aggregator: Marcus cascade diagram + verdict | ~1 s |
| 23 | `23_build_zif_clusters.py` | L3b: bimetallic ZIF cluster models for DET hopping pathway | < 1 s |
| 24 | `24_dft_hopping_integrals.py` | L3b DFT: ΔSCF hopping integrals (Marcus ET rates through ZIF) | ~3-4 h |
| 30 | `30_kinetics_delta_t.py` | L4: EBFC kinetics → delta_t(glucose, temp) for Lorenz attractor | ~1 s |
| 30b | `30b_kinetics_monte_carlo.py` | L4b: Monte Carlo uncertainty (10k samples) → 90% CI for delta_t | ~1 s |
| 31 | `31_eis_impedance_model.py` | L4c: EIS Randles circuit → Nyquist/Bode predictions for Ti-coin tests | ~1 s |
| 27 | `27_md_dft_ensemble.py` | L3/L2 bridge: FAD HOMO/LUMO from 5 MD snapshots (thermal robustness) | ~2-3 h |
| 28 | `28_electron_tunneling_pathway.py` | L3: Beratan-Onuchic electron tunneling pathway (NetworkX graph) | < 1 s |
| 29 | `29_dft_reorganization_energy.py` | L3: Nelsen 4-point reorganization energy λ_inner | ~2 h |
| 40 | `40_validate_vs_experiment.py` | Ti-coin Stage 2: compare in-silico predictions vs experimental CV/EIS | ~1 s |

Scripts 08-09 are reserved for future ligands. 10-14 are L2 MD runs.
20-range is L3 DFT. 23-24 are L3b cathode DET. 27-29 are advanced L3 analyses.
30-range is L4 kinetics/EIS.

## Why the GAFF detour (script 02 + 03)?

The `amber14-all.xml` bundle we load ships templates for proteins
(20 amino acids + protonation variants HID/HIE/HIP, CYX, GLH/ASH +
N-/C-caps), nucleic acids, lipids, sugars, and the standard monatomic
ions (Na+, Cl-, K+, …). It does **not** ship templates for
small-molecule cofactors (FAD, NAD, heme, …) or custom organic ligands
like genipin. The moment `forcefield.createSystem()` walks the topology
and hits an unknown residue, it raises
`ValueError: No template found for residue N (FAD)`. So before any real
L2 run you must parameterize each non-standard residue once. We do this
via the GAFF (General Amber Force Field) pipeline shipped in
`openmmforcefields`:

1. RDKit reads the molecule (PDB coords + SMILES bond orders / pure SMILES).
2. `openff.toolkit.Molecule` wraps it with chemistry-aware metadata.
3. `GAFFTemplateGenerator` shells out to AmberTools' `antechamber` →
   AM1-BCC charges, GAFF atom types, then `parmchk2` for missing FF terms.
4. Result is serialized to `cache/gaff_cache.json`. Re-running scripts
   that touch the same ligand is a cache hit (seconds, not minutes).

The cache file is committed (small, deterministic). MD trajectories under
`cache/runs/` are not.

---

## CI gate

`.github/workflows/in_silico_smoke.yml` runs `01_smoke_test_water_box.py` on
every PR that touches `tools/in_silico/**` or `docs/protocols/ebfc/in_silico/**`,
with `SILKEN_FORCE_PLATFORM=CPU` so the run is deterministic on hosted
runners. The conda env is cached by `mamba-org/setup-micromamba@v2` (keyed
on `environment.yml`), so cold runs take ~10 min, cached runs ~3 min.

## L1 protein structure (AlphaFold 3)

L1 uses AlphaFold 3 Server to predict the GOx homodimer + FAD cofactor
structure. The result PDB is stored in `docs/protocols/ebfc/in_silico/`
and used as input for all L2 MD simulations.

1. Go to [AlphaFold 3 Server](https://alphafoldserver.com/) and sign in
   with a Google account (free for academic/non-commercial use).
2. Create a new job:
   - **Protein**: paste GOx sequence (UniProt P13006, chain A, 583 aa)
   - **Ligand**: add FAD (CCD code `FAD`)
   - **Copies**: 2 (homodimer)
3. Submit and wait (~5 min). Download the top-ranked PDB.
4. Rename to `fold_gox_fad_model_0.pdb` and place in
   `docs/protocols/ebfc/in_silico/`.

Current result: `d_FAD = 15.998 Å` (inter-subunit FAD distance),
pLDDT = 93.2 (high confidence). See `01_03 §3.4` for validation.

## Quickstart (one-time setup)

```bash
# 1. Install Miniforge (conda-forge native arm64 builds)
curl -L -o /tmp/Miniforge3.sh \
  "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-arm64.sh"
bash /tmp/Miniforge3.sh -b -p "$HOME/miniforge3"
"$HOME/miniforge3/bin/conda" init zsh
# → restart shell, or `source ~/.zshrc`

# 2. Create the project env from spec
conda env create -f tools/in_silico/environment.yml

# 3. Activate
conda activate silken_md

# 4. Verify
python -m openmm.testInstallation
```

## Daily use

```bash
conda activate silken_md
python tools/in_silico/scripts/<script>.py
```

## Python version policy

Pinned to **Python 3.12** in `environment.yml`. This is the highest version
with full conda-forge coverage for the L2-L4 stack as of 2026-Q2
(`openmm 8.3+`, `pdbfixer`, `mdtraj`, `pyscf`, `cantera`). When 3.13 ships
stable builds for all dependencies, bump and refresh `environment.yml`.

## GPU notes (macOS arm64)

OpenMM ships four platforms: `Reference`, `CPU`, `OpenCL`, `CUDA`. On Apple
Silicon only `Reference` and `CPU` are reliable — Apple deprecated OpenCL
years ago and `CUDA` is Nvidia-only.

**This means**: locally, use Mac for **script development and short
sanity runs (≤ 1 ns)**. Production runs (10–100 ns) go to cloud GPU per
the infra section of `docs/01_03 §3.4`:

- GCP `g2-standard-12` (1× L4) — ~$1–2/h
- AWS `g5.2xlarge` (1× A10G) — ~$1.20/h
- AWS `p5.2xlarge` (1× H100) — ~$30/h (heavy MD only)

## Adding a new dependency

1. Edit `environment.yml`, append under `dependencies:`.
2. `conda env update -f tools/in_silico/environment.yml --prune`
3. Commit the change to `environment.yml`.

Never `pip install` directly into the env without recording it in
`environment.yml` — that breaks reproducibility for the rest of the team
and the AI agents that consume this stack.

## Why not GROMACS / NAMD?

See `docs/01_03 §3.4` for the full rationale. TL;DR: OpenMM is Python-first,
so AI agents (Claude, Copilot) can generate runnable simulation scripts
end-to-end without us hand-writing GROMACS `.mdp` files.
