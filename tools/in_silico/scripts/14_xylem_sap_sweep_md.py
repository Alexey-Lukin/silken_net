#!/usr/bin/env python
"""
L2 — xylem sap composition sweep: test enzyme stability across tree species.

Purpose
-------
The current L2 MD uses simplified xylem sap (TIP3P + NaCl 0.05M, pH 4.5).
Real xylem sap varies significantly between tree species:
  - Pinus sylvestris (pine): pH 5.0, IS 0.015M, low glucose
  - Picea abies (spruce): pH 4.2, IS 0.012M — most acidic
  - Quercus robur (oak): pH 5.5, IS 0.020M — more neutral
  - Fagus sylvatica (beech): pH 6.0, IS 0.018M — most neutral

This script runs the same full-matrix MD (protein + FAD + genipin +
chitosan + CNC) with different ionic strengths to simulate different
tree species. pH is adjusted via pdbfixer protonation states.

Results show whether the RMSD stability verdict holds across all species
or if certain xylem compositions destabilize the enzyme.

Prerequisites: scripts 02-05 (parameterize FAD, genipin, chitosan, CNC).

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/14_xylem_sap_sweep_md.py

    # Single species:
    SILKEN_SAP_SPECIES=picea_abies python tools/in_silico/scripts/14_xylem_sap_sweep_md.py
"""
from __future__ import annotations

import json
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
    KINETICS_DIR,
    LIGANDS_DIR,
    N_CELLOBIOSE,
    N_CHITOSAN,
    N_GENIPIN,
    PRESSURE_ATM,
    REPO_ROOT,
    RUNS_DIR,
    TIMESTEP_FS,
    WATER_PADDING_NM,
)
from lib.geometry import place_on_sphere, positions_to_nm_array, restraint_protein_heavy_atoms
from lib.utils import banner, pick_platform, ps_to_steps
from lib.xylem_sap import get_sap_profile

FAD_SDF = LIGANDS_DIR / "FAD.sdf"
GENIPIN_SDF = LIGANDS_DIR / "genipin.sdf"
CHITOSAN_SDF = LIGANDS_DIR / "chitosan_trimer.sdf"
CELLOBIOSE_SDF = LIGANDS_DIR / "cellobiose.sdf"
OUT_DIR = KINETICS_DIR

DEFAULT_SPECIES = [
    "pinus_sylvestris",
    "pinus_sylvestris_winter",
    "picea_abies",
    "quercus_robur",
    "fagus_sylvatica",
    "generic_simplified",
]

TEMPERATURE_K = 298
PRODUCTION_PS = int(os.environ.get("SILKEN_PRODUCTION_PS", "100"))
REPORT_EVERY_PS = 1.0
TRAJECTORY_EVERY_PS = 2.0


