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
days) + 1. (4) The same replay capped at 1 May. (5) The battery TYPE for the ratified set — AGM lead-acid ⊥ LiFePO4 —
over the capped 1 December campaign of every season, with the ERA5 2 m air as the battery temperature (hourly, and a
24-hour trailing mean for the thermal mass): the hours below each source's discharge floor and the Beaufort-5 hours
among them; for AGM, the hours the air spends below the freezing point of the electrolyte at the battery's state of
charge (which falls with the ampere-hours drawn), for swaps every 10 … 14 days; and, for each maker's cold-capacity
reading, the battery days at the coldest fortnights and the trips when every battery is swapped at its derated resource
(the capacity fraction at the mean air temperature of its own interval).

⚠️ Why the replay and not the mean rate: an earlier version divided TARGET_HOURS by the month's 30-year mean rate. That
is the length of a campaign in an average year, and no year is average — 14 of 30 Januaries have no Beaufort-5 hour at
all — so it put the shortest campaign in January at ≈ 50 days, where the replay's median is longer and January is not
the fastest start (caught by the adversary before push, 2026-10-18). The mean-rate figure stays in the cache only as
the month's rate, never as a length.

CAN: say which start months make a short campaign likely, how often a winter fails to deliver, and price it in trips.
CANNOT: say how ERA5's open-terrain grid wind relates to the wind under the canopy at anchor height — that transfer is
exactly what the campaign measures, and with ≈ 2 storms in 10 hours one campaign cannot show that it is stable; say
whether TARGET_HOURS is enough for a histogram's tail; price cold derating in (3)–(4) (USABLE_FRACTION = 1, so those
battery days are a ceiling and those trips a floor). (5) CAN say what each chemistry costs in mass and price, how often the
site's air crosses each sheet's discharge floor and the AGM freezing curve, and what the makers' cold readings would do
to the swaps. It CANNOT say the cold capacity at OUR current (≈ C/419): no sheet measures it and no reading is a proven
floor there — Lifeline's C/20 is the highest curve on its page while its own text gives less, Victron's nominal is stated
for any current ≤ 1C, Rolls names no current and the EVE row is a cell minimum to a cut-off below a pack's (each
reading's «basis») — and readings of
different kinds and currents do not rank the two chemistries; nor the recommended battery's own cold capacity (its cells'
maker is not named); nor the battery's own temperature (ASSUMED no colder than the 2 m air: under snow it runs warmer,
but on bare ground in a clear calm night the air near the ground can be colder); nor whether one hour below a freezing
point freezes 10–30 kg (the 24-hour mean is the other named reading), nor whether a frozen AGM still feeds our current.

Battery sources (read 2026-10-19; transcriptions in BATTERY_TYPES): Victron «12,8 & 25,6 Volt Lithium-Iron-Phosphate
Batteries Smart» datasheet; EVE Power LF100LA specification RD-LF100LA-S01-LF rev. B (Table 4, §3.7.3.2); Concorde,
Technical Manual for Lifeline Batteries, Document 6-0101 Rev. F (Table 6-2 freezing points; Appendix C p. 38 read off
the page image); Rolls Battery R12-100AGM datasheet Rev. 7 (August 2024); LogicPower product pages 24662 and 3877 and
the 24662 passport and the JK BMS manual (logicpower.ua — masses, ranges and prices listed in Ukraine; the AGM card
shows OutOfStock on the day).

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

