# SPDX-License-Identifier: AGPL-3.0-or-later
"""Shared Michaelis-Menten / pH forms for the L4 kinetics scripts (30, 30b).

One home for the forms themselves — the CONSTANTS they consume stay in `constants.py`, and the
absolute results stay in each script's cache. Pure stdlib, so the unit tests stay CI-safe
(stdlib-only, like `mechanics.py`, whose precedent this follows: a formula used by two scripts is
a drift surface until it has one implementation — §When Modifying #25).
"""
from __future__ import annotations

from .constants import PH_KINETICS_SYGMUND


def mm_velocity(k_cat: float, km_mM: float, glucose_mM: float) -> float:
    """Michaelis-Menten velocity in the units of `k_cat` (per-enzyme turnover, s⁻¹)."""
    return k_cat * glucose_mM / (km_mM + glucose_mM)


def ph_current_ratio(glucose_mM: float, form: str) -> float:
    """Current ratio pH 5.5 / pH 7.5 at this glucose, from ONE enzyme form's own MM pair.

    The ratio is **[S]-dependent** because both k_cat and K_M move with pH, and they move in
    OPPOSITE directions for the current: k_cat falls, K_M falls too (higher affinity), so the two
    partly cancel. Reporting a single factor would hide that.

    ⚠️ Source bounds travel with the number (`constants.PH_KINETICS_SYGMUND`): Sygmund 2011 Table 3
    is the FREE enzyme with a ferrocenium acceptor at 30 °C — not our immobilised Os-polymer
    electrode — so a consumer prints this BESIDE its model and never folds it in (⚖️ 2026-09-18).
    Both forms (`wt` ⊥ `rec`) are kept because they disagree, and the disagreement IS the bracket.
    """
    km_lo, kcat_lo = PH_KINETICS_SYGMUND[form][5.5]
    km_hi, kcat_hi = PH_KINETICS_SYGMUND[form][7.5]
    return mm_velocity(kcat_lo, km_lo, glucose_mM) / mm_velocity(kcat_hi, km_hi, glucose_mM)
