#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.8.7 — Axial Z-stack tolerance analysis (3-spring) for the Soldier capsule ↔ anchor blind-mate.

The bayonet-closed Z-loop (Radome ↔ Zone 3) compresses THREE compliant elements simultaneously:
  1. Pogo pins  (Mill-Max 0908, 1.52 mm travel)        — 50-70 % mid-stroke window (02_02 §2.2/§3.5)
  2. O-ring     (EPDM, CS 1.78 mm)                      — 15-30 % static squeeze (Parker handbook)
  3. Sil-Pad    (Bergquist 1500ST, ~1 mm, HW.30)        — acoustic-coupling contact, 20 yr creep

🔑 Pogo + Sil-Pad are PARALLEL springs on the SAME gap (Power Deck ↔ Zone 3) → one gap sets both
compressions. O-ring is on a separate gap (Radome rim ↔ Zone 3). 02_02 §3.5 models only pogo+O-ring;
the acoustic pad is the missing 3rd spring (this script closes that gap).

DMLS Ti ±0.3 mm dominates the budget; raw RSS exceeds the (narrow) windows → a robot-selected 0.1 mm
spacer (off the measured DMLS+PCB stack) is the mitigation. RF antenna Z-clearance (02_01 §5.3,
~12 mm antenna↔Ti) is enforced here as a GEOMETRIC constraint; the VNA/HFSS validation is lab-side
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
from lib.constants import CACHE_DIR, REPO_ROOT
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

# ── Nominal gaps — design targets, centered (pogo 60 %, pad 35 %, O-ring 20 %) ──
GAP_PZ = 0.65                              # mm — Power Deck ↔ Zone 3 (sets pogo + pad)
POGO_FREE = GAP_PZ + 0.60 * POGO_TRAVEL    # protrusion so pogo sits at 60 % at nominal gap
GAP_OR = ORING_CS * (1.0 - 0.20)           # Radome rim ↔ Zone 3 so O-ring sits at 20 %

# ── RF constraint (02_01 §5.3) — geometric, self-owned (Гончаров VNA pending) ──
RF_ANT_TI_CLEARANCE_MIN = 12.0   # mm — antenna ↔ Ti flange min Z-clearance for VSWR

# ── Gland geometry inputs (HW.33 branch (а), ⚖️ 2026-09-10) ──
# The squeeze verdict fixes the groove DEPTH. Depth alone does not make a gland: an O-ring displaces a
# fixed cross-section area, so the WIDTH follows from the depth, and the width has to live inside the
# flat face that closes on it. That third question is what this block asks.
ORING_SQUEEZE_RATIFIED = 0.245   # ⚖️ founder-proxy 2026-09-10 — centre of the 19-30 % intersection
# Gland fill = O-ring section area / groove section area. A gland filled to 100 % has nowhere to put the
# elastomer it displaces, so the ring extrudes or the faces are held apart. ⚠️ 00_06 §0: the ceiling
# below is CITED industry practice (Parker's own design rule is a groove ~25 % larger than the ring,
# i.e. ~80 % fill), NOT a computed physical fact — the verdict here is deliberately reported against all
# three so it does not rest on the choice.
GLAND_FILL_CEILINGS = (0.80, 0.85, 0.90)
# The stress level below which 20-yr PEEK stress-relaxation is not worth a model. Anchored INSIDE our
# own canon rather than on an outside datasheet: 01_01 §4.3 tabulates PEEK relaxation on the press-fit
# joint at 25-30 MPa contact pressure, so a tenth of that is a conservative floor for "negligible".
PEEK_RELAX_REGIME_MPA = 10.0
POGO_SPRING_FORCE_N = 0.96       # N per pin at FULL travel (02_02 §2.2) — an upper bound at 50-70 %
POGO_PIN_COUNT = 2               # centre (GND) + outer ring (V+), 02_02 §1.2

# CEM manifests are the parameter SSOT of the shipped geometry (canon-gated by scripts/cem_canon_sync.rb).
# Read at RUNTIME, never mirrored as literals here: the CAD and in-silico halves share no identifier
# vocabulary, so a hand-copied dimension can only ever be found by grepping the VALUE.
CEM_DIR = REPO_ROOT / "tools" / "cad" / "cem"


