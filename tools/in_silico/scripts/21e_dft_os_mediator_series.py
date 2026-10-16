#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""L3 task ① — Os-mediator structure-property series (full Hammett range).

Computes the Os(III)+e⁻→Os(II) ΔSCF reduction energy for cis-[Os(4,4'-X-bpy)₂(1-MeIm)Cl]ⁿ⁺
across a 4,4'-substituent series at CONSTANT charge (+1/+2), isolating the
electronic effect (no charge change → no differential-PCM confounder; that is ②).
Establishes (a) the Hammett LFER for the Os(III/II) potential and (b) the
cascade-alignment design rule Δ = HOMO(FADH₂) − LUMO(Os III) vs substituent.

Pre-check (dmbpy/bpy/dcbpy) PASSED 2026-06-05: monotonic with σ, reproduces 21b
(Δ=0.000). The LFER slope is COMPUTED here (not hardcoded) over the linear-regime
fit-set (REF_LFER_SET) and written to results["lfer"] — the single source the
figure (60), table (61) and prose all read, so the number cannot drift.

PREDICTION (fixed): ΔE_red decreases (E° rises) and the cascade Δ rises toward 0
(less uphill) as σ_para increases (electron-withdrawing 4,4'-substituents).

Method: B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM, vertical ΔSCF, level_shift OFF (21b-faithful).
Sequential single process (feedback_dft_sequential). Cache-skip: complexes already present with both states
`converged` in os_mediator_series.json are reused (no recompute) — `converged` is a stationary point, not an
accepted state (in-silico §Critical Rules #14), and these B3LYP rows carry no <S²> (their negative check is by gap and
LFER — PIPELINE_STATUS ① residue); a stricter reuse here would recompute the canonical series under whatever PySCF
runs it, since this path has no version guard. Cascade Δ
uses FADH₂ HOMO from dft/lumiflavin.json. Numbers feed SUMMARY.md (One-Home) once done.

Run:  conda activate silken_md
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py

ωB97X tier of the σ-axis EXTREMES (⚖️ founder 2026-10-02, 00_07 HW.5.IS; question and cost — PIPELINE_STATUS ①):
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py wb97x [nh2 no2 nme2]
21f's own ωB97X tier (imported) on the named complexes only, into its OWN cache (OUT_WB97X) at full precision,
written after EACH state — so a stop costs one SCF, not the night. Refuses any PySCF but the RECORDED one: the
dmbpy and bpy ωB97X points it is compared with were computed there, and a lock run would put a second cavity
convention into the same table. ≈ 8–27 h per complex (×14–46 the B3LYP pair) — one per night, nothing else heavy.
CAN show: whether ωB97X keeps the B3LYP offset (≈ +0.138 eV on the dmbpy/bpy pair) at the donor plateau and the
acceptor end. CANNOT show: an adiabatic or speciation effect (vertical, chloro form only), nor a new cascade
verdict — the authoritative reading stays the verified E°s.
Once every extreme is accepted it writes the comparison with the B3LYP series into the same cache
(`vs_b3lyp`, see _vs_b3lyp) — the numbers SUMMARY §Mediator and the paper quote.
An Os(III) state is ACCEPTED by its <S²> (≤ S2_MAX_DOUBLET), never by `converged` (§Critical Rules #14): a state is
reused only when accepted, and a recomputed Os(III) starts from the Os(II) closed shell minus one β electron and is
checked for internal stability (⚖️ founder 2026-10-09, 00_07 HW.5.IS).
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py wb97x-compare
rewrites `vs_b3lyp` from the caches alone — no SCF — e.g. after the small-basis cache changed.
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py wb97x-631gd [nh2 no2]
the same tier with the B3LYP basis (34b's tier, ⚖️ 2026-10-08) into its own cache; `vs_b3lyp` reads it to split the
ends' change into functional and basis. Both modes refuse a geometry that is not the B3LYP row's BEFORE any SCF.

One-knob variants of THIS protocol (00_07 HW.5.IS: which part of it carries the Me excess the aqueous measured series
shows) — each into its own cache, on bpy · dmbpy · ome · cl by default, with a per-pair comparison to the series rows:
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py b3lyp-osdef2      # def2-TZVP/ECP on Os
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py b3lyp-iefpcm      # IEF-PCM, the same cavity
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py b3lyp-uffcavity   # UFF ×1.1 radii (Gaussian 16's)
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py b3lyp-gas         # no continuum
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py b3lyp-pyaxial     # pyridine for 1-MeIm (A1′)
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py b3lyp-relaxed-os2 # Os(II) relaxed (dmbpy ome bpy)
CAN show: how much of each pair the one knob moves. CANNOT show: free-energy terms or the Os(III) state's own relaxation
(every variant is a vertical ΔSCF on one geometry per point — `b3lyp-relaxed-os2` moves that geometry to Os(II)'s
minimum), nor which variant is nearer experiment — that is `83`. The Os(III) state's own relaxation is leg (3б):
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py b3lyp-relaxed-os3 # Os(III) from each relaxed Os(II)
— the adiabatic ΔE_red and λ_III per point, into its own cache (`main_relaxed_os3`).
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import BASIS_LIGHT, DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT, S2_MAX_DOUBLET
from lib.dft_utils import dft_optimize, dft_singlepoint
from lib.os_geometry import (
    BPY_SMILES,
    DCBPY_SMILES,
    DMBPY_SMILES,
    MEIM_SMILES,
    PY_SMILES,
    build_monodentate,
    build_os_complex,
    write_xyz,
)
from lib.utils import banner

# 4,4'-X-2,2'-bipyridine series, ordered by Hammett σ_para (donor → acceptor).
# The σ_para values are a NAMED ASSUMPTION (paper §2.3, 09_references disposition route (b), 2026-10-02):
# the conventional tabulated constants, as compiled by Hansch, Leo & Taft (Chem. Rev. 1991, 91, 165 —
# Crossref-confirmed, the values NOT checked against its full text, which is paywalled). The fitted slope
# inherits them, and the slope is the quantitative part of the design rule (00_02 §2.1) — so their error is its error;
# its method dependence is a second, separate uncertainty (the `vs_b3lyp` block of OUT_WB97X).
# Each X-bpy has exactly 2 aromatic ring N (substituent N of NMe₂/NH₂/NO₂ is
# non-aromatic → excluded by build_chelate's ring-N filter). Constant charge +1/+2.
SERIES = [
    ("nme2", "CN(C)c1ccnc(-c2cc(N(C)C)ccn2)c1", -0.83, "4,4'-bis(dimethylamino) (strong donor)"),
    ("nh2", "Nc1ccnc(-c2cc(N)ccn2)c1", -0.66, "4,4'-diamino (donor)"),
    ("ome", "COc1ccnc(-c2cc(OC)ccn2)c1", -0.27, "4,4'-dimethoxy (donor)"),
    ("dmbpy", DMBPY_SMILES, -0.17, "4,4'-dimethyl (weak donor)"),
    ("bpy", BPY_SMILES, 0.00, "parent (reproduces 21b)"),
    # the acceptor point of the measured series of this scaffold — ref 8's PVI polymers and Montón-Vicente 2026 (script 83)
    ("cl", "Clc1ccnc(-c2cc(Cl)ccn2)c1", 0.23, "4,4'-dichloro (weak acceptor)"),
    ("dcbpy", DCBPY_SMILES, 0.45, "4,4'-dicarboxy (acceptor)"),
    ("no2", "O=[N+]([O-])c1ccnc(-c2cc([N+](=O)[O-])ccn2)c1", 0.78, "4,4'-dinitro (strong acceptor)"),
    # CHEM.23: NO₂ is electrochemically UNSTABLE (reduces NO₂→NHOH→NH₂ on Os cycling at
    # pH 4.5 → degrades to the donor-saturated WORST cascade). Inert high-σ acceptors that
    # give the same LUMO lowering without degrading over 20 yr:
    ("cf3", "FC(F)(F)c1ccnc(-c2cc(C(F)(F)F)ccn2)c1", 0.54, "4,4'-bis(CF₃) (inert acceptor — CHEM.23)"),
    ("so2cf3", "O=S(=O)(C(F)(F)F)c1ccnc(-c2cc(S(=O)(=O)C(F)(F)F)ccn2)c1", 0.96, "4,4'-bis(triflyl SO₂CF₃) (inert strong acceptor — CHEM.23)"),
]

REF_21B = {"os2_HOMO": -4.875, "os2_LUMO": -2.156, "os3_HOMO": -6.359, "os3_LUMO": -4.228}

# Canonical Hammett LFER fit-set = classic monosubstituents OMe→NO₂ (the linear regime).
# EXCLUDED (overlaid as called-out points, NOT fitted): NMe₂/NH₂ (σ⁻ donor-resonance
# saturation, plateau ~−3.91 eV) and the inert CF₃-family design picks CF₃/SO₂CF₃
# (high-σ flattening). Must stay identical to the fit-set in 60_paper_figures.py.
REF_LFER_SET = ["ome", "dmbpy", "bpy", "dcbpy", "no2"]
OUT = DFT_CACHE / "os_mediator_series.json"
OUT_WB97X = DFT_CACHE / "os_mediator_series_wb97x.json"   # ωB97X extremes — its own cache (one cache per model)
WB97X_EXTREMES = ["nh2", "no2", "nme2"]   # donor plateau pair + acceptor end, cheapest first (⚖️ 2026-10-02)
# 34b's tier (ωB97X, B3LYP's 6-31G(d) basis) at the axis ends — splits the ×0.85 into functional and basis there
# (⚖️ founder 2026-10-08, 00_07 HW.5.IS); its own cache, because it is another model (§When Modifying #17)
OUT_WB97X_631GD = DFT_CACHE / "os_mediator_series_wb97x_631gd.json"
# The B3LYP series protocol with ONE change each (00_07 HW.5.IS: which part of our protocol carries the Me excess the aqueous
# measured series shows) — each its own cache (§When Modifying #17), the same points and pairs by default.
OUT_OSDEF2 = DFT_CACHE / "os_mediator_series_osdef2.json"      # def2-TZVP and its ECP on Os instead of LANL2DZ
OUT_IEFPCM = DFT_CACHE / "os_mediator_series_iefpcm.json"      # IEF-PCM instead of C-PCM, the cavity unchanged
OUT_UFFCAV = DFT_CACHE / "os_mediator_series_uffcavity.json"   # the cavity radii: UFF ×1.1 (Gaussian 16's default) for ours
OUT_GAS = DFT_CACHE / "os_mediator_series_gas.json"            # no continuum — the share of each pair the solvent model carries
OUT_PYAXIAL = DFT_CACHE / "os_mediator_series_pyaxial.json"    # pyridine for 1-MeIm — the axial N-donor of the aqueous series
OUT_RELAXED = DFT_CACHE / "os_mediator_series_relaxed_os2.json"   # each point at its own relaxed Os(II) geometry
OUT_RELAXED3 = DFT_CACHE / "os_mediator_series_relaxed_os3.json"  # (3б): Os(III) relaxed from each relaxed Os(II)
RELAX_POINTS = ["dmbpy", "ome", "bpy"]   # the decisive pair OMe−Me first; H for Me−H; acceptors only on request
# (estimate for both states: the donors' optimisation ⊥ single-point time ratio × the acceptor's single point — 00_07 HW.5.IS)
# Declared before the first run (00_07 HW.5.IS leg 3a): energy and gradient at Gaussian's default thresholds (geomeTRIC's
# GAU), displacement at its loose ones — the Os–Cl mode is flat (skill in-silico, DFT Gotchas: displacement never met).
# What bounds the error is the GRADIENT, not the step (run-path adversary, 2026-10-12): at the Os(II) minimum Os(III) is
# not stationary, so a leftover geometry error δ ≤ gmax/k enters ΔE_red at first order — ≲ 2 meV a complex, ≲ 1 mV per
# substituent on a pair (an estimate: λ(III) ≈ 0.03 eV, k ≈ 0.1 Ha/Bohr²), an order under the 16 mV asked about. Leg 3б
# measured λ(III) about three times that on Me, and its step-0 gradient puts k nearer 0.05 in one dimension: the bound
# then reads ≈ 4 meV a complex, ≈ 2 mV per substituent — several times under, not an order.
RELAX_CONV = {"convergence_energy": 1e-6, "convergence_grms": 3e-4, "convergence_gmax": 4.5e-4,
              "convergence_drms": 6.7e-3, "convergence_dmax": 1e-2}
RELAX_MAXSTEPS = 120
RELAX_SCF_CONV_TOL = 1e-8   # the steps' SCF; at the series' 1e-6 a warm-started gradient is off by up to 7e-5 Ha/Bohr
#                             (≈ 15 % of gmax), at 1e-8 by ≤ 6e-6 (OsO₄, 2026-10-12); the single points stay at 1e-6
RELAX_ENERGY_TOL_HA = 1e-5  # step 0 ⊥ the series row, and the relaxed single point ⊥ the optimiser's last step
OS3_MIN_OS_SPIN = 0.8   # OURS: the relaxed donors' Os(III) carries 0.91–0.93 of its spin on Os (Mulliken); a hole that
# moved onto a ligand (a nitro-bpy can hold one) is not the Os(III/II) couple the series compares — refused before (3б)
RELAX_MAX_DONOR_SHIFT_A = 0.3   # an Os–donor distance moving this far is a units slip, not chemistry — refused at the step
VARIANT_POINTS = ["bpy", "dmbpy", "ome", "cl"]
N_SUBST = 4   # two 4,4'-X2-bpy per complex
VARIANT_MAX_CYCLE = 400   # the LANL2DZ rows of bpy · dmbpy · ome were run at 400 cycles, no Newton rescue (c60e01d09, 2026-06-05);
                          # cl at today's 100 + rescue converged unrescued — 400 keeps every pair on the path its row took
VARIANT_PAIRS = (("dmbpy", "bpy"), ("ome", "bpy"), ("cl", "bpy"), ("ome", "dmbpy"), ("cl", "dmbpy"), ("cl", "ome"))
WB97X_631GD_ENDS = ["nh2", "no2"]
# The centre of the comparison was computed at the same ωB97X/def2-TZVP tier by other scripts, each on a file that
# must equal this series' own geometry of that complex (checked at runtime, never assumed): (cache, xyz it ran on).
WB97X_CENTRE = {"dmbpy": ("os_complex_wb97xd_dmbpy.json", "os_dmbpy_meim_cl_full.xyz"),   # 21f wb97x tier
                "bpy": ("os_complex_wb97xd.json", "os_bpy_im_cl.xyz")}                   # 21d (21b's ligand file)
SAME_GEOMETRY_TOL_A = 1e-3   # the xyz files carry 6 decimals; a rebuild lands within 5e-7 Å
SPAN_ENDS = ("nme2", "no2")   # named, not «lowest/highest σ»: an added acceptor point must not move the span
# ωB97X with the SMALL basis at the centre — the chloro form of 34b's speciation cross-check — splits the centre's
# B3LYP → ωB97X/def2-TZVP change into a functional and a basis part (the ends' points of that tier: `wb97x-631gd`).
WB97X_SMALL_BASIS = {"dmbpy": "wb97x_speciation_dmbpy.json", "bpy": "wb97x_speciation.json"}


def _ls(sigmas: list[float], energies: list[float]) -> tuple[float, float, float]:
    """Unrounded least-squares (slope, intercept, R²) — compute FROM this, never from a rounded fit."""
    n = len(sigmas)
    sx, sy = sum(sigmas), sum(energies)
    sxx = sum(s * s for s in sigmas)
    sxy = sum(s * e for s, e in zip(sigmas, energies, strict=True))
    slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    intercept = (sy - slope * sx) / n
    ybar = sy / n
    ss_tot = sum((e - ybar) ** 2 for e in energies)
    ss_res = sum((e - (slope * s + intercept)) ** 2 for s, e in zip(sigmas, energies, strict=True))
    return slope, intercept, 1.0 - ss_res / ss_tot


def _lfer_fit(sigmas: list[float], energies: list[float]) -> dict:
    """Least-squares ΔE_red-vs-σ slope + R² (pure-python, no numpy dep), rounded for display."""
    slope, intercept, r2 = _ls(sigmas, energies)
    return {"slope_eV_per_sigma": round(slope, 4), "intercept_eV": round(intercept, 4),
            "r2": round(r2, 4), "n": len(sigmas)}


def _read_xyz(path: Path) -> list:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [(ln.split()[0], tuple(float(v) for v in ln.split()[1:4])) for ln in lines[2:2 + int(lines[0])]]


def _save(path: Path, rec: dict) -> None:
    """Write a cache atomically — a kill mid-write leaves the previous file, never a truncated one."""
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(rec, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def _series_geometry_dev(name: str, atoms: list) -> float:
    """Max |Δxyz| between a rebuilt series complex and the xyz its B3LYP row was computed on."""
    ref = LIGANDS_DIR / f"os_{name}_meim_cl.xyz"
    if not ref.exists():
        sys.exit(f"{name}: no B3LYP geometry {ref.name} to compare with")
    return _max_dev_A([(el, tuple(xyz)) for el, xyz in atoms], _read_xyz(ref))


def _max_dev_A(a: list, b: list) -> float:
    """Largest coordinate difference between two geometries; inf when the atom lists differ."""
    if [e for e, _ in a] != [e for e, _ in b]:
        return float("inf")
    return max(abs(p - q) for (_, x), (_, y) in zip(a, b, strict=True) for p, q in zip(x, y, strict=True))


def _acceptance(state: dict, open_shell: bool) -> str:
    """'accepted' · 'not_converged' · 'not_aufbau' · 'unstable' · 'spin_contaminated' · 's2_not_recorded'.

    A converged SCF is a stationary point, not the ground state (in-silico §Critical Rules #14): an open-shell
    state is accepted by its <S²> ≤ S2_MAX_DOUBLET, an aufbau filling and — when it was checked — internal
    stability. 's2_not_recorded' = a row written before <S²> was recorded (2026-10-11): in the cache it stands on
    `converged` alone (a run log may print its <S²>; not every source has one) — the reuse path recomputes it, the
    comparison names it. A field that is absent (rows before 2026-10-11)
    is not read as a pass or a fail of that criterion; only `s2` is required for a reuse.
    """
    if not state.get("converged"):
        return "not_converged"
    if state.get("aufbau") is False:
        return "not_aufbau"
    if not open_shell:
        return "accepted"
    if state.get("stable_internal") is False:
        return "unstable"
    if state.get("s2") is None:
        return "s2_not_recorded"
    return "accepted" if state["s2"] <= S2_MAX_DOUBLET else "spin_contaminated"


def _doublet_start(atoms: list, chk: Path, os2_row: dict, xc: str, basis_light, conv: float, charge: int = 1) -> tuple:
    """A UKS start for Os(III) on its own Os(II) closed shell: the converged orbitals minus one β electron from the HOMO.

    The rescue that let NO₂ Os(III) land at <S²> 1.767 starts from the failed orbitals (§Critical Rules #14); this
    start puts the hole where the doublet keeps it. When `chk` holds no orbitals, Os(II) is re-run into it and refused
    unless it reproduces the row's E_total within the SCF tolerance — the start then stands on the same closed shell
    as the cached row. CAN show: the start is a doublet with the hole in the HOMO, and how much of that orbital is on
    Os (`hole_os_fraction`, Mulliken). CANNOT show: that the SCF stays on it — `s2` and the stability check judge that.
    """
    import numpy as np
    from pyscf.scf import chkfile

    rerun_delta = None
    if not chk.exists():
        os2 = dft_singlepoint(atoms, charge=charge, spin=0, label="closed shell re-run for the doublet start", xc=xc,
                              basis_light=basis_light, conv_tol=conv, chkfile=str(chk))
        rerun_delta = os2["E_total_Ha"] - os2_row["E_total_Ha"]
        if not os2["converged"] or abs(rerun_delta) > conv:
            sys.exit(f"Os(II) re-run does not reproduce its row (ΔE {rerun_delta:+.2e} Ha, converged "
                     f"{os2['converged']}) — the doublet start would stand on another closed shell; refused")
    mol = chkfile.load_mol(str(chk))
    mo, occ = chkfile.load(str(chk), "scf/mo_coeff"), chkfile.load(str(chk), "scf/mo_occ")
    homo = int(np.flatnonzero(occ > 0)[-1])
    occ_a, occ_b = occ / 2, occ / 2
    occ_b[homo] = 0.0
    c = mo[:, homo]
    pop = c * (mol.intor_symmetric("int1e_ovlp") @ c)
    os_ao = [i for a, (_, _, p0, p1) in enumerate(mol.aoslice_by_atom()) if mol.atom_symbol(a) == "Os"
             for i in range(p0, p1)]
    start = {"from": "Os(II) closed shell minus one β electron from its HOMO",
             "hole_os_fraction": float(pop[os_ao].sum()), "os2_rerun_delta_Ha": rerun_delta}
    return np.array([(mo * occ_a) @ mo.T, (mo * occ_b) @ mo.T]), start


def _vs_b3lyp(rec: dict) -> dict:
    """ω−B3 at every σ point that BOTH tiers computed on the SAME geometry, at full precision.

    CAN show: whether the B3LYP/6-31G(d) → ωB97X/def2-TZVP shift of ΔE_red is constant along σ (a rigid
    offset) or not, the donor-plateau gap in both tiers, and the slope of each tier over the points of the
    canonical fit-set that both have. CANNOT separate the functional from the basis change, nor say which
    tier is right — no measured series is triangulated here (paper §3.3). Refuses unless each pair sits on
    one geometry: the series point is rebuilt and compared with the xyz its B3LYP row wrote, the centre
    points' xyz files with the series file of the same complex.
    """
    b3 = {c["name"]: c for c in json.loads(OUT.read_text(encoding="utf-8"))["complexes"]}
    series_smiles = {name: smi for name, smi, _, _ in SERIES}
    points = []
    not_compared = {}   # a point with no accepted pair has no ΔE to compare — named with its reason, never a crash
    s2_not_recorded = []   # Os(III) states compared on their run log only — named, never silently passed
    for name, c in rec["complexes"].items():
        verdicts = {s: _acceptance(c.get(s, {}), s == "os3") for s in ("os2", "os3")}
        refused = {s: v for s, v in verdicts.items() if v not in ("accepted", "s2_not_recorded")}
        if refused or "dE_red_eV" not in c:
            not_compared[name] = refused or {"pair": "no dE_red_eV"}
            continue
        if verdicts["os3"] == "s2_not_recorded":
            s2_not_recorded.append(f"{OUT_WB97X.name}:{name}")
        atoms, _ = build_os_complex(bpy_smiles=series_smiles[name])
        points.append((name, c["dE_red_eV"], OUT_WB97X.name, _series_geometry_dev(name, atoms)))
    for name, (cache, xyz) in WB97X_CENTRE.items():
        w = json.loads((DFT_CACHE / cache).read_text(encoding="utf-8"))
        verdicts = {"os2": _acceptance(w["os2_plus"], False), "os3": _acceptance(w["os3_plus"], True)}
        if verdicts["os2"] != "accepted" or verdicts["os3"] not in ("accepted", "s2_not_recorded"):
            sys.exit(f"{cache}: a centre state is not accepted {verdicts}")
        if verdicts["os3"] == "s2_not_recorded":
            s2_not_recorded.append(cache)
        dE = (w["os2_plus"]["E_total_Ha"] - w["os3_plus"]["E_total_Ha"]) * HARTREE_TO_EV   # full precision
        dev = _max_dev_A(_read_xyz(LIGANDS_DIR / xyz), _read_xyz(LIGANDS_DIR / f"os_{name}_meim_cl.xyz"))
        points.append((name, dE, cache, dev))
    off_geom = {n: d for n, _, _, d in points if d > SAME_GEOMETRY_TOL_A}
    if off_geom:
        sys.exit(f"ω−B3 would mix geometries (max |Δxyz| Å): {off_geom}")
    rows = sorted(({"name": n, "sigma_para": b3[n]["sigma_para"], "b3lyp_dE_red_eV": b3[n]["dE_red_eV"],
                    "wb97x_dE_red_eV": e, "omega_minus_b3_eV": e - b3[n]["dE_red_eV"], "wb97x_source": src,
                    "geometry_max_dev_A": d} for n, e, src, d in points), key=lambda r: r["sigma_para"])
    by = {r["name"]: r for r in rows}
    subset = [n for n in REF_LFER_SET if n in by]
    sig = [by[n]["sigma_para"] for n in subset]
    sb3, _, r2b3 = _ls(sig, [by[n]["b3lyp_dE_red_eV"] for n in subset])
    sw, _, r2w = _ls(sig, [by[n]["wb97x_dE_red_eV"] for n in subset])
    lo, hi = by[SPAN_ENDS[0]], by[SPAN_ENDS[1]]
    offsets = [r["omega_minus_b3_eV"] for r in rows]
    span_b3 = hi["b3lyp_dE_red_eV"] - lo["b3lyp_dE_red_eV"]
    span_w = hi["wb97x_dE_red_eV"] - lo["wb97x_dE_red_eV"]
    acceptor_gap = ({t: by["so2cf3"][f"{t}_dE_red_eV"] - by["no2"][f"{t}_dE_red_eV"] for t in ("b3lyp", "wb97x")}
                    if "so2cf3" in by else None)
    plateau = {t: by["nme2"][f"{t}_dE_red_eV"] - by["nh2"][f"{t}_dE_red_eV"] for t in ("b3lyp", "wb97x")}
    same_sign = plateau["b3lyp"] * plateau["wb97x"] > 0
    centre = _centre_decomposition(by, series_smiles)
    cs = centre["local_slope_eV_per_sigma"]
    opposite = (cs["wb97x_631gd"] - cs["b3lyp_631gd"]) * (cs["wb97x_def2tzvp"] - cs["wb97x_631gd"]) < 0
    ends = _ends_decomposition(by, series_smiles, centre, subset)
    s2_not_recorded += centre.pop("s2_not_recorded") + ends.pop("s2_not_recorded")
    es = ends["slope_over_common_subset_by_tier"]
    ends_clause = (f"over {', '.join(subset)} the slope runs {es['b3lyp_631gd']:+.3f} → {es['wb97x_631gd']:+.3f} "
                   f"(ωB97X, 6-31G(d)) → {es['wb97x_def2tzvp']:+.3f} eV/σ, so of the ×{sw / sb3:.2f} the functional "
                   f"carries ×{es['wb97x_631gd'] / es['b3lyp_631gd']:.2f} and the basis "
                   f"×{es['wb97x_def2tzvp'] / es['wb97x_631gd']:.2f}" if es else "at the ends the two are not separated")
    gap_clause = (f" The acceptor gap so2cf3 − no2 is {acceptor_gap['b3lyp'] * 1000:+.1f} (B3LYP) ⊥ "
                  f"{acceptor_gap['wb97x'] * 1000:+.1f} meV (ωB97X)." if acceptor_gap else "")
    # every pair whose order by ΔE_red differs between the tiers, and the tier that keeps its σ order (a larger σ
    # lowers ΔE_red) — built from the rows, so the prose cannot claim «the order is kept» past a swap
    swaps = [{"pair": [a["name"], b["name"]],
              "sigma_order_kept_by": "b3lyp" if (b["b3lyp_dE_red_eV"] - a["b3lyp_dE_red_eV"]) * (b["sigma_para"] - a["sigma_para"]) < 0
              else "wb97x"}
             for i, a in enumerate(rows) for b in rows[i + 1:]
             if (a["b3lyp_dE_red_eV"] - b["b3lyp_dE_red_eV"]) * (a["wb97x_dE_red_eV"] - b["wb97x_dE_red_eV"]) < 0]
    order_clause = ("the order by ΔE_red is the same at both tiers" if not swaps else
                    "the order by ΔE_red is the same except " + "; ".join(
                        f"{s['pair'][0]}/{s['pair'][1]}, which swap (σ order kept by "
                        f"{'B3LYP' if s['sigma_order_kept_by'] == 'b3lyp' else 'ωB97X'})" for s in swaps))
    lo_off = min(rows, key=lambda r: r["omega_minus_b3_eV"])
    hi_off = max(rows, key=lambda r: r["omega_minus_b3_eV"])
    n_sources = len(rows) + len(centre["points"]) + len(ends["points"])
    s2_clause = (f" The Os(III) <S²> is not in the cache for {len(s2_not_recorded)} of the {n_sources} sources compared "
                 f"(`os3_s2_not_recorded`); in the cache those points stand on `converged` alone — for the 21e rows a run "
                 f"log prints their <S²>, for the other sources no log is kept." if s2_not_recorded else "")
    return {
        "method_pair": "B3LYP/6-31G(d) (os_mediator_series.json) ⊥ ωB97X/def2-TZVP (this cache + WB97X_CENTRE), "
                       "LANL2DZ(Os), C-PCM, vertical ΔSCF on one geometry per point",
        "points": rows,
        "offset_range_eV": [min(offsets), max(offsets)],
        "common_fit_subset": subset,
        "slope_b3lyp_eV_per_sigma": sb3, "r2_b3lyp": r2b3,
        "slope_wb97x_eV_per_sigma": sw, "r2_wb97x": r2w,
        "slope_ratio_wb97x_over_b3lyp": sw / sb3,
        "not_compared": not_compared,
        "os3_s2_max_accepted": S2_MAX_DOUBLET,   # what `_acceptance` holds a RECORDED <S²> to; os3_s2_not_recorded stand on `converged` alone
        "os3_s2_not_recorded": s2_not_recorded,
        "span": {"from": lo["name"], "to": hi["name"], "b3lyp_eV": span_b3, "wb97x_eV": span_w,
                 "ratio_wb97x_over_b3lyp": span_w / span_b3},
        "donor_plateau_gap_nme2_minus_nh2_eV": plateau,
        "donor_plateau_gap_same_sign": same_sign,
        "same_order_by_dE_red": ([r["name"] for r in sorted(rows, key=lambda r: r["b3lyp_dE_red_eV"])]
                                 == [r["name"] for r in sorted(rows, key=lambda r: r["wb97x_dE_red_eV"])]),
        "order_swaps": swaps,
        "centre_decomposition": centre,
        "centre_functional_and_basis_pull_opposite_ways": opposite,
        "ends_decomposition": ends,
        "acceptor_gap_so2cf3_minus_no2_eV": acceptor_gap,
        "verdict": (f"ω−B3 runs from {lo_off['omega_minus_b3_eV']:+.3f} ({lo_off['name']}) to "
                    f"{hi_off['omega_minus_b3_eV']:+.3f} eV ({hi_off['name']}), a range of "
                    f"{max(offsets) - min(offsets):.3f} eV; {order_clause}; over {', '.join(subset)} the ωB97X slope "
                    f"is {sw:+.3f} against {sb3:+.3f} eV/σ (×{sw / sb3:.2f}); the donor-plateau gap (nme2 − nh2) is "
                    f"{plateau['b3lyp'] * 1000:+.1f} ⊥ {plateau['wb97x'] * 1000:+.1f} meV, "
                    f"{'the same' if same_sign else 'an opposite'} sign. At the centre, where ωB97X also exists "
                    f"with the small basis, the local slope is {cs['b3lyp_631gd']:+.3f} (B3LYP) → "
                    f"{cs['wb97x_631gd']:+.3f} (ωB97X, same basis) → {cs['wb97x_def2tzvp']:+.3f} eV/σ (def2-TZVP): "
                    f"the functional and the basis {'pull opposite ways' if opposite else 'pull the same way'} there; "
                    f"{ends_clause}; neither tier is checked against a measured series.{gap_clause}{s2_clause}"),
    }


def _ends_decomposition(by: dict, series_smiles: dict, centre: dict, subset: list) -> dict:
    """The same split at the ends, from this script's own small-basis cache (`wb97x-631gd`), when it exists.

    Each point is rebuilt and refused unless it equals the series xyz. With the centre pair (34b) it can give every
    member of the common fit subset all three tiers — then the subset slope is reported per tier, which says how much
    of the def2-TZVP ×ratio is the functional and how much the basis. CANNOT say it for a point that has no
    small-basis value (SO₂CF₃), nor which tier is right.
    """
    small, refused, s2_not_recorded = {}, {}, []
    if OUT_WB97X_631GD.exists():
        for name, c in json.loads(OUT_WB97X_631GD.read_text(encoding="utf-8"))["complexes"].items():
            if "dE_red_eV" in c and name in by:
                os3 = _acceptance(c["os3"], True)
                if os3 not in ("accepted", "s2_not_recorded"):   # an SCF artefact must not read as a method effect
                    refused[name] = os3
                    continue
                if os3 == "s2_not_recorded":
                    s2_not_recorded.append(f"{OUT_WB97X_631GD.name}:{name}")
                atoms, _ = build_os_complex(bpy_smiles=series_smiles[name])
                dev = _series_geometry_dev(name, atoms)
                if dev > SAME_GEOMETRY_TOL_A:
                    sys.exit(f"{OUT_WB97X_631GD.name} {name} is not the series geometry (max |Δxyz| {dev} Å)")
                small[name] = (c["dE_red_eV"], dev)
    pts = sorted(({"name": n, "sigma_para": by[n]["sigma_para"], "b3lyp_631gd_eV": by[n]["b3lyp_dE_red_eV"],
                   "wb97x_631gd_eV": e, "wb97x_def2tzvp_eV": by[n]["wb97x_dE_red_eV"],
                   "functional_eV": e - by[n]["b3lyp_dE_red_eV"], "basis_eV": by[n]["wb97x_dE_red_eV"] - e,
                   "wb97x_631gd_source": OUT_WB97X_631GD.name, "geometry_max_dev_A": d}
                  for n, (e, d) in small.items()), key=lambda p: p["sigma_para"])
    tiers = {p["name"]: p for p in centre["points"] + pts}
    slopes = None
    if all(n in tiers for n in subset):
        sig = [tiers[n]["sigma_para"] for n in subset]
        slopes = {t: _ls(sig, [tiers[n][f"{t}_eV"] for n in subset])[0]
                  for t in ("b3lyp_631gd", "wb97x_631gd", "wb97x_def2tzvp")}
    return {"points": pts, "slope_over_common_subset_by_tier": slopes, "not_compared": refused,
            "s2_not_recorded": s2_not_recorded}


def _centre_decomposition(by: dict, series_smiles: dict) -> dict:
    """Split the centre pair's B3LYP/6-31G(d) → ωB97X/def2-TZVP change into functional and basis parts.

    The middle tier is the chloro form of 34b (ωB97X/6-31G(d)), built with 34b's OWN call (its FORMS row,
    imported) and refused unless that build equals the series xyz of the complex. CAN show: how much of the centre's
    offset and local slope is the functional and how much the basis. CANNOT show the same at the ends of the axis.
    """
    spec = importlib.util.spec_from_file_location("s34b", Path(__file__).with_name("34b_wb97x_speciation.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    _, axial, twists, _, _ = next(f for f in mod.FORMS if f[0] == "chloro")
    pts, s2_not_recorded = [], []
    for name, cache in WB97X_SMALL_BASIS.items():
        form = next(f for f in json.loads((DFT_CACHE / cache).read_text(encoding="utf-8"))["forms"] if f["name"] == "chloro")
        assert form["converged"], f"{cache}: chloro did not converge"
        s2_not_recorded.append(f"{cache}:chloro")   # 34b's forms carry one `converged` for both states, no <S²>
        atoms, _ = build_os_complex(bpy_smiles=series_smiles[name], axial=axial, axial_twists=twists)
        dev = _max_dev_A([(el, tuple(xyz)) for el, xyz in atoms], _read_xyz(LIGANDS_DIR / f"os_{name}_meim_cl.xyz"))
        if dev > SAME_GEOMETRY_TOL_A:
            sys.exit(f"34b chloro {name} is not the series geometry (max |Δxyz| {dev} Å)")
        small = (form["E_os2_Ha"] - form["E_os3_Ha"]) * HARTREE_TO_EV
        b3, tz = by[name]["b3lyp_dE_red_eV"], by[name]["wb97x_dE_red_eV"]
        pts.append({"name": name, "sigma_para": by[name]["sigma_para"], "b3lyp_631gd_eV": b3, "wb97x_631gd_eV": small,
                    "wb97x_def2tzvp_eV": tz, "functional_eV": small - b3, "basis_eV": tz - small,
                    "wb97x_631gd_source": f"{cache} (34b, chloro)", "geometry_max_dev_A": dev})
    pts.sort(key=lambda p: p["sigma_para"])
    lo, hi = pts[0], pts[-1]
    dsig = hi["sigma_para"] - lo["sigma_para"]
    return {"points": pts, "local_slope_eV_per_sigma": {
        t: (hi[f"{t}_eV"] - lo[f"{t}_eV"]) / dsig for t in ("b3lyp_631gd", "wb97x_631gd", "wb97x_def2tzvp")},
        "s2_not_recorded": s2_not_recorded}


def _load_cache() -> dict:
    if not OUT.exists():
        return {}
    try:
        old = json.loads(OUT.read_text(encoding="utf-8"))
        return {c["name"]: c for c in old.get("complexes", []) if c.get("converged")}
    except Exception:
        return {}


def main() -> int:
    cached = _load_cache()
    results = {
        "method": "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM(water) vertical ΔSCF",
        "model": "cis-[Os(4,4'-X-bpy)2(1-MeIm)Cl]^+/2+ — constant charge; E° + cascade vs Hammett σ_para",
        "complexes": [],
    }

    for name, smi, sigma, desc in SERIES:
        if name in cached:
            banner(f"① {name}  (σ={sigma:+.2f}) — reused from cache")
            results["complexes"].append(cached[name])
            continue
        banner(f"① {name}  (σ_para={sigma:+.2f}, {desc})")
        atoms, info = build_os_complex(bpy_smiles=smi)
        print(f"  geometry: {info['n_atoms']} atoms, min {info['min_contact_A']} Å, "
              f"Os-coord {info['os_coord_distances_A']}")
        write_xyz(atoms, LIGANDS_DIR / f"os_{name}_meim_cl.xyz",
                  f"cis-[Os({name})2(1-MeIm)Cl] programmatic octahedral")
        os2 = dft_singlepoint(atoms, charge=1, spin=0, label=f"Os(II) {name}")
        print(f"  Os(II)  E={os2['E_total_Ha']:.6f} Ha  HOMO={os2['HOMO_eV']:.3f}  "
              f"LUMO={os2['LUMO_eV']:.3f} eV  ({os2['wall_seconds']}s, conv={os2['converged']})")
        os3 = dft_singlepoint(atoms, charge=2, spin=1, label=f"Os(III) {name}")
        print(f"  Os(III) E={os3['E_total_Ha']:.6f} Ha  HOMO={os3['HOMO_eV']:.3f}  "
              f"LUMO={os3['LUMO_eV']:.3f} eV  ({os3['wall_seconds']}s, conv={os3['converged']})")
        dE_red = (os2["E_total_Ha"] - os3["E_total_Ha"]) * HARTREE_TO_EV
        print(f"  ΔE_red(III→II) = {dE_red:+.4f} eV")
        if name == "bpy":
            d = max(abs(os2["HOMO_eV"] - REF_21B["os2_HOMO"]), abs(os3["LUMO_eV"] - REF_21B["os3_LUMO"]))
            print(f"  ↳ 21b reproduction: max|Δ|={d:.3f} eV {'✅' if d < 0.05 else '❌ DIVERGES'}")
            results["reproduces_21b"] = d < 0.05
        results["complexes"].append({
            "name": name, "sigma_para": sigma, "desc": desc, "geometry": info,
            "os2": os2, "os3": os3, "dE_red_eV": dE_red,
            "converged": os2["converged"] and os3["converged"],
        })

    # ── cascade alignment Δ = HOMO(FADH₂) − LUMO(Os III) ──
    fad_path = DFT_CACHE / "lumiflavin.json"
    fadh2_homo = None
    if fad_path.exists():
        fadh2_homo = json.loads(fad_path.read_text(encoding="utf-8"))["red"]["HOMO_eV"]
        for c in results["complexes"]:
            c["cascade_delta_eV"] = round(fadh2_homo - c["os3"]["LUMO_eV"], 4)

    banner("① FULL TREND vs Hammett σ_para")
    by_sigma = sorted(results["complexes"], key=lambda c: c["sigma_para"])
    print(f"  FADH₂ HOMO = {fadh2_homo} eV (B3LYP, cache)\n")
    print("  name    σ_para   ΔE_red(eV)   Os(III)LUMO   cascadeΔ(eV)  conv")
    for c in by_sigma:
        cd = c.get("cascade_delta_eV", float("nan"))
        print(f"    {c['name']:6s} {c['sigma_para']:+.2f}   {c['dE_red_eV']:+.4f}    "
              f"{c['os3']['LUMO_eV']:+.3f}      {cd:+.4f}    {c['converged']}")

    dEs = [c["dE_red_eV"] for c in by_sigma]
    mono_E = all(dEs[i] >= dEs[i + 1] for i in range(len(dEs) - 1))
    cds = [c.get("cascade_delta_eV", 0) for c in by_sigma]
    mono_casc = all(cds[i] <= cds[i + 1] for i in range(len(cds) - 1))
    results["monotonic_with_sigma"] = mono_E
    results["cascade_monotonic"] = mono_casc
    if fadh2_homo is not None:
        best = max(by_sigma, key=lambda c: c["cascade_delta_eV"])
        results["best_cascade_mediator"] = best["name"]
        print(f"\n  E° monotonic with σ? {'✅' if mono_E else '❌'}   "
              f"cascade Δ monotonic (rises with σ)? {'✅' if mono_casc else '❌'}")
        print(f"  Most favourable cascade: {best['name']} (Δ={best['cascade_delta_eV']:+.4f} eV) "
              f"→ design rule: electron-withdrawing 4,4'-bpy improves FADH₂→Os alignment")

    # ── Hammett LFER slope (computed → JSON = single source for fig 60 / table 61 / prose) ──
    by_name = {c["name"]: c for c in results["complexes"]}
    fit_pts = [(by_name[n]["sigma_para"], by_name[n]["dE_red_eV"]) for n in REF_LFER_SET]
    lfer = _lfer_fit([s for s, _ in fit_pts], [e for _, e in fit_pts])
    lfer["fit_set"] = REF_LFER_SET
    lfer["excluded"] = {"donor_saturation": ["nme2", "nh2"], "inert_design_picks": ["cf3", "so2cf3"],
                        "measured_series_points": ["cl"]}   # added 2026-10-11 for script 83, not to move the canonical fit
    lfer["x"], lfer["y"] = "sigma_para", "dE_red_eV"
    results["lfer"] = lfer
    print(f"  ① LFER slope (OMe→NO₂, n={lfer['n']}): {lfer['slope_eV_per_sigma']:+.3f} eV/σ "
          f"(r²={lfer['r2']:.3f})")

    OUT.write_text(json.dumps(results, indent=2), encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)} ({len(results['complexes'])} complexes)")
    return 0


def _tier_21f_wb97x() -> tuple:
    """21f's own ωB97X tier (xc, basis_light, level_shift_open, out_name, conv_tol) — imported, never retyped."""
    spec = importlib.util.spec_from_file_location("s21f", Path(__file__).with_name("21f_dft_os_dimethyl.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.TIERS["wb97x"]


def _recorded_pyscf() -> str:
    explicit = Path(__file__).resolve().parents[1] / "environment.computed.explicit.txt"
    return re.search(r"/pyscf-(\d+\.\d+\.\d+)-", explicit.read_text(encoding="utf-8")).group(1)


def main_wb97x(names: list[str], small_basis: bool = False) -> int:
    import pyscf

    if pyscf.__version__ != _recorded_pyscf():
        sys.exit(f"PySCF {pyscf.__version__} is not the recorded {_recorded_pyscf()} — the ωB97X points this is "
                 f"compared with were computed there; run in silken_md")
    xc, basis_light, lshift, _, conv = _tier_21f_wb97x()
    out = OUT_WB97X
    if small_basis:   # 34b's tier: the same functional, shift and tolerance, the B3LYP tier's basis
        basis_light, out = None, OUT_WB97X_631GD
    series = {name: (smi, sigma) for name, smi, sigma, _ in SERIES}
    unknown = [n for n in names if n not in series]
    if unknown:
        sys.exit(f"not in SERIES: {unknown}")
    tier_note = " with the B3LYP tier basis — 34b's tier" if small_basis else ""
    rec = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {
        "method": f"{xc.upper()}/{basis_light or BASIS_LIGHT}+LANL2DZ(Os)+C-PCM(water) vertical ΔSCF — 21f's wb97x "
                  f"tier, imported{tier_note}; Os(III) level shift {lshift:g}, conv_tol {conv:g}",
        "environment": {"pyscf": pyscf.__version__},
        "complexes": {},
    }
    with tempfile.TemporaryDirectory() as tmp:
        for name in names:
            smi, sigma = series[name]
            c = rec["complexes"].setdefault(name, {"sigma_para": sigma})
            atoms, _ = build_os_complex(bpy_smiles=smi)
            dev = _series_geometry_dev(name, atoms)
            if dev > SAME_GEOMETRY_TOL_A:   # refused BEFORE the SCF: an off-geometry point costs seconds, not a night
                sys.exit(f"{name}: rebuilt geometry is {dev} Å off its B3LYP row — not comparable, refused")
            chk = Path(tmp) / f"{name}_os2.chk"
            for state, charge, spin, shift in (("os2", 1, 0, 0.0), ("os3", 2, 1, lshift)):
                verdict = _acceptance(c.get(state, {}), spin != 0)
                if verdict == "accepted":
                    banner(f"① ωB97X {name} {state} — reused from {out.name}")
                    continue
                if state == "os3" and _acceptance(c["os2"], False) != "accepted":
                    print(f"  {name} os3 not computed: os2 is not accepted, so its orbitals cannot start the doublet")
                    continue
                if state in c:   # a stale row is replaced, never reused because it says `converged`
                    print(f"  replacing {name} {state}: {verdict}")
                    c.pop("dE_red_eV", None)
                    _save(out, rec)   # before the SCF: a crash mid-run must not leave the stale ΔE on disk
                banner(f"① ωB97X {name} {state} (σ_para={sigma:+.2f}, PySCF {pyscf.__version__})")
                if state == "os2":
                    c[state] = dft_singlepoint(atoms, charge=charge, spin=spin, label=f"{state} {name} ({xc})",
                                               xc=xc, basis_light=basis_light, conv_tol=conv, chkfile=str(chk))
                else:
                    dm0, start = _doublet_start(atoms, chk, c["os2"], xc, basis_light, conv)
                    rerun = start["os2_rerun_delta_Ha"]
                    print(f"  doublet start: hole on Os {start['hole_os_fraction']:.3f}"
                          + ("" if rerun is None else f", Os(II) re-run ΔE {rerun:+.1e} Ha"))
                    c[state] = dft_singlepoint(atoms, charge=charge, spin=spin, label=f"{state} {name} ({xc})",
                                               xc=xc, basis_light=basis_light, conv_tol=conv,
                                               level_shift_open=shift, dm0=dm0, stability=True)
                    c[state]["start"] = start
                s2 = c[state].get("s2")
                print(f"  E={c[state]['E_total_Ha']:.8f} Ha ({c[state]['wall_seconds']}s, "
                      f"conv={c[state]['converged']}, {_acceptance(c[state], spin != 0)}"
                      + ("" if s2 is None else f", <S²> {s2:.4f}") + ")")
                _save(out, rec)
            if all(_acceptance(c[s], s == "os3") == "accepted" for s in ("os2", "os3")):
                c["dE_red_eV"] = (c["os2"]["E_total_Ha"] - c["os3"]["E_total_Ha"]) * HARTREE_TO_EV   # full precision
                _save(out, rec)
                print(f"  ΔE_red(III→II) {name} = {c['dE_red_eV']:+.6f} eV")
    if not small_basis and all("dE_red_eV" in rec["complexes"].get(n, {}) for n in WB97X_EXTREMES):
        rec["vs_b3lyp"] = _vs_b3lyp(rec)
        _save(out, rec)
        print(f"  ω−B3: {rec['vs_b3lyp']['verdict']}")
    banner(f"✅ saved {out.name}")
    return 0


# mode → (the ONE dft_singlepoint keyword set that differs from main()'s call, the method line of its cache, the comparison
# block's key, its (series, variant) column names, the rescued-rows key). The def2 names are kept: 83 and the pins read them.
_VAR = ("vs_series", ("series_mV", "variant_mV"), "rescued_rows")
VARIANTS = {
    "b3lyp-osdef2": ({"basis_os": "def2-tzvp"}, "B3LYP/6-31G(d)+def2-TZVP/ECP(Os)+C-PCM(water) vertical ΔSCF — the B3LYP "
                     "series protocol, Os basis/ECP only changed", "vs_lanl2dz", ("lanl2dz_mV", "def2tzvp_mV"), "rescued_def2_rows"),
    "b3lyp-iefpcm": ({"pcm_method": "IEF-PCM"}, "B3LYP/6-31G(d)+LANL2DZ(Os)+IEF-PCM(water) vertical ΔSCF — the B3LYP series "
                     "protocol, the boundary formulation only changed (IEF-PCM for C-PCM), the cavity unchanged", *_VAR),
    "b3lyp-uffcavity": ({"pcm_radii": "uff-1.1"}, "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM(water) vertical ΔSCF — the B3LYP series "
                        "protocol, the cavity radii only changed: UFF ×1.1 with a sphere on every H (Gaussian 16's default "
                        "radii, not its surface discretisation) for PySCF's default table — modified Bondi ×1.2, Os a 2.40 Å "
                        "placeholder (1.72 Å here)", *_VAR),
    "b3lyp-gas": ({"with_pcm": False}, "B3LYP/6-31G(d)+LANL2DZ(Os) gas phase vertical ΔSCF — the B3LYP series protocol, "
                  "the continuum only removed", *_VAR),
    "b3lyp-pyaxial": ({}, "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM(water) vertical ΔSCF — the B3LYP series protocol, the axial "
                      "N-donor only changed: pyridine for 1-methylimidazole (the aqueous series' ampy is a 4-substituted "
                      "pyridine), placed by the series builder at the same Os–N; Os, both chelates and Cl are the series' "
                      "own atoms", *_VAR),
    "b3lyp-relaxed-os2": ({}, "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM(water) vertical ΔSCF — the B3LYP series protocol, the "
                          "geometry only changed: each point's Os(II) geometry relaxed with the same protocol (geomeTRIC, "
                          "DFT grid response on; energy and gradient at Gaussian's default thresholds, displacement at its "
                          "loose ones — the flat Os–Cl mode), both states then at that geometry", *_VAR),
}
VARIANT_RELAX = {"b3lyp-relaxed-os2"}   # the knob is the geometry itself (`_relaxed_os2`)
# The knob of a geometry variant is the builder's axial set, not an SCF keyword (`_axial_swap`).
VARIANT_AXIAL = {"b3lyp-pyaxial": (("ligand", PY_SMILES, "N"), ("cl",))}


def _variant_out(mode: str) -> Path:
    """Looked up at call time, so a rehearsal can redirect each cache."""
    return {"b3lyp-osdef2": OUT_OSDEF2, "b3lyp-iefpcm": OUT_IEFPCM, "b3lyp-uffcavity": OUT_UFFCAV, "b3lyp-gas": OUT_GAS,
            "b3lyp-pyaxial": OUT_PYAXIAL, "b3lyp-relaxed-os2": OUT_RELAXED}[mode]


def _donor_distances(atoms: list) -> list:
    """Os (the builder's atom 0) to its six nearest atoms, Å, sorted — frame-free, unlike a coordinate difference."""
    os_xyz = np.asarray(atoms[0][1], float)
    return sorted(round(float(np.linalg.norm(np.asarray(x, float) - os_xyz)), 4) for _, x in atoms[1:])[:6]


def _atoms_json(atoms: list) -> list:
    return [(e, [float(v) for v in x]) for e, x in atoms]


def _relaxed_os2(out: Path, rec: dict, c: dict, name: str, atoms: list, state: str = "os2", ref_e: float | None = None):
    """Leg (3a) — and, with state="os3", leg (3б): the point's Os(II) (or Os(III)) geometry relaxed with the series
    protocol from `atoms`, whose own energy in that state is `ref_e` (default: the series row's Os(II)). A converged
    geometry in the cache is reused; a non-converged one, or the partial geometry a killed run left, is the RESTART point
    (never the start again — the same input would fail the same way); every step's lowest-energy geometry is written to
    the cache as it comes. Refused at the step: a step 0 that is not `ref_e` (another protocol or state), an Os–donor
    distance moved by more than RELAX_MAX_DONOR_SHIFT_A from the start (a units slip), an open-shell step whose <S²>
    exceeds S2_MAX_DOUBLET (§Critical Rules #14). Returns the relaxed atoms, or None when the optimisation did not
    converge — that point then has no ΔE_red and no pair, and the run goes on to the next point."""
    charge, spin, label = (1, 0, "Os(II)") if state == "os2" else (2, 1, "Os(III)")
    key, part = f"geometry_{state}_relaxed", f"geometry_{state}_partial"
    g = c.get(key)
    same = g and g["info"].get("conv_params") == RELAX_CONV and g["info"].get("scf_conv_tol") == RELAX_SCF_CONV_TOL
    if g and g["info"]["converged"] and same:
        banner(f"① b3lyp-relaxed-{state} {name} — relaxed {label} geometry reused from {out.name}")
        return [(e, np.asarray(x, float)) for e, x in g["atoms"]]
    resume = c.get(part) or g
    if resume is g and g and not any(t.get("scf_converged", True) for t in g["info"]["trajectory"]):
        resume = None   # step 0's own SCF failed: no converged energy to check a restart against — start afresh
    start = [(e, np.asarray(x, float)) for e, x in resume["atoms"]] if resume else atoms
    restarted_from = None if not resume else ("partial" if part in c else
                                              g["info"]["returned"] if not g["info"]["converged"] else "other thresholds")
    series_e = ref_e if ref_e is not None else next(
        r["os2"]["E_total_Ha"] for r in json.loads(OUT.read_text(encoding="utf-8"))["complexes"] if r["name"] == name)
    ref_dd = _donor_distances(atoms)
    # a restart is checked against the saved geometry's OWN energy — a plain start there may land in another state
    start_e = series_e if not resume else (c[part]["E_min_Ha"] if part in c else
                                           min(t["E_Ha"] for t in g["info"]["trajectory"] if t.get("scf_converged", True)))

    def keep(geom: list, tr: list):
        if len(tr) == 1 and abs(tr[0]["E_Ha"] - start_e) > RELAX_ENERGY_TOL_HA:
            sys.exit(f"{name}: step 0 is {tr[0]['E_Ha']:.8f} Ha against the start's {start_e:.8f} — "
                     f"not the series protocol or not the same state, refused")
        if spin and tr[-1].get("s2", float("inf")) > S2_MAX_DOUBLET:
            sys.exit(f"{name}: step {len(tr)} has <S²> {tr[-1].get('s2')} — not the doublet, refused")
        shift = max(abs(x - y) for x, y in zip(_donor_distances(geom), ref_dd, strict=True))
        if shift > RELAX_MAX_DONOR_SHIFT_A:
            sys.exit(f"{name}: an Os–donor distance moved by {shift:.3f} Å — a units slip, not chemistry; refused")
        c[part] = {"atoms": _atoms_json(geom), "steps": len(tr), "E_min_Ha": min(t["E_Ha"] for t in tr),
                   "restarted_from": restarted_from}
        _save(out, rec)

    banner(f"① b3lyp-relaxed-{state} {name} — relaxing {label} (≤ {RELAX_MAXSTEPS} steps"
           + (f", restarted from the {restarted_from} geometry)" if restarted_from else ")"))
    new, info = dft_optimize(start, charge=charge, spin=spin, label=f"{state} {name} relax", maxsteps=RELAX_MAXSTEPS,
                             conv_params=RELAX_CONV, on_step=keep, max_cycle=VARIANT_MAX_CYCLE,
                             conv_tol=RELAX_SCF_CONV_TOL)
    tr = info["trajectory"]
    info.update(restarted_from=restarted_from, scf_conv_tol=RELAX_SCF_CONV_TOL,
                donor_distances_A={"start": ref_dd, "relaxed": _donor_distances(new)} if state == "os3" else
                {"programmatic": ref_dd, "relaxed": _donor_distances(new)},
                step0_minus_series_Ha=(tr[0]["E_Ha"] - series_e) if tr and restarted_from is None else None,
                relaxation_meV=(series_e - min(t["E_Ha"] for t in tr)) * HARTREE_TO_EV * 1000 if tr else None)
    c[key] = {"atoms": _atoms_json(new), "info": info}
    c.pop(part, None)
    for k in (("os2", "os3", "dE_red_eV") if state == "os2" else ("os3", "dE_red_adiabatic_eV", "lambda_os3_meV")):
        c.pop(k, None)   # single points of another geometry are not this geometry's
    _save(out, rec)
    print(f"  {'converged' if info['converged'] else 'NOT converged'} in {info['steps']} steps, {info['wall_seconds']} s; "
          f"relaxation {info['relaxation_meV']} meV" + (f"; {info['error']}" if info["error"] else ""))
    return new if info["converged"] else None


def _axial_swap(name: str, series_atoms: list, smi: str, axial: tuple) -> list:
    """Rebuild a series complex with another axial set; refused unless Os, both chelates and the chloride are the series'
    own atoms (the builder's order: Os · bpy₁ · bpy₂ · axial[0] · Cl), so the axial ligand is the one thing changed."""
    var, _ = build_os_complex(bpy_smiles=smi, axial=axial)
    k = len(series_atoms) - len(build_monodentate(MEIM_SMILES)[0]) - 1
    dev = max(_max_dev_A(var[:k], series_atoms[:k]), _max_dev_A(var[-1:], series_atoms[-1:]))
    if dev > SAME_GEOMETRY_TOL_A or var[-1][0] != "Cl":
        sys.exit(f"{name}: the {axial[0][1]} build moves the rest of the octahedron ({dev} Å) — not one knob, refused")
    return var


def _vs_series(rec: dict, mode: str) -> dict:
    """Per-substituent pair shifts of E° (mV, −ΔΔE_red/4) in the series cache ⊥ this variant's cache.

    CAN show: how much of each pair the one changed knob moves, on the same geometry and the same SCF protocol.
    CANNOT show: which of the two is nearer experiment — that is `83`'s job, against its measured series."""
    _, _, _, (col_s, col_v), rescued_key = VARIANTS[mode]
    rows = json.loads(OUT.read_text(encoding="utf-8"))["complexes"]
    base = {c["name"]: c["dE_red_eV"] for c in rows}
    d2 = {n: c["dE_red_eV"] for n, c in rec["complexes"].items() if "dE_red_eV" in c}
    pairs = []
    for x, ref in VARIANT_PAIRS:
        if x in d2 and ref in d2:
            lo, hi = -(base[x] - base[ref]) / N_SUBST * 1000, -(d2[x] - d2[ref]) / N_SUBST * 1000
            pairs.append({"x": x, "ref": ref, col_s: lo, col_v: hi, "change_mV": hi - lo})
    rescued = sorted(n for n, c in rec["complexes"].items() for s in ("os2", "os3") if c.get(s, {}).get("rescued"))
    out = {"pairs": pairs, "point_shift_eV": {n: d2[n] - base[n] for n in d2}, rescued_key: rescued}
    if mode != "b3lyp-osdef2":   # the series side of each pair stands on `converged` where its row predates <S²> (§Critical Rules #14)
        out["series_os3_s2_not_recorded"] = sorted(c["name"] for c in rows if c["name"] in d2 and "s2" not in c["os3"])
    return out


def main_variant(mode: str, names: list[str]) -> int:
    """The B3LYP series protocol (plain start, no level shift, its tolerance) with ONE knob changed — nothing else moves."""
    import pyscf

    if pyscf.__version__ != _recorded_pyscf():
        sys.exit(f"PySCF {pyscf.__version__} is not the recorded {_recorded_pyscf()} — the series rows it is compared with "
                 f"were computed there; run in silken_md")
    kw, method, cmp_key, (col_s, col_v), _ = VARIANTS[mode]
    out = _variant_out(mode)
    series = {name: (smi, sigma) for name, smi, sigma, _ in SERIES}
    unknown = [n for n in names if n not in series]
    if unknown:
        sys.exit(f"not in SERIES: {unknown}")
    rec = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {
        "method": f"{method}; max_cycle {VARIANT_MAX_CYCLE} as the June LANL2DZ rows",
        "environment": {"pyscf": pyscf.__version__}, "complexes": {}}
    rec.pop(cmp_key, None)   # rebuilt at the end — a crash mid-run must not leave a comparison of rows since replaced
    for name in names:
        smi, sigma = series[name]
        c = rec["complexes"].setdefault(name, {"sigma_para": sigma})
        atoms, _ = build_os_complex(bpy_smiles=smi)
        dev = _series_geometry_dev(name, atoms)
        if dev > SAME_GEOMETRY_TOL_A:   # refused BEFORE the SCF
            sys.exit(f"{name}: rebuilt geometry is {dev} Å off its B3LYP row — not comparable, refused")
        if mode in VARIANT_AXIAL:
            atoms = _axial_swap(name, atoms, smi, VARIANT_AXIAL[mode])
        if mode in VARIANT_RELAX:
            atoms = _relaxed_os2(out, rec, c, name, atoms)
            if atoms is None:
                continue
        for state, charge, spin in (("os2", 1, 0), ("os3", 2, 1)):
            verdict = _acceptance(c.get(state, {}), spin != 0)
            if verdict == "accepted":
                banner(f"① {mode} {name} {state} — reused from {out.name}")
                continue
            if state in c:
                print(f"  replacing {name} {state}: {verdict}")
                c.pop("dE_red_eV", None)
                _save(out, rec)
            banner(f"① {mode} {name} {state} (σ_para={sigma:+.2f}, PySCF {pyscf.__version__})")
            c[state] = dft_singlepoint(atoms, charge=charge, spin=spin, label=f"{state} {name} ({mode})",
                                       max_cycle=VARIANT_MAX_CYCLE, **kw)
            s2 = c[state].get("s2")
            print(f"  E={c[state]['E_total_Ha']:.8f} Ha ({c[state]['wall_seconds']}s, {_acceptance(c[state], spin != 0)}"
                  + ("" if s2 is None else f", <S²> {s2:.4f}") + ")")
            _save(out, rec)
        if mode in VARIANT_RELAX and "os2" in c:   # the single point must sit on the optimiser's last step
            last = c["geometry_os2_relaxed"]["info"]["trajectory"][-1]["E_Ha"]
            c["os2_minus_last_step_Ha"] = c["os2"]["E_total_Ha"] - last
            if abs(c["os2_minus_last_step_Ha"]) > RELAX_ENERGY_TOL_HA:
                _save(out, rec)
                sys.exit(f"{name}: the Os(II) single point is {c['os2_minus_last_step_Ha']:+.2e} Ha off the optimiser's "
                         f"last step — not on the relaxed geometry, refused")
        if all(_acceptance(c[s], s == "os3") == "accepted" for s in ("os2", "os3")):
            c["dE_red_eV"] = (c["os2"]["E_total_Ha"] - c["os3"]["E_total_Ha"]) * HARTREE_TO_EV
            _save(out, rec)
            print(f"  ΔE_red(III→II) {name} = {c['dE_red_eV']:+.6f} eV")
    rec[cmp_key] = _vs_series(rec, mode)
    _save(out, rec)
    for p in rec[cmp_key]["pairs"]:
        print(f"  {p['x']}−{p['ref']}: {p[col_s]:+.1f} (series) → {p[col_v]:+.1f} mV ({mode})")
    banner(f"✅ saved {out.name}")
    return 0


def main_relaxed_os3(names: list[str]) -> int:
    """Leg (3б) of 00_07 HW.5.IS: each point's Os(III) relaxed with the series protocol from its relaxed Os(II) geometry
    (`b3lyp-relaxed-os2`, which must hold an accepted point) — the adiabatic ΔE_red = E(Os(II) at its minimum) −
    E(Os(III) at its own), and λ_III = E(Os(III) vertical at the Os(II) minimum) − E(Os(III) at its own). The Os(II)
    side is the os2 cache's own record (the same geometry and protocol), never recomputed; its vertical Os(III) is the
    step-0 reference, so the optimiser must start in the same state.
    CAN show: how much of each point and pair the Os(III) state's own relaxation moves — the «vertical» assumption, and
    the size of the point shift the trigger of D is read on (PIPELINE_STATUS, D). CANNOT show: free energies, or which
    geometry is nearer the real complex."""
    import pyscf

    if pyscf.__version__ != _recorded_pyscf():
        sys.exit(f"PySCF {pyscf.__version__} is not the recorded {_recorded_pyscf()} — run in silken_md")
    src = json.loads(OUT_RELAXED.read_text(encoding="utf-8"))["complexes"]
    out = OUT_RELAXED3
    rec = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {
        "method": "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM(water) adiabatic ΔSCF — the B3LYP series protocol; Os(II) at its "
                  f"relaxed geometry ({OUT_RELAXED.name}), Os(III) relaxed from it with the same optimiser and thresholds; "
                  f"max_cycle {VARIANT_MAX_CYCLE}",
        "environment": {"pyscf": pyscf.__version__}, "complexes": {}}
    rec.pop("vs_vertical", None)   # rebuilt at the end
    for name in names:
        s = src.get(name, {})
        g2 = s.get("geometry_os2_relaxed")
        if not (g2 and g2["info"]["converged"] and "dE_red_eV" in s
                and all(_acceptance(s.get(k, {}), k == "os3") == "accepted" for k in ("os2", "os3"))):
            sys.exit(f"{name}: no accepted relaxed Os(II) point in {OUT_RELAXED.name} — run b3lyp-relaxed-os2 first")
        if s["os3"].get("rescued"):   # its energy is step 0's reference, and the optimiser has no rescue path
            sys.exit(f"{name}: the vertical Os(III) in {OUT_RELAXED.name} needed the Newton rescue — no reference step 0 "
                     f"can reach (in-silico §Critical Rules #14), refused")
        if s["os3"].get("os_spin_mulliken", 1.0) < OS3_MIN_OS_SPIN:
            sys.exit(f"{name}: the vertical Os(III) holds {s['os3']['os_spin_mulliken']:.2f} of its spin on Os — the hole "
                     f"is not on the metal, so this is not the Os(III/II) couple; refused")
        c = rec["complexes"].setdefault(name, {"sigma_para": s["sigma_para"]})
        if "os2_E_Ha" in c and c["os2_E_Ha"] != s["os2"]["E_total_Ha"]:   # the Os(II) start moved: nothing here is its
            print(f"  {name}: the relaxed Os(II) point changed in {OUT_RELAXED.name} — its Os(III) record is discarded")
            for k in [k for k in c if k != "sigma_para"]:
                c.pop(k)
        c.update(os2_E_Ha=s["os2"]["E_total_Ha"], os3_vertical_E_Ha=s["os3"]["E_total_Ha"],
                 dE_red_vertical_eV=s["dE_red_eV"], source=OUT_RELAXED.name)
        atoms = _relaxed_os2(out, rec, c, name, [(e, np.asarray(x, float)) for e, x in g2["atoms"]], state="os3",
                             ref_e=s["os3"]["E_total_Ha"])
        if atoms is None:
            continue
        if _acceptance(c.get("os3", {}), True) != "accepted":
            if "os3" in c:
                print(f"  replacing {name} os3: {_acceptance(c['os3'], True)}")
            banner(f"① b3lyp-relaxed-os3 {name} os3 at its own minimum (PySCF {pyscf.__version__})")
            c["os3"] = dft_singlepoint(atoms, charge=2, spin=1, label=f"os3 {name} (b3lyp-relaxed-os3)",
                                       max_cycle=VARIANT_MAX_CYCLE)
            _save(out, rec)
        verdict = _acceptance(c["os3"], True)
        print(f"  E={c['os3']['E_total_Ha']:.8f} Ha ({c['os3']['wall_seconds']}s, {verdict}, <S²> {c['os3'].get('s2')})")
        if verdict != "accepted":
            continue
        if c["os3"].get("rescued"):   # <S²> passes, but a rescue starts from the failed orbitals (§Critical Rules #14):
            c["os3_refused"] = "the single point needed the Newton rescue — its state is not certified"   # recorded
            c.pop("os3")
            _save(out, rec)
            print(f"  {name}: refused — {c['os3_refused']}")
            continue
        off = c["os3"]["E_total_Ha"] - c["geometry_os3_relaxed"]["info"]["trajectory"][-1]["E_Ha"]
        if abs(off) > RELAX_ENERGY_TOL_HA:   # not dropped silently, not kept: the next point still runs
            c["os3_refused"] = (f"the plain-start single point is {off:+.2e} Ha off the optimiser's last step — "
                                + ("a lower state: the optimiser followed an excited one" if off < 0 else
                                   "a higher state, or not this geometry"))
            c.pop("os3")
            _save(out, rec)
            print(f"  {name}: refused — {c['os3_refused']}")
            continue
        c.pop("os3_refused", None)
        c["os3_minus_last_step_Ha"] = off
        c["dE_red_adiabatic_eV"] = (c["os2_E_Ha"] - c["os3"]["E_total_Ha"]) * HARTREE_TO_EV
        c["lambda_os3_meV"] = (c["os3_vertical_E_Ha"] - c["os3"]["E_total_Ha"]) * HARTREE_TO_EV * 1000
        _save(out, rec)
        print(f"  ΔE_red adiabatic {name} = {c['dE_red_adiabatic_eV']:+.6f} eV (λ_III {c['lambda_os3_meV']:.1f} meV)")
    rec["vs_vertical"] = _vs_vertical(rec)
    _save(out, rec)
    for n, v in rec["vs_vertical"]["point_shift_eV"].items():
        print(f"  {n}: adiabatic − series (programmatic, vertical) = {v:+.4f} eV")
    banner(f"✅ saved {out.name}")
    return 0


def _vs_vertical(rec: dict) -> dict:
    """Each adiabatic point ⊥ the series row (programmatic geometry, vertical) and ⊥ the (3a) vertical point; the
    per-substituent pairs (mV, −ΔΔE_red/4) in all three. CANNOT show which is nearer experiment — that is `83`."""
    base = {c["name"]: c["dE_red_eV"] for c in json.loads(OUT.read_text(encoding="utf-8"))["complexes"]}
    d = {n: c for n, c in rec["complexes"].items() if "dE_red_adiabatic_eV" in c}
    cols = {"series_mV": base, "relaxed_os2_mV": {n: c["dE_red_vertical_eV"] for n, c in d.items()},
            "adiabatic_mV": {n: c["dE_red_adiabatic_eV"] for n, c in d.items()}}
    pairs = [{"x": x, "ref": r, **{k: -(e[x] - e[r]) / N_SUBST * 1000 for k, e in cols.items()}}
             for x, r in VARIANT_PAIRS if x in d and r in d]
    for p in pairs:
        p["change_mV"] = p["adiabatic_mV"] - p["relaxed_os2_mV"]
    return {"pairs": pairs, "point_shift_eV": {n: c["dE_red_adiabatic_eV"] - base[n] for n, c in d.items()},
            "lambda_os3_meV": {n: c["lambda_os3_meV"] for n, c in d.items()}}


def main_os_basis(names: list[str]) -> int:
    return main_variant("b3lyp-osdef2", names)


def main_compare() -> int:
    """Rewrite `vs_b3lyp` from the caches alone — no SCF, so no reuse question and no recompute of a row whose
    <S²> was written before it was recorded (that is the strict reuse of main_wb97x, and it would cost a night)."""
    rec = json.loads(OUT_WB97X.read_text(encoding="utf-8"))
    missing = [n for n in WB97X_EXTREMES if "dE_red_eV" not in rec["complexes"].get(n, {})]
    if missing:
        sys.exit(f"{OUT_WB97X.name}: no accepted ΔE_red for {missing} — nothing to compare")
    rec["vs_b3lyp"] = _vs_b3lyp(rec)
    _save(OUT_WB97X, rec)
    print(f"  ω−B3: {rec['vs_b3lyp']['verdict']}")
    banner(f"✅ saved {OUT_WB97X.name}")
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["wb97x-631gd"]:
        raise SystemExit(main_wb97x(sys.argv[2:] or WB97X_631GD_ENDS, small_basis=True))
    if sys.argv[1:2] == ["b3lyp-relaxed-os3"]:
        raise SystemExit(main_relaxed_os3(sys.argv[2:] or RELAX_POINTS))
    if sys.argv[1:2] and sys.argv[1] not in {"wb97x", "wb97x-631gd", "wb97x-compare", *VARIANTS}:
        sys.exit(f"unknown mode {sys.argv[1]!r} — a typo would fall through to main() and rewrite {OUT.name}")
    if sys.argv[1:2] and sys.argv[1] in VARIANTS:
        raise SystemExit(main_variant(sys.argv[1], sys.argv[2:] or (RELAX_POINTS if sys.argv[1] in VARIANT_RELAX
                                                                    else VARIANT_POINTS)))
    if sys.argv[1:2] == ["wb97x-compare"]:
        raise SystemExit(main_compare())
    raise SystemExit(main_wb97x(sys.argv[2:] or WB97X_EXTREMES) if sys.argv[1:2] == ["wb97x"] else main())
