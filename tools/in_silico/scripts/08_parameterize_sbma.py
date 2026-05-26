#!/usr/bin/env python
"""
L2 step 2g — parameterize SBMA monomer (zwitterionic anti-biofouling) for GAFF.

Why SBMA
--------
Sulfobetaine methacrylate (SBMA, CAS 3637-26-1) is the monomer of the
Nafion-g-PSBMA anti-biofouling membrane (Layer 5 of the anode stack,
01_03 §2.1). Each SBMA unit carries both +N(CH₃)₂ and -SO₃⁻ charges
(zwitterionic), binds 8 water molecules per chain, and creates the
hydration barrier that blocks resin biofouling.

Parameterizing SBMA enables future diffusion MD (script 13): build an
explicit PSBMA membrane layer, place glucose on one side, and measure
D_eff from MSD — replacing the literature estimate D=2×10⁻⁶ cm²/s.

The monomer is net-neutral (internal charge compensation +/−).

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/08_parameterize_sbma.py
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
from lib.utils import banner

LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)

# SBMA monomer: N-(3-sulfopropyl)-N-methacryloxyethyl-N,N-dimethylammonium betaine
# Zwitterionic: quaternary ammonium (+) and sulfonate (−), net charge 0.
# Structure: methacrylate ester — ethyl linker — N+(CH₃)₂ — propyl — SO₃⁻
SBMA_SMILES = "C=C(C)C(=O)OCC[N+](C)(C)CCCS([O-])(=O)=O"

OUT_SDF = LIGANDS_DIR / "sbma_monomer.sdf"


def main() -> int:
    banner("Building SBMA monomer from SMILES")
    print(f"  SMILES: {SBMA_SMILES}")
    print(f"  CAS: 3637-26-1")
    mol = Molecule.from_smiles(SBMA_SMILES)
    mol.name = "SBM"
    mol.generate_conformers(n_conformers=1)
    print(f"  Heavy atoms: {sum(1 for a in mol.atoms if a.atomic_number > 1)}")
    print(f"  Total atoms: {mol.n_atoms} | bonds: {mol.n_bonds}")
    print(f"  Total charge: {mol.total_charge}")
    print(f"  Net zwitterionic: N+ and SO₃⁻ cancel out")

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

    banner("✅ SBMA parameterized — ready for PSBMA membrane diffusion MD (script 13)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