# (5) The battery TYPE (desk leg of HW.43), read in the makers' sheets 2026-10-19. Prices are the seller's card that day
# (a snapshot, not a quote); «discharge_C»/«charge_C» are the sheets' operating ranges.
SWAP_DAYS_RATIFIED = 14                                  # OURS: «приблизно кожні 2 тижні» of the ⚖️ 2026-10-18, read as 14 days
FREEZE_SWAP_DAYS = (10, 11, 12, 13, 14)                  # the AGM freezing count, for every cadence and every first-swap day
SWAP_RULES = {                                           # OURS: candidate swap calendars for the chosen chemistry
    "every_14_days": {"short_days": 14, "short_months": [], "long_days": 14},
    "december_to_february_every_10_else_14": {"short_days": 10, "short_months": [12, 1, 2], "long_days": 14},
    "december_to_march_every_10_else_14": {"short_days": 10, "short_months": [12, 1, 2, 3], "long_days": 14},
    "every_10_days": {"short_days": 10, "short_months": [], "long_days": 10},
}
COLDEST_MEAN_DAYS = (1, 3, 5, 7, 10, 14)                 # the coldest n-day mean air of the window, to set a cold test against
FREEZER_C = -18.0                                        # the freezer test's nominal temperature; its accepted mean −20 … −18 °C
MEASURED_BAND = (0.58, 0.81)                             # the band where the measured fraction sets the swaps (10 → 58 %, 14 → 81 %)
RH_SPEC_PCT = 80                                         # the LogicPower LiFePO4 passport and manual: humidity 10–80 % RH
BATTERY_TYPES = {
    "agm_lead_acid": {
        "examples": {
            "LogicPower LPM-MG 12V 100 Ah": {
                "mass_kg": 28.29, "price_uah": 9314, "discharge_C": [-15, 50], "charge_C": [-10, 50],
                "source": "logicpower.ua, product 3877, «specifications» tab; the card's schema.org availability reads "
                          "OutOfStock on 2026-10-19 (an «AGM мультигелевий» product)"},
            "Rolls R12-100AGM": {"mass_kg": 27.0, "capacity_Ah_c20": 100, "capacity_Ah_c100": 110,
                                 "source": "Rolls Battery datasheet R12-100AGM, Rev. 7, August 2024 (at our ≈ C/419 the rating is at least the 100-hour 110 Ah, so the AGM battery days below, on 100 Ah, are low by up to ≈ 10 %)"}},
        # operating (discharge) floors as each source states them — one product's floor is not the chemistry's
        "discharge_floors_C": {"LogicPower LPM-MG": -15, "Lifeline (operating range)": -40},
        # electrolyte freezing point by state of charge (%): Concorde, Lifeline Technical Manual 6-0101 Rev. F, Table 6-2
        "freezing_point_C_by_soc": [[0, -6.0], [25, -13.0], [50, -25.0], [75, -47.0], [100, -70.0]],
        "maker_on_freezing": "Lifeline 6-0101 Rev. F: «resistant to damage by freezing temperatures» against flooded "
                             "batteries (§3.1, Table 3-1); and (§5.8) in cold climates «the state of charge should be kept "
                             "at a maximum to prevent freezing», frozen batteries «are not capable of charging or "
                             "discharging except at very low rates, and may be permanently damaged by expansion of the "
                             "electrolyte», and a battery whose container shows cracking «is no longer serviceable»",
        "cold_readings": {
            "lifeline_c20": {"points": [[-20, 0.68], [0, 0.90], [25, 1.00]], "rate": "C/20",
                             "basis": "the highest curve on its page, which rises as the current falls (C/1 … C/20); "
                                      "the manual's own text gives less (≈ 60 % at −18 °C, current not stated) — not a "
                                      "proven floor at our current",
                             "source": "Lifeline Technical Manual 6-0101 Rev. F, Appendix C p. 38 «Capacity versus "
                                       "Temperature», C/20 curve, read off the page image at its −4 °F and 32 °F marks; "
                                       "the manual's text (§5.8) gives «about 60 %» for continuous operation at −18 °C, "
                                       "current not stated — below this curve there"},
            "rolls": {"points": [[-15, 0.65], [0, 0.85], [25, 1.00], [40, 1.02]], "rate": "not stated",
                      "basis": "current not stated — not shown to be a floor; below −15 °C extrapolated along the sheet's "
                               "coldest segment",
                      "source": "Rolls R12-100AGM datasheet, «Capacity Affect by Temperature»"}}},
    "lifepo4": {
        "examples": {
            "LogicPower LP LiFePO4 12.8V 100 Ah (BMS 100A/50A) Smart BT": {
                "mass_kg": 9.67, "price_uah": 16074, "discharge_C": [-20, 60], "charge_C": [0, 40],
                "humidity_pct": [10, RH_SPEC_PCT],
                "source": "logicpower.ua, product 24662 (InStock 2026-10-19), passport 0024662-datasheet.pdf (internal "
                          "BMS, Bluetooth; prismatic cells of an unnamed maker; humidity 10–80 % RH); BMS manual "
                          "BMS-JK-12V_24V.pdf, all 32 page images read: no low-temperature discharge cut-off stated, "
                          "only the ranges (discharge −20…+60, charge 0…+40 °C, charging stops below 0 °C, p. 8); use in "
                          "improper conditions voids the warranty (p. 8), warranty only in suitable climatic conditions "
                          "(p. 28); after storage below 5 °C wait for room temperature and no condensate (p. 17); charge a "
                          "battery kept below the charge range only after ≥ 4 h at room temperature (p. 20); not warranty "
                          "cases (p. 21): operation outside the allowed temperatures and humidity, condensation, and deep "
                          "discharge — a long stay cut off at low voltage; keep from rain and damp (p. 25); the app's "
                          "remaining percent is the remainder of a set full capacity (p. 12, our reading)"},
            "Victron LiFePO4 12.8/100 Smart": {
                "mass_kg": 14.0, "discharge_C": [-20, 50], "charge_C": [5, 50],
                "source": "Victron datasheet «12,8 & 25,6 Volt Lithium-Iron-Phosphate Batteries Smart» (needs an external BMS)"}},
        "discharge_floors_C": {"LogicPower LP LiFePO4 · Victron (operating range)": -20},
        "cold_readings": {
            "eve_cell_0p5c": {"points": [[-20, 0.55], [0, 0.80], [10, 0.85], [25, 1.00]], "rate": "0.5C",
                              # §4.2.2: no continuous discharge allowed below this state of charge (%) at the temperature
                              "discharge_soc_floor_pct": [[-20, 30], [-10, 20], [0, 10], [10, 0]],
                              "basis": "a cell minimum at 0.5C down to 2.0 V per cell, below a pack's 10.5 V cut-off "
                                       "(2.625 V per cell) — not shown to be a floor for a pack",
                              "source": "EVE LF100LA specification RD-LF100LA-S01-LF rev. B, Table 4 and §3.7.3.2 (the "
                                        "0.5C current is in the Chinese text of the method only)"},
            "victron_pack_le_1c": {"points": [[-20, 0.50], [0, 0.80], [25, 1.00]], "rate": "≤ 1C",
                                   "basis": "the maker's nominal for any current up to 1C, ours included (to 11.2 V); "
                                            "whether with margin at our current, the sheet does not say",
                                   "source": "Victron LiFePO4 Smart datasheet, «Nominal capacity @ 25 / 0 / −20 °C»"}}},
}


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


