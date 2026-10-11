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
"""
from __future__ import annotations

import importlib.util
import json
import os
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import BASIS_LIGHT, DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT, S2_MAX_DOUBLET
from lib.dft_utils import dft_singlepoint
from lib.os_geometry import BPY_SMILES, DCBPY_SMILES, DMBPY_SMILES, build_os_complex, write_xyz
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
# The B3LYP series protocol with ONE change — def2-TZVP and its ECP on osmium instead of LANL2DZ (00_07 HW.5.IS: which part of
# our protocol carries the Me excess the aqueous measured series shows). Own cache; the points of that comparison by default.
OUT_OSDEF2 = DFT_CACHE / "os_mediator_series_osdef2.json"
OSDEF2_POINTS = ["bpy", "dmbpy", "ome", "cl"]
N_SUBST = 4   # two 4,4'-X2-bpy per complex
OSDEF2_MAX_CYCLE = 400   # the LANL2DZ rows of bpy · dmbpy · ome were run at 400 cycles, no Newton rescue (c60e01d09, 2026-06-05);
                         # cl at today's 100 + rescue converged unrescued — 400 keeps every pair on the path its row took
OSDEF2_PAIRS = (("dmbpy", "bpy"), ("ome", "bpy"), ("cl", "bpy"), ("ome", "dmbpy"), ("cl", "dmbpy"), ("cl", "ome"))
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
        print(f"  Least-uphill cascade: {best['name']} (Δ={best['cascade_delta_eV']:+.4f} eV) "
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


def _vs_lanl2dz(rec: dict) -> dict:
    """Per-substituent pair shifts of E° (mV, −ΔΔE_red/4) with LANL2DZ (the series cache) ⊥ def2-TZVP/ECP (this cache) on Os.

    CAN show: how much of each pair the osmium basis/ECP moves, on the same geometry and the same SCF protocol.
    CANNOT show: which of the two is nearer experiment — that is `83`'s job, against its measured series."""
    lanl = {c["name"]: c["dE_red_eV"] for c in json.loads(OUT.read_text(encoding="utf-8"))["complexes"]}
    d2 = {n: c["dE_red_eV"] for n, c in rec["complexes"].items() if "dE_red_eV" in c}
    pairs = []
    for x, ref in OSDEF2_PAIRS:
        if x in d2 and ref in d2:
            lo, hi = -(lanl[x] - lanl[ref]) / N_SUBST * 1000, -(d2[x] - d2[ref]) / N_SUBST * 1000
            pairs.append({"x": x, "ref": ref, "lanl2dz_mV": lo, "def2tzvp_mV": hi, "change_mV": hi - lo})
    rescued = sorted(n for n, c in rec["complexes"].items() for s in ("os2", "os3") if c.get(s, {}).get("rescued"))
    return {"pairs": pairs, "point_shift_eV": {n: d2[n] - lanl[n] for n in d2}, "rescued_def2_rows": rescued}


def main_os_basis(names: list[str]) -> int:
    """The B3LYP series protocol (plain start, no level shift, its tolerance) with def2-TZVP/ECP on Os — nothing else moves."""
    import pyscf

    if pyscf.__version__ != _recorded_pyscf():
        sys.exit(f"PySCF {pyscf.__version__} is not the recorded {_recorded_pyscf()} — the LANL2DZ rows it is compared with "
                 f"were computed there; run in silken_md")
    series = {name: (smi, sigma) for name, smi, sigma, _ in SERIES}
    unknown = [n for n in names if n not in series]
    if unknown:
        sys.exit(f"not in SERIES: {unknown}")
    rec = json.loads(OUT_OSDEF2.read_text(encoding="utf-8")) if OUT_OSDEF2.exists() else {
        "method": "B3LYP/6-31G(d)+def2-TZVP/ECP(Os)+C-PCM(water) vertical ΔSCF — the B3LYP series protocol, Os basis/ECP only "
                  f"changed; max_cycle {OSDEF2_MAX_CYCLE} as the June LANL2DZ rows",
        "environment": {"pyscf": pyscf.__version__}, "complexes": {}}
    rec.pop("vs_lanl2dz", None)   # rebuilt at the end — a crash mid-run must not leave a comparison of rows since replaced
    for name in names:
        smi, sigma = series[name]
        c = rec["complexes"].setdefault(name, {"sigma_para": sigma})
        atoms, _ = build_os_complex(bpy_smiles=smi)
        dev = _series_geometry_dev(name, atoms)
        if dev > SAME_GEOMETRY_TOL_A:   # refused BEFORE the SCF
            sys.exit(f"{name}: rebuilt geometry is {dev} Å off its B3LYP row — not comparable, refused")
        for state, charge, spin in (("os2", 1, 0), ("os3", 2, 1)):
            verdict = _acceptance(c.get(state, {}), spin != 0)
            if verdict == "accepted":
                banner(f"① def2(Os) {name} {state} — reused from {OUT_OSDEF2.name}")
                continue
            if state in c:
                print(f"  replacing {name} {state}: {verdict}")
                c.pop("dE_red_eV", None)
                _save(OUT_OSDEF2, rec)
            banner(f"① def2(Os) {name} {state} (σ_para={sigma:+.2f}, PySCF {pyscf.__version__})")
            c[state] = dft_singlepoint(atoms, charge=charge, spin=spin, label=f"{state} {name} (b3lyp, def2 Os)",
                                       basis_os="def2-tzvp", max_cycle=OSDEF2_MAX_CYCLE)
            s2 = c[state].get("s2")
            print(f"  E={c[state]['E_total_Ha']:.8f} Ha ({c[state]['wall_seconds']}s, {_acceptance(c[state], spin != 0)}"
                  + ("" if s2 is None else f", <S²> {s2:.4f}") + ")")
            _save(OUT_OSDEF2, rec)
        if all(_acceptance(c[s], s == "os3") == "accepted" for s in ("os2", "os3")):
            c["dE_red_eV"] = (c["os2"]["E_total_Ha"] - c["os3"]["E_total_Ha"]) * HARTREE_TO_EV
            _save(OUT_OSDEF2, rec)
            print(f"  ΔE_red(III→II) {name} = {c['dE_red_eV']:+.6f} eV")
    rec["vs_lanl2dz"] = _vs_lanl2dz(rec)
    _save(OUT_OSDEF2, rec)
    for p in rec["vs_lanl2dz"]["pairs"]:
        print(f"  {p['x']}−{p['ref']}: {p['lanl2dz_mV']:+.1f} (LANL2DZ) → {p['def2tzvp_mV']:+.1f} mV (def2-TZVP)")
    banner(f"✅ saved {OUT_OSDEF2.name}")
    return 0


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
    if sys.argv[1:2] == ["b3lyp-osdef2"]:
        raise SystemExit(main_os_basis(sys.argv[2:] or OSDEF2_POINTS))
    if sys.argv[1:2] == ["wb97x-compare"]:
        raise SystemExit(main_compare())
    raise SystemExit(main_wb97x(sys.argv[2:] or WB97X_EXTREMES) if sys.argv[1:2] == ["wb97x"] else main())
