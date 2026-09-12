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
FORCED, and a 10 µm conformal film asked to be a bearing in a THROUGH bore of L/D ≈ 12.6 wears through to a
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
from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    CACHE_DIR,
    D_BUS_ROD_MM,
    E_PEEK_PA,
    NU_PEEK,
    REPO_ROOT,
    SIGMA_YIELD_PEEK_PA,
    T_ASSEMBLY_C,
    T_FOREST_MAX_C,
    T_FOREST_MIN_C,
)
from lib.mechanics import thick_wall_hoop
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Bus geometry (mm) — the ROD, not the Ø1.35 cathode channel it threads ──
# ⛔ Do not substitute the channel here: σ ∝ 1/d³, so the channel Ø inflates every fatigue SF ×2.46 and turns a
#    predicted failure into a comfortable margin. One home for the value: lib.constants (01_01 §1.4).
D_BUS = D_BUS_ROD_MM

# ── Axial stack (mm) — READ from the CEM manifests at runtime, never re-typed ─────────────────────
# 🔴 Every span below used to be a literal, and the costliest one decomposed ITSELF in prose — "gap 6
#    + cathode bore ~14 + flange/pad standoff ~16 = 36" — with the third term citing nothing. The CEM
#    stack says otherwise: the pad IS the rod's own end face (02_02 §1.2), so nothing protrudes past
#    the flange disc, and the span is 23 mm. σ ∝ L, so the free-cantilever column was over-stated
#    1.57× and every unsupported SF under-stated by the same factor (00_07 HW.34, fixed 2026-09-12).
# ⛔ The lesson is the FORM, not the number: a constant that decomposes itself in a comment READS as
#    derived and is not. These are derived — change a CEM field and they move.
CEM_DIR = REPO_ROOT / "tools" / "cad" / "cem"


def cem(stem: str) -> dict:
    """CEM manifests = the parameter SSOT of the shipped geometry (canon-gated by cem_canon_sync.rb)."""
    return json.loads((CEM_DIR / f"{stem}.json").read_text(encoding="utf-8"))


_FLANGE, _SLEEVE = cem("cathode_flange"), cem("zone2_sleeve")
SHANK_LEN_MM = float(_FLANGE["shank_length_mm"])        # Zone-3 shank — enters the sleeve from the top
FLANGE_THK_MM = float(_FLANGE["flange_thickness_mm"])   # the disc the pogo pad sits on
SLEEVE_LEN_MM = float(_SLEEVE["length_mm"])             # PEEK thermal break, axial (01_01 §4.1)
# ⚠️ The ONE term with no JSON field: how deep the Zone-1 anode inserts into the sleeve. Its only home
#    is `Cem.cs AnchorAxialStackCem.Zone1InsertionMm` — an HW.8 PLACEHOLDER, not a frozen dim — so it
#    crosses the machine halves BY VALUE, which is the caveat Cem.cs itself writes about scripts 54/58.
#    ⛔ Do not promote it into a CEM field to make this line look derived: that would canonise a
#    placeholder (00_06 §0). It is quoted here as what it is.
Z1_INSERTION_MM = 30.0
# F2 insertion budget (AxialStack.InsertionBudgetMm) — what is left of the sleeve bore once both shanks
# are in. This IS the unsupported PEEK gap: the rod crosses it with no wall on either side.
PEEK_GAP_MM = SLEEVE_LEN_MM - Z1_INSERTION_MM - SHANK_LEN_MM
# Free (laterally UNSUPPORTED) cantilever length in each case:
L_FREE_UNSUP = PEEK_GAP_MM + SHANK_LEN_MM + FLANGE_THK_MM   # full protrusion above the anode top
L_FREE_SUP = PEEK_GAP_MM                                    # liner supports the bore run → the gap only

# ── Loads ──
# ── Channel run (mm from the anode root) — the wall that the two branches above IGNORE ──
# Both L_FREE_* above are free-cantilever idealisations: they assume NO wall anywhere over the span.
# The real rod threads a Ø1.35 bore, so a branch that leaves a gap is neither of them — see §4 below.
# ⚠️ The run length is read CONSERVATIVELY (shorter = less room for contact to happen): the model's own
# decomposition of L_FREE_UNSUP says "cathode bore ~14", while cem/cathode_flange.json gives
# shank 14 + flange 3 = 17. Taking 14 makes the contact finding harder to reach, not easier.
CHANNEL_START_MM = PEEK_GAP_MM     # the PEEK gap ends and the bore begins
CHANNEL_LEN_MM = SHANK_LEN_MM      # conservative: the shank run ONLY, not the flange disc above it
# Full DRILLED depth of the bore (shank + flange disc). Distinct from CHANNEL_LEN_MM above, which is
# the deliberately-short span used for the CONTACT question; this one is the MACHINING referent, and it
# is what the L/D ratio is about — which operation the bore needs.
# ⛔ That ratio lived in prose (here and in SUMMARY) with no cache owner, so it could not be checked
#    against the diameter it divides by. Derived now.
BORE_DEPTH_MM = SHANK_LEN_MM + FLANGE_THK_MM
# ⛔ SECOND REFERENT, split out 2026-09-12 (00_07 HW.34): the thermal block below needs the LINER's
#    length, and it used to borrow the machining depth — one name for two quantities, so editing either
#    silently moved the other (the very class this file guards for D_BUS).
# ⛔ DO NOT re-declare this length an assumption, and do not drop the protrusion term: the axial
#    extent is RATIFIED (01_01 §1.4, founder-proxy 2026-09-12 — the tube covers the channel END TO
#    END and its lower end protrudes into the PEEK gap), so the liner runs the channel PLUS that
#    overhang. A constant calling a settled dimension «assumed» is worse than an unmarked one: it
#    tells the reader the number is soft when it is the spec.
# ⚠️ By-value crossing, declared: `AxialStack.LinerLengthMm` in tools/cad does this same arithmetic
#    (channel run + protrusion) over the same two CEM fields. Nothing binds the two halves; what binds
#    both to canon is `cem_canon_sync.rb` on the fields themselves.
LINER_PROTRUSION_MM = float(_FLANGE["bus_liner_protrusion_mm"])
LINER_LENGTH_MM = BORE_DEPTH_MM + LINER_PROTRUSION_MM
# ⛔ The channel is THROUGH, never blind: `CathodeFlange.cs` cuts z 0..14 in the shank and 14..17 in
# the disc, exiting the pogo face — and a blind bore could not pass a conductor at all. It matters
# because the L/D argument («the vendor picks the operation») is about a MACHINING class, and L/D 12.6
# through is a different class from L/D 12.6 blind: reaming from both ends, chip evacuation. The word
# «blind» was this file's own prose and reached five doc homes from here; swept 2026-09-12.
# ⛔ Both dims below were LITERALS (1.35 and a 0.150 repeated in four places) in a file that already
#    loads `_FLANGE` — i.e. the same "constant with no home" class its own D_BUS comment guards, and
#    the same one the protrusion fix cured by DERIVING rather than retyping. The manifest fields exist
#    and `cem_canon_sync.rb` pins them to canon, so reading them inherits the gate.
D_CHANNEL_MM = float(_FLANGE["bore_diameter_mm"])     # cathode channel Ø (canon 01_01 §1.4; OPENED
                                                      # 1.30 → 1.35, branch (в), 00_07 HW.34)
LINER_WALL_MM = float(_FLANGE["bus_liner_thickness_mm"])

# Insulation branches: wall thickness AND — new 2026-09-11 — WHICH SIDE the leftover play sits on.
# ⛔ The side is not bookkeeping, it changes what the BEAM is. A conformal film is bonded to the rod, so
#    its play is on the rod side by construction and the bending member is the bare Ti rod. The ratified
#    liner is the opposite: the tube is tight on the WIRE and the pair enters the bore as ONE body
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
    # ⛔ The label is DERIVED from the same field as the value: a literal label is free to keep
    #    saying 0.15 after the wall moves, and it is the label that test fixtures and prose quote.
    (f"PEEK liner {LINER_WALL_MM:.2f} mm", LINER_WALL_MM, "channel"),
)

# ── Composite bending stiffness, for the CHANNEL-side branch only ──
# With the tube tight on the wire the two bend together, so the member is stiffer than the bare rod and
# the wall is reached LATER — which is the conservative direction for the question "is the rod supported
# at the bore mouth". Bounds, both reported rather than one picked: LOWER = bare rod (tube slips, carries
# no shear), UPPER = full composite (perfect bond). Neither is measured; a press-fit polymer tube sits
# between them, and PEEK is soft enough that the whole span between the bounds is a few per cent.
# ⛔ ONE home: `lib.constants.E_PEEK_PA` (Victrex 450G, 23 °C). A local 3.6e9 lived here until
#    2026-09-12 — a SECOND PEEK modulus in a file that already imports the first, 10 % apart, feeding
#    the composite EI → first contact → the span-optimism term of the seam bound (00_07 HW.34).

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
ENDURANCE_OVER_YIELD = 0.45   # wrought-Ti fatigue ratio — a BAND 0.40-0.50, not a constant, and the
                              # band is written right here while only its MIDPOINT enters the model.
                              # ⚠️ Every SF scales LINEARLY with it: at 0.40 the binding link (Ta,
                              # welded, unsupported) reads 1.96, so the shipped verdict «all six clear
                              # SF 2» is a statement about the midpoint of an unmeasured band, not
                              # about the band. Found 2026-09-12 by a same-FORM sweep (a single point
                              # standing in for a coefficient); not yet swept — 00_07 HW.34.
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

