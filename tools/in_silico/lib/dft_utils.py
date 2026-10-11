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


def _scf_object(atoms, charge: int, spin: int, xc: str = "b3lyp", with_pcm: bool = True, conv_tol: float = 1e-6,
                max_cycle: int = 100, level_shift_open: float = 0.0, basis_light: str | None = None,
                basis_os: str | None = None, chkfile: str | None = None, pcm_method: str = "C-PCM",
                pcm_radii: str | None = None):
    """The SCF object of the shared protocol (keywords: `dft_singlepoint`) — ONE home for the single point and the
    geometry optimisation, so a relaxed point and a vertical one cannot differ in anything but the geometry."""
    from pyscf import dft, gto, solvent

    from .constants import BASIS_LIGHT, BASIS_OS, ECP_OS, SOLVENT_EPS_WATER

    light = basis_light or BASIS_LIGHT
    atoms_pyscf = [(s, (float(p[0]), float(p[1]), float(p[2]))) for s, p in atoms]
    mol = gto.M(atom=atoms_pyscf,
                basis={"Os": basis_os or BASIS_OS, "default": light}, ecp={"Os": basis_os or ECP_OS},
                charge=charge, spin=spin, unit="Angstrom")
    mf = dft.RKS(mol) if spin == 0 else dft.UKS(mol)
    mf.xc = xc
    if spin != 0 and level_shift_open:
        mf.level_shift = level_shift_open
    if with_pcm:
        mf = solvent.PCM(mf)
        mf.with_solvent.eps = SOLVENT_EPS_WATER
        mf.with_solvent.method = pcm_method
        if pcm_radii == "uff-1.1":
            from pyscf.data import radii
            mf.with_solvent.radii_table = 1.1 * radii.UFF
        elif pcm_radii is not None:
            raise ValueError(f"unknown pcm_radii {pcm_radii!r}")
    mf.conv_tol = conv_tol
    mf.max_cycle = max_cycle
    if chkfile:
        mf.chkfile = chkfile
    return mol, mf


def dft_optimize(atoms, charge: int, spin: int, label: str = "", maxsteps: int = 100,
                 conv_params: dict | None = None, on_step=None, **protocol) -> tuple[list, dict]:
    """Relax a geometry with geomeTRIC on the SCF object `dft_singlepoint` builds (`_scf_object`, `protocol` = its
    keywords) — one protocol, one home.

    The gradient carries the DFT grid response: without it the analytic gradient of this protocol departs from the
    central difference of its own energy by ~1e-4 Ha/Bohr on a light atom — a third of geomeTRIC's default gmax — in
    gas and in C-PCM alike, so the C-PCM gradient (with PySCF ≤ 2.12's ECP-sphere switching) is consistent and the grid
    is not; with the response, ≤ 1e-5 (OsO₄, LANL2DZ/6-31G(d), B3LYP, measured 2026-10-12). The SCF tolerance of the
    steps matters the same way: at conv_tol 1e-6 a warm-started gradient is off by up to 7e-5 Ha/Bohr, at 1e-8 by
    ≤ 6e-6 (same molecule, same day) — the caller sets it (`conv_tol` in `protocol`).

    Never loses a step: `on_step(geometry_Å, trajectory)` runs after every gradient (the geometry is read from the
    step's `mol` in Å — the engine's `coords` local is in Bohr); an SCF that fails at a step ends the run as NOT
    converged with its reason, it does not raise. Returns (atoms in Å, info): on convergence the final geometry, else
    the LOWEST-energy geometry evaluated — the restart point. CANNOT show: that the minimum found is the global one."""
    import time

    import geometric
    import numpy as np
    from pyscf.geomopt.geometric_solver import kernel as geomopt

    _, mf = _scf_object(atoms, charge, spin, **protocol)
    grad = mf.nuc_grad_method()
    grad.grid_response = True
    trajectory, best = [], {}

    def record(env):
        m = env["mol"]
        xyz = m.atom_coords(unit="Angstrom")
        geom = [(m.atom_symbol(i), xyz[i]) for i in range(m.natm)]
        trajectory.append({"E_Ha": float(env["energy"]), "grad_max_Ha_bohr": float(np.abs(env["gradients"]).max()),
                           "grid_response": bool(env["g_scanner"].grid_response)})
        if not best or trajectory[-1]["E_Ha"] < best["E_Ha"]:
            best.update(E_Ha=trajectory[-1]["E_Ha"], geometry=geom, step=len(trajectory))
        if on_step:
            on_step(best["geometry"], trajectory)

    t0 = time.time()
    error = None
    try:
        converged, mol_eq = geomopt(grad, assert_convergence=True, callback=record, maxsteps=maxsteps,
                                    **(conv_params or {}))
    except RuntimeError as exc:   # the wrapper's «Nuclear gradients … not converged»: an SCF failed at a step
        converged, mol_eq, error = False, None, str(exc)
    if converged:
        xyz = mol_eq.atom_coords(unit="Angstrom")
        out = [(mol_eq.atom_symbol(i), xyz[i]) for i in range(mol_eq.natm)]
    else:
        out = best.get("geometry", [(sym, np.asarray(x, float)) for sym, x in atoms])
    return out, {"label": label, "converged": bool(converged), "steps": len(trajectory), "trajectory": trajectory,
                 "returned": "final" if converged else f"lowest-energy step {best.get('step')}", "error": error,
                 "conv_params": conv_params or {}, "maxsteps": maxsteps, "geometric": geometric.__version__,
                 "wall_seconds": round(time.time() - t0, 1)}


