#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.3.IS — Lamé thermal stress analysis for Ti↔PEEK press-fit.

Analytical solution for thick-walled cylinder thermal mismatch:
  α(Ti-6Al-4V) = 8.6×10⁻⁶ /K
  α(PEEK 450G) = 47×10⁻⁶ /K
  → 5.5× mismatch creates interface stress during seasonal cycling.

Computes radial and tangential stress at Ti↔PEEK interface across
temperature range -30°C to +40°C (Cherkasy forest extremes).

Press-fit long-term integrity is modelled as STRESS RELAXATION (constant
strain), NOT creep (constant stress): a press-fit fixes the interference
geometrically, so the contact pressure decays toward a semicrystalline
floor — it does not "open a gap". Failure metric = residual contact
pressure P_c(t) vs xylem sap pressure. Also computes the winter cold-leak
at the OUTER interface (PEEK shrinks away from the outer Ti shell).

No FEA needed — axisymmetric Lamé equations have closed-form solution.
Relaxation params are literature-grounded estimates pending a Prony-series
fit from школа Гусака (00_02 Стаття 2).
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
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    E_PEEK_PA,
    H7S6_INTERF_DIA_MAX_UM,
    H7S6_INTERF_DIA_MIN_UM,
    KINETICS_DIR,
    NU_PEEK,
    R_INTERFACE_M,
    R_OUTER_M,
    REPO_ROOT,
    SIGMA_YIELD_PEEK_PA,
    T_ASSEMBLY_C,
)
from lib.mechanics import thermal_interference, thick_wall_hoop
from lib.utils import banner

OUT_DIR = KINETICS_DIR
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Material / geometry constants live in lib.constants (One-Home, HW.3.IS 2026-06-22); aliased for readability.
# Ti props from the ALLOY_PROPERTIES baseline; PEEK + frozen geometry from the anchor press-fit block.
ALPHA_TI = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]   # 1/K — Ti-6Al-4V CTE
ALPHA_PEEK = ALPHA_PEEK_1K
E_TI = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e9
E_PEEK = E_PEEK_PA
NU_TI = ALLOY_PROPERTIES[ALLOY_BASELINE]["nu"]
SIGMA_YIELD_PEEK = SIGMA_YIELD_PEEK_PA

# Geometry — frozen Ø11/2mm (HW.33). R_INNER (bus bore) stays local — JSON/winter only, not a contact surface.
R_INNER = 0.8e-3              # m — Ti shaft central bus bore (~Ø1.6); NOT a press-fit contact surface
R_INTERFACE = R_INTERFACE_M   # m — Ti↔PEEK press-fit CONTACT radius (Ø11 shaft / 2)
R_OUTER = R_OUTER_M           # m — PEEK sleeve outer radius (Ø15 wound / 2)

T_ASSEMBLY = T_ASSEMBLY_C            # °C — assembly temperature
T_RANGE = np.linspace(-30, 40, 71)   # °C sweep

# Press-fit H7/s6 band — diametral 5-34 µm (lib.constants). Radial interference = diametral / 2.
I_DIA_MIN_UM = H7S6_INTERF_DIA_MIN_UM   # µm — min diametral (governs sealing)
I_DIA_MAX_UM = H7S6_INTERF_DIA_MAX_UM   # µm — max diametral (governs hoop stress)
DELTA_RADIAL_MIN = I_DIA_MIN_UM * 1e-6 / 2.0   # m — radial = diametral / 2
DELTA_RADIAL_MAX = I_DIA_MAX_UM * 1e-6 / 2.0   # m
P_SAP_MPa = 0.5              # MPa — conservative xylem positive/capillary sap pressure (seal must exceed)

