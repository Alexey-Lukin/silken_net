#!/usr/bin/env python
"""
L3 step 2b — frontier orbitals of the FULL Os redox mediator.

Model: cis-[Os(bpy)₂(1-MeIm)Cl]ⁿ⁺ (~54 atoms)

Supersedes the NH₃ surrogate (script 21) by including π-backbonding from
bipyridine ligands — the dominant missing effect (~1.0-1.5 eV systematic
shift on Os d-orbitals that caused the NH₃ model to give UPHILL verdict).

Geometry construction
---------------------
Octahedral cis-[Os(bpy)₂(1-MeIm)Cl]⁺ assembled programmatically:
  - Two s-cis bpy chelates in orthogonal planes (xz and yz)
  - 1-methylimidazole along +y (trans to bpy2 N)
  - Cl along +x (trans to bpy1 N)
  - Os-N(bpy) = 2.06 Å, N-Os-N bite ≈ 78°
  - Os-N(Im) = 2.10 Å, Os-Cl = 2.38 Å

Known remaining bias after this fix: B3LYP underestimates FADH₂ HOMO by
~0.6 eV (Bhattacharyya & Truhlar 2007). Definitive publication-grade
verdict requires ωB97X-D/def2-TZVP or ΔSCF (→ Future Work).

Outputs
-------
  * docs/protocols/ebfc/in_silico/ligands/os_bpy_im_cl.xyz  — assembled geom
  * tools/in_silico/cache/dft/os_complex.json                — DFT energies

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/21b_dft_os_bpy_full.py

Expected wall time: ~10-30 min (two DFT single-points on ~54-atom system).
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
from pyscf import dft, gto, solvent
from rdkit import Chem
from rdkit.Chem import AllChem

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    BASIS_LIGHT,
    BASIS_OS,
    DFT_CACHE,
    ECP_OS,
    HARTREE_TO_EV,
    LIGANDS_DIR,
    REPO_ROOT,
    SOLVENT_EPS_WATER,
)
from lib.utils import banner

# ── Bond lengths (Å) from crystallographic data of Os-bpy complexes ──
OS_N_BPY = 2.06
OS_N_IM = 2.10
OS_CL = 2.38
BITE_DEG = 78.0

XC_FUNCTIONAL = "b3lyp"
SOLVENT_EPS = SOLVENT_EPS_WATER


# ═══════════════════════════════════════════════════════════════════
# Geometry construction
# ═══════════════════════════════════════════════════════════════════

def _plane_normal(atoms: list[tuple[str, np.ndarray]]) -> np.ndarray:
    """Compute normal to the best-fit plane of heavy atoms."""
    pts = np.array([p for s, p in atoms if s != "H"])
    centroid = pts.mean(axis=0)
    centered = pts - centroid
    _, _, vh = np.linalg.svd(centered)
    normal = vh[-1]
    return normal / np.linalg.norm(normal)


def build_cis_bpy() -> tuple[list[tuple[str, np.ndarray]], int, int]:
    """Build planar s-cis 2,2'-bipyridine (chelation-ready)."""
    mol = Chem.MolFromSmiles("c1ccnc(-c2ccccn2)c1")
    if mol is None:
        sys.exit("RDKit: failed to parse bpy SMILES")
    mol = Chem.AddHs(mol)
    if AllChem.EmbedMolecule(mol, randomSeed=42) != 0:
        sys.exit("RDKit: bpy embed failed")
    AllChem.MMFFOptimizeMolecule(mol, maxIters=2000, mmffVariant="MMFF94s")

    n_idx = [i for i, a in enumerate(mol.GetAtoms()) if a.GetSymbol() == "N"]
    assert len(n_idx) == 2, f"Expected 2 N in bpy, got {len(n_idx)}"

    path = Chem.GetShortestPath(mol, n_idx[0], n_idx[1])
    if len(path) != 4:
        sys.exit(f"Unexpected N-N path length {len(path)} (expected 4: N-C-C-N)")

    conf = mol.GetConformer()
    cur = AllChem.GetDihedralDeg(conf, path[0], path[1], path[2], path[3])
    if abs(cur) > 90:
        AllChem.SetDihedralDeg(conf, path[0], path[1], path[2], path[3], 0.0)

    atoms = []
    for i in range(mol.GetNumAtoms()):
        sym = mol.GetAtomWithIdx(i).GetSymbol()
        p = conf.GetAtomPosition(i)
        atoms.append((sym, np.array([p.x, p.y, p.z])))

    return atoms, n_idx[0], n_idx[1]


