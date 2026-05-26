#!/usr/bin/env python
"""
Ti-coin Stage 2 — compare in-silico predictions vs experimental data.

Purpose
-------
When CV/EIS measurements arrive from Ti-coin tests (01_03 §3.5), this
script loads the in-silico predictions (L3 DFT, L4 kinetics, L4b EIS)
and generates a comparison report with statistical metrics.

Usage
-----
1. Record experimental values in the EXPERIMENTAL dict below
2. Run: python tools/in_silico/scripts/40_validate_vs_experiment.py
3. Output: comparison report + agreement metrics

Currently shows PREDICTED values only (no experimental data yet).
Update EXPERIMENTAL dict when Ti-coin data arrives.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/40_validate_vs_experiment.py
"""
from __future__ import annotations

import json
import time
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
DFT_CACHE = REPO_ROOT / "tools/in_silico/cache/dft"
KINETICS = REPO_ROOT / "tools/in_silico/cache/kinetics"
OUT_DIR = KINETICS
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ═══════════════════════════════════════════════════════════════════
# IN-SILICO PREDICTIONS (loaded from cache)
# ═══════════════════════════════════════════════════════════════════

def load_predictions() -> dict:
    """Load all in-silico predictions from cache files."""
    preds = {}

    # L3: Os cascade
    comp = json.loads((DFT_CACHE / "comparison.json").read_text())
    preds["E_cascade_eV"] = comp["delta_eV"]
    preds["HOMO_FADH2_eV"] = comp["donor_homo_eV"]
    preds["LUMO_Os3_eV"] = comp["acceptor_lumo_eV"]

    # L4: kinetics
    kin = json.loads((KINETICS / "delta_t_lookup.json").read_text())
    for pt in kin["reference_points"]:
        if pt["scenario"] == "healthy summer":
            preds["delta_t_healthy_s"] = pt["delta_t_s"]
        elif pt["scenario"] == "cold winter / stress":
            preds["delta_t_stressed_s"] = pt["delta_t_s"]
    preds["j_max_uA_cm2"] = kin["parameters"]["j_max_25C_uA_cm2"]
    preds["Km_mM"] = kin["parameters"]["Km_mM"]

    # L4b: EIS
    eis = json.loads((KINETICS / "eis_model.json").read_text())
    preds["Rct_ohm"] = eis["parameters"]["Rct_ohm"]
    preds["Rs_ohm"] = eis["parameters"]["Rs_ohm"]
    preds["Cdl_uF_cm2"] = eis["parameters"]["Cdl_uF_cm2"]

    # Monte Carlo
    mc = json.loads((KINETICS / "monte_carlo.json").read_text())
    for sc in mc["scenarios"]:
        if sc["label"] == "Healthy summer":
            preds["delta_t_healthy_p5"] = sc["p5_s"]
            preds["delta_t_healthy_p95"] = sc["p95_s"]

    return preds


# ═══════════════════════════════════════════════════════════════════
# EXPERIMENTAL DATA (fill in when Ti-coin Stage 2 data arrives)
# ═══════════════════════════════════════════════════════════════════

EXPERIMENTAL = {
    # Uncomment and fill when data arrives:
    # "j_max_uA_cm2": 450,        # CV peak current density
    # "Rct_ohm": 180,             # EIS semicircle diameter
    # "Rs_ohm": 75,               # EIS high-freq intercept
    # "Cdl_uF_cm2": 35,           # EIS double-layer capacitance
    # "OCV_mV": 650,              # Open circuit voltage
    # "delta_t_measured_s": 45,   # Measured charge time at 25°C
    # "Km_mM": 25,                # From Lineweaver-Burk plot
    # "stability_30d_pct": 92,    # Activity retention after 30 days
}


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def main() -> int:
    banner("Ti-coin Stage 2 — in-silico vs experimental comparison")

    preds = load_predictions()

    print("\n  IN-SILICO PREDICTIONS:")
    print(f"  {'Parameter':<30s} {'Predicted':>12s} {'Unit':>10s}")
    print("  " + "-" * 55)
    for key, val in sorted(preds.items()):
        unit = "eV" if "eV" in key else "s" if "_s" in key else "Ω" if "ohm" in key else \
               "µA/cm²" if "uA" in key else "µF/cm²" if "uF" in key else "mM" if "mM" in key else ""
        print(f"  {key:<30s} {val:>12.3f} {unit:>10s}")

    if not EXPERIMENTAL:
        print("\n  ⚠️  No experimental data yet — fill EXPERIMENTAL dict when Ti-coin data arrives")
        print("  Script ready for validation — just uncomment and fill values in the script.")
    else:
        banner("COMPARISON: Predicted vs Experimental")
        print(f"\n  {'Parameter':<25s} {'Predicted':>10s} {'Measured':>10s} {'Error %':>10s} {'Match':>8s}")
        print("  " + "-" * 65)

        matches = []
        for key, exp_val in EXPERIMENTAL.items():
            if key in preds:
                pred_val = preds[key]
                err_pct = abs(pred_val - exp_val) / exp_val * 100
                match = "✅" if err_pct < 50 else "⚠️" if err_pct < 100 else "❌"
                matches.append(err_pct < 100)
                print(f"  {key:<25s} {pred_val:>10.1f} {exp_val:>10.1f} {err_pct:>9.1f}% {match:>8s}")

        overall = sum(matches) / len(matches) * 100 if matches else 0
        print(f"\n  Overall agreement: {overall:.0f}% ({sum(matches)}/{len(matches)} within 100%)")

    # Save predictions for reference
    results = {"predictions": preds, "experimental": EXPERIMENTAL}
    out_path = OUT_DIR / "validation_report.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    print(f"\n  Wrote {out_path.relative_to(REPO_ROOT)}")

    banner("✅ Validation script ready — update EXPERIMENTAL dict when data arrives")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
