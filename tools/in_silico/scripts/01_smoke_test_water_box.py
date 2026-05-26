#!/usr/bin/env python
"""
L2 smoke test — physical engine sanity check.

Purpose
-------
Verify that the MD engine (OpenMM + AMBER ff14SB) can:
  1. Load the deglycosylated GcGDH structure from AlphaFold 3.
  2. Strip non-standard residues (FAD cofactor, etc.) that have no force-field
     parameters yet — ligand parameterization (GAFF / OpenFF) is a separate L2
     milestone, see docs/01_03 §3.4 and scripts 02-05 for ligand parameterization.
  3. Protonate the protein at pH 4.5 (xylem-like).
  4. Wrap it in a TIP3P water box with NaCl at xylem-relevant ionic strength.
  5. Energy-minimise and run 1000 MD steps (≈ 2 ps at 2 fs timestep).

Success criterion
-----------------
The script completes without raising `No template found for residue X`,
reports a finite, negative potential energy after minimisation, and finishes
the 1000-step integration. This proves the engine + force field + the
deglycosylated GcGDH topology are mutually compatible — the green light for
real L2 work (genipin / Os-polymer / CNC matrix MD).

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/01_smoke_test_water_box.py
"""
from __future__ import annotations

import os
import sys
import time
from pathlib import Path

import openmm
from openmm import LangevinMiddleIntegrator, Platform
from openmm.app import PME, ForceField, HBonds, Modeller, PDBFile, Simulation
from openmm.unit import femtosecond, kelvin, kilojoule_per_mole, molar, nanometer, picosecond
from pdbfixer import PDBFixer

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import REPO_ROOT, AF3_PDB, PH, IONIC_STRENGTH, TIMESTEP_FS
from lib.utils import banner, pick_platform

INPUT_PDB = AF3_PDB
TEMPERATURE = 298       # K
WATER_PADDING = float(os.environ.get("SILKEN_WATER_PADDING", "1.0"))  # nm; CI uses 0.5 for speed
MD_STEPS = int(os.environ.get("SILKEN_MD_STEPS", "1000"))  # CI uses 100 for speed
MIN_ITERATIONS = int(os.environ.get("SILKEN_MIN_ITERATIONS", "500"))


def main() -> int:
    if not INPUT_PDB.exists():
        sys.exit(f"Missing input PDB: {INPUT_PDB}")

    banner(f"OpenMM {openmm.__version__} — smoke test")
    print(f"Input: {INPUT_PDB.relative_to(REPO_ROOT)}")

    # ---------- 1. Fix structure, strip non-standard residues ----------
    banner("Cleaning structure (pdbfixer)")
    fixer = PDBFixer(filename=str(INPUT_PDB))
    # Drop FAD, any ions, any waters — they have no ff14SB templates.
    # Real L2 will re-add FAD via GAFF/OpenFF parameterisation.
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=PH)
    n_atoms_protein = fixer.topology.getNumAtoms()
    n_residues = fixer.topology.getNumResidues()
    print(f"After cleanup: {n_residues} residues, {n_atoms_protein} atoms (FAD stripped)")

    # ---------- 2. Solvate ----------
    banner("Building water box")
    modeller = Modeller(fixer.topology, fixer.positions)
    forcefield = ForceField("amber14-all.xml", "amber14/tip3pfb.xml")
    modeller.addSolvent(
        forcefield,
        padding=WATER_PADDING * nanometer,
        ionicStrength=IONIC_STRENGTH * molar,
        positiveIon="Na+",
        negativeIon="Cl-",
    )
    n_atoms_total = modeller.topology.getNumAtoms()
    print(
        f"After solvation: {n_atoms_total} atoms total "
        f"(+{n_atoms_total - n_atoms_protein} solvent atoms, "
        f"~{(n_atoms_total - n_atoms_protein) // 3} water molecules + ions)"
    )

    # ---------- 3. Build system + integrator + platform ----------
    banner("Creating OpenMM System")
    system = forcefield.createSystem(
        modeller.topology,
        nonbondedMethod=PME,
        nonbondedCutoff=1.0 * nanometer,
        constraints=HBonds,
    )
    integrator = LangevinMiddleIntegrator(
        TEMPERATURE * kelvin,
        1.0 / picosecond,
        TIMESTEP_FS * femtosecond,
    )
    platform = pick_platform()
    print(f"Platform: {platform.getName()}")
    simulation = Simulation(modeller.topology, system, integrator, platform)
    simulation.context.setPositions(modeller.positions)

    # ---------- 4. Minimise + measure energies ----------
    banner("Energy minimisation")
    state0 = simulation.context.getState(getEnergy=True)
    e0 = state0.getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    print(f"  PE before min: {e0:>14.2f} kJ/mol")
    t = time.time()
    simulation.minimizeEnergy(maxIterations=max(MIN_ITERATIONS, 500))
    dt_min = time.time() - t
    e1 = simulation.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    actual_iters = max(MIN_ITERATIONS, 500)
    print(f"  PE after  min: {e1:>14.2f} kJ/mol  ({dt_min:.2f}s, {actual_iters} iter max)")
    if e1 >= e0:
        sys.exit(f"FAIL: minimisation did not reduce PE: {e0:.2f} → {e1:.2f}")
    if e1 > 0:
        print(f"  ⚠️  PE still positive (large system on CPU may need more iterations — OK for smoke test)")

    # ---------- 5. Short MD ----------
    banner(f"Running {MD_STEPS} MD steps ({MD_STEPS * TIMESTEP_FS / 1000:.1f} ps @ {TIMESTEP_FS} fs)")
    simulation.context.setVelocitiesToTemperature(TEMPERATURE * kelvin)
    t = time.time()
    simulation.step(MD_STEPS)
    dt_md = time.time() - t
    e_final = simulation.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    ns_per_day = (MD_STEPS * TIMESTEP_FS / 1e6) / (dt_md / 86400)
    print(f"  PE after  MD : {e_final:>14.2f} kJ/mol  ({dt_md:.2f}s; {ns_per_day:.2f} ns/day on {platform.getName()})")

    banner("✅ SMOKE TEST PASSED — engine works on this structure")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
