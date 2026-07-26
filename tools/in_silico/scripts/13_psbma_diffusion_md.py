#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L2 — glucose diffusion through PSBMA membrane layer.

Purpose (per docs/01_03 §2.1 Layer 5 + §3.4 L4)
-------------------------------------------------
Compute the effective diffusion coefficient D_eff of glucose through a
simplified Nafion-g-PSBMA anti-biofouling layer from first-principles MD,
replacing the literature estimate D=2×10⁻⁶ cm²/s used in L4 kinetics.

The PSBMA membrane is modeled as a slab of SBMA monomers (zwitterionic
units) packed in water. Glucose molecules are placed on one side and their
mean square displacement (MSD) is tracked over the production run.

Model simplifications
---------------------
  - SBMA monomers (not polymerized chains) — captures the zwitterionic
    hydration shell effect without requiring polymer topology.
  - Flat slab geometry (not cylindrical pore) — adequate for D_eff estimation.
  - No Nafion backbone — SBMA hydration is the dominant transport barrier.

Physical setup
--------------
  1. Build a water box with a central slab of N_SBMA monomers (~20 µm thick
     after equilibration, scaled to nm for MD).
  2. Place N_GLUCOSE glucose molecules on one side of the slab.
  3. Equilibrate (NVT → NPT).
  4. Production: track glucose center-of-mass positions.
  5. Compute MSD(t) → D = MSD / (6·t) in the diffusion regime.

Prerequisites: script 08 (parameterize SBMA), script 02 (FAD → glucose proxy).

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/13_psbma_diffusion_md.py

