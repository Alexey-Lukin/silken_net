#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""L3 — Os mediator on the REAL 4,4'-dimethyl-bpy ligand (OS-RECOMPUTE 2026-06-17).

The verified device mediator is Zafar 2012's [Os(4,4'-dimethyl-2,2'-bipyridine)₂(PVI)Cl]⁺
(E°' = 21 mV vs Ag/AgCl 0.1 M KCl = +309 mV vs NHE), NOT the plain-bpy model that scripts
21b/21d computed. The 4,4'-dimethyl groups are weak donors (σ_para = −0.17) → they raise the
Os(III) LUMO → make the raw cascade slightly more uphill (the "substituent" axis the ② gap
decomposition did not separate). This script recomputes the Os(II)/Os(III) couple on the
dimethyl complex at two tiers, replacing the plain-bpy numbers in the canon (founder: full
dimethyl swap):

  b3lyp  (B5) → B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM  → os_complex.json   (SOLE owner; feeds 22 / comparison)
  wb97x  (B1) → ωB97X/def2-TZVP+LANL2DZ(Os)+C-PCM → os_complex_wb97xd_dmbpy.json (feeds the
                 adiabatic ΔSCF generator: EA_Os3(dmbpy) = E(OsII) − E(OsIII))

Geometry = the shared programmatic octahedron (lib.os_geometry.build_os_complex), so this is
the dimethyl twin of 21b/21d with no duplicated geometry code. The plain-bpy 21b/21d stay as
the parent reference (π-backbonding demonstration; superseded as the device baseline).

Discipline (in-silico skill): no density_fit for Os; level_shift=0.3 on the Os(III) UKS
doublet (read E_total, not LUMO, when shifted); DFT jobs sequential — do NOT run a second
heavy job on the same CPU.

Run:  mamba run -n silken_md python tools/in_silico/scripts/21f_dft_os_dimethyl.py b3lyp
      mamba run -n silken_md python tools/in_silico/scripts/21f_dft_os_dimethyl.py wb97x
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, OS_DEVICE_MEDIATOR_LIGAND, REPO_ROOT
from lib.dft_utils import dft_singlepoint
from lib.os_geometry import DMBPY_SMILES, build_os_complex, write_xyz
from lib.utils import banner

TIERS = {
    # tier: (xc, basis_light, level_shift_open, output_json, conv_tol)
    "b3lyp": ("b3lyp", "6-31g(d)", 0.0, "os_complex.json", 1e-6),
    "wb97x": ("wb97x", "def2-tzvp", 0.3, "os_complex_wb97xd_dmbpy.json", 1e-6),
}
FADH2_HOMO_B3LYP_EV = -5.137   # dft/lumiflavin.json red (cascade donor, B3LYP) — for the Koopmans note


def main(argv) -> int:
    tier = argv[1] if len(argv) > 1 else "b3lyp"
    if tier not in TIERS:
        sys.exit(f"unknown tier {tier!r}; choose: {', '.join(TIERS)}")
    xc, basis_light, lshift, out_name, conv = TIERS[tier]
    out = DFT_CACHE / out_name

    banner(f"OS-RECOMPUTE dimethyl mediator — tier {tier} ({xc.upper()}/{basis_light})")
    atoms, info = build_os_complex(bpy_smiles=DMBPY_SMILES)
    print(f"  geometry: {info['n_atoms']} atoms, min {info['min_contact_A']} Å "
          f"({info['min_pair']}), min-interlig {info['min_interlig_A']} Å, "
          f"Os-coord {info['os_coord_distances_A']}")
    write_xyz(atoms, LIGANDS_DIR / "os_dmbpy_meim_cl_full.xyz",
              "cis-[Os(4,4'-dimethyl-bpy)2(1-MeIm)Cl] programmatic octahedral (OS-RECOMPUTE)")

    # Os(II) closed-shell (+1), Os(III) doublet (+2). level_shift only on the open shell.
    os2 = dft_singlepoint(atoms, charge=1, spin=0, label=f"Os(II) dmbpy ({xc})",
                          xc=xc, basis_light=basis_light, conv_tol=conv)
    print(f"  Os(II)  E={os2['E_total_Ha']:.6f} Ha  HOMO={os2['HOMO_eV']:.3f}  "
          f"LUMO={os2['LUMO_eV']:.3f} eV  ({os2['wall_seconds']}s, conv={os2['converged']})")
    os3 = dft_singlepoint(atoms, charge=2, spin=1, label=f"Os(III) dmbpy ({xc})",
                          xc=xc, basis_light=basis_light, conv_tol=conv, level_shift_open=lshift)
    print(f"  Os(III) E={os3['E_total_Ha']:.6f} Ha  HOMO={os3['HOMO_eV']:.3f}  "
          f"LUMO={os3['LUMO_eV']:.3f} eV  ({os3['wall_seconds']}s, conv={os3['converged']})")

    # EA_Os3 = E(OsII) − E(OsIII): the quantity the adiabatic ΔSCF generator consumes.
    dE_red = (os2["E_total_Ha"] - os3["E_total_Ha"]) * HARTREE_TO_EV
    cascade_koopmans = FADH2_HOMO_B3LYP_EV - os3["LUMO_eV"]   # B3LYP-scale orbital offset only
    print(f"  ΔE_red(III→II) = {dE_red:+.4f} eV   "
          f"(Koopmans cascadeΔ vs B3LYP FADH₂ = {cascade_koopmans:+.4f} eV)")

    results = {
        "method": f"{xc.upper()}/{basis_light}+LANL2DZ(Os)+C-PCM(water,C-PCM)",
        "model_note": ("REAL device mediator cis-[Os(4,4'-dimethyl-bpy)2(1-MeIm)Cl]^n+ "
                       "(Zafar 2012 +309 mV vs NHE). Supersedes the plain-bpy 21b/21d as the "
                       "device baseline; plain-bpy retained as the parent π-backbonding reference."),
        "ligand": OS_DEVICE_MEDIATOR_LIGAND,
        "os2_plus": os2,
        "os3_plus": os3,
        "dE_red_III_to_II_eV": round(dE_red, 4),
        "EA_Os3_eV": round(-dE_red, 4),   # reduction Os(III)+e⁻→Os(II) energy release (= −ΔE_red)
    }
    out.write_text(json.dumps(results, indent=2), encoding="utf-8")
    banner(f"✅ saved {out.relative_to(REPO_ROOT)}")
    if tier == "wb97x":
        print("  → next: B2 adiabatic ΔSCF generator (IP_adiab(FAD) − EA_Os3(dmbpy))")
    else:
        print("  → next: re-run 22_compare_homo_lumo.py to refresh comparison.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
