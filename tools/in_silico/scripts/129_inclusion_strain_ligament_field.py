#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""129 — the gyroid's ligament field under the inclusion's OWN multiaxial strain, against `105`'s uniaxial-state reading
(00_07 HW.23, the leg «поле перемичок під БАГАТОВІСНОЮ деформацією включення», step 3 of 3).

WHY. `105` reads the ligament peak from the periodic voxel case under a unit UNIAXIAL macro stress across the anchor's axis
and multiplies it by the share t_L = 1 — but the bonded gyroid in the wood is strained multiaxially (01_01 §5.2, ceiling
(4)): `106`'s Eshelby inclusion takes the far field along the stem and returns a full strain ε_I, whose L component is
t_L and whose other components (across, along the anchor's axis, shear off the cube axis) the uniaxial reading does not
carry. This script reads the ligament field under each cell's own ε_I.

CHAIN. `106` exports ε_I per cell (Scots pine readings × alloys × fills), per unit far-field ε_L, in the lattice's cube frame,
on the material-tensor form of each rung of the part's density at `105`'s three sampled angles
(`cache/mechanical/gyroid_inclusion_strain_cases.json`); `fea --periodic --strain-cases` superposes the six unit solutions of
the same rung under each ε_I (tools/cad `cache/fea/periodic_strain_fields.*`): σ_W under that strain and the peak's
quantiles over σ_W in two measures. So the peak per unit far-field ε_L is q·σ_W (units of E_s), and the stem's surface
strain above which it reaches σ_e/S is lim / (q·σ_W·r/R), lim = `105`'s endurance strain over S — the same arithmetic as
`105`'s uniaxial reading, with q·σ_W in place of k_p·√(E*/φ)·t_L (`105` at t_L = 1).

RULES (`105`'s and `106`'s, unchanged): two measures (max|σ_i| ⊥ von Mises) and two quantiles (p99 ⊥ p99.9) are NAMED
readings; a binding claim takes the LOWEST peak over rungs × measures, i.e. the HIGHEST threshold, over the modelled cells
of the alloy, and over θ when the install angle is free (three sampled angles — not a ceiling over every angle); rounded
UP (`up0`). ⚠️ Only the EMPTY-PORE fill (pores carry nothing) puts the strain and the field on ONE body — the field is read
on the empty-pore lattice — so it is the binding scope; the two filled fills (additive host sapwood · the Voigt phase
bound on an isotropic mix) build ε_I on a body the field does not have, and the direction of that error is not bounded (a
filler pushes the lattice toward affine strain, raising σ_W at a fixed strain, while the peak ratio may fall): they are
printed beside it as readings, never the headline.
WHAT IT ADDS over `105`: per cell the factor R = peak(ε_I) / (t_L · `105`'s uniaxial peak on the same rung, angle and
measure) — the share's part divided out, what is left is the off-L components' effect on the peak (R > 1 raises it).

CONTROLS (CAN / CANNOT): the C# strain-field output's tensor C equals the committed ladder's on every rung (another solve, a
moved geometry or ν — not a wrong solve shared by both); the rung tensor the exporter built ε_I on (its cases file) equals
the ladder's (a ladder re-solved without re-running `106`); σ_W² = εᵀ·C·ε / φ on every case (σ_W rescaled, per another strain or φ —
not a wrong field, the identity holds on any converged one); every case's strain in the C# output equals the exported one
(a stale or another cases file); the cases cover exactly the rungs of the part's density and `105`'s angles.

CAN: per alloy, depth reference, quantile and SF line, the binding surface strain under the inclusion's own strain (θ = 0 and
θ free, all fills ⊥ lattice fills), the same with max|σ_i| alone, its ratio to `105`'s uniaxial reading at t_L = 1, the share
and cell that bind, and whether the source day reaches it on a large stem at SF 2.
CANNOT: (1) the pores' tissue in the FIELD (the field is read on the empty-pore lattice; the tissue enters ε_I only);
(2) the other two C44 forms of `106` (part body, absolute ⊥ Zener) — their strain is on another body than the field's;
(3) the junction (gyroid ⊥ shank), the finite part's rim, any K_t of a smooth ligament (01_01 §5.2 ceiling (3)); (4) the
green-wood group (Scots pine readings only); (5) a ceiling over every install angle (three sampled); (6) ε_RR is the far
field's (`106`'s infinite cylinder, its CANNOT (4)), not scaled by the inclusion's stiffness.