def capacity_fraction(points: list, t_c):
    """A sheet's capacity fraction at temperature t_c: piecewise linear between its points, held at the warmest one,
    EXTRAPOLATED along the coldest segment below the coldest one (holding it there would be the kind side)."""
    ts = np.array([p[0] for p in points], float)
    fs = np.array([p[1] for p in points], float)
    t = np.asarray(t_c, float)
    slope = (fs[1] - fs[0]) / (ts[1] - ts[0])
    return np.where(t < ts[0], fs[0] + slope * (t - ts[0]), np.interp(t, ts, fs))


def battery_intervals(temp: np.ndarray, start: int, stop: int, frac, full_hours: float,
                      cap_hours: int | None = None) -> list[float]:
    """Battery after battery from `start` to `stop`: each runs until the charge drawn reaches the rating times the
    capacity fraction at the MEAN temperature of its own interval so far — or, with `cap_hours`, until that cap if it
    comes first (the ratified «≈ 2 weeks, not longer than its resource»). Days per battery; the last one may outlast."""
    out, t0 = [], start
    while t0 < stop:
        seg = temp[t0:stop]
        k = np.arange(1, seg.size + 1)
        hit = np.flatnonzero(k >= frac(np.cumsum(seg) / k) * full_hours)
        n = int(hit[0]) + 1 if hit.size else seg.size
        if cap_hours is not None:
            n = min(n, cap_hours)
        out.append(n / 24.0)
        t0 += n
    return out


def lfp_trips_rule_victron(types_out: dict) -> list:
    """The Victron reading's trips under the ratified rule, as section (5) stored them."""
    return types_out["lifepo4"]["cold_readings"]["victron_pack_le_1c"]["ratified_rule"]["trips_by_season"]


def r2s(pair: list) -> str:
    """«a–b», or «a» when both ends agree."""
    return f"{pair[0]}–{pair[-1]}" if pair[0] != pair[-1] else f"{pair[0]}"


def reading_range(readings: dict, key: str, sub: str | None = None) -> list:
    """[min, max] of a field over a chemistry's cold readings (of `readings[*][sub]` when `sub` is given)."""
    vals = [(r[sub][key] if sub else r[key]) for r in readings.values()]
    return [min(vals), max(vals)]


