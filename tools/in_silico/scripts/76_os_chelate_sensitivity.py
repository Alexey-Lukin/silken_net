#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""C-min — how far the device Os couple moves when the bpy chelate the builder leaves open is closed (paper §2.3).

Why this exists: the shared builder (`lib/os_geometry`) places a rigid MMFF chelate whose own N···N (2.69–2.72 Å)
cannot meet the 78° bite at Os–N(bpy) 2.06 Å, so every osmium geometry of the pipeline realises Os–N(bpy)
2.091–2.099 Å at an 80.1–80.6° bite. The verdict on §2.3 (B′, delegated 2026-10-01 — the §2.3 line of
`paper/09_references.md`) keeps the distances a named assumption and lets a sensitivity number into Methods only
COMPUTED. This computes it on the device couple: the `21f` B3LYP pair — its own tier settings, imported — on the
same complex with the chelate CLOSED (`build_os_complex(close_chelate=True)`: N···N held at 2·2.06·sin 39°,
ring angles relaxed by MMFF94s, both targets realised or the build refuses), against the lock re-run of the
default pair.

Environment: the conda-lock (`silken_lock`). The base is the lock re-run of `21f`
(`cache/reproduction/lock_rerun_2026-10-01.json`); the recorded environment (PySCF 2.11.0) carries the PCM
ECP-radius defect (`75`), so a difference taken across the two would mix a cavity change into the number.
Refuses on another PySCF than the lock record's, and on a default geometry that is not, byte for byte, the
committed `ligands/os_dmbpy_meim_cl_full.xyz` the base was computed on.

CAN show: the shift of the vertical ΔE_red(III→II) of the dmbpy chloro couple at B3LYP/6-31G(d)+LANL2DZ(Os)/C-PCM
when its chelates go from the realised geometry to Os–N(bpy) 2.06 Å at 78°, per state and for the couple.
CANNOT show: (1) an optimised geometry — the closed chelate is still a rigid MMFF ligand placed onto ASSUMED
targets, so this prices the builder's open chelate, not the distance from a crystal or a minimum; (2) the other
members of the class — the aqua and bis-Im forms (`34`/`34b`), the substituent series (`21e`), the ωB97X tier:
the full C, which this number triggers only at ≥ 0.1 eV; (3) a ② difference — both of its members move, and
only their difference carries a conclusion.

