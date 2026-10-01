#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Attribution of the conda-lock gap on metal-in-PCM couples to the PySCF 2.13.0 PCM ECP-radius fix.

Why this exists: `cache/reproduction/lock_rerun_2026-10-01.json` measured that the B3LYP osmium couple
of `21f` does not reproduce under the conda-lock (PySCF 2.13.1) while the flavin chain (`20` + `32`)
and the gas-phase FO-DFT coupling (`24b`) do. PySCF 2.13.0 lists among its fixes «A bug where PCM
assigned incorrect radii to ECP atoms» (CHANGELOG; pyscf/pyscf PR #3159, merge commit 79e82d965f):
up to 2.12 `solvent/pcm.gen_surface` placed each atom's surface points on its ELEMENT radius but took
the switching-function radius `R_J` at `mol.atom_charges()` — the nuclear charge minus the ECP core —
so an Os atom under LANL2DZ (Z_eff = 16) was switched with the radius of sulfur. This script asks
whether that one change is the whole gap.

What it runs (sequentially — in-silico Critical Rule #3), all through `lib.dft_utils.dft_singlepoint`:
  device  the `21f` B3LYP couple — its own builder and its own tier settings (imported from `21f`) — in
          the RECORDED environment (PySCF 2.11.0) with the fix EMULATED, compared with the committed
          cache (`dft/os_complex.json`, 2.11.0) and the lock re-run (`lock_rerun_2026-10-01.json`, 2.13.1).
  aqua    [Os(H2O)6]2+/3+ on the geometry `34` wrote (`ligands/os_hexaaqua.xyz`), `34`'s level shift on
          Os(III), conv_tol tightened to 1e-9 so the variants compare far below the gap:
          A = 2.11.0 as is · B = 2.11.0 with the fix emulated · C = the lock interpreter as is
          (a child process of `--lock-python`).
The emulation patches the module table in place for the duration of one SCF and restores it:
`modified_Bondi[Z_eff] := modified_Bondi[Z]` for every ECP element, so the switching radius looked up at
Z_eff is the element's own. It is valid only while no atom of element Z_eff is present (it would move
that atom too) — asserted — and it is refused in a build that already carries the fix.

CAN show: whether the emulated fix alone takes the recorded environment onto the lock value, per state.
CANNOT show: (1) the fix apart from the SCF solution where an open shell can land in different solutions —
the high-symmetry Os(III) aqua need not reach the same solution from run to run (the recorded environment
itself committed that couple twice, 2.4 meV apart), and with no stability analysis or <S²> in this record a
different solution is read from the energies, not proven; 2.13.0 also changed SCF defaults, a second
difference this script does not isolate; (2) the members of the class it does not run (the ωB97X tier of
`21f`, `21d`, `21e`, the `34`/`34b` complexes, `35`) — for them the gap is NOT measured.

Writes: tools/in_silico/cache/reproduction/pcm_ecp_radius_attribution.json (committed caches untouched).
Run:    mamba run -n silken_md python tools/in_silico/scripts/75_pcm_ecp_radius_attribution.py \\
            --lock-python ~/miniforge3/envs/silken_lock/bin/python
        (--verdict-only rebuilds the record's prose from its numbers, no SCF)
Cost:   ≈ 36 min of SCF on one machine (device ≈ 23 min, aqua 3 × ≈ 4 min), one job at a time.
"""
from __future__ import annotations

import argparse
import datetime
import importlib.util
import json
import platform
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    BASIS_LIGHT,
    BASIS_OS,
    CACHE_DIR,
    DFT_CACHE,
    ECP_OS,
    HARTREE_TO_EV,
    LIGANDS_DIR,
    REPO_ROOT,
)
from lib.dft_utils import dft_singlepoint
from lib.os_geometry import DMBPY_SMILES, build_os_complex
from lib.utils import banner

OUT = CACHE_DIR / "reproduction" / "pcm_ecp_radius_attribution.json"
LOCK_RECORD = CACHE_DIR / "reproduction" / "lock_rerun_2026-10-01.json"
AQUA_XYZ = LIGANDS_DIR / "os_hexaaqua.xyz"
AQUA_CONV = 1e-9          # tighter than 34's 1e-6: the variants must differ by more than the SCF tolerance
AQUA_MAX_CYCLE = 200
AQUA_LEVEL_SHIFT = 0.3    # 34's setting on the Os(III) UKS
FIX_VERSION = (2, 13, 0)  # first PySCF release carrying PR #3159
# OURS, not a source's: a pure cavity change moves the two states of a couple roughly with the squared charge —
# Born (3/2)² = 2.25 for the aqua couple, and the device couple MEASURED 3.3 at (2/1)² = 4 — so an open-shell
# shift above 10× the closed-shell one is read as a different SCF solution, not as the cavity.
OPEN_OVER_CLOSED_CEILING = 10.0
MARK = "@@ATTRIBUTION@@ "
PR = "https://github.com/pyscf/pyscf/pull/3159"
CORRECTS = ("the cause clause of lock_rerun_2026-10-01.json's verdict («SCF/PCM numerics on a heavy-metal ECP "
            "couple, not a different input») — the input DOES differ: the PCM cavity of an ECP atom. That record "
            "stays as written (a record of its day); this one carries the measured cause.")


def _version() -> str:
    import pyscf
    return pyscf.__version__


def _vtuple(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in v.split(".")[:3])


def _tier_21f() -> tuple:
    """21f's own b3lyp tier (xc, basis_light, level_shift_open, out_name, conv_tol) — imported, never retyped."""
    spec = importlib.util.spec_from_file_location("s21f", Path(__file__).with_name("21f_dft_os_dimethyl.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.TIERS["b3lyp"]


def _read_xyz(path: Path) -> list[tuple[str, np.ndarray]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    n = int(lines[0].split()[0])
    return [(ln.split()[0], np.array([float(x) for x in ln.split()[1:4]])) for ln in lines[2:2 + n]]


@contextmanager
def ecp_radius_fix_emulated(atoms, charge: int):
    """Give each ECP element's Z_eff slot of the PCM radius table the element's own radius, then restore."""
    from pyscf import gto
    from pyscf.data import radii
    from pyscf.solvent import pcm

    if _vtuple(_version()) >= FIX_VERSION:
        sys.exit(f"PySCF {_version()} already carries the fix — emulating it there would label nothing")
    mol = gto.M(atom=[(s, tuple(float(c) for c in p)) for s, p in atoms],
                basis={"Os": BASIS_OS, "default": BASIS_LIGHT}, ecp={"Os": ECP_OS},
                charge=charge, spin=0, unit="Angstrom", verbose=0)
    z_elem = [int(gto.charge(e)) for e in mol.elements]
    z_eff = [int(z) for z in mol.atom_charges()]
    pairs = {(z, ze) for z, ze in zip(z_elem, z_eff, strict=True) if ze != z}
    if len({ze for _, ze in pairs}) != len(pairs):
        sys.exit("emulation invalid: two ECP elements share one Z_eff slot")
    remap = {ze: z for z, ze in pairs}
    clash = sorted(set(remap) & set(z_elem))
    if clash:
        sys.exit(f"emulation invalid: element(s) Z={clash} present — patching their slot would move them too")
    saved = pcm.modified_Bondi.copy()
    info = {mol.elements[z_elem.index(z)]: {
        "Z": z, "Z_eff": ze, "note": "modified-Bondi table radius at the Z_eff slot; PCM scales it by 1.2",
        "slot_radius_A_before": round(float(saved[ze]) * radii.BOHR, 6),
        "slot_radius_A_after": round(float(saved[z]) * radii.BOHR, 6)} for ze, z in remap.items()}
    try:
        for ze, z in remap.items():
            pcm.modified_Bondi[ze] = saved[z]
        yield info
    finally:
        pcm.modified_Bondi[:] = saved


def _pair(atoms, q2: int, q3: int, label: str, *, xc="b3lyp", basis_light=None, conv=1e-6,
          lshift=0.0, max_cycle=100) -> dict:
    os2 = dft_singlepoint(atoms, charge=q2, spin=0, label=f"Os(II) {label}", xc=xc,
                          basis_light=basis_light, conv_tol=conv, max_cycle=max_cycle)
    os3 = dft_singlepoint(atoms, charge=q3, spin=1, label=f"Os(III) {label}", xc=xc,
                          basis_light=basis_light, conv_tol=conv, max_cycle=max_cycle,
                          level_shift_open=lshift)
    keep = ("E_total_Ha", "converged", "wall_seconds")
    return {"pyscf": _version(), "os2": {k: os2[k] for k in keep}, "os3": {k: os3[k] for k in keep},
            "dE_red_III_to_II_eV": (os2["E_total_Ha"] - os3["E_total_Ha"]) * HARTREE_TO_EV}


def run_aqua(emulate: bool) -> dict:
    atoms = _read_xyz(AQUA_XYZ)
    kw = {"conv": AQUA_CONV, "lshift": AQUA_LEVEL_SHIFT, "max_cycle": AQUA_MAX_CYCLE}
    if not emulate:
        return _pair(atoms, 2, 3, "aqua", **kw)
    with ecp_radius_fix_emulated(atoms, charge=2) as info:
        out = _pair(atoms, 2, 3, "aqua (fix emulated)", **kw)
    return {**out, "emulated": info}


def open_shell_reading(rec: dict) -> dict:
    """The open-shell call as FIELDS, so a pin can read it instead of parsing prose (§When Modifying #8).
    B meeting C says the fixed cavity and the lock reached the same state in THIS run; whether A's distance from
    them is the cavity is read from how far the open-shell shift outgrows the closed-shell one."""
    d2, d3 = rec["aqua_os_h2o6"]["differences_Ha"]["os2"], rec["aqua_os_h2o6"]["differences_Ha"]["os3"]
    ratio = abs(d3["A_minus_B"]) / abs(d2["A_minus_B"])
    meets = abs(d3["B_minus_C"]) <= 10 * AQUA_CONV
    return {"B_meets_C": meets, "open_over_closed_shift_ratio": ratio,
            "ratio_ceiling_read_as_cavity": OPEN_OVER_CLOSED_CEILING,
            "attributed_to_the_fix": meets and ratio <= OPEN_OVER_CLOSED_CEILING,
            "A_minus_C_meV": abs(d3["A_minus_C"]) * HARTREE_TO_EV * 1e3}


def build_verdict(rec: dict) -> str:
    """The record's prose, built from its own numbers only (in-silico §When Modifying #5) — so `--verdict-only`
    can rebuild it without a single SCF."""
    dev = rec["device_21f"]
    st, dE = dev["states"], dev["dE_red_III_to_II_eV"]
    dev_max = max(abs(s["with_fix_minus_lock_Ha"]) for s in st.values())
    gap_max = max(abs(s["with_fix_minus_committed_Ha"]) for s in st.values())
    d2, d3 = rec["aqua_os_h2o6"]["differences_Ha"]["os2"], rec["aqua_os_h2o6"]["differences_Ha"]["os3"]
    osr = open_shell_reading(rec)
    if not osr["B_meets_C"]:
        open_clause = ("the emulated fix does NOT take this state onto the lock value: the variants sit in "
                       "different SCF solutions, so the gap mixes the cavity fix with the solution reached "
                       "(2.13.0 also changed SCF defaults) — not attributed.")
    elif not osr["attributed_to_the_fix"]:
        open_clause = (f"B and C meet, but A lies {osr['A_minus_C_meV']:.0f} meV from them — "
                       f"{osr['open_over_closed_shift_ratio']:.0f}x the closed-shell effect of the fix, far beyond "
                       f"a cavity change — so A sits in a different SCF solution and the open shell is NOT "
                       f"attributed; with no stability analysis here, which solution a run reaches is not controlled.")
    else:
        open_clause = "the emulated fix takes this state onto the lock value as well."
    return (
        f"Device couple (21f): with the PCM ECP-radius fix emulated, PySCF {dev['pyscf_recorded']} lands on the "
        f"lock re-run (PySCF {dev['pyscf_lock']}) to {dev_max:.1e} Ha in both states, against a recorded-vs-lock "
        f"gap of up to {gap_max:.1e} Ha; dE_red(III->II) = {dE['recorded_with_fix']:.4f} eV (lock "
        f"{dE['lock_rerun']:.4f}, committed {dE['committed']:.4f}). Closed-shell [Os(H2O)6]2+: B - C = "
        f"{d2['B_minus_C']:.1e} Ha against A - C = {d2['A_minus_C']:.1e} Ha. Open-shell [Os(H2O)6]3+: "
        f"B - C = {d3['B_minus_C']:.1e} Ha and A - C = {d3['A_minus_C']:.1e} Ha — {open_clause} "
        f"Members of the class not run here are not measured by it.")


def run_lock_child(lock_python: str) -> dict:
    """Variant C: the same aqua pair in the LOCK interpreter, as is — a child process, after the parent's SCFs."""
    run = subprocess.run([lock_python, str(Path(__file__).resolve()), "--child-aqua"],
                         capture_output=True, text=True, check=False)
    lines = [ln for ln in run.stdout.splitlines() if ln.startswith(MARK)]
    if run.returncode != 0 or len(lines) != 1:
        sys.exit(f"lock child failed (exit {run.returncode}):\n{run.stderr[-2000:]}")
    return json.loads(lines[0][len(MARK):])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--lock-python", help="interpreter of the conda-lock environment (variant C)")
    ap.add_argument("--verdict-only", action="store_true",
                    help="rebuild the record's verdict from its own numbers — no SCF")
    ap.add_argument("--child-aqua", action="store_true", help=argparse.SUPPRESS)
    args = ap.parse_args()
    if args.child_aqua:
        print(MARK + json.dumps(run_aqua(emulate=False)))
        return 0
    if args.verdict_only:
        return _write(json.loads(OUT.read_text(encoding="utf-8")))
    if not args.lock_python:
        ap.error("--lock-python is required (variant C runs in the lock environment)")

    xc, basis_light, lshift, out_name, conv = _tier_21f()
    committed = json.loads((DFT_CACHE / out_name).read_text(encoding="utf-8"))
    lock = json.loads(LOCK_RECORD.read_text(encoding="utf-8"))["files"][f"dft/{out_name}"]["per_field"]
    lock_env = json.loads(LOCK_RECORD.read_text(encoding="utf-8"))["lock_env"]["versions"]["pyscf"]

    banner(f"device couple (21f {xc}) in PySCF {_version()} with the ECP-radius fix emulated")
    atoms, _ = build_os_complex(bpy_smiles=DMBPY_SMILES)
    with ecp_radius_fix_emulated(atoms, charge=1) as dev_info:
        dev = _pair(atoms, 1, 2, "dmbpy (fix emulated)", xc=xc, basis_light=basis_light, conv=conv,
                    lshift=lshift)
    device = {"settings": f"21f tier '{xc}': {xc}/{basis_light}+LANL2DZ(Os), C-PCM, conv_tol {conv:g}, "
                          f"Os(III) level shift {lshift:g}", "emulated": dev_info, "pyscf_recorded": dev["pyscf"],
              "pyscf_lock": lock_env, "states": {}}
    for st in ("os2", "os3"):
        key = f"{st}_plus.E_total_Ha"
        e_fix = dev[st]["E_total_Ha"]
        device["states"][st] = {
            "committed_Ha": committed[f"{st}_plus"]["E_total_Ha"], "lock_rerun_Ha": lock[key]["lock_rerun"],
            "recorded_with_fix_Ha": e_fix, "converged": dev[st]["converged"],
            "with_fix_minus_lock_Ha": e_fix - lock[key]["lock_rerun"],
            "with_fix_minus_committed_Ha": e_fix - committed[f"{st}_plus"]["E_total_Ha"],
            "wall_seconds": dev[st]["wall_seconds"]}
    device["dE_red_III_to_II_eV"] = {"committed": committed["dE_red_III_to_II_eV"],
                                     "lock_rerun": lock["dE_red_III_to_II_eV"]["lock_rerun"],
                                     "recorded_with_fix": round(dev["dE_red_III_to_II_eV"], 6)}

    banner(f"[Os(H2O)6] A — PySCF {_version()} as is")
    a = run_aqua(emulate=False)
    banner(f"[Os(H2O)6] B — PySCF {_version()} with the fix emulated")
    b = run_aqua(emulate=True)
    banner("[Os(H2O)6] C — the lock interpreter as is (child process)")
    c = run_lock_child(args.lock_python)
    aqua = {"geometry": str(AQUA_XYZ.relative_to(REPO_ROOT)),
            "settings": f"b3lyp/{BASIS_LIGHT}+LANL2DZ(Os), C-PCM, conv_tol {AQUA_CONV:g}, "
                        f"Os(III) level shift {AQUA_LEVEL_SHIFT:g}",
            "A_recorded_as_is": a, "B_recorded_with_fix": b, "C_lock_as_is": c,
            "differences_Ha": {st: {"B_minus_C": b[st]["E_total_Ha"] - c[st]["E_total_Ha"],
                                    "A_minus_C": a[st]["E_total_Ha"] - c[st]["E_total_Ha"],
                                    "A_minus_B": a[st]["E_total_Ha"] - b[st]["E_total_Ha"]}
                               for st in ("os2", "os3")}}

    record = {
        "what": ("Attribution of the conda-lock gap on metal-in-PCM couples (paper §2.7) to the PySCF 2.13.0 "
                 "fix of the PCM switching radius of ECP atoms. Committed caches are UNCHANGED by this run."),
        "date": datetime.date.today().isoformat(),
        "platform": {"os": platform.platform(), "machine": platform.machine(),
                     "python": platform.python_version()},
        "cause_under_test": {
            "changelog": "PySCF 2.13.0 (2026-04-20), Fixes: 'A bug where PCM assigned incorrect radii to ECP atoms'",
            "pull_request": PR, "merge_commit": "79e82d965f6162429c459f1166b07febbfa734b7",
            "mechanism": ("up to 2.12 gen_surface took the switching-function radius R_J at mol.atom_charges() "
                          "(nuclear charge minus the ECP core) and the surface points at the element radius; "
                          "from 2.13.0 both use the element")},
        "procedure": ("this script, one SCF at a time: the device couple in the recorded env with the fix "
                      "emulated (21f's builder and b3lyp tier via lib.dft_utils.dft_singlepoint), then the "
                      "hexa-aqua pair A/B in the recorded env and C in the lock env as a child process; the "
                      "device's lock values are READ from lock_rerun_2026-10-01.json, not re-run"),
        "device_21f": device,
        "aqua_os_h2o6": aqua,
    }
    return _write(record)


def _write(record: dict) -> int:
    record.pop("verdict", None)   # rebuilt below, after the field it reads
    record["corrects"] = CORRECTS
    record["open_shell_reading"] = open_shell_reading(record)
    record["verdict"] = build_verdict(record)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"saved {OUT.relative_to(REPO_ROOT)}")
    print(record["verdict"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
