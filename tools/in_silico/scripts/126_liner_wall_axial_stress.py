#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""126 — the bus liner's WALL under the axial path: the mean and the amplitude of its stress per bond state of `103` and
per alloy, against PEEK's fatigue readings and against its short-term strength and creep at the warm edge — a FIRST-ORDER
CABINET CHECK (00_07 HW.34, the leg «стінка лайнера під осьовим шляхом — кабінетна перевірка першого порядку»; no solve).

WHY. `102` caps every axial force on the wire at the liner wall's 23 °C yield (53.65 N on 0.5365 mm²) and leaves out
«the wall's creep under a sustained load, its fatigue as an insulator» (its CANNOT 5). The ⚖️ of 2026-11-14 (01_01 §1.4
«Співвісність» ⊕) asked which axis the wall is on — yield, fatigue or creep — and whether a review trigger fires: Ta
chosen · a capture set stronger than the wall · THIS check failing. This script is that check; it adds no mechanics.

CHAIN (in-silico §Critical Rules #15; the bodies are `102`'s, §When Modifying #41). The wire is welded to the anode; the
liner grips it by interference and is held at its TOP by the capture (not designed — `102` takes it as holding, so the
wall sees a force only behind a capture that holds it; a capture of holding force H caps |F| at H, and what it lets slip
becomes the centre pad's travel — `102`'s named consequence). Every axial force the pair carries crosses the liner's tube
at its held end, so the wall's axial stress there is σ = F / A_tube, F the root force of `102`'s closed form.

MODEL. The force per cell is `102`'s own: its `Pair`, its cached grips, its Masing cycle and its clip of a peak past the
23 °C cap, at the shares of `102`'s shift that `103` caches per bond state, on `103`'s two premises (the flange on the
bark ⊥ a rigid Zone-3 fit). The seasonal hot preload is `102`'s too — rebuilt here from `55`'s press-fit rows and `102`'s
spans by `102`'s own forms (control: it reproduces `102`'s cached preload at the capsule edge) so that it can be read at
BOTH warm-edge temperatures `102` carries: the capsule model's edge (`90`, a ceiling for a sleeve inside wood) ⊥ the
cambium under the flange (`79`). The corners are `102`'s (adverse: the tightest part at μ max — the top of `55`'s swept
μ, with no measured member — the upper whisker reversed ± or one-sided; gentle: the nominal part after creep at μ min,
the median one-sided), the preload added on both — on the gentle one OUR addition, built as `102` builds the adverse one.
Per cell: σ_m, σ_a, σ_max, R and the Goodman equivalent fully reversed amplitude σ_ar = σ_a / (1 − σ_m⁺/σ_u), σ_u the
short-term yield at the cell's temperature (23 °C for the sway alone; PEEK 450G's tensile strength is its yield point —
Victrex Figure 1 — so Goodman ≡ Soderberg here). Thresholds in share, by bisection on `102`'s cycle: where the reversed
amplitude reaches each fatigue reading, where the preload plus the reversed amplitude reaches the warm-edge yield; the
retained liner modulus below which the displacement-imposed preload falls under that yield; the cold edge's force.

READINGS (each read in its source on 2026-11-15; ⛔ none is of an extruded 0.15 mm tube — CANNOT 1):
  · The ANCHOR (`59`'s cache, `SUMMARY` §HW.43 «PEEK mechanical-lock barb», 30–48 MPa @ 1e6–1e7): its two sources.
    (i) peekchina.com, «Fatigue Strength of PEEK: A Guide for Gear Engineers», under «1. Flexural/Bending Fatigue
    Strength»: «ARKPEEK-1000: Unfilled PEEK: Endurance Limit: 30–40 MPa at 10⁶–10⁷ cycles (room temperature, dry).»
    — the vendor's own grade; NO R-ratio, specimen, frequency or source is stated (ASTM D7774 is listed elsewhere on the
    page, not tied to the number) — a vendor claim without a DOI (in-silico §Critical Rules #44). A FLEXURAL figure:
    carried to a uniformly loaded wall it is optimistic (a bending specimen has its peak at the outer fibre only).
    (ii) Pastukhov, Kanters, Engels, Govaert 2020, J. Polym. Sci. 58(5), 716–736, doi 10.1002/pol.20190091 (Crossref
    verified, CC BY): the BODY WAS NOT READ — Wiley returned HTTP 403 to every fetch; only the abstract was read, which
    calls the limit «the apparent endurance (fatigue) limit for plasticity‐controlled failure», tied to an evolution of
    the yield stress (stress- and temperature-accelerated physical aging, and strain hardening), with one model for
    «time‐to‐failure under both static and cyclic load». The anchor's 48 (`59`'s «~41–48 MPa @ 1e7») has no page in the
    tree. So the anchor's R is UNKNOWN, and it enters as two named readings: F1 — a fully reversed amplitude (R = −1);
    F2 — a maximum stress at R = 0.1, carried to R = −1 by a Goodman line to the tree's σ_y (our conversion).
  · F3 — Victrex «VICTREX™ PEEK properties brochure» (product guide EN 09-2018), Figure 9 «Tensile fatigue … at 5Hz at
    23°C and 120°C», series «PEEK 450G [23˚C]»; the text: «ISO tensile bars stressed at 5Hz with a sine wave between 10
    and 100% of predefined loads» — R = 0.1, σ_max read off the plot (VICTREX_FIG9), carried to R = −1 by the same
    Goodman line as F2 — the kindest reading.
  · The warm edge's short-term yield — the same brochure, Figure 4 «Tensile strength versus temperature», series «PEEK
    450G» (VICTREX_FIG4), two readings at each warm-edge temperature: its absolute value, and its ratio to its own 23 °C
    value times the tree's σ_y (Figure 1 of the same brochure puts 450G's yield at ≈ 99 MPa, Figure 4 at ≈ 89 at 23 °C —
    the brochure disagrees with itself, so both are carried); the absolute one also at ± its digitisation band.
  · Creep — the same brochure, Figure 7 «Tensile creep of PEEK 450G … at 23°C», ISO 899, 1000 h, 20–60 MPa
    (VICTREX_FIG7). ⛔ NO creep datum AT the warm edge was found in a readable source: the 23 °C strain is a LOWER bound
    on the strain at the warm edge at the same stress (sign: the Arrhenius temperature activation of the yield kinetics,
    Pastukhov abstract), and no plotted curve exists above 60 MPa.
  Figures digitised at 300 dpi on 2026-11-15 (resolution: Figure 4 ±2 MPa, Figure 9 ±1 MPa, Figure 7 ±0.02 %, the line
  widths); vendor «typical» data, not guaranteed values.

