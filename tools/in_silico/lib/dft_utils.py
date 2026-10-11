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
                    basis_light: str | None = None,
                    dm0=None, chkfile: str | None = None,
                    stability: bool = False, max_stability_steps: int = 3) -> dict:
    """DFT single-point on a metal complex (RKS closed / UKS open) + C-PCM water.

    Shared SSOT runner for the L3 Os scripts (21b / 21e / 34 / 34b series). `atoms`
    is a list of (symbol, xyz-array). `xc` selects the functional (b3lyp screening /
    wb97x range-separated); `basis_light` overrides the light-atom basis (default
    `None` → constants.BASIS_LIGHT = 6-31G(d); pass "def2-tzvp" for the
    publication-grade ωB97X tier). Os always uses LANL2DZ+ECP. `level_shift_open`
    is OFF by default (0.0): the committed B3LYP Os rows were converged so (21b-faithful),
    and a shift changes the path an SCF takes, hence possibly the state it lands on.
    The shift does NOT bias the reported orbital energies of a converged run: PySCF
    re-diagonalises the unshifted Fock matrix once converged (`scf/hf.py` kernel,
    `conv_check`), and the Newton solver canonicalises with the shift at 0 — verified in
    the source of 2.11.0 (recorded) and 2.13.1 (lock), 2026-10-11. Enable it only where
    SCF oscillates (in-silico §Critical Rules #5: UKS on Os(III)/Co/Ce). No `density_fit`
    (#4: heavy-metal aux basis is slower). Returns E_total (Ha) + frontier energies (eV)
    + `rescued` (the first SCF did not converge and the Newton solver took over) and, for
    an open shell, `s2` = <S²>: `converged` certifies a stationary point, not the ground
    state, so an open-shell point is accepted by its `s2` (§Critical Rules #14).

    `dm0` — the initial density (e.g. a doublet start built from the closed-shell
    neighbour's orbitals); `chkfile` — PySCF writes the converged orbitals there, for such
    a start; `stability` — after convergence, run the internal stability analysis of the
    UKS solution (with the solvent response) and follow an instability downhill with the
    Newton solver, at most `max_stability_steps` times; the result then carries
    `stable_internal` and `stability_steps` (and `pre_stability` = E and <S²> of the state the
    first SCF found, when an instability was followed). `aufbau` — no occupied orbital lies above an
    empty one of the same spin. CAN show: the solution is a local minimum in orbital space with an
    aufbau filling. CANNOT show: it is the global one — no start guarantees the ground state.
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
    if chkfile:
        mf.chkfile = chkfile

    t0 = time.time()
    e_total = mf.kernel(dm0=dm0)
    rescued = not mf.converged
    if rescued:
        # SOSCF (Newton) rescue for an oscillating open-shell SCF (e.g. CF₃/SO₂CF₃ Os(III)).
        # It starts from the failed orbitals AND occupation, so it can converge to a
        # spin-contaminated stationary point — the reason `s2` is recorded (§Critical Rules #14).
        mf = mf.newton()
        mf.max_cycle = 100
        e_total = mf.kernel()
    extra = {"rescued": rescued}
    if stability and spin != 0 and mf.converged:
        steps = 0
        first = {"E_total_Ha": float(e_total), "s2": float(mf.spin_square()[0])}
        while True:
            mo_i, _, stable, _ = mf.stability(return_status=True)
            if stable or steps == max_stability_steps:
                break
            steps += 1
            mf = mf.newton()   # returns mf itself when it already is the Newton solver
            e_total = mf.kernel(mo_i, mf.mo_occ)
            if not mf.converged:
                break
        extra.update(stable_internal=bool(stable), stability_steps=steps)
        if steps:   # the state the first SCF found is replaced — kept, not overwritten without a trace
            extra["pre_stability"] = first
    dt = time.time() - t0
    if spin != 0:
        extra["s2"] = float(mf.spin_square()[0])
    # aufbau per spin: the Newton solver keeps the occupation it started from, so a converged state can hold an
    # electron above an empty orbital of the same spin — an excited state with a clean <S²> (adversary, 2026-10-11)
    occ, e = (mf.mo_occ, mf.mo_energy) if spin != 0 else ([mf.mo_occ], [mf.mo_energy])
    extra["aufbau"] = all(float(ei[oi > 0].max()) <= float(ei[oi == 0].min()) for oi, ei in zip(occ, e, strict=True))
    homo_ha, lumo_ha = extract_frontier(mf, mol)
    return {
        "label": label, "charge": charge, "spin": spin,
        "n_atoms": int(mol.natm), "n_electrons": int(mol.nelectron),
        "converged": bool(mf.converged), "wall_seconds": round(dt, 1),
        "E_total_Ha": float(e_total), **frontier_to_ev(homo_ha, lumo_ha), **extra,
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
