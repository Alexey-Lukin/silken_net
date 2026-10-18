#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
98 — How long the field strain campaign of HW.43 must run, and how many trips its batteries cost, from the 30-year
hourly ERA5 wind of the site cell (the instrument sheet docs/protocols/anchor/field_strain_sensor_sheet.md, its §3).

THE QUESTION. The field leg (00_07 HW.43; ⚖️ delegated 2026-09-23 — a strain gauge on the stem, not an anemometer)
records the strain at anchor height on a host-size pine. Its product is the histogram of strain RANGES, and that is
period-specific. The sheet proposes carrying it in time at the same site through the ERA5 hourly 10 m wind of the site
cell, which the tree already holds (data/era5_cherkasy, 1991–2020): bin the measured hours by the same hour's ERA5
wind, then weight the bins by the 30-year climatology. That needs the campaign to collect hours in the strong-wind bins,
and how long that takes depends on the month it starts in — and on the YEAR, because strong wind comes in a few storms.

WHAT IS COMPUTED. (1) Per calendar month, over 1991–2020: the mean hours per day with ERA5 10 m wind ≥ Beaufort 4
(5.5 m/s), Beaufort 5 (8.0 m/s, «small trees in leaf begin to sway»; the WMO anchors script 62 uses — a proxy, not a sway
criterion) and the all-year 99th percentile of the hourly series (data-defined); the Beaufort-5 storms — runs of
consecutive hours ≥ 8 m/s — that start in the month, and the share of years in which the month has none. (2) The
REPLAY, which is the campaign length: for every start month and each of the 30 years, start on the 1st and count real
hours until TARGET_HOURS at ≥ 8 m/s (OURS — a declared minimum, not a statistical design); a start whose target is not
reached before the series ends is censored and ranks last. The median, p75 and p90 take an actual year's value (numpy
«higher»), never an interpolation. (3) For the sheet's sensor set, the battery days and the TRIPS a campaign of the
median (and p75) length costs: installation + one swap per battery after the first + removal = ceil(days / battery
days) + 1.

⚠️ Why the replay and not the mean rate: an earlier version divided TARGET_HOURS by the month's 30-year mean rate. That
is the length of a campaign in an average year, and no year is average — 14 of 30 Januaries have no Beaufort-5 hour at
all — so it put the shortest campaign in January at ≈ 50 days, where the replay's median is longer and January is not
the fastest start (caught by the adversary before push, 2026-10-18). The mean-rate figure stays in the cache only as
the month's rate, never as a length.

CAN: say which start months make a short campaign likely, how often a winter fails to deliver, and price it in trips.
CANNOT: say how ERA5's open-terrain grid wind relates to the wind under the canopy at anchor height — that transfer is
exactly what the campaign measures, and with ≈ 2 storms in 10 hours one campaign cannot show that it is stable; say
whether TARGET_HOURS is enough for a histogram's tail; price cold derating or depth of discharge (USABLE_FRACTION = 1,
so the battery days are a ceiling and the trips a floor).

Power (read in the primaries): Nickl, Kolbe & Schindler 2022, HardwareX 12, e00379 (PMC9685482) — the ground receiver
draws 0.13 A and each Tree Strain Sensor 26.3 mA; ten sensors run 152 h on a 12 V 60 Ah battery (the control). Kolbe &
Schindler 2021, HardwareX 9, e00180 (PMC9041182), Table 1 — a Tree Response Sensor draws 0.03 A. The set is the
primary's pair — two strain sensors at right angles, which give the bending strain at ANY azimuth of the circle, so the
anchor's azimuth need not be known — plus one tilt sensor beside them at anchor height: three of the four sensors per
tree the forest access application asks for. The 100 Ah battery is OURS (a larger stock size).

Clock: the ERA5 file runs on a fixed UTC+3 clock (data/era5_cherkasy/README.md); month starts here are cut at UTC+3
midnight. To join a field record in UTC, subtract 3 h from the file's labels — the sheet's §2.

