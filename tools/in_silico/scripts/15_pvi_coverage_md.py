#!/usr/bin/env python
"""
L2 Gen 2.5+ — PVI backbone coverage test.

Tests whether poly(vinylimidazole) polymer brush (without Os metal)
creates steric stress on dgrGcGDH protein. PVI is the backbone of
the Os-PVI redox polymer — this test isolates the mechanical effect
of the polymer on enzyme conformation.

If RMSD stays < 3 Å with PVI added → polymer brush doesn't denature
the enzyme → safe for Gen 2.0 MET stack.

Reference: 01_03 §3.4.1 Decision Log — "PVI-backbone без металу"
"""
from __future__ import annotations

import os
import sys
import time
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
    DCDReporter,
    ForceField,
    HBonds,
    Modeller,
    PDBFile,
    Simulation,
    StateDataReporter,
)
from openmm.unit import (
    atmosphere,
    femtosecond,
    kelvin,
    kilojoule_per_mole,
    molar,
    nanometer,
    picosecond,
)
from openmmforcefields.generators import GAFFTemplateGenerator
from pdbfixer import PDBFixer

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    REPO_ROOT, AF3_PDB, LIGANDS_DIR, CACHE_FILE, RUNS_DIR,
    PH, IONIC_STRENGTH, PRESSURE_ATM, WATER_PADDING_NM, TIMESTEP_FS,
    EQUIL_NVT_PS, EQUIL_NPT_PS, N_GENIPIN, GAFF_VERSION,
)
from lib.geometry import positions_to_nm_array, restraint_protein_heavy_atoms
from lib.utils import banner, ps_to_steps, pick_platform

FAD_SDF = LIGANDS_DIR / "FAD.sdf"
GENIPIN_SDF = LIGANDS_DIR / "genipin.sdf"
PVI_SDF = LIGANDS_DIR / "pvi_trimer.sdf"
TEMPERATURE_K = 298
N_PVI = 5  # PVI trimer copies around protein
PRODUCTION_PS = int(os.environ.get("SILKEN_PRODUCTION_PS", "100"))


