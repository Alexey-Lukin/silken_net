#!/usr/bin/env python
"""
L3 — ωB97X ΔSCF cross-check of the ② mediator speciation (chloro → aqua → bis-Im).

The ② result (script 34, B3LYP) is that replacing the chloro ligand by the active
6th ligand shifts the Os(III/II) redox energy by ~0.3–0.5 eV (aqua > bis-Im > chloro
as acceptors). A reviewer will ask: is that SPECIATION trend an artifact of B3LYP, or
functional-robust? This re-runs the three forms' vertical **ΔSCF ΔE_red = E(Os II) −
E(Os III)** at the range-separated **ωB97X** functional (same 6-31G(d)+LANL2DZ basis +
C-PCM, same programmatic geometries) and compares the speciation shifts to B3LYP.

ΔSCF (total-energy difference), NOT orbital energies — ωB97X Koopmans LUMOs are poor
redox proxies (in-silico skill gotcha), but the ΔSCF ΔE_red is valid. So this checks
the speciation TREND at the ΔSCF level across two functionals.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, REPO_ROOT
from lib.dft_utils import dft_singlepoint
from lib.os_geometry import BPY_SMILES, DMBPY_SMILES, MEIM_SMILES, WATER_SMILES, build_os_complex
from lib.utils import banner

OUT = DFT_CACHE / "wb97x_speciation.json"
BPY = BPY_SMILES   # parent bpy; --dimethyl (OS-RECOMPUTE) → real device 4,4'-dimethyl-bpy + separate cache

# (name, axial spec, axial_twists, q_os2, q_os3) — chloro is a **+1/+2** couple (the
# anionic Cl⁻ removes one charge); aqua + bis-Im are **+2/+3** (neutral 6th ligand). The
# differing couple charge IS part of the speciation physics, not a confound. Geometries
# validated in script 34; chloro = the ①/k0 parent.
FORMS = [
    ("chloro", (("ligand", MEIM_SMILES, "N"), ("cl",)), (0.0, 0.0), 1, 2),
    ("aqua",   (("ligand", MEIM_SMILES, "N"), ("ligand", WATER_SMILES, "O")), (0.0, 0.0), 2, 3),
    ("bisim",  (("ligand", MEIM_SMILES, "N"), ("ligand", MEIM_SMILES, "N")), (45.0, 30.0), 2, 3),
]


def run_form(name, axial, twists, q2, q3):
    atoms, info = build_os_complex(bpy_smiles=BPY, axial=axial, axial_twists=twists)
    banner(f"ωB97X {name} — {info['n_atoms']} atoms, min-interlig {info['min_interlig_A']} Å, couple +{q2}/+{q3}")
    os2 = dft_singlepoint(atoms, charge=q2, spin=0, label=f"Os(II) {name}", xc="wb97x")
    print(f"  Os(II)  E={os2['E_total_Ha']:.6f} Ha ({os2['wall_seconds']}s, conv={os2['converged']})")
    os3 = dft_singlepoint(atoms, charge=q3, spin=1, label=f"Os(III) {name}", xc="wb97x",
                          level_shift_open=0.3)
    print(f"  Os(III) E={os3['E_total_Ha']:.6f} Ha ({os3['wall_seconds']}s, conv={os3['converged']})")
    dE_red = (os2["E_total_Ha"] - os3["E_total_Ha"]) * HARTREE_TO_EV
    print(f"  ΔE_red(III→II) = {dE_red:+.4f} eV")
    return {
        "name": name, "n_atoms": os2["n_atoms"],
        "dE_red_eV": round(dE_red, 4),
        "converged": os2["converged"] and os3["converged"],
        "E_os2_Ha": os2["E_total_Ha"], "E_os3_Ha": os3["E_total_Ha"],
    }


def main(argv) -> int:
    global BPY, OUT
    if "--dimethyl" in argv:   # OS-RECOMPUTE: real device mediator + separate cache
        BPY = DMBPY_SMILES
        OUT = DFT_CACHE / "wb97x_speciation_dmbpy.json"
    banner("② speciation — ωB97X ΔSCF cross-check (chloro → aqua → bis-Im)")
    t0 = time.time()
    results = [run_form(*f) for f in FORMS]

    banner("Speciation shifts vs chloro (ωB97X ΔSCF) — compare to B3LYP +0.51 (aqua) / +0.30 (bis-Im)")
    chloro = next(r for r in results if r["name"] == "chloro")
    for r in results:
        r["shift_vs_chloro_eV"] = round(r["dE_red_eV"] - chloro["dE_red_eV"], 4)
        print(f"  {r['name']:>7s}: ΔE_red {r['dE_red_eV']:+.4f}  shift {r['shift_vs_chloro_eV']:+.4f} eV")

    payload = {
        "method": "ωB97X/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF ΔE_red; cross-check of the "
                  "B3LYP ② speciation trend (script 34). Same programmatic geometries.",
        "note": "ΔSCF total-energy difference (ωB97X Koopmans LUMOs are unreliable); tests whether "
                "the aqua > bis-Im > chloro speciation trend is functional-robust.",
        "forms": results,
        "wall_seconds": round(time.time() - t0, 1),
    }
    DFT_CACHE.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, indent=2))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
