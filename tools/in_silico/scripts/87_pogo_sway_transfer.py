#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""87 — what trunk sway does to the pogo contact: the transfer «stem motion → load through the pins» (00_07 HW.43,
the machine leg split off the measurement leg when the crown pause was lifted for measurements, founder 2026-10-13).

QUESTION. HW.43 asks whether each contact/spring part of the stack sits below its endurance limit under the sway cycle
budget (`62`). For the pogo spring, `59` framing B needs the stress amplitude at the REAL sway micro-motion, and the
tree had neither a model nor a measurement of how stem motion reaches the pins (01_02 §2.2, the boundary note).

ANSWER'S FORM (revised 2026-10-13 after the adversarial pass — the first version priced one path as if it were all).
Sway reaches the pins along four paths; this file computes two to a number and states the other two as conditions:
  (A) RIM — PREMISE of everything below. The capsule is carried as one body with the flange only while the rim's lug-face
      friction holds the capsule's own WEIGHT (the anchor axis is near-horizontal, so the weight is a lateral load on
      the rim) plus the wind drag on the radome plus its inertia. That friction rests on the push-off forces — the pogo
      pair and the O-ring, whose force canon does not have (`52`'s named missing datum). Computed: the O-ring force at
      which the rim holds. If it does not hold, the capsule shifts inside the collar's running clearance and the pins
      SLIDE over the pads — the regime `55`'s per-cycle drag µ·F_pogo describes.
  (B) STACK INERTIA, with the rim holding. Wire stress is linear in spring force (τ = 8·F·D·K_w/(π·d³), 02_02 §2.2), so
      the amplitude over the mean is a force ratio. For a COAXIAL clamp ΔF ≤ m·a (all of it on the weakest pin, none on
      the gasket in parallel), and the static axial share of the weight, m·g·sin(install angle), lowers the MEAN — taken
      with the sign that unloads the pins. ⚠️ The clamp is NOT coaxial: two pins below, one eccentric gasket above
      (02_01 поз. 24), so a lateral acceleration at the stack's centre-of-mass height adds a force PAIR m·a·h/s that
      m·a does not bound; h and s are layout quantities (HW.9) and are not in the tree — named, not computed.
  (C) CENTRE PAD, mass-independent. Trunk bending puts a longitudinal strain κ·y across the stem, and its Poisson part
      μ_LR·ε_L is a RADIAL strain that varies along a radial anchor lying in the bending plane: the deep anode (the bus
      wire's root) and the flange at the bark follow wood strained differently, so the wire tip moves ALONG the pin
      axis against the flange by up to Δu = μ_LR · ε_s · Δx (ε_s the stem-surface strain, Δx the depth span; rigid parts
      each following their local wood — a ceiling, as in `77`). Over the pin's working compression this is the force
      ratio Δu/x_min for a spring without barrel preload (with preload, smaller). This is the term in the strain the
      field gauge measures (01_02 §2.2, ⚖️ 2026-09-23).
  (D) THERMAL, not sway — the daily expansion mismatch of radome, stack, sleeve and wire moves the same contacts; not
      computed here (`00_07` HW.43, its own leg).

STEM INPUT (Schindler & Kolbe 2020, Forests 11:145, doi 10.3390/f11020145 — one Scots pine, H 16.8 m, DBH 21.5 cm, tilt
sensors at 0.1…12 m, the windiest interval of one January day, gusts to 15.0 m/s at the canopy top): the root plate
does not tilt («close to zero over the entire M range» at 0.1 m); the slope of tilt on low-pass flux at 2.0 m is READ
FROM FIGURE 9 (median and upper whisker — a whisker is not the maximum); the strongest flux is > 31 m²/s². Tilt grows
monotonically with height, so for an anchor at any h ≤ 2.0 m: θ ≤ θ2, x ≤ θ2·(h2 − h1), and the surface strain is
taken from the mean curvature between 0.1 and 2.0 m at the source tree's DBH. The acceleration takes the whole swing
as oscillating at the upper f0 (0.74 Hz): (2π·f0)²·x + g·sin θ. ⚠️ That is NOT a proven bound in either direction —
the swing measured is mostly non-oscillatory (NOS), but the oscillatory share at 2 m is not published (only at
0.1/4/8/12 m), at the base OS carries ~40 % of the variance, and higher modes weigh as f². Flux scales as U², so a
storm twice as windy multiplies every stem quantity here roughly ×4: these numbers describe that one day.

CAN show: the O-ring force the rim needs (A); the inertial force ratio per gram of stack and the masses at which it
reaches 10 % and at which the weakest pin unloads, static weight included (B, coaxial clamp); the centre-pad ratio per
1000 µε of stem-surface strain and at the source day's strain (C); the quasi-static stiffness the stack's suspension
needs. CANNOT show: the stack mass, its centre-of-mass height and the pin spacing (layout, HW.9); the O-ring force; the
spring's τ_m and rate (the drawing, node_pogo_rfq п. 1a); μ_LR of green P. sylvestris (the bracket is nine pines at
≈ 12 % moisture, Wood Handbook 2021 Table 5–2); anything about OUR stems (canon hosts are DBH ≥ 38 cm, larger than the
one source tree); the thermal path (D).
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import (
    CACHE_DIR,
    INSTALL_ANGLE_DEG,
    POGO_PIN_COUNT,
    REPO_ROOT,
    SWAY_F0_HZ_HIGH_READING,
)
from lib.utils import banner


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


s52 = _load("zstack52", "52_z_stack_tolerance.py")
s55 = _load("bus55", "55_bus_mechanical.py")

SI_DESCRIPTION = ("How trunk sway reaches the spring contact pins of the sensor capsule: a rim-friction condition, the "
                  "inertia of the board stack and a Poisson term at the centre pad, from published stem-tilt data of a "
                  "Scots pine.")

RADOME_CEM = REPO_ROOT / "tools/cad/cem/radome.json"
ZSTACK52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
TORQUE77 = CACHE_DIR / "mechanical" / "anchor_torque_path.json"
OUT_JSON = CACHE_DIR / "mechanical" / "pogo_sway_transfer.json"

G = 9.80665                       # m/s²
# Schindler & Kolbe 2020 (Forests 11:145) — text values, and the two Figure-9 readings at h2 (a PLOT read, ±0.01)
H1_M, H2_M = 0.1, 2.0
FLUX_MAX_M2S2 = 31.0              # «low-pass filtered M … exceeded 31 m²/s²» (interval 68)
NOS7_AT_MAX_DEG = 12.0            # «NOS … reached values of 12°» at h7 in that interval
SLOPE7_INTERVAL68 = 0.37          # °/(m²/s²) — that interval's regression slope at h7 (text; R² = 1.00 on the same data)
SLOPE2_READ = {"median": 0.03, "upper_whisker": 0.06}   # °/(m²/s²) at h2 — Figure 9, read from the plot
DBH_SOURCE_TREE_M = 0.215
# μ_LR of the nine pines in Wood Handbook 2021 (FPL-GTR-282) ch. 5 Table 5–2, ≈ 12 % moisture; P. sylvestris absent.
MU_LR_PINES = {"loblolly": 0.328, "lodgepole": 0.316, "longleaf": 0.332, "pond": 0.280, "ponderosa": 0.337,
               "red": 0.347, "slash": 0.392, "sugar": 0.356, "western white": 0.329}
# The pin's LOWEST force in canon: 60 ± 20 g at mid-stroke (0906-…-75 datasheet, 02_02 §2.2 — the series is HW.9's pick,
# so this is the datasheet's floor, not yet a canonical one); mid-stroke IS the 50–70 % working window.
PIN_FORCE_MIN_N = (60.0 - 20.0) * 1e-3 * G
X_PRELOAD_MIN_MM = s52.POGO_WIN[0] * s52.POGO_TRAVEL      # the smallest working compression, 50 % of the travel
MU_LOW = min(s55.MU_SWEEP)        # the low end of 55's swept Au↔Ti friction — the friction the stick checks take
# Deliberate ceilings, not estimates: the capsule envelope as solid copper (the densest bulk material in it), and drag
# at the canopy-top gust with Cd = 2 (above a flat plate normal to the flow).
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
            "nos_displacement_mm": round(x * 1000, 1), "accel_m_s2": round(a, 3),
            "accel_oscillation_m_s2": round(a_osc, 3), "accel_gravity_tilt_m_s2": round(a - a_osc, 3),
            "mean_curvature_rad_per_m": round(kappa, 5),
            "surface_strain_microstrain_source_tree": round(kappa * DBH_SOURCE_TREE_M / 2 * 1e6, 0)}


