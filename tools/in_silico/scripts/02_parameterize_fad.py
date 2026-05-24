#!/usr/bin/env python
"""
L2 step 2a — parameterize FAD cofactor for GAFF (General Amber Force Field).

Why this script exists
----------------------
The 01 smoke test stripped FAD out of the topology because `amber14-all.xml`
has no template for "FAD" residue — AMBER ships templates for the 20 standard
amino acids only. For real L2 stability MD (script 10) we need FAD bound in
the active site, with proper bonds, angles, torsions, and partial charges.

What this script does
---------------------
1. Loads FAD coordinates from the AF3 output (AF3 placed FAD in its bound
   pose inside GcGDH's active site).
2. Loads the canonical CCD SMILES for FAD (correct bond orders, including
   aromatic rings, phosphodiester linkages, and stereo centers).
3. Uses RDKit to project the SMILES bond orders onto the PDB-derived FAD —
   merges the AF3 pose with the correct chemistry.
4. Hands the resulting molecule to `openmmforcefields.GAFFTemplateGenerator`,
   which spawns `antechamber` + `parmchk2` under the hood to compute AM1-BCC
   partial charges and GAFF atom types. Result is cached as JSON for reuse
   by script 10.
5. Writes `FAD.sdf` (chemistry-aware, with AF3 coordinates) as the canonical
   ligand artifact.

Cost
----
First run takes ≈ 5–15 minutes (antechamber's AM1 SCF on ~84 atoms). Subsequent
runs hit the cache and finish in seconds.

Run
---
    conda activate silken_md
    python tools/in_silico/scripts/02_parameterize_fad.py
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

from openff.toolkit import Molecule
from openmm.app import ForceField, PDBFile
from openmmforcefields.generators import GAFFTemplateGenerator
from rdkit import Chem
from rdkit.Chem import AllChem

REPO_ROOT = Path(__file__).resolve().parents[3]
AF3_PDB = REPO_ROOT / "docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb"
LIGANDS_DIR = REPO_ROOT / "docs/protocols/ebfc/in_silico/ligands"
CACHE_DIR = REPO_ROOT / "tools/in_silico/cache"
LIGANDS_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

# Canonical FAD SMILES from AF3 job's CCD entry (chemical formula C27H33N9O15P2).
# Source: docs/protocols/ebfc/in_silico/alphafold3/fold_dgrgcgdh_fad_v1_model_0.cif
# (chem_comp.pdbx_smiles for residue FAD).
FAD_SMILES = (
    "Cc1cc2N=C3C(=O)NC(=O)N=C3N(C[C@H](O)[C@H](O)[C@H](O)CO[P@](O)(=O)"
    "O[P@@](O)(=O)OC[C@H]4O[C@H]([C@H](O)[C@@H]4O)n5cnc6c(N)ncnc56)c2cc1C"
)

GAFF_VERSION = "gaff-2.11"
OUT_SDF = LIGANDS_DIR / "FAD.sdf"
CACHE_FILE = CACHE_DIR / "gaff_cache.json"


def banner(msg: str) -> None:
    print(f"\n[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def extract_fad_pdb_block(pdb_path: Path) -> str:
    """Pull only FAD HETATM lines (plus END) from a multi-chain PDB."""
    keep_lines = []
    with pdb_path.open() as fh:
        for line in fh:
            if line.startswith(("HETATM", "CONECT")) and " FAD " in line:
                keep_lines.append(line)
            elif line.startswith("HETATM") and line[17:20].strip() == "FAD":
                keep_lines.append(line)
    if not keep_lines:
        raise SystemExit(f"No FAD HETATM records found in {pdb_path}")
    keep_lines.append("END\n")
    return "".join(keep_lines)


def main() -> int:
    if not AF3_PDB.exists():
        sys.exit(f"Missing AF3 PDB: {AF3_PDB}")

    banner("Extracting FAD coordinates from AF3 output")
    fad_pdb_block = extract_fad_pdb_block(AF3_PDB)
    print(f"  Extracted {fad_pdb_block.count(chr(10)) - 1} HETATM/CONECT lines")

    # --- 1. RDKit: read FAD with AF3 coordinates (no bond orders yet) ---
    pdb_mol = Chem.MolFromPDBBlock(fad_pdb_block, removeHs=False, sanitize=False)
    if pdb_mol is None:
        sys.exit("RDKit failed to parse FAD PDB block")
    print(f"  PDB-derived RDKit mol: {pdb_mol.GetNumAtoms()} atoms (no bond orders)")

    # --- 2. RDKit: build chemistry-aware reference from SMILES ---
    ref_mol = Chem.MolFromSmiles(FAD_SMILES)
    if ref_mol is None:
        sys.exit("RDKit failed to parse FAD SMILES")
    ref_mol = AllChem.AddHs(ref_mol)
    print(f"  SMILES reference  : {ref_mol.GetNumAtoms()} atoms ({Chem.MolToSmiles(Chem.RemoveHs(ref_mol))[:60]}...)")

    # --- 3. Project bond orders from reference onto PDB-derived mol ---
    # AF3 PDB has no hydrogens on the ligand → strip Hs from reference for matching,
    # then re-add Hs after to get a chemistry-complete molecule.
    ref_no_h = Chem.RemoveHs(ref_mol)
    banner("Transferring bond orders from SMILES → PDB coordinates")
    try:
        fad_mol = AllChem.AssignBondOrdersFromTemplate(ref_no_h, pdb_mol)
    except ValueError as e:
        sys.exit(f"Bond-order transfer failed (atom mismatch): {e}")
    fad_mol = Chem.AddHs(fad_mol, addCoords=True)
    print(f"  Final RDKit mol   : {fad_mol.GetNumAtoms()} atoms (bonds + AF3 heavy-atom coords + auto Hs)")

    # --- 4. Convert to OpenFF Molecule ---
    banner("Building OpenFF Molecule")
    off_mol = Molecule.from_rdkit(fad_mol, allow_undefined_stereo=True)
    off_mol.name = "FAD"
    print(f"  OpenFF mol total charge: {off_mol.total_charge}")
    print(f"  Atoms: {off_mol.n_atoms} | bonds: {off_mol.n_bonds}")

    # --- 5. Save as SDF (canonical chemistry-aware ligand artifact) ---
    off_mol.to_file(str(OUT_SDF), file_format="sdf")
    print(f"  Wrote {OUT_SDF.relative_to(REPO_ROOT)}")

    # --- 6. Trigger GAFF parameter generation + cache ---
    banner(f"Generating GAFF {GAFF_VERSION} parameters (antechamber + AM1-BCC; this is the slow step)")
    print(f"  Cache: {CACHE_FILE.relative_to(REPO_ROOT)}")
    t = time.time()
    gaff = GAFFTemplateGenerator(
        molecules=[off_mol],
        forcefield=GAFF_VERSION,
        cache=str(CACHE_FILE),
    )

    # Build a minimal ForceField that uses GAFF for FAD only — this triggers
    # the generator on first system creation.
    forcefield = ForceField()
    forcefield.registerTemplateGenerator(gaff.generator)
    mm_top = off_mol.to_topology().to_openmm()
    system = forcefield.createSystem(mm_top)
    dt = time.time() - t
    print(
        f"  ✓ System built: {system.getNumParticles()} particles, "
        f"{system.getNumConstraints()} constraints, "
        f"{system.getNumForces()} force terms"
    )
    print(f"  Parameterization wall-clock: {dt:.1f}s")
    print(f"  Cache file size: {CACHE_FILE.stat().st_size / 1024:.1f} KB")

    banner("✅ FAD parameterized — GAFF params cached, FAD.sdf ready for script 10")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
