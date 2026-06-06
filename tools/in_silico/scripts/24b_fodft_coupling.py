#!/usr/bin/env python
"""
L3b — fragment-orbital (FO-DFT-style) electronic coupling t_ij for the Cu-Co ZIF hop.

Rigorous upgrade of script 24's crude coupling (which relied on finding two charge-
localised SCF minima by initial-guess biasing, with a 0.05 eV fallback when they
collapsed to the same state). Here we do a single dimer SCF and extract the diabatic
coupling by **two-state diabatisation**:

  1. one UKS dimer SCF on the clash-free Cu-Co cluster (script 23 geometry);
  2. pick the two frontier MOs (near the SOMO/HOMO) carrying the most Cu-d + Co-d
     character — the donor/acceptor pair (or their bonding/antibonding combination);
  3. **localise** that 2-orbital space (manual 2×2 Mulliken-Hush — diagonalise the Cu-projected
     population matrix; lo.PM/lo.Boys crash on a PySCF lib.einsum bug) → one orbital on Cu, one on Co;
  4. H_ab (= t_ij) is the off-diagonal of the Fock matrix in that localised basis;
     the diagonals are the site energies (their difference is the driving-force ΔG).

This is the standard "fragment orbitals from the dimer" route — no fragment-basis
counterpoise bookkeeping, no SCF-state biasing. It is an electron-coupling estimate,
not a CDFT diabatic state (that remains the capstone). Diagnostics (the chosen MOs,
their metal populations, the localisation) are printed so the result is auditable; a
physicality band flags a non-sensical coupling honestly (cf. the script-29 λ closure).

NB: only the Cu-Co bottleneck is recomputed (script 24 found it rate-limiting); the
other two hops are far from limiting and keep their script-24 ΔSCF t_ij.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
from pyscf import dft, gto

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import BASIS_LIGHT, DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT
from lib.utils import banner

OUT = DFT_CACHE / "fodft_coupling.json"
XYZ = LIGANDS_DIR / "cu_co_zif.xyz"
CHARGE, SPIN = 1, 2                       # clash-free Cu-Co cluster (script 23/24)
BASIS_METALS = {"Cu": "lanl2dz", "Co": "lanl2dz"}
ECP_METALS = {"Cu": "lanl2dz", "Co": "lanl2dz"}


def crude_cu_co_t_ij() -> float:
    """script-24's crude Cu-Co ΔSCF t_ij, read from its cache at runtime — drift-proof (mirrors the
    SSOT `zif_hopping.json`, never a hardcoded copy that silently diverges if script 24 is re-run)."""
    z = json.loads((DFT_CACHE / "zif_hopping.json").read_text())
    return next(p["t_ij_eV"] for p in z["pairs"] if {p["metal1"], p["metal2"]} == {"Cu", "Co"})


def read_xyz(path: Path):
    lines = path.read_text().strip().split("\n")
    n = int(lines[0])
    return [(p[0], (float(p[1]), float(p[2]), float(p[3])))
            for p in (ln.split() for ln in lines[2:2 + n])]


def mo_metal_pop(mol, C, S, metal_idx):
    """Per-MO Mulliken population on the given atom indices (rows of C are AOs)."""
    ao_atom = mol.ao_labels(fmt=None)              # (atom_id, symbol, ...) per AO
    rows = [i for i, lab in enumerate(ao_atom) if lab[0] in metal_idx]
    SC = S @ C
    return (C[rows, :] * SC[rows, :]).sum(axis=0)  # pop_i on those atoms, per MO


def main() -> int:
    banner("FO-DFT coupling — Cu-Co ZIF hop (two-state diabatisation)")
    t0 = time.time()
    if not XYZ.exists():
        sys.exit(f"Missing {XYZ}. Run script 23 first.")
    atoms = read_xyz(XYZ)

    basis = dict(BASIS_METALS)
    basis["default"] = BASIS_LIGHT
    mol = gto.M(atom=atoms, basis=basis, ecp=dict(ECP_METALS),
                charge=CHARGE, spin=SPIN, unit="Angstrom")
    cu_idx = [i for i, a in enumerate(atoms) if a[0] == "Cu"]
    co_idx = [i for i, a in enumerate(atoms) if a[0] == "Co"]
    print(f"  {len(atoms)} atoms; Cu={cu_idx}, Co={co_idx}; charge={CHARGE} spin={SPIN}")

    mf = dft.UKS(mol)
    mf.xc = "b3lyp"
    mf.conv_tol = 1e-6
    mf.max_cycle = 300
    mf.level_shift = 0.3
    mf.verbose = 0
    e_scf = mf.kernel()
    if not mf.converged:
        mf = mf.newton()
        mf.max_cycle = 100
        e_scf = mf.kernel()
    print(f"  dimer SCF: E={e_scf:.6f} Ha, converged={mf.converged}")

    S = mf.get_ovlp()
    # work in the alpha channel (the open-shell / hole-transfer channel)
    C, eps = mf.mo_coeff[0], mf.mo_energy[0]
    nocc = int((mf.mo_occ[0] > 0).sum())

    # frontier window around the SOMO/HOMO; pick the 2 MOs with the most Cu+Co metal weight
    lo_i, hi_i = max(0, nocc - 6), min(C.shape[1], nocc + 4)
    pop_cu = mo_metal_pop(mol, C, S, cu_idx)
    pop_co = mo_metal_pop(mol, C, S, co_idx)
    cand = sorted(range(lo_i, hi_i), key=lambda i: -(pop_cu[i] + pop_co[i]))[:2]
    i, j = sorted(cand)
    print(f"  frontier window MO[{lo_i}:{hi_i}], nocc(α)={nocc}")
    for k in (i, j):
        print(f"    MO {k}: ε={eps[k] * HARTREE_TO_EV:+.3f} eV  pop(Cu)={pop_cu[k]:.2f} pop(Co)={pop_co[k]:.2f}")

    # localise the 2-orbital space → one orbital on Cu, one on Co. lo.PM / lo.Boys crash here on a
    # PySCF lib.einsum version bug, so do the 2×2 diabatisation by hand: diagonalise the Cu-projected
    # population matrix in the {i,j} MO basis → rotation R that localises one orbital on Cu, the other
    # off-Cu (= Co); H_ab = off-diagonal of the Fock in that basis (F is diagonal = ε in the MO basis,
    # MOs orthonormal, so Floc = Rᵀ·diag(εᵢ,εⱼ)·R — Mulliken-Hush-style population diabatisation).
    ao_atom = mol.ao_labels(fmt=None)
    rows_cu = [a for a, lab in enumerate(ao_atom) if lab[0] in cu_idx]
    SC = S @ C
    mos = [i, j]
    Pcu = np.array([[0.5 * sum(C[r, mos[x]] * SC[r, mos[y]] + C[r, mos[y]] * SC[r, mos[x]]
                               for r in rows_cu) for y in range(2)] for x in range(2)])
    _, R = np.linalg.eigh(Pcu)
    Cloc = C[:, mos] @ R
    Floc = R.T @ np.diag([eps[i], eps[j]]) @ R       # 2×2 Fock in the localised (diabatic) basis (Ha)
    t_ij = abs(Floc[0, 1]) * HARTREE_TO_EV
    dG_site = abs(Floc[0, 0] - Floc[1, 1]) * HARTREE_TO_EV
    p_cu_loc = mo_metal_pop(mol, Cloc, S, cu_idx)
    p_co_loc = mo_metal_pop(mol, Cloc, S, co_idx)

    banner("FO-DFT coupling result")
    print(f"  localised orbital 0: pop(Cu)={p_cu_loc[0]:.2f} pop(Co)={p_co_loc[0]:.2f}")
    print(f"  localised orbital 1: pop(Cu)={p_cu_loc[1]:.2f} pop(Co)={p_co_loc[1]:.2f}")
    crude = crude_cu_co_t_ij()
    print(f"  |t_ij| (FO-DFT)  = {t_ij:.5f} eV   (script-24 crude = {crude:.5f} eV, loaded from zif_hopping.json)")
    print(f"  site-energy gap  = {dG_site:.4f} eV   (≈ |ΔG| for the hop)")
    localised = (max(p_cu_loc[0], p_cu_loc[1]) > 0.3 and max(p_co_loc[0], p_co_loc[1]) > 0.3)
    physical = (1e-5 < t_ij < 1.0) and localised
    print(f"  localised onto distinct metals: {localised} · |t_ij| in 1e-5–1 eV: {1e-5 < t_ij < 1.0}")
    print(f"  → {'✅ physical coupling' if physical else '⚠️ inspect — non-localised or out-of-band'}")

    OUT.write_text(json.dumps({
        "method": "FO-DFT two-state diabatisation (single UKS dimer SCF, manual 2×2 Mulliken-Hush "
                  "population diabatisation of the 2 metal-d frontier MOs, off-diagonal Fock = t_ij); "
                  "B3LYP/6-31G(d)+LANL2DZ",
        "pair": "Cu-Co (rate-limiting hop)",
        "t_ij_eV": round(t_ij, 6),
        "t_ij_crude_script24_eV": round(crude, 6),
        "site_energy_gap_eV": round(dG_site, 4),
        "frontier_MOs": [int(i), int(j)],
        "localised": bool(localised),
        "physically_reasonable": bool(physical),
        "wall_seconds": round(time.time() - t0, 1),
    }, indent=2))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
