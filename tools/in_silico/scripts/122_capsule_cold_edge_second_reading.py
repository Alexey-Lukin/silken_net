#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
122 — The capsule's cold edge on the COLDER named reading of the air (00_07 HW.37). `81` ran the isolated capsule on
ERA5 air only. `121` then read Cherkasy's cold edge from two reanalyses and found ERA5 the warmer of the two. This
script runs `81`'s DEEP edge — the isolated lump under a clear sky, with no sun, in still air — on MERRA-2's hourly
air, and asks whether the capsule requirement (−40 °C) stays uncrossed, and on WHAT a crossing stands.

WHAT IS REUSED, NOT COPIED. The lump is `81`'s: `solve`, `t_env4`, `longest_spell`, the geometry, ε, the sky view and
Brutsaert's clear sky are imported from it, and so are its floor (the EDLC operating minimum) and the capsule
requirement. Nothing of `81`, `79`, `71`, `120` or `121` is changed; this script writes its own cache.

INPUT. MERRA-2 2 m air temperature and its «dew/frost point», and CERES SYN1deg's downward long-wave flux at the
surface, clear-sky and all-sky, as NASA POWER serves them — hourly means on the UTC clock, all four from one file and
one row (tools/in_silico/data/power_cherkasy_longwave/hourly_2001_2020.csv.gz — the file `120` and `121` read; the
stamp is the START of the averaged hour). Both air readings are taken on `121`'s hours window, read from its cache. The ERA5
series is `79`'s join (air and dew point on the file's own clock), moved to UTC by subtracting the offset its header
declares — the direction `121`'s control 6 holds, and control 3 here holds the result to `121`'s series hour for hour.

THE SKY IS A SECOND AXIS, NOT A GIVEN. `81`'s clear sky is Brutsaert's one-line formula from the dew point. On frost
hours `120` found that formula below the product's clear-sky flux; near −35 °C it is an extrapolation (vapour pressure
of a few tenths of a hectopascal). So the MERRA-2 air is run under three skies: the formula (`81`'s deep edge), the
product's clear-sky flux, and the product's all-sky flux — the last two read from the same row as the air.
  • «The product» is CERES SYN1deg, not MERRA-2: by its data-quality summary its clear-sky flux is the all-sky
    radiative-transfer computation with the clouds removed, on another analysis's six-hourly profiles. So it is not a
    measurement, and not computed on the air it shares a row with; the «emissivity» printed for it is that flux over
    the black-body flux of MERRA-2's 2 m air — a ratio of two sources (under the all-sky flux it exceeds 1 on some
    hours). It is a second READING of the sky, not a judge of the formula.
  • The «dew/frost point» is read as a dew point over water, as `81` reads ERA5's; the file's header does not say
    which of the two it is below 0 °C. The same run with it read as a frost point over ice (`120`'s conversion) and
    with it capped at the air are reported beside.
  • No wind rides in the hourly file: inside the hourly record only the calm run is computed.

THE DAYS BEFORE THE HOURLY RECORD. POWER serves no hourly series before 2001, and MERRA-2's lowest daily minimum of
the 29 seasons `121` reads lies before it. For every day the daily file carries before the hourly record the lump is
solved at the day's minimum — the coldest hourly mean of that UTC day by the product's definition, which `121`'s
control 5 holds on 2001–2020 only — under the formula sky, over a sweep of dew-point depressions (OURS; that it spans
what MERRA-2 itself carries on its coldest hours of the window is asserted by the page's builder). For the days the lump falls below the
requirement the script then reports what the same files say against the three things the lump took as given: the sky
emissivity at which the lump sits ON the requirement, beside the formula's and the product's; the daily-mean 10 m wind
the daily file carries, and the lump with `71`'s shares k of it (k is ours, unmeasured); and the station's own row for
the day, where it has one.

THE LUMP'S OWN SPREAD. `71` prices its still-air kernel at ×0.7 off its home geometry (its H_C_SENSITIVITY — ours, not
a measured band) and prints the hot bound with it. The same factor is run here on the cold edge, where a weaker
kernel makes the capsule COLDER, so every margin of the page is printed beside its ×0.7 reading.

DIRECTION. For a GIVEN air and a GIVEN clear-sky form, four choices put the capsule's TEMPERATURE below a real one:
isolated from the bark, clear every hour, no sun, still air; with no heat capacity the minimum cannot be deeper than
here either (`81`). The HOUR COUNTS are an upper count in the first four only: a heat capacity can stretch a spell as
well as shave it (`81`). The sky view and the capsule's emissivity are `71`'s assumptions, not bounds, and the half of
the view that is not sky is taken at the air's temperature. The AIR is not
a bound in either reading (`121`). So a crossing here is a crossing of the model's lower bound on one named reading
of the air and one named form of the sky — not a forecast for the plot.

CONTROLS that can fail (raise, never warn):
  1. `81`'s own record through THIS script's call path reproduces `81`'s cached deep edge — coldest hour and its
     stamp, hours and days below the floor, the longest spell, hours below the requirement — and `81`'s deep edge IS
     the regime and wind this script hard-codes. CAN catch: a regime, a wind, a dew point off by a tenth of a kelvin
     or a geometry off by a percent reaching `solve` here. CANNOT: an error inside `81`'s lump; a geometry off by a
     tenth of a percent (`81` rounds its statistics to 0.01 K).
  2. The MERRA-2 window is one unbroken hourly clock with no missing value in any of the four columns. CAN catch: a
     gap that would join a «spell» across it, the fill value read as a number. CANNOT: a wrong value.
  3. The ERA5 window is `121`'s UTC series hour for hour, and the air's hours below each of `121`'s thresholds equal
     `121`'s cached counts in both readings. CAN catch: another file or column; the ERA5 offset applied with the
     wrong sign, not at all, or by another number of hours (the hour-for-hour half — tried 0, −3, +2, +4 h). The
     COUNTS alone cannot: the hours the window gains or loses at its ends are all above −10 °C. CANNOT: both readers
     wrong the same way.
  4. The day outside the hourly record is `121`'s: MERRA-2's lowest daily minimum and its day are read from `121`'s
     cache, the day must be single, must precede the hourly file's first day, and the daily file must carry that
     value on that day. CAN catch: a re-run of `121` moving the floor into the hourly window, where the sweep would
     be the wrong tool; the cache and the daily file drifting apart. CANNOT: the daily value being wrong.
  5. MERRA-2's dew column against ERA5's dew point on the same UTC hours: the mean difference inside a bound and the
     two correlated. CAN catch: another column in its place (cloud amount, a flux, the air column — tried), kelvin
     for Celsius, a shift beyond the bound. CANNOT: a bias inside the bound (a few kelvin of dew point move the
     coldest hour by tenths of a kelvin); which of dew or frost point it is.
  6. The product's clear-sky flux is not above its all-sky flux by more than rounding on any hour, is below it on
     some, and both give a ratio to the air's black-body flux inside (0, 1.2). CAN catch: the two flux columns
     swapped, one column read into both places, a column that is not a flux (cloud amount, the air). CANNOT: a shift
     of an hour or two between flux and air; that the flux belongs to MERRA-2's air — it is CERES's; an error in
     the product.
  7. The ×0.7 kernel run: with `71`'s kernels scaled the deep edge must come out colder, and after the run the
     unscaled deep edge must be reproduced field for field. CAN catch: the scaling not reaching `81`'s lump (the run
     would then repeat the unscaled one), the kernels left scaled for what is computed after. CANNOT: whether ×0.7
     is the right size of the spread.