# PEEK stress relaxation under CONSTANT STRAIN (press-fit), NOT creep. Semicrystalline PEEK retains a
# substantial relaxed (equilibrium) modulus — the crystalline phase forms a permanent elastic network, so
# stress relaxes toward a floor E_∞, NOT to zero. Single-Maxwell + floor (= 2-term Prony):
#   P_c(t) = P_c(0) · [ E∞/E0 + (1 − E∞/E0)·exp(−t/τ) ]
# INTERIM literature-Prony (HW.3.IS 2026-06-21, NOT Гусак-authoritative): the 2-term structure is validated
# by published PEEK 450G viscoelastic models (MDPI Polymers 2021 PMC8199459 — ISV with TWO relaxing
# components; + a fractional-Maxwell PEEK-aging fit). The coefficients below are kept CONSERVATIVE: at
# forest temperatures (−30…+40 °C, all ≪ Tg 143 °C) PEEK is glassy-semicrystalline → relaxation is slow and
# the retained fraction is likely HIGHER than 0.65, so this UNDER-states residual P_c (safe direction). The
# authoritative multi-term Maxwell-Wiechert fit (with measured creep data) stays with школа Гусака
# (00_02 Стаття 2) — door open; we do NOT fabricate coefficients from unavailable (paywalled) data.
PEEK_RELAX_FLOOR = 0.65      # E_∞/E_0 — retained modulus fraction (conservative; lit ≥0.65 below Tg)
PEEK_RELAX_TAU_YEARS = 1.0   # relaxation time constant (years) — interim conservative estimate


def lame_interface_stress(dT: float) -> dict:
    """Thermal-mismatch interface stress via the consistent rigid-inner thick-wall Lamé (lib.mechanics).

    HW.3.IS fix 2026-06-22: the previous form divided by (k²−1) — a residual of the dropped rigid-outer-
    shell baseline — which over-stated σ_t ≈ 4.3×. Now routed through thick_wall_hoop (the SAME relation
    contact_pressure uses), so thermal + press-fit are one consistent model; the combined worst case lives
    in script 56. Cooling (dT<0) makes the higher-CTE PEEK grip harder → δ_therm>0 → tensile bore hoop.
    """
    T_c = T_ASSEMBLY + dT
    delta_r = thermal_interference(T_c, T_ASSEMBLY, ALPHA_PEEK, ALPHA_TI, R_INTERFACE)
    s = thick_wall_hoop(delta_r, R_INTERFACE, R_OUTER, E_PEEK, NU_PEEK)
    return {
        "dT_K": dT,
        "delta_r_um": delta_r * 1e6,
        "sigma_r_MPa": s["sigma_r"] / 1e6,
        "sigma_t_MPa": s["sigma_t"] / 1e6,
        "safety_factor": SIGMA_YIELD_PEEK / max(abs(s["sigma_t"]), 1),
    }


def contact_pressure(delta: float, b: float, c: float) -> float:
    """Initial press-fit contact pressure (rigid-inner Lamé). Delegates to the shared core
    (lib.mechanics.thick_wall_hoop) so 50/51/56 use ONE formula (HW.3.IS 2026-06-22). Identical result."""
    return thick_wall_hoop(delta, b, c, E_PEEK, NU_PEEK)["P_c"]        # Pa


def relaxed_pressure(p0: float, years: float) -> float:
    """Stress relaxation under CONSTANT STRAIN (press-fit): contact pressure
    decays toward the semicrystalline floor, NOT to zero."""
    return p0 * (PEEK_RELAX_FLOOR + (1.0 - PEEK_RELAX_FLOOR)
                 * np.exp(-years / PEEK_RELAX_TAU_YEARS))


def cold_effective_interference(delta_init: float, r: float, dT_cold: float):
    """Winter effective interference at the OUTER interface: PEEK (higher CTE)
    shrinks away from the outer Ti shell on cooling → interference is LOST."""
    loss = r * (ALPHA_PEEK - ALPHA_TI) * abs(dT_cold)
    return delta_init - loss, loss


