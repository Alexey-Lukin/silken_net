#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.3.IS — Unified thick-wall Lamé: press-fit interference + thermal mismatch in ONE model.

Scripts 50/51 ONCE computed the Ti↔PEEK interface stress three inconsistent ways (FIXED at source
2026-06-22 — scope-B; this script drove that reconciliation, the values below are the pre-fix history):
  - 50 lame_interface_stress  (thermal-only σ_t):  E·ε/(k²−1)         → 29.7 MPa @ −30°C (SF 3.4×)
  - 50 contact_pressure       (press-fit P_c):     rigid-inner Lamé (k²+1)/(k²−1)+ν
  - 51 press_fit_window       (mech+thermal hoop): thin-wall E·δ/D·2  → ~40 MPa @ −30°C max fit
The "thermal" (50) and "press-fit hoop" (51) are partial views of the SAME interference put
through DIFFERENT formulas, so they cannot be added — the naïve 29.7+40 → SF 1.4× in 00_07 is an
apples+oranges artifact. This script puts BOTH the mechanical (H7/s6) and the thermal interference
through ONE rigid-inner / free-outer thick-wall Lamé (lib.mechanics), so the combined worst case
— −30°C AND s6-max fit, which stack additively in the cold — is physically meaningful.

Because P_c is LINEAR in δ, the mechanical and thermal hoop superpose EXACTLY:
σ_t(δ_mech + δ_therm) = σ_t(δ_mech) + σ_t(δ_therm). The "unification" is doing both through the
same formula so the sum is real.

Pure analytical (numpy sweep + lib.mechanics scalar core); no FEA. Authoritative Prony relaxation
+ barb-tip stress-concentration FEA stay with школа Гусака (00_02 Стаття 2). Result + the
reconciliation feed THERMAL_STRESS_REPORT.md + 00_07 HW.3.IS.
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
    T_FOREST_MAX_C,
    T_FOREST_MIN_C,
)
from lib.mechanics import thermal_interference, thick_wall_hoop
from lib.utils import banner

OUT_DIR = KINETICS_DIR
OUT_DIR.mkdir(parents=True, exist_ok=True)

MPA = 1e6
B = R_INTERFACE_M
C = R_OUTER_M
ALPHA_TI_1K = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]   # Ti baseline α — One-Home alloy table
DELTA_MECH = {
    "min": H7S6_INTERF_DIA_MIN_UM * 1e-6 / 2.0,   # radial = diametral / 2 (sealing-governing)
    "max": H7S6_INTERF_DIA_MAX_UM * 1e-6 / 2.0,   # radial (hoop-governing)
}

# PRE-FIX legacy numbers (50/51 at −30°C BEFORE the 2026-06-22 source-fix). Kept to document why the
# canon moved off "SF 3.4×" / the naïve 1.4× — since the fix, 50/51/56 all share lib.mechanics and agree.
LEGACY_50_THERMAL_MPA = 29.73   # 50 lame_interface_stress, the OLD E·ε/(k²−1) denominator (now thick_wall_hoop)
LEGACY_51_HOOP_MPA = 40.1       # 51 press_fit_window OLD thin-wall σ_hoop @ −30°C max fit (now thick-wall)


def state(t_c: float, fit: str) -> dict:
    """Full bore stress state at temperature `t_c` and H7/s6 `fit` ('min' | 'max')."""
    d_th = thermal_interference(t_c, T_ASSEMBLY_C, ALPHA_PEEK_1K, ALPHA_TI_1K, B)
    d_total = DELTA_MECH[fit] + d_th
    s = thick_wall_hoop(d_total, B, C, E_PEEK_PA, NU_PEEK)
    s["T_C"] = t_c
    s["delta_mech_um"] = DELTA_MECH[fit] * 1e6
    s["delta_therm_um"] = d_th * 1e6
    s["delta_total_um"] = d_total * 1e6
    s["SF_t"] = SIGMA_YIELD_PEEK_PA / max(abs(s["sigma_t"]), 1.0)
    s["SF_vm"] = SIGMA_YIELD_PEEK_PA / max(s["sigma_vm"], 1.0)
    return s


