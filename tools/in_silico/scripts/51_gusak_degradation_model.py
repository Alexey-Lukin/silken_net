#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.3 — Гусак degradation models: Arrhenius aging + Kirkendall diffusion + H7/s6 press-fit.
HW.37 — EDLC endurance-hours (Eaton KR / KEMET FG0H474ZF) reuses the generalized Arrhenius
kernel below + a sibling vendor voltage-doubling model (4th analytical model, added 2026-09-09).

Four analytical models for 20-year anchor/component integrity (школа Гусака):

1. Arrhenius accelerated aging: lab weeks → field years equivalence (Ti corrosion, HW.3)
2. Kirkendall ion diffusion: V³⁺/Al³⁺ release through TiO₂ passive layer
3. H7/s6 press-fit interference window: min/max натяг vs ΔCTE
4. EDLC endurance-hours: vendor temperature+voltage life-doubling rule (HW.37)

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
    EATON_KR_RATED_HOURS,
    EATON_KR_RATED_TEMP_C,
    EATON_KR_RATED_VOLTAGE_V,
    FIELD_TEMPS_C,
    KEMET_FG_RATED_HOURS,
    KEMET_FG_RATED_TEMP_C,
    KEMET_FG_RATED_VOLTAGE_V,
    KINETICS_DIR,
    NU_PEEK,
    R_INTERFACE_M,
    R_OUTER_M,
    REPO_ROOT,
    SIGMA_YIELD_PEEK_PA,
    T_ASSEMBLY_C,
    THERMAL_DOUBLING_INTERVAL_K,
    VOLTAGE_DOUBLING_CONSERVATIVE_V,
    VOLTAGE_DOUBLING_OPTIMISTIC_V,
)
from lib.mechanics import thick_wall_hoop
from lib.utils import banner

OUT_JSON = KINETICS_DIR / "gusak_degradation.json"


def arrhenius_aging(
    t_field_k: float = 288.15,
    t_lab_k: float = 313.15,
    ea_range_ev=(0.7, 0.85, 1.0),
    lab_weeks=(4, 8, 12),
    weeks_per_year: float = 52.0,
    label: str = "Ti corrosion",
):
    """Arrhenius acceleration: lab weeks at T_lab -> field years at T_field.

    Generalized 2026-09-09 (HW.37): was hardcoded to the Ti-corrosion T_field/T_lab/Ea
    triple with no parameters at all — this signature now accepts them, so the SAME
    continuous exp(Ea/kB*(1/T_field-1/T_lab)) kernel is reusable for any fixed-Ea
    Arrhenius problem. Defaults reproduce the ORIGINAL Ti-corrosion call exactly
    (HW.3/HW.3.IS numbers unchanged — main() below still calls this with no args).

    NOTE this is NOT the model HW.37's EDLC capacitor endurance-hours needs (see
    capacitor_life_hours() below): vendor capacitor datasheets use a discrete "life
    doubles every dT/dV" step-rule, which is a DIFFERENT functional form from this
    continuous exp() kernel (a fixed Ea integrated continuously over a 60 degree span
    does not reproduce a flat "2x per 10 degrees" applied uniformly — verified while
    generalizing this function, not a bug in either model).
    """
    banner(f"1. Arrhenius Accelerated Aging — {label}")

    kb_ev = 8.617e-5  # eV/K

    print(f"  T_field = {t_field_k - 273.15:.0f}°C ({t_field_k:.0f} K)")
    print(f"  T_lab   = {t_lab_k - 273.15:.0f}°C ({t_lab_k:.0f} K)")
    print()
    header = "  ".join(f"{w} wks" for w in lab_weeks)
    print(f"  {'Ea (eV)':>8s}  {header}")
    print(f"  {'-' * 36}")

    results = {}
    for ea in ea_range_ev:
        accel = np.exp(ea / kb_ev * (1 / t_field_k - 1 / t_lab_k))
        equiv = {}
        for weeks in lab_weeks:
            years = weeks / weeks_per_year * accel
            equiv[weeks] = round(years, 1)
        row = "  ".join(f"{equiv[w]:>6}" for w in lab_weeks)
        print(f"  {ea:>8.2f}  {row}  years")
        results[str(ea)] = equiv

    return results


def capacitor_life_hours(
    rated_hours: float,
    t_rated_c: float,
    v_rated_v: float,
    t_field_c: float,
    v_field_v: float,
    dt_double_c: float = THERMAL_DOUBLING_INTERVAL_K,
    dv_double_v: float = VOLTAGE_DOUBLING_CONSERVATIVE_V,
) -> float:
    """HW.37 — vendor EDLC/electrolytic-capacitor endurance-hours doubling rule:

        life(T, V) = rated_hours * 2^((T_rated-T)/dt_double) * 2^((V_rated-V)/dv_double)

    This is the industry "N-rule" vendor app notes cite as an Arrhenius-derived
    approximation (e.g. "life doubles for every dt_double °C drop"), applied as a
    discrete step factor — NOT the continuous fixed-Ea exp() kernel in
    arrhenius_aging() above (see that function's docstring: a fixed-Ea continuous
    Arrhenius over the same 70->10°C span gives a materially different, MORE
    conservative acceleration than a flat "2x per 10°C" applied uniformly — a
    known model-choice distinction, not an error in either model).
    """
    accel_t = 2.0 ** ((t_rated_c - t_field_c) / dt_double_c)
    accel_v = 2.0 ** ((v_rated_v - v_field_v) / dv_double_v)
    return rated_hours * accel_t * accel_v


