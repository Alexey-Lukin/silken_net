#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""L3 task ① — Os-mediator structure-property series (full Hammett range).

Computes the Os(III)+e⁻→Os(II) ΔSCF reduction energy for cis-[Os(4,4'-X-bpy)₂(1-MeIm)Cl]ⁿ⁺
across a 4,4'-substituent series at CONSTANT charge (+1/+2), isolating the
electronic effect (no charge change → no differential-PCM confounder; that is ②).
Establishes (a) the Hammett LFER for the Os(III/II) potential and (b) the
cascade-alignment design rule Δ = HOMO(FADH₂) − LUMO(Os III) vs substituent.

Pre-check (dmbpy/bpy/dcbpy) PASSED 2026-06-05: monotonic with σ, reproduces 21b
(Δ=0.000). The LFER slope is COMPUTED here (not hardcoded) over the linear-regime
fit-set (REF_LFER_SET) and written to results["lfer"] — the single source the
figure (60), table (61) and prose all read, so the number cannot drift.

PREDICTION (fixed): ΔE_red decreases (E° rises) and the cascade Δ rises toward 0
(less uphill) as σ_para increases (electron-withdrawing 4,4'-substituents).

Method: B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM, vertical ΔSCF, level_shift OFF (21b-faithful).
Sequential single process (feedback_dft_sequential). Cache-skip: complexes already
present + converged in os_mediator_series.json are reused (no recompute). Cascade Δ
uses FADH₂ HOMO from dft/lumiflavin.json. Numbers feed SUMMARY.md (One-Home) once done.

Run:  conda activate silken_md
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py

ωB97X tier of the σ-axis EXTREMES (⚖️ founder 2026-10-02, 00_07 HW.5.IS; question and cost — PIPELINE_STATUS ①):
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py wb97x [nh2 no2 nme2]
21f's own ωB97X tier (imported) on the named complexes only, into its OWN cache (OUT_WB97X) at full precision,
written after EACH state — so a stop costs one SCF, not the night. Refuses any PySCF but the RECORDED one: the
dmbpy and bpy ωB97X points it is compared with were computed there, and a lock run would put a second cavity
convention into the same table. ≈ 8–29 h per complex (×23–46 the B3LYP pair) — one per night, nothing else heavy.
CAN show: whether ωB97X keeps the B3LYP offset (≈ +0.138 eV on the dmbpy/bpy pair) at the donor plateau and the
acceptor end. CANNOT show: an adiabatic or speciation effect (vertical, chloro form only), nor a new cascade
verdict — the authoritative reading stays the verified E°s.
"""
from __future__ import annotations

import importlib.util
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT
from lib.dft_utils import dft_singlepoint
from lib.os_geometry import BPY_SMILES, DCBPY_SMILES, DMBPY_SMILES, build_os_complex, write_xyz
from lib.utils import banner

# 4,4'-X-2,2'-bipyridine series, ordered by Hammett σ_para (donor → acceptor).
# The σ_para values are a NAMED ASSUMPTION (paper §2.3, 09_references disposition route (b), 2026-10-02):
# the conventional tabulated constants, as compiled by Hansch, Leo & Taft (Chem. Rev. 1991, 91, 165 —
# Crossref-confirmed, the values NOT checked against its full text, which is paywalled). The fitted slope
# inherits them; the design rule rests on the series ORDER, which a revision of a few hundredths does not move.
# Each X-bpy has exactly 2 aromatic ring N (substituent N of NMe₂/NH₂/NO₂ is
# non-aromatic → excluded by build_chelate's ring-N filter). Constant charge +1/+2.
SERIES = [
    ("nme2", "CN(C)c1ccnc(-c2cc(N(C)C)ccn2)c1", -0.83, "4,4'-bis(dimethylamino) (strong donor)"),
    ("nh2", "Nc1ccnc(-c2cc(N)ccn2)c1", -0.66, "4,4'-diamino (donor)"),
    ("ome", "COc1ccnc(-c2cc(OC)ccn2)c1", -0.27, "4,4'-dimethoxy (donor)"),
    ("dmbpy", DMBPY_SMILES, -0.17, "4,4'-dimethyl (weak donor)"),
    ("bpy", BPY_SMILES, 0.00, "parent (reproduces 21b)"),
    ("dcbpy", DCBPY_SMILES, 0.45, "4,4'-dicarboxy (acceptor)"),
    ("no2", "O=[N+]([O-])c1ccnc(-c2cc([N+](=O)[O-])ccn2)c1", 0.78, "4,4'-dinitro (strong acceptor)"),
    # CHEM.23: NO₂ is electrochemically UNSTABLE (reduces NO₂→NHOH→NH₂ on Os cycling at
    # pH 4.5 → degrades to the donor-saturated WORST cascade). Inert high-σ acceptors that
    # give the same LUMO lowering without degrading over 20 yr:
    ("cf3", "FC(F)(F)c1ccnc(-c2cc(C(F)(F)F)ccn2)c1", 0.54, "4,4'-bis(CF₃) (inert acceptor — CHEM.23)"),
    ("so2cf3", "O=S(=O)(C(F)(F)F)c1ccnc(-c2cc(S(=O)(=O)C(F)(F)F)ccn2)c1", 0.96, "4,4'-bis(triflyl SO₂CF₃) (inert strong acceptor — CHEM.23)"),
]

REF_21B = {"os2_HOMO": -4.875, "os2_LUMO": -2.156, "os3_HOMO": -6.359, "os3_LUMO": -4.228}

# Canonical Hammett LFER fit-set = classic monosubstituents OMe→NO₂ (the linear regime).
# EXCLUDED (overlaid as called-out points, NOT fitted): NMe₂/NH₂ (σ⁻ donor-resonance
# saturation, plateau ~−3.91 eV) and the inert CF₃-family design picks CF₃/SO₂CF₃
# (high-σ flattening). Must stay identical to the fit-set in 60_paper_figures.py.
REF_LFER_SET = ["ome", "dmbpy", "bpy", "dcbpy", "no2"]
OUT = DFT_CACHE / "os_mediator_series.json"
OUT_WB97X = DFT_CACHE / "os_mediator_series_wb97x.json"   # ωB97X extremes — its own cache (one cache per model)
WB97X_EXTREMES = ["nh2", "no2", "nme2"]   # donor plateau pair + acceptor end, cheapest first (⚖️ 2026-10-02)


def _lfer_fit(sigmas: list[float], energies: list[float]) -> dict:
    """Least-squares ΔE_red-vs-σ slope + R² (pure-python, no numpy dep)."""
    n = len(sigmas)
    sx, sy = sum(sigmas), sum(energies)
    sxx = sum(s * s for s in sigmas)
    sxy = sum(s * e for s, e in zip(sigmas, energies, strict=True))
    slope = (n * sxy - sx * sy) / (n * sxx - sx * sx)
    intercept = (sy - slope * sx) / n
    ybar = sy / n
    ss_tot = sum((e - ybar) ** 2 for e in energies)
    ss_res = sum((e - (slope * s + intercept)) ** 2 for s, e in zip(sigmas, energies, strict=True))
    r2 = 1.0 - ss_res / ss_tot
    return {"slope_eV_per_sigma": round(slope, 4), "intercept_eV": round(intercept, 4),
            "r2": round(r2, 4), "n": n}


def _load_cache() -> dict:
    if not OUT.exists():
        return {}
    try:
        old = json.loads(OUT.read_text(encoding="utf-8"))
        return {c["name"]: c for c in old.get("complexes", []) if c.get("converged")}
    except Exception:
        return {}


def main() -> int:
    cached = _load_cache()
    results = {
        "method": "B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM(water) vertical ΔSCF",
        "model": "cis-[Os(4,4'-X-bpy)2(1-MeIm)Cl]^+/2+ — constant charge; E° + cascade vs Hammett σ_para",
        "complexes": [],
    }

    for name, smi, sigma, desc in SERIES:
        if name in cached:
            banner(f"① {name}  (σ={sigma:+.2f}) — reused from cache")
            results["complexes"].append(cached[name])
            continue
        banner(f"① {name}  (σ_para={sigma:+.2f}, {desc})")
        atoms, info = build_os_complex(bpy_smiles=smi)
        print(f"  geometry: {info['n_atoms']} atoms, min {info['min_contact_A']} Å, "
              f"Os-coord {info['os_coord_distances_A']}")
        write_xyz(atoms, LIGANDS_DIR / f"os_{name}_meim_cl.xyz",
                  f"cis-[Os({name})2(1-MeIm)Cl] programmatic octahedral")
        os2 = dft_singlepoint(atoms, charge=1, spin=0, label=f"Os(II) {name}")
        print(f"  Os(II)  E={os2['E_total_Ha']:.6f} Ha  HOMO={os2['HOMO_eV']:.3f}  "
              f"LUMO={os2['LUMO_eV']:.3f} eV  ({os2['wall_seconds']}s, conv={os2['converged']})")
        os3 = dft_singlepoint(atoms, charge=2, spin=1, label=f"Os(III) {name}")
        print(f"  Os(III) E={os3['E_total_Ha']:.6f} Ha  HOMO={os3['HOMO_eV']:.3f}  "
              f"LUMO={os3['LUMO_eV']:.3f} eV  ({os3['wall_seconds']}s, conv={os3['converged']})")
        dE_red = (os2["E_total_Ha"] - os3["E_total_Ha"]) * HARTREE_TO_EV
        print(f"  ΔE_red(III→II) = {dE_red:+.4f} eV")
        if name == "bpy":
            d = max(abs(os2["HOMO_eV"] - REF_21B["os2_HOMO"]), abs(os3["LUMO_eV"] - REF_21B["os3_LUMO"]))
            print(f"  ↳ 21b reproduction: max|Δ|={d:.3f} eV {'✅' if d < 0.05 else '❌ DIVERGES'}")
            results["reproduces_21b"] = d < 0.05
        results["complexes"].append({
            "name": name, "sigma_para": sigma, "desc": desc, "geometry": info,
            "os2": os2, "os3": os3, "dE_red_eV": dE_red,
            "converged": os2["converged"] and os3["converged"],
        })

    # ── cascade alignment Δ = HOMO(FADH₂) − LUMO(Os III) ──
    fad_path = DFT_CACHE / "lumiflavin.json"
    fadh2_homo = None
    if fad_path.exists():
        fadh2_homo = json.loads(fad_path.read_text(encoding="utf-8"))["red"]["HOMO_eV"]
        for c in results["complexes"]:
            c["cascade_delta_eV"] = round(fadh2_homo - c["os3"]["LUMO_eV"], 4)

    banner("① FULL TREND vs Hammett σ_para")
    by_sigma = sorted(results["complexes"], key=lambda c: c["sigma_para"])
    print(f"  FADH₂ HOMO = {fadh2_homo} eV (B3LYP, cache)\n")
    print("  name    σ_para   ΔE_red(eV)   Os(III)LUMO   cascadeΔ(eV)  conv")
    for c in by_sigma:
        cd = c.get("cascade_delta_eV", float("nan"))
        print(f"    {c['name']:6s} {c['sigma_para']:+.2f}   {c['dE_red_eV']:+.4f}    "
              f"{c['os3']['LUMO_eV']:+.3f}      {cd:+.4f}    {c['converged']}")

    dEs = [c["dE_red_eV"] for c in by_sigma]
    mono_E = all(dEs[i] >= dEs[i + 1] for i in range(len(dEs) - 1))
    cds = [c.get("cascade_delta_eV", 0) for c in by_sigma]
    mono_casc = all(cds[i] <= cds[i + 1] for i in range(len(cds) - 1))
    results["monotonic_with_sigma"] = mono_E
    results["cascade_monotonic"] = mono_casc
    if fadh2_homo is not None:
        best = max(by_sigma, key=lambda c: c["cascade_delta_eV"])
        results["best_cascade_mediator"] = best["name"]
        print(f"\n  E° monotonic with σ? {'✅' if mono_E else '❌'}   "
              f"cascade Δ monotonic (rises with σ)? {'✅' if mono_casc else '❌'}")
        print(f"  Least-uphill cascade: {best['name']} (Δ={best['cascade_delta_eV']:+.4f} eV) "
              f"→ design rule: electron-withdrawing 4,4'-bpy improves FADH₂→Os alignment")

    # ── Hammett LFER slope (computed → JSON = single source for fig 60 / table 61 / prose) ──
    by_name = {c["name"]: c for c in results["complexes"]}
    fit_pts = [(by_name[n]["sigma_para"], by_name[n]["dE_red_eV"]) for n in REF_LFER_SET]
    lfer = _lfer_fit([s for s, _ in fit_pts], [e for _, e in fit_pts])
    lfer["fit_set"] = REF_LFER_SET
    lfer["excluded"] = {"donor_saturation": ["nme2", "nh2"], "inert_design_picks": ["cf3", "so2cf3"]}
    lfer["x"], lfer["y"] = "sigma_para", "dE_red_eV"
    results["lfer"] = lfer
    print(f"  ① LFER slope (OMe→NO₂, n={lfer['n']}): {lfer['slope_eV_per_sigma']:+.3f} eV/σ "
          f"(r²={lfer['r2']:.3f})")

    OUT.write_text(json.dumps(results, indent=2), encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)} ({len(results['complexes'])} complexes)")
    return 0


def _tier_21f_wb97x() -> tuple:
    """21f's own ωB97X tier (xc, basis_light, level_shift_open, out_name, conv_tol) — imported, never retyped."""
    spec = importlib.util.spec_from_file_location("s21f", Path(__file__).with_name("21f_dft_os_dimethyl.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.TIERS["wb97x"]


def _recorded_pyscf() -> str:
    explicit = Path(__file__).resolve().parents[1] / "environment.computed.explicit.txt"
    return re.search(r"/pyscf-(\d+\.\d+\.\d+)-", explicit.read_text(encoding="utf-8")).group(1)


def main_wb97x(names: list[str]) -> int:
    import pyscf

    if pyscf.__version__ != _recorded_pyscf():
        sys.exit(f"PySCF {pyscf.__version__} is not the recorded {_recorded_pyscf()} — the ωB97X points this is "
                 f"compared with were computed there; run in silken_md")
    xc, basis_light, lshift, _, conv = _tier_21f_wb97x()
    series = {name: (smi, sigma) for name, smi, sigma, _ in SERIES}
    unknown = [n for n in names if n not in series]
    if unknown:
        sys.exit(f"not in SERIES: {unknown}")
    rec = json.loads(OUT_WB97X.read_text(encoding="utf-8")) if OUT_WB97X.exists() else {
        "method": f"{xc.upper()}/{basis_light}+LANL2DZ(Os)+C-PCM(water) vertical ΔSCF — 21f's wb97x tier, imported; "
                  f"Os(III) level shift {lshift:g}, conv_tol {conv:g}",
        "environment": {"pyscf": pyscf.__version__},
        "complexes": {},
    }
    for name in names:
        smi, sigma = series[name]
        c = rec["complexes"].setdefault(name, {"sigma_para": sigma})
        atoms, _ = build_os_complex(bpy_smiles=smi)
        for state, charge, spin, shift in (("os2", 1, 0, 0.0), ("os3", 2, 1, lshift)):
            if c.get(state, {}).get("converged"):
                banner(f"① ωB97X {name} {state} — reused from {OUT_WB97X.name}")
                continue
            banner(f"① ωB97X {name} {state} (σ_para={sigma:+.2f}, PySCF {pyscf.__version__})")
            c[state] = dft_singlepoint(atoms, charge=charge, spin=spin, label=f"{state} {name} ({xc})",
                                       xc=xc, basis_light=basis_light, conv_tol=conv, level_shift_open=shift)
            print(f"  E={c[state]['E_total_Ha']:.8f} Ha ({c[state]['wall_seconds']}s, conv={c[state]['converged']})")
            OUT_WB97X.write_text(json.dumps(rec, indent=2) + "\n", encoding="utf-8")
        if c["os2"]["converged"] and c["os3"]["converged"]:
            c["dE_red_eV"] = (c["os2"]["E_total_Ha"] - c["os3"]["E_total_Ha"]) * HARTREE_TO_EV   # full precision
            OUT_WB97X.write_text(json.dumps(rec, indent=2) + "\n", encoding="utf-8")
            print(f"  ΔE_red(III→II) {name} = {c['dE_red_eV']:+.6f} eV")
    banner(f"✅ saved {OUT_WB97X.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main_wb97x(sys.argv[2:] or WB97X_EXTREMES) if sys.argv[1:2] == ["wb97x"] else main())
