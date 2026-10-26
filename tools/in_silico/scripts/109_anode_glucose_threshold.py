#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""109 — the glucose the sap must bring to the bore wall BEFORE the anchor's anode can feed the node through the stagnant
gap `85` computes, and what binds first there (00_07 HW.54, the leg «поріг глюкози біля стінки каналу — скриптом, не
оцінкою»).

WHY. The roots check of §01 (HW.54) asks whether the anode's fuel can reach it at all: in the state the HW.53 bench sets by
hand — the gap between the gyroid and the bore wall filled with sap that does not move (`85`'s `sap_gap`) — glucose arrives
only by diffusion. The leg asked for the limiting diffusion current of glucose in that geometry, against the node's sleep
and cold-start draws, with glucose's diffusion coefficient from a primary source and the boost converter's efficiency at
the small current (02_03 §9.1). The sap's own glucose is not in the tree; the logs of HW.3 read it.

WHAT IS PUBLISHED, AND WHICH SIDE IT STANDS ON. A NECESSARY condition: the limiting current through the gap is S·C_b with
S = n·F·D·A/δ, so below C_nec = I/S the gap cannot carry the draw I for ANY enzyme, glucose being the only substrate. It is computed on the side that keeps
«below X it cannot» true — the larger area (`85`'s bottom cap added), D at the top of its stated 95 % uncertainty, the
smallest reading of the draw — and rounded DOWN. It is not a sufficient condition and is never written as one: the
unpriced axes (sap more viscous than water, glucose eaten on the way, the enzyme's ceiling on Ti in sap, only the β-anomer
being the enzyme's substrate, the wall's own resistance) raise the true threshold — xylose, the enzyme's other substrate,
is the one that would lower it — and in this same stagnant gap the face FIRST leaves the enzyme's MEASURED pH window (pH
5.5, the acid end of its kinetics — not a stop): `85`'s currents for that edge lie below the draws here in almost every
reading. That half is read from `85`'s cache and printed beside each draw; this script adds nothing to its model.

MODEL. δ = r_a·ln(r_b/r_a), the envelope's lateral area and the bottom cap's share are READ from `85`'s cache, never
recomputed (in-silico §When Modifying #4). Beside the necessary threshold an ESTIMATE in series with the enzyme is printed —
C* = I/S + K_M·I/(J_max·A − I) on the envelope area at the pH-7.4 laboratory ceiling, carried to temperature by two Ea
readings (Sygmund 2011's measured 19.5 kJ/mol for this enzyme above 26 °C; lib EA_ENZYME's assumed 40), with the same
paper's pH bracket beside it — whether the envelope area over- or understates the kinetic term is NOT established (the
porous layer's penetration depth decides), so the estimate carries no direction.

D. Glucose's infinite-dilution binary diffusion coefficient in water (Mogi et al. 2007, Taylor dispersion), at the record's
three points in the sap's range — 273.2, 293.2 and 298.2 K — with the record's 95 % expanded uncertainty (assigned by the
TRC compiler; its unit is not printed, and it reads as 1e-9 m²/s by its ratio to the values, ≈ 6.5–7.1 %); Ribeiro et al.
2006 (Taylor dispersion, 298.15 K) is the cross-check. Sap is taken as WATER (no viscosity of pine sap is sourced).

DRAWS. The BQ25570 cold start, P_IN(CS) at V_IN(CS) typ and max (02_03 §1.5) — an input current already. The sleep loads at
VSTOR — §9.6 Scenario C's target 4.18 µW (its mechanism refuted, FW.54; the target stands), the shipped STOP2 9.26 µW
(§9.3), and the shipped STOP2 plus §9.3's own illustration of a 1 µA EDLC leak (+4.5 µW, not a measurement) — turned into
an input current by the boost: I·η(I)·V = P at V_OP 0.5 V (lib) or 0.325 V (§9.1 table) — both kept, their hull
published, neither chosen. η(I) is known only at anchors, each an INTERVAL — 0.20–0.30 at ~10 µA (§9.1 text) and the
table's 0.68 · 0.75 · 0.82 at its own currents, each ± §9.1's own read error (±0.15) — so the input current is BRACKETED,
not solved: with η non-decreasing in I (the datasheet curves rise over this range, §9.1), the root lies between the roots
of the two extreme step curves the intervals allow (the most efficient and the least).

WHAT IT CANNOT SEE. Whether a living stem keeps the gap stagnant (flow raises the supply; wood grown into the gap has no
transport source in the tree); glucose consumed on the way by wood cells or microbes; the α-anomer (the enzyme oxidises
β-D-glucose — Sygmund 2011 — so α must mutarotate during its passage; slow mutarotation raises the threshold); xylose, the
enzyme's other substrate (lowers it, if present); the wall's resistance (embolised tracheids, resin); temperatures between 0
and 20 °C other than by bracketing; the proton half at 20 and 0 °C (`85` prices 25 °C; smaller diffusivities there lower its
currents further); the enzyme's ceiling on etched Ti in sap.

CONTROLS. (1) Every series estimate is checked by a forward solve (bisection on transport = kinetics at the face) that must
return the draw — CAN catch an algebra or unit slip, CANNOT a wrong input. (2) δ from the cached radii equals the cached δ
and sits below the gap — CAN catch a geometry read from the wrong field. (3) Mogi and Ribeiro at 25 °C agree within 1 % and
Mogi's 20/25 °C ratio sits within 5 % of the Stokes–Einstein ratio T/η_water (IAPWS viscosities, NIST WebBook) — CAN catch a
mistyped D at those two temperatures; the 0 °C point has no viscosity in the tree and is not controlled. (4) Each sleep
bracket's closed form is re-found by bisection on the same two extreme step curves — CAN catch a slip in the closed form,
CANNOT a wrong anchor (it shares them).
"""

from __future__ import annotations

import itertools
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    BQ25570_PIN_CS_UW,
    BQ25570_VIN_CS_MAX_MV,
    BQ25570_VIN_CS_TYP_MV,
    CACHE_DIR,
    EA_ENZYME,
    EA_SYGMUND_GCGDH,
    ETA_BOOST_TABLE_UW,
    ETA_BQ_10UA_READING,
    ETA_TABLE_READ_ERROR,
    F_CONST,
    J_MAX_25C,
    KM_GLUCOSE,
    N_ELECTRONS,
    P_EDLC_LEAK_1UA_ILLUSTRATION,
    P_SLEEP_VSTOR,
    P_SLEEP_VSTOR_STOP2,
    PH_KINETICS_SYGMUND,
    R_GAS,
    REPO_ROOT,
    V_OP,
    V_OP_02_03_TABLE,
)
from lib.utils import banner

SI_DESCRIPTION = ("Glucose supply threshold of the anchor's anode: the limiting current of steady cylindrical glucose "
                  "diffusion through a stagnant sap-filled gap between the electrode envelope and the bore wall gives "
                  "the bulk glucose concentration below which the node's cold-start and sleep currents cannot be "
                  "carried, from measured diffusion coefficients of glucose in water at 0, 20 and 25 degrees Celsius "
                  "with their uncertainty; sleep currents are bracketed on a non-decreasing boost-efficiency curve, a "
                  "series estimate with Michaelis-Menten kinetics is printed beside, and the interfacial proton limit "
                  "of the same gap is read from a companion model")

SRC85 = CACHE_DIR / "kinetics" / "electrode_interfacial_ph.json"
OUT = CACHE_DIR / "kinetics" / "anode_glucose_threshold.json"

# D-glucose in water, infinite dilution (m²/s), and the record's 95 % expanded uncertainty as printed (unit not given;
# read as 1e-9 m²/s by its ratio to the values) — Mogi, Sugai, Fuse, Funazukuri, J. Chem. Eng. Data 2007, 52, 40-43
# (Taylor dispersion, 0.1 MPa, 273.2-353.2 K), NIST TRC ThermoML data record (trc.nist.gov/ThermoML/10.1021/je0601816.xml,
# the D-glucose/water block); the paper's full text was not accessed. No point between 273.2 and 293.2 K.
D_GLUCOSE_MOGI = {273.2: 3.23e-10, 293.2: 6.05e-10, 298.2: 6.76e-10}
U_GLUCOSE_MOGI_PRINTED = {273.2: 0.023, 293.2: 0.040, 298.2: 0.044}
U_UNIT_READ = 1e-9
# Ribeiro et al., J. Chem. Eng. Data 2006, 51, 1836-1840 (Taylor dispersion, 298.15 K), NIST TRC ThermoML record.
D_GLUCOSE_RIBEIRO_298 = {0.002: 6.78e-10, 0.005: 6.77e-10, 0.01: 6.76e-10}
# Water viscosity (µPa·s) at 0.101325 MPa, NIST Chemistry WebBook (IAPWS formulation): 293.15 K → 1001.60, 298.15 K → 890.022.
ETA_WATER_UPAS = {293.15: 1001.60, 298.15: 890.022}
T_REF_K = 298.15
I_ETA_10UA = 10.0  # µA — the current at which 02_03 §9.1's text reads η 0.20-0.30

SOURCES = {
    "D_glucose": "Mogi N., Sugai E., Fuse Y., Funazukuri T. J. Chem. Eng. Data 2007, 52, 40-43, doi:10.1021/je0601816 — "
                 "NIST TRC ThermoML data record (the paper's full text not accessed)",
    "D_glucose_cross_check": "Ribeiro A.C.F. et al. J. Chem. Eng. Data 2006, 51, 1836-1840, doi:10.1021/je0602061 — "
                             "NIST TRC ThermoML data record (the paper's full text not accessed)",
    "water_viscosity": "NIST Chemistry WebBook, Thermophysical Properties of Fluid Systems (IAPWS), isobar 0.101325 MPa",
    "geometry_and_proton_limit": "85 cache anchor_anode_sap_gap.by_sku[*] (geometry; face_pH_5.5 / face_pH_4.5 at 25 °C)",
    "cold_start": "lib.constants BQ25570_PIN_CS_UW / BQ25570_VIN_CS_{TYP,MAX}_MV (02_03 §1.5), as 85",
    "sleep": "lib.constants P_SLEEP_VSTOR (02_03 §9.6 target) · P_SLEEP_VSTOR_STOP2 · P_EDLC_LEAK_1UA_ILLUSTRATION "
             "(02_03 §9.3) through ETA_BQ_10UA_READING · ETA_BOOST_TABLE_UW at V_OP · V_OP_02_03_TABLE (02_03 §9.1)",
    "enzyme": "lib.constants J_MAX_25C · KM_GLUCOSE (Zafar 2012) · EA_SYGMUND_GCGDH (Sygmund 2011, measured) · EA_ENZYME "
              "(assumed) · PH_KINETICS_SYGMUND (Sygmund 2011)",
}


def _down2(x: float) -> float:
    """A necessary threshold is quoted as «below X the gap cannot carry the draw» — rounded DOWN keeps that true."""
    return math.floor(x * 100.0 + 1e-9) / 100.0


def load_85() -> dict:
    return json.loads(SRC85.read_text(encoding="utf-8"))["anchor_anode_sap_gap"]


def sensitivity_uA_per_mM(g: dict, d_m2s: float, with_cap: bool) -> float:
    """S = n·F·D·A/δ: µA per mM (1 mM = 1e-6 mol/cm³ and 1 A = 1e6 µA cancel)."""
    area = g["envelope_lateral_area_cm2"] * ((1.0 + g["bottom_cap_over_envelope"]) if with_cap else 1.0)
    return N_ELECTRONS * F_CONST * d_m2s * 1e4 * area / g["annulus_delta_cm"]


def jmax_A_uA(g: dict, t_k: float, ea: float, kcat_ratio: float = 1.0) -> float:
    return J_MAX_25C * math.exp(-ea / R_GAS * (1.0 / t_k - 1.0 / T_REF_K)) * kcat_ratio \
        * g["envelope_lateral_area_cm2"] * 1e6


def series_mM(i_uA: float, s: float, jmax_a: float, km: float) -> float:
    if i_uA >= jmax_a:
        raise ValueError(f"draw {i_uA} µA at or above the enzyme ceiling {jmax_a} µA — no finite threshold")
    return i_uA / s + km * i_uA / (jmax_a - i_uA)


def forward_current_uA(c_b: float, s: float, jmax_a: float, km: float) -> float:
    lo, hi = 0.0, c_b
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if s * (c_b - mid) > jmax_a * mid / (km + mid):
            lo = mid
        else:
            hi = mid
    return s * (c_b - 0.5 * (lo + hi))


def eta_anchors() -> list[tuple[float, float, float]]:
    """(current µA, η low, η high) — 02_03 §9.1: the text's ~10 µA reading, then the table's points at its own V_OP, each
    widened by the table's own read error (ETA_TABLE_READ_ERROR) — the canon gives them as eye-readings, not points."""
    out = [(I_ETA_10UA, *ETA_BQ_10UA_READING)]
    out += [(p / (V_OP_02_03_TABLE * 1e3) * 1e3, max(0.0, eta - ETA_TABLE_READ_ERROR), min(1.0, eta + ETA_TABLE_READ_ERROR))
            for p, eta in ETA_BOOST_TABLE_UW]
    return out


def _envelope_root(y: float, fast: bool) -> float:
    """The root of I·η(I) = y on the extreme step curve the anchors allow for a non-decreasing η: the most efficient one
    (fast — η = the NEXT anchor's high end on each segment, the smallest root) or the least (η = this anchor's low end, the
    largest root). Closed form: inside a segment the root is y/η; where the product jumps past y, it is the jump point."""
    anchors = eta_anchors()
    for (i0, e0lo, _e0hi), (i1, _e1lo, e1hi) in itertools.pairwise(anchors):
        if fast:
            if y <= i0 * e1hi:
                return i0
            if y <= i1 * e1hi:
                return y / e1hi
        else:
            if y <= i0 * e0lo:
                return i0
            if y < i1 * e0lo:
                return y / e0lo
    raise ValueError(f"P/V = {y:.2f} µA·η lies above the efficiency anchors of 02_03 §9.1")


def input_bracket_uA(p_w: float, v: float) -> list[float]:
    """The input current I with I·η(I)·V = P, over every non-decreasing η(I) through the anchor INTERVALS: between the
    roots of the two extreme step curves. Refuses a load whose root could lie below the first anchor (no reading there)."""
    y = p_w / v * 1e6  # µA·η
    i0, _e0lo, e0hi = eta_anchors()[0]
    if y < i0 * e0hi:
        raise ValueError(f"P/V = {y:.2f} µA·η: the root may lie below {i0} µA, where 02_03 §9.1 has no reading")
    return [_envelope_root(y, True), _envelope_root(y, False)]


def step_root_uA(p_w: float, v: float, fast: bool) -> float:
    """Control (4): the same extreme step curve's root by BISECTION on I·η_step(I) = P/V — a route independent of the
    closed form above (it shares only the anchors, which it is not meant to check)."""
    y = p_w / v * 1e6
    anchors = eta_anchors()

    def eta_at(i: float) -> float:
        for (i0, e0lo, _e0hi), (i1, _e1lo, e1hi) in itertools.pairwise(anchors):
            if (i0 < i <= i1) if fast else (i0 <= i < i1):
                return e1hi if fast else e0lo
        return anchors[0][2] if fast else anchors[-1][1]

    lo, hi = anchors[0][0], anchors[-1][0]
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if mid * eta_at(mid) < y:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def draws() -> tuple[dict, dict]:
    """Every draw as [low, high] µA; the sleep loads also per V_OP (both kept — the hull is published, neither chosen)."""
    out = {"cold_start_typ": [BQ25570_PIN_CS_UW / BQ25570_VIN_CS_TYP_MV * 1e3] * 2,
           "cold_start_worst_vin": [BQ25570_PIN_CS_UW / BQ25570_VIN_CS_MAX_MV * 1e3] * 2}
    by_v = {}
    loads = {"sleep_scenario_c_target": P_SLEEP_VSTOR, "sleep_stop2_shipped": P_SLEEP_VSTOR_STOP2,
             "sleep_stop2_plus_edlc_1uA": P_SLEEP_VSTOR_STOP2 + P_EDLC_LEAK_1UA_ILLUSTRATION}
    for name, p in loads.items():
        by_v[name] = {}
        for v in (V_OP, V_OP_02_03_TABLE):
            b = input_bracket_uA(p, v)
            for fast, end in ((True, 0), (False, 1)):
                r = step_root_uA(p, v, fast)
                assert abs(r - b[end]) < 1e-6 * max(1.0, b[end]), f"{name} @ {v} V: closed form ≠ bisection ({b[end]} vs {r})"
            by_v[name][f"{v:.3f}"] = b
        out[name] = [min(b[0] for b in by_v[name].values()), max(b[1] for b in by_v[name].values())]
    return out, by_v


def flag(draw: list, limit: list) -> str:
    """Against 85's current bracket at a face pH edge: beyond it in every reading, in some, or in none."""
    if draw[0] > limit[1]:
        return "every"
    return "some" if draw[1] > limit[0] else "none"


def main() -> int:
    banner("109 — the glucose the sap must bring to the bore wall (00_07 HW.54)")
    a85 = load_85()
    dr, dr_by_v = draws()
    for k, ref in (("cold_start_typ", "typ"), ("cold_start_worst_vin", "worst")):
        assert round(dr[k][0], 1) == a85["cold_start_uA"][ref], f"cold start {k} does not reproduce 85's cache"
    ribeiro_gap = abs(D_GLUCOSE_RIBEIRO_298[0.002] / D_GLUCOSE_MOGI[298.2] - 1.0)
    assert ribeiro_gap < 0.01, f"Mogi and Ribeiro disagree at 25 °C by {100 * ribeiro_gap:.2f} %"
    se_pred = (293.15 / 298.15) * (ETA_WATER_UPAS[298.15] / ETA_WATER_UPAS[293.15])
    se_meas = D_GLUCOSE_MOGI[293.2] / D_GLUCOSE_MOGI[298.2]
    assert abs(se_meas / se_pred - 1.0) < 0.05, f"Mogi 20/25 °C ratio {se_meas:.3f} vs Stokes–Einstein {se_pred:.3f}"
    phb = {f: {"km_ratio": p[5.5][0] / p[7.5][0], "kcat_ratio": p[5.5][1] / p[7.5][1]}
           for f, p in PH_KINETICS_SYGMUND.items()}
    eas = {"ea_19.5_measured": EA_SYGMUND_GCGDH, "ea_40_assumed": EA_ENZYME}

    by_sku, worst_fwd = {}, 0.0
    for sku, blk in sorted(a85["by_sku"].items()):
        g = blk["geometry"]
        delta = g["anode_radius_cm"] * math.log(g["bore_radius_cm"] / g["anode_radius_cm"])
        assert abs(delta - g["annulus_delta_cm"]) < 1e-12, f"{sku}: δ from the radii ≠ the cached δ"
        assert delta < g["bore_radius_cm"] - g["anode_radius_cm"], f"{sku}: δ not below the gap"
        proton = {e: blk[f"face_pH_{e}"]["i_anode_uA"] for e in ("5.5", "4.5")}
        rows = {}
        for t_k, d in sorted(D_GLUCOSE_MOGI.items()):
            u = U_GLUCOSE_MOGI_PRINTED[t_k] * U_UNIT_READ
            s_max, s_min = sensitivity_uA_per_mM(g, d + u, True), sensitivity_uA_per_mM(g, d - u, False)
            s_env = sensitivity_uA_per_mM(g, d, False)
            th = {}
            for name, (i_lo, i_hi) in dr.items():
                est = {}
                for ek, ea in eas.items():
                    ja = jmax_A_uA(g, t_k, ea)
                    c = series_mM(i_hi, s_env, ja, KM_GLUCOSE)
                    worst_fwd = max(worst_fwd, abs(forward_current_uA(c, s_env, ja, KM_GLUCOSE) / i_hi - 1.0))
                    ph = {f: round(series_mM(i_hi, s_env, jmax_A_uA(g, t_k, ea, r["kcat_ratio"]),
                                             KM_GLUCOSE * r["km_ratio"]), 4) for f, r in phb.items()}
                    est[ek] = {"mM": round(c, 4), "transport_share": round((i_hi / s_env) / c, 3), "ph_bracket_mM": ph}
                th[name] = {"draw_uA": [round(i_lo, 2), round(i_hi, 2)],
                            "necessary_mM": [_down2(i_lo / s_max), _down2(i_hi / s_max)],
                            "series_estimate_at_draw_high": est}
            rows[f"{t_k:.1f}"] = {"T_C": round(t_k - 273.15, 2), "D_m2_s": d, "U_m2_s": u,
                                  "S_uA_per_mM": [round(s_min, 2), round(s_max, 2)],
                                  "S_envelope_D_uA_per_mM": round(s_env, 2), "thresholds": th}
        by_sku[sku] = {"delta_cm": round(delta, 5), "envelope_cm2": round(g["envelope_lateral_area_cm2"], 3),
                       "cap_share": round(g["bottom_cap_over_envelope"], 4), "proton_limit_25C_uA": proton,
                       "beyond_proton_limit_25C": {n: {e: flag(dr[n], proton[e]) for e in proton} for n in dr},
                       "by_T_K": rows}
    assert worst_fwd < 1e-9, f"forward solve misses the draw by {worst_fwd:.2e}"

    def span(t_key: str, n: str, end: int) -> list:
        vals = [b["by_T_K"][t_key]["thresholds"][n]["necessary_mM"][end] for b in by_sku.values()]
        return [min(vals), max(vals)]

    pine = by_sku["anchor_zone1_pine"]
    temps = list(pine["by_T_K"])
    flags55 = [b["beyond_proton_limit_25C"][n]["5.5"] for b in by_sku.values() for n in dr]
    findings = {
        "necessary_cold_start_typ_mM_by_T": {k: span(k, "cold_start_typ", 0) for k in temps},
        "necessary_sleep_stop2_mM_by_T": {k: span(k, "sleep_stop2_shipped", 0) for k in temps},
        "necessary_sleep_target_mM_by_T": {k: span(k, "sleep_scenario_c_target", 0) for k in temps},
        "pine_S_uA_per_mM_by_T": {k: pine["by_T_K"][k]["S_uA_per_mM"] for k in temps},
        "pine_necessary_cold_start_typ_mM_by_T": {k: pine["by_T_K"][k]["thresholds"]["cold_start_typ"]["necessary_mM"][0]
                                                  for k in temps},
        "draws_beyond_pH55_in_every_reading": flags55.count("every"),
        "draws_x_skus": len(flags55),
        "pine_cold_start_typ_beyond_pH45": pine["beyond_proton_limit_25C"]["cold_start_typ"]["4.5"],
        "d_ratio_0C_over_25C": round(D_GLUCOSE_MOGI[273.2] / D_GLUCOSE_MOGI[298.2], 3),
    }
    c20, c0 = findings["necessary_cold_start_typ_mM_by_T"]["293.2"], findings["necessary_cold_start_typ_mM_by_T"]["273.2"]
    every = findings["draws_beyond_pH55_in_every_reading"] == findings["draws_x_skus"]
    verdict = (f"Necessary, not sufficient: below {c20[0]:.2f}–{c20[1]:.2f} mM of glucose at the bore wall (20 °C, across the "
               f"Zone-1 parts; {c0[0]:.2f}–{c0[1]:.2f} mM at 0 °C) a stagnant sap gap cannot carry the cold-start draw "
               f"({dr['cold_start_typ'][0]:.1f} µA) for any enzyme, glucose being the only substrate. In the same gap the "
               "face first leaves the enzyme's measured pH window: "
               + ("every draw here exceeds, in every reading, the current at which 85's face leaves the enzyme's kinetic "
                  "bracket (pH 5.5) at 25 °C" if every else
                  f"{findings['draws_beyond_pH55_in_every_reading']} of {findings['draws_x_skus']} draw×part pairs exceed, "
                  "in every reading, the current at which 85's face leaves the enzyme's kinetic bracket (pH 5.5) at 25 °C")
               + ", and on pine the cold start reaches pH 4.5 "
               + {"every": "in every reading", "some": "in some readings", "none": "in none"}[findings["pine_cold_start_typ_beyond_pH45"]]
               + " "
               "— so sap above the threshold does not by itself keep the face inside that window.")
    result = {
        "script": "109_anode_glucose_threshold.py",
        "question": "the bulk sap glucose at the bore wall below which 85's stagnant sap gap cannot carry the node's "
                    "cold-start and sleep draws, and what binds first in that gap",
        "model": "necessary: C_nec = I/S, S = n·F·D·A/δ on the side that keeps «below X it cannot» true (bottom cap added, "
                 "D + U, the draw's low end; rounded down); S_uA_per_mM = [envelope at D − U, with the cap at D + U]; "
                 "series estimate C* = I/S + K_M·I/(J_max·A − I) on the envelope at D and the draw's high end, per Ea",
        "sources": SOURCES,
        "D_glucose_m2_s": {f"{k:.1f}": v for k, v in D_GLUCOSE_MOGI.items()},
        "U_glucose_m2_s": {f"{k:.1f}": v * U_UNIT_READ for k, v in U_GLUCOSE_MOGI_PRINTED.items()},
        "D_controls": {"ribeiro_2mM_vs_mogi_298": round(ribeiro_gap, 4),
                       "stokes_einstein_20_25_predicted": round(se_pred, 4), "mogi_20_25_measured": round(se_meas, 4)},
        "eta_anchors_uA": [[round(i, 2), lo, hi] for i, lo, hi in eta_anchors()],
        "draws_uA": {n: [round(v[0], 2), round(v[1], 2)] for n, v in dr.items()},
        "sleep_draws_by_v_op_uA": {n: {v: [round(b[0], 2), round(b[1], 2)] for v, b in d.items()} for n, d in dr_by_v.items()},
        "ph_bracket_ratios": {f: {k: round(v, 3) for k, v in r.items()} for f, r in phb.items()},
        "by_sku": by_sku,
        "findings": findings,
        "verdict": verdict,
        "controls": {"forward_solve_max_rel_error": worst_fwd, "delta_matches_85": True, "cold_start_reproduces_85": True,
                     "sleep_brackets_contain_step_roots": True},
        "cannot_see": ["whether a living stem keeps the gap stagnant (flow raises the supply; ingrowth has no source)",
                       "glucose consumed on the way by wood cells or microbes (raises the threshold)",
                       "the α-anomer: the enzyme oxidises β-D-glucose, slow mutarotation raises the threshold",
                       "xylose, the enzyme's other substrate (lowers it, if present)",
                       "the bore wall's own resistance — embolised tracheids, resin (raises it)",
                       "sap viscosity above water's (raises it)",
                       "temperatures between 0 and 20 °C except as a bracket; the proton half below 25 °C",
                       "the enzyme ceiling on etched Ti in sap; whether the envelope area over- or understates the "
                       "kinetic term (not established — the series estimate carries no direction)"],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(verdict)
    for k in temps:
        r = pine["by_T_K"][k]
        print(f"  pine {k} K: S {r['S_uA_per_mM'][0]:.1f}–{r['S_uA_per_mM'][1]:.1f} µA/mM · necessary: cold typ "
              f"{r['thresholds']['cold_start_typ']['necessary_mM'][0]:.2f} · STOP2 "
              f"{r['thresholds']['sleep_stop2_shipped']['necessary_mM'][0]:.2f} mM")
    print("  draws µA:", {n: [round(v[0], 1), round(v[1], 1)] for n, v in dr.items()})
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
