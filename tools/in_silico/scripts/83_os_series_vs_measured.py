#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""① against a MEASURED series — the substituent shift of E°(Os III/II) per 4,4'-substituent, computed ⊥ measured.

The paper withdrew the claim that the Hammett slope was «triangulated against … the measured series» (2026-09-25,
paper/09_references.md §3.3): no script or cache performed the comparison. This is that instrument; its first series
is the measured 4,4'-X2-bpy Os(III/II) series the ChemRxiv scout found (00_07 HW.5.IS, 2026-10-11):

  Goldschmid, S. L.; Bednářová, E.; Beck, L. R.; Xie, K.; Tay, N. E. S.; Ravetz, B. D.; Li, J.; Joe, C. L.; Rovis, T.
  «Tuning the Electrochemical and Photophysical Properties of Osmium Complexes for Application in Photoredox
  Catalysis», ChemRxiv 2021, doi:10.26434/chemrxiv-2021-jfmqq (preprint v1, CC BY-NC 4.0; version of record: Synlett
  2022). Table 2, E1/2(Os III/II) of [Os(L)3](PF6)2 — MeCN, 0.1 M TBAPF6, 100 mV/s, N2, vs Fc/Fc+ — transcribed from
  the rendered page image of the preprint PDF on 2026-10-11 (entries 1, 3, 4, 5; the text of §2.2 states the same four
  values). The reference electrode cancels in every number below: only DIFFERENCES to the bpy parent are used.

For THIS first series — CAN show: (1) the per-pair shift, per substituent, of each donor BOTH series have (Me · OMe against H) — the primary
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

