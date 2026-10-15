#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L3 — Nelsen 4-point reorganization energy λ for the FADH•/FADH⁻ anode couple.

Rescues script 29, which computed λ for FADH₂ → FADH₂•⁺ (radical CATION) — a
species that is pathological in implicit solvent (uncompensated cation radical →
+160 eV cross-terms / non-convergence; see PIPELINE_STATUS, script 29 row).

The physically correct FIRST electron transfer at the anode (pH 7, where the
reduced flavin is the anion FADH⁻) is a clean one-electron oxidation:

    FADH⁻ (anion, singlet)  ⇌  FADH• (neutral semiquinone radical, doublet) + e⁻

Both members are stable, charge-DELOCALISED flavin species (no localised small
ion → C-PCM behaves), and they share the SAME nuclei (the deprotonated
isoalloxazine), so the Nelsen 4-point applies cleanly:

    λ₁ = E(FADH⁻ @ R_rad)   − E(FADH⁻ @ R_anion)     (reduced member, ox geom)
    λ₂ = E(FADH•  @ R_anion) − E(FADH•  @ R_rad)      (ox member, reduced geom)
    λ_inner = λ₁ + λ₂                                  (both > 0)

This is the INNER-sphere λ. The Marcus OUTER-sphere λ_o (nonequilibrium solvent
polarisation) adds on top. The 0.7–0.8 eV it is compared with is the TOTAL (inner +
outer) λ of OTHER protein ET centres (azurin, cyt c/b₅ — ref 48, Gray & Winkler 2005):
no flavin primary, and no rate consumes it. A modest computed λ_i is therefore
expected and consistent (the rigid aromatic isoalloxazine distorts little on 1 e⁻).

The deprotonation site is screened (most-stable N-H removal, the script-33
approach). All at B3LYP/def2-SVP + C-PCM — λ_i is an energy difference of the
SAME electronic state at two geometries, so it is insensitive to functional/basis
(the argument script 29 makes; a composite ωB97X/def2-TZVP only destabilised the
cross-SPs there).
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from pyscf import dft, gto, solvent
from rdkit import Chem
from rdkit.Chem import AllChem

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, REPO_ROOT, SOLVENT_EPS_WATER
from lib.dft_utils import dft_optimize
from lib.flavin import LUMIFLAVIN_RED_SMILES, check_15_dihydro, locants
from lib.utils import banner

LIT_LAMBDA_TOTAL_EV = 0.7        # comparison constant — TOTAL λ of OTHER protein ET centres (ref 48); no flavin primary; consumed by no rate
OUT_JSON = DFT_CACHE / "semiquinone_lambda.json"


def build_fadh2():
    m = Chem.AddHs(Chem.MolFromSmiles(LUMIFLAVIN_RED_SMILES))
    check_15_dihydro(m)   # before any SCF (in-silico §Critical Rules #16; 2026-10-15 the 4a,5 tautomer stood here)
    AllChem.EmbedMolecule(m, randomSeed=42)
    AllChem.MMFFOptimizeMolecule(m, maxIters=2000, mmffVariant="MMFF94s")
    return m


def atoms_from_rdkit(m):
    conf = m.GetConformer()
    return [(m.GetAtomWithIdx(i).GetSymbol(),
             (conf.GetAtomPosition(i).x, conf.GetAtomPosition(i).y, conf.GetAtomPosition(i).z))
            for i in range(m.GetNumAtoms())]


def nh_hydrogens(m):
    """(H_idx, N_idx) for every H bonded to a nitrogen — candidate deprotonation sites."""
    out = []
    for a in m.GetAtoms():
        if a.GetSymbol() == "H":
            nb = a.GetNeighbors()
            if nb and nb[0].GetSymbol() == "N":
                out.append((a.GetIdx(), nb[0].GetIdx()))
    return out


def pyscf_mol(atoms, charge, spin, basis="def2-svp"):
    mol = gto.Mole()
    mol.atom = [(s, xyz) for s, xyz in atoms]
    mol.basis = basis
    mol.charge = charge
    mol.spin = spin
    mol.verbose = 0
    mol.build()
    return mol