Run:  conda activate silken_md
      python tools/in_silico/scripts/129_inclusion_strain_ligament_field.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import ALLOY_BASELINE, CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("The gyroid lattice's ligament stress field under the inclusion's own multiaxial strain in the wood (an "
                  "Eshelby inclusion per wood reading, alloy and pore fill), read from periodic voxel finite-element "
                  "solutions superposed under each strain, and the stem surface strain above which the ligament peak "
                  "reaches the endurance line — beside the uniaxial-stress reading of script 105.")

MECH = CACHE_DIR / "mechanical"
FEA_DIR = REPO_ROOT / "tools/cad/cache/fea"
STRAIN_FIELDS = FEA_DIR / "periodic_strain_fields.network.w100.c1.json"
LADDER = FEA_DIR / "periodic_homogenization.network.w100.c1.json"
CASES = MECH / "gyroid_inclusion_strain_cases.json"
OUT = MECH / "inclusion_strain_ligament_field.json"
MEASURES = {"max_principal": "principal_over_sigma_w", "von_mises": "von_mises_over_sigma_w"}
QUANTILES = ("p99", "p99.9")
LATTICE_FILLS = ("pores_carry_nothing", "pores_additive_host_sapwood")


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


s106 = _load("s106_129", "106_gyroid_wood_strain_share.py")


def up0(x: float) -> float:
    return float(math.ceil(round(x, 9)))


def parse_label(lb: str) -> tuple[str, str, str, float, int]:
    al, rh, rd, fill, th, st = lb.split("|")
    return al, f"{rh}|{rd}", fill, float(th[2:]), int(st[1:])


