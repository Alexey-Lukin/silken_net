#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""100 — Stage-2 coin replicate power: what 2…6 replicate coupons per arm can tell apart (00_07 HW.24, the leg
«таблиця потужності реплік»; no SCF, no measured spread).

WHY. 01_03 §3.5 leaves the number of replicates per arm «after the lab's prices». These rows turn that into a choice of
a row by price — but the coin carries three DIFFERENT kinds of decision, and «power» is a different quantity for each:
  two_arm   — a contrast of two arms (the matched ZIF pair on Ti-6Al-4V · any two alloys · the cathode on gold against
              titanium, branches (1)/(2) of the cathode-lever rule, 01_03 §3.2): the smallest ratio of the two arms'
              geometric means a two-sample t-test on log values detects with power P_TARGET at two-sided ALPHA.
              Below it the contrast reads «≈» by default, not by measurement — and the lever rule ACTS on «≈».
  gate      — one arm against a fixed threshold (C · D · E, 01_03 §3.5). Canon writes «≥ threshold» without saying of
              WHAT; three readings are carried, and they move in OPPOSITE directions with n: the arm's geometric mean ·
              its one-sided (1 − ALPHA) lower confidence bound · every coupon. Output: the margin above the threshold a
              good arm needs to pass with probability P_TARGET (one table serves every gate — the threshold cancels in
              a ratio), the pass probability of an arm sitting exactly at the threshold, the pass probability where
              canon names the value it expects (D's +7.5 % target; E's full recovery, which IS its threshold), and the
              largest CV at which each gate's best case (BEST_CASE) still passes.
  selection — the down-select among the Zone-1 candidates (every alloy but the control and the coin-only benchmark,
              01_02 §2.5 · lib.constants COIN_BENCHMARK_ALLOYS): the ratio by which the best candidate must exceed the
              others (all equal — the least favourable configuration) for the highest sample geometric mean to pick it
              with probability P_TARGET. Conditional: canon names no rule that combines current, retention and the
              ICP-MS rank into a winner; this is the reading «one current metric decides».
  budget    — coupons each alloy needs at n per arm against the coupon letter's quote point, and the units the lab
              prices per n (A coupons · C channel-days · D · E).

MODEL. Each coupon's value (a current density, a retention, a recovery ratio) is log-normal around its arm's geometric
mean with one coefficient of variation CV in every arm; σ = sqrt(ln(1 + CV²)) on the log scale. The CV grid is ASSUMED:
no coin has been measured, and the lab's stated repeatability of repeated scans on ONE coupon (test A) is a FLOOR on the
between-coupon CV, not its value — loading and etch spread add to it.
Two readings of WHERE the spread is estimated, a bracket, never a pick (in-silico §When Modifying #11):
  own    — from the coupons of the contrast or the arm itself (df = na + nb − 2 · n − 1): robust if the arms' spreads
           differ; the adverse end.
  pooled — over every arm that measures the SAME quantity, valid only if they share one CV (this model's assumption):
           the 30-day retention over the C_ARMS arms of the hold, a day-0 cathode current over the CATHODE_ARMS
           titanium-cathode arms (df = arms × (n − 1)); the optimistic end. D's chloride ratio and E's recovery are
           measured on their own arm only, so they have no pooled reading.

CAN: say, inside this model, what each n resolves and which decisions it hands to a default; count the priced units
per n; show where the coupon letter's quote point caps n. A seeded Monte Carlo of the same decision rules (the t-test
in both readings · the three gate readings and the pooled bound · argmax selection) checks every closed form at two
cells and fails the run beyond 4 standard errors (`control`).
CANNOT: (1) give the CV; (2) speak for a metric whose spread is not log-normal, or say which of the two readings holds
(that is whether the arms share one spread — measured only by the coin itself); (3) price anything — it counts, the
quote prices; (4) say which reading of «≥ threshold» canon means, or whether the day-0 cathodes of the flange
candidates are «comparative arms» in the sense of 01_03 §3.5 — both are verdicts; (5) cover the ICP-MS series (n = 3
by the letter; its spread near the LOQ is another metric) or test H; (6) count C channels beyond the anodes and the
Ti-6Al-4V pair — the ratified channel order ends in «→ the rest», which names no arm.

Run:  conda activate silken_md
      python tools/in_silico/scripts/100_coin_replicate_power.py
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy import integrate, optimize, stats

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    COIN_BENCHMARK_ALLOYS,
    COIN_CHLORIDE_MIN_RATIO,
    COIN_CHLORIDE_TARGET_RATIO,
    COIN_CONTROL_ALLOY,
    COIN_ELECTRODE_ARMS,
    COIN_GOLD_COUPONS,
    COIN_HOLD_DAYS,
    COIN_ORDER_CONTROL_HIGH,
    COIN_ORDER_PER_ALLOY,
    COIN_RESERVE_12WK_PER_ALLOY,
    COIN_RETENTION_30D_MIN,
    COIN_UCST_RECOVERY_RATIO,
    COIN_UNCOATED_ICPMS_PER_ALLOY,
    KINETICS_DIR,
    REPO_ROOT,
)
from lib.utils import banner

