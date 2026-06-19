#!/usr/bin/env python
"""
L3 — PCET redox potential of FAD/FADH₂ via the thermodynamic proton reference.

Fixes the earlier invalid attempt that computed H₃O⁺ explicitly in PCM (PCM
oversolvates small ions). The correct approach for a proton-coupled couple is
NOT explicit water — it is the **thermodynamic proton reference**: never
compute H⁺ in DFT, instead add the experimentally-fixed solvated-proton free
energy as a constant.

Couple (2e⁻/2H⁺):  FAD + 2H⁺ + 2e⁻ → FADH₂
  ΔG°(electrons free) = E(FADH₂) − E(FAD) − n_H · G*(H⁺,aq)
  E°_abs = −ΔG° / n_e            (volts, absolute scale)
  E° vs SHE = E°_abs − |SHE_abs|
  E°'(pH)   = E° − (0.05916 · n_H / n_e) · pH      (Nernstian proton term)

Uses the B3LYP/6-31G(d)+PCM single-point energies already cached by script 20
(lumiflavin ox/red) — this is a SCREENING-tier estimate (electronic E as proxy
for G; no ZPE/thermal, MMFF geometry). A publication-grade refinement would
geom-opt both forms + add thermal G at ωB97X (flagged as future work; needs CPU).

Constants (Isse & Gennaro 2010, self-consistent set):
  G_gas(H⁺)            = −6.28  kcal/mol   (Sackur-Tetrode, 1 atm)
  1 atm → 1 M (gas)    = +1.89  kcal/mol
  ΔG*_solv(H⁺)         = −265.9 kcal/mol
  → G*(H⁺,aq,1M)       = −270.29 kcal/mol = −11.72 eV
  |SHE_abs|            = 4.281 V            (consistent with the above)
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, REPO_ROOT
from lib.utils import banner

KCAL_TO_EV = 0.0433641153

# Thermodynamic proton reference (Isse & Gennaro 2010, J. Phys. Chem. B)
G_GAS_H = -6.28          # kcal/mol
GAS_1ATM_TO_1M = 1.89    # kcal/mol
DG_SOLV_H = -265.9       # kcal/mol
G_STAR_H_AQ_EV = (G_GAS_H + GAS_1ATM_TO_1M + DG_SOLV_H) * KCAL_TO_EV  # eV
SHE_ABS_V = 4.281        # absolute potential of SHE (V)

N_E = 2
N_H = 2
NERNST_SLOPE = 0.05916   # V per pH unit at 298 K

# Experimental references for context
EXP_FREE_FLAVIN_PH7_MV = -208   # free FAD/FADH₂ vs NHE @ pH 7 (well-known)
EXP_PROTEIN_BOUND_MV = -265     # GcGDH bound FAD, VERIFIED −0.265 V vs SHE (Schachinger, Ma, Ludwig, Electrochem. Commun. 2023, 146, 107405); 01_03 "+60 mV" was wrong (conflated w/ Os mediator)

OUT_JSON = DFT_CACHE / "pcet_redox_potential.json"


def main() -> int:
    banner("PCET redox potential — FAD/FADH₂ (thermodynamic proton reference)")

    lf = json.loads((DFT_CACHE / "lumiflavin.json").read_text())
    e_ox = lf["ox"]["E_total_Ha"]
    e_red = lf["red"]["E_total_Ha"]
    print(f"  Source: lumiflavin.json ({lf['method']})")
    print(f"  E(FAD, ox)   = {e_ox:.6f} Ha")
    print(f"  E(FADH₂, red)= {e_red:.6f} Ha")
    print(f"  ΔE(red−ox)   = {(e_red - e_ox) * HARTREE_TO_EV:.3f} eV")
    print(f"  G*(H⁺,aq)    = {G_STAR_H_AQ_EV:.3f} eV  |SHE_abs| = {SHE_ABS_V} V")

    de_ev = (e_red - e_ox) * HARTREE_TO_EV
    dG = de_ev - N_H * G_STAR_H_AQ_EV          # electrons free (vacuum 0)
    e_abs = -dG / N_E                           # V (absolute)
    e_vs_she_ph0 = e_abs - SHE_ABS_V            # V vs SHE at pH 0

    banner("Result")
    print(f"  E°_abs            = {e_abs:+.3f} V")
    print(f"  E° vs SHE (pH 0)  = {e_vs_she_ph0 * 1000:+.0f} mV")

    results = {}
    for ph in (0.0, 4.5, 7.0):
        e_ph = e_vs_she_ph0 - NERNST_SLOPE * (N_H / N_E) * ph
        results[f"pH_{ph}"] = round(e_ph * 1000, 1)
        print(f"  E°'(pH {ph:>3}) vs NHE = {e_ph * 1000:+.0f} mV")

    e_ph7 = results["pH_7.0"]
    print()
    print(f"  vs free-flavin exp (pH 7): {EXP_FREE_FLAVIN_PH7_MV} mV "
          f"→ Δ = {e_ph7 - EXP_FREE_FLAVIN_PH7_MV:+.0f} mV")
    print(f"  (protein-bound FAD-GDH is tuned to ~{EXP_PROTEIN_BOUND_MV} mV — "
          f"this is the free cofactor)")

    verdict = abs(e_ph7 - EXP_FREE_FLAVIN_PH7_MV) < 100
    print(f"  Within 100 mV of free-flavin exp: {'✅ YES' if verdict else '⚠️ NO'} "
          f"→ proton-reference PCET is VALID with implicit solvation alone")

    print()
    print("  ⚠️ Screening tier: electronic E as proxy for G (no ZPE/thermal,")
    print("     MMFF geometry). Main uncertainty = SHE_abs convention (±0.15 V).")
    print("     Refinement: geom-opt + thermal G at ωB97X (needs CPU).")

    output = {
        "method": "Thermodynamic proton reference (Isse-Gennaro 2010) on "
                  "B3LYP/6-31G(d)+PCM SP energies (screening tier)",
        "couple": "FAD + 2H+ + 2e- -> FADH2",
        "E_ox_Ha": e_ox,
        "E_red_Ha": e_red,
        "G_star_H_aq_eV": round(G_STAR_H_AQ_EV, 4),
        "SHE_abs_V": SHE_ABS_V,
        "E_abs_V": round(e_abs, 4),
        "E_vs_SHE_mV": dict(results.items()),
        "exp_free_flavin_pH7_mV": EXP_FREE_FLAVIN_PH7_MV,
        "delta_vs_exp_pH7_mV": round(e_ph7 - EXP_FREE_FLAVIN_PH7_MV, 1),
        "valid_proton_reference": bool(verdict),
        "caveats": "Electronic E proxy for G; SHE_abs convention ±0.15 V; "
                   "geom-opt+thermal at wB97X is the publication-grade refinement.",
    }
    OUT_JSON.write_text(json.dumps(output, indent=2))
    banner(f"✅ Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
