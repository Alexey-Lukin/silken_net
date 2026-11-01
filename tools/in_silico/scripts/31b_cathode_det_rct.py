#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""31b — cathode DET charge-transfer resistance band (③, INDICATIVE).

Script 31 models the ANODE EIS (Rct from enzyme j_max). The cathode story is
different: the Cu–Co DET hop is a BRACKET whose position against enzymatic turnover is conditional
on λ(Co) (gap sign × λ(Cu) reading × λ(Co) value — see SUMMARY §Cathode). One might want a single cathode
"Rct" for the Nyquist prediction, but (00_07, verified 2026-06-06) the cathode
is a **kinetic competition** (k_DET vs turnover), NOT a fixed Rct — and a
surface Rct also scales with the unknown site coverage Γ. So we report a BAND, and
let it make the honest point: the cathode arc size is uncertain by orders of
magnitude, so EIS cannot pin it a priori.

    Laviron surface-confined ET:  R_ct = RT / (n²F²·A·k_DET·Γ)

over a grid of (k_DET scenario × Γ coverage). k_DET scenarios are loaded from the
canon cache (drift-proof): the corners and ΔG = 0 reading of the literature-λ(Co) and
the computed-λ(Co) brackets, both on the FO-DFT coupling. Compared against the canon anode Rct (read at run time from script 31's cache) for context.

Run:  mamba run -n silken_md python tools/in_silico/scripts/31b_cathode_det_rct.py
Cost: ~instant (analytical).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import A_ELECTRODE, DFT_CACHE, F_CONST, KINETICS_DIR, R_GAS, REPO_ROOT, TEMPERATURE_K
from lib.utils import banner

N_E = 1            # single-electron DET hop
T = TEMPERATURE_K

# Site coverage Γ (mol/cm²) — unknown for the ZIF nanozyme; honest broad band:
# sparse sub-monolayer (~1e-12) → dense nanozyme monolayer (~1e-10).
GAMMA_GRID = {"sparse 1e-12": 1e-12, "monolayer 1e-11": 1e-11, "dense 1e-10": 1e-10}


def rct(k_det: float, gamma: float) -> float:
    return R_GAS * T / (N_E ** 2 * F_CONST ** 2 * A_ELECTRODE * k_det * gamma)


def main() -> int:
    klam = json.loads((DFT_CACHE / "cathode_ket_lambda.json").read_text())
    turnover = klam["turnover_s"]
    lit = klam["scenarios"]["literature λ"]
    comp = klam["scenarios"]["computed λ (B3LYP)"]
    # k_DET scenarios (s⁻¹) from canon margins × turnover (drift-proof). Each is a CORNER of the
    # bracket 25 publishes (gap sign × λ(Cu) reading) or its ΔG = 0 reading — which 25 names a
    # default, not a measurement, so it rides here as a label, never as «the» value. Labels are
    # built from the cache: typed «(×1.4)» labels outlived the number they named once already.
    # ⊕ 2026-10-15 (self-review clusters 1 · 8): 25's table runs on the FO-DFT coupling, so the second axis here is no
    # longer the coupling method but λ(Co) — the assumed literature value ⊥ the computed one, which the verdict is
    # conditional on.
    margins = {
        "lit-λ(Co) adverse corner": lit["margin_vs_turnover_adverse"],
        "lit-λ(Co) ΔG=0 (default)": lit["margin_vs_turnover_at_dG0"],
        "lit-λ(Co) favourable corner": lit["margin_vs_turnover_favourable"],
        "computed-λ(Co) adverse corner": comp["margin_vs_turnover_adverse"],
        "computed-λ(Co) ΔG=0 (default)": comp["margin_vs_turnover_at_dG0"],
        "computed-λ(Co) favourable corner": comp["margin_vs_turnover_favourable"],
    }
    k_scenarios = {f"{name} (×{m:.2g})": m * turnover for name, m in margins.items()}
    # Canon anode Rct for context (from script 31's eis_model, if present).
    anode_rct = None
    eis = KINETICS_DIR / "eis_model.json"
    if eis.exists():
        j = json.loads(eis.read_text())
        anode_rct = j.get("Rct_ohm") or j.get("rct_ohm") or (j.get("parameters", {}) or {}).get("Rct_ohm")

    banner("Cathode DET R_ct band (③ bracket — INDICATIVE)")
    print(f"  R_ct = RT/(n²F²·A·k_DET·Γ), n={N_E}, A={A_ELECTRODE} cm², turnover={turnover:.0f} s⁻¹")
    if anode_rct:
        print(f"  (context: canon anode R_ct ≈ {anode_rct:.0f} Ω)")
    print(f"\n  {'k_DET scenario':>26} {'k (s⁻¹)':>12} " + " ".join(f"{g:>14}" for g in GAMMA_GRID) )
    print("  " + "-" * 86)

    grid = []
    all_rct = []
    for kname, k in k_scenarios.items():
        row = []
        for gname, gamma in GAMMA_GRID.items():
            r = rct(k, gamma)
            row.append(r)
            all_rct.append(r)
            grid.append({"k_label": kname, "k_det_s": k, "gamma_label": gname, "gamma_mol_cm2": gamma, "rct_ohm": r})
        print(f"  {kname:>26} {k:>12.0f} " + " ".join(f"{v:>14.3g}" for v in row))

    lo, hi = min(all_rct), max(all_rct)
    # ⊕ 2026-11-01 (⚖️ founder: the verdict is conditional on λ(Cu) too): the band above and the overlap of the two λ(Co)
    # branches are on the two SOLUTION readings of λ(Cu). A lower λ(Cu) (azurin's protein-held one is 25's example) makes
    # the computed-λ(Co) chain faster, so its R_ct reaches far below the overlap — but no lower than the FLOOR the
    # λ(Cu)-independent hops set (25 → `copper_lambda_condition.chain_at_lambda_cu_zero`): an arc below the overlap then
    # excludes only «computed λ(Co) on a solution-reading λ(Cu)», and only an arc below the floor still excludes the
    # computed λ(Co) at any λ(Cu). Printed, so the text is never hand-derived.
    overlap = [min(g["rct_ohm"] for g in grid if g["k_label"].startswith("computed")),
               max(g["rct_ohm"] for g in grid if g["k_label"].startswith("lit"))]
    sens = klam["other_hops_threshold_sensitivity"]
    k_az = [v["margin_vs_turnover"] * turnover
            for v in sens["by_scenario"]["computed λ (B3LYP)"]["verdict_at_azurin_by_dG"].values()]
    rct_az = [min(rct(max(k_az), g) for g in GAMMA_GRID.values()), max(rct(min(k_az), g) for g in GAMMA_GRID.values())]
    zero = klam["copper_lambda_condition"]["chain_at_lambda_cu_zero"]["computed λ (B3LYP)"]
    fast = max(zero.values(), key=lambda v: v["margin_vs_turnover"])
    rct_floor = min(rct(fast["margin_vs_turnover"] * turnover, g) for g in GAMMA_GRID.values())
    print(f"  λ(Co) branches overlap (solution readings of λ(Cu)): {overlap[0]:.3g} – {overlap[1]:.3g} Ω; "
          f"computed λ(Co) at λ(Cu) {sens['lambda_cu_azurin_eV']} eV: {rct_az[0]:.3g} – {rct_az[1]:.3g} Ω; "
          f"its floor at any λ(Cu): {rct_floor:.3g} Ω ({fast['binding_hop']})")
    print(f"\n  cathode R_ct band: {lo:.3g} – {hi:.3g} Ω  (≈ {hi/lo:.0e}× spread)")
    if anode_rct:
        # The comparison with the anode is COMPUTED: a typed «comparable to the anode» survived the
        # 2026-09-21 bracket, whose adverse corner put the slow end orders of magnitude past it.
        ratio_hi = hi / anode_rct
        slow_end = (f"exceeds the anode arc (~{anode_rct:.0f} Ω) up to ×{ratio_hi:.2g} (slow/sparse)"
                    if ratio_hi > 3 else
                    f"is comparable to the anode arc (~{anode_rct:.0f} Ω, slow/sparse)")
    verdict = (
        f"the cathode DET R_ct is NOT a single value — it spans {lo:.2g}–{hi:.2g} Ω across the k_DET "
        f"bracket (gap sign × λ(Cu) reading × λ(Co) value) AND the unknown coverage Γ. It can be "
        f"negligible (fast/dense) or it {slow_end}. → an EIS cathode arc cannot be "
        "predicted a priori; the robust statement stays the KINETIC COMPETITION k_DET vs turnover (SUMMARY "
        "§Cathode). The decisive test is the measured Ti-coin cathode EIS."
        if anode_rct else
        f"cathode DET R_ct spans {lo:.2g}–{hi:.2g} Ω — k_DET bracket × unknown-Γ → indicative only; "
        "the robust statement is the kinetic competition k_DET against turnover, itself conditional on λ(Co) and λ(Cu)."
    )
    print(f"\n  ⚠️ INDICATIVE — {verdict}")

    out = {
        "method": "Laviron surface-confined R_ct = RT/(n²F²·A·k_DET·Γ); k_DET = the corners of the 25 bracket; INDICATIVE",
        "caveat": "k_DET bracket (gap sign × λ(Cu) reading × λ(Co) value) × unknown Γ → a BAND, not a fixed Rct (00_07): the cathode is a kinetic competition, not a clean Rct",
        "n_electrons": N_E, "A_cm2": A_ELECTRODE, "turnover_s": turnover,
        "k_scenarios_s": k_scenarios, "gamma_grid_mol_cm2": GAMMA_GRID,
        "anode_rct_ohm_context": anode_rct,
        "grid": grid, "rct_band_ohm": [lo, hi],
        "lambda_co_branch_overlap_ohm": overlap,
        "lambda_co_branch_overlap_reading": "computed-λ(Co) minimum ⊥ literature-λ(Co) maximum, both on the two "
                                            "solution readings of λ(Cu); outside it an arc excludes one λ(Co) branch "
                                            "ON THOSE READINGS",
        "computed_lambda_co_at_protein_held_lambda_cu": {
            "lambda_cu_eV": sens["lambda_cu_azurin_eV"], "rct_ohm": rct_az,
            "reading": "the computed-λ(Co) chain at azurin's λ(Cu) (25's sensitivity example, not this site's value): "
                       "its low end lies far below the overlap"},
        "computed_lambda_co_floor_at_any_lambda_cu": {
            "rct_ohm": rct_floor, "binding_hop": fast["binding_hop"],
            "reading": "the lowest R_ct the computed-λ(Co) chain reaches at ANY λ(Cu) ≥ 0, at the densest Γ of the grid: the "
                       "λ(Cu)-independent hops cap its rate — the Co–Ce hop on its shipped coupling at an assumed ΔG = 0 "
                       "(25 → `co_ce_ceiling_that_erases_the_straddle`) — so on that hop only an arc below this still excludes "
                       "the computed λ(Co) whatever λ(Cu) is"},
        "verdict": verdict,
    }
    outp = KINETICS_DIR / "cathode_det_rct.json"
    outp.write_text(json.dumps(out, indent=2))
    banner(f"✅ saved {outp.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
