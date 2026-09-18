#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L4 — EBFC kinetics: predict delta_t (supercapacitor charge time) from
glucose concentration and temperature.

Physical model
--------------
    glucose diffusion (Fick) → Michaelis-Menten (dgrFAD-GDH)
    → electron current (Os-mediated) → BQ25570 boost → EDLC charge → delta_t

This closes the final level of the 4-level Zero-Lab pipeline (01_03 §3.4).
The output delta_t is the EBFC recharge time that, per [E.63], now drives
growth_points DIRECTLY (bio_contract.rb metabolic_health) — NOT β-perturbation,
which was reversed as economically null/inverted (00_07 E.63 / 03_04 §4.3).

Key literature parameters
-------------------------
  j_max(25°C) = 881 µA/cm²    — Michaelis-Menten ASYMPTOTE of dgrGcGDH + Os-polymer: derived from
                                Zafar 2012 (PMC3275720) Table 1 row dgrGcGDH (K_M^app 13.9 mM) and
                                its 520 µA/cm² at 20 mM. A LAB CEILING — pH 7.4 phosphate, graphite,
                                flow; the pH correction toward sap is NOT applied (lib/constants.py)
  Km = 13.9 mM                — K_M^app of that same row and the same fit, so the pair moves together.
                                Apparent: it carries the hydrogel's mass-transfer resistance
  V_op = 0.5 V                — EBFC under load (OCV 0.6-0.8 V, 01_03 §1)
  η_bq = 0.68                 — BQ25570 boost efficiency @ P_EBFC≈15µW (docs/02_03 §9.1
                                 table is source of truth; TI SLUSBH2G gives no closed-form
                                 η(P_IN) — see constants.py ETA_BQ comment, [HW.47] 2026-09-09)
  A = 2.0 cm²                 — ONE face of the Ø16×1 mm Ti-coin COUPON (01_01 §6), see
                                 the WHICH BODY note below; constants.py A_ELECTRODE
  E_cycle = 5 mJ              — STM32WLE5JC per wake cycle (sense + LoRa TX)
  Ea = 40 kJ/mol              — Arrhenius activation energy (FAD enzyme typical)
  D_eff = 2e-6 cm²/s          — glucose through chitosan hydrogel matrix
  δ = 20 µm                   — membrane + hydrogel thickness (01_03 §2.1)

WHICH BODY these delta_t belong to
----------------------------------
Every absolute delta_t printed here is a **Ti-coin coupon** prediction, and that is what
it is for: the Stage-2 in-vitro coin is the body this model is meant to be compared
against (01_01 §6). It is NOT the anchor. The Zone-1 gyroid anode is a different body by
30-60× — CAD `SpecificSurface` puts it at 65-123 cm² against the coupon's 2.0 — and the
scaling is not a rounding error: this model is KINETICS-limited across its whole range
(j_kinetic 233-520 vs j_diffusion 965-3859 µA/cm² at 5-20 mM), so area passes into current
without saturating and delta_t ∝ 1/A EXACTLY (A=1→39.9 s, 2→19.9, 3→13.3, 5→8.0 at 10 mM, 25°C).
⚠️ Both rows move with J_MAX_25C — re-read them from the run, never from this docstring.

So do not read a number from here as the anchor's recharge interval, and do not feed one
into the DELTA_T_FAST_S / DELTA_T_SLOW_S calibration — those are per-deployment and wait
on a measured recharge curve (00_07 E.63, HW.13). Anchor-scale delta_t is not computed by
this model at all. [E.63, 2026-09-11]

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/30_kinetics_delta_t.py
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
    BASELINE_DELTA_T_S,
    D_EFF_GLUCOSE,
    DELTA_MEMBRANE,
    E_CYCLE,
    EA_ENZYME,
    ETA_BQ,
    F_CONST,
    J_MAX_25C,
    KINETICS_DIR,
    KM_GLUCOSE,
    N_ELECTRONS,
    PH_KINETICS_SYGMUND,
    R_GAS,
    REPO_ROOT,
    TEMPERATURE_K,
    V_OP,
)

T_REF = TEMPERATURE_K
D_EFF = D_EFF_GLUCOSE
from lib.utils import banner

OUT_DIR = KINETICS_DIR
OUT_DIR.mkdir(parents=True, exist_ok=True)

GLUCOSE_RANGE_MM = np.linspace(1, 30, 60)       # mM
TEMP_RANGE_C = np.linspace(-10, 40, 51)          # °C


