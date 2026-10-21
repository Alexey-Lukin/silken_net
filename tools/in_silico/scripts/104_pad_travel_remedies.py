#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""104 — what each remedy for the centre pad's thermal travel buys against the pogo window and costs on the seam
(00_07 HW.43, the leg «ціни ліків ходу центральної площадки» — applied: ⚖️ founder 2026-10-21 chose (б), `52`'s L3
rung, 02_02 §3.5; no solve).

WHY. `102` (2026-10-20) found the centre pad leaving `90`'s L1 margin on the free-sleeve reading — at the cold edge on
every part and grip, at the hot edge on a part at the window floor — and `103` that within its model the wood only
shortens that thermal travel. The leg asks for each remedy's price in µm against the margin and in load on the seam, on
both of `102`'s spans, before a verdict.

READINGS TAKEN.
- Two readings of the pad against the window, each priced. HELD: the seasonal edges alone — the whole travel in state 1,
  the anchor's first winter before the callus, where `103`'s share is 0 (unless ice in the gap ties the anode at the cold
  edge — not bounded). HELD + SWAY: once the wood holds the anchor (states 2–3) the sway rides ON the seasonal position —
  unlike `90`'s daily swing, which lies inside the seasonal edges `90` already judges — so the window takes their sum: the
  held part at the state's effective CTE (the wood shortens it), the sway at the same state's share, both read off
  `103`'s (CTE, share) front; the sum is bounded from above on the kept front (each kept CTE with the next kept share), at
  `87`'s median ⊥ upper-whisker shift (each at its high end), the held part and the sway maximised over the grips
  separately — an upper end of the sum.
- The Zone-3 shank on the 18 mm span is read bonded to the PEEK over its run (lib.mechanics, the fits' one rule); the
  need with it read as Ti is printed and is smaller, so the bonded reading is the adverse end.
- Every grip of `102`'s window: the three parts × relaxed or not × μ's two ends (`102`'s heat reads four of them); the
  worst at both temperature readings (`90`'s capsule model edges — a ceiling for a sleeve inside wood — ⊥ `79`'s cambium
  under the flange), against both of `90`'s isothermal stack readings (low ⊥ high stack); `90`'s radome-leads reading —
  where L1 breaks for the outer pad already — is priced apart.

REMEDIES, by family; they combine. The NEED is what the pad's travel exceeds the margin by, the larger of the two edges.
(1) δ itself — what grows between the anode's face and the flange's seat. (1a) The PEEK run's length: on the 18 mm span the
    gap, so the Zone-3 shank grows by as much (`55`: gap = sleeve − Zone-1 insertion − shank; liner run = shank + flange +
    protrusion; bare run = gap − protrusion); on the 32 mm span the PEEK above the anode, the gap first and then the shank.
    (1b) The PEEK run's effective CTE (a filled grade). Both also lower the seam's hot preload.
(2) The pin's working window: a longer stroke with the deck re-spaced so the nominal compression stays at 60 % (as `52`
    builds the gap) adds the window's half-width — 0.1 µm per µm of stroke — to each of `90`'s margins (half-width ×
    stroke − residual − the stack's own thermal term); kept at today's gap the margins move −0.5 ⊥ +0.7 µm per µm instead.
(3) The L1 residual, `52`'s rule rss(CNC member, spacer half-step), rounded as `52`'s cache and `90` carry it: the bayonet
    hard-stop (L2 — the member 0.10 → 0.05, as `52` models deterministic engagement) ⊥ the same 0.05 by a tolerance class on
    the radome (only if the member is machining tolerance — `52` names it engagement, whose play a hard-stop removes and a
    tolerance class may not) ⊥ a finer spacer step ⊥ L2 with a finer step.
(2) and (3) leave δ — and the seam's load — as they are, and they lift `90`'s outer pad as well. Holding the pad stiffer is
not a remedy: the liner wall caps how far the wire stretches, so a stiffer grip moves the rest of δ onto the seam (`102`).

MODEL. `102`'s Pair (closed form, rigid stick, Coulomb slip) on `102`'s inputs, rebuilt from the same sources (`55`'s
window rows, `90`'s temperatures and margins, `79`'s cambium); the seam on `102`'s `soderberg_k` with `86`'s inputs.

CAN: per span, temperature and stack reading — the need on both readings; what each remedy adds or removes in µm and the
spare it leaves; the stroke, PEEK run length and effective CTE at which the need closes; the hot preload on the seam and
`86`'s seam requirement with `103`'s sway corners on top (its least corners and its caps), per alloy, at each δ remedy
against today; the need's sensitivity to the placeholder shank; the sway alone against L1. Controls: (a) the
rebuilt pair re-derives `102`'s cached pad travel at its four readings on both spans with the shank as Ti (a drifted
input, grip rule, span or temperature); (b) the seam re-derives `102`'s share-0 requirement on 32 mm and `103`'s state-1
one on 18 mm (a wrong preload corner or alloy row), (b2) and `103`'s least sway corners (a wrong corner or share); (c)
`52`'s rule rounded as `52` caches it re-derives `90`'s two residuals and `90`'s L2 − L1 margin step (a residual read off
the wrong member); (e) the geometry at the closing gap against `55`'s own relations (a sign error in the shank's update,
a dropped protrusion); (f) the front's share-0 end, shank as Ti at `103`'s CTE, re-derives the held need with the shank
bonded (`103`'s CTE convention against this script's). None sees an error `102` or `103` shares.
CANNOT: (1) any grade's CTE or modulus — (1b) is a threshold, and a filled grade also moves the Zone 1↔2 press-fit
(`50`/`51`/`56` and its ratified band) and the liner's thermal grip; (2) whether the hard-stop acts under branch (а) —
`52`'s rerun at the root move — or whether a tolerance class reaches the member; (3) a longer pin's own free length, which
moves `90`'s thermal term (bounded by α_brass · ΔS · ΔT); nor the pin's own height — its travel tolerance, as far as it is
the plunger's free length, moves the compression at a fixed gap by its whole size and has no member in `52`'s chain
(00_07 HW.8.7); (4) the gap's other duties — the thermal break G1 set at 18 mm (`54`'s frost gate) and
the wire's unsupported run — and whether a shank longer than `92`'s sweep keeps its contact results: (1a) prices the
length only; (5) the sway's own phase against the seasonal edge (the sum is the coincidence of the two); (6) anything
`102` or `103` cannot (their CANNOT lists).

