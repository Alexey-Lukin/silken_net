#!/usr/bin/env python
"""
HW.24 bake-off — per-alloy native-oxide DET feasibility (Ta DET-risk pre-coin).

Each candidate alloy forms a native passive oxide; enzyme/mediator DET requires the
electron to tunnel through it to the metal. A WIDER band-gap + THICKER oxide → steeper
tunnelling decay → worse DET. This ANALYTICAL model (lit band-gaps + a WKB square-barrier
decay) predicts — BEFORE the coin — that Ta2O5 (wider, thicker, more dielectric than TiO2)
is a DET RISK relative to the TiO2 baseline the Gen 2.0 stack is designed on, and that the
Au-coated coupon (no oxide, metallic) is the DET-electrical CEILING.

Metric = the tunnelling DECAY EXPONENT 2·κ·d (dimensionless; higher = worse DET), normalised
to TiO2. NOT absolute DET rate (real DET is defect-/thin-spot-mediated + bridged by EAAE
roughness + Os-mediator + ZIF — that is why the stack works on TiO2 at all). The RELATIVE
ranking is the robust output; rigorous oxide conduction-band offset = DFT (deferred,
[[feedback_no_df_heavy_metals]]).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import KINETICS_DIR, REPO_ROOT
from lib.utils import banner

OUT_JSON = KINETICS_DIR / "oxide_det_per_alloy.json"

# Native passive-oxide of each alloy's DOMINANT surface oxide (literature). Eg = band-gap (eV),
# d = native passive-layer thickness (nm). The Gen 2.0 DET stack is designed on TiO2 (the baseline
# that works); every other alloy's oxide is compared to it. Au coupon = metallic (no oxide) = ceiling.
OXIDES = {
    "Ti-6Al-4V":         {"oxide": "TiO2",            "Eg_eV": 3.2, "d_nm": 4.0},
    "Ti-6Al-7Nb":        {"oxide": "TiO2(+Nb2O5)",    "Eg_eV": 3.3, "d_nm": 4.0},
    "CP-Ti-Gr4":         {"oxide": "TiO2",            "Eg_eV": 3.2, "d_nm": 3.5},
    "beta-Ti-13Nb-13Zr": {"oxide": "TiO2/Nb2O5/ZrO2", "Eg_eV": 3.6, "d_nm": 4.5},
    "Ta":                {"oxide": "Ta2O5",           "Eg_eV": 4.2, "d_nm": 6.0},
    "Ti-15Zr":           {"oxide": "TiO2/ZrO2",       "Eg_eV": 3.7, "d_nm": 4.0},
    "Au-coating":        {"oxide": "none (noble)",    "Eg_eV": 0.0, "d_nm": 0.0},
}

M_E = 9.10938e-31    # kg
HBAR = 1.054572e-34  # J·s
Q = 1.602177e-19     # C


def tunnel_decay(d_nm: float, barrier_eV: float) -> float:
    """WKB square-barrier decay exponent 2·κ·d (dimensionless). κ = sqrt(2 m φ)/ħ.
    Metallic surface (d=0) → 0 (no barrier = DET ceiling)."""
    if d_nm <= 0:
        return 0.0
    phi = max(barrier_eV, 0.1) * Q
    kappa = np.sqrt(2.0 * M_E * phi) / HBAR          # 1/m
    return float(2.0 * kappa * d_nm * 1e-9)


def main() -> int:
    banner("HW.24 bake-off — per-alloy oxide-DET feasibility (WKB, analytical)")

    # Barrier φ ≈ Eg/2 (electron from the Fermi level sees ~half the gap to the oxide conduction
    # band — a simple proxy; rigorous = oxide CB offset, DFT). Decay normalised to TiO2 (4V baseline).
    results = {}
    for alloy, ox in OXIDES.items():
        phi = ox["Eg_eV"] / 2.0
        decay = tunnel_decay(ox["d_nm"], phi)
        results[alloy] = {**ox, "barrier_eV": round(phi, 2), "tunnel_decay": round(decay, 2)}

    base = results["Ti-6Al-4V"]["tunnel_decay"]
    print(f"  {'alloy':>20s} {'oxide':>16s} {'Eg':>5s} {'d(nm)':>6s} {'decay':>6s} {'vs 4V':>6s} {'flag':>6s}")
    print(f"  {'-'*72}")
    for alloy, r in results.items():
        ratio = r["tunnel_decay"] / base if base > 0 else 0.0
        r["det_vs_tio2"] = round(ratio, 2)
        r["det_flag"] = (
            "ceil" if r["d_nm"] == 0 else
            "RISK" if ratio >= 1.4 else
            "↑" if ratio >= 1.15 else "ok"
        )
        print(f"  {alloy:>20s} {r['oxide']:>16s} {r['Eg_eV']:>5.1f} {r['d_nm']:>6.1f} "
              f"{r['tunnel_decay']:>6.1f} {ratio:>5.2f}x {r['det_flag']:>6s}")

    print()
    print("  Au = DET-electrical CEILING (no oxide). Ta2O5 (wider+thicker) = DET RISK vs the TiO2-")
    print("  designed Gen 2.0 stack → Ta benchmark tests biocompat ceiling but likely loses on DET.")
    print("  WKB decay-exponent (relative); absolute DET is defect-/mediator-bridged. Coin confirms.")

    OUT_JSON.write_text(json.dumps(results, indent=2))
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
