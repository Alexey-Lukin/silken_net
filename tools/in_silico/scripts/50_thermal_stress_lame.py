#!/usr/bin/env python
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
fit from школа Гусака (08_01 Стаття 2).
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
from lib.constants import KINETICS_DIR, REPO_ROOT
from lib.utils import banner

OUT_DIR = KINETICS_DIR
OUT_DIR.mkdir(parents=True, exist_ok=True)

# Material properties
ALPHA_TI = 8.6e-6       # 1/K — Ti-6Al-4V CTE
ALPHA_PEEK = 47e-6       # 1/K — PEEK 450G CTE
E_TI = 110e9             # Pa — Young's modulus Ti-6Al-4V
E_PEEK = 3.6e9           # Pa — Young's modulus PEEK 450G
NU_TI = 0.33             # Poisson's ratio Ti
NU_PEEK = 0.40           # Poisson's ratio PEEK
SIGMA_YIELD_PEEK = 100e6 # Pa — PEEK yield stress
SIGMA_YIELD_TI = 880e6   # Pa — Ti-6Al-4V yield

# Geometry (coaxial: Zone 1 Ti inner → Zone 2 PEEK → Zone 3 Ti outer)
R_INNER = 3.0e-3         # m — Ti gyroid inner radius
R_INTERFACE = 5.0e-3     # m — Ti↔PEEK interface
R_OUTER = 8.0e-3         # m — outer Ti flange radius

# Environment
T_ASSEMBLY = 20.0        # °C — assembly temperature
T_RANGE = np.linspace(-30, 40, 71)  # °C sweep

# Press-fit interference (radial) and sealing requirement
DELTA_INTERFERENCE = 50e-6   # m — radial press-fit interference (~50 µm)
P_SAP_MPa = 0.5              # MPa — conservative xylem positive/capillary sap pressure (seal must exceed)

# PEEK stress relaxation under CONSTANT STRAIN (press-fit), NOT creep.
# Semicrystalline PEEK retains a substantial relaxed (equilibrium) modulus —
# the crystalline phase forms a permanent elastic network, so stress relaxes
# toward a floor E_∞, NOT to zero. Single-Maxwell + floor (≈ 2-term Prony):
#   P_c(t) = P_c(0) · [ E∞/E0 + (1 − E∞/E0)·exp(−t/τ) ]
# These two numbers are literature-grounded ESTIMATES; school of Gusak to
# supply the proper Prony series (Maxwell-Wiechert) fit (08_01 Стаття 2).
PEEK_RELAX_FLOOR = 0.65      # E_∞/E_0 — fraction of modulus retained at equilibrium
PEEK_RELAX_TAU_YEARS = 1.0   # relaxation time constant (years)


def lame_interface_stress(dT: float) -> dict:
    """Compute interface stress from differential thermal expansion."""
    d_alpha = ALPHA_PEEK - ALPHA_TI
    delta_r = d_alpha * dT * R_INTERFACE

    # Simplified thick-wall: PEEK sleeve under internal (Ti) expansion
    k = R_OUTER / R_INTERFACE
    sigma_r = E_PEEK * abs(delta_r) / R_INTERFACE / (k**2 - 1)
    sigma_t = sigma_r * (k**2 + 1) / (k**2 - 1)

    if dT < 0:
        sigma_r = -sigma_r
        sigma_t = -sigma_t

    return {
        "dT_K": dT,
        "delta_r_um": delta_r * 1e6,
        "sigma_r_MPa": sigma_r / 1e6,
        "sigma_t_MPa": sigma_t / 1e6,
        "safety_factor": SIGMA_YIELD_PEEK / max(abs(sigma_t), 1),
    }


