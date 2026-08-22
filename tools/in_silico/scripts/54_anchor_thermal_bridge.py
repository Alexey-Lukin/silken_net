#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 — Axial thermal-bridge analysis of the central bus conductor through the Zone-2 PEEK break.

The three-zone anchor (01_01 §1) breaks the Ti thermal short with a PEEK sleeve (Zone 2) so winter
surface cold does NOT pipe down to the living sapwood around the Zone-1 anode (§4.1). But ONE conductor
crosses the break unavoidably: the central electrical BUS that carries the anode (EBFC V−/GND) up to the
pogo pad (01_01 §2/§4.1, 02_02 §1.2). 01_01 §4.1 specs it "~1–2 mm², minimal cross-section" and asserts
"thin bus ≫ thermal resistance than solid Ti" — but never QUANTIFIES the residual leak, and writes the
material ambiguously ("анодний вал / Cu-провідник"). This script closes that: how much does the bus
defeat the PEEK break, and does the MATERIAL (Cu vs Ti-monolithic vs steel) matter?

KEY GEOMETRY INSIGHT (why a naïve "λA/L through 50 mm PEEK" is wrong): the Ti shanks of Zone 1 (anode,
Ø11) and Zone 3 (cathode, Ø9) press IN from both ends and bridge most of the 50 mm sleeve; the only
PEEK/air-dominated gap is L_g = 50 − L_a − L_c (≈6 mm at the F2 placeholder insertions). So the heat
path is a resistor LADDER (Z3-shank ∥ bus → gap ∥ bus → Z1-shank ∥ bus), in parallel with the
continuous PEEK sleeve WALL (Ø11→Ø15). The bus is the one conductor continuous across the whole break.

Model: 1D lumped resistor network, steady state. The Zone-1 anode pocket (living sapwood, the at-risk
tissue) sits between the cold flange (≈ T_air, flush Ti disc) via the anchor and the warm deep-trunk
reservoir (T_deep) via a wood spreading resistance. T_anode is a thermal voltage-divider. The ABSOLUTE
T_anode depends on the uncertain wood reservoir (λ_wood, R_res, T_deep) → swept; the COMPARATIVE result
(Cu vs Ti bus) is robust because R_wood is identical across materials and the bus term swamps (Cu) or
vanishes (Ti) regardless. A full 3D conjugate model is bench/FEA-side (no COMSOL here).

No FEA / no DFT — closed-form thermal resistance ladder (numpy for the sweep + matplotlib summary).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import ALLOY_PROPERTIES, CACHE_DIR, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Thermal conductivities λ (W/m·K), literature ──
LAMBDA_TI = 6.7        # Ti-6Al-4V (CLAUDE.md §3 / 01_01 §4.1; ASM ~6.7 at RT) — the anode/shank metal
LAMBDA_CU = 400.0      # pure annealed Cu (CRC ~401; ETP 390-400) — the "Cu bus" baseline material
LAMBDA_316SS = 15.0    # 316 stainless — a low-λ metallic alternative bus material
LAMBDA_PEEK = 0.25     # PEEK 450G (01_01 §4.1; Victrex datasheet 0.25) — the thermal-break dielectric
LAMBDA_AIR = 0.026     # still air in the gap void (negligible vs the bus)
# Wet sapwood is water-laden; radial λ of green conifer wood ~0.2-0.5 (FPL Wood Handbook, MC>60%).
LAMBDA_WOOD_BASE = 0.30   # baseline radial λ of wet Pinus sapwood
LAMBDA_WOOD_SWEEP = (0.20, 0.30, 0.40, 0.50)
# Living parenchyma tolerates mild sub-zero (supercooling + solute/osmotic freezing-point depression);
# lethal intracellular ice nucleation is nearer −2…−5 °C, not a hard 0. Soft cell-damage threshold:
CELL_FREEZE_C = -2.0      # °C — below this the anode-pocket living tissue is at ice-nucleation risk

# ── Electrical resistivity ρ (Ω·m) — to prove the bus material is electrically free at µA ──
RHO_CU = 1.68e-8       # annealed Cu
RHO_TI = 1.78e-6       # Ti-6Al-4V (~170 µΩ·cm — 100× worse than Cu, still irrelevant at µA)
RHO_316SS = 7.4e-7

