#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""HW.43 — the wind the cycle budget counts on and the wind the field campaign is planned on come from two reanalyses
that disagree: MERRA-2 and ERA5 against the Cherkasy station's own wind.

QUESTION. `62` takes its duty fractions from MERRA-2's DAILY MEAN 10 m wind (NASA POWER); `98` plans the field strain
campaign on ERA5's HOURLY 10 m wind and its stop rule counts hours at Beaufort 5. A desk pass on 2026-11-13 found the
two series an order of magnitude apart in strong-wind hours on the same point. Three things were open: which of the two
the station's own anemometer sits nearer to, on the quantity each script actually counts; how much of any gap is
produced by choosing the days BY one series; and what each script's figures become on the other reanalysis.

DATA. `tools/in_silico/data/station_cherkasy/` (queries, units and ceilings — its README):
  · GSOD `33487099999`, 1991 … 1998 — `WDSP` (mean of the day's reports, with their count) and `MXSPD` (the highest
    sustained wind among those reports), both in knots; the reports themselves are whole metres per second
    (control 2), so every station threshold is a threshold on an INTEGER;
  · MERRA-2 daily `WS10M` · `WS10M_MAX` (NASA POWER), 1991–2020, UTC days;
  · MERRA-2 hourly `WS10M` (NASA POWER), 2001–2020, UTC.
ERA5 is the tree's hourly file (`data/era5_cherkasy/hourly_1991_2020.csv.gz`, km/h, the file's clock is UTC+3).
The thresholds are not typed here: the Beaufort anchors are read from `62`'s cache and the campaign's Beaufort-5
threshold from `98`'s.

