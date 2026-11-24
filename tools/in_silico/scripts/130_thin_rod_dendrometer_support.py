#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""130 — a thin rod in the stem as the point dendrometer's support, in place of the anchor: its thermal artefact in the
wood and above the bark, on the live-bark datum and on `114`'s, against the commercial frames' 0.3 µm/K (00_07 HW.54,
the leg «ролі деталей анкера без комірки»; 00_07 DOC-T.131, the leg «конструкція анкера без комірки», which waited for
exactly this count — «рахунок тонкої опори»).

WHY. `114` priced the support of a point dendrometer that uses the ANCHOR: from the flange seat its thermal term stays
under the frames' 0.3 µm/K only for a tie shallower than 7.67 mm (premise (a)) or 21.01 mm (premise (b)) — on the live-
bark datum −0.65 / −13.33 mm and +12.68 / +0.008 mm — and a flange that bears on the dead bark loses part of the bark's
radial change (01_03 §4 ⊕ (в)). With the cell cut (⚖️ founder 2026-11-22, 01_03 §4) the read-only role check of
2026-11-22 named the gap: the canon never priced the simplest support the market uses — a thin rod in the wood, a frame
clamped to it above the bark, the probe on the live bark. This script prices it on `114`'s loop.

MODEL. The loop (`114` (1)) closed for a rod frame, origin at the live bark the probe touches, per kelvin:
    A = (α_w − α_rod)·z_f  +  (α_s − α_rod)·h_c  +  (α_s − α_frame)·(h − h_c)
