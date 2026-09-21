#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L3b step 1 — build bimetallic ZIF cluster models for hopping integral calculations.

Constructs three minimal bimetallic clusters that represent the DET pathway
through the nCoCuCeZIF nanozyme cathode:

  MWCNT ←t₃→ Ce(Im)₂ ←t₂→ Co(Im)₂ ←t₁→ Cu(Im)₂ (≈ laccase T1)

Each cluster: two metal centers bridged by a 2-methylimidazolate linker,
with additional terminal imidazolate ligands for tetrahedral coordination.

Geometry: programmatic octahedral/tetrahedral placement (same approach as
script 21b for Os-bpy). Metal-N distances from crystallographic data.

🔴 **This model is COPLANAR by construction, and that is a hard limit, not a detail**
(measured 2026-09-21 while pricing the CHEM.35 benzimidazolate bridge, `01_03 §3.2`).
The terminal ligands lie in the metal plane, so a bridge placed correctly — both ring
N at their bond length, both metals IN the bridge-ring plane — collides with them
(0.254 Å for methylimidazolate, 0.358 Å for benzimidazolate). The shipped cluster
escapes that only because `place_ligand_at` lays the ring ALONG the M···M axis, at the
cost of a 5 % short Co–N. **So no BRIDGE lever is answerable here: it needs a 3D cluster
with tetrahedral terminals, which moves every shipped L3b number** (⚖️ `00_07` HW.5.IS).
The flags below exist to MEASURE that limit, not to work around it.

⚠️ `ZIF_NODE_DIST` is FIXED, so a linker swap alone cannot move the metals apart in this
model. That is only legitimate while the bridge N···N span — the distance that actually
sets M···M through an imidazolate bridge — is linker-invariant, and this script now
MEASURES it across the whole linker library each run (`zif_bridge_geometry.json`) instead
of assuming it. A linker outside `SPAN_TOLERANCE_A` makes the fixed node distance an
unstated assumption, and the run refuses.

