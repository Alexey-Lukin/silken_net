#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 — Mechanical check of the central bus rod (buckling + sway fatigue), the second-half de-risk of
the monolithic-bus idea after the thermal bridge (script 54).

A monolithic Ti bus is a thin Ø1.3 rod rising from the anode shank, through the PEEK gap and the cathode
bore, to the pogo pad. Two mechanical questions the monolithic idea raises (01_01 §4.1 / 00_07 HW.34):
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

Per-alloy endurance is keyed to yield (σ_e ≈ k·σ_y) from lib ALLOY_PROPERTIES — ties HW.34 ↔ HW.24.
No FEA — slender-beam closed form (Euler buckling + cantilever bending + S-N endurance ratio).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import ALLOY_PROPERTIES, CACHE_DIR, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "mechanical"
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ── Bus geometry (mm) — mirrors script 54 / CEM (bus threads the Ø1.3 cathode bottleneck) ──
D_BUS = 1.3
# Free (laterally UNSUPPORTED) cantilever length in each case:
L_FREE_UNSUP = 36.0   # mm — no liner: gap 6 + cathode bore ~14 + flange/pad standoff ~16 = full protrusion
L_FREE_SUP = 6.0      # mm — liner supports the bore run → only the PEEK gap is unsupported

# ── Loads ──
F_POGO_N = 1.0        # N — pogo spring force on the rod tip (~100 g, 02_02 §2.2)
MU_CONTACT = 0.3      # Au↔Ti dry sliding friction (the cyclic lateral drag = µ·F_pogo); swept 0.2-0.5
MU_SWEEP = (0.2, 0.3, 0.4, 0.5)

# ── Material / fatigue ──
E_TI = 110e9          # Pa — Ti-6Al-4V Young's modulus (β-Ti lower, but E barely moves buckling here)
# Endurance limit ≈ fatigue ratio × yield, then knocked down for AS-PRINTED SLM surface/porosity
# (HIP + machining recovers most of it — the bus tip is gold-plated/finished anyway). Conservative.
ENDURANCE_OVER_YIELD = 0.45   # wrought-Ti fatigue ratio (σ_e/σ_y ≈ 0.4-0.5)
AS_PRINTED_DERATE = 0.5       # SLM as-built knockdown (rough surface + sub-surface porosity)

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


def endurance_MPa(yield_MPa: float) -> float:
    return ENDURANCE_OVER_YIELD * AS_PRINTED_DERATE * yield_MPa