def main() -> int:
    banner("129 — the ligament field under the inclusion's own strain, against 105's uniaxial reading")
    d105 = json.loads((MECH / "printed_part_sway_stress.json").read_text(encoding="utf-8"))
    sf = json.loads(STRAIN_FIELDS.read_text(encoding="utf-8"))
    lad = json.loads(LADDER.read_text(encoding="utf-8"))
    cases_doc = json.loads(CASES.read_text(encoding="utf-8"))
    cases = cases_doc["cases"]
    phi = 1.0 - d105["inputs"]["fea_rows_used"]["finest_unlocked"]["porosity"]
    nu_s = lad["poisson_ratio"]                    # the ladder's solid; periodic_rungs holds the strain file to it
    rungs = s106.periodic_rungs(sf, phi, nu_s)
    by_steps = {r["steps_per_period"]: r for r in lad["rows"]}
    rung_t = cases_doc["rung_tensors"]
    controls_rung = max(abs(rung_t[str(st)][k] - by_steps[st][k]) for st in s106.PERIODIC_RUNGS for k in ("C11", "C12", "C44"))
    controls_rung = max(controls_rung, max(abs(rung_t[str(st)]["solid_fraction"] - by_steps[st]["solid_fraction_meshed"])
                                           for st in s106.PERIODIC_RUNGS))
    assert controls_rung < 1e-12, f"106 built ε_I on another rung tensor than the ladder's ({controls_rung}) — re-run 106"

    controls = {"C_vs_ladder_worst": 0.0, "sigma_w_identity_worst": 0.0, "strain_vs_export_worst": 0.0,
                "exporter_rung_tensor_vs_ladder_worst": controls_rung}
    want = {c["label"]: c for c in cases}
    seen = set()
    cells = {}
    for r in rungs:
        st = r["steps_per_period"]
        c_mat = np.array(r["C"])
        controls["C_vs_ladder_worst"] = max(controls["C_vs_ladder_worst"],
                                            float(np.abs(c_mat - np.array(by_steps[st]["C"])).max()))
        ph = r["solid_fraction_meshed"]
        for f in r["strain_fields"]:
            lb = f["label"]
            al, wk, fill, th, cst = parse_label(lb)
            assert cst == st, f"case {lb} read on rung {st}"
            eps = np.array(f["strain"])
            controls["strain_vs_export_worst"] = max(controls["strain_vs_export_worst"],
                                                     float(np.abs(eps - np.array(want[lb]["strain"])).max()))
            e_energy = float(eps @ c_mat @ eps)
            controls["sigma_w_identity_worst"] = max(controls["sigma_w_identity_worst"],
                                                     abs(f["sigma_w"] ** 2 / (e_energy / ph) - 1.0))
            peak = {q: {m: f[key][q] * f["sigma_w"] for m, key in MEASURES.items()} for q in QUANTILES}
            cells[lb] = {"alloy": al, "wood": wk, "fill": fill, "theta_deg": th, "rung": st, "t_L": want[lb]["t_L"],
                         "sigma_w_per_unit_eps_L": f["sigma_w"], "peak_per_unit_eps_L": peak}
            seen.add(lb)
    assert controls["C_vs_ladder_worst"] < 1e-12, f"the strain-case solves are not the ladder's: {controls['C_vs_ladder_worst']}"
    assert controls["sigma_w_identity_worst"] < 1e-6, f"σ_W² ≠ εᵀCε/φ: {controls['sigma_w_identity_worst']}"
    assert controls["strain_vs_export_worst"] < 1e-12, "the C# cases are not the exported ones — re-run fea --periodic"
    assert seen == set(want), f"{len(set(want) - seen)} exported cases have no field — re-run fea --periodic --strain-cases"
    thetas = sorted({c["theta_deg"] for c in cells.values()})
    assert thetas == [0.0, 22.5, 45.0], f"the sampled angles moved: {thetas}"
    assert sorted({c["rung"] for c in cells.values()}) == list(s106.PERIODIC_RUNGS), "the cases do not cover the rungs"

    ulr = d105["gyroid_ligament_field_uniaxial_reading"]
    uni, ufield = ulr["binds_above_surface_strain_ue"], ulr["field"]
    for c in cells.values():                       # R per measure and quantile against 105 on the same rung · angle · measure
        u = ufield[f"{c['theta_deg']:g}"]
        c["multiaxial_factor"] = {q: {m: c["peak_per_unit_eps_L"][q][m]
                                      / (c["t_L"] * u[q]["by_rung"][str(c["rung"])]["peak_per_E_s_strain"][m])
                                      for m in MEASURES} for q in QUANTILES}
    depth = d105["inputs"]["depth_fraction"]
    scopes = {"empty_pores": ("pores_carry_nothing",), "filled_additive": ("pores_additive_host_sapwood",),
              "filled_voigt_bound": ("pores_voigt_phase_bound",),
              "all_fills": ("pores_carry_nothing", "pores_additive_host_sapwood", "pores_voigt_phase_bound")}
    out_al = {}
    for al, row in d105["alloys"].items():
        out_al[al] = {}
        mine = [c for c in cells.values() if c["alloy"] == al]
        for dk, frac in depth.items():
            for sfl in (1.0, 2.0):
                lim = row["endurance_strain_printed_ue"] / sfl
                for q in QUANTILES:
                    key = f"{dk}|{q}|sf{sfl:g}"

                    def thr(c, measures=tuple(MEASURES), q=q, lim=lim, frac=frac):
                        return lim / (min(c["peak_per_unit_eps_L"][q][m] for m in measures) * frac)

                    res = {}
                    for scope, fills in scopes.items():
                        pool = [c for c in mine if c["fill"] in fills]
                        at0 = max((c for c in pool if c["theta_deg"] == 0.0), key=thr)
                        free = max(pool, key=thr)
                        prin = max(pool, key=lambda c: thr(c, ("max_principal",)))
                        rs = [c["multiaxial_factor"][q][m] for c in pool for m in MEASURES]
                        res[scope] = {"binds_above_theta0_ue": up0(thr(at0)), "theta0_cell": f"{at0['wood']}|s{at0['rung']}",
                                      "binds_above_theta_free_ue": up0(thr(free)),
                                      "theta_free_cell": f"{free['wood']}|{free['fill']}|th{free['theta_deg']:g}|s{free['rung']}",
                                      "theta_free_t_L": free["t_L"],
                                      "theta_free_multiaxial_factor": free["multiaxial_factor"][q],
                                      "binds_above_max_principal_only_ue": up0(thr(prin, ("max_principal",))),
                                      "multiaxial_factor_range": [min(rs), max(rs)]}
                    u = uni[al][key]
                    res["uniaxial_105_t_L_1"] = {"theta0_ue": u["0"], "any_sampled_angle_ue": u["any_sampled_angle"]}
                    out_al[al][key] = res

    src = {}
    for rd, rv in d105["inputs"]["stem_readings_87"].items():
        eps = rv["surface_strain_ue"]
        src[rd] = {"surface_strain_ue": eps,
                   "by_alloy": {al: {q: {sc: eps > out_al[al][f"large_stem_limit|{q}|sf2"][sc]["binds_above_theta_free_ue"]
                                         for sc in scopes} for q in QUANTILES} for al in out_al}}

    k0 = "large_stem_limit|p99|sf2"
    b = out_al[ALLOY_BASELINE][k0]
    e = b["empty_pores"]
    rf = e["theta_free_multiaxial_factor"]

    def who(rd: str, q: str, sc: str) -> str:
        xs = [al for al in out_al if src[rd]["by_alloy"][al][q][sc]]
        return ", ".join(xs) if xs else "no alloy"
    verdict = (
        f"Under the inclusion's own multiaxial strain (106's Eshelby ε_I per cell, the material-tensor form of each rung, 105's "
        f"three angles), on the empty-pore fill — the one where the strain and the field are one body — the ligament peak on a "
        f"large stem at SF 2 (p99) binds above a surface strain of {e['binds_above_theta_free_ue']:.0f} µε for {ALLOY_BASELINE} "
        f"with the install angle free ({e['theta_free_cell']}, t_L {e['theta_free_t_L']:.3f}; the off-L components change the peak "
        f"×{min(rf.values()):.2f} to ×{max(rf.values()):.2f} over the share's part there, over the fill's cells ×"
        f"{e['multiaxial_factor_range'][0]:.2f} to ×{e['multiaxial_factor_range'][1]:.2f}) and at θ = 0 above "
        f"{e['binds_above_theta0_ue']:.0f} µε, where the cube takes more than the wood (t_L > 1); 105's uniaxial reading at t_L = 1 "
        f"gives {b['uniaxial_105_t_L_1']['any_sampled_angle_ue']:.0f} µε with the angle free and {b['uniaxial_105_t_L_1']['theta0_ue']:.0f} "
        f"µε at θ = 0. On the filled fills, whose "
        f"field is not their own (direction of the error not bounded), the figure reads {b['filled_additive']['binds_above_theta_free_ue']:.0f} "
        f"µε (additive) and {b['filled_voigt_bound']['binds_above_theta_free_ue']:.0f} µε (Voigt bound). The source day on a large stem "
        f"at SF 2 against the empty-pore threshold: the median ({src['median']['surface_strain_ue']:.0f} µε) reaches it for "
        f"{who('median', 'p99', 'empty_pores')} at p99 and {who('median', 'p99.9', 'empty_pores')} at p99.9; the upper whisker "
        f"({src['upper_whisker']['surface_strain_ue']:.0f} µε) for {who('upper_whisker', 'p99', 'empty_pores')} at p99 and "
        f"{who('upper_whisker', 'p99.9', 'empty_pores')} at p99.9.")
    print(verdict)
    OUT.write_text(json.dumps({
        "script": "129_inclusion_strain_ligament_field.py",
        "question": "the ligament field under the inclusion's own multiaxial strain (00_07 HW.23, ceiling (4) of 01_01 §5.2)",
        "sources": {"strain_fields": str(STRAIN_FIELDS.relative_to(REPO_ROOT)), "ladder": str(LADDER.relative_to(REPO_ROOT)),
                    "cases": str(CASES.relative_to(REPO_ROOT))},
        "rules": {"measures": list(MEASURES), "quantiles": list(QUANTILES),
                  "binding": "lowest peak over rungs × measures → highest threshold over the alloy's cells (and θ if free); up0"},
        "alloys": out_al, "source_day_large_stem_sf2": src, "controls": controls,
        "not_computed": ["tissue in the field", "the part-body C44 forms", "the junction / rim / K_t", "green wood", "every angle"],
        "verdict": verdict}, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"→ {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
