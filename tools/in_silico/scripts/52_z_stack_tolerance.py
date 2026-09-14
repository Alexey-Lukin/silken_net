#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.8.7 — Axial Z-stack tolerance analysis (3-spring) for the Soldier capsule ↔ anchor blind-mate.

The bayonet-closed Z-loop (Radome ↔ Zone 3) compresses THREE compliant elements simultaneously:
  1. Pogo pins  (Mill-Max 0908, 1.52 mm travel)        — 50-70 % mid-stroke window (02_02 §2.2/§3.5)
  2. O-ring     (EPDM, CS 1.78 mm)                      — 15-30 % static squeeze (industry practice, NOT
                                                          Parker — Parker's face-seal window is 19-32 %; see ORING_WIN)
  3. Sil-Pad    (Bergquist 1500ST, ~1 mm, HW.30)        — acoustic-coupling contact, 20 yr creep

🔑 Pogo + Sil-Pad are PARALLEL springs on the SAME gap (Power Deck ↔ Zone 3) → one gap sets both
compressions. The O-ring is on its OWN chain: ⚖️ 2026-09-10 (00_07 HW.33, branch (а), applied in CAD
2026-09-14) put the single groove in the flange top face against a FLAT radome rim, so the rim is a hard
datum on that face and the squeeze is set by ONE machined dimension — the groove depth — not by where the
bayonet seats the rim. `TOL_OR` therefore has one contributor and neither the spacer nor the bayonet
hard-stop touches it. 02_02 §3.5 models only pogo+O-ring; the acoustic pad is the missing 3rd spring
(this script closes that gap).

DMLS Ti ±0.3 mm dominates the budget; raw RSS exceeds the (narrow) windows → a robot-selected 0.1 mm
spacer (off the measured DMLS+PCB stack) is the mitigation. RF antenna Z-clearance is enforced here as
a GEOMETRIC constraint at OUR 12 mm working floor (02_01 §5.3 itself asks ≥ 8 mm, 10-15 desirable — see
RF_ANT_TI_CLEARANCE_MIN); the VNA/HFSS validation is lab-side
(Гончаров, 00_02 §1.2 — currently unresponsive, so the geometry is self-owned, not blocked on him).

1D linear tolerance chain — closed-form RSS + worst-case, no FEA / numpy.

A second question rides the same axis and is answered in the gland section: the ⚖️ of 2026-09-10 fixed
the O-ring squeeze and therefore the groove DEPTH, but an O-ring displaces a fixed cross-section area,
so the depth implies a WIDTH — and the width has to live inside the flat face that closes on it. That
face is the bottom annulus of the PEEK dome wall, i.e. its width IS the wall thickness, and the three
MATE-Ø candidates disagree on whether it exists at all. The section also derives the depth-tolerance
BUDGET (the input the open ⚖️ lacks) and settles, by inversion, whether a PEEK rim may be treated as a
rigid datum for twenty years. Geometry is read from `tools/cad/cem/*.json` at RUNTIME — the two machine
halves share no identifier vocabulary, so a mirrored dimension is findable only by grepping its value.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT, SLM_MIN_WALL_DEFAULT_MM
from lib.utils import banner  # import-safe now (openmm is lazy in pick_platform)

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)


# ── Spring specs (canon) ──
POGO_TRAVEL = 1.52   # mm — Mill-Max 0908/0909 full travel (02_02 §2.2)
PAD_FREE = 1.0       # mm — Bergquist Sil-Pad 1500ST free thickness (02_01 §6, HW.30; range 0.5-1.0)
ORING_CS = 1.78      # mm — EPDM O-ring cross-section (02_02 §3.2)

# ── Working windows (fraction) ──
POGO_WIN = (0.50, 0.70)   # Mill-Max mid-stroke (02_02 §3.5)
ORING_WIN = (0.15, 0.30)  # industry practice for static seals, centre 20 % (02_02 §3.5).
# ⚠️ NOT Parker: that attribution was withdrawn 2026-09-10. The applicable Parker table is settled now —
# ⚖️ founder 2026-09-10 put the single O-ring on the flange TOP face against the radome rim, i.e. a FACE
# seal, so Parker ORD 5700 Chart 4-3 for W .070" applies and its window is TIGHTER at the bottom.
ORING_WIN_PARKER_FACE = (0.19, 0.32)  # Parker ORD 5700 Chart 4-3, face seal, W .070" (00_07 HW.33)
PAD_WIN = (0.20, 0.50)    # gap filler: acoustic-contact-min .. squeeze-out-max (Sil-Pad tolerates wide squeeze)
PAD_CREEP_RETAIN = 0.85   # compression fraction retained after 20 yr (HW.30 lifecycle estimate)
PAD_ACOUSTIC_MIN = 0.20   # post-creep floor for acoustic contact (pad_pct·creep must stay ≥ this)

# ── Gland geometry inputs (HW.33 branch (а), ⚖️ 2026-09-10; APPLIED in CAD 2026-09-14) ──
# The squeeze verdict fixes the groove DEPTH. Depth alone does not make a gland: an O-ring displaces a
# fixed cross-section area, so the WIDTH follows from the depth, and the width has to live inside the
# face that closes on it — the seal land of the radome's rim boss since 2026-09-14.
ORING_SQUEEZE_RATIFIED = 0.245   # ⚖️ founder-proxy 2026-09-10 — centre of the 19-30 % intersection
# Gland fill = O-ring section area / groove section area. A gland filled to 100 % has nowhere to put the
# elastomer it displaces, so the ring extrudes or the faces are held apart. ⚠️ 00_06 §0: the ceiling
# below is CITED industry practice (Parker's own design rule is a groove ~25 % larger than the ring,
# i.e. ~80 % fill), NOT a computed physical fact — the verdict here is deliberately reported against all
# three so it does not rest on the choice. ⚖️ WHICH fill the part is cut to is an OPEN verdict (00_07
# HW.33): the CAD designs to the 80 % rule until then, and that choice is read back off the manifests.
GLAND_FILL_CEILINGS = (0.80, 0.85, 0.90)
GLAND_FILL_DESIGN_TO = 0.80

# ── Nominal gaps — design targets, centered (pogo 60 %, pad 35 %, O-ring at the RATIFIED 24.5 %) ──
GAP_PZ = 0.65                              # mm — Power Deck ↔ Zone 3 (sets pogo + pad)
POGO_FREE = GAP_PZ + 0.60 * POGO_TRAVEL    # protrusion so pogo sits at 60 % at nominal gap
# The O-ring "gap" IS the flange groove depth: under branch (а) the flat radome rim lands on the flange
# top face (hard datum), so the ring is squeezed from CS 1.78 to exactly the machined depth. This READ
# `ORING_CS * (1.0 - 0.20)` = 1.424 — the 20 % nominal the bayonet used to seat the rim at — until the
# verdict was applied; the pre-verdict figure is kept below as `GAP_OR_PRE_BRANCH_A` for the record only.
# 🔗 C#↔Python crossing, EXPLICIT: the CAD derives the same depth from the `o_ring` block of
# cem/cathode_flange.json (CathodeFlangeCem.ORing.DepthMm); `applied_gland()` reads that block and refuses
# to run if it disagrees with these constants, and RadomeTests pins the C# side against this cache.
GAP_OR = ORING_CS * (1.0 - ORING_SQUEEZE_RATIFIED)
GAP_OR_PRE_BRANCH_A = ORING_CS * (1.0 - 0.20)   # the 20 % chain before ⚖️ 2026-09-10 — history, not an input

# ── RF constraint (02_01 §5.3) — geometric, self-owned (Гончаров VNA pending) ──
# ⛔ This 12 is OURS, not canon's — do NOT "correct" a measured 8.0 upward to meet it, and do not
# quote it as a requirement. 02_01 §5.3's normative table asks for >= 8 mm (10-15 desirable), grounds
# it on lambda/40 = 8.6, and makes HFSS mandatory below 10. Its only 12 is the OUTCOME of a proposed
# two-deck board stack, i.e. a design point mirrored here as a floor. The same mirror sits in the
# other machine half (tools/cad Cem.RfClearanceMinMm). Which number is the acceptance floor is an
# open verdict (00_07 HW.33); the measurement that settles it is the UNI.10 VNA sweep of 5/8/12.
# Rule this violates, and it is ours: skill in-silico #9 — if canon gives a RANGE, say which END you
# took; if the number is not an end, say what it IS and whose. [2026-09-11]
RF_ANT_TI_CLEARANCE_MIN = 12.0   # mm — antenna <-> Ti flange Z-clearance, OUR working floor

