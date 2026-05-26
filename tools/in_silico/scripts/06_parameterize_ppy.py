#!/usr/bin/env python
"""
L2 step 2e — parameterize polypyrrole (PPy) oligomer for GAFF.

Why PPy
-------
Polypyrrole is the optional conductive copolymer additive in the Gen 2.0
anode MET stack (docs/01_03 §2.3). Electrochemically polymerized between
Layer 2 (MWCNT) and the Os-polymer, it boosts electronic conductivity of
the hydrogel matrix (10-100 S/cm vs ~10⁻⁴ for Os-polymer alone) and adds
capacitive buffer for peak current during STM32 wakeup.

We parameterize a PPy pentamer (5 pyrrole units, doped form) to check
whether PPy sterically interferes with the FAD active site of dgrFAD-GDH.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/06_parameterize_ppy.py
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

# Polypyrrole pentamer (5 × pyrrole linked 2,5).
# Neutral (undoped) form — doping is an electrochemical process, not
# captured in classical FF. Neutral parameterization is standard for MD.
# Alpha,alpha' (2,5) linked polypyrrole — the standard oxidative coupling.
# Each pyrrole ring: N-C2=C3-C4=C5, linked at C2 and C5 (alpha positions).
PPY_PENTAMER_SMILES = "c1ccc([nH]1)-c2ccc([nH]2)-c3ccc([nH]3)-c4ccc([nH]4)-c5ccc[nH]5"

OUT_SDF = LIGANDS_DIR / "ppy_pentamer.sdf"


def main() -> int:
    banner("Building polypyrrole pentamer from SMILES")
    print(f"  SMILES: {PPY_PENTAMER_SMILES}")
    mol = Molecule.from_smiles(PPY_PENTAMER_SMILES)
    mol.name = "PPY"
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

    banner("✅ PPy pentamer parameterized — ready for matrix MD")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
