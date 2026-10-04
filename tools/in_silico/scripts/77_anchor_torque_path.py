#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
77 — Torque path onto the anchor's OWN axis, and what the press-fit friction carries (00_07 HW.26; the input
of the fork 01_01 §4.3 C).

QUESTION. §4.3 C (anti-rotation) may be dropped only on the ABSENCE of a torque path onto the anchor's axis —
not on friction, because at the floor of the interference window at +40 °C the friction is zero by the window's
own definition. Does a wind path exist, and what does the friction of the Zone-1 shank in the PEEK sleeve carry?

VERDICT (01_01 §4.3 C): the path exists, and C was dropped on its MAGNITUDE — Q2 below puts wind torsion at
micro-slip — not on its absence; the premise above is the question as first posed, not the rule that decided it.

MECHANISM (analytic — nothing fitted):
  * Trunk BENDING rotates a cross-section as a plane; for a radial anchor the material rotation about its own
    axis is the same at every depth (bending about the anchor axis: ω = −v′(z), independent of the radial
    coordinate), so bending puts no gradient along the anchor and no torque into it.
  * Trunk TORSION (an asymmetric crown in wind) differs. Saint-Venant torsion of a cylindrically orthotropic
    stem, u_θ = φ(z)·r, has a material rotation about the RADIAL axis ω_r = −½·r·φ′, which grows with the
    distance from the stem axis: wood near the bark turns about the anchor's axis more than wood at its tip,
    so two anchor parts coupled to wood at different depths are driven apart by ½·φ′·Δx.
  * A rigid cylinder of radius a turned by θ against an elastic medium carries 4π·G·a²·θ per unit length
    (plane strain, u_θ = θ·a²/ρ). With φ′ = τ_s/(G·R) for a surface torsional shear stress τ_s of a stem of
    radius R, G cancels — the same G_LT shears the L–T plane in both the stem's torsion and the part's turning —
    so the torque the shank↔sleeve interface must pass to keep the gyroid (deep) and the sleeve (shallow)
    turning together is
        T = 2π · S · (τ_s / R) · Δx,   S = (a1²·ℓ1 · a2²·ℓ2) / (a1²·ℓ1 + a2²·ℓ2).
  * Before slipping, the interface carries T_cap = μ · P_c · (2π·a_s·ℓ_s) · a_s, with P_c from the same Lamé as
    50/56 (lib.mechanics) on the ratified band, relaxed with lib.constants, at the assembly temperature and at the
    summer extreme. INVERSION: τ_s* = T_cap · R / (2π · S · Δx) — the stem-surface torsional shear stress at
    which the press-fit slips.
  * The same inequality bounds the PEEK: while the interface holds, the shear stress at the bore cannot exceed
    μ·P_c — so the sleeve's torsional loading under wind is capped by the friction itself; above it the
    interface slips by ½·φ′·Δx instead.

