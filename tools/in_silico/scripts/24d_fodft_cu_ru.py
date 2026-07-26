#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""24d — FO-DFT coupling t_ij for the Cu–Ru ZIF hop (CHEM.32 rigour upgrade).

Same two-state Mulliken–Hush diabatisation as 24b (FO-DFT for Cu–Co), applied to the
Co→Ru-swapped cluster (`cu_ru_zif.xyz`, identical geometry). 24c's crude ΔSCF
energy-splitting gave a LARGE Cu–Ru splitting (ΔE ≈ 0.21 eV) whose magnitude the crude
method cannot be trusted on — exactly the reason 24b was needed for Cu–Co (there the
crude 0.00128 → FO-DFT 0.00546). This firms t_ij(Cu–Ru) by the rigorous route and reads
24c's crude value from cache for comparison.

  1. one UKS dimer SCF on cu_ru_zif (charge +1, spin 1 — Cu-Ru cluster, 253 e⁻);
  2. pick the two frontier MOs with the most Cu-d + Ru-d weight (donor/acceptor pair);
  3. localise that 2-orbital space (manual 2×2 Mulliken-Hush — lo.PM/lo.Boys crash on a
     PySCF lib.einsum bug) → one orbital on Cu, one on Ru;
  4. H_ab (= t_ij) is the off-diagonal Fock in the localised basis; diagonals = site energies.

Run:  mamba run -n silken_md python tools/in_silico/scripts/24d_fodft_cu_ru.py
Wall: ~10 min (one UKS dimer SCF).
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

OUT = DFT_CACHE / "cu_ru_fodft.json"
XYZ = LIGANDS_DIR / "cu_ru_zif.xyz"
CHARGE, SPIN = 1, 1                       # Co→Ru swap: Ru(lanl2dz)=16 val e⁻ → 253 e⁻ (odd) → doublet
BASIS_METALS = {"Cu": "lanl2dz", "Ru": "lanl2dz"}
ECP_METALS = {"Cu": "lanl2dz", "Ru": "lanl2dz"}


def crude_cu_ru_t_ij() -> float:
    """24c's crude Cu-Ru ΔSCF t_ij, read from cache at runtime — drift-proof (never a hardcoded copy)."""
    z = json.loads((DFT_CACHE / "cu_ru_coupling.json").read_text())
    return next(p["t_ij_eV"] for p in z["pairs"] if "CHEM.32" in p["label"])


def read_xyz(path: Path):
    lines = path.read_text().strip().split("\n")
    n = int(lines[0])
    return [(p[0], (float(p[1]), float(p[2]), float(p[3])))
            for p in (ln.split() for ln in lines[2:2 + n])]


def mo_metal_pop(mol, C, S, metal_idx):
    ao_atom = mol.ao_labels(fmt=None)
    rows = [i for i, lab in enumerate(ao_atom) if lab[0] in metal_idx]
    SC = S @ C
    return (C[rows, :] * SC[rows, :]).sum(axis=0)


