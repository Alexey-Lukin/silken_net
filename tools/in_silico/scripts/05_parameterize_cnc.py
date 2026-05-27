#!/usr/bin/env python
"""
L2 step 2d — parameterize a cellobiose unit (CNC proxy) for GAFF.

Why cellobiose
--------------
Cellulose nanocrystals (CNC) in the Gen 2.0 matrix (2-6% w/w, docs/01_03
§2.1) are rigid crystalline fibers ~100 nm long. Simulating an entire CNC
particle is infeasible in all-atom MD. Instead we use cellobiose — the
β-1,4-linked glucose disaccharide that is the fundamental repeat unit of
cellulose. Multiple copies placed with position restraints approximate the
stiff crystalline surface that the protein sees in the real matrix.

Same GAFF pipeline as genipin (script 03): SMILES → OpenFF → AM1-BCC → cache.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/05_parameterize_cnc.py
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

from openff.toolkit import Molecule
from openmm.app import ForceField
from openmmforcefields.generators import GAFFTemplateGenerator

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import REPO_ROOT, LIGANDS_DIR, CACHE_FILE, GAFF_VERSION
from lib.utils import banner

LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)

# Cellobiose: β-D-glucopyranosyl-(1→4)-β-D-glucopyranose.
# PubChem CID 10712. The minimal repeat of cellulose.
# Both anomeric carbons specified as β (equatorial OH) to satisfy OpenFF
# stereo requirements. In solution the reducing end equilibrates α/β,
# but for MD we need a single defined conformer.
CELLOBIOSE_SMILES = (
    "OC[C@H]1O[C@@H](O)[C@H](O)[C@@H](O)[C@@H]1"
    "O[C@@H]2[C@@H](CO)O[C@@H](O)[C@H](O)[C@@H]2O"
)

OUT_SDF = LIGANDS_DIR / "cellobiose.sdf"


def main() -> int:
    banner("Building cellobiose from SMILES")
    print(f"  SMILES: {CELLOBIOSE_SMILES}")
    mol = Molecule.from_smiles(CELLOBIOSE_SMILES)
    mol.name = "CLB"
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

    banner("✅ Cellobiose parameterized — GAFF params cached, cellobiose.sdf ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
