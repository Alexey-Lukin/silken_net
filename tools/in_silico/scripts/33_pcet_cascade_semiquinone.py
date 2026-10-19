#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
L3 — PCET-corrected anode oxidation via the neutral semiquinone (FADH•).

Root-cause hypothesis for the UPHILL vertical ΔSCF cascade (written for its +0.998 eV on the 4a,5-dihydro
donor the chain carried until 2026-10-15). The ΔSCF cascade used the BARE cation-radical IP:
    FADH₂ → FADH₂•⁺ + e⁻        = IP_vertical of 21g   (WRONG in water)
The uncompensated cation radical FADH₂•⁺ is pathological in implicit solvent
(it also broke the Nelsen-λ script 29) — measured on the 4a,5-dihydro tautomer; on the 1,5-dihydro donor
21g relaxes FADH₂•⁺ to a minimum (its Hessian, 2026-10-19). The physically correct first oxidation
step in water is PROTON-COUPLED — it sheds a proton concertedly:
    FADH₂ → FADH• + H⁺ + e⁻
with the proton handled by the thermodynamic proton reference (no explicit
water, no QM/MM):
    Cost_PCET = [E(FADH•) − E(FADH₂)] + G*(H⁺,aq)

Then the cascade vs the Os reduction (cached ΔSCF of the dimethyl device, os_complex_wb97xd_dmbpy.json):
    ΔG_cascade(PCET) = Cost_PCET + ΔE(Os III→II)

Expectation (review): deprotonation relieves the cation-radical strain →
Cost_PCET drops ~1–1.5 eV below the bare IP → cascade collapses toward DOWNHILL,
matching experiment. (RESULT below: it does NOT flip — Cost_PCET lies ABOVE the bare IP on both
tautomers, so the cache's `drop_vs_bare_eV` holds that rise, not a drop; what the gap to the verified
−0.574 eV, E°(Os +309) − E°(FAD-GDH −265 mV SHE), is made of — revision step 3, 00_07 HW.5.IS.)

Levels: radical site screened at B3LYP/6-31G(d)+PCM (cheap), final energies
at ωB97X/def2-TZVP+PCM (consistent with the cached cascade pieces).

2026-10-15 (the 1,5-dihydro recompute, in-silico §Critical Rules #16): the flavin SMILES comes from lib/flavin.py and
is checked before any SCF; the semiquinone site is recorded by LOCANT (an RDKit index is not one — N1 of the new
SMILES and N5 of the retired one are both index 18); geometry goes through `lib/dft_utils.dft_optimize`, whose
convergence flag is real (since 2026-10-18 through `relax_checked`: a Hessian per species, an escape off a saddle); and the bare-IP comparison is LOADED from 21g's cache (`IP_vertical_eV`, `dG_vertical_eV` —
the same ωB97X/def2-TZVP+PCM tier, on 21g's def2-SVP minimum of the neutral — 35 meV from this script's 6-31G(d)
one at that tier) instead of the typed 5.391 / 0.998, which were hand-added
numbers on the 4a,5 tautomer. Run AFTER 21g.
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
from lib.constants import CACHE_DIR, DFT_CACHE, HARTREE_TO_EV, REPO_ROOT
from lib.dft_utils import relax_checked
from lib.flavin import LUMIFLAVIN_RED_SMILES, check_15_dihydro, locants
from lib.utils import banner

# Thermodynamic proton reference (same constant as script 32, Isse-Gennaro 2010)
G_STAR_H_AQ_EV = -11.72          # G*(H⁺,aq,1M); reviewer's no-1M-corr value = -11.80
EXP_CASCADE_EV = -0.574          # verified downhill: E°(Os +309) − E°(FAD-GDH −265 mV SHE); was −0.14 (Cosnier, withdrawn)

OUT_JSON = DFT_CACHE / "pcet_cascade.json"
RUNS = CACHE_DIR / "runs" / "33"   # Hessians and optimisation checkpoints (gitignored)
# 33's FADH₂ repeats 32b's reduced flavin — same builder, protocol and escape — so its minimum is 32b's (a free control)
THERMO_32B = DFT_CACHE / "pcet_redox_potential_thermo.json"


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


