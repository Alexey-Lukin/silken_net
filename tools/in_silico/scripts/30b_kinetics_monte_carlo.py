#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L4b — Monte Carlo uncertainty analysis for delta_t predictions.

Samples from parameter distributions instead of fixed values:
  Km ~ Uniform(10, 50) mM — deliberately WIDER than the fitted K_M^app (13.9 ± 3.1 mM): the upper
           end covers the case where the apparent constant is inflated by mass transfer in the
           hydrogel. Narrowing it to the fit would make the model look more certain than it is
  Ea ~ Uniform(30, 50) kJ/mol
  j_max ~ Normal(J_MAX_25C, J_MAX_25C_SD) µA/cm² — the asymptote and its 1σ are IMPORTED, never
           typed here: both are derived in lib/constants.py from Zafar 2012's own error bars
  A_electrode ~ Uniform(1, 5) cm²
  E_cycle ~ Uniform(E_CYCLE_LOW, E_CYCLE_HIGH) ≈ U(30.8, 52.2) mJ — the node chain's OWN bracket
           (02_03 §9.4, every input named in lib/constants.py): the compute ceilings pull the cycle
           cost down, the two core-idle terms §9.4 names but does not add pull it up; the canon
           leaves the sign of the sum open. EDLC self-discharge is a continuous drain, not in it.
           Until 2026-09-27 this was U(3, 10) around a 5 mJ placeholder (E.63)
  P_sleep = P_SLEEP_VSTOR (fixed) — the chain's sleep drain, subtracted from the boosted power

Produces confidence intervals for delta_t at reference conditions.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/30b_kinetics_monte_carlo.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    BASELINE_DELTA_T_S,
    E_CYCLE_HIGH,
    E_CYCLE_LOW,
    ETA_BQ,
    J_MAX_25C,
    J_MAX_25C_SD,
    KINETICS_DIR,
    P_SLEEP_VSTOR,
    R_GAS,
    REPO_ROOT,
    TEMPERATURE_K,
    V_OP,
)
from lib.kinetics import ph_current_ratio
from lib.utils import banner

OUT_DIR = KINETICS_DIR
OUT_DIR.mkdir(parents=True, exist_ok=True)

T_REF = TEMPERATURE_K
N_SAMPLES = 10_000
BASELINE = float(BASELINE_DELTA_T_S)


def delta_t(glucose_mm, temp_c, km, ea, jmax, a_el, e_cyc):
    temp_k = temp_c + 273.15
    j = jmax * np.exp(-ea / R_GAS * (1.0 / temp_k - 1.0 / T_REF))
    j *= glucose_mm / (km + glucose_mm)
    p = V_OP * j * a_el * ETA_BQ - P_SLEEP_VSTOR   # [E.63] same form as 30 and the canon's H
    return np.where(p > 0, e_cyc / p, np.inf)


def _finite(x: float) -> float | None:
    """A percentile as the cache writes it: rounded, or None where it is «never» (inf)."""
    return round(float(x), 1) if np.isfinite(x) else None


def _never_max_area(dt, a_el) -> float | None:
    """Largest sampled electrode area among the «never» samples (None if there are none)."""
    never = ~np.isfinite(dt)
    return round(float(a_el[never].max()), 2) if never.any() else None


def _fmt(x: float | None) -> str:
    return "never" if x is None else f"{x:.1f}"


def _order(x: float | None) -> float:
    return float("inf") if x is None else x