the IN-WOOD term over the rod's tie depth z_f below the live bark, the ABOVE-BARK term over the rod between the live bark
and its clamp at height h_c, and the FRAME term from the clamp up to the sensor at h (α_s: the scale's or probe's
material). The third is a free design choice (a frame matched to the scale nulls it) and is nulled; the second is NOT
free — h_c is at least the dead bark the clamp must clear — so it is printed per rod × scale material at named heights,
and the in-wood term is printed beside it. This is `114`'s formula with the rod as the section list, z_t = 0, h = h_c
and α_h = α_rod (control (5) holds the mapping), on the live-bark datum and on the install day.
Two conventions are printed, because they null DIFFERENT terms: (A) the scale matched to the ROD (α_s = α_rod) nulls the
above-bark term, so the crossing is the in-wood one, z* = 0.3/(|α_w − α_rod|·1e3) below the live bark; (B) `114`'s base
convention, the scale matched to the WOOD (α_s = α_w), with the clamp at the dead bark's surface: the rod segment through
the dead bark z_t joins the in-wood term, A = (α_w − α_rod)·(z_f + z_t), so the crossing below the live bark is z* − z_t —
printed on the rod's OWN dead bark (the install heights: lib's ridge bark at the two DBH ends; a negative crossing reads
«over the frames at any tie») and, for the comparison with `114`'s anchor only, on `114`'s dead bark under the flange
(a reading of the flange's geometry), where `114` records the anchor's live-bark crossings the same way (control (3)). The depth AXIS is 0–100 mm below the live bark, install-day: a crossing beyond it is
reported as «beyond the axis», not as a depth — the hosts' xylem radius is a few hundred mm and the one α_w reading
(fresh sapwood) does not describe heartwood. Over the life the live bark moves outward at `114`'s radial rate while the tie
stays in old xylem, so z_f grows by the increment: under (A), or with a clamp that keeps its height above the bark, the
drift is |α_w − α_rod|·rate (and the years from the chosen tie to the crossing follow); with a FIXED clamp z_f + h_c is
constant and the drift is |α_w − α_s|·rate per scale — zero for a wood-matched scale. The allowed scale mismatch per height,
(0.3 − |in-wood term at the chosen tie|)/h_c, is the conservative half of the window either side. Because α_w is ONE reading, each depth also prints the window of α_w within which the in-wood term stays
under the frames, [α_rod − 300/z, α_rod + 300/z] ppm/K — every material's window at one depth has the same width 600/z;
the titanium alloys' INTERSECTION is what the verdict quotes. The µm figures are `114`'s air proxy, |A|·ΔT over `114`'s
spans — a stem-interior proxy, not a bound (`114` CANNOT (2)).

CONTROLS (CAN / CANNOT).
 (1) `114`'s anchor sections, rebuilt from `103`'s cache through `114`'s imported `anchor_sections`, equal the sections
     `114` cached and, integrated by its `anchor_term_um_per_k`, reproduce every named point and its frames' crossing.
     CAN catch: a drift between `114`'s code and its cache, a `103` cache that moved under `114`. CANNOT: a formula wrong in
     both (one code).
 (2) For every rod material, `114`'s integrator evaluated AT our crossing z* returns |A| = 0.3 µm/K — on both signs, so the
     α < α_w branch `114`'s own `frames_crossing_mm` cannot see (it accumulates the signed slope) is checked too.
     CAN catch: a sign or unit error in our crossing. CANNOT: a wrong α_w or α_rod (shared).
 (3) The datum shift of convention (B) — crossing below the live bark = crossing from the seat − z_t — reproduces `114`'s
     cached `crossing_minus_live_bark_depth_mm` for every anchor row and both dead-bark readings. CAN catch: a misread of
     `114`'s datum or of which dead bark it uses (the comparison would then not be like-for-like). CANNOT: a wrong dead-bark
     reading (`114`'s input).
 (4) α_w read from `103`'s cache equals `114`'s recorded input. CAN catch: a `114` cache older than `103`'s. CANNOT: a wrong
     primary reading (Sevanto et al. 2005, transcribed in `103`).
 (5) `114`'s `artefact_um_per_k` with the rod mapping (sections = the rod, z_t = 0, h = h_c, α_h = α_rod) equals the explicit
     in-wood + above-bark sum for every rod × scale × height cell. CAN catch: a role or sign error in our above-bark term.
     CANNOT: a loop wrong in `114` itself.

CANNOT (the count's ceilings, printed into the cache):
 (1) α_w is one reading — Sevanto et al. 2005, P. sylvestris, fresh water-saturated xylem, 5–45 °C, radial, bark excluded,
     the table's mean (`103`); its spread is not in the tree, hence the window; its depth profile (sapwood → heartwood) and
     the rod's own wound (resin, the CODIT column) under an offset probe are not modelled. The live phloem between the
     probe's surface and the cambium is taken at the xylem's α, as `103` and `114` take the span's wood side.
 (2) Frozen days: a freezing stem shrinks (103 CANNOT (4)), which is not a CTE; the unfrozen share printed is `114`'s
     (ERA5 air minimum > 0 °C), not the stem's state; and the seasonal span reaches below Sevanto's 5 °C.
 (3) A uniform ΔT: the rod, frame and probe above the bark sit in air and sun while the embedded rod lags — the nulling of
     the frame term (and of the above-bark term under (A)) holds only isothermally.
 (4) The 0.3 µm/K is the whole instrument's budget (`114` CANNOT (7)) — «under the frames» is not «meets the frames»; and
     whether commercial frames' figure includes their own in-wood rod loop is not in the tree.
 (5) The effective tie of a distributed fixation (a threaded or press-fitted length) and its creep under the probe's
     spring — the depth is an axis; a callus around the rod moves the tie over the years.
 (6) The bark's grip on the rod through its hole (friction, healing, callus) — the same mechanism as `114`'s bearing loss,
     with the hole's stiffness in place of the flange's face; unpriced, and it may grow with healing.
 (7) The rod's bending and the frame's stiffness under its own mass and wind; a lateral offset of rod and probe; corrosion
     of the rod in sap (00_07 HW.3 tests Ti in sap, not stainless); stainless grades other than 302 (lib has none).
 (8) The capsule's mount and the link between a head on the rod and the capsule — a design fork, not a count (00_07
     DOC-T.131).

Run:  ~/miniforge3/envs/silken_md/bin/python tools/in_silico/scripts/130_thin_rod_dendrometer_support.py   # < 1 s
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import (
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    ALPHA_SS302_1K,
    ALPHA_STEEL_MILD_1K,
    BARK_SINGLE_RIDGE_MM_BY_DBH_CM,
    CACHE_DIR,
    DBH_MAX_CM,
    DBH_MIN_CM,
    LIVE_PHLOEM_MM_THICK_END_READING,
    LIVE_PHLOEM_MM_THIN_END,
    REPO_ROOT,
)
from lib.utils import banner

MECH = CACHE_DIR / "mechanical"
BUDGET_114 = MECH / "dendrometer_support_budget.json"
WOOD_103 = MECH / "anchor_wood_share.json"
OUT = MECH / "thin_rod_dendrometer_support.json"

AXIS_MM = 100.0                                      # the install-day tie axis below the live bark — our choice
DEPTHS_MM = (5.0, 10.0, 20.0, 30.0, 50.0, 100.0)     # its grid
INSTALL_TIE_MM = 30.0                                # the named install tie the life drift starts from — our choice
ROD_LONG_MM = 1.0e4                                  # a section long enough to hold every crossing (integrator calls)


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S114 = _load("s114_dendrometer", "114_dendrometer_support_budget.py")
FRAME = S114.FRAME_UM_PER_K

ROD_MATERIALS = {alloy: (p["alpha_1K"], "lib ALLOY_PROPERTIES alpha_1K — lib cites no source for it")
                 for alloy, p in ALLOY_PROPERTIES.items()}
ROD_MATERIALS["SS302"] = (ALPHA_SS302_1K, "lib ALPHA_SS302_1K — Parker Table 2-5, «Stainless Steel, Type 302»")
ROD_MATERIALS["steel_mild"] = (ALPHA_STEEL_MILD_1K, "lib ALPHA_STEEL_MILD_1K — Parker Table 2-5, «Steel, Mild»")
TITANIUM = tuple(m for m in ROD_MATERIALS if m.startswith(("Ti", "CP-Ti", "beta-Ti")))

# the dead bark the clamp must clear, from lib's single-ridge bark minus the live phloem readings (thin end · thick end)
DEAD_BARK_MM = {f"dbh{int(dbh)}": (BARK_SINGLE_RIDGE_MM_BY_DBH_CM[int(dbh)][0] - LIVE_PHLOEM_MM_THIN_END,
                                   BARK_SINGLE_RIDGE_MM_BY_DBH_CM[int(dbh)][1] - LIVE_PHLOEM_MM_THICK_END_READING)
                for dbh in (DBH_MIN_CM, DBH_MAX_CM)}
HC_INSTALL_MM = (min(v[0] for v in DEAD_BARK_MM.values()), max(v[1] for v in DEAD_BARK_MM.values()))
TRAVEL_MM = tuple(r * S114.LIFE_YR for r in S114.RADIAL_RATE_MM_PER_YR)   # 114's rate ends over its life


def crossing_mm(alpha_rod: float, alpha_w: float) -> float | None:
    """|in-wood term| = 0.3 µm/K, either sign: z* = FRAME / (|α_w − α_rod|·1e3), lengths in mm."""
    d = abs(alpha_w - alpha_rod)
    return None if d == 0.0 else FRAME / (d * 1e3)


def on_axis(z: float | None) -> float | str:
    return "beyond the axis" if z is None or z > AXIS_MM else round(z, 2)


def window_ppm(alpha_rod: float, z_mm: float) -> list[float]:
    half = FRAME / (z_mm * 1e-3)
    return [round(alpha_rod * 1e6 - half, 2), round(alpha_rod * 1e6 + half, 2)]


def sign_reading(alpha_w: float, alpha_rod: float, cited: bool) -> str:
    da = alpha_w - alpha_rod
    word = "negative" if da < 0 else "positive"
    flips = ">" if da < 0 else "<"
    alpha_note = "α from the Parker table" if cited else "lib's α cites no source"
    return (f"{word} on the one α_w reading (Δα {da * 1e6:+.2f} ppm/K); it flips if α_w {flips} {alpha_rod * 1e6:g} ppm/K — "
            f"conditional (one α_w reading; {alpha_note})")


def in_wood(alpha_rod: float, z: float, alpha_w: float) -> float:
    return S114.anchor_term_um_per_k([(0.0, ROD_LONG_MM, alpha_rod)], z, alpha_w)


def years_to_cross(z_star: float | None, rate: float) -> float | str:
    if z_star is None or z_star > AXIS_MM:
        return "beyond the axis"
    return 0.0 if z_star <= INSTALL_TIE_MM else round((z_star - INSTALL_TIE_MM) / rate, 1)


def main() -> int:
    banner("130 — a thin rod as the point dendrometer's support, against the anchor (114)")
    z114 = json.loads(BUDGET_114.read_text(encoding="utf-8"))
    z103 = json.loads(WOOD_103.read_text(encoding="utf-8"))
    alpha_w = z103["inputs"]["alpha_xylem_green_ppm_K"] * 1e-6
    zt_114 = z114["inputs"]["dead_bark_under_flange_78_probe_proxy_mm"]
    controls = {}

    # (4) α_w — 103's cache against 114's recorded input
    controls["4_alpha_w_103_equals_114_input"] = z114["inputs"]["alpha_xylem_green_ppm_K"] == alpha_w * 1e6
    assert controls["4_alpha_w_103_equals_114_input"], "114's cache is older than 103's"

    # (1) 114's anchor rows reproduced from 103's cache through 114's own functions
    c1 = {"rows": 0, "points": 0, "max_abs_diff_um_per_K": 0.0, "sections_equal_114_cache": True}
    for key, row in z114["support"].items():
        premise, shank = key.split(":")
        sections = S114.anchor_sections(z103, premise, shank)
        cached = [tuple(s) for s in row["sections_mm_alpha_ppm_K"]]
        c1["sections_equal_114_cache"] &= all(abs(a - ca) < 1e-9 and abs(b - cb) < 1e-9 and abs(al * 1e6 - cal) < 6e-5
                                              for (a, b, al), (ca, cb, cal) in zip(sections, cached, strict=True))
        for pt in row["points"].values():
            got = round(S114.anchor_term_um_per_k(sections, pt["z_f_mm"], alpha_w), 3)
            c1["max_abs_diff_um_per_K"] = max(c1["max_abs_diff_um_per_K"], abs(got - pt["anchor_term_um_per_K"]))
            c1["points"] += 1
        zc = S114.frames_crossing_mm(sections, alpha_w)
        assert zc is not None and abs(round(zc, 2) - row["frames_crossing_depth_mm"]) < 1e-9, (key, zc)
        c1["rows"] += 1
    controls["1_anchor_rows_reproduced"] = c1
    assert c1["sections_equal_114_cache"] and c1["max_abs_diff_um_per_K"] < 1e-9, c1

    # (3) convention (B)'s datum shift reproduces 114's live-bark crossings of the anchor
    c3 = 0.0
    for row in z114["support"].values():
        for side, zt in zt_114.items():
            c3 = max(c3, abs((row["frames_crossing_depth_mm"] - zt) - row["crossing_minus_live_bark_depth_mm"][side]))
    controls["3_datum_shift_reproduces_114_live_bark_crossings_max_miss_mm"] = round(c3, 4)
    assert c3 <= 0.006, c3          # 114 rounds the seat crossing to 0.01 mm and the shifted one to 0.001

    spans = z114["temperature"]
    proxy_k = {"diurnal_growing_p50": spans["diurnal_range_growing_MJJA_K"]["p50"],
               "diurnal_growing_p95": spans["diurnal_range_growing_MJJA_K"]["p95"],
               "seasonal_unfrozen_p5_p95": round(spans["daily_mean_unfrozen_p5_p95_C"][1]
                                                 - spans["daily_mean_unfrozen_p5_p95_C"][0], 6)}
    scales = {m: a for m, (a, _src) in ROD_MATERIALS.items()} | {"matched_to_wood": alpha_w}
    hc_named = {"install_min": HC_INSTALL_MM[0], "install_max": HC_INSTALL_MM[1],
                "install_min_plus_life_travel_slow": HC_INSTALL_MM[0] + TRAVEL_MM[0],
                "install_max_plus_life_travel_fast": HC_INSTALL_MM[1] + TRAVEL_MM[1]}

    rods, c2, c5, trap = {}, 0.0, 0.0, []
    for mat, (alpha, src) in ROD_MATERIALS.items():
        z_star = crossing_mm(alpha, alpha_w)
        # (2) 114's integrator at our crossing returns the frames' figure, on both signs
        c2 = max(c2, abs(abs(in_wood(alpha, z_star, alpha_w)) - FRAME))
        if alpha < alpha_w and S114.frames_crossing_mm([(0.0, ROD_LONG_MM, alpha)], alpha_w) is None:
            trap.append(mat)
        depths = {}
        for z in DEPTHS_MM:
            a = in_wood(alpha, z, alpha_w)
            depths[f"{z:g}"] = {"A_in_wood_um_per_K": round(a, 4), "x_frames": round(abs(a) / FRAME, 3),
                                "under_frames": abs(a) < FRAME, "alpha_w_window_ppm_K": window_ppm(alpha, z),
                                "air_proxy_um": {k: round(abs(a) * v, 2) for k, v in proxy_k.items()}}
        above = {}
        a30 = in_wood(alpha, INSTALL_TIE_MM, alpha_w)
        p95 = proxy_k["diurnal_growing_p95"]
        for sname, a_s in scales.items():
            cells = {}
            for hname, hc in hc_named.items():
                explicit = a30 + (a_s - alpha) * hc * 1e3
                via_114 = S114.artefact_um_per_k([(0.0, ROD_LONG_MM, alpha)], INSTALL_TIE_MM, 0.0, hc, alpha_w, a_s, alpha)
                c5 = max(c5, abs(explicit - via_114))
                cells[hname] = {"above_bark_um_per_K": round((a_s - alpha) * hc * 1e3, 4),
                                "total_at_install_tie_um_per_K": round(explicit, 4),
                                "x_frames": round(abs(explicit) / FRAME, 3),
                                "total_air_proxy_um_p95": round(abs(explicit) * p95, 2)}
            above[sname] = cells
        conv_b = {side: on_axis(None if z_star is None else z_star - zt) for side, zt in zt_114.items()}
        own_b = {}
        for hname in ("install_min", "install_max"):
            zb = None if z_star is None else z_star - hc_named[hname]
            own_b[hname] = "over the frames at any tie" if zb is not None and zb < 0 else on_axis(zb)
        rods[mat] = {"alpha_ppm_K": round(alpha * 1e6, 3), "alpha_source": src,
                     "alpha_w_minus_alpha_rod_ppm_K": round((alpha_w - alpha) * 1e6, 3),
                     "sign": sign_reading(alpha_w, alpha, cited=mat in ("SS302", "steel_mild")),
                     "crossing_below_live_bark_mm": {
                         "A_scale_matched_to_rod": on_axis(z_star),
                         "B_scale_matched_to_wood_on_the_rods_own_dead_bark": own_b,
                         "B_for_comparison_with_114_anchor_on_its_dead_bark": conv_b},
                     "depths": depths,
                     "above_bark_at_install_tie_30mm": above,
                     "scale_mismatch_allowed_ppm_K_at_install_tie": {
                         h: round((FRAME - abs(a30)) / (hc * 1e-3), 3) for h, hc in hc_named.items()},
                     "life_drift": {
                         "scale_matched_to_rod_or_clamp_keeping_h_c": {
                             "um_per_K_per_year_at_rate_ends": [round(abs(alpha_w - alpha) * r * 1e3, 4)
                                                                for r in S114.RADIAL_RATE_MM_PER_YR],
                             "years_from_the_chosen_30mm_tie_to_crossing_at_rate_ends":
                                 [years_to_cross(z_star, r) for r in S114.RADIAL_RATE_MM_PER_YR]},
                         "fixed_clamp_um_per_K_per_year_at_rate_ends_by_scale": {
                             sn: [round(abs(alpha_w - a_s) * r * 1e3, 4) for r in S114.RADIAL_RATE_MM_PER_YR]
                             for sn, a_s in scales.items()}}}
    controls["2_integrator_at_our_crossing_max_miss_um_per_K"] = c2
    controls["2_114_frames_crossing_returns_none_where_alpha_below_wood"] = trap
    controls["5_mapping_onto_114_artefact_max_miss_um_per_K"] = c5
    assert c2 < 1e-12 and c5 < 1e-12, (c2, c5)

    # the anchor: live-bark crossings (114's), worst rows and the PEEK share of the deepest-tie term (114's cached sections)
    peek_share = {}
    for key, row in z114["support"].items():
        secs = row["sections_mm_alpha_ppm_K"]
        deep = max(p["z_f_mm"] for p in row["points"].values())
        tot = sum((alpha_w * 1e6 - al) * (min(b, deep) - a) for a, b, al in secs if min(b, deep) > a)
        pk = sum((alpha_w * 1e6 - al) * (min(b, deep) - a) for a, b, al in secs
                 if min(b, deep) > a and abs(al - ALPHA_PEEK_1K * 1e6) < 1e-9)
        peek_share[key] = round(pk / tot, 3)
    anchor = {"frames_crossing_from_seat_mm": {k: r["frames_crossing_depth_mm"] for k, r in z114["support"].items()},
              "crossing_below_live_bark_mm": {k: r["crossing_minus_live_bark_depth_mm"] for k, r in z114["support"].items()},
              "x_frames_at_deepest_named_tie": {k: max(r["points"].values(), key=lambda p: p["z_f_mm"])["x_frames"]
                                                for k, r in z114["support"].items()},
              "peek_share_of_deepest_tie_term": peek_share,
              "dead_bark_under_flange_mm_114": zt_114}
    bb = z114["bark_bearing"]
    bearing = {"rod": "no flange face on the bark; the hole's grip on the rod (friction, healing, callus) is the same "
                      "mechanism with another stiffness — unpriced, and it may grow with healing (CANNOT 6)",
               "anchor_114_premise_b_fraction_lost_air_dry_bark": bb["fraction_lost_U_at_air_dry_bark_readings"],
               "anchor_114_premise_b_fraction_lost_rigid_bark": bb["fraction_lost_U_rigid_bark"],
               "anchor_114_premise_a": "a rising bark can lift the flange off the sleeve — no reference (114's reading)"}

    # ── the headline: every figure the verdict prints, computed from the raw values and rounded ONCE
    def raw_a(mat, z):
        return (alpha_w - ROD_MATERIALS[mat][0]) * z * 1e3
    def raw_above(mat, a_s, hc):
        return (a_s - ROD_MATERIALS[mat][0]) * hc * 1e3
    win100 = [max(ROD_MATERIALS[m][0] * 1e6 - FRAME / (AXIS_MM * 1e-3) for m in TITANIUM),
              min(ROD_MATERIALS[m][0] * 1e6 + FRAME / (AXIS_MM * 1e-3) for m in TITANIUM)]
    hc_life = hc_named["install_max_plus_life_travel_fast"]
    deep = anchor["x_frames_at_deepest_named_tie"]
    z_ss, z_ms = crossing_mm(ALPHA_SS302_1K, alpha_w), crossing_mm(ALPHA_STEEL_MILD_1K, alpha_w)
    anc = anchor["crossing_below_live_bark_mm"]

    def about0(x):
        return "≈ 0" if abs(x) < 0.01 else f"{x:.1f}"
    h = {
        "ti_in_wood_max_um_per_K_at_100mm": round(max(abs(raw_a(m, AXIS_MM)) for m in TITANIUM), 3),
        "ti_alpha_w_window_intersection_at_100mm_ppm_K": [round(win100[0], 1), round(win100[1], 1)],
        "ta_in_wood_um_per_K_at_100mm": round(raw_a("Ta", AXIS_MM), 3),
        "anchor_x_frames_at_deepest_named_tie": [min(deep.values()), max(deep.values())],
        "anchor_peek_share_pct": [round(100 * min(peek_share.values())), round(100 * max(peek_share.values()))],
        "ti_scale_mismatch_allowed_ppm_K_install": [
            round(min((FRAME - abs(raw_a(m, INSTALL_TIE_MM))) / (hc_named["install_max"] * 1e-3) for m in TITANIUM), 1),
            round(min((FRAME - abs(raw_a(m, INSTALL_TIE_MM))) / (hc_named["install_min"] * 1e-3) for m in TITANIUM), 1)],
        "ti_scale_mismatch_allowed_ppm_K_life": round(min((FRAME - abs(raw_a(m, INSTALL_TIE_MM))) / (hc_life * 1e-3)
                                                          for m in TITANIUM), 1),
        "ti_ss302_scale_above_bark_um_per_K_install": [
            round(min(abs(raw_above(m, ALPHA_SS302_1K, hc_named["install_min"])) for m in TITANIUM), 3),
            round(max(abs(raw_above(m, ALPHA_SS302_1K, hc_named["install_max"])) for m in TITANIUM), 3)],
        "ti_ss302_scale_above_bark_um_per_K_life_max": round(max(abs(raw_above(m, ALPHA_SS302_1K, hc_life))
                                                                 for m in TITANIUM), 3),
        "ss302_crossing_A_mm": round(z_ss),
        "ss302_window_at_30mm_ppm_K": window_ppm(ALPHA_SS302_1K, INSTALL_TIE_MM),
        "ss302_crossing_B_own_bark_dbh_min_thin_mm": round(z_ss - hc_named["install_min"]),
        "ss302_B_own_bark_dbh_max_thick_over_at_any_tie": z_ss - hc_named["install_max"] < 0,
        "mild_steel_crossing_A_mm": round(z_ms),
        "ti_drift_A_max_um_per_K_per_year": round(max(abs(alpha_w - ROD_MATERIALS[m][0]) * S114.RADIAL_RATE_MM_PER_YR[1] * 1e3
                                                      for m in TITANIUM), 4),
        "ss302_crossing_B_114_dead_bark_mm": [round(z_ss - zt_114["thin_contact_78"]), round(z_ss - zt_114["thick_side_78"])],
        "anchor_crossing_below_live_bark_a": [about0(anc["flange_on_bark:bonded"]["thin_contact_78"]),
                                              about0(anc["flange_on_bark:bonded"]["thick_side_78"])],
        "anchor_crossing_below_live_bark_b": [about0(anc["zone3_fit:bonded"]["thin_contact_78"]),
                                              about0(anc["zone3_fit:bonded"]["thick_side_78"])],
        "unfrozen_days_share_114": round(spans["unfrozen_days_share"], 2),
    }
    assert h["ss302_B_own_bark_dbh_max_thick_over_at_any_tie"], "the verdict's stainless clause assumes it"
    verdict = (
        f"(1) Rod vs anchor, in the wood (convention A — the scale of the rod's alloy; one green-xylem α reading, "
        f"{alpha_w * 1e6:g} ppm/K; lib's titanium α values cite no source): on that one reading a titanium-alloy rod's term stays "
        f"at or under {h['ti_in_wood_max_um_per_K_at_100mm']} µm/K over the install-day axis 0–{AXIS_MM:g} mm, and it does not "
        f"cross the frames' {FRAME} µm/K as long as α_w lies within {h['ti_alpha_w_window_intersection_at_100mm_ppm_K'][0]}–"
        f"{h['ti_alpha_w_window_intersection_at_100mm_ppm_K'][1]} ppm/K (the alloys' windows intersected at {AXIS_MM:g} mm); "
        f"tantalum, the opposite sign, reaches {h['ta_in_wood_um_per_K_at_100mm']} µm/K there. The anchor (114) reaches "
        f"×{h['anchor_x_frames_at_deepest_named_tie'][0]}–×{h['anchor_x_frames_at_deepest_named_tie'][1]} the frames at its "
        f"deepest named tie, the PEEK sleeve carrying {h['anchor_peek_share_pct'][0]}–{h['anchor_peek_share_pct'][1]} % of it. "
        f"(2) Above the bark the rod between the live bark and its clamp faces the scale, (α_s − α_rod)·h_c: with the in-wood "
        f"term of a chosen {INSTALL_TIE_MM:g} mm tie, a titanium rod stays under the frames for any scale within "
        f"{h['ti_scale_mismatch_allowed_ppm_K_install'][0]}–{h['ti_scale_mismatch_allowed_ppm_K_install'][1]} ppm/K of the rod "
        f"at install heights (h_c {HC_INSTALL_MM[0]:g}–{HC_INSTALL_MM[1]:g} mm, the ridge bark the clamp clears over DBH "
        f"{DBH_MIN_CM:g}–{DBH_MAX_CM:g}) and within {h['ti_scale_mismatch_allowed_ppm_K_life']} ppm/K at {hc_life:g} mm (a "
        f"fixed clamp set to clear twenty years of fast growth — a choice); a stainless-302 scale on a titanium rod costs "
        f"{h['ti_ss302_scale_above_bark_um_per_K_install'][0]}–{h['ti_ss302_scale_above_bark_um_per_K_install'][1]} µm/K "
        f"above the bark at install heights and up to {h['ti_ss302_scale_above_bark_um_per_K_life_max']} at {hc_life:g} mm — "
        f"for a steel or stainless scale this term dominates; a scale, probe and frame of the rod's own alloy cost nothing, "
        f"isothermally. (3) A stainless rod is not supported: under convention A it reaches the frames near "
        f"{h['ss302_crossing_A_mm']} mm (its α_w window at {INSTALL_TIE_MM:g} mm, {h['ss302_window_at_30mm_ppm_K'][0]}–"
        f"{h['ss302_window_at_30mm_ppm_K'][1]} ppm/K, ends just under the one reading); under convention B (the scale matched "
        f"to the wood, the clamp at the dead bark's surface) near {h['ss302_crossing_B_own_bark_dbh_min_thin_mm']} mm on the "
        f"thinnest bark (DBH {DBH_MIN_CM:g}) and over the frames at any tie on the thickest (DBH {DBH_MAX_CM:g}); mild steel "
        f"under A near {h['mild_steel_crossing_A_mm']} mm. (4) Over the life the tie deepens at "
        f"{S114.RADIAL_RATE_MM_PER_YR[0]:g}–{S114.RADIAL_RATE_MM_PER_YR[1]:g} mm/yr: under convention A, or with a clamp that "
        f"keeps its height, the drift is |α_w − α_rod|·rate (titanium at most {h['ti_drift_A_max_um_per_K_per_year']} µm/K per "
        f"year); with a fixed clamp it is |α_w − α_s|·rate — zero for a wood-matched scale. (5) For comparison with 114 on its "
        f"datum and convention (B, 114's dead bark under the flange): stainless crosses near "
        f"{h['ss302_crossing_B_114_dead_bark_mm'][0]} / {h['ss302_crossing_B_114_dead_bark_mm'][1]} mm below the live bark, "
        f"the anchor at {h['anchor_crossing_below_live_bark_a'][0]} / {h['anchor_crossing_below_live_bark_a'][1]} mm (premise a "
        f"— inside the dead bark) and {h['anchor_crossing_below_live_bark_b'][0]} / {h['anchor_crossing_below_live_bark_b'][1]} "
        f"mm (premise b). (6) Not computed: the hole's grip on the rod, so no rod-vs-anchor bearing comparison; a non-uniform "
        f"ΔT; frozen days (114's unfrozen share {h['unfrozen_days_share_114']}, an air criterion); whether the frames' "
        f"{FRAME} µm/K includes their own in-wood rod loop (commercial frames sit on rods); and the instrument's other "
        f"terms — {FRAME} µm/K is its whole budget.")
    print(verdict)
    for m, r in rods.items():
        print(f"  {m:<18} α {r['alpha_ppm_K']:>6}  Δα {r['alpha_w_minus_alpha_rod_ppm_K']:>+7}  z*(A) "
              f"{r['crossing_below_live_bark_mm']['A_scale_matched_to_rod']}  z*(B) "
              f"{r['crossing_below_live_bark_mm']['B_scale_matched_to_wood_on_the_rods_own_dead_bark']}  A@30 "
              f"{r['depths']['30']['A_in_wood_um_per_K']:+.4f}")
    print(f"  controls: {controls}")

    OUT.write_text(json.dumps({
        "script": "130_thin_rod_dendrometer_support.py",
        "leg": "00_07 HW.54 «ролі деталей анкера без комірки» · DOC-T.131 «конструкція анкера без комірки» — рахунок тонкої опори",
        "what": "a monolithic rod in the stem as the point dendrometer's support: 114's loop with the rod as the section "
                "list — in-wood term on the install-day axis, above-bark term per rod × scale, two conventions, life drift",
        "inputs": {"alpha_xylem_green_ppm_K": alpha_w * 1e6,
                   "alpha_xylem_source": "103's cache (Sevanto et al. 2005, P. sylvestris, fresh water-saturated xylem, "
                                         "5–45 °C, radial, bark excluded — one reading, the table's mean)",
                   "frame_sensitivity_um_per_K": FRAME, "axis_mm": AXIS_MM, "depths_mm": list(DEPTHS_MM),
                   "install_tie_mm": INSTALL_TIE_MM, "radial_rate_mm_per_yr": list(S114.RADIAL_RATE_MM_PER_YR),
                   "life_yr": S114.LIFE_YR, "life_travel_mm": list(TRAVEL_MM),
                   "dead_bark_mm_by_dbh": DEAD_BARK_MM, "h_c_named_mm": hc_named,
                   "scale_alphas_ppm_K": {k: round(v * 1e6, 3) for k, v in scales.items()},
                   "air_proxy_spans_K": proxy_k, "unfrozen_days_share_114": spans["unfrozen_days_share"],
                   "choices": {
                       "axis_mm": "ours — the install-day tie axis; beyond it a crossing is «beyond the axis»",
                       "install_tie_mm": "ours — the tie the above-bark cells and the life years start from; the SS302 "
                                         "years depend on it sitting just above that rod's crossing",
                       "h_c_named_mm": "install = lib's single-ridge bark minus the live phloem readings (furrows are "
                                       "thinner — no primary in the tree; the thick end's live phloem is lib's assumed "
                                       "reading); life = install + 114's rate × life, paired min+slow · max+fast — ours; "
                                       "the life heights mean a FIXED clamp set to clear twenty years of growth"}},
        "rods": rods, "anchor_114": anchor, "bark_bearing": bearing, "headline": h,
        "frame_term": "(α_s − α_frame)·(h − h_c) — nulled: a frame matched to the scale; isothermal only (CANNOT 3)",
        "controls": controls,
        "not_computed": ["α_w's spread and depth profile; the rod's wound", "the live phloem's own α",
                         "frozen days (not a CTE; the share is an air criterion)", "a non-uniform ΔT above vs in the wood",
                         "whether the frames' 0.3 µm/K includes their own in-wood loop; the instrument's other terms",
                         "the tie's effective depth and creep; callus", "the hole's grip on the rod",
                         "bending, frame stiffness, lateral offset, corrosion in sap, other stainless grades",
                         "the capsule's mount and the head–capsule link"],
        "verdict": verdict}, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"→ {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