A SECOND, aqueous series of our own scaffold (`aqueous_series` block, 2026-10-11 — found while looking for the ligands of
paper ref 8, read later the same day — the third block below):

  Montón-Vicente et al., «Tunable Osmium Complexes …», Langmuir 2026, 42, 24074–24085, doi:10.1021/acs.langmuir.6c02628
  (CC BY; PMC13523742). Table 1, E1/2(Os II/III) of [Os(4,4'-X2-bpy)2Cl(ampy)]+, ampy = 4-(aminomethyl)pyridine —
  air-equilibrated PBS pH 7.4, 25 °C, vs Ag/AgCl, measured in that paper in triplicate — read from the PMC text on
  2026-10-11 (complexes 1–3; the text of §3.3 states the same three values). X = OMe · Me · Cl, no parent bpy, so the
  differences are taken to Me. Same charge (+1/+2), same solvent, same bis-bpy chloro core as ours: of A1–A2 only the
  axial N-donor remains — (A1′) pyridine ⊥ 1-methylimidazole shifts the absolute E°, not the substituent difference.
  The same Table 1 prints the authors' own B3LYP E1/2 (def2-TZVP/ECP on Os, def2-SVP elsewhere, IEFPCM water; both
  oxidation states optimised, vibrational frequencies, potential from ΔG — their §2.6 and §3.3), so every pair is read
  three ways: measured · ours (vertical ΔSCF on one programmatic geometry) · theirs (relaxed, free energy).
  CAN show: per-substituent pair shifts OMe−Me, Cl−Me and Cl−OMe — Cl is an ACCEPTOR point — and whether the source's
  relaxed B3LYP reproduces a pair ours misses (a protocol effect, A4, rather than the functional). CANNOT show: a slope
  — the measured shifts are not linear in σp (the two pairwise slopes differ ×4), so the three-point slope ratio is
  kept in the cache as a mix of the pairs, not read as a slope.

A THIRD series — OUR scaffold to the N-donor (`pvi_series` block, 2026-10-11): paper ref 8 itself,

  Zafar, Wang, Sygmund, Ludwig, Leech, Gorton, Anal. Chem. 2012, 84, 334–341, doi:10.1021/ac202647z. Table 1, E°′ of the
  Os polymers [Os(4,4'-X2-bpy)2(PVI)Cl]+ (PVI = poly(N-vinylimidazole), the imidazole N-donor our 1-MeIm models), films
  on graphite in 50 mM phosphate buffer pH 7.4, measured in that paper (CVs of its Fig. 1A) — read from the page image of
  a copy the founder downloaded on 2026-10-11 — an academia.edu upload of the ACS typeset PDF, pp. 334–341 (the text layer
  gives the same numbers; the copy is kept out of the repository).
  X = OMe · Me · H · Cl at one Os loading (1:9, polymers b, c, d, f). (A5) The film's environment moves E°′ by more than a
  substituent does — the same Me complex at loading 1:11 (polymer e) sits +135 mV from polymer c — so only the equal-
  loading points are compared, on the premise that their environment is common. No A1/A1′: the N-donor is ours.

Run:  conda activate silken_md; python tools/in_silico/scripts/83_os_series_vs_measured.py
      (reads caches, no SCF — but it imports 21e for its σ table, one home, and 21e loads lib/ with RDKit)
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE, HARTREE_TO_EV, LIGANDS_DIR, REPO_ROOT

SI_DESCRIPTION = ("Computed shift of the Os(III/II) potential per 4,4'-bipyridine substituent compared with three measured "
                  "series: homoleptic osmium complexes in acetonitrile (donors only), an aqueous series of the same "
                  "bis-bipyridine chloro core, and the osmium redox polymers of the same core with an imidazole donor "
                  "(paper ref 8), under named transfer assumptions.")  # its row in the paper SI (72): English, no repo jargon
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
AQ_SOURCE = {"doi": "10.1021/acs.langmuir.6c02628", "journal": "Langmuir 2026, 42 (33), 24074–24085", "pmc": "PMC13523742",
             "table": "Table 1", "complex": "[Os(4,4'-X2-bpy)2Cl(ampy)]+, ampy = 4-(aminomethyl)pyridine",
             "medium": "air-equilibrated PBS pH 7.4, 25 °C; E1/2 = mean of the CV peak potentials, triplicate",
             "reference": "Ag/AgCl (3 M NaCl; cancels in differences)", "cv": "5 V/s, 2 mm gold disk",
             "peak_separation_V": {"ome": 0.12, "dmbpy": 0.08, "cl": 0.14}, "uncertainty": "no SEM printed for E1/2",
             "read": "2026-10-11, PMC text of Table 1, §2.6 and §3.3; §3.3 states the same measured values",
             "licence": "CC BY 4.0"}
# the source's own computed E1/2 (Table 1, «E1/2 calc», V vs Ag/AgCl) — B3LYP, def2-TZVP+ECP (Os) / def2-SVP, IEFPCM water,
# both oxidation states optimised with frequencies, E = ΔG/nF − 4.637 V (its §2.6, §3.3)
AQ_SOURCE_DFT_E12_V = {"ome": -0.031, "dmbpy": 0.129, "cl": 0.339}
AQ_PAIRS = (("ome", "dmbpy"), ("cl", "dmbpy"), ("cl", "ome"))   # (X, reference) — per substituent, X minus reference
# E1/2(Os II/III), V vs Ag/AgCl — Table 1 of AQ_SOURCE; key = the 21e SERIES name. 4 substituents, as in ours.
AQ_MEASURED_E12_V = {"ome": (0.036, "complex 1"), "dmbpy": (0.195, "complex 2"), "cl": (0.340, "complex 3")}
AQ_REF = "dmbpy"   # the series has no parent bpy
PVI_SOURCE = {"doi": "10.1021/ac202647z", "journal": "Anal. Chem. 2012, 84, 334–341 (paper ref 8)", "table": "Table 1",
              "complex": "[Os(4,4'-X2-bpy)2(PVI)Cl]+, Os:PVI loading 1:9 (polymers b, c, d, f)",
              "medium": "adsorbed films on spectrographic graphite with PEGDGE, 50 mM phosphate buffer pH 7.4; E°′ from CV (Fig. 1A)",
              "reference": "NHE as printed (cancels in differences)",
              "read": "2026-10-11, page image (p. 337) of a copy the founder downloaded — an academia.edu upload of the ACS typeset "
                      "PDF; the text layer gives the same numbers; no uncertainties or replicates printed",
              "polymer_e": "the Me complex at loading 1:11 is PVI12-[Os(dmbpy)2Cl], a gift from TheraSense — another source as well"}
# E°′(Os II/III), V vs NHE — Table 1 of PVI_SOURCE; key = the 21e SERIES name. 4 substituents, as in ours.
PVI_MEASURED_E_V = {"ome": (0.140, "polymer b"), "dmbpy": (0.309, "polymer c"), "bpy": (0.420, "polymer d"),
                    "cl": (0.489, "polymer f")}
PVI_LOADING_CONTROL = {"same_complex": "dmbpy", "loading_1_9_V": 0.309, "loading_1_11_V": 0.444, "where": "polymers c and e"}
PVI_PAIRS = (("ome", "bpy"), ("dmbpy", "bpy"), ("cl", "bpy"), ("ome", "dmbpy"), ("cl", "dmbpy"), ("cl", "ome"))
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


SOLVATION_VARIANTS = (("iefpcm", "os_mediator_series_iefpcm.json", "IEF-PCM for C-PCM"),
                      ("uffcavity", "os_mediator_series_uffcavity.json", "Gaussian 16's UFF ×1.1 cavity radii"),
                      ("gas", "os_mediator_series_gas.json", "no continuum"))   # 21e's one-knob variants (00_07 HW.5.IS)
AXIAL_VARIANT = ("pyaxial", "os_mediator_series_pyaxial.json")   # 21e `b3lyp-pyaxial`: pyridine for 1-MeIm — the A1′ knob


def _solvation_clause(aq: dict) -> str:
    """What the continuum variants say about the OMe−Me gap — built from the block (pinned whole with the verdict).

    The threshold «half the excess» is OURS: a variant that moves the pair TOWARD the measured by less than half of what
    separates ours from it cannot by itself explain it (a move away counts as none). The gas phase is a bound, not a
    candidate: it gives the continuum's whole share of the pair, whose sign says whether the continuum attenuates or
    amplifies it. What is left is listed, never closed — the frame has members no variant moved (adversary, 2026-10-12)."""
    sc = aq.get("solvation_check")
    if not sc or not all(k in sc for k, _, _ in SOLVATION_VARIANTS):
        return "so the vertical ΔSCF on one programmatic geometry or the C-PCM continuum; three points do not say which. "
    ex = sc["ome_dmbpy_excess_mV"]
    if abs(ex) < 0.05:
        return "and ours meets the measured on OMe−Me, so no part of the protocol is singled out by this pair. "
    moves = {k: sc[k]["ome_dmbpy_change_mV"] for k, _, _ in SOLVATION_VARIANTS}
    reach = [lab for k, _, lab in SOLVATION_VARIANTS[:2] if -moves[k] / ex >= 0.5]
    ours = next(p["ours_mV"] for p in aq["pairs"] if (p["x"], p["ref"]) == ("ome", "dmbpy"))
    share = -moves["gas"]   # the continuum's part of the pair: series − gas
    role = "attenuates" if share * ours < 0 else "amplifies"
    nums = (f"on OMe−Me, whose computed excess over the measured is {ex:+.1f} mV, IEF-PCM moves the pair by "
            f"{moves['iefpcm']:+.1f} mV and the UFF ×1.1 radii by {moves['uffcavity']:+.1f} mV; removing the continuum "
            f"moves it by {moves['gas']:+.1f} mV, so the continuum {role} the pair by {abs(share):.1f} mV")
    if reach:
        return (f"and of the continuum: {nums} — {' and '.join(reach)} move it toward the measured by half the excess or "
                f"more, so the continuum stays a candidate. ")
    head = (f"nor the continuum's formulation or its radii: {nums}, but neither variant moves it toward the measured by "
            f"half the excess. ")
    under = "A1′–A2′"
    ax = aq.get("axial_check")
    if ax:
        mv = ax["ome_dmbpy_change_mV"]
        if -mv / ex >= 0.5:
            return head + (f"The axial N-donor does: pyridine for 1-MeIm moves the pair by {mv:+.1f} mV toward the measured, "
                           f"so A1′ does not hold for this pair. ")
        head += f"Nor the axial N-donor: pyridine for 1-MeIm moves the pair by {mv:+.1f} mV, so A1′ holds for it. "
        under = "A2′"
    return head + (f"Left untested (under {under}): the vertical ΔSCF on one programmatic geometry against optimised "
                   f"states and free energies, the program's own cavity discretisation and, on this pair, the ligand basis. ")


def verdict_aqueous(aq: dict) -> str:
    """The aqueous block's prose, built from the block alone (pinned whole, like `verdict`)."""
    pairs = aq["pairs"]
    lab = {"ome": "OMe", "dmbpy": "Me", "cl": "Cl"}
    txt = "; ".join(f"{lab[p['x']]}−{lab[p['ref']]} {p['ours_mV']:+.1f} ours against {p['measured_mV']:+.1f} measured "
                    f"(×{p['ours_over_measured']:.2f}; theirs ×{p['source_dft_over_measured']:.2f})" for p in pairs)
    pw = aq["measured_pairwise_slope_per_substituent_V_per_sigma"]
    return (f"Against the aqueous series of our own bis-bpy chloro core (monodentate pyridine for our 1-MeIm, PBS pH 7.4), "
            f"per 4,4'-substituent: {txt}. The two pairs taken to Me share our Me point, so they are not independent; "
            f"the source's relaxed B3LYP — our functional — reproduces OMe−Me, so that gap sits in our protocol, not in the "
            f"functional; of the protocol, " + (f"not the osmium basis/ECP (def2-TZVP moves every pair by at most "
            f"{aq['os_basis_check']['max_pair_change_mV']:.1f} mV), " + _solvation_clause(aq) if "os_basis_check" in aq else
            "the vertical ΔSCF on one programmatic geometry, LANL2DZ on Os or C-PCM; three points do not say which. ")
            + f"Its one acceptor point, Cl, comes out larger than "
            f"measured in both computations. The measured shifts are not linear in σp (pairwise slopes "
            f"{pw['ome-dmbpy']:.3f} and {pw['dmbpy-cl']:.3f} V/σ per substituent), so no slope is read from three points.")


def verdict_pvi(pv: dict) -> str:
    """The PVI block's prose, built from the block alone (pinned whole, like `verdict`)."""
    lab = {"ome": "OMe", "dmbpy": "Me", "bpy": "H", "cl": "Cl"}
    pairs = "; ".join(f"{lab[p['x']]}−{lab[p['ref']]} {p['ours_mV']:+.1f} ours against {p['measured_mV']:+.1f} measured "
                      f"(×{p['ours_over_measured']:.2f})" for p in pv["pairs"])
    sl = pv["pairwise_slope_per_substituent_V_per_sigma"]
    seg = "; ".join(f"{k}: {v['measured']:.3f} measured, {v['ours']:.3f} ours" for k, v in sl.items())
    return (f"Against paper ref 8's own series — our core with an imidazole N-donor, [Os(X2-bpy)2(PVI)Cl]+ at one loading, "
            f"pH 7.4 — per 4,4'-substituent: {pairs}. The measured sensitivity falls from the donor to the acceptor side "
            f"and ours much less (pairwise slopes, V/σ per substituent — {seg}), so the computed effect is about right for "
            f"OMe against H and too large toward the acceptor end. The same Me complex from another source at another loading "
            f"sits {pv['loading_control']['shift_mV']:+.0f} mV away (A5) — more than all four Me → H — so the film and its "
            f"preparation move E°′ by more than the pairs compared, and only the equal-loading points of one route are compared.")


def pvi(sigma: dict, b3: dict) -> dict:
    e_meas = {n: e for n, (e, _) in PVI_MEASURED_E_V.items()}
    e_ours = {n: -b3[n]["dE_red_eV"] for n in PVI_MEASURED_E_V}   # E° up to a constant: −ΔE_red
    pairs = []
    for x, ref in PVI_PAIRS:
        meas = (e_meas[x] - e_meas[ref]) / N_SUBST_COMPUTED * 1000
        ours = (e_ours[x] - e_ours[ref]) / N_SUBST_COMPUTED * 1000
        pairs.append({"x": x, "ref": ref, "measured_mV": meas, "ours_mV": ours, "ours_over_measured": ours / meas})
    order = sorted(PVI_MEASURED_E_V, key=lambda n: sigma[n])
    slopes = {f"{a}-{b}": {"measured": (e_meas[b] - e_meas[a]) / (sigma[b] - sigma[a]) / N_SUBST_COMPUTED,
                           "ours": (e_ours[b] - e_ours[a]) / (sigma[b] - sigma[a]) / N_SUBST_COMPUTED}
              for a, b in itertools.pairwise(order)}
    lc = PVI_LOADING_CONTROL
    pv = {"source": PVI_SOURCE, "measured_E_V": {n: {"E_V": e, "where": w, "sigma_para": sigma[n]} for n, (e, w) in PVI_MEASURED_E_V.items()},
          "pairs": pairs, "pairwise_slope_per_substituent_V_per_sigma": slopes,
          "loading_control": {**lc, "shift_mV": (lc["loading_1_11_V"] - lc["loading_1_9_V"]) * 1000},
          "assumptions": ["A3 sigma_para as in 21e SERIES, unchecked", "A4 vertical ΔSCF difference against an E°′ difference",
                          "A5 the film environment is common to the equal-loading polymers b, c, d, f"]}
    pv["verdict"] = verdict_pvi(pv)
    return pv


def aqueous(sigma: dict, b3: dict) -> dict:
    e_ref = AQ_MEASURED_E12_V[AQ_REF][0]
    measured = {n: {"E12_V": e, "where": w, "sigma_para": sigma[n], "shift_V": e - e_ref,
                    "shift_per_substituent_V": (e - e_ref) / N_SUBST_COMPUTED} for n, (e, w) in AQ_MEASURED_E12_V.items()}
    computed = {}
    for n in AQ_MEASURED_E12_V:   # E° relative to Me = −(ΔE_red(X) − ΔE_red(Me))
        shift = -(b3[n]["dE_red_eV"] - b3[AQ_REF]["dE_red_eV"])
        computed[n] = {"shift_V": shift, "shift_per_substituent_V": shift / N_SUBST_COMPUTED}
    names = sorted(AQ_MEASURED_E12_V, key=lambda n: sigma[n])
    xs = [sigma[n] for n in names]
    c_slope, c_r2 = _slope_r2(xs, [computed[n]["shift_V"] for n in names])
    m_slope, m_r2 = _slope_r2(xs, [measured[n]["shift_V"] for n in names])
    slope = {"points": names, "computed_b3lyp_per_substituent_V_per_sigma": c_slope / N_SUBST_COMPUTED,
             "computed_b3lyp_r2": c_r2, "measured_per_substituent_V_per_sigma": m_slope / N_SUBST_COMPUTED,
             "measured_r2": m_r2, "ratio_computed_over_measured": c_slope / m_slope}
    def per_sub(e: dict, x: str, ref: str) -> float:
        return (e[x] - e[ref]) / N_SUBST_COMPUTED * 1000
    e_meas = {n: e for n, (e, _) in AQ_MEASURED_E12_V.items()}
    e_ours = {n: -b3[n]["dE_red_eV"] for n in AQ_MEASURED_E12_V}   # E° up to a constant: −ΔE_red
    pairs = []
    for x, ref in AQ_PAIRS:
        meas, ours, theirs = (per_sub(e, x, ref) for e in (e_meas, e_ours, AQ_SOURCE_DFT_E12_V))
        pairs.append({"x": x, "ref": ref, "measured_mV": meas, "ours_mV": ours, "source_dft_mV": theirs,
                      "ours_over_measured": ours / meas, "source_dft_over_measured": theirs / meas})
    aq = {"source": AQ_SOURCE, "reference_point": AQ_REF, "source_dft_E12_V": AQ_SOURCE_DFT_E12_V, "pairs": pairs,
          "measured_pairwise_slope_per_substituent_V_per_sigma": {
              f"{a}-{b}": (e_meas[b] - e_meas[a]) / (sigma[b] - sigma[a]) / N_SUBST_COMPUTED
              for a, b in (("ome", "dmbpy"), ("dmbpy", "cl"))},
          "assumptions": ["A1′ the monodentate N-donor (pyridine ⊥ 1-methylimidazole) shifts the absolute E°, not the substituent difference",
                          "A2′ formal charge +1/+2 in both; the free amine of ampy is likely protonated at pH 7.4 and PBS carries an "
                          "ionic strength our C-PCM lacks — both constant across the series",
                          "A3 sigma_para as in 21e SERIES, unchecked", "A4 vertical ΔSCF difference against an E1/2 difference"],
          "measured": measured, "computed_b3lyp": computed,
          "ratio_computed_over_measured_per_substituent": {n: computed[n]["shift_per_substituent_V"]
                                                           / measured[n]["shift_per_substituent_V"]
                                                           for n in AQ_MEASURED_E12_V if n != AQ_REF},
          "slope": slope, "slope_note": "a weighted mix of the pairs — the measured shifts are not linear in σp; not read as a slope"}
    osd = DFT_CACHE / "os_mediator_series_osdef2.json"   # 21e `b3lyp-osdef2`: the same protocol, def2-TZVP/ECP on Os
    if osd.exists():
        v = json.loads(osd.read_text(encoding="utf-8"))["vs_lanl2dz"]
        aq["os_basis_check"] = {"max_pair_change_mV": max(abs(p["change_mV"]) for p in v["pairs"]),
                                "point_shift_meV": [min(v["point_shift_eV"].values()) * 1000, max(v["point_shift_eV"].values()) * 1000],
                                "pairs": len(v["pairs"]), "rescued_def2_rows": v["rescued_def2_rows"]}
    def finished(f: str):   # a cache still being written has no vs_series yet
        path = DFT_CACHE / f
        return json.loads(path.read_text(encoding="utf-8"))["vs_series"] if path.exists() and \
            "vs_series" in json.loads(path.read_text(encoding="utf-8")) else None

    def entry(v: dict) -> dict:
        by = {(p["x"], p["ref"]): p for p in v["pairs"]}
        return {"max_pair_change_mV": max(abs(p["change_mV"]) for p in v["pairs"]), "pairs": len(v["pairs"]),
                "ome_dmbpy_change_mV": by[("ome", "dmbpy")]["change_mV"],
                "aqueous_pairs_over_measured": {f"{x}-{r}": by[(x, r)]["variant_mV"]
                                                / next(p["measured_mV"] for p in pairs if (p["x"], p["ref"]) == (x, r))
                                                for x, r in AQ_PAIRS},
                "rescued_rows": v["rescued_rows"], "series_os3_s2_not_recorded": v["series_os3_s2_not_recorded"]}

    present = [(k, v) for k, f, _ in SOLVATION_VARIANTS if (v := finished(f))]
    if present:   # 21e's continuum variants — each the series protocol with one knob changed
        meas = next(p["measured_mV"] for p in pairs if (p["x"], p["ref"]) == ("ome", "dmbpy"))
        ours = next(p["ours_mV"] for p in pairs if (p["x"], p["ref"]) == ("ome", "dmbpy"))
        aq["solvation_check"] = {"ome_dmbpy_excess_mV": ours - meas}
        for k, v in present:
            aq["solvation_check"][k] = entry(v)
    if (v := finished(AXIAL_VARIANT[1])):   # 21e `b3lyp-pyaxial` — the axial N-donor, the one knob of A1′
        aq["axial_check"] = entry(v)
    aq["verdict"] = verdict_aqueous(aq)
    return aq


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
        "aqueous_series": aqueous(sigma, b3),
        "pvi_series": pvi(sigma, b3),
    }
    rec["verdict"] = verdict(rec)
    OUT.write_text(json.dumps(rec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(rec["verdict"])
    print(rec["aqueous_series"]["verdict"])
    print(rec["pvi_series"]["verdict"])
    print(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
