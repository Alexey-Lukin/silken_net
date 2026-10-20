#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Ti-coin Stage 2 — compare in-silico predictions vs experimental data.

Purpose
-------
When CV/EIS measurements arrive from Ti-coin tests (01_03 §3.5), this
script loads the in-silico predictions (L3 DFT, L4 kinetics, L4b EIS)
and generates a comparison report with statistical metrics, plus the
coin's ACCEPTANCE gates (V_OC, R_int; and C · D · E per arm), which are judged
against thresholds, not against a prediction.

Status: a FRAME, untested on real data (00_07 HW.24). The field list and the
normalisation follow the lab letter's repo layer (anchor_coin_electrochem_rfq §4).

Every EXPERIMENTAL key belongs to exactly one class below, and a key in no class
is an error — a typo or a new field must not drop out of the report silently:
  COMPARED       — has a prediction; counted in «Overall agreement».
  REPORTED_ONLY  — no prediction exists; printed as «NO PREDICTION», never counted.
  GATES          — acceptance gates (01_03 §3.5 · 02_03 §1.5); pass/fail, not agreement.
  ARM_GATES      — the gates C · D · E: a dict arm label → LIST of ratios, one per coupon (retention · chloride
                   ratio · recovery); each arm is judged and printed under its own label. ⚖️ RATIFIED 2026-10-20 (01_03 §3.5, under the thresholds): the arm's GEOMETRIC MEAN
                   is judged; the one-sided 95 % lower confidence bound is printed beside it, never judged; no
                   «every coupon». E's threshold is full recovery minus the instrument's repeatability band —
                   `cv_scan_sigma` (σ of one scan → 1.96·√2·σ) or `cv_repeatability_r` (a repeatability limit r,
                   taken as is). Both routes are the ISO 5725 repeatability limit at 95 % — r = 1.96·√2·σ (⚖️
                   founder 2026-10-20, the correction of the first wording, 01_03 §3.5). Without one of them the
                   RECORD is refused, as R_int without R_partition.
  GATE_INPUTS    — inputs a gate needs that are not gates themselves (the joint · the band).
  METADATA       — inputs to the normalisation (the O-ring window area).

What the checks here CAN and CANNOT catch (in-silico §When Modifying #8):
  - j_max: the prediction is the Michaelis-Menten parameter of L4, so only the MM fit of
    the lab's glucose series is compared; the CV peak current is reported, never compared.
  - R_ct: the model gives Ω at its own electrode area, the lab gives Ω at its window area,
    so both are compared as Ω·cm². A second time constant in the lab's equivalent circuit
    would make R_ct not one number — this script cannot see that; read the lab's fit.
  - R_s depends on the cell geometry, so it is reported only.
  - The R_int gate uses the WORST-CASE VIN(CS) (max) — ⚖️ RATIFIED by the founder 2026-10-01
    (01_03 §3.5, 00_07 HW.24), the same end of the datasheet range as the V_OC gate, until HW.46
    measures VIN(CS) of our batch. The convention flips a verdict — a coin at V_OC exactly at
    VIN(CS) max passes the V_OC gate yet has no R_int ceiling at max, while typ gives it one — so the
    typ ceiling is printed beside it (`gate_line`) and recorded in the report, as a reference only.
  - Thresholds come from lib.constants (mirrors of 02_03 §1.1 and 01_03 §3.5), never typed here.
  - C · D · E: the lower bound needs t₀.₉₅ quantiles, carried as a table (stdlib only — the bare CI job runs
    these tests) and pinned against scipy in test_cache_integrity; an arm of one coupon has no bound (n/a).
    The band of E is the instrument's, a FLOOR: re-mounting, drift between the two measurements and the
    coupons' different response are not in it, and if E is measured by another technique than the CV
    whose repeatability the lab states, the band must be asked again.

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
import math
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    BQ25570_PIN_CS_UW,
    BQ25570_VIN_CS_MAX_MV,
    BQ25570_VIN_CS_TYP_MV,
    COIN_CHLORIDE_MIN_RATIO,
    COIN_RETENTION_30D_MIN,
    COIN_UCST_RECOVERY_RATIO,
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
    # "retention_30d_by_coupon": {"anode Ti-6Al-7Nb": [0.91, 0.86], "cathode 4V nanozyme": [0.88, 0.84]},  # C, per arm
    # "chloride_ratio_by_coupon": {"cathode 4V (D)": [1.04, 0.97]},   # D — at 0.25 M NaCl / chloride-free start
    # "ucst_recovery_by_coupon": {"anode 4V membrane (E)": [0.99, 1.01]},   # E — after −10 → +25 °C / pre-freeze
    # "cv_scan_sigma": 0.02,        # E's band: the lab's σ of ONE scan (fraction) — OR the next line, never both
    # "cv_repeatability_r": 0.05,   # E's band: the lab's repeatability limit r (fraction, ISO 5725)
    # "OCV_mV": 750,                # V_OC of the pair — acceptance gate
    # "R_int_ohm": 4000,            # two-point R_int (V_OC + cell voltage at ≈25 µA) — acceptance gate
    # "R_partition_ohm": 300,       # the compartment JOINT alone (EIS, two identical inert electrodes, no coupons)
}