# The stress level below which 20-yr PEEK stress-relaxation is not worth a model. Anchored INSIDE our
# own canon rather than on an outside datasheet: 01_01 §4.3 tabulates PEEK relaxation on the press-fit
# joint at 25-30 MPa contact pressure, so a tenth of that — of its LOWER end, the conservative reading —
# is the floor for "negligible". ⛔ 10.0 stood here under this same sentence: a THIRD of the table, and
# the table's own 20-yr column still relaxes at ~8-12 MPa, i.e. that floor sat inside the regime it
# was meant to stay below.
PEEK_RELAX_REGIME_MPA = 2.5
POGO_SPRING_FORCE_N = 0.96       # N per pin at FULL travel (02_02 §2.2) — an upper bound at 50-70 %
POGO_PIN_COUNT = 2               # centre (GND) + outer ring (V+), 02_02 §1.2

# ── Board budget inputs handed to HW.9 (00_07 HW.33 leg, 2026-09-14) ──
# Canon rows, each named beside its number; nothing about the board LAYOUT is typed, because the layout
# does not exist yet — what is computed is the envelope a layout must fit.
CROWN_EDGE_R_RATIFIED_MM = 5.0   # ⚖️ founder 2026-09-11 (00_07 HW.33): a flat crown with an R5 edge round
#                                  replaces the full hemisphere, rise = R (a quarter round). Canon floor R ≥ 5
#                                  (01_04 §5.5). NOT applied in CAD — `radome.json` carries no crown field yet.
FR4_THICKNESS_MM = 1.6           # 02_01 §3.1 BOM pos. 8 — «FR4, 4 шари, 1.6 мм», both decks
FR4_THICKNESS_UNSOURCED_MM = 1.0 # what the 2026-09-11 vertical budget used; no home anywhere — a contrast row
B2B_STACK_MM = (8.0, 10.0)       # 02_01 §3.1 BOM pos. 12 — Samtec FTSH/CLT board-to-board stack height 8–10
B2B_STACK_ALT_MM = 6.0           # the same row's named alternative (Hirose DF40, 6 mm stack) — priced, not chosen
# The three live piezo candidates with the heights 02_01 §6 quotes for them (vendor figures, not re-verified
# here). Canon mounts the piezo on the UNDERSIDE of the Power Deck, inside the gap `GAP_PZ` models.
PIEZO_HEIGHT_MM = {"Mallory AST1240MLTRQ": 3.3, "Mallory AST1109MLTRQ": 2.0, "Murata PKMCS0909E4000-R1": 1.9}
# The tallest part named in the BOM for the RF deck: Seeed LoRa-E5 module (02_01 §3.1 pos. 1), 12×12×2.5 mm per
# https://wiki.seeedstudio.com/LoRa-E5_STM32WLE5JC_Module/ (read 2026-09-14). WHICH SIDE of the RF deck it
# rides is a layout choice (HW.9), so the budget TESTS the top side instead of assuming it.
RF_DECK_TALLEST_BOM_PART_MM = 2.5
RF_Z_CANON_FLOOR_MM = 8.0        # 02_01 §5.3 normative row «≥ 8» (λ/40 = 8.6 in the same row)
RF_Z_HFSS_TRIGGER_MM = 10.0      # 02_01 §5.3, same row: HFSS mandatory below 10

# CEM manifests are the parameter SSOT of the shipped geometry (canon-gated by scripts/cem_canon_sync.rb).
# Read at RUNTIME, never mirrored as literals here: the CAD and in-silico halves share no identifier
# vocabulary, so a hand-copied dimension can only ever be found by grepping the VALUE.
CEM_DIR = REPO_ROOT / "tools" / "cad" / "cem"


def cem(stem: str) -> dict:
    return json.loads((CEM_DIR / f"{stem}.json").read_text(encoding="utf-8"))

# ── Tolerance contributors (± half-width, mm) ──
# Shared Power↔Zone3 gap: DMLS Ti flange + both FR4 decks + B2B stack + CNC radome engagement.
TOL_PZ = {"DMLS_Ti": 0.30, "FR4_power": 0.20, "B2B_stack": 0.15, "FR4_rf": 0.20, "CNC_radome": 0.10}
# O-ring chain: ONE machined dimension — the flange groove depth (branch (а): the flat rim is a hard datum
# on the flange face, so the DMLS seat and the CNC rim engagement that used to be the two contributors here
# are no longer in the chain at all; that pair RSS'd to ±0.18 = 1.84× the budget and never fitted).
# ⛔ The 0.05 is NOT a specification: it is the value the shop is being ASKED whether it holds (00_07 HW.33 👤,
# 02_02 §3.5 «рутинні ±0.05») — a placeholder for a vendor answer, and the verdict below is conditional on it.
# The FLATNESS of the two mating faces (flange top face · radome rim) belongs in this chain too and is in
# no canon: it is a named missing datum (depth_tolerance_budget), and the RSS leftover is what it may spend.
DEPTH_TOL_ASKED = 0.05
TOL_OR = {"machined_groove_depth": DEPTH_TOL_ASKED}
TOL_OR_PRE_BRANCH_A = {"DMLS_Ti_seat": 0.15, "CNC_radome_rim": 0.10}   # the retired two-contributor pair — history
# A selective 0.1 mm spacer removes the MEASURED rigid stack (DMLS+PCB+B2B), leaving only the CNC PEEK
# engagement + the spacer half-step as residual (see residual() in main). It acts on the SHARED gap only.
SPACER_STEP = 0.10   # mm — eccentric spacer increment (02_02 §3.5); residual ±half-step


def rss(tols: list[float]) -> float:
    return math.sqrt(sum(t * t for t in tols))


def pct(gap: float, free: float, ref: float) -> float:
    """Compression fraction = (free − gap) / ref."""
    return (free - gap) / ref


def windows_at(d_pz: float, d_or: float) -> dict:
    """Three compression %s when the shared gap shifts by d_pz and the O-ring gap by d_or."""
    return {
        "pogo": pct(GAP_PZ + d_pz, POGO_FREE, POGO_TRAVEL),
        "pad": pct(GAP_PZ + d_pz, PAD_FREE, PAD_FREE),
        "oring": pct(GAP_OR + d_or, ORING_CS, ORING_CS),
    }


def in_win(val: float, win: tuple[float, float]) -> bool:
    return win[0] <= val <= win[1]


def assess(label: str, d_pz: float, d_or: float) -> dict:
    w = windows_at(d_pz, d_or)
    pad_creep = w["pad"] * PAD_CREEP_RETAIN
    ok = (in_win(w["pogo"], POGO_WIN) and in_win(w["oring"], ORING_WIN)
          and in_win(w["pad"], PAD_WIN) and pad_creep >= PAD_ACOUSTIC_MIN)
    return {"label": label, "d_pz": d_pz, "d_or": d_or,
            "pogo_pct": w["pogo"], "pad_pct": w["pad"], "pad_pct_20yr": pad_creep,
            "oring_pct": w["oring"], "pass": ok}


def ring_area_mm2(cs: float) -> float:
    """Cross-section area an O-ring of cord diameter `cs` must be given room for."""
    return math.pi / 4.0 * cs * cs


def gland_width_required(cs: float, depth: float, fill: float) -> float:
    """Groove width whose section area holds the ring at no more than `fill` of the gland."""
    return ring_area_mm2(cs) / (fill * depth)


def seal_faces() -> dict:
    """Where a FACE seal can physically live, per MATE-Ø candidate — read off the shipped geometry.

    ⚖️ 2026-09-10 put one O-ring on the flange TOP face, closed by the radome rim. That rim is the
    bottom annulus of the dome wall, so its width IS the wall thickness — and the three MATE-Ø
    candidates do not merely resize it, they disagree on whether it exists at all.
    """
    flange, radome = cem("cathode_flange"), cem("radome")
    flange_r = flange["flange_diameter_mm"] / 2.0
    dome_r = radome["dome_diameter_mm"] / 2.0
    rim_in = dome_r - radome["wall_thickness_mm"]

    # `skirt` opens the lower cavity out to flange_r + 0.3 and wraps a ring to (lug tip + clearance).
    # Both offsets are bare literals in Assembly.ApplyEnclosingSkirt / Cem.SkirtClearanceMm — no CEM
    # field owns them, so they are mirrored here with that provenance named rather than silently.
    skirt_bore_r = flange_r + 0.3
    skirt_outer_r = flange_r + flange["lug_protrusion_mm"] + 0.5

    return {
        "flange_top_face_outer_r_mm": flange_r,
        "asis": {"rim_r_mm": [rim_in, dome_r], "land_mm": dome_r - rim_in,
                 "note": "dome wall bottom butts the flange top face; land = wall thickness"},
        "inboard": {"rim_r_mm": [rim_in, dome_r], "land_mm": dome_r - rim_in,
                    "note": "only the lug protrusion is clamped — the rim is the asis rim, unchanged"},
        "skirt": {"rim_r_mm": None, "land_mm": 0.0,
                  "radial_clearance_mm": skirt_bore_r - flange_r,
                  "skirt_ring_r_mm": [skirt_bore_r, skirt_outer_r],
                  "note": f"the lower cavity is CUT AWAY to r={skirt_bore_r:.1f} to admit the "
                          f"Ø{flange['flange_diameter_mm']:.0f} disc, so no radome material stands over "
                          f"the flange top face — a FACE seal has no mating face here at all, and the "
                          f"surviving interface is the {skirt_bore_r - flange_r:.1f} mm RADIAL clearance "
                          f"between the skirt bore and the flange rim"},
    }


