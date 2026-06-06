#!/usr/bin/env python
"""
L4b — EIS (Electrochemical Impedance Spectroscopy) model for Gen 2.0 EBFC.

Predicts the Nyquist plot (Z_real vs -Z_imag) using a modified Randles
equivalent circuit with parameters derived from L2/L3/L4 in-silico results.

Equivalent circuit
------------------
    Rs — [Rct || CPE] — Zw

  Rs   = solution resistance (xylem sap electrolyte, ~50-200 Ω)
  Rct  = charge transfer resistance (enzyme → Os → electrode)
         Estimated from j_max via: Rct = RT / (n·F·j0·A)
  CPE  = constant phase element (double-layer capacitance, ~10-100 µF/cm²)
  Zw   = Warburg impedance (glucose diffusion through matrix)
         σ = RT / (n²·F²·A·√2) × (1/(D_glucose·[glucose]))

Parameters from in-silico pipeline
-----------------------------------
  j_max = 494 µA/cm² (L3, dgrGcGDH + Os-polymer, Zafar 2012)
  D_eff = 2e-6 cm²/s (L4, glucose in chitosan hydrogel)
  A     = 2 cm² (effective electrode area on gyroid)
  [S]   = 10 mM (typical xylem glucose)

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/31_eis_impedance_model.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    A_ELECTRODE,
    D_EFF_GLUCOSE,
    F_CONST,
    J_MAX_25C,
    KINETICS_DIR,
    N_ELECTRONS,
    R_GAS,
    REPO_ROOT,
    TEMPERATURE_K,
)
from lib.utils import banner

OUT_DIR = KINETICS_DIR
OUT_DIR.mkdir(parents=True, exist_ok=True)

T = TEMPERATURE_K
N_E = N_ELECTRONS
J_MAX = J_MAX_25C
D_GLUCOSE = D_EFF_GLUCOSE
C_GLUCOSE = 10e-6        # mol/cm³ (= 10 mM)

R_S = 100.0              # Ω — solution resistance (xylem sap ~50-200 Ω)
CDL = 50e-6              # F/cm² — double layer capacitance
CPE_N = 0.85             # CPE exponent (1.0 = ideal capacitor, 0.5 = Warburg)

FREQ_MIN = 0.01          # Hz
FREQ_MAX = 100_000       # Hz
N_POINTS = 200


def compute_rct() -> float:
    """Charge transfer resistance from exchange current density."""
    j0 = J_MAX * 0.1  # exchange current ~10% of j_max (Butler-Volmer at low η)
    return R_GAS * T / (N_E * F_CONST * j0 * A_ELECTRODE)


def compute_warburg_sigma() -> float:
    """Warburg coefficient σ (Ω·s^-0.5)."""
    return (R_GAS * T) / (N_E**2 * F_CONST**2 * A_ELECTRODE * np.sqrt(2)) * \
           (1.0 / (np.sqrt(D_GLUCOSE) * C_GLUCOSE))


def impedance_randles(freq: np.ndarray, rs: float, rct: float,
                      cdl: float, cpn: float, sigma: float) -> np.ndarray:
    """Modified Randles circuit impedance: Rs + [Rct || CPE] + Zw."""
    omega = 2 * np.pi * freq

    # CPE: Z_cpe = 1 / (Q·(jω)^n), where Q relates to capacitance
    Q = cdl * A_ELECTRODE  # total capacitance
    z_cpe = 1.0 / (Q * (1j * omega) ** cpn)

    # Warburg: Zw = σ/√ω × (1 - j)
    z_w = sigma / np.sqrt(omega) * (1 - 1j)

    # Rct + Zw in parallel with CPE
    z_faradaic = rct + z_w
    z_parallel = (z_faradaic * z_cpe) / (z_faradaic + z_cpe)

    return rs + z_parallel


def main() -> int:
    banner("EIS impedance model for Gen 2.0 EBFC anode")

    rct = compute_rct()
    sigma = compute_warburg_sigma()

    print("  Parameters:")
    print(f"    Rs  = {R_S:.0f} Ω (solution)")
    print(f"    Rct = {rct:.0f} Ω (charge transfer)")
    print(f"    Cdl = {CDL*1e6:.0f} µF/cm²")
    print(f"    CPE n = {CPE_N}")
    print(f"    σ   = {sigma:.1f} Ω·s⁻⁰·⁵ (Warburg)")
    print(f"    j_max = {J_MAX*1e6:.0f} µA/cm², A = {A_ELECTRODE} cm²")

    freq = np.logspace(np.log10(FREQ_MIN), np.log10(FREQ_MAX), N_POINTS)
    z = impedance_randles(freq, R_S, rct, CDL, CPE_N, sigma)

    z_real = z.real
    z_imag = -z.imag

    banner("Generating Nyquist and Bode plots")

    fig, axes = plt.subplots(1, 3, figsize=(16, 5))

    # Nyquist plot
    ax = axes[0]
    ax.plot(z_real, z_imag, "b-", linewidth=1.5)
    ax.set_xlabel("Z' (Ω)")
    ax.set_ylabel("-Z'' (Ω)")
    ax.set_title("Nyquist plot — EBFC Gen 2.0 anode")
    ax.set_aspect("equal")
    ax.grid(True, alpha=0.3)
    # Mark key frequencies
    for f_mark in [0.1, 1, 10, 100, 1000]:
        idx = np.argmin(np.abs(freq - f_mark))
        ax.plot(z_real[idx], z_imag[idx], "ro", markersize=5)
        ax.annotate(f"{f_mark} Hz", (z_real[idx], z_imag[idx]),
                    textcoords="offset points", xytext=(5, 5), fontsize=7)

    # Bode magnitude
    ax2 = axes[1]
    ax2.loglog(freq, np.abs(z), "b-", linewidth=1.5)
    ax2.set_xlabel("Frequency (Hz)")
    ax2.set_ylabel("|Z| (Ω)")
    ax2.set_title("Bode magnitude")
    ax2.grid(True, alpha=0.3, which="both")

    # Bode phase
    ax3 = axes[2]
    phase = np.degrees(np.arctan2(z.imag, z.real))
    ax3.semilogx(freq, -phase, "r-", linewidth=1.5)
    ax3.set_xlabel("Frequency (Hz)")
    ax3.set_ylabel("-Phase (°)")
    ax3.set_title("Bode phase")
    ax3.grid(True, alpha=0.3, which="both")

    fig.suptitle(
        f"EIS Model: Rs={R_S:.0f}Ω, Rct={rct:.0f}Ω, Cdl={CDL*1e6:.0f}µF/cm², σ={sigma:.0f}Ω·s⁻⁰·⁵",
        fontsize=10,
    )
    fig.tight_layout()
    fig_path = OUT_DIR / "eis_nyquist.png"
    fig.savefig(fig_path, dpi=140)
    print(f"  Wrote {fig_path.relative_to(REPO_ROOT)}")

    # Save results
    results = {
        "model": "Modified Randles: Rs + [Rct||CPE] + Zw",
        "parameters": {
            "Rs_ohm": R_S,
            "Rct_ohm": round(rct, 1),
            "Cdl_uF_cm2": CDL * 1e6,
            "CPE_n": CPE_N,
            "sigma_warburg": round(sigma, 1),
            "j_max_uA_cm2": J_MAX * 1e6,
            "A_electrode_cm2": A_ELECTRODE,
            "D_glucose_cm2_s": D_GLUCOSE,
            "C_glucose_mM": C_GLUCOSE * 1e6,
        },
        "diagnostics": {
            "semicircle_diameter_ohm": round(rct, 1),
            "high_freq_intercept_ohm": R_S,
            "low_freq_slope": "45° Warburg tail",
            "time_constant_s": round(rct * CDL * A_ELECTRODE, 4),
        },
        "predictions_for_ti_coin": {
            "expected_Rct_range_ohm": f"{rct*0.5:.0f}-{rct*2:.0f}",
            "expected_Rs_range_ohm": "50-200",
            "warburg_region_below_Hz": round(1.0 / (2 * np.pi * rct * CDL * A_ELECTRODE), 2),
        },
    }

    json_path = OUT_DIR / "eis_model.json"
    with json_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    print(f"  Wrote {json_path.relative_to(REPO_ROOT)}")

    banner("EIS predictions for Ti-coin Stage 2 experiments")
    print(f"  Semicircle diameter (Rct): ~{rct:.0f} Ω")
    print(f"  High-freq intercept (Rs): ~{R_S:.0f} Ω")
    print(f"  Time constant τ = Rct×Cdl×A: {rct * CDL * A_ELECTRODE * 1e3:.1f} ms")
    print(f"  Warburg region: below ~{1.0/(2*np.pi*rct*CDL*A_ELECTRODE):.1f} Hz")
    print("  ✅ These predictions can be compared with CV/EIS data from Ti-coin tests")

    banner("✅ EIS model complete")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