def _bare_cation_route() -> tuple[float, float, str]:
    """(IP_vertical, ΔG_vertical) of the bare FADH₂ → FADH₂•⁺ route from 21g's cache — the comparison this script's
    PCET route is set against. Loaded, never typed (in-silico §When Modifying #4)."""
    p = DFT_CACHE / "delta_scf_corrections.json"
    if not p.exists():
        sys.exit(f"missing {p.name} — run 21g first (the bare-IP comparison is read from it)")
    d = json.loads(p.read_text(encoding="utf-8"))
    return d["IP_vertical_eV"], d["dG_vertical_eV"], p.name


def atoms_from_rdkit(mol_rd):
    conf = mol_rd.GetConformer()
    return [(mol_rd.GetAtomWithIdx(i).GetSymbol(),
             (conf.GetAtomPosition(i).x, conf.GetAtomPosition(i).y, conf.GetAtomPosition(i).z))
            for i in range(mol_rd.GetNumAtoms())]


def build_fadh2():
    m = Chem.AddHs(Chem.MolFromSmiles(LUMIFLAVIN_RED_SMILES))
    check_15_dihydro(m)   # before any SCF (in-silico §Critical Rules #16)
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


def run_opt(atoms, charge, spin, label, level_shift=0.0):
    """Geom-opt at B3LYP/6-31G(d)+PCM through lib `relax_checked` → (atoms, summary, minimum_check): `dft_optimize`, then
    an analytic Hessian, and a saddle sends it off along its imaginary modes (§Critical Rules #18 — the planar RDKit/MMFF
    start of the 1,5-dihydro flavin converged to the butterfly's planar saddle in 32b). The summary carries geomeTRIC's
    own verdict (`converged`) and whether the point is a minimum (`minimum`); the caller gates on both."""
    return relax_checked(atoms, charge, spin, label=label, runs=RUNS, xc="b3lyp", basis_light="6-31g(d)",
                         level_shift_open=level_shift, conv_tol=1e-8, max_cycle=300)


