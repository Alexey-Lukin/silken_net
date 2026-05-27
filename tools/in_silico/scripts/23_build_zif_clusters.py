#!/usr/bin/env python
"""
L3b step 1 — build bimetallic ZIF cluster models for hopping integral calculations.

Constructs three minimal bimetallic clusters that represent the DET pathway
through the nCoCuCeZIF nanozyme cathode:

  MWCNT ←t₃→ Ce(Im)₂ ←t₂→ Co(Im)₂ ←t₁→ Cu(Im)₂ (≈ laccase T1)

Each cluster: two metal centers bridged by a 2-methylimidazolate linker,
with additional terminal imidazolate ligands for tetrahedral coordination.

Geometry: programmatic octahedral/tetrahedral placement (same approach as
script 21b for Os-bpy). Metal-N distances from crystallographic data.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/23_build_zif_clusters.py
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from rdkit import Chem
from rdkit.Chem import AllChem

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import REPO_ROOT, LIGANDS_DIR
from lib.utils import banner

LIGANDS_DIR.mkdir(parents=True, exist_ok=True)

BOND_CU_N = 2.02   # Å — Cu²⁺ in ZIF / imidazolate
BOND_CO_N = 2.05   # Å — Co²⁺ in ZIF-67
BOND_CE_N = 2.45   # Å — Ce³⁺ in imidazolate (larger ionic radius)
ZIF_NODE_DIST = 6.0  # Å (sodalite topology)

MEIMID_SMILES = "Cc1ncc[nH]1"


def build_meimidazole() -> tuple[list[tuple[str, np.ndarray]], int, int]:
    """Build 2-methylimidazole; return (atoms, N3_idx, NH_idx)."""
    mol = Chem.MolFromSmiles(MEIMID_SMILES)
    mol = Chem.AddHs(mol)
    AllChem.EmbedMolecule(mol, randomSeed=42)
    AllChem.MMFFOptimizeMolecule(mol, maxIters=2000, mmffVariant="MMFF94s")

    n_indices = [i for i, a in enumerate(mol.GetAtoms()) if a.GetSymbol() == "N"]
    # N3 = deprotonated (coordinates to metal), NH = protonated
    nh_idx = None
    n3_idx = None
    for ni in n_indices:
        has_h = any(mol.GetAtomWithIdx(nb.GetIdx()).GetSymbol() == "H"
                    for nb in mol.GetAtomWithIdx(ni).GetNeighbors())
        if has_h:
            nh_idx = ni
        else:
            n3_idx = ni
    if n3_idx is None:
        n3_idx = n_indices[0]
    if nh_idx is None:
        nh_idx = n_indices[1]

    conf = mol.GetConformer()
    atoms = []
    for i in range(mol.GetNumAtoms()):
        sym = mol.GetAtomWithIdx(i).GetSymbol()
        p = conf.GetAtomPosition(i)
        atoms.append((sym, np.array([p.x, p.y, p.z])))
    return atoms, n3_idx, nh_idx


def place_ligand_at(
    lig_atoms: list[tuple[str, np.ndarray]],
    coord_n: int,
    target_n: np.ndarray,
    outward: np.ndarray,
) -> list[tuple[str, np.ndarray]]:
    """Place ligand with coordinating N at target_n, ring extending outward."""
    anchor = lig_atoms[coord_n][1]
    com = np.mean([p for _, p in lig_atoms], axis=0)
    src_dir = com - anchor
    src_dir /= np.linalg.norm(src_dir)

    tgt_dir = outward / np.linalg.norm(outward)

    # Simple rotation: align src_dir to tgt_dir
    v = np.cross(src_dir, tgt_dir)
    s = np.linalg.norm(v)
    c = np.dot(src_dir, tgt_dir)

    if s < 1e-8:
        R = np.eye(3) if c > 0 else -np.eye(3)
    else:
        vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
        R = np.eye(3) + vx + vx @ vx * (1 - c) / (s * s)

    return [(sym, R @ (pos - anchor) + target_n) for sym, pos in lig_atoms]


def build_bimetallic_cluster(
    metal1: str, r1: float,
    metal2: str, r2: float,
    label: str,
) -> list[tuple[str, np.ndarray]]:
    """Build M1(Im)₂ -- Im_bridge -- M2(Im)₂ cluster."""
    im, n3, nh = build_meimidazole()

    m1_pos = np.array([-ZIF_NODE_DIST / 2, 0.0, 0.0])
    m2_pos = np.array([+ZIF_NODE_DIST / 2, 0.0, 0.0])
    bridge_dir = m2_pos - m1_pos
    bridge_dir /= np.linalg.norm(bridge_dir)

    all_atoms: list[tuple[str, np.ndarray]] = []
    all_atoms.append((metal1, m1_pos))
    all_atoms.append((metal2, m2_pos))

    # Bridging imidazolate: N3 → M1, NH → M2
    bridge_n3_pos = m1_pos + r1 * bridge_dir
    bridge_nh_pos = m2_pos - r2 * bridge_dir
    bridge_mid = (bridge_n3_pos + bridge_nh_pos) / 2
    bridge = place_ligand_at(im, n3, bridge_n3_pos, bridge_dir)
    all_atoms += bridge

    # Terminal ligands on M1: 2 imidazolates at ~109° (tetrahedral)
    for angle in [120, 240]:
        rad = np.radians(angle)
        direction = np.array([np.cos(rad), np.sin(rad), 0.0])
        target = m1_pos + r1 * direction
        lig = place_ligand_at(im, n3, target, direction)
        all_atoms += lig

    # Terminal ligands on M2: 2 imidazolates
    for angle in [60, -60]:
        rad = np.radians(angle)
        direction = np.array([np.cos(rad), np.sin(rad), 0.0])
        target = m2_pos + r2 * direction
        lig = place_ligand_at(im, n3, target, direction)
        all_atoms += lig

    print(f"  {label}: {len(all_atoms)} atoms ({metal1} + {metal2} + 5×MeIm)")
    return all_atoms


def build_ce_graphene_cluster() -> list[tuple[str, np.ndarray]]:
    """Build Ce(Im)₂ + coronene (MWCNT proxy) cluster."""
    im, n3, nh = build_meimidazole()

    ce_pos = np.array([0.0, 0.0, 3.5])  # Ce 3.5 Å above graphene plane
    all_atoms: list[tuple[str, np.ndarray]] = [("Ce", ce_pos)]

    # Two terminal imidazolates on Ce
    for angle in [60, -60]:
        rad = np.radians(angle)
        direction = np.array([np.cos(rad), np.sin(rad), 0.5])
        direction /= np.linalg.norm(direction)
        target = ce_pos + BOND_CE_N * direction
        lig = place_ligand_at(im, n3, target, direction)
        all_atoms += lig

    # Coronene (C₂₄H₁₂) from RDKit — clean aromatic MWCNT surface proxy
    cor_mol = Chem.MolFromSmiles("c1cc2ccc3ccc4ccc5ccc6ccc1c7c2c3c4c5c67")
    cor_mol = Chem.AddHs(cor_mol)
    AllChem.EmbedMolecule(cor_mol, randomSeed=42)
    AllChem.MMFFOptimizeMolecule(cor_mol, maxIters=2000, mmffVariant="MMFF94s")
    conf = cor_mol.GetConformer()
    for i in range(cor_mol.GetNumAtoms()):
        sym = cor_mol.GetAtomWithIdx(i).GetSymbol()
        p = conf.GetAtomPosition(i)
        all_atoms.append((sym, np.array([p.x, p.y, 0.0])))  # flatten to z=0

    n_cor = cor_mol.GetNumAtoms()
    print(f"  Ce-graphene: {len(all_atoms)} atoms (Ce + 2×MeIm + coronene {n_cor})")
    return all_atoms


def write_xyz(atoms: list[tuple[str, np.ndarray]], path: Path, comment: str) -> None:
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, pos in atoms:
            fh.write(f"{sym:2s}  {pos[0]: 12.6f}  {pos[1]: 12.6f}  {pos[2]: 12.6f}\n")


def check_distances(atoms: list[tuple[str, np.ndarray]], label: str) -> None:
    positions = np.array([p for _, p in atoms])
    n = len(positions)
    min_d = 1e9
    for i in range(n):
        for j in range(i + 1, n):
            d = np.linalg.norm(positions[i] - positions[j])
            if d < min_d:
                min_d = d
                mi, mj = i, j
    print(f"  Min distance: {min_d:.3f} Å ({atoms[mi][0]}#{mi}–{atoms[mj][0]}#{mj})")
    if min_d < 0.8:
        print(f"  ⚠️  Short contact in {label}!")


def main() -> int:
    banner("L3b — building ZIF bimetallic cluster models")

    banner("1. Cu-Co cluster (T1 ↔ ZIF-67 node)")
    cu_co = build_bimetallic_cluster("Cu", BOND_CU_N, "Co", BOND_CO_N, "Cu-Co")
    check_distances(cu_co, "Cu-Co")
    p1 = LIGANDS_DIR / "cu_co_zif.xyz"
    write_xyz(cu_co, p1, "Cu(Im)2-Im-Co(Im)2 bimetallic ZIF cluster")
    print(f"  Wrote {p1.relative_to(REPO_ROOT)}")

    banner("2. Co-Ce cluster (ZIF-67 node ↔ Ce vacancy)")
    co_ce = build_bimetallic_cluster("Co", BOND_CO_N, "Ce", BOND_CE_N, "Co-Ce")
    check_distances(co_ce, "Co-Ce")
    p2 = LIGANDS_DIR / "co_ce_zif.xyz"
    write_xyz(co_ce, p2, "Co(Im)2-Im-Ce(Im)2 bimetallic ZIF cluster")
    print(f"  Wrote {p2.relative_to(REPO_ROOT)}")

    banner("3. Ce-graphene cluster (Ce ↔ MWCNT electrode)")
    ce_gr = build_ce_graphene_cluster()
    check_distances(ce_gr, "Ce-graphene")
    p3 = LIGANDS_DIR / "ce_graphene.xyz"
    write_xyz(ce_gr, p3, "Ce(Im)2 + coronene (MWCNT proxy)")
    print(f"  Wrote {p3.relative_to(REPO_ROOT)}")

    banner("✅ All 3 ZIF clusters built")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
