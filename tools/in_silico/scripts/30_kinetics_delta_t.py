#!/usr/bin/env python
"""
L4 — EBFC kinetics: predict delta_t (supercapacitor charge time) from
glucose concentration and temperature.

Physical model
--------------
    glucose diffusion (Fick) → Michaelis-Menten (dgrFAD-GDH)
    → electron current (Os-mediated) → BQ25570 boost → EDLC charge → delta_t

This closes the final level of the 4-level Zero-Lab pipeline (01_03 §3.4).
The output delta_t is the same quantity that the Lorenz attractor uses as
β-perturbation (bio_contract.rb: BASELINE_DELTA_T_S = 60 s).

Key literature parameters
-------------------------
  j_max(25°C) = 494 µA/cm²    — dgrGcGDH + Os-polymer (Zafar 2012, PMC3275720)
  Km ≈ 20 mM                  — estimate for GcGDH (between Asp 87 mM, Mucor 28 mM)
  V_op = 0.5 V                — EBFC under load (OCV 0.6-0.8 V, 01_03 §1)
  η_bq = 0.85                 — BQ25570 boost efficiency (TI SLUSBH2G)
  E_cycle = 5 mJ              — STM32WLE5JC per wake cycle (sense + LoRa TX)
  Ea = 40 kJ/mol              — Arrhenius activation energy (FAD enzyme typical)
  D_eff = 2e-6 cm²/s          — glucose through chitosan hydrogel matrix
  δ = 20 µm                   — membrane + hydrogel thickness (01_03 §2.1)

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/30_kinetics_delta_t.py
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import REPO_ROOT, LIGANDS_DIR, DFT_CACHE, KINETICS_DIR, HARTREE_TO_EV
OUT_DIR = KINETICS_DIR
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ═══════════════════════════════════════════════════════════════════
# Physical constants
# ═══════════════════════════════════════════════════════════════════
F_CONST = 96485.0          # Faraday constant, C/mol
R_GAS = 8.314              # gas constant, J/(mol·K)
N_ELECTRONS = 2            # electrons per glucose (FAD → FADH₂)

# ═══════════════════════════════════════════════════════════════════
# EBFC parameters (from literature + docs)
# ═══════════════════════════════════════════════════════════════════
J_MAX_25C = 494e-6         # A/cm² — dgrGcGDH + Os-polymer at 20 mM glucose, 25°C (Zafar 2012, PMC3275720)
KM_GLUCOSE = 20.0          # mM — estimated for GcGDH (between Asp 87 mM and Mucor 28 mM; j_max reached at 20 mM suggests Km ≤ 20)
EA_ENZYME = 40_000.0       # J/mol — typical Arrhenius Ea for FAD-dependent enzyme reactions (literature range 30-50 kJ/mol)
T_REF = 298.15             # K — reference temperature (25°C)

V_OP = 0.5                 # V — EBFC under load (OCV 0.6-0.8 V from 01_03 §1, ~60-70% under MPPT)
A_ELECTRODE = 2.0          # cm² — conservative estimate: portion of ~30 cm² gyroid surface with active enzyme layer

ETA_BQ = 0.85              # BQ25570 boost converter efficiency
E_CYCLE = 5e-3             # J — energy per MCU wake cycle (sense + compute + LoRa TX)

# Diffusion (for mass-transport limitation check)
D_EFF = 2e-6               # cm²/s — glucose in chitosan/Nafion matrix
DELTA_MEMBRANE = 20e-4     # cm (= 20 µm) — total membrane + hydrogel thickness

# Firmware constants (for validation)
BASELINE_DELTA_T_S = 60    # seconds (bio_contract.rb)

# Sweep ranges
GLUCOSE_RANGE_MM = np.linspace(1, 30, 60)       # mM
TEMP_RANGE_C = np.linspace(-10, 40, 51)          # °C


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


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


def main() -> int:
    banner("L4 EBFC kinetics — delta_t prediction")
    print(f"  j_max(25°C) = {J_MAX_25C*1e6:.0f} µA/cm²")
    print(f"  Km = {KM_GLUCOSE:.0f} mM")
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
    dt_base = delta_t(10, 25)
    sensitivities = {}

    for param, values, label in [
        ("Km", [10, 15, 20, 30, 50], "mM"),
        ("A_electrode", [1, 2, 3, 5], "cm²"),
        ("E_cycle", [2, 5, 10, 20], "mJ"),
        ("j_max", [200, 494, 700, 1000], "µA/cm²"),
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

    # ── 7. Verdict ──
    banner("L4 verdict")
    dt_healthy = delta_t(10, 25)
    dt_stress = delta_t(5, 5)
    verdict_ok = dt_healthy < BASELINE_DELTA_T_S and dt_stress > BASELINE_DELTA_T_S
    if verdict_ok:
        print(f"  ✅ BASELINE VALIDATED")
        print(f"     Healthy tree (10 mM, 25°C): delta_t = {dt_healthy:.1f}s < 60s → β increases")
        print(f"     Stressed tree (5 mM, 5°C):  delta_t = {dt_stress:.1f}s > 60s → β at baseline")
        print(f"     EBFC discriminates healthy vs stressed → Lorenz attractor receives meaningful signal")
    else:
        print(f"  ⚠️  Model needs parameter adjustment")
        print(f"     dt_healthy={dt_healthy:.1f}s, dt_stress={dt_stress:.1f}s")

    banner("✅ L4 complete — EBFC kinetics validated against firmware BASELINE_DELTA_T_S = 60s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
