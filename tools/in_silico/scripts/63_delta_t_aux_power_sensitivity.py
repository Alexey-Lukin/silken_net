#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.42 — Does a second power source on the SAME BQ25570 rail contaminate `delta_t`?

WHY THIS EXISTS. `00_07` HW.21 carries a checkbox for TEG multi-input integration onto
the same BQ25570 charging rail the EBFC already feeds. Since [E.63], `delta_t` (the
EDLC recharge interval, `02_03 §12.2-12.3`) drives `growth_points` DIRECTLY — a
money-minting signal, not a debug counter. `01_03 §4`'s instrumental-noise-source list
is exhaustively CHEMICAL (enzyme degradation, membrane fouling, chlorides); it has no
axis at all for "a second, unrelated power source lands on the same charge rail". This
script closes that missing axis with one closed form: how much injecting an auxiliary
power P_aux (HW.21's TEG estimate, 50-200 µW; swept 10-200 µW here) shifts `delta_t`
away from the EBFC-only baseline.

Model
-----
The EBFC-only baseline uses the canon ENERGY-BUDGET model (`02_03` §9.1/§9.2/§9.8 —
NOT script 30's Michaelis-Menten chemistry model; different "canon numbers", same
underlying delta_t = energy / power form):

    delta_t_baseline(P) = E_window / (P * eta_boost)

with E_window = the EDLC window ON VSTOR, VBAT_OK ON (3.40 V) -> the RATIFIED VBAT_OV
(4.822 V, Derate — founder 2026-09-09), `02_03 §8` ≈ 2.75 J: the energy the boost has to PUT
IN, which is what a charging time divides. ⛔ Not the post-buck usable window (≈ 2.42 J,
also §8): eta_buck sits on the DISCHARGE side and never enters a charging time — until
2026-09-25 this script divided the post-buck figure, and on the part's 5.5 V rating instead
of VBAT_OV (00_07 HW.37). The two canon season/efficiency anchors: summer 15 uW @
eta_boost=0.68 (ETA_BQ, §9.2), winter 3-5 uW @ eta_boost=0.65 (§9.8: "eta_boost lower at
lower I_IN").

Injecting P_aux onto the SAME rail is reported as a BRACKET, not a single number,
because the multi-input TOPOLOGY itself is still open (FW.50 — this script does not
decide it, and does not decide HW.42's rail-split (v) either):

  * Model A (shared boost, LOWER bound) — P_aux is harvested through the SAME
    converter stage as the EBFC, i.e. it sees the same eta_boost as P_gen. eta_boost
    then CANCELS algebraically in the delta_t ratio:
        pct_shift_A = P_aux / (P_gen + P_aux) * 100
    independent of C, E_window and eta_boost's actual value — the FLOOR of the
    contamination, true for any shared-converter topology regardless of efficiency.
  * Model B (direct injection, UPPER bound) — P_aux reaches VSTOR without the
    boost-stage loss (its own dedicated converter), while P_gen is still derated by
    eta_boost:
        pct_shift_B = P_aux / (P_gen*eta_boost + P_aux) * 100
    always >= Model A.
  * Model C (measured eta(P) curve) — Model A refined with BQ25570's own measured
    efficiency-vs-input-current table (§9.1: 15uW->0.68, 30uW->0.75, 100uW->0.82,
    log-interpolated/extrapolated at the COMBINED P_gen+P_aux). Not a 4th free
    parameter — it is Model A with a MEASURED, not assumed-constant, eta_boost.
    Flagged EXTRAPOLATED wherever P_gen+P_aux exceeds the table's 100 uW top point.

The window is DERIVED in `lib/constants.py` from C and the two thresholds — one truth, so a
moved VBAT_OV reaches it. Its controls live where they can fail: `test_doc_cache_sync` pins
the cached window to `02_03 §8` (canon ⟷ machine), `test_cache_integrity` pins the cache to
the constants and every absolute delta_t to E_window/(P·eta). Re-deriving the same formula
here would be an identity, not a check (in-silico §When Modifying #8), so the script prints
the derivation and asserts nothing about it.

Scope: SENSITIVITY NUMBER ONLY. Whether this forces a physical rail split or blocks
HW.21's multi-input checkbox is an explicit (v) reserved for the founder (00_07
HW.42) — not decided here.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/63_delta_t_aux_power_sensitivity.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    C_EDLC_F,
    EDLC_WINDOW_USABLE_J,
    EDLC_WINDOW_VSTOR_J,
    ETA_BOOST_TABLE_UW,
    ETA_BOOST_WINTER,
    ETA_BQ,
    ETA_BUCK_ACTIVE,
    KINETICS_DIR,
    P_GEN_SUMMER_UW,
    P_GEN_WINTER_RANGE_UW,
    REPO_ROOT,
    VBAT_OK_ON_V,
    VBAT_OV_RATIFIED_V,
)
from lib.utils import banner

OUT_JSON = KINETICS_DIR / "delta_t_aux_power_sensitivity.json"

# 10..200 uW, 10 uW steps — spans HW.21's own 50-200 uW TEG estimate with margin below it.
P_AUX_RANGE_UW = np.linspace(10.0, 200.0, 20)


def eta_boost_curve(p_total_uw: float, floor_eta: float) -> tuple[float, bool]:
    """Log-linear interpolation of BQ25570's MEASURED eta_boost(P_IN) (canon 02_03 §9.1
    3-point table). Below the table's lowest point, holds flat at the season's OWN
    canon-stated floor_eta (not the table's bottom value, which is the summer point —
    winter's own §9.8 value is lower). Above the table's top point, log-linearly
    EXTRAPOLATES the last segment's slope — returns (eta, was_extrapolated) so callers
    can flag it rather than silently overstate confidence."""
    ps = np.array([p for p, _ in ETA_BOOST_TABLE_UW], dtype=float)
    etas = np.array([e for _, e in ETA_BOOST_TABLE_UW], dtype=float)
    log_ps = np.log(ps)
    if p_total_uw <= ps[0]:
        return floor_eta, False
    if p_total_uw >= ps[-1]:
        slope = (etas[-1] - etas[-2]) / (log_ps[-1] - log_ps[-2])
        eta = float(etas[-1] + slope * (np.log(p_total_uw) - log_ps[-1]))
        return eta, True
    return float(np.interp(np.log(p_total_uw), log_ps, etas)), False


def delta_t_seconds(p_w: float, eta: float, e_window_j: float = EDLC_WINDOW_VSTOR_J) -> float:
    """Closed form: time to put E_window Joules INTO the EDLC at net charging power p_w*eta."""
    return e_window_j / (p_w * eta)


def sweep_season(label: str, p_gen_uw: float, eta_boost_season: float) -> dict:
    p_gen_w = p_gen_uw * 1e-6
    dt_base_s = delta_t_seconds(p_gen_w, eta_boost_season)

    rows = []
    pct_a_check = []
    for p_aux_uw in P_AUX_RANGE_UW:
        p_aux_w = p_aux_uw * 1e-6
        p_total_uw = p_gen_uw + p_aux_uw

        dt_a = delta_t_seconds(p_gen_w + p_aux_w, eta_boost_season)
        pct_a = (dt_base_s - dt_a) / dt_base_s * 100.0
        pct_a_check.append(p_aux_uw / p_total_uw * 100.0)

        dt_b = EDLC_WINDOW_VSTOR_J / (p_gen_w * eta_boost_season + p_aux_w)
        pct_b = (dt_base_s - dt_b) / dt_base_s * 100.0

        eta_c, extrapolated = eta_boost_curve(p_total_uw, floor_eta=eta_boost_season)
        dt_c = delta_t_seconds(p_gen_w + p_aux_w, eta_c)
        pct_c = (dt_base_s - dt_c) / dt_base_s * 100.0

        rows.append(
            {
                "P_aux_uW": round(float(p_aux_uw), 1),
                "delta_t_A_s": round(dt_a, 2),
                "pct_shift_A": round(pct_a, 2),
                "delta_t_B_s": round(dt_b, 2),
                "pct_shift_B": round(pct_b, 2),
                "eta_boost_C": round(eta_c, 4),
                "eta_C_extrapolated": extrapolated,
                "delta_t_C_s": round(dt_c, 2),
                "pct_shift_C": round(pct_c, 2),
            }
        )

    # Self-check: Model A's algebraic simplification pct_shift_A == P_aux/(P_gen+P_aux)*100
    computed_a = np.array([r["pct_shift_A"] for r in rows])
    closed_form_a = np.array([round(v, 2) for v in pct_a_check])
    assert np.allclose(computed_a, closed_form_a, atol=0.05), (
        "Model A closed form P_aux/(P_gen+P_aux) does not match the direct delta_t ratio"
    )

    print(
        f"\n  {label}: P_gen={p_gen_uw:.0f} uW, eta_boost={eta_boost_season}, "
        f"delta_t_baseline={dt_base_s:.1f} s ({dt_base_s / 3600:.2f} h)"
    )
    print(f"  {'P_aux(uW)':>10s}  {'A shared-boost':>15s}  {'B direct-inject':>16s}  {'C measured-eta':>15s}")
    for r in rows:
        flag = "*" if r["eta_C_extrapolated"] else " "
        print(
            f"  {r['P_aux_uW']:>10.0f}  {r['pct_shift_A']:>13.1f}%  {r['pct_shift_B']:>14.1f}%  "
            f"{r['pct_shift_C']:>13.1f}%{flag}"
        )

    return {
        "P_gen_uW": p_gen_uw,
        "eta_boost": eta_boost_season,
        "delta_t_baseline_s": round(dt_base_s, 2),
        "delta_t_baseline_h": round(dt_base_s / 3600.0, 3),
        "sweep": rows,
    }


def main() -> int:
    banner("HW.42 — delta_t sensitivity to a second power source on the shared BQ25570 rail")

    # -- The window, derived in lib/constants.py (no assert here: it would be an identity — see docstring) --
    banner("0. EDLC window at the RATIFIED VBAT_OV (02_03 §8; Derate, founder 2026-09-09)")
    print(f"  C={C_EDLC_F} F, VBAT_OK ON {VBAT_OK_ON_V} V -> VBAT_OV {VBAT_OV_RATIFIED_V} V")
    print(f"  on VSTOR (what the boost puts in):       {EDLC_WINDOW_VSTOR_J:.3f} J  <- every delta_t below divides THIS")
    print(
        f"  on VOUT after buck (x eta_buck {ETA_BUCK_ACTIVE}): {EDLC_WINDOW_USABLE_J:.3f} J  "
        "(discharge side — never a charging time)"
    )
    print()
    print(f"  NOTE — this script's delta_t_baseline (below) is a FULL-WINDOW-FILL time ({EDLC_WINDOW_VSTOR_J:.2f} J),")
    print("  a different quantity from §9.6 Scenario C's ~1.95 h (time to replenish ONE TX cycle's")
    print("  spend). This codebase already carries several non-interchangeable delta_t definitions")
    print("  (script 30's chemistry model: 20-101 s; 06_08 notes a 63-320x spread among them) —")
    print("  but ALL THREE pct_shift models below are algebraically INDEPENDENT of E_window's size")
    print("  (it cancels in every ratio), so which delta_t definition you pick does not change the")
    print("  contamination percentage — only the seconds/hours column would differ.")

    banner("1. Summer baseline (P_gen=15 uW)")
    summer = sweep_season("summer", P_GEN_SUMMER_UW, ETA_BQ)

    banner("2. Winter baseline, low/high end of the 3-5 uW range")
    winter_lo = sweep_season("winter (3 uW)", P_GEN_WINTER_RANGE_UW[0], ETA_BOOST_WINTER)
    winter_hi = sweep_season("winter (5 uW)", P_GEN_WINTER_RANGE_UW[1], ETA_BOOST_WINTER)

    # -- Headline numbers at the example anchors the tracker asks about --
    banner("3. Headline contamination (Model A shared-boost floor / Model B direct-inject ceiling)")
    headline = {}
    for name, season in [("summer_15uW", summer), ("winter_3uW", winter_lo), ("winter_5uW", winter_hi)]:
        by_aux = {row["P_aux_uW"]: row for row in season["sweep"]}
        headline[name] = {
            "P_aux_10uW_pct_shift_A": by_aux[10.0]["pct_shift_A"],
            "P_aux_10uW_pct_shift_B": by_aux[10.0]["pct_shift_B"],
            "P_aux_50uW_pct_shift_A": by_aux[50.0]["pct_shift_A"],
            "P_aux_50uW_pct_shift_B": by_aux[50.0]["pct_shift_B"],
            "P_aux_200uW_pct_shift_A": by_aux[200.0]["pct_shift_A"],
            "P_aux_200uW_pct_shift_B": by_aux[200.0]["pct_shift_B"],
        }
        print(
            f"  {name}: at P_aux=10uW (range floor) -> {by_aux[10.0]['pct_shift_A']:.1f}-"
            f"{by_aux[10.0]['pct_shift_B']:.1f}% shift already; "
            f"at 50uW -> {by_aux[50.0]['pct_shift_A']:.1f}-{by_aux[50.0]['pct_shift_B']:.1f}%; "
            f"at 200uW -> {by_aux[200.0]['pct_shift_A']:.1f}-{by_aux[200.0]['pct_shift_B']:.1f}%"
        )

    print()
    print("  (v) SENSITIVITY NUMBER ONLY (00_07 HW.42) — whether this forces a physical rail")
    print("      split or blocks HW.21's multi-input checkbox is reserved for the founder.")

    output = {
        "model": (
            "delta_t = E_window_vstor / (P * eta_boost); P_aux bracket = shared-boost (A) vs "
            "direct-injection (B) vs measured-eta-curve (C); multi-input topology (FW.50) still open"
        ),
        "constants": {
            "C_EDLC_F": C_EDLC_F,
            "VBAT_OV_V": VBAT_OV_RATIFIED_V,
            "VBAT_OK_ON_V": VBAT_OK_ON_V,
            "eta_buck_active": ETA_BUCK_ACTIVE,
            "E_window_vstor_J": EDLC_WINDOW_VSTOR_J,
            "E_window_usable_J": EDLC_WINDOW_USABLE_J,
            "P_aux_range_uW": [float(v) for v in P_AUX_RANGE_UW],
        },
        "seasons": {
            "summer_15uW": summer,
            "winter_3uW": winter_lo,
            "winter_5uW": winter_hi,
        },
        "headline": headline,
    }

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(output, indent=2))
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
