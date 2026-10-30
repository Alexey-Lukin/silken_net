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
from lib.constants import DFT_CACHE, HARTREE_TO_EV, NERNST_SLOPE_V, PAPER_DIR, REPO_ROOT

SI_DESCRIPTION = "61 — Paper Tables T1–T4, generated from the cache (drift-safe)."  # its row in the paper SI (72): English, no repo jargon


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
    koop_dm = wb_dm["os3_plus"]["LUMO_eV"] - wb["fadh2_red"]["HOMO_eV"]  # ωB97X Koopmans ΔG = −Δε, dimethyl

    # ── drift asserts vs SUMMARY canon ──
    _close(dscf["dG_vertical_eV"], 0.3875, 0.01, "T2 ΔSCF vertical (dimethyl)")
    _close(dscf["dG_adiabatic_eV"], 0.0482, 0.01, "T2 ΔSCF adiabatic (dimethyl)")
    _close(koop_dm, 4.826, 0.01, "T2 Koopmans ωB97X (dimethyl)")
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
    _close(series["complexes"][names.index("bpy")]["cascade_delta_eV"], 0.2097, 0.005, "T4 H cascade")
    _close(series["complexes"][names.index("so2cf3")]["cascade_delta_eV"], 0.8921, 0.005, "T4 SO₂CF₃ cascade")

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
    md.append("| Cascade like for like · series · speciation | B3LYP | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | frontier orbitals, ΔSCF redox, the like-for-like cascade (Table 2), mediator series (①), speciation (②) |")
    md.append("| Thermochemistry | B3LYP + analytic C-PCM Hessian; RRHO at 298.15 K | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | the flavin E° at four levels (32b); the Os couple's zero-point energy, one form (96) |")
    md.append("| ωB97X one-electron readings | ωB97X single points (FAD geometries B3LYP/def2-SVP for the ΔSCF, B3LYP/6-31G(d) for the proton-coupled route) | def2-TZVP; LANL2DZ (Os) | C-PCM (water) | vertical and adiabatic ΔSCF of the first oxidation; the proton-coupled one-electron route with the proton reference (Table 2b) |")
    md.append("| Publication — speciation | ωB97X | 6-31G(d); LANL2DZ (Os) | C-PCM (water) | speciation functional-robustness (②) |")
    md.append("| PCET | B3LYP + thermodynamic proton reference (Isse–Gennaro) | 6-31G(d) | C-PCM (water) | the 2e⁻/2H⁺ FAD E° (32, 32b) |")
    md.append("| PCET — basis and functional | B3LYP, then ωB97X, single points on 32b's minima + the same proton reference | def2-TZVP | C-PCM (water) | the 2e⁻/2H⁺ FAD E° one knob at a time (112); with the device couple's ωB97X energies (def2-TZVP; LANL2DZ (Os)) the device cascade at that tier (95, Table 2 footnote) |")
    md.append("| Reorganisation λ | B3LYP; Nelsen 4-point (29b, 35) | def2-SVP (29b, flavin); 6-31G(d) + LANL2DZ (Co, Ru) / stuttgart_rsc (Ce) (35) | C-PCM (water) | inner-sphere λ_i of the flavin semiquinone couple and of Co, Ce and Ru; + Marcus two-sphere outer-sphere λ_o for the flavin (29c, analytical) |")
    md.append("| DET coupling | B3LYP; ΔSCF-UKS energy-splitting (24); two-state orbital diabatisation, FO-DFT label (24b; the Ru swap 24c/24d) | 6-31G(d); LANL2DZ (Cu, Co, Ru); stuttgart_rsc (Ce) | none (gas phase) | ZIF inter-metal t_ij and the site-energy gap |")
    md.append("\n*Reproducibility: scripted, fixed-seed DFT in `tools/in_silico`; every DFT cache behind these tables computed with PySCF 2.11.0 "
              "(the recorded environment — §2.7; the lock re-runs are separate records, SI S3).*\n")

    # ── Table 2 — the cascade like for like (95; ⚖️ founder 2026-10-16 «напрямок + таблиця»), then the one-electron
    # readings of the same step for the record — their sign carries no conclusion (⚖️ founder 2026-10-19, D) ──
    lfl = _load("cascade_like_for_like.json")
    levels = ("mmff_electronic", "relaxed_electronic", "relaxed_plus_zpe", "relaxed_rrho_free_energy")
    meas = lfl["measured"]
    _close(meas["cascade_same_couples_V"], 0.529, 1e-9, "T2 measured cascade, same free couples")
    _close(lfl["forms"][0]["by_donor_level"]["relaxed_electronic"]["cascade_V"], 0.2185, 0.0006, "T2 device form, relaxed el.")
    _close(lfl["both_sided"]["levels"]["relaxed_plus_zpe"]["cascade_V"], 0.5963, 0.0006, "T2 both-sided chloro, + ZPE")

    def sg(x: float, spec: str) -> str:   # the table's minus sign, not a hyphen
        return f"{x:{spec}}".replace("-", "−")

    def mv(v: float) -> str:
        return sg(v * 1000, "+.1f")

    def mv0(v: float, signed: bool = True) -> str:   # a measured value or a threshold — whole millivolts
        return sg(v * 1000, "+.0f" if signed else ".0f")

    cells = [f["by_donor_level"][k]["cascade_V"] for f in lfl["forms"] for k in levels]
    cells += [lfl["both_sided"]["levels"][k]["cascade_V"] for k in ("relaxed_electronic", "relaxed_plus_zpe")]
    if min(cells) <= 0:   # the caption's «every cell is downhill» is read from the cells, never typed
        sys.exit(f"CANON DRIFT [T2]: a like-for-like cell is not downhill (min {min(cells) * 1000:+.1f} mV) — rewrite §3.5")

    sh = lfl["shared_shifts"]
    soc, conv = sh["terms"]["spin_orbit_os"], sh["terms"]["she_abs_4_44"]
    bipy = sh["terms"]["spin_orbit_os_ref63_bipy"]
    s2rows = lfl["shared_shifts"]["ref63_table_s2_rows"]
    both = sh["combined"]["spin_orbit_os + she_abs_4_44"]
    both_bipy = sh["combined"]["spin_orbit_os_ref63_bipy + she_abs_4_44"]
    film = _load("os_series_vs_measured.json")["pvi_series"]["loading_control"]["shift_mV"] / 1000.0   # §3.3's 135 mV
    flv = lfl["flavin"]["levels"]
    md.append("## Table 2. The anode→mediator cascade like for like — the 2e⁻/2H⁺ flavin couple against each Os(III/II) "
              "form on one SHE scale\n")
    md.append("| Os form (B3LYP/6-31G(d)+LANL2DZ(Os)/C-PCM) | E°(Os) vs SHE, mV | acceptor side, mV | cascade, flavin MMFF el. "
              "| cascade, flavin relaxed el. | cascade, flavin + ZPE ¹ | cascade, flavin + RRHO ¹ |")
    md.append("|---|---|---|---|---|---|---|")
    md.append("| *flavin: E°(FAD/FADH₂) at pH 7, mV (donor side)* | | | "
              + " | ".join(f"*{mv(flv[k]['E_pH7_computed_V'])} ({mv(flv[k]['donor_side_V'])})*" for k in levels) + " |")
    for f in lfl["forms"]:
        md.append(f"| {f['form']} | {mv(f['E_os_vs_SHE_V'])} | {mv(f['acceptor_side_V'])} | "
                  + " | ".join(mv(f["by_donor_level"][k]["cascade_V"]) for k in levels) + " |")
    bs = lfl["both_sided"]["levels"]
    md.append(f"| {lfl['both_sided']['form']}, Os side with its own ZPE ² | {mv(bs['relaxed_electronic']['E_os_vs_SHE_V'])} el. / "
              f"{mv(bs['relaxed_plus_zpe']['E_os_vs_SHE_V'])} + ZPE | "
              f"{mv(bs['relaxed_electronic']['acceptor_side_V'])} el. / {mv(bs['relaxed_plus_zpe']['acceptor_side_V'])} + ZPE | — | {mv(bs['relaxed_electronic']['cascade_V'])} | "
              f"{mv(bs['relaxed_plus_zpe']['cascade_V'])} | not comparable ³ |")
    md.append(f"| **Measured (free flavin; film-bound mediator, pH 7.4)** | **{mv0(meas['E_os_V'])}** | | "
              + " | ".join(f"**{mv0(meas['cascade_same_couples_V'])}**" for _ in levels) + " |")
    canc = "; ".join(f"{c['form']} at {flv[c['level']]['label']} ({mv(c['gap_V'])} mV = donor {mv(c['donor_side_V'])} + "
                     f"acceptor {mv(c['acceptor_side_V'])})" for c in lfl["cancellations"]["rows"])
    ht = lfl["higher_tier"]
    htl = ht.get("levels", {})
    # the footnote writes «stay downhill» and «keep … on the 4.44 V convention» for the two one-sided cells: refuse rather
    # than print a threshold under a false word
    if ht["computed"] and any(htl[k]["direction"] != "downhill" or htl[k]["with_she_abs_4_44_V"] <= 0
                                for k in ("relaxed_plus_zpe", "relaxed_rrho_free_energy")):
        raise SystemExit("higher tier: a zero-point/RRHO cell is no longer downhill, or no longer > 0 on the 4.44 V convention — "
                         "rewrite the Table 2 footnote, do not regenerate it")
    higher = (f"At ωB97X/def2-TZVP on both sides — the device form only, the one osmium form computed at that tier, against "
              f"the flavin re-read at it on 32b's geometries (script 112) — the device cascade is "
              f"{mv(htl['relaxed_electronic']['cascade_V'])} mV on the relaxed electronic flavin level "
              f"({htl['relaxed_electronic']['direction']}) and {mv(htl['relaxed_plus_zpe']['cascade_V'])} / "
              f"{mv(htl['relaxed_rrho_free_energy']['cascade_V'])} mV with the flavin's zero-point / RRHO terms (one-sided; single "
              f"points — the osmium geometry programmatic and vertical with LANL2DZ on osmium as in every cell, the flavin's "
              f"geometry and thermal terms from B3LYP, its Os(III) accepted on convergence alone; the zero-point / RRHO cells stay "
              f"downhill until the spin–orbit shift passes {mv(-htl['relaxed_plus_zpe']['cascade_V'])} / "
              f"{mv(-htl['relaxed_rrho_free_energy']['cascade_V'])} mV, at the [Os(bpy)₃] size read "
              f"{mv(htl['relaxed_plus_zpe']['with_spin_orbit_os_ref63_bipy_V'])} / "
              f"{mv(htl['relaxed_rrho_free_energy']['with_spin_orbit_os_ref63_bipy_V'])} mV, and on the 4.44 V convention keep "
              f"{mv(htl['relaxed_plus_zpe']['with_she_abs_4_44_V'])} / {mv(htl['relaxed_rrho_free_energy']['with_she_abs_4_44_V'])} "
              f"mV; §3.5). ") if ht["computed"] else ""
    md.append(f"\n*Cascade = E°(Os) − E°(FAD/FADH₂, pH 7) in mV, > 0 = downhill; every cell at this tier (B3LYP/6-31G(d)) is downhill (smallest "
              f"{mv(min(cells))} mV). Donor side = computed − measured free flavin "
              f"({mv0(lfl['flavin']['E_pH7_measured_free_V'])} mV); acceptor side = measured ({mv0(meas['E_os_V'])} mV) − "
              f"computed Os; their sum is the gap to the measured {mv0(meas['cascade_same_couples_V'])} mV (the free flavin against the "
              f"film-bound mediator, whose preparation moves its E°′ by {mv0(film, False)} mV, §3.3; the flavin at pH 7, the film "
              f"at pH 7.4). The device's {mv0(meas['cascade_device_V'])} mV adds the measured protein shift of the bound cofactor "
              f"({mv0(meas['protein_shift_V'])} mV), which is not computed here. The flavin levels: MMFF "
              "geometries (script 32), relaxed (32b), + its zero-point energy, + its RRHO free energy. ¹ One-sided: these "
              "levels correct the flavin only — every Os form stays at its electronic energy, except the row marked ². "
              "² Both Os states relaxed and given their own zero-point energy (script 96). ³ The two Os states' soft-mode "
              f"censuses differ, so their RRHO free energies are not compared. Every cell shares one functional, one continuum, one "
              f"absolute-SHE convention ({lfl['conventions']['SHE_abs_V']} V) and a scalar-relativistic osmium, which the cells do "
              f"not test: spin–orbit coupling on osmium, omitted, reverses a cell beyond {mv(soc['first_flip_at_V'])[1:]} mV; at "
              f"the size ref 63 computes for [Os(bpy)₃] ({mv0(bipy['shift_V'])} mV) it turns {bipy['n_uphill']} of the "
              f"{bipy['n_cells']} cells uphill, {soc['n_uphill']} at the octahedral summary of ref 63's abstract ({mv0(soc['shift_V'])} mV) and up to "
              f"{max(r['n_uphill'] for r in s2rows['rows'].values())} at the larger rows of its Table S2 (−400 mV), while against the measured flavin the device couple keeps "
              f"{mv(bipy['against_measured_flavin']['by_form_V'][lfl['forms'][0]['form']])} mV at the [Os(bpy)₃] value and turns uphill past "
              f"{mv(s2rows['device_turns_uphill_against_measured_flavin_past_V'])} mV; the alternative 4.44 V convention "
              f"({mv0(conv['shift_V'])} mV) turns {'none' if not conv['n_uphill'] else conv['n_uphill']}, with spin–orbit coupling "
              f"{both_bipy['n_uphill']} and {both['n_uphill']} (§3.5). {higher}Agreements by cancellation, not validations — thresholds ours "
              f"(|gap| ≤ {mv0(lfl['cancellations']['gap_max_V'], False)} mV while each side is ≥ "
              f"{mv0(lfl['cancellations']['each_side_min_V'], False)} "
              f"mV off): {canc}.*\n")
    # the ΔSCF rows from their DEFINITION — 21g's energies and B1's — never from the 4-decimal display rows: the vertical
    # 0.38745 is stored as 0.3875 and would print +0.388 (in-silico §When Modifying #6); the display rows stay a control
    ea_dm = (wb_dm["os3_plus"]["E_total_Ha"] - wb_dm["os2_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    vert = (dscf["E_FADH2_cation_vertical_Ha"] - dscf["E_FADH2_Ha"]) * HARTREE_TO_EV - ea_dm
    adia = (dscf["E_FADH2_cation_adiabatic_Ha"] - dscf["E_FADH2_Ha"]) * HARTREE_TO_EV - ea_dm
    # 6e-5 = the display rows' rounding bound (round(·, 4) → 5e-5) plus 1e-5 for the float path
    _close(vert, dscf["dG_vertical_eV"], 6e-5, "T2b ΔSCF vertical vs its cached display row")
    _close(adia, dscf["dG_adiabatic_eV"], 6e-5, "T2b ΔSCF adiabatic vs its cached display row")
    pc = _load("pcet_cascade.json")
    pcet = (pc["E_FADH_radical_Ha"] - pc["E_FADH2_Ha"]) * HARTREE_TO_EV + pc["G_star_H_aq_eV"] - ea_dm
    _close(pcet, pc["cascade_pcet_eV"], 6e-4, "T2b PCET route vs its cached display row (3 decimals)")
    md.append("## Table 2b. One-electron readings of the same step — not like-for-like with the 2e⁻/2H⁺ driving force\n")
    md.append("| Reading (ωB97X/def2-TZVP, the device dimethyl mediator) | ΔE/e⁻ (eV), > 0 = uphill |")
    md.append("|---|---|")
    md.append(f"| ΔSCF, vertical | {sg(vert, '+.3f')} |")
    md.append(f"| ΔSCF, adiabatic (FAD side relaxed; Os vertical) | {sg(adia, '+.3f')} |")
    md.append(f"| Proton-coupled route FADH₂ → FADH• + H⁺ + e⁻ (proton reference, 1 M H⁺ — pH 0; B3LYP/6-31G(d) geometries) | {sg(pcet, '+.3f')} |")
    pcet_ph7 = pcet - 7.0 * NERNST_SLOPE_V                                   # the same Nernst term the 2e⁻/2H⁺ couple carries (32)
    h = pc["minimum_check"]
    dzpe = (h["FADH_radical"]["harmonic"]["ZPE_Ha"] - h["FADH2"]["harmonic"]["ZPE_Ha"]) * HARTREE_TO_EV
    md.append(f"| the same route at pH 7 (Nernst term, −{7.0 * NERNST_SLOPE_V:.3f} eV) | {sg(pcet_ph7, '+.3f')} |")
    md.append(f"| the same route at pH 7 with the flavin zero-point energies (B3LYP harmonic, {sg(dzpe, '+.3f')} eV) ⁴ | {sg(pcet_ph7 + dzpe, '+.3f')} |")
    md.append("\n*Electronic energy differences per electron transferred (the proton-coupled route adds the proton reference). "
              f"The ωB97X Koopmans offset, Δε = ε_HOMO(FADH₂) − ε_LUMO(Os(III)) = {sg(-koop_dm, '+.3f')} eV in Table 4's sign "
              "(> 0 = downhill), is a range-separation artefact and is not used. FADH₂ = the 1,5-dihydro "
              "tautomer; the flavin geometries are minima by their Hessians, the osmium side vertical on its programmatic "
              "geometry. These are "
              "one-electron quantities set against no two-electron value here, and no conclusion is drawn from their sign; the "
              "B3LYP orbital offset is in Table 4 (Me row). ⁴ Mixed tiers — ωB97X/def2-TZVP electronic energies with the B3LYP/6-31G(d) "
              "zero-point energies of the two flavin states (script 33's Hessians); the osmium side carries no thermochemistry here.*\n")

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
    md.append(f"| Ce–graphene (vacancy↔MWCNT, multi-walled carbon nanotube) | {p['Ce-graphene']['t_ij_eV']:.5f} (crude) | {p['Ce-graphene']['t_ij_eV']:.5f} | {res['Ce-graphene']:.0f} | — | — |")
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

    md.append(_row(f"**literature λ** (Cu {cu_lo:.1f}–{cu_hi:.1f} / Co {lam_lit['Co']:.1f}, assumed / Ce {lam_lit['Ce']:.1f})",
                   sc["literature λ"], bold=True))
    md.append(_row(f"**computed λ** (B3LYP: Co {lam_comp['Co']:.2f}; Cu literature)", sc["computed λ (B3LYP)"], bold=True))
    ru_half = ket["ru_lambda_nelsen_halves"]
    md.append(_row(f"Ru-swap (Co→Ru, computed λ {lam_comp['Ru']:.2f}) — *indicative: λ(Ru) sums Nelsen halves "
                   f"{ru_half['lambda_1_eV']:+.2f} and {ru_half['lambda_2_eV']:+.2f} eV; the Cu–Ru coupling and gap are not "
                   "obtainable from the minimal cluster, so it borrows the Cu–Co coupling and every column is ΔG = 0*",
                   sc["Ru-swap (Co→Ru, computed)"]))
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
    md.append("## Table 4. Osmium mediator series — ΔE_red and the Koopmans offset vs Hammett σ (①)\n")
    md.append("cis-[Os(4,4′-X-bpy)₂(1-MeIm)Cl]⁺/²⁺ at constant charge; B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM vertical ΔSCF; "
              "last column — the same ΔSCF at ωB97X/def2-TZVP on the same geometry, minus the B3LYP value.\n")
    md.append("| 4,4′-X | σ_para | ΔE_red(III→II) (eV) | Os(III) LUMO (eV) | Koopmans offset Δε (eV) | note | ω−B3 (eV) |")
    md.append("|---|---|---|---|---|---|---|")
    lbl = {"nme2": "NMe₂", "nh2": "NH₂", "ome": "OMe", "dmbpy": "Me", "bpy": "H",
           "cl": "Cl", "dcbpy": "COOH", "cf3": "CF₃", "no2": "NO₂", "so2cf3": "SO₂CF₃"}
    # ⚖️ founder 2026-10-15: SO₂CF₃ is not relaxed, so it is not printed as the optimum (PIPELINE_STATUS, note under D)
    note = {"nme2": "donor saturation", "bpy": "reference", "cf3": "assumed inert (not tested)",
            "no2": "unstable on cycling", "so2cf3": "assumed inert (not tested); order vs NO₂ open"}
    vs = series_wb["vs_b3lyp"]
    omega = {p["name"]: p["omega_minus_b3_eV"] for p in vs["points"]}
    for c in sorted(series["complexes"], key=lambda x: x["sigma_para"]):
        n = c["name"]
        om = f"{omega[n]:+.3f}" if n in omega else "—"
        md.append(f"| {lbl.get(n, n)} | {c['sigma_para']:+.2f} | {c['dE_red_eV']:.3f} | "
                  f"{c['os3']['LUMO_eV']:.3f} | {c['cascade_delta_eV']:+.4f} | {note.get(n, '')} | {om} |")
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
                f"decided — relaxing {lbl[rel]} alone moves {lbl[rel]}'s own Koopmans offset by "
                f"{m(mv['os3_on_own_minimum'], '+.0f')} meV with Os(III) on its own minimum and "
                f"{m(mv['os3_on_os2_minimum'], '+.0f')} meV with Os(III) vertical, and {lbl[other]} was not relaxed")
    undecided = "".join("; " + pair_clause(k, v) for k, v in open_pairs)
    if flipped:
        undecided += ("; relaxing both members reverses " + ", ".join("→".join(lbl[x] for x in f.split("-")) for f in flipped))
    md.append(f"\n*Koopmans trend: the Koopmans offset rises with σ ({m(ends_casc[0]['cascade_delta_eV'], '+.2f')} "
              f"{lbl[ends_casc[0]['name']]} → {m(ends_casc[1]['cascade_delta_eV'], '+.2f')} "
              f"{lbl[ends_casc[1]['name']]}){undecided}; ΔE_red "
              f"LFER slope ≈ −{abs(lf_slope):.2f} eV/σ over OMe→NO₂ (Fig 2). Higher E°(Os) lowers OCV, so "
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
