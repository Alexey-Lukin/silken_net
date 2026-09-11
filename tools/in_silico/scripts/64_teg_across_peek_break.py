#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.21 — Can a Bi₂Te₃ TEG be mounted ACROSS the Zone-2 PEEK break instead of glued to the bark?

WHY THIS EXISTS. `00_07` HW.21 carries a 🤖 leg (from the DOC-T.107 review): the bark-glued TEG of
`01_03 §6.2` sees its ΔT through bark (λ 0.05–0.1) and through a joint nobody clamps, whereas Zone 2
is the ONE place in the whole anchor where both junctions are already mechanically fixed on opposite
sides of a λ 0.25 insulator. Geometrically that is the obvious mount. ⚠️ But it aims straight at the
reason Zone 2 exists at all (`01_01 §4.1`: a continuous Ti thermal bridge super-cools the cambial ring
→ intracellular ice → membrane rupture), and a TEG is, before it is anything else, a THERMALLY
CONDUCTIVE PLATE. The tracker names the first step and it is machine-side: put a `+G_TEG` branch in
parallel with the Zone-2 gap and compare the resulting flux against the residual bridge we already
accept (the monolithic Ti bus, `01_01 §1.4` / HW.34).

This script is that branch. It answers three questions the checkbox implies but does not separate:
  Q1 THERMAL   — how much of the break does a TEG defeat, against the −2.0 °C cambium-freeze gate
                 script 54 already uses?
  Q2 BUDGET    — inverted: what is the LARGEST conductance that may cross the break and still pass
                 the gate, expressed as a purchasable footprint?
  Q3 ELECTRICAL— what does the module actually GIVE at the ΔT that survives its own installation, so
                 the verdict compares «what it gives» against «what it costs thermally» rather than
                 asserting one of them.

MODEL — the SAME 1D lumped resistor ladder as script 54, not a re-derivation. Script 54 is imported
(digit-leading module name → importlib, the script-24c pattern) so `conductance` / `parallel_G` /
`series` / `r_wood_spread` / `t_anode`, every λ, every frozen dimension and the −2.0 °C gate are the
BYTE-IDENTICAL objects, not copies that can drift. `assert_ladder_matches_54()` below re-derives 54's
own cached Ti/no-bus/Cu conductances from the reassembled ladder and fails the run if they differ.

  center: [Z3 Ti-shank ∥ bus](L_c) — [gap air ∥ bus ∥ **TEG**](L_g) — [Z1 Ti-shank ∥ bus](L_a)
  wall:   PEEK annulus Ø11→Ø15, continuous over L_sleeve      (∥ **TEG** in the sleeve-span mount)

TWO MOUNTS, because «across the break» is two different parts:
  * `gap`    — the module bridges only the L_g ≈ 6 mm PEEK-only gap (short collars grabbing the two
               shank ends) → G_TEG parallels the GAP SEGMENT, in series with the two Ti shanks.
  * `sleeve` — the module bridges the whole 50 mm sleeve (flange ↔ Zone-1 body, via straps) →
               G_TEG parallels the WHOLE anchor, alongside the PEEK wall.
Both are modelled with IDEAL straps/collars (zero contact and strap resistance). That overstates
G_TEG (→ thermal harm conservative = the safe direction for a reject) AND overstates the share of the
break's ΔT that actually lands on the module faces (→ electrical output optimistic). Both biases point
the same way: they make the TEG look BETTER on the axis it is being defended on and WORSE on the axis
it is being challenged on, so a rejection under them is robust. A real 50 mm strap is NOT free (Al,
20 mm², 50 mm → G ≈ 0.08 W/K, the same order as the module itself) — see caveats.

ELECTRICAL — module-level Seebeck, stated openly:
    V_oc  = S_module · ΔT,      S_module = n_couples · 2 · S_leg
    P_max = S_module²·ΔT²/(4R) = Z·K·ΔT²/4 = (ZT/T̄)·G_TEG·ΔT²/4        (matched electrical load)
The second form is used because Z = S²/(R·K) is exact at module level, so P follows from the SAME
G_TEG the thermal half computes — no free leg geometry, no assumed leg resistivity. R_module is then
back-solved and cached purely as a plausibility cross-check against real parts.
ΔT is NOT assumed: it is the ΔT that survives the module's own installation (the module collapses the
very gradient it harvests), read off the solved ladder.

LITERATURE ANCHORS (hypothesis-grade inputs, `00_06 §0` Validation Gate — nothing here is measured):
  * κ_eff 1.2–1.6 W/(m·K) — RT thermal conductivity of Bi₂Te₃-alloy thermoelectric material.
    Poudel, Hao, Ma, Lan, Minnich, Yu, Yan, Wang, Muto, Vashaee, Chen, Liu, Dresselhaus, Chen, Ren,
    "High-Thermoelectric Performance of Nanostructured Bismuth Antimony Telluride Bulk Alloys",
    *Science* **320**(5876), 634–638 (2008), doi:10.1126/science.1156446 (Crossref-verified) —
    ingot BiSbTe κ in the 1.2–1.6 W/(m·K) band around 300 K; the standard textbook range, Goldsmid,
    *Introduction to Thermoelectricity*, 2nd ed., Springer Series in Materials Science (2016),
    doi:10.1007/978-3-662-49256-7 (Crossref-verified), agrees.
    ⚠️ Applying MATERIAL κ over the FULL module footprint is deliberate and conservative: a real
    module fills only ~20–40 % of its footprint with legs, so a leg-only κ_eff is LOWER. A
    fill-factor lower bound (κ_eff 0.4) is computed below and does NOT change the verdict.
  * ZT_module 0.7 (bracket 0.5–1.0) — commercial Bi₂Te₃ module near 300 K; material ZT ≈ 1.0
    (Goldsmid, above), module-level lower through contacts and ceramics. P ∝ ZT linearly.
  * S_leg 200 µV/K — optimized Bi₂Te₃ near 300 K (Goldsmid, above).
  * n_couples 0.08 mm⁻² — ASSUMPTION, not literature: the familiar 127-couple / 40×40 mm form
    factor. It sets V_oc only; P_max does not use it.

⛔ SCOPE. Thermal admissibility + own output ONLY. This does NOT re-open `01_03 §6.2`'s shared-rail
verdict (HW.42, ratified founder 2026-09-09 — a TEG on the BQ25570 rail poisons `delta_t`, i.e. the
mint) and does NOT decide the separate-charging-tract 👤 leg. No FEA, no DFT — closed-form ladder,
numpy + matplotlib only.