CAN: per bond state of `103` (both premises), alloy and corner (the preloaded ones at both warm-edge temperatures), the
wall's σ_m, σ_a, σ_max, R and σ_ar; which axis each cell is on under the adverse and the kind set of readings; the shares
at which fatigue and the warm-edge yield switch on; the holding force below which a capture keeps each fatigue reading off
the wall, and the summer preload it would then let slip; the retained modulus that takes the hot preload under the warm-
edge yield; the cold edge's force on the wall. Controls: the forces at `102`'s grid shares reproduce `102`'s cache to 1e-9
on every corner, alloy and share; the rebuilt preload reproduces `102`'s cached one at the capsule edge on both premises
and grips, and `102`'s thermal rows (its baseline wire, both temperature readings, hot and cold) to their rounding; every
threshold LANDS on its target; the transcriptions are monotone where the physics owes it.
CANNOT: (1) the TUBE — every reading is from moulded bars or an unstated specimen of bulk PEEK; an extruded 0.15 mm wall
may differ in crystallinity, orientation and surface, and nothing here says in which direction; (2) the anchor's R, its
specimen and Pastukhov's numbers (body not read); (3) PEEK's R = −1 strength from a source that states R; (4) creep or
ratcheting at the warm edge, or any time at the edge — the preloaded cells are read as if every cycle sat at the hottest
hour (an adverse reading, its size not computed); (5) the fatigue readings at temperature — F1–F3 are room-temperature
data, used undiminished at the warm edge (optimistic there); (6) the compressive half of the SWAY — symmetric, `102`'s
CANNOT 2 (the cold edge's compression is `102`'s own thermal result, read here); (7) the capture's stress concentration,
its form and strength; (8) plastic strain, ratcheting or shakedown once a yield is reached (flagged, not followed); (9)
the liner's own thermal growth over its run (`102`'s CANNOT 12 — the force there is an upper end); (10) the budget's
1.6–4.7e8 cycles against readings at 1e6–1e7 (`59`'s extrapolation; F3's own curve barely falls from 1e6 to 1e7); (11)
the modulus's fall with temperature, which lowers a displacement-imposed preload — `102` takes E at 23 °C × its relax
floor; (12) the canonical Zone-3 shank (Ø11 under interference, 01_01 §1) — the CEM's placeholder is read, as in `103`.

Run:  conda activate silken_md
      python tools/in_silico/scripts/126_liner_wall_axial_stress.py
