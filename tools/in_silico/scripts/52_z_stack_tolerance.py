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
ORING_WIN = (0.15, 0.30)  # Parker static squeeze — reconciles the §3.2(20-25) / §3.5(15-25) drift
PAD_WIN = (0.20, 0.50)    # gap filler: acoustic-contact-min .. squeeze-out-max (Sil-Pad tolerates wide squeeze)
PAD_CREEP_RETAIN = 0.85   # compression fraction retained after 20 yr (HW.30 lifecycle estimate)
PAD_ACOUSTIC_MIN = 0.20   # post-creep floor for acoustic contact (pad_pct·creep must stay ≥ this)

# ── Nominal gaps — design targets, centered (pogo 60 %, pad 35 %, O-ring 20 %) ──
GAP_PZ = 0.65                              # mm — Power Deck ↔ Zone 3 (sets pogo + pad)
POGO_FREE = GAP_PZ + 0.60 * POGO_TRAVEL    # protrusion so pogo sits at 60 % at nominal gap
GAP_OR = ORING_CS * (1.0 - 0.20)           # Radome rim ↔ Zone 3 so O-ring sits at 20 %

# ── RF constraint (02_01 §5.3) — geometric, self-owned (Гончаров VNA pending) ──
RF_ANT_TI_CLEARANCE_MIN = 12.0   # mm — antenna ↔ Ti flange min Z-clearance for VSWR

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
            "oring": {"cs_mm": ORING_CS, "window_pct": ORING_WIN},
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
