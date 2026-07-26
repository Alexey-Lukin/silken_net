#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""29c — outer-sphere (solvent) reorganization energy λ_o for the anode FAD→Os ET.

Closes the "total anode λ" loop: script 29b computed the *inner-sphere* λ_i = 0.389 eV
(FADH•/FADH⁻ Nelsen 4-point). The Marcus rate also needs the *outer-sphere* (solvent)
term λ_o. Here we add it from the classical Marcus **two-sphere** dielectric-continuum
model — analytical, no DFT:

    λ_o = (e²/4πε₀)·(1/2a_D + 1/2a_A − 1/d)·(1/ε_op − 1/ε_s)        [Marcus 1956]

    (e²/4πε₀ = 14.3996 eV·Å; a_D,a_A,d in Å; ε_op = optical = n²; ε_s = static.)

⚠️ INDICATIVE, not a clean compute (00_07): λ_o is strongly sensitive to the assumed
donor/acceptor radii, the donor–acceptor distance d, and the *local* static dielectric
ε_s (the FAD is buried → its environment is far from bulk water). We therefore report a
GRID, not a single number, and read off the physical conclusions (the bracket around the
literature 0.7–0.8 eV, and the burial effect), not a false-precision value.

Run:  mamba run -n silken_md python tools/in_silico/scripts/29c_outer_sphere_lambda.py
Cost: ~instant (analytical).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, REPO_ROOT
from lib.utils import banner

E2_4PIEPS0 = 14.399645          # eV·Å — e²/(4πε₀)
EPS_OP_WATER = 1.333 ** 2       # optical dielectric = n²  ≈ 1.777
EPS_S_WATER = 78.3553           # bulk water (lib SOLVENT_EPS_WATER)

# Donor/acceptor effective radii (Å) — the DOMINANT sensitivity, so radius is a grid axis.
# "hard-sphere" = naive small spheres; "delocalized" = the charge spreads over the flavin
# π-system (and the Os bpy ligands) → larger effective radius → smaller λ_o (the physical case).
RADII = {"hard-sphere (3.5/5.0)": (3.5, 5.0), "delocalized (6.0/6.0)": (6.0, 6.0)}
# Donor–acceptor centre-to-centre distance (Å): vdW contact ET vs the buried-FAD mediated reach.
D_GRID = {"contact": None, "tunnel (16)": 16.0}   # contact = a_D+a_A (per radius set)
# Local static dielectric: bulk water → partially-buried interface → protein interior.
EPS_S_GRID = {"water (78)": EPS_S_WATER, "buried (~4)": 4.0}


def lambda_o(a_d: float, a_a: float, d: float, eps_op: float, eps_s: float) -> float:
    geom = 1.0 / (2 * a_d) + 1.0 / (2 * a_a) - 1.0 / d
    pekar = 1.0 / eps_op - 1.0 / eps_s
    return E2_4PIEPS0 * geom * pekar


def main() -> int:
    sq = json.loads((DFT_CACHE / "semiquinone_lambda.json").read_text())
    lam_i = sq["lambda_inner_eV"]
    lit_total = sq["literature_lambda_total_eV"]

    banner("Outer-sphere λ_o (Marcus two-sphere) — anode FAD→Os")
    print(f"  inner-sphere λ_i (29b, cache) = {lam_i:.3f} eV | ε_op={EPS_OP_WATER:.3f} | lit total ≈ {lit_total} eV\n")
    print(f"  {'radii (Å)':>22} {'d (Å)':>8} {'ε_s':>12} {'λ_o (eV)':>10} {'λ_tot':>8}")
    print("  " + "-" * 64)

    grid = []
    for rname, (a_d, a_a) in RADII.items():
        for dname, dval in D_GRID.items():
            d = (a_d + a_a) if dval is None else dval
            for ename, eps_s in EPS_S_GRID.items():
                lo = lambda_o(a_d, a_a, d, EPS_OP_WATER, eps_s)
                tot = lam_i + lo
                grid.append({"radii_label": rname, "a_d_A": a_d, "a_a_A": a_a,
                             "d_label": dname, "d_A": d, "eps_s_label": ename, "eps_s": eps_s,
                             "lambda_o_eV": lo, "lambda_total_eV": tot})
                print(f"  {rname:>22} {d:>8.1f} {ename:>12} {lo:>10.3f} {tot:>8.3f}")

    los = [g["lambda_o_eV"] for g in grid]
    tots = [g["lambda_total_eV"] for g in grid]
    # Physically-motivated end: charge delocalized over the π-system AND a buried low-ε pocket.
    phys = [g["lambda_total_eV"] for g in grid if g["a_d_A"] >= 6.0 and g["eps_s"] <= 4.0]

    print()
    print(f"  λ_o spans {min(los):.2f}–{max(los):.2f} eV, λ_total {min(tots):.2f}–{max(tots):.2f} eV — radius/ε dominate.")
    print(f"  naive hard-sphere-in-water OVER-estimates (λ_total up to {max(tots):.2f} eV ≫ lit {lit_total}).")
    print(f"  physically-motivated end (delocalized π-charge + buried ε≈4): λ_total {min(phys):.2f}–{max(phys):.2f} eV.")
    verdict = (
        f"the two-sphere λ_o is radius/ε-DOMINATED (λ_total {min(tots):.2f}–{max(tots):.2f} eV across plausible "
        f"assumptions): naive hard-spheres in bulk water over-estimate (≫{lit_total}), while charge delocalized "
        f"over the flavin π-system in the buried low-ε pocket reproduces the literature ~0.7–0.8 eV "
        f"({min(phys):.2f}–{max(phys):.2f}). → we keep the LITERATURE λ in the Marcus rates (not a two-sphere "
        "number); this estimate only CONFIRMS that value is physically reasonable and shows WHY it is "
        "indicative (the point-sphere continuum model cannot pin λ_o to better than its radius assumption)."
    )
    print(f"\n  ⚠️ INDICATIVE — {verdict}")

    out = {
        "method": "Marcus two-sphere outer-sphere λ_o (dielectric continuum); analytical, INDICATIVE",
        "caveat": "radius/distance/local-ε dominated → grid not one number (00_07); rates keep the LIT λ",
        "lambda_inner_eV": lam_i, "literature_total_eV": lit_total,
        "params": {"eps_op": EPS_OP_WATER, "e2_4pieps0_eV_A": E2_4PIEPS0,
                   "radii_sets_A": RADII, "eps_s_grid": EPS_S_GRID},
        "grid": grid,
        "lambda_o_range_eV": [min(los), max(los)],
        "lambda_total_range_eV": [min(tots), max(tots)],
        "lambda_total_physical_end_eV": [min(phys), max(phys)],
        "verdict": verdict,
    }
    outp = DFT_CACHE / "outer_sphere_lambda.json"
    outp.write_text(json.dumps(out, indent=2))
    banner(f"✅ saved {outp.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
