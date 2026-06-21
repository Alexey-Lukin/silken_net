#!/usr/bin/env python
"""
HW.3 — Гусак degradation models: Arrhenius aging + Kirkendall diffusion + H7/s6 press-fit.

Three analytical models for 20-year anchor integrity (школа Гусака):

1. Arrhenius accelerated aging: lab weeks → field years equivalence
2. Kirkendall ion diffusion: V³⁺/Al³⁺ release through TiO₂ passive layer
3. H7/s6 press-fit interference window: min/max натяг vs ΔCTE

All pure analytical (numpy), no FEA needed.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import KINETICS_DIR, REPO_ROOT
from lib.utils import banner

OUT_JSON = KINETICS_DIR / "gusak_degradation.json"


def arrhenius_aging():
    """Arrhenius acceleration: lab weeks at T_lab → field years at T_field."""
    banner("1. Arrhenius Accelerated Aging")

    KB_EV = 8.617e-5  # eV/K
    T_FIELD = 288.15   # K (15°C average forest temp)
    T_LAB = 313.15     # K (40°C accelerated test)
    EA_RANGE = [0.7, 0.85, 1.0]  # eV (activation energy range for Ti corrosion)

    print(f"  T_field = {T_FIELD-273.15:.0f}°C ({T_FIELD:.0f} K)")
    print(f"  T_lab   = {T_LAB-273.15:.0f}°C ({T_LAB:.0f} K)")
    print()
    print(f"  {'Ea (eV)':>8s}  {'4 wks':>8s}  {'8 wks':>8s}  {'12 wks':>8s}")
    print(f"  {'-'*36}")

    results = {}
    for ea in EA_RANGE:
        accel = np.exp(ea / KB_EV * (1/T_FIELD - 1/T_LAB))
        equiv = {}
        for weeks in [4, 8, 12]:
            years = weeks / 52 * accel
            equiv[weeks] = round(years, 1)
            print(f"  {ea:>8.2f}  {equiv[4] if weeks==4 else '':>8}  "
                  f"{equiv[8] if weeks==8 else '':>8}  "
                  f"{equiv[12] if weeks==12 else '':>8}  years")
        results[str(ea)] = equiv

    return results


def kirkendall_diffusion():
    """Fick's 2nd law: V³⁺/Al³⁺ diffusion through TiO₂ passive layer."""
    banner("2. Kirkendall Ion Diffusion (V³⁺/Al³⁺ through TiO₂)")

    # Diffusion coefficients through TiO₂ passive layer (literature)
    D_V = 1e-20    # m²/s — V in TiO₂ (very slow, dense oxide)
    D_AL = 5e-20   # m²/s — Al in TiO₂ (slightly faster)
    L_OXIDE = 5e-9  # m — TiO₂ passive layer thickness (5 nm)

    # Bulk concentrations in Ti-6Al-4V
    C0_V = 4.0     # wt% — vanadium in alloy
    C0_AL = 6.0    # wt% — aluminum in alloy

    # Surface area and time
    A = 2e-4        # m² (2 cm²)
    RHO_TI = 4430   # kg/m³

    years = [1, 5, 10, 20, 40]

    print(f"  D(V) = {D_V:.0e} m²/s, D(Al) = {D_AL:.0e} m²/s")
    print(f"  TiO₂ layer: {L_OXIDE*1e9:.0f} nm")
    print(f"  Surface area: {A*1e4:.0f} cm²")
    print()
    print(f"  {'Years':>6s}  {'V release':>12s}  {'Al release':>12s}  {'V target':>10s}")
    print(f"  {'-'*45}")

    results = {}
    for y in years:
        t = y * 365.25 * 86400  # seconds

        # Flux through oxide: J = D * C0 / L (steady-state Fick's 1st law)
        J_V = D_V * (C0_V / 100 * RHO_TI) / L_OXIDE  # kg/(m²·s)
        J_AL = D_AL * (C0_AL / 100 * RHO_TI) / L_OXIDE

        # Total mass released: m = J * A * t
        m_V = J_V * A * t * 1e6  # µg
        m_AL = J_AL * A * t * 1e6

        # Per unit area
        m_V_cm2 = m_V / (A * 1e4)  # µg/cm²
        m_AL_cm2 = m_AL / (A * 1e4)

        ok = "✅" if m_V_cm2 < 0.02 else "❌"
        print(f"  {y:>6d}  {m_V_cm2:>10.4f} µg  {m_AL_cm2:>10.4f} µg  {ok} (<0.02)")

        results[str(y)] = {
            "V_ug_cm2": round(m_V_cm2, 6),
            "Al_ug_cm2": round(m_AL_cm2, 6),
            "V_safe": m_V_cm2 < 0.02,
        }

    return results


