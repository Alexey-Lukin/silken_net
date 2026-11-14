#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""124 — the stem-face light logger under a SECOND sky: the south face lit by the CERES SYN1deg sky (NASA POWER hourly)
and judged, as the sheet prescribes, against ERA5's GHI — what the disagreement of two sky products alone does to the
daily ratio, to the dip rules with a base estimated from the record, and to the seasonal R (00_07 HW.54, the leg
«Р3(б)(4) — переписати правила розбору покриву ДО даних», stage 1: the estimated base from both sides; the sheet
`docs/protocols/ebfc/stem_face_winter_light.md` §6).

WHY. Since 2026-11-09 the logger has no on-site reference: R is the face's daily light over ERA5's GHI of that day
(01_03 §4, ⊕ under Р3(б)(4); the named price — «R по днях шумніше (комірка ERA5 — не двір)»). Every rehearsal of the
cover rules so far (`117`, `118`) lit the face with the same ERA5 it divided by, so the sky's own error was absent by
construction, and the noise the rejected rule sets were tuned against (σ 0.1–0.3, one seed) had no source. This script
lights the face with a second estimate of the same sky and keeps ERA5 as the divisor and as the analyst's world.
⚠️ A reading, not a bound. CERES is itself a computed product on a coarser cell with an hourly error of its own (the
data README), and the yard differs from both; the disagreement of two gridded estimates bounds the error of neither.

