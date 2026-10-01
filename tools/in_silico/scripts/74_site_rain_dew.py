#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Site climate of the Cherkasy grid point, 1991–2020, for two open legs that each asked a number of the
climate and had only a route to it:

  (A) HW.25 rain/dew stand (`docs/protocols/anchor/gdl_rain_dew_stand.md` §7 pp. 3–4): how often it rains,
      how hard, and how many nights and hours carry dew — an ORIENTATION for whoever builds the stand,
      never a choice of its regime (the `[вибір стенда]` cells stay open).
  (B) HW.6 install season (`01_04 §3.5`): the dates at which the published xylogenesis thresholds for
      conifers / Scots pine are crossed at this grid point — an INPUT with bounds, never a window verdict.

SOURCES — the data and the thresholds are separate claims with separate owners:
  • Climate — ERA5 via the Open-Meteo archive, the same grid point and model pin as the two older files in
    `data/era5_cherkasy/` (queries, dates and ceilings in its README). Inputs: daily precipitation sum and
    hours; hourly dew point, relative humidity and soil temperature at 0–7 and 7–28 cm; the committed hourly
    2 m air temperature; the committed daily mean 2 m air temperature.
  • Soil threshold — Belokopytova et al. 2026, Plants 15:1933, DOI 10.3390/plants15131933 (Scots pine,
    southern limit of the range in Siberia, seven years): soil at 20 cm ≥ 3.5 °C preceded cambial onset by
    9.6 ± 1.1 days. ERA5's 7–28 cm layer is the one that contains 20 cm — a layer mean, not a depth.
  • Air thresholds — Rossi et al. 2008, Global Ecol. Biogeogr. 17:696, DOI 10.1111/j.1466-8238.2008.00417.x
    (seven conifer species, ten European and Canadian cold-climate sites): onset and end of xylogenesis
    converge at a daily MEAN air temperature of about 8–9 °C. Both ends of that range are swept.

