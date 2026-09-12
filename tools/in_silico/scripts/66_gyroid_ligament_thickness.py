#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.33 — the thinnest printed feature of a gyroid, per TOPOLOGY, at a fixed porosity.

WHY THIS EXISTS. `01_01 §5.5` carries a printability chain that is quoted across the tree:

    wall ~= 0.10 * period  ->  at an SLM floor of 200 um the minimum printable pore is ~1.2 mm
                           ->  the canonical 300->100 um bio-gradient is un-printable at 65 %

Every link of that chain was written 2026-06-20 (`03feed90`), i.e. in the SHEET era, and the word
`network` appears nowhere in it. The topology was ratified NETWORK on 2026-09-10 and applied in CAD
on 2026-09-11 (`33cd84f0`) -- and the ratification re-solved `wallParam` against the porosity target
without re-deriving the THICKNESS rule that the rest of the tree quotes. A sheet gyroid is a thin
shell wrapped around the minimal surface; a network gyroid is one solid labyrinth and has no wall at
all. The two therefore cannot share a thickness rule, and this script measures what the network rule
actually is.

⚠️ This script does NOT decide the pore-size target. That target is bio-hub / FEA-gated
(`01_01 §5.5`, `00_07` HW.33) and remains a founder judgment. What this script settles is only the
GROUND that the judgment was resting on.

TWO INDEPENDENT INSTRUMENTS, because one measurement is a claim and two are a check
(the `00_06 §0` Validation Gate wants a re-runnable number, not a recalled formula):

  (1) MORPHOLOGICAL OPENING by a ball of diameter d -- the same instrument `TopologyCrossChecks.cs`
      already uses for the as-printed check, so its result is comparable with the shipped metric.
      `t_open(f)` = the ball diameter at which the opening still leaves a fraction f of the metal.
      f = 0.5 is the median feature thickness.

  (2) HYDRAULIC DIAMETER `t_hyd = 4 * V_solid / S_solid`, with the specific surface taken from the
      SHIPPED PicoGK measurement rather than recomputed here -- an independently produced number
      from the other machine half. For a slab `t_hyd = 2 * t_wall`; for a ligament it is the
      diameter directly.

  (1) and (2) share no code and no assumption beyond the geometry itself. A third, purely analytic
  control exists for the SHEET branch only: the gyroid minimal surface has area ~= 3.091 * a^2 per
  cubic cell, so `t_wall = phi_solid * a / 3.091`. All three must agree on sheet or the model is
  wrong before it is ever pointed at network.

DECLARED CEILINGS -- read these before quoting any number below:
  * BOTH instruments are ISOTROPIC. An inscribed ball and a hydraulic diameter cannot see the
    MINIMUM NECK of an inclined, curved ligament, which is what an LPBF scan plane actually has to
    resolve. The true neck is <= the numbers here, so the thickness is an UPPER bound and the
    derived minimum printable pore is a LOWER bound -- i.e. this script errs OPTIMISTIC. How much
    is not measured, and closing that gap needs a directional (per-slice) width, not a better ball.
  * The geometry here is an IDEAL, infinite, ungraded gyroid. Every shipped SKU is graded in period
    (and `graded_porosity` in level), finite, and bored -- so the rim of a real part is thinner than
    its nominal cell implies. `01_02 §6` carries the measured per-SKU sub-floor fractions; those are
    the numbers for a PART, these are the numbers for a RULE.
  * The floor is treated as a pure XY feature size: no Z slicing, no supports, no trapped powder,
    no melt-pool physics. Same ceiling `TopologyCrossChecks.cs` declares for its own opening.
  * Voxel quantisation is +/- one cell (a/N). At N = 96 that is ~1 % of a period.
  * `stepped` is NOT covered. It is the one SKU still on the sheet formulation (`ZonedGyroid` uses
    the `|eq|` band), so the sheet column is the one that applies to it.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from scipy import ndimage

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lib.utils import banner

OUT_JSON = REPO_ROOT / "tools" / "in_silico" / "cache" / "mechanical" / "gyroid_ligament.json"

# --- inputs -----------------------------------------------------------------------------------
N = 96                      # voxels per period
POROSITY = 0.65             # `01_01 §5.2` nominal
GYROID_MINIMAL_SURFACE_A2 = 3.091   # literature: area of the gyroid minimal surface per cubic cell