def build_meimidazole() -> tuple[list[tuple[str, np.ndarray]], int]:
    """Build 1-methylimidazole; return (atoms, coordinating_N_index)."""
    mol = Chem.MolFromSmiles("Cn1ccnc1")
    if mol is None:
        sys.exit("RDKit: failed to parse 1-MeIm SMILES")
    mol = Chem.AddHs(mol)
    if AllChem.EmbedMolecule(mol, randomSeed=42) != 0:
        sys.exit("RDKit: 1-MeIm embed failed")
    AllChem.MMFFOptimizeMolecule(mol, maxIters=2000, mmffVariant="MMFF94s")

    n_idx = [i for i, a in enumerate(mol.GetAtoms()) if a.GetSymbol() == "N"]
    assert len(n_idx) == 2

    coord_n = None
    for ni in n_idx:
        is_methylated = any(
            nb.GetSymbol() == "C" and nb.GetTotalDegree() == 4
            for nb in mol.GetAtomWithIdx(ni).GetNeighbors()
        )
        if not is_methylated:
            coord_n = ni
            break
    if coord_n is None:
        coord_n = n_idx[1]

    conf = mol.GetConformer()
    atoms = []
    for i in range(mol.GetNumAtoms()):
        sym = mol.GetAtomWithIdx(i).GetSymbol()
        p = conf.GetAtomPosition(i)
        atoms.append((sym, np.array([p.x, p.y, p.z])))

    return atoms, coord_n


def _align_bpy(
    bpy: list[tuple[str, np.ndarray]],
    n1: int,
    n2: int,
    target_n1: np.ndarray,
    target_n2: np.ndarray,
    os_pos: np.ndarray,
) -> list[tuple[str, np.ndarray]]:
    """Rigid-body transform: place bpy N atoms at targets, ring extending outward."""
    s_n1, s_n2 = bpy[n1][1], bpy[n2][1]
    s_mid = (s_n1 + s_n2) / 2
    t_mid = (target_n1 + target_n2) / 2

    # Source frame
    s_e1 = s_n2 - s_n1
    s_e1 /= np.linalg.norm(s_e1)

    s_e3 = _plane_normal(bpy)
    s_e3 -= s_e3.dot(s_e1) * s_e1
    s_e3 /= np.linalg.norm(s_e3)

    s_e2 = np.cross(s_e3, s_e1)
    bulk = np.mean([p for _, p in bpy], axis=0) - s_mid
    if bulk.dot(s_e2) < 0:
        s_e2, s_e3 = -s_e2, -s_e3

    # Target frame
    t_e1 = target_n2 - target_n1
    t_e1 /= np.linalg.norm(t_e1)

    t_e2 = t_mid - os_pos
    t_e2 -= t_e2.dot(t_e1) * t_e1
    t_e2 /= np.linalg.norm(t_e2)

    t_e3 = np.cross(t_e1, t_e2)

    R_s = np.column_stack([s_e1, s_e2, s_e3])
    R_t = np.column_stack([t_e1, t_e2, t_e3])
    R = R_t @ R_s.T

    return [(sym, R @ (pos - s_mid) + t_mid) for sym, pos in bpy]


def _align_monodentate(
    mol_atoms: list[tuple[str, np.ndarray]],
    coord_n: int,
    target_n_pos: np.ndarray,
    outward_dir: np.ndarray,
    plane_hint: np.ndarray,
) -> list[tuple[str, np.ndarray]]:
    """Place monodentate ligand with coordinating N at target, ring outward."""
    s_anchor = mol_atoms[coord_n][1]
    s_com = np.mean([p for _, p in mol_atoms], axis=0)
    s_dir = s_com - s_anchor
    s_dir /= np.linalg.norm(s_dir)

    s_normal = _plane_normal(mol_atoms)
    s_normal -= s_normal.dot(s_dir) * s_dir
    s_normal /= np.linalg.norm(s_normal)
    s_perp = np.cross(s_normal, s_dir)

    t_dir = outward_dir / np.linalg.norm(outward_dir)
    t_normal = plane_hint - plane_hint.dot(t_dir) * t_dir
    t_normal /= np.linalg.norm(t_normal)
    t_perp = np.cross(t_normal, t_dir)

    R_s = np.column_stack([s_dir, s_perp, s_normal])
    R_t = np.column_stack([t_dir, t_perp, t_normal])
    R = R_t @ R_s.T

    return [(sym, R @ (pos - s_anchor) + target_n_pos) for sym, pos in mol_atoms]