Run:  python tools/in_silico/scripts/98_field_strain_campaign.py      # seconds
"""
from __future__ import annotations

import importlib.util
import json
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import CACHE_DIR
from lib.utils import banner

SI_DESCRIPTION = ("How long a field campaign of stem-strain sensors must run to collect strong-wind hours, replayed over 30 "
                  "years of hourly reanalysis wind at the site for each start month, and how many battery trips that costs.")  # its row in the paper SI (72)
OUT_JSON = CACHE_DIR / "mechanical" / "field_strain_campaign.json"

BEAUFORT_MS = {"beaufort_4": 5.5, "beaufort_5": 8.0}     # WMO anchors as script 62 uses them — a proxy, not a criterion
TARGET_HOURS = 10                                        # OURS: Beaufort-5 hours the campaign must collect
RECEIVER_A, TSS_A, TRS_A = 0.13, 0.0263, 0.03            # Nickl 2022 (receiver, strain sensor) · Kolbe 2021 Table 1 (tilt)
N_TSS, N_TRS = 2, 1                                      # the primary's perpendicular pair + one tilt sensor beside it
N_TSS_WITH_THIRD = 3                                     # the variant: a third TSS opposite one of the pair (redundancy, common mode)
BATTERY_AH = {"60_Ah_as_in_the_papers": 60.0, "100_Ah_ours": 100.0}
USABLE_FRACTION = 1.0                                    # OURS: the full rating, as the papers' 152 h figure uses it
CHECK_TEN_TSS_H = 152.0                                  # Nickl 2022: ten sensors, 60 Ah → 152 h — the control
WITHIN_DAYS = (30, 60, 90)                               # the share of years whose campaign ends within these
CAP_MONTH_DAY = (5, 1)                                   # OURS, a candidate cap: the campaign stops at 1 May (end of April)
WINTER_STARTS = (12, 1, 2, 3)


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def replay_days(strong: np.ndarray, start: int, target: int) -> float | None:
    """Days from hour index `start` until `target` strong hours are collected; None if the series ends first."""
    hits = np.flatnonzero(strong[start:])
    if hits.size < target:
        return None
    return (hits[target - 1] + 1) / 24.0


def storms(strong: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Start indices and lengths (hours) of the runs of consecutive strong hours."""
    s = strong.astype(np.int8)
    start = np.flatnonzero(np.diff(np.concatenate(([0], s))) == 1)
    end = np.flatnonzero(np.diff(np.concatenate((s, [0]))) == -1)
    return start, end - start + 1