# EXPERIMENTAL key → the prediction key it is compared with.
COMPARED = {
    "j_max_MM_uA_cm2": "j_max_MM_uA_cm2",
    "Km_mM": "Km_mM",
    "Rct_ohm": "Rct_ohm_cm2",       # measured Ω × exposed_area_cm2 against the model's Ω·cm²
    "Cdl_uF_cm2": "Cdl_uF_cm2",
}
REPORTED_ONLY = {"j_cv_peak_uA_cm2", "Rs_ohm", "delta_t_measured_s"}
GATES = {"OCV_mV", "R_int_ohm"}
# Gate per list key: its label and threshold (mirrors of 01_03 §3.5 via lib.constants). E's threshold is lowered by
# the band at judgement time (`e_band`).
ARM_GATES = {
    "retention_30d_by_coupon": ("C retention", COIN_RETENTION_30D_MIN),
    "chloride_ratio_by_coupon": ("D chloride", COIN_CHLORIDE_MIN_RATIO),
    "ucst_recovery_by_coupon": ("E recovery", COIN_UCST_RECOVERY_RATIO),
}
# The ISO 5725 repeatability limit r = 1.96·√2·σ_r: the two-sided 95 % normal quantile (⚖️ 2026-10-20 — E's band).
REPEATABILITY_COVERAGE_95 = 1.96
# One-sided 95 % Student-t quantiles by degrees of freedom (pinned against scipy.stats.t.ppf in test_cache_integrity).
T_ONE_SIDED_95 = {1: 6.3138, 2: 2.9200, 3: 2.3534, 4: 2.1318, 5: 2.0150, 6: 1.9432, 7: 1.8946, 8: 1.8595,
                  9: 1.8331, 10: 1.8125, 11: 1.7959, 12: 1.7823, 13: 1.7709, 14: 1.7613, 15: 1.7531, 16: 1.7459,
                  17: 1.7396, 18: 1.7341, 19: 1.7291, 20: 1.7247, 21: 1.7207, 22: 1.7171, 23: 1.7139, 24: 1.7109,
                  25: 1.7081, 26: 1.7056, 27: 1.7033, 28: 1.7011, 29: 1.6991, 30: 1.6973}
# ⚖️ founder 2026-10-12 (00_07 HW.24): the coin cell has two compartments, so the two-point R_int carries the joint
# (membrane / frit / salt bridge) too — a property of the CELL, not of the electrodes, which the cold-start gate must
# not charge to the pair. The lab measures the joint alone (measurement B, anchor_coin_electrochem_rfq) and it is
# subtracted here; EIS A sees each electrode in its own three-electrode cell and cannot see the joint.
GATE_INPUTS = {"R_partition_ohm", "cv_scan_sigma", "cv_repeatability_r"}
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
    unknown = set(exp) - set(COMPARED) - REPORTED_ONLY - GATES - set(ARM_GATES) - GATE_INPUTS - METADATA
    if unknown:
        raise SystemExit(f"EXPERIMENTAL keys in no class: {sorted(unknown)} — classify them above")
    if "Rct_ohm" in exp and "exposed_area_cm2" not in exp:
        raise SystemExit("Rct_ohm needs exposed_area_cm2: Ω is comparable only per cm²")
    if "R_int_ohm" in exp and "OCV_mV" not in exp:
        raise SystemExit("R_int_ohm needs OCV_mV: its ceiling is a function of V_OC (02_03 §1.5)")
    if "R_int_ohm" in exp and "R_partition_ohm" not in exp:
        raise SystemExit("R_int_ohm of the two-compartment cell needs R_partition_ohm: the joint belongs to the cell, "
                         "not the electrodes (00_07 HW.24, 2026-10-12)")
    if "R_partition_ohm" in exp and not 0.0 <= exp["R_partition_ohm"] < exp.get("R_int_ohm", float("inf")):
        raise SystemExit("R_partition_ohm must lie in [0, R_int_ohm): a joint at least as resistive as the whole cell "
                         "means the two readings are not of one configuration")
    for key in set(ARM_GATES) & set(exp):
        arms = exp[key]
        if not isinstance(arms, dict) or not arms:
            raise SystemExit(f"{key} must be a dict arm label → list of ratios — a record names the arm it judges")
        for arm, values in arms.items():
            if not (isinstance(arm, str) and arm.strip()):
                raise SystemExit(f"{key}: every arm needs a non-empty label")
            if not isinstance(values, list) or not values or not all(_positive(v) for v in values):
                raise SystemExit(f"{key}[{arm!r}] must be a non-empty list of finite positive ratios, one per coupon")
            if len(values) - 1 > max(T_ONE_SIDED_95):
                raise SystemExit(f"{key}[{arm!r}]: more coupons than the t table carries — extend T_ONE_SIDED_95")
    bands = [k for k in ("cv_scan_sigma", "cv_repeatability_r") if k in exp]
    if "ucst_recovery_by_coupon" in exp and len(bands) != 1:
        raise SystemExit("ucst_recovery_by_coupon needs exactly one band — cv_scan_sigma OR cv_repeatability_r: E's "
                         "threshold is full recovery minus the instrument's repeatability (⚖️ 2026-10-20, 01_03 §3.5)")
    if any(not _positive(exp[k]) for k in bands) or (bands and not 0.0 < e_band(exp) < 1.0):
        raise SystemExit("the repeatability band must be a finite positive fraction whose derived band lies in (0, 1)")


