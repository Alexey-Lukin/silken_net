#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""118 — how often a single season of a single logger on the south face can tell the four `115` readings of snow and
hoarfrost cover apart, on a PERFECT logger, under three readings of the coverage test and the sheet's literal count test
(00_07 HW.54, the leg «Р3(б)(4) — переписати правила розбору покриву ДО даних»; the sheet
`docs/protocols/ebfc/stem_face_winter_light.md` §6).

WHY. Two rewrites of the sheet's §6 pp. 3–7 failed their adversaries (2026-11-10): the first judged too few days, the
second held on one noise seed, and its adversary measured that a typical season would most likely end «not judged».
Before a third rule set is tuned, this script measures what the TRUTH offers to be found: on a perfect logger — no
noise, no crown, the base known exactly, the true cover known hour by hour — in how many winters does the true reading
leave at least two episodes that another reading does not cover? If that were low under every reading of the test, the
ratified answer to «no deep episodes» (01_03 §4 ⚖️ «Польова відповідь Р3(б)», 2026-11-01: the camera question returns)
would be due before the data.
⚠️ This is NOT a ceiling on every rule. A first version (2026-11-11) called its one test a ceiling; its adversary
measured that a stricter coverage test and episodes without the 0.8 merge reject MORE often on the same perfect logger —
coverage on «any day of the episode» weakens as episodes grow, so granting the rules perfect knowledge can LOWER power —
and that the clearing decision, which this script does not model, is a further channel. The variants are therefore
measured side by side, and the result is a measured power per test, not a bound.

MODEL.
  THE FACE — `115`'s south face: light dni·gc[180] + ½dif + ½refl at each of `79`'s two reflection ends, cover from
    `115`'s `cover_readings` (the ONE home of the cover model) on the season's own record (CERRA held flat — it ends
    2021-06-30T23:00 UTC at this point, `117`).
  A DAY's transmitted share under reading X — Σ g·(1 − c_X) / Σ g over the day's lit hours; with the base known exactly,
    R_d / R_base IS this share. A day with ΣGHI < 0.1 kWh/m² is not judged and neither starts, continues nor breaks an
    episode (the sheet's p.1, p.6). No candidate-day restriction.
  EPISODES of truth T — «merged»: a start on a judged day with T's share < 0.5, a run while judged days stay < 0.8 (p.5,
    p.6); «runs»: consecutive judged days with T's share < 0.5 only.
  A MISS of reading Y (the leg's requirement (2), a coverage test, in three readings):
    lenient — Y's share is ≥ 0.5 on EVERY judged day of a merged episode (Y covers none of it);
    strict  — Y's share is ≥ 0.5 on AT LEAST ONE dip day (T < 0.5) of a merged episode (Y does not keep the face
              covered on every recorded dip day);
    runs    — the lenient test on «runs» episodes.
    Y is rejectable in a winter with ≥ k misses (k = 2, the sheet's p.7; k = 1 beside it).
  THE COUNT TEST — the sheet's p.7 last bullet (without p.6's candidate-day start): Y is rejected when the record (T)
    shows at least 2 more merged episodes than Y gives. Printed for every ordered pair, including readings that cover MORE than the truth — where a rejection
    is an artefact of counting (a longer cover merges into fewer episodes).
  NOISE on the lenient test — a miss stays visible if any of its judged days reads as a dip under the log-normal
    cell-vs-yard term share·exp(σz − σ²/2) < 0.5, independent per day; the chance that ≥ k of a winter's misses are
    visible is an exact Poisson-binomial sum; a continuation day (0.5–0.8) that noise pushes below 0.5 counts too, so
    noise-made dips are credited as power. Not modelled: noise splitting or merging episodes, and every noise dip that
    makes a TRUE reading look as if it misses (the false-rejection side).
  THE BASE THE RECORD OFFERS (`truths`) — everything above grants an exact base. The sheet's p.4 estimates it from the
    record's own cover-free days (≥ 5 needed), so per truth the script counts the judged days the truth leaves at share
    ≥ 0.8 and the mean transmitted share over the judged days — where the first is small, a base from the record fails
    and the power above is not reachable by p.4 (it costs missed detections, not only false rejections), while the
    second is the factor by which cover alone lowers the measured R that §6's first rule reads directly.

