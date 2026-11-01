#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Cluster-charge probe of the deposited Cu–Co ZIF cluster — a RECORD, not a cache (self-review round 2, К8′ / П4(б′) stage 1).

Shipped `24b` runs `cu_co_zif.xyz` (four protonated terminal 2-methylimidazoles + one imidazolate bridge → ligands −1) at
charge +1, spin 2 → metals +2 (Cu(I)/Co(I)). The physical hop of the node (canon 01_03 §2.2: Cu²⁺/Cu⁺ · Co³⁺/Co²⁺) is
Cu(II)/Co(II) → metals +4 → cluster +3 on the deposited geometry; the builder docstring's intent (terminal imidazolates) →
strip the four N–H protons → cluster −1. Both variants, spins 2S = 2 and 4 (Cu(II) d⁹ S = ½ + high-spin Co(II) S = 3/2 →
triplet / quintet), same functional, basis, ECP and gas phase as 24b; the 24b two-orbital localisation and physicality check
applied verbatim (imported). The record it wrote on 2026-10-23 is `cache/reproduction/cluster_charge_probe_2026-10-23.json`:
no variant yields a readable diabatic pair (the +3 picks sit at the window edge ≈ 8 eV apart, the −1 picks are unbound virtuals
with mixed populations), so stage 2 — re-running 24/24b at the physical charge — did not start; the question of a continuum
treatment went back to the author. `--rehearse` = STO-3G, 5 SCF cycles, plumbing only.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import sys
import time
from pathlib import Path

from pyscf import dft, gto

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import BASIS_LIGHT, LIGANDS_DIR, REPO_ROOT

SI_DESCRIPTION = ("Charge probe of the deposited Cu–Co cluster: the two-orbital diabatisation of script 24b repeated at the "
                  "cluster's physical charge (+3) and on its imidazolate form (−1), two spin states each, in the gas phase; a "
                  "record of why no variant yields a readable diabatic pair, not a cache the manuscript quotes.")
OUT_DEFAULT = REPO_ROOT / "tools" / "in_silico" / "cache" / "reproduction" / "cluster_charge_probe_2026-10-23.json"

_spec = importlib.util.spec_from_file_location("s24b", Path(__file__).resolve().parent / "24b_fodft_coupling.py")
s24b = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(s24b)


def strip_nh_protons(atoms, cutoff=1.15):
    """Remove every H within `cutoff` Å of an N (the four terminal N–H of the deposited cluster)."""
    keep, removed = [], []
    for i, (sym, xyz) in enumerate(atoms):
        if sym == "H" and any(a[0] == "N" and math.dist(xyz, a[1]) < cutoff for a in atoms):
            removed.append(i)
        else:
            keep.append((sym, xyz))
    return keep, removed


def run(atoms, charge, spin, rehearse):
    basis = {"Cu": "lanl2dz", "Co": "lanl2dz", "default": ("sto-3g" if rehearse else BASIS_LIGHT)}
    mol = gto.M(atom=atoms, basis=basis, ecp={"Cu": "lanl2dz", "Co": "lanl2dz"},
                charge=charge, spin=spin, unit="Angstrom")
    cu_idx = [i for i, a in enumerate(atoms) if a[0] == "Cu"]
    co_idx = [i for i, a in enumerate(atoms) if a[0] == "Co"]
    mf = dft.UKS(mol)
    mf.xc = "b3lyp"
    mf.conv_tol = 1e-6
    mf.max_cycle = 5 if rehearse else 300
    mf.level_shift = 0.3
    mf.verbose = 0
    t0 = time.time()
    e = mf.kernel()
    rescued = False
    if not mf.converged and not rehearse:
        mf = mf.newton()
        mf.max_cycle = 100
        e = mf.kernel()
        rescued = True
    ss, mult = mf.spin_square()
    rec = {"charge": charge, "spin_2S": spin, "n_atoms": len(atoms), "n_electrons": mol.nelectron,
           "E_Ha": float(e), "converged": bool(mf.converged), "newton_rescue": rescued,
           "S2": float(ss), "multiplicity": float(mult), "wall_s": round(time.time() - t0, 1)}
    rec.update(s24b.couple(mol, mf, cu_idx, co_idx))
    return rec


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("out", type=Path, nargs="?", default=OUT_DEFAULT)
    ap.add_argument("--rehearse", action="store_true")
    ap.add_argument("--variants", default="protonated+3:2,protonated+3:4,imidazolate-1:2,imidazolate-1:4")
    args = ap.parse_args()
    atoms = s24b.read_xyz(LIGANDS_DIR / "cu_co_zif.xyz")
    strip, removed = strip_nh_protons(atoms)
    results = {"probe": "cluster charge, stage 1 of the ratified two-stage recompute; a record, NOT a cache", "rehearse": args.rehearse,
               "deposited_xyz": "cu_co_zif.xyz", "n_atoms_deposited": len(atoms),
               "nh_protons_stripped_for_imidazolate_variant": removed, "runs": []}
    for v in args.variants.split(","):
        name, spin = v.split(":")
        charge = int(name.split("+")[1]) if "+" in name else -int(name.split("-")[1])
        geom = strip if name.startswith("imidazolate") else atoms
        print(f"=== {name} spin={spin}: {len(geom)} atoms, charge {charge:+d} ===", flush=True)
        try:
            rec = run(geom, charge, int(spin), args.rehearse)
            rec["variant"] = name
        except Exception as exc:  # a parity or build error is data here, not a crash
            rec = {"variant": name, "charge": charge, "spin_2S": int(spin), "error": repr(exc)}
        results["runs"].append(rec)
        print(json.dumps(rec, indent=1), flush=True)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(results, indent=1))
    print("DONE", args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
