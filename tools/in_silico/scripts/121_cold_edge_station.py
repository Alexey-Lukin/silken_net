#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""HW.37 — does the reanalysis the cold edge stands on run warm on cold nights? ERA5 and MERRA-2 daily minima against
the Cherkasy station, on two station records that do not overlap.

QUESTION. Canon's cold numbers for the node — the lowest air temperature and every count of cold hours and days —
are read off ERA5 (`docs/02_03 §12.1`; `81`; the frost days of `79`). A desk pass on 2026-11-13 found ERA5 warmer than
the station on the coldest nights of 2000–2009. Three things were open: does the gap hold on another decade, how much
of it is produced by choosing the days BY the station, and what a second reanalysis gives for the same edge.

DATA. `tools/in_silico/data/station_cherkasy/` (queries, flags and ceilings — its README):
  · GHCN-Daily `UPM00033487`, TMIN, 2000-01-01 … 2009-06-17 — values whose quality flag is blank;
  · GSOD `33487099999`, MIN, 1991 … 1998 — split by its attribute: an explicit minimum report ⊥ a minimum derived from
    the hourly reports (`*`), which can only sit at or above the true minimum;
  · MERRA-2 daily T2M_MIN (NASA POWER), 1991–2020, UTC days.
ERA5 is the tree's hourly file (`data/era5_cherkasy/hourly_1991_2020.csv.gz`). The station's «day» for a reported
minimum is a reporting window, not a calendar day, so ERA5's minimum is taken over THREE windows and all three are
carried: the UTC day, the file's own clock day (UTC+3), and the night 18:00 UTC of the previous day … 06:00 UTC — a
window a morning minimum report plausibly covers, NOT read from a station manual.

