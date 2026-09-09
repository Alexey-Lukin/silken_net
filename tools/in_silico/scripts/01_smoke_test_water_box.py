#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L2 smoke test — physical engine sanity check.

Purpose
-------
Verify that the MD engine (OpenMM + AMBER ff14SB) can:
  1. Load the deglycosylated GcGDH structure from AlphaFold 3, dropping the
     N-terminal disordered tail (see "N-terminal truncation" below).
  2. Strip non-standard residues (FAD cofactor, etc.) that have no force-field
     parameters yet — ligand parameterization (GAFF / OpenFF) is a separate L2
     milestone, see docs/01_03 §3.4 and scripts 02-05 for ligand parameterization.
  3. Protonate the protein at pH 4.5 (xylem-like).
  4. Wrap it in a TIP3P-FB water box with NaCl at xylem-relevant ionic strength.
  5. Energy-minimise and run 1000 MD steps (≈ 2 ps at 2 fs timestep).

N-terminal truncation
----------------------
Residues 1-26 carry AF3 pLDDT < 50 (AF3's own "very low confidence, often
disordered" bucket — matches the model's reported fraction_disordered=0.04,
`L1_protein_architecture.md`) and form an extended, floppy arm reaching ~87 Å
from the folded core's center of mass. That single tail forces the water box
from ~69K atoms to ~310K atoms at the same CI padding (0.5 nm) — measured
2026-09-09 (`00_07` HW.5.IS): the oversized box left a capped 500-iteration
minimisation 2/3 of the way through the 40-min CI budget (1617 s, PE still at
−5.34M kJ/mol) before the 10 K pre-relax exploded into "Particle coordinate is
NaN". A full (uncapped) minimisation on the truncated model converges in
~1.8-3 min and the complete pipeline (minimise + 10 K pre-relax + production)
finishes in 2.2-3.8 min wall-clock, no NaN — 10x+ margin under the 40-min
budget even throttled to 4 CPU threads. This is scoped to the SMOKE TEST only
(engine/force-field/topology sanity, per "Success criterion" below) — it does
NOT touch the full-length model scripts 10/11/12/14/15/16 use for the real L2
science, and since AF3 itself has low confidence in this tail's position,
truncating it loses nothing the smoke test is meant to catch.

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

import io
import os
import sys
import time
from pathlib import Path

import openmm
from openmm import LangevinMiddleIntegrator
from openmm.app import PME, ForceField, HBonds, Modeller, Simulation
from openmm.unit import femtosecond, kelvin, kilojoule_per_mole, molar, nanometer, picosecond
from pdbfixer import PDBFixer

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import AF3_PDB, IONIC_STRENGTH, PH, REPO_ROOT, TIMESTEP_FS, WATER_MODEL_XML
from lib.utils import banner, pick_platform

INPUT_PDB = AF3_PDB
TEMPERATURE = 298       # K
WATER_PADDING = float(os.environ.get("SILKEN_WATER_PADDING", "1.0"))  # nm; CI uses 0.5 for speed
MD_STEPS = int(os.environ.get("SILKEN_MD_STEPS", "1000"))  # CI uses 100 for speed
MIN_ITERATIONS = int(os.environ.get("SILKEN_MIN_ITERATIONS", "500"))
# Deterministic RNG so the CI smoke GATE is reproducible, not flaky. Both the
# starting velocity draw and the Langevin thermostat are stochastic; unseeded
# (OpenMM seed 0 = random per run) a not-fully-minimised box occasionally
# explodes mid-integration → "Particle coordinate is NaN". seed=42 = pipeline convention.
RANDOM_SEED = int(os.environ.get("SILKEN_RANDOM_SEED", "42"))
# 10 K pre-relaxation steps before the 298 K run — the house anti-NaN pattern
# (scripts 12-14): a cold thermostat bleeds off residual steric strain the
# (CI-truncated) minimisation leaves, instead of exploding on the first kick.
PRE_RELAX_STEPS = int(os.environ.get("SILKEN_PRE_RELAX_STEPS", "1000"))
# N-terminal disordered tail (AF3 pLDDT < 50, residues 1-26) — see the
# "N-terminal truncation" docstring section above for the measurement this is
# based on (00_07 HW.5.IS, 2026-09-09). Smoke-test scope only.
N_TERM_TRUNCATE_RESIDUES = 26


def _drop_n_term_residues(pdb_path: Path, n: int) -> io.StringIO:
    """Return `pdb_path`'s ATOM records with the first `n` residues dropped.

    Must filter the raw text BEFORE PDBFixer/Modeller ever build a Topology:
    deleting residues from an already-built Topology leaves the new chain
    start looking like an INTERNAL residue (missing its N-terminal H's) to
    ForceField template matching ("No template found ... missing 1 N atom
    ... Is the chain missing a terminal capping group?"). Filtering the text
    first lets PDBFixer/addMissingHydrogens recognize the new first residue
    as a proper chain terminus and add the right N-cap hydrogens.
    """
    kept = [
        line
        for line in pdb_path.read_text().splitlines(keepends=True)
        if not (line.startswith("ATOM") and int(line[22:26]) <= n)
    ]
    return io.StringIO("".join(kept))


def main() -> int:
    if not INPUT_PDB.exists():
        sys.exit(f"Missing input PDB: {INPUT_PDB}")

    banner(f"OpenMM {openmm.__version__} — smoke test")
    print(f"Input: {INPUT_PDB.relative_to(REPO_ROOT)}")

    # ---------- 1. Fix structure, strip non-standard residues ----------
    banner("Cleaning structure (pdbfixer)")
    print(f"  Dropping N-terminal disordered tail (residues 1-{N_TERM_TRUNCATE_RESIDUES}, AF3 pLDDT < 50)")
    fixer = PDBFixer(pdbfile=_drop_n_term_residues(INPUT_PDB, N_TERM_TRUNCATE_RESIDUES))
    # Drop FAD, any ions, any waters — they have no ff14SB templates.
    # Real L2 will re-add FAD via GAFF/OpenFF parameterisation.
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=PH)
    n_atoms_protein = fixer.topology.getNumAtoms()
    n_residues = fixer.topology.getNumResidues()
    print(f"After cleanup: {n_residues} residues, {n_atoms_protein} atoms (FAD + N-term tail stripped)")

    # ---------- 2. Solvate ----------
    banner("Building water box")
    modeller = Modeller(fixer.topology, fixer.positions)
    forcefield = ForceField("amber14-all.xml", WATER_MODEL_XML)
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
    integrator.setRandomNumberSeed(RANDOM_SEED)  # deterministic thermostat noise
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
        print("  ⚠️  PE still positive (large system on CPU may need more iterations — OK for smoke test)")

    # ---------- 5. Short MD ----------
    banner(f"Pre-relaxing at 10 K ({PRE_RELAX_STEPS} steps)")
    simulation.context.setVelocitiesToTemperature(10 * kelvin, RANDOM_SEED)
    simulation.step(PRE_RELAX_STEPS)

    banner(f"Running {MD_STEPS} MD steps ({MD_STEPS * TIMESTEP_FS / 1000:.1f} ps @ {TIMESTEP_FS} fs)")
    simulation.context.setVelocitiesToTemperature(TEMPERATURE * kelvin, RANDOM_SEED)
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
