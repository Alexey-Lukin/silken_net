#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.43 (checkbox 2) — endurance-limit literature review for the four contact/elastic parts named
in the item: pogo spring (Mill-Max 0906), Sil-Pad (HW.30), genipin-chitosan-CNC matrix, PEEK
mechanical-lock barbs (HW.26). Closed form only (no FEA) — the question is the ACCEPTANCE UNIT
itself: for each part, is it below its endurance/fatigue limit (N does not matter) or does the
computed cycle budget N ≈ 6.3e8 (HW.43 head, 20 yr × 1 Hz trunk sway, 01_02 §2.2) decide?

⚠️ 00_06 §0 Validation Gate: every number below is a CITED literature value, not a computed
physical fact — mark of the ones that remain genuinely open, do not round them into a verdict.

Verdicts by part (see the four functions + `main` for the full reasoning and caveats):
  1. Pogo spring (BeCu C17200) — TWO MISMATCHED FRAMINGS, not one number. By the manufacturer's
     own full-stroke actuation-life rating: FAILS (N budget is 630-6300x the rated life) — but that
     framing almost certainly does not apply, because canon (01_01 §2) already asserts the spring
     travel margin absorbs sway as micro-motion, not full-stroke cycling. By the physically-relevant
     low-amplitude stress-fatigue model, real S-N anchor points exist, but the actual working stress
     at the true sway deflection amplitude is NOT computed anywhere in canon — PARTIAL, names the
     missing datum.
  2. PEEK mechanical-lock barb (cyclic fatigue, NOT the already-tracked HW.26 static cold-flow
     creep) — a real endurance-limit reference now exists (30-48 MPa @ 1e6-1e7 cycles, two
     independent sources) but the actual barb contact-stress amplitude is not computed (HW.26 FEA
     still open) — PARTIAL, hands HW.26 an acceptance threshold to FEA against.
  3. Sil-Pad — genuinely NOT closeable by this method: compression-set/creep in silicone elastomers
     is formulation-specific and has no generic closed-form S-N curve; HW.30 already schedules the
     only correct instrument (bench Arrhenius-accelerated creep test) — OPEN, correctly so.
  4. Genipin-chitosan-CNC matrix — CATEGORY MISMATCH, a correction to HW.43's own list, not a
     finding about the matrix: it is a ~10-20 µm enzyme-immobilization hydrogel COATING (01_03
     §2.1 Layer 4), not a load-bearing spring/structural element under the 0.5-5 N axial stress
     table (01_02 §2.2). Its own cyclic-strain assessment exists (script 16, N=10 MD cycles,
     qualitative pseudoplastic verdict — PIPELINE_STATUS.md row 16) and the wet-lab bench spec
     (01_03 §3.4, 10 000 cycles @ 0.1 Hz) is already the item's own cited comparison point; neither
     is an S-N endurance-limit measurement, and none exists in the literature for a crosslinked
     hydrogel coating the way it does for metals/PEEK. Durability axis for this part is chemical/
     enzymatic (HW.5 stability tests), not mechanical fatigue.

Sources (fetched 2026-09-09, see verdict `sources` list in the JSON output for exact citations):
  - BeCu C17200 VHCF: "Specific very high cycle fatigue fracture mechanism in C17200 beryllium
    copper alloy…" (ScienceDirect) + "Rotating Bending Fatigue Behaviors of C17200…" (PMC/NCBI).
  - Mill-Max 0906 series product page (mill-max.com) — mechanical life spec.
  - PEEK endurance limit: peekchina.com "Fatigue Strength of PEEK: A Guide for Gear Engineers" +
    Pastukhov et al. 2020, "Physical background of the endurance limit in poly(ether ether ketone)",
    J. Polym. Sci. (Wiley).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)

N_BUDGET_CYCLES = 6.3e8  # HW.43 head number: 20 yr x 1 Hz trunk sway (01_02 §2.2 lower bound of 1-5 Hz)