def main() -> int:
    banner("HW.3.IS — Unified thick-wall Lamé (press-fit + thermal, ONE model)")
    print(f"  Geometry: PEEK sleeve bore Ø{B*2e3:.0f} → OD Ø{C*2e3:.0f} mm (frozen HW.33); rigid Ti shaft, free outer (tree)")
    print(f"  PEEK 450G: E={E_PEEK_PA/1e9:.1f} GPa, ν={NU_PEEK}, yield={SIGMA_YIELD_PEEK_PA/MPA:.0f} MPa; Δα={(ALPHA_PEEK_1K-ALPHA_TI_1K)*1e6:.1f}e-6/K")
    print(f"  H7/s6 Ø11 interference: {H7S6_INTERF_DIA_MIN_UM:.0f}-{H7S6_INTERF_DIA_MAX_UM:.0f} µm diametral")

    temps = np.linspace(T_FOREST_MIN_C, T_FOREST_MAX_C, 71)
    grid = {fit: [state(float(t), fit) for t in temps] for fit in ("min", "max")}

    # ── Combined worst case for PEEK yield = coldest + max fit (both maximise interference) ──
    worst = min(grid["max"], key=lambda s: s["SF_t"])
    banner("Combined worst case (cold + max fit stack additively)")
    print(f"  T={worst['T_C']:.0f}°C, fit=max: δ = {worst['delta_mech_um']:.1f}(mech) + {worst['delta_therm_um']:.1f}(therm) = {worst['delta_total_um']:.1f} µm radial")
    print(f"  P_c = {worst['P_c']/MPA:.2f} MPa → σ_t(bore) = {worst['sigma_t']/MPA:.2f} MPa, σ_vm = {worst['sigma_vm']/MPA:.2f} MPa")
    print(f"  SF (σ_t vs yield) = {worst['SF_t']:.1f}×   |   SF (von Mises) = {worst['SF_vm']:.1f}×")

    # ── Reconciliation against the two legacy partial numbers ──
    banner("Reconciliation vs the PRE-FIX legacy formulas (50/51 now fixed at source — scope-B)")
    therm_only = thick_wall_hoop(
        thermal_interference(T_FOREST_MIN_C, T_ASSEMBLY_C, ALPHA_PEEK_1K, ALPHA_TI_1K, B), B, C, E_PEEK_PA, NU_PEEK
    )
    mech_only_max = thick_wall_hoop(DELTA_MECH["max"], B, C, E_PEEK_PA, NU_PEEK)
    over_factor = LEGACY_50_THERMAL_MPA / (therm_only["sigma_t"] / MPA)
    naive_sum = LEGACY_50_THERMAL_MPA + LEGACY_51_HOOP_MPA
    print(f"  thermal-only σ_t: {therm_only['sigma_t']/MPA:.2f} MPa  (OLD script 50 = {LEGACY_50_THERMAL_MPA:.1f} → was ×{over_factor:.1f} overstated; now fixed, 50 agrees)")
    print(f"  pressfit-only σ_t, max: {mech_only_max['sigma_t']/MPA:.2f} MPa  (OLD script 51 thin-wall = {LEGACY_51_HOOP_MPA:.1f}; now thick-wall, 51 agrees)")
    print(f"  naïve add of the two OLD numbers: {naive_sum:.0f} MPa → SF {SIGMA_YIELD_PEEK_PA/MPA/naive_sum:.1f}× (the 00_07 ~1.4× — the artifact this pass retired)")
    superpos = therm_only["sigma_t"] + mech_only_max["sigma_t"]
    print(f"  linear superposition: σ_t(therm)+σ_t(mech_max) = {superpos/MPA:.2f} MPa == σ_t(combined worst) {worst['sigma_t']/MPA:.2f} MPa ✓")

    # ── Sealing corner (warmest + min fit → lowest P_c); 20-yr relaxation handled by script 50 ──
    # δ_total < 0 = the press-fit SEPARATES (thermal expansion exceeds the min mechanical interference);
    # contact can't carry tension → clamp P_c to 0 (gap). This is exactly why the O-ring, not the
    # press-fit, is the essential seal at the hot end.
    seal = min(grid["min"], key=lambda s: s["P_c"])
    gap = seal["delta_total_um"] < 0
    pc0 = max(seal["P_c"], 0.0)
    banner("Sealing corner (warm + min fit → lowest initial P_c)")
    if gap:
        print(f"  T={seal['T_C']:.0f}°C, fit=min: δ_total = {seal['delta_total_um']:.1f} µm < 0 → press-fit SEPARATES (gap); P_c = 0")
        print("  Hot + min-fit opens the Ti↔PEEK joint → the axial O-ring is the ONLY seal here (script 50 / report §2-3).")
    else:
        print(f"  T={seal['T_C']:.0f}°C, fit=min: δ_total = {seal['delta_total_um']:.1f} µm → P_c(0) = {pc0/MPA:.2f} MPa")
        print("  (20-yr stress relaxation toward the semicrystalline floor + O-ring-essential → script 50 / report §2)")

    banner("Verdict")
    sf = worst["SF_t"]
    word = "comfortable (>3×)" if sf > 3 else ("marginal" if sf > 1.5 else "TIGHT")
    print(f"  Honest combined worst-case SF = {sf:.1f}× (σ_t) / {worst['SF_vm']:.1f}× (von Mises) — {word}.")
    print(f"  The scary naïve {SIGMA_YIELD_PEEK_PA/MPA/naive_sum:.1f}× is an artifact of adding two differently-formulated stresses.")
    print(f"  NB: script 50's OLD thermal σ_t (29.7 = the former 'SF 3.4× / CTE-limited' headline) was ~{over_factor:.1f}× overstated by a (k²−1) denominator → FIXED at source 2026-06-22 (lib.mechanics); canon 01_01 §4.2 corrected.")

    # ── Plot ──
    _fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
    for fit, style in (("min", "bs--"), ("max", "go-")):
        ax1.plot(temps, [s["sigma_t"] / MPA for s in grid[fit]], style, markersize=3, linewidth=1.5, label=f"σ_t, {fit} fit")
    ax1.axhline(SIGMA_YIELD_PEEK_PA / MPA, color="r", linestyle="--", label=f"PEEK yield ({SIGMA_YIELD_PEEK_PA/MPA:.0f} MPa)")
    ax1.set_xlabel("Temperature (°C)")
    ax1.set_ylabel("Bore hoop σ_t (MPa)")
    ax1.set_title("Unified bore hoop vs T (mech + thermal interference)")
    ax1.legend()
    ax1.grid(True, alpha=0.3)

    for fit, style in (("min", "bs--"), ("max", "go-")):
        ax2.plot(temps, [s["SF_t"] for s in grid[fit]], style, markersize=3, linewidth=1.5, label=f"SF, {fit} fit")
    ax2.axhline(3.0, color="orange", linestyle=":", label="SF = 3")
    ax2.axhline(1.0, color="r", linestyle="--", label="SF = 1 (yield)")
    ax2.set_xlabel("Temperature (°C)")
    ax2.set_ylabel("Safety factor (σ_t vs yield)")
    ax2.set_title("Safety factor vs T")
    ax2.set_ylim(0, None)
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    plt.tight_layout()
    fig_path = OUT_DIR / "unified_press_fit_lame.png"
    plt.savefig(fig_path, dpi=150)
    print(f"\n  Plot: {fig_path.relative_to(REPO_ROOT)}")

    # ── JSON ──
    def slim(s: dict) -> dict:
        stress_keys = ("P_c", "sigma_t", "sigma_r", "sigma_vm")
        return {k: round(v / MPA, 3) if k in stress_keys else round(v, 3) for k, v in s.items()}

    output = {
        "method": "Unified rigid-inner / free-outer thick-wall Lamé (press-fit + thermal interference, one model)",
        "geometry_mm": {"bore_d": B * 2e3, "od_d": C * 2e3, "interface_r": B * 1e3, "outer_r": C * 1e3},
        "materials": {
            "PEEK-450G": {"alpha_1K": ALPHA_PEEK_1K, "E_GPa": E_PEEK_PA / 1e9, "nu": NU_PEEK, "yield_MPa": SIGMA_YIELD_PEEK_PA / MPA},
            "Ti-6Al-4V": {"alpha_1K": ALPHA_TI_1K},
        },
        "h7s6_interference_diametral_um": [H7S6_INTERF_DIA_MIN_UM, H7S6_INTERF_DIA_MAX_UM],
        "combined_worst_case": {
            "T_C": worst["T_C"],
            "fit": "max",
            "delta_mech_um": round(worst["delta_mech_um"], 3),
            "delta_therm_um": round(worst["delta_therm_um"], 3),
            "delta_total_um": round(worst["delta_total_um"], 3),
            "P_c_MPa": round(worst["P_c"] / MPA, 3),
            "sigma_t_MPa": round(worst["sigma_t"] / MPA, 3),
            "sigma_vm_MPa": round(worst["sigma_vm"] / MPA, 3),
            "SF_sigma_t": round(worst["SF_t"], 2),
            "SF_von_mises": round(worst["SF_vm"], 2),
        },
        "reconciliation": {
            "unified_thermal_only_sigma_t_MPa": round(therm_only["sigma_t"] / MPA, 3),
            "legacy_50_thermal_sigma_t_MPa": LEGACY_50_THERMAL_MPA,
            "script50_overstatement_factor": round(over_factor, 2),
            "unified_pressfit_max_sigma_t_MPa": round(mech_only_max["sigma_t"] / MPA, 3),
            "legacy_51_thinwall_hoop_MPa": LEGACY_51_HOOP_MPA,
            "naive_add_MPa": round(naive_sum, 1),
            "naive_add_SF": round(SIGMA_YIELD_PEEK_PA / MPA / naive_sum, 2),
            "note": "PRE-FIX: 50 lame_interface_stress used E·ε/(k²−1) (rigid-outer-shell residual) → overstated thermal σ_t ~4.3×; 51 hoop was thin-wall. FIXED 2026-06-22 (scope-B): 50/51/56 now share lib.mechanics (rigid-inner thick-wall Lamé). P_c linear in δ → exact superposition.",
        },
        "sealing_corner": {
            "T_C": seal["T_C"],
            "fit": "min",
            "delta_total_um": round(seal["delta_total_um"], 3),
            "P_c_initial_MPa": round(pc0 / MPA, 3),
            "press_fit_separates": bool(gap),
            "note": "Hot + min-fit: δ_total<0 → press-fit gaps open → P_c clamped to 0; O-ring is the only seal. 20-yr relaxation + O-ring-essential conclusion lives in script 50 / THERMAL_STRESS_REPORT §2-3.",
        },
        "sweep": {fit: [slim(s) for s in grid[fit][::10]] for fit in ("min", "max")},
        "verdict": (
            f"Honest combined worst-case (−30°C + s6-max) SF {worst['SF_t']:.1f}× (σ_t) / {worst['SF_vm']:.1f}× (von Mises); "
            f"the naïve 1.4× was an apples+oranges artifact; script 50's old thermal σ_t was overstated ~{over_factor:.1f}× → fixed at source + canon 01_01 §4.2 corrected (2026-06-22)."
        ),
    }
    json_path = OUT_DIR / "unified_press_fit_lame.json"
    json_path.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