def gland_verdict() -> dict:
    """Does the ratified single-groove face seal FIT the face that has to close on it?"""
    depth = ORING_CS * (1.0 - ORING_SQUEEZE_RATIFIED)
    faces = seal_faces()
    required = {f"{int(f * 100)}%": gland_width_required(ORING_CS, depth, f) for f in GLAND_FILL_CEILINGS}
    widest_ok = min(required.values())          # the most permissive fill ceiling
    candidates = {}
    for name in ("asis", "inboard", "skirt"):
        land = faces[name]["land_mm"]
        candidates[name] = {
            "land_mm": round(land, 3),
            "residual_after_groove_mm": round(land - widest_ok, 3),
            "face_seal_possible": bool(land - widest_ok > 0.0),
        }
    # Smaller standard cords, in case the verdict is "the cord is too fat for this wall".
    alt = {}
    for cs in (1.42, 1.27, 1.02):
        d = cs * (1.0 - ORING_SQUEEZE_RATIFIED)
        w = gland_width_required(cs, d, 0.85)
        alt[f"CS {cs}"] = {"depth_mm": round(d, 3), "width_at_85pct_mm": round(w, 3),
                           "land_left_on_asis_rim_mm": round(faces["asis"]["land_mm"] - w, 3)}
    return {"depth_mm": round(depth, 4), "ring_area_mm2": round(ring_area_mm2(ORING_CS), 4),
            "required_width_mm": {k: round(v, 3) for k, v in required.items()},
            "faces": faces, "candidates": candidates, "smaller_cord_options": alt}


def rim_boss_radial_budget() -> dict:
    """What the ratified rim BOSS leaves for the PCB — and it is a CEILING, not a nominal.

    ⚖️ 2026-09-10 (00_07 HW.33) put the bayonet socket and the seal land on ONE local inward boss,
    radially one after the other. Its named price was «the rim cavity becomes ≈Ø15–16 against Ø21
    today», and that range is what this derives — every term from the CEM or from the gland function
    above, none typed:

        cavity ≤ dome_Ø − 2·( socket_band + gland_width(cs, fill) + 2·slot_clearance )
        socket_band = lug_radius + slot_clearance   (the entry slot must clear the lug)

    🔴 **All three terms are MINIMA, so the result is an upper bound on the cavity, with ZERO
    tolerance allowance in it.** Reading it as a nominal to design a board against is the error this
    function exists to prevent: any growth in any term eats the board. The boss IS cut in CAD since
    2026-09-14 at exactly these minima (`applied_gland`), so nothing has grown — yet. HW.9 designs
    against the WORST row, not the friendliest (⚖️ 2026-09-14: the ceiling is its INPUT, not a gate).
    ⊕ It also prices the levers, which is the half a single number hides: raising the gland fill
    ceiling and thinning the cord both widen the cavity WITHOUT touching the Ø25 freeze — and the
    freeze is the most expensive move available, not the first one.
    """
    radome = cem("radome")
    dome_d = radome["dome_diameter_mm"]
    slot_clear = radome["slot_clearance_mm"]
    socket_band = radome["lug_radius_mm"] + slot_clear      # entry slot must clear the lug
    misalign = 2.0 * slot_clear                              # radial socket misalignment allowance

    rows = []
    for cs in (ORING_CS, 1.42, 1.27):
        depth = cs * (1.0 - ORING_SQUEEZE_RATIFIED)
        for fill in GLAND_FILL_CEILINGS:
            seal_band = gland_width_required(cs, depth, fill) + misalign
            boss = socket_band + seal_band
            rows.append({"cord_cs_mm": cs, "gland_fill": fill,
                         "gland_width_mm": round(gland_width_required(cs, depth, fill), 3),
                         "seal_band_mm": round(seal_band, 3), "boss_radial_mm": round(boss, 3),
                         "cavity_ceiling_mm": round(dome_d - 2.0 * boss, 2),
                         "shipped_cord": bool(abs(cs - ORING_CS) < 1e-9)})
    shipped = [r for r in rows if r["shipped_cord"]]
    worst = min(shipped, key=lambda r: r["cavity_ceiling_mm"])
    best = max(shipped, key=lambda r: r["cavity_ceiling_mm"])
    # Cheapest lever that does NOT touch the Ø25 freeze: keep the fill, thin the cord.
    same_fill = [r for r in rows if abs(r["gland_fill"] - worst["gland_fill"]) < 1e-9]
    cord_lever = max(same_fill, key=lambda r: r["cavity_ceiling_mm"])
    return {
        "inputs_mm": {"dome_dia": dome_d, "slot_clearance": slot_clear,
                      "socket_band": round(socket_band, 3), "misalignment_allowance": misalign},
        "cavity_today_mm": round(dome_d - 2.0 * radome["wall_thickness_mm"], 2),
        "rows": rows,
        "shipped_cord_range_mm": [worst["cavity_ceiling_mm"], best["cavity_ceiling_mm"]],
        "design_to_mm": worst["cavity_ceiling_mm"],
        "levers_that_keep_the_od_freeze": {
            "raise_gland_fill": {"from_pct": int(worst["gland_fill"] * 100),
                                 "to_pct": int(best["gland_fill"] * 100),
                                 "buys_mm": round(best["cavity_ceiling_mm"] - worst["cavity_ceiling_mm"], 2)},
            "thin_the_cord": {"from_cs": ORING_CS, "to_cs": cord_lever["cord_cs_mm"],
                              "at_fill_pct": int(worst["gland_fill"] * 100),
                              "buys_mm": round(cord_lever["cavity_ceiling_mm"] - worst["cavity_ceiling_mm"], 2),
                              "price": "moves the SSOT cross-section 02_02 §3.2"},
        },
        "ceiling": "⛔ every term is a MINIMUM, so this is an upper bound with no tolerance in it; "
                   "the boss is cut in CAD at exactly these minima (2026-09-14), so nothing has grown yet. Diameter is ONE of three gates — "
                   "the internal HEIGHT above the flange face (not cavity_height_mm alone: the inner cap adds "
                   "its radius, 00_07 HW.33) and the antenna↔Ti clearance are separate and are NOT judged here.",
    }


