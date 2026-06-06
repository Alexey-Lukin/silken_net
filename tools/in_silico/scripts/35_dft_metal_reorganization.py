#!/usr/bin/env python
"""L3b task ③ — computed inner-sphere reorganization energy λ for the ZIF metal hops.

WHY. Script 24's Marcus rates used a blanket λ = 0.7 eV — too small for first-row /
redox-active metals whose coordination sphere relaxes a lot on electron transfer.
This computes λ from first principles per metal couple and feeds it back into 24,
replacing the guess. (The cathode-not-rate-limiting verdict is robust regardless;
this makes it quantitative.)

METHOD — Nelsen 4-point on a single-metal aquo model [M(H₂O)₆]^q (two-sphere Marcus
for a hop: λ_hop(M1-M2) = (λ_M1 + λ_M2)/2). Aquo is a robust, well-behaved proxy for
the ZIF imidazolate-N first shell — inner-sphere λ is dominated by the M–L bond
contraction on oxidation, only modestly ligand-dependent. This is the well-behaved
re-use of script 29's machinery (which failed ONLY for the pathological flavin
radical cation; closed-shell/localised metal d/f states are fine).

  λ = [E(red @ ox_geom) − E(red @ red_geom)] + [E(ox @ red_geom) − E(ox @ ox_geom)]

Couples (ZIF oxidation states, 01_03 §1): Cu²⁺/Cu⁺ (d⁹/d¹⁰) · Co³⁺/Co²⁺ (d⁶ LS / d⁷
HS) · Ce⁴⁺/Ce³⁺ (f⁰/f¹). B3LYP/6-31G(d)+lanl2dz(Cu,Co)/stuttgart_rsc(Ce)+C-PCM;
cross-SPs seeded from the diagonal density (prevents SCF collapse, script 29 pattern).

HONEST LIMITS (I own these): aquo ≠ the exact ZIF-N shell; Cu(I) prefers low
coordination and Ce has an f-electron → those geom-opts can misbehave. Each metal
reports a physicality check; where the 4-point is unphysical, the literature
self-exchange λ is used as fallback (flagged). Rigorous λ + diabatic coupling = CDFT
capstone (школа Мінаєва). Sequential, no density_fit (feedback_*). Cache-skip via
metal_reorganization.json.

Run:  python tools/in_silico/scripts/35_dft_metal_reorganization.py co   # pre-check one metal
      python tools/in_silico/scripts/35_dft_metal_reorganization.py        # all three
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, REPO_ROOT, HARTREE_TO_EV, BASIS_LIGHT, SOLVENT_EPS_WATER
from lib.utils import banner

OUT = DFT_CACHE / "metal_reorganization.json"
OH = 0.9572
HOH = np.radians(104.52)

# per-metal: basis/ecp, oxidised + reduced (charge, spin=2S, initial M–O Å), lit λ (eV, fallback)
METALS = {
    "cu": dict(sym="Cu", basis="lanl2dz", ecp="lanl2dz",
               ox=dict(q=2, spin=1, d=2.00), red=dict(q=1, spin=0, d=2.15), lit=2.0),
    "co": dict(sym="Co", basis="lanl2dz", ecp="lanl2dz",
               ox=dict(q=3, spin=0, d=1.91), red=dict(q=2, spin=3, d=2.10), lit=1.3),
    "ce": dict(sym="Ce", basis="stuttgart_rsc", ecp="stuttgart_rsc",
               ox=dict(q=4, spin=0, d=2.32), red=dict(q=3, spin=1, d=2.52), lit=1.0),
    # ZIF-N field control: [Co(NH₃)₆] vs aquo — does an N-donor field cut λ (smaller
    # bond change / Co²⁺ low-spin)? Co³⁺ LS / Co²⁺ HS (classic ammine couple); if even
    # this strong N-field keeps Co²⁺ HS → the large λ is real, not an aquo artifact.
    "co_nh3": dict(sym="Co", basis="lanl2dz", ecp="lanl2dz", ligand="ammine",
                   ox=dict(q=3, spin=0, d=1.97), red=dict(q=2, spin=3, d=2.12), lit=1.3),
    # note #29: Ru(III/II) is low-spin in BOTH states (4d, strong field) → no spin
    # crossover → small bond change → small λ → fast hop. The cathode fix vs Co.
    "ru": dict(sym="Ru", basis="lanl2dz", ecp="lanl2dz",
               ox=dict(q=3, spin=1, d=2.03), red=dict(q=2, spin=0, d=2.12), lit=0.8),
}


def _unit(v):
    return v / np.linalg.norm(v)


def build_hexaaqua(sym, d):
    """[M(H₂O)₆] octahedron, O at ±x,±y,±z·d, H's pointing outward."""
    atoms = [(sym, np.zeros(3))]
    for axis in (np.array([1.0, 0, 0]), np.array([0, 1.0, 0]), np.array([0, 0, 1.0])):
        for s in (1.0, -1.0):
            o = s * d * axis
            to = -_unit(o)
            ref = np.roll(axis, 1)
            perp = _unit(ref - ref.dot(to) * to)
            away = -to
            atoms.append(("O", o))
            atoms.append(("H", o + OH * (np.cos(HOH / 2) * away + np.sin(HOH / 2) * perp)))
            atoms.append(("H", o + OH * (np.cos(HOH / 2) * away - np.sin(HOH / 2) * perp)))
    return atoms


