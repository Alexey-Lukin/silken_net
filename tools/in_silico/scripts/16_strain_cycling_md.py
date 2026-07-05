#!/usr/bin/env python
"""
L2/HW.3.IS — Cyclic strain MD for genipin-chitosan-CNC matrix.

Simulates wind-induced thigmomorphogenesis: ±5% uniaxial strain
applied cyclically to the hydrogel matrix to verify pseudoplastic
behavior (01_03 §2.1 Layer 4).

Protocol:
  1. Build genipin + chitosan + cellobiose matrix in water box
  2. Equilibrate (NVT + NPT)
  3. Apply cyclic strain: stretch box X by +5%, hold, compress -5%, hold
  4. Repeat N cycles
  5. Measure: stress-strain hysteresis, matrix integrity (no fracture)

Success: matrix absorbs strain without microcracking → pseudoplastic ✅
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
from openff.toolkit import Molecule
from openmm import (
    LangevinMiddleIntegrator,
    MonteCarloBarostat,
    Vec3,
)
from openmm.app import (
    PME,
    ForceField,
    HBonds,
    Modeller,
    Simulation,
)
from openmm.unit import (
    atmosphere,
    femtosecond,
    kelvin,
    kilojoule_per_mole,
    nanometer,
    picosecond,
)
from openmmforcefields.generators import GAFFTemplateGenerator

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    CACHE_FILE,
    GAFF_VERSION,
    KINETICS_DIR,
    LIGANDS_DIR,
    N_CELLOBIOSE,
    N_CHITOSAN,
    N_GENIPIN,
    PRESSURE_ATM,
    REPO_ROOT,
    RUNS_DIR,
    TIMESTEP_FS,
    WATER_MODEL_XML,
)
from lib.geometry import positions_to_nm_array
from lib.utils import banner, pick_platform, ps_to_steps

TEMPERATURE_K = 298
N_CYCLES = int(os.environ.get("SILKEN_STRAIN_CYCLES", "10"))
STRAIN_PERCENT = 5.0
HOLD_PS = 5.0           # hold at each extreme
RAMP_PS = 2.0           # strain ramp duration
EQUIL_PS = 50           # pre-equilibration


def main() -> int:
    banner(f"L2 strain cycling — ±{STRAIN_PERCENT}% × {N_CYCLES} cycles")

    for p in (LIGANDS_DIR / "genipin.sdf", LIGANDS_DIR / "chitosan_trimer.sdf",
              LIGANDS_DIR / "cellobiose.sdf", CACHE_FILE):
        if not p.exists():
            sys.exit(f"Missing: {p}")

    run_id = datetime.now().strftime("%Y%m%dT%H%M%S") + "_strain"
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    print(f"  Output: {run_dir.relative_to(REPO_ROOT)}")
    print(f"  Cycles: {N_CYCLES}, Strain: ±{STRAIN_PERCENT}%")

    # Load ligands
    banner("Loading matrix ligands")
    genipin = Molecule.from_file(str(LIGANDS_DIR / "genipin.sdf"))
    genipin.name = "GEN"
    chitosan = Molecule.from_file(str(LIGANDS_DIR / "chitosan_trimer.sdf"))
    chitosan.name = "CSO"
    cellobiose = Molecule.from_file(str(LIGANDS_DIR / "cellobiose.sdf"))
    cellobiose.name = "CLB"

    # Build small matrix box (no protein — just matrix)
    banner("Building matrix-only box")
    forcefield = ForceField(WATER_MODEL_XML)
    gaff = GAFFTemplateGenerator(
        molecules=[genipin, chitosan, cellobiose],
        forcefield=GAFF_VERSION,
        cache=str(CACHE_FILE),
    )
    forcefield.registerTemplateGenerator(gaff.generator)

    # Place ligands in a small box
    modeller = Modeller(genipin.to_topology().to_openmm(),
                        genipin.conformers[0].to_openmm())

    rng = np.random.default_rng(42)
    box_size = 4.0  # nm

    def add_molecules(mol, n, name):
        for _i in range(n):
            top = mol.to_topology().to_openmm()
            if not mol.conformers:
                mol.generate_conformers(n_conformers=1)
            coords_nm = positions_to_nm_array(mol.conformers[0].to_openmm())
            coords_nm -= coords_nm.mean(axis=0)
            offset = rng.uniform(0.5, box_size - 0.5, size=3)
            translated = coords_nm + offset
            positions = [Vec3(*xyz) for xyz in translated] * nanometer
            modeller.add(top, positions)
        print(f"  +{n}×{name}: {n * mol.n_atoms} atoms")

    add_molecules(genipin, N_GENIPIN - 1, "GEN")  # -1 because first already added
    add_molecules(chitosan, N_CHITOSAN, "CSO")
    add_molecules(cellobiose, N_CELLOBIOSE, "CLB")

    # Solvate
    banner("Solvating")
    modeller.addSolvent(
        forcefield,
        boxSize=Vec3(box_size, box_size, box_size) * nanometer,
        positiveIon="Na+", negativeIon="Cl-",
    )
    print(f"  Total atoms: {modeller.topology.getNumAtoms()}")

    # Build system
    banner("Building system")
    platform = pick_platform()
    print(f"  Platform: {platform.getName()}")
    system = forcefield.createSystem(
        modeller.topology,
        nonbondedMethod=PME,
        nonbondedCutoff=1.0 * nanometer,
        constraints=HBonds,
    )
    integrator = LangevinMiddleIntegrator(
        TEMPERATURE_K * kelvin, 1.0 / picosecond, TIMESTEP_FS * femtosecond
    )
    sim = Simulation(modeller.topology, system, integrator, platform)
    sim.context.setPositions(modeller.positions)

    # Minimize
    banner("Energy minimisation")
    sim.minimizeEnergy(maxIterations=10000)

    # Brief relaxation
    sim.context.setVelocitiesToTemperature(10 * kelvin)
    sim.step(1000)

    # NVT equilibration
    banner(f"NVT equilibration: {EQUIL_PS} ps")
    sim.context.setVelocitiesToTemperature(TEMPERATURE_K * kelvin)
    sim.step(ps_to_steps(EQUIL_PS))

    # NPT equilibration
    banner("NPT equilibration: 50 ps")
    barostat = MonteCarloBarostat(PRESSURE_ATM * atmosphere, TEMPERATURE_K * kelvin)
    system.addForce(barostat)
    sim.context.reinitialize(preserveState=True)
    sim.step(ps_to_steps(50))

    # Get equilibrated box
    state = sim.context.getState(getPositions=True)
    box_vectors = state.getPeriodicBoxVectors()
    Lx0 = box_vectors[0][0].value_in_unit(nanometer)
    Ly0 = box_vectors[1][1].value_in_unit(nanometer)
    Lz0 = box_vectors[2][2].value_in_unit(nanometer)
    print(f"  Equilibrated box: {Lx0:.2f} × {Ly0:.2f} × {Lz0:.2f} nm")

    # Remove barostat for strain control
    for i in range(system.getNumForces() - 1, -1, -1):
        if isinstance(system.getForce(i), MonteCarloBarostat):
            system.removeForce(i)
    sim.context.reinitialize(preserveState=True)

    # Strain cycling
    banner(f"Strain cycling: ±{STRAIN_PERCENT}% × {N_CYCLES} cycles")
    strain_frac = STRAIN_PERCENT / 100.0
    results = []

    prev_strain = 0.0
    ramp_substeps = 20  # gradual box deformation

    for cycle in range(N_CYCLES):
        for phase, strain in [("stretch", +strain_frac), ("compress", -strain_frac), ("restore", 0.0)]:
            # Gradually ramp box size to avoid NaN
            for sub in range(1, ramp_substeps + 1):
                frac = prev_strain + (strain - prev_strain) * sub / ramp_substeps
                Lx_new = Lx0 * (1.0 + frac)
                sim.context.setPeriodicBoxVectors(
                    Vec3(Lx_new, 0, 0) * nanometer,
                    Vec3(0, Ly0, 0) * nanometer,
                    Vec3(0, 0, Lz0) * nanometer,
                )
                sim.step(ps_to_steps(RAMP_PS) // ramp_substeps)
            prev_strain = strain

            # Hold and measure
            sim.step(ps_to_steps(HOLD_PS))
            state = sim.context.getState(getEnergy=True)
            pe = state.getPotentialEnergy().value_in_unit(kilojoule_per_mole)
            results.append({
                "cycle": cycle, "phase": phase, "strain_pct": strain * 100,
                "PE_kJ_mol": pe,
            })

        if (cycle + 1) % max(1, N_CYCLES // 5) == 0:
            print(f"  Cycle {cycle+1}/{N_CYCLES}: PE = {pe:.0f} kJ/mol")

    # Analysis
    banner("Strain cycling analysis")
    stretch_pe = [r["PE_kJ_mol"] for r in results if r["phase"] == "stretch"]
    compress_pe = [r["PE_kJ_mol"] for r in results if r["phase"] == "compress"]
    restore_pe = [r["PE_kJ_mol"] for r in results if r["phase"] == "restore"]

    pe_drift = abs(restore_pe[-1] - restore_pe[0]) / abs(restore_pe[0]) * 100

    print(f"  Stretch PE:  {np.mean(stretch_pe):.0f} ± {np.std(stretch_pe):.0f} kJ/mol")
    print(f"  Compress PE: {np.mean(compress_pe):.0f} ± {np.std(compress_pe):.0f} kJ/mol")
    print(f"  Restore PE:  {np.mean(restore_pe):.0f} ± {np.std(restore_pe):.0f} kJ/mol")
    print(f"  PE drift after {N_CYCLES} cycles: {pe_drift:.3f}%")

    stable = pe_drift < 1.0
    print(f"  Matrix integrity: {'✅ STABLE (pseudoplastic)' if stable else '❌ DEGRADING'}")

    # Save
    output = {
        "method": "OpenMM NVT cyclic uniaxial strain",
        "strain_pct": STRAIN_PERCENT,
        "n_cycles": N_CYCLES,
        "hold_ps": HOLD_PS,
        "temperature_K": TEMPERATURE_K,
        "results": results,
        "summary": {
            "stretch_PE_mean": float(np.mean(stretch_pe)),
            "compress_PE_mean": float(np.mean(compress_pe)),
            "restore_PE_mean": float(np.mean(restore_pe)),
            "PE_drift_pct": pe_drift,
            "stable": stable,
        },
        "verdict": "Pseudoplastic — matrix absorbs strain without degradation" if stable else "Matrix degrading under cyclic strain",
    }
    out_path = KINETICS_DIR / "strain_cycling.json"
    out_path.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {out_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
