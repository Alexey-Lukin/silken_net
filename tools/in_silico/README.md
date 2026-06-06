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

> **Inventory only** (what each script does + cost). Per-script **status + result numbers** live in
> [`SUMMARY.md`](../../docs/protocols/ebfc/in_silico/SUMMARY.md) (results) and
> [`PIPELINE_STATUS.md`](../../docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md) (status) — this table
> links there, it does **not** mirror the numbers (SSOT One-Home; the mirror was a drift source).

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
| 14 | `14_xylem_sap_sweep_md.py` | L2: enzyme stability across 6 tree species (pH 4.2-5.8) | ~3-4 h GPU |
| 15 | `15_pvi_coverage_md.py` | L2 Gen 2.5+: PVI backbone steric (brush) test | ~1 h GPU |
| 16 | `16_strain_cycling_md.py` | HW.3.IS: cyclic ±5% strain on the genipin-chitosan-CNC matrix | ~30 min GPU |
| 20 | `20_dft_lumiflavin.py` | L3 DFT: FAD/FADH₂ frontier orbitals (B3LYP/6-31G(d)+PCM) | ~2 min |
| 21 | `21_dft_os_bipy_complex.py` | L3 DFT: Os mediator — NH₃ surrogate (baseline, superseded by 21b) | ~30 s |
| 21b | `21b_dft_os_bpy_full.py` | L3 DFT: Os mediator — full [Os(bpy)₂(1-MeIm)Cl] with π-backbonding | ~15-30 min |
| 21c | `21c_dft_os_bpy_geomopt.py` | L3 DFT: Os mediator — geometry optimization via PySCF + geomeTRIC (terminated — Cl flat PES) | ~6-12 h |
| 21d | `21d_dft_os_bpy_wb97xd.py` | L3 DFT: publication-grade ωB97X/def2-TZVP Os complex (adiabatic ΔSCF cross-check) | ~hours |
| 21e | `21e_dft_os_mediator_series.py` | L3 ①: Os 4,4'-substituent Hammett series (9× vertical ΔSCF) → LFER mediator design rule | ~30-60 min |
| 22 | `22_compare_homo_lumo.py` | L3 aggregator: Marcus cascade diagram + verdict | ~1 s |
| 23 | `23_build_zif_clusters.py` | L3b: bimetallic ZIF cluster models for DET hopping pathway | < 1 s |
| 24 | `24_dft_hopping_integrals.py` | L3b DFT: ΔSCF hopping integrals, crude State-A/B (Marcus ET rates through ZIF) | ~3-4 h |
| 24b | `24b_fodft_coupling.py` | L3b: FO-DFT two-state coupling t_ij for the Cu-Co hop (rigor upgrade of 24; loads zif_hopping cache for comparison) | ~hours |
| 24c | `24c_cu_ru_coupling.py` | L3b CHEM.32: Cu-Ru crude ΔSCF (Co→Ru @identical geom) + Cu-Co control; t_ij non-physical (see 24d) | ~2 h |
| 24d | `24d_fodft_cu_ru.py` | L3b CHEM.32: Cu-Ru FO-DFT diabatisation → t_ij NON-PHYSICAL (frontier all-Ru, no Cu-d partner); coupling-boost CDFT-pending | ~15 min |
| 25 | `25_cathode_ket_lambda.py` | L3b ③: Marcus k_ET vs **computed** λ — honest borderline DET margin (reads 24 t_ij + 35 λ) | ~1 s |
| 27 | `27_md_dft_ensemble.py` | L3/L2 bridge: FAD HOMO across 5 MD snapshots (thermal-robustness check) | ~30 min |
| 28 | `28_electron_tunneling_pathway.py` | L3: Beratan-Onuchic tunneling pathway, single snapshot | < 1 s |
| 28b | `28b_tunneling_ensemble.py` | L3 (CHEM.16): Beratan-Onuchic over the MD ensemble → β·d distribution + conformational gating (image_molecules PBC unwrap) | ~few min |
| 29 | `29_dft_reorganization_energy.py` | L3: Nelsen λ for FADH₂/FADH₂•⁺ — radical-cation pathological in PCM (superseded by 29b) | ~1-2 h |
| 29b | `29b_dft_semiquinone_lambda.py` | L3: Nelsen λ for the FADH⁻/FADH• anode couple (rescues 29 → inner-sphere λ_i 0.39 eV) | ~1-2 h |
| 29c | `29c_outer_sphere_lambda.py` | L3: outer-sphere λ_o (Marcus two-sphere, analytical) → total anode λ; radius/ε-dominated → INDICATIVE | ~1 s |
| 32 | `32_pcet_redox_potential.py` | L3: PCET E°(FAD/FADH₂) via thermodynamic proton reference | < 1 s |
| 33 | `33_pcet_cascade_semiquinone.py` | L3: PCET-corrected cascade via neutral semiquinone (does not flip downhill → confirms PCM method-limit) | < 1 s |
| 34 | `34_dft_microsolvation.py` | L3 ②: cluster-continuum micro-solvation + speciation (chloro/aqua/bis-Im + [Os(H₂O)₆] benchmark) → decompose the PCM cascade gap | ~hours |
| 34b | `34b_wb97x_speciation.py` | L3: ωB97X ΔSCF cross-check of the ② speciation trend (functional-robustness) | ~hours |
| 35 | `35_dft_metal_reorganization.py` | L3b ③: computed inner-sphere λ for the ZIF metal hops (Nelsen 4-point on [M(H₂O)₆]) | ~hours |
| 30 | `30_kinetics_delta_t.py` | L4: EBFC kinetics → delta_t(glucose, temp) for Lorenz attractor | ~1 s |
| 30b | `30b_kinetics_monte_carlo.py` | L4b: Monte Carlo uncertainty (10k samples) → 90% CI for delta_t | ~1 s |
| 31 | `31_eis_impedance_model.py` | L4c: EIS Randles circuit → Nyquist/Bode predictions for Ti-coin tests | ~1 s |
| 31b | `31b_cathode_det_rct.py` | L4c ③: cathode DET R_ct band (borderline k_DET × unknown Γ) → kinetic competition, not a fixed Rct; INDICATIVE | ~1 s |
| 40 | `40_validate_vs_experiment.py` | Ti-coin Stage 2: compare in-silico predictions vs experimental CV/EIS | ~1 s |
| 50 | `50_thermal_stress_lame.py` | HW.3 anchor: Lamé thermal stress + Findley creep | ~1 s |
| 51 | `51_gusak_degradation_model.py` | HW.3 anchor: Arrhenius aging + Kirkendall V diffusion + H7/s6 window | ~1 s |
| 60 | `60_paper_figures.py` | Стаття 1 figures from cache (+PDB for Fig 2): Fig 2 DRAFT / 3 / 4 / 5 + S1; canon-asserted → `paper/figures/` | ~4 s |
| 61 | `61_paper_tables.py` | Стаття 1 Tables T1–T4 from cache (canon-asserted, no DFT) → `paper/06_tables.md` | ~1 s |