def build_hexammine(sym, d):
    """[M(NH₃)₆] octahedron — a clean, classic strong N-donor field. [Co(NH₃)₆]³⁺/²⁺
    is a textbook self-exchange couple (literature λ for validation). Used as the
    N-field test vs aquo: imidazole-ring placement is build-fiddly (recurring
    N–H-into-metal clashes — same class as the ZIF bug), whereas ammine builds
    cleanly (NH₃ H's point away from the metal by construction). Robustly answers
    "does an N-donor field cut λ vs the O-field?"; the conclusion transfers to the
    weaker-field ZIF imidazolate (if a *strong* ammine field doesn't force Co²⁺
    low-spin, the imidazolate won't either)."""
    atoms = [(sym, np.zeros(3))]
    NH, theta = 1.015, np.radians(70.0)              # M–N–H ≈ 110° → H's splay away from metal
    for dd in (np.array([1.0, 0, 0]), np.array([-1.0, 0, 0]), np.array([0, 1.0, 0]),
               np.array([0, -1.0, 0]), np.array([0, 0, 1.0]), np.array([0, 0, -1.0])):
        n = d * dd
        e1 = _unit(np.roll(dd, 1) - np.dot(np.roll(dd, 1), dd) * dd)
        e2 = np.cross(dd, e1)
        atoms.append(("N", n))
        for phi in (0.0, 2 * np.pi / 3, 4 * np.pi / 3):
            atoms.append(("H", n + NH * (np.cos(theta) * dd
                                         + np.sin(theta) * (np.cos(phi) * e1 + np.sin(phi) * e2))))
    return atoms


def build_cluster(cfg, d):
    """Dispatch the first-shell model by cfg['ligand'] ('aqua' default | 'ammine')."""
    if cfg.get("ligand") == "ammine":
        return build_hexammine(cfg["sym"], d)
    return build_hexaaqua(cfg["sym"], d)


def metal_mol(atoms, cfg, q, spin):
    from pyscf import gto
    a = [(s, (float(p[0]), float(p[1]), float(p[2]))) for s, p in atoms]
    return gto.M(atom=a, basis={cfg["sym"]: cfg["basis"], "default": BASIS_LIGHT},
                 ecp={cfg["sym"]: cfg["ecp"]}, charge=q, spin=spin, unit="Angstrom")


