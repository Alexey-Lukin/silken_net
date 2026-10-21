#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""103 — how much of the stem's radial shift the wood imposes on the anchor, per bond state, and which unmeasured
quantity decides it (00_07 HW.43 — the share leg, and the heat with the flange on a Zone-3 fit, both closed
2026-10-20; no solve).

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

TWO PREMISES for what locates the flange on the sleeve — the joint between them is the Zone-3 shank (01_01 §1: a Ø11
bore under interference; the CEM still carries a clearance placeholder, 00_07 HW.8.9). (a) FLANGE ON THE BARK: the
shank sits in clearance, the disc on the sleeve's top face, and the whole 32 mm between the anode's face and the seat is
PEEK. (b) ZONE-3 FIT: the shank is held in the sleeve over its run, taken as a RIGID fit (a fit that slips gives back
(a)) — over the shank's length the section is the Ti shank (the CEM's diameter less the bus channel) bonded to the PEEK
around it, so only the gap below it is PEEK. Each premise is read on `102`'s span of the same name: the effective CTE is
taken over the PEEK length, the Ti length at the flange alloy's CTE (`102`'s `pad_at`), and the pad thresholds and the
seam's hot preload are `102`'s for that span — the bonded section grows at its own composite CTE, `102`'s gap-only span
at the Ti's (the shank held at its end), and the offset between the two readings is printed.

STATES. (1) Anode not bonded: the anode end is free, so the wood imposes nothing through the flange — except where a
grip of the sleeve in its channel, or ice in the sap-filled 2 mm gap at the cold edge, ties it (neither is bounded).
(2) Anode bonded, the sleeve free below the bark: the anode bond, the sleeve and the bark bearing in series.
(3) Anode bonded and the sleeve tied RIGIDLY to the wood by the callus ring, the bark bearing acting too — canon's mature
state (the ring and the bark that rises against the flange at once). Canon grows the ring over Zone 2's OUTER edge
(01_04 §3.1 step 4, «Переваги»), and callus grows from the cambium outward while the stem's growth carries new wood
along the sleeve toward the flange — so the tie's depth below the flange seat is an AXIS, from the flange to the
install-day cambium (bark + phloem, `78`), the deepest it can sit.
One solver carries all three: the sleeve as two segments (flange → cambium → anode face) on three nodes, each segment's
compliance and free growth integrated over the premise's sections, the bearing k_F at the flange, a tie k_T at the
cambium (0 in state 2, rigid in state 3) and the anode bond k_A at the anode, against the wood's displacement — for the
sway `87`'s shift, linear in depth from the flange (0) to the anode's centroid (the full shift), for the heat the
xylem's free growth to the bond's depth against the sleeve's and the anode metal's between its face and that depth. The
share is the sleeve's stretch over the shift at the bond's depth, scaled to `102`'s shift (taken at `87`'s full depth)
before it enters the seam; controls hold the solver to the closed forms of state 2 (k_A, k_sleeve, k_F in series) and of
the bearing-released state 3, to an independent chain of short elements assembled by section (the premise's section
boundary inside it), and check that a partial tie lies between states 2 and 3 (monotone in k_T) and that the share and
the CTE move monotonically with the tie's depth.

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
alone and with `102`'s seasonal hot preload on the premise's span (the PEEK ⊥ Ti mismatch is the anchor's own and acts
in every state); the centre pad's hot and cold conclusions flip, with the bearing in contact (the bark's rise makes it
the service state). The seam at each share is `102`'s own closed form (its `Pair` and `soderberg_k`) on `102`'s cached
inputs, held to `102`'s grid by a control.

Stiffnesses: k_sleeve = E_PEEK·A/L over the 32 mm span (unrelaxed for the sway, × PEEK_RELAX_FLOOR for the slow heat),
each segment by its length — and under a Zone-3 fit the shank's run by E_Ti·A_shank + E_PEEK·A; k_A = 2π·G_eff·L_anode
/ ln(R/r), our order-of-magnitude shear-lag form for a cylinder pulled along the stem's radius, with G_eff = √(G_LR·G_RT)
— the radius-normal shear acts in both planes at once (anti-plane shear in an orthotropic medium) — and ln(R/r) carried
as a bracket.

