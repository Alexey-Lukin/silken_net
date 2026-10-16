#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""95 — the anode cascade like-for-like: 2e⁻/2H⁺ FAD against the Os(III/II) couple on ONE SHE scale (no SCF).

WHY. Table 2 of Стаття 1 set the bare one-electron oxidation FADH₂ → FADH₂•⁺ against the two-electron, two-proton potential
of FAD, and a Koopmans orbital offset against a free energy (self-review round 1, cluster 3 — 00_07 HW.5.IS, revision step 3).
Both halves of a like-for-like comparison are already computed at ONE tier (B3LYP/6-31G(d)+C-PCM, LANL2DZ on Os) under ONE
absolute-SHE convention (script 32, Isse & Gennaro 2010): E°(FAD/FADH₂) at pH 7 (32) and ΔE_red(III→II) of each Os form
(21f · 34 · 21e relaxed). This script sets them side by side and splits the distance to the measured cascade by SIDE:

    E°(Os) vs SHE     = −ΔE_red(III→II) − |SHE_abs|                     one electron, no proton, pH-independent
    cascade           = E°(Os) − E°(FAD/FADH₂, pH 7)                   > 0 = downhill
    measured, free    = E°(Os) +309 mV − E°(free FAD) −220 mV          the SAME two couples the computation models
    measured, device  = E°(Os) +309 mV − E°(FAD-GDH, bound) −265 mV    adds the protein shift of the cofactor (④)
    donor side        = E°(FAD)_computed − E°(free FAD)_measured        > 0 = the computation shortens the cascade there
    acceptor side     = E°(Os)_measured − E°(Os)_computed               > 0 = the computation shortens the cascade there

CAN: say, per Os form, how far the computed cascade sits from the measured one for the same couples and on which side each
part of that distance lies — from the committed caches alone. CANNOT: (1) the ZPE and thermal terms — both sides are
electronic energies, and the PCET side gains two X–H bonds, so its omitted term is the larger one; its size is not computed
here; (2) the protein shift of the bound cofactor (free −220 → bound −265 mV) — measured, carried as such, never computed
(④); (3) the measured mediator is a polymer film, the computed one a molecule with one 1-MeIm; (4) any ωB97X reading — the
flavin has no ωB97X PCET potential, so an ωB97X Os side would not be like-for-like; (5) geometry: the flavin is MMFF-embedded
(20), each Os form is programmatic or B3LYP-relaxed as its label says. NHE and SHE are taken as one scale, as in 32.

Run:  conda activate silken_md
      python tools/in_silico/scripts/95_cascade_like_for_like.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, E_FAD_GDH_MV_SHE, E_OS_MEDIATOR_MV_NHE, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("L3 anode cascade like-for-like: the 2e⁻/2H⁺ FAD potential (32) against the Os(III/II) couple of each "
                  "computed form (21f · 34 · 21e relaxed) on one SHE scale, the distance to the measured cascade split by side; "
                  "no SCF")

OUT = DFT_CACHE / "cascade_like_for_like.json"


def _load(name: str) -> dict:
    return json.loads((DFT_CACHE / name).read_text(encoding="utf-8"))


def forms() -> list[tuple[str, str, float]]:
    """(label, source, ΔE_red(III→II) eV) — every B3LYP/C-PCM chloro-core form of the device mediator in the caches."""
    micro = {r["name"]: r for r in _load("microsolvation_dmbpy.json")["results"]}
    relaxed2 = _load("os_mediator_series_relaxed_os2.json")["complexes"]["dmbpy"]
    relaxed3 = _load("os_mediator_series_relaxed_os3.json")["complexes"]["dmbpy"]
    rows = [("chloro (device, programmatic)", "21f os_complex.json", _load("os_complex.json")["dE_red_III_to_II_eV"])]
    rows += [(f"chloro + {k} H₂O on Cl⁻", "34 microsolvation_dmbpy.json", micro[f"mediator_k{k}_clwaters"]["dE_red_eV"])
             for k in (1, 2, 3)]
    rows += [("chloro, Os(II) relaxed, Os(III) vertical", "21e os_mediator_series_relaxed_os2.json", relaxed2["dE_red_eV"]),
             ("chloro, both states relaxed (adiabatic)", "21e os_mediator_series_relaxed_os3.json",
              relaxed3["dE_red_adiabatic_eV"])]
    rows += [("aqua (benchmark form)", "34 microsolvation_dmbpy.json", micro["aqua_meim_h2o"]["dE_red_eV"]),
             ("bis-imidazole (operando upper form)", "34 microsolvation_dmbpy.json", micro["bisim_meim2"]["dE_red_eV"])]
    return rows


