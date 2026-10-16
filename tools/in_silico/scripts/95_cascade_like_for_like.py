#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""95 — the anode cascade like-for-like: 2e⁻/2H⁺ FAD against the Os(III/II) couple on ONE SHE scale (no SCF).

WHY. Table 2 of Стаття 1 set the bare one-electron oxidation FADH₂ → FADH₂•⁺ against the two-electron, two-proton potential
of FAD, and a Koopmans orbital offset against a free energy (self-review round 1, cluster 3 — 00_07 HW.5.IS, revision step 3).
Both halves of a like-for-like comparison are already computed at ONE tier (B3LYP/6-31G(d)+C-PCM, LANL2DZ on Os) under ONE
absolute-SHE convention (script 32, Isse & Gennaro 2010): E°(FAD/FADH₂) at pH 7 (32, and 32b at four levels) and
ΔE_red(III→II) of each Os form (21f · 34 · 21e relaxed). This script sets them side by side and splits the distance to the
measured cascade by SIDE:

    E°(Os) vs SHE     = −ΔE_red(III→II) − |SHE_abs|                     one electron, no proton, pH-independent
    cascade           = E°(Os) − E°(FAD/FADH₂, pH 7)                   > 0 = downhill
    measured, free    = E°(Os) +309 mV − E°(free FAD) −220 mV          the SAME two couples the computation models
    measured, device  = E°(Os) +309 mV − E°(FAD-GDH, bound) −265 mV    adds the protein shift of the cofactor (④)
    donor side        = E°(FAD)_computed − E°(free FAD)_measured        > 0 = the computation shortens the cascade there
    acceptor side     = E°(Os)_measured − E°(Os)_computed               > 0 = the computation shortens the cascade there