def main() -> int:
    banner("PCET cascade via neutral semiquinone FADH• (anode oxidation)")
    RUNS.mkdir(parents=True, exist_ok=True)
    e_red_32b = json.loads(THERMO_32B.read_text())["species"]["red"]["E_Ha"]   # read first: a missing cache stops here
    t0 = time.time()

    fadh2 = build_fadh2()
    atoms_red = atoms_from_rdkit(fadh2)
    nh = nh_hydrogens(fadh2)
    loc = locants(fadh2)
    print(f"  FADH₂: {len(atoms_red)} atoms; candidate N-H sites: {[loc[n] for _, n in nh]}")

    # --- screen radical sites at B3LYP/6-31G(d) (cheap) ---
    banner("Screen semiquinone sites (B3LYP/6-31G(d)+PCM, UKS doublet)")
    best = None
    for h_idx, n_idx in nh:
        rad_atoms = [a for i, a in enumerate(atoms_red) if i != h_idx]
        mol = pyscf_mol(rad_atoms, charge=0, spin=1, basis="6-31g(d)")
        e, conv = run_sp(mol, "b3lyp", level_shift=0.2)
        print(f"    remove H@{loc[n_idx]}: E = {e:.6f} Ha  conv={conv}")
        if conv and (best is None or e < best[1]):
            best = (h_idx, e, n_idx, rad_atoms)
    if best is None:
        sys.exit("No converged semiquinone radical")
    h_idx, _, n_idx, rad_atoms = best
    site = loc[n_idx]
    print(f"  → most stable semiquinone: H removed from {site}" + ("" if site == "N1" else
          "  ⚠️ NOT N1: the physiological neutral semiquinone carries H on N5 (H removed from N1) — read before integrating"))

    # --- geometry-optimize BOTH neutral species (B3LYP/6-31G(d)+PCM) ---
    # Both are well-behaved closed-shell/doublet neutrals — no cation-radical
    # pathology (script 29 met it in FADH₂•⁺ on the 4a,5-dihydro tautomer; 21g relaxes the 1,5 one to a minimum,
    # and this script never optimizes it). Relaxing
    # is essential: an unrelaxed semiquinone is artificially strained.
    banner("Geometry optimization (B3LYP/6-31G(d)+PCM)")
    t = time.time()
    red_opt_atoms, opt_red, chk_red = run_opt(atoms_red, 0, 0, "FADH2")
    print(f"  FADH₂ opt done ({time.time()-t:.0f}s) conv={opt_red['converged']} steps={opt_red['steps']}")
    t = time.time()
    rad_opt_atoms, opt_rad, chk_rad = run_opt(rad_atoms, 0, 1, "FADH_radical", level_shift=0.2)
    print(f"  FADH• opt done ({time.time()-t:.0f}s) conv={opt_rad['converged']} steps={opt_rad['steps']}")
    if not all(o["converged"] and o["minimum"] for o in (opt_red, opt_rad)):
        side = OUT_JSON.with_suffix(".unconverged.json")
        side.write_text(json.dumps({"semiquinone_site": site, "geom_opt": {"FADH2": opt_red, "FADH_radical": opt_rad},
                                    "minimum_check": {"FADH2": chk_red, "FADH_radical": chk_rad}}, indent=2), encoding="utf-8")
        banner(f"⛔ geometry optimisation not converged, or not a minimum — {side.name} written, {OUT_JSON.name} untouched")
        return 1

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
    bare_ip, cascade_bare, bare_src = _bare_cation_route()
    print(f"  Bare cation-radical IP:         FADH₂→FADH₂•⁺      = {bare_ip:+.3f} eV ({bare_src})")
    print(f"  PCET oxidation cost:            FADH₂→FADH•+H⁺+e⁻ = {cost_pcet:+.3f} eV")
    print(f"  Drop vs bare IP:                {cost_pcet - bare_ip:+.3f} eV")
    print(f"  + Os(III)→Os(II) reduction:     {os_reduction:+.3f} eV (Os ωB97X cache, drift-safe)")
    print(f"  → ΔG_cascade(PCET):             {cascade_pcet:+.3f} eV")
    print(f"  (bare cascade = {cascade_bare:+.3f} eV; experiment = {EXP_CASCADE_EV:+.2f} eV)")
    downhill = cascade_pcet < 0
    print(f"  Verdict: {'✅ DOWNHILL — matches experiment' if downhill else '⚠️ still uphill'}")

    output = {
        "method": "PCET semiquinone: ωB97X/def2-TZVP+PCM // B3LYP/6-31G(d)+PCM "
                  "geom-opt; thermodynamic proton reference (G*(H+,aq)=-11.72 eV)",
        "semiquinone_site": site,
        "semiquinone_site_note": "locant from topology (lib/flavin.locants); H removed from that nitrogen",
        "fadh2_tautomer": {"name": "1,5-dihydrolumiflavin", "smiles": LUMIFLAVIN_RED_SMILES},
        "geom_opt": {"optimizer": "lib/dft_utils.relax_checked: dft_optimize (grid response, conv_tol 1e-8), analytic C-PCM Hessian, saddle escape",
                     "FADH2": opt_red, "FADH_radical": opt_rad},
        "minimum_check": {"FADH2": chk_red, "FADH_radical": chk_rad},
        "control_FADH2_minimum_vs_32b_Ha": chk_red["harmonic"]["E_Ha"] - e_red_32b,
        "E_FADH2_Ha": e_fadh2,
        "E_FADH_radical_Ha": e_fadhrad,
        "G_star_H_aq_eV": G_STAR_H_AQ_EV,
        "bare_IP_eV": round(bare_ip, 4),
        "bare_route_source": f"{bare_src} (IP_vertical_eV · dG_vertical_eV, 21g)",
        "pcet_oxidation_cost_eV": round(cost_pcet, 3),
        "drop_vs_bare_eV": round(cost_pcet - bare_ip, 3),
        "os_reduction_eV": round(os_reduction, 4),
        "cascade_pcet_eV": round(cascade_pcet, 3),
        "cascade_bare_eV": round(cascade_bare, 4),
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
