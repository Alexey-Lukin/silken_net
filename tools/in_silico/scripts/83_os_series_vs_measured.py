#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""① against a MEASURED series — the substituent shift of E°(Os III/II) per 4,4'-substituent, computed ⊥ measured.

The paper withdrew the claim that the Hammett slope was «triangulated against … the measured series» (2026-09-25,
paper/09_references.md §3.3): no script or cache performed the comparison. This is that instrument, for the one
measured 4,4'-X2-bpy Os(III/II) series found (00_07 HW.5.IS, ChemRxiv scout 2026-10-11):

  Goldschmid, S. L.; Bednářová, E.; Beck, L. R.; Xie, K.; Tay, N. E. S.; Ravetz, B. D.; Li, J.; Joe, C. L.; Rovis, T.
  «Tuning the Electrochemical and Photophysical Properties of Osmium Complexes for Application in Photoredox
  Catalysis», ChemRxiv 2021, doi:10.26434/chemrxiv-2021-jfmqq (preprint v1, CC BY-NC 4.0; version of record: Synlett
  2022). Table 2, E1/2(Os III/II) of [Os(L)3](PF6)2 — MeCN, 0.1 M TBAPF6, 100 mV/s, N2, vs Fc/Fc+ — transcribed from
  the rendered page image of the preprint PDF on 2026-10-11 (entries 1, 3, 4, 5; the text of §2.2 states the same four
  values). The reference electrode cancels in every number below: only DIFFERENCES to the bpy parent are used.