def applied_gland() -> dict:
    """The gland as the CAD cuts it since 2026-09-14 (branch (а) APPLIED) — re-derived here from both manifests
    by the SAME chain as the C# (CathodeFlange.ORingGroove* / Radome.SealLand* / Radome.SocketPocket*).

    🔗 The C#↔Python crossing, explicit and pinned in BOTH directions: the manifests carry the gland spec as an
    `o_ring` block (cord · squeeze · fill) that this function reads and REFUSES if it disagrees with this
    script's constants; RadomeTests reads this section back and asserts the C# derivation equals it. Every
    number below is therefore a mirror with a witness on each side, never a retyped literal.

    The retired counter-groove pair this function replaced (flange 0.9 at r 9-11 · radome 0.9 at r 10.5-11.5:
    0.50 mm of radial overlap, 75 % of the flange groove under the dome cavity, −1.1 % squeeze) is gone from
    both manifests; the record of WHY the boss exists is `gland_verdict()` (the 2.0 mm wall could not close it).
    """
    flange, radome = cem("cathode_flange"), cem("radome")
    for part, doc in (("cathode_flange", flange), ("radome", radome)):
        o = doc["o_ring"]
        mismatch = {k: (o[k], v) for k, v in (("cs_mm", ORING_CS), ("squeeze", ORING_SQUEEZE_RATIFIED),
                                              ("gland_fill", GLAND_FILL_DESIGN_TO)) if abs(o[k] - v) > 1e-9}
        if mismatch:
            raise SystemExit(f"cem/{part}.json `o_ring` disagrees with this script (manifest, script): {mismatch} "
                             "— the C#↔Python gland crossing has two values; fix ONE home, never both")
    for key in ("lug_radius_mm", "slot_clearance_mm"):
        if abs(flange[key] - radome[key]) > 1e-9:
            raise SystemExit(f"{key}: flange {flange[key]} ≠ radome {radome[key]} — the two halves of the socket band "
                             "disagree (xUnit pins them equal; the manifests drifted)")

    depth = ORING_CS * (1.0 - ORING_SQUEEZE_RATIFIED)
    width = gland_width_required(ORING_CS, depth, GLAND_FILL_DESIGN_TO)
    flange_r = flange["flange_diameter_mm"] / 2.0
    dome_r = radome["dome_diameter_mm"] / 2.0
    clr = radome["slot_clearance_mm"]
    socket_band = radome["lug_radius_mm"] + clr
    seal_band = width + 2.0 * clr
    boss = socket_band + seal_band
    land = (dome_r - boss, dome_r - socket_band)
    groove_out = flange_r - socket_band - clr
    groove_in = groove_out - width
    pocket = (dome_r - socket_band, dome_r - radome["wall_thickness_mm"] + socket_band)
    skin = dome_r - pocket[1]
    # Rim contact area on the flange face: the boss annulus minus the groove footprint (the ring, not PEEK, is
    # there) minus the three entry-slot openings in the outer band — each a disc of radius `socket_band` about
    # the inner wall, clipped to the pocket band [pocket_in, pocket_out] (an exact circular-segment integral).
    r_slot, rim_in = socket_band, dome_r - radome["wall_thickness_mm"]

    def seg(x: float) -> float:       # ∫ 2·sqrt(R² − t²) dt from 0 to x
        x = max(-r_slot, min(r_slot, x))
        return x * math.sqrt(max(r_slot * r_slot - x * x, 0.0)) + r_slot * r_slot * math.asin(x / r_slot)

    slot_opening = seg(pocket[1] - rim_in) - seg(pocket[0] - rim_in)
    contact = (math.pi * (dome_r ** 2 - land[0] ** 2)
               - math.pi * (groove_out ** 2 - groove_in ** 2)
               - radome["bayonet_lugs"] * slot_opening)
    return {
        "applied": "2026-09-14 — branch (а) in CathodeFlange.cs / Radome.cs; read back off cem/cathode_flange.json + cem/radome.json",
        "squeeze_pct": round(ORING_SQUEEZE_RATIFIED * 100, 1),
        "gland_fill": GLAND_FILL_DESIGN_TO,
        "flange_groove_depth_mm": round(depth, 4),
        "flange_groove_width_mm": round(width, 4),
        "flange_groove_r_mm": [round(groove_in, 4), round(groove_out, 4)],
        "radome_seal_land_r_mm": [round(land[0], 4), round(land[1], 4)],
        "seal_land_margin_mm": [round(groove_in - land[0], 4), round(land[1] - groove_out, 4)],
        "socket_band_mm": round(socket_band, 4),
        "socket_pocket_r_mm": [round(pocket[0], 4), round(pocket[1], 4)],
        "socket_skin_mm": round(skin, 4),
        "rim_cavity_mm": round(dome_r * 2.0 - 2.0 * boss, 4),
        "rim_contact_area_mm2": round(contact, 2),
        "entry_slot_opening_mm2_each": round(slot_opening, 3),
        "note": "the seal land backs the groove by one socket clearance on each side, so the ring stays backed with "
                "the radome one clearance off-centre; the socket pocket is `socket_band − skin` deep, not the full "
                "band — the budget above counts no skin, and a pocket cut to the dome OD would breach the shell. "
                "⚠️ The lugs still sit at mid-disc: the ratified collar (02_02 §4.4) is not modelled on either part.",
    }


def depth_tolerance_budget() -> dict:
    """After branch (а) ONE machined depth sets the squeeze — so how tight must it be?

    This does not invent the tolerance the CEM lacks (that number belongs to whoever machines the
    part). It derives the BUDGET the tolerance has to fit inside, which is the input the open ⚖️ is
    actually missing: a requirement, not a guess.
    """
    lo = max(ORING_WIN[0], ORING_WIN_PARKER_FACE[0])
    hi = min(ORING_WIN[1], ORING_WIN_PARKER_FACE[1])
    half_pct = min(ORING_SQUEEZE_RATIFIED - lo, hi - ORING_SQUEEZE_RATIFIED)
    budget = half_pct * ORING_CS
    # ── Allocation: what a candidate depth tolerance LEAVES for the two mating faces ──
    # 🔴 Combination is RSS, and the rule is not cosmetic: linear subtraction (budget − depth) reads
    # ±48 µm left at a ±50 µm depth where RSS leaves ±84, and at ±100 µm it reads «−2 µm» instead of
    # «the depth alone already busts it». Both mislead, in opposite directions, at different values.
    alloc = []
    for depth_tol in (0.025, 0.05, 0.10):
        rem_sq = budget ** 2 - depth_tol ** 2
        fits = rem_sq > 0
        alloc.append({
            "depth_tol_mm": depth_tol,
            "fits_alone": bool(fits),
            "flatness_left_rss_mm": round(math.sqrt(rem_sq), 4) if fits else 0.0,
            "per_face_if_equal_mm": round(math.sqrt(rem_sq / 2.0), 4) if fits else 0.0,
            "linear_leftover_mm": round(budget - depth_tol, 4),   # the WRONG rule, kept to show the gap
        })
    # The chain as modelled NOW (branch (а) applied): one machined depth at the value the shop is asked to hold,
    # against the retired pair it replaced — the pair never fitted (1.84× the budget), which is what branch (а)
    # existed to collapse.
    now_rss = rss(list(TOL_OR.values()))
    pre_rss = rss(list(TOL_OR_PRE_BRANCH_A.values()))
    return {"intersection_window_pct": [round(lo * 100, 1), round(hi * 100, 1)],
            "nominal_pct": round(ORING_SQUEEZE_RATIFIED * 100, 1),
            "half_band_pct_points": round(half_pct * 100, 2),
            "total_gap_budget_half_width_mm": round(budget, 4),
            "allocation_rss": alloc,
            "chain_as_modelled": {
                "contributors_mm": dict(TOL_OR), "rss_mm": round(now_rss, 4),
                "over_budget_x": round(now_rss / budget, 2),
                "flatness_left_rss_mm": round(math.sqrt(max(budget ** 2 - now_rss ** 2, 0.0)), 4),
                "note": "branch (а) APPLIED 2026-09-14: ONE machined dimension, the flange groove depth, at the "
                        "±0.05 the shop is ASKED to hold (00_07 HW.33 👤 — a placeholder for the vendor's answer, "
                        "not a spec). The flatness of the flange top face and of the radome rim is NOT in the "
                        "chain (missing datum) and has the RSS leftover to spend, both faces together.",
            },
            "chain_pre_branch_a": {
                "contributors_mm": dict(TOL_OR_PRE_BRANCH_A), "rss_mm": round(pre_rss, 4),
                "over_budget_x": round(pre_rss / budget, 2),
                "note": "the retired pair of counter-grooves (DMLS seat + CNC rim) — it did NOT fit, 1.84× the "
                        "budget; kept as the record of why the chain was rebuilt rather than re-run.",
            },
            "note": "the WHOLE O-ring chain must fit inside this half-band: machined groove depth plus "
                    "the flatness of both mating faces, RSS. ⛔ The number itself is NOT ours to invent "
                    "(00_07 HW.33: it comes from whoever machines the part) — what this derives is the "
                    "REQUIREMENT the shop's tolerance has to fit inside, i.e. it turns «what is your "
                    "tolerance?» into «can you hold ±X?». ⚠️ And a general-tolerance GRADE is not a "
                    "substitute: a grade is a table keyed to the nominal size, so citing one without "
                    "opening it at 1.344 mm is a claim, not a specification — see the allocation rows."}