# SLM / u-LPBF floors. ⚠️ 200 um is a DEFAULT, not a constant -- `01_01 §5.5` puts the real number
# in the CEM field `slm_min_wall_mm`, answered by the DMLS RFQ (00_07 HW.33).
FLOORS_UM = {"slm_default": 200.0, "u_lpbf": 100.0}

# Specific surface of the SHIPPED pine SKU, measured by PicoGK, NOT recomputed here.
# Provenance: tools/cad/out/anchor_zone1_pine.metrics.json (network, wallParam 0.10, voxel 0.10 mm).
SHIPPED_PINE = {
    "porosity": 0.6486965082613849,
    "specific_surface_mm2_per_mm3": 1.354304947575984,
    "core_period_mm": 2.5,
    "rim_period_mm": 2.0,
}
# Canon `01_02 §6` measured the sheet->network specific-surface ratio per SKU at 1.84-1.89x.
SHEET_OVER_NETWORK_SPECIFIC_SURFACE = 1.87


def gyroid_field(n: int) -> np.ndarray:
    lin = (np.arange(n) + 0.5) / n
    x, y, z = np.meshgrid(lin, lin, lin, indexing="ij")
    k = 2 * np.pi
    return (np.sin(k * x) * np.cos(k * y)
            + np.sin(k * y) * np.cos(k * z)
            + np.sin(k * z) * np.cos(k * x))


def mask_for(g: np.ndarray, param: float, topology: str) -> np.ndarray:
    """sheet: solid where |eq| < 0.5*w (a BAND).  network: solid where eq < level (a LEVEL)."""
    return np.abs(g) < 0.5 * param if topology == "sheet" else g < param


def solve_param(g: np.ndarray, target_solid: float, topology: str) -> float:
    lo, hi = (0.0, 1.5) if topology == "sheet" else (-1.5, 1.5)
    for _ in range(60):
        mid = 0.5 * (lo + hi)
        if mask_for(g, mid, topology).mean() < target_solid:
            lo = mid
        else:
            hi = mid
    return 0.5 * (lo + hi)


def opening_profile(mask: np.ndarray, n: int, max_r: int = 30) -> dict[float, float]:
    """{ball diameter in units of the period: surviving fraction of the phase}.

    Opening by a ball of radius r == dilate(erode(mask, ball_r), ball_r), and BOTH steps are
    exact level sets of a Euclidean distance transform:
        erode(mask, ball_r)  == { EDT(mask)      >  r }
        dilate(S,    ball_r) == { EDT(not S)     <= r }
    So the whole radius sweep costs two EDTs per radius instead of two ball convolutions, and the
    cost stops growing with r. (A direct `binary_opening` with an explicit ball is O(r^3) per
    radius and does not finish on this grid — measured, not assumed.)

    The array is tiled 3x3x3 first so the transforms see the true periodic neighbourhood; a
    `mode="wrap"` pad is not enough because a ball of radius r reaches r voxels in every direction.
    """
    total = int(mask.sum())
    tiled = np.tile(mask, (3, 3, 3))
    sl = tuple(slice(s, 2 * s) for s in mask.shape)
    edt_in = ndimage.distance_transform_edt(tiled)
    out: dict[float, float] = {}
    for r in range(1, max_r + 1):
        eroded = edt_in > r
        if not eroded.any():
            out[2.0 * r / n] = 0.0
            break
        kept = ndimage.distance_transform_edt(~eroded) <= r
        out[2.0 * r / n] = float((mask & kept[sl]).sum() / total)
        if out[2.0 * r / n] == 0.0:
            break
    return out


def thickness_at(profile: dict[float, float], keep: float) -> float:
    """Interpolate the ball diameter (in periods) at which `keep` of the metal survives."""
    items = sorted(profile.items())
    prev_d, prev_f = 0.0, 1.0
    for d, f in items:
        if f <= keep:
            if prev_f == f:
                return d
            return prev_d + (prev_f - keep) * (d - prev_d) / (prev_f - f)
        prev_d, prev_f = d, f
    return items[-1][0]


def pore_phase_size(mask: np.ndarray, n: int) -> float:
    """Median pore-phase feature size, same instrument applied to the complement."""
    return thickness_at(opening_profile(~mask, n), 0.5)


