#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
99 — Can our L3 pipeline carry a cluster model of the biomimetic coatings on TiO₂ (00_07 HW.40, the desk leg «чи тягне
кластерну модель наш L3-конвеєр»)? Basis size of model clusters, measured; the cost of one SCF and of a relaxation,
ESTIMATED from the pipeline's own timed runs — no SCF is run here.

THE QUESTION. 01_04 §4.3 names surface DFT of Zn-HAp and PEDOT:PSS clusters on TiO₂ (adsorption energies, charge transfer)
as an R&D candidate, and HW.40 asks whether our PySCF tier can carry it without a collaborator. The cost of a hybrid-DFT
SCF grows with the number of basis functions, which depends only on COMPOSITION and basis — so it is measured honestly
before anyone builds a structure; the time is an extrapolation and is labelled one.

WHAT IS MEASURED. (1) `nao_nr` of a ladder of model compositions — OURS, a size ladder, not a validated surface model: a
hydroxylated (TiO₂)n·(H₂O)n/2 cluster, one hydroxyapatite cell with one Zn on a Ca site (Ca₉Zn(PO₄)₆(OH)₂), an EDOT
trimer and a styrenesulfonic-acid dimer, alone and each on (TiO₂)₁₆ — at three tiers: 21e's B3LYP/6-31G(d)+LANL2DZ(Os)
all-electron on the 3d metals, the same with LANL2DZ+ECP on Ti/Zn/Ca (the pipeline's 3d precedent is 24's LANL2DZ on
Cu/Co), and 21f's def2-TZVP. The PEDOT:PSS composite is the doped polaron: EDOT₃⁺ with one sulfonate deprotonated (PSS⁻),
an odd electron count — a UKS doublet; the lone trimer is modelled as the cation. Atoms sit on a dummy grid — the count
does not see positions. (2) From the committed caches, with the SAME count: the 21e series (os_mediator_series.json, its
complexes rebuilt by 21e's own builder from its SERIES table — the builder's atom and electron counts are checked against
the cache) and 21f's ωB97X extremes (os_mediator_series_wb97x.json), each with its timed Os(II) RKS and Os(III) UKS SCF.

WHAT IS ESTIMATED — every range is a bracket of NAMED readings, the low end optimistic, the high end pessimistic.
(3) One SCF = the tier's LARGEST routine SCF (the anchor) × (N / N_anchor)^p: low p = the exponent fitted within the
series (light-atom Os complexes), high p = 3 (OURS — beyond the fitted span); the high end also carries the composition
reading — primitives per basis function of the model over the anchor's (the clusters' 26 all-electron 3d/Ca atoms are
heavier per function than the series' light atoms). (4) The open-shell factor: low = the 21e series' routine Os(III)
UKS / Os(II) RKS minimum; high = the pipeline's own harder records at the tier — 34's micro-solvated pairs (H-bonded
waters, the closest analogue to a hydroxylated surface) at 21e's tier, 21f's ωB97X pairs at def2-TZVP (level shift,
Newton rescues and a stability analysis included, so a ceiling, not a routine cost). (5) A relaxation: low = the
shortest LONG-start relaxation of the five 21e Os(II) relaxations (a freshly built adsorbate is a long start, never the
near start), in SCF-equivalents; high = STEPS_MANY optimiser steps (OURS — the clusters' many soft OH, H-bond and torsion
modes; 21e caps at 120) × the largest SCF-equivalents per step of those relaxations. (6) A Hessian (the pipeline's
minimum check, `relax_to_minimum`): 96's RKS Hessian/SCF ratio; for UKS with a VV10 functional PySCF has no analytic
Hessian. (7) The env: D3/D4 and `pyscf.dispersion` absent; VV10 native (any functional can carry it); `pyscf.pbc`
present, its periodic cost not assessed here.