METHOD. Days are paired by date, on the days EVERY reading carries (the night window needs the previous evening, so
the file's first day drops out); nothing is interpolated or filled.
  A. reanalysis − station on the paired days, conditioned three ways, because a gap measured on days CHOSEN by one
     series is pulled toward that series' extremes: (1) station below a threshold; (2) reanalysis below the same
     threshold; (3) no condition — the low quantiles of the winter minima of each series on the same days, and the
     number of those days each series puts below each threshold. (1) and (2) are two ENDS, not two parts of one gap.
  B. the edge itself over whole seasons July…June: the lowest minimum with every day it fell on, the days below each
     threshold, and the days whose MAXIMUM stays below each threshold, for ERA5 and for MERRA-2 — two named readings,
     neither picked;
  C. HOURS below each threshold, 2001–2020 — the form canon counts the cold edge in — from the two hourly series
     the tree already holds: ERA5's, and MERRA-2's 2 m temperature riding in `data/power_cherkasy_longwave/` (an
     hour's mean there against the value at the hour here; a count of hours needs no clock pairing).

CONTROLS — each can fail:
  1. Pairing. The correlation of station and reanalysis minima at lag 0 exceeds lag −1 and lag +1, for every record
     and every reading. CAN catch: a one-day shift in any file. CANNOT: a unit error (correlation ignores scale), nor
     which of the three ERA5 windows is the station's.
  2. Units. The mean reanalysis − station over ALL paired days of a record is inside ±3 K. CAN catch: °F left as °C
     (GSOD arrives in °F even from a «metric» request), tenths of a degree read as degrees. CANNOT: a bias of the
     size this script is looking for — which is why it is a bound, not a pin.
  3. ERA5 files agree. The clock-day MEAN recomputed from the hourly file equals `daily_t2m_mean_1991_2020.csv` on
     every day to the rounding of both (0.1 K). CAN catch: a clock offset applied to the wrong file (the UTC-day mean
     misses by kelvins), a wrong column, a one-day shift. CANNOT: an error common to both files.
  4. The GHCN-Daily file is the one the README describes: the quality flags dropped are exactly its 74 «I» and one «G»,
     and kept plus dropped is the README's 2 558 TMIN values. CAN catch: another or a shorter response under the same
     name, a flag read from the wrong field of the attribute triple. CANNOT: a wrong flag in the archive.
  5. MERRA-2 files agree. The daily T2M_MIN equals the minimum of the hourly T2M over the UTC day on every day of
     2001–2020 (0.011 K for rounding). CAN catch: a one-day shift of either file, a daily minimum that is not the
     minimum of the hourly field. CANNOT: an error in MERRA-2.
  6. The direction of the clock offset. ERA5's hourly values, read as UTC by SUBTRACTING the file's offset, change hour
     to hour in step with MERRA-2's UTC series: the correlation of first differences peaks within one hour (lags
     −3…+3). CAN catch: the offset applied with the wrong sign (the peak then sits six hours away; tried both ways) —
     the UTC day, the night window and the hours window all stand on it. CANNOT: an error inside the tolerance — the
     peak already sits between lags −1 and 0 (instants against hourly means), so a series two hours late still passes
     while one two hours early does not (tried).

CEILINGS. One station, and not the forest plot: a synoptic site at a town against cells of 0.25° and
0.5° × 0.625° — part of any gap is siting, not reanalysis error. The two station records share no day, so nothing
here says they are one instrument. A reanalysis «daily minimum» is the lowest of 24 hourly values — instants for ERA5,
hourly means for MERRA-2 — and both sit at or above the continuous minimum a thermometer reports. The coldest bins
hold a handful of days (the cache carries the counts) and their means are not bias estimates. Nothing here CORRECTS a
reanalysis; it says how far apart the two readings of the edge are, and where the station fell between or beyond them.
The node's capsule is not air: `81` puts it below the air under a clear calm sky, and `81` ran on ERA5 only.

Run: python scripts/121_cold_edge_station.py   (seconds)
"""

import csv
import gzip
import itertools
import json
import statistics as st
import sys
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Whether a reanalysis runs warm on cold nights: daily minimum air temperature of two reanalyses "
                  "against two non-overlapping records of one synoptic station, with the gap conditioned on the "
                  "station, on the reanalysis and on neither, and the cold edge of twenty-nine seasons read from "
                  "both reanalyses.")

DATA_DIR = REPO_ROOT / "tools/in_silico/data/station_cherkasy"
ERA5_DIR = REPO_ROOT / "tools/in_silico/data/era5_cherkasy"
MERRA2_HOURLY = REPO_ROOT / "tools/in_silico/data/power_cherkasy_longwave/hourly_2001_2020.csv.gz"
HOURS_WINDOW = ("2001-01-01", "2020-12-30")     # whole UTC days both hourly series carry (the ERA5 file stops 3 h short of 2020's UTC end)
EDGE_WINDOW = ("1991-07-01", "2020-06-30")      # whole seasons July…June both reanalyses carry
OUT = CACHE_DIR / "thermal" / "cold_edge_station.json"
THRESHOLDS_C = (-10.0, -15.0, -20.0, -25.0)     # the grid every count and condition is taken on — points, not a law
QUANTILES = (0.01, 0.05, 0.10)
WINTER_MONTHS = (11, 12, 1, 2, 3)
NIGHT_UTC = (18, 6)                             # the night window: 18:00 UTC of the previous day … 06:00 UTC, both ends in
MIN_BIN = 5                                     # a conditioned bin is reported as a mean only with this many days
UNITS_BOUND_K = 3.0
ERA5_FILES_TOL_K = 0.1                          # the daily file is rounded to 0.1 K, the hourly values too
MERRA2_FILES_TOL_K = 0.011
GHCND_QUALITY_FLAGS = {"I": 74, "G": 1}         # the README's count of flagged TMIN values — control 4
GHCND_TMIN_VALUES = 2558                        # the README's count of TMIN values, flagged or not — control 4
OFFSET_LAGS = (-3, -2, -1, 0, 1, 2, 3)          # control 6


def load_ghcnd() -> tuple[dict, dict]:
    """date → TMIN °C for values with a blank quality flag; and the count of each quality flag dropped (control 4)."""
    out, dropped = {}, Counter()
    with gzip.open(DATA_DIR / "ghcnd_UPM00033487_2000_2009.csv.gz", "rt", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if not r["TMIN"].strip():
                continue
            _, quality, _ = r["TMIN_ATTRIBUTES"].split(",")
            if quality:
                dropped[quality] += 1
                continue
            out[r["DATE"]] = float(r["TMIN"])
    if dict(dropped) != GHCND_QUALITY_FLAGS or len(out) + sum(dropped.values()) != GHCND_TMIN_VALUES:
        raise AssertionError(f"control 4: {len(out)} kept and {dict(dropped)} dropped — the README's file has {GHCND_QUALITY_FLAGS} "
                             f"dropped of {GHCND_TMIN_VALUES} TMIN values")
    return out, dict(dropped)


def load_gsod() -> tuple[dict, dict]:
    """date → MIN °C, split by the attribute: explicit report ⊥ derived from hourly (`*`). GSOD carries °F."""
    explicit, derived = {}, {}
    with gzip.open(DATA_DIR / "gsod_33487099999_1991_1998.csv.gz", "rt", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            if r["MIN"].strip() == "9999.9":
                continue
            attr = r["MIN_ATTRIBUTES"].strip()
            if attr not in ("", "*"):
                raise ValueError(f"GSOD MIN attribute this script does not know: {attr!r} on {r['DATE']}")
            (derived if attr else explicit)[r["DATE"]] = (float(r["MIN"]) - 32.0) / 1.8
    return explicit, derived


def load_merra2() -> tuple[dict, dict]:
    """date (UTC day) → T2M_MIN, T2M_MAX; refuses the product's missing value."""
    with gzip.open(DATA_DIR / "power_merra2_daily_1991_2020.csv.gz", "rt", encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    tmin, tmax = {}, {}
    for r in csv.DictReader(lines[lines.index("-END HEADER-") + 1:]):
        day = f"{int(r['YEAR']):04d}-{int(r['MO']):02d}-{int(r['DY']):02d}"
        lo, hi = float(r["T2M_MIN"]), float(r["T2M_MAX"])
        if lo <= -999 or hi <= -999:
            raise ValueError(f"MERRA-2 carries its missing value on {day}")
        tmin[day], tmax[day] = lo, hi
    return tmin, tmax


def load_era5() -> dict:
    """The hourly file reduced to daily minima over three windows (clock day · UTC day · the night ending at 06:00
    UTC), daily maxima over the first two, the clock-day mean (control 3) and the hours below each threshold."""
    lo_clock, hi_clock, lo_utc, hi_utc, lo_night = {}, {}, {}, {}, {}
    total, count, night_n = Counter(), Counter(), Counter()
    hours_below, hours, series = dict.fromkeys(THRESHOLDS_C, 0), 0, []
    with gzip.open(ERA5_DIR / "hourly_1991_2020.csv.gz", "rt", encoding="utf-8") as fh:
        meta = next(csv.DictReader([fh.readline(), fh.readline()]))
        offset = timedelta(seconds=int(meta["utc_offset_seconds"]))
        fh.readline()
        rows = csv.reader(fh)
        head = next(rows)
        col = [i for i, h in enumerate(head) if h.startswith("temperature_2m")]
        if head[0] != "time" or len(col) != 1:
            raise ValueError(f"unexpected ERA5 header: {head}")
        for row in rows:
            t = float(row[col[0]])
            utc = datetime.fromisoformat(row[0]) - offset
            clock_day, utc_day = row[0][:10], utc.date().isoformat()
            total[clock_day] += t
            count[clock_day] += 1
            if HOURS_WINDOW[0] <= utc_day <= HOURS_WINDOW[1]:
                hours += 1
                series.append(t)
                for thr in THRESHOLDS_C:
                    hours_below[thr] += t < thr
            for day, lo, hi in ((clock_day, lo_clock, hi_clock), (utc_day, lo_utc, hi_utc)):
                if day not in lo or t < lo[day]:
                    lo[day] = t
                if day not in hi or t > hi[day]:
                    hi[day] = t
            night = (utc.date() + timedelta(days=1)).isoformat() if utc.hour >= NIGHT_UTC[0] else utc_day if utc.hour <= NIGHT_UTC[1] else None
            if night:
                night_n[night] += 1
                if night not in lo_night or t < lo_night[night]:
                    lo_night[night] = t
    first, last = min(lo_clock), max(lo_clock)
    whole = {d for d in lo_utc if first <= d < last}          # the UTC days before the first and on the last clock day are cut by the offset
    full_night = (24 - NIGHT_UTC[0]) + NIGHT_UTC[1] + 1
    return {"offset_s": int(offset.total_seconds()), "hours": hours, "hours_below": hours_below, "hourly_utc": series,
            "min_clock": lo_clock, "max_clock": hi_clock, "mean_clock": {d: total[d] / count[d] for d in lo_clock},
            "min_utc": {d: lo_utc[d] for d in whole}, "max_utc": {d: hi_utc[d] for d in whole},
            "min_night": {d: v for d, v in lo_night.items() if night_n[d] == full_night}}


def merra2_hourly() -> dict:
    """MERRA-2's hourly 2 m temperature: hours below each threshold over HOURS_WINDOW, and the minimum per UTC day."""
    below, hours, lo, series = dict.fromkeys(THRESHOLDS_C, 0), 0, {}, []
    with gzip.open(MERRA2_HOURLY, "rt", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            day = f"{int(r['YEAR']):04d}-{int(r['MO']):02d}-{int(r['DY']):02d}"
            t = float(r["T2M"])
            if t <= -999:
                raise ValueError(f"MERRA-2 hourly carries its missing value on {day}")
            if day not in lo or t < lo[day]:
                lo[day] = t
            if HOURS_WINDOW[0] <= day <= HOURS_WINDOW[1]:
                hours += 1
                series.append(t)
                for thr in THRESHOLDS_C:
                    below[thr] += t < thr
    return {"hours": hours, "hours_below": below, "min_utc": lo, "hourly_utc": series}


def control_era5_files(era5: dict) -> dict:
    """Control 3: the clock-day mean recomputed from the hourly file against the daily-mean file."""
    worst, n = 0.0, 0
    with open(ERA5_DIR / "daily_t2m_mean_1991_2020.csv", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            worst = max(worst, abs(float(r["t2m_mean_c"]) - era5["mean_clock"][r["date"]]))
            n += 1
    if worst > ERA5_FILES_TOL_K:
        raise AssertionError(f"control 3: the hourly file's clock-day mean misses the daily-mean file by {worst:.3f} K")
    return {"days": n, "worst_difference_K": worst, "tolerance_K": ERA5_FILES_TOL_K}


def control_merra2_files(daily_min: dict, hourly_min: dict) -> dict:
    """Control 5: the daily T2M_MIN against the minimum of the hourly T2M over the UTC day."""
    days = sorted(set(daily_min) & set(hourly_min))
    worst = max(abs(daily_min[d] - hourly_min[d]) for d in days)
    if worst > MERRA2_FILES_TOL_K:
        raise AssertionError(f"control 5: MERRA-2's daily minimum misses the minimum of its hourly field by {worst:.3f} K")
    return {"days": len(days), "worst_difference_K": worst, "tolerance_K": MERRA2_FILES_TOL_K}


def control_offset_direction(era5_utc: list, merra2_utc: list) -> dict:
    """Control 6: first differences of the two hourly series over the hours window; lag L pairs ERA5's change at hour i
    with MERRA-2's at hour i + L."""
    da = [y - x for x, y in itertools.pairwise(era5_utc)]
    db = [y - x for x, y in itertools.pairwise(merra2_utc)]
    by_lag = {}
    for lag in OFFSET_LAGS:
        a = da[max(-lag, 0): len(da) - max(lag, 0)]
        b = db[max(lag, 0): len(db) - max(-lag, 0)]
        by_lag[str(lag)] = pearson(a, b)
    best = max(by_lag, key=by_lag.get)
    if abs(int(best)) > 1:
        raise AssertionError(f"control 6: ERA5 read as UTC pairs best with MERRA-2 at lag {best} h — the offset's sign is suspect: {by_lag}")
    return {"correlation_by_lag_h": by_lag, "best_lag_h": int(best)}


def pearson(a: list, b: list) -> float:
    ma, mb = st.fmean(a), st.fmean(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b, strict=True))
    return num / (sum((x - ma) ** 2 for x in a) * sum((y - mb) ** 2 for y in b)) ** 0.5


def shifted(day: str, lag: int) -> str:
    return (date.fromisoformat(day) + timedelta(days=lag)).isoformat()


def control_pairing(station: dict, ref: dict, what: str) -> dict:
    """Control 1: lag 0 correlates best."""
    out = {}
    for lag in (-1, 0, 1):
        days = [d for d in station if shifted(d, lag) in ref]
        out[str(lag)] = pearson([station[d] for d in days], [ref[shifted(d, lag)] for d in days])
    if not (out["0"] > out["-1"] and out["0"] > out["1"]):
        raise AssertionError(f"control 1: {what} pairs best at a lag other than 0: {out}")
    return out


def quantile(values: list, q: float) -> float:
    s = sorted(values)
    pos = q * (len(s) - 1)
    lo = int(pos)
    return s[lo] + (s[min(lo + 1, len(s) - 1)] - s[lo]) * (pos - lo)


def gap(days: list, station: dict, ref: dict) -> dict:
    """reanalysis − station over `days`; a mean only where the bin is not thin."""
    if len(days) < MIN_BIN:
        return {"days": len(days)}
    d = [ref[x] - station[x] for x in days]
    return {"days": len(days), "mean_K": st.fmean(d), "median_K": st.median(d)}


def compare(station: dict, refs: dict) -> dict:
    """One station record against every reanalysis reading, on the days ALL of them carry."""
    days = sorted(d for d in station if all(d in r for r in refs.values()))
    winter = [d for d in days if int(d[5:7]) in WINTER_MONTHS]
    lowest = min(station[d] for d in days)
    out = {"paired_days": len(days), "first_day": days[0], "last_day": days[-1], "winter_days": len(winter),
           "station": {"lowest_C": lowest, "lowest_days": [d for d in days if station[d] == lowest],
                       "winter_quantiles_C": {str(q): quantile([station[d] for d in winter], q) for q in QUANTILES},
                       "days_below": {str(t): sum(station[d] < t for d in days) for t in THRESHOLDS_C}},
           "reanalyses": {}}
    for name, ref in refs.items():
        all_days = gap(days, station, ref)
        if abs(all_days["mean_K"]) > UNITS_BOUND_K:
            raise AssertionError(f"control 2: {name} − station over all paired days is {all_days['mean_K']:.2f} K")
        coldest = min(ref[d] for d in days)
        out["reanalyses"][name] = {
            "all_days": all_days,
            "winter_days": gap(winter, station, ref),
            "station_below": {str(t): gap([d for d in days if station[d] < t], station, ref) for t in THRESHOLDS_C},
            "reanalysis_below": {str(t): gap([d for d in days if ref[d] < t], station, ref) for t in THRESHOLDS_C},
            "winter_quantiles_C": {str(q): quantile([ref[d] for d in winter], q) for q in QUANTILES},
            "days_below": {str(t): sum(ref[d] < t for d in days) for t in THRESHOLDS_C},
            "on_station_lowest_days_C": {d: ref[d] for d in out["station"]["lowest_days"]},
            "lowest_C": coldest, "station_on_its_lowest_days_C": {d: station[d] for d in days if ref[d] == coldest},
            "pairing_correlation_by_lag": control_pairing(station, ref, name)}
    return out


def season(day: str) -> int:
    return int(day[:4]) if int(day[5:7]) >= 7 else int(day[:4]) - 1


def edge(tmin: dict, tmax: dict, records: dict) -> dict:
    """The cold edge of one reanalysis reading over the whole seasons July…June inside EDGE_WINDOW."""
    days = sorted(d for d in tmin if EDGE_WINDOW[0] <= d <= EDGE_WINDOW[1])
    seasons = sorted({season(d) for d in days})
    lowest = min(tmin[d] for d in days)
    lowest_days = [d for d in days if tmin[d] == lowest]
    out = {"days": len(days), "seasons": len(seasons), "lowest_C": lowest, "lowest_days": lowest_days,
           "station_on_lowest_days_C": {d: {name: rec.get(d) for name, rec in records.items()} for d in lowest_days},
           "min_below": {}, "max_below": {}}
    for t in THRESHOLDS_C:
        for key, series in (("min_below", tmin), ("max_below", tmax)):
            hit = [d for d in days if series[d] < t]
            per = Counter(season(d) for d in hit)
            out[key][str(t)] = {"days": len(hit), "seasons_with_any": len(per), "most_in_one_season": max(per.values(), default=0)}
    return out


def main() -> int:
    banner("HW.37 — the cold edge against the station: ERA5 and MERRA-2 daily minima")
    ghcnd, flags = load_ghcnd()
    gsod_explicit, gsod_derived = load_gsod()
    m2_min, m2_max = load_merra2()
    era5 = load_era5()
    m2h = merra2_hourly()
    refs = {"era5_utc_day": era5["min_utc"], "era5_clock_day": era5["min_clock"], "era5_night": era5["min_night"], "merra2_utc_day": m2_min}
    records = {"ghcnd_2000_2009": ghcnd, "gsod_1991_1998_explicit": gsod_explicit, "gsod_1991_1998_derived": gsod_derived}
    if set(ghcnd) & (set(gsod_explicit) | set(gsod_derived)):
        raise AssertionError("the two station records were expected to share no day")
    by_record = {name: compare(rec, refs) for name, rec in records.items()}
    edges = {"era5_clock_day": edge(era5["min_clock"], era5["max_clock"], records),
             "era5_utc_day": edge(era5["min_utc"], era5["max_utc"], records),
             "merra2_utc_day": edge(m2_min, m2_max, records)}
    if m2h["hours"] != era5["hours"]:
        raise AssertionError(f"the two hourly series do not cover the same hours: {m2h['hours']} against {era5['hours']}")
    hours = {"window_utc_days": list(HOURS_WINDOW), "hours_era5": era5["hours"], "hours_merra2": m2h["hours"],
             "era5": {str(t): int(n) for t, n in era5["hours_below"].items()},
             "merra2": {str(t): int(n) for t, n in m2h["hours_below"].items()}}

    def held(reading: str, cond: str, t: float) -> list:
        """The conditioned mean gap of one reading on the two independent records that report explicit minima."""
        return [by_record[r]["reanalyses"][reading][cond][str(t)].get("mean_K") for r in ("ghcnd_2000_2009", "gsod_1991_1998_explicit")]

    t = -15.0
    e_st, e_re = held("era5_utc_day", "station_below", t), held("era5_utc_day", "reanalysis_below", t)
    m_st, m_re = held("merra2_utc_day", "station_below", t), held("merra2_utc_day", "reanalysis_below", t)
    e_edge, m_edge = edges["era5_clock_day"], edges["merra2_utc_day"]
    verdict = (f"On days the station's minimum is below {t:g} °C, ERA5 (UTC day) is warmer by {e_st[0]:+.2f} K on the 2000–2009 "
               f"record and {e_st[1]:+.2f} K on the explicit minima of 1991–1998; chosen by ERA5's own minimum instead, the same "
               f"gap is {e_re[0]:+.2f} and {e_re[1]:+.2f} K. MERRA-2: {m_st[0]:+.2f} and {m_st[1]:+.2f} K chosen by the station, "
               f"{m_re[0]:+.2f} and {m_re[1]:+.2f} K chosen by itself. Lowest minimum over the {e_edge['seasons']} seasons "
               f"{EDGE_WINDOW[0][:4]}/{int(EDGE_WINDOW[0][2:4]) + 1}…{int(EDGE_WINDOW[1][:4]) - 1}/{EDGE_WINDOW[1][2:4]}: ERA5 "
               f"{e_edge['lowest_C']:.1f} °C ({', '.join(e_edge['lowest_days'])}), MERRA-2 {m_edge['lowest_C']:.1f} °C "
               f"({', '.join(m_edge['lowest_days'])}).")

    result = {
        "script": "121_cold_edge_station.py",
        "question": "does the reanalysis the cold edge stands on run warm on cold nights, and what does a second one give",
        "model": {"thresholds_C": list(THRESHOLDS_C), "quantiles": list(QUANTILES), "winter_months": list(WINTER_MONTHS),
                  "min_days_for_a_mean": MIN_BIN, "era5_clock_offset_s": era5["offset_s"], "night_window_utc_hours": list(NIGHT_UTC),
                  "gap_sign": "reanalysis minus station", "edge_window": list(EDGE_WINDOW)},
        "inputs": {"ghcnd_tmin_days": len(ghcnd), "ghcnd_dropped_on_quality_flag": flags,
                   "gsod_explicit_days": len(gsod_explicit), "gsod_derived_days": len(gsod_derived),
                   "merra2_days": len(m2_min), "era5_clock_days": len(era5["min_clock"]), "era5_utc_days": len(era5["min_utc"]),
                   "era5_nights": len(era5["min_night"])},
        "controls": {"era5_files_agree": control_era5_files(era5), "merra2_files_agree": control_merra2_files(m2_min, m2h["min_utc"]),
                     "era5_utc_offset_direction": control_offset_direction(era5["hourly_utc"], m2h["hourly_utc"]),
                     "units_bound_K": UNITS_BOUND_K, "records_share_no_day": True},
        "station_records": by_record,
        "cold_edge": edges,
        "hours_below_2001_2020": hours,
        "verdict": verdict,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(verdict)
    print(f"→ {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