"""
from __future__ import annotations

import importlib.util
import itertools
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
    SIGMA_YIELD_PEEK_PA,
)
from lib.mechanics import bonded_fit_section
from lib.utils import banner

SI_DESCRIPTION = ("First-order check of the axial stress in the thin PEEK liner wall of the anchor's bus wire: its mean "
                  "and amplitude per bond state of the anchor in the wood and per wire alloy, from the shear-lag model's "
                  "root force, against PEEK fatigue readings and against its strength and creep at two warm-edge "
                  "temperatures, with the load shares at which each failure axis switches on; no solve")

MECH = CACHE_DIR / "mechanical"
OUT = MECH / "liner_wall_axial_stress.json"

# ── literature, transcribed (READINGS in the docstring) ──────────────────────────────────────────────────────────────
VICTREX_BROCHURE = ("Victrex, «VICTREX™ PEEK properties brochure» (product guide, EN 09-2018), victrex.com "
                    "/-/media/downloads/technical-guides/victrex-product-guide-victrex-peek-properties-en-09-2018.pdf, "
                    "read and digitised at 300 dpi 2026-11-15")
# Figure 4, series «PEEK 450G»: (°C, MPa) along the plotted dots, 23–77 °C (below Tg; the curve bends past ≈ 130 °C)
VICTREX_FIG4 = ((23.0, 89.2), (28.1, 87.1), (46.0, 79.9), (51.1, 77.4), (56.2, 75.4), (61.3, 73.3), (66.5, 71.2),
                (71.6, 69.1), (76.7, 67.1))
VICTREX_FIG4_DIGITISE_MPA = 2.0        # the plotted line's width at 300 dpi
VICTREX_FIG1_YIELD_23C_MPA = 99.0      # Figure 1, «PEEK 450G» stress-strain peak, at ≈ 5.4 % strain (23 °C)
# Figure 9, series «PEEK 450G [23˚C]», R = 0.1, 5 Hz: (cycles, σ_max MPa); the curve's last plotted dot sits at ≈ 10^6.96
VICTREX_FIG9 = ((1e3, 91.7), (1e6, 88.0), (10 ** 6.96, 87.4))
VICTREX_FIG9_R = 0.1
# Figure 7, PEEK 450G at 23 °C (ISO 899): stress MPa → (strain % at the first plotted time ≈ 0.004 h, at ≈ 1000 h)
VICTREX_FIG7 = {20.0: (0.55, 0.62), 30.0: (0.81, 0.94), 40.0: (1.10, 1.28), 50.0: (1.42, 1.74), 60.0: (1.77, 2.29)}
VICTREX_FIG7_HOURS = 1000.0
PEEKCHINA = ("peekchina.com/blog/fatigue-strength-of-peek-a-guide-for-gear-engineers.html, «1. Flexural/Bending Fatigue "
             "Strength»: «ARKPEEK-1000: Unfilled PEEK: Endurance Limit: 30–40 MPa at 10⁶–10⁷ cycles (room temperature, "
             "dry).» — no R-ratio, specimen, frequency or source stated; a flexural figure, optimistic for an axially "
             "loaded wall; read 2026-11-15")
PASTUKHOV = ("Pastukhov, Kanters, Engels, Govaert 2020, J. Polym. Sci. 58(5), 716–736, doi 10.1002/pol.20190091 — body "
             "NOT read (HTTP 403 from Wiley, 2026-11-15); abstract read via Crossref: «the apparent endurance (fatigue) "
             "limit for plasticity‐controlled failure» tied to yield-stress evolution, one model for static and cyclic "
             "time-to-failure; `59`'s «~41–48 MPa @ 1e7» has no page in the tree")
R01_SPLIT = ((1 - VICTREX_FIG9_R) / 2, (1 + VICTREX_FIG9_R) / 2)     # σ_a, σ_m per unit σ_max at R = 0.1

BASE_CORNERS = ("adverse_reversed", "adverse_one_sided", "gentle_one_sided")
HOT_CORNERS = ("adverse_reversed_hot_preload", "adverse_one_sided_hot_preload", "gentle_one_sided_hot_preload")
WARM = {"capsule_edge_90": "capsule_model_edges_90", "cambium_under_flange_79": "cambium_under_flange_79"}   # → `102`'s key


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module          # 55 and 86 (through 102) declare dataclasses, which look their module up here
    spec.loader.exec_module(module)
    return module


s102 = _load("liner102", "102_wire_liner_shear_lag.py")   # its Pair — the force on its own closed form
s55 = s102.s55


def interp(rows, x: float) -> float:
    for (x0, y0), (x1, y1) in itertools.pairwise(rows):
        if x0 <= x <= x1:
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)
    raise ValueError(f"{x} outside the transcribed range {rows[0][0]}–{rows[-1][0]}")


def bisect_up(fn, lo: float, hi: float, n: int = 100) -> float:
    """The root of an increasing fn on [lo, hi], fn(lo) < 0 ≤ fn(hi)."""
    for _ in range(n):
        mid = 0.5 * (lo + hi)
        lo, hi = (mid, hi) if fn(mid) < 0 else (lo, mid)
    return 0.5 * (lo + hi)


def down_n(x: float, n: int) -> float:
    """A «below X» limit at n decimals rounds DOWN, so the sentence stays true (in-silico §When Modifying #43)."""
    return math.floor(round(x * 10 ** n, 9)) / 10 ** n


def goodman(s_a: float, s_m: float, s_u: float) -> float:
    """The fully reversed amplitude equivalent to (σ_a, σ_m) on the Goodman line to σ_u; inf once σ_m reaches σ_u."""
    m = max(s_m, 0.0)
    return math.inf if m >= s_u else s_a / (1.0 - m / s_u)


def main() -> int:
    banner("126 — the bus liner's wall under the axial path: stress per bond state against fatigue, yield and creep")
    d102 = json.loads((MECH / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    d103 = json.loads((MECH / "anchor_wood_share.json").read_text(encoding="utf-8"))
    d55 = json.loads((MECH / "bus_mechanical.json").read_text(encoding="utf-8"))
    d59 = json.loads((MECH / "contact_endurance_check.json").read_text(encoding="utf-8"))["parts"]["peek_barb_cyclic"]
    d77 = json.loads((MECH / "anchor_torque_path.json").read_text(encoding="utf-8"))["geometry"]

    geo = d102["geometry"]
    win = d55["interference_window"]
    cp = win["cold_press_fit"]
    area = cp["tube_section_mm2"]
    s_y23 = cp["peek_yield_MPa"]
    if s_y23 != SIGMA_YIELD_PEEK_PA / 1e6 or abs(s_y23 * area - geo["wall_cap_N_23C"]) > 1e-9:
        raise RuntimeError("control: the wall's 23 °C cap is not σ_y·A of `55`'s tube on the lib's σ_y")
    shift_hi = max(d102["sway_input"]["shift_um_87"]["upper_whisker"]) * 1e-3
    shift_lo = min(d102["sway_input"]["shift_um_87"]["median"]) * 1e-3
    mu = cp["mu_sweep"]
    grips = d102["grip"]["by_part_N_per_mm_at_20C"]["window_ceiling"]
    q_adv = grips[max(grips, key=float)]
    temps102 = d102["thermal"]["temperatures_c"]
    t_warm = {k: temps102[v][1] for k, v in WARM.items()}
    t_cold = {k: temps102[v][0] for k, v in WARM.items()}
    t_ref = d102["thermal"]["assembly_c"]

    # ── the warm edge's short-term yield per temperature, two readings (Figure 4 absolute ⊥ its ratio on the tree's σ_y) ──
    f4_23 = interp(VICTREX_FIG4, 23.0)
    y_warm = {tk: {"fig4_absolute": interp(VICTREX_FIG4, t), "fig4_ratio_on_tree_yield": interp(VICTREX_FIG4, t) / f4_23 * s_y23}
              for tk, t in t_warm.items()}
    side_of = {"adverse": "fig4_absolute", "kind": "fig4_ratio_on_tree_yield"}
    if any(y["fig4_absolute"] >= y["fig4_ratio_on_tree_yield"] for y in y_warm.values()):
        raise RuntimeError("control: the absolute Figure-4 reading is expected the lower — the sides would swap")

    # ── fatigue readings as a fully reversed limit amplitude (MPa) ──
    anchor = d59["endurance_limit_MPa"]
    f3_smax = VICTREX_FIG9[-1][1]
    fat = {"F1_anchor_as_reversed_amplitude_low": anchor[0], "F1_anchor_as_reversed_amplitude_high": anchor[1],
           "F2_anchor_as_max_stress_at_R0.1_low": goodman(R01_SPLIT[0] * anchor[0], R01_SPLIT[1] * anchor[0], s_y23),
           "F2_anchor_as_max_stress_at_R0.1_high": goodman(R01_SPLIT[0] * anchor[1], R01_SPLIT[1] * anchor[1], s_y23),
           "F3_victrex_450G_R0.1_to_reversed": goodman(R01_SPLIT[0] * f3_smax, R01_SPLIT[1] * f3_smax, s_y23)}
    fat_adv, fat_kind = min(fat, key=fat.get), max(fat, key=fat.get)

    # ── the hot preload, rebuilt from `55`'s rows and the lib by `102`'s forms (its q_of and spans), at any temperature ──
    rows55 = {r["at"]: r for r in cp["rows"]}
    a_run, l_run = geo["bare_run_mm"], geo["liner_run_mm"]
    dalpha_r = (ALPHA_PEEK_1K - ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]) * s55.D_BUS / 2.0 * 1e3

    def q_at(part: str, m: float, relaxed: bool, t: float) -> float:
        i20 = rows55[part]["interference_radial_um"]
        i = max(0.0, i20 - dalpha_r * (t - win["thermal"]["t_ref_c"]))
        return rows55[part]["by_mu"][f"{m:g}"]["friction_N"] / l_run * (i / i20) * (PEEK_RELAX_FLOOR if relaxed else 1.0)

    alpha_fl = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    e_peek = E_PEEK_PA / 1e6
    a_sleeve = math.pi * ((d77["sleeve_outer_radius_m"] * 1e3) ** 2 - (d77["shank_radius_m"] * 1e3) ** 2)
    a_shank3 = math.pi / 4.0 * (s55.cem("cathode_flange")["shank_diameter_mm"] ** 2 - s55.D_CHANNEL_MM ** 2)
    _, alpha_shank3 = bonded_fit_section(ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3, alpha_fl, a_shank3, e_peek,
                                         ALPHA_PEEK_1K, a_sleeve, PEEK_RELAX_FLOOR)
    peek32, ti32 = d102["thermal"]["spans_mm_peek_ti"]["gap_and_shank_disc_on_sleeve_top"]

    def d_th(alloy: str, premise: str, t: float) -> float:
        aw = ALLOY_PROPERTIES[alloy]["alpha_1K"]
        if premise == "flange_on_bark":
            per_k = ALPHA_PEEK_1K * peek32 + alpha_fl * ti32 - aw * (a_run + l_run)
        else:
            per_k = (ALPHA_PEEK_1K * s55.PEEK_GAP_MM + alpha_shank3 * s55.SHANK_LEN_MM + alpha_fl * s55.FLANGE_THK_MM
                     - aw * (a_run + l_run))
        return per_k * (t - t_ref)

    def preload_at(alloy: str, premise: str, grip: str, t: float, retained: float = PEEK_RELAX_FLOOR) -> tuple[float, bool]:
        q = q_at("window_ceiling", max(mu), False, t) if grip == "adverse" else q_at("ratified_nominal", min(mu), True, t)
        ea_w = ALLOY_PROPERTIES[alloy]["E_GPa"] * 1e3 * geo["wire_area_mm2"]
        f, _, capped = s102.Pair(q, ea_w, geo["liner_EA_N"] * retained, a_run, l_run, geo["wall_cap_N_23C"]).virgin(d_th(alloy, premise, t))
        return f, capped

    # control: `102`'s cached preload at the capsule edge, every alloy, premise and grip (both unrounded)
    pre_miss = 0.0
    for al, row in d102["seam_by_alloy"].items():
        for pm in ("flange_on_bark", "zone3_fit"):
            src = row["hot_preload"] if pm == "flange_on_bark" else row["hot_preload"]["zone3_fit_bonded_shank"]
            for gr, key in (("adverse", "F_N_relaxed_liner"), ("gentle", "F_N_gentle_nominal_relaxed_mu_low")):
                pre_miss = max(pre_miss, abs(preload_at(al, pm, gr, t_warm["capsule_edge_90"])[0] - src[key]))
    if pre_miss > 1e-9:
        raise RuntimeError(f"control: the rebuilt hot preload misses `102`'s cache by {pre_miss}")
    # control: `102`'s thermal rows (its baseline wire on the bark span), hot and cold, both temperature readings, to their
    # 0.01 N rounding — the rebuild at a temperature other than the capsule edge is `102`'s form there too
    th_miss = 0.0
    for tk, k102 in WARM.items():
        for gr, part in (("adverse", f"window_ceiling__mu{max(mu):g}"), ("gentle", f"ratified_nominal_relaxed__mu{min(mu):g}")):
            r = d102["thermal"]["by_reading"][f"gap_and_shank_disc_on_sleeve_top__{k102}__{part}"]
            th_miss = max(th_miss, abs(preload_at(ALLOY_BASELINE, "flange_on_bark", gr, t_warm[tk])[0] - r["hot"]["root_F_N"]),
                          abs(preload_at(ALLOY_BASELINE, "flange_on_bark", gr, t_cold[tk])[0] - r["cold"]["root_F_N"]))
    if th_miss > 0.005 + 1e-9:
        raise RuntimeError(f"control: the rebuild misses `102`'s thermal rows by {th_miss} N")

    pre = {(al, pm, gr, tk): preload_at(al, pm, gr, t)[0] for al in d102["seam_by_alloy"] for pm in ("flange_on_bark", "zone3_fit")
           for gr in ("adverse", "gentle") for tk, t in t_warm.items()}

    # ── forces: `102`'s Pair on its cached inputs, the preload added and clipped as `102` adds and clips it ──
    def pair(alloy: str, grip: str):
        ea_w = ALLOY_PROPERTIES[alloy]["E_GPa"] * 1e3 * geo["wire_area_mm2"]
        q = q_adv if grip == "adverse" else d102["seam_by_alloy"][alloy]["gentle_grip_N_per_mm"]
        return s102.Pair(q, ea_w, geo["liner_EA_N"], a_run, l_run, geo["wall_cap_N_23C"])

    def forces(alloy: str, sh: float, corner: str, premise: str = "flange_on_bark", temp: str | None = None) -> dict:
        grip = corner.split("_")[0]
        pr = pair(alloy, grip)
        if corner.startswith("adverse_reversed"):
            c = pr.cycle(sh * shift_hi, 0.0)
        elif grip == "adverse":
            c = pr.cycle(sh * shift_hi / 2.0, sh * shift_hi / 2.0)
        else:
            c = pr.cycle(sh * shift_lo / 2.0, sh * shift_lo / 2.0)
        f_amp, f_mean, clipped = c["F_amp"], c["F_mean"], False
        if corner.endswith("_hot_preload"):
            f_mean += pre[(alloy, premise, grip, temp)]
        demand = f_mean + f_amp
        if corner.endswith("_hot_preload") and demand > pr.cap + 1e-9:
            f_mean, clipped = pr.cap - f_amp, True
        return {"F_amp": f_amp, "F_mean": f_mean, "F_peak_demand": demand, "capped": c["capped"], "clipped": clipped}

    # control: at `102`'s grid shares the forces are `102`'s cache, every corner, alloy and share (both unrounded)
    to102 = {"adverse_reversed": "sway_reversed", "adverse_one_sided": "sway_one_sided",
             "adverse_reversed_hot_preload": "sway_reversed_hot_preload",
             "adverse_one_sided_hot_preload": "sway_one_sided_hot_preload"}
    miss, compared = 0.0, 0
    for alloy, row in d102["seam_by_alloy"].items():
        for sh, g in row["by_share"].items():
            for mine, theirs in to102.items():
                f = forces(alloy, float(sh), mine, temp="capsule_edge_90")
                miss = max(miss, abs(f["F_amp"] - g["adverse"][theirs]["F_amp_N"]), abs(f["F_mean"] - g["adverse"][theirs]["F_mean_N"]))
                compared += 1
            f = forces(alloy, float(sh), "gentle_one_sided")
            miss = max(miss, abs(f["F_amp"] - g["gentle_one_sided"]["F_amp_N"]), abs(f["F_mean"] - g["gentle_one_sided"]["F_mean_N"]))
            compared += 1
    expected = sum(len(r["by_share"]) for r in d102["seam_by_alloy"].values()) * 5
    if miss > 1e-9 or compared != expected:
        raise RuntimeError(f"control: the forces miss `102`'s grid by {miss} over {compared} of {expected} cells")

    # ── the states: `103`'s shares of `102`'s shift ──
    def states_of(block: dict) -> dict:
        s3 = block["state3_no_bearing_any_depth_of_102_shift"]
        return {"state1_anode_free": block["state1_anode_free"],
                "state2_air_dry_readings_max": block["state2_at_air_dry_readings"]["max"],
                "state2_cap_rigid_bark_bond_soft": block["state2_cap_rigid_bark"]["anode_bond_soft"],
                "state2_cap_rigid_bark_bond_stiff": block["state2_cap_rigid_bark"]["anode_bond_stiff"],
                "state3_no_bearing_bond_soft_max": s3["anode_bond_soft"]["max"],
                "state3_no_bearing_bond_stiff_min": s3["anode_bond_stiff"]["min"],
                "state3_no_bearing_bond_stiff_max": s3["anode_bond_stiff"]["max"],
                "state3_cap_rigid_bark_bond_soft": block["state3_cap_rigid_bark_of_102_shift"]["anode_bond_soft"],
                "state3_cap_rigid_bark_bond_stiff": block["state3_cap_rigid_bark_of_102_shift"]["anode_bond_stiff"]}

    premises = {"flange_on_bark": states_of(d103["share"]), "zone3_fit": states_of(d103["zone3_fit"]["share"])}
    alloys = list(d102["seam_by_alloy"])

    def cell(alloy: str, sh: float, corner: str, premise: str, temp: str | None) -> dict:
        f = forces(alloy, sh, corner, premise, temp)
        s_m, s_a = f["F_mean"] / area, f["F_amp"] / area
        s_max, s_min = s_m + s_a, s_m - s_a
        at_cap = f["capped"] or f["clipped"]
        s_u = {side: (y_warm[temp][rd] if temp else s_y23) for side, rd in side_of.items()}
        sar = {k: goodman(s_a, s_m, v) for k, v in s_u.items()}

        def axis(side: str) -> str:
            lim = fat[fat_adv] if side == "adverse" else fat[fat_kind]
            if at_cap:
                return "yield_23C_cap"
            if temp and s_max >= s_u[side]:
                return "yield_warm_edge"
            if sar[side] > lim:
                return "fatigue"
            return "clear_on_read_data"
        return {"share": sh, "sigma_mean_MPa": s_m, "sigma_amp_MPa": s_a, "sigma_max_MPa": s_max, "sigma_min_MPa": s_min,
                "R": s_min / s_max if s_max > 0 else None, "sigma_peak_demand_MPa": f["F_peak_demand"] / area,
                "wall_at_23C_cap": at_cap,
                "goodman_reversed_equivalent_MPa": {k: (None if math.isinf(v) else v) for k, v in sar.items()},
                "axis_adverse_readings": axis("adverse"), "axis_kind_readings": axis("kind")}

    corner_keys = [(c, None) for c in BASE_CORNERS] + [(c, tk) for c in HOT_CORNERS for tk in WARM]
    table = {pm: {st: {al: {(c if tk is None else f"{c}@{tk}"): cell(al, sh, c, pm, tk) for c, tk in corner_keys}
                       for al in alloys} for st, sh in sts.items()} for pm, sts in premises.items()}

    # ── thresholds in share ──
    def amp_rev(alloy: str, sh: float) -> float:
        return forces(alloy, sh, "adverse_reversed")["F_amp"] / area

    thresholds = {}
    for alloy, row in d102["seam_by_alloy"].items():
        cap_amp = amp_rev(alloy, 1.0)
        fat_sh = {k: (None if v >= cap_amp else bisect_up(lambda s, v=v, al=alloy: amp_rev(al, s) - v, 0.0, 1.0))
                  for k, v in fat.items()}
        warm = {}
        for tk in WARM:
            for pm in premises:
                for gr, corner in (("adverse", "adverse_reversed_hot_preload"), ("gentle", "gentle_one_sided_hot_preload")):
                    for rd, sy in y_warm[tk].items():
                        def over(s, c=(alloy, corner, pm, tk), sy=sy):
                            return forces(c[0], s, c[1], c[2], c[3])["F_peak_demand"] / area - sy
                        warm[f"{tk}__{pm}__{gr}__{rd}"] = (0.0 if over(0.0) >= 0 else
                                                           (bisect_up(over, 0.0, 1.0) if over(1.0) >= 0 else None))
        thresholds[alloy] = {"fatigue_share_reversed": fat_sh, "yield_23C_share_102": row["adverse_share_at_wall_cap_exact"],
                             "warm_edge_yield_share": warm}

    land = 0.0
    for alloy, t in thresholds.items():
        for k, s in t["fatigue_share_reversed"].items():
            if s is not None:
                land = max(land, abs(amp_rev(alloy, s) - fat[k]))
        for key, s in t["warm_edge_yield_share"].items():
            tk, pm, gr, rd = key.split("__")
            corner = "adverse_reversed_hot_preload" if gr == "adverse" else "gentle_one_sided_hot_preload"
            if s is not None and s > 0:
                land = max(land, abs(forces(alloy, s, corner, pm, tk)["F_peak_demand"] / area - y_warm[tk][rd]))
    if land > 1e-6:
        raise RuntimeError(f"control: a threshold misses its target by {land} MPa")

    # ── the warm edge: the preload alone (share 0), against the short-term yield and the 23 °C creep curves; the lever ──
    def creep_floor(s: float):
        """A LOWER bound on the 1000 h strain at the warm edge at stress s: the 23 °C curve of the largest plotted stress
        not above s (creep rises with the stress and with the temperature); None below the lowest curve. No upper bound."""
        below = [k for k in sorted(VICTREX_FIG7) if k <= s]
        return None if not below else {"plotted_stress_MPa": below[-1], "strain_pct_at_1000h_23C": VICTREX_FIG7[below[-1]][1]}

    e_creep_top = max(VICTREX_FIG7) / (VICTREX_FIG7[max(VICTREX_FIG7)][1] / 100.0) / e_peek
    band = VICTREX_FIG4_DIGITISE_MPA
    warm_edge = {}
    for (alloy, pm, gr, tk), f_pre in pre.items():
        s_pre = f_pre / area
        f_full, cap_full = preload_at(alloy, pm, gr, t_warm[tk], 1.0)
        lever = {}
        for rd, sy in y_warm[tk].items():
            target = sy * area
            if f_pre < target:
                lever[rd] = "below already at the relax floor"
            elif preload_at(alloy, pm, gr, t_warm[tk], 1e-6)[0] >= target:
                lever[rd] = 0.0
            else:
                lever[rd] = bisect_up(lambda f, target=target, k=(alloy, pm, gr, t_warm[tk]): preload_at(*k, f)[0] - target,
                                      1e-6, PEEK_RELAX_FLOOR)
        y4 = y_warm[tk]["fig4_absolute"]
        warm_edge[f"{alloy}__{pm}__{gr}__{tk}"] = {
            "t_C": t_warm[tk], "F_preload_N": f_pre, "sigma_preload_MPa": s_pre, "share_of_23C_yield": s_pre / s_y23,
            "share_of_warm_edge_yield": {rd: s_pre / sy for rd, sy in y_warm[tk].items()},
            "reaches_warm_edge_yield": {rd: s_pre >= sy for rd, sy in y_warm[tk].items()},
            "reaches_fig4_band": {"minus": s_pre >= y4 - band, "plus": s_pre >= y4 + band},
            "creep_23C_lower_bound": creep_floor(s_pre),
            "sigma_preload_unrelaxed_liner_MPa": f_full / area, "unrelaxed_capped_at_23C_yield": cap_full,
            "retained_modulus_below_which_it_falls_under_warm_edge_yield": lever}

    # ── the cold edge: `102`'s own thermal result on the wall, every alloy (the sway's symmetric half is another matter) ──
    cold = {}
    for alloy in alloys:
        for pm in premises:
            for gr in ("adverse", "gentle"):
                for tk, t in t_cold.items():
                    f, capped = preload_at(alloy, pm, gr, t)
                    cold[f"{alloy}__{pm}__{gr}__{tk}"] = {"t_C": t, "F_N": f, "sigma_MPa": f / area, "at_23C_cap": capped}

    # ── the capture: ONE holding force H caps |F|; below each fatigue reading's force it keeps that reading off the wall ──
    pre_groups = {f"{pm}__{gr}__{tk}": [pre[(al, pm, gr, tk)] for al in alloys]
                  for pm in premises for gr in ("adverse", "gentle") for tk in WARM}
    h_lim = {k: v * area for k, v in fat.items()}
    capture = {"holding_force_below_N": h_lim,
               "warm_edge_yield_force_N": {tk: {rd: sy * area for rd, sy in y.items()} for tk, y in y_warm.items()},
               "wall_23C_yield_N": geo["wall_cap_N_23C"],
               "summer_preload_N_range": {k: [min(v), max(v)] for k, v in pre_groups.items()},
               "preload_groups_slipping_under_adverse_H": sorted(k for k, v in pre_groups.items() if min(v) > h_lim[fat_adv]),
               "reading": "a capture of holding force H caps |F| at H: the wall's amplitude cannot pass H/A, nor its peak; "
                          "whatever force passes H slips — a summer preload above H slips every summer, and the slip is the "
                          "centre pad's travel (`102`)"}

    # ── verdict, built from the numbers ──
    ti, ta, tb = thresholds[ALLOY_BASELINE], thresholds["Ta"], thresholds["beta-Ti-13Nb-13Zr"]
    f1l, f1h = "F1_anchor_as_reversed_amplitude_low", "F1_anchor_as_reversed_amplitude_high"
    f2l, f2h, f3 = "F2_anchor_as_max_stress_at_R0.1_low", "F2_anchor_as_max_stress_at_R0.1_high", "F3_victrex_450G_R0.1_to_reversed"
    order = (f2l, f1l, f2h, f1h, f3)
    n_first = sum(all(s is not None and s < t["yield_23C_share_102"] for s in t["fatigue_share_reversed"].values())
                  for t in thresholds.values())

    def fs(t: dict, k: str) -> str:
        s = t["fatigue_share_reversed"][k]
        return "never" if s is None else f"{down_n(s, 2):.2f}"
    lines = [
        f"Sway on the adverse corner (`102`'s reversed upper whisker, R = −1): the wall's amplitude stays clear of the fatigue "
        f"readings ({' · '.join(f'{fat[k]:.1f}' for k in order)} MPa reversed-equivalent: F2 low · F1 low · F2 high · F1 high · "
        f"F3) only below share {' · '.join(fs(ti, k) for k in order)} on {ALLOY_BASELINE} ({' · '.join(fs(ta, k) for k in order)} "
        f"on Ta, {' · '.join(fs(tb, k) for k in order)} on beta-Ti-13Nb-13Zr) — against 23 °C yield from "
        f"{ti['yield_23C_share_102']:.4f}, {ta['yield_23C_share_102']:.4f} and {tb['yield_23C_share_102']:.4f}: on {n_first} of "
        f"{len(alloys)} alloys every fatigue reading switches on before the yield."]
    reach = {pm: [st for st in sts if any(table[pm][st][al]["adverse_reversed"]["axis_kind_readings"] != "clear_on_read_data"
                                          for al in alloys)] for pm, sts in premises.items()}
    clear = {pm: [st for st in sts if all(table[pm][st][al]["adverse_reversed"]["axis_adverse_readings"] == "clear_on_read_data"
                                          for al in alloys)] for pm, sts in premises.items()}
    for pm, name in (("flange_on_bark", "the flange on the bark"), ("zone3_fit", "a Zone-3 fit")):
        lines.append(f"By `103`'s states, the sway alone on the adverse reversed corner, {name}: past fatigue or yield on some "
                     f"alloy even on the kindest reading — {', '.join(reach[pm]) or 'none'}; clear on every alloy even on the "
                     f"adverse one — {', '.join(clear[pm]) or 'none'}.")
    lines.append(f"Tension–tension: the one reading with a stated R (450G, 23 °C, R {VICTREX_FIG9_R:g}) holds {f3_smax:.1f} MPa "
                 f"σ_max at ≈ 1e7 — {f3_smax / s_y23:.2f} of the tree's yield and ×{f3_smax / y_warm['capsule_edge_90']['fig4_absolute']:.2f} "
                 f"(capsule edge) ⊥ ×{f3_smax / y_warm['cambium_under_flange_79']['fig4_absolute']:.2f} (cambium) the warm-edge "
                 f"short-term yield, so where R ≥ {VICTREX_FIG9_R:g} PEEK's fatigue is bounded by its yield.")

    def count(tk: str, pm: str, key: str, sub: str | None = None) -> int:
        blk = "reaches_warm_edge_yield" if sub is None else "reaches_fig4_band"
        return sum(warm_edge[f"{al}__{pm}__adverse__{tk}"][blk][key if sub is None else sub] for al in alloys)

    def span(lo: int, hi: int) -> str:
        return f"{lo}" if lo == hi else f"{lo}–{hi}"

    for tk, name in (("capsule_edge_90", "the capsule edge"), ("cambium_under_flange_79", "the cambium under the flange")):
        rng = {pm: (min(warm_edge[f"{al}__{pm}__adverse__{tk}"]["sigma_preload_MPa"] for al in alloys),
                    max(warm_edge[f"{al}__{pm}__adverse__{tk}"]["sigma_preload_MPa"] for al in alloys)) for pm in premises}
        y = y_warm[tk]
        lines.append(
            f"Warm edge at {name} ({t_warm[tk]:.1f} °C), the preload alone at share 0 on the adverse grip: "
            f"{rng['flange_on_bark'][0]:.1f}–{rng['flange_on_bark'][1]:.1f} MPa with the flange on the bark, "
            f"{rng['zone3_fit'][0]:.1f}–{rng['zone3_fit'][1]:.1f} on a Zone-3 fit, against 450G's short-term yield there of "
            f"{y['fig4_absolute']:.1f} (Figure 4, ±{band:g} digitised) ⊥ {y['fig4_ratio_on_tree_yield']:.1f} MPa (its ratio on the "
            f"tree's {s_y23:g}) — reached on the bark on "
            f"{span(count(tk, 'flange_on_bark', 'fig4_absolute', 'plus'), count(tk, 'flange_on_bark', 'fig4_absolute', 'minus'))} "
            f"of {len(alloys)} alloys across Figure 4's band and on "
            f"{count(tk, 'flange_on_bark', 'fig4_ratio_on_tree_yield')} on the ratio reading, on a Zone-3 fit on "
            f"{count(tk, 'zone3_fit', 'fig4_absolute', 'minus')} even at the band's low end.")
    lev = {al: warm_edge[f"{al}__flange_on_bark__adverse__capsule_edge_90"]["retained_modulus_below_which_it_falls_under_warm_edge_yield"]
           ["fig4_absolute"] for al in alloys}
    lev_num = {al: v for al, v in lev.items() if isinstance(v, float)}
    lev_ti = lev[ALLOY_BASELINE]
    lines.append(
        f"The preload is imposed by a DISPLACEMENT (the sleeve's growth over the wire), so it is self-limiting and creep relaxes "
        f"it: at the capsule edge on the bark, of the {len(lev_num)} alloys whose preload reaches Figure 4's short-term yield at "
        f"`102`'s relax floor {PEEK_RELAX_FLOOR:g}, it falls under it once the liner keeps less than "
        f"{down_n(min(lev_num.values()), 3):.3f}–{down_n(max(lev_num.values()), 3):.3f} of its modulus ({ALLOY_BASELINE} "
        f"{lev_ti if isinstance(lev_ti, str) else format(down_n(lev_ti, 3), '.3f')}) — and 450G's own 23 °C curve at "
        f"{max(VICTREX_FIG7):g} MPa already sits at {e_creep_top:.3f} of the tree's E after {VICTREX_FIG7_HOURS:g} h. Creep and "
        f"ratcheting are not assessed.")
    floors = {gr: [warm_edge[f"{al}__{pm}__{gr}__capsule_edge_90"]["creep_23C_lower_bound"] for al in alloys for pm in premises]
              for gr in ("adverse", "gentle")}
    above_top = {pm: sum(warm_edge[f"{al}__{pm}__adverse__capsule_edge_90"]["sigma_preload_MPa"] > max(VICTREX_FIG7) for al in alloys)
                 for pm in premises}
    gentle_lb = [c["strain_pct_at_1000h_23C"] for c in floors["gentle"] if c]
    lines.append(
        f"Creep: no datum at the warm edge was read. 450G's 23 °C curves (ISO 899, {VICTREX_FIG7_HOURS:g} h, "
        f"{min(VICTREX_FIG7):g}–{max(VICTREX_FIG7):g} MPa) are a LOWER bound there: at the capsule edge the adverse-grip preload "
        f"lies above the top curve on {above_top['flange_on_bark']} of {len(alloys)} alloys on the bark and "
        f"{above_top['zone3_fit']} on a Zone-3 fit (at least {VICTREX_FIG7[max(VICTREX_FIG7)][1]:.2f} % in {VICTREX_FIG7_HOURS:g} h, "
        f"no upper bound); the gentle-grip preload "
        f"{'at least ' + format(min(gentle_lb), '.2f') + ' % where a curve lies below it' if gentle_lb else 'below every curve'}"
        f" ({sum(c is None for c in floors['gentle'])} of {len(floors['gentle'])} gentle cells below the lowest curve, no bound).")
    adv_bark = capture["summer_preload_N_range"]["flange_on_bark__adverse__capsule_edge_90"]
    lines.append(
        f"The capture caps |F| with ONE holding force H: it keeps the fatigue readings off the wall only while H < "
        f"{down_n(h_lim[fat_adv], 1):.1f} N (F2 low) … {down_n(h_lim[fat_kind], 1):.1f} N (F3); below the first, every summer "
        f"preload group slips ({len(capture['preload_groups_slipping_under_adverse_H'])} of {len(pre_groups)} — on the bark at the "
        f"capsule edge {adv_bark[0]:.1f}–{adv_bark[1]:.1f} N), and the slip is the centre pad's travel.")
    past48 = sorted((premises[pm][st], pm, st, table[pm][st][ALLOY_BASELINE]["adverse_reversed"]["sigma_amp_MPa"])
                     for pm in premises for st in premises[pm]
                     if table[pm][st][ALLOY_BASELINE]["adverse_reversed"]["sigma_amp_MPa"] > fat[f1h])
    past_f3 = [s for s, _, _, s_a in past48 if s_a > fat[f3]]
    ex = past48[0]
    lines.append(
        f"The fatigue leg as the trigger's ground: on {ALLOY_BASELINE} the reversed sway passes the anchor's {fat[f1h]:g} MPa in "
        f"{len(past48)} of {sum(len(v) for v in premises.values())} state cells of `103` (both premises) — the least share "
        f"{ex[0]:.4f} ({ex[2]}, {ex[1]}) → {ex[3]:.1f} MPa — and F3's {fat[f3]:.1f} only from share {min(past_f3):.4f}.")
    cold_bark = [cold[f"{al}__flange_on_bark__adverse__{tk}"] for al in alloys for tk in WARM]
    cold_z3 = [cold[f"{al}__zone3_fit__adverse__{tk}"]["sigma_MPa"] for al in alloys for tk in WARM]
    lines.append(
        f"Cold edge (`102`'s thermal result, adverse grip): on the bark the wall reaches its 23 °C limit in compression on "
        f"{sum(c['at_23C_cap'] for c in cold_bark)} of {len(cold_bark)} alloy × temperature cells; on a Zone-3 fit "
        f"{min(cold_z3):.1f} … {max(cold_z3):.1f} MPa — a seasonal swing of the wall from the warm-edge preload to that, "
        f"not the sway's symmetric half.")

    result = {
        "script": Path(__file__).name,
        "question": "00_07 HW.34 — the liner wall under the axial path: which axis (yield · fatigue · creep), first-order",
        "inputs": {"tube_section_mm2": area, "sigma_y_23C_MPa": s_y23, "wall_cap_N_23C": geo["wall_cap_N_23C"],
                   "t_warm_C_102": t_warm, "t_cold_C_102": t_cold, "mu_sweep_55": mu,
                   "shift_um_102": {"upper_whisker_high": shift_hi * 1e3, "median_low": shift_lo * 1e3},
                   "anchor_MPa_59": anchor, "anchor_cycles_59": d59["tested_range_cycles"],
                   "budget_cycles_62": d59["budget_cycles"], "source": "102 · 103 · 55 · 59 · 77 caches; 102's Pair"},
        "readings": {
            "anchor_sources": {"peekchina": PEEKCHINA, "pastukhov_2020": PASTUKHOV,
                               "R_ratio": "not stated in the one source read; the other's body not read",
                               "specimen": "not stated (peekchina: flexural); bulk PEEK either way — not an extruded 0.15 mm tube"},
            "fatigue_reversed_limit_MPa": fat,
            "fatigue_adverse_reading": fat_adv, "fatigue_kind_reading": fat_kind,
            "victrex": {"document": VICTREX_BROCHURE, "fig9_450G_23C_R01_cycles_max_stress": [list(r) for r in VICTREX_FIG9],
                        "fig9_R": VICTREX_FIG9_R, "fig4_450G_C_MPa": [list(r) for r in VICTREX_FIG4],
                        "fig4_digitise_MPa": VICTREX_FIG4_DIGITISE_MPA, "fig1_450G_yield_23C_MPa": VICTREX_FIG1_YIELD_23C_MPA,
                        "fig7_450G_23C_creep_strain_pct_first_and_1000h": {f"{k:g}": list(v) for k, v in VICTREX_FIG7.items()}},
            "warm_edge_yield_MPa": y_warm,
            "fig9_max_stress_over_yields": {"tree_23C": f3_smax / s_y23, "fig4_23C": f3_smax / f4_23,
                                            **{f"fig4_{tk}": f3_smax / y["fig4_absolute"] for tk, y in y_warm.items()}},
            "fig7_top_curve_1000h_secant_over_tree_E": e_creep_top,
        },
        "states_share_of_102_shift": premises,
        "cells": table,
        "thresholds": thresholds,
        "warm_edge_preload": warm_edge,
        "cold_edge": cold,
        "capture": capture,
        "controls": {"forces_vs_102_grid_max_miss_N": miss, "forces_vs_102_grid_cells": compared,
                     "preload_rebuilt_vs_102_max_miss_N": pre_miss, "preload_rebuilt_vs_102_thermal_rows_max_miss_N": th_miss,
                     "threshold_landing_max_miss_MPa": land},
        "not_modelled": ["the extruded 0.15 mm tube itself (every reading is bulk PEEK)", "the anchor's R-ratio and specimen",
                         "creep and ratcheting at the warm edge, and the time at it (preloaded cells read as if always at the "
                         "hottest hour)", "fatigue readings at temperature (room-temperature data used undiminished)",
                         "the sway's compressive half (symmetric, 102)", "the capture's stress concentration and strength",
                         "plastic strain, ratcheting or shakedown past a yield", "the liner's own thermal growth (102 CANNOT 12)",
                         "the modulus's fall with temperature", "cycles beyond 1e7", "the canonical Zone-3 shank (CEM placeholder)"],
        "verdict": " ".join(lines),
    }
    # the transcriptions: what the physics owes them
    if any(b[1] >= a[1] for a, b in itertools.pairwise(VICTREX_FIG4)):
        raise RuntimeError("control: Figure 4 must fall with temperature")
    if any(b[1] > a[1] for a, b in itertools.pairwise(VICTREX_FIG9)):
        raise RuntimeError("control: Figure 9 must not rise with cycles")
    st = sorted(VICTREX_FIG7)
    if any(VICTREX_FIG7[b][i] <= VICTREX_FIG7[a][i] for a, b in itertools.pairwise(st) for i in (0, 1)) or \
            any(v[1] <= v[0] for v in VICTREX_FIG7.values()):
        raise RuntimeError("control: Figure 7 must rise with stress and with time")
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("\n  " + "\n  ".join(lines))
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