CAN: give per state and premise the share of the sway shift, its cap at a rigid bark, the seam requirement it implies on
`102`'s closed form, the bearing stiffness at which each state-2 conclusion is reached at either end of the bond
bracket, and the tie's depth at which each state-3 conclusion is reached with no bearing; and per premise the (CTE, share)
front — the configurations no other beats on both — that `104` adds the held travel and the sway on (its ends held to
the free sleeve, the largest cap and the CTE floor by a control).
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
and the wood is not, which overstates how far a tied segment follows the wood; (8) the Zone-3 fit itself: its axial
holding force (a fit that slips returns premise (a)), the canonical Ø11 shank (the CEM's placeholder diameter is read)
and its length — both open in HW.8.9, so premise (b) is re-run when they land; a rigid tie on the Ti-reinforced run is
a bound the wood's own stiffness is further from than on PEEK.

Run:  conda activate silken_md
      python tools/in_silico/scripts/103_anchor_wood_share.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np

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

SI_DESCRIPTION = ("The share of a living stem's radial shift that the wood imposes on the anchor, per bond state of the "
                  "anode and the sleeve, from the stiffness of the bark bearing, the anode's bond in the xylem, a tie "
                  "of the sleeve at the cambium and the PEEK sleeve, with the bark-bearing stiffness at which the share "
                  "reaches each seam requirement and each contact-pad conclusion flips, at both ends of the anode-bond "
                  "bracket, for the flange located by the bark and by a rigid Zone-3 fit; no solve")

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
FRONT_STEP = 0.005         # the share step the (CTE, share) front is kept at (`104` bounds what falls between)
FE_STEP = 0.5              # mm — the element of the control chain; its tie depths and section boundaries sit on nodes


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


s55 = _load("bus55", "55_bus_mechanical.py")
s102 = _load("liner102", "102_wire_liner_shear_lag.py")   # its Pair and soderberg_k — the seam on its own closed form


class Sleeve:
    """The anchor between the flange's seat (depth 0) and the anode's face (depth `span`) as sections of uniform make-up,
    each (from, to, {load: EA}, α of its free growth on the relaxed PEEK). `ti_len` of the span counts as Ti in `102`'s
    span convention, so the effective CTE is read over the PEEK length `102`'s thresholds are about."""

    def __init__(self, span: float, segs: list, ti_len: float, alpha_ti: float):
        self.span, self.segs, self.ti_len, self.alpha_ti = span, segs, ti_len, alpha_ti
        self.peek_len = span - ti_len

    def _over(self, d1: float, d2: float) -> list:
        return [(max(0.0, min(d2, b) - max(d1, a)), ea, al) for a, b, ea, al in self.segs]

    def comp(self, d1: float, d2: float, load: str) -> float:
        """Axial compliance between two depths, mm/N."""
        return sum(x / ea[load] for x, ea, _ in self._over(d1, d2))

    def free(self, d1: float, d2: float) -> float:
        """Free thermal growth between two depths, mm/K (the relaxed PEEK's)."""
        return sum(x * al for x, _, al in self._over(d1, d2))

    def cte(self, s: float) -> float:
        """The effective CTE in ppm/K of the PEEK length, from a growth s in mm/K over the whole span, the Ti length at
        the flange alloy's CTE — `102`'s `pad_at` convention."""
        return (s - self.alpha_ti * self.ti_len) / self.peek_len * 1e6


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


def fe_stretch(sl: Sleeve, k_f: float, k_t: float, ka: float, d_t: float, load: str, w_t: float, w_a: float) -> float:
    """The control: the same chain as a row of FE_STEP-long bar elements, each assigned its section by its midpoint, the
    tie on a node, solved whole. Independent of `Sleeve.comp`/`free` and of the 3-node reduction. CAN catch a section
    boundary integrated wrongly, a tie split across it, a free growth on the wrong segment; CANNOT see a wrong section
    make-up, which both read from `segs`."""
    n = round(sl.span / FE_STEP)
    h = sl.span / n
    nodes = [d_t] + [x for a, b, _, _ in sl.segs for x in (a, b)]
    if any(abs(round(x / h) * h - x) > 1e-9 for x in nodes):
        raise ValueError("FE control: the tie and every section boundary must sit on a node")
    kmat, f = np.zeros((n + 1, n + 1)), np.zeros(n + 1)
    for e in range(n):
        mid = (e + 0.5) * h
        _, _, ea, al = next(s for s in sl.segs if s[0] <= mid < s[1])
        k, grow = ea[load] / h, (al * h if load == "slow" else 0.0)
        kmat[e:e + 2, e:e + 2] += k * np.array([[1.0, -1.0], [-1.0, 1.0]])
        f[e] -= k * grow
        f[e + 1] += k * grow
    it = round(d_t / h)
    kmat[0, 0] += k_f
    kmat[it, it] += k_t
    kmat[n, n] += ka
    f[it] += k_t * w_t
    f[n] += ka * w_a
    u = np.linalg.solve(kmat, f)
    return float(u[n] - u[0])


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
    alpha_anode = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]                  # the anode, the flange and the wire:
    #                                                                             `102`'s baseline alloy throughout

    # ── the two premises for what locates the flange on the sleeve ──
    ti_fl = ALLOY_PROPERTIES[ALLOY_BASELINE]
    d_shank = float(s55.cem("cathode_flange")["shank_diameter_mm"])            # the CEM's — a placeholder, HW.8.9
    l_shank = s55.SHANK_LEN_MM
    a_shank = math.pi / 4.0 * (d_shank ** 2 - s55.D_CHANNEL_MM ** 2)
    ea_peek = {"sway": e_peek * a_sleeve, "slow": e_peek * PEEK_RELAX_FLOOR * a_sleeve}
    # every fit of the anchor read by ONE rule — bonded over its run (lib.mechanics), the adverse end of its thermal
    # reading; the Zone-3 shank (premise b) and the Zone-1 anode shank pressed into the sleeve's bottom (both premises)
    ea_comp, alpha_comp = bonded_fit_section(ti_fl["E_GPa"] * 1e3, ti_fl["alpha_1K"], a_shank, e_peek, ALPHA_PEEK_1K,
                                             a_sleeve, PEEK_RELAX_FLOOR)
    lock1 = s55.cem("mechanical_lock.zone1")
    l_z1 = s55.Z1_INSERTION_MM
    a_z1 = math.pi / 4.0 * (lock1["shank_diameter_mm"] ** 2 - lock1["bore_diameter_mm"] ** 2)
    _, alpha_z1 = bonded_fit_section(ti_fl["E_GPa"] * 1e3, alpha_anode, a_z1, e_peek, ALPHA_PEEK_1K, a_sleeve, PEEK_RELAX_FLOOR)
    sleeves = {"flange_on_bark": Sleeve(span, [(0.0, span, ea_peek, ALPHA_PEEK_1K)], 0.0, ti_fl["alpha_1K"]),
               "zone3_fit": Sleeve(span, [(0.0, l_shank, ea_comp, alpha_comp), (l_shank, span, ea_peek, ALPHA_PEEK_1K)],
                                   l_shank, ti_fl["alpha_1K"])}

    def stretch(sl: Sleeve, k_f: float, k_t: float, ka: float, d_t: float, load: str, w_t: float, w_a: float) -> float:
        """The sleeve's stretch (anode node − flange node) on the 3-node chain; the wood is at 0 under the flange."""
        k_up, k_lo = 1.0 / sl.comp(0.0, d_t, load), 1.0 / sl.comp(d_t, span, load)
        e_up, e_lo = (sl.free(0.0, d_t), sl.free(d_t, span)) if load == "slow" else (0.0, 0.0)
        x0, _, x2 = tridiag3(k_f + k_up, -k_up, -k_up, k_up + k_lo + k_t, -k_lo, -k_lo, k_lo + ka,
                             (-k_up * e_up, k_t * w_t + k_up * e_up - k_lo * e_lo, ka * w_a + k_lo * e_lo))
        return x2 - x0

    def share(sl: Sleeve, k_f: float, k_t: float, ka: float, d_t: float, dv: float) -> float:
        """The sleeve's stretch over the shift at the bond's depth dv."""
        return stretch(sl, k_f, k_t, ka, d_t, "sway", d_t / dv, 1.0)

    def w_anode_heat(dv: float, ax: float = ALPHA_XYLEM_GREEN_1K, z1_bonded: bool = True) -> float:
        """Per kelvin: the wood's growth to the bond's depth less the anode metal's between its face and that depth — the
        anode's shank inside the sleeve bonded to the PEEK around it (the fits' one rule), or held at its end (Ti alone)."""
        return ax * dv - (alpha_z1 if z1_bonded else alpha_anode) * l_z1 - alpha_anode * (dv - span - l_z1)

    def a_eff(sl: Sleeve, k_f: float, k_t: float, ka: float, d_t: float, dv: float, ax: float = ALPHA_XYLEM_GREEN_1K,
              z1_bonded: bool = True) -> float:
        """The span's effective CTE, ppm/K of its PEEK length, on the relaxed PEEK."""
        return sl.cte(stretch(sl, k_f, k_t, ka, d_t, "slow", ax * d_t, w_anode_heat(dv, ax, z1_bonded)))

    # controls: the solver against the closed forms of state 2 and of the bearing-released state 3, per premise
    miss = 0.0
    for sl in sleeves.values():
        k_s = {ld: 1.0 / sl.comp(0.0, span, ld) for ld in ("sway", "slow")}
        e_tot = sl.free(0.0, span)
        for ka in (k_a_lo, k_a_hi):
            for dv in dx_mm.values():
                for k_f in (1.0, 300.0, 1e5):
                    kc = series(ka, k_f)
                    miss = max(miss, abs(share(sl, k_f, 0.0, ka, 5.0, dv) - kc / (kc + k_s["sway"])),
                               abs(a_eff(sl, k_f, 0.0, ka, 5.0, dv) - sl.cte(e_tot + (w_anode_heat(dv) - e_tot) * kc / (kc + k_s["slow"]))))
                for d_t in tie_mm.values():
                    seg, seg_slow = (ka / (ka + 1.0 / sl.comp(d_t, span, ld)) for ld in ("sway", "slow"))
                    e_lo = sl.free(d_t, span)
                    miss = max(miss, abs(share(sl, 0.0, TIE_RIGID, ka, d_t, dv) - seg * (dv - d_t) / dv),
                               abs(a_eff(sl, 0.0, TIE_RIGID, ka, d_t, dv) - sl.cte(sl.free(0.0, d_t) + e_lo + (w_anode_heat(dv) - ALPHA_XYLEM_GREEN_1K
                                                                                                             * d_t - e_lo) * seg_slow)))
    if miss > 1e-6:
        raise RuntimeError(f"control: the 3-node solver misses the closed forms by {miss}")

    # control: the 3-node reduction against the element chain — a tie on, above and below each premise's section
    # boundary, every state's stiffness, both loads. The miss is scaled by the LOAD, not by the result: with no bearing and
    # no tie the sway moves the sleeve whole and its true stretch is 0, where a ratio to the result measures roundoff
    # (the sway's scale is the unit shift at the bond, the heat's the sleeve's own free growth)
    fe_miss = 0.0
    for sl in sleeves.values():
        scale = {"sway": 1.0, "slow": sl.free(0.0, span)}
        for d_t in (5.0, l_shank, 20.0, 24.0, span - FE_STEP):
            for k_f in (0.0, 300.0, 1e5):
                for k_t in (0.0, 1e3, TIE_RIGID):
                    for ka in (k_a_lo, k_a_hi):
                        for dv in dx_mm.values():
                            for load, w_t, w_a in (("sway", d_t / dv, 1.0),
                                                   ("slow", ALPHA_XYLEM_GREEN_1K * d_t, w_anode_heat(dv))):
                                a3 = stretch(sl, k_f, k_t, ka, d_t, load, w_t, w_a)
                                af = fe_stretch(sl, k_f, k_t, ka, d_t, load, w_t, w_a)
                                fe_miss = max(fe_miss, abs(a3 - af) / scale[load])
    if fe_miss > 1e-8:
        raise RuntimeError(f"control: the 3-node reduction misses the element chain by {fe_miss:.3e} of the load's scale")

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

    monos = {}
    for pname, sl in sleeves.items():
        mono = {"in_bearing": 0.0, "in_bond": 0.0, "in_tie": 0.0, "in_tie_depth": 0.0}
        for dv in dx_mm.values():
            for d_t in tie_mm.values():
                for kt in (0.0, 1e2, 1e4, TIE_RIGID):
                    for ka in grid_a:
                        mono["in_bearing"] = max(mono["in_bearing"], worst_rise([share(sl, kf, kt, ka, d_t, dv) for kf in grid_f]),
                                                 worst_rise([-a_eff(sl, kf, kt, ka, d_t, dv) for kf in grid_f]))
                    for kf in (0.0, 1e2, 1e4, 1e8):
                        mono["in_bond"] = max(mono["in_bond"], worst_rise([share(sl, kf, kt, ka, d_t, dv) for ka in grid_a]),
                                              worst_rise([-a_eff(sl, kf, kt, ka, d_t, dv) for ka in grid_a]))
                for ka in grid_a:
                    for kf in (0.0, 1e2, 1e4, 1e8):
                        for seq in ([share(sl, kf, kt, ka, d_t, dv) for kt in grid_t], [a_eff(sl, kf, kt, ka, d_t, dv) for kt in grid_t]):
                            mono["in_tie"] = max(mono["in_tie"], min(worst_rise(seq), worst_rise([-x for x in seq])))
            for ka in grid_a:
                mono["in_tie_depth"] = max(mono["in_tie_depth"], worst_rise([-share(sl, 0.0, TIE_RIGID, ka, d, dv) for d in grid_d]),
                                           worst_rise([a_eff(sl, 0.0, TIE_RIGID, ka, d, dv) for d in grid_d]))
                # at a rigid bark the CTE runs the other way with depth (falling) — monotone, so the CTE's floor over the
                # model sits at an end of every axis (the bearing's two ends bracket it, monotone in the bearing above)
                seq = [a_eff(sl, TIE_RIGID, TIE_RIGID, ka, d, dv) for d in grid_d]
                mono["in_tie_depth"] = max(mono["in_tie_depth"], min(worst_rise(seq), worst_rise([-x for x in seq])))
        if max(mono.values()) > 1e-8:
            raise RuntimeError(f"control: not monotone where the readings need it ({pname}): {mono}")
        monos[pname] = mono

    # ── the seam on `102`'s own closed form ──
    geo = d102["geometry"]
    shipped = d86["by_geometry"][next(k for k in d86["by_geometry"] if k.startswith("shipped"))]
    amp86, off86 = d102["seam_86_inputs"]["amplitude_MPa"], d102["seam_86_inputs"]["offset_um"]
    shift_hi = max(d102["sway_input"]["shift_um_87"]["upper_whisker"]) * 1e-3
    shift_lo = min(d102["sway_input"]["shift_um_87"]["median"]) * 1e-3
    ceiling_grips = d102["grip"]["by_part_N_per_mm_at_20C"]["window_ceiling"]
    q_adv = ceiling_grips[max(ceiling_grips, key=float)]                 # the tightest part at `102`'s largest μ

    def preload_of(alloy: str, premise: str) -> float:
        """`102`'s relaxed-liner hot preload on the premise's span."""
        hp = d102["seam_by_alloy"][alloy]["hot_preload"]
        return hp["F_N_relaxed_liner"] if premise == "flange_on_bark" else hp["zone3_fit_bonded_shank"]["F_N_relaxed_liner"]

    def seam_k(alloy: str, sh: float, corner: str, premise: str = "flange_on_bark") -> float | None:
        """`102`'s seam at a share of `102`'s shift, on `102`'s own Pair, inputs and preload (its cached relaxed-liner hot
        preload force on the premise's span), clipped at the wall as `102` clips it."""
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
                f_mean += preload_of(alloy, premise)
                if f_amp + f_mean > pr.cap + 1e-9:
                    f_mean = pr.cap - f_amp
        return s102.soderberg_k(amp86, mean86, f_amp, f_mean, geo["wire_area_mm2"], row86)

    # control: this function at `102`'s grid shares must give back `102`'s cached seam requirements (the 32 mm preload)
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

    flips = d102["thermal"]["flip_vs_larger_margin_ppm_K"]
    flip_keys = {"flange_on_bark": ("cold_flange_on_bark", "hot_floor_part_flange_on_bark"),
                 "zone3_fit": ("cold_zone3_fit_gap_only", "hot_floor_part_zone3_fit_gap_only")}
    wire_run = s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM + s55.LINER_LENGTH_MM
    kf_read = {f"{e}__{t}": ev * a_annulus / tv for e, ev in E_BARK_RADIAL_MPA.items() for t, tv in bark_t.items()}
    d_deep = max(tie_mm.values())
    depths = {t: [DEPTH_MIN + (d - DEPTH_MIN) * i / 40 for i in range(41)] for t, d in tie_mm.items()}
    corners = ("adverse_reversed", "adverse_reversed_hot_preload", "adverse_one_sided", "gentle")
    labels = {"share_0.25": "the share reaches `102`'s 0.25 row", "ta_k1_sway_alone": "Ta's seam passes k 1 on the sway alone",
              "ta_k1_hot_preload": "Ta's seam passes k 1 with the hot preload", "hot": "the centre pad's hot conclusion flips",
              "cold": "the centre pad's cold conclusion flips"}

    def r6(v):
        return None if v is None else round(v, 6)

    def by_bond(vals: dict, bond: str) -> list:
        return [v for k, v in vals.items() if k.endswith(bond)]

    def group(thr: dict, name: str) -> dict:
        return {f"{x}__{k}": v for x, vals in thr.items() if x == name or x.startswith(name + "_flip_") for k, v in vals.items()}

    def analyse(premise: str) -> dict:
        """Every reading of one premise — the same events, axes and floors, on its sleeve, thresholds and preload."""
        sl = sleeves[premise]
        cold_thr, hot_thr = (sorted(set(flips[k])) for k in flip_keys[premise])

        # ── the events, each increasing in what reaches it ──
        def event(name: str, k_f: float, k_t: float, ka: float, d_t: float, dv: float) -> float:
            if name.startswith("share_"):                                      # `102`'s rows are shares of its shift
                return share(sl, k_f, k_t, ka, d_t, dv) * dv / dv_ceil - float(name.split("_")[1])
            if name.startswith("ta_k1_"):
                corner = "adverse_reversed_hot_preload" if name.endswith("hot_preload") else "adverse_reversed"
                return seam_k("Ta", share(sl, k_f, k_t, ka, d_t, dv) * dv / dv_ceil, corner, premise) - 1.0
            return float(name.split("_")[2]) - a_eff(sl, k_f, k_t, ka, d_t, dv)
        names = ([f"share_{row:g}" for row in SHARE_ROWS] + ["ta_k1_sway_alone", "ta_k1_hot_preload"]
                 + [f"hot_flip_{x:g}" for x in hot_thr] + [f"cold_flip_{x:g}" for x in cold_thr])

        # state 2: the bearing at which each is reached, per bond end and `87` depth reading (the tie's depth is moot there)
        thr2 = {n: {f"{dk}__{b}": r6(threshold(lambda kf, n=n, ka=ka, dv=dv: event(n, kf, 0.0, ka, 5.0, dv)))
                    for dk, dv in dx_mm.items() for b, ka in bonds} for n in names}

        # state 3: with no bearing, the rigid tie's depth shallower than which each is reached (0 = not even at the flange,
        # «deepest» = already at the install-day cambium of the deeper bark reading)
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
        s2_read = [share(sl, kf, 0.0, ka, 5.0, dv_ceil) for kf in kf_read.values() for ka in k_a.values()]
        # «at a rigid bark» is the rigid constant, not the bearing axis's search bound: against the Ti-reinforced run of a
        # Zone-3 fit a bearing of KF_HI is not rigid (it under-read the state-3 cap by 8e-4 there)
        cap2 = {b: share(sl, TIE_RIGID, 0.0, ka, 5.0, dv_ceil) for b, ka in bonds}
        s3_free = {b: [share(sl, 0.0, TIE_RIGID, ka, d, dv) * dv / dv_ceil for ds in depths.values() for d in ds for dv in dx_mm.values()]
                   for b, ka in bonds}
        cap3 = {b: max(share(sl, TIE_RIGID, TIE_RIGID, ka, d, dv) * dv / dv_ceil for ds in depths.values() for d in ds for dv in dx_mm.values())
                for b, ka in bonds}
        # the lowest CTE the model reaches — over the corners of the stiffness box (each stiffness enters one diagonal cell, so
        # the CTE is a ratio of linear functions in each and its minimum at every depth sits at a corner) and the depth axis,
        # whose ends carry it at a rigid tie (monotone in depth at both bearing ends, controls above) — against the CTE at which the pad's travel per kelvin changes sign on `102`'s span of this premise (α·PEEK + α_Ti·Ti −
        # α_Ti·wire = 0, its `pad_at`): above it, holding the span only shortens the thermal travel, so the free sleeve is the
        # travel's adverse end; and the floor of any coupling at all — the span following the wood outright — which bounds a
        # reversed travel beyond the model's brackets
        cte_reverse = alpha_anode * (wire_run - s55.FLANGE_THK_MM - sl.ti_len) / sl.peek_len * 1e6
        cte_grid = [(a_eff(sl, kf, kt, ka, d, dv), kf, kt, ka, d, dv) for kf in (0.0, TIE_RIGID) for kt in (0.0, TIE_RIGID)
                    for ka in (k_a_lo, k_a_hi) for d in grid_d for dv in dx_mm.values()]
        cte_min = min(cte_grid)
        cte_floor_coupled = sl.cte(min(w_anode_heat(dv) for dv in dx_mm.values()))
        cte_free = sl.cte(sl.free(0.0, span))

        def cte_min_over_model(ax: float = ALPHA_XYLEM_GREEN_1K, z1_bonded: bool = True) -> float:
            return min(a_eff(sl, kf, kt, ka, d, dv, ax, z1_bonded) for kf in (0.0, TIE_RIGID) for kt in (0.0, TIE_RIGID)
                       for ka in (k_a_lo, k_a_hi) for d in grid_d for dv in dx_mm.values())
        # the xylem CTE below which, within the model, the wood could reverse the pad's thermal travel — the headline
        # «only shortens» stands on one reading of it (in-silico §When Modifying #40); the min is monotone in it
        lo_x, hi_x = 0.0, ALPHA_XYLEM_GREEN_1K
        if cte_min_over_model(hi_x) <= cte_reverse or cte_min_over_model(lo_x) >= cte_reverse:
            ax_reverse = None
        else:
            for _ in range(60):
                mid = 0.5 * (lo_x + hi_x)
                lo_x, hi_x = (lo_x, mid) if cte_min_over_model(mid) > cte_reverse else (mid, hi_x)
            ax_reverse = 0.5 * (lo_x + hi_x)
        # the favourable end of the fits' reading: the anode's shank held at its end, Ti alone
        ti_end = {"cte_min_ppm_K": round(cte_min_over_model(z1_bonded=False), 6),
                  "cte_floor_span_follows_the_wood_ppm_K": round(sl.cte(min(w_anode_heat(dv, z1_bonded=False) for dv in dx_mm.values())), 6)}
        ti_end["reversed_shift_per_K_at_most_of_free_sleeve"] = round(
            (cte_reverse - ti_end["cte_floor_span_follows_the_wood_ppm_K"]) / (cte_free - cte_reverse), 6)
        reversed_fraction = (cte_reverse - cte_floor_coupled) / (cte_free - cte_reverse)
        # a channel grip is a deeper tie of the same kind: the depth below the flange seat past which a rigid tie, at a rigid
        # bark and the stiff bond, takes the CTE to the travel's sign change
        lo, hi = d_deep, span - 1e-3
        for _ in range(80):
            mid = 0.5 * (lo + hi)
            if a_eff(sl, TIE_RIGID, TIE_RIGID, k_a_hi, mid, dv_ceil) > cte_reverse:
                lo = mid
            else:
                hi = mid
        grip_reverse_depth = 0.5 * (lo + hi) if a_eff(sl, TIE_RIGID, TIE_RIGID, k_a_hi, span - 1e-3, dv_ceil) < cte_reverse else None
        seam = {}
        for alloy in ("Ta", ALLOY_BASELINE):
            # the least state-3 requirement: the deepest tie (the thick bark's install-day cambium), no bearing, the nominal depth
            least3 = {b: {c: round(min(seam_k(alloy, share(sl, 0.0, TIE_RIGID, ka, d_deep, dv) * dv / dv_ceil, c, premise)
                                       for dv in dx_mm.values()), 4)
                          for c in ("adverse_reversed", "adverse_reversed_hot_preload")} for b, ka in bonds}
            seam[alloy] = {"state1": {"sway": d102["seam_by_alloy"][alloy]["seam_k_86"],
                                      "hot_preload": round(seam_k(alloy, 0.0, "adverse_reversed_hot_preload", premise), 4)},
                           "state2_at_air_dry_readings_max": {c: round(seam_k(alloy, max(s2_read), c, premise), 4) for c in corners},
                           "state3_least_any_depth_and_bearing": least3,
                           "at_share_1": {c: round(seam_k(alloy, 1.0, c, premise), 4) for c in corners}}

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
        # the (CTE, share) pairs no other configuration beats on both — over the bearing, tie, bond, tie depth and bond depth
        # grids. `104` adds the held travel at the CTE to the sway at the share; both rise (the travel in the CTE above its sign change, the sway in the share),
        # so their sum's maximum over these configurations lies on this front, whose top end is the free sleeve (share 0).
        # Kept every FRONT_STEP of share: a dropped point lies in the box of two kept neighbours, so `104` bounds the sum
        # from above by each kept CTE with the NEXT kept share
        pts = []
        d_front = sorted({*grid_d, *(d for ds in depths.values() for d in ds)})
        for kf in (*grid_f, TIE_RIGID):
            for ka in grid_a:
                for dv in dx_mm.values():
                    for kt in grid_t:
                        for d in (d_front if kt > 0 else (5.0,)):
                            pts.append((a_eff(sl, kf, kt, ka, d, dv), share(sl, kf, kt, ka, d, dv) * dv / dv_ceil, kf, kt, ka, d, dv))
        pts.sort(key=lambda p: (-p[0], -p[1]))
        full, s_top = [], -1.0
        for a, sh, *_ in pts:
            if sh > s_top + 1e-12:
                full.append((a, sh))
                s_top = sh
        # control: the front's ends are the model's own extremes — its least share-0 point the free sleeve, its largest
        # share the larger rigid-bark cap of states 2 and 3 (over the same depths), and no configuration below the CTE floor
        if abs(full[0][0] - cte_free) > 1e-9 or abs(full[-1][1] - max(*cap2.values(), *cap3.values())) > 1e-9 or min(p[0] for p in pts) < cte_min[0] - 1e-9:
            raise RuntimeError(f"control: the (CTE, share) front's ends are not the model's free sleeve, cap and CTE floor: "
                               f"{full[0][0]} vs {cte_free}; {full[-1][1]} vs {max(*cap2.values(), *cap3.values())}; {min(p[0] for p in pts)} vs {cte_min[0]}")
        kept = [full[0]]
        for a, sh in full[1:-1]:
            if sh - kept[-1][1] >= FRONT_STEP:
                kept.append((a, sh))
        if len(kept) > 1 and full[-1][1] - kept[-1][1] < FRONT_STEP:
            kept[-1] = full[-1]          # the end replaces a near neighbour: the dropped point lies in their box
        else:
            kept.append(full[-1])
        front = {"cte_ppm_K": [round(a, 6) for a, _ in kept], "share_of_102_shift": [round(sh, 6) for _, sh in kept],
                 "points_on_the_full_front": len(full), "step": FRONT_STEP,
                 "reading": "non-dominated (CTE, share) pairs over the model's grids, every FRONT_STEP of share; a dropped "
                            "point lies between two kept neighbours on both axes"}
        return {
            "front": front,
            "sleeve": sl, "thr2": thr2, "dep3": dep3, "table2": table2, "table3": table3, "seam": seam,
            "s2_read": s2_read, "cap2": cap2, "s3_free": s3_free, "cap3": cap3, "cold_thr": cold_thr, "hot_thr": hot_thr,
            "heat": {"thresholds_102_ppm_K": {"cold": flips[flip_keys[premise][0]], "hot": flips[flip_keys[premise][1]]},
                     "cte_min_ppm_K_over_the_model": round(cte_min[0], 6),
                     "cte_min_at": {"bearing": "rigid" if cte_min[1] else "none", "tie": "rigid" if cte_min[2] else "none",
                                    "anode_bond": "stiff" if cte_min[3] == k_a_hi else "soft", "tie_depth_mm": round(cte_min[4], 3),
                                    "bond_depth_mm": cte_min[5]},
                     "cte_travel_reverses_ppm_K_102": round(cte_reverse, 6),
                     "wood_only_shortens_the_pad_travel": cte_min[0] > cte_reverse,
                     "cte_floor_span_follows_the_wood_ppm_K": round(cte_floor_coupled, 6),
                     "reversed_shift_per_K_at_most_of_free_sleeve": round(reversed_fraction, 6),
                     "deeper_tie_reaching_the_sign_change_mm_from_flange_seat": None if grip_reverse_depth is None else round(grip_reverse_depth, 3),
                     "xylem_cte_at_which_the_wood_reverses_the_travel_ppm_K": None if ax_reverse is None else round(ax_reverse * 1e6, 6),
                     "fits_read": "bonded over the run (lib.mechanics) — the adverse end; the Zone-1 shank held at its end below",
                     "zone1_shank_held_at_its_end": ti_end},
            "cte_free": cte_free,
        }

    bark, z3 = analyse("flange_on_bark"), analyse("zone3_fit")

    def down2(x: float) -> float:
        return math.floor(round(x * 100, 9)) / 100

    def up2(x: float) -> float:
        return math.ceil(round(x * 100, 9)) / 100

    def up1(x: float) -> float:
        return math.ceil(round(x * 10, 9)) / 10

    def c2(n: str, table2: dict) -> str:
        no, yes = table2[n]["no_below"], table2[n]["yes_above"]
        a = "at any bearing" if no == 0.0 else ("at no bearing" if no is None else f"not below {math.floor(no)} N/mm")
        b = "" if yes is None else f", whatever the bond above {math.ceil(yes)} N/mm"
        return f"{labels[n]} {a} (stiff bond){b}"

    def state3_phrase(table3: dict) -> str:
        cold_d, hot_d = table3["cold"]["holds_only_deeper_than_mm"], table3["hot"]["holds_only_deeper_than_mm"]
        cold = ("flips at any depth" if table3["cold"]["reached_at_any_depth"] else "never flips" if cold_d is None
                else f"holds only while the tie sits deeper than {math.floor(cold_d * 10) / 10:g} mm")
        hot = ("flips at any depth" if table3["hot"]["reached_at_any_depth"] else "never flips" if hot_d is None
               else f"only deeper than {math.floor(hot_d * 10) / 10:g} mm")
        return f"the cold pad conclusion {cold} and the hot one {hot}"

    ta = bark["seam"]["Ta"]
    l3 = ta["state3_least_any_depth_and_bearing"]
    verdict = (
        f"State 1 (the anode not bonded — a Ø{2 * r_anode:g} gyroid with {gap_radial:g} mm of radial clearance in the "
        f"Ø{2 * r_sleeve:g} channel): share 0, unless the channel grips the sleeve or ice fills the gap (neither bounded). "
        f"State 2 (anode bonded, the sleeve free below the bark): the anode bond caps the share at "
        f"{up2(bark['cap2']['anode_bond_stiff']):.2f} (stiff bond) ⊥ {up2(bark['cap2']['anode_bond_soft']):.2f} (soft); at the air-dry bark "
        f"readings (a bearing of {math.floor(min(kf_read.values()))}–{math.ceil(max(kf_read.values()))} N/mm, which bounds "
        f"the green one in neither direction) {down2(min(bark['s2_read'])):.2f}–{up2(max(bark['s2_read'])):.2f}; "
        f"{'; '.join(c2(n, bark['table2']) for n in labels)}. State 3 (a rigid callus tie, its depth from the flange to the install-day "
        f"cambium at {', '.join(f'{v:g}' for v in tie_mm.values())} mm, the bearing acting too): with no bearing "
        f"{down2(min(min(v) for v in bark['s3_free'].values())):.2f}–{up2(max(max(v) for v in bark['s3_free'].values())):.2f} of `102`'s "
        f"shift, up to {up2(bark['cap3']['anode_bond_stiff']):.2f} ⊥ {up2(bark['cap3']['anode_bond_soft']):.2f} at a rigid bark; at the "
        f"stiff bond {state3_phrase(bark['table3'])}, "
        f"with no bearing — a bearing flips them deeper still. Ta on the adverse reversed corner needs "
        f"{ta['state1']['sway']:.4f} on the sway alone and {up2(ta['state1']['hot_preload']):.2f} with the preload in "
        f"state 1, up to {up2(ta['state2_at_air_dry_readings_max']['adverse_reversed']):.2f} ⊥ "
        f"{up2(ta['state2_at_air_dry_readings_max']['adverse_reversed_hot_preload']):.2f} in state 2 at the air-dry readings, "
        f"and in state 3 at least {down2(l3['anode_bond_stiff']['adverse_reversed']):.2f} ⊥ "
        f"{down2(l3['anode_bond_stiff']['adverse_reversed_hot_preload']):.2f} at the stiff bond and "
        f"{down2(l3['anode_bond_soft']['adverse_reversed']):.2f} ⊥ {down2(l3['anode_bond_soft']['adverse_reversed_hot_preload']):.2f} "
        f"at the soft one, whatever the tie's depth and the bearing. Ti-6Al-4V needs at most "
        f"{up2(max(bark['seam'][ALLOY_BASELINE]['at_share_1'].values())):.2f} at any share. Heat: within the model the free "
        f"sleeve is the adverse end of the pad's thermal travel while xylem's CTE stays above "
        f"{up2(bark['heat']['xylem_cte_at_which_the_wood_reverses_the_travel_ppm_K']):.2f} ppm/K (the one reading taken is "
        f"{ALPHA_XYLEM_GREEN_1K * 1e6:g}).")

    def floor_ppm(x: float) -> float:
        return math.floor(round(x * 100, 9)) / 100

    zs = z3["seam"]["Ta"]
    zl3 = zs["state3_least_any_depth_and_bearing"]
    zh = z3["heat"]
    z_shortens = zh["wood_only_shortens_the_pad_travel"]
    comp_offset = (alpha_comp - ti_fl["alpha_1K"]) * l_shank / sleeves["zone3_fit"].peek_len * 1e6
    # the temperature readings on which `102`'s free gap-only sleeve does not leave the window hot (no threshold there)
    flip_gap = {k.split("__", 1)[1]: v["hot_floor_part_vs_lower_margin_ppm_K"] for k, v in d102["thermal"]["flip_effective_cte_ppm_K"].items()
                if k.startswith("gap_only")}
    reading_name = {"capsule_model_edges_90": "capsule-edge (`90`)", "cambium_under_flange_79": "cambium-under-the-flange (`79`)"}
    no_hot = [reading_name.get(t, t) for t, v in flip_gap.items() if v[max(v, key=float)] is None]
    # the soft bond in state 3 with no bearing: at which depths each pad conclusion still holds
    soft3 = {s: [v for n, vals in z3["dep3"].items() if n.startswith(f"{s}_flip_") for k, v in vals.items() if k.endswith("anode_bond_soft")]
             for s in ("cold", "hot")}
    soft_out = all(v is None for vs in soft3.values() for v in vs)
    # state 3 at the stiff bond, per temperature reading — each reading has its own threshold, and an aggregate over them
    # would call a reading's sliver of depth («only deeper than X») a «never»
    flip_gap_all = {k.split("__", 1)[1]: v for k, v in d102["thermal"]["flip_effective_cte_ppm_K"].items() if k.startswith("gap_only")}
    flip_side = {"cold": "cold_tightest_grip_vs_upper_margin_ppm_K", "hot": "hot_floor_part_vs_lower_margin_ppm_K"}

    def per_reading(side: str) -> str:
        parts = []
        for x in (z3["cold_thr"] if side == "cold" else z3["hot_thr"]):
            rd = [reading_name.get(t, t) for t, v in flip_gap_all.items() if v[flip_side[side]][max(v[flip_side[side]], key=float)] == x]
            dep = [v for k, v in z3["dep3"][f"{side}_flip_{x:g}"].items() if k.endswith("anode_bond_stiff")]
            # «at no depth» only when EVERY bond-depth reading reaches it at the deepest tie; otherwise the necessary depth
            # is the largest numeric one (a «deepest» reading never holds, so it only strengthens «only while deeper»)
            num = [v for v in dep if isinstance(v, float)]
            what = ("at no depth" if all(v == "deepest" for v in dep) else "at every depth" if all(v is None for v in dep)
                    else f"only while the tie sits deeper than {math.floor(max(num) * 10) / 10:g} mm" if num and None not in dep
                    else "at some depths only")
            parts.append(f"{what} on the {' and '.join(rd)} reading")
        return f"the {side} one (the pad out of L1) holds " + ", ".join(parts)
    verdict_z3 = (
        f"With a Zone-3 fit locating the flange — the CEM's Ø{d_shank:g} × {l_shank:g} mm shank taken as fitted rigidly in "
        f"the sleeve (a placeholder, HW.8.9; a fit that slips returns the bark reading) — only the "
        f"{sleeves['zone3_fit'].peek_len:g} mm gap below the shank is PEEK, and the shank's run grows at "
        f"{alpha_comp * 1e6:.2f} ppm/K as the Ti bonded to the PEEK around it (`102`'s gap-only span takes the Ti's "
        f"{ti_fl['alpha_1K'] * 1e6:g}, an offset of {up1(comp_offset):.1f} ppm/K on the gap). The share of the sway shift: in state 2 "
        f"capped at {up2(z3['cap2']['anode_bond_stiff']):.2f} ⊥ {up2(z3['cap2']['anode_bond_soft']):.2f}, "
        f"{down2(min(z3['s2_read'])):.2f}–{up2(max(z3['s2_read'])):.2f} at the air-dry readings; in state 3 with no bearing "
        f"{down2(min(min(v) for v in z3['s3_free'].values())):.2f}–{up2(max(max(v) for v in z3['s3_free'].values())):.2f}, up to "
        f"{up2(z3['cap3']['anode_bond_stiff']):.2f} ⊥ {up2(z3['cap3']['anode_bond_soft']):.2f} at a rigid bark. Heat: over every state, "
        f"bond, bearing and tie depth the gap's effective CTE {'never falls below' if z_shortens else 'falls to'} "
        f"{floor_ppm(zh['cte_min_ppm_K_over_the_model']):.2f} ppm/K against the {zh['cte_travel_reverses_ppm_K_102']:g} at which "
        f"the pad's travel changes sign on that span, so "
        + (f"within the model the free sleeve stays the adverse end of the pad's thermal travel — the free gap at "
           f"{z3['cte_free']:.1f} ppm/K, {up1(z3['cte_free'] - ALPHA_PEEK_1K * 1e6):.1f} above `102`'s gap-only reading — "
           f"while xylem's CTE stays above {up2(zh['xylem_cte_at_which_the_wood_reverses_the_travel_ppm_K']):.2f} ppm/K (the one "
           f"reading taken is {ALPHA_XYLEM_GREEN_1K * 1e6:g}); the deciding corner (a rigid tie at the thick bark's "
           f"install-day cambium, {zh['cte_min_at']['tie_depth_mm']:g} mm, below the shank) leaves the shank's run unloaded; "
           if z_shortens else "within the model the wood can reverse the pad's thermal travel; ")
        + f"the span following the wood outright takes the gap's CTE to {floor_ppm(zh['cte_floor_span_follows_the_wood_ppm_K']):.2f}, "
        f"a reversed shift per kelvin under {math.ceil(zh['reversed_shift_per_K_at_most_of_free_sleeve'] * 1000) / 10:g} % of the "
        f"free sleeve's. The cold conclusion holds while the gap's CTE stays above "
        f"{'–'.join(f'{up1(x):.1f}' for x in z3['cold_thr'])} ppm/K and the hot one above "
        f"{'–'.join(f'{up1(x):.1f}' for x in z3['hot_thr'])}"
        + (f" (the {', '.join(no_hot)} reading has no hot threshold: the free sleeve does not leave the window hot there)"
           if no_hot else "")
        + f"; state 2: {c2('cold', z3['table2'])}; {c2('hot', z3['table2'])}; {c2('ta_k1_hot_preload', z3['table2'])}; "
        f"state 3 with no bearing, at the stiff bond: {per_reading('cold')}; {per_reading('hot')} (the deepest tie sits at "
        f"{d_deep:g} mm)"
        + ("; at the soft bond both hold at every depth" if soft_out else "")
        + f". Ta on the adverse reversed corner needs {up2(zs['state1']['hot_preload']):.2f} in state 1 with `102`'s preload "
        f"on the bonded shank's span, and in state 3 at least {down2(zl3['anode_bond_stiff']['adverse_reversed']):.2f} on the "
        f"sway alone and {down2(zl3['anode_bond_stiff']['adverse_reversed_hot_preload']):.2f} with the preload at the stiff "
        f"bond, {down2(zl3['anode_bond_soft']['adverse_reversed']):.2f} and "
        f"{down2(zl3['anode_bond_soft']['adverse_reversed_hot_preload']):.2f} at the soft one, whatever the tie's depth and the "
        f"bearing.")

    def shares_block(r: dict) -> dict:
        return {"state1_anode_free": 0.0,
                "state1_ties_not_bounded": ["the sleeve's grip in the Ø15 channel", "ice in the 2 mm gap at the cold edge"],
                "state2_at_air_dry_readings": {"min": round(min(r["s2_read"]), 4), "max": round(max(r["s2_read"]), 4)},
                "state2_cap_rigid_bark": {k: round(v, 4) for k, v in r["cap2"].items()},
                "state3_no_bearing_any_depth_of_102_shift": {b: {"min": round(min(v), 4), "max": round(max(v), 4)} for b, v in r["s3_free"].items()},
                "state3_cap_rigid_bark_of_102_shift": {k: round(v, 4) for k, v in r["cap3"].items()}}

    heat_bark = dict(bark["heat"])
    heat_bark = {"thresholds_102_ppm_K": heat_bark.pop("thresholds_102_ppm_K"),
                 "flange_located_by": "the bark (a Zone-3 fit: block `zone3_fit`)", **heat_bark,
                 "not_in_the_wood_side": "the dead bark's thermal and humidity strain; the frost response and its sign at the tie"}
    result = {
        "script": Path(__file__).name,
        "geometry": {"span_mm": span, "sleeve_area_mm2": round(a_sleeve, 2), "anode_radius_mm": r_anode,
                     "anode_length_mm": l_anode, "channel_radius_mm": r_sleeve, "anode_radial_clearance_mm": gap_radial,
                     "flange_annulus_mm2": round(a_annulus, 1), "bark_mm_78": bark_t, "phloem_mm_78": phloem,
                     "flange_seat_to_install_day_cambium_mm": tie_mm, "shift_span_mm_87": dx_mm,
                     "zone1_shank_in_sleeve": {"length_mm": l_z1, "ti_section_mm2": round(a_z1, 2),
                                               "alpha_bonded_ppm_K": round(alpha_z1 * 1e6, 4)},
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
        "share": shares_block(bark),
        "state2_bearing_N_per_mm": bark["thr2"],
        "state3_tie_depth_mm_no_bearing": bark["dep3"],
        "readings": {"state2": bark["table2"], "state3": bark["table3"]},
        "heat": heat_bark,
        "cte_share_front": bark["front"],
        "seam_on_102_closed_form": bark["seam"],
        "zone3_fit": {
            "premise": "the Zone-3 shank fitted RIGIDLY in the sleeve over its run (01_01 §1: Ø11 under interference; the "
                       "CEM's placeholder diameter and length are read, HW.8.9) — a fit that slips returns the bark reading",
            "shank": {"diameter_mm_cem": d_shank, "length_mm": l_shank, "channel_mm": s55.D_CHANNEL_MM,
                      "ti_section_mm2": round(a_shank, 2), "alloy": ALLOY_BASELINE},
            "sections_mm": {"composite_run": [0.0, l_shank], "peek_gap": [l_shank, span]},
            "stiffness_N_per_mm": {"composite_run": {ld: round(v / l_shank, 1) for ld, v in ea_comp.items()},
                                   "peek_gap": {ld: round(v / (span - l_shank), 1) for ld, v in ea_peek.items()},
                                   "sleeve_whole": {ld: round(1.0 / sleeves["zone3_fit"].comp(0.0, span, ld), 1) for ld in ("sway", "slow")}},
            "alpha_composite_ppm_K": round(alpha_comp * 1e6, 4),
            "composite_vs_102_gap_only_offset_ppm_K": round(comp_offset, 4),
            "cte_free_sleeve_ppm_K": round(z3["cte_free"], 4),
            "share": shares_block(z3),
            "state2_bearing_N_per_mm": z3["thr2"],
            "state3_tie_depth_mm_no_bearing": z3["dep3"],
            "readings": {"state2": z3["table2"], "state3": z3["table3"]},
            "heat": z3["heat"],
            "cte_share_front": z3["front"],
            "seam_on_102_closed_form": z3["seam"],
            "preload_102": "hot_preload.zone3_fit_bonded_shank — `102`'s span with the Zone-3 shank's run bonded (lib.mechanics)",
            "verdict": verdict_z3,
        },
        "controls": {"solver_vs_closed_forms_max_miss": miss, "monotone_worst_step": monos["flange_on_bark"],
                     "monotone_worst_step_zone3_fit": monos["zone3_fit"],
                     "solver_vs_element_chain_max_miss_of_load_scale": fe_miss,
                     "pad_travel_monotone_in_shift_worst_step": pad_worst,
                     "seam_vs_102_grid_max_miss": ctrl_miss},
        "verdict": verdict,
    }
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("\n  " + verdict)
    print("\n  " + verdict_z3)
    print(f"\n  seam (bark): {json.dumps(bark['seam'], ensure_ascii=False)}")
    print(f"  seam (Zone-3 fit): {json.dumps(z3['seam'], ensure_ascii=False)}")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
