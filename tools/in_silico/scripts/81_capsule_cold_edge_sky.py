#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
81 — The cold edge of the sensor capsule's thermal envelope WITH the night sky (00_07 HW.37; the capsule envelope is
outside the crown pause — ⚖️ founder 2026-09-26): over thirty winters of hourly weather, how many hours does the
capsule spend below its EDLC's operating floor, and how cold does it get?

WHY A NEW SCRIPT. `71` answers the hot side and leaves the cold side open on purpose: its lump has no sky, so every
hour without solar gain returns the capsule exactly at air temperature, and its cold count is the AIR's (a lower
bound on the capsule's cold hours). `79` has the sky (Brutsaert clear-sky emissivity from the ERA5 dew point) but
couples the capsule to the bark through the flange, and gives the ISOLATED capsule at one reference hour only
(`mechanism.capsule` in its cache). This script runs `71`'s isolated lump hourly over the whole record with `79`'s
sky term. It changes neither `71` nor `79`: both are imported, so their numbers and pins stay where they are.

MODEL — one isothermal lump (`71`'s geometry from tools/cad/cem/radome.json), steady within each hour:
    α·F·DIF·A_exp = h_c·A_exp·(T − T_a) + ε·σ·A_exp·(T⁴ − T_env⁴),   T_env⁴ = F·T_sky⁴ + (1 − F)·T_a⁴
  • h_c = max(natural, forced) with `71`'s kernels — natural convection called with |ΔT| (a lump colder than the air
    drives the same boundary layer downward; `71` zeroes it there, which is right for its hot bound only), forced
    cross-flow at u = k·u10 for `71`'s k ∈ {0, 0.1, 0.3}.
  • Long-wave exchanged at full T⁴, not linearised: the cold edge sits exactly where the linearisation around
    the air temperature is worst.
  • Sky — the two ends of `79`: CLEAR every hour (T_sky⁴ = ε_sky·T_a⁴, ε_sky by Brutsaert 1975 from `79`) and
    OVERCAST every hour (T_sky = T_a, no long-wave deficit — on a sunless hour this is `71`'s lump exactly).
    Real cloud cover is not in the tree.
  • Sun — the two ends of `79`: none, and ERA5 DIFFUSE through the sky view F (no beam: under a crown or on a north
    face), at the LIGHTEST specified finish α = 0.50 (02_01 §5.2) — the least daytime gain, the cold end of `71`'s
    α sweep.
  • ε = 0.90, F = 0.5 — `71`'s, both ours.
  • Solved per hour by vectorised bisection: the residual falls monotonically in T (convection and radiation both
    grow with T), so the root is unique and the bracket cannot lose it.

DIRECTION OF EACH CHOICE, stated per quantity:
  • Isolated lump: no heat from the bark through the flange — the capsule is COLDER here than tied to the flange
    (`79` keeps that end): the clear-sky end is a lower bound on the temperature and an upper bound on cold hours.
  • Clear every hour: below any real winter, which has cloudy nights — the same direction again.
  • Steady state per hour: the capsule's own heat capacity is not modelled. It averages past hours, so with it the
    minimum cannot be deeper than here — the same direction once more; the hour count and the longest spell are not
    bounded the same way (a lag can stretch a cold spell as well as shave it).
  • No sun, or diffuse sun at the lightest α without beam: daytime gain absent or at its smallest — the cold side
    again. A clear sky with no sun all day is below any real winter day — the model's lower bound, as in `79`.
  • Which end the site leans to near the floor is MEASURED on ERA5's own sky, not assumed: on the winter days the
    air's minimum falls below a threshold, the share of daylight hours with direct normal irradiance ≥ 120 W/m²
    (the WMO sunshine threshold, WMO-No. 8 Part I ch. 8) against the same share for every winter day — the day's
    sky as the proxy for the night's, which has no radiation to read; and the 10-m wind at the hours the air is
    below the floor against every winter hour. Both are reported as numbers; only the «leans to the clear end»
    word is chosen by them (the cold days' share above the winter's). The 10-m wind says nothing about k, the share
    that reaches the trunk under a crown — that stays ours.
  So the deepest run is the cold edge and the shallowest the warm one; both are SELECTED from the numbers, and a real
  site lies between them. The longest spell counts consecutive hours below the floor on the record's own clock.

CONTROLS that can fail (raise, never warn):
  1. the reference hour of `79` (still air, no sun, clear sky) must reproduce `79`'s cached capsule depression;
  2. overcast with no sun must return T = T_a EXACTLY on every hour (it is `71`'s lump without gain) — it fails if
     the exact-root branch of `solve` is lost, which would tip the record's hours that sit on the floor below it;
  3. this script's air count below the floor must equal `71`'s cached one — the same file, the same clock;
  4. the record must be one unbroken hourly clock, or a «spell» would join hours across a gap.

CAN show: hours and calendar days per 30 years with the isolated capsule below the EDLC operating floor (−25 °C) and
below the capsule requirement (−40 °C), the longest spell below the floor, the coldest capsule hour and the air at
it — per sky end, sun end and wind; the sunshine share and the wind on the cold days, against the whole winter.
CANNOT show: the temperature INSIDE the capsule (one lump, no internal resistance — a thermocouple under the radome
is the 👤 leg of HW.37); real cloud cover; snow or rime on the radome; the EDLC's behaviour below its floor (only
the vendor can say — node_edlc_rfq Part B); ERA5 smoothing of station extremes (it moves the cold edge DOWN).

Run:  python tools/in_silico/scripts/81_capsule_cold_edge_sky.py      # seconds (30 years hourly, 12 runs)
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, EDLC_OPERATING_MIN_C, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = "Cold edge of the sensor capsule's thermal envelope with clear-sky and overcast long-wave exchange, over thirty years of hourly weather, against the operating floor of its supercapacitor."  # its row in the paper SI (72): English, no repo jargon

OUT_DIR = CACHE_DIR / "thermal"
OUT = OUT_DIR / "capsule_cold_edge_sky.json"
SCRIPTS = Path(__file__).resolve().parent

REGIMES = (("clear_no_sun", False, False), ("overcast_no_sun", True, False),     # (name, overcast sky, diffuse sun) — `79`'s
           ("clear_diffuse_sun", False, True), ("overcast_diffuse_sun", True, True))
SUNSHINE_DNI_W_M2 = 120.0              # WMO-No. 8 Part I ch. 8: sunshine = direct (normal) irradiance above this
COLD_DAY_THRESHOLDS_C = (-15.0, -20.0, EDLC_OPERATING_MIN_C)   # a day counts when its air minimum falls below
WINTER_MONTHS = (12, 1, 2)
BISECT_LO_K, BISECT_HI_K = -40.0, 80.0   # bracket around the air: the root is inside for every hour of the record
BISECT_TOL_K = 1e-6
BISECT_MAX_ITER = 80
MECHANISM_TOL_K = 0.01                   # `79` rounds its depression to 0.01 K


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
S79 = _load("s79_frost", "79_flange_cambium_frost.py")
SIGMA, EPSILON, SKY_VIEW = S71.SIGMA, S71.EPSILON, S71.SKY_VIEW
ALPHA_COLD = S71.ALPHA_EDGES[0]           # the lightest specified finish — least daytime gain
CAPSULE_REQUIREMENT_MIN_C = S71.CAPSULE_ENVELOPE_C[0]


def residual(t, t_air, q_area, t_env4, d_m, u):
    """Net heat into the lump per unit exposed area at temperature t (W/m²); falls monotonically in t."""
    dt = t - t_air
    film = 0.5 * (t + t_air)
    h_c = np.maximum(S71.h_natural(d_m, np.abs(dt), film), S71.h_forced(d_m, u, film))
    return q_area - h_c * dt - EPSILON * SIGMA * ((t + 273.15) ** 4 - t_env4)


def solve(t_air, q_area, t_env4, d_m, u):
    """Vectorised bisection on `residual`; raises if the bracket does not hold or the loop does not close. An hour
    with no gain and no long-wave deficit has its root at the air EXACTLY (the residual there is 0.0 in floating
    point, and the root is unique) and is returned as such: ERA5 air comes in 0.1 K steps, so hours sit exactly ON
    the floor, and a root within the bisection tolerance would tip them below it."""
    exact = residual(t_air, t_air, q_area, t_env4, d_m, u) == 0.0
    lo, hi = t_air + BISECT_LO_K, t_air + BISECT_HI_K
    if np.any(residual(lo, t_air, q_area, t_env4, d_m, u) <= 0) or np.any(residual(hi, t_air, q_area, t_env4, d_m, u) >= 0):
        raise RuntimeError("bisection bracket does not contain the root for every hour")
    for _ in range(BISECT_MAX_ITER):
        mid = 0.5 * (lo + hi)
        up = residual(mid, t_air, q_area, t_env4, d_m, u) > 0
        lo, hi = np.where(up, mid, lo), np.where(up, hi, mid)
        if np.max(hi - lo) < BISECT_TOL_K:
            return np.where(exact, t_air, 0.5 * (lo + hi))
    raise RuntimeError(f"bisection did not close in {BISECT_MAX_ITER} iterations")


def t_env4(overcast: bool, t_air, t_dew):
    t_a4 = (t_air + 273.15) ** 4
    if overcast:
        return t_a4
    return SKY_VIEW * S79.sky_emissivity(t_air, t_dew) * t_a4 + (1.0 - SKY_VIEW) * t_a4


def control_mechanism(d_m: float) -> dict:
    """Control 1: `79`'s reference hour must come out at `79`'s own cached depression."""
    cache79 = json.loads((OUT_DIR / "flange_cambium_frost.json").read_text())
    want = float(cache79["mechanism"]["capsule"]["equilibrium_minus_air_K"])
    ref = cache79["mechanism"]["reference_hour"]
    ta, td = np.array([ref["t_air_C"]]), np.array([ref["t_dew_C"]])
    got = float(solve(ta, np.zeros(1), t_env4(False, ta, td), d_m, np.zeros(1))[0] - ta[0])
    if abs(got - want) > MECHANISM_TOL_K:
        raise SystemExit(f"control 1 failed: reference hour gives {got:.3f} K, `79` caches {want:.2f} K")
    return {"reference_hour": ref, "depression_here_K": round(got, 3), "depression_in_79_K": want}


def deg(x: float, nd: int = 1) -> str:
    """A temperature for prose, with the typographic minus the docs quote."""
    return f"{x:.{nd}f}".replace("-", "−")


def longest_spell(mask) -> int:
    """Longest run of consecutive True hours (control 4 has proven the clock unbroken)."""
    edges = np.diff(np.concatenate(([0], mask.astype(np.int8), [0])))
    starts, ends = np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)
    return int((ends - starts).max()) if starts.size else 0


