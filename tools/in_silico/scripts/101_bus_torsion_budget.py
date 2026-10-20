#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""101 — how far the Ø1.0 bus wire can twist between its weld root and the pad plane before it yields, per alloy,
and which link of the series that turns its top gives way first (00_07 HW.26, the leg «бюджет закручування шини Ø1.0
між коренем звару й хватом лайнера, по сплаву»; no solve).

WHY. 01_01 §4.3 C («Межі присуду»): once HW.8.9 makes the Zone-3 shank a fit, an event torque on the flange (the
bayonet, a branch, an animal, a person) reacts through the Zone-1 shank's friction too, and slip under force means
rotation without a bound — and with it the bus twists (§1.4). Nothing in the tree gave the angle the wire takes
before it yields: `77` is the stem's and the sleeve's torsion, `59` the pogo spring. This is that angle, per alloy of
the bus (the bake-off winner becomes the wire, 01_02 §2.5), for the row the FMEA will take when the event-torque
verdict comes (00_07 HW.26, the event-moment leg).

THE ROUTE IS A SERIES (in-silico §When Modifying #44). The wire's top end face is the contact pad (01_01 §1.4), and
nothing in the tree holds it but the PEEK liner: the flange turns the wire only through the capture at the pad plane
(not designed yet), the liner tube and the liner's friction grip on the wire. The wire twists to its yield only if
that series — or a parallel tie that bypasses it — carries the wire's yield torque. So the output is three things: the
wire's elastic angle and yield torque; the torque at which each in-tree holder gives way — the liner tube's own
torsional first yield and its grip on the wire, at the nominal fit and after creep; and the wire yield below which
the order of the two flips (the weld root's heat-affected zone may sit there).

GEOMETRY (01_01 §1.4, read from `55` at runtime): the wire is welded to the anode at the bottom of the PEEK gap; the
liner rides tight on it over the whole bore and protrudes into the gap. A rotation of the flange against the anode
twists the wire over a wire-only run (the gap less the protrusion) and a run where the liner sits on it.

MODEL. Saint-Venant torsion, elastic to first yield at the outer surface: θ_y = τ_y · L_eff / (G · r), T_y = τ_y · J / r.
Two readings of each uncertain term, carried as a bracket (in-silico §When Modifying #11), never a pick:
  yield criterion — von Mises τ_y = σ_y/√3 ⊥ Tresca τ_y = σ_y/2 (the lower);
  the twisted run — top_clamped: the whole run twists as bare wire, which needs a capture that clamps the wire itself
                    (not in the tree) ⊥ liner_bonded: the liner bonded to the wire over the bore as a parallel PEEK
                    tube — the stiff bound (its free bottom end makes the real share smaller), under which more of the
                    angle goes into the bare run and the wire yields at a SMALLER angle.
The liner tube's yield torque is first yield of a free tube from PEEK's tensile yield; the grip torque is μ times the
fit's normal force (`55`'s contact pressure at the nominal radial interference, over `55`'s contact area) times the
wire's radius, over `55`'s μ sweep, at the nominal fit at 20 °C and after creep (× PEEK_RELAX_FLOOR, as `87` prices it).
The wind's rotation is `77`'s gyroid rotation at the cap taken at the sleeve's BARK end, where the flange sits
(`77`'s rigid-gyroid bark_end_peak_factor — the larger), and the torque it forces through the wire on the stiff bound.

CAN: give, inside this model, each alloy's elastic angle and yield torque over the shipped run; say whether the liner
tube yields before the wire does and before its own grip slips; give the wire yield below which that flips; and set the
wind's rotation and torque against both. A control recomputes every first-yield angle by another route — the torque
from the two runs' series compliance at θ_y, then the wire's surface stress — an identity that catches coding slips in
the run lengths, not modelling errors.
CANNOT: (1) say whether an event SLIPS the flange at all — that is the event-torque verdict's question (the collar, the
HW.8.9 fit); (2) give the angle to fracture — plastic twisting beyond first yield, and the turns a drawn wire survives,
are not in the tree; (3) give the weld root's heat-affected-zone yield (the same ceiling as `86`) — the flip threshold
is what stands in for it; (4) give a drawn wire's own yield — ALLOY_PROPERTIES is the yield `86` uses, and β-Ti's has
no source there; (5) price a parallel tie: ice or hardened resin in the wet gap or channel (`87`, 02_02 §3.5) can tie
the wire or the liner to the metal, and a tie on the liner's OD feeds torque into the wire through the grip without
crossing the tube's top section — then the wire, not the liner, may yield; no number in the tree bounds such a tie;
(6) model the capture — not designed; the order assumes one that seizes the liner's top end, while one that clamps
the liner's OD over the flange disc passes torque through the wall into the grip; (7) give the ROTATION at which the
liner gives way — that needs the liner's own compliance with Coulomb slip (#44), so the switch is cut, and at the
fit's floor (+40 °C, zero interference) the grip slips at once; (8) reduce the tube's yield torque for the fit's own
stress, +40 °C or creep — each lowers it, so the order is safe and the tube's figure is not the torque it survives;
(9) leave the placeholder Zone-3 shank length (HW.8.9) — the run, the angles and the grip scale with it.

Run:  conda activate silken_md
      python tools/in_silico/scripts/101_bus_torsion_budget.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    ALLOY_PROPERTIES,
    CACHE_DIR,
    D_BUS_ROD_MM,
    E_PEEK_PA,
    NU_PEEK,
    PEEK_RELAX_FLOOR,
    REPO_ROOT,
    SIGMA_YIELD_PEEK_PA,
)
from lib.utils import banner

SI_DESCRIPTION = ("Torsion budget of the anchor's welded bus wire: the elastic twist angle and torque to first surface "
                  "yield over the run from the weld root to the pad plane, per candidate alloy, under two yield criteria "
                  "and two readings of the twisted run, set against the torque at which the press-fitted PEEK liner — "
                  "the only in-tree holder of the wire's top — yields in torsion or its grip slips, the wire yield below "
                  "which that order flips, and the stem-torsion rotation at the sleeve's bark end; no solve")

MECH = CACHE_DIR / "mechanical"
OUT = MECH / "bus_torsion_budget.json"
READINGS = {"von_mises": 1.0 / math.sqrt(3.0), "tresca": 0.5}   # τ_y / σ_y


def _load_55():
    spec = importlib.util.spec_from_file_location("s55", Path(__file__).with_name("55_bus_mechanical.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules["s55"] = module          # 55 declares dataclasses, which look their module up here
    spec.loader.exec_module(module)
    return module


def down1(x: float) -> float:
    """A «below it, harmless» threshold rounds down (in-silico §When Modifying #43)."""
    return math.floor(round(x * 10.0, 9)) / 10.0


def up1(x: float) -> float:
    return math.ceil(round(x * 10.0, 9)) / 10.0


def up2(x: float) -> float:
    """An «at most» quantity rounds up."""
    return math.ceil(round(x * 100.0, 9)) / 100.0


def shear_modulus_mpa(e_gpa: float, nu: float) -> float:
    return e_gpa * 1e3 / (2.0 * (1.0 + nu))


def polar_moment(d_outer: float, d_inner: float = 0.0) -> float:
    return math.pi / 32.0 * (d_outer ** 4 - d_inner ** 4)


def main() -> int:
    banner("101 — bus wire torsion budget and the links that turn its top (per alloy)")
    s55 = _load_55()
    d, r = D_BUS_ROD_MM, D_BUS_ROD_MM / 2.0
    liner_id = s55.LINER_BORE_SPECIFIED_MM
    liner_od = liner_id + 2.0 * s55.LINER_WALL_MM
    liner_len = s55.LINER_LENGTH_MM
    bare_len = s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM
    run_len = bare_len + liner_len
    if abs(run_len - (s55.PEEK_GAP_MM + s55.BORE_DEPTH_MM)) > 1e-9:
        raise RuntimeError("the twisted run does not add up to the gap plus the bore")
    j_wire = polar_moment(d)
    j_liner = polar_moment(liner_od, liner_id)
    gj_liner = shear_modulus_mpa(E_PEEK_PA / 1e9, NU_PEEK) * j_liner

    # ── the in-tree holder of the wire's top: the liner tube's torsional first yield, and its grip on the wire ──
    peek_yield = SIGMA_YIELD_PEEK_PA / 1e6
    tube = {c: k * peek_yield * j_liner / (liner_od / 2.0) for c, k in READINGS.items()}
    win = json.loads((MECH / "bus_mechanical.json").read_text(encoding="utf-8"))["interference_window"]
    p_nominal = win["per_um_radial_MPa"]["P_c"] * (d - liner_id) / 2.0 * 1e3
    normal_n = p_nominal * win["cold_press_fit"]["contact_area_mm2"]
    mu_sweep = win["axial_friction_lock"]["mu_sweep"]
    grip = {f"{mu:g}": mu * normal_n * r for mu in mu_sweep}
    grip_relaxed = {mu: v * PEEK_RELAX_FLOOR for mu, v in grip.items()}
    tube_hi = max(tube.values())
    tube_below_grip = {"nominal_fit": tube_hi < min(grip.values()), "creep_relaxed_fit": tube_hi < min(grip_relaxed.values())}
    # the wire yield at which its first-yield torque meets the tube's, on the pairing least kind to «the tube first»
    flip_yield_mpa = tube_hi / (READINGS["tresca"] * j_wire / r)

    # ── the wind's rotation where the flange sits: the sleeve's bark end ──
    wb = json.loads((MECH / "anchor_torque_path.json").read_text(encoding="utf-8"))["wind_bracket"]
    centroid = {s["pine"]: s["rotation_gyroid_vs_sleeve_rad"] for s in wb["species"]}
    factor = wb["bark_end_peak_factor"]
    wind_species = max(centroid, key=centroid.get)
    wind_bark_max = centroid[wind_species] * factor["rigid_gyroid"]

    rows, control, wind_torque = {}, [], {}
    for alloy, p in sorted(ALLOY_PROPERTIES.items(), key=lambda kv: kv[1]["yield_MPa"]):
        g = shear_modulus_mpa(p["E_GPa"], p["nu"])
        gj_wire = g * j_wire
        share = gj_wire / (gj_wire + gj_liner)          # the wire's part of the bore run's stiffness, bonded
        l_eff = {"top_clamped": run_len, "liner_bonded": bare_len + liner_len * share}
        per, t_y = {}, {}
        for crit, k in READINGS.items():
            tau_y = k * p["yield_MPa"]
            t_y[crit] = tau_y * j_wire / r
            for run, length in l_eff.items():
                theta = tau_y * length / (g * r)
                per[f"{crit}__{run}"] = theta
                # control: torque from the two runs' series compliance at θ, then the bare wire's surface stress
                compliance = bare_len / gj_wire + liner_len / (gj_wire + (gj_liner if run == "liner_bonded" else 0.0))
                tau_check = theta / compliance * r / j_wire
                control.append(abs(tau_check - tau_y) / tau_y)
                if abs(tau_check - tau_y) > 1e-9 * tau_y:
                    raise RuntimeError(f"control: {alloy} {crit} {run} gives τ {tau_check} ≠ τ_y {tau_y}")
        wind_torque[alloy] = wind_bark_max * gj_wire / l_eff["liner_bonded"]
        lo, hi = min(per.values()), max(per.values())
        rows[alloy] = {"yield_MPa": p["yield_MPa"], "G_MPa": round(g, 1), "wire_share_of_bore_stiffness": round(share, 4),
                       "theta_y_rad": {kk: round(v, 6) for kk, v in per.items()},
                       "theta_y_deg_min": round(math.degrees(lo), 3), "theta_y_deg_max": round(math.degrees(hi), 3),
                       "wire_yield_torque_Nmm": {c: round(v, 2) for c, v in t_y.items()},
                       "tube_yields_before_wire": tube_hi < min(t_y.values()),
                       "root_yield_knockdown_tolerated": round(flip_yield_mpa / p["yield_MPa"], 3),
                       "margin_over_wind_bark_end": round(lo / wind_bark_max, 1)}

    weakest = min(rows, key=lambda a: rows[a]["theta_y_deg_min"])
    strongest = max(rows, key=lambda a: rows[a]["theta_y_deg_max"])
    ty_lo = min(min(v["wire_yield_torque_Nmm"].values()) for v in rows.values())
    ty_hi = max(max(v["wire_yield_torque_Nmm"].values()) for v in rows.values())
    tube_first_all = all(v["tube_yields_before_wire"] for v in rows.values())
    margin = math.floor(rows[weakest]["theta_y_deg_min"] / math.degrees(wind_bark_max))
    wind_t_max = max(wind_torque.values())
    lines = [f"Over the {run_len:.0f} mm run between the weld root and the pad plane the wire stays elastic below "
             f"{down1(rows[weakest]['theta_y_deg_min']):.1f}–{down1(rows[weakest]['theta_y_deg_max']):.1f}° on {weakest} "
             f"(the lowest) and below up to {down1(rows[strongest]['theta_y_deg_max']):.1f}° on {strongest} — a fraction of a "
             f"turn — and getting there takes {down1(ty_lo):.1f}–{up1(ty_hi):.1f} N·mm at its top."]
    if tube_first_all and all(tube_below_grip.values()):
        lines.append(f"The only in-tree holder of that top, the PEEK liner, first yields in torsion at "
                     f"{down1(min(tube.values())):.1f}–{up1(tube_hi):.1f} N·mm — below the wire on every alloy, and below its "
                     f"own grip on every swept μ at the nominal and the creep-relaxed fit (the grip is zero at the fit's "
                     f"floor, +40 °C, and slips at once). With the tree's holder an unbounded event slip therefore yields or "
                     f"slips the liner — the channel's insulation — or slips the capture; the wire yields only if another "
                     f"link carries its yield torque: a capture that clamps the wire, or a parallel tie of ice or resin in "
                     f"the wet gap or channel. The order holds for any wire yield above {math.ceil(flip_yield_mpa):.0f} MPa.")
    lines.append(f"The wind's rotation at the sleeve's bark end is at most {up2(wind_bark_max * 1e3):.2f} mrad "
                 f"({wind_species}) — at least {margin}× below the lowest wire budget — and forces at most "
                 f"{up2(wind_t_max):.2f} N·mm through the wire, far below the tube's yield.")

    result = {
        "script": Path(__file__).name,
        "geometry": {"wire_d_mm": d, "bare_run_mm": round(bare_len, 3), "liner_run_mm": round(liner_len, 3),
                     "run_mm": round(run_len, 3), "liner_id_mm": round(liner_id, 5), "liner_od_mm": round(liner_od, 5),
                     "source": "55_bus_mechanical (PEEK_GAP_MM · BORE_DEPTH_MM · LINER_* — from the CEMs at runtime); "
                               "the Zone-3 shank length is a placeholder (HW.8.9)"},
        "readings": {"yield_criterion": {"von_mises": "τ_y = σ_y/√3", "tresca": "τ_y = σ_y/2 (the lower)"},
                     "twisted_run": {"top_clamped": "the whole run twists as bare wire — needs a capture that clamps the "
                                                    "wire itself, not in the tree",
                                     "liner_bonded": "the liner bonded to the wire over the bore as a parallel PEEK tube — "
                                                     "the stiff bound; the angle to yield is smaller"}},
        "holder": {"liner_tube_first_yield_torque_Nmm": {c: round(v, 2) for c, v in tube.items()},
                   "grip_torque_Nmm_by_mu": {"nominal_fit_20C": {mu: round(v, 1) for mu, v in grip.items()},
                                             "creep_relaxed_fit": {mu: round(v, 1) for mu, v in grip_relaxed.items()},
                                             "fit_floor_40C": 0.0},
                   "grip_nominal_pressure_MPa": round(p_nominal, 3), "grip_normal_force_N": round(normal_n, 1),
                   "tube_yields_below_grip_on_every_mu": tube_below_grip,
                   "tube_torque_not_survival": "first yield of a free tube: the fit's own stress, +40 °C and creep each "
                                               "lower it",
                   "capture_at_pad_plane": "not designed — the order assumes a capture that seizes the liner's top end",
                   "parallel_tie": "ice or resin in the wet gap or channel can carry torque to the wire past the tube; "
                                   "not bounded in the tree",
                   "source": "PEEK yield lib SIGMA_YIELD_PEEK_PA; contact pressure, area and μ sweep — 55's cache "
                             "interference_window; creep floor lib PEEK_RELAX_FLOOR"},
        "wire_yield_below_which_the_order_flips_MPa": round(flip_yield_mpa, 1),
        "by_alloy": rows,
        "wind_bark_end": {"rotation_by_species_centroid_rad": centroid, "bark_end_factor": factor,
                          "rotation_max_rad": wind_bark_max, "max_species": wind_species,
                          "torque_through_wire_max_Nmm": round(wind_t_max, 4),
                          "source": "77 anchor_torque_path.json wind_bracket (rotation × bark_end_peak_factor, rigid "
                                    "gyroid — the larger); torque on the liner_bonded stiff bound"},
        "control": {"route": "torque from the series compliance at θ_y, then the bare wire's surface stress — an "
                             "identity: it catches coding slips in the run lengths, not modelling errors",
                    "cases": len(control), "max_relative_miss": max(control)},
        "findings": {"tube_yields_before_wire_on_every_alloy": tube_first_all},
        "verdict": " ".join(lines),
    }
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"\n  Run: bare {bare_len:.1f} mm + liner {liner_len:.1f} mm = {run_len:.1f} mm; wire Ø{d} mm")
    print(f"  Liner tube first yield {min(tube.values()):.2f}–{tube_hi:.2f} N·mm; grip nominal "
          f"{min(grip.values()):.1f}–{max(grip.values()):.1f}, creep-relaxed {min(grip_relaxed.values()):.1f}–"
          f"{max(grip_relaxed.values()):.1f} N·mm (μ {mu_sweep}); order flips below wire yield {flip_yield_mpa:.1f} MPa")
    print(f"  {'alloy':<20s} {'σ_y':>6s} {'θ_y deg':>14s} {'T_y N·mm':>14s}  tube first  knockdown  × wind")
    for alloy, row in rows.items():
        ty = row["wire_yield_torque_Nmm"]
        print(f"  {alloy:<20s} {row['yield_MPa']:>6.0f} {row['theta_y_deg_min']:>6.2f}–{row['theta_y_deg_max']:<6.2f}"
              f" {ty['tresca']:>6.1f}–{ty['von_mises']:<6.1f}  {row['tube_yields_before_wire']!s:>9s}"
              f"  {row['root_yield_knockdown_tolerated']:>8.3f}  {row['margin_over_wind_bark_end']:>6.0f}")
    print("\n  " + result["verdict"])
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
