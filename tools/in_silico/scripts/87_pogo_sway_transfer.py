#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""87 — what trunk sway does to the pogo contact: the transfer «stem motion → load through the pins» (00_07 HW.43,
the machine leg split off the measurement leg when the crown pause was lifted for measurements, founder 2026-10-13).

QUESTION. HW.43 asks whether each contact/spring part of the stack sits below its endurance limit under the sway cycle
budget (`62`). For the pogo spring, `59` framing B needs the stress amplitude at the REAL sway micro-motion, and the
tree had neither a model nor a measurement of how stem motion reaches the pins (01_02 §2.2, the boundary note).

MECHANISM (analytic — nothing fitted):
  * The capsule is a rigid appendage of the anchor: the radome rim sits on the Zone-3 flange face, the bayonet holds
    it (02_02 §4.3), and the board stack is clamped axially between the pogo springs below and the pocket gasket above
    (02_01 §3, поз. 24/25). Trunk BENDING rotates the anchor's cross-section as a plane and puts no gradient along it
    (77); trunk TORSION turns the deep anode against the sleeve about the anchor's own axis (77), i.e. it SPINS the
    centre pad under an on-axis pin and moves nothing at the outer ring, which is the flange itself. So stem motion
    reaches the pins only as the INERTIA of the stack and of the capsule — the stem's acceleration at the anchor plus
    gravity re-projected by the stem's tilt.
  * Spring wire stress is linear in the spring force, τ = 8·F·D·K_w/(π·d³) (02_02 §2.2), so the stress AMPLITUDE over
    the mean is the force ratio ΔF/F. Quasi-statically ΔF on the springs is at most the stack's inertial force m·a
    (all of it on ONE pin, none on the gasket in parallel), so
        τ_a / τ_m  ≤  r = m · a / F_pin,min
    — no spring drawing is needed for the RATIO; the drawing (node_pogo_rfq п. 1a) gives τ_m, and τ_a = r·τ_m.
  * Stem input at the anchor (Schindler & Kolbe 2020, Forests 11:145, doi 10.3390/f11020145 — one Scots pine,
    H 16.8 m, DBH 21.5 cm, tilt sensors at 0.1…12 m, the windiest interval of the day): the root plate does not tilt
    (h1 = 0.1 m: «close to zero over the entire M range»); the slope of tilt on low-pass momentum flux at h2 = 2.0 m is
    READ FROM FIGURE 9 (a plot — median and upper whisker, ±0.01); the text gives the strongest flux, > 31 m²/s², and
    the tilt it produced at 12 m, 12°. Tilt grows monotonically with height (Fig. 9), so for an anchor at ANY height
    h ≤ 2.0 m: θ ≤ θ2 = Sl2·M_max and the displacement x ≤ θ2·(h2 − h1) — the whole column below tilted by the most
    any of it tilts. The acceleration bound treats that whole swing as oscillating at the UPPER f0 reading (0.74 Hz):
        a ≤ (2π·f0)²·x + g·sin θ
    while the measured swing is mostly the NON-oscillatory component (NOS) — an over-estimate, kept on purpose.

CAN show: the force ratio r per unit stack mass, the stack mass at which r reaches 10 % and at which the preload of the
weakest pin would unload (r = 1), r at a deliberately absurd mass ceiling (the whole capsule envelope as solid copper);
whether the axial contact ever unloads; the spring + gasket stiffness the quasi-static step needs; whether the rim
(lug-face friction under the pogo push alone) holds the capsule against wind drag at the canopy-top gust plus the
capsule's inertia; the ratio of `55`'s per-cycle drag premise (µ·F_pogo, the pin sliding every cycle) to the inertial
lateral load. Also the stem's mean curvature between h1 and h2 and its surface strain — the range the field strain
sensor (01_02 §2.2) must cover.
CANNOT show: the stack MASS (no part masses in the tree — one scale reading); the spring's τ_m and stiffness (the
drawing, п. 1a); the O-ring's compression force (a named missing datum, 52) — the rim check runs on the pogo push
alone; anything about OUR stems — one smaller tree on one January day (canon hosts are DBH ≥ 38 cm), the Fig. 9 values
are a plot reading, and the 31 m²/s² interval is that site's «exceptional» day, not a design storm; vibration above the
first sway modes (branch modes, impacts) — not in the source; the THERMAL cycling of the pogo gap (radome vs stack vs
flange expansion, daily) — `52` has no thermal axis, and this script does not add one.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

SI_DESCRIPTION = ("How trunk sway reaches the spring contact pins of the sensor capsule: the inertia of the board stack as a "
                  "fraction of the spring preload, from published stem-tilt data of a Scots pine.")

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import (
    CACHE_DIR,
    INSTALL_ANGLE_DEG,
    POGO_PIN_COUNT,
    POGO_SPRING_FORCE_N,
    REPO_ROOT,
    SWAY_F0_HZ_HIGH_READING,
)
from lib.utils import banner

RADOME_CEM = REPO_ROOT / "tools/cad/cem/radome.json"
ZSTACK52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
OUT_JSON = CACHE_DIR / "mechanical" / "pogo_sway_transfer.json"

