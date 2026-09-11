#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 — Mechanical check of the central bus rod (buckling + sway fatigue), the second-half de-risk of
the monolithic-bus idea after the thermal bridge (script 54).

A monolithic Ti bus rises from the anode shank, through the PEEK gap and the cathode bore, to the pogo pad.

⛔ DIAMETER — THE ROD, NEVER THE CHANNEL. Canon 01_01 §1.4 freezes three dimensions and only one of
   them is metal: rod Ø1.0 · cathode channel Ø1.3 · liner 0.15. D_BUS here is the ROD, imported from
   lib.constants (one home). Substituting the channel inflates every fatigue SF ×2.2 (σ ∝ 1/d³) and
   flips the load-bearing conclusion: at Ø1.3 the unsupported branch reads 'marginal for the soft
   alloys', at Ø1.0 it is a predicted FAILURE for Ta and CP-Ti and infinite life for NOBODY. That is
   the whole reason the liner's support role is not optional — see the verdict.

Two mechanical questions the monolithic idea raises (01_01 §4.1 / 00_07 HW.34):
  1. Buckling — the pogo pin presses the rod tip axially (~1 N, 02_02 §2.2). Does a slender rod buckle?
  2. Sway fatigue — over 20-25 yr (~10^8-10^9 sway cycles) a CYCLIC lateral load bends the rod. The
     defensible driver is pogo-contact friction drag (µ·F_pogo) as the capsule sways and the pin slides
     on the pad; PEEK-sleeve flex adds a secondary base motion. Does the rod survive infinite-life?

KEY COUPLING (the whole point): the unsupported free length is what hurts. The SAME insulating liner the
bus needs through the cathode bore (short-circuit guard, HW.34 sub-2) also LATERALLY SUPPORTS the rod →
collapses the free length from the full protrusion to just the PEEK gap. So insulation = support =
fatigue-fix are ONE design item. This script quantifies "supported vs unsupported" and shows the liner
is what makes fatigue comfortable for every alloy (and that the weaker bake-off alloys — Ta, CP-Ti —
have the least margin, the same ranking as the thermal side).

FABRICATION BRANCH — the second thing that moves every SF, and it is a VERDICT, not a parameter.
  ⚖️ 2026-09-10 (00_07 HW.34) ratified the rod as a WELDED cold-drawn wire, so the as-built knockdown
  `AS_PRINTED_DERATE` no longer applies to the shipped part. Both columns are printed side by side —
  `printed` (superseded) and `welded` (shipped) — because the fabrication choice is what moves the
  still-open LINING verdict, and a reader handed one column cannot see that it moved.
  ⛔ THE MODEL HAS NO WELD SEAM. It is a homogeneous cantilever, while the ratified rod carries a
  heat-affected zone in the ROOT — exactly where the bending moment peaks. So the doubled SF describes
  the WIRE and says NOTHING about the JOINT; the seam is a separate open question (00_07 HW.34), and
  quoting a welded-column SF as if it covered the weld is the error this note exists to prevent.
  ⚠️ Likewise absent from canon: as-printed `Sa` and the printed diameter tolerance — `DMLS Ti ±0.3`
  is an AXIAL Z-stack contribution, not a diametral one.

Per-alloy endurance is keyed to yield (σ_e ≈ k·σ_y) from lib ALLOY_PROPERTIES — ties HW.34 ↔ HW.24.
No FEA — slender-beam closed form (Euler buckling + cantilever bending + S-N endurance ratio).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import ALLOY_PROPERTIES, CACHE_DIR, D_BUS_ROD_MM, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Bus geometry (mm) — the ROD, not the Ø1.3 cathode channel it threads ──
# ⛔ Do not substitute the channel here: σ ∝ 1/d³, so Ø1.3 inflates every fatigue SF ×2.2 and turns a
#    predicted failure into a comfortable margin. One home for the value: lib.constants (01_01 §1.4).
D_BUS = D_BUS_ROD_MM
# Free (laterally UNSUPPORTED) cantilever length in each case:
L_FREE_UNSUP = 36.0   # mm — no liner: gap 6 + cathode bore ~14 + flange/pad standoff ~16 = full protrusion
L_FREE_SUP = 6.0      # mm — liner supports the bore run → only the PEEK gap is unsupported

