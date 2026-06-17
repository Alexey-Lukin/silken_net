#!/usr/bin/env python
"""L3 task ② — cluster-continuum micro-solvation of the Os(III/II) couple.

WHY. The raw FADH₂→Os cascade is uphill in *every* implicit-solvent method
(B3LYP-Koopmans −0.91 eV; ΔSCF ωB97X adiabatic +0.88 eV) while experiment is
−0.14 eV. Script 32 already shows the *flavin* PCET potential is reproduced to
~50 mV, so the flavin solvation is NOT the culprit — the ~1 eV residual lives on
the charge-changing **Os(III)²⁺/Os(II)⁺** couple. This is the textbook failure of
implicit (PCM) solvation for group-8 octahedral M(III/II): the ~1 V error is
pinned on the *directionality of 2nd-shell H-bonds* that a continuum cannot model
(Jaque/Truhlar JPCC 10.1021/jp406772u; Ru(H₂O)₆ ~1 V PCM error). The fix is
cluster-continuum — explicit waters on the worst-solvated sites + C-PCM outside.

This script tests whether explicit micro-solvation moves the Os energetics in the
gap-closing direction, on TWO systems:

  • aquo   — [Os(H₂O)₆]³⁺/²⁺ benchmark. n=0 (bare ion) → n=6 (inner shell). Same
             metal + basis as the real mediator, so the recovered PCM error
             transfers directly. Validates the protocol vs a known group-8 case.
  • mediator — the real cis-[Os(bpy)₂(1-MeIm)Cl]⁺/²⁺ (≡ ① parent / 21b) with
             k=0..3 explicit waters H-bonded to the Cl⁻ ligand (the dominant
             directional H-bond site PCM gets wrong). k=0 reuses ① from cache.

Quantity = ΔSCF reduction energy ΔE_red(III→II) = E(Os II) − E(Os III), in eV
(shift-invariant to level_shift, unlike Koopmans orbital energies). The mediator
stage also reports the orbital cascade Δ = HOMO(FADH₂) − LUMO(Os III) for
continuity with ①. Screening tier = vertical (one geometry per system, both
oxidation states); inner-shell reorganization (~0.1–0.3 eV) ≈ cancels in the
*shift* across shells. Geometry relaxation = the publication refinement (xtb is
absent in silken_md → would relax with pyscf.geomopt; deferred to final numbers).

HONEST LIMITS (for §3.5): (a) a single shell does NOT converge the absolute
potential — n=6 over-, n=18 under-estimates (literature); the real complex is a
*bounded* estimate, full closure needs QM/MM (Минаєв capstone). (b) scalar-ECP
LANL2DZ omits Os spin-orbit coupling, which shifts Os(II/III) potentials
(JACS 10.1021/ja800616s). Both stated as method limits, not hidden.

Method: B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM, vertical ΔSCF, level_shift=0.3 (UKS
Os III only; E_total is shift-invariant). Sequential (feedback_dft_sequential),
no density_fit (feedback_no_df_heavy_metals). Cache-skip via microsolvation.json.

Run:  conda activate silken_md
      python tools/in_silico/scripts/34_dft_microsolvation.py aquo      # cheap benchmark
      python tools/in_silico/scripts/34_dft_microsolvation.py mediator  # real complex
      python tools/in_silico/scripts/34_dft_microsolvation.py           # both
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT
from lib.dft_utils import dft_singlepoint
from lib.os_geometry import BPY_SMILES, DMBPY_SMILES, build_os_complex, write_xyz
from lib.utils import banner

OUT = DFT_CACHE / "microsolvation.json"
# Chelate for the mediator/aqua/bis-Im stages. Default = parent bpy; `--dimethyl`
# (OS-RECOMPUTE) overrides to the real device 4,4'-dimethyl-bpy (Zafar +309 mV) and
# writes a separate cache so the plain-bpy records are never cache-skipped into it.
BPY = BPY_SMILES


def _xyz_stem(name: str) -> str:
    """Ligand xyz filename, dmbpy-prefixed when the dimethyl mediator is active so a
    --dimethyl run never clobbers the plain-bpy geometries (hexaaqua is ligand-independent)."""
    return f"{'os_dmbpy' if BPY == DMBPY_SMILES else 'os_bpy'}_{name}"
OS_O_AQUA = 2.10          # Å, Os–OH₂ (vertical, both oxidation states; screening tier)
OH = 0.9572               # Å, water O–H
HOH = np.radians(104.52)  # water bond angle
HB_O_X = 3.10             # Å, donor-O ⋯ acceptor distance for an O–H⋯X H-bond
FADH2_HOMO_EV = -5.137    # B3LYP cache (dft/lumiflavin.json red) — cascade donor level


def _unit(v):
    return v / np.linalg.norm(v)


def coord_water(o_pos, to_metal, ref=None):
    """Inner-shell water: O at o_pos, a lone pair toward the metal (`to_metal`
    unit vector), both H's splayed to the far side (M–O–H ≈ 128°)."""
    away = -_unit(to_metal)
    if ref is None:
        ref = np.array([0.0, 0.0, 1.0]) if abs(away[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    perp = _unit(ref - ref.dot(away) * away)
    h1 = o_pos + OH * (np.cos(HOH / 2) * away + np.sin(HOH / 2) * perp)
    h2 = o_pos + OH * (np.cos(HOH / 2) * away - np.sin(HOH / 2) * perp)
    return [("O", o_pos), ("H", h1), ("H", h2)]


def donor_water(acceptor_pos, approach_dir, ref=None):
    """H-bond-donor water: one O–H points at `acceptor_pos`; O sits HB_O_X away
    along `approach_dir` (unit, pointing outward from acceptor). Second H + lone
    pairs face away. Used to solvate the Cl⁻ ligand (O–H⋯Cl⁻)."""
    o_pos = acceptor_pos + HB_O_X * _unit(approach_dir)
    to_acc = _unit(acceptor_pos - o_pos)
    if ref is None:
        ref = np.array([0.0, 0.0, 1.0]) if abs(to_acc[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    perp = _unit(ref - ref.dot(to_acc) * to_acc)
    h1 = o_pos + OH * to_acc                                   # donates to acceptor
    h2 = o_pos + OH * (np.cos(HOH) * to_acc + np.sin(HOH) * perp)
    return [("O", o_pos), ("H", h1), ("H", h2)]


def build_hexaaqua(d=OS_O_AQUA):
    """[Os(H₂O)₆] octahedron: O at ±x,±y,±z·d, H's pointing outward."""
    atoms = [("Os", np.zeros(3))]
    for axis in (np.array([1.0, 0, 0]), np.array([0, 1.0, 0]), np.array([0, 0, 1.0])):
        for s in (1.0, -1.0):
            o = s * d * axis
            atoms += coord_water(o, to_metal=-o, ref=np.roll(axis, 1))
    return atoms


def build_hexaaqua_2shell(d=OS_O_AQUA):
    """[Os(H₂O)₆]·12H₂O — inner shell + a 2nd shell H-bonded to each inner O–H
    (12 acceptor waters, lone pair toward the inner-shell donor H). This is the
    literature n=18 cluster: n=6 over-, n=18 under-estimates E° → the pair brackets
    experiment and exposes the ~1 eV continuum-shell error."""
    inner = build_hexaaqua(d)
    atoms = list(inner)
    inner_O = [(i, p) for i, (s, p) in enumerate(inner) if s == "O"]
    for oi, op in inner_O:
        for hi in (oi + 1, oi + 2):                       # the two H's of this water
            hp = inner[hi][1]
            o2 = hp + 1.85 * _unit(hp - op)               # acceptor O ~2.8 Å from inner O
            atoms += coord_water(o2, to_metal=hp - o2)    # lone pair toward inner H
    return atoms


def run_pair(atoms, q_os2, q_os3, name, results, cache, xyz=None):
    """Compute the Os(II)/Os(III) ΔSCF pair for one geometry; cache-skip."""
    if name in cache and cache[name].get("converged"):
        banner(f"② {name} — reused from cache")
        results.append(cache[name])
        return cache[name]
    banner(f"② {name}  (Os(II) q={q_os2} s=0 / Os(III) q={q_os3} s=1)")
    if xyz is not None:
        write_xyz(atoms, xyz, f"② {name}")
    os2 = dft_singlepoint(atoms, charge=q_os2, spin=0, label=f"Os(II) {name}")
    print(f"  Os(II)  E={os2['E_total_Ha']:.6f} Ha  LUMO={os2['LUMO_eV']:.3f}  "
          f"({os2['n_atoms']} at, {os2['wall_seconds']}s, conv={os2['converged']})")
    os3 = dft_singlepoint(atoms, charge=q_os3, spin=1, label=f"Os(III) {name}",
                          level_shift_open=0.3)
    print(f"  Os(III) E={os3['E_total_Ha']:.6f} Ha  LUMO={os3['LUMO_eV']:.3f}  "
          f"({os3['n_atoms']} at, {os3['wall_seconds']}s, conv={os3['converged']})")
    dE_red = (os2["E_total_Ha"] - os3["E_total_Ha"]) * HARTREE_TO_EV
    rec = {
        "name": name, "n_atoms": os2["n_atoms"], "os2": os2, "os3": os3,
        "dE_red_eV": round(dE_red, 4),
        "cascade_delta_eV": round(FADH2_HOMO_EV - os3["LUMO_eV"], 4),
        "converged": os2["converged"] and os3["converged"],
    }
    print(f"  ΔE_red(III→II) = {dE_red:+.4f} eV   cascadeΔ = {rec['cascade_delta_eV']:+.4f} eV")
    results.append(rec)
    return rec


def stage_aquo(results, cache, two_shell=False):
    """[Os(H₂O)₆]³⁺/²⁺ group-8 PCM benchmark. n=6 inner shell (cheap, primary);
    n=18 two-shell (heavy) when `two_shell` — the pair brackets experiment."""
    banner("STAGE aquo — [Os(H₂O)₆]³⁺/²⁺ group-8 PCM benchmark")
    # waters are neutral → Os(II) = complex +2, Os(III) = complex +3.
    run_pair(build_hexaaqua(), q_os2=2, q_os3=3, name="aquo_n6_innershell",
             results=results, cache=cache, xyz=LIGANDS_DIR / "os_hexaaqua.xyz")
    if two_shell:
        run_pair(build_hexaaqua_2shell(), q_os2=2, q_os3=3, name="aquo_n18_twoshell",
                 results=results, cache=cache, xyz=LIGANDS_DIR / "os_hexaaqua_2shell.xyz")


def stage_mediator(results, cache):
    """Real cis-[Os(bpy)₂(1-MeIm)Cl]⁺/²⁺ + k waters H-bonded to the Cl⁻ ligand.
    k=0 ≡ ① parent (21b). Cl is the last-appended atom from build_os_complex."""
    banner("STAGE mediator — [Os(bpy)₂(MeIm)Cl]⁺/²⁺ + k·H₂O on Cl⁻")
    base, info = build_os_complex(bpy_smiles=BPY)  # axial = (MeIm +y, Cl +x)
    cl_idx = next(i for i, (s, _) in enumerate(base) if s == "Cl")
    cl_pos = base[cl_idx][1]
    os_pos = base[0][1]
    cl_out = _unit(cl_pos - os_pos)               # Os→Cl, outward
    # up to 3 waters around Cl⁻: one straight out, two splayed ±60° off-axis
    perp = _unit(np.cross(cl_out, np.array([0.0, 0.0, 1.0])))
    perp2 = _unit(np.cross(cl_out, perp))
    approaches = [
        cl_out,
        _unit(np.cos(np.radians(55)) * cl_out + np.sin(np.radians(55)) * perp),
        _unit(np.cos(np.radians(55)) * cl_out + np.sin(np.radians(55)) * perp2),
    ]
    print(f"  base complex: {info['n_atoms']} atoms, Cl#{cl_idx} at {cl_pos.round(2)}")
    for k in range(0, 4):
        atoms = list(base)
        for j in range(k):
            atoms += donor_water(cl_pos, approaches[j], ref=perp if j else None)
        run_pair(atoms, q_os2=1, q_os3=2, name=f"mediator_k{k}_clwaters",
                 results=results, cache=cache,
                 xyz=LIGANDS_DIR / _xyz_stem(f"meim_cl_{k}w.xyz") if k else None)


def stage_bisim(results, cache):
    """Bis-imidazole speciation: cis-[Os(bpy)₂(1-MeIm)₂]²⁺/³⁺ — Cl⁻ replaced by a 2nd
    1-methylimidazole (CHEM.20/26: in the PVI brush a 2nd imidazole from the chain
    is the likely 6th ligand, not Cl⁻ or H₂O — the most PVI-realistic form). +2/+3
    couple like aqua. Predicted: MeIm is a stronger σ-donor than H₂O → slightly LOWER
    E° / worse acceptor than aqua, but better than chloro (anionic Cl removed). Settles
    the note's direction-confusion (the note claimed stronger donor → better acceptor,
    which is backwards)."""
    from lib.os_geometry import MEIM_SMILES
    banner("STAGE bisim — [Os(bpy)₂(1-MeIm)₂]²⁺/³⁺ (Cl⁻→2nd imidazole, PVI-realistic)")
    axial = (("ligand", MEIM_SMILES, "N"), ("ligand", MEIM_SMILES, "N"))
    # The two cis 1-MeIm rings place co-planar (both in the xy plane) and clash (H–H
    # 0.91 Å). Twist each about its Os–N bond into a propeller; a 2D scan over the two
    # twists maximises the min non-bonded inter-ligand contact at (45°, 30°) → 2.23 Å
    # (ring–ring and ring–bpy both relieved). Rotation about the M–N bond is a real
    # low-barrier DOF, so the vertical ΔSCF couple stays on the same programmatic tier
    # as the chloro/aqua stages (apples-to-apples speciation).
    atoms, info = build_os_complex(bpy_smiles=BPY, axial=axial, axial_twists=(45.0, 30.0))
    print(f"  bis-Im complex: {info['n_atoms']} atoms, min-interlig {info['min_interlig_A']} Å "
          f"({info['min_interlig_pair']}), Os-coord {info['os_coord_distances_A']}")
    if info["min_interlig_A"] < 1.8:
        print(f"  ⚠️ SKIP bis-Im — rings still clash ({info['min_interlig_A']} Å < 1.8 non-bonded); "
              f"re-tune axial_twists (00_07 CHEM.20/26).")
        return
    run_pair(atoms, q_os2=2, q_os3=3, name="bisim_meim2",
             results=results, cache=cache, xyz=LIGANDS_DIR / _xyz_stem("meim2.xyz"))


def stage_aqua(results, cache):
    """Aquation speciation: cis-[Os(bpy)₂(1-MeIm)(H₂O)]²⁺/³⁺ — Cl⁻ replaced by a
    coordinated water (the inner-shell LIMIT of micro-solvation). L3 Caveat 5: the
    real Os-PVI mediator is likely the aqua (or bis-imidazole) form, and the cited
    exp E°≈+200 mV probably belongs to it, NOT the chloro complex (① / mediator k0).
    A +2/+3 couple (like the [Os(H₂O)₆] benchmark), so differential solvation is
    more severe; the weaker H₂O donor (vs π-donor Cl⁻) leaves Os(III) less
    stabilized → higher E° → lower LUMO → better cascade acceptor. Tests speciation
    as a cascade-alignment correction distinct from outer-sphere solvation."""
    from lib.os_geometry import MEIM_SMILES, WATER_SMILES
    banner("STAGE aqua — [Os(bpy)₂(MeIm)(H₂O)]²⁺/³⁺ (Cl⁻→aqua speciation)")
    axial = (("ligand", MEIM_SMILES, "N"), ("ligand", WATER_SMILES, "O"))
    atoms, info = build_os_complex(bpy_smiles=BPY, axial=axial)
    print(f"  aqua complex: {info['n_atoms']} atoms, min {info['min_contact_A']} Å, "
          f"Os-coord {info['os_coord_distances_A']}")
    run_pair(atoms, q_os2=2, q_os3=3, name="aqua_meim_h2o",
             results=results, cache=cache, xyz=LIGANDS_DIR / _xyz_stem("meim_h2o.xyz"))


def summarize(results):
    banner("② SUMMARY — micro-solvation shift in ΔE_red(III→II)")
    aquo = [r for r in results if r["name"].startswith("aquo")]
    med = [r for r in results if r["name"].startswith("mediator")]
    for r in (x for x in results if x["name"].startswith("aqua_")):
        print(f"  aqua  {r['n_atoms']} at  ΔE_red {r['dE_red_eV']:+.4f} eV  "
              f"cascadeΔ {r['cascade_delta_eV']:+.4f} eV  (Cl⁻→H₂O speciation)")
    n6 = next((r for r in aquo if "n6" in r["name"]), None)
    n18 = next((r for r in aquo if "n18" in r["name"]), None)
    if n6:
        line = f"  aquo  n6 ΔE_red {n6['dE_red_eV']:+.3f} eV"
        if n18:
            line += (f"  →  n18 {n18['dE_red_eV']:+.3f} eV  "
                     f"(2nd-shell shift {n18['dE_red_eV'] - n6['dE_red_eV']:+.3f} eV)")
        print(line)
    if med:
        k0 = next((r for r in med if r["name"].startswith("mediator_k0")), None)
        print("  mediator  k·H₂O(Cl⁻)   ΔE_red(eV)   cascadeΔ(eV)   shift_vs_k0")
        for r in med:
            sh = (r["dE_red_eV"] - k0["dE_red_eV"]) if k0 else float("nan")
            print(f"    {r['name'].split('_')[1]:>3s}   {r['n_atoms']:3d} at   "
                  f"{r['dE_red_eV']:+.4f}    {r['cascade_delta_eV']:+.4f}    {sh:+.4f}")


def main(argv) -> int:
    global BPY, OUT
    argv = list(argv)
    if "--dimethyl" in argv:   # OS-RECOMPUTE: real device mediator + separate cache
        BPY = DMBPY_SMILES
        OUT = DFT_CACHE / "microsolvation_dmbpy.json"
        argv.remove("--dimethyl")
    stage = argv[1] if len(argv) > 1 else "all"
    cache = {}
    if OUT.exists():
        try:
            cache = {r["name"]: r for r in json.loads(OUT.read_text())["results"]
                     if r.get("converged")}
        except Exception:
            cache = {}
    results = []
    if stage in ("aquo", "aquo18", "all"):
        stage_aquo(results, cache, two_shell=(stage == "aquo18"))
    if stage in ("mediator", "all"):
        stage_mediator(results, cache)
    if stage in ("aqua", "all"):
        stage_aqua(results, cache)
    if stage == "bisim":  # explicit-only (geometry-gated, see stage_bisim); not in "all"
        stage_bisim(results, cache)
    summarize(results)
    payload = {
        "method": "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF; cluster-continuum micro-solvation",
        "quantity": "ΔE_red(III→II) = E(Os II) − E(Os III), eV; cascadeΔ = HOMO(FADH₂ −5.137) − LUMO(OsIII)",
        "limits": "vertical (no reorg relax); single shell not converged (n6 over / n18 under); LANL2DZ omits Os SOC",
        "results": results,
    }
    # merge with any cached records not recomputed this run (keep all stages)
    if OUT.exists():
        try:
            old = {r["name"]: r for r in json.loads(OUT.read_text())["results"]}
            for name, rec in old.items():
                if name not in {r["name"] for r in results}:
                    results.append(rec)
        except Exception:
            pass
    OUT.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)} ({len(results)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
