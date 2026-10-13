#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""89 — the bayonet clamp over temperature: how stiff the clamp loop may be, and what the collar wall must then carry
(00_07 HW.33, the 🤖 leg «тепловий затиск байонета»; its consumer is the conditional root-package member «стінка коміра
за міцністю», ⚖️ founder 2026-10-13, 02_02 §4.4, whose NUMBER this leg revises before the root moves).

QUESTION. The bayonet is deflection-controlled (02_02 §4.3): the clamp C is the elastic squeeze of the loop
lug → groove ledge → radome → rim → flange face → collar → lug. The ratified member sizes the collar wall for the clamp
at the ASSEMBLY temperature — `88`: (R0 + p)/f at the window top for a ring that never relaxes. Temperature moves C by
s·ΔT, where s = k_loop·Δα·L (N/K) is the loop's thermal sensitivity: in the cold the relaxed clamp must still exceed
the lift, in the heat the unrelaxed clamp must not exceed the lug root. This script inverts that pair: for a given s,
the lug load and the collar wall it needs; the s each wall tolerates; how soft the loop must be for it; and the s the
PEEK alone would give if it were the loop's only compliance.

PATHS (rule 15 (a)–(b)). Between the lug and the flange face canon defines: (1) the radome PEEK between the groove's
lower flank and the rim face, in compression — the clamp's spring and the CTE member, over the span
L = lock_groove_z − socket band (the groove is a band of half-height lug radius + slot clearance around lock_groove_z,
Radome.cs; lock_groove_z is a PLACEHOLDER, 02_02 §4.4 / 00_07 HW.8); (2) the Ti collar from the flange face to the lug
underside over the same span — one Ti body with the flange (02_02 §4.4, Assembly.RequiredLugZMm) — so the free mismatch
per kelvin is (α_PEEK − α_Ti)·L and its SIGN is fixed: cold unloads the clamp, heat loads it; (3) the three lug–ledge
contacts and the lug's own bending — series compliance that lowers s, NOT computed; (4) the rim-face contact, in
parallel with (5) the O-ring, whose reaction is the lift L the clamp must exceed — in the cold the ring's own
contraction lowers it (Parker Table 2-5, `88`), so the assembly-temperature lift is the conservative one for the cold
condition, and the heat condition does not contain it; (6) the pogo pair, inside the lift. Loads that do not depend on
the clamp (weight, wind, inertia — `87`; ice — `73`) are not this model's.

FORM. C(T) = C0 + s·(T − T_asm) while the rim stays seated; the PEEK relaxation f of `52` acts on the mechanical clamp,
and the thermal part is taken as elastic (a cold snap is fast against relaxation). Cold, end of life:
f·C0 − s·ΔT_c ≥ L0. Heat, start of life: C0 + s·ΔT_h ≤ cap(wall), cap linear in the wall (`73`, pure shear). So the
lug must carry cap_needed(s) = (L0 + s·ΔT_c)/f + s·ΔT_h, the wall follows `73`'s rows, a wall tolerates
s_max = (f·cap(wall) − L0)/(ΔT_c + f·ΔT_h), and the loop may be no stiffer than k_max = s_max/(Δα·L).

ASSUMPTIONS (ours, named): the loop is isothermal at the capsule's temperature — the flange is tied to the stem by
conduction, so it is no colder in winter than `81`'s isolated capsule and no hotter in summer than `71`'s
adiabatic-base capsule, which makes both bounds conservative for the loop; superposition of relaxation and thermal
load; L0 at the band's top (`88`), the ring never relaxing — the corner the ratified member stands on.

