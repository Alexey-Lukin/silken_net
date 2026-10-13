#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""88 — the O-ring's own reaction: Parker's compression-load band over the squeeze window, and what it does to the
three models that stood on a bound instead (00_07 HW.43, the leg «нижня межа реакції O-ring»; 52 · 73 · 87).

QUESTION. Canon had no O-ring compression force. `52 §rim_datum_creep` put a «deliberately generous» 100 N on it
(lib `GENEROUS_ORING_BOUND_N`) to size the initial bayonet clamp, `73` judged the collar wall against that bound and
called the missing datum «no longer a blocker precisely because the generous bound is covered», and `87`'s premise
(A) needs the same force from BELOW at the end of service. One datum, three roles, opposite signs: `52`/`73` are
threatened by the UPPER reaction at the TOP of the squeeze window, `87` by the LOWER reaction at the FLOOR after the
ring's own relaxation (in-silico rule 15 (c): say what each «≤» bounds and with which sign).

PATHS (rule 15 (a)–(b)). The bayonet is deflection-controlled (02_02 §4.3): the lugs hold the radome at a set Z, so the
ring's squeeze is fixed by the groove depth and the rim datum, and its reaction is a LIFT on the radome that the lugs
carry together with the pogo pair. The reaction scales with squeeze (the tolerance chain of `52`), with the compound's
hardness and formulation (the width of Parker's bar), with time (stress relaxation — not in this source) and weakly
with temperature. `52`'s requirement is P0 ≥ lift / f(t), f(t) the 20-year PEEK relaxation fraction, checked against
`73`'s lug-root capacity; `87`'s end-of-life capacity is µ·lift.

SOURCE. Parker O-Ring Handbook ORD 5700, Figure 2-4 «.070 Cross Section», p. 2-11 (PDF page 23 of
parker.com/content/dam/Parker-com/Literature/O-Ring-Division-Literature/ORD-5700.pdf, read 2026-10-13):
«Compression Load per Linear Inch of Seal — Pounds» against «Percent Compression», one bar per Shore A hardness
50–90 at 5 · 10 · 20 · 30 · 40 %. The bar ends below are the VECTOR coordinates of the PDF page (pdftocairo -svg), in pt,
converted on the chart's own decade lines (0.1 at x = 113.50, 1000 at x = 541.14) — a transcription, not an eye
reading. Its precision: the plot's minor gridlines depart from a true log scale by up to ~1.6 pt, ≈ ±4 % in load.
§3.8 (p. 3-9): the anticipated load «is not fixed, but is a range of values» from a large number of tests, Table 2-3
picks the portion of the bar when the hardness is known accurately, and service temperature lowers the force «very
little except for the hardest compounds» (N0674-70: −10 % from 24 to 126 °C). §2.4.11 defines compression set as the
same relaxation, 100 % meaning the seal «no longer exerts a force» — but Parker reports it only after 70 h at 100 °C,
so the END-OF-SERVICE reaction is NOT read from this source.

ASSUMPTIONS (ours, named, not Parker's): load interpolated log-linearly in squeeze between the chart's rows; the seal
length is the mean circumference of the ring stretched onto the groove's inner wall (AS568-019 — 02_02 §3.2); the
chart's bars hold at our 80 % gland fill (confinement raises the load only near a full gland).

CAN show: the reaction band (N) at the window floor, at both ends of the chain `52` models, at the nominal and at the
window top; the share of its initial reaction the ring must keep for 87's (A); the clamp 52's requirement needs with the
band's upper end, against 73's lug-root capacity, the squeeze at which the lug root starts to bind, and the collar wall
strength would then ask for.
CANNOT show: the ring's stress relaxation over 20 years in the field (a compound datum — ISO 3384-type data from the
vendor); our compound's own curve (Parker's bar spans compounds); the clamp the bayonet actually delivers; the cold
side, where EPDM stiffens and the reaction rises.
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


def lbf_per_in(x_pt: float) -> float:
    return 0.1 * 10 ** ((x_pt - X_DECADE_0P1) / PT_PER_DECADE)


def band_at(pct: float, shore: int = SHORE_A) -> tuple[float, float]:
    """(low, high) lbf per inch of seal at `pct` compression — log-linear between the chart's rows (our assumption)."""
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


def squeeze_where(load_lbf_in: float, end: int, lo: float, hi: float) -> float | None:
    """The compression (%) at which the bar's `end` (0 low, 1 high) reaches `load_lbf_in` — bisection, or None."""
    f = lambda p: band_at(p)[end] - load_lbf_in  # noqa: E731
    if f(lo) > 0 or f(hi) < 0:
        return None
    for _ in range(80):
        mid = 0.5 * (lo + hi)
        lo, hi = (lo, mid) if f(mid) > 0 else (mid, hi)
    return 0.5 * (lo + hi)