def run_sp(mol, level_shift=0.3, dm0=None):
    """PCM single-point; SOSCF (newton) fallback if DIIS stalls. Returns (mf, E)."""
    from pyscf import dft, solvent
    mf = dft.RKS(mol) if mol.spin == 0 else dft.UKS(mol)
    mf.xc = "b3lyp"
    mf = solvent.PCM(mf)
    mf.with_solvent.eps = SOLVENT_EPS_WATER
    mf.with_solvent.method = "C-PCM"
    mf.conv_tol = 1e-6
    mf.max_cycle = 300
    mf.verbose = 0
    if mol.spin != 0:
        mf.level_shift = level_shift
    e = mf.kernel(dm0=dm0)
    if not mf.converged:
        mf = mf.newton()
        mf.max_cycle = 100
        e = mf.kernel(dm0=mf.make_rdm1() if dm0 is None else dm0)
    return mf, float(e)


def run_opt(mol, level_shift=0.3, maxsteps=50):
    """Geometry-optimise (PCM) → optimised Mole. Returns (mol_opt, converged)."""
    from pyscf.geomopt import geometric_solver
    mf, _ = run_sp(mol, level_shift=level_shift)
    conv = True
    try:
        mol_opt = geometric_solver.optimize(mf, maxsteps=maxsteps)
    except Exception as exc:                          # opt blew up → caller flags
        print(f"    ⚠️ geom-opt exception: {exc}")
        mol_opt, conv = mol, False
    return mol_opt, conv


def _coords(mol):
    syms = [mol.atom_symbol(i) for i in range(mol.natm)]
    xyz = mol.atom_coords(unit="Angstrom")
    return [(syms[i], xyz[i]) for i in range(mol.natm)]


def _mo_dist(mol_opt, cfg):
    """Mean metal–ligand distance (Å) over the 6 nearest coordinating atoms (O for
    aqua, N for imidazole) — physicality probe (should contract on oxidation)."""
    coord_elem = "O" if cfg.get("ligand", "aqua") == "aqua" else "N"
    at = _coords(mol_opt)
    mp = next(p for s, p in at if s == cfg["sym"])
    return float(np.mean(sorted(np.linalg.norm(p - mp) for s, p in at if s == coord_elem)[:6]))


def compute_lambda(name, cfg):
    banner(f"③ λ — [{cfg['sym']}(H₂O)₆] {cfg['ox']['q']}+/{cfg['red']['q']}+ self-exchange")
    t0 = time.time()
    # geom-opt both oxidation states
    mol_ox = metal_mol(build_cluster(cfg, cfg["ox"]["d"]), cfg, cfg["ox"]["q"], cfg["ox"]["spin"])
    mol_ox_opt, c1 = run_opt(mol_ox)
    print(f"  ox  geom-opt done ({time.time()-t0:.0f}s)  ⟨M-O⟩={_mo_dist(mol_ox_opt, cfg):.3f} Å")
    t1 = time.time()
    mol_red = metal_mol(build_cluster(cfg, cfg["red"]["d"]), cfg, cfg["red"]["q"], cfg["red"]["spin"])
    mol_red_opt, c2 = run_opt(mol_red)
    print(f"  red geom-opt done ({time.time()-t1:.0f}s)  ⟨M-O⟩={_mo_dist(mol_red_opt, cfg):.3f} Å")

    # diagonal SPs (seed cross-SPs from these densities)
    mf_ox_d, E_ox_ox = run_sp(metal_mol(_coords(mol_ox_opt), cfg, cfg["ox"]["q"], cfg["ox"]["spin"]))
    mf_red_d, E_red_red = run_sp(metal_mol(_coords(mol_red_opt), cfg, cfg["red"]["q"], cfg["red"]["spin"]))
    # cross SPs (seeded): red@ox_geom, ox@red_geom
    _, E_red_ox = run_sp(metal_mol(_coords(mol_ox_opt), cfg, cfg["red"]["q"], cfg["red"]["spin"]),
                         dm0=mf_red_d.make_rdm1())
    _, E_ox_red = run_sp(metal_mol(_coords(mol_red_opt), cfg, cfg["ox"]["q"], cfg["ox"]["spin"]),
                         dm0=mf_ox_d.make_rdm1())

    lam1 = (E_red_ox - E_red_red) * HARTREE_TO_EV    # red distorted to ox geometry
    lam2 = (E_ox_red - E_ox_ox) * HARTREE_TO_EV      # ox distorted to red geometry
    lam = lam1 + lam2
    d_ox, d_red = _mo_dist(mol_ox_opt, cfg), _mo_dist(mol_red_opt, cfg)
    # physicality: λ in 0.2–4 eV, both opts converged, M–O contracts on oxidation (d_ox < d_red)
    physical = (0.2 < lam < 4.0) and c1 and c2 and (d_ox < d_red)
    print(f"  λ₁(red@ox)={lam1:+.3f}  λ₂(ox@red)={lam2:+.3f}  →  λ={lam:.3f} eV   "
          f"(lit≈{cfg['lit']}; {'✅ physical' if physical else '⚠️ suspect → lit fallback'})")
    return {
        "name": name, "metal": cfg["sym"], "couple": f"{cfg['ox']['q']}+/{cfg['red']['q']}+",
        "lambda_1_eV": round(lam1, 4), "lambda_2_eV": round(lam2, 4),
        "lambda_computed_eV": round(lam, 4), "lambda_lit_eV": cfg["lit"],
        "MO_ox_A": round(d_ox, 3), "MO_red_A": round(d_red, 3),
        "opt_converged": bool(c1 and c2), "physical": bool(physical),
        "lambda_use_eV": round(lam, 4) if physical else cfg["lit"],
        "wall_seconds": round(time.time() - t0, 1),
    }


