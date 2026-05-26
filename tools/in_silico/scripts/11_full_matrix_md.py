#!/usr/bin/env python
"""
L2-extended — full matrix stability MD: protein + FAD + genipin + chitosan + CNC.

Purpose (per docs/01_03 §3.4, step 3)
--------------------------------------
Extends the baseline genipin-only MD (script 10) by adding the remaining
components of the Gen 2.0 protective matrix:
  - Chitosan trimer oligomers (proxy for the chitosan backbone)
  - Cellobiose units (proxy for CNC — cellulose nanocrystal fibrils)

The question: does the FULL matrix (not just genipin alone) preserve the
protein fold? If RMSD < 3 Å → the complete Genipin-Chitosan-CNC hydrogel
is compatible with dgrGcGDH at pH 4.5.

Builds on script 10's verified result (RMSD 0.95 ± 0.20 Å with genipin
alone). If this script shows higher RMSD, the difference isolates the
effect of chitosan/CNC on the fold.

Prerequisites: scripts 02, 03, 04, 05 (parameterize FAD, genipin, chitosan, CNC).

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/11_full_matrix_md.py
    # longer run:
    SILKEN_PRODUCTION_PS=500 python tools/in_silico/scripts/11_full_matrix_md.py
"""
from __future__ import annotations

import os
import sys
import time
from datetime import datetime
from pathlib import Path

