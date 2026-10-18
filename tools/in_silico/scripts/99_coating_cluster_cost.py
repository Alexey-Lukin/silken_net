#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
99 — Can our L3 pipeline carry a cluster model of the biomimetic coatings on TiO₂ (00_07 HW.40, the desk leg «чи тягне
кластерну модель наш L3-конвеєр»)? Basis size of model clusters and the cost of one SCF, from the pipeline's own measured
run — no SCF is run here.

THE QUESTION. 01_04 §4.3 names surface DFT of Zn-HAp and PEDOT:PSS clusters on TiO₂ (adsorption energies, charge transfer)
as an R&D candidate, and HW.40 asks whether our PySCF tier can carry it without a collaborator. The cost of a hybrid-DFT
SCF is set by the number of basis functions, and that depends only on the COMPOSITION and the basis — not on geometry — so
it can be measured honestly before anyone builds a structure.

WHAT IS COMPUTED. (1) The basis functions (PySCF `nao_nr`) of a ladder of model compositions at the pipeline's two tiers —
21e's B3LYP/6-31G(d) (+LANL2DZ ECP on Os) and 21f's def2-TZVP — and of the pipeline's reference, the Os(dmbpy) complex
whose 21e-protocol Os(II) SCF 96 timed (its run log: `scf_wall_s`). The compositions are OURS — a size ladder, not a
validated surface model: a hydroxylated anatase-like (TiO₂)n·(H₂O)n/2 cluster, one hydroxyapatite unit cell with one Zn on a
Ca site (Ca₉Zn(PO₄)₆(OH)₂), an EDOT trimer and a styrenesulfonic-acid dimer, alone and each on the larger TiO₂ cluster.
Atoms are placed on a dummy grid: the count does not see positions. (2) One SCF's wall time, scaled from the reference as
(N/N_ref)^p with p = 3 and p = 4 — a named bracket (formal hybrid-DFT scaling is N⁴ with integral screening pulling it
down; neither end is measured here). Oxidised PEDOT is a polaron, a UKS doublet, and its open-shell factor is a bracket of
two named readings: ×2 (two spin Fock builds — OURS, formal) and 96's measured ratio of the Os(III) UKS control SCF to the
Os(II) RKS one, which carries a hard d-shell's convergence (Critical Rule #5) an organic radical need not have. (3) A
relaxation, as 96's measured ratio of one relaxation of the reference (7.9 h, its docstring) to its SCF. (4) What the env
carries for the adsorption energies the canon asks for: whether a dispersion correction is installed.