def main() -> int:
    phi_solid = 1.0 - POROSITY
    banner(f"Gyroid ligament thickness — phi_solid={phi_solid:.3f} (porosity {POROSITY:.0%}), N={N}")

    g = gyroid_field(N)
    result: dict[str, dict] = {}

    for topology in ("sheet", "network"):
        param = solve_param(g, phi_solid, topology)
        mask = mask_for(g, param, topology)
        measured_phi = float(mask.mean())
        prof = opening_profile(mask, N)
        t_med = thickness_at(prof, 0.5)
        t_p90 = thickness_at(prof, 0.10)     # diameter that only the thickest tenth survives
        pore = pore_phase_size(mask, N)

        entry = {
            "param": float(param),
            "param_meaning": ("wallParam as a BAND: |eq| < 0.5*w" if topology == "sheet"
                              else "wallParam as a LEVEL: eq < 0.5*(w-1); this script solves the "
                                   "level directly, so `param` here IS the level, not wallParam"),
            "measured_phi_solid": measured_phi,
            "t_median_over_period": t_med,
            "t_thickest_decile_over_period": t_p90,
            "pore_median_over_period": pore,
            "closure_check_t_plus_pore_over_period": t_med + pore,
        }

        if topology == "sheet":
            analytic = measured_phi / GYROID_MINIMAL_SURFACE_A2
            entry["t_analytic_over_period"] = analytic
            entry["analytic_vs_measured_ratio"] = t_med / analytic

        result[topology] = entry
        banner(f"  {topology:8s} level={param:+.4f}  phi={measured_phi:.4f}  "
               f"t/a={t_med:.4f}  pore/a={pore:.4f}")

    # --- instrument (2): hydraulic diameter from the SHIPPED specific surface -------------------
    phi_shipped = 1.0 - SHIPPED_PINE["porosity"]
    s_net = SHIPPED_PINE["specific_surface_mm2_per_mm3"]
    a_eff = 0.5 * (SHIPPED_PINE["core_period_mm"] + SHIPPED_PINE["rim_period_mm"])
    t_hyd_net = 4.0 * phi_shipped / s_net
    s_sheet = s_net * SHEET_OVER_NETWORK_SPECIFIC_SURFACE
    t_hyd_sheet_slab = 0.5 * (4.0 * phi_shipped / s_sheet)   # slab: t_hyd = 2 * wall

    cross = {
        "source": "tools/cad/out/anchor_zone1_pine.metrics.json (PicoGK, network, voxel 0.10 mm)",
        "graded_period_mean_mm": a_eff,
        "network_t_hyd_over_period": t_hyd_net / a_eff,
        "sheet_wall_from_specific_surface_over_period": t_hyd_sheet_slab / a_eff,
        "sheet_specific_surface_ratio_provenance":
            "01_02 §6 measured sheet->network specific surface at 1.84-1.89x per SKU; 1.87 used",
        "note": "a graded SKU has no single period, so the mean of core and rim is used; this is "
                "the coarsest assumption in the cross-check and it is why this instrument is a "
                "CHECK on the order of magnitude, not a second decimal place",
    }
    result["cross_check_hydraulic_diameter"] = cross

    # --- invert the floors ----------------------------------------------------------------------
    # 🔴 THE PERIOD IS THE ONLY UNAMBIGUOUS AXIS, and that is not pedantry — canon never wrote down
    # how "pore size" maps onto the period, which is exactly why its `1.2 mm` cannot be re-derived.
    # Back-solving `01_01 §5.5` (wall 0.10*a, floor 200 um => a = 2.0 mm => pore 1.2 mm) implies
    # pore = 0.60*a, a convention that appears in no line of canon. Our measured inscribed-sphere
    # convention gives 0.34*a (sheet) / 0.55*a (network). Both are reported below so that the
    # topology effect is never confused with a change of definition.
    CANON_IMPLIED_PORE_OVER_PERIOD = 0.60
    inversion: dict[str, dict] = {}
    for topology in ("sheet", "network"):
        t_over_a = result[topology]["t_median_over_period"]
        pore_over_a = result[topology]["pore_median_over_period"]
        per_floor = {}
        for name, floor_um in FLOORS_UM.items():
            period_um = floor_um / t_over_a
            per_floor[name] = {
                "floor_um": floor_um,
                "min_period_um": period_um,
                "min_pore_um_inscribed_sphere": period_um * pore_over_a,
                "min_pore_um_canon_implied_0p60": period_um * CANON_IMPLIED_PORE_OVER_PERIOD,
            }
        inversion[topology] = per_floor
    inversion["pore_convention_note"] = (
        "Two conventions, reported side by side on purpose. `inscribed_sphere` is what this script "
        "measures (median ball that fits in the pore phase). `canon_implied_0p60` reproduces the "
        "existing canon chain and exists only so the comparison is like-for-like — it is NOT a "
        "second measurement, and canon never states it."
    )
    result["floor_inversion"] = inversion

    # --- what this does to the canonical bio-gradient --------------------------------------------
    net_t = result["network"]["t_median_over_period"]
    gradient = {}
    for pore_um in (100.0, 150.0, 300.0, 500.0):
        for label, pore_over_a in (("inscribed_sphere", result["network"]["pore_median_over_period"]),
                                   ("canon_implied_0p60", CANON_IMPLIED_PORE_OVER_PERIOD)):
            period_um = pore_um / pore_over_a
            lig = period_um * net_t
            gradient[f"pore_{int(pore_um)}um__{label}"] = {
                "period_um": period_um,
                "network_ligament_um": lig,
                "clears_slm_default_floor": lig >= FLOORS_UM["slm_default"],
                "clears_u_lpbf_floor": lig >= FLOORS_UM["u_lpbf"],
            }
    result["canonical_bio_gradient_on_network"] = gradient

    # --- asserts on quantities with KNOWN bounds (cheapest class of LLM-error to catch) ----------
    for topology in ("sheet", "network"):
        e = result[topology]
        assert 0.0 < e["measured_phi_solid"] < 1.0, f"{topology}: phi out of (0,1)"
        assert abs(e["measured_phi_solid"] - phi_solid) < 0.005, f"{topology}: phi off target"
        assert 0.0 < e["t_median_over_period"] < 1.0, f"{topology}: t/a out of (0,1)"
        # Closure along a traverse — and the two topologies close DIFFERENTLY, which is itself the
        # structural fact this script is about. A network gyroid is BIcontinuous: one ligament plus
        # one pore labyrinth fills the period. A sheet gyroid is TRIcontinuous: the period contains
        # TWO walls and TWO separate pore labyrinths, so it closes at 2*(t + pore).
        # ⚠️ This assert fired on the first run with the bicontinuous form applied to both, i.e. it
        # caught a wrong model rather than a wrong number — which is the whole point of asserting a
        # quantity whose bound is known in advance.
        n_repeat = 1 if topology == "network" else 2
        closure = n_repeat * e["closure_check_t_plus_pore_over_period"]
        assert 0.75 < closure < 1.25, \
            f"{topology}: {n_repeat}*(t + pore) = {closure:.3f} does not close on the period"
    # The sheet branch has a closed form; the two must agree or the voxel model is wrong.
    assert 0.85 < result["sheet"]["analytic_vs_measured_ratio"] < 1.25, \
        "sheet: opening disagrees with the analytic minimal-surface form"

    ratio = net_t / result["sheet"]["t_median_over_period"]
    result["headline"] = {
        "sheet_t_over_period": result["sheet"]["t_median_over_period"],
        "network_t_over_period": net_t,
        "network_over_sheet": ratio,
        "verdict": (
            f"At {POROSITY:.0%} porosity a network ligament is {ratio:.1f}x thicker than a sheet "
            f"wall. The canon rule `wall ~= 0.10*period` is the SHEET rule and must not be quoted "
            f"for the shipped network SKUs. MEASURED here; the pore-size TARGET is not decided by "
            f"this script and stays bio-hub/FEA-gated."
        ),
        "ceilings": (
            "Both instruments are isotropic and cannot see the minimum neck of an inclined "
            "ligament, so the thickness is an UPPER bound and the minimum printable pore a LOWER "
            "bound -- this script errs optimistic by an unmeasured margin. Ideal infinite ungraded "
            "gyroid; per-PART numbers live in 01_02 §6. XY feature size only: no Z slicing, "
            "supports, trapped powder or melt-pool physics. `stepped` is out of scope -- it is "
            "still on the sheet formulation."
        ),
    }

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(result, indent=2))
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    banner(result["headline"]["verdict"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