def run_single_sap(species: str, platform) -> dict:
    """Run full matrix MD with xylem sap composition for given species."""
    profile = get_sap_profile(species)
    ph = profile["ph"]
    ionic_strength = profile["ionic_strength_M"]

    banner(f"=== Xylem sap sweep: {species} ({profile['common_name']}) ===")
    print(f"  pH={ph}, IS={ionic_strength}M, glucose={profile['glucose_mM']}mM")

    run_id = datetime.now().strftime("%Y%m%dT%H%M%S") + f"_sap_{species}"
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    # Protein at species-specific pH
    fixer = PDBFixer(filename=str(AF3_PDB))
    fixer.removeHeterogens(keepWater=False)
    fixer.findMissingResidues()
    fixer.findMissingAtoms()
    fixer.addMissingAtoms()
    fixer.addMissingHydrogens(pH=ph)
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

    # Force field with species-specific ionic strength
    forcefield = ForceField("amber14-all.xml", "amber14/tip3pfb.xml")
    gaff = GAFFTemplateGenerator(
        molecules=[fad, genipin, chitosan, cellobiose],
        forcefield=GAFF_VERSION, cache=str(CACHE_FILE),
    )
    forcefield.registerTemplateGenerator(gaff.generator)

    modeller.addSolvent(forcefield, padding=WATER_PADDING_NM * nanometer,
                        ionicStrength=ionic_strength * molar,
                        positiveIon="Na+", negativeIon="Cl-")
    total_atoms = modeller.topology.getNumAtoms()

    system = forcefield.createSystem(modeller.topology, nonbondedMethod=PME,
                                     nonbondedCutoff=1.0 * nanometer, constraints=HBonds)
    integrator = LangevinMiddleIntegrator(TEMPERATURE_K * kelvin, 1.0 / picosecond, TIMESTEP_FS * femtosecond)
    sim = Simulation(modeller.topology, system, integrator, platform)
    sim.context.setPositions(modeller.positions)

    with (run_dir / "system.pdb").open("w") as fh:
        PDBFile.writeFile(modeller.topology, modeller.positions, fh, keepIds=True)

    # Minimise
    sim.minimizeEnergy(maxIterations=10000)

    # Brief low-T relaxation to resolve residual clashes
    sim.context.setVelocitiesToTemperature(10 * kelvin)
    sim.step(1000)

    # NVT
    ramp_step = 10
    restraint_protein_heavy_atoms(system, modeller.positions, modeller.topology, k=10.0)
    sim.context.reinitialize(preserveState=True)
    sim.context.setVelocitiesToTemperature(50 * kelvin)
    steps_per_ramp = ps_to_steps(EQUIL_NVT_PS) // ((TEMPERATURE_K - 50) // ramp_step)
    for T in range(50, TEMPERATURE_K + 1, ramp_step):
        sim.integrator.setTemperature(T * kelvin)
        sim.step(steps_per_ramp)
    sim.context.setParameter("k", 0.0)

    # NPT
    barostat = MonteCarloBarostat(PRESSURE_ATM * atmosphere, TEMPERATURE_K * kelvin)
    system.addForce(barostat)
    sim.context.reinitialize(preserveState=True)
    sim.step(ps_to_steps(EQUIL_NPT_PS))

    # Production
    dcd_path = run_dir / "production.dcd"
    sim.reporters.append(DCDReporter(str(dcd_path), ps_to_steps(TRAJECTORY_EVERY_PS)))
    sim.reporters.append(StateDataReporter(str(run_dir / "production.csv"),
                                           ps_to_steps(REPORT_EVERY_PS),
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
        "species": species,
        "common_name": profile["common_name"],
        "ph": ph,
        "ionic_strength_M": ionic_strength,
        "glucose_mM": profile["glucose_mM"],
        "total_atoms": total_atoms,
        "rmsd_mean_A": round(float(rmsd_A.mean()), 3),
        "rmsd_std_A": round(float(rmsd_A.std()), 3),
        "rmsd_max_A": round(float(rmsd_A.max()), 3),
        "stable": bool(rmsd_A.max() < 3.0),
        "ns_per_day": round(ns_per_day, 2),
    }

    verdict = "✅ STABLE" if result["stable"] else "⚠️ UNSTABLE"
    print(f"  RMSD: {result['rmsd_mean_A']:.3f} ± {result['rmsd_std_A']:.3f} Å (max {result['rmsd_max_A']:.3f}) → {verdict}")
    return result


def main() -> int:
    for p in (AF3_PDB, FAD_SDF, GENIPIN_SDF, CHITOSAN_SDF, CELLOBIOSE_SDF, CACHE_FILE):
        if not p.exists():
            sys.exit(f"Missing: {p}. Run scripts 02-05 first.")

    species_env = os.environ.get("SILKEN_SAP_SPECIES")
    species_list = [s.strip() for s in species_env.split(",")] if species_env else DEFAULT_SPECIES

    banner(f"L2 xylem sap sweep — {len(species_list)} species")
    platform = pick_platform()
    print(f"  Platform: {platform.getName()}")

    results = []
    for species in species_list:
        result = run_single_sap(species, platform)
        results.append(result)

    # Summary
    banner("Xylem sap sweep summary")
    print(f"  {'Species':<25s} {'pH':>4s} {'IS(M)':>6s} {'RMSD mean':>10s} {'RMSD max':>9s} {'Verdict':>10s}")
    print("  " + "-" * 68)
    all_stable = True
    for r in results:
        v = "STABLE" if r["stable"] else "UNSTABLE"
        if not r["stable"]:
            all_stable = False
        print(f"  {r['species']:<25s} {r['ph']:>4.1f} {r['ionic_strength_M']:>6.3f} {r['rmsd_mean_A']:>9.3f} Å {r['rmsd_max_A']:>8.3f} Å {v:>10s}")

    overall = "✅ Enzyme stable across ALL species" if all_stable else "⚠️ Some species cause instability"
    print(f"\n  {overall}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / "xylem_sap_sweep.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump({"sweep": results, "verdict": overall}, fh, indent=2)
    print(f"  Wrote {out_path.relative_to(REPO_ROOT)}")

    banner("✅ Xylem sap sweep complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