# ── The FIT between the liner and the wire (00_07 HW.34) ──────────────────────────────────────
# ⚖️ 2026-09-11 ratified the DIRECTION of the assembly clearance: the play goes to the CHANNEL side,
# «the tube is tight on the WIRE and the pair enters the bore as one body». Every stiffness bound,
# every first-contact number and the whole wear axis rest on that sentence — and until this block
# existed NOTHING in the tree carried the interference it asserts — canon said so in as many words
# («натягу пари … у дереві НЕМАЄ ЖОДНОГО»), and ⛔ DO NOT grep for that sentence: the commit that
# wrote this block is the one that replaced it with the derived window, so the citation would be a
# quote of text it deleted. Provenance is `git log -S` on 01_01 §1.4, not a live phrase.
#
# 🔴 AND THE TUBE'S BORE NOMINAL IS SPECIFIED NOWHERE — the constant block below carries the
#    evidence and the correction. At the assumption the window is computed under (bore = rod Ø)
#    the fit is line-to-line, i.e. half the population comes out with clearance — the same shape
#    as the F3 gate's `≤` (00_07 HW.34, fixed 2026-09-11): a true statement about the arithmetic
#    and a false one about the assembly. ⛔ But «line-to-line» is that ASSUMPTION's consequence,
#    never a drawing's: nobody has specified the bore, so today the vendor's process centres it.
# 🔴 THE TUBE'S BORE NOMINAL IS SPECIFIED NOWHERE, and saying «canon names it ID 1.00» was wrong —
#    caught by adversarial review 2026-09-12, hours after this block shipped. Canon `01_01 §1.4`
#    says the OPPOSITE four sentences from the paragraph this block fed: the frozen dim is the
#    WALL (0.15), «а постачальник екструдованої PEEK-трубки продає й тримає ID та OD», and it tells
#    the reader to re-express the dim as an ID/OD pair before moving it. «ID 1.00» appears only in
#    an OPEN RFQ leg (`00_07` HW.34) and the procurement registry — a question, never a drawing.
# ⛔ So the honest state is WORSE than «line-to-line», and the worse version is the useful one:
#    nobody has specified the bore, therefore the fit is whatever the vendor's process happens to
#    centre on. The block computes the window under a DECLARED assumption (bore = rod Ø, the only
#    reading the tree supports) and says so in the cache instead of asserting a spec.
LINER_BORE_SPECIFIED_MM = None     # NOT SPECIFIED — no canon row, no drawing (00_07 HW.34 RFQ leg)
LINER_BORE_ASSUMED_MM = D_BUS      # the assumption the window is computed at, named as one
# ⛔ NOT MEASURED, and kept visibly absent for the same reason as WELD_KNOCKDOWN_MEASURED: there is no
#    canon row, no vendor answer and no measurement for either band, so a plausible number typed here
#    would be the FALLBACK species of fabrication (00_01 §1.1). What the model computes instead is the
#    question that CAN be answered from what we hold — the BUDGET the pair can absorb — against which
#    a vendor's answer becomes a verdict rather than a figure in a letter.
LINER_BORE_TOLERANCE_MEASURED_UM = None   # extruded PEEK tube ID band — RFQ (00_07 HW.34)
WIRE_OD_TOLERANCE_MEASURED_UM = None      # cold-drawn wire OD band — RFQ (00_07 HW.34)
# ⛔ NO measured or cited µ for PEEK-on-Ti exists anywhere in this tree, so this is a SWEEP and never
#    a value: its only job is to report whether the axial-lock verdict is µ-INVARIANT across it. The
#    low end is deliberately below anything a dry polymer/metal pair is likely to show, because the
#    interesting answer is the one that survives the friendliest assumption to the opposite case.
MU_PEEK_TI_SWEEP = (0.1, 0.2, 0.3, 0.4)

# ── WEAR — the ground the liner actually stands on (00_07 HW.34, ⚖️ 2026-09-11) ────────────────
# ⛔ NOT MEASURED, and kept visibly absent for the third time in this file, for the same reason as
#    WELD_KNOCKDOWN_MEASURED and the two vendor bands: there is no canon row, no vendor answer and no
#    measurement anywhere in this tree for a PEEK-on-Ti pair, so a plausible number typed here would
#    be the FALLBACK species of fabrication (00_01 §1.1). What §7 computes instead is the BUDGET —
#    the rate the pair may have and still keep the wall — so an accelerated tribo-test returns a
#    VERDICT rather than a figure in a report.
SPECIFIC_WEAR_RATE_MEASURED = None   # k_w [mm³/(N·m)] — Archard specific wear rate, NOT MEASURED
# ⛔ THE FLOW PRESSURE THAT BOUNDS THE CONTACT AREA IS A SWEEP, NOT A VALUE — and getting this wrong
#    is the difference between a budget and a flattering number. PEEK cannot carry a line load: it
#    flows until the pressure drops to what the material supports, so A ≥ R/p_flow and the budget is
#    proportional to that area. p_flow is NOT the tensile yield: a contact confined by the surrounding
#    material flows at the INDENTATION limit, classically ~3× yield (the same constraint factor that
#    puts HARDNESS, not yield, in Archard's own law). One end of the sweep would therefore over-state
#    the allowable area threefold, in the direction that makes the part look safe.
#    1.0 = unconfined simple compression (loosest) · 3.0 = fully-plastic indentation (tightest).
#    ⚠️ Neither is measured for PEEK at this geometry, and the yield they scale is the 23 °C TENSILE
#    datasheet figure while the contact is compressive and cold — so the pair is a bracket on the flow
#    pressure, never a value, and the CONSERVATIVE end drives every headline.
CONTACT_CONSTRAINT_FACTORS = (1.0, 3.0)
# Where the duty comes from. ⛔ NOT retyped: script 62 derived the sway-cycle count from ten years of
# real NASA POWER wind for Cherkasy and named two literature gaps it could not close, so a literal
# here would be a mirror of another script's result — the one thing the in-silico rule forbids
# outright. A missing cache is REPORTED, never defaulted: §7 simply does not compute.
WIND_CACHE = OUT_DIR / "wind_duty_cycle.json"

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
        ei += E_PEEK_PA * (np.pi / 4.0) * (r_o ** 4 - r_i ** 4)
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


def tip_load_slope_rad(force_lat_N: float, x_mm: float, length_mm: float,
                       ei_Nm2: float | None = None) -> float:
    """Slope θ(x) = dδ/dx of the same cantilever — the ANGLE at which the rod meets the bore.

    Analytic derivative of `tip_load_deflection_mm`, not a finite difference: θ = F·x·(2L−x)/(2EI).
    It answers a question the deflection cannot — WHETHER a chamfer would be met by the rod at all,
    since a lead-in at 30-45° is two orders steeper than this approach angle.
    """
    ei = ei_Nm2 if ei_Nm2 is not None else E_TI * second_moment_m4(D_BUS)
    x, ell = x_mm * MM_M, length_mm * MM_M
    return force_lat_N * x * (2.0 * ell - x) / (2.0 * ei)


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


def prop_reaction_N(force_lat_N: float, station_mm: float, gap_mm: float, length_mm: float,
                    ei_Nm2: float) -> float:
    """Wall reaction if the unilateral constraint is idealised as ONE rigid prop at `station_mm`.

    Compatibility, not equilibrium: the free tip-loaded shape overshoots the gap at that station by
    δ(a) − g, and the prop has to push it back through its own flexibility f = a³/(3EI). Hence
    R = (δ(a) − g)/f, clipped at zero where the rod does not reach the wall there.

    ⛔ Declared ceiling, and it is the whole reason the caller reports a BRACKET instead of a number:
    the real constraint is DISTRIBUTED over the run from first contact to the bore end, and no
    distributed-contact solution exists anywhere in this tree. A single prop is exact only for a
    single-point contact; the family of stations across the active run brackets the distributed case.
    Also rigid and frictionless — no contact compliance, no tangential traction at the prop.
    """
    over_mm = tip_load_deflection_mm(force_lat_N, station_mm, length_mm, ei_Nm2=ei_Nm2) - gap_mm
    if over_mm <= 0.0:
        return 0.0
    flex_m_per_N = (station_mm * MM_M) ** 3 / (3.0 * ei_Nm2)
    return over_mm * MM_M / flex_m_per_N


def surface_axial_slip_mm(force_lat_N: float, station_mm: float, length_mm: float,
                          radius_mm: float, ei_Nm2: float) -> float:
    """Axial travel of the CONTACT fibre between the unloaded and fully-loaded states (mm).

    Euler-Bernoulli kinematics, nothing more: plane sections stay plane and normal, so a fibre at
    `radius_mm` from the neutral axis displaces axially by r·θ(x) as the beam rotates. That is the
    only relative tangential motion the contact sees — the bore is fixed, the rod's surface slides
    past it — and it is what turns a cycle COUNT into a sliding DISTANCE.

    ⛔ Two declared ceilings, both in the CONSERVATIVE direction (they over-state the slip, so the
    budget they feed is tighter than the truth):
      (a) θ is the FREE slope; a rod held by the wall rotates less there;
      (b) the whole excursion is counted as sliding, while contact exists only over the part of it
          after touchdown.
    ⛔ What it is NOT: the second-order axial foreshortening of the beam (≈ 0.6·δ²/L, three orders
       smaller here) and any rolling component of the contact. Neither is modelled.
    """
    return radius_mm * tip_load_slope_rad(force_lat_N, station_mm, length_mm, ei_Nm2=ei_Nm2)


# ── The liner↔wire fit: Lamé on the tube, thermal on the pair, friction along it ──────────────
# ⛔ ONE geometry for all three, declared once: the tube is the SLEEVE (bore = rod radius, OD = bore +
#    wall) and the Ti wire is the SHAFT. `lib.mechanics.thick_wall_hoop` is exactly that case — rigid
#    inner, free outer. Two declared ceilings ride on it.
#    (a) RIGID INNER. E_Ti/E_PEEK ≈ 27, so the wire does compress a little and the true contact
#        pressure is slightly LOWER than this. That makes the yield-limited ceiling CONSERVATIVE
#        (the real allowable interference is a few per cent larger), which is the safe direction.
#    (b) FREE OUTER. The tube's OD is free only while it does not touch the Ø1.35 wall. That is not
#        assumed — `liner_od_growth_m` prices the growth and §6 checks the remaining play stays
#        positive across the whole band. If it ever did not, this whole model would be the wrong one.
LINER_BORE_M = ((LINER_BORE_SPECIFIED_MM or LINER_BORE_ASSUMED_MM) / 2.0) * MM_M
LINER_OD_M = LINER_BORE_M + LINER_WALL_MM * MM_M


def fit_state(delta_radial_m: float) -> dict:
    """Bore stress state of the liner at a given RADIAL interference on the wire (Pa)."""
    return thick_wall_hoop(delta_radial_m, LINER_BORE_M, LINER_OD_M, E_PEEK_PA, NU_PEEK)