# ── Loads ──
# ── Channel run (mm from the anode root) — the wall that the two branches above IGNORE ──
# Both L_FREE_* above are free-cantilever idealisations: they assume NO wall anywhere over the span.
# The real rod threads a Ø1.3 bore, so a branch that leaves a gap is neither of them — see §4 below.
# ⚠️ The run length is read CONSERVATIVELY (shorter = less room for contact to happen): the model's own
# decomposition of L_FREE_UNSUP says "cathode bore ~14", while cem/cathode_flange.json gives
# shank 14 + flange 3 = 17. Taking 14 makes the contact finding harder to reach, not easier.
CHANNEL_START_MM = L_FREE_SUP      # the PEEK gap ends and the bore begins
CHANNEL_LEN_MM = 14.0
D_CHANNEL_MM = 1.3                 # cathode channel Ø, canon 01_01 §1.4 (frozen)
# Radial free play left by each insulation branch, measured on the ROD side.
# ⛔ `liner` is NOMINALLY zero — that is the F3 gate's arithmetic (1.0 + 2×0.15 ≤ 1.3), not an assembly
#    clearance; the real allocation is an open ⚖️ (00_07 HW.34). A few µm is carried so the regime is
#    computed rather than asserted, and the conclusion does not depend on which µm-value you pick.
INSULATION_OPTIONS = (
    ("conformal 10 µm film", 0.010),
    ("conformal TiO2 ~5 µm", 0.005),
    ("PEEK liner 0.15 mm", 0.1475),   # 2.5 µm radial assembly play — µm-scale by construction
)

F_POGO_N = 1.0        # N — pogo spring force on the rod tip (~100 g, 02_02 §2.2)
MU_CONTACT = 0.3      # Au↔Ti dry sliding friction (the cyclic lateral drag = µ·F_pogo); swept 0.2-0.5
MU_SWEEP = (0.2, 0.3, 0.4, 0.5)

# ── Material / fatigue ──
E_TI = 110e9          # Pa — Ti-6Al-4V Young's modulus (β-Ti lower, but E barely moves buckling here)
# Endurance limit ≈ fatigue ratio × yield, then knocked down for AS-PRINTED SLM surface/porosity
# (HIP + machining recovers most of it — the bus tip is gold-plated/finished anyway). Conservative.
ENDURANCE_OVER_YIELD = 0.45   # wrought-Ti fatigue ratio (σ_e/σ_y ≈ 0.4-0.5)
AS_PRINTED_DERATE = 0.5       # SLM as-built knockdown (rough surface + sub-surface porosity)
WROUGHT_DERATE = 1.0          # cold-drawn wire carries no as-built knockdown at all
# ⚖️ HW.34 ratified 2026-09-10: the rod is a WELDED cold-drawn wire, so `welded` is the SHIPPED
# branch and `printed` is kept only to show what the fabrication choice bought. Both columns are
# emitted on purpose — the fabrication choice moves the LINER verdict, and a reader given one
# column cannot see that. [00_07 HW.34]
FAB_BRANCHES = (("printed", AS_PRINTED_DERATE), ("welded", WROUGHT_DERATE))
SHIPPED_BRANCH = "welded"
INFINITE_LIFE_SF = 2.0        # the SF line this script calls "infinite life"

MM_M = 1e-3


def second_moment_m4(d_mm: float) -> float:
    r = (d_mm / 2.0) * MM_M
    return np.pi / 4.0 * r ** 4


def euler_buckling_N(length_mm: float) -> float:
    """Fixed-free column (base fixed at the shank, tip pogo-contacted ≈ free): K=2."""
    i_area = second_moment_m4(D_BUS)
    le = 2.0 * (length_mm * MM_M)
    return (np.pi ** 2) * E_TI * i_area / (le ** 2)


def bending_stress_MPa(force_lat_N: float, length_mm: float) -> float:
    """Max fibre stress at the root of a cantilever with a transverse TIP load: σ = F·L·c/I."""
    i_area = second_moment_m4(D_BUS)
    c = (D_BUS / 2.0) * MM_M
    return force_lat_N * (length_mm * MM_M) * c / i_area / 1e6


