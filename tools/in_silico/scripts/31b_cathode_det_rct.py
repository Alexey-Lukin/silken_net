#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""31b — cathode DET charge-transfer resistance band (③ borderline, INDICATIVE).

Script 31 models the ANODE EIS (Rct from enzyme j_max). The cathode story is
different: the rate-limiting Cu–Co DET hop is *borderline* (k_DET ~ enzymatic
turnover, λ-sensitive — see SUMMARY §Cathode). One might want a single cathode
"Rct" for the Nyquist prediction, but (00_07, verified 2026-06-06) the borderline
cathode is a **kinetic competition** (k_DET vs turnover), NOT a fixed Rct — and a
surface Rct also scales with the unknown site coverage Γ. So we report a BAND, and
let it make the honest point: the cathode arc size is uncertain by orders of
magnitude, so EIS cannot pin it a priori.

    Laviron surface-confined ET:  R_ct = RT / (n²F²·A·k_DET·Γ)

over a grid of (k_DET scenario × Γ coverage). k_DET scenarios are loaded from the
canon cache (drift-proof): the literature-λ borderline value and the FO-DFT margin
range. Compared against the canon anode Rct (~130 Ω) for context.

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
    fo = klam["fodft_cuco_rigor"]["margin_vs_turnover_by_dG_sign"]
    # k_DET scenarios (s⁻¹) from canon margins × turnover (drift-proof).
    k_scenarios = {
        "lit-λ borderline (×1.4)": klam["scenarios"]["literature λ"]["margin_vs_turnover"] * turnover,
        "FO-DFT low (×0.6)": fo["dG=+gap"] * turnover,
        "FO-DFT mid (×25)": fo["dG=0"] * turnover,
        "FO-DFT high (×730)": fo["dG=-gap"] * turnover,
    }
    # Canon anode Rct for context (from script 31's eis_model, if present).
    anode_rct = None
    eis = KINETICS_DIR / "eis_model.json"
    if eis.exists():
        j = json.loads(eis.read_text())
        anode_rct = j.get("Rct_ohm") or j.get("rct_ohm") or (j.get("parameters", {}) or {}).get("Rct_ohm")

    banner("Cathode DET R_ct band (③ borderline — INDICATIVE)")
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
    print(f"\n  cathode R_ct band: {lo:.3g} – {hi:.3g} Ω  (≈ {hi/lo:.0e}× spread)")
    verdict = (
        f"the cathode DET R_ct is NOT a single value — it spans {lo:.2g}–{hi:.2g} Ω across the borderline "
        f"k_DET (λ/coupling-sensitive) AND the unknown coverage Γ. It can be negligible (fast/dense) or "
        f"comparable to the anode arc (~{anode_rct:.0f} Ω, slow/sparse). → an EIS cathode arc cannot be "
        "predicted a priori; the robust statement stays the KINETIC COMPETITION k_DET ~ turnover (SUMMARY "
        "§Cathode). The decisive test is the measured Ti-coin cathode EIS."
        if anode_rct else
        f"cathode DET R_ct spans {lo:.2g}–{hi:.2g} Ω — borderline-k_DET × unknown-Γ → indicative only; "
        "the robust statement is the kinetic competition k_DET ~ turnover."
    )
    print(f"\n  ⚠️ INDICATIVE — {verdict}")

    out = {
        "method": "Laviron surface-confined R_ct = RT/(n²F²·A·k_DET·Γ); k_DET from canon cache; INDICATIVE",
        "caveat": "borderline k_DET (λ/coupling-sensitive) × unknown Γ → a BAND, not a fixed Rct (00_07): the cathode is a kinetic competition, not a clean Rct",
        "n_electrons": N_E, "A_cm2": A_ELECTRODE, "turnover_s": turnover,
        "k_scenarios_s": k_scenarios, "gamma_grid_mol_cm2": GAMMA_GRID,
        "anode_rct_ohm_context": anode_rct,
        "grid": grid, "rct_band_ohm": [lo, hi], "verdict": verdict,
    }
    outp = KINETICS_DIR / "cathode_det_rct.json"
    outp.write_text(json.dumps(out, indent=2))
    banner(f"✅ saved {outp.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
