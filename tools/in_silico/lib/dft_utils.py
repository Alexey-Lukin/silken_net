# SPDX-License-Identifier: AGPL-3.0-or-later
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


def dft_singlepoint(atoms, charge: int, spin: int, label: str = "",
                    xc: str = "b3lyp", with_pcm: bool = True,
                    conv_tol: float = 1e-6, max_cycle: int = 100,
                    level_shift_open: float = 0.0,
                    basis_light: str | None = None) -> dict:
    """DFT single-point on a metal complex (RKS closed / UKS open) + C-PCM water.

    Shared SSOT runner for the L3 Os scripts (21b / 21e / 34 / 34b series). `atoms`
    is a list of (symbol, xyz-array). `xc` selects the functional (b3lyp screening /
    wb97x range-separated); `basis_light` overrides the light-atom basis (default
    `None` → constants.BASIS_LIGHT = 6-31G(d); pass "def2-tzvp" for the
    publication-grade ωB97X tier). Os always uses LANL2DZ+ECP. `level_shift_open`
    is OFF by default (0.0) to match the validated 21b behaviour and keep reported
    virtual-orbital energies physical — PySCF's level_shift adds a constant to
    virtual MO energies, so an enabled shift biases the reported LUMO (E_total stays
    shift-invariant). Enable it only where SCF oscillates (in-silico skill gotcha
    #5: UKS on Os(III)/Co/Ce) and then read E_total, not LUMO. No `density_fit`
    (gotcha #4: heavy-metal aux basis is slower). Returns E_total (Ha) + frontier
    energies (eV).
    """
    import time

    from pyscf import dft, gto, solvent

    from .constants import BASIS_LIGHT, BASIS_OS, ECP_OS, SOLVENT_EPS_WATER

    light = basis_light or BASIS_LIGHT
    atoms_pyscf = [(s, (float(p[0]), float(p[1]), float(p[2]))) for s, p in atoms]
    mol = gto.M(atom=atoms_pyscf,
                basis={"Os": BASIS_OS, "default": light}, ecp={"Os": ECP_OS},
                charge=charge, spin=spin, unit="Angstrom")
    mf = dft.RKS(mol) if spin == 0 else dft.UKS(mol)
    mf.xc = xc
    if spin != 0 and level_shift_open:
        mf.level_shift = level_shift_open
    if with_pcm:
        mf = solvent.PCM(mf)
        mf.with_solvent.eps = SOLVENT_EPS_WATER
        mf.with_solvent.method = "C-PCM"
    mf.conv_tol = conv_tol
    mf.max_cycle = max_cycle

    t0 = time.time()
    e_total = mf.kernel()
    if not mf.converged:
        # SOSCF (Newton) rescue for oscillating open-shell SCF (e.g. CF₃/SO₂CF₃
        # Os(III) UKS at level_shift=0). Converges the hard case WITHOUT a level
        # shift, so the reported LUMO stays physical (unlike level_shift, which
        # biases virtual MO energies — matters because 21e's cascade Δ reads LUMO).
        mf = mf.newton()
        mf.max_cycle = 100
        e_total = mf.kernel()
    dt = time.time() - t0
    homo_ha, lumo_ha = extract_frontier(mf, mol)
    return {
        "label": label, "charge": charge, "spin": spin,
        "n_atoms": int(mol.natm), "n_electrons": int(mol.nelectron),
        "converged": bool(mf.converged), "wall_seconds": round(dt, 1),
        "E_total_Ha": float(e_total), **frontier_to_ev(homo_ha, lumo_ha),
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