Numeric prefixes encode the pipeline DAG and group: 02-08 prep (GAFF),
10-16 L2 MD, 20-35 L3 DFT (23-25 + 24b L3b cathode DET; 27-35 advanced L3 —
tunneling/λ/PCET/micro-solvation/speciation),
30-31 L4 kinetics/EIS, 40 validation, 50-51 HW.3 anchor mechanics
(analytical numpy — not part of the L1-L4 enzyme DAG), 60-61 paper assets
(figures + tables, cache-only renderers). Rows are listed in execution order;
08-09 reserved for future ligands.

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

`.github/workflows/in_silico_smoke.yml` has two jobs, both triggered only on PRs
touching `tools/in_silico/**` or `docs/protocols/ebfc/in_silico/**`:

- **`lock_sync`** — fail-fast: `conda-lock.yml` must still match `environment.yml`
  (`conda-lock --check-input-hash` + `git diff`). Edit `environment.yml` without
  regenerating the lock and this job fails (see *Adding a new dependency* below).
- **`smoke`** — runs `01_smoke_test_water_box.py` with `SILKEN_FORCE_PLATFORM=CPU`
  (deterministic on hosted runners), in the env built from the **pinned**
  `conda-lock.yml`. Cached by `mamba-org/setup-micromamba@v3` keyed on the lock
  hash, so cold runs take ~10 min, cached runs ~3 min.

> **Why the lock (resolved 2026-06-04):** `environment.yml` uses `>=` specifiers,
> so a bare `conda env create` picks the latest compatible build each solve — a
> breaking transitive conda-forge release could red CI on code nobody touched and,
> worse, silently shift the numbers behind a TRL-evidence run. The committed
> `conda-lock.yml` pins exact versions + hashes per platform (`linux-64` +
> `osx-arm64`) → bit-reproducible envs. Repo-wide pin-policy home:
> [`docs/03_01_Firmware_Lifecycle_and_DMA.md §12.5`](../../docs/03_01_Firmware_Lifecycle_and_DMA.md).

## L1 protein structure (AlphaFold 3)

> **Gen 2.0 — NOT GOx.** The anode enzyme is **deglycosylated FAD-GDH**
> (dgrGcGDH from *Glomerella cingulata*), not the rejected Gen 1.0 GOx.

L1 uses AlphaFold 3 Server to predict the deglycosylated FAD-GDH + FAD
cofactor structure. The result PDB is stored in
`docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb` and used as input for all
L2 MD simulations.

