#!/usr/bin/env python
"""
L3 step 1 — frontier orbitals of the FAD redox core (lumiflavin).

Why lumiflavin and not the full FAD
-----------------------------------
The whole FAD molecule has ~84 atoms, but the redox-active chemistry lives
entirely in the isoalloxazine ring (the flavin head). The ribitol + ADP tail
is electronically isolated by a saturated CH2 spacer at N10. Lumiflavin =
7,8,10-trimethylisoalloxazine is the canonical truncation: keeps the full
π-system + N10 methyl (mimicking the ribitol attachment) and drops the
~50 atoms of phosphates + adenine that just add SCF noise. This is the
standard reduction used in flavin DFT literature (e.g. Hall, Hopper, Bash
2000; Bhattacharyya, Stankovich, Truhlar 2007).

What this script does
---------------------
For each redox form (oxidized FAD and 2e-/2H+-reduced FADH₂):
  1. Build the structure via RDKit (SMILES → 3D conformer → MMFF94s opt).
  2. Single-point DFT at B3LYP/6-31G(d) in PCM water (ε = 78.3553).
  3. Report HOMO / LUMO energies and total electronic energy.

Then estimate the apparent redox potential vs. NHE from the ΔE between
oxidized and reduced forms — a sanity check against the experimental
+60 mV value cited in `docs/01_03 §2.1`.

Why B3LYP/6-31G(d) and not ωB97X-D/def2-TZVP
--------------------------------------------
B3LYP is the workhorse hybrid functional that has been benchmarked on
flavin redox chemistry for two decades and gives quantitatively sensible
HOMO/LUMO ordering at ~1/2 the cost of a range-separated functional. For a
publication-grade rerun, swap `XC_FUNCTIONAL` to `wb97x-d` and `BASIS_LIGHT`
to `def2-tzvp` — the rest of the script stays as-is. Documented as future
work in `docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md`.

Outputs
-------
  * `docs/protocols/ebfc/in_silico/ligands/lumiflavin_ox.xyz`     — MMFF geom
  * `docs/protocols/ebfc/in_silico/ligands/lumiflavin_red.xyz`    — MMFF geom
  * `tools/in_silico/cache/dft/lumiflavin.json`                   — energies

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/20_dft_lumiflavin.py
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np
from pyscf import dft, gto, solvent
from rdkit import Chem
from rdkit.Chem import AllChem

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import REPO_ROOT, LIGANDS_DIR, DFT_CACHE, KINETICS_DIR, HARTREE_TO_EV



# Lumiflavin (7,8,10-trimethylisoalloxazine), neutral oxidized form.
# PubChem CID 1549108. The N1 and N5 positions are sp2 and unprotonated.
LUMIFLAVIN_OX_SMILES = "Cc1cc2nc3c(=O)[nH]c(=O)nc3n(C)c2cc1C"

# 1,5-dihydrolumiflavin — the accepted reduced (FADH₂-like) form. N1 and N5
# are now sp3 with explicit H; the ring buckles (non-planar) and RDKit's
# MMFF94s embed produces the expected envelope conformation.
LUMIFLAVIN_RED_SMILES = "CC1=CC2=C(C=C1C)N(C)C3=NC(=O)NC(=O)C3N2"

XC_FUNCTIONAL = "b3lyp"
BASIS_LIGHT = "6-31g(d)"      # for organic ligands; bump to def2-tzvp for publication
SOLVENT_EPS_WATER = 78.3553   # xylem ≈ water
MMFF_ITER = 2000


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def build_mol_from_smiles(smiles: str, name: str) -> Chem.Mol:
    """SMILES → 3D RDKit Mol with MMFF94s preoptimization."""
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        sys.exit(f"RDKit failed to parse SMILES: {smiles}")
    mol = Chem.AddHs(mol)
    embedded = AllChem.EmbedMolecule(mol, randomSeed=42, useRandomCoords=False)
    if embedded != 0:
        sys.exit(f"Embed failed for {name}")
    AllChem.MMFFOptimizeMolecule(mol, maxIters=MMFF_ITER, mmffVariant="MMFF94s")
    return mol


def mol_to_pyscf_atoms(mol: Chem.Mol) -> list[tuple[str, tuple[float, float, float]]]:
    """RDKit Mol → list of (element, (x, y, z)) for PySCF."""
    conf = mol.GetConformer()
    out: list[tuple[str, tuple[float, float, float]]] = []
    for i, atom in enumerate(mol.GetAtoms()):
        p = conf.GetAtomPosition(i)
        out.append((atom.GetSymbol(), (p.x, p.y, p.z)))
    return out


def write_xyz(atoms, path: Path, comment: str) -> None:
    with path.open("w", encoding="utf-8") as fh:
        fh.write(f"{len(atoms)}\n{comment}\n")
        for sym, (x, y, z) in atoms:
            fh.write(f"{sym:2s}  {x: 12.6f}  {y: 12.6f}  {z: 12.6f}\n")


def dft_singlepoint(atoms, charge: int, spin: int, label: str, with_pcm: bool = True) -> dict:
    """B3LYP/6-31G(d) single-point with optional implicit-water PCM."""
    banner(f"DFT SP: {label} (charge={charge}, spin={spin}, PCM={'yes' if with_pcm else 'no'})")
    mol = gto.M(atom=atoms, basis=BASIS_LIGHT, charge=charge, spin=spin, unit="Angstrom")
    mf = dft.RKS(mol) if spin == 0 else dft.UKS(mol)
    mf.xc = XC_FUNCTIONAL
    if with_pcm:
        mf = solvent.PCM(mf)
        mf.with_solvent.eps = SOLVENT_EPS_WATER
        mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-7
    mf.max_cycle = 200
    t = time.time()
    energy_total = mf.kernel()
    dt = time.time() - t

    # Frontier orbitals
    if spin == 0:
        nocc = mol.nelectron // 2
        homo = mf.mo_energy[nocc - 1]
        lumo = mf.mo_energy[nocc]
    else:
        # Pick HOMO/LUMO from the higher-energy of α/β
        nocc_a, nocc_b = mol.nelec
        ho_a = mf.mo_energy[0][nocc_a - 1] if nocc_a > 0 else -np.inf
        ho_b = mf.mo_energy[1][nocc_b - 1] if nocc_b > 0 else -np.inf
        homo = max(ho_a, ho_b)
        lu_a = mf.mo_energy[0][nocc_a] if nocc_a < len(mf.mo_energy[0]) else np.inf
        lu_b = mf.mo_energy[1][nocc_b] if nocc_b < len(mf.mo_energy[1]) else np.inf
        lumo = min(lu_a, lu_b)

    print(f"  E_total = {energy_total:.6f} Ha  ({dt:.1f}s, converged={mf.converged})")
    print(f"  HOMO    = {homo:.6f} Ha = {homo * HARTREE_TO_EV:.3f} eV")
    print(f"  LUMO    = {lumo:.6f} Ha = {lumo * HARTREE_TO_EV:.3f} eV")
    print(f"  GAP     = {(lumo - homo) * HARTREE_TO_EV:.3f} eV")
    return {
        "label": label,
        "charge": charge,
        "spin": spin,
        "n_atoms": mol.natm,
        "n_electrons": mol.nelectron,
        "converged": bool(mf.converged),
        "wall_seconds": dt,
        "E_total_Ha": float(energy_total),
        "HOMO_Ha": float(homo),
        "LUMO_Ha": float(lumo),
        "HOMO_eV": float(homo * HARTREE_TO_EV),
        "LUMO_eV": float(lumo * HARTREE_TO_EV),
        "gap_eV": float((lumo - homo) * HARTREE_TO_EV),
    }


def main() -> int:
    banner("Building lumiflavin oxidized (FAD-like, closed shell, S=0)")
    ox_mol = build_mol_from_smiles(LUMIFLAVIN_OX_SMILES, "ox")
    ox_atoms = mol_to_pyscf_atoms(ox_mol)
    write_xyz(ox_atoms, LIGANDS_DIR / "lumiflavin_ox.xyz", "lumiflavin oxidized — MMFF94s")
    print(f"  Atoms: {len(ox_atoms)}")

    banner("Building lumiflavin reduced (1,5-dihydro, FADH₂-like, closed shell, S=0)")
    red_mol = build_mol_from_smiles(LUMIFLAVIN_RED_SMILES, "red")
    red_atoms = mol_to_pyscf_atoms(red_mol)
    write_xyz(red_atoms, LIGANDS_DIR / "lumiflavin_red.xyz", "1,5-dihydrolumiflavin — MMFF94s")
    print(f"  Atoms: {len(red_atoms)}")

    results = {
        "method": f"{XC_FUNCTIONAL.upper()}/{BASIS_LIGHT}+PCM(water,C-PCM)",
        "ox":  dft_singlepoint(ox_atoms,  charge=0, spin=0, label="lumiflavin_ox"),
        "red": dft_singlepoint(red_atoms, charge=0, spin=0, label="lumiflavin_red"),
    }

    # Apparent reduction free energy (very rough — no ZPE, no thermal, no 2H+
    # correction; for the publication-grade we'd compute ΔG_red properly via
    # frequencies + the standard hydrogen reference electrode). Useful here
    # only as a sanity-check sign on the redox direction.
    de_red = (results["red"]["E_total_Ha"] - results["ox"]["E_total_Ha"]) * HARTREE_TO_EV
    print(f"\n  ΔE(FAD → FADH₂)  ≈ {de_red:.3f} eV  (electronic only; no ZPE/thermal/H+)")

    out_path = DFT_CACHE / "lumiflavin.json"
    with out_path.open("w", encoding="utf-8") as fh:
        json.dump(results, fh, indent=2)
    banner(f"✅ Saved {out_path.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