def run_sp(mol, xc="b3lyp", level_shift=0.0, dm0=None):
    """PCM single-point; optional dm0 seed for the Nelsen cross-terms (prevents
    collapse to a wrong state at the distorted geometry). SOSCF (Newton) fallback
    for any residual DIIS stalling — cached/converged results unaffected."""
    mf = dft.RKS(mol) if mol.spin == 0 else dft.UKS(mol)
    mf.xc = xc
    mf = solvent.PCM(mf)
    mf.with_solvent.eps = SOLVENT_EPS_WATER
    mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 300
    mf.verbose = 0
    if level_shift > 0:
        mf.level_shift = level_shift
    e = mf.kernel(dm0=dm0)
    if not mf.converged:
        mf = mf.newton()
        mf.max_cycle = 100
        e = mf.kernel(dm0=mf.make_rdm1() if dm0 is None else dm0)
    return mf, float(e)


def run_opt(atoms, charge, spin, label, level_shift=0.0):
    """Geom-opt at B3LYP/def2-SVP+PCM through `dft_optimize` (grid response; its convergence flag is geomeTRIC's own —
    the `geometric_solver.optimize` it replaced drops that flag) → (atoms, summary)."""
    out, info = dft_optimize(atoms, charge, spin, label=label, maxsteps=100, xc="b3lyp", basis_light="def2-svp",
                             level_shift_open=level_shift, conv_tol=1e-8, max_cycle=300)
    last = info["trajectory"][-1] if info["trajectory"] else {}
    summary = {k: info[k] for k in ("converged", "steps", "returned", "error", "wall_seconds", "maxsteps")}
    summary["final_grad_max_Ha_bohr"] = last.get("grad_max_Ha_bohr")
    return [(s, tuple(float(x) for x in c)) for s, c in out], summary


