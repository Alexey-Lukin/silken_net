#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L3b — fragment-orbital (FO-DFT-style) electronic coupling t_ij for the Cu-Co ZIF hop.

Rigorous upgrade of script 24's crude coupling (which relied on finding two charge-
localised SCF minima by initial-guess biasing, with a 0.05 eV fallback when they
collapsed to the same state). Here we do a single dimer SCF and extract the diabatic
coupling by **two-state diabatisation**:

  1. one UKS dimer SCF on the clash-free Cu-Co cluster (script 23 geometry);
  2. pick, within a fixed window HOMO−5 … LUMO+3 of the α channel, the two MOs with the largest combined
     Cu + Co Mulliken population (all AOs of the two atoms, not d alone) — the donor/acceptor pair (or their
     bonding/antibonding combination);
  3. **localise** that 2-orbital space (manual 2×2 population localisation — diagonalise the Cu-projected
     population matrix; lo.PM/lo.Boys crash on a PySCF lib.einsum bug) → one orbital on Cu, one on Co;
  4. H_ab (= t_ij) is the off-diagonal of the Fock matrix in that localised basis; the diagonals are the
     site energies, and their difference is a gas-phase one-electron orbital-energy gap — not a free energy,
     and its sign is not fixed here (script 25 carries it as a bracket on ΔG).

This is a two-orbital population localisation — labelled FO-DFT in the paper's tables and figures, but
neither the textbook fragment-orbital basis nor the dipole-based generalised Mulliken–Hush scheme, and no
specific published implementation — nor novelty — is claimed (attribution withdrawn 2026-10-02 —
docs/protocols/ebfc/in_silico/paper/09_references.md, the FO-DFT line). It needs no
fragment-basis counterpoise bookkeeping and no SCF-state biasing. It is an electron-coupling estimate,
not a CDFT diabatic state (that remains the capstone). A physicality band flags a non-sensical coupling
(cf. the script-29 λ closure), and because that flag tests only localisation and the t_ij band, the cache
also records what it cannot see — the window, the picks relative to the HOMO and whether one sits at its
edge, their ε and populations, the localisation's 2θ, the charge and ⟨S²⟩ (in-silico §When Modifying #49).

NB: only the Cu-Co bottleneck is recomputed (script 24 found it rate-limiting); the
other two hops are far from limiting and keep their script-24 ΔSCF t_ij.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np
from pyscf import dft, gto

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import BASIS_LIGHT, DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT
from lib.utils import banner

# One cache per MODEL (§When Modifying #17): a geometry change takes its own out-path,
# so a variant run can never silently replace the shipped verdict.
GEOMETRIES: dict[str, tuple[str, str, str]] = {
    "shipped": ("cu_co_zif.xyz", "fodft_coupling.json",
                "legacy centre-of-mass bridge orientation, 2-methylimidazolate — "
                "the shipped cathode stack"),
    # ⛔ REFUSED geometry, kept buildable on purpose: script 23 exits 1 on it because the
    # metals sit 0.70 / 1.37 Å off their own bridge-ring plane. It is here to MEASURE how
    # far the coupling rides on a ring roll nobody has determined — a sensitivity probe,
    # never a candidate. Build it with `23 --solve-bridge --roll perpendicular`.
    "offplane": ("cu_co_zif_solved_perp.xyz", "fodft_coupling_offplane.json",
                 "REFUSED probe — bridge ring rolled out of the metals' coordination "
                 "plane; prices the model's geometric freedom, not a better cluster"),
}
CHARGE, SPIN = 1, 2                       # clash-free Cu-Co cluster (script 23/24)
# ⚠️ Both are hardcoded, and script 23 prints the electron count precisely so a
# geometry whose parity flips is caught by the reader rather than by a wrong answer.
BASIS_METALS = {"Cu": "lanl2dz", "Co": "lanl2dz"}
ECP_METALS = {"Cu": "lanl2dz", "Co": "lanl2dz"}


