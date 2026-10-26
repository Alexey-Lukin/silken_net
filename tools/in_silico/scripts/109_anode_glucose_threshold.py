#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""109 — how much glucose the sap must bring to the bore wall for the anchor's anode to feed the node through the
stagnant gap `85` computes (00_07 HW.54, the leg «поріг глюкози біля стінки каналу — скриптом, не оцінкою»).

WHY. The roots check of §01 (HW.54) asks whether the anode's fuel can reach it at all, before any enzyme question: in
the state the HW.53 bench sets by hand — the gap between the gyroid and the bore wall filled with sap that does not
move (`85`'s `sap_gap`) — glucose arrives only by diffusion. A desk estimate of 2026-10-25 put the answer at «≈ 104 µA
per mM at 25 °C, a threshold of ≈ 0.3–0.5 mM»; the leg asked for it computed, with glucose's diffusion coefficient from a
primary source (the tree had none: `D_EFF_GLUCOSE` in lib.constants is a coating's), at the temperatures the sap sees,
and with the boost converter's efficiency AT the small current (02_03 §9.1), not the 0.68 of its table point. The sap's
own glucose is not in the tree either — the logs of HW.3 are where it gets read; this script prices the threshold that
reading will be judged against.

MODEL. The annulus between the gyroid's envelope (radius r_a) and the bore wall (r_b) holds stagnant sap; glucose enters
at the wall at the sap's concentration C_b and is consumed at the envelope at C_s. Steady cylindrical diffusion gives the
envelope flux j = n·F·D·(C_b − C_s)/δ with δ = r_a·ln(r_b/r_a) — `85`'s `annulus_delta_cm`, READ from its cache with the
envelope's area and the bottom cap's share, never recomputed (in-silico §When Modifying #4). So the transport-limited
current per millimolar is S = n·F·D·A/δ (A the envelope's lateral area; `85`'s bottom cap adds its share at the high
end, as `85` brackets its own currents). In series the enzyme at the face delivers I = J_max·A·C_s/(K_M + C_s), the
Michaelis–Menten pair of lib.constants on the ENVELOPE area — the gyroid's real surface is 30–60× larger (lib.constants
A_ELECTRODE), so this overstates the kinetic term, i.e. errs toward a higher threshold. The bulk concentration that
carries a current I is then
    C*(I) = I/S + K_M·I/(J_max·A − I).
J_max is the pH-7.4 laboratory ceiling at 25 °C, carried to the other temperatures by lib.constants EA_ENZYME (an
assumed «typical FAD enzyme» value — named, not sourced); the pH bracket of ⚖️ 2026-09-18 (Sygmund 2011, both forms) is
printed BESIDE the ceiling, never folded in.

D. Glucose's infinite-dilution binary diffusion coefficient in water (Mogi et al. 2007, Taylor dispersion), at the three
temperatures of that record that fall in the sap's range — 273.2, 293.2 and 298.2 K; Ribeiro et al. 2006 (Taylor
dispersion, 298.15 K) is the cross-check. Sap is taken as WATER: no viscosity of pine sap is sourced (the nearest, Wen
et al. 2023, reports conifer sap MORE viscous than poplar's — numbers not read), and a more viscous sap lowers D and
RAISES every threshold here; the sap's own solutes are millimolar, and Ribeiro's −4 % from 2 mM to 0.1 M says
concentration is not the axis that matters.

DEMANDS. The cold start of the BQ25570 (02_03 §1.5): P_IN(CS) at V_IN(CS) typ and max — the same lib constants `85`
reads, and the control checks they reproduce its cached `cold_start_uA`. The sleep drain: P_SLEEP_VSTOR/(η·V) over the
named readings of 02_03 §9.1 — η 0.68 at its table point (~46 µA) and 0.20–0.30 from its text (the curve at ~10 µA);
V_OP 0.5 V (lib) and 0.325 V (its table), ⛔ never merged (⚖️ 2026-09-10). The sleep's input current falls between 10 and
46 µA, where the curve RISES with current, so the 0.20 end overstates the draw — the conservative end, on a stated ground.

WHAT IT CANNOT SEE. Whether a living stem keeps the gap stagnant (sap flow past the face would RAISE the supply; wood
growing into the gap — `85`'s `ingrown` state — has no transport source in the tree); glucose consumed on the way by the
wood's own cells or by microbes (would LOWER the supply); temperatures between 0 and 20 °C other than by bracketing (the
record has no point between); the enzyme's ceiling on etched Ti in sap (lib.constants J_MAX_25C is graphite in phosphate).
CONTROLS. (1) The closed form C*(I) is checked by a FORWARD solve — bisection on the transport ⟷ kinetics balance for
C_s at the computed C*, which must return the demand current; it CAN catch an algebra or unit slip in the inversion and
CANNOT catch a wrong input. (2) δ recomputed from the cached radii must equal the cached δ and sit below the gap (r_a·ln(
r_b/r_a) < r_b − r_a); it CAN catch a geometry read from the wrong field. (3) Mogi and Ribeiro at 25 °C must agree within
1 %; it CAN catch a mistyped D, and CANNOT tell which source is right. (4) Every threshold falls as T rises.
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
    ETA_BQ,
    ETA_BQ_10UA_READING,
    F_CONST,
    J_MAX_25C,
    KM_GLUCOSE,
    N_ELECTRONS,
    P_SLEEP_VSTOR,
    PH_KINETICS_SYGMUND,
    R_GAS,
    REPO_ROOT,
    V_OP,
    V_OP_02_03_TABLE,
)
from lib.utils import banner

SI_DESCRIPTION = ("Glucose supply threshold of the anchor's anode: steady cylindrical diffusion of glucose through a "
                  "stagnant sap-filled gap between the electrode envelope and the bore wall, in series with "
                  "Michaelis-Menten kinetics at the electrode face, inverted for the bulk glucose concentration that "
                  "carries the node's cold-start and sleep currents, using measured infinite-dilution diffusion "
                  "coefficients of glucose in water at 0, 20 and 25 degrees Celsius, with a forward-solve control")

SRC85 = CACHE_DIR / "kinetics" / "electrode_interfacial_ph.json"
OUT = CACHE_DIR / "kinetics" / "anode_glucose_threshold.json"

# D-glucose in water, infinite dilution (m²/s) — Mogi, Sugai, Fuse, Funazukuri, J. Chem. Eng. Data 2007, 52, 40-43
# (Taylor dispersion, 0.1 MPa, 273.2-353.2 K). Read from the NIST TRC ThermoML data record of the paper
# (trc.nist.gov/ThermoML/10.1021/je0601816.xml, the D-glucose/water block); the paper's full text was not accessed.
# Only the three points in the sap's range are kept; the record has none between 273.2 and 293.2 K.
D_GLUCOSE_MOGI = {273.2: 3.23e-10, 293.2: 6.05e-10, 298.2: 6.76e-10}
# Cross-check at 298.15 K — Ribeiro et al., J. Chem. Eng. Data 2006, 51, 1836-1840 (Taylor dispersion), NIST TRC ThermoML
# record of the paper; its lowest concentrations (mol/dm³ → m²/s). No point below 298.15 K.
D_GLUCOSE_RIBEIRO_298 = {0.002: 6.78e-10, 0.005: 6.77e-10, 0.01: 6.76e-10}
T_REF_K = 298.15

SOURCES = {
    "D_glucose": "Mogi N., Sugai E., Fuse Y., Funazukuri T. J. Chem. Eng. Data 2007, 52, 40-43, doi:10.1021/je0601816 — "
                 "NIST TRC ThermoML data record (the paper's full text not accessed)",
    "D_glucose_cross_check": "Ribeiro A.C.F. et al. J. Chem. Eng. Data 2006, 51, 1836-1840, doi:10.1021/je0602061 — "
                             "NIST TRC ThermoML data record (the paper's full text not accessed)",
    "geometry": "85 cache anchor_anode_sap_gap.by_sku[*].geometry (the CEMs as 84 reads them)",
    "cold_start": "lib.constants BQ25570_PIN_CS_UW / BQ25570_VIN_CS_{TYP,MAX}_MV (02_03 §1.5), as 85",
    "sleep": "lib.constants P_SLEEP_VSTOR over ETA_BQ · ETA_BQ_10UA_READING and V_OP · V_OP_02_03_TABLE (02_03 §9.1)",
    "enzyme": "lib.constants J_MAX_25C · KM_GLUCOSE (Zafar 2012, the pH-7.4 ceiling) · EA_ENZYME (assumed) · "
              "PH_KINETICS_SYGMUND (the pH bracket, printed beside)",
}


def _up2(x: float) -> float:
    """A threshold is quoted as «above X the sap carries the draw» — rounded UP keeps that sentence true."""
    return math.ceil(x * 100.0 - 1e-9) / 100.0


def load_85() -> tuple[dict, dict]:
    d = json.loads(SRC85.read_text(encoding="utf-8"))["anchor_anode_sap_gap"]
    return {k: v["geometry"] for k, v in d["by_sku"].items()}, d["cold_start_uA"]


def sensitivity_uA_per_mM(g: dict, d_m2s: float, with_cap: bool) -> float:
    """S = n·F·D·A/δ: µA per mM (1 mM = 1e-6 mol/cm³ and 1 A = 1e6 µA cancel)."""
    area = g["envelope_lateral_area_cm2"] * ((1.0 + g["bottom_cap_over_envelope"]) if with_cap else 1.0)
    return N_ELECTRONS * F_CONST * d_m2s * 1e4 * area / g["annulus_delta_cm"]


def jmax_A_uA(g: dict, t_k: float, kcat_ratio: float = 1.0) -> float:
    arrh = math.exp(-EA_ENZYME / R_GAS * (1.0 / t_k - 1.0 / T_REF_K))
    return J_MAX_25C * arrh * kcat_ratio * g["envelope_lateral_area_cm2"] * 1e6


def threshold_mM(i_uA: float, s: float, jmax_a: float, km: float) -> float:
    if i_uA >= jmax_a:
        raise ValueError(f"demand {i_uA} µA at or above the enzyme ceiling {jmax_a} µA — no finite threshold")
    return i_uA / s + km * i_uA / (jmax_a - i_uA)


def forward_current_uA(c_b: float, s: float, jmax_a: float, km: float) -> float:
    """Control (1): bisection for the face concentration where transport meets kinetics, then the current it carries."""
    lo, hi = 0.0, c_b
    for _ in range(200):
        mid = 0.5 * (lo + hi)
        if s * (c_b - mid) > jmax_a * mid / (km + mid):
            lo = mid
        else:
            hi = mid
    c_s = 0.5 * (lo + hi)
    return s * (c_b - c_s)


def demands() -> dict:
    cold = {"cold_start_typ": BQ25570_PIN_CS_UW / BQ25570_VIN_CS_TYP_MV * 1e3,
            "cold_start_worst_vin": BQ25570_PIN_CS_UW / BQ25570_VIN_CS_MAX_MV * 1e3}
    readings = {f"eta{eta:.2f}_v{v:.3f}": P_SLEEP_VSTOR / (eta * v) * 1e6
                for eta in (ETA_BQ, *ETA_BQ_10UA_READING) for v in (V_OP, V_OP_02_03_TABLE)}
    sleep = {"sleep_optimistic": min(readings.values()), "sleep_adverse": max(readings.values())}
    return {**cold, **sleep, "_sleep_readings_uA": readings}


def ph_bracket() -> dict:
    out = {}
    for form, pts in PH_KINETICS_SYGMUND.items():
        (km55, kc55), (km75, kc75) = pts[5.5], pts[7.5]
        out[form] = {"km_ratio": km55 / km75, "kcat_ratio": kc55 / kc75}
    return out


def main() -> int:
    banner("109 — glucose the sap must bring to the bore wall (00_07 HW.54)")
    geom, cold85 = load_85()
    dem = demands()
    names = [k for k in dem if not k.startswith("_")]
    for k, ref in (("cold_start_typ", "typ"), ("cold_start_worst_vin", "worst")):
        assert round(dem[k], 1) == cold85[ref], f"cold start {k} {dem[k]} does not reproduce 85's cached {cold85[ref]}"
    ribeiro_gap = abs(D_GLUCOSE_RIBEIRO_298[0.002] / D_GLUCOSE_MOGI[298.2] - 1.0)
    assert ribeiro_gap < 0.01, f"Mogi and Ribeiro disagree at 25 °C by {100 * ribeiro_gap:.2f} %"
    phb = ph_bracket()

    by_sku, worst_fwd = {}, 0.0
    for sku, g in sorted(geom.items()):
        delta = g["anode_radius_cm"] * math.log(g["bore_radius_cm"] / g["anode_radius_cm"])
        assert abs(delta - g["annulus_delta_cm"]) < 1e-12, f"{sku}: δ from the radii ≠ the cached δ"
        assert delta < g["bore_radius_cm"] - g["anode_radius_cm"], f"{sku}: δ not below the gap"
        rows = {}
        for t_k, d in sorted(D_GLUCOSE_MOGI.items()):
            s_env, s_cap = sensitivity_uA_per_mM(g, d, False), sensitivity_uA_per_mM(g, d, True)
            ja = jmax_A_uA(g, t_k)
            th = {}
            for n in names:
                i = dem[n]
                c_env = threshold_mM(i, s_env, ja, KM_GLUCOSE)
                c_cap = threshold_mM(i, s_cap, ja, KM_GLUCOSE)
                for c, s in ((c_env, s_env), (c_cap, s_cap)):
                    worst_fwd = max(worst_fwd, abs(forward_current_uA(c, s, ja, KM_GLUCOSE) / i - 1.0))
                beside = {form: threshold_mM(i, s_env, jmax_A_uA(g, t_k, r["kcat_ratio"]), KM_GLUCOSE * r["km_ratio"])
                          for form, r in phb.items()}
                th[n] = {"demand_uA": round(i, 2), "mM": [round(c_cap, 4), round(c_env, 4)],
                         "mM_up": _up2(c_env), "transport_share": round((i / s_env) / c_env, 3),
                         "ph_bracket_mM": {f: round(v, 4) for f, v in beside.items()}}
            rows[f"{t_k:.1f}"] = {"T_C": round(t_k - 273.15, 2), "D_m2_s": d,
                                  "S_uA_per_mM": [round(s_env, 2), round(s_cap, 2)],
                                  "jmax_envelope_uA": round(ja, 1), "thresholds": th}
        by_sku[sku] = {"delta_cm": round(delta, 5), "envelope_cm2": round(g["envelope_lateral_area_cm2"], 3),
                       "cap_share": round(g["bottom_cap_over_envelope"], 4), "by_T_K": rows}
    assert worst_fwd < 1e-9, f"forward solve misses the demand by {worst_fwd:.2e}"
    for sku, b in by_sku.items():
        for n in names:
            seq = [b["by_T_K"][k]["thresholds"][n]["mM"][1] for k in sorted(b["by_T_K"], key=float)]
            assert all(a > c for a, c in itertools.pairwise(seq)), f"{sku} {n}: threshold does not fall as T rises"

    def span(t_key: str, n: str) -> list:
        vals = [b["by_T_K"][t_key]["thresholds"][n]["mM_up"] for b in by_sku.values()]
        return [min(vals), max(vals)]

    shares = [b["by_T_K"][k]["thresholds"][n]["transport_share"] for b in by_sku.values() for k in b["by_T_K"] for n in names]
    pine = by_sku["anchor_zone1_pine"]["by_T_K"]
    findings = {
        "cold_start_typ_mM_by_T": {k: span(k, "cold_start_typ") for k in pine},
        "sleep_adverse_mM_by_T": {k: span(k, "sleep_adverse") for k in pine},
        "sleep_optimistic_mM_by_T": {k: span(k, "sleep_optimistic") for k in pine},
        "pine_S_uA_per_mM_by_T": {k: pine[k]["S_uA_per_mM"] for k in pine},
        "transport_share_min": min(shares),
        "d_ratio_0C_over_25C": round(D_GLUCOSE_MOGI[273.2] / D_GLUCOSE_MOGI[298.2], 3),
    }
    c20, c0, s20 = findings["cold_start_typ_mM_by_T"]["293.2"], findings["cold_start_typ_mM_by_T"]["273.2"], \
        findings["sleep_adverse_mM_by_T"]["293.2"]
    verdict = (f"Through a stagnant sap gap the anode carries the cold-start draw ({dem['cold_start_typ']:.1f} µA) once the "
               f"sap brings {c20[0]:.2f}–{c20[1]:.2f} mM glucose to the bore wall at 20 °C across the Zone-1 SKUs, and "
               f"{c0[0]:.2f}–{c0[1]:.2f} mM at 0 °C (D falls ×{findings['d_ratio_0C_over_25C']:.2f} from 25 to 0 °C); the "
               f"most adverse sleep reading ({dem['sleep_adverse']:.1f} µA) needs {s20[0]:.2f}–{s20[1]:.2f} mM at 20 °C. "
               f"Transport carries at least {100 * findings['transport_share_min']:.0f} % of every threshold at the "
               f"laboratory enzyme ceiling — the threshold is a diffusion number, set by D and the gap, not by the enzyme.")
    result = {
        "script": "109_anode_glucose_threshold.py",
        "question": "the bulk sap glucose at the bore wall that carries the node's cold-start and sleep currents through "
                    "85's stagnant sap gap",
        "model": "C*(I) = I/S + K_M·I/(J_max·A − I), S = n·F·D·A/δ, δ = r_a·ln(r_b/r_a) from 85; mM = [with the bottom "
                 "cap, envelope only]; mM_up = the envelope-only threshold rounded up",
        "sources": SOURCES,
        "D_glucose_m2_s": {f"{k:.1f}": v for k, v in D_GLUCOSE_MOGI.items()},
        "D_cross_check_298_15K": {"ribeiro_2mM": D_GLUCOSE_RIBEIRO_298[0.002], "mogi_298_2K": D_GLUCOSE_MOGI[298.2],
                                  "relative_gap": round(ribeiro_gap, 4)},
        "demands_uA": {n: round(dem[n], 2) for n in names},
        "sleep_readings_uA": {k: round(v, 2) for k, v in dem["_sleep_readings_uA"].items()},
        "ph_bracket_ratios": {f: {k: round(v, 3) for k, v in r.items()} for f, r in phb.items()},
        "by_sku": by_sku,
        "findings": findings,
        "verdict": verdict,
        "controls": {"forward_solve_max_rel_error": worst_fwd, "delta_matches_85": True,
                     "cold_start_reproduces_85": True, "thresholds_fall_with_T": True},
        "cannot_see": ["whether a living stem keeps the gap stagnant (flow raises the supply; ingrowth has no source)",
                       "glucose consumed on the way by wood cells or microbes (lowers the supply)",
                       "temperatures between 0 and 20 °C except as a bracket (no measured D between)",
                       "sap viscosity above water's (would lower D and raise every threshold)",
                       "the enzyme ceiling on etched Ti in sap (J_MAX_25C is graphite in phosphate at pH 7.4)"],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(verdict)
    for k in pine:
        print(f"  pine {k} K: S {pine[k]['S_uA_per_mM'][0]:.1f}–{pine[k]['S_uA_per_mM'][1]:.1f} µA/mM · "
              f"cold typ {pine[k]['thresholds']['cold_start_typ']['mM_up']:.2f} mM · "
              f"sleep {pine[k]['thresholds']['sleep_optimistic']['mM_up']:.2f}–"
              f"{pine[k]['thresholds']['sleep_adverse']['mM_up']:.2f} mM")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