Q2 (2026-10-03, the same crown-pause exception): how LARGE the demand gets under wind — a bracket of named readings,
not a measurement of our stems. Ordinary wind: Kolbe, Pfenning & Schindler 2024 (Forest Ecology and Management
553:121638) measured a living PONDEROSA pine at mean wind 0.09–3.9 m/s and found torsion «hardly measurable in the
lower stem parts» — read from the abstract and highlights only (the full text is closed), so a direction, no number.
The CAP: the stem-surface torsional shear stress at the anchor cannot exceed the green wood's shear strength parallel
to grain, or the stem fails there; Skatter & Kučera 2000 (Forest Ecology and Management 135:97–103, abstract) predict
for four Scots pine stands that trees fail in torsion as often as in bending at critical wind, so the cap is a state
the population reaches; that it is reached higher up, where the stem is thinner, is OUR derivation (under one torque
τ = 2T/πR³), so the thicker base stays below it. At the cap, per pine that carries both Wood Handbook tables
(WH2010_PINES): the surface shear strain γ = τ_cap/G_LT, the gyroid-vs-sleeve rotation if the interface carries
nothing Δθ = ½·γ·Δx/R, the slip at the shank surface Δθ·a_s and its peak at the sleeve's bark end (the sleeve
follows its local wood: × (l2 + l1/2)/Δx for a rigid gyroid), the rigid-part demand, demand·τ_cap, and the radial
clearance below which a hex key (the largest the shank's own circle holds) would engage at all, c* = Δθ·s/(2√3) —
beside the swing the PEEK↔Ti expansion mismatch alone gives that clearance over the forest temperature range.

CAN show: that a wind torque path exists; the stress τ_s* at which friction gives way, per band edge, friction
coefficient, insertion depth and temperature; that at the band floor at +40 °C it gives way at ANY torsion; the
cap μ·P_c on the PEEK's torsional shear under wind; ESTIMATES at the cap (species means, rigid parts — directions
below) of the slip amplitude, of the demand a form lock would face and of the clearance at which the hex of
01_01 §4.3 C would engage.
CANNOT show: how large τ_s is under ORDINARY wind for our stems (Kolbe 2024 gives a direction, no number); any
value for P. sylvestris itself — the green values are US pines' (Wood Handbook 2010), and their G_LT/E_L is the
≈ 12 %-moisture ratio applied to green E_L (shear moduli fall toward saturation, so green G_LT is probably HIGH
here and the slip and c* LOW — the same direction as the species-MEAN strength, Wood Handbook Table 5–6 giving a
shear COV of 14 %, and the linear γ = τ/G, which green wood leaves before failure); the parts' OWN compliance beyond
the bark-end factor — the demand and τ_s* come from RIGID bodies coupled at their centroids, while the PEEK sleeve's
torsional decay length on wood is a few millimetres (`sleeve_torsional_decay_length_mm`): compliant parts take the
wood's twist by their own, so the real demand is LOWER and τ_s* a LOWER bound on GROSS slip, while the interface shear
gathers near the ends, where local slip starts earlier — the slip itself they redistribute (its bark-end peak is
bracketed), not lower; the gyroid's coupling at all — one narrow step drills the channel for anode and sleeve alike
(01_04 §3.1), Ø15, so the Ø11 gyroid sits in it with ≈ 2 mm of radial gap until the wood grows in; μ of the
shank↔sleeve pair (UNMEASURED — bracketed below; the liner tribology test asks the same PEEK↔Ti pair class); the
weaker coupling of the sleeve's outer part in dead bark (it moves the sleeve's centroid deeper and SHORTENS Δx,
i.e. LOWERS the demand — not modelled, so the demand here is an upper bound on that axis); the porous gyroid's
coupling (taken as a solid cylinder of its OD — an upper bound); the bayonet's own torque at locking (the collar
is not modelled — the second, EVENT path is named in the cache, not computed; today the flange reacts it only
through its seats, since the Zone-3 shank sits with clearance in the bore).