def crude_cu_co_t_ij() -> float:
    """script-24's crude Cu-Co ΔSCF t_ij, read from its cache at runtime — drift-proof (mirrors the
    SSOT `zif_hopping.json`, never a hardcoded copy that silently diverges if script 24 is re-run)."""
    z = json.loads((DFT_CACHE / "zif_hopping.json").read_text())
    return next(p["t_ij_eV"] for p in z["pairs"] if {p["metal1"], p["metal2"]} == {"Cu", "Co"})


def read_xyz(path: Path):
    lines = path.read_text().strip().split("\n")
    n = int(lines[0])
    return [(p[0], (float(p[1]), float(p[2]), float(p[3])))
            for p in (ln.split() for ln in lines[2:2 + n])]


def mo_metal_pop(mol, C, S, metal_idx):
    """Per-MO Mulliken population on the given atom indices (rows of C are AOs)."""
    ao_atom = mol.ao_labels(fmt=None)              # (atom_id, symbol, ...) per AO
    rows = [i for i, lab in enumerate(ao_atom) if lab[0] in metal_idx]
    SC = S @ C
    return (C[rows, :] * SC[rows, :]).sum(axis=0)  # pop_i on those atoms, per MO


def converge(mol, conv_tol: float = 1e-10, conv_tol_grad: float = 3e-7, level_shift: float = 0.3,
             max_cycle: int = 300) -> tuple:
    """The dimer SCF — ONE home (24d imports it): a level-shifted DIIS (Newton if it stalls) to reach the basin, then an
    UNSHIFTED DIIS polish from that density to `conv_tol_grad`, the polished solution's internal stability, and the orbital
    gradient it actually stopped at, measured on a fresh Fock build.

    Why the polish: t_ij is an off-diagonal Fock element, so it carries the residual Fock error — of the order of the orbital
    gradient the SCF stops at — and |g| / t_ij is its relative resolution. PySCF's default stop is |g| < √conv_tol: at
    conv_tol 1e-6 the shipped t_ij came out ×3.7 high, and at 1e-10 two routes to one minimum (E within 4e-8 Ha, the same
    populations) still gave t_ij 17 % apart (2026-10-31). On O₂ a Newton run to a 1e-7 gradient stalled at 2e-7 where the
    unshifted DIIS reached 6e-9, hence DIIS for the polish; the shift stays a path knob, and the endpoint does not depend on
    it. The target sits ABOVE the cluster's numerical floor, not on it: in the STO-3G rehearsal two polishes from the same
    stage-1 energy (to 1e-8 Ha) ended at |g| 7e-8 after 18 cycles and stalled at 1.7e-7 for 100 — 1e-7 is grid noise, and
    3e-7 still resolves the shipped t_ij (≈ 5.4e-5 Ha) to ≈ 0.5 %. «converged» certifies a stationary point, not a minimum
    (Critical Rule #14): the orbital Hessian says which.
    """
    mf = dft.UKS(mol)
    mf.xc = "b3lyp"
    mf.conv_tol, mf.max_cycle, mf.level_shift, mf.verbose = conv_tol, max_cycle, level_shift, 0
    mf.kernel()
    rescued = not mf.converged
    if rescued:
        mf = mf.newton()
        mf.max_cycle = 100
        mf.kernel()
    pol = dft.UKS(mol)
    pol.xc = "b3lyp"
    pol.conv_tol, pol.conv_tol_grad, pol.max_cycle, pol.verbose = conv_tol, conv_tol_grad, 100, 0
    e_scf = pol.kernel(dm0=mf.make_rdm1())
    ss, _mult = pol.spin_square()
    _, _, stable, _ = pol.stability(internal=True, external=False, return_status=True)
    g = float(np.linalg.norm(pol.get_grad(pol.mo_coeff, pol.mo_occ)))
    # stage 1's own end, so a polish that slid into another state shows as an energy step, not as a self-consistent record
    return pol, {"stage1_converged": bool(mf.converged), "E_stage1_Ha": round(float(mf.e_tot), 8),
                 "scf_converged": bool(pol.converged), "newton_rescue": rescued, "polish_cycles": int(pol.cycles),
                 "conv_tol": conv_tol, "conv_tol_grad": conv_tol_grad, "level_shift": level_shift,
                 "E_scf_Ha": round(float(e_scf), 8), "stable_internal": bool(stable),
                 "orbital_grad_norm_Ha": float(f"{g:.2e}"), "S2": round(float(ss), 4)}