SI_DESCRIPTION = ("Statistical design of the Stage-2 coin test: the smallest arm-to-arm ratio, the margin above an "
                  "acceptance threshold under three readings of the gate, and the alloy-selection gap that 2–6 replicate "
                  "coupons per arm resolve, under an assumed log-normal coupon-to-coupon spread estimated per contrast "
                  "or pooled over the arms that share it, with the coupon budget per replicate count and a Monte Carlo "
                  "check of every closed form; no SCF")

OUT = KINETICS_DIR / "coin_replicate_power.json"

# Conventions of THIS model, not canon: the replicate range the leg asks for, an ASSUMED spread grid, one probability
# level for every family so the rows read alike, and the Monte Carlo that checks the closed forms.
N_GRID = (2, 3, 4, 5, 6)
CV_ASSUMED = (0.05, 0.10, 0.20, 0.30)
ALPHA = 0.05
P_TARGET = 0.80
READINGS = ("arm_mean", "lower_bound", "every_coupon")
MC_TRIALS = 200_000
MC_SEED = 20261020
MC_CELLS = ((2, 0.30), (4, 0.10))
MC_TOLERANCE_SE = 4.0
# The best case each gate can see, a reading of THIS model: a retention or a recovery above 100 % (drift, rehydration,
# break-in) is not excluded physically, but it is not a stack's design state, so the margin over C's and E's thresholds
# is capped here; D's best case is the canon's own +7.5 % target. From it: the largest CV at which that best case still
# passes with P_TARGET.
BEST_CASE = {"C": (1.00, COIN_RETENTION_30D_MIN), "D": (COIN_CHLORIDE_TARGET_RATIO, COIN_CHLORIDE_MIN_RATIO),
             "E": (1.00, COIN_UCST_RECOVERY_RATIO)}

CANDIDATES = tuple(a for a in COIN_ELECTRODE_ARMS if a != COIN_CONTROL_ALLOY and a not in COIN_BENCHMARK_ALLOYS)
C_ARMS = sum(in_c for arms in COIN_ELECTRODE_ARMS.values() for in_c in arms.values())
CATHODE_ARMS = sum(arm.startswith("cathode") for arms in COIN_ELECTRODE_ARMS.values() for arm in arms)
NON_ELECTRODE = COIN_UNCOATED_ICPMS_PER_ALLOY + COIN_RESERVE_12WK_PER_ALLOY


def sigma_log(cv: float) -> float:
    return math.sqrt(math.log1p(cv * cv))


def pooled_df(arms: int, n: int) -> int:
    return arms * (n - 1)


def two_arm_power(u: float, sigma: float, na: int, nb: int, df: int | None = None) -> float:
    """Power of the two-sample t-test on log values when the arms' log-means differ by u; df defaults to the
    contrast's own coupons, a pooled estimate passes its own."""
    df = na + nb - 2 if df is None else df
    nc = u / (sigma * math.sqrt(1.0 / na + 1.0 / nb))
    tc = stats.t.ppf(1.0 - ALPHA / 2.0, df)
    lower = float(stats.nct.cdf(-tc, df, nc))
    if not math.isfinite(lower):
        # scipy's nct returns NaN for this vanishing tail at large nc. T < −tc < 0 needs Z + nc < 0, so the tail is at
        # most Φ(−nc): take 0 only where that bound is negligible, never as a silent stand-in.
        if stats.norm.cdf(-nc) > 1e-9:
            raise RuntimeError(f"nct lower tail is NaN at df={df}, nc={nc} and its bound is not negligible")
        lower = 0.0
    return float(stats.nct.sf(tc, df, nc)) + lower


