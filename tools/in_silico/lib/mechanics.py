# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared mechanics helpers for the anchor Ti↔PEEK press-fit (HW.3.IS).

Thick-wall (Lamé) relations for a compliant sleeve (PEEK) shrink-/press-fit on a much stiffer
shaft (Ti, treated rigid). Pure stdlib (math) — no numpy — so the unit tests stay CI-safe
(stdlib-only, like test_cache_integrity). Scripts 50/51 hold legacy partial forms of these;
the unified script 56 uses this core, and the eventual 50/51 retrofit (scope-B) folds onto it.
"""
from __future__ import annotations

import math


def thick_wall_hoop(delta_radial: float, b: float, c: float, e_mod: float, nu: float) -> dict:
    """Rigid-inner / free-outer thick-wall Lamé for a sleeve (bore b, OD c) on a rigid shaft.

    `delta_radial` = radial interference (m); >0 = interference (sleeve stretched onto the shaft).
    Returns the BORE stress state (r = b, the critical location — max tensile hoop), in Pa:
      P_c       contact pressure at the bore
      sigma_t   tangential (hoop) stress at r=b — the max tensile value
      sigma_r   radial stress at r=b = −P_c
      sigma_vm  von Mises at r=b (plane stress, σ_z ≈ 0)

    Rigid-inner contact pressure  P_c = E·δ / (b·[(c²+b²)/(c²−b²) + ν])  (Shigley/RoyMech — the
    E_shaft ≫ E_sleeve limit of the two-cylinder interference fit; mirrors script 50 contact_pressure).
    Bore hoop  σ_t = P_c·(c²+b²)/(c²−b²)  (Lamé cylinder under internal pressure P_c, free outer).
    """
    ratio = (c * c + b * b) / (c * c - b * b)          # (k²+1)/(k²−1)
    p_c = e_mod * delta_radial / (b * (ratio + nu))
    sigma_t = p_c * ratio
    sigma_r = -p_c
    sigma_vm = math.sqrt(sigma_t * sigma_t - sigma_t * sigma_r + sigma_r * sigma_r)
    return {"P_c": p_c, "sigma_t": sigma_t, "sigma_r": sigma_r, "sigma_vm": sigma_vm}


def thermal_interference(t_c: float, t_assembly_c: float, alpha_sleeve: float,
                         alpha_shaft: float, b: float) -> float:
    """Extra RADIAL interference (m) from differential CTE when cooled below assembly temp.

    δ_therm = (α_sleeve − α_shaft)·(T_assembly − T)·b. >0 when T < T_assembly: the higher-CTE
    sleeve (PEEK) shrinks onto the shaft (Ti) → grips harder, so the interference grows in the cold.
    """
    return (alpha_sleeve - alpha_shaft) * (t_assembly_c - t_c) * b
