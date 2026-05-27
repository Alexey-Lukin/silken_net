#!/usr/bin/env python
"""
L2 — temperature sweep: full matrix stability at multiple temperatures.

Purpose (per docs/01_03 §4 "Zero Instrumental Noise")
------------------------------------------------------
Verify that the Gen 2.0 matrix (genipin + chitosan + CNC) does not
denature dgrFAD-GDH across the operational temperature range of a tree
(-10°C to +40°C). This replaces the Arrhenius extrapolation in L4 with
first-principles MD data.

Runs the same system as script 11 (full matrix) at 4 temperatures:
  -10°C (263 K) — winter minimum
    5°C (278 K) — early spring / late autumn
   25°C (298 K) — summer baseline (same as script 11)
   40°C (313 K) — extreme heat

Each run: min → NVT → NPT → 100 ps production → RMSD analysis.
Results compared as RMSD(T) curve.

Prerequisites: scripts 02-05 (parameterize FAD, genipin, chitosan, CNC).

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/12_temperature_sweep_md.py

    # Single temperature only:
    SILKEN_SWEEP_TEMPS=278 python tools/in_silico/scripts/12_temperature_sweep_md.py

Expected wall time: ~2.5 hours GPU (4 × ~35 min each at 10 ns/day).
"""
from __future__ import annotations

import json
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
from lib.constants import (
    REPO_ROOT, AF3_PDB, LIGANDS_DIR, CACHE_FILE, RUNS_DIR,
    PH, PRESSURE_ATM, IONIC_STRENGTH, WATER_PADDING_NM, TIMESTEP_FS,
    EQUIL_NVT_PS, EQUIL_NPT_PS,
    N_GENIPIN, N_CHITOSAN, N_CELLOBIOSE, GAFF_VERSION,
)
from lib.geometry import positions_to_nm_array, place_on_sphere, restraint_protein_heavy_atoms
from lib.utils import banner, ps_to_steps, pick_platform

FAD_SDF = LIGANDS_DIR / "FAD.sdf"
GENIPIN_SDF = LIGANDS_DIR / "genipin.sdf"
CHITOSAN_SDF = LIGANDS_DIR / "chitosan_trimer.sdf"
CELLOBIOSE_SDF = LIGANDS_DIR / "cellobiose.sdf"

DEFAULT_TEMPS_K = [263, 278, 298, 313]  # -10, 5, 25, 40 °C
PRODUCTION_PS = int(os.environ.get("SILKEN_PRODUCTION_PS", "100"))
REPORT_EVERY_PS = 1.0
TRAJECTORY_EVERY_PS = 2.0