CAN show: (1) the per-pair shift, per substituent, of each donor BOTH series have (Me · OMe against H) — the primary
reading: does each computed pair agree with its measured one; (2) the three-point slope over those donors (H · Me · OMe)
— a DERIVED reading, not a second agreement: Me's leverage in it is small, so it mostly restates the OMe pair; (3) the
measured alkyl-only line (H · Me · tBu), which has no computed counterpart (tBu is not in 21e). CANNOT show: the
acceptor side (the series has no 4,4'-acceptor), nor OUR complex's measured slope. Named transfer assumptions, none of them tested here:
  (A1) additivity — a ring substituent shifts E° by the same amount per substituent in a homoleptic tris-diimine
       (6 substituents, +2/+3) and in our heteroleptic bis-bpy complex (4 substituents, +1/+2): Lever's premise;
  (A2) the solvent (MeCN ⊥ water) and the charge state change the absolute E°, not the substituent DIFFERENCE;
  (A3) σp as in 21e's SERIES (Hansch, Leo & Taft 1991, not checked against the full text), and tBu σp −0.20 from the
       same compilation, equally unchecked;
  (A4) a vertical ΔSCF difference (computed) is compared with an E1/2 difference (measured, adiabatic).

Run:  conda activate silken_md; python tools/in_silico/scripts/83_os_series_vs_measured.py
      (reads caches, no SCF — but it imports 21e for its σ table, one home, and 21e loads lib/ with RDKit)
"""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT

SI_DESCRIPTION = ("Computed shift of the Os(III/II) potential per 4,4'-bipyridine substituent compared with a measured "
                  "series of homoleptic osmium complexes (donor side only, under named transfer assumptions).")  # its row in the paper SI (72): English, no repo jargon
SOURCE = {"doi": "10.26434/chemrxiv-2021-jfmqq", "version": "preprint v1 (2021-10-22)", "table": "Table 2",
          "medium": "MeCN, 0.1 M TBAPF6, 100 mV/s, N2", "reference": "Fc/Fc+ (cancels in differences)",
          "read": "2026-10-11, rendered page image of the preprint PDF; §2.2 text states the same values",
          "licence": "CC BY-NC 4.0"}
# E1/2(Os III/II), V vs Fc/Fc+, [Os(L)3](PF6)2 — Table 2 of the source; key = the 21e SERIES name of the ligand where
# one exists. 6 substituents per complex (three 4,4'-X2-bpy).
MEASURED_E12_V = {"bpy": (0.44, "Os12, entry 1"), "dmbpy": (0.35, "Os26, entry 3"),
                  "dtbbpy": (0.32, "Os27, entry 4"), "ome": (0.07, "Os28, entry 5")}
N_SUBST_MEASURED = 6
N_SUBST_COMPUTED = 4   # cis-[Os(4,4'-X2-bpy)2(1-MeIm)Cl]: two bpy, two substituents each
SIGMA_P_TBU = -0.20    # (A3) Hansch, Leo & Taft 1991 compilation — the source 21e's SERIES names; not checked against it
OUT = DFT_CACHE / "os_series_vs_measured.json"


def _load(name: str):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(f"{name}.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _slope_r2(xs: list[float], ys: list[float]) -> tuple[float, float]:
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    sxx = sum((x - mx) ** 2 for x in xs)
    slope = sum((x - mx) * (y - my) for x, y in zip(xs, ys, strict=True)) / sxx
    ss_res = sum((y - (my + slope * (x - mx))) ** 2 for x, y in zip(xs, ys, strict=True))
    ss_tot = sum((y - my) ** 2 for y in ys)
    return slope, 1.0 - ss_res / ss_tot


def verdict(rec: dict) -> str:
    """The cache's prose, built from the record alone — so a pin can rebuild it and compare it whole (§When Modifying #5)."""
    m, c, r, ms = rec["measured"], rec["computed"], rec["ratio_computed_over_measured_per_substituent"], rec["matched_slope"]
    al = rec["measured_readings"]["alkyl_only"]
    return (f"Of the two donor pairs both series have, per 4,4'-substituent against H: OMe agrees — "
            f"{c['b3lyp_631gd']['ome']['shift_per_substituent_V'] * 1000:+.1f} mV computed (B3LYP) against "
            f"{m['ome']['shift_per_substituent_V'] * 1000:+.1f} measured (×{r['b3lyp_631gd:ome']:.2f}); Me does not — "
            f"{c['b3lyp_631gd']['dmbpy']['shift_per_substituent_V'] * 1000:+.1f} (B3LYP) and "
            f"{c['wb97x_def2tzvp']['dmbpy']['shift_per_substituent_V'] * 1000:+.1f} mV (ωB97X) against "
            f"{m['dmbpy']['shift_per_substituent_V'] * 1000:+.1f} measured (×{r['b3lyp_631gd:dmbpy']:.2f} and "
            f"×{r['wb97x_def2tzvp:dmbpy']:.2f}). The computed donors lie on one σp line (r² {ms['computed_b3lyp_r2']:.2f} "
            f"over {', '.join(ms['points'])}), the measured do not (r² {ms['measured_r2']:.2f}): the measured Me is weak "
            f"against the line through H and OMe. A three-point slope over the same donors comes out ×"
            f"{ms['ratio_computed_over_measured']:.2f} ({ms['computed_b3lyp_per_substituent_V_per_sigma']:.3f} against "
            f"{ms['measured_per_substituent_V_per_sigma']:.3f} V/σ per substituent), but Me's leverage in it is small, so "
            f"it restates the OMe pair rather than adding a second agreement. The measured alkyl-only line (H · Me · tBu) "
            f"gives {al['per_substituent_V_per_sigma']:.3f} V/σ per substituent (r² {al['r2']:.2f}; no computed tBu); "
            f"the computed LFER over {', '.join(rec['computed_lfer_fit_set'])} gives "
            f"{rec['computed_lfer_per_substituent_V_per_sigma']:.3f}. Donor side only, one homoleptic series in MeCN, "
            f"under assumptions A1–A4; the acceptor side — most of the σ range of the LFER fit — has no measured "
            f"counterpart here.")


def main() -> int:
    s21e = _load("21e_dft_os_mediator_series")
    sigma = {name: sig for name, _, sig, _ in s21e.SERIES} | {"dtbbpy": SIGMA_P_TBU}
    # measured: shift of E° to the bpy parent, per substituent
    e_bpy = MEASURED_E12_V["bpy"][0]
    measured = {n: {"E12_V": e, "where": w, "sigma_para": sigma[n], "shift_V": e - e_bpy,
                    "shift_per_substituent_V": (e - e_bpy) / N_SUBST_MEASURED} for n, (e, w) in MEASURED_E12_V.items()}
    readings = {}
    for label, names in (("matched", ["bpy", "dmbpy", "ome"]), ("alkyl_only", ["bpy", "dmbpy", "dtbbpy"]),
                         ("all_measured", ["bpy", "dmbpy", "dtbbpy", "ome"])):
        slope, r2 = _slope_r2([sigma[n] for n in names], [measured[n]["E12_V"] for n in names])
        readings[label] = {"points": names, "slope_V_per_sigma": slope, "r2": r2,
                           "per_substituent_V_per_sigma": slope / N_SUBST_MEASURED}
    # computed: E° shift = −(ΔE_red(X) − ΔE_red(bpy)) — ΔE_red = E(II) − E(III) falls as E° rises
    b3 = {c["name"]: c for c in json.loads((DFT_CACHE / "os_mediator_series.json").read_text(encoding="utf-8"))["complexes"]}
    computed = {"b3lyp_631gd": {}, "wb97x_def2tzvp": {}}
    for n in ("dmbpy", "ome"):
        shift = -(b3[n]["dE_red_eV"] - b3["bpy"]["dE_red_eV"])
        computed["b3lyp_631gd"][n] = {"shift_V": shift, "shift_per_substituent_V": shift / N_SUBST_COMPUTED}
    centre = {}   # ωB97X/def2-TZVP exists for dmbpy and bpy only — 21e's WB97X_CENTRE (21f / 21d caches)
    for n, (cache, xyz) in s21e.WB97X_CENTRE.items():   # refused unless on the series geometry — 21e's own check
        dev = s21e._max_dev_A(s21e._read_xyz(LIGANDS_DIR / xyz), s21e._read_xyz(LIGANDS_DIR / f"os_{n}_meim_cl.xyz"))
        if dev > s21e.SAME_GEOMETRY_TOL_A:
            sys.exit(f"{cache}: not the series geometry (max |Δxyz| {dev} Å)")
        w = json.loads((DFT_CACHE / cache).read_text(encoding="utf-8"))
        centre[n] = (w["os2_plus"]["E_total_Ha"] - w["os3_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    shift = -(centre["dmbpy"] - centre["bpy"])
    computed["wb97x_def2tzvp"]["dmbpy"] = {"shift_V": shift, "shift_per_substituent_V": shift / N_SUBST_COMPUTED}
    names = readings["matched"]["points"]   # the same points, computed: E° relative to bpy = −(ΔE_red(X) − ΔE_red(bpy))
    c_slope, c_r2 = _slope_r2([sigma[n] for n in names], [-(b3[n]["dE_red_eV"] - b3["bpy"]["dE_red_eV"]) for n in names])
    matched = {"points": names, "computed_b3lyp_per_substituent_V_per_sigma": c_slope / N_SUBST_COMPUTED,
               "computed_b3lyp_r2": c_r2,
               "measured_per_substituent_V_per_sigma": readings["matched"]["per_substituent_V_per_sigma"],
               "measured_r2": readings["matched"]["r2"]}
    matched["ratio_computed_over_measured"] = (matched["computed_b3lyp_per_substituent_V_per_sigma"]
                                               / matched["measured_per_substituent_V_per_sigma"])
    lfer = json.loads((DFT_CACHE / "os_mediator_series.json").read_text(encoding="utf-8"))["lfer"]
    fit = lfer["fit_set"]   # the slope refitted from the unrounded rows — compute FROM those, never from a rounded fit
    per_sub_lfer = -_slope_r2([b3[n]["sigma_para"] for n in fit], [b3[n]["dE_red_eV"] for n in fit])[0] / N_SUBST_COMPUTED
    ratios = {f"{tier}:{n}": v["shift_per_substituent_V"] / measured[n]["shift_per_substituent_V"]
              for tier, rows in computed.items() for n, v in rows.items()}
    rec = {
        "script": Path(__file__).name,
        "question": "① — does the computed substituent shift of E°(Os III/II) agree with a measured 4,4'-X2-bpy series?",
        "source": SOURCE,
        "assumptions": ["A1 additivity per substituent across homoleptic tris and heteroleptic bis complexes",
                        "A2 solvent and charge state shift the absolute E°, not the substituent difference",
                        "A3 sigma_para as in 21e SERIES; tBu -0.20 from the same compilation, unchecked",
                        "A4 vertical ΔSCF difference (computed) against an E1/2 difference (measured)"],
        "measured": measured,
        "measured_readings": readings,
        "matched_slope": matched,
        "computed": computed,
        "computed_lfer_per_substituent_V_per_sigma": per_sub_lfer,
        "computed_lfer_fit_set": lfer["fit_set"],
        "ratio_computed_over_measured_per_substituent": ratios,
        "not_covered": "the acceptor side — the measured series has no 4,4'-acceptor; OMe at ωB97X — not computed",
    }
    rec["verdict"] = verdict(rec)
    OUT.write_text(json.dumps(rec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(rec["verdict"])
    print(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