Run
---
    conda run -n silken_md python tools/in_silico/scripts/64_teg_across_peek_break.py
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

# Reuse script 54's exact ladder helpers, λ set, frozen geometry and −2.0 °C gate (digit-leading
# module name → importlib, the script-24c pattern). Importing does NOT run 54's main().
_spec = importlib.util.spec_from_file_location("bridge54", HERE / "54_anchor_thermal_bridge.py")
t54 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(t54)

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── TEG module inputs (see LITERATURE ANCHORS in the docstring) ──
KAPPA_SWEEP = (1.2, 1.4, 1.6)      # W/(m·K), module effective through-thickness conductivity
KAPPA_BASE = 1.4
KAPPA_FILL_LOWER = 0.4             # leg-only fill-factor lower bound (sensitivity, not a catalogue value)
FOOTPRINTS_MM = (8.0, 15.0, 20.0, 30.0, 40.0)
THICKNESSES_MM = (2.0, 3.0, 4.0)
ZT_MODULE = 0.7
ZT_BRACKET = (0.5, 1.0)
S_LEG_V_K = 200e-6                 # V/K per leg
COUPLE_DENSITY_MM2 = 0.08          # couples per mm² (127-couple / 40×40 mm form factor) — ASSUMPTION
VIN_CS_MV = 600.0                  # BQ25570 cold-start VIN(CS) typ., `02_03 §1.5` / HW.46
TARGET_UW = (50.0, 200.0)          # HW.21's own winter harvest target (µW) — the band the residual is judged against
# Bus-Ø robustness bound. Script 54 now carries the canon rod (lib.constants D_BUS_ROD_MM, 01_01 §1.4);
# the Ø1.35 cathode CHANNEL is the physical upper bound on how fat that rod could ever be, so sweeping to
# it answers "could the bus diameter move this verdict at all?" — the check the old caveat performed.
D_BUS_UPPER_BOUND_MM = 1.35        # cathode channel Ø (01_01 §1.4, opened by 00_07 HW.34) — the fattest a bus rod could be

MM2_M2 = 1e-6
MM_M = 1e-3
KELVIN = 273.15


def g_teg(kappa: float, footprint_mm: float, thickness_mm: float) -> float:
    """Module through-thickness thermal conductance G = κ_eff·A/t (W/K)."""
    return t54.conductance(kappa, footprint_mm * footprint_mm, thickness_mm)


def anchor(bus_lambda: float, g_mod: float = 0.0, mount: str = "none", a_bus: float | None = None) -> dict:
    """Script 54's flange→anode ladder with an optional TEG branch.

    mount='gap'    → G_TEG ∥ the L_g PEEK-only gap segment (in series with both Ti shanks)
    mount='sleeve' → G_TEG ∥ the whole anchor (alongside the continuous PEEK wall)
    a_bus overrides the bus cross-section (Ø-sensitivity only; 54's own D_BUS is never modified).
    """
    l_a, l_c = t54.L_A_INSERT, t54.L_C_INSERT
    l_g = t54.L_SLEEVE - l_a - l_c
    area_bus = t54.A_BUS if a_bus is None else a_bus

    def g_bus_seg(length_mm: float) -> float:
        return t54.conductance(bus_lambda, area_bus, length_mm) if bus_lambda > 0 else 0.0

    g_z3 = t54.parallel_G([t54.conductance(t54.LAMBDA_TI, t54.A_TI_Z3, l_c), g_bus_seg(l_c)])
    g_gap_bare = t54.parallel_G([t54.conductance(t54.LAMBDA_AIR, t54.A_GAP_VOID, l_g), g_bus_seg(l_g)])
    g_z1 = t54.parallel_G([t54.conductance(t54.LAMBDA_TI, t54.A_TI_Z1, l_a), g_bus_seg(l_a)])

    g_gap = g_gap_bare + g_mod if mount == "gap" else g_gap_bare
    r_center = t54.series([1.0 / g_z3, 1.0 / g_gap, 1.0 / g_z1])
    g_center = 1.0 / r_center
    g_wall = t54.conductance(t54.LAMBDA_PEEK, t54.A_PEEK_WALL, t54.L_SLEEVE)
    g_total = g_center + g_wall + (g_mod if mount == "sleeve" else 0.0)
    return {"g_total": g_total, "g_center": g_center, "g_wall": g_wall, "g_z3": g_z3, "g_z1": g_z1,
            "g_gap_bare": g_gap_bare, "g_gap": g_gap, "l_gap": l_g,
            "r_shanks": 1.0 / g_z3 + 1.0 / g_z1}


def assert_ladder_matches_54() -> None:
    """The ONE runnable check that this reassembled ladder IS 54's, not a look-alike."""
    cached = json.loads((OUT_DIR / "anchor_thermal_bridge.json").read_text())["anchor_conductance"]
    for key, lam in (("Ti", t54.LAMBDA_TI), ("none", 0.0), ("Cu", t54.LAMBDA_CU)):
        ours = anchor(lam)["g_total"]
        theirs = cached[key]["g_total_W_K"]
        if not np.isclose(ours, theirs, rtol=1e-12):
            raise AssertionError(f"ladder drift vs script 54 cache [{key}]: {ours!r} != {theirs!r}")


def module_dt(res: dict, mount: str, t_anode_c: float, t_air_c: float) -> tuple[float, float, float]:
    """ΔT actually left across the module faces after it has collapsed its own gradient.

    Returns (dT_K, T_cold_face_C, T_hot_face_C). Winter sign convention: the trunk is the hot side.
    """
    if mount == "sleeve":
        return t_anode_c - t_air_c, t_air_c, t_anode_c
    q_center = res["g_center"] * (t_anode_c - t_air_c)      # W through the center ladder
    t_cold = t_air_c + q_center / res["g_z3"]               # Z3-shank drop from the flange
    d_t = q_center / res["g_gap"]
    return d_t, t_cold, t_cold + d_t