def sky_on_cold_days(time, t_air, dni, dif, u10) -> dict:
    """ERA5's own sky and wind on the cold days, against every winter day (the docstring's proxy). Days are cut on
    the record's clock (fixed UTC+3, the data README), as in `71`. Stored at the precision the verdict prints, so
    the prose never re-rounds a rounded row (in-silico §When Modifying #6)."""
    winter = np.isin(np.array([int(s[5:7]) for s in time]), WINTER_MONTHS)
    days, idx = np.unique(np.array([s[:10] for s in time]), return_inverse=True)
    day_min = np.full(days.size, np.inf)
    np.minimum.at(day_min, idx, t_air)
    daylight = winter & ((dni > 0) | (dif > 0))

    def share(mask):
        hours = int(mask.sum())
        return {"daylight_hours": hours, "sunshine_share": round(float((dni[mask] >= SUNSHINE_DNI_W_M2).mean()), 2)}

    floor = t_air < EDLC_OPERATING_MIN_C
    return {
        "winter_months": list(WINTER_MONTHS),
        "sunshine_dni_w_m2": SUNSHINE_DNI_W_M2,
        "all_winter_days": share(daylight),
        "days_with_air_min_below": {f"{c:.0f}": share(daylight & (day_min[idx] < c)) for c in COLD_DAY_THRESHOLDS_C},
        "u10_median_m_s": {"hours_air_below_floor": round(float(np.median(u10[floor])), 1),
                           "all_winter_hours": round(float(np.median(u10[winter])), 1)},
    }


