#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later
"""③ Cathode DET k_ET vs reorganization energy λ — honest margin analysis.

Combines the geometry-corrected hopping integrals t_ij (script 24, on the
deprotonated / clash-free ZIF cluster) with the COMPUTED metal reorganization
energies λ (script 35, Nelsen 4-point) under the two-sphere Marcus approximation
λ_hop = (λ_i + λ_j)/2, to test whether the old "k_DET ≫ turnover (~10⁵×)" claim
survives a realistic λ. It does NOT: that margin was a double artifact of
(a) a broken bridging geometry (script 23 imidazole N–H clashing into the 2nd
metal at 0.97 Å — since deprotonated to an imidazolate bridge) and (b) an
assumed λ = 0.7 eV. ⊕ 2026-10-15: the table runs on 24b's diabatised coupling, and the verdict is
CONDITIONAL on λ(Co) — below turnover at every corner on the COMPUTED λ(Co) 3.09 eV, straddling it only
on the ASSUMED literature 1.4 eV, which has no primary (`cobalt_lambda_condition`);
a Co→Ru swap (computed λ_Ru = 0.78) restores a margin that is indicative only, because
Cu(II/I) keeps a large λ — itself a bracket of two named readings, never a pick.
Compute-light: reads cached JSON, runs no DFT.

Run:  python tools/in_silico/scripts/25_cathode_ket_lambda.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE as CACHE
from lib.constants import ZIF_DSCF_CONV_TOL_HA
from lib.dft_utils import marcus_rate

TURNOVER_S = 1.0e3  # enzymatic turnover ~10³ s⁻¹ (the rate the cathode must beat)

# Literature self-exchange reorganization energies (eV) for the aqua/ammine couples
# — textbook Marcus values; the first-row/Cu couples are intrinsically large. Co/Ce/Ru have
# no primary in the tree either (the paper names them as assumptions in Methods — ratified 2026-10-01).
#
# λ(Cu) is a BRACKET of two NAMED solution readings, never a pick (§When Modifying #11), and the
# verdict is judged at its adverse corner:
#   · "unsourced" 2.0 — the value this script always carried; no primary found.
#   · "cu_phen2" 2.4 — self-exchange of Cu(phen)₂²⁺/⁺, Gray & Winkler, PNAS 2005, 102, 3534
#     (PMC553296, §"Ru-Proteins", citing their ref 24). ⚠️ The species is an inline formula IMAGE;
#     the page's text layer drops it, and it had been read as «aqueous Cu(II/I)» — it is a bis-phen
#     N4 chelate, not the aqua ion. Read from the image 2026-09-24.
# ⛔ Both are UNCONSTRAINED solution couples. A framework-held Cu–N4 node can sit BELOW both (the
# same paragraph gives Cu(II/I) in azurin 0.7 eV — the entatic fold), so the bracket bounds the
# READINGS, not the site: its adverse end is a consumer ceiling, its kind end is no floor.
LAMBDA_CU_READINGS = {"unsourced": 2.0, "cu_phen2": 2.4}
LAMBDA_CU_READING_SOURCES = {
    "unsourced": "textbook value, no primary found — [CITATION NEEDED]",
    "cu_phen2": "Cu(phen)2 2+/+ self-exchange ≈2.4 eV — Gray & Winkler, PNAS 2005, 102, 3534 "
                "(PMC553296); species read from the inline formula image, not the text layer",
}
LAMBDA_CU_BASE = "unsourced"   # the reading `lambda_lit_eV` and the single-λ fields carry
LAMBDA_LIT = {"Cu": LAMBDA_CU_READINGS[LAMBDA_CU_BASE], "Co": 1.4, "Ce": 1.0, "Ru": 0.8}   # assumed, no primary (paper §2.5); script 35's own `lit` marker for its Co rows is 1.3 — the paper prints this 1.4


def _load_tij() -> dict[str, float]:
    """Geometry-corrected t_ij per hop from script 24 (fixed clash-free cluster)."""
    raw = json.loads((CACHE / "zif_hopping.json").read_text())
    pairs = raw["pairs"] if isinstance(raw, dict) else raw
    out = {}
    for p in pairs:
        m1, m2 = p["metal1"], p["metal2"]
        out[f"{m1}-{m2}"] = float(p["t_ij_eV"])
    return out


def _load_lambda_computed() -> tuple[dict[str, float], dict[str, str]]:
    """λ per metal for the "computed" scenarios, WITH per-metal provenance.

    Not every entry is computed, and the key name alone says the opposite. Cu falls
    back to `LAMBDA_LIT` — a Cu(I) d¹⁰ hexa-aqua optimisation is unphysical. The
    docstring knew that; the emitted cache did not, and the cache is what the canon
    quotes. The returned provenance map rides beside the numbers so a reader of the
    JSON sees which half is a measurement (the absence is DRAWN, not left to a
    default that reads like a result).

    🔴 The Cu provenance line is DERIVED from the cache, never typed. It used to state
    «script 35 has no Cu row» as a fact about ANOTHER artefact — true on the day it was
    written, and false after the first full run of 35, whose `which = … or list(METALS)`
    includes `cu` and whose unphysical branch still emits a row (with `lambda_use_eV`
    = lit). The number here is safe either way, because this fallback is hard-coded;
    what was not safe is the SENTENCE, and nothing could have reddened it. A third
    state — 35 emitting a Cu row that PASSES its physicality check — makes this
    hard-coded fallback stale, so it is announced loudly rather than absorbed.
    """
    res = json.loads((CACHE / "metal_reorganization.json").read_text())["results"]
    by_name = {r["name"]: float(r["lambda_use_eV"]) for r in res}
    co_row = "co_nh3" if "co_nh3" in by_name else "co"
    values = {
        "Cu": LAMBDA_LIT["Cu"],
        "Co": by_name[co_row],
        "Ce": by_name["ce"],
        "Ru": by_name["ru"],
    }
    cu_row = next((r for r in res if r.get("name") == "cu"), None)
    if cu_row is None:
        cu_prov = ("LITERATURE, NOT COMPUTED — script 35 emitted no Cu row (Cu(I) d¹⁰ "
                   "hexa-aqua optimisation is unphysical); this is LAMBDA_LIT['Cu']")
    elif not cu_row.get("physical"):
        cu_prov = ("LITERATURE, NOT COMPUTED — script 35 DID emit a Cu row and flagged it "
                   f"unphysical (λ_computed = {cu_row.get('lambda_computed_eV')} eV); "
                   "this is LAMBDA_LIT['Cu']")
    else:
        cu_prov = ("⚠️ STALE FALLBACK — script 35 now emits a PHYSICAL Cu row "
                   f"(λ_computed = {cu_row.get('lambda_computed_eV')} eV), so this "
                   "hard-coded LAMBDA_LIT['Cu'] no longer reflects the pipeline and the "
                   "bottleneck λ must be re-judged (00_07 HW.5.IS)")
    provenance = {
        "Cu": cu_prov,
        "Co": f"computed — script 35 row `{co_row}` (ammine = the ZIF N-donor analogue)",
        "Ce": "computed — script 35 row `ce`",
        "Ru": "computed — script 35 row `ru`",
    }
    return values, provenance


def _two_sphere(la: float, lb: float) -> float:
    return 0.5 * (la + lb)


def main() -> int:
    tij = _load_tij()
    lam_c, lam_prov = _load_lambda_computed()
    print("=== λ per metal (script 35 where it exists) ===")
    for m, v in lam_c.items():
        print(f"  {m:3s} λ = {v:.4f} eV — {lam_prov[m]}")
    print("=== geometry-corrected t_ij (script 24, clash-free cluster) ===")
    for h, t in tij.items():
        print(f"  {h:8s} t_ij = {t:.5f} eV")

    # Each scenario maps a hop → its two-sphere λ. The Ru-swap replaces the Co node.
    # ── driving force: what is MEASURED, what is a default wearing a measurement's clothes ──
    # `marcus_rate`'s dG defaults to 0. Until 2026-09-21 every scenario row below took that
    # default while the FO-DFT block at the bottom of this same script already knew a computed
    # Cu-Co site-energy gap — so the headline margins quoted by canon, SUMMARY, PIPELINE_STATUS,
    # L3 and the paper were ΔG = 0 READINGS, not measurements. They are now brackets.
    fo = json.loads((CACHE / "fodft_coupling.json").read_text())
    ru_fo = json.loads((CACHE / "cu_ru_fodft.json").read_text())
    # MAGNITUDE only. The 24b two-state diabatisation returns |ΔE| between two diabatic states;
    # which of them is the donor on the cathode's electron path is NOT fixed by that calculation,
    # so the sign stays unmeasured and both ends are carried (§When Modifying #11).
    GAP_EV = {"Cu-Co": float(fo["site_energy_gap_eV"])}
    # ⛔ Self-review round 1, cluster 8 (2026-10-15): the crude t(Cu–Co) of script 24 is half the difference of two UNCONSTRAINED
    # SCF solutions of one cluster from one start (state B differs only in SCF settings: level shift, DIIS space, cycle cap) — not charge-localised states, and
    # the difference is a single-digit multiple of the tolerance both were converged to (`dscf_coupling_resolution`). So the
    # table runs on the two-state diabatisation (24b) for the bottleneck pair; the other hops keep 24's value (resolved against
    # tolerance, but not a diabatic coupling either), and the crude-t table stays as `scenarios_crude_dscf` so the numbers
    # published before this date remain traceable. ⚠️ The Ru-swap borrows the Cu–Co coupling for its Cu–Ru node (24d's own is
    # self-flagged non-physical), so its lever is λ alone — as before, now on the diabatised t.
    tij_crude = dict(tij)
    tij["Cu-Co"] = float(fo["t_ij_eV"])
    T_SOURCE = {h: ("24b two-state diabatisation (FO-DFT label)" if h == "Cu-Co" else "24 crude ΔSCF") for h in tij}
    GAP_SOURCE = {"Cu-Co": "fodft_coupling.json (24b) · site_energy_gap_eV"}
    # ⛔ The Ru node's gap is NOT unmeasured-yet, it is unmeasurable at this cluster level: 24d
    # returns a number AND self-flags it non-physical (both diabatic orbitals sit on Ru, pop(Cu)=0)
    # — the same failure that disqualified its t_ij, so it disqualifies its gap too.
    RU_GAP_REFUSED = {
        "pair": ru_fo["pair"], "gap_eV_reported": float(ru_fo["site_energy_gap_eV"]),
        "usable": False,
        "reason": "24d self-flags localised=False / physically_reasonable=False — the minimal "
                  "cluster cannot form a clean Cu↔Ru diabatic pair, so its site-energy gap is not "
                  "a measurement any more than its t_ij was",
    }

    # Each scenario maps a hop → its two-sphere λ. The Ru-swap replaces the Co node.
    # ⚠️ The Ru-swap REUSES the "Cu-Co" / "Co-Ce" keys for what are physically the Cu-Ru / Ru-Ce
    # nodes, so `node_identity` says what each slot really is — without it the Cu-Co gap would be
    # applied to a pair it was never measured on.
    # λ(Cu) enters EVERY scenario but the retired 0.7 one — the computed set falls back to the
    # literature Cu too (script 35 has no physical Cu row) — so each is built per λ(Cu) reading.
    def _scenarios(lam_cu: float) -> dict[str, dict[str, float]]:
        lit, comp = dict(LAMBDA_LIT, Cu=lam_cu), dict(lam_c, Cu=lam_cu)
        return {
            "canon λ=0.7 (old assumption)": {
                "Cu-Co": 0.7, "Co-Ce": 0.7, "Ce-C": 0.7},
            "literature λ": {
                "Cu-Co": _two_sphere(lit["Cu"], lit["Co"]),
                "Co-Ce": _two_sphere(lit["Co"], lit["Ce"]),
                "Ce-C": lit["Ce"]},
            "computed λ (B3LYP)": {
                "Cu-Co": _two_sphere(comp["Cu"], comp["Co"]),
                "Co-Ce": _two_sphere(comp["Co"], comp["Ce"]),
                "Ce-C": comp["Ce"]},
            "Ru-swap (Co→Ru, computed)": {
                "Cu-Co": _two_sphere(comp["Cu"], comp["Ru"]),   # Cu–Ru node
                "Co-Ce": _two_sphere(comp["Ru"], comp["Ce"]),   # Ru–Ce node
                "Ce-C": comp["Ce"]},
        }
    scen_by_cu = {r: _scenarios(v) for r, v in LAMBDA_CU_READINGS.items()}
    scenarios = scen_by_cu[LAMBDA_CU_BASE]
    NODE_IDENTITY = {
        "Ru-swap (Co→Ru, computed)": {"Cu-Co": "Cu-Ru", "Co-Ce": "Ru-Ce", "Ce-C": "Ce-C"},
    }

    def _dg(scenario: str, branch: str) -> dict[str, float]:
        """ΔG per hop for one branch. A hop whose node has no USABLE measured gap gets 0.0 —
        and the caller records that as an assumption, never as a measurement."""
        ident = NODE_IDENTITY.get(scenario, {})
        out_dg = {}
        for hop in tij:
            node = ident.get(hop, hop)
            mag = GAP_EV.get(node)
            out_dg[hop] = 0.0 if (mag is None or branch == "zero") else (
                +mag if branch == "adverse" else -mag)
        return out_dg

    def _measured_hops(scenario: str) -> list[str]:
        ident = NODE_IDENTITY.get(scenario, {})
        return [h for h in tij if ident.get(h, h) in GAP_EV]

    BRANCHES = ("adverse (+gap, uphill)", "dG=0 (ASSUMPTION)", "favourable (−gap, downhill)")
    _BRANCH_KEY = {BRANCHES[0]: "adverse", BRANCHES[1]: "zero", BRANCHES[2]: "favourable"}

    out = {"t_ij_eV": tij, "t_ij_source": T_SOURCE, "t_ij_crude_dscf_eV": tij_crude,
           "lambda_computed_eV": lam_c,
           "lambda_computed_provenance": lam_prov,
           "lambda_lit_eV": LAMBDA_LIT, "turnover_s": TURNOVER_S,
           "driving_force": {
               "measured_magnitude_eV": GAP_EV, "measured_source": GAP_SOURCE,
               "sign_is_unmeasured": True,
               "sign_convention": "marcus_rate takes dG in eV; NEGATIVE is downhill and faster "
                                  "for |dG| < 2λ, so the ADVERSE end is +|gap|",
               "hops_without_a_usable_gap": {
                   h: "no FO-DFT diabatisation exists for this pair" for h in tij
                   if h not in GAP_EV},
               "unmeasured_treatment": "dG = 0, recorded per scenario as an ASSUMPTION "
                                       "(`driving_force_measured_for_bottleneck`), because a "
                                       "default that reads like a measurement is how the headline "
                                       "margins came to be quoted as if ΔG were known",
               "ru_node_gap_refused": RU_GAP_REFUSED,
           },
           "consumer_rule": "take `margin_vs_turnover_adverse` — a bracket's consumer ceiling is "
                            "the ADVERSE reading, cited (in-silico §When Modifying #11); it is the "
                            "worst CORNER of two axes, the gap sign × the λ(Cu) reading, and "
                            "`adverse_corner` names it. `margin_vs_turnover_favourable` is the kind "
                            "corner. `margin_vs_turnover_at_dG0` and `by_dG` stay at the BASE λ(Cu) "
                            "reading so the pre-2026-09-21 published number stays traceable, NOT so "
                            "it can be quoted",
           "lambda_cu_readings_eV": LAMBDA_CU_READINGS,
           "lambda_cu_reading_sources": LAMBDA_CU_READING_SOURCES,
           "lambda_cu_base_reading": LAMBDA_CU_BASE,
           "lambda_cu_bracket_bounds": "the READINGS, not the site — both are unconstrained "
                                       "solution couples; a framework-held Cu–N4 node can sit below "
                                       "both (Cu(II/I) in azurin 0.7 eV, same source), so the kind "
                                       "end is no floor",
           "scenarios": {}}

    def _branches(name: str, lam: dict[str, float], t_map: dict[str, float] | None = None) -> dict[str, dict]:
        per_branch, ident = {}, NODE_IDENTITY.get(name, {})
        for label in BRANCHES:
            dg = _dg(name, _BRANCH_KEY[label])
            ks = {h: marcus_rate(t, lam[h], dg[h]) for h, t in (t_map or tij).items()}
            hop = min(ks, key=ks.get)
            per_branch[label] = {
                "dG_eV": dg, "k_ET_per_s": ks, "bottleneck_hop": ident.get(hop, hop),
                "bottleneck_s": ks[hop], "margin_vs_turnover": ks[hop] / TURNOVER_S}
        return per_branch

    print(f"\n  {'scenario':32s} {'BOTTLENECK':>11} {'adverse':>11} {'ΔG=0':>11} {'favourable':>11}"
          "   (adverse/favourable = worst/kindest corner over gap sign × λ(Cu) reading)")
    for name, lam in scenarios.items():
        ident = NODE_IDENTITY.get(name, {})
        grid = {r: _branches(name, scen_by_cu[r][name]) for r in LAMBDA_CU_READINGS}
        per_branch = grid[LAMBDA_CU_BASE]
        # The corners are COMPUTED over all six cells, never assumed from «higher λ is slower»
        # (true only while every |ΔG| < λ — asserted by nobody, so not relied on).
        cells = [(r, b, grid[r][b]["margin_vs_turnover"]) for r in grid for b in BRANCHES]
        worst, kind = min(cells, key=lambda c: c[2]), max(cells, key=lambda c: c[2])
        measured = _measured_hops(name)
        zero = per_branch[BRANCHES[1]]
        out["scenarios"][name] = {
            "lambda_hop_eV": lam,
            "node_identity": {h: ident.get(h, h) for h in tij},
            "hops_with_a_measured_gap": measured,
            "driving_force_measured_for_bottleneck": grid[worst[0]][worst[1]]["bottleneck_hop"] in
            [ident.get(h, h) for h in measured],
            "by_dG": per_branch,
            "by_lambda_cu": {
                r: {"lambda_hop_eV": scen_by_cu[r][name],
                    **{f"margin_vs_turnover_{_BRANCH_KEY[b]}": grid[r][b]["margin_vs_turnover"]
                       for b in BRANCHES}}
                for r in grid},
            "adverse_corner": {"lambda_cu_reading": worst[0], "dG_branch": worst[1]},
            "favourable_corner": {"lambda_cu_reading": kind[0], "dG_branch": kind[1]},
            "margin_vs_turnover_adverse": worst[2],
            "margin_vs_turnover_at_dG0": zero["margin_vs_turnover"],
            "margin_vs_turnover_favourable": kind[2],
            "bottleneck_hop_is_branch_invariant":
                len({grid[r][b]["bottleneck_hop"] for r in grid for b in BRANCHES}) == 1,
        }
        flag = "" if measured else "   [no measured ΔG on any hop — all three columns are ΔG=0]"
        print(f"  {name:32s} {grid[worst[0]][worst[1]]['bottleneck_hop']:>11}"
              f" {'×' + format(worst[2], '.2g'):>11}"
              f" {'×' + format(zero['margin_vs_turnover'], '.2g'):>11}"
              f" {'×' + format(kind[2], '.2g'):>11}{flag}")

    # The pre-2026-10-15 table on the crude coupling — a RECORD of what was published, never a consumer reading.
    out["scenarios_crude_dscf"] = {}
    for name in scenarios:
        g = {(r, b): v["margin_vs_turnover"] for r in LAMBDA_CU_READINGS
             for b, v in _branches(name, scen_by_cu[r][name], tij_crude).items()}
        out["scenarios_crude_dscf"][name] = {
            "margin_vs_turnover_adverse": min(g.values()),
            "margin_vs_turnover_at_dG0": g[(LAMBDA_CU_BASE, BRANCHES[1])],
            "margin_vs_turnover_favourable": max(g.values())}

    # FO-DFT rigor (script 24b): the same bottleneck with the two-state coupling instead of the
    # crude ΔSCF one. ⊕ 2026-10-15: the scenario table above now runs on this coupling, so this block equals its
    # literature row; it is kept because 60 · 61 · 31b read its per-λ(Cu) shape. Kept as its own block because it answers a DIFFERENT question — whether the
    # verdict survives the coupling METHOD — while the table above answers it across λ.
    t_fo, dg_fo = fo["t_ij_eV"], fo["site_energy_gap_eV"]
    lam_lit = _two_sphere(LAMBDA_LIT["Cu"], LAMBDA_LIT["Co"])

    def _fo_margins(lam_hop: float) -> dict[str, float]:
        return {tag: marcus_rate(t_fo, lam_hop, dg) / TURNOVER_S
                for tag, dg in (("dG=0", 0.0), ("dG=+gap", dg_fo), ("dG=-gap", -dg_fo))}
    fo_by_cu = {r: _fo_margins(_two_sphere(v, LAMBDA_LIT["Co"]))
                for r, v in LAMBDA_CU_READINGS.items()}
    fo_margin = fo_by_cu[LAMBDA_CU_BASE]
    fo_cells = [(r, tag, m) for r, ms in fo_by_cu.items() for tag, m in ms.items()]
    fo_worst, fo_kind = min(fo_cells, key=lambda c: c[2]), max(fo_cells, key=lambda c: c[2])
    out["fodft_cuco_rigor"] = {
        "t_ij_eV": t_fo, "t_ij_crude_eV": fo["t_ij_crude_script24_eV"], "site_gap_eV": dg_fo,
        "lambda_hop_eV": lam_lit,
        "margin_vs_turnover_by_dG_sign": {k: round(v, 3) for k, v in fo_margin.items()},
        "by_lambda_cu": {r: {"lambda_hop_eV": _two_sphere(LAMBDA_CU_READINGS[r], LAMBDA_LIT["Co"]),
                             "margin_vs_turnover_by_dG_sign": {k: round(v, 3) for k, v in ms.items()}}
                         for r, ms in fo_by_cu.items()},
        "margin_adverse_corner": round(fo_worst[2], 3),
        "adverse_corner": {"lambda_cu_reading": fo_worst[0], "dG_branch": fo_worst[1]},
        "margin_favourable_corner": round(fo_kind[2], 3),
        "favourable_corner": {"lambda_cu_reading": fo_kind[0], "dG_branch": fo_kind[1]},
        "single_lambda_fields_are_at": f"λ(Cu) reading `{LAMBDA_CU_BASE}` — the corners are the "
                                       "consumer's numbers"}
    print(f"\n  FO-DFT rigor (Cu-Co t={t_fo:.5f} vs crude {fo['t_ij_crude_script24_eV']:.5f}, "
          f"gap {dg_fo} eV):")
    for r, ms in fo_by_cu.items():
        print(f"    λ(Cu) {r:9s} " + "  ".join(f"{tag} ×{m:.2g}" for tag, m in ms.items()))
    print(f"    corners: adverse ×{fo_worst[2]:.2g} ({fo_worst[0]}, {fo_worst[1]}) · "
          f"favourable ×{fo_kind[2]:.3g} ({fo_kind[0]}, {fo_kind[1]})")

    # 🔴 GEOMETRY SENSITIVITY — the term nothing declared until 2026-09-21, and it is NOT
    # ×|t|²: the refused off-plane bridge moves the site-energy gap as well as the coupling,
    # and both come out of the SAME diabatisation of the SAME cluster. Quoting the |t|² part
    # alone understates it ~25× and misdescribes it in kind, so the margin is recomputed here
    # end-to-end. ⛔ The off-plane geometry is REFUSED by script 23 (metals 0.70 / 1.37 Å out
    # of their own bridge-ring plane — a nitrogen binds through an IN-plane lone pair), so this
    # is the cost of building it WRONG, never a two-sided uncertainty on the shipped number.
    off_path = CACHE / "fodft_coupling_offplane.json"
    if off_path.exists():
        off = json.loads(off_path.read_text())
        off_margin = {tag: marcus_rate(off["t_ij_eV"], lam_lit, dg) / TURNOVER_S
                      for tag, dg in (("dG=0", 0.0), ("dG=+gap", off["site_energy_gap_eV"]))}
        out["geometry_sensitivity_refused_offplane"] = {
            "what": "bridge ring rolled out of the metals' coordination plane; REFUSED by "
                    "script 23 (`bridge_out_of_plane` > `PLANARITY_TOL_A`) — a probe, not a candidate",
            "t_ij_eV": off["t_ij_eV"], "site_gap_eV": off["site_energy_gap_eV"],
            "t_ij_ratio_vs_shipped": round(off["t_ij_eV"] / t_fo, 2),
            "margin_adverse": round(off_margin["dG=+gap"], 1),
            "margin_adverse_shipped": round(fo_margin["dG=+gap"], 3),
            "margin_ratio": round(off_margin["dG=+gap"] / fo_margin["dG=+gap"], 0),
            "flips_the_verdict": bool(
                (fo_margin["dG=+gap"] < 1.0) != (off_margin["dG=+gap"] < 1.0)),
            "why_not_t_squared": "the gap moves too, so the margin ratio is NOT the square of "
                                 "the coupling ratio — quoting |t|² alone understates it",
        }
        g = out["geometry_sensitivity_refused_offplane"]
        print(f"\n  geometry sensitivity (REFUSED off-plane probe): t_ij ×{g['t_ij_ratio_vs_shipped']}, "
              f"margin ×{g['margin_adverse_shipped']} → ×{g['margin_adverse']} "
              f"(×{g['margin_ratio']:.0f}); flips the verdict: {g['flips_the_verdict']}")

    lit = out["scenarios"]["literature λ"]

    # A COUPLING lever (bridge π-system, pore guest, metal-d swap) buys k ∝ |t_ij|², so the
    # multiplier it must deliver to lift the consumer-rule (ADVERSE) reading to enzymatic turnover
    # is 1/√margin. Derived here rather than inside whichever lever is being priced, because the
    # acceptance number belongs to the BOTTLENECK, not to the lever.
    # ⛔ Does NOT apply to a λ lever (Co→Ru): λ sits in the Marcus exponent, not in the prefactor,
    # so a λ gain does not convert into a coupling multiplier and this number must not be read onto it.
    out["coupling_gain_to_reach_turnover"] = {
        "definition": "|t_ij| multiplier the bottleneck hop needs for k_ET to reach enzymatic "
                      "turnover at the consumer-rule (adverse) end; k_ET ∝ |t_ij|², so 1/√margin. "
                      "A COUPLING lever only.",
        # ⊕ 2026-10-15 (cluster 1): the gain is CONDITIONAL on λ(Co) like the verdict it serves — the fields above
        # are at the ASSUMED literature λ(Co), the computed one needs the multiplier below. Quoting one without
        # naming its λ(Co) is how the single pre-conditional number got carried for weeks.
        "by_lambda_co": {
            "literature_assumed": {"lambda_co_eV": LAMBDA_LIT["Co"],
                                   "gain_fodft_t": round(lit["margin_vs_turnover_adverse"] ** -0.5, 3)},
            "computed": {"lambda_co_eV": lam_c["Co"],
                         "gain_fodft_t": round(out["scenarios"]["computed λ (B3LYP)"][
                             "margin_vs_turnover_adverse"] ** -0.5, 3)}},
        "at_literature_lambda_crude_t": round(out["scenarios_crude_dscf"]["literature λ"]["margin_vs_turnover_adverse"] ** -0.5, 3),
        "at_literature_lambda_fodft_t": round(lit["margin_vs_turnover_adverse"] ** -0.5, 3),
        "at_corner": "the adverse corner of BOTH axes (gap sign × λ(Cu) reading) — "
                     "`adverse_corner` of the literature scenario and of `fodft_cuco_rigor`",
        "judge_against": "at_literature_lambda_fodft_t — the rigorous coupling, and the scale the "
                         "canon quotes; the crude row exists so each published t_ij scale carries "
                         "its OWN acceptance number instead of one being read onto the other",
    }
    print("\n  coupling gain needed to reach turnover (adverse end, k ∝ |t|²):")
    for k in ("at_literature_lambda_crude_t", "at_literature_lambda_fodft_t"):
        print(f"    {k:32s} ×{out['coupling_gain_to_reach_turnover'][k]}")

    # ── Self-review round 1 of Стаття 1, clusters 1 and 8 (2026-10-15) ──────────────────────────────────────────────
    # (8) Is the crude ΔSCF coupling RESOLVED? It is half the energy difference of two SCF solutions of one cluster,
    # so the difference is read against the tolerance both were converged to.
    zif = json.loads((CACHE / "zif_hopping.json").read_text())
    out["dscf_coupling_resolution"] = {
        "scf_tol_Ha": ZIF_DSCF_CONV_TOL_HA,
        "pairs": {p["label"]: {"delta_E_Ha": round(abs(p["E_state_A_Ha"] - p["E_state_B_Ha"]), 8),
                              "delta_E_over_scf_tol": round(abs(p["E_state_A_Ha"] - p["E_state_B_Ha"])
                                                            / ZIF_DSCF_CONV_TOL_HA, 1),
                              "t_ij_eV": p["t_ij_eV"]} for p in zif["pairs"]},
        "reading": "t = ΔE/2 of two SCF solutions; for the bottleneck pair ΔE is a single-digit multiple of the "
                   "SCF tolerance, so the paper takes the two-state diabatisation (FO-DFT label, 24b) as the coupling",
    }
    # (1) What the cathode needs from λ(Co): the λ(Co) at which the Cu–Co hop reaches turnover, per coupling, per λ(Cu)
    # reading and per ΔG branch. k is monotone in λ_hop over the bracket searched, which is asserted, not assumed.
    def _lambda_hop_at_turnover(t: float, dg: float) -> float | None:
        lo, hi = 0.05, 8.0
        grid = [lo + i * (hi - lo) / 400 for i in range(401)]
        ks = [marcus_rate(t, x, dg) for x in grid]
        peak = max(range(len(ks)), key=ks.__getitem__)
        if ks[peak] < TURNOVER_S:
            return None                               # unreachable at ANY λ — the coupling is too small
        a, b = grid[peak], hi
        if marcus_rate(t, b, dg) > TURNOVER_S:
            return b
        assert all(ks[i] >= ks[i + 1] for i in range(peak, len(ks) - 1)), "k(λ) not monotone past its peak"
        for _ in range(80):
            m = (a + b) / 2
            a, b = (m, b) if marcus_rate(t, m, dg) > TURNOVER_S else (a, m)
        return (a + b) / 2
    co_need = {}
    for t_name, t_val in (("fodft", t_fo), ("crude_dscf", tij_crude["Cu-Co"])):
        for r, lam_cu in LAMBDA_CU_READINGS.items():
            for tag, dg in (("dG=0", 0.0), ("dG=+gap", dg_fo)):
                lh = _lambda_hop_at_turnover(t_val, dg)
                co_need[f"{t_name}|{r}|{tag}"] = None if lh is None else round(2 * lh - lam_cu, 3)
    out["cobalt_lambda_condition"] = {
        "lambda_co_computed_eV": lam_c["Co"],
        "lambda_co_computed_provenance": lam_prov["Co"],
        "lambda_co_assumed_eV": LAMBDA_LIT["Co"],
        "lambda_co_assumed_source": "literature value with no primary in the tree (paper Methods names it an assumption)",
        "lambda_co_at_turnover_eV": co_need,
        "lambda_co_at_turnover_adverse_corner_eV": min(v for k, v in co_need.items() if k.startswith("fodft|") and v is not None),
        "lambda_co_at_turnover_key": "<coupling>|<λ(Cu) reading>|<ΔG branch>; the λ(Co) at which the Cu–Co hop reaches "
                                     "turnover (two-sphere λ_hop); null = unreachable at any λ",
    }
    ru35 = next(r for r in json.loads((CACHE / "metal_reorganization.json").read_text())["results"] if r["name"] == "ru")
    out["ru_lambda_nelsen_halves"] = {
        "lambda_1_eV": ru35["lambda_1_eV"], "lambda_2_eV": ru35["lambda_2_eV"],
        "negative_half": bool(min(ru35["lambda_1_eV"], ru35["lambda_2_eV"]) < 0),
        "reading": "a negative Nelsen half means one state's energy at the OTHER state's geometry lies below its own "
                   "optimised one — the optimisation did not find that minimum — so λ(Ru) is indicative, not computed",
    }
    cc = out["cobalt_lambda_condition"]

    # ⛔ Built from the numbers above, never typed: this string is what the docs quote, and the
    # sentence it replaced ("borderline ×1–30") was true only of the ΔG = 0 column.
    ru = out["scenarios"]["Ru-swap (Co→Ru, computed)"]
    WITHDRAWN = "canon λ=0.7 (old assumption)"
    invariant = all(sc["bottleneck_hop_is_branch_invariant"] for k, sc in out["scenarios"].items() if k != WITHDRAWN)
    flips = [f"{b} → {v['bottleneck_hop']}" for b, v in out["scenarios"][WITHDRAWN]["by_dG"].items()
             if v["bottleneck_hop"] != lit["by_dG"][BRANCHES[1]]["bottleneck_hop"]]
    comp = out["scenarios"]["computed λ (B3LYP)"]
    co_lbl = zif["pairs"][0]["label"]
    verdict = (
        f"The bottleneck is {lit['by_dG'][BRANCHES[1]]['bottleneck_hop']}"
        + (", in every ΔG branch of every live scenario" if invariant else
           ", but which hop limits DEPENDS on the ΔG branch — read per row")
        + (f" (the withdrawn λ = 0.7 row differs: {'; '.join(flips)})" if flips else "")
        + f". Its coupling is the two-state diabatisation (24b, t = {t_fo:.4f} eV): the crude ΔSCF value "
        f"({tij_crude['Cu-Co']:.4f} eV) is half an energy difference of "
        f"{out['dscf_coupling_resolution']['pairs'][co_lbl]['delta_E_over_scf_tol']}× the SCF tolerance between two "
        "unconstrained solutions from one start, so it is not used (its table is kept as `scenarios_crude_dscf`). "
        f"Every margin is a BRACKET over the sign of the measured {GAP_EV['Cu-Co']} eV site-energy gap and the λ(Cu) "
        f"reading ({' ⊥ '.join(f'{r} {v}' for r, v in LAMBDA_CU_READINGS.items())} eV); ΔG = 0 is the function's "
        "DEFAULT, not a measurement. The verdict is CONDITIONAL ON λ(Co). At the assumed literature λ(Co) "
        f"{LAMBDA_LIT['Co']} eV (no primary): ×{lit['margin_vs_turnover_adverse']:.2g} … "
        f"×{lit['margin_vs_turnover_favourable']:.3g} (×{lit['margin_vs_turnover_at_dG0']:.2g} at ΔG = 0 on the "
        f"{LAMBDA_CU_BASE} reading). At the computed λ(Co) {lam_c['Co']} eV ({lam_prov['Co']}): "
        f"×{comp['margin_vs_turnover_adverse']:.2g} … ×{comp['margin_vs_turnover_favourable']:.2g} "
        f"(×{comp['margin_vs_turnover_at_dG0']:.2g} at ΔG = 0). Turnover needs λ(Co) ≲ "
        f"{co_need[f'fodft|{LAMBDA_CU_BASE}|dG=0']} eV at ΔG = 0 on the {LAMBDA_CU_BASE} reading and ≲ "
        f"{cc['lambda_co_at_turnover_adverse_corner_eV']} eV at the adverse corner. "
        + ("⚠️ The adverse corner is below turnover on BOTH λ(Co) values — rate-limiting, not borderline. "
           if max(lit["margin_vs_turnover_adverse"], comp["margin_vs_turnover_adverse"]) < 1.0 else "")
        + "The λ(Cu) bracket bounds the READINGS, not the site: both are unconstrained solution couples, and a "
        "framework-held Cu–N4 node can sit below both. "
        f"The Ru-swap reads ×{ru['margin_vs_turnover_adverse']:.2g} … ×{ru['margin_vs_turnover_favourable']:.2g} — "
        "across the λ(Cu) reading only, on the borrowed Cu–Co coupling, because no usable gap or coupling exists for the "
        f"{RU_GAP_REFUSED['pair']} node: {RU_GAP_REFUSED['reason']}; and its λ(Ru) is a sum of Nelsen halves "
        f"{ru35['lambda_1_eV']:.3f} and {ru35['lambda_2_eV']:.3f} eV"
        + (" — one negative — so that margin is indicative only." if out["ru_lambda_nelsen_halves"]["negative_half"]
           else ".")
    )
    out["verdict"] = verdict
    (CACHE / "cathode_ket_lambda.json").write_text(json.dumps(out, indent=2))
    print("\n  " + verdict.replace(". ", ".\n  "))
    print("\n  Mitigations (unchanged in kind): low-λ metal (Ru), conductive-MOF band transport")
    print("  (CHEM.31), or enzyme-free SAC (CHEM.6).")
    print("  saved → cache/dft/cathode_ket_lambda.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