def rim_datum_creep(applied: dict) -> dict:
    """⊂ correction (1) of the ⚖️: the rim is PEEK, so may it be treated as a rigid datum for 20 yr?

    Asked by INVERSION, because two of the three springs in the stack have no force datum anywhere in
    canon: instead of summing forces we do not have, compute the force that WOULD push the rim into the
    stress regime where relaxation is worth modelling, and compare it with the one spring canon does
    specify. A bound that holds by two orders of magnitude against that spring — and still by a few
    times against a generous guess for the two unmeasured ones — does not need the missing numbers.
    The contact area is the APPLIED rim's (boss annulus − groove footprint − entry-slot openings,
    `applied_gland`), not the bare 2.0 mm wall the verdict was first checked against (144 mm²).
    """
    faces = seal_faces()
    area = applied["rim_contact_area_mm2"]
    f_star = PEEK_RELAX_REGIME_MPA * area                     # N (MPa·mm² = N)
    pogo = POGO_SPRING_FORCE_N * POGO_PIN_COUNT
    return {
        "rim_contact_area_mm2": round(area, 1),
        "force_to_reach_relax_regime_N": round(f_star, 0),
        "relax_regime_floor_MPa": PEEK_RELAX_REGIME_MPA,
        "pogo_pair_force_N_upper_bound": round(pogo, 2),
        "stress_at_pogo_alone_MPa": round(pogo / area, 4),
        "stress_at_100N_assumed_total_MPa": round(100.0 / area, 3),
        "margin_x_at_100N": round(f_star / 100.0, 1),
        "missing_datum": "Sil-Pad 1500ST deflection-vs-pressure and the O-ring compression load per unit "
                         "of seal length — neither has a home in canon, so the total stack force is not "
                         "computable today. The bound above is why that does not block the verdict.",
        "verdict": f"NEGLIGIBLE — reaching the relaxation regime needs {f_star:.0f} N on the rim, while "
                   f"the only spring canon specifies contributes {pogo:.2f} N; even a deliberately "
                   f"generous 100 N for the two unmeasured springs leaves a {f_star / 100.0:.1f}x "
                   f"margin. No creep member is warranted in the Z-chain for the rim.",
        "skirt_note": faces["skirt"]["note"],
    }


def collar_radial_budget(boss: dict) -> dict:
    """(1) The rim-boss ceiling MINUS the wall of the ratified collar — a wall no artefact specifies.

    ⚖️ 2026-09-11 put the lugs on a raised collar grown in the SOCKET band (02_02 §4.4), and the verdict
    names its own price: the ≤Ø ceiling «shrinks by the collar wall». No CEM field, no canon row and no
    bayonet load model gives that wall (02_02 §4.1 lists retention requirements without a force), so it is
    NOT typed here. The ceiling comes back as a function of it, and the one floor that has a home — the
    canon default SLM min wall — gives the loosest bound ANY collar can leave. A collar that carries lugs
    is thicker than a print floor, so every real ceiling sits below that row.
    """
    slot_clear = cem("radome")["slot_clearance_mm"]
    design_to = boss["design_to_mm"]
    rows = []
    for t in (SLM_MIN_WALL_DEFAULT_MM, 0.5, 1.0, 1.5, 2.0):
        rows.append({"collar_wall_mm": t,
                     "ceiling_mm": round(design_to - 2.0 * t, 2),
                     "ceiling_mm_if_collar_needs_running_clearance": round(design_to - 2.0 * (t + slot_clear), 2)})
    return {
        "closed_form": "board_dia <= design_to - 2*collar_wall",
        "design_to_mm": design_to,
        "printability_floor_mm": SLM_MIN_WALL_DEFAULT_MM,
        "loosest_ceiling_any_collar_mm": rows[0]["ceiling_mm"],
        "rows": rows,
        "missing_datum": "collar wall thickness — no CEM field, no canon row, no bayonet retention FORCE in "
                         "canon to size it against; owner = the collar implementation leg (00_07 HW.33) and the "
                         "lug/Z redesign (HW.8)",
        "readings": "the verdict says the ceiling shrinks by the WALL (column ceiling_mm). If the collar also "
                    "needs a running clearance inside its socket — nothing states it — the ceiling drops by "
                    "2*slot_clearance more (second column). The print floor applies to the SLM branch only: "
                    "the flange route is open (00_07 HW.23).",
    }


def crown_inner_height_mm(r_mm: float, radome: dict, crown: bool) -> float:
    """Internal height over the rim plane at radius r — under today's hemisphere or the RATIFIED flat crown.

    The cavity is a cylinder of `cavity_height_mm` under a cap; the cap's inner surface is the outer one
    offset by the wall, so the crown's inner edge round is R − wall, centred on the outer round's radius.
    ⚠️ A uniform wall under the crown is the READING of «стінка купола лишається 2.0» — the verdict names
    the outer round only. With branch (а) the rim sits on the flange face, so this is height over that face.
    """
    cav, wall = radome["cavity_height_mm"], radome["wall_thickness_mm"]
    dome_r = radome["dome_diameter_mm"] / 2.0
    if not crown:
        r_in = dome_r - wall
        return cav + math.sqrt(max(r_in * r_in - r_mm * r_mm, 0.0))
    round_in = CROWN_EDGE_R_RATIFIED_MM - wall
    d = r_mm - (dome_r - CROWN_EDGE_R_RATIFIED_MM)
    if d <= 0.0:
        return cav + round_in
    return cav + math.sqrt(max(round_in * round_in - d * d, 0.0))


