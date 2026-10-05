#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
82 — The running clearance of the bayonet collar in the radome's socket band (00_07 HW.33 · HW.9 root package;
crown-pause exception ⚖️ founder 2026-10-05, recorded by subject in the §01a preamble): the radial gap between the
Ti collar's OUTER face and the PEEK socket band's INNER wall that keeps the bayonet turning across the capsule
envelope — the member `52` §collar_radial_budget takes as an input and has no number for (its second column puts
the socket's 0.3 mm slot clearance there because «nothing states it»).

WHY A MODEL AND WHY THE ANSWER IS A TABLE. Physics fixes only the FLOOR of the clearance: the cold edge closes it,
because the PEEK band lies OUTSIDE the Ti collar and PEEK contracts ~5.5× more. Everything above the floor is the
manufacturing tolerance of the two surfaces, and that is set by the ROUTE (machined ⊥ moulded radome, the flange
route), which the paused vendor letters decide. So the model gives the floor exactly and the design clearance as a
function of the route, and the board ceiling for each row through `52`'s own chain — the root package then takes
the row the drawing's fit names. The root itself is NOT moved here (two root moves are ruled out; 00_07 HW.9).

MODEL (radial, at the interface diameter D = 2 × the socket band's inner radius, from `73`'s cache):
  • thermal closing  δ_T = (D/2)·(α_PEEK − α_Ti)·(T_ref − T)    for T < T_ref; negative = the gap opens.
    T_ref = 20 °C — ISO 1, the temperature at which a drawing's dimensions hold. Two cold readings: the capsule
    REQUIREMENT −40 °C (`71`'s cache) and the modelled cold edge of the isolated capsule (`81`). Plus a GRADIENT
    bound: the PEEK at the cold edge while the Ti stays at T_ref (the flange is tied to the bark, the dome
    radiates to the sky) — δ = (D/2)·α_PEEK·(T_ref − T), the largest closing any temperature split can give.
  • tolerance: the hole (PEEK band) and the shaft (Ti collar) each take their ISO 286 grade at D; the design
    clearance is the minimum gap the drawing must specify at T_ref so that the worst case (hole at its smallest,
    shaft at its largest) still clears at the cold edge:
        c_design = δ_T(cold) + roundness_hole + roundness_shaft + (IT_hole + IT_shaft)/2
    with symmetric (±IT/2) bands about the nominal gap — a drawing that puts the fit unilateral (H/f) moves the
    same total into the fundamental deviation, not out of the sum.
  • ISO 286 grades are COMPUTED from the standard's formula (i = 0.45·Dg^(1/3) + 0.001·Dg µm at the geometric
    mean Dg of the size range, IT5…IT12 = 7, 10, 16, 25, 40, 64, 100, 160 i, rounded by the standard's steps), and
    a control holds them against the published table for 18–30 mm.
  • routes (ours — the bracket axis; the vendors' answers pin the row): both machined (Ti IT7 · PEEK IT9) · machined
    Ti with a moulded PEEK band (IT7 · IT11) · a coarse moulding (IT8 · IT12); roundness per surface as declared
    in ROUTES.
  • board ceiling: `52`'s chain, design_to − 2·(t + c), at the collar wall's print floor t (`52` / `73`: the
    wall is set by printability, not strength).

DIRECTION OF EACH CHOICE, stated per quantity:
  • the requirement −40 °C (not the modelled −33.5 °C) and the gradient bound make the floor LARGER — safe;
  • α_PEEK of 450G from lib.constants; the radome grade is not chosen yet (radome_material_rfq, paused), so a
    sensitivity at 55·10⁻⁶ /K (ours — an upper plausible value for an unfilled grade) is printed beside it;
  • moisture uptake swells the PEEK band OUTWARD (the bore grows) — it opens the gap, so it is left out: dry is
    the tight case; the hot edge opens it too (printed as the maximum gap a loose row can rattle in);
  • symmetric tolerance bands with no statistical (RSS) relief — worst case, the larger clearance.

CONTROLS that can fail (raise, never warn):
  1. the computed ISO 286 grades reproduce the published values for 18–30 mm (IT5…IT12 = 9, 13, 21, 33, 52, 84,
     130, 210 µm) — a wrong formula or a wrong rounding step fails here;
  2. this script's ceiling at c = the socket slot clearance and t = the print floor equals `52`'s cached
     «ceiling_mm_if_collar_needs_running_clearance» — the same chain, read from the other side;
  3. the sign: the thermal closing is zero at T_ref and NEGATIVE at the hot edge — it fails if the interface is
     ever entered the other way round (PEEK inside the Ti), where the hot edge would be the binding one.

CAN show: the clearance floor the cold edge imposes, the design clearance per route, the maximum gap at the hot
edge, and the board ceiling each row leaves.
CANNOT show: the vendors' real tolerances (the rows are ours until they answer); capillary water held in a narrow
gap and its ice (FMEA `#26` — the drainage requirement of 02_02 §4.4 governs it, and a tighter gap holds water
higher); friction and wear of the turning fit; creep of the PEEK band under the clamp (`52` §rim_datum_creep).

Run:  python tools/in_silico/scripts/82_collar_running_clearance.py      # < 1 s
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, ALPHA_PEEK_1K, CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = "Running clearance of the bayonet collar in the radome's socket band across the capsule temperature envelope, as a function of the manufacturing route, and the board ceiling each route leaves."  # its row in the paper SI (72): English, no repo jargon

OUT = CACHE_DIR / "mechanical" / "collar_running_clearance.json"
CACHE_73 = CACHE_DIR / "mechanical" / "collar_wall_inversion.json"
CACHE_52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
CACHE_71 = CACHE_DIR / "thermal" / "capsule_envelope.json"
CACHE_81 = CACHE_DIR / "thermal" / "capsule_cold_edge_sky.json"
RADOME_CEM = REPO_ROOT / "tools/cad/cem/radome.json"

T_REF_C = 20.0                       # ISO 1 — the reference temperature of dimensional specifications
ALPHA_PEEK_SENSITIVITY_1K = 55e-6    # ours — an upper plausible CTE for an unfilled grade (the radome grade is open)
ISO286_RANGE_MM = (18.0, 30.0)       # the size step that holds the interface diameter
ISO286_MULTIPLIER = {5: 7, 6: 10, 7: 16, 8: 25, 9: 40, 10: 64, 11: 100, 12: 160}
ISO286_PUBLISHED_18_30_UM = {5: 9, 6: 13, 7: 21, 8: 33, 9: 52, 10: 84, 11: 130, 12: 210}
ROUTES = (   # (name, Ti collar grade, PEEK band grade, Ti roundness mm, PEEK roundness mm) — ours, the bracket axis
    ("machined collar · machined band", 7, 9, 0.005, 0.010),
    ("machined collar · moulded band", 7, 11, 0.005, 0.030),
    ("coarse: IT8 collar · IT12 moulded band", 8, 12, 0.010, 0.050),
)


def deg(x: float) -> str:
    """A whole-degree temperature for prose, with the typographic minus the docs quote."""
    return f"{x:.0f}".replace("-", "−")


def iso286_round(value_um: float) -> int:
    """The standard's rounding steps for computed grade values: 1 µm up to 60, 2 µm to 100, 5 µm to 200, 10 µm above."""
    step = 1 if value_um <= 60 else 2 if value_um <= 100 else 5 if value_um <= 200 else 10
    return int(step * round(value_um / step))


def iso286_grades(size_range=ISO286_RANGE_MM) -> dict:
    d_g = math.sqrt(size_range[0] * size_range[1])
    i_um = 0.45 * d_g ** (1.0 / 3.0) + 0.001 * d_g
    return {grade: iso286_round(mult * i_um) for grade, mult in ISO286_MULTIPLIER.items()}


def thermal_closing_mm(d_mm: float, alpha_outer: float, alpha_inner: float, t_outer: float, t_inner: float) -> float:
    """Radial closing of the gap between an OUTER ring (the PEEK band) and an INNER one (the Ti collar), each at its
    own temperature; positive = the gap closes."""
    r = d_mm / 2.0
    return r * (alpha_outer * (T_REF_C - t_outer) - alpha_inner * (T_REF_C - t_inner))


def main() -> int:
    banner("HW.33 — the bayonet collar's running clearance in the radome socket band (capsule envelope × route)")
    c73 = json.loads(CACHE_73.read_text())
    c52 = json.loads(CACHE_52.read_text())["collar_radial_budget"]
    t_min_req, t_max_req = json.loads(CACHE_71.read_text())["rating_c"]["capsule_requirement"]
    t_min_model = json.loads(CACHE_81.read_text())["edges"]["coldest_c"]
    slot_clear = json.loads(RADOME_CEM.read_text())["slot_clearance_mm"]
    d_mm = 2.0 * c73["geometry"]["band_r_inner_mm"]
    if not ISO286_RANGE_MM[0] < d_mm <= ISO286_RANGE_MM[1]:
        raise SystemExit(f"interface Ø{d_mm} mm left the ISO 286 size step {ISO286_RANGE_MM} — pick the step it is in")
    a_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    design_to, t_floor = c52["design_to_mm"], c52["printability_floor_mm"]

    # ── control 1: ISO 286 grades from the formula against the published table ──────────────────────────────
    it = iso286_grades()
    if it != ISO286_PUBLISHED_18_30_UM:
        raise SystemExit(f"control 1 failed: ISO 286 grades {it} ≠ published {ISO286_PUBLISHED_18_30_UM}")
    print(f"  control 1: ISO 286 IT5…IT12 at 18–30 mm = {list(it.values())} µm (= published) ✓")

    # ── control 2: the same chain as 52 ────────────────────────────────────────────────────────────────────
    def ceiling(c_mm: float, t_mm: float = t_floor) -> float:
        return round(design_to - 2.0 * (t_mm + c_mm), 2)
    want = next(r["ceiling_mm_if_collar_needs_running_clearance"] for r in c52["rows"] if r["collar_wall_mm"] == t_floor)
    if ceiling(slot_clear) != want:
        raise SystemExit(f"control 2 failed: ceiling at c = {slot_clear} gives {ceiling(slot_clear)} ≠ 52's {want}")
    print(f"  control 2: ceiling at c = slot clearance {slot_clear} mm, t = {t_floor} mm → {want} mm (= 52) ✓")

    # ── thermal members ───────────────────────────────────────────────────────────────────────────────────────
    def iso(t_c: float, a_peek: float = ALPHA_PEEK_1K) -> float:
        return thermal_closing_mm(d_mm, a_peek, a_ti, t_c, t_c)
    if iso(T_REF_C) != 0.0 or not iso(t_max_req) < 0.0:
        raise SystemExit("control 3 failed: the closing must be zero at T_ref and negative (opening) at the hot edge")
    print(f"  control 3: closing 0 at {T_REF_C:.0f} °C, {iso(t_max_req) * 1e3:+.1f} µm at {t_max_req:.0f} °C (opens) ✓")
    thermal = {
        "isothermal_requirement": iso(t_min_req),
        "isothermal_model_edge": iso(t_min_model),
        "gradient_bound_requirement": thermal_closing_mm(d_mm, ALPHA_PEEK_1K, a_ti, t_min_req, T_REF_C),
        "isothermal_requirement_alpha_sensitivity": iso(t_min_req, ALPHA_PEEK_SENSITIVITY_1K),
        "hot_edge_requirement": iso(t_max_req),
    }
    for k, v in thermal.items():
        print(f"  thermal {k:42s} {v * 1e3:+7.1f} µm radial")
    floor_closing = max(thermal["gradient_bound_requirement"], thermal["isothermal_requirement_alpha_sensitivity"])

    # ── design clearance per route ───────────────────────────────────────────────────────────────────────────
    rows = []
    for name, it_ti, it_peek, rnd_ti, rnd_peek in ROUTES:
        tol = (it[it_ti] + it[it_peek]) / 2.0 / 1000.0
        base = rnd_ti + rnd_peek + tol
        c_iso = thermal["isothermal_requirement"] + base
        c_bound = floor_closing + base
        rows.append({
            "route": name, "it_collar": it_ti, "it_band": it_peek, "it_collar_um": it[it_ti], "it_band_um": it[it_peek],
            "roundness_mm": [rnd_ti, rnd_peek], "half_tolerance_sum_mm": round(tol, 4),
            "design_clearance_isothermal_mm": round(c_iso, 3),
            "design_clearance_bound_mm": round(c_bound, 3),
            "max_gap_hot_edge_mm": round(c_bound + tol - thermal["hot_edge_requirement"], 3),
            "ceiling_isothermal_mm": ceiling(c_iso), "ceiling_bound_mm": ceiling(c_bound),
        })
        r = rows[-1]
        print(f"  {name:40s} c {r['design_clearance_isothermal_mm']:.3f}–{r['design_clearance_bound_mm']:.3f} mm · "
              f"ceiling {r['ceiling_bound_mm']:.2f}–{r['ceiling_isothermal_mm']:.2f} mm · hot gap ≤ {r['max_gap_hot_edge_mm']:.3f}")

    # ── verdict, built from the numbers (in-silico §When Modifying #5) ──────────────────────────────────────────
    lo, hi = rows[0], rows[-1]
    above = all(r["design_clearance_bound_mm"] < slot_clear for r in rows)
    clause = (f"every row stays below the {slot_clear} mm that 52 puts there for want of a number" if above else
              f"a row reaches the {slot_clear} mm that 52 puts there for want of a number")
    verdict = (f"The cold edge closes the collar's running clearance by {thermal['isothermal_requirement'] * 1e3:.0f} µm "
               f"radially at the capsule requirement {deg(t_min_req)} °C (both parts at it), "
               f"{thermal['gradient_bound_requirement'] * 1e3:.0f} µm if the Ti stays at {T_REF_C:.0f} °C — that is the "
               f"physics floor. The design clearance the drawing must specify is the floor plus the tolerance of the "
               f"route: {lo['design_clearance_isothermal_mm']:.3f}–{lo['design_clearance_bound_mm']:.3f} mm with both "
               f"surfaces machined, up to {hi['design_clearance_isothermal_mm']:.3f}–{hi['design_clearance_bound_mm']:.3f} mm "
               f"for a coarse moulding — {clause}; at the print-floor wall {t_floor} mm the board ceiling becomes "
               f"{hi['ceiling_bound_mm']:.2f}–{lo['ceiling_isothermal_mm']:.2f} mm instead of {want:.2f} "
               f"(design_to {design_to:.2f}). The row is the drawing's fit, and the route that pins it is the vendors'.")
    print(f"\n  {verdict}")

    out = {
        "question": "radial running clearance of the bayonet collar in the radome socket band across the capsule "
                    "envelope, per manufacturing route, and the board ceiling it leaves (00_07 HW.33 / HW.9)",
        "interface": {"diameter_mm": round(d_mm, 3), "from": "73 geometry.band_r_inner_mm × 2",
                      "outer": "PEEK socket band (radome)", "inner": f"collar ({ALLOY_BASELINE})"},
        "inputs": {
            "t_ref_c": T_REF_C, "t_min_requirement_c": t_min_req, "t_max_requirement_c": t_max_req,
            "t_min_model_edge_c": t_min_model, "alpha_peek_1K": ALPHA_PEEK_1K,
            "alpha_peek_sensitivity_1K": ALPHA_PEEK_SENSITIVITY_1K, "alpha_ti_1K": a_ti,
            "design_to_mm": design_to, "collar_wall_print_floor_mm": t_floor, "slot_clearance_mm": slot_clear,
            "routes": [list(r) for r in ROUTES], "routes_are": "ours — the bracket axis until the vendors answer",
        },
        "iso286_grades_18_30_um": {f"IT{k}": v for k, v in it.items()},
        "thermal_closing_mm": {k: round(v, 4) for k, v in thermal.items()},
        "floor_closing_mm": round(floor_closing, 4),
        "routes": rows,
        "controls": {"iso286_matches_published": True, "chain_equals_52": {"c_mm": slot_clear, "t_mm": t_floor,
                                                                            "ceiling_mm": want},
                     "closing_sign": "zero at T_ref, opening at the hot edge"},
        "verdict": verdict,
        "ceilings": [
            "the routes' grades and roundness are ours until the vendors answer (DMLS / CNC / moulding letters, paused)",
            "the radome PEEK grade is open — the CTE sensitivity row stands for it",
            "capillary water in a narrow gap and its ice are not modelled — the drainage requirement governs them",
            "friction, wear and creep of the turning fit are not modelled",
        ],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"\n  wrote {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
