# `tools/in_silico/` — Zero-Lab Computational Stack (L1 → L4)

This directory hosts the **Python-based simulation environment** for the EBFC
in-silico validation pipeline described in
[`docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md §3.4`](../../docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md).

| Level | Tool | What we model |
|-------|------|---------------|
| **L1** | AlphaFold 3 / ESMFold | Protein architecture — ✅ Passed 2026-05-24 (`d_FAD = 15.998 Å`) |
| **L2** | **OpenMM** (Python API) | Molecular dynamics — water box, pH 4.5, genipin/Os-polymer/CNC stability |
| **L3** | PySCF | DFT — HOMO/LUMO of Os redox polymer vs FAD cofactor |
| **L4** | Cantera + MM extension | Reaction kinetics — `delta_t` for Lorenz attractor |

SSOT artifacts (PDB structures, validation results, papers) live in
`docs/protocols/ebfc/in_silico/`. Scripts live in `scripts/` here.

---

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