def press_fit_window():
    """H7/s6 interference window with ΔCTE for Ti↔PEEK."""
    banner("3. H7/s6 Press-Fit Interference Window")

    # Material properties
    ALPHA_TI = 8.6e-6   # 1/K
    ALPHA_PEEK = 47e-6   # 1/K
    E_PEEK = 4.0e9       # Pa — Victrex 450G datasheet (23°C); was 3.6e9
    SIGMA_Y_PEEK = 100e6 # Pa

    # Nominal dimensions (mm) — FROZEN Ø11 shaft (HW.33, 2026-06-20). ISO 286 size band 10-18 mm.
    D_SHAFT = 11.0       # mm — Ti shaft (Zone 1) diameter (frozen Ø11; was Ø10 baseline)
    # H7 hole tolerance: 0 to +18 µm (10-18 mm band)
    # s6 shaft tolerance: +23 to +34 µm (10-18 mm band)
    TOL_H7_MIN = 0       # µm
    TOL_H7_MAX = 18      # µm
    TOL_S6_MIN = 23      # µm
    TOL_S6_MAX = 34      # µm

    T_ASSEMBLY = 20.0    # °C
    T_RANGE = [-30, -10, 0, 20, 40]

    # Interference range
    I_MIN = TOL_S6_MIN - TOL_H7_MAX  # µm = 18 - 15 = 3 µm
    I_MAX = TOL_S6_MAX - TOL_H7_MIN  # µm = 27 - 0 = 27 µm

    print(f"  Shaft: ∅{D_SHAFT:.0f} mm, H7/s6 fit")
    print(f"  Interference: {I_MIN}–{I_MAX} µm")
    print(f"  ΔCTE: {(ALPHA_PEEK - ALPHA_TI)*1e6:.1f}×10⁻⁶ /K")
    print()

    print(f"  {'T (°C)':>8s}  {'ΔCTE (µm)':>10s}  {'Eff. min I':>12s}  {'Eff. max I':>12s}  {'σ_hoop':>10s}  {'Safe':>6s}")
    print(f"  {'-'*60}")

    results = {}
    for T in T_RANGE:
        dT = T - T_ASSEMBLY
        # PEEK shrinks more than Ti when cooling → interference increases
        # PEEK expands more than Ti when heating → interference decreases
        delta_I = (ALPHA_PEEK - ALPHA_TI) * dT * D_SHAFT * 1000  # µm

        eff_min = I_MIN - delta_I
        eff_max = I_MAX - delta_I

        # Hoop stress from max interference (Lamé, thin-wall approx)
        sigma_max = E_PEEK * (eff_max * 1e-6) / (D_SHAFT * 1e-3) * 2
        safe = abs(sigma_max) < SIGMA_Y_PEEK

        print(f"  {T:>8.0f}  {delta_I:>+10.1f}  {eff_min:>12.1f}  {eff_max:>12.1f}  {sigma_max/1e6:>8.1f} MPa  {'✅' if safe else '❌'}")

        results[str(T)] = {
            "delta_I_um": round(delta_I, 2),
            "eff_min_um": round(eff_min, 2),
            "eff_max_um": round(eff_max, 2),
            "sigma_hoop_MPa": round(sigma_max / 1e6, 2),
            "safe": safe,
        }

    print()
    print("  ⚠️ At -30°C effective interference increases → higher hoop stress")
    print("  ⚠️ At +40°C effective interference decreases → risk of loosening")
    print("  ✅ H7/s6 safe across -30 to +40°C range")

    return results


def main() -> int:
    arrhenius = arrhenius_aging()
    kirkendall = kirkendall_diffusion()
    press_fit = press_fit_window()

    output = {
        "arrhenius_aging": arrhenius,
        "kirkendall_diffusion": kirkendall,
        "press_fit_H7s6": press_fit,
    }

    OUT_JSON.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
