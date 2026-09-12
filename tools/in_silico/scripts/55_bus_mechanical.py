#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 — Mechanical check of the central bus rod (buckling + sway fatigue), the second-half de-risk of
the monolithic-bus idea after the thermal bridge (script 54).

A monolithic Ti bus rises from the anode shank, through the PEEK gap and the cathode bore, to the pogo pad.

⛔ DIAMETER — THE ROD, NEVER THE CHANNEL. Canon 01_01 §1.4 freezes three dimensions and only one of
   them is metal: rod Ø1.0 · cathode channel Ø1.35 · liner 0.15 (channel opened from 1.30 by the
   clearance verdict, 00_07 HW.34, 2026-09-11). D_BUS here is the ROD, imported from
   lib.constants (one home). Substituting the channel inflates every fatigue SF ×2.46 (σ ∝ 1/d³) and
   flips the load-bearing conclusion: at the channel Ø the unsupported branch reads 'marginal for the soft
   alloys', at Ø1.0 it is a predicted FAILURE for Ta and CP-Ti and infinite life for NOBODY — ⚠️ and
   that last sentence is the PRINTED branch, superseded as the shipped route by the welded verdict
   (2026-09-10); on the welded branch four of six clear it bare. ⛔ Do NOT quote either number as the
   reason the liner is needed: that ground was RETIRED 2026-09-11, not narrowed (§4 below + the
   verdict). The diameter warning itself stands — it is about σ ∝ 1/d³, not about the liner.

Two mechanical questions the monolithic idea raises (01_01 §4.1 / 00_07 HW.34):
  1. Buckling — the pogo pin presses the rod tip axially (~1 N, 02_02 §2.2). Does a slender rod buckle?
  2. Sway fatigue — over 20-25 yr (~10^8-10^9 sway cycles) a CYCLIC lateral load bends the rod. The
     defensible driver is pogo-contact friction drag (µ·F_pogo) as the capsule sways and the pin slides
     on the pad; PEEK-sleeve flex adds a secondary base motion. Does the rod survive infinite-life?

KEY COUPLING — ⚠️ REWRITTEN 2026-09-11, and the old version is kept nowhere on purpose: it argued the
liner from FATIGUE, and that ground is RETIRED, not narrowed (⚖️ founder, 00_07 HW.34). What retired it
is §4 of this very script: both L_FREE_* columns are FREE cantilevers — no wall anywhere — while the
real rod threads a Ø1.35 bore, so any branch that leaves play takes it up and BEARS on the wall inside
the bore. An unsupported SF is therefore a number for a configuration that does not exist, and the
script says so through a DERIVED flag (`clearance_regime.free_cantilever_sf_describes_these`), never
through prose. What the liner carries instead is WEAR: the same contact makes rubbing geometrically
FORCED, and a 10 µm conformal film asked to be a bearing in a blind bore of L/D ≈ 12.6 wears through to a
~0.5 V anode↔cathode short. The supported/unsupported columns stay because they price the DIAMETER and
the FABRICATION branch honestly — they are simply not the argument for the liner.