def cem(stem: str) -> dict:
    return json.loads((CEM_DIR / f"{stem}.json").read_text(encoding="utf-8"))

# ── Tolerance contributors (± half-width, mm) ──
# Shared Power↔Zone3 gap: DMLS Ti flange + both FR4 decks + B2B stack + CNC radome engagement.
TOL_PZ = {"DMLS_Ti": 0.30, "FR4_power": 0.20, "B2B_stack": 0.15, "FR4_rf": 0.20, "CNC_radome": 0.10}
# O-ring gap: DMLS Ti seat + CNC radome rim (fewer links — nearer the bayonet datum).
TOL_OR = {"DMLS_Ti_seat": 0.15, "CNC_radome_rim": 0.10}
# A selective 0.1 mm spacer removes the MEASURED rigid stack (DMLS+PCB+B2B), leaving only the CNC PEEK
# engagement + the spacer half-step as residual (see residual() in main).
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


def shipped_groove_alignment() -> dict:
    """The two counter-grooves the shipped CAD still cuts — do they even face each other?"""
    flange, radome = cem("cathode_flange"), cem("radome")
    flange_r = flange["flange_diameter_mm"] / 2.0
    dome_r = radome["dome_diameter_mm"] / 2.0
    rim_in = dome_r - radome["wall_thickness_mm"]
    # CathodeFlange.Build: outer edge = flangeR − 1.5 (a bare literal in the generator, no CEM field).
    f_out = flange_r - 1.5
    f_in = f_out - flange["o_ring_groove_width_mm"]
    r_in, r_out = rim_in, rim_in + radome["o_ring_groove_width_mm"]
    overlap = max(0.0, min(f_out, r_out) - max(f_in, r_in))
    under_cavity = max(0.0, min(rim_in, f_out) - f_in)
    return {
        "flange_groove_r_mm": [round(f_in, 2), round(f_out, 2)],
        "radome_groove_r_mm": [round(r_in, 2), round(r_out, 2)],
        "radome_rim_r_mm": [round(rim_in, 2), round(dome_r, 2)],
        "radial_overlap_mm": round(overlap, 3),
        "flange_groove_share_under_dome_cavity": round(under_cavity / (f_out - f_in), 3),
        "combined_depth_mm": round(flange["o_ring_groove_depth_mm"] + radome["o_ring_groove_depth_mm"], 3),
        "combined_squeeze_pct": round((ORING_CS - (flange["o_ring_groove_depth_mm"]
                                                   + radome["o_ring_groove_depth_mm"])) / ORING_CS * 100, 1),
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
    return {"intersection_window_pct": [round(lo * 100, 1), round(hi * 100, 1)],
            "nominal_pct": round(ORING_SQUEEZE_RATIFIED * 100, 1),
            "half_band_pct_points": round(half_pct * 100, 2),
            "total_gap_budget_half_width_mm": round(half_pct * ORING_CS, 4),
            "note": "the WHOLE O-ring chain must fit inside this half-band: machined groove depth plus "
                    "the flatness of both mating faces, RSS. It is not a tight number — a routine "
                    "±0.05 mm on the depth leaves the rest of the budget for flatness."}


def rim_datum_creep() -> dict:
    """⊂ correction (1) of the ⚖️: the rim is PEEK, so may it be treated as a rigid datum for 20 yr?

    Asked by INVERSION, because two of the three springs in the stack have no force datum anywhere in
    canon: instead of summing forces we do not have, compute the force that WOULD push the rim into the
    stress regime where relaxation is worth modelling, and compare it with the one spring canon does
    specify. A bound that holds by three orders of magnitude does not need the missing numbers.
    """
    faces = seal_faces()
    dome_r = cem("radome")["dome_diameter_mm"] / 2.0
    rim_in = dome_r - cem("radome")["wall_thickness_mm"]
    area = math.pi * (dome_r ** 2 - rim_in ** 2)
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
                   f"generous 100 N for the two unmeasured springs leaves a {f_star / 100.0:.0f}x "
                   f"margin. No creep member is warranted in the Z-chain for the rim.",
        "skirt_note": faces["skirt"]["note"],
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
        """Residual gap tolerance (±) after levers. bayonet hard-stop → deterministic engagement
        (CNC 0.10→0.05); spacer → only CNC + spacer half-step survive (measured stack removed)."""
        cnc_pz = 0.05 if bayonet else TOL_PZ["CNC_radome"]
        cnc_or = 0.05 if bayonet else TOL_OR["CNC_radome_rim"]
        if spacer:
            return rss([cnc_pz, SPACER_STEP / 2]), rss([cnc_or, SPACER_STEP / 2])
        return (rss([v for k, v in TOL_PZ.items() if k != "CNC_radome"] + [cnc_pz]),
                rss([v for k, v in TOL_OR.items() if k != "CNC_radome_rim"] + [cnc_or]))

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
    # The mitigation above centres the O-ring at 20 %, which sits BELOW the Parker face-seal floor once
    # the residual band is applied. The question the open ⚖️ asks is whether that forces a documented
    # deviation from Parker — so instead of judging the current nominal, derive the nominal that would
    # satisfy BOTH windows and report what it costs. The O-ring gap has its own tolerance chain
    # (TOL_OR), so moving it does not touch pogo or pad at all.
    banner("Parker face-seal reconciliation — does the mitigation need a deviation?")
    _, res_or_final = residual(True, True)
    half_pct = res_or_final / ORING_CS
    now_lo, now_hi = 0.20 - half_pct, 0.20 + half_pct
    lo_both = max(ORING_WIN[0], ORING_WIN_PARKER_FACE[0])
    hi_both = min(ORING_WIN[1], ORING_WIN_PARKER_FACE[1])
    nominal_both = (lo_both + hi_both) / 2.0
    band_lo, band_hi = nominal_both - half_pct, nominal_both + half_pct
    fits_both = band_lo >= lo_both and band_hi <= hi_both
    gap_or_new = ORING_CS * (1.0 - nominal_both)
    print(f"  Residual O-ring band after spacer + hard-stop: ±{half_pct*100:.2f} pp of squeeze")
    print(f"  At the CURRENT 20 % nominal:  {now_lo*100:.1f}-{now_hi*100:.1f} %  → "
          f"industry {'OK' if now_lo >= ORING_WIN[0] and now_hi <= ORING_WIN[1] else 'FAIL'}, "
          f"Parker face {'OK' if now_lo >= ORING_WIN_PARKER_FACE[0] and now_hi <= ORING_WIN_PARKER_FACE[1] else 'FAIL'}")
    print(f"  Windows intersect at {lo_both*100:.0f}-{hi_both*100:.0f} % → "
          f"centring the band there means a {nominal_both*100:.1f} % nominal")
    print(f"  At that nominal:              {band_lo*100:.1f}-{band_hi*100:.1f} %  → "
          f"{'BOTH windows hold' if fits_both else 'still outside — a deviation IS required'}")
    print(f"  Cost of the move: O-ring gap {GAP_OR:.3f} → {gap_or_new:.3f} mm, i.e. the radome rim comes")
    print(f"  down {abs(GAP_OR - gap_or_new)*1000:.0f} µm. Pogo and pad ride a DIFFERENT tolerance chain "
          "(TOL_PZ) and do not move.")
    if fits_both:
        print("  → The open ⚖️ «accept a deviation from Parker OR re-run 52» does not need a choice:")
        print("    a ~0.1 mm nominal change satisfies Parker face-seal AND industry practice at once,")
        print("    with symmetric margin. What remains is a design edit, not a judgement.")

    # ── Gland geometry: does the ratified seal FIT the face that closes on it? (00_07 HW.33) ──
    # ⚠️ Declared ceiling: this section judges the PROPOSED branch (а), not the shipped stack, so it
    # deliberately does NOT move the exit code — that stays the 3-spring assessment above. Reading a
    # green run as "the gland is fine" is exactly the mis-read this note exists to stop.
    banner("Gland geometry — the ratified depth needs a WIDTH, and the width needs a FACE")
    gland = gland_verdict()
    align = shipped_groove_alignment()
    budget = depth_tolerance_budget()
    rim = rim_datum_creep()

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

    print(f"\n  Shipped counter-grooves — flange r {align['flange_groove_r_mm']} vs radome r {align['radome_groove_r_mm']}:")
    print(f"    radial overlap {align['radial_overlap_mm']:.2f} mm; "
          f"{align['flange_groove_share_under_dome_cavity']*100:.0f} % of the flange groove lies under the "
          f"dome CAVITY (nothing presses it)")
    print(f"    combined depth {align['combined_depth_mm']:.2f} mm ⇒ squeeze {align['combined_squeeze_pct']:+.1f} % "
          "— the ring is not compressed at all")

    print(f"\n  Depth-tolerance BUDGET (the input the open ⚖️ lacks): the whole O-ring chain must stay "
          f"within ±{budget['total_gap_budget_half_width_mm']*1000:.0f} µm")
    print(f"    ({budget['half_band_pct_points']:.2f} pp of squeeze either side of the "
          f"{budget['nominal_pct']:.1f} % nominal, inside the {budget['intersection_window_pct']} % window)")

    print(f"\n  PEEK rim as a rigid datum (⊂ correction (1)): contact area {rim['rim_contact_area_mm2']:.0f} mm²; "
          f"reaching {rim['relax_regime_floor_MPa']:.0f} MPa needs {rim['force_to_reach_relax_regime_N']:.0f} N")
    print(f"    pogo pair (the only spring canon specifies) = {rim['pogo_pair_force_N_upper_bound']:.2f} N "
          f"→ {rim['stress_at_pogo_alone_MPa']:.4f} MPa; at a generous 100 N total the margin is still "
          f"{rim['margin_x_at_100N']:.0f}×")
    print("    → creep member NOT warranted for the rim; missing datum named in the JSON, not guessed")

    banner("Verdict")
    print(f"  Un-mitigated: {'holds' if raw_ok else 'FAILS — RSS exceeds the narrowest window'} → spacer MANDATORY (02_02 §3.5).")
    print(f"  Minimum mitigation that holds: {final_label or 'NONE in ladder — widen O-ring CS / bigger pogo travel'}.")
    print("  🔑 Pad = 3rd spring (∥ pogo on the shared gap) — absent from 02_02 §3.5; close that canon gap.")
    print("  🔑 Bayonet (not thread) hard-stop is load-bearing — deterministic Z halves the CNC residual → O-ring holds.")
    print(f"  RF: antenna↔Ti ≥ {RF_ANT_TI_CLEARANCE_MIN:.0f} mm = geometric radome-height constraint (VNA self-owned; Гончаров lab pending).")

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
            "band_at_current_nominal_pct": [round(now_lo * 100, 1), round(now_hi * 100, 1)],
            "current_nominal_holds_industry": bool(now_lo >= ORING_WIN[0] and now_hi <= ORING_WIN[1]),
            "current_nominal_holds_parker_face": bool(now_lo >= ORING_WIN_PARKER_FACE[0]
                                                      and now_hi <= ORING_WIN_PARKER_FACE[1]),
            "intersection_window_pct": [round(lo_both * 100, 1), round(hi_both * 100, 1)],
            "recommended_nominal_pct": round(nominal_both * 100, 1),
            "band_at_recommended_pct": [round(band_lo * 100, 1), round(band_hi * 100, 1)],
            "recommended_holds_both": bool(fits_both),
            "oring_gap_mm_current": round(GAP_OR, 3),
            "oring_gap_mm_recommended": round(gap_or_new, 3),
            "radome_rim_shift_um": round(abs(GAP_OR - gap_or_new) * 1000, 0),
            "note": "The open HW.33 fork was 'accept a documented deviation from Parker OR re-run 52'. "
                    "Re-run says the fork is removable: the two windows intersect at 19-30 %, the "
                    "residual band is +/-3.97 pp, so centring the nominal in the intersection puts the "
                    "whole band inside BOTH with symmetric margin. The O-ring rides its own tolerance "
                    "chain, so pogo and pad are untouched. Cost is a nominal geometry edit, not a "
                    "judgement."},
        "gland_geometry": gland,
        "shipped_groove_alignment": align,
        "depth_tolerance_budget": budget,
        "rim_datum_creep": rim,
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
