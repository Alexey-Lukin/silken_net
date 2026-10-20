#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""103 — how much of the stem's radial shift the wood imposes on the anchor, per bond state, and which unmeasured
quantity decides it (00_07 HW.43, the leg «частка зсуву, яку деревина накладає на анкер, за станом звʼязку анода — для
гойдання (C) і для тепла»; no solve).

WHY. `102` (2026-10-20) gives the bus wire's root load and the centre pad's travel as a function of the share of `87`'s
sway shift the wood imposes on the anchor, and prices the heat on the PEEK sleeve's FREE growth (a share of 0 for the
heat). Two of its conclusions wait on that share: where the seam requirement lies between its gentle and adverse
corners (HW.34), and whether the centre pad's seasonal travel past `90`'s L1 margin survives the wood holding the span.

CHAIN (in-silico §Critical Rules #15; 01_04 §2, §3.1, §3.3; spans from `55`/`77`/`78`). The wood reaches the anchor at
three places, and canon says what holds each: the ANODE — a Ø11 gyroid in the Ø15 narrow-step channel (01_04 §3.3),
free until the callus fills it and bonded after (01_04 §2, phases 2–4); the SLEEVE — snug in the same Ø15 channel, its
grip there not in the tree, and in the mature state wrapped by a callus ring below the bark (01_04 §2, phase 4; §3.1,
step 4); the FLANGE — seated on faced dead bark (01_04 §3.1, step 3), a bearing whose stiffness and preload are not in
the tree: the bark rises against the flange as the stem grows (01_04 §3.1, «кора, що підіймається»), and dead bark
swells and shrinks with humidity (Oberhuber et al. 2020). The anchor between the anode's face and the flange's seat is
the PEEK sleeve (`102`'s 32 mm span). The thermal mismatch PEEK ⊥ Ti is the anchor's own and exists in every state.

STATES. (1) Anode not bonded: the anode end is free, so the wood imposes nothing through the flange — except where a
grip of the sleeve in its channel, or ice in the sap-filled 2 mm gap at the cold edge, ties it (neither is bounded).
(2) Anode bonded, the sleeve free below the bark: the anode bond, the sleeve and the bark bearing in series.
(3) Anode bonded and the sleeve tied RIGIDLY to the wood by the callus ring, the bark bearing acting too — canon's mature
state (the ring and the bark that rises against the flange at once). Canon grows the ring over Zone 2's OUTER edge
(01_04 §3.1 step 4, «Переваги»), and callus grows from the cambium outward while the stem's growth carries new wood
along the sleeve toward the flange — so the tie's depth below the flange seat is an AXIS, from the flange to the
install-day cambium (bark + phloem, `78`), the deepest it can sit.
One solver carries all three: the sleeve as two elastic segments (flange → cambium → anode face) on three nodes, the
bearing k_F at the flange, a tie k_T at the cambium (0 in state 2, rigid in state 3) and the anode bond k_A at the
anode, against the wood's displacement — for the sway `87`'s shift, linear in depth from the flange (0) to the anode's
centroid (the full shift), for the heat the xylem's free growth to the bond's depth against the sleeve's and the anode
metal's between its face and that depth. The share is the sleeve's stretch over the shift at the bond's depth, scaled
to `102`'s shift (taken at `87`'s full depth) before it enters the seam; controls hold the solver to the closed forms of
state 2 (k_A, k_sleeve, k_F in series) and of the bearing-released state 3, and check that a partial tie lies between
states 2 and 3 (monotone in k_T) and that the share and the CTE move monotonically with the tie's depth.

THE AXES. In state 2 the bark enters only as the bearing's stiffness k_F (N/mm) — what a flange mock pressed on faced
bark measures (force over settlement); the bark's radial modulus enters as k_F = E·A/t. No green modulus was found, and
the air-dry readings bound it in neither direction (green bark is softer than air-dry; the one pine reading was read
off a load cell's travel, which the same paper's own wood cube suggests understates it by under 2× on these thin
blocks — our estimate). Each state-2 conclusion is printed as the k_F at which it is reached at BOTH ends of the
anode-bond bracket (0 = at any k_F, None = at none): below the stiff-bond value it does not happen whatever the bond,
above the soft-bond value it happens whatever the bond. In state 3 the tie's depth decides: with no bearing at all, the
depth shallower than which each conclusion is reached at a rigid tie (a bearing only lowers the CTE and raises the
share further, so it is reached at any bearing there), and Ta's least seam requirement over every depth and bearing.
The conclusions: the share reaches `102`'s seam rows; Ta's seam passes k 1 on the adverse reversed corner, on the sway
alone and with `102`'s seasonal hot preload (the PEEK ⊥ Ti mismatch is the anchor's own and acts in every state); the
centre pad's hot and cold conclusions flip, with the bearing in contact (the bark's rise makes it the service state)
and the flange located by the bark (a Zone-3 fit, `00_07` HW.8.9, is not computed here). The seam at each share is
`102`'s own closed form (its `Pair` and `soderberg_k`) on `102`'s cached inputs, held to `102`'s grid by a control.

Stiffnesses: k_sleeve = E_PEEK·A/L over the 32 mm span (unrelaxed for the sway, × PEEK_RELAX_FLOOR for the slow heat),
each segment by its length; k_A = 2π·G_eff·L_anode / ln(R/r), our order-of-magnitude shear-lag form for a cylinder
pulled along the stem's radius, with G_eff = √(G_LR·G_RT) — the radius-normal shear acts in both planes at once
(anti-plane shear in an orthotropic medium) — and ln(R/r) carried as a bracket.

