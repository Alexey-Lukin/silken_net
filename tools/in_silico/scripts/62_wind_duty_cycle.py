#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.43 (checkbox 1) — wind duty-cycle for the Cherkasy pine forest, from open meteorological data.

The cycle count of the anchor stack is built here, in two factors, and neither closes to one number.
FREQUENCY — continuous sway at the fundamental frequency over the service life is an UPPER bound on the
first-mode cycle count, and the frequency itself is a BRACKET of two named field readings of Pinus
sylvestris at one site (`lib/constants.py` SWAY_F0_HZ_*, canon 01_02 §2.2): 0.26–0.312 Hz (Kolbe &
Schindler 2021; Nickl et al. 2022) and 0.74 Hz (Schindler & Kolbe 2020). The texts name no cause for the
2.4–2.8x gap, so the high reading is the ceiling any consumer takes, carried with its source. ⛔ The canon's
1–5 Hz band is a BENCH frequency with no field reading behind it, so no budget is counted at it.
DUTY — a tree does not sway continuously; it sways when the wind is strong enough to excite it, and is
comparatively still the rest of the time. That fraction is what the wind data below bounds.

⚠️ 00_06 §0 Validation Gate: this script computes a real fraction from real data, but it does NOT
manufacture the one number the item wants (a single duty-cycle). Two genuine gaps in the open
literature make a point-estimate dishonest, and both are named explicitly rather than absorbed
into a false-precision number (mission_criterion: СЛОВО/КОЛОНКА/ФОЛБЕК — do not invent a value
because the checkbox has a slot for one):

  1. THRESHOLD gap — the wind speed at which a tree trunk's fundamental sway mode is actually
     excited is explicitly "poorly constrained" in peer-reviewed literature (Umlauft et al. 2025,
     Methods in Ecology & Evolution: sensors are insensitive below ~0-2 m/s, but the precise onset
     of resonant excitation "remains poorly constrained and likely varies with species-specific
     traits"). This script uses the WMO Beaufort scale's standard tree/branch-motion descriptions
     as a citable, well-established PROXY anchor (NOT a validated sway-onset criterion): Beaufort 3
     (3.4 m/s, "leaves and small twigs in constant motion"), Beaufort 4 (5.5 m/s, "small branches
     move, raises dust"), Beaufort 5 (8.0 m/s, "small trees in leaf begin to sway").
  2. CANOPY gap — the fetched data is OPEN/10m-reference wind (NASA POWER WS10M), not in-canopy
     trunk-level wind. Forest-interior wind is measurably lower than the open reference, but the
     reduction factor is NOT a clean constant: sub-canopy wind-profile literature (ScienceDirect/
     Wiley/USFS Treesearch, searched 2026-09-09) reports reduction factors that vary by MORE THAN
     4x depending on forest type, height above ground, and the open wind speed itself — "static"
     reduction factors are explicitly flagged in that literature as inadequate. No single number is
     asserted here; the duty-cycle below is therefore an UPPER-BOUND-of-the-upper-bound (computed
     on OPEN wind, which over-counts strong-wind time relative to the sheltered forest interior).

Three bounds travel with every count this script writes (cache `bounds_that_travel`), and a consumer that
quotes a count without them quotes more than was measured: (1) frequency × time bounds FIRST-MODE cycles, not
strain ranges — the largest ranges sit below f0; (2) the canon's host trees are larger than the measured ones;
(3) the two frequency readings disagree and nothing in the sources resolves it.

Source: NASA POWER API (power.larc.nasa.gov), daily WS10M (10m wind speed), Cherkasy coordinates
49.44N 32.06E, 2015-01-01..2024-12-31 (3653 days, fetched 2026-09-09). Raw response committed at
tools/in_silico/data/nasa_power_cherkasy_ws10m_2015_2024.json (network fetch is not CI-reproducible,
so the source file is checked in, not regenerated at run time).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    ANCHOR_SERVICE_LIFE_YEARS,
    CACHE_DIR,
    REPO_ROOT,
    SECONDS_PER_YEAR,
    SWAY_F0_HZ_HIGH_READING,
    SWAY_F0_HZ_LOW_READING,
)
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)
DATA_FILE = REPO_ROOT / "tools/in_silico/data/nasa_power_cherkasy_ws10m_2015_2024.json"