def contact_pressure(delta: float, b: float, c: float) -> float:
    """Initial press-fit contact pressure: PEEK hub (b→c) on rigid Ti shaft.
    Lamé interference fit, rigid inner member (E_Ti ≫ E_PEEK)."""
    geom = (c**2 + b**2) / (c**2 - b**2) + NU_PEEK
    return E_PEEK * delta / (b * geom)        # Pa


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
    banner("Press-fit contact pressure & stress relaxation (constant strain)")
    p0 = contact_pressure(DELTA_INTERFERENCE, R_INNER, R_OUTER)  # Pa
    print(f"  Initial interference: {DELTA_INTERFERENCE*1e6:.0f} µm → P_c(0) = {p0/1e6:.1f} MPa")
    print(f"  Model: stress relaxation (NOT creep) — P_c decays to {PEEK_RELAX_FLOOR*100:.0f}% floor (semicrystalline)")
    years = [0, 1, 5, 10, 20]
    relax_results = []
    for y in years:
        pc = relaxed_pressure(p0, y)
        print(f"  {y:>3d} years: P_c = {pc/1e6:.1f} MPa  ({'seal holds' if pc/1e6 > P_SAP_MPa else 'SEAL LOST'} vs sap {P_SAP_MPa} MPa)")
        relax_results.append({"years": y, "P_c_MPa": pc / 1e6})
    pc_20 = relax_results[-1]["P_c_MPa"]

    # --- Winter cold-leak at the OUTER interface ---
    banner("Winter cold-leak check (OUTER interface, -30°C)")
    dT_cold = -50.0
    delta_eff, loss = cold_effective_interference(DELTA_INTERFERENCE, R_OUTER, dT_cold)
    print(f"  At ΔT={dT_cold:.0f} K, outer r={R_OUTER*1e3:.0f} mm:")
    print(f"    interference loss = r·(α_PEEK−α_Ti)·|ΔT| = {loss*1e6:.1f} µm")
    print(f"    effective interference = {DELTA_INTERFERENCE*1e6:.0f} − {loss*1e6:.1f} = {delta_eff*1e6:.1f} µm")
    print("  Inner interface TIGHTENS in cold (PEEK grips Ti shaft); OUTER is the weak link.")
    cold_ok = delta_eff > 0
    print(f"  {'✅ outer interface survives winter' if cold_ok else '❌ outer interface opens in winter'} "
          f"({delta_eff*1e6:.0f} µm residual)")

    banner("Verdict")
    print(f"  Thermal stress: {abs(worst['sigma_t_MPa']):.2f} MPa ≪ PEEK yield {SIGMA_YIELD_PEEK/1e6:.0f} MPa (safety {worst['safety_factor']:.0f}×)")
    print(f"  Stress relaxation: P_c {p0/1e6:.1f} → {pc_20:.1f} MPa over 20yr (NOT zero — semicrystalline floor)")
    print(f"  Winter outer interface: {delta_eff*1e6:.0f} µm residual interference (survives)")
    print(f"  Sealing: residual P_c {pc_20:.1f} MPa > sap {P_SAP_MPa} MPa, BUT primary hermetic seal = elastomer O-ring")
    print("           (FKM/EPDM, rubber-elastic → immune to PEEK relaxation). Barbs/retaining ring")
    print("           handle AXIAL pull-out + anti-rotation ONLY (they do NOT seal).")
    print("  ✅ Ti↔PEEK press-fit survives 20+ years; PEEK = structural isolator + backup P_c")

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
    relax_pc = [r["P_c_MPa"] for r in relax_results]
    ax2.plot(relax_years, relax_pc, "go-", linewidth=2, markersize=8, label="P_c(t)")
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
        "geometry_mm": {"r_inner": R_INNER*1e3, "r_interface": R_INTERFACE*1e3, "r_outer": R_OUTER*1e3},
        "worst_case": {
            "T_C": worst["T_C"],
            "sigma_t_MPa": worst["sigma_t_MPa"],
            "safety_factor": worst["safety_factor"],
        },
        "press_fit": {
            "interference_um": DELTA_INTERFERENCE * 1e6,
            "P_c_initial_MPa": p0 / 1e6,
            "relaxation_model": "stress relaxation (constant strain), Maxwell+floor",
            "relax_floor": PEEK_RELAX_FLOOR,
            "relax_tau_years": PEEK_RELAX_TAU_YEARS,
            "P_c_20yr_MPa": pc_20,
            "sap_pressure_MPa": P_SAP_MPa,
            "seal_holds_20yr": bool(pc_20 > P_SAP_MPa),
            "relaxation_series": relax_results,
            "note": "relax_floor/tau are literature-grounded estimates; Prony fit pending (Gusak, 08_01 Стаття 2)",
        },
        "winter_cold_leak": {
            "dT_K": dT_cold,
            "outer_radius_mm": R_OUTER * 1e3,
            "interference_loss_um": loss * 1e6,
            "effective_interference_um": delta_eff * 1e6,
            "outer_survives_winter": bool(cold_ok),
            "note": "OUTER interface is the winter weak link (PEEK shrinks from outer Ti shell); inner tightens",
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
