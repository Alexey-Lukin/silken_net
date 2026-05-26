#!/usr/bin/env python
"""
L3 step 2 — frontier orbitals of the Os redox mediator (minimal d-orbital model).

Why a minimal [Os(NH₃)₅Cl]ⁿ⁺ instead of the real [Os(bpy)₂(Im)Cl]ⁿ⁺
-----------------------------------------------------------------
The real Os-PVI redox polymer ligation is 2,2'-bipyridine × 2 + imidazole +
Cl⁻. Hand-building a 51-atom cis-cis-octahedral complex around Os without a
crystal seed is brittle — the two chelating bpy rings tend to clash near the
inter-ring C-C' bond unless you DFT-optimise from scratch (many hours).
A Kabsch-aligned MMFF-fragment build was attempted; the two bpy planes
intersect because cis-cis octahedral geometry forces orthogonal-ish bite
planes and the rings extend into each other.

For the L3 cascade question "does electron flow downhill from FAD to Os?"
the dominant variable is **Os formal charge + σ-donation strength of the
coordination sphere**. Amine N (NH₃) is a respectable σ-donor surrogate for
imidazole/bipyridine nitrogens — same hybridisation, same σ-character.

Known limitation: the NH₃ surrogate lacks **π-backbonding** from bpy, which
in the real complex lowers the Os t₂g d-orbital energies by ~1.0-1.5 eV.
The cascade test `ε_HOMO(FADH₂) > ε_LUMO(Os(III))` is therefore in **the
harder direction** with this model — any "downhill" verdict here would
hold a fortiori with the real bpy ligands. An "uphill" verdict, on the
other hand, is inconclusive — it could simply mean the NH₃ surrogate has
pushed the Os(III) LUMO too high. See `L3_quantum_chemistry.md §Caveats`
for the diagnostic discussion.

Publication-grade path: full [Os(bpy)₂(Im)Cl] geometry from a CSD/COD
crystal seed + ωB97X-D/def2-TZVP + ΔSCF + RRHO corrections. Documented as
Future Work in `L3_quantum_chemistry.md`.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/21_dft_os_bipy_complex.py
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
from pyscf import dft, gto, solvent

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    LIGANDS_DIR, DFT_CACHE, HARTREE_TO_EV,
    BASIS_LIGHT, BASIS_OS, ECP_OS, SOLVENT_EPS_WATER,
)
from lib.utils import banner

LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
DFT_CACHE.mkdir(parents=True, exist_ok=True)

OS_N_AMINE = 2.10
OS_CL = 2.35
N_H_AMINE = 1.01

XC_FUNCTIONAL = "b3lyp"


def build_nh3_at_position(n_pos: np.ndarray, os_pos: np.ndarray) -> list[tuple[str, np.ndarray]]:
    """NH₃ with N at `n_pos`; H atoms in a tetrahedral cone pointing away from Os."""
    out_dir = n_pos - os_pos
    out_dir /= np.linalg.norm(out_dir)
    if abs(out_dir[2]) < 0.9:
        local_x = np.array([0.0, 0.0, 1.0])
    else:
        local_x = np.array([1.0, 0.0, 0.0])
    local_x = local_x - local_x.dot(out_dir) * out_dir
    local_x /= np.linalg.norm(local_x)
    local_y = np.cross(out_dir, local_x)

    tilt = np.radians(71.0)
    atoms = [("N", n_pos)]
    for k in range(3):
        phi = 2 * np.pi * k / 3.0
        h_dir = np.cos(tilt) * out_dir + np.sin(tilt) * (np.cos(phi) * local_x + np.sin(phi) * local_y)
        atoms.append(("H", n_pos + N_H_AMINE * h_dir))
    return atoms


def build_os_complex() -> list[tuple[str, np.ndarray]]:
    os_pos = np.zeros(3)
    atoms: list[tuple[str, np.ndarray]] = [("Os", os_pos)]
    for n_pos in (
        np.array([+OS_N_AMINE, 0.0, 0.0]),
        np.array([-OS_N_AMINE, 0.0, 0.0]),
        np.array([0.0, +OS_N_AMINE, 0.0]),
        np.array([0.0, -OS_N_AMINE, 0.0]),
        np.array([0.0, 0.0, +OS_N_AMINE]),
    ):
        atoms += build_nh3_at_position(n_pos, os_pos)
    atoms.append(("Cl", np.array([0.0, 0.0, -OS_CL])))
    return atoms


def write_xyz(atoms, path: Path, comment: str) -> None:
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, pos in atoms:
            fh.write(f"{sym:2s}  {pos[0]: 12.6f}  {pos[1]: 12.6f}  {pos[2]: 12.6f}\n")


def atoms_to_pyscf(atoms):
    return [(s, (float(p[0]), float(p[1]), float(p[2]))) for s, p in atoms]


def dft_singlepoint(atoms_pyscf, charge: int, spin: int, label: str, with_pcm: bool = True) -> dict:
    banner(f"DFT SP: {label} (charge={charge}, spin={spin}, PCM={'yes' if with_pcm else 'no'})")
    basis_spec = {"Os": BASIS_OS, "default": BASIS_LIGHT}
    ecp_spec = {"Os": ECP_OS}
    mol = gto.M(
        atom=atoms_pyscf, basis=basis_spec, ecp=ecp_spec,
        charge=charge, spin=spin, unit="Angstrom",
    )
    mf = dft.RKS(mol) if spin == 0 else dft.UKS(mol)
    mf.xc = XC_FUNCTIONAL
    if with_pcm:
        mf = solvent.PCM(mf)
        mf.with_solvent.eps = SOLVENT_EPS_WATER
        mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 300
    t = time.time()
    energy_total = mf.kernel()
    dt = time.time() - t

    if spin == 0:
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

    print(f"  E_total = {energy_total:.6f} Ha  ({dt:.1f}s, converged={mf.converged})")
    print(f"  HOMO    = {homo:.6f} Ha = {homo * HARTREE_TO_EV:.3f} eV")
    print(f"  LUMO    = {lumo:.6f} Ha = {lumo * HARTREE_TO_EV:.3f} eV")
    print(f"  GAP     = {(lumo - homo) * HARTREE_TO_EV:.3f} eV")
    return {
        "label": label,
        "charge": charge,
        "spin": spin,
        "n_atoms": mol.natm,
        "n_electrons": mol.nelectron,
        "converged": bool(mf.converged),
        "wall_seconds": dt,
        "E_total_Ha": float(energy_total),
        "HOMO_Ha": float(homo),
        "LUMO_Ha": float(lumo),
        "HOMO_eV": float(homo * HARTREE_TO_EV),
        "LUMO_eV": float(lumo * HARTREE_TO_EV),
        "gap_eV": float((lumo - homo) * HARTREE_TO_EV),
    }


def main() -> int:
    banner("Building [Os(NH₃)₅Cl] octahedral geometry (minimal d-orbital model)")
    atoms = build_os_complex()
    write_xyz(atoms, LIGANDS_DIR / "os_amine_cl.xyz", "[Os(NH3)5Cl] minimal d-orbital model")
    print(f"  Atoms: {len(atoms)}  (Os + 5×NH₃ + Cl = 1+15+1)")
    atoms_pyscf = atoms_to_pyscf(atoms)

    results = {
        "method": f"{XC_FUNCTIONAL.upper()}/{BASIS_OS}(Os)+{BASIS_LIGHT}(others)+PCM(water,C-PCM)",
        "model_note": "[Os(NH3)5Cl]^n+ minimal σ-donor surrogate for the real [Os(bpy)2(Im)Cl]^n+; lacks π-backbonding from bpy (Os t2g LUMO ~1-1.5 eV too high vs real complex)",
        "os2_plus":  dft_singlepoint(atoms_pyscf, charge=1, spin=0, label="Os(II) [Os(NH3)5Cl]+"),
        "os3_plus":  dft_singlepoint(atoms_pyscf, charge=2, spin=1, label="Os(III) [Os(NH3)5Cl]2+"),
    }

    de_red = (results["os2_plus"]["E_total_Ha"] - results["os3_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    print(f"\n  ΔE(Os(III) → Os(II)) ≈ {de_red:.3f} eV  (electronic only; no ZPE/thermal)")

    out_path = DFT_CACHE / "os_complex.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    banner(f"✅ Saved {out_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