SERVICE_S = ANCHOR_SERVICE_LIFE_YEARS * SECONDS_PER_YEAR
# Continuous sway at f0 for the whole service life — the UPPER bound of the first-mode count (bound 1).
N_CONTINUOUS_LOW_READING = tuple(f * SERVICE_S for f in SWAY_F0_HZ_LOW_READING)
N_CONTINUOUS_CEILING = SWAY_F0_HZ_HIGH_READING * SERVICE_S
READINGS_RATIO = tuple(SWAY_F0_HZ_HIGH_READING / f for f in reversed(SWAY_F0_HZ_LOW_READING))

LOW_READING_SOURCES = [
    "Kolbe S., Schindler D. (2021) TreeMMoSys: A low cost sensor network to measure wind-induced tree "
    "response. HardwareX 9, e00180, doi:10.1016/j.ohx.2021.e00180 — stem tilt, three P. sylvestris "
    "H 17.2-18.0 m / DBH 22.6-25.8 cm, 10 Apr-10 Oct 2020: first vibration mode 0.273 / 0.312 / 0.312 Hz",
    "Nickl J., Kolbe S., Schindler D. (2022) Enhancing TreeMMoSys with a high-precision strain gauge to "
    "measure the wind-induced response of trees down to the ground. HardwareX 12, e00379, "
    "doi:10.1016/j.ohx.2022.e00379 — strain at 2.7 m (H/7), June 2021: f0 = 0.26 Hz",
]
HIGH_READING_SOURCE = (
    "Schindler D., Kolbe S. (2020) Assessment of the Response of a Scots Pine Tree to Effective Wind Loading. "
    "Forests 11, 145, doi:10.3390/f11020145 — one P. sylvestris H 16.8 m / DBH 21.5 cm, 30 Jan 2019: "
    "'The damped fundamental sway frequency of the stem (f0) was determined at 0.74 Hz'"
)
SITE = ("Hartheim forest research site, Univ. Freiburg, southern Upper Rhine Valley, 47°56'04\"N 7°36'02\"E "
        "— the same coordinates in all three texts")

# WMO Beaufort scale anchors (m/s) — the low end of each band, standard/citable, NOT a validated
# sway-onset threshold (see module docstring gap 1).
BEAUFORT_ANCHORS = {
    "Beaufort 3 (leaves/twigs in constant motion)": 3.4,
    "Beaufort 4 (small branches move)": 5.5,
    "Beaufort 5 (small trees begin to sway)": 8.0,
}


def load_daily_ws10m() -> list[float]:
    d = json.loads(DATA_FILE.read_text())
    ws = d["properties"]["parameter"]["WS10M"]
    vals = [v for v in ws.values() if isinstance(v, (int, float)) and v > -900]
    if len(vals) < 3000:
        raise RuntimeError(f"Expected ~3653 daily values, got {len(vals)} — source file truncated?")
    return vals