def teg_output(g_mod: float, d_t: float, t_mean_c: float, footprint_mm2: float, zt: float = ZT_MODULE) -> dict:
    """Module electrical output at the surviving ΔT. P_max = (ZT/T̄)·G_TEG·ΔT²/4 (matched load)."""
    t_mean_k = t_mean_c + KELVIN
    p_w = (zt / t_mean_k) * g_mod * d_t * d_t / 4.0
    s_module = COUPLE_DENSITY_MM2 * footprint_mm2 * 2.0 * S_LEG_V_K
    v_oc = s_module * d_t
    r_module = s_module * s_module / ((zt / t_mean_k) * g_mod) if g_mod > 0 else float("nan")
    return {"p_uW": p_w * 1e6, "v_oc_mV": v_oc * 1e3, "s_module_V_K": s_module,
            "r_module_ohm": r_module, "t_mean_C": t_mean_c}


def g_anchor_gate_max(g_wood: float, t_deep: float, t_air: float) -> float | None:
    """Largest flange→anode conductance that still holds T_anode ≥ the −2.0 °C gate.

    None ⇒ degenerate scenario: the reservoir itself is at/below the gate, unreachable at any G.
    """
    t_gate = t54.CELL_FREEZE_C
    if t_deep <= t_gate:
        return None
    return g_wood * (t_deep - t_gate) / (t_gate - t_air)


def g_teg_budget(g_max: float, mount: str) -> float:
    """Invert the gate: the largest admissible G_TEG. -inf ⇒ no module admissible at ANY size."""
    base = anchor(t54.LAMBDA_TI)
    if mount == "sleeve":
        return g_max - base["g_total"]
    g_center_max = g_max - base["g_wall"]
    if g_center_max <= 0:
        return float("-inf")
    r_gap_max = 1.0 / g_center_max - base["r_shanks"]
    if r_gap_max <= 0:                       # even a PERFECT short of the gap cannot save it
        return float("-inf")
    return 1.0 / r_gap_max - base["g_gap_bare"]


def footprint_for_g(g_val: float, kappa: float, thickness_mm: float) -> float:
    """Module footprint (mm²) that realises a given G_TEG at (κ, t)."""
    return g_val * (thickness_mm * MM_M) / kappa / MM2_M2


