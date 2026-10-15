#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""61 — Стаття 1 Tables T1–T4, generated from the cache (drift-safe).

Reads cache/dft JSON only — no kinetics cache and no DFT run (`_load` is rooted at
DFT_CACHE; a change to cache/kinetics does NOT require re-running this script) —
asserts the headline numbers against the SUMMARY canon at build time, and writes
paper/06_tables.md. Same discipline as 60_paper_figures.py — re-run after any
upstream DFT-cache change; if a cache drifts from canon the build fails loudly
instead of shipping a wrong table.

Run:  mamba run -n silken_md python tools/in_silico/scripts/61_paper_tables.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, PAPER_DIR, REPO_ROOT

SI_DESCRIPTION = "61 — Paper Tables T1–T4, generated from the cache (drift-safe)."  # its row in the paper SI (72): English, no repo jargon

# Canon values that live in SUMMARY prose (not a single cache field) — kept here as
# explicit constants WITH a source note, and cross-checked against cache where one exists.
B3LYP_CORRECTED_WITHDRAWN = -0.07     # SUMMARY: tuned to the wrong −0.14 → withdrawn, do NOT cite
EXP_VERIFIED_EV = -0.574             # E°(Os)+309 − E°(FAD-GDH)−265 mV SHE (Zafar 2012 + Schachinger 2023)


def _load(name: str) -> dict:
    p = DFT_CACHE / name
    if not p.exists():
        sys.exit(f"missing cache {p}")
    return json.loads(p.read_text())


def _close(a: float, b: float, tol: float, what: str) -> None:
    if abs(a - b) > tol:
        sys.exit(f"CANON DRIFT [{what}]: cache {a:.4f} vs canon {b:.4f} (tol {tol})")