G = 9.80665                       # m/s²
# Schindler & Kolbe 2020 (Forests 11:145) — text values, and the two Figure-9 readings at h2 (a PLOT read, ±0.01)
H1_M, H2_M, H7_M = 0.1, 2.0, 12.0
FLUX_MAX_M2S2 = 31.0              # «low-pass filtered M … exceeded 31 m²/s²» (interval 68)
NOS7_AT_MAX_DEG = 12.0            # «NOS … reached values of 12°» at h7 in that interval
SLOPE7_INTERVAL68 = 0.37          # °/(m²/s²) — that interval's regression slope at h7 (Fig. 8c, text)
SLOPE2_READ = {"median": 0.03, "upper_whisker": 0.06}   # °/(m²/s²) at h2 — Figure 9, read from the plot
DBH_SOURCE_TREE_M = 0.215
# The pin's LOWEST force in canon: 60 ± 20 g at mid-stroke (0906-…-75 datasheet, 02_02 §2.2) — mid-stroke IS the
# 50–70 % working window; POGO_SPRING_FORCE_N (0.96, full travel) is the upper bound the push-off checks use.
PIN_FORCE_MIN_N = (60.0 - 20.0) * 1e-3 * G
MU_LOW = 0.2                      # the low end of 55's MU_SWEEP (Au↔Ti) — the friction the stick checks take
MU_55, F_POGO_55 = 0.3, 1.0       # 55's per-cycle drag premise: µ·F_pogo (55: MU_CONTACT, F_POGO_N)
# Deliberate ceilings, not estimates: the capsule envelope as solid copper (the densest bulk material in the stack),
# and drag at the canopy-top gust with Cd = 2 (above a flat plate normal to the flow).
RHO_CU_G_CM3 = 8.96
RHO_AIR, CD_CEILING, GUST_CANOPY_MS = 1.2, 2.0, 15.0
DAF_MARGIN = 10.0                 # quasi-static: the stack's own frequency ≥ 10 × f0 (amplification ≤ 1 %)


def stem_at_anchor(slope2: float) -> dict:
    theta2 = math.radians(slope2 * FLUX_MAX_M2S2)
    x = theta2 * (H2_M - H1_M)
    a_osc = (2 * math.pi * SWAY_F0_HZ_HIGH_READING) ** 2 * x
    a = a_osc + G * math.sin(theta2)
    kappa = theta2 / (H2_M - H1_M)
    return {"slope_deg_per_m2s2": slope2, "tilt_deg": round(math.degrees(theta2), 2),
            "displacement_mm": round(x * 1000, 1), "accel_m_s2": round(a, 3),
            "accel_oscillation_m_s2": round(a_osc, 3), "accel_gravity_tilt_m_s2": round(a - a_osc, 3),
            "mean_curvature_rad_per_m": round(kappa, 5),
            "surface_strain_microstrain_source_tree": round(kappa * DBH_SOURCE_TREE_M / 2 * 1e6, 0)}


