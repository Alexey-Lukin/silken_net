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
test the next rewrite needs is a PERFECT-LOGGER rehearsal — the modelled face under each `115` reading's cover and under
none, the rules asked to keep the truth and reject the rest — which this script does not run.

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

WHAT IT CANNOT SEE. The logger: R itself, its dips, the false-dip rate — the rehearsal counts what the rules can JUDGE, not
what they will find, and not whether they DISCRIMINATE (the perfect-logger rehearsal above). ERA5's RH at 2 m in an open
cell for the logger's RH by a trunk under a crown; a cell, not the yard (ERA5-Land overstates snow cover — the data
README); the season's own clock (the files run on a fixed UTC+3; a query's offset is the zone's at the moment of the
query — the sheet's §5).

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

Run:  python tools/in_silico/scripts/117_stem_face_cover_rules_rehearsal.py      # under a minute
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import KINETICS_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("A rehearsal, on thirty winters of hourly reanalysis weather, of the rules a single light logger on a pine "
                  "stem's face will be read by: how many winter days the rules as first written, and a rejected draft "
                  "rewrite, can judge against a base of cover-free days, and how many overcast hours on bare ground a winter "
                  "offers at most.")

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


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S115 = _load("s115_cover", "115_pv_face_snow_frost_azimuth.py")
S110, S79 = S115.S110, S115.S79


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
                     "draft_candidates_subset_of_written": True, "ghi_is_110s": True},
        "summary": summary, "per_winter": per_winter}, indent=2, ensure_ascii=False))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
