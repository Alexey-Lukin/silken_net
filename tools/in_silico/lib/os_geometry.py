# SPDX-License-Identifier: AGPL-3.0-or-later
"""Parameterized octahedral Os-complex geometry builder (shared SSOT).

Generalizes the programmatic cis-[Os(bpy)₂(L)(X)]ⁿ⁺ assembly first written inline
in scripts/21b_dft_os_bpy_full.py, so that the mediator structure-property series
(21e, task ①), the device couple (21f) and the speciation series (34, 34b) build
from one source (in-silico skill: "shared lib is SSOT"). ⚠️ 21b itself was never
migrated: it keeps its own builder and its own copy of the constants below (same
values — today its ligands/os_bpy_im_cl.xyz is coordinate-identical to this
builder's plain-bpy chloro complex), and 21d reads that file. A change here does
NOT reach 21b → 21d; nor does it reach the Os–OH₂ distance of 34's hexa-aqua
benchmark, a third copy (`OS_O_AQUA`).

What varies:
  * `bpy_smiles`  — the chelate (plain 2,2'-bipyridine or 4,4'-substituted), to
                    tune the Os(III/II) potential electronically at constant charge.
  * `monodentate` — the two non-chelate sites (+y, +x): "cl" or an N/O-donor.

RDKit cannot embed an octahedral metal centre, which is exactly why the cage is
assembled by rigid-body placement of MMFF-optimised ligands (as in 21b). Bond
lengths are ASSUMED typical Os-ligand distances, not taken from a source: no
structure of this complex class was found, so they are an input assumption, not a
citation. A desk comparison with crystal structures of RELATED Os centres (COD,
2026-10-01) puts every target inside or at the edge of their ranges — a comparison,
never our source (paper §2.3; index paper/09_references.md §Claims still without a
source).
They are placement TARGETS, not the realised geometry: the rigid MMFF chelate keeps
its own N···N (2.69–2.72 Å) and does not close onto the 78° bite, so the realised
Os–N(bpy) is 2.091–2.099 Å at a bite of 80.1–80.6° across the series (measured
from the committed ligands/os_*.xyz); the monodentate distances are realised
exactly. No Os geometry the pipeline uses is optimised (21c tried and was
terminated unconverged). A different set — or a builder that closes the bite — is
a MODEL change: it rebuilds the geometry of 21e/21f/34/34b, and of 21b → 21d only
through 21b's own copy.
`close_chelate=True` is that builder behind a switch, OFF by default and read only by
`76` (C-min, the computed sensitivity of paper §2.3): the chelate is re-optimised with
its N···N held at the spacing the two targets imply and its N–C–C–N dihedral held, so
the rigid placement realises Os–N(bpy) and the bite — and the build REFUSES when it
does not (in-silico §When Modifying #27). The default path never enters that code.

Geometry is returned with an `info` dict (atom count, min contact, Os-ligand
distances) so the *caller* prints/validates — the lib stays I/O-free.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from rdkit import Chem
from rdkit.Chem import AllChem

# ── Os-ligand bond lengths (Å) — ASSUMED typical values, no primary source in the tree ──
OS_N_BPY = 2.06
OS_N_DONOR = 2.10        # Os–N(imidazole/pyridine)
OS_O_DONOR = 2.10        # Os–O(aqua)
OS_CL = 2.38
BITE_DEG = 78.0          # N–Os–N bpy bite angle

# ── chelate closure — read only when close_chelate=True ──
CLOSE_K = 1.0e5          # MMFF restraint stiffness on the held N···N and N–C–C–N dihedral
CLOSE_RESTARTS = 50      # Minimize calls allowed before the closure gives up (`_hold_nn`)
CLOSE_TOL_A = 0.002      # refusal band: each realised Os–N(bpy) against OS_N_BPY (≫ the closure's own N···N residual,
                         # ≤ 0.2 mÅ on every series ligand, 2026-10-02) …
CLOSE_TOL_DEG = 0.1      # … each bite against BITE_DEG, the dihedral against its pre-closure value

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


def build_chelate(bpy_smiles: str = BPY_SMILES, nn_A: float | None = None):
    """Build a planar s-cis 2,2'-bipyridine (or 4,4'-substituted); return
    (atoms, n1, n2) where n1,n2 are the two coordinating *ring* N indices.
    `nn_A` (Å): None keeps the MMFF chelate with its own N···N; a value closes it
    to that N···N (`_hold_nn`)."""
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
    if nn_A is not None:
        _hold_nn(mol, path, nn_A)

    return _atoms_of(mol), n_idx[0], n_idx[1]


def _hold_nn(mol, path, nn_A):
    """Re-optimise the s-cis chelate under MMFF94s with its ring-N···N held at `nn_A` and
    the N–C–C–N dihedral held where the flattening left it: the closure is carried by the
    ring angles, not by a twist. Refuses an unconverged or drifted result."""
    conf = mol.GetConformer()
    dih0 = AllChem.GetDihedralDeg(conf, *path)
    ff = AllChem.MMFFGetMoleculeForceField(
        mol, AllChem.MMFFGetMoleculeProperties(mol, mmffVariant="MMFF94s"))
    ff.MMFFAddDistanceConstraint(path[0], path[3], False, nn_A, nn_A, CLOSE_K)
    ff.MMFFAddTorsionConstraint(*path, False, dih0, dih0, CLOSE_K)
    # RDKit's BFGS reports convergence (0) when its line search stalls against the stiff restraint, short of
    # the minimum — one call left bpy 0.03 Å off the held N···N. Each call resets the Hessian, so restart
    # until two converged calls agree; the realised-distance gate in `build_os_complex` stays the arbiter.
    e_prev = None
    for _ in range(CLOSE_RESTARTS):
        rc, e = ff.Minimize(maxIts=2000), ff.CalcEnergy()
        if rc == 0 and e_prev is not None and abs(e - e_prev) < 1e-9:
            break
        e_prev = e
    else:
        raise RuntimeError(f"chelate closure to N···N {nn_A:.4f} Å did not converge")
    if abs(AllChem.GetDihedralDeg(conf, *path) - dih0) > CLOSE_TOL_DEG:
        raise RuntimeError(f"chelate closure moved the N–C–C–N dihedral off {dih0:.2f}°")


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

    s_e1 = s_n2 - s_n1
    s_e1 /= np.linalg.norm(s_e1)
    s_e3 = _plane_normal(bpy)
    s_e3 -= s_e3.dot(s_e1) * s_e1
    s_e3 /= np.linalg.norm(s_e3)
    s_e2 = np.cross(s_e3, s_e1)
    bulk = np.mean([p for _, p in bpy], axis=0) - s_mid
    if bulk.dot(s_e2) < 0:
        s_e2, s_e3 = -s_e2, -s_e3

    t_e1 = target_n2 - target_n1
    t_e1 /= np.linalg.norm(t_e1)
    t_e2 = t_mid - os_pos
    t_e2 -= t_e2.dot(t_e1) * t_e1
    t_e2 /= np.linalg.norm(t_e2)
    t_e3 = np.cross(t_e1, t_e2)

    R = np.column_stack([t_e1, t_e2, t_e3]) @ np.column_stack([s_e1, s_e2, s_e3]).T
    return [(sym, R @ (pos - s_mid) + t_mid) for sym, pos in bpy]


def _rotate_about_axis(point, axis, origin, angle_rad):
    """Rodrigues rotation of a single point about `axis` through `origin`."""
    k = axis / np.linalg.norm(axis)
    v = point - origin
    return (origin + v * np.cos(angle_rad)
            + np.cross(k, v) * np.sin(angle_rad)
            + k * k.dot(v) * (1.0 - np.cos(angle_rad)))


def _align_monodentate(mol_atoms, coord, target_pos, outward_dir, plane_hint, twist_deg=0.0):
    """Place a monodentate ligand with its donor atom at target, ring outward.

    `twist_deg` rotates the placed ligand about its Os–donor bond axis — a real
    low-barrier rotational DOF — used to twist two cis rings into a propeller when
    they would otherwise clash co-planar (bis-Im, 00_07 note 20/26)."""
    s_anchor = mol_atoms[coord][1]
    s_dir = np.mean([p for _, p in mol_atoms], axis=0) - s_anchor
    s_dir /= np.linalg.norm(s_dir)
    s_normal = _plane_normal(mol_atoms)
    s_normal -= s_normal.dot(s_dir) * s_dir
    s_normal /= np.linalg.norm(s_normal)
    s_perp = np.cross(s_normal, s_dir)

    t_dir = outward_dir / np.linalg.norm(outward_dir)
    t_normal = plane_hint - plane_hint.dot(t_dir) * t_dir
    t_normal /= np.linalg.norm(t_normal)
    t_perp = np.cross(t_normal, t_dir)

    R = np.column_stack([t_dir, t_perp, t_normal]) @ np.column_stack([s_dir, s_perp, s_normal]).T
    placed = [(sym, R @ (pos - s_anchor) + target_pos) for sym, pos in mol_atoms]
    if twist_deg:
        ang = np.radians(twist_deg)
        placed = [(sym, _rotate_about_axis(p, t_dir, target_pos, ang)) for sym, p in placed]
    return placed


# Default axial set = 1-methylimidazole (+y) and chloride (+x) → reproduces 21b
DEFAULT_AXIAL = (("ligand", MEIM_SMILES, "N"), ("cl",))


def build_os_complex(bpy_smiles: str = BPY_SMILES, axial=DEFAULT_AXIAL,
                     axial_twists=(0.0, 0.0), close_chelate: bool = False):
    """Assemble cis-[Os(bpy)₂(A0)(A1)] octahedron.

    bpy1 in xz-plane, bpy2 in yz-plane; axial[0] along +y, axial[1] along +x.
    `axial` items: ("cl",) for chloride, or ("ligand", smiles, coord_elem).
    `axial_twists` (deg) rotate each axial ligand about its Os–donor bond — leave
    (0, 0) for the canonical placement (21b/① series/mediator/aqua all unchanged);
    used only to propeller two cis rings apart (bis-Im, note 20/26).
    `close_chelate` closes both chelates onto OS_N_BPY at BITE_DEG and refuses the
    build if either is not realised (C-min only; module docstring).
    Returns (atoms, info) where info has n_atoms / min_contact_A / os_distances and
    the realised chelate (os_n_bpy_A, bite_deg).
    """
    os_pos = np.zeros(3)
    half = np.radians(BITE_DEG / 2)
    bpy, n1, n2 = build_chelate(bpy_smiles, nn_A=2 * OS_N_BPY * np.sin(half) if close_chelate else None)

    # ── bpy1 chelate (xz plane) ──
    mid1 = np.array([-1.0, 0.0, 1.0])
    mid1 /= np.linalg.norm(mid1)
    perp1 = np.cross(np.array([0.0, 1.0, 0.0]), mid1)
    perp1 /= np.linalg.norm(perp1)
    tn1_1 = os_pos + OS_N_BPY * (np.cos(half) * mid1 + np.sin(half) * perp1)
    tn2_1 = os_pos + OS_N_BPY * (np.cos(half) * mid1 - np.sin(half) * perp1)
    bpy1 = _align_bpy(bpy, n1, n2, tn1_1, tn2_1, os_pos)

    # ── bpy2 chelate (yz plane) ──
    mid2 = np.array([0.0, -1.0, -1.0])
    mid2 /= np.linalg.norm(mid2)
    perp2 = np.cross(np.array([1.0, 0.0, 0.0]), mid2)
    perp2 /= np.linalg.norm(perp2)
    tn1_2 = os_pos + OS_N_BPY * (np.cos(half) * mid2 + np.sin(half) * perp2)
    tn2_2 = os_pos + OS_N_BPY * (np.cos(half) * mid2 - np.sin(half) * perp2)
    bpy2 = _align_bpy(bpy, n1, n2, tn1_2, tn2_2, os_pos)

    all_atoms = [("Os", os_pos), *bpy1, *bpy2]
    block_id = [-1] + [0] * len(bpy1) + [1] * len(bpy2)   # -1 = metal (skip in clash)
    slot_dirs = (np.array([0.0, 1.0, 0.0]), np.array([1.0, 0.0, 0.0]))   # +y, +x
    plane_hints = (np.array([0.0, 0.0, 1.0]), np.array([0.0, 0.0, 1.0]))

    for k, (spec, sdir, phint, tw) in enumerate(zip(axial, slot_dirs, plane_hints, axial_twists, strict=False)):
        if spec[0] == "cl":
            all_atoms.append(("Cl", os_pos + OS_CL * sdir))
            block_id.append(2 + k)
        else:
            _, smiles, coord_elem = spec
            lig, coord = build_monodentate(smiles, coord_elem)
            dist = OS_O_DONOR if coord_elem == "O" else OS_N_DONOR
            placed = _align_monodentate(lig, coord, os_pos + dist * sdir, sdir, phint,
                                        twist_deg=tw)
            all_atoms.extend(placed)
            block_id.extend([2 + k] * len(placed))

    # ── geometry diagnostics (caller prints) ──
    # min_contact_A = closest atom pair *incl. bonds* (~1.08 C–H floor); a catastrophic-
    # fusion sentinel. min_interlig_A = closest pair across DIFFERENT ligand blocks (metal
    # excluded) = the true non-bonded steric clash (what gates a propeller de-clash).
    pos = np.array([p for _, p in all_atoms])
    n = len(pos)
    min_d, min_pair = 1e9, (0, 0)
    min_il, min_il_pair = 1e9, (0, 0)
    for i in range(n):
        for j in range(i + 1, n):
            d = float(np.linalg.norm(pos[i] - pos[j]))
            if d < min_d:
                min_d, min_pair = d, (i, j)
            if block_id[i] >= 0 and block_id[j] >= 0 and block_id[i] != block_id[j] and d < min_il:
                min_il, min_il_pair = d, (i, j)
    os_dists = sorted(float(np.linalg.norm(pos[k] - pos[0]))
                      for k in range(1, n)
                      if all_atoms[k][0] in ("N", "Cl", "O"))[:6]
    chelates = [(1 + n1, 1 + n2), (1 + len(bpy) + n1, 1 + len(bpy) + n2)]
    os_n_bpy = [float(np.linalg.norm(pos[k] - pos[0])) for pair in chelates for k in pair]
    bites = [float(np.degrees(np.arccos(np.dot(pos[a], pos[b]) / np.linalg.norm(pos[a]) / np.linalg.norm(pos[b]))))
             for a, b in chelates]
    if close_chelate and (max(abs(d - OS_N_BPY) for d in os_n_bpy) > CLOSE_TOL_A
                          or max(abs(b - BITE_DEG) for b in bites) > CLOSE_TOL_DEG):
        raise ValueError(f"closed chelate not realised: Os–N(bpy) {[round(d, 4) for d in os_n_bpy]} Å, "
                         f"bite {[round(b, 2) for b in bites]}° against {OS_N_BPY} Å / {BITE_DEG}°")
    info = {
        "n_atoms": n,
        "min_contact_A": round(min_d, 3),
        "min_pair": f"{all_atoms[min_pair[0]][0]}#{min_pair[0]}-{all_atoms[min_pair[1]][0]}#{min_pair[1]}",
        "min_interlig_A": round(min_il, 3),
        "min_interlig_pair": f"{all_atoms[min_il_pair[0]][0]}#{min_il_pair[0]}-{all_atoms[min_il_pair[1]][0]}#{min_il_pair[1]}",
        "os_coord_distances_A": [round(d, 3) for d in os_dists],
        "os_n_bpy_A": [round(d, 4) for d in os_n_bpy],
        "bite_deg": [round(b, 2) for b in bites],
    }
    return all_atoms, info


def write_xyz(atoms, path: Path, comment: str = ""):
    with Path(path).open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, p in atoms:
            fh.write(f"{sym:2s}  {p[0]: 12.6f}  {p[1]: 12.6f}  {p[2]: 12.6f}\n")