Every variant takes its OWN out-path, because a flag that changes the MODEL must not
overwrite the shipped one (§When Modifying #17).

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/23_build_zif_clusters.py             # the shipped stack
    python tools/in_silico/scripts/23_build_zif_clusters.py --bridge-linker bzim
    # the REFUSED probe that prices the ring-roll freedom (×24 on t_ij):
    python tools/in_silico/scripts/23_build_zif_clusters.py --solve-bridge --roll perpendicular
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from rdkit import Chem
from rdkit.Chem import AllChem

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, LIGANDS_DIR, REPO_ROOT
from lib.utils import banner

LIGANDS_DIR.mkdir(parents=True, exist_ok=True)

BOND_CU_N = 2.02   # Å — Cu²⁺ in ZIF / imidazolate
BOND_CO_N = 2.05   # Å — Co²⁺ in ZIF-67
BOND_CE_N = 2.45   # Å — Ce³⁺ in imidazolate (larger ionic radius)
ZIF_NODE_DIST = 6.0  # Å (sodalite topology)

# Linker library. `meim` is the shipped stack; `bzim` is the CHEM.35 lever.
LINKERS: dict[str, tuple[str, str]] = {
    "meim": ("Cc1ncc[nH]1", "2-methylimidazolate — ZIF-8, shipped cathode stack"),
    "bzim": ("c1ccc2[nH]cnc2c1", "benzimidazolate — ZIF-7/11, CHEM.35 lever"),
}
REFERENCE_LINKER = "meim"
SPAN_TOLERANCE_A = 0.05   # Å — see the module docstring; 0.05 is ~2% of the span and
                          # an order below the 0.9 Å by which the benzo fusion grows
                          # the ligand FOOTPRINT, so the control separates the two axes.

MEIMID_SMILES = LINKERS[REFERENCE_LINKER][0]


def build_linker(
    smiles: str, deprotonate_nh: bool = False,
) -> tuple[list[tuple[str, np.ndarray]], int, int]:
    """Build a bridging linker from SMILES; return (atoms, N3_idx, NH_idx).

    `deprotonate_nh` removes the proton on the N–H nitrogen, which is what a
    BRIDGING imidazolate actually is. The shipped path does not use it: there the
    proton is stripped afterwards by `deprotonate_metal_clashes`, i.e. by a
    proximity heuristic that only fires because the legacy placement happens to
    drive that H into the second metal. Fix the placement and the heuristic stops
    firing — so a correctly placed bridge must be deprotonated by CHEMISTRY here.
    """
    mol = Chem.MolFromSmiles(smiles)
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

    drop = set()
    if deprotonate_nh:
        drop = {nb.GetIdx() for nb in mol.GetAtomWithIdx(nh_idx).GetNeighbors()
                if nb.GetSymbol() == "H"}
        if len(drop) != 1:
            raise ValueError(f"expected exactly one N–H proton, found {len(drop)}")

    conf = mol.GetConformer()
    atoms = []
    remap: dict[int, int] = {}
    for i in range(mol.GetNumAtoms()):
        if i in drop:
            continue
        sym = mol.GetAtomWithIdx(i).GetSymbol()
        p = conf.GetAtomPosition(i)
        remap[i] = len(atoms)
        atoms.append((sym, np.array([p.x, p.y, p.z])))
    return atoms, remap[n3_idx], remap[nh_idx]


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


def place_bridge_ligand(
    lig_atoms: list[tuple[str, np.ndarray]],
    n3: int, nh: int,
    m1: np.ndarray, m2: np.ndarray,
    r1: float, r2: float,
    roll: str = "inplane",
) -> list[tuple[str, np.ndarray]]:
    """Place a BRIDGING linker so BOTH ring nitrogens reach their metal.

    `place_ligand_at` orients a ligand by its centre of mass, which says nothing
    about where the second nitrogen lands. For 2-methylimidazolate that accident
    is benign (the second N arrives ~1.95 Å from M2 — a bond); for a ring fused at
    the back it is not (benzimidazolate arrives at ~3.2 Å — no bond at all, and the
    N–H then survives the clash filter, leaving an unbridged, mis-charged dimer).

    Here the placement is SOLVED instead: N3 sits at `m1 + r1·u`, and the ligand is
    rotated about N3 so that N1 lands exactly `r2` from M2. The M–N–C angles bend to
    absorb the difference, which is what a real zigzag imidazolate bridge does — the
    N···N span (2.21 Å) is longer than the `D − r1 − r2` gap, so a collinear bridge
    does not exist at any linker.

    🔴 The ring is then rolled about the N···N axis until BOTH metals lie IN its plane
    (normal ∥ ẑ), and that criterion is the load-bearing half: a coordinating nitrogen
    binds through a lone pair that lies IN the ring plane, so an out-of-plane metal is
    not a longer bond, it is the WRONG bond. Measured cost of getting this backwards —
    an earlier build rolled the ring PERPENDICULAR instead (chosen to keep a bulky
    linker off the coplanar terminals), which put Cu 0.70 Å and Co 1.37 Å off the plane
    and moved the FO-DFT coupling by **24×**, because the metal d then overlaps the ring
    π directly. It looked physical to every check in the pipeline.

    CAN catch nothing by itself — it is a constructor, and its output is judged by
    `check_distances`, by the M–N distances the caller prints, and by the in-plane
    criterion above. CANNOT give a relaxed geometry: nothing here minimises energy, so
    a bulky linker may still clash with the coplanar terminals — that is what the
    caller's clash refusal is for, and it is a real limit of a 2D minimal model.
    """
    a = lig_atoms[n3][1]
    b = lig_atoms[nh][1]
    s = float(np.linalg.norm(b - a))

    u = (m2 - m1) / np.linalg.norm(m2 - m1)
    p3 = m1 + r1 * u
    d = float(np.linalg.norm(m2 - p3))

    cos_phi = (s * s + d * d - r2 * r2) / (2.0 * s * d)
    if not -1.0 <= cos_phi <= 1.0:
        raise ValueError(
            f"no bridge closes: span {s:.3f} Å, gap {d:.3f} Å, M2–N target {r2:.3f} Å"
        )
    phi = float(np.arccos(cos_phi))

    # in-plane normal to u (the metals lie on x, the cluster is built in xy)
    n_hat = np.cross(np.array([0.0, 0.0, 1.0]), u)
    n_hat /= np.linalg.norm(n_hat)
    target_dir = np.cos(phi) * u + np.sin(phi) * n_hat

    src_dir = (b - a) / s
    placed = _rotate_onto(lig_atoms, a, src_dir, target_dir, p3)

    # Roll about the N···N axis until the ring plane CONTAINS both metals. The metals sit
    # on x and the two bridging N are placed in xy, so that is exactly `normal ∥ ẑ` — the
    # score to MAXIMISE. ⛔ Minimising it stands the ring on edge and takes the metals out
    # of their own lone pairs (see the docstring: 24× on the coupling).
    z_hat = np.array([0.0, 0.0, 1.0])
    axis = target_dir
    if roll == "perpendicular":
        # ⛔ NOT a production geometry — the planarity check refuses it. Kept buildable so
        # the 24× coupling sensitivity it measures stays a live instrument rather than a
        # remembered number (a retired branch gets a frozen witness, not a deletion).
        best, best_score = placed, -abs(float(np.dot(_ring_normal(placed), z_hat)))
        for deg in range(5, 180, 5):
            cand = _rotate_about_axis(placed, p3, axis, np.radians(deg))
            score = -abs(float(np.dot(_ring_normal(cand), z_hat)))
            if score > best_score:
                best, best_score = cand, score
        return best
    best, best_score = placed, abs(float(np.dot(_ring_normal(placed), z_hat)))
    for deg in range(1, 360):
        cand = _rotate_about_axis(placed, p3, axis, np.radians(deg))
        score = abs(float(np.dot(_ring_normal(cand), z_hat)))
        if score > best_score:
            best, best_score = cand, score
    return best


def _rotate_onto(atoms, anchor, src_dir, tgt_dir, target_anchor):
    """Rodrigues rotation aligning `src_dir` onto `tgt_dir`, re-anchored.

    ⛔ Deliberately NOT factored out of `place_ligand_at`, although the algebra is the
    same: the shipped cluster XYZ is committed and its coupling is pinned doc↔cache, so
    re-associating those float operations could move the last digits of a geometry
    nothing else would flag. The duplication is the cheaper of the two risks.
    """
    v = np.cross(src_dir, tgt_dir)
    s_ = np.linalg.norm(v)
    c = float(np.dot(src_dir, tgt_dir))
    if s_ < 1e-8:
        R = np.eye(3) if c > 0 else -np.eye(3)
    else:
        vx = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
        R = np.eye(3) + vx + vx @ vx * (1 - c) / (s_ * s_)
    return [(sym, R @ (pos - anchor) + target_anchor) for sym, pos in atoms]


def _rotate_about_axis(atoms, origin, axis, theta):
    k = axis / np.linalg.norm(axis)
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    R = np.eye(3) + np.sin(theta) * K + (1 - np.cos(theta)) * (K @ K)
    return [(sym, R @ (pos - origin) + origin) for sym, pos in atoms]


def _ring_normal(atoms) -> np.ndarray:
    heavy = np.array([p for s, p in atoms if s != "H"])
    centred = heavy - heavy.mean(axis=0)
    # smallest-variance direction = plane normal (rings are near-planar)
    return np.linalg.svd(centred)[2][-1]


def bridge_span_nn(atoms: list[tuple[str, np.ndarray]], n3: int, nh: int) -> float:
    """Distance between the two ring nitrogens of a linker, in Å.

    This is the geometric quantity the metal···metal distance rides on: an
    imidazolate bridges through N3→M1 and N1→M2, so M···M is set by this span plus
    the two M–N bonds and the M–N–C angles. A ring FUSED at the back (benzimidazolate)
    grows the ligand footprint without touching it.

    CAN catch: a linker that genuinely lengthens the bridge (a 4,4'-bipyridyl-type
    spacer, an extended bis-azolate). CANNOT catch: a change in the M–N–C angles or
    in the framework topology — both also move M···M and neither is modelled here,
    since `ZIF_NODE_DIST` is a fixed input, not a solved geometry.
    """
    return float(np.linalg.norm(atoms[n3][1] - atoms[nh][1]))


def build_bimetallic_cluster(
    metal1: str, r1: float,
    metal2: str, r2: float,
    label: str,
    smiles: str = MEIMID_SMILES,
    bridge_smiles: str | None = None,
    solve_bridge: bool = False,
    roll: str = "inplane",
) -> list[tuple[str, np.ndarray]]:
    """Build M1(Im)₂ -- Im_bridge -- M2(Im)₂ cluster."""
    im, n3, _nh = build_linker(smiles)
    if solve_bridge:
        # A correctly placed bridge is an imidazolATE — strip its proton by chemistry,
        # not by the proximity heuristic the legacy placement leans on.
        br, br_n3, br_nh = build_linker(bridge_smiles or smiles, deprotonate_nh=True)
    else:
        br, br_n3, br_nh = build_linker(bridge_smiles) if bridge_smiles else (im, n3, _nh)

    m1_pos = np.array([-ZIF_NODE_DIST / 2, 0.0, 0.0])
    m2_pos = np.array([+ZIF_NODE_DIST / 2, 0.0, 0.0])
    bridge_dir = m2_pos - m1_pos
    bridge_dir /= np.linalg.norm(bridge_dir)

    all_atoms: list[tuple[str, np.ndarray]] = []
    all_atoms.append((metal1, m1_pos))
    all_atoms.append((metal2, m2_pos))

    if solve_bridge:
        bridge = place_bridge_ligand(br, br_n3, br_nh, m1_pos, m2_pos, r1, r2, roll)
    else:
        # Legacy placement: N3 → M1, ring oriented by centre of mass. Where the SECOND
        # nitrogen lands is an accident of the linker — see `place_bridge_ligand`.
        bridge_n3_pos = m1_pos + r1 * bridge_dir
        bridge = place_ligand_at(br, br_n3, bridge_n3_pos, bridge_dir)
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

    print(f"  {label}: {len(all_atoms)} atoms ({metal1} + {metal2} + 5×linker)")
    return all_atoms


def build_ce_graphene_cluster(smiles: str = MEIMID_SMILES) -> list[tuple[str, np.ndarray]]:
    """Build Ce(Im)₂ + coronene (MWCNT proxy) cluster."""
    im, n3, _nh = build_linker(smiles)

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


def deprotonate_metal_clashes(
    atoms: list[tuple[str, np.ndarray]], threshold: float = 1.3,
) -> tuple[list[tuple[str, np.ndarray]], int]:
    """Remove H atoms sitting within `threshold` Å of a metal.

    Root-cause fix (2026-06-05): the bridging 2-methylimidazole was placed by a
    single-anchor rotation (N3→M1), which left its OTHER (N–H) nitrogen facing M2
    with the H pointing straight INTO the metal (H···M ≈ 0.97 Å — physically
    impossible). In a real ZIF the bridge is a **deprotonated imidazolate** that
    coordinates both metals through its two ring N (no H on either). Dropping the
    clashing H restores that: the bare N coordinates M2 cleanly. Each removed H is
    a proton → the cluster charge drops by 1 per removal (caller updates charge).
    Returns (cleaned_atoms, n_removed)."""
    metals = [p for s, p in atoms if s in ("Cu", "Co", "Ce")]
    cleaned: list[tuple[str, np.ndarray]] = []
    removed = 0
    for s, p in atoms:
        if s == "H" and any(np.linalg.norm(p - m) < threshold for m in metals):
            removed += 1
            continue
        cleaned.append((s, p))
    return cleaned, removed


def write_xyz(atoms: list[tuple[str, np.ndarray]], path: Path, comment: str) -> None:
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, pos in atoms:
            fh.write(f"{sym:2s}  {pos[0]: 12.6f}  {pos[1]: 12.6f}  {pos[2]: 12.6f}\n")


CLASH_A = 0.8   # Å — below the shortest real bond here (N–H ≈ 1.01 Å)


def check_distances(atoms: list[tuple[str, np.ndarray]], label: str) -> float:
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
    if min_d < CLASH_A:
        print(f"  ⛔ Short contact in {label} — this geometry is not physical.")
    return float(min_d)


Z = {"H": 1, "C": 6, "N": 7, "Cu": 29, "Co": 27, "Ce": 58}


def report_electrons(atoms: list[tuple[str, np.ndarray]], charge: int) -> None:
    """Print the electron count downstream SCF scripts must match.

    24/24b hardcode CHARGE/SPIN for the shipped cluster; a linker or placement
    change moves the atom set, and an odd/even flip there silently makes the
    hardcoded spin wrong. Printing it is what keeps the two in step — there is no
    gate on this pair.
    """
    z = sum(Z[s] for s, _ in atoms)
    n_e = z - charge
    print(f"  Σ Z = {z} · at charge {charge:+d} → {n_e} electrons "
          f"({'even' if n_e % 2 == 0 else 'ODD'})")


PLANARITY_TOL_A = 0.15   # Å — see `bridge_out_of_plane`


def bridge_out_of_plane(atoms: list[tuple[str, np.ndarray]]) -> tuple[float, float] | None:
    """How far each metal sits from the BRIDGING ring's plane, in Å (None if no bridge).

    A coordinating nitrogen binds through a lone pair lying IN the ring plane, so an
    out-of-plane metal is not a stretched bond — it is a different bond, and it opens a
    direct metal-d ⇄ ring-π channel. Measured: 0.70 / 1.37 Å off-plane moved the FO-DFT
    coupling 24× while every other check in the pipeline stayed green.

    CAN catch a bridge rolled out of its own coordination plane, whatever put it there.
    CANNOT judge the M–N–C angles inside the plane, nor say that the in-plane geometry
    is right — it only refuses the failure mode that has actually bitten.
    """
    metals = [(s, p) for s, p in atoms if s in ("Cu", "Co", "Ce")]
    if len(metals) < 2:
        return None
    (_, m1p), (_, m2p) = metals[0], metals[1]
    ns = [p for s, p in atoms if s == "N"]
    pair = None
    for pa in ns:
        for pb in ns:
            if pa is pb:
                continue
            if (2.0 < np.linalg.norm(pa - pb) < 2.4
                    and np.linalg.norm(pa - m1p) < 2.3 and np.linalg.norm(pb - m2p) < 2.3):
                pair = (pa, pb)
                break
        if pair:
            break
    if pair is None:
        return None
    mid = (pair[0] + pair[1]) / 2.0
    ring = np.array([p for s, p in atoms if s != "H" and np.linalg.norm(p - mid) < 2.6])
    if len(ring) < 4:
        return None
    centre = ring.mean(axis=0)
    normal = np.linalg.svd(ring - centre)[2][-1]
    return (abs(float(np.dot(m1p - centre, normal))),
            abs(float(np.dot(m2p - centre, normal))))


def report_bridge(atoms: list[tuple[str, np.ndarray]], m1: str, m2: str) -> None:
    """Print each metal's nearest nitrogen — the bridge either closes or it does not."""
    metals = [(s, p) for s, p in atoms if s in ("Cu", "Co", "Ce")]
    ns = [p for s, p in atoms if s == "N"]
    for sym, mp in metals[:2]:
        ds = sorted(float(np.linalg.norm(p - mp)) for p in ns)
        print(f"  {sym}–N: " + " · ".join(f"{d:.3f}" for d in ds[:4]) + " Å")


def measure_spans() -> dict[str, float]:
    """Bridge N···N span for EVERY linker in the library, not just the one in use.

    Measuring the whole library keeps the cache a complete statement about it, so the
    committed file says the same thing whichever run wrote it last — a partial cache
    would make the claim depend on the last command line.
    """
    spans = {}
    for key in LINKERS:
        atoms, n3, nh = build_linker(LINKERS[key][0])
        spans[key] = round(bridge_span_nn(atoms, n3, nh), 4)
    return spans


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--linker", choices=sorted(LINKERS), default=REFERENCE_LINKER,
                    help="linker for every bridging and terminal position")
    ap.add_argument("--bridge-linker", choices=sorted(LINKERS), default=None,
                    help="swap ONLY the bridging linker (CHEM.35 is a claim about the "
                         "bridge, and a terminal swap crowds the coplanar sites)")
    ap.add_argument("--solve-bridge", action="store_true",
                    help="place the bridge so BOTH ring N reach their metal, instead of "
                         "orienting by centre of mass (changes the shipped geometry)")
    ap.add_argument("--roll", choices=("inplane", "perpendicular"), default="inplane",
                    help="bridge-ring roll about its N···N axis. `inplane` keeps both metals "
                         "in the ring plane (physical). `perpendicular` is the REFUSED probe "
                         "that measures how much the coupling rides on this choice")
    args = ap.parse_args()
    linker = args.linker
    bridge_key = args.bridge_linker or linker
    smiles, linker_label = LINKERS[linker]
    bridge_smiles, bridge_label = LINKERS[bridge_key]
    parts = ([] if linker == REFERENCE_LINKER else [linker])
    if args.bridge_linker and args.bridge_linker != linker:
        parts.append(f"br{args.bridge_linker}")
    if args.solve_bridge:
        parts.append("solved")
    if args.roll != "inplane":
        parts.append("perp")
    suffix = ("_" + "_".join(parts)) if parts else ""

    banner(f"L3b — building ZIF bimetallic cluster models "
           f"(terminals {linker_label} · bridge {bridge_label}"
           f"{' · solved placement' if args.solve_bridge else ''})")

    # The fixed ZIF_NODE_DIST is only legitimate while the bridge span is linker-
    # invariant — so measure it rather than assume it (see module docstring).
    spans = measure_spans()
    ref = spans[REFERENCE_LINKER]
    here = spans[bridge_key]
    delta = abs(here - ref)
    print(f"  bridge N···N span: {here:.4f} Å  (reference {REFERENCE_LINKER} "
          f"{ref:.4f} Å, Δ {delta:.4f} Å, tolerance {SPAN_TOLERANCE_A} Å)")
    if delta > SPAN_TOLERANCE_A:
        print(f"  ⛔ This linker moves the bridge span by {delta:.4f} Å, so the fixed "
              f"ZIF_NODE_DIST = {ZIF_NODE_DIST} Å is an UNSTATED assumption for it. "
              "Solve the node distance before comparing couplings.")
        return 1
    geom_out = DFT_CACHE / "zif_bridge_geometry.json"
    DFT_CACHE.mkdir(parents=True, exist_ok=True)
    geom_out.write_text(json.dumps({
        "method": "RDKit ETKDG (seed 42) + MMFF94s; span = distance between the two ring N",
        "purpose": "the premise under the FIXED ZIF_NODE_DIST — does a linker swap move the metals?",
        "zif_node_dist_A": ZIF_NODE_DIST,
        "span_tolerance_A": SPAN_TOLERANCE_A,
        "reference_linker": REFERENCE_LINKER,
        "bridge_span_nn_A": spans,
        "linkers": {k: v[1] for k, v in LINKERS.items()},
    }, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"  Wrote {geom_out.relative_to(REPO_ROOT)}")

    clashes: list[str] = []

    banner("1. Cu-Co cluster (T1 ↔ ZIF-67 node)")
    cu_co = build_bimetallic_cluster("Cu", BOND_CU_N, "Co", BOND_CO_N, "Cu-Co",
                                     smiles, bridge_smiles, args.solve_bridge, args.roll)
    cu_co, nrem = deprotonate_metal_clashes(cu_co)
    ntot = nrem + (1 if args.solve_bridge else 0)
    print(f"  bridge protons removed: {ntot} "
          f"({'chemistry' if args.solve_bridge else 'metal-clash heuristic'}) "
          f"→ cluster charge −{ntot}")
    report_electrons(cu_co, +1)
    report_bridge(cu_co, "Cu", "Co")
    oop = bridge_out_of_plane(cu_co)
    if oop is None:
        print("  ⛔ no bridging N pair reaches BOTH metals — this is not a bridged dimer")
        clashes.append("Cu-Co (no bridge)")
    else:
        print(f"  metals off the bridge-ring plane: Cu {oop[0]:.3f} · Co {oop[1]:.3f} Å "
              f"(tolerance {PLANARITY_TOL_A} Å)")
        if max(oop) > PLANARITY_TOL_A:
            print("  ⛔ the bridging N lone pairs do not point at their metals")
            clashes.append("Cu-Co (out-of-plane bridge)")
    if check_distances(cu_co, "Cu-Co") < CLASH_A:
        clashes.append("Cu-Co")
    p1 = LIGANDS_DIR / f"cu_co_zif{suffix}.xyz"
    write_xyz(cu_co, p1, f"Cu(L)2-L-Co(L)2 ZIF cluster; terminals {linker_label}; "
                         f"bridge {bridge_label}")
    print(f"  Wrote {p1.relative_to(REPO_ROOT)}")

    banner("2. Co-Ce cluster (ZIF-67 node ↔ Ce vacancy)")
    co_ce = build_bimetallic_cluster("Co", BOND_CO_N, "Ce", BOND_CE_N, "Co-Ce",
                                     smiles, bridge_smiles, args.solve_bridge, args.roll)
    co_ce, nrem = deprotonate_metal_clashes(co_ce)
    ntot = nrem + (1 if args.solve_bridge else 0)
    print(f"  bridge protons removed: {ntot} "
          f"({'chemistry' if args.solve_bridge else 'metal-clash heuristic'}) "
          f"→ cluster charge −{ntot}")
    report_electrons(co_ce, +1)
    report_bridge(co_ce, "Co", "Ce")
    oop = bridge_out_of_plane(co_ce)
    if oop is None:
        print("  ⛔ no bridging N pair reaches BOTH metals — this is not a bridged dimer")
        clashes.append("Co-Ce (no bridge)")
    else:
        print(f"  metals off the bridge-ring plane: Co {oop[0]:.3f} · Ce {oop[1]:.3f} Å "
              f"(tolerance {PLANARITY_TOL_A} Å)")
        if max(oop) > PLANARITY_TOL_A:
            print("  ⛔ the bridging N lone pairs do not point at their metals")
            clashes.append("Co-Ce (out-of-plane bridge)")
    if check_distances(co_ce, "Co-Ce") < CLASH_A:
        clashes.append("Co-Ce")
    p2 = LIGANDS_DIR / f"co_ce_zif{suffix}.xyz"
    write_xyz(co_ce, p2, f"Co(L)2-L-Ce(L)2 ZIF cluster; terminals {linker_label}; "
                         f"bridge {bridge_label}")
    print(f"  Wrote {p2.relative_to(REPO_ROOT)}")

    banner("3. Ce-graphene cluster (Ce ↔ MWCNT electrode)")
    ce_gr = build_ce_graphene_cluster(smiles)
    if check_distances(ce_gr, "Ce-graphene") < CLASH_A:
        clashes.append("Ce-graphene")
    p3 = LIGANDS_DIR / f"ce_graphene{suffix}.xyz"
    write_xyz(ce_gr, p3, f"Ce(L)2 + coronene (MWCNT proxy); L = {linker_label}")
    print(f"  Wrote {p3.relative_to(REPO_ROOT)}")

    if clashes:
        banner("⛔ Clashing geometry — do NOT run DFT on this")
        print("  Clusters with a contact below "
              f"{CLASH_A} Å: {', '.join(clashes)}. The files are written so they can be "
              "inspected, but a coupling computed on them is not a measurement.")
        return 1

    banner("✅ All 3 ZIF clusters built")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
