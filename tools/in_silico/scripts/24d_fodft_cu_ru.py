#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""24d — FO-DFT coupling t_ij for the Cu–Ru ZIF hop (CHEM.32 rigour upgrade).

Same two-state orbital diabatisation as 24b (the FO-DFT label for Cu–Co), applied to the
Co→Ru-swapped cluster (`cu_ru_zif.xyz`, identical geometry). 24c's crude ΔSCF
energy-splitting gave a LARGE Cu–Ru splitting (ΔE ≈ 0.21 eV) whose magnitude the crude
method cannot be trusted on — exactly the reason 24b was needed for Cu–Co (there the
crude 0.00128 → FO-DFT 0.001475 once its SCF converged, 2026-10-31). ⚠️ RESULT: it did NOT firm anything — the rigorous route came out non-physical too (t_ij 0.113 eV polished, 0.105 at the old SCF stop,
frontier MOs all-Ru with no Cu-d partner), i.e. a SECOND negative rather than a closure. The Ru
'double-whammy' t_ij boost stays an unconfirmed hypothesis, moved to a CDFT capstone (00_07 CHEM.32).
This script attempts to firm t_ij(Cu–Ru) by the rigorous route and reads
24c's crude value from cache for comparison.

  1. one UKS dimer SCF on cu_ru_zif (charge +1, spin 1 — Cu-Ru cluster, 253 e⁻), through 24b's `converge` — its tolerances,
     its unshifted polish and its stability check;
  2. pick, in 24b's window, the two α MOs with the largest Cu + Ru Mulliken population (24b's `couple`);
  3. localise that 2-orbital space (manual 2×2 population localisation — lo.PM/lo.Boys crash on a
     PySCF lib.einsum bug) → one orbital on Cu, one on Ru;
  4. H_ab (= t_ij) is the off-diagonal Fock in the localised basis; diagonals = site energies.

Run:  mamba run -n silken_md python tools/in_silico/scripts/24d_fodft_cu_ru.py
Wall: ~10 min (one UKS dimer SCF).
"""
from __future__ import annotations

import importlib.util
import json
import sys
import time
from pathlib import Path

from pyscf import gto

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import BASIS_LIGHT, DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT
from lib.utils import banner

_spec = importlib.util.spec_from_file_location("s24b", Path(__file__).resolve().parent / "24b_fodft_coupling.py")
s24b = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(s24b)

SI_DESCRIPTION = "24d — FO-DFT coupling t_ij for the Cu–Ru ZIF hop (rigour check of 24c)."  # its row in the paper SI (72): English, no repo jargon

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

    crude = crude_cu_ru_t_ij()                       # read before the SCF: a missing cache dies in seconds, not hours
    mf, scf = s24b.converge(mol)                                 # the ONE home of the SCF (24b's defaults)
    print(f"  internal stability of the UKS solution: "
          f"{'stable' if scf['stable_internal'] else 'UNSTABLE — a lower solution exists'}")
    print(f"  dimer SCF: E={scf['E_scf_Ha']:.8f} Ha, converged={scf['scf_converged']}, Newton rescue={scf['newton_rescue']}, "
          f"polish {scf['polish_cycles']} cycles to |g|={scf['orbital_grad_norm_Ha']:.1e} Ha, "
          f"<S²>={scf['S2']:.3f} (pure {SPIN / 2 * (SPIN / 2 + 1):.3f})")

    rec = s24b.couple(mol, mf, cu_idx, ru_idx, partner="Ru")   # the ONE home of the diabatisation
    t_ij, dG_site = rec["t_ij_eV"], rec["site_energy_gap_eV"]
    resolution = scf["orbital_grad_norm_Ha"] * HARTREE_TO_EV / t_ij
    print(f"  frontier window MO[{rec['window'][0]}:{rec['window'][1]}], nocc(α)={rec['nocc_alpha']}; picked "
          + " · ".join(f"HOMO{k:+d}" for k in rec["picked_rel_HOMO"]))
    for k, e, pc, pr in zip(rec["picked_MOs"], rec["eps_picked_eV"], rec["pop_cu_picked"], rec["pop_partner_picked"], strict=True):
        print(f"    MO {k}: ε={e:+.3f} eV  pop(Cu)={pc:.2f} pop(Ru)={pr:.2f}")

    banner("FO-DFT coupling result — Cu-Ru")
    for k in range(2):
        print(f"  localised orbital {k}: pop(Cu)={rec['loc_pop_cu'][k]:.2f} pop(Ru)={rec['loc_pop_partner'][k]:.2f}")
    print(f"  |t_ij| (FO-DFT)  = {t_ij:.6f} eV   (24c crude ΔSCF = {crude:.5f} eV, from cu_ru_coupling.json; "
          f"SCF resolution |g|/t_ij = {resolution:.1e})")
    print(f"  site-energy gap  = {dG_site:.4f} eV   (diagonal Fock difference — not a free energy, sign not fixed)")
    print(f"  localised onto distinct metals: {rec['localised']} · |t_ij| in 1e-5–1 eV: {1e-5 < t_ij < 1.0}")
    print(f"  → {'✅ physical coupling' if rec['physically_reasonable'] else '⚠️ inspect — non-localised or out-of-band'}")

    OUT.write_text(json.dumps({
        "method": "FO-DFT-labelled two-state diabatisation, 24b's `couple` (single UKS dimer SCF; the 2 α MOs with the "
                  "largest Cu + Ru Mulliken population in the window HOMO−5 … LUMO+3, manual 2×2 population localisation, "
                  "off-diagonal Fock = t_ij); B3LYP/6-31G(d)+LANL2DZ; Co→Ru @identical geom",
        "pair": "Cu-Ru (CHEM.32, Co→Ru swap)",
        "t_ij_eV": round(t_ij, 6),
        "t_ij_crude_24c_eV": round(crude, 6),
        "site_energy_gap_eV": round(dG_site, 4),
        "frontier_MOs": rec["picked_MOs"],
        "localised": rec["localised"],
        "physically_reasonable": rec["physically_reasonable"],
        "caveat": "fixed-geom (Co→Ru @identical coords) isolates 4d-diffuseness; real Ru-N longer → upper bound",
        # the record the flag cannot replace (in-silico §When Modifying #49)
        "charge": CHARGE, "spin_2S": SPIN, "n_electrons": mol.nelectron,
        **scf, "grad_norm_over_t_ij": float(f"{resolution:.2e}"), "S2_pure": SPIN / 2 * (SPIN / 2 + 1),
        **{k: rec[k] for k in ("nocc_alpha", "window", "picked_rel_HOMO", "pick_at_window_edge")},
        "eps_picked_eV": [round(e, 4) for e in rec["eps_picked_eV"]],
        "pop_cu_picked": [round(x, 3) for x in rec["pop_cu_picked"]],
        "pop_ru_picked": [round(x, 3) for x in rec["pop_partner_picked"]],
        "loc_pop_cu": [round(x, 3) for x in rec["loc_pop_cu"]],
        "loc_pop_ru": [round(x, 3) for x in rec["loc_pop_partner"]],
        "site_energy_cu_minus_ru_eV": round(rec["site_energy_cu_minus_partner_eV"], 4),
        "localisation_2theta_deg": round(rec["localisation_2theta_deg"], 2),
        "wall_seconds": round(time.time() - t0, 1),
    }, indent=2))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