def build_full_os_complex() -> list[tuple[str, np.ndarray]]:
    """
    Assemble cis-[Os(bpy)₂(1-MeIm)Cl]⁺.

    Arrangement:
      bpy1 in xz plane (midpoint toward -x,+z)
      bpy2 in yz plane (midpoint toward -y,-z)
      Cl along +x (trans to bpy1 N1 ≈ -x)
      Im along +y (trans to bpy2 N3 ≈ -y)
    """
    os_pos = np.zeros(3)
    half = np.radians(BITE_DEG / 2)

    banner("Building s-cis 2,2'-bipyridine")
    bpy, n1, n2 = build_cis_bpy()
    print(f"  atoms: {len(bpy)}, N indices: [{n1}, {n2}]")

    banner("Building 1-methylimidazole")
    im, im_n = build_meimidazole()
    print(f"  atoms: {len(im)}, coord N: {im_n}")

    # ── bpy1 chelate (xz plane, normal = +y) ──
    mid1 = np.array([-1.0, 0.0, 1.0])
    mid1 /= np.linalg.norm(mid1)
    perp1 = np.cross(np.array([0.0, 1.0, 0.0]), mid1)
    perp1 /= np.linalg.norm(perp1)
    tn1_1 = os_pos + OS_N_BPY * (np.cos(half) * mid1 + np.sin(half) * perp1)
    tn2_1 = os_pos + OS_N_BPY * (np.cos(half) * mid1 - np.sin(half) * perp1)
    bpy1 = _align_bpy(bpy, n1, n2, tn1_1, tn2_1, os_pos)

    # ── bpy2 chelate (yz plane, normal = +x) ──
    mid2 = np.array([0.0, -1.0, -1.0])
    mid2 /= np.linalg.norm(mid2)
    perp2 = np.cross(np.array([1.0, 0.0, 0.0]), mid2)
    perp2 /= np.linalg.norm(perp2)
    tn1_2 = os_pos + OS_N_BPY * (np.cos(half) * mid2 + np.sin(half) * perp2)
    tn2_2 = os_pos + OS_N_BPY * (np.cos(half) * mid2 - np.sin(half) * perp2)
    bpy2 = _align_bpy(bpy, n1, n2, tn1_2, tn2_2, os_pos)

    # ── 1-methylimidazole along +y ──
    im_target = os_pos + OS_N_IM * np.array([0.0, 1.0, 0.0])
    im_placed = _align_monodentate(
        im, im_n, im_target,
        outward_dir=np.array([0.0, 1.0, 0.0]),
        plane_hint=np.array([0.0, 0.0, 1.0]),
    )

    # ── Cl along +x ──
    cl_pos = os_pos + OS_CL * np.array([1.0, 0.0, 0.0])

    all_atoms: list[tuple[str, np.ndarray]] = [("Os", os_pos)]
    all_atoms += bpy1
    all_atoms += bpy2
    all_atoms += im_placed
    all_atoms += [("Cl", cl_pos)]

    # ── Geometry sanity checks ──
    banner("Geometry check")
    positions = np.array([p for _, p in all_atoms])
    n = len(positions)
    min_d, min_pair = 1e9, (0, 0)
    for i in range(n):
        for j in range(i + 1, n):
            d = np.linalg.norm(positions[i] - positions[j])
            if d < min_d:
                min_d = d
                min_pair = (i, j)
    print(f"  Total atoms: {n}")
    print(f"  Min distance: {min_d:.3f} Å ({all_atoms[min_pair[0]][0]}#{min_pair[0]}–{all_atoms[min_pair[1]][0]}#{min_pair[1]})")

    # Check Os-ligand distances
    for label, expected in [("bpy1-N1", OS_N_BPY), ("bpy1-N2", OS_N_BPY),
                            ("bpy2-N1", OS_N_BPY), ("bpy2-N2", OS_N_BPY),
                            ("Im-N", OS_N_IM), ("Cl", OS_CL)]:
        idx_map = {
            "bpy1-N1": 1 + n1,
            "bpy1-N2": 1 + n2,
            "bpy2-N1": 1 + len(bpy) + n1,
            "bpy2-N2": 1 + len(bpy) + n2,
            "Im-N": 1 + 2 * len(bpy) + im_n,
            "Cl": len(all_atoms) - 1,
        }
        dist = np.linalg.norm(positions[idx_map[label]] - positions[0])
        print(f"  Os–{label}: {dist:.3f} Å (target {expected:.2f})")

    if min_d < 0.8:
        print("  ⚠️  Very short contact — geometry may need adjustment")
        sys.exit(1)

    return all_atoms