def main() -> int:
    banner("FO-DFT coupling — Cu-Ru ZIF hop (two-state diabatisation, CHEM.32)")
    t0 = time.time()
    if not XYZ.exists():
        sys.exit(f"Missing {XYZ}. Build it first (24c).")
    atoms = read_xyz(XYZ)

    basis = dict(BASIS_METALS)
    basis["default"] = BASIS_LIGHT
    mol = gto.M(atom=atoms, basis=basis, ecp=dict(ECP_METALS),
                charge=CHARGE, spin=SPIN, unit="Angstrom")
    cu_idx = [i for i, a in enumerate(atoms) if a[0] == "Cu"]
    ru_idx = [i for i, a in enumerate(atoms) if a[0] == "Ru"]
    print(f"  {len(atoms)} atoms; Cu={cu_idx}, Ru={ru_idx}; charge={CHARGE} spin={SPIN}")

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
    C, eps = mf.mo_coeff[0], mf.mo_energy[0]
    nocc = int((mf.mo_occ[0] > 0).sum())

    lo_i, hi_i = max(0, nocc - 6), min(C.shape[1], nocc + 4)
    pop_cu = mo_metal_pop(mol, C, S, cu_idx)
    pop_ru = mo_metal_pop(mol, C, S, ru_idx)
    cand = sorted(range(lo_i, hi_i), key=lambda i: -(pop_cu[i] + pop_ru[i]))[:2]
    i, j = sorted(cand)
    print(f"  frontier window MO[{lo_i}:{hi_i}], nocc(α)={nocc}")
    for k in (i, j):
        print(f"    MO {k}: ε={eps[k] * HARTREE_TO_EV:+.3f} eV  pop(Cu)={pop_cu[k]:.2f} pop(Ru)={pop_ru[k]:.2f}")

    ao_atom = mol.ao_labels(fmt=None)
    rows_cu = [a for a, lab in enumerate(ao_atom) if lab[0] in cu_idx]
    SC = S @ C
    mos = [i, j]
    Pcu = np.array([[0.5 * sum(C[r, mos[x]] * SC[r, mos[y]] + C[r, mos[y]] * SC[r, mos[x]]
                               for r in rows_cu) for y in range(2)] for x in range(2)])
    _, R = np.linalg.eigh(Pcu)
    Cloc = C[:, mos] @ R
    Floc = R.T @ np.diag([eps[i], eps[j]]) @ R
    t_ij = abs(Floc[0, 1]) * HARTREE_TO_EV
    dG_site = abs(Floc[0, 0] - Floc[1, 1]) * HARTREE_TO_EV
    p_cu_loc = mo_metal_pop(mol, Cloc, S, cu_idx)
    p_ru_loc = mo_metal_pop(mol, Cloc, S, ru_idx)

    banner("FO-DFT coupling result — Cu-Ru")
    print(f"  localised orbital 0: pop(Cu)={p_cu_loc[0]:.2f} pop(Ru)={p_ru_loc[0]:.2f}")
    print(f"  localised orbital 1: pop(Cu)={p_cu_loc[1]:.2f} pop(Ru)={p_ru_loc[1]:.2f}")
    crude = crude_cu_ru_t_ij()
    print(f"  |t_ij| (FO-DFT)  = {t_ij:.5f} eV   (24c crude ΔSCF = {crude:.5f} eV, from cu_ru_coupling.json)")
    print(f"  site-energy gap  = {dG_site:.4f} eV   (≈ |ΔG| for the hop)")
    localised = (max(p_cu_loc[0], p_cu_loc[1]) > 0.3 and max(p_ru_loc[0], p_ru_loc[1]) > 0.3)
    physical = (1e-5 < t_ij < 1.0) and localised
    print(f"  localised onto distinct metals: {localised} · |t_ij| in 1e-5–1 eV: {1e-5 < t_ij < 1.0}")
    print(f"  → {'✅ physical coupling' if physical else '⚠️ inspect — non-localised or out-of-band'}")

    OUT.write_text(json.dumps({
        "method": "FO-DFT two-state diabatisation (single UKS dimer SCF, manual 2×2 Mulliken-Hush "
                  "population diabatisation of the 2 metal-d frontier MOs, off-diagonal Fock = t_ij); "
                  "B3LYP/6-31G(d)+LANL2DZ; Co→Ru @identical geom",
        "pair": "Cu-Ru (CHEM.32, Co→Ru swap)",
        "t_ij_eV": round(t_ij, 6),
        "t_ij_crude_24c_eV": round(crude, 6),
        "site_energy_gap_eV": round(dG_site, 4),
        "frontier_MOs": [int(i), int(j)],
        "localised": bool(localised),
        "physically_reasonable": bool(physical),
        "caveat": "fixed-geom (Co→Ru @identical coords) isolates 4d-diffuseness; real Ru-N longer → upper bound",
        "wall_seconds": round(time.time() - t0, 1),
    }, indent=2))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