def main() -> int:
    banner("Nelsen 4-point λ — FADH•/FADH⁻ anode couple (rescues script 29)")
    t_total = time.time()

    fadh2 = build_fadh2()
    atoms_red = atoms_from_rdkit(fadh2)
    nh = nh_hydrogens(fadh2)
    loc = locants(fadh2)
    print(f"  FADH₂: {len(atoms_red)} atoms; candidate N-H sites: {[loc[n] for _, n in nh]}")

    # --- screen the deprotonation site → most stable neutral semiquinone FADH• ---
    banner("Screen semiquinone site (B3LYP/6-31g(d)+PCM, UKS doublet)")
    best = None
    for h_idx, n_idx in nh:
        rad_atoms = [a for i, a in enumerate(atoms_red) if i != h_idx]
        mf_s, e = run_sp(pyscf_mol(rad_atoms, 0, 1, basis="6-31g(d)"), "b3lyp", level_shift=0.2)
        print(f"    remove H@{loc[n_idx]}: E = {e:.6f} Ha  conv={mf_s.converged}")
        if mf_s.converged and (best is None or e < best[1]):   # an unconverged site never wins the screen
            best = (h_idx, e, n_idx, rad_atoms)
    if best is None:
        sys.exit("No converged semiquinone radical")
    h_idx, _, n_idx, rad_atoms = best
    site = loc[n_idx]
    print(f"  → most stable semiquinone: H removed from {site} ({len(rad_atoms)} atoms)" + ("" if site == "N1" else
          "  ⚠️ NOT N1: FADH⁻ is the N1-deprotonated anion and FADH• carries H on N5 — read before integrating"))
    # rad_atoms = the shared 'FADH' nuclei for BOTH couple members (same nuclei →
    # Nelsen applies). FADH• = (0, doublet); FADH⁻ = (−1, singlet).

    # --- geom-opt both members at their own charge/spin (B3LYP/def2-SVP+PCM) ---
    banner("Step 1: geom-opt FADH• (neutral doublet) at B3LYP/def2-SVP")
    t = time.time()
    R_rad, opt_rad = run_opt(rad_atoms, 0, 1, "FADH_radical", level_shift=0.2)
    print(f"  FADH• opt done ({time.time()-t:.0f}s) conv={opt_rad['converged']} steps={opt_rad['steps']}")

    banner("Step 2: geom-opt FADH⁻ (anion singlet) at B3LYP/def2-SVP")
    t = time.time()
    R_anion, opt_an = run_opt(rad_atoms, -1, 0, "FADH_anion")
    print(f"  FADH⁻ opt done ({time.time()-t:.0f}s) conv={opt_an['converged']} steps={opt_an['steps']}")
    if not (opt_rad["converged"] and opt_an["converged"]):
        side = OUT_JSON.with_suffix(".unconverged.json")
        side.write_text(json.dumps({"semiquinone_site": site, "geom_opt": {"FADH_radical": opt_rad, "FADH_anion": opt_an}},
                                   indent=2), encoding="utf-8")
        banner(f"⛔ geometry optimisation not converged — {side.name} written, {OUT_JSON.name} untouched")
        return 1

    # --- diagonal SPs (each member at its own optimized geometry) ---
    banner("Step 3: diagonal SPs")
    mf_rad_d, E_rad_at_Rrad = run_sp(pyscf_mol(R_rad, 0, 1), "b3lyp", level_shift=0.2)
    dm_rad = mf_rad_d.make_rdm1()
    print(f"  E(FADH• @ R_rad)    = {E_rad_at_Rrad:.6f} Ha")
    mf_an_d, E_an_at_Ran = run_sp(pyscf_mol(R_anion, -1, 0), "b3lyp")
    dm_an = mf_an_d.make_rdm1()
    print(f"  E(FADH⁻ @ R_anion)  = {E_an_at_Ran:.6f} Ha")

    # --- cross SPs (seed each from the same-charge/spin diagonal density) ---
    banner("Step 4: cross SPs (seeded)")
    _, E_rad_at_Ran = run_sp(pyscf_mol(R_anion, 0, 1), "b3lyp", level_shift=0.2, dm0=dm_rad)
    print(f"  E(FADH• @ R_anion)  = {E_rad_at_Ran:.6f} Ha")
    _, E_an_at_Rrad = run_sp(pyscf_mol(R_rad, -1, 0), "b3lyp", dm0=dm_an)
    print(f"  E(FADH⁻ @ R_rad)    = {E_an_at_Rrad:.6f} Ha")

    # --- Nelsen 4-point ---
    banner("λ_inner (Nelsen 4-point, FADH•/FADH⁻)")
    lambda_1 = E_an_at_Rrad - E_an_at_Ran        # reduced member (FADH⁻) distorted to ox geom
    lambda_2 = E_rad_at_Ran - E_rad_at_Rrad      # ox member (FADH•) distorted to reduced geom
    lam_eV = (lambda_1 + lambda_2) * HARTREE_TO_EV
    print(f"  λ₁ = E(FADH⁻@R_rad) − E(FADH⁻@R_anion) = {lambda_1*HARTREE_TO_EV:+.4f} eV")
    print(f"  λ₂ = E(FADH•@R_anion) − E(FADH•@R_rad) = {lambda_2*HARTREE_TO_EV:+.4f} eV")
    print(f"  λ_inner = λ₁ + λ₂                       = {lam_eV:.4f} eV")
    print(f"  Comparison λ_total, other protein ET centres (ref 48): {LIT_LAMBDA_TOTAL_EV:.2f} eV")
    physical = 0.05 < lam_eV < 1.5
    print(f"  Physically reasonable inner-sphere (0.05–1.5 eV): "
          f"{'✅ YES' if physical else '❌ NO — likely SCF artifact'}")

    result = {
        "method": "Nelsen 4-point at B3LYP/def2-SVP + C-PCM, FADH•/FADH⁻ couple "
                  "(seeded cross-SPs); rescues script 29 (FADH₂•⁺ radical-cation pathology)",
        "couple": "FADH•(neutral,doublet) / FADH⁻(anion,singlet)",
        "semiquinone_site": site,
        "semiquinone_site_note": "locant from topology (lib/flavin.locants); H removed from that nitrogen of FADH₂",
        "fadh2_tautomer": {"name": "1,5-dihydrolumiflavin", "smiles": LUMIFLAVIN_RED_SMILES},
        "geom_opt": {"optimizer": "lib/dft_utils.dft_optimize (grid response, conv_tol 1e-8)",
                     "FADH_radical": opt_rad, "FADH_anion": opt_an},
        "physically_reasonable": bool(physical),
        "E_rad_at_Rrad_Ha": E_rad_at_Rrad,
        "E_an_at_Ran_Ha": E_an_at_Ran,
        "E_rad_at_Ran_Ha": E_rad_at_Ran,
        "E_an_at_Rrad_Ha": E_an_at_Rrad,
        "lambda_1_eV": float(lambda_1 * HARTREE_TO_EV),
        "lambda_2_eV": float(lambda_2 * HARTREE_TO_EV),
        "lambda_inner_eV": float(lam_eV),
        "literature_lambda_total_eV": LIT_LAMBDA_TOTAL_EV,
        "lambda_total_comparison_basis": "TOTAL λ of OTHER protein ET centres (azurin, cyt c/b5; ref 48); "
                                         "no flavin primary; consumed by no rate",
        "note": "inner-sphere only; Marcus outer-sphere λ_o adds on top → total comparable to the "
                "0.7–0.8 eV range of other protein ET centres (ref 48); no anode rate consumes it",
        "wall_seconds": time.time() - t_total,
    }
    DFT_CACHE.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(result, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
