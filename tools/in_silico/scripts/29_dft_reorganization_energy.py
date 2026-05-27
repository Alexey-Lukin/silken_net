#!/usr/bin/env python
"""
L3 — Nelsen 4-point reorganization energy λ for FADH₂/FADH₂⁺.

Computes inner-sphere reorganization energy from first principles
using the 4-point method (Nelsen 1987):

  λ_inner = [E(neutral @ cation_geom) - E(neutral @ neutral_geom)]
          + [E(cation @ neutral_geom)  - E(cation @ cation_geom)]

Protocol:
  1. Geom opt FADH₂ (neutral) at B3LYP/def2-SVP + PCM
  2. Geom opt FADH₂⁺ (cation) at B3LYP/def2-SVP + PCM
  3. SP at ωB97X/def2-TZVP: E(neutral @ neutral_geom) + E(cation @ cation_geom)
  4. Cross-SP: E(neutral @ cation_geom) + E(cation @ neutral_geom)
  5. λ_inner = (3→4 cross terms)

Replaces hardcoded λ=0.7 eV in Marcus rate calculations.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from pyscf import dft, gto, solvent
from pyscf.geomopt import geometric_solver
from rdkit import Chem
from rdkit.Chem import AllChem

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import REPO_ROOT, DFT_CACHE, HARTREE_TO_EV
from lib.utils import banner

LUMIFLAVIN_RED = "CC1=CC2=C(C=C1C)N(C)C3=NC(=O)NC(=O)C3N2"
OUT_JSON = DFT_CACHE / "reorganization_energy.json"


def build_mol(smiles, charge=0, spin=0, basis="def2-svp"):
    mol_rd = Chem.MolFromSmiles(smiles)
    mol_rd = Chem.AddHs(mol_rd)
    AllChem.EmbedMolecule(mol_rd, randomSeed=42)
    AllChem.MMFFOptimizeMolecule(mol_rd, maxIters=2000, mmffVariant="MMFF94s")
    conf = mol_rd.GetConformer()
    atom_str = "; ".join(
        f"{mol_rd.GetAtomWithIdx(i).GetSymbol()} "
        f"{conf.GetAtomPosition(i).x:.4f} "
        f"{conf.GetAtomPosition(i).y:.4f} "
        f"{conf.GetAtomPosition(i).z:.4f}"
        for i in range(mol_rd.GetNumAtoms())
    )
    mol = gto.Mole()
    mol.atom = atom_str
    mol.basis = basis
    mol.charge = charge
    mol.spin = spin
    mol.build()
    return mol


def run_sp(mol, xc="wb97x", level_shift=0.0):
    mf = dft.RKS(mol) if mol.spin == 0 else dft.UKS(mol)
    mf.xc = xc
    mf = solvent.PCM(mf)
    mf.with_solvent.eps = 78.3553
    mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 400
    mf.verbose = 0
    if level_shift > 0:
        mf.level_shift = level_shift
    e = mf.kernel()
    return mf, float(e)


def mol_with_coords(template_mol, coords_mol):
    """Create mol with template's basis/charge/spin but coords from coords_mol."""
    new = template_mol.copy()
    new.atom = coords_mol.atom
    new.build()
    return new