Writes: tools/in_silico/cache/reproduction/os_chelate_sensitivity.json · ligands/os_dmbpy_meim_cl_closed.xyz
        (under `reproduction/`, not `dft/`: it ran under the lock, and every cache outside `reproduction/` is
        computed in the recorded environment — the partition the SI's S1 states)
Run:    ~/miniforge3/envs/silken_lock/bin/python tools/in_silico/scripts/76_os_chelate_sensitivity.py
Cost:   ≈ 27 min of SCF (the lock re-run of the default pair took 671.8 + 946.4 s), one job at a time.
"""
from __future__ import annotations

import datetime
import importlib.util
import json
import platform
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT
from lib.dft_utils import dft_singlepoint
from lib.os_geometry import BITE_DEG, DMBPY_SMILES, OS_N_BPY, build_os_complex, write_xyz
from lib.utils import banner

SI_DESCRIPTION = "Sensitivity of the device osmium couple to closing its bipyridine chelates onto the assumed bond length and bite angle."  # its row in the paper SI (72): English, no repo jargon

OUT = CACHE_DIR / "reproduction" / "os_chelate_sensitivity.json"
DEFAULT_XYZ = LIGANDS_DIR / "os_dmbpy_meim_cl_full.xyz"
CLOSED_XYZ = LIGANDS_DIR / "os_dmbpy_meim_cl_closed.xyz"
LOCK_RECORD = CACHE_DIR / "reproduction" / "lock_rerun_2026-10-01.json"
FULL_C_TRIGGER_EV = 0.1   # the delegated verdict's trigger on an absolute number (§2.3 line of 09_references)


def _tier_21f() -> tuple:
    """21f's own b3lyp tier (xc, basis_light, level_shift_open, out_name, conv_tol) — imported, never retyped."""
    spec = importlib.util.spec_from_file_location("s21f", Path(__file__).with_name("21f_dft_os_dimethyl.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.TIERS["b3lyp"]


def _xyz_body(atoms) -> list[str]:
    """The coordinate lines exactly as `write_xyz` prints them."""
    return [f"{s:2s}  {p[0]: 12.6f}  {p[1]: 12.6f}  {p[2]: 12.6f}" for s, p in atoms]


def _geometry(info: dict) -> dict:
    return {k: info[k] for k in ("os_n_bpy_A", "bite_deg", "min_interlig_A", "min_interlig_pair")}


def main() -> int:
    import pyscf
    import rdkit

    lock = json.loads(LOCK_RECORD.read_text(encoding="utf-8"))
    if pyscf.__version__ != lock["lock_env"]["versions"]["pyscf"]:
        sys.exit(f"PySCF {pyscf.__version__} is not the lock record's {lock['lock_env']['versions']['pyscf']} — "
                 f"the base was computed there; run in silken_lock")
    xc, basis_light, lshift, out_name, conv = _tier_21f()
    base = lock["files"][f"dft/{out_name}"]["per_field"]
    e2_base, e3_base = base["os2_plus.E_total_Ha"]["lock_rerun"], base["os3_plus.E_total_Ha"]["lock_rerun"]

    default, info_default = build_os_complex(bpy_smiles=DMBPY_SMILES)
    if _xyz_body(default) != DEFAULT_XYZ.read_text(encoding="utf-8").splitlines()[2:]:
        sys.exit(f"this environment builds a default geometry other than {DEFAULT_XYZ.name} — the base does not apply")
    closed, info_closed = build_os_complex(bpy_smiles=DMBPY_SMILES, close_chelate=True)
    write_xyz(closed, CLOSED_XYZ,
              "cis-[Os(4,4'-dimethyl-bpy)2(1-MeIm)Cl] programmatic octahedral, chelates closed (C-min)")
    banner(f"C-min — 21f tier '{xc}' on the closed chelate, PySCF {pyscf.__version__}")
    print(f"  Os–N(bpy) {info_default['os_n_bpy_A']} → {info_closed['os_n_bpy_A']} Å, "
          f"bite {info_default['bite_deg']} → {info_closed['bite_deg']}°")

    os2 = dft_singlepoint(closed, charge=1, spin=0, label="Os(II) dmbpy closed chelate",
                          xc=xc, basis_light=basis_light, conv_tol=conv)
    os3 = dft_singlepoint(closed, charge=2, spin=1, label="Os(III) dmbpy closed chelate",
                          xc=xc, basis_light=basis_light, conv_tol=conv, level_shift_open=lshift)
    if not (os2["converged"] and os3["converged"]):
        sys.exit("an SCF did not converge — no number is written")
    de_closed = (os2["E_total_Ha"] - os3["E_total_Ha"]) * HARTREE_TO_EV
    de_base = (e2_base - e3_base) * HARTREE_TO_EV
    shift = de_closed - de_base
    print(f"  ΔE_red(III→II) {de_base:+.4f} → {de_closed:+.4f} eV  (shift {shift * 1e3:+.1f} meV)")

    record = {
        "what": ("C-min: the device Os couple (21f, b3lyp tier) on its default geometry and with both bpy chelates "
                 "closed onto the builder's targets — the computed sensitivity of paper §2.3."),
        "date": datetime.date.today().isoformat(),
        "environment": {"pyscf": pyscf.__version__, "rdkit": rdkit.__version__,
                        "python": platform.python_version(), "machine": platform.machine()},
        "settings": f"21f tier '{xc}': {xc}/{basis_light}+LANL2DZ(Os), C-PCM, conv_tol {conv:g}, "
                    f"Os(III) level shift {lshift:g}",
        "targets": {"os_n_bpy_A": OS_N_BPY, "bite_deg": BITE_DEG},
        "geometry": {"default": _geometry(info_default), "closed": _geometry(info_closed),
                     "default_xyz": str(DEFAULT_XYZ.relative_to(REPO_ROOT)),
                     "closed_xyz": str(CLOSED_XYZ.relative_to(REPO_ROOT))},
        "base": {"source": str(LOCK_RECORD.relative_to(REPO_ROOT)), "os2_E_total_Ha": e2_base,
                 "os3_E_total_Ha": e3_base, "dE_red_III_to_II_eV": de_base},
        "closed": {"os2_plus": os2, "os3_plus": os3, "dE_red_III_to_II_eV": de_closed},
        "sensitivity": {
            "dE_red_shift_eV": shift,
            "os2_shift_eV": (os2["E_total_Ha"] - e2_base) * HARTREE_TO_EV,
            "os3_shift_eV": (os3["E_total_Ha"] - e3_base) * HARTREE_TO_EV,
            "full_C_trigger_eV": FULL_C_TRIGGER_EV,
            "full_C_triggered": abs(shift) >= FULL_C_TRIGGER_EV,
        },
    }
    OUT.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)} — full C {'TRIGGERED' if abs(shift) >= FULL_C_TRIGGER_EV else 'not triggered'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
