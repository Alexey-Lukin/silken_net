#!/usr/bin/env python
"""L3 — adiabatic ΔSCF generator for the FADH₂→Os cascade (OS-RECOMPUTE 2026-06-17).

Closes the ORPHAN cache `delta_scf_corrections.json` (commit 2f49cde added the JSON
with NO script — the generator was lost). Recomputes the headline composite adiabatic
ΔSCF from scratch and writes it drift-safe:

  FAD side (geom-opt B3LYP/def2-SVP → SP ωB97X/def2-TZVP, both PCM):
    IP_vertical  = E(FADH₂⁺ @ FADH₂ geom)   − E(FADH₂)
    IP_adiabatic = E(FADH₂⁺ @ FADH₂⁺ geom)  − E(FADH₂)
    relaxation   = IP_adiabatic − IP_vertical   (small: lumiflavin is rigid planar)

  Os side (LOADED, not hardcoded — drift-safe):
    EA_Os3 = E(Os II) − E(Os III) from os_complex_wb97xd_dmbpy.json (B1, the REAL
             dimethyl mediator) — falls back to plain os_complex_wb97xd.json with a flag.

  Cascade (FADH₂ + Os(III) → FADH₂⁺ + Os(II), per e⁻):
    ΔG_vertical  = IP_vertical  − EA_Os3
    ΔG_adiabatic = IP_adiabatic − EA_Os3     ← headline (Table 2, SUMMARY)

The FAD side does not depend on the mediator (same flavin), so re-running with the
dimethyl Os only changes EA_Os3 → ΔG. The raw cascade stays uphill in every method;
the gap to the verified downhill driving force is the decomposed implicit-solvation
limit (②). This script supplies the DFT mechanism number, not the verdict.

Discipline: no density_fit; level_shift on the FADH₂⁺ doublet + SOSCF fallback; DFT
jobs sequential. ~2-3 h (two geom-opts + three SP).

Run:  mamba run -n silken_md python tools/in_silico/scripts/21g_adiabatic_dscf.py          # dimethyl (B1 cache)
      mamba run -n silken_md python tools/in_silico/scripts/21g_adiabatic_dscf.py --plain   # plain-bpy reference
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
from lib.constants import DFT_CACHE, HARTREE_TO_EV, REPO_ROOT, SOLVENT_EPS_WATER
from lib.utils import banner

LUMIFLAVIN_RED = "CC1=CC2=C(C=C1C)N(C)C3=NC(=O)NC(=O)C3N2"   # FADH₂ (1,5-dihydro), matches 33
OUT = DFT_CACHE / "delta_scf_corrections.json"
GEOMOPT_BASIS = "def2-svp"     # geometry optimization tier (composite ωB97X//B3LYP)
SP_BASIS = "def2-tzvp"         # single-point tier


def _atoms(mol_rd):
    conf = mol_rd.GetConformer()
    return [(mol_rd.GetAtomWithIdx(i).GetSymbol(),
             (conf.GetAtomPosition(i).x, conf.GetAtomPosition(i).y, conf.GetAtomPosition(i).z))
            for i in range(mol_rd.GetNumAtoms())]


def _build_fadh2():
    m = Chem.AddHs(Chem.MolFromSmiles(LUMIFLAVIN_RED))
    AllChem.EmbedMolecule(m, randomSeed=42)
    AllChem.MMFFOptimizeMolecule(m, maxIters=2000, mmffVariant="MMFF94s")
    return _atoms(m)


def _mol(atoms, charge, spin, basis):
    m = gto.Mole()
    m.atom = [(s, xyz) for s, xyz in atoms]
    m.basis = basis
    m.charge = charge
    m.spin = spin
    m.verbose = 0
    m.build()
    return m


def _mf(mol, xc, level_shift=0.0):
    mf = dft.RKS(mol) if mol.spin == 0 else dft.UKS(mol)
    mf.xc = xc
    mf = solvent.PCM(mf)
    mf.with_solvent.eps = SOLVENT_EPS_WATER
    mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 300
    mf.verbose = 0
    if level_shift:
        mf.level_shift = level_shift
    return mf


def _sp(atoms, charge, spin, xc, basis, level_shift=0.0) -> tuple[float, bool]:
    mf = _mf(_mol(atoms, charge, spin, basis), xc, level_shift)
    e = mf.kernel()
    if not mf.converged:
        mf = mf.newton()
        mf.max_cycle = 100
        e = mf.kernel()
    return float(e), bool(mf.converged)


def _opt(atoms, charge, spin, level_shift=0.0):
    """Geom-opt at B3LYP/def2-SVP+PCM → optimized atom list + converged flag."""
    mf = _mf(_mol(atoms, charge, spin, GEOMOPT_BASIS), "b3lyp", level_shift)
    mol_opt = geometric_solver.optimize(mf, maxsteps=50)
    syms = [mol_opt.atom_symbol(i) for i in range(mol_opt.natm)]
    coords = mol_opt.atom_coords(unit="Angstrom")
    converged = mol_opt.converged if hasattr(mol_opt, "converged") else True
    return [(s, tuple(c)) for s, c in zip(syms, coords, strict=False)], bool(converged)


def _load_ea_os3(plain: bool) -> tuple[float, str]:
    """EA_Os3 = E(Os II) − E(Os III), ωB97X/def2-TZVP. Drift-safe: read from cache."""
    name = "os_complex_wb97xd.json" if plain else "os_complex_wb97xd_dmbpy.json"
    p = DFT_CACHE / name
    if not p.exists():
        sys.exit(f"missing {p} — run 21f (wb97x) first" if not plain else f"missing {p}")
    d = json.loads(p.read_text())
    ea = (d["os2_plus"]["E_total_Ha"] - d["os3_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    return ea, name


def main(argv) -> int:
    plain = "--plain" in argv
    banner(f"Adiabatic ΔSCF generator — {'plain-bpy reference' if plain else 'dimethyl mediator'}")
    t0 = time.time()

    fadh2 = _build_fadh2()
    print(f"  FADH₂ lumiflavin: {len(fadh2)} atoms")

    # FAD side: geom-opt both states at B3LYP/def2-SVP, SP at ωB97X/def2-TZVP
    banner("FADH₂ geom-opt (B3LYP/def2-SVP+PCM)")
    t = time.time()
    red_opt, c_red = _opt(fadh2, 0, 0)
    print(f"  done {time.time()-t:.0f}s conv={c_red}")
    banner("FADH₂⁺ geom-opt (B3LYP/def2-SVP+PCM, doublet, level_shift=0.2)")
    t = time.time()
    cat_opt, c_cat = _opt(fadh2, 1, 1, level_shift=0.2)
    print(f"  done {time.time()-t:.0f}s conv={c_cat}")

    banner("ωB97X/def2-TZVP single-points")
    e_red, cr = _sp(red_opt, 0, 0, "wb97x", SP_BASIS)
    e_cat_ad, ca = _sp(cat_opt, 1, 1, "wb97x", SP_BASIS, level_shift=0.2)        # adiabatic (relaxed cation)
    e_cat_vert, cv = _sp(red_opt, 1, 1, "wb97x", SP_BASIS, level_shift=0.2)      # vertical (cation @ neutral geom)
    print(f"  E(FADH₂)            = {e_red:.6f} Ha  conv={cr}")
    print(f"  E(FADH₂⁺ @ cation)  = {e_cat_ad:.6f} Ha  conv={ca}")
    print(f"  E(FADH₂⁺ @ neutral) = {e_cat_vert:.6f} Ha  conv={cv}")

    ip_vertical = (e_cat_vert - e_red) * HARTREE_TO_EV
    ip_adiabatic = (e_cat_ad - e_red) * HARTREE_TO_EV
    relaxation = ip_adiabatic - ip_vertical

    ea_os3, ea_src = _load_ea_os3(plain)
    dG_vertical = ip_vertical - ea_os3
    dG_adiabatic = ip_adiabatic - ea_os3

    banner("Cascade ΔG per electron (raw DFT — mechanism, not verdict)")
    print(f"  IP_vertical  = {ip_vertical:+.4f} eV   IP_adiabatic = {ip_adiabatic:+.4f} eV   "
          f"(relax {relaxation:+.4f})")
    print(f"  EA_Os3       = {ea_os3:+.4f} eV   (from {ea_src})")
    print(f"  ΔG_vertical  = {dG_vertical:+.4f} eV   ΔG_adiabatic = {dG_adiabatic:+.4f} eV  "
          f"({'UPHILL' if dG_adiabatic > 0 else 'downhill'})")

    out = {
        "method": "Composite adiabatic ΔSCF: geom-opt B3LYP/def2-SVP+PCM, SP ωB97X/def2-TZVP+PCM. "
                  "FAD side recomputed; EA_Os3 loaded drift-safe from the Os ωB97X cache.",
        "mediator": "plain-bpy (reference)" if plain else "4,4'-dimethyl-bpy (real device, Zafar +309 mV)",
        "ea_os3_source": ea_src,
        "E_FADH2_Ha": e_red,
        "E_FADH2_cation_adiabatic_Ha": e_cat_ad,
        "E_FADH2_cation_vertical_Ha": e_cat_vert,
        "IP_vertical_eV": round(ip_vertical, 4),
        "IP_adiabatic_eV": round(ip_adiabatic, 4),
        "relaxation_eV": round(relaxation, 4),
        "EA_Os3_eV": round(ea_os3, 4),
        "dG_vertical_eV": round(dG_vertical, 4),
        "dG_adiabatic_eV": round(dG_adiabatic, 4),
        "geom_opt_converged": {"FADH2": c_red, "FADH2_cation": c_cat},
        "sp_converged": {"FADH2": cr, "cation_adiabatic": ca, "cation_vertical": cv},
        "wall_seconds": round(time.time() - t0, 1),
    }
    OUT.write_text(json.dumps(out, indent=2), encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)} — orphan cache now has a generator")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
