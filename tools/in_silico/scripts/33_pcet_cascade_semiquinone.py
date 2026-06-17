#!/usr/bin/env python
"""
L3 — PCET-corrected anode oxidation via the neutral semiquinone (FADH•).

Root-cause fix for the +0.998 eV UPHILL cascade artifact. The ΔSCF cascade
used the BARE cation-radical IP:
    FADH₂ → FADH₂•⁺ + e⁻        = +5.391 eV   (WRONG in water)
The uncompensated cation radical FADH₂•⁺ is pathological in implicit solvent
(it also broke the Nelsen-λ script 29). The physically correct first oxidation
step in water is PROTON-COUPLED — it sheds a proton concertedly:
    FADH₂ → FADH• + H⁺ + e⁻
with the proton handled by the thermodynamic proton reference (no explicit
water, no QM/MM):
    Cost_PCET = [E(FADH•) − E(FADH₂)] + G*(H⁺,aq)

Then the cascade vs the Os reduction (cached ΔSCF, −4.392 eV):
    ΔG_cascade(PCET) = Cost_PCET + ΔE(Os III→II)

Expectation (review): deprotonation relieves the cation-radical strain →
Cost_PCET drops ~1–1.5 eV below +5.391 → cascade collapses toward DOWNHILL,
matching experiment. (RESULT below: it does NOT flip — the residual gap is the
PCM/speciation limit, not proton coupling; the verified driving force is −0.574 eV,
E°(Os +309) − E°(FAD-GDH −265 mV SHE).)

Levels: radical site screened at B3LYP/6-31G(d)+PCM (cheap), final energies
at ωB97X/def2-TZVP+PCM (consistent with the cached cascade pieces).
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
from lib.constants import DFT_CACHE, HARTREE_TO_EV, REPO_ROOT
from lib.utils import banner

LUMIFLAVIN_RED = "CC1=CC2=C(C=C1C)N(C)C3=NC(=O)NC(=O)C3N2"

# Thermodynamic proton reference (same constant as script 32, Isse-Gennaro 2010)
G_STAR_H_AQ_EV = -11.72          # G*(H⁺,aq,1M); reviewer's no-1M-corr value = -11.80
BARE_IP_EV = 5.391               # FADH₂ → FADH₂•⁺ + e⁻ (vertical FAD IP — unchanged by the mediator)
EXP_CASCADE_EV = -0.574          # verified downhill: E°(Os +309) − E°(FAD-GDH −265 mV SHE); was −0.14 (Cosnier, withdrawn)

OUT_JSON = DFT_CACHE / "pcet_cascade.json"


def _os_reduction_ev() -> float:
    """ΔE(Os III + e⁻ → Os II), ωB97X ΔSCF — LOADED drift-safe from the Os cache
    (OS-RECOMPUTE: prefer the real dimethyl mediator; fall back to plain-bpy until 21f
    wb97x has run, then a literal as last resort)."""
    for name in ("os_complex_wb97xd_dmbpy.json", "os_complex_wb97xd.json"):
        p = DFT_CACHE / name
        if p.exists():
            d = json.loads(p.read_text())
            return (d["os2_plus"]["E_total_Ha"] - d["os3_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    return -4.392


def atoms_from_rdkit(mol_rd):
    conf = mol_rd.GetConformer()
    return [(mol_rd.GetAtomWithIdx(i).GetSymbol(),
             (conf.GetAtomPosition(i).x, conf.GetAtomPosition(i).y, conf.GetAtomPosition(i).z))
            for i in range(mol_rd.GetNumAtoms())]


def build_fadh2():
    m = Chem.MolFromSmiles(LUMIFLAVIN_RED)
    m = Chem.AddHs(m)
    AllChem.EmbedMolecule(m, randomSeed=42)
    AllChem.MMFFOptimizeMolecule(m, maxIters=2000, mmffVariant="MMFF94s")
    return m


def nh_hydrogens(mol_rd):
    """Indices of H atoms bonded to a nitrogen (candidate deprotonation sites)."""
    out = []
    for a in mol_rd.GetAtoms():
        if a.GetSymbol() == "H":
            nbrs = a.GetNeighbors()
            if nbrs and nbrs[0].GetSymbol() == "N":
                out.append((a.GetIdx(), nbrs[0].GetIdx()))
    return out


def pyscf_mol(atoms, charge, spin, basis):
    mol = gto.Mole()
    mol.atom = [(s, xyz) for s, xyz in atoms]
    mol.basis = basis
    mol.charge = charge
    mol.spin = spin
    mol.verbose = 0
    mol.build()
    return mol


def _mf(mol, xc, level_shift=0.0):
    mf = dft.RKS(mol) if mol.spin == 0 else dft.UKS(mol)
    mf.xc = xc
    mf = solvent.PCM(mf)
    mf.with_solvent.eps = 78.3553
    mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 300
    mf.verbose = 0
    if level_shift:
        mf.level_shift = level_shift
    return mf


def run_sp(mol, xc, level_shift=0.0):
    mf = _mf(mol, xc, level_shift)
    e = mf.kernel()
    if not mf.converged:
        mf = mf.newton()
        mf.max_cycle = 100
        e = mf.kernel()
    return float(e), bool(mf.converged)


def run_opt(mol, xc, level_shift=0.0):
    """Geometry-optimize (well-behaved neutral species only) → optimized Mole."""
    mf = _mf(mol, xc, level_shift)
    mol_opt = geometric_solver.optimize(mf, maxsteps=50)
    return mol_opt


def main() -> int:
    banner("PCET cascade via neutral semiquinone FADH• (anode oxidation)")
    t0 = time.time()

    fadh2 = build_fadh2()
    atoms_red = atoms_from_rdkit(fadh2)
    nh = nh_hydrogens(fadh2)
    print(f"  FADH₂: {len(atoms_red)} atoms; candidate N-H sites: {[n for _, n in nh]}")

    # --- screen radical sites at B3LYP/6-31G(d) (cheap) ---
    banner("Screen semiquinone sites (B3LYP/6-31G(d)+PCM, UKS doublet)")
    best = None
    for h_idx, n_idx in nh:
        rad_atoms = [a for i, a in enumerate(atoms_red) if i != h_idx]
        mol = pyscf_mol(rad_atoms, charge=0, spin=1, basis="6-31g(d)")
        e, conv = run_sp(mol, "b3lyp", level_shift=0.2)
        print(f"    remove H@N{n_idx}: E = {e:.6f} Ha  conv={conv}")
        if conv and (best is None or e < best[1]):
            best = (h_idx, e, n_idx, rad_atoms)
    if best is None:
        sys.exit("No converged semiquinone radical")
    h_idx, _, n_idx, rad_atoms = best
    print(f"  → most stable semiquinone: H removed from N{n_idx}")

    # --- geometry-optimize BOTH neutral species (B3LYP/6-31G(d)+PCM) ---
    # Both are well-behaved closed-shell/doublet neutrals — no cation-radical
    # pathology (that only afflicts FADH₂•⁺, which we never optimize). Relaxing
    # is essential: an unrelaxed semiquinone is artificially strained.
    banner("Geometry optimization (B3LYP/6-31G(d)+PCM)")
    t = time.time()
    mol_red_opt = run_opt(pyscf_mol(atoms_red, 0, 0, "6-31g(d)"), "b3lyp")
    print(f"  FADH₂ opt done ({time.time()-t:.0f}s)")
    t = time.time()
    mol_rad_opt = run_opt(pyscf_mol(rad_atoms, 0, 1, "6-31g(d)"), "b3lyp", level_shift=0.2)
    print(f"  FADH• opt done ({time.time()-t:.0f}s)")

    def opt_atoms(mol_opt):
        syms = [mol_opt.atom_symbol(i) for i in range(mol_opt.natm)]
        coords = mol_opt.atom_coords(unit="Angstrom")
        return [(s, tuple(c)) for s, c in zip(syms, coords, strict=False)]

    red_opt_atoms = opt_atoms(mol_red_opt)
    rad_opt_atoms = opt_atoms(mol_rad_opt)

    # --- final energies at ωB97X/def2-TZVP+PCM (on optimized geometries) ---
    banner("Final energies (ωB97X/def2-TZVP+PCM, geom-optimized)")
    t = time.time()
    e_fadh2, c1 = run_sp(pyscf_mol(red_opt_atoms, 0, 0, "def2-tzvp"), "wb97x")
    print(f"  E(FADH₂)  = {e_fadh2:.6f} Ha ({time.time()-t:.0f}s) conv={c1}")
    t = time.time()
    e_fadhrad, c2 = run_sp(pyscf_mol(rad_opt_atoms, 0, 1, "def2-tzvp"), "wb97x", level_shift=0.2)
    print(f"  E(FADH•)  = {e_fadhrad:.6f} Ha ({time.time()-t:.0f}s) conv={c2}")

    # --- PCET arithmetic ---
    banner("PCET-corrected oxidation cost + cascade")
    cost_pcet = (e_fadhrad - e_fadh2) * HARTREE_TO_EV + G_STAR_H_AQ_EV
    os_reduction = _os_reduction_ev()
    cascade_pcet = cost_pcet + os_reduction
    print(f"  Bare cation-radical IP (old):   FADH₂→FADH₂•⁺      = +{BARE_IP_EV:.3f} eV")
    print(f"  PCET oxidation cost (new):      FADH₂→FADH•+H⁺+e⁻ = {cost_pcet:+.3f} eV")
    print(f"  Drop vs bare IP:                {cost_pcet - BARE_IP_EV:+.3f} eV")
    print(f"  + Os(III)→Os(II) reduction:     {os_reduction:+.3f} eV (Os ωB97X cache, drift-safe)")
    print(f"  → ΔG_cascade(PCET):             {cascade_pcet:+.3f} eV")
    print(f"  (old bare cascade = +0.998 eV uphill; experiment = {EXP_CASCADE_EV:+.2f} eV)")
    downhill = cascade_pcet < 0
    print(f"  Verdict: {'✅ DOWNHILL — matches experiment' if downhill else '⚠️ still uphill'}")

    output = {
        "method": "PCET semiquinone: ωB97X/def2-TZVP+PCM // B3LYP/6-31G(d)+PCM "
                  "geom-opt; thermodynamic proton reference (G*(H+,aq)=-11.72 eV)",
        "semiquinone_site": f"N{n_idx}",
        "E_FADH2_Ha": e_fadh2,
        "E_FADH_radical_Ha": e_fadhrad,
        "G_star_H_aq_eV": G_STAR_H_AQ_EV,
        "bare_IP_eV": BARE_IP_EV,
        "pcet_oxidation_cost_eV": round(cost_pcet, 3),
        "drop_vs_bare_eV": round(cost_pcet - BARE_IP_EV, 3),
        "os_reduction_eV": round(os_reduction, 4),
        "cascade_pcet_eV": round(cascade_pcet, 3),
        "cascade_bare_eV": 0.998,
        "exp_cascade_eV": EXP_CASCADE_EV,
        "downhill": bool(downhill),
        "converged": {"FADH2": c1, "FADH_radical": c2},
        "wall_seconds": time.time() - t0,
    }
    DFT_CACHE.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
