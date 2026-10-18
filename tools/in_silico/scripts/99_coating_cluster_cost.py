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

WHAT IS ESTIMATED. (3) The scaling exponent p from a log-log fit of SCF wall time against basis size within each series
(OURS as a fit); one SCF of a model = the tier's LARGEST routine SCF × (N / N_anchor)^p for p in [p_fit, 3] — the fit
holds only up to the anchor, and beyond it 3 is a named upper reading, not a measurement. (4) The open-shell factor: the
range of the 21e series' Os(III) UKS / Os(II) RKS ratio — routine runs (96's control SCF carried a stability analysis and
is NOT used). (5) A relaxation = SCF × the relaxation/SCF ratio of 21e's relaxed dmbpy, read in both states: Os(II) from
the programmatic octahedron (the long start) and Os(III) from the Os(II) minimum (the near start) — the ratio depends on
where a relaxation starts. (6) The env's dispersion options: D3/D4 packages, and PySCF's native VV10 (non-local
correlation in ωB97X-V-type functionals).

CAN: say how large these clusters are against the pipeline's own largest SCF, and the order of magnitude of one SCF and a
relaxation. CANNOT: say whether a cluster of this size models the surface (a periodic slab is the usual model, and
adsorption energies need cluster-size and termination convergence); the SCF cycle count of these systems (taken as the
series'); the effect of C-PCM, which the series ran and a surface model in vacuum would not (the tree's gas/C-PCM pair
is recorded, not applied); basis-set superposition (counterpoise: 5 SCFs per adsorption energy instead of 3); give any
adsorption energy.

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
P_HIGH = 3                              # OURS: the named upper reading beyond the fitted range


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
    from pyscf import gto
    basis, ecp = TIERS[tier]
    sym = [el for el, n in sorted(composition.items()) for _ in range(n)]
    grid = list(itertools.islice(itertools.product(range(8), repeat=3), len(sym)))   # positions do not enter nao
    atoms = [(el, (3.0 * i, 3.0 * j, 3.0 * k)) for el, (i, j, k) in zip(sym, grid, strict=True)]  # > 512 atoms raises
    ecp = {k: v for k, v in ecp.items() if k in composition}
    for spin in (0, 1):
        try:
            m = gto.M(atom=atoms, basis=basis, ecp=ecp, charge=charge, spin=spin, verbose=0, unit="Angstrom")
            return int(m.nao_nr()), int(m.nelectron)
        except RuntimeError:
            continue
    raise SystemExit(f"no consistent spin for {composition} at charge {charge}")


def series_points() -> dict:
    spec = importlib.util.spec_from_file_location("s21e", next(HERE.glob("21e_*.py")))
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
            pts[tier][name] = {"nao": n, "rks_s": c["os2"]["wall_seconds"], "uks_s": c["os3"]["wall_seconds"]}
    return pts


def fit_p(points: dict) -> float:
    x = np.log([v["nao"] for v in points.values()])
    y = np.log([v["rks_s"] for v in points.values()])
    return float(np.polyfit(x, y, 1)[0])