def pass_probability(reading: str, u: float, sigma: float, n: int, df: int | None = None) -> float:
    """P(the arm passes) when its true geometric mean sits u above the threshold on the log scale; df only for the
    lower bound (defaults to the arm's own n − 1)."""
    if reading == "arm_mean":
        return float(stats.norm.cdf(u * math.sqrt(n) / sigma))
    if reading == "lower_bound":
        df = n - 1 if df is None else df
        return float(stats.nct.sf(stats.t.ppf(1.0 - ALPHA, df), df, u * math.sqrt(n) / sigma))
    if reading == "every_coupon":
        return float(stats.norm.cdf(u / sigma) ** n)
    raise ValueError(reading)


def correct_selection(u: float, sigma: float, n: int, k: int) -> float:
    """P(the best of k arms has the highest sample log-mean), the other k − 1 equal and u below it."""
    shift = u * math.sqrt(n) / sigma
    value, _ = integrate.quad(lambda z: stats.norm.pdf(z) * stats.norm.cdf(z + shift) ** (k - 1), -12.0, 12.0,
                              epsabs=1e-12, epsrel=1e-12)
    return value


def solve_increasing(f, target: float) -> float:
    """The u ≥ 0 at which an increasing f reaches target (f(0) < target for every family here)."""
    if f(0.0) >= target:
        raise ValueError(f"f(0) = {f(0.0)} already reaches {target}")
    hi = 0.5
    for _ in range(60):
        if f(hi) >= target:
            break
        hi *= 2.0
    else:
        raise RuntimeError("no bracket — the family never reaches the target")
    return optimize.brentq(lambda u: f(u) - target, 0.0, hi, xtol=1e-12)


def max_cv_passing(reading: str, u: float, n: int, df: int | None = None) -> float | None:
    """The largest CV at which an arm u above its threshold still passes with P_TARGET; None if none does (u ≤ 0
    gives P ≤ 0.5 under every reading, below any P_TARGET above one half)."""
    if u <= 0.0:
        return None
    g = lambda s: pass_probability(reading, u, s, n, df) - P_TARGET  # noqa: E731 — falls with the spread
    lo, hi = 1e-6, 0.05
    if g(lo) <= 0.0:
        raise RuntimeError(f"{reading} n={n}: even a vanishing spread misses P_TARGET")
    for _ in range(60):
        if g(hi) < 0.0:
            break
        hi *= 2.0
    else:
        raise RuntimeError("no bracket on the spread")
    s = optimize.brentq(g, lo, hi, xtol=1e-12)
    return math.sqrt(math.expm1(s * s))


def r6(x: float) -> float:
    return round(float(x), 6)


def key(cv: float) -> str:
    return f"{cv:.2f}"


def budget(n: int) -> dict:
    per_alloy = {}
    for alloy, arms in COIN_ELECTRODE_ARMS.items():
        quote = COIN_ORDER_CONTROL_HIGH if alloy == COIN_CONTROL_ALLOY else COIN_ORDER_PER_ALLOY
        need = len(arms) * n + NON_ELECTRODE
        per_alloy[alloy] = {"electrode_arms": len(arms), "coupons_needed": need, "letter_quote_point": quote,
                            "fits_letter_quote": need <= quote}
    electrode = sum(len(arms) * n for arms in COIN_ELECTRODE_ARMS.values())
    return {"per_alloy": per_alloy,
            "gold_coupons_needed": n, "gold_coupons_ordered": COIN_GOLD_COUPONS,
            "test_A_coupons": electrode + n,
            "C_channels": C_ARMS * n, "C_channel_days": C_ARMS * n * COIN_HOLD_DAYS,
            "test_D_coupons": n, "test_E_coupons": n}