def pogo_spring_verdict() -> dict:
    mfr_life_lo, mfr_life_hi = 1.0e5, 1.0e6  # Mill-Max 0906 series datasheet, "mechanical life at mid-stroke"
    becu_anchor_MPa_cycles = [(400.0, 3.05e6), (240.0, 1.0e10)]  # ultrasonic VHCF test points (C17200)
    ratio_lo = N_BUDGET_CYCLES / mfr_life_hi
    ratio_hi = N_BUDGET_CYCLES / mfr_life_lo
    return {
        "part": "pogo spring (Mill-Max 0906, BeCu C17200)",
        "framing_A_full_stroke_actuation": {
            "mfr_rated_life_cycles": [mfr_life_lo, mfr_life_hi],
            "budget_cycles": N_BUDGET_CYCLES,
            "overrun_x": [round(ratio_lo, 0), round(ratio_hi, 0)],
            "verdict": "FAILS by this framing (budget is 630-6300x the manufacturer's rated full-stroke "
                       "actuation life) — but this framing is almost certainly WRONG for our load case: "
                       "the mfr spec is for full 1.5mm-travel plunge/mate cycles, and canon (01_01 §2) "
                       "already asserts the travel margin exists precisely so sway is absorbed as small "
                       "residual contact micro-motion, not full-stroke actuation.",
        },
        "framing_B_low_amplitude_stress_fatigue": {
            "anchor_points_MPa_cycles": becu_anchor_MPa_cycles,
            "vhcf_caveat": "C17200 shows NO strict flat endurance limit in VHCF (>1e7) — stress continues "
                           "to matter at very-high-cycle counts, unlike a classic steel fatigue limit.",
            "verdict": "PARTIAL — physically the right model (micro-motion, not full-stroke), and the "
                       "240 MPa -> 1e10-cycle anchor comfortably covers our 6.3e8 budget IF the true "
                       "working stress stays near or below that. But the actual stress at the REAL sway "
                       "deflection amplitude at the pogo tip is not computed anywhere in canon — missing "
                       "datum: spring wire diameter / rate + measured (or bench-derived) micro-deflection "
                       "amplitude during sway, not the full 1.5mm design travel.",
        },
        "closed": False,
        "verdict": "TWO mismatched framings, neither closed — see framing_A (fails, likely wrong model) "
                   "and framing_B (physically right, needs one missing datum) above.",
        "missing_datum": "spring wire diameter/rate (Mill-Max 0906 full mechanical dwg) + actual sway-"
                          "induced micro-deflection amplitude at the pogo contact (bench/field, not the "
                          "1.5mm design travel) — without it, framing B cannot be closed to a number.",
    }


def peek_barb_cyclic_verdict() -> dict:
    endurance_lo_MPa, endurance_hi_MPa = 30.0, 48.0  # unfilled PEEK, 1e6-1e7 cycles, 2 converging sources
    return {
        "part": "PEEK mechanical-lock barb (HW.26) — CYCLIC fatigue axis, distinct from HW.26's "
                "already-tracked STATIC cold-flow creep (time-based, not cycle-based — orthogonal "
                "failure mode, both need checking separately)",
        "endurance_limit_MPa": [endurance_lo_MPa, endurance_hi_MPa],
        "tested_range_cycles": [1.0e6, 1.0e7],
        "budget_cycles": N_BUDGET_CYCLES,
        "extrapolation_note": "budget is 1-2 orders beyond the tested range, but PEEK's endurance limit "
                               "is reported as a genuine flat fatigue limit (self-heating/crack-arrest "
                               "mechanism, not VHCF-style continued degradation like metals) — Pastukhov "
                               "et al. 2020 title is literally 'Physical background of the ENDURANCE "
                               "LIMIT in PEEK'. Treat 30 MPa as a defensible lower-bound acceptance "
                               "threshold, not a precisely-validated number at 6.3e8.",
        "closed": False,
        "verdict": "Reference endurance limit established (30-48 MPa @ 1e6-1e7 cycles) — see "
                   "missing_datum for what still closes it.",
        "missing_datum": "actual contact-stress amplitude at the mechanical-lock barb under sway-induced "
                          "cyclic load — this is exactly what HW.26's own pending ANSYS LS-DYNA FEA leg "
                          "computes; this script hands that FEA a numeric acceptance criterion (30-48 "
                          "MPa) to compare against instead of running blind.",
    }


def silpad_verdict() -> dict:
    return {
        "part": "Sil-Pad (Bergquist Sil-Pad 1500ST, HW.30) — 3rd spring in the Z-stack, 30-40% "
                "sustained compression per HW.30",
        "closed": False,
        "verdict": "NOT closeable by S-N literature review — this is a genuinely different failure "
                    "mechanism from spring/metal fatigue. Silicone elastomer degradation under sustained "
                    "compression is COMPRESSION-SET / STRESS-RELAXATION (creep), which is formulation-"
                    "specific (filler loading, cure system) and has no generic closed-form S-N curve in "
                    "the open literature the way BeCu or PEEK do. HW.30 already schedules the only "
                    "correct instrument for this axis: a bench Arrhenius-accelerated creep test "
                    "('Lifecycle test: Sil-Pad creep під 30-40% compression × 20 років'). This item does "
                    "not duplicate that leg — it confirms literature review cannot substitute for it.",
    }


