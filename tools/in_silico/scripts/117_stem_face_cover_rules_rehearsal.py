#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""117 — whether the cover-reading rules of the stem-face light sheet can judge a winter at all: their first four steps
rehearsed on the hourly ERA5 record of thirty winters, before the logger is bought (00_07 HW.54, the leg «Р3(б)(4) —
переписати правила розбору покриву ДО даних»; the sheet `docs/protocols/ebfc/stem_face_winter_light.md` §6).

WHY. An adversary found that, as written on 2026-11-09/10, the candidate days (a snow event or a frost night, plus the
three days after) take most of the season, so the base R — a median over the non-candidate days of the same ground state
and diffuse-light tercile within ±15 days — has almost nothing to stand on, and the reading says «not judged» whatever the
logger records. The rules are a `[вибір]` of the sheet, written before data on purpose. This script measures, on the
record the season will be read against, how many days a version of the rules can JUDGE.
⚠️ Judgeability is a NECESSARY property, not an acceptance test. A first rewrite (2026-11-10, below as the DRAFT) judged
every day of the median winter and was still rejected by its adversary: its base fell back across diffuse classes and
manufactured dips on a cover-free face, its episode count did not move with cover, and its frost rule was narrower than
`115`'s own frost (the provenance and the requirements for the next rewrite — the leg in `00_07` HW.54). The acceptance
test a rewrite needs is a PERFECT-LOGGER rehearsal — the modelled face under each `115` reading's cover and under none,
the rules asked to keep the truth and reject the rest. ⊕ 2026-11-15: the rules rewritten that day (the sheet's §6,
«Правила розбору, переписані до даних — 2026-11-15») are rehearsed here that way — the block THE RULES REWRITTEN below;
the rules as written and the draft stay as measured readings of those texts.

MODEL. Per calendar day (the data's fixed clock) of December–February, 29 full winters (1991/92 … 2019/20):
  GHI — `110`'s `irradiance` (the same function the sheet's R divides by); a day with ΣGHI < 0.1 kWh/m² is not judgeable.
  ground state — ERA5-Land `snow_depth`, the day's mean: bare < 0.01 m · intermediate · snow ≥ 0.11 m (`79`'s REFLECT_ENDS).
  the night of day d — the hours with GHI = 0 from the last lit hour of d − 1 to the first lit hour of d.
  RH over ice — e(T_dew)/e_ice(T_air): `79`'s Magnus over water at the dew point, `115`'s over ice; ERA5's 2 m air stands in
    for the logger's own RH, which sits by a trunk under a crown.
  THE RULES AS WRITTEN (2026-11-09/10):
    candidate — frost: a night with an hour of air < 0 °C and RH_ice ≥ 0.90; snow: a ceiling event (a rise ≥ 2 mm/h in
      ERA5-Land OR CERRA, air ≤ +1 °C) or an NREL event (a rise ≥ 1 cm/h in ERA5-Land, any air); the event's day and the
      three after;
    base — the median over the non-candidate judgeable days within ±15 days of the same ground state and the same tercile
      of the diffuse share (terciles over the season's judgeable days, per ground state); < 5 → ±30; < 5 → not judged.
  THE DRAFT (2026-11-10, REJECTED — kept as a measured reading of that draft, never a rule):
    candidate — frost: a night with ≥ 3 consecutive hours of air < 0 °C in which either the cloud is ≤ 0.5 and RH_ice ≥ 0.9
      or RH_ice ≥ 1.0, marking the morning's day only; snow: a rise ≥ 1 cm/h in ERA5-Land with air ≤ +1 °C, marking its day
      and the next;
    base — the median over the non-candidate judgeable days of the whole season of the same ground state and a fixed
      diffuse class (Σ diffuse / Σ GHI < 0.5 · < 0.9 · ≥ 0.9); < 5 → the same ground state, every class (the fallback the
      adversary showed manufactures dips); < 5 → not judged.
  A day is JUDGED when it is judgeable and has a base.
  Also printed — two facts no rewrite changes: the event days CERRA's ≥ 2 mm added to ERA5-Land in 1991–2020 (CERRA ends
  at this point at 2021-06-30T23:00 UTC, probed 2026-11-10, so the season cannot have them); and, per winter, an UPPER
  bound on the overcast lit hours (hourly diffuse share ≥ 0.9, GHI ≥ 20 W/m²) on bare-ground judgeable days — before any
  candidate or episode day is excluded — which an adverse R for `110` could stand on, beside the same bound with
  intermediate ground (biased up by the light snow reflects).
  THE RULES REWRITTEN (2026-11-15), on a PERFECT logger — the south face `118` reads (dni·gc[180] + ½dif + ½refl at both
    of `79`'s reflection ends), lit by ERA5, under a TRUTH's cover from `115`'s `cover_readings` on the season's record
    (CERRA held flat), no noise, no yard, the analyst on the truth's air (ERA5's — the rule of two airs needs a second
    air, so its numbers stay `124`'s):
    ⚠️ The truth and the readings come out of ONE model on ONE sky and ONE air, so what this block shows is that the rules
      are CONSISTENT with `115` — not that they judge a real record: its zero of false rejections is a construction
      (controls (6)–(7)); the false rejections of a true reading under another sky and air are `124`'s.
    truths and readings — none · the four `115` readings · three HYBRIDS (the ceiling's snow-only cover with a lighter
      reading's frost-only cover — the leg's (7); «lighter» = the three readings under the ceiling, «middle» = melt only
      and NREL) · three DRY readings (a lighter reading with its wet-snow window opened downward, so dry snow plasters
      too and clears by that reading's own rule — a private instance of `115` with WET_SNOW_C widened; the leg's (27));
      the analyst tests every one but «none»;
    R_d — the day's face light over ΣGHI; a day with ΣGHI < 0.1 kWh/m² is not judged;
    base — `124`'s `base_from_record` (leave-one-out median, same ground state and diffuse tercile, ±15 → ±30 days,
      ≥ 5, a dark pool gives none — no fallback across classes); a SEASON WITH A BASE has one on at least half its
      judged days — in any other season the episode rules do not apply (no run is counted);
    dip and run — R_d < θ · base, θ 0.1 deciding (0.15 · 0.2 beside it); a run is consecutive based days in a dip;
    coverage test — a run is a miss of reading Y when Y's own transmitted share stays ≥ 0.5 on every day of it and of
      the tol days either side (tol 1 deciding; 0 · 2 beside it); Y is rejected with ≥ 2 misses; a rejection is FALSE
      when Y is the truth, the truth is «none», or Y covers every hour the truth covers, else «not proven false»;
    labels — a snow event (an ERA5-Land rise ≥ 1 cm in an hour, any air) or an onset of a lighter reading's frost on a
      run's first day or the day before; runs without one are counted against the Poisson bar: λ is `124`'s false-run
      rate of a cover-free face under the second sky at θ 0.1 (the larger end), k the least count with P(N ≥ k) ≤ α
      0.01 at λ and at its one-sided 95 % upper bound;
    the adverse R's hours — overcast lit hours (as above) on bare-ground judged days WITH A BASE outside the runs (the
      sheet's p. 8; every judged day in a season without a base), against 30;
    the trigger's frequency — «no deep episode» (01_03 §4, ⚖️ 2026-11-01) read through p. 6: a season without a base or
      with no run at θ 0.1;
    noise — R_d · exp(σz − σ²/2), independent per day, one draw per seed shared by truths and ends, over 10 seeds and
      σ 0 … 1.2 — the base re-estimated on the noisy record; for «none», «melt only» and «NREL published».

