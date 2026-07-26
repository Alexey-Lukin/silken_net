#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L2 — full stability MD: GcGDH + FAD + genipin matrix in xylem-like water box.

Purpose (per docs/01_03 §3.4 L2)
-------------------------------
Ask the physical question that L2 is designed to answer:

    Does the deglycosylated GcGDH protein denature inside the
    genipin-chitosan-CNC matrix at xylem pH (4.5)?

Operationally: does the protein backbone RMSD vs the AF3 starting structure
plateau within an acceptable window (typically < 3 Å) when genipin
molecules are crowding around it? A plateau ⇒ stable fold. Runaway ⇒
denaturation, and the matrix needs redesign before we order any Ti monets
(`§3.5 Ti-coin in vitro tests`).

What this script assembles
--------------------------
- Protein  : deglycosylated GcGDH from `dgrGcGDH_AF3.pdb`, prepared at pH 4.5
             by pdbfixer (AMBER ff14SB).
- FAD      : reloaded from `FAD.sdf` at its AF3 active-site pose (GAFF via
             cached parameters from script 02).
- Genipin  : N_GENIPIN copies of `genipin.sdf`, scattered around the protein
             surface (GAFF via cached parameters from script 03).
- Solvent  : TIP3P-FB water box, NaCl at 0.05 M.

Stages
------
1. Energy minimisation (≤ 5000 iterations).
2. NVT equilibration: 50 ps @ 100 K → 298 K with restraints on protein heavy
   atoms (lets solvent + ligands relax around a frozen fold).
3. NPT equilibration: 100 ps @ 298 K, 1 atm, restraints released.
4. Production: PRODUCTION_PS picoseconds @ 298 K, 1 atm.
5. Backbone RMSD analysis vs frame 0 via mdtraj → printed + saved.

Outputs (gitignored under `tools/in_silico/cache/runs/<timestamp>/`)
-------------------------------------------------------------------
- `system.pdb`    — final solvated topology (for restart / visualization)
- `production.dcd`— production trajectory
- `production.csv`— step / time / energy / temperature / RMSD
- `summary.txt`   — final RMSD stats + wall-clock per stage

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/10_genipin_stability_md.py
    # or for a longer run:
    SILKEN_PRODUCTION_PS=500 python tools/in_silico/scripts/10_genipin_stability_md.py
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
    AF3_PDB,
    CACHE_FILE,
    EQUIL_NPT_PS,
    EQUIL_NVT_PS,
    GAFF_VERSION,
    IONIC_STRENGTH,
    LIGANDS_DIR,
    N_GENIPIN,
    PH,
    PRESSURE_ATM,
    REPO_ROOT,
    RUNS_DIR,
    TIMESTEP_FS,
    WATER_MODEL_LABEL,
    WATER_MODEL_XML,
    WATER_PADDING_NM,
)
from lib.geometry import positions_to_nm_array, restraint_protein_heavy_atoms
from lib.utils import banner, pick_platform, ps_to_steps

FAD_SDF = LIGANDS_DIR / "FAD.sdf"
GENIPIN_SDF = LIGANDS_DIR / "genipin.sdf"
TEMPERATURE_K = 298
PRODUCTION_PS = int(os.environ.get("SILKEN_PRODUCTION_PS", "100"))

REPORT_EVERY_PS = 1.0    # state log frequency
TRAJECTORY_EVERY_PS = 2.0   # DCD frame frequency