CAN show: on MERRA-2 air under three skies and on ERA5 air under the formula sky — the coldest capsule hour and the
air at it, hours and days below the EDLC floor, the longest spell, hours below the capsule requirement; the capsule at
every daily minimum before the hourly record for a sweep of dew-point depressions; on the days that fall below the
requirement — the sky emissivity the crossing needs against the formula's and the product's, the wind the daily file
carries, the station's row.
CANNOT show: which air reading is right for the plot (the capsule logger's first winter is the judge — HW.37); the
product's sky before 2001; the wind at MERRA-2's coldest hour (the daily file carries a mean; ERA5's hourly wind for
those days is in the tree and not read here); the share k of the wind that reaches the trunk; sunlit runs on MERRA-2; the
temperature inside the capsule; the EDLC's or the seal's behaviour at these temperatures.

Run:  python tools/in_silico/scripts/122_capsule_cold_edge_second_reading.py      # under a minute
"""
from __future__ import annotations

import contextlib
import csv
import gzip
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, EDLC_OPERATING_MIN_C, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Cold edge of the sensor capsule (isolated lump, no sun, still air) on a second reanalysis reading "
                  "of the air under three readings of the sky, hourly over twenty years, and at every daily "
                  "minimum of the ten years before them, against the capsule's temperature requirement.")

SCRIPTS = Path(__file__).resolve().parent
THERMAL = CACHE_DIR / "thermal"
OUT = THERMAL / "capsule_cold_edge_second_reading.json"
DEEP = ("clear_no_sun", "k=0.0")                 # `81`'s deep edge — control 1 holds this script to it
DEW_SWEEP_K = (-2.0, 0.0, 1.0, 2.0, 3.0, 5.0)    # OURS: air minus dew point tried where no hourly record exists
COLDEST_HOURS = 200                              # OURS: the hours MERRA-2's own sky and air-minus-dew are reported on
COLD_AIR_C = -20.0                               # OURS: «cold hours» for the reported capsule-minus-air
DEW_UNITS_BOUND_K, DEW_MIN_CORRELATION = 3.0, 0.95     # OURS — control 5; the bound is the size of `121`'s units bound
FLUX_ROUNDING_WM2 = 0.011                        # the fluxes come with two decimals — control 6
BISECT_ITER = 80
KNOT_M_S = 0.514444


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S81 = _load("s81_cold_edge", "81_capsule_cold_edge_sky.py")
S120 = _load("s120_sky_product", "120_sky_longwave_product.py")
S121 = _load("s121_cold_edge", "121_cold_edge_station.py")
REQUIREMENT_C = S81.CAPSULE_REQUIREMENT_MIN_C
SIGMA, SKY_VIEW, WIND_K = S81.SIGMA, S81.SKY_VIEW, S81.S71.WIND_K
KERNEL_SCALE = S81.S71.H_C_SENSITIVITY           # `71`'s own reading of its still-air kernel off its home geometry
HOURS_PER_YEAR = 8766.0                          # `81`'s


@contextlib.contextmanager
def kernel_scaled(scale: float):
    """`71`'s sensitivity reading applied to `81`'s lump: `81`'s residual calls `71`'s two convection kernels by
    attribute at call time, so they are scaled on the module and restored — control 7 holds both halves."""
    natural, forced = S81.S71.h_natural, S81.S71.h_forced
    S81.S71.h_natural = lambda *a, **k: scale * natural(*a, **k)
    S81.S71.h_forced = lambda *a, **k: scale * forced(*a, **k)
    try:
        yield
    finally:
        S81.S71.h_natural, S81.S71.h_forced = natural, forced


def kelvin4(t_c):
    return (t_c + 273.15) ** 4


def env4_emissivity(t_air, eps_sky):
    """`81`'s environment term for a sky of effective emissivity `eps_sky` (its `t_env4` with ε given, not computed)."""
    return SKY_VIEW * eps_sky * kelvin4(t_air) + (1.0 - SKY_VIEW) * kelvin4(t_air)


def env4_flux(t_air, lw_down):
    """The same term with the sky's flux read from the product: σ·T_sky⁴ = LW↓."""
    return SKY_VIEW * lw_down / SIGMA + (1.0 - SKY_VIEW) * kelvin4(t_air)


def lump(t_air, env4, d_m: float, u=None):
    """`81`'s lump with no sun: still air unless a wind at the capsule is given."""
    zero = np.zeros_like(t_air)
    return S81.solve(t_air, zero, env4, d_m, zero if u is None else u)


def deep_edge(t_air, t_dew, d_m: float):
    """`81`'s deep edge for an air series: Brutsaert's clear sky, no sun, still air."""
    return lump(t_air, S81.t_env4(False, t_air, t_dew), d_m)


def summary(t, time, t_air) -> dict:
    """Raw numbers of one temperature series — nothing rounded (the docs round, the cache does not)."""
    below = t < EDLC_OPERATING_MIN_C
    i = int(np.argmin(t))
    return {"coldest_C": float(t[i]), "at": str(time[i]), "air_at_coldest_C": float(t_air[i]),
            "minus_air_at_coldest_K": float(t[i] - t_air[i]),
            "hours_below_floor": int(below.sum()), "days_below_floor": len({str(s)[:10] for s in time[below]}),
            "longest_spell_below_floor_h": int(S81.longest_spell(below)),
            "hours_below_requirement": int((t < REQUIREMENT_C).sum())}


def spread(x) -> dict:
    return {"lowest": float(np.min(x)), "median": float(np.median(x)), "highest": float(np.max(x))}


def load_merra2(window: tuple) -> dict:
    """MERRA-2 hourly air, dew point and the two long-wave fluxes on `window` (whole UTC days, both ends in).
    Controls 2 and 6 are here."""
    cols = {"t_air": "T2M", "t_dew": "T2MDEW", "lw_clear": "CLRSKY_SFC_LW_DWN", "lw_all": "ALLSKY_SFC_LW_DWN"}
    out = {k: [] for k in cols}
    time, first_day = [], None
    with gzip.open(S121.MERRA2_HOURLY, "rt", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            day = f"{int(r['YEAR']):04d}-{int(r['MO']):02d}-{int(r['DY']):02d}"
            first_day = first_day or day
            if not window[0] <= day <= window[1]:
                continue
            for k, col in cols.items():
                v = float(r[col])
                if v <= -999:
                    raise AssertionError(f"control 2: MERRA-2 hourly carries its missing value in {col} on {day}")
                out[k].append(v)
            time.append(f"{day}T{int(r['HR']):02d}")
    time = np.array(time)
    step = np.diff(time.astype("datetime64[h]")).astype(int)
    if not np.all(step == 1):
        raise AssertionError(f"control 2: the MERRA-2 hourly clock breaks at {int(np.sum(step != 1))} places")
    out = {k: np.array(v) for k, v in out.items()}
    eps_clear, eps_all = (out[k] / (SIGMA * kelvin4(out["t_air"])) for k in ("lw_clear", "lw_all"))
    if np.any(out["lw_clear"] > out["lw_all"] + FLUX_ROUNDING_WM2) or not all(e.min() > 0.0 and e.max() < 1.2 for e in (eps_clear, eps_all)):
        raise AssertionError("control 6: the product's clear-sky flux exceeds its all-sky flux, or a flux column is not a flux")
    if not np.any(out["lw_all"] > out["lw_clear"] + FLUX_ROUNDING_WM2):
        raise AssertionError("control 6: the two flux columns are one series")
    return {"time": time, **out, "eps_clear": eps_clear, "eps_all": eps_all, "file_first_day": first_day}


def load_merra2_daily() -> dict:
    """UTC day → the daily file's row (minimum, mean, maximum of the air; mean and maximum of the 10 m wind)."""
    with gzip.open(S121.DATA_DIR / "power_merra2_daily_1991_2020.csv.gz", "rt", encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    out = {}
    for r in csv.DictReader(lines[lines.index("-END HEADER-") + 1:]):
        day = f"{int(r['YEAR']):04d}-{int(r['MO']):02d}-{int(r['DY']):02d}"
        row = {k: float(r[k]) for k in ("T2M_MIN", "T2M", "T2M_MAX", "WS10M", "WS10M_MAX")}
        if any(v <= -999 for v in row.values()):
            raise ValueError(f"the MERRA-2 daily file carries its missing value on {day}")
        out[day] = row
    return out


def station_row(day: str) -> dict | None:
    """The station's Global Summary of the Day row for `day`, in °C and m/s — None when the record has no such day."""
    c = lambda f: (float(f) - 32.0) / 1.8      # noqa: E731 — the product's temperatures are °F (`121`'s README)
    with gzip.open(S121.DATA_DIR / "gsod_33487099999_1991_1998.csv.gz", "rt", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["DATE"].strip() != day:
                continue
            if any(float(r[k]) > 9000 for k in ("TEMP", "MIN", "MAX")) or float(r["WDSP"]) > 900:
                raise ValueError(f"the station's row for {day} carries a missing value")
            return {"mean_C": c(r["TEMP"]), "mean_from_reports": int(r["TEMP_ATTRIBUTES"]),
                    "min_C": c(r["MIN"]), "min_is_derived_from_hourly_reports": r["MIN_ATTRIBUTES"].strip() == "*",
                    "max_C": c(r["MAX"]), "max_is_an_explicit_report": not r["MAX_ATTRIBUTES"].strip(),
                    "wind_mean_m_s": float(r["WDSP"]) * KNOT_M_S}
    return None


def load_era5(window: tuple) -> tuple[dict, dict]:
    """`79`'s ERA5 join: the whole record on the file's clock (for control 1) and the window on the UTC clock."""
    w = S81.S79.load_weather()
    offset_h, rem = divmod(int(S81.S79._header_dict(S81.S71.DATA_FILE)["utc_offset_seconds"]), 3600)
    if rem:
        raise AssertionError("the ERA5 file's UTC offset is not a whole number of hours")
    utc = w["time"].astype("datetime64[h]") - np.timedelta64(offset_h, "h")
    day = utc.astype("datetime64[D]")
    keep = (day >= np.datetime64(window[0])) & (day <= np.datetime64(window[1]))
    full = {"time": w["time"], "t_air": w["t_air"], "t_dew": w["t_dew"]}
    cut = {"time": np.datetime_as_string(utc[keep], unit="h"), "t_air": w["t_air"][keep], "t_dew": w["t_dew"][keep],
           "utc_offset_h": offset_h}
    return full, cut


def control_81(full: dict, d_m: float) -> dict:
    """Control 1: `81`'s cached deep edge, reproduced through this script's call path."""
    d81 = json.loads((THERMAL / "capsule_cold_edge_sky.json").read_text())
    if (d81["edges"]["deep"]["regime"], d81["edges"]["deep"]["wind"]) != DEEP:
        raise AssertionError(f"control 1: `81`'s deep edge is now {d81['edges']['deep']['regime']} / {d81['edges']['deep']['wind']}, not {DEEP}")
    cached = d81["runs"][DEEP[0]][DEEP[1]]
    got = S81.stats(deep_edge(full["t_air"], full["t_dew"], d_m), full["time"], full["t_air"])
    if got != cached:
        diff = {k: (got[k], cached[k]) for k in cached if got.get(k) != cached[k]}
        raise AssertionError(f"control 1: `81`'s deep edge is not reproduced here — (here, in `81`): {diff}")
    return {"reproduced": True, "regime": DEEP[0], "wind": DEEP[1], "fields": sorted(cached)}


def control_121(m2: dict, era5: dict, hours121: dict) -> dict:
    """Control 3: the ERA5 window against `121`'s reader hour for hour, and the air's hours below `121`'s thresholds."""
    if not np.array_equal(era5["t_air"], np.array(S121.load_era5()["hourly_utc"])):
        raise AssertionError("control 3: the ERA5 window is not `121`'s UTC series hour for hour — the clock offset or its sign")
    out = {}
    for name, air in (("merra2", m2["t_air"]), ("era5", era5["t_air"])):
        if len(air) != hours121[f"hours_{name}"]:
            raise AssertionError(f"control 3: {name} has {len(air)} hours on the window, `121` counted {hours121[f'hours_{name}']}")
        here = {thr: int((air < float(thr)).sum()) for thr in hours121[name]}
        if here != hours121[name]:
            raise AssertionError(f"control 3: {name} air hours below thresholds here {here} ⊥ `121` {hours121[name]}")
        out[name] = here
    return out


def control_dew(m2: dict, era5: dict) -> dict:
    """Control 5: MERRA-2's dew column against ERA5's dew point on the same UTC hours."""
    diff = float(np.mean(m2["t_dew"] - era5["t_dew"]))
    r = float(np.corrcoef(m2["t_dew"], era5["t_dew"])[0, 1])
    if abs(diff) > DEW_UNITS_BOUND_K or r < DEW_MIN_CORRELATION:
        raise AssertionError(f"control 5: MERRA-2 dew against ERA5 dew — mean {diff:+.2f} K, r {r:.3f}")
    return {"mean_minus_era5_K": diff, "correlation": r, "bound_K": DEW_UNITS_BOUND_K, "least_correlation": DEW_MIN_CORRELATION}


def bisect(f, lo: float, hi: float) -> float:
    """Root of a scalar `f` that changes sign once on [lo, hi]; raises when it does not or the loop does not close."""
    flo, fhi = f(lo), f(hi)
    if not flo * fhi < 0:
        raise RuntimeError(f"bisection bracket [{lo}, {hi}] does not hold a sign change ({flo:.3g}, {fhi:.3g})")
    for _ in range(BISECT_ITER):
        mid = 0.5 * (lo + hi)
        if (f(mid) > 0) == (flo > 0):
            lo = mid
        else:
            hi = mid
        if hi - lo < 1e-9:
            return 0.5 * (lo + hi)
    raise RuntimeError(f"bisection did not close in {BISECT_ITER} iterations")


def days_before(edge121: dict, m2: dict, d_m: float) -> dict:
    """The capsule at every daily minimum the daily file carries before the hourly record. Control 4."""
    days = edge121["lowest_days"]
    if len(days) != 1 or not days[0] < m2["file_first_day"]:
        raise AssertionError(f"control 4: MERRA-2's lowest daily minimum ({days}) is not one day before the hourly record "
                             f"({m2['file_first_day']}) — the sweep is the wrong tool")
    daily = load_merra2_daily()
    air = float(edge121["lowest_C"])
    if daily.get(days[0], {}).get("T2M_MIN") != air:
        raise AssertionError(f"control 4: the daily file reads {daily.get(days[0])} on {days[0]}, `121` caches {air}")

    def at(t_air: float, dd: float, u: float = 0.0) -> float:
        ta = np.array([t_air])
        return float(lump(ta, S81.t_env4(False, ta, ta - dd), d_m, np.array([u]))[0])

    def eps_formula(t_air: float, dd: float) -> float:
        return float(S81.S79.sky_emissivity(np.array([t_air]), np.array([t_air - dd]))[0])

    sweep = [{"air_minus_dew_K": dd, "sky_emissivity": eps_formula(air, dd), "capsule_C": at(air, dd), "minus_air_K": at(air, dd) - air}
             for dd in DEW_SWEEP_K]
    before = sorted(d for d in daily if d < m2["file_first_day"])
    air_b = np.array([daily[d]["T2M_MIN"] for d in before])
    ends = {}
    for dd in (DEW_SWEEP_K[0], DEW_SWEEP_K[-1]):
        t = deep_edge(air_b, air_b - dd, d_m)
        ends[f"{dd:g}"] = [{"day": before[i], "air_min_C": float(air_b[i]), "capsule_C": float(t[i])} for i in np.flatnonzero(t < REQUIREMENT_C)]

    # what the same files say on the days the lump falls below the requirement at any end of the sweep
    coldest = np.argsort(m2["t_air"])[:COLDEST_HOURS]
    eps_prod = spread(m2["eps_clear"][coldest])
    those = {}
    for day in sorted({h["day"] for hits in ends.values() for h in hits}):
        row = daily[day]
        ta = np.array([row["T2M_MIN"]])
        need = {f"{dd:g}": bisect(lambda u, t0=row["T2M_MIN"], dd=dd: at(t0, dd, u) - REQUIREMENT_C, 0.0, 5.0)
                for dd in (DEW_SWEEP_K[0], DEW_SWEEP_K[-1]) if at(row["T2M_MIN"], dd) < REQUIREMENT_C}
        st = station_row(day)
        those[day] = {
            "merra2": {"min_C": row["T2M_MIN"], "mean_C": row["T2M"], "max_C": row["T2M_MAX"],
                       "wind_10m_mean_m_s": row["WS10M"], "wind_10m_max_m_s": row["WS10M_MAX"]},
            "sky_emissivity_on_the_requirement": bisect(lambda e, ta=ta: float(lump(ta, env4_emissivity(ta, e), d_m)[0]) - REQUIREMENT_C, 0.2, 1.0),
            "capsule_at_product_clear_sky_emissivity_C": {k: float(lump(ta, env4_emissivity(ta, e), d_m)[0]) for k, e in eps_prod.items()},
            "wind_at_the_capsule_on_the_requirement_m_s": need,
            "that_wind_as_a_share_of_the_daily_mean_10m_wind": {k: u / row["WS10M"] for k, u in need.items()},
            "that_wind_as_a_share_of_the_station_mean_wind": {k: u / st["wind_mean_m_s"] for k, u in need.items()} if st else None,
            "capsule_with_a_share_of_the_daily_mean_wind_C": {f"k={k}": {f"{dd:g}": at(row["T2M_MIN"], dd, k * row["WS10M"])
                                                                         for dd in (DEW_SWEEP_K[0], DEW_SWEEP_K[-1])} for k in WIND_K},
            "station": st,
        }
    own = (m2["t_air"] - m2["t_dew"])[coldest]
    return {"day": days[0], "air_min_C": air, "sweep": sweep,
            "merra2_air_minus_dew_on_its_coldest_hours_K": {"hours": COLDEST_HOURS, **spread(own)},
            "every_day_before_the_hourly_record": {"first_day": before[0], "last_day": before[-1], "days": len(before),
                                                   "below_requirement_at_air_minus_dew_K": ends},
            "days_below_the_requirement": those}


def minus_air(t, t_air) -> dict:
    cold = t_air < COLD_AIR_C
    d = (t - t_air)[cold]
    return {"hours": int(cold.sum()), "deepest_K": float(d.min()), "median_K": float(np.median(d)), "shallowest_K": float(d.max())}


def deg(x: float, nd: int = 1) -> str:
    return f"{x:.{nd}f}".replace("-", "−")


def main() -> int:
    banner("HW.37 — the capsule's deep cold edge on MERRA-2 air (the colder named reading), under three skies")
    d121 = json.loads((THERMAL / "cold_edge_station.json").read_text())
    hours121 = d121["hours_below_2001_2020"]
    window = tuple(hours121["window_utc_days"])
    d_m = S81.S71.geometry()["dome_diameter_mm"] * 1e-3

    era5_full, era5 = load_era5(window)
    m2 = load_merra2(window)
    c1 = control_81(era5_full, d_m)
    print("  control 1: `81`'s cached deep edge reproduced through this script's call path ✓")
    print(f"  controls 2 · 6: MERRA-2 — {len(m2['t_air'])} hours on one unbroken clock, no missing value, clear-sky flux ≤ all-sky ✓")
    c3 = control_121(m2, era5, hours121)
    print("  control 3: the ERA5 window is `121`'s series hour for hour; air hours below `121`'s thresholds equal its counts ✓")
    c5 = control_dew(m2, era5)
    print(f"  control 5: MERRA-2 dew against ERA5 dew — mean {c5['mean_minus_era5_K']:+.2f} K, r {c5['correlation']:.3f} ✓")

    readings = {}
    for name, w in (("merra2", m2), ("era5", era5)):
        cap = deep_edge(w["t_air"], w["t_dew"], d_m)
        readings[name] = {"air": summary(w["t_air"], w["time"], w["t_air"]), "capsule": summary(cap, w["time"], w["t_air"]),
                          "capsule_minus_air_on_cold_hours": minus_air(cap, w["t_air"])}

    # the sky as a second axis — MERRA-2 air under the formula's clear sky and the product's two fluxes
    ta, time = m2["t_air"], m2["time"]
    skies = {"formula_clear": readings["merra2"]["capsule"],
             "product_clear": summary(lump(ta, env4_flux(ta, m2["lw_clear"]), d_m), time, ta),
             "product_all_sky": summary(lump(ta, env4_flux(ta, m2["lw_all"]), d_m), time, ta)}
    coldest = np.argsort(ta)[:COLDEST_HOURS]
    eps_formula = S81.S79.sky_emissivity(ta, m2["t_dew"])
    lw_formula = eps_formula * SIGMA * kelvin4(ta)
    sky_cold = {"hours": COLDEST_HOURS, "formula_clear": spread(eps_formula[coldest]), "product_clear": spread(m2["eps_clear"][coldest]),
                "product_all_sky": spread(m2["eps_all"][coldest]),
                "formula_minus_product_clear_Wm2": spread((lw_formula - m2["lw_clear"])[coldest])}
    for name, s in skies.items():
        print(f"  MERRA-2 air, {name:15s}: capsule coldest {deg(s['coldest_C'], 2)} °C ({s['at']}), {s['hours_below_floor']} h below the floor, "
              f"{s['hours_below_requirement']} h below {deg(REQUIREMENT_C, 0)} °C")
    e = readings["era5"]["capsule"]
    print(f"  ERA5 air,    formula_clear  : capsule coldest {deg(e['coldest_C'], 2)} °C ({e['at']}), {e['hours_below_floor']} h below the floor")

    # the «dew/frost point» read three ways: over water (the run above), capped at the air, as a frost point over ice
    m = readings["merra2"]["capsule"]
    above = m2["t_dew"] > ta
    variants = {}
    for key, td in (("capped_at_air", np.minimum(m2["t_dew"], ta)), ("read_as_frost_point", S120.frost_point_as_dew_point(m2["t_dew"]))):
        s = summary(deep_edge(ta, td, d_m), time, ta)
        variants[key] = {"capsule": s, "coldest_shift_K": s["coldest_C"] - m["coldest_C"],
                         "hours_below_floor_shift": s["hours_below_floor"] - m["hours_below_floor"]}

    out_day = days_before(d121["cold_edge"]["merra2_utc_day"], m2, d_m)

    # the lump's own spread: `71`'s ×0.7 reading of its still-air kernel, run on the cold edge
    eps_prod = sky_cold["product_clear"]
    with kernel_scaled(KERNEL_SCALE):
        k_skies = {"formula_clear": summary(deep_edge(ta, m2["t_dew"], d_m), time, ta),
                   "product_clear": summary(lump(ta, env4_flux(ta, m2["lw_clear"]), d_m), time, ta),
                   "product_all_sky": summary(lump(ta, env4_flux(ta, m2["lw_all"]), d_m), time, ta)}
        k_era5 = summary(deep_edge(era5["t_air"], era5["t_dew"], d_m), era5["time"], era5["t_air"])
        k_days = {}
        for day, x in out_day["days_below_the_requirement"].items():
            t0 = np.array([x["merra2"]["min_C"]])
            k_days[day] = {key: float(lump(t0, env4_emissivity(t0, e), d_m)[0]) for key, e in eps_prod.items()}
    if summary(deep_edge(ta, m2["t_dew"], d_m), time, ta) != m:
        raise AssertionError("control 7: `71`'s kernels were not restored after the sensitivity run")
    if not all(k_skies[k]["coldest_C"] < skies[k]["coldest_C"] for k in skies):
        raise AssertionError("control 7: a weaker still-air kernel did not make the capsule colder — the scaling did not reach the lump")
    print(f"  control 7: kernel × {KERNEL_SCALE} makes every run colder, and the unscaled deep edge is reproduced after it ✓")
    for name, s in k_skies.items():
        print(f"    kernel × {KERNEL_SCALE}, MERRA-2 air, {name:15s}: coldest {deg(s['coldest_C'], 2)} °C, {s['hours_below_floor']} h below the floor, "
              f"{s['hours_below_requirement']} h below {deg(REQUIREMENT_C, 0)} °C")
    print(f"  control 4: MERRA-2's lowest daily minimum ({out_day['day']}) precedes the hourly record and is the daily file's ✓")
    every = out_day["every_day_before_the_hourly_record"]
    hits = every["below_requirement_at_air_minus_dew_K"]
    for dd, h in hits.items():
        print(f"    days of {every['first_day'][:4]}–{every['last_day'][:4]} with the capsule below {deg(REQUIREMENT_C, 0)} °C, air minus dew "
              f"{dd} K: {len(h)} — {', '.join(x['day'] for x in h)}")
    for day, x in out_day["days_below_the_requirement"].items():
        st = x["station"]
        print(f"    {day}: sky emissivity on the requirement {x['sky_emissivity_on_the_requirement']:.3f}; MERRA-2 wind "
              f"{x['merra2']['wind_10m_mean_m_s']:.2f} m/s; station " + (f"mean {deg(st['mean_C'])} °C, min {deg(st['min_C'])} °C" if st else "has no row"))

    sweep_c = [s["capsule_C"] for s in out_day["sweep"]]
    in_window = ("stays above" if m["hours_below_requirement"] == 0 else f"is on {m['hours_below_requirement']} hours below")
    n = [len(h) for h in hits.values()]
    n_days = f"{n[-1]}" if n[0] == n[-1] else f"{min(n)} to {max(n)}"
    named = ", ".join(sorted({x["day"] for h in hits.values() for x in h}))
    verdict = (f"On MERRA-2 air the capsule's deep edge (isolated, Brutsaert's clear sky, no sun, still air) bottoms at "
               f"{deg(m['coldest_C'], 2)} °C over {window[0][:4]}–{window[1][:4]} and {in_window} the capsule requirement of "
               f"{deg(REQUIREMENT_C, 0)} °C; under the product's clear-sky flux the same lump on the same air bottoms at "
               f"{deg(skies['product_clear']['coldest_C'], 2)} °C, on ERA5 air under the formula at {deg(e['coldest_C'], 2)} °C. Below the "
               f"EDLC floor of {deg(EDLC_OPERATING_MIN_C, 0)} °C: {m['hours_below_floor']} hours (formula sky), "
               f"{skies['product_clear']['hours_below_floor']} (product's clear sky), {e['hours_below_floor']} (ERA5 air, formula sky). "
               f"Solved under the formula sky at the minimum of each of the {every['days']} days before the hourly record, the lump is "
               f"below the requirement on {n_days} ({named}), by at most {REQUIREMENT_C - min(sweep_c):.2f} K; with the product's "
               f"clear-sky ratios, or with a tenth of the daily-mean wind, the lump there is above the requirement. With `71`'s "
               f"×{KERNEL_SCALE:g} reading of the still-air kernel the formula-sky run on MERRA-2 air bottoms at "
               f"{deg(k_skies['formula_clear']['coldest_C'], 2)} °C with {k_skies['formula_clear']['hours_below_requirement']} hours below "
               f"the requirement inside the hourly record, the product's clear-sky run at {deg(k_skies['product_clear']['coldest_C'], 2)} °C.")

    result = {
        "script": "122_capsule_cold_edge_second_reading.py",
        "question": "does the capsule's deep cold edge still clear the capsule requirement on the colder named reading of the air, and on what does a crossing stand",
        "model": {"lump": "81 (imported): isolated, steady per hour", "regime": DEEP[0], "wind": DEEP[1],
                  "edlc_floor_C": EDLC_OPERATING_MIN_C, "capsule_requirement_C": REQUIREMENT_C,
                  "window_utc_days": list(window), "era5_utc_offset_h": era5["utc_offset_h"],
                  "dew_sweep_K": list(DEW_SWEEP_K), "cold_air_C": COLD_AIR_C, "wind_k": list(WIND_K),
                  "kernel_scale": KERNEL_SCALE, "years_of_window": len(ta) / HOURS_PER_YEAR,
                  "skies": {"formula_clear": "Brutsaert 1975 from the dew point, via 79 — 81's clear sky",
                            "product_clear": "CLRSKY_SFC_LW_DWN of the same row", "product_all_sky": "ALLSKY_SFC_LW_DWN of the same row"}},
        "inputs": {"hours": len(ta), "merra2_hourly_first_day": m2["file_first_day"], "merra2_hours_dew_above_air": int(above.sum()),
                   "merra2_hours_dew_above_air_with_air_at_or_above_0C": int((above & (ta >= 0.0)).sum())},
        "controls": {"deep_edge_of_81": c1, "air_hours_below_thresholds_as_in_121": c3, "era5_window_is_121s_hour_for_hour": True,
                     "merra2_dew_against_era5_dew": c5, "kernel_scaled_run_colder_and_restored": True},
        "readings": readings,
        "merra2_air_by_sky": skies,
        "sky_emissivity_on_merra2_coldest_hours": sky_cold,
        "merra2_dew": variants,
        "kernel_sensitivity": {"scale": KERNEL_SCALE, "merra2_air_by_sky": k_skies, "era5_formula_clear": k_era5,
                               "capsule_at_product_clear_sky_emissivity_on_the_days_below_the_requirement_C": k_days},
        "day_before_the_hourly_record": out_day,
        "verdict": verdict,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(verdict)
    print(f"→ {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