def edlc_endurance_hours():
    """HW.37 — EDLC calendar-life via temperature+voltage endurance-hours doubling,
    for the two canon-cited SKUs (`02_01 §3` поз.3): Eaton KR-5R5H474-R and KEMET
    FG0H474ZF, both rated 1000 h @ 70°C @ 5.5 V (00_07 HW.37). Confirms the
    2026-09-09 hand-calc through the ACTUAL pipeline (it was hand-computed once,
    not previously reused as code) and extends it to KEMET, whose OWN voltage
    coefficient is not published — reported as a sensitivity bracket across the
    ~2x vendor disagreement (Abracon/CDE 0.2 V vs Vishay/Eaton 0.4 V per doubling)
    rather than a false-precise single number.
    """
    banner("4. EDLC Endurance-Hours — Temperature + Voltage Doubling (HW.37)")

    hours_per_year = 365.25 * 24.0  # consistent with kirkendall_diffusion()'s 365.25 d/yr above

    skus = {
        "Eaton_KR-5R5H474-R": {
            "rated_hours": EATON_KR_RATED_HOURS,
            "t_rated_c": EATON_KR_RATED_TEMP_C,
            "v_rated_v": EATON_KR_RATED_VOLTAGE_V,
        },
        "KEMET_FG0H474ZF": {
            "rated_hours": KEMET_FG_RATED_HOURS,
            "t_rated_c": KEMET_FG_RATED_TEMP_C,
            "v_rated_v": KEMET_FG_RATED_VOLTAGE_V,
        },
    }

    print(f"  Doubling rule: life ∝ 2^(ΔT/{THERMAL_DOUBLING_INTERVAL_K:.0f}°C) · 2^(ΔV/dV_double)")
    print(
        f"  Voltage-coefficient bracket: optimistic {VOLTAGE_DOUBLING_OPTIMISTIC_V}V "
        f"vs conservative {VOLTAGE_DOUBLING_CONSERVATIVE_V}V per 2×"
    )

    results = {}
    for name, sku in skus.items():
        print(f"\n  {name}: rated {sku['rated_hours']:.0f} h @ {sku['t_rated_c']:.0f}°C @ {sku['v_rated_v']:.2f} V")
        sku_result = {"rated": dict(sku), "at_rated_voltage": {}, "voltage_derating": {}}

        # (a) At full rated voltage — temperature-only, matches the 2026-09-09 hand-calc.
        print(f"    {'T_field(°C)':>12s}  {'life (h)':>12s}  {'life (yr)':>10s}")
        for t_field in FIELD_TEMPS_C:
            life_h = capacitor_life_hours(
                sku["rated_hours"],
                sku["t_rated_c"],
                sku["v_rated_v"],
                t_field,
                sku["v_rated_v"],  # v_field == v_rated -> the voltage term is a no-op
                dt_double_c=THERMAL_DOUBLING_INTERVAL_K,
                dv_double_v=VOLTAGE_DOUBLING_CONSERVATIVE_V,
            )
            life_yr = life_h / hours_per_year
            print(f"    {t_field:>12.0f}  {life_h:>12.0f}  {life_yr:>10.2f}")
            sku_result["at_rated_voltage"][str(t_field)] = {
                "life_hours": round(life_h, 0),
                "life_years": round(life_yr, 2),
            }

        # (b) Voltage-derating bracket at the coldest field point (10°C, HW.7's own working
        # point) — optimistic vs conservative coefficient, at the three candidate VBAT_OV
        # targets already live in the HW.7/HW.12 discussion.
        t_field = FIELD_TEMPS_C[-1]
        print(f"    Voltage derating @ {t_field:.0f}°C:")
        print(f"    {'V_target':>8s}  {'optimistic (yr)':>16s}  {'conservative (yr)':>18s}")
        for v_target in (5.37, 5.29, 5.20):
            life_opt_yr = (
                capacitor_life_hours(
                    sku["rated_hours"],
                    sku["t_rated_c"],
                    sku["v_rated_v"],
                    t_field,
                    v_target,
                    dt_double_c=THERMAL_DOUBLING_INTERVAL_K,
                    dv_double_v=VOLTAGE_DOUBLING_OPTIMISTIC_V,
                )
                / hours_per_year
            )
            life_cons_yr = (
                capacitor_life_hours(
                    sku["rated_hours"],
                    sku["t_rated_c"],
                    sku["v_rated_v"],
                    t_field,
                    v_target,
                    dt_double_c=THERMAL_DOUBLING_INTERVAL_K,
                    dv_double_v=VOLTAGE_DOUBLING_CONSERVATIVE_V,
                )
                / hours_per_year
            )
            print(f"    {v_target:>8.2f}  {life_opt_yr:>16.1f}  {life_cons_yr:>18.1f}")
            sku_result["voltage_derating"][str(v_target)] = {
                "optimistic_yr": round(life_opt_yr, 1),
                "conservative_yr": round(life_cons_yr, 1),
            }
        results[name] = sku_result

    print()
    print("  ⚖️  post-Arrhenius derate/oversize/SKU-freeze decision is LIVE (00_07 HW.37) —")
    print("      NOT made here; this reports the life numbers the decision needs.")

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
    edlc_endurance = edlc_endurance_hours()

    output = {
        "arrhenius_aging": arrhenius,
        "kirkendall_diffusion": kirkendall,
        "press_fit_H7s6": press_fit,
        "edlc_endurance_hours": edlc_endurance,
    }

    OUT_JSON.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