def main() -> int:
    banner("HW.34 — Bus rod mechanical check (buckling + sway fatigue)")
    print(f"  Rod Ø{D_BUS:.1f} mm; free length unsupported {L_FREE_UNSUP:.0f} mm (no liner) vs "
          f"supported {L_FREE_SUP:.0f} mm (liner = the insulation, HW.34 sub-2)")
    print(f"  Pogo {F_POGO_N:.1f} N axial; cyclic lateral drag = µ·F_pogo (µ={MU_CONTACT:.1f}); "
          f"σ_e ≈ {ENDURANCE_OVER_YIELD:.2f}·{AS_PRINTED_DERATE:.2f}·σ_y (as-printed)")

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
    print(f"  {'alloy (= bus, monolithic)':<24s} {'σ_y':>5s} {'σ_e':>5s} {'SF unsup':>9s} {'SF sup':>8s} {'unsup life':>11s}")
    print(f"  {'-'*74}")
    alloy_rows = []
    for name, props in sorted(ALLOY_PROPERTIES.items(), key=lambda kv: -kv[1]["yield_MPa"]):
        sy = props["yield_MPa"]
        se = endurance_MPa(sy)
        sf_unsup = se / sig_unsup
        sf_sup = se / sig_sup
        life = "∞ (>SF 2)" if sf_unsup >= 2.0 else "⚠ marginal"
        print(f"  {name:<24s} {sy:>5.0f} {se:>5.0f} {sf_unsup:>8.1f}× {sf_sup:>7.1f}× {life:>11s}")
        alloy_rows.append({"alloy": name, "yield_MPa": sy, "endurance_MPa": round(se, 1),
                           "sf_unsupported": round(sf_unsup, 2), "sf_supported": round(sf_sup, 2),
                           "unsupported_infinite_life": bool(sf_unsup >= 2.0)})
    print("\n  → SUPPORTED (liner): comfortable infinite life for EVERY alloy (SF 9-26×). UNSUPPORTED:")
    print("    fine for the strong alloyed Ti (4V/7Nb/β/15Zr, SF ~4×) but MARGINAL for soft Ta/CP-Ti")
    print("    (SF <2.5×). Same ranking as the thermal side → the leading bake-off candidates win on both.")

    # ── 3. Robustness: sweep the friction coefficient (the cyclic-load assumption) ──
    banner("Robustness — friction-coefficient sweep (the cyclic-drag assumption)")
    sy_4v = ALLOY_PROPERTIES["Ti-6Al-4V"]["yield_MPa"]
    se_4v = endurance_MPa(sy_4v)
    print(f"  {'µ':>5s} {'F_lat (N)':>10s} {'σ unsup':>9s} {'σ sup':>8s} {'SF unsup(4V)':>13s} {'SF sup(4V)':>11s}")
    print(f"  {'-'*60}")
    mu_rows = []
    for mu in MU_SWEEP:
        fl = mu * F_POGO_N
        su = bending_stress_MPa(fl, L_FREE_UNSUP)
        ss = bending_stress_MPa(fl, L_FREE_SUP)
        print(f"  {mu:>5.1f} {fl:>10.2f} {su:>7.1f} MPa {ss:>5.1f} MPa {se_4v / su:>11.1f}× {se_4v / ss:>10.1f}×")
        mu_rows.append({"mu": mu, "f_lat_N": round(fl, 3), "sigma_unsup_MPa": round(su, 1),
                        "sigma_sup_MPa": round(ss, 1), "sf_unsup_4v": round(se_4v / su, 2),
                        "sf_sup_4v": round(se_4v / ss, 2)})
    print("  → Even at µ=0.5 the SUPPORTED rod stays SF ≫ 2 (4V). The liner is the robust mitigation;")
    print("    bare-cantilever margin erodes with µ → don't run the bus unsupported.")

    # ── Verdict ──
    banner("Verdict")
    p_cr_unsup = euler_buckling_N(L_FREE_UNSUP)
    print(f"  1. Buckling: non-issue (P_cr {p_cr_unsup:.0f} N ≫ 1 N pogo, SF {p_cr_unsup / F_POGO_N:.0f}× even unsupported).")
    print("  2. Sway fatigue: the LINER (= the insulation, HW.34 sub-2) is load-bearing — supported gives")
    print("     SF 9-26× (infinite life, all alloys); unsupported is marginal for soft Ta/CP-Ti.")
    print("  3. So the SAME part fixes three things at once — short-circuit isolation, lateral support,")
    print("     and fatigue. Monolithic is mechanically sound WITH the bore liner; do NOT run it bare.")
    print("  4. Per-alloy fatigue margin tracks yield (β-Ti/15Zr/4V > CP-Ti > Ta) — SAME ranking as the")
    print("     thermal bridge → the leading bake-off candidates (HW.24) win on both axes, no tension.")
    print("  5. Caveat: the cyclic-load amplitude (pogo friction + PEEK flex) is an ESTIMATE — the real")
    print("     sway spectrum is bench/field (00_02). Comparative supported-vs-unsupported is robust.")

    out = {
        "method": "slender-beam closed form — Euler buckling (fixed-free) + cantilever tip-load bending "
                  "+ S-N endurance ratio (σ_e ≈ k·σ_y, as-printed derate). No FEA.",
        "geometry_mm": {"bus_dia": D_BUS, "free_len_unsupported": L_FREE_UNSUP, "free_len_supported": L_FREE_SUP},
        "loads": {"pogo_axial_N": F_POGO_N, "friction_mu": MU_CONTACT, "lateral_drag_N": MU_CONTACT * F_POGO_N},
        "fatigue_model": {"endurance_over_yield": ENDURANCE_OVER_YIELD, "as_printed_derate": AS_PRINTED_DERATE},
        "buckling": {"p_cr_unsupported_N": round(euler_buckling_N(L_FREE_UNSUP), 1),
                     "p_cr_supported_N": round(euler_buckling_N(L_FREE_SUP), 1),
                     "sf_unsupported": round(euler_buckling_N(L_FREE_UNSUP) / F_POGO_N, 1)},
        "bending_stress_MPa": {"unsupported": round(sig_unsup, 1), "supported": round(sig_sup, 1)},
        "per_alloy_fatigue": alloy_rows,
        "friction_sweep": mu_rows,
        "verdict": ("Monolithic bus is mechanically sound WITH the bore liner: buckling non-issue (SF "
                    f"{p_cr_unsup / F_POGO_N:.0f}x); the liner doubles as lateral support → fatigue SF 9-26x (infinite life, all "
                    "alloys). UNSUPPORTED is marginal for soft Ta/CP-Ti. Liner = insulation + support + "
                    "fatigue-fix in one (HW.34 sub-2). Per-alloy margin tracks yield = same ranking as "
                    "thermal → leading HW.24 candidates win on both."),
        "caveats": "cyclic-load amplitude (pogo friction + PEEK flex) is an estimate; real sway spectrum "
                   "is bench/field (00_02). Comparative supported-vs-unsupported + per-alloy ranking robust.",
    }
    json_path = OUT_DIR / "bus_mechanical.json"
    json_path.write_text(json.dumps(out, indent=2, default=str))
    banner(f"✅ Saved {json_path.relative_to(REPO_ROOT)}")
    # gate: supported rod must clear infinite life for the baseline alloy (sanity, not a product pass/fail)
    return 0 if endurance_MPa(sy_4v) / sig_sup >= 2.0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