Run:  conda activate silken_md
      python tools/in_silico/scripts/104_pad_travel_remedies.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    CACHE_DIR,
    E_PEEK_PA,
    PEEK_RELAX_FLOOR,
    REPO_ROOT,
)
from lib.mechanics import bonded_fit_section
from lib.utils import banner

SI_DESCRIPTION = ("Prices of the remedies for the anchor's centre contact pad leaving the pogo pins' working window with "
                  "temperature: for each — a shorter or lower-expansion polymer run, a longer pin stroke, a smaller "
                  "stack-up residual — the micrometres it gains or removes against the window margin on both spans, with "
                  "the stem's sway on the seasonal position and without it, and the load it leaves on the bus wire's weld "
                  "seam, on the wire–liner shear-lag closed form; no solve")

MECH = CACHE_DIR / "mechanical"
OUT = MECH / "pad_travel_remedies.json"
PARTS = ("window_floor", "ratified_nominal", "window_ceiling")
GRIPS = tuple((part, relaxed, m) for part in PARTS for relaxed in (False, True) for m in ("min", "max"))
GRIPS_102 = (("window_floor", False, "min"), ("ratified_nominal", True, "min"), ("ratified_nominal", False, "min"),
             ("window_ceiling", False, "max"))   # the four `102`'s heat reads
STACKS = ("isothermal_low_stack", "isothermal_high_stack")
LEADS = "radome_leads_reading"
GAP_MIN = 0.5      # mm — the shortest bare run the length route goes down to (the wire still crossing the gap)
SPANS = {"gap_and_shank_disc_on_sleeve_top": "32", "gap_only_shank_held_at_its_end": "18"}
FRONT_OF = {"18": "zone3_fit", "32": "flange_on_bark"}       # `103`'s premise behind each span
SHANKS_HW89 = (10.0, 18.0)   # mm — `92`'s swept ends of the placeholder Zone-3 shank (HW.8.9)
L2 = "L2 bayonet hard-stop (CNC member 0.10 → 0.05 mm)"
CLASS = "the CNC member at ±0.05 mm by a tolerance class (if it is machining tolerance)"
ZERO = "spacer step → 0 (the lever's bound)"


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


s55 = _load("bus55", "55_bus_mechanical.py")
s52 = _load("zstack52", "52_z_stack_tolerance.py")
s102 = _load("liner102", "102_wire_liner_shear_lag.py")
STEP_FINE = s52.SPACER_STEP_FINE   # the finer spacer step — its home is `52` (the ratified L3 rung)
L3_90 = f"L3 spacer {STEP_FINE:g} mm + bayonet hard-stop"   # `90`'s window of that rung
FINE = f"spacer step {STEP_FINE:g} mm"
L2FINE = f"L2 hard-stop + spacer step {STEP_FINE:g} mm"


def bisect(fn, lo: float, hi: float, n: int = 100) -> float | None:
    """The root of a monotone fn on [lo, hi], or None if it does not change sign there."""
    flo = fn(lo)
    if (flo > 0) == (fn(hi) > 0):
        return None
    for _ in range(n):
        mid = 0.5 * (lo + hi)
        if (fn(mid) > 0) == (flo > 0):
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def ceil3(x: float) -> float:
    """`52`'s cache carries the residual to the micrometre, and `90` builds its margins on that; a remedy's residual is
    carried the same way, rounded up."""
    return math.ceil(round(x * 1000, 9)) / 1000


def down1(x: float) -> float:
    return math.floor(round(x * 10, 9)) / 10


def up1(x: float) -> float:
    return math.ceil(round(x * 10, 9)) / 10


def spare(x: float) -> str:
    """A spare reads «spare X» rounded down, a shortfall «short X» rounded up."""
    return f"spare {down1(x):.1f}" if x >= 0 else f"short {up1(-x):.1f}"


def up3(x: float) -> float:
    """A requirement («k ≥ X», «a stroke of at least X») rounds up (in-silico §When Modifying #43)."""
    return math.ceil(round(x * 1000, 9)) / 1000


