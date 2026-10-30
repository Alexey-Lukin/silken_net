#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""112 — E°(FAD/FADH₂) on 32b's relaxed geometries at the larger basis, then at the range-separated functional.

WHY. The like-for-like cascade (95) reads its donor side from 32b, whose one tier is B3LYP/6-31G(d)+C-PCM, and the
manuscript's limits paragraph lists «the basis and the functional» among the donor-side terms it does not size (paper
§3.5). This script sizes those two and nothing else (self-review round 2, П4(a) — ⚖️ founder 2026-10-23, «both»).

One knob at a time (in-silico §When Modifying #33 · #36), every tier on the SAME two geometries:
  (0) control — the committed relaxed geometries (`ligands/lumiflavin_{ox,red}_opt.xyz`) must be the ones 32b cached
      (≤ GEOM_TOL_A), and the shared single point at 32b's tier must reproduce 32b's energies (≤ CONTROL_TOL_HA), else
      the run stops before any larger SCF: a geometry or protocol drift would otherwise read as a basis or functional
      effect;
  (1) the basis — B3LYP/def2-TZVP+C-PCM, both states;
  (2) the functional — ωB97X/def2-TZVP+C-PCM, both states (plain ωB97X, Critical Rule #20); its reduced flavin is held to
      33's ωB97X/def2-TZVP energy of 33's own minimum within CONTROL_33_TOL_HA — the same minimum as 32b's by 33's
      `control_FADH2_minimum_vs_32b_Ha`, not the same coordinates, so this checks the protocol, not the geometry.
E° by 32b's `potential` — 32's formula, proton reference and SHE, loaded, never retyped. Each tier is read against 32b's
relaxed electronic E°; the composite readings (+ ZPE, + RRHO free energy) add 32b's B3LYP/6-31G(d) thermal terms to the
new electronic energies (Critical Rule #22's composite, one level further), so they move by exactly the same shift.

CAN: say how far the larger basis, and then the range-separated functional, move E°(FAD/FADH₂) on 32b's geometries — so
how far each moves the donor side of the like-for-like cascade if the osmium side is held.
CANNOT: (1) the geometry at the new tiers — both states stay B3LYP/6-31G(d) minima; (2) the thermal terms at the new
tiers — 32b's Hessians are reused; (3) the osmium side at the same tiers — 95's acceptor side stays at its own tier, so
a cascade cell with this donor would mix tiers, and none is written; (4) any other donor-side term the paper names
(lumiflavin for FAD, the protonation state at pH 7, the soft modes, explicit water); (5) basis-set convergence —
def2-TZVP is one step up, not a limit.

Writes `cache/dft/pcet_donor_basis_functional.json` (its own cache — 32b's and 33's are only read) and a
`<cache>.partial.json` after each state and on any failure.

Run (in-silico §When Modifying #21a · #34 — sequential, nothing heavy alongside):
  python tools/in_silico/scripts/112_pcet_donor_basis_functional.py --rehearse <dir>   # STO-3G, writes only into <dir>
  cd /Users/oleksiilukin/silken_net || exit 1
  perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' -- caffeinate -ims ~/miniforge3/envs/silken_md/bin/python -u \\
      tools/in_silico/scripts/112_pcet_donor_basis_functional.py > tools/in_silico/cache/runs/112.log 2>&1 &
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, LIGANDS_DIR, REPO_ROOT
from lib.dft_utils import dft_singlepoint
from lib.utils import banner

SI_DESCRIPTION = ("L3 FAD/FADH₂ PCET potential on the B3LYP/6-31G(d)+C-PCM relaxed geometries, re-read at the def2-TZVP "
                  "basis and then the ωB97X functional (C-PCM), one knob at a time — the donor side's basis and functional")

SCRIPTS = Path(__file__).resolve().parent
OUT = DFT_CACHE / "pcet_donor_basis_functional.json"
CONTROL_TOL_HA = 1e-6     # 32b's own control tolerance — the same protocol on the same coordinates
GEOM_TOL_A = 1e-6         # the .xyz carries 8 decimals of 32b's cached coordinates
# 33's minimum and 32b's differ by 3.9e-6 Ha at B3LYP (33's control) and 33 converged at conv_tol 1e-6; another basis,
# functional or continuum moves a 33-atom flavin by orders more — DECLARED between the two, not a measured noise floor
CONTROL_33_TOL_HA = 1e-4
TIERS = (  # (key, xc, light-atom basis, the knob this tier turns over the previous one)
    ("b3lyp_def2tzvp", "b3lyp", "def2-tzvp", "basis: 6-31G(d) → def2-TZVP at B3LYP"),
    ("wb97x_def2tzvp", "wb97x", "def2-tzvp", "functional: B3LYP → ωB97X at def2-TZVP"),
)


def _module(fname: str):
    spec = importlib.util.spec_from_file_location(fname[:-3].replace("-", "_"), SCRIPTS / fname)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def geometry_check(s32b, cache32b) -> dict:
    """Before any SCF: the committed relaxed geometries are 32b's cached ones — atom order and coordinates."""
    out = {}
    for tag in ("ox", "red"):
        committed = s32b._read_xyz(LIGANDS_DIR / f"lumiflavin_{tag}_opt.xyz")
        cached = cache32b["species"][tag]["relaxed_geometry"]
        if [a for a, _ in committed] != [a for a, _ in cached]:
            raise SystemExit(f"{tag}: ligands/lumiflavin_{tag}_opt.xyz has another atom order than 32b's cache")
        dev = max(float(np.abs(p - np.asarray(q)).max()) for (_, p), (_, q) in zip(committed, cached, strict=True))
        if dev > GEOM_TOL_A:
            raise SystemExit(f"{tag}: ligands/lumiflavin_{tag}_opt.xyz departs from 32b's cached geometry by {dev:.2e} Å")
        out[tag] = {"atoms": committed, "max_dev_vs_32b_cache_A": dev}
    return out


def single_point(atoms, label: str, **protocol) -> dict:
    r = dft_singlepoint(atoms, 0, 0, label=label, **protocol)
    if not r["converged"] or not r["aufbau"]:
        raise SystemExit(f"{label}: converged={r['converged']} aufbau={r['aufbau']} — no number is written")
    return {"E_Ha": r["E_total_Ha"], "rescued": r["rescued"], "wall_seconds": r["wall_seconds"]}


def main(argv) -> int:
    import pyscf
    rehearse = argv[argv.index("--rehearse") + 1] if "--rehearse" in argv else None
    out_cache = Path(rehearse) / OUT.name if rehearse else OUT
    out_cache.parent.mkdir(parents=True, exist_ok=True)
    base = {"conv_tol": 1e-8}
    s32, s32b = _module("32_pcet_redox_potential.py"), _module("32b_pcet_redox_thermo.py")
    cache32 = json.loads((DFT_CACHE / "pcet_redox_potential.json").read_text(encoding="utf-8"))
    cache32b = json.loads((DFT_CACHE / "pcet_redox_potential_thermo.json").read_text(encoding="utf-8"))
    cache33 = json.loads((DFT_CACHE / "pcet_cascade.json").read_text(encoding="utf-8"))
    if s32b.potential(cache32b["species"]["red"]["E_Ha"], cache32b["species"]["ox"]["E_Ha"], s32) \
            != cache32b["E_vs_SHE_mV"]["relaxed_electronic"]:
        raise SystemExit("32b's formula on 32b's energies does not give 32b's cached relaxed E° — the shared formula drifted")
    meas = cache32["exp_free_flavin_pH7_mV"][0]
    th = {t: cache32b["species"][t] for t in ("ox", "red")}

    banner("112 — geometry check before any SCF" + (" (STO-3G REHEARSAL)" if rehearse else ""))
    geo = geometry_check(s32b, cache32b)
    record = {"method": "single points on 32b's B3LYP/6-31G(d)+C-PCM relaxed geometries; C-PCM water; E° by 32's formula "
                        "(32b `potential`); thermal terms from 32b's B3LYP/6-31G(d) Hessians",
              "rehearsal": bool(rehearse), "pyscf": pyscf.__version__, "protocol": base,
              "geometry": {t: {"file": f"ligands/lumiflavin_{t}_opt.xyz",
                               "max_dev_vs_32b_cache_A": geo[t]["max_dev_vs_32b_cache_A"]} for t in ("ox", "red")},
              "control_32b": {}, "tiers": {}}
    partial = Path(f"{out_cache}.partial.json")

    def dump(path: Path) -> None:
        path.write_text(json.dumps(record, indent=2, ensure_ascii=False, default=str) + "\n", encoding="utf-8")

    light = {"basis_light": "sto-3g"} if rehearse else {}
    try:
        banner("(0) control — 32b's tier on the committed relaxed geometries against 32b's cache")
        for tag in ("ox", "red"):
            sp = single_point(geo[tag]["atoms"], f"{tag} control", xc="b3lyp", **base, **light)
            sp["delta_vs_32b_Ha"] = sp["E_Ha"] - th[tag]["E_Ha"]
            record["control_32b"][tag] = sp
            print(f"  {tag}: E = {sp['E_Ha']:.8f} Ha, Δ vs 32b = {sp['delta_vs_32b_Ha']:+.2e} Ha", flush=True)
            if abs(sp["delta_vs_32b_Ha"]) > CONTROL_TOL_HA and not rehearse:
                raise SystemExit(f"control failed: 32b's tier departs from 32b by {sp['delta_vs_32b_Ha']:+.2e} Ha on {tag}")
        dump(partial)

        for key, xc, basis, knob in TIERS:
            banner(f"{key} — {knob}")
            tier = record["tiers"][key] = {"xc": xc, "basis_light": basis, "knob": knob, "species": {}}
            for tag in ("ox", "red"):
                sp = single_point(geo[tag]["atoms"], f"{tag} {key}", xc=xc, **base,
                                  basis_light=light.get("basis_light", basis))
                tier["species"][tag] = sp
                print(f"  {tag}: E = {sp['E_Ha']:.8f} Ha ({sp['wall_seconds']:.0f} s, rescued={sp['rescued']})", flush=True)
                dump(partial)
    except BaseException:
        dump(partial)
        raise

    e33 = cache33["E_FADH2_Ha"]
    d33 = record["tiers"]["wb97x_def2tzvp"]["species"]["red"]["E_Ha"] - e33
    record["control_33"] = {"E_FADH2_33_Ha": e33, "delta_Ha": d33, "tolerance_Ha": CONTROL_33_TOL_HA}
    print(f"  control 33: ωB97X/def2-TZVP FADH₂ here − 33's = {d33:+.2e} Ha", flush=True)
    if abs(d33) > CONTROL_33_TOL_HA and not rehearse:
        dump(Path(f"{out_cache}.unconverged.json"))
        raise SystemExit(f"control failed: the reduced flavin departs from 33's ωB97X/def2-TZVP energy by {d33:+.2e} Ha")

    ref = cache32b["E_vs_SHE_mV"]["relaxed_electronic"]
    prev = ref
    for key, *_ in TIERS:
        tier = record["tiers"][key]
        ox, red = tier["species"]["ox"]["E_Ha"], tier["species"]["red"]["E_Ha"]
        levels = tier["E_vs_SHE_mV"] = {
            "relaxed_electronic": s32b.potential(red, ox, s32),
            "relaxed_plus_zpe": s32b.potential(red + th["red"]["ZPE_Ha"], ox + th["ox"]["ZPE_Ha"], s32),
            "relaxed_rrho_free_energy": s32b.potential(red + th["red"]["G_tot_Ha"] - th["red"]["E_Ha"],
                                                       ox + th["ox"]["G_tot_Ha"] - th["ox"]["E_Ha"], s32),
        }
        e7 = levels["relaxed_electronic"]["pH_7.0"]
        tier["shift_vs_32b_pH7_mV"] = round(e7 - ref["pH_7.0"], 1)
        tier["shift_vs_previous_tier_pH7_mV"] = round(e7 - prev["pH_7.0"], 1)
        tier["vs_measured_free_flavin_pH7_mV"] = {k: round(v["pH_7.0"] - meas, 1) for k, v in levels.items()}
        prev = levels["relaxed_electronic"]
    b, f = (record["tiers"][k]["shift_vs_previous_tier_pH7_mV"] for k, *_ in TIERS)
    both = record["tiers"]["wb97x_def2tzvp"]["shift_vs_32b_pH7_mV"]
    record["knobs_pH7_mV"] = {"basis": b, "functional": f, "both": both}
    t1, t2 = (record["tiers"][k] for k, *_ in TIERS)
    e1, e2 = (t["E_vs_SHE_mV"]["relaxed_electronic"]["pH_7.0"] for t in (t1, t2))
    levels = list(t1["vs_measured_free_flavin_pH7_mV"])
    sides = {name: " · ".join(f"{src[k]:+.1f}" for k in levels)
             for name, src in (("t1", t1["vs_measured_free_flavin_pH7_mV"]), ("t2", t2["vs_measured_free_flavin_pH7_mV"]),
                               ("32b", cache32b["vs_measured_free_flavin_pH7_mV"]))}
    record["verdict"] = ("STO-3G REHEARSAL — every tier below is STO-3G, not its label. " if rehearse else "") + (
        f"E°(FAD/FADH₂, pH 7) on 32b's relaxed geometries: {ref['pH_7.0']:+.1f} mV at B3LYP/6-31G(d) (32b), {e1:+.1f} at "
        f"B3LYP/def2-TZVP — the basis moves it {b:+.1f} mV — and {e2:+.1f} at ωB97X/def2-TZVP — the functional a further "
        f"{f:+.1f} mV, {both:+.1f} together. Against {meas:+.0f} mV measured for the free flavin the donor side reads, "
        f"electronic · + ZPE · + RRHO: {sides['t1']} mV at B3LYP/def2-TZVP, {sides['t2']} mV at ωB97X/def2-TZVP (32b: "
        f"{sides['32b']}). Geometries and thermal terms stay 32b's B3LYP/6-31G(d) ones; the osmium side is not recomputed "
        f"(CANNOT 1–3).")
    dump(out_cache)
    for stale in (partial, Path(f"{out_cache}.unconverged.json")):
        stale.unlink(missing_ok=True)
    banner(f"✅ saved {out_cache if rehearse else out_cache.relative_to(REPO_ROOT)}")
    print("  " + record["verdict"], flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