def vertical_stack_budget(boss: dict) -> dict:
    """(2) Does the board stack fit UNDER the ratified crown, with the stack as the BOM specifies it?

    The block over the flange face is (what stands under the Power Deck) + FR4 + B2B + FR4 + whatever
    stands on top of the RF deck.
    🔴 «As the BOM specifies it» carries a term the Z-chain above never had. Canon mounts the SMD piezo on
    the UNDERSIDE of the Power Deck with the Sil-Pad sandwiched between it and the flange (02_01 §6), while
    `GAP_PZ` models the pad spanning the whole board↔flange gap — as if nothing stood under the board. A
    1.9–3.3 mm part cannot live in a 0.65 mm gap, so exactly one of two placements is physical, and they
    price differently; both are reported, neither is chosen:
      • pad_beside_piezo — the pad spans board↔flange as `GAP_PZ` models it; the piezo then needs a pocket
        in the flange face or the other side of the board, and no CEM or canon row carries either;
      • pad_under_piezo — the reading of 02_01 §6: the board stands h_piezo higher, the pogo protrusion
        grows by h_piezo, and pad and pogo stop sharing one gap (the 3-spring model above splits).
    Tolerance is reported against TWO chain readings, because the TOP clearance is not the gap chain: the
    spacer holds the BOTTOM gap, so the top absorbs the stack's own variation, and whether the flange DMLS
    term enters depends on whether crown and spacer share the flange face as datum (branch (а) flat rim says
    they do). Neither reading is derived from a drawing — both are named, and the worst case rides along.
    """
    radome = cem("radome")
    r_edge = boss["design_to_mm"] / 2.0
    h = {"crown_centre": crown_inner_height_mm(0.0, radome, True),
         "crown_at_board_ceiling_edge": crown_inner_height_mm(r_edge, radome, True),
         "hemisphere_centre_today": crown_inner_height_mm(0.0, radome, False),
         "hemisphere_at_board_ceiling_edge_today": crown_inner_height_mm(r_edge, radome, False)}
    tol = {"tol_pz_rss_as_quoted_02_02": rss(list(TOL_PZ.values())),
           "top_chain_rss_flange_face_datum": rss([v for k, v in TOL_PZ.items() if k != "DMLS_Ti"]
                                                  + [SPACER_STEP / 2.0]),
           "tol_pz_worst_case": sum(TOL_PZ.values())}

    def row(placement: str, piezo: str | None, fr4: float, b2b: float) -> dict:
        h_piezo = PIEZO_HEIGHT_MM[piezo] if piezo else 0.0
        underside = GAP_PZ + (h_piezo if placement == "pad_under_piezo" else 0.0)
        # ⛔ pad_beside_piezo leaves the piezo OUT of the stack, so «does a piezo stand under the board» is a
        # question about the candidates, never about the 0 mm this row stacks — reading it off h_piezo = 0
        # printed «fits» for a gap no candidate fits.
        piezo_fits = (True if placement == "pad_under_piezo"
                      else any(h_p <= GAP_PZ for h_p in PIEZO_HEIGHT_MM.values()))
        rf_top = underside + 2.0 * fr4 + b2b
        room_c = h["crown_centre"] - rf_top
        after = {k: round(room_c - v, 3) for k, v in tol.items()}
        return {
            "placement": placement, "piezo": piezo, "piezo_mm": h_piezo if piezo else None,
            "fr4_mm": fr4, "b2b_mm": b2b,
            "b2b_is_named_alternative": bool(abs(b2b - B2B_STACK_ALT_MM) < 1e-9),
            "fr4_is_bom": bool(abs(fr4 - FR4_THICKNESS_MM) < 1e-9),
            "board_underside_over_flange_mm": round(underside, 3),
            "piezo_fits_under_board": bool(piezo_fits),
            "pogo_protrusion_required_mm": round(underside + 0.60 * POGO_TRAVEL, 3),
            "rf_deck_top_over_flange_mm": round(rf_top, 3),
            "antenna_z_over_ti_mm": round(rf_top, 3),
            "rf_meets_canon_floor_8": bool(rf_top >= RF_Z_CANON_FLOOR_MM),
            "rf_below_hfss_trigger_10": bool(rf_top < RF_Z_HFSS_TRIGGER_MM),
            "rf_meets_cem_design_point_12": bool(rf_top >= RF_ANT_TI_CLEARANCE_MIN),
            "room_over_rf_deck_centre_mm": round(room_c, 3),
            "room_over_rf_deck_at_board_edge_mm": round(h["crown_at_board_ceiling_edge"] - rf_top, 3),
            "room_after_tolerance_mm": after,
            "tallest_bom_part_fits_on_top": {k: bool(v >= RF_DECK_TALLEST_BOM_PART_MM) for k, v in after.items()},
        }

    rows = []
    for fr4 in (FR4_THICKNESS_MM, FR4_THICKNESS_UNSOURCED_MM):
        for b2b in (*B2B_STACK_MM, B2B_STACK_ALT_MM):
            rows.append(row("pad_beside_piezo", None, fr4, b2b))
            for name in PIEZO_HEIGHT_MM:
                rows.append(row("pad_under_piezo", name, fr4, b2b))
    bom = [r for r in rows if r["fr4_is_bom"] and not r["b2b_is_named_alternative"]]
    alt = [r for r in rows if r["fr4_is_bom"] and r["b2b_is_named_alternative"]]

    def span(sel: list[dict], key: str) -> list[float]:
        return [min(r[key] for r in sel), max(r[key] for r in sel)]

    under = [r for r in bom if r["placement"] == "pad_under_piezo"]
    beside = [r for r in bom if r["placement"] == "pad_beside_piezo"]
    alt_beside = next(r for r in alt if r["placement"] == "pad_beside_piezo")
    rss_key = "tol_pz_rss_as_quoted_02_02"
    return {
        "inputs_mm": {"gap_pz": GAP_PZ, "fr4_bom": FR4_THICKNESS_MM, "fr4_unsourced_contrast": FR4_THICKNESS_UNSOURCED_MM,
                      "b2b_bom": list(B2B_STACK_MM), "b2b_named_alternative": B2B_STACK_ALT_MM,
                      "piezo_heights": dict(PIEZO_HEIGHT_MM), "tallest_rf_deck_bom_part": RF_DECK_TALLEST_BOM_PART_MM,
                      "crown_edge_r_ratified": CROWN_EDGE_R_RATIFIED_MM, "board_ceiling_radius": round(r_edge, 3)},
        "internal_height_mm": {k: round(v, 3) for k, v in h.items()},
        "tolerance_readings_mm": {k: round(v, 3) for k, v in tol.items()},
        "rows": rows,
        "summary": {
            "bom_rf_deck_top_mm": {"pad_beside_piezo": span(beside, "rf_deck_top_over_flange_mm"),
                                   "pad_under_piezo": span(under, "rf_deck_top_over_flange_mm")},
            "bom_room_centre_mm": {"pad_beside_piezo": span(beside, "room_over_rf_deck_centre_mm"),
                                   "pad_under_piezo": span(under, "room_over_rf_deck_centre_mm")},
            "piezo_fits_in_gap_pz_any_candidate": any(h_p <= GAP_PZ for h_p in PIEZO_HEIGHT_MM.values()),
            "tallest_bom_part_fits_on_top_any_bom_row_rss_as_quoted": {
                "pad_beside_piezo": any(r["tallest_bom_part_fits_on_top"][rss_key] for r in beside),
                "pad_under_piezo": any(r["tallest_bom_part_fits_on_top"][rss_key] for r in under)},
            "pad_under_piezo_rows_that_do_not_close_at_all": [
                f"{r['piezo']} · B2B {r['b2b_mm']:g}" for r in under if r["room_over_rf_deck_centre_mm"] < 0.0],
            "alt_b2b_lever": {"buys_height_mm": round(B2B_STACK_MM[0] - B2B_STACK_ALT_MM, 2),
                              "antenna_z_mm_pad_beside_piezo": alt_beside["antenna_z_over_ti_mm"],
                              "below_hfss_trigger_pad_beside_piezo": alt_beside["rf_below_hfss_trigger_10"]},
        },
        "missing_datum": "piezo height TOLERANCE and solder standoff (pad_under_piezo adds both to the stack); "
                         "which side of the RF deck carries the module; the Power-Deck top-side and RF-deck "
                         "bottom-side contents inside the B2B gap (not judged here)",
        "ceiling": "⛔ judges the block OVER the flange face under the ratified crown only — not the B2B gap's own "
                   "contents, not the radial fit (collar_radial_budget), not the RF acceptance floor (open ⚖️ "
                   "00_07 HW.33, VNA UNI.10); the piezo placement is an open question, not a choice made here.",
    }


def report_row(a: dict) -> str:
    def mark(v, win):
        return "OK " if win[0] <= v <= win[1] else "!! "
    return (f"  {a['label']:<22s} pogo {a['pogo_pct']*100:5.1f}% {mark(a['pogo_pct'], POGO_WIN)} "
            f"pad {a['pad_pct']*100:5.1f}% (20yr {a['pad_pct_20yr']*100:4.1f}%) {mark(a['pad_pct'], PAD_WIN)} "
            f"O-ring {a['oring_pct']*100:5.1f}% {mark(a['oring_pct'], ORING_WIN)} "
            f"{'PASS' if a['pass'] else 'FAIL'}")