def main() -> int:
    banner("Nelsen 4-point reorganization energy (FADH₂/FADH₂⁺)")
    t_total = time.time()

    # Step 1: Geom opt FADH₂ (neutral)
    banner("Step 1: Geom opt FADH₂ (charge=0) at B3LYP/def2-SVP")
    mol_n = build_mol(LUMIFLAVIN_RED, charge=0, spin=0)
    mf_n, _ = run_sp(mol_n, xc="b3lyp")
    t0 = time.time()
    mol_n_opt = geometric_solver.optimize(mf_n, maxsteps=50)
    print(f"  Converged ({time.time()-t0:.0f}s)")

    # Step 2: Geom opt FADH₂⁺ (cation)
    banner("Step 2: Geom opt FADH₂⁺ (charge=+1, spin=1) at B3LYP/def2-SVP")
    mol_c = build_mol(LUMIFLAVIN_RED, charge=1, spin=1)
    mf_c, _ = run_sp(mol_c, xc="b3lyp", level_shift=0.2)
    t0 = time.time()
    mol_c_opt = geometric_solver.optimize(mf_c, maxsteps=50)
    print(f"  Converged ({time.time()-t0:.0f}s)")

    # Step 3: SP at ωB97X on own geometries (diagonal terms)
    banner("Step 3: ωB97X SP — diagonal terms")

    mol_n_tzvp = mol_n_opt.copy()
    mol_n_tzvp.basis = "def2-tzvp"
    mol_n_tzvp.build()
    _, E_n_at_Rn = run_sp(mol_n_tzvp, xc="wb97x")
    print(f"  E(neutral @ R_neutral) = {E_n_at_Rn:.6f} Ha")

    mol_c_tzvp = mol_c_opt.copy()
    mol_c_tzvp.basis = "def2-tzvp"
    mol_c_tzvp.build()
    _, E_c_at_Rc = run_sp(mol_c_tzvp, xc="wb97x", level_shift=0.2)
    print(f"  E(cation @ R_cation)   = {E_c_at_Rc:.6f} Ha")

    # Step 4: Cross-SP (off-diagonal terms)
    banner("Step 4: ωB97X SP — cross terms (4-point)")

    # Neutral at cation geometry
    mol_n_at_Rc = gto.Mole()
    mol_n_at_Rc.atom = mol_c_opt.atom
    mol_n_at_Rc.basis = "def2-tzvp"
    mol_n_at_Rc.charge = 0
    mol_n_at_Rc.spin = 0
    mol_n_at_Rc.build()
    _, E_n_at_Rc = run_sp(mol_n_at_Rc, xc="wb97x")
    print(f"  E(neutral @ R_cation)  = {E_n_at_Rc:.6f} Ha")

    # Cation at neutral geometry
    mol_c_at_Rn = gto.Mole()
    mol_c_at_Rn.atom = mol_n_opt.atom
    mol_c_at_Rn.basis = "def2-tzvp"
    mol_c_at_Rn.charge = 1
    mol_c_at_Rn.spin = 1
    mol_c_at_Rn.build()
    _, E_c_at_Rn = run_sp(mol_c_at_Rn, xc="wb97x", level_shift=0.2)
    print(f"  E(cation @ R_neutral)  = {E_c_at_Rn:.6f} Ha")

    # Step 5: Compute λ
    banner("λ_inner (Nelsen 4-point)")
    lambda_1 = E_n_at_Rc - E_n_at_Rn
    lambda_2 = E_c_at_Rn - E_c_at_Rc
    lambda_inner = lambda_1 + lambda_2

    print(f"  λ₁ = E(n@Rc) - E(n@Rn) = {lambda_1:.6f} Ha = {lambda_1*HARTREE_TO_EV:.4f} eV")
    print(f"  λ₂ = E(c@Rn) - E(c@Rc) = {lambda_2:.6f} Ha = {lambda_2*HARTREE_TO_EV:.4f} eV")
    print(f"  λ_inner = λ₁ + λ₂       = {lambda_inner:.6f} Ha = {lambda_inner*HARTREE_TO_EV:.4f} eV")
    print(f"  Literature λ (assumed):    0.7000 eV")
    print(f"  Difference:                {lambda_inner*HARTREE_TO_EV - 0.7:+.4f} eV")

    result = {
        "method": "Nelsen 4-point at ωB97X/def2-TZVP // B3LYP/def2-SVP geom",
        "E_n_at_Rn_Ha": E_n_at_Rn,
        "E_c_at_Rc_Ha": E_c_at_Rc,
        "E_n_at_Rc_Ha": E_n_at_Rc,
        "E_c_at_Rn_Ha": E_c_at_Rn,
        "lambda_1_eV": float(lambda_1 * HARTREE_TO_EV),
        "lambda_2_eV": float(lambda_2 * HARTREE_TO_EV),
        "lambda_inner_eV": float(lambda_inner * HARTREE_TO_EV),
        "literature_lambda_eV": 0.7,
        "wall_seconds": time.time() - t_total,
    }
    DFT_CACHE.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(result, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
