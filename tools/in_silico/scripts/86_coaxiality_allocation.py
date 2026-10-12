#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""86 — what a channel-to-root misalignment costs the bus root once the static bending is treated as a MEAN stress
(00_07 HW.34, «число співвісності»; ⚖️ founder 2026-10-12: exception to the crown pause for this question).

WHY. A Zone-3 channel axis off the bus root axis by more than the radial play makes the bore mouth a contact station
and puts a STATIC bending on the root (script 68, `offset_static_shipped_branch`). Until now the tree had no mean-stress
correction, so the coaxiality NUMBER could not be priced: a tight allocation (offset inside the play, no mean at all)
was the only branch with a price, and the ratified FORM (01_01 §1.4 «Співвісність») waited. The condition written there
in advance — «if G1 lands inside the lock window, the cheap offset may make a loose tolerance better than a tight one» —
fired on 2026-10-12 (G1: 0.64 MPa per µm past the play instead of the placeholder's 5.74). This script prices both.

MODEL. Soderberg, per alloy and per allowed radial offset e of the channel axis from the root axis:
    1/SF_wire = σ_a/σ_e + σ_m/σ_y
and the seam knock-down k a weld must carry for the joint to keep the infinite-life line SF_target:
    k_break_even = σ_a / (σ_e · (1/SF_target − σ_m/σ_y))      (no k exists once σ_m/σ_y ≥ 1/SF_target)
  * σ_y — lib.constants; σ_e — script 55's `endurance_MPa` on the WELDED branch (cold-drawn wire, ratified ratio 0.40);
    SF_target — 55's INFINITE_LIFE_SF. Nothing typed here.
  * σ_m(e) — 68's static root stress at offset e, the WORST over the six plays 68 sweeps (zero interference + the five
    rows of 55's interference window), per geometry.
  * σ_a — the UPPER end of 68's coaxial bracket at the worst swept µ (the Ti-bore stop), the worst over the same plays.
    Under an offset the mouth contact shortens the span, so the real amplitude is likely lower; 68's rigid-wall
    reversing amplitude (≤ 4.2 MPa) is the other end and is NOT used.
  The three choices are each the conservative one, so every SF here is a LOWER bound and every k_break_even an UPPER
  bound on what the joint must carry — for the model's inputs; see the ceilings.

CONTROLS (the run aborts when one fails):
  1. σ_e/σ_a computed here on the ZERO-INTERFERENCE play must equal script 55's `binding_alloy_sf_shipped_at_upper_end`
     for its binding alloy on the shipped geometry (one quantity, two scripts — 55 prices that one play; the amplitude
     used below is the worst over all six, so the published zero-offset SF sits slightly under 55's);
  2. along the offset grid the mean is non-decreasing, SF_wire non-increasing and k_break_even non-decreasing;
  3. offsets inside the smallest play carry no mean on any play.

DECLARED CEILINGS — read before quoting a number:
  * Soderberg (yield line) is more conservative than Goodman; the tree has no ultimate strength per alloy, so
    Goodman cannot be run — the conservatism is a choice forced by the inputs, not a measurement.
  * WELD RESIDUAL TENSION is itself a mean stress, and this file does not carry it: it adds to σ_m and RAISES every
    k_break_even row. The vendor's k must therefore say whether it was measured with the post-weld treatment we ship.
  * The weld-toe notch and the bead section (01_01 §1.4) stay outside, as everywhere in the tree.
  * The seam row divides the mean by the WIRE's yield: the heat-affected zone of a Ti weld can yield differently, and
    no number for it exists here — a lower HAZ yield raises the k rows too.
  * The mean is 68's RIGID-wall figure — an upper bound under an offset (a compliant mouth relieves it).
  * What tightening costs in machining and inspection is NOT priced here — that is the other side of the allocation.
"""
from __future__ import annotations

import importlib.util
import json
import sys
from itertools import pairwise
from pathlib import Path

SI_DESCRIPTION = "What a channel-to-root misalignment costs the bus root with a Soderberg mean-stress correction."

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import ALLOY_PROPERTIES, CACHE_DIR, REPO_ROOT
from lib.utils import banner

_spec = importlib.util.spec_from_file_location("bus55", HERE / "55_bus_mechanical.py")
s55 = importlib.util.module_from_spec(_spec)
sys.modules["bus55"] = s55   # a dataclass under `from __future__ import annotations` resolves its module by name
_spec.loader.exec_module(s55)

BUS68 = CACHE_DIR / "mechanical" / "bus_contact_equilibrium.json"
BUS55 = CACHE_DIR / "mechanical" / "bus_mechanical.json"
OUT_JSON = CACHE_DIR / "mechanical" / "coaxiality_allocation.json"
# Allocation branches, each a TOTAL radial offset budget of the channel axis from the root axis (µm). The ISO 1101
# coaxiality zone is the diameter, 2·e. 20 = the largest point of 68's grid inside the smallest swept play (21.2 µm,
# wire carrying the interference at the window ceiling); 50 and 100 = the two loose points 68 already solves.
BRANCHES_UM = {"tight": 20, "loose_50": 50, "loose_100": 100}


def soderberg(sigma_a: float, sigma_m: float, sigma_e: float, sigma_y: float) -> tuple[float, float | None]:
    sf = 1.0 / (sigma_a / sigma_e + sigma_m / sigma_y)
    room = 1.0 / s55.INFINITE_LIFE_SF - sigma_m / sigma_y
    return sf, (sigma_a / (sigma_e * room) if room > 0 else None)


def main() -> int:
    banner("HW.34 — coaxiality allocation: a channel offset as a MEAN stress (Soderberg), per alloy and geometry")
    d68 = json.loads(BUS68.read_text(encoding="utf-8"))
    d55 = json.loads(BUS55.read_text(encoding="utf-8"))
    geos = [g["label"] for g in d68["inputs"]["geometries"]]
    alloys = {name: (p["yield_MPa"], s55.endurance_MPa(p["yield_MPa"], derate=s55.WROUGHT_DERATE))
              for name, p in sorted(ALLOY_PROPERTIES.items(), key=lambda kv: -kv[1]["yield_MPa"])}
    min_play = min(o["radial_play_um"] for o in d68["offset_static_shipped_branch"])
    out_geo = {}
    for geo in geos:
        offs = [o for o in d68["offset_static_shipped_branch"] if o["geometry"] == geo]
        grid = [p["offset_um"] for p in offs[0]["by_offset"]]
        mean = {e: max(next(p["sigma_root_MPa"] for p in o["by_offset"] if p["offset_um"] == e) for o in offs) for e in grid}
        liner = [r for r in d68["drag_coaxial"] if r["geometry"] == geo and r["branch"].startswith("PEEK liner")]
        amp = max(r["by_mu"]["0.5"]["sigma_root_MPa_upper_end"] for r in liner)
        amp_zero = next(r for r in liner if r["play"] == "zero interference")["by_mu"]["0.5"]["sigma_root_MPa_upper_end"]
        if any(mean[e] != 0.0 for e in grid if e < min_play):
            raise SystemExit(f"control 3: an offset inside the smallest play ({min_play} µm) carries a mean on {geo}")
        rows = {}
        for name, (sy, se) in alloys.items():
            per = []
            for e in grid:
                sf, k = soderberg(amp, mean[e], se, sy)
                per.append({"offset_um": e, "mean_MPa": mean[e], "sf_wire": round(sf, 3),
                            "k_break_even": None if k is None else round(k, 4)})
            for a, b in pairwise(per):
                if b["mean_MPa"] < a["mean_MPa"] or b["sf_wire"] > a["sf_wire"] or (
                        a["k_break_even"] is not None and b["k_break_even"] is not None
                        and b["k_break_even"] < a["k_break_even"]):
                    raise SystemExit(f"control 2: not monotone on {geo}/{name} at {b['offset_um']} µm")
            rows[name] = {"yield_MPa": sy, "endurance_MPa": se, "by_offset": per}
        out_geo[geo] = {"amplitude_MPa": amp, "amplitude_zero_interference_MPa": amp_zero, "amplitude_is": "upper end of 68's coaxial bracket at the worst swept µ, "
                        "worst over the six plays (Ti-bore stop)", "mean_is": "68's rigid-wall static root stress, worst "
                        "over the six plays", "by_alloy": rows}

    shipped = out_geo[geos[0]]
    binding = min(shipped["by_alloy"], key=lambda n: shipped["by_alloy"][n]["by_offset"][0]["sf_wire"])
    sf0 = round(shipped["by_alloy"][binding]["endurance_MPa"] / shipped["amplitude_zero_interference_MPa"], 3)
    s55_sf0 = d55["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"][0]["binding_alloy_sf_shipped_at_upper_end"]
    if abs(sf0 - s55_sf0) > 0.01:
        raise SystemExit(f"control 1: zero-mean SF {sf0:.3f} ≠ script 55's {s55_sf0} for {binding}")

    branches = {}
    for bname, e in BRANCHES_UM.items():
        per_geo = {}
        for geo in geos:
            rows = out_geo[geo]["by_alloy"]
            at = {n: next(p for p in r["by_offset"] if p["offset_um"] == e) for n, r in rows.items()}
            worst = min(at, key=lambda n: at[n]["sf_wire"])
            ks = [p["k_break_even"] for p in at.values()]
            per_geo[geo] = {"binding_alloy": worst, "mean_MPa": at[worst]["mean_MPa"], "sf_wire_binding": at[worst]["sf_wire"],
                            "k_break_even_binding": at[worst]["k_break_even"],
                            "k_break_even_max_over_alloys": None if None in ks else max(ks)}
        branches[bname] = {"radial_offset_budget_um": e, "iso1101_coaxiality_zone_mm": round(2 * e / 1000.0, 3),
                           "by_geometry": per_geo}

    t = branches["tight"]["by_geometry"][geos[0]]
    for bname in ("loose_50", "loose_100"):
        b = branches[bname]["by_geometry"][geos[0]]
        print(f"  {bname:>9s} (⌀{branches[bname]['iso1101_coaxiality_zone_mm']:.2f}): binding {b['binding_alloy']} — mean "
              f"{b['mean_MPa']:.1f} MPa · SF wire {t['sf_wire_binding']:.2f} → {b['sf_wire_binding']:.2f} · seam k ≥ "
              f"{t['k_break_even_binding']:.3f} → {b['k_break_even_binding']:.3f}")
    out = {
        "question": "00_07 HW.34 — what a channel-to-root misalignment costs the bus root once its static bending is a "
                    "MEAN stress, so that the coaxiality NUMBER can be allocated (⚖️ 2026-10-12 exception to the crown pause)",
        "model": "Soderberg: 1/SF = σ_a/σ_e + σ_m/σ_y; k_break_even = σ_a / (σ_e·(1/SF_target − σ_m/σ_y))",
        "inputs": {"script68_cache": str(BUS68.relative_to(REPO_ROOT)), "endurance": "script 55 endurance_MPa, welded "
                   "branch (WROUGHT_DERATE), ratified ratio", "endurance_over_yield": s55.ENDURANCE_OVER_YIELD,
                   "sf_target": s55.INFINITE_LIFE_SF, "smallest_swept_play_um": min_play},
        "by_geometry": out_geo,
        "branches": branches,
        "controls": {"zero_mean_sf_equals_script55": {"alloy": binding, "sf": sf0, "script55": s55_sf0},
                     "monotone_in_offset": True, "no_mean_inside_smallest_play": True},
        "not_modelled": {
            "goodman": "no ultimate strength per alloy in the tree, so the yield line (Soderberg) is used — conservative",
            "weld_residual_tension": "a mean stress this file does not carry; it raises every k_break_even row",
            "weld_toe_notch_and_bead": "outside, as everywhere in the tree (01_01 §1.4)",
            "haz_yield": "the seam row divides the mean by the wire's yield; a lower heat-affected-zone yield raises it",
            "tightening_cost": "machining and inspection cost of a tighter allocation — the other side of the choice",
            "compliant_mouth": "the mean is a rigid-wall upper bound under an offset",
        },
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