def write_xyz(atoms: list[tuple[str, np.ndarray]], path: Path, comment: str) -> None:
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, pos in atoms:
            fh.write(f"{sym:2s}  {pos[0]: 12.6f}  {pos[1]: 12.6f}  {pos[2]: 12.6f}\n")


# ═══════════════════════════════════════════════════════════════════
# DFT
# ═══════════════════════════════════════════════════════════════════

def atoms_to_pyscf(atoms: list[tuple[str, np.ndarray]]):
    return [(s, (float(p[0]), float(p[1]), float(p[2]))) for s, p in atoms]


def dft_singlepoint(
    atoms_pyscf, charge: int, spin: int, label: str, with_pcm: bool = True
) -> dict:
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
        mf.with_solvent.eps = SOLVENT_EPS
        mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 400

    t0 = time.time()
    energy_total = mf.kernel()
    dt = time.time() - t0

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


# ═══════════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════════

def main() -> int:
    atoms = build_full_os_complex()
    xyz_path = LIGANDS_DIR / "os_bpy_im_cl.xyz"
    write_xyz(atoms, xyz_path, "cis-[Os(bpy)2(1-MeIm)Cl] — programmatic octahedral")
    banner(f"Wrote {xyz_path.relative_to(REPO_ROOT)}")

    atoms_pyscf = atoms_to_pyscf(atoms)

    results = {
        "method": f"{XC_FUNCTIONAL.upper()}/{BASIS_OS}(Os)+{BASIS_LIGHT}(others)+PCM(water,C-PCM)",
        "model_note": (
            "Full cis-[Os(bpy)2(1-MeIm)Cl]^n+ with π-backbonding from bipyridine. "
            "Supersedes the NH3 surrogate model (script 21)."
        ),
        "os2_plus": dft_singlepoint(
            atoms_pyscf, charge=1, spin=0,
            label="Os(II) [Os(bpy)2(1-MeIm)Cl]+",
        ),
        "os3_plus": dft_singlepoint(
            atoms_pyscf, charge=2, spin=1,
            label="Os(III) [Os(bpy)2(1-MeIm)Cl]2+",
        ),
    }

    de = (results["os2_plus"]["E_total_Ha"] - results["os3_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    print(f"\n  ΔE(Os(III) → Os(II)) ≈ {de:.3f} eV  (electronic only; no ZPE/thermal)")

    out_path = DFT_CACHE / "os_complex.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    banner(f"✅ Saved {out_path.relative_to(REPO_ROOT)}")

    # Quick cascade check vs existing FAD data
    fad_path = DFT_CACHE / "lumiflavin.json"
    if fad_path.exists():
        fad = json.loads(fad_path.read_text(encoding="utf-8"))
        fadh2_homo = fad["red"]["HOMO_eV"]
        os3_lumo = results["os3_plus"]["LUMO_eV"]
        delta = fadh2_homo - os3_lumo
        direction = "✅ DOWNHILL" if delta > 0 else "❌ UPHILL (B3LYP HOMO bias remains)"
        print(f"\n  Quick cascade: HOMO(FADH₂)={fadh2_homo:.3f}, LUMO(Os(III))={os3_lumo:.3f}")
        print(f"  Δε = {delta:+.3f} eV → {direction}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