# ── Density ρ (kg/m³) + specific heat c (J/kg·K) — for the transient time-constant only ──
RHO_C_TI = 4430.0 * 560.0      # Ti-6Al-4V volumetric heat capacity (ρ from lib ALLOY_PROPERTIES, c≈560)
RHO_C_WOODWET = 900.0 * 2500.0  # wet sapwood (ρ≈900 green, c≈2500 water-laden)
TI_SOLID_FRACTION = 0.35        # gyroid is 65% porous → 35% solid Ti (01_01 §1, porosity 60-70%)

# ── Geometry (mm), FROZEN dims (HW.33, 2026-06-20; mirrors script 50 + CEM manifests) ──
D_SLEEVE_OUT = 15.0    # PEEK sleeve OD (= wound Ø, 01_01 §4.2)
D_SLEEVE_BORE = 11.0   # PEEK bore = Zone-1 shaft Ø (zone2_sleeve.json)
D_Z1_SHANK = 11.0      # Zone-1 anode shank OD (mechanical_lock.zone1.json)
D_Z3_SHANK = 9.0       # Zone-3 cathode shank OD (cathode_flange.json / mechanical_lock.zone3.json)
D_BORE_ANODE = 1.6     # bus bore in the anode shank (anchor_zone1.pine.json; = script 50 R_INNER Ø1.6)
D_BORE_CATHODE = 1.3   # bus bore through the cathode shank+flange (cathode_flange.json) — the BOTTLENECK
L_SLEEVE = 50.0        # PEEK break axial length (01_01 §4.1, frozen)
# Shank insertion placeholders (F2 axial-stack: 50 − 30 − 14 = 6 mm gap). These are HW.8 placeholders →
# the gap (effective PEEK break) is itself a design lever, swept below.
L_A_INSERT = 30.0      # Zone-1 anode shank insertion into the sleeve
L_C_INSERT = 14.0      # Zone-3 cathode shank insertion

# The bus must thread the narrowest bore (cathode Ø1.3) → that caps the conductor cross-section.
D_BUS = D_BORE_CATHODE
# Anode-pocket geometry for the wood spreading resistance + transient capacitance
L_ANODE_GYROID = 30.0  # gyroid length in sapwood (01_01 §1, 30-50 mm)
D_POCKET_WOOD = 25.0   # outer Ø of the at-risk wet-sapwood pocket around the anode (≈ flange Ø)

MM2_M2 = 1e-6
MM_M = 1e-3


def area_circle_mm2(d_mm: float) -> float:
    return np.pi / 4.0 * d_mm * d_mm


def area_annulus_mm2(d_out: float, d_in: float) -> float:
    return np.pi / 4.0 * (d_out * d_out - d_in * d_in)


def conductance(lmbda: float, area_mm2: float, length_mm: float) -> float:
    """Axial thermal conductance G = λ·A/L (W/K). Areas in mm², length in mm."""
    return lmbda * (area_mm2 * MM2_M2) / (length_mm * MM_M)


def series(rs: list[float]) -> float:
    return sum(rs)


def parallel_G(gs: list[float]) -> float:
    return sum(gs)


# ── Cross-section areas (mm²) ──
A_PEEK_WALL = area_annulus_mm2(D_SLEEVE_OUT, D_SLEEVE_BORE)        # continuous sleeve wall
A_TI_Z1 = area_annulus_mm2(D_Z1_SHANK, D_BORE_ANODE)              # anode shank metal (bored)
A_TI_Z3 = area_annulus_mm2(D_Z3_SHANK, D_BORE_CATHODE)           # cathode shank metal (bored)
A_BUS = area_circle_mm2(D_BUS)                                    # bus conductor (Ø1.3 bottleneck)
A_GAP_VOID = area_circle_mm2(D_SLEEVE_BORE)                       # open bore in the gap (air)