def stats(t, time, t_air) -> dict:
    """Counts for one temperature series `t` (the capsule's in `runs`, the air's itself in `air`)."""
    below = t < EDLC_OPERATING_MIN_C
    i = int(np.argmin(t))
    return {
        "hours_below_floor": int(below.sum()),
        "days_below_floor": len({s[:10] for s in time[below]}),
        "longest_spell_below_floor_h": longest_spell(below),
        "hours_below_capsule_requirement": int((t < CAPSULE_REQUIREMENT_MIN_C).sum()),
        "coldest_c": round(float(t[i]), 2),
        "at": str(time[i]),
        "t_air_at_coldest_c": round(float(t_air[i]), 2),
        "depression_at_coldest_K": round(float(t[i] - t_air[i]), 2),
    }


def main() -> int:
    banner("HW.37 — the capsule's cold edge WITH the night sky (ERA5 Cherkasy, hourly 1991–2020)")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    geo = S71.geometry()
    d_m = geo["dome_diameter_mm"] * 1e-3
    w = S79.load_weather()
    time, t_air, t_dew, dif, u10 = w["time"], w["t_air"], w["t_dew"], w["dif"], w["u10"]
    dni = S71.load_hours()["dni"]        # `79`'s join carries no beam; `71`'s loader reads the same file and clock
    n = len(t_air)
    years = n / 8766.0
    q_sun = ALPHA_COLD * SKY_VIEW * dif   # W/m² of exposed area: `71`'s α·F·DIF with no beam, divided by A_exp
    step = np.diff(time.astype("datetime64[h]")).astype(int)
    if not np.all(step == 1):
        raise SystemExit(f"control 4 failed: the hourly clock breaks at {int(np.sum(step != 1))} places")
    print(f"  control 4: {n} hours on one unbroken hourly clock ✓")

    mech = control_mechanism(d_m)
    print(f"  control 1: reference hour {mech['depression_here_K']:+.3f} K here ⊥ {mech['depression_in_79_K']:+.2f} K in `79` ✓")

    cap71 = json.loads((OUT_DIR / "capsule_envelope.json").read_text())["cold_hours_below_edlc_floor"]
    air = stats(t_air, time, t_air)
    if air["hours_below_floor"] != cap71["hours"] or air["days_below_floor"] != cap71["days"]:
        raise SystemExit(f"control 3 failed: air below the floor {air['hours_below_floor']} h / {air['days_below_floor']} d "
                         f"here ⊥ {cap71['hours']} h / {cap71['days']} d in `71`")
    print(f"  control 3: air below {deg(EDLC_OPERATING_MIN_C, 0)} °C — {air['hours_below_floor']} h on "
          f"{air['days_below_floor']} days, coldest {air['coldest_c']:.1f} °C (= `71`) ✓")

    runs, raw_min = {}, {}
    zero = np.zeros_like(t_air)
    for name, overcast, sun in REGIMES:
        env4 = t_env4(overcast, t_air, t_dew)
        runs[name] = {}
        for k in S71.WIND_K:
            t_cap = solve(t_air, q_sun if sun else zero, env4, d_m, k * u10)
            if overcast and not sun and not np.array_equal(t_cap, t_air):
                gap = float(np.max(np.abs(t_cap - t_air)))
                raise SystemExit(f"control 2 failed: overcast with no sun sits up to {gap:.2e} K off the air (k = {k})")
            runs[name][f"k={k}"] = r = stats(t_cap, time, t_air)
            raw_min[(name, f"k={k}")] = float(t_cap.min())
            print(f"  {name:20s} k {k:.1f}: below the floor {r['hours_below_floor']:5d} h on {r['days_below_floor']:3d} "
                  f"days, longest spell {r['longest_spell_below_floor_h']:3d} h · below {deg(CAPSULE_REQUIREMENT_MIN_C, 0)} °C "
                  f"{r['hours_below_capsule_requirement']:3d} h · coldest {r['coldest_c']:6.2f} °C ({r['at']}, air "
                  f"{r['t_air_at_coldest_c']:.1f})")
    print("  control 2: overcast with no sun returns the air temperature on every hour ✓")
    sky = sky_on_cold_days(time, t_air, dni, dif, u10)
    floor_key = f"{EDLC_OPERATING_MIN_C:.0f}"
    for c, r in sky["days_with_air_min_below"].items():
        print(f"  winter days with air min < {c} °C: sunshine {r['sunshine_share']:.2f} of {r['daylight_hours']} daylight h")
    print(f"  every winter day: sunshine {sky['all_winter_days']['sunshine_share']:.2f} of "
          f"{sky['all_winter_days']['daylight_hours']} daylight h · u10 median "
          f"{sky['u10_median_m_s']['hours_air_below_floor']:.1f} m/s below the floor ⊥ "
          f"{sky['u10_median_m_s']['all_winter_hours']:.1f} m/s every winter hour")

    # ── verdict, built from the numbers above (in-silico §When Modifying #5) ──────────────────────────────
    flat = [(name, k, r) for name, by_k in runs.items() for k, r in by_k.items()]
    deep_n, deep_k, deep = max(flat, key=lambda x: (x[2]["hours_below_floor"], -x[2]["coldest_c"]))
    shal_n, shal_k, shallow = min(flat, key=lambda x: (x[2]["hours_below_floor"], -x[2]["coldest_c"]))
    coldest = min(raw_min.values())   # the prose prints the raw minimum, not the 2-decimal row (#6)
    longest = max(r["longest_spell_below_floor_h"] for _, _, r in flat)
    below_req = max(r["hours_below_capsule_requirement"] for _, _, r in flat)

    def words(name, k):
        sky, sun = name.split("_", 1)
        sun = {"no_sun": "no sun", "diffuse_sun": "diffuse sun"}[sun]
        wind = "still air" if k == "k=0.0" else f"u = {k[2:]}·u10"
        return f"{sky} sky every hour, {sun}, {wind}"

    factor = deep["hours_below_floor"] / air["hours_below_floor"]
    req = f"the capsule requirement {deg(CAPSULE_REQUIREMENT_MIN_C, 0)} °C"
    req_clause = f"no run crosses {req}" if below_req == 0 else f"{req} is crossed for up to {below_req} h"
    verdict = (f"With the night sky the isolated capsule spends between {shallow['hours_below_floor']} h on "
               f"{shallow['days_below_floor']} days ({words(shal_n, shal_k)}) and {deep['hours_below_floor']} h on "
               f"{deep['days_below_floor']} days ({words(deep_n, deep_k)}) in {years:.0f} years below the EDLC floor "
               f"{deg(EDLC_OPERATING_MIN_C, 0)} °C, against the air's {air['hours_below_floor']} h on "
               f"{air['days_below_floor']} days — up to ×{factor:.1f}; the longest spell below the floor is {longest} h "
               f"and the coldest capsule hour {deg(coldest)} °C; {req_clause}. A real winter lies between the edges.")
    cold_share = sky["days_with_air_min_below"][floor_key]["sunshine_share"]
    all_share = sky["all_winter_days"]["sunshine_share"]
    lean = "leans to the clear end" if cold_share > all_share else "does not lean to the clear end"
    verdict += (f" On the winter days the air falls below the floor, ERA5's own daylight sky is sunny for "
                f"{cold_share:.2f} of its hours against {all_share:.2f} for every winter day (direct normal irradiance "
                f"≥ {SUNSHINE_DNI_W_M2:.0f} W/m², the WMO threshold; the day's sky as the night's proxy), so near the "
                f"floor the site {lean}; its 10-m wind in the hours below the floor has a median of "
                f"{sky['u10_median_m_s']['hours_air_below_floor']:.1f} m/s against "
                f"{sky['u10_median_m_s']['all_winter_hours']:.1f} m/s for every winter hour.")
    edges = {"deep": {"regime": deep_n, "wind": deep_k, **deep}, "shallow": {"regime": shal_n, "wind": shal_k, **shallow},
             "coldest_c": round(coldest, 2), "longest_spell_below_floor_h": longest,
             "max_hours_below_capsule_requirement": below_req,
             "deep_over_air": round(factor, 2)}
    print(f"\n  {verdict}")

    out = {
        "question": "hours per 30 years with the ISOLATED capsule below the EDLC operating floor, with the night sky "
                    "(00_07 HW.37); the edge 71 left open",
        "method": "71's lump (geometry, Churchill–Chu with |ΔT|, Churchill–Bernstein) + 79's Brutsaert clear sky; "
                  "steady per hour, full T⁴, vectorised bisection",
        "inputs": {
            "geometry": geo,
            "epsilon": EPSILON, "sky_view": SKY_VIEW, "alpha": ALPHA_COLD,
            "regimes": {"clear": "Brutsaert 1975 via 79 (ERA5 dew point)", "overcast": "T_sky = T_air",
                        "no_sun": "no solar gain", "diffuse_sun": "ERA5 diffuse through F, no beam"},
            "wind_k": list(S71.WIND_K),
            "edlc_floor_c": EDLC_OPERATING_MIN_C,
            "capsule_requirement_min_c": CAPSULE_REQUIREMENT_MIN_C,
            "n_hours": n,
            "years": round(years, 1),
        },
        "controls": {"mechanism_vs_79": mech, "overcast_no_sun_equals_air_every_hour": True,
                     "air_count_equals_71": {"hours": air["hours_below_floor"], "days": air["days_below_floor"]},
                     "unbroken_hourly_clock": True},
        "air": air,
        "runs": runs,
        "edges": edges,
        "sky_on_cold_days": sky,
        "verdict": verdict,
        "ceilings": [
            "isolated lump — no heat from the bark through the flange: colder than the capsule tied to the flange",
            "clear sky every hour at the clear end; real cloud cover is not in the tree",
            "no sun all day with a clear sky is below any real winter day — the model's lower bound, as in 79",
            "steady per hour — the capsule's heat capacity is not modelled; it averages past hours, so the minima here "
            "are not shallower than with it, while the hour count and the spell are not bounded the same way",
            "one isothermal lump — the temperature INSIDE the capsule is the thermocouple leg of HW.37",
            "ERA5 smooths station extremes — the true cold edge sits lower by an unknown margin",
            "no snow or rime on the radome",
        ],
    }
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"\n  wrote {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
