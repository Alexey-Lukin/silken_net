#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.37 (leg «теплова огинаюча капсули ⊥ рейтинг вцілілого EDLC») — how hot does the Soldier capsule get
under its PEEK radome, against the operating rating of the surviving EDLC (`KR-5R5H474-R`, 02_03 §12.1),
while canon 02_02 §2.1 gives the capsule −40…+85 °C.

The question is a BOUND, not a forecast: does any hour of thirty Cherkasy years put the capsule above the
rating? A lumped energy balance per hour answers it. A forecast for a real trunk would need what no file in
the tree has — bark surface temperature, canopy transmittance at the install point, the radome's finish.

MODEL — one isothermal lump (radome + cavity air + boards + EDLC), quasi-steady per hour (a Ø25 lump of a
few grams against a loss coefficient of a few hundredths W/K settles in minutes, so an hour is steady):
    α·(DNI·A_proj + F·DIF·A_exp) = (h_c + h_r)·A_exp·(T_cap − T_air)
  • A_proj — the LARGEST projection of the exposed radome over ALL beam directions, √(A_crown² + (D·H)²).
    The axis sits at the 30° install angle (01_04 §3.2) and a trunk faces any azimuth, so the worst
    orientation is taken instead of a sun-position model — an UPPER bound on the direct gain by construction.
  • A_exp — crown disc + side wall of the part standing over the bark. H over the bark is read from the CEM
    as cavity + crown, which is how 01_04 §5.5 writes it («18.0 (порожнина 13.0 + корона 5.0)»), and the
    crown rise equals the edge radius by construction (picogk skill, radome row), so `bell_radius_mm` is
    the crown term. The flange's catalytic band above the bark is NOT added — it would only ADD area.
  • F — sky view factor of that surface for the diffuse beam: 0.5, a surface on a vertical trunk sees half
    a sky. ⚠️ Ours, not measured.
  • h_c — the larger of natural convection (Churchill–Chu, horizontal cylinder) and forced convection
    (Churchill–Bernstein) at trunk-level wind u = k·u10. k = 0 (still air) is the BOUND; k > 0 is a
    bracket, because sub-canopy wind reduction varies more than 4× in the literature (`62`'s docstring).
  • h_r — linearised long-wave exchange 4·ε·σ·T_m³ with surroundings AT AIR temperature: the sky's cold is
    ignored, which is conservative for the hot bound and makes the night capsule track the air exactly.
  • BASE — adiabatic. The PEEK thermal break of Zone 2 stands between the capsule and the stem, so the
    stem neither cools nor heats the lump much through the anchor.
    ⛔ What is NOT modelled and moves the hot answer UP: sunlit bark around the flange rim. A dark bark
    surface in full sun can run hotter than the small capsule (a large flat surface has a lower h than a
    Ø25 body), and the rim would then conduct heat IN. No bark temperature exists in the tree, so this is a
    named ceiling, not a term — and it is the first thing a field reading should settle.

INPUTS THAT ARE BRACKETS, NOT NUMBERS:
  • α, solar absorptance of the radome — canon does NOT specify the finish (`radome.json` surface_finish:
    NOT SPECIFIED IN CANON) and names a bark-coloured PC/ASA as a declared alternative (02_01 §5.2). So α is
    swept over [0.50, 0.95] and every verdict is given PER α. No PEEK absorptance was read from a primary:
    the low end stands for a light unfilled polymer, the high end for a dark one.
  • ε = 0.90 — ours, typical of polymers in the thermal infrared, not read from a primary.
  • Climate — ERA5 hourly at the Cherkasy grid point (`data/era5_cherkasy/`, provenance in its README).
    ⛔ A reanalysis grid cell smooths extremes: station maxima run hotter than ERA5 by an unknown margin.

TWO CASES — keep them apart:
  (a) SUNLIT — the beam reaches the capsule (forest edge, gap, thinned stand): the ENVELOPE case.
  (b) SHADED — no direct beam, open-sky diffuse only: an UPPER bound on the under-crown case the leg names
      (a crown also cuts most of the diffuse).

SECOND OUTPUT — the temperature the EDLC AGES at. 02_03 §12.1 prices the EDLC life at two reference points,
10 °C and 25 °C (00_07 HW.37/HW.7). The rate that matters is the vendor's doubling rule, rate ∝ 2^(T/10),
averaged over the hours, so the equivalent constant temperature is T_eff = 10·log2⟨2^(T/10)⟩ — the same
construction as `51`'s Arrhenius-effective field temperature, with the vendor's rule in place of a fixed Ea.
Life at T_eff comes from `51`'s own kernel (`capacitor_life_hours`), imported, never re-implemented.

THIRD OUTPUT — cold hours below the EDLC operating floor (air; the lump tracks air at night in this model,
and real sky cooling would make the capsule COLDER — so the count is a LOWER bound for the capsule).

    ~/miniforge3/envs/silken_md/bin/python tools/in_silico/scripts/71_capsule_thermal_envelope.py
"""
from __future__ import annotations

import gzip
import importlib.util
import io
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    CACHE_DIR,
    EATON_KR_RATED_HOURS,
    EATON_KR_RATED_TEMP_C,
    EATON_KR_RATED_VOLTAGE_V,
    EDLC_OPERATING_MAX_C,
    EDLC_OPERATING_MIN_C,
    REPO_ROOT,
    THERMAL_DOUBLING_INTERVAL_K,
    VBAT_OV_RATIFIED_V,
    VOLTAGE_DOUBLING_CONSERVATIVE_V,
    VOLTAGE_DOUBLING_OPTIMISTIC_V,
)
from lib.utils import banner

OUT_DIR = CACHE_DIR / "thermal"
DATA_FILE = REPO_ROOT / "tools/in_silico/data/era5_cherkasy/hourly_1991_2020.csv.gz"
RADOME_CEM = REPO_ROOT / "tools/cad/cem/radome.json"
SCRIPT_51 = Path(__file__).resolve().parent / "51_gusak_degradation_model.py"

CAPSULE_ENVELOPE_C = (-40.0, 85.0)   # 02_02 §2.1 — the capsule REQUIREMENT (canon's), printed beside the rating

ALPHA_SWEEP = (0.50, 0.60, 0.70, 0.80, 0.90, 0.95)
ALPHA_EDGES = (0.50, 0.95)           # the two ends the verdicts quote
EPSILON = 0.90                       # ours — see docstring
SKY_VIEW = 0.5                       # ours — see docstring
WIND_K = (0.0, 0.1, 0.3)             # u_trunk = k·u10; k = 0 is the still-air BOUND
WIND_K_TYPICAL = 0.1                 # the aging series take a light breeze, not dead calm, as the typical hour
# The still-air h_c comes from a correlation for a LONG HORIZONTAL cylinder; ours is a short one (Ø25 × 18)
# tilted 30°. ±30 % is the ordinary scatter of such correlations off their home geometry — ours, not a
# measured band — so the hot bound is also printed with h_c scaled down by it, and the verdict quotes both.
H_C_SENSITIVITY = 0.7
SIGMA = 5.670374419e-8
G = 9.81

FIXED_POINT_TOL_K = 1e-6
FIXED_POINT_MAX_ITER = 400


def air_props(t_film_c):
    """Dry air at 1 atm, linear over roughly −30…+80 °C (tabulated values at 20 °C, slopes from the same
    table) — ample for h at the ±0.5 % level the verdicts do not depend on."""
    t = t_film_c - 20.0
    return {
        "k": 0.02514 + 7.4e-5 * t,        # W/m·K
        "nu": 1.516e-5 + 9.0e-8 * t,      # m²/s
        "alpha": 2.074e-5 + 1.3e-7 * t,   # m²/s
        "pr": 0.7309 - 1.5e-4 * t,
    }


def h_natural(d_m, dt, t_film_c):
    """Churchill–Chu, long horizontal cylinder (Incropera eq. 9.34); 0 where the lump is not warmer."""
    p = air_props(t_film_c)
    beta = 1.0 / (t_film_c + 273.15)
    ra = G * beta * np.maximum(dt, 0.0) * d_m ** 3 / (p["nu"] * p["alpha"])
    nu = (0.60 + 0.387 * ra ** (1 / 6) / (1 + (0.559 / p["pr"]) ** (9 / 16)) ** (8 / 27)) ** 2
    return np.where(dt > 0, nu * p["k"] / d_m, 0.0)


def h_forced(d_m, u, t_film_c):
    """Churchill–Bernstein, cylinder in cross-flow (Incropera eq. 7.54); 0 in still air."""
    p = air_props(t_film_c)
    re = np.maximum(u, 0.0) * d_m / p["nu"]
    pr = p["pr"]
    nu = 0.3 + (0.62 * re ** 0.5 * pr ** (1 / 3)) / (1 + (0.4 / pr) ** (2 / 3)) ** 0.25 * (
        1 + (re / 282000.0) ** (5 / 8)) ** (4 / 5)
    return np.where(u > 0, nu * p["k"] / d_m, 0.0)


def geometry() -> dict:
    cem = json.loads(RADOME_CEM.read_text())
    d_mm = float(cem["dome_diameter_mm"])
    h_mm = float(cem["cavity_height_mm"]) + float(cem["bell_radius_mm"])
    a_crown = math.pi * (d_mm / 2) ** 2
    return {
        "dome_diameter_mm": d_mm,
        "h_over_bark_mm": h_mm,
        "h_over_bark_from": "radome.json cavity_height_mm + bell_radius_mm (01_04 §5.5: порожнина + корона)",
        "a_proj_max_mm2": round(math.hypot(a_crown, d_mm * h_mm), 2),
        "a_exp_mm2": round(a_crown + math.pi * d_mm * h_mm, 2),
    }


def solve_t_cap(t_air, q_w, a_exp_m2, d_m, u, h_c_scale=1.0):
    """Vectorised fixed point on T_cap: h depends on ΔT and on the film temperature. Hours with no gain
    are exact (T_cap = T_air) and never enter the iteration. `h_c_scale` exists for ONE sensitivity run
    (H_C_SENSITIVITY); every other call leaves it at 1."""
    t_air = np.asarray(t_air, dtype=float)
    q_w = np.asarray(q_w, dtype=float)
    u = np.broadcast_to(np.asarray(u, dtype=float), t_air.shape)
    out = t_air.copy()
    live = q_w > 0
    if not live.any():
        return out
    ta, q, uu = t_air[live], q_w[live], u[live]
    t = ta + q / (12.0 * a_exp_m2)
    for _ in range(FIXED_POINT_MAX_ITER):
        t_film = 0.5 * (t + ta)
        h_c = h_c_scale * np.maximum(h_natural(d_m, t - ta, t_film), h_forced(d_m, uu, t_film))
        h_r = 4 * EPSILON * SIGMA * (t_film + 273.15) ** 3
        t_new = ta + q / ((h_c + h_r) * a_exp_m2)
        if np.max(np.abs(t_new - t)) < FIXED_POINT_TOL_K:
            out[live] = t_new
            return out
        t = 0.5 * t + 0.5 * t_new
    raise RuntimeError(f"T_cap fixed point did not converge in {FIXED_POINT_MAX_ITER} iterations")


def load_hours() -> dict:
    with gzip.open(DATA_FILE, "rt", encoding="utf-8") as fh:
        body = [ln for ln in fh if ln[:2] in ("ti", "19", "20")]
    arr = np.genfromtxt(io.StringIO("".join(body[1:])), delimiter=",", dtype=None, encoding="utf-8",
                        names=("time", "t", "dni", "dif", "u10"))
    return {
        "time": arr["time"].astype(str),
        "t_air": arr["t"].astype(float),
        "dni": arr["dni"].astype(float),
        "dif": arr["dif"].astype(float),
        "u10": arr["u10"].astype(float) / 3.6,
    }


def t_eff_doubling(series_c) -> float:
    """Equivalent constant temperature under the vendor rule rate ∝ 2^(T/ΔT_double)."""
    k = THERMAL_DOUBLING_INTERVAL_K
    return float(k * math.log2(np.mean(np.power(2.0, np.asarray(series_c) / k))))


def load_capacitor_kernel():
    spec = importlib.util.spec_from_file_location("s51", SCRIPT_51)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.capacitor_life_hours


def life_years(kernel, t_c: float) -> dict:
    hours_per_year = 365.25 * 24.0
    out = {}
    for label, dv in (("optimistic_yr", VOLTAGE_DOUBLING_OPTIMISTIC_V), ("conservative_yr", VOLTAGE_DOUBLING_CONSERVATIVE_V)):
        h = kernel(EATON_KR_RATED_HOURS, EATON_KR_RATED_TEMP_C, EATON_KR_RATED_VOLTAGE_V, t_c,
                   VBAT_OV_RATIFIED_V, dt_double_c=THERMAL_DOUBLING_INTERVAL_K, dv_double_v=dv)
        out[label] = round(h / hours_per_year, 1)
    return out


def main() -> int:
    banner("HW.37 — capsule thermal envelope vs the EDLC operating rating (ERA5 Cherkasy, hourly 1991–2020)")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    geo = geometry()
    a_proj = geo["a_proj_max_mm2"] * 1e-6
    a_exp = geo["a_exp_mm2"] * 1e-6
    d_m = geo["dome_diameter_mm"] * 1e-3
    h = load_hours()
    n = len(h["t_air"])
    print(f"  geometry: Ø{geo['dome_diameter_mm']:.1f} × {geo['h_over_bark_mm']:.1f} mm over the bark · "
          f"A_proj,max {geo['a_proj_max_mm2']:.0f} mm² · A_exp {geo['a_exp_mm2']:.0f} mm²")
    print(f"  climate: {n} hours; air max {h['t_air'].max():.1f} °C, min {h['t_air'].min():.1f} °C")

    # ── 1. the hot bound, per case × α × wind ────────────────────────────────────────────────────────
    hot = {}
    for case, beam in (("sunlit", 1.0), ("shaded", 0.0)):
        hot[case] = {}
        for alpha in ALPHA_SWEEP:
            q = alpha * (beam * h["dni"] * a_proj + SKY_VIEW * h["dif"] * a_exp)
            hot[case][f"{alpha:.2f}"] = {}
            for k in WIND_K:
                t_cap = solve_t_cap(h["t_air"], q, a_exp, d_m, k * h["u10"])
                i = int(np.argmax(t_cap))
                hot[case][f"{alpha:.2f}"][f"{k:.1f}"] = {
                    "t_cap_max_c": round(float(t_cap[i]), 1),
                    "at": str(h["time"][i]),
                    "t_air_c": float(h["t_air"][i]),
                    "margin_to_rating_k": round(EDLC_OPERATING_MAX_C - float(t_cap[i]), 1),
                }
    worst = hot["sunlit"][f"{ALPHA_EDGES[1]:.2f}"]["0.0"]
    lightest = hot["sunlit"][f"{ALPHA_EDGES[0]:.2f}"]["0.0"]
    shaded_worst = hot["shaded"][f"{ALPHA_EDGES[1]:.2f}"]["0.0"]
    # One sensitivity, on the worst cell only: the still-air correlation off its home geometry.
    sens = {}
    for alpha in ALPHA_EDGES:
        q = alpha * (h["dni"] * a_proj + SKY_VIEW * h["dif"] * a_exp)
        t_cap = solve_t_cap(h["t_air"], q, a_exp, d_m, 0.0, h_c_scale=H_C_SENSITIVITY)
        i = int(np.argmax(t_cap))
        sens[f"{alpha:.2f}"] = {"t_cap_max_c": round(float(t_cap[i]), 1), "at": str(h["time"][i]),
                                "margin_to_rating_k": round(EDLC_OPERATING_MAX_C - float(t_cap[i]), 1)}
    sens_worst = sens[f"{ALPHA_EDGES[1]:.2f}"]
    print("\n  1. Hottest hour of the capsule (still air = the bound; adiabatic base):")
    for case in ("sunlit", "shaded"):
        row = " · ".join(f"α {a}: {hot[case][a]['0.0']['t_cap_max_c']:.1f}" for a in hot[case])
        print(f"     {case:<7s} {row} °C")
    print(f"     rating {EDLC_OPERATING_MAX_C:.0f} °C → margin ≥ {worst['margin_to_rating_k']:.1f} K sunlit "
          f"(α {ALPHA_EDGES[1]}, {worst['at']}, air {worst['t_air_c']:.1f} °C) · ≥ {shaded_worst['margin_to_rating_k']:.1f} K shaded")
    print(f"     h_c × {H_C_SENSITIVITY}: sunlit α {ALPHA_EDGES[0]} → {sens[f'{ALPHA_EDGES[0]:.2f}']['t_cap_max_c']:.1f} °C · "
          f"α {ALPHA_EDGES[1]} → {sens_worst['t_cap_max_c']:.1f} °C (margin {sens_worst['margin_to_rating_k']:.1f} K)")
    rating_exceeded = max(worst["t_cap_max_c"], sens_worst["t_cap_max_c"]) > EDLC_OPERATING_MAX_C

    # ── 2. the temperature the EDLC ages at (vendor doubling rule), and its life at the ratified VBAT_OV ──
    kernel = load_capacitor_kernel()
    aging = {"air": {"t_eff_c": round(t_eff_doubling(h["t_air"]), 2), "mean_c": round(float(h["t_air"].mean()), 2)}}
    for case, beam in (("shaded", 0.0), ("sunlit", 1.0)):
        for alpha in ALPHA_EDGES:
            for k in (0.0, WIND_K_TYPICAL):
                q = alpha * (beam * h["dni"] * a_proj + SKY_VIEW * h["dif"] * a_exp)
                t_cap = solve_t_cap(h["t_air"], q, a_exp, d_m, k * h["u10"])
                aging[f"{case}_alpha{alpha:.2f}_k{k:.1f}"] = {
                    "t_eff_c": round(t_eff_doubling(t_cap), 2),
                    "mean_c": round(float(t_cap.mean()), 2),
                    "hours_above_60c": int((t_cap > 60.0).sum()),
                }
    for row in aging.values():
        row["life_at_ratified_vbat_ov"] = life_years(kernel, row["t_eff_c"])
    ref = {f"{t:.0f}": life_years(kernel, t) for t in (10.0, 25.0)}
    print("\n  2. Aging temperature (vendor 2× per 10 K) and EDLC life at the ratified VBAT_OV "
          f"{VBAT_OV_RATIFIED_V:.3f} V (conservative–optimistic):")
    print(f"     reference points of 02_03 §12.1: 10 °C → {ref['10']['conservative_yr']}–{ref['10']['optimistic_yr']} yr · "
          f"25 °C → {ref['25']['conservative_yr']}–{ref['25']['optimistic_yr']} yr")
    for key, row in aging.items():
        life = row["life_at_ratified_vbat_ov"]
        print(f"     {key:<24s} T_eff {row['t_eff_c']:5.2f} °C → {life['conservative_yr']:5.1f}–{life['optimistic_yr']:5.1f} yr")
    t_eff_air = aging["air"]["t_eff_c"]
    life_air = aging["air"]["life_at_ratified_vbat_ov"]
    shaded_keys = [k for k in aging if k.startswith("shaded")]
    sunlit_keys = [k for k in aging if k.startswith("sunlit")]
    cons_all = [aging[k]["life_at_ratified_vbat_ov"]["conservative_yr"] for k in aging]
    opt_all = [aging[k]["life_at_ratified_vbat_ov"]["optimistic_yr"] for k in aging]

    # ── 3. cold hours below the EDLC floor (air; a LOWER bound for the capsule) ─────────────────────────
    years = n / 8766.0
    cold = h["t_air"] < EDLC_OPERATING_MIN_C
    cold_days = sorted({t[:10] for t in h["time"][cold]})
    print(f"\n  3. Air below the EDLC floor {EDLC_OPERATING_MIN_C:.0f} °C: {int(cold.sum())} hours on "
          f"{len(cold_days)} days in {years:.0f} years (coldest hour {h['t_air'].min():.1f} °C) — a LOWER bound "
          f"for the capsule, which real sky cooling makes colder at night")

    # ── verdicts, built from the numbers above (in-silico §When Modifying #5) ─────────────────────────
    # Every judging clause is chosen BY the numbers, not typed beside them: the h_c shift is the model's
    # own uncertainty measure, so «of the order of» means the dark margin is under twice that shift.
    h_c_shift = sens_worst["t_cap_max_c"] - worst["t_cap_max_c"]
    dark_judgement = ("is of the order of the model's own uncertainty"
                      if sens_worst["margin_to_rating_k"] <= 2.0 * h_c_shift
                      else "stays well clear of the model's own uncertainty")
    hottest_any = max(worst["t_cap_max_c"], sens_worst["t_cap_max_c"])
    capsule_upper = ("is not approached" if hottest_any < CAPSULE_ENVELOPE_C[1] - 10.0
                     else "is approached" if hottest_any < CAPSULE_ENVELOPE_C[1] else "is EXCEEDED")
    verdict_hot = (
        f"{'EXCEEDED' if rating_exceeded else 'Not exceeded'}: the hottest capsule hour of {years:.0f} ERA5 years is "
        f"{worst['t_cap_max_c']:.1f} °C (sunlit, α {ALPHA_EDGES[1]}, still air, adiabatic base; {worst['at']}, air "
        f"{worst['t_air_c']:.1f} °C) against the {EDLC_OPERATING_MAX_C:.0f} °C EDLC rating — margin "
        f"{worst['margin_to_rating_k']:.1f} K; {lightest['t_cap_max_c']:.1f} °C at α {ALPHA_EDGES[0]}; shaded (open-sky "
        f"diffuse only) {shaded_worst['t_cap_max_c']:.1f} °C. With still-air h_c × {H_C_SENSITIVITY} (the correlation off "
        f"its home geometry) the sunlit worst is {sens_worst['t_cap_max_c']:.1f} °C — margin "
        f"{sens_worst['margin_to_rating_k']:.1f} K (the h_c shift alone is {h_c_shift:.1f} K), so for a DARK finish in "
        f"full sun the margin {dark_judgement}, while a light one keeps ≥ "
        f"{EDLC_OPERATING_MAX_C - sens[f'{ALPHA_EDGES[0]:.2f}']['t_cap_max_c']:.1f} K. The capsule requirement's upper "
        f"{CAPSULE_ENVELOPE_C[1]:.0f} °C {capsule_upper} in this climate. NOT modelled and moving the hot answer "
        f"UP: sunlit bark conducting through the flange rim; ERA5 smoothing of station maxima."
    )
    def _side(vals):
        return ("stays BELOW 20 yr in every case" if max(vals) < 20 else
                "stays ABOVE 20 yr in every case" if min(vals) >= 20 else "crosses 20 yr between cases")
    if min(cons_all) >= 20:
        claim = "so 20 years holds in every case at both ends of the voltage-coefficient bracket"
    elif max(cons_all) < 20 <= min(opt_all):
        claim = "so the 20-year claim now rests on the vendor voltage coefficient alone"
    elif max(opt_all) < 20:
        claim = "so 20 years fails in every case even at the optimistic coefficient"
    else:
        claim = "so the 20-year claim depends on the case (finish, sun, wind) as well as on the coefficient"
    verdict_aging = (
        f"The EDLC ages at T_eff {t_eff_air:.1f} °C in open air (vendor 2×/10 K over {n} hours), not at the 10 °C "
        f"reference point; under the radome {min(aging[k]['t_eff_c'] for k in shaded_keys):.1f}–"
        f"{max(aging[k]['t_eff_c'] for k in shaded_keys):.1f} °C shaded and "
        f"{min(aging[k]['t_eff_c'] for k in sunlit_keys):.1f}–{max(aging[k]['t_eff_c'] for k in sunlit_keys):.1f} °C "
        f"sunlit. At the ratified VBAT_OV the life is {life_air['conservative_yr']}–{life_air['optimistic_yr']} yr in "
        f"air and {min(cons_all)}–{max(opt_all)} yr across every case: the conservative voltage coefficient "
        f"{_side(cons_all)}, the optimistic one {_side(opt_all)} — {claim}."
    )
    print("\n  VERDICT (hot):   " + verdict_hot)
    print("  VERDICT (aging): " + verdict_aging)

    out = {
        "question": "00_07 HW.37 leg: capsule thermal envelope vs the surviving EDLC operating rating",
        "rating_c": {"edlc_operating_min": EDLC_OPERATING_MIN_C, "edlc_operating_max": EDLC_OPERATING_MAX_C,
                     "capsule_requirement": list(CAPSULE_ENVELOPE_C)},
        "geometry": geo,
        "inputs": {
            "alpha_sweep": list(ALPHA_SWEEP), "alpha_owner": "ours — finish NOT SPECIFIED IN CANON (radome.json)",
            "epsilon": EPSILON, "epsilon_owner": "ours",
            "sky_view": SKY_VIEW, "sky_view_owner": "ours",
            "wind_k": list(WIND_K), "wind_k_typical_for_aging": WIND_K_TYPICAL,
            "climate": "ERA5 hourly, Cherkasy grid point 49.5N 32.0E, 1991-2020 (data/era5_cherkasy/README.md)",
            "n_hours": n,
        },
        "hot_bound": hot,
        "hot_bound_h_c_sensitivity": {"h_c_scale": H_C_SENSITIVITY, "sunlit_still_air": sens,
                                      "why": "long-horizontal-cylinder correlation applied to a short tilted one — ours"},
        "rating_exceeded": rating_exceeded,
        "aging": aging,
        "aging_reference_points_02_03": ref,
        "cold_hours_below_edlc_floor": {"hours": int(cold.sum()), "days": len(cold_days), "years": round(years, 1),
                                        "coldest_air_c": float(h["t_air"].min()),
                                        "bound": "LOWER bound for the capsule (no sky cooling in the model)"},
        "not_modelled": [
            "sunlit bark conducting heat through the flange rim — moves the hot bound UP; no bark temperature in the tree",
            "ERA5 smoothing of station extremes — moves the hot bound UP by an unknown margin",
            "canopy transmittance for beam and diffuse — the shaded case is open-sky diffuse, an UPPER bound on under-crown",
            "sky long-wave cooling at night — makes the capsule colder than air, so cold hours are a LOWER bound",
        ],
        "verdict_hot": verdict_hot,
        "verdict_aging": verdict_aging,
    }
    path = OUT_DIR / "capsule_envelope.json"
    path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"\n  wrote {path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
