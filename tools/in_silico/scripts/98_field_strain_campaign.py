#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
98 — How long the field strain campaign of HW.43 must run, and how many visits its batteries cost, from the 30-year
hourly ERA5 wind of the site cell (the instrument sheet docs/protocols/anchor/field_strain_sensor_sheet.md, its §3).

THE QUESTION. The field leg (00_07 HW.43; ⚖️ delegated 2026-09-23 — a strain gauge on the stem, not an anemometer)
records the strain at anchor height on a host-size pine. Its product is the histogram of strain RANGES, and that is
site- and period-specific: without a wind series of its own it cannot be carried to a 20-year budget. The carrier is
the ERA5 hourly 10 m wind of the same cell, which the tree already holds (data/era5_cherkasy, 1991–2020): bin the
measured hours by the same hour's ERA5 wind, then weight the bins by the 30-year climatology. That needs the campaign
to collect hours in the strong-wind bins, and how long that takes depends on the month it runs in.

WHAT IS COMPUTED. Per calendar month, over 1991–2020: the mean hours per day with ERA5 10 m wind ≥ three thresholds —
Beaufort 4 (5.5 m/s) and Beaufort 5 (8.0 m/s, «small trees in leaf begin to sway»; the WMO anchors script 62 uses, a
proxy, not a sway criterion) and the all-year 99th percentile of the hourly series (data-defined); the expected days to
collect TARGET_HOURS above each (OURS — a declared minimum per bin, not a statistical design); and, for the sensor set the
sheet specifies, the battery days and the visits that campaign costs (power figures read in the two primaries).

CAN: say which months make a short campaign possible, and price it in visits. CANNOT: say how ERA5's open-terrain grid
wind relates to the wind under the canopy at anchor height — that transfer is exactly what the campaign measures (the
binning absorbs it, provided it is stable); say whether TARGET_HOURS is enough for a histogram's tail; include
interannual spread (the per-month mean is a 30-year mean, and a given winter may give half as much).

Power (read in the primaries): Nickl, Kolbe & Schindler 2022, HardwareX 12, e00379 (PMC9685482) — the ground receiver
draws 0.13 A and each Tree Strain Sensor 26.3 mA; ten sensors run 152 h on a 12 V 60 Ah battery. Kolbe & Schindler 2021,
HardwareX 9, e00180 (PMC9041182) — a Tree Response Sensor (tilt) draws 0.03 A. The 100 Ah battery is OURS (a larger stock
size), as is the usable fraction USABLE_FRACTION.

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

SI_DESCRIPTION = ("How long a field campaign of stem-strain sensors must run to collect strong-wind hours, month by month, "
                  "from 30 years of hourly reanalysis wind at the site, and how many battery visits that costs.")  # its row in the paper SI (72)
OUT_JSON = CACHE_DIR / "mechanical" / "field_strain_campaign.json"