def main() -> int:
    t0 = time.time()
    banner("98 — field strain campaign: Beaufort-5 hours replayed by start month over ERA5, battery trips (HW.43)")
    h = _load("s71_capsule", "71_capsule_thermal_envelope.py").load_hours()
    u, stamp = h["u10"], h["time"]
    year = np.array([int(t[:4]) for t in stamp])
    month = np.array([int(t[5:7]) for t in stamp])
    day1 = np.array([t[8:13] == "01T00" for t in stamp])
    years = sorted(set(year.tolist()))
    p99 = float(np.percentile(u, 99))
    thresholds = {**BEAUFORT_MS, "p99_all_year": p99}
    strong = u >= BEAUFORT_MS["beaufort_5"]
    storm_start, storm_len = storms(strong)
    if storm_len.sum() != strong.sum():
        raise SystemExit("storm runs do not add up to the strong hours")      # control: every strong hour is in one run

    # control: the paper's own figure — ten sensors on 60 Ah — must come out of the same arithmetic
    ten = 60.0 / (RECEIVER_A + 10 * TSS_A)
    if abs(ten - CHECK_TEN_TSS_H) > 0.02 * CHECK_TEN_TSS_H:
        raise SystemExit(f"power arithmetic does not reproduce Nickl 2022's 152 h for ten sensors: {ten:.0f} h")
    current_a = RECEIVER_A + N_TSS * TSS_A + N_TRS * TRS_A
    battery_days = {k: round(ah * USABLE_FRACTION / current_a / 24.0, 2) for k, ah in BATTERY_AH.items()}

    def trips(days):
        return {k: (int(np.ceil(days / bd)) + 1 if days is not None else None) for k, bd in battery_days.items()}

    by_month = {}
    for m in range(1, 13):
        sel = month == m
        n_days = sel.sum() / 24.0
        rates = {k: round(float((u[sel] >= thr).sum() / n_days), 3) for k, thr in thresholds.items()}
        in_month = month[storm_start] == m
        b5_by_year = [int(strong[sel & (year == y)].sum()) for y in years]
        starts = [int(np.flatnonzero(day1 & (month == m) & (year == y))[0]) for y in years]
        runs = [replay_days(strong, s, TARGET_HOURS) for s in starts]
        ranked = np.array([r if r is not None else np.inf for r in runs])
        q = {f"p{p}": float(np.percentile(ranked, p, method="higher")) for p in (50, 75, 90)}
        q = {k: (round(v, 1) if np.isfinite(v) else None) for k, v in q.items()}
        by_month[f"{m:02d}"] = {
            "hours_per_day": rates,
            "beaufort_5_storms_30y": int(in_month.sum()),
            "beaufort_5_hours_per_storm_mean": round(float(storm_len[in_month].mean()), 2) if in_month.any() else None,
            "years_without_beaufort_5": int(sum(1 for b in b5_by_year if b == 0)),
            "replay_days_by_year": [round(r, 2) if r is not None else None for r in runs],
            "replay_days": q,
            "censored_years": int(sum(1 for r in runs if r is None)),
            "share_within_days": {str(d): round(float((ranked <= d).mean()), 3) for d in WITHIN_DAYS},
            "trips_at_median": trips(q["p50"]),
            "trips_at_p75": trips(q["p75"]),
        }
    # (4) the same replay with a cap: stop at the target OR at 1 May of the season, whichever first — what the campaign
    # collects by then, and the trips it costs at most. A season whose cap lies beyond the series is dropped, not ranked.
    index = {s: i for i, s in enumerate(stamp)}
    capped = {}
    for m in WINTER_STARTS:
        seasons = []
        for y in years:
            cap_year = y + 1 if m == 12 else y
            cap_key = f"{cap_year}-{CAP_MONTH_DAY[0]:02d}-{CAP_MONTH_DAY[1]:02d}T00:00"
            if cap_key not in index:
                continue
            s0 = int(np.flatnonzero(day1 & (month == m) & (year == y))[0])
            c = index[cap_key]
            got = int(strong[s0:c].sum())
            full = replay_days(strong, s0, TARGET_HOURS)
            used = min(full, (c - s0) / 24.0) if full is not None else (c - s0) / 24.0
            seasons.append({"start_year": y, "beaufort_5_hours_by_cap": got, "reached": got >= TARGET_HOURS,
                            "days_used": round(used, 2)})
        hrs = np.array([s["beaufort_5_hours_by_cap"] for s in seasons])
        used = np.array([s["days_used"] for s in seasons])
        capped[f"{m:02d}"] = {
            "n_seasons": len(seasons),
            "share_reached_by_cap": round(float(np.mean([s["reached"] for s in seasons])), 3),
            "seasons_not_reached": int(sum(1 for s in seasons if not s["reached"])),
            "seasons_with_zero_by_cap": int((hrs == 0).sum()),
            "beaufort_5_hours_by_cap_median": float(np.percentile(hrs, 50, method="higher")),
            "days_used_median": float(np.percentile(used, 50, method="higher")),
            "days_used_max": round(float(used.max()), 2),
            "trips_max": {k: int(np.ceil(used.max() / bd)) + 1 for k, bd in battery_days.items()},
            "trips_median": {k: int(np.ceil(float(np.percentile(used, 50, method="higher")) / bd)) + 1
                             for k, bd in battery_days.items()},
            "seasons": seasons,
        }
    month_rate = {f"{m:02d}": by_month[f"{m:02d}"]["hours_per_day"]["beaufort_5"] for m in range(1, 13)}
    # the variant set: a third strain sensor — its current, battery days and the capped December trips
    cur3 = RECEIVER_A + N_TSS_WITH_THIRD * TSS_A + N_TRS * TRS_A
    bd3 = {k: round(ah * USABLE_FRACTION / cur3 / 24.0, 2) for k, ah in BATTERY_AH.items()}
    dec = capped["12"]
    third = {"n_tss": N_TSS_WITH_THIRD, "current_A": round(cur3, 4), "battery_days": bd3,
             "december_capped_trips_median": {k: int(np.ceil(dec["days_used_median"] / b)) + 1 for k, b in bd3.items()},
             "december_capped_trips_max": {k: int(np.ceil(dec["days_used_max"] / b)) + 1 for k, b in bd3.items()}}

    med = {m: r["replay_days"]["p50"] for m, r in by_month.items() if r["replay_days"]["p50"] is not None}
    best = min(med, key=med.get)
    rb = by_month[best]
    jan = by_month["01"]
    winter = sorted(("12", "01", "02", "03"), key=lambda m: med[m])
    verdict = (
        f"Replayed over 1991–2020, a campaign that must collect {TARGET_HOURS} hours of ERA5 10 m wind ≥ 8.0 m/s (Beaufort 5) "
        f"at the site cell takes a median {rb['replay_days']['p50']:.0f} days from a start on the 1st of month {best} "
        f"(p75 {rb['replay_days']['p75']:.0f}, p90 {rb['replay_days']['p90']:.0f}); the winter starts rank "
        f"{' < '.join(winter)} by median, and January's {jan['replay_days']['p50']:.0f} — like the others — sits inside the "
        f"scatter of 30 years, so December–March is one window, not a ranking. The hours come in storms: "
        f"{jan['years_without_beaufort_5']} of {len(years)} Januaries have no Beaufort-5 hour at all, and the January storms "
        f"last {jan['beaufort_5_hours_per_storm_mean']:.1f} h on average, so {TARGET_HOURS} hours are about two storms. "
        f"Capped at 1 May, a 1 December start reaches the target in {capped['12']['share_reached_by_cap'] * 100:.0f} % of "
        f"{capped['12']['n_seasons']} seasons ({capped['12']['seasons_not_reached']} do not), against "
        f"{capped['03']['share_reached_by_cap'] * 100:.0f} % from 1 March, for at most "
        f"{capped['12']['trips_max']['100_Ah_ours']} trips on 100 Ah. "
        f"The sheet's set ({N_TSS} strain sensors at right angles and {N_TRS} tilt sensor on one receiver, {current_a:.4f} A) "
        f"runs {battery_days['60_Ah_as_in_the_papers']:.1f} days on 60 Ah and {battery_days['100_Ah_ours']:.1f} on 100 Ah, so "
        f"the median campaign from month {best} costs {rb['trips_at_median']['60_Ah_as_in_the_papers']} / "
        f"{rb['trips_at_median']['100_Ah_ours']} trips (60 / 100 Ah: installation, swaps, removal) and the p75 one "
        f"{rb['trips_at_p75']['60_Ah_as_in_the_papers']} / {rb['trips_at_p75']['100_Ah_ours']}. The battery days take the "
        f"full rating in winter cold, so the trips are a floor; and how ERA5's open-terrain wind maps to the wind under the "
        f"canopy is what the campaign measures, not what this assumes.")

    out = {
        "question": "How long the HW.43 field strain campaign must run, by start month, to collect strong-wind hours that let "
                    "its strain-range histogram be weighted by the 30-year ERA5 wind climatology; and its battery trips.",
        "wind_series": "ERA5 hourly 10 m wind speed, data/era5_cherkasy/hourly_1991_2020.csv.gz (71's loader), km/h → m/s, "
                       "fixed UTC+3 clock",
        "thresholds_ms": {k: round(v, 3) for k, v in thresholds.items()},
        "target_beaufort_5_hours_ours": TARGET_HOURS,
        "years": [years[0], years[-1]],
        "quantile_method": "numpy percentile, method='higher' — an actual year's value; a censored start ranks last",
        "power": {"receiver_A": RECEIVER_A, "tss_A": TSS_A, "trs_A": TRS_A, "n_tss": N_TSS, "n_trs": N_TRS,
                  "current_A": round(current_a, 4), "control_ten_tss_60Ah_h": round(ten, 1),
                  "control_paper_h": CHECK_TEN_TSS_H, "usable_fraction_ours": USABLE_FRACTION,
                  "trips_rule": "ceil(days / battery days) + 1 — installation, one swap per battery after the first, removal",
                  "sources": {"receiver_and_tss": "Nickl, Kolbe & Schindler 2022, HardwareX 12, e00379 (PMC9685482)",
                              "trs": "Kolbe & Schindler 2021, HardwareX 9, e00180 (PMC9041182), Table 1"}},
        "battery_days": battery_days,
        "battery_Ah_for_90_days": round(current_a * 24 * 90),     # what one battery would need for the application's quarter
        "by_month": by_month,
        "best_start_month": best,
        "capped_at": f"{CAP_MONTH_DAY[1]:02d}.{CAP_MONTH_DAY[0]:02d} of the season (ours, a candidate)",
        "capped_by_start_month": capped,
        "beaufort_5_rate_after_april": {m: month_rate[m] for m in ("05", "06", "07", "08", "09")},
        "set_with_third_tss": third,
        "not_modelled": ["the ERA5 → sub-canopy wind transfer (the campaign measures it; ≈ 2 storms cannot show it is stable)",
                         "whether TARGET_HOURS suffices for the histogram's tail",
                         "battery derating in cold and depth of discharge (USABLE_FRACTION = 1 — the trips are a floor)"],
        "verdict": verdict,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for m, r in by_month.items():
        rd = r["replay_days"]
        print(f"  {m}: B5 {r['hours_per_day']['beaufort_5']:5.3f} h/d · {r['beaufort_5_storms_30y']:3d} storms · "
              f"{r['years_without_beaufort_5']:2d} y without · replay p50 {rd['p50']} p75 {rd['p75']} p90 {rd['p90']} d · "
              f"trips {r['trips_at_median']['60_Ah_as_in_the_papers']}/{r['trips_at_median']['100_Ah_ours']}")
    print(f"\n  VERDICT: {verdict}")
    banner(f"✅ saved {OUT_JSON.name} · {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