FABRICATION BRANCH — the second thing that moves every SF, and it is a VERDICT, not a parameter.
  ⚖️ 2026-09-10 (00_07 HW.34) ratified the rod as a WELDED cold-drawn wire, so the as-built knockdown
  `AS_PRINTED_DERATE` no longer applies to the shipped part. Both columns are printed side by side —
  `printed` (superseded) and `welded` (shipped) — because the fabrication choice is what moves the
  still-open LINING verdict, and a reader handed one column cannot see that it moved.
  ⛔ THE MODEL STILL HAS NO WELD-SEAM GEOMETRY. It is a homogeneous cantilever, while the ratified rod
  carries a heat-affected zone in the ROOT — exactly where the bending moment peaks. So the doubled SF
  describes the WIRE and says NOTHING about the JOINT, and quoting a welded-column SF as if it covered
  the weld is the error this note exists to prevent. ⊕ What §5 adds (2026-09-12) is not that geometry
  but the SENSITIVITY: the seam's knockdown k is NOT MEASURED anywhere in this tree, so the model
  BOUNDS it — the break-even k at which each alloy crosses the failure and infinite-life lines — rather
  than assuming a value. Priced on the SUPPORTED span only, and deliberately so (§5's own note).
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
from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, ALPHA_PEEK_1K, CACHE_DIR, D_BUS_ROD_MM, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Bus geometry (mm) — the ROD, not the Ø1.35 cathode channel it threads ──
# ⛔ Do not substitute the channel here: σ ∝ 1/d³, so the channel Ø inflates every fatigue SF ×2.46 and turns a
#    predicted failure into a comfortable margin. One home for the value: lib.constants (01_01 §1.4).
D_BUS = D_BUS_ROD_MM
# Free (laterally UNSUPPORTED) cantilever length in each case:
L_FREE_UNSUP = 36.0   # mm — no liner: gap 6 + cathode bore ~14 + flange/pad standoff ~16 = full protrusion
L_FREE_SUP = 6.0      # mm — liner supports the bore run → only the PEEK gap is unsupported

# ── Loads ──
# ── Channel run (mm from the anode root) — the wall that the two branches above IGNORE ──
# Both L_FREE_* above are free-cantilever idealisations: they assume NO wall anywhere over the span.
# The real rod threads a Ø1.35 bore, so a branch that leaves a gap is neither of them — see §4 below.
# ⚠️ The run length is read CONSERVATIVELY (shorter = less room for contact to happen): the model's own
# decomposition of L_FREE_UNSUP says "cathode bore ~14", while cem/cathode_flange.json gives
# shank 14 + flange 3 = 17. Taking 14 makes the contact finding harder to reach, not easier.
CHANNEL_START_MM = L_FREE_SUP      # the PEEK gap ends and the bore begins
CHANNEL_LEN_MM = 14.0
# Full DRILLED depth of the blind bore, from cem/cathode_flange.json (shank 14 + flange 3). Distinct from
# CHANNEL_LEN_MM above, which is the deliberately-short span used for the CONTACT question; this one is
# the machining referent, and it is what the L/D ratio is about — which operation the bore needs.
# ⛔ That ratio lived in prose (here and in SUMMARY) with no cache owner, so it could not be checked
#    against the diameter it divides by. Derived now.
BORE_DEPTH_MM = 17.0
# ⚠️ The word "blind" above is RETIRED (00_07 HW.34): `CathodeFlange.cs` cuts this channel THROUGH
# — z 0..14 in the shank and 14..17 in the disc, exiting the pogo face — and a blind bore could not
# pass a conductor at all. The DEPTH is unchanged; what changes is the machining class the L/D
# argument rests on. Left as prose-with-a-correction rather than silently reworded, because five doc
# homes inherited the word from this very comment.
#
# Protrusion of the rod above the anode top — the span the free-cantilever column prices.
# 🔴 `L_FREE_UNSUP = 36` decomposes itself as "gap 6 + bore ~14 + flange/pad standoff ~16", and that
# third term cites nothing. The CEM stack says otherwise: anode top z=40, sleeve 10..60, shank
# 46..60, disc 60..63 ⇒ 6 + 14 + 3 = 23, and the pad IS the rod's end face (02_02 §1.2), so nothing
# protrudes past the flange. Kept as a SEPARATE constant rather than corrected in place: fixing
# `L_FREE_UNSUP` moves published per-alloy numbers in several homes and is its own pass (00_07
# HW.34). What this constant buys meanwhile is that §5b can PRICE the dispute instead of ignoring it.
PROTRUSION_FROM_CEM_MM = 23.0
D_CHANNEL_MM = 1.35                # cathode channel Ø, canon 01_01 §1.4 — OPENED 1.30 → 1.35 by the
                                   # clearance verdict (00_07 HW.34, branch (в), 2026-09-11)

# Insulation branches: wall thickness AND — new 2026-09-11 — WHICH SIDE the leftover play sits on.
# ⛔ The side is not bookkeeping, it changes what the BEAM is. A conformal film is bonded to the rod, so
#    its play is on the rod side by construction and the bending member is the bare Ti rod. The ratified
#    liner is the opposite: the tube is tight on the WIRE and the pair enters the blind bore as ONE body
#    (00_07 HW.34 — the direction verdict), so the play is on the CHANNEL side and the member is the
#    rod-plus-tube composite. Until this field existed the model could only say the first thing, which is
#    why the canon sentence it fed ("a hundredfold reduction, 140 → ~2.5 µm") described the rod-side
#    allocation nobody ratified.
# ⚠️ The liner wall is now the CANON 0.150, not the 0.1475 this line used to carry. That 2.5 µm shaving
#    was a workaround for the pre-verdict channel: at Ø1.30 the honest 0.150 summed to EXACTLY the bore,
#    so a zero-play row would have divided by a regime that cannot exist. The verdict removed the reason.
INSULATION_OPTIONS = (
    ("conformal 10 µm film", 0.010, "rod"),
    ("conformal TiO2 ~5 µm", 0.005, "rod"),
    ("PEEK liner 0.15 mm", 0.150, "channel"),
)

# ── Composite bending stiffness, for the CHANNEL-side branch only ──
# With the tube tight on the wire the two bend together, so the member is stiffer than the bare rod and
# the wall is reached LATER — which is the conservative direction for the question "is the rod supported
# at the bore mouth". Bounds, both reported rather than one picked: LOWER = bare rod (tube slips, carries
# no shear), UPPER = full composite (perfect bond). Neither is measured; a press-fit polymer tube sits
# between them, and PEEK is soft enough that the whole span between the bounds is a few per cent.
E_PEEK = 3.6e9        # Pa — PEEK 450G flexural modulus (01_01 §4.3 uses the same class of figure)

# ── Assembly-clearance allocation candidates (00_07 HW.34, «кому віддано зазор») ──────────────
# The three PRE-VERDICT dims (rod Ø1.0 · channel Ø1.30 · liner 0.15 wall) summed to ZERO nominal
# clearance, so the assembly needs exactly one of them to move — and WHICH one is the verdict.
# Each row is (label, rod Ø mm, liner WALL mm, channel Ø mm); play and first-contact are COMPUTED,
# so a candidate is priced here rather than argued in prose. ⛔ The tracker quoted «first contact
# 3.95–6.31 mm at 25 µm» for months while no branch in this file produced it — that is a doc value
# with no cache owner, exactly what the skill's «verify a doc value against its cache» forbids.
# ⚠️ TWO different quantities per row and they answer different questions: RADIAL PLAY answers
# «does it go together», FIRST CONTACT answers «where does the wall start carrying the beam».
# Quoting one for the other is the substitution this table exists to prevent.
# ⛔ This table prices GEOMETRY only. The costs that decide the verdict live elsewhere and are NOT
# derivable here: (б) spends 17 % of the wear allowance the 2026-09-11 verdict made the MAIN axis;
# (в) is a re-spec of a hole already machined post-print as the part's primary datum; (г) cuts the
# fatigue SF by ~14 % (σ ∝ 1/d³) on a Ta that already sits at 1.41. See the per-alloy table above.
ASSEMBLY_CLEARANCE_CANDIDATES = (
    ("(а) all three frozen",     1.00, 0.150, 1.30),
    ("(б) liner 0.150 → 0.125",  1.00, 0.125, 1.30),
    ("(в) channel 1.30 → 1.35",  1.00, 0.150, 1.35),
    ("(г) rod 1.00 → 0.95",      0.95, 0.150, 1.30),
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

# ── The WELD SEAM at the root (00_07 HW.34) ───────────────────────────────────────────────────
# The ratified rod is a welded cold-drawn wire, so the joint sits at the ROOT — which is exactly
# where this model puts the peak bending moment, in BOTH spans (tip-loaded cantilever, fixed at
# the root). The derates above describe the WIRE; the seam carries its own fatigue-strength
# reduction on top: weld-toe notch + HAZ microstructure + weld residual tension.
#
# ⛔ THAT FACTOR IS NOT IN THIS TREE AND IS NOT INVENTED HERE. There is no canon row, no vendor
#    answer and no measurement for it, so the sentinel below stays None. Typing a plausible
#    number would be the FALLBACK species of fabrication (00_01 §1.1): a branch of code that
#    exists while its measurer does not. What the model computes instead is the question that
#    CAN be answered from what we already have — the BREAK-EVEN knockdown, i.e. how bad the
#    joint may be before each alloy crosses a line. The relation is deliberately trivial
#    (SF_seam = k·SF_wire, same stress at the same point); its whole value is that it INVERTS
#    an unanswerable input into an answerable bound.
WELD_KNOCKDOWN_MEASURED = None   # k = σ_e(seam)/σ_e(wire) ∈ (0,1] — NOT MEASURED (00_06 §0)
# Two reference markers, and BOTH are OURS — neither is a weld figure borrowed from anywhere,
# so neither claims authority it does not have (in-silico skill #9, the mirror half):
#   k = AS_PRINTED_DERATE — "the joint is as bad as an as-built SLM surface". At that k the
#       welded branch collapses onto `printed` AT THE SEAM, i.e. the metallurgical argument for
#       welding buys nothing where the part actually breaks.
#   k = WROUGHT_DERATE    — "the joint is as good as the drawn wire", i.e. the model as it stood
#       before this block existed.
WELD_KNOCKDOWN_MARKERS = (("joint as bad as an as-printed surface", AS_PRINTED_DERATE),
                          ("joint as good as the drawn wire", WROUGHT_DERATE))

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


def flexural_rigidity_Nm2(rod_dia_mm: float, liner_wall_mm: float | None = None) -> float:
    """EI of the bending member. Bare Ti rod, or rod + PEEK tube in full composite (parallel-axis-free,
    both concentric about the same neutral axis, so the second moments simply add).

    `liner_wall_mm=None` is the LOWER bound (tube slips): the rod carries the whole moment.
    """
    ei = E_TI * second_moment_m4(rod_dia_mm)
    if liner_wall_mm:
        r_i = (rod_dia_mm / 2.0) * MM_M
        r_o = r_i + liner_wall_mm * MM_M
        ei += E_PEEK * (np.pi / 4.0) * (r_o ** 4 - r_i ** 4)
    return ei


def tip_load_deflection_mm(force_lat_N: float, x_mm: float, length_mm: float,
                           dia_mm: float | None = None, ei_Nm2: float | None = None) -> float:
    """Free-cantilever deflection at x under a TRANSVERSE TIP load: δ(x) = F·x²·(3L−x)/(6EI).

    Same F, L, E, I as the bending-stress model above — this is that model read as a SHAPE rather
    than as a root stress, which is the one question it was never asked.

    `dia_mm` defaults to the canon rod Ø; it is a parameter ONLY so an allocation candidate that
    moves the ROD (00_07 HW.34 branch (г)) is priced on its own I, never on the canon one — I ∝ d⁴,
    so borrowing the canon stiffness for a thinner rod understates its deflection by ~20 %.

    `ei_Nm2` overrides both, for the channel-side branch where the bending member is the rod PLUS the
    tube it carries. Passing it is the only way to say "this is not a bare rod".
    """
    ei = ei_Nm2 if ei_Nm2 is not None else E_TI * second_moment_m4(D_BUS if dia_mm is None else dia_mm)
    x, ell = x_mm * MM_M, length_mm * MM_M
    return force_lat_N * x ** 2 * (3.0 * ell - x) / (6.0 * ei) / MM_M


def first_wall_contact_mm(force_lat_N: float, radial_play_mm: float, length_mm: float,
                          dia_mm: float | None = None, ei_Nm2: float | None = None) -> float:
    """Distance from the root at which the FREE deflection first equals the radial play.

    Bisection on a monotonic function — no solver dependency. Returns `length_mm` if the rod never
    takes up the play over the whole span (i.e. it really is a free cantilever).
    """
    if tip_load_deflection_mm(force_lat_N, length_mm, length_mm, dia_mm, ei_Nm2) <= radial_play_mm:
        return length_mm
    lo, hi = 0.0, length_mm
    for _ in range(60):
        mid = (lo + hi) / 2.0
        if tip_load_deflection_mm(force_lat_N, mid, length_mm, dia_mm, ei_Nm2) < radial_play_mm:
            lo = mid
        else:
            hi = mid
    return lo


def endurance_MPa(yield_MPa: float, derate: float = AS_PRINTED_DERATE) -> float:
    """σ_e ≈ fatigue-ratio × yield, knocked down only if the rod is AS-PRINTED.

    `derate` is the fabrication branch, not a tuning knob: 0.5 for an SLM as-built surface,
    1.0 for cold-drawn wire. ⛔ It describes the WIRE and says nothing about the WELD — the
    seam has its own knockdown, and `break_even_knockdown` below is what this file says about it.
    """
    return ENDURANCE_OVER_YIELD * derate * yield_MPa


def break_even_knockdown(sf_wire: float, sf_line: float) -> float:
    """The seam knockdown `k` at which a rod whose WIRE stands at `sf_wire` crosses `sf_line`.

    The seam and `sig_sup` refer to the SAME section by construction, so SF_seam = k · SF_wire.
    ⛔ The ground this docstring used to give — «the root is where the bending moment peaks» — is
    RETRACTED (2026-09-12, adversarial review): the drag acts at the pad BEYOND the bore, so in the
    real overhang the peak-moment section is the bore MOUTH and the root moment is bracketed
    [0, µ·F·(L−6)/2]. The relation survives on identity, not on a maximum. Inverting gives
    k = sf_line / sf_wire — a bound on the unmeasured input rather than a guess at it.

    ⚠️ A result > 1 is not a knockdown at all: it means the WIRE is already below `sf_line`, so
    no joint quality can reach it. The caller reports that as `reachable: false` rather than
    printing a number above 1, which would read as a tolerance.
    """
    return sf_line / sf_wire


def main() -> int:
    banner("HW.34 — Bus rod mechanical check (buckling + sway fatigue)")
    print(f"  Rod Ø{D_BUS:.1f} mm; free length unsupported {L_FREE_UNSUP:.0f} mm (no liner) vs "
          f"supported {L_FREE_SUP:.0f} mm (liner = the insulation, HW.34 sub-2)")
    print(f"  Pogo {F_POGO_N:.1f} N axial; cyclic lateral drag = µ·F_pogo (µ={MU_CONTACT:.1f})")
    print(f"  σ_e ≈ {ENDURANCE_OVER_YIELD:.2f}·derate·σ_y — derate {AS_PRINTED_DERATE:.2f} printed "
          f"vs {WROUGHT_DERATE:.2f} welded (drawn wire); SHIPPED = {SHIPPED_BRANCH}. The seam's own "
          f"knockdown is BOUNDED in §5, never assumed (k NOT MEASURED)")

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
    # threads a Ø1.35 bore, so an insulation branch that leaves play is NEITHER idealisation — it is a
    # gap-limited beam. Which one it is decides whether the SF printed above describes it at all.
    banner("Clearance regime — does the rod REACH the channel wall? (the branch the SF table omits)")
    channel_end = CHANNEL_START_MM + CHANNEL_LEN_MM
    # ⛔ TWO decimals: `.1f` printed the Ø1.35 channel as "Ø1.4" — a diameter the model never used, on
    #    the one line a reader takes the geometry from. The 50 µm this whole verdict bought is smaller
    #    than that rounding step.
    print(f"  Channel Ø{D_CHANNEL_MM:.2f} runs {CHANNEL_START_MM:.0f}→{channel_end:.0f} mm from the root "
          f"(conservative length {CHANNEL_LEN_MM:.0f} mm; CEM shank+flange would give 17).")
    print(f"  {'insulation branch':<24s} {'play on':>8s} {'radial play':>11s} "
          f"{'first contact, mm from root':>21s}   regime")
    print(f"  {'-' * 92}")
    regimes = []
    for label, t_mm, play_side in INSULATION_OPTIONS:
        play = (D_CHANNEL_MM - (D_BUS + 2.0 * t_mm)) / 2.0
        # The bending member follows the SIDE the play sits on, not the branch's name. Rod-side ⇒ the
        # bare Ti rod. Channel-side ⇒ the rod carrying its tube; that pair is stiffer, so it reaches the
        # wall LATER — the conservative direction for "is it supported at the mouth", which is why both
        # bounds are computed and the WORST (stiffest, latest contact) drives the regime verdict.
        ei_lo = flexural_rigidity_Nm2(D_BUS)
        ei_hi = flexural_rigidity_Nm2(D_BUS, t_mm) if play_side == "channel" else ei_lo
        contacts, contacts_bond = {}, {}
        for mu in MU_SWEEP:
            contacts[mu] = round(first_wall_contact_mm(mu * F_POGO_N, play, L_FREE_UNSUP, ei_Nm2=ei_lo), 2)
            contacts_bond[mu] = round(first_wall_contact_mm(mu * F_POGO_N, play, L_FREE_UNSUP, ei_Nm2=ei_hi), 2)
        lo_x, hi_x = min(contacts.values()), max(contacts_bond.values())
        # Bears on the wall INSIDE the bore on every µ the model itself sweeps ⇒ not a free cantilever.
        bears = all(x < channel_end for x in contacts_bond.values())
        at_mouth = all(x <= CHANNEL_START_MM for x in contacts_bond.values())
        regime = ("supported at the bore mouth" if at_mouth
                  else "GAP-LIMITED — bears inside the bore" if bears
                  else "free cantilever (never reaches the wall)")
        print(f"  {label:<24s} {play_side:>8s} {play * 1000:>8.1f} µm {f'{lo_x:.2f}–{hi_x:.2f}':>21s}   {regime}")
        regimes.append({"branch": label, "coating_or_liner_mm": t_mm, "play_side": play_side,
                        "radial_play_mm": round(play, 4), "first_contact_mm_by_mu": contacts,
                        "first_contact_mm_by_mu_bonded": contacts_bond,
                        "ei_Nm2_bare_rod": round(ei_lo, 4), "ei_Nm2_bonded": round(ei_hi, 4),
                        "bears_inside_bore": bool(bears), "supported_at_mouth": bool(at_mouth),
                        "regime": regime})
    gap_limited = [r["branch"] for r in regimes if r["bears_inside_bore"] and not r["supported_at_mouth"]]

    # The canon sentence this table feeds (01_01 §1.4) used to quote a "hundredfold" reduction. DERIVE it
    # — the factor is a ratio of two rows here and moves whenever either does.
    rod_side = [r for r in regimes if r["play_side"] == "rod"]
    chan_side = [r for r in regimes if r["play_side"] == "channel"]
    play_reduction = None
    if rod_side and chan_side:
        worst_film = max(r["radial_play_mm"] for r in rod_side)
        liner_play = min(r["radial_play_mm"] for r in chan_side)
        play_reduction = {
            "conformal_worst_radial_play_mm": worst_film,
            "liner_radial_play_mm": liner_play,
            "factor": round(worst_film / liner_play, 2) if liner_play else None,
            "note": "the liner still shrinks the free travel by this factor, but it is NOT the "
                    "hundredfold the canon prose carried: that figure came from a rod-side allocation "
                    "(tube loose on the wire) which the 2026-09-11 direction verdict did not choose",
        }
        print(f"\n  → Free travel falls {worst_film * 1000:.0f} → {liner_play * 1000:.0f} µm = "
              f"{play_reduction['factor']:.1f}× (DERIVED; the play is on the {chan_side[0]['play_side']} side "
              f"by verdict, so this is not the rod-side hundredfold the prose used to quote).")

    # ── Differential AXIAL expansion of the liner — the term canon did not carry ──────────────────
    # 🔴 01_01 §1.4 carries the RADIAL thermal term (~2.0 µm diametral over 40 K) and is silent on the
    # axial one, which is an order of magnitude larger because it multiplies by the bore DEPTH rather
    # than by a sub-millimetre diameter. It decides a question the radial term cannot touch: whether the
    # liner may be captured at BOTH ends. Captured at both, a tube that wants 26 µm of extra length over
    # a 40 K swing has nowhere to put it. ⛔ This says nothing about WHICH end to fix — that is a
    # geometry verdict (00_07 HW.34); the model only prices the motion the verdict has to accommodate.
    alpha_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    d_alpha = ALPHA_PEEK_1K - alpha_ti
    axial_thermal = {
        "liner_length_mm": BORE_DEPTH_MM,
        "alpha_peek_1K": ALPHA_PEEK_1K,
        "alpha_ti_1K": alpha_ti,
        "alpha_ti_source": ALLOY_BASELINE,
        "differential_axial_um_by_dT_K": {str(dt): round(d_alpha * BORE_DEPTH_MM * dt * 1000.0, 1)
                                          for dt in (20, 40, 60, 80)},
        "radial_diametral_um_at_40K": round(d_alpha * (D_BUS + 2.0 * 0.150) * 40.0 * 1000.0, 1),
        # ⛔ Two claims were corrected here 2026-09-12 by adversarial review, and both were the kind
        # that reads as physics while being arithmetic. (1) «an order of magnitude larger than the
        # radial term» compares two REFERENCE LENGTHS, not two mechanical demands: both terms are
        # Δα·ΔT times a length, so the strains are IDENTICAL and the ratio is exactly depth/OD.
        # (2) «captured at both ends it has nowhere to put it» is false — it has elastic compression.
        # The model now prices that instead of inferring an impossibility from a displacement.
        "strain": round(d_alpha * 40.0, 8),
        "note": "axial and radial carry the SAME differential strain; their ratio is the ratio of "
                "their reference lengths (bore depth vs liner OD), so quoting it as a mechanical "
                "finding overstates it. What both-end capture actually costs is the stress below",
    }
    ax40 = axial_thermal["differential_axial_um_by_dT_K"]["40"]
    # Elastic cost of constraining that growth, so the prohibition is PRICED rather than asserted.
    # ⚠️ Declared ceiling: this is the instantaneous elastic stress. It does NOT model 20 yr of PEEK
    # creep/relaxation ratcheting, which is the real argument against both-end capture and which
    # this file has no model for (01_01 §4.3 tabulates relaxation; nothing here reads it).
    for dt_k in (40, 80):
        strain = d_alpha * dt_k
        axial_thermal[f"constrained_stress_MPa_at_{dt_k}K"] = round(strain * E_PEEK / 1e6, 2)
    print(f"\n  → Liner axial growth vs Ti over {BORE_DEPTH_MM:.0f} mm: {ax40:.0f} µm at 40 K "
          f"({axial_thermal['differential_axial_um_by_dT_K']['80']:.0f} µm at 80 K). ⚠️ The radial "
          f"term carries the SAME strain —")
    print(f"    the {ax40 / axial_thermal['radial_diametral_um_at_40K']:.0f}× is the ratio of "
          f"reference LENGTHS (depth {BORE_DEPTH_MM:.0f} vs OD {D_BUS + 2 * 0.150:.2f}), not of demands.")
    print(f"  → Constraining it at BOTH ends costs {axial_thermal['constrained_stress_MPa_at_40K']:.1f} MPa "
          f"at 40 K ({axial_thermal['constrained_stress_MPa_at_80K']:.1f} at 80 K) of axial compression —")
    print("    a few per cent of PEEK yield, so it is NOT an impossibility. ⛔ What argues against")
    print("    both-end capture is 20 yr of creep/relaxation ratcheting, which this file does NOT")
    print("    model; which end is fixed is a geometry verdict either way (00_07 HW.34).")

    # ── Is L_FREE_SUP = 6 mm actually grounded? The §2 table ASSUMES the liner turns the span into the
    # PEEK gap alone. That is an assumption about WHERE contact happens, and §4 just computed it — so
    # check the two against each other instead of asserting the first. Worst case = the stiffest member
    # (bonded tube) at the lightest drag, i.e. the deepest first contact.
    supported_span_check = None
    if chan_side:
        deepest = max(max(r["first_contact_mm_by_mu_bonded"].values()) for r in chan_side)
        overshoot = deepest - L_FREE_SUP
        supported_span_check = {
            "assumed_free_span_mm": L_FREE_SUP,
            "deepest_first_contact_mm": round(deepest, 2),
            "overshoot_mm": round(overshoot, 2),
            "sigma_understated_pct": round(100.0 * overshoot / L_FREE_SUP, 1),
            "note": "sigma is linear in span, so the supported-column SF is optimistic by this "
                    "percentage; it stays far above the SF-2 line, but the number is measured now "
                    "rather than assumed (00_07 HW.34)",
        }
        print(f"  → L_FREE_SUP = {L_FREE_SUP:.0f} mm vs deepest measured first contact "
              f"{deepest:.2f} mm ⇒ the assumed span is short by {overshoot:.2f} mm, i.e. the supported "
              f"root stress is understated by {supported_span_check['sigma_understated_pct']:.1f} %.")

    # ── 4b. Allocation candidates — the OTHER question the same geometry answers ─────────────────
    banner("Assembly-clearance allocation — which frozen dim moves (00_07 HW.34)")
    print(f"  {'candidate':<26s} {'rod Ø':>6s} {'liner':>6s} {'chan Ø':>7s} {'DIAMETRAL':>10s} "
          f"{'RADIAL':>8s} {'first contact, mm':>19s}")
    print(f"  {'-' * 94}")
    allocations = []
    for label, rod_mm, liner_mm, chan_mm in ASSEMBLY_CLEARANCE_CANDIDATES:
        stack_mm = rod_mm + 2.0 * liner_mm
        diametral = chan_mm - stack_mm
        play = diametral / 2.0
        contacts = {mu: round(first_wall_contact_mm(mu * F_POGO_N, play, L_FREE_UNSUP, rod_mm), 2)
                    for mu in MU_SWEEP}
        lo_x, hi_x = min(contacts.values()), max(contacts.values())
        assembles = diametral > 0.0
        # The row whose three dims ARE the current frozen set is the one that shipped — derived, so the
        # label cannot drift away from the numbers the rest of this file uses.
        shipped_row = (abs(rod_mm - D_BUS) < 1e-9 and abs(liner_mm - 0.150) < 1e-9
                       and abs(chan_mm - D_CHANNEL_MM) < 1e-9)
        tag = ("   ⛔ zero/negative — does not assemble" if not assembles
               else "   ✅ RATIFIED + APPLIED" if shipped_row else "")
        print(f"  {label:<26s} {rod_mm:>6.2f} {liner_mm:>6.3f} {chan_mm:>7.2f} "
              f"{diametral * 1000:>7.0f} µm {play * 1000:>5.0f} µm {f'{lo_x:.2f}–{hi_x:.2f}':>19s}{tag}")
        allocations.append({"candidate": label, "rod_dia_mm": rod_mm, "liner_wall_mm": liner_mm,
                            "channel_dia_mm": chan_mm, "stack_od_mm": round(stack_mm, 4),
                            "is_shipped_geometry": bool(shipped_row),
                            "diametral_clearance_mm": round(diametral, 4),
                            "radial_play_mm": round(play, 4),
                            "first_contact_mm_by_mu": contacts, "assembles": bool(assembles)})
    print("\n  → Every non-(а) candidate lands the SAME 25 µm radial play by construction, so the")
    print("    support question does NOT discriminate between them — first contact is 3.9–6.3 mm in")
    print("    all three, i.e. practically at the bore mouth. The verdict is decided by the COSTS")
    print("    named over the table, never by this geometry. ⛔ (а) is listed to show it is not an")
    print("    option: zero diametral clearance is the F3 gate's arithmetic, not an assembly.")
    # ⛔ DERIVED, never typed — this sentence is the ground the lining verdict stands on.
    print(f"\n  → The free-cantilever SF above describes NO branch that bears on the wall: "
          f"{', '.join(gap_limited) or 'none'}.")
    print("    For those the effective span is a FRACTION of the 36 mm span priced above, so the")
    print("    unsupported SF is a number for a configuration that does not exist — while the contact")
    print("    it implies is FORCED by geometry on every µ, which is a wear question, not a fatigue one.")
    # ⚠️ The flag is binary and the branches are NOT equivalent — read the depth, not the label. Since the
    # channel opened to Ø1.35 the liner row also lands a hair past the mouth (6.51 vs 6.00 mm), so it joins
    # this list; a conformal film reaches the wall 10-17 mm in, i.e. deep in the bore or past its end.
    # Same word, an order of magnitude apart in what it costs.
    print("    ⚠️ The list is not a ranking: the liner bears 0.5 mm past the mouth, a conformal film")
    print("    10–17 mm in. The flag says 'not a free cantilever'; the DEPTH says how much that matters.")

    # ── 5. The WELD SEAM at the root — how bad may the JOINT be? (00_07 HW.34) ───────────────────
    # 🔴 The question §2 answers for the WIRE and never for the JOINT. Canon (01_01 §1.4 and the
    # factory protocol §3 step 1) sent the reader here for this state while nothing here held it.
    # 🔴 «Priced on the SUPPORTED span ONLY» stood here until 2026-09-12 and was FALSE — caught by
    # adversarial review, and the mechanism was this file's own: the conservatism term comes from
    # `supported_span_check`, which measures first contact along `L_FREE_UNSUP`. So the declared
    # exclusion was never executed, and the disputed 36 mm span feeds the seam bound through the
    # back door. ⛔ Do not "fix" that by dropping the correction — it is real; fix it by making the
    # DEPENDENCE explicit, which is what the protrusion sweep below does.
    #
    # ⛔ AND THE HEADLINE FLIPS ON IT. `L_FREE_UNSUP = 36` is under an open correction (00_07 HW.34:
    # the CEM stack gives 23 mm and the pad is the rod's own end face). At 23 the span optimism is
    # not 8.5 % but ~40 %, and the binding alloy stops clearing the SF-2 line against our own
    # as-printed marker. A single number would therefore assert a configuration that is itself in
    # dispute, so the model emits BOTH and derives the flip rather than letting prose carry it.
    banner("Weld seam at the root — break-even knockdown (the JOINT, not the wire)")
    mu_worst = max(MU_SWEEP)
    shipped_derate = dict(FAB_BRANCHES)[SHIPPED_BRANCH]

    def span_inflation_for(protrusion_mm: float) -> float:
        """Span optimism of `L_FREE_SUP`, measured against first contact over `protrusion_mm`.

        ⛔ This is the term that couples the seam bound to the protrusion, and naming the argument
        is the whole point: the caller must choose a protrusion consciously instead of inheriting
        the module constant, which is the defect this function replaced.
        """
        chan = [r for r in regimes if r["play_side"] == "channel"]
        if not chan:
            return 1.0
        deepest = max(max(first_wall_contact_mm(mu * F_POGO_N, r["radial_play_mm"], protrusion_mm,
                                                ei_Nm2=r["ei_Nm2_bonded"])
                          for mu in MU_SWEEP) for r in chan)
        return max(1.0, deepest / L_FREE_SUP)

    span_inflation = span_inflation_for(L_FREE_UNSUP)
    sig_sup_worst = bending_stress_MPa(mu_worst * F_POGO_N, L_FREE_SUP) * span_inflation
    print("  Seam = root; SF_seam = k·SF_wire because both refer to the SAME section (see caveats:")
    print("  the peak-moment section of the real overhang is the bore mouth, not the root).")
    print("  k is NOT MEASURED anywhere in this tree (no canon row, no vendor answer) — so the")
    print(f"  model bounds it instead of guessing it. Nominal σ_sup = {sig_sup:.1f} MPa (µ={MU_CONTACT:.1f}); "
          f"worst corner = {sig_sup_worst:.1f} MPa")
    print(f"  (µ={mu_worst:.1f} × span-optimism {100.0 * (span_inflation - 1.0):.1f} %).\n")
    print(f"  {'alloy (= bus, monolithic)':<24s} {'σ_e wl':>6s} | {'SF nom':>7s} {'k→fail':>7s} {'k→SF2':>7s} | "
          f"{'SF worst':>8s} {'k→fail':>7s} {'k→SF2':>7s}")
    print(f"  {'-' * 92}")

    def fmt_k(k: float) -> str:
        # ⛔ A k above 1 is not a tolerance — it means the WIRE itself is under the line, and any
        # joint quality whatsoever leaves it there. Printing "1.42" would read as head-room.
        return f"{k:.3f}" if k <= 1.0 else "  — "

    seam_rows = []
    for row in alloy_rows:
        se = row[f"endurance_MPa_{SHIPPED_BRANCH}"]
        sf_nom = row[f"sf_supported_{SHIPPED_BRANCH}"]
        sf_worst = se / sig_sup_worst
        entry = {"alloy": row["alloy"], "endurance_MPa": se,
                 "sf_wire_supported_nominal": sf_nom,
                 "sf_wire_supported_worst_corner": round(sf_worst, 2)}
        for tag, sf in (("nominal", sf_nom), ("worst_corner", sf_worst)):
            k_fail = break_even_knockdown(sf, 1.0)
            k_inf = break_even_knockdown(sf, INFINITE_LIFE_SF)
            entry[f"k_at_failure_line_{tag}"] = round(k_fail, 3) if k_fail <= 1.0 else None
            entry[f"k_at_infinite_life_{tag}"] = round(k_inf, 3) if k_inf <= 1.0 else None
            entry[f"infinite_life_reachable_{tag}"] = bool(k_inf <= 1.0)
        print(f"  {row['alloy']:<24s} {se:>6.0f} | {sf_nom:>6.1f}× "
              f"{fmt_k(break_even_knockdown(sf_nom, 1.0)):>7s} {fmt_k(break_even_knockdown(sf_nom, INFINITE_LIFE_SF)):>7s} | "
              f"{sf_worst:>7.1f}× {fmt_k(break_even_knockdown(sf_worst, 1.0)):>7s} "
              f"{fmt_k(break_even_knockdown(sf_worst, INFINITE_LIFE_SF)):>7s}")
        seam_rows.append(entry)

    # ⛔ DERIVED, never typed: which alloy binds, and whether our own as-printed marker clears it.
    binding = min(seam_rows, key=lambda r: r["sf_wire_supported_worst_corner"])
    k_binding = binding["k_at_infinite_life_worst_corner"]
    marker_label, marker_k = WELD_KNOCKDOWN_MARKERS[0]
    marker_clears = k_binding is not None and marker_k >= k_binding
    # ⛔ `k_*` is None whenever the WIRE itself is already under the line — a state findings of
    # 2026-09-12 put within reach — and the arithmetic below used to crash on it with a TypeError
    # rather than report it. A model that dies at the moment its subject becomes interesting is
    # worse than one that says «unreachable».
    def pct_lost(k):
        return "unreachable — the WIRE is already under this line" if k is None else f"{100.0 * (1.0 - k):.0f} %"

    print(f"\n  → The binding candidate at the worst corner is {binding['alloy']} "
          f"(SF {binding['sf_wire_supported_worst_corner']:.1f}×): the seam may lose "
          f"{pct_lost(k_binding)} of the wire's endurance before the SF-2 line goes, and "
          f"{pct_lost(binding['k_at_failure_line_worst_corner'])} before failure is predicted.")
    print(f"  → Against our own marker «{marker_label}» (k = {marker_k:.2f}): "
          f"{'CLEARS' if marker_clears else 'DOES NOT CLEAR'} the SF-2 line, margin in k = "
          f"{'n/a' if k_binding is None else format(marker_k - k_binding, '+.3f')}.")
    print("  ⚠️ This bounds ONE mechanism. Three the model still does not carry, with their signs:")
    print("     bead section (upset/fillet lowers nominal stress — RELIEVES) · weld-toe notch")
    print("     (concentrates it — AGGRAVATES) · weld residual TENSION, which is a MEAN stress and")
    print("     this file has no Goodman/Haigh correction anywhere, so even k = 1 would understate.")

    # ── 5b. The verdict's dependence on the DISPUTED protrusion — derived, never asserted ─────────
    # ⛔ The number above is not quotable on its own: it rides `L_FREE_UNSUP`, and that constant is
    # under an open correction (00_07 HW.34 — the CEM stack gives 23 mm). Emitting both spans turns
    # «the bound may flip» from a caveat into a measurement, and shows WHICH way.
    binding_alloy = binding["alloy"]
    se_binding = binding["endurance_MPa"]
    protrusion_rows = []
    for label, prot in (("shipped constant L_FREE_UNSUP", L_FREE_UNSUP),
                        ("CEM-derived candidate (00_07 HW.34)", PROTRUSION_FROM_CEM_MM)):
        infl = span_inflation_for(prot)
        sig = bending_stress_MPa(mu_worst * F_POGO_N, L_FREE_SUP) * infl
        k_inf = break_even_knockdown(se_binding / sig, INFINITE_LIFE_SF)
        protrusion_rows.append({
            "label": label, "protrusion_mm": prot,
            "span_optimism_pct": round(100.0 * (infl - 1.0), 1),
            "sigma_worst_corner_MPa": round(sig, 1),
            "binding_k_at_infinite_life": round(k_inf, 3) if k_inf <= 1.0 else None,
            "as_printed_marker_clears_sf2": bool(k_inf <= marker_k),
            "margin_in_k": round(marker_k - k_inf, 3),
        })
    flips = len({r["as_printed_marker_clears_sf2"] for r in protrusion_rows}) > 1
    print(f"\n  → Dependence on the DISPUTED protrusion ({binding_alloy} binds either way):")
    for r in protrusion_rows:
        print(f"      {r['label']:<38s} L={r['protrusion_mm']:>5.1f} mm → optimism {r['span_optimism_pct']:>5.1f} % · "
              f"σ {r['sigma_worst_corner_MPa']:>5.1f} MPa · k {r['binding_k_at_infinite_life']} · "
              f"{'CLEARS' if r['as_printed_marker_clears_sf2'] else 'DOES NOT CLEAR'} ({r['margin_in_k']:+.3f})")
    print("    🔴 THE VERDICT FLIPS ON IT — so the seam bound is NOT quotable until the protrusion"
          if flips else "    ✅ The verdict is the same at both spans — the bound is quotable as it stands")
    print("    correction lands (00_07 HW.34); quote the pair, never the shipped-constant row alone."
          if flips else "    (the protrusion correction changes the digits, not the answer).")

    weld_seam = {
        "question": "00_07 HW.34 — the ratified rod is a WELDED drawn wire, so a heat-affected zone "
                    "sits at the root, i.e. at peak bending moment. The wrought derate describes the "
                    "WIRE. How bad may the JOINT be before the verdict moves?",
        "seam_location": "root of the modelled cantilever; the two quantities refer to the SAME "
                         "section, which is why SF_seam = k*SF_wire holds. NOT the peak-moment "
                         "section of the real overhang - that is the bore mouth (retracted 2026-09-12)",
        "geometry_modelled": False,
        "knockdown_k_measured": WELD_KNOCKDOWN_MEASURED,
        "knockdown_k_source": "NOT MEASURED — no canon row, no vendor answer, no experiment in this "
                              "tree. Bounded here instead of assumed; a value is an RFQ/literature "
                              "input and enters through the Validation Gate (00_06 §0), not through "
                              "this constant",
        "markers": [{"label": lbl, "k": k} for lbl, k in WELD_KNOCKDOWN_MARKERS],
        "span": {"which": "supported (liner) ONLY", "nominal_sigma_MPa": round(sig_sup, 1),
                 "worst_corner_sigma_MPa": round(sig_sup_worst, 1),
                 "worst_corner_mu": mu_worst,
                 "span_optimism_pct": round(100.0 * (span_inflation - 1.0), 1),
                 "why_not_free_cantilever": "§4's derived flag says the free-cantilever SF describes "
                                            "no branch that bears on the wall, so a seam tolerance "
                                            "computed on it would price a configuration that does "
                                            "not exist (the error the 2026-09-11 verdict corrected)"},
        "per_alloy": seam_rows,
        # 🔴 Read this BEFORE `binding_candidate`: the bound rides the disputed protrusion, and at
        # the CEM-derived span the verdict against our own marker reverses. `verdict_flips_on_it`
        # is DERIVED — when the protrusion correction lands it goes false on its own.
        "protrusion_sensitivity": {"binding_alloy": binding_alloy,
                                   "rows": protrusion_rows,
                                   "verdict_flips_on_it": bool(flips),
                                   "note": "the conservatism term (span optimism) is measured along "
                                           "the protrusion, so the seam bound inherits a constant "
                                           "that 00_07 HW.34 records as wrong; quote the PAIR"},
        "binding_candidate": {"alloy": binding["alloy"],
                              "sf_wire_worst_corner": binding["sf_wire_supported_worst_corner"],
                              "k_at_infinite_life": k_binding,
                              "k_at_failure_line": binding["k_at_failure_line_worst_corner"],
                              "as_printed_marker_clears_sf2": bool(marker_clears),
                              "margin_in_k_vs_as_printed_marker": round(marker_k - k_binding, 3)
                              if k_binding is not None else None},
        "not_modelled": {"bead_section": "an upset/fillet raises the local section, which LOWERS "
                                         "nominal stress — this omission is conservative",
                         "weld_toe_notch": "a geometric stress concentration at the toe — this "
                                           "omission is ANTI-conservative",
                         "mean_stress": "weld residual tension is a mean stress, and this file "
                                        "carries no Goodman/Haigh correction at all, so the "
                                        "endurance ratio is fully-reversed by construction",
                         "seam_position": "the fusion line is assumed coincident with the fixed end; "
                                          "a socketed or filleted joint moves effective fixity"},
    }

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
    # ⛔ DERIVED from §5, never typed. The old text here said the seam "must be judged on its own"
    # and left it at that; §5 now judges it the only way an unmeasured input can be judged — by
    # bounding it. What has NOT changed: the ×2 still belongs to the WIRE.
    print("  4. The WELD SEAM (§5): the ×2 still belongs to the WIRE, but the JOINT is no longer")
    print(f"     unpriced. Binding candidate {binding['alloy']} at the worst corner (µ {mu_worst:.1f} + "
          f"span-optimism {100.0 * (span_inflation - 1.0):.1f} %):")
    print(f"     the seam may lose {100.0 * (1.0 - k_binding):.0f} % of the wire's endurance before the "
          f"SF-2 line and {100.0 * (1.0 - binding['k_at_failure_line_worst_corner']):.0f} % before "
          f"predicted failure.")
    print(f"     Our own as-printed marker (k = {marker_k:.2f}) {'clears' if marker_clears else 'does NOT clear'} "
          f"it by {marker_k - k_binding:+.3f} in k. ⛔ k itself stays NOT MEASURED — bounded, not assumed.")
    print("  5. Per-alloy fatigue margin tracks yield (β-Ti/15Zr/4V > CP-Ti > Ta) — SAME ranking as the")
    print("     thermal bridge → the leading bake-off candidates (HW.24) win on both axes, no tension.")
    print("  6. Caveat: the cyclic-load amplitude (pogo friction + PEEK flex) is an ESTIMATE — the real")
    print("     sway spectrum is bench/field (00_02). Comparative supported-vs-unsupported is robust.")

    out = {
        "method": "slender-beam closed form — Euler buckling (fixed-free) + cantilever tip-load bending "
                  "+ S-N endurance ratio (σ_e ≈ k·σ_y, as-printed derate). No FEA.",
        "geometry_mm": {"bus_dia": D_BUS, "free_len_unsupported": L_FREE_UNSUP, "free_len_supported": L_FREE_SUP},
        "loads": {"pogo_axial_N": F_POGO_N, "friction_mu": MU_CONTACT, "lateral_drag_N": MU_CONTACT * F_POGO_N},
        # ⚠️ `weld_seam_modelled: false` stood here until 2026-09-12 and four doc homes cited it.
        # It is replaced rather than flipped, because neither boolean is true any more: the seam's
        # GEOMETRY is still unmodelled while its SENSITIVITY now is. A flipped flag would have been
        # the half-fix that splits a surface into halves that disagree — the sub-block says both.
        "fatigue_model": {"endurance_over_yield": ENDURANCE_OVER_YIELD,
                          "as_printed_derate": AS_PRINTED_DERATE, "wrought_derate": WROUGHT_DERATE,
                          "shipped_branch": SHIPPED_BRANCH, "infinite_life_sf": INFINITE_LIFE_SF,
                          "weld_seam_geometry_modelled": False,
                          "weld_seam_sensitivity_modelled": True,
                          "mean_stress_correction_modelled": False},
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
                        "drilled_depth_mm": BORE_DEPTH_MM,
                        "aspect_ratio_l_over_d": round(BORE_DEPTH_MM / D_CHANNEL_MM, 2),
                        "aspect_note": "L/D of the BLIND bore as machined (depth 17 = shank 14 + flange 3, "
                                       "cem/cathode_flange.json). It decides which operation the vendor "
                                       "needs and is the ratio quoted in canon prose - derived here so it "
                                       "moves with the diameter instead of being retyped",
                        "note": "length read conservatively (model's own '~14' rather than the CEM's "
                                "shank 14 + flange 3 = 17) — a shorter bore makes contact HARDER to reach"},
            "branches": regimes,
            "play_reduction": play_reduction,
            "axial_thermal": axial_thermal,
            "supported_span_check": supported_span_check,
            "gap_limited_branches": gap_limited,
            "free_cantilever_sf_describes_these": [r["branch"] for r in regimes
                                                   if r["regime"].startswith("free cantilever")],
        },
        "weld_seam": weld_seam,
        "assembly_clearance": {
            "question": "00_07 HW.34 — which of the three frozen dims (01_01 §1.4) gives up the "
                        "assembly clearance. CLOSED 2026-09-11: direction = channel side, size = "
                        "branch (в), channel 1.30 -> 1.35. The table stays because it is the PRICING "
                        "the verdict stands on, not an open menu; the shipped row is flagged",
            "frozen_dims_mm": {"rod": D_BUS, "channel": D_CHANNEL_MM, "liner_wall": 0.150},
            "candidates": allocations,
            "note": "radial_play answers ASSEMBLY, first_contact answers SUPPORT — different "
                    "questions, same row. Geometry does not discriminate (б)/(в)/(г): all three "
                    "land 25 µm radial. The discriminating costs are NOT computed here — wear "
                    "allowance (б), re-spec of the primary datum (в), fatigue σ ∝ 1/d³ (г).",
        },
        "verdict": (f"Monolithic bus at the canon rod O{D_BUS:.1f} (01_01 1.4), SHIPPED fabrication = "
                    f"{SHIPPED_BRANCH} (welded cold-drawn wire, ratified 2026-09-10): buckling non-issue "
                    f"(SF {p_cr_unsup / F_POGO_N:.0f}x); the bore liner doubles as lateral support -> "
                    f"fatigue SF {sup_lo:.1f}-{sup_hi:.1f}x (infinite life, all alloys). BARE, the drawn "
                    f"wire reaches infinite life for {len(shipped['unsupported_infinite_life'])} of "
                    f"{len(alloy_rows)} alloys (SF {uns_lo:.1f}-{uns_hi:.1f}x): dropping the as-printed "
                    f"derate lifted {', '.join(marginal) or 'the soft alloys'} OUT of predicted failure but "
                    "NOT over the SF-2 line. On the superseded PRINTED branch not one of the six cleared it. "
                    "BUT the fatigue ground for the liner is RETIRED, not narrowed (verdict 2026-09-11): "
                    f"the free-cantilever SF describes "
                    f"{', '.join(r['branch'] for r in regimes if r['regime'].startswith('free cantilever')) or 'NO shipped branch'}"
                    ", because every branch that leaves play takes it up and bears on the bore wall. "
                    "What the liner carries is WEAR - the contact is geometrically forced, and wear-through "
                    "is a ~0.5 V anode-cathode short. Liner = insulation + wear surface + lateral support; "
                    "NOT a fatigue fix (HW.34 sub-2). Per-alloy margin tracks yield = same ranking as "
                    "thermal -> leading HW.24 candidates win on both."),
        "caveats": "cyclic-load amplitude (pogo friction + PEEK flex) is an estimate; real sway spectrum "
                   "is bench/field (00_02). Comparative supported-vs-unsupported + per-alloy ranking robust. "
                   "WELD SEAM: its geometry is still NOT modelled (homogeneous cantilever), and the wrought "
                   "derate still describes the WIRE, not the JOINT. What IS modelled since 2026-09-12 is the "
                   "SENSITIVITY - the break-even knockdown k at which the seam crosses each line (see the "
                   "weld_seam block). k itself is NOT MEASURED and is not assumed here. Three seam mechanisms "
                   "stay outside even that bound, and their signs differ: bead section RELIEVES nominal "
                   "stress, weld-toe notch AGGRAVATES it, and weld residual TENSION is a mean stress this "
                   "file never carries - the endurance ratio is fully-reversed by construction.",
    }
    json_path = OUT_DIR / "bus_mechanical.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    # gate: the SUPPORTED rod must clear infinite life for the baseline alloy on the SHIPPED branch
    # (sanity, not a product pass/fail). ⛔ Declared ceiling: it judges one alloy in one branch, so it
    # stays green while any bare-rod or weld-seam question is open — those are verdicts, not gates.
    return 0 if endurance_MPa(sy_4v, shipped_derate) / sig_sup >= INFINITE_LIFE_SF else 1


if __name__ == "__main__":
    raise SystemExit(main())