def main() -> int:
    for p in (AF3_PDB, FAD_SDF, GENIPIN_SDF, CACHE_FILE):
        if not p.exists():
            sys.exit(f"Missing prerequisite: {p}\nRun scripts 02 and 03 first.")

    run_id = datetime.now().strftime("%Y%m%dT%H%M%S")
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    banner(f"L2 stability MD — run {run_id}")
    print(f"  Output: {run_dir.relative_to(REPO_ROOT)}")
    print(f"  Production length: {PRODUCTION_PS} ps  (env SILKEN_PRODUCTION_PS to override)")

    # ---------- 1. Protein prep ----------
    banner("Preparing protein (pdbfixer, strip FAD, add Hs @ pH 4.5)")
    fixer = PDBFixer(filename=str(AF3_PDB))
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=PH)
    print(f"  Protein: {fixer.topology.getNumResidues()} residues, {fixer.topology.getNumAtoms()} atoms")

    modeller = Modeller(fixer.topology, fixer.positions)

    # ---------- 2. Add FAD back at AF3 pose ----------
    banner("Loading FAD from SDF (AF3 active-site pose)")
    fad = Molecule.from_file(str(FAD_SDF))
    fad.name = "FAD"
    fad_top = fad.to_topology().to_openmm()
    fad_pos = fad.conformers[0].to_openmm()
    modeller.add(fad_top, fad_pos)
    print(f"  +FAD: {fad.n_atoms} atoms")

    # ---------- 3. Place N genipin copies around the protein ----------
    banner(f"Loading & placing {N_GENIPIN} genipin copies on a Fibonacci sphere")
    genipin_template = Molecule.from_file(str(GENIPIN_SDF))
    genipin_template.name = "GEN"
    if not genipin_template.conformers:
        genipin_template.generate_conformers(n_conformers=1)

    # Reference template topology + positions in nm (centered on its centroid)
    g_top = genipin_template.to_topology().to_openmm()
    g_coords_nm = positions_to_nm_array(genipin_template.conformers[0].to_openmm())
    g_coords_nm -= g_coords_nm.mean(axis=0)  # centroid at origin

    # Find a "shell radius" just outside the protein bounding sphere
    protein_coords_nm = positions_to_nm_array(modeller.positions)
    protein_center = protein_coords_nm.mean(axis=0)
    shell_radius = (protein_coords_nm - protein_center).max() + 0.8  # 0.8 nm margin beyond protein surface — prevents steric clash while keeping ligands close enough for interaction during equilibration

    rng = np.random.default_rng(42)
    for i in range(N_GENIPIN):
        # Fibonacci sphere for deterministic, well-spaced placement
        phi = np.pi * (3.0 - np.sqrt(5.0)) * i
        y = 1.0 - (i / max(1, N_GENIPIN - 1)) * 2.0 if N_GENIPIN > 1 else 0.0
        r = np.sqrt(max(0.0, 1.0 - y * y))
        unit_vec = np.array([np.cos(phi) * r, y, np.sin(phi) * r])
        unit_vec += rng.normal(scale=0.02, size=3)  # tiny jitter to avoid aliasing

        translated_nm = g_coords_nm + (protein_center + unit_vec * shell_radius)
        new_positions = [Vec3(*xyz) for xyz in translated_nm] * nanometer
        modeller.add(g_top, new_positions)

    print(f"  +{N_GENIPIN} × GEN: {N_GENIPIN * genipin_template.n_atoms} atoms")

    # ---------- 4. Force field with GAFF cache for ligands ----------
    banner(f"Building ForceField (AMBER ff14SB + {WATER_MODEL_LABEL} + GAFF for FAD/GEN)")
    forcefield = ForceField("amber14-all.xml", WATER_MODEL_XML)
    # GAFFTemplateGenerator matches by graph structure → one Molecule per
    # unique chemical species is enough, even if N copies sit in the topology.
    gaff = GAFFTemplateGenerator(
        molecules=[fad, genipin_template],
        forcefield=GAFF_VERSION,
        cache=str(CACHE_FILE),
    )
    forcefield.registerTemplateGenerator(gaff.generator)

    # ---------- 5. Solvate ----------
    banner(f"Solvating ({WATER_MODEL_LABEL} + 0.05 M NaCl)")
    modeller.addSolvent(
        forcefield,
        padding=WATER_PADDING_NM * nanometer,
        ionicStrength=IONIC_STRENGTH * molar,
        positiveIon="Na+",
        negativeIon="Cl-",
    )
    print(f"  Total atoms after solvation: {modeller.topology.getNumAtoms()}")

    # ---------- 6. System ----------
    banner("Building System")
    system = forcefield.createSystem(
        modeller.topology,
        nonbondedMethod=PME,
        nonbondedCutoff=1.0 * nanometer,
        constraints=HBonds,
    )
    integrator = LangevinMiddleIntegrator(TEMPERATURE_K * kelvin, 1.0 / picosecond, TIMESTEP_FS * femtosecond)
    platform = pick_platform()
    print(f"  Platform: {platform.getName()}")
    sim = Simulation(modeller.topology, system, integrator, platform)
    sim.context.setPositions(modeller.positions)

    # Snapshot the initial topology for the trajectory analysis
    with (run_dir / "system.pdb").open("w") as fh:
        PDBFile.writeFile(modeller.topology, modeller.positions, fh, keepIds=True)

    # ---------- 7. Minimise ----------
    banner("Energy minimisation (max 10000 iter)")
    t = time.time()
    sim.minimizeEnergy(maxIterations=10000)
    e_min = sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    print(f"  PE after min: {e_min:.2f} kJ/mol  ({time.time()-t:.1f}s)")

    # ---------- 8. NVT equilibration with protein-heavy-atom restraints ----------
    ramp_step = 10
    banner(f"NVT equilibration: heating 100→298 K over {EQUIL_NVT_PS} ps (protein heavy atoms restrained)")
    restraint_protein_heavy_atoms(system, modeller.positions, modeller.topology, k=10.0)
    sim.context.reinitialize(preserveState=True)
    sim.context.setVelocitiesToTemperature(100 * kelvin)
    steps_per_ramp = ps_to_steps(EQUIL_NVT_PS) // ((TEMPERATURE_K - 100) // ramp_step)
    for T in range(100, TEMPERATURE_K + 1, ramp_step):
        sim.integrator.setTemperature(T * kelvin)
        sim.step(steps_per_ramp)
    e_nvt = sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    print(f"  PE after NVT: {e_nvt:.2f} kJ/mol")

    # Release restraints
    sim.context.setParameter("k", 0.0)

    # ---------- 9. NPT equilibration ----------
    banner(f"NPT equilibration: {EQUIL_NPT_PS} ps @ 298 K, 1 atm (unrestrained)")
    barostat = MonteCarloBarostat(PRESSURE_ATM * atmosphere, TEMPERATURE_K * kelvin)
    system.addForce(barostat)
    sim.context.reinitialize(preserveState=True)
    sim.step(ps_to_steps(EQUIL_NPT_PS))
    e_npt = sim.context.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    print(f"  PE after NPT: {e_npt:.2f} kJ/mol")

    # ---------- 10. Production ----------
    banner(f"Production: {PRODUCTION_PS} ps @ 298 K, 1 atm")
    dcd_path = run_dir / "production.dcd"
    csv_path = run_dir / "production.csv"
    sim.reporters.append(DCDReporter(str(dcd_path), ps_to_steps(TRAJECTORY_EVERY_PS)))
    sim.reporters.append(
        StateDataReporter(
            str(csv_path),
            ps_to_steps(REPORT_EVERY_PS),
            step=True,
            time=True,
            potentialEnergy=True,
            temperature=True,
            volume=True,
            speed=True,
        )
    )
    t = time.time()
    sim.step(ps_to_steps(PRODUCTION_PS))
    dt_prod = time.time() - t
    ns_per_day = (PRODUCTION_PS / 1000.0) / (dt_prod / 86400)
    print(f"  Production wall-clock: {dt_prod:.1f}s  ({ns_per_day:.2f} ns/day on {platform.getName()})")

    # ---------- 11. RMSD analysis ----------
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

    with (run_dir / "summary.txt").open("w", encoding="utf-8") as fh:
        fh.write(
            f"# L2 stability MD summary — run {run_id}\n\n"
            f"Production length : {PRODUCTION_PS} ps\n"
            f"Platform          : {platform.getName()}\n"
            f"Speed             : {ns_per_day:.2f} ns/day\n"
            f"Atoms             : {modeller.topology.getNumAtoms()}\n"
            f"Genipin copies    : {N_GENIPIN} × {genipin_template.n_atoms} = {N_GENIPIN * genipin_template.n_atoms} atoms\n\n"
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