def main() -> int:
    pcet = _load("pcet_redox_potential.json")
    she_abs = pcet["SHE_abs_V"]
    e_fad = pcet["E_vs_SHE_mV"]["pH_7.0"] / 1000.0
    (fad_free_meas,) = [v / 1000.0 for v in pcet["exp_free_flavin_pH7_mV"]]   # 32 carries one sourced reading
    os_meas = E_OS_MEDIATOR_MV_NHE / 1000.0
    fad_bound_meas = E_FAD_GDH_MV_SHE / 1000.0
    meas_free = os_meas - fad_free_meas
    meas_device = os_meas - fad_bound_meas
    donor = e_fad - fad_free_meas

    banner("95 — anode cascade like-for-like (B3LYP/C-PCM, one SHE scale)")
    print(f"  E°(FAD/FADH₂, pH 7) computed {e_fad * 1000:+.1f} mV ⊥ measured free flavin {fad_free_meas * 1000:+.0f} mV "
          f"→ donor side {donor * 1000:+.1f} mV")
    print(f"  measured cascade, same couples {meas_free * 1000:+.0f} mV · device (bound FAD-GDH) {meas_device * 1000:+.0f} mV\n")
    rows = []
    print(f"  {'form':44s} {'E°(Os) mV':>10s} {'cascade mV':>11s} {'gap mV':>8s} {'acceptor':>9s} {'donor':>7s}")
    for label, source, de_red in forms():
        e_os = -de_red - she_abs
        cascade = e_os - e_fad
        acceptor = os_meas - e_os
        gap = meas_free - cascade
        rows.append({"form": label, "source": source, "dE_red_III_to_II_eV": de_red, "E_os_vs_SHE_V": round(e_os, 4),
                     "cascade_V": round(cascade, 4), "direction": "downhill" if cascade > 0 else "uphill",
                     "gap_to_measured_same_couples_V": round(gap, 4), "acceptor_side_V": round(acceptor, 4),
                     "donor_side_V": round(donor, 4)})
        print(f"  {label:44s} {e_os * 1000:+10.1f} {cascade * 1000:+11.1f} {gap * 1000:+8.1f} {acceptor * 1000:+9.1f} "
              f"{donor * 1000:+7.1f}")

    dev = rows[0]
    closest = min(rows, key=lambda r: abs(r["acceptor_side_V"]))
    over = [r["form"] for r in rows if r["acceptor_side_V"] < 0]
    verdict = (
        f"On one SHE scale at B3LYP/C-PCM the device chloro couple gives a {dev['direction']} cascade of "
        f"{dev['cascade_V'] * 1000:+.0f} mV against {meas_free * 1000:+.0f} mV measured for the same free couples; of the "
        f"{dev['gap_to_measured_same_couples_V'] * 1000:.0f} mV between them {dev['acceptor_side_V'] * 1000:.0f} mV lie on the "
        f"acceptor side and {donor * 1000:.0f} mV on the donor side. Every form is {'downhill' if all(r['cascade_V'] > 0 for r in rows) else 'not all downhill'}; "
        f"the acceptor side is smallest for «{closest['form']}» ({closest['acceptor_side_V'] * 1000:+.0f} mV)"
        + (f", and {', '.join('«' + f + '»' for f in over)} overshoot the measured mediator" if over else "")
        + f". The device cascade (+{meas_device * 1000:.0f} mV) adds the measured protein shift "
        f"({(fad_bound_meas - fad_free_meas) * 1000:+.0f} mV on the donor), which is not computed here. Electronic energies on "
        "both sides — the ZPE and thermal terms, larger on the PCET side, are not in these numbers."
    )
    result = {
        "method": "B3LYP/6-31G(d)+C-PCM(water), LANL2DZ on Os; electronic energies (no ZPE/thermal); one absolute-SHE "
                  "convention (32: Isse & Gennaro 2010)",
        "conventions": {"SHE_abs_V": she_abs, "E_os": "−ΔE_red(III→II) − |SHE_abs|",
                        "cascade": "E°(Os) − E°(FAD/FADH₂, pH 7), > 0 = downhill",
                        "sides": "donor = computed − measured free FAD; acceptor = measured − computed Os; gap = their sum"},
        "flavin": {"E_pH7_computed_V": round(e_fad, 4), "E_pH7_measured_free_V": fad_free_meas,
                   "donor_side_V": round(donor, 4), "source": "32 pcet_redox_potential.json"},
        "measured": {"E_os_V": os_meas, "E_fad_gdh_bound_V": fad_bound_meas, "cascade_same_couples_V": round(meas_free, 4),
                     "cascade_device_V": round(meas_device, 4),
                     "protein_shift_V": round(fad_bound_meas - fad_free_meas, 4)},
        "forms": rows,
        "not_computed": ["ZPE and thermal terms (both sides; larger on the PCET side)",
                         "protein shift of the bound cofactor (measured, carried)",
                         "polymer film of the measured mediator vs one 1-MeIm molecule",
                         "any ωB97X reading (no ωB97X PCET potential of the flavin)"],
        "verdict": verdict,
    }
    if "--dry" in sys.argv:
        print("\n  " + verdict)
        return 0
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    print("  " + verdict)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