def main() -> int:
    banner("104 — the centre pad's thermal travel: what each remedy buys (µm) and costs (seam)")
    d102 = json.loads((MECH / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    d90 = json.loads((MECH / "pogo_thermal_gap.json").read_text(encoding="utf-8"))
    d86 = json.loads((MECH / "coaxiality_allocation.json").read_text(encoding="utf-8"))
    d103 = json.loads((MECH / "anchor_wood_share.json").read_text(encoding="utf-8"))
    win = json.loads((MECH / "bus_mechanical.json").read_text(encoding="utf-8"))["interference_window"]
    cp = win["cold_press_fit"]
    rows55 = {row["at"]: row for row in cp["rows"]}
    mu = {"min": min(cp["mu_sweep"]), "max": max(cp["mu_sweep"])}

    # ── `102`'s inputs, from `102`'s sources ──
    area_w = math.pi * s55.D_BUS ** 2 / 4.0
    l55 = s55.LINER_LENGTH_MM
    prot = s55.LINER_PROTRUSION_MM
    gap0, shank0, flange = s55.PEEK_GAP_MM, s55.SHANK_LEN_MM, s55.FLANGE_THK_MM
    e_peek = E_PEEK_PA / 1e6
    ea_l = e_peek * cp["tube_section_mm2"]
    wall_cap = cp["peek_yield_MPa"] * cp["tube_section_mm2"]
    base = ALLOY_PROPERTIES[ALLOY_BASELINE]
    ea_w0 = base["E_GPa"] * 1e3 * area_w
    alpha_fl = base["alpha_1K"]
    dalpha_r = (ALPHA_PEEK_1K - alpha_fl) * s55.D_BUS / 2.0 * 1e3
    t_ref = d90["inputs"]["assembly_temperature_c"]
    t_fit = win["thermal"]["t_ref_c"]
    temps = {k: tuple(v) for k, v in d102["thermal"]["temperatures_c"].items()}
    t_hot = temps["capsule_model_edges_90"][1]
    geo77 = json.loads((MECH / "anchor_torque_path.json").read_text(encoding="utf-8"))["geometry"]
    a_sleeve = math.pi * ((geo77["sleeve_outer_radius_m"] * 1e3) ** 2 - (geo77["shank_radius_m"] * 1e3) ** 2)
    a_shank3 = math.pi / 4.0 * (s55.cem("cathode_flange")["shank_diameter_mm"] ** 2 - s55.D_CHANNEL_MM ** 2)

    def alpha_comp(alpha_peek: float) -> float:
        return bonded_fit_section(base["E_GPa"] * 1e3, alpha_fl, a_shank3, e_peek, alpha_peek, a_sleeve, PEEK_RELAX_FLOOR)[1]
    alpha_s3 = alpha_comp(ALPHA_PEEK_1K)

    def q_of(part: str, mu_v: float, relaxed: bool, t_c: float) -> float:
        i20 = rows55[part]["interference_radial_um"]
        i = max(0.0, i20 - dalpha_r * (t_c - t_fit))
        return rows55[part]["by_mu"][f"{mu_v:g}"]["friction_N"] / l55 * (i / i20) * (PEEK_RELAX_FLOOR if relaxed else 1.0)

    def geometry(span: str, gap: float, shank: float | None = None) -> tuple[float, float, float]:
        """(bare run a, liner run L, shank length): on the 18 mm span the shank takes up what the gap gives; on the 32 mm
        span the shank stays unless given."""
        if shank is None:
            shank = shank0 + (gap0 - gap) if span == "18" else shank0
        return gap - prot, shank + flange + prot, shank

    def shift_per_k(span: str, gap: float, alpha_run: float, alpha_w: float, shank_bonded: bool = True,
                    shank: float | None = None, alpha_s: float | None = None) -> float:
        """mm/K, + = the flange away from the anode; alpha_run is the PEEK run's CTE (the gap on 18, gap + shank on 32)."""
        a, L, sh = geometry(span, gap, shank)
        if span == "32":
            grow = alpha_run * (gap + sh) + alpha_fl * flange
        else:
            grow = alpha_run * gap + ((alpha_s or alpha_s3) if shank_bonded else alpha_fl) * sh + alpha_fl * flange
        return grow - alpha_w * (a + L)

    def travel(span: str, gap: float, alpha_run: float, shank_bonded: bool = True, shank: float | None = None,
               alpha_s: float | None = None, grips=GRIPS) -> dict:
        """The pad's cold protrusion and hot recession (µm) at each grip and temperature reading."""
        a, L, _ = geometry(span, gap, shank)
        per_k = shift_per_k(span, gap, alpha_run, alpha_fl, shank_bonded, shank, alpha_s)
        out = {}
        for tname, (t_lo, t_hi) in temps.items():
            for part, relaxed, m in grips:
                key = f"{tname}__{part}{'_relaxed' if relaxed else ''}__mu{mu[m]:g}"
                hot = s102.Pair(q_of(part, mu[m], relaxed, t_hi), ea_w0, ea_l * PEEK_RELAX_FLOOR, a, L, wall_cap)
                cold = s102.Pair(q_of(part, mu[m], relaxed, t_lo), ea_w0, ea_l * PEEK_RELAX_FLOOR, a, L, wall_cap)
                out[key] = {"cold": -cold.virgin(per_k * (t_lo - t_ref))[1] * 1e3,
                            "hot": hot.virgin(per_k * (t_hi - t_ref))[1] * 1e3}
        return out

    def edges(tr: dict) -> dict:
        return {t: {"cold": max(v["cold"] for k, v in tr.items() if k.startswith(t)),
                    "hot": max(v["hot"] for k, v in tr.items() if k.startswith(t))} for t in temps}

    def need(tr: dict, margins: dict, add: float = 0.0) -> dict:
        """Per temperature × stack reading: how far the worst grip's travel (plus `add` on both edges) exceeds the margin."""
        out = {}
        for t, e in edges(tr).items():
            for sname, (m_lo, m_hi) in margins.items():
                out[f"{t}__{sname}"] = {"cold_over_upper": e["cold"] + add - m_hi, "hot_over_lower": e["hot"] + add - m_lo,
                                        "need": max(e["cold"] + add - m_hi, e["hot"] + add - m_lo)}
        return out

    def worst(tr: dict, margins: dict, add: float = 0.0) -> float:
        return max(v["need"] for v in need(tr, margins, add).values())

    # ── control (a): `102`'s cached pad travel at its four readings, shank as Ti ──
    miss_a = 0.0
    for sname, sp in SPANS.items():
        for key, v in travel(sp, gap0, ALPHA_PEEK_1K, shank_bonded=False, grips=GRIPS_102).items():
            row = d102["thermal"]["by_reading"][f"{sname}__{key}"]
            miss_a = max(miss_a, abs(v["cold"] - row["cold"]["pad_protrudes_um"]), abs(v["hot"] - row["hot"]["pad_recedes_um"]))
    if miss_a > 0.006:
        raise RuntimeError(f"control (a): the rebuilt pair misses `102`'s cached pad travel by {miss_a:.4f} µm")

    # ── the seam: `102`'s hot preload corner (the tightest part at μ max, relaxed liner, the capsule's hot edge) ──
    shipped = d86["by_geometry"][next(k for k in d86["by_geometry"] if k.startswith("shipped"))]
    e86, amp86 = d86["branches"]["loose_50"]["radial_offset_budget_um"], shipped["amplitude_MPa"]

    def mean86(alloy: str) -> float:
        return next(o["mean_MPa"] for o in shipped["by_alloy"][alloy]["by_offset"] if o["offset_um"] == e86)

    def preload(alloy: str, span: str, gap: float, alpha_run: float, shank: float | None = None) -> dict:
        p = ALLOY_PROPERTIES[alloy]
        a, L, _ = geometry(span, gap, shank)
        pr = s102.Pair(q_of("window_ceiling", mu["max"], False, t_hot), p["E_GPa"] * 1e3 * area_w, ea_l * PEEK_RELAX_FLOOR,
                       a, L, wall_cap)
        f, _, capped = pr.virgin(shift_per_k(span, gap, alpha_run, p["alpha_1K"], shank=shank) * (t_hot - t_ref))
        return {"F_hot_N": f, "seam_k_no_sway": s102.soderberg_k(amp86, mean86(alloy), 0.0, f, area_w, shipped["by_alloy"][alloy]),
                "capped": capped}

    shift_hi = max(d102["sway_input"]["shift_um_87"]["upper_whisker"]) * 1e-3

    def seam_sway(alloy: str, sh: float, pre: float, gap: float) -> dict:
        """`103`'s corner: the sway reversed at `87`'s upper whisker on the tightest part at 20 °C (unrelaxed liner), the
        hot preload on its mean, clipped at the cap as `102` clips it."""
        p = ALLOY_PROPERTIES[alloy]
        a, L, _ = geometry("18", gap)
        pr = s102.Pair(q_of("window_ceiling", mu["max"], False, t_fit), p["E_GPa"] * 1e3 * area_w, ea_l, a, L, wall_cap)
        c = pr.cycle(sh * shift_hi, 0.0)
        f_mean, clipped = c["F_mean"] + pre, False
        if c["F_amp"] + f_mean > pr.cap + 1e-9:
            f_mean, clipped = pr.cap - c["F_amp"], True
        return {"k": s102.soderberg_k(amp86, mean86(alloy), c["F_amp"], f_mean, area_w, shipped["by_alloy"][alloy]),
                "cap_binds": clipped or c["capped"]}

    # control (b): `102`'s share-0 requirement on 32 mm and `103`'s state-1 one on 18 mm
    miss_b = 0.0
    for alloy in ("Ta", ALLOY_BASELINE):
        miss_b = max(miss_b, abs(preload(alloy, "32", gap0, ALPHA_PEEK_1K)["seam_k_no_sway"]
                                 - d102["seam_by_alloy"][alloy]["by_share"]["0"]["seam_k_adverse_with_preload"]),
                     abs(preload(alloy, "18", gap0, ALPHA_PEEK_1K)["seam_k_no_sway"]
                         - d103["zone3_fit"]["seam_on_102_closed_form"][alloy]["state1"]["hot_preload"]))
    if miss_b > 2e-4:
        raise RuntimeError(f"control (b): the seam misses `102`/`103`'s cached requirement by {miss_b:.5f}")
    sh3 = d103["zone3_fit"]["share"]
    corners = {"state2_at_air_dry_readings_max": sh3["state2_at_air_dry_readings"]["max"],
               "state3_least_stiff_bond": sh3["state3_no_bearing_any_depth_of_102_shift"]["anode_bond_stiff"]["min"],
               "state3_least_soft_bond": sh3["state3_no_bearing_any_depth_of_102_shift"]["anode_bond_soft"]["min"],
               "state2_cap_stiff_bond": sh3["state2_cap_rigid_bark"]["anode_bond_stiff"],
               "state2_cap_soft_bond": sh3["state2_cap_rigid_bark"]["anode_bond_soft"],
               "state3_cap_stiff_bond": sh3["state3_cap_rigid_bark_of_102_shift"]["anode_bond_stiff"],
               "state3_cap_soft_bond": sh3["state3_cap_rigid_bark_of_102_shift"]["anode_bond_soft"]}
    # control (b2): today's least corners re-derive `103`'s cached ones (its shares are rounded to 1e-4)
    z3 = d103["zone3_fit"]["seam_on_102_closed_form"]
    miss_b2 = 0.0
    for alloy in ("Ta", ALLOY_BASELINE):
        pre = preload(alloy, "18", gap0, ALPHA_PEEK_1K)["F_hot_N"]
        for name, cached in (("state2_at_air_dry_readings_max", z3[alloy]["state2_at_air_dry_readings_max"]),
                             ("state3_least_stiff_bond", z3[alloy]["state3_least_any_depth_and_bearing"]["anode_bond_stiff"]),
                             ("state3_least_soft_bond", z3[alloy]["state3_least_any_depth_and_bearing"]["anode_bond_soft"])):
            miss_b2 = max(miss_b2, abs(seam_sway(alloy, corners[name], 0.0, gap0)["k"] - cached["adverse_reversed"]),
                          abs(seam_sway(alloy, corners[name], pre, gap0)["k"] - cached["adverse_reversed_hot_preload"]))
    if miss_b2 > 2e-3:
        raise RuntimeError(f"control (b2): the sway corners miss `103`'s cached requirement by {miss_b2:.4f}")

    # ── the window side: `90`'s margins on `52`'s residuals as `52` caches them ──
    win90 = d90["seasonal"]["model_edges"]
    res90 = d90["inputs"]["mitigation_residual_mm_52"]
    stroke0 = d90["inputs"]["pogo_travel_mm"]
    half = d90["inputs"]["window"][1] - d90["inputs"]["nominal_pct"]        # of the stroke, each side
    cnc = s52.TOL_PZ["CNC_radome"]
    half_step = s52.SPACER_STEP / 2.0
    residual = {L2: ceil3(s52.rss([cnc / 2.0, half_step])), CLASS: ceil3(s52.rss([cnc / 2.0, half_step])),
                FINE: ceil3(s52.rss([cnc, STEP_FINE / 2.0])), ZERO: ceil3(cnc),
                L2FINE: ceil3(s52.rss([cnc / 2.0, STEP_FINE / 2.0]))}
    gain = {k: (res90["L1 spacer only"] - r) * 1e3 for k, r in residual.items()}
    # control (c): `52`'s rule as `52` caches it re-derives `90`'s residuals, and the L2 gain `90`'s own margin step
    l2_step = [w["window"]["L2 spacer + bayonet hard-stop"]["margin_um"][i] - w["window"]["L1 spacer only"]["margin_um"][i]
               for w in win90.values() for i in (0, 1)]
    l3_step = [w["window"][L3_90]["margin_um"][i] - w["window"]["L1 spacer only"]["margin_um"][i]
               for w in win90.values() for i in (0, 1)]
    miss_c = max(abs(ceil3(s52.rss([cnc, half_step])) - res90["L1 spacer only"]) * 1e3,
                 abs(residual[L2] - res90["L2 spacer + bayonet hard-stop"]) * 1e3, abs(residual[L2FINE] - res90[L3_90]) * 1e3,
                 *(abs(s - gain[L2]) for s in l2_step), *(abs(s - gain[L2FINE]) for s in l3_step))
    if miss_c > 0.05 + 1e-9:
        raise RuntimeError(f"control (c): `52`'s residual rule misses `90`'s residuals or L2 step by {miss_c:.3f} µm")

    l1 = {s: tuple(win90[s]["window"]["L1 spacer only"]["margin_um"]) for s in STACKS}
    l1_leads = {LEADS: tuple(win90[LEADS]["window"]["L1 spacer only"]["margin_um"])}
    brass = d90["inputs"]["alpha_brass_c36000_1K"] * max(abs(t - t_ref) for ts in temps.values() for t in ts)

    def stroke_for(n: float) -> float:
        return stroke0 + max(n, 0.0) / (half * 1e3)

    def sway_amp(span: str, sh: float, rd: str) -> float:
        """The pad's sway amplitude (µm) at a share of `102`'s shift — `87`'s reading at its high end, reversed, the worst
        grip at 20 °C on the unrelaxed liner."""
        a, L, _ = geometry(span, gap0)
        return max(s102.Pair(q_of(part, mu[m], relaxed, t_fit), ea_w0, ea_l, a, L, wall_cap)
                   .cycle(sh * max(d102["sway_input"]["shift_um_87"][rd]) * 1e-3, 0.0)["pad_amp"] * 1e3 for part, relaxed, m in GRIPS)

    shift_um = {rd: max(d102["sway_input"]["shift_um_87"][rd]) for rd in ("median", "upper_whisker")}
    held_front = {}

    def with_sway(span: str, margins: dict, rd: str) -> dict:
        """The need on the held + sway reading, bounded from above: the held travel at each kept front CTE plus the sway's
        SHIFT at the NEXT kept share. The pad travel is the shift less the wire's stretch, which never falls as the shift
        grows, so the travel rises by at most the shift added to it — the sway's increment is bounded by its own shift on
        `102`'s pair, whatever the grip — and every configuration between two kept points lies in that box."""
        fr = d103[FRONT_OF[span]]["cte_share_front"] if span == "18" else d103["cte_share_front"]
        ctes, shs = fr["cte_ppm_K"], fr["share_of_102_shift"]
        if span not in held_front:
            held_front[span] = [travel(span, gap0, c * 1e-6, shank_bonded=False) for c in ctes]
        held = held_front[span]
        best, upper, lower = None, -1e9, -1e9
        for i, tr in enumerate(held):
            g = shs[min(i + 1, len(shs) - 1)] * shift_um[rd]
            per = need(tr, margins, g)
            n = max(v["need"] for v in per.values())
            upper = max(upper, *(v["cold_over_upper"] for v in per.values()))
            lower = max(lower, *(v["hot_over_lower"] for v in per.values()))
            if best is None or n > best["need"]:
                best = {"need": n, "cte_ppm_K": ctes[i], "share": shs[min(i + 1, len(shs) - 1)], "sway_shift_um": g}
        best["cold_over_upper"], best["hot_over_lower"] = upper, lower
        best["need_on_kept_points"] = max(worst(tr, margins, s * shift_um[rd]) for tr, s in zip(held, shs, strict=True))
        best["free_sleeve_need"] = worst(held[0], margins)
        return best

    by_span = {}
    for sp in SPANS.values():
        tr = travel(sp, gap0, ALPHA_PEEK_1K)
        n_iso, n_leads = worst(tr, l1), worst(tr, l1_leads)
        n_ti = worst(travel(sp, gap0, ALPHA_PEEK_1K, shank_bonded=False), l1)
        sway_n = {rd: with_sway(sp, l1, rd) for rd in ("median", "upper_whisker")}
        sway_leads = {rd: with_sway(sp, l1_leads, rd) for rd in ("median", "upper_whisker")}
        held_per = need(tr, l1)
        # control (f): the front's share-0 end (shank as Ti at `103`'s CTE) is the held need with the shank bonded
        if abs(sway_n["median"]["free_sleeve_need"] - n_iso) > 0.01:
            raise RuntimeError(f"control (f): `103`'s free-sleeve CTE gives {sway_n['median']['free_sleeve_need']:.3f} µm "
                               f"against the held need {n_iso:.3f}")
        # (1a) the PEEK run's length, (1b) its effective CTE — each closing the held need
        g_lo = prot + GAP_MIN
        gap_star = bisect(lambda g, sp=sp: worst(travel(sp, g, ALPHA_PEEK_1K), l1), g_lo, gap0)
        shank_star = None
        if gap_star is None and sp == "32":   # the gap alone cannot: the shank's run is PEEK on this span too
            shank_star = bisect(lambda s, sp=sp, g=g_lo: worst(travel(sp, g, ALPHA_PEEK_1K, shank=s), l1), 0.0, shank0)
        alpha_star = bisect(lambda al, sp=sp: worst(travel(sp, gap0, al), l1), alpha_fl, ALPHA_PEEK_1K)
        alpha_star_both = (bisect(lambda al: worst(travel("18", gap0, al, alpha_s=alpha_comp(al)), l1), alpha_fl, ALPHA_PEEK_1K)
                           if sp == "18" else alpha_star)
        if alpha_star is None or (gap_star is None and shank_star is None):
            raise RuntimeError("a δ route does not close the held need on the span's geometry")
        if gap_star is not None:
            # control (e): the closing geometry against `55`'s own relations
            a_x, l_x, sh_x = geometry(sp, gap_star)
            if (abs(a_x - (gap_star - s55.LINER_PROTRUSION_MM)) > 1e-9 or abs(l_x - (sh_x + s55.FLANGE_THK_MM + s55.LINER_PROTRUSION_MM)) > 1e-9
                    or (sp == "18" and abs(gap_star + sh_x - (s55.SLEEVE_LEN_MM - s55.Z1_INSERTION_MM)) > 1e-9)):
                raise RuntimeError("control (e): the closing geometry breaks `55`'s relations")
        run_route = ({"gap_mm": gap_star, "shank_mm": geometry(sp, gap_star)[2], "peek_run_mm": gap_star + (shank0 if sp == "32" else 0.0)}
                     if gap_star is not None else {"gap_mm": g_lo, "shank_mm": shank_star, "peek_run_mm": g_lo + shank_star})
        seam_len = {alloy: preload(alloy, sp, run_route["gap_mm"], ALPHA_PEEK_1K, None if gap_star is not None else shank_star)
                    for alloy in ALLOY_PROPERTIES}
        seam_cte = {alloy: preload(alloy, sp, gap0, alpha_star) for alloy in ALLOY_PROPERTIES}
        seam_today = {alloy: preload(alloy, sp, gap0, ALPHA_PEEK_1K) for alloy in ALLOY_PROPERTIES}
        by_span[sp] = {
            "travel_um_max": edges(tr), "need_um": need(tr, l1), "need_um_isothermal_worst": n_iso,
            "need_um_isothermal_worst_shank_as_ti": n_ti if sp == "18" else None,
            "need_um_radome_leads": n_leads, "need_um_radome_leads_by_temp": need(tr, l1_leads),
            "need_um_held_plus_sway": sway_n, "need_um_held_plus_sway_radome_leads": sway_leads,
            "window_breach_pct_of_stroke": {
                "held": {"over_upper_edge": max(v["cold_over_upper"] for v in held_per.values()) / (stroke0 * 10),
                         "under_lower_edge": max(v["hot_over_lower"] for v in held_per.values()) / (stroke0 * 10)},
                **{f"held_plus_sway_{rd}": {"over_upper_edge": v["cold_over_upper"] / (stroke0 * 10),
                                            "under_lower_edge": v["hot_over_lower"] / (stroke0 * 10)} for rd, v in sway_n.items()}},
            "window_side": {k: {"gain_um": g, "spare_um_held": g - n_iso, "spare_um_radome_leads": g - n_leads,
                                **{f"spare_um_held_plus_sway_{rd}": g - sway_n[rd]["need"] for rd in sway_n},
                                **{f"spare_um_held_plus_sway_{rd}_radome_leads": g - sway_leads[rd]["need"] for rd in sway_leads}}
                            for k, g in gain.items()},
            "stroke": {"stroke_mm_closing_held": stroke_for(n_iso), "stroke_mm_closing_radome_leads": stroke_for(n_leads),
                       **{f"stroke_mm_closing_held_plus_sway_{rd}": stroke_for(v["need"]) for rd, v in sway_n.items()},
                       **{f"stroke_mm_closing_held_plus_sway_{rd}_radome_leads": stroke_for(v["need"]) for rd, v in sway_leads.items()},
                       "stroke_mm_with_L2_held": stroke_for(n_iso - gain[L2]),
                       "stroke_mm_with_fine_step_held_plus_sway_upper_whisker": stroke_for(sway_n["upper_whisker"]["need"] - gain[FINE]),
                       **{f"stroke_mm_with_L2_held_plus_sway_{rd}": stroke_for(v["need"] - gain[L2]) for rd, v in sway_n.items()},
                       "pin_body_um_per_mm_extra_free_length_at_far_edge": brass * 1e3,
                       "stroke_nominal_mm": stroke0, "window_half_width_of_stroke": half,
                       "pin_travel_tolerance_mm_not_in_52_chain": s52.POGO_TRAVEL_TOL},
            "run_length": {**{f"{k}_closing": v for k, v in run_route.items()}, "route": "gap" if gap_star is not None else "gap then shank",
                           "peek_run_mm_today": gap0 + (shank0 if sp == "32" else 0.0)},
            "run_cte": {"cte_ppm_K_closing": alpha_star * 1e6, "cte_ppm_K_free_peek": ALPHA_PEEK_1K * 1e6,
                        "cte_ppm_K_closing_grade_in_the_shank_composite_too": alpha_star_both * 1e6},
            "seam_hot_preload": {alloy: {"today": seam_today[alloy], "run_length": seam_len[alloy], "run_cte": seam_cte[alloy]}
                                 for alloy in ALLOY_PROPERTIES},
        }
        # the sway alone at the front's largest share against L1's smaller margin on each edge: where it exceeds it, no δ
        # route closes the held + sway need by itself — the held part cannot go below zero
        top = (d103[FRONT_OF[sp]] if sp == "18" else d103)["cte_share_front"]["share_of_102_shift"][-1]
        by_span[sp]["sway_alone_at_the_largest_share"] = {
            rd: {"share": top, "amp_um": sway_amp(sp, top, rd),
                 "over_l1_um": sway_amp(sp, top, rd) - min(min(m) for m in l1.values())} for rd in ("median", "upper_whisker")}
        if sp == "18":
            by_span[sp]["need_um_by_placeholder_shank"] = {f"{s:g}": worst(travel(sp, gap0 + shank0 - s, ALPHA_PEEK_1K), l1)
                                                           for s in (*SHANKS_HW89, shank0)}
            # the held reading's slope with the shank, carried onto the worst combined corner as an ESTIMATE (`103`'s front
            # itself moves with the shank): the shortest shank at which L2 with the finer step still closes it
            nb = by_span[sp]["need_um_by_placeholder_shank"]
            slope = (nb[f"{SHANKS_HW89[0]:g}"] - nb[f"{shank0:g}"]) / (shank0 - SHANKS_HW89[0])
            spare_worst = min(v for k, v in by_span[sp]["window_side"][L2FINE].items() if k.startswith("spare_um"))
            by_span[sp]["placeholder_shank_estimate"] = {"slope_um_per_mm_held": slope, "l2fine_worst_spare_um": spare_worst,
                                                         "shortest_shank_mm_closing_with_l2fine": shank0 - spare_worst / slope}
            by_span[sp]["run_cte"]["cte_ppm_K_free_gap_with_bonded_shank"] = (ALPHA_PEEK_1K + (alpha_s3 - alpha_fl) * shank0 / gap0) * 1e6
            by_span[sp]["seam_with_sway"] = {
                alloy: {name: {"today": seam_sway(alloy, sh, seam_today[alloy]["F_hot_N"], gap0),
                               "run_length": seam_sway(alloy, sh, seam_len[alloy]["F_hot_N"], run_route["gap_mm"]),
                               "run_cte": seam_sway(alloy, sh, seam_cte[alloy]["F_hot_N"], gap0),
                               "sway_alone": seam_sway(alloy, sh, 0.0, gap0), "share": sh}
                        for name, sh in corners.items()} for alloy in ("Ta", ALLOY_BASELINE)}

    # ── verdict, built from the numbers ──
    s18, s32 = by_span["18"], by_span["32"]
    ws18, ws32 = s18["window_side"], s32["window_side"]
    sw18, sw32 = s18["need_um_held_plus_sway"], s32["need_um_held_plus_sway"]
    ta18 = s18["seam_hot_preload"]["Ta"]
    st18 = s18["seam_with_sway"]["Ta"]
    f_same = max(by_span[sp]["seam_hot_preload"]["Ta"][r]["F_hot_N"] for sp, r in (("18", "run_length"), ("18", "run_cte"), ("32", "run_cte")))
    f_32len = by_span["32"]["seam_hot_preload"]["Ta"]["run_length"]["F_hot_N"]
    lines = [
        f"Need on the held reading (the pad's free-sleeve travel over `90`'s isothermal L1 margin, worst grip, temperature and "
        f"stack): {up1(s18['need_um_isothermal_worst']):.1f} µm on the 18 mm span (the Zone-3 fit, shank bonded — "
        f"{up1(s18['need_um_isothermal_worst_shank_as_ti']):.1f} with it as Ti) and {up1(s32['need_um_isothermal_worst']):.1f} "
        f"on the 32 mm span; where the radome leads, {up1(s18['need_um_radome_leads']):.1f} and "
        f"{up1(s32['need_um_radome_leads']):.1f}. On the held + sway reading (`103`'s front, the sway's increment bounded by "
        f"its shift — an upper end) {up1(sw18['median']['need']):.1f} ⊥ {up1(sw18['upper_whisker']['need']):.1f} µm on 18 mm at "
        f"`87`'s median ⊥ upper-whisker shift (the latter at a share of {sw18['upper_whisker']['share']:.2f}, CTE "
        f"{sw18['upper_whisker']['cte_ppm_K']:.1f}), {up1(s18['need_um_held_plus_sway_radome_leads']['median']['need']):.1f} ⊥ "
        f"{up1(s18['need_um_held_plus_sway_radome_leads']['upper_whisker']['need']):.1f} with the radome leading too; "
        f"{up1(sw32['median']['need']):.1f} ⊥ {up1(sw32['upper_whisker']['need']):.1f} on 32 mm. Left as is, the stroke leaves "
        f"the window on both sides on 18 mm — {up1(s18['window_breach_pct_of_stroke']['held']['over_upper_edge']):.1f} % of the "
        f"stroke past 70 % and {up1(s18['window_breach_pct_of_stroke']['held']['under_lower_edge']):.1f} % under 50 % held, "
        f"{up1(s18['window_breach_pct_of_stroke']['held_plus_sway_upper_whisker']['over_upper_edge']):.1f} ⊥ "
        f"{up1(s18['window_breach_pct_of_stroke']['held_plus_sway_upper_whisker']['under_lower_edge']):.1f} % with the "
        f"upper-whisker sway.",
        f"Window side (δ and the seam unchanged; the outer pad lifted too): the bayonet hard-stop (L2) adds {down1(gain[L2]):.1f} µm "
        f"to both margins — on 18 mm {spare(ws18[L2]['spare_um_held'])} held "
        f"({spare(ws18[L2]['spare_um_radome_leads'])} with the radome leading), {spare(ws18[L2]['spare_um_held_plus_sway_median'])} ⊥ "
        f"{spare(ws18[L2]['spare_um_held_plus_sway_upper_whisker'])} with the sway, "
        f"{spare(ws18[L2]['spare_um_held_plus_sway_upper_whisker_radome_leads'])} with both; on 32 mm {spare(ws32[L2]['spare_um_held'])} held. "
        f"L2 with a {STEP_FINE:g} mm spacer step adds {down1(gain[L2FINE]):.1f} — on 18 mm {spare(ws18[L2FINE]['spare_um_held'])} "
        f"held, {spare(ws18[L2FINE]['spare_um_held_plus_sway_upper_whisker'])} with the upper-whisker sway, "
        f"{spare(ws18[L2FINE]['spare_um_held_plus_sway_upper_whisker_radome_leads'])} with the radome leading too — every "
        f"reading closed on the 14 mm placeholder shank, the worst while the shank stays above about "
        f"{up1(s18['placeholder_shank_estimate']['shortest_shank_mm_closing_with_l2fine']):.1f} mm (the held reading's slope, "
        f"{up1(s18['placeholder_shank_estimate']['slope_um_per_mm_held']):.1f} µm per mm, an estimate); on 32 mm "
        f"{spare(ws32[L2FINE]['spare_um_held'])} held. A tolerance class holding the CNC member to ±0.05 mm adds what L2 does if "
        f"the member is machining tolerance; a {STEP_FINE:g} mm step alone adds {down1(gain[FINE]):.1f} and no step "
        f"{down1(gain[ZERO]):.1f}. A longer stroke, the deck re-spaced to keep 60 % nominal, closes the held need from "
        f"{up3(s18['stroke']['stroke_mm_closing_held']):.3f} mm on 18 mm ({up3(s18['stroke']['stroke_mm_closing_held_plus_sway_upper_whisker']):.3f} "
        f"with the upper-whisker sway) and {up3(s32['stroke']['stroke_mm_closing_held']):.3f} on 32 mm, against the {stroke0:g} mm nominal.",
        f"δ side (closes the held need only): on 18 mm a gap of {down1(s18['run_length']['gap_mm_closing']):.1f} mm (from "
        f"{s18['run_length']['peek_run_mm_today']:g} — the Zone-3 shank {up1(s18['run_length']['shank_mm_closing']):.1f} mm) or a "
        f"PEEK-run CTE of {down1(s18['run_cte']['cte_ppm_K_closing']):.1f} ppm/K (free PEEK {ALPHA_PEEK_1K * 1e6:g}; "
        f"{down1(s18['run_cte']['cte_ppm_K_closing_grade_in_the_shank_composite_too']):.1f} if the grade fills the shank's composite too); on "
        f"32 mm a PEEK run of {down1(s32['run_length']['peek_run_mm_closing']):.1f} mm (the shank cut to "
        f"{down1(s32['run_length']['shank_mm_closing']):.1f}) or {down1(s32['run_cte']['cte_ppm_K_closing']):.1f} ppm/K. Where the "
        f"wire–liner pair stays as it is — both CTE routes and the length route on 18 mm — the need fixes the shift per kelvin and "
        f"with it one hot preload, on Ta {up1(f_same):.1f} N; the length route on 32 mm cuts the shank and the liner run with it, "
        f"landing at {up1(f_32len):.1f} N — against {up1(ta18['today']['F_hot_N']):.1f} today on 18 mm. `86`'s requirement with no sway "
        f"{up3(ta18['today']['seam_k_no_sway']):.3f} → {up3(max(ta18['run_length']['seam_k_no_sway'], ta18['run_cte']['seam_k_no_sway'])):.3f}; "
        f"with `103`'s sway on top, at its least state-3 corner on a stiff bond at least {up3(st18['state3_least_stiff_bond']['today']['k']):.3f} → "
        f"{up3(max(st18['state3_least_stiff_bond']['run_length']['k'], st18['state3_least_stiff_bond']['run_cte']['k'])):.3f} (the sway "
        f"alone {up3(st18['state3_least_stiff_bond']['sway_alone']['k']):.3f}), and at its caps unchanged where the liner wall binds "
        f"({up3(st18['state3_cap_stiff_bond']['today']['k']):.3f}).",
        f"On held + sway the sway alone at `103`'s largest share ({s18['sway_alone_at_the_largest_share']['median']['share']:.2f}) "
        f"swings ±{up1(s18['sway_alone_at_the_largest_share']['median']['amp_um']):.1f} ⊥ "
        f"±{up1(s18['sway_alone_at_the_largest_share']['upper_whisker']['amp_um']):.1f} µm on 18 mm — "
        + ("past L1's smaller margin at both shift readings, so there no δ route closes the need by itself"
           if all(v["over_l1_um"] > 0 for v in s18["sway_alone_at_the_largest_share"].values()) else
           "past L1's smaller margin at the upper whisker only" if s18["sway_alone_at_the_largest_share"]["upper_whisker"]["over_l1_um"] > 0
           else "inside L1's smaller margin at both shift readings")
        + ". Sensitivity: the placeholder shank at `92`'s "
        f"{SHANKS_HW89[0]:g} ⊥ {SHANKS_HW89[1]:g} mm moves the held need on 18 mm to "
        f"{up1(s18['need_um_by_placeholder_shank'][f'{SHANKS_HW89[0]:g}']):.1f} ⊥ {up1(s18['need_um_by_placeholder_shank'][f'{SHANKS_HW89[1]:g}']):.1f} µm. "
        f"Not priced: the pin's own height — its datasheet's ±{s52.POGO_TRAVEL_TOL:.3f} mm on the travel, which, as far as it is "
        f"the plunger's free length, moves the compression at a fixed gap by as much, past every spare here — has no member in "
        f"`52`'s chain (HW.8.7).",
    ]

    def rnd(o):
        if isinstance(o, float):
            return round(o, 6)
        if isinstance(o, dict):
            return {k: rnd(v) for k, v in o.items()}
        return o

    result = {
        "script": Path(__file__).name,
        "question": "00_07 HW.43 — the prices of the remedies for the centre pad's thermal travel, before the verdict",
        "readings": {"held": "the seasonal edges against the window — the whole travel in state 1 (share 0, unless ice in "
                             "the gap ties the anode at the cold edge — not bounded)",
                     "held_plus_sway": "the sway rides on the seasonal position once the wood holds the anchor: the held "
                                       "part at 103's CTE plus the sway at 103's share, on 103's front (each kept CTE with "
                                       "the next kept share), the two maximised over the grips separately — an upper end",
                     "shank_18": "bonded over its run (lib.mechanics) — the adverse end (the need with it as Ti is smaller)",
                     "grips": "every part × relaxed or not × μ end of 102's window; both temperature readings; both "
                              "isothermal stacks; the radome-leads reading priced apart",
                     "alpha_shank_run_ppm_K": round(alpha_s3 * 1e6, 4)},
        "inputs": {"margins_um_90": {s: {"L1": win90[s]["window"]["L1 spacer only"]["margin_um"],
                                         "L2": win90[s]["window"]["L2 spacer + bayonet hard-stop"]["margin_um"]}
                                     for s in (*STACKS, LEADS)},
                   "residual_rule_52": {"L1_mm_90": res90["L1 spacer only"], "cnc_member_mm": cnc, "spacer_step_mm": s52.SPACER_STEP,
                                        "by_remedy_mm": residual},
                   "temperatures_c": temps, "assembly_c": t_ref, "gap_mm": gap0, "shank_mm": shank0, "flange_mm": flange,
                   "shift_um_87": d102["sway_input"]["shift_um_87"]},
        "window_side_gain_um": rnd(gain),
        "by_span": rnd(by_span),
        "controls": {"pad_travel_vs_102_max_miss_um": round(miss_a, 5), "seam_vs_102_103_max_miss": round(miss_b, 6),
                     "seam_sway_corners_vs_103_max_miss": round(miss_b2, 5), "residuals_and_l2_step_vs_90_max_miss_um": round(miss_c, 4),
                     "reading": "(a) a drifted input, grip rule, span or temperature; (b) a wrong preload corner or alloy "
                                "row; (b2) a wrong sway corner or share; (c) a residual read off the wrong member; (e) the "
                                "closing geometry off 55's relations; (f) 103's CTE convention off this script's — none sees "
                                "an error 102 or 103 shares"},
        "verdict": " ".join(lines),
    }
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("\n  " + "\n  ".join(lines))
    print(f"\n  controls: pad vs 102 ≤ {miss_a:.4f} µm · seam vs 102/103 ≤ {miss_b:.5f} · sway corners ≤ {miss_b2:.5f} · "
          f"residuals/L2 step vs 90 ≤ {miss_c:.3f} µm")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
