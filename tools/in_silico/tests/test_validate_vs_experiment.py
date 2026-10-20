# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Script 40 (Ti-coin Stage 2 comparison) — its acceptance gates and key classes, plus the
mirror its thresholds read (00_07 HW.24).

Pure stdlib + pytest (lib/ is stdlib at import; openmm loads lazily) — run by the bare `cache_doc_sync`
job of in_silico_smoke.yml, as test_unified_lame is.
CAN catch: a wrong R_int ceiling formula or unit (pinned to the 02_03 §1.5 table rows), a V_OC gate
on the wrong threshold, the typ ceiling dropping out of the printed R_int gate row, an unclassified
EXPERIMENTAL key passing silently, R_ct compared without an area, and the cold-start constants
drifting from the 02_03 §1.1 table.
⚠️ `test_gates_judge_on_worst_case_threshold` pins a RATIFIED verdict — the R_int ceiling judged at
VIN(CS) max (⚖️ 2026-10-01, 01_03 §3.5 · 00_07 HW.24) — until HW.46 measures VIN(CS) of our batch.
CANNOT catch: whether the lab's equivalent circuit makes R_ct one number, or whether a measured
value is plausible — the script has no real data yet.
"""
import ast
import importlib.util
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
sys.path.insert(0, str(ROOT))

_spec = importlib.util.spec_from_file_location("validate40", ROOT / "scripts" / "40_validate_vs_experiment.py")
v40 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(v40)


@pytest.mark.parametrize("v_oc,vin_cs,ceiling", [
    (700.0, 600.0, 4000.0),   # 02_03 §1.5 table: 700 mV, typ → ≤ 4.0 kΩ
    (800.0, 600.0, 8000.0),   # 800 mV, typ → ≤ 8.0 kΩ
    (800.0, 700.0, 4666.7),   # 800 mV, worst-case → ≤ 4.7 kΩ
])
def test_r_int_ceiling_matches_canon_table(v_oc, vin_cs, ceiling):
    assert v40.r_int_ceiling_ohm(v_oc, vin_cs) == pytest.approx(ceiling, abs=0.1)


@pytest.mark.parametrize("v_oc", [500.0, 600.0, 700.0])
def test_r_int_impossible_at_or_below_threshold(v_oc):
    assert v40.r_int_ceiling_ohm(v_oc, 700.0) is None


def test_gates_judge_on_worst_case_threshold():
    # Both gates at VIN(CS) max are ratified: V_OC (2026-09-27) and the R_int ceiling (2026-10-01).
    gates = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 690.0, "R_int_ohm": 1000.0, "R_partition_ohm": 0.0})}
    assert not gates["V_OC >= VIN(CS) max"]["pass"]          # 690 clears typ 600, not max 700
    assert not gates["R_int <= ceiling at VIN(CS) max"]["pass"]
    gates = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 800.0, "R_int_ohm": 4500.0, "R_partition_ohm": 0.0})}
    assert gates["V_OC >= VIN(CS) max"]["pass"] and gates["R_int <= ceiling at VIN(CS) max"]["pass"]
    gates = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 800.0, "R_int_ohm": 5000.0, "R_partition_ohm": 0.0})}
    assert not gates["R_int <= ceiling at VIN(CS) max"]["pass"]   # passes typ (8 kΩ), fails max


def test_gate_row_prints_typ_ceiling_beside_max():
    rows = {g["gate"]: v40.gate_line(g) for g in v40.acceptance_gates({"OCV_mV": 700.0, "R_int_ohm": 3000.0, "R_partition_ohm": 0.0})}
    assert "typ ceiling" not in rows["V_OC >= VIN(CS) max"]
    r_int = rows["R_int <= ceiling at VIN(CS) max"]
    assert "impossible" in r_int and "FAIL" in r_int and r_int.endswith("(typ ceiling 4000)")
    rows = {g["gate"]: v40.gate_line(g) for g in v40.acceptance_gates({"OCV_mV": 600.0, "R_int_ohm": 3000.0, "R_partition_ohm": 0.0})}
    assert rows["R_int <= ceiling at VIN(CS) max"].endswith("(typ ceiling impossible)")


@pytest.mark.parametrize("exp", [
    {"j_max_uA_cm2": 450},                    # the old ambiguous key — must not vanish silently
    {"Rct_ohm": 180},                         # Ω without the window area
    {"R_int_ohm": 4000},                      # a ceiling without V_OC
    {"OCV_mV": 800, "R_int_ohm": 4000},       # a two-compartment R_int without its joint (HW.24, 2026-10-12)
    {"OCV_mV": 800, "R_int_ohm": 4000, "R_partition_ohm": 4000},   # a joint as resistive as the whole cell
    {"OCV_mV": 800, "R_int_ohm": 4000, "R_partition_ohm": -1},     # a negative joint
])
def test_bad_experimental_input_refuses(exp):
    with pytest.raises(SystemExit):
        v40.check_keys(exp)


def test_joint_is_subtracted_before_the_r_int_gate():
    # ⚖️ 2026-10-12 (HW.24): at V_OC 800 mV the max-VIN(CS) ceiling lies between 4500 and 5000 Ω (test above). A cell
    # reading 5000 Ω fails when the joint is charged to the electrodes and passes once its 500 Ω are removed — the
    # case the verdict exists for; the printed row names both terms.
    cell_only = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 800.0, "R_int_ohm": 5000.0, "R_partition_ohm": 0.0})}
    assert not cell_only["R_int <= ceiling at VIN(CS) max"]["pass"]
    split = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 800.0, "R_int_ohm": 5000.0, "R_partition_ohm": 500.0})}
    row = split["R_int <= ceiling at VIN(CS) max"]
    assert row["pass"] and row["measured"] == pytest.approx(4500.0)
    assert "[cell 5000 − joint 500]" in v40.gate_line(row)


def test_rct_compared_per_area():
    preds = {"Rct_ohm_cm2": 145.8}
    rows = v40.compare(preds, {"Rct_ohm": 72.9, "exposed_area_cm2": 2.0})
    assert rows[0]["measured"] == pytest.approx(145.8)
    assert rows[0]["err_pct"] == pytest.approx(0.0)


def _literal(symbol: str) -> float:
    tree = ast.parse((ROOT / "lib" / "constants.py").read_text(encoding="utf-8"))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(getattr(t, "id", None) == symbol for t in node.targets):
            return ast.literal_eval(node.value)
    raise AssertionError(f"lib/constants.py has no literal {symbol}")


def test_cold_start_constants_mirror_canon():
    doc = (REPO / "docs" / "02_03_BQ25570_MPPT_Nano_Power.md").read_text(encoding="utf-8")
    vin = re.search(r"^\| `VIN\(CS\)` \| \*\*(\d+) мВ\*\* \| \*\*(\d+) мВ\*\* \|", doc, re.M)
    pin = re.search(r"^\| `PIN\(CS\)` \| \*\*(\d+) мкВт\*\* \|", doc, re.M)
    assert vin and pin, "02_03 §1.1 table rows for VIN(CS)/PIN(CS) not found — the pin lost its anchor"
    assert float(vin.group(1)) == _literal("BQ25570_VIN_CS_TYP_MV")
    assert float(vin.group(2)) == _literal("BQ25570_VIN_CS_MAX_MV")
    assert float(pin.group(1)) == _literal("BQ25570_PIN_CS_UW")


def test_coin_gate_and_layout_constants_mirror_canon():
    """The C/D/E thresholds and the coupon layout script 100 reads (00_07 HW.24) against their homes.

    CAN catch: a threshold edited on one side only; a layout whose control arms × 2 + the non-electrode coupons no
    longer give the letter's «at 19»; the letter's 12 = 3 + 3 + 6 split moving. CANNOT catch: which electrode arms
    an alloy carries beyond the control's count — that layout lives in 01_03 §3.5 prose.
    """
    doc = (REPO / "docs" / "01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md").read_text(encoding="utf-8")
    c = re.search(r"^> - \*\*30-day stability:\*\* ≥ \*\*(\d+)% retention\*\*", doc, re.M)
    d = re.search(r"^> - \*\*Chloride:\*\* .*НЕ нижче −(\d+)% \(ZIF-гібрид ціль \*\*\+([\d.]+)%\*\*", doc, re.M)
    e = re.search(r"^> - \*\*UCST recovery:\*\* .*відновлюється до \*\*(\d+)%\*\*", doc, re.M)
    assert c and d and e, "01_03 §3.5 gate lines not found — the pin lost its anchor"
    assert _literal("COIN_RETENTION_30D_MIN") == pytest.approx(int(c.group(1)) / 100)
    assert _literal("COIN_CHLORIDE_MIN_RATIO") == pytest.approx(1 - int(d.group(1)) / 100)
    assert _literal("COIN_CHLORIDE_TARGET_RATIO") == pytest.approx(1 + float(d.group(2)) / 100)
    assert _literal("COIN_UCST_RECOVERY_RATIO") == pytest.approx(int(e.group(1)) / 100)

    letter = (REPO / "docs/protocols/procurement/anchor_alloy_rfq.md").read_text(encoding="utf-8")
    q = re.search(r"\*\*Quantity: (\d+) per alloy\*\* — (\d+) for electrode testing, (\d+) for an uncoated ion-release "
                  r"series and (\d+) uncoated coupons held in reserve", letter)
    hi = re.search(r"quote it at (\d+) and at (\d+)\.", letter)
    assert q and hi, "anchor_alloy_rfq quantity sentences not found — the pin lost its anchor"
    total, electrode, uncoated, reserve = (int(x) for x in q.groups())
    assert total == electrode + uncoated + reserve, "the letter's 12 no longer splits into its three parts"
    assert _literal("COIN_QUOTE_PER_ALLOY") == total
    assert _literal("COIN_UNCOATED_ICPMS_PER_ALLOY") == uncoated
    assert _literal("COIN_RESERVE_12WK_PER_ALLOY") == reserve
    assert _literal("COIN_QUOTE_CONTROL_HIGH") == int(hi.group(2))
    # E's band factor (⚖️ 2026-10-20): the canon's «1.96·√2·σ» and 40's constant are one number
    assert "1.96·√2·σ" in doc and v40.REPEATABILITY_COVERAGE_95 == 1.96
    arms = _literal("COIN_ELECTRODE_ARMS")[_literal("COIN_CONTROL_ALLOY")]
    assert len(arms) * 2 + uncoated + reserve == int(hi.group(2)), "the control's arms × 2 no longer give «at 19»"
    for alloy in _literal("COIN_BENCHMARK_ALLOYS"):
        cem = (REPO / f"tools/cad/cem/ti_coin.{alloy.lower()}.json").read_text(encoding="utf-8")
        assert "NOT an anchor candidate" in cem, f"{alloy} is mirrored as a coin-only benchmark; its manifest no longer says so"


# ── gates C · D · E (⚖️ 2026-10-20, 01_03 §3.5 under the thresholds): the arm's geometric mean is judged, the one-sided
# 95 % lower bound is printed beside it and never judged, «every coupon» is not a reading; E against full recovery minus
# the instrument's repeatability band. CAN catch: a gate that judges per coupon or on the bound; a bound on the wrong df,
# spread or scale (its value is pinned); D on the wrong threshold; E judged without its band or with the wrong 1.96·√2; a
# record that does not name its arm; a bool, inf or string passing as a ratio or a band. CANNOT catch whether the lab's
# band fits E's technique (a ceiling in 40's header).
def _row(exp, gate, arm="arm"):
    return {g["gate"]: g for g in v40.acceptance_gates(exp)}[f"{gate} — {arm}"]


def test_arm_gate_judges_the_geometric_mean_not_every_coupon():
    row = _row({"retention_30d_by_coupon": {"arm": [0.95, 0.78, 0.92]}}, "C retention")
    assert row["limit"] == _literal("COIN_RETENTION_30D_MIN") and row["arm"] == "arm"
    assert row["measured"] == pytest.approx((0.95 * 0.78 * 0.92) ** (1 / 3)) and row["pass"]   # one coupon below 0.80


def test_lower_bound_is_printed_not_judged_and_its_value_is_pinned():
    row = _row({"retention_30d_by_coupon": {"arm": [0.85, 0.82]}}, "C retention")
    # scipy: exp(mean(log) − t.ppf(0.95, 1)·stdev(log)/√2) = 0.7453377; df = n, pstdev or a linear-scale bound miss it
    assert row["lower_bound"] == pytest.approx(0.745338, abs=1e-5)
    assert row["pass"] and row["lower_bound"] < row["limit"]          # the mean clears 0.80, its bound does not
    line = v40.gate_line(row)
    assert "PASS" in line and "one-sided 95 % lower bound 0.745" in line and "printed, not judged" in line


def test_each_arm_is_judged_under_its_own_label():
    rows = {g["gate"]: g for g in v40.acceptance_gates(
        {"retention_30d_by_coupon": {"anode Ti-15Zr": [0.9, 0.88], "cathode 4V nanozyme": [0.7, 0.72]}})}
    assert rows["C retention — anode Ti-15Zr"]["pass"] and not rows["C retention — cathode 4V nanozyme"]["pass"]


@pytest.mark.parametrize("values,passes", [([0.95, 0.93], True), ([0.89, 0.88], False)])
def test_d_is_judged_against_its_own_threshold(values, passes):
    row = _row({"chloride_ratio_by_coupon": {"arm": values}}, "D chloride")
    assert row["limit"] == _literal("COIN_CHLORIDE_MIN_RATIO") and row["pass"] is passes


def test_one_coupon_has_no_bound():
    row = _row({"chloride_ratio_by_coupon": {"arm": [0.95]}}, "D chloride")
    assert row["lower_bound"] is None and "lower bound n/a" in v40.gate_line(row)


# ⚖️ 2026-10-20: both routes are the ISO 5725 limit at 95 % — σ of one scan → 1.96·√2·σ, the lab's r as is.
@pytest.mark.parametrize("band,width,passes,route", [
    ({"cv_scan_sigma": 0.005}, 1.96 * 2 ** 0.5 * 0.005, True, "1.96·√2·σ"),   # limit 0.98614: 0.98750 passes
    ({"cv_scan_sigma": 0.004}, 1.96 * 2 ** 0.5 * 0.004, False, "1.96·√2·σ"),  # limit 0.98891 — √2·σ alone gave 0.99434
    ({"cv_repeatability_r": 0.01}, 0.01, False, "r"),                         # limit 0.99 — r taken as is
])
def test_e_is_judged_against_full_recovery_minus_the_band(band, width, passes, route):
    row = _row({"ucst_recovery_by_coupon": {"arm": [0.99, 0.985]}, **band}, "E recovery")
    assert row["band"] == pytest.approx(width) and row["limit"] == pytest.approx(1.0 - width)
    assert row["measured"] == pytest.approx((0.99 * 0.985) ** 0.5) and row["pass"] is passes
    assert f"[limit = 1 − band {row['band']:.3f}, {route}]" in v40.gate_line(row)


@pytest.mark.parametrize("exp", [
    {"ucst_recovery_by_coupon": {"arm": [0.99, 1.0]}},                          # E without its band
    {"ucst_recovery_by_coupon": {"arm": [0.99]}, "cv_scan_sigma": 0.01, "cv_repeatability_r": 0.02},   # two bands
    {"ucst_recovery_by_coupon": {"arm": [0.99]}, "cv_scan_sigma": 0.4},         # derived band 1.96·√2·0.4 ≥ 1
    {"ucst_recovery_by_coupon": {"arm": [0.99]}, "cv_scan_sigma": "0.01"},      # a string band
    {"ucst_recovery_by_coupon": {"arm": [0.99]}, "cv_repeatability_r": True},   # a bool band
    {"retention_30d_by_coupon": [0.9, 0.88]},                                   # a bare list — no arm named
    {"retention_30d_by_coupon": {"": [0.9]}},                                   # an empty arm label
    {"retention_30d_by_coupon": {"arm": [True, True]}},                         # bools as ratios
    {"retention_30d_by_coupon": {"arm": [float("inf"), 0.9]}},                  # an infinite ratio
    {"chloride_ratio_by_coupon": {"arm": []}},
    {"stability_30d_pct": 92},                                                  # the retired single-coupon key
])
def test_bad_arm_input_refuses(exp):
    with pytest.raises(SystemExit):
        v40.check_keys(exp)
