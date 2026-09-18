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
liner from FATIGUE, and that ground is RETIRED, not narrowed (⚖️ founder, 00_07 HW.34). Both L_FREE_*
columns are FREE cantilevers — no wall anywhere — while the real rod threads a Ø1.35 bore, so a branch
that leaves play can take it up and BEAR on the wall. WHERE it bears is an EQUILIBRIUM question, and §4
answers it with the contact solver of `lib.beam_contact` (the one script 68 shipped 2026-09-14), on the
insertion placeholder AND at both ends of the Zone-1 lock window: on a coaxial channel the touchdown
drag is far below every swept µ·F, the ONLY contact under drag is the exit plane (the pad plane, where
the tube ends flush), and against a RIGID wall the root stress is 3·E·c·g/L² whatever the drag — the
LOWER end of a bracket whose upper end is the Ti-bore stop behind the polymer wall (the free cantilever
where the drag cannot reach it), the contact compliance between them measured nowhere; a channel off the
root axis by more than the play makes the MOUTH a contact station and puts a STATIC bending on the root.
An unsupported SF is therefore a number for a configuration that does not exist, and the script says
so through DERIVED flags, never through prose. What the liner carries instead is WEAR: the exit contact
is forced on every swept µ, and a 10 µm conformal film asked to be a bearing in a THROUGH bore of
L/D ≈ 12.6 wears through to a ~0.5 V anode↔cathode short. The supported/unsupported columns stay because
they price the DIAMETER and the FABRICATION branch honestly — they are simply not the argument for the
liner, and the 6 mm «supported span» they use is an idealisation §4c measures against the equilibrium.

FABRICATION BRANCH — the second thing that moves every SF, and it is a VERDICT, not a parameter.
  ⚖️ 2026-09-10 (00_07 HW.34) ratified the rod as a WELDED cold-drawn wire, so the as-built knockdown
  `AS_PRINTED_DERATE` no longer applies to the shipped part. Both columns are printed side by side —
  `printed` (superseded) and `welded` (shipped) — because the fabrication choice is what moves the
  still-open LINING verdict, and a reader handed one column cannot see that it moved.
  ⛔ THE MODEL STILL HAS NO WELD-SEAM GEOMETRY. It is a homogeneous cantilever, while the ratified rod
  carries a heat-affected zone at the ROOT — and the root IS the peak-moment section in every drag and
  offset configuration the equilibrium computes (DERIVED per solve, `lib.beam_contact` moment field; the
  one class where the peak leaves the root is a tilt about the mouth large enough to take up the play on
  both walls, script 68 §tilt). So the doubled SF describes the WIRE and says NOTHING about the JOINT,
  and quoting a welded-column SF as if it covered the weld is the error this note exists to prevent.
  ⊕ §5 does NOT price the joint. Its knockdown k is NOT MEASURED anywhere in this tree, and since
  2026-09-14 no break-even k is derived either: the root section sees two regimes (fully-reversed drag
  on a coaxial channel ⊥ a static MEAN from a channel offset with the drag as amplitude), the model has
  no mean-stress correction, and a k inverted from the coaxial cap alone would silently assume
  coaxiality. What §5 gives is the INPUT any seam acceptance needs — amplitude and mean at the root per
  regime and geometry — and keeps k visibly absent (`WELD_KNOCKDOWN_MEASURED = None`).
  ⚠️ Likewise absent from canon: as-printed `Sa` and the printed diameter tolerance — `DMLS Ti ±0.3`
  is an AXIAL Z-stack contribution, not a diametral one.

GEOMETRY AXIS — read before any number. The unsupported PEEK gap, which sets the mouth station and the
rod length, comes from `Z1_INSERTION_MM = 30`, an HW.8 PLACEHOLDER that lies OUTSIDE the Zone-1 lock's
own insertion window (00_07 HW.26 G1). Every equilibrium block below is computed at the placeholder AND
at both ends of the lock window (`GEOMETRIES`); the §1–§3 free-cantilever tables stay on the placeholder
and say so in the cache (`geometry_mm`).

Per-alloy endurance is keyed to yield (σ_e ≈ k·σ_y) from lib ALLOY_PROPERTIES — ties HW.34 ↔ HW.24.
No FEA — slender-beam closed form (Euler buckling + cantilever bending + S-N endurance ratio).
"""
from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib import beam_contact as bc
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

# ── Channel run (mm from the anode root) — the wall that the two branches above IGNORE ──
# Both L_FREE_* above are free-cantilever idealisations: they assume NO wall anywhere over the span.
# The real rod threads a Ø1.35 bore from the mouth (where the PEEK gap ends) to the EXIT on the pogo
# face — the full drilled depth, shank + flange disc — and the pad is the rod's own end face there, so
# the channel exit IS the rod's end (02_02 §1.2). ⚠️ A shorter, «conservative» run (the shank only) stood
# here while the contact question was «does the rod reach the wall at all»; under the equilibrium the
# question is WHERE the wall ends, because that is the station the drag is reacted at, and a run cut
# short would move it. The exit is therefore the drilled depth, read from the CEM.
CHANNEL_START_MM = PEEK_GAP_MM     # the PEEK gap ends and the bore begins (placeholder geometry)
# Full DRILLED depth of the bore (shank + flange disc) — the MACHINING referent, and what the L/D
# ratio is about — which operation the bore needs. ⛔ That ratio lived in prose (here and in SUMMARY)
# with no cache owner, so it could not be checked against the diameter it divides by. Derived now.
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
#    (channel run + protrusion) over the same two CEM fields. Nothing binds the two halves, and canon binds
#    only one field: `cem_canon_sync.rb` pins the liner WALL but has no row for `bus_liner_protrusion_mm`,
#    so the ratified >= 1.0 is held by this cache and 01_01 §1.4 prose, not by a gate.
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


# ── The geometry AXIS: the placeholder and both ends of the Zone-1 lock window ────────────────────
# ⛔ One home for the three geometries scripts 55 and 68 compute on; 68 imports these (it imports this
#    module), so the two cannot drift apart on the mouth or the exit. The lock window is the formula of
#    `MechanicalLock.InsertionWindowMm` in tools/cad — a by-value crossing, pinned there by
#    `MechanicalLockTests`, and nothing binds this line to it.
@dataclass(frozen=True)
class Geometry:
    label: str
    insertion_mm: float
    gap_mm: float        # unsupported PEEK gap = the channel mouth, mm from the root
    pad_mm: float        # pad plane = rod length = channel exit
    liner_from_mm: float # the composite member starts here (the ratified protrusion into the gap)

    @classmethod
    def at_insertion(cls, label: str, insertion_mm: float) -> Geometry:
        gap = SLEEVE_LEN_MM - insertion_mm - SHANK_LEN_MM
        return cls(label, insertion_mm, gap, gap + BORE_DEPTH_MM, gap - LINER_PROTRUSION_MM)

    def channel(self) -> bc.Channel:
        return bc.Channel(self.gap_mm, self.pad_mm, self.liner_from_mm)


def lock_insertion_window_mm() -> tuple[float, float]:
    """Zone-1 lock insertion window from the lock manifest: end of the PEEK contact zone -> near flank of
    the DIN-471 groove."""
    lock = cem("mechanical_lock.zone1")
    return (float(lock["contact_start_mm"]) + float(lock["contact_length_mm"]), float(lock["groove_offset_mm"]))


def geometries() -> list[Geometry]:
    lo, hi = lock_insertion_window_mm()
    return [Geometry.at_insertion("script 55 placeholder (HW.8)", Z1_INSERTION_MM),
            Geometry.at_insertion("lock window, near end", hi),
            Geometry.at_insertion("lock window, far end", lo)]


GEOMETRIES = geometries()
PLACEHOLDER_GEOMETRY = GEOMETRIES[0]
assert abs(PLACEHOLDER_GEOMETRY.pad_mm - L_FREE_UNSUP) < 1e-9 and abs(PLACEHOLDER_GEOMETRY.gap_mm - L_FREE_SUP) < 1e-9, \
    "the free-cantilever spans and the placeholder geometry disagree"
# The channel-offset sweeps (µm), shared with script 68 so that 55's seam inputs and 68's offset table are
# the same points of the same model. SWEPT, never measured: which offset the stack delivers is computed
# nowhere in the tree (00_07 HW.34 ⚖️ coaxiality).
OFFSETS_UM = (0, 10, 15, 20, 25, 30, 40, 50, 75, 100)
REVERSING_DRAG_OFFSETS_UM = (0, 10, 25, 50, 100)

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
# fatigue SF by ~14 % (σ ∝ 1/d³) on Ta, the lowest-SF alloy — its SF lives in the cache, not here.
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
ENDURANCE_OVER_YIELD = 0.40   # ⚖️ founder 2026-09-17 RATIFIED the LOW end of the band, and the model
                              # RUNS there since 2026-09-18 — every SF below is a 0.40 number. What the
                              # move cost is visible in the data, not in this comment: at the midpoint
                              # the welded branch cleared SF 2 on all six alloys, at the ratified end it
                              # is five (Ta falls to 1.96 free-cantilever). Below: why the band existed.
                              # wrought-Ti fatigue ratio — a BAND 0.40-0.50, not a constant, and the
                              # band is written right here while only its MIDPOINT enters the model.
                              # ⚠️ Every SF scales LINEARLY with it: at 0.40 the binding link (Ta,
                              # welded, unsupported) reads 1.96, so the shipped verdict «all six clear
                              # SF 2» is a statement about the midpoint of an unmeasured band, not
                              # about the band. Found 2026-09-12 by a same-FORM sweep (a single point
                              # standing in for a coefficient); swept since — ENDURANCE_RATIO_SWEEP.
# ⛔ THE BAND ENTERS THE MODEL NOW, not just the comment above it. Until 2026-09-12 only the MIDPOINT
#    did, while every SF scales LINEARLY with this coefficient — so «all six clear SF 2» was a statement
#    about one point of an unmeasured band, dressed as a statement about the band. The ends are the ones
#    the comment has carried since the constant was written; ⛔ they are not measured for OUR alloys and
#    are not a distribution — a sweep, and its job is to say whether a verdict SURVIVES it (00_07 HW.34).
ENDURANCE_RATIO_SWEEP = (0.40, 0.45, 0.50)
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
# The ratified rod is a welded cold-drawn wire, so the joint sits at the ROOT — and the root is the
# peak-moment section in every drag and offset configuration the equilibrium computes (§4, derived
# per solve). The derates above describe the WIRE; the seam carries its own fatigue-strength reduction
# on top: weld-toe notch + HAZ microstructure + weld residual tension.
#
# ⛔ THAT FACTOR IS NOT IN THIS TREE AND IS NOT INVENTED HERE. There is no canon row, no vendor
#    answer and no measurement for it, so the sentinel below stays None. Typing a plausible
#    number would be the FALLBACK species of fabrication (00_01 §1.1): a branch of code that
#    exists while its measurer does not.
# ⛔ AND NO BREAK-EVEN k IS DERIVED EITHER (2026-09-14). The inversion SF_seam = k·SF_wire needs ONE
#    fully-reversed stress at the root, and the equilibrium gives the root two regimes instead: on a
#    coaxial channel the drag is fully reversed with an amplitude that is a BRACKET — rigid wall = its
#    LOWER end, Ti-bore stop = upper, mean 0; a channel off the root axis by more than the play puts a
#    STATIC bending on the same section (a MEAN, a rigid-wall UPPER bound) with the drag as amplitude on
#    top. This file has no mean-stress correction, so the offset regime cannot be priced, and a k inverted
#    from the rigid-wall end of the coaxial bracket alone would silently assume both a coaxiality the stack
#    does not carry anywhere and a rigid wall the part does not have. §5 therefore gives the INPUTS a seam
#    acceptance needs (amplitude and mean per regime and geometry, with their signs) and keeps k absent.
WELD_KNOCKDOWN_MEASURED = None   # k = σ_e(seam)/σ_e(wire) ∈ (0,1] — NOT MEASURED (00_06 §0)
# Two reference markers, and BOTH are OURS — neither is a weld figure borrowed from anywhere,
# so neither claims authority it does not have (in-silico skill #9, the mirror half):
#   k = AS_PRINTED_DERATE — "the joint is as bad as an as-built SLM surface". At that k the
#       welded branch collapses onto `printed` AT THE SEAM, i.e. the metallurgical argument for
#       welding buys nothing where the part actually breaks.
#   k = WROUGHT_DERATE    — "the joint is as good as the drawn wire", i.e. the model as it stood
#       before this block existed.
# They are kept as the scale a vendor's k will be read against; nothing here is compared with them.
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
# ⚖️ The two paragraphs above are the PRE-VERDICT state. RATIFIED founder 2026-09-18 (00_07 HW.34): the tube bore
#    nominal = wire Ø − 11.41 µm — the window centre this block printed at bore = rod Ø — with the WALL kept at
#    the ratified 0.15 (OD_nom = ID_nom + 2×0.15) and the tube fitted HOT (01_01 §3 step 4a; a cold slide at this
#    interference would crush the tube). Typed as the ratified number, not re-derived at run time: the window
#    moves by a fraction of a µm with the bore it is computed at, and a spec that followed it would move on every
#    re-run. `nominal_vs_window_centre_diametral_um` in the cache reports how far the two sit apart.
LINER_BORE_SPECIFIED_MM = D_BUS - 11.41e-3
LINER_BORE_ASSUMED_MM = D_BUS      # the pre-verdict reading; kept as the reference the ratified offset is quoted from
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


def branch_member(row: dict) -> tuple[float, float]:
    """(radial play mm, EI N·m²) of an insulation branch, re-derived from its DEFINITION.

    ⛔ The clearance-regime rows ROUND both for the cache, and downstream blocks used to compute FROM
    those rounded fields (the bonded EI came back rounded to four decimals, +0.6 %). Computation takes
    the member from here; the rounded row fields are display only.
    """
    t_mm = row["coating_or_liner_mm"]
    play = (D_CHANNEL_MM - (D_BUS + 2.0 * t_mm)) / 2.0
    ei = flexural_rigidity_Nm2(D_BUS, t_mm) if row["play_side"] == "channel" else flexural_rigidity_Nm2(D_BUS)
    return play, ei


def member_ei_at(geo: Geometry, row: dict, bonded: bool):
    """EI along the rod for an insulation branch: the bare Ti rod everywhere, or — channel-side branch,
    tube tight on the wire — the rod-plus-tube composite from the liner's lower end onward."""
    ei_bare = flexural_rigidity_Nm2(D_BUS)
    ei_bond = flexural_rigidity_Nm2(D_BUS, row["coating_or_liner_mm"]) if (row["play_side"] == "channel" and bonded) else ei_bare

    def ei_at(x_mm: float) -> float:
        return ei_bond if x_mm >= geo.liner_from_mm else ei_bare
    return ei_at