OPERATIONALISATIONS THAT ARE OURS (each one moves a number; none is the source's):
  • a wet day is ≥ 1.0 mm (the common climatological convention; ≥ 0.1 mm is reported beside it, because
    ERA5 drizzles), and intensity on a wet day is sum / precipitation_hours — an HOURLY MEAN of that day;
  • a dew hour is a NIGHT hour (20:00–06:59 UTC+3 — Open-Meteo's fixed offset, no DST; in winter that is
    civil 19:00–05:59) with T2m − Td ≤ 1 °C or RH ≥ 95 %, split by T2m > 0 °C (liquid — what the stand
    reproduces) ⊥ ≤ 0 °C (hoar frost — outside the stand's base); a dew night is a night with at least one
    dew hour, and the night belongs to the date of its evening;
  • a threshold is «crossed» in spring SUSTAINEDLY: on the first day of the first run of ≥ RUN_DAYS
    consecutive days at or above it that starts after the last return below it lasting ≥ RUN_DAYS, both
    searched up to SEASON_ANCHOR_DOY (≈ 1 July); a shorter dip does not break the season. «Left» in autumn
    is the mirror: the last day of the last such run that ends before the first return below lasting
    ≥ RUN_DAYS after the anchor. Counting from 1 January / to 31 December instead takes a winter thaw for
    spring and a warm wave after weeks of cold for the end of the season.

CEILINGS — what these numbers are NOT (the same text rides into the cache):
  • a ~0.25° reanalysis cell, not the plot: convective downpours are smoothed, so the intensity
    percentiles are LOW; drizzle is over-produced, so the ≥ 0.1 mm wet-day fraction is HIGH;
  • air at 2 m, not the coupon face or the bark: dew on a radiating surface forms on more nights than
    the air criterion admits;
  • open-field soil, not forest soil under a canopy and litter, which warms later in spring;
  • the thresholds come from other sites and climates (Siberian southern limit; Alpine/boreal/Canadian
    sites), and they are thresholds of XYLOGENESIS (cambium), not of resin pressure — the subject of 01_04
    §3.5 is resin, and no primary in the tree ties its seasonality to a temperature;
  • the crossing dates are as sharp as the rule that makes them, and the rule is ours (RUN_DAYS, the
    anchor, «sustained»): a return below shorter than RUN_DAYS is absorbed into the season, a longer one
    moves the date. The sources dated onset and end from observed cambium, not from a temperature series,
    so another defensible rule moves these dates — the P10 and the earliest years most, being made of the
    early thaws and false starts the rule has to judge;
  • the clock is a fixed UTC+3 (Open-Meteo applies one offset to the whole series, no DST — the CSV
    headers say 10800 s, and the hours run through the DST-change days with no gap and no repeat): the
    night window 20:00–06:59 UTC+3 is civil 19:00–05:59 in winter, and the daily rain sums and soil means
    are cut at UTC+3 midnight (the committed daily air-mean file kept no header, so its day boundary is
    not verified).

    ~/miniforge3/envs/silken_md/bin/python tools/in_silico/scripts/74_site_rain_dew.py
"""
from __future__ import annotations

import datetime as dt
import gzip
import io
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

DATA = REPO_ROOT / "tools/in_silico/data/era5_cherkasy"
OUT_DIR = CACHE_DIR / "thermal"

WET_DAY_MM = 1.0
WET_DAY_MM_LOOSE = 0.1
DEW_SPREAD_C = 1.0
DEW_RH_PCT = 95.0
# 20:00–06:59 UTC+3 (Open-Meteo's fixed offset, no DST; in winter civil 19:00–05:59) — stamps NOT converted
NIGHT_HOURS = set(range(20, 24)) | set(range(0, 7))
RUN_DAYS = 5
SEASON_ANCHOR_DOY = 182      # ≈ 1 July: spring is searched before it, autumn after it
SOIL_ONSET_C = 3.5            # Belokopytova et al. 2026, soil at 20 cm
SOIL_LEAD_DAYS = 9.6          # same source: soil date precedes cambial onset by 9.6 ± 1.1 d
AIR_MEAN_THRESHOLDS_C = (8.0, 9.0)   # Rossi et al. 2008, daily mean, onset ≈ end


def _csv_block(lines, names, dtypes):
    body = [ln for ln in lines if ln[:2] in ("19", "20")]
    return np.genfromtxt(io.StringIO("".join(body)), delimiter=",", encoding="utf-8",
                         dtype=list(zip(names, dtypes, strict=True)))


def load():
    with open(DATA / "daily_precip_1991_2020.csv", encoding="utf-8") as fh:
        pr = _csv_block(fh, ("date", "p_mm", "p_h"), ("U10", float, float))
    with gzip.open(DATA / "hourly_dew_rh_soil_1991_2020.csv.gz", "rt", encoding="utf-8") as fh:
        hd = _csv_block(fh, ("time", "td", "rh", "s07", "s728"), ("U16", float, float, float, float))
    with gzip.open(DATA / "hourly_1991_2020.csv.gz", "rt", encoding="utf-8") as fh:
        ht = _csv_block(fh, ("time", "t", "dni", "dif", "u10"), ("U16", float, float, float, float))
    with open(DATA / "daily_t2m_mean_1991_2020.csv", encoding="utf-8") as fh:
        ta = _csv_block(fh, ("date", "t"), ("U10", float))
    if not np.array_equal(hd["time"], ht["time"]):
        raise RuntimeError("hourly files are not on the same clock — the join would pair different hours")
    return pr, hd, ht, ta


def pct(a, q):
    return round(float(np.percentile(a, q)), 2)


def rain(pr):
    p, h = pr["p_mm"], pr["p_h"]
    n_years = len({d[:4] for d in pr["date"]})
    out = {}
    for label, thr in (("wet_day_ge_1mm", WET_DAY_MM), ("wet_day_ge_0p1mm", WET_DAY_MM_LOOSE)):
        wet = p >= thr
        out[label] = {"threshold_mm": thr, "fraction_of_days": round(float(wet.mean()), 3),
                      "days_per_year": round(float(wet.sum()) / n_years, 1)}
    wet = (p >= WET_DAY_MM) & (h > 0)
    inten = p[wet] / h[wet]
    out["intensity_on_wet_days_mm_per_h"] = {
        "definition": "daily sum / precipitation_hours on days with ≥ 1.0 mm — an hourly MEAN of that day",
        "median": pct(inten, 50), "p90": pct(inten, 90), "max": round(float(inten.max()), 2), "n_days": int(wet.sum())}
    out["daily_sum_on_wet_days_mm"] = {"median": pct(p[p >= WET_DAY_MM], 50), "p90": pct(p[p >= WET_DAY_MM], 90),
                                       "max": round(float(p.max()), 1)}
    out["hours_on_wet_days"] = {"median": pct(h[wet], 50), "p90": pct(h[wet], 90)}
    out["annual_sum_mm_mean"] = round(float(p.sum()) / n_years, 0)
    return out


def dew(hd, ht):
    t, td, rh = ht["t"], hd["td"], hd["rh"]
    hour = np.array([int(s[11:13]) for s in hd["time"]])
    date = np.array([dt.date.fromisoformat(s[:10]) for s in hd["time"]])
    night_key = np.array([d - dt.timedelta(days=1) if hr < 7 else d for d, hr in zip(date, hour, strict=True)])
    is_night = np.isin(hour, list(NIGHT_HOURS))
    cond = is_night & (((t - td) <= DEW_SPREAD_C) | (rh >= DEW_RH_PCT))
    n_years = len({d.year for d in date})
    out = {}
    for label, phase in (("liquid_t2m_above_0", t > 0), ("frost_t2m_le_0", t <= 0)):
        c = cond & phase
        per_night = {}
        for k in night_key[c]:
            per_night[k] = per_night.get(k, 0) + 1
        hours = np.array(list(per_night.values()))
        all_nights = len(set(night_key[is_night]))
        out[label] = {"nights_per_year": round(len(per_night) / n_years, 1),
                      "fraction_of_nights": round(len(per_night) / all_nights, 3),
                      "hours_per_dew_night_median": pct(hours, 50), "hours_per_dew_night_p90": pct(hours, 90),
                      "hours_per_year": round(float(c.sum()) / n_years, 0)}
    out["criterion"] = ("night hour 20:00–06:59 UTC+3 (Open-Meteo's fixed offset, no DST; in winter civil "
                        f"19:00–05:59) with T2m − Td ≤ {DEW_SPREAD_C} °C or RH ≥ {DEW_RH_PCT} %; "
                        "a night belongs to the date of its evening")
    return out


def _runs(mask):
    """(start, end) index pairs of runs of True at least RUN_DAYS long."""
    out, i, n = [], 0, len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j < n and mask[j]:
                j += 1
            if j - i >= RUN_DAYS:
                out.append((i, j - 1))
            i = j
        else:
            i += 1
    return out


def crossings(dates, values, thr):
    """Per year: the SUSTAINED spring crossing and autumn leaving around SEASON_ANCHOR_DOY.

    Spring = the first day of the first run ≥ thr that starts after the last ≥ RUN_DAYS return below thr
    starting by the anchor; autumn = its mirror, the last day of the last run ≥ thr that ends before the
    first ≥ RUN_DAYS return below ending after the anchor. A year with no such crossing on either side
    is skipped, which `n_years` shows."""
    rows = {}
    anchor = SEASON_ANCHOR_DOY - 1                       # index of the anchor day in a whole year
    for y in sorted({d.year for d in dates}):
        idx = [i for i, d in enumerate(dates) if d.year == y]
        if len(idx) < 365 or dates[idx[0]].timetuple().tm_yday != 1:
            raise RuntimeError(f"{y} is not a whole year — the anchor index would point at the wrong day")
        above = values[idx] >= thr
        warm, cold = _runs(above), _runs(~above)
        last_cold = max((s for s, _e in cold if s <= anchor), default=-1)
        first_cold = min((e for _s, e in cold if e >= anchor), default=len(idx))
        spring = next((s for s, _e in warm if last_cold < s <= anchor), None)
        autumn = max((e for _s, e in warm if anchor <= e < first_cold), default=None)
        if spring is None or autumn is None:
            continue
        rows[y] = (dates[idx[spring]].timetuple().tm_yday, dates[idx[autumn]].timetuple().tm_yday)
    spring = np.array([v[0] for v in rows.values()])
    autumn = np.array([v[1] for v in rows.values()])
    return spring, autumn, len(rows)


def doy_summary(arr):
    def mmdd(doy):
        return (dt.date(2001, 1, 1) + dt.timedelta(days=round(float(doy)) - 1)).strftime("%m-%d")
    return {"doy_p10": pct(arr, 10), "doy_median": pct(arr, 50), "doy_p90": pct(arr, 90),
            "date_p10": mmdd(np.percentile(arr, 10)), "date_median": mmdd(np.median(arr)),
            "date_p90": mmdd(np.percentile(arr, 90)), "earliest": mmdd(arr.min()), "latest": mmdd(arr.max())}


def soil_and_air(hd, ta):
    day = np.array([s[:10] for s in hd["time"]])
    uniq, inv = np.unique(day, return_inverse=True)
    dates = np.array([dt.date.fromisoformat(s) for s in uniq])
    s728 = np.bincount(inv, weights=hd["s728"]) / np.bincount(inv)
    s07 = np.bincount(inv, weights=hd["s07"]) / np.bincount(inv)
    out = {}
    for layer, series in (("soil_7_28cm", s728), ("soil_0_7cm", s07)):
        spring, _autumn, n = crossings(dates, series, SOIL_ONSET_C)
        onset = spring + SOIL_LEAD_DAYS
        out[f"{layer}_ge_{SOIL_ONSET_C}C_spring"] = doy_summary(spring) | {"n_years": n}
        out[f"{layer}_implied_cambial_onset"] = doy_summary(onset) | {
            "rule": f"spring crossing + {SOIL_LEAD_DAYS} d (Belokopytova et al. 2026; their SE ± 1.1 d not swept)"}
    adates = np.array([dt.date.fromisoformat(s) for s in ta["date"]])
    for thr in AIR_MEAN_THRESHOLDS_C:
        spring, autumn, n = crossings(adates, ta["t"], thr)
        out[f"air_mean_ge_{thr:g}C"] = {"spring": doy_summary(spring), "autumn": doy_summary(autumn), "n_years": n}
    return out


def main() -> int:
    banner("HW.25 / HW.6 — Cherkasy site climate: rain, dew, xylogenesis-threshold dates (ERA5 1991–2020)")
    pr, hd, ht, ta = load()
    r, d, s = rain(pr), dew(hd, ht), soil_and_air(hd, ta)

    wet = r["wet_day_ge_1mm"]
    it = r["intensity_on_wet_days_mm_per_h"]
    liq = d["liquid_t2m_above_0"]
    rain_prose = (f"Days with ≥ 1 mm: {wet['fraction_of_days']:.0%} ({wet['days_per_year']} a year); on them the "
                  f"day's hourly-mean intensity has median {it['median']} and P90 {it['p90']} mm/h "
                  f"(max {it['max']}). ERA5 smooths downpours, so the percentiles are a LOWER bound on the "
                  f"intensity a coupon meets.")
    dew_prose = (f"Dew nights (air criterion, T2m > 0 °C): {liq['nights_per_year']} a year "
                 f"({liq['fraction_of_nights']:.0%} of nights), median {liq['hours_per_dew_night_median']} h and "
                 f"P90 {liq['hours_per_dew_night_p90']} h of dew-point hours per such night; air at 2 m, not "
                 f"the coupon face.")
    soil = s[f"soil_7_28cm_ge_{SOIL_ONSET_C}C_spring"]
    onset = s["soil_7_28cm_implied_cambial_onset"]
    a8, a9 = s["air_mean_ge_8C"], s["air_mean_ge_9C"]
    season_prose = (f"Soil 7–28 cm reaches {SOIL_ONSET_C} °C sustainedly (the first {RUN_DAYS}-day run after the "
                    f"last {RUN_DAYS}-day return below) at median {soil['date_median']} "
                    f"(P10–P90 {soil['date_p10']}–{soil['date_p90']}), implying cambial onset near "
                    f"{onset['date_median']} by the Siberian lead; daily mean air ≥ 8–9 °C sustainedly begins "
                    f"at median {a8['spring']['date_median']}–{a9['spring']['date_median']} and ends at "
                    f"{a9['autumn']['date_median']}–{a8['autumn']['date_median']}. These are xylogenesis "
                    f"thresholds from other sites, not resin pressure, and open-field soil warms earlier than "
                    f"forest soil.")
    for line in (rain_prose, dew_prose, season_prose):
        print("  " + line)

    out = {
        "question": "00_07 HW.25 (rain/dew stand §7 pp. 3–4) + HW.6 (install season, 01_04 §3.5): site climate inputs",
        "inputs": {
            "climate": "ERA5 via Open-Meteo archive, Cherkasy grid point 49.5N 32.0E, 1991-2020 (data/era5_cherkasy/README.md)",
            "soil_threshold": "Belokopytova et al. 2026, Plants 15:1933, doi:10.3390/plants15131933 — soil 20 cm ≥ 3.5 °C, lead 9.6 ± 1.1 d (Pinus sylvestris, Siberia)",
            "air_thresholds": "Rossi et al. 2008, Global Ecol. Biogeogr. 17:696, doi:10.1111/j.1466-8238.2008.00417.x — daily mean ≈ 8–9 °C at onset and end (7 conifer species)",
            "ours": {"wet_day_mm": WET_DAY_MM, "dew_spread_c": DEW_SPREAD_C, "dew_rh_pct": DEW_RH_PCT,
                     "night_hours": "20:00-06:59 UTC+3 (Open-Meteo's fixed offset, no DST; in winter civil 19:00-05:59)",
                     "run_days": RUN_DAYS, "season_anchor_doy": SEASON_ANCHOR_DOY,
                     "crossing": "sustained: spring = first day of the first run ≥ run_days after the last return "
                                 "below lasting ≥ run_days, searched to season_anchor_doy; autumn = the mirror"},
        },
        "rain": r,
        "dew": d,
        "season": s,
        "ceilings": [
            "a ~0.25° reanalysis cell: downpours smoothed (intensity percentiles LOW), drizzle over-produced (≥ 0.1 mm fraction HIGH)",
            "air at 2 m, not the coupon face or the bark: a radiating surface collects dew on more nights",
            "open-field soil, not forest soil under canopy and litter, which warms later in spring",
            "thresholds are of xylogenesis from other sites and climates, not of resin pressure (the subject of 01_04 §3.5)",
            "crossing dates are as sharp as our rule (run_days, the anchor, «sustained»): a shorter return below is absorbed, "
            "a longer one moves the date; the sources dated onset and end from observed cambium, not from a temperature "
            "series, so another defensible rule moves these dates — the P10 and the earliest years most",
            "the clock is a fixed UTC+3 (no DST): the night window 20:00–06:59 UTC+3 is civil 19:00–05:59 in winter, and "
            "daily rain sums and soil means are cut at UTC+3 midnight",
        ],
        "rain_prose": rain_prose,
        "dew_prose": dew_prose,
        "season_prose": season_prose,
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / "site_rain_dew.json"
    path.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"\n  wrote {path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