def liner_thermal_interference_m(t_c: float, t_ref_c: float = T_ASSEMBLY_C) -> float:
    """Extra RADIAL interference on the WIRE when the pair sits at `t_c` (m).

    ⛔ Sign discipline, and this is the interface the canon sentence warns about mixing up: here PEEK
    is the OUTER member, so cooling shrinks it ONTO the wire and the interference GROWS (positive).
    On the OTHER interface — liner OD against the cathode bore — PEEK is the inner member and cooling
    pulls it AWAY, which is the ~2.0 µm diametral term §4 already carries. Same Δα, opposite effect.
    """
    alpha_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    return (ALPHA_PEEK_1K - alpha_ti) * (t_ref_c - t_c) * LINER_BORE_M


def liner_od_growth_m(p_c_Pa: float) -> float:
    """Radial growth of the liner OD under bore pressure `p_c` — Lamé, free outer surface.

    u(c) = (c/E)·σ_θ(c) with σ_θ(c) = 2·P_c·b²/(c²−b²). This is what EATS the channel play the
    clearance table above treats as a constant 25 µm: that figure is only true at ZERO interference,
    i.e. at exactly the fit the direction verdict rules out.
    """
    b2, c2 = LINER_BORE_M ** 2, LINER_OD_M ** 2
    return 2.0 * p_c_Pa * b2 * LINER_OD_M / (E_PEEK_PA * (c2 - b2))


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
    # 🔴 01_01 §1.4 carries the RADIAL thermal term (~2.0 µm diametral over 40 K) and was silent on the
    # axial one. It decides a question the radial term cannot touch: whether the liner may be captured
    # at BOTH ends. ⛔ This says nothing about WHICH end to fix — that is a geometry verdict
    # (00_07 HW.34); the model only prices the motion the verdict has to accommodate.
    # 🔴 AND SINCE §6 BELOW EXISTS, READ THAT FIRST: the motion priced here is the FREE differential
    #    growth, which is what a MECHANICAL capture has to accommodate. §6 measures that friction on
    #    the wire already restrains it over essentially the whole allowable interference band — so the
    #    stress below is incurred whichever end is captured, and «both ends» is not the discriminator
    #    the ratified ground reads as. The exception is a fit at the very FLOOR of that band, where the
    #    tube slips and relieves instead; nothing in the tree specifies which of the two we ship.
    alpha_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    d_alpha = ALPHA_PEEK_1K - alpha_ti
    axial_thermal = {
        "liner_length_mm": LINER_LENGTH_MM,
        # ⛔ DO NOT flip this back to an «assumed» flag — the axial extent is ratified, and a flag
        #    that calls a frozen dim soft is read downstream as «this may still move».
        "liner_length_is_ratified": True,
        "liner_length_provenance": "channel run (cem/cathode_flange shank + flange) + the RATIFIED "
                                   "protrusion (cem bus_liner_protrusion_mm, ⚖️ 01_01 §1.4 "
                                   "2026-09-12: tube covers the channel end to end, lower end "
                                   "protrudes into the PEEK gap). ⚠️ Canon states the protrusion as "
                                   "a MINIMUM (≥ 1.0 mm); the CEM nominal is taken, so a longer tube "
                                   "grows proportionally more",
        "alpha_peek_1K": ALPHA_PEEK_1K,
        "alpha_ti_1K": alpha_ti,
        "alpha_ti_source": ALLOY_BASELINE,
        "differential_axial_um_by_dT_K": {str(dt): round(d_alpha * LINER_LENGTH_MM * dt * 1000.0, 1)
                                          for dt in (20, 40, 60, 80)},
        "radial_diametral_um_at_40K": round(d_alpha * (D_BUS + 2.0 * LINER_WALL_MM) * 40.0 * 1000.0, 1),
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
        axial_thermal[f"constrained_stress_MPa_at_{dt_k}K"] = round(strain * E_PEEK_PA / 1e6, 2)
    print(f"\n  → Liner axial growth vs Ti over {LINER_LENGTH_MM:.1f} mm (channel {BORE_DEPTH_MM:.0f} + ratified protrusion {LINER_PROTRUSION_MM:.1f}, ⚖️ 2026-09-12): {ax40:.1f} µm at 40 K "
          f"({axial_thermal['differential_axial_um_by_dT_K']['80']:.0f} µm at 80 K). ⚠️ The radial "
          f"term carries the SAME strain —")
    print(f"    the {ax40 / axial_thermal['radial_diametral_um_at_40K']:.0f}× is the ratio of "
          f"reference LENGTHS (liner {LINER_LENGTH_MM:.1f} vs OD {D_BUS + 2 * LINER_WALL_MM:.2f}), not of demands.")
    print(f"  → Constraining it at BOTH ends costs {axial_thermal['constrained_stress_MPa_at_40K']:.1f} MPa "
          f"at 40 K ({axial_thermal['constrained_stress_MPa_at_80K']:.1f} at 80 K) of axial compression —")
    print("    a few per cent of PEEK yield, so it is NOT an impossibility. ⛔ What argues against")
    print("    both-end capture is 20 yr of creep/relaxation ratcheting, which this file does NOT")
    print("    model; which end is fixed is a geometry verdict either way (00_07 HW.34).")

    # ── 4b. WHERE the wall actually starts — the assumption every contact number above makes ────
    # 🔴 `first_wall_contact_mm` bisects from the ROOT and assumes a wall over the whole span. There
    # is none for the first `CHANNEL_START_MM`: that run is the PEEK gap inside the Ø11 sleeve bore,
    # where the rod has millimetres of room, not micrometres. So a computed contact SHORTER than the
    # mouth does not mean «it touches there» — it means the rod has ALREADY exceeded the play by the
    # time it reaches the mouth, and what it meets is the bore EDGE, not the wall.
    # ⛔ Why this is a verdict input and not a footnote (00_07 HW.34, the open ⚖️ on the liner's AXIAL
    # extent): a liner that starts flush with the mouth puts that first contact on its own end face /
    # the titanium edge — a line contact and a stress raiser — while a liner protruding into the gap
    # puts it on polymer, distributed. Canon freezes the 0.15 WALL and says nothing about where the
    # tube begins, so the model prices the CONDITION and leaves the choice to the verdict.
    # ⚠️ Declared ceiling: this derives a GEOMETRIC condition (free deflection at the mouth vs play),
    # never the edge stress itself — no notch factor and no contact model exists anywhere here.
    banner("Where the wall starts — is first contact an EDGE, not a wall? (input to the axial ⚖️)")
    edge_rows = []
    for r in regimes:
        ei_eff = r["ei_Nm2_bonded"]
        per_mu = {}
        for mu in MU_SWEEP:
            d_mouth = tip_load_deflection_mm(mu * F_POGO_N, CHANNEL_START_MM, L_FREE_UNSUP, ei_Nm2=ei_eff)
            slope = tip_load_slope_rad(mu * F_POGO_N, CHANNEL_START_MM, L_FREE_UNSUP, ei_Nm2=ei_eff)
            per_mu[mu] = {"deflection_at_mouth_um": round(d_mouth * 1000.0, 1),
                          "edge_bearing": bool(d_mouth > r["radial_play_mm"]),
                          # How far the rod WANTS to be inside the wall when it arrives. Elastic
                          # contact has to absorb exactly this — on a sharp edge, over ~no area.
                          "interference_at_mouth_um": round(max(0.0, d_mouth - r["radial_play_mm"]) * 1000.0, 1),
                          # The approach angle. A lead-in chamfer is cut at 30-45°; if the rod
                          # arrives two orders flatter, the chamfer is not what it lands on — the
                          # chamfer/cylinder junction is, i.e. the edge simply MOVES inward.
                          "approach_angle_deg": round(float(np.degrees(slope)), 3)}
        edge_mus = [mu for mu, v in per_mu.items() if v["edge_bearing"]]
        edge_rows.append({"branch": r["branch"], "radial_play_um": round(r["radial_play_mm"] * 1000.0, 1),
                          "by_mu": per_mu, "edge_bearing_mus": edge_mus,
                          "edge_bearing_on_any_mu": bool(edge_mus)})
        state = (f"EDGE at µ {', '.join(str(m) for m in edge_mus)}" if edge_mus else "no edge contact on any swept µ")
        print(f"  {r['branch']:<24s} play {r['radial_play_mm'] * 1000:>5.1f} µm · "
              f"free deflection at the mouth "
              f"{min(v['deflection_at_mouth_um'] for v in per_mu.values()):>5.1f}–"
              f"{max(v['deflection_at_mouth_um'] for v in per_mu.values()):>5.1f} µm   → {state}")
    _edge_any = [r["branch"] for r in edge_rows if r["edge_bearing_on_any_mu"]]
    print(f"  → Branches whose first contact is the bore EDGE on at least one swept µ: "
          f"{', '.join(_edge_any) or 'none'} (DERIVED).")
    _worst = max((v for r in edge_rows for v in r["by_mu"].values()),
                 key=lambda v: v["interference_at_mouth_um"])
    print(f"  → Worst corner: the member wants to be {_worst['interference_at_mouth_um']:.1f} µm INSIDE the "
          f"wall on arrival, meeting it at {_worst['approach_angle_deg']:.2f}°.")
    print("    🔴 Two consequences, and the second one kills the obvious fix. (1) On a SHARP edge that")
    print("    interference is taken over ~no area, so the contact is a stress raiser by construction —")
    print("    and no chamfer/radius is specified anywhere in the tree (canon, CEM, generator: zero hits).")
    print("    (2) ⛔ A LEAD-IN CHAMFER does not solve it: cut at 30-45° it is two orders steeper than")
    print("    the approach angle above, so the rod never lands on the chamfer face — it lands where")
    print("    the chamfer meets the cylinder. A chamfer MOVES the edge inward; only a RADIUS removes it.")
    # ⛔ The materials do NOT change with the tube's start, and saying they do was wrong: the ratified
    #    direction puts the play on the CHANNEL side, so what meets the bore is the tube's OUTER
    #    surface — polymer against titanium either way. What DOES change is which FEATURE meets it.
    #    Flush with the mouth, the tube's own END FACE arrives at the bore edge: ring against ring.
    #    Started earlier, the edge meets the tube's cylindrical flank instead. Derived below is the
    #    protrusion at which that is true for EVERY swept µ, i.e. the earliest computed contact.
    _chan = [r for r in regimes if r["play_side"] == "channel"]
    # 🔴 The BONDED column, and the correction matters more than the number: this used to read
    #    `first_contact_mm_by_mu` (the BARE rod), while §2 of this same file declares the composite
    #    to be the member for the channel-side branch — «the tube is tight on the WIRE and the pair
    #    enters the bore as ONE body». So the ratified protrusion cited the configuration the
    #    direction verdict EXCLUDES, which is the exact row-mix this commit congratulated itself
    #    for finding in the play table (found by adversarial review 2026-09-12). The neighbour
    #    `supported_span_check` already used the bonded column, so one section picked bare and the
    #    next picked bonded, unexplained. ⚖️ The ratified ≥ 1.0 mm STANDS and is now conservative
    #    by a larger margin, not by accident.
    earliest = min(min(r["first_contact_mm_by_mu_bonded"].values()) for r in _chan) if _chan else None
    liner_start = None
    if earliest is not None:
        liner_start = {
            "earliest_computed_contact_mm_from_root": round(earliest, 2),
            "mouth_mm": CHANNEL_START_MM,
            "min_protrusion_into_gap_mm": round(max(0.0, CHANNEL_START_MM - earliest), 2),
            "why": "below this the bore edge arrives at the tube's END FACE (ring on ring) instead of "
                   "its cylindrical flank; the materials are the same either way (play is channel-side, "
                   "so the tube's outer surface is what meets the bore), the FEATURE is not",
            "not_modelled": "the contact stress itself — no notch factor, no contact model, and no wear "
                            "model exists anywhere in this tree (00_07 HW.34)",
        }
        print(f"  → For the edge to meet the tube's FLANK rather than its END FACE on every swept µ, the "
              f"tube must start {liner_start['min_protrusion_into_gap_mm']:.2f} mm before the mouth "
              f"(earliest computed contact {earliest:.2f} mm from the root, DERIVED).")
        print("    ⛔ The tube is tight on the WIRE, so protruding does NOT leave it unsupported — it")
        print("    rides the rod. What protrusion costs is length, not a new free span.")

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
        shipped_row = (abs(rod_mm - D_BUS) < 1e-9 and abs(liner_mm - LINER_WALL_MM) < 1e-9
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
    # ⛔ DERIVED from the rows just printed. A typed "3.9-6.3 mm" stood here and had drifted off its
    #    own table by the time the protrusion was corrected — the exact class this file guards.
    _ok = [a for a in allocations if a["assembles"]]
    _c = [x for a in _ok for x in a["first_contact_mm_by_mu"].values()]
    _play = {round(a["radial_play_mm"] * 1000) for a in _ok}
    print(f"\n  → Every non-(а) candidate lands the SAME "
          f"{'/'.join(str(p) for p in sorted(_play))} µm radial play by construction, so the")
    print(f"    support question does NOT discriminate between them — first contact is "
          f"{min(_c):.1f}–{max(_c):.1f} mm in")
    print("    all three, i.e. practically at the bore mouth. The verdict is decided by the COSTS")
    print("    named over the table, never by this geometry. ⛔ (а) is listed to show it is not an")
    print("    option: zero diametral clearance is the F3 gate's arithmetic, not an assembly.")
    # ⛔ DERIVED, never typed — this sentence is the ground the lining verdict stands on.
    print(f"\n  → The free-cantilever SF above describes NO branch that bears on the wall: "
          f"{', '.join(gap_limited) or 'none'}.")
    print(f"    For those the effective span is a FRACTION of the {L_FREE_UNSUP:.0f} mm span priced "
          f"above, so the")
    print("    unsupported SF is a number for a configuration that does not exist — while the contact")
    print("    it implies is FORCED by geometry on every µ, which is a wear question, not a fatigue one.")
    # ⚠️ The flag is binary and the branches are NOT equivalent — read the DEPTH, not the label, and
    # read how MANY friction points reach the wall at all. 🔴 Both used to be typed here ("the liner
    # bears 0.5 mm past the mouth, a conformal film 10-17 mm in") and both went stale the moment the
    # protrusion was corrected 2026-09-12: on the true 23 mm span a conformal film no longer reaches
    # the wall inside the bore at LOW friction, so «contact is forced on every µ» — the sentence the
    # lining verdict leaned on — is now true of the LINER and only partly true of a film.
    for r in regimes:
        inside = [mu for mu, x in r["first_contact_mm_by_mu_bonded"].items() if x < channel_end]
        depth = min(r["first_contact_mm_by_mu_bonded"].values()) - CHANNEL_START_MM
        print(f"    ⚠️ {r['branch']:<24s} bears at {depth:+.1f} mm vs the mouth, on "
              f"{len(inside)}/{len(MU_SWEEP)} of the swept µ"
              f"{' — NOT on the whole sweep' if len(inside) < len(MU_SWEEP) else ''}")

    # ── 5. The WELD SEAM at the root — how bad may the JOINT be? (00_07 HW.34) ───────────────────
    # 🔴 The question §2 answers for the WIRE and never for the JOINT. Canon (01_01 §1.4 and the
    # factory protocol §3 step 1) sent the reader here for this state while nothing here held it.
    # 🔴 «Priced on the SUPPORTED span ONLY» stood here until 2026-09-12 and was FALSE — caught by
    # adversarial review, and the mechanism was this file's own: the conservatism term comes from
    # `supported_span_check`, which measures first contact along `L_FREE_UNSUP`. ⛔ That coupling is
    # REAL and is not removed — the seam bound rides the protrusion by construction, so the honest
    # fix was the INPUT, not the declaration: the protrusion is derived from the CEM stack now
    # (23 mm), where it used to be a literal 36 that decomposed itself in a comment.
    #
    # ⛔ AND THE HEADLINE REVERSED WHEN IT LANDED (2026-09-12). At 36 mm the span optimism read
    # 8.5 % and our own as-printed marker cleared the SF-2 line; at the true 23 mm the optimism is
    # ~40 %, the stress is higher, and the binding alloy NO LONGER clears it. The bound did not get
    # worse — it was never that good, and the model was reading a span the part does not have.
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

    # ⛔ §5b stood here until 2026-09-12 and swept the seam bound over TWO protrusions, because the
    # span it rides was a literal under open correction. The correction landed (the span is CEM-derived
    # now), so the sweep priced a dispute that no longer exists and is gone with it. What survives is
    # the DEPENDENCE, recorded in `span_provenance` below — the term is still measured along the
    # protrusion, and that is a property of the mechanism, not of the bad constant.
    print(f"\n  → Span: the optimism term is measured along the protrusion "
          f"({L_FREE_UNSUP:.0f} mm, CEM-derived), so the bound moves with the axial stack.")

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
        "span": {"which": "supported (liner) span, inflated by an optimism term measured along the "
                          "protrusion — NOT a supported-only figure, see span_provenance",
                 "nominal_sigma_MPa": round(sig_sup, 1),
                 "worst_corner_sigma_MPa": round(sig_sup_worst, 1),
                 "worst_corner_mu": mu_worst,
                 "span_optimism_pct": round(100.0 * (span_inflation - 1.0), 1),
                 "why_not_free_cantilever": "§4's derived flag says the free-cantilever SF describes "
                                            "no branch that bears on the wall, so a seam tolerance "
                                            "computed on it would price a configuration that does "
                                            "not exist (the error the 2026-09-11 verdict corrected)"},
        "per_alloy": seam_rows,
        # 🔴 Read this BEFORE `binding_candidate`: the bound rides the PROTRUSION through the span
        # optimism term, so the span's provenance is part of the result, not metadata.
        "span_provenance": {
            "protrusion_mm": L_FREE_UNSUP,
            "derived_from": "cem/zone2_sleeve.length_mm - Cem.cs Zone1InsertionMm (HW.8 placeholder, "
                            "no JSON field) - cem/cathode_flange.shank_length_mm, + shank + "
                            "flange_thickness_mm",
            "was_literal_until": "2026-09-12",
            "note": "a literal 36 mm stood here and decomposed itself in a comment whose third term "
                    "cited nothing; the CEM stack gives 23. The reversal it caused is recorded in "
                    "00_07 HW.34 — at 36 our own as-printed marker cleared the SF-2 line, at 23 it "
                    "does not. The bound did not worsen; it was reading a span the part does not have",
        },
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

    # ── 6. The liner↔wire FIT — the interference the ratified direction asserts (00_07 HW.34) ────
    # 🔴 §2–§5 all stand on one sentence of the 2026-09-11 direction verdict: «the tube is tight on
    # the WIRE and the pair enters the bore as one body». The composite stiffness bound, the
    # first-contact numbers, the wear axis and the whole edge-bearing block inherit it — and the
    # interference that sentence asserts existed NOWHERE, which canon states outright.
    # ⛔ Same inversion as §5, and for the same reason: both vendor bands are unmeasured, so the model
    # bounds what it CAN — the window the geometry allows — and reports the BUDGET. A vendor answer is
    # then judged against a number instead of read into a blank.
    banner("Liner↔wire fit — the interference window (00_07 HW.34)")
    t_ref = T_ASSEMBLY_C
    g_cold = liner_thermal_interference_m(T_FOREST_MIN_C, t_ref)   # > 0: cold grips harder
    g_hot = liner_thermal_interference_m(T_FOREST_MAX_C, t_ref)    # < 0: heat loosens it
    unit = fit_state(1e-6)                                          # everything here is linear in δ
    per_um = {k: v / 1e-6 for k, v in unit.items()}                 # Pa per metre of interference
    # CEILING — von Mises at the bore reaches PEEK yield, evaluated at the COLD extreme where the
    # thermal term ADDS. ⛔ vM governs, not hoop: at this wall ratio σ_vm/σ_t ≈ 1.15, so pinning the
    # ceiling on the hoop alone would allow ~15 % more interference than the material does.
    d_yield_vm = SIGMA_YIELD_PEEK_PA / per_um["sigma_vm"]
    d_yield_hoop = SIGMA_YIELD_PEEK_PA / per_um["sigma_t"]
    ceiling = d_yield_vm - g_cold
    # FLOOR — the fit must still BE a fit at the hot extreme, i.e. survive the thermal loss. This is
    # the weakest possible floor and it is named as such: it only asks that interference not reach
    # zero, never that it be enough for anything.
    floor = -g_hot
    window = ceiling - floor
    print(f"  Pair: wire Ø{D_BUS:.2f} in a tube bore Ø{2 * LINER_BORE_M / MM_M:.2f} (ASSUMED — not specified anywhere), wall "
          f"{LINER_WALL_MM:.3f} ⇒ OD Ø{2 * LINER_OD_M / MM_M:.2f} (CEM-derived).")
    print("  🔴 The tube's bore nominal is NOT SPECIFIED anywhere — canon freezes the WALL and says the")
    print("     supplier holds ID/OD. So «tight on the wire» is not even a tolerance outcome yet: it is")
    print("     whatever the vendor's process centres on. The window below assumes bore = rod Ø.")
    print(f"  Thermal on THIS interface (PEEK outside ⇒ cold grips): {g_cold * 1e6:+.2f} µm radial at "
          f"{T_FOREST_MIN_C:.0f} °C, {g_hot * 1e6:+.2f} µm at {T_FOREST_MAX_C:.0f} °C (ref {t_ref:.0f} °C).")
    print(f"  σ per µm of radial interference: P_c {per_um['P_c'] * 1e-12:.2f} · σ_t "
          f"{per_um['sigma_t'] * 1e-12:.2f} · σ_vm {per_um['sigma_vm'] * 1e-12:.2f} MPa/µm.")
    print(f"  → WINDOW (as-manufactured at {t_ref:.0f} °C): {floor * 1e6:.2f} … {ceiling * 1e6:.2f} µm "
          f"radial = {window * 2e6:.1f} µm DIAMETRAL budget for BOTH parts together.")
    print(f"    Ceiling = σ_vm at the bore hits PEEK yield {SIGMA_YIELD_PEEK_PA / 1e6:.0f} MPa at "
          f"{T_FOREST_MIN_C:.0f} °C ({d_yield_vm * 1e6:.2f} µm there, {d_yield_hoop * 1e6:.2f} on hoop alone);")
    print(f"    floor = the thermal loss at {T_FOREST_MAX_C:.0f} °C, i.e. the fit merely stays a fit.")
    print(f"  ⛔ To land INSIDE that window the NOMINAL must move: the tube bore has to run "
          f"{(floor + ceiling) / 2 * 2e6:.1f} µm under the wire")
    print("     diametrally at mid-window. That is a ⚖️ (a nominal interference, or a graded/selected")
    print("     fit, or a heated assembly — available only BEFORE enzyme functionalisation), not a")
    print("     tolerance question, and it is NOT decided here.")

    # The play the clearance table above treats as a constant — priced across the window.
    play_nominal = (D_CHANNEL_MM - (D_BUS + 2.0 * LINER_WALL_MM)) / 2.0 * MM_M
    play_rows = []
    for label, d in (("floor", floor), ("mid-window", 0.5 * (floor + ceiling)), ("ceiling", ceiling)):
        growth = liner_od_growth_m(per_um["P_c"] * d)
        play_rows.append({"at": label, "interference_radial_um": round(d * 1e6, 2),
                          "od_growth_radial_um": round(growth * 1e6, 2),
                          "channel_radial_play_um": round((play_nominal - growth) * 1e6, 2),
                          "outer_surface_still_free": bool(growth < play_nominal)})
        print(f"    {label:<11s} δ {d * 1e6:>5.2f} µm → OD +{growth * 1e6:>5.2f} µm radial → channel "
              f"play {play_nominal * 1e6:.1f} → {(play_nominal - growth) * 1e6:>5.2f} µm")
    print(f"  🔴 So the {play_nominal * 1e6:.0f} µm radial play §2 and §4 use is the value at ZERO "
          f"interference — the one fit the direction")
    print("     verdict excludes. At the top of the window it is ~40 % smaller, which makes edge")
    print("     bearing MORE likely, not less: the same geometry, read at the fit that ships.")

    # Axial friction lock — does the wire hold the tube, or does the CAPTURED END hold it?
    a_tube = np.pi * (LINER_OD_M ** 2 - LINER_BORE_M ** 2)
    peri = np.pi * (2.0 * LINER_BORE_M) * (LINER_LENGTH_MM * MM_M)
    lock_rows = []
    for dt_k in (40, 80):
        sig_z = d_alpha * dt_k * E_PEEK_PA
        f_thermal = sig_z * a_tube
        mu_delta = f_thermal / (per_um["P_c"] * peri)     # the product that balances it, m
        by_mu = {}
        for mu in MU_PEEK_TI_SWEEP:
            d_slip = mu_delta / mu
            # Full lock of the mid-section needs the shear to accumulate within HALF the length.
            d_full = 2.0 * d_slip
            by_mu[mu] = {"slip_threshold_um": round(d_slip * 1e6, 3),
                         "full_lock_threshold_um": round(d_full * 1e6, 3),
                         "floor_is_locked": bool(floor >= d_full),
                         "floor_holds_at_all": bool(floor >= d_slip)}
        lock_rows.append({"delta_T_K": dt_k, "axial_stress_MPa": round(sig_z / 1e6, 2),
                          "differential_force_N": round(f_thermal, 3),
                          "mu_times_delta_break_even_um": round(mu_delta * 1e6, 4), "by_mu": by_mu})
        worst = by_mu[min(MU_PEEK_TI_SWEEP)]
        print(f"\n  ΔT {dt_k} K: the tube's differential growth needs {f_thermal:.2f} N to restrain "
              f"({sig_z / 1e6:.1f} MPa axial).")
        print(f"    Friction on the wire supplies it once µ·δ ≥ {mu_delta * 1e6:.3f} µm; at the "
              f"friendliest µ {min(MU_PEEK_TI_SWEEP):.1f} that is δ ≥ "
              f"{worst['slip_threshold_um']:.2f} µm to hold at all, {worst['full_lock_threshold_um']:.2f} µm to lock the mid-section.")
    # ⛔ DERIVED, never typed: the verdict is whether the whole window is on one side of that line.
    locked_everywhere = all(r["by_mu"][mu]["floor_is_locked"] for r in lock_rows for mu in MU_PEEK_TI_SWEEP)
    locked_above_floor = all(v["full_lock_threshold_um"] * 1e-6 < ceiling
                             for r in lock_rows for v in r["by_mu"].values())
    print(f"\n  → Locked over the WHOLE window including its floor, on every swept µ: {locked_everywhere}.")
    print(f"    Locked somewhere below the ceiling on every swept µ: {locked_above_floor}.")
    print("  🔴 Consequence for the OPEN ⚖️ «which end is fixed»: above a fraction of a micrometre the")
    print("     WIRE is the second capture, so the differential stress §4 prices is incurred whichever")
    print("     end is mechanically fixed — the ratified ground («both-end capture is what 20 yr of")
    print("     creep forbids») does not discriminate there. It discriminates ONLY at the very floor,")
    print("     where the tube slips and relieves. ⛔ Which of the two ships is set by a number no")
    print("     drawing carries, so this is an input to that verdict, not an answer to it.")

    interference_window = {
        "question": "00_07 HW.34 — the 2026-09-11 direction verdict asserts the tube is TIGHT on the "
                    "wire; canon states no interference for that pair exists anywhere (01_01 1.4). "
                    "This block derives the window the geometry allows, so a vendor tolerance becomes "
                    "judgeable instead of being read into a blank",
        "pair_mm": {"wire_dia": D_BUS, "liner_bore_assumed": LINER_BORE_ASSUMED_MM,
                    "liner_wall": LINER_WALL_MM, "liner_od_nominal": round(2 * LINER_OD_M / MM_M, 3),
                    "liner_length": LINER_LENGTH_MM},
        "bore_nominal_specified_mm": LINER_BORE_SPECIFIED_MM,
        "bore_nominal_is_assumed": bool(LINER_BORE_SPECIFIED_MM is None),
        "nominal_finding": "the tube's bore nominal is SPECIFIED NOWHERE. Canon freezes the WALL "
                           "(0.15) and states that the extruded-tube supplier holds ID and OD, i.e. "
                           "the bought part is dimensioned by a quantity its process does not "
                           "control; 'ID 1.00' lives only in an OPEN RFQ leg, never on a drawing. "
                           "So the ratified 'tight on the wire' is not a tolerance outcome yet - it "
                           "is whatever the vendor's process centres on, and at the assumed "
                           "bore = rod diameter it is a line-to-line fit where half the population "
                           "comes out with clearance. Landing inside the window needs a SPECIFIED "
                           "nominal interference - a verdict (00_07 HW.34), not a tolerance. "
                           "CORRECTED 2026-09-12: this key used to assert the nominals as a SPEC "
                           "and compared D_BUS with itself, so the flag was identically true and "
                           "could never falsify",
        "thermal": {"t_ref_c": t_ref, "t_min_c": T_FOREST_MIN_C, "t_max_c": T_FOREST_MAX_C,
                    "radial_gain_at_t_min_um": round(g_cold * 1e6, 3),
                    "radial_loss_at_t_max_um": round(g_hot * 1e6, 3),
                    "sign_note": "PEEK is the OUTER member on THIS interface, so cooling grips "
                                 "harder; on the liner-OD/bore interface it is the inner member and "
                                 "cooling pulls away (the ~2.0 um diametral term in axial_thermal). "
                                 "Same Delta-alpha, opposite effect - the confusion canon warns about"},
        "per_um_radial_MPa": {k: round(v * 1e-12, 3) for k, v in per_um.items()},
        "floor": {"radial_um": round(floor * 1e6, 3),
                  "ground": "the fit must still be a fit at the hot extreme; this asks only that the "
                            "interference not reach zero, never that it suffice for anything"},
        "ceiling": {"radial_um": round(ceiling * 1e6, 2),
                    "criterion": "von Mises at the liner bore = PEEK tensile yield, evaluated at the "
                                 "COLD extreme where the thermal term adds",
                    "yield_MPa": SIGMA_YIELD_PEEK_PA / 1e6,
                    "delta_at_yield_cold_um": round(d_yield_vm * 1e6, 2),
                    "delta_at_yield_hoop_only_um": round(d_yield_hoop * 1e6, 2),
                    "why_von_mises": "sigma_vm/sigma_t ~ 1.15 at this wall ratio, so a hoop-only "
                                     "ceiling would allow ~15 % more interference than the material"},
        "window_radial_um": round(window * 1e6, 2),
        "window_diametral_um": round(window * 2e6, 2),
        "required_nominal_offset_diametral_um": round((floor + ceiling) / 2 * 2e6, 2),
        "vendor_inputs_measured": {"liner_bore_tolerance_um": LINER_BORE_TOLERANCE_MEASURED_UM,
                                   "wire_od_tolerance_um": WIRE_OD_TOLERANCE_MEASURED_UM,
                                   "source": "NOT MEASURED - zero data in this tree for either band "
                                             "(00_07 HW.34, two open RFQ legs). The diametral window "
                                             "above is what their SUM may occupy; a quoted band wider "
                                             "than it means the ratified fit cannot be bought, it has "
                                             "to be selected, machined or heat-assembled"},
        "od_growth_eats_channel_play": {"nominal_radial_play_um": round(play_nominal * 1e6, 2),
                                        "rows": play_rows,
                                        "note": "the 25 um the clearance table uses is the ZERO-"
                                                "interference value, i.e. the one fit the direction "
                                                "verdict excludes; at the ceiling it is ~40 % smaller, "
                                                "which makes EDGE bearing more likely, not less"},
        "axial_friction_lock": {"mu_is_swept_not_measured": True,
                                "mu_sweep": list(MU_PEEK_TI_SWEEP),
                                "tube_section_mm2": round(a_tube / (MM_M ** 2), 4),
                                "rows": lock_rows,
                                "locked_over_whole_window": bool(locked_everywhere),
                                "locked_below_ceiling_on_every_mu": bool(locked_above_floor),
                                "not_modelled": "the thermal SIGN coupling, and it bites at the floor: "
                                                "the floor is DEFINED as the interference that just "
                                                "survives +40 C, so AT the floor at the hot extreme the "
                                                "interference is 0 and so is the grip - for every mu. "
                                                "The grip here is priced from P_c at the 20 C reference "
                                                "while loading a 40-80 K excursion, so `floor_is_locked` "
                                                "describes the reference state, never the end of the "
                                                "excursion that removes it. Anywhere above the floor the "
                                                "coupling is second-order; at the floor it is the whole "
                                                "answer (adversarial review 2026-09-12)",
                                "consequence": "above a fraction of a micrometre the WIRE is the "
                                               "second capture, so the differential axial stress is "
                                               "incurred whichever end is mechanically fixed. The "
                                               "ratified ground for one-end capture (20 yr creep "
                                               "under sustained compression) therefore does not "
                                               "discriminate except at the window FLOOR, where the "
                                               "tube slips and relieves instead - and nothing "
                                               "specifies which of the two ships (00_07 HW.34)"},
        "not_modelled": {"creep_relaxation": "PEEK relaxes under sustained hoop stress, so over 20 yr "
                                             "the real floor RISES (grip decays) and the real ceiling "
                                             "FALLS (sustained stress limit < yield). The true window "
                                             "is NARROWER than this on BOTH sides. 01_01 4.3 "
                                             "tabulates relaxation and nothing reads it into this chain",
                         "temperature_dependence": "E_PEEK and the yield are the 23 C datasheet "
                                                   "values; both move at -30 C and in opposite "
                                                   "directions for this bound",
                         "form_error": "tube ovality, wire out-of-round and bore straightness are "
                                       "assumed zero; a real pair consumes part of this window on "
                                       "form before it consumes any on size",
                         "surface": "asperity flattening on assembly reduces the effective "
                                    "interference, and no Sa for either surface exists in canon",
                         "insertion_force": "the force to press the tube onto the wire is not "
                                            "computed; at the ceiling it is a real handling question"},
    }

    # ── 7. WEAR — the budget for the ground the liner actually STANDS on (00_07 HW.34) ────────────
    # 🔴 ⚖️ 2026-09-11 retired the fatigue ground and replaced it with WEAR. Until this block nothing
    # in this tree computed it: every `wear`/`fretting` mention in this file was PROSE, one of them
    # literally «The discriminating costs are NOT computed here», so «rated for 20 years» was a claim
    # with no instrument — and FMEA #21, the highest RPN in the whole register, asserted wear-through
    # outright. An assertion and its denial were both available and neither was measurable.
    # ⛔ Same inversion as §5 and §6, third time, same reason: the specific wear rate of PEEK on Ti is
    #    NOT in this tree, so the model bounds what it CAN — the rate the pair may have and still keep
    #    the wall — and an accelerated tribo-test then returns a VERDICT instead of a figure.
    # 🔑 THE CHAIN, so a reader can attack each link separately:
    #    duty  = (cycles from script 62's real-wind cache) × (slip per cycle from beam kinematics)
    #    load  = propped-cantilever reaction at the wall, bracketed over the active run
    #    budget= wear-through volume / (load × duty), with the area bracketed between a bound the
    #            MATERIAL sets and the full projected bearing area
    banner("Wear budget — what rate may the pair have and still keep the wall? (00_07 HW.34)")
    # 🔑 SELF-CHECK against a CLOSED-FORM solution, not against a frozen baseline. A regression pin
    #    proves a number stopped moving; these prove it is RIGHT, and one line each covers the
    #    deflection formula, the flexibility, the unit handling and the sign together.
    #    (a) A prop at the TIP with ZERO gap must carry the ENTIRE tip load: R = δ(L)/f(L) = F exactly.
    #    (b) The slope at the tip of a tip-loaded cantilever is F·L²/(2EI), so the surface fibre's
    #        axial travel there is exactly r·F·L²/(2EI).
    _ei_chk = flexural_rigidity_Nm2(D_BUS)
    _f_chk = MU_CONTACT * F_POGO_N
    assert abs(prop_reaction_N(_f_chk, L_FREE_UNSUP, 0.0, L_FREE_UNSUP, _ei_chk) - _f_chk) < 1e-9, \
        "a zero-gap prop at the tip must carry the whole tip load"
    _slip_closed = (D_BUS / 2.0) * _f_chk * (L_FREE_UNSUP * MM_M) ** 2 / (2.0 * _ei_chk)
    assert abs(surface_axial_slip_mm(_f_chk, L_FREE_UNSUP, L_FREE_UNSUP, D_BUS / 2.0, _ei_chk)
               - _slip_closed) < 1e-12, "tip slip diverged from r·F·L²/(2EI)"
    wear_rows: list[dict] = []
    duty_anchors: list[dict] = []
    thermal_rows: list[dict] = []
    binding_wear: dict | None = None
    wind = None
    if WIND_CACHE.exists():
        wind = json.loads(WIND_CACHE.read_text())
        for row in wind.get("beaufort_exceedance", []):
            duty_anchors.append({"anchor": row["anchor"], "n_cycles": float(row["n_eff_cycles_upper_bound"])})
        # The raw 20 yr × 1 Hz budget, kept as the ABSOLUTE ceiling: script 62's own verdict is that
        # the duty does NOT close to a single number (two named literature gaps), so the bracket is
        # the honest object and its top is this.
        duty_anchors.append({"anchor": "raw 20 yr x 1 Hz upper bound (script 62 ceiling)",
                             "n_cycles": float(wind["budget_cycles_upper_bound"])})
    if not duty_anchors:
        print("  ⛔ NOT COMPUTED — wind_duty_cycle.json is absent, so the cycle count has no source.")
        print("     ⛔ No fallback is substituted: a typed cycle count would be the very species of")
        print("     fabrication this whole block exists to avoid. Run `62_wind_duty_cycle.py` first.")
    else:
        n_worst = max(a["n_cycles"] for a in duty_anchors)
        print(f"  Duty: {len(duty_anchors)} anchors from script 62 (real NASA POWER wind, "
              f"{wind['n_days']} days), {min(a['n_cycles'] for a in duty_anchors):.2e}"
              f"–{n_worst:.2e} sway cycles over the service life.")
        print("  Wear-through = the branch's own wall thickness, because nothing else separates the "
              "anode from the cathode:")
        print(f"  {'branch':<24s} {'µ':>4s} {'R_wall':>8s} {'slip/cyc':>9s} {'sliding':>10s} "
              f"{'k_max lo':>10s} {'k_max hi':>10s}")
        print(f"  {'-' * 92}")
        for r in regimes:
            play, t_mm = r["radial_play_mm"], r["coating_or_liner_mm"]
            ei = r["ei_Nm2_bonded"]
            od_mm = D_BUS + 2.0 * t_mm
            for mu in MU_SWEEP:
                f_lat = mu * F_POGO_N
                onset = first_wall_contact_mm(f_lat, play, L_FREE_UNSUP, ei_Nm2=ei)
                # The wall only exists from the mouth inward; a computed onset before it means the rod
                # has already exceeded the play on arrival, i.e. it meets the bore EDGE (§4b).
                run_start = max(onset, CHANNEL_START_MM)
                if run_start >= channel_end:
                    wear_rows.append({"branch": r["branch"], "mu": mu, "contact": False,
                                      "why": "the rod never reaches the wall inside the bore at this "
                                             "µ — the free-cantilever case, so no rubbing is priced"})
                    print(f"  {r['branch']:<24s} {mu:>4.1f} {'—':>8s} {'—':>9s} {'—':>10s} "
                          f"{'no contact':>10s} {'':>10s}")
                    continue
                # ⛔ BRACKET, not a number: scan the single-prop family across the active run and keep
                #    its maximum. The distributed reaction the real contact carries lies inside this
                #    family; taking the max is the conservative end for a wear budget.
                stations = np.linspace(run_start, channel_end, 201)
                reactions = [prop_reaction_N(f_lat, float(a), play, L_FREE_UNSUP, ei) for a in stations]
                i_max = int(np.argmax(reactions))
                r_wall, a_star = float(reactions[i_max]), float(stations[i_max])
                if r_wall <= 0.0:
                    wear_rows.append({"branch": r["branch"], "mu": mu, "contact": False,
                                      "why": "the wall is touched but carries no reaction at this load "
                                             "— contact begins exactly where the play is taken up"})
                    print(f"  {r['branch']:<24s} {mu:>4.1f} {'0.00 N':>8s} {'—':>9s} {'—':>10s} "
                          f"{'no load':>10s} {'':>10s}")
                    continue
                slip_mm = surface_axial_slip_mm(f_lat, a_star, L_FREE_UNSUP, od_mm / 2.0, ei)
                # ⛔ The MATERIAL sets the smallest area the contact may have: PEEK cannot carry a line
                #    load, it flows until the pressure falls to what it supports. So A ≥ R/p_flow is
                #    DERIVED, not assumed — and it is what replaces the arbitrary contact patch this
                #    block would otherwise need. p_flow is BRACKETED (see the constant block); the
                #    TIGHTEST factor drives the headline, the loosest is reported beside it so the
                #    reader sees what the choice is worth. Ceiling: a flow-pressure bound, never a
                #    Hertz solution; no strain hardening, no viscoelastic recovery.
                area_by_factor = {f"{c:.1f}": r_wall / (c * SIGMA_YIELD_PEEK_PA) * 1e6
                                  for c in CONTACT_CONSTRAINT_FACTORS}
                a_min_mm2 = min(area_by_factor.values())
                # The opposite end: the pair worn in until it bears over the whole run, priced in the
                # PROJECTED-AREA convention that polymer plain-bearing wear rates are quoted against.
                a_proj_mm2 = od_mm * (channel_end - run_start)
                # 🔑 THE REACTION CANCELS AT THE TIGHT END, and that was not the plan — it is what the
                #    algebra turned out to say. A = R/p_flow and duty = R·s, so k = h·A/duty reduces to
                #    h/(p_flow·s): the flow-limited budget does not contain the contact force AT ALL.
                #    Consequence worth more than the number: the weakest link in this chain — a
                #    propped-cantilever reaction standing in for a distributed contact — has NO say in
                #    the binding half of the answer. It survives only in the loose (worn-in) end.
                #    Pinned against the closed form rather than described, so a refactor cannot quietly
                #    reintroduce the dependence. ⚠️ Checked on the UNROUNDED distance: the first version
                #    read the rounded field back out of the payload and failed on its own 4e-6 of
                #    rounding — a pin that judges a display value is judging the formatter.
                p_flow_N_mm2 = max(CONTACT_CONSTRAINT_FACTORS) * SIGMA_YIELD_PEEK_PA / 1e6
                per_anchor = []
                for anc in duty_anchors:
                    sliding_m = anc["n_cycles"] * 2.0 * slip_mm * MM_M
                    duty_nm = r_wall * sliding_m
                    k_edge = t_mm * a_min_mm2 / duty_nm
                    k_closed = t_mm / (p_flow_N_mm2 * sliding_m)
                    assert abs(k_edge - k_closed) <= 1e-9 * k_closed, \
                        "the flow-limited budget stopped reducing to h/(p_flow·s) — the reaction crept back in"
                    per_anchor.append({
                        "anchor": anc["anchor"], "n_cycles": anc["n_cycles"],
                        "sliding_distance_m": round(sliding_m, 1),
                        "duty_N_m": round(duty_nm, 1),
                        "k_max_edge_mm3_per_Nm": t_mm * a_min_mm2 / duty_nm,
                        "k_max_conformal_mm3_per_Nm": t_mm * a_proj_mm2 / duty_nm,
                    })
                worst = min(per_anchor, key=lambda p: p["k_max_edge_mm3_per_Nm"])
                # 🔑 Bounds with a KNOWN sign are asserted IN THE CODE, not trusted to the author: the
                #    bracket must be a bracket (the flow-limited patch cannot exceed the full projected
                #    bearing), every budget must be positive, and the slip must stay a small fraction
                #    of the span or the small-deflection beam this whole file rests on is the wrong
                #    model. A quantity whose limit is known and unchecked is the one class of error
                #    that is free to catch (00_06 §0).
                assert 0.0 < a_min_mm2 <= a_proj_mm2, "the area bracket inverted — bound above the full run"
                assert all(p["k_max_edge_mm3_per_Nm"] > 0.0 for p in per_anchor), "non-positive budget"
                assert slip_mm < 0.01 * L_FREE_UNSUP, "slip is no longer small against the span"
                wear_rows.append({
                    "branch": r["branch"], "mu": mu, "contact": True,
                    "wall_allowance_mm": t_mm, "rubbing_od_mm": round(od_mm, 3),
                    "contact_run_mm": [round(run_start, 2), round(channel_end, 2)],
                    "edge_bearing": bool(onset < CHANNEL_START_MM),
                    "reaction_max_N": round(r_wall, 3), "reaction_station_mm": round(a_star, 2),
                    "slip_per_cycle_um": round(slip_mm * 1000.0, 3),
                    "area_material_bound_mm2": round(a_min_mm2, 5),
                    "area_by_constraint_factor_mm2": {k: round(v, 5) for k, v in area_by_factor.items()},
                    "area_projected_full_run_mm2": round(a_proj_mm2, 3),
                    "by_duty_anchor": per_anchor,
                    "k_max_span_ratio": round(a_proj_mm2 / a_min_mm2, 1),
                })
                print(f"  {r['branch']:<24s} {mu:>4.1f} {r_wall:>6.2f} N {slip_mm * 1000:>7.1f} µm "
                      f"{worst['sliding_distance_m']:>8.0f} m {worst['k_max_edge_mm3_per_Nm']:>10.2e} "
                      f"{worst['k_max_conformal_mm3_per_Nm']:>10.2e}")
        # The SECOND driver, priced so that «the sway dominates» is a measurement and not an assumption.
        # ⛔ Its cycle count is a SWEEP, never a value: the seasonal swing is one per year by definition,
        #    the diurnal count is not in this tree at all, and the point is that even the generous end
        #    stays orders below the sway term.
        for per_year in (1, 365):
            for dt_k in (40, 80):
                growth_mm = d_alpha * LINER_LENGTH_MM * dt_k
                sliding_m = 20.0 * per_year * 2.0 * growth_mm * MM_M
                thermal_rows.append({"cycles_per_year": per_year, "delta_T_K": dt_k,
                                     "stroke_um": round(growth_mm * 1000.0, 1),
                                     "sliding_distance_m": round(sliding_m, 4)})
        sway_max = max((p["sliding_distance_m"] for w in wear_rows if w["contact"]
                        for p in w["by_duty_anchor"]), default=0.0)
        thermal_max = max(t["sliding_distance_m"] for t in thermal_rows)
        print(f"\n  → Second driver, the liner's differential thermal travel: at most "
              f"{thermal_max:.3f} m of sliding over the service life")
        print(f"    against {sway_max:.0f} m from sway — "
              f"{sway_max / thermal_max:.0e}× smaller, so the sway drag is the whole wear axis "
              f"(DERIVED, not assumed).")
        contact_rows = [w for w in wear_rows if w["contact"]]
        if contact_rows:
            shipped_rows = [w for w in contact_rows if w["branch"].startswith("PEEK liner")]
            binding_wear = min(shipped_rows or contact_rows,
                               key=lambda w: min(p["k_max_edge_mm3_per_Nm"] for p in w["by_duty_anchor"]))
            b_worst = min(binding_wear["by_duty_anchor"], key=lambda p: p["k_max_edge_mm3_per_Nm"])
            print(f"\n  → BUDGET for the shipped branch at its worst corner (µ {binding_wear['mu']:.1f}, "
                  f"{b_worst['anchor']}):")
            print(f"    the pair may wear at k ≤ {b_worst['k_max_edge_mm3_per_Nm']:.2e} mm³/(N·m) if the "
                  f"contact stays the MATERIAL-bounded patch")
            print(f"    ({binding_wear['area_material_bound_mm2']:.4f} mm² — PEEK at the TIGHTEST "
                  f"swept flow pressure; the loosest gives "
                  f"{max(binding_wear['area_by_constraint_factor_mm2'].values()):.4f} mm²),")
            print(f"    and at k ≤ {b_worst['k_max_conformal_mm3_per_Nm']:.2e} once it is worn in over "
                  f"the run.")
            print(f"  🔴 The two ends differ by {binding_wear['k_max_span_ratio']:.0f}×, and NOTHING in "
                  f"the tribology decides between them —")
            print("     the CONTACT GEOMETRY does, and that is an OPEN ⚖️ (the bore entry carries a")
            print("     radius whose value is unnamed; the liner's protrusion decides whether first")
            print("     contact lands on titanium edge or on polymer). So the wear verdict is gated on")
            print("     a decision of OURS, not on a number from a vendor. ⛔ k itself stays NOT MEASURED.")
            print("  🔑 And the TIGHT end does not contain the contact force at all: with the area")
            print("     flow-limited, k = wall / (flow pressure × sliding distance) — the reaction")
            print("     cancels. The shakiest input of the chain (a single prop standing in for a")
            print("     distributed contact) therefore has no say in the binding half of the answer.")

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
    # 🔴 The `clears_all` branch used to end "the liner's remaining ground is insulation alone", and
    # that CONTRADICTED the ratified verdict: ⚖️ 2026-09-11 already retired the fatigue ground and
    # replaced it with WEAR. The line was written before that verdict and survived it.
    print("     Dropping the as-printed derate lifted the soft alloys OUT of predicted failure; whether"
          if not clears_all else "     Every alloy clears it bare, so the FATIGUE motive for support is "
                                 "spent — which is NOT news:")
    # ⛔ This branch read «The ratified ground is WEAR, and NOTHING here computes it» until §7 existed.
    #    True when written, false the moment the wear block shipped — and nothing but reading the file's
    #    own output as a stranger would have caught it: both halves are grammatical and each was once
    #    correct. The pointer is DERIVED from whether the block actually ran, never from this sentence.
    print("     it also carried them over the infinite-life line is what the two lists above answer."
          if not clears_all else
          "     ⚖️ 2026-09-11 retired that ground already. The ratified ground is WEAR — "
          + ("BOUNDED in §7." if binding_wear is not None else "NOT computed in this run (§7)."))
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
    # ⛔ DERIVED from §6, never typed. The point is not the width but WHERE the nominals sit: the
    # verdict every other section leans on («tight on the wire») is not produced by the drawing.
    _iw = interference_window
    print(f"  6. THE FIT (§6) — the interference the direction verdict asserts is now BOUNDED: "
          f"{_iw['floor']['radial_um']:.2f}…{_iw['ceiling']['radial_um']:.2f} µm radial,")
    print(f"     i.e. {_iw['window_diametral_um']:.1f} µm diametral for BOTH parts together. "
          f"⛔ But the specified nominals are")
    print(f"     {'NOT SPECIFIED AT ALL' if _iw['bore_nominal_is_assumed'] else 'specified'}"
          f", so «tight on the wire» is whatever the vendor centres on, not a drawing —")
    print(f"     the nominal must move {_iw['required_nominal_offset_diametral_um']:.1f} µm "
          f"diametrally to land in the window (a ⚖️, not a tolerance).")
    print(f"     Friction locks the tube axially over the whole window except its floor "
          f"(locked_over_whole_window={_iw['axial_friction_lock']['locked_over_whole_window']}), so")
    print("     the ratified ground for ONE-end capture does not discriminate above ~1 µm of fit.")
    # ⛔ DERIVED from §7, never typed. The sentence this replaces was the file's own «NOTHING here
    # computes it» — true when written, and the reason this block exists.
    if binding_wear is not None:
        _bw = min(binding_wear["by_duty_anchor"], key=lambda p: p["k_max_edge_mm3_per_Nm"])
        print(f"  7. WEAR (§7) — the ratified ground is no longer unpriced. The shipped liner at its "
              f"worst corner (µ {binding_wear['mu']:.1f})")
        print(f"     may wear at k ≤ {_bw['k_max_edge_mm3_per_Nm']:.2e} mm³/(N·m) on the material-bounded "
              f"patch, k ≤ {_bw['k_max_conformal_mm3_per_Nm']:.2e} worn in —")
        print(f"     a {binding_wear['k_max_span_ratio']:.0f}× span decided by CONTACT GEOMETRY, which is "
              f"our own open ⚖️, not the vendor's number.")
        print("     ⛔ k stays NOT MEASURED; what changed is that a tribo-test now returns a verdict.")
    else:
        print("  7. WEAR (§7): NOT COMPUTED — the duty cache is absent and no cycle count is "
              "substituted (run script 62).")
    print("  8. Caveat: the cyclic-load amplitude (pogo friction + PEEK flex) is an ESTIMATE — the real")
    print("     sway spectrum is bench/field (00_02). Comparative supported-vs-unsupported is robust.")

    # ⛔ Built as ONE expression, never as a literal glued onto the verdict: adjacent string literals
    #    concatenate BEFORE a trailing conditional binds, so writing this inline would have emptied the
    #    whole verdict on the branch where the duty cache is missing — a defect visible only in the
    #    absent-cache run, i.e. exactly the one nobody executes.
    wear_verdict_sentence = (
        "WEAR is BOUNDED since 2026-09-12 (wear_budget): the rate is not measured anywhere, so the "
        "block prices the BUDGET, and its two ends are set by the CONTACT GEOMETRY - an open verdict "
        "of ours - not by tribology. The same block re-earns the rejection of the conformal branches "
        "on the wear axis itself, which is where the 2026-09-11 ground had been weakened."
        if binding_wear is not None else
        "WEAR is NOT priced in this run: the duty cache is absent and no cycle count is substituted."
    )

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
                        "aspect_note": "L/D of the bore as machined (depth = shank + flange, read from "
                                       "cem/cathode_flange.json). It decides which operation the vendor "
                                       "needs and is the ratio quoted in canon prose - derived here so it "
                                       "moves with the diameter instead of being retyped",
                        "note": "length read conservatively — the SHANK run only, not the flange disc above it; a shorter bore makes contact HARDER to reach, so the contact finding is not an artefact of "
                                "the span"},
            "branches": regimes,
            # 🔴 Read BEFORE any first_contact number: those bisect from the root over an assumed
            # full-length wall, and the first CHANNEL_START_MM has none (PEEK gap, Ø11 sleeve bore).
            # A contact shorter than the mouth therefore means EDGE bearing, not deep support.
            "edge_bearing": {"mouth_mm": CHANNEL_START_MM, "rows": edge_rows,
                             "liner_start": liner_start,
                             "note": "geometric condition only (free deflection at the mouth vs radial "
                                     "play); no notch factor and no contact model exists in this tree. "
                                     "Input to the OPEN axial-extent verdict (00_07 HW.34)"},
            "play_reduction": play_reduction,
            "axial_thermal": axial_thermal,
            "supported_span_check": supported_span_check,
            "gap_limited_branches": gap_limited,
            "free_cantilever_sf_describes_these": [r["branch"] for r in regimes
                                                   if r["regime"].startswith("free cantilever")],
        },
        "weld_seam": weld_seam,
        "interference_window": interference_window,
        "wear_budget": {
            "question": "00_07 HW.34 — ⚖️ 2026-09-11 made WEAR the ground the structural liner stands "
                        "on, and nothing in this tree computed it: every wear/fretting mention in this "
                        "file was prose, so 'rated for 20 years' had no instrument and FMEA #21 "
                        "asserted wear-through with none either. This block bounds the rate the pair "
                        "may have and still keep the wall, so a tribo-test returns a verdict",
            "specific_wear_rate_measured": SPECIFIC_WEAR_RATE_MEASURED,
            "contact_constraint_factors_swept": list(CONTACT_CONSTRAINT_FACTORS),
            "contact_area_bound": "A >= R / (constraint x PEEK yield). The constraint factor is SWEPT, "
                                  "never chosen: a confined contact flows at the indentation limit "
                                  "(~3x yield, the same factor that puts HARDNESS in Archard's law), "
                                  "so taking yield alone would over-state the allowable area threefold "
                                  "in the direction that makes the part look safe. Headlines use the "
                                  "TIGHTEST factor",
            "interface": "liner OD (PEEK) against the cathode bore (Ti). Set by the 2026-09-11 "
                         "DIRECTION verdict: the tube is tight on the wire, so the play - and "
                         "therefore the rubbing - sits on the CHANNEL side",
            "second_interface_not_priced": "at the FLOOR of the interference window §6 shows the tube "
                                           "slips on the WIRE instead, which puts a second sliding "
                                           "pair inside the same part. Nothing specifies which of the "
                                           "two ships, and this block prices only the ratified one",
            "duty_source": str(WIND_CACHE.relative_to(REPO_ROOT)) if wind else None,
            "duty_anchors": duty_anchors,
            "duty_note": "cycle counts are LOADED from script 62 (ten years of real NASA POWER wind "
                         "for Cherkasy), never retyped. Script 62's own verdict is that the duty does "
                         "NOT close to a single number - two named literature gaps - so the anchors "
                         "are a bracket and the raw 20 yr x 1 Hz budget is its ceiling",
            "rows": wear_rows,
            "thermal_driver": {
                "rows": thermal_rows,
                "cycles_per_year_is_swept": True,
                "note": "the liner's differential axial travel against Ti, the only other sliding this "
                        "geometry produces. Its cycle count is SWEPT (seasonal = 1/yr by definition, "
                        "diurnal is nowhere in this tree) because the finding is the ORDER: even the "
                        "generous end stays orders below the sway term, so the sway drag is the wear "
                        "axis. DERIVED, not assumed",
            },
            "binding": binding_wear,
            "reaction_cancels_at_the_tight_end": "A = R/p_flow and duty = R x s, so k = h x A / duty "
                                                 "reduces EXACTLY to h / (p_flow x s). The flow-limited "
                                                 "budget therefore contains no contact force, and the "
                                                 "weakest input of the chain - a single prop standing in "
                                                 "for a distributed contact - has no say in the binding "
                                                 "half of the answer. It survives only in the worn-in "
                                                 "end, through the projected area. Pinned in-run against "
                                                 "the closed form, not merely described",
            "not_modelled": {
                "distributed_contact": "the wall reaction is the maximum of the single-prop family "
                                       "across the active run; no distributed-contact solution exists "
                                       "in this tree, so the true reaction is bracketed, not solved - "
                                       "and see reaction_cancels_at_the_tight_end for why that "
                                       "bracket does not reach the binding number",
                "slip_regime": "Archard assumes GROSS slip. The slip amplitudes here sit in the range "
                               "where a real pair may be in partial slip instead, which wears far "
                               "less and damages by fretting FATIGUE rather than by removal. The "
                               "regime boundary is not in this tree, so the gross-slip reading is "
                               "taken - the conservative one for a wear budget, and the wrong one for "
                               "predicting the failure MODE",
                "third_body": "PEEK debris trapped in a 25 um clearance is neither evacuated nor "
                              "modelled; it can either bed the contact in (less wear) or turn the "
                              "pair abrasive (much more)",
                "titanium_side": "only the polymer is priced. The bore also wears, and on the EDGE "
                                 "branch it is the sharp edge doing the cutting",
                "temperature_and_creep": "k, the PEEK yield that bounds the contact area, and the "
                                         "modulus are all 23 C datasheet values; none is swept over "
                                         "the -30..+40 C service band, and creep flattens the contact "
                                         "over 20 yr in a direction this bound does not follow",
                "amplitude_coupling": "slip and reaction both scale with the drag, so a real sway "
                                      "SPECTRUM (not a single amplitude) would redistribute the duty; "
                                      "the load spectrum is bench/field, 00_02",
            },
        },
        "assembly_clearance": {
            "question": "00_07 HW.34 — which of the three frozen dims (01_01 §1.4) gives up the "
                        "assembly clearance. CLOSED 2026-09-11: direction = channel side, size = "
                        "branch (в), channel 1.30 -> 1.35. The table stays because it is the PRICING "
                        "the verdict stands on, not an open menu; the shipped row is flagged",
            "frozen_dims_mm": {"rod": D_BUS, "channel": D_CHANNEL_MM, "liner_wall": LINER_WALL_MM,
                               "liner_length": LINER_LENGTH_MM, "liner_protrusion": LINER_PROTRUSION_MM},
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
                    "thermal -> leading HW.24 candidates win on both. " + wear_verdict_sentence),
        "caveats": "cyclic-load amplitude (pogo friction + PEEK flex) is an estimate; real sway spectrum "
                   "is bench/field (00_02). Comparative supported-vs-unsupported + per-alloy ranking robust. "
                   "WELD SEAM: its geometry is still NOT modelled (homogeneous cantilever), and the wrought "
                   "derate still describes the WIRE, not the JOINT. What IS modelled since 2026-09-12 is the "
                   "SENSITIVITY - the break-even knockdown k at which the seam crosses each line (see the "
                   "weld_seam block). k itself is NOT MEASURED and is not assumed here. "
                   "THE FIT: the liner-wire interference the direction verdict asserts is BOUNDED since "
                   "2026-09-12 (interference_window), and its two vendor bands stay NOT MEASURED. The "
                   "headline is not the width but the nominals: rod O1.0 against tube bore O1.00 is a "
                   "line-to-line fit, so the ratified 'tight on the wire' is a tolerance outcome, and "
                   "landing in the window needs a nominal interference - a verdict, not a tolerance. "
                   "Creep is modelled NOWHERE, so the real window is narrower on BOTH sides. "
                   "WEAR: the specific wear rate stays NOT MEASURED; what is computed is the BUDGET, and "
                   "its span is set by the contact AREA, which is bracketed between a flow-pressure bound "
                   "and the full projected run. Archard assumes GROSS slip - at these amplitudes a real "
                   "pair may be in partial slip, which removes less material and fails by fretting FATIGUE "
                   "instead, a mode nothing here models. Third-body debris, the titanium side of the pair "
                   "and the whole -30..+40 C dependence are outside the bound. "
                   "Three seam mechanisms "
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