def j_max_at_temp(temp_c: float) -> float:
    """Temperature-corrected j_max via Arrhenius."""
    temp_k = temp_c + 273.15
    return J_MAX_25C * np.exp(-EA_ENZYME / R_GAS * (1.0 / temp_k - 1.0 / T_REF))


def j_diffusion_limit(glucose_mm: float) -> float:
    """Diffusion-limited current density (Fick's first law, steady state)."""
    glucose_mol_cm3 = glucose_mm * 1e-6  # mM → mol/cm³
    return N_ELECTRONS * F_CONST * D_EFF * glucose_mol_cm3 / DELTA_MEMBRANE


def current_density(glucose_mm: float, temp_c: float) -> float:
    """Effective current density accounting for kinetics + diffusion."""
    j_kin = j_max_at_temp(temp_c) * glucose_mm / (KM_GLUCOSE + glucose_mm)
    j_diff = j_diffusion_limit(glucose_mm)
    return min(j_kin, j_diff)


def delta_t(glucose_mm: float, temp_c: float) -> float:
    """Predict EBFC charge time (seconds) for given conditions."""
    j = current_density(glucose_mm, temp_c)
    if j <= 0:
        return float("inf")
    p_ebfc = V_OP * j * A_ELECTRODE
    p_net = p_ebfc * ETA_BQ
    return E_CYCLE / p_net


def ph_ratio(glucose_mm: float, form: str) -> float:
    """Current ratio pH 5.5 / pH 7.5 at this glucose, from ONE enzyme form's own MM pair.

    The ratio is [S]-dependent because both k_cat and K_M move with pH, and they move in
    opposite directions for the current: k_cat falls, K_M falls too (higher affinity), so the
    two partly cancel. Reporting a single factor would hide that.
    """
    km_lo, kcat_lo = PH_KINETICS_SYGMUND[form][5.5]
    km_hi, kcat_hi = PH_KINETICS_SYGMUND[form][7.5]
    v_lo = kcat_lo * glucose_mm / (km_lo + glucose_mm)
    v_hi = kcat_hi * glucose_mm / (km_hi + glucose_mm)
    return v_lo / v_hi


