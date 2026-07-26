#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L4b — Monte Carlo uncertainty analysis for delta_t predictions.

Samples from parameter distributions instead of fixed values:
  Km ~ Uniform(10, 50) mM
  Ea ~ Uniform(30, 50) kJ/mol
  j_max ~ Normal(494, 50) µA/cm²
  A_electrode ~ Uniform(1, 5) cm²
  E_cycle ~ Uniform(3, 10) mJ

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
    ETA_BQ,
    KINETICS_DIR,
    R_GAS,
    REPO_ROOT,
    TEMPERATURE_K,
    V_OP,
)
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
    p = V_OP * j * a_el * ETA_BQ
    return np.where(p > 0, e_cyc / p, np.inf)


def main() -> int:
    banner(f"Monte Carlo delta_t uncertainty ({N_SAMPLES} samples)")

    rng = np.random.default_rng(42)

    km = rng.uniform(10, 50, N_SAMPLES)           # mM
    ea = rng.uniform(30_000, 50_000, N_SAMPLES)   # J/mol
    jmax = rng.normal(494e-6, 50e-6, N_SAMPLES)   # A/cm²
    jmax = np.clip(jmax, 100e-6, 1000e-6)
    a_el = rng.uniform(1, 5, N_SAMPLES)            # cm²
    e_cyc = rng.uniform(3e-3, 10e-3, N_SAMPLES)    # J

    scenarios = [
        ("Healthy summer", 10, 25),
        ("Active growth", 20, 30),
        ("Cold winter", 5, 5),
        ("Severe stress", 3, 0),
    ]

    results = {"n_samples": N_SAMPLES, "scenarios": []}

    print(f"\n  {'Scenario':<20s}  {'Median':>8s}  {'5%':>8s}  {'95%':>8s}  {'vs 60s':>10s}")
    print("  " + "-" * 62)

    for label, glu, tc in scenarios:
        dt = delta_t(glu, tc, km, ea, jmax, a_el, e_cyc)
        dt = np.clip(dt, 0, 3600)

        p5, p50, p95 = np.percentile(dt, [5, 50, 95])
        status = "< baseline" if p50 < BASELINE else "> baseline"

        print(f"  {label:<20s}  {p50:>7.1f}s  {p5:>7.1f}s  {p95:>7.1f}s  {status:>10s}")

        results["scenarios"].append({
            "label": label, "glucose_mM": glu, "temp_C": tc,
            "p5_s": round(p5, 1), "median_s": round(p50, 1), "p95_s": round(p95, 1),
            "vs_baseline": status,
        })

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
    cs = ax.contour(glu_range, temp_range, prob_grid,
                     levels=[0.5], colors="white", linewidths=2)
    ax.clabel(cs, fmt={0.5: "50%"}, fontsize=9)
    ax.set_xlabel("[glucose] (mM)")
    ax.set_ylabel("Temperature (°C)")
    ax.set_title("P(delta_t < 60s) — old-baseline fraction (lab-scale; E.63: GP now field-scale)")
    fig.colorbar(im, ax=ax, label="Probability")

    # Distribution at reference condition (10 mM, 25°C)
    ax2 = axes[1]
    dt_ref = delta_t(10, 25, km, ea, jmax, a_el, e_cyc)
    dt_ref = np.clip(dt_ref, 0, 300)
    ax2.hist(dt_ref, bins=50, density=True, alpha=0.7, color="steelblue", edgecolor="white")
    ax2.axvline(BASELINE, color="red", linestyle="--", linewidth=2, label="baseline 60s")
    p5, p50, p95 = np.percentile(dt_ref, [5, 50, 95])
    ax2.axvline(p50, color="green", linewidth=2, label=f"median {p50:.0f}s")
    ax2.axvspan(p5, p95, alpha=0.2, color="green", label=f"90% CI [{p5:.0f}-{p95:.0f}s]")
    ax2.set_xlabel("delta_t (seconds)")
    ax2.set_ylabel("Density")
    ax2.set_title("delta_t distribution at 10 mM glucose, 25°C")
    ax2.legend()
    ax2.set_xlim(0, 200)

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