def dft_singlepoint(atoms, charge: int, spin: int, label: str = "",
                    xc: str = "b3lyp", with_pcm: bool = True,
                    conv_tol: float = 1e-6, max_cycle: int = 100,
                    level_shift_open: float = 0.0,
                    basis_light: str | None = None, basis_os: str | None = None,
                    dm0=None, chkfile: str | None = None,
                    stability: bool = False, max_stability_steps: int = 3,
                    pcm_method: str = "C-PCM", pcm_radii: str | None = None) -> dict:
    """DFT single-point on a metal complex (RKS closed / UKS open) + C-PCM water.

    Shared SSOT runner for the L3 Os scripts that import it (21e · 21f · 34 · 34b · 75 · 76, grep 2026-10-12; 20, 21,
    21b and 21d keep local copies of their own). `atoms`
    is a list of (symbol, xyz-array). `xc` selects the functional (b3lyp screening /
    wb97x range-separated); `basis_light` overrides the light-atom basis (default
    `None` → constants.BASIS_LIGHT = 6-31G(d); pass "def2-tzvp" for the
    publication-grade ωB97X tier). `basis_os` sets the Os basis AND its ECP together (default `None` → LANL2DZ/LANL2DZ;
    "def2-tzvp" = def2-TZVP with the def2 ECP — both remove a 60-electron core). `level_shift_open`
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

    `pcm_method` — the continuum's boundary formulation ('C-PCM' as every committed row, or 'IEF-PCM'); the cavity
    is not touched by it. `pcm_radii` — the atomic radii of the cavity: `None` = PySCF's default table (modified Bondi
    ×1.2; for Os a 2.0 Å placeholder ×1.2 = 2.40 Å — every committed row), "uff-1.1" = UFF radii ×1.1 with a sphere on
    every hydrogen, Gaussian 16's default radii (gaussian.com/scrf; G16's own surface discretisation is not reproduced).
    ⚠️ Under PySCF ≤ 2.12 the switching function of an ECP atom's sphere takes its radius at Z_eff (Os/LANL2DZ → sulfur's)
    while its surface points sit on its own (paper §2.7) — in both tables, so the radii knob also moves Os's own sphere
    (2.40 → 1.72 Å), and with it most of that artefact's area; it stays the one knob «radii».

    For an open shell with osmium, `os_spin_mulliken` = the Mulliken spin density (α−β) on Os: <S²> and aufbau cannot
    tell a doublet whose hole sits on a ligand from one whose hole sits on the metal; this can (≈ 1 on Os(III)).
    """
    import time

    mol, mf = _scf_object(atoms, charge, spin, xc=xc, with_pcm=with_pcm, conv_tol=conv_tol, max_cycle=max_cycle,
                          level_shift_open=level_shift_open, basis_light=basis_light, basis_os=basis_os,
                          chkfile=chkfile, pcm_method=pcm_method, pcm_radii=pcm_radii)
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
        os_atoms = [i for i in range(mol.natm) if mol.atom_symbol(i) == "Os"]
        if os_atoms:
            from pyscf.scf.uhf import mulliken_spin_pop
            ms = mulliken_spin_pop(mol, mf.make_rdm1(), verbose=0)[1]
            extra["os_spin_mulliken"] = float(sum(ms[i] for i in os_atoms))
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