BUS_MATERIALS = {
    "none":  {"lambda": 0.0,        "rho": None,     "label": "no bus (bare break)"},
    # superseded 2026-06-21 (01_01 §1.4 monolithic) — kept as the pre-monolithic baseline
    "Cu":    {"lambda": LAMBDA_CU,  "rho": RHO_CU,   "label": "copper (pre-monolithic baseline)"},
    "Ti":    {"lambda": LAMBDA_TI,  "rho": RHO_TI,   "label": "Ti-6Al-4V (monolithic w/ anode)"},
    "316SS": {"lambda": LAMBDA_316SS, "rho": RHO_316SS, "label": "316 stainless"},
}


def g_anchor(bus_lambda: float, l_a: float, l_c: float) -> dict:
    """Flange→anode anchor conductance for a given bus λ and shank insertions.

    Resistor ladder (center) in parallel with the continuous PEEK wall:
      center:  [Z3 Ti-shank ∥ bus](L_c) — [gap air ∥ bus](L_g) — [Z1 Ti-shank ∥ bus](L_a)
      wall:    PEEK annulus Ø11→Ø15, continuous over L_sleeve
    """
    l_g = L_SLEEVE - l_a - l_c

    def g_bus_seg(length_mm: float) -> float:
        return conductance(bus_lambda, A_BUS, length_mm) if bus_lambda > 0 else 0.0
    # center ladder segments (each = local sheath ∥ bus)
    g_seg_z3 = parallel_G([conductance(LAMBDA_TI, A_TI_Z3, l_c), g_bus_seg(l_c)])
    g_seg_gap = parallel_G([conductance(LAMBDA_AIR, A_GAP_VOID, l_g), g_bus_seg(l_g)])
    g_seg_z1 = parallel_G([conductance(LAMBDA_TI, A_TI_Z1, l_a), g_bus_seg(l_a)])
    r_center = series([1.0 / g_seg_z3, 1.0 / g_seg_gap, 1.0 / g_seg_z1])
    g_center = 1.0 / r_center
    g_wall = conductance(LAMBDA_PEEK, A_PEEK_WALL, L_SLEEVE)
    g_tot = g_center + g_wall
    return {"g_center": g_center, "g_wall": g_wall, "g_total": g_tot, "r_total": 1.0 / g_tot,
            "l_gap": l_g, "g_gap_seg": g_seg_gap}


def r_wood_spread(lambda_wood: float, r_res_mm: float) -> float:
    """Radial spreading resistance from the anode (Ø11 × L_gyroid cylinder) to a deep reservoir at
    r_res. Coaxial-shell conduction R = ln(r2/r1)/(2π λ L). Conservative (radial only; end-conduction
    would lower R → warmer anode → less alarming, so this errs toward the bus looking BAD = safe)."""
    r1 = (D_Z1_SHANK / 2.0) * MM_M
    r2 = r_res_mm * MM_M
    L = L_ANODE_GYROID * MM_M
    return np.log(r2 / r1) / (2.0 * np.pi * lambda_wood * L)


def t_anode(g_anchor_val: float, r_wood: float, t_air: float, t_deep: float) -> float:
    """Steady-state anode-pocket temperature: divider between cold flange (T_air) via the anchor and
    the warm deep trunk (T_deep) via the wood. T = (G_a·T_air + G_w·T_deep)/(G_a + G_w)."""
    g_w = 1.0 / r_wood
    return (g_anchor_val * t_air + g_w * t_deep) / (g_anchor_val + g_w)


def v_drop_uv(rho: float, current_a: float) -> float:
    """Bus IR-drop (µV) at a given current — proves the material is electrically free at EBFC µA."""
    if rho is None:
        return 0.0
    r_elec = rho * (L_SLEEVE * MM_M) / (A_BUS * MM2_M2)   # Ω
    return r_elec * current_a * 1e6


def pocket_capacitance() -> float:
    """Lumped heat capacity (J/K) of the anode + its wet-sapwood pocket, for the transient τ."""
    v_ti = TI_SOLID_FRACTION * area_circle_mm2(D_Z1_SHANK) * L_ANODE_GYROID * (MM_M ** 3)
    v_wood = area_annulus_mm2(D_POCKET_WOOD, D_Z1_SHANK) * (L_ANODE_GYROID + 10.0) * (MM_M ** 3)
    return v_ti * RHO_C_TI + v_wood * RHO_C_WOODWET