def main() -> int:
    banner("HW.43 — trunk sway → load through the pogo pins: rim condition · stack inertia · centre-pad Poisson term")
    cem = json.loads(RADOME_CEM.read_text(encoding="utf-8"))
    rim = json.loads(ZSTACK52.read_text(encoding="utf-8"))["rim_datum_creep"]
    geo77 = json.loads(TORQUE77.read_text(encoding="utf-8"))["geometry"]
    d, h_cap = cem["dome_diameter_mm"], cem["cavity_height_mm"] + cem["bell_radius_mm"]   # 71's h over bark
    mass_ceiling_g = math.pi * (d / 2) ** 2 * h_cap * 1e-3 * RHO_CU_G_CM3
    drag = 0.5 * RHO_AIR * GUST_CANOPY_MS ** 2 * CD_CEILING * d * h_cap * 1e-6
    sin_i, cos_i = math.sin(math.radians(INSTALL_ANGLE_DEG)), math.cos(math.radians(INSTALL_ANGLE_DEG))
    push = POGO_PIN_COUNT * PIN_FORCE_MIN_N
    dx_nominal, dx_ceiling = geo77["centroid_separation_m"], geo77["gyroid_length_m"] + geo77["sleeve_length_m"]
    mu_lr_lo, mu_lr_hi = min(MU_LR_PINES.values()), max(MU_LR_PINES.values())

    control = SLOPE7_INTERVAL68 * FLUX_MAX_M2S2
    print(f"  control (units only — the slope was regressed on the same interval): 0.37 × 31 = {control:.1f}° vs 12°")
    print(f"  pin force floor {PIN_FORCE_MIN_N:.3f} N · working compression ≥ {X_PRELOAD_MIN_MM:.2f} mm · µ {MU_LOW} · "
          f"capsule ceiling {mass_ceiling_g:.0f} g (Ø{d} × {h_cap} mm of copper) · drag ceiling {drag:.3f} N")

    rows = {}
    for name, s2 in SLOPE2_READ.items():
        st = stem_at_anchor(s2)
        a = st["accel_m_s2"]
        eps = st["surface_strain_microstrain_source_tree"] * 1e-6
        m = mass_ceiling_g * 1e-3
        demand = math.hypot(m * G * cos_i, drag + m * a)          # weight ⊥ wind + inertia, worst case at right angles
        oring_needed = max(0.0, demand / MU_LOW - push)
        per_g = a * 1e-3 / PIN_FORCE_MIN_N
        mean_at_ceiling = PIN_FORCE_MIN_N - m * G * sin_i
        poisson_per_1000 = {"mu_lr_lo_dx_nominal": round(mu_lr_lo * 1e-3 * dx_nominal * 1e3 / X_PRELOAD_MIN_MM, 4),
                            "mu_lr_hi_dx_ceiling": round(mu_lr_hi * 1e-3 * dx_ceiling * 1e3 / X_PRELOAD_MIN_MM, 4)}
        du_lo, du_hi = mu_lr_lo * eps * dx_nominal * 1e6, mu_lr_hi * eps * dx_ceiling * 1e6
        rows[name] = {
            "stem_at_anchor_h_le_2m": st,
            "A_rim": {"capsule_weight_N_at_ceiling": round(m * G, 3),
                      "demand_N_at_ceiling": round(demand, 3),
                      "o_ring_force_N_that_holds_the_rim_at_ceiling": round(oring_needed, 2),
                      "note": "pogo push alone does not hold even the capsule's weight; below this O-ring force the "
                              "capsule shifts inside the collar clearance and the pins slide (55's regime)"},
            "B_inertia_coaxial": {
                "force_ratio_per_gram": round(per_g, 5),
                "stack_mass_g_for_ratio_10pct": round(0.10 / per_g, 1),
                "stack_mass_g_where_weakest_pin_unloads": round(PIN_FORCE_MIN_N / ((a + G * sin_i) * 1e-3), 0),
                "ratio_at_mass_ceiling_over_reduced_mean": (round(m * a / mean_at_ceiling, 3)
                                                            if mean_at_ceiling > 0 else None),
                "unloads_at_mass_ceiling": m * (a + G * sin_i) >= PIN_FORCE_MIN_N,
                "pair_factor_h_over_s": "NOT COMPUTED — layout (HW.9): pin spacing and the stack's centre-of-mass height",
                "suspension_k_N_per_mm_needed_at_ceiling":
                    round(m * (2 * math.pi * DAF_MARGIN * SWAY_F0_HZ_HIGH_READING) ** 2 / 1000, 3)},
            "C_centre_pad_poisson": {
                "ratio_per_1000_microstrain": poisson_per_1000,
                "axial_shift_um_at_source_strain": [round(du_lo, 1), round(du_hi, 1)],
                "ratio_at_source_strain": [round(du_lo * 1e-3 / X_PRELOAD_MIN_MM, 4),
                                           round(du_hi * 1e-3 / X_PRELOAD_MIN_MM, 4)]},
        }
        r = rows[name]
        b, c = r["B_inertia_coaxial"], r["C_centre_pad_poisson"]
        print(f"\n  [{name}: slope at 2 m {s2}] tilt ≤ {st['tilt_deg']}° · NOS x ≤ {st['nos_displacement_mm']} mm · "
              f"a ≈ {a} m/s² · stem strain {st['surface_strain_microstrain_source_tree']:.0f} µε (source DBH)")
        print(f"    (A) rim holds the copper ceiling only with an O-ring force ≥ "
              f"{r['A_rim']['o_ring_force_N_that_holds_the_rim_at_ceiling']} N (weight {m * G:.2f} N, drag {drag:.3f} N)")
        print(f"    (B) {b['force_ratio_per_gram'] * 100:.2f} %/g · 10 % at {b['stack_mass_g_for_ratio_10pct']} g · weakest pin "
              f"unloads at {b['stack_mass_g_where_weakest_pin_unloads']:.0f} g (static share in) · copper ceiling unloads: "
              f"{b['unloads_at_mass_ceiling']} · × pair factor h/s NOT computed")
        print(f"    (C) centre pad Δu {c['axial_shift_um_at_source_strain'][0]}…{c['axial_shift_um_at_source_strain'][1]} µm → "
              f"{c['ratio_at_source_strain'][0] * 100:.1f}…{c['ratio_at_source_strain'][1] * 100:.1f} % of the working "
              f"compression; per 1000 µε {c['ratio_per_1000_microstrain']['mu_lr_lo_dx_nominal'] * 100:.2f}…"
              f"{c['ratio_per_1000_microstrain']['mu_lr_hi_dx_ceiling'] * 100:.2f} %")

    out = {
        "question": "HW.43 — the transfer «stem motion → load through the pogo pins»",
        "source": "Schindler & Kolbe 2020, Forests 11:145, doi 10.3390/f11020145 (one P. sylvestris, H 16.8 m, "
                  "DBH 21.5 cm; 30 Jan 2019, 3-s gust 15.0 m/s at canopy top) · μ_LR: Wood Handbook 2021 "
                  "(FPL-GTR-282) ch. 5 Table 5–2, nine pines at ≈ 12 % moisture",
        "inputs": {"h1_m": H1_M, "h2_m": H2_M, "flux_max_m2s2": FLUX_MAX_M2S2,
                   "slope_at_h2_read_from_figure9": SLOPE2_READ, "f0_upper_hz": SWAY_F0_HZ_HIGH_READING,
                   "pin_force_min_N": round(PIN_FORCE_MIN_N, 3), "pin_count": POGO_PIN_COUNT,
                   "working_compression_min_mm": X_PRELOAD_MIN_MM, "mu_low": MU_LOW,
                   "install_angle_deg": INSTALL_ANGLE_DEG, "capsule_envelope_mm": [d, h_cap],
                   "mass_ceiling_g": round(mass_ceiling_g, 1), "drag_ceiling_N": round(drag, 3),
                   "mu_lr_pines": MU_LR_PINES, "depth_span_m": {"nominal_centroids_77": dx_nominal,
                                                               "ceiling_full_depth_77": dx_ceiling},
                   "dbh_source_tree_m": DBH_SOURCE_TREE_M,
                   "rim_required_initial_clamp_N_from_52": rim["required_initial_clamp_N"]},
        "controls": {"slope_times_flux_reproduces_12m_tilt": {"deg": round(control, 2), "text_deg": NOS7_AT_MAX_DEG,
                                                              "note": "units only — same-interval regression"}},
        "by_slope_reading": rows,
        "missing_data": ["O-ring compression force (52's named missing datum) — decides (A)",
                         "stack mass, centre-of-mass height and pin spacing — layout HW.9 / a scale reading",
                         "spring drawing (node_pogo_rfq п. 1a): τ_m and rate",
                         "μ_LR of green P. sylvestris; stem strain and acceleration at anchor height on host-size pines"],
        "not_computed": "(D) thermal cycling of the pogo contacts — `00_07` HW.43, its own leg",
        "verdict": ("Sway reaches the pins along four paths. With the rim holding (an O-ring force the canon lacks), "
                    "two are a fraction of the preload: the stack's inertia (per gram, × a pair factor the layout sets) "
                    "and a mass-independent centre-pad term in the stem's surface strain; without it, the pins slide "
                    "(55's regime). The input describes one January day of one smaller tree."),
    }
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
