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
    is not; with the response, ≤ 1e-5 (OsO₄, LANL2DZ/6-31G(d), B3LYP, measured 2026-10-12; the doublet [OsO₄]⁺ in UKS, ≤ 7e-6,
    2026-10-13). An open shell's trajectory records each step's <S²>. The SCF tolerance of the
    steps matters the same way: at conv_tol 1e-6 a warm-started gradient is off by up to 7e-5 Ha/Bohr, at 1e-8 by
    ≤ 6e-6 (same molecule, same day) — the caller sets it (`conv_tol` in `protocol`).

    Never loses a step: `on_step(geometry_Å, trajectory)` runs after every gradient (the geometry is read from the
    step's `mol` in Å — the engine's `coords` local is in Bohr); an SCF that fails at a step ends the run as NOT
    converged with its reason, it does not raise. Returns (atoms in Å, info): on convergence the final geometry, else
    the LOWEST-energy geometry evaluated — the restart point. CANNOT show: that the minimum found is the global one."""
    import time

    import geometric
    import geometric.errors
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
        ok = bool(getattr(env["g_scanner"], "converged", True))
        trajectory.append({"E_Ha": float(env["energy"]), "grad_max_Ha_bohr": float(np.abs(env["gradients"]).max()),
                           "grid_response": bool(env["g_scanner"].grid_response), "scf_converged": ok})
        if m.spin:   # an open shell's step is a stationary point, not its state (§Critical Rules #14) — the caller judges
            trajectory[-1]["s2"] = float(env["g_scanner"].base.spin_square()[0])
        if not ok:   # PySCF calls back BEFORE it raises on a failed SCF: that step is neither the best nor the keeper's
            return
        if not best or trajectory[-1]["E_Ha"] < best["E_Ha"]:
            best.update(E_Ha=trajectory[-1]["E_Ha"], geometry=geom, step=len(trajectory))
        if on_step:
            on_step(best["geometry"], trajectory)

    t0 = time.time()
    error = None
    try:
        converged, mol_eq = geomopt(grad, assert_convergence=True, callback=record, maxsteps=maxsteps,
                                    **(conv_params or {}))
    except (RuntimeError, geometric.errors.Error) as exc:   # an SCF failed at a step («Nuclear gradients … not
        converged, mol_eq, error = False, None, f"{type(exc).__name__}: {exc}"   # converged»), or geomeTRIC gave up
    if converged:
        xyz = mol_eq.atom_coords(unit="Angstrom")
        out = [(mol_eq.atom_symbol(i), xyz[i]) for i in range(mol_eq.natm)]
    else:
        out = best.get("geometry", [(sym, np.asarray(x, float)) for sym, x in atoms])
    return out, {"label": label, "converged": bool(converged), "steps": len(trajectory), "trajectory": trajectory,
                 "returned": "final" if converged else f"lowest-energy step {best.get('step')}", "error": error,
                 "conv_params": conv_params or {}, "maxsteps": maxsteps, "geometric": geometric.__version__,
                 "wall_seconds": round(time.time() - t0, 1)}


# A saddle escape converges on geomeTRIC's TIGHT gradients with its DEFAULT displacement criteria, the SCF at 1e-10 — the
# reasons (a flat surface beside the saddle; TIGHT's own dmax would pin methyl rotors at the gradient noise floor) are
# 32b's, where it was measured (in-silico §Critical Rules #18)
ESCAPE_CONV = {"convergence_set": "GAU_TIGHT", "convergence_drms": 1.2e-3, "convergence_dmax": 1.8e-3}
ESCAPE_CONV_TOL = 1e-10


def harmonic(atoms, charge: int, spin: int, hessian_path, imag_tol_cm: float, label: str = "",
             temperature_K: float = 298.15, pressure_Pa: float = 101325.0, **protocol) -> dict:
    """A stationary point's harmonic analysis on the shared protocol (`_scf_object`): an SCF at conv_tol 1e-9, the analytic
    Hessian (saved to `hessian_path`), frequencies and the RRHO terms. Modes beyond `imag_tol_cm` come back as
    `_escape_modes` (the caller pops them); an open shell records the SCF's <S²> (§Critical Rules #14). CANNOT: the DFT
    grid response in the Hessian — PySCF has none, while the geometry was minimised with it (32b CANNOT 4)."""
    import time

    from pyscf.hessian import thermo

    mol, mf = _scf_object(atoms, charge, spin, **{**protocol, "conv_tol": 1e-9})
    e = float(mf.kernel())
    if not mf.converged:
        raise SystemExit(f"{label}: the SCF did not converge — no number is written")
    t0 = time.time()
    hess = mf.Hessian().kernel()
    np.save(hessian_path, hess)
    freq = thermo.harmonic_analysis(mol, hess)
    nu = np.asarray(freq["freq_wavenumber"], dtype=complex)    # imaginary modes come back complex (scimath.sqrt)
    imag = sorted((float(abs(v.imag)) for v in nu if abs(v.imag) > 0), reverse=True)
    real = np.sort(nu.real[np.abs(nu.imag) == 0])
    t = thermo.thermo(mf, freq["freq_au"], temperature_K, pressure_Pa)
    out = {"E_Ha": e, "ZPE_Ha": float(t["ZPE"][0]), "G_tot_Ha": float(t["G_tot"][0]), "H_tot_Ha": float(t["H_tot"][0]),
           "imaginary_cm": imag, "real_cm": [round(float(x), 2) for x in real],
           "n_imag_tolerated": sum(v <= imag_tol_cm for v in imag), "n_imag_beyond_tolerance": sum(v > imag_tol_cm for v in imag),
           "n_modes_below_100cm": int(np.sum(real < 100.0)), "hessian_wall_s": round(time.time() - t0, 1),
           "hessian_file": str(hessian_path),
           "_escape_modes": [np.asarray(freq["norm_mode"][i]) for i, v in enumerate(nu) if abs(v.imag) > imag_tol_cm]}
    if spin:
        out["s2"] = float(mf.spin_square()[0])
    return out


def escape_geometry(atoms, modes, step_a: float) -> list:
    """A stationary point with a mode beyond the tolerance is a saddle; step off it along the sum of every such mode (each
    normalised to a unit largest atomic displacement), the SUM scaled so its largest atomic displacement is `step_a` —
    scaled one by one, two modes sharing an atom move it further (0.134 Å on 32b's run-1 saddle). A symmetric start has
    no gradient out of its symmetry plane, so only a Hessian sends the optimiser off it (§Critical Rules #18). The sign
    of each mode is arbitrary: the two butterfly folds of a reduced flavin are mirror images."""
    xyz = np.array([p for _, p in atoms], dtype=float)
    step = sum(v / np.linalg.norm(v, axis=1).max() for v in modes)
    xyz = xyz + step_a * step / np.linalg.norm(step, axis=1).max()
    return [(s, xyz[i]) for i, (s, _) in enumerate(atoms)]


# the Hessian's own SCF (a fresh start at conv_tol 1e-9) must land on the optimisation's state: its energy within this of
# the last step's (32b run 2: 8e-11 · 1.4e-9 Ha), and a doublet's <S²> within S2_TOL of it
STATE_TOL_HA, S2_TOL = 1e-6, 0.01


def hydrogen_owners(atoms) -> list[tuple[int, float]]:
    """For each H: (index of its nearest heavy atom, distance Å) — the hydrogen POSITIONS that tell a tautomer."""
    xyz = np.array([p for _, p in atoms])
    heavy = [i for i, (s, _) in enumerate(atoms) if s != "H"]
    out = []
    for s, p in atoms:
        if s == "H":
            d = np.linalg.norm(xyz[heavy] - p, axis=1)
            out.append((heavy[int(np.argmin(d))], float(d.min())))
    return out


def tautomer_change(start, relaxed, xh_max_a: float) -> tuple[list, list]:
    """(moved, long): hydrogens whose nearest heavy atom changed during an optimisation, and X–H bonds stretched past
    `xh_max_a` — both empty for the input's tautomer (§Critical Rules #16)."""
    a, b = hydrogen_owners(start), hydrogen_owners(relaxed)
    moved = [(i, x[0], y[0]) for i, (x, y) in enumerate(zip(a, b, strict=True)) if x[0] != y[0]]
    long = [(i, round(y[1], 3)) for i, y in enumerate(b) if y[1] > xh_max_a]
    return moved, long


def relax_to_minimum(start, charge: int, spin: int, *, label: str, tag: str, runs, imag_tol_cm: float, max_escapes: int,
                     step_a: float, on_relaxed=None, on_saddle=None, write_xyz=None, temperature_K: float = 298.15,
                     pressure_Pa: float = 101325.0, **protocol) -> tuple[list, dict, dict]:
    """`dft_optimize`, then `harmonic`; a mode beyond `imag_tol_cm` sends the optimisation off that saddle
    (`escape_geometry`) on ESCAPE_CONV at ESCAPE_CONV_TOL, at most `max_escapes` times. ONE home for every flavin
    optimisation started from a planar RDKit/MMFF geometry (32b · 21g · 33 · 29b).

    `on_relaxed(relaxed, info)` runs after every optimisation and may raise (an unconverged run, a tautomer change —
    the caller's refusals); `on_saddle(saddle)` gets each saddle's record (its Hessian renamed to
    `hessian_<tag>_saddle<n>.npy`, its geometry kept). Returns (geometry, harmonic record, last optimisation info);
    `harmonic["_escape_modes"]` still non-empty means the last attempt was a saddle too — the caller refuses it. The
    Hessian's SCF is tied to the optimisation's state (STATE_TOL_HA on the energy; a doublet's <S²> under S2_MAX_DOUBLET
    and within S2_TOL of the last step's), else SystemExit: a frequency set of another state is no number for this one."""
    from pathlib import Path

    from .constants import S2_MAX_DOUBLET
    from .utils import banner

    runs = Path(runs)
    for attempt in range(max_escapes + 1):
        suffix = f"_escape{attempt}" if attempt else ""
        banner(f"(i) relax {tag}" + (f" — saddle escape {attempt}" if attempt else ""))
        ck = runs / f"opt_{tag}{suffix}.checkpoint.xyz"
        relaxed, info = dft_optimize(start, charge, spin, label=f"{label}{suffix}", conv_params=ESCAPE_CONV if attempt else None,
                                     on_step=(lambda g, tr, ck=ck: write_xyz(g, ck, f"lowest-energy step of {len(tr)}"))
                                     if write_xyz else None,
                                     **({**protocol, "conv_tol": ESCAPE_CONV_TOL} if attempt else protocol))
        traj = info.pop("trajectory", [])
        info["final_step"] = traj[-1] if traj else None
        if on_relaxed:
            on_relaxed(relaxed, info)
        banner(f"(ii)/(iii) Hessian {tag}" + (f" — saddle escape {attempt}" if attempt else ""))
        th = harmonic(relaxed, charge, spin, runs / f"hessian_{tag}.npy", imag_tol_cm, label=f"{tag} Hessian single point",
                      temperature_K=temperature_K, pressure_Pa=pressure_Pa, **protocol)
        last = info["final_step"] or {}
        if "E_Ha" in last and abs(th["E_Ha"] - last["E_Ha"]) > STATE_TOL_HA:
            raise SystemExit(f"{tag}: the Hessian's SCF lies {th['E_Ha'] - last['E_Ha']:+.2e} Ha from the optimisation's last step "
                             "— another electronic state; no number is written")
        if spin == 1 and (th["s2"] > S2_MAX_DOUBLET or ("s2" in last and abs(th["s2"] - last["s2"]) > S2_TOL)):
            raise SystemExit(f"{tag}: the Hessian's SCF has <S²> {th['s2']:.3f} (last step {last.get('s2')}) — another or a "
                             "contaminated state (§Critical Rules #14); no number is written")
        if not th["_escape_modes"] or attempt == max_escapes:
            return relaxed, th, info
        modes = th.pop("_escape_modes")
        saddle_hess = runs / f"hessian_{tag}_saddle{attempt}.npy"
        Path(th["hessian_file"]).replace(saddle_hess)
        if on_saddle:
            on_saddle({**{k: th[k] for k in ("E_Ha", "ZPE_Ha", "G_tot_Ha", "imaginary_cm", "real_cm")}, "geom_opt": info,
                       "hessian_file": str(saddle_hess), "geometry": [(s, [float(x) for x in p]) for s, p in relaxed]})
        print(f"  {tag}: saddle (imaginary {[round(v, 1) for v in th['imaginary_cm']]} cm⁻¹) — stepping "
              f"{step_a} Å along each mode beyond {imag_tol_cm} cm⁻¹ and re-optimising", flush=True)
        start = escape_geometry(relaxed, modes, step_a)
    raise AssertionError("unreachable")


def relax_checked(atoms, charge: int, spin: int, *, label: str, runs, imag_tol_cm: float = 20.0, max_escapes: int = 2,
                  step_a: float = 0.1, xh_max_a: float = 1.2, **protocol) -> tuple[list, dict, dict]:
    """`relax_to_minimum` for a script that keeps one optimisation summary per species and writes a side file on failure
    (21g · 33 · 29b): never raises on the optimisation's own failures. Returns (atoms, summary, minimum_check) —
    `summary["converged"]` is geomeTRIC's verdict on the last run, `summary["minimum"]` whether the point it reached is a
    minimum (no mode beyond `imag_tol_cm` after at most `max_escapes` escapes, and every escape went DOWN); the caller
    gates on both. `minimum_check` holds the harmonic record (frequencies, ZPE, RRHO, <S²> on an open shell) and every
    saddle met with its height over the minimum — the measure of what a planar start had cost the number. Every
    optimisation is checked against the species' own start for a moved proton or a stretched X–H (`xh_max_a`; FADH₂•⁺
    in C-PCM stretches one), and a Hessian whose SCF fails or lands on another state is a refusal with its reason, not
    a crash — the side file keeps the hours already spent."""
    from pathlib import Path

    class _Stop(Exception):
        pass
    last, saddles, refusal = {}, [], None

    def on_relaxed(relaxed, info):
        last.update(relaxed=relaxed, info=info)
        if not info["converged"]:
            raise _Stop
        moved, long = tautomer_change(atoms, relaxed, xh_max_a)
        if moved or long:
            info["error"] = f"not the start's tautomer — moved H {moved}, long X–H {long}"
            raise _Stop

    def write_xyz(geom, path, comment):
        Path(path).write_text(f"{len(geom)}\n{comment}\n" + "".join(f"{s} {x:.8f} {y:.8f} {z:.8f}\n" for s, (x, y, z) in geom),
                              encoding="utf-8")
    th = None
    try:
        relaxed, th, info = relax_to_minimum(atoms, charge, spin, label=label, tag=label, runs=runs, imag_tol_cm=imag_tol_cm,
                                             max_escapes=max_escapes, step_a=step_a, on_relaxed=on_relaxed,
                                             on_saddle=saddles.append, write_xyz=write_xyz, **protocol)
    except _Stop:
        relaxed, info = last["relaxed"], last["info"]
    except SystemExit as exc:   # the Hessian's SCF failed, or landed on another state (relax_to_minimum's refusals)
        relaxed, info, refusal = last["relaxed"], last["info"], str(exc)
    summary = {k: info[k] for k in ("converged", "steps", "returned", "error", "wall_seconds", "maxsteps")}
    if refusal:
        summary["error"] = refusal
    summary["final_grad_max_Ha_bohr"] = (info.get("final_step") or {}).get("grad_max_Ha_bohr")
    check = {"imag_tolerance_cm": imag_tol_cm, "max_escapes": max_escapes, "step_A": step_a,
             "saddles": [{k: v for k, v in sd.items() if k != "geom_opt"} for sd in saddles]}
    summary["minimum"] = False
    if th is not None:
        modes = th.pop("_escape_modes")
        check["harmonic"] = th
        heights = [(sd["E_Ha"] - th["E_Ha"]) * HARTREE_TO_EV * 1000 for sd in saddles]
        check["saddle_above_minimum_meV"] = [round(h, 2) for h in heights]
        if modes:
            summary["error"] = f"a saddle after {max_escapes} escape(s): imaginary {[round(v, 1) for v in th['imaginary_cm']]} cm⁻¹"
        elif any(h <= 0 for h in heights):
            summary["error"] = f"an escape did not descend (heights {check['saddle_above_minimum_meV']} meV)"
        else:
            summary["minimum"] = True
    return [(s, tuple(float(x) for x in c)) for s, c in relaxed], summary, check


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