1. Go to [AlphaFold 3 Server](https://alphafoldserver.com/) and sign in
   with a Google account (free for academic/non-commercial use).
2. Build the dgr-mutant sequence: run [`deglycosylate.rb`](../../docs/protocols/ebfc/in_silico/deglycosylate.rb)
   on UniProt **G8E4B5** (FAD-GDH *G. cingulata*, 600 aa) → mutates 11
   N-X-S/T sequons N→Q.
   > **Why mutate, not just "skip sugars":** AF3 does not model glycans
   > unless you explicitly add sugar ligands — feeding it the wild-type
   > sequence already yields a bare (unglycosylated) fold. So the N→Q edits
   > are **not** "removing sugars from the model." Their real purpose is
   > twofold: (a) they ARE the production gene design (dgr-mutant) so
   > *Pichia* physically can't glycosylate those sites (`01_03 §3.7`); and
   > (b) we fold the mutant to confirm the 11 point mutations themselves
   > don't destabilize the globule or perturb the FAD active site.
3. Create a new AF3 job:
   - **Protein**: paste the dgr-mutant sequence (600 aa, monomer)
   - **Ligand**: add FAD (CCD code `FAD`)
4. Submit and wait (~5 min). Download the top-ranked PDB → `dgrGcGDH_AF3.pdb`.

Current result: **`d_FAD = 15.998 Å`** (FAD N5 → Tyr90 OH, the tunneling
distance to the Os mediator), confirmed in UCSF ChimeraX. < r_tunneling
(Os-bpy ≈ 18-20 Å) → MET architecture viable. See
[`L1_protein_architecture.md`](../../docs/protocols/ebfc/in_silico/L1_protein_architecture.md)
and `01_03 §3.4` for validation.

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

## Reproducible install (pinned lock)

`conda env create -f environment.yml` (above) re-solves and grabs the latest
compatible builds — fine for day-to-day dev. For the **exact** env CI uses and
that produced the L1–L4 numbers, install from the committed `conda-lock.yml`
instead. Needs `conda-lock` once (`pipx install conda-lock`, or
`conda install -n base -c conda-forge conda-lock`):

```bash
conda-lock install -n silken_md tools/in_silico/conda-lock.yml
```

`environment.yml` stays the human-editable source; `conda-lock.yml` is the
generated pinned artifact (versions + hashes, `linux-64` + `osx-arm64`). Pin
rationale: `docs/03_01 §12.5`.

## Daily use

```bash
conda activate silken_md
python tools/in_silico/scripts/<script>.py
```

## Python version policy

Pinned to **Python 3.12** in `environment.yml`. This is the highest version
with full conda-forge coverage for the L2-L4 stack as of 2026-Q2
(`openmm 8.3+`, `pdbfixer`, `mdtraj`, `pyscf`, `scipy/numpy`). When 3.13 ships
stable builds for all dependencies, bump and refresh `environment.yml`.

## GPU notes (macOS arm64)

OpenMM ships four platforms: `Reference`, `CPU`, `OpenCL`, `CUDA`. On Apple
Silicon **`OpenCL` is the GPU platform to use** — despite Apple's "deprecated"
label, OpenMM 8.x runs on the Apple GPU through it. **Verified on this project:**
our L2 production MD (467k-atom system) auto-selects `OpenCL` and sustains
**~10–11 ns/day** on the M-series GPU. `CUDA` is Nvidia-only; `CPU`/`Reference`
are ~10–20× slower and reserved for CI determinism and tiny sanity runs.

Scripts auto-select the fastest available platform; force one with
`SILKEN_FORCE_PLATFORM=CPU` (CI uses this for reproducibility).

**This means**: the Mac (OpenCL) handles development **and** the short-to-medium
production runs we actually do (single MD trajectories up to ~10 ns ≈ a day).
Reach for cloud GPU only for **large/parallel campaigns** (100+ ns, or many
trajectories at once) per `docs/01_03 §3.4`:

- GCP `g2-standard-12` (1× L4) — ~$1–2/h
- AWS `g5.2xlarge` (1× A10G) — ~$1.20/h
- AWS `p5.2xlarge` (1× H100) — ~$30/h (heavy MD only)

## Adding a new dependency

1. Edit `environment.yml`, append under `dependencies:`.
2. Regenerate the lock (re-solves both platforms):
   ```bash
   conda-lock lock -f tools/in_silico/environment.yml \
     --lockfile tools/in_silico/conda-lock.yml -p linux-64 -p osx-arm64
   ```
3. Sync your local env to the new lock:
   `conda-lock install -n silken_md tools/in_silico/conda-lock.yml`.
4. Commit **both** `environment.yml` and `conda-lock.yml` (the `lock_sync` CI job
   fails if they drift apart).

Never `pip install` directly into the env without recording it in
`environment.yml` — that breaks reproducibility for the rest of the team
and the AI agents that consume this stack.

## Why not GROMACS / NAMD?

See `docs/01_03 §3.4` for the full rationale. TL;DR: OpenMM is Python-first,
so AI agents (Claude, Copilot) can generate runnable simulation scripts
end-to-end without us hand-writing GROMACS `.mdp` files.