def _positive(v) -> bool:
    """A finite positive real — not a bool (isinstance(True, int) holds), not inf or NaN."""
    return type(v) in (int, float) and math.isfinite(v) and v > 0


def e_band(exp: dict) -> float:
    """E's band — the ISO 5725 repeatability limit at 95 % by either route: σ of one scan → 1.96·√2·σ (two scans,
    95 % coverage), or the lab's limit r, which already is that (⚖️ 2026-10-20, 01_03 §3.5)."""
    if "cv_scan_sigma" in exp:
        return REPEATABILITY_COVERAGE_95 * math.sqrt(2.0) * exp["cv_scan_sigma"]
    return exp["cv_repeatability_r"]


def arm_gate(values: list[float], threshold: float) -> dict:
    """⚖️ 2026-10-20: the arm's geometric mean is judged; its one-sided 95 % lower bound is printed, never judged."""
    logs = [math.log(v) for v in values]
    mean = statistics.fmean(logs)
    bound = (math.exp(mean - T_ONE_SIDED_95[len(logs) - 1] * statistics.stdev(logs) / math.sqrt(len(logs)))
             if len(logs) > 1 else None)
    return {"measured": math.exp(mean), "lower_bound": bound, "n": len(logs), "limit": threshold,
            "pass": math.exp(mean) >= threshold}


def acceptance_gates(exp: dict) -> list[dict]:
    """The coin's gates (01_03 §3.5). Judged against thresholds, never against a prediction."""
    rows = []
    if "OCV_mV" in exp:
        v_oc = exp["OCV_mV"]
        rows.append({"gate": "V_OC >= VIN(CS) max", "measured": v_oc,
                     "limit": BQ25570_VIN_CS_MAX_MV, "pass": v_oc >= BQ25570_VIN_CS_MAX_MV})
        if "R_int_ohm" in exp:
            ceiling = r_int_ceiling_ohm(v_oc, BQ25570_VIN_CS_MAX_MV)
            electrodes = exp["R_int_ohm"] - exp["R_partition_ohm"]   # the joint is the cell's, not the pair's
            rows.append({"gate": "R_int <= ceiling at VIN(CS) max", "measured": electrodes,
                         "cell_R_int_ohm": exp["R_int_ohm"], "partition_ohm": exp["R_partition_ohm"],
                         "limit": ceiling,
                         "limit_at_typ": r_int_ceiling_ohm(v_oc, BQ25570_VIN_CS_TYP_MV),
                         "pass": ceiling is not None and electrodes <= ceiling})
    for key, (label, threshold) in ARM_GATES.items():
        for arm, values in exp.get(key, {}).items():
            row = {"gate": f"{label} — {arm}", "arm": arm}
            if key == "ucst_recovery_by_coupon":
                band = e_band(exp)
                row |= {"band": band, "band_route": "1.96·√2·σ" if "cv_scan_sigma" in exp else "r"}
                row |= arm_gate(values, threshold - band)
            else:
                row |= arm_gate(values, threshold)
            rows.append(row)
    return rows


def gate_line(g: dict) -> str:
    """One printed gate row; the R_int row carries its typ ceiling beside the judged max one."""
    def shown(limit):
        return "impossible" if limit is None else f"{limit:.0f}"
    if "lower_bound" in g:   # an arm gate: a ratio, judged on the mean, the bound beside it
        bound = "n/a" if g["lower_bound"] is None else f"{g['lower_bound']:.3f}"
        band = f"  [limit = 1 − band {g['band']:.3f}, {g['band_route']}]" if "band" in g else ""
        return (f"  {g['gate']:<34s} measured {g['measured']:>8.3f}  limit {g['limit']:>10.3f}  "
                f"{'PASS' if g['pass'] else 'FAIL'}{band}  (one-sided 95 % lower bound {bound}, n = {g['n']} — "
                f"printed, not judged)")
    typ = f"  (typ ceiling {shown(g['limit_at_typ'])})" if "limit_at_typ" in g else ""
    split = (f"  [cell {g['cell_R_int_ohm']:.0f} − joint {g['partition_ohm']:.0f}]" if "partition_ohm" in g else "")
    return (f"  {g['gate']:<34s} measured {g['measured']:>8.0f}  limit {shown(g['limit']):>10s}  "
            f"{'PASS' if g['pass'] else 'FAIL'}{split}{typ}")


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
                print(gate_line(g))

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