WHAT IT CANNOT SEE. The yard against the cell, a crown, sensor offsets, cosine and spectral errors, the logger's clock,
the hourly signature, fog and rime (`115` has none), a house's shadow, the hybrid reading (ceiling snow with a surviving
reading's frost — not in `115`), and the decisions other than coverage and count (dry snow; clearing). A test with high
power here is necessary for the field question to be answerable through it, never sufficient.

CONTROLS (each says what it CAN and CANNOT catch).
  (1) With CERRA as `115` reads it, the south face's share of winter light lost to each reading at both ends equals
      `115`'s cached `light_lost_share_of_winter_harvest`; CAN catch a wrong column, end, face or cover call, CANNOT an
      error inside `115`'s cover model.
  (2) GHI is `110`'s `irradiance` GHI hour by hour; CAN catch a different sun or column.
  (3) The episode functions on a synthetic winter give the right days, merged and runs; CAN catch an off-by-one or a
      not-judged day that starts, continues or breaks, CANNOT a wrong threshold value.
  (4) Where Y covers every hour T covers (c_Y ≥ c_T hour by hour), Y misses nothing under all three readings — asserted
      per pair, end and winter; the cache records how many of those checks held a truth episode at all (the rest cannot
      fail); CAN catch a miss computed on the wrong reading or day, CANNOT one wrong the same way for both readings.
