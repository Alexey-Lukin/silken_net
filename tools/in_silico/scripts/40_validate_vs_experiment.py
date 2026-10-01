#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Ti-coin Stage 2 — compare in-silico predictions vs experimental data.

Purpose
-------
When CV/EIS measurements arrive from Ti-coin tests (01_03 §3.5), this
script loads the in-silico predictions (L3 DFT, L4 kinetics, L4b EIS)
and generates a comparison report with statistical metrics, plus the
coin's ACCEPTANCE gates (V_OC, R_int), which are judged against thresholds,
not against a prediction.

Status: a FRAME, untested on real data (00_07 HW.24). The field list and the
normalisation follow the lab letter's repo layer (anchor_coin_electrochem_rfq §4).

Every EXPERIMENTAL key belongs to exactly one class below, and a key in no class
is an error — a typo or a new field must not drop out of the report silently:
  COMPARED       — has a prediction; counted in «Overall agreement».
  REPORTED_ONLY  — no prediction exists; printed as «NO PREDICTION», never counted.
  GATES          — acceptance gates (01_03 §3.5 · 02_03 §1.5); pass/fail, not agreement.
  METADATA       — inputs to the normalisation (the O-ring window area).

What the checks here CAN and CANNOT catch (in-silico §When Modifying #8):
  - j_max: the prediction is the Michaelis-Menten parameter of L4, so only the MM fit of
    the lab's glucose series is compared; the CV peak current is reported, never compared.
  - R_ct: the model gives Ω at its own electrode area, the lab gives Ω at its window area,
    so both are compared as Ω·cm². A second time constant in the lab's equivalent circuit
    would make R_ct not one number — this script cannot see that; read the lab's fit.
  - R_s depends on the cell geometry, so it is reported only.
  - The R_int gate uses the WORST-CASE VIN(CS) (max), the same threshold the V_OC gate is
    ratified on; the typ ceiling is printed beside it for information.
  - Thresholds come from lib.constants (mirrors of 02_03 §1.1), never typed here.

Usage
-----
1. Record experimental values in the EXPERIMENTAL dict below
2. Run: python tools/in_silico/scripts/40_validate_vs_experiment.py
3. Output: comparison report + agreement metrics + acceptance gates

Currently shows PREDICTED values only (no experimental data yet).
Update EXPERIMENTAL dict when Ti-coin data arrives.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/40_validate_vs_experiment.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    BQ25570_PIN_CS_UW,
    BQ25570_VIN_CS_MAX_MV,
    BQ25570_VIN_CS_TYP_MV,
    DFT_CACHE,
    KINETICS_DIR,
    REPO_ROOT,
)
from lib.utils import banner

KINETICS = KINETICS_DIR
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
    # The Michaelis-Menten parameter, NOT a CV peak current density.
    preds["j_max_MM_uA_cm2"] = kin["parameters"]["j_max_25C_uA_cm2"]
    preds["Km_mM"] = kin["parameters"]["Km_mM"]

    # L4b: EIS — R_ct in Ω holds only at the model's electrode area, so carry the
    # area-specific value too; that is the one a lab number can be compared with.
    eis = json.loads((KINETICS / "eis_model.json").read_text())
    preds["Rct_ohm"] = eis["parameters"]["Rct_ohm"]
    preds["A_model_cm2"] = eis["parameters"]["A_electrode_cm2"]
    preds["Rct_ohm_cm2"] = preds["Rct_ohm"] * preds["A_model_cm2"]
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
    # Uncomment and fill when data arrives (field list — anchor_coin_electrochem_rfq §4):
    # "exposed_area_cm2": 2.0,      # O-ring window area of THIS record — required to compare R_ct
    # "j_max_MM_uA_cm2": 450,       # Michaelis-Menten fit of the glucose series
    # "Km_mM": 25,                  # the same fit
    # "Rct_ohm": 180,               # EIS semicircle diameter, Ω at the exposed area above
    # "Cdl_uF_cm2": 35,             # EIS double-layer capacitance
    # "j_cv_peak_uA_cm2": 300,      # CV peak current density — reported only
    # "Rs_ohm": 75,                 # EIS high-freq intercept — cell-dependent, reported only
    # "delta_t_measured_s": 45,     # Measured charge time at 25°C — reported only
    # "stability_30d_pct": 92,      # Activity retention after 30 days — reported only
    # "OCV_mV": 750,                # V_OC of the pair — acceptance gate
    # "R_int_ohm": 4000,            # two-point R_int (V_OC + cell voltage at ≈25 µA) — acceptance gate
}

# EXPERIMENTAL key → the prediction key it is compared with.
COMPARED = {
    "j_max_MM_uA_cm2": "j_max_MM_uA_cm2",
    "Km_mM": "Km_mM",
    "Rct_ohm": "Rct_ohm_cm2",       # measured Ω × exposed_area_cm2 against the model's Ω·cm²
    "Cdl_uF_cm2": "Cdl_uF_cm2",
}
REPORTED_ONLY = {"j_cv_peak_uA_cm2", "Rs_ohm", "delta_t_measured_s", "stability_30d_pct"}
GATES = {"OCV_mV", "R_int_ohm"}
METADATA = {"exposed_area_cm2"}


def r_int_ceiling_ohm(v_oc_mv: float, vin_cs_mv: float) -> float | None:
    """02_03 §1.5: R_int ≤ (V_OC − VIN(CS)) × VIN(CS) / PIN(CS); mV·mV/µW = Ω.

    None when V_OC ≤ VIN(CS): no R_int lets the part cold-start at all."""
    if v_oc_mv <= vin_cs_mv:
        return None
    return (v_oc_mv - vin_cs_mv) * vin_cs_mv / BQ25570_PIN_CS_UW


