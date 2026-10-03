#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
77 — Torque path onto the anchor's OWN axis, and what the press-fit friction carries (00_07 HW.26; the input
of the fork 01_01 §4.3 C).

QUESTION. §4.3 C (anti-rotation) may be dropped only on the ABSENCE of a torque path onto the anchor's axis —
not on friction, because at the floor of the interference window at +40 °C the friction is zero by the window's
own definition. Does a wind path exist, and what does the friction of the Zone-1 shank in the PEEK sleeve carry?

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

CAN show: that a wind torque path exists; the stress τ_s* at which friction gives way, per band edge, friction
coefficient, insertion depth and temperature; that at the band floor at +40 °C it gives way at ANY torsion; the
cap μ·P_c on the PEEK's torsional shear under wind.
CANNOT show: how large τ_s is under real wind for our stems (no measured value is read here — Kolbe, Pfenning &
Schindler 2024, Forest Ecology and Management 553:121638, measured torsional vibration of a living PONDEROSA
pine — not our P. sylvestris — and is NOT read); the slip AMPLITUDE in microns (it needs G_LT of green pine,
which is not in the tree); μ of the shank↔sleeve pair (UNMEASURED — bracketed below; the liner tribology test
asks the same PEEK↔Ti pair class); the
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


def main() -> int:
    g = geometry()
    rows = grid(g)
    v = verdict(g, rows)

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
        "ceilings": ["no measured stem torsion is read — τ_s* is a threshold, not a forecast",
                     "slip amplitude not computed — needs G_LT of green pine, not in the tree",
                     "μ unmeasured — bracketed",
                     "the sleeve's outer part in dead bark couples weaker — the demand here is an upper bound on that axis",
                     "the porous gyroid is coupled as a solid cylinder of its OD — an upper bound",
                     "the bayonet locking torque (event path) is named, not computed — the collar is not modelled"],
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"\n  cache → {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