def main() -> int:
    t0 = time.time()
    banner("99 — coating clusters on TiO2: basis size measured, SCF and relaxation cost from the pipeline's series (HW.40)")
    pts = series_points()
    p_fit = {tier: round(fit_p(v), 2) for tier, v in pts.items()}
    anchor = {tier: max(v.items(), key=lambda kv: kv[1]["nao"]) for tier, v in pts.items()}
    anchor["21e_lanl2dz_3d"] = anchor["21e_b3lyp_631gd"]                  # the same Os-complex anchor (no 3d metal in it)
    p_fit["21e_lanl2dz_3d"] = p_fit["21e_b3lyp_631gd"]
    uks = [v["uks_s"] / v["rks_s"] for v in pts["21e_b3lyp_631gd"].values()]
    shell = (round(min(uks), 2), round(max(uks), 2))
    r2 = json.loads(RELAX_OS2.read_text(encoding="utf-8"))["complexes"]["dmbpy"]
    r3 = json.loads(RELAX_OS3.read_text(encoding="utf-8"))["complexes"]["dmbpy"]
    relax = {"os2_from_octahedron": round(r2["geometry_os2_relaxed"]["info"]["wall_seconds"] / r2["os2"]["wall_seconds"], 1),
             "os3_from_os2_minimum": round(r3["geometry_os3_relaxed"]["info"]["wall_seconds"] / r3["os3"]["wall_seconds"], 1)}
    rel_lo, rel_hi = min(relax.values()), max(relax.values())
    gas = json.loads(GAS_CACHE.read_text(encoding="utf-8"))["complexes"]["dmbpy"]["os2"]["wall_seconds"]
    pcm = {c["name"]: c for c in json.loads(SERIES_CACHE.read_text(encoding="utf-8"))["complexes"]}["dmbpy"]["os2"]["wall_seconds"]

    rows = {}
    for name, (comp, charge) in MODELS.items():
        n, ne = {}, None
        for tier in TIERS:
            n[tier], ne_t = nao(comp, tier, charge)
            ne = ne_t if tier == "21e_b3lyp_631gd" else ne
        if (name in OPEN_SHELL) != (ne % 2 == 1):
            raise SystemExit(f"{name}: {ne} electrons — the open-shell set and the parity disagree")
        est = {}
        for tier in TIERS:
            a = anchor[tier][1]
            ratio = n[tier] / a["nao"]
            f = shell if name in OPEN_SHELL else (1.0, 1.0)
            ends = sorted(a["rks_s"] * s * ratio ** p / 3600 for s in f for p in (p_fit[tier], P_HIGH))
            est[tier] = {"ratio_to_anchor": round(ratio, 2), "one_scf_h": {"low": round(ends[0], 2), "high": round(ends[-1], 2)},
                         "relaxation_days": {"low": round(ends[0] * rel_lo / 24, 1), "high": round(ends[-1] * rel_hi / 24, 1)}}
        rows[name] = {"composition": comp, "charge": charge, "n_atoms": sum(comp.values()), "n_electrons": ne,
                      "open_shell": name in OPEN_SHELL, "nao": n, "estimate": est}
    from pyscf.dft import libxc
    disp = {"dftd3": bool(importlib.util.find_spec("dftd3")), "dftd4": bool(importlib.util.find_spec("dftd4")),
            "vv10_native_wb97x_v": bool(libxc.nlc_coeff("wb97x-v"))}

    z, pe = rows["Zn_HAp_on_TiO2_16"], rows["PEDOT_PSS_on_TiO2_16"]
    ae, af = anchor["21e_b3lyp_631gd"], anchor["21f_def2tzvp"]
    ze, pee = z["estimate"]["21e_b3lyp_631gd"], pe["estimate"]["21e_b3lyp_631gd"]
    zt = z["estimate"]["21f_def2tzvp"]
    verdict = (
        f"Measured: Zn-HAp (one Zn-substituted cell) on a (TiO2)16 cluster has {z['n_atoms']} atoms and "
        f"{z['nao']['21e_b3lyp_631gd']} basis functions at 21e's tier ({z['nao']['21e_lanl2dz_3d']} with LANL2DZ on the 3d "
        f"metals, {z['nao']['21f_def2tzvp']} at def2-TZVP); PEDOT:PSS as the doped polaron on the same cluster has "
        f"{pe['n_atoms']} atoms, {pe['n_electrons']} electrons (a doublet) and {pe['nao']['21e_b3lyp_631gd']} functions. The "
        f"pipeline's largest routine SCF at 21e's tier is {ae[0]} ({ae[1]['nao']} functions, {ae[1]['rks_s']:.0f} s) and at "
        f"def2-TZVP 21f's {af[0]} ({af[1]['nao']} functions, {af[1]['rks_s'] / 3600:.1f} h Os(II), "
        f"{af[1]['uks_s'] / 3600:.1f} h Os(III)), so the clusters are {ze['ratio_to_anchor']}× and "
        f"{pee['ratio_to_anchor']}× the 21e anchor and about the size of what def2-TZVP already ran. Estimated: the series "
        f"scale as N^{p_fit['21e_b3lyp_631gd']} (21e) and N^{p_fit['21f_def2tzvp']} (ωB97X); extrapolating with p from the "
        f"fit to 3, one 21e-tier SCF of Zn-HAp/TiO2 takes {ze['one_scf_h']['low']:.1f}–{ze['one_scf_h']['high']:.1f} h and a "
        f"relaxation {ze['relaxation_days']['low']:.1f}–{ze['relaxation_days']['high']:.0f} days; PEDOT:PSS (open-shell "
        f"factor {shell[0]}–{shell[1]} from the series' routine UKS/RKS pairs) {pee['one_scf_h']['low']:.1f}–"
        f"{pee['one_scf_h']['high']:.1f} h and {pee['relaxation_days']['low']:.1f}–{pee['relaxation_days']['high']:.0f} days. "
        f"D3/D4 are not installed, but PySCF carries VV10 natively (ωB97X-V-type functionals), so a dispersion-inclusive "
        f"calculation needs no new dependency; at def2-TZVP, the tier such a functional runs at, one SCF of Zn-HAp/TiO2 is "
        f"{zt['one_scf_h']['low']:.0f}–{zt['one_scf_h']['high']:.0f} h and a relaxation {zt['relaxation_days']['low']:.0f}–"
        f"{zt['relaxation_days']['high']:.0f} days (VV10's own grid cost not included). So a cluster relaxation of one adsorbate is within reach of our CPU — days to "
        f"weeks, one job at a time; an adsorption energy is 3 such SCFs (5 with counterpoise). What it cannot settle is "
        f"whether a cluster models the surface: a periodic slab is the usual model, and a cluster study needs its own size "
        f"and termination convergence, which multiplies the jobs.")

    out = {
        "question": "Can the in-silico L3 tier carry cluster models of Zn-HAp and PEDOT:PSS on TiO2 (00_07 HW.40) — basis size "
                    "measured from composition, SCF and relaxation cost estimated from the pipeline's own timed series.",
        "tiers": {k: {"basis": v[0], "ecp": v[1]} for k, v in TIERS.items()},
        "series_points": pts,
        "fit_exponent": p_fit, "upper_exponent_ours": P_HIGH,
        "anchor": {k: {"name": v[0], **v[1]} for k, v in anchor.items()},
        "uks_over_rks_21e_series": list(shell),
        "relaxation_over_scf_21e_dmbpy": relax,
        "gas_over_cpcm_dmbpy_os2": round(gas / pcm, 2),
        "models_ours": "a size ladder, not a validated surface model — compositions and charges in the script",
        "by_model": rows,
        "dispersion_in_env": disp,
        "not_modelled": ["whether a cluster of this size models the surface (cluster-size and termination convergence)",
                         "the SCF cycle count of these systems (taken as the series')",
                         "C-PCM in the series against vacuum for a surface model (gas/C-PCM recorded, not applied)",
                         "basis-set superposition (counterpoise)", "any adsorption energy"],
        "verdict": verdict,
    }
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"  fit p: {p_fit} · anchors: { {k: (v[0], v[1]['nao']) for k, v in anchor.items()} } · UKS/RKS {shell} · "
          f"relax/SCF {relax} · gas/C-PCM {gas / pcm:.2f}")
    for name, r in rows.items():
        e = r["estimate"]["21e_b3lyp_631gd"]
        print(f"  {name:22s} {r['n_atoms']:4d} atoms · {r['n_electrons']} e · nao {r['nao']} · ×{e['ratio_to_anchor']} · "
              f"SCF {e['one_scf_h']['low']}–{e['one_scf_h']['high']} h · relax {e['relaxation_days']['low']}–"
              f"{e['relaxation_days']['high']} d{' (UKS)' if r['open_shell'] else ''}")
    print(f"  dispersion: {disp}\n\n  VERDICT: {verdict}")
    banner(f"✅ saved {OUT_JSON.name} · {time.time() - t0:.0f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