WHAT IT CANNOT SEE. The logger: R itself, its dips, the false-dip rate — the rehearsal of the rules as written counts
what they can JUDGE, not what they will find, and not whether they DISCRIMINATE. ERA5's RH at 2 m in an open
cell for the logger's RH by a trunk under a crown; a cell, not the yard (ERA5-Land overstates snow cover — the data
README); the season's own clock (the files run on a fixed UTC+3; a query's offset is the zone's at the moment of the
query — the sheet's §5). For the rewritten rules: everything a perfect logger is perfect at — a second sky and a
second air (`124`), the yard's building and stems (`125`), sensor offsets, cosine and spectral errors, the logger's clock,
fog and rime (`115` has none), the human minutes and the snapshots (the rules keep both out of every count), other
azimuths and the winters after 2020 (the record ends with the 2019/20 winter); a day noise that is log-normal and
independent, which no measured sky is (`124`'s second sky is heavy-tailed).

CONTROLS (each says what it CAN and CANNOT catch).
  (1) The rules as written reproduce the adversary's measurement within 5 points: frost alone ≈ 80 % of the days candidate
      (the session's own check, 80.2 %, night 18:00–08:00), frost and snow 88–90 %, and ≈ 97.6 % of the days not judged;
      CAN catch a rule built otherwise than the sheet's text, CANNOT a misreading both share.
  (2) ERA5-Land's hourly rises are whole centimetres (its 1 cm grid), so «≥ 2 mm» and «≥ 1 cm» select the same hours in it;
      CAN catch a grid that is not what the data README says, CANNOT a gridded series' own errors.
  (3) The draft's candidates are a subset of the written ones (it only narrowed); every judged day's pool has ≥ 5 days and
      holds no candidate day (true by the pool's construction — asserted, cannot fail); CAN catch a widened draft rule,
      CANNOT a wrong threshold value.
  (4) GHI is `110`'s `irradiance` GHI, recomputed here from DNI, the sun and the diffuse column hour by hour; CAN catch a
      different sun or column, CANNOT `110`'s own errors.
  (5) The opened wet-snow window leaves the ceiling bit for bit, makes dry melt only cover every hour melt only covers,
      and adds cover somewhere; CAN catch the window applied to the wrong instance or column, CANNOT a wrong clearing.
  (6) The leg's acceptance on the perfect logger (requirement (1)): with no cover there is no run at θ 0.1 in any winter
      at either end — this CAN fail (a base that manufactures dips); no reading is ever rejected under itself — a
      tautology on one air and one sky (the run is the truth's own cover), asserted so that a broken miss count shows,
      and the reason the leg's (17) judges the rules by false rejections, not by the truth surviving.
  (7) No rejected reading covers every hour a surviving one covers (the table's inconsistent row); on one air a covered
      day carries a miss down the nesting, so this cannot fail here — it guards the miss and containment code only.
  (8) At σ 0 the noise branch gives the noiseless outcome in every seed; the Poisson rate bound at n = 0 equals
      −ln 0.05; `124`'s rate is a whole count of runs over its winters. CAN catch a noise or Poisson branch built on other
      inputs, CANNOT a wrong α.

Run:  python tools/in_silico/scripts/117_stem_face_cover_rules_rehearsal.py      # under a minute
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import KINETICS_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("A rehearsal, on thirty winters of hourly reanalysis weather, of the rules a single light logger on a pine "
                  "stem's face will be read by: how many winter days the rules as first written, and a rejected draft "
                  "rewrite, can judge against a base of cover-free days, how many overcast hours on bare ground a winter "
                  "offers at most, and the rewritten rules on a perfect logger under each snow- and hoarfrost-cover model "
                  "and under none, with and without a day noise.")

HERE = Path(__file__).resolve().parent
OUT = KINETICS_DIR / "stem_face_cover_rules_rehearsal.json"
MONTHS = (12, 1, 2)
GHI_MIN_KWH = 0.1                        # the sheet's §6 p. 1: a day under it is not judged
OLD = {"frost_rh_ice": 0.90, "snow_ceiling_mm": 2, "snow_ceiling_max_c": 1.0, "nrel_mm": 10, "days_after": 3,
       "window_d": (15, 30), "pool_min": 5}
DRAFT = {"frost_rh_ice_clear": 0.90, "frost_cloud_clear_max": 0.5, "frost_rh_ice_any_sky": 1.0, "frost_run_h": 3,
         "snow_mm": 10, "snow_max_c": 1.0, "days_after": 1, "pool_min": 5, "diffuse_edges": (0.5, 0.9)}
OVERCAST_HOUR = {"diffuse_share_min": 0.9, "ghi_min_w_m2": 20.0}  # an overcast lit hour, for the adverse-R upper bound
OVERCAST_HOURS_PRINTED = (25, 30, 35)    # the bound's count against a few bars — no bar is ratified (the draft took 30)
ADVERSARY = {"old_frost_candidate_share": 0.802, "old_all_candidate_share": (0.88, 0.90), "old_not_judged_share": 0.976}
P124 = KINETICS_DIR / "stem_face_second_sky.json"
# the rules rewritten 2026-11-15 (the sheet's §6, «Правила розбору, переписані до даних — 2026-11-15»), declared before
# their run here; θ is 124's (the depth at which a cover-free face under the second sky stops making two false runs)
NEW = {"theta": 0.1, "thetas": (0.2, 0.15, 0.1), "covered": 0.5, "tol": 1, "tols": (0, 1, 2), "k": 2,
       "season_base_min_share": 0.5, "alpha": 0.01, "rate_confidence": 0.95, "overcast_hours_min": 30,
       "snow_label_mm": 10}
# rules of the sheet's p. 0 and p. 4 that need the logger's own record, so no ERA5 rehearsal can run them — DECLARED
# here only so the sheet's text has a twin to be pinned against (test_stem_face_rule_constants_match_the_rehearsal)
DECLARED_NOT_REHEARSED = {"clock_threshold_w_m2": 1.0, "step_beam_share": 0.5, "dark_pool_sd": 3,
                          "logger_air_gap_max_h": 3}
READINGS = ("ceiling", "melt_only", "nrel_published", "favourable_end")
LIGHTER = READINGS[1:]                               # the three readings under the ceiling
MIDDLE = READINGS[1:3]                               # the two middle ones (the sheet's «середні»)
HYBRIDS = tuple(f"hybrid_{y}" for y in LIGHTER)       # the ceiling's snow with that reading's frost (the leg's (7))
DRY = tuple(f"dry_{y}" for y in LIGHTER)               # that reading with dry snow plastering too, its own clearing kept
TRUTHS = ("none", *READINGS, *HYBRIDS, *DRY)
ANALYST = (*READINGS, *HYBRIDS, *DRY)
SIGMAS = (0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2)         # a scale past the cliff (in-silico §When Modifying #54)
SEEDS = 10
NOISE_TRUTHS = ("none", "melt_only", "nrel_published")


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S124 = _load("s124_rules", "124_stem_face_second_sky.py")      # base_from_record · terciles · runs_below · misses
S115 = S124.S115                                                # the cover model's ONE home, through the same import
S110, S79, S71 = S115.S110, S115.S79, S115.S71
S115_DRY = _load("s115_dry", "115_pv_face_snow_frost_azimuth.py")   # a PRIVATE instance with its wet-snow window opened
S115_DRY.WET_SNOW_C = (-math.inf, S115.WET_SNOW_C[1])               # downward: «dry snow plasters too» (the leg's (27))


def runs_at_least(mask: np.ndarray, n: int) -> bool:
    run = 0
    for m in mask:
        run = run + 1 if m else 0
        if run >= n:
            return True
    return False


def ground_state(depth_m: float) -> str:
    lo, hi = sorted(e[2] for e in S79.REFLECT_ENDS)        # 0.01 · 0.11 m — `79`'s two ends
    return "bare" if depth_m < lo else ("snow" if depth_m >= hi else "intermediate")


def diffuse_class(share: float) -> str:
    e = DRAFT["diffuse_edges"]
    return "clearish" if share < e[0] else ("mixed" if share < e[1] else "overcast")


def poisson_tail(lam: float, k: int) -> float:
    """P(N ≥ k) for a Poisson count of mean λ."""
    term, cdf = math.exp(-lam), 0.0
    for i in range(k):
        cdf += term
        term *= lam / (i + 1)
    return max(0.0, 1.0 - cdf)


def k_at(lam: float, alpha: float) -> int:
    """The least k with P(N ≥ k | λ) ≤ α — the bar of a one-sided Poisson test."""
    k = 1
    while poisson_tail(lam, k) > alpha:
        k += 1
    return k


def rate_upper(n: int, exposure: float, conf: float) -> float:
    """The one-sided upper confidence bound on a Poisson rate from n events over `exposure` — the λ at which
    P(N ≤ n) = 1 − conf, by bisection (P(N ≤ n) falls as λ grows)."""
    lo, hi = 0.0, (n + 10.0) * 10.0 / exposure
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        lo, hi = (mid, hi) if 1.0 - poisson_tail(mid * exposure, n + 1) > 1.0 - conf else (lo, mid)
    return hi


def rehearse_new_rules(wx, sun, gc, ghi, snow, rise_e5, first_idx, season_year, in_season, judgeable, depth, dif_share):
    """The rules rewritten 2026-11-15 on a PERFECT logger (the leg's requirement (1)): the south face lit by ERA5, no
    noise, no yard, its cover the truth's (`115`'s `cover_readings`, the season's record — CERRA held flat), judged with
    the base the record offers (124's functions — their ONE home), on the analyst's air = the truth's (ERA5's: the
    rule of two airs cannot be told from one air here — its numbers are 124's). Then the same with a log-normal day
    noise on R over seeds and a σ scale past the cliff (the leg's (10))."""
    ends = [e[0] for e in S79.REFLECT_ENDS]
    j180 = list(S79.AZIMUTHS_DEG).index(180)
    refl = S79.reflected_rows(snow, ghi)
    g = np.stack([wx["dni"] * gc[j180] + 0.5 * wx["dif"] + 0.5 * refl[k] for k in range(1, len(ends) + 1)], axis=1)
    snow_season = {"era5_land": snow["era5_land"],
                   "cerra": {**snow["cerra"], "depth_m": np.zeros_like(snow["cerra"]["depth_m"])}}
    d_dome = S71.geometry()["dome_diameter_mm"] / 1000.0
    cov = S115.cover_readings(wx, g, snow_season, d_dome)["covers"]
    cov_dry = S115_DRY.cover_readings(wx, g, snow_season, d_dome)["covers"]
    assert np.array_equal(cov_dry["ceiling"][0], cov["ceiling"][0]), "control 5: the wet-snow window moved the ceiling"
    assert np.all(cov_dry["melt_only"][0] >= cov["melt_only"][0]), "control 5: dry melt only does not cover melt only"
    assert np.any(cov_dry["melt_only"][0] > cov["melt_only"][0]), "control 5: the opened window added no snow"
    cover = {"none": np.zeros_like(g), **{y: cov[y][0] for y in READINGS},
             **{f"hybrid_{y}": np.maximum(cov["ceiling"][1], cov[y][2]).astype(float) for y in LIGHTER},
             **{f"dry_{y}": cov_dry[y][0] for y in LIGHTER}}

    def daysum(x):
        return np.add.reduceat(x, first_idx, axis=0)

    n_days = len(first_idx)
    hours_per_day = np.diff([*first_idx, len(ghi)])
    win_h = np.repeat(in_season, hours_per_day)
    ghi_wh = daysum(ghi)
    face = daysum(g)
    light = {t: daysum(g * (1.0 - cover[t])) for t in TRUTHS}
    r = {t: light[t] / np.where(ghi_wh > 0, ghi_wh, 1.0)[:, None] for t in TRUTHS}
    covered = {y: np.where(face > 0, light[y] / np.where(face > 0, face, 1.0), 1.0) < NEW["covered"] for y in ANALYST}
    contains = {(t, y, c): bool(np.all(cover[y][win_h, c] >= cover[t][win_h, c] - 1e-12))
                for t in TRUTHS for y in ANALYST for c in range(len(ends)) if t != y}
    lo, hi = sorted(e[2] for e in S79.REFLECT_ENDS)
    ground = np.where(depth < lo, 0, np.where(depth < hi, 1, 2))
    overcast_bare = daysum(((ghi >= OVERCAST_HOUR["ghi_min_w_m2"])
                            & (wx["dif"] >= OVERCAST_HOUR["diffuse_share_min"] * np.maximum(ghi, 1e-9))).astype(int))
    overcast_bare = np.where(ground == 0, overcast_bare, 0)
    # the labels of p.3 (they switch nothing): a snow event of any temperature, or an onset of a middle reading's frost
    snow_day = daysum((rise_e5 >= NEW["snow_label_mm"]).astype(int)) > 0
    onset = np.zeros((n_days, len(ends)), bool)
    for y in LIGHTER:
        fr = cov[y][2]
        onset |= daysum((fr & ~np.vstack([np.zeros((1, fr.shape[1]), bool), fr[:-1]])).astype(int)) > 0
    label = snow_day[:, None] | onset

    winters = sorted(set(season_year[in_season]))
    sel_of = {w: np.nonzero(in_season & (season_year == w))[0] for w in winters}
    jd_of = {w: sel_of[w][judgeable[sel_of[w]]] for w in winters}
    terc_of = {w: S124.terciles(jd_of[w], ground, dif_share, n_days) for w in winters}

    # the Poisson bar (p.7) from 124's cover-free face under the second sky at the deciding θ
    z124 = json.loads(P124.read_text())
    n124 = z124["inputs"]["seasons"][1] - z124["inputs"]["seasons"][0] + 1
    rate = max(z124["cover_free"][f"ceres:{e}"]["by_theta"][f"{NEW['theta']:g}"]["runs_per_winter_mean"] for e in ends)
    runs124 = round(rate * n124)
    assert abs(runs124 - rate * n124) < 1e-9, "124's rate is not a whole count of runs over its winters"
    rate_up = rate_upper(runs124, n124, NEW["rate_confidence"])
    assert abs(rate_upper(0, 1.0, 0.95) + math.log(0.05)) < 1e-6, "the rate bound's closed form at n = 0"
    k_p = k_at(rate, NEW["alpha"])
    poisson = {"source": "124 cover_free «ceres» (the product's sky), the larger end", "runs": runs124, "winters": n124,
               "rate_per_winter": rate, "rate_upper": rate_up, "alpha": NEW["alpha"], "k_at_rate": k_p,
               "k_at_rate_upper": k_at(rate_up, NEW["alpha"]),
               "p_two_runs_at_rate": poisson_tail(rate, 2), "p_two_runs_at_rate_upper": poisson_tail(rate_up, 2)}

    def judge(r_tc, c, w):
        jd, sel = jd_of[w], sel_of[w]
        base = S124.base_from_record(r_tc, jd, ground, terc_of[w])
        ratio = np.full(n_days, np.nan)
        ratio[jd] = r_tc[jd] / base[jd]
        based = int(np.sum(np.isfinite(ratio[jd])))
        with_base = based >= NEW["season_base_min_share"] * len(jd)
        runs = {th: [[int(sel[i]) for i in run] for run in S124.runs_below(ratio[sel], th)] if with_base else []
                for th in NEW["thetas"]}
        return based, with_base, runs, np.isfinite(ratio)

    def rejected(runs, c, tol):
        return {y for y in ANALYST if S124.misses(runs, covered[y][:, c], tol) >= NEW["k"]}

    def flags(t, c):
        return {y: bool(t == "none" or y == t or contains[(t, y, c)]) for y in ANALYST}

    cells = {}
    for c, end in enumerate(ends):
        for t in TRUTHS:
            fl = flags(t, c)
            rows, rej_by_key = [], []
            for w in winters:
                based, with_base, runs, has_base = judge(r[t][:, c], c, w)
                main_runs = runs[NEW["theta"]]
                in_run = np.zeros(n_days, bool)
                for run in main_runs:
                    in_run[run] = True
                jd = jd_of[w]
                r_days = jd[has_base[jd] & ~in_run[jd]] if with_base else jd
                rej = {f"theta{th:g}:tol{tol}": sorted(rejected(runs[th], c, tol)) for th in NEW["thetas"] for tol in NEW["tols"]}
                decided = set(rej[f"theta{NEW['theta']:g}:tol{NEW['tol']}"])
                # a rejected reading that covers every hour a surviving one covers — the table's inconsistent row; on
                # one air it cannot happen (a day-covered nesting carries the misses down), so it is asserted, not counted
                assert not any(contains.get((z, y, c), False) for y in decided for z in ANALYST if z not in decided and z != y), (end, t, w)
                rej_by_key.append(rej)
                rows.append({"season": int(w), "days": len(sel_of[w]), "judged_days": len(jd), "based_days": based,
                             "season_with_base": with_base,
                             "runs": {f"{th:g}": len(runs[th]) for th in NEW["thetas"]},
                             "runs_without_event": sum(not (label[run[0], c] or label[run[0] - 1, c]) for run in main_runs),
                             "overcast_bare_hours_outside_runs": int(overcast_bare[r_days].sum()),
                             "rejected": sorted(decided)})
            if t == "none":   # the leg's (1): no cover — no episode, nothing rejected
                assert all(rw["runs"][f"{NEW['theta']:g}"] == 0 for rw in rows), (end, "a run on a cover-free perfect logger")
            if t in ANALYST:  # the truth is never rejected under itself on a perfect logger — a tautology (the leg's (17))
                assert all(t not in rw["rejected"] for rw in rows), (end, t)

            def outcome(key, rows=rows, fl=fl, rej_by_key=rej_by_key):
                hit = [(rw["season"], set(rk[key])) for rw, rk in zip(rows, rej_by_key, strict=True)]
                return {"winters_with_a_rejection_not_proven_false": sum(any(not fl[y] for y in h) for _, h in hit),
                        "winters_with_a_false_rejection": sum(any(fl[y] for y in h) for _, h in hit),
                        "winters_with_no_rejection": sum(not h for _, h in hit),
                        "odd_winters_not_proven_false": sum(any(not fl[y] for y in h) for s, h in hit if s % 2),
                        "even_winters_not_proven_false": sum(any(not fl[y] for y in h) for s, h in hit if not s % 2)}
            dkey = f"theta{NEW['theta']:g}:tol{NEW['tol']}"
            withb = [rw for rw in rows if rw["season_with_base"]]
            cells[f"{end}:{t}"] = {
                "verdict_day_share": round(sum(rw["based_days"] for rw in withb) / sum(rw["days"] for rw in rows), 4),
                "winters_with_base": len(withb),
                "median_based_days": float(np.median([rw["based_days"] for rw in rows])),
                "winters_with_at_least_1_run": {f"{th:g}": sum(rw["runs"][f"{th:g}"] >= 1 for rw in rows) for th in NEW["thetas"]},
                "winters_with_at_least_2_runs": {f"{th:g}": sum(rw["runs"][f"{th:g}"] >= 2 for rw in rows) for th in NEW["thetas"]},
                "runs_without_event": sum(rw["runs_without_event"] for rw in rows),
                "winters_test_b_fires": sum(rw["runs_without_event"] >= k_p for rw in rows),
                "winters_adverse_r_estimable": sum(rw["overcast_bare_hours_outside_runs"] >= NEW["overcast_hours_min"] for rw in rows),
                "outcome": {key: outcome(key) for key in rej_by_key[0]},
                "winters_rejected_by_reading": {y: sum(y in rw["rejected"] for rw in rows) for y in ANALYST},
                "proven_false": [y for y in ANALYST if fl[y]],
                "per_winter": rows}

    # the noise branch: R · exp(σz − σ²/2), independent per day, one draw per seed shared by the truths and ends
    noise = {}
    for si, sigma in enumerate(SIGMAS):
        for seed in range(SEEDS):
            z = np.random.default_rng([seed, si]).standard_normal(n_days)
            for c, end in enumerate(ends):
                for t in NOISE_TRUTHS:
                    fl = flags(t, c)
                    rn = r[t][:, c] * np.exp(sigma * z - sigma ** 2 / 2.0)
                    per = []
                    for w in winters:
                        _, _, runs, _ = judge(rn, c, w)
                        per.append((int(w), len(runs[NEW["theta"]]), rejected(runs[NEW["theta"]], c, NEW["tol"])))
                    cell = noise.setdefault(f"sigma_{sigma:g}", {}).setdefault(f"{end}:{t}", {
                        "winters_with_at_least_2_runs": [], "winters_with_a_false_rejection": [],
                        "winters_with_a_rejection_not_proven_false": [], "odd_winters_false": [], "even_winters_false": []})
                    cell["winters_with_at_least_2_runs"].append(sum(n >= NEW["k"] for _, n, _ in per))
                    cell["winters_with_a_false_rejection"].append(sum(any(fl[y] for y in h) for _, _, h in per))
                    cell["winters_with_a_rejection_not_proven_false"].append(sum(any(not fl[y] for y in h) for _, _, h in per))
                    cell["odd_winters_false"].append(sum(any(fl[y] for y in h) for s, _, h in per if s % 2))
                    cell["even_winters_false"].append(sum(any(fl[y] for y in h) for s, _, h in per if not s % 2))
    dkey = f"theta{NEW['theta']:g}:tol{NEW['tol']}"
    for key, v in noise["sigma_0"].items():      # control: σ 0 is the noiseless branch, seed for seed
        o = cells[key]["outcome"][dkey]
        assert set(v["winters_with_a_false_rejection"]) == {o["winters_with_a_false_rejection"]}, key
        assert set(v["winters_with_a_rejection_not_proven_false"]) == {o["winters_with_a_rejection_not_proven_false"]}, key
    false_any = [s for s in SIGMAS if any(max(v["winters_with_a_false_rejection"]) > 0 for v in noise[f"sigma_{s:g}"].values())]
    return {"cells": cells, "noise": noise, "poisson": poisson, "ends": ends,
            "least_sigma_with_a_false_rejection_in_any_seed": min(false_any) if false_any else None,
            "containment": {f"{ends[c]}:{t}->{y}": v for (t, y, c), v in contains.items() if t != "none"}}


def new_summary(new: dict, old_winters_with_base: int) -> dict:
    """The figures the sheet and SUMMARY quote, each a min–max over both reflection ends (and the truths named)."""
    cells, ends = new["cells"], new["ends"]
    dkey = f"theta{NEW['theta']:g}:tol{NEW['tol']}"
    th = f"{NEW['theta']:g}"
    groups = {"none": ("none",), "middle": MIDDLE, "favourable_end": ("favourable_end",), "ceiling": ("ceiling",),
              "hybrid": HYBRIDS, "dry": DRY}

    def span(get, truths):
        vals = [get(cells[f"{e}:{t}"]) for e in ends for t in truths]
        return [min(vals), max(vals)]

    def by_group(get):
        return {gname: span(get, ts) for gname, ts in groups.items()}

    def median_span(cell, t, field):
        return sorted(float(np.median(cell[f"{e}:{t}"][field])) for e in ends)

    noise = {s: {"false_rejection_winters_max_over_seeds": max(max(v["winters_with_a_false_rejection"]) for v in cell.values()),
                 "false_rejection_winters_median_over_seeds_max_over_cells": max(float(np.median(v["winters_with_a_false_rejection"])) for v in cell.values()),
                 "cover_free_two_run_winters_max_over_seeds": max(max(cell[f"{e}:none"]["winters_with_at_least_2_runs"]) for e in ends),
                 "not_proven_false_winters_median_over_seeds": {
                     t: median_span(cell, t, "winters_with_a_rejection_not_proven_false") for t in NOISE_TRUTHS[1:]}}
             for s, cell in new["noise"].items()}
    dry = {f"{fam}_{y}": {"winters_reading_rejected": span(lambda c, y=y: c["winters_rejected_by_reading"][y], (f"{fam}_{y}",)),
                          "winters_with_base": span(lambda c: c["winters_with_base"], (f"{fam}_{y}",)),
                          "winters_with_at_least_2_runs": span(lambda c, th=th: c["winters_with_at_least_2_runs"][th], (f"{fam}_{y}",))}
           for fam in ("hybrid", "dry") for y in LIGHTER}
    return {
        "winters": len(cells[f"{ends[0]}:none"]["per_winter"]),
        "verdict_day_share": by_group(lambda c: c["verdict_day_share"]),
        "winters_with_base": by_group(lambda c: c["winters_with_base"]),
        "winters_with_at_least_1_run": by_group(lambda c: c["winters_with_at_least_1_run"][th]),
        "winters_with_at_least_2_runs": by_group(lambda c: c["winters_with_at_least_2_runs"][th]),
        "winters_adverse_r_estimable": by_group(lambda c: c["winters_adverse_r_estimable"]),
        # the ratified trigger as p. 6 sets its frequency: «no deep episode» = a season without a base or with no run
        "winters_camera_question_returns": by_group(lambda c: sum((not r["season_with_base"]) or r["runs"][th] == 0
                                                                  for r in c["per_winter"])),
        "winters_with_exactly_1_run": by_group(lambda c: sum(r["season_with_base"] and r["runs"][th] == 1
                                                             for r in c["per_winter"])),
        "winters_test_b_fires": by_group(lambda c: c["winters_test_b_fires"]),
        "winters_not_proven_false": by_group(lambda c: c["outcome"][dkey]["winters_with_a_rejection_not_proven_false"]),
        "winters_no_rejection": by_group(lambda c: c["outcome"][dkey]["winters_with_no_rejection"]),
        "false_rejection_winters_max": max(c["outcome"][dkey]["winters_with_a_false_rejection"] for c in cells.values()),
        "by_tol_not_proven_false_middle": {f"tol{tol}": span(lambda c, tol=tol: c["outcome"][f"theta{th}:tol{tol}"]["winters_with_a_rejection_not_proven_false"], MIDDLE)
                                           for tol in NEW["tols"]},
        "by_theta_not_proven_false_middle": {f"{t:g}": span(lambda c, t=t: c["outcome"][f"theta{t:g}:tol{NEW['tol']}"]["winters_with_a_rejection_not_proven_false"], MIDDLE)
                                             for t in NEW["thetas"]},
        "odd_even_not_proven_false_middle": {"odd": span(lambda c: c["outcome"][dkey]["odd_winters_not_proven_false"], MIDDLE),
                                             "even": span(lambda c: c["outcome"][dkey]["even_winters_not_proven_false"], MIDDLE)},
        "dry_snow": dry,
        "poisson": new["poisson"],
        "noise": noise,
        "least_sigma_with_a_false_rejection_in_any_seed": new["least_sigma_with_a_false_rejection_in_any_seed"],
        "before": {"winters_with_base_old_rules": old_winters_with_base}}


def main() -> int:
    banner("HW.54 Р3(б)(4) — the stem-face cover rules, rehearsed on ERA5 1991–2020 before the logger")
    wx = S79.load_weather()
    times = wx["time"]
    st = S79.site()
    sun = S79.sun_enu(times, st)
    gc, _ = S79.face_factors(sun)
    _, ghi = S110.irradiance(wx, sun, gc)
    ghi_here = wx["dni"] * np.maximum(sun[2], 0.0).mean(axis=1) + wx["dif"]
    assert np.allclose(ghi, ghi_here, rtol=0, atol=1e-9), "control 4: GHI is not 110's"
    snow = S79.load_snow(times)
    rise = {n: np.concatenate([[0], np.rint(np.diff(r["depth_m"]) * 1000.0).astype(int)]) for n, r in snow.items()}
    assert np.all(rise["era5_land"] % 10 == 0), "control 2: ERA5-Land rises are not whole centimetres"
    t_air, cloud = wx["t_air"], wx["cloud"]
    rh_ice = S79.vapour_pressure_hpa(wx["t_dew"]) / S115.e_ice_hpa(t_air)

    day_str = np.array([t[:10] for t in times])
    days, first_idx = np.unique(day_str, return_index=True)
    bounds = [*first_idx, len(times)]
    n_days = len(days)
    month = np.array([int(d[5:7]) for d in days])
    year = np.array([int(d[:4]) for d in days])
    season_year = np.where(month == 12, year + 1, year)
    in_season = np.isin(month, MONTHS) & (season_year >= 1992) & (season_year <= 2020)

    lit = ghi > 0.0
    ghi_kwh = np.zeros(n_days)
    dif_share = np.full(n_days, np.nan)
    depth = np.zeros(n_days)
    frost_old, frost_draft = np.zeros(n_days, bool), np.zeros(n_days, bool)
    ev_old, ev_draft, ev_cerra_only = np.zeros(n_days, bool), np.zeros(n_days, bool), np.zeros(n_days, bool)
    last_lit_prev = None
    for k in range(n_days):
        a, b = bounds[k], bounds[k + 1]
        g = ghi[a:b]
        ghi_kwh[k] = g.sum() / 1000.0
        dif_share[k] = wx["dif"][a:b].sum() / g.sum() if g.sum() > 0 else np.nan
        depth[k] = snow["era5_land"]["depth_m"][a:b].mean()
        lit_idx = np.nonzero(lit[a:b])[0]
        first_lit = a + (lit_idx[0] if len(lit_idx) else b - a)
        if last_lit_prev is not None:
            night = slice(last_lit_prev + 1, first_lit)
            cold = t_air[night] < 0.0
            frost_old[k] = bool(np.any(cold & (rh_ice[night] >= OLD["frost_rh_ice"])))
            clear_frost = (cloud[night] <= DRAFT["frost_cloud_clear_max"]) & (rh_ice[night] >= DRAFT["frost_rh_ice_clear"])
            frost_draft[k] = runs_at_least(cold & (clear_frost | (rh_ice[night] >= DRAFT["frost_rh_ice_any_sky"])),
                                           DRAFT["frost_run_h"])
        last_lit_prev = a + (lit_idx[-1] if len(lit_idx) else -1)
        cold1 = t_air[a:b] <= OLD["snow_ceiling_max_c"]
        e5, ce = rise["era5_land"][a:b], rise["cerra"][a:b]
        ceiling = ((e5 >= OLD["snow_ceiling_mm"]) | (ce >= OLD["snow_ceiling_mm"])) & cold1
        nrel = e5 >= OLD["nrel_mm"]
        ev_old[k] = bool(np.any(ceiling | nrel))
        ev_draft[k] = bool(np.any((e5 >= DRAFT["snow_mm"]) & (t_air[a:b] <= DRAFT["snow_max_c"])))
        ev_cerra_only[k] = (bool(np.any((ce >= OLD["snow_ceiling_mm"]) & cold1))
                            and not bool(np.any((e5 >= OLD["snow_ceiling_mm"]) & cold1)))

    def spread(mask: np.ndarray, after: int) -> np.ndarray:
        out = mask.copy()
        for s in range(1, after + 1):
            out[s:] |= mask[:-s]
        return out

    cand_old_frost = spread(frost_old, OLD["days_after"])
    cand_old = cand_old_frost | spread(ev_old, OLD["days_after"])
    cand_draft = frost_draft | spread(ev_draft, DRAFT["days_after"])
    assert not np.any(cand_draft & ~cand_old), "control 3: a draft candidate the written rules do not flag"
    judgeable = ghi_kwh >= GHI_MIN_KWH
    gstate = np.array([ground_state(d) for d in depth])
    dclass = np.array([diffuse_class(s) if np.isfinite(s) else "none" for s in dif_share])

    def overcast_hours(day_ids) -> int:
        h = 0
        for i in day_ids:
            sl = slice(bounds[i], bounds[i + 1])
            g = ghi[sl]
            h += int(np.sum((g >= OVERCAST_HOUR["ghi_min_w_m2"])
                            & (wx["dif"][sl] >= OVERCAST_HOUR["diffuse_share_min"] * np.maximum(g, 1e-9))))
        return h

    winters = sorted(set(season_year[in_season]))
    per_winter = {}
    for w in winters:
        idx = np.nonzero(in_season & (season_year == w))[0]
        terc = {}
        for gs in ("bare", "intermediate", "snow"):
            vals = dif_share[idx][judgeable[idx] & (gstate[idx] == gs)]
            terc[gs] = np.quantile(vals, [1 / 3, 2 / 3]) if len(vals) >= 3 else None

        def tercile(i, terc=terc):
            q = terc[gstate[i]]
            return None if q is None else int(np.searchsorted(q, dif_share[i], side="right"))
        judged_old = np.zeros(len(idx), bool)
        for j, i in enumerate(idx):
            if not judgeable[i]:
                continue
            ti = tercile(i)
            for half in OLD["window_d"]:
                pool = [m for m in idx if abs(m - i) <= half and m != i and judgeable[m] and not cand_old[m]
                        and gstate[m] == gstate[i] and tercile(m) == ti]
                if len(pool) >= OLD["pool_min"]:
                    judged_old[j] = True
                    break
        base_draft = judgeable[idx] & ~cand_draft[idx]
        judged_draft = np.zeros(len(idx), bool)
        fallback = 0
        for j, i in enumerate(idx):
            if not judgeable[i]:
                continue
            same = [m for m in idx[base_draft] if m != i and gstate[m] == gstate[i]]
            pool = [m for m in same if dclass[m] == dclass[i]]
            if len(pool) < DRAFT["pool_min"]:
                pool, fallback = same, fallback + 1
            if len(pool) >= DRAFT["pool_min"]:
                assert not np.any(cand_draft[pool]), "control 3: a candidate day in a base pool"
                judged_draft[j] = True
        bare = idx[judgeable[idx] & (gstate[idx] == "bare")]
        shallow = idx[judgeable[idx] & (gstate[idx] != "snow")]
        per_winter[f"{w - 1}/{w % 100:02d}"] = {
            "days": len(idx),
            "old_candidate_share": {"frost": round(float(cand_old_frost[idx].mean()), 4), "all": round(float(cand_old[idx].mean()), 4)},
            "old_judged_share": round(float(judged_old.mean()), 4),
            "draft_candidate_share": round(float(cand_draft[idx].mean()), 4),
            "draft_candidate_share_frost": round(float(frost_draft[idx].mean()), 4),
            "draft_judged_share": round(float(judged_draft.mean()), 4),
            "draft_fallback_days": fallback,
            "judgeable_share": round(float(judgeable[idx].mean()), 4),
            "overcast_hours_upper_bound": {"bare": overcast_hours(bare), "bare_or_intermediate_upward_biased": overcast_hours(shallow)},
            "ground_state_days": {gs: int(np.sum(gstate[idx] == gs)) for gs in ("bare", "intermediate", "snow")},
            "cerra_only_ceiling_event_days": int(ev_cerra_only[idx].sum())}

    def col(key, sub=None):
        return np.array([(v[key][sub] if sub else v[key]) for v in per_winter.values()])

    all_days = np.nonzero(in_season)[0]
    old_frost_all = float(cand_old_frost[all_days].mean())
    old_all = float(cand_old[all_days].mean())
    old_judged = float(np.average(col("old_judged_share"), weights=col("days")))
    lo5 = 0.05
    assert abs(old_frost_all - ADVERSARY["old_frost_candidate_share"]) <= lo5, ("control 1: frost", old_frost_all)
    assert ADVERSARY["old_all_candidate_share"][0] - lo5 <= old_all <= ADVERSARY["old_all_candidate_share"][1] + lo5, ("control 1", old_all)
    assert abs((1 - old_judged) - ADVERSARY["old_not_judged_share"]) <= lo5, ("control 1: not judged", 1 - old_judged)
    dj = col("draft_judged_share")
    bare_h, shallow_h = col("overcast_hours_upper_bound", "bare"), col("overcast_hours_upper_bound", "bare_or_intermediate_upward_biased")
    summary = {
        "winters": len(per_winter),
        "old": {"candidate_share_frost": round(old_frost_all, 4), "candidate_share_all": round(old_all, 4),
                "judged_share_all_days": round(old_judged, 4),
                "winters_with_no_day_judged": int(np.sum(col("old_judged_share") == 0.0))},
        "draft_2026_11_10_rejected": {
            "candidate_share_all": round(float(cand_draft[all_days].mean()), 4),
            "candidate_share_frost_of_all_days": round(float(frost_draft[all_days].mean()), 4),
            "judged_share_median_winter": round(float(np.median(dj)), 4), "judged_share_min_winter": round(float(dj.min()), 4),
            "fallback_days": int(col("draft_fallback_days").sum()),
            "rejected_because": "judgeability does not discriminate: the class fallback manufactures dips on a cover-free face, "
                                "the episode count does not move with cover, the frost rule is narrower than 115's frost "
                                "(adversary 2026-11-10; requirements for the next rewrite — 00_07 HW.54)"},
        "overcast_hours_upper_bound": {
            "bare_median_winter": float(np.median(bare_h)), "bare_winters_with_none": int(np.sum(bare_h == 0)),
            "bare_winters_under": {str(n): int(np.sum(bare_h < n)) for n in OVERCAST_HOURS_PRINTED},
            "bare_or_intermediate_median_winter": float(np.median(shallow_h)),
            "bare_or_intermediate_winters_under": {str(n): int(np.sum(shallow_h < n)) for n in OVERCAST_HOURS_PRINTED}},
        "cerra_only_ceiling_event_days_per_winter": {"median": float(np.median(col("cerra_only_ceiling_event_days"))),
                                                     "max": int(col("cerra_only_ceiling_event_days").max())},
        "judgeable_share_median_winter": round(float(np.median(col("judgeable_share"))), 4)}

    new = rehearse_new_rules(wx, sun, gc, ghi, snow, rise["era5_land"], first_idx, season_year, in_season, judgeable,
                             depth, dif_share)
    summary["rules_2026_11_15"] = new_summary(new, int(np.sum(col("old_judged_share") >= NEW["season_base_min_share"])))

    print(json.dumps(summary, indent=1, ensure_ascii=False))
    for w, v in per_winter.items():
        print(f"  {w}: old cand {v['old_candidate_share']['all']:.2f} judged {v['old_judged_share']:.2f} | draft cand "
              f"{v['draft_candidate_share']:.2f} judged {v['draft_judged_share']:.2f} (fallback {v['draft_fallback_days']}) | "
              f"overcast h ≤ {v['overcast_hours_upper_bound']} | ground {v['ground_state_days']}")

    OUT.write_text(json.dumps({
        "script": Path(__file__).name, "leg": "00_07 HW.54 Р3(б)(4)",
        "what": "the stem-face cover rules (the sheet's §6 pp. 1–4) rehearsed on ERA5 1991–2020 December–February: the share "
                "of days the rules as written and a rejected draft can judge against a base of non-candidate days, the CERRA "
                "event days the season cannot have, and an upper bound on the overcast bare-ground hours per winter",
        "inputs": {"months": MONTHS, "ghi_min_kwh_m2": GHI_MIN_KWH, "rules_as_written": OLD, "draft_2026_11_10_rejected": DRAFT,
                   "overcast_hour": OVERCAST_HOUR, "overcast_hours_printed": OVERCAST_HOURS_PRINTED,
                   "ground_edges_m_79": sorted(e[2] for e in S79.REFLECT_ENDS), "adversary_reproduced": ADVERSARY,
                   "sources": {"weather": "79's load_weather (ERA5 hourly, dew point, cloud)", "ghi": "110's irradiance",
                               "snow": "79's load_snow (ERA5-Land · CERRA)", "ice_saturation": "115's e_ice_hpa",
                               "cerra_end": "CERRA's last hour at this point: 2021-06-30T23:00 UTC (Open-Meteo archive, "
                                            "probed 2026-11-10)"}},
        "controls": {"reproduces_the_adversary_within": lo5, "era5_land_rises_whole_cm": True,
                     "draft_candidates_subset_of_written": True, "ghi_is_110s": True,
                     "dry_window_leaves_the_ceiling_and_nests_melt_only": True,
                     "no_run_on_a_cover_free_perfect_logger": True, "no_reading_rejected_under_itself_tautology": True,
                     "no_rejected_reading_contains_a_surviving_one": True, "noise_at_sigma_0_is_the_noiseless_branch": True},
        "summary": summary, "per_winter": per_winter,
        "rules_2026_11_15": {
            "what": "the rules rewritten 2026-11-15 on a perfect logger: the south face lit by ERA5 under each truth's cover "
                    "(115's cover_readings, CERRA held flat; a hybrid is the ceiling's snow with a middle reading's frost), "
                    "the base the record offers (124's functions), runs, the coverage test, the Poisson bar from 124's "
                    "cover-free face under the second sky, and a log-normal day noise over seeds",
            "inputs": {"rules": NEW, "declared_not_rehearsed": DECLARED_NOT_REHEARSED,
                       "base_windows_d": S124.WINDOWS_D, "base_min_days": S124.BASE_MIN_DAYS,
                       "truths": TRUTHS, "analyst_readings": ANALYST, "sigmas": SIGMAS, "seeds": SEEDS,
                       "noise_truths": NOISE_TRUTHS, "analyst_air": "the truth's (ERA5's) — the rule of two airs is 124's",
                       "base_runs_misses": "124's base_from_record · terciles · runs_below · misses (imported)"},
            "cells": new["cells"], "noise": new["noise"], "containment": new["containment"]}}, indent=2, ensure_ascii=False))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
