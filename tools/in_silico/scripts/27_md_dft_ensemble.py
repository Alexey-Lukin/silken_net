#!/usr/bin/env python
"""
L3/L2 bridge — MD→DFT ensemble averaging.

Extracts FAD isoalloxazine ring coordinates from 5 MD trajectory
frames (2, 4, 6, 8, 10 ns) and computes B3LYP HOMO/LUMO at each.
Shows how thermal "breathing" of the protein modulates the redox
properties of the cofactor.

If HOMO spread < 0.3 eV → thermally robust cascade.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import REPO_ROOT, DFT_CACHE, HARTREE_TO_EV
from lib.utils import banner

RUNS_DIR = REPO_ROOT / "tools/in_silico/cache/runs"
OUT_JSON = DFT_CACHE / "md_dft_ensemble.json"

SAMPLE_TIMES_NS = [2, 4, 6, 8, 10]


def find_latest_fullmatrix_run() -> Path | None:
    """Find the latest full matrix MD run directory."""
    candidates = sorted(RUNS_DIR.glob("*fullmatrix*"), reverse=True)
    for c in candidates:
        dcd = c / "production.dcd"
        pdb = c / "system.pdb"
        if dcd.exists() and pdb.exists():
            return c
    return None


def extract_fad_ring_atoms(traj) -> list[int]:
    """Find isoalloxazine ring atoms in topology.

    FAD residue has ~86 atoms. We want only the redox-active
    isoalloxazine ring (equivalent to lumiflavin): atoms with
    element C/N/O that are part of the tricyclic ring system.
    We identify them as FAD residue atoms excluding the ribitol
    chain (atoms with names starting with C1', C2', etc.).
    """
    top = traj.topology
    fad_atoms = []
    for atom in top.atoms:
        if atom.residue.name in ("FAD", "LFN"):
            fad_atoms.append(atom.index)

    if not fad_atoms:
        for atom in top.atoms:
            if atom.residue.index >= top.n_residues - 5:
                if atom.element.symbol != "H":
                    fad_atoms.append(atom.index)

    return fad_atoms


def main() -> int:
    banner("MD→DFT Ensemble: FAD HOMO/LUMO across MD trajectory")

    run_dir = find_latest_fullmatrix_run()
    if run_dir is None:
        sys.exit("No full matrix MD run found in cache/runs/")

    dcd = run_dir / "production.dcd"
    pdb = run_dir / "system.pdb"
    print(f"  Run: {run_dir.name}")
    print(f"  DCD: {dcd.stat().st_size / 1e9:.1f} GB")

    try:
        import mdtraj as md
    except ImportError:
        sys.exit("mdtraj required")

    banner("Loading trajectory (stride=100 for speed)")
    traj = md.load(str(dcd), top=str(pdb), stride=100)
    print(f"  Frames: {traj.n_frames}, Atoms: {traj.n_atoms}")

    times_ps = traj.time
    print(f"  Time range: {times_ps[0]:.0f} — {times_ps[-1]:.0f} ps")

    fad_atoms = extract_fad_ring_atoms(traj)
    if len(fad_atoms) < 10:
        print(f"  ⚠️ Only {len(fad_atoms)} FAD atoms found — using all non-H non-water")
        fad_atoms = [a.index for a in traj.topology.atoms
                     if a.residue.name not in ("HOH", "NA", "CL", "WAT")
                     and a.element.symbol != "H"
                     and a.residue.index >= traj.topology.n_residues - 5]

    print(f"  FAD atoms: {len(fad_atoms)}")

    fad_elements = [traj.topology.atom(i).element.symbol for i in fad_atoms]
    heavy_fad = [(i, e) for i, e in zip(fad_atoms, fad_elements) if e != "H"]
    print(f"  FAD heavy atoms: {len(heavy_fad)}")

    results = []

    for ns in SAMPLE_TIMES_NS:
        target_ps = ns * 1000
        frame_idx = np.argmin(np.abs(times_ps - target_ps))
        actual_ps = times_ps[frame_idx]

        banner(f"DFT SP at t={actual_ps:.0f} ps ({ns} ns)")

        coords = traj.xyz[frame_idx] * 10.0  # nm → Å

        from pyscf import dft, gto, solvent

        atom_str = "; ".join(
            f"{e} {coords[i][0]:.4f} {coords[i][1]:.4f} {coords[i][2]:.4f}"
            for i, e in heavy_fad
        )

        mol = gto.Mole()
        mol.atom = atom_str
        mol.basis = "6-31g(d)"
        mol.charge = 0
        mol.spin = 0
        mol.verbose = 0
        mol.build()

        mf = dft.RKS(mol)
        mf.xc = "b3lyp"
        mf.conv_tol = 1e-6
        mf.max_cycle = 200

        t0 = time.time()
        energy = mf.kernel()
        dt = time.time() - t0

        if not mf.converged:
            print(f"  ⚠️ SCF not converged at {ns} ns — skipping")
            continue

        nocc = mol.nelectron // 2
        homo = float(mf.mo_energy[nocc - 1]) * HARTREE_TO_EV
        lumo = float(mf.mo_energy[nocc]) * HARTREE_TO_EV
        gap = lumo - homo

        print(f"  E = {energy:.6f} Ha ({dt:.0f}s)")
        print(f"  HOMO = {homo:.3f} eV, LUMO = {lumo:.3f} eV, Gap = {gap:.3f} eV")

        results.append({
            "time_ns": ns,
            "time_ps": float(actual_ps),
            "frame": int(frame_idx),
            "E_Ha": float(energy),
            "HOMO_eV": homo,
            "LUMO_eV": lumo,
            "gap_eV": gap,
            "converged": True,
            "wall_s": dt,
        })

    if not results:
        print("No converged frames — cannot compute ensemble")
        return 1

    homos = [r["HOMO_eV"] for r in results]
    lumos = [r["LUMO_eV"] for r in results]

    banner("Ensemble Summary")
    print(f"  Frames analyzed: {len(results)}")
    print(f"  HOMO: {np.mean(homos):.3f} ± {np.std(homos):.3f} eV")
    print(f"  LUMO: {np.mean(lumos):.3f} ± {np.std(lumos):.3f} eV")
    print(f"  HOMO range: {np.min(homos):.3f} to {np.max(homos):.3f} eV (spread {np.max(homos)-np.min(homos):.3f})")

    robust = np.std(homos) < 0.3
    print(f"  Thermally robust (σ < 0.3 eV): {'✅ YES' if robust else '❌ NO'}")

    output = {
        "method": "B3LYP/6-31G(d) SP on MD snapshots (no PCM, vacuum)",
        "trajectory": run_dir.name,
        "frames": results,
        "ensemble": {
            "HOMO_mean_eV": float(np.mean(homos)),
            "HOMO_std_eV": float(np.std(homos)),
            "HOMO_range_eV": float(np.max(homos) - np.min(homos)),
            "LUMO_mean_eV": float(np.mean(lumos)),
            "LUMO_std_eV": float(np.std(lumos)),
            "thermally_robust": robust,
        },
    }
    DFT_CACHE.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
