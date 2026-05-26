"""Shared MD utility functions for L2 molecular dynamics scripts."""
from __future__ import annotations

from datetime import datetime
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
RUNS_DIR = REPO_ROOT / "tools/in_silico/cache/runs"
AF3_PDB = REPO_ROOT / "docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb"
LIGANDS_DIR = REPO_ROOT / "docs/protocols/ebfc/in_silico/ligands"
CACHE_FILE = REPO_ROOT / "tools/in_silico/cache/gaff_cache.json"


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
    import mdtraj as md

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