import numpy as np
import openmm
from openff.toolkit import Molecule
from openmm import (
    LangevinMiddleIntegrator,
    MonteCarloBarostat,
    Platform,
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
from lib.geometry import positions_to_nm_array, place_on_sphere, restraint_protein_heavy_atoms
from lib.utils import banner, ps_to_steps, pick_platform

REPO_ROOT = Path(__file__).resolve().parents[3]
AF3_PDB = REPO_ROOT / "docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb"
LIGANDS_DIR = REPO_ROOT / "docs/protocols/ebfc/in_silico/ligands"
FAD_SDF = LIGANDS_DIR / "FAD.sdf"
GENIPIN_SDF = LIGANDS_DIR / "genipin.sdf"
CHITOSAN_SDF = LIGANDS_DIR / "chitosan_trimer.sdf"
CELLOBIOSE_SDF = LIGANDS_DIR / "cellobiose.sdf"
CACHE_FILE = REPO_ROOT / "tools/in_silico/cache/gaff_cache.json"
RUNS_DIR = REPO_ROOT / "tools/in_silico/cache/runs"

PH = 4.5
TEMPERATURE_K = 298
PRESSURE_ATM = 1.0
IONIC_STRENGTH = 0.05
WATER_PADDING_NM = 1.0
TIMESTEP_FS = 2.0

EQUIL_NVT_PS = 50
EQUIL_NPT_PS = 100
PRODUCTION_PS = int(os.environ.get("SILKEN_PRODUCTION_PS", "100"))

N_GENIPIN = 10
N_CHITOSAN = 5
N_CELLOBIOSE = 8
GAFF_VERSION = "gaff-2.11"

REPORT_EVERY_PS = 1.0
TRAJECTORY_EVERY_PS = 2.0


def main() -> int:
    prereqs = [AF3_PDB, FAD_SDF, GENIPIN_SDF, CHITOSAN_SDF, CELLOBIOSE_SDF, CACHE_FILE]
    for p in prereqs:
        if not p.exists():
            sys.exit(f"Missing prerequisite: {p}\nRun scripts 02-05 first.")

    run_id = datetime.now().strftime("%Y%m%dT%H%M%S") + "_fullmatrix"
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    banner(f"L2-extended full matrix MD — run {run_id}")
    print(f"  Output: {run_dir.relative_to(REPO_ROOT)}")
    print(f"  Matrix: {N_GENIPIN}×GEN + {N_CHITOSAN}×CSO + {N_CELLOBIOSE}×CLB")
    print(f"  Production: {PRODUCTION_PS} ps  (env SILKEN_PRODUCTION_PS to override)")

    # ── 1. Protein ──
    banner("Preparing protein (pdbfixer, strip FAD, add Hs @ pH 4.5)")
    fixer = PDBFixer(filename=str(AF3_PDB))
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=PH)
    print(f"  Protein: {fixer.topology.getNumResidues()} res, {fixer.topology.getNumAtoms()} atoms")

    modeller = Modeller(fixer.topology, fixer.positions)

    # ── 2. FAD at AF3 pose ──
    banner("Loading FAD from SDF (AF3 active-site pose)")
    fad = Molecule.from_file(str(FAD_SDF))
    fad.name = "FAD"
    modeller.add(fad.to_topology().to_openmm(), fad.conformers[0].to_openmm())
    print(f"  +FAD: {fad.n_atoms} atoms")

    # ── 3. Load ligand templates ──
    banner("Loading ligand templates")
    genipin = Molecule.from_file(str(GENIPIN_SDF))
    genipin.name = "GEN"
    if not genipin.conformers:
        genipin.generate_conformers(n_conformers=1)

    chitosan = Molecule.from_file(str(CHITOSAN_SDF))
    chitosan.name = "CSO"
    if not chitosan.conformers:
        chitosan.generate_conformers(n_conformers=1)

    cellobiose = Molecule.from_file(str(CELLOBIOSE_SDF))
    cellobiose.name = "CLB"
    if not cellobiose.conformers:
        cellobiose.generate_conformers(n_conformers=1)

    print(f"  GEN: {genipin.n_atoms} atoms | CSO: {chitosan.n_atoms} atoms | CLB: {cellobiose.n_atoms} atoms")

    # ── 4. Place ligands on Fibonacci sphere ──
    protein_coords_nm = positions_to_nm_array(modeller.positions)
    protein_center = protein_coords_nm.mean(axis=0)
    shell_radius = (protein_coords_nm - protein_center).max() + 0.8

    rng = np.random.default_rng(42)

    banner(f"Placing {N_GENIPIN}×GEN on shell (r={shell_radius:.1f} nm)")
    place_on_sphere(modeller, genipin, N_GENIPIN, protein_center, shell_radius, rng, offset=0)
    print(f"  +{N_GENIPIN}×GEN: {N_GENIPIN * genipin.n_atoms} atoms")

    banner(f"Placing {N_CHITOSAN}×CSO on outer shell")
    place_on_sphere(modeller, chitosan, N_CHITOSAN, protein_center, shell_radius + 0.5, rng, offset=N_GENIPIN)
    print(f"  +{N_CHITOSAN}×CSO: {N_CHITOSAN * chitosan.n_atoms} atoms")

    banner(f"Placing {N_CELLOBIOSE}×CLB on outer shell")
    place_on_sphere(modeller, cellobiose, N_CELLOBIOSE, protein_center, shell_radius + 0.3, rng, offset=N_GENIPIN + N_CHITOSAN)
    print(f"  +{N_CELLOBIOSE}×CLB: {N_CELLOBIOSE * cellobiose.n_atoms} atoms")

    # ── 5. Force field ──
    banner("Building ForceField (AMBER ff14SB + TIP3P + GAFF for all ligands)")
    forcefield = ForceField("amber14-all.xml", "amber14/tip3pfb.xml")
    gaff = GAFFTemplateGenerator(
        molecules=[fad, genipin, chitosan, cellobiose],
        forcefield=GAFF_VERSION,
        cache=str(CACHE_FILE),
    )
    forcefield.registerTemplateGenerator(gaff.generator)

    # ── 6. Solvate ──
    banner("Solvating (TIP3P + 0.05 M NaCl)")
    modeller.addSolvent(
        forcefield,
        padding=WATER_PADDING_NM * nanometer,
        ionicStrength=IONIC_STRENGTH * molar,
        positiveIon="Na+",
        negativeIon="Cl-",
    )
    total_atoms = modeller.topology.getNumAtoms()
    print(f"  Total atoms after solvation: {total_atoms}")

    # ── 7. System ──
    banner("Building System")
    system = forcefield.createSystem(
        modeller.topology,
        nonbondedMethod=PME,
        nonbondedCutoff=1.0 * nanometer,
        constraints=HBonds,
    )
    integrator = LangevinMiddleIntegrator(
        TEMPERATURE_K * kelvin, 1.0 / picosecond, TIMESTEP_FS * femtosecond,
    )
    platform = pick_platform()
    print(f"  Platform: {platform.getName()}")
    sim = Simulation(modeller.topology, system, integrator, platform)
    sim.context.setPositions(modeller.positions)

    with (run_dir / "system.pdb").open("w") as fh:
        PDBFile.writeFile(modeller.topology, modeller.positions, fh, keepIds=True)

    # ── 8. Minimise ──
    banner("Energy minimisation (max 5000 iter)")
    t = time.time()
    sim.minimizeEnergy(maxIterations=5000)
    e_min = sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    print(f"  PE after min: {e_min:.2f} kJ/mol  ({time.time()-t:.1f}s)")

    # ── 9. NVT ──
    banner(f"NVT equilibration: 100→298 K over {EQUIL_NVT_PS} ps (protein restrained)")
    restraint = restraint_protein_heavy_atoms(system, modeller.positions, modeller.topology, k=10.0)
    sim.context.reinitialize(preserveState=True)
    sim.context.setVelocitiesToTemperature(100 * kelvin)
    steps_per_ramp = ps_to_steps(EQUIL_NVT_PS) // ((TEMPERATURE_K - 100) // 5)
    for T in range(100, TEMPERATURE_K + 1, 5):
        sim.integrator.setTemperature(T * kelvin)
        sim.step(steps_per_ramp)
    e_nvt = sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    print(f"  PE after NVT: {e_nvt:.2f} kJ/mol")

    sim.context.setParameter("k", 0.0)

    # ── 10. NPT ──
    banner(f"NPT equilibration: {EQUIL_NPT_PS} ps @ 298 K, 1 atm")
    barostat = MonteCarloBarostat(PRESSURE_ATM * atmosphere, TEMPERATURE_K * kelvin)
    system.addForce(barostat)
    sim.context.reinitialize(preserveState=True)
    sim.step(ps_to_steps(EQUIL_NPT_PS))
    e_npt = sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    print(f"  PE after NPT: {e_npt:.2f} kJ/mol")

    # ── 11. Production ──
    banner(f"Production: {PRODUCTION_PS} ps @ 298 K, 1 atm")
    dcd_path = run_dir / "production.dcd"
    csv_path = run_dir / "production.csv"
    sim.reporters.append(DCDReporter(str(dcd_path), ps_to_steps(TRAJECTORY_EVERY_PS)))
    sim.reporters.append(
        StateDataReporter(
            str(csv_path), ps_to_steps(REPORT_EVERY_PS),
            step=True, time=True, potentialEnergy=True,
            temperature=True, volume=True, speed=True,
        )
    )
    t = time.time()
    sim.step(ps_to_steps(PRODUCTION_PS))
    dt_prod = time.time() - t
    ns_per_day = (PRODUCTION_PS / 1000.0) / (dt_prod / 86400)
    print(f"  Wall-clock: {dt_prod:.1f}s  ({ns_per_day:.2f} ns/day on {platform.getName()})")

    # ── 12. RMSD analysis ──
    banner("Backbone RMSD vs frame 0 (mdtraj)")
    import mdtraj as md

    traj = md.load(str(dcd_path), top=str(run_dir / "system.pdb"))
    backbone = traj.topology.select("backbone")
    traj_aligned = traj.superpose(traj, frame=0, atom_indices=backbone)
    rmsd_nm = md.rmsd(traj_aligned, traj_aligned, frame=0, atom_indices=backbone)
    rmsd_A = rmsd_nm * 10.0
    print(f"  Frames           : {traj.n_frames}")
    print(f"  RMSD mean ± std  : {rmsd_A.mean():.3f} ± {rmsd_A.std():.3f} Å")
    print(f"  RMSD min / max   : {rmsd_A.min():.3f} / {rmsd_A.max():.3f} Å")
    plateau_test = rmsd_A.max() < 3.0
    verdict = "✅ STABLE (RMSD_max < 3 Å)" if plateau_test else "⚠ NEEDS LONGER RUN OR DESIGN REVIEW"
    print(f"  Verdict          : {verdict}")

    ligand_summary = (
        f"Genipin copies    : {N_GENIPIN} × {genipin.n_atoms} = {N_GENIPIN * genipin.n_atoms} atoms\n"
        f"Chitosan copies   : {N_CHITOSAN} × {chitosan.n_atoms} = {N_CHITOSAN * chitosan.n_atoms} atoms\n"
        f"Cellobiose copies : {N_CELLOBIOSE} × {cellobiose.n_atoms} = {N_CELLOBIOSE * cellobiose.n_atoms} atoms\n"
    )

    with (run_dir / "summary.txt").open("w", encoding="utf-8") as fh:
        fh.write(
            f"# L2-extended full matrix MD — run {run_id}\n\n"
            f"Production length : {PRODUCTION_PS} ps\n"
            f"Platform          : {platform.getName()}\n"
            f"Speed             : {ns_per_day:.2f} ns/day\n"
            f"Atoms             : {total_atoms}\n"
            f"{ligand_summary}\n"
            f"PE after min      : {e_min:.2f} kJ/mol\n"
            f"PE after NVT      : {e_nvt:.2f} kJ/mol\n"
            f"PE after NPT      : {e_npt:.2f} kJ/mol\n\n"
            f"Backbone RMSD vs frame 0:\n"
            f"  mean ± std      : {rmsd_A.mean():.3f} ± {rmsd_A.std():.3f} Å\n"
            f"  min / max       : {rmsd_A.min():.3f} / {rmsd_A.max():.3f} Å\n"
            f"  verdict         : {verdict}\n"
        )

    banner(f"✅ Done — artefacts in {run_dir.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
