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
assumed λ = 0.7 eV. With literature/computed λ the Cu–Co hop (the new bottleneck
after the geometry fix shrank its t_ij 0.033 → 0.0013 eV) falls to ~turnover;
a Co→Ru swap (computed λ_Ru = 0.78) restores only a modest ×30 margin because
Cu(II/I) keeps a large λ. Compute-light: reads cached JSON, runs no DFT.

Run:  python tools/in_silico/scripts/25_cathode_ket_lambda.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE as CACHE
from lib.dft_utils import marcus_rate

TURNOVER_S = 1.0e3  # enzymatic turnover ~10³ s⁻¹ (the rate the cathode must beat)

# Literature self-exchange reorganization energies (eV) for the aqua/ammine couples
# — textbook Marcus values; the first-row/Cu couples are intrinsically large.
LAMBDA_LIT = {"Cu": 2.0, "Co": 1.4, "Ce": 1.0, "Ru": 0.8}


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

    Not every entry is computed, and the key name alone says the opposite. Script 35
    has no Cu row — Cu(I) d¹⁰ hexa-aqua optimisation is unphysical — so Cu falls back
    to `LAMBDA_LIT`. The docstring knew that; the emitted cache did not, and the cache
    is what the canon quotes. The returned provenance map rides beside the numbers so
    a reader of the JSON sees which half is a measurement (the absence is DRAWN, not
    left to a default that reads like a result).
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
    provenance = {
        "Cu": "LITERATURE, NOT COMPUTED — script 35 has no Cu row (Cu(I) d¹⁰ hexa-aqua "
              "optimisation is unphysical); this is LAMBDA_LIT['Cu']",
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
    # MAGNITUDE only. The Mulliken-Hush diabatisation returns |ΔE| between two diabatic states;
    # which of them is the donor on the cathode's electron path is NOT fixed by that calculation,
    # so the sign stays unmeasured and both ends are carried (§When Modifying #11).
    GAP_EV = {"Cu-Co": float(fo["site_energy_gap_eV"])}
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
    scenarios = {
        "canon λ=0.7 (old assumption)": {
            "Cu-Co": 0.7, "Co-Ce": 0.7, "Ce-C": 0.7},
        "literature λ": {
            "Cu-Co": _two_sphere(LAMBDA_LIT["Cu"], LAMBDA_LIT["Co"]),
            "Co-Ce": _two_sphere(LAMBDA_LIT["Co"], LAMBDA_LIT["Ce"]),
            "Ce-C": LAMBDA_LIT["Ce"]},
        "computed λ (B3LYP, Co over-est)": {
            "Cu-Co": _two_sphere(lam_c["Cu"], lam_c["Co"]),
            "Co-Ce": _two_sphere(lam_c["Co"], lam_c["Ce"]),
            "Ce-C": lam_c["Ce"]},
        "Ru-swap (Co→Ru, computed)": {
            "Cu-Co": _two_sphere(lam_c["Cu"], lam_c["Ru"]),   # Cu–Ru node
            "Co-Ce": _two_sphere(lam_c["Ru"], lam_c["Ce"]),   # Ru–Ce node
            "Ce-C": lam_c["Ce"]},
    }
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

    out = {"t_ij_eV": tij, "lambda_computed_eV": lam_c,
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
                            "the ADVERSE reading, cited (in-silico §When Modifying #11). "
                            "`margin_vs_turnover_at_dG0` is kept so the pre-2026-09-21 published "
                            "number stays traceable, NOT so it can be quoted",
           "scenarios": {}}

    print(f"\n  {'scenario':32s} {'BOTTLENECK':>11} {'adverse':>11} {'ΔG=0':>11} {'favourable':>11}")
    for name, lam in scenarios.items():
        per_branch, ident = {}, NODE_IDENTITY.get(name, {})
        for label in BRANCHES:
            dg = _dg(name, _BRANCH_KEY[label])
            ks = {h: marcus_rate(t, lam[h], dg[h]) for h, t in tij.items()}
            hop = min(ks, key=ks.get)
            per_branch[label] = {
                "dG_eV": dg, "k_ET_per_s": ks, "bottleneck_hop": ident.get(hop, hop),
                "bottleneck_s": ks[hop], "margin_vs_turnover": ks[hop] / TURNOVER_S}
        measured = _measured_hops(name)
        adverse, zero, fav = (per_branch[b] for b in BRANCHES)
        out["scenarios"][name] = {
            "lambda_hop_eV": lam,
            "node_identity": {h: ident.get(h, h) for h in tij},
            "hops_with_a_measured_gap": measured,
            "driving_force_measured_for_bottleneck": adverse["bottleneck_hop"] in
            [ident.get(h, h) for h in measured],
            "by_dG": per_branch,
            "margin_vs_turnover_adverse": adverse["margin_vs_turnover"],
            "margin_vs_turnover_at_dG0": zero["margin_vs_turnover"],
            "margin_vs_turnover_favourable": fav["margin_vs_turnover"],
            "bottleneck_hop_is_branch_invariant":
                len({b["bottleneck_hop"] for b in per_branch.values()}) == 1,
        }
        flag = "" if measured else "   [no measured ΔG on any hop — all three columns are ΔG=0]"
        print(f"  {name:32s} {adverse['bottleneck_hop']:>11}"
              f" {'×' + format(adverse['margin_vs_turnover'], '.2g'):>11}"
              f" {'×' + format(zero['margin_vs_turnover'], '.2g'):>11}"
              f" {'×' + format(fav['margin_vs_turnover'], '.2g'):>11}{flag}")

    # FO-DFT rigor (script 24b): the same bottleneck with the two-state coupling instead of the
    # crude ΔSCF one. Kept as its own block because it answers a DIFFERENT question — whether the
    # verdict survives the coupling METHOD — while the table above answers it across λ.
    t_fo, dg_fo = fo["t_ij_eV"], fo["site_energy_gap_eV"]
    lam_lit = _two_sphere(LAMBDA_LIT["Cu"], LAMBDA_LIT["Co"])
    fo_margin = {tag: marcus_rate(t_fo, lam_lit, dg) / TURNOVER_S
                 for tag, dg in (("dG=0", 0.0), ("dG=+gap", dg_fo), ("dG=-gap", -dg_fo))}
    out["fodft_cuco_rigor"] = {
        "t_ij_eV": t_fo, "t_ij_crude_eV": fo["t_ij_crude_script24_eV"], "site_gap_eV": dg_fo,
        "lambda_hop_eV": lam_lit,
        "margin_vs_turnover_by_dG_sign": {k: round(v, 3) for k, v in fo_margin.items()}}
    print(f"\n  FO-DFT rigor (Cu-Co t={t_fo:.5f} vs crude {fo['t_ij_crude_script24_eV']:.5f}, "
          f"gap {dg_fo} eV) @ lit-λ {lam_lit}:")
    for tag, m in fo_margin.items():
        print(f"    {tag:9s} ×{m:.2g}")

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
        "at_literature_lambda_crude_t": round(lit["margin_vs_turnover_adverse"] ** -0.5, 3),
        "at_literature_lambda_fodft_t": round(fo_margin["dG=+gap"] ** -0.5, 3),
        "judge_against": "at_literature_lambda_fodft_t — the rigorous coupling, and the scale the "
                         "canon quotes; the crude row exists so each published t_ij scale carries "
                         "its OWN acceptance number instead of one being read onto the other",
    }
    print("\n  coupling gain needed to reach turnover (adverse end, k ∝ |t|²):")
    for k in ("at_literature_lambda_crude_t", "at_literature_lambda_fodft_t"):
        print(f"    {k:32s} ×{out['coupling_gain_to_reach_turnover'][k]}")

    # ⛔ Built from the numbers above, never typed: this string is what the docs quote, and the
    # sentence it replaced ("borderline ×1–30") was true only of the ΔG = 0 column.
    ru = out["scenarios"]["Ru-swap (Co→Ru, computed)"]
    invariant = all(sc["bottleneck_hop_is_branch_invariant"] for sc in out["scenarios"].values())
    verdict = (
        f"The bottleneck is {lit['by_dG'][BRANCHES[1]]['bottleneck_hop']} (smallest t_ij after the "
        f"geometry fix)"
        + (", and it stays the bottleneck in every ΔG branch of every scenario"
           if invariant else ", but which hop limits DEPENDS on the ΔG branch — read per row")
        + f". At literature λ the margin is a BRACKET over the sign of the measured "
        f"{GAP_EV['Cu-Co']} eV site-energy gap: "
        f"×{lit['margin_vs_turnover_adverse']:.2g} (adverse, uphill) … "
        f"×{lit['margin_vs_turnover_favourable']:.2g} (favourable, downhill), with "
        f"×{lit['margin_vs_turnover_at_dG0']:.2g} at ΔG = 0 — and ΔG = 0 is the function's DEFAULT, "
        "not a measurement, which is how it came to be published as the margin. ⚠️ The adverse "
        "reading puts the cathode BELOW enzymatic turnover rather than above it — rate-limiting, "
        "not borderline; it is quoted as a margin (×0.032) and never as its reciprocal, because "
        "the reciprocal collides numerically with the Ru-swap margin below and means the opposite. "
        f"The Ru-swap mitigation reads ×{ru['margin_vs_turnover_at_dG0']:.2g}, but on ALL THREE "
        "columns alike, because no usable gap exists for the "
        f"{RU_GAP_REFUSED['pair']} node: {RU_GAP_REFUSED['reason']}. So the Ru lever's driving "
        "force is unmeasured by construction, and its margin is a ΔG = 0 reading."
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