def root_sigma_MPa(clamp_moment_Nm: float) -> float:
    """Root fibre stress of the Ti rod from a clamp moment — the TUBE carries none of it in this reading."""
    return abs(clamp_moment_Nm) * (D_BUS / 2.0) * MM_M / second_moment_m4(D_BUS) / 1e6


def endurance_MPa(yield_MPa: float, derate: float = AS_PRINTED_DERATE,
                  ratio: float | None = None) -> float:
    """σ_e ≈ fatigue-ratio × yield, knocked down only if the rod is AS-PRINTED.

    `derate` is the fabrication branch, not a tuning knob: 0.5 for an SLM as-built surface,
    1.0 for cold-drawn wire. ⛔ It describes the WIRE and says nothing about the WELD — the
    seam has its own knockdown, and §5 says why no bound on it is derived here either.

    `ratio` overrides the fatigue ratio and exists for ONE caller: the band sweep. It defaults to
    the module constant, so every pre-existing call keeps its exact value — the sweep is added
    beside the model, never folded into it.
    """
    return (ENDURANCE_OVER_YIELD if ratio is None else ratio) * derate * yield_MPa


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
    banner("HW.34 — Bus rod mechanical check (buckling + sway fatigue + contact equilibrium)")
    print(f"  Rod Ø{D_BUS:.1f} mm; PLACEHOLDER geometry (Z1 insertion {Z1_INSERTION_MM:.0f} mm, HW.8): free length "
          f"unsupported {L_FREE_UNSUP:.0f} mm (no liner) vs the {L_FREE_SUP:.0f} mm gap the §2 supported column idealises")
    print("  Contact blocks (§4–§7) run on every geometry: " + " · ".join(f"{g.label} (gap {g.gap_mm:.0f}, exit {g.pad_mm:.0f})" for g in GEOMETRIES))
    print(f"  Pogo {F_POGO_N:.1f} N axial; cyclic lateral drag = µ·F_pogo (µ={MU_CONTACT:.1f})")
    print(f"  σ_e ≈ {ENDURANCE_OVER_YIELD:.2f}·derate·σ_y — derate {AS_PRINTED_DERATE:.2f} printed "
          f"vs {WROUGHT_DERATE:.2f} welded (drawn wire); SHIPPED = {SHIPPED_BRANCH}. The seam's own "
          f"knockdown k is NOT MEASURED and no break-even k is derived (§5)")

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

    # ── 4. Where the rod meets the wall — the EQUILIBRIUM, not the free shape (00_07 HW.34) ────────
    # 🔴 Until 2026-09-14 this block read the contact station off the FREE tip-loaded cantilever at
    # FULL drag — the station where δ(x) first equals the play. That shape is not an equilibrium: under
    # a tip load the deflection grows monotonically from the root, so as the drag ramps up the first
    # station to reach a uniform wall is the FARTHEST one inside the channel — the exit — and from then
    # on the drag is reacted there. Script 68 solved the contact (2026-09-14), and every block that stood
    # on the free-shape reading (edge bearing at the mouth · the first-contact range under the protrusion
    # · the span optimism and through it the seam bound · the wear station) is re-derived here on the
    # same solver (`lib.beam_contact`, one home), on the placeholder AND at both ends of the lock window.
    # ⛔ What the coaxial solve can say: WHETHER a branch touches down (µ·F against the touchdown drag),
    #    WHERE (the exit, asserted), the rigid-wall root stress — the LOWER end of a bracket (below) — and
    #    the wall reaction. What it cannot: anything about a channel off the root axis — that is §4b.
    banner("Clearance regime — where does the rod meet the wall? (equilibrium, both geometries)")
    print(f"  Channel Ø{D_CHANNEL_MM:.2f}, drilled depth {BORE_DEPTH_MM:.0f} mm (shank + flange; the exit is the pogo face, "
          f"where the tube ends flush). Rigid frictionless wall, perfect clamp — each figure carries its sign (the rigid-wall root is the LOWER end).")
    print(f"  {'geometry':<28s} {'branch':<22s} {'play':>7s} {'F_td':>8s} {'σ_root [rigid…upper] @µ0.5':>28s} {'R_exit≤':>8s}   regime (quantifier explicit)")
    print(f"  {'-' * 118}")
    regimes = []
    _coax_solves: dict[tuple, dict] = {}   # raw solves, keyed (geometry, branch, µ, member) — §7 reads slopes UNROUNDED
    _rot_upper: dict[tuple, float] = {}    # in-contact rotation path per cycle at the upper end (mm), UNROUNDED, for §7
    ei_bare = flexural_rigidity_Nm2(D_BUS)
    for geo in GEOMETRIES:
        ch = geo.channel()
        for label, t_mm, play_side in INSULATION_OPTIONS:
            row = {"branch": label, "coating_or_liner_mm": t_mm, "play_side": play_side}
            play, ei_bond = branch_member(row)
            ei_at_bond = member_ei_at(geo, row, bonded=True)
            ei_at_bare = member_ei_at(geo, row, bonded=False)
            # Touchdown drag: the tip load at which the FREE deflection at the exit equals the play. Exact
            # for the composite member (EI steps at the liner start); the bare closed form is the control.
            f_td = bc.touchdown_drag_N(ch, ei_at_bond, play)
            f_td_bare = bc.touchdown_drag_N(ch, ei_at_bare, play)
            f_td_closed = 3.0 * ei_bare * play * MM_M / (geo.pad_mm * MM_M) ** 3
            assert abs(f_td_bare - f_td_closed) <= 0.005 * f_td_closed, "bare touchdown drag ≠ 3·EI·g/L³"
            cap_closed = 3.0 * E_TI * (D_BUS / 2.0) * MM_M * play * MM_M / (geo.pad_mm * MM_M) ** 2 / 1e6
            by_mu = {}
            for mu in MU_SWEEP:
                f_lat = mu * F_POGO_N
                res = bc.solve(ch, ei_at_bond, play, drag_N=f_lat)
                bare = bc.solve(ch, ei_at_bare, play, drag_N=f_lat)
                _coax_solves[(geo.label, label, mu, "bonded")], _coax_solves[(geo.label, label, mu, "bare")] = res, bare
                stations = [z["station_mm"] for z in res["contacts"]]
                touched = f_lat > f_td
                # CONTROLS that can fail: the only contact is the exit (catches a wrong exit station, rod
                # length or play); the bare cap equals 3·E·c·g/L² once touched down (an independent formula);
                # the mouth is never reached coaxially; the peak moment sits at the root (moment field).
                if touched:
                    assert stations == [round(geo.pad_mm, 2)], f"{geo.label}/{label}/µ{mu}: coaxial contact is not the exit"
                    if f_lat > 1.001 * f_td_bare:
                        assert abs(root_sigma_MPa(bare["clamp_moment_Nm"]) - cap_closed) <= 0.005 * cap_closed, "coaxial cap ≠ closed form"
                else:
                    assert not stations, f"{geo.label}/{label}/µ{mu}: contact below the touchdown drag"
                assert abs(bc.deflection_mm(res, geo.gap_mm)) < play, f"{geo.label}/{label}/µ{mu}: the mouth was reached coaxially"
                assert res["peak_moment_station_mm"] == 0.0, f"{geo.label}/{label}/µ{mu}: peak moment left the root"
                r_exit = -res["contacts"][0]["force_N"] if stations else 0.0
                if touched:
                    assert abs(r_exit - (f_lat - f_td)) <= 2e-4, "exit reaction ≠ drag − touchdown drag"
                # 🔴 THE RIGID-WALL ROOT STRESS IS THE LOWER END OF A BRACKET, NOT A CAP. A rigid wall prescribes
                #    the exit deflection at g; the real wall is the PEEK wall of the tube (or the film) on the Ti
                #    bore's exit edge, so the exit yields by R/k and the root moment grows by 3EI·(R/k)/L² — where
                #    in the bracket the root sits is set by the CONTACT COMPLIANCE, measured nowhere. The UPPER end
                #    needs no compliance model: the rod cannot pass the Ti bore behind the polymer, so its exit
                #    travel is at most the play plus the polymer's own wall — the same solve with the wall moved
                #    out by that wall (the free cantilever F·L when the drag cannot reach the Ti bore).
                upper = bc.solve(ch, ei_at_bond, play + t_mm, drag_N=f_lat)
                sig_upper = root_sigma_MPa(upper["clamp_moment_Nm"])
                sig_free = bending_stress_MPa(f_lat, geo.pad_mm)
                assert sig_upper <= sig_free * 1.0001, "the Ti-bore stop cannot exceed the free cantilever"
                assert sig_upper >= root_sigma_MPa(res["clamp_moment_Nm"]) - 1e-9, "the upper end fell below the rigid-wall end"
                if geo is PLACEHOLDER_GEOMETRY:
                    # CONTROL, two owners of one quantity: the free-cantilever end IS §3's unsupported column at this µ.
                    _mu_row = next(m for m in mu_rows if m["mu"] == mu)
                    assert abs(sig_free - _mu_row["sigma_unsup_MPa"]) <= 0.05, "free-cantilever end ≠ §3 sigma_unsup"
                rot_upper = 4.0 * ((D_BUS + 2.0 * t_mm) / 2.0) * (bc.slope_rad(upper, geo.pad_mm) - bc.slope_rad(res, geo.pad_mm))
                _rot_upper[(geo.label, label, mu)] = rot_upper
                by_mu[str(mu)] = {"touches_down": bool(touched),
                                  "contact_station_mm": stations[0] if stations else None,
                                  "sigma_root_MPa_bonded": round(root_sigma_MPa(res["clamp_moment_Nm"]), 2),
                                  "sigma_root_MPa_bare": round(root_sigma_MPa(bare["clamp_moment_Nm"]), 2),
                                  "sigma_root_MPa_upper_end": round(sig_upper, 2),
                                  "upper_end_is": ("Ti-bore stop — the polymer wall fully yielded, rod against the bare bore"
                                                   if upper["contacts"] else "free cantilever — the drag cannot reach the Ti bore"),
                                  "sigma_root_MPa_free_cantilever": round(sig_free, 2),
                                  "exit_reaction_N_upper_rigid_wall": round(r_exit, 4),
                                  "deflection_at_mouth_um": round(bc.deflection_mm(res, geo.gap_mm) * 1e3, 2),
                                  "slope_at_exit_mrad_rigid_wall": round(bc.slope_rad(res, geo.pad_mm) * 1e3, 4),
                                  "in_contact_rotation_path_per_cycle_um_upper": round(rot_upper * 1e3, 3)}
            touch_mus = [mu for mu in MU_SWEEP if by_mu[str(mu)]["touches_down"]]
            # ⛔ The QUANTIFIER is explicit — ALL, SOME or NONE — because an else-branch once read «not on
            #    every µ» as «never» (2026-09-14) and a verdict inherited it.
            regime = ("touches down at the EXIT on every swept µ" if len(touch_mus) == len(MU_SWEEP)
                      else f"touches down at the EXIT on µ {', '.join(str(m) for m in touch_mus)} only; free cantilever on the rest"
                      if touch_mus else "free cantilever on every swept µ (never reaches the wall)")
            regimes.append({"geometry": geo.label, "branch": label, "coating_or_liner_mm": t_mm, "play_side": play_side,
                            "radial_play_mm": round(play, 4),
                            "ei_Nm2_bare_rod": round(ei_bare, 4), "ei_Nm2_bonded": round(ei_bond, 4),
                            "touchdown_drag_N_bonded": round(f_td, 5), "touchdown_drag_N_bare_closed_form": round(f_td_closed, 5),
                            "coaxial_cap_sigma_MPa_bare_closed_form": round(cap_closed, 2),
                            "coaxial_root_bound": "LOWER end — rigid wall. A compliant polymer wall lets the exit yield by R/k and "
                                                  "raises the root moment by 3EI·(R/k)/L²; the UPPER end is the Ti-bore stop "
                                                  "(the polymer wall fully yielded) or the free cantilever F·L where the drag "
                                                  "cannot reach it — sigma_root_MPa_upper_end per µ. Where the root sits in "
                                                  "[lower, upper] is set by the contact compliance, MEASURED NOWHERE",
                            "by_mu": by_mu, "touches_down_on_mus": touch_mus,
                            "touches_down_on_every_mu": len(touch_mus) == len(MU_SWEEP),
                            "contact_station_when_touched_down_mm": round(geo.pad_mm, 2),
                            "mouth_reached_on_any_mu": False,
                            "regime": regime})
            _w = by_mu[str(max(MU_SWEEP))]
            print(f"  {geo.label:<28s} {label:<22s} {play * 1e3:>5.0f} µm {f_td:>7.4f} N {_w['sigma_root_MPa_bonded']:>6.2f}…{_w['sigma_root_MPa_upper_end']:<6.1f} MPa "
                  f"{_w['exit_reaction_N_upper_rigid_wall']:>8.4f} N   {regime}")
    # Cross-geometry, cross-µ facts the verdict is built from — DERIVED, never typed.
    shipped_regimes = [r for r in regimes if r["play_side"] == "channel"]
    shipped_forced_everywhere = all(r["touches_down_on_every_mu"] for r in shipped_regimes)
    by_geometry = []
    for geo in GEOMETRIES:
        rows = [r for r in regimes if r["geometry"] == geo.label]
        by_geometry.append({"geometry": geo.label, "mouth_mm": geo.gap_mm, "exit_mm": geo.pad_mm,
                            "forced_on_every_mu_branches": [r["branch"] for r in rows if r["touches_down_on_every_mu"]],
                            "partly_branches": [r["branch"] for r in rows if r["touches_down_on_mus"] and not r["touches_down_on_every_mu"]],
                            "free_on_every_mu_branches": [r["branch"] for r in rows if not r["touches_down_on_mus"]]})
    print(f"\n  → Shipped liner: exit contact forced on every swept µ on every geometry: {shipped_forced_everywhere} (DERIVED).")
    for g in by_geometry:
        print(f"    {g['geometry']:<28s} forced: {', '.join(g['forced_on_every_mu_branches']) or 'none'} · "
              f"partly: {', '.join(g['partly_branches']) or 'none'} · free: {', '.join(g['free_on_every_mu_branches']) or 'none'}")
    print("  → Coaxially the mouth is never reached (deflection there is a fraction of the play on every row, asserted).")
    print("    Against a RIGID wall the root stress is 3·E·c·g/L² once touched down and does not grow with µ — and that")
    print("    is the LOWER end of a bracket: the real wall is the polymer on the Ti bore's edge, it yields by R/k, and the")
    print("    root lies between the rigid figure and the Ti-bore stop / free cantilever (per µ above). The contact")
    print("    compliance that places it is measured nowhere.")

    # The canon sentence this table feeds (01_01 §1.4) used to quote a "hundredfold" reduction. DERIVE it
    # — the factor is a ratio of two rows here and moves whenever either does.
    rod_side = [r for r in regimes if r["play_side"] == "rod" and r["geometry"] == PLACEHOLDER_GEOMETRY.label]
    chan_side = [r for r in regimes if r["play_side"] == "channel" and r["geometry"] == PLACEHOLDER_GEOMETRY.label]
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


    # ── 4b. The MOUTH as a contact station — a channel OFF the root axis (00_07 HW.34) ────────────
    # 🔴 Until 2026-09-14 this block asked whether the FREE deflection at the mouth exceeds the play and
    # called that «edge bearing»; the equilibrium says the mouth is never reached on a coaxial channel
    # (§4, asserted). The mouth IS a contact station when the channel axis sits off the root axis by
    # more than the play — a tolerance-stack quantity that the flange and sleeve CEMs declare
    # separately and nothing chains to the root (00_07 HW.34 ⚖️ coaxiality). Priced at ONE reference
    # excess past the play — SWEPT, not measured — with the per-µm secants beside it, because the
    # quantities that matter to the ratified verdicts (which FEATURE of the tube the edge meets; how
    # flat the approach is against a lead-in chamfer) are set by the OFFSET, not by µ.
    banner("Edge bearing — the mouth as a contact station under a channel offset (swept, never measured)")
    excess_um = 5.0
    edge_rows = []
    for geo in GEOMETRIES:
        ch = geo.channel()
        a_m = geo.gap_mm * MM_M
        for label, t_mm, play_side in INSULATION_OPTIONS:
            row = {"branch": label, "coating_or_liner_mm": t_mm, "play_side": play_side}
            play, _ = branch_member(row)
            ei_at_bond = member_ei_at(geo, row, bonded=True)
            res = bc.solve(ch, ei_at_bond, play, offset_mm=play + excess_um * 1e-3)
            stations = [z["station_mm"] for z in res["contacts"]]
            assert stations == [round(geo.gap_mm, 2)], f"{geo.label}/{label}: past the play the mouth is not the only contact"
            assert res["peak_moment_station_mm"] == 0.0, f"{geo.label}/{label}: peak moment left the root under offset"
            theta = bc.slope_rad(res, geo.gap_mm)
            p_mouth = res["contacts"][0]["force_N"]
            # CONTROLS with an independent formula, on the bare lever (the composite starts at the liner's
            # lower end, so on the placeholder 1 of the 6 mm is composite — hence 2 %, not 0.5 %):
            # a cantilever of length a deflected by δ at its tip has tip slope 3δ/(2a) and needs 3·EI·δ/a³.
            theta_closed = 3.0 * excess_um * 1e-6 / (2.0 * a_m)
            p_closed = 3.0 * ei_bare * excess_um * 1e-6 / a_m ** 3
            assert abs(theta - theta_closed) <= 0.02 * theta_closed, "mouth approach angle ≠ 3δ/(2a)"
            assert abs(p_mouth - p_closed) <= 0.02 * p_closed, "mouth reaction ≠ 3·EI·δ/a³"
            coax = next(r for r in regimes if r["geometry"] == geo.label and r["branch"] == label)
            edge_rows.append({
                "geometry": geo.label, "branch": label, "radial_play_um": round(play * 1e3, 1),
                "mouth_mm": geo.gap_mm,
                "mouth_is_station_for_offset_beyond_um": round(play * 1e3, 1),
                "reference_excess_past_play_um": excess_um,
                "at_reference": {"offset_um": round((play + excess_um * 1e-3) * 1e3, 1),
                                 "contacts": res["contacts"],
                                 "mouth_reaction_N": round(p_mouth, 4),
                                 "approach_angle_deg": round(float(np.degrees(theta)), 4),
                                 "sigma_root_MPa": round(root_sigma_MPa(res["clamp_moment_Nm"]), 2)},
                "approach_angle_deg_per_um_past_play": round(float(np.degrees(3.0e-6 / (2.0 * a_m))), 5),
                "mouth_reaction_N_per_um_past_play": round(3.0 * ei_bare * 1e-6 / a_m ** 3, 4),
                "lead_in_chamfer_deg": [30.0, 45.0],
                "chamfer_over_approach_at_reference": round(30.0 / float(np.degrees(theta))),
                "coaxial_regime_reaches_mouth": coax["mouth_reached_on_any_mu"],
                "regime_note": "the mouth is a contact station ONLY off-axis; coaxially the drag contact is the exit (§4)",
            })
            print(f"  {geo.label:<28s} {label:<22s} play {play * 1e3:>5.0f} µm · mouth loaded beyond that offset; at +{excess_um:.0f} µm: "
                  f"P {p_mouth:.3f} N, approach {np.degrees(theta):.4f}° ({np.degrees(3.0e-6 / (2.0 * a_m)):.4f}°/µm), σ_root {root_sigma_MPa(res['clamp_moment_Nm']):.1f} MPa")
    _ship_edge = [r for r in edge_rows if r["branch"].startswith("PEEK liner")]
    print("  → A lead-in chamfer at 30–45° is hundreds of times steeper than the approach at any swept excess")
    print(f"    ({min(r['chamfer_over_approach_at_reference'] for r in _ship_edge)}× at the reference on the shipped branch), so the rod")
    print("    never lands on a chamfer face — it lands where the chamfer meets the cylinder; only a RADIUS removes the edge.")

    # The axial-⚖️ input, re-derived. ⛔ The «earliest computed contact 0.79 mm before the mouth» this key
    # carried was the station where the FREE shape crosses the play — not a contact. Under an offset the
    # fulcrum is the mouth plane itself, so the geometry demands only that the tube COVER the mouth; what
    # a minimum protrusion must clear beyond that is the entry radius (unnamed) and the axial position
    # stack (unmeasured) — neither is in this model, so no floor below the ratified value is priced here.
    liner_start = {
        "contact_station_under_offset": "the mouth plane itself (the bore's entry edge is the fulcrum), on every geometry — asserted",
        "feature_met": "the tube's cylindrical flank if the tube covers the mouth; its END FACE (ring on ring) "
                       "if it ends flush or short — the materials are polymer on titanium either way (play is "
                       "channel-side, so the tube's outer surface is what meets the bore)",
        "min_protrusion_from_geometry_mm": None,
        "floor_terms_not_in_this_tree": ["the entry radius — NOT SPECIFIED (cem/cathode_flange notes.post_process)",
                                         "the axial position stack: the liner's own differential thermal travel "
                                         "(axial_thermal, 27.6 µm at 40 K) plus tube-length and seating tolerances, none in canon"],
        "ratified_protrusion_mm": LINER_PROTRUSION_MM,
        "ratified_protrusion_source": "cem/cathode_flange bus_liner_protrusion_mm (⚖️ 01_01 §1.4, 2026-09-12)",
        "why": "under offset the mouth edge is the fulcrum, so any tube that covers the mouth meets it on its "
               "flank; the geometry alone sets no minimum beyond covering it, and the two terms a minimum must "
               "clear are unmeasured — the ≥ 1.0 mm stands as a value the geometry cannot price below",
        "coaxial_regime": "the mouth is not reached at all; the drag contact is the tube's flush end at the "
                          "EXIT — see exit_contact",
        "not_modelled": "the contact stress itself — no notch factor and no contact model; wear is BOUNDED in "
                        "this cache's wear_budget block, but its specific rate is NOT MEASURED (00_07 HW.34)",
    }
    # The OTHER end, which the drift picture never saw: coaxially the drag is reacted at the EXIT, where the
    # tube ends flush with the pogo face — the bore's exit edge meets the tube's end corner, edge on edge,
    # the very form the ≥ 1.0 mm protrusion avoids at the mouth. Nothing specifies an exit radius.
    exit_contact = []
    for geo in GEOMETRIES:
        rows = [r for r in regimes if r["geometry"] == geo.label and r["play_side"] == "channel"]
        reactions = [v["exit_reaction_N_upper_rigid_wall"] for r in rows for v in r["by_mu"].values() if v["touches_down"]]
        slopes = [v["slope_at_exit_mrad_rigid_wall"] for r in rows for v in r["by_mu"].values() if v["touches_down"]]
        exit_contact.append({"geometry": geo.label, "exit_mm": geo.pad_mm,
                             "feature": "tube end face flush with the pogo face against the bore's exit edge — ring on ring",
                             "landing_angle_deg_rigid_wall": round(float(np.degrees(max(slopes) * 1e-3)), 4),
                             "reaction_N_over_swept_mu_upper_rigid_wall": [round(min(reactions), 4), round(max(reactions), 4)],
                             "reaction_bound": "UPPER — rigid wall: the drag minus the touchdown drag on every cycle; a "
                                               "compliant polymer edge takes less, down to nothing at the free end",
                             "exit_radius_specified_mm": None, "exit_protrusion_specified_mm": None})
    print(f"  → Exit contact (coaxial drag): edge on edge at the tube's flush end, landing at "
          f"{exit_contact[0]['landing_angle_deg_rigid_wall']:.3f}° with at most {exit_contact[0]['reaction_N_over_swept_mu_upper_rigid_wall'][0]:.2f}–"
          f"{exit_contact[0]['reaction_N_over_swept_mu_upper_rigid_wall'][1]:.2f} N (rigid wall) on the placeholder; no exit radius is specified anywhere.")

    # ── 4c. The §2 «supported» column against the equilibrium ────────────────────────────────────
    # The §2 table prices the liner-supported rod as a 6 mm cantilever (the placeholder's PEEK gap) propped
    # where the bore begins. 🔴 Until 2026-09-14 this block measured that idealisation against the free-shape
    # first contact and reported the column «understated by 40.8 %». Under the equilibrium there is no propped
    # 6 mm span: against a RIGID wall the coaxial root stress is set by the exit contact and the column OVERSTATES
    # it — the sign of the finding reversed with the picture — and that rigid-wall figure is itself the LOWER end
    # of a bracket (a compliant polymer wall raises the root moment), so the column's position INSIDE or ABOVE the
    # bracket is derived per geometry too. Under a channel offset the comparison has no meaning, because the root
    # then carries a MEAN the column does not represent at all.
    sup_nominal = bending_stress_MPa(MU_CONTACT * F_POGO_N, L_FREE_SUP)
    sup_worst = bending_stress_MPa(max(MU_SWEEP) * F_POGO_N, L_FREE_SUP)
    supported_check = {"idealisation": f"a {L_FREE_SUP:.0f} mm cantilever (the placeholder's PEEK gap) propped where the bore "
                                       "begins — the §2 «supported» column, computed on the placeholder only",
                       "supported_column_sigma_MPa": {"nominal_mu": round(sup_nominal, 1), "worst_mu": round(sup_worst, 1)},
                       "coaxial_cap_bound": "LOWER — rigid wall; a compliant polymer wall raises the root moment by 3EI·(R/k)/L², "
                                            "the Ti-bore stop / free cantilever is the UPPER end (bracket_MPa_* per geometry), "
                                            "and the contact compliance that places the root in it is measured nowhere",
                       "by_geometry": [], "coaxial_sign": None, "offset_regime": "not comparable — a mean stress"}

    def _position(x: float, lo: float, hi: float) -> str:
        return "below the rigid-wall end" if x < lo else ("inside the bracket" if x <= hi else "above the upper end")

    for geo in GEOMETRIES:
        rows_g = [r for r in regimes if r["geometry"] == geo.label and r["play_side"] == "channel"]
        cap = max(v["sigma_root_MPa_bonded"] for r in rows_g for v in r["by_mu"].values())
        up_nom = rows_g[0]["by_mu"][str(MU_CONTACT)]["sigma_root_MPa_upper_end"]
        up_worst = rows_g[0]["by_mu"][str(max(MU_SWEEP))]["sigma_root_MPa_upper_end"]
        # The binding alloy's SF at BOTH ends of the bracket, so «infinite life with the liner» can be quoted with its
        # sign: the shipped (welded) endurance of the lowest-endurance alloy against the rigid-wall end and the upper end.
        se_min = min(endurance_MPa(r["yield_MPa"], dict(FAB_BRANCHES)[SHIPPED_BRANCH]) for r in alloy_rows)
        supported_check["by_geometry"].append({"geometry": geo.label, "coaxial_cap_MPa_bonded": cap,
                                               "column_over_cap_nominal": round(sup_nominal / cap, 2),
                                               "column_over_cap_worst": round(sup_worst / cap, 2),
                                               "bracket_MPa_nominal_mu": [cap, up_nom],
                                               "bracket_MPa_worst_mu": [cap, up_worst],
                                               "column_position_nominal_mu": _position(sup_nominal, cap, up_nom),
                                               "column_position_worst_mu": _position(sup_worst, cap, up_worst),
                                               "binding_alloy_sf_shipped_at_rigid_end": round(se_min / cap, 2),
                                               "binding_alloy_sf_shipped_at_upper_end": round(se_min / up_worst, 2)})
    _ratios = [g["column_over_cap_nominal"] for g in supported_check["by_geometry"]]
    supported_check["coaxial_sign"] = (
        ("against a RIGID wall the column OVERSTATES the root stress on every geometry" if min(_ratios) > 1.0
         else "against a RIGID wall the column UNDERSTATES the root stress on at least one geometry")
        + "; against a compliant wall the root lies in [rigid, upper] and the column sits "
        + ", ".join(f"{g['column_position_nominal_mu']} at nominal µ / {g['column_position_worst_mu']} at worst µ ({g['geometry']})"
                    for g in supported_check["by_geometry"]))
    print(f"\n  → §2's supported column ({sup_nominal:.1f} MPa nominal, {sup_worst:.1f} worst µ) against the rigid-wall end: "
          + " · ".join(f"{g['geometry'][:18]} ×{g['column_over_cap_nominal']:.2f}/{g['column_over_cap_worst']:.2f}" for g in supported_check["by_geometry"]))
    print(f"    {supported_check['coaxial_sign']}; under a channel offset the comparison has no meaning (mean stress).")

    # ── 4d. Allocation candidates — the OTHER question the same geometry answers ─────────────────
    banner("Assembly-clearance allocation — which frozen dim moves (00_07 HW.34)")
    print(f"  {'candidate':<26s} {'rod Ø':>6s} {'liner':>6s} {'chan Ø':>7s} {'DIAMETRAL':>10s} "
          f"{'RADIAL':>8s} {'cap σ (placeholder)':>20s} {'F_td':>8s}")
    print(f"  {'-' * 100}")
    allocations = []
    for label, rod_mm, liner_mm, chan_mm in ASSEMBLY_CLEARANCE_CANDIDATES:
        stack_mm = rod_mm + 2.0 * liner_mm
        diametral = chan_mm - stack_mm
        play = diametral / 2.0
        assembles = diametral > 0.0
        # Closed forms on the candidate's OWN rod: cap = 3·E·c·g/L², touchdown = 3·EI·g/L³ (bare rod, placeholder
        # exit) — a candidate that moves the ROD (г) is priced on its own I, never on the canon one.
        ei_c = E_TI * second_moment_m4(rod_mm)
        cap = 3.0 * E_TI * (rod_mm / 2.0) * MM_M * play * MM_M / (PLACEHOLDER_GEOMETRY.pad_mm * MM_M) ** 2 / 1e6 if assembles else None
        f_td = 3.0 * ei_c * play * MM_M / (PLACEHOLDER_GEOMETRY.pad_mm * MM_M) ** 3 if assembles else None
        shipped_row = (abs(rod_mm - D_BUS) < 1e-9 and abs(liner_mm - LINER_WALL_MM) < 1e-9
                       and abs(chan_mm - D_CHANNEL_MM) < 1e-9)
        tag = ("   ⛔ zero/negative — does not assemble" if not assembles
               else "   ✅ RATIFIED + APPLIED" if shipped_row else "")
        print(f"  {label:<26s} {rod_mm:>6.2f} {liner_mm:>6.3f} {chan_mm:>7.2f} "
              f"{diametral * 1000:>7.0f} µm {play * 1000:>5.0f} µm {(f'{cap:.2f} MPa' if cap is not None else '—'):>20s} "
              f"{(f'{f_td:.4f} N' if f_td is not None else '—'):>8s}{tag}")
        allocations.append({"candidate": label, "rod_dia_mm": rod_mm, "liner_wall_mm": liner_mm,
                            "channel_dia_mm": chan_mm, "stack_od_mm": round(stack_mm, 4),
                            "is_shipped_geometry": bool(shipped_row),
                            "diametral_clearance_mm": round(diametral, 4),
                            "radial_play_mm": round(play, 4),
                            "coaxial_cap_sigma_MPa_placeholder": round(cap, 2) if cap is not None else None,
                            "touchdown_drag_N_placeholder": round(f_td, 4) if f_td is not None else None,
                            "assembles": bool(assembles)})
    _ok = [a for a in allocations if a["assembles"]]
    _play = {round(a["radial_play_mm"] * 1000) for a in _ok}
    print(f"\n  → Every non-(а) candidate lands the SAME {'/'.join(str(p) for p in sorted(_play))} µm radial play by construction, so")
    print("    the support question does NOT discriminate between them — the coaxial cap differs only through the")
    print("    rod's own c and I. The verdict is decided by the COSTS named over the table, never by this geometry.")
    print("    ⛔ (а) is listed to show it is not an option: zero diametral clearance is the F3 gate's arithmetic, not an assembly.")

    # ── 5. The WELD SEAM at the root — what a seam acceptance would be judged on (00_07 HW.34) ────
    # 🔴 Until 2026-09-14 this block inverted SF_seam = k·SF_wire on ONE fully-reversed stress — the §2
    # supported column at the worst swept µ, inflated by a span optimism measured along the free-shape first
    # contact — and reported a break-even k. That stress was the root stress of a free cantilever whose
    # length is a free-shape crossing station: no equilibrium configuration produces it. The equilibrium
    # gives the root TWO regimes instead, and neither is a single fully-reversed number:
    #   coaxial — the drag is fully reversed with an amplitude that is a BRACKET (rigid wall = LOWER end,
    #             Ti-bore stop = upper, mean 0; the compliance between them unmeasured);
    #   offset  — a channel off the root axis by more than the play puts a STATIC bending on the same section
    #             (a MEAN that grows with the offset, a rigid-wall UPPER bound) with the reversing drag as
    #             amplitude on top.
    # ⛔ No k is derived from either. This file has no mean-stress correction, so the offset regime cannot be
    #    priced; and a k inverted from the rigid-wall end of the coaxial bracket alone would silently assume
    #    both a coaxiality the stack carries nowhere (00_07 HW.34 ⚖️) and a rigid wall. What a seam acceptance
    #    needs is given instead: the amplitude and mean at the root per regime and geometry, with their signs,
    #    on the same solver and the same offset points as script 68's sweep.
    banner("Weld seam at the root — the inputs a seam acceptance needs (no break-even k is derived)")
    mu_worst = max(MU_SWEEP)
    shipped_derate = dict(FAB_BRANCHES)[SHIPPED_BRANCH]
    root_loading = []
    liner_row = next(r for r in regimes if r["play_side"] == "channel" and r["geometry"] == PLACEHOLDER_GEOMETRY.label)
    liner_def = {"branch": liner_row["branch"], "coating_or_liner_mm": liner_row["coating_or_liner_mm"], "play_side": "channel"}
    zero_play, _ = branch_member(liner_def)
    for geo in GEOMETRIES:
        ch = geo.channel()
        ei_at_bond = member_ei_at(geo, liner_def, bonded=True)
        coax = next(r for r in regimes if r["geometry"] == geo.label and r["play_side"] == "channel")
        cap = coax["by_mu"][str(mu_worst)]["sigma_root_MPa_bonded"]
        cap_upper = coax["by_mu"][str(mu_worst)]["sigma_root_MPa_upper_end"]
        exact = {}
        for e_um in OFFSETS_UM:
            res = bc.solve(ch, ei_at_bond, zero_play, offset_mm=e_um / 1000.0)
            assert res["peak_moment_station_mm"] == 0.0, f"{geo.label}: peak moment left the root at offset {e_um} µm"
            exact[e_um] = root_sigma_MPa(res["clamp_moment_Nm"])
        past = [e for e in OFFSETS_UM if e / 1000.0 > zero_play]
        secant = (exact[past[-1]] - exact[past[0]]) / (past[-1] - past[0])
        amps = []
        assert set(REVERSING_DRAG_OFFSETS_UM) <= set(OFFSETS_UM), "the reversing-drag offsets must be points of the static sweep"
        for e_um in REVERSING_DRAG_OFFSETS_UM:
            mp = bc.solve(ch, ei_at_bond, zero_play, drag_N=+mu_worst * F_POGO_N, offset_mm=e_um / 1000.0)
            mn = bc.solve(ch, ei_at_bond, zero_play, drag_N=-mu_worst * F_POGO_N, offset_mm=e_um / 1000.0)
            assert mp["peak_moment_station_mm"] == 0.0 and mn["peak_moment_station_mm"] == 0.0, "peak moment left the root under reversing drag"
            amps.append({"offset_um": e_um, "mean_MPa": round(exact[e_um], 2),
                         "amplitude_MPa": round(root_sigma_MPa((mp["clamp_moment_Nm"] - mn["clamp_moment_Nm"]) / 2.0), 2)})
        amp_max = max(a["amplitude_MPa"] for a in amps)
        root_loading.append({
            "geometry": geo.label,
            "coaxial": {"amplitude_MPa_lower_rigid_wall": cap, "amplitude_MPa_upper_end": cap_upper,
                        "upper_end_is": coax["by_mu"][str(mu_worst)]["upper_end_is"], "mean_MPa": 0.0,
                        "bound": "the rigid-wall figure is the LOWER end — a compliant polymer wall raises the root moment by "
                                 "3EI·(R/k)/L²; the upper end is the Ti-bore stop (or the free cantilever where the drag cannot "
                                 "reach it); the contact compliance that places the amplitude in the bracket is measured nowhere",
                        "note": "fully reversed; at the zero-interference play (the largest play, so the largest rigid-wall "
                                "figure — the fit's OD growth lowers it, script 68 sweeps the window rows)"},
            "offset": {"mean_MPa_per_um_past_play": round(secant, 3), "secant_between_um": [past[0], past[-1]],
                       "by_offset": amps, "amplitude_MPa_max_over_swept_offsets": amp_max,
                       "bound": "rigid-wall figures: the static mean is an UPPER bound (a compliant mouth relieves a "
                                "displacement-driven load); the amplitude bracket under a compliant mouth is not derived",
                       "note": "the mean is a FUNCTION of an offset measured nowhere; the amplitude is the reversing "
                               "worst-µ drag on top of it, and on the lock-window geometry it exceeds the rigid-wall coaxial figure"},
            "peak_moment_at_root_in_every_solve": True,
        })
        print(f"  {geo.label:<28s} coaxial: amplitude {cap:.2f} (rigid wall, LOWER) … {cap_upper:.1f} MPa (upper end), mean 0 · "
              f"offset: mean {secant:.3f} MPa/µm past the play, amplitude up to {amp_max:.2f} MPa (rigid wall) over offsets "
              f"{min(REVERSING_DRAG_OFFSETS_UM)}–{max(REVERSING_DRAG_OFFSETS_UM)} µm")
    print("  ⛔ No break-even k: the offset regime carries a MEAN this file cannot correct for, the coaxial amplitude is a")
    print("     BRACKET whose compliance input is unmeasured, and a k from its rigid-wall end alone would assume both a")
    print("     coaxiality no drawing demands and a rigid wall. k itself stays NOT MEASURED — it comes from the vendor.")
    print("  ⚠️ Three seam mechanisms stay outside any bound, with their signs: bead section (RELIEVES) · weld-toe notch")
    print("     (AGGRAVATES) · weld residual TENSION (a mean, and the model has no Goodman/Haigh correction anywhere).")

    weld_seam = {
        "question": "00_07 HW.34 — the ratified rod is a WELDED drawn wire, so a heat-affected zone sits at the "
                    "root of the cantilever. The wrought derate describes the WIRE. What would a seam acceptance "
                    "have to be judged on?",
        "seam_location": "root of the cantilever — the peak-moment section in every drag and offset configuration "
                         "the equilibrium computes (asserted per solve from the moment field; the one class where "
                         "the peak leaves the root is a tilt about the mouth large enough to take up the play on both "
                         "walls, script 68 §tilt)",
        "geometry_modelled": False,
        "knockdown_k_measured": WELD_KNOCKDOWN_MEASURED,
        "knockdown_k_source": "NOT MEASURED — no canon row, no vendor answer, no experiment in this tree. A value is "
                              "an RFQ/literature input and enters through the Validation Gate (00_06 §0), not through "
                              "this constant",
        "break_even_k": None,
        "break_even_k_not_derived_because": "SF_seam = k·SF_wire needs ONE fully-reversed stress at the root. The "
                                            "equilibrium gives the root two regimes: on a coaxial channel the drag is "
                                            "fully reversed with an amplitude that is a BRACKET (rigid wall = LOWER end, "
                                            "Ti-bore stop = upper, the contact compliance between them unmeasured); a "
                                            "channel off the root axis by more than the play puts a STATIC mean on the "
                                            "same section with the drag as amplitude. No mean-stress correction exists in "
                                            "this file, so the offset regime cannot be priced, and a k inverted from the "
                                            "rigid-wall end of the coaxial bracket alone would silently assume both a "
                                            "coaxiality the stack carries nowhere (00_07 HW.34) and a rigid wall. Until "
                                            "2026-09-14 a k was inverted from a stress no equilibrium configuration produces",
        "root_section_loading": root_loading,
        "what_a_seam_acceptance_needs": ["the joint's fatigue class / knockdown k from the vendor (weld class, WPS, "
                                         "toe treatment) — RFQ, 00_07 HW.34",
                                         "the channel offset the stack delivers relative to the root axis — computed "
                                         "nowhere; its price is an order of magnitude apart between the insertion "
                                         "placeholder and the lock window (HW.26 G1 first)",
                                         "a mean-stress model for the offset regime — absent from this tree"],
        "markers": [{"label": lbl, "k": k} for lbl, k in WELD_KNOCKDOWN_MARKERS],
        "markers_note": "OUR scale for reading a vendor's k (as bad as an as-printed surface ⊥ as good as the drawn "
                        "wire); nothing here is compared against them since no k is derived",
        "not_modelled": {"bead_section": "an upset/fillet raises the local section, which LOWERS nominal stress — this "
                                         "omission is conservative",
                         "weld_toe_notch": "a geometric stress concentration at the toe — this omission is ANTI-conservative",
                         "mean_stress": "weld residual tension is a mean stress, and this file carries no Goodman/Haigh "
                                        "correction at all — the same absence that stops the offset regime being priced",
                         "seam_position": "the fusion line is assumed coincident with the fixed end; a socketed or "
                                          "filleted joint moves effective fixity",
                         "clamp": "perfect — weld and printed-anode compliance lower every stress here"},
    }

    # ── 5b. The OTHER coefficient the model took a single POINT of (00_07 HW.34) ─────────────────
    # 🔴 `ENDURANCE_OVER_YIELD` is a BAND, written beside the constant since the file was born, and
    # only its MIDPOINT ever entered the model. Every SF scales LINEARLY with it, so «all six clear
    # SF 2» was a claim about one point of an unmeasured band wearing the clothes of a claim about
    # the band. ⛔ This block does NOT choose an end and does NOT re-verdict: it reports whether the
    # STANDING conclusion survives the band — the measurement the open ⚖️ was missing. It sweeps the
    # §2 free-cantilever column only: the seam column it used to carry was priced on the retired
    # drift-picture stress, and no seam k exists to sweep.
    banner("Endurance-ratio band — does the standing bare-rod verdict survive it? (00_07 HW.34, sweep only)")
    print(f"  σ_e/σ_y is a BAND {min(ENDURANCE_RATIO_SWEEP):.2f}–{max(ENDURANCE_RATIO_SWEEP):.2f}; the model runs "
          f"at {ENDURANCE_OVER_YIELD:.2f}. ⛔ A sweep, never a distribution — no end is measured for OUR alloys.")
    print(f"  {'ratio':>6s} {'bare: ∞-life':>14s} {'below SF 2':>24s} {'predicted failure':>20s}")
    print(f"  {'-' * 70}")
    ratio_rows = []
    for ratio in ENDURANCE_RATIO_SWEEP:
        inf_l, marg_l, fail_l = [], [], []
        sf_by_alloy = {}
        for r in alloy_rows:
            sf_u = endurance_MPa(r["yield_MPa"], shipped_derate, ratio) / sig_unsup
            sf_by_alloy[r["alloy"]] = round(sf_u, 2)
            (inf_l if sf_u >= INFINITE_LIFE_SF else fail_l if sf_u < 1.0 else marg_l).append(r["alloy"])
        # ⛔ The BINDING SF gets its own field because prose quotes it: a doc number with no cache
        #    owner is the one thing this tree forbids outright, and «Ta reads 1.96 at 0.40» is
        #    exactly the sentence a reader acts on.
        binding_alloy = min(sf_by_alloy, key=lambda a: sf_by_alloy[a])
        ratio_rows.append({
            "endurance_over_yield": ratio,
            "unsupported_infinite_life": inf_l,
            "unsupported_marginal": marg_l,
            "unsupported_predicted_failure": fail_l,
            "unsupported_infinite_life_for_all": len(inf_l) == len(alloy_rows),
            "sf_unsupported_by_alloy": sf_by_alloy,
            "binding_alloy_unsupported": binding_alloy,
            "binding_sf_unsupported": sf_by_alloy[binding_alloy],
        })
        print(f"  {ratio:>6.2f} {f'{len(inf_l)}/{len(alloy_rows)}':>14s} {', '.join(marg_l) or '—':>24s} "
              f"{', '.join(fail_l) or '—':>20s}")
    # ⛔ DERIVED, never typed: the question is INVARIANCE, and a hand-written «holds across the band»
    #    is exactly the sentence that survives the input that falsifies it.
    band_all_clear = {r["unsupported_infinite_life_for_all"] for r in ratio_rows}
    print(f"\n  → «bare rod reaches infinite life for EVERY alloy» is "
          f"{'INVARIANT across the band' if len(band_all_clear) == 1 else 'NOT invariant — it FLIPS inside the band'}.")
    print("  ⛔ Which end to stand on is a ⚖️ (00_07 HW.34); this block measures, it does not choose.")

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
    bore_state = "RATIFIED 2026-09-18" if LINER_BORE_SPECIFIED_MM is not None else "ASSUMED — not specified anywhere"
    print(f"  Pair: wire Ø{D_BUS:.2f} in a tube bore Ø{2 * LINER_BORE_M / MM_M:.5f} ({bore_state}), wall "
          f"{LINER_WALL_MM:.3f} ⇒ OD Ø{2 * LINER_OD_M / MM_M:.5f} (CEM-derived).")
    if LINER_BORE_SPECIFIED_MM is None:
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
    centre_um = (floor + ceiling) / 2 * 2e6
    if LINER_BORE_SPECIFIED_MM is None:
        print(f"  ⛔ To land INSIDE that window the NOMINAL must move: the tube bore has to run "
              f"{centre_um:.1f} µm under the wire")
        print("     diametrally at mid-window. That is a ⚖️ (a nominal interference, or a graded/selected")
        print("     fit, or a heated assembly — available only BEFORE enzyme functionalisation), not a")
        print("     tolerance question, and it is NOT decided here.")
    else:
        nominal_um = (D_BUS - LINER_BORE_SPECIFIED_MM) * 1e3
        print(f"  ⚖️ Ratified nominal: bore {nominal_um:.2f} µm under the wire (diametral) against the recomputed "
              f"window centre {centre_um:.2f} µm — {nominal_um - centre_um:+.2f} µm apart;")
        print("     fitted hot (01_01 §3 step 4a); a sum of the two bands wider than the window → sort around the same target.")

    # The play the clearance table above treats as a constant — priced across the window.
    # ⚖️ With the ratified nominal the interference comes from a SMALLER BORE at a fixed wall, so the free OD
    #    is smaller by 2δ before the fit swells it back by the Lamé growth: play = play_zero + δ − growth. The
    #    pre-verdict reading (bore = rod Ø) had no such term, and read the whole growth as lost play.
    play_nominal = (D_CHANNEL_MM - (D_BUS + 2.0 * LINER_WALL_MM)) / 2.0 * MM_M
    bore_follows_fit = LINER_BORE_SPECIFIED_MM is not None
    play_rows = []
    for label, d in (("floor", floor), ("mid-window", 0.5 * (floor + ceiling)), ("ceiling", ceiling)):
        growth = liner_od_growth_m(per_um["P_c"] * d)
        play = play_nominal + (d if bore_follows_fit else 0.0) - growth
        play_rows.append({"at": label, "interference_radial_um": round(d * 1e6, 2),
                          "od_growth_radial_um": round(growth * 1e6, 2),
                          "channel_radial_play_um": round(play * 1e6, 2),
                          "outer_surface_still_free": bool(play > 0.0)})
        print(f"    {label:<11s} δ {d * 1e6:>5.2f} µm → OD +{growth * 1e6:>5.2f} µm radial → channel "
              f"play {play_nominal * 1e6:.1f} → {play * 1e6:>5.2f} µm")
    if bore_follows_fit:
        print(f"  ✅ With the ratified nominal the {play_nominal * 1e6:.0f} µm radial play §2 and §4 use is the LOWER end of the")
        print("     window: the smaller bore pays for the Lamé growth, so edge bearing is read conservatively.")
    else:
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
        "nominal_vs_window_centre_diametral_um": (None if LINER_BORE_SPECIFIED_MM is None else
                                                  round((D_BUS - LINER_BORE_SPECIFIED_MM) * 1e3 - (floor + ceiling) * 1e6, 3)),
        "nominal_finding": ("RATIFIED founder 2026-09-18 (00_07 HW.34): the bore nominal is wire - 11.41 um "
                            "(the window centre at bore = rod diameter), the wall stays 0.15 so OD = ID + 0.30, "
                            "and the tube is fitted hot (01_01 3 step 4a); a sum of the two vendor bands wider "
                            "than the window is sorted around the same target. Before the verdict this key read "
                            "'SPECIFIED NOWHERE' - the bought part was dimensioned by a quantity its process "
                            "does not control, and the fit was whatever the vendor's process centred on"
                            if LINER_BORE_SPECIFIED_MM is not None else
                           "the tube's bore nominal is SPECIFIED NOWHERE. Canon freezes the WALL "
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
                           "could never falsify"),
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
                                        "note": ("with the RATIFIED nominal (2026-09-18) the interference comes from a smaller "
                                                         "bore at a fixed wall, so play = play_zero + delta - OD growth: the 25 um the "
                                                         "clearance table uses is the LOWER end across the window, i.e. conservative "
                                                         "for edge bearing" if bore_follows_fit else
                                                         "the 25 um the clearance table uses is the ZERO-"
                                                         "interference value, i.e. the one fit the direction "
                                                         "verdict excludes; at the ceiling it is ~40 % smaller, "
                                                         "which makes EDGE bearing more likely, not less")},
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
    # 🔴 ⚖️ 2026-09-11 retired the fatigue ground and replaced it with WEAR, and this block bounds it: the
    # specific wear rate of PEEK on Ti is NOT in this tree, so the model bounds what it CAN — the rate the
    # pair may have and still keep the wall — and an accelerated tribo-test then returns a VERDICT.
    # 🔴 THE STATION IS THE EQUILIBRIUM'S SINCE 2026-09-14. Until then the block scanned a single-prop family
    # along the free-shape first contact and took the free slope there as the slip — a station the contact
    # solver says is never a station. Two regimes now, both from §4/§4b:
    #   coaxial — the drag is reacted at the EXIT (the tube's flush end, edge on edge), with R = µ·F − F_td;
    #   offset  — the MOUTH carries a static reaction and the reversing drag rotates the rod about it.
    # 🔑 AND THE COAXIAL SLIDING IS A BRACKET WHOSE ENDS HAVE SIGNS. Against a RIGID wall the touched-down shape
    #    does not change with the drag, so the surface fibre at the exit does not rotate while pressed on the
    #    wall: the rotation between the two touched-down states happens while the rod crosses the play, out of
    #    contact — a rigid point contact slides ZERO from bending kinematics. Against the real wall — the polymer
    #    on the Ti bore's exit edge — the exit yields by R/k and the rod DOES rotate in contact, by up to the
    #    rotation between the rigid-wall state and the Ti-bore stop (the polymer wall fully yielded) or the free
    #    cantilever where the drag cannot reach the bore (§4, `in_contact_rotation_path_per_cycle_um_upper`).
    #    So the in-contact sliding per cycle lies in [0 (rigid), 4·r·(θ_upper − θ_rigid)], and the contact
    #    compliance that places it is measured nowhere. ⛔ The rigid-wall rotation 4·r·θ_rigid — «the ceiling»
    #    this block priced its budget on until 2026-09-14 — is the OUT-of-contact rotation: it bounds nothing,
    #    and it is kept as a figure only so the rigid-wall reading stays quotable as what it is.
    # 🔑 THE CHAIN, so a reader can attack each link separately:
    #    duty  = (cycles from script 62's real-wind cache) × (in-contact sliding per cycle at the station)
    #    load  = the station's wall reaction from the contact equilibrium (rigid wall = its UPPER bound)
    #    budget= wear-through volume / (load × duty), with the area bracketed between a bound the
    #            MATERIAL sets and the full projected bearing of the bore run
    #    The BOUND takes the upper sliding and the upper reaction (the two maxima are not simultaneous, so the
    #    product bound is conservative): an allowable k below it passes whatever the compliance turns out to be.
    banner("Wear budget — what rate may the pair have and still keep the wall? (equilibrium stations)")
    # 🔑 SELF-CHECK against a CLOSED-FORM solution, not against a frozen baseline: the touched-down bare rod's
    #    exit slope is 3·g/(2·L) (a cantilever deflected by g at its tip), and the exit reaction is the drag
    #    minus the touchdown drag (asserted per row in §4).
    _chk = _coax_solves[(PLACEHOLDER_GEOMETRY.label, liner_def["branch"], max(MU_SWEEP), "bare")]
    assert abs(bc.slope_rad(_chk, PLACEHOLDER_GEOMETRY.pad_mm) - 3.0 * zero_play * MM_M / (2.0 * PLACEHOLDER_GEOMETRY.pad_mm * MM_M)) \
        <= 0.005 * 3.0 * zero_play * MM_M / (2.0 * PLACEHOLDER_GEOMETRY.pad_mm * MM_M), "exit slope of the touched-down rod ≠ 3g/(2L)"
    wear_rows: list[dict] = []
    duty_anchors: list[dict] = []
    thermal_rows: list[dict] = []
    binding_wear: dict | None = None
    branch_discrimination: dict | None = None
    wind = None
    if WIND_CACHE.exists():
        wind = json.loads(WIND_CACHE.read_text())
        for row in wind.get("beaufort_exceedance", []):
            duty_anchors.append({"anchor": row["anchor"], "n_cycles": float(row["n_eff_cycles_upper_bound"])})
        # Continuous sway at the high f0 reading, kept as the ABSOLUTE ceiling: script 62's own verdict is
        # that neither the duty nor the frequency closes to a single number, so the bracket is the honest
        # object and its top is this. Its label is script 62's, never typed here.
        duty_anchors.append({"anchor": f"ceiling: {wind['budget_basis']}",
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
        # ⛔ THE FLOW PRESSURE THAT BOUNDS THE CONTACT AREA IS A SWEEP: A ≥ R/p_flow, the TIGHTEST factor drives
        #    the headline (see the constant block). With A flow-limited and duty = R·s the reaction CANCELS:
        #    k = h/(p_flow·s) exactly — pinned in-run against the closed form on every row.
        p_flow_N_mm2 = max(CONTACT_CONSTRAINT_FACTORS) * SIGMA_YIELD_PEEK_PA / 1e6

        def budgets(t_mm: float, od_mm: float, run_mm: float, r_wall: float, slip_mm: float) -> tuple[dict, float, float, list[dict]]:
            area_by_factor = {f"{c:.1f}": r_wall / (c * SIGMA_YIELD_PEEK_PA) * 1e6 for c in CONTACT_CONSTRAINT_FACTORS}
            a_min_mm2 = min(area_by_factor.values())
            # The opposite end: the pair worn in until it bears over the whole bore run, in the PROJECTED-AREA
            # convention that polymer plain-bearing wear rates are quoted against.
            a_proj_mm2 = od_mm * run_mm
            per_anchor = []
            for anc in duty_anchors:
                sliding_m = anc["n_cycles"] * slip_mm * MM_M
                duty_nm = r_wall * sliding_m
                k_edge = t_mm * a_min_mm2 / duty_nm
                k_closed = t_mm / (p_flow_N_mm2 * sliding_m)
                assert abs(k_edge - k_closed) <= 1e-9 * k_closed, \
                    "the flow-limited budget stopped reducing to h/(p_flow·s) — the reaction crept back in"
                per_anchor.append({"anchor": anc["anchor"], "n_cycles": anc["n_cycles"],
                                   "sliding_distance_m": round(sliding_m, 1), "duty_N_m": round(duty_nm, 1),
                                   "k_edge": k_edge, "k_conformal": t_mm * a_proj_mm2 / duty_nm})
            # 🔑 Bounds with a KNOWN sign are asserted IN THE CODE: the bracket must be a bracket, every budget
            #    positive, and the slip a small fraction of the span or the small-deflection beam is wrong.
            assert 0.0 < a_min_mm2 <= a_proj_mm2, "the area bracket inverted — bound above the full run"
            assert all(p["k_edge"] > 0.0 for p in per_anchor), "non-positive budget"
            assert slip_mm < 0.01 * run_mm, "slip is no longer small against the run"
            return area_by_factor, a_min_mm2, a_proj_mm2, per_anchor

        print(f"  {'geometry':<20s} {'branch':<22s} {'regime':<16s} {'µ/offset':>9s} {'R≤':>8s} {'s/cyc≤':>9s} "
              f"{'sliding≤':>9s} {'k≥ edge':>10s} {'k≥ worn':>10s} {'rigid fig':>10s}")
        print(f"  {'-' * 134}")
        for geo in GEOMETRIES:
            ch = geo.channel()
            run_mm = geo.pad_mm - geo.gap_mm
            for label, t_mm, play_side in INSULATION_OPTIONS:
                row = {"branch": label, "coating_or_liner_mm": t_mm, "play_side": play_side}
                play, _ = branch_member(row)
                od_mm = D_BUS + 2.0 * t_mm
                coax = next(r for r in regimes if r["geometry"] == geo.label and r["branch"] == label)
                # ── COAXIAL regime: the exit station ──
                for mu in MU_SWEEP:
                    v = coax["by_mu"][str(mu)]
                    if not v["touches_down"]:
                        wear_rows.append({"geometry": geo.label, "branch": label, "regime": "coaxial", "mu": mu, "contact": False,
                                          "why": "below the touchdown drag the rod never reaches the wall — a free "
                                                 "cantilever at this µ, so no rubbing is priced"})
                        print(f"  {geo.label[:18]:<20s} {label:<22s} {'coaxial':<16s} {mu:>9.1f} {'—':>8s} {'—':>9s} {'—':>9s} {'no contact':>10s}")
                        continue
                    res = _coax_solves[(geo.label, label, mu, "bonded")]
                    theta_rigid = bc.slope_rad(res, geo.pad_mm)
                    r_upper = v["exit_reaction_N_upper_rigid_wall"]
                    rot_rigid_mm = 4.0 * (od_mm / 2.0) * theta_rigid      # out-of-contact rotation between the ±wall states
                    s_upper_mm = _rot_upper[(geo.label, label, mu)]       # in-contact sliding at the upper end of the bracket
                    # The BOUND: upper sliding × upper reaction (conservative — the two maxima are not simultaneous).
                    area_by_factor, a_min_mm2, a_proj_mm2, per_bound = budgets(t_mm, od_mm, run_mm, r_upper, s_upper_mm)
                    # The rigid-wall FIGURE: the out-of-contact rotation counted as if it happened in contact — what this
                    # block called a ceiling until 2026-09-14; it bounds nothing and is kept only as the rigid reading.
                    _, _, _, per_rigid = budgets(t_mm, od_mm, run_mm, r_upper, rot_rigid_mm)
                    per_anchor = [{"anchor": b["anchor"], "n_cycles": b["n_cycles"],
                                   "sliding_distance_m_upper": b["sliding_distance_m"], "duty_N_m_upper": b["duty_N_m"],
                                   "k_bound_edge_mm3_per_Nm": b["k_edge"], "k_bound_conformal_mm3_per_Nm": b["k_conformal"],
                                   "k_rigid_wall_figure_edge_mm3_per_Nm": f["k_edge"],
                                   "k_rigid_wall_figure_conformal_mm3_per_Nm": f["k_conformal"]}
                                  for b, f in zip(per_bound, per_rigid, strict=True)]
                    worst = min(per_anchor, key=lambda p: p["k_bound_edge_mm3_per_Nm"])
                    wear_rows.append({
                        "geometry": geo.label, "branch": label, "regime": "coaxial", "mu": mu, "contact": True,
                        "station_mm": geo.pad_mm, "station": "exit — the tube's flush end against the bore's exit edge",
                        "wall_allowance_mm": t_mm, "rubbing_od_mm": round(od_mm, 3),
                        "reaction_N_upper_rigid_wall": round(r_upper, 4),
                        "reaction_bound": "UPPER — rigid wall (drag − touchdown drag); a compliant polymer edge takes less",
                        "landing_angle_mrad_rigid_wall": round(theta_rigid * 1e3, 4),
                        "sliding_in_contact_um_rigid_kinematics": 0.0,
                        "out_of_contact_rotation_per_cycle_um_rigid_wall": round(rot_rigid_mm * 1000.0, 3),
                        "sliding_in_contact_per_cycle_um_upper": round(s_upper_mm * 1000.0, 3),
                        "upper_end_is": v["upper_end_is"],
                        "sliding_bracket_note": "in-contact sliding per cycle lies in [0 (rigid wall), 4·r·(θ_upper − θ_rigid)]; "
                                                "the rigid-wall rotation 4·r·θ_rigid is OUT of contact and bounds nothing; the "
                                                "contact compliance that places the pair in the bracket is measured nowhere, and "
                                                "the mode at the rigid end is a reversing normal load with a landing (partial "
                                                "slip / impact fretting, not modelled)",
                        "area_material_bound_mm2": round(a_min_mm2, 5),
                        "area_by_constraint_factor_mm2": {k: round(vv, 5) for k, vv in area_by_factor.items()},
                        "area_projected_full_run_mm2": round(a_proj_mm2, 3),
                        "by_duty_anchor": per_anchor,
                        "k_span_ratio": round(a_proj_mm2 / a_min_mm2, 1),
                    })
                    print(f"  {geo.label[:18]:<20s} {label:<22s} {'coaxial':<16s} {mu:>9.1f} {r_upper:>6.3f} N {s_upper_mm * 1000:>7.2f} µm "
                          f"{worst['sliding_distance_m_upper']:>7.0f} m {worst['k_bound_edge_mm3_per_Nm']:>10.2e} {worst['k_bound_conformal_mm3_per_Nm']:>10.2e} "
                          f"{worst['k_rigid_wall_figure_edge_mm3_per_Nm']:>10.2e}")
                # ── OFFSET regime: the mouth station, shipped branch, swept offsets past the play ──
                past = [e for e in OFFSETS_UM if e / 1000.0 > play]
                if not past:
                    wear_rows.append({"geometry": geo.label, "branch": label, "regime": "offset", "contact": False,
                                      "why": f"the swept offsets (≤ {max(OFFSETS_UM)} µm) lie inside this branch's play "
                                             f"({play * 1e3:.0f} µm), so the mouth is never a station on the sweep"})
                    continue
                ei_at_bond = member_ei_at(geo, row, bonded=True)
                for e_um in past:
                    sol = {tag: bc.solve(ch, ei_at_bond, play, drag_N=f, offset_mm=e_um / 1000.0)
                           for tag, f in (("static", 0.0), ("+drag", +mu_worst * F_POGO_N), ("-drag", -mu_worst * F_POGO_N))}
                    mouth_r = {tag: next((z["force_N"] for z in s["contacts"] if abs(z["station_mm"] - geo.gap_mm) < 1e-9), 0.0)
                               for tag, s in sol.items()}
                    loaded_through = min(mouth_r.values()) > 0.0
                    d_theta = abs(bc.slope_rad(sol["+drag"], geo.gap_mm) - bc.slope_rad(sol["-drag"], geo.gap_mm))
                    slip_mm = 2.0 * (od_mm / 2.0) * d_theta
                    r_wall = max(mouth_r.values())
                    area_by_factor, a_min_mm2, a_proj_mm2, per_rigid = budgets(t_mm, od_mm, run_mm, r_wall, slip_mm)
                    per_anchor = [{"anchor": f["anchor"], "n_cycles": f["n_cycles"],
                                   "sliding_distance_m": f["sliding_distance_m"], "duty_N_m": f["duty_N_m"],
                                   "k_rigid_wall_figure_edge_mm3_per_Nm": f["k_edge"],
                                   "k_rigid_wall_figure_conformal_mm3_per_Nm": f["k_conformal"]} for f in per_rigid]
                    worst = min(per_anchor, key=lambda p: p["k_rigid_wall_figure_edge_mm3_per_Nm"])
                    wear_rows.append({
                        "geometry": geo.label, "branch": label, "regime": "offset", "offset_um": e_um, "mu": mu_worst, "contact": True,
                        "station_mm": geo.gap_mm, "station": "mouth — the bore's entry edge against the tube's flank",
                        "wall_allowance_mm": t_mm, "rubbing_od_mm": round(od_mm, 3),
                        "mouth_reaction_N": {k: round(vv, 4) for k, vv in mouth_r.items()},
                        "mouth_loaded_through_the_cycle": bool(loaded_through),
                        "reaction_N_upper_rigid_wall": round(r_wall, 4),
                        "rotation_about_mouth_per_cycle_mrad": round(d_theta * 1e3, 4),
                        "slip_per_cycle_um_rigid_wall": round(slip_mm * 1000.0, 3),
                        "bound_note": "rigid-wall FIGURES, not bounds: the mouth reaction is an UPPER bound (a compliant mouth "
                                      "relieves a displacement-driven load), and the in-contact rotation about a compliant mouth "
                                      "is not derived — 2·r·Δθ is the rigid-wall rotation about the loaded mouth as the drag "
                                      "reverses; a sliding contact under a sustained load when the mouth stays loaded through the "
                                      "cycle, intermittent when it does not (the reaction taken is the largest of the three states)",
                        "area_material_bound_mm2": round(a_min_mm2, 5),
                        "area_by_constraint_factor_mm2": {k: round(vv, 5) for k, vv in area_by_factor.items()},
                        "area_projected_full_run_mm2": round(a_proj_mm2, 3),
                        "by_duty_anchor": per_anchor,
                        "k_span_ratio": round(a_proj_mm2 / a_min_mm2, 1),
                    })
                    print(f"  {geo.label[:18]:<20s} {label:<22s} {'offset (rigid)':<16s} {e_um:>7d} µm {r_wall:>6.3f} N {slip_mm * 1000:>7.2f} µm "
                          f"{worst['sliding_distance_m']:>7.0f} m {'—':>10s} {'—':>10s} {worst['k_rigid_wall_figure_edge_mm3_per_Nm']:>10.2e}"
                          f"{'' if loaded_through else '   (mouth unloads during part of the cycle)'}")
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
        sway_max = max((p.get("sliding_distance_m_upper", p.get("sliding_distance_m", 0.0)) for w in wear_rows if w["contact"]
                        for p in w["by_duty_anchor"]), default=0.0)
        thermal_max = max(t["sliding_distance_m"] for t in thermal_rows)
        print(f"\n  → Second driver, the liner's differential thermal travel: at most "
              f"{thermal_max:.3f} m of sliding over the service life")
        print(f"    against up to {sway_max:.0f} m from sway — "
              f"{sway_max / thermal_max:.0e}× smaller, so the sway drag is the whole wear axis "
              f"(DERIVED, not assumed).")
        contact_rows = [w for w in wear_rows if w["contact"]]
        coax_rows = [w for w in contact_rows if w["regime"] == "coaxial"]
        if coax_rows:
            liner_label = liner_def["branch"]
            shipped_rows = [w for w in coax_rows if w["branch"] == liner_label]
            # The binding row is the SHIPPED branch's worst corner on the BOUND: the tight end ties across the µ rows
            # once the Ti-bore stop saturates the in-contact rotation (the sliding stops growing with µ), so the tie
            # is broken by the worn-in end, i.e. by the largest reaction.
            # ⛔ The tie is analytic, not floating-point: the rows differ at the 1e-10 level through the solve, so a
            #    raw `min` picked the binding row by NOISE (µ 0.4 on one cycle count, µ 0.5 on another). The tight
            #    end is compared at six significant figures — far below anything the budget is quoted at.
            def _corner(w: dict) -> tuple[float, float]:
                edge = min(p["k_bound_edge_mm3_per_Nm"] for p in w["by_duty_anchor"])
                return float(f"{edge:.6e}"), min(p["k_bound_conformal_mm3_per_Nm"] for p in w["by_duty_anchor"])
            binding_wear = min(shipped_rows or coax_rows, key=_corner)
            b_worst = min(binding_wear["by_duty_anchor"], key=lambda p: p["k_bound_edge_mm3_per_Nm"])
            # 🔴 DOES THE WEAR AXIS DISCRIMINATE THE BRANCHES? Derived on BOTH axes, because the answer differs:
            #    on the rigid-wall figures a thin film demands a far stricter rate (allowance ÷ the same rotation);
            #    on the BOUND the in-contact sliding is capped by the polymer's own wall (6·r·t/L at the Ti-bore stop),
            #    so the allowance and the sliding both scale with the wall and the tight end stops depending on it.
            by_key = {(w["geometry"], w["branch"], w["mu"]): w for w in coax_rows}
            disc = []
            for (g_, b_, mu_), w in by_key.items():
                peer = by_key.get((g_, liner_label, mu_))
                if peer is None or b_ == liner_label:
                    continue
                fb = min(p["k_bound_edge_mm3_per_Nm"] for p in w["by_duty_anchor"])
                lb = min(p["k_bound_edge_mm3_per_Nm"] for p in peer["by_duty_anchor"])
                fr = min(p["k_rigid_wall_figure_edge_mm3_per_Nm"] for p in w["by_duty_anchor"])
                lr = min(p["k_rigid_wall_figure_edge_mm3_per_Nm"] for p in peer["by_duty_anchor"])
                disc.append({"geometry": g_, "branch": b_, "mu": mu_,
                             "film_over_liner_tight_bound": round(fb / lb, 3),
                             "film_over_liner_tight_rigid_figure": round(fr / lr, 4),
                             "film_stricter_on_bound": bool(fb < lb), "film_stricter_on_rigid_figure": bool(fr < lr)})
            branch_discrimination = {
                "rows": disc,
                "films_stricter_on_rigid_wall_figures": bool(disc) and all(d["film_stricter_on_rigid_figure"] for d in disc),
                "films_stricter_on_bounds": bool(disc) and all(d["film_stricter_on_bound"] for d in disc),
                "films_stricter_on_bounds_anywhere": any(d["film_stricter_on_bound"] for d in disc),
                "note": "on the rigid-wall figures the conformal films demand a stricter rate than the shipped liner at every "
                        "swept µ where both touch down; on the BOUND they do not — at the Ti-bore stop the in-contact sliding "
                        "is 6·r·t/L, proportional to the polymer's own wall, so a thick wall buys allowance and spends it on "
                        "sliding in equal measure, and the tight end stops depending on the wall. The wear budget therefore "
                        "discriminates the branches ONLY against a rigid wall; on the bracket it does not, and which reading "
                        "applies is set by the contact compliance, measured nowhere",
            }
            print(f"\n  → BOUND for the shipped branch at its worst corner ({binding_wear['regime']} regime, "
                  f"{binding_wear['geometry']}, µ {binding_wear['mu']}, {b_worst['anchor']}):")
            print(f"    an allowable k below {b_worst['k_bound_edge_mm3_per_Nm']:.2e} mm³/(N·m) keeps the wall whatever the contact")
            print(f"    compliance, if the contact stays the MATERIAL-bounded patch ({binding_wear['area_material_bound_mm2']:.4f} mm² — PEEK at the")
            print(f"    TIGHTEST swept flow pressure; the loosest gives {max(binding_wear['area_by_constraint_factor_mm2'].values()):.4f} mm²), and below")
            print(f"    {b_worst['k_bound_conformal_mm3_per_Nm']:.2e} once it is worn in over the run. The rigid-wall FIGURES are "
                  f"{b_worst['k_rigid_wall_figure_edge_mm3_per_Nm']:.2e} / {b_worst['k_rigid_wall_figure_conformal_mm3_per_Nm']:.2e}")
            print("    — the out-of-contact rotation counted as if in contact; they bound nothing.")
            print(f"  🔴 The two ends differ by {binding_wear['k_span_ratio']:.0f}×, and NOTHING in "
                  f"the tribology decides between them —")
            print("     the CONTACT GEOMETRY does, and that is an OPEN ⚖️ (the bore entry carries a radius whose")
            print("     value is unnamed, the EXIT — the coaxial station — has none specified at all, and the")
            print("     ratified protrusion decides which FEATURE of the tube meets the entry edge). So the wear")
            print("     verdict is gated on a decision of OURS, not on a number from a vendor. ⛔ k itself stays NOT MEASURED.")
            print("  🔑 The TIGHT end does not contain the contact force at all: with the area flow-limited,")
            print("     k = wall / (flow pressure × sliding distance) — the reaction cancels, so the shakiest input")
            print("     of the chain has no say in the binding half of the answer. ⚠️ And the sliding is a BRACKET:")
            print("     a rigid point contact slides zero; a compliant one rotates in contact up to the Ti-bore stop.")
            print(f"  → Branch discrimination: films stricter on the rigid-wall figures = {branch_discrimination['films_stricter_on_rigid_wall_figures']}, "
                  f"on the bounds = {branch_discrimination['films_stricter_on_bounds']} (DERIVED).")


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
          if not clears_all else "     Every alloy clears it bare, so the FATIGUE motive for support is "
                                 "spent — which is NOT news:")
    print("     it also carried them over the infinite-life line is what the two lists above answer."
          if not clears_all else
          "     ⚖️ 2026-09-11 retired that ground already. The ratified ground is WEAR — "
          + ("BOUNDED in §7." if binding_wear is not None else "NOT computed in this run (§7)."))
    # ⛔ DERIVED from §4, never typed.
    print(f"  4. CONTACT (§4, equilibrium): the shipped liner touches down at the EXIT on every swept µ on every geometry: "
          f"{shipped_forced_everywhere}; the mouth is never reached coaxially; the root stress lies in "
          + " / ".join(f"[{g['bracket_MPa_worst_mu'][0]:.2f}, {g['bracket_MPa_worst_mu'][1]:.1f}]" for g in supported_check["by_geometry"])
          + " MPa at worst µ (placeholder / lock window near / far) — rigid wall LOWER, Ti-bore stop or free cantilever UPPER, "
          "the contact compliance unmeasured; the §2 supported column overstates the rigid-wall end ×"
          + "/".join(f"{g['column_over_cap_nominal']:.1f}" for g in supported_check["by_geometry"]) + " at nominal µ and sits "
          + " / ".join(g["column_position_nominal_mu"] for g in supported_check["by_geometry"]) + ".")
    print("  5. The WELD SEAM (§5): the ×2 still belongs to the WIRE, and the JOINT is NOT priced — no break-even k is")
    print("     derived, because the root sees a fully-reversed coaxial cap OR a static mean from a channel offset,")
    print("     and the model has no mean-stress correction. The inputs a seam acceptance needs are in the cache:")
    for rl in root_loading:
        print(f"     {rl['geometry']:<28s} coaxial amplitude [{rl['coaxial']['amplitude_MPa_lower_rigid_wall']:.2f}, "
              f"{rl['coaxial']['amplitude_MPa_upper_end']:.1f}] MPa (mean 0) · offset mean "
              f"{rl['offset']['mean_MPa_per_um_past_play']:.3f} MPa/µm past the play, amplitude up to {rl['offset']['amplitude_MPa_max_over_swept_offsets']:.2f} MPa (rigid wall)")
    print("     ⛔ k itself stays NOT MEASURED — it comes from the vendor (00_07 HW.34).")
    print("  6. Per-alloy fatigue margin tracks yield (β-Ti/15Zr/4V > CP-Ti > Ta) — SAME ranking as the")
    print("     thermal bridge → the leading bake-off candidates (HW.24) win on both axes, no tension.")
    _r_flip = [r["endurance_over_yield"] for r in ratio_rows if not r["unsupported_infinite_life_for_all"]]
    print("  6b. THE ENDURANCE BAND (§5b) — the model runs at the MIDPOINT of an unmeasured band. «Bare rod: infinite")
    print(f"     life for every alloy» {'FLIPS' if _r_flip else 'holds'}"
          + (f" at ratio {', '.join(f'{r:.2f}' for r in _r_flip)}." if _r_flip else " across the whole band.")
          + " ⛔ Which end to stand on is a ⚖️ (00_07 HW.34); §5b measures, it does not choose.")
    # ⛔ DERIVED from §6, never typed. The point is not the width but WHERE the nominals sit: the
    # verdict every other section leans on («tight on the wire») is not produced by the drawing.
    _iw = interference_window
    print(f"  7. THE FIT (§6) — the interference the direction verdict asserts is now BOUNDED: "
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
    # ⛔ DERIVED from §7, never typed.
    if binding_wear is not None:
        _bw = min(binding_wear["by_duty_anchor"], key=lambda p: p["k_bound_edge_mm3_per_Nm"])
        print(f"  8. WEAR (§7) — the ratified ground is no longer unpriced. The shipped liner at its worst corner "
              f"({binding_wear['regime']} regime, {binding_wear['geometry']}, µ {binding_wear['mu']})")
        print(f"     keeps the wall whatever the contact compliance if k < {_bw['k_bound_edge_mm3_per_Nm']:.2e} mm³/(N·m) on the "
              f"material-bounded patch, k < {_bw['k_bound_conformal_mm3_per_Nm']:.2e} worn in")
        print(f"     (rigid-wall figures {_bw['k_rigid_wall_figure_edge_mm3_per_Nm']:.2e} / {_bw['k_rigid_wall_figure_conformal_mm3_per_Nm']:.2e} bound nothing) — "
              f"a {binding_wear['k_span_ratio']:.0f}× span decided by CONTACT GEOMETRY, our own open ⚖️.")
        print(f"     Films stricter than the liner: on the rigid-wall figures {branch_discrimination['films_stricter_on_rigid_wall_figures']}, "
              f"on the bounds {branch_discrimination['films_stricter_on_bounds']} — the wear axis discriminates the branches only "
              "against a rigid wall.")
        print("     ⛔ k stays NOT MEASURED; a tribo-test returns a verdict only together with the slip amplitude.")
    else:
        print("  8. WEAR (§7): NOT COMPUTED — the duty cache is absent and no cycle count is "
              "substituted (run script 62).")
    print("  9. Caveat: the cyclic-load amplitude (pogo friction + PEEK flex) is an ESTIMATE — the real")
    print("     sway spectrum is bench/field (00_02). Comparative supported-vs-unsupported is robust.")

    # ⛔ Built as ONE expression, never as a literal glued onto the verdict: adjacent string literals
    #    concatenate BEFORE a trailing conditional binds, so writing this inline would have emptied the
    #    whole verdict on the branch where the duty cache is missing — a defect visible only in the
    #    absent-cache run, i.e. exactly the one nobody executes.
    wear_verdict_sentence = (
        "WEAR is BOUNDED (wear_budget) at the EQUILIBRIUM stations since 2026-09-14 - the exit under coaxial drag, "
        "the mouth under a channel offset: the rate is not measured anywhere, so the block prices the BUDGET as a "
        "BOUND over the contact-compliance bracket (a rigid point contact slides zero, a compliant one rotates in "
        "contact up to the Ti-bore stop; the rigid-wall figures bound nothing), and the two ends are set by the "
        "CONTACT GEOMETRY - an open verdict of ours - not by tribology. "
        + ("The wear axis re-earns the rejection of the conformal branches against a RIGID wall only; on the bound "
           "it does not discriminate them, because the in-contact sliding scales with the polymer's own wall."
           if branch_discrimination and branch_discrimination["films_stricter_on_rigid_wall_figures"]
           and not branch_discrimination["films_stricter_on_bounds"] else
           "Branch discrimination on the wear axis: " + json.dumps({k: v for k, v in (branch_discrimination or {}).items() if k != "rows"}))
        if binding_wear is not None else
        "WEAR is NOT priced in this run: the duty cache is absent and no cycle count is substituted."
    )
    _ship_geo = [f"{g['geometry']} [{g['bracket_MPa_worst_mu'][0]:.2f}, {g['bracket_MPa_worst_mu'][1]:.1f}] MPa" for g in supported_check["by_geometry"]]

    out = {
        "method": "slender-beam closed form — Euler buckling (fixed-free) + cantilever tip-load bending "
                  "+ S-N endurance ratio (σ_e ≈ k·σ_y, as-printed derate) for the free-cantilever tables; "
                  "the contact blocks (§4-§7) solve the rod in the rigid channel as a unilateral-contact "
                  "equilibrium (lib.beam_contact, the solver script 68 shipped). No FEA beyond that beam element.",
        "geometry_mm": {"bus_dia": D_BUS, "free_len_unsupported": L_FREE_UNSUP, "free_len_supported": L_FREE_SUP,
                        "insertion_placeholder_mm": Z1_INSERTION_MM,
                        "note": "free_len_* are the PLACEHOLDER geometry's spans (Z1_INSERTION_MM = 30, an HW.8 "
                                "placeholder outside the Zone-1 lock window, 00_07 HW.26 G1); the §1-§3 tables stand on "
                                "them, the contact blocks are computed on every geometry in clearance_regime.geometries"},
        "loads": {"pogo_axial_N": F_POGO_N, "friction_mu": MU_CONTACT, "lateral_drag_N": MU_CONTACT * F_POGO_N},
        # ⚠️ `weld_seam_modelled: false` stood here until 2026-09-12 and four doc homes cited it.
        # It is replaced rather than flipped, because neither boolean is true any more: the seam's
        # GEOMETRY is still unmodelled while its SENSITIVITY now is. A flipped flag would have been
        # the half-fix that splits a surface into halves that disagree — the sub-block says both.
        # ⛔ Since 2026-09-14 the sensitivity half is the ROOT LOADING per regime, not a break-even k.
        "fatigue_model": {"endurance_over_yield": ENDURANCE_OVER_YIELD,
                          "as_printed_derate": AS_PRINTED_DERATE, "wrought_derate": WROUGHT_DERATE,
                          "shipped_branch": SHIPPED_BRANCH, "infinite_life_sf": INFINITE_LIFE_SF,
                          "weld_seam_geometry_modelled": False,
                          "weld_seam_sensitivity_modelled": True,
                          "weld_seam_break_even_k_derived": False,
                          "mean_stress_correction_modelled": False},
        "buckling": {"p_cr_unsupported_N": round(euler_buckling_N(L_FREE_UNSUP), 1),
                     "p_cr_supported_N": round(euler_buckling_N(L_FREE_SUP), 1),
                     "sf_unsupported": round(euler_buckling_N(L_FREE_UNSUP) / F_POGO_N, 1)},
        "bending_stress_MPa": {"unsupported": round(sig_unsup, 1), "supported": round(sig_sup, 1)},
        "per_alloy_fatigue": alloy_rows,
        "fabrication_branches": branch_summary,
        "friction_sweep": mu_rows,
        "clearance_regime": {
            "method": "unilateral contact of the clamped rod in a rigid frictionless channel, cubic Hermite "
                      "elements + active set (lib.beam_contact, one home with script 68); the drag acts at the "
                      "exit (the pad is the rod's own end face). Upper bounds on the wall/clamp account",
            "channel": {"dia_mm": D_CHANNEL_MM, "start_mm": CHANNEL_START_MM,
                        "length_mm": BORE_DEPTH_MM,
                        "drilled_depth_mm": BORE_DEPTH_MM,
                        "aspect_ratio_l_over_d": round(BORE_DEPTH_MM / D_CHANNEL_MM, 2),
                        "aspect_note": "L/D of the bore as machined (depth = shank + flange, read from "
                                       "cem/cathode_flange.json). It decides which operation the vendor "
                                       "needs and is the ratio quoted in canon prose - derived here so it "
                                       "moves with the diameter instead of being retyped",
                        "note": "the wall runs from the mouth to the EXIT on the pogo face — the full drilled "
                                "depth — because under the equilibrium the exit is the station the drag is reacted "
                                "at, and a run cut short (the shank only, as this key once read) would move it; "
                                "start_mm is the placeholder geometry's mouth"},
            "insertion_placeholder_mm": Z1_INSERTION_MM,
            "lock_insertion_window_mm": list(lock_insertion_window_mm()),
            "geometries": [g.__dict__ for g in GEOMETRIES],
            "branches": regimes,
            "by_geometry": by_geometry,
            "shipped_exit_contact_forced_on_every_mu_and_geometry": bool(shipped_forced_everywhere),
            "edge_bearing": {"reference_excess_past_play_um": excess_um, "rows": edge_rows,
                             "liner_start": liner_start, "exit_contact": exit_contact,
                             "note": "the mouth is a contact station only when the channel axis sits off the root "
                                     "axis by more than the play — swept, never measured; coaxially the drag contact "
                                     "is the exit. Geometric conditions only: no notch factor and no contact model "
                                     "exists in this tree. Input to the axial-extent and entry-radius verdicts and "
                                     "to the open coaxiality ⚖️ (00_07 HW.34)"},
            "play_reduction": play_reduction,
            "axial_thermal": axial_thermal,
            "supported_column_vs_equilibrium": supported_check,
        },
        "weld_seam": weld_seam,
        "endurance_ratio_band": {
            "question": "00_07 HW.34 — ENDURANCE_OVER_YIELD is a BAND written beside the constant "
                        "since this file was born, and only its MIDPOINT ever entered the model. "
                        "Every SF scales linearly with it, so a standing conclusion may be a "
                        "statement about one point wearing the clothes of a statement about the "
                        "band. This block sweeps it and reports INVARIANCE; it chooses no end",
            "band": list(ENDURANCE_RATIO_SWEEP),
            "model_runs_at": ENDURANCE_OVER_YIELD,
            "band_is_measured": False,
            "band_provenance": "the ends are the ones the constant's own comment has carried from "
                               "the first commit (wrought-Ti fatigue ratio ~0.4-0.5). They are NOT "
                               "measured for our alloys and are NOT a distribution - a bracket",
            "sweeps": "the §2 free-cantilever column on the placeholder span only; the seam column this block "
                      "carried until 2026-09-14 was priced on the retired drift-picture stress and no seam k "
                      "exists to sweep (weld_seam.break_even_k_not_derived_because)",
            "rows": ratio_rows,
            "bare_infinite_life_for_all_is_invariant": len(band_all_clear) == 1,
        },
        "interference_window": interference_window,
        "wear_budget": {
            "question": "00_07 HW.34 — ⚖️ 2026-09-11 made WEAR the ground the structural liner stands "
                        "on, and nothing in this tree computed it until 2026-09-12. This block bounds the rate the pair "
                        "may have and still keep the wall, so a tribo-test returns a verdict — at the "
                        "EQUILIBRIUM stations since 2026-09-14",
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
            "stations": {"coaxial": "the EXIT (the tube's flush end against the bore's exit edge), reaction = "
                                    "drag - touchdown drag, on every swept µ above touchdown",
                         "offset": "the MOUTH (the bore's entry edge against the tube's flank) when the channel "
                                   "axis is off the root axis by more than the play; the reversing drag rotates "
                                   "the rod about it. SWEPT offsets, never measured"},
            "coaxial_sliding_bracket": "against a RIGID wall the touched-down shape does not rotate with the drag, so a "
                                       "rigid point contact slides ZERO from bending kinematics and the 4·r·θ_rigid "
                                       "rotation between the ±wall states happens OUT of contact (it bounds nothing; kept "
                                       "as the rigid-wall figure). Against the real polymer wall the exit yields by R/k and "
                                       "the rod rotates IN contact, up to the Ti-bore stop (the polymer wall fully yielded) "
                                       "— the UPPER end of the sliding, 6·r·t/L per cycle where the drag reaches the bore. "
                                       "The bound below takes that upper sliding with the upper (rigid-wall) reaction; the "
                                       "contact compliance that places the real pair in the bracket is measured nowhere, "
                                       "and at the rigid end the driver is a normal load cycling 0 <-> R with a landing "
                                       "(partial slip / impact fretting, a mode nothing here models)",
            "branch_discrimination": branch_discrimination,
            "second_interface_not_priced": "at the FLOOR of the interference window §6 shows the tube "
                                           "slips on the WIRE instead, which puts a second sliding "
                                           "pair inside the same part. Nothing specifies which of the "
                                           "two ships, and this block prices only the ratified one",
            "duty_source": str(WIND_CACHE.relative_to(REPO_ROOT)) if wind else None,
            "duty_anchors": duty_anchors,
            "duty_note": ("cycle counts are LOADED from script 62 (ten years of real NASA POWER wind "
                          "for Cherkasy, times a bracket of two field sway-frequency readings), never "
                          "retyped. Script 62's own verdict is that neither closes to a single number, so "
                          "the anchors are a bracket and its ceiling is "
                          + (wind["budget_basis"] if wind else "NOT COMPUTED")),
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
                                                 "weakest input of the chain has no say in the binding "
                                                 "half of the answer. It survives only in the worn-in "
                                                 "end, through the projected area. Pinned in-run against "
                                                 "the closed form, not merely described",
            "not_modelled": {
                "contact_compliance": "the wall is rigid and frictionless; the reaction is the equilibrium's, "
                                      "not a distributed pressure - and see coaxial_slip_is_a_ceiling for what "
                                      "that does to the sliding distance",
                "slip_regime": "Archard assumes GROSS slip. The slip amplitudes here sit in the range "
                               "where a real pair may be in partial slip instead, which wears far "
                               "less and damages by fretting FATIGUE rather than by removal. The "
                               "regime boundary is not in this tree, so the gross-slip reading is "
                               "taken - the conservative one for a wear budget, and the wrong one for "
                               "predicting the failure MODE",
                "third_body": "PEEK debris trapped in a 25 um clearance is neither evacuated nor "
                              "modelled; it can either bed the contact in (less wear) or turn the "
                              "pair abrasive (much more)",
                "titanium_side": "only the polymer is priced. The bore also wears, and at both stations "
                                 "it is a bore EDGE doing the cutting - the entry edge (radius unnamed) and "
                                 "the exit edge (nothing specified)",
                "temperature_and_creep": "k, the PEEK yield that bounds the contact area, and the "
                                         "modulus are all 23 C datasheet values; none is swept over "
                                         "the -30..+40 C service band, and creep flattens the contact "
                                         "over 20 yr in a direction this bound does not follow",
                "amplitude_coupling": "slip and reaction both scale with the drag, so a real sway "
                                      "SPECTRUM (not a single amplitude) would redistribute the duty; "
                                      "the load spectrum is bench/field, 00_02",
                "offset": "the channel offset is swept, never measured; the offset-regime rows are priced "
                          "at the swept points only",
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
            "note": "radial_play answers ASSEMBLY, the coaxial cap and touchdown answer SUPPORT — different "
                    "questions, same row. Geometry does not discriminate (б)/(в)/(г): all three "
                    "land 25 µm radial. The discriminating costs are NOT computed here — wear "
                    "allowance (б), re-spec of the primary datum (в), fatigue σ ∝ 1/d³ (г).",
        },
        "verdict": (f"Monolithic bus at the canon rod O{D_BUS:.1f} (01_01 1.4), SHIPPED fabrication = "
                    f"{SHIPPED_BRANCH} (welded cold-drawn wire, ratified 2026-09-10): buckling non-issue "
                    f"(SF {p_cr_unsup / F_POGO_N:.0f}x); the bore liner doubles as lateral support -> "
                    f"fatigue SF {sup_lo:.1f}-{sup_hi:.1f}x (infinite life, all alloys) on the 6 mm supported "
                    f"idealisation, which OVERSTATES the coaxial equilibrium root stress. BARE, the drawn "
                    f"wire reaches infinite life for {len(shipped['unsupported_infinite_life'])} of "
                    f"{len(alloy_rows)} alloys (SF {uns_lo:.1f}-{uns_hi:.1f}x, placeholder span); "
                    # ⛔ DERIVED from branch_summary, never typed: this sentence read «NOT over the SF-2 line.
                    #    On the superseded PRINTED branch not one of the six cleared it» for a whole day after
                    #    the L_FREE_UNSUP=36 inputs were retired — the printed report was derived, the cache
                    #    verdict was prose, and only the cache is what docs quote.
                    + (f"short of the SF-2 line: {', '.join(marginal)}; " if marginal
                       else "none is left short of the SF-2 line; ")
                    + (f"predicted failure: {', '.join(failing)}. " if failing
                       else "none is predicted to fail. ")
                    + "".join(f"On the superseded {b.upper()} branch "
                              f"{len(branch_summary[b]['unsupported_infinite_life'])} of {len(alloy_rows)} "
                              "reach infinite life bare"
                              + (f" ({', '.join(branch_summary[b]['unsupported_marginal'])} short of the "
                                 "SF-2 line)" if branch_summary[b]["unsupported_marginal"] else "")
                              + (f", predicted failure: {', '.join(branch_summary[b]['unsupported_predicted_failure'])}"
                                 if branch_summary[b]["unsupported_predicted_failure"] else "")
                              + ". "
                              for b, _ in FAB_BRANCHES if b != SHIPPED_BRANCH)
                    + "BUT the fatigue ground for the liner is RETIRED, not narrowed (verdict 2026-09-11), and "
                    "since 2026-09-14 the contact is an EQUILIBRIUM, not a free-shape reading: on a coaxial channel "
                    f"the shipped liner touches down at the EXIT on every swept µ on every geometry ({shipped_forced_everywhere}), "
                    "the mouth is never reached, and the root stress at worst µ lies in " + " / ".join(_ship_geo)
                    + " (rigid wall = LOWER end, Ti-bore stop or free cantilever = UPPER end, bonded, zero-interference "
                    "play; the contact compliance that places it is measured nowhere); "
                    + "; ".join(f"{g['geometry']}: forced {', '.join(g['forced_on_every_mu_branches']) or 'none'}, "
                                f"partly {', '.join(g['partly_branches']) or 'none'}, free {', '.join(g['free_on_every_mu_branches']) or 'none'}"
                                for g in by_geometry)
                    + ". A channel off the root axis by more than the play makes the MOUTH a contact station and puts a "
                    "static MEAN on the root (swept, never measured). What the liner carries is WEAR - the exit contact is "
                    "geometrically forced on every swept µ, and wear-through is a ~0.5 V anode-cathode short. Liner = "
                    "insulation + wear surface + lateral support; NOT a fatigue fix (HW.34 sub-2). The seam is NOT priced: "
                    "no break-even k (weld_seam.break_even_k_not_derived_because). Per-alloy margin tracks yield = same "
                    "ranking as thermal -> leading HW.24 candidates win on both. " + wear_verdict_sentence),
        "caveats": "cyclic-load amplitude (pogo friction + PEEK flex) is an estimate; real sway spectrum "
                   "is bench/field (00_02). Comparative supported-vs-unsupported + per-alloy ranking robust. "
                   "GEOMETRY: the unsupported PEEK gap comes from Z1_INSERTION_MM = 30, an HW.8 placeholder outside "
                   "the Zone-1 lock window (00_07 HW.26 G1); the contact blocks carry the placeholder AND both "
                   "window ends, the §1-§3 tables the placeholder only. "
                   "CONTACT: rigid frictionless wall, perfect clamp, small deflection. The SIGN of the rigid-wall figure "
                   "differs by regime: under coaxial drag it is the LOWER end of the root stress (a compliant polymer wall "
                   "raises the root moment by 3EI·(R/k)/L², the Ti-bore stop or free cantilever is the upper end), under a "
                   "channel offset it is an UPPER bound (a compliant mouth relieves a displacement-driven load); the "
                   "contact compliance is measured nowhere, and the channel offset, tilt and the fit's play are SWEPT. "
                   "WELD SEAM: its geometry is still NOT modelled (homogeneous cantilever), and the wrought "
                   "derate still describes the WIRE, not the JOINT. No break-even knockdown k is derived (the root "
                   "sees a fully-reversed coaxial cap OR a static mean from an offset, and no mean-stress "
                   "correction exists here); what IS given is the root amplitude and mean per regime and geometry "
                   "(weld_seam.root_section_loading). k itself is NOT MEASURED and is not assumed here. "
                   "THE FIT: the liner-wire interference the direction verdict asserts is BOUNDED since "
                   "2026-09-12 (interference_window), and its two vendor bands stay NOT MEASURED. The "
                   "headline is not the width but the nominal: the tube's bore nominal is SPECIFIED NOWHERE "
                   "('ID 1.00' lives only in an open RFQ leg), so the ratified 'tight on the wire' is not a "
                   "tolerance outcome yet, and landing in the window needs a nominal interference - a verdict, "
                   "not a tolerance. "
                   "Creep is modelled NOWHERE, so the real window is narrower on BOTH sides. "
                   "WEAR: the specific wear rate stays NOT MEASURED; what is computed is the BUDGET at the "
                   "equilibrium stations (exit under coaxial drag, mouth under an offset) as a BOUND over the "
                   "contact-compliance bracket, its span set by the contact AREA bracketed between a flow-pressure "
                   "bound and the full projected run. The coaxial in-contact sliding lies in [0 (rigid wall), the "
                   "rotation to the Ti-bore stop]; the rigid-wall rotation figure bounds nothing, and against a rigid "
                   "wall the driver is the reversing normal load. On the bound the wear axis does NOT discriminate the "
                   "shipped liner from a conformal film (branch_discrimination). Archard assumes GROSS slip - at these "
                   "amplitudes a real pair may be in partial slip, "
                   "which removes less material and fails by fretting FATIGUE instead, a mode nothing here models. "
                   "Third-body debris, the titanium side of the pair and the whole -30..+40 C dependence are "
                   "outside the bound. Three seam mechanisms stay outside any bound, and their signs differ: bead "
                   "section RELIEVES nominal stress, weld-toe notch AGGRAVATES it, and weld residual TENSION is a "
                   "mean stress this file never carries.",
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