def tip_load_deflection_mm(force_lat_N: float, x_mm: float, length_mm: float) -> float:
    """Free-cantilever deflection at x under a TRANSVERSE TIP load: δ(x) = F·x²·(3L−x)/(6EI).

    Same F, L, E, I as the bending-stress model above — this is that model read as a SHAPE rather
    than as a root stress, which is the one question it was never asked.
    """
    i_area = second_moment_m4(D_BUS)
    x, ell = x_mm * MM_M, length_mm * MM_M
    return force_lat_N * x ** 2 * (3.0 * ell - x) / (6.0 * E_TI * i_area) / MM_M


def first_wall_contact_mm(force_lat_N: float, radial_play_mm: float, length_mm: float) -> float:
    """Distance from the root at which the FREE deflection first equals the radial play.

    Bisection on a monotonic function — no solver dependency. Returns `length_mm` if the rod never
    takes up the play over the whole span (i.e. it really is a free cantilever).
    """
    if tip_load_deflection_mm(force_lat_N, length_mm, length_mm) <= radial_play_mm:
        return length_mm
    lo, hi = 0.0, length_mm
    for _ in range(60):
        mid = (lo + hi) / 2.0
        if tip_load_deflection_mm(force_lat_N, mid, length_mm) < radial_play_mm:
            lo = mid
        else:
            hi = mid
    return lo


def endurance_MPa(yield_MPa: float, derate: float = AS_PRINTED_DERATE) -> float:
    """σ_e ≈ fatigue-ratio × yield, knocked down only if the rod is AS-PRINTED.

    `derate` is the fabrication branch, not a tuning knob: 0.5 for an SLM as-built surface,
    1.0 for cold-drawn wire. ⛔ It describes the WIRE and says nothing about the WELD.
    """
    return ENDURANCE_OVER_YIELD * derate * yield_MPa