def main() -> int:
    banner("HW.8.7 — Z-stack tolerance (3-spring: pogo ∥ pad, O-ring)")

    pz_rss, pz_wc = rss(list(TOL_PZ.values())), sum(TOL_PZ.values())
    or_rss, or_wc = rss(list(TOL_OR.values())), sum(TOL_OR.values())
    print(f"  Shared Power↔Zone3 gap tol:  RSS ±{pz_rss:.2f}  worst-case ±{pz_wc:.2f} mm  (DMLS Ti ±0.30 dominates)")
    print(f"  O-ring gap tol:              RSS ±{or_rss:.2f}  worst-case ±{or_wc:.2f} mm")
    print(f"  Windows — pogo {POGO_WIN[0]*100:.0f}-{POGO_WIN[1]*100:.0f}% (Δ{(POGO_WIN[1]-POGO_WIN[0])*POGO_TRAVEL:.2f}mm) · "
          f"pad {PAD_WIN[0]*100:.0f}-{PAD_WIN[1]*100:.0f}% · O-ring {ORING_WIN[0]*100:.0f}-{ORING_WIN[1]*100:.0f}% (Δ{(ORING_WIN[1]-ORING_WIN[0])*ORING_CS:.2f}mm)")

    banner("Un-mitigated (raw DMLS-dominated stack)")
    unmit = [
        assess("nominal", 0.0, 0.0),
        assess("RSS +", +pz_rss, +or_rss), assess("RSS -", -pz_rss, -or_rss),
        assess("worst-case +", +pz_wc, +or_wc), assess("worst-case -", -pz_wc, -or_wc),
    ]
    for a in unmit:
        print(report_row(a))
    raw_ok = all(c["pass"] for c in unmit)
    print(f"  → un-mitigated {'PASS' if raw_ok else 'FAIL — mitigation required'}")

    # ── Mitigation escalation: each lever shrinks the residual until all 3 windows hold ──
    banner("Mitigation escalation (spacer removes measured DMLS+PCB+B2B; bayonet hard-stop halves CNC)")

    def residual(bayonet: bool, spacer: bool) -> tuple[float, float]:
        """Residual gap tolerance (±) after levers, for the SHARED gap: bayonet hard-stop → deterministic
        engagement (CNC 0.10→0.05); spacer → only CNC + spacer half-step survive (measured stack removed).
        The O-ring chain is untouched by either lever since branch (а): the rim is a hard datum on the
        flange face, so its residual is the machined groove depth alone, whatever seats the bayonet."""
        cnc_pz = 0.05 if bayonet else TOL_PZ["CNC_radome"]
        res_or = rss(list(TOL_OR.values()))
        if spacer:
            return rss([cnc_pz, SPACER_STEP / 2]), res_or
        return rss([v for k, v in TOL_PZ.items() if k != "CNC_radome"] + [cnc_pz]), res_or

    escalation = []
    final_label = None
    for label, bayo, spac in [("L1 spacer only", False, True), ("L2 spacer + bayonet hard-stop", True, True)]:
        rp, ro = residual(bayo, spac)
        ecases = [assess("nominal", 0.0, 0.0), assess("residual +", rp, ro), assess("residual -", -rp, -ro)]
        ok = all(c["pass"] for c in ecases)
        print(f"  {label}:  Power↔Zone3 ±{rp:.2f}  O-ring ±{ro:.2f} mm")
        for c in ecases[1:]:
            print(report_row(c))
        print(f"    → {'PASS — all 3 windows hold incl. 20yr pad creep' if ok else 'FAIL'}")
        escalation.append({"label": label, "residual_pz": round(rp, 3), "residual_or": round(ro, 3),
                           "cases": ecases, "pass": ok})
        if ok and final_label is None:
            final_label = label
    mit_ok = final_label is not None

    # ── Parker face-seal reconciliation (00_07 HW.33) ──
    # The chain used to centre the O-ring at 20 %, which sat BELOW the Parker face-seal floor once the
    # residual band was applied. The question the (then open) ⚖️ asked was whether that forces a documented
    # deviation from Parker — so instead of judging that nominal, derive the nominal that satisfies BOTH
    # windows and report what it costs. That nominal (24.5 %) is RATIFIED and, since 2026-09-14, APPLIED:
    # GAP_OR is the flange groove depth at it. The 20 % figures are re-derived below as the record of the
    # move, never as a live input. The O-ring has its own chain (TOL_OR), so nothing here touches pogo or pad.
    banner("Parker face-seal reconciliation — the ratified nominal, and the chain it now rides")
    _, res_or_final = residual(True, True)
    half_pct = res_or_final / ORING_CS
    half_pct_pre = rss([0.05, SPACER_STEP / 2]) / ORING_CS   # the pre-(а) residual: CNC rim after hard-stop ⊕ spacer half-step
    pre_lo, pre_hi = 0.20 - half_pct_pre, 0.20 + half_pct_pre
    lo_both = max(ORING_WIN[0], ORING_WIN_PARKER_FACE[0])
    hi_both = min(ORING_WIN[1], ORING_WIN_PARKER_FACE[1])
    nominal_both = (lo_both + hi_both) / 2.0
    band_lo, band_hi = nominal_both - half_pct, nominal_both + half_pct
    fits_both = band_lo >= lo_both and band_hi <= hi_both
    gap_or_new = ORING_CS * (1.0 - nominal_both)
    applied_nominal = abs(gap_or_new - GAP_OR) < 1e-9
    print(f"  Residual O-ring band on the applied one-term chain (±{DEPTH_TOL_ASKED} depth, asked): ±{half_pct*100:.2f} pp of squeeze")
    print(f"  (pre-(а) chain, hard-stop + spacer on the two-contributor pair: ±{half_pct_pre*100:.2f} pp; at its 20 % nominal "
          f"{pre_lo*100:.1f}-{pre_hi*100:.1f} % → industry {'OK' if pre_lo >= ORING_WIN[0] and pre_hi <= ORING_WIN[1] else 'FAIL'}, "
          f"Parker face {'OK' if pre_lo >= ORING_WIN_PARKER_FACE[0] and pre_hi <= ORING_WIN_PARKER_FACE[1] else 'FAIL'})")
    print(f"  Windows intersect at {lo_both*100:.0f}-{hi_both*100:.0f} % → "
          f"centring the band there means a {nominal_both*100:.1f} % nominal")
    print(f"  At that nominal:              {band_lo*100:.1f}-{band_hi*100:.1f} %  → "
          f"{'BOTH windows hold' if fits_both else 'still outside — a deviation IS required'}")
    print(f"  Applied in CAD: {'YES' if applied_nominal else 'NO'} — GAP_OR (flange groove depth) = {GAP_OR:.3f} mm; the pre-(а) 20 % chain "
          f"seated the rim at {GAP_OR_PRE_BRANCH_A:.3f}, i.e. the move was {abs(GAP_OR_PRE_BRANCH_A - gap_or_new)*1000:.0f} µm. "
          "Pogo and pad ride a DIFFERENT chain (TOL_PZ) and did not move.")

    # ── Gland geometry: does the ratified seal FIT the face that closes on it? (00_07 HW.33) ──
    # ⚠️ Declared ceiling: this section judges the gland and the faces, not the 3-spring stack, so it
    # deliberately does NOT move the exit code — that stays the 3-spring assessment above. Reading a
    # green run as "the gland is fine" is exactly the mis-read this note exists to stop.
    banner("Gland geometry — the ratified depth needs a WIDTH, and the width needs a FACE")
    gland = gland_verdict()
    boss = rim_boss_radial_budget()
    applied = applied_gland()
    budget = depth_tolerance_budget()
    rim = rim_datum_creep(applied)

    print(f"  O-ring CS {ORING_CS} mm → section area {gland['ring_area_mm2']:.3f} mm²; "
          f"ratified squeeze {ORING_SQUEEZE_RATIFIED*100:.1f} % → groove depth {gland['depth_mm']:.3f} mm")
    for k, v in gland["required_width_mm"].items():
        print(f"    gland fill ≤ {k:<4s} → groove width ≥ {v:.3f} mm")
    print("  Face available to close on that groove, per MATE-Ø candidate:")
    for name, c in gland["candidates"].items():
        verdict = "fits" if c["face_seal_possible"] else "DOES NOT FIT"
        print(f"    {name:<8s} land {c['land_mm']:.2f} mm → residual {c['residual_after_groove_mm']:+.2f} mm  {verdict}")
    print(f"    ⚠️ skirt: {gland['faces']['skirt']['note']}")
    print("  If the cord is the problem rather than the wall, the smaller standard cords:")
    for k, v in gland["smaller_cord_options"].items():
        print(f"    {k}: depth {v['depth_mm']:.3f}  width@85% {v['width_at_85pct_mm']:.3f}  "
              f"land left on the asis rim {v['land_left_on_asis_rim_mm']:+.3f} mm")

    print(f"\n  APPLIED gland (branch (а), 2026-09-14, read back off both manifests): flange groove "
          f"{applied['flange_groove_width_mm']:.3f} × {applied['flange_groove_depth_mm']:.3f} at r {applied['flange_groove_r_mm']}")
    print(f"    radome seal land r {applied['radome_seal_land_r_mm']} (margin {applied['seal_land_margin_mm']} each side) · "
          f"socket pocket r {applied['socket_pocket_r_mm']} (skin {applied['socket_skin_mm']:.2f}) · rim cavity Ø{applied['rim_cavity_mm']:.2f}")
    print(f"    rim contact area {applied['rim_contact_area_mm2']:.1f} mm² (boss − groove − {cem('radome')['bayonet_lugs']} slot openings "
          f"of {applied['entry_slot_opening_mm2_each']:.2f} each)")

    print(f"\n  Depth-tolerance BUDGET: the whole O-ring chain must stay "
          f"within ±{budget['total_gap_budget_half_width_mm']*1000:.0f} µm")
    print(f"    ({budget['half_band_pct_points']:.2f} pp of squeeze either side of the "
          f"{budget['nominal_pct']:.1f} % nominal, inside the {budget['intersection_window_pct']} % window)")
    cm = budget["chain_as_modelled"]
    print(f"    chain as modelled: {cm['contributors_mm']} → RSS ±{cm['rss_mm']*1000:.0f} µm = {cm['over_budget_x']:.2f}× budget, "
          f"leaving ±{cm['flatness_left_rss_mm']*1000:.0f} µm (RSS) for the flatness of BOTH mating faces — a named missing datum")
    cp = budget["chain_pre_branch_a"]
    print(f"    (retired pre-(а) pair {cp['contributors_mm']} → RSS ±{cp['rss_mm']*1000:.0f} µm = {cp['over_budget_x']:.2f}× budget — never fitted)")

    print(f"\n  PEEK rim as a rigid datum (⊂ correction (1)): contact area {rim['rim_contact_area_mm2']:.0f} mm²; "
          f"reaching {rim['relax_regime_floor_MPa']:.1f} MPa needs {rim['force_to_reach_relax_regime_N']:.0f} N")
    print(f"    pogo pair (the only spring canon specifies) = {rim['pogo_pair_force_N_upper_bound']:.2f} N "
          f"→ {rim['stress_at_pogo_alone_MPa']:.4f} MPa; at a generous 100 N total the margin is still "
          f"{rim['margin_x_at_100N']:.1f}×")
    print("    → creep member NOT warranted for the rim; missing datum named in the JSON, not guessed")

    # ── Board budget handed to HW.9 (00_07 HW.33 leg 2026-09-14) ──
    # ⚠️ Same declared ceiling as the gland block: an envelope for a layout that does not exist yet, so it
    # does NOT move the exit code.
    banner("Board budget handed to HW.9 — collar wall (radial) and the block under the crown (vertical)")
    collar = collar_radial_budget(boss)
    vert = vertical_stack_budget(boss)
    print(f"  (1) Radial: board Ø ≤ {collar['design_to_mm']:.2f} − 2·collar_wall, and no artefact gives the wall:")
    for r in collar["rows"]:
        print(f"      wall {r['collar_wall_mm']:.2f} → Ø ≤ {r['ceiling_mm']:.2f}   "
              f"(Ø ≤ {r['ceiling_mm_if_collar_needs_running_clearance']:.2f} if it also needs a running clearance)")
    print(f"      → the loosest ceiling ANY collar can leave: Ø{collar['loosest_ceiling_any_collar_mm']:.2f} "
          f"(the {collar['printability_floor_mm']:.1f} mm print floor, SLM branch only)")
    ih, tr = vert["internal_height_mm"], vert["tolerance_readings_mm"]
    rss_key = "tol_pz_rss_as_quoted_02_02"
    print(f"  (2) Vertical: {ih['crown_centre']:.2f} mm over the flange face under the ratified crown "
          f"({ih['crown_at_board_ceiling_edge']:.2f} at the Ø{collar['design_to_mm']:.2f} edge; "
          f"{ih['hemisphere_centre_today']:.2f} under today's hemisphere)")
    print("      tolerance readings: " + " · ".join(f"{k} ±{v:.2f}" for k, v in tr.items()))
    print(f"      FR4 {FR4_THICKNESS_MM:.1f} (BOM) rows — RF-deck top over the flange · room over it · after ±{tr[rss_key]:.2f} · "
          f"tallest BOM part ({RF_DECK_TALLEST_BOM_PART_MM:.1f}) on top  [* = the BOM's named B2B alternative]")
    for r in vert["rows"]:
        if not r["fr4_is_bom"]:
            continue
        tag = (f"{r['placement']:<17s} {(r['piezo'] or '—'):<25s} "
               f"B2B {r['b2b_mm']:>4.1f}{'*' if r['b2b_is_named_alternative'] else ' '}")
        print(f"      {tag} top {r['rf_deck_top_over_flange_mm']:5.2f}  room {r['room_over_rf_deck_centre_mm']:+5.2f}  "
              f"→ {r['room_after_tolerance_mm'][rss_key]:+5.2f}  "
              f"{'fits' if r['tallest_bom_part_fits_on_top'][rss_key] else 'NO  '}"
              f"{'' if r['piezo_fits_under_board'] else '  ⚠ no candidate piezo stands in this gap'}")
    s = vert["summary"]
    print(f"  → no candidate piezo fits under the board at GAP_PZ {GAP_PZ:.2f}: "
          f"{not s['piezo_fits_in_gap_pz_any_candidate']} — the two placements are the open question, not a choice here")
    print(f"  → tallest BOM part on the RF-deck TOP, any BOM row: pad_beside_piezo "
          f"{s['tallest_bom_part_fits_on_top_any_bom_row_rss_as_quoted']['pad_beside_piezo']} · pad_under_piezo "
          f"{s['tallest_bom_part_fits_on_top_any_bom_row_rss_as_quoted']['pad_under_piezo']}")
    if s["pad_under_piezo_rows_that_do_not_close_at_all"]:
        print(f"  → pad_under_piezo rows with NEGATIVE room before any tolerance: "
              f"{', '.join(s['pad_under_piezo_rows_that_do_not_close_at_all'])}")

    banner("Verdict")
    print(f"  Un-mitigated: {'holds' if raw_ok else 'FAILS — RSS exceeds the narrowest window'} → spacer MANDATORY (02_02 §3.5).")
    print(f"  Minimum mitigation that holds: {final_label or 'NONE in ladder — widen O-ring CS / bigger pogo travel'}.")
    print("  🔑 Pad = 3rd spring (∥ pogo on the shared gap) — absent from 02_02 §3.5; close that canon gap.")
    print("  🔑 Bayonet (not thread) hard-stop halves the CNC residual on the SHARED gap; the O-ring no longer rides it —")
    print("     its Z is the flat rim ON the flange face (branch (а)), so the seal holds on the machined depth alone.")
    print(f"  RF: antenna↔Ti ≥ {RF_ANT_TI_CLEARANCE_MIN:.0f} mm = OUR working floor, NOT a canon requirement "
          "(02_01 §5.3 asks ≥8, 10-15 desirable, HFSS below 10; open verdict 00_07 HW.33, VNA sweep 5/8/12 = UNI.10).")

    out = {
        "method": "1D linear tolerance chain (RSS + worst-case), 3-spring blind-mate Z-stack",
        "springs": {
            "pogo": {"travel_mm": POGO_TRAVEL, "free_mm": round(POGO_FREE, 3), "window_pct": POGO_WIN},
            "pad": {"free_mm": PAD_FREE, "window_pct": PAD_WIN,
                    "creep_retain_20yr": PAD_CREEP_RETAIN, "acoustic_min_pct": PAD_ACOUSTIC_MIN},
            "oring": {"cs_mm": ORING_CS, "window_pct": ORING_WIN,
                      "window_pct_parker_face": ORING_WIN_PARKER_FACE},
        },
        "shared_gap_note": "pogo + pad are parallel springs on the Power↔Zone3 gap; O-ring on Radome-rim↔Zone3",
        "nominal_gaps_mm": {"power_zone3": GAP_PZ, "oring": round(GAP_OR, 3)},
        "tolerance_mm": {
            "power_zone3": {"contributors": TOL_PZ, "rss": round(pz_rss, 3), "worst_case": round(pz_wc, 3)},
            "oring": {"contributors": TOL_OR, "rss": round(or_rss, 3), "worst_case": round(or_wc, 3)},
        },
        "unmitigated": {"cases": unmit, "pass": raw_ok},
        "mitigation_escalation": escalation,
        "min_mitigation_pass": final_label,
        "parker_face_reconciliation": {
            "residual_half_width_pct_points": round(half_pct * 100, 2),
            "residual_half_width_pct_points_pre_branch_a": round(half_pct_pre * 100, 2),
            "band_at_pre_branch_a_20pct_nominal": [round(pre_lo * 100, 1), round(pre_hi * 100, 1)],
            "pre_branch_a_nominal_held_industry": bool(pre_lo >= ORING_WIN[0] and pre_hi <= ORING_WIN[1]),
            "pre_branch_a_nominal_held_parker_face": bool(pre_lo >= ORING_WIN_PARKER_FACE[0]
                                                          and pre_hi <= ORING_WIN_PARKER_FACE[1]),
            "intersection_window_pct": [round(lo_both * 100, 1), round(hi_both * 100, 1)],
            "recommended_nominal_pct": round(nominal_both * 100, 1),
            "band_at_recommended_pct": [round(band_lo * 100, 1), round(band_hi * 100, 1)],
            "recommended_holds_both": bool(fits_both),
            "applied_in_cad": bool(applied_nominal),
            "oring_gap_mm_applied": round(GAP_OR, 3),
            "oring_gap_mm_pre_branch_a": round(GAP_OR_PRE_BRANCH_A, 3),
            "oring_gap_mm_recommended": round(gap_or_new, 3),
            "radome_rim_shift_um": round(abs(GAP_OR_PRE_BRANCH_A - gap_or_new) * 1000, 0),
            "note": "The HW.33 fork was 'accept a documented deviation from Parker OR re-run 52'. The re-run "
                    "said the fork is removable: the two windows intersect at 19-30 %, so centring the nominal "
                    "there puts the whole residual band inside BOTH with symmetric margin. RATIFIED 2026-09-10 "
                    "and APPLIED in CAD 2026-09-14 (branch (а)): the residual band is now the one-term machined "
                    "depth chain (+/-2.81 pp at the +/-0.05 the shop is asked to hold), where the pre-(а) pair "
                    "after hard-stop + spacer read +/-3.97 pp. The O-ring rides its own chain, so pogo and pad "
                    "are untouched."},
        "gland_geometry": gland,
        "rim_boss_radial_budget": boss,
        "applied_gland": applied,
        "depth_tolerance_budget": budget,
        "rim_datum_creep": rim,
        "collar_radial_budget": collar,
        "vertical_stack_budget": vert,
        "rf_constraint": {"antenna_ti_clearance_min_mm": RF_ANT_TI_CLEARANCE_MIN,
                          "note": "geometric (self-owned); VNA/HFSS lab-side Гончаров 00_02 §1.2, unresponsive"},
        "verdict": (f"3-spring Z-stack holds at '{final_label}' incl. 20yr pad creep"
                    if mit_ok else "no ladder level holds — widen O-ring CS / bigger pogo travel"),
    }
    json_path = OUT_DIR / "z_stack_tolerance.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    return 0 if mit_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