CAN: say how large these clusters are against the pipeline's own largest SCF, and the order of magnitude of one SCF, a
relaxation and a Hessian at two readings — B3LYP/6-31G(d) without dispersion, and the dispersion-inclusive def2-TZVP tier.
CANNOT: say whether a cluster of this size models the surface (a periodic slab is the usual model, and adsorption
energies need cluster-size and termination convergence); the SCF cycle count or the optimiser step count of these
systems (no cache holds cycle counts; steps are a named reading); VV10's own grid cost; the effect of C-PCM, which the
series ran and a surface model in vacuum would not (the gas/C-PCM pair is recorded, not applied); the periodic route;
give any adsorption energy (one needs the complex and both fragments relaxed, plus counterpoise SCFs).

Run:  python tools/in_silico/scripts/99_coating_cluster_cost.py      # seconds, no SCF
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import CACHE_DIR, DFT_CACHE
from lib.os_geometry import build_os_complex
from lib.utils import banner

SI_DESCRIPTION = ("The basis size of model coating clusters (Zn-substituted hydroxyapatite and PEDOT:PSS on a TiO2 cluster) at "
                  "the pipeline's tiers, and the cost of one SCF and of a relaxation extrapolated from the pipeline's own "
                  "timed series.")  # its row in the paper SI (72)
OUT_JSON = CACHE_DIR / "dft" / "coating_cluster_cost.json"
SERIES_CACHE = DFT_CACHE / "os_mediator_series.json"            # 21e default: B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM
WB97X_CACHE = DFT_CACHE / "os_mediator_series_wb97x.json"        # 21f's ωB97X/def2-TZVP extremes
RELAX_OS2 = DFT_CACHE / "os_mediator_series_relaxed_os2.json"
RELAX_OS3 = DFT_CACHE / "os_mediator_series_relaxed_os3.json"
GAS_CACHE = DFT_CACHE / "os_mediator_series_gas.json"

TIERS = {
    "21e_b3lyp_631gd": ({"default": "6-31g*", "Os": "lanl2dz"}, {"Os": "lanl2dz"}),
    "21e_lanl2dz_3d": ({"default": "6-31g*", "Os": "lanl2dz", "Ti": "lanl2dz", "Zn": "lanl2dz", "Ca": "lanl2dz"},
                       {"Os": "lanl2dz", "Ti": "lanl2dz", "Zn": "lanl2dz", "Ca": "lanl2dz"}),
    "21f_def2tzvp": ({"default": "def2-tzvp", "Os": "lanl2dz"}, {"Os": "lanl2dz"}),
}
MICRO_CACHE = DFT_CACHE / "microsolvation_dmbpy.json"           # 34's cluster-continuum pairs (H-bonded waters)
THERMO_CACHE = DFT_CACHE / "os_couple_thermo.json"               # 96: the RKS Hessian against its SCF
SCRIPT_21E = HERE / "21e_dft_os_mediator_series.py"
P_HIGH = 3                              # OURS: the named upper reading beyond the fitted range
STEPS_MANY = 200                        # OURS: optimiser steps of a soft 116–154-atom cluster (21e caps at 120)