The donor is read at 32b's four levels, one knob at a time: the MMFF geometries' electronic energies (32's protocol — 32b's
control, which must equal 32's cache or this script refuses), the relaxed geometries, + the zero-point energy, + the RRHO
thermal free energy. The acceptor is one reading per Os form at every level.

CAN: say, per Os form and per donor level, how far the computed cascade sits from the measured one for the same couples and
on which side each part of that distance lies — from the committed caches alone; and, once 96 has run, the adiabatic chloro
form with the ZPE and RRHO terms on BOTH sides (`both_sided`, two boundary controls: one SHE, and 96's electronic ΔG_red =
this form's ΔE_red). CANNOT: (1) the Os side's ZPE and thermal terms of every other form — 96 corrects one (32b CANNOT 1),
so there the cascade at (ii)/(iii) is a ONE-SIDED correction, and only the electronic levels carry the same approximation
on both sides; 96's RRHO level enters only when its two states' soft-mode censuses match; (2) the protein shift of the bound cofactor (free −220 → bound −265 mV) — measured, carried as
such, never computed (④); (3) the measured mediator is a polymer film, the computed one a molecule with one 1-MeIm; (4) any
ωB97X reading — the flavin has no ωB97X PCET potential, so an ωB97X Os side would not be like-for-like; (5) geometry: each
Os form is programmatic or B3LYP-relaxed as its label says, the flavin MMFF or relaxed as its level says. NHE and SHE are
taken as one scale, as in 32.

Run:  conda activate silken_md
      python tools/in_silico/scripts/95_cascade_like_for_like.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, E_FAD_GDH_MV_SHE, E_OS_MEDIATOR_MV_NHE, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("L3 anode cascade like-for-like: the 2e⁻/2H⁺ FAD potential at 32b's four levels (MMFF electronic = 32 · "
                  "relaxed · + ZPE · + RRHO) against the Os(III/II) couple of each computed form (21f · 34 · 21e relaxed) on "
                  "one SHE scale, the distance to the measured cascade split by side; no SCF")

OUT = DFT_CACHE / "cascade_like_for_like.json"
# 32b's keys, in the order its knobs are added; the first is 32's protocol and must reproduce 32's cache
LEVELS = {"mmff_electronic": "MMFF geometries, electronic (32)",
          "relaxed_electronic": "relaxed, electronic",
          "relaxed_plus_zpe": "relaxed + ZPE",
          "relaxed_rrho_free_energy": "relaxed + RRHO free energy"}
ONE_SIDED = ("relaxed_plus_zpe", "relaxed_rrho_free_energy")
# 96 corrects ONE Os form on its side too — its levels, paired with 32b's relaxed ones (both sides relaxed at every level)
BOTH_SIDED_FORM = "chloro, both states relaxed (adiabatic)"
OS_LEVEL_OF = {"relaxed_electronic": "electronic", "relaxed_plus_zpe": "plus_zpe", "relaxed_rrho_free_energy": "rrho_free_energy"}
# an agreement is named a CANCELLATION when the cascade lands this close to the measured one while EACH side is at least the
# second number off (0.1 eV — D's first trigger): 32b's ZPE level put the device cascade 0.3 mV from the measurement out
# of a −210 mV donor and a +209 mV acceptor error (2026-10-16), and a bare «matches» would be quoted as validation
CANCEL_GAP_V, CANCEL_SIDE_V = 0.05, 0.1


def cancels(gap: float, donor: float, acceptor: float) -> bool:
    return abs(gap) <= CANCEL_GAP_V and min(abs(donor), abs(acceptor)) >= CANCEL_SIDE_V


def _load(name: str) -> dict:
    return json.loads((DFT_CACHE / name).read_text(encoding="utf-8"))


def forms() -> list[tuple[str, str, float]]:
    """(label, source, ΔE_red(III→II) eV) — every B3LYP/C-PCM chloro-core form of the device mediator in the caches."""
    micro = {r["name"]: r for r in _load("microsolvation_dmbpy.json")["results"]}
    relaxed2 = _load("os_mediator_series_relaxed_os2.json")["complexes"]["dmbpy"]
    relaxed3 = _load("os_mediator_series_relaxed_os3.json")["complexes"]["dmbpy"]
    rows = [("chloro (device, programmatic)", "21f os_complex.json", _load("os_complex.json")["dE_red_III_to_II_eV"])]
    rows += [(f"chloro + {k} H₂O on Cl⁻", "34 microsolvation_dmbpy.json", micro[f"mediator_k{k}_clwaters"]["dE_red_eV"])
             for k in (1, 2, 3)]
    rows += [("chloro, Os(II) relaxed, Os(III) vertical", "21e os_mediator_series_relaxed_os2.json", relaxed2["dE_red_eV"]),
             ("chloro, both states relaxed (adiabatic)", "21e os_mediator_series_relaxed_os3.json",
              relaxed3["dE_red_adiabatic_eV"])]
    rows += [("aqua (benchmark form)", "34 microsolvation_dmbpy.json", micro["aqua_meim_h2o"]["dE_red_eV"]),
             ("bis-imidazole (operando upper form)", "34 microsolvation_dmbpy.json", micro["bisim_meim2"]["dE_red_eV"])]
    return rows


def donor_levels(pcet: dict, thermo: dict) -> dict[str, float]:
    """E°(FAD/FADH₂, pH 7) in V at each of 32b's levels — after the control: 32b's MMFF level must be 32's number."""
    steps = thermo["E_vs_SHE_mV"]
    if list(steps) != list(LEVELS):
        raise SystemExit(f"32b's levels are {list(steps)}, this script reads {list(LEVELS)} — re-read 32b before 95")
    # 32b's MMFF level comes from its OWN single points (≤ 1e-6 Ha from 20's), so the 0.1 mV rounding may differ by one unit
    if steps["mmff_electronic"].keys() != pcet["E_vs_SHE_mV"].keys() or any(
            abs(steps["mmff_electronic"][ph] - v) > 0.1 + 1e-9 for ph, v in pcet["E_vs_SHE_mV"].items()):
        raise SystemExit("32b's MMFF level is not 32's cached potential — the two flavin caches describe different protocols")
    return {k: steps[k]["pH_7.0"] / 1000.0 for k in LEVELS}


def both_sided(rows: list, e_fad: dict, meas_free: float, fad_free_meas: float, os_meas: float, she_abs: float) -> dict:
    """The adiabatic chloro form with 96's thermochemistry on the Os side too — or an explicit «not computed» when 96 has
    not run. Two boundary controls: 96's SHE (32's module) is 95's (32's cache), and 96's electronic ΔG_red is the ΔE_red
    this form already carries (21e) — else the two halves of the row would stand on different references."""
    if not (DFT_CACHE / "os_couple_thermo.json").exists():
        return {"form": BOTH_SIDED_FORM, "computed": False, "reason": "96 os_couple_thermo.json not run yet"}
    th = _load("os_couple_thermo.json")
    (row,) = [r for r in rows if r["form"] == BOTH_SIDED_FORM]
    if abs(-(th["E_os_vs_SHE_V"]["electronic"] + she_abs) - th["dG_red_eV"]["electronic"]) > 1e-4 + 1e-9:
        raise SystemExit("96's E°(Os) does not stand on 95's SHE — the two halves would use different references")
    if abs(th["dG_red_eV"]["electronic"] - row["dE_red_III_to_II_eV"]) > 1e-3:
        raise SystemExit("96's electronic ΔG_red is not the ΔE_red 95 carries for this form — re-run 96 on 21e's current caches")
    out = {"form": BOTH_SIDED_FORM, "computed": True, "source": "96 os_couple_thermo.json",
           "rrho_comparable": th["rrho_comparable"], "levels": {}}
    for k, os_k in OS_LEVEL_OF.items():
        if os_k == "rrho_free_energy" and not th["rrho_comparable"]:
            out["levels"][k] = {"skipped": "96: the two Os states' soft-mode censuses differ — RRHO not comparable"}
            continue
        e_os = -th["dG_red_eV"][os_k] - she_abs
        cascade = e_os - e_fad[k]
        out["levels"][k] = {"E_os_vs_SHE_V": round(e_os, 4), "acceptor_side_V": round(os_meas - e_os, 4),
                            "donor_side_V": round(e_fad[k] - fad_free_meas, 4), "cascade_V": round(cascade, 4),
                            "gap_to_measured_same_couples_V": round(meas_free - cascade, 4),
                            "direction": "downhill" if cascade > 0 else "uphill"}
    return out


def main() -> int:
    pcet = _load("pcet_redox_potential.json")
    thermo = _load("pcet_redox_potential_thermo.json")
    she_abs = pcet["SHE_abs_V"]
    e_fad = donor_levels(pcet, thermo)
    (fad_free_meas,) = [v / 1000.0 for v in pcet["exp_free_flavin_pH7_mV"]]   # 32 carries one sourced reading
    os_meas = E_OS_MEDIATOR_MV_NHE / 1000.0
    fad_bound_meas = E_FAD_GDH_MV_SHE / 1000.0
    meas_free = os_meas - fad_free_meas
    meas_device = os_meas - fad_bound_meas
    donor = {k: e - fad_free_meas for k, e in e_fad.items()}

    banner("95 — anode cascade like-for-like (B3LYP/C-PCM, one SHE scale)")
    print(f"  measured free flavin {fad_free_meas * 1000:+.0f} mV · measured cascade, same couples {meas_free * 1000:+.0f} mV · "
          f"device (bound FAD-GDH) {meas_device * 1000:+.0f} mV")
    for k, label in LEVELS.items():
        print(f"  E°(FAD/FADH₂, pH 7) {label:30s} {e_fad[k] * 1000:+7.1f} mV → donor side {donor[k] * 1000:+7.1f} mV"
              + ("   (one-sided: Os without thermochemistry)" if k in ONE_SIDED else ""))
    print(f"\n  {'form':44s} {'E°(Os) mV':>10s} {'acceptor':>9s}  " + "  ".join(f"{'cascade ' + str(i):>10s}"
                                                                          for i in range(len(LEVELS))))
    rows = []
    for label, source, de_red in forms():
        e_os = -de_red - she_abs
        acceptor = os_meas - e_os
        by_level = {}
        for k in LEVELS:
            cascade = e_os - e_fad[k]
            by_level[k] = {"cascade_V": round(cascade, 4), "direction": "downhill" if cascade > 0 else "uphill",
                           "gap_to_measured_same_couples_V": round(meas_free - cascade, 4),
                           "donor_side_V": round(donor[k], 4)}
        rows.append({"form": label, "source": source, "dE_red_III_to_II_eV": de_red, "E_os_vs_SHE_V": round(e_os, 4),
                     "acceptor_side_V": round(acceptor, 4), "by_donor_level": by_level})
        print(f"  {label:44s} {e_os * 1000:+10.1f} {acceptor * 1000:+9.1f}  "
              + "  ".join(f"{by_level[k]['cascade_V'] * 1000:+10.1f}" for k in LEVELS))
    print("  cascade 0…3 = " + " · ".join(LEVELS.values()))
    bs = both_sided(rows, e_fad, meas_free, fad_free_meas, os_meas, she_abs)
    if bs["computed"]:
        print(f"\n  «{BOTH_SIDED_FORM}» with the Os thermochemistry too (96): "
              + " · ".join(f"{LEVELS[k]} {v['cascade_V'] * 1000:+.1f} mV" if "cascade_V" in v else f"{LEVELS[k]} — {v['skipped']}"
                           for k, v in bs["levels"].items()))
    else:
        print(f"\n  both-sided row: {bs['reason']}")

    cancellations = [{"form": r["form"], "level": k, "gap_V": c["gap_to_measured_same_couples_V"],
                      "donor_side_V": c["donor_side_V"], "acceptor_side_V": r["acceptor_side_V"]}
                     for r in rows for k, c in r["by_donor_level"].items()
                     if cancels(c["gap_to_measured_same_couples_V"], c["donor_side_V"], r["acceptor_side_V"])]
    cancellations += [{"form": BOTH_SIDED_FORM + " (96 both-sided)", "level": k, "gap_V": v["gap_to_measured_same_couples_V"],
                       "donor_side_V": v["donor_side_V"], "acceptor_side_V": v["acceptor_side_V"]}
                      for k, v in bs.get("levels", {}).items()
                      if "cascade_V" in v and cancels(v["gap_to_measured_same_couples_V"], v["donor_side_V"], v["acceptor_side_V"])]
    dev = rows[0]
    closest = min(rows, key=lambda r: abs(r["acceptor_side_V"]))
    over = [r["form"] for r in rows if r["acceptor_side_V"] < 0]
    uphill = [(r["form"], LEVELS[k]) for r in rows for k in LEVELS if r["by_donor_level"][k]["direction"] == "uphill"]
    screening, zpe = "mmff_electronic", "relaxed_plus_zpe"
    dev_at = {k: dev["by_donor_level"][k] for k in LEVELS}
    verdict = (
        f"On one SHE scale at B3LYP/C-PCM the device chloro couple against the flavin couple at 32's protocol gives a "
        f"{dev_at[screening]['direction']} cascade of {dev_at[screening]['cascade_V'] * 1000:+.0f} mV against "
        f"{meas_free * 1000:+.0f} mV measured for the same free couples; of the "
        f"{dev_at[screening]['gap_to_measured_same_couples_V'] * 1000:.0f} mV between them "
        f"{dev['acceptor_side_V'] * 1000:+.0f} mV lie on the acceptor side and {donor[screening] * 1000:+.0f} mV on the donor "
        f"side. Relaxing the flavin, then adding its ZPE, then its RRHO free energy moves the donor side to "
        + " · ".join(f"{donor[k] * 1000:+.0f}" for k in list(LEVELS)[1:])
        + " mV, and the device cascade to " + " · ".join(f"{dev_at[k]['cascade_V'] * 1000:+.0f}" for k in list(LEVELS)[1:])
        + " mV"
        + (f" — the screening donor side ({donor[screening] * 1000:+.0f} mV) does not survive the zero-point term it omits"
           if abs(donor[zpe] - donor[screening]) > abs(donor[screening]) else "")
        + ". "
        + (f"Within {CANCEL_GAP_V * 1000:.0f} mV of the measured cascade while each side is ≥ {CANCEL_SIDE_V * 1000:.0f} mV off — "
           "an agreement by CANCELLATION, not a validation: "
           + "; ".join(f"«{c['form']}» at {LEVELS[c['level']]} ({c['gap_V'] * 1000:+.1f} mV = donor {c['donor_side_V'] * 1000:+.0f}"
                       f" + acceptor {c['acceptor_side_V'] * 1000:+.0f})" for c in cancellations) + ". "
           if cancellations else "")
        + ("Every form is downhill at every donor level" if not uphill else
           "Uphill: " + "; ".join(f"«{f}» at {lv}" for f, lv in uphill))
        + f"; the acceptor side is smallest for «{closest['form']}» ({closest['acceptor_side_V'] * 1000:+.0f} mV)"
        + (f", and {', '.join('«' + f + '»' for f in over)} overshoot the measured mediator" if over else "")
        + (". The ZPE and RRHO levels correct the donor only — no Os form carries thermochemistry, so those cascades are "
           "one-sided" if not bs["computed"] else
           f". The ZPE and RRHO levels correct the donor of every form and the Os side of «{BOTH_SIDED_FORM}» only (96): "
           "with both sides relaxed and corrected that form gives "
           + " · ".join(f"{v['cascade_V'] * 1000:+.0f}" if "cascade_V" in v else "RRHO not comparable"
                        for v in bs["levels"].values())
           + " mV (electronic · ZPE · RRHO); every other form's ZPE/RRHO cascade is one-sided")
        + f". The device cascade (+{meas_device * 1000:.0f} mV) adds the measured protein shift "
          f"({(fad_bound_meas - fad_free_meas) * 1000:+.0f} mV on the donor), which is not computed here."
    )
    result = {
        "method": "B3LYP/6-31G(d)+C-PCM(water), LANL2DZ on Os; the flavin at 32b's four levels (MMFF electronic = 32 · relaxed "
                  "electronic · + ZPE · + RRHO free energy), every Os form at its electronic energy and the adiabatic chloro one also "
                  "with 96's thermochemistry; one absolute-SHE "
                  "convention (32: Isse & Gennaro 2010)",
        "conventions": {"SHE_abs_V": she_abs, "E_os": "−ΔE_red(III→II) − |SHE_abs|",
                        "cascade": "E°(Os) − E°(FAD/FADH₂, pH 7), > 0 = downhill",
                        "sides": "donor = computed − measured free FAD; acceptor = measured − computed Os; gap = their sum"},
        "flavin": {"E_pH7_measured_free_V": fad_free_meas,
                   "levels": {k: {"label": LEVELS[k], "E_pH7_computed_V": round(e_fad[k], 4),
                                  "donor_side_V": round(donor[k], 4), "one_sided": k in ONE_SIDED} for k in LEVELS},
                   "source": "32 pcet_redox_potential.json (the control) · 32b pcet_redox_potential_thermo.json"},
        "measured": {"E_os_V": os_meas, "E_fad_gdh_bound_V": fad_bound_meas, "cascade_same_couples_V": round(meas_free, 4),
                     "cascade_device_V": round(meas_device, 4),
                     "protein_shift_V": round(fad_bound_meas - fad_free_meas, 4)},
        "forms": rows,
        "both_sided": bs,
        "cancellations": {"gap_max_V": CANCEL_GAP_V, "each_side_min_V": CANCEL_SIDE_V, "rows": cancellations},
        "not_computed": [("ZPE and thermal terms of every Os form but the adiabatic chloro one (96 corrects one form) — for "
                          "the others the ZPE and RRHO levels correct the donor only") if bs["computed"] else
                         ("ZPE and thermal terms of the Os couple (96 not run) — the ZPE and RRHO levels correct the donor "
                          "only"),
                         "protein shift of the bound cofactor (measured, carried)",
                         "polymer film of the measured mediator vs one 1-MeIm molecule",
                         "any ωB97X reading (no ωB97X PCET potential of the flavin)"],
        "verdict": verdict,
    }
    if "--dry" in sys.argv:
        print("\n  " + verdict)
        return 0
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    print("  " + verdict)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