"""

from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import KINETICS_DIR
from lib.utils import banner

SI_DESCRIPTION = ("How often one winter of a single light logger on a pine stem's face could tell four models of snow and "
                  "hoarfrost cover apart, on a perfect logger with the true cover known hour by hour, under several "
                  "readings of a coverage test, over 29 winters of hourly reanalysis weather.")

HERE = Path(__file__).resolve().parent
OUT = KINETICS_DIR / "stem_face_cover_power.json"
PV115 = KINETICS_DIR / "pv_face_snow_frost_azimuth.json"
MONTHS = (12, 1, 2)
SEASONS = (1992, 2020)                    # the record's 29 full Dec–Feb seasons (Dec 1991 … Feb 2020)
READINGS = ("ceiling", "melt_only", "nrel_published", "favourable_end")
GHI_MIN_KWH = 0.1                          # p.1: a day below it is not judged
DIP, CONT = 0.5, 0.8                       # p.5 · p.6
COVERED = 0.5                              # requirement (2): a day «covered» by Y below this share
KS = (1, 2)                                # p.7 decides on k = 2; k = 1 printed beside it
COUNT_MARGIN = 2                           # p.7 as written: the record shows ≥ 2 more episodes than Y gives
SIGMAS = (0.0, 0.1, 0.2, 0.3, 0.4, 0.5)    # a scale to past the cliff, not a grid that stops before it (#11, #54)
TESTS = ("lenient", "strict", "runs")


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S115 = _load("s115_cover_118", "115_pv_face_snow_frost_azimuth.py")
S110, S79, S71 = S115.S110, S115.S79, S115.S71


def episodes_merged(share: np.ndarray, judged: np.ndarray) -> list:
    """p.5 + p.6: a start on a judged day below DIP, a run while judged days stay below CONT; a day not judged neither
    starts, continues nor breaks one. Returns the judged day indices of each episode."""
    eps, cur = [], None
    for d in range(len(share)):
        if not judged[d]:
            continue
        if cur is None:
            if share[d] < DIP:
                cur = [d]
        elif share[d] < CONT:
            cur.append(d)
        else:
            eps.append(cur)
            cur = None
    if cur is not None:
        eps.append(cur)
    return eps


def episodes_runs(share: np.ndarray, judged: np.ndarray) -> list:
    """Consecutive judged days below DIP only (a day not judged neither continues nor breaks a run)."""
    eps, cur = [], None
    for d in range(len(share)):
        if not judged[d]:
            continue
        if share[d] < DIP:
            cur = [d] if cur is None else [*cur, d]
        elif cur is not None:
            eps.append(cur)
            cur = None
    if cur is not None:
        eps.append(cur)
    return eps


def control_episodes() -> None:
    s = np.array([1.0, 0.4, 0.7, 0.1, 0.9, 0.3, 0.45, 1.0])
    j = np.array([True, True, True, False, True, True, True, True])
    assert episodes_merged(s, j) == [[1, 2], [5, 6]], episodes_merged(s, j)    # day 3 is not judged
    assert episodes_runs(s, j) == [[1], [5, 6]], episodes_runs(s, j)
    assert episodes_merged(np.array([0.6, 0.7, 0.9]), np.ones(3, bool)) == []


def p_at_least(probs: list, k: int) -> float:
    """P(≥ k successes) for independent Bernoulli trials — the Poisson-binomial tail, by dynamic programming."""
    dist = np.zeros(len(probs) + 1)
    dist[0] = 1.0
    for p in probs:
        dist[1:] = dist[1:] * (1.0 - p) + dist[:-1] * p
        dist[0] *= 1.0 - p
    return float(dist[k:].sum())


def dip_prob(share: float, sigma: float) -> float:
    """P(share · exp(σz − σ²/2) < DIP) for a standard normal z — one day reads as a dip."""
    if sigma == 0.0:
        return 1.0 if share < DIP else 0.0
    if share <= 0.0:
        return 1.0
    zc = (math.log(DIP / share) + sigma ** 2 / 2.0) / sigma
    return 0.5 * (1.0 + math.erf(zc / math.sqrt(2.0)))


def visible(day_shares: list, sigma: float) -> float:
    """P(at least one judged day of a miss reads as a dip), days independent."""
    return 1.0 - float(np.prod([1.0 - dip_prob(x, sigma) for x in day_shares]))


def main() -> int:
    banner("HW.54 Р3(б)(4) — how often one season of one logger can tell the cover readings apart (perfect logger)")
    control_episodes()
    z115 = json.loads(PV115.read_text())
    wx = S79.load_weather()
    times = wx["time"]
    sun = S79.sun_enu(times, S79.site())
    gc, _ = S79.face_factors(sun)
    _, ghi = S110.irradiance(wx, sun, gc)
    assert np.allclose(ghi, wx["dni"] * np.maximum(sun[2], 0.0).mean(axis=1) + wx["dif"], rtol=0, atol=1e-9), "control 2"
    snow = S79.load_snow(times)
    refl = S79.reflected_rows(snow, ghi)
    ends = [e[0] for e in S79.REFLECT_ENDS]
    j180 = list(S79.AZIMUTHS_DEG).index(180)
    g = np.stack([wx["dni"] * gc[j180] + 0.5 * wx["dif"] + 0.5 * refl[k] for k in range(1, len(ends) + 1)], axis=1)
    d_dome = S71.geometry()["dome_diameter_mm"] / 1000.0

    # control (1): with CERRA as 115 reads it, the light-lost shares are 115's
    full = S115.cover_readings(wx, g, snow, d_dome)["covers"]
    winter_h = np.isin(times.astype("datetime64[M]").astype(int) % 12 + 1, S115.WINTER_MONTHS)
    control1 = 0
    for c, end in enumerate(ends):
        for rd in READINGS:
            want = z115["covers"][f"open_face_180.{end}:{rd}"]["light_lost_share_of_winter_harvest"]
            got = round(float((g[:, c] * full[rd][0][:, c])[winter_h].sum() / g[:, c][winter_h].sum()), 4)
            assert got == want, ("control 1", end, rd, got, want)
            control1 += 1

    # the season's record: CERRA flat
    snow_season = {"era5_land": snow["era5_land"],
                   "cerra": {**snow["cerra"], "depth_m": np.zeros_like(snow["cerra"]["depth_m"])}}
    cov = S115.cover_readings(wx, g, snow_season, d_dome)["covers"]

    # days
    day_str = np.array([t[:10] for t in times.astype(str)])
    days, first_idx = np.unique(day_str, return_index=True)
    month = np.array([int(d[5:7]) for d in days])
    year = np.array([int(d[:4]) for d in days])
    season_year = np.where(month == 12, year + 1, year)
    lit = ghi > 0.0

    def daysum(x):
        return np.add.reduceat(np.where(lit, x, 0.0), first_idx)

    judged_all = daysum(ghi) / 1000.0 >= GHI_MIN_KWH
    face = np.stack([daysum(g[:, c]) for c in range(len(ends))], axis=1)                     # (days, ends)
    safe_face = np.where(face > 0, face, 1.0)
    share = {rd: np.stack([np.where(face[:, c] > 0, daysum(g[:, c] * (1.0 - cov[rd][0][:, c])) / safe_face[:, c], 1.0)
                           for c in range(len(ends))], axis=1) for rd in READINGS}
    contains = {(t, y): [bool(np.all(cov[y][0][:, c] >= cov[t][0][:, c] - 1e-12)) for c in range(len(ends))]
                for t in READINGS for y in READINGS if t != y}

    seasons = list(range(SEASONS[0], SEASONS[1] + 1))
    sel_of = {sy: np.nonzero(np.isin(month, MONTHS) & (season_year == sy))[0] for sy in seasons}

    # what the record itself offers a base, per truth: judged days the truth leaves free of cover (share ≥ CONT — the
    # days a base estimated FROM THE RECORD could stand on; the sheet's p.4 asks for ≥ 5), and the mean transmitted share
    # over the judged days — the factor by which cover alone lowers the measured R that §6's first rule reads directly
    truths = {}
    for c, end in enumerate(ends):
        for t in READINGS:
            free = [int(np.sum(judged_all[sel_of[sy]] & (share[t][sel_of[sy], c] >= CONT))) for sy in seasons]
            mean_share = [float(share[t][sel_of[sy], c][judged_all[sel_of[sy]]].mean()) for sy in seasons]
            truths[f"{end}:{t}"] = {"cover_free_judged_days_per_winter": free,
                                    "winters_with_fewer_than_5_cover_free_judged_days": sum(f < 5 for f in free),
                                    "median_cover_free_judged_days": float(np.median(free)),
                                    "mean_transmitted_share_over_judged_days_per_winter": [round(x, 4) for x in mean_share],
                                    "median_winter_mean_transmitted_share": float(np.median(mean_share))}
    out_pairs, c4_checks, c4_nonempty = {}, 0, 0
    for c, end in enumerate(ends):
        for t in READINGS:
            for y in READINGS:
                if t == y:
                    continue
                per_winter = []
                for sy in seasons:
                    sel = sel_of[sy]
                    jd, st, sy_ = judged_all[sel], share[t][sel, c], share[y][sel, c]
                    merged, runs = episodes_merged(st, jd), episodes_runs(st, jd)
                    miss = {"lenient": [e for e in merged if not np.any(sy_[e] < COVERED)],
                            "strict": [e for e in merged if np.any(sy_[[d for d in e if st[d] < DIP]] >= COVERED)],
                            "runs": [e for e in runs if not np.any(sy_[e] < COVERED)]}
                    if contains[(t, y)][c]:
                        assert not any(miss.values()), ("control 4", end, t, y, sy)
                        c4_checks += 1
                        c4_nonempty += bool(merged)
                    n_y = len(episodes_merged(sy_, jd))
                    per_winter.append({
                        "season": sy, "episodes_merged": len(merged), "episodes_runs": len(runs),
                        "episodes_of_reading_merged": n_y, "count_test_rejects": len(merged) - n_y >= COUNT_MARGIN,
                        **{f"misses_{m}": len(v) for m, v in miss.items()},
                        "lenient_miss_day_shares": [[round(float(st[d]), 4) for d in e] for e in miss["lenient"]]})
                counts = {f"{m}:k{k}": sum(w[f"misses_{m}"] >= k for w in per_winter) for m in TESTS for k in KS}
                noise = {}
                for sigma in SIGMAS:
                    for k in KS:
                        p = [p_at_least([visible(e, sigma) for e in w["lenient_miss_day_shares"]], k) for w in per_winter]
                        even = [pp for pp, w in zip(p, per_winter, strict=True) if w["season"] % 2 == 0]
                        odd = [pp for pp, w in zip(p, per_winter, strict=True) if w["season"] % 2 == 1]
                        noise[f"sigma_{sigma:g}:k{k}"] = {"expected_winters": float(np.sum(p)),
                                                          "even_seasons": float(np.sum(even)),
                                                          "odd_seasons": float(np.sum(odd))}
                out_pairs[f"{end}:{t}->{y}"] = {
                    "truth": t, "reading": y, "end": end, "y_covers_every_hour_t_covers": contains[(t, y)][c],
                    "winters": len(per_winter), "winters_rejectable": counts,
                    "count_test_winters": sum(w["count_test_rejects"] for w in per_winter),
                    "truth_episodes_merged_mean": float(np.mean([w["episodes_merged"] for w in per_winter])),
                    "lenient_noise": noise, "per_winter": per_winter}
    assert c4_checks > 0 and c4_nonempty > 0, "control 4 never held a truth episode"

    print("  truth (end)        cover-free judged days per winter (median) · winters < 5 · median winter mean share")
    for key, v in truths.items():
        print(f"  {key:<22s} {v['median_cover_free_judged_days']:5.1f} · "
              f"{v['winters_with_fewer_than_5_cover_free_judged_days']:2d} · {v['median_winter_mean_transmitted_share']:.3f}")
    print("  truth → reading (end)                 winters with ≥ 2 misses: lenient · strict · runs   ≥1 (lenient)   count test")
    for r in out_pairs.values():
        w = r["winters_rejectable"]
        print(f"  {r['truth']:>14s} → {r['reading']:<14s} ({r['end']:<4s})  {w['lenient:k2']:3d} · {w['strict:k2']:3d} · "
              f"{w['runs:k2']:3d}            {w['lenient:k1']:3d}          {r['count_test_winters']:3d}"
              f"{'   (covers every hour)' if r['y_covers_every_hour_t_covers'] else ''}")

    OUT.write_text(json.dumps({
        "question": "00_07 HW.54 Р3(б)(4): how often one season of one south-face logger can reject a reading under three "
                    "readings of the coverage test and the sheet's count test, on a perfect logger — a measured power "
                    "per test, not a ceiling on every rule",
        "inputs": {"months": list(MONTHS), "seasons": list(SEASONS), "readings": list(READINGS), "ends": ends,
                   "ghi_min_kwh": GHI_MIN_KWH, "dip": DIP, "continuation": CONT, "covered": COVERED, "ks": list(KS),
                   "count_margin": COUNT_MARGIN, "sigmas": list(SIGMAS), "tests": list(TESTS),
                   "cerra_on_season": "held flat (ends 2021-06-30T23:00 UTC at this point)"},
        "controls": {"115_light_lost_shares_checked": control1, "ghi": "110 irradiance", "episode_functions": "synthetic",
                     "containment_checks": c4_checks, "containment_checks_with_a_truth_episode": c4_nonempty},
        "truths": truths,
        "pairs": out_pairs,
    }, indent=2))
    print(f"[118] wrote {OUT.relative_to(HERE.parents[2])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
