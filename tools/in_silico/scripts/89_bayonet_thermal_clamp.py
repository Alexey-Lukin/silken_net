#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""89 — the bayonet clamp over its interference tolerance and temperature: how stiff the clamp loop may be, and what
the collar wall must then carry (00_07 HW.33, the leg «тепловий затиск байонета»; its consumer is the conditional
root-package member «стінка коміра за міцністю», ⚖️ founder 2026-10-13, 02_02 §4.4 — a price this raises goes back
to the founder).

QUESTION. The bayonet is deflection-controlled (02_02 §4.3): the clamp C is the elastic squeeze of the loop
lug → groove ledge → radome → rim → flange face → collar → lug, so C = k·(interference), with k the loop's stiffness.
Two displacements move it: the TOLERANCE of the interference (±δ — the lock-groove Z of the radome and the lug Z of the
collar, neither specified) and TEMPERATURE (the free mismatch Δα·L per kelvin). The ratified member sizes the collar wall
for the clamp `52` asks at the assembly temperature with no tolerance — `88`: (R0 + p)/f at the window top for a ring
that never relaxes. This script prices the wall as a function of k, and states what a FORCE-controlled clamp (a
compliant element whose stroke absorbs δ, temperature and creep) would ask instead.

PATHS (rule 15 (a)–(b)). Between the lug and the flange face canon defines: (1) the radome PEEK between the groove's
lower flank and the rim face, in compression, over the span L = lock_groove_z − socket band (the groove is a band of
half-height lug radius + slot clearance around lock_groove_z, Radome.cs; lock_groove_z is a PLACEHOLDER, 02_02 §4.4 /
00_07 HW.8); (2) the Ti collar from the flange face to the lug underside over the same span — one Ti body with the
flange (02_02 §4.4, Assembly.RequiredLugZMm) — so the mismatch is (α_PEEK·ΔT_PEEK − α_Ti·ΔT_Ti)·L and, at one
temperature, cold unloads the clamp and heat loads it; (3) the interference itself, whose tolerance δ moves the clamp by
k·δ — the same k that turns the mismatch into force; (4) the three lug–ledge contacts (line contacts of the R1.5 lugs,
above the PEEK yield at these loads, so the ledge creeps locally beyond `52`'s f), the lug's bending, the collar wall's
bending under three eccentric loads (which also raises its stress beyond `73`'s pure shear), the flange disc's bending
between the ledge contact and the collar root, and the boss ring's bending between the lugs under the ring's distributed
lift (the rim can lift locally between lugs before C < L overall) — all in series or alongside, NOT computed; (5) the
rim-face contact, in parallel with (6) the O-ring, whose reaction is the lift L the clamp must exceed — in the cold the
cord's own contraction takes ~3 % of the squeeze, but the compound's force near −40 °C is not in the source (`88`), so L0
is TAKEN, not bounded; (7) the pogo pair inside L; (8) PEEK–Ti friction if `82`'s running clearance closes in the cold.
Loads that do not depend on the clamp (weight, wind, inertia — `87`; ice — `73`) are not this model's.

FORM. The delivered clamp is C0 ± k·δ. Cold, end of life — the summer increment relaxes too (held for months against
`52`'s τ of a year), so the winter clamp is f·C0 − s·(ΔT_c + (1 − f)·ΔT_h) with s = k·Δα·L, and it must stay ≥ L0. Heat,
start of life: C0 + k·δ + s·ΔT_h ≤ cap(wall), cap linear in the wall (`73`, pure shear). So the lug must carry
cap_needed(k) = L0/f + k·[2δ + Δα·L·((ΔT_c + (1 − f)·ΔT_h)/f + ΔT_h)] — for a PEEK-DOMINATED loop, k = k_PEEK (the
grid below is that, and k = 0 is not a loop). ⚠️ The relaxation f applies only as far as the PEEK IS the compliance: in a
series loop of PEEK (k_p, relaxing to f) and a non-relaxing spring (k_s) at fixed interference the clamp keeps
f·(k_p + k_s)/(k_s + f·k_p) of itself, i.e. f_eff = f/(f + φ·(1 − f)) with φ = k/k_p the PEEK's share of the compliance —
so the lug load runs continuously from L0 (k_s → 0, FORCE control) to the PEEK-dominated value, and ANY wall between can
be met by SOME loop; the ratified number is one point on that curve, not a property of the design. A spring-dominated
clamp still carries k_s·(2δ + Δα·L·(ΔT_c + ΔT_h) + creep stroke), adds its own relaxation and force tolerance, and, being
soft, gives the rim a near-zero load factor against the tipping loads `87` names. Its limit is printed below.

ASSUMPTIONS (ours, named): the loop at the capsule's temperature — NOT conservative: the PEEK ledge sits at the sunlit
outer diameter while the Ti collar and flange are tied to the stem, and a gradient increases the mismatch; the
gradient-bound reading takes α_PEEK alone (the Ti held at the assembly temperature), up to α_Ti/Δα more; the hot model
edge is `71`'s lumped capsule mean for the canon finish α ≤ 0.5 (02_01, delegated 2026-09-27), not the PEEK at the
sunlit base, so the 85 °C requirement governs; L0 at `88`'s band top with the ring never relaxing (the member's corner).

CAN show: for each squeeze point of `88`, two temperature readings, two Δα readings and three δ readings, the collar
wall as a function of k, the k the print floor and the member wall tolerate, the wall a PEEK-only column would need, and
the force-controlled lug load and wall. CANNOT show: k itself (paths 4 — FEA or bench; the lug geometry is a
placeholder); δ (neither Z tolerance is specified); the ledge's local creep; seasonal ratcheting beyond one summer.
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    CACHE_DIR,
    E_PEEK_PA,
    NU_PEEK,
    SIGMA_YIELD_PEEK_PA,
)
from lib.utils import banner

SI_DESCRIPTION = ("How much the bayonet's grip spreads with its fit tolerance and with heat and cold, and how thick the "
                  "titanium collar must then be — as a function of how stiff the clamp is, which is still unmeasured.")

ZSTACK52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
COLLAR73 = CACHE_DIR / "mechanical" / "collar_wall_inversion.json"
CLEAR82 = CACHE_DIR / "mechanical" / "collar_running_clearance.json"
BAND88 = CACHE_DIR / "mechanical" / "oring_reaction_band.json"
CAPSULE71 = CACHE_DIR / "thermal" / "capsule_envelope.json"
RADOME_CEM = HERE.parent.parent / "cad" / "cem" / "radome.json"
OUT_JSON = CACHE_DIR / "mechanical" / "bayonet_thermal_clamp.json"

K_GRID_N_PER_UM = (0.3, 1.0, 3.0, 10.0, 30.0)   # PEEK-dominated loop stiffnesses printed; the real one is unmeasured
DELTA_MM = (0.0, 0.05, 0.10)   # ±interference tolerance: none · the ±0.05 class the shop is asked for a MACHINED Ti
#                                groove depth (`52` DEPTH_TOL_ASKED, unanswered — HW.23), borrowed here for one Z dimension ·
#                                both Z dimensions at it, summed arithmetically (RSS would be ±0.071; `52`'s face flatness,
#                                ±84 µm, sits in the same loop and is NOT in either reading)
YIELD_ONSET_LINE_CONTACT = 1.67  # p0 / Y at first yield under a line contact (Tresca; Johnson, Contact Mechanics, §6.2)
HOT_FINISH_ALPHA = "0.50"      # canon finish α ≤ 0.5 (02_01, ⚖️ delegated 2026-09-27); `71`'s still-air h_c × 0.7 row


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S88 = _load("s88_band", "88_oring_reaction_band.py")


def main() -> int:
    banner("Bayonet clamp — interference tolerance and temperature: loop stiffness k, the lug load, the collar wall (HW.33)")
    z52 = json.loads(ZSTACK52.read_text(encoding="utf-8"))
    c73 = json.loads(COLLAR73.read_text(encoding="utf-8"))
    c82 = json.loads(CLEAR82.read_text(encoding="utf-8"))
    b88 = json.loads(BAND88.read_text(encoding="utf-8"))
    c71 = json.loads(CAPSULE71.read_text(encoding="utf-8"))
    radome = json.loads(RADOME_CEM.read_text(encoding="utf-8"))

    f = z52["rim_datum_creep"]["relax_fraction_at_service"]
    rows73 = c73["case_b_lug_root_shear"]["rows"]
    floor_wall = min(r["wall_mm"] for r in rows73)
    cap_floor = c73["verdict"]["capacity_at_print_floor_N"]
    member_wall = b88["band"]["window_top"]["collar_wall_strength_asks_mm_ring_never_relaxes"]
    cap_member = cap_floor * member_wall / floor_wall          # `73`: pure shear, linear in the wall

    t_asm = c82["inputs"]["t_ref_c"]
    hot_model = c71["hot_bound_h_c_sensitivity"]["sunlit_still_air"][HOT_FINISH_ALPHA]["t_cap_max_c"]
    readings = {"capsule_requirement": (c82["inputs"]["t_min_requirement_c"], c82["inputs"]["t_max_requirement_c"]),
                "model_edges": (c82["inputs"]["t_min_model_edge_c"], hot_model)}

    a_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    d_alpha = {"isothermal": ALPHA_PEEK_1K - a_ti, "gradient_bound": ALPHA_PEEK_1K}
    span_mm = radome["lock_groove_z_mm"] - (radome["lug_radius_mm"] + radome["slot_clearance_mm"])

    ag = z52["applied_gland"]
    slots = radome["bayonet_lugs"] * ag["entry_slot_opening_mm2_each"]
    sections = {"socket_band_annulus": math.pi * (ag["socket_pocket_r_mm"][1] ** 2 - ag["socket_pocket_r_mm"][0] ** 2) - slots,
                "rim_contact": ag["rim_contact_area_mm2"],
                "boss_section": math.pi * ((radome["dome_diameter_mm"] / 2) ** 2
                                           - ag["radome_seal_land_r_mm"][0] ** 2) - slots}
    k_column = {k: E_PEEK_PA * a * 1e-6 / (span_mm * 1e-3) * 1e-6 for k, a in sections.items()}   # N/µm over the span

    def wall_for(force: float) -> float:
        return S88.wall_for_force(rows73, force)

    # The lug is a radial pin (CathodeFlange.cs) on the groove's FLAT lower flank → a line contact.
    flange = json.loads((RADOME_CEM.parent / "cathode_flange.json").read_text(encoding="utf-8"))
    lug_r = radome["lug_radius_mm"]
    band = ag["socket_pocket_r_mm"][1] - ag["socket_pocket_r_mm"][0]
    engaged = {"socket_band_minus_clearance": round(band - radome["slot_clearance_mm"], 3),
               "cem_protrusion": flange["lug_protrusion_mm"]}
    ti = ALLOY_PROPERTIES[ALLOY_BASELINE]
    e_star = 1.0 / ((1 - NU_PEEK ** 2) / E_PEEK_PA + (1 - ti["nu"] ** 2) / (ti["E_GPa"] * 1e9))     # Pa
    p0_yield = YIELD_ONSET_LINE_CONTACT * SIGMA_YIELD_PEEK_PA

    def p0_mpa(force_per_lug: float, length_mm: float) -> float:
        fl = force_per_lug / (length_mm * 1e-3)                                    # N/m
        return math.sqrt(fl * e_star / (math.pi * lug_r * 1e-3)) * 1e-6

    points = {}
    for name, b in b88["band"].items():
        l0 = b["required_clamp_N_at_band_high"]["at_assembly"]
        per = {}
        for rname, (t_min, t_max) in readings.items():
            dtc, dth = t_asm - t_min, t_max - t_asm
            cold_eff = dtc + (1.0 - f) * dth                     # the summer increment relaxes before the winter
            for aname, da in d_alpha.items():
                thermal_um = da * span_mm * 1e3 * (cold_eff / f + dth)   # µm of interference-equivalent
                by_delta = {}
                for delta in DELTA_MM:
                    slope_um = 2.0 * delta * 1e3 + thermal_um            # cap_needed = L0/f + k·slope (k in N/µm)
                    need = {str(k): l0 / f + k * slope_um for k in K_GRID_N_PER_UM}

                    def k_max(cap, l0=l0, slope_um=slope_um):
                        v = (cap - l0 / f) / slope_um
                        return v if v >= 0 else None

                    km = {"print_floor": k_max(cap_floor), "member_wall": k_max(cap_member)}
                    by_delta[str(delta)] = {
                        "slope_um": round(slope_um, 2),
                        "thermal_share_of_slope": round(thermal_um / slope_um, 3),
                        "lug_load_N_by_k": {k: round(v, 1) for k, v in need.items()},
                        "strength_wall_mm_by_k": {k: round(wall_for(v), 3) for k, v in need.items()},
                        "wall_mm_per_N_per_um": round(wall_for(cap_floor + slope_um) - wall_for(cap_floor), 4),
                        "k_max_N_per_um": {w: (round(v, 3) if v is not None else None) for w, v in km.items()},
                        "wall_mm_if_the_PEEK_column_were_the_loop": {
                            sec: round(wall_for(l0 / f + kc * slope_um), 2) for sec, kc in k_column.items()}}
                per[f"{rname}|{aname}"] = {"dT_cold_K": round(dtc, 2), "dT_hot_K": round(dth, 2),
                                           "cold_with_summer_relaxed_K": round(cold_eff, 2),
                                           "thermal_um": round(thermal_um, 2), "by_delta_mm": by_delta}
        req = per["capsule_requirement|isothermal"]
        spring = {}
        for dstr in req["by_delta_mm"]:
            spread_um = 2.0 * float(dstr) * 1e3 + d_alpha["isothermal"] * span_mm * 1e3 * (
                req["dT_cold_K"] + req["dT_hot_K"])                      # a spring does not relax: no f, no ratchet
            ks = (cap_floor - l0) / spread_um if cap_floor > l0 else None
            spring[dstr] = {"spread_um": round(spread_um, 2),
                            "k_spring_max_N_per_um_zero_tolerance": round(ks, 3) if ks else None,
                            "working_deflection_mm_at_band_centre": round((cap_floor + l0) / 2 / ks * 1e-3, 2) if ks else None}
        loads = {"PEEK_dominated_minimum": l0 / f, "force_controlled": l0}
        points[name] = {"squeeze_pct": b["squeeze_pct"], "lift_L0_N_at_band_top": l0,
                        "PEEK_dominated_lower_bound_lug_load_N": round(l0 / f, 1),
                        "PEEK_dominated_lower_bound_wall_mm": round(wall_for(l0 / f), 3),
                        "force_controlled_lug_load_N": round(l0, 1),
                        "force_controlled_wall_mm_zero_band": round(wall_for(l0), 3),
                        "force_band_half_width_to_print_floor": round((cap_floor - l0) / (cap_floor + l0), 3)
                        if cap_floor > l0 else None,
                        "spring_capsule_requirement": spring,
                        "lug_line_contact_p0_MPa": {
                            lk: {ek: round(p0_mpa(v / radome["bayonet_lugs"], ev), 0) for ek, ev in engaged.items()}
                            for lk, v in loads.items()},
                        "by_reading": per}

    top, flo, nom = points["window_top"], points["window_floor"], points["nominal"]
    key = "capsule_requirement|isothermal"
    t5, t0 = top["by_reading"][key]["by_delta_mm"]["0.05"], top["by_reading"][key]["by_delta_mm"]["0.0"]
    n5 = nom["by_reading"][key]["by_delta_mm"]["0.05"]
    f5 = flo["by_reading"][key]["by_delta_mm"]["0.05"]
    tg = top["by_reading"]["capsule_requirement|gradient_bound"]["by_delta_mm"]["0.0"]
    sp = top["spring_capsule_requirement"]["0.05"]
    pc_top = top["lug_line_contact_p0_MPa"]["PEEK_dominated_minimum"]
    pc_flo = flo["lug_line_contact_p0_MPa"]["PEEK_dominated_minimum"]
    pc_force = top["lug_line_contact_p0_MPa"]["force_controlled"]
    verdict = (
        f"A deflection-controlled clamp moves with its interference tolerance and with temperature through the loop "
        f"stiffness k. In a PEEK-dominated loop (k = k_PEEK, the PEEK relaxing by f — the form `52` and the member assume) "
        f"every N/µm adds {t5['wall_mm_per_N_per_um']:.3f} mm of wall at the window top with a ±0.05 mm interference over "
        f"the capsule requirement (temperature {t5['thermal_share_of_slope'] * 100:.0f} % of it), "
        f"{t0['wall_mm_per_N_per_um']:.4f} mm with no tolerance ({tg['wall_mm_per_N_per_um']:.4f} with a Ti–PEEK "
        f"gradient) — so such a loop needs more than the ratified {member_wall:.2f} mm for any k, which is its lower bound, "
        f"not an estimate. A compliant element in series makes the relaxation and the k-terms fade, and the lug load runs "
        f"continuously down to L0 — {top['force_controlled_lug_load_N']:.0f} N at the window top, a "
        f"{top['force_controlled_wall_mm_zero_band']:.2f} mm wall with a zero force band — so the ratified number is one "
        f"point on a curve of an unmeasured k, bounding nothing. That force-controlled end is not cheap: to stay inside "
        f"the print floor its spring must be no stiffer than {sp['k_spring_max_N_per_um_zero_tolerance']:.2f} N/µm with "
        f"±0.05 mm and zero force tolerance (≈ {sp['working_deflection_mm_at_band_centre']:.1f} mm of working deflection), "
        f"its whole force band fits ±{top['force_band_half_width_to_print_floor'] * 100:.1f} %, and a soft clamp gives the "
        f"rim almost no stiffness against tipping. Separately, the lug is a radial pin on a flat ledge — a line contact — "
        f"whose peak pressure at the window top is {min(pc_top.values()):.0f}–{max(pc_top.values()):.0f} MPa "
        f"({min(pc_flo.values()):.0f}–{max(pc_flo.values()):.0f} at the window floor; "
        f"{min(pc_force.values()):.0f}–{max(pc_force.values()):.0f} at the window top even under the force-controlled L0) "
        f"against {p0_yield * 1e-6:.0f} MPa for first yield of the PEEK at its tensile yield (the compressive yield is "
        f"higher and not in the tree): the ledge yields and creeps beyond `52`'s f across the window under the PEEK-dominated load, and at the window top under either clamp. With ±0.05 the print floor carries a PEEK-dominated loop at the window floor up to "
        f"k = {f5['k_max_N_per_um']['print_floor']:.2f} N/µm and at the nominal up to "
        f"{n5['k_max_N_per_um']['print_floor']:.2f}. k, δ and the PEEK's share of the compliance are not computed — the lug "
        f"geometry and both Z tolerances are placeholders; the member goes back to the founder (02_02 §4.4).")

    out = {
        "question": "How the bayonet clamp spreads with its interference tolerance and temperature, and the collar wall "
                    "its lug load then needs — the number of the conditional root-package member (02_02 §4.4).",
        "form": "PEEK-dominated loop (k = k_PEEK): cap_needed(k) = L0/f + k·[2δ + Δα·L·((ΔT_c + (1 − f)·ΔT_h)/f + ΔT_h)]; "
                "a series spring makes f_eff = f/(f + φ(1 − f)), φ = k/k_PEEK, so the load runs continuously to the "
                "force-controlled L0 (plus k_s·spread)",
        "assumptions": ["the loop at the capsule's temperature — NOT conservative; the gradient-bound reading takes "
                        "α_PEEK alone",
                        "relaxation acts on the mechanical clamp; the summer thermal increment relaxes too before the "
                        "winter (one summer)",
                        "L0 at the band's top with the ring never relaxing; the ring's force in the cold is taken, "
                        "not bounded",
                        "lug-root capacity linear in the wall (73, pure shear — collar bending under eccentric lugs "
                        "would lower it)"],
        "inputs": {"relax_fraction_at_service_52": f, "assembly_temperature_c_82": t_asm,
                   "temperature_readings_c": {k: list(v) for k, v in readings.items()},
                   "hot_edge_reading": f"71: lumped capsule mean, sunlit, still air, h_c × 0.7, absorptance "
                                       f"{HOT_FINISH_ALPHA} (canon finish)",
                   "e_peek_pa": E_PEEK_PA, "alpha_peek_1K": ALPHA_PEEK_1K, "alpha_ti_1K": a_ti,
                   "delta_alpha_1K": d_alpha, "delta_mm": list(DELTA_MM),
                   "delta_from": "±interference tolerance; 0.05 = the class the shop is asked for the groove depth "
                                 "(52 DEPTH_TOL_ASKED) on one Z dimension, 0.10 = both at it; neither is specified",
                   "lug_root_capacity_N_at_print_floor_73": cap_floor, "print_floor_wall_mm_73": floor_wall,
                   "member_wall_mm_88": member_wall, "lug_root_capacity_N_at_member_wall": round(cap_member, 1),
                   "span_mm_placeholder": round(span_mm, 3),
                   "span_from": "radome.json lock_groove_z_mm − (lug_radius_mm + slot_clearance_mm); lock_groove_z "
                                "is a placeholder (HW.8)",
                   "peek_sections_mm2": {k: round(v, 1) for k, v in sections.items()},
                   "lug_line_contact": {"lug_radius_mm": lug_r, "engaged_length_mm": engaged,
                                        "e_star_pa": round(e_star, -6), "yield_onset_p0_pa": p0_yield,
                                        "yield_onset_ratio": YIELD_ONSET_LINE_CONTACT,
                                        "sigma_yield_peek_pa": SIGMA_YIELD_PEEK_PA}},
        "peek_column": {"k_N_per_um_over_span": {k: round(v, 1) for k, v in k_column.items()},
                        "is": "the loop's stiffness if a PEEK annulus over the span were its ONLY compliance — not what "
                              "sits under the lugs (the load enters through three line contacts), so a ceiling and no "
                              "estimate of k"},
        "by_squeeze_point": points,
        "missing_data": ["k: the lug contacts, the ledge, the lug's, collar's, flange disc's and boss ring's bending (FEA "
                         "or bench; lug geometry placeholder, HW.8)",
                         "δ: the tolerances of the lock-groove Z and the lug Z (neither specified)",
                         "the ledge's local creep under contact stress above the PEEK yield",
                         "the PEEK at the sunlit base vs the lumped capsule mean; the ring's force below room "
                         "temperature; resin swell (88)",
                         "the PEEK's share of the loop compliance (it sets how much of f applies)",
                         "a compliant element's force tolerance and space, if the clamp is made force-controlled"],
        "verdict": verdict,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"  span {span_mm:.2f} mm (placeholder) · Δα {d_alpha} · f {f} · member wall {member_wall} mm")
    for name, p in points.items():
        print(f"  {name:13s} L0 {p['lift_L0_N_at_band_top']:6.1f} N · PEEK-dominated lower bound wall "
              f"{p['PEEK_dominated_lower_bound_wall_mm']} · force-controlled wall {p['force_controlled_wall_mm_zero_band']} · "
              f"line-contact p0 {p['lug_line_contact_p0_MPa']}")
        r = p["by_reading"][key]["by_delta_mm"]
        for d, v in r.items():
            print(f"      δ ±{d} mm: slope {v['slope_um']} µm (thermal {v['thermal_share_of_slope']}) · "
                  f"wall(k) {v['strength_wall_mm_by_k']} · k_max {v['k_max_N_per_um']}")
    print(f"\n  VERDICT: {verdict}")
    print(f"  → {OUT_JSON.relative_to(HERE.parent.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
