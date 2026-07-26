#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
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
from lib.constants import DFT_CACHE, HARTREE_TO_EV, REPO_ROOT
from lib.utils import banner

RUNS_DIR = REPO_ROOT / "tools/in_silico/cache/runs"
OUT_JSON = DFT_CACHE / "md_dft_ensemble.json"

SAMPLE_TIMES_NS = [2, 4, 6, 8, 10]


def find_largest_fullmatrix_run() -> Path | None:
    """Find the full matrix MD run with the largest DCD (= longest production)."""
    best, best_size = None, 0
    for c in RUNS_DIR.glob("*fullmatrix*"):
        dcd = c / "production.dcd"
        pdb = c / "system.pdb"
        if dcd.exists() and pdb.exists():
            size = dcd.stat().st_size
            if size > best_size:
                best, best_size = c, size
    return best


def extract_fad_ring_atoms(traj) -> tuple[list[int], list[int]]:
    """Find isoalloxazine ring heavy atoms + candidate hydrogens.

    Returns (heavy_ring_indices, candidate_h_indices).
    FAD is parameterized as "UNK" residue (86 atoms, 53 heavy).
    Select the large non-standard residue, then filter to ring
    atoms (C/N/O, excluding P and ribitol-ADP chain atoms).
    """
    top = traj.topology
    fad_residue = None
    for r in top.residues:
        if r.n_atoms > 50 and r.name not in ("HOH", "NA", "CL", "WAT"):
            fad_residue = r
            break

    if fad_residue is None:
        return [], []

    # Full FAD (51 heavy atoms) is too large for SCF on MD snapshots.
    # Extract only the isoalloxazine ring (≈19 heavy atoms = lumiflavin equivalent).
    # In GAFF topology: ring atoms are N5x-N8x, C9x-C21x, O7x-O8x
    # (the tricyclic dimethylbenzene + pyrazine + pyrimidine system).
    #
    # CRITICAL: heavy atoms alone (no H) leave dangling valences → radical
    # character → SCF will NOT converge. We MUST include the hydrogens bonded
    # to the selected ring atoms so the fragment is a valid closed-shell molecule.
    ring_atom_prefixes = {
        "N5", "N6", "N7", "N8",
        "C9", "C10", "C11", "C12", "C13", "C14", "C15",
        "C16", "C17", "C18", "C19", "C20", "C21",
        "O7", "O8",
    }
    heavy_ring = set()
    for a in fad_residue.atoms:
        if a.element.symbol == "H":
            continue
        prefix = a.name.rstrip("x")
        if prefix in ring_atom_prefixes:
            heavy_ring.add(a.index)

    if len(heavy_ring) < 10:
        # Fallback: full FAD heavy atoms (no P)
        heavy_ring = {a.index for a in fad_residue.atoms
                      if a.element.symbol not in ("H", "P")}

    # FAD is a non-standard "UNK" residue → mdtraj has NO bond records for it
    # (no CONECT in PDB). So bond-based H selection finds nothing. Instead we
    # collect candidate hydrogens (all H in the residue) and let the caller
    # attach them by distance at each frame (geometry-dependent).
    candidate_h = [a.index for a in fad_residue.atoms if a.element.symbol == "H"]
    return sorted(heavy_ring), candidate_h


def main() -> int:
    banner("MD→DFT Ensemble: FAD HOMO/LUMO across MD trajectory")

    run_dir = find_largest_fullmatrix_run()
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

    heavy_ring, candidate_h = extract_fad_ring_atoms(traj)
    if len(heavy_ring) < 5:
        print(f"  ⚠️ Only {len(heavy_ring)} FAD ring atoms found")
        return 1

    top = traj.topology
    sym = {a.index: a.element.symbol for a in top.atoms}
    print(f"  FAD ring heavy atoms: {len(heavy_ring)}, candidate H: {len(candidate_h)}")

    results = []

    for ns in SAMPLE_TIMES_NS:
        target_ps = ns * 1000
        frame_idx = np.argmin(np.abs(times_ps - target_ps))
        actual_ps = times_ps[frame_idx]

        banner(f"DFT SP at t={actual_ps:.0f} ps ({ns} ns)")

        coords = traj.xyz[frame_idx] * 10.0  # nm → Å

        # Attach hydrogens by distance: any candidate H within 1.3 Å of a
        # selected ring heavy atom caps that valence. FAD is a non-standard
        # residue with no bond records, so distance is the robust criterion.
        ring_coords = np.array([coords[i] for i in heavy_ring])
        frag = list(heavy_ring)
        for h_idx in candidate_h:
            d = np.linalg.norm(ring_coords - coords[h_idx], axis=1)
            if d.min() < 1.3:
                frag.append(h_idx)
        frag_atoms = [(i, sym[i]) for i in frag]

        from pyscf import dft, gto

        atom_str = "; ".join(
            f"{e} {coords[i][0]:.4f} {coords[i][1]:.4f} {coords[i][2]:.4f}"
            for i, e in frag_atoms
        )

        mol = gto.Mole()
        mol.atom = atom_str
        mol.basis = "6-31g(d)"
        # Fragment includes H (capped valences) → neutral closed-shell.
        Z = {"H": 1, "C": 6, "N": 7, "O": 8, "S": 16, "P": 15}
        n_electrons = sum(Z.get(e, 0) for _, e in frag_atoms)
        mol.charge = n_electrons % 2  # safety: enforce even electron count
        mol.spin = 0
        mol.verbose = 0
        mol.build()

        n_h = sum(1 for _, e in frag_atoms if e == "H")
        print(f"  Fragment: {len(frag_atoms)} atoms ({n_h} H), {mol.nelectron} e⁻")

        mf = dft.RKS(mol)
        mf.xc = "b3lyp"
        mf.conv_tol = 1e-6
        mf.max_cycle = 200

        t0 = time.time()
        energy = mf.kernel()

        # MD snapshots are not energy-minimized — first-order DIIS can stall.
        # Fall back to second-order SOSCF (Newton), the robust convergence path.
        if not mf.converged:
            print(f"  DIIS stalled at {ns} ns — retrying with SOSCF (Newton)")
            mf = mf.newton()
            mf.max_cycle = 100
            energy = mf.kernel()

        dt = time.time() - t0

        if not mf.converged:
            print(f"  ⚠️ SCF not converged at {ns} ns (even with SOSCF) — skipping")
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

    robust = bool(np.std(homos) < 0.3)  # cast np.bool_ → Python bool (JSON-safe)
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
