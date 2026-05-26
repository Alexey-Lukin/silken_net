"""Shared DFT utility functions for L3 quantum chemistry scripts."""
from __future__ import annotations

import numpy as np
from .constants import HARTREE_TO_EV


def extract_frontier(mf, mol) -> tuple[float, float]:
    """Extract HOMO and LUMO energies (in Hartree) from converged SCF."""
    if mol.spin == 0:
        nocc = mol.nelectron // 2
        homo = mf.mo_energy[nocc - 1]
        lumo = mf.mo_energy[nocc]
    else:
        nocc_a, nocc_b = mol.nelec
        ho_a = mf.mo_energy[0][nocc_a - 1]
        ho_b = mf.mo_energy[1][nocc_b - 1]
        homo = max(ho_a, ho_b)
        lu_a = mf.mo_energy[0][nocc_a]
        lu_b = mf.mo_energy[1][nocc_b]
        lumo = min(lu_a, lu_b)
    return float(homo), float(lumo)


def frontier_to_ev(homo_ha: float, lumo_ha: float) -> dict:
    """Convert Hartree HOMO/LUMO to eV with gap."""
    return {
        "HOMO_Ha": homo_ha,
        "LUMO_Ha": lumo_ha,
        "HOMO_eV": homo_ha * HARTREE_TO_EV,
        "LUMO_eV": lumo_ha * HARTREE_TO_EV,
        "gap_eV": (lumo_ha - homo_ha) * HARTREE_TO_EV,
    }


def cascade_verdict(homo_donor_eV: float, lumo_acceptor_eV: float) -> dict:
    """Marcus cascade test: is electron transfer downhill?"""
    delta = homo_donor_eV - lumo_acceptor_eV
    favorable = delta > 0
    direction = "✅ DOWNHILL" if favorable else "❌ UPHILL"
    return {
        "donor_homo_eV": homo_donor_eV,
        "acceptor_lumo_eV": lumo_acceptor_eV,
        "delta_eV": delta,
        "favorable": favorable,
        "verdict": direction,
    }


def marcus_rate(t_ij_eV: float, lambda_reorg: float = 0.7,
                dG: float = 0.0, temp_K: float = 298.15) -> float:
    """Marcus electron transfer rate constant (s⁻¹).

    Args:
        t_ij_eV: electronic coupling (hopping integral) in eV
        lambda_reorg: reorganization energy in eV (default 0.7)
        dG: driving force in eV (default 0, symmetric)
        temp_K: temperature in Kelvin
    """
    HBAR = 6.582119569e-16   # eV·s
    KB = 8.617333262e-5       # eV/K
    prefactor = (2 * np.pi / HBAR) * t_ij_eV**2
    denom = np.sqrt(4 * np.pi * lambda_reorg * KB * temp_K)
    exponent = -(dG + lambda_reorg)**2 / (4 * lambda_reorg * KB * temp_K)
    return float(prefactor / denom * np.exp(exponent))