CAN: give per state the share of the sway shift, its cap at a rigid bark, the seam requirement it implies on `102`'s
closed form, the bearing stiffness at which each state-2 conclusion is reached at either end of the bond bracket, and
the tie's depth at which each state-3 conclusion is reached with no bearing.
CANNOT: (1) give the bark bearing's green stiffness or its growth preload, the sleeve's grip in the Ø15 channel, or the
callus ring's stiffness and depth — all unmeasured, so the bearing and the tie's depth are axes and the tie is taken at
its rigid end (a channel grip is a deeper tie of the same kind, not computed); (2) give
green constants of P. sylvestris (the bark moduli are air-dry, one read off a load cell's travel; G is a green-radiata ⊥
moist-Scots-pine bracket); (3) the dead bark's thermal and humidity strain over its thickness — the span's wood side is
taken at xylem's CTE; (4) the frost response as a coefficient or even its sign at the tie: green wood specimens frost-
shrink (Kübler 1983 on white oak; Schirp & Kübler 1968 measured Scots pine, not read), living pine-sapling xylem shrank
(Lindfors 2015), heat-killed xylem swelled — and a tie sits in the wound's reaction zone; (5) ice in the anode's gap or
at the sleeve's interface at the cold edge (a tie of unknown strength, `102` CANNOT 3); (6) the wood's strain field near
the anchor — the imposed shift is `87`'s, linear in depth; (7) mixed relaxation: for the slow heat the PEEK is relaxed
and the wood is not, which overstates how far a tied segment follows the wood.

Run:  conda activate silken_md
      python tools/in_silico/scripts/103_anchor_wood_share.py
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
from lib.utils import banner

SI_DESCRIPTION = ("The share of a living stem's radial shift that the wood imposes on the anchor, per bond state of the "
                  "anode and the sleeve, from the stiffness of the bark bearing, the anode's bond in the xylem, a tie "
                  "of the sleeve at the cambium and the PEEK sleeve, with the bark-bearing stiffness at which the share "
                  "reaches each seam requirement and each contact-pad conclusion flips, at both ends of the anode-bond "
                  "bracket; no solve")

MECH = CACHE_DIR / "mechanical"
THERM = CACHE_DIR / "thermal"
OUT = MECH / "anchor_wood_share.json"

# ── literature constants, each read in the primary on 2026-10-20 (a bracket of named readings) ──
E_BARK_RADIAL_MPA = {
    # Bold, Langer, Börnert, Speck 2020, Int. J. Mol. Sci. 21(9):3355, doi 10.3390/ijms21093355, §2.3.1 — giant sequoia,
    # whole bark, air-dry (~60 % RH), loaded through its thickness: «between 0.87 and 1.11 MPa» (secant) — the low end
    "sequoia_whole_bark_air_dry": 0.87,
    # Eberhardt 2007, Forest Prod. J. 57(4):95–97, Table 1, row Bark / No solvent / Radial — Pinus taeda outer bark,
    # air-dry 10.8 % MC; deformation read off the load cell's travel (the paper's own radial wood cube reads low on the
    # same set-up); green bark is softer than air-dry — so this bounds the green modulus in neither direction
    "p_taeda_outer_bark_air_dry": 18.0,
}
# G_eff = √(G_LR·G_RT), the radius-normal (anti-plane) shear modulus, from pairs measured on one specimen group:
G_PAIRS_MPA = {
    # Davies, Altaner, Apiolaza 2016, N.Z. J. For. Sci. 46:19, doi 10.1186/s40490-016-0075-x, Table 2 — GREEN P. radiata,
    # LR and RT per group (GPa, one significant figure): stiff outerwood 0.06/0.05, non-stiff outerwood 0.03/0.02 (the
    # lowest product — taken), stiff corewood 0.04/0.02, non-stiff corewood 0.03/0.04
    "green_p_radiata_lowest_group": (30.0, 20.0),
    # Güntekin & Akar 2019, Drewno 62(204):41–53, doi 10.12841/wood.1644-3985.220.09, Table 4 — P. sylvestris sapwood at
    # 22.8 % MC (the moistest measured, below fibre saturation — an UPPER end for green wood): G_LR 737, G_RT 74
    "scots_pine_22_8pct_mc": (737.0, 74.0),
}
G_EFF_MPA = {k: math.sqrt(lr * rt) for k, (lr, rt) in G_PAIRS_MPA.items()}
LN_R_OVER_R = (2.3, 3.5)   # the log term of the cylinder's shear lag — our bracket (R ≈ 10 r … the stem's radius scale)
# Sevanto, Hölttä, Hirsikko, Vesala, Nikinmaa 2005, Boreal Env. Res. 10:437–445, Table 1, column Pinus sylvestris, Mean —
# fresh water-saturated xylem, 5–45 °C, radial (diameter) direction, bark excluded, no hysteresis
ALPHA_XYLEM_GREEN_1K = 7.9e-6
SHARE_ROWS = (0.25, 0.5)   # `102`'s seam rows the bearing thresholds are taken at
TIE_RIGID = 1e12           # N/mm — the rigid tie of state 3
KF_LO, KF_HI = 1e-3, 1e8   # N/mm — the bearing axis a threshold is sought on
DEPTH_MIN = 0.5            # mm — the shallowest tie below the flange seat the depth axis starts at


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