def letter_ceiling() -> dict:
    """The largest equal n per arm the letter's quote point carries, per alloy (its electrode coupons ÷ its arms)."""
    out = {}
    for alloy, arms in COIN_ELECTRODE_ARMS.items():
        quote = COIN_ORDER_CONTROL_HIGH if alloy == COIN_CONTROL_ALLOY else COIN_ORDER_PER_ALLOY
        electrode = quote - NON_ELECTRODE
        out[alloy] = {"electrode_coupons": electrode, "electrode_arms": len(arms),
                      "max_equal_n_per_arm": electrode // len(arms), "split_if_unequal": electrode % len(arms) != 0}
    return out


def monte_carlo(rng: np.random.Generator, n: int, cv: float, u: dict) -> dict:
    """The same decision rules, simulated, at the closed forms' own solutions — each must land on P_TARGET."""
    s, trials = sigma_log(cv), MC_TRIALS
    got = {}
    # own reading: the spread from the contrast's own coupons
    for name, na in (("two_arm_equal", n), ("two_arm_single", 1)):
        a = rng.normal(0.0, s, (trials, na))
        b = rng.normal(u[name], s, (trials, n))
        ss = (a.var(axis=1, ddof=1) * (na - 1) if na > 1 else 0.0) + b.var(axis=1, ddof=1) * (n - 1)
        df = na + n - 2
        t = (b.mean(axis=1) - a.mean(axis=1)) / np.sqrt(ss / df * (1.0 / na + 1.0 / n))
        got[name] = float(np.mean(np.abs(t) > stats.t.ppf(1.0 - ALPHA / 2.0, df)))
    # pooled reading: the spread from every arm that measures the quantity; the contrast is between arm 0 and the
    # shifted arm (two_arm_equal), or one extra coupon against arm 0 (two_arm_single — the gold coupon adds no df)
    x = rng.normal(0.0, s, (trials, C_ARMS, n))
    x[:, 1, :] += u["two_arm_equal_pooled"]
    sp = np.sqrt(x.var(axis=2, ddof=1).mean(axis=1))
    df = pooled_df(C_ARMS, n)
    t = (x[:, 1, :].mean(axis=1) - x[:, 0, :].mean(axis=1)) / (sp * math.sqrt(2.0 / n))
    got["two_arm_equal_pooled"] = float(np.mean(np.abs(t) > stats.t.ppf(1.0 - ALPHA / 2.0, df)))
    y = rng.normal(0.0, s, (trials, CATHODE_ARMS, n))
    y[:, 0, :] += u["two_arm_single_pooled"]
    gold = rng.normal(0.0, s, trials)
    sp = np.sqrt(y.var(axis=2, ddof=1).mean(axis=1))
    df = pooled_df(CATHODE_ARMS, n)
    t = (y[:, 0, :].mean(axis=1) - gold) / (sp * math.sqrt(1.0 + 1.0 / n))
    got["two_arm_single_pooled"] = float(np.mean(np.abs(t) > stats.t.ppf(1.0 - ALPHA / 2.0, df)))
    del x, y
    tc1 = stats.t.ppf(1.0 - ALPHA, n - 1)
    for reading in READINGS:
        x = rng.normal(u[reading], s, (trials, n))
        if reading == "arm_mean":
            ok = x.mean(axis=1) >= 0.0
        elif reading == "lower_bound":
            ok = x.mean(axis=1) - tc1 * x.std(axis=1, ddof=1) / math.sqrt(n) >= 0.0
        else:
            ok = (x >= 0.0).all(axis=1)
        got[reading] = float(np.mean(ok))
    x = rng.normal(0.0, s, (trials, C_ARMS, n))
    x[:, 0, :] += u["lower_bound_pooled"]
    sp = np.sqrt(x.var(axis=2, ddof=1).mean(axis=1))
    tcp = stats.t.ppf(1.0 - ALPHA, pooled_df(C_ARMS, n))
    got["lower_bound_pooled"] = float(np.mean(x[:, 0, :].mean(axis=1) - tcp * sp / math.sqrt(n) >= 0.0))
    del x
    v = rng.normal(0.0, s, (trials, len(CANDIDATES), n))
    v[:, 0, :] += u["selection"]
    got["selection"] = float(np.mean(v.mean(axis=2).argmax(axis=1) == 0))
    return got


def main() -> int:
    banner("100 — Stage-2 coin: what 2…6 replicate coupons per arm resolve (assumed spread)")
    k = len(CANDIDATES)
    two = {name: {} for name in ("equal", "single", "equal_pooled", "single_pooled")}
    margin, sel, d_target = {r: {} for r in READINGS}, {}, {r: {} for r in READINGS}
    margin_lb_pooled = {}
    solutions = {}
    for cv in CV_ASSUMED:
        s = sigma_log(cv)
        for t in two.values():
            t[key(cv)] = {}
        sel[key(cv)], margin_lb_pooled[key(cv)] = {}, {}
        for r in READINGS:
            margin[r][key(cv)], d_target[r][key(cv)] = {}, {}
        for n in N_GRID:
            dfc, dfk = pooled_df(C_ARMS, n), pooled_df(CATHODE_ARMS, n)
            sol = {"two_arm_equal": solve_increasing(lambda u: two_arm_power(u, s, n, n), P_TARGET),
                   "two_arm_single": solve_increasing(lambda u: two_arm_power(u, s, 1, n), P_TARGET),
                   "two_arm_equal_pooled": solve_increasing(lambda u: two_arm_power(u, s, n, n, dfc), P_TARGET),
                   "two_arm_single_pooled": solve_increasing(lambda u: two_arm_power(u, s, 1, n, dfk), P_TARGET),
                   "lower_bound_pooled": solve_increasing(
                       lambda u: pass_probability("lower_bound", u, s, n, dfc), P_TARGET),
                   "selection": solve_increasing(lambda u: correct_selection(u, s, n, k), P_TARGET)}
            for r in READINGS:
                sol[r] = solve_increasing(lambda u, r=r: pass_probability(r, u, s, n), P_TARGET)
                d_target[r][key(cv)][str(n)] = r6(pass_probability(
                    r, math.log(COIN_CHLORIDE_TARGET_RATIO / COIN_CHLORIDE_MIN_RATIO), s, n))
                margin[r][key(cv)][str(n)] = r6(math.exp(sol[r]))
            solutions[(n, cv)] = sol
            for name in two:
                two[name][key(cv)][str(n)] = r6(math.exp(sol["two_arm_" + name]))
            margin_lb_pooled[key(cv)][str(n)] = r6(math.exp(sol["lower_bound_pooled"]))
            sel[key(cv)][str(n)] = r6(math.exp(sol["selection"]))

    at_threshold = {r: {str(n): r6(pass_probability(r, 0.0, 1.0, n)) for n in N_GRID} for r in READINGS}
    full_recovery_u = math.log(BEST_CASE["E"][0] / BEST_CASE["E"][1])
    max_cv = {}
    for gate, (best, threshold) in BEST_CASE.items():
        u_best = math.log(best / threshold)
        max_cv[gate] = {"best_case_ratio": best, "threshold": threshold,
                        "by_reading": {r: {str(n): (None if (c := max_cv_passing(r, u_best, n)) is None else r6(c))
                                           for n in N_GRID} for r in READINGS}}
    u_c = math.log(BEST_CASE["C"][0] / BEST_CASE["C"][1])
    max_cv["C"]["by_reading"]["lower_bound_pooled"] = {
        str(n): r6(max_cv_passing("lower_bound", u_c, n, pooled_df(C_ARMS, n))) for n in N_GRID}

    # ── control: the closed forms against a simulation of the same rules ──
    rng = np.random.default_rng(MC_SEED)
    se = math.sqrt(P_TARGET * (1.0 - P_TARGET) / MC_TRIALS)
    control = {"trials": MC_TRIALS, "seed": MC_SEED, "tolerance": r6(MC_TOLERANCE_SE * se), "cells": []}
    for n, cv in MC_CELLS:
        got = monte_carlo(rng, n, cv, solutions[(n, cv)])
        worst = max(abs(p - P_TARGET) for p in got.values())
        control["cells"].append({"n": n, "cv": cv, "p_simulated": {kk: r6(p) for kk, p in got.items()},
                                 "worst_miss": r6(worst)})
        if worst > MC_TOLERANCE_SE * se:
            raise RuntimeError(f"Monte Carlo misses a closed form at n={n}, CV={cv}: {got}")

    # ── the letter's arithmetic must reproduce from the mirrored layout (the 4V quote point) ──
    control_need_at_2 = budget(2)["per_alloy"][COIN_CONTROL_ALLOY]["coupons_needed"]
    if control_need_at_2 != COIN_ORDER_CONTROL_HIGH:
        raise RuntimeError(f"layout mirror ≠ letter: the control needs {control_need_at_2} at n=2, the letter quotes "
                           f"{COIN_ORDER_CONTROL_HIGH}")
    ceiling = letter_ceiling()

    # ── findings, read from the numbers ──
    def trend(rows):
        up = all(all(a < b for a, b in zip(row, row[1:])) for row in rows)
        down = all(all(a > b for a, b in zip(row, row[1:])) for row in rows)
        return "grows" if up else "shrinks" if down else "mixed"

    gate_trend = {r: trend([[margin[r][key(cv)][str(n)] for n in N_GRID] for cv in CV_ASSUMED]) for r in READINGS}
    gate_trend["lower_bound_pooled"] = trend([[margin_lb_pooled[key(cv)][str(n)] for n in N_GRID] for cv in CV_ASSUMED])
    findings = {
        "gate_margin_with_n": gate_trend,
        "arm_mean_passes_a_borderline_arm_at_every_n": all(at_threshold["arm_mean"][str(n)] == 0.5 for n in N_GRID),
        "full_recovery_pass_probability": {r: at_threshold[r] for r in READINGS} if full_recovery_u == 0.0 else None,
        "alloys_whose_letter_quote_gives_an_arm_a_single_replicate": sorted(
            a for a, c in ceiling.items() if c["max_equal_n_per_arm"] < 2),
        "selection_candidates": list(CANDIDATES),
    }

    lines = [f"Gate readings move apart with n: the margin a good arm needs {gate_trend['every_coupon']} with n when "
             f"every coupon must pass, {gate_trend['lower_bound']} under the lower confidence bound (pooled: "
             f"{gate_trend['lower_bound_pooled']}) and {gate_trend['arm_mean']} under the arm mean — so n and the "
             f"reading of «≥ threshold» are one decision."]
    if findings["arm_mean_passes_a_borderline_arm_at_every_n"]:
        lines.append("Under the arm-mean reading an arm sitting exactly at its threshold passes half the time at "
                     "every n.")
    if findings["full_recovery_pass_probability"] is not None:
        p = findings["full_recovery_pass_probability"]
        lines.append(f"Gate E's threshold is full recovery itself, so an electrode recovering exactly 100 % passes with "
                     f"probability {p['arm_mean'][str(N_GRID[0])]} (arm mean), {p['lower_bound'][str(N_GRID[0])]} "
                     f"(lower bound) or {p['every_coupon'][str(N_GRID[0])]}…{p['every_coupon'][str(N_GRID[-1])]} "
                     f"(every coupon) — whatever the spread.")
    single = findings["alloys_whose_letter_quote_gives_an_arm_a_single_replicate"]
    if single:
        lines.append(f"At the coupon letter's quote point ({COIN_ORDER_PER_ALLOY} per alloy, {COIN_ORDER_CONTROL_HIGH} "
                     f"for {COIN_CONTROL_ALLOY}) the two-arm alloys {', '.join(single)} carry their electrode coupons "
                     f"as 2 + 1, i.e. one arm on a single replicate; the gold coupon is single by order.")

    result = {
        "script": Path(__file__).name,
        "conventions": {
            "n_grid": list(N_GRID), "cv_assumed_NOT_MEASURED": list(CV_ASSUMED),
            "sigma_log": {key(cv): r6(sigma_log(cv)) for cv in CV_ASSUMED},
            "alpha": ALPHA, "p_target": P_TARGET,
            "two_arm_test": "two-sample t on log values, two-sided, equal spread in both arms",
            "spread_readings": {
                "own": "estimated from the contrast's or the arm's own coupons — robust if the arms' spreads differ; "
                       "the adverse end",
                "pooled": f"estimated over every arm that measures the same quantity — the 30-day retention over the "
                          f"{C_ARMS} arms of the hold C, a day-0 cathode current over the {CATHODE_ARMS} titanium-cathode "
                          f"arms; valid only if they share one CV (this model's assumption); the optimistic end. "
                          f"D and E are measured on their own arm only — no pooled reading",
                "pooled_arms": {"hold_C": C_ARMS, "titanium_cathodes": CATHODE_ARMS}},
            "gate_readings": {"arm_mean": "the arm's geometric mean ≥ threshold",
                              "lower_bound": f"the one-sided {1 - ALPHA:.0%} lower confidence bound of the geometric "
                                             f"mean ≥ threshold",
                              "every_coupon": "every coupon ≥ threshold"},
            "selection_rule": "the highest sample geometric mean picks the winner; the other candidates equal",
            "cv_floor": "the lab's stated repeatability of repeated scans on one coupon (test A) — a FLOOR on the "
                        "between-coupon CV, not its value",
        },
        "two_arm": {"ratio_detectable_equal_n": two["equal"],
                    "ratio_detectable_single_vs_n": two["single"],
                    "ratio_detectable_equal_n_pooled": two["equal_pooled"],
                    "ratio_detectable_single_vs_n_pooled": two["single_pooled"],
                    "single_coupon_floor": {key(cv): r6(math.exp(
                        (stats.norm.ppf(1.0 - ALPHA / 2.0) + stats.norm.ppf(P_TARGET)) * sigma_log(cv)))
                        for cv in CV_ASSUMED},
                    "note": "single_vs_n — ONE coupon on one side (the gold coupon by order) against n on the other; "
                            "_pooled — the spread pooled over the arms of the same quantity (conventions); "
                            "single_coupon_floor — its limit with any n and a known spread (a z-test): the one coupon's "
                            "own spread never averages out"},
        "gate": {
            "thresholds": {"C_retention_30d": COIN_RETENTION_30D_MIN, "D_chloride": COIN_CHLORIDE_MIN_RATIO,
                           "D_chloride_target": COIN_CHLORIDE_TARGET_RATIO, "E_recovery": COIN_UCST_RECOVERY_RATIO},
            "margin_ratio_needed": margin,
            "margin_ratio_needed_lower_bound_pooled_C": margin_lb_pooled,
            "p_pass_at_threshold": at_threshold,
            "D_p_pass_at_target": d_target,
            "max_cv_for_best_case": max_cv,
            "note": "margin_ratio_needed — true value / threshold for P(pass) = p_target; the same table for C, D, E. "
                    "max_cv_for_best_case — the largest coupon-to-coupon CV at which the gate's best case (no loss · "
                    "D's own target · full recovery) still passes with p_target; null where no spread lets it. "
                    "lower_bound_pooled exists for C only (the retention every arm of the hold measures)",
        },
        "selection": {"candidates": list(CANDIDATES), "control_excluded": COIN_CONTROL_ALLOY,
                      "benchmark_excluded": list(COIN_BENCHMARK_ALLOYS),
                      "ratio_needed": sel,
                      "conditional_on": "one current metric deciding — canon names no rule combining current, "
                                        "retention and the ICP-MS rank"},
        "budget": {"by_n": {str(n): budget(n) for n in N_GRID}, "letter_ceiling": ceiling,
                   "C_arms_counted": "the anodes and the Ti-6Al-4V pair; the channel order's «→ the rest» names no arm"},
        "control": control,
        "findings": findings,
        "verdict": " ".join(lines),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    labels = {"equal": "Two arms, equal n — own spread", "equal_pooled": f"Two arms — spread pooled over {C_ARMS} arms",
              "single": "One coupon against n — own spread",
              "single_pooled": f"One coupon against n — pooled over {CATHODE_ARMS} cathode arms"}
    for name, label in labels.items():
        print(f"\n  {label} (smallest detectable ratio, power 0.80, two-sided α 0.05):")
        for n in N_GRID:
            print(f"    {n}  " + "".join(f"  ×{two[name][key(cv)][str(n)]:7.3f}" for cv in CV_ASSUMED))
    for r in READINGS:
        print(f"\n  Gate margin (true / threshold) for P(pass) 0.80 — {r}; at threshold P = "
              + ", ".join(f"{at_threshold[r][str(n)]}" for n in N_GRID))
        for n in N_GRID:
            print(f"    {n}  " + "".join(f"  ×{margin[r][key(cv)][str(n)]:6.3f}" for cv in CV_ASSUMED))
    for gate, block in max_cv.items():
        print(f"\n  Gate {gate}: the largest CV at which its best case (×{block['best_case_ratio']} against "
              f"{block['threshold']}) passes with P 0.80 — n = {', '.join(map(str, N_GRID))}")
        for r, row in block["by_reading"].items():
            print(f"    {r:19s}" + "".join("     none" if row[str(n)] is None else f"  {row[str(n)]:7.3f}"
                                           for n in N_GRID))
    print(f"\n  Selection among {k} candidates {CANDIDATES} — ratio for P(correct) 0.80:")
    for n in N_GRID:
        print(f"    {n}  " + "".join(f"  ×{sel[key(cv)][str(n)]:6.3f}" for cv in CV_ASSUMED))
    print("\n  Letter ceiling:", {a: c["max_equal_n_per_arm"] for a, c in ceiling.items()})
    print("  Control:", [(c["n"], c["cv"], c["worst_miss"]) for c in control["cells"]], "tolerance", control["tolerance"])
    print("\n  " + result["verdict"])
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