CAN show: for each squeeze point of `88` and two temperature readings (the capsule requirement · the models' edges),
the lug load and wall as a function of s, the s the print floor and the member wall tolerate, the softness k_max that
needs at the placeholder span and how it compares with the PEEK column under the lug, and the wall a PEEK-only loop
would need. CANNOT show: the lug-contact and ledge compliance — they decide s (FEA or bench; the lug geometry is a
placeholder); a temperature gradient between Ti and PEEK; PEEK relaxing faster in the heat (`52`'s f is
temperature-free) or ratcheting over seasons; the ring's force below room temperature; resin swell.
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, ALPHA_PEEK_1K, CACHE_DIR, E_PEEK_PA
from lib.utils import banner

SI_DESCRIPTION = ("How much the bayonet's grip changes when the anchor heats and cools, and how thick the titanium "
                  "collar must then be — as a function of how stiff the clamp is, which is still unmeasured.")

ZSTACK52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
COLLAR73 = CACHE_DIR / "mechanical" / "collar_wall_inversion.json"
CLEAR82 = CACHE_DIR / "mechanical" / "collar_running_clearance.json"
BAND88 = CACHE_DIR / "mechanical" / "oring_reaction_band.json"
CAPSULE71 = CACHE_DIR / "thermal" / "capsule_envelope.json"
RADOME_CEM = HERE.parent.parent / "cad" / "cem" / "radome.json"
OUT_JSON = CACHE_DIR / "mechanical" / "bayonet_thermal_clamp.json"

S_GRID_N_PER_K = (0.0, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0)   # loop sensitivities printed; the real one is unmeasured
HOT_FINISH_ALPHA = "0.95"     # `71`'s dark-finish row — the radome finish is open, so the hotter reading is taken


def _load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S88 = _load("s88_band", "88_oring_reaction_band.py")


def main() -> int:
    banner("Bayonet clamp over temperature — loop sensitivity s, the lug load and the collar wall it needs (HW.33)")
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
    d_alpha = {"lib": ALPHA_PEEK_1K - a_ti, "sensitivity_82": c82["inputs"]["alpha_peek_sensitivity_1K"] - a_ti}
    span_mm = radome["lock_groove_z_mm"] - (radome["lug_radius_mm"] + radome["slot_clearance_mm"])

    ag = z52["applied_gland"]
    slots = radome["bayonet_lugs"] * ag["entry_slot_opening_mm2_each"]
    sections = {"socket_band_under_the_lugs": math.pi * (ag["socket_pocket_r_mm"][1] ** 2
                                                         - ag["socket_pocket_r_mm"][0] ** 2) - slots,
                "rim_contact": ag["rim_contact_area_mm2"],
                "boss_section": math.pi * ((radome["dome_diameter_mm"] / 2) ** 2
                                           - ag["radome_seal_land_r_mm"][0] ** 2) - slots}
    s_column = {k: E_PEEK_PA * a * 1e-6 * d_alpha["lib"] for k, a in sections.items()}   # N/K, PEEK the only compliance
    k_column = {k: E_PEEK_PA * a * 1e-6 / (span_mm * 1e-3) * 1e-6 for k, a in sections.items()}   # N/µm over the span

    def wall_for(force: float) -> float:
        return S88.wall_for_force(rows73, force)

    points = {}
    for name, b in b88["band"].items():
        l0 = b["required_clamp_N_at_band_high"]["at_assembly"]
        per = {}
        for rname, (t_min, t_max) in readings.items():
            dtc, dth = t_asm - t_min, t_max - t_asm
            slope_n = dtc / f + dth                               # extra lug load per N/K of loop sensitivity
            need = {str(s): round((l0 + s * dtc) / f + s * dth, 1) for s in S_GRID_N_PER_K}

            def s_max(cap, l0=l0, dtc=dtc, dth=dth):
                v = (f * cap - l0) / (dtc + f * dth)
                return v if v >= 0 else None

            s_floor, s_member = s_max(cap_floor), s_max(cap_member)
            k_raw = {w: (s / (d_alpha["lib"] * span_mm * 1e-3) * 1e-6 if s is not None else None)
                     for w, s in (("print_floor", s_floor), ("member_wall", s_member))}
            k_max = {w: (round(k, 2) if k is not None else None) for w, k in k_raw.items()}
            per[rname] = {"dT_cold_K": round(dtc, 2), "dT_hot_K": round(dth, 2),
                          "lug_load_N_by_s": need,
                          "strength_wall_mm_by_s": {k: round(wall_for(v), 3) for k, v in need.items()},
                          "wall_mm_per_N_per_K": round(wall_for(cap_floor + slope_n) - wall_for(cap_floor), 4),
                          "s_max_N_per_K": {k: (round(v, 3) if v is not None else None)
                                            for k, v in (("print_floor", s_floor), ("member_wall", s_member))},
                          "k_max_N_per_um_at_span": k_max,
                          "softer_than_peek_under_the_lugs_x": {
                              w: (round(k_column["socket_band_under_the_lugs"] / k, 1) if k else None)
                              for w, k in k_raw.items()},
                          "wall_mm_if_the_PEEK_column_were_the_loop": {
                              k: round(wall_for((l0 + s * dtc) / f + s * dth), 2) for k, s in s_column.items()}}
        points[name] = {"squeeze_pct": b["squeeze_pct"], "lift_L0_N_at_band_top": l0,
                        "isothermal_lug_load_N": round(l0 / f, 1), "by_temperature": per}

    top, flo, nom = points["window_top"], points["window_floor"], points["nominal"]
    rq, me = "capsule_requirement", "model_edges"
    soft = k_column["socket_band_under_the_lugs"]
    verdict = (
        f"Temperature moves the clamp by s N/K, and the lug carries (L0 + s·ΔT_c)/f + s·ΔT_h. At the window top the "
        f"ratified member wall ({member_wall:.2f} mm) is the s = 0 answer: every N/K of loop sensitivity adds "
        f"{top['by_temperature'][rq]['wall_mm_per_N_per_K']:.3f} mm of wall over the capsule requirement "
        f"({t_asm - readings[rq][0]:.0f} K down, {readings[rq][1] - t_asm:.0f} K up) and "
        f"{top['by_temperature'][me]['wall_mm_per_N_per_K']:.3f} mm over the models' edges, so the member holds only for "
        f"a loop that does not feel temperature at all. The print floor carries the window floor up to "
        f"s = {flo['by_temperature'][rq]['s_max_N_per_K']['print_floor']:.2f} N/K and the nominal up to "
        f"{nom['by_temperature'][rq]['s_max_N_per_K']['print_floor']:.2f} (requirement); at the placeholder span "
        f"{span_mm:.1f} mm that asks a loop no stiffer than "
        f"{flo['by_temperature'][rq]['k_max_N_per_um_at_span']['print_floor']:.1f} … "
        f"{nom['by_temperature'][rq]['k_max_N_per_um_at_span']['print_floor']:.1f} N/µm, against "
        f"{soft:.0f} N/µm for the PEEK column under the lugs alone — "
        f"{flo['by_temperature'][rq]['softer_than_peek_under_the_lugs_x']['print_floor']:.0f}–"
        f"{nom['by_temperature'][rq]['softer_than_peek_under_the_lugs_x']['print_floor']:.0f}× softer. If the PEEK were the loop's only compliance "
        f"(s = {min(s_column.values()):.0f}–{max(s_column.values()):.0f} N/K), the window top would need a wall of "
        f"{min(top['by_temperature'][rq]['wall_mm_if_the_PEEK_column_were_the_loop'].values()):.1f}–"
        f"{max(top['by_temperature'][rq]['wall_mm_if_the_PEEK_column_were_the_loop'].values()):.1f} mm. The lug "
        f"contacts and the ledge are in series and soften the loop; how much — and so whether the bayonet needs a "
        f"compliant element, or a thicker wall, or a ring that relaxes — is not computed here (the lug geometry is a "
        f"placeholder).")

    out = {
        "question": "How stiff the bayonet clamp loop may be over the capsule's temperature range, and the collar wall "
                    "its lug load then needs — the number of the conditional root-package member (02_02 §4.4).",
        "form": "C(T) = C0 + s·(T − T_asm); cold, end of life: f·C0 − s·ΔT_c ≥ L0; heat, start: C0 + s·ΔT_h ≤ cap(wall); "
                "cap_needed(s) = (L0 + s·ΔT_c)/f + s·ΔT_h; s_max = (f·cap − L0)/(ΔT_c + f·ΔT_h); "
                "k_max = s_max/(Δα·L)",
        "assumptions": ["the loop isothermal at the capsule's temperature (both bounds conservative for the loop)",
                        "relaxation acts on the mechanical clamp, the thermal part is elastic, and the two superpose",
                        "L0 at the band's top with the ring never relaxing (the ratified member's corner); in the cold "
                        "the ring's own contraction lowers it, so the cold condition is conservative",
                        "lug-root capacity linear in the wall (73, pure shear)"],
        "inputs": {"relax_fraction_at_service_52": f, "assembly_temperature_c_82": t_asm,
                   "temperature_readings_c": {k: list(v) for k, v in readings.items()},
                   "hot_edge_reading": f"71: sunlit, still air, h_c × 0.7, absorptance {HOT_FINISH_ALPHA}",
                   "e_peek_pa": E_PEEK_PA, "alpha_peek_1K": ALPHA_PEEK_1K, "alpha_ti_1K": a_ti,
                   "delta_alpha_1K": d_alpha,
                   "lug_root_capacity_N_at_print_floor_73": cap_floor, "print_floor_wall_mm_73": floor_wall,
                   "member_wall_mm_88": member_wall, "lug_root_capacity_N_at_member_wall": round(cap_member, 1),
                   "span_mm_placeholder": round(span_mm, 3),
                   "span_from": "radome.json lock_groove_z_mm − (lug_radius_mm + slot_clearance_mm); lock_groove_z "
                                "is a placeholder (HW.8)",
                   "peek_sections_mm2": {k: round(v, 1) for k, v in sections.items()}},
        "peek_column": {"s_N_per_K": {k: round(v, 1) for k, v in s_column.items()},
                        "k_N_per_um_over_span": {k: round(v, 1) for k, v in k_column.items()},
                        "is": "the loop's sensitivity if the PEEK under the lug were its ONLY compliance — a ceiling: "
                              "series compliance (lug contacts, ledge, lug bending) only lowers it"},
        "by_squeeze_point": points,
        "missing_data": ["the lug-contact and ledge compliance — they set s (FEA or bench; lug geometry placeholder, HW.8)",
                         "the span: lock_groove_z is a placeholder (02_02 §4.4, HW.8)",
                         "a Ti–PEEK temperature gradient (sun on the radome, shaded flange)",
                         "PEEK relaxation in the heat and its ratcheting over seasons (52's f is temperature-free)",
                         "the ring's force below room temperature and resin swell (88)"],
        "verdict": verdict,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"  span {span_mm:.2f} mm (placeholder) · Δα {d_alpha['lib'] * 1e6:.1f} ppm/K · f {f} · member wall {member_wall} mm")
    print(f"  PEEK column s {', '.join(f'{k} {v:.1f}' for k, v in s_column.items())} N/K")
    for name, p in points.items():
        for rname, r in p["by_temperature"].items():
            print(f"  {name:13s} {rname:20s} L0 {p['lift_L0_N_at_band_top']:6.1f} N · wall(s) {r['strength_wall_mm_by_s']} · "
                  f"s_max {r['s_max_N_per_K']} · k_max {r['k_max_N_per_um_at_span']}")
    print(f"\n  VERDICT: {verdict}")
    print(f"  → {OUT_JSON.relative_to(HERE.parent.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
