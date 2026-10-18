#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""90 — the pogo gap's thermal travel: how temperature moves the pins' working compression, seasonally and daily, and
whether `52`'s mitigations still hold the mid-stroke window (00_07 HW.43, the leg «тепловий хід зазору pogo — вісь,
якої в `52` немає»; `87` prices sway, this prices heat and cold).

QUESTION. `52` budgets the Power-Deck ↔ Zone-3 gap at one temperature: the pins sit at 60 % of their travel at the
nominal gap, the window is 50–70 %, and the minimal mitigation that passes (a measured spacer) leaves ±0.112 mm. The gap
is the difference of two columns that expand differently — the radome's PEEK from the rim to the pocket floor, and the
board stack hanging from that floor — so temperature moves it, and the window margin left after the mitigation is the
budget it eats.

PATHS (rule 15 (a)–(b)). Along Z, between the flange face (the pads; also the rim's datum) and the pins' tips: (1) the
radome PEEK from the rim face to the pocket floor, H = pocket_floor_over_rim (a PLACEHOLDER, 00_07 HW.29) — up with
heat; PREMISE: the rim stays seated on the flange face (script 89: a stiff clamp loop unloads in the cold, and a lifted
rim moves the datum to the lug ledge, where `52`'s residual no longer applies); (2) the stack hanging from that floor — two FR-4 decks (Z CTE, Panasonic R-1755M/V) and the steel standoffs between
them (⚖️ 2026-10-05, poz. 25: no screws, WA-SMSI «tinned steel», no grade → mild steel, stainless 302 as the other end;
if the B2B pair beside them bottoms out instead — standoff 8.0 against a mated 8.13 mm, 02_01 — its LCP body sets the
spacing, so the script states the spacer CTE at which L1's margin reaches zero) — down with heat, so the gap is
H·α_PEEK − Σ(L·α); PREMISE: the stack is SEATED on the floor — in fact it floats on a force balance of the pogo pair
(≈ 0.8–1.9 N) against the pocket gasket (of the same order), two springs in series that set the working point and shrink
the thermal stroke; (3) the pocket gasket between the RF deck and the floor (EPDM, its compressed height a PLACEHOLDER 0,
HW.32) — as a CTE term, named, not computed; (4) the pin's own body below the board — brass C36000 (CDA, 20.5 ppm/K,
a 20–300 °C mean). The window is geometric: the compression is the pin's FREE length less the gap, so what moves the
tip is the free length — 52's POGO_FREE, the barrel from the mount to its lip plus the plunger from its stop to the
tip, taken as one brass column (the BeCu spring inside does not set the length) — and the WORKING STROKE moves by the
gap's coefficient minus that column's; in the radome-leads reading the stack and the pin stay put, so there it is the
radome alone; (5) the flange: the pads and the rim seat share its
face, so its Ti does not enter thermally (52's DMLS Ti term is a static tolerance). Radially: (6) what holds the stack in-plane is not modelled: if the radome (PEEK) holds it,
a pin at radius r slides by (α_PEEK − α_Ti)·r per kelvin (the upper reading); if the pins follow the board's own in-plane
expansion, α_PEEK becomes FR-4's in-plane CTE, 11–15 ppm/K (Panasonic R-1755M/V); both printed per mm of radius, the
outer pad's radius being the layout's (HW.9); the
centre pad (the bus-wire end, r = 0) does not slide. (7) The centre pad's own path — the Ti wire
inside the PEEK sleeve between the Zone 1↔2 press-fit and the liner grip — loads the wire and, as the wire slips in the
liner near its held end, moves the pad; 87 computes the ceiling the liner wall puts on that axial force, not the split
(HW.34/HW.43), named only here — so every window statement here is about the OUTER pad: the centre pad's axial position
rides on that path, and a slipping grip moves it by tens of µm on 20 K (00_07 HW.43). (8) The B2B pair beside the standoffs strains by their mismatch — not the pins'.

READINGS. Temperatures: the capsule requirement (−40…85 °C, `82`) and the models' edges (`81`'s −33.5 °C; `71`'s 55.0 °C
for the canon finish α ≤ 0.5, a lumped mean), assembly at 20 °C. Isothermal (radome and stack together) and a radome-leads
READING (the radome moves, the stack stays) — not a bound: the floor hangs from the dome top through ~3 mm of chamber wall,
so a lagging wall can push the lead higher. The daily cycle: `71`'s hourly capsule temperature over 30 ERA5 years
(sunlit, α 0.5, the aging wind factor), its daily range — a READING whose error has no known sign on the range: `71`
takes the worst direct-sun gain (the day's peak up) and has no night-sky cooling (the night's minimum up), and as one
lump with an adiabatic base it cannot give a shell/stack lag. Only `52`'s MINIMAL mitigation (the spacer, L1) is judged
here; whether its second lever (the bayonet hard-stop) still acts under branch (а), where the rim seats the radome, is
`52`'s question for the root-package re-run (canon keeps it live, 02_02 §3.5), not this script's.

CAN show: the gap's thermal coefficient and seasonal swing, the window check at `52`'s two mitigations with it, the
daily stroke and its force ratio over the minimum preload (as `87` prices sway), the radial slide per mm of pad radius.
CANNOT show: the pocket gasket's term (placeholder), the pin body's beyond one brass column at a 20–300 °C mean CTE,
the spring force's own temperature dependence (the force ratio takes force ∝ stroke at a fixed rate, while the BeCu
spring's modulus falls with temperature — no figure in the tree), the stack's real centring, the
centre pad's wire path, a gradient inside the stack.
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_BRASS_C36000_1K,
    ALPHA_FR4_XY_1K,
    ALPHA_FR4_Z_1K,
    ALPHA_PEEK_1K,
    ALPHA_SS302_1K,
    ALPHA_STEEL_MILD_1K,
    CACHE_DIR,
)
from lib.utils import banner

SI_DESCRIPTION = ("How heat and cold change how hard the spring contacts press on the anchor — over a season and over "
                  "a day — and whether the assembly's tolerance budget still leaves room for it.")

ZSTACK52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
CLEAR82 = CACHE_DIR / "mechanical" / "collar_running_clearance.json"
CAPSULE71 = CACHE_DIR / "thermal" / "capsule_envelope.json"
RADOME_CEM = HERE.parent.parent / "cad" / "cem" / "radome.json"
OUT_JSON = CACHE_DIR / "mechanical" / "pogo_thermal_gap.json"

DAILY_ALPHA = 0.5        # canon finish α ≤ 0.5 (02_01, ⚖️ delegated 2026-09-27)
DAILY_CASE = "sunlit"


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S52 = _load("s52_zstack", "52_z_stack_tolerance.py")
S71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")


def main() -> int:
    banner("HW.43 — the pogo gap's thermal travel: seasonal swing vs 52's window, daily stroke, radial slide")
    z52 = json.loads(ZSTACK52.read_text(encoding="utf-8"))
    c82 = json.loads(CLEAR82.read_text(encoding="utf-8"))
    c71 = json.loads(CAPSULE71.read_text(encoding="utf-8"))
    radome = json.loads(RADOME_CEM.read_text(encoding="utf-8"))

    vin = z52["vertical_stack_budget"]["inputs_mm"]
    gap, fr4, standoff = vin["gap_pz"], vin["fr4_bom"], vin["b2b_bom"][0]
    h_floor = radome["pocket_floor_over_rim_mm"]
    assert abs(gap + 2 * fr4 + standoff - h_floor) < 1e-6, "52's chain no longer closes on the radome's pocket floor"
    travel, win = S52.POGO_TRAVEL, S52.POGO_WIN
    nominal_pct = (S52.POGO_FREE - S52.GAP_PZ) / travel
    x_preload_min = win[0] * travel                              # the smallest working compression — 87's denominator

    a_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    radome_um_k = ALPHA_PEEK_1K * h_floor * 1e3                  # µm/K, up with heat
    stack_um_k = {"low": 2 * fr4 * ALPHA_FR4_Z_1K[0] * 1e3 + standoff * ALPHA_STEEL_MILD_1K * 1e3,
                  "high": 2 * fr4 * ALPHA_FR4_Z_1K[1] * 1e3 + standoff * ALPHA_SS302_1K * 1e3}
    gap_um_k = {"isothermal_low_stack": radome_um_k - stack_um_k["high"],     # the smaller net coefficient
                "isothermal_high_stack": radome_um_k - stack_um_k["low"],
                "radome_leads_reading": radome_um_k}
    pin_body_mm = S52.POGO_FREE                                  # the FREE length moves the tip: stroke = free − gap
    pin_um_k_per_ppm = pin_body_mm * 1e-6 * 1e3                 # µm/K per 1 ppm/K of the pin's CTE
    pin_um_k = pin_body_mm * ALPHA_BRASS_C36000_1K * 1e3        # µm/K — the brass body, down with heat
    # the WORKING STROKE (what the pins' compression follows): the gap's opening minus the body's growth; when the
    # radome leads, the stack and the pin stay put, so there it is the radome's alone
    stroke_um_k = {"isothermal_low_stack": gap_um_k["isothermal_low_stack"] - pin_um_k,
                   "isothermal_high_stack": gap_um_k["isothermal_high_stack"] - pin_um_k,
                   "radome_leads_reading": radome_um_k}

    t_asm = c82["inputs"]["t_ref_c"]
    hot_model = c71["hot_bound_h_c_sensitivity"]["sunlit_still_air"][f"{DAILY_ALPHA:.2f}"]["t_cap_max_c"]
    readings = {"capsule_requirement": (c82["inputs"]["t_min_requirement_c"], c82["inputs"]["t_max_requirement_c"]),
                "model_edges": (c82["inputs"]["t_min_model_edge_c"], hot_model)}
    mitig = {m["label"]: m["residual_pz"] for m in z52["mitigation_escalation"]}

    seasonal = {}
    for rname, (t_min, t_max) in readings.items():
        per = {}
        for cname, coeff in gap_um_k.items():
            cold_um = -coeff * (t_asm - t_min)             # gap change in the cold (negative: the gap closes)
            hot_um = coeff * (t_max - t_asm)
            s_cold, s_hot = -stroke_um_k[cname] * (t_asm - t_min), stroke_um_k[cname] * (t_max - t_asm)
            # the pins' compression moves opposite to the gap
            comp_cold_pct, comp_hot_pct = -s_cold * 1e-3 / travel, -s_hot * 1e-3 / travel
            checks = {}
            for label, res in mitig.items():
                hi = nominal_pct + res / travel + comp_cold_pct        # residual closes the gap AND the cold closes it
                lo = nominal_pct - res / travel + comp_hot_pct
                checks[label] = {"compression_pct_range": [round(lo * 100, 2), round(hi * 100, 2)],
                                 "holds_window": bool(win[0] <= lo and hi <= win[1]),
                                 "margin_um": [round((lo - win[0]) * travel * 1e3, 1), round((win[1] - hi) * travel * 1e3, 1)]}
            per[cname] = {"gap_um_cold": round(cold_um, 1), "gap_um_hot": round(hot_um, 1),
                          "stroke_um_cold": round(s_cold, 1), "stroke_um_hot": round(s_hot, 1), "window": checks}
        seasonal[rname] = per

    # Daily: 71's hourly capsule temperature, reproduced from its own code and checked against its cache.
    h = S71.load_hours()
    geo = S71.geometry()
    a_proj, a_exp, d_m = geo["a_proj_max_mm2"] * 1e-6, geo["a_exp_mm2"] * 1e-6, geo["dome_diameter_mm"] * 1e-3
    k_wind = c71["inputs"]["wind_k_typical_for_aging"]
    q = DAILY_ALPHA * (1.0 * h["dni"] * a_proj + S71.SKY_VIEW * h["dif"] * a_exp)
    t_cap = S71.solve_t_cap(h["t_air"], q, a_exp, d_m, k_wind * h["u10"])
    want = c71["hot_bound"][DAILY_CASE][f"{DAILY_ALPHA:.2f}"][f"{k_wind:.1f}"]["t_cap_max_c"]
    if abs(round(float(t_cap.max()), 1) - want) > 0.05:
        raise SystemExit(f"71 does not reproduce its own cache: {t_cap.max():.2f} vs {want}")
    days = np.array([t[:10] for t in h["time"]])
    _, idx = np.unique(days, return_index=True)
    bounds = [*idx.tolist(), len(days)]
    ranges = np.array([t_cap[a:b].max() - t_cap[a:b].min() for a, b in itertools.pairwise(bounds)
                       if b - a >= 20])
    stats = {"median": float(np.median(ranges)), "p95": float(np.percentile(ranges, 95)), "max": float(ranges.max())}
    daily = {}
    for cname, coeff in stroke_um_k.items():
        daily[cname] = {s: {"stroke_um": round(coeff * v, 2),
                            "force_ratio_over_min_preload": round(coeff * v * 1e-3 / x_preload_min, 4)}
                        for s, v in stats.items()}
    slide_um_per_mm_k = {"isothermal": (ALPHA_PEEK_1K - a_ti) * 1e3, "flange_held": ALPHA_PEEK_1K * 1e3,
                         # the pins following the board's own in-plane expansion instead (FR-4, both ends)
                         "board_isothermal_low": (ALPHA_FR4_XY_1K[0] - a_ti) * 1e3,
                         "board_isothermal_high": (ALPHA_FR4_XY_1K[1] - a_ti) * 1e3,
                         "board_flange_held_high": ALPHA_FR4_XY_1K[1] * 1e3}
    slide_daily_um_per_mm = {k: {s: round(v * stats[s], 3) for s in stats} for k, v in slide_um_per_mm_k.items()}

    req = seasonal["capsule_requirement"]
    l1 = "L1 spacer only"
    # a radome that LEADS the stack by g kelvin adds (stack + pin)·g to the stroke change (the pin lags with the stack), so
    # L1's isothermal margin tolerates g ≤ margin / (stack + pin), each isothermal case with its OWN stack, the smaller
    case_stack = {"isothermal_low_stack": stack_um_k["high"] + pin_um_k, "isothermal_high_stack": stack_um_k["low"] + pin_um_k}
    leads = [min(req[c]["window"][l1]["margin_um"]) / st for c, st in case_stack.items()
             if min(req[c]["window"][l1]["margin_um"]) > 0]
    lead_tolerated_k = min(leads) if leads else None
    # the spacer CTE at which L1's isothermal margin reaches zero (the B2B body instead of the steel standoff)
    t_min_r, t_max_r = readings["capsule_requirement"]
    room_um = ((win[1] - nominal_pct) * travel - mitig[l1]) * 1e3            # to each window edge after the residual
    coef_allowed = min(room_um / (t_max_r - t_asm), room_um / (t_asm - t_min_r))
    spacer_alpha_zero = {f"fr4_{int(a * 1e6)}": (radome_um_k - 2 * fr4 * a * 1e3 - pin_um_k - coef_allowed) / (standoff * 1e3)
                         for a in ALPHA_FR4_Z_1K}                       # 52's RSS residual; a linear one leaves no room
    iso_hi, grad = req["isothermal_high_stack"], req["radome_leads_reading"]
    verdict = (
        f"The gap is the radome's PEEK column ({h_floor:.2f} mm to the pocket floor) minus the board stack hanging from it, "
        f"so it moves by {gap_um_k['isothermal_low_stack']:.2f}–{gap_um_k['isothermal_high_stack']:.2f} µm/K with both "
        f"together and {gap_um_k['radome_leads_reading']:.2f} µm/K when the radome leads: over the capsule "
        f"requirement it closes by up to {-iso_hi['gap_um_cold']:.0f} µm in the cold and opens by "
        f"{iso_hi['gap_um_hot']:.0f} µm in the heat ({-grad['gap_um_cold']:.0f} / {grad['gap_um_hot']:.0f} µm with the "
        f"radome-leads reading). The pins' working stroke follows the gap less the growth of their own brass body "
        f"({pin_um_k:.3f} µm/K, C36000 at 20.5 ppm/K over its {pin_body_mm:.2f} mm free length): {stroke_um_k['isothermal_low_stack']:.2f}–"
        f"{stroke_um_k['isothermal_high_stack']:.2f} µm/K together, the radome's {stroke_um_k['radome_leads_reading']:.2f} "
        f"µm/K when it leads. Against 52's minimal mitigation ({l1}, ±{mitig[l1]:.3f} mm, which leaves "
        f"{(win[1] - nominal_pct) * travel * 1e3 - mitig[l1] * 1e3:.0f} µm to each window edge) the isothermal swing "
        f"{'holds' if iso_hi['window'][l1]['holds_window'] else 'breaks'} the 50–70 % window (margins "
        f"{iso_hi['window'][l1]['margin_um'][0]:.0f} / {iso_hi['window'][l1]['margin_um'][1]:.0f} µm) and the radome-leads "
        f"reading {'holds' if grad['window'][l1]['holds_window'] else 'breaks'} it "
        f"({grad['window'][l1]['margin_um'][0]:.0f} / {grad['window'][l1]['margin_um'][1]:.0f} µm) — L1 tolerates a radome "
        f"leading the stack by about {lead_tolerated_k:.0f} K at the extremes, and its isothermal margin reaches zero only "
        f"for a spacing member of CTE {max(spacer_alpha_zero.values()) * 1e6:.1f}…{min(spacer_alpha_zero.values()) * 1e6:.1f} "
        f"ppm/K (if the B2B body, not the steel standoff, sets the spacing — its LCP CTE is not in the tree), against 52's "
        f"RSS residual — a linear sum of the same two terms (±0.15 mm) leaves no room even at the assembly temperature. "
        f"This is the OUTER pad, with the rim and the stack seated: the centre pad rides on the wire path (HW.34). "
        f"Daily, 71's capsule (a reading — its error on the range has no known sign) swings by a median "
        f"{stats['median']:.1f} K and a 95th percentile {stats['p95']:.1f} K, a pin stroke of "
        f"{min(v['median']['stroke_um'] for v in daily.values()):.1f}–{max(v['p95']['stroke_um'] for v in daily.values()):.1f} µm "
        f"— {min(v['median']['force_ratio_over_min_preload'] for v in daily.values()) * 100:.1f}–"
        f"{max(v['p95']['force_ratio_over_min_preload'] for v in daily.values()) * 100:.1f} % of the minimum preload "
        f"once a day — and, if the radome holds the stack in-plane, a pin at radius r slides by "
        f"{slide_daily_um_per_mm['isothermal']['p95']:.2f}–{slide_daily_um_per_mm['flange_held']['p95']:.2f} µm per mm of r "
        f"on a 95th-percentile day — {slide_daily_um_per_mm['board_isothermal_low']['p95']:.2f}–"
        f"{slide_daily_um_per_mm['board_flange_held_high']['p95']:.2f} µm if the pins follow the board's own in-plane "
        f"expansion (FR-4 11–15 ppm/K). The thermal swing is added linearly to 52's RSS residual (a systematic term on a "
        f"statistical one — the conservative stacking), and the one axial term still not computed SHRINKS it — the pocket "
        f"gasket (placeholder) expands as the PEEK does and pushes the stack the other way — so, for a given temperature "
        f"field and the seated premises, leaving it out keeps the stroke an upper estimate (the radome-leads reading and "
        f"71's daily range are readings, not bounds). Not computed either: the stack's real "
        f"centring and the centre pad's wire path (HW.34).")

    out = {
        "question": "How temperature moves the pogo pins' working compression, seasonally and daily, and whether 52's "
                    "mitigations still hold the 50–70 % window.",
        "inputs": {"pocket_floor_over_rim_mm_placeholder": h_floor, "gap_mm_52": gap, "fr4_deck_mm_52": fr4,
                   "standoff_mm_52": standoff, "pogo_travel_mm": travel, "window": list(win),
                   "nominal_pct": round(nominal_pct, 4), "x_preload_min_mm": round(x_preload_min, 3),
                   "alpha_peek_1K": ALPHA_PEEK_1K, "alpha_ti_1K": a_ti, "alpha_fr4_z_1K": list(ALPHA_FR4_Z_1K),
                   "alpha_steel_1K": [ALPHA_STEEL_MILD_1K, ALPHA_SS302_1K],
                   "mitigation_residual_mm_52": mitig, "assembly_temperature_c": t_asm,
                   "temperature_readings_c": {k: list(v) for k, v in readings.items()},
                   "daily_series": f"71: {DAILY_CASE}, α {DAILY_ALPHA}, wind factor {k_wind}, ERA5 1991–2020 hourly; "
                                   f"no night-sky cooling — a reading whose error on the range has no known sign",
                   "pin_free_length_mm": round(pin_body_mm, 3), "alpha_brass_c36000_1K": ALPHA_BRASS_C36000_1K,
                   "alpha_fr4_xy_1K": list(ALPHA_FR4_XY_1K)},
        "coefficients_um_per_K": {"radome": round(radome_um_k, 4), "stack": {k: round(v, 4) for k, v in stack_um_k.items()},
                                  "gap": {k: round(v, 4) for k, v in gap_um_k.items()},
                                  "pin_body_per_ppm": round(pin_um_k_per_ppm, 5), "pin_body": round(pin_um_k, 4),
                                  "working_stroke": {k: round(v, 4) for k, v in stroke_um_k.items()}},
        "seasonal": seasonal,
        "radome_lead_tolerated_by_L1_K": round(lead_tolerated_k, 1) if lead_tolerated_k else None,
        "spacer_alpha_1K_at_zero_L1_margin": {k: round(v, 8) for k, v in spacer_alpha_zero.items()},
        "premises": ["the rim stays seated on the flange face (89: the cold unloads a stiff clamp)",
                     "the stack is seated on the pocket floor (it floats on the pogo pair against the pocket gasket)",
                     "the OUTER pad only — the centre pad rides on the wire path (HW.34)",
                     "only 52's minimal mitigation (L1, the spacer) is judged; whether L2 acts under branch (а) is 52's "
                     "question (canon keeps it live)"],
        "daily_capsule_range_K": {k: round(v, 2) for k, v in stats.items()},
        "daily_days": len(ranges),
        "daily": daily,
        "radial_slide_um_per_mm_radius_per_K": {k: round(v, 4) for k, v in slide_um_per_mm_k.items()},
        "radial_slide_daily_um_per_mm_radius": slide_daily_um_per_mm,
        "missing_data": ["the pocket gasket's compressed height (placeholder 0, HW.32) and its EPDM expansion",
                         "the pin body beyond one brass column at a 20–300 °C mean CTE (C36000, CDA)",
                         "the pocket floor height itself (placeholder, HW.29)",
                         "what centres the stack radially, and the outer pad's radius (layout, HW.9)",
                         "night-sky cooling in the daily range (81 has it, 71 does not)",
                         "the centre pad's wire path inside the PEEK sleeve (HW.34)"],
        "verdict": verdict,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"  gap coefficients µm/K: {out['coefficients_um_per_K']['gap']} · daily range K {out['daily_capsule_range_K']}")
    for rname, per in seasonal.items():
        for cname, v in per.items():
            print(f"  {rname:20s} {cname:28s} gap {v['gap_um_cold']:+6.1f} / {v['gap_um_hot']:+6.1f} µm · stroke "
                  f"{v['stroke_um_cold']:+6.1f} / {v['stroke_um_hot']:+6.1f} µm · "
                  f"L1 {v['window'][l1]}")
    print(f"\n  VERDICT: {verdict}")
    print(f"  → {OUT_JSON.relative_to(HERE.parent.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