def ti_cluster(n: int) -> dict:
    return {"H": n, "O": 2 * n + n // 2, "Ti": n}            # (TiO₂)n·(H₂O)n/2 — hydroxylated termination


def merge(*parts: dict, minus_h: int = 0) -> dict:
    out: dict = {}
    for part in parts:
        for el, n in part.items():
            out[el] = out.get(el, 0) + n
    out["H"] -= minus_h
    return dict(sorted(out.items()))                          # sorted: stable cache bytes


HAP_ZN = {"Ca": 9, "H": 2, "O": 26, "P": 6, "Zn": 1}           # Ca₉Zn(PO₄)₆(OH)₂
EDOT3 = {"C": 18, "H": 14, "O": 6, "S": 3}                     # C₆nH₄n₊₂O₂nSn, n = 3
PSS2 = {"C": 16, "H": 18, "O": 6, "S": 2}                      # styrenesulfonic acid dimer, H-capped
MODELS = {   # name: (composition, charge)
    "TiO2_8": (ti_cluster(8), 0),
    "TiO2_16": (ti_cluster(16), 0),
    "Zn_HAp_cell": (HAP_ZN, 0),
    "EDOT_trimer_cation": (EDOT3, +1),                                         # the polaron alone
    "PSS_dimer": (PSS2, 0),
    "Zn_HAp_on_TiO2_16": (merge(HAP_ZN, ti_cluster(16)), 0),
    "PEDOT_PSS_on_TiO2_16": (merge(EDOT3, PSS2, ti_cluster(16), minus_h=1), 0),  # EDOT₃⁺ · PSS⁻ (one sulfonate)
}
OPEN_SHELL = {"EDOT_trimer_cation", "PEDOT_PSS_on_TiO2_16"}


def nao(composition: dict, tier: str, charge: int = 0) -> tuple[int, int]:
    """Basis functions and electrons of a composition at a tier; spin is set by parity."""
    m = mol(composition, tier, charge)
    return int(m.nao_nr()), int(m.nelectron)


def mol(composition: dict, tier: str, charge: int = 0):
    from pyscf import gto
    basis, ecp = TIERS[tier]
    sym = [el for el, n in sorted(composition.items()) for _ in range(n)]
    grid = list(itertools.islice(itertools.product(range(8), repeat=3), len(sym)))   # positions do not enter nao
    atoms = [(el, (3.0 * i, 3.0 * j, 3.0 * k)) for el, (i, j, k) in zip(sym, grid, strict=True)]  # > 512 atoms raises
    ecp = {k: v for k, v in ecp.items() if k in composition}
    for spin in (0, 1):
        try:
            return gto.M(atom=atoms, basis=basis, ecp=ecp, charge=charge, spin=spin, verbose=0, unit="Angstrom")
        except RuntimeError:
            continue
    raise SystemExit(f"no consistent spin for {composition} at charge {charge}")


def series_points() -> dict:
    spec = importlib.util.spec_from_file_location("s21e", SCRIPT_21E)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["s21e"] = mod
    spec.loader.exec_module(mod)
    smiles = {name: smi for name, smi, _, _ in mod.SERIES}
    cache = {c["name"]: c for c in json.loads(SERIES_CACHE.read_text(encoding="utf-8"))["complexes"]}
    wb = json.loads(WB97X_CACHE.read_text(encoding="utf-8"))["complexes"]
    pts = {"21e_b3lyp_631gd": {}, "21f_def2tzvp": {}}
    for name, smi in smiles.items():
        atoms, _ = build_os_complex(bpy_smiles=smi)
        comp: dict = {}
        for a in atoms:
            comp[a[0]] = comp.get(a[0], 0) + 1
        for tier, src in (("21e_b3lyp_631gd", cache), ("21f_def2tzvp", wb)):
            if name not in src:
                continue
            c = src[name]
            if sum(comp.values()) != c["os2"]["n_atoms"]:
                raise SystemExit(f"21e's builder gives {sum(comp.values())} atoms for {name}, {tier} cached {c['os2']['n_atoms']}")
            n, ne = nao(comp, tier, c["os2"]["charge"])
            if ne != c["os2"]["n_electrons"]:
                raise SystemExit(f"{name} ({tier}): {ne} electrons against the cache's {c['os2']['n_electrons']}")
            m = mol(comp, tier, c["os2"]["charge"])
            pts[tier][name] = {"nao": n, "prim_per_nao": round(m.npgto_nr() / n, 4),
                               "rks_s": c["os2"]["wall_seconds"], "uks_s": c["os3"]["wall_seconds"]}
    return pts


def fit_p(points: dict) -> float:
    x = np.log([v["nao"] for v in points.values()])
    y = np.log([v["rks_s"] for v in points.values()])
    return float(np.polyfit(x, y, 1)[0])


def main() -> int:
    t0 = time.time()
    banner("99 — coating clusters on TiO2: basis size measured, SCF / relaxation / Hessian cost estimated (HW.40)")
    import pyscf
    from pyscf.dft import libxc
    pts = series_points()
    p_fit = {tier: round(fit_p(v), 2) for tier, v in pts.items()}
    anchor = {tier: max(v.items(), key=lambda kv: kv[1]["nao"]) for tier, v in pts.items()}
    anchor["21e_lanl2dz_3d"] = anchor["21e_b3lyp_631gd"]                  # the same Os-complex anchor (no 3d metal in it)
    p_fit["21e_lanl2dz_3d"] = p_fit["21e_b3lyp_631gd"]

    routine = [v["uks_s"] / v["rks_s"] for v in pts["21e_b3lyp_631gd"].values()]
    micro = [r["os3"]["wall_seconds"] / r["os2"]["wall_seconds"]
             for r in json.loads(MICRO_CACHE.read_text(encoding="utf-8"))["results"]]
    wbx = [v["uks_s"] / v["rks_s"] for v in pts["21f_def2tzvp"].values()]
    shell_readings = {"21e_routine_series": [round(min(routine), 2), round(max(routine), 2)],
                      "34_microsolvated": [round(min(micro), 2), round(max(micro), 2)],
                      "21f_wb97x_with_rescues": [round(min(wbx), 2), round(max(wbx), 2)]}
    shell = {"21e_b3lyp_631gd": (shell_readings["21e_routine_series"][0], shell_readings["34_microsolvated"][1]),
             "21e_lanl2dz_3d": (shell_readings["21e_routine_series"][0], shell_readings["34_microsolvated"][1]),
             "21f_def2tzvp": (shell_readings["21e_routine_series"][0], shell_readings["21f_wb97x_with_rescues"][1])}

    relax = {}
    for state, path, key, start in (("os2", RELAX_OS2, "geometry_os2_relaxed", "long"),
                                    ("os3", RELAX_OS3, "geometry_os3_relaxed", "near")):
        for name, c in json.loads(path.read_text(encoding="utf-8"))["complexes"].items():
            info = c[key]["info"]
            eq = info["wall_seconds"] / c[state]["wall_seconds"]
            relax[f"{state}_{name}"] = {"start": start, "steps": info["steps"], "scf_equivalents": round(eq, 1),
                                        "per_step": round(eq / info["steps"], 3), "maxsteps": info["maxsteps"]}
    long_ = [v for v in relax.values() if v["start"] == "long"]
    relax_lo = min(v["scf_equivalents"] for v in long_)
    per_step_hi = max(v["per_step"] for v in long_)
    relax_hi = round(STEPS_MANY * per_step_hi, 1)
    th = json.loads(THERMO_CACHE.read_text(encoding="utf-8"))["species"]["os2"]
    hess_over_scf = round(th["hessian_wall_s"] / th["scf_wall_s"], 1)
    gas = json.loads(GAS_CACHE.read_text(encoding="utf-8"))["complexes"]["dmbpy"]["os2"]["wall_seconds"]
    pcm = {c["name"]: c for c in json.loads(SERIES_CACHE.read_text(encoding="utf-8"))["complexes"]}["dmbpy"]["os2"]["wall_seconds"]

    rows = {}
    for name, (comp, charge) in MODELS.items():
        n, prim, ne = {}, {}, None
        for tier in TIERS:
            m = mol(comp, tier, charge)
            n[tier], prim[tier] = int(m.nao_nr()), round(m.npgto_nr() / m.nao_nr(), 4)
            ne = int(m.nelectron) if tier == "21e_b3lyp_631gd" else ne
        if (name in OPEN_SHELL) != (ne % 2 == 1):
            raise SystemExit(f"{name}: {ne} electrons — the open-shell set and the parity disagree")
        est = {}
        for tier in TIERS:
            a = anchor[tier][1]
            ratio = n[tier] / a["nao"]
            comp_f = max(1.0, prim[tier] / a["prim_per_nao"])
            s_lo, s_hi = shell[tier] if name in OPEN_SHELL else (1.0, 1.0)
            lo = a["rks_s"] * s_lo * ratio ** p_fit[tier] / 3600
            hi = a["rks_s"] * s_hi * comp_f * ratio ** P_HIGH / 3600
            lo, hi = min(lo, hi), max(lo, hi)
            est[tier] = {"ratio_to_anchor": round(ratio, 2), "composition_factor": round(comp_f, 2),
                         "one_scf_h": {"low": round(lo, 2), "high": round(hi, 2)},
                         "relaxation_days": {"low": round(lo * relax_lo / 24, 1), "high": round(hi * relax_hi / 24, 1)},
                         "rks_hessian_days": (None if name in OPEN_SHELL and tier == "21f_def2tzvp" else
                                              {"low": round(lo * hess_over_scf / 24, 1),
                                               "high": round(hi * hess_over_scf / 24, 1)})}
        rows[name] = {"composition": comp, "charge": charge, "n_atoms": sum(comp.values()), "n_electrons": ne,
                      "open_shell": name in OPEN_SHELL, "nao": n, "prim_per_nao": prim, "estimate": est}
    import inspect

    import pyscf.hessian.uks as hess_uks
    env = {"pyscf": pyscf.__version__,
           "dftd3": bool(importlib.util.find_spec("dftd3")), "dftd4": bool(importlib.util.find_spec("dftd4")),
           "pyscf_dispersion": bool(importlib.util.find_spec("pyscf.dispersion")),
           "vv10_native": bool(libxc.nlc_coeff("wb97x-v")),
           "uks_nlc_hessian": "UKS Hessian for NLC functional" not in inspect.getsource(hess_uks),
           "pyscf_pbc": bool(importlib.util.find_spec("pyscf.pbc"))}
    ecp_core = {el: int(mol({el: 1}, "21e_lanl2dz_3d", 0).atom_nelec_core(0)) for el in ("Ca", "Ti", "Zn")}

    z, pe = rows["Zn_HAp_on_TiO2_16"], rows["PEDOT_PSS_on_TiO2_16"]
    ae, af = anchor["21e_b3lyp_631gd"], anchor["21f_def2tzvp"]
    za, zt = z["estimate"]["21e_b3lyp_631gd"], z["estimate"]["21f_def2tzvp"]
    pa, pt = pe["estimate"]["21e_b3lyp_631gd"], pe["estimate"]["21f_def2tzvp"]

    def r(e, key, fmt=".0f"):
        return f"{e[key]['low']:{fmt}}–{e[key]['high']:{fmt}}"
    verdict = (
        f"Measured: Zn-HAp (one Zn-substituted cell) on a (TiO2)16 cluster has {z['n_atoms']} atoms and "
        f"{z['nao']['21e_b3lyp_631gd']} basis functions at 21e's tier ({z['nao']['21f_def2tzvp']} at def2-TZVP); "
        f"PEDOT:PSS as the doped polaron on it has {pe['n_atoms']} atoms, {pe['n_electrons']} electrons (a doublet) and "
        f"{pe['nao']['21e_b3lyp_631gd']} functions — {za['ratio_to_anchor']}× and {pa['ratio_to_anchor']}× the pipeline's "
        f"largest routine SCF at that tier ({ae[0]}, {ae[1]['nao']} functions, {ae[1]['rks_s']:.0f} s), and about the size "
        f"def2-TZVP already ran ({af[0]}, {af[1]['nao']} functions). Estimated, low end optimistic and high end "
        f"pessimistic: (A) B3LYP/6-31G(d) without dispersion — one SCF of Zn-HAp/TiO2 {r(za, 'one_scf_h', '.1f')} h, a "
        f"relaxation {r(za, 'relaxation_days', '.1f')} days; PEDOT:PSS {r(pa, 'one_scf_h', '.1f')} h and "
        f"{r(pa, 'relaxation_days')} days. (B) dispersion-inclusive at def2-TZVP (VV10 is native; its own grid cost is not "
        f"included) — Zn-HAp/TiO2 {r(zt, 'one_scf_h')} h per SCF and {r(zt, 'relaxation_days')} days per relaxation, "
        f"PEDOT:PSS {r(pt, 'one_scf_h')} h and {r(pt, 'relaxation_days')} days. Each is ONE configuration; adsorption sites, "
        f"cluster sizes and terminations multiply it, and an adsorption energy relaxes the complex and both fragments. A "
        f"certified minimum adds a Hessian ≈ {hess_over_scf:.0f} SCFs for RKS, and PySCF {pyscf.__version__} has no analytic "
        f"UKS Hessian for a VV10 functional, so the PEDOT polaron's minimum cannot be certified that way. So single SCFs and "
        f"a B3LYP screen of one configuration (days to a month) are within reach of our CPU; a dispersion-inclusive, "
        f"size-converged cluster study is months of one CPU for Zn-HAp and up to years for the PEDOT polaron at the "
        f"pessimistic end — the scale at which a collaborator or a compute allocation matters; the periodic route "
        f"(pyscf.pbc is installed) is not assessed here.")

    out = {
        "question": "Can the in-silico L3 tier carry cluster models of Zn-HAp and PEDOT:PSS on TiO2 (00_07 HW.40) — basis size "
                    "measured from composition, SCF, relaxation and Hessian cost estimated from the pipeline's own timed runs.",
        "tiers": {k: {"basis": v[0], "ecp": v[1]} for k, v in TIERS.items()},
        "ecp_core_electrons_lanl2dz_3d": ecp_core,
        "series_points": pts,
        "fit_exponent": p_fit, "upper_exponent_ours": P_HIGH,
        "anchor": {k: {"name": v[0], **v[1]} for k, v in anchor.items()},
        "open_shell_readings": shell_readings,
        "open_shell_factor_by_tier": {k: list(v) for k, v in shell.items()},
        "relaxations_21e": relax,
        "relaxation_scf_equivalents": {"low_shortest_long_start": relax_lo, "high_steps_many_ours": relax_hi,
                                       "steps_many_ours": STEPS_MANY, "per_step_high": per_step_hi},
        "rks_hessian_over_scf_96": hess_over_scf,
        "gas_over_cpcm_dmbpy_os2": round(gas / pcm, 2),
        "models_ours": "a size ladder, not a validated surface model — compositions and charges in the script",
        "by_model": rows,
        "env": env,
        "not_modelled": ["whether a cluster of this size models the surface (cluster-size and termination convergence)",
                         "the SCF cycle count and the optimiser step count of these systems (steps are a named reading)",
                         "VV10's own grid cost", "C-PCM in the series against vacuum for a surface model (recorded, not applied)",
                         "the periodic route (pyscf.pbc)", "any adsorption energy (complex + both fragments + counterpoise)"],
        "verdict": verdict,
    }
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  fit p {p_fit} · shell {shell} · relax SCF-eq {relax_lo}…{relax_hi} · Hessian/SCF {hess_over_scf} · env {env}")
    for name, row in rows.items():
        for tier in ("21e_b3lyp_631gd", "21f_def2tzvp"):
            e = row["estimate"][tier]
            print(f"  {name:22s} {tier:16s} nao {row['nao'][tier]:5d} ×{e['ratio_to_anchor']} comp {e['composition_factor']} · "
                  f"SCF {e['one_scf_h']['low']}–{e['one_scf_h']['high']} h · relax {e['relaxation_days']['low']}–"
                  f"{e['relaxation_days']['high']} d")
    print(f"\n  VERDICT: {verdict}")
    banner(f"✅ saved {OUT_JSON.name} · {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