def main() -> int:
    for p in (AF3_PDB, FAD_SDF, GENIPIN_SDF, PVI_SDF, CACHE_FILE):
        if not p.exists():
            sys.exit(f"Missing: {p}")

    run_id = datetime.now().strftime("%Y%m%dT%H%M%S") + "_pvi_coverage"
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    banner(f"L2 PVI coverage test — {N_PVI}×PVI + {N_GENIPIN}×GEN + FAD")
    print(f"  Output: {run_dir.relative_to(REPO_ROOT)}")

    # Protein prep
    banner("Preparing protein")
    fixer = PDBFixer(filename=str(AF3_PDB))
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=PH)
    modeller = Modeller(fixer.topology, fixer.positions)

    # FAD
    banner("Loading FAD")
    fad = Molecule.from_file(str(FAD_SDF))
    fad.name = "FAD"
    modeller.add(fad.to_topology().to_openmm(), fad.conformers[0].to_openmm())

    # Genipin
    banner(f"Placing {N_GENIPIN}×genipin")
    genipin = Molecule.from_file(str(GENIPIN_SDF))
    genipin.name = "GEN"
    if not genipin.conformers:
        genipin.generate_conformers(n_conformers=1)
    g_top = genipin.to_topology().to_openmm()
    g_coords = positions_to_nm_array(genipin.conformers[0].to_openmm())
    g_coords -= g_coords.mean(axis=0)
    protein_coords = positions_to_nm_array(modeller.positions)
    protein_center = protein_coords.mean(axis=0)
    shell_r = (protein_coords - protein_center).max() + 0.8

    rng = np.random.default_rng(42)
    for pos in place_on_sphere(N_GENIPIN, shell_r, protein_center, rng):
        translated = g_coords + pos
        modeller.add(g_top, [Vec3(*xyz) for xyz in translated] * nanometer)

    # PVI trimer
    banner(f"Placing {N_PVI}×PVI trimer (polymer brush proxy)")
    pvi = Molecule.from_file(str(PVI_SDF))
    pvi.name = "PVI"
    if not pvi.conformers:
        pvi.generate_conformers(n_conformers=1)
    pvi_top = pvi.to_topology().to_openmm()
    pvi_coords = positions_to_nm_array(pvi.conformers[0].to_openmm())
    pvi_coords -= pvi_coords.mean(axis=0)
    inner_shell = shell_r - 0.3  # closer to protein than genipin

    for pos in place_on_sphere(N_PVI, inner_shell, protein_center, rng):
        translated = pvi_coords + pos
        modeller.add(pvi_top, [Vec3(*xyz) for xyz in translated] * nanometer)

    print(f"  Total ligand atoms: {N_GENIPIN * genipin.n_atoms + N_PVI * pvi.n_atoms + fad.n_atoms}")

    # Force field
    banner("Building ForceField")
    forcefield = ForceField("amber14-all.xml", "amber14/tip3pfb.xml")
    gaff = GAFFTemplateGenerator(
        molecules=[fad, genipin, pvi],
        forcefield=GAFF_VERSION,
        cache=str(CACHE_FILE),
    )
    forcefield.registerTemplateGenerator(gaff.generator)

    # Solvate
    banner("Solvating")
    modeller.addSolvent(
        forcefield,
        padding=WATER_PADDING_NM * nanometer,
        ionicStrength=IONIC_STRENGTH * molar,
    )
    n_total = modeller.topology.getNumAtoms()
    print(f"  Total atoms: {n_total}")

    # System
    banner("Building System")
    system = forcefield.createSystem(
        modeller.topology, nonbondedMethod=PME,
        nonbondedCutoff=1.0 * nanometer, constraints=HBonds,
    )
    integrator = LangevinMiddleIntegrator(
        TEMPERATURE_K * kelvin, 1.0 / picosecond, TIMESTEP_FS * femtosecond
    )
    platform = pick_platform()
    print(f"  Platform: {platform.getName()}")
    sim = Simulation(modeller.topology, system, integrator, platform)
    sim.context.setPositions(modeller.positions)

    with (run_dir / "system.pdb").open("w") as fh:
        PDBFile.writeFile(modeller.topology, modeller.positions, fh, keepIds=True)

    # Minimize
    banner("Energy minimisation (max 10000 iter)")
    sim.minimizeEnergy(maxIterations=10000)

    # Pre-relaxation
    sim.context.setVelocitiesToTemperature(10 * kelvin)
    sim.step(1000)

    # NVT
    ramp_step = 10
    banner(f"NVT: 100→{TEMPERATURE_K} K over {EQUIL_NVT_PS} ps")
    restraint = restraint_protein_heavy_atoms(system, modeller.positions, modeller.topology, k=10.0)
    sim.context.reinitialize(preserveState=True)
    sim.context.setVelocitiesToTemperature(50 * kelvin)
    steps_per_ramp = ps_to_steps(EQUIL_NVT_PS) // ((TEMPERATURE_K - 50) // ramp_step)
    for T in range(50, TEMPERATURE_K + 1, ramp_step):
        sim.integrator.setTemperature(T * kelvin)
        sim.step(steps_per_ramp)
    sim.context.setParameter("k", 0.0)

    # NPT
    banner(f"NPT: {EQUIL_NPT_PS} ps")
    barostat = MonteCarloBarostat(PRESSURE_ATM * atmosphere, TEMPERATURE_K * kelvin)
    system.addForce(barostat)
    sim.context.reinitialize(preserveState=True)
    sim.step(ps_to_steps(EQUIL_NPT_PS))

    # Production
    banner(f"Production: {PRODUCTION_PS} ps")
    report_steps = ps_to_steps(1.0)
    sim.reporters.append(StateDataReporter(
        str(run_dir / "production.csv"), report_steps,
        step=True, time=True, potentialEnergy=True, temperature=True,
        volume=True, speed=True,
    ))
    sim.reporters.append(DCDReporter(str(run_dir / "production.dcd"), report_steps * 2))

    t0 = time.time()
    sim.step(ps_to_steps(PRODUCTION_PS))
    wall = time.time() - t0
    ns_day = (PRODUCTION_PS / 1e3) / (wall / 86400)
    print(f"  Wall-clock: {wall:.1f}s  ({ns_day:.2f} ns/day)")

    # RMSD
    banner("Backbone RMSD vs frame 0 (mdtraj)")
    import mdtraj as md
    traj = md.load(str(run_dir / "production.dcd"), top=str(run_dir / "system.pdb"))
    backbone = traj.topology.select("backbone")
    traj.superpose(traj, frame=0, atom_indices=backbone)
    diff = traj.xyz[:, backbone, :] - traj.xyz[0, backbone, :]
    rmsd = np.sqrt((diff**2).sum(axis=2).mean(axis=1)) * 10.0

    mean_rmsd = np.mean(rmsd)
    std_rmsd = np.std(rmsd)
    max_rmsd = np.max(rmsd)
    verdict = "✅ STABLE" if max_rmsd < 3.0 else "⚠ NEEDS LONGER RUN"

    print(f"  Frames: {traj.n_frames}")
    print(f"  RMSD: {mean_rmsd:.3f} ± {std_rmsd:.3f} Å (max {max_rmsd:.3f})")
    print(f"  Verdict: {verdict} — PVI brush {'does NOT' if max_rmsd < 3.0 else 'MAY'} denature enzyme")

    banner(f"✅ Done — artefacts in {run_dir.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
