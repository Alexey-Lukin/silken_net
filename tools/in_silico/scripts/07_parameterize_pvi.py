#!/usr/bin/env python
"""
L2 step 2f — parameterize poly(vinylimidazole) backbone (PVI, no Os) for GAFF.

Why PVI without Os
------------------
The Os redox polymer in Gen 2.0 is [Os(bpy)₂(poly-vinylimidazole)Cl]⁺/²⁺.
GAFF cannot handle transition metals, so we parameterize only the organic
PVI backbone — the polymer chain that coats the protein surface.

This answers a deferred L2 question (01_03 §3.4.1 Decision Log): does the
PVI polymer brush act as a mechanical stress source on the protein fold?
If RMSD stays < 3 Å with PVI copies around the protein, it's safe.

We use a PVI trimer (3 × 1-vinylimidazole repeat units) as the proxy.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/07_parameterize_pvi.py
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

from openff.toolkit import Molecule
from openmm.app import ForceField
from openmmforcefields.generators import GAFFTemplateGenerator

REPO_ROOT = Path(__file__).resolve().parents[3]
LIGANDS_DIR = REPO_ROOT / "docs/protocols/ebfc/in_silico/ligands"
CACHE_DIR = REPO_ROOT / "tools/in_silico/cache"
LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# Poly(1-vinylimidazole) trimer — 3 repeat units.
# Each unit: vinyl backbone (CH₂-CH) + imidazole ring attached at N1.
# This is the organic polymer backbone WITHOUT Os metal centers.
# Poly(1-vinylimidazole): backbone attached to N1 of imidazole.
# N3 (the other ring nitrogen) remains free to coordinate Os.
# This matches the real Os-PVI polymer where Os binds through N3.
PVI_TRIMER_SMILES = "C[C@@H](n1ccnc1)C[C@H](n2ccnc2)C[C@@H](n3ccnc3)C"

GAFF_VERSION = "gaff-2.11"
OUT_SDF = LIGANDS_DIR / "pvi_trimer.sdf"
CACHE_FILE = CACHE_DIR / "gaff_cache.json"


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main() -> int:
    banner("Building poly(vinylimidazole) trimer from SMILES")
    print(f"  SMILES: {PVI_TRIMER_SMILES}")
    mol = Molecule.from_smiles(PVI_TRIMER_SMILES)
    mol.name = "PVI"
    mol.generate_conformers(n_conformers=1)
    print(f"  Heavy atoms: {sum(1 for a in mol.atoms if a.atomic_number > 1)}")
    print(f"  Total atoms: {mol.n_atoms} | bonds: {mol.n_bonds}")
    print(f"  Total charge: {mol.total_charge}")

    mol.to_file(str(OUT_SDF), file_format="sdf")
    print(f"  Wrote {OUT_SDF.relative_to(REPO_ROOT)}")

    banner(f"Generating GAFF {GAFF_VERSION} parameters (antechamber + AM1-BCC)")
    print(f"  Cache: {CACHE_FILE.relative_to(REPO_ROOT)} (shared)")
    t = time.time()
    gaff = GAFFTemplateGenerator(
        molecules=[mol],
        forcefield=GAFF_VERSION,
        cache=str(CACHE_FILE),
    )
    forcefield = ForceField()
    forcefield.registerTemplateGenerator(gaff.generator)
    mm_top = mol.to_topology().to_openmm()
    system = forcefield.createSystem(mm_top)
    dt = time.time() - t
    print(
        f"  ✓ System built: {system.getNumParticles()} particles, "
        f"{system.getNumForces()} force terms"
    )
    print(f"  Parameterization wall-clock: {dt:.1f}s")
    print(f"  Cache file size: {CACHE_FILE.stat().st_size / 1024:.1f} KB")

    banner("✅ PVI trimer parameterized — ready for steric coverage MD")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
