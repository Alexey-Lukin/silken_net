#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""① against Lever's additive E_L scheme — the per-substituent shift of E°(Os III/II) that Lever's ligand parameters
predict for our bis-bpy chloro core, beside the computed (21e) and the measured (83's three series) shifts (00_07 HW.5.IS,
Стаття 1 self-review round 2, П4 (г) — the paper said «not triangulated here against Lever's additive E_L parametrisation»).

SOURCE — read from the page images of a scan on 2026-10-30, NOT from the version of record:
  Lever, A. B. P. «Electrochemical Parametrization of Metal Complex Redox Potentials, using the Ruthenium(III)/Ruthenium(II)
  Couple to generate a Ligand Electrochemical Series», Office of Naval Research Technical Report No. 27, York University
  (pages dated 10/8/89 and 10/17/89) — the manuscript submitted to Inorganic Chemistry and published as Inorg. Chem. 1990,
  29, 1271–1285, doi:10.1021/ic00331a030 (paper ref 23; the DOI checked on Crossref 2026-10-30). The copy read is an
  academia.edu upload of the scanned report (54 pages; sha256 in LEVER_COPY). The version of record was NOT read, so
  every number below is the REPORT's and may differ from the published tables (in-silico §Critical Rules #43).
  Table 1 (report pp. 15–19): E_L per donor site, V vs NHE. Table 2 (report p. 20): S_M and I_M per couple.
  Convention (report p. 4, eq. 3): [Ru(bpy)3]2+ has six identical Ru–N bonds and E_L(bpy) was first set to 1.53/6, so a
  bipyridine counts TWICE — once per donor atom.

MODEL. E°(M n/n−1) = S_M · ΣE_L + I_M. In our cis-[Os(4,4'-X2-bpy)2(1-MeIm)Cl]+ the two substituted bipyridines hold four
of the six sites and carry four substituents — one per site — so the shift from a reference ligand, per substituent, is
S_M · k · ΔE_L, with k = 1 for a 4,4'-disubstituted bpy. The axial ligands cancel in every difference. Of our series Table 1
holds the 4,4'-disubstituted Me2 row only (also Br2 and Ph2, which we did not compute); two rows come through a NAMED transfer:
  (L1) 4-nitro-bpy is mono-substituted — one NO2 per two sites — so per NO2 substituent the site shift is k = 2 times its
       ΔE_L: additivity WITHIN the ligand, not shown by the report;
  (L2) Br stands for Cl as a halogen of the same σp — 0.23 for Cl in 21e's SERIES, 0.23 for Br from the same Hansch–Leo–Taft
       compilation, unchecked like 83's A3 — never as Cl's own E_L, which the table does not have.
The report's 4-substituted PYRIDINE rows (4-COOH, 4-Cl, 4-CF3 …) are not used: most carry «(Aq)» — derived from aqueous
ruthenium ammine data «assuming a perfect fit» (Table 1, footnote b) — and they would add a monodentate → bipyridine transfer.

LINES — on the Cl pairs at the half-range, the side a reading falls on is set by the line. Table 2 prints two Os(III)/Os(II) lines: organic (1.01, SE 0.02,
80 points) and water (1.61, SE 0.05, 18 points). In organic solvents S_M and I_M «are generally insensitive to the net charge
of the species» (the report's abstract) — but «the slope is also influenced by the solvent» (p. 10), so for an aqueous reading
the organic line is a solvent transfer; the water one the report defines only «for the net charge (2+) species» — «there are insufficient data to define the slopes for other
net charge species» — dominated by polyammines (1.76 for the ammines alone), and ascribes its steepness to outer-sphere
solute–solvent interaction and entropy (p. 10), neither of which a vertical C-PCM ΔSCF carries. (L3) Every aqueous reading
here — ours, ref 8's PVI films, the ampy series — is a +1 Os(II) complex, so the water line is borrowed across charge for
all three. Which line describes a +1 complex in water the report does not say, so EVERY reading is judged on BOTH lines.
BANDS, each k · S_M · (the summed half-widths of the two E_L): ROUNDING — half the last printed digit (0.01 V; bpy 0.001);
RANGE — the several values of one ligand's E_L from different complexes «usually do not differ by more than 20mV» (report
p. 4): ±20 mV, the report's own number; HALF-RANGE — a row listed from 1–3 complexes (the rows used carry no braces, Table 1,
footnote a) is typically within ±10 mV of the ligand's average; HALF-RANGE-ALL — the same ±10 mV on bpy too, the band a
departure of OUR complexes from additivity would need. bpy, averaged over 94 complexes, is otherwise held at its rounding.
Summed linearly.

CAN show: per pair, line and band, on which side of Lever's prediction our computed and each measured shift lies. CANNOT show:
OMe, COOH, CF3, SO2CF3, NMe2 and NH2 (no 4,4'-row — the E_L–σ relation of Masui & Lever, Inorg. Chem. 1993, 32, 2199, would
cover them; not read); whether the version of record changed a value; whether the transfers L1–L3 hold, or which line a +1
complex in water follows; how far OUR complexes depart from additivity — bpy included (with ±10 mV on bpy too, NO2 − H lies
inside the water line — the `half_range_all` band); S_M's standard error, the scatter of the water data about their line (p. 10) and the lines' own
scatter (R 0.98 / 0.99), none of which is in a band; the measured series' own errors (ref 8's Me complex at a second loading,
from another source as well, differs by 135 mV per complex); our shift beyond the programmatic vertical B3LYP one — the relaxed Cl rows of 83 are read
(`relaxed_ours`), the relaxed NO2 row is not; the absolute E° of our complex (I_M's ±0.11 V and the media mismatch outweigh
every shift here).
WITNESS: the page images, Table 1 re-read at 300 dpi on 2026-10-30 — the first read, at 130 dpi, took 4,4'-Br2bpy's «0.28» for
«0.26» (caught by this script's adversary at 300 dpi, against the same page's 6s and 8s). A misread S_M or I_M no check here
would see.
"""
from __future__ import annotations

import json
import sys
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import DFT_CACHE
from lib.utils import banner

SI_DESCRIPTION = ("Shift of the Os(III/II) potential per 4,4'-bipyridine substituent predicted by Lever's additive ligand "
                  "electrochemical parameters (E_L, S_M), read from the Office of Naval Research report that is the submitted "
                  "manuscript of paper ref 23, beside the computed shift and the three measured series of script 83.")
LEVER_SOURCE = {
    "title": "Electrochemical Parametrization of Metal Complex Redox Potentials, using the Ruthenium(III)/Ruthenium(II) "
             "Couple to generate a Ligand Electrochemical Series",
    "author": "A. B. P. Lever", "document": "Office of Naval Research Technical Report No. 27, York University",
    "dated": "10/8/89 (Table 2) · 10/17/89 (Table 1)",
    "published_as": "Inorg. Chem. 1990, 29, 1271–1285, doi:10.1021/ic00331a030 (paper ref 23; Crossref 2026-10-30)",
    "read": "2026-10-30, page images of the scan (Table 1 at 300 dpi); the version of record was NOT read",
}
LEVER_COPY = {"host": "academia.edu upload of the scanned report", "pages": 54,
              "sha256": "9abbd839b0fde08994fdd415563b606e5b050e1ed92f4cc02b9a487938d11730"}
# Table 1, E_L per donor site (V vs NHE), with its printed precision and where it stands
LEVER_EL = {
    "bpy": (0.259, 0.001, "2,2'-Bipyridine {94}, report p. 15"),
    "dmbpy": (0.23, 0.01, "2,2-Bipyridine, 4,4-dimethyl (4,4-Me2bpy), report p. 15"),
    "br2bpy": (0.28, 0.01, "2,2-Bipyridine, 4,4'-dibromo (4,4-Br2bpy), report p. 15"),
    "no2_mono": (0.30, 0.01, "2,2-Bipyridine, 4-nitro, report p. 15"),
}
# Table 2, Os(III)/Os(II): slope S_M ± standard error, intercept I_M ± standard error (V vs NHE), number of points
LEVER_OS = {"water": {"S_M": 1.61, "S_M_se": 0.05, "I_M": -1.30, "I_M_se": 0.11, "n": 18},
            "organic": {"S_M": 1.01, "S_M_se": 0.02, "I_M": -0.40, "I_M_se": 0.11, "n": 80}}
RANGE_V = 0.020   # report p. 4: one ligand's E_L values from different complexes «usually do not differ by more than 20mV»
BANDS = {"rounding": None, "half_range": RANGE_V / 2, "range": RANGE_V, "half_range_all": RANGE_V / 2}   # None = half-digit
N_SUBST_COMPUTED = 4   # cis-[Os(4,4'-X2-bpy)2(1-MeIm)Cl]: two bpy, two substituents each — 83's constant
# (our X, our reference, Lever's row for X, Lever's row for the reference, k, the transfer it needs)
PAIRS = (("dmbpy", "bpy", "dmbpy", "bpy", 1, None),
         ("cl", "bpy", "br2bpy", "bpy", 1, "L2"),
         ("cl", "dmbpy", "br2bpy", "dmbpy", 1, "L2"),
         ("no2", "bpy", "no2_mono", "bpy", 2, "L1"))
OUT = DFT_CACHE / "os_series_vs_lever.json"


def mv(v: float) -> str:
    """A shift in mV, one decimal, half-up on the decimal string (so −27.75 prints −27.8, not float's −27.7)."""
    return f"{Decimal(repr(v * 1e3)).quantize(Decimal('0.0001')).quantize(Decimal('0.1'), ROUND_HALF_UP):+}"


def half_width(name: str, band: str) -> float:
    printed = LEVER_EL[name][1]
    if band == "rounding" or (name == "bpy" and band != "half_range_all"):
        return printed / 2
    return BANDS[band]


def lever_shift(x: str, ref: str, k: int, line: str) -> dict:
    """Per-substituent shift, V: S_M · k · ΔE_L, and its bands (module docstring)."""
    s = LEVER_OS[line]["S_M"]
    mid = s * k * (LEVER_EL[x][0] - LEVER_EL[ref][0])
    out = {"shift_V": mid}
    for band in BANDS:
        h = s * k * (half_width(x, band) + half_width(ref, band))
        out[f"{band}_band_V"] = [mid - h, mid + h]
    return out


def side(value: float, band: list) -> str:
    return "inside" if band[0] <= value <= band[1] else ("above" if value > band[1] else "below")


def measured_per_substituent(m83: dict, x: str, ref: str) -> dict:
    """The measured per-substituent shift of the same pair in each of 83's series that holds both points."""
    out = {}
    mecn = m83["measured"]
    if x in mecn and ref in mecn:   # MeCN, homoleptic tris: 83 stores the shift to bpy per substituent
        out["mecn_tris"] = mecn[x]["shift_per_substituent_V"] - mecn[ref]["shift_per_substituent_V"]
    pvi = m83["pvi_series"]["measured_E_V"]
    if x in pvi and ref in pvi:   # paper ref 8, our core with PVI: E°′ per complex → per substituent
        out["pvi_ref8"] = (pvi[x]["E_V"] - pvi[ref]["E_V"]) / N_SUBST_COMPUTED
    aq = m83["aqueous_series"]["measured"]
    if x in aq and ref in aq:   # Montón-Vicente 2026, our core with ampy, PBS: per substituent to dmbpy
        out["aqueous_ampy"] = aq[x]["shift_per_substituent_V"] - aq[ref]["shift_per_substituent_V"]
    return out


def sides(r: dict) -> dict:
    """{reading: {line: {band: side}}} — every reading on both lines and in every band."""
    vals = {"ours": r["computed_b3lyp_V"], **r["measured_V"]}
    return {k: {line: {band: side(v, r["lever"][line][f"{band}_band_V"]) for band in BANDS} for line in LEVER_OS}
            for k, v in vals.items()}


def outside(rows: list, line: str, band: str) -> list:
    """(pair, reading, side) for every reading that falls outside the band on that line."""
    return [(r["pair"], k, s[line][band]) for r in rows for k, s in r["sides"].items() if s[line][band] != "inside"]


def verdict(rows: list) -> str:
    cells = []
    for line in LEVER_OS:
        for band in ("half_range", "range", "half_range_all"):
            out = outside(rows, line, band)
            what = ("every reading inside on every pair" if not out else
                    "outside: " + ", ".join(f"{who} {where} on {pair}" for pair, who, where in out))
            cells.append(f"{line} line, {band.replace('_', '-')} band — {what}")
    preds = "; ".join(f"{r['pair']}{' (' + r['transfer'] + ')' if r['transfer'] else ''}: Lever "
                      f"{mv(r['lever']['organic']['shift_V'])} organic / {mv(r['lever']['water']['shift_V'])} water, ours "
                      f"{mv(r['computed_b3lyp_V'])}" + "".join(f", {k} {mv(v)}" for k, v in r["measured_V"].items())
                      for r in rows)
    return ("Per 4,4'-substituent, mV, against Lever's E_L scheme (ONR report of paper ref 23, not the version of record) — "
            + preds + ". Each reading on both lines: " + " · ".join(cells) + ". Which side a reading takes depends on the "
            "line and the band, and the report defines no line for a +1 complex in water. OMe, COOH, CF3, SO2CF3, NMe2 and NH2 "
            "have no 4,4'-row in Table 1.")


def relaxed_ours(m83: dict, rows: list) -> dict:
    """83's relaxed readings of OUR Cl pairs (ref 8's rows hold them) on both lines, at the half-range with and without bpy."""
    by = {r["pair"]: r for r in rows}
    out = {}
    for p in m83["relaxed_geometry_check"]["acceptors"]["pairs_vs_measured"]:
        if p["series_name"] != "ref 8" or p["pair"] not in by:
            continue
        r = by[p["pair"]]
        out[p["pair"]] = {tier: {"shift_mV": p[f"{tier}_mV"],
                                 "sides": {ln: {band: side(p[f"{tier}_mV"] / 1e3, r["lever"][ln][f"{band}_band_V"])
                                                for band in ("half_range", "half_range_all")} for ln in LEVER_OS}}
                          for tier in ("series", "relaxed", "adiabatic")}
    return out


def main() -> int:
    banner("① Os(III/II) substituent shift against Lever's E_L scheme")
    b3 = {c["name"]: c for c in json.loads((DFT_CACHE / "os_mediator_series.json").read_text(encoding="utf-8"))["complexes"]}
    m83 = json.loads((DFT_CACHE / "os_series_vs_measured.json").read_text(encoding="utf-8"))
    rows = []
    for x, ref, lx, lref, k, transfer in PAIRS:
        ours = -(b3[x]["dE_red_eV"] - b3[ref]["dE_red_eV"]) / N_SUBST_COMPUTED   # E° shift = −ΔΔE_red (83's convention)
        rows.append({"pair": f"{x}-{ref}", "lever_rows": [lx, lref], "k": k, "transfer": transfer,
                     "lever": {line: lever_shift(lx, lref, k, line) for line in LEVER_OS},
                     "computed_b3lyp_V": ours, "measured_V": measured_per_substituent(m83, x, ref)})
        rows[-1]["sides"] = sides(rows[-1])
        r = rows[-1]
        print(f"  {x:>5s} − {ref:<5s} Lever organic {mv(r['lever']['organic']['shift_V'])} · water "
              f"{mv(r['lever']['water']['shift_V'])}   ours {mv(ours)}  measured "
              + ", ".join(f"{k2} {mv(v)}" for k2, v in r["measured_V"].items()))
    rec = {
        "script": Path(__file__).name,
        "question": "① П4 (г) — on which side of Lever's additive E_L prediction do the computed and the measured "
                    "per-substituent shifts of E°(Os III/II) fall, per line and band?",
        "source": LEVER_SOURCE, "copy": LEVER_COPY,
        "convention": "each bipyridine counts twice (report p. 4, eq. 3); four substituents per complex, one per site",
        "E_L_V_vs_NHE": {k: {"E_L": v, "printed_to": p, "where": w} for k, (v, p, w) in LEVER_EL.items()},
        "os_iii_ii_lines": LEVER_OS,
        "transfers": {"L1": "4-nitro-bpy (mono) for 4,4'-(NO2)2-bpy: additivity within the ligand, k = 2",
                      "L2": "4,4'-Br2-bpy for 4,4'-Cl2-bpy: a halogen of the same σp (0.23; Br's unchecked), not Cl's own E_L",
                      "L3": "the water line is defined for net-charge 2+ species (report p. 10); every aqueous reading here "
                            "(ours, ref 8, ampy) is a +1 Os(II) complex"},
        "bands": {"rounding": "half the last printed digit of each E_L",
                  "half_range": f"±{RANGE_V / 2} V per E_L — one complex typically within half the usual 20 mV range "
                                "between complexes (report p. 4)",
                  "range": f"±{RANGE_V} V per E_L — that usual maximum",
                  "always": "bpy (94 compounds) keeps its rounding; summed linearly; S_M's SE and the water scatter left out"},
        "witness": "page images; Table 1 re-read at 300 dpi 2026-10-30 (a 130-dpi read had taken Br2bpy's 0.28 for 0.26)",
        "pairs": rows,
        "relaxed_ours": relaxed_ours(m83, rows),
        "not_covered": ["ome", "dcbpy", "cf3", "so2cf3", "nme2", "nh2"],
        "verdict": verdict(rows),
    }
    OUT.write_text(json.dumps(rec, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
    print("\n" + rec["verdict"])
    banner(f"✅ Saved {OUT.name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