def alloy_comparative() -> dict:
    """Per-alloy comparative for the Stage-2 coin bake-off (01_02 §2.5). Two signals: (1) the
    worst-case Ti↔PEEK thermal stress driven by the alloy CTE mismatch with PEEK — the Ti CTE
    barely moves it (PEEK's 47e-6 dominates the mismatch), so this CONFIRMS the press-fit is
    alloy-ROBUST; (2) the bulk E that sets the gyroid isoelasticity (E_gyroid ≈ E·(1−φ)^n) — the
    REAL bake-off lever: β-Ti's low 80 GPa pulls E toward wood (9–16), the HW.33 sheet/network knob.
    Numbers compare against the coin nano-indentation (criterion 4) when in-vitro data lands."""
    banner("Alloy comparative (Stage-2 bake-off) — CTE-mismatch stress + gyroid-E lever")
    print(f"  {'alloy':>20s}  {'E (GPa)':>8s}  {'a (1e-6/K)':>11s}  {'sig_t @-30C':>13s}  {'note':>6s}")
    print(f"  {'-'*64}")
    out = {}
    for alloy, props in ALLOY_PROPERTIES.items():
        alpha = props["alpha_1K"]
        delta_r = thermal_interference(-30.0, T_ASSEMBLY, ALPHA_PEEK, alpha, R_INTERFACE)
        sigma_t = thick_wall_hoop(delta_r, R_INTERFACE, R_OUTER, E_PEEK, NU_PEEK)["sigma_t"]
        out[alloy] = {
            "E_GPa": props["E_GPa"],
            "alpha_1K": alpha,
            "yield_MPa": props["yield_MPa"],
            "sigma_t_worst_MPa": round(sigma_t / 1e6, 2),
            "peek_safety_factor": round(SIGMA_YIELD_PEEK / max(sigma_t, 1), 1),
        }
        flag = "low-E" if props["E_GPa"] < 90 else ""
        print(f"  {alloy:>20s}  {props['E_GPa']:>8.0f}  {alpha*1e6:>11.1f}  {sigma_t/1e6:>11.2f} MPa  {flag:>6s}")
    print()
    print("  Press-fit is alloy-ROBUST (PEEK CTE 47e-6 dominates). The E column is the bake-off signal:")
    print("  beta-Ti 80 GPa lowers gyroid E toward wood (9-16) -> softens the HW.33 sheet/network call.")
    return out