def main() -> int:
    banner("HW.34 — Central bus thermal bridge through the Zone-2 PEEK break")

    print(f"  Geometry (frozen): PEEK Ø{D_SLEEVE_BORE:.0f}→Ø{D_SLEEVE_OUT:.0f} × {L_SLEEVE:.0f} mm; "
          f"bus Ø{D_BUS:.1f} (A={A_BUS:.2f} mm²); shanks Z1 Ø{D_Z1_SHANK:.0f}/Z3 Ø{D_Z3_SHANK:.0f}")
    print(f"  Insertions L_a={L_A_INSERT:.0f} L_c={L_C_INSERT:.0f} → effective PEEK gap L_g="
          f"{L_SLEEVE - L_A_INSERT - L_C_INSERT:.0f} mm (Ti shanks bridge {L_A_INSERT + L_C_INSERT:.0f}/"
          f"{L_SLEEVE:.0f} mm of the break)")
    print(f"  λ (W/m·K): Cu {LAMBDA_CU:.0f} · 316SS {LAMBDA_316SS:.0f} · Ti {LAMBDA_TI:.1f} · "
          f"PEEK {LAMBDA_PEEK:.2f} · wood {LAMBDA_WOOD_BASE:.2f}")

    # ── 1. Anchor conductance per bus material (at placeholder insertions) ──
    banner("Anchor flange→anode conductance per bus material")
    g_peek_wall = conductance(LAMBDA_PEEK, A_PEEK_WALL, L_SLEEVE)
    print(f"  PEEK sleeve wall alone (continuous Ø11→Ø15): G = {g_peek_wall:.2e} W/K  (R = {1/g_peek_wall:6.0f} K/W)\n")
    print(f"  {'bus material':<32s} {'G_anchor (W/K)':>14s} {'R_anchor (K/W)':>14s} {'× vs no-bus':>12s}")
    print(f"  {'-'*74}")
    anchor = {}
    for key, m in BUS_MATERIALS.items():
        ga = g_anchor(m["lambda"], L_A_INSERT, L_C_INSERT)
        anchor[key] = ga
    g_none = anchor["none"]["g_total"]
    for key, m in BUS_MATERIALS.items():
        ga = anchor[key]
        print(f"  {m['label']:<32s} {ga['g_total']:>14.3e} {ga['r_total']:>14.1f} {ga['g_total']/g_none:>11.1f}×")
    cu_vs_ti = anchor["Cu"]["g_total"] / anchor["Ti"]["g_total"]
    print(f"\n  → Cu bus conductance = {cu_vs_ti:.1f}× the Ti-bus anchor; Cu bus alone carries "
          f"{(anchor['Cu']['g_total'] - g_peek_wall) / anchor['Cu']['g_total'] * 100:.0f}% of the Cu-case heat.")

    # ── 2. Electrical sanity — the material is free at EBFC µA ──
    banner("Electrical check (bus IR-drop) — the µA current makes material choice electrically free")
    for cur_label, cur in [("100 µA (EBFC typ.)", 100e-6), ("1 mA (peak)", 1e-3)]:
        drops = {k: v_drop_uv(m["rho"], cur) for k, m in BUS_MATERIALS.items() if m["rho"]}
        print(f"  @ {cur_label:<20s}  Cu {drops['Cu']:.3f} µV · Ti {drops['Ti']:.2f} µV · 316SS {drops['316SS']:.2f} µV "
              f"(vs EBFC ~500 000 µV → all negligible)")
    print("  → Ti's 100× worse resistivity is irrelevant: even at 1 mA the IR-drop is sub-mV. The bus is")
    print("    a THERMAL component, not an electrical one — so pick the material on the thermal axis.")

    # ── 3. Steady-state anode-pocket temperature (baseline + sweep) ──
    banner("Steady-state anode-pocket temperature (the living-sapwood freezing question)")
    # T_deep = +2°C: the large-trunk core LAGS a sharp air drop (thermal mass + sap latent heat) — this is
    # exactly the regime where the bridge does harm. A fully cold-soaked trunk (no gradient) has nothing
    # to pipe. T_deep is swept below for robustness.
    t_air_base, t_deep_base = -30.0, 2.0
    r_wood_base = r_wood_spread(LAMBDA_WOOD_BASE, 150.0)
    print(f"  Baseline: T_air={t_air_base:.0f}°C (winter, §4.1), T_deep={t_deep_base:+.0f}°C (core lags snap), "
          f"λ_wood={LAMBDA_WOOD_BASE:.2f}, R_res=150 mm → R_wood={r_wood_base:.0f} K/W")
    print(f"  Cell-damage threshold ≈ {CELL_FREEZE_C:+.0f}°C (supercooling + solute FP-depression)\n")
    print(f"  {'bus material':<32s} {'T_anode (°C)':>12s} {'Δ below core':>13s} {'cell-freeze':>12s}")
    print(f"  {'-'*70}")
    t_base = {}
    for key in BUS_MATERIALS:
        t_base[key] = t_anode(anchor[key]["g_total"], r_wood_base, t_air_base, t_deep_base)
    for key, m in BUS_MATERIALS.items():
        depress = t_deep_base - t_base[key]
        risk = "❄ RISK" if t_base[key] < CELL_FREEZE_C else "ok"
        print(f"  {m['label']:<32s} {t_base[key]:>12.1f} {depress:>+13.1f} {risk:>12s}")
    print(f"\n  → Cu bus drags the anode pocket {t_base['none'] - t_base['Cu']:.1f}°C COLDER than no-bus; "
          f"Ti bus is within {abs(t_base['Ti'] - t_base['none']):.1f}°C of bare → thermally invisible.")

    # Robustness sweep across the uncertain wood/boundary inputs
    banner("Robustness sweep — ΔT_anode(Cu − Ti) across uncertain wood/boundary inputs")
    print(f"  {'T_air':>6s} {'T_deep':>7s} {'λ_wood':>7s} {'R_res':>6s} | {'T(Cu)':>7s} {'T(Ti)':>7s} {'ΔT Cu−Ti':>9s}")
    print(f"  {'-'*64}")
    sweep = []
    dts = []
    for t_air in (-20.0, -30.0):
        for t_deep in (-5.0, 0.0, 2.0):
            for lw in LAMBDA_WOOD_SWEEP:
                for r_res in (100.0, 150.0):
                    rw = r_wood_spread(lw, r_res)
                    t_cu = t_anode(anchor["Cu"]["g_total"], rw, t_air, t_deep)
                    t_ti = t_anode(anchor["Ti"]["g_total"], rw, t_air, t_deep)
                    d = t_cu - t_ti
                    dts.append(d)
                    sweep.append({"t_air": t_air, "t_deep": t_deep, "lambda_wood": lw, "r_res_mm": r_res,
                                  "t_cu": round(t_cu, 2), "t_ti": round(t_ti, 2), "dt_cu_ti": round(d, 2)})
    # print a representative slice (λ_wood baseline, R_res 150)
    for s in sweep:
        if s["lambda_wood"] == 0.40 and s["r_res_mm"] == 150.0:
            print(f"  {s['t_air']:>6.0f} {s['t_deep']:>7.0f} {s['lambda_wood']:>7.2f} {s['r_res_mm']:>6.0f} | "
                  f"{s['t_cu']:>7.1f} {s['t_ti']:>7.1f} {s['dt_cu_ti']:>9.1f}")
    print(f"\n  ΔT_anode(Cu−Ti) over the FULL {len(sweep)}-point grid: "
          f"{min(dts):.1f} … {max(dts):.1f}°C colder with Cu (always negative = Cu always worse).")

    # ── 3b. Per-alloy MONOLITHIC bus (bus λ = the anode alloy; the bus decision dissolves into HW.24) ──
    # If the bus is printed monolithic with the anode, its material is NOT a free choice — it IS whatever
    # the Stage-2 coin bake-off (HW.24) picks. So the thermal bridge is a (secondary) per-alloy input.
    banner("Per-alloy monolithic bus — bus λ = anode alloy (ties HW.34 ↔ HW.24 bake-off)")
    print(f"  {'anode alloy (= bus)':<22s} {'λ':>6s} {'G_anchor':>10s} {'T_anode':>8s} {'Δ<core':>7s} {'risk':>6s}")
    print(f"  {'-'*64}")
    alloy_rows = []
    for name, props in sorted(ALLOY_PROPERTIES.items(), key=lambda kv: kv[1]["lambda_W_mK"]):
        lam = props["lambda_W_mK"]
        ga = g_anchor(lam, L_A_INSERT, L_C_INSERT)["g_total"]
        ta = t_anode(ga, r_wood_base, t_air_base, t_deep_base)
        risk = "❄ RISK" if ta < CELL_FREEZE_C else "ok"
        print(f"  {name:<22s} {lam:>6.1f} {ga:>10.2e} {ta:>7.1f}° {t_deep_base-ta:>+6.1f} {risk:>6s}")
        alloy_rows.append({"alloy": name, "lambda_W_mK": lam, "g_anchor_W_K": ga,
                           "t_anode_C": round(ta, 2), "depression_below_core_C": round(t_deep_base - ta, 2),
                           "cell_freeze_risk": bool(ta < CELL_FREEZE_C)})
    print(f"  {'(reference) separate Cu wire':<22s} {LAMBDA_CU:>6.0f} {anchor['Cu']['g_total']:>10.2e} "
          f"{t_base['Cu']:>7.1f}° {t_deep_base-t_base['Cu']:>+6.1f} {'❄ RISK':>6s}")
    print("  → EVERY bake-off alloy monolithic stays ≪ Cu: alloyed α+β (4V/7Nb/β/15Zr, λ~7) keep the")
    print("    pocket near bare; CP-Ti (λ17) mild; Ta (λ57, coin-only benchmark) the worst Ti but still")
    print("    far above Cu. Bus-thermal ALIGNS with the other bake-off drivers (low-E/V-free → low-λ).")

    # ── 4. Shank-insertion lever (the effective break length is itself a design knob) ──
    banner("Secondary — shank insertion sets the effective break (thermal ↔ press-fit tradeoff)")
    print(f"  {'L_a':>4s} {'L_c':>4s} {'gap':>4s} | {'R_anchor Cu':>12s} {'R_anchor Ti':>12s} {'R_anchor none':>14s}")
    print(f"  {'-'*58}")
    insertion_rows = []
    for l_a, l_c in [(30.0, 14.0), (20.0, 10.0), (10.0, 8.0), (6.0, 6.0)]:
        if l_a + l_c >= L_SLEEVE:
            continue
        rc = 1.0 / g_anchor(LAMBDA_CU, l_a, l_c)["g_total"]
        rt = 1.0 / g_anchor(LAMBDA_TI, l_a, l_c)["g_total"]
        rn = 1.0 / g_anchor(0.0, l_a, l_c)["g_total"]
        gap = L_SLEEVE - l_a - l_c
        print(f"  {l_a:>4.0f} {l_c:>4.0f} {gap:>4.0f} | {rc:>10.1f}   {rt:>10.1f}   {rn:>12.1f}")
        insertion_rows.append({"l_a": l_a, "l_c": l_c, "gap": gap,
                               "r_anchor_cu": round(rc, 1), "r_anchor_ti": round(rt, 1), "r_anchor_none": round(rn, 1)})
    print("  → Less shank insertion = longer PEEK-only gap = better break, but less press-fit grip. With a")
    print("    Cu bus the bus dominates so shank length barely helps; with a Ti bus the gap length matters.")

    # ── 5. Transient time-constant (the metal tracks a cold-snap faster than the wood buffers) ──
    banner("Transient — pocket thermal time-constant (cold-snap responsiveness)")
    c_pocket = pocket_capacitance()
    g_w_base = 1.0 / r_wood_base
    tau_cu = c_pocket / (anchor["Cu"]["g_total"] + g_w_base) / 60.0
    tau_ti = c_pocket / (anchor["Ti"]["g_total"] + g_w_base) / 60.0
    tau_none = c_pocket / (anchor["none"]["g_total"] + g_w_base) / 60.0
    print(f"  Pocket heat capacity C ≈ {c_pocket:.0f} J/K (35% Ti gyroid + wet-sapwood shell)")
    print(f"  τ = C/(G_anchor+G_wood):  Cu {tau_cu:.0f} min · Ti {tau_ti:.0f} min · none {tau_none:.0f} min")
    print("  → Cu bus ~halves the pocket's natural buffering (faster equilibration to a cold snap), in")
    print("    addition to the colder steady state. Steady-state ΔT is the load-bearing result; τ is a")
    print("    secondary indicator (lumped C is approximate).")

    # ── Verdict ──
    banner("Verdict")
    print(f"  1. The Cu bus is the DOMINANT axial cold path: G_anchor(Cu) = {cu_vs_ti:.0f}× the Ti-bus")
    print(f"     anchor; with Cu the bus carries ~{(anchor['Cu']['g_total']-g_peek_wall)/anchor['Cu']['g_total']*100:.0f}% of the heat crossing the break.")
    print(f"  2. A Ti(-6Al-4V) bus is thermally INVISIBLE — anode pocket within "
          f"{abs(t_base['Ti']-t_base['none']):.1f}°C of bare; Cu drives it {t_base['none']-t_base['Cu']:.0f}°C colder (into a freeze).")
    print("  3. Electrically the swap is FREE (µA → sub-mV IR-drop even for Ti's 100× resistivity).")
    print("  4. RECOMMENDATION: a Ti-6Al-4V bus printed MONOLITHIC with the Zone-1 anode (same SLM) —")
    print("     kills the thermal bridge AND the bottom Ti↔Cu galvanic joint (02_02 §1.2) in one move.")
    print("     (Material is a founder call → 00_07 HW.34, not baseline canon; no-premature-canon.)")
    print("  5. Caveat: 1D lumped ladder, steady state; absolute T_anode depends on the swept wood")
    print("     reservoir. The Cu≫Ti ranking is robust to all of it. Conjugate FEA = bench-side.")

    # ── Plot: T_anode vs T_air per material + the sweep band ──
    _fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    t_air_axis = np.linspace(-30, 5, 36)
    for key, m in BUS_MATERIALS.items():
        ys = [t_anode(anchor[key]["g_total"], r_wood_base, ta, t_deep_base) for ta in t_air_axis]
        style = "--" if key == "none" else "-"
        ax1.plot(t_air_axis, ys, style, linewidth=2, label=m["label"])
    ax1.axhline(0.0, color="c", linestyle=":", label="0°C (freezing)")
    ax1.plot(t_air_axis, t_air_axis, color="0.7", linewidth=1, label="T_air (no break)")
    ax1.set_xlabel("Surface / flange air temperature (°C)")
    ax1.set_ylabel("Zone-1 anode pocket temperature (°C)")
    ax1.set_title(f"Anode pocket vs winter air (T_deep={t_deep_base:.0f}°C, λ_wood={LAMBDA_WOOD_BASE:.2f})")
    ax1.legend(fontsize=8)
    ax1.grid(True, alpha=0.3)

    labels = [BUS_MATERIALS[k]["label"].split(" (")[0] for k in BUS_MATERIALS]
    rvals = [anchor[k]["r_total"] for k in BUS_MATERIALS]
    colors = ["0.6", "tab:red", "tab:green", "tab:orange"]
    ax2.bar(labels, rvals, color=colors)
    ax2.set_yscale("log")
    ax2.set_ylabel("Anchor thermal resistance R_anchor (K/W, log)")
    ax2.set_title("Higher R = better break.  Cu bus collapses it ~10-25×")
    ax2.grid(True, alpha=0.3, axis="y")
    plt.tight_layout()
    fig_path = OUT_DIR / "anchor_thermal_bridge.png"
    plt.savefig(fig_path, dpi=150)
    print(f"\n  Plot: {fig_path.relative_to(REPO_ROOT)}")

    out = {
        "method": "1D lumped thermal resistance ladder (center: Z3-shank∥bus — gap∥bus — Z1-shank∥bus) "
                  "in parallel with the continuous PEEK sleeve wall; steady-state 2-node anode divider "
                  "(cold flange via anchor ↔ warm deep trunk via wood spreading R). No FEA/DFT.",
        "lambda_W_mK": {"Ti-6Al-4V": LAMBDA_TI, "Cu": LAMBDA_CU, "316SS": LAMBDA_316SS,
                        "PEEK-450G": LAMBDA_PEEK, "air": LAMBDA_AIR, "wood_wet_sapwood": LAMBDA_WOOD_BASE},
        "geometry_mm": {"sleeve_od": D_SLEEVE_OUT, "sleeve_bore": D_SLEEVE_BORE, "sleeve_len": L_SLEEVE,
                        "z1_shank_od": D_Z1_SHANK, "z3_shank_od": D_Z3_SHANK,
                        "bus_dia_bottleneck": D_BUS, "bus_area_mm2": round(A_BUS, 3),
                        "shank_insert_a": L_A_INSERT, "shank_insert_c": L_C_INSERT,
                        "effective_gap": L_SLEEVE - L_A_INSERT - L_C_INSERT},
        "peek_wall_G_W_K": g_peek_wall,
        "anchor_conductance": {k: {"g_total_W_K": anchor[k]["g_total"], "r_total_K_W": anchor[k]["r_total"],
                                   "g_center_W_K": anchor[k]["g_center"], "g_wall_W_K": anchor[k]["g_wall"],
                                   "x_vs_no_bus": anchor[k]["g_total"] / g_none}
                               for k in BUS_MATERIALS},
        "cu_vs_ti_conductance_ratio": cu_vs_ti,
        "electrical_ir_drop_uV": {"at_100uA": {k: v_drop_uv(m["rho"], 100e-6) for k, m in BUS_MATERIALS.items() if m["rho"]},
                                  "at_1mA": {k: v_drop_uv(m["rho"], 1e-3) for k, m in BUS_MATERIALS.items() if m["rho"]},
                                  "ebfc_reference_uV": 500000},
        "steady_state_baseline": {"t_air_C": t_air_base, "t_deep_C": t_deep_base,
                                  "lambda_wood": LAMBDA_WOOD_BASE, "r_res_mm": 150.0,
                                  "r_wood_K_W": r_wood_base, "cell_freeze_threshold_C": CELL_FREEZE_C,
                                  "t_anode_C": {k: round(t_base[k], 2) for k in BUS_MATERIALS},
                                  "depression_below_core_C": {k: round(t_deep_base - t_base[k], 2) for k in BUS_MATERIALS},
                                  "cell_freeze_risk": {k: bool(t_base[k] < CELL_FREEZE_C) for k in BUS_MATERIALS},
                                  "cu_colder_than_none_C": round(t_base["none"] - t_base["Cu"], 2),
                                  "ti_within_of_none_C": round(abs(t_base["Ti"] - t_base["none"]), 2)},
        "robustness_sweep": {"n_points": len(sweep), "dt_cu_ti_min_C": round(min(dts), 2),
                             "dt_cu_ti_max_C": round(max(dts), 2), "grid": sweep},
        "per_alloy_monolithic_bus": {"note": "bus λ = anode alloy (monolithic); the bus material is NOT "
                                     "a separate choice — it follows the HW.24 bake-off. All ≪ Cu.",
                                     "rows": alloy_rows},
        "shank_insertion_lever": insertion_rows,
        "transient_tau_min": {"Cu": round(tau_cu, 1), "Ti": round(tau_ti, 1), "none": round(tau_none, 1),
                              "pocket_C_J_K": round(c_pocket, 1)},
        "verdict": ("Cu bus dominates the axial cold path (~{:.0f}x the Ti-bus anchor) and drives the "
                    "Zone-1 anode pocket ~{:.0f}C colder (into a freeze) than a Ti bus, which is thermally "
                    "invisible. Swap is electrically free at uA. Recommend Ti-6Al-4V bus monolithic with "
                    "the anode (also kills the Ti-Cu galvanic joint). Material = founder call, 00_07 HW.34."
                    ).format(cu_vs_ti, t_base["none"] - t_base["Cu"]),
        "caveats": "1D lumped ladder + steady state; absolute T_anode depends on the swept wood reservoir "
                   "(lambda_wood, R_res, T_deep). The Cu>>Ti ranking is robust across the whole grid. "
                   "Conjugate 3D FEA + bench validation (Cherkasy winter) refine the absolute numbers.",
    }
    json_path = OUT_DIR / "anchor_thermal_bridge.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    # gate: Cu must be materially worse than Ti (sanity, not a product pass/fail)
    return 0 if cu_vs_ti > 3.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
