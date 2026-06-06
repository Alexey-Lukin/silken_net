#!/usr/bin/env python3
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
from lib.dft_utils import marcus_rate

CACHE = Path(__file__).resolve().parents[1] / "cache" / "dft"
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


def _load_lambda_computed() -> dict[str, float]:
    """Computed λ per metal (script 35). Co = ammine (co_nh3) as the ZIF N-donor
    analogue; Cu absent (Cu(I) d¹⁰ hexa-aqua opt is unphysical → use literature)."""
    res = json.loads((CACHE / "metal_reorganization.json").read_text())["results"]
    by_name = {r["name"]: float(r["lambda_use_eV"]) for r in res}
    return {
        "Cu": LAMBDA_LIT["Cu"],                       # not computed (see docstring)
        "Co": by_name.get("co_nh3", by_name.get("co")),
        "Ce": by_name.get("ce"),
        "Ru": by_name.get("ru"),
    }


def _two_sphere(la: float, lb: float) -> float:
    return 0.5 * (la + lb)


def main() -> int:
    tij = _load_tij()
    lam_c = _load_lambda_computed()
    print("=== geometry-corrected t_ij (script 24, clash-free cluster) ===")
    for h, t in tij.items():
        print(f"  {h:8s} t_ij = {t:.5f} eV")

    # Each scenario maps a hop → its two-sphere λ. The Ru-swap replaces the Co node.
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

    out = {"t_ij_eV": tij, "lambda_computed_eV": lam_c,
           "lambda_lit_eV": LAMBDA_LIT, "turnover_s": TURNOVER_S, "scenarios": {}}
    print(f"\n  {'scenario':32s} {'k(Cu-Co)':>10} {'k(Co-Ce)':>10} {'k(Ce-C)':>10}"
          f" {'BOTTLENECK':>11} {'vs turnover':>12}")
    for name, lam in scenarios.items():
        ks = {h: marcus_rate(t, lambda_reorg=lam[{"Cu-Co": "Cu-Co", "Co-Ce": "Co-Ce",
                                                   "Ce-C": "Ce-C"}[h]])
              for h, t in tij.items()}
        bottleneck = min(ks.values())
        margin = bottleneck / TURNOVER_S
        out["scenarios"][name] = {"lambda_hop_eV": lam, "k_ET_per_s": ks,
                                  "bottleneck_s": bottleneck, "margin_vs_turnover": margin}
        print(f"  {name:32s} {ks['Cu-Co']:10.2e} {ks['Co-Ce']:10.2e} {ks['Ce-C']:10.2e}"
              f" {bottleneck:11.2e} {'×'+format(margin, '.1e'):>12}")

    # FO-DFT rigor (script 24b): the Cu-Co bottleneck with the two-state coupling t_ij + the computed
    # site-energy gap, vs the crude ΔSCF t_ij. t_ij is ~4× crude (k ~18×), but the 0.18 eV site-gap
    # swings the margin by its sign → the borderline/sensitive verdict is robust to the coupling
    # method (not a crude-t_ij artifact); the old ~10⁵× is firmly excluded either way.
    fo = json.loads((CACHE / "fodft_coupling.json").read_text())
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

    (CACHE / "cathode_ket_lambda.json").write_text(json.dumps(out, indent=2))
    print("\n  bottleneck hop = Cu-Co (smallest t_ij after the geometry fix).")
    print("  → the old ~10⁵× margin was a geometry+λ artifact; realistic λ leaves the")
    print("    cathode borderline (×1–30) — possibly co-limiting. Mitigation: low-λ metal")
    print("    (Ru), conductive-MOF band transport (CHEM.31), or enzyme-free SAC (CHEM.6).")
    print("  saved → cache/dft/cathode_ket_lambda.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