Run:  python tools/in_silico/scripts/77_anchor_torque_path.py      # stdlib only, seconds
"""
from __future__ import annotations

import itertools
import json
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    CACHE_DIR,
    DBH_MIN_CM,
    E_PEEK_PA,
    H7S6_INTERF_DIA_MAX_UM,
    H7S6_INTERF_DIA_MIN_UM,
    NU_PEEK,
    PEEK_RELAX_FLOOR,
    PEEK_RELAX_TAU_YEARS,
    R_INTERFACE_M,
    R_OUTER_M,
    REPO_ROOT,
    T_ASSEMBLY_C,
    T_FOREST_MAX_C,
    T_FOREST_MIN_C,
)
from lib.mechanics import thermal_interference, thick_wall_hoop
from lib.utils import banner

SI_DESCRIPTION = "Torque path onto the anchor's own axis under stem torsion, and the press-fit friction that carries it (by inversion)."  # its row in the paper SI (72): English, no repo jargon

OUT_DIR = CACHE_DIR / "mechanical"
OUT = OUT_DIR / "anchor_torque_path.json"
CEM = REPO_ROOT / "tools" / "cad" / "cem"
BUS_CACHE = OUT_DIR / "bus_mechanical.json"     # 55 — the lock insertion window (one home: MechanicalLock)

# ⚠️ UNMEASURED, private to this model: PEEK↔Ti in sap. A bracket, not a value — the decisive result (zero capacity
# at the band floor at +40 °C) does not depend on it; the τ_s* figures scale with it linearly.
MU_BRACKET = (0.1, 0.4)
SERVICE_YEARS = 20.0                            # years — the 20-yr column of the press-fit relaxation (01_01 §4.2)

# Q2 — green clear-wood values, private to this model: USDA Wood Handbook 2010 (FPL-GTR-190), Table 5–3a (green: bending
# MOE, shear strength parallel to grain) × Table 5–1 (G_LT/E_L at ≈ 12 % moisture) — ONLY the pines carrying both tables.
# ⚠️ P. sylvestris is in neither (the bracket's weakest link), and the 12 % ratio is applied to green E_L.
WH2010_PINES = {   # name: (G_LT/E_L at ≈ 12 %, bending MOE green MPa, shear ∥ grain green MPa)
    "loblolly": (0.081, 9700, 5.9),
    "lodgepole": (0.046, 7400, 4.7),
    "longleaf": (0.060, 11000, 7.2),
    "pond": (0.045, 8800, 6.5),
    "ponderosa": (0.115, 6900, 4.8),
    "red": (0.081, 8800, 4.8),
    "slash": (0.053, 10500, 6.6),
    "sugar": (0.113, 7100, 5.0),
    "western white": (0.048, 8200, 4.7),
}
WH2010_EL_OVER_BENDING_MOE = 1.10               # Table 5–1 footnote a: «EL may be approximated by increasing modulus of
                                                # elasticity values in Table 5–3 by 10%»
C_HEX_MAX_RADIAL_CLEARANCE_M = 0.05e-3          # 01_01 §4.3 C as written: «hex driver fit з ≤ 0.05 mm radial clearance»


def cem(name: str) -> dict:
    return json.loads((CEM / f"{name}.json").read_text(encoding="utf-8"))


def geometry() -> dict:
    """Read every dimension at RUNTIME — the CEM manifests and 55's cache — never type a mirror."""
    gy, sl = cem("anchor_zone1.pine"), cem("zone2_sleeve")
    window = json.loads(BUS_CACHE.read_text(encoding="utf-8"))["clearance_regime"]["lock_insertion_window_mm"]
    a1 = gy["outer_diameter_mm"] / 2.0 * 1e-3            # gyroid — coupled to sapwood over its length
    l1 = gy["length_mm"] * 1e-3
    a2 = (sl["bore_diameter_mm"] / 2.0 + sl["wall_thickness_mm"]) * 1e-3   # sleeve OD / 2 — coupled to the wound
    l2 = sl["length_mm"] * 1e-3
    # Depth from the bark surface: the sleeve spans [0, l2] (the flange rests on its end face at the bark), and
    # the gyroid continues below it — centroids at l2/2 and l2 + l1/2.
    dx = (l2 + l1 / 2.0) - l2 / 2.0
    s = (a1 ** 2 * l1 * a2 ** 2 * l2) / (a1 ** 2 * l1 + a2 ** 2 * l2)
    return {"gyroid_radius_m": a1, "gyroid_length_m": l1, "sleeve_outer_radius_m": a2, "sleeve_length_m": l2,
            "shank_radius_m": R_INTERFACE_M, "insertion_window_m": [w * 1e-3 for w in window],
            "centroid_separation_m": dx, "coupling_factor_S_m3": s,
            "stem_radius_m": DBH_MIN_CM / 2.0 * 1e-2}


def contact_pressure(dia_um: float, t_c: float) -> float:
    """Relaxed P_c (Pa) at temperature t_c for a DIAMETRAL band edge — 0 when the edge opens a gap."""
    alpha_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    delta = dia_um * 1e-6 / 2.0 + thermal_interference(t_c, T_ASSEMBLY_C, ALPHA_PEEK_1K, alpha_ti, R_INTERFACE_M)
    if delta <= 0.0:
        return 0.0
    p0 = thick_wall_hoop(delta, R_INTERFACE_M, R_OUTER_M, E_PEEK_PA, NU_PEEK)["P_c"]
    f = PEEK_RELAX_FLOOR + (1.0 - PEEK_RELAX_FLOOR) * math.exp(-SERVICE_YEARS / PEEK_RELAX_TAU_YEARS)
    return p0 * f


