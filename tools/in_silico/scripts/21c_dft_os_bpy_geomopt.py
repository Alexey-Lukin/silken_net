#!/usr/bin/env python
"""
L3 step 2c — DFT geometry optimization of [Os(bpy)₂(1-MeIm)Cl]ⁿ⁺.

Refines the programmatic geometry from script 21b by running a full
DFT geometry optimization via PySCF + geomeTRIC. Expected improvements:
  - Os-N distances tighten from 2.10 → ~2.06 Å
  - π-backbonding strengthens → LUMO(Os(III)) drops ~0.1-0.3 eV
  - Raw Koopmans Δε moves closer to (or past) zero → stronger verdict

Uses B3LYP/6-31G(d) + LANL2DZ(Os) + C-PCM water — same level of theory
as script 21b, but with optimized geometry. Publication-grade upgrade
(ωB97X-D/def2-TZVP) is a separate future step.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/21c_dft_os_bpy_geomopt.py

Expected wall time: ~6-12 hours CPU (geometry opt ~30-100 SCF cycles × ~8 min each).
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
from pyscf import dft, gto, solvent
from pyscf.geomopt import geometric_solver

REPO_ROOT = Path(__file__).resolve().parents[3]
LIGANDS_DIR = REPO_ROOT / "docs/protocols/ebfc/in_silico/ligands"
DFT_CACHE = REPO_ROOT / "tools/in_silico/cache/dft"
LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
DFT_CACHE.mkdir(parents=True, exist_ok=True)

INPUT_XYZ = LIGANDS_DIR / "os_bpy_im_cl.xyz"
OUTPUT_XYZ = LIGANDS_DIR / "os_bpy_im_cl_opt.xyz"
OUTPUT_JSON = DFT_CACHE / "os_complex_geomopt.json"

XC_FUNCTIONAL = "b3lyp"
BASIS_LIGHT = "6-31g(d)"
BASIS_OS = "lanl2dz"
ECP_OS = "lanl2dz"
SOLVENT_EPS = 78.3553
HARTREE_TO_EV = 27.211386245988
BOHR_TO_ANG = 0.529177249


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def read_xyz(path: Path) -> list[tuple[str, tuple[float, float, float]]]:
    lines = path.read_text().strip().split("\n")
    n_atoms = int(lines[0])
    atoms = []
    for line in lines[2 : 2 + n_atoms]:
        parts = line.split()
        atoms.append((parts[0], (float(parts[1]), float(parts[2]), float(parts[3]))))
    return atoms


def write_xyz(atoms, path: Path, comment: str) -> None:
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, (x, y, z) in atoms:
            fh.write(f"{sym:2s}  {x: 12.6f}  {y: 12.6f}  {z: 12.6f}\n")


def build_mol(atoms, charge: int, spin: int):
    basis_spec = {"Os": BASIS_OS, "default": BASIS_LIGHT}
    ecp_spec = {"Os": ECP_OS}
    return gto.M(
        atom=atoms, basis=basis_spec, ecp=ecp_spec,
        charge=charge, spin=spin, unit="Angstrom",
    )


def build_mf(mol, with_pcm: bool = True):
    mf = dft.RKS(mol) if mol.spin == 0 else dft.UKS(mol)
    mf.xc = XC_FUNCTIONAL
    if with_pcm:
        mf = solvent.PCM(mf)
        mf.with_solvent.eps = SOLVENT_EPS
        mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 400
    return mf


def extract_frontier(mf, mol):
    if mol.spin == 0:
        nocc = mol.nelectron // 2
        homo = mf.mo_energy[nocc - 1]
        lumo = mf.mo_energy[nocc]
    else:
        nocc_a, nocc_b = mol.nelec
        ho_a = mf.mo_energy[0][nocc_a - 1]
        ho_b = mf.mo_energy[1][nocc_b - 1]
        homo = max(ho_a, ho_b)
        lu_a = mf.mo_energy[0][nocc_a]
        lu_b = mf.mo_energy[1][nocc_b]
        lumo = min(lu_a, lu_b)
    return float(homo), float(lumo)


def os_n_distances(atoms):
    os_pos = None
    n_positions = []
    for sym, pos in atoms:
        if sym == "Os":
            os_pos = np.array(pos)
        elif sym == "N":
            n_positions.append(np.array(pos))
    if os_pos is None:
        return []
    return [float(np.linalg.norm(n - os_pos)) for n in n_positions]


def main() -> int:
    if not INPUT_XYZ.exists():
        sys.exit(f"Missing {INPUT_XYZ}. Run script 21b first.")

    atoms = read_xyz(INPUT_XYZ)
    banner(f"Loaded {len(atoms)} atoms from {INPUT_XYZ.name}")

    os_n_before = os_n_distances(atoms)
    print(f"  Os-N distances (before opt): {[f'{d:.3f}' for d in sorted(os_n_before)[:6]]}")

    # ── 1. Geometry optimization on Os(II) singlet (cheaper, faster convergence) ──
    banner("Geometry optimization: Os(II) [Os(bpy)₂(1-MeIm)Cl]⁺ (RKS, charge=+1, spin=0)")
    mol = build_mol(atoms, charge=1, spin=0)
    mf = build_mf(mol, with_pcm=False)

    t0 = time.time()
    mol_opt = geometric_solver.optimize(mf)
    dt_opt = time.time() - t0
    banner(f"Geometry optimization converged in {dt_opt:.0f}s ({dt_opt/60:.1f} min)")

    opt_coords = mol_opt.atom_coords(unit="Ang")
    opt_atoms = [(mol_opt.atom_symbol(i), tuple(opt_coords[i])) for i in range(mol_opt.natm)]

    os_n_after = os_n_distances(opt_atoms)
    print(f"  Os-N distances (after opt):  {[f'{d:.3f}' for d in sorted(os_n_after)[:6]]}")
    if any(d < 1.5 or d > 3.0 for d in os_n_after[:6]):
        print(f"  ⚠️  WARNING: Unusual Os-N distances — geometry may be a local minimum")

    write_xyz(opt_atoms, OUTPUT_XYZ, "cis-[Os(bpy)2(1-MeIm)Cl] — B3LYP/6-31G(d)+LANL2DZ geom opt")
    print(f"  Wrote {OUTPUT_XYZ.relative_to(REPO_ROOT)}")

    # ── 2. Single-point at optimized geometry: Os(II) with PCM ──
    banner("SP at optimized geometry: Os(II) + PCM")
    mol_os2 = build_mol(opt_atoms, charge=1, spin=0)
    mf_os2 = build_mf(mol_os2, with_pcm=True)
    t0 = time.time()
    e_os2 = mf_os2.kernel()
    dt_os2 = time.time() - t0
    homo_os2, lumo_os2 = extract_frontier(mf_os2, mol_os2)
    print(f"  E = {e_os2:.6f} Ha ({dt_os2:.0f}s, converged={mf_os2.converged})")
    print(f"  HOMO = {homo_os2 * HARTREE_TO_EV:.3f} eV, LUMO = {lumo_os2 * HARTREE_TO_EV:.3f} eV")

    # ── 3. Single-point at optimized geometry: Os(III) with PCM ──
    banner("SP at optimized geometry: Os(III) + PCM (doublet)")
    mol_os3 = build_mol(opt_atoms, charge=2, spin=1)
    mf_os3 = build_mf(mol_os3, with_pcm=True)
    t0 = time.time()
    e_os3 = mf_os3.kernel()
    dt_os3 = time.time() - t0
    homo_os3, lumo_os3 = extract_frontier(mf_os3, mol_os3)
    print(f"  E = {e_os3:.6f} Ha ({dt_os3:.0f}s, converged={mf_os3.converged})")
    print(f"  HOMO = {homo_os3 * HARTREE_TO_EV:.3f} eV, LUMO = {lumo_os3 * HARTREE_TO_EV:.3f} eV")

    # ── 4. Cascade check ──
    banner("Cascade check vs FADH₂")
    fad_path = DFT_CACHE / "lumiflavin.json"
    if fad_path.exists():
        fad = json.loads(fad_path.read_text(encoding="utf-8"))
        fadh2_homo = fad["red"]["HOMO_eV"]
        os3_lumo_ev = lumo_os3 * HARTREE_TO_EV
        delta = fadh2_homo - os3_lumo_ev
        direction = "✅ DOWNHILL" if delta > 0 else "❌ UPHILL"
        print(f"  HOMO(FADH₂) = {fadh2_homo:.3f} eV")
        print(f"  LUMO(Os(III)) = {os3_lumo_ev:.3f} eV")
        print(f"  Δε = {delta:+.3f} eV → {direction}")

    # ── 5. Save results ──
    results = {
        "method": f"{XC_FUNCTIONAL.upper()}/{BASIS_OS}(Os)+{BASIS_LIGHT}(others)+PCM(water,C-PCM)",
        "model_note": "Full cis-[Os(bpy)2(1-MeIm)Cl] with DFT geometry optimization (B3LYP, no PCM) + SP with PCM.",
        "geometry_opt_seconds": dt_opt,
        "os_n_distances_before": sorted(os_n_before)[:6],
        "os_n_distances_after": sorted(os_n_after)[:6],
        "os2_plus": {
            "label": "Os(II) [Os(bpy)2(1-MeIm)Cl]+ (geom opt)",
            "charge": 1, "spin": 0,
            "n_atoms": mol_os2.natm, "n_electrons": mol_os2.nelectron,
            "converged": bool(mf_os2.converged), "wall_seconds": dt_os2,
            "E_total_Ha": float(e_os2),
            "HOMO_Ha": homo_os2, "LUMO_Ha": lumo_os2,
            "HOMO_eV": homo_os2 * HARTREE_TO_EV, "LUMO_eV": lumo_os2 * HARTREE_TO_EV,
            "gap_eV": (lumo_os2 - homo_os2) * HARTREE_TO_EV,
        },
        "os3_plus": {
            "label": "Os(III) [Os(bpy)2(1-MeIm)Cl]2+ (geom opt)",
            "charge": 2, "spin": 1,
            "n_atoms": mol_os3.natm, "n_electrons": mol_os3.nelectron,
            "converged": bool(mf_os3.converged), "wall_seconds": dt_os3,
            "E_total_Ha": float(e_os3),
            "HOMO_Ha": homo_os3, "LUMO_Ha": lumo_os3,
            "HOMO_eV": homo_os3 * HARTREE_TO_EV, "LUMO_eV": lumo_os3 * HARTREE_TO_EV,
            "gap_eV": (lumo_os3 - homo_os3) * HARTREE_TO_EV,
        },
    }

    with OUTPUT_JSON.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    banner(f"✅ Saved {OUTPUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