def wall_for_force(rows: list[dict], force_n: float) -> float:
    """73's lug-root breakeven is linear in the wall (pure shear); interpolate its own rows, extrapolate below none."""
    pts = sorted((r["wall_mm"], r["breakeven_force_N"]) for r in rows)
    for (w0, f0), (w1, f1) in itertools.pairwise(pts):
        if f0 <= force_n <= f1:
            return w0 + (force_n - f0) * (w1 - w0) / (f1 - f0)
    w0, f0 = pts[0]
    return w0 * force_n / f0


def main() -> int:
    banner("O-ring reaction — Parker Figure 2-4 over the squeeze window: 52's clamp · 73's lug root · 87's (A)")
    z52 = json.loads(ZSTACK52.read_text(encoding="utf-8"))
    c73 = json.loads(COLLAR73.read_text(encoding="utf-8"))
    s87 = json.loads(SWAY87.read_text(encoding="utf-8"))

    cs = z52["springs"]["oring"]["cs_mm"]
    groove_inner_d = 2.0 * z52["applied_gland"]["flange_groove_r_mm"][0]
    seal_length_in = math.pi * (groove_inner_d + cs) / IN_MM
    win = z52["depth_tolerance_budget"]["intersection_window_pct"]
    nominal = z52["depth_tolerance_budget"]["nominal_pct"]
    chain = z52["parker_face_reconciliation"]["band_at_recommended_pct"]
    points = {"window_floor": win[0], "chain_low": chain[0], "nominal": nominal, "chain_high": chain[1],
              "window_top": win[1]}

    rim = z52["rim_datum_creep"]
    pogo, f_t = rim["pogo_pair_force_N_upper_bound"], rim["relax_fraction_at_service"]
    lug_cap = c73["verdict"]["capacity_at_print_floor_N"]
    sf73 = c73["safety_factor"]
    lug_rows = c73["case_b_lug_root_shear"]["rows"]
    o_ring_needed = max(r["A_rim"]["o_ring_force_N_needed_at_end_of_life"] for r in s87["by_slope_reading"].values())

    band = {}
    for name, pct in points.items():
        lo, hi = band_at(pct)
        need_hi = (pogo + hi * seal_length_in * LBF_N) / f_t
        band[name] = {"squeeze_pct": pct,
                      "lbf_per_in": [round(lo, 2), round(hi, 2)],
                      "reaction_N": [round(lo * seal_length_in * LBF_N, 1), round(hi * seal_length_in * LBF_N, 1)],
                      "required_initial_clamp_N_at_band_high": round(need_hi, 1),
                      "lug_root_margin_x_at_print_floor": round(lug_cap / need_hi, 2),
                      "collar_wall_strength_asks_mm": round(max(wall_for_force(lug_rows, need_hi), 0.0), 3)}

    # Inversion (no datum needed): the reaction at which 52's requirement meets 73's capacity at the print floor.
    r_bind = lug_cap * f_t - pogo
    bind_lbf_in = r_bind / LBF_N / seal_length_in
    sq_bind_hi = squeeze_where(bind_lbf_in, 1, 5.0, 40.0)
    sq_bind_lo = squeeze_where(bind_lbf_in, 0, 5.0, 40.0)
    gen_lbf_in = GENEROUS_ORING_BOUND_N / LBF_N / seal_length_in
    sq_generous_hi = squeeze_where(gen_lbf_in, 1, 5.0, 40.0)
    sq_generous_lo = squeeze_where(gen_lbf_in, 0, 5.0, 40.0)

    floor_lo = band["window_floor"]["reaction_N"][0]
    retained_needed = o_ring_needed / floor_lo
    top = band["window_top"]
    chain_hi = band["chain_high"]
    nom = band["nominal"]

    verdict = (
        f"The «generous» {GENEROUS_ORING_BOUND_N:.0f} N is not an upper bound: Parker's 70 Shore A bar for the .070 section "
        f"puts the ring's reaction at {nom['reaction_N'][0]:.0f}–{nom['reaction_N'][1]:.0f} N at the {nominal:.1f} % nominal "
        f"and up to {top['reaction_N'][1]:.0f} N at the {win[1]:.0f} % window top, and the band's high end passes "
        f"{GENEROUS_ORING_BOUND_N:.0f} N already at {sq_generous_hi:.1f} % squeeze. With that high end, 52's requirement "
        f"(lift / {f_t:.2f}) asks {nom['required_initial_clamp_N_at_band_high']:.0f} N at the nominal — the lug root "
        f"still carries it at the print floor ({nom['lug_root_margin_x_at_print_floor']:.2f}×, SF {sf73:.0f} inside) — "
        f"but {top['required_initial_clamp_N_at_band_high']:.0f} N at the window top "
        f"({top['lug_root_margin_x_at_print_floor']:.2f}×): above {sq_bind_hi:.1f} % squeeze a compound at the hard end of "
        f"the bar makes strength, not printability, size the collar wall — {top['collar_wall_strength_asks_mm']:.2f} mm "
        f"at the window top against the 0.2 mm print floor; the chain 52 models today ends at {chain[1]:.1f} % "
        f"({chain_hi['lug_root_margin_x_at_print_floor']:.2f}×). From below, the ring starts at no less than "
        f"{floor_lo:.0f} N at the {win[0]:.0f} % floor, so 87's (A) holds at the end of service only if the ring keeps "
        f"{retained_needed * 100:.0f} % of its initial reaction after 20 years — a compound datum Parker does not give.")

    out = {
        "question": "The O-ring's compression reaction over the squeeze window — the datum 52 replaced with a "
                    "generous bound, 73 judged the collar wall against, and 87's (A) needs from below.",
        "source": {"document": "Parker O-Ring Handbook ORD 5700",
                   "figure": "Figure 2-4: .070 Cross Section, p. 2-11 (PDF page 23)",
                   "url": "parker.com/content/dam/Parker-com/Literature/O-Ring-Division-Literature/ORD-5700.pdf",
                   "read": "2026-10-13, vector coordinates of the PDF page (pdftocairo -svg)",
                   "precision_fraction": GRID_PRECISION_FRACTION,
                   "temperature": "§3.8: force decreases very little with temperature except the hardest compounds "
                                  "(N0674-70: −10 % from 24 to 126 °C)",
                   "time": "§2.4.11: compression set is the same relaxation (100 % = no force), reported only after "
                           "70 h at 100 °C — no field-life figure"},
        "assumptions": ["log-load linear in squeeze between the chart's rows",
                        "seal length = mean circumference on the groove's inner wall (ring stretched onto it)",
                        "the unconfined bars hold at an 80 % gland fill"],
        "inputs": {"shore_a": SHORE_A, "shore_a_tolerance": SHORE_A_TOLERANCE, "cs_mm": cs,
                   "groove_inner_diameter_mm": round(groove_inner_d, 3),
                   "seal_length_in": round(seal_length_in, 4), "seal_length_mm": round(seal_length_in * IN_MM, 2),
                   "window_pct": win, "nominal_pct": nominal, "chain_pct_as_modelled_by_52": chain,
                   "pogo_pair_N_upper_bound": pogo, "relax_fraction_at_service_52": f_t,
                   "lug_root_capacity_N_at_print_floor_73": lug_cap, "safety_factor_73": sf73,
                   "o_ring_force_N_needed_end_of_life_87": o_ring_needed},
        "chart_70_shore_a_lbf_per_in": {str(p): [round(v, 2) for v in (lbf_per_in(a), lbf_per_in(b))]
                                        for p, (a, b) in sorted(BARS_070_PT[SHORE_A].items())},
        "band": band,
        "inversion": {"reaction_N_at_which_lug_binds": round(r_bind, 1),
                      "squeeze_pct_band_high_binds": round(sq_bind_hi, 2) if sq_bind_hi else None,
                      "squeeze_pct_band_low_binds": round(sq_bind_lo, 2) if sq_bind_lo else None,
                      "squeeze_pct_band_high_exceeds_generous_bound": round(sq_generous_hi, 2) if sq_generous_hi else None,
                      "squeeze_pct_band_low_exceeds_generous_bound": round(sq_generous_lo, 2) if sq_generous_lo else None},
        "end_of_service": {"initial_reaction_N_low_at_window_floor": floor_lo,
                           "o_ring_force_N_needed_87": o_ring_needed,
                           "retained_fraction_needed": round(retained_needed, 3),
                           "is": "a requirement on the compound's stress relaxation over 20 years, not a force this "
                                 "source gives"},
        "missing_data": ["the compound's own compression-load curve at 19–30 % for CS 1.78 (Parker's bar spans "
                         "compounds)",
                         "its stress relaxation over the service life at the capsule's envelope (ISO 3384-type data)",
                         "the cold-side stiffening of EPDM (raises the reaction; adverse for the lug, favourable for "
                         "(A))"],
        "verdict": verdict,
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"  seal length {seal_length_in:.3f} in ({seal_length_in * IN_MM:.1f} mm) on the groove's inner wall")
    for name, b in band.items():
        print(f"  {name:13s} {b['squeeze_pct']:5.1f} %  reaction {b['reaction_N'][0]:6.1f}–{b['reaction_N'][1]:6.1f} N"
              f"  clamp@high {b['required_initial_clamp_N_at_band_high']:6.1f} N"
              f"  lug {b['lug_root_margin_x_at_print_floor']:.2f}×  wall {b['collar_wall_strength_asks_mm']:.3f} mm")
    low_bind = f"at {sq_bind_lo:.1f} %" if sq_bind_lo else "never within the chart"
    print(f"  lug root binds at a reaction of {r_bind:.0f} N — band high at {sq_bind_hi:.1f} %, band low {low_bind}")
    print(f"  (A): {floor_lo:.0f} N initially at the floor, {o_ring_needed:.2f} N needed at the end of service → keep "
          f"{retained_needed * 100:.0f} %")
    print(f"\n  VERDICT: {verdict}")
    print(f"  → {OUT_JSON.relative_to(HERE.parent.parent.parent)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