METHOD. Days are paired by UTC date on the days EVERY reading carries; nothing is interpolated or filled.
  A. THE DAILY MEAN (the quantity `62` counts): each series' mean and the share of days whose mean reaches each
     Beaufort anchor, on the same days.
  B. THE DAILY MAXIMUM (a day can hold a Beaufort-5 hour only if its maximum reaches it — the quantity behind `98`'s
     hours): the station's `MXSPD` against ERA5's maximum over the 24 hourly instants, ERA5's maximum over the eight
     synoptic instants 00…21 UTC (nearer the station's reporting schedule; it does NOT equalise the support — a
     point's short mean against an instant of a grid-cell average) and MERRA-2's maximum of 24 hourly means. Days at
     the threshold are counted in TWO readings, because the station reports whole m/s: «reported 8 or more» against
     the reanalysis at 8.0 and at 7.5 (the value a report of 8 rounds from); and the station's own count is printed
     one whole m/s either side of the threshold. Three further readings keep LEVEL and RANKING apart: the spread of
     each series (coefficient of variation of the daily mean, maximum over mean); each reanalysis' maximum rescaled
     to the station's mean; and, of each reanalysis' own N highest daily maxima (N = the station's count of
     threshold days, with the ties at the N-th value), how many are station threshold days — a count no level enters.
     reanalysis − station is conditioned three ways, because a gap measured on days CHOSEN by one series is pulled
     toward that series' extremes: (1) station at or above the threshold; (2) reanalysis at or above it; (3) no
     condition — the upper quantiles of each series on the same days. (1) and (2) are two ENDS, not parts of one gap.
  C. HOURS at Beaufort 5 over the campaign's seasons 1 December … 30 April, 2001/02 … 2019/20, from the two hourly
     series — the form `98`'s stop rule counts — with the hours both series flag.
  D. `62`'s exceedance shares recomputed on ERA5's daily mean and on MERRA-2's over the same 30 years.

CONTROLS — each can fail:
  1. Pairing. The correlation of the station's daily mean with each reanalysis' daily mean at lag 0 exceeds lag −1 and
     lag +1. CAN catch: a one-day shift in any file. CANNOT: a unit error (correlation ignores scale).
  2. Units of the station file. Every `MXSPD` is a whole number of m/s when read as knots, inside 0.08 kn of its
     print (the archive's own conversion is not exactly 1852/3600 — the worst miss is in the cache), and no day's mean
     exceeds its maximum by more than the print's rounding. CAN catch: a «metric» response (the wind arrives in m/s
     and the grid of knots disappears), mph, the two columns swapped. CANNOT: a wrong report in the archive.
  3. MERRA-2's files agree: the daily mean and maximum equal the mean and the maximum of the hourly field over the
     UTC day; and the file `62` reads — whose header names its time standard as LST, not UTC — equals the mean of the
     same hourly field over days of UTC + 2 h on every day they share. CAN catch: a different point or product under
     `62`'s file name, a one-day shift, a daily «maximum» that is not the maximum of the hourly means, `62`'s file
     read as UTC days (it then misses by up to 0.8 m/s — tried). CANNOT: an error in MERRA-2.
  4. This script's reading of the ERA5 file is `98`'s: January's Beaufort-5 hours per day and the Januaries without
     one, counted here on the file's clock days, equal `98`'s cache. CAN catch: a wrong column or unit (km/h left as
     m/s), a threshold read from the wrong cache key. CANNOT: an error both readings share.
  5. The direction of the clock offset. ERA5's hourly wind, read as UTC by SUBTRACTING the file's offset, correlates
     with MERRA-2's UTC series best within one hour (lags −3…+3). CAN catch: the offset applied with the wrong sign
     (the best lag inside the window is then −3, at its edge — tried). CANNOT: an error inside the tolerance, and
     the tolerance is lopsided: the peak already sits between lags −1 and 0 (instants against hourly means).

CEILINGS. One station, at a town, and not the forest plot: a synoptic anemometer against grid cells of 0.25° and
0.5° × 0.625°; part of any gap is siting and exposure, and nothing here says how either cell's open-terrain wind
relates to the wind under a canopy at anchor height — that transfer is what the field campaign measures. The
station's maximum is the highest of four to ten reports a day, each a short mean, so it sits at or below the day's
true maximum of such means; a reanalysis hour is an instant (ERA5) or an hourly mean (MERRA-2) of a grid-cell
average and holds no gust. The anemometer's height, type and averaging time are not read from a station manual. The
record is 1991–1998, dense only to 1994, and shares no year with the hours of part C. Nothing here CORRECTS a
reanalysis or re-plans the campaign: it says how far apart the two readings are, where the station fell, and what
each script's figures become on the other series.

Run: python scripts/123_wind_reanalyses_station.py   (seconds)
"""

import csv
import gzip
import io
import json
import statistics as st
import sys
import tarfile
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Two reanalyses of the 10 m wind against one synoptic station's daily mean and daily maximum wind, "
                  "with the gap conditioned on the station, on the reanalysis and on neither, and the strong-wind "
                  "hours of nineteen winter seasons read from both reanalyses.")

DATA_DIR = REPO_ROOT / "tools/in_silico/data/station_cherkasy"
ERA5_HOURLY = REPO_ROOT / "tools/in_silico/data/era5_cherkasy/hourly_1991_2020.csv.gz"
POWER_62 = REPO_ROOT / "tools/in_silico/data/nasa_power_cherkasy_ws10m_2015_2024.json"
CACHE_62 = CACHE_DIR / "mechanical" / "wind_duty_cycle.json"
CACHE_98 = CACHE_DIR / "mechanical" / "field_strain_campaign.json"
OUT = CACHE_DIR / "mechanical" / "wind_reanalyses_station.json"

KNOT_MS = 1852.0 / 3600.0
GSOD_MISSING = "999.9"
KNOT_GRID_TOL = 0.08                    # a whole m/s lands within this of the file's print in knots (control 2; measured worst 0.065)
MEAN_OVER_MAX_TOL = 0.05                # m/s — the day's mean may exceed its maximum by the print's rounding only (control 2)
SYNOPTIC_UTC = (0, 3, 6, 9, 12, 15, 18, 21)
DENSE_REPORTS = 7                       # the «dense» subset: days with at least this many reports (of the usual eight)
ROUNDING_HALF = 0.5                     # a report of N m/s rounds from [N − 0.5, N + 0.5)
QUANTILES = (0.90, 0.95, 0.99)
MIN_BIN = 5                             # a conditioned bin is reported as a mean only with this many days
CAMPAIGN_MONTHS = (12, 1, 2, 3, 4)      # 1 December … 30 April — the campaign's season, `98` «capped at 01.05»
HOURS_SEASONS = (2001, 2019)            # seasons 2001/02 … 2019/20: whole campaign seasons both hourly series carry
LST_SHIFT_H = 2                         # `62`'s file is in POWER's «LST»: at this longitude its day is the UTC day shifted by 2 h (control 3)
MERRA2_DAILY_TOL = 0.011                # the daily mean and maximum against the hourly field (measured: exact to the print)
OFFSET_LAGS = (-3, -2, -1, 0, 1, 2, 3)  # control 5


def thresholds() -> tuple[list, float]:
    """The Beaufort anchors of `62` and the Beaufort-5 threshold of `98`, read from their caches (never typed here)."""
    anchors = [r["threshold_ms"] for r in json.loads(CACHE_62.read_text())["beaufort_exceedance"]]
    b5 = json.loads(CACHE_98.read_text())["thresholds_ms"]["beaufort_5"]
    if b5 not in anchors:
        raise AssertionError(f"`98`'s Beaufort-5 threshold {b5} is not among `62`'s anchors {anchors}")
    return anchors, b5


def load_gsod() -> dict:
    """date → {mean m/s, reports, max m/s (an integer)}; and control 2's worst distance from the knot grid."""
    days, worst, above, worst_above = {}, 0.0, 0, 0.0
    with gzip.open(DATA_DIR / "gsod_33487099999_1991_1998.csv.gz", "rt", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            wdsp, mx = r["WDSP"].strip(), r["MXSPD"].strip()
            if GSOD_MISSING in (wdsp, mx):
                continue
            whole = round(float(mx) * KNOT_MS)                      # knots → m/s, to the whole number the station reported
            miss = abs(float(mx) - whole / KNOT_MS)
            worst = max(worst, miss)
            if miss > KNOT_GRID_TOL:
                raise AssertionError(f"control 2: MXSPD {mx} kn on {r['DATE']} is not a whole number of m/s")
            mean = float(wdsp) * KNOT_MS
            if mean > whole + MEAN_OVER_MAX_TOL:
                raise AssertionError(f"control 2: the day's mean {mean:.2f} m/s exceeds its maximum {whole} on {r['DATE']}")
            if mean > whole:
                above, worst_above = above + 1, max(worst_above, mean - whole)
            days[r["DATE"]] = {"mean": mean, "reports": int(r["WDSP_ATTRIBUTES"]), "max": float(whole)}
    return {"days": days, "worst_knot_grid_miss": worst, "days_mean_above_max": above, "worst_mean_above_max_ms": worst_above}


def load_merra2_daily() -> tuple[dict, dict]:
    with gzip.open(DATA_DIR / "power_merra2_daily_1991_2020.csv.gz", "rt", encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    mean, peak = {}, {}
    for r in csv.DictReader(lines[lines.index("-END HEADER-") + 1:]):
        day = f"{int(r['YEAR']):04d}-{int(r['MO']):02d}-{int(r['DY']):02d}"
        a, b = float(r["WS10M"]), float(r["WS10M_MAX"])
        if a <= -999 or b <= -999:
            raise ValueError(f"MERRA-2 daily carries its missing value on {day}")
        mean[day], peak[day] = a, b
    return mean, peak


def load_merra2_hourly() -> dict:
    """UTC hour key «YYYY-MM-DDTHH» → WS10M, from the twenty yearly responses in the tarball."""
    out = {}
    with tarfile.open(DATA_DIR / "power_merra2_hourly_wind_2001_2020.csv.tar.gz", "r:gz") as tar:
        for member in sorted(tar.getnames()):
            lines = io.TextIOWrapper(tar.extractfile(member), encoding="utf-8").read().splitlines()
            for r in csv.DictReader(lines[lines.index("-END HEADER-") + 1:]):
                v = float(r["WS10M"])
                key = f"{int(r['YEAR']):04d}-{int(r['MO']):02d}-{int(r['DY']):02d}T{int(r['HR']):02d}"
                if v <= -999:
                    raise ValueError(f"MERRA-2 hourly carries its missing value at {key}")
                out[key] = v
    return out


def load_era5() -> dict:
    """The hourly wind in m/s: by UTC hour key, and by the file's own clock day (control 4 reads it as `98` does)."""
    by_utc, by_clock_day = {}, {}
    with gzip.open(ERA5_HOURLY, "rt", encoding="utf-8") as fh:
        meta = next(csv.DictReader([fh.readline(), fh.readline()]))
        offset = timedelta(seconds=int(meta["utc_offset_seconds"]))
        fh.readline()
        rows = csv.reader(fh)
        head = next(rows)
        col = [i for i, h in enumerate(head) if h.startswith("wind_speed_10m")]
        if head[0] != "time" or len(col) != 1 or "km/h" not in head[col[0]]:
            raise ValueError(f"unexpected ERA5 header: {head}")
        for row in rows:
            v = float(row[col[0]]) / 3.6
            utc = datetime.fromisoformat(row[0]) - offset
            by_utc[utc.strftime("%Y-%m-%dT%H")] = v
            by_clock_day.setdefault(row[0][:10], []).append(v)
    return {"offset_s": int(offset.total_seconds()), "by_utc": by_utc, "by_clock_day": by_clock_day}


def daily_from_hourly(by_utc: dict) -> dict:
    """UTC day → mean, maximum of the 24 values and maximum of the eight synoptic ones; whole days only."""
    per = {}
    for key, v in by_utc.items():
        per.setdefault(key[:10], {})[int(key[11:13])] = v
    out = {}
    for day, hours in per.items():
        if len(hours) == 24:
            out[day] = {"mean": st.fmean(hours.values()), "max24": max(hours.values()),
                        "max_synoptic": max(hours[h] for h in SYNOPTIC_UTC)}
    return out


def pearson(a: list, b: list) -> float:
    ma, mb = st.fmean(a), st.fmean(b)
    num = sum((x - ma) * (y - mb) for x, y in zip(a, b, strict=True))
    return num / (sum((x - ma) ** 2 for x in a) * sum((y - mb) ** 2 for y in b)) ** 0.5


def shifted(day: str, lag: int) -> str:
    return (date.fromisoformat(day) + timedelta(days=lag)).isoformat()


def control_pairing(station: dict, ref: dict, what: str) -> dict:
    out = {}
    for lag in (-1, 0, 1):
        days = [d for d in station if shifted(d, lag) in ref]
        out[str(lag)] = pearson([station[d] for d in days], [ref[shifted(d, lag)] for d in days])
    if not (out["0"] > out["-1"] and out["0"] > out["1"]):
        raise AssertionError(f"control 1: {what} pairs best at a lag other than 0: {out}")
    return out


def control_merra2_files(daily_mean: dict, daily_max: dict, hourly: dict) -> dict:
    hourly_daily = daily_from_hourly(hourly)
    days = sorted(set(daily_mean) & set(hourly_daily))
    worst_mean = max(abs(daily_mean[d] - hourly_daily[d]["mean"]) for d in days)
    worst_max = max(abs(daily_max[d] - hourly_daily[d]["max24"]) for d in days)
    file62 = json.loads(POWER_62.read_text())
    standard, ws62 = file62["header"]["time_standard"], file62["properties"]["parameter"]["WS10M"]
    lst = {}
    for key, v in hourly.items():                       # the hourly field regrouped into days of UTC + LST_SHIFT_H
        t = datetime.strptime(key, "%Y-%m-%dT%H") + timedelta(hours=LST_SHIFT_H)
        lst.setdefault(t.strftime("%Y%m%d"), []).append(v)
    shared = sorted(d for d, values in lst.items() if len(values) == 24 and d in ws62)
    worst62 = max(abs(st.fmean(lst[d]) - ws62[d]) for d in shared)
    worst62_as_utc = max(abs(daily_mean[f"{d[:4]}-{d[4:6]}-{d[6:]}"] - ws62[d]) for d in shared)
    if standard != "LST" or max(worst62, worst_mean, worst_max) > MERRA2_DAILY_TOL:
        raise AssertionError(f"control 3: MERRA-2's files disagree — `62`'s file ({standard}) against the hourly field on its own days "
                             f"{worst62:.3f}, daily mean against hourly {worst_mean:.3f}, daily maximum against hourly {worst_max:.3f} m/s")
    return {"days_against_hourly": len(days), "worst_daily_mean_against_hourly_ms": worst_mean,
            "worst_daily_max_against_hourly_ms": worst_max, "tolerance_ms": MERRA2_DAILY_TOL,
            "file_of_62": {"time_standard": standard, "day_is_utc_plus_h": LST_SHIFT_H, "days_shared": len(shared),
                           "first_day": shared[0], "last_day": shared[-1], "worst_difference_on_its_own_days_ms": worst62,
                           "worst_difference_if_read_as_utc_days_ms": worst62_as_utc}}


def control_reading_is_98s(era5_clock: dict, b5: float) -> dict:
    """Control 4: January's Beaufort-5 hours per day and the Januaries without one, on the file's clock days."""
    theirs = json.loads(CACHE_98.read_text())["by_month"]["01"]
    days = [d for d in era5_clock if d[5:7] == "01"]
    hours = sum(v >= b5 for d in days for v in era5_clock[d])
    per_year = Counter()
    for d in days:
        per_year[d[:4]] += sum(v >= b5 for v in era5_clock[d])
    mine = {"hours_per_day": round(hours / len(days), 3), "years_without": sum(1 for y in {d[:4] for d in days} if per_year[y] == 0)}
    if mine["hours_per_day"] != theirs["hours_per_day"]["beaufort_5"] or mine["years_without"] != theirs["years_without_beaufort_5"]:
        raise AssertionError(f"control 4: this script reads January as {mine}, `98` as {theirs['hours_per_day']['beaufort_5']} "
                             f"h/day and {theirs['years_without_beaufort_5']} years without")
    return {"january_beaufort_5_hours_per_day": mine["hours_per_day"], "januaries_without_a_beaufort_5_hour": mine["years_without"],
            "januaries": len({d[:4] for d in days})}


def control_offset_direction(era5_utc: dict, merra2_utc: dict) -> dict:
    keys = sorted(set(era5_utc) & set(merra2_utc))
    a, b = [era5_utc[k] for k in keys], [merra2_utc[k] for k in keys]
    by_lag = {}
    for lag in OFFSET_LAGS:                     # lag L pairs ERA5 at hour i with MERRA-2 at hour i + L
        x = a[max(-lag, 0): len(a) - max(lag, 0)]
        y = b[max(lag, 0): len(b) - max(-lag, 0)]
        by_lag[str(lag)] = pearson(x, y)
    best = max(by_lag, key=by_lag.get)
    if abs(int(best)) > 1:
        raise AssertionError(f"control 5: ERA5 read as UTC pairs best with MERRA-2 at lag {best} h — the offset's sign is suspect: {by_lag}")
    return {"hours": len(keys), "correlation_by_lag_h": by_lag, "best_lag_h": int(best)}


def quantile(values: list, q: float) -> float:
    s = sorted(values)
    pos = q * (len(s) - 1)
    lo = int(pos)
    return s[lo] + (s[min(lo + 1, len(s) - 1)] - s[lo]) * (pos - lo)


def gap(days: list, station: dict, ref: dict) -> dict:
    if len(days) < MIN_BIN:
        return {"days": len(days)}
    d = [ref[x] - station[x] for x in days]
    return {"days": len(days), "mean_ms": st.fmean(d), "median_ms": st.median(d)}


def compare(days: list, gsod: dict, means: dict, peaks: dict, anchors: list, b5: float) -> dict:
    """One set of paired station days: part A (daily mean) and part B (daily maximum)."""
    s_mean = {d: gsod[d]["mean"] for d in days}
    s_max = {d: gsod[d]["max"] for d in days}
    s_mean_of_means = st.fmean(s_mean.values())

    def cv(values) -> float:
        values = list(values)
        return st.pstdev(values) / st.fmean(values)

    out = {"paired_days": len(days), "first_day": days[0], "last_day": days[-1],
           "daily_mean": {"station": {"mean_ms": s_mean_of_means, "coefficient_of_variation": cv(s_mean.values()),
                                      "share_at_or_above": {str(t): sum(v >= t for v in s_mean.values()) / len(days) for t in anchors}},
                          "reanalyses": {}},
           "daily_max": {"station": {"mean_ms": st.fmean(s_max.values()), "max_over_mean": st.fmean(s_max.values()) / s_mean_of_means,
                                     "days_reported_at_or_above": {str(t): sum(v >= t for v in s_max.values()) for t in (b5 - 1.0, b5, b5 + 1.0)},
                                     "quantiles_ms": {str(q): quantile(list(s_max.values()), q) for q in QUANTILES},
                                     "highest_ms": max(s_max.values())},
                         "reanalyses": {}}}
    for name, ref in means.items():
        out["daily_mean"]["reanalyses"][name] = {
            "mean_ms": st.fmean(ref[d] for d in days), "ratio_of_means_to_station": st.fmean(ref[d] for d in days) / s_mean_of_means,
            "coefficient_of_variation": cv(ref[d] for d in days),
            "all_days": gap(days, s_mean, ref),
            "share_at_or_above": {str(t): sum(ref[d] >= t for d in days) / len(days) for t in anchors},
            "pairing_correlation_by_lag": control_pairing(s_mean, ref, name)}
    a, b = list(means)
    out["daily_mean"]["the_two_reanalyses"] = {"pair": [a, b], "correlation": pearson([means[a][d] for d in days], [means[b][d] for d in days]),
                                               "ratio_of_means": st.fmean(means[b][d] for d in days) / st.fmean(means[a][d] for d in days)}
    windy = [d for d in days if s_max[d] >= b5]
    own_mean = {"era5": st.fmean(means["era5_utc_day"][d] for d in days), "merra2": st.fmean(means["merra2_utc_day"][d] for d in days)}
    for name, ref in peaks.items():
        mean_of_own_series = own_mean["era5" if name.startswith("era5") else "merra2"]
        factor = s_mean_of_means / mean_of_own_series
        nth = sorted((ref[d] for d in days), reverse=True)[len(windy) - 1]
        top = [d for d in days if ref[d] >= nth]
        row = {"mean_ms": st.fmean(ref[d] for d in days), "max_over_mean": st.fmean(ref[d] for d in days) / mean_of_own_series,
               "all_days": gap(days, s_max, ref),
               "quantiles_ms": {str(q): quantile([ref[d] for d in days], q) for q in QUANTILES}, "highest_ms": max(ref[d] for d in days),
               "rescaled_to_station_mean": {"factor": factor, "days_at_or_above": sum(ref[d] * factor >= b5 for d in days)},
               "own_highest_days": {"n_station_threshold_days": len(windy), "nth_value_ms": nth, "days_at_or_above_nth": len(top),
                                    "station_threshold_days_among": sum(s_max[d] >= b5 for d in top)},
               "at_threshold": {}}
        for label, thr in (("as_printed", b5), ("rounding_consistent", b5 - ROUNDING_HALF)):
            mine = [d for d in days if ref[d] >= thr]
            both = [d for d in mine if s_max[d] >= b5]
            row["at_threshold"][label] = {
                "reanalysis_threshold_ms": thr, "days_reanalysis": len(mine), "days_both": len(both),
                "days_station_only": len(windy) - len(both), "days_reanalysis_only": len(mine) - len(both),
                "station_chosen": gap(windy, s_max, ref), "reanalysis_chosen": gap(mine, s_max, ref)}
        out["daily_max"]["reanalyses"][name] = row
    return out


def campaign_season(key: str) -> int | None:
    """The season a UTC hour or day belongs to (the year its December is in), or None outside 1 December … 30 April."""
    month = int(key[5:7])
    if month not in CAMPAIGN_MONTHS:
        return None
    return int(key[:4]) if month == 12 else int(key[:4]) - 1


def hours_block(era5_utc: dict, merra2_utc: dict, b5: float) -> dict:
    """Part C: Beaufort-5 hours of each hourly series over the campaign's seasons, and the hours both flag."""
    keys = [k for k in sorted(set(era5_utc) & set(merra2_utc))
            if (s := campaign_season(k)) is not None and HOURS_SEASONS[0] <= s <= HOURS_SEASONS[1]]
    per = {"era5": Counter(), "merra2": Counter(), "both": Counter()}
    days = {"era5": set(), "merra2": set()}
    seasons = sorted({campaign_season(k) for k in keys})
    for k in keys:
        s, e, m = campaign_season(k), era5_utc[k] >= b5, merra2_utc[k] >= b5
        per["era5"][s] += e
        per["merra2"][s] += m
        per["both"][s] += e and m
        if e:
            days["era5"].add(k[:10])
        if m:
            days["merra2"].add(k[:10])
    jan = {name: Counter() for name in ("era5", "merra2")}
    for k in keys:
        if k[5:7] == "01":
            jan["era5"][k[:4]] += era5_utc[k] >= b5
            jan["merra2"][k[:4]] += merra2_utc[k] >= b5

    def row(name: str) -> dict:
        v = [per[name][s] for s in seasons]
        return {"per_season": v, "median": st.median(v), "least": min(v), "most": max(v), "total": sum(v)}

    return {"threshold_ms": b5, "seasons": [f"{s}/{(s + 1) % 100:02d}" for s in seasons], "hours_per_season": len(keys) / len(seasons),
            "hours": len(keys), "era5": row("era5"), "merra2": row("merra2"), "both_total": sum(per["both"].values()),
            "mean_speed_all_hours_ms": {"era5": st.fmean(era5_utc[k] for k in keys), "merra2": st.fmean(merra2_utc[k] for k in keys)},
            "days_with_such_an_hour": {name: len(d) for name, d in days.items()},
            "januaries": len(jan["era5"]), "januaries_without_such_an_hour": {name: sum(1 for n in c.values() if n == 0) for name, c in jan.items()}}


def main() -> int:
    banner("HW.43 — two reanalyses of the wind against the Cherkasy station")
    anchors, b5 = thresholds()
    gsod = load_gsod()
    m2_mean, m2_max = load_merra2_daily()
    m2_hourly = load_merra2_hourly()
    era5 = load_era5()
    e_daily = daily_from_hourly(era5["by_utc"])
    means = {"era5_utc_day": {d: v["mean"] for d, v in e_daily.items()}, "merra2_utc_day": m2_mean}
    peaks = {"era5_max_of_24_instants": {d: v["max24"] for d, v in e_daily.items()},
             "era5_max_of_8_synoptic_instants": {d: v["max_synoptic"] for d, v in e_daily.items()},
             "merra2_max_of_24_hourly_means": m2_max}
    station = gsod["days"]
    paired = sorted(d for d in station if all(d in r for r in (*means.values(), *peaks.values())))
    subsets = {"all_days": paired,
               "dense_days": [d for d in paired if station[d]["reports"] >= DENSE_REPORTS],
               "campaign_months": [d for d in paired if int(d[5:7]) in CAMPAIGN_MONTHS]}
    by_subset = {name: compare(days, station, means, peaks, anchors, b5) for name, days in subsets.items()}

    common = sorted(set(means["era5_utc_day"]) & set(m2_mean))
    thirty = {"days": len(common), "first_day": common[0], "last_day": common[-1],
              "share_of_days_with_mean_at_or_above": {name: {str(t): sum(ref[d] >= t for d in common) / len(common) for t in anchors}
                                                      for name, ref in means.items()},
              "mean_ms": {name: st.fmean(ref[d] for d in common) for name, ref in means.items()}}
    hours = hours_block(era5["by_utc"], m2_hourly, b5)
    controls = {"station_units": {"worst_knot_grid_miss_kn": gsod["worst_knot_grid_miss"], "tolerance_kn": KNOT_GRID_TOL,
                                  "days_mean_above_max": gsod["days_mean_above_max"],
                                  "worst_mean_above_max_ms": gsod["worst_mean_above_max_ms"], "mean_over_max_tolerance_ms": MEAN_OVER_MAX_TOL},
                "merra2_files_agree": control_merra2_files(m2_mean, m2_max, m2_hourly),
                "era5_reading_is_98s": control_reading_is_98s(era5["by_clock_day"], b5),
                "era5_utc_offset_direction": control_offset_direction(era5["by_utc"], m2_hourly)}

    a = by_subset["all_days"]
    am, ax = a["daily_mean"], a["daily_max"]
    e24 = ax["reanalyses"]["era5_max_of_24_instants"]["at_threshold"]
    m24 = ax["reanalyses"]["merra2_max_of_24_hourly_means"]["at_threshold"]
    verdict = (f"On the {a['paired_days']} paired station days of {a['first_day'][:4]}–{a['last_day'][:4]} the station's daily mean wind "
               f"is {am['station']['mean_ms']:.2f} m/s, ERA5's {am['reanalyses']['era5_utc_day']['mean_ms']:.2f} and MERRA-2's "
               f"{am['reanalyses']['merra2_utc_day']['mean_ms']:.2f}. The station reported {b5:g} m/s or more on "
               f"{ax['station']['days_reported_at_or_above'][str(b5)]} of those days; ERA5's hourly maximum reaches {b5:g} m/s on "
               f"{e24['as_printed']['days_reanalysis']} days, {e24['as_printed']['days_both']} of them among the station's "
               f"({e24['rounding_consistent']['days_reanalysis']} and {e24['rounding_consistent']['days_both']} at {b5 - ROUNDING_HALF:g}), "
               f"MERRA-2's on {m24['as_printed']['days_reanalysis']}, {m24['as_printed']['days_both']} among the station's "
               f"({m24['rounding_consistent']['days_reanalysis']} and {m24['rounding_consistent']['days_both']}). "
               f"Over the campaign seasons {hours['seasons'][0]}…{hours['seasons'][-1]} the hours at {b5:g} m/s or more are a median "
               f"{hours['era5']['median']:g} a season in ERA5 and {hours['merra2']['median']:g} in MERRA-2.")

    result = {
        "script": "123_wind_reanalyses_station.py",
        "question": "which reanalysis of the 10 m wind the station sits nearer to, on the daily mean `62` counts and on the daily "
                    "maximum behind `98`'s Beaufort-5 hours, and what each script's figures become on the other series",
        "model": {"beaufort_anchors_ms_from_62": anchors, "beaufort_5_ms_from_98": b5, "knot_ms": KNOT_MS,
                  "station_reports_whole_ms": True, "rounding_half_ms": ROUNDING_HALF, "synoptic_utc_hours": list(SYNOPTIC_UTC),
                  "dense_days_min_reports": DENSE_REPORTS, "quantiles": list(QUANTILES), "min_days_for_a_mean": MIN_BIN,
                  "campaign_months": list(CAMPAIGN_MONTHS), "era5_clock_offset_s": era5["offset_s"], "gap_sign": "reanalysis minus station"},
        "inputs": {"gsod_days_with_wind": len(station), "reports_per_day": dict(sorted(Counter(v["reports"] for v in station.values()).items())),
                   "paired_days_by_year": dict(sorted(Counter(d[:4] for d in paired).items())),
                   "merra2_daily_days": len(m2_mean), "merra2_hourly_hours": len(m2_hourly), "era5_hours": len(era5["by_utc"]),
                   "era5_whole_utc_days": len(e_daily)},
        "controls": controls,
        "station_days": by_subset,
        "thirty_years_daily_mean": thirty,
        "campaign_season_hours": hours,
        "verdict": verdict,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(verdict)
    print(f"→ {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
