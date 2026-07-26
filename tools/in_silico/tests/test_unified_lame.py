# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Unit gates for the unified thick-wall Lamé core (lib.mechanics) — HW.3.IS.

Pure stdlib + pytest (no numpy / conda), CI-safe like test_cache_integrity. Validates the
analytical INVARIANTS, not a frozen headline number: zero-interference → zero-stress, exact
linear superposition (the basis for combining press-fit + thermal in one model), cold-tightening
monotonicity, and a physical combined worst-case band (catches the 1.4× artifact + gross errors).
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    E_PEEK_PA,
    H7S6_INTERF_DIA_MAX_UM,
    NU_PEEK,
    R_INTERFACE_M,
    R_OUTER_M,
    SIGMA_YIELD_PEEK_PA,
    T_ASSEMBLY_C,
    T_FOREST_MIN_C,
)
from lib.mechanics import thermal_interference, thick_wall_hoop

B, C = R_INTERFACE_M, R_OUTER_M
ALPHA_TI = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]


def _hoop(delta: float) -> dict:
    return thick_wall_hoop(delta, B, C, E_PEEK_PA, NU_PEEK)


def test_zero_interference_zero_stress():
    s = _hoop(0.0)
    assert abs(s["P_c"]) < 1e-9
    assert abs(s["sigma_t"]) < 1e-9
    assert abs(s["sigma_vm"]) < 1e-9


def test_linear_superposition():
    # P_c linear in δ → σ_t(δ1+δ2) == σ_t(δ1)+σ_t(δ2): the basis for combining press-fit + thermal.
    d1, d2 = 5e-6, 11e-6
    combined = _hoop(d1 + d2)["sigma_t"]
    summed = _hoop(d1)["sigma_t"] + _hoop(d2)["sigma_t"]
    assert math.isclose(combined, summed, rel_tol=1e-12)


def test_bore_stress_state():
    s = _hoop(10e-6)
    assert math.isclose(s["sigma_r"], -s["P_c"], rel_tol=1e-12)   # radial at bore = −contact pressure
    assert s["sigma_t"] > 0 > s["sigma_r"]                          # tensile hoop, compressive radial
    assert s["sigma_vm"] > s["sigma_t"]                            # von Mises > σ_t (mixed tension/compression)


def test_cold_tightens_interference():
    # higher-CTE PEEK shrinks onto the Ti shaft on cooling → interference grows below assembly temp
    cold = thermal_interference(T_FOREST_MIN_C, T_ASSEMBLY_C, ALPHA_PEEK_1K, ALPHA_TI, B)
    warm = thermal_interference(40.0, T_ASSEMBLY_C, ALPHA_PEEK_1K, ALPHA_TI, B)
    at_assembly = thermal_interference(T_ASSEMBLY_C, T_ASSEMBLY_C, ALPHA_PEEK_1K, ALPHA_TI, B)
    assert cold > 0
    assert abs(at_assembly) < 1e-15
    assert warm < 0


def test_combined_worst_case_physical():
    # −30°C + s6-max = the design-critical corner: below yield, with a comfortable (not 1.4×) margin.
    d_mech = H7S6_INTERF_DIA_MAX_UM * 1e-6 / 2.0
    d_th = thermal_interference(T_FOREST_MIN_C, T_ASSEMBLY_C, ALPHA_PEEK_1K, ALPHA_TI, B)
    s = _hoop(d_mech + d_th)
    sf = SIGMA_YIELD_PEEK_PA / s["sigma_t"]
    assert s["sigma_t"] < SIGMA_YIELD_PEEK_PA      # below PEEK yield
    assert 3.0 < sf < 12.0                          # comfortable, sane band (not the 1.4× artifact)
