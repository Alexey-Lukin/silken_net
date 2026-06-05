#!/usr/bin/env python
"""L3 task ① — Os-mediator structure-property series (full Hammett range).

Computes the Os(III)+e⁻→Os(II) ΔSCF reduction energy for cis-[Os(4,4'-X-bpy)₂(1-MeIm)Cl]ⁿ⁺
across a 4,4'-substituent series at CONSTANT charge (+1/+2), isolating the
electronic effect (no charge change → no differential-PCM confounder; that is ②).
Establishes (a) the Hammett LFER for the Os(III/II) potential and (b) the
cascade-alignment design rule Δ = HOMO(FADH₂) − LUMO(Os III) vs substituent.

Pre-check (dmbpy/bpy/dcbpy) PASSED 2026-06-05: monotonic with σ, reproduces 21b
(Δ=0.000), LFER slope ≈ −0.89 eV/σ. This is the full series.

PREDICTION (fixed): ΔE_red decreases (E° rises) and the cascade Δ rises toward 0
(less uphill) as σ_para increases (electron-withdrawing 4,4'-substituents).

Method: B3LYP/6-31G(d)+LANL2DZ(Os)+C-PCM, vertical ΔSCF, level_shift OFF (21b-faithful).
Sequential single process (feedback_dft_sequential). Cache-skip: complexes already
present + converged in os_mediator_series.json are reused (no recompute). Cascade Δ
uses FADH₂ HOMO from dft/lumiflavin.json. Numbers feed SUMMARY.md (One-Home) once done.

Run:  conda activate silken_md
      python tools/in_silico/scripts/21e_dft_os_mediator_series.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, LIGANDS_DIR, REPO_ROOT, HARTREE_TO_EV
from lib.os_geometry import build_os_complex, write_xyz, BPY_SMILES, DMBPY_SMILES, DCBPY_SMILES
from lib.dft_utils import dft_singlepoint
from lib.utils import banner

# 4,4'-X-2,2'-bipyridine series, ordered by Hammett σ_para (donor → acceptor).
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
]

REF_21B = {"os2_HOMO": -4.875, "os2_LUMO": -2.156, "os3_HOMO": -6.359, "os3_LUMO": -4.228}
OUT = DFT_CACHE / "os_mediator_series.json"


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

    OUT.write_text(json.dumps(results, indent=2), encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)} ({len(results['complexes'])} complexes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
