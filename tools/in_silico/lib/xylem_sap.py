# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Xylem sap composition profiles for different tree species.

Based on literature and 00_02 §1.1 (Xylem-Sim) protocol. Each profile defines
the ionic composition for OpenMM solvation to simulate realistic
xylem-like environments instead of generic TIP3P-FB + NaCl.

Usage:
    from lib.xylem_sap import SAP_PROFILES, get_sap_profile

    profile = get_sap_profile("pinus_sylvestris")
    # Use profile["ph"], profile["ionic_strength"], etc. in MD setup
"""
from __future__ import annotations

# ═══════════════════════════════════════════════════════════════════
# Xylem sap profiles by tree species
# ═══════════════════════════════════════════════════════════════════
# Sources:
#   Pinus sylvestris: 00_02 §1.1 (Xylem-Sim) (Cherkasy forest, Spriahailo data)
#   Quercus robur: Losso et al. 2016, Tree Physiology
#   Picea abies: Mayr et al. 2014, New Phytologist
#   Fagus sylvatica: Cochard 2006, Comptes Rendus Geoscience
#   Generic: simplified model used in current L2 MD baseline

SAP_PROFILES = {
    "pinus_sylvestris": {
        "common_name": "Scots pine (Cherkasy forest)",
        "ph": 5.0,
        "glucose_mM": 5.0,
        "ionic_strength_M": 0.015,
        "malic_acid_mM": 3.0,
        "oxalic_acid_mM": 1.0,
        "K_mM": 3.5,
        "Ca_mM": 1.0,
        "Mg_mM": 0.5,
        "Cl_mM": 0.5,
        "resin_acids": True,
        "notes": "Primary target species. pH 5.0-5.5 seasonally. Resin (abietic acid) significant.",
    },
    "pinus_sylvestris_winter": {
        "common_name": "Scots pine — winter dormancy",
        "ph": 4.5,
        "glucose_mM": 2.0,
        "ionic_strength_M": 0.008,
        "malic_acid_mM": 1.0,
        "oxalic_acid_mM": 0.5,
        "K_mM": 2.0,
        "Ca_mM": 0.5,
        "Mg_mM": 0.2,
        "Cl_mM": 0.3,
        "resin_acids": True,
        "notes": "Dormancy: reduced sap flow, lower sugar, lower pH.",
    },
    "pinus_sylvestris_summer": {
        "common_name": "Scots pine — active photosynthesis",
        "ph": 5.5,
        "glucose_mM": 15.0,
        "ionic_strength_M": 0.025,
        "malic_acid_mM": 5.0,
        "oxalic_acid_mM": 2.0,
        "K_mM": 5.0,
        "Ca_mM": 2.0,
        "Mg_mM": 1.0,
        "Cl_mM": 1.0,
        "resin_acids": True,
        "notes": "Peak photosynthesis: maximum sugar, higher pH, more ions.",
    },
    "quercus_robur": {
        "common_name": "English oak",
        "ph": 5.5,
        "glucose_mM": 10.0,
        "ionic_strength_M": 0.020,
        "malic_acid_mM": 2.0,
        "oxalic_acid_mM": 1.0,
        "K_mM": 4.0,
        "Ca_mM": 1.5,
        "Mg_mM": 0.8,
        "Cl_mM": 0.8,
        "resin_acids": False,
        "notes": "Deciduous. More tannins, less resin. Higher pH than pine.",
    },
    "picea_abies": {
        "common_name": "Norway spruce",
        "ph": 4.2,
        "glucose_mM": 4.0,
        "ionic_strength_M": 0.012,
        "malic_acid_mM": 2.0,
        "oxalic_acid_mM": 1.5,
        "K_mM": 2.5,
        "Ca_mM": 0.8,
        "Mg_mM": 0.3,
        "Cl_mM": 0.4,
        "resin_acids": True,
        "notes": "Most acidic conifer. Stress test for pH tolerance.",
    },
    "fagus_sylvatica": {
        "common_name": "European beech",
        "ph": 6.0,
        "glucose_mM": 8.0,
        "ionic_strength_M": 0.018,
        "malic_acid_mM": 1.5,
        "oxalic_acid_mM": 0.5,
        "K_mM": 3.0,
        "Ca_mM": 2.0,
        "Mg_mM": 1.0,
        "Cl_mM": 0.5,
        "resin_acids": False,
        "notes": "Most neutral pH. Tests upper pH boundary.",
    },
    "generic_simplified": {
        "common_name": "Simplified model (current L2 baseline)",
        "ph": 4.5,
        "glucose_mM": 10.0,
        "ionic_strength_M": 0.05,
        "malic_acid_mM": 0.0,
        "oxalic_acid_mM": 0.0,
        "K_mM": 0.0,
        "Ca_mM": 0.0,
        "Mg_mM": 0.0,
        "Cl_mM": 50.0,
        "resin_acids": False,
        "notes": "TIP3P-FB + NaCl 0.05M at pH 4.5. Used in all L2 runs to date.",
    },
}


def get_sap_profile(species: str) -> dict:
    """Get xylem sap profile for a tree species.

    Args:
        species: Key from SAP_PROFILES (e.g., "pinus_sylvestris")

    Returns:
        dict with pH, glucose_mM, ionic_strength_M, and individual ion concentrations.

    Raises:
        KeyError if species not found.
    """
    if species not in SAP_PROFILES:
        available = ", ".join(SAP_PROFILES.keys())
        raise KeyError(f"Unknown species '{species}'. Available: {available}")
    return SAP_PROFILES[species]


def list_profiles() -> None:
    """Print all available xylem sap profiles."""
    print(f"{'Species':<30s} {'Name':<35s} {'pH':>4s} {'Glucose':>8s} {'IS':>6s}")
    print("-" * 85)
    for key, p in SAP_PROFILES.items():
        print(f"{key:<30s} {p['common_name']:<35s} {p['ph']:>4.1f} {p['glucose_mM']:>7.1f}mM {p['ionic_strength_M']:>5.3f}M")


if __name__ == "__main__":
    list_profiles()