def swap_chain(month: np.ndarray, start: int, stop: int, rule: dict) -> list[tuple[int, int]]:
    """A swap CALENDAR from `start` to `stop`: each interval lasts rule["short_days"] when it starts in one of
    rule["short_months"], else rule["long_days"]. Returns (start hour, length in hours), the last one cut at `stop`."""
    out, t0 = [], start
    while t0 < stop:
        n = 24 * (rule["short_days"] if int(month[t0]) in rule["short_months"] else rule["long_days"])
        out.append((t0, min(n, stop - t0)))
        t0 += n
    return out


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

    # (5) the battery TYPE for the ratified set (three TSS + one TRS) over the ratified campaign of every season (1 December
    # → the target or 1 May). The battery temperature is the ERA5 2 m air, hourly and as a 24-hour trailing mean (the
    # thermal mass of 10–30 kg; OURS) — ASSUMED no colder than the box on the ground: under snow the box runs warmer, but
    # on bare ground in a clear calm night the air near the ground can be colder.
    t_air = h["t_air"]
    t24 = np.convolve(t_air, np.ones(24) / 24.0)[: t_air.size]
    t24[:23] = np.cumsum(t_air[:23]) / np.arange(1, 24)
    temps = {"air_hourly": t_air, "air_24h_mean": t24}
    full_h = bd3["100_Ah_ours"] * 24.0
    need = SWAP_DAYS_RATIFIED / bd3["100_Ah_ours"]                  # the capacity fraction a 14-day swap needs
    spans = []
    for s in dec["seasons"]:
        s0 = index[f"{s['start_year']}-12-01T00:00"]
        spans.append((s["start_year"], s0, s0 + round(s["days_used"] * 24)))
    # the climate of the whole window (a calm year runs to 1 May): each season's coldest 14-day mean air temperature
    windows = [(index[f"{y}-12-01T00:00"], index[f"{y + 1}-05-01T00:00"]) for y, _, _ in spans]
    coldest14 = [float(np.convolve(t_air[a:b], np.ones(14 * 24) / (14 * 24.0), mode="valid").min()) for a, b in windows]
    c14_median = float(np.percentile(coldest14, 50, method="higher"))
    c14_min = min(coldest14)
    coldest_mean = {str(nd): round(min(float(np.convolve(t_air[a:b], np.ones(nd * 24) / (nd * 24.0), mode="valid").min())
                                       for a, b in windows), 1) for nd in COLDEST_MEAN_DAYS}
    # control: with the full rating at every temperature the battery chain must give exactly ceil(span / battery) per season
    for _, a, b in spans:
        n_full = len(battery_intervals(t_air, a, b, lambda m: np.ones_like(m), full_h))
        if n_full != int(np.ceil((b - a) / np.ceil(full_h))):
            raise SystemExit("battery chain at full capacity does not reproduce ceil(span / battery days)")
    fp = BATTERY_TYPES["agm_lead_acid"]["freezing_point_C_by_soc"]
    fp_soc, fp_t = [p[0] for p in fp], [p[1] for p in fp]
    freeze_by_cadence = {}
    for days in FREEZE_SWAP_DAYS:      # swaps every `days`; the state of charge falls with the ampere-hours drawn
        swap_h = days * 24
        by_phase, anchored = {}, None  # fresh on 1 December, the FIRST swap on day p = 1 … days — the count moves with p
        for p in range(1, days + 1):
            per = {r: [] for r in temps}
            for _, a, b in spans:
                k = np.arange(b - a)
                since = np.where(k < p * 24, k, (k - p * 24) % swap_h)
                t_freeze = np.interp(100.0 * (1.0 - (since + 1) / full_h), fp_soc, fp_t)
                for r, tt in temps.items():
                    per[r].append(int((tt[a:b] < t_freeze).sum()))
            by_phase[p] = {r: int(sum(1 for x in v if x > 0)) for r, v in per.items()}
            if p == days:
                anchored = per             # the first swap on day `days`: every swap on a multiple of it from 1 December
        soc = 100.0 * (1.0 - swap_h / full_h)
        freeze_by_cadence[str(days)] = {
            "soc_at_swap_pct": round(soc, 1),
            "freezing_point_at_swap_C": round(float(np.interp(soc, fp_soc, fp_t)), 1),
            "freeze_hours_by_season": anchored,
            "seasons_with_freeze_hours": by_phase[days],
            "seasons_with_freeze_hours_over_first_swap_day": {
                r: [min(v[r] for v in by_phase.values()), max(v[r] for v in by_phase.values())] for r in temps},
        }
    types_out = {}
    for name, ty in BATTERY_TYPES.items():
        floors = {}
        for src, floor in ty["discharge_floors_C"].items():
            below = {r: [int((tt[a:b] < floor).sum()) for _, a, b in spans] for r, tt in temps.items()}
            floors[src] = {
                "floor_C": floor,
                "hours_below_by_season": below,
                "seasons_with_hours_below": {r: int(sum(1 for x in v if x > 0)) for r, v in below.items()},
                "beaufort_5_hours_below": int(sum(int((strong[a:b] & (t_air[a:b] < floor)).sum()) for _, a, b in spans)),
            }
        readings = {}
        for rn, rd in ty["cold_readings"].items():
            pts = rd["points"]
            frac = lambda m, pts=pts: capacity_fraction(pts, m)           # noqa: E731
            chains = [battery_intervals(t_air, a, b, frac, full_h) for _, a, b in spans]
            capped14 = [battery_intervals(t_air, a, b, frac, full_h, cap_hours=SWAP_DAYS_RATIFIED * 24) for _, a, b in spans]
            trips_cold = [len(c) + 1 for c in chains]
            trips_rule = [len(c) + 1 for c in capped14]
            full_runs = [d for c in chains for d in c[:-1]]           # the last battery of a season may be cut by its end
            readings[rn] = {
                **rd,
                "threshold_mean_C_for_14_day_swap": round(float(np.interp(need, [p[1] for p in pts], [p[0] for p in pts])), 1),
                "battery_days_at_median_coldest_fortnight": round(float(frac(c14_median)) * bd3["100_Ah_ours"], 1),
                "battery_days_at_coldest_fortnight": round(float(frac(c14_min)) * bd3["100_Ah_ours"], 1),
                "trips_by_season": trips_cold,                            # every battery swapped at its derated resource
                "trips_median": int(np.percentile(trips_cold, 50, method="higher")),
                "trips_max": int(max(trips_cold)),
                "shortest_battery_days": round(min(full_runs), 2) if full_runs else None,
                "ratified_rule": {                                        # swapped at min(14 days, its derated resource)
                    "trips_by_season": trips_rule,
                    "trips_median": int(np.percentile(trips_rule, 50, method="higher")),
                    "trips_max": int(max(trips_rule))},
            }
        types_out[name] = {
            "examples": ty["examples"],
            "discharge_floors": floors,
            "cold_readings": readings,
            "readings_range": {"battery_days_at_median_coldest_fortnight": reading_range(readings, "battery_days_at_median_coldest_fortnight"),
                               "battery_days_at_coldest_fortnight": reading_range(readings, "battery_days_at_coldest_fortnight"),
                               "trips_median": reading_range(readings, "trips_median"),
                               "trips_max": reading_range(readings, "trips_max"),
                               "ratified_rule_trips_median": reading_range(readings, "trips_median", "ratified_rule"),
                               "ratified_rule_trips_max": reading_range(readings, "trips_max", "ratified_rule")},
        }
    agm, lfp = types_out["agm_lead_acid"], types_out["lifepo4"]
    types_out["agm_lead_acid"]["freezing"] = {
        "freezing_point_C_by_soc": fp,
        "maker_on_freezing": BATTERY_TYPES["agm_lead_acid"]["maker_on_freezing"],
        "by_swap_days": freeze_by_cadence,
    }
    # swap calendars for the chosen chemistry: trips, and the intervals in which a LiFePO4 reading's battery is empty at
    # least one hour before the swap (a cut-off before it, if that reading held at our current)
    every14 = [int(np.ceil(s["days_used"] / SWAP_DAYS_RATIFIED)) + 1 for s in dec["seasons"]]
    rules_out = {}
    for rname, rule in SWAP_RULES.items():
        chains = [swap_chain(month, a, b, rule) for _, a, b in spans]
        trips = [len(c) + 1 for c in chains]
        at_risk = {}
        for rn, rd in BATTERY_TYPES["lifepo4"]["cold_readings"].items():
            pts, n_int, seasons_hit = rd["points"], 0, 0
            for c in chains:
                hit = 0
                for i0, n in c:
                    seg = t_air[i0:i0 + n]
                    k = np.arange(1, n + 1)
                    hit += bool(np.any((k >= capacity_fraction(pts, np.cumsum(seg) / k) * full_h)[:-1]))
                n_int += hit
                seasons_hit += hit > 0
            at_risk[rn] = {"intervals": n_int, "seasons": seasons_hit}
        rules_out[rname] = {"rule": rule, "trips_by_season": trips,
                            "trips_median": int(np.percentile(trips, 50, method="higher")), "trips_max": int(max(trips)),
                            "at_risk_by_lifepo4_reading": at_risk}
    # the RATIFIED rule (min(14 days, resource)) run on the Victron reading with the interval's mean temperature known:
    # its intervals, then the other reading's cut-offs inside them
    vic = BATTERY_TYPES["lifepo4"]["cold_readings"]["victron_pack_le_1c"]["points"]
    inc_chains = []
    for _, a, b in spans:
        days_list = battery_intervals(t_air, a, b, lambda m: capacity_fraction(vic, m), full_h, cap_hours=SWAP_DAYS_RATIFIED * 24)
        starts = a + np.concatenate(([0], np.cumsum([round(dd * 24) for dd in days_list])[:-1])).astype(int)
        inc_chains.append([(int(s0), round(dd * 24)) for s0, dd in zip(starts, days_list, strict=True)])
    inc_risk = {}
    for rn, rd in BATTERY_TYPES["lifepo4"]["cold_readings"].items():
        n_int = seasons_hit = 0
        for c in inc_chains:
            hit = 0
            for i0, n in c:
                seg = t_air[i0:i0 + n]
                k = np.arange(1, n + 1)
                hit += bool(np.any((k >= capacity_fraction(rd["points"], np.cumsum(seg) / k) * full_h)[:-1]))
            n_int += hit
            seasons_hit += hit > 0
        inc_risk[rn] = {"intervals": n_int, "seasons": seasons_hit}
    inc_trips = [len(c) + 1 for c in inc_chains]
    rules_out["ratified_rule_on_victron_reading"] = {
        "rule": "min(14 days, the Victron reading's resource at the interval's mean temperature — known in advance here, "
                "a forecast in the field), no margin",
        "trips_by_season": inc_trips, "trips_median": int(np.percentile(inc_trips, 50, method="higher")),
        "trips_max": int(max(inc_trips)), "at_risk_by_lifepo4_reading": inc_risk}
    if inc_trips != lfp_trips_rule_victron(types_out):
        raise SystemExit("the ratified rule's chain does not reproduce the Victron reading's ratified-rule trips")
    # the freezer test's band: the measured fraction at FREEZER_C joined linearly to the full rating at +25 °C (OURS — the
    # shape the band needs, since one point gives no curve), run under the ratified rule
    band = {}
    for fm in MEASURED_BAND:
        curve = [[FREEZER_C, fm], [25.0, 1.0]]
        chains_b = [battery_intervals(t_air, a, b, lambda m, c=curve: capacity_fraction(c, m), full_h,
                                      cap_hours=SWAP_DAYS_RATIFIED * 24) for _, a, b in spans]
        tr = [len(c) + 1 for c in chains_b]
        full = [dd for c in chains_b for dd in c[:-1]]          # every battery but a season's last, which its end may cut
        band[f"{fm:.2f}"] = {"curve": curve, "trips_by_season": tr,
                             "trips_median": int(np.percentile(tr, 50, method="higher")), "trips_max": int(max(tr)),
                             "shortest_full_interval_h": round(min(full) * 24) if full else None,
                             "intervals_shorter_than_14_days": int(sum(1 for dd in full if dd * 24 < SWAP_DAYS_RATIFIED * 24))}
    top = band[f"{MEASURED_BAND[1]:.2f}"]
    if top["intervals_shorter_than_14_days"] or top["trips_by_season"] != every14:
        raise SystemExit("a battery at the band's top end must last every 14-day interval of every season")
    accepted = [-20.0, -18.0]
    if accepted[1] > coldest_mean["10"]:
        raise SystemExit("the freezer window's warm end must be no warmer than the record's coldest 10-day mean")
    if rules_out["every_14_days"]["trips_by_season"] != every14:
        raise SystemExit("the 14-day calendar does not reproduce ceil(days / 14) + 1")     # control: two independent codes
    # site humidity against the LiFePO4 sheet's 10–80 % RH (74's own loader, joined on 71's clock)
    _, hd, _, _ = _load("s74_site", "74_site_rain_dew.py").load()
    if not np.array_equal(hd["time"], stamp):
        raise SystemExit("74's humidity series is not on 71's clock")
    rh = hd["rh"]
    rh_by_season = [float((rh[a:b] > RH_SPEC_PCT).mean()) for _, a, b in spans]
    rh_share = float(sum(int((rh[a:b] > RH_SPEC_PCT).sum()) for _, a, b in spans) / sum(b - a for _, a, b in spans))
    b5_air = [float(t_air[a:b][strong[a:b]].min()) for _, a, b in spans if strong[a:b].any()]
    b5_air24 = [float(t24[a:b][strong[a:b]].min()) for _, a, b in spans if strong[a:b].any()]
    mass = {n: [e["mass_kg"] for e in t["examples"].values()] for n, t in types_out.items()}
    fz14 = freeze_by_cadence[str(SWAP_DAYS_RATIFIED)]
    lfp_floor = next(iter(lfp["discharge_floors"].values()))
    b5_below = sum(f["beaufort_5_hours_below"] for t in types_out.values() for f in t["discharge_floors"].values())
    battery = {
        "question": "Which chemistry for the 12 V 100 Ah campaign battery: AGM lead-acid ⊥ LiFePO4 — by mass, price and "
                    "what the site's winter does to each (desk leg of HW.43); and which swap calendar for it.",
        "set": f"{N_TSS_WITH_THIRD} TSS + {N_TRS} TRS on receiver V2 (the ratified set)",
        "current_A": round(cur3, 4),
        "rate_of_100_Ah": f"C/{100.0 / cur3:.0f}",
        "battery_days_full_rating": bd3["100_Ah_ours"],
        "swap_days_ratified_ours": SWAP_DAYS_RATIFIED,
        "capacity_fraction_needed_for_swap": round(need, 3),
        "capacity_fraction_needed_for_swap_days": {str(dd): round(dd / bd3["100_Ah_ours"], 3) for dd in (10, 14)},
        "battery_temperature": "ERA5 2 m air of the site cell, hourly and as a 24-hour trailing mean for the thermal "
                               "mass (ours); ASSUMED no colder than the box on the ground",
        "seasons": len(spans),
        "campaign_span": "1 December → 10 Beaufort-5 hours or 1 May (the capped December replay above)",
        "air_min_C": round(float(min(t_air[a:b].min() for a, b in windows)), 1),
        "coldest_air_in_a_beaufort_5_hour_C": round(min(b5_air), 1),
        "coldest_24h_mean_air_in_a_beaufort_5_hour_C": round(min(b5_air24), 1),
        "coldest_mean_air_over_days_C": coldest_mean,
        "coldest_fortnight_mean_C": {"by_season": [round(x, 1) for x in coldest14], "median": round(c14_median, 1),
                                     "min": round(c14_min, 1)},
        "trips_every_14_days": {"median": int(np.percentile(every14, 50, method="higher")), "max": int(max(every14))},
        "types": types_out,
        "swap_rules_lifepo4": rules_out,
        "freezer_test": {"temperature_C": FREEZER_C, "accepted_mean_C": accepted,
                         "stop_Ah_for_14_days_at_this_current": round(SWAP_DAYS_RATIFIED * 24 * cur3, 1),
                         "stop_Ah_rounded_up": int(np.ceil(SWAP_DAYS_RATIFIED * 24 * cur3)),
                         "stop_Ah_with_10_pct_current_margin": int(np.ceil(SWAP_DAYS_RATIFIED * 24 * cur3 * 1.1)),
                         "band_shape": "the measured fraction at the freezer temperature joined linearly to the full "
                                       "rating at +25 °C (ours)",
                         "band_ends_under_the_ratified_rule": band},
        "air_rh_above_spec": {"spec_pct": RH_SPEC_PCT, "share_of_campaign_hours": round(rh_share, 3),
                              "share_by_season_min_max": [round(min(rh_by_season), 2), round(max(rh_by_season), 2)]},
        "derating_rule": "each battery runs until the charge drawn reaches the rating times the reading's capacity "
                         "fraction at the mean air temperature of its own interval so far; it is swapped then (or at 14 "
                         "days, under the ratified rule)",
        "readings_basis": "no sheet measures our current and no reading is a proven floor there: Lifeline's C/20 is "
                          "the highest curve on its page while its own text gives less; Victron's nominal is stated for "
                          "any current ≤ 1C, ours included; Rolls states no current; the EVE row is a cell minimum to a "
                          "cut-off below a pack's — see each reading's «basis»; the readings differ in kind and current, "
                          "so they do not rank the two chemistries",
    }
    rl, ra = lfp["readings_range"], agm["readings_range"]
    battery["verdict"] = (
        f"For the ratified set ({cur3:.4f} A, C/{100.0 / cur3:.0f} of 100 Ah) over the ratified campaign of "
        f"{len(spans)} seasons: AGM weighs {min(mass['agm_lead_acid']):.0f}–{max(mass['agm_lead_acid']):.0f} kg and "
        f"LiFePO4 {min(mass['lifepo4']):.1f}–{max(mass['lifepo4']):.0f} kg per battery, carried in and out on every "
        f"swap. An AGM's electrolyte freezes at a temperature set by its state of charge, which falls with the "
        f"ampere-hours drawn: swapped every {SWAP_DAYS_RATIFIED} days it is at {fz14['soc_at_swap_pct']:.1f} % by the "
        f"swap (point {fz14['freezing_point_at_swap_C']:.1f} °C), and the ERA5 air goes below the point of its current "
        f"charge in {fz14['seasons_with_freeze_hours_over_first_swap_day']['air_24h_mean'][0]}–"
        f"{fz14['seasons_with_freeze_hours_over_first_swap_day']['air_24h_mean'][1]} of {len(spans)} campaigns on the "
        f"24-hour mean, as the first swap moves over the cycle; the maker rates AGM against flooded batteries as "
        f"resistant to freezing damage but tells the user to keep the charge at a maximum, since a frozen battery "
        f"discharges only at very low rates and may be damaged. LiFePO4 holds no water; its sheets allow discharge to "
        f"{lfp_floor['floor_C']} °C, which the air crosses in {lfp_floor['seasons_with_hours_below']['air_24h_mean']} "
        f"campaigns on the 24-hour mean, and the coldest air in any Beaufort-5 hour is {min(b5_air):.1f} °C "
        f"({b5_below} target hours below a discharge floor). The LiFePO4 sheet's humidity ends at {RH_SPEC_PCT} % RH, "
        f"and the air is above it {rh_share * 100:.0f} % of the campaign hours. No maker's cold reading is measured at "
        f"our current; on them a battery lasts {ra['battery_days_at_coldest_fortnight'][0]:.1f}–"
        f"{ra['battery_days_at_coldest_fortnight'][1]:.1f} days (AGM) and {rl['battery_days_at_coldest_fortnight'][0]:.1f}–"
        f"{rl['battery_days_at_coldest_fortnight'][1]:.1f} (LiFePO4) in the coldest fortnight of {len(spans)} seasons, "
        f"and under the ratified min(14 days, resource) a LiFePO4 campaign costs {rl['ratified_rule_trips_median'][1]} "
        f"trips at the median and up to {rl['ratified_rule_trips_max'][0]}–{rl['ratified_rule_trips_max'][1]}. "
        f"Against the LiFePO4 readings (a battery empty at least an hour before its swap), the ratified rule run on the "
        f"Victron reading with the interval's mean temperature known cuts off in "
        f"{r2s(sorted(v['seasons'] for v in rules_out['ratified_rule_on_victron_reading']['at_risk_by_lifepo4_reading'].values()))} "
        f"of {len(spans)} campaigns, swapping every 14 days in "
        f"{r2s(sorted(v['seasons'] for v in rules_out['every_14_days']['at_risk_by_lifepo4_reading'].values()))}, and "
        f"every 10 days from December to March in "
        f"{r2s(sorted(v['seasons'] for v in rules_out['december_to_march_every_10_else_14']['at_risk_by_lifepo4_reading'].values()))} "
        f"— whether the readings hold at our current, only a measurement shows.")

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
        "battery_type": battery,
        "not_modelled": ["the ERA5 → sub-canopy wind transfer (the campaign measures it; ≈ 2 storms cannot show it is stable)",
                         "whether TARGET_HOURS suffices for the histogram's tail",
                         "cold derating in the trips above (USABLE_FRACTION = 1 — those trips are a floor); battery_type "
                         "prices it with the makers' readings, none of them measured at our current",
                         "the battery's own temperature (assumed no colder than the 2 m air)"],
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
    print(f"\n  BATTERY: {battery['verdict']}")
    banner(f"✅ saved {OUT_JSON.name} · {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
