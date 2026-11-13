#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""HW.6 — which cloudy-sky long-wave form the winter sky follows: `79`'s two forms and its clear-sky formula against a
satellite-derived product, and `79`'s frost half re-run under that product's sky.

QUESTION. `79` weighs real cloud through two long-wave forms that disagree under full cover — «linear» (a covered sky
is black) and «B82» (clear sky × (1 + C·c²), C 0.22) — and says in its own ceilings that which one holds decides the
sign of the shift under the flange. Canon keeps that open (`docs/01_04 §3.1`). This script does not model the sky: it
reads one, and asks (A) which form the read sky follows and (B) what `79`'s frost half says under it.

DATA. `tools/in_silico/data/power_cherkasy_longwave/` — NASA POWER hourly, the ERA5 files' own point, 2001–2020:
all-sky and clear-sky downward long-wave at the surface and cloud amount (the response's header names CERES SYN1deg),
2 m temperature and dew/frost point (MERRA-2). How the product is computed, on what cell and how well at an hourly
step is NOT read from its primary here (the data README names it); it is not a measurement at the site.

A — FORMS AGAINST THE PRODUCT (no simulation), frost hours of `79`'s winter months (frost by ERA5's air):
  • the cloud ENHANCEMENT E = all-sky / clear-sky flux of the product — no temperature enters THAT side. The forms' own
    E is (c + (1−c)·ε)/ε for «linear» and min(1 + C·c², 1/ε) for «B82»; ε is `79`'s clear-sky emissivity on ERA5's
    temperature and dew point, so under full cover the linear form's E is 1/ε and carries `79`'s clear-sky formula
    with it. The intermediate tier is therefore printed too — the linear form on the PRODUCT'S clear-sky emissivity,
    which takes `79`'s clear-sky formula out of the comparison and, with it, puts the product's colder air under the
    cloud (in-silico §When Modifying #33). Printed against ERA5's cover — what `79` feeds its
    forms — and against the product's own cloud amount, bin by bin: a statement about a form is a statement about the
    bins it was read in (#54), and the seasonal count is taken twice, under cover above 0.8 and at 0.5 or less;
  • the C a B82-shaped form would need to meet the product, C = (E − 1)/c², under cover above 0.8;
  • `79`'s clear-sky formula (Brutsaert 1975) against the product's clear-sky flux in three named ways: on the
    MERRA-2 temperature and dew point POWER serves beside the flux; the same with that dew/frost point read as a
    FROST point below 0 °C; and as `79` actually computes it, on ERA5's temperature and dew point. By class of hour,
    because the gap is a cold-weather one.

B — `79`'s FROST HALF UNDER THE PRODUCT'S SKY, 2001–2020, whole days, both ends of the bark bracket, both winds, both
couplings, with and without diffuse sun — `79`'s own columns, statistics and thresholds, imported, not re-typed. Five
skies on the SAME hours: `79`'s «linear» and «B82» on ERA5 cover, and the product in three NAMED readings (they
disagree, so none is picked — in-silico §When Modifying #11):
  • «emissivity» — ε = F_all / σT_p⁴ on the product's own air temperature, carried onto the model's air temperature;
  • «flux» — the product's flux as given, set against the model's air temperature;
  • «air» — the product's flux with the product's OWN air temperature driving the column (ERA5 keeps the wind and the
    diffuse sun): the one reading in which sky and air come from one source. The product's dew point enters part B
    in no reading — the sky is the product's flux.
On frost hours ERA5's air is warmer than the product's, so «flux» leaves the sky colder against the air than
«emissivity» does, and «air» moves the air itself. Which air is nearer the site is not settled here (00_07 HW.37 holds
the station comparison); the three readings are the bracket. Each sky defines its OWN frost days — the bark's daily
minimum under that sky is below 0 °C, as in `79` — so the day sets differ between all five skies.
The product's sky enters `79.simulate` UNTOUCHED: the model's sky input is (T_air, T_dew, cloud), and with cloud 0 the
«linear» kind — the carrier used here — reduces to ε(T_air, T_dew)·σT⁴ with no black-body cap (B82 would keep one). An
effective dew point — Magnus inverted through Brutsaert — therefore carries any target emissivity, above 1 included,
through `79`'s own code. `79` is not edited and its cache is not re-run.

CLOCK. POWER stamps an hourly value with the START of the hour it averages (its FAQ — quoted in the data README);
`79.simulate` applies row `hr` to the hour ENDING at it. A product hour therefore lands one row later than its stamp
(`PRODUCT_STAMP_LAG_H`). The unshifted pairing is run once more for the «flux» reading, and the largest move of a
share is cached.

CONTROLS (each can fail; what it cannot catch is said)
  1. Effective dew point: `79.sky_emissivity` of the inverted dew point returns the target, every hour. CANNOT catch a
     wrong target.
  2. Injection path = native path: `79`'s own B82 sky, fed through the effective dew point with cloud 0, must return
     `79`'s native B82 cambium series on a winter window where B82's black-sky cap never binds (asserted). B82 and not
     «linear», because «linear»'s cloudy term follows the substep air temperature and cannot be reproduced by an
     hourly emissivity — said, not hidden. CAN catch a wrong inversion, a column mix-up, a slip in the rows of the
     INJECTED sky. CANNOT catch anything about the product's clock — it never touches the product — nor an error
     shared by both paths (`79`'s own).
  3. Clock, end to end: the same B82 sky written out as a synthetic product on the product's clock and stamp
     convention, brought back through `on_model_clock` and the «flux» reading, must return `79`'s native B82 series.
     CAN catch an index slip between the product's clock and the model's rows and a reading built on the wrong
     column. CANNOT catch a wrong CONVENTION — were the stamp the end of the hour, it would pass all the same.
  4. Clock, against data: the hour-to-hour changes of the product's air temperature correlate with ERA5's best at the
     pairing used (row lag 0 of −3…+3). CAN catch a temperature pairing off by an hour or more. CANNOT separate half
     an hour, and says nothing direct about the fluxes' stamps — they ride the same response.
  5. Coverage: every hour of the simulated window is matched to exactly one product hour; the product carries no
     missing value.
Not a control: `79`'s two forms are recomputed here on 2001–2020; they are not expected to equal `79`'s thirty-year
cache and are not compared with it.

CEILINGS — see the cache's `ceilings`; the three that decide how far the result reaches: the product is computed, with
an accuracy not read here; a closed stand's sky view, wind and sun on the face are `79`'s, unchanged; the
radome↔flange coupling stays unmeasured, so the sign under the flange is still a bracket over its two ends.

Run:  python tools/in_silico/scripts/120_sky_longwave_product.py      # ≈ 30 min on two cores (five 20-year passes per bark end, the two ends in parallel)
"""

import gzip
import importlib.util
import json
import sys
from concurrent.futures import ProcessPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Which cloudy-sky long-wave form a winter sky follows: two textbook forms and a clear-sky formula set "
                  "against a satellite-derived hourly surface flux product over twenty winters, and the cambium "
                  "temperature under a titanium flange against bare bark recomputed under that product's sky in three "
                  "named readings.")

SCRIPTS = Path(__file__).resolve().parent
OUT = CACHE_DIR / "thermal" / "sky_longwave_product.json"
DATA_FILE = REPO_ROOT / "tools/in_silico/data/power_cherkasy_longwave/hourly_2001_2020.csv.gz"
FIRST_DAY, LAST_DAY = "2001-01-02", "2020-12-31"   # whole days on the ERA5 clock that the product covers end to end
PRODUCT_STAMP_LAG_H = 1        # the product's stamp is the START of its hour; `79` applies a row to the hour ENDING at it
CLOCK_LAGS = (-3, -2, -1, 0, 1, 2, 3)
COVER_BINS = ((0.0, 0.2), (0.2, 0.5), (0.5, 0.8), (0.8, 0.95), (0.95, 0.995), (0.995, 1.0))   # ERA5 cover; last bin closed
AMOUNT_BINS = ((0.0, 20.0), (20.0, 50.0), (50.0, 80.0), (80.0, 95.0), (95.0, 100.0))          # CERES cloud amount, %
NIGHT_HOURS = (18, 6)          # the local hours a night's median is taken over, 18:00–05:59
MIN_NIGHT_HOURS = 100          # a season enters a seasonal bracket with at least this many frost night hours of the class
COVERED = 0.8                  # «covered» for the seasonal bracket and the C fit — ERA5 cover, and CERES amount / 100
PARTIAL = 0.5                  # «partial cover» — ERA5 cover at or below this
COLD_CLASS_C = -10.0           # the cold class of the clear-sky comparison
SUMMER_MONTHS = (5, 6, 7, 8)
MAGNUS_ICE = (22.46, 272.62)   # Magnus over ice — the pair printed beside `79`'s water pair; NOT re-read here: a sensitivity, not an input
CONTROL_WINDOW = ("2010-01-01", "2010-02-10")      # controls 2 and 3: forty winter days
PRODUCT_REGIMES = (("product_no_sun", "linear", False), ("product_diffuse_sun", "linear", True))
READINGS = ("emissivity", "flux", "air")
SUNS = ("no_sun", "diffuse_sun")
PRODUCT_KEYS = ("all", "clear", "t", "td", "amount")


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S79 = _load("s79_frost", "79_flange_cambium_frost.py")
S78, S58, S71 = S79.S78, S79.S58, S79.S71
SIGMA = S79.SIGMA


def load_product() -> dict:
    """The product on its own UTC clock: hour stamps and the five columns; refuses a missing value."""
    with gzip.open(DATA_FILE, "rt", encoding="utf-8") as fh:
        head = fh.readline().strip().split(",")
        rows = np.loadtxt(fh, delimiter=",")
    want = ["YEAR", "MO", "DY", "HR", "ALLSKY_SFC_LW_DWN", "CLRSKY_SFC_LW_DWN", "T2M", "T2MDEW", "CLOUD_AMT"]
    if head != want:
        raise SystemExit(f"{DATA_FILE.name}: columns are {head}, not {want}")
    if np.any(rows[:, 4:] <= -999.0):
        raise SystemExit(f"{DATA_FILE.name}: a missing value (-999) — the series is not whole")
    utc = [datetime(int(y), int(m), int(d), int(h)) for y, m, d, h in rows[:, :4]]
    return {"utc": utc, "all": rows[:, 4], "clear": rows[:, 5], "t": rows[:, 6], "td": rows[:, 7], "amount": rows[:, 8]}


def on_model_clock(prod: dict, times: np.ndarray, offset_s: int, i0: int, i1: int, lag_h: int = PRODUCT_STAMP_LAG_H) -> dict:
    """The product's columns for ERA5 rows i0…i1 (control 5 — every row matched, none twice). A product hour stamped H
    (UTC, the START of the hour it averages) lands on the model row `lag_h` hours after that instant."""
    idx = {t: k for k, t in enumerate(times)}
    shift = timedelta(seconds=offset_s) + timedelta(hours=lag_h)
    pos = np.full(i1 - i0, -1)
    for k, u in enumerate(prod["utc"]):
        j = idx.get((u + shift).strftime("%Y-%m-%dT%H:%M"))
        if j is not None and i0 <= j < i1:
            if pos[j - i0] != -1:
                raise SystemExit("two product hours land on one ERA5 hour — the clock shift is wrong")
            pos[j - i0] = k
    if np.any(pos < 0):
        raise SystemExit(f"{int(np.sum(pos < 0))} ERA5 hours of the window have no product hour")
    return {k: prod[k][pos] for k in PRODUCT_KEYS}


def effective_dew_point(t_air_c: np.ndarray, eps: np.ndarray) -> np.ndarray:
    """The dew point at which `79`'s clear-sky emissivity equals `eps`: Brutsaert inverted for e (hPa), Magnus for T_d."""
    e_hpa = (t_air_c + 273.15) * (eps / S79.BRUTSAERT_A) ** (1.0 / S79.BRUTSAERT_EXP)
    ln = np.log(e_hpa / 6.112)
    return 243.12 * ln / (17.62 - ln)


def with_sky(w: dict, eps: np.ndarray) -> tuple[dict, float]:
    """`w` with the sky replaced by the emissivity `eps` (relative to `w`'s own air temperature); control 1's residual."""
    td = effective_dew_point(w["t_air"], eps)
    resid = float(np.max(np.abs(S79.sky_emissivity(w["t_air"], td) - eps)))
    if not resid < 1e-9:
        raise SystemExit(f"control 1 failed: the effective dew point misses its emissivity by {resid:.3g}")
    return {**w, "t_dew": td, "cloud": np.zeros_like(w["cloud"])}, resid


def reading_emissivities(w: dict, p: dict) -> dict:
    """Per reading: the sky as an emissivity relative to the air temperature that reading drives the column with, and
    the weather whose sky it replaces."""
    bb_model, bb_prod = SIGMA * (w["t_air"] + 273.15) ** 4, SIGMA * (p["t"] + 273.15) ** 4
    return {"emissivity": (p["all"] / bb_prod, w), "flux": (p["all"] / bb_model, w),
            "air": (p["all"] / bb_prod, {**w, "t_air": p["t"]})}


def reading_weather(w: dict, p: dict) -> tuple[dict, dict]:
    """The three readings as weather dicts for `79.simulate`, and control 1's residual of each."""
    out, resid = {}, {}
    for rd, (eps, base) in reading_emissivities(w, p).items():
        out[rd], resid[rd] = with_sky(base, eps)
    return out, resid


def control_injection(wx: dict, times: np.ndarray, offset_s: int, ar: dict, thin_mm: float) -> dict:
    """Controls 2 and 3 — `79`'s own B82 sky through the effective dew point, and the same sky sent round the product's
    clock, each against `79`'s native B82 columns."""
    i0, i1 = int(np.searchsorted(times, CONTROL_WINDOW[0] + "T00:00")), int(np.searchsorted(times, CONTROL_WINDOW[1] + "T00:00"))
    w = {k: v[i0:i1] for k, v in wx.items()}
    eps_clear = S79.sky_emissivity(w["t_air"], w["t_dew"])
    eps_b82 = (1.0 + S79.B82_C * w["cloud"] ** 2) * eps_clear
    # the cap binds when (1 + C·c²)·ε·T1⁴ ≥ T_substep⁴; the coldest substep of an hour is the colder of its two ends
    t1 = w["t_air"] + 273.15
    t_lo = np.minimum(t1, np.concatenate(([t1[0]], t1[:-1])))
    headroom = float(np.max(eps_b82 * t1 ** 4 / t_lo ** 4))
    if not headroom < 1.0:
        raise SystemExit(f"control 2: B82's black-sky cap binds in the control window (ratio {headroom:.3f}) — move the window")
    native_cols, native_labels = S79.column_table(ar, (("cloud_b82_no_sun", "b82", False), ("cloud_b82_diffuse_sun", "b82", True)))
    inj_cols, inj_labels = S79.column_table(ar, PRODUCT_REGIMES)
    if [lab[1:] for lab in native_labels] != [lab[1:] for lab in inj_labels]:
        raise SystemExit("control 2: the two column tables are not in the same order")
    stack, probe = S78.layers(thin_mm), thin_mm + S58.T_PHLOEM
    cam_n, surf_n = S79.simulate(stack, probe, w, native_cols)

    def off_native(weather: dict, what: str) -> float:
        cam_i, surf_i = S79.simulate(stack, probe, weather, inj_cols)
        gap = float(max(np.max(np.abs(cam_n - cam_i)), np.max(np.abs(surf_n - surf_i))))
        if not gap < 1e-6:
            raise SystemExit(f"{what} failed: the injected B82 sky is {gap:.3g} K off `79`'s native B82")
        return gap

    gap_injection = off_native(with_sky(w, eps_b82)[0], "control 2")
    # control 3 — a synthetic product: row k's B82 flux stamped as the product would stamp the hour ending at row k
    back = timedelta(seconds=offset_s) + timedelta(hours=PRODUCT_STAMP_LAG_H)
    synthetic = {"utc": [datetime.fromisoformat(str(t)) - back for t in times[i0:i1]],
                 "all": eps_b82 * SIGMA * t1 ** 4, "clear": eps_clear * SIGMA * t1 ** 4,
                 "t": w["t_air"], "td": w["t_dew"], "amount": 100.0 * w["cloud"]}
    order = np.random.default_rng(0).permutation(i1 - i0)          # the product's row order must not matter
    synthetic = {k: [v[j] for j in order] if k == "utc" else np.asarray(v)[order] for k, v in synthetic.items()}
    round_trip = on_model_clock(synthetic, times, offset_s, i0, i1)
    gap_clock = off_native(reading_weather(w, round_trip)[0]["flux"], "control 3")
    return {"window": list(CONTROL_WINDOW), "hours": int(i1 - i0), "columns": len(native_labels),
            "cap_headroom_ratio_max": headroom, "max_abs_difference_K": gap_injection,
            "clock_round_trip_max_abs_difference_K": gap_clock}


def control_clock(w: dict, p: dict) -> dict:
    """Control 4 — hour-to-hour changes of the product's air temperature against ERA5's at row lags; lag L compares the
    product's change at row k with ERA5's at row k + L. The pairing used must correlate best."""
    da, dp = np.diff(w["t_air"]), np.diff(p["t"])
    by_lag = {}
    for lag in CLOCK_LAGS:
        a = da[max(lag, 0): len(da) + min(lag, 0)]
        b = dp[max(-lag, 0): len(dp) + min(-lag, 0)]
        by_lag[str(lag)] = float(np.corrcoef(a, b)[0, 1])
    best = max(by_lag, key=by_lag.get)
    if best != "0":
        raise SystemExit(f"control 4 failed: the product's temperature pairs best with ERA5 at row lag {best}, not 0 — {by_lag}")
    return {"correlation_by_row_lag": by_lag, "best_row_lag": int(best), "stamp_lag_rows_applied": PRODUCT_STAMP_LAG_H}


def pct(x: np.ndarray, q: float) -> float:
    return float(np.percentile(x, q))


def frost_point_as_dew_point(td_c: np.ndarray) -> np.ndarray:
    """The dew point over water that carries the vapour pressure of `td_c` read as a FROST point below 0 °C (over ice)."""
    a_i, b_i = MAGNUS_ICE
    e_hpa = np.where(td_c < 0.0, 6.112 * np.exp(a_i * td_c / (b_i + td_c)), S79.vapour_pressure_hpa(td_c))
    ln = np.log(e_hpa / 6.112)
    return 243.12 * ln / (17.62 - ln)


def forms_against_product(w: dict, p: dict, times: np.ndarray) -> dict:
    """Part A. Frost hours of `79`'s winter months on the simulated window — raw numbers; the consumer rounds."""
    year = np.array([int(t[:4]) for t in times])
    month = np.array([int(t[5:7]) for t in times])
    hour = np.array([int(t[11:13]) for t in times])
    winter = np.isin(month, S79.WINTER_MONTHS)
    frost = winter & (w["t_air"] < S79.FROST_DAY_C)
    c, amt = w["cloud"], p["amount"] / 100.0
    eps = S79.sky_emissivity(w["t_air"], w["t_dew"])
    bb_p = SIGMA * (p["t"] + 273.15) ** 4
    eps_pc = p["clear"] / bb_p                       # the product's own clear-sky emissivity, on its own air
    e_obs = p["all"] / p["clear"]

    def forms(cv, e):
        return (cv + (1.0 - cv) * e) / e, np.minimum(1.0 + S79.B82_C * cv * cv, 1.0 / e)

    def table(cv, bins, scale, e_lin, e_b82, e_lin_pc):
        rows = []
        for lo, hi in bins:
            last = (lo, hi) == bins[-1]
            m = frost & (cv * scale >= lo) & ((cv * scale <= hi) if last else (cv * scale < hi))
            rows.append({"from": lo, "to": hi, "hours": int(m.sum()), "share_of_frost_hours": float(m.sum() / frost.sum()),
                         "product_median": float(np.median(e_obs[m])),
                         "product_p10_p90": [pct(e_obs[m], 10), pct(e_obs[m], 90)],
                         "linear_median": float(np.median(e_lin[m])), "b82_median": float(np.median(e_b82[m])),
                         "linear_on_product_clear_sky_median": float(np.median(e_lin_pc[m])),
                         "linear_on_product_clear_sky_p10_p90": [pct(e_lin_pc[m], 10), pct(e_lin_pc[m], 90)]})
        return rows

    lin_c, b82_c = forms(c, eps)
    lin_a, b82_a = forms(amt, eps)
    lin_c_pc, lin_a_pc = forms(c, eps_pc)[0], forms(amt, eps_pc)[0]
    night = (hour >= NIGHT_HOURS[0]) | (hour < NIGHT_HOURS[1])
    years = sorted(set(year.tolist()))

    def seasonal(cover_class, what: dict) -> dict:
        seasons = []
        for y in years[:-1]:   # a season runs November…March across the year's end
            s = frost & night & cover_class & (((year == y) & (month >= 11)) | ((year == y + 1) & (month <= 3)))
            if int(s.sum()) >= MIN_NIGHT_HOURS:
                seasons.append({"season": f"{y}/{str(y + 1)[2:]}", "hours": int(s.sum()),
                                "product": float(np.median(e_obs[s])), "linear": float(np.median(lin_c[s])),
                                "b82": float(np.median(b82_c[s])), "linear_on_product_clear_sky": float(np.median(lin_c_pc[s]))})

        def rng(key):
            return [min(s[key] for s in seasons), max(s[key] for s in seasons)]

        return {**what, "night_hours_local": list(NIGHT_HOURS), "min_hours": MIN_NIGHT_HOURS, "seasons": seasons,
                "product_range": rng("product"), "linear_range": rng("linear"), "b82_range": rng("b82"),
                "linear_on_product_clear_sky_range": rng("linear_on_product_clear_sky"),
                "seasons_product_closer_to_b82": sum(abs(s["product"] - s["b82"]) < abs(s["product"] - s["linear"]) for s in seasons),
                "seasons_product_closer_to_b82_than_to_linear_on_product_clear_sky":
                    sum(abs(s["product"] - s["b82"]) < abs(s["product"] - s["linear_on_product_clear_sky"]) for s in seasons),
                "seasons_total": len(seasons)}

    fit = {}
    for name, cv in (("era5_cover", c), ("ceres_amount", amt)):
        m = frost & (cv > COVERED)
        cf = (e_obs[m] - 1.0) / cv[m] ** 2
        fit[name] = {"hours": int(m.sum()), "median": float(np.median(cf)), "p10_p90": [pct(cf, 10), pct(cf, 90)]}

    # the clear-sky formula against the product's clear-sky flux — three named ways, by class of hour
    eps_p = S79.sky_emissivity(p["t"], p["td"])
    eps_p_frost_point = S79.sky_emissivity(p["t"], frost_point_as_dew_point(p["td"]))
    bb_w = SIGMA * (w["t_air"] + 273.15) ** 4
    classes = (("all_frost_hours", frost), ("era5_cover_below_0.2", frost & (c < 0.2)), ("ceres_amount_below_20pct", frost & (amt < 0.2)),
               ("frost_hours_below_cold_class", frost & (w["t_air"] < COLD_CLASS_C)), ("winter_hours_not_frost", winter & ~frost),
               ("summer_hours", np.isin(month, SUMMER_MONTHS)))
    clear = {}
    for name, m in classes:
        clear[name] = {"hours": int(m.sum()),
                       "brutsaert_minus_product_Wm2": float(np.mean(eps_p[m] * bb_p[m] - p["clear"][m])),
                       "brutsaert_with_frost_point_minus_product_Wm2": float(np.mean(eps_p_frost_point[m] * bb_p[m] - p["clear"][m])),
                       "brutsaert_on_era5_minus_product_Wm2": float(np.mean(eps[m] * bb_w[m] - p["clear"][m])),
                       "emissivity_product_median": float(np.median(eps_pc[m])),
                       "emissivity_brutsaert_median": float(np.median(eps_p[m]))}
    dt = w["t_air"][frost] - p["t"][frost]
    return {
        "frost_hours": int(frost.sum()), "months": list(S79.WINTER_MONTHS), "frost_below_C": S79.FROST_DAY_C,
        "enhancement_by_era5_cover": table(c, COVER_BINS, 1.0, lin_c, b82_c, lin_c_pc),
        "enhancement_by_ceres_amount_pct": table(amt, AMOUNT_BINS, 100.0, lin_a, b82_a, lin_a_pc),
        "era5_cover_median_within_ceres_amount_bins": [
            {"from": lo, "to": hi, "era5_cover_median": float(np.median(c[frost & (amt * 100 >= lo) & (amt * 100 < hi + (hi == 100.0))]))}
            for lo, hi in AMOUNT_BINS],
        "seasonal_night_medians_covered": seasonal(c > COVERED, {"covered_above": COVERED}),
        "seasonal_night_medians_partial_cover": seasonal(c <= PARTIAL, {"cover_at_most": PARTIAL,
                                                                        "share_of_frost_hours": float((frost & (c <= PARTIAL)).sum() / frost.sum())}),
        "b82_constant_the_product_asks": {"model_C": S79.B82_C, "covered_above": COVERED, **fit},
        "clear_sky_formula_against_product": {"cold_class_below_C": COLD_CLASS_C, "summer_months": list(SUMMER_MONTHS),
                                              "magnus_over_ice": list(MAGNUS_ICE), "by_class": clear},
        "era5_minus_product_air_temperature_K": {"mean": float(dt.mean()), "rmse": float(np.sqrt((dt ** 2).mean()))},
    }


def frost_half(cam: np.ndarray, labels: list, times: np.ndarray, side: str, bark_mm: float) -> list:
    """`79`'s cloud-regime statistics, row by row (regime × wind × coupling) for one bark end — shares raw, with the
    day counts they are made of; `shift_K` is `79.shift_stats`, rounded as `79` rounds it."""
    m = S79.daily_minima(cam, times)
    month = np.array([int(times[(S79.SPIN_UP_DAYS + d) * 24][5:7]) for d in range(m.shape[0])])
    rows = []
    for name in dict.fromkeys(lab[0] for lab in labels):
        for k in S79.WIND_K:
            jb = labels.index((name, "bark", k))
            frost, cold = m[:, jb] < S79.FROST_DAY_C, m[:, jb] < S79.COLD_DAY_C
            for cp in S79.COUPLINGS:
                s = m[:, jb] - m[:, labels.index((name, cp, k))]
                colder, warmer = s > S79.COLDER_BAND_K, s < -S79.COLDER_BAND_K
                rows.append({"regime": name, "coupling": cp, "wind_k": k, "bark_side": side, "bark_mm": bark_mm,
                             "shift_K": S79.shift_stats(m, jb, labels.index((name, cp, k))),
                             "frost_days": int(np.count_nonzero(frost)),
                             "colder_days": int(np.count_nonzero(colder & frost)),
                             "warmer_days": int(np.count_nonzero(warmer & frost)),
                             "colder_share": float(np.mean(colder[frost])), "warmer_share": float(np.mean(warmer[frost])),
                             "cold_days": {"days": int(np.count_nonzero(cold)),
                                           "colder_share": float(np.mean(colder[cold])) if np.any(cold) else None},
                             "by_month": {str(mo): {"frost_days": int(np.count_nonzero(frost & (month == mo))),
                                                    "colder_share": float(np.mean(colder[frost & (month == mo)]))}
                                          for mo in range(1, 13) if np.any(frost & (month == mo))}})   # every month with a frost day, as `79`
    return rows


def summarise(rows: list) -> dict:
    """Per regime and coupling: the range over wind and bark end — the form `79` quotes."""
    out = {}
    for name in dict.fromkeys(r["regime"] for r in rows):
        out[name] = {}
        for cp in S79.COUPLINGS:
            rr = [r for r in rows if r["regime"] == name and r["coupling"] == cp]
            cd = [r["cold_days"] for r in rr if r["cold_days"]["days"]]
            months = sorted({int(mo) for r in rr for mo in r["by_month"]})
            out[name][cp] = {
                "frost_days_range": [min(r["frost_days"] for r in rr), max(r["frost_days"] for r in rr)],
                "median_K_range": [min(r["shift_K"]["median"] for r in rr), max(r["shift_K"]["median"] for r in rr)],
                "max_K": max(r["shift_K"]["max"] for r in rr),
                "colder_share_range": [min(r["colder_share"] for r in rr), max(r["colder_share"] for r in rr)],
                "warmer_share_range": [min(r["warmer_share"] for r in rr), max(r["warmer_share"] for r in rr)],
                "cold_days_colder_share_range": [min(c["colder_share"] for c in cd), max(c["colder_share"] for c in cd)] if cd else None,
                "by_month_colder_share_range": {
                    str(mo): [min(r["by_month"][str(mo)]["colder_share"] for r in rr if str(mo) in r["by_month"]),
                              max(r["by_month"][str(mo)]["colder_share"] for r in rr if str(mo) in r["by_month"])]
                    for mo in months}}
    return out


def bracket_facts(rows: list) -> dict:
    """What the table does and does not say about the sign — every clause of the verdict is built from this, and the
    doc↔cache test rebuilds it from `runs`. A cell is (sun, coupling, wind, bark end)."""
    cell = {(r["regime"], r["coupling"], r["wind_k"], r["bark_side"]): r for r in rows}
    keys = sorted({(r["wind_k"], r["bark_side"]) for r in rows})

    def shares(regime, cp):
        return [cell[(regime, cp, k, side)]["colder_share"] for k, side in keys]

    def medians(regime, cp):
        return [cell[(regime, cp, k, side)]["shift_K"]["median"] for k, side in keys]

    between = pairs = opposite_tied = 0
    margin = None
    spread_between_readings, spread_inside_reading, disjoint = [], [], []
    for sun in SUNS:
        for cp in S79.COUPLINGS:
            lin, b82 = shares(f"cloud_linear_{sun}", cp), shares(f"cloud_b82_{sun}", cp)
            if max(b82) < min(lin) or max(lin) < min(b82):
                disjoint.append({"sun": sun, "coupling": cp, "linear": [min(lin), max(lin)], "b82": [min(b82), max(b82)]})
            if cp == "tied":
                opposite_tied += sum(a * b < 0 for a, b in zip(medians(f"cloud_linear_{sun}", cp), medians(f"cloud_b82_{sun}", cp), strict=True))
            by_reading = [shares(f"product_{sun}_{rd}", cp) for rd in READINGS]
            for prod in by_reading:
                for x, f1, f2 in zip(prod, lin, b82, strict=True):
                    lo, hi = min(f1, f2), max(f1, f2)
                    pairs += 1
                    between += int(lo <= x <= hi)
                    gap = min(x - lo, hi - x)
                    margin = gap if margin is None else min(margin, gap)
                spread_inside_reading.append(max(prod) - min(prod))
            spread_between_readings.append(max(max(col) - min(col) for col in zip(*by_reading, strict=True)))

    def median_range(cp, regimes):
        vals = [v for regime in regimes for v in medians(regime, cp)]
        return [min(vals), max(vals)]

    product = [f"product_{sun}_{rd}" for sun in SUNS for rd in READINGS]
    return {
        "cells_per_sky_and_coupling": len(keys),
        "reading_cells_between_the_two_forms": int(between), "reading_cells_total": int(pairs),
        "smallest_margin_inside_the_forms": float(margin),
        "largest_spread_between_readings_in_one_cell": float(max(spread_between_readings)),
        "smallest_spread_inside_one_reading": float(min(spread_inside_reading)),
        "forms_ranges_that_do_not_overlap": disjoint, "sun_and_coupling_blocks": len(SUNS) * len(S79.COUPLINGS),
        "tied_cells_where_the_forms_medians_have_opposite_signs": int(opposite_tied), "tied_cells_total": len(keys) * len(SUNS),
        "product_median_K_range": {cp: median_range(cp, product) for cp in S79.COUPLINGS},
        "linear_diffuse_sun_decoupled_median_K_range": median_range("decoupled", ["cloud_linear_diffuse_sun"]),
        "frost_days_range_by_sky": {regime: [min(r["frost_days"] for r in rows if r["regime"] == regime),
                                             max(r["frost_days"] for r in rows if r["regime"] == regime)]
                                    for regime in dict.fromkeys(r["regime"] for r in rows)},
    }


def _inputs():
    """Everything the run needs, loaded identically in the parent and in each worker."""
    ar = S79.areas()
    wx = S79.load_weather()
    times = np.asarray(wx["time"]).astype(str)
    offset_s = int(S79._header_dict(S71.DATA_FILE)["utc_offset_seconds"])
    i0, i1 = int(np.searchsorted(times, FIRST_DAY + "T00:00")), int(np.searchsorted(times, LAST_DAY + "T23:00")) + 1
    if times[i0] != FIRST_DAY + "T00:00" or times[i1 - 1] != LAST_DAY + "T23:00" or (i1 - i0) % 24:
        raise SystemExit("the simulated window is not whole days on the ERA5 clock")
    w = {k: v[i0:i1] for k, v in wx.items()}
    prod = load_product()
    p = on_model_clock(prod, times, offset_s, i0, i1)
    p_unshifted = on_model_clock(prod, times, offset_s, i0, i1, lag_h=0)
    return ar, wx, times, offset_s, i0, i1, w, p, p_unshifted


def _bark_end(side: str) -> dict:
    ar, _, _, _, _, _, w, p, p_unshifted = _inputs()
    t_w = np.asarray(w["time"]).astype(str)
    b = S78.bark_bracket()[f"{side}_mm"]
    stack, probe = S78.layers(b), b + S58.T_PHLOEM
    native_cols, native_labels = S79.column_table(ar, S79.CLOUD_REGIMES)
    prod_cols, prod_labels = S79.column_table(ar, PRODUCT_REGIMES)
    cam, _ = S79.simulate(stack, probe, w, native_cols)
    rows = frost_half(cam, native_labels, t_w, side, b)
    wxs, resid = reading_weather(w, p)
    for rd in READINGS:
        cam, _ = S79.simulate(stack, probe, wxs[rd], prod_cols)
        rows += frost_half(cam, [(f"{name}_{rd}", cp, k) for name, cp, k in prod_labels], t_w, side, b)
    cam, _ = S79.simulate(stack, probe, reading_weather(w, p_unshifted)[0]["flux"], prod_cols)
    unshifted = frost_half(cam, [(f"{name}_flux", cp, k) for name, cp, k in prod_labels], t_w, side, b)
    return {"side": side, "bark_mm": b, "rows": rows, "unshifted_flux_rows": unshifted, "resid": resid}


def pc(lo_hi) -> str:
    return f"{lo_hi[0]:.0%}–{lo_hi[1]:.0%}"


def main() -> int:
    banner("HW.6 — the cloudy winter sky: 79's two long-wave forms against a satellite product, and the frost half under it")
    units = S79.brutsaert_unit_check()
    ar, wx, times, offset_s, i0, i1, w, p, _ = _inputs()
    t_w = times[i0:i1]
    print(f"  window {FIRST_DAY} … {LAST_DAY}: {i1 - i0} hours, every one matched to a product hour "
          f"(clock shift {offset_s} s + {PRODUCT_STAMP_LAG_H} h for the stamp)")

    bark = S78.bark_bracket()
    ctrl = control_injection(wx, times, offset_s, ar, bark["thin_mm"])
    print(f"  controls 2–3: injected B82 sky vs 79's native B82, {ctrl['hours']} h × {ctrl['columns']} columns — "
          f"max |Δ| {ctrl['max_abs_difference_K']:.2e} K direct, {ctrl['clock_round_trip_max_abs_difference_K']:.2e} K "
          f"round the product's clock (cap headroom {ctrl['cap_headroom_ratio_max']:.4f})")
    clock = control_clock(w, p)
    print("  control 4: product ΔT vs ERA5 ΔT by row lag — " + " · ".join(f"{lag}: {r:.3f}" for lag, r in clock["correlation_by_row_lag"].items()))

    a = forms_against_product(w, p, t_w)
    full, partial = a["enhancement_by_era5_cover"][-1], a["enhancement_by_era5_cover"][1]
    sn, sp = a["seasonal_night_medians_covered"], a["seasonal_night_medians_partial_cover"]
    cl = a["clear_sky_formula_against_product"]["by_class"]["all_frost_hours"]
    print(f"  A · frost hours {a['frost_hours']}; under full ERA5 cover ({full['hours']} h) E: product {full['product_median']:.3f} "
          f"[{full['product_p10_p90'][0]:.3f}…{full['product_p10_p90'][1]:.3f}] · linear {full['linear_median']:.3f} "
          f"(on the product's clear sky {full['linear_on_product_clear_sky_median']:.3f}) · B82 {full['b82_median']:.3f}")
    print(f"      seasonal night medians: cover > {COVERED} — closer to B82 in {sn['seasons_product_closer_to_b82']} of {sn['seasons_total']}; "
          f"cover ≤ {PARTIAL} — in {sp['seasons_product_closer_to_b82']} of {sp['seasons_total']}")
    print(f"      clear sky, Brutsaert − product on frost hours: {cl['brutsaert_minus_product_Wm2']:+.1f} W/m² on the product's T, Td · "
          f"{cl['brutsaert_with_frost_point_minus_product_Wm2']:+.1f} with a frost point · {cl['brutsaert_on_era5_minus_product_Wm2']:+.1f} as 79 computes it")

    month = np.array([int(t[5:7]) for t in t_w])
    frost_h = np.isin(month, S79.WINTER_MONTHS) & (w["t_air"] < S79.FROST_DAY_C)
    above_black = {rd: {"share_of_all_hours": float(np.mean(eps > 1.0)), "share_of_frost_hours": float(np.mean(eps[frost_h] > 1.0)),
                        "largest_emissivity_on_frost_hours": float(np.max(eps[frost_h]))}
                   for rd, (eps, _) in reading_emissivities(w, p).items()}

    # part B — one bark end per process; each worker reloads the same files and returns its rows and control residuals
    with ProcessPoolExecutor(max_workers=2) as pool:
        done = list(pool.map(_bark_end, ("thin", "thick")))
    rows = [r for part in done for r in part["rows"]]
    unshifted = [r for part in done for r in part["unshifted_flux_rows"]]
    resid = done[0]["resid"]
    for part in done:
        if part["resid"] != resid:
            raise SystemExit("the two bark ends did not see the same sky — the workers loaded different inputs")
        print(f"  B · {part['side']:<5s} bark {part['bark_mm']:5.2f} mm done (five skies and the unshifted flux reading)", flush=True)
    summ = summarise(rows)
    facts = bracket_facts(rows)
    shifted = {(r["regime"], r["coupling"], r["wind_k"], r["bark_side"]): r["colder_share"] for r in rows}
    clock_move = max(abs(r["colder_share"] - shifted[(r["regime"], r["coupling"], r["wind_k"], r["bark_side"])]) for r in unshifted)
    print("  B · share of frost days colder under the flange (range over wind and bark end) — tied | decoupled:")
    for name, r in summ.items():
        print(f"      {name:<32s} {pc(r['tied']['colder_share_range'])} | {pc(r['decoupled']['colder_share_range'])}"
              f"   median shift tied {r['tied']['median_K_range'][0]:+.2f}…{r['tied']['median_K_range'][1]:+.2f} K")

    def share(name, cp="tied"):
        return pc(summ[name][cp]["colder_share_range"])

    def side_of(x: float) -> str:
        return "below" if x < 0 else "above"

    pm = facts["product_median_K_range"]
    text = (
        f"On {a['frost_hours']} frost hours of November–March 2001–2020 the product's cloud enhancement (all-sky over clear-sky "
        f"flux) under full ERA5 cover has median {full['product_median']:.3f} (10th–90th percentile "
        f"{full['product_p10_p90'][0]:.3f}–{full['product_p10_p90'][1]:.3f}); 79's B82 form gives {full['b82_median']:.3f}, its linear "
        f"form {full['linear_median']:.3f}, and the linear form on the product's own clear-sky emissivity "
        f"{full['linear_on_product_clear_sky_median']:.3f}. Under cover above {COVERED} the product's seasonal night medians sit closer to "
        f"B82 in {sn['seasons_product_closer_to_b82']} of {sn['seasons_total']} seasons; under cover of {PARTIAL} or less — "
        f"{sp['share_of_frost_hours']:.0%} of frost hours — in {sp['seasons_product_closer_to_b82']} of {sp['seasons_total']}; in the "
        f"{partial['from']}–{partial['to']} bin the medians are {partial['product_median']:.3f} for the product, "
        f"{partial['linear_median']:.3f} for the linear form and {partial['b82_median']:.3f} for B82. On the MERRA-2 temperature and "
        f"dew point served beside it, 79's clear-sky formula is {abs(cl['brutsaert_minus_product_Wm2']):.1f} W/m² "
        f"{side_of(cl['brutsaert_minus_product_Wm2'])} the product's clear-sky flux on frost hours, and "
        f"{abs(cl['brutsaert_on_era5_minus_product_Wm2']):.1f} W/m² {side_of(cl['brutsaert_on_era5_minus_product_Wm2'])} it as 79 "
        f"computes it, on ERA5. 79's frost half on the same years, tied end, share of frost days colder under the flange "
        f"without sun: linear {share('cloud_linear_no_sun')}, B82 {share('cloud_b82_no_sun')}, the product "
        f"{share('product_no_sun_emissivity')} (emissivity reading), {share('product_no_sun_flux')} (flux reading) and "
        f"{share('product_no_sun_air')} (air reading); with diffuse sun: linear {share('cloud_linear_diffuse_sun')}, B82 "
        f"{share('cloud_b82_diffuse_sun')}, the product {share('product_diffuse_sun_emissivity')}, {share('product_diffuse_sun_flux')} "
        f"and {share('product_diffuse_sun_air')}. In {facts['reading_cells_between_the_two_forms']} of {facts['reading_cells_total']} "
        f"cell-and-reading pairs the product's share lies between the two forms' (smallest margin "
        f"{facts['smallest_margin_inside_the_forms']:+.3f}); the two forms' own ranges do not overlap in "
        f"{len(facts['forms_ranges_that_do_not_overlap'])} of {facts['sun_and_coupling_blocks']} sun-and-coupling blocks, and their "
        f"medians have opposite signs in {facts['tied_cells_where_the_forms_medians_have_opposite_signs']} of "
        f"{facts['tied_cells_total']} tied cells. Under the product's sky the median shift runs "
        f"{pm['decoupled'][0]:+.2f}…{pm['decoupled'][1]:+.2f} K at the decoupled end and {pm['tied'][0]:+.2f}…{pm['tied'][1]:+.2f} K "
        f"at the tied end.")
    print("  " + text)
    print(f"      unshifted product clock, flux reading: a share moves by at most {clock_move:.3f}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "script": "120_sky_longwave_product.py",
        "question": "which cloudy-sky long-wave form the winter sky follows, and 79's frost half under the read sky",
        "data": {"product_file": str(DATA_FILE.relative_to(REPO_ROOT)),
                 "product_sources": "CERES SYN1deg (fluxes, cloud amount) · MERRA-2 (temperature, dew/frost point) via NASA POWER — as the response's header names them",
                 "weather": "79.load_weather() — ERA5 at the same point", "window_days": [FIRST_DAY, LAST_DAY], "hours": int(i1 - i0),
                 "clock_shift_s": offset_s, "product_stamp_lag_h": PRODUCT_STAMP_LAG_H},
        "model": {"sky_view": S79.SKY_VIEW, "epsilon": S79.EPSILON, "b82_C": S79.B82_C, "brutsaert": units,
                  "frost_day_C": S79.FROST_DAY_C, "cold_day_C": S79.COLD_DAY_C, "colder_band_K": S79.COLDER_BAND_K,
                  "spin_up_days": S79.SPIN_UP_DAYS, "wind_k": list(S79.WIND_K), "bark_mm": {"thin": bark["thin_mm"], "thick": bark["thick_mm"]},
                  "readings": {"emissivity": "ε = F_all/σT_p⁴ on the product's own air temperature, carried onto the model's",
                               "flux": "the product's flux as given, against the model's air temperature",
                               "air": "the product's flux with the product's own air temperature driving the column; wind and "
                                      "diffuse sun stay ERA5's"}},
        "controls": {"effective_dew_point_max_residual": resid, "injection_equals_native_b82": ctrl, "clock_against_era5": clock,
                     "product_hours_matched": int(i1 - i0), "sky_above_black_body": above_black,
                     "unshifted_clock_flux_reading_largest_share_move": float(clock_move)},
        "forms_vs_product": a,
        "frost_half_2001_2020": {"by_regime": summ, "bracket": facts, "runs": rows, "unshifted_flux_runs": unshifted},
        "verdict": {"text": text},
        "ceilings": [
            "how the product is computed, on what cell and how well at an hourly step is not read from its primary here — it is not a "
            "measurement at the site",
            "the product's hourly mean temperature is paired as the temperature at the END of its hour — up to half an hour, declared; "
            "the fluxes' stamp convention is POWER's documentation's, and the data check (control 4) is on temperature only",
            "ERA5's and the product's air temperatures disagree on frost hours, so the product's sky is carried in three named readings and "
            "none is picked",
            "each sky defines its own frost days, so the five skies' shares are taken over different day sets (their counts are cached)",
            "in the diffuse-sun columns of the product's readings the long wave is the product's cloud and the short wave is ERA5's — "
            "the two disagree hour by hour",
            "the product's sky is above a black body at the air temperature on a share of frost hours (cached); 79's own forms never are, "
            "and no cap is applied here",
            "ERA5 cover and the product's cloud amount disagree hour by hour; 79 feeds its forms ERA5 cover, and the comparison is printed under both",
            "the comparison runs on 2001–2020, not on the thirty years 79 caches — 79's two forms are recomputed here on the same years; "
            "79's beam and ground-reflected light are not re-run under the product's sky",
            "sky view, wind at the trunk, sun on the face, 1D and zero contact resistance are 79's, unchanged; a closed stand's canopy is not a "
            "half sky at air temperature by measurement",
            "the radome↔flange coupling is not measured — decoupled and tied remain its two ends, so the sign under the flange stays a bracket",
            "no injury verdict — no frost-hardiness threshold for pine cambium in the tree"],
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"  cache → {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
