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
⚠️ `test_gates_judge_on_worst_case_threshold` pins a MACHINE choice — the R_int ceiling judged at
VIN(CS) max — pending ⚖️ 00_07 HW.24 «worst ⊥ typ»; it flips with that verdict, not before.
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
    # R_int at max is a machine choice pending ⚖️ 00_07 HW.24 (worst ⊥ typ); V_OC at max is ratified.
    gates = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 690.0, "R_int_ohm": 1000.0})}
    assert not gates["V_OC >= VIN(CS) max"]["pass"]          # 690 clears typ 600, not max 700
    assert not gates["R_int <= ceiling at VIN(CS) max"]["pass"]
    gates = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 800.0, "R_int_ohm": 4500.0})}
    assert gates["V_OC >= VIN(CS) max"]["pass"] and gates["R_int <= ceiling at VIN(CS) max"]["pass"]
    gates = {g["gate"]: g for g in v40.acceptance_gates({"OCV_mV": 800.0, "R_int_ohm": 5000.0})}
    assert not gates["R_int <= ceiling at VIN(CS) max"]["pass"]   # passes typ (8 kΩ), fails max


def test_gate_row_prints_typ_ceiling_beside_max():
    rows = {g["gate"]: v40.gate_line(g) for g in v40.acceptance_gates({"OCV_mV": 700.0, "R_int_ohm": 3000.0})}
    assert "typ ceiling" not in rows["V_OC >= VIN(CS) max"]
    r_int = rows["R_int <= ceiling at VIN(CS) max"]
    assert "impossible" in r_int and "FAIL" in r_int and r_int.endswith("(typ ceiling 4000)")
    rows = {g["gate"]: v40.gate_line(g) for g in v40.acceptance_gates({"OCV_mV": 600.0, "R_int_ohm": 3000.0})}
    assert rows["R_int <= ceiling at VIN(CS) max"].endswith("(typ ceiling impossible)")


@pytest.mark.parametrize("exp", [
    {"j_max_uA_cm2": 450},                    # the old ambiguous key — must not vanish silently
    {"Rct_ohm": 180},                         # Ω without the window area
    {"R_int_ohm": 4000},                      # a ceiling without V_OC
])
def test_bad_experimental_input_refuses(exp):
    with pytest.raises(SystemExit):
        v40.check_keys(exp)


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