def main() -> int:
    banner("HW.43 — trunk sway → load through the pogo pins (inertial transfer, force-ratio form)")
    cem = json.loads(RADOME_CEM.read_text(encoding="utf-8"))
    rim = json.loads(ZSTACK52.read_text(encoding="utf-8"))["rim_datum_creep"]
    d, h_cap = cem["dome_diameter_mm"], cem["cavity_height_mm"] + cem["bell_radius_mm"]   # 71's h over bark
    mass_ceiling_g = math.pi * (d / 2) ** 2 * h_cap * 1e-3 * RHO_CU_G_CM3
    area = d * h_cap * 1e-6
    drag = 0.5 * RHO_AIR * GUST_CANOPY_MS ** 2 * CD_CEILING * area

    control = SLOPE7_INTERVAL68 * FLUX_MAX_M2S2
    print(f"  control: interval-68 slope at 12 m × {FLUX_MAX_M2S2:.0f} m²/s² = {control:.1f}° (text: {NOS7_AT_MAX_DEG:.0f}°)")
    print(f"  pin force floor {PIN_FORCE_MIN_N:.2f} N (60−20 g, mid-stroke) · f0 {SWAY_F0_HZ_HIGH_READING} Hz · "
          f"mass ceiling {mass_ceiling_g:.0f} g (Ø{d} × {h_cap} mm of copper)")

    rows = {}
    for name, s2 in SLOPE2_READ.items():
        st = stem_at_anchor(s2)
        a = st["accel_m_s2"]
        r_per_g = a * 1e-3 / PIN_FORCE_MIN_N
        lateral_static = G * math.cos(math.radians(INSTALL_ANGLE_DEG))
        rows[name] = {
            "stem_at_anchor_h_le_2m": st,
            "axial_force_ratio_per_gram": round(r_per_g, 5),
            "stack_mass_g_for_ratio_10pct": round(0.10 / r_per_g, 1),
            "stack_mass_g_for_preload_unload": round(1.0 / r_per_g, 0),
            "axial_force_ratio_at_mass_ceiling": round(r_per_g * mass_ceiling_g, 3),
            "spring_plus_gasket_k_N_per_mm_needed_at_mass_ceiling":
                round(mass_ceiling_g * 1e-3 * (2 * math.pi * DAF_MARGIN * SWAY_F0_HZ_HIGH_READING) ** 2 / 1000, 3),
            "lateral_cyclic_over_static_gravity": round(a / lateral_static, 3),
            "rim_demand_over_lug_friction_pogo_only": round(
                (drag + mass_ceiling_g * 1e-3 * a) / (MU_LOW * POGO_PIN_COUNT * PIN_FORCE_MIN_N), 2),
            "o_ring_force_N_that_closes_the_rim_check": round(
                max(0.0, (drag + mass_ceiling_g * 1e-3 * a) / MU_LOW - POGO_PIN_COUNT * PIN_FORCE_MIN_N), 2),
            "stack_mass_g_where_inertia_reaches_55_drag": round(MU_55 * F_POGO_55 / (a * 1e-3), 0),
        }
        r = rows[name]
        print(f"\n  [{name}: slope at 2 m {s2} °/(m²/s²)] tilt ≤ {st['tilt_deg']}° · x ≤ {st['displacement_mm']} mm · "
              f"a ≤ {a} m/s² ({st['accel_oscillation_m_s2']} sway + {st['accel_gravity_tilt_m_s2']} tilt)")
        print(f"    stem curvature 0.1–2 m {st['mean_curvature_rad_per_m']} rad/m → "
              f"{st['surface_strain_microstrain_source_tree']:.0f} µε at the source tree's DBH")
        print(f"    τ_a/τ_m ≤ {r['axial_force_ratio_per_gram'] * 100:.2f} % per gram of stack · 10 % at "
              f"{r['stack_mass_g_for_ratio_10pct']} g · preload unloads at {r['stack_mass_g_for_preload_unload']:.0f} g · "
              f"{r['axial_force_ratio_at_mass_ceiling'] * 100:.0f} % at the {mass_ceiling_g:.0f} g ceiling")
        print(f"    quasi-static needs k(springs ∥ gasket) ≥ "
              f"{r['spring_plus_gasket_k_N_per_mm_needed_at_mass_ceiling']} N/mm at the ceiling · lateral cyclic/static "
              f"{r['lateral_cyclic_over_static_gravity']} (no reversal while < 1)")
        print(f"    rim: demand / lug friction on the pogo push alone = {r['rim_demand_over_lug_friction_pogo_only']} "
              f"(drag {drag:.3f} N at {GUST_CANOPY_MS:.0f} m/s, Cd {CD_CEILING}) — closed by any O-ring force ≥ "
              f"{r['o_ring_force_N_that_closes_the_rim_check']} N · 55's per-cycle drag needs a "
              f"{r['stack_mass_g_where_inertia_reaches_55_drag']:.0f} g stack")

    out = {
        "question": "HW.43 — the transfer «stem motion → load through the pogo pins»",
        "source": "Schindler & Kolbe 2020, Forests 11:145, doi 10.3390/f11020145 (one P. sylvestris, H 16.8 m, "
                  "DBH 21.5 cm; 30 Jan 2019, 3-s gust 15.0 m/s at canopy top)",
        "inputs": {"h1_m": H1_M, "h2_m": H2_M, "flux_max_m2s2": FLUX_MAX_M2S2,
                   "slope_at_h2_read_from_figure9": SLOPE2_READ, "f0_upper_hz": SWAY_F0_HZ_HIGH_READING,
                   "pin_force_min_N": round(PIN_FORCE_MIN_N, 3), "pin_count": POGO_PIN_COUNT,
                   "pin_force_full_travel_N": POGO_SPRING_FORCE_N, "mu_low": MU_LOW,
                   "install_angle_deg": INSTALL_ANGLE_DEG, "capsule_envelope_mm": [d, h_cap],
                   "mass_ceiling_g": round(mass_ceiling_g, 1), "drag_ceiling_N": round(drag, 3),
                   "rim_required_initial_clamp_N_from_52": rim["required_initial_clamp_N"]},
        "controls": {"slope_times_flux_reproduces_12m_tilt": {"deg": round(control, 2), "text_deg": NOS7_AT_MAX_DEG}},
        "by_slope_reading": rows,
        "missing_data": ["stack mass — one scale reading of the assembled board stack",
                         "spring drawing (node_pogo_rfq п. 1a): τ_m and stiffness",
                         "O-ring compression force (52's named missing datum)"],
        "not_computed": "thermal cycling of the pogo gap (radome · stack · flange expansion, daily) — no thermal axis in 52",
        "verdict": ("Stem motion reaches the pins only as inertia: the spring force amplitude over its preload is r = m·a/F, "
                    "per gram of stack; τ_a = r·τ_m once the drawing gives τ_m. The field number the pogo needs is the "
                    "stem ACCELERATION at the anchor and the stack MASS, not a micro-deformation measured at the pin."),
    }
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