s55 = _load("bus55", "55_bus_mechanical.py")
s102 = _load("liner102", "102_wire_liner_shear_lag.py")   # its Pair and soderberg_k — the seam on its own closed form


def series(*k: float) -> float:
    return 1.0 / sum(1.0 / x for x in k)


def tridiag3(b0, c0, a1, b1, c1, a2, b2, f):
    """x of the symmetric 3-node chain [[b0, c0, 0], [a1, b1, c1], [0, a2, b2]]·x = f (Thomas)."""
    c0p = c0 / b0
    f0p = f[0] / b0
    m1 = b1 - a1 * c0p
    c1p = c1 / m1
    f1p = (f[1] - a1 * f0p) / m1
    x2 = (f[2] - a2 * f1p) / (b2 - a2 * c1p)
    x1 = f1p - c1p * x2
    return f0p - c0p * x1, x1, x2


def threshold(fn) -> float | None:
    """The bearing stiffness at which an increasing fn crosses 0: 0.0 if it is already ≥ 0 at no bearing, None if it
    never reaches 0 at a rigid one."""
    if fn(KF_LO) >= 0:
        return 0.0
    return bisect_log(fn, KF_LO, KF_HI)


def bisect_log(fn, lo: float, hi: float, n: int = 120) -> float | None:
    """The root of a monotone fn on [lo, hi] on a log axis, or None if it does not change sign there."""
    flo, fhi = fn(lo), fn(hi)
    if (flo > 0) == (fhi > 0):
        return None
    for _ in range(n):
        mid = math.sqrt(lo * hi)
        if (fn(mid) > 0) == (flo > 0):
            lo, flo = mid, fn(mid)
        else:
            hi = mid
    return math.sqrt(lo * hi)