def main(argv) -> int:
    which = [a for a in argv[1:] if a in METALS] or list(METALS)
    cache = {}
    if OUT.exists():
        try:
            cache = {r["name"]: r for r in json.loads(OUT.read_text())["results"]}
        except Exception:
            cache = {}
    results = []
    for name in which:
        if name in cache and cache[name].get("opt_converged"):
            banner(f"③ {name} — reused from cache (λ_use={cache[name]['lambda_use_eV']} eV)")
            results.append(cache[name])
            continue
        results.append(compute_lambda(name, METALS[name]))

    banner("③ λ SUMMARY (per metal) + two-sphere hop λ")
    for r in results:
        print(f"  {r['metal']:3s} {r['couple']:8s} λ_comp={r['lambda_computed_eV']:+.3f}  "
              f"use={r['lambda_use_eV']:.3f} eV  (M-O {r['MO_ox_A']}→{r['MO_red_A']} Å, "
              f"{'physical' if r['physical'] else 'LIT fallback'})")
    lam = {r["metal"]: r["lambda_use_eV"] for r in results}
    hops = {}
    if {"Cu", "Co"} <= lam.keys():
        hops["Cu-Co"] = round((lam["Cu"] + lam["Co"]) / 2, 3)
    if {"Co", "Ce"} <= lam.keys():
        hops["Co-Ce"] = round((lam["Co"] + lam["Ce"]) / 2, 3)
    if "Ce" in lam:
        hops["Ce-graphene"] = lam["Ce"]               # Ce↔aromatic; use Ce λ
    for h, v in hops.items():
        print(f"  hop {h:12s} λ = {v} eV  (two-sphere)")

    # merge cached records not recomputed this run
    if OUT.exists():
        try:
            old = {r["name"]: r for r in json.loads(OUT.read_text())["results"]}
            for nm, rec in old.items():
                if nm not in {r["name"] for r in results}:
                    results.append(rec)
        except Exception:
            pass
    OUT.write_text(json.dumps({
        "method": "Nelsen 4-point inner-sphere λ on [M(H₂O)₆]^q, B3LYP/6-31G(d)+lanl2dz/stuttgart_rsc+C-PCM",
        "note": "two-sphere Marcus λ_hop=(λ_M1+λ_M2)/2; aquo proxy for ZIF-N shell; lit fallback if unphysical; rigorous=CDFT capstone",
        "hops": hops, "results": results,
    }, indent=2), encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