CAN: say how many times larger than our largest routine SCF these clusters are, and order of magnitude of one SCF and of a
relaxation. CANNOT: say whether a cluster of this size is a valid model of the surface (cluster-size and termination
convergence of adsorption energies is a study of its own, and a periodic slab is the usual model); say how many SCF cycles
these systems need (taken equal to the reference's); price basis-set superposition (counterpoise doubles the fragments);
give any adsorption energy.

Run:  python tools/in_silico/scripts/99_coating_cluster_cost.py      # seconds, no SCF
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import CACHE_DIR, DFT_CACHE
from lib.utils import banner

SI_DESCRIPTION = ("The basis size of model coating clusters (Zn-substituted hydroxyapatite and PEDOT:PSS on a TiO2 cluster) at "
                  "the pipeline's two tiers, and the cost of one SCF scaled from the pipeline's own timed run.")  # its row in the paper SI (72)
OUT_JSON = CACHE_DIR / "dft" / "coating_cluster_cost.json"
RUN_LOG_96 = CACHE_DIR / "runs" / "96" / "run.log"
REF_GEOMETRY = DFT_CACHE / "os_mediator_series_relaxed_os2.json"     # 21e's relaxed Os(II) dmbpy — the SCF 96 timed

TIERS = {"21e_b3lyp_631gd": {"default": "6-31g*", "Os": "lanl2dz"}, "21f_def2tzvp": {"default": "def2-tzvp", "Os": "lanl2dz"}}
ECP = {"Os": "lanl2dz"}
EXPONENTS = (3, 4)                       # OURS: the named bracket of SCF scaling with basis size
UKS_OVER_RKS_96 = 2.1 * 3600 / 656.8     # 96: Os(III) UKS control SCF 2.1 h (its docstring) over the Os(II) RKS SCF
UKS_FORMAL = 2.0                         # OURS: two spin Fock builds per cycle, the formal open-shell cost
RELAX_OVER_SCF_96 = 7.9 * 3600 / 656.8   # 96's docstring: one relaxation of the reference took 7.9 h


def ti_cluster(n: int) -> dict:
    return {"Ti": n, "O": 2 * n + n // 2, "H": n}          # (TiO₂)n·(H₂O)n/2 — hydroxylated termination


MODELS = {
    "TiO2_8": ti_cluster(8),
    "TiO2_16": ti_cluster(16),
    "Zn_HAp_cell": {"Ca": 9, "Zn": 1, "P": 6, "O": 26, "H": 2},                  # Ca₉Zn(PO₄)₆(OH)₂
    "EDOT_trimer": {"C": 18, "H": 14, "O": 6, "S": 3},                           # C₆nH₄n₊₂O₂nSn, n = 3
    "PSS_dimer": {"C": 16, "H": 18, "O": 6, "S": 2},                             # styrenesulfonic acid dimer, H-capped
}
MODELS["Zn_HAp_on_TiO2_16"] = {k: MODELS["Zn_HAp_cell"].get(k, 0) + MODELS["TiO2_16"].get(k, 0)
                               for k in sorted(set(MODELS["Zn_HAp_cell"]) | set(MODELS["TiO2_16"]))}  # sorted: stable bytes
MODELS["PEDOT_PSS_on_TiO2_16"] = {k: sum(MODELS[m].get(k, 0) for m in ("EDOT_trimer", "PSS_dimer", "TiO2_16"))
                                  for k in sorted(set().union(*(MODELS[m] for m in ("EDOT_trimer", "PSS_dimer", "TiO2_16"))))}
OPEN_SHELL = {"PEDOT_PSS_on_TiO2_16", "EDOT_trimer"}     # the oxidised (doped) PEDOT polaron is a doublet


def nao(composition: dict, basis: dict) -> int:
    from pyscf import gto
    sym = [el for el, n in sorted(composition.items()) for _ in range(n)]
    grid = list(itertools.islice(itertools.product(range(8), repeat=3), len(sym)))   # positions do not enter nao
    atoms = [(el, (3.0 * i, 3.0 * j, 3.0 * k)) for el, (i, j, k) in zip(sym, grid, strict=True)]  # > 512 atoms raises
    ne = sum(gto.charge(el) for el in sym)
    mol = gto.M(atom=atoms, basis=basis, ecp={k: v for k, v in ECP.items() if k in composition}, spin=ne % 2,
                verbose=0, unit="Angstrom")
    return int(mol.nao_nr())


def main() -> int:
    t0 = time.time()
    banner("99 — coating clusters on TiO2: basis size and the cost of one SCF from 96's timed run (HW.40)")
    log = RUN_LOG_96.read_text(encoding="utf-8")
    m = re.search(r"os2: E = .*?'scf_wall_s': ([0-9.]+)", log)
    if not m:
        raise SystemExit("96's run log carries no Os(II) scf_wall_s — the reference is gone")
    ref_wall = float(m.group(1))
    geo = json.loads(REF_GEOMETRY.read_text(encoding="utf-8"))["complexes"]["dmbpy"]["geometry_os2_relaxed"]["atoms"]
    ref_comp: dict = {}
    for el, _ in geo:
        ref_comp[el] = ref_comp.get(el, 0) + 1
    ref = {tier: nao(ref_comp, basis) for tier, basis in TIERS.items()}

    rows = {}
    for name, comp in MODELS.items():
        n = {tier: nao(comp, basis) for tier, basis in TIERS.items()}
        ratio = n["21e_b3lyp_631gd"] / ref["21e_b3lyp_631gd"]
        shells = (UKS_FORMAL, UKS_OVER_RKS_96) if name in OPEN_SHELL else (1.0, 1.0)
        hours = sorted(ref_wall * s * ratio ** p / 3600 for p in EXPONENTS for s in shells)
        rows[name] = {
            "composition": comp, "n_atoms": sum(comp.values()), "nao": n, "ratio_to_ref_21e": round(ratio, 2),
            "open_shell": name in OPEN_SHELL,
            "one_scf_h_21e": {"low": round(hours[0], 2), "high": round(hours[-1], 2)},
            "relaxation_days_21e": {"low": round(hours[0] * RELAX_OVER_SCF_96 / 24, 1),
                                    "high": round(hours[-1] * RELAX_OVER_SCF_96 / 24, 1)},
        }
    disp = {k: bool(importlib.util.find_spec(k)) for k in ("dftd3", "dftd4", "pyscf.dispersion")}

    big = rows["Zn_HAp_on_TiO2_16"]
    ped = rows["PEDOT_PSS_on_TiO2_16"]
    verdict = (
        f"At 21e's tier the reference Os(dmbpy) complex ({sum(ref_comp.values())} atoms) has {ref['21e_b3lyp_631gd']} basis "
        f"functions and its Os(II) SCF took {ref_wall:.0f} s in 96's run. Zn-HAp (one Zn-substituted unit cell) on a (TiO2)16 "
        f"cluster has {big['n_atoms']} atoms and {big['nao']['21e_b3lyp_631gd']} functions ({big['ratio_to_ref_21e']}× the "
        f"reference): one closed-shell SCF ≈ {big['one_scf_h_21e']['low']:.1f}–{big['one_scf_h_21e']['high']:.1f} h (N³–N⁴ "
        f"from the reference), a relaxation ≈ {big['relaxation_days_21e']['low']:.0f}–{big['relaxation_days_21e']['high']:.0f} "
        f"days at 96's relaxation/SCF ratio ({RELAX_OVER_SCF_96:.0f}). PEDOT:PSS (an EDOT trimer and a sulfonic-acid dimer) on "
        f"the same cluster has {ped['n_atoms']} atoms and {ped['nao']['21e_b3lyp_631gd']} functions ({ped['ratio_to_ref_21e']}×), "
        f"and as the oxidised polaron it is a UKS doublet: ≈ {ped['one_scf_h_21e']['low']:.0f}–{ped['one_scf_h_21e']['high']:.0f} "
        f"h for one SCF (open-shell factor ×{UKS_FORMAL:.0f} formal to ×{UKS_OVER_RKS_96:.1f} — 96's Os(III), a harder shell), "
        f"a relaxation ≈ {ped['relaxation_days_21e']['low']:.0f}–{ped['relaxation_days_21e']['high']:.0f} days. An adsorption "
        f"energy needs the complex and both fragments (twice that with counterpoise). The env carries no dispersion correction "
        f"({', '.join(k for k, v in disp.items() if not v)} absent), which an adsorption energy on an oxide is expected to need "
        f"(our expectation — no source in the tree). So one single-point screen is within reach of our CPU; a relaxed, "
        f"dispersion-corrected, size-converged adsorption study is not without a new dependency and weeks to over a year of "
        f"one CPU — and whether a cluster models the surface at all is the first question, which this count cannot answer.")

    out = {
        "question": "Can the in-silico L3 tier carry cluster models of Zn-HAp and PEDOT:PSS on TiO2 (00_07 HW.40) — basis size "
                    "and the cost of one SCF, measured from composition and scaled from the pipeline's own timed run.",
        "reference": {"system": "21e Os(II) dmbpy, relaxed (os_mediator_series_relaxed_os2.json)", "composition": ref_comp,
                      "n_atoms": sum(ref_comp.values()), "nao": ref, "scf_wall_s_96": ref_wall,
                      "uks_over_rks_96": round(UKS_OVER_RKS_96, 2), "uks_formal_ours": UKS_FORMAL,
                      "relaxation_over_scf_96": round(RELAX_OVER_SCF_96, 1)},
        "tiers": TIERS, "exponent_bracket_ours": list(EXPONENTS),
        "models_ours": "a size ladder, not a validated surface model — compositions in the script",
        "by_model": rows,
        "dispersion_in_env": disp,
        "not_modelled": ["whether a cluster of this size models the surface (cluster-size and termination convergence)",
                         "the SCF cycle count of these systems (taken equal to the reference's)",
                         "basis-set superposition (counterpoise)", "any adsorption energy"],
        "verdict": verdict,
    }
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  reference: {sum(ref_comp.values())} atoms · nao {ref} · SCF {ref_wall:.0f} s")
    for name, r in rows.items():
        print(f"  {name:22s} {r['n_atoms']:4d} atoms · nao {r['nao']} · ×{r['ratio_to_ref_21e']} · one SCF "
              f"{r['one_scf_h_21e']['low']}–{r['one_scf_h_21e']['high']} h · relax {r['relaxation_days_21e']['low']}–"
              f"{r['relaxation_days_21e']['high']} d{' (UKS)' if r['open_shell'] else ''}")
    print(f"  dispersion in env: {disp}")
    print(f"\n  VERDICT: {verdict}")
    banner(f"✅ saved {OUT_JSON.name} · {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