def couple(mol, mf, cu_idx, partner_idx, partner: str = "Co") -> dict:
    """The two-state diabatisation — ONE home (24d and 24e import it): window, pick, 2×2 localisation, t_ij, gap, physicality.

    The physicality check asks «two localised orbitals on distinct metals, t_ij inside a band» and nothing else, so the
    record carries what it cannot see (in-silico §When Modifying #49): the window, the picks relative to the HOMO and
    whether one sits at the window's edge, their canonical ε and metal populations, the two-state mixing angle 2θ —
    tan 2θ = 2·t_ij / gap, label-free, so a small 2θ says the gap is nearly the canonical ε difference of the pair — and
    the SIGNED site-energy difference, Cu-localised minus partner-localised, which the reported |gap| folds away.
    """
    S = mf.get_ovlp()
    # work in the alpha channel (the open-shell / hole-transfer channel)
    C, eps = mf.mo_coeff[0], mf.mo_energy[0]
    nocc = int((mf.mo_occ[0] > 0).sum())
    # frontier window around the SOMO/HOMO; pick the 2 MOs with the most Cu+Co metal weight
    lo_i, hi_i = max(0, nocc - 6), min(C.shape[1], nocc + 4)
    pop_cu = mo_metal_pop(mol, C, S, cu_idx)
    pop_p = mo_metal_pop(mol, C, S, partner_idx)
    cand = sorted(range(lo_i, hi_i), key=lambda i: -(pop_cu[i] + pop_p[i]))[:2]
    i, j = sorted(cand)
    # localise the 2-orbital space → one orbital on Cu, one on Co. lo.PM / lo.Boys crash here on a
    # PySCF lib.einsum version bug, so do the 2×2 diabatisation by hand: diagonalise the Cu-projected
    # population matrix in the {i,j} MO basis → rotation R that localises one orbital on Cu, the other
    # off-Cu (= the partner); H_ab = off-diagonal of the Fock in that basis (F is diagonal = ε in the MO basis,
    # MOs orthonormal, so Floc = Rᵀ·diag(εᵢ,εⱼ)·R — a population-based localisation).
    ao_atom = mol.ao_labels(fmt=None)
    rows_cu = [a for a, lab in enumerate(ao_atom) if lab[0] in cu_idx]
    SC = S @ C
    mos = [i, j]
    Pcu = np.array([[0.5 * sum(C[r, mos[x]] * SC[r, mos[y]] + C[r, mos[y]] * SC[r, mos[x]]
                               for r in rows_cu) for y in range(2)] for x in range(2)])
    _, R = np.linalg.eigh(Pcu)
    Cloc = C[:, mos] @ R
    Floc = R.T @ np.diag([eps[i], eps[j]]) @ R       # 2×2 Fock in the localised (diabatic) basis (Ha)
    t_ij = abs(Floc[0, 1]) * HARTREE_TO_EV
    gap = abs(Floc[0, 0] - Floc[1, 1]) * HARTREE_TO_EV
    p_cu = mo_metal_pop(mol, Cloc, S, cu_idx)
    p_p = mo_metal_pop(mol, Cloc, S, partner_idx)
    k_cu = int(np.argmax(p_cu))                   # the Cu-localised orbital of the pair
    localised = bool(max(p_cu[0], p_cu[1]) > 0.3 and max(p_p[0], p_p[1]) > 0.3)
    physical = bool((1e-5 < t_ij < 1.0) and localised)
    return {
        "nocc_alpha": nocc, "window": [lo_i, hi_i], "picked_MOs": [int(i), int(j)],
        "picked_rel_HOMO": [int(i) - (nocc - 1), int(j) - (nocc - 1)],
        "pick_at_window_edge": bool(i == lo_i or j == hi_i - 1),
        "eps_picked_eV": [float(eps[i] * HARTREE_TO_EV), float(eps[j] * HARTREE_TO_EV)],
        "partner": partner,
        "pop_cu_picked": [float(pop_cu[i]), float(pop_cu[j])], "pop_partner_picked": [float(pop_p[i]), float(pop_p[j])],
        "t_ij_eV": float(t_ij), "site_energy_gap_eV": float(gap),
        "site_energy_cu_minus_partner_eV": float((Floc[k_cu, k_cu] - Floc[1 - k_cu, 1 - k_cu]) * HARTREE_TO_EV),
        "localisation_2theta_deg": float(np.degrees(np.arctan2(2 * t_ij, gap))),
        "loc_pop_cu": [float(p_cu[0]), float(p_cu[1])], "loc_pop_partner": [float(p_p[0]), float(p_p[1])],
        "localised": localised, "physically_reasonable": physical,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--geometry", choices=sorted(GEOMETRIES), default="shipped",
                    help="which script-23 cluster to couple")
    ap.add_argument("--conv-tol", type=float, default=1e-10,
                    help="SCF energy tolerance (Ha). 1e-10 since 2026-10-30: at 1e-6 both clusters stopped short of their "
                         "minima, by 1.8–5.3e-5 Ha, and t_ij moved with them")
    ap.add_argument("--conv-tol-grad", type=float, default=3e-7,
                    help="orbital-gradient target of the final unshifted polish (Ha); |g| / t_ij is t_ij's relative "
                         "resolution (see `converge`, which also says why not lower). 3e-7 since 2026-10-31")
    ap.add_argument("--level-shift", type=float, default=0.3,
                    help="level shift (Ha) of the first stage only — steers the path into the basin; the polish runs "
                         "unshifted, so a second route to the same point is a check")
    args = ap.parse_args()
    xyz_name, out_name, geom_label = GEOMETRIES[args.geometry]
    xyz = LIGANDS_DIR / xyz_name
    out = DFT_CACHE / out_name

    banner(f"FO-DFT coupling — Cu-Co ZIF hop ({geom_label})")
    t0 = time.time()
    if not xyz.exists():
        sys.exit(f"Missing {xyz}. Run script 23 first (the flag that builds it is in its --help).")
    atoms = read_xyz(xyz)

    basis = dict(BASIS_METALS)
    basis["default"] = BASIS_LIGHT
    mol = gto.M(atom=atoms, basis=basis, ecp=dict(ECP_METALS),
                charge=CHARGE, spin=SPIN, unit="Angstrom")
    cu_idx = [i for i, a in enumerate(atoms) if a[0] == "Cu"]
    co_idx = [i for i, a in enumerate(atoms) if a[0] == "Co"]
    print(f"  {len(atoms)} atoms; Cu={cu_idx}, Co={co_idx}; charge={CHARGE} spin={SPIN}")

    crude = crude_cu_co_t_ij()                       # read before the SCF: a missing cache dies in seconds, not hours
    mf, scf = converge(mol, args.conv_tol, args.conv_tol_grad, args.level_shift)
    print(f"  internal stability of the UKS solution: "
          f"{'stable' if scf['stable_internal'] else 'UNSTABLE — a lower solution exists'}")
    print(f"  dimer SCF: E={scf['E_scf_Ha']:.8f} Ha, converged={scf['scf_converged']}, Newton rescue={scf['newton_rescue']}, "
          f"polish {scf['polish_cycles']} cycles to |g|={scf['orbital_grad_norm_Ha']:.1e} Ha, "
          f"<S²>={scf['S2']:.3f} (pure {SPIN / 2 * (SPIN / 2 + 1):.3f})")

    rec = couple(mol, mf, cu_idx, co_idx)
    t_ij, dG_site = rec["t_ij_eV"], rec["site_energy_gap_eV"]
    resolution = scf["orbital_grad_norm_Ha"] * HARTREE_TO_EV / t_ij
    print(f"  frontier window MO[{rec['window'][0]}:{rec['window'][1]}], nocc(α)={rec['nocc_alpha']}; picked "
          + " · ".join(f"HOMO{k:+d}" for k in rec["picked_rel_HOMO"])
          + (" — ⚠️ one pick sits at the window's edge" if rec["pick_at_window_edge"] else ""))
    for k, e, pc, po in zip(rec["picked_MOs"], rec["eps_picked_eV"], rec["pop_cu_picked"], rec["pop_partner_picked"], strict=True):
        print(f"    MO {k}: ε={e:+.3f} eV  pop(Cu)={pc:.2f} pop(Co)={po:.2f}")

    banner("FO-DFT coupling result")
    for k in range(2):
        print(f"  localised orbital {k}: pop(Cu)={rec['loc_pop_cu'][k]:.2f} pop(Co)={rec['loc_pop_partner'][k]:.2f}")
    print(f"  |t_ij| (FO-DFT)  = {t_ij:.6f} eV   (script-24 crude = {crude:.5f} eV, loaded from zif_hopping.json; "
          f"SCF resolution |g|/t_ij = {resolution:.1e})")
    print(f"  site-energy gap  = {dG_site:.4f} eV   (diagonal Fock difference — not a free energy; Cu-site minus Co-site "
          f"{rec['site_energy_cu_minus_partner_eV']:+.4f} eV; mixing angle 2θ = {rec['localisation_2theta_deg']:.2f}°)")
    print(f"  localised onto distinct metals: {rec['localised']} · |t_ij| in 1e-5–1 eV: {1e-5 < t_ij < 1.0}")
    print(f"  → {'✅ physical coupling' if rec['physically_reasonable'] else '⚠️ inspect — non-localised or out-of-band'}"
          " (the check sees neither the window's edge nor ⟨S²⟩ — both are in the record)")

    out.write_text(json.dumps({
        "geometry": args.geometry,
        "geometry_note": geom_label,
        "xyz": xyz_name,
        "method": "FO-DFT-labelled two-state diabatisation (single UKS dimer SCF; the 2 α MOs with the largest Cu + Co "
                  "Mulliken population in the window HOMO−5 … LUMO+3, manual 2×2 population localisation, off-diagonal "
                  "Fock = t_ij); B3LYP/6-31G(d)+LANL2DZ",
        "pair": "Cu-Co (rate-limiting hop)",
        "t_ij_eV": round(t_ij, 6),
        "t_ij_crude_script24_eV": round(crude, 6),
        "crude_is_shipped_geometry_only": args.geometry != "shipped",
        "site_energy_gap_eV": round(dG_site, 4),
        "frontier_MOs": rec["picked_MOs"],
        "localised": rec["localised"],
        "physically_reasonable": rec["physically_reasonable"],
        # the record the flag cannot replace (in-silico §When Modifying #49) — the cluster's charge is the MODEL's,
        # not the physical hop's (+3, paper §2.5), so «physical» here is a verdict about the model
        "charge": CHARGE, "spin_2S": SPIN, "n_electrons": mol.nelectron,
        **scf, "grad_norm_over_t_ij": float(f"{resolution:.2e}"), "S2_pure": SPIN / 2 * (SPIN / 2 + 1),
        **{k: rec[k] for k in ("nocc_alpha", "window", "picked_rel_HOMO", "pick_at_window_edge")},
        "eps_picked_eV": [round(e, 4) for e in rec["eps_picked_eV"]],
        "pop_cu_picked": [round(p, 3) for p in rec["pop_cu_picked"]],
        "pop_co_picked": [round(p, 3) for p in rec["pop_partner_picked"]],
        "loc_pop_cu": [round(p, 3) for p in rec["loc_pop_cu"]],
        "loc_pop_co": [round(p, 3) for p in rec["loc_pop_partner"]],
        "site_energy_cu_minus_co_eV": round(rec["site_energy_cu_minus_partner_eV"], 4),
        "localisation_2theta_deg": round(rec["localisation_2theta_deg"], 2),
        "wall_seconds": round(time.time() - t0, 1),
    }, indent=2))
    banner(f"✅ Saved {out.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