def main() -> int:
    banner("HW.34 — Bus rod mechanical check (buckling + sway fatigue)")
    print(f"  Rod Ø{D_BUS:.1f} mm; free length unsupported {L_FREE_UNSUP:.0f} mm (no liner) vs "
          f"supported {L_FREE_SUP:.0f} mm (liner = the insulation, HW.34 sub-2)")
    print(f"  Pogo {F_POGO_N:.1f} N axial; cyclic lateral drag = µ·F_pogo (µ={MU_CONTACT:.1f})")
    print(f"  σ_e ≈ {ENDURANCE_OVER_YIELD:.2f}·derate·σ_y — derate {AS_PRINTED_DERATE:.2f} printed "
          f"vs {WROUGHT_DERATE:.2f} welded (drawn wire); SHIPPED = {SHIPPED_BRANCH}, weld seam NOT modelled")

    # ── 1. Buckling under the pogo axial force ──
    banner("Buckling (pogo axial force on a slender rod)")
    for label, lf in [("unsupported", L_FREE_UNSUP), ("supported (liner)", L_FREE_SUP)]:
        p_cr = euler_buckling_N(lf)
        print(f"  {label:<20s} L={lf:>4.0f} mm → P_cr = {p_cr:6.1f} N → SF = {p_cr / F_POGO_N:5.1f}× vs {F_POGO_N:.0f} N pogo")
    print("  → No buckling concern (pogo is 1 N; even unsupported the critical load is ≫ that).")

    # ── 2. Sway fatigue: bending stress vs per-alloy endurance, supported vs unsupported ──
    banner("Sway fatigue — bending stress vs endurance (per bake-off alloy, ties HW.24)")
    f_lat = MU_CONTACT * F_POGO_N
    sig_unsup = bending_stress_MPa(f_lat, L_FREE_UNSUP)
    sig_sup = bending_stress_MPa(f_lat, L_FREE_SUP)
    print(f"  Cyclic lateral drag F = µ·F_pogo = {f_lat:.2f} N → root stress: "
          f"unsupported {sig_unsup:.1f} MPa · supported {sig_sup:.1f} MPa\n")
    print(f"  {'alloy (= bus, monolithic)':<24s} {'σ_y':>5s} | {'σ_e pr':>6s} {'SFu pr':>7s} "
          f"{'life pr':>10s} | {'σ_e wl':>6s} {'SFu wl':>7s} {'life wl':>10s}")
    print(f"  {'-' * 96}")

    def life_label(sf: float) -> str:
        # THREE tiers, not two: below SF 1.0 the rod is not "marginal", it is predicted to fail.
        # A two-tier label printed "marginal" for SF 0.71 — a word with no measurer behind it.
        if sf >= INFINITE_LIFE_SF:
            return "∞ (>SF 2)"
        return "⚠ marginal" if sf >= 1.0 else "✗ FAILS"

    alloy_rows = []
    for name, props in sorted(ALLOY_PROPERTIES.items(), key=lambda kv: -kv[1]["yield_MPa"]):
        sy = props["yield_MPa"]
        row = {"alloy": name, "yield_MPa": sy}
        for branch, derate in FAB_BRANCHES:
            se = endurance_MPa(sy, derate)
            row[f"endurance_MPa_{branch}"] = round(se, 1)
            row[f"sf_unsupported_{branch}"] = round(se / sig_unsup, 2)
            row[f"sf_supported_{branch}"] = round(se / sig_sup, 2)
            row[f"unsupported_infinite_life_{branch}"] = bool(se / sig_unsup >= INFINITE_LIFE_SF)
            row[f"unsupported_predicted_failure_{branch}"] = bool(se / sig_unsup < 1.0)
        # ⛔ TWO decimals, not one: CP-Ti lands at 1.96 and rounds to "2.0" at one decimal, i.e. the
        # cell would print the threshold itself while its own label says "marginal" — a table
        # contradicting itself in adjacent columns, and the reader would trust the number.
        print(f"  {name:<24s} {sy:>5.0f} | {row['endurance_MPa_printed']:>6.0f} "
              f"{row['sf_unsupported_printed']:>6.2f}× {life_label(row['sf_unsupported_printed']):>10s} | "
              f"{row['endurance_MPa_welded']:>6.0f} {row['sf_unsupported_welded']:>6.2f}× "
              f"{life_label(row['sf_unsupported_welded']):>10s}")
        alloy_rows.append(row)

    # Everything below is DERIVED from alloy_rows. A hardcoded range here mirrored the numbers above and
    # drifted the moment the diameter moved — the table said one thing and its own summary another.
    def spread(key: str) -> tuple[float, float]:
        vals = [r[key] for r in alloy_rows]
        return min(vals), max(vals)

    branch_summary = {}
    for branch, _ in FAB_BRANCHES:
        uns_lo, uns_hi = spread(f"sf_unsupported_{branch}")
        sup_lo_b, sup_hi_b = spread(f"sf_supported_{branch}")
        failing_b = [r["alloy"] for r in alloy_rows if r[f"unsupported_predicted_failure_{branch}"]]
        marginal_b = [r["alloy"] for r in alloy_rows
                      if not r[f"unsupported_predicted_failure_{branch}"]
                      and not r[f"unsupported_infinite_life_{branch}"]]
        infinite_b = [r["alloy"] for r in alloy_rows if r[f"unsupported_infinite_life_{branch}"]]
        branch_summary[branch] = {
            "sf_unsupported_range": [uns_lo, uns_hi], "sf_supported_range": [sup_lo_b, sup_hi_b],
            "unsupported_predicted_failure": failing_b, "unsupported_marginal": marginal_b,
            "unsupported_infinite_life": infinite_b,
            "unsupported_infinite_life_for_all": len(infinite_b) == len(alloy_rows),
            "supported_infinite_life_for_all": all(r[f"sf_supported_{branch}"] >= INFINITE_LIFE_SF
                                                   for r in alloy_rows),
        }
    shipped = branch_summary[SHIPPED_BRANCH]
    sup_lo, sup_hi = shipped["sf_supported_range"]
    uns_lo, uns_hi = shipped["sf_unsupported_range"]
    failing = shipped["unsupported_predicted_failure"]
    marginal = shipped["unsupported_marginal"]

    for branch, _ in FAB_BRANCHES:
        b = branch_summary[branch]
        tag = " (SHIPPED, ⚖️ 2026-09-10)" if branch == SHIPPED_BRANCH else " (superseded fabrication)"
        print(f"\n  → {branch.upper()}{tag}")
        print(f"      SUPPORTED (liner): SF {b['sf_supported_range'][0]:.1f}-{b['sf_supported_range'][1]:.1f}× — "
              f"{'infinite life for EVERY alloy' if b['supported_infinite_life_for_all'] else 'NOT infinite life for every alloy'}.")
        print(f"      UNSUPPORTED: SF {b['sf_unsupported_range'][0]:.1f}-{b['sf_unsupported_range'][1]:.1f}× — "
              f"infinite life for {len(b['unsupported_infinite_life'])}/{len(alloy_rows)}; "
              f"predicted FAILURE for {', '.join(b['unsupported_predicted_failure']) or 'none'}; "
              f"marginal for {', '.join(b['unsupported_marginal']) or 'none'}.")
    print("    Same ranking as the thermal side → the leading bake-off candidates win on both.")

    # ── 3. Robustness: sweep the friction coefficient (the cyclic-load assumption) ──
    banner("Robustness — friction-coefficient sweep (the cyclic-drag assumption)")
    sy_4v = ALLOY_PROPERTIES["Ti-6Al-4V"]["yield_MPa"]
    se_4v = {b: endurance_MPa(sy_4v, d) for b, d in FAB_BRANCHES}
    print(f"  {'µ':>5s} {'F_lat (N)':>10s} {'σ unsup':>9s} {'σ sup':>8s} | "
          f"{'SFu pr':>7s} {'SFs pr':>7s} | {'SFu wl':>7s} {'SFs wl':>7s}   (4V)")
    print(f"  {'-' * 82}")
    mu_rows = []
    for mu in MU_SWEEP:
        fl = mu * F_POGO_N
        su = bending_stress_MPa(fl, L_FREE_UNSUP)
        ss = bending_stress_MPa(fl, L_FREE_SUP)
        row = {"mu": mu, "f_lat_N": round(fl, 3), "sigma_unsup_MPa": round(su, 1),
               "sigma_sup_MPa": round(ss, 1)}
        for branch, _ in FAB_BRANCHES:
            row[f"sf_unsup_4v_{branch}"] = round(se_4v[branch] / su, 2)
            row[f"sf_sup_4v_{branch}"] = round(se_4v[branch] / ss, 2)
        print(f"  {mu:>5.1f} {fl:>10.2f} {su:>7.1f} MPa {ss:>5.1f} MPa | "
              f"{row['sf_unsup_4v_printed']:>6.1f}× {row['sf_sup_4v_printed']:>6.1f}× | "
              f"{row['sf_unsup_4v_welded']:>6.1f}× {row['sf_sup_4v_welded']:>6.1f}×")
        mu_rows.append(row)
    worst_mu = max(MU_SWEEP)
    for branch, _ in FAB_BRANCHES:
        worst_sup = min(r[f"sf_sup_4v_{branch}"] for r in mu_rows)
        worst_uns = min(r[f"sf_unsup_4v_{branch}"] for r in mu_rows)
        print(f"  → {branch}: at µ={worst_mu:.1f} the SUPPORTED rod holds SF {worst_sup:.1f}× (4V, "
              f"{'above' if worst_sup >= INFINITE_LIFE_SF else 'BELOW'} the SF-2 line); "
              f"BARE it falls to {worst_uns:.1f}× "
              f"({'still above' if worst_uns >= INFINITE_LIFE_SF else 'BELOW'}).")
    print("    The liner is the robust mitigation in BOTH branches; bare-cantilever margin erodes with µ.")

    # ── 4. Which regime each insulation branch actually puts the rod in ──────────────────────────
    # 🔴 The question §2 never asks. Both L_FREE_* are free cantilevers: no wall anywhere. But the rod
    # threads a Ø1.3 bore, so an insulation branch that leaves play is NEITHER idealisation — it is a
    # gap-limited beam. Which one it is decides whether the SF printed above describes it at all.
    banner("Clearance regime — does the rod REACH the channel wall? (the branch the SF table omits)")
    channel_end = CHANNEL_START_MM + CHANNEL_LEN_MM
    print(f"  Channel Ø{D_CHANNEL_MM:.1f} runs {CHANNEL_START_MM:.0f}→{channel_end:.0f} mm from the root "
          f"(conservative length {CHANNEL_LEN_MM:.0f} mm; CEM shank+flange would give 17).")
    print(f"  {'insulation branch':<24s} {'radial play':>11s} {'first contact, mm from root':>30s}   regime")
    print(f"  {'-' * 92}")
    regimes = []
    for label, t_mm in INSULATION_OPTIONS:
        play = (D_CHANNEL_MM - (D_BUS + 2.0 * t_mm)) / 2.0
        contacts = {}
        for mu in MU_SWEEP:
            contacts[mu] = round(first_wall_contact_mm(mu * F_POGO_N, play, L_FREE_UNSUP), 2)
        lo_x, hi_x = min(contacts.values()), max(contacts.values())
        # Bears on the wall INSIDE the bore on every µ the model itself sweeps ⇒ not a free cantilever.
        bears = all(x < channel_end for x in contacts.values())
        at_mouth = all(x <= CHANNEL_START_MM for x in contacts.values())
        regime = ("supported at the bore mouth" if at_mouth
                  else "GAP-LIMITED — bears inside the bore" if bears
                  else "free cantilever (never reaches the wall)")
        print(f"  {label:<24s} {play * 1000:>8.1f} µm {f'{lo_x:.2f}–{hi_x:.2f}':>30s}   {regime}")
        regimes.append({"branch": label, "coating_or_liner_mm": t_mm,
                        "radial_play_mm": round(play, 4), "first_contact_mm_by_mu": contacts,
                        "bears_inside_bore": bool(bears), "supported_at_mouth": bool(at_mouth),
                        "regime": regime})
    gap_limited = [r["branch"] for r in regimes if r["bears_inside_bore"] and not r["supported_at_mouth"]]
    # ⛔ DERIVED, never typed — this sentence is the ground the lining verdict stands on.
    print(f"\n  → The free-cantilever SF above describes NO branch that bears on the wall: "
          f"{', '.join(gap_limited) or 'none'}.")
    print("    For those the effective span is a FRACTION of the 36 mm span priced above, so the")
    print("    unsupported SF is a number for a configuration that does not exist — while the contact")
    print("    it implies is FORCED by geometry on every µ, which is a wear question, not a fatigue one.")

    # ── Verdict ──
    banner("Verdict")
    p_cr_unsup = euler_buckling_N(L_FREE_UNSUP)
    print(f"  1. Buckling: non-issue (P_cr {p_cr_unsup:.0f} N ≫ 1 N pogo, SF {p_cr_unsup / F_POGO_N:.0f}× even unsupported).")
    print(f"  2. Sway fatigue on the SHIPPED ({SHIPPED_BRANCH}) rod: supported SF {sup_lo:.1f}-{sup_hi:.1f}×; "
          f"unsupported FAILS for {', '.join(failing) or 'no alloy'}.")
    # ⛔ The sentence below is DERIVED, never typed: a hand-written "all alloys clear it" is exactly the
    # claim that goes stale the moment an input moves, and this file's own inputs just moved.
    n_inf = len(shipped["unsupported_infinite_life"])
    clears_all = shipped["unsupported_infinite_life_for_all"]
    print(f"  3. ⚖️ ANSWER TO THE OPEN LINING VERDICT — bare, the drawn wire "
          f"{'clears EVERY alloy' if clears_all else 'does NOT clear every alloy'}:")
    print(f"     unsupported infinite life is reached by {n_inf}/{len(alloy_rows)} "
          f"({', '.join(shipped['unsupported_infinite_life']) or 'none'}); still short of the SF-2 line: "
          f"{', '.join(marginal) or 'none'}; predicted failure: {', '.join(failing) or 'none'}.")
    print("     Dropping the as-printed derate lifted the soft alloys OUT of predicted failure; whether"
          if not clears_all else "     Every alloy clears it bare, so the support motive is spent;")
    print("     it also carried them over the infinite-life line is what the two lists above answer."
          if not clears_all else "     the liner's remaining ground is insulation alone.")
    print("  4. ⛔ And the ×2 belongs to the WIRE, never to the JOINT: this model is a homogeneous")
    print("     cantilever with NO WELD SEAM, while the weld sits in the root — the point of maximum")
    print("     bending moment. The seam is unmodelled here and must be judged on its own (00_07 HW.34).")
    print("  5. Per-alloy fatigue margin tracks yield (β-Ti/15Zr/4V > CP-Ti > Ta) — SAME ranking as the")
    print("     thermal bridge → the leading bake-off candidates (HW.24) win on both axes, no tension.")
    print("  6. Caveat: the cyclic-load amplitude (pogo friction + PEEK flex) is an ESTIMATE — the real")
    print("     sway spectrum is bench/field (00_02). Comparative supported-vs-unsupported is robust.")

    out = {
        "method": "slender-beam closed form — Euler buckling (fixed-free) + cantilever tip-load bending "
                  "+ S-N endurance ratio (σ_e ≈ k·σ_y, as-printed derate). No FEA.",
        "geometry_mm": {"bus_dia": D_BUS, "free_len_unsupported": L_FREE_UNSUP, "free_len_supported": L_FREE_SUP},
        "loads": {"pogo_axial_N": F_POGO_N, "friction_mu": MU_CONTACT, "lateral_drag_N": MU_CONTACT * F_POGO_N},
        "fatigue_model": {"endurance_over_yield": ENDURANCE_OVER_YIELD,
                          "as_printed_derate": AS_PRINTED_DERATE, "wrought_derate": WROUGHT_DERATE,
                          "shipped_branch": SHIPPED_BRANCH, "infinite_life_sf": INFINITE_LIFE_SF,
                          "weld_seam_modelled": False},
        "buckling": {"p_cr_unsupported_N": round(euler_buckling_N(L_FREE_UNSUP), 1),
                     "p_cr_supported_N": round(euler_buckling_N(L_FREE_SUP), 1),
                     "sf_unsupported": round(euler_buckling_N(L_FREE_UNSUP) / F_POGO_N, 1)},
        "bending_stress_MPa": {"unsupported": round(sig_unsup, 1), "supported": round(sig_sup, 1)},
        "per_alloy_fatigue": alloy_rows,
        "fabrication_branches": branch_summary,
        "friction_sweep": mu_rows,
        "clearance_regime": {
            "channel": {"dia_mm": D_CHANNEL_MM, "start_mm": CHANNEL_START_MM,
                        "length_mm": CHANNEL_LEN_MM,
                        "note": "length read conservatively (model's own '~14' rather than the CEM's "
                                "shank 14 + flange 3 = 17) — a shorter bore makes contact HARDER to reach"},
            "branches": regimes,
            "gap_limited_branches": gap_limited,
            "free_cantilever_sf_describes_these": [r["branch"] for r in regimes
                                                   if r["regime"].startswith("free cantilever")],
        },
        "verdict": (f"Monolithic bus at the canon rod O{D_BUS:.1f} (01_01 1.4), SHIPPED fabrication = "
                    f"{SHIPPED_BRANCH} (welded cold-drawn wire, ratified 2026-09-10): buckling non-issue "
                    f"(SF {p_cr_unsup / F_POGO_N:.0f}x); the bore liner doubles as lateral support -> "
                    f"fatigue SF {sup_lo:.1f}-{sup_hi:.1f}x (infinite life, all alloys). BARE, the drawn "
                    f"wire reaches infinite life for {len(shipped['unsupported_infinite_life'])} of "
                    f"{len(alloy_rows)} alloys (SF {uns_lo:.1f}-{uns_hi:.1f}x): dropping the as-printed "
                    f"derate lifted {', '.join(marginal) or 'the soft alloys'} OUT of predicted failure but "
                    "NOT over the SF-2 line. So the liner's SUPPORT role is NARROWED by the fabrication "
                    "verdict, not retired - which is the measurement the open HW.34 lining verdict was "
                    "missing. On the superseded PRINTED branch not one of the six cleared it. "
                    "Liner = insulation + support + fatigue-fix in one (HW.34 sub-2). "
                    "Per-alloy margin tracks yield = same ranking as "
                    "thermal -> leading HW.24 candidates win on both."),
        "caveats": "cyclic-load amplitude (pogo friction + PEEK flex) is an estimate; real sway spectrum "
                   "is bench/field (00_02). Comparative supported-vs-unsupported + per-alloy ranking robust. "
                   "NO WELD SEAM is modelled: this is a homogeneous cantilever, while the ratified welded "
                   "rod puts a heat-affected zone at the root, i.e. at peak bending moment. The wrought "
                   "derate describes the WIRE and says nothing about the JOINT.",
    }
    json_path = OUT_DIR / "bus_mechanical.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    # gate: the SUPPORTED rod must clear infinite life for the baseline alloy on the SHIPPED branch
    # (sanity, not a product pass/fail). ⛔ Declared ceiling: it judges one alloy in one branch, so it
    # stays green while any bare-rod or weld-seam question is open — those are verdicts, not gates.
    shipped_derate = dict(FAB_BRANCHES)[SHIPPED_BRANCH]
    return 0 if endurance_MPa(sy_4v, shipped_derate) / sig_sup >= INFINITE_LIFE_SF else 1


if __name__ == "__main__":
    raise SystemExit(main())