def grid(g: dict) -> list[dict]:
    demand_per_pa = 2.0 * math.pi * g["coupling_factor_S_m3"] * g["centroid_separation_m"] / g["stem_radius_m"]
    rows = []
    for t_c, (edge, dia), mu, l_s in itertools.product(
            (T_ASSEMBLY_C, T_FOREST_MAX_C),
            (("band floor", H7S6_INTERF_DIA_MIN_UM), ("band top", H7S6_INTERF_DIA_MAX_UM)),
            MU_BRACKET, g["insertion_window_m"]):
        p_c = contact_pressure(dia, t_c)
        a_s = g["shank_radius_m"]
        t_cap = mu * p_c * 2.0 * math.pi * a_s * l_s * a_s
        rows.append({"temperature_C": t_c, "band_edge": edge, "interference_diametral_um": dia, "mu": mu,
                     "insertion_mm": round(l_s * 1e3, 1), "P_c_relaxed_MPa": round(p_c / 1e6, 4),
                     "capacity_N_m": round(t_cap, 4),
                     "tau_s_star_MPa": round(t_cap / demand_per_pa / 1e6, 4),
                     "peek_bore_shear_cap_MPa": round(mu * p_c / 1e6, 4)})
    return rows


def verdict(g: dict, rows: list[dict]) -> dict:
    at = {t: [r for r in rows if r["temperature_C"] == t] for t in (T_ASSEMBLY_C, T_FOREST_MAX_C)}
    lo20 = min(r["tau_s_star_MPa"] for r in at[T_ASSEMBLY_C])
    hi20 = max(r["tau_s_star_MPa"] for r in at[T_ASSEMBLY_C])
    hi40 = max(r["tau_s_star_MPa"] for r in at[T_FOREST_MAX_C])
    floor40 = [r for r in at[T_FOREST_MAX_C] if r["band_edge"] == "band floor"]
    zero_at_floor = all(r["capacity_N_m"] == 0.0 for r in floor40)
    cap = max(r["peek_bore_shear_cap_MPa"] for r in rows)
    demand = 2.0 * math.pi * g["coupling_factor_S_m3"] * g["centroid_separation_m"] / g["stem_radius_m"]
    return {
        "wind_path_exists": True,
        "demand_N_m_per_MPa_of_tau_s": round(demand * 1e6, 4),
        "tau_s_star_MPa_at_assembly_temperature": [lo20, hi20],
        "tau_s_star_MPa_max_at_summer_extreme": hi40,
        "capacity_zero_at_band_floor_at_summer_extreme": zero_at_floor,
        "peek_bore_shear_cap_MPa_max": cap,
        "event_path": "the bayonet's locking and unlocking torque must be reacted by the flange: today only through its "
                      "seats (the sleeve's end face and the faced bark), because the Zone-3 shank is a Ø9 placeholder in "
                      "the Ø11 bore — clearance, so it passes none (01_01 §1, HW.8) — unless the flange is held by a tool "
                      "while the radome turns; the collar is not modelled, so the torque's size is not computed — a lever "
                      "exists (a tool hold), not a number",
        "text": (f"A wind torque path onto the anchor's own axis EXISTS: stem torsion turns wood at the bark more "
                 f"than at the tip (ω_r = −½·r·φ′), bending does not. The shank↔sleeve press-fit passes it until the "
                 f"stem-surface torsional shear stress reaches τ_s* = {lo20:.2f}–{hi20:.2f} MPa at "
                 f"{T_ASSEMBLY_C:.0f} °C (≤ {hi40:.2f} MPa at {T_FOREST_MAX_C:.0f} °C), "
                 f"{'and at the band floor at ' + format(T_FOREST_MAX_C, '.0f') + ' °C it carries NOTHING — the shank turns in the sleeve at any torsion' if zero_at_floor else 'and at the band floor it still carries a little'}. "
                 f"While it holds, the PEEK's shear at the bore is capped by the friction itself at μ·P_c ≤ {cap:.2f} MPa, "
                 f"so the torsional creep §4.3 C was written against cannot build beyond that cap; above it the "
                 f"interface slips by ½·φ′·Δx — a fretting question, not a creep one. "
                 f"«Drop C on the absence of a path» is therefore not available: the path exists."),
    }