def run_single_temperature(temp_k: int, platform: Platform) -> dict:
    """Run full matrix MD at a single temperature. Returns RMSD stats."""
    temp_c = temp_k - 273.15
    banner(f"=== Temperature sweep: {temp_c}°C ({temp_k} K) ===")

    run_id = datetime.now().strftime("%Y%m%dT%H%M%S") + f"_T{temp_k}K"
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    # Protein
    fixer = PDBFixer(filename=str(AF3_PDB))
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=PH)
    modeller = Modeller(fixer.topology, fixer.positions)

    # FAD
    fad = Molecule.from_file(str(FAD_SDF))
    fad.name = "FAD"
    modeller.add(fad.to_topology().to_openmm(), fad.conformers[0].to_openmm())

    # Ligands
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

    protein_coords_nm = positions_to_nm_array(modeller.positions)
    protein_center = protein_coords_nm.mean(axis=0)
    shell_radius = (protein_coords_nm - protein_center).max() + 0.8
    rng = np.random.default_rng(42)

    place_on_sphere(modeller, genipin, N_GENIPIN, protein_center, shell_radius, rng, 0)
    place_on_sphere(modeller, chitosan, N_CHITOSAN, protein_center, shell_radius + 0.5, rng, N_GENIPIN)
    place_on_sphere(modeller, cellobiose, N_CELLOBIOSE, protein_center, shell_radius + 0.3, rng, N_GENIPIN + N_CHITOSAN)

    # Force field
    forcefield = ForceField("amber14-all.xml", "amber14/tip3pfb.xml")
    gaff = GAFFTemplateGenerator(
        molecules=[fad, genipin, chitosan, cellobiose],
        forcefield=GAFF_VERSION, cache=str(CACHE_FILE),
    )
    forcefield.registerTemplateGenerator(gaff.generator)

    # Solvate
    modeller.addSolvent(forcefield, padding=WATER_PADDING_NM * nanometer,
                        ionicStrength=IONIC_STRENGTH * molar, positiveIon="Na+", negativeIon="Cl-")

    # System
    system = forcefield.createSystem(modeller.topology, nonbondedMethod=PME,
                                     nonbondedCutoff=1.0 * nanometer, constraints=HBonds)
    integrator = LangevinMiddleIntegrator(temp_k * kelvin, 1.0 / picosecond, TIMESTEP_FS * femtosecond)
    sim = Simulation(modeller.topology, system, integrator, platform)
    sim.context.setPositions(modeller.positions)

    with (run_dir / "system.pdb").open("w") as fh:
        PDBFile.writeFile(modeller.topology, modeller.positions, fh, keepIds=True)

    # Minimise
    min_iters = 20000 if temp_k > 300 else 10000
    sim.minimizeEnergy(maxIterations=min_iters)

    # NVT with restraints — heat to target T
    ramp_step = 10
    restraint = restraint_protein_heavy_atoms(system, modeller.positions, modeller.topology, k=10.0)
    sim.context.reinitialize(preserveState=True)
    sim.context.setVelocitiesToTemperature(100 * kelvin)
    start_t = min(100, temp_k)
    if temp_k <= start_t:
        sim.step(ps_to_steps(EQUIL_NVT_PS))
    else:
        n_ramp = max(1, (temp_k - start_t) // ramp_step)
        steps_per_ramp = ps_to_steps(EQUIL_NVT_PS) // n_ramp
        for t_step in range(start_t, temp_k + 1, ramp_step):
            sim.integrator.setTemperature(t_step * kelvin)
            sim.step(steps_per_ramp)
    sim.context.setParameter("k", 0.0)

    # NPT
    barostat = MonteCarloBarostat(PRESSURE_ATM * atmosphere, temp_k * kelvin)
    system.addForce(barostat)
    sim.context.reinitialize(preserveState=True)
    sim.step(ps_to_steps(EQUIL_NPT_PS))

    # Production
    dcd_path = run_dir / "production.dcd"
    csv_path = run_dir / "production.csv"
    sim.reporters.append(DCDReporter(str(dcd_path), ps_to_steps(TRAJECTORY_EVERY_PS)))
    sim.reporters.append(StateDataReporter(str(csv_path), ps_to_steps(REPORT_EVERY_PS),
                                           step=True, time=True, potentialEnergy=True,
                                           temperature=True, speed=True))
    t0 = time.time()
    sim.step(ps_to_steps(PRODUCTION_PS))
    dt_prod = time.time() - t0
    ns_per_day = (PRODUCTION_PS / 1000.0) / (dt_prod / 86400)

    # RMSD
    import mdtraj as md
    traj = md.load(str(dcd_path), top=str(run_dir / "system.pdb"))
    backbone = traj.topology.select("backbone")
    traj.superpose(traj, frame=0, atom_indices=backbone)
    rmsd_nm = md.rmsd(traj, traj, frame=0, atom_indices=backbone)
    rmsd_A = rmsd_nm * 10.0

    result = {
        "temp_K": temp_k,
        "temp_C": temp_c,
        "rmsd_mean_A": round(float(rmsd_A.mean()), 3),
        "rmsd_std_A": round(float(rmsd_A.std()), 3),
        "rmsd_max_A": round(float(rmsd_A.max()), 3),
        "stable": bool(rmsd_A.max() < 3.0),
        "ns_per_day": round(ns_per_day, 2),
        "run_dir": str(run_dir.relative_to(REPO_ROOT)),
    }

    verdict = "✅ STABLE" if result["stable"] else "⚠️ UNSTABLE"
    print(f"  RMSD: {result['rmsd_mean_A']:.3f} ± {result['rmsd_std_A']:.3f} Å (max {result['rmsd_max_A']:.3f}) → {verdict}")
    print(f"  Speed: {ns_per_day:.2f} ns/day")
    return result


def main() -> int:
    for p in (AF3_PDB, FAD_SDF, GENIPIN_SDF, CHITOSAN_SDF, CELLOBIOSE_SDF, CACHE_FILE):
        if not p.exists():
            sys.exit(f"Missing prerequisite: {p}\nRun scripts 02-05 first.")

    temps_env = os.environ.get("SILKEN_SWEEP_TEMPS")
    if temps_env:
        temps = [int(t) for t in temps_env.split(",")]
    else:
        temps = DEFAULT_TEMPS_K

    banner(f"L2 temperature sweep — {len(temps)} temperatures: {temps}")
    platform = pick_platform()
    print(f"  Platform: {platform.getName()}")

    results = []
    for temp_k in temps:
        result = run_single_temperature(temp_k, platform)
        results.append(result)

    # Summary
    banner("Temperature sweep summary")
    print(f"  {'T(°C)':>6s}  {'RMSD mean':>10s}  {'RMSD max':>9s}  {'Verdict':>10s}")
    print("  " + "-" * 42)
    all_stable = True
    for r in results:
        v = "STABLE" if r["stable"] else "UNSTABLE"
        if not r["stable"]:
            all_stable = False
        print(f"  {r['temp_C']:>5d}°C  {r['rmsd_mean_A']:>9.3f} Å  {r['rmsd_max_A']:>8.3f} Å  {v:>10s}")

    overall = "✅ All temperatures STABLE" if all_stable else "⚠️ Some temperatures UNSTABLE"
    print(f"\n  {overall}")

    # Save
    out_path = REPO_ROOT / "tools/in_silico/cache/kinetics/temperature_sweep.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump({"sweep": results, "verdict": overall}, fh, indent=2)
    print(f"  Wrote {out_path.relative_to(REPO_ROOT)}")

    banner("✅ Temperature sweep complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
