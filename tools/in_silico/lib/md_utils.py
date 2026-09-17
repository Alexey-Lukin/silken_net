# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared MD utility functions for L2 molecular dynamics scripts.

`prepare_protein` was de-duplicated out of five MD scripts (10/11/12/14/15) in the
2026-06-06 hygiene batch. ⚠️ How that refactor was VERIFIED, recorded here because it
is the only thing that says what the green actually covers (migrated from `00_07`
HW.5.IS on 2026-09-17): topology, atom count and residue sequence were compared per
script — NOT a bit-exact re-run. `PDBFixer.addMissingHydrogens` carries its own
pre-existing hydrogen-placement non-determinism, orthogonal to this refactor and
washed out by the first minimisation, so bit-equality was never available to assert.
⛔ The PBC trajectory loader was deliberately left untouched: it is context-dependent
and was out of that batch's scope — it is not covered by the verification above.
"""
from __future__ import annotations

from datetime import datetime
from pathlib import Path

import numpy as np

from .constants import RUNS_DIR


def create_run_dir(prefix: str = "") -> tuple[str, Path]:
    """Create a timestamped run directory under cache/runs/."""
    run_id = datetime.now().strftime("%Y%m%dT%H%M%S")
    if prefix:
        run_id = f"{prefix}_{run_id}"
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_id, run_dir


def prepare_protein(pdb_path: Path | str, ph: float = 4.5):
    """Load PDB, strip heterogens, fix missing atoms, protonate at given pH.

    Returns (topology, positions) ready for Modeller.
    """
    from pdbfixer import PDBFixer

    fixer = PDBFixer(filename=str(pdb_path))
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=ph)
    return fixer.topology, fixer.positions


def rmsd_vs_frame0(traj) -> np.ndarray:
    """Compute backbone RMSD vs first frame using mdtraj."""

    backbone = traj.topology.select("backbone")
    traj.superpose(traj, frame=0, atom_indices=backbone)
    diff = traj.xyz[:, backbone, :] - traj.xyz[0, backbone, :]
    return np.sqrt((diff**2).sum(axis=2).mean(axis=1)) * 10.0  # nm → Å


def summarize_rmsd(rmsd_angstrom: np.ndarray, label: str = "Production") -> dict:
    """Print and return RMSD summary stats."""
    stats = {
        "mean_A": float(np.mean(rmsd_angstrom)),
        "std_A": float(np.std(rmsd_angstrom)),
        "max_A": float(np.max(rmsd_angstrom)),
        "final_A": float(rmsd_angstrom[-1]),
        "n_frames": len(rmsd_angstrom),
    }
    print(f"  {label} RMSD: {stats['mean_A']:.3f} ± {stats['std_A']:.3f} Å "
          f"(max {stats['max_A']:.3f}, final {stats['final_A']:.3f})")
    return stats