def unit_of(key: str) -> str:
    if key.startswith("delta_t"):
        return "s"
    for suffix, unit in (("_eV", "eV"), ("_ohm_cm2", "Ω·cm²"), ("_ohm", "Ω"), ("_uA_cm2", "µA/cm²"),
                         ("_uF_cm2", "µF/cm²"), ("_cm2", "cm²"), ("_mM", "mM")):
        if key.endswith(suffix):
            return unit
    return ""


def check_keys(exp: dict) -> None:
    unknown = set(exp) - set(COMPARED) - REPORTED_ONLY - GATES - METADATA
    if unknown:
        raise SystemExit(f"EXPERIMENTAL keys in no class: {sorted(unknown)} — classify them above")
    if "Rct_ohm" in exp and "exposed_area_cm2" not in exp:
        raise SystemExit("Rct_ohm needs exposed_area_cm2: Ω is comparable only per cm²")
    if "R_int_ohm" in exp and "OCV_mV" not in exp:
        raise SystemExit("R_int_ohm needs OCV_mV: its ceiling is a function of V_OC (02_03 §1.5)")


def acceptance_gates(exp: dict) -> list[dict]:
    """The coin's gates (01_03 §3.5). Judged against thresholds, never against a prediction."""
    rows = []
    if "OCV_mV" in exp:
        v_oc = exp["OCV_mV"]
        rows.append({"gate": "V_OC >= VIN(CS) max", "measured": v_oc,
                     "limit": BQ25570_VIN_CS_MAX_MV, "pass": v_oc >= BQ25570_VIN_CS_MAX_MV})
        if "R_int_ohm" in exp:
            ceiling = r_int_ceiling_ohm(v_oc, BQ25570_VIN_CS_MAX_MV)
            rows.append({"gate": "R_int <= ceiling at VIN(CS) max", "measured": exp["R_int_ohm"],
                         "limit": ceiling,
                         "limit_at_typ": r_int_ceiling_ohm(v_oc, BQ25570_VIN_CS_TYP_MV),
                         "pass": ceiling is not None and exp["R_int_ohm"] <= ceiling})
    return rows


def compare(preds: dict, exp: dict) -> list[dict]:
    rows = []
    for key, pred_key in COMPARED.items():
        if key not in exp:
            continue
        measured = exp[key] * exp["exposed_area_cm2"] if key == "Rct_ohm" else exp[key]
        predicted = preds[pred_key]
        err_pct = abs(predicted - measured) / measured * 100
        rows.append({"key": pred_key, "predicted": predicted, "measured": measured,
                     "err_pct": err_pct, "within_100pct": err_pct < 100})
    return rows


def main() -> int:
    banner("Ti-coin Stage 2 — in-silico vs experimental comparison")

    preds = load_predictions()
    check_keys(EXPERIMENTAL)

    print("\n  IN-SILICO PREDICTIONS:")
    print(f"  {'Parameter':<30s} {'Predicted':>12s} {'Unit':>10s}")
    print("  " + "-" * 55)
    for key, val in sorted(preds.items()):
        unit = unit_of(key)
        # [E.63] A percentile can be None («never gathers a cycle») since 30b stopped capping it.
        shown = "never" if val is None else f"{val:.3f}"
        print(f"  {key:<30s} {shown:>12s} {unit:>10s}")

    rows, gates = [], []
    if not EXPERIMENTAL:
        print("\n  ⚠️  No experimental data yet — fill EXPERIMENTAL dict when Ti-coin data arrives")
    else:
        banner("COMPARISON: Predicted vs Experimental")
        print(f"\n  {'Parameter':<25s} {'Predicted':>10s} {'Measured':>10s} {'Error %':>10s} {'Match':>8s}")
        print("  " + "-" * 65)
        rows = compare(preds, EXPERIMENTAL)
        for row in rows:
            match = "✅" if row["err_pct"] < 50 else "⚠️" if row["err_pct"] < 100 else "❌"
            print(f"  {row['key']:<25s} {row['predicted']:>10.1f} {row['measured']:>10.1f} "
                  f"{row['err_pct']:>9.1f}% {match:>8s}")
        for key in sorted(REPORTED_ONLY & set(EXPERIMENTAL)):
            print(f"  {key:<25s} {'—':>10s} {EXPERIMENTAL[key]:>10.1f}  NO PREDICTION — reported only")
        matches = [row["within_100pct"] for row in rows]
        overall = sum(matches) / len(matches) * 100 if matches else 0
        print(f"\n  Overall agreement: {overall:.0f}% ({sum(matches)}/{len(matches)} within 100%)")

        gates = acceptance_gates(EXPERIMENTAL)
        if gates:
            banner("ACCEPTANCE GATES (01_03 §3.5 · 02_03 §1.5)")
            for g in gates:
                limit = "impossible" if g["limit"] is None else f"{g['limit']:.0f}"
                print(f"  {g['gate']:<34s} measured {g['measured']:>8.0f}  limit {limit:>10s}  "
                      f"{'PASS' if g['pass'] else 'FAIL'}")

    # Save predictions for reference
    results = {"predictions": preds, "experimental": EXPERIMENTAL,
               "comparison": rows, "acceptance_gates": gates}
    out_path = OUT_DIR / "validation_report.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    print(f"\n  Wrote {out_path.relative_to(REPO_ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
