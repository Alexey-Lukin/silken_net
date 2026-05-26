#!/usr/bin/env python
"""
L2 step 2c — parameterize a chitosan trimer (3 × D-glucosamine) for GAFF.

Why a trimer and not a full polymer
------------------------------------
Real chitosan in the Gen 2.0 matrix is 200-500 kDa (1500-4000 residues), but
GAFF is designed for small molecules. A trimer (3 × β-1,4-linked GlcN)
captures the key chemistry: primary amine groups (-NH₂) that react with
genipin, hydroxyl groups, and the pyranose ring conformational flexibility.
Multiple trimer copies in the MD box approximate the crowding effect of a
longer chain without requiring polymer-specific force fields.

Deacetylation >75% per docs/01_03 §2.1 — all three units are fully
deacetylated (free -NH₂, no N-acetyl groups).

Same GAFF pipeline as genipin (script 03): SMILES → OpenFF → AM1-BCC → cache.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/04_parameterize_chitosan.py
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

from openff.toolkit import Molecule
from openmm.app import ForceField
from openmmforcefields.generators import GAFFTemplateGenerator

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import LIGANDS_DIR, CACHE_FILE, GAFF_VERSION

LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)

# Chitosan trimer: 3 × D-glucosamine linked β-1,4.
# Each unit: 2-amino-2-deoxy-D-glucose (GlcN), fully deacetylated.
# Built as: GlcN-β(1→4)-GlcN-β(1→4)-GlcN with reducing-end OH.
CHITOSAN_TRIMER_SMILES = (
    "N[C@@H]1[C@@H](O)[C@H](O)[C@@H](CO)O[C@@H]1"
    "O[C@H]2[C@H](O)[C@@H](N)[C@@H](O[C@@H]2CO)"
    "O[C@H]3[C@H](O)[C@@H](N)[C@H](O)[C@@H](CO)O3"
)

OUT_SDF = LIGANDS_DIR / "chitosan_trimer.sdf"


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main() -> int:
    banner("Building chitosan trimer from SMILES")
    print(f"  SMILES: {CHITOSAN_TRIMER_SMILES}")
    mol = Molecule.from_smiles(CHITOSAN_TRIMER_SMILES)
    mol.name = "CSO"
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

    banner("✅ Chitosan trimer parameterized — GAFF params cached, chitosan_trimer.sdf ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
