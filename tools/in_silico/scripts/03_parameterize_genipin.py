#!/usr/bin/env python
"""
L2 step 2b — parameterize genipin (the natural crosslinker) for GAFF.

Why genipin
-----------
Genipin (C11H14O5, MW 226.23) is the non-toxic plant-derived crosslinker that
replaces glutaraldehyde in the Gen 2.0 enzyme-immobilisation matrix (see
`docs/01_03 §3.6` for the rationale). To check whether GcGDH denatures inside
the genipin-chitosan-CNC scaffold, we need genipin molecules floating around
the protein in the L2 stability MD (script 10).

Same parameterization recipe as FAD (AM1-BCC + GAFF), but:
  • Genipin is small (15 heavy atoms) → antechamber finishes in ~30 seconds.
  • No bound pose to preserve — we build a fresh 3D conformer from SMILES.
  • Generates N copies for the box only at simulation time (script 10);
    here we just need a single canonical reference structure + cached params.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/03_parameterize_genipin.py
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import LIGANDS_DIR, CACHE_FILE, GAFF_VERSION

from openff.toolkit import Molecule
from openmm.app import ForceField
from openmmforcefields.generators import GAFFTemplateGenerator

LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)

# PubChem CID 442424 isomeric SMILES. C11H14O5, MW 226.23.
# Bicyclic iridoid: methyl ester + enol-ether + primary alcohol + exocyclic C=C.
GENIPIN_SMILES = "COC(=O)C1=CO[C@H]([C@H]2[C@@H]1CC=C2CO)O"

OUT_SDF = LIGANDS_DIR / "genipin.sdf"


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main() -> int:
    banner("Building genipin from SMILES")
    print(f"  SMILES: {GENIPIN_SMILES}")
    mol = Molecule.from_smiles(GENIPIN_SMILES)
    mol.name = "GEN"
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

    banner("✅ Genipin parameterized — GAFF params cached, genipin.sdf ready for script 10")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