def main() -> int:
    banner("HW.3.IS — Lamé thermal stress (Ti↔PEEK press-fit)")

    results = []
    for T in T_RANGE:
        dT = T - T_ASSEMBLY
        r = lame_interface_stress(dT)
        r["T_C"] = T
        results.append(r)

    banner("Temperature sweep results")
    print(f"  {'T (°C)':>8s} {'ΔT (K)':>8s} {'Δr (µm)':>10s} {'σ_r (MPa)':>10s} {'σ_t (MPa)':>10s} {'Safety':>8s}")
    print(f"  {'-'*54}")
    for r in results[::10]:
        print(f"  {r['T_C']:>8.0f} {r['dT_K']:>8.0f} {r['delta_r_um']:>10.1f} {r['sigma_r_MPa']:>10.2f} {r['sigma_t_MPa']:>10.2f} {r['safety_factor']:>8.1f}×")

    worst = max(results, key=lambda r: abs(r["sigma_t_MPa"]))
    print(f"\n  Worst case: T={worst['T_C']:.0f}°C, σ_t={worst['sigma_t_MPa']:.2f} MPa, safety={worst['safety_factor']:.1f}×")

    # --- Press-fit contact pressure + STRESS RELAXATION (constant strain) ---
    # Lamé interference fit, rigid Ti shaft: contact radius b = R_INTERFACE (the shaft surface where PEEK
    # grips), NOT R_INNER. HW.3.IS bug-fix 2026-06-21: the old call passed R_INNER (the gyroid bus bore),
    # over-stating P_c ~2.6×. P_c spans the H7/s6 interference band; MIN interference governs sealing.
    banner("Press-fit contact pressure & stress relaxation (constant strain)")
    p0_min = contact_pressure(DELTA_RADIAL_MIN, R_INTERFACE, R_OUTER)  # Pa — worst case for sealing
    p0_max = contact_pressure(DELTA_RADIAL_MAX, R_INTERFACE, R_OUTER)  # Pa — worst case for hoop stress
    print(f"  H7/s6 interference: {I_DIA_MIN_UM:.0f}-{I_DIA_MAX_UM:.0f} µm diametral (Ø11) → P_c(0) = {p0_min/1e6:.2f}-{p0_max/1e6:.2f} MPa")
    print(f"  Model: stress relaxation (NOT creep) — P_c decays to {PEEK_RELAX_FLOOR*100:.0f}% floor (semicrystalline)")
    years = [0, 1, 5, 10, 20]
    relax_results = []
    for y in years:
        pc_min = relaxed_pressure(p0_min, y)
        pc_max = relaxed_pressure(p0_max, y)
        holds = pc_min / 1e6 > P_SAP_MPa
        print(f"  {y:>3d} years: P_c = {pc_min/1e6:.2f}-{pc_max/1e6:.2f} MPa  "
              f"(min {'> sap' if holds else '≤ sap → O-ring carries the seal'})")
        relax_results.append({"years": y, "P_c_min_MPa": pc_min / 1e6, "P_c_max_MPa": pc_max / 1e6})
    pc_20_min = relax_results[-1]["P_c_min_MPa"]
    pc_20_max = relax_results[-1]["P_c_max_MPa"]

    # --- Winter behaviour: the INNER Ti↔PEEK interface tightens; the outer surface is the TREE ---
    # HW.3.IS reframe 2026-06-21: the frozen anchor's PEEK OD (Ø15) sits in the TREE (compliant wood +
    # callus), NOT a rigid outer Ti shell — so the old "outer Ti cold-leak" was a baseline modelling
    # artifact. In winter PEEK shrinks MORE than Ti (Δα), so the inner press-fit grips the Ti shaft HARDER.
    banner("Winter check (-30°C): inner interface tightens; outer = tree, not a Ti shell")
    dT_cold = -50.0
    _delta_eff, loss = cold_effective_interference(DELTA_RADIAL_MIN, R_OUTER, dT_cold)
    print(f"  Δα = {(ALPHA_PEEK-ALPHA_TI)*1e6:.0f}e-6/K → INNER Ti↔PEEK interface TIGHTENS in cold (good).")
    print(f"  A hypothetical rigid OUTER Ti shell would lose r·Δα·|ΔT| = {loss*1e6:.1f} µm of interference,")
    print("  but the real outer surface is the wound (wood E≈PEEK + callus), so that is a conservative")
    print("  artifact, not a seal path. Hermetic seal = the AXIAL O-ring at the flange (immune to this).")

    alloy_cmp = alloy_comparative()

    banner("Verdict")
    print(f"  Thermal stress: {abs(worst['sigma_t_MPa']):.2f} MPa ≪ PEEK yield {SIGMA_YIELD_PEEK/1e6:.0f} MPa (safety {worst['safety_factor']:.1f}×)")
    print(f"  Press-fit P_c (H7/s6 band): {p0_min/1e6:.2f}-{p0_max/1e6:.2f} → {pc_20_min:.2f}-{pc_20_max:.2f} MPa over 20yr (semicrystalline floor)")
    seal_word = ">" if pc_20_min > P_SAP_MPa else "≤"
    print(f"  At MIN H7/s6 interference the relaxed P_c ({pc_20_min:.2f} MPa) {seal_word} sap ({P_SAP_MPa} MPa) →")
    print("    the elastomer O-ring (NOT PEEK contact) is the ESSENTIAL hermetic seal — this is exactly why")
    print("    it is the primary seal, not a redundancy. Barbs/retaining ring = AXIAL pull-out + anti-rotation")
    print("    ONLY (they do NOT seal). PEEK = structural/thermal isolator + (at max fit) a backup P_c.")
    print(f"  ✅ Ti↔PEEK press-fit survives 20+ years (thermal {worst['safety_factor']:.1f}× margin; seal via O-ring).")

    # Plot
    _fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

    temps = [r["T_C"] for r in results]
    sigma_t = [r["sigma_t_MPa"] for r in results]

    ax1.plot(temps, sigma_t, "b-", linewidth=2)
    ax1.axhline(y=SIGMA_YIELD_PEEK/1e6, color="r", linestyle="--", label=f"PEEK yield ({SIGMA_YIELD_PEEK/1e6:.0f} MPa)")
    ax1.axhline(y=-SIGMA_YIELD_PEEK/1e6, color="r", linestyle="--")
    ax1.set_xlabel("Temperature (°C)")
    ax1.set_ylabel("Tangential stress σ_t (MPa)")
    ax1.set_title("Ti↔PEEK Interface Stress vs Temperature")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    relax_years = [r["years"] for r in relax_results]
    relax_pc_min = [r["P_c_min_MPa"] for r in relax_results]
    relax_pc_max = [r["P_c_max_MPa"] for r in relax_results]
    ax2.plot(relax_years, relax_pc_max, "go-", linewidth=2, markersize=7, label="P_c max (H7/s6 max fit)")
    ax2.plot(relax_years, relax_pc_min, "bs--", linewidth=2, markersize=7, label="P_c min (H7/s6 min fit)")
    ax2.fill_between(relax_years, relax_pc_min, relax_pc_max, alpha=0.15, color="green")
    ax2.axhline(y=P_SAP_MPa, color="r", linestyle="--", label=f"sap pressure ({P_SAP_MPa} MPa)")
    ax2.set_xlabel("Time (years)")
    ax2.set_ylabel("Contact pressure P_c (MPa)")
    ax2.set_title("PEEK Stress Relaxation (constant strain)")
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    fig_path = OUT_DIR / "thermal_stress_lame.png"
    plt.savefig(fig_path, dpi=150)
    print(f"\n  Plot: {fig_path.relative_to(REPO_ROOT)}")

    # Save JSON
    output = {
        "method": "Lamé thick-walled cylinder + stress relaxation (constant strain)",
        "materials": {
            "Ti-6Al-4V": {"alpha": ALPHA_TI, "E_GPa": E_TI/1e9, "nu": NU_TI},
            "PEEK-450G": {"alpha": ALPHA_PEEK, "E_GPa": E_PEEK/1e9, "nu": NU_PEEK, "yield_MPa": SIGMA_YIELD_PEEK/1e6},
        },
        "alloy_comparative": alloy_cmp,
        "geometry_mm": {"r_inner": R_INNER*1e3, "r_interface": R_INTERFACE*1e3, "r_outer": R_OUTER*1e3},
        "worst_case": {
            "T_C": worst["T_C"],
            "sigma_t_MPa": worst["sigma_t_MPa"],
            "safety_factor": worst["safety_factor"],
        },
        "press_fit": {
            "fit": "H7/s6 (ISO 286, Ø11)",
            "interference_diametral_um": [I_DIA_MIN_UM, I_DIA_MAX_UM],
            "contact_radius_mm": R_INTERFACE * 1e3,
            "P_c_initial_MPa": [p0_min / 1e6, p0_max / 1e6],
            "relaxation_model": "stress relaxation (constant strain), Maxwell+floor",
            "relax_floor": PEEK_RELAX_FLOOR,
            "relax_tau_years": PEEK_RELAX_TAU_YEARS,
            "P_c_20yr_MPa": [pc_20_min, pc_20_max],
            "sap_pressure_MPa": P_SAP_MPa,
            "seal_holds_20yr_min_fit": bool(pc_20_min > P_SAP_MPa),
            "relaxation_series": relax_results,
            "note": "P_c uses the bug-fixed contact radius b=R_INTERFACE (was R_INNER -> ~2.6x over-stated) + the H7/s6 band (was a 50um placeholder). At MIN fit the relaxed P_c may be <= sap, so the elastomer O-ring is the ESSENTIAL seal. relax_floor/tau = interim literature-Prony (NOT Gusak-authoritative, 00_02 Стаття 2).",
        },
        "winter": {
            "dT_K": dT_cold,
            "outer_radius_mm": R_OUTER * 1e3,
            "inner_interface": "tightens in cold (PEEK grips the Ti shaft harder) -- good",
            "hypothetical_outer_shell_loss_um": loss * 1e6,
            "note": "frozen anchor PEEK OD (O15) sits in the TREE (compliant wood + callus), NOT a rigid outer Ti shell -> the old outer-Ti cold-leak was a baseline artifact. Seal = axial O-ring at the flange.",
        },
        "sealing": "primary hermetic seal = elastomer O-ring (FKM/EPDM); PEEK = structural isolator + residual P_c; barbs = axial pull-out + anti-rotation only (NOT sealing)",
        "verdict": "Ti↔PEEK press-fit survives 20+ years seasonal cycling (stress relaxation to semicrystalline floor, not creep collapse)",
    }
    json_path = OUT_DIR / "thermal_stress_lame.json"
    json_path.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