def genipin_matrix_verdict() -> dict:
    return {
        "part": "genipin-chitosan-CNC matrix (Zone-1 anode enzyme-immobilization layer, 01_03 §2.1 "
                "Layer 4)",
        "closed": False,
        "category_mismatch": True,
        "verdict": "CORRECTION TO HW.43's OWN LIST, not a finding about the matrix. Canon (01_03 §2.1) "
                    "describes this as a ~10-20 um hydrogel COATING for enzyme immobilization on the "
                    "Zone-1 gyroid surface — it is not a load-bearing spring/structural element under "
                    "the 0.5-5 N axial mechanical-stress table (01_02 §2.2), so the 'endurance limit / "
                    "S-N' method this checkbox prescribes does not apply to it the way it does to a "
                    "metal spring or a PEEK barb. Its own cyclic-strain durability HAS already been "
                    "probed twice, and neither probe is an S-N measurement: (a) script "
                    "16_strain_cycling_md.py ran N=10 MD cycles at +/-5% strain and returned a "
                    "QUALITATIVE verdict ('pseudoplastic, PE drift 1.0%' — PIPELINE_STATUS.md row 16), "
                    "not a fatigue-life number, and MD cannot be extrapolated 8 orders of magnitude to "
                    "6.3e8 cycles by any known method; (b) the wet-lab bench spec (01_03 §3.4, 10 000 "
                    "cycles @ 0.1 Hz, ~28h) is the SAME 5-orders-short comparison HW.43's own head "
                    "paragraph already names as the open gap. No published S-N/endurance-limit data "
                    "exists for a crosslinked genipin-chitosan hydrogel coating (searched; none found). "
                    "The matrix's durability axis that actually matters is CHEMICAL/ENZYMATIC — does the "
                    "immobilized enzyme retain activity and does the crosslink network stay intact under "
                    "repeated sap exposure — and that axis is already tracked separately (HW.5 30-day "
                    "stability test, 01_03 MD stability checks), not by this checkbox.",
    }


def main() -> int:
    banner("HW.43 — Contact/elastic-part endurance-limit literature review (checkbox 2)")
    print(f"  Cycle budget under review: N = {N_BUDGET_CYCLES:.1e} (HW.43 head, 20yr x 1Hz)\n")

    parts = {
        "pogo_spring": pogo_spring_verdict(),
        "peek_barb_cyclic": peek_barb_cyclic_verdict(),
        "sil_pad": silpad_verdict(),
        "genipin_matrix": genipin_matrix_verdict(),
    }
    for v in parts.values():
        banner(v["part"])
        print(f"  closed: {v['closed']}")
        print(f"  verdict: {v['verdict']}\n" if "verdict" in v else "")

    banner("Verdict")
    print("  None of the four parts is fully CLOSED by literature review alone — and that is itself")
    print("  the honest result HW.43 asked for: an ACCEPTANCE UNIT per part, not a rubber-stamped pass.")
    print("  - Pogo spring: physically-right framing needs one missing datum (real sway micro-deflection).")
    print("  - PEEK barb: real 30-48 MPa threshold now exists for HW.26's pending FEA to check against.")
    print("  - Sil-Pad: correctly routes to the bench creep test HW.30 already schedules — no substitute.")
    print("  - Genipin matrix: REMOVE from the S-N framing (category mismatch); its axis is chemical, HW.5.")
    print("  bench (🔗) is needed for: pogo spring (if framing-B stress exceeds ~240 MPa) and PEEK barb")
    print("  (if HW.26 FEA finds barb stress above ~30 MPa) — NOT for Sil-Pad (bench needed regardless,")
    print("  already tracked) or genipin (different axis, HW.5, not this item).")

    out = {
        "method": "literature-cited endurance/fatigue-limit review, no FEA — matches HW.43's own request "
                  "for an acceptance UNIT per part, not a single pass/fail number.",
        "budget_cycles": N_BUDGET_CYCLES,
        "parts": parts,
        "sources": [
            "Mill-Max 0906 series product page (mill-max.com) — mechanical life 1e5-1e6 cycles at mid-stroke",
            "ScienceDirect — 'Specific very high cycle fatigue fracture mechanism in C17200 beryllium "
            "copper alloy caused by grain boundary precipitates and persistent slip bands' — VHCF anchor "
            "points (400 MPa/3.05e6 cyc, 240 MPa/1e10 cyc), no strict VHCF flat limit",
            "PMC/NCBI — 'Rotating Bending Fatigue Behaviors of C17200 Beryllium Copper Alloy at High "
            "Temperatures' — corroborating BeCu fatigue behaviour",
            "peekchina.com — 'Fatigue Strength of PEEK: A Guide for Gear Engineers' — unfilled PEEK "
            "endurance limit 30-40 MPa @ 1e6-1e7 cycles",
            "Pastukhov et al. 2020, J. Polym. Sci., 'Physical background of the endurance limit in "
            "poly(ether ether ketone)' (Wiley) — corroborating ~41-48 MPa @ 1e7 cycles, true flat limit",
            "docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md row 16 (script 16_strain_cycling_md.py, "
            "N=10 MD cycles, qualitative pseudoplastic verdict) — genipin-matrix existing cyclic probe",
        ],
        "verdict": "No part fully closed; each gets a named acceptance threshold or a named reason the "
                   "method does not apply, per-part detail in `parts`. Genipin-matrix removed from the "
                   "S-N framing as a category-mismatch correction to HW.43's own checkbox list.",
        "caveats": "All numeric thresholds are cited literature values, not computed physical facts for "
                   "OUR exact parts/geometry (00_06 §0 Validation Gate) — each 'missing_datum' field names "
                   "exactly what closes the remaining gap.",
    }
    json_path = OUT_DIR / "contact_endurance_check.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    return 0  # literature-review script: no pass/fail gate, exit 0 = ran to completion


if __name__ == "__main__":
    raise SystemExit(main())
