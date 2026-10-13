#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""88 — the O-ring's own reaction: Parker's compression-load band over the squeeze window, and what it does to the
three models that stood on a bound instead (00_07 HW.43, the leg «нижня межа реакції O-ring»; 52 · 73 · 87).

QUESTION. Canon had no O-ring compression force. `52 §rim_datum_creep` put a «deliberately generous» 100 N on it
(lib `GENEROUS_ORING_BOUND_N`) to size the initial bayonet clamp, `73` judged the collar wall against that bound and
called the missing datum «no longer a blocker precisely because the generous bound is covered», and `87`'s premise
(A) needs a reaction from BELOW. One datum, opposite signs: `52`/`73` are threatened by the UPPER reaction at the TOP
of the squeeze window, `87` by the LOWER reaction at the FLOOR (in-silico rule 15 (c)).

PATHS (rule 15 (a)–(b)). The bayonet is deflection-controlled (02_02 §4.3): the lugs hold the radome at a set Z, the
ring's squeeze is fixed by the groove depth and the rim datum, and its reaction R is a LIFT on the radome that the
lugs carry with the pogo pair p. Both the clamp and R relax over time: the clamp with the PEEK it compresses
(f(t) of `52`), R with the elastomer's stress relaxation (not in this source). So `52`'s requirement «the rim stays
seated» is max over t of (R(t) + p) / f(t), bracketed by R0 + p at assembly (f = 1) and (R0 + p) / f(20 y) if the
ring never relaxes — the second is the form `52` prints. This script states how much of R0 the ring must LOSE by each
year for the lug root to carry the requirement — f(t) reaches its floor within a few years, so most of that loss is
due early, not by year 20. The lug root carries the DELIVERED clamp, which is at least the requirement: the margin
here says whether a bayonet that meets the requirement can exist, not that the delivered one is safe. For (A), `87`
gives the reaction each clamp design needs: an INITIAL one for a clamp at the form `52` prints, (R0 + p) / f(20 y)
(it never lifts while L ≤ L0), the one LEFT after 20 years for a weaker clamp (it can lift, and a lift is taken as not
undone — conservative); this script compares both with the band's LOW end at the window floor. The friction bound runs
through the lug ledge (the rim's share can be zero), with a dry µ while the ring is greased.
⚠️ TEMPERATURE is not in any of 52 · 87 · 88: in the clamp loop the PEEK is squeezed between two Ti faces over the same
span, so cold unloads the clamp and HEAT raises it (heat is the lug root's threat), and the ring's own contraction takes
squeeze in the cold (Parker Table 2-5); the ring's force below room temperature is not in this source. Every margin
below holds at the assembly temperature, and «L stays ≤ L0» is a condition (resin swell raises L too), not a result.

SOURCE. Parker O-Ring Handbook ORD 5700 (parker.com/content/dam/Parker-com/Literature/O-Ring-Division-Literature/
ORD-5700.pdf, read 2026-10-13). Figure 2-4 «.070 Cross Section», p. 2-11 (PDF page 23): «Compression Load per Linear
Inch of Seal — Pounds» against «Percent Compression», one bar per Shore A hardness 50–90 at 5 · 10 · 20 · 30 · 40 %. The
bar ends below are the VECTOR coordinates of the PDF page (pdftocairo -svg), in pt, converted on the chart's own decade
lines (0.1 at x = 113.50, 1000 at x = 541.14) — a transcription, not an eye reading; the plot's minor gridlines depart
from a true log scale by up to ~1.6 pt, ≈ ±4 % in load. Table 2-3 (p. 2-10): for a ring under 25.4 mm (1") in
diameter the load lies in the «Middle third of range» (hardness below normal) or the «Upper third of range» (above
normal) — never the lower third; so the band used here runs from the bottom of the bar's middle third, taken in the
log scale the bar is drawn on (a linear third would sit higher), to the bar's top. §3.8 (p. 3-9): the load «is not
fixed, but is a range of values»; temperature lowers it «very little except for the hardest compounds» (N0674-70:
−10 % from 24 to 126 °C). Parker gives COMPRESSION SET (the share of deflection not recovered after release, e.g. after
70 h at 100 °C), not stress relaxation, so the ring's force after years in the field is NOT read from this source.

ASSUMPTIONS (ours, named, not Parker's): load interpolated log-linearly in squeeze between the chart's rows (it reads
a little low against a smooth curve between 20 and 30 %); the seal length is the mean circumference of the ring
stretched onto the groove's inner wall (AS568-019 — 02_02 §3.2); the chart's bars hold at our 80 % gland fill.

CAN show: the reaction band (N) at the window floor, at both ends of the chain `52` models, at the nominal and at the
window top; for the lug root, the requirement bracket, the margin at both ends of it, the share of R0 the ring must
lose for SF 2 to hold, the squeeze at which the band's top binds (with the transcription's ±4 %), and the collar wall
strength would ask for; the share of R0 the ring must lose by each year; for (A), the band's floor against `87`'s
needs.
CANNOT show: the ring's stress relaxation (a compound datum — ISO 3384-type data from the vendor); our compound's own
curve; the clamp the bayonet delivers; anything at another temperature than assembly; lug bending and the
fillet (`73` is pure shear).
"""
from __future__ import annotations

import itertools
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import CACHE_DIR, GENEROUS_ORING_BOUND_N
from lib.utils import banner

SI_DESCRIPTION = ("The force an O-ring pushes back with when it is squeezed, from a seal maker's published chart, over "
                  "the range of squeeze our tolerances allow, and what that force means for the bayonet lock and for "
                  "the capsule staying put.")

ZSTACK52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
COLLAR73 = CACHE_DIR / "mechanical" / "collar_wall_inversion.json"
SWAY87 = CACHE_DIR / "mechanical" / "pogo_sway_transfer.json"
OUT_JSON = CACHE_DIR / "mechanical" / "oring_reaction_band.json"

LBF_N = 4.4482216152605
IN_MM = 25.4
# Figure 2-4 calibration: the decade lines of the plot, in pt on the PDF page.
X_DECADE_0P1, X_DECADE_1000 = 113.50, 541.14
PT_PER_DECADE = (X_DECADE_1000 - X_DECADE_0P1) / 4.0
GRID_PRECISION_FRACTION = 0.04       # the minor gridlines' departure from a true log scale, as a load fraction
# Bar ends (x_left, x_right) in pt, Shore A → percent compression. Transcribed from the PDF's vector paths, page 23.
BARS_070_PT = {
    50: {5: (174.60, 211.58), 10: (216.01, 289.76), 20: (257.82, 322.36), 30: (296.18, 332.12), 40: (335.53, 391.99)},
    60: {5: (183.65, 220.56), 10: (222.36, 263.62), 20: (263.16, 307.72), 30: (304.75, 366.20), 40: (345.39, 404.77)},
    70: {5: (197.89, 241.92), 10: (236.74, 286.23), 20: (279.18, 329.22), 30: (316.98, 382.30), 40: (353.69, 422.67)},
    80: {5: (210.40, 265.77), 10: (262.86, 306.82), 20: (296.18, 347.12), 30: (333.92, 392.19), 40: (370.62, 430.00)},
    90: {5: (256.92, 314.29), 10: (288.99, 342.01), 20: (322.38, 372.56), 30: (354.31, 408.57), 40: (385.48, 431.38)},
}
SHORE_A = 70                         # EPDM 70 Shore A — 02_02 §3.2 (⚖️ founder 2026-07-03)
SHORE_A_TOLERANCE = 5                # Parker §2.4.2: durometer «is generally called out in specifications with a tolerance of ±5»
RING_ID_MM = 20.35                   # AS568-019 as supplied — 02_02 §3.2 (⚖️ делеговано 2026-10-01); < 25.4 → Table 2-3 upper rows
TABLE_2_3_BOTTOM = 1.0 / 3.0         # the bottom of the bar's middle third, as a fraction of the bar in log scale
SCHEDULE_YEARS = (1, 2, 3, 5, 10, 20)  # years at which the share the ring must have lost is printed (≤ 52's service life)


def lbf_per_in(x_pt: float) -> float:
    return 0.1 * 10 ** ((x_pt - X_DECADE_0P1) / PT_PER_DECADE)


def bar_at(pct: float, shore: int = SHORE_A) -> tuple[float, float]:
    """The bar's (low, high) in lbf per inch of seal at `pct` — log-linear between the chart's rows (our assumption)."""
    rows = sorted(BARS_070_PT[shore])
    if not rows[0] <= pct <= rows[-1]:
        raise ValueError(f"{pct} % is outside the chart's rows {rows[0]}–{rows[-1]} %")
    lo_row = max(r for r in rows if r <= pct)
    hi_row = min(r for r in rows if r >= pct)
    out = []
    for end in (0, 1):
        a = math.log10(lbf_per_in(BARS_070_PT[shore][lo_row][end]))
        b = math.log10(lbf_per_in(BARS_070_PT[shore][hi_row][end]))
        w = 0.0 if hi_row == lo_row else (pct - lo_row) / (hi_row - lo_row)
        out.append(10 ** (a + w * (b - a)))
    return out[0], out[1]


def band_at(pct: float) -> tuple[float, float]:
    """Table 2-3 for a ring under 1": from the bottom of the bar's middle third (log scale) to the bar's top."""
    lo, hi = bar_at(pct)
    return lo * (hi / lo) ** TABLE_2_3_BOTTOM, hi


def squeeze_where_high_reaches(load_lbf_in: float, scale: float = 1.0) -> float | None:
    """The compression (%) at which the band's TOP × `scale` reaches `load_lbf_in` — bisection on 5–40 %, or None."""
    f = lambda p: band_at(p)[1] * scale - load_lbf_in  # noqa: E731
    lo, hi = 5.0, 40.0
    if f(lo) > 0 or f(hi) < 0:
        return None
    for _ in range(80):
        mid = 0.5 * (lo + hi)
        lo, hi = (lo, mid) if f(mid) > 0 else (mid, hi)
    return 0.5 * (lo + hi)


def wall_for_force(rows: list[dict], force_n: float) -> float:
    """73's lug-root breakeven is linear in the wall (pure shear); interpolate its own rows, scale below the first."""
    pts = sorted((r["wall_mm"], r["breakeven_force_N"]) for r in rows)
    for (w0, f0), (w1, f1) in itertools.pairwise(pts):
        if f0 <= force_n <= f1:
            return w0 + (force_n - f0) * (w1 - w0) / (f1 - f0)
    w0, f0 = pts[0]
    return w0 * force_n / f0


def main() -> int:
    banner("O-ring reaction — Parker Figure 2-4 + Table 2-3 over the squeeze window: 52's clamp · 73's lug root · 87's (A)")
    z52 = json.loads(ZSTACK52.read_text(encoding="utf-8"))
    c73 = json.loads(COLLAR73.read_text(encoding="utf-8"))
    s87 = json.loads(SWAY87.read_text(encoding="utf-8"))
    assert RING_ID_MM < IN_MM, "Table 2-3's upper rows are for rings under 25.4 mm"

    cs = z52["springs"]["oring"]["cs_mm"]
    groove_inner_d = 2.0 * z52["applied_gland"]["flange_groove_r_mm"][0]
    seal_length_in = math.pi * (groove_inner_d + cs) / IN_MM
    to_n = seal_length_in * LBF_N
    win = z52["depth_tolerance_budget"]["intersection_window_pct"]
    nominal = z52["depth_tolerance_budget"]["nominal_pct"]
    chain = z52["parker_face_reconciliation"]["band_at_recommended_pct"]
    points = {"window_floor": win[0], "chain_low": chain[0], "nominal": nominal, "chain_high": chain[1],
              "window_top": win[1]}

    rim = z52["rim_datum_creep"]
    p52, f_t = rim["pogo_pair_force_N_upper_bound"], rim["relax_fraction_at_service"]
    f_of = lambda t: rim["relax_floor"] + (1.0 - rim["relax_floor"]) * math.exp(-t / rim["relax_tau_years"])  # noqa: E731
    years = [y for y in SCHEDULE_YEARS if y <= rim["service_years"]]
    lug_cap = c73["verdict"]["capacity_at_print_floor_N"]
    sf73 = c73["safety_factor"]
    lug_rows = c73["case_b_lug_root_shear"]["rows"]

    band = {}
    for name, pct in points.items():
        lo, hi = band_at(pct)
        bar_lo, _ = bar_at(pct)
        r_hi = hi * to_n
        need_asm, need_20 = r_hi + p52, (r_hi + p52) / f_t     # requirement bracket: at assembly ⊥ ring never relaxes
        # share of R0 the ring must have LOST by year t for SF 2 to hold then — f(t) floors early, so most is due early
        lose = {str(y): round(max(1.0 - (lug_cap * f_of(y) - p52) / r_hi, 0.0), 3) for y in years}
        band[name] = {"squeeze_pct": pct,
                      "bar_lbf_per_in": [round(bar_lo, 2), round(hi, 2)],
                      "lbf_per_in": [round(lo, 2), round(hi, 2)],
                      "reaction_N": [round(lo * to_n, 1), round(r_hi, 1)],
                      "required_clamp_N_at_band_high": {"at_assembly": round(need_asm, 1),
                                                        "after_20_years_ring_never_relaxes": round(need_20, 1)},
                      "lug_root_margin_x_at_print_floor": {"at_assembly": round(lug_cap / need_asm, 2),
                                                           "after_20_years_ring_never_relaxes": round(lug_cap / need_20, 2)},
                      "ring_must_have_lost_share_of_R0_by_year": lose,
                      "collar_wall_strength_asks_mm_ring_never_relaxes": round(wall_for_force(lug_rows, need_20), 3)}

    # Inversion (no datum needed): the reaction at which 52's requirement (ring never relaxing) meets 73's capacity.
    r_bind = lug_cap * f_t - p52
    bind_lbf_in = r_bind / to_n
    sq_bind = squeeze_where_high_reaches(bind_lbf_in)
    sq_bind_reads = [squeeze_where_high_reaches(bind_lbf_in, 1 + s * GRID_PRECISION_FRACTION) for s in (1, -1)]
    sq_generous = squeeze_where_high_reaches(GENEROUS_ORING_BOUND_N / to_n)

    floor_lo = band["window_floor"]["reaction_N"][0]
    a_rows = {k: r["A_rim"] for k, r in s87["by_slope_reading"].items()}
    need = {k: max(a["o_ring_reaction_N_needed"][k] for a in a_rows.values())
            for k in next(iter(a_rows.values()))["o_ring_reaction_N_needed"]}
    # a margin only where the need is an INITIAL reaction; after 20 years the ring's reaction is unknown → a share
    a_margin = {k: round(floor_lo / v, 2) if v > 0 else None for k, v in need.items() if k.startswith("initial")}
    retained = round(need["after_20_years_with_a_weaker_clamp"] / floor_lo, 3)

    top, chain_hi, nom = band["window_top"], band["chain_high"], band["nominal"]
    end, early, mid = str(years[-1]), "2", "5"
    lost = lambda b, y: b["ring_must_have_lost_share_of_R0_by_year"][y] * 100  # noqa: E731
    verdict = (
        f"The «generous» {GENEROUS_ORING_BOUND_N:.0f} N is not an upper bound: for a ring under 1\" Parker's Table 2-3 puts "
        f"the 70 Shore A load in the middle or upper third of the Figure 2-4 bar, so the reaction is "
        f"{nom['reaction_N'][0]:.0f}–{nom['reaction_N'][1]:.0f} N at the {nominal:.1f} % nominal and "
        f"{top['reaction_N'][0]:.0f}–{top['reaction_N'][1]:.0f} N at the {win[1]:.0f} % window top, and the band's top passes "
        f"{GENEROUS_ORING_BOUND_N:.0f} N from {sq_generous:.1f} % squeeze. With that top, 52's requirement lies between the "
        f"clamp at assembly and the 20-year form 52 prints: the lug root at the print floor (SF {sf73:.0f} inside) carries it "
        f"at the nominal at both ends ({nom['lug_root_margin_x_at_print_floor']['after_20_years_ring_never_relaxes']:.2f}× "
        f"at the worse), at the chain 52 models today ({chain[1]:.1f} %) only if the ring has lost about "
        f"{lost(chain_hi, '10'):.0f} % of its reaction by year 10 "
        f"({chain_hi['lug_root_margin_x_at_print_floor']['after_20_years_ring_never_relaxes']:.2f}× if it never does), and at "
        f"the window top only if it has lost about {lost(top, early):.0f} % by year {early} and about "
        f"{lost(top, mid):.0f} % already by year {mid} — the PEEK clamp floors within a few years, so the ring's loss is due "
        f"early "
        f"({top['lug_root_margin_x_at_print_floor']['after_20_years_ring_never_relaxes']:.2f}× if it never does, "
        f"{top['lug_root_margin_x_at_print_floor']['at_assembly']:.2f}× at assembly); a ring that does not relax makes the "
        f"lug bind from {sq_bind:.1f} % ({min(sq_bind_reads):.1f}–{max(sq_bind_reads):.1f} % over the transcription's ±4 %), "
        f"and strength, not printability, then sizes the collar wall — up to "
        f"{top['collar_wall_strength_asks_mm_ring_never_relaxes']:.2f} mm at the window top against the 0.2 mm print floor. "
        f"From below, the ring starts at no less than {floor_lo:.0f} N at the {win[0]:.0f} % floor — "
        f"{a_margin['initial_with_clamp_at_52_requirement']:.1f}× what 87's (A) needs with a clamp at the form 52 prints, "
        f"(R0 + p) / {f_t:.2f}, which never lets the rim lift while the lift stays at its initial value; a weaker clamp can "
        f"let the rim lift (whether it does depends on the ring's relaxation, not modelled), a lift is taken as not undone "
        f"(conservative), and (A) then rests on the ring keeping "
        f"{retained * 100:.0f} % of that floor for {end} years. Every margin here holds at the assembly temperature.")

    out = {
        "question": "The O-ring's compression reaction over the squeeze window — the datum 52 replaced with a "
                    "generous bound, 73 judged the collar wall against, and 87's (A) needs from below.",
        "source": {"document": "Parker O-Ring Handbook ORD 5700",
                   "figure": "Figure 2-4: .070 Cross Section, p. 2-11 (PDF page 23)",
                   "table": "Table 2-3: O-Ring Compression Force, p. 2-10 — under 25.4 mm: middle third (hardness below "
                            "normal) or upper third (above normal) of the bar",
                   "url": "parker.com/content/dam/Parker-com/Literature/O-Ring-Division-Literature/ORD-5700.pdf",
                   "read": "2026-10-13, vector coordinates of the PDF page (pdftocairo -svg)",
                   "precision_fraction": GRID_PRECISION_FRACTION,
                   "temperature": "§3.8: force decreases very little with temperature except the hardest compounds "
                                  "(N0674-70: −10 % from 24 to 126 °C)",
                   "time": "Parker gives compression set (deflection not recovered after release), not stress "
                           "relaxation — no field-life force"},
        "assumptions": ["log-load linear in squeeze between the chart's rows",
                        "Table 2-3's thirds taken in the log scale the bar is drawn on",
                        "seal length = mean circumference on the groove's inner wall (ring stretched onto it)",
                        "the unconfined bars hold at an 80 % gland fill"],
        "inputs": {"shore_a": SHORE_A, "shore_a_tolerance": SHORE_A_TOLERANCE, "ring_id_mm": RING_ID_MM, "cs_mm": cs,
                   "groove_inner_diameter_mm": round(groove_inner_d, 3),
                   "seal_length_in": round(seal_length_in, 4), "seal_length_mm": round(seal_length_in * IN_MM, 2),
                   "window_pct": win, "nominal_pct": nominal, "chain_pct_as_modelled_by_52": chain,
                   "pogo_pair_N_upper_bound_52": p52, "relax_fraction_at_service_52": f_t,
                   "lug_root_capacity_N_at_print_floor_73": lug_cap, "safety_factor_73": sf73,
                   "o_ring_reaction_N_needed_87": need},
        "chart_70_shore_a_lbf_per_in": {str(p): [round(v, 2) for v in (lbf_per_in(a), lbf_per_in(b))]
                                        for p, (a, b) in sorted(BARS_070_PT[SHORE_A].items())},
        "band": band,
        "inversion": {"reaction_N_at_which_lug_binds_ring_never_relaxes": round(r_bind, 1),
                      "squeeze_pct_band_high_binds": round(sq_bind, 2) if sq_bind else None,
                      "squeeze_pct_band_high_binds_over_transcription": [round(min(sq_bind_reads), 2),
                                                                          round(max(sq_bind_reads), 2)],
                      "squeeze_pct_band_high_exceeds_generous_bound": round(sq_generous, 2) if sq_generous else None},
        "rim_premise_A": {"reaction_N_low_at_window_floor": floor_lo,
                          "needs_87": need,
                          "margin_x": a_margin,
                          "share_retained_needed_with_a_weaker_clamp": retained,
                          "is": "a clamp at the form 52 prints for the ring's own reaction, (R0 + p) / f(20 y), never "
                                "lets the rim lift while the lift stays at L0, so the needed reaction is an initial one; a "
                                "weaker clamp can let the rim lift (it does when R(t) + p > f(t)·C0), a lift is taken as "
                                "not undone (conservative for (A): lifted, the normal force is L; reseated, 2C − L ≥ L), "
                                "and the normal force is then what the ring has left — less than a constant-squeeze "
                                "relaxation datum says, because the ledge PEEK creeping under a lift takes squeeze (52); the friction bound runs through the lug "
                                "ledge (the rim's share can be zero), with µ from 55's dry PEEK–Ti sweep — the ring is "
                                "greased; temperature is not modelled"},
        "missing_data": ["the compound's own compression-load curve at 15–35 % for CS 1.78 (the band spans compounds)",
                         "its stress relaxation over the service life at the capsule's envelope (ISO 3384-type data) — "
                         "it moves 52's requirement between its two ends",
                         "the clamp the bayonet delivers (lug ramp, interference)",
                         "temperature: the PEEK in the clamp loop sits between two Ti faces over the same span, so "
                         "cold unloads the clamp and heat raises it (the loop's compliance sets how fast); the ring's "
                         "own contraction takes squeeze in the cold, and its force below room temperature is not in "
                         "the source — every margin here is at the assembly temperature",
                         "resin swell — any swell raises the reaction (02_02 §3.2: up to 15 % keeps EPDM, 15–25 % is the "
                         "founder's call, above 25 % reopens the material — bench thresholds on free rings, not a "
                         "service bound)"],
        "verdict": verdict,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"  seal length {seal_length_in:.3f} in ({seal_length_in * IN_MM:.1f} mm) · Table 2-3 portion for ID {RING_ID_MM} mm")
    for name, b in band.items():
        m = b["lug_root_margin_x_at_print_floor"]
        print(f"  {name:13s} {b['squeeze_pct']:5.1f} %  reaction {b['reaction_N'][0]:6.1f}–{b['reaction_N'][1]:6.1f} N"
              f"  lug {m['at_assembly']:.2f}× (assembly) … {m['after_20_years_ring_never_relaxes']:.2f}× (no ring relaxation)"
              f"  ring must have lost {b['ring_must_have_lost_share_of_R0_by_year']}")
    print(f"  ring never relaxing: lug binds at {r_bind:.0f} N — band top at {sq_bind:.2f} % "
          f"({min(sq_bind_reads):.2f}–{max(sq_bind_reads):.2f} % over ±4 %)")
    print(f"  (A): floor {floor_lo:.1f} N vs needs {need} → margins {a_margin}; a weaker clamp's ring keeps {retained * 100:.0f} %")
    print(f"\n  VERDICT: {verdict}")
    print(f"  → {OUT_JSON.relative_to(HERE.parent.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