def build() -> str:
    """The whole 06_tables.md, rendered from the caches — `main` writes it, and
    `test_doc_cache_sync` compares it with the committed file (a generator no CI ran
    lay broken three days after a cache-schema change, and the table was hand-edited)."""
    series = _load("os_mediator_series.json")
    series_wb = _load("os_mediator_series_wb97x.json")   # 21e `wb97x` — the ω−B3 column of Table 4
    # 83 — which Table 4 neighbours relaxation leaves undecided (the SO₂CF₃ clause, ⚖️ founder 2026-10-15)
    acceptors = _load("os_series_vs_measured.json")["relaxed_geometry_check"]["acceptors"]
    zif = _load("zif_hopping.json")
    fodft = _load("fodft_coupling.json")
    ket = _load("cathode_ket_lambda.json")
    dscf = _load("delta_scf_corrections.json")
    wb = _load("os_complex_wb97xd.json")           # plain — FADH₂ ωB97X HOMO (FAD unchanged)
    wb_dm = _load("os_complex_wb97xd_dmbpy.json")   # dimethyl Os (B1) — the real mediator
    koop_dm = abs(wb["fadh2_red"]["HOMO_eV"] - wb_dm["os3_plus"]["LUMO_eV"])  # ωB97X Koopmans, dimethyl

    # ── drift asserts vs SUMMARY canon ──
    _close(dscf["dG_vertical_eV"], 1.395, 0.01, "T2 ΔSCF vertical (dimethyl)")
    _close(dscf["dG_adiabatic_eV"], 1.0335, 0.01, "T2 ΔSCF adiabatic (dimethyl)")
    _close(koop_dm, 6.020, 0.01, "T2 Koopmans ωB97X (dimethyl)")
    _close(zif["pairs"][0]["t_ij_eV"], 0.00128, 1e-4, "T3 Cu-Co ΔSCF t_ij")
    _close(fodft["t_ij_eV"], 0.005462, 1e-4, "T3 Cu-Co FO-DFT t_ij")
    # 505a1fac4 (2026-09-21) split the single margin into a bracket, and 2026-09-24 added the λ(Cu)
    # reading as its second axis — the asserts follow the fields that now carry each number.
    # ⊕ 2026-10-15 (self-review cluster 8): the table runs on the FO-DFT coupling — the old crude-t values (×1.385 ·
    # ×0.00448) now sit under `scenarios_crude_dscf`, and the computed-λ(Co) row carries the verdict's other end.
    _close(ket["scenarios"]["literature λ"]["margin_vs_turnover_at_dG0"], 25.165, 0.1, "T3 lit-λ margin (ΔG=0)")
    _close(ket["scenarios"]["literature λ"]["margin_vs_turnover_adverse"], 0.081, 0.002, "T3 lit-λ adverse corner")
    _close(ket["scenarios"]["computed λ (B3LYP)"]["margin_vs_turnover_at_dG0"], 0.00542, 0.0002,
           "T3 computed-λ margin (ΔG=0)")
    names = [c["name"] for c in series["complexes"]]
    _close(series["complexes"][names.index("bpy")]["cascade_delta_eV"], -0.9093, 0.005, "T4 H cascade")
    _close(series["complexes"][names.index("so2cf3")]["cascade_delta_eV"], -0.2269, 0.005, "T4 SO₂CF₃ cascade")

    md: list[str] = []
    md.append("# Tables — Стаття 1 (EBFC quantum chemistry)\n")
    md.append("> **Generated** by [`tools/in_silico/scripts/61_paper_tables.py`]"
              "(../../../../tools/in_silico/scripts/61_paper_tables.py) from the result caches "
              "(drift-safe: every headline number is asserted against [`SUMMARY.md`](../SUMMARY.md) at "
              "build). **Do not hand-edit** — change SUMMARY/the cache and re-run. "
              "Re-run: `mamba run -n silken_md python tools/in_silico/scripts/61_paper_tables.py`.\n")

    # ── Table 1 — levels of theory ──
    md.append("## Table 1. Levels of theory\n")
    md.append("| Tier | Functional | Basis / ECP | Solvent | Used for |")
    md.append("|---|---|---|---|---|")
    md.append("| Screening | B3LYP | 6-31G(d); LANL2DZ (Os, Cu, Co); stuttgart_rsc (Ce) | C-PCM (water) | frontier orbitals, ΔSCF redox, mediator series (①), speciation (②) |")
    md.append("| Publication — cascade | ωB97X (FAD geometries B3LYP/def2-SVP) | def2-TZVP; LANL2DZ (Os) | C-PCM (water) | adiabatic ΔSCF cross-check |")
    md.append("| Publication — speciation | ωB97X | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | speciation functional-robustness (②) |")
    md.append("| PCET | B3LYP/6-31G(d) + thermodynamic proton reference (Isse–Gennaro) | — | PCM | FAD E°; semiquinone cascade |")
    md.append("| Reorganisation λ | B3LYP/def2-SVP (29b), 6-31G(d)+LANL2DZ/stuttgart_rsc (35); Nelsen 4-point | C-PCM | inner-sphere λ_i; + Marcus two-sphere outer-sphere λ_o (29c, analytical) |")
    md.append("| DET coupling | ΔSCF-UKS energy-splitting (24); two-state orbital diabatisation, FO-DFT label (24b) | none (gas phase) | ZIF inter-metal t_ij |")
    md.append("\n*Reproducibility: scripted, fixed-seed DFT in `tools/in_silico`; every DFT cache behind these tables computed with PySCF 2.11.0 "
              "(the recorded environment — §2.7; the lock re-runs are separate records, SI S3).*\n")

    # ── Table 2 — cascade energetics, all methods ──
    koop = koop_dm
    md.append("## Table 2. Anode→mediator cascade ΔG per electron, all methods\n")
    md.append("| Method | ΔG/e⁻ (eV) | Direction | vs verified −0.574 eV |")
    md.append("|---|---|---|---|")
    md.append(f"| Koopmans ωB97X (orbital offset) | +{koop:.3f} | uphill | range-separation artefact — *never use* |")
    md.append(f"| ΔSCF ωB97X (vertical) | +{dscf['dG_vertical_eV']:.3f} | uphill | +{dscf['dG_vertical_eV'] - EXP_VERIFIED_EV:.2f} |")
    md.append(f"| **ΔSCF ωB97X (adiabatic)** | **+{dscf['dG_adiabatic_eV']:.3f}** | uphill | +{dscf['dG_adiabatic_eV'] - EXP_VERIFIED_EV:.2f} |")
    md.append(f"| B3LYP Koopmans «corrected» | {B3LYP_CORRECTED_WITHDRAWN:+.2f} | — | **withdrawn** (tuned to the wrong −0.14) |")
    md.append(f"| **Experiment (verified E°s)** | **{EXP_VERIFIED_EV:+.2f}** | **downhill** | reference |")
    md.append("\n*The raw uphill ΔG is the implicit-solvation method limit (differential PCM solvation, "
              "chloro↔bis-Im bracket + the 4,4′-dimethyl substituent, Fig 5 / ②); the verified +574 mV / "
              "−0.574 eV is E°(Os) +309 − E°(FAD-GDH) −265 mV vs SHE.*\n")

    # ── Table 3 — DET hops + reorganization energies (cathode) ──
    p = {x["label"].split()[0]: x for x in zif["pairs"]}   # "Cu-Co"/"Co-Ce"/"Ce-graphene"
    lam_lit, lam_comp = ket["lambda_lit_eV"], ket["lambda_computed_eV"]
    cu_read = ket["lambda_cu_readings_eV"]                  # λ(Cu) is a bracket of named readings
    cu_lo, cu_hi = min(cu_read.values()), max(cu_read.values())

    def _hop_band(other: float) -> str:
        """λ_hop(Cu–X) over the λ(Cu) readings — a band, because λ(Cu) is one."""
        return f"{(cu_lo + other) / 2:.2f}–{(cu_hi + other) / 2:.2f}"

    md.append("## Table 3. Cathode DET hops, couplings and reorganisation energies\n")
    # Self-review round 1, cluster 8: the coupling the margins use is printed as such, and the crude ΔSCF one beside it
    # with its resolution — two unconstrained SCF solutions whose difference is read against their tolerance.
    res = {k.split()[0]: v["delta_E_over_scf_tol"] for k, v in ket["dscf_coupling_resolution"]["pairs"].items()}
    md.append("| Hop | t_ij used (eV) | crude ΔSCF t_ij (eV) | crude ΔE ÷ SCF tolerance | λ_hop lit (eV) | λ_hop computed (eV) |")
    md.append("|---|---|---|---|---|---|")
    md.append(f"| **Cu–Co** (T1↔node, bottleneck) | **{fodft['t_ij_eV']:.5f}** (FO-DFT) | {p['Cu-Co']['t_ij_eV']:.5f} | {res['Cu-Co']:.1f} | {_hop_band(lam_lit['Co'])} | {_hop_band(lam_comp['Co'])} |")
    md.append(f"| Co–Ce (node↔vacancy) | {p['Co-Ce']['t_ij_eV']:.5f} (crude) | {p['Co-Ce']['t_ij_eV']:.5f} | {res['Co-Ce']:.0f} | {(lam_lit['Co']+lam_lit['Ce'])/2:.2f} | {(lam_comp['Co']+lam_comp['Ce'])/2:.2f} |")
    md.append(f"| Ce–graphene (vacancy↔MWCNT) | {p['Ce-graphene']['t_ij_eV']:.5f} (crude) | {p['Ce-graphene']['t_ij_eV']:.5f} | {res['Ce-graphene']:.0f} | — | — |")
    md.append("\n**Cu–Co bottleneck margin vs enzymatic turnover (10³ s⁻¹), by λ scenario, on the FO-DFT coupling** — "
              "each a bracket over the sign of the computed site-energy gap and the λ(Cu) reading; the consumer "
              "reading is the ADVERSE corner:\n")
    md.append("| λ scenario | adverse corner | ΔG = 0 (default, not a measurement) | favourable corner |")
    md.append("|---|---|---|---|")
    sc = ket["scenarios"]

    def _row(label: str, s: dict, bold: bool = False) -> str:
        a, z, f = (s["margin_vs_turnover_adverse"], s["margin_vs_turnover_at_dG0"],
                   s["margin_vs_turnover_favourable"])
        cell = (lambda v: f"**×{v:.2g}**") if bold else (lambda v: f"×{v:.2g}")
        return f"| {label} | {cell(a)} | ×{z:.2g} | ×{f:.2g} |"

    md.append(_row("canon λ=0.7 (old, withdrawn)", sc["canon λ=0.7 (old assumption)"]))
    md.append(_row(f"**literature λ** (Cu {cu_lo:.1f}–{cu_hi:.1f} / Co {lam_lit['Co']:.1f}, assumed / Ce {lam_lit['Ce']:.1f})",
                   sc["literature λ"], bold=True))
    md.append(_row(f"**computed λ** (B3LYP: Co {lam_comp['Co']:.2f}; Cu literature)", sc["computed λ (B3LYP)"], bold=True))
    ru_half = ket["ru_lambda_nelsen_halves"]
    md.append(_row(f"Ru-swap (Co→Ru, computed λ {lam_comp['Ru']:.2f}) — *indicative: λ(Ru) sums Nelsen halves "
                   f"{ru_half['lambda_1_eV']:+.2f} and {ru_half['lambda_2_eV']:+.2f} eV; the Cu–Ru coupling and gap are not "
                   "obtainable from the minimal cluster, so it borrows the Cu–Co coupling and every column is ΔG = 0*",
                   sc["Ru-swap (Co→Ru, computed)"]))
    md.append(_row("crude ΔSCF coupling, literature λ — *superseded record*", ket["scenarios_crude_dscf"]["literature λ"]))
    lit, comp = sc["literature λ"], sc["computed λ (B3LYP)"]
    co = ket["cobalt_lambda_condition"]
    co_dg0 = co["lambda_co_at_turnover_eV"][f"fodft|{ket['lambda_cu_base_reading']}|dG=0"]
    md.append("\n*Inner-sphere λ via Nelsen 4-point (35) on [Co(NH₃)₆] for Co and on [M(H₂O)₆] for Ce and Ru; λ(Cu) is a "
              f"literature bracket of two solution readings — {cu_lo:.1f} eV (textbook value, source not "
              f"found) and {cu_hi:.1f} eV (Cu(phen)₂²⁺/⁺ self-exchange, Gray & Winkler) — a Cu(I) d¹⁰ "
              "hexa-aqua optimisation being unphysical, so λ_hop(Cu–Co) is half computed and half cited. "
              "Both readings are unconstrained solution couples; a framework-held Cu–N₄ site can lie below "
              "both (0.7 eV in azurin, same source), so the favourable corner is no floor. The adverse corner is "
              "the uphill gap sign at the higher λ(Cu). The crude ΔSCF couplings are half the energy difference of "
              "two unconstrained SCF solutions from one start; for Cu–Co that difference is a single-digit multiple "
              "of the SCF tolerance, so the margins use the two-state diabatisation (FO-DFT label, Methods §2.5). "
              f"The verdict is conditional on λ(Co): turnover needs λ(Co) ≲ {co_dg0:.1f} eV at ΔG = 0 on the "
              f"{cu_lo:.1f} eV λ(Cu) reading and ≲ {co['lambda_co_at_turnover_adverse_corner_eV']:.1f} eV at the adverse corner; "
              f"the computed {lam_comp['Co']:.2f} eV puts the cathode {'below' if comp['margin_vs_turnover_favourable'] < 1 else 'across'} "
              f"turnover at every corner, the assumed {lam_lit['Co']:.1f} eV (no primary) "
              + ("across it" if lit["margin_vs_turnover_adverse"] < 1.0 <= lit["margin_vs_turnover_favourable"] else "on one side of it")
              + ".*\n")

    # ── Table 4 — mediator structure–activity series ──
    md.append("## Table 4. Osmium mediator series — E° and cascade-Δ vs Hammett σ (①)\n")
    md.append("cis-[Os(4,4′-X-bpy)₂(1-MeIm)Cl]⁺/²⁺ at constant charge; B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF; "
              "last column — the same ΔSCF at ωB97X/def2-TZVP on the same geometry, minus the B3LYP value.\n")
    md.append("| 4,4′-X | σ_para | ΔE_red(III→II) (eV) | Os(III) LUMO (eV) | cascade Δ (eV) | note | ω−B3 (eV) |")
    md.append("|---|---|---|---|---|---|---|")
    lbl = {"nme2": "NMe₂", "nh2": "NH₂", "ome": "OMe", "dmbpy": "Me", "bpy": "H",
           "cl": "Cl", "dcbpy": "COOH", "cf3": "CF₃", "no2": "NO₂", "so2cf3": "SO₂CF₃"}
    # ⚖️ founder 2026-10-15: SO₂CF₃ is not relaxed, so it is not printed as the optimum (PIPELINE_STATUS, note under D)
    note = {"nme2": "donor saturation", "bpy": "reference", "cf3": "inert option",
            "no2": "unstable on cycling", "so2cf3": "inert; order vs NO₂ open"}
    vs = series_wb["vs_b3lyp"]
    omega = {p["name"]: p["omega_minus_b3_eV"] for p in vs["points"]}
    for c in sorted(series["complexes"], key=lambda x: x["sigma_para"]):
        n = c["name"]
        om = f"{omega[n]:+.3f}" if n in omega else "—"
        md.append(f"| {lbl.get(n, n)} | {c['sigma_para']:+.2f} | {c['dE_red_eV']:.3f} | "
                  f"{c['os3']['LUMO_eV']:.3f} | {c['cascade_delta_eV']:.4f} | {note.get(n, '')} | {om} |")
    lf_slope = series["lfer"]["slope_eV_per_sigma"]
    sub = ", ".join(lbl[n] for n in vs["common_fit_subset"])
    cs = vs["centre_decomposition"]["local_slope_eV_per_sigma"]
    # every clause from the cache (in-silico §When Modifying #5): the acceptor and the ends sentences were typed once
    # and turned false when SO₂CF₃ and the small-basis ends landed (2026-10-11)
    sigma = {c["name"]: c["sigma_para"] for c in series["complexes"]}
    fit_acceptors = [n for n in vs["common_fit_subset"] if sigma[n] > 0]
    extra = [p for p in vs["points"] if p["sigma_para"] > 0 and p["name"] not in vs["common_fit_subset"]]
    def m(x: float, spec: str) -> str:   # the table's minus sign, not a hyphen
        return f"{x:{spec}}".replace("-", "−")
    acceptor = ((f"resting on the {'one acceptor point' if len(fit_acceptors) == 1 else 'acceptor points'} of that set, "
                 f"{', '.join(lbl[n] for n in fit_acceptors)}" if fit_acceptors else "with no acceptor point in that set")
                + (f"; outside the fit, {', '.join(lbl[p['name']] for p in extra)} "
                   f"{'carries' if len(extra) == 1 else 'carry'} ω−B3 "
                   + ", ".join(f"{p['omega_minus_b3_eV']:+.3f}" for p in extra) if extra else ""))
    es = vs["ends_decomposition"]["slope_over_common_subset_by_tier"]
    ends = (f"with ωB97X also at 6-31G(d) on every point of {sub}, the slope runs {m(es['b3lyp_631gd'], '.3f')} → "
            f"{m(es['wb97x_631gd'], '.3f')} → {m(es['wb97x_def2tzvp'], '.3f')} eV/σ — functional ×"
            f"{es['wb97x_631gd'] / es['b3lyp_631gd']:.2f}, basis ×{es['wb97x_def2tzvp'] / es['wb97x_631gd']:.2f}"
            if es else "at the ends the two are not separated")
    by_sigma = sorted(series["complexes"], key=lambda x: x["sigma_para"])
    ends_casc = (by_sigma[0], by_sigma[-1])
    # A half-relaxed pair is OPEN when its relaxed member moved by at least the gap — then relaxing the other could
    # reverse it; the cache's own `close` flag (gap < 100 meV) is a different gate and would hide a far pair a big move
    # reaches. A pair the cache already found reversed is printed as reversed (adversary on d11c3b0ec, 2026-10-15).
    open_pairs = [(k, v) for k, v in acceptors["table4_neighbours_half_relaxed"].items()
                  if max(abs(x) for x in v["relaxed_member_cascade_move_meV"].values())
                  >= abs(v["programmatic_koopmans_gap_meV"])]
    flipped = acceptors["verdict_condition"]["neighbour_order_flipped"]
    def pair_clause(k: str, v: dict) -> str:
        lo, hi = k.split("-")
        mv = v["relaxed_member_cascade_move_meV"]
        rel = v["relaxed_member"]
        other = hi if rel == lo else lo
        return (f"the order of {lbl[lo]}→{lbl[hi]} ({m(v['programmatic_koopmans_gap_meV'], '+.1f')} meV) is not "
                f"decided — relaxing {lbl[rel]} alone moves {lbl[rel]}'s own cascade Δ by "
                f"{m(mv['os3_on_own_minimum'], '+.0f')} meV with Os(III) on its own minimum and "
                f"{m(mv['os3_on_os2_minimum'], '+.0f')} meV with Os(III) vertical, and {lbl[other]} was not relaxed")
    undecided = "".join("; " + pair_clause(k, v) for k, v in open_pairs)
    if flipped:
        undecided += ("; relaxing both members reverses " + ", ".join("→".join(lbl[x] for x in f.split("-")) for f in flipped))
    md.append(f"\n*Design rule: cascade Δ rises with σ ({m(ends_casc[0]['cascade_delta_eV'], '.2f')} "
              f"{lbl[ends_casc[0]['name']]} → {m(ends_casc[1]['cascade_delta_eV'], '.2f')} "
              f"{lbl[ends_casc[1]['name']]}){undecided}; ΔE_red "
              f"LFER slope ≈ −{abs(lf_slope):.2f} eV/σ over OMe→NO₂ (Fig 3b). Higher E°(Os) lowers OCV, so "
              f"the cell optimum (~+309 mV) balances driving force vs overpotential. ωB97X/def2-TZVP cross-check: "
              f"over {sub} the slope is {m(vs['slope_wb97x_eV_per_sigma'], '.2f')} against "
              f"{m(vs['slope_b3lyp_eV_per_sigma'], '.2f')} eV/σ at B3LYP (×{vs['slope_ratio_wb97x_over_b3lyp']:.2f}, "
              f"{acceptor}); at Me/H, where ωB97X also exists with 6-31G(d), the local slope runs "
              f"{m(cs['b3lyp_631gd'], '.3f')} → {m(cs['wb97x_631gd'], '.3f')} → {m(cs['wb97x_def2tzvp'], '.3f')} eV/σ, i.e. the "
              f"functional and the basis change pull "
              f"{'opposite ways' if vs['centre_functional_and_basis_pull_opposite_ways'] else 'the same way'}; "
              f"{ends}.*\n")

    return "\n".join(md) + "\n"


def main() -> int:
    out = PAPER_DIR / "06_tables.md"
    out.write_text(build())
    print(f"  ✓ wrote {out.relative_to(REPO_ROOT)} (T1–T4)")
    print("Done — all canon cross-checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
