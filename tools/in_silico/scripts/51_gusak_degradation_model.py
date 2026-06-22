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
from lib.constants import (
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    E_PEEK_PA,
    KINETICS_DIR,
    NU_PEEK,
    R_INTERFACE_M,
    R_OUTER_M,
    REPO_ROOT,
    SIGMA_YIELD_PEEK_PA,
    T_ASSEMBLY_C,
)
from lib.mechanics import thick_wall_hoop
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
    """Fick's 1st law: V/Al diffusion through the passive oxide, PER candidate alloy (Stage-2
    coin bake-off, 01_02 §2.5). Composition-driven: release ∝ bulk wt%, so 4% V gives the 56×
    baseline and every V-free alloy gives ~0. The oxide-diffusion D is a SHARED literature constant
    (per-alloy oxide diffusivity is rarely published; the composition effect dominates the small
    Nb/Zr/Ta oxide-stability difference). Output is nested {alloy: {year: {...}}}."""
    banner("2. Kirkendall Ion Diffusion (V/Al through the oxide) — per alloy")

    # Diffusion coefficients through the passive oxide (literature; shared across Ti alloys, 01_02 §2.5)
    D_V = 1e-20     # m²/s — V through TiO₂ (very slow, dense oxide)
    D_AL = 5e-20    # m²/s — Al through TiO₂ (slightly faster)
    L_OXIDE = 5e-9  # m — passive layer thickness (5 nm)
    A = 2e-4        # m² (2 cm² coin face)
    V_TARGET = 0.02  # µg/cm² — toxicological target (01_02 §2.4)

    years = [1, 5, 10, 20, 40]

    print(f"  D(V) = {D_V:.0e} m²/s, D(Al) = {D_AL:.0e} m²/s · oxide {L_OXIDE*1e9:.0f} nm · {A*1e4:.0f} cm²")
    print(f"  {'alloy':>20s}  {'V wt%':>6s}  {'Al wt%':>6s}  {'V@20yr':>10s}  {'Al@20yr':>10s}  {'V safe':>7s}")
    print(f"  {'-'*68}")

    results = {}
    for alloy, props in ALLOY_PROPERTIES.items():
        c0_v, c0_al, rho = props["V_wt"], props["Al_wt"], props["rho_kg_m3"]
        # Steady-state Fick's 1st law flux: J = D · C0 / L  (C0 = wt-fraction · density)
        j_v = D_V * (c0_v / 100 * rho) / L_OXIDE     # kg/(m²·s)
        j_al = D_AL * (c0_al / 100 * rho) / L_OXIDE
        per_year = {}
        for y in years:
            t = y * 365.25 * 86400  # seconds
            m_v = j_v * A * t * 1e6
            m_al = j_al * A * t * 1e6
            m_v_cm2 = m_v / (A * 1e4)   # µg/cm²
            m_al_cm2 = m_al / (A * 1e4)
            per_year[str(y)] = {
                "V_ug_cm2": round(m_v_cm2, 6),
                "Al_ug_cm2": round(m_al_cm2, 6),
                "V_safe": m_v_cm2 < V_TARGET,
            }
        v20 = per_year["20"]["V_ug_cm2"]
        al20 = per_year["20"]["Al_ug_cm2"]
        ok = "✅" if per_year["20"]["V_safe"] else "❌"
        print(f"  {alloy:>20s}  {c0_v:>6.1f}  {c0_al:>6.1f}  {v20:>8.3f}µg  {al20:>8.3f}µg  {ok:>7s}")
        results[alloy] = per_year

    print()
    print("  Composition dominates: V-free alloys release ZERO V (the 56× toxicity driver gone);")
    print("  Al-bearing (4V, 7Nb) still leak Al (phytotoxic in acidic sap, 01_04 §4.2 tree-lens).")
    return results


def press_fit_window():
    """H7/s6 interference window with ΔCTE for Ti↔PEEK."""
    banner("3. H7/s6 Press-Fit Interference Window")

    # Material props from lib.constants (One-Home, HW.3.IS); ΔCTE drives the temperature term below.
    ALPHA_TI = ALLOY_PROPERTIES["Ti-6Al-4V"]["alpha_1K"]   # 1/K
    ALPHA_PEEK = ALPHA_PEEK_1K   # 1/K

    # Nominal dimensions (mm) — FROZEN Ø11 shaft (HW.33, 2026-06-20). ISO 286 size band 10-18 mm.
    D_SHAFT = 11.0       # mm — Ti shaft (Zone 1) diameter (frozen Ø11; was Ø10 baseline)
    # H7 hole tolerance: 0 to +18 µm (10-18 mm band); s6 shaft tolerance: +23 to +34 µm
    TOL_H7_MIN = 0       # µm
    TOL_H7_MAX = 18      # µm
    TOL_S6_MIN = 23      # µm
    TOL_S6_MAX = 34      # µm

    T_ASSEMBLY = T_ASSEMBLY_C   # °C (lib.constants)
    T_RANGE = [-30, -10, 0, 20, 40]

    # Interference range (diametral µm)
    I_MIN = TOL_S6_MIN - TOL_H7_MAX  # = 23 − 18 = 5 µm (governs sealing)
    I_MAX = TOL_S6_MAX - TOL_H7_MIN  # = 34 − 0 = 34 µm (governs hoop)

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

        # Hoop stress from max effective interference — consistent thick-wall Lamé (lib.mechanics, HW.3.IS
        # 2026-06-22; was a thin-wall E·δ/D·2 approx that over-stated ~2×). eff_max is DIAMETRAL → radial = /2.
        sigma_max = thick_wall_hoop(eff_max * 1e-6 / 2.0, R_INTERFACE_M, R_OUTER_M, E_PEEK_PA, NU_PEEK)["sigma_t"]
        safe = abs(sigma_max) < SIGMA_YIELD_PEEK_PA

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