def main() -> int:
    banner("HW.43 — wind duty-cycle for Cherkasy pine forest (checkbox 1)")
    vals = load_daily_ws10m()
    n = len(vals)
    print(f"  Source: NASA POWER WS10M, Cherkasy 49.44N 32.06E, {n} daily means (2015-2024)")
    print(f"  Daily-mean wind speed: min {min(vals):.2f} · mean {sum(vals) / n:.2f} · max {max(vals):.2f} m/s\n")

    banner("Frequency — a bracket of two named field readings (lib/constants.py, canon 01_02 §2.2)")
    lo_n, hi_n = N_CONTINUOUS_LOW_READING
    print(f"  low reading  {SWAY_F0_HZ_LOW_READING[0]}–{SWAY_F0_HZ_LOW_READING[1]} Hz → "
          f"{lo_n:.3e}–{hi_n:.3e} cycles of continuous sway over {ANCHOR_SERVICE_LIFE_YEARS:g} yr")
    print(f"  high reading {SWAY_F0_HZ_HIGH_READING} Hz → {N_CONTINUOUS_CEILING:.3e} cycles (the ceiling)")
    print(f"  the readings differ {READINGS_RATIO[0]:.2f}–{READINGS_RATIO[1]:.2f}x at one site; no source names why\n")

    banner("Exceedance fraction at Beaufort anchors (OPEN/10m reference — see gap 2, canopy)")
    rows = []
    for label, thresh in BEAUFORT_ANCHORS.items():
        frac = sum(1 for v in vals if v >= thresh) / n
        n_ceiling = N_CONTINUOUS_CEILING * frac
        n_low = [round(x * frac, -4) for x in N_CONTINUOUS_LOW_READING]
        print(f"  {label:<42s} >= {thresh:4.1f} m/s: {frac * 100:5.1f}% of days -> N_eff <= {n_ceiling:.2e} "
              f"at the ceiling, {n_low[0]:.2e}–{n_low[1]:.2e} at the low reading "
              f"(if EVERY exceeding day swayed continuously)")
        rows.append({"anchor": label, "threshold_ms": thresh, "exceedance_fraction": round(frac, 4),
                     "n_eff_cycles_upper_bound": round(n_ceiling, -4),
                     "n_eff_cycles_at_low_reading": n_low})

    generous = rows[0]
    bounds = [
        ("(1) frequency x time counts continuous oscillation at f0, so it bounds FIRST-MODE cycles and is not a "
         "count of strain ranges: the strain spectrum's first maxima sit at 0.04-0.05 Hz, below f0 (Nickl et al. "
         "2022), and for its sample tree the maximum wind-induced response is quasi-static rather than the dynamic "
         "reaction near f0 (Schindler & Kolbe 2020). The honest budget is a histogram of strain ranges at anchor "
         "height, measured for no P. sylvestris."),
        ("(2) the canon's host trees (DBH >= 38 cm) are larger than every measured tree (DBH 21.5-25.8 cm); the "
         "natural sway frequency is linear in DBH/H^2 (Moore & Maguire 2004), so a larger DBH raises it and a "
         "taller tree lowers it — the hosts' frequency is extrapolated, and its direction is not fixed without "
         "their height."),
        (f"(3) the two readings come from one group at one site on trees of one size and differ "
         f"{READINGS_RATIO[0]:.1f}-{READINGS_RATIO[1]:.1f}x; both measured STEM motion (tilt, orientation), so "
         f"'stem vs whole tree' does not separate them; the dates (one January day vs a summer half-year) and the "
         f"methods differ, and neither text names a cause — so the ceiling is the high reading, carried with its "
         f"source, until a measurement resolves it."),
    ]

    banner("Verdict")
    print("  This does NOT produce the single duty-cycle number the checkbox asks for — two named")
    print("  literature gaps (sway-onset threshold poorly constrained; canopy wind-reduction factor")
    print("  varies >4x, not a constant) make a point estimate dishonest (00_06 §0).")
    print("  What IS established, on real open data: even the MOST GENEROUS bracket (open/10m wind,")
    print(f"  lowest Beaufort anchor {generous['threshold_ms']} m/s) keeps {generous['exceedance_fraction'] * 100:.0f}% "
          f"of days, i.e. N_eff <= {generous['n_eff_cycles_upper_bound']:.2e} at the frequency ceiling")
    print("  before canopy attenuation is applied (which can only shrink it further).")
    for b in bounds:
        print(f"  {b}")

    budget_basis = (f"{ANCHOR_SERVICE_LIFE_YEARS:g} yr of continuous sway at the high f0 reading "
                    f"{SWAY_F0_HZ_HIGH_READING} Hz (Schindler & Kolbe 2020) — the ceiling of the frequency x time "
                    f"form, script 62")
    out = {
        "method": "exceedance-fraction of real 10-year daily-mean open/10m wind speed (NASA POWER) "
                  "against WMO Beaufort-scale tree-motion anchors, used as a citable proxy for a "
                  "sway-onset threshold that the peer-reviewed literature reports as poorly constrained; "
                  "multiplied by continuous sway at a bracket of two named field frequency readings.",
        "service_life_years": ANCHOR_SERVICE_LIFE_YEARS,
        "sway_frequency": {
            "site": SITE,
            "low_reading_hz": list(SWAY_F0_HZ_LOW_READING),
            "low_reading_sources": LOW_READING_SOURCES,
            "high_reading_hz": SWAY_F0_HZ_HIGH_READING,
            "high_reading_source": HIGH_READING_SOURCE,
            "readings_ratio_x": [round(r, 2) for r in READINGS_RATIO],
            "cause_named_by_sources": False,
            "bench_band_note": "1-5 Hz (01_02 §2.2) is a BENCH frequency with no field reading; no budget is counted at it",
        },
        "budget_cycles_upper_bound": round(N_CONTINUOUS_CEILING, -4),
        "budget_basis": budget_basis,
        "budget_cycles_at_low_reading": [round(x, -4) for x in N_CONTINUOUS_LOW_READING],
        "bounds_that_travel": bounds,
        "n_days": n,
        "daily_ws10m_ms": {"min": round(min(vals), 2), "mean": round(sum(vals) / n, 2), "max": round(max(vals), 2)},
        "beaufort_exceedance": rows,
        "gaps": {
            "sway_onset_threshold": "poorly constrained in peer-reviewed literature (Umlauft et al. 2025) "
                                     "— Beaufort anchors are a standard PROXY, not a validated criterion.",
            "canopy_attenuation": "sub-canopy wind reduction factor varies >4x by forest type/height/"
                                   "open-wind-speed (ScienceDirect/Wiley/USFS Treesearch, no single "
                                   "constant is defensible) — this computation uses OPEN/10m wind, which "
                                   "OVER-states in-canopy duty cycle, so the printed N_eff values are "
                                   "themselves upper bounds, not the true budget.",
        },
        "verdict": (f"Duty cycle NOT closed to a single number (two named open literature gaps), and the frequency it "
                    f"multiplies is a bracket of two named readings. Continuous sway over "
                    f"{ANCHOR_SERVICE_LIFE_YEARS:g} yr gives {lo_n:.2e}-{hi_n:.2e} cycles at the low reading and "
                    f"{N_CONTINUOUS_CEILING:.2e} at the high one; the most generous Beaufort bracket keeps "
                    f"{generous['exceedance_fraction'] * 100:.0f}% of days, i.e. N_eff <= "
                    f"{generous['n_eff_cycles_upper_bound']:.2e} at the ceiling. Every count is an upper bound on "
                    f"first-mode cycles, not a strain-range count (bounds_that_travel). Closure needs an in-stand "
                    f"anemometer at trunk height, a species-specific sway-onset study and a strain-range histogram "
                    f"at anchor height — none exists in open literature."),
        "source_file": "tools/in_silico/data/nasa_power_cherkasy_ws10m_2015_2024.json",
        "source_url": "https://power.larc.nasa.gov/api/temporal/daily/point?parameters=WS10M&community="
                       "RE&longitude=32.06&latitude=49.44&start=20150101&end=20241231&format=JSON",
        "fetched": "2026-09-09",
    }
    json_path = OUT_DIR / "wind_duty_cycle.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    return 0  # literature+data review: no pass/fail gate, exit 0 = ran to completion


if __name__ == "__main__":
    raise SystemExit(main())