def main() -> int:
    banner("L4 EBFC kinetics — delta_t prediction")
    print(f"  j_max(25°C) = {J_MAX_25C*1e6:.0f} µA/cm²")
    print(f"  Km = {KM_GLUCOSE:.1f} mM")
    print(f"  V_op = {V_OP} V, A = {A_ELECTRODE} cm²")
    print(f"  E_cycle = {E_CYCLE*1e3:.1f} mJ, η_BQ = {ETA_BQ}")
    print(f"  Ea = {EA_ENZYME/1000:.0f} kJ/mol")
    print(f"  D_eff = {D_EFF:.1e} cm²/s, δ = {DELTA_MEMBRANE*1e4:.0f} µm")

    # ── 1. Compute delta_t grid ──
    banner("Computing delta_t(glucose, temp) lookup table")
    grid = np.zeros((len(TEMP_RANGE_C), len(GLUCOSE_RANGE_MM)))
    for i, tc in enumerate(TEMP_RANGE_C):
        for k, glu in enumerate(GLUCOSE_RANGE_MM):
            grid[i, k] = delta_t(glu, tc)

    grid_clipped = np.clip(grid, 0, 600)  # cap at 10 min for visualization

    # ── 2. Validation: reference points ──
    banner("Validation against BASELINE_DELTA_T_S = 60 s")
    ref_points = [
        (10, 25, "healthy summer"),
        (5, 5, "cold winter / stress"),
        (20, 30, "active growth"),
        (3, 0, "severe stress"),
        (15, 20, "moderate spring"),
    ]
    print(f"  {'[glucose]':>10s}  {'T(°C)':>6s}  {'delta_t(s)':>10s}  {'vs 60s':>8s}  scenario")
    print("  " + "-" * 58)
    results_table = []
    for glu, tc, label in ref_points:
        dt = delta_t(glu, tc)
        status = "< baseline" if dt < BASELINE_DELTA_T_S else "> baseline"
        print(f"  {glu:>8.0f} mM  {tc:>5.0f}°C  {dt:>9.1f} s  {status:>8s}  {label}")
        results_table.append({
            "glucose_mM": glu, "temp_C": tc, "delta_t_s": round(dt, 1),
            "vs_baseline": status, "scenario": label,
        })

    # Check: at what glucose/temp does delta_t = 60s?
    banner("Iso-delta_t = 60s contour (baseline)")
    for tc in [5, 15, 25]:
        for glu in np.linspace(1, 30, 300):
            if delta_t(glu, tc) <= BASELINE_DELTA_T_S:
                print(f"  T={tc}°C: delta_t=60s at [glucose] ≈ {glu:.1f} mM")
                break
        else:
            print(f"  T={tc}°C: delta_t=60s NOT achievable in [1-30 mM] range")

    # ── 3. Diffusion limitation check ──
    banner("Diffusion limitation analysis")
    for glu in [5, 10, 20]:
        j_d = j_diffusion_limit(glu) * 1e6
        j_k = j_max_at_temp(25) * glu / (KM_GLUCOSE + glu) * 1e6
        limiting = "KINETICS" if j_k < j_d else "DIFFUSION"
        print(f"  [glucose]={glu} mM: j_kinetic={j_k:.0f} µA/cm², j_diffusion={j_d:.0f} µA/cm² → {limiting}")

    # ── 4. Sensitivity analysis ──
    banner("Sensitivity analysis (delta_t at 10 mM, 25°C)")
    sensitivities = {}

    for param, values, label in [
        ("Km", [10, 13.9, 20, 30, 50], "mM"),
        ("A_electrode", [1, 2, 3, 5], "cm²"),
        ("E_cycle", [2, 5, 10, 20], "mJ"),
        # 494 stays in the sweep on purpose: it is the density this model used to be anchored on
        # (native GcGDH at 20 mM), so the row prices what the re-anchoring moved (00_07 HW.5.IS).
        ("j_max", [200, 494, 881, 1200], "µA/cm²"),
    ]:
        sens = []
        for v in values:
            saved = globals()[{
                "Km": "KM_GLUCOSE", "A_electrode": "A_ELECTRODE",
                "E_cycle": "E_CYCLE", "j_max": "J_MAX_25C",
            }[param]]
            if param == "Km":
                globals()["KM_GLUCOSE"] = v
            elif param == "A_electrode":
                globals()["A_ELECTRODE"] = v
            elif param == "E_cycle":
                globals()["E_CYCLE"] = v * 1e-3
            elif param == "j_max":
                globals()["J_MAX_25C"] = v * 1e-6
            dt_v = delta_t(10, 25)
            sens.append({"value": v, "unit": label, "delta_t_s": round(dt_v, 1)})
            # restore
            if param == "Km":
                globals()["KM_GLUCOSE"] = saved
            elif param == "A_electrode":
                globals()["A_ELECTRODE"] = saved
            elif param == "E_cycle":
                globals()["E_CYCLE"] = saved
            elif param == "j_max":
                globals()["J_MAX_25C"] = saved
        sensitivities[param] = sens
        pairs = [(s["value"], str(s["delta_t_s"]) + "s") for s in sens]
        print(f"  {param}: {pairs}")

    # ── 4b. pH bracket (⚖️ 2026-09-18) — printed BESIDE the ceiling, never folded into it ──
    banner("pH bracket: the model runs at the pH-7.4 lab ceiling; sap is pH 5.75")
    ph_rows = []
    print(f"  {'scenario':<22s}  {'ceiling':>9s}  {'×wt':>6s}  {'×rec':>6s}  {'delta_t at pH 5.5':>20s}")
    print("  " + "-" * 72)
    for glu, tc, label in ref_points:
        dt_ceiling = delta_t(glu, tc)
        r_wt, r_rec = ph_ratio(glu, "wt"), ph_ratio(glu, "rec")
        dt_wt, dt_rec = dt_ceiling / r_wt, dt_ceiling / r_rec
        lo, hi = sorted((dt_wt, dt_rec))
        print(f"  {label:<22s}  {dt_ceiling:>8.1f}s  {r_wt:>6.2f}  {r_rec:>6.2f}  {lo:>9.1f}–{hi:.1f}s")
        ph_rows.append({
            "scenario": label, "glucose_mM": glu, "temp_C": tc,
            "delta_t_ceiling_s": round(dt_ceiling, 1),
            "ratio_wt": round(r_wt, 3), "ratio_rec": round(r_rec, 3),
            "delta_t_ph55_low_s": round(lo, 1), "delta_t_ph55_high_s": round(hi, 1),
        })
    print("  ⚠️  Source: Sygmund 2011 Table 3 — FREE enzyme, ferrocenium acceptor, 30 °C, pH 5.5 vs 7.5.")
    print("      Not our immobilised Os-polymer electrode, and the 30 °C measurement is applied at every")
    print("      temperature here, which assumes a temperature-independent pH effect nobody measured.")

    # ── 5. Heatmap ──
    banner("Generating delta_t heatmap")
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))

    # Heatmap
    ax = axes[0]
    im = ax.contourf(
        GLUCOSE_RANGE_MM, TEMP_RANGE_C, grid_clipped,
        levels=np.arange(0, 310, 10), cmap="RdYlGn_r",
    )
    cs = ax.contour(
        GLUCOSE_RANGE_MM, TEMP_RANGE_C, grid,
        levels=[BASELINE_DELTA_T_S], colors="white", linewidths=2,
    )
    ax.clabel(cs, fmt="60s baseline", fontsize=9)
    ax.set_xlabel("[glucose] (mM)")
    ax.set_ylabel("Temperature (°C)")
    ax.set_title("delta_t (seconds) — EBFC charge time")
    fig.colorbar(im, ax=ax, label="delta_t (s)")

    # Cross-sections
    ax2 = axes[1]
    for tc, color in [(5, "blue"), (15, "orange"), (25, "green")]:
        dts = [delta_t(g, tc) for g in GLUCOSE_RANGE_MM]
        ax2.plot(GLUCOSE_RANGE_MM, dts, color=color, linewidth=2, label=f"T={tc}°C")
    ax2.axhline(BASELINE_DELTA_T_S, color="red", linestyle="--", alpha=0.7, label="baseline 60s")
    ax2.set_xlabel("[glucose] (mM)")
    ax2.set_ylabel("delta_t (seconds)")
    ax2.set_title("delta_t vs glucose at different temperatures")
    ax2.set_ylim(0, 300)
    ax2.legend()
    ax2.grid(True, alpha=0.3)

    fig.tight_layout()
    fig_path = OUT_DIR / "delta_t_heatmap.png"
    fig.savefig(fig_path, dpi=140)
    print(f"  Wrote {fig_path.relative_to(REPO_ROOT)}")

    # ── 6. Save results ──
    banner("Saving results")
    lookup = {
        "model": "Michaelis-Menten + Arrhenius + BQ25570 boost + EDLC charge",
        "ph_bracket": {
            "source": "Sygmund 2011, Microb. Cell Fact. 10:106, Table 3 (doi:10.1186/1475-2859-10-106)",
            "measured": "free enzyme, ferrocenium 20 uM, 30 C, pH 5.5 vs 7.5 — NOT the immobilised Os electrode",
            "applies_to": "our sap setpoint pH 5.75 against the model's pH-7.4 ceiling",
            "ceiling_is_the_model": True,
            "rows": ph_rows,
        },
        "parameters": {
            "j_max_25C_uA_cm2": J_MAX_25C * 1e6,
            "Km_mM": KM_GLUCOSE,
            "V_op_V": V_OP,
            "A_electrode_cm2": A_ELECTRODE,
            "eta_BQ": ETA_BQ,
            "E_cycle_mJ": E_CYCLE * 1e3,
            "Ea_kJ_mol": EA_ENZYME / 1000,
            "D_eff_cm2_s": D_EFF,
            "delta_membrane_um": DELTA_MEMBRANE * 1e4,
            "BASELINE_DELTA_T_S": BASELINE_DELTA_T_S,
        },
        "reference_points": results_table,
        "sensitivity": sensitivities,
    }

    lookup_path = OUT_DIR / "delta_t_lookup.json"
    with lookup_path.open("w", encoding="utf-8") as fh:
        json.dump(lookup, fh, indent=2)
    print(f"  Wrote {lookup_path.relative_to(REPO_ROOT)}")

    # ── 7. Verdict [E.63] ──
    banner("L4 verdict [E.63 — see 00_07 E.63 / 03_04 §4.3]")
    dt_healthy = delta_t(10, 25)
    dt_stress = delta_t(5, 5)
    print(f"     Healthy (10 mM, 25°C): delta_t = {dt_healthy:.1f}s | Stressed (5 mM, 5°C): {dt_stress:.1f}s")
    print(f"  ⚠️  LAB-CEILING values (E_CYCLE={E_CYCLE*1e3:.0f}mJ, j_max={J_MAX_25C*1e6:.0f} µA/cm²"
          f" at pH 7.4 on graphite). The old 60s baseline +")
    print("      β-perturbation coupling was REVERSED in E.63 (delta_t→β was economically")
    print("      null/inverted). delta_t now drives growth_points DIRECTLY via")
    print("      metabolic_health(delta_t); FAST/SLOW thresholds are field-scale and")
    print("      calibration-pending on the bench recharge curve (RUNBOOK §3.2-3.3).")

    banner("L4 complete — EBFC recharge-kinetics model (delta_t → growth_points, E.63)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