def wind_bracket(g: dict, rows: list[dict]) -> dict:
    """Q2 — the demand at the CAP, per pine of WH2010_PINES: ESTIMATES, not bounds. High on the rigid-part and
    gyroid-coupling axes and on «the interface carries nothing»; low on the species-mean strength, the 12 %-ratio G_LT
    and the linear γ = τ/G (the module docstring names each). The base stays below the cap (τ = 2T/πR³)."""
    demand = 2.0 * math.pi * g["coupling_factor_S_m3"] * g["centroid_separation_m"] / g["stem_radius_m"]   # N·m per Pa
    a_s, r_stem, dx = g["shank_radius_m"], g["stem_radius_m"], g["centroid_separation_m"]
    hex_af = 2.0 * a_s * math.cos(math.radians(30.0))   # the largest hex the shank's own circle holds — C names no size
    alpha_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    thermal_swing = 0.5 * hex_af * (ALPHA_PEEK_1K - alpha_ti) * (T_FOREST_MAX_C - T_FOREST_MIN_C)
    forest_span_k = T_FOREST_MAX_C - T_FOREST_MIN_C
    species = []
    g_peek = E_PEEK_PA / (2.0 * (1.0 + NU_PEEK))
    j_sleeve = 0.5 * math.pi * (g["sleeve_outer_radius_m"] ** 4 - R_INTERFACE_M ** 4)
    for name, (glt_over_el, moe_mpa, shear_mpa) in WH2010_PINES.items():
        g_lt = glt_over_el * WH2010_EL_OVER_BENDING_MOE * moe_mpa * 1e6
        gamma = shear_mpa * 1e6 / g_lt
        dtheta = 0.5 * gamma * dx / r_stem
        # how far along the PEEK sleeve a twist dies out against the wood it is coupled to: λ = √(G·J / 4πG_LT·a²) —
        # a few mm against its 50 mm length, i.e. the sleeve follows its LOCAL wood and the rigid-body demand is high
        decay = math.sqrt(g_peek * j_sleeve / (4.0 * math.pi * g_lt * g["sleeve_outer_radius_m"] ** 2))
        species.append({"pine": name, "tau_cap_MPa": shear_mpa, "G_LT_green_est_MPa": round(g_lt / 1e6, 1),
                        "surface_shear_strain_at_cap": round(gamma, 6),
                        "rotation_gyroid_vs_sleeve_rad": round(dtheta, 7),
                        "slip_at_shank_surface_um": round(dtheta * a_s * 1e6, 2),
                        "rigid_part_demand_at_cap_N_m": round(demand * shear_mpa * 1e6, 3),
                        "hex_engages_below_radial_clearance_um": round(dtheta * hex_af / (2.0 * math.sqrt(3.0)) * 1e6, 2),
                        # the slice of temperature over which a key fitted to the engagement window stays engaged WITHOUT
                        # radial preload: the threshold and the PEEK↔Ti swing both scale with the hex size, so this does not
                        "engagement_band_without_preload_K": round(dtheta / (math.sqrt(3.0) * (ALPHA_PEEK_1K - alpha_ti)), 1),
                        "sleeve_torsional_decay_length_mm": round(decay * 1e3, 2)})
    tau_cap = [s["tau_cap_MPa"] for s in species]
    slip = [s["slip_at_shank_surface_um"] for s in species]
    demand_cap = [s["rigid_part_demand_at_cap_N_m"] for s in species]
    c_star = [s["hex_engages_below_radial_clearance_um"] for s in species]
    band = [s["engagement_band_without_preload_K"] for s in species]
    decay_mm = [s["sleeve_torsional_decay_length_mm"] for s in species]
    tau_star_max = max(r["tau_s_star_MPa"] for r in rows)
    rigid_exceeds = tau_star_max < min(tau_cap)
    # Without friction the compliant sleeve follows its local wood while the Ti part turns as its driver, the gyroid,
    # does: the slip then peaks at the sleeve's BARK end, over the lever from there to the gyroid's centroid (a rigid
    # gyroid) or to its top end (a fully compliant one), against the centroid lever Δx of the figures above.
    l1, l2 = g["gyroid_length_m"], g["sleeve_length_m"]
    peak_hi, peak_lo = (l2 + l1 / 2.0) / dx, l2 / dx
    c_star_peak_max = max(c_star) * peak_hi
    band_peak_max = max(band) * peak_hi
    c_hex_um = C_HEX_MAX_RADIAL_CLEARANCE_M * 1e6
    swing_um = thermal_swing * 1e6
    above = ", above every τ_s*" if rigid_exceeds else ""
    return {
        "ordinary_wind": {"tau_s_MPa": None,
                          "reading": "Kolbe, Pfenning & Schindler 2024 (doi:10.1016/j.foreco.2023.121638), living ponderosa "
                                     "pine, mean wind 0.09–3.9 m/s: torsion «hardly measurable in the lower stem parts» — "
                                     "abstract and highlights only (full text closed); no number"},
        "cap_reading": "Skatter & Kučera 2000 (doi:10.1016/S0378-1127(00)00301-7), four Scots pine stands, model: torsional "
                       "failure predicted as often as bending failure at critical wind — the population reaches the cap; that "
                       "it does so higher up the stem, and the thicker base stays below it, is our derivation (τ = 2T/πR³)",
        "values_source": "USDA Wood Handbook 2010 (FPL-GTR-190), Table 5–3a (green) × Table 5–1 (G_LT/E_L at ≈ 12 %), "
                         "E_L ≈ 1.1 × bending MOE (Table 5–1 footnote a); species-mean values (Table 5–6: shear COV 14 %)",
        "hex_across_flats_mm": round(hex_af * 1e3, 3),
        "species": species,
        "tau_cap_MPa_range": [min(tau_cap), max(tau_cap)],
        "slip_at_shank_surface_um_range": [min(slip), max(slip)],
        "rigid_part_demand_at_cap_N_m_range": [min(demand_cap), max(demand_cap)],
        "hex_engages_below_radial_clearance_um_range": [min(c_star), max(c_star)],
        "engagement_band_without_preload_K_range": [min(band), max(band)],
        "sleeve_torsional_decay_length_mm_range": [min(decay_mm), max(decay_mm)],
        "bark_end_peak_factor": {"rigid_gyroid": round(peak_hi, 3), "compliant_gyroid": round(peak_lo, 3),
                                 "reading": "free-interface slip at the sleeve's bark end ÷ the centroid figure: the sleeve "
                                            "follows its local wood (decay length ≪ its length), the Ti part turns as the "
                                            "gyroid's centroid (rigid) or its top end (fully compliant); the factors above "
                                            "are applied at the rigid-gyroid value"},
        "slip_at_bark_end_um_range": [round(min(slip) * peak_hi, 2), round(max(slip) * peak_hi, 2)],
        "hex_engages_below_radial_clearance_um_bark_end_range": [round(min(c_star) * peak_hi, 2), round(c_star_peak_max, 2)],
        "engagement_band_without_preload_K_bark_end_range": [round(min(band) * peak_hi, 1), round(band_peak_max, 1)],
        "strain_factor_to_engage_written_hex_at_bark_end": round(C_HEX_MAX_RADIAL_CLEARANCE_M * 1e6 / c_star_peak_max, 2),
        "strain_factor_to_fill_forest_span_at_bark_end": round(forest_span_k / band_peak_max, 2),
        "c_hex_max_radial_clearance_um": c_hex_um,
        "hex_clearance_thermal_swing_um": round(swing_um, 2),
        "thermal_range_C": [T_FOREST_MIN_C, T_FOREST_MAX_C],
        "rigid_part_demand_at_cap_exceeds_every_tau_s_star": rigid_exceeds,
        "text": (f"At the cap — the green pine's shear strength {min(tau_cap):.1f}–{max(tau_cap):.1f} MPa, species means, which "
                 f"the thicker stem base stays below — rigid parts with an interface that carried nothing would slip "
                 f"{min(slip):.1f}–{max(slip):.1f} µm apart at the shank surface (centroids {dx * 1e3:.0f} mm apart). The "
                 f"parts' compliance redistributes that slip rather than removing it: the PEEK sleeve's torsional decay "
                 f"length on wood is {min(decay_mm):.1f}–{max(decay_mm):.1f} mm against its {l2 * 1e3:.0f} mm, so it follows "
                 f"its local wood, and without friction the slip peaks at its bark end, up to {peak_hi:.2f}× the centroid "
                 f"figure for a rigid gyroid ({peak_lo:.2f}× for a fully compliant one) — "
                 f"{min(slip) * peak_hi:.1f}–{max(slip) * peak_hi:.1f} µm; the DEMAND, the moment that would stop the slip "
                 f"({min(demand_cap):.1f}–{max(demand_cap):.1f} N·m for rigid parts{above}), the compliant parts lower, "
                 f"taking the wood's twist by their own. A micron scale, not a turn. A hex key engages under that slip only "
                 f"below {min(c_star):.1f}–{max(c_star):.1f} µm of radial clearance at the centroid figure, "
                 f"{min(c_star) * peak_hi:.1f}–{c_star_peak_max:.1f} µm at the bark end (at the written maximum of 01_01 "
                 f"§4.3 C, {c_hex_um:.0f} µm, never — the strain would have to be "
                 f"{c_hex_um / c_star_peak_max:.1f}× larger), and the PEEK↔Ti mismatch alone moves that clearance by "
                 f"{swing_um:.1f} µm over {T_FOREST_MIN_C:.0f}…+{T_FOREST_MAX_C:.0f} °C: a key tight enough to engage stays "
                 f"preload-free over only {min(band):.0f}–{max(band):.0f} K of those {forest_span_k:.0f} "
                 f"({min(band) * peak_hi:.0f}–{band_peak_max:.0f} K at the bark end; a span independent of the hex size) and "
                 f"sits in radial interference colder than that — a press-fit hex whose flats relax as the round band does. "
                 f"Estimates: P. sylvestris is in neither table, and the species-mean strength, the 12 % G_LT/E_L ratio on "
                 f"green wood and the linear γ = τ/G push the slip and c* UP; the gyroid's 2 mm gap in the Ø15 channel "
                 f"pushes them DOWN (until the wood grows into it, nothing drives the gyroid at all)."),
    }