BEAUFORT_MS = {"beaufort_4": 5.5, "beaufort_5": 8.0}     # WMO anchors as script 62 uses them — a proxy, not a criterion
TARGET_HOURS = 10.0                                      # OURS: hours wanted in each strong-wind bin
RECEIVER_A, TSS_A, TRS_A = 0.13, 0.0263, 0.03            # Nickl 2022 (receiver, strain sensor) · Kolbe 2021 (tilt sensor)
N_TSS, N_TRS = 4, 1                                      # the sheet's set: four strain sensors at 90°, one tilt sensor
BATTERY_AH = {"60_Ah_as_in_the_papers": 60.0, "100_Ah_ours": 100.0}
USABLE_FRACTION = 1.0                                    # OURS: the papers' 152 h for ten sensors uses the full rating
CHECK_TEN_TSS_H = 152.0                                  # Nickl 2022: ten sensors, 60 Ah → 152 h — the control


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    t0 = time.time()
    banner("98 — field strain campaign: strong-wind hours by month from ERA5, battery visits (HW.43)")
    h = _load("s71_capsule", "71_capsule_thermal_envelope.py").load_hours()
    u, month = h["u10"], np.array([int(t[5:7]) for t in h["time"]])
    p99 = float(np.percentile(u, 99))
    thresholds = {**BEAUFORT_MS, "p99_all_year": p99}

    # control: the paper's own figure — ten sensors on 60 Ah — must come out of the same arithmetic
    ten = 60.0 / (RECEIVER_A + 10 * TSS_A)
    if abs(ten - CHECK_TEN_TSS_H) > 0.02 * CHECK_TEN_TSS_H:
        raise SystemExit(f"power arithmetic does not reproduce Nickl 2022's 152 h for ten sensors: {ten:.0f} h")
    current_a = RECEIVER_A + N_TSS * TSS_A + N_TRS * TRS_A
    battery_days = {k: round(ah * USABLE_FRACTION / current_a / 24.0, 1) for k, ah in BATTERY_AH.items()}

    by_month = {}
    for m in range(1, 13):
        sel = u[month == m]
        days = sel.size / 24.0
        row = {}
        for k, thr in thresholds.items():
            per_day = float((sel >= thr).sum() / days)
            need = TARGET_HOURS / per_day if per_day > 0 else None
            row[k] = {"hours_per_day": round(per_day, 3), "days_for_target": round(need, 1) if need else None,
                      "visits_60Ah": int(np.ceil(need / battery_days["60_Ah_as_in_the_papers"])) if need else None,
                      "visits_100Ah": int(np.ceil(need / battery_days["100_Ah_ours"])) if need else None}
        by_month[f"{m:02d}"] = row
    b5 = {m: r["beaufort_5"]["days_for_target"] for m, r in by_month.items()}
    best = min((m for m in b5 if b5[m]), key=lambda m: b5[m])
    worst = max((m for m in b5 if b5[m]), key=lambda m: b5[m])
    verdict = (
        f"Over 1991–2020 the site cell's hourly ERA5 10 m wind reaches Beaufort 5 (8.0 m/s) on "
        f"{by_month[best]['beaufort_5']['hours_per_day']:.2f} h/day in month {best} and "
        f"{by_month[worst]['beaufort_5']['hours_per_day']:.2f} h/day in month {worst}: {TARGET_HOURS:g} h at Beaufort 5 take "
        f"≈ {b5[best]:.0f} days starting in {best} and ≈ {b5[worst]:.0f} days in {worst}. With the sheet's set ({N_TSS} strain "
        f"sensors and {N_TRS} tilt sensor on one receiver, {current_a:.3f} A) a 60 Ah battery lasts "
        f"{battery_days['60_Ah_as_in_the_papers']:.1f} days and a 100 Ah one {battery_days['100_Ah_ours']:.1f}, so the best "
        f"month costs {by_month[best]['beaufort_5']['visits_60Ah']} / {by_month[best]['beaufort_5']['visits_100Ah']} visits "
        f"(60 / 100 Ah) and the worst {by_month[worst]['beaufort_5']['visits_60Ah']} / "
        f"{by_month[worst]['beaufort_5']['visits_100Ah']}. The all-year 99th percentile of the hourly wind is {p99:.2f} m/s. "
        f"These are 30-year monthly means; a given winter can give half as much, and how ERA5's open-terrain wind maps to "
        f"the wind under the canopy is what the campaign measures, not what this assumes.")

    out = {
        "question": "How long the HW.43 field strain campaign must run, by month, to collect strong-wind hours that let its "
                    "strain-range histogram be weighted by the 30-year ERA5 wind climatology; and its battery visits.",
        "wind_series": "ERA5 hourly 10 m wind, data/era5_cherkasy/hourly_1991_2020.csv.gz (71's loader), km/h → m/s",
        "thresholds_ms": {k: round(v, 3) for k, v in thresholds.items()},
        "target_hours_per_bin_ours": TARGET_HOURS,
        "power": {"receiver_A": RECEIVER_A, "tss_A": TSS_A, "trs_A": TRS_A, "n_tss": N_TSS, "n_trs": N_TRS,
                  "current_A": round(current_a, 4), "control_ten_tss_60Ah_h": round(ten, 1),
                  "control_paper_h": CHECK_TEN_TSS_H, "usable_fraction_ours": USABLE_FRACTION,
                  "sources": {"receiver_and_tss": "Nickl, Kolbe & Schindler 2022, HardwareX 12, e00379 (PMC9685482)",
                              "trs": "Kolbe & Schindler 2021, HardwareX 9, e00180 (PMC9041182)"}},
        "battery_days": battery_days,
        "by_month": by_month,
        "best_month_beaufort_5": best, "worst_month_beaufort_5": worst,
        "not_modelled": ["the ERA5 → sub-canopy wind transfer (the campaign measures it)",
                         "whether TARGET_HOURS suffices for the histogram's tail",
                         "interannual spread — per-month figures are 30-year means",
                         "battery derating in cold (USABLE_FRACTION = 1, as the papers' figure)"],
        "verdict": verdict,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for m, r in by_month.items():
        print(f"  {m}: B4 {r['beaufort_4']['hours_per_day']:5.2f} h/d · B5 {r['beaufort_5']['hours_per_day']:5.2f} h/d "
              f"→ {r['beaufort_5']['days_for_target']} d ({r['beaufort_5']['visits_60Ah']} / {r['beaufort_5']['visits_100Ah']} visits)")
    print(f"\n  VERDICT: {verdict}")
    banner(f"✅ saved {OUT_JSON.name} · {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