Expected wall time: ~1-2 hours GPU (smaller system than protein MD).
"""
from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import matplotlib
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
    molar,
    nanometer,
    picosecond,
)
from openmmforcefields.generators import GAFFTemplateGenerator

matplotlib.use("Agg")
import matplotlib.pyplot as plt

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    CACHE_FILE,
    GAFF_VERSION,
    KINETICS_DIR,
    LIGANDS_DIR,
    PRESSURE_ATM,
    REPO_ROOT,
    RUNS_DIR,
    TIMESTEP_FS,
    WATER_MODEL_LABEL,
    WATER_MODEL_XML,
)
from lib.geometry import positions_to_nm_array
from lib.utils import banner, pick_platform, ps_to_steps

SBMA_SDF = LIGANDS_DIR / "sbma_monomer.sdf"
OUT_DIR = KINETICS_DIR

GLUCOSE_SMILES = "OC[C@H]1OC(O)[C@H](O)[C@@H](O)[C@@H]1O"

N_SBMA = 30
N_GLUCOSE = 5
SLAB_THICKNESS_NM = 3.0
TEMPERATURE_K = 298
EQUIL_NVT_PS = 20
EQUIL_NPT_PS = 50
PRODUCTION_PS = int(os.environ.get("SILKEN_PRODUCTION_PS", "200"))
REPORT_EVERY_PS = 0.5
TRAJECTORY_EVERY_PS = 1.0


def build_glucose() -> Molecule:
    """Build a glucose molecule for diffusion tracking."""
    mol = Molecule.from_smiles(GLUCOSE_SMILES, allow_undefined_stereo=True)
    mol.name = "GLC"
    mol.generate_conformers(n_conformers=1)
    return mol


def main() -> int:
    if not SBMA_SDF.exists():
        sys.exit(f"Missing {SBMA_SDF}. Run script 08 first.")
    if not CACHE_FILE.exists():
        sys.exit(f"Missing {CACHE_FILE}. Run scripts 02-08 first.")

    run_id = datetime.now().strftime("%Y%m%dT%H%M%S") + "_psbma_diffusion"
    run_dir = RUNS_DIR / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    banner(f"L2 PSBMA diffusion MD — run {run_id}")
    print(f"  SBMA monomers: {N_SBMA}, glucose probes: {N_GLUCOSE}")
    print(f"  Production: {PRODUCTION_PS} ps")

    # ── 1. Load SBMA template ──
    banner("Loading SBMA monomer from SDF")
    sbma = Molecule.from_file(str(SBMA_SDF))
    sbma.name = "SBM"
    if not sbma.conformers:
        sbma.generate_conformers(n_conformers=1)
    print(f"  SBMA: {sbma.n_atoms} atoms")

    # ── 2. Build glucose ──
    banner("Building glucose probe molecules")
    glucose = build_glucose()
    print(f"  Glucose: {glucose.n_atoms} atoms")

    # ── 3. Assemble system: SBMA slab + glucose on one side ──
    banner(f"Assembling membrane slab ({N_SBMA} SBMA + {N_GLUCOSE} glucose)")

    # Start with first SBMA as seed topology
    sbma_top = sbma.to_topology().to_openmm()
    sbma_coords = positions_to_nm_array(sbma.conformers[0].to_openmm())
    sbma_coords -= sbma_coords.mean(axis=0)

    modeller = Modeller(sbma_top, [Vec3(*c) for c in sbma_coords] * nanometer)

    rng = np.random.default_rng(42)

    # Place remaining SBMA monomers in a slab centered at z=0
    for _i in range(1, N_SBMA):
        x = rng.uniform(-2.0, 2.0)
        y = rng.uniform(-2.0, 2.0)
        z = rng.uniform(-SLAB_THICKNESS_NM / 2, SLAB_THICKNESS_NM / 2)
        offset = np.array([x, y, z])
        shifted = sbma_coords + offset
        modeller.add(sbma_top, [Vec3(*c) for c in shifted] * nanometer)

    # Place glucose probes above the slab (z > slab top + 0.5 nm)
    glc_top = glucose.to_topology().to_openmm()
    glc_coords = positions_to_nm_array(glucose.conformers[0].to_openmm())
    glc_coords -= glc_coords.mean(axis=0)

    glucose_start_indices = []
    n_atoms_before_glucose = modeller.topology.getNumAtoms()

    for i in range(N_GLUCOSE):
        x = rng.uniform(-1.5, 1.5)
        y = rng.uniform(-1.5, 1.5)
        z = SLAB_THICKNESS_NM / 2 + 1.0 + i * 0.5  # above slab
        offset = np.array([x, y, z])
        shifted = glc_coords + offset
        glucose_start_indices.append(modeller.topology.getNumAtoms())
        modeller.add(glc_top, [Vec3(*c) for c in shifted] * nanometer)

    print(f"  System before solvation: {modeller.topology.getNumAtoms()} atoms")
    print(f"  Glucose atom indices start: {glucose_start_indices}")

    # ── 4. Force field ──
    banner(f"Building ForceField (AMBER {WATER_MODEL_LABEL} + GAFF for SBMA/glucose)")
    forcefield = ForceField(WATER_MODEL_XML)
    gaff = GAFFTemplateGenerator(
        molecules=[sbma, glucose],
        forcefield=GAFF_VERSION,
        cache=str(CACHE_FILE),
    )
    forcefield.registerTemplateGenerator(gaff.generator)

    # ── 5. Solvate ──
    banner("Solvating")
    modeller.addSolvent(
        forcefield,
        padding=1.5 * nanometer,
        ionicStrength=0.05 * molar,
        positiveIon="Na+",
        negativeIon="Cl-",
    )
    total_atoms = modeller.topology.getNumAtoms()
    print(f"  Total atoms: {total_atoms}")

    # ── 6. System ──
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

    # ── 7. Minimise ──
    banner("Energy minimisation")
    sim.minimizeEnergy(maxIterations=10000)

    # Brief low-T relaxation
    sim.context.setVelocitiesToTemperature(10 * kelvin)
    sim.step(1000)

    # ── 8. NVT ──
    banner(f"NVT equilibration: {EQUIL_NVT_PS} ps @ {TEMPERATURE_K} K")
    sim.context.setVelocitiesToTemperature(TEMPERATURE_K * kelvin)
    sim.step(ps_to_steps(EQUIL_NVT_PS))

    # ── 9. NPT ──
    banner(f"NPT equilibration: {EQUIL_NPT_PS} ps")
    barostat = MonteCarloBarostat(PRESSURE_ATM * atmosphere, TEMPERATURE_K * kelvin)
    system.addForce(barostat)
    sim.context.reinitialize(preserveState=True)
    sim.step(ps_to_steps(EQUIL_NPT_PS))

    # ── 10. Production with position tracking ──
    banner(f"Production: {PRODUCTION_PS} ps — tracking glucose MSD")
    dcd_path = run_dir / "production.dcd"
    sim.reporters.append(DCDReporter(str(dcd_path), ps_to_steps(TRAJECTORY_EVERY_PS)))
    sim.reporters.append(
        StateDataReporter(
            str(run_dir / "production.csv"), ps_to_steps(REPORT_EVERY_PS),
            step=True, time=True, potentialEnergy=True, temperature=True, speed=True,
        )
    )

    t0 = time.time()
    sim.step(ps_to_steps(PRODUCTION_PS))
    dt_prod = time.time() - t0
    print(f"  Wall-clock: {dt_prod:.1f}s")

    # ── 11. MSD analysis ──
    banner("Computing glucose MSD → D_eff")
    import mdtraj as md

    traj = md.load(str(dcd_path), top=str(run_dir / "system.pdb"))

    # Find glucose residues by name
    glc_residues = [r for r in traj.topology.residues if r.name == "GLC"]
    if not glc_residues:
        print("  ⚠️ No glucose residues found — using atom indices")
        glc_atom_indices = list(range(n_atoms_before_glucose,
                                      n_atoms_before_glucose + N_GLUCOSE * glucose.n_atoms))
    else:
        glc_atom_indices = []
        for r in glc_residues:
            glc_atom_indices.extend([a.index for a in r.atoms])

    expected_glc_atoms = N_GLUCOSE * glucose.n_atoms
    assert len(glc_atom_indices) == expected_glc_atoms, \
        f"Glucose atom count mismatch: expected {expected_glc_atoms}, got {len(glc_atom_indices)}"

    # Compute center-of-mass for each glucose at each frame
    n_frames = traj.n_frames
    n_atoms_per_glc = glucose.n_atoms
    n_glc = len(glc_atom_indices) // n_atoms_per_glc

    com_positions = np.zeros((n_frames, n_glc, 3))
    for g in range(n_glc):
        atom_slice = glc_atom_indices[g * n_atoms_per_glc: (g + 1) * n_atoms_per_glc]
        com_positions[:, g, :] = traj.xyz[:, atom_slice, :].mean(axis=1)

    # MSD: average over all glucose probes and time origins
    dt_ps = TRAJECTORY_EVERY_PS
    max_lag = n_frames // 2
    msd = np.zeros(max_lag)
    for lag in range(1, max_lag):
        displacements = com_positions[lag:] - com_positions[:-lag]
        sq_disp = np.sum(displacements**2, axis=2)  # (n_windows, n_glc)
        msd[lag] = sq_disp.mean()

    time_ps = np.arange(max_lag) * dt_ps
    time_ns = time_ps / 1000.0

    # Fit D from linear regime (skip first 10% for ballistic regime)
    fit_start = max(1, max_lag // 10)
    fit_end = max_lag
    if fit_end > fit_start + 5:
        coeffs = np.polyfit(time_ns[fit_start:fit_end], msd[fit_start:fit_end], 1)
        slope_nm2_per_ns = coeffs[0]
        d_nm2_per_ns = slope_nm2_per_ns / 6.0  # 3D diffusion: MSD = 6Dt
        d_cm2_per_s = d_nm2_per_ns * 1e-14 / 1e-9  # nm²/ns → cm²/s
    else:
        d_cm2_per_s = 0.0
        slope_nm2_per_ns = 0.0

    print(f"  Glucose probes tracked: {n_glc}")
    print(f"  MSD slope: {slope_nm2_per_ns:.4f} nm²/ns")
    print(f"  D_eff = {d_cm2_per_s:.2e} cm²/s")
    print("  Literature D (chitosan hydrogel): ~2e-6 cm²/s")
    print("  Literature D (pure water): ~6.7e-6 cm²/s")

    # Compare with L4 assumption
    d_ratio = d_cm2_per_s / 2e-6 if d_cm2_per_s > 0 else 0
    print(f"  Ratio vs L4 assumption: {d_ratio:.2f}×")

    # ── 12. Save ──
    results = {
        "model": "SBMA slab + glucose MSD",
        "N_SBMA": N_SBMA,
        "N_glucose": n_glc,
        "production_ps": PRODUCTION_PS,
        "D_eff_cm2_s": d_cm2_per_s,
        "MSD_slope_nm2_ns": slope_nm2_per_ns,
        "D_literature_cm2_s": 2e-6,
        "D_water_cm2_s": 6.7e-6,
        "ratio_vs_L4_assumption": round(d_ratio, 2),
    }

    json_path = OUT_DIR / "psbma_diffusion.json"
    with json_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    print(f"\n  Wrote {json_path.relative_to(REPO_ROOT)}")

    # MSD plot
    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(time_ns[:max_lag], msd[:max_lag], "b-", linewidth=1.5, label="MSD (glucose)")
    if fit_end > fit_start + 5:
        fit_line = np.polyval(coeffs, time_ns[fit_start:fit_end])
        ax.plot(time_ns[fit_start:fit_end], fit_line, "r--", linewidth=2,
                label=f"Linear fit: D={d_cm2_per_s:.2e} cm²/s")
    ax.set_xlabel("Time (ns)")
    ax.set_ylabel("MSD (nm²)")
    ax.set_title(f"Glucose diffusion through SBMA slab ({N_SBMA} monomers)")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig_path = OUT_DIR / "psbma_diffusion_msd.png"
    fig.savefig(fig_path, dpi=140)
    print(f"  Wrote {fig_path.relative_to(REPO_ROOT)}")

    banner("✅ PSBMA diffusion MD complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