def main() -> int:
    banner("HW.21 — TEG mounted ACROSS the Zone-2 PEEK break (vs the residual monolithic-Ti bridge)")
    assert_ladder_matches_54()
    print("  ✓ ladder re-derives script 54's cached Ti / no-bus / Cu conductances exactly (rtol 1e-12)")

    base_ti = anchor(t54.LAMBDA_TI)
    base_none = anchor(0.0)
    g_none = base_none["g_total"]
    t_air, t_deep = -30.0, 2.0
    r_wood = t54.r_wood_spread(t54.LAMBDA_WOOD_BASE, 150.0)
    g_wood = 1.0 / r_wood
    t_ti = t54.t_anode(base_ti["g_total"], r_wood, t_air, t_deep)
    t_none = t54.t_anode(g_none, r_wood, t_air, t_deep)

    print(f"\n  Baseline (script 54, unchanged): T_air={t_air:.0f} °C · T_deep={t_deep:+.0f} °C · "
          f"λ_wood={t54.LAMBDA_WOOD_BASE:.2f} · R_res=150 mm → R_wood={r_wood:.1f} K/W")
    print(f"  Gate: T_anode ≥ {t54.CELL_FREEZE_C:+.1f} °C (cambium ice-nucleation, 01_01 §4.1)")
    print(f"  Residual bridge we ALREADY accept — monolithic Ti bus: G={base_ti['g_total']:.3e} W/K "
          f"(×{base_ti['g_total'] / g_none:.2f} vs no-bus), T_anode={t_ti:+.2f} °C  → PASS")
    print(f"  Ideal break (no bus at all):        G={g_none:.3e} W/K (×1.00), T_anode={t_none:+.2f} °C")
    print(f"  PEEK-only gap in the ladder: L_g={base_ti['l_gap']:.0f} mm; the module bridges it (gap mount) "
          f"or the whole {t54.L_SLEEVE:.0f} mm sleeve (sleeve mount)")

    # ── Reference: a solid Ti anchor (NO PEEK break) — the condition Zone 2 exists to prevent ──
    g_solid = t54.conductance(t54.LAMBDA_TI, t54.A_TI_Z1, t54.L_SLEEVE)
    t_solid = t54.t_anode(g_solid, r_wood, t_air, t_deep)
    # ── Asymptote: gap mount with G_TEG → ∞ (a perfect thermal short of the gap) ──
    g_gap_inf = anchor(t54.LAMBDA_TI, g_mod=1e9, mount="gap")["g_total"]
    t_gap_inf = t54.t_anode(g_gap_inf, r_wood, t_air, t_deep)
    print(f"\n  Reference — solid Ti, NO PEEK break:  G={g_solid:.3e} W/K, T_anode={t_solid:+.2f} °C")
    print(f"  Asymptote — gap mount, G_TEG → ∞:     G={g_gap_inf:.3e} W/K, T_anode={t_gap_inf:+.2f} °C")
    print(f"  → a gap-spanning module saturates {abs(t_gap_inf - t_solid):.2f} °C from the NO-BREAK condition: "
          f"past a few mW/K it is not «partly» defeating Zone 2, it has REVERTED the design to pre-PEEK.")

    # ── 1. Catalogue module sweep ──
    banner("Q1 — catalogue Bi₂Te₃ modules across the break (κ_eff 1.2–1.6, t 2–4 mm)")
    print(f"  {'module':>12s} {'κ':>4s} {'G_TEG':>10s} {'×G_anch':>8s} | {'gap: T_an':>10s} {'×no-bus':>8s} "
          f"{'gate':>6s} {'ΔT':>7s} {'P':>8s} {'V_oc':>9s} | {'sleeve: T_an':>13s} {'gate':>6s} {'P':>8s}")
    print(f"  {'-' * 128}")
    rows = []
    for foot in FOOTPRINTS_MM:
        for thick in THICKNESSES_MM:
            for kappa in KAPPA_SWEEP:
                gm = g_teg(kappa, foot, thick)
                row = {"footprint_mm": foot, "thickness_mm": thick, "kappa_W_mK": kappa,
                       "footprint_mm2": foot * foot, "g_teg_W_K": gm,
                       "x_vs_ti_bus_anchor": gm / base_ti["g_total"]}
                for mount in ("gap", "sleeve"):
                    res = anchor(t54.LAMBDA_TI, g_mod=gm, mount=mount)
                    ta = t54.t_anode(res["g_total"], r_wood, t_air, t_deep)
                    d_t, t_cold, t_hot = module_dt(res, mount, ta, t_air)
                    out = teg_output(gm, d_t, (t_cold + t_hot) / 2.0, foot * foot)
                    row[mount] = {"g_anchor_W_K": res["g_total"], "x_vs_no_bus": res["g_total"] / g_none,
                                  "t_anode_C": round(ta, 2), "gate_pass": bool(ta >= t54.CELL_FREEZE_C),
                                  "dT_module_K": round(d_t, 3), "p_uW": round(out["p_uW"], 1),
                                  "v_oc_mV": round(out["v_oc_mV"], 2),
                                  "v_oc_vs_vin_cs": round(out["v_oc_mV"] / VIN_CS_MV, 4),
                                  "r_module_ohm": round(out["r_module_ohm"], 3)}
                rows.append(row)
                if kappa == KAPPA_BASE:
                    g_r, s_r = row["gap"], row["sleeve"]
                    print(f"  {f'{foot:.0f}×{foot:.0f}×{thick:.0f}':>12s} {kappa:>4.1f} {gm:>10.3e} "
                          f"{row['x_vs_ti_bus_anchor']:>7.0f}× | {g_r['t_anode_C']:>9.1f}° "
                          f"{g_r['x_vs_no_bus']:>7.0f}× {'❄FAIL' if not g_r['gate_pass'] else 'ok':>6s} "
                          f"{g_r['dT_module_K']:>6.2f}K {g_r['p_uW']:>7.0f}µW {g_r['v_oc_mV']:>7.1f}mV | "
                          f"{s_r['t_anode_C']:>12.1f}° {'❄FAIL' if not s_r['gate_pass'] else 'ok':>6s} "
                          f"{s_r['p_uW']:>7.0f}µW")
    n_pass = sum(1 for r in rows for m in ("gap", "sleeve") if r[m]["gate_pass"])
    print(f"\n  (printed at κ_eff={KAPPA_BASE}; the full {len(rows)}-geometry × 2-mount grid is cached)")
    print(f"  Gate passes across the ENTIRE catalogue grid: {n_pass} / {len(rows) * 2}")

    # ── 2. Inverted question: the thermal budget for anything crossing the break ──
    banner("Q2 — inverted: the LARGEST conductance admissible across the break (the −2.0 °C budget)")
    g_max_base = g_anchor_gate_max(g_wood, t_deep, t_air)
    budgets = {}
    for mount in ("gap", "sleeve"):
        b = g_teg_budget(g_max_base, mount)
        area = footprint_for_g(b, KAPPA_BASE, 3.0) if b > 0 else float("nan")
        budgets[mount] = {"g_teg_max_W_K": b, "footprint_mm2_at_kappa1p4_t3mm": area,
                          "side_mm": float(np.sqrt(area)) if b > 0 else float("nan")}
        print(f"  {mount:>7s} mount: G_anchor may reach {g_max_base:.3e} W/K → G_TEG ≤ {b:.3e} W/K "
              f"→ at κ={KAPPA_BASE}, t=3 mm that is {area:.2f} mm² "
              f"({np.sqrt(area):.2f}×{np.sqrt(area):.2f} mm)")
    smallest = min(FOOTPRINTS_MM) ** 2
    ratio_gap = smallest / budgets["gap"]["footprint_mm2_at_kappa1p4_t3mm"]
    print(f"\n  → the smallest module in the sweep ({min(FOOTPRINTS_MM):.0f}×{min(FOOTPRINTS_MM):.0f} = "
          f"{smallest:.0f} mm²) is ×{ratio_gap:.0f} OVER the gap-mount budget.")
    print("    The admissible part is not a small module — it is a sub-mm² bespoke micro-TEG.")

    gm_budget = budgets["gap"]["g_teg_max_W_K"]
    res_b = anchor(t54.LAMBDA_TI, g_mod=gm_budget, mount="gap")
    ta_b = t54.t_anode(res_b["g_total"], r_wood, t_air, t_deep)
    dt_b, tc_b, th_b = module_dt(res_b, "gap", ta_b, t_air)
    out_b = teg_output(gm_budget, dt_b, (tc_b + th_b) / 2.0,
                       budgets["gap"]["footprint_mm2_at_kappa1p4_t3mm"])
    v_oc_1couple_mv = 2.0 * S_LEG_V_K * dt_b * 1e3     # <1 couple fits there: price it as ONE couple
    print(f"  At exactly that budget: T_anode={ta_b:+.2f} °C (= the gate, ZERO margin), "
          f"ΔT_module={dt_b:.1f} K, P={out_b['p_uW']:.0f} µW")
    print(f"    → energetically NOT pointless (HW.21's own TEG target is {TARGET_UW[0]:.0f}–{TARGET_UW[1]:.0f} µW winter) — but V_oc is "
          f"{v_oc_1couple_mv:.1f} mV as a single couple,")
    print(f"      i.e. ×{VIN_CS_MV / v_oc_1couple_mv:.0f} below BQ25570's VIN(CS) {VIN_CS_MV:.0f} mV (HW.46).")

    # ── 3. The power optimum — and whether the gate survives it ──
    banner("Q3 — thermal impedance match: the module that gives the MOST power, and its gate cost")
    g_axis = np.logspace(-5, 1, 600)
    p_axis, t_axis = [], []
    for gm in g_axis:
        res = anchor(t54.LAMBDA_TI, g_mod=gm, mount="gap")
        ta = t54.t_anode(res["g_total"], r_wood, t_air, t_deep)
        d_t, tc, th = module_dt(res, "gap", ta, t_air)
        p_axis.append(teg_output(gm, d_t, (tc + th) / 2.0, footprint_for_g(gm, KAPPA_BASE, 3.0))["p_uW"])
        t_axis.append(ta)
    p_axis, t_axis = np.asarray(p_axis), np.asarray(t_axis)
    i_opt = int(np.argmax(p_axis))
    g_opt, p_opt, t_opt = float(g_axis[i_opt]), float(p_axis[i_opt]), float(t_axis[i_opt])
    a_opt = footprint_for_g(g_opt, KAPPA_BASE, 3.0)
    print(f"  P peaks at G_TEG={g_opt:.3e} W/K (≈{np.sqrt(a_opt):.1f}×{np.sqrt(a_opt):.1f}×3 mm at "
          f"κ={KAPPA_BASE}): P={p_opt:.0f} µW — and T_anode there is {t_opt:+.2f} °C")
    print(f"  → the power optimum sits ×{abs(t_opt / t54.CELL_FREEZE_C):.1f} PAST the gate. Bigger is not "
          "better on either")
    print("    axis: past the match the module collapses its own ΔT (P ∝ G·ΔT², ΔT ∝ 1/G → P ∝ 1/G).")
    big = next(r for r in rows
               if r["footprint_mm"] == 40.0 and r["thickness_mm"] == 3.0 and r["kappa_W_mK"] == KAPPA_BASE)
    small = next(r for r in rows
                 if r["footprint_mm"] == 8.0 and r["thickness_mm"] == 4.0 and r["kappa_W_mK"] == KAPPA_BASE)
    print(f"    Measured on the catalogue rows: 8×8×4 gives {small['gap']['p_uW']:.0f} µW, "
          f"40×40×3 gives {big['gap']['p_uW']:.0f} µW — the 25× larger module gives "
          f"{small['gap']['p_uW'] / big['gap']['p_uW']:.0f}× LESS.")

    # ── 4. Robustness: 54's own wood/boundary grid ──
    banner("Robustness — the same wood-reservoir sweep script 54 uses (48 points)")
    grid, budget_grid = [], []
    for ta_air in (-20.0, -30.0):
        for td in (-5.0, 0.0, 2.0):
            for lw in t54.LAMBDA_WOOD_SWEEP:
                for r_res in (100.0, 150.0):
                    rw = t54.r_wood_spread(lw, r_res)
                    gw = 1.0 / rw
                    g_max = g_anchor_gate_max(gw, td, ta_air)
                    degenerate = g_max is None
                    t_ti_pt = t54.t_anode(base_ti["g_total"], rw, ta_air, td)
                    pt = {"t_air": ta_air, "t_deep": td, "lambda_wood": lw, "r_res_mm": r_res,
                          "degenerate_reservoir_below_gate": degenerate,
                          "t_anode_ti_bus_C": round(t_ti_pt, 2),
                          "ti_bus_gate_pass": bool(t_ti_pt >= t54.CELL_FREEZE_C)}
                    if not degenerate:
                        b_gap = g_teg_budget(g_max, "gap")
                        pt["g_teg_budget_gap_W_K"] = b_gap
                        pt["g_teg_budget_sleeve_W_K"] = g_teg_budget(g_max, "sleeve")
                        budget_grid.append(b_gap)
                    for foot, thick in ((8.0, 4.0), (40.0, 3.0)):
                        gm = g_teg(KAPPA_BASE, foot, thick)
                        res = anchor(t54.LAMBDA_TI, g_mod=gm, mount="gap")
                        pt[f"t_anode_gap_{foot:.0f}x{foot:.0f}x{thick:.0f}_C"] = round(
                            t54.t_anode(res["g_total"], rw, ta_air, td), 2)
                    grid.append(pt)
    n_deg = sum(1 for p in grid if p["degenerate_reservoir_below_gate"])
    live = [p for p in grid if not p["degenerate_reservoir_below_gate"]]
    ti_fail = [p for p in live if not p["ti_bus_gate_pass"]]
    # Name the DISCRIMINATING axis, not every value present: λ_wood spans all four in the failing set
    # (so it discriminates nothing); T_deep does — a nearly cold-soaked core is what removes the budget.
    fail_cold_core = [p for p in ti_fail if p["t_deep"] <= 0.0]
    fail_warm_core = [p for p in ti_fail if p["t_deep"] > 0.0]
    teg_pass = [p for p in live if p["t_anode_gap_8x8x4_C"] >= t54.CELL_FREEZE_C]
    print(f"  {len(grid)} points · {n_deg} DEGENERATE (T_deep ≤ gate → unreachable at any G, the tree is")
    print("    already frozen — those points cannot judge a TEG either way)")
    print(f"  Of the {len(live)} live points the Ti-bus baseline ITSELF already fails the gate in "
          f"{len(ti_fail)}, and the")
    print(f"    discriminating axis is the CORE, not the wood: {len(fail_cold_core)} of them sit at "
          f"T_deep 0 °C (a nearly cold-soaked")
    if fail_warm_core:
        print(f"    trunk), the remaining {len(fail_warm_core)} at T_deep +2 with the lowest-λ wood "
              f"(λ_wood {min(p['lambda_wood'] for p in fail_warm_core):.2f}) — so λ_wood does not")
        print("    discriminate on its own.")
    else:
        # Not a formatting edge case: at the canon rod Ø1.0 the warm-core set is EMPTY, i.e. the residual
        # Ti bridge no longer removes the whole allowance anywhere the trunk is still above the gate.
        print("    trunk) and — at the canon rod Ø1.0 — that is ALL of them: not one warm-core point")
        print("    (T_deep +2) fails on the Ti bus alone. The baseline failure is a property of a")
        print("    cold-soaked trunk, no longer of the bus.")
    print("    There a TEG is not marginal — the residual Ti bridge has already spent the allowance.")
    print(f"  Smallest catalogue module (8×8×4, gap mount) passes the gate in {len(teg_pass)} of "
          f"{len(live)} live points")
    print(f"  G_TEG budget over the live grid: {min(budget_grid):.2e} … {max(budget_grid):.2e} W/K "
          "(negative = zero headroom:")
    print("    the residual Ti bridge already spends the whole allowance before any TEG is added)")

    # ── 5. Sensitivities that could have rescued it ──
    banner("Sensitivities — the two objections that could plausibly overturn this")
    gm_fill = g_teg(KAPPA_FILL_LOWER, 8.0, 4.0)
    res_fill = anchor(t54.LAMBDA_TI, g_mod=gm_fill, mount="gap")
    t_fill = t54.t_anode(res_fill["g_total"], r_wood, t_air, t_deep)
    print("  (a) FILL FACTOR — real modules are ~20–40 % legs, so κ_eff over the full footprint is an")
    print(f"      over-estimate. At the leg-only lower bound κ_eff={KAPPA_FILL_LOWER}: smallest module "
          f"8×8×4 → G={gm_fill:.3e} W/K,")
    print(f"      T_anode={t_fill:+.2f} °C → "
          f"{'still ❄FAIL' if t_fill < t54.CELL_FREEZE_C else 'PASSES (verdict would change!)'}")
    a_bus_fat = np.pi / 4.0 * D_BUS_UPPER_BOUND_MM ** 2
    ti_fat = anchor(t54.LAMBDA_TI, a_bus=a_bus_fat)["g_total"]
    gm_ref = g_teg(KAPPA_BASE, 8.0, 4.0)
    t_fat = t54.t_anode(anchor(t54.LAMBDA_TI, g_mod=gm_ref, mount="gap", a_bus=a_bus_fat)["g_total"],
                        r_wood, t_air, t_deep)
    t_rod = t54.t_anode(anchor(t54.LAMBDA_TI, g_mod=gm_ref, mount="gap")["g_total"], r_wood, t_air, t_deep)
    print("  (b) BUS DIAMETER cannot move this verdict, and that is worth measuring rather than assuming.")
    print(f"      Baseline is the canon rod Ø{t54.D_BUS:.1f}; the fattest physically possible bus is the "
          f"Ø{D_BUS_UPPER_BOUND_MM:.1f} channel it threads (01_01 §1.4).")
    print(f"      Bus alone: G {base_ti['g_total']:.3e} → {ti_fat:.3e} W/K "
          f"(a real {100 * (ti_fat / base_ti['g_total'] - 1):.0f} % shift).")
    print(f"      With the smallest module on top: T_anode {t_rod:+.2f} → {t_fat:+.2f} °C — the module")
    print(f"      conductance is ×{gm_ref / base_ti['g_total']:.0f} the whole anchor, so the bus Ø cannot "
          "move this verdict.")

    # ── Verdict ──
    banner("Verdict")
    print(f"  1. 🔴 NO catalogue geometry passes: {len(rows) * 2 - n_pass} of {len(rows) * 2} (footprint × "
          "thickness × κ × mount)")
    print(f"     combinations FAIL the {t54.CELL_FREEZE_C:+.1f} °C gate. The smallest part swept (8×8×4 mm) "
          "already carries")
    print(f"     ×{small['x_vs_ti_bus_anchor']:.0f} the conductance of the ENTIRE anchor and puts the pocket "
          f"at {small['gap']['t_anode_C']:+.1f} °C.")
    print(f"  2. 🔴 It is not a partial defeat. A gap-spanning module saturates at {t_gap_inf:+.1f} °C, "
          f"{abs(t_gap_inf - t_solid):.2f} °C from a")
    print(f"     SOLID Ti anchor with no PEEK break at all ({t_solid:+.1f} °C) — the exact condition Zone 2 "
          "exists to")
    print("     prevent (01_01 §4.1: cambium crystallisation).")
    print(f"  3. The budget is the number to keep: ≤ {budgets['gap']['g_teg_max_W_K']:.1e} W/K ≈ "
          f"{budgets['gap']['footprint_mm2_at_kappa1p4_t3mm']:.1f} mm² at 3 mm —")
    print(f"     ×{ratio_gap:.0f} smaller than the smallest module swept, and over 54's live wood grid the "
          f"budget goes NEGATIVE (min {min(budget_grid):.1e} W/K).")
    # The RELATION to the target is derived, not asserted: the yield is computed a few lines up, so a
    # hardcoded "inside" becomes a lie the moment the budget moves — it already had (428 µW vs 50-200).
    p_res = out_b["p_uW"]
    rel = "inside" if TARGET_UW[0] <= p_res <= TARGET_UW[1] else ("above" if p_res > TARGET_UW[1] else "below")
    print(f"  4. ⚖️ The honest residual: at the budget the part still yields ~{p_res:.0f} µW — {rel} "
          f"HW.21's own {TARGET_UW[0]:.0f}–{TARGET_UW[1]:.0f} µW")
    print(f"     target — but at ZERO gate margin, at V_oc ≈ {v_oc_1couple_mv:.0f} mV "
          f"(×{VIN_CS_MV / v_oc_1couple_mv:.0f} under VIN(CS) {VIN_CS_MV:.0f} mV, HW.46), as a")
    print("     bespoke sub-mm² micro-TEG. That is a different project, not a module choice.")
    print("  5. Same SHAPE as the already-ratified HW.42: the conductance that harvests IS the conductance")
    print("     that kills the break, exactly as the power that helps IS the power that poisons delta_t.")
    print("     Both rejections are structural, not budgetary — no number moves them.")
    print("  6. ⚠️ Hypothesis, `00_06 §0`: 1D ladder, steady state, ideal straps/collars, literature κ/ZT.")
    print("     in-silico ≠ measured. What this cannot see → caveats in the cache + SUMMARY.")

    # ── Plot ──
    _fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5))
    ax1.semilogx(g_axis, t_axis, color="tab:blue", linewidth=2, label="gap mount (TEG ∥ 6 mm gap)")
    t_sleeve_axis = [t54.t_anode(anchor(t54.LAMBDA_TI, g_mod=gm, mount="sleeve")["g_total"],
                                 r_wood, t_air, t_deep) for gm in g_axis]
    ax1.semilogx(g_axis, t_sleeve_axis, color="tab:purple", linewidth=2,
                 label="sleeve mount (TEG ∥ whole break)")
    ax1.axhline(t54.CELL_FREEZE_C, color="tab:red", linestyle="--", linewidth=2,
                label=f"cambium gate {t54.CELL_FREEZE_C:+.1f} °C")
    ax1.axhline(t_solid, color="0.4", linestyle=":", label=f"solid Ti, NO break ({t_solid:+.1f} °C)")
    ax1.axhline(t_ti, color="tab:green", linestyle="-.", label=f"residual Ti bus, no TEG ({t_ti:+.2f} °C)")
    for foot, thick in ((8.0, 4.0), (15.0, 3.0), (40.0, 3.0)):
        gm = g_teg(KAPPA_BASE, foot, thick)
        ax1.axvline(gm, color="0.75", linewidth=0.8)
        ax1.annotate(f"{foot:.0f}×{foot:.0f}", (gm, -27), fontsize=7, rotation=90, ha="right")
    ax1.set_xlabel("TEG module thermal conductance G_TEG (W/K, log)")
    ax1.set_ylabel("Zone-1 anode pocket temperature (°C)")
    ax1.set_title(f"The break vs the module (T_air={t_air:.0f} °C, T_deep={t_deep:+.0f} °C)")
    ax1.legend(fontsize=7)
    ax1.grid(True, alpha=0.3)

    ax2.loglog(g_axis, p_axis, color="tab:orange", linewidth=2, label="P_max at the surviving ΔT")
    ax2.axvline(g_opt, color="tab:orange", linestyle=":", label=f"thermal match ({g_opt:.1e} W/K)")
    ax2.axvspan(g_axis[0], max(budgets["gap"]["g_teg_max_W_K"], g_axis[0]), color="tab:green", alpha=0.15,
                label="gate-admissible G_TEG")
    ax2.axhspan(*TARGET_UW, color="tab:blue", alpha=0.12,
                label=f"HW.21 target {TARGET_UW[0]:.0f}–{TARGET_UW[1]:.0f} µW")
    ax2.set_xlabel("TEG module thermal conductance G_TEG (W/K, log)")
    ax2.set_ylabel("Module electrical output P_max (µW, log)")
    ax2.set_title("What it gives — and where the gate lets it live")
    ax2.legend(fontsize=7)
    ax2.grid(True, alpha=0.3, which="both")
    plt.tight_layout()
    fig_path = OUT_DIR / "teg_across_peek_break.png"
    plt.savefig(fig_path, dpi=150)
    print(f"\n  Plot: {fig_path.relative_to(REPO_ROOT)}")

    out = {
        "hypothesis_gate": "in-silico, NOT measured (00_06 §0 Validation Gate). Every number below is a "
                           "hypothesis-grade closed-form estimate on literature inputs.",
        "method": "Script 54's 1D lumped thermal-resistance ladder, imported (not copied) and extended with "
                  "a TEG conductance branch G_TEG = kappa_eff*A/t. Two mounts: 'gap' (G_TEG parallel to the "
                  "L_g PEEK-only gap segment, in series with both Ti shanks) and 'sleeve' (G_TEG parallel to "
                  "the whole flange->anode anchor, alongside the PEEK wall). Steady-state 2-node anode "
                  "divider vs the wood spreading resistance, same -2.0 C cambium gate. Module output "
                  "P_max = (ZT/T_mean)*G_TEG*dT^2/4 at matched electrical load (equivalent to S^2*dT^2/(4R) "
                  "via Z = S^2/(R*K)), evaluated at the dT that SURVIVES the module's own installation. "
                  "No FEA, no DFT.",
        "ladder_identity_check": "anchor() re-derives script 54's cached Ti / no-bus / Cu g_total to "
                                 "rtol 1e-12; the run aborts otherwise. Script 54 and its cache are NOT "
                                 "modified by this script.",
        "literature_inputs": {
            "kappa_teg_W_mK": list(KAPPA_SWEEP),
            "kappa_source": "Bi2Te3-alloy RT thermal conductivity ~1.2-1.6 W/(m.K). Poudel et al., Science "
                            "320(5876) 634-638 (2008), doi:10.1126/science.1156446 (Crossref-verified); "
                            "Goldsmid, Introduction to Thermoelectricity 2nd ed., Springer Series in "
                            "Materials Science (2016), doi:10.1007/978-3-662-49256-7 (Crossref-verified). "
                            "Applied over the FULL module footprint = deliberately conservative (a real "
                            "module is only ~20-40% legs); the fill-factor lower bound is computed below.",
            "kappa_fill_lower_bound_W_mK": KAPPA_FILL_LOWER,
            "zt_module": ZT_MODULE, "zt_bracket": list(ZT_BRACKET),
            "zt_note": "commercial Bi2Te3 module near 300 K; material ZT ~1.0 (Goldsmid), module-level lower "
                       "through contacts/ceramics. P scales LINEARLY with ZT.",
            "seebeck_leg_V_K": S_LEG_V_K,
            "couple_density_mm2": COUPLE_DENSITY_MM2,
            "couple_density_note": "ASSUMPTION, not literature (127-couple / 40x40 mm form factor). Sets "
                                   "V_oc only; P_max does not use it.",
            "bq25570_vin_cs_mV": VIN_CS_MV,
        },
        "baseline_from_script_54": {
            "t_air_C": t_air, "t_deep_C": t_deep, "lambda_wood": t54.LAMBDA_WOOD_BASE, "r_res_mm": 150.0,
            "r_wood_K_W": r_wood, "cell_freeze_threshold_C": t54.CELL_FREEZE_C,
            "gap_length_mm": base_ti["l_gap"],
            "ti_bus_g_anchor_W_K": base_ti["g_total"], "ti_bus_t_anode_C": round(t_ti, 2),
            "no_bus_g_anchor_W_K": g_none, "no_bus_t_anode_C": round(t_none, 2),
            "solid_ti_no_break_g_W_K": g_solid, "solid_ti_no_break_t_anode_C": round(t_solid, 2),
            "gap_mount_asymptote_g_W_K": g_gap_inf, "gap_mount_asymptote_t_anode_C": round(t_gap_inf, 2),
            "asymptote_vs_no_break_delta_C": round(abs(t_gap_inf - t_solid), 2),
        },
        "catalogue_sweep": {"n_geometries": len(rows), "n_mount_combinations": len(rows) * 2,
                            "n_gate_passes": n_pass, "rows": rows},
        "thermal_budget": {"g_anchor_max_at_gate_W_K": g_max_base, "by_mount": budgets,
                           "smallest_swept_module_mm2": smallest,
                           "smallest_module_over_budget_x": ratio_gap,
                           "at_budget": {"g_teg_W_K": gm_budget, "t_anode_C": round(ta_b, 2),
                                         "dT_module_K": round(dt_b, 2), "p_uW": round(out_b["p_uW"], 1),
                                         "v_oc_single_couple_mV": round(v_oc_1couple_mv, 2),
                                         "vin_cs_shortfall_x": round(VIN_CS_MV / v_oc_1couple_mv, 1)}},
        "power_optimum": {"g_teg_W_K": g_opt, "p_uW": round(p_opt, 1), "t_anode_C": round(t_opt, 2),
                          "equivalent_footprint_mm2_at_kappa1p4_t3mm": round(a_opt, 2),
                          "gate_pass": bool(t_opt >= t54.CELL_FREEZE_C),
                          "note": "P ~ G*dT^2 and dT ~ 1/G past the match, so a BIGGER module gives LESS: "
                                  "8x8x4 -> {:.0f} uW vs 40x40x3 -> {:.0f} uW.".format(
                                      small["gap"]["p_uW"], big["gap"]["p_uW"])},
        "robustness_grid": {"n_points": len(grid), "n_degenerate_reservoir_below_gate": n_deg,
                            "n_live": len(live),
                            "n_live_where_ti_bus_baseline_itself_fails": len(ti_fail),
                            "ti_bus_failure_axis": {
                                "n_at_cold_soaked_core_t_deep_le_0": len(fail_cold_core),
                                "n_at_warm_core_t_deep_gt_0": len(fail_warm_core),
                                "note": "The discriminating axis is the CORE reservoir, not the wood: "
                                        "lambda_wood takes ALL FOUR swept values inside the failing set, so "
                                        "it separates nothing. Naming lambda_wood here would be a true list "
                                        "and a false cause."},
                            "n_live_where_smallest_module_passes": len(teg_pass),
                            "g_teg_budget_min_W_K": min(budget_grid),
                            "g_teg_budget_max_W_K": max(budget_grid), "grid": grid},
        "sensitivities": {
            "fill_factor_lower_bound": {"kappa_W_mK": KAPPA_FILL_LOWER, "module": "8x8x4 mm",
                                        "g_teg_W_K": gm_fill, "t_anode_C": round(t_fill, 2),
                                        "gate_pass": bool(t_fill >= t54.CELL_FREEZE_C)},
            "bus_diameter_immaterial": {
                "d_bus_baseline_mm": t54.D_BUS, "d_bus_upper_bound_mm": D_BUS_UPPER_BOUND_MM,
                "ti_bus_g_anchor_baseline_W_K": base_ti["g_total"], "ti_bus_g_anchor_upper_W_K": ti_fat,
                "t_anode_with_8x8x4_baseline_C": round(t_rod, 2),
                "t_anode_with_8x8x4_upper_C": round(t_fat, 2),
                "g_teg_over_anchor_x": gm_ref / base_ti["g_total"],
                "note": "Baseline is the canon rod O1.0 (01_01 1.4, lib D_BUS_ROD_MM); the O1.35 cathode "
                        "channel is the fattest a bus could physically be. Widening to it shifts the "
                        "bare-anchor conductance materially but CANNOT move this verdict, because the "
                        "smallest swept module conducts orders of magnitude more than the whole anchor "
                        "either way. Script 54 and its cache are not modified by this run."},
        },
        "verdict": ("REJECT as posed. No catalogue Bi2Te3 geometry passes ({}/{} footprint x thickness x "
                    "kappa x mount combinations fail) the -2.0 C cambium gate: the smallest part swept "
                    "(8x8x4 mm) already conducts ~{:.0f}x the ENTIRE anchor and drops the Zone-1 pocket to "
                    "{:.1f} C. It is not a partial defeat - a gap-spanning module saturates at {:.1f} C, "
                    "within {:.2f} C of a SOLID Ti anchor with no PEEK break at all ({:.1f} C), i.e. it "
                    "reverts the design to exactly the pre-PEEK condition Zone 2 exists to prevent "
                    "(01_01 4.1). The budget for anything crossing the break is <= {:.1e} W/K (~{:.1f} mm2 "
                    "at 3 mm, x{:.0f} smaller than the smallest module), and over the live wood grid that "
                    "budget goes NEGATIVE. Honest residual: at the budget a bespoke sub-mm2 micro-TEG still "
                    "yields ~{:.0f} uW - {} HW.21's own 50-200 uW target - but at zero gate margin and "
                    "V_oc ~{:.0f} mV, x{:.0f} below BQ25570 VIN(CS) 600 mV (HW.46). Same structural shape as "
                    "the ratified HW.42: the conductance that harvests IS the conductance that kills the "
                    "break."
                    ).format(len(rows) * 2 - n_pass, len(rows) * 2, small["x_vs_ti_bus_anchor"],
                             small["gap"]["t_anode_C"], t_gap_inf, abs(t_gap_inf - t_solid), t_solid,
                             budgets["gap"]["g_teg_max_W_K"],
                             budgets["gap"]["footprint_mm2_at_kappa1p4_t3mm"], ratio_gap,
                             out_b["p_uW"], rel, v_oc_1couple_mv, VIN_CS_MV / v_oc_1couple_mv),
        "caveats": "HYPOTHESIS, not measurement (00_06 0). WHAT THE 1D LADDER CANNOT SEE: "
                   "(1) 3-D SPREADING - a real module is a flat PLATE bolted onto a O11-15 mm cylinder, so "
                   "heat converges into and diverges out of its footprint in 3-D. The 1D ladder cannot "
                   "represent that constriction: it assumes the whole footprint is thermally engaged, which "
                   "OVERSTATES G_TEG (and thus the harm), while it equally misses the lateral bark/air "
                   "paths that would partly bypass the module. "
                   "(2) CONTACT RESISTANCE - collars, straps, thermal interface material and the module's "
                   "two alumina faces are ALL modelled as zero. A real 50 mm strap (Al, 20 mm2) is ~0.08 "
                   "W/K, the same order as the module itself, so the sleeve mount in particular is an "
                   "idealisation. Adding them lowers G_TEG (less harm) AND lowers the dT reaching the faces "
                   "(less power): they shrink both sides of the trade, they do not rescue it. "
                   "(3) THE MODULE'S OWN LEG GEOMETRY - fill factor, leg aspect ratio, ceramic thickness "
                   "and the Peltier/Thomson back-reaction under electrical load are all folded into one "
                   "kappa_eff and one module ZT. A purpose-optimised part could shift G_TEG by ~2-3x; the "
                   "fill-factor sensitivity brackets that and the verdict survives. "
                   "(4) TRANSIENTS AND SEASONAL REVERSAL - steady state only. The ladder cannot see the "
                   "summer reversal (heat piped INWARD, tissue desiccation, 01_01 4.1) nor freeze-thaw "
                   "cycling, both of which a permanently installed conductive plate makes worse, not better. "
                   "(5) The wood reservoir (lambda_wood, R_res, T_deep) is swept, not known; 16 of the 48 "
                   "grid points are DEGENERATE (reservoir at/below the gate). "
                   "(6) Only bench validation (Cherkasy winter) and conjugate 3-D FEA can turn any of this "
                   "into a measurement.",
    }
    json_path = OUT_DIR / "teg_across_peek_break.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    # gate: the finding is only meaningful if the smallest catalogue module really does dwarf the anchor
    return 0 if small["x_vs_ti_bus_anchor"] > 3.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