def main() -> int:
    g = geometry()
    rows = grid(g)
    v = verdict(g, rows)
    w = wind_bracket(g, rows)

    banner("HW.26 — torque path onto the anchor's own axis, by INVERSION (no wind torsion is measured in the tree)")
    print(f"  gyroid Ø{g['gyroid_radius_m'] * 2e3:.1f} × {g['gyroid_length_m'] * 1e3:.0f} mm · sleeve Ø"
          f"{g['sleeve_outer_radius_m'] * 2e3:.1f} × {g['sleeve_length_m'] * 1e3:.0f} mm · centroids "
          f"{g['centroid_separation_m'] * 1e3:.0f} mm apart · stem R {g['stem_radius_m'] * 1e2:.0f} cm (DBH {DBH_MIN_CM:.0f})")
    print(f"  demand: T = {v['demand_N_m_per_MPa_of_tau_s']:.3f} N·m per MPa of stem-surface torsional shear stress τ_s")
    for t in (T_ASSEMBLY_C, T_FOREST_MAX_C):
        print(f"\n  at {t:.0f} °C (P_c relaxed {SERVICE_YEARS:.0f} yr):")
        for r in (r for r in rows if r["temperature_C"] == t):
            print(f"    {r['band_edge']:<10s} {r['interference_diametral_um']:>4.0f} µm · μ {r['mu']:.1f} · "
                  f"ℓ_s {r['insertion_mm']:>4.1f} mm → P_c {r['P_c_relaxed_MPa']:.3f} MPa, cap {r['capacity_N_m']:.3f} N·m, "
                  f"τ_s* {r['tau_s_star_MPa']:.3f} MPa")
    print(f"\n  → {v['text']}")
    print(f"  ⊕ event path: {v['event_path']}")

    banner("Q2 — how large under wind: the CAP (green shear strength), US pines of the Wood Handbook 2010")
    print(f"  ordinary wind: {w['ordinary_wind']['reading']}")
    print(f"  hex of 01_01 §4.3 C taken as the largest the shank holds: across flats {w['hex_across_flats_mm']:.2f} mm")
    for s in w["species"]:
        print(f"    {s['pine']:<14s} τ_cap {s['tau_cap_MPa']:.1f} MPa · G_LT≈{s['G_LT_green_est_MPa']:>5.0f} MPa → slip "
              f"{s['slip_at_shank_surface_um']:>5.2f} µm · rigid demand {s['rigid_part_demand_at_cap_N_m']:.2f} N·m · hex engages "
              f"below {s['hex_engages_below_radial_clearance_um']:.2f} µm · preload-free band {s['engagement_band_without_preload_K']:.1f} K · "
              f"sleeve decay {s['sleeve_torsional_decay_length_mm']:.1f} mm")
    pk = w["bark_end_peak_factor"]
    print(f"  bark-end peak of the free-interface slip: ×{pk['rigid_gyroid']:.2f} (rigid gyroid) · ×{pk['compliant_gyroid']:.2f} "
          f"(compliant) → hex engages below {w['hex_engages_below_radial_clearance_um_bark_end_range'][1]:.2f} µm at most")
    print(f"  PEEK↔Ti swing of that clearance over {T_FOREST_MIN_C:.0f}…+{T_FOREST_MAX_C:.0f} °C: "
          f"{w['hex_clearance_thermal_swing_um']:.2f} µm")
    print(f"\n  → {w['text']}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "method": "analytic: Saint-Venant torsion of the stem (rotation gradient along a radial anchor) × rigid-inclusion "
                  "turning stiffness 4πGa² (G cancels), against Coulomb friction of the Lamé press-fit (lib.mechanics); "
                  "inversion for the stem-surface torsional shear stress at which the press-fit slips",
        "inputs": {"mu_bracket_UNMEASURED": list(MU_BRACKET), "service_years": SERVICE_YEARS,
                   "relax_floor": PEEK_RELAX_FLOOR, "relax_tau_years": PEEK_RELAX_TAU_YEARS},
        "geometry": {k: (round(v_, 6) if isinstance(v_, float) else v_) for k, v_ in g.items()},
        "grid": rows,
        "verdict": v,
        "wind_bracket": w,
        "ceilings": ["no measured stem torsion is read — τ_s* is a threshold, not a forecast",
                     "the wind bracket estimates the demand only at its CAP (green shear strength); under ordinary wind the "
                     "only reading is a direction (Kolbe 2024: hardly measurable at the stem base), no number",
                     "the cap's green values are US pines' species MEANS (Wood Handbook 2010; shear COV 14 %) — P. sylvestris "
                     "is in neither table — and their G_LT/E_L is the ≈ 12 %-moisture ratio applied to green E_L (green G_LT "
                     "probably HIGH, so slip and c* probably LOW); the strain is linear γ = τ/G",
                     "the demand and τ_s* treat both parts as RIGID bodies coupled at their centroids — the PEEK sleeve's "
                     "torsional decay length on wood is a few mm (`sleeve_torsional_decay_length_mm`), so the real demand is "
                     "LOWER and τ_s* a LOWER bound on gross slip; the slip is redistributed, not lowered — its bark-end peak "
                     "is carried at the rigid-gyroid factor; the Ø11 gyroid sits in the Ø15 channel with ≈ 2 mm of radial gap",
                     "μ unmeasured — bracketed",
                     "the sleeve's outer part in dead bark couples weaker — the demand here is an upper bound on that axis",
                     "the porous gyroid is coupled as a solid cylinder of its OD — an upper bound",
                     "the bayonet locking torque (event path) is named, not computed — the collar is not modelled"],
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"\n  cache → {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