def main() -> int:
    banner("103 — the share of the stem's shift the wood imposes on the anchor, per bond state")
    g77 = json.loads((MECH / "anchor_torque_path.json").read_text(encoding="utf-8"))["geometry"]
    bark78 = json.loads((THERM / "flange_cambium_heat.json").read_text(encoding="utf-8"))
    d87 = json.loads((MECH / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    d102 = json.loads((MECH / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    d86 = json.loads((MECH / "coaxiality_allocation.json").read_text(encoding="utf-8"))

    r_sleeve = g77["sleeve_outer_radius_m"] * 1e3
    r_bore = g77["shank_radius_m"] * 1e3
    r_anode = g77["gyroid_radius_m"] * 1e3
    l_anode = g77["gyroid_length_m"] * 1e3
    span = s55.PEEK_GAP_MM + s55.SHANK_LEN_MM          # the anode's face to the flange's seat — `102`'s 32 mm span
    a_sleeve = math.pi * (r_sleeve ** 2 - r_bore ** 2)
    e_peek = E_PEEK_PA / 1e6
    k_sleeve = {"sway": e_peek * a_sleeve / span, "slow": e_peek * PEEK_RELAX_FLOOR * a_sleeve / span}
    d_flange = bark78["bark"]["flange_diameter_mm"]
    a_annulus = math.pi / 4.0 * (d_flange ** 2 - (2 * r_sleeve) ** 2)
    bark_t = {"thin_contact_78": bark78["bark"]["thin_mm"], "thick_side_78": bark78["bark"]["thick_mm"]}
    phloem = bark78["inputs"]["phloem_mm"]
    gap_radial = r_sleeve - r_anode
    dx_mm = {k: v * 1e3 for k, v in d87["inputs"]["depth_span_m"].items()}

    k_a = {f"{g}__ln{ln:g}": 2 * math.pi * gv * l_anode / ln for g, gv in G_EFF_MPA.items() for ln in LN_R_OVER_R}
    k_a_lo, k_a_hi = min(k_a.values()), max(k_a.values())
    bonds = (("anode_bond_stiff", k_a_hi), ("anode_bond_soft", k_a_lo))
    tie_mm = {t: tv + phloem for t, tv in bark_t.items()}                       # flange seat → install-day cambium
    dv_ceil = max(dx_mm.values())                                               # `87`'s full depth — `102`'s shift
    alpha_anode = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]

    def stretch(k_f: float, k_t: float, ka: float, d_t: float, load: str, w_t: float, w_a: float,
                e_up: float = 0.0, e_lo: float = 0.0) -> float:
        """The sleeve's stretch (anode node − flange node) on the 3-node chain; the wood is at 0 under the flange."""
        k_up, k_lo = k_sleeve[load] * span / d_t, k_sleeve[load] * span / (span - d_t)
        x0, _, x2 = tridiag3(k_f + k_up, -k_up, -k_up, k_up + k_lo + k_t, -k_lo, -k_lo, k_lo + ka,
                             (-k_up * e_up, k_t * w_t + k_up * e_up - k_lo * e_lo, ka * w_a + k_lo * e_lo))
        return x2 - x0

    def share(k_f: float, k_t: float, ka: float, d_t: float, dv: float) -> float:
        """The sleeve's stretch over the shift at the bond's depth dv."""
        return stretch(k_f, k_t, ka, d_t, "sway", d_t / dv, 1.0)

    def w_anode_heat(dv: float) -> float:
        """Per kelvin: the wood's growth to the bond's depth less the anode metal's between its face and that depth."""
        return ALPHA_XYLEM_GREEN_1K * dv - alpha_anode * (dv - span)

    def a_eff(k_f: float, k_t: float, ka: float, d_t: float, dv: float) -> float:
        """The span's effective CTE, ppm/K, on the relaxed PEEK."""
        return stretch(k_f, k_t, ka, d_t, "slow", ALPHA_XYLEM_GREEN_1K * d_t, w_anode_heat(dv),
                       ALPHA_PEEK_1K * d_t, ALPHA_PEEK_1K * (span - d_t)) / span * 1e6

    # controls: the solver against the closed forms of state 2 and of the bearing-released state 3
    miss = 0.0
    for ka in (k_a_lo, k_a_hi):
        for dv in dx_mm.values():
            for k_f in (1.0, 300.0, 1e5):
                kc = series(ka, k_f)
                e_tot = ALPHA_PEEK_1K * span
                miss = max(miss, abs(share(k_f, 0.0, ka, 5.0, dv) - kc / (kc + k_sleeve["sway"])),
                           abs(a_eff(k_f, 0.0, ka, 5.0, dv) - (e_tot + (w_anode_heat(dv) - e_tot) * kc / (kc + k_sleeve["slow"]))
                               / span * 1e6))
            for d_t in tie_mm.values():
                x_t = span - d_t
                seg, seg_slow = (ka / (ka + k_sleeve[ld] * span / x_t) for ld in ("sway", "slow"))
                e_lo = ALPHA_PEEK_1K * x_t
                miss = max(miss, abs(share(0.0, TIE_RIGID, ka, d_t, dv) - seg * (dv - d_t) / dv),
                           abs(a_eff(0.0, TIE_RIGID, ka, d_t, dv) - (ALPHA_PEEK_1K * d_t + e_lo + (w_anode_heat(dv) - ALPHA_XYLEM_GREEN_1K
                                                                                                   * d_t - e_lo) * seg_slow) / span * 1e6))
    if miss > 1e-6:
        raise RuntimeError(f"control: the 3-node solver misses the closed forms by {miss}")

    # control: monotone where the readings need it — rising with the bearing and the bond (a threshold in k_F, and the two
    # bond ends bracket every bond), monotone in the tie either way (k_T enters one diagonal cell, so the solution is a
    # ratio of two linear functions of it: a partial tie lies between states 2 and 3), and with no bearing the share
    # falling and the CTE rising as the rigid tie sits deeper (a depth threshold)
    grid_t = [0.0] + [10 ** (i / 2) for i in range(-4, 25)] + [TIE_RIGID]
    grid_f = [0.0] + [10 ** (i / 2) for i in range(-6, 17)]
    grid_a = [k_a_lo * (k_a_hi / k_a_lo) ** (i / 8) for i in range(9)]
    grid_d = [DEPTH_MIN + (max(tie_mm.values()) - DEPTH_MIN) * i / 40 for i in range(41)]

    def worst_rise(seq: list) -> float:
        return max(seq[i] - seq[i + 1] for i in range(len(seq) - 1))

    mono = {"in_bearing": 0.0, "in_bond": 0.0, "in_tie": 0.0, "in_tie_depth": 0.0}
    for dv in dx_mm.values():
        for d_t in tie_mm.values():
            for kt in (0.0, 1e2, 1e4, TIE_RIGID):
                for ka in grid_a:
                    mono["in_bearing"] = max(mono["in_bearing"], worst_rise([share(kf, kt, ka, d_t, dv) for kf in grid_f]),
                                             worst_rise([-a_eff(kf, kt, ka, d_t, dv) for kf in grid_f]))
                for kf in (0.0, 1e2, 1e4, 1e8):
                    mono["in_bond"] = max(mono["in_bond"], worst_rise([share(kf, kt, ka, d_t, dv) for ka in grid_a]),
                                          worst_rise([-a_eff(kf, kt, ka, d_t, dv) for ka in grid_a]))
            for ka in grid_a:
                for kf in (0.0, 1e2, 1e4, 1e8):
                    for seq in ([share(kf, kt, ka, d_t, dv) for kt in grid_t], [a_eff(kf, kt, ka, d_t, dv) for kt in grid_t]):
                        mono["in_tie"] = max(mono["in_tie"], min(worst_rise(seq), worst_rise([-x for x in seq])))
        for ka in grid_a:
            mono["in_tie_depth"] = max(mono["in_tie_depth"], worst_rise([-share(0.0, TIE_RIGID, ka, d, dv) for d in grid_d]),
                                       worst_rise([a_eff(0.0, TIE_RIGID, ka, d, dv) for d in grid_d]))
            # at a rigid bark the CTE runs the other way with depth (falling) — monotone, so the CTE's floor over the
            # model sits at an end of every axis (the bearing's two ends bracket it, monotone in the bearing above)
            seq = [a_eff(TIE_RIGID, TIE_RIGID, ka, d, dv) for d in grid_d]
            mono["in_tie_depth"] = max(mono["in_tie_depth"], min(worst_rise(seq), worst_rise([-x for x in seq])))
    if max(mono.values()) > 1e-8:
        raise RuntimeError(f"control: not monotone where the readings need it: {mono}")

    # ── the seam on `102`'s own closed form ──
    geo = d102["geometry"]
    shipped = d86["by_geometry"][next(k for k in d86["by_geometry"] if k.startswith("shipped"))]
    amp86, off86 = d102["seam_86_inputs"]["amplitude_MPa"], d102["seam_86_inputs"]["offset_um"]
    shift_hi = max(d102["sway_input"]["shift_um_87"]["upper_whisker"]) * 1e-3
    shift_lo = min(d102["sway_input"]["shift_um_87"]["median"]) * 1e-3
    ceiling_grips = d102["grip"]["by_part_N_per_mm_at_20C"]["window_ceiling"]
    q_adv = ceiling_grips[max(ceiling_grips, key=float)]                 # the tightest part at `102`'s largest μ

    def seam_k(alloy: str, sh: float, corner: str) -> float | None:
        """`102`'s seam at a share of `102`'s shift, on `102`'s own Pair, inputs and preload (its cached relaxed-liner hot
        preload force), clipped at the wall as `102` clips it."""
        row86 = shipped["by_alloy"][alloy]
        mean86 = next(o["mean_MPa"] for o in row86["by_offset"] if o["offset_um"] == off86)
        ea_w = ALLOY_PROPERTIES[alloy]["E_GPa"] * 1e3 * geo["wire_area_mm2"]
        if corner == "gentle":
            pr = s102.Pair(d102["seam_by_alloy"][alloy]["gentle_grip_N_per_mm"], ea_w, geo["liner_EA_N"],
                           geo["bare_run_mm"], geo["liner_run_mm"], geo["wall_cap_N_23C"])
            c = pr.cycle(sh * shift_lo / 2.0, sh * shift_lo / 2.0)
            f_amp, f_mean = c["F_amp"], c["F_mean"]
        else:
            pr = s102.Pair(q_adv, ea_w, geo["liner_EA_N"], geo["bare_run_mm"], geo["liner_run_mm"], geo["wall_cap_N_23C"])
            c = pr.cycle(sh * shift_hi, 0.0) if corner.startswith("adverse_reversed") else pr.cycle(sh * shift_hi / 2.0, sh * shift_hi / 2.0)
            f_amp, f_mean = c["F_amp"], c["F_mean"]
            if corner.endswith("_hot_preload"):
                f_mean += d102["seam_by_alloy"][alloy]["hot_preload"]["F_N_relaxed_liner"]
                if f_amp + f_mean > pr.cap + 1e-9:
                    f_mean = pr.cap - f_amp
        return s102.soderberg_k(amp86, mean86, f_amp, f_mean, geo["wire_area_mm2"], row86)

    # control: this function at `102`'s grid shares must give back `102`'s cached seam requirements
    grid_corner = {"sway_reversed": "adverse_reversed", "sway_one_sided": "adverse_one_sided",
                   "sway_reversed_hot_preload": "adverse_reversed_hot_preload",
                   "sway_one_sided_hot_preload": "adverse_one_sided_hot_preload"}
    ctrl_miss = 0.0
    for alloy, row in d102["seam_by_alloy"].items():
        for sh, g in row["by_share"].items():
            for c102, c103 in grid_corner.items():
                ctrl_miss = max(ctrl_miss, abs(seam_k(alloy, float(sh), c103) - g["adverse"][c102]["seam_k"]))
            ctrl_miss = max(ctrl_miss, abs(seam_k(alloy, float(sh), "gentle") - g["gentle_one_sided"]["seam_k"]))
    if ctrl_miss > 2e-4:
        raise RuntimeError(f"control: the seam function misses `102`'s cached grid by {ctrl_miss}")

    # ── the events, each increasing in what reaches it ──
    flips = d102["thermal"]["flip_vs_larger_margin_ppm_K"]
    cold_thr, hot_thr = flips["cold_flange_on_bark"], flips["hot_floor_part_flange_on_bark"]

    def event(name: str, k_f: float, k_t: float, ka: float, d_t: float, dv: float) -> float:
        if name.startswith("share_"):                                      # `102`'s rows are shares of its shift
            return share(k_f, k_t, ka, d_t, dv) * dv / dv_ceil - float(name.split("_")[1])
        if name.startswith("ta_k1_"):
            corner = "adverse_reversed_hot_preload" if name.endswith("hot_preload") else "adverse_reversed"
            return seam_k("Ta", share(k_f, k_t, ka, d_t, dv) * dv / dv_ceil, corner) - 1.0
        return float(name.split("_")[2]) - a_eff(k_f, k_t, ka, d_t, dv)
    names = ([f"share_{row:g}" for row in SHARE_ROWS] + ["ta_k1_sway_alone", "ta_k1_hot_preload"]
             + [f"hot_flip_{x:g}" for x in hot_thr] + [f"cold_flip_{x:g}" for x in cold_thr])

    def r6(v):
        return None if v is None else round(v, 6)
    # state 2: the bearing at which each is reached, per bond end and `87` depth reading (the tie's depth is moot there)
    thr2 = {n: {f"{dk}__{b}": r6(threshold(lambda kf, n=n, ka=ka, dv=dv: event(n, kf, 0.0, ka, 5.0, dv)))
                for dk, dv in dx_mm.items() for b, ka in bonds} for n in names}
    # state 3: with no bearing, the rigid tie's depth shallower than which each is reached (0 = not even at the flange,
    # «deepest» = already at the install-day cambium of the deeper bark reading)
    d_deep = max(tie_mm.values())

    def depth_threshold(fn) -> float | str | None:
        if fn(d_deep) >= 0:
            return "deepest"
        if fn(DEPTH_MIN) < 0:
            return None
        lo, hi = DEPTH_MIN, d_deep
        for _ in range(80):
            mid = 0.5 * (lo + hi)
            if fn(mid) >= 0:
                lo = mid
            else:
                hi = mid
        return round(0.5 * (lo + hi), 4)
    dep3 = {n: {f"{dk}__{b}": depth_threshold(lambda d, n=n, ka=ka, dv=dv: event(n, 0.0, TIE_RIGID, ka, d, dv))
                for dk, dv in dx_mm.items() for b, ka in bonds} for n in names}

    # ── the shares and the seam values the prose quotes ──
    kf_read = {f"{e}__{t}": ev * a_annulus / tv for e, ev in E_BARK_RADIAL_MPA.items() for t, tv in bark_t.items()}
    s2_read = [share(kf, 0.0, ka, 5.0, dv_ceil) for kf in kf_read.values() for ka in k_a.values()]
    cap2 = {b: share(KF_HI, 0.0, ka, 5.0, dv_ceil) for b, ka in bonds}
    depths = {t: [DEPTH_MIN + (d - DEPTH_MIN) * i / 40 for i in range(41)] for t, d in tie_mm.items()}
    s3_free = {b: [share(0.0, TIE_RIGID, ka, d, dv) * dv / dv_ceil for ds in depths.values() for d in ds for dv in dx_mm.values()]
               for b, ka in bonds}
    cap3 = {b: max(share(KF_HI, TIE_RIGID, ka, d, dv) * dv / dv_ceil for ds in depths.values() for d in ds for dv in dx_mm.values())
            for b, ka in bonds}
    # the lowest CTE the model reaches — over the corners of the stiffness box (each stiffness enters one diagonal cell, so
    # the CTE is a ratio of linear functions in each and its minimum at every depth sits at a corner) and the depth axis,
    # whose ends carry it at a rigid tie (monotone in depth at both bearing ends, controls above) — against the CTE at which the pad's travel per kelvin changes sign on `102`'s own span (α·PEEK + α_Ti·disc −
    # α_Ti·wire = 0, its `pad_at`): above it, holding the span only shortens the thermal travel, so the free sleeve is the
    # travel's adverse end; and the floor of any coupling at all — the span following the wood outright — which bounds a
    # reversed travel beyond the model's brackets
    wire_run = s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM + s55.LINER_LENGTH_MM
    cte_reverse = alpha_anode * (wire_run - s55.FLANGE_THK_MM) / span * 1e6
    cte_grid = [(a_eff(kf, kt, ka, d, dv), kf, kt, ka, d, dv) for kf in (0.0, TIE_RIGID) for kt in (0.0, TIE_RIGID)
                for ka in (k_a_lo, k_a_hi) for d in grid_d for dv in dx_mm.values()]
    cte_min = min(cte_grid)
    cte_floor_coupled = min(w_anode_heat(dv) for dv in dx_mm.values()) / span * 1e6
    # control: the pad's travel on `102`'s Pair never falls as the shift grows — every cached grip (and a decade either
    # side, since `102` takes the grip by temperature; a part that grips with nothing passes the shift whole, pad = δ), the liner at its unrelaxed and relaxed modulus; with the shift per
    # kelvin linear in the CTE and zero at the sign change, the travel is then monotone in the CTE on each side of it
    ea_w_base = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3 * geo["wire_area_mm2"]
    grips = [q * f for part in d102["grip"]["by_part_N_per_mm_at_20C"].values() for q in part.values() for f in (0.1, 1.0, 10.0)]
    shifts = [i * 2e-3 for i in range(151)]                                      # 0 … 0.3 mm
    pad_worst = 0.0
    for q in grips:
        for ea_l in (geo["liner_EA_N"], geo["liner_EA_N"] * PEEK_RELAX_FLOOR):
            pr = s102.Pair(q, ea_w_base, ea_l, geo["bare_run_mm"], geo["liner_run_mm"], geo["wall_cap_N_23C"])
            pad_worst = max(pad_worst, worst_rise([abs(pr.virgin(x)[1]) for x in shifts]))
    if pad_worst > 1e-12:
        raise RuntimeError(f"control: the pad's travel falls as the shift grows (worst step {pad_worst})")
    reversed_fraction = (cte_reverse - cte_floor_coupled) / (ALPHA_PEEK_1K * 1e6 - cte_reverse)
    # a channel grip is a deeper tie of the same kind: the depth below the flange seat past which a rigid tie, at a rigid
    # bark and the stiff bond, takes the CTE to the travel's sign change
    lo, hi = d_deep, span - 1e-3
    for _ in range(80):
        mid = 0.5 * (lo + hi)
        if a_eff(TIE_RIGID, TIE_RIGID, k_a_hi, mid, dv_ceil) > cte_reverse:
            lo = mid
        else:
            hi = mid
    grip_reverse_depth = 0.5 * (lo + hi) if a_eff(TIE_RIGID, TIE_RIGID, k_a_hi, span - 1e-3, dv_ceil) < cte_reverse else None
    corners = ("adverse_reversed", "adverse_reversed_hot_preload", "adverse_one_sided", "gentle")
    seam = {}
    for alloy in ("Ta", ALLOY_BASELINE):
        # the least state-3 requirement: the deepest tie (the thick bark's install-day cambium), no bearing, the nominal depth
        least3 = {b: {c: round(min(seam_k(alloy, share(0.0, TIE_RIGID, ka, d_deep, dv) * dv / dv_ceil, c) for dv in dx_mm.values()), 4)
                      for c in ("adverse_reversed", "adverse_reversed_hot_preload")} for b, ka in bonds}
        seam[alloy] = {"state1": {"sway": d102["seam_by_alloy"][alloy]["seam_k_86"],
                                  "hot_preload": round(seam_k(alloy, 0.0, "adverse_reversed_hot_preload"), 4)},
                       "state2_at_air_dry_readings_max": {c: round(seam_k(alloy, max(s2_read), c), 4) for c in corners},
                       "state3_least_any_depth_and_bearing": least3,
                       "at_share_1": {c: round(seam_k(alloy, 1.0, c), 4) for c in corners}}

    def down2(x: float) -> float:
        return math.floor(round(x * 100, 9)) / 100

    def up2(x: float) -> float:
        return math.ceil(round(x * 100, 9)) / 100

    def down0(x: float) -> float:
        return math.floor(x)

    def by_bond(vals: dict, bond: str) -> list:
        return [v for k, v in vals.items() if k.endswith(bond)]

    def group(thr: dict, name: str) -> dict:
        return {f"{x}__{k}": v for x, vals in thr.items() if x == name or x.startswith(name + "_flip_") for k, v in vals.items()}
    labels = {"share_0.25": "the share reaches `102`'s 0.25 row", "ta_k1_sway_alone": "Ta's seam passes k 1 on the sway alone",
              "ta_k1_hot_preload": "Ta's seam passes k 1 with the hot preload", "hot": "the centre pad's hot conclusion flips",
              "cold": "the centre pad's cold conclusion flips"}
    # state 2: «no» below the lowest stiff-bond bearing, «yes» above the highest soft-bond one, over every reading
    table2 = {}
    for n in labels:
        st, so = by_bond(group(thr2, n), "anode_bond_stiff"), by_bond(group(thr2, n), "anode_bond_soft")
        table2[n] = {"no_below": None if None in st else min(st), "yes_above": None if None in so else max(so)}
    # state 3: with no bearing, «holds» only while the tie sits deeper than the largest stiff-bond depth over every reading
    table3 = {}
    for n in labels:
        dep = by_bond(group(dep3, n), "anode_bond_stiff")
        table3[n] = {"reached_at_any_depth": "deepest" in dep,
                     "holds_only_deeper_than_mm": None if "deepest" in dep or all(v is None for v in dep)
                     else max(v for v in dep if v is not None)}

    def c2(n: str) -> str:
        no, yes = table2[n]["no_below"], table2[n]["yes_above"]
        a = "at any bearing" if no == 0.0 else ("at no bearing" if no is None else f"not below {math.floor(no)} N/mm")
        b = "" if yes is None else f", whatever the bond above {math.ceil(yes)} N/mm"
        return f"{labels[n]} {a} (stiff bond){b}"
    ta = seam["Ta"]
    l3 = ta["state3_least_any_depth_and_bearing"]
    cold_d, hot_d = table3["cold"]["holds_only_deeper_than_mm"], table3["hot"]["holds_only_deeper_than_mm"]
    verdict = (
        f"State 1 (the anode not bonded — a Ø{2 * r_anode:g} gyroid with {gap_radial:g} mm of radial clearance in the "
        f"Ø{2 * r_sleeve:g} channel): share 0, unless the channel grips the sleeve or ice fills the gap (neither bounded). "
        f"State 2 (anode bonded, the sleeve free below the bark): the anode bond caps the share at "
        f"{up2(cap2['anode_bond_stiff']):.2f} (stiff bond) ⊥ {up2(cap2['anode_bond_soft']):.2f} (soft); at the air-dry bark "
        f"readings (a bearing of {math.floor(min(kf_read.values()))}–{math.ceil(max(kf_read.values()))} N/mm, which bounds "
        f"the green one in neither direction) {down2(min(s2_read)):.2f}–{up2(max(s2_read)):.2f}; "
        f"{'; '.join(c2(n) for n in labels)}. State 3 (a rigid callus tie, its depth from the flange to the install-day "
        f"cambium at {', '.join(f'{v:g}' for v in tie_mm.values())} mm, the bearing acting too): with no bearing "
        f"{down2(min(min(v) for v in s3_free.values())):.2f}–{up2(max(max(v) for v in s3_free.values())):.2f} of `102`'s "
        f"shift, up to {up2(cap3['anode_bond_stiff']):.2f} ⊥ {up2(cap3['anode_bond_soft']):.2f} at a rigid bark; at the "
        f"stiff bond the cold pad conclusion "
        f"{'flips at any depth' if cold_d is None else f'holds only while the tie sits deeper than {math.floor(cold_d * 10) / 10:g} mm'} "
        f"and the hot one {'flips at any depth' if hot_d is None else f'only deeper than {math.floor(hot_d * 10) / 10:g} mm'}, "
        f"with no bearing — a bearing flips them deeper still. Ta on the adverse reversed corner needs "
        f"{ta['state1']['sway']:.4f} on the sway alone and {up2(ta['state1']['hot_preload']):.2f} with the preload in "
        f"state 1, up to {up2(ta['state2_at_air_dry_readings_max']['adverse_reversed']):.2f} ⊥ "
        f"{up2(ta['state2_at_air_dry_readings_max']['adverse_reversed_hot_preload']):.2f} in state 2 at the air-dry readings, "
        f"and in state 3 at least {down2(l3['anode_bond_stiff']['adverse_reversed']):.2f} ⊥ "
        f"{down2(l3['anode_bond_stiff']['adverse_reversed_hot_preload']):.2f} at the stiff bond and "
        f"{down2(l3['anode_bond_soft']['adverse_reversed']):.2f} ⊥ {down2(l3['anode_bond_soft']['adverse_reversed_hot_preload']):.2f} "
        f"at the soft one, whatever the tie's depth and the bearing. Ti-6Al-4V needs at most "
        f"{up2(max(seam[ALLOY_BASELINE]['at_share_1'].values())):.2f} at any share.")

    result = {
        "script": Path(__file__).name,
        "geometry": {"span_mm": span, "sleeve_area_mm2": round(a_sleeve, 2), "anode_radius_mm": r_anode,
                     "anode_length_mm": l_anode, "channel_radius_mm": r_sleeve, "anode_radial_clearance_mm": gap_radial,
                     "flange_annulus_mm2": round(a_annulus, 1), "bark_mm_78": bark_t, "phloem_mm_78": phloem,
                     "flange_seat_to_install_day_cambium_mm": tie_mm, "shift_span_mm_87": dx_mm,
                     "source": "55 · 77 · 78 · 87 caches; 01_04 §3.3 Ø15 narrow step = the sleeve's OD"},
        "inputs": {"E_bark_radial_MPa_air_dry": E_BARK_RADIAL_MPA,
                   "G_pairs_LR_RT_MPa": {k: list(v) for k, v in G_PAIRS_MPA.items()},
                   "G_eff_MPa": {k: round(v, 2) for k, v in G_EFF_MPA.items()},
                   "ln_R_over_r": list(LN_R_OVER_R), "alpha_xylem_green_ppm_K": ALPHA_XYLEM_GREEN_1K * 1e6,
                   "alpha_anode_ppm_K": round(alpha_anode * 1e6, 3)},
        "stiffness_N_per_mm": {"sleeve": {k: round(v, 1) for k, v in k_sleeve.items()},
                               "anode_bond": {k: round(v, 1) for k, v in k_a.items()},
                               "bark_bearing_per_MPa": {t: round(a_annulus / tv, 3) for t, tv in bark_t.items()},
                               "bark_bearing_at_air_dry_readings": {k: round(v, 3) for k, v in kf_read.items()}},
        "share": {"state1_anode_free": 0.0,
                  "state1_ties_not_bounded": ["the sleeve's grip in the Ø15 channel", "ice in the 2 mm gap at the cold edge"],
                  "state2_at_air_dry_readings": {"min": round(min(s2_read), 4), "max": round(max(s2_read), 4)},
                  "state2_cap_rigid_bark": {k: round(v, 4) for k, v in cap2.items()},
                  "state3_no_bearing_any_depth_of_102_shift": {b: {"min": round(min(v), 4), "max": round(max(v), 4)} for b, v in s3_free.items()},
                  "state3_cap_rigid_bark_of_102_shift": {k: round(v, 4) for k, v in cap3.items()}},
        "state2_bearing_N_per_mm": thr2,
        "state3_tie_depth_mm_no_bearing": dep3,
        "readings": {"state2": table2, "state3": table3},
        "heat": {"thresholds_102_ppm_K": {"cold": cold_thr, "hot": hot_thr},
                 "flange_located_by": "the bark (a Zone-3 fit, 00_07 HW.8.9, is not computed here)",
                 "cte_min_ppm_K_over_the_model": round(cte_min[0], 6),
                 "cte_min_at": {"bearing": "rigid" if cte_min[1] else "none", "tie": "rigid" if cte_min[2] else "none",
                                "anode_bond": "stiff" if cte_min[3] == k_a_hi else "soft", "tie_depth_mm": round(cte_min[4], 3),
                                "bond_depth_mm": cte_min[5]},
                 "cte_travel_reverses_ppm_K_102": round(cte_reverse, 6),
                 "wood_only_shortens_the_pad_travel": cte_min[0] > cte_reverse,
                 "cte_floor_span_follows_the_wood_ppm_K": round(cte_floor_coupled, 6),
                 "reversed_shift_per_K_at_most_of_free_sleeve": round(reversed_fraction, 6),
                 "deeper_tie_reaching_the_sign_change_mm_from_flange_seat": None if grip_reverse_depth is None else round(grip_reverse_depth, 3),
                 "not_in_the_wood_side": "the dead bark's thermal and humidity strain; the frost response and its sign at the tie"},
        "seam_on_102_closed_form": seam,
        "controls": {"solver_vs_closed_forms_max_miss": miss, "monotone_worst_step": mono,
                     "pad_travel_monotone_in_shift_worst_step": pad_worst,
                     "seam_vs_102_grid_max_miss": ctrl_miss},
        "verdict": verdict,
    }
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("\n  " + verdict)
    print(f"\n  seam: {json.dumps(seam, ensure_ascii=False)}")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