MODEL.
  THE WORLDS, one divisor. A world is (the sky that lights the face, the air the truth's cover runs on, the air the
    analyst's reading runs on). The sky is ERA5 + α · (product − ERA5), column by column (DNI, diffuse, GHI), under
    `79`'s sun, face factors and albedo ends: α 0 is ERA5 itself, α 1 the product, α 1/√2 the share that is ERA5's own if
    the two products err independently and equally — three NAMED readings of a split nobody here has measured. ⚠️ The
    middle one reproduces a VARIANCE only: a linear mix cannot take a day below 1 − 1/√2 = 0.29 of its ERA5-lit light,
    so it can say nothing about dips at a threshold of 0.3 or deeper (its zeros there are the construction's). The air
    is ERA5's, or MERRA-2's 2 m temperature and dew point at the same point (the columns of
    `data/power_cherkasy_longwave/`; colder than ERA5's in winter by the mean control 5 records). That file's humidity
    column is a «Dew/Frost Point» whose meaning below 0 °C its header does not settle, and the cover's channel under a
    colder air is hoarfrost — so the column is carried in BOTH readings, as `120` and `122` do: «merra2» reads it as a
    dew point over water (the moister reading), «merra2_frost» as a frost point below 0 °C (`120`'s conversion). The worlds:
      «era5»             α 0, ERA5 air both sides — the rehearsals' world: only the base's own error;
      «half» · «ceres»   α 1/√2 · 1, ERA5 air both sides — the second sky, at two shares;
      «ceres_cold_truth» α 1, the truth on MERRA-2 air, the analyst on ERA5 air — the sheet's p.7 as written («`115`
                         проганяється на ERA5») in a yard whose air is not the cell's;
      «ceres_cold_both» · «era5_cold_both»  the same colder air under truth AND analyst, hour for hour — the CEILING
                         of what an analyst on the yard's own air could gain, not what a sensor gains: no sensor
                         error, no difference between the air at the logger and the air that drives the cover;
      «ceres_frost_both» · «era5_frost_both»  the same, on the frost-point reading of the humidity column.
    In every world R_d = Σ face / Σ GHI_ERA5 over the day (the sheet's p.1), a day with ΣGHI_ERA5 < 0.1 kWh/m² is not
    judged, and the analyst lights its readings with ERA5 — the only sky it has.
  COVER. Truth T ∈ {none, the four `115` readings}: `115`'s `cover_readings` (the ONE home of the cover model) run on
    the WORLD's face light and the truth's air — so the truth's clearing follows the world's sky. The analyst runs each
    reading Y on ERA5's sky and its own air: the mismatch of timing between truth and analyst is the worlds', not a
    synthetic shift. Wind, cloud for the sky's emission and snow are ERA5's in every world.
  THE BASE THE RECORD OFFERS — the sheet's p.4 without its candidate-day exclusion (which `117` measured to remove
    almost the whole winter): the median R of the other judged days within ±15 days, of the same ground state (p.2) and
    the same tercile of ERA5's daily diffuse fraction (terciles over the season's judged days, per ground state); fewer
    than 5 such days — ±30; still fewer — the day has no base and neither starts, continues nor breaks a run.
  A DIP at threshold θ — R_d < θ · base; a RUN — consecutive based days in a dip (the «runs» episodes of `118`).
  THE COVERAGE TEST (the leg's requirement (2)) — a run is a MISS of reading Y when Y's own transmitted share on ERA5
    stays ≥ 0.5 on every day of the run and of the `tol` days either side (tol 0 · 1 — the ±1-day axis the leg asks
    for); Y is rejected in a winter with ≥ k misses (k 1 · 2 · 3).
  FALSE ⊥ NOT-PROVEN-FALSE rejections. The record is a lower bound on cover, so the test may only reject a reading that
    gives LESS cover than was recorded. A rejection of Y under truth T is FALSE when Y is T, when T is «none», or when Y
    covers every hour T covers in the analyst's run (the containment `118` asserts). Every other rejection is counted as
    «not proven false» — the flag sits on the PAIR, not on the run, so such a rejection can still rest on runs the
    truth's cover did not make (sky-made dips where the lighter reading has no cover); it is an upper count of power.
  THE RULE OF TWO AIRS (added 2026-11-14 for the rewrite of the sheet's pp. 3–7). The analyst the season will have
    holds exactly two airs: ERA5's and the logger's own. Three rules are scored at θ 0.1 and 0.15, tol 1, k 2: reject
    on ERA5's air alone · on the logger's air alone · only when BOTH reject. The truth's air runs over ERA5's,
    MERRA-2's in both readings of its humidity column, and ERA5's warmed by 1 and 2 K on temperature and dew point
    alike (a yard warmer than the cell, with the cell's snow, cloud and wind). The logger's air is the TRUTH's air
    with a sensor error, on three axes — each grants that the air at the logger IS the air that drives the cover,
    which nothing here tests, and no cell has both airs away from the cover's:
      «d»    a constant offset on temperature and dew point alike (−1 … +1 K) — it keeps the dew-point deficit, so
             the logger's humidity is exact on it (asserted);
      «dew»  a constant offset on the dew point alone (−2 · −1 · +1 K; capped at the air) — a humidity sensor's
             error, added after this block's adversary showed the first axis was blind to it;
      «other_humidity_reading»  on MERRA-2's air, the humidity column read the OTHER way (dew ⊥ frost point) — a
             named reading, not a typed offset.
    A rejection is PROVEN false on the air whose run shows the containment (the readings' nesting is not the same on
    every air — it fails on the warmed ones, recorded); under «both» it is proven false when either air proves it.
    Counts are kept per winter and per reading; for the truth's own runs missed on both airs with no sensor error, the
    days are sorted by what stood over them (the truth's cover · no cover · the product's sky under half of ERA5's).

DECLARED BEFORE THE RUN. The θ grid (0.5 · 0.3 · 0.2 · 0.15 · 0.1 · 0.05), tol and k above; the seasons are the product's
nineteen full Dec–Feb seasons (2002–2020), split odd ⊥ even as the held-out axis (#56); no synthetic noise is added and
no threshold is tuned here — the numbers are printed for every grid point, and a sentence built on them names the grid.
The α and air axes were added after the first version's adversary (2026-11-14) showed that its conclusions moved with
both; their values (1/√2; MERRA-2 as the one second air in the tree) were fixed before their run.

WHAT IT CANNOT SEE. The yard against either cell (a crown, the house, point-against-area scatter — all of which add to
what is printed), the product's own error (which subtracts from what ERA5 alone would cause), sensor errors other than
a constant offset on temperature and dew point, a logger whose air is not the air that drives the cover, cosine and
spectral errors, the logger's clock, fog and rime, a second wind and a second long-wave sky (the air axis swaps the
2 m temperature and dew point only, and MERRA-2 is a cell too — under a crown the nights may as well be warmer), the
product's «Dew/Frost Point» taken as a dew point, the hybrid reading, the decisions other than coverage (dry snow;
clearing), a real on-site reference (a horizontal logger knows the global flux only and is covered by the same snow —
the «era5» world is kinder than it), and rules other than these (another base, hourly signatures).

CONTROLS (each says what it CAN and CANNOT catch).
  (1) The correlation of ERA5's GHI with the product's over row lags −1…+3 peaks at the applied lag; CAN catch a clock
      shift of a whole hour, CANNOT a sub-hour one.
  (2) The product's DNI · cos(zenith) + diffuse closes on its own global flux under this script's sun (median within
      2 %); CAN catch a wrong column, unit or sun, CANNOT the product's cloud error.
  (3) In the «era5» world the cover-free judged days per winter and truth equal `118`'s cached counts for the same
      seasons; CAN catch a wrong face, end, cover call or day rule, CANNOT an error both scripts share.
  (4) The run function on a synthetic winter gives the right days, and equals `118`'s at θ 0.5; the base and tercile
      functions return hand-computed medians on a synthetic season (window, stratum, leave-one-out, the dark-pool and
      too-few-days branches); the miss function counts hand-placed runs at tol 0 and 1; CAN catch an off-by-one, a
      based-day rule, a wrong window, stratum or day index, CANNOT a wrong threshold value.
  (5) The second air correlates with ERA5's above 0.98 hour by hour and its dew point lies below its own temperature
      on average (it exceeds it in a few percent of hours — an hour's-mean artefact, capped at the air as `122` does,
      the share recorded); the mean of ERA5's air minus it is recorded over all hours and over the seasons' DJF hours
      (`120` reports the same difference on ITS rows — winter frost hours — where it is larger); CAN catch a swapped or
      foreign column and a gross clock error, CANNOT say which air is the yard's.
  (6) The two-air block: at no sensor error its outcomes AND its count of winters the truth is rejected are the
      worlds' own (ERA5's air alone is «era5» · «ceres» · «ceres_cold_truth», the logger's alone the «…_both» worlds;
      the other-humidity logger alone under «both»-air truth is checked the same way where a world exists); on ERA5's
      air warmed by 1 K with the logger 1 K low the logger IS ERA5 and the three rules agree; «both» never rejects a
      reading in more winters than either single rule; the «d» axis keeps the dew-point deficit and the «dew» axis the
      temperature. CAN catch a wrong run, base, miss, flag or truth count, an «or» for the «and», a shift of the wrong
      sign or column; CANNOT an error the worlds share, nor a wrong count at a sensor error no world carries.
  One code path builds every world's face from α, so control (3) on α 0 covers the composition of all of them; at α 1
  the mixed sky is the product's columns exactly (asserted).
"""

from __future__ import annotations

import gzip
import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import KINETICS_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("A light logger on a pine stem's south face under a second sky: the face lit by a satellite-based "
                  "surface-irradiance product and judged against reanalysis irradiance — the false light dips, the "
                  "rejections of snow- and hoarfrost-cover models and the seasonal ratio that the disagreement of the "
                  "two sky estimates alone produces, over 19 winters.")

HERE = Path(__file__).resolve().parent
OUT = KINETICS_DIR / "stem_face_second_sky.json"
P118 = KINETICS_DIR / "stem_face_cover_power.json"
DATA_FILE = REPO_ROOT / "tools/in_silico/data/power_cherkasy_shortwave/hourly_2001_2020.csv.gz"
COLUMNS = ["YEAR", "MO", "DY", "HR", "ALLSKY_SFC_SW_DWN", "ALLSKY_SFC_SW_DNI", "ALLSKY_SFC_SW_DIFF", "CLRSKY_SFC_SW_DWN"]
PRODUCT_STAMP_LAG_H = 1                     # the product's stamp is the START of its hour; an ERA5 row is the hour ENDING at it
LAGS = (-1, 0, 1, 2, 3)
MONTHS = (12, 1, 2)
SEASONS = (2002, 2020)                      # the product's 19 full Dec–Feb seasons (Dec 2001 … Feb 2020)
AIR_FILE = REPO_ROOT / "tools/in_silico/data/power_cherkasy_longwave/hourly_2001_2020.csv.gz"
AIR_COLUMNS = ["YEAR", "MO", "DY", "HR", "ALLSKY_SFC_LW_DWN", "CLRSKY_SFC_LW_DWN", "T2M", "T2MDEW", "CLOUD_AMT"]
READINGS = ("ceiling", "melt_only", "nrel_published", "favourable_end")
TRUTHS = ("none", *READINGS)
ALPHA_EQUAL_SPLIT = 2.0 ** -0.5             # ERA5's share of the disagreement if the two products err independently and equally
WORLDS = {                                  # (α of the sky, the truth's air, the analyst's air)
    "era5": (0.0, "era5", "era5"),
    "half": (ALPHA_EQUAL_SPLIT, "era5", "era5"),
    "ceres": (1.0, "era5", "era5"),
    "ceres_cold_truth": (1.0, "merra2", "era5"),
    "ceres_cold_both": (1.0, "merra2", "merra2"),
    "era5_cold_both": (0.0, "merra2", "merra2"),
    "ceres_frost_both": (1.0, "merra2_frost", "merra2_frost"),
    "era5_frost_both": (0.0, "merra2_frost", "merra2_frost"),
}
DETAIL_WORLDS = ("era5", "ceres")           # the worlds whose per-winter rows the cache keeps
AIR_MIN_CORRELATION = 0.98                  # control 5
GHI_MIN_KWH = 0.1                           # the sheet's p.1
GROUND_EDGES_M = (0.01, 0.11)               # the sheet's p.2 (`79`'s REFLECT_ENDS depths)
WINDOWS_D = (15, 30)                        # the sheet's p.4
BASE_MIN_DAYS = 5                           # the sheet's p.4
THETAS = (0.5, 0.3, 0.2, 0.15, 0.1, 0.05)   # declared before the run; 0.5 is the sheet's p.5
COVERED = 0.5                               # a day «covered» by reading Y below this share (`118`)
FREE = 0.8                                  # a day the truth leaves free of cover (`118`'s CONT)
TOLS = (0, 1)
KS = (1, 2, 3)
# the rule of two airs (declared before its run, 2026-11-14)
RULE_SKIES = {"era5": 0.0, "ceres": 1.0}
RULE_THETAS = (0.1, 0.15)
RULE_TOL, RULE_K = 1, 2
SENSOR_OFFSETS_K = (-1.0, -0.5, 0.0, 0.5, 1.0)
DEW_OFFSETS_K = (-2.0, -1.0, 1.0)            # on the dew point alone
OTHER_HUMIDITY = {"merra2": "merra2_frost", "merra2_frost": "merra2"}
WARM_YARD_K = (1.0, 2.0)
RULES = ("era5_alone", "logger_alone", "both")
CLOSURE_MIN_W = 50.0
CLOSURE_TOL = 0.02


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S118 = _load("s118_second_sky", "118_stem_face_cover_power.py")
S120 = _load("s120_second_sky", "120_sky_longwave_product.py")          # frost_point_as_dew_point — the ONE home of that reading
S115 = S118.S115
S110, S79, S71 = S115.S110, S115.S79, S115.S71


def load_power(path: Path, columns: list, take: dict) -> dict:
    """A NASA POWER hourly file on its own UTC clock; refuses another column set or a missing value. `take` maps a
    name to a column index."""
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        head = fh.readline().strip().split(",")
        rows = np.loadtxt(fh, delimiter=",")
    if head != columns:
        raise SystemExit(f"{path.name}: columns are {head}, not {columns}")
    if np.any(rows[:, 4:] <= -999.0):
        raise SystemExit(f"{path.name}: a missing value (-999) — the series is not whole")
    utc = np.array([f"{int(y):04d}-{int(m):02d}-{int(d):02d}T{int(h):02d}" for y, m, d, h in rows[:, :4]],
                   dtype="datetime64[h]")
    return {"utc": utc, **{name: rows[:, col] for name, col in take.items()}}


def on_model_clock(prod: dict, times_h: np.ndarray, offset_h: int, lag_h: int) -> dict:
    """The product's columns on the ERA5 rows (NaN where the product has no hour): a product hour stamped H (UTC, the
    START of its hour) lands on the model row `lag_h` hours after that instant on the model's clock."""
    at = prod["utc"] + np.timedelta64(offset_h + lag_h, "h")
    pos = np.searchsorted(times_h, at)
    ok = (pos < len(times_h)) & (times_h[np.minimum(pos, len(times_h) - 1)] == at)
    out = {}
    for key in prod:
        if key == "utc":
            continue
        col = np.full(len(times_h), np.nan)
        col[pos[ok]] = prod[key][ok]
        out[key] = col
    return out


def misses(runs: list, covered: np.ndarray, tol: int) -> int:
    """The runs (lists of day indices on `covered`'s own axis) on none of whose days, nor of the `tol` days either
    side, the reading covers the face."""
    return sum(not np.any(covered[max(run[0] - tol, 0):run[-1] + tol + 1]) for run in runs)


def runs_below(ratio: np.ndarray, theta: float) -> list:
    """Consecutive based days (ratio not NaN) below θ; a day without a base neither continues nor breaks a run."""
    runs, cur = [], None
    for d, r in enumerate(ratio):
        if np.isnan(r):
            continue
        if r < theta:
            cur = [d] if cur is None else [*cur, d]
        elif cur is not None:
            runs.append(cur)
            cur = None
    if cur is not None:
        runs.append(cur)
    return runs


def control_runs() -> None:
    s = np.array([1.0, 0.4, 0.7, np.nan, 0.9, 0.3, 0.45, 1.0, 0.2, np.nan, 0.1])
    assert runs_below(s, 0.5) == [[1], [5, 6], [8, 10]], runs_below(s, 0.5)       # a NaN day neither continues nor breaks
    assert runs_below(s, 0.25) == [[8, 10]], runs_below(s, 0.25)
    share = np.array([1.0, 0.4, 0.7, 0.1, 0.9, 0.3, 0.45, 1.0])
    judged = np.array([True, True, True, False, True, True, True, True])
    assert runs_below(np.where(judged, share, np.nan), S118.DIP) == S118.episodes_runs(share, judged), "control 4"
    # misses: a reading that covers day 4 only — the run [5, 6] is a miss at tol 0, covered at tol 1; [1] a miss at both
    cov = np.zeros(12, bool)
    cov[4] = True
    assert misses([[1], [5, 6]], cov, 0) == 2 and misses([[1], [5, 6]], cov, 1) == 1 and misses([[3]], cov, 1) == 0
    assert misses([[0]], cov, 1) == 1 and misses([[11]], cov, 1) == 1                # the axis ends


def control_base() -> None:
    """Hand-computed medians on a synthetic season of 40 days: the stratum (ground state × diffuse tercile), the ±15
    then ±30 window, leave-one-out, the dark-pool and the too-few-days branches."""
    n = 40
    jd = np.arange(n)
    ground = np.zeros(n, int)
    ground[30:] = 2                                               # ten days on snow: their own tercile edges
    dif = np.concatenate([np.tile([0.1, 0.5, 0.9], 10), np.tile([0.15, 0.55, 0.95], 4)[:10]])   # clear of the tercile edges
    terc = terciles(jd, ground, dif, n)
    assert list(terc[:6]) == [0, 1, 2, 0, 1, 2] and list(terc[30:33]) == [0, 1, 2], terc
    r = np.arange(n, dtype=float) + 1.0
    base = base_from_record(r, jd, ground, terc)
    # day 0: stratum = bare ground, tercile 0 → days 3, 6, …, 27; within ±15: 3, 6, 9, 12, 15 → r 4, 7, 10, 13, 16 → 10
    assert base[0] == 10.0, base[0]
    # day 15 (tercile 0): days 0, 3, 6, 9, 12, 18, 21, 24, 27 within ±15, itself left out → median of r = 13
    assert base[15] == 13.0, base[15]
    # day 30 (snow, tercile 0): its stratum holds days 33, 36, 39 only — fewer than 5 in either window → no base
    assert np.isnan(base[30]), base[30]
    dark = r.copy()
    dark[[3, 6, 9, 12, 15]] = 0.0                                 # day 0's whole pool dark → no base
    assert np.isnan(base_from_record(dark, jd, ground, terc)[0])
    far = base_from_record(r, jd[[0, 18, 21, 24, 27, 30]], ground, terc)
    # day 0 with a pool only beyond ±15 (18, 21, 24, 27): four days in ±30 → fewer than 5 → no base
    assert np.isnan(far[0]), far[0]
    # the ±30 branch GIVING a base: day 0 with tercile-0 days 3, 6 in ±15 (two — too few) and 18, 21, 24 more in ±30 →
    # five days, r = 4, 7, 19, 22, 25 → median 19; a window of 20 or 16 instead of 30 would leave fewer than five
    wide = base_from_record(r, jd[[0, 3, 6, 18, 21, 24]], ground, terc)
    assert wide[0] == 19.0, wide[0]


def terciles(jd: np.ndarray, ground: np.ndarray, dif_frac: np.ndarray, n_days: int) -> np.ndarray:
    """The tercile (0 · 1 · 2) of ERA5's daily diffuse fraction among the season's judged days of the same ground state."""
    terc = np.full(n_days, -1)
    for state in (0, 1, 2):
        dd = jd[ground[jd] == state]
        if len(dd):
            edges = np.percentile(dif_frac[dd], [100.0 / 3.0, 200.0 / 3.0])
            terc[dd] = np.searchsorted(edges, dif_frac[dd], side="right")
    return terc


def base_from_record(r: np.ndarray, jd: np.ndarray, ground: np.ndarray, terc: np.ndarray) -> np.ndarray:
    """The sheet's p.4 on the record itself, leave-one-out, without the candidate-day exclusion; NaN where no window
    holds BASE_MIN_DAYS days."""
    base = np.full(len(r), np.nan)
    for d in jd:
        same = (jd != d) & (ground[jd] == ground[d]) & (terc[jd] == terc[d])
        for window in WINDOWS_D:
            pool = jd[same & (np.abs(jd - d) <= window)]
            if len(pool) >= BASE_MIN_DAYS:
                med = float(np.median(r[pool]))
                base[d] = med if med > 0.0 else np.nan      # a pool that is dark at its median offers no base
                break
    return base


def main() -> int:
    banner("HW.54 Р3(б)(4) — the stem-face logger under a second sky (CERES SYN1deg via NASA POWER) judged against ERA5")
    control_runs()
    control_base()
    wx = S79.load_weather()
    times_h = np.asarray(wx["time"]).astype("datetime64[h]")
    st = S79.site()
    offset_h = round(st["utc_offset_h"])
    sun = S79.sun_enu(wx["time"], st)
    gc, _ = S79.face_factors(sun)
    cosz = np.maximum(sun[2], 0.0).mean(axis=1)
    _, ghi_e = S110.irradiance(wx, sun, gc)
    snow = S79.load_snow(wx["time"])
    ends = [e[0] for e in S79.REFLECT_ENDS]
    j180 = list(S79.AZIMUTHS_DEG).index(180)
    d_dome = S71.geometry()["dome_diameter_mm"] / 1000.0

    # the product on the model's clock — control (1)
    prod = load_power(DATA_FILE, COLUMNS, {"dwn": 4, "dni": 5, "dif": 6})
    by_lag = {}
    for lag in LAGS:
        c = on_model_clock(prod, times_h, offset_h, lag)
        m = np.isfinite(c["dwn"]) & ((ghi_e > 0) | (c["dwn"] > 0))
        by_lag[lag] = float(np.corrcoef(ghi_e[m], c["dwn"][m])[0, 1])
    best = max(by_lag, key=by_lag.get)
    if best != PRODUCT_STAMP_LAG_H:
        raise SystemExit(f"control 1: the best row lag is {best}, not the applied {PRODUCT_STAMP_LAG_H} — {by_lag}")
    cp = on_model_clock(prod, times_h, offset_h, PRODUCT_STAMP_LAG_H)
    have = np.isfinite(cp["dwn"])
    # control (2): the product's components close on its own global flux under this script's sun
    m = have & (cp["dwn"] > CLOSURE_MIN_W)
    closure = (cp["dni"][m] * cosz[m] + cp["dif"][m]) / cp["dwn"][m]
    closure_median = float(np.median(closure))
    if abs(closure_median - 1.0) > CLOSURE_TOL:
        raise SystemExit(f"control 2: DNI·cos z + DIF over DWN has a median of {closure_median:.4f}")

    # the second air (MERRA-2 2 m temperature and dew point, the same service and clock) — control (5)
    air = on_model_clock(load_power(AIR_FILE, AIR_COLUMNS, {"t": 6, "td": 7}), times_h, offset_h, PRODUCT_STAMP_LAG_H)
    have_air = np.isfinite(air["t"])
    if not np.array_equal(have_air, have):
        raise SystemExit("the air file and the sky file do not cover the same hours")
    air_corr = float(np.corrcoef(wx["t_air"][have], air["t"][have])[0, 1])
    dew_gap = float((air["t"][have] - air["td"][have]).mean())
    dew_above = float(np.mean(air["td"][have] > air["t"][have]))
    if air_corr < AIR_MIN_CORRELATION or dew_gap <= 0.0:
        raise SystemExit(f"control 5: air correlation {air_corr:.4f}, mean temperature minus dew point {dew_gap:.2f} K")
    air_diff = float((wx["t_air"][have] - air["t"][have]).mean())
    # where a product has no hour (before 2001) every world is ERA5's, so the cover model's memory starts sane — those
    # hours lie outside the seasons read
    t_m = np.where(have, air["t"], wx["t_air"])
    td_capped = np.minimum(np.where(have, air["td"], wx["t_dew"]), t_m)
    td_frost = np.where(have, np.minimum(S120.frost_point_as_dew_point(np.where(have, air["td"], 0.0)), t_m), wx["t_dew"])
    wx_air = {"era5": wx, "merra2": {**wx, "t_air": t_m, "t_dew": np.where(have, td_capped, wx["t_dew"])},
              "merra2_frost": {**wx, "t_air": t_m, "t_dew": td_frost}}
    frost_reading_shift = float((td_capped[win_air := have & (t_m < 0.0)] - td_frost[win_air]).mean())
    shift_of = {}

    def shifted(name: str, delta: float) -> str:
        """The name of an air shifted by δ K on temperature and dew point alike («era5+1.5K»)."""
        base, total = shift_of.get(name, (name, 0.0))
        total += delta
        new = base if total == 0.0 else f"{base}{total:+g}K"
        shift_of.setdefault(new, (base, total))
        return new

    dew_of = {}

    def dew_shifted(name: str, delta: float) -> str:
        """The name of an air whose dew point alone is shifted by δ K and capped at the air («merra2dew-1K»)."""
        new = f"{name}dew{delta:+g}K"
        dew_of[new] = (name, delta)
        return new

    def air_of(name: str) -> dict:
        if name not in wx_air:
            if name in dew_of:
                base, delta = dew_of[name]
                wx_air[name] = {**air_of(base), "t_dew": np.minimum(air_of(base)["t_dew"] + delta, air_of(base)["t_air"])}
            else:
                base, total = shift_of[name]
                wx_air[name] = {**wx_air[base], "t_air": wx_air[base]["t_air"] + total, "t_dew": wx_air[base]["t_dew"] + total}
        return wx_air[name]

    def sky(alpha: float):
        """ERA5 + α · (product − ERA5), column by column; ERA5 where the product has no hour."""
        def blend(e, c):                       # the ends exactly, so α 0 and α 1 are the two products bit for bit
            return e if alpha == 0.0 else np.where(have, c if alpha == 1.0 else e + alpha * (c - e), e)
        mix = {k: blend(e, cp[c]) for k, c, e in
               (("dni", "dni", wx["dni"]), ("dif", "dif", wx["dif"]), ("ghi", "dwn", ghi_e))}
        refl = S79.reflected_rows(snow, mix["ghi"])
        face = np.stack([mix["dni"] * gc[j180] + 0.5 * mix["dif"] + 0.5 * refl[k] for k in range(1, len(ends) + 1)], axis=1)
        return mix, face

    skies = {alpha: sky(alpha) for alpha in sorted({w[0] for w in WORLDS.values()})}
    assert np.array_equal(skies[1.0][0]["dni"][have], cp["dni"][have]) and np.array_equal(skies[0.0][0]["ghi"], ghi_e), "α ends"
    snow_season = {"era5_land": snow["era5_land"],
                   "cerra": {**snow["cerra"], "depth_m": np.zeros_like(snow["cerra"]["depth_m"])}}
    cover_cache = {}

    def cover_of(alpha: float, air_name: str):
        if (alpha, air_name) not in cover_cache:
            cover_cache[(alpha, air_name)] = S115.cover_readings(air_of(air_name), skies[alpha][1], snow_season, d_dome)["covers"]
        return cover_cache[(alpha, air_name)]

    # days
    day_str = np.array([str(t)[:10] for t in times_h])
    days, first = np.unique(day_str, return_index=True)
    month = np.array([int(d[5:7]) for d in days])
    year = np.array([int(d[:4]) for d in days])
    season_year = np.where(month == 12, year + 1, year)
    seasons = list(range(SEASONS[0], SEASONS[1] + 1))
    hours_per_day = np.add.reduceat(np.ones(len(times_h)), first)

    def daysum(x):
        return np.add.reduceat(x, first)

    whole = daysum(have.astype(float)) == hours_per_day
    g_e_kwh = daysum(ghi_e) / 1000.0
    g_c_kwh = daysum(skies[1.0][0]["ghi"]) / 1000.0
    judged = (g_e_kwh >= GHI_MIN_KWH) & whole
    safe_g = np.where(g_e_kwh > 0, g_e_kwh, 1.0)
    dif_frac = np.where(g_e_kwh > 0, daysum(wx["dif"]) / 1000.0 / safe_g, 1.0)
    depth = daysum(snow["era5_land"]["depth_m"]) / hours_per_day
    ground = np.where(depth < GROUND_EDGES_M[0], 0, np.where(depth < GROUND_EDGES_M[1], 1, 2))
    sel_of = {sy: np.nonzero(np.isin(month, MONTHS) & (season_year == sy))[0] for sy in seasons}
    jd_of = {sy: sel_of[sy][judged[sel_of[sy]]] for sy in seasons}
    terc_of = {sy: terciles(jd_of[sy], ground, dif_frac, len(days)) for sy in seasons}
    month_h = times_h.astype("datetime64[M]").astype(int) % 12 + 1
    year_h = times_h.astype("datetime64[Y]").astype(int) + 1970
    win_h = np.isin(month_h, MONTHS) & np.isin(np.where(month_h == 12, year_h + 1, year_h), seasons)
    air_diff_winter = float((wx["t_air"][win_h] - air["t"][win_h]).mean())

    def light(alpha: float, air_name: str, truth: str, c: int) -> np.ndarray:
        """The day's face light (kWh/m²) that truth T lets through under that sky and air."""
        keep = 1.0 if truth == "none" else 1.0 - cover_of(alpha, air_name)[truth][0][:, c]
        return daysum(skies[alpha][1][:, c] * keep) / 1000.0

    # the analyst's reading Y: ERA5's sky, the analyst's air — the day's transmitted share, whether Y «covers» the day,
    # and which readings cover every hour another covers (the false-rejection rule)
    analyst = {}

    def analyst_for(air_name: str) -> dict:
        if air_name not in analyst:
            share = {(y, c): np.where(light(0.0, "era5", "none", c) > 0,
                                      light(0.0, air_name, y, c) / np.where(light(0.0, "era5", "none", c) > 0, light(0.0, "era5", "none", c), 1.0),
                                      1.0) for y in READINGS for c in range(len(ends))}
            cov = cover_of(0.0, air_name)
            analyst[air_name] = {
                "share": share, "covered": {k: v < COVERED for k, v in share.items()},
                "contains": {(t, y, c): bool(np.all(cov[y][0][win_h, c] >= cov[t][0][win_h, c] - 1e-12))
                             for t in READINGS for y in READINGS for c in range(len(ends)) if t != y}}
        return analyst[air_name]

    world_airs = sorted({w[2] for w in WORLDS.values()})
    for air_name in world_airs:
        analyst_for(air_name)

    # control (3): the «era5» world's cover-free judged days per winter are 118's
    z118 = json.loads(P118.read_text())
    control3 = 0
    for c, end in enumerate(ends):
        for t in READINGS:
            want = z118["truths"][f"{end}:{t}"]["cover_free_judged_days_per_winter"]
            for sy in seasons:
                got = int(np.sum(analyst["era5"]["share"][(t, c)][jd_of[sy]] >= FREE))
                assert got == want[sy - z118["inputs"]["seasons"][0]], ("control 3", end, t, sy, got)
                control3 += 1

    # A. the sky alone
    sel = np.concatenate([jd_of[sy] for sy in seasons])
    x = np.log(g_c_kwh[sel] / g_e_kwh[sel])
    xc = x - np.median(x)
    sky_alone = {"days": len(sel), "median_ratio_ceres_over_era5": float(np.exp(np.median(x))),
                 "sd_ln": float(x.std()), "mad_sd_ln": float(1.4826 * np.median(np.abs(xc))),
                 "ratio_over_median_percentiles": {str(q): float(np.exp(np.percentile(xc, q))) for q in (1, 5, 25, 75, 95, 99)},
                 "share_of_days_below": {str(th): float(np.mean(np.exp(xc) < th)) for th in (0.5, 0.3, 0.2)}}
    seasonal_r, beam = {}, {}
    for c, end in enumerate(ends):
        per = [float(light(1.0, "era5", "none", c)[jd_of[sy]].sum() / light(0.0, "era5", "none", c)[jd_of[sy]].sum()) for sy in seasons]
        seasonal_r[end] = {"ceres_world_over_era5_world_per_winter": [round(v, 4) for v in per],
                           "median": float(np.median(per)), "min": float(min(per)), "max": float(max(per))}
    for w, alpha in (("era5", 0.0), ("ceres", 1.0)):
        beam[w] = float((skies[alpha][0]["dni"] * gc[j180])[win_h].sum() / skies[alpha][1][win_h, 0].sum())
    ghi_winter = [float(g_c_kwh[jd_of[sy]].sum() / g_e_kwh[jd_of[sy]].sum()) for sy in seasons]

    # B. the record under each truth in each world, judged with the base the record offers
    out_cells, truths_out, cover_free = {}, {}, {}
    for w, (alpha, truth_air, analyst_air) in WORLDS.items():
        an = analyst[analyst_air]
        for c, end in enumerate(ends):
            r_none = light(alpha, "era5", "none", c) / safe_g
            for t in TRUTHS:
                r = light(alpha, truth_air, t, c) / safe_g
                per_winter, ratios, base_err, shares, based = [], [], [], [], []
                for sy in seasons:
                    jd = jd_of[sy]
                    base = base_from_record(r, jd, ground, terc_of[sy])
                    ratio = np.full(len(days), np.nan)
                    ratio[jd] = r[jd] / base[jd]
                    ok = jd[np.isfinite(ratio[jd])]
                    ratios.extend(ratio[ok])
                    base_err.extend(base[ok] / r_none[ok])
                    shares.append(float(np.mean(np.where(r_none[jd] > 0, r[jd] / np.where(r_none[jd] > 0, r_none[jd], 1.0), 1.0))))
                    based.append(len(ok))
                    row = {"season": sy, "judged_days": len(jd), "based_days": len(ok), "by_theta": {}}
                    seq = ratio[sel_of[sy]]
                    for theta in THETAS:
                        runs = [[int(sel_of[sy][i]) for i in run] for run in runs_below(seq, theta)]
                        row["by_theta"][f"{theta:g}"] = {
                            "dip_days": int(sum(len(run) for run in runs)), "runs": len(runs),
                            "misses": {f"tol{tol}:{y}": misses(runs, an["covered"][(y, c)], tol) for tol in TOLS for y in READINGS}}
                    per_winter.append(row)
                ratios = np.array(ratios)
                key = f"{w}:{end}:{t}"
                truths_out[key] = {"median_winter_mean_transmitted_share": float(np.median(shares)),
                                   "median_based_days_per_winter": float(np.median(based)),
                                   "winters_with_a_base_on_at_least_half_the_judged_days": int(sum(
                                       pw["based_days"] * 2 >= pw["judged_days"] for pw in per_winter)),
                                   "median_base_over_cover_free_r": float(np.median(base_err)) if len(base_err) else None}
                rej, outcome = {}, {}
                for theta in THETAS:
                    for tol in TOLS:
                        for k in KS:
                            true_w = false_w = none_w = 0
                            flags = {y: bool(t == "none" or y == t or an["contains"].get((t, y, c), False)) for y in READINGS}
                            for y in READINGS:
                                hit = [pw["season"] for pw in per_winter
                                       if pw["by_theta"][f"{theta:g}"]["misses"][f"tol{tol}:{y}"] >= k]
                                rej[f"theta{theta:g}:tol{tol}:k{k}:{y}"] = {
                                    "winters": len(hit), "odd": sum(s % 2 == 1 for s in hit), "even": sum(s % 2 == 0 for s in hit),
                                    "false_rejection": flags[y]}
                            # the season's outcome: a winter with a rejection not proven false, with a false one, with none
                            for pw in per_winter:
                                hit = [y for y in READINGS if pw["by_theta"][f"{theta:g}"]["misses"][f"tol{tol}:{y}"] >= k]
                                true_w += any(not flags[y] for y in hit)
                                false_w += any(flags[y] for y in hit)
                                none_w += not hit
                            outcome[f"theta{theta:g}:tol{tol}:k{k}"] = {"winters_with_a_rejection_not_proven_false": true_w,
                                                                        "winters_with_a_false_rejection": false_w,
                                                                        "winters_with_no_rejection": none_w}
                out_cells[key] = {"world": w, "end": end, "truth": t, "rejections": rej, "outcome": outcome,
                                  **({"per_winter": per_winter} if w in DETAIL_WORLDS else {})}
                if t == "none" and truth_air == "era5":
                    by_theta = {}
                    for theta in THETAS:
                        dd = np.array([pw["by_theta"][f"{theta:g}"]["dip_days"] for pw in per_winter])
                        rr = np.array([pw["by_theta"][f"{theta:g}"]["runs"] for pw in per_winter])
                        odd = np.array([pw["season"] % 2 == 1 for pw in per_winter])
                        by_theta[f"{theta:g}"] = {"dip_days_per_winter_mean": float(dd.mean()), "dip_days_per_winter_max": int(dd.max()),
                                                  "runs_per_winter_mean": float(rr.mean()), "runs_per_winter_min": int(rr.min()),
                                                  **{f"winters_with_at_least_{n}_runs": int(np.sum(rr >= n)) for n in KS},
                                                  "odd_winters_with_at_least_2_runs": int(np.sum(rr[odd] >= 2)),
                                                  "even_winters_with_at_least_2_runs": int(np.sum(rr[~odd] >= 2))}
                    cover_free[f"{w}:{end}"] = {
                        "sd_ln_r_over_base": float(np.log(ratios).std()),
                        "r_over_base_percentiles": {str(q): float(np.percentile(ratios, q)) for q in (1, 5, 50, 95, 99)},
                        "by_theta": by_theta}

    # C. the rule of two airs: the same record judged on ERA5's air, on the logger's (the truth's air with a sensor
    # error), and on both
    truth_airs = ("era5", "merra2", "merra2_frost", *[shifted("era5", k) for k in WARM_YARD_K])
    two_airs, logger_of = {}, {}
    for truth_air in truth_airs:
        logger_of[truth_air] = {f"d{delta:+g}": shifted(truth_air, delta) for delta in SENSOR_OFFSETS_K}
        if truth_air in OTHER_HUMIDITY or truth_air == "era5":
            logger_of[truth_air].update({f"dew{delta:+g}": dew_shifted(truth_air, delta) for delta in DEW_OFFSETS_K})
        if truth_air in OTHER_HUMIDITY:
            logger_of[truth_air]["other_humidity_reading"] = OTHER_HUMIDITY[truth_air]

    def missed(run: list, covered: np.ndarray) -> bool:
        return not np.any(covered[max(run[0] - RULE_TOL, 0):run[-1] + RULE_TOL + 1])

    for sky_name, alpha in RULE_SKIES.items():
        for truth_air in truth_airs:
            for c, end in enumerate(ends):
                r_none = light(alpha, "era5", "none", c) / safe_g
                for t in TRUTHS:
                    r = light(alpha, truth_air, t, c) / safe_g
                    share = np.where(r_none > 0, r / np.where(r_none > 0, r_none, 1.0), 1.0)
                    runs = {}
                    for sy in seasons:
                        jd = jd_of[sy]
                        base = base_from_record(r, jd, ground, terc_of[sy])
                        ratio = np.full(len(days), np.nan)
                        ratio[jd] = r[jd] / base[jd]
                        for theta in RULE_THETAS:
                            runs[(sy, theta)] = [[int(sel_of[sy][i]) for i in run] for run in runs_below(ratio[sel_of[sy]], theta)]
                    for label, logger in logger_of[truth_air].items():
                        an = {"era5": analyst_for("era5"), "logger": analyst_for(logger)}
                        proven = {a: {y: bool(t == "none" or y == t or v["contains"].get((t, y, c), False)) for y in READINGS}
                                  for a, v in an.items()}
                        flags = {"era5_alone": proven["era5"], "logger_alone": proven["logger"],
                                 "both": {y: proven["era5"][y] or proven["logger"][y] for y in READINGS}}
                        for theta in RULE_THETAS:
                            rejected = {rule: [] for rule in RULES}
                            for sy in seasons:
                                hit = {a: {y for y in READINGS
                                           if sum(missed(run, v["covered"][(y, c)]) for run in runs[(sy, theta)]) >= RULE_K}
                                       for a, v in an.items()}
                                rejected["era5_alone"].append(hit["era5"])
                                rejected["logger_alone"].append(hit["logger"])
                                rejected["both"].append(hit["era5"] & hit["logger"])
                            cell = {rule: {"winters_with_a_rejection_not_proven_false": sum(any(not flags[rule][y] for y in h) for h in per),
                                           "winters_with_a_false_rejection": sum(any(flags[rule][y] for y in h) for h in per),
                                           "winters_with_no_rejection": sum(not h for h in per),
                                           "winters_the_truth_is_rejected": None if t == "none" else sum(t in h for h in per),
                                           "winters_rejected_by_reading": {y: sum(y in h for h in per) for y in READINGS},
                                           "proven_false": [y for y in READINGS if flags[rule][y]]}
                                    for rule, per in rejected.items()}
                            if label == "d+0" and theta == RULE_THETAS[0] and t != "none":
                                lost = [run for sy in seasons for run in runs[(sy, theta)]
                                        if all(missed(run, v["covered"][(t, c)]) for v in an.values())]
                                on = np.array([d for run in lost for d in run], dtype=int)
                                cell["runs_of_the_truth_missed_on_both_airs"] = {
                                    "runs": len(lost), "days": len(on),
                                    "days_the_truths_cover_takes_over_half": int(np.sum(share[on] < COVERED)),
                                    "days_free_of_the_truths_cover": int(np.sum(share[on] >= FREE)),
                                    **({"days_the_products_ghi_is_under_half_of_era5s": int(np.sum(g_c_kwh[on] < 0.5 * g_e_kwh[on]))}
                                       if alpha == 1.0 else {})}
                            two_airs[f"{sky_name}:{truth_air}:{end}:{t}:{label}:theta{theta:g}"] = cell
    # control (6)
    control6 = {"outcomes": 0, "truth_counts": 0, "logger_is_era5": 0, "both_within_each": 0}
    same_as = {("era5", "era5", "era5_alone", "d+0"): "era5", ("era5", "era5", "logger_alone", "d+0"): "era5",
               ("ceres", "era5", "era5_alone", "d+0"): "ceres", ("ceres", "era5", "logger_alone", "d+0"): "ceres",
               ("ceres", "merra2", "era5_alone", "d+0"): "ceres_cold_truth", ("ceres", "merra2", "logger_alone", "d+0"): "ceres_cold_both",
               ("era5", "merra2", "logger_alone", "d+0"): "era5_cold_both",
               ("ceres", "merra2_frost", "logger_alone", "d+0"): "ceres_frost_both",
               ("era5", "merra2_frost", "logger_alone", "d+0"): "era5_frost_both"}
    for (sky_name, truth_air, rule, label), world in same_as.items():
        for end in ends:
            for t in TRUTHS:
                for theta in RULE_THETAS:
                    got = two_airs[f"{sky_name}:{truth_air}:{end}:{t}:{label}:theta{theta:g}"][rule]
                    old = out_cells[f"{world}:{end}:{t}"]
                    want = old["outcome"][f"theta{theta:g}:tol{RULE_TOL}:k{RULE_K}"]
                    assert all(got[k] == v for k, v in want.items()), ("control 6", sky_name, truth_air, rule, end, t, theta, got, want)
                    control6["outcomes"] += 1
                    for y in READINGS:
                        assert got["winters_rejected_by_reading"][y] == old["rejections"][f"theta{theta:g}:tol{RULE_TOL}:k{RULE_K}:{y}"]["winters"]
                        control6["truth_counts"] += 1
    warm1 = shifted("era5", WARM_YARD_K[0])
    assert logger_of[warm1][f"d{-WARM_YARD_K[0]:+g}"] == "era5"
    for key, cell in two_airs.items():
        if f":{warm1}:" in key and f":d{-WARM_YARD_K[0]:+g}:" in key:
            assert cell["era5_alone"] == cell["logger_alone"] == cell["both"], ("control 6, the logger is ERA5", key)
            control6["logger_is_era5"] += 1
        for y in READINGS:
            n = {rule: cell[rule]["winters_rejected_by_reading"][y] for rule in RULES}
            assert n["both"] <= min(n["era5_alone"], n["logger_alone"]), ("control 6, both within each", key, y, n)
            control6["both_within_each"] += 1
    for name, (base, _total) in shift_of.items():
        if name in wx_air and name != base:
            assert np.allclose(wx_air[name]["t_air"] - wx_air[name]["t_dew"], wx_air[base]["t_air"] - wx_air[base]["t_dew"], rtol=0, atol=1e-9)
    dew_deficit = {}
    for name, (base, delta) in dew_of.items():
        if name in wx_air:
            assert np.array_equal(wx_air[name]["t_air"], wx_air[base]["t_air"]) and np.all(wx_air[name]["t_dew"] <= wx_air[name]["t_air"])
            moved = float((wx_air[name]["t_dew"] - wx_air[base]["t_dew"])[win_h].mean())
            assert (moved < 0.0) == (delta < 0.0) and abs(moved) <= abs(delta) + 1e-9, ("control 6, the dew axis", name, moved)
            dew_deficit[name] = float((wx_air[name]["t_air"] - wx_air[name]["t_dew"])[win_h].mean())
    assert control6["logger_is_era5"] > 0
    nesting_differs = {name: sorted(f"{ends[c]}:{t}->{y}" for (t, y, c), v in a["contains"].items() if v != analyst["era5"]["contains"][(t, y, c)])
                       for name, a in analyst.items()}
    nesting_differs = {name: v for name, v in nesting_differs.items() if v}

    print(f"  clock: corr by row lag {', '.join(f'{k:+d}: {v:.3f}' for k, v in by_lag.items())}; closure median {closure_median:.3f}; "
          f"ERA5 air − MERRA-2 air {air_diff:.2f} K over all hours, {air_diff_winter:.2f} K over the seasons' DJF hours")
    print(f"  the sky alone — daily GHI, product over ERA5, {sky_alone['days']} judged DJF days: sd(ln) {sky_alone['sd_ln']:.3f}, "
          f"MAD-sd {sky_alone['mad_sd_ln']:.3f}")
    print("  the cover-free face, R over the record's own base:  sd(ln)   runs/winter and winters with ≥ 2 runs, per θ")
    for key, v in cover_free.items():
        cells = "  ".join(f"θ{th}: {b['runs_per_winter_mean']:.2f}/{b['winters_with_at_least_2_runs']}" for th, b in v["by_theta"].items())
        print(f"    {key:<12s} {v['sd_ln_r_over_base']:.3f}   {cells}")
    for end in ends:
        sr = seasonal_r[end]
        print(f"  seasonal R, product-lit over ERA5-lit ({end}): median {sr['median']:.3f}, {sr['min']:.3f}…{sr['max']:.3f}")
    print("  how a season ends, tol 1 — winters of 19 with (a rejection not proven false · a false one · none), low end:")
    for w in WORLDS:
        for k, theta in ((2, 0.5), (2, 0.15), (2, 0.1), (1, 0.3), (1, 0.1)):
            parts = [f"{t[:5]} " + "·".join(str(v) for v in out_cells[f"{w}:low:{t}"]["outcome"][f"theta{theta:g}:tol1:k{k}"].values())
                     for t in TRUTHS]
            print(f"    {w:<17s} k{k} θ{theta:<4g} " + " | ".join(parts))

    print(f"  the rule of two airs, θ {RULE_THETAS[0]:g}, tol {RULE_TOL}, k {RULE_K}, the product's sky — winters of 19 the TRUE reading is "
          "rejected under itself, low/high end, per rule ERA5 alone | logger alone | both:")
    for truth_air in truth_airs:
        for t in ("melt_only", "nrel_published"):
            row = []
            for label in logger_of[truth_air]:
                lo, hi = (two_airs[f"ceres:{truth_air}:{end}:{t}:{label}:theta{RULE_THETAS[0]:g}"] for end in ends)
                row.append(f"{label} " + "|".join(f"{lo[rule]['winters_the_truth_is_rejected']}/{hi[rule]['winters_the_truth_is_rejected']}" for rule in RULES))
            print(f"    {truth_air:<13s} {t[:9]:<9s} " + "  ".join(row))
    print(f"  nesting of the readings differs from ERA5's air on: {nesting_differs}")

    OUT.write_text(json.dumps({
        "question": "00_07 HW.54 Р3(б)(4), stage 1: what the disagreement of two sky products, and of two airs, does to the "
                    "stem-face logger's daily R against ERA5, to the dip rules with a base estimated from the record, and to "
                    "the seasonal R — readings, not bounds",
        "inputs": {"product_file": str(DATA_FILE.relative_to(REPO_ROOT)), "air_file": str(AIR_FILE.relative_to(REPO_ROOT)),
                   "months": list(MONTHS), "seasons": list(SEASONS),
                   "worlds": {w: {"alpha": a, "truth_air": ta, "analyst_air": aa} for w, (a, ta, aa) in WORLDS.items()},
                   "truths": list(TRUTHS), "readings": list(READINGS), "ends": ends,
                   "ghi_min_kwh": GHI_MIN_KWH, "ground_edges_m": list(GROUND_EDGES_M), "windows_d": list(WINDOWS_D),
                   "base_min_days": BASE_MIN_DAYS, "thetas": list(THETAS), "covered": COVERED, "free": FREE,
                   "tols": list(TOLS), "ks": list(KS), "product_stamp_lag_h": PRODUCT_STAMP_LAG_H,
                   "cerra_on_season": "held flat, as `118`",
                   "base": "the sheet's p.4 on the record, leave-one-out, without the candidate-day exclusion"},
        "controls": {"correlation_by_row_lag": {str(k): v for k, v in by_lag.items()}, "best_row_lag": int(best),
                     "closure_median": closure_median,
                     "closure_p5_p95": [float(v) for v in np.percentile(closure, [5, 95])],
                     "118_cover_free_day_counts_checked": control3,
                     "era5_air_minus_merra2_air_mean_K": {"all_hours": air_diff, "seasons_djf_hours": air_diff_winter},
                     "air_correlation": air_corr, "merra2_dew_point_above_its_temperature_share_capped": dew_above,
                     "dew_point_minus_its_frost_reading_mean_K_below_0C": frost_reading_shift,
                     "run_base_and_miss_functions": "synthetic; the run function also equals 118's at θ 0.5"},
        "sky_alone": sky_alone,
        "ghi_ratio_per_winter": [round(v, 4) for v in ghi_winter],
        "seasonal_r": seasonal_r,
        "beam_share_of_winter_face_light_low_end": beam,
        "containment_by_analyst_air": {air_name: {f"{end}:{t}->{y}": a["contains"][(t, y, c)] for c, end in enumerate(ends)
                                                  for t in READINGS for y in READINGS if t != y}
                                       for air_name, a in analyst.items() if air_name in world_airs},
        "cover_free": cover_free,
        "truths": truths_out,
        "cells": out_cells,
        "two_airs_rule": {"inputs": {"skies": RULE_SKIES, "truth_airs": list(truth_airs), "sensor_offsets_K": list(SENSOR_OFFSETS_K),
                                     "dew_offsets_K": list(DEW_OFFSETS_K), "loggers_by_truth_air": logger_of,
                                     "thetas": list(RULE_THETAS), "tol": RULE_TOL, "k": RULE_K, "rules": list(RULES),
                                     "logger_air": "the truth's air with a sensor error: «d» on temperature and dew point alike, "
                                                   "«dew» on the dew point alone, «other_humidity_reading» the column read the other way",
                                     "control_6_checks": control6,
                                     "mean_dew_point_deficit_K_on_the_dew_axis_djf": dew_deficit,
                                     "nesting_differs_from_era5_air": nesting_differs},
                          "cells": two_airs},
    }, indent=2))
    print(f"[124] wrote {OUT.relative_to(HERE.parents[2])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