def main() -> int:
    banner(f"Monte Carlo delta_t uncertainty ({N_SAMPLES} samples)")

    rng = np.random.default_rng(42)

    km = rng.uniform(10, 50, N_SAMPLES)           # mM
    ea = rng.uniform(30_000, 50_000, N_SAMPLES)   # J/mol
    jmax = rng.normal(J_MAX_25C, J_MAX_25C_SD, N_SAMPLES)   # A/cm², lib.constants (00_07 HW.5.IS)
    jmax = np.clip(jmax, max(100e-6, J_MAX_25C - 4 * J_MAX_25C_SD), J_MAX_25C + 4 * J_MAX_25C_SD)
    a_el = rng.uniform(1, 5, N_SAMPLES)            # cm²
    e_cyc = rng.uniform(E_CYCLE_LOW, E_CYCLE_HIGH, N_SAMPLES)    # J — the chain's bracket

    scenarios = [
        ("Healthy summer", 10, 25),
        ("Active growth", 20, 30),
        ("Cold winter", 5, 5),
        ("Severe stress", 3, 0),
    ]

    # 🔴 The five axes above are NOT the whole uncertainty, and until 2026-09-21 nothing here said
    # so. `J_MAX_25C` is a pH-7.4 LABORATORY CEILING (constants.py); our anode sits in sap at
    # pH 5.75, and a quantified bracket for that shift has existed since ⚖️ 2026-09-18. Script `30`
    # obeyed that verdict and printed the bracket beside its table — its SIBLING here never did, so
    # a CI conditional on the wrong medium was reading as the CI. The verdict is applied here now,
    # in its ratified shape: printed BESIDE, never folded in (00_05 §4 — a rule ratified for one leg
    # does not reach its sister by itself).
    results = {
        "n_samples": N_SAMPLES,
        # [E.63] What the band was sampled FROM, so a gate can hold the cache to lib/constants.py.
        "parameters": {
            "E_cycle_low_mJ": E_CYCLE_LOW * 1e3, "E_cycle_high_mJ": E_CYCLE_HIGH * 1e3,
            "P_sleep_VSTOR_uW": P_SLEEP_VSTOR * 1e6, "A_electrode_cm2": [1.0, 5.0],
        },
        "conditional_on": {
            "medium": "the sampled j_max is centred on the pH-7.4 laboratory ceiling "
                      "(J_MAX_25C, constants.py) — the percentiles below are a CI AT THAT CEILING",
            "not_sampled": ["the pH-driven k_cat/K_M shift toward sap pH 5.75"],
            "why_not_folded_in": "⚖️ founder 2026-09-18: the correction is not a point, so the "
                                 "model stays on the ceiling and the bracket is printed beside it",
            "bracket_source": "Sygmund 2011 Table 3 via lib.kinetics.ph_current_ratio — FREE enzyme, "
                              "ferrocenium acceptor, 30 °C; both enzyme forms are kept because they "
                              "disagree, and the disagreement IS the bracket",
            "bracket_is_a_transport_not_an_added_variance": "every sample's current is scaled by "
                                                            "the [S]-dependent ratio and the "
                                                            "percentiles are recomputed, i.e. the "
                                                            "whole distribution is moved to pH 5.5 "
                                                            "(dividing the percentiles stopped being "
                                                            "exact once the sleep drain entered, E.63); "
                                                            "the ratio carries the SOURCE's K_M "
                                                            "shift while the sampled `km` spread is "
                                                            "about OUR apparent constant — related "
                                                            "axes, deliberately not summed",
        },
        "never_gathers_cycle": "a sample whose boosted power does not exceed P_SLEEP_VSTOR never "
                               "gathers a cycle (delta_t = inf, the canon's H = inf); its share is "
                               "never_gathers_cycle_pct, and a percentile that lands on it is null — "
                               "never a capped number",
        "scenarios": [],
    }

    print(f"\n  {'Scenario':<20s}  {'Median':>8s}  {'5%':>8s}  {'95%':>8s}  {'vs 60s':>10s}"
          f"  {'median at pH 5.5':>18s}")
    print("  " + "-" * 82)

    for label, glu, tc in scenarios:
        dt = delta_t(glu, tc, km, ea, jmax, a_el, e_cyc)
        # [E.63] No cap before the percentiles: with the chain's cycle cost the stressed tails pass
        # any round ceiling, and a sample at or below the sleep drain is «never», not a big number.
        # `inverted_cdf` returns an actual sample, so a percentile on such a sample stays inf.
        p5, p50, p95 = np.percentile(dt, [5, 50, 95], method="inverted_cdf")
        never_pct = round(100.0 * float(np.mean(~np.isfinite(dt))), 2)
        # WHICH samples never gather a cycle: the area axis reaches below the coupon's 2 cm² face.
        never_area = _never_max_area(dt, a_el)
        status = "< baseline" if p50 < BASELINE else "> baseline"

        # The pH bracket: scale every sample's current by the [S]-dependent ratio (j ∝ jmax) and
        # recompute. A ratio < 1 (slower enzyme at pH 5.5) LENGTHENS delta_t — by MORE than 1/r,
        # because the sleep drain does not shrink with the current.
        ratios = {f: ph_current_ratio(glu, f) for f in ("wt", "rec")}
        ph_band = {}
        for f, r in ratios.items():
            dt_ph = delta_t(glu, tc, km, ea, jmax * r, a_el, e_cyc)
            q = np.percentile(dt_ph, [5, 50, 95], method="inverted_cdf")
            ph_band[f] = {"ratio": round(r, 3), "p5_s": _finite(q[0]), "median_s": _finite(q[1]),
                          "p95_s": _finite(q[2]),
                          "never_gathers_cycle_pct": round(100.0 * float(np.mean(~np.isfinite(dt_ph))), 2),
                          "never_max_area_cm2": _never_max_area(dt_ph, a_el)}
        med_lo, med_hi = sorted((ph_band[f]["median_s"] for f in ratios), key=_order)
        ph_status = "< baseline" if _order(med_hi) < BASELINE else (
            "> baseline" if _order(med_lo) > BASELINE else "straddles baseline")

        print(f"  {label:<20s}  {p50:>7.1f}s  {p5:>7.1f}s  {p95:>7.1f}s  {status:>10s}"
              f"  {_fmt(med_lo):>8s}–{_fmt(med_hi)}s")

        results["scenarios"].append({
            "label": label, "glucose_mM": glu, "temp_C": tc,
            "p5_s": _finite(p5), "median_s": _finite(p50), "p95_s": _finite(p95),
            "never_gathers_cycle_pct": never_pct, "never_max_area_cm2": never_area,
            "vs_baseline": status,
            "ph55_bracket": ph_band,
            "ph55_median_low_s": med_lo, "ph55_median_high_s": med_hi,
            "ph55_vs_baseline": ph_status,
        })
    print("  ⚠️  The last column is the SAME distribution transported to pH 5.5, not a wider CI —")
    print("      it says where the whole band sits if the sap-pH penalty is real, and its source is")
    print("      a free-enzyme measurement at 30 °C applied at every temperature here.")

    # Heatmap: P(delta_t < 60s) as function of glucose × temp
    banner("Computing P(delta_t < 60s) heatmap")
    glu_range = np.linspace(1, 30, 30)
    temp_range = np.linspace(-10, 40, 25)
    prob_grid = np.zeros((len(temp_range), len(glu_range)))

    for i, tc in enumerate(temp_range):
        for j, glu in enumerate(glu_range):
            dt = delta_t(glu, tc, km, ea, jmax, a_el, e_cyc)
            prob_grid[i, j] = np.mean(dt < BASELINE)

    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    ax = axes[0]
    im = ax.contourf(glu_range, temp_range, prob_grid,
                      levels=np.arange(0, 1.05, 0.05), cmap="RdYlGn")
    # [E.63] With the chain's cycle cost the 50 % line may not exist at all — draw it only if it does.
    if prob_grid.min() < 0.5 < prob_grid.max():
        cs = ax.contour(glu_range, temp_range, prob_grid,
                         levels=[0.5], colors="white", linewidths=2)
        ax.clabel(cs, fmt={0.5: "50%"}, fontsize=9)
    ax.set_xlabel("[glucose] (mM)")
    ax.set_ylabel("Temperature (°C)")
    ax.set_title("P(delta_t < 60s) at the pH-7.4 ceiling — old-baseline fraction\n(lab-scale; E.63: GP now field-scale; sap-pH bracket in the table, not here)", fontsize=10)
    fig.colorbar(im, ax=ax, label="Probability")

    # Distribution at reference condition (10 mM, 25°C)
    ax2 = axes[1]
    dt_ref = delta_t(10, 25, km, ea, jmax, a_el, e_cyc)
    # Percentiles on the UNCLIPPED sample — clipping is for display only, and a clip below p95
    # would print a CI the distribution does not have.
    p5, p50, p95 = np.percentile(dt_ref, [5, 50, 95])
    ax2.hist(np.clip(dt_ref, 0, 2 * p95), bins=50, density=True, alpha=0.7, color="steelblue",
             edgecolor="white")
    ax2.axvline(BASELINE, color="red", linestyle="--", linewidth=2, label="baseline 60s")
    ax2.axvline(p50, color="green", linewidth=2, label=f"median {p50:.0f}s")
    ax2.axvspan(p5, p95, alpha=0.2, color="green", label=f"90% CI [{p5:.0f}-{p95:.0f}s]")
    ax2.set_xlabel("delta_t (seconds)")
    ax2.set_ylabel("Density")
    ax2.set_title("delta_t distribution at 10 mM glucose, 25°C")
    ax2.legend()
    ax2.set_xlim(0, 2 * p95)

    fig.tight_layout()
    fig_path = OUT_DIR / "delta_t_monte_carlo.png"
    fig.savefig(fig_path, dpi=140)
    print(f"  Wrote {fig_path.relative_to(REPO_ROOT)}")

    # Save
    json_path = OUT_DIR / "monte_carlo.json"
    with json_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    print(f"  Wrote {json_path.relative_to(REPO_ROOT)}")

    banner("✅ Monte Carlo analysis complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
