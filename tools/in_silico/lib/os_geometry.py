"""Parameterized octahedral Os-complex geometry builder (shared SSOT).

Generalizes the programmatic cis-[Os(bpy)₂(L)(X)]ⁿ⁺ assembly originally inlined
in scripts/21b_dft_os_bpy_full.py so that BOTH the single-complex reference
(21b) and the mediator structure-property series (21e, task ①) build from one
source — no duplicated geometry code (in-silico skill: "shared lib is SSOT").

What varies:
  * `bpy_smiles`  — the chelate (plain 2,2'-bipyridine or 4,4'-substituted), to
                    tune the Os(III/II) potential electronically at constant charge.
  * `monodentate` — the two non-chelate sites (+y, +x): "cl" or an N/O-donor.

RDKit cannot embed an octahedral metal centre, which is exactly why the cage is
assembled by rigid-body placement of MMFF-optimised ligands (as in 21b). Bond
lengths from crystallographic Os-bpy data.

Geometry is returned with an `info` dict (atom count, min contact, Os-ligand
distances) so the *caller* prints/validates — the lib stays I/O-free.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from rdkit import Chem
from rdkit.Chem import AllChem

# ── Crystallographic Os-ligand bond lengths (Å) ──
OS_N_BPY = 2.06
OS_N_DONOR = 2.10        # Os–N(imidazole/pyridine)
OS_O_DONOR = 2.10        # Os–O(aqua)
OS_CL = 2.38
BITE_DEG = 78.0          # N–Os–N bpy bite angle

# ── Ligand SMILES ──
BPY_SMILES = "c1ccnc(-c2ccccn2)c1"                       # 2,2'-bipyridine (parent)
DMBPY_SMILES = "Cc1ccnc(-c2cc(C)ccn2)c1"                 # 4,4'-dimethyl-2,2'-bpy (donor, σ=-0.17)
DCBPY_SMILES = "OC(=O)c1ccnc(-c2cc(C(=O)O)ccn2)c1"       # 4,4'-dicarboxy-2,2'-bpy (acceptor, σ=+0.45)
MEIM_SMILES = "Cn1ccnc1"                                 # 1-methylimidazole
PY_SMILES = "c1ccncc1"                                   # pyridine
WATER_SMILES = "O"                                       # aqua


def _embed(mol):
    """AddHs + MMFF94s-optimised 3D embed (seed=42 for determinism)."""
    mol = Chem.AddHs(mol)
    if AllChem.EmbedMolecule(mol, randomSeed=42) != 0:
        raise RuntimeError("RDKit embed failed")
    AllChem.MMFFOptimizeMolecule(mol, maxIters=2000, mmffVariant="MMFF94s")
    return mol


def _atoms_of(mol):
    conf = mol.GetConformer()
    out = []
    for i in range(mol.GetNumAtoms()):
        p = conf.GetAtomPosition(i)
        out.append((mol.GetAtomWithIdx(i).GetSymbol(), np.array([p.x, p.y, p.z])))
    return out


def _plane_normal(atoms):
    """Normal to the best-fit plane of the heavy atoms."""
    pts = np.array([p for s, p in atoms if s != "H"])
    centroid = pts.mean(axis=0)
    _, _, vh = np.linalg.svd(pts - centroid)
    n = vh[-1]
    return n / np.linalg.norm(n)


def build_chelate(bpy_smiles: str = BPY_SMILES):
    """Build a planar s-cis 2,2'-bipyridine (or 4,4'-substituted); return
    (atoms, n1, n2) where n1,n2 are the two coordinating *ring* N indices."""
    mol = Chem.MolFromSmiles(bpy_smiles)
    if mol is None:
        raise ValueError(f"bad bpy SMILES: {bpy_smiles!r}")
    mol = _embed(mol)

    # Coordinating N = aromatic ring nitrogen (excludes substituent N like -NH₂)
    n_idx = [a.GetIdx() for a in mol.GetAtoms()
             if a.GetSymbol() == "N" and a.GetIsAromatic() and a.IsInRing()]
    if len(n_idx) != 2:
        raise ValueError(f"expected 2 ring N in bpy, got {len(n_idx)} for {bpy_smiles!r}")

    # Flatten the inter-ring dihedral to s-cis (chelation-ready)
    path = Chem.GetShortestPath(mol, n_idx[0], n_idx[1])
    if len(path) != 4:
        raise ValueError(f"unexpected N–N path length {len(path)} (want N-C-C-N)")
    conf = mol.GetConformer()
    if abs(AllChem.GetDihedralDeg(conf, path[0], path[1], path[2], path[3])) > 90:
        AllChem.SetDihedralDeg(conf, path[0], path[1], path[2], path[3], 0.0)

    return _atoms_of(mol), n_idx[0], n_idx[1]


def build_monodentate(smiles: str, coord_elem: str = "N"):
    """Build a monodentate ligand; return (atoms, coord_idx). For an N-donor
    heterocycle the coordinating N is the non-substituted ring N; for water the O."""
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        raise ValueError(f"bad monodentate SMILES: {smiles!r}")
    mol = _embed(mol)

    cand = [a.GetIdx() for a in mol.GetAtoms() if a.GetSymbol() == coord_elem]
    if not cand:
        raise ValueError(f"no {coord_elem} donor in {smiles!r}")

    coord = cand[0]
    if coord_elem == "N" and len(cand) > 1:
        # prefer the ring N NOT bonded to a 4-coordinate C (the methylated one)
        for ni in cand:
            a = mol.GetAtomWithIdx(ni)
            methylated = any(nb.GetSymbol() == "C" and nb.GetTotalDegree() == 4
                             for nb in a.GetNeighbors())
            if a.GetIsAromatic() and not methylated:
                coord = ni
                break
    return _atoms_of(mol), coord


def _align_bpy(bpy, n1, n2, target_n1, target_n2, os_pos):
    """Rigid-body place a bpy so its two N sit at the targets, ring outward."""
    s_n1, s_n2 = bpy[n1][1], bpy[n2][1]
    s_mid = (s_n1 + s_n2) / 2
    t_mid = (target_n1 + target_n2) / 2

    s_e1 = s_n2 - s_n1; s_e1 /= np.linalg.norm(s_e1)
    s_e3 = _plane_normal(bpy); s_e3 -= s_e3.dot(s_e1) * s_e1; s_e3 /= np.linalg.norm(s_e3)
    s_e2 = np.cross(s_e3, s_e1)
    bulk = np.mean([p for _, p in bpy], axis=0) - s_mid
    if bulk.dot(s_e2) < 0:
        s_e2, s_e3 = -s_e2, -s_e3

    t_e1 = target_n2 - target_n1; t_e1 /= np.linalg.norm(t_e1)
    t_e2 = t_mid - os_pos; t_e2 -= t_e2.dot(t_e1) * t_e1; t_e2 /= np.linalg.norm(t_e2)
    t_e3 = np.cross(t_e1, t_e2)

    R = np.column_stack([t_e1, t_e2, t_e3]) @ np.column_stack([s_e1, s_e2, s_e3]).T
    return [(sym, R @ (pos - s_mid) + t_mid) for sym, pos in bpy]


def _align_monodentate(mol_atoms, coord, target_pos, outward_dir, plane_hint):
    """Place a monodentate ligand with its donor atom at target, ring outward."""
    s_anchor = mol_atoms[coord][1]
    s_dir = np.mean([p for _, p in mol_atoms], axis=0) - s_anchor
    s_dir /= np.linalg.norm(s_dir)
    s_normal = _plane_normal(mol_atoms); s_normal -= s_normal.dot(s_dir) * s_dir
    s_normal /= np.linalg.norm(s_normal)
    s_perp = np.cross(s_normal, s_dir)

    t_dir = outward_dir / np.linalg.norm(outward_dir)
    t_normal = plane_hint - plane_hint.dot(t_dir) * t_dir; t_normal /= np.linalg.norm(t_normal)
    t_perp = np.cross(t_normal, t_dir)

    R = np.column_stack([t_dir, t_perp, t_normal]) @ np.column_stack([s_dir, s_perp, s_normal]).T
    return [(sym, R @ (pos - s_anchor) + target_pos) for sym, pos in mol_atoms]


# Default axial set = 1-methylimidazole (+y) and chloride (+x) → reproduces 21b
DEFAULT_AXIAL = (("ligand", MEIM_SMILES, "N"), ("cl",))


def build_os_complex(bpy_smiles: str = BPY_SMILES, axial=DEFAULT_AXIAL):
    """Assemble cis-[Os(bpy)₂(A0)(A1)] octahedron.

    bpy1 in xz-plane, bpy2 in yz-plane; axial[0] along +y, axial[1] along +x.
    `axial` items: ("cl",) for chloride, or ("ligand", smiles, coord_elem).
    Returns (atoms, info) where info has n_atoms / min_contact_A / os_distances.
    """
    os_pos = np.zeros(3)
    half = np.radians(BITE_DEG / 2)
    bpy, n1, n2 = build_chelate(bpy_smiles)

    # ── bpy1 chelate (xz plane) ──
    mid1 = np.array([-1.0, 0.0, 1.0]); mid1 /= np.linalg.norm(mid1)
    perp1 = np.cross(np.array([0.0, 1.0, 0.0]), mid1); perp1 /= np.linalg.norm(perp1)
    tn1_1 = os_pos + OS_N_BPY * (np.cos(half) * mid1 + np.sin(half) * perp1)
    tn2_1 = os_pos + OS_N_BPY * (np.cos(half) * mid1 - np.sin(half) * perp1)
    bpy1 = _align_bpy(bpy, n1, n2, tn1_1, tn2_1, os_pos)

    # ── bpy2 chelate (yz plane) ──
    mid2 = np.array([0.0, -1.0, -1.0]); mid2 /= np.linalg.norm(mid2)
    perp2 = np.cross(np.array([1.0, 0.0, 0.0]), mid2); perp2 /= np.linalg.norm(perp2)
    tn1_2 = os_pos + OS_N_BPY * (np.cos(half) * mid2 + np.sin(half) * perp2)
    tn2_2 = os_pos + OS_N_BPY * (np.cos(half) * mid2 - np.sin(half) * perp2)
    bpy2 = _align_bpy(bpy, n1, n2, tn1_2, tn2_2, os_pos)

    all_atoms = [("Os", os_pos)] + bpy1 + bpy2
    slot_dirs = (np.array([0.0, 1.0, 0.0]), np.array([1.0, 0.0, 0.0]))   # +y, +x
    plane_hints = (np.array([0.0, 0.0, 1.0]), np.array([0.0, 0.0, 1.0]))

    for spec, sdir, phint in zip(axial, slot_dirs, plane_hints):
        if spec[0] == "cl":
            all_atoms.append(("Cl", os_pos + OS_CL * sdir))
        else:
            _, smiles, coord_elem = spec
            lig, coord = build_monodentate(smiles, coord_elem)
            dist = OS_O_DONOR if coord_elem == "O" else OS_N_DONOR
            placed = _align_monodentate(lig, coord, os_pos + dist * sdir, sdir, phint)
            all_atoms.extend(placed)

    # ── geometry diagnostics (caller prints) ──
    pos = np.array([p for _, p in all_atoms])
    n = len(pos)
    min_d, min_pair = 1e9, (0, 0)
    for i in range(n):
        for j in range(i + 1, n):
            d = float(np.linalg.norm(pos[i] - pos[j]))
            if d < min_d:
                min_d, min_pair = d, (i, j)
    os_dists = sorted(float(np.linalg.norm(pos[k] - pos[0]))
                      for k in range(1, n)
                      if all_atoms[k][0] in ("N", "Cl", "O"))[:6]
    info = {
        "n_atoms": n,
        "min_contact_A": round(min_d, 3),
        "min_pair": f"{all_atoms[min_pair[0]][0]}#{min_pair[0]}-{all_atoms[min_pair[1]][0]}#{min_pair[1]}",
        "os_coord_distances_A": [round(d, 3) for d in os_dists],
    }
    return all_atoms, info


def write_xyz(atoms, path: Path, comment: str = ""):
    with Path(path).open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, p in atoms:
            fh.write(f"{sym:2s}  {p[0]: 12.6f}  {p[1]: 12.6f}  {p[2]: 12.6f}\n")
