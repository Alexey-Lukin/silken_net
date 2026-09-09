#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.43 (checkbox 1) — wind duty-cycle for the Cherkasy pine forest, from open meteorological data.

Without this, N = 6.3e8 cycles (HW.43 head: 20 yr x 1 Hz trunk sway, 01_02 §2.2 lower bound of the
canon's 1-5 Hz range) is an UPPER BOUND, not a budget — a tree does not sway continuously; it sways
when the wind is strong enough to excite it, and is comparatively still the rest of the time.

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

Bottom line this script DOES establish, honestly: even on the OPEN/10m reference (the more
generous of the two gaps, i.e. this OVER-states duty cycle), the fraction of time wind exceeds
even the LOWEST Beaufort anchor is well under 1 — so 6.3e8 is confirmed to be a real overcount,
by at least the printed factor, and the true number is bounded further down by the (unquantified)
canopy attenuation. That is the closed-form contribution; a single duty-cycle number is NOT.

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
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)
DATA_FILE = REPO_ROOT / "tools/in_silico/data/nasa_power_cherkasy_ws10m_2015_2024.json"

N_BUDGET_CYCLES = 6.3e8

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

    banner("Exceedance fraction at Beaufort anchors (OPEN/10m reference — see gap 2, canopy)")
    rows = []
    for label, thresh in BEAUFORT_ANCHORS.items():
        frac = sum(1 for v in vals if v >= thresh) / n
        n_eff = N_BUDGET_CYCLES * frac
        print(f"  {label:<42s} >= {thresh:4.1f} m/s: {frac * 100:5.1f}% of days -> "
              f"N_eff <= {n_eff:.2e} (if EVERY exceeding day swayed the full 1Hz budget)")
        rows.append({"anchor": label, "threshold_ms": thresh, "exceedance_fraction": round(frac, 4),
                     "n_eff_cycles_upper_bound": round(n_eff, -4)})

    banner("Verdict")
    print("  This does NOT produce the single duty-cycle number the checkbox asks for — two named")
    print("  literature gaps (sway-onset threshold poorly constrained; canopy wind-reduction factor")
    print("  varies >4x, not a constant) make a point estimate dishonest (00_06 §0).")
    print("  What IS established, on real open data: even the MOST GENEROUS bracket (open/10m wind,")
    print(f"  lowest Beaufort anchor 3.4 m/s) gives a duty cycle of only {rows[0]['exceedance_fraction']*100:.0f}%,")
    print(f"  i.e. N_eff <= {rows[0]['n_eff_cycles_upper_bound']:.2e} even before canopy attenuation is")
    print("  applied (which can only shrink this further, per the >4x-variable literature above).")
    print("  So 6.3e8 is CONFIRMED to overstate the real budget by at least this factor; closing the")
    print("  checkbox to a single number needs either a field anemometer INSIDE the Cherkasy stand at")
    print("  trunk height, or a species-specific sway-onset study — neither exists in open literature.")

    out = {
        "method": "exceedance-fraction of real 10-year daily-mean open/10m wind speed (NASA POWER) "
                  "against WMO Beaufort-scale tree-motion anchors, used as a citable proxy for a "
                  "sway-onset threshold that the peer-reviewed literature reports as poorly constrained.",
        "budget_cycles_upper_bound": N_BUDGET_CYCLES,
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
        "verdict": "Duty cycle NOT closed to a single number (two named open literature gaps). Confirmed: "
                   "even the most generous bracket bounds N_eff well under the 6.3e8 upper bound — exact "
                   "closure needs an in-stand anemometer at trunk height (bench/field) or a species-"
                   "specific sway-onset study, neither of which exists in open literature today.",
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
