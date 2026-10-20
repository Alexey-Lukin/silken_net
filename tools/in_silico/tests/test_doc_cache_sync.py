# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Doc↔cache numeric-drift guard for the EBFC in-silico pipeline.

The cache JSON is SSOT (see the `in-silico` skill: cache-is-SSOT). Every headline number
quoted in SUMMARY / L3 / the paper MUST equal its owner cache within display rounding.

Why this guard exists (and why `test_cache_integrity.py` is not enough): a model-swap or
re-run leaves a *self-consistent stale pocket* — the doc stays internally consistent on the
OLD value, so `rg`/graphify flag zero conflicts. Only dumping the owner cache and diffing
against the doc catches it (the 2026-06-19 dimethyl recompute; the −1.054/−1.051 provenance
mix; the xylem-pH column drift). This guard does exactly that, CONTEXT-ANCHORED: the same
number legitimately appears against different owners (cascade Δ −1.051 = comparison.json /
script 22, vs −1.054 = microsolvation_dmbpy.json k0 / script 34), so each check anchors on
the surrounding label text, never a bare number.

Runs without the conda env (stdlib + json only) — safe for CI.
Add a row to CHECKS when you add a headline number with a clean single cache-owner.
Tolerance rule: ~1 unit in the doc's last displayed digit (honours "within display rounding").
"""
import fnmatch
import itertools
import json
import math
import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
CACHE = REPO / "tools/in_silico/cache"

# ── loaders (memoized) ──
_CACHE: dict = {}
_DOC: dict = {}


def C(rel: str):
    """Load a cache JSON by path relative to tools/in_silico/cache/."""
    if rel not in _CACHE:
        _CACHE[rel] = json.loads((CACHE / rel).read_text(encoding="utf-8"))
    return _CACHE[rel]


def _dscf_vertical_eV(d) -> float:
    """21g's vertical ΔG from its DEFINITION — its energies and B1's — never from the 4-decimal display row: 0.38745 is
    stored as 0.3875, so a 3-decimal quote of the row reads +0.388 against a true +0.387 (in-silico §When Modifying #6)."""
    from lib.constants import HARTREE_TO_EV
    b1 = C("dft/os_complex_wb97xd_dmbpy.json")
    ea = (b1["os3_plus"]["E_total_Ha"] - b1["os2_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    return (d["E_FADH2_cation_vertical_Ha"] - d["E_FADH2_Ha"]) * HARTREE_TO_EV - ea


def doc(rel: str) -> str:
    """Read a doc by path relative to the repo root."""
    if rel not in _DOC:
        _DOC[rel] = (REPO / rel).read_text(encoding="utf-8")
    return _DOC[rel]


DONORS = ("ome", "dmbpy", "bpy")   # the relaxed donors — pins over the (3а)/(3б) comparisons stay on them, so the
# acceptor points (⚖️ 2026-10-14) landing in the same caches never move what these pins stand on


def _donor_pairs(cmp: dict) -> list:
    return [p for p in cmp["pairs"] if p["x"] in DONORS and p["ref"] in DONORS]


def _donor_points(cmp: dict) -> list:
    return [s for n, s in cmp["point_shift_eV"].items() if n in DONORS]


def named(rows, key, value):
    """First dict in a list whose [key] == value (micro-solvation / xylem / kinetics lists)."""
    for r in rows:
        if r.get(key) == value:
            return r
    raise KeyError(f"no row with {key}={value!r}")


def xylem_rows(d):
    return d.get("sweep", d) if isinstance(d, dict) else d


# Every dash variant that can stand in for a minus sign in a doc number:
# hyphen-minus U+002D, minus U+2212, en-dash U+2013, em-dash U+2014,
# hyphen U+2010, non-breaking hyphen U+2011, fullwidth hyphen-minus U+FF0D.
_DASHES = "−–—‐‑－"


# Superscript digits, so a doc cell written as `3.6×10⁴` is pinnable like a plain decimal. Without
# this the harness parses only the convenient half of a table, and a pin that covers half a table
# reads like a pin that covers the table.
# ⁻ is U+207B SUPERSCRIPT MINUS — a different codepoint from every dash in `_DASHES`, so it has to
# be named here; omitting it made `7.4×10⁻⁶` raise instead of parse (caught on the first probe).
_SUP_MINUS = "⁻"
_SUP = "⁰¹²³⁴⁵⁶⁷⁸⁹"
_SUP_MAP = ({c: str(i) for i, c in enumerate(_SUP)}
            | dict.fromkeys(_DASHES, "-") | {_SUP_MINUS: "-"})


def _hexa(d: dict, name: str) -> float:
    """ΔE_red (eV) of one [Os(H₂O)ₙ] shell row of 34's microsolvation.json."""
    return next(r for r in d["results"] if r["name"] == name)["dE_red_eV"]


def _ss_after(d: dict, form: str, level: str) -> float:
    """A cell's cascade (mV) after spin–orbit coupling alone — read from 95's `shared_shifts`, NaN when that cell does not
    flip (the doc names it as one that does)."""
    hit = [u for u in d["shared_shifts"]["terms"]["spin_orbit_os"]["uphill"] if u["form"] == form and u["level"] == level]
    return 1000 * hit[0]["after_V"] if hit else float("nan")


def _to_float(s: str) -> float:
    if s == "∞":
        return math.inf
    for d in _DASHES:
        s = s.replace(d, "-")
    s = s.replace(" ", "")
    if "×10" in s:
        mant, _, exp = s.partition("×10")
        return float(mant) * 10 ** int("".join(_SUP_MAP.get(c, c) for c in exp))
    return float(s)


SUMMARY = "docs/protocols/ebfc/in_silico/SUMMARY.md"
L3 = "docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md"
PIPELINE = "docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md"
CODIT = "docs/01_04_CODIT_and_Xylemointegration.md"  # thermal-penetration cache (§3.5) — a non-SUMMARY doc-target
BLIND_MATE = "docs/02_02_Blind_Mate_Pogo_Pin_Interface.md"  # Z-stack + gland geometry (§3.5), owner = script 52
COAXIAL = "docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md"  # anchor geometry; §1.4 bus + liner, owner = script 55
METALLURGY = "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md"  # §2.1 synthetic sap + its saturation verdict, owner = script 67
SAP = "chemistry/sap_recipe_saturation.json"
PAPER_RESULTS = "docs/protocols/ebfc/in_silico/paper/03_results.md"  # §3.4 cathode DET, owner = script 25
L1 = "docs/protocols/ebfc/in_silico/L1_protein_architecture.md"  # §2 aggregation recipe, owner = script 69
CHEM11 = "chemistry/chem11_aggregation_compensation.json"
CONSERVATION = "chemistry/chem11_site_conservation.json"  # §2 conservation block, owner = script 70

# Each check: (label, doc-path, regex with ONE capture group = the doc number,
#             cache-file, resolver(cache)->float, tolerance).
# Number class allows an optional leading sign: a dash of any flavour, or an explicit plus — a cascade
# that changes sign is written «+0.068», and a class without «+» reads that cell as absent, not as drift.
N = rf"([+{_DASHES}\-]?[\d.]+)"


def _sf97_floor(d: dict) -> float:
    """97's lowest drawn-wire SF under either edge inside ⌀0.10, rounded DOWN to the doc's one decimal — «не нижче» / «is» a floor."""
    return math.floor(min(f["sf_drawn_wire"] for r in d["rows"] if r["offset_um"] <= d["summary"]["tolerance_offset_um"]
                          for st in ("mouth", "exit") for f in r[st]["faces"].values()) * 10) / 10


def _pine85(d: dict) -> dict:
    """85's anchor anode on the pine part — the one SUMMARY quotes by number."""
    return d["anchor_anode_sap_gap"]["by_sku"]["anchor_zone1_pine"]


def _wbl(d: dict) -> dict:
    """87's (C)-behind-the-liner ceiling — it reads no slope reading."""
    return d["C_wire_behind_liner"]


def _up2(x: float) -> float:
    """A requirement «k ≥ X» rounded UP to the doc's two decimals (in-silico §When Modifying #43)."""
    return math.ceil(x * 100 - 1e-9) / 100


def _down2(x: float) -> float:
    """A floor «SF drops to X» rounded DOWN to the doc's two decimals (in-silico §When Modifying #43)."""
    return math.floor(x * 100 + 1e-9) / 100
NSCI =rf"([{_DASHES}\-]?[\d.]+(?:×10[{_SUP_MINUS}]?[{_SUP}]+)?)"
CHECKS = [
    # ── PRIMARY: the provenance-mix the guard exists to catch ──
    (
        "cascade Δε Marcus-verdict → comparison.json (script 22 gate)",
        SUMMARY, rf"Raw Δε \(dimethyl\) \| {N} eV",
        "dft/comparison.json", lambda d: d["delta_eV"], 0.001,
    ),
    (
        "cascade Δε ωB97X-table B3LYP col → comparison.json",
        L3, rf"\| Δε \(dimethyl\) \| {N} eV \| \*\*[{_DASHES}\-][\d.]+",
        "dft/comparison.json", lambda d: d["delta_eV"], 0.001,
    ),
    (
        "cascade Δε ωB97X-table ωB97X col → os_complex_wb97xd + _dmbpy",
        L3, rf"\| Δε \(dimethyl\) \| [+{_DASHES}\-]?[\d.]+ eV \| \*\*{N} eV\*\*",
        "dft/os_complex_wb97xd.json",
        lambda d: d["fadh2_red"]["HOMO_eV"] - C("dft/os_complex_wb97xd_dmbpy.json")["os3_plus"]["LUMO_eV"], 0.001,
    ),
    (
        "§2.7 Koopmans offset, recorded environment → comparison.json",
        "docs/protocols/ebfc/in_silico/paper/02_methods.md", rf"offset {N} eV in the recorded environment read",
        "dft/comparison.json", lambda d: d["delta_eV"], 0.0001,
    ),
    (
        "§2.7 Koopmans offset under the lock → lumiflavin.json + lock record 2026-10-01",
        "docs/protocols/ebfc/in_silico/paper/02_methods.md",
        rf"read [{_DASHES}\-]?[\d.]+, [{_DASHES}\-]?[\d.]+ and {N} eV under the lock",
        "dft/lumiflavin.json",
        lambda d: d["red"]["HOMO_eV"] - C("reproduction/lock_rerun_2026-10-01.json")["files"]["dft/os_complex.json"]["per_field"]["os3_plus.LUMO_eV"]["lock_rerun"],
        0.0001,
    ),
    (
        "cascade Δε k0 ladder → microsolvation_dmbpy.json (script 34 — DIFFERENT owner)",
        # anchored on the chemistry table header "gap closed vs k0" (not a bare "| 0 |")
        SUMMARY, rf"gap closed vs k0[\s\S]{{1,60}}?\| 0 \| {N} \|",
        "dft/microsolvation_dmbpy.json",
        lambda d: named(d["results"], "name", "mediator_k0_clwaters")["cascade_delta_eV"], 0.001,
    ),
    # ── Anode frontier + ΔSCF ──
    (
        "ε_HOMO(FADH₂) → comparison.json",
        SUMMARY, rf"ε_HOMO\(FADH₂\) \| {N} eV",
        "dft/comparison.json", lambda d: d["donor_homo_eV"], 0.001,
    ),
    (
        "ε_LUMO(Os III) dmbpy → os_complex.json (21f, identity-pinned)",
        SUMMARY, rf"ε_LUMO\(Os\(III\)\) dmbpy \| {N} eV",
        "dft/os_complex.json", lambda d: d["os3_plus"]["LUMO_eV"], 0.001,
    ),
    (
        "EA_Os3 (B1) → os_complex_wb97xd_dmbpy.json",
        SUMMARY, r"EA_Os3 = \*\*([\d.]+) eV\*\* from B1",
        "dft/os_complex_wb97xd_dmbpy.json", lambda d: d["EA_Os3_eV"], 0.001,
    ),
    (
        "ΔSCF adiabatic → delta_scf_corrections.json",
        SUMMARY, rf"adiabatic \*\*{N}\*\* = IP_adiab",
        "dft/delta_scf_corrections.json", lambda d: d["dG_adiabatic_eV"], 0.0005,
    ),
    (
        "IP_adiab(FAD) → delta_scf_corrections.json",
        SUMMARY, r"IP_adiab\(FAD ([\d.]+)\)",
        "dft/delta_scf_corrections.json", lambda d: d["IP_adiabatic_eV"], 0.001,
    ),
    # The step-2 flavin chain re-run from the butterfly minimum (00_07 HW.5.IS, 2026-10-19): the adiabatic ΔG crossed zero
    # (−0.079 → +0.048 eV) and none of the numbers below had a pin — the PCET cascade, the vertical ΔSCF and the saddle
    # heights were quoted unguarded in SUMMARY · L3 · PIPELINE_STATUS
    ("ΔSCF vertical, all-methods table → delta_scf_corrections.json", SUMMARY, rf"\| ΔSCF ωB97X \(vertical\) \| {N} \|",
     "dft/delta_scf_corrections.json", _dscf_vertical_eV, 0.0005),
    ("ΔSCF adiabatic, all-methods table → delta_scf_corrections.json", SUMMARY, rf"\| \*\*ΔSCF ωB97X \(adiabatic\)\*\* \| \*\*{N}\*\*",
     "dft/delta_scf_corrections.json", lambda d: d["dG_adiabatic_eV"], 0.0005),
    ("ΔSCF vertical, B2 → delta_scf_corrections.json", SUMMARY, rf"The vertical {N} \(IP_vert",
     "dft/delta_scf_corrections.json", _dscf_vertical_eV, 0.0005),
    ("IP_vert, B2 → delta_scf_corrections.json", SUMMARY, r"\(IP_vert ([\d.]+);",
     "dft/delta_scf_corrections.json", lambda d: d["IP_vertical_eV"], 0.001),
    ("cation relaxation, B2 → delta_scf_corrections.json", SUMMARY, rf"cation relaxation {N} eV\)",
     "dft/delta_scf_corrections.json", lambda d: d["relaxation_eV"], 0.001),
    ("ΔSCF adiabatic, L3 row → delta_scf_corrections.json", SUMMARY, rf"uphill: the adiabatic ΔSCF \(ΔG {N} eV\)",
     "dft/delta_scf_corrections.json", lambda d: d["dG_adiabatic_eV"], 0.005),
    ("PCET cascade, L3 row → pcet_cascade.json", SUMMARY, rf"and PCET \(ΔG {N} eV\)",
     "dft/pcet_cascade.json", lambda d: d["cascade_pcet_eV"], 0.005),
    ("PCET oxidation cost → pcet_cascade.json", L3, rf"PCET oxidation cost = \*\*{N} eV\*\*",
     "dft/pcet_cascade.json", lambda d: d["pcet_oxidation_cost_eV"], 0.005),
    ("PCET rise over the bare IP → pcet_cascade.json", L3, rf"than the bare IP \({N} eV;",
     "dft/pcet_cascade.json", lambda d: d["drop_vs_bare_eV"], 0.005),
    ("PCET cascade, L3 → pcet_cascade.json", L3, rf"Cascade = \*\*{N} eV \(still uphill\)",
     "dft/pcet_cascade.json", lambda d: d["cascade_pcet_eV"], 0.0005),
    ("21g FADH₂ saddle height → delta_scf_corrections.json", PIPELINE, rf"\*\*{N}\*\* meV above its minimum on `21g`",
     "dft/delta_scf_corrections.json", lambda d: d["minimum_check"]["FADH2"]["saddle_above_minimum_meV"][0], 0.05),
    ("33 FADH₂ saddle height → pcet_cascade.json", PIPELINE, rf"and \*\*{N}\*\* meV\s+on `33`",
     "dft/pcet_cascade.json", lambda d: d["minimum_check"]["FADH2"]["saddle_above_minimum_meV"][0], 0.05),
    # the copies the round-2 review found unpinned (L3 · the PIPELINE banner · SUMMARY's L3 row)
    ("ΔSCF vertical, L3 full row → delta_scf_corrections.json", L3, rf"\*\*{N} \(UPHILL\)\*\*",
     "dft/delta_scf_corrections.json", _dscf_vertical_eV, 0.0005),
    ("ΔSCF vertical, L3 methods table → delta_scf_corrections.json", L3, rf"\| ΔSCF ωB97X \(vertical\) \| {N} \| [\d.]+ \| same molecule",
     "dft/delta_scf_corrections.json", _dscf_vertical_eV, 0.0005),
    ("IP_vert, L3 half-reaction → delta_scf_corrections.json", L3, rf"\| \*\*{N}\*\* \(cost; `IP_vertical_eV`",
     "dft/delta_scf_corrections.json", lambda d: d["IP_vertical_eV"], 0.001),
    ("IP_adiab, L3 relaxation → delta_scf_corrections.json", L3, rf"IP relaxation \(1,5-dihydro\): [\d.]+ → {N} eV",
     "dft/delta_scf_corrections.json", lambda d: d["IP_adiabatic_eV"], 0.001),
    ("cation relaxation, L3 → delta_scf_corrections.json", L3, rf"IP relaxation \(1,5-dihydro\): [\d.]+ → [\d.]+ eV \({N} eV\)",
     "dft/delta_scf_corrections.json", lambda d: d["relaxation_eV"], 0.001),
    ("ΔSCF adiabatic, banner → delta_scf_corrections.json", PIPELINE, rf"adiabatic ΔG [{_DASHES}\-]0\.079 → \*\*{N}\*\* eV",
     "dft/delta_scf_corrections.json", lambda d: d["dG_adiabatic_eV"], 0.0005),
    ("ΔSCF vertical, banner → delta_scf_corrections.json", PIPELINE, rf"vertical \+0\.095 → {N}, IP_adiab",
     "dft/delta_scf_corrections.json", _dscf_vertical_eV, 0.0005),
    ("IP_adiab, banner → delta_scf_corrections.json", PIPELINE, rf"IP_adiab 4\.164 → {N}; `33`",
     "dft/delta_scf_corrections.json", lambda d: d["IP_adiabatic_eV"], 0.001),
    ("PCET cost, banner → pcet_cascade.json", PIPELINE, rf"PCET cost 4\.711 → {N} eV",
     "dft/pcet_cascade.json", lambda d: d["pcet_oxidation_cost_eV"], 0.0005),
    ("PCET cascade, banner → pcet_cascade.json", PIPELINE, rf"cascade\s+\+0\.468 → \*\*{N}\*\* eV",
     "dft/pcet_cascade.json", lambda d: d["cascade_pcet_eV"], 0.0005),
    ("ΔSCF vertical, SUMMARY L3 row → delta_scf_corrections.json", SUMMARY, rf"the vertical ΔSCF \(ΔG {N}\)",
     "dft/delta_scf_corrections.json", _dscf_vertical_eV, 0.005),
    (
        "PCET E°(FAD/FADH₂) pH7 → pcet_redox_potential.json",
        SUMMARY, rf"E°\(FAD/FADH₂\) = \*\*{N} mV vs NHE",
        "dft/pcet_redox_potential.json", lambda d: d["E_vs_SHE_mV"]["pH_7.0"], 1.0,
    ),
    # The free-flavin exp value is −220 mV (ref 25) alone since 2026-10-02 (00_07 HW.5.IS): «within ~50 mV»
    # had been quoted from an unsourced −208 end, which the citation disposition rule then dropped.
    (
        "PCET Δ vs free-flavin −220 → pcet_redox_potential.json",
        SUMMARY, rf"lands \*\*{N} mV\*\* from the free-flavin",
        "dft/pcet_redox_potential.json", lambda d: d["delta_vs_exp_pH7_mV"][0], 1.0,
    ),
    # 97 — the wire under the liner's edges (HW.34, 2026-10-16): the table's SF cells and the four claims under it
    ("97 canon k_x bonded → wire_under_liner_edges", COAXIAL, rf"для кожного шва з `k` < \*\*{N}\*\*\s+на зчепленій основі",
     "mechanical/wire_under_liner_edges.json", lambda d: math.floor(d["summary"]["by_base"]["bonded"]["lowest_k_crossover_within_tolerance"]["k_crossover"] * 100) / 100, 1e-9),
    ("97 canon k_x frictionless → wire_under_liner_edges", COAXIAL, rf"і `k` < \*\*{N}\*\* на вільній",
     "mechanical/wire_under_liner_edges.json", lambda d: math.floor(d["summary"]["by_base"]["frictionless"]["lowest_k_crossover_within_tolerance"]["k_crossover"] * 100) / 100, 1e-9),
    ("97 canon liner-end factor → wire_under_liner_edges", COAXIAL, rf"номінал голого боку менш ніж у ×\*\*{N}\*\* за ідеального шва",
     "mechanical/wire_under_liner_edges.json", lambda d: math.floor(d["summary"]["by_base"]["bonded"]["liner_end_corner_factor_to_out_rank_within_tolerance"]["1"]["factor"] * 100) / 100, 1e-9),
    ("97 canon liner-end factor k=0.388 → wire_under_liner_edges", COAXIAL, rf"\(×\*\*{N}\*\* за `k` 0\.388\)",
     "mechanical/wire_under_liner_edges.json", lambda d: math.floor(d["summary"]["by_base"]["bonded"]["liner_end_corner_factor_to_out_rank_within_tolerance"]["0.388"]["factor"] * 100) / 100, 1e-9),
    *[(f"97 canon frictionless k_x arc bracket {end} → wire_under_liner_edges", COAXIAL, anchor, "mechanical/wire_under_liner_edges.json",
       (lambda d, i=i: math.floor(d["summary"]["by_base"]["frictionless"]["lowest_k_crossover_within_tolerance"]["k_crossover_contact_x1_3"][i] * 100) / 100), 1e-9)
      for end, i, anchor in (("low", 0, rf"опустила б поріг до \*\*{N}–"), ("high", 1, rf"опустила б поріг до \*\*[\d.]+–{N}\*\*"))],
    ("97 canon lowest drawn-wire SF → wire_under_liner_edges", COAXIAL, rf"під обома кромками не нижче {N}\.",
     "mechanical/wire_under_liner_edges.json", lambda d: _sf97_floor(d), 1e-9),
    ("97 k_x bonded → wire_under_liner_edges", SUMMARY, rf"for every seam with `k` < {N} on the bonded base",
     "mechanical/wire_under_liner_edges.json", lambda d: math.floor(d["summary"]["by_base"]["bonded"]["lowest_k_crossover_within_tolerance"]["k_crossover"] * 100) / 100, 1e-9),
    ("97 k_x frictionless → wire_under_liner_edges", SUMMARY, rf"\*\*and `k` < {N} on the frictionless base",
     "mechanical/wire_under_liner_edges.json", lambda d: math.floor(d["summary"]["by_base"]["frictionless"]["lowest_k_crossover_within_tolerance"]["k_crossover"] * 100) / 100, 1e-9),
    ("97 lowest drawn-wire SF inside ⌀0.10 → wire_under_liner_edges", SUMMARY, rf"under either edge inside ⌀0.10 is \*\*{N}\*\*",
     "mechanical/wire_under_liner_edges.json", lambda d: _sf97_floor(d), 1e-9),
    # (A): the contact's own tension per base (a reading; the bonded one quoted as a bound, so rounded UP) and its weight on 1/SF
    ("97 contact tension frictionless → wire_under_liner_edges", SUMMARY, rf"beside a patch is \*\*{N}\*\* MPa on the frictionless base",
     "mechanical/wire_under_liner_edges.json", lambda d: d["summary"]["by_base"]["frictionless"]["contact_tension_max"]["MPa"], 0.005),
    ("97 contact tension bonded (bound) → wire_under_liner_edges", SUMMARY, rf"and under\s+\*\*{N}\*\* MPa on the bonded one",
     "mechanical/wire_under_liner_edges.json", lambda d: math.ceil(d["summary"]["by_base"]["bonded"]["contact_tension_max"]["MPa"] * 1000) / 1000, 1e-9),
    ("97 contact weight on 1/SF max → wire_under_liner_edges", SUMMARY, rf"is largest — ×\*\*{N}\*\* — where the governing",
     "mechanical/wire_under_liner_edges.json", lambda d: d["summary"]["contact_factor_on_1_over_sf_max"]["factor"], 0.005),
    ("97 contact weight at a tensile mean (bound) → wire_under_liner_edges", SUMMARY, rf"by at most ×\*\*{N}\*\*\s+\(frictionless, 30 µm",
     "mechanical/wire_under_liner_edges.json", lambda d: math.ceil(d["summary"]["contact_factor_at_tensile_mean_max"]["factor"] * 100) / 100, 1e-9),
    *[(f"97 frictionless k_x arc bracket {end} → wire_under_liner_edges", SUMMARY, anchor, "mechanical/wire_under_liner_edges.json",
       (lambda d, i=i: math.floor(d["summary"]["by_base"]["frictionless"]["lowest_k_crossover_within_tolerance"]["k_crossover_contact_x1_3"][i] * 100) / 100), 1e-9)
      for end, i, anchor in (("low", 0, rf"would put it at \*\*{N}–"), ("high", 1, rf"would put it at \*\*[\d.]+–{N}\*\*"))],
    *[(f"97 liner-end factor {label} → wire_under_liner_edges", SUMMARY, anchor, "mechanical/wire_under_liner_edges.json",
       (lambda d, base=base, k=k: math.floor(d["summary"]["by_base"][base]["liner_end_corner_factor_to_out_rank_within_tolerance"][k]["factor"] * 100) / 100), 1e-9)
      for label, anchor, base, k in (
          ("bonded k=1", rf"less than ×\*\*{N}\*\* \(bonded, perfect seam", "bonded", "1"),
          ("frictionless k=1", rf"/ ×\*\*{N}\*\* \(frictionless, 50 µm\)", "frictionless", "1"),
          ("k=0.388", rf"or ×\*\*{N}\*\* with `k` 0.388", "bonded", "0.388"))],
    # The like-for-like block (32b's four donor levels · 95's table, 2026-10-16) — every table cell, so the thesis «direction +
    # table» of the like-for-like revision cannot quote a cascade its caches no longer give.
    *[(f"like-for-like flavin {key} → pcet_redox_potential_thermo", SUMMARY, anchor, "dft/pcet_redox_potential_thermo.json",
       lambda d, key=key: d["E_vs_SHE_mV"][key]["pH_7.0"], 0.05)
      for key, anchor in (("mmff_electronic", rf"\*\*{N}\*\* mV on the MMFF geometries \(32's protocol"),
                          ("relaxed_electronic", rf"· \*\*{N}\*\* mV relaxed ·"),
                          ("relaxed_plus_zpe", rf"· \*\*{N}\*\* mV \+ ZPE ·"),
                          ("relaxed_rrho_free_energy", rf"· \*\*{N}\*\* mV \+ RRHO free energy, against"))],
    ("like-for-like saddle height → pcet_redox_potential_thermo", SUMMARY, rf"\*\*{N}\*\* meV above it",
     "dft/pcet_redox_potential_thermo.json", lambda d: d["saddle_above_minimum_meV"]["red"][0], 0.05),
    *[(f"like-for-like table «{form}» column {j} → cascade_like_for_like", SUMMARY,
       rf"\| {re.escape(form)} \| " + r"[^|\n]* \| " * j + rf"{N} \|", "dft/cascade_like_for_like.json",
       lambda d, form=form, j=j: 1000 * (lambda r: [r["E_os_vs_SHE_V"], r["acceptor_side_V"],
                                                    *(c["cascade_V"] for c in r["by_donor_level"].values())][j])(
           next(r for r in d["forms"] if r["form"] == form)), 0.05)
      for form in ("chloro (device, programmatic)", *(f"chloro + {k} H₂O on Cl⁻" for k in (1, 2, 3)),
                   "chloro, Os(II) relaxed, Os(III) vertical", "chloro, both states relaxed (adiabatic)",
                   "aqua (methodological reference)", "bis-imidazole (operando form)")
      for j in range(6)],
    ("like-for-like measured same couples → cascade_like_for_like", SUMMARY, rf"film-bound mediator: \*\*{N}\*\* mV",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["measured"]["cascade_same_couples_V"], 0.5),
    ("like-for-like smallest cascade → cascade_like_for_like", SUMMARY, rf"smallest: \*\*{N}\*\* mV",
     "dft/cascade_like_for_like.json",
     lambda d: 1000 * min(c["cascade_V"] for r in d["forms"] for c in r["by_donor_level"].values()), 0.05),
    ("like-for-like device cancellation at ZPE → cascade_like_for_like", SUMMARY, rf"lands \*\*{N}\*\* mV from the measured \+529",
     "dft/cascade_like_for_like.json",
     lambda d: 1000 * abs(next(c["gap_V"] for c in d["cancellations"]["rows"]
                               if c["form"] == "chloro (device, programmatic)" and c["level"] == "relaxed_plus_zpe")), 0.05),
    # ⊕ 2026-10-18 — 96: the adiabatic chloro form with thermochemistry on BOTH sides (95's both_sided row)
    ("like-for-like 96 Os-side ZPE shift → os_couple_thermo", SUMMARY, rf"the ZPE moves E°\(Os\) by \*\*\+{N}\*\* mV",
     "dft/os_couple_thermo.json", lambda d: d["shift_vs_electronic_mV"]["plus_zpe"], 0.05),
    ("like-for-like both-sided electronic → cascade_like_for_like", SUMMARY, rf"the table's \*\*\+{N}\*\* mV on the electronic level",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["both_sided"]["levels"]["relaxed_electronic"]["cascade_V"], 0.05),
    ("like-for-like both-sided + ZPE → cascade_like_for_like", SUMMARY, rf"and \*\*\+{N}\*\* mV with the ZPE",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["both_sided"]["levels"]["relaxed_plus_zpe"]["cascade_V"], 0.05),
    ("like-for-like both-sided + ZPE over the measured → cascade_like_for_like", SUMMARY, rf"\*\*{N}\*\* mV over the measured \+529",
     "dft/cascade_like_for_like.json",
     lambda d: -1000 * d["both_sided"]["levels"]["relaxed_plus_zpe"]["gap_to_measured_same_couples_V"], 0.5),
    ("like-for-like adiabatic + ZPE one-sided, in the footnote → cascade_like_for_like", SUMMARY, rf"against \+{N} one-sided",
     "dft/cascade_like_for_like.json",
     lambda d: 1000 * next(r for r in d["forms"] if r["form"] == "chloro, both states relaxed (adiabatic)")["by_donor_level"]["relaxed_plus_zpe"]["cascade_V"], 0.05),
    ("like-for-like both-sided + ZPE, acceptor side → cascade_like_for_like", SUMMARY, rf"the acceptor side \+{N} and the donor",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["both_sided"]["levels"]["relaxed_plus_zpe"]["acceptor_side_V"], 0.5),
    ("like-for-like both-sided + ZPE, donor side → cascade_like_for_like", SUMMARY, rf"the donor side {N} mV\. Its RRHO",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["both_sided"]["levels"]["relaxed_plus_zpe"]["donor_side_V"], 0.5),
    # ⊕ 2026-10-19 — the choices every cell shares (95 `shared_shifts`): §3.5 states the direction as the protocol's, and
    # every number it sets against the cells is read here (referee rounds 2–3 of step 3 — spin–orbit coupling on Os, set
    # against the computed AND the measured flavin)
    *[(f"paper §3.5 shared shift: {lab} → cascade_like_for_like", PAPER_RESULTS, pat, "dft/cascade_like_for_like.json", fn, tol)
      for lab, pat, fn, tol in (
          ("smallest cascade", rf"the smallest cascade, \+{N} mV, is the device form", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["first_flip_at_V"], 0.05),
          ("SOC size", rf"by ≈ {N} mV in octahedral homoleptic complexes,<sup>19,63</sup>", lambda d: -1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["shift_V"], 0.5),
          ("first-flip threshold", rf"beyond the smallest margin, {N} mV,", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["first_flip_at_V"], 0.05),
          ("SOC cells uphill", rf"at the full octahedral value {N} of the 32 cells turn uphill", lambda d: d["shared_shifts"]["terms"]["spin_orbit_os"]["n_uphill"], 0.0),
          ("SOC cells counted", rf"value [\d]+ of the {N} cells turn uphill", lambda d: d["shared_shifts"]["terms"]["spin_orbit_os"]["n_cells"], 0.0),
          ("SOC device MMFF", rf"electronic flavin\s+levels \(to {N} and", lambda d: _ss_after(d, "chloro (device, programmatic)", "mmff_electronic"), 0.05),
          ("SOC device relaxed", rf"levels \(to [{_DASHES}\-]?[\d.]+ and {N} mV\), the doubly", lambda d: _ss_after(d, "chloro (device, programmatic)", "relaxed_electronic"), 0.05),
          ("SOC adiabatic MMFF", rf"the doubly relaxed form on both \(to {N} and", lambda d: _ss_after(d, "chloro, both states relaxed (adiabatic)", "mmff_electronic"), 0.05),
          ("SOC adiabatic relaxed", rf"\(to [{_DASHES}\-]?[\d.]+ and {N} mV\) and the one-water", lambda d: _ss_after(d, "chloro, both states relaxed (adiabatic)", "relaxed_electronic"), 0.05),
          ("SOC one water relaxed", rf"relaxed level \(to {N} mV\) — so five", lambda d: _ss_after(d, "chloro + 1 H₂O on Cl⁻", "relaxed_electronic"), 0.05),
          ("electronic flavin above measured (MMFF)", rf"flavin levels {N} and [\d.]+ mV above the measured", lambda d: 1000 * d["flavin"]["levels"]["mmff_electronic"]["donor_side_V"], 0.5),
          ("electronic flavin above measured (relaxed)", rf"flavin levels [\d.]+ and {N} mV above the measured", lambda d: 1000 * d["flavin"]["levels"]["relaxed_electronic"]["donor_side_V"], 0.5),
          ("SOC ZPE/RRHO floor", rf"keep\s+at least \+{N} mV", lambda d: 1000 * (min(r["by_donor_level"][k]["cascade_V"] for r in d["forms"] for k in ("relaxed_plus_zpe", "relaxed_rrho_free_energy")) + d["shared_shifts"]["terms"]["spin_orbit_os"]["shift_V"]), 0.05),
          ("SOC device vs measured flavin", rf"with the full\s+shift lies at \+{N} mV", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["against_measured_flavin"]["by_form_V"]["chloro (device, programmatic)"], 0.05),
          ("4.44 V shift", rf"lowers every E°\(Os\) and every cascade by {N} mV", lambda d: -1000 * d["shared_shifts"]["terms"]["she_abs_4_44"]["shift_V"], 0.5),
          ("SOC + 4.44 V cells uphill", rf"together with the full spin–orbit shift {N} of the 32", lambda d: d["shared_shifts"]["combined"]["spin_orbit_os + she_abs_4_44"]["n_uphill"], 0.0),
          ("functional, Os side", rf"lowers the device couple's E°\(Os\) by {N} mV \(Table 4;", lambda d: -1000 * d["shared_shifts"]["terms"]["functional_os_side"]["shift_V"], 0.5),
          ("functional only", rf"Table 4; {N} mV of it the functional", lambda d: -1000 * d["shared_shifts"]["terms"]["functional_os_side"]["functional_only_6_31gd_V"], 0.5),
          ("Os ZPE raises", rf"zero-point energy \(\+{N} mV where computed", lambda d: 1000 * (d["both_sided"]["levels"]["relaxed_plus_zpe"]["E_os_vs_SHE_V"] - d["both_sided"]["levels"]["relaxed_electronic"]["E_os_vs_SHE_V"]), 0.5),
          ("protein shift raises", rf"bound flavin \(\+{N} mV, §3\.6\)", lambda d: -1000 * d["measured"]["protein_shift_V"], 0.5),
          ("limits: SOC", rf"spin–orbit coupling on osmium \(≈ {N} mV at its octahedral value, not\s+computed", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["shift_V"], 0.5),
          ("limits: acceptor side before", rf"acceptor side from \+{N} to", lambda d: 1000 * d["forms"][0]["acceptor_side_V"], 0.5),
          ("limits: acceptor side after", rf"acceptor side from \+[\d.]+ to \+{N} mV", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["device_acceptor_side_after_V"], 0.5),
          ("limits: functional", rf"functional \({N} mV on the osmium side", lambda d: -1000 * d["shared_shifts"]["terms"]["functional_os_side"]["shift_V"], 0.5),
          ("limits: convention", rf"\({N} mV between 4\.281 and 4\.44 V\)", lambda d: -1000 * d["shared_shifts"]["terms"]["she_abs_4_44"]["shift_V"], 0.5),
      )],
    *[(f"paper §3.5 hexa-aqua {lab} → microsolvation.json", PAPER_RESULTS, pat, "dft/microsolvation.json", fn, tol)
      for lab, pat, fn, tol in (
          ("second-shell shift", rf"a second shell lowers E° by {N} V", lambda d: _hexa(d, "aquo_n18_twoshell") - _hexa(d, "aquo_n6_innershell"), 0.005),
          ("n6", rf"ΔE_red going from\s+{N} to", lambda d: _hexa(d, "aquo_n6_innershell"), 0.0005),
          ("n18", rf"ΔE_red going from\s+[{_DASHES}\-]?[\d.]+ to {N} eV", lambda d: _hexa(d, "aquo_n18_twoshell"), 0.0005),
      )],
    *[(f"{where} SOC cells uphill → cascade_like_for_like", doc_rel, pat, "dft/cascade_like_for_like.json", fn, 0.0)
      for where, doc_rel, pat, fn in (
          ("SUMMARY Conclusion", SUMMARY, rf"turns up to \*\*{N}\*\* of the 32 uphill",
           lambda d: d["shared_shifts"]["terms"]["spin_orbit_os"]["n_uphill"]),
          ("SUMMARY Conclusion + 4.44 V", SUMMARY, rf"with the spin–orbit shift \*\*{N}\*\*\)",
           lambda d: d["shared_shifts"]["combined"]["spin_orbit_os + she_abs_4_44"]["n_uphill"]),
          ("paper §4", "docs/protocols/ebfc/in_silico/paper/04_conclusion.md", rf"turns up to {N} of the 32 cells uphill at its octahedral",
           lambda d: d["shared_shifts"]["terms"]["spin_orbit_os"]["n_uphill"]),
          ("OUTLINE §3.5", "docs/protocols/ebfc/in_silico/paper/00_OUTLINE.md", rf"turns up to {N} of the 32 cells uphill at its octahedral value",
           lambda d: d["shared_shifts"]["terms"]["spin_orbit_os"]["n_uphill"]),
          ("PIPELINE row 95", "docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md", rf"turns up to {N} of 32 cells uphill",
           lambda d: d["shared_shifts"]["terms"]["spin_orbit_os"]["n_uphill"]),
      )],
    # ⊕ 2026-10-19 — `94`: the weakest link of the SOC submission measured as a threshold; the status row prints its
    # range, read here from the cache (the submission in 00_07 copies it, unpinned: 00_07 is outside this job's paths)
    *[(f"{where} SOC quenching threshold {k} → os_soc_quenching_model", doc_rel, pat, "dft/os_soc_quenching_model.json",
       (lambda kk, ii: lambda d: d["summary"][kk][ii])(k, i), 0.0)
      for where, doc_rel, pats in (
          ("PIPELINE row 94", "docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md",
           (rf"is ≥ {N}–[\d.]+ eV \(hole on a single orbital\)", rf"is ≥ [\d.]+–{N} eV \(hole on a single orbital\)",
            rf"or ≥ {N}–[\d.]+ eV \(on a degenerate pair", rf"or ≥ [\d.]+–{N} eV \(on a degenerate pair")),)
      for k, i, pat in zip(("one_up_threshold_eV", "one_up_threshold_eV", "two_up_threshold_eV", "two_up_threshold_eV"),
                           (0, 1, 0, 1), pats, strict=True)],
    ("SUMMARY Conclusion first flip → cascade_like_for_like", SUMMARY, rf"reverses a cell beyond \*\*\+{N}\*\* mV",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["first_flip_at_V"], 0.05),
    ("SUMMARY Conclusion device vs measured flavin → cascade_like_for_like", SUMMARY, rf"shifted device couple lies at \*\*\+{N}\*\* mV",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["against_measured_flavin"]["by_form_V"]["chloro (device, programmatic)"], 0.05),
    ("PIPELINE row 95 device vs measured flavin → cascade_like_for_like", "docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md", rf"device couple stays at \+{N} mV",
     "dft/cascade_like_for_like.json", lambda d: 1000 * d["shared_shifts"]["terms"]["spin_orbit_os"]["against_measured_flavin"]["by_form_V"]["chloro (device, programmatic)"], 0.05),
    ("SUMMARY Conclusion functional, Os side → cascade_like_for_like", SUMMARY, rf"device couple's Os side \({N} mV\)",
     "dft/cascade_like_for_like.json", lambda d: -1000 * d["shared_shifts"]["terms"]["functional_os_side"]["shift_V"], 0.5),
    # PIPELINE_STATUS row 96 — the three E°(Os) levels it prints
    *[(f"PIPELINE 96 E°(Os) {lvl} → os_couple_thermo", "docs/protocols/ebfc/in_silico/PIPELINE_STATUS.md", pat,
       "dft/os_couple_thermo.json", (lambda lv: lambda d: 1000 * d["E_os_vs_SHE_V"][lv])(lvl), 0.05)
      for lvl, pat in (("electronic", rf"E°\(Os\) \+{N} mV vs SHE electronic"), ("plus_zpe", rf"\+{N} with the ZPE \(\+40\.6\)"),
                       ("rrho_free_energy", rf"RRHO \(\+{N}\) not comparable"))],
    # ── Hammett LFER ──
    (
        "LFER slope → os_mediator_series.json",
        SUMMARY, rf"slope ≈ {N} eV/σ",
        "dft/os_mediator_series.json", lambda d: d["lfer"]["slope_eV_per_sigma"], 0.005,
    ),
    # ── ① ωB97X ⊥ B3LYP along σ (21e `wb97x`, vs_b3lyp block, 2026-10-08) — one pin per table row ──
    *[(
        f"ω−B3 {label} → os_mediator_series_wb97x.json vs_b3lyp",
        SUMMARY, rf"\| {re.escape(label)} \| [^|\n]* \| [^|\n]* \| [^|\n]* \| \*\*\+{N}\*\* \|",
        "dft/os_mediator_series_wb97x.json",
        lambda d, name=name: named(d["vs_b3lyp"]["points"], "name", name)["omega_minus_b3_eV"], 0.0001,
    ) for label, name in (("NMe₂", "nme2"), ("NH₂", "nh2"), ("Me (dmbpy)", "dmbpy"), ("H (bpy)", "bpy"),
                          ("NO₂", "no2"), ("SO₂CF₃", "so2cf3"))],
    # the acceptor pair and the ends split (2026-10-11: SO₂CF₃ landed; the small-basis ends accepted)
    *[(f"table {col} column {label} → vs_b3lyp", SUMMARY,
       rf"\| {re.escape(label)} \| [^|\n]* \| "   # the row that ends in the ω−B3 column (the series table above has none)
       + (rf"{N} \| [^|\n]* \|" if col == "B3LYP" else rf"[^|\n]* \| {N}[^|\n]*\|") + r" \*\*\+[\d.]+\*\* \|",
       "dft/os_mediator_series_wb97x.json",
       lambda d, name=name, key=key: named(d["vs_b3lyp"]["points"], "name", name)[key], 0.00005)
      for label, name in (("NMe₂", "nme2"), ("NH₂", "nh2"), ("Me (dmbpy)", "dmbpy"), ("H (bpy)", "bpy"),
                          ("NO₂", "no2"), ("SO₂CF₃", "so2cf3"))
      for col, key in (("B3LYP", "b3lyp_dE_red_eV"), ("ωB97X", "wb97x_dE_red_eV"))],
    ("Limit (3): SO₂CF₃ ΔE_red more negative than NO₂ at ωB97X (meV) → vs_b3lyp acceptor gap", SUMMARY,
     rf"at ωB97X SO₂CF₃'s ΔE_red is {N} meV more negative",
     "dft/os_mediator_series_wb97x.json", lambda d: -d["vs_b3lyp"]["acceptor_gap_so2cf3_minus_no2_eV"]["wb97x"] * 1000, 0.5),
    ("ends: functional ratio → vs_b3lyp ends_decomposition", SUMMARY, rf"the change is the functional's \(×{N}\)",
     "dft/os_mediator_series_wb97x.json",
     lambda d: (lambda t: t["wb97x_631gd"] / t["b3lyp_631gd"])(d["vs_b3lyp"]["ends_decomposition"]["slope_over_common_subset_by_tier"]),
     0.005),
    ("ends: basis ratio → vs_b3lyp ends_decomposition", SUMMARY, rf"\(×[\d.]+\), the basis ×{N} — at ωB97X",
     "dft/os_mediator_series_wb97x.json",
     lambda d: (lambda t: t["wb97x_def2tzvp"] / t["wb97x_631gd"])(d["vs_b3lyp"]["ends_decomposition"]["slope_over_common_subset_by_tier"]),
     0.005),
    ("SO₂CF₃ ΔE_red less negative than NO₂ at B3LYP (meV) → vs_b3lyp acceptor gap", SUMMARY, rf"SO₂CF₃'s ΔE_red is {N} meV less negative than NO₂'s at B3LYP",
     "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["acceptor_gap_so2cf3_minus_no2_eV"]["b3lyp"] * 1000, 0.05),
    ("SO₂CF₃ ΔE_red more negative than NO₂ at ωB97X (meV) → vs_b3lyp acceptor gap", SUMMARY, rf"out of σ order\) and {N} meV more negative at ωB97X",
     "dft/os_mediator_series_wb97x.json", lambda d: -d["vs_b3lyp"]["acceptor_gap_so2cf3_minus_no2_eV"]["wb97x"] * 1000, 0.05),
    *[(f"second-acceptor offset {name} → vs_b3lyp", SUMMARY, anchor, "dft/os_mediator_series_wb97x.json",
       lambda d, name=name: named(d["vs_b3lyp"]["points"], "name", name)["omega_minus_b3_eV"], 0.0005)
      for name, anchor in (("so2cf3", rf"carries a SMALLER offset \(\+{N} against"),
                           ("no2", rf"SMALLER offset \(\+[\d.]+ against \+{N} eV\)"))],
    *[(f"ends {part} at {name} → vs_b3lyp ends_decomposition", SUMMARY, anchor, "dft/os_mediator_series_wb97x.json",
       lambda d, part=part, name=name: named(d["vs_b3lyp"]["ends_decomposition"]["points"], "name", name)[part], 0.0005)
      for part, name, anchor in (("functional_eV", "nh2", rf"the functional moves ΔE_red by \+{N} \(NH₂\)"),
                                 ("functional_eV", "no2", rf"\(NH₂\) / \+{N} eV \(NO₂\) and the basis"),
                                 ("basis_eV", "nh2", rf"\(NO₂\) and the basis by {N} / "),
                                 ("basis_eV", "no2", rf"and the basis by [−\-][\d.]+ / {N} eV, so over"))],
    *[(f"ends slope {tier} → vs_b3lyp ends_decomposition", SUMMARY, anchor, "dft/os_mediator_series_wb97x.json",
       lambda d, tier=tier: d["vs_b3lyp"]["ends_decomposition"]["slope_over_common_subset_by_tier"][tier], 0.0005)
      for tier, anchor in (("b3lyp_631gd", rf"over Me · H · NO₂ the slope runs \*\*{N} \(B3LYP\)"),
                           ("wb97x_631gd", rf"→ {N} \(ωB97X at 6-31G\(d\)\) → [−\-][\d.]+ eV/σ \(def2-TZVP\)\*\*"),
                           ("wb97x_def2tzvp", rf"\(ωB97X at 6-31G\(d\)\) → {N} eV/σ \(def2-TZVP\)\*\*"))],
    (
        "ωB97X slope over the shared fit points → vs_b3lyp",
        SUMMARY, rf"the ωB97X slope is \*\*{N} against",
        "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["slope_wb97x_eV_per_sigma"], 0.001,
    ),
    (
        "B3LYP slope over the same points → vs_b3lyp",
        SUMMARY, rf"against {N} eV/σ at B3LYP \(×",
        "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["slope_b3lyp_eV_per_sigma"], 0.001,
    ),
    (
        "ωB97X/B3LYP slope ratio → vs_b3lyp",
        SUMMARY, rf"eV/σ at B3LYP \(×{N}\)\*\*",
        "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["slope_ratio_wb97x_over_b3lyp"], 0.01,
    ),
    # the centre split (34b's ωB97X/6-31G(d) chloro points) — local slope per tier, functional and basis per point
    *[(
        f"centre local slope {tier} → vs_b3lyp centre_decomposition",
        SUMMARY, anchor,
        "dft/os_mediator_series_wb97x.json",
        lambda d, tier=tier: d["vs_b3lyp"]["centre_decomposition"]["local_slope_eV_per_sigma"][tier], 0.001,
    ) for tier, anchor in (("b3lyp_631gd", rf"the local slope runs \*\*{N} \(B3LYP\) →"),
                           ("wb97x_631gd", rf"→ {N} \(ωB97X, 6-31G\(d\)\) →"),
                           ("wb97x_def2tzvp", rf"→ {N} eV/σ \(ωB97X, def2-TZVP\)"))],
    *[(
        f"centre {part} part at {name} → vs_b3lyp centre_decomposition",
        SUMMARY, anchor,
        "dft/os_mediator_series_wb97x.json",
        lambda d, part=part, name=name: named(d["vs_b3lyp"]["centre_decomposition"]["points"], "name", name)[part], 0.001,
    ) for part, name, anchor in (("functional_eV", "dmbpy", rf"the functional alone moves ΔE_red by \+{N} \(Me\)"),
                                 ("functional_eV", "bpy", rf"\(Me\) / \+{N} eV \(H\) and the basis"),
                                 ("basis_eV", "dmbpy", rf"the basis change by \+{N} / "),
                                 ("basis_eV", "bpy", rf"by \+[\d.]+ / {N} eV, so the local slope"))],
    # the paper's §3.3 sentence and the «≈15 %» every summary of it carries (abstract · intro · conclusion · cover letter)
    (
        "paper §3.3 ω−B3 donor end → vs_b3lyp",
        PAPER_RESULTS, rf"rises from \+{N} eV at the donor end",
        "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["points"][0]["omega_minus_b3_eV"], 0.006,
    ),
    (
        "paper §3.3 ω−B3 at NO₂ → vs_b3lyp",
        PAPER_RESULTS, rf"to \+{N} eV at NO₂, so over the",
        "dft/os_mediator_series_wb97x.json",
        lambda d: named(d["vs_b3lyp"]["points"], "name", "no2")["omega_minus_b3_eV"], 0.006,
    ),
    # the donor comparison with the one measured series (script 83, Goldschmid 2021) — per 4,4'-substituent against H, in mV
    *[(f"paper §3.3 donor comparison {what} → os_series_vs_measured.json", PAPER_RESULTS, anchor,
       "dft/os_series_vs_measured.json", get, tol)
      for what, anchor, get, tol in (
          ("OMe computed", rf"OMe agrees\s+\({N} mV computed at B3LYP",
           lambda d: d["computed"]["b3lyp_631gd"]["ome"]["shift_per_substituent_V"] * 1000, 0.05),
          ("OMe measured", rf"computed at B3LYP, {N} mV measured\)",
           lambda d: d["measured"]["ome"]["shift_per_substituent_V"] * 1000, 0.05),
          ("Me computed B3LYP", rf"Me does not \({N} mV at B3LYP",
           lambda d: d["computed"]["b3lyp_631gd"]["dmbpy"]["shift_per_substituent_V"] * 1000, 0.05),
          ("Me computed ωB97X", rf"at B3LYP and {N} mV at\s+ωB97X/def2-TZVP",
           lambda d: d["computed"]["wb97x_def2tzvp"]["dmbpy"]["shift_per_substituent_V"] * 1000, 0.05),
          ("Me measured", rf"against\s+{N} mV measured\)",
           lambda d: d["measured"]["dmbpy"]["shift_per_substituent_V"] * 1000, 0.05),
          ("measured r² over H, Me, OMe", rf"the measured do\s+not \(r² = {N}\)",
           lambda d: d["measured_readings"]["matched"]["r2"], 0.005),
          ("tBu measured", rf"tBu, is as weak\s+\({N} mV, with its σ_para unchecked",
           lambda d: d["measured"]["dtbbpy"]["shift_per_substituent_V"] * 1000, 0.05),
          *[(f"Me computed over measured (MeCN) at {tier}", rf"\(ref 8\) to {N} times \(acetonitrile",
             lambda d, tier=tier: d["ratio_computed_over_measured_per_substituent"][f"{tier}:dmbpy"], 0.05)
            for tier in ("b3lyp_631gd", "wb97x_def2tzvp")])],
    # the osmium-basis check (21e `b3lyp-osdef2`, via 83 `aqueous_series.os_basis_check`) — the paper and SUMMARY
    ("paper §3.3 Os-basis point shift low → osdef2", PAPER_RESULTS, rf"moves every\s+point by {N}–[\d.]+ meV",
     "dft/os_series_vs_measured.json", lambda d: d["aqueous_series"]["os_basis_check"]["point_shift_meV"][0], 0.5),
    ("paper §3.3 Os-basis point shift high → osdef2", PAPER_RESULTS, rf"point by [\d.]+–{N} meV and every pair",
     "dft/os_series_vs_measured.json", lambda d: d["aqueous_series"]["os_basis_check"]["point_shift_meV"][1], 0.5),
    ("paper §3.3 Os-basis max pair change → osdef2", PAPER_RESULTS, rf"every pair by at most {N} mV per substituent",
     "dft/os_series_vs_measured.json", lambda d: d["aqueous_series"]["os_basis_check"]["max_pair_change_mV"], 0.05),
    ("SUMMARY Os-basis point shift low → osdef2", SUMMARY, rf"moves every point by \+{N}…\+[\d.]+ meV and every pair",
     "dft/os_series_vs_measured.json", lambda d: d["aqueous_series"]["os_basis_check"]["point_shift_meV"][0], 0.5),
    ("SUMMARY Os-basis point shift high → osdef2", SUMMARY, rf"point by \+[\d.]+…\+{N} meV and every pair by",
     "dft/os_series_vs_measured.json", lambda d: d["aqueous_series"]["os_basis_check"]["point_shift_meV"][1], 0.5),
    ("SUMMARY Os-basis max pair change → osdef2", SUMMARY, rf"every pair by ≤ {N} mV per substituent\); the ligand basis",
     "dft/os_series_vs_measured.json", lambda d: d["aqueous_series"]["os_basis_check"]["max_pair_change_mV"], 0.05),
    # the continuum variants (21e `b3lyp-iefpcm` · `b3lyp-uffcavity` · `b3lyp-gas`, via 83 `aqueous_series.solvation_check`;
    # the UFF point shifts from that variant's own `vs_series`) — the paper and SUMMARY
    *[(f"{doc_name} continuum {what} → solvation_check", doc, anchor, "dft/os_series_vs_measured.json",
       lambda d, get=get: get(d["aqueous_series"]["solvation_check"]), tol)
      for doc_name, doc, what, anchor, get, tol in (
          ("paper §3.3", PAPER_RESULTS, "OMe−Me excess", rf"falls about {N} mV per substituent\s+short",
           lambda c: c["ome_dmbpy_excess_mV"], 0.5),
          ("paper §3.3", PAPER_RESULTS, "IEF move", rf"in place of C-PCM moves the pair by \+{N} mV",
           lambda c: c["iefpcm"]["ome_dmbpy_change_mV"], 0.05),
          ("paper §3.3", PAPER_RESULTS, "UFF move", rf"the source states none — by {N} mV",
           lambda c: c["uffcavity"]["ome_dmbpy_change_mV"], 0.05),
          ("paper §3.3", PAPER_RESULTS, "IEF max pair", rf"every pair by at most {N} and [\d.]+ mV\)",
           lambda c: c["iefpcm"]["max_pair_change_mV"], 0.05),
          ("paper §3.3", PAPER_RESULTS, "UFF max pair", rf"every pair by at most [\d.]+ and {N} mV\)",
           lambda c: c["uffcavity"]["max_pair_change_mV"], 0.05),
          ("paper §3.3", PAPER_RESULTS, "gas move", rf"Removing the continuum moves the pair by {N} mV",
           lambda c: c["gas"]["ome_dmbpy_change_mV"], 0.05),
          ("SUMMARY", SUMMARY, "OMe−Me excess", rf"computed excess over the measured is \+{N} mV per substituent",
           lambda c: c["ome_dmbpy_excess_mV"], 0.05),
          ("SUMMARY", SUMMARY, "IEF move", rf"IEF-PCM for C-PCM moves the pair\s+by \+{N} mV",
           lambda c: c["iefpcm"]["ome_dmbpy_change_mV"], 0.05),
          ("SUMMARY", SUMMARY, "UFF move", rf"sphere on every H by {N} mV",
           lambda c: c["uffcavity"]["ome_dmbpy_change_mV"], 0.05),
          ("SUMMARY", SUMMARY, "IEF max pair", rf"every pair by ≤ {N} / ≤ [\d.]+ mV;",
           lambda c: c["iefpcm"]["max_pair_change_mV"], 0.05),
          ("SUMMARY", SUMMARY, "UFF max pair", rf"every pair by ≤ [\d.]+ / ≤ {N} mV;",
           lambda c: c["uffcavity"]["max_pair_change_mV"], 0.05),
          ("SUMMARY", SUMMARY, "gas move", rf"a bound, not a candidate — moves it by {N} mV",
           lambda c: c["gas"]["ome_dmbpy_change_mV"], 0.05))],
    # where the OMe−Me gap sits (83 `pvi_series`: ours − measured per pair) and the ligand basis on Me−H (21e `wb97x`
    # `vs_b3lyp.centre_decomposition`: functional, then basis, per substituent) — adversary 2026-10-12
    *[(f"{doc_name} {what}", doc, anchor, cache, get, tol) for doc_name, doc, what, anchor, cache, get, tol in (
        ("paper §3.3", PAPER_RESULTS, "PVI OMe−H short", rf"OMe against H {N} mV per substituent short",
         "dft/os_series_vs_measured.json", lambda d: _pvi_gap(d, "ome", "bpy"), 0.05),
        ("paper §3.3", PAPER_RESULTS, "PVI Me−H over", rf"Me against H {N} mV over",
         "dft/os_series_vs_measured.json", lambda d: abs(_pvi_gap(d, "dmbpy", "bpy")), 0.05),
        ("paper §3.3", PAPER_RESULTS, "PVI OMe−H percent short", rf"falls\s+{N} % short in the other",
         "dft/os_series_vs_measured.json", lambda d: (1 - _pvi_ratio(d, "ome", "bpy")) * 100, 0.5),
        ("SUMMARY", SUMMARY, "PVI OMe−H short", rf"OMe−H {N} mV short and Me−H",
         "dft/os_series_vs_measured.json", lambda d: _pvi_gap(d, "ome", "bpy"), 0.05),
        ("SUMMARY", SUMMARY, "PVI Me−H over", rf"short and Me−H {N} mV over",
         "dft/os_series_vs_measured.json", lambda d: abs(_pvi_gap(d, "dmbpy", "bpy")), 0.05),
        ("paper §3.3", PAPER_RESULTS, "Me−H functional", rf"moves the shift by \+{N} mV per substituent",
         "dft/os_mediator_series_wb97x.json", lambda d: _centre_split(d)[0], 0.05),
        ("paper §3.3", PAPER_RESULTS, "Me−H basis", rf"def2-TZVP then by {N} mV",
         "dft/os_mediator_series_wb97x.json", lambda d: _centre_split(d)[1], 0.05),
        ("SUMMARY", SUMMARY, "Me−H functional", rf"def2-TZVP: \+{N}, then",
         "dft/os_mediator_series_wb97x.json", lambda d: _centre_split(d)[0], 0.05),
        ("SUMMARY", SUMMARY, "Me−H basis", rf"then {N} mV per substituent — our two tiers",
         "dft/os_mediator_series_wb97x.json", lambda d: _centre_split(d)[1], 0.05))],
    # the axial N-donor (21e `b3lyp-pyaxial`, via 83 `aqueous_series.axial_check`)
    *[(f"{doc_name} axial {what} → axial_check", doc, anchor, "dft/os_series_vs_measured.json",
       lambda d, k=k: d["aqueous_series"]["axial_check"][k], 0.05)
      for doc_name, doc, what, anchor, k in (
          ("paper §3.3", PAPER_RESULTS, "OMe−Me move", rf"1-methylimidazole moves the pair by \+{N} mV", "ome_dmbpy_change_mV"),
          ("paper §3.3", PAPER_RESULTS, "max pair", rf"\(every pair by at most {N} mV\)\. Relaxing the Os\(II\)", "max_pair_change_mV"),
          ("SUMMARY", SUMMARY, "OMe−Me move", rf"pyridine for 1-MeIm moves OMe−Me by \+{N} mV", "ome_dmbpy_change_mV"),
          ("SUMMARY", SUMMARY, "max pair", rf"and every pair by ≤ {N} mV per substituent\), so A1′", "max_pair_change_mV"))],
    # the Os(II) geometry (21e `b3lyp-relaxed-os2`, via 83 `aqueous_series.relaxation_check` and the variant's own vs_series)
    *[(f"{doc_name} relaxed OMe−Me move → relaxation_check", doc, anchor, "dft/os_series_vs_measured.json",
       lambda d: d["aqueous_series"]["relaxation_check"]["ome_dmbpy_change_mV"], 0.05)
      for doc_name, doc, anchor in (
          ("paper §3.3", PAPER_RESULTS, rf"\(Cl is read below\), closes this pair \({N} mV"),
          ("SUMMARY", SUMMARY, rf"relaxed with the acceptors, below\) — OMe−Me moves by {N} mV"))],
    *[(f"{doc_name} relaxed OMe−Me value → relaxed_os2", doc, anchor, "dft/os_mediator_series_relaxed_os2.json",
       lambda d: next(p["variant_mV"] for p in d["vs_series"]["pairs"] if (p["x"], p["ref"]) == ("ome", "dmbpy")), 0.05)
      for doc_name, doc, anchor in (
          ("paper §3.3", PAPER_RESULTS, rf"closes this pair \([^,]+, to {N} against"),
          ("SUMMARY", SUMMARY, rf"OMe−Me moves by [^,]+, to {N} against"))],
    *[(f"SUMMARY relaxed point shift {n} → relaxed_os2", SUMMARY, anchor, "dft/os_mediator_series_relaxed_os2.json",
       lambda d, n=n: d["vs_series"]["point_shift_eV"][n] * 1000, 0.5)
      for n, anchor in (("ome", rf"relaxed shifts are {N} \(OMe\)"), ("bpy", rf"\(OMe\), {N} \(H\)"), ("dmbpy", rf"\(H\) and {N} meV \(Me\)"))],
    # the same relaxation across every series sharing its points (83 `relaxed_geometry_check`) — ratios, shape, Os–donors
    *[(f"{doc_name} relaxed {what} → relaxed_geometry_check", doc, anchor, "dft/os_series_vs_measured.json", fn, tol)
      for doc_name, doc, what, anchor, fn, tol in (
          ("paper §3.3", PAPER_RESULTS, "aqueous OMe−Me", rf"substituent, {N} times; the source",
           lambda d: d["relaxed_geometry_check"]["aqueous_ome_dmbpy_ratio_ours_over_measured"]["relaxed"], 0.005),
          *[("paper §3.3", PAPER_RESULTS, f"ref 8 {lab} {t}", anchor,
             lambda d, k=k, t=t: d["relaxed_geometry_check"]["pvi_ratio_ours_over_measured"][k][t], 0.005)
            for lab, k, pre in (("OMe−H", "ome-bpy", r"\(OMe−H from"), ("Me−H", "dmbpy-bpy", r", Me−H\s+from"),
                                ("OMe−Me", "ome-dmbpy", r"\(OMe−Me from"))
            for t, anchor in (("series", rf"{pre} {N} to"), ("relaxed", rf"{pre} [\d.]+ to {N}[ ),;]"))],
          ("paper §3.3", PAPER_RESULTS, "donor r² series", rf"three computed donors from {N} to",
           lambda d: d["relaxed_geometry_check"]["donor_r2"]["series"], 0.00005),
          ("paper §3.3", PAPER_RESULTS, "donor r² relaxed", rf"three computed donors from [\d.]+ to {N}\)",
           lambda d: d["relaxed_geometry_check"]["donor_r2"]["relaxed"], 0.0005),
          ("paper §3.3", PAPER_RESULTS, "MeCN OMe before", rf"OMe against H\s+goes from\s+{N} to",
           lambda d: d["relaxed_geometry_check"]["mecn_ratio_ours_over_measured"]["ome"]["series"], 0.005),
          ("paper §3.3", PAPER_RESULTS, "MeCN OMe after", rf"OMe against H\s+goes from\s+[\d.]+ to {N} times",
           lambda d: d["relaxed_geometry_check"]["mecn_ratio_ours_over_measured"]["ome"]["relaxed"], 0.005),
          ("paper §3.3", PAPER_RESULTS, "Me−H pair change", rf"pairs change by {N} % \(Me−H\)",
           lambda d: d["relaxed_geometry_check"]["computed_pair_change"]["dmbpy-bpy"] * 100, 0.5),
          ("paper §3.3", PAPER_RESULTS, "OMe−Me pair change", rf"to \+{N} % \(OMe−Me\)",
           lambda d: d["relaxed_geometry_check"]["computed_pair_change"]["ome-dmbpy"] * 100, 0.5),
          *[("paper §3.3", PAPER_RESULTS, f"bite {geo} {end}", anchor,
             lambda d, geo=geo, f=f: f(b for v in d["relaxed_geometry_check"]["os_donors_A"].values()
                                       for b in v[geo]["bite_deg"]), 0.05)
            for geo, pre in (("relaxed", r"bite"), ("programmatic", r"against the programmatic"))
            for end, anchor, f in (("low", rf"{pre} {N}–", min), ("high", rf"{pre} [\d.]+–{N}°", max))],
          ("paper §3.3", PAPER_RESULTS, "pair move per complex", rf"up to\s+{N} meV a complex against",
           lambda d: max(abs(p["change_mV"]) for p in _donor_pairs(C("dft/os_mediator_series_relaxed_os2.json")["vs_series"])) * 4,
           0.5),
          ("paper §3.3", PAPER_RESULTS, "Os–N(bpy) low", rf"Os–N\(bpy\)\s+{N}–",
           lambda d: min(min(v["relaxed"]["N_bpy"]) for v in d["relaxed_geometry_check"]["os_donors_A"].values()), 0.005),
          ("paper §3.3", PAPER_RESULTS, "Os–N(bpy) high", rf"Os–N\(bpy\)\s+[\d.]+–{N} Å",
           lambda d: max(max(v["relaxed"]["N_bpy"]) for v in d["relaxed_geometry_check"]["os_donors_A"].values()), 0.005),
          ("paper §3.3", PAPER_RESULTS, "Os–N(L)", rf"Os–N\(L\) lengthens to {N} Å",
           lambda d: max(v["relaxed"]["N_L"] for v in d["relaxed_geometry_check"]["os_donors_A"].values()), 0.005),
          ("paper §3.3", PAPER_RESULTS, "Os–Cl low", rf"Os–Cl to {N}–",
           lambda d: min(v["relaxed"] for v in d["relaxed_geometry_check"]["os_cl_A"].values()), 0.005),
          ("paper §3.3", PAPER_RESULTS, "Os–Cl high", rf"Os–Cl to [\d.]+–{N} Å",
           lambda d: max(v["relaxed"] for v in d["relaxed_geometry_check"]["os_cl_A"].values()), 0.005),
          ("SUMMARY", SUMMARY, "aqueous OMe−Me", rf"×{N} against the source's optimised",
           lambda d: d["relaxed_geometry_check"]["aqueous_ome_dmbpy_ratio_ours_over_measured"]["relaxed"], 0.005),
          ("SUMMARY", SUMMARY, "ref 8 OMe−H after", rf"each, OMe−H ×[\d.]+ → ×{N}",
           lambda d: d["relaxed_geometry_check"]["pvi_ratio_ours_over_measured"]["ome-bpy"]["relaxed"], 0.005),
          ("SUMMARY", SUMMARY, "donor r² relaxed", rf"r² of the three donors [\d.]+ → {N}",
           lambda d: d["relaxed_geometry_check"]["donor_r2"]["relaxed"], 0.0005),
          ("SUMMARY", SUMMARY, "MeCN OMe after", rf"MeCN OMe−H moves away, ×[\d.]+ → ×{N}",
           lambda d: d["relaxed_geometry_check"]["mecn_ratio_ours_over_measured"]["ome"]["relaxed"], 0.005),
          ("SUMMARY", SUMMARY, "OMe−Me pair change", rf"\(Me−H\) to \+{N} % \(OMe−Me\), up to",
           lambda d: d["relaxed_geometry_check"]["computed_pair_change"]["ome-dmbpy"] * 100, 0.5),
          ("SUMMARY", SUMMARY, "donor slope", rf"donor slope rises by \+{N} %",
           lambda d: d["relaxed_geometry_check"]["donor_slope_change"] * 100, 0.5),
          ("SUMMARY", SUMMARY, "Koopmans offset move", rf"Koopmans offset \([+{_DASHES}\-]?[\d.]+ eV\) moves by \+{N} eV",
           lambda d: (next(c["os3"]["LUMO_eV"] for c in C("dft/os_mediator_series.json")["complexes"] if c["name"] == "dmbpy")
                      - C("dft/os_mediator_series_relaxed_os2.json")["complexes"]["dmbpy"]["os3"]["LUMO_eV"]), 0.0005))],
    *[(f"«up to 20.1 mV» donor pairs with both Os states relaxed in {where} → 83 adiabatic",
       f"docs/protocols/ebfc/in_silico/paper/{where}", anchor, "dft/os_series_vs_measured.json",
       lambda d: max(abs(v) for v in d["relaxed_geometry_check"]["adiabatic"]["pair_move_from_series_mV"].values()), 0.05)
      for where, anchor in (("05_abstract.md", rf"donor pairs move by up to {N} mV per substituent"),
                            ("07_cover_letter.md", rf"donor pairs move by up to {N} mV per substituent"),
                            ("04_conclusion.md", rf"its donor pairs by up to {N} mV per substituent, so"),
                            ("01_introduction.md", rf"its donor pairs by up to {N} mV per substituent between"))],
    ("paper §2.3 pair move per complex → relaxed_os2", "docs/protocols/ebfc/in_silico/paper/02_methods.md",
     rf"pairs by up to {N} meV a complex", "dft/os_mediator_series_relaxed_os2.json",
     lambda d: max(abs(p["change_mV"]) for p in _donor_pairs(d["vs_series"])) * 4, 0.5),
    *[(f"paper §2.3 relaxed points {end} → relaxed_os2", "docs/protocols/ebfc/in_silico/paper/02_methods.md", anchor,
       "dft/os_mediator_series_relaxed_os2.json", fn, 0.5)
      for end, anchor, fn in (
          ("low", rf"moves the points by {N}–", lambda d: -max(_donor_points(d["vs_series"])) * 1000),
          ("high", rf"moves the points by [\d.]+–{N} meV", lambda d: -min(_donor_points(d["vs_series"])) * 1000))],
    ("SUMMARY UFF point shift low → uffcavity", SUMMARY, rf"every absolute point, by {N}…",
     "dft/os_mediator_series_uffcavity.json", lambda d: max(d["vs_series"]["point_shift_eV"].values()) * 1000, 0.5),
    ("SUMMARY UFF point shift high → uffcavity", SUMMARY, rf"every absolute point, by [^…]+…{N} meV",
     "dft/os_mediator_series_uffcavity.json", lambda d: min(d["vs_series"]["point_shift_eV"].values()) * 1000, 0.5),
    # paper ref 8's own series (script 83 `pvi_series`, Zafar 2012 Table 1) — our core and N-donor; pairs[i] in PVI_PAIRS order:
    # OMe−H, Me−H, Cl−H, OMe−Me, Cl−Me, Cl−OMe; pairwise slopes in σ order ome-dmbpy, dmbpy-bpy, bpy-cl
    *[(f"paper §3.3 ref-8 series {what} → os_series_vs_measured.json", PAPER_RESULTS, anchor,
       "dft/os_series_vs_measured.json", get, tol)
      for what, anchor, get, tol in (
          ("OMe−H ratio", rf"our shifts are {N} times the measured for OMe against H",
           lambda d: d["pvi_series"]["pairs"][0]["ours_over_measured"], 0.005),
          ("OMe−H ours", rf"OMe against H \({N} against", lambda d: d["pvi_series"]["pairs"][0]["ours_mV"], 0.05),
          ("OMe−H measured", rf"OMe against H \([−\-][\d.]+ against {N} mV\), [\d.]+",
           lambda d: d["pvi_series"]["pairs"][0]["measured_mV"], 0.05),
          ("Me−H ratio", rf"{N}\s+times for Me \(", lambda d: d["pvi_series"]["pairs"][1]["ours_over_measured"], 0.005),
          ("Me−H ours", rf"times for Me \({N} against", lambda d: d["pvi_series"]["pairs"][1]["ours_mV"], 0.05),
          ("Me−H measured", rf"times for Me \([−\-][\d.]+ against {N} mV\)",
           lambda d: d["pvi_series"]["pairs"][1]["measured_mV"], 0.051),   # −27.75: an exact .x5 tie
          ("Cl−H ratio", rf"and {N} times for Cl \(", lambda d: d["pvi_series"]["pairs"][2]["ours_over_measured"], 0.005),
          ("Cl−H ours", rf"times for Cl \(\+{N} against", lambda d: d["pvi_series"]["pairs"][2]["ours_mV"], 0.05),
          ("Cl−H measured", rf"times for Cl \(\+[\d.]+ against \+{N} mV\)",
           lambda d: d["pvi_series"]["pairs"][2]["measured_mV"], 0.051),   # +17.25: an exact .x5 tie
          *[(f"measured slope {k}", anchor, lambda d, k=k: d["pvi_series"]["pairwise_slope_per_substituent_V_per_sigma"][k]["measured"], 0.00051)
            for k, anchor in (("ome-dmbpy", rf"side \({N}, [\d.]+ and [\d.]+ V per σ unit"),   # 0.4225: tie, tol below
                              ("dmbpy-bpy", rf"side \([\d.]+, {N} and [\d.]+ V per σ unit"),
                              ("bpy-cl", rf"side \([\d.]+, [\d.]+ and {N} V per σ unit"))],
          *[(f"our slope {k}", anchor, lambda d, k=k: d["pvi_series"]["pairwise_slope_per_substituent_V_per_sigma"][k]["ours"], 0.0005)
            for k, anchor in (("ome-dmbpy", rf"ours falls much less \({N}, [\d.]+ and [\d.]+\)"),
                              ("dmbpy-bpy", rf"ours falls much less \([\d.]+, {N} and [\d.]+\)"),
                              ("bpy-cl", rf"ours falls much less \([\d.]+, [\d.]+ and {N}\)"))],
          ("loading control", rf"another polymer loading\s+sits {N} mV away",
           lambda d: d["pvi_series"]["loading_control"]["shift_mV"], 0.5),
          ("Me−H ratio (closing)", rf"the measured Me shift is {N} \(ref 8\) to",
           lambda d: d["pvi_series"]["pairs"][1]["ours_over_measured"], 0.05),
          ("smallest Cl pair (closing)", rf"exceed the\s+measured ones {N} to [\d.]+ times across",
           lambda d: min(p["ours_over_measured"] for blk in ("pvi_series", "aqueous_series")
                         for p in d[blk]["pairs"] if "cl" in (p["x"], p["ref"])), 0.05),
          ("largest Cl pair (closing)", rf"measured ones [\d.]+ to {N} times across",
           lambda d: max(p["ours_over_measured"] for blk in ("pvi_series", "aqueous_series")
                         for p in d[blk]["pairs"] if "cl" in (p["x"], p["ref"])), 0.05),
          ("aqueous measured slope OMe→Me", rf"as ref 8's do \({N} and [\d.]+ V per σ unit",
           lambda d: d["aqueous_series"]["measured_pairwise_slope_per_substituent_V_per_sigma"]["ome-dmbpy"], 0.00051),   # 0.3975: an exact .x5 tie
          ("aqueous measured slope Me→Cl", rf"as ref 8's do \([\d.]+ and {N} V per σ unit",
           lambda d: d["aqueous_series"]["measured_pairwise_slope_per_substituent_V_per_sigma"]["dmbpy-cl"], 0.0005))],
    *[(f"SUMMARY ref-8 series {what} → os_series_vs_measured.json", SUMMARY, anchor,
       "dft/os_series_vs_measured.json", get, tol)
      for what, anchor, get, tol in (
          ("Cl−H (🔑)", rf"own series the computed sensitivity is ×{N} the measured",
           lambda d: d["pvi_series"]["pairs"][2]["ours_over_measured"], 0.005),
          ("OMe−H (limit 2)", rf"per substituent OMe−H ×{N}, Me−H", lambda d: d["pvi_series"]["pairs"][0]["ours_over_measured"], 0.005),
          ("Me−H (limit 2)", rf"OMe−H ×[\d.]+, Me−H ×{N}, Cl−H", lambda d: d["pvi_series"]["pairs"][1]["ours_over_measured"], 0.005),
          ("Cl−H (limit 2)", rf"Me−H ×[\d.]+, Cl−H ×{N}; the measured", lambda d: d["pvi_series"]["pairs"][2]["ours_over_measured"], 0.005),
          *[(f"SUMMARY ref-8 slope {k} {side}", rf"{anchor}", lambda d, k=k, side=side: d["pvi_series"]["pairwise_slope_per_substituent_V_per_sigma"][k][side], tol)
            for k, side, anchor, tol in (("ome-dmbpy", "measured", rf"donor to acceptor \(pairwise {N} → [\d.]+ → [\d.]+ V/σ", 0.005),
                                         ("dmbpy-bpy", "measured", rf"donor to acceptor \(pairwise [\d.]+ → {N} → [\d.]+ V/σ", 0.005),
                                         ("bpy-cl", "measured", rf"donor to acceptor \(pairwise [\d.]+ → [\d.]+ → {N} V/σ", 0.0005),
                                         ("ome-dmbpy", "ours", rf"ours much less \({N} → [\d.]+ → [\d.]+\)", 0.005),
                                         ("dmbpy-bpy", "ours", rf"ours much less \([\d.]+ → {N} → [\d.]+\)", 0.005),
                                         ("bpy-cl", "ours", rf"ours much less \([\d.]+ → [\d.]+ → {N}\)", 0.005))],
          ("loading control (limit 2)", rf"another loading sits \+{N} mV away",
           lambda d: d["pvi_series"]["loading_control"]["shift_mV"], 0.5))],
    # the aqueous series of our own core (script 83 `aqueous_series`, Montón-Vicente 2026) — per-substituent pairs, read three
    # ways (measured · ours · the source's relaxed B3LYP); pairs[i] in the order of 83's AQ_PAIRS: OMe−Me, Cl−Me, Cl−OMe
    *[(f"paper §3.3 aqueous {what} → os_series_vs_measured.json", PAPER_RESULTS, anchor,
       "dft/os_series_vs_measured.json", lambda d, i=i, key=key: d["aqueous_series"]["pairs"][i][key], tol)
      for what, anchor, i, key, tol in (
          ("OMe−Me ratio", rf"our computed shifts are {N} times the measured", 0, "ours_over_measured", 0.005),
          ("OMe−Me ours", rf"for OMe against Me \({N} against", 0, "ours_mV", 0.05),
          ("OMe−Me measured", rf"OMe against Me \([−\-][\d.]+ against {N} mV\)", 0, "measured_mV", 0.051),   # an exact .x5 tie
          ("Cl−Me ratio", rf"{N} times for Cl against Me", 1, "ours_over_measured", 0.05),
          ("Cl−Me ours", rf"Cl against Me \(\+{N} against", 1, "ours_mV", 0.05),
          ("Cl−Me measured", rf"Cl against Me \(\+[\d.]+ against \+{N} mV\)", 1, "measured_mV", 0.051),   # an exact .x5 tie
          ("Cl−OMe ratio", rf"{N} times for\s+Cl against OMe", 2, "ours_over_measured", 0.005),
          ("Cl−OMe ours", rf"Cl against OMe \(\+{N} against", 2, "ours_mV", 0.05),
          ("Cl−OMe measured", rf"Cl against OMe \(\+[\d.]+ against \+{N} mV\)", 2, "measured_mV", 0.05),
          ("source DFT OMe−Me", rf"gives {N},\s+[\d.]+\s+and\s+[\d.]+\s+for the same pairs", 0, "source_dft_over_measured", 0.005),
          ("source DFT Cl−Me", rf"gives [\d.]+,\s+{N}\s+and\s+[\d.]+\s+for the same pairs", 1, "source_dft_over_measured", 0.005),
          ("source DFT Cl−OMe", rf"gives [\d.]+,\s+[\d.]+\s+and\s+{N}\s+for the same pairs", 2, "source_dft_over_measured", 0.005))],
    *[(f"SUMMARY aqueous {what} → os_series_vs_measured.json", SUMMARY, anchor,
       "dft/os_series_vs_measured.json", lambda d, i=i, key=key: d["aqueous_series"]["pairs"][i][key], 0.005)
      for what, anchor, i, key in (
          ("Cl−OMe ours (🔑)", rf"Cl against OMe in a second aqueous series is ×{N} \(the", 2, "ours_over_measured"),
          ("Cl−OMe source DFT (🔑)", rf"\(the source's relaxed B3LYP ×{N}\);", 2, "source_dft_over_measured"),
          ("OMe−Me ours (limit 2)", rf"per substituent, OMe−Me ×{N}, Cl−Me", 0, "ours_over_measured"),
          ("Cl−Me ours (limit 2)", rf"OMe−Me ×[\d.]+, Cl−Me ×{N}, Cl−OMe", 1, "ours_over_measured"),
          ("Cl−OMe ours (limit 2)", rf"Cl−Me ×[\d.]+, Cl−OMe ×{N} — the two pairs", 2, "ours_over_measured"),
          ("OMe−Me source DFT (limit 2)", rf"\(both states optimised, ΔG\) gives ×{N}, ×", 0, "source_dft_over_measured"),
          ("Cl−Me source DFT (limit 2)", rf"ΔG\) gives ×[\d.]+, ×{N}, ×", 1, "source_dft_over_measured"),
          ("Cl−OMe source DFT (limit 2)", rf"ΔG\) gives ×[\d.]+, ×[\d.]+, ×{N}, and its functional is ours", 2, "source_dft_over_measured"))],
    ("paper §3.3 second-acceptor difference → vs_b3lyp", PAPER_RESULTS, rf"carries a smaller difference \(\+{N} eV\)",
     "dft/os_mediator_series_wb97x.json", lambda d: named(d["vs_b3lyp"]["points"], "name", "so2cf3")["omega_minus_b3_eV"], 0.005),
    ("paper §3.3 acceptor swap at B3LYP (meV) → vs_b3lyp", PAPER_RESULTS, rf"the ΔE_red of SO₂CF₃ is {N} meV less negative than that of NO₂",
     "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["acceptor_gap_so2cf3_minus_no2_eV"]["b3lyp"] * 1000, 0.5),
    ("paper §3.3 acceptor swap at ωB97X (meV) → vs_b3lyp", PAPER_RESULTS, rf"at ωB97X it is {N} meV more negative\)",
     "dft/os_mediator_series_wb97x.json", lambda d: -d["vs_b3lyp"]["acceptor_gap_so2cf3_minus_no2_eV"]["wb97x"] * 1000, 0.5),
    *[(f"paper §3.3 ends slope {tier} → vs_b3lyp ends_decomposition", PAPER_RESULTS, anchor,
       "dft/os_mediator_series_wb97x.json",
       lambda d, tier=tier: d["vs_b3lyp"]["ends_decomposition"]["slope_over_common_subset_by_tier"][tier], 0.006)
      for tier, anchor in (("b3lyp_631gd", rf"the slope runs {N} \(B3LYP\) → [−\-][\d.]+ \(ωB97X at 6-31G"),
                           ("wb97x_def2tzvp", rf"\(ωB97X at 6-31G\(d\)\) → {N}\s+eV per σ unit \(def2-TZVP\)"))],
    ("paper §3.3 ends slope at 6-31G(d) → vs_b3lyp ends_decomposition", PAPER_RESULTS, rf"→ {N} \(ωB97X at 6-31G\(d\)\) →",
     "dft/os_mediator_series_wb97x.json",
     lambda d: d["vs_b3lyp"]["ends_decomposition"]["slope_over_common_subset_by_tier"]["wb97x_631gd"], 0.006),
    ("paper §2.2 Os(III) acceptance threshold → vs_b3lyp os3_s2_max_accepted",
     "docs/protocols/ebfc/in_silico/paper/02_methods.md", rf"accepted on its ⟨S²⟩ \(≤ {N}; a pure doublet",
     "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["os3_s2_max_accepted"], 0.0),
    (
        "paper §3.3 ωB97X slope → vs_b3lyp",
        PAPER_RESULTS, rf"\(Me, H, NO₂\) the slope is {N} against",
        "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["slope_wb97x_eV_per_sigma"], 0.006,
    ),
    (
        "paper §3.3 B3LYP slope, same points → vs_b3lyp",
        PAPER_RESULTS, rf"the slope is [^ ]+ against {N} eV per σ unit",
        "dft/os_mediator_series_wb97x.json", lambda d: d["vs_b3lyp"]["slope_b3lyp_eV_per_sigma"], 0.006,
    ),
    (
        "paper §3.3 functional-alone flattening at the centre → vs_b3lyp centre_decomposition",
        PAPER_RESULTS, rf"functional alone flattens the local slope by ≈{N} %",
        "dft/os_mediator_series_wb97x.json",
        lambda d: (1 - d["vs_b3lyp"]["centre_decomposition"]["local_slope_eV_per_sigma"]["wb97x_631gd"]
                   / d["vs_b3lyp"]["centre_decomposition"]["local_slope_eV_per_sigma"]["b3lyp_631gd"]) * 100, 0.6,
    ),
    *[(
        f"«≈15 %» shallower slope in {where} → vs_b3lyp",
        f"docs/protocols/ebfc/in_silico/paper/{where}", anchor,
        "dft/os_mediator_series_wb97x.json",
        lambda d: (1 - d["vs_b3lyp"]["slope_ratio_wb97x_over_b3lyp"]) * 100, 0.6,
    ) for where, anchor in (("05_abstract.md", rf"≈{N} % shallower at ωB97X/def2-TZVP"),
                            ("07_cover_letter.md", rf"≈{N} % shallower at ωB97X/def2-TZVP"),
                            ("01_introduction.md", rf"its slope moves by ≈{N} % between"),
                            ("04_conclusion.md", rf"makes its slope ≈{N} % shallower"))],
    # ── Micro-solvation ② (2nd-shell = plain file, ligand-independent benchmark) ──
    (
        "2nd-shell PCM shift → microsolvation.json n18−n6",
        SUMMARY, r"2nd-shell shift = \*\*\+([\d.]+) eV",
        "dft/microsolvation.json",
        lambda d: (named(d["results"], "name", "aquo_n18_twoshell")["dE_red_eV"]
                   - named(d["results"], "name", "aquo_n6_innershell")["dE_red_eV"]), 0.001,
    ),
    (
        "bis-Im cascade Δ → microsolvation_dmbpy.json",
        SUMMARY, rf"bis-Im\*\* cis.*cascade Δ \*\*{N}",
        "dft/microsolvation_dmbpy.json",
        lambda d: named(d["results"], "name", "bisim_meim2")["cascade_delta_eV"], 0.001,
    ),
    # ── Tunneling ──
    (
        "β·d ensemble → tunneling_ensemble.json",
        SUMMARY, r"ln Σw = \*\*([\d.]+) ± 0\.13",
        "dft/tunneling_ensemble.json", lambda d: d["beta_d_mean"], 0.005,
    ),
    # ── Cathode DET (all three ZIF hops) ──
    (
        "Cu-Co t_ij (crude) → zif_hopping.json pairs[0]",
        SUMMARY, r"Cu↔Co \(T1↔ZIF node\) \| ([\d.]+) crude",
        "dft/zif_hopping.json", lambda d: d["pairs"][0]["t_ij_eV"], 2e-5,
    ),
    (
        "Co-Ce t_ij → zif_hopping.json pairs[1]",
        SUMMARY, r"Co↔Ce \(ZIF node↔vacancy\) \| ([\d.]+) \|",
        "dft/zif_hopping.json", lambda d: d["pairs"][1]["t_ij_eV"], 2e-5,
    ),
    (
        "Ce-graphene t_ij → zif_hopping.json pairs[2]",
        SUMMARY, r"Ce↔graphene \(vacancy↔MWCNT\) \| ([\d.]+) \|",
        "dft/zif_hopping.json", lambda d: d["pairs"][2]["t_ij_eV"], 1e-4,
    ),
    (
        "Cu-Co t_ij (FO-DFT) → fodft_coupling.json",
        SUMMARY, r"t_ij\(Cu-Co\) = \*\*([\d.]+) eV",
        "dft/fodft_coupling.json", lambda d: d["t_ij_eV"], 2e-5,
    ),
    # ── Bridge geometry: the premise under the FIXED ZIF_NODE_DIST, and the acceptance
    #    threshold any COUPLING lever has to beat. Both are what CHEM.35 turned on.
    (
        "bridge N···N span, methylimidazolate → zif_bridge_geometry.json",
        SUMMARY, r"2-methylimidazolate ⊥ benzimidazolate \| \*\*([\d.]+) ⊥ [\d.]+ Å",
        "dft/zif_bridge_geometry.json", lambda d: d["bridge_span_nn_A"]["meim"], 5e-4,
    ),
    (
        "bridge N···N span, benzimidazolate → zif_bridge_geometry.json",
        SUMMARY, r"2-methylimidazolate ⊥ benzimidazolate \| \*\*[\d.]+ ⊥ ([\d.]+) Å",
        "dft/zif_bridge_geometry.json", lambda d: d["bridge_span_nn_A"]["bzim"], 5e-4,
    ),
    (
        # The ×24 geometry sensitivity. Pinned because it is now a DECLARED ceiling on ③:
        # the doc may not drift from the probe that measured it.
        "off-plane bridge t_ij (the ×24 probe) → fodft_coupling_offplane.json",
        SUMMARY, r"moves the FO-DFT coupling \*\*[\d.]+ → ([\d.]+) eV",
        "dft/fodft_coupling_offplane.json", lambda d: d["t_ij_eV"], 1e-4,
    ),
    (
        # The margin the REFUSED geometry reads — the number that says the criterion is
        # load-bearing (it crosses turnover), not that ③ carries a band that wide.
        "off-plane margin (crosses turnover) → cathode_ket_lambda.json",
        SUMMARY, r"margin goes \*\*×[\d.]+ → ×([\d]+) — a factor",
        "dft/cathode_ket_lambda.json",
        lambda d: d["geometry_sensitivity_refused_offplane"]["margin_adverse"], 1.0,
    ),
    (
        "coupling gain to reach turnover (FO-DFT scale, assumed λ(Co)) → cathode_ket_lambda.json",
        SUMMARY, r"needs \*\*×([\d.]+)\*\* on the diabatised t_ij at the ASSUMED",
        "dft/cathode_ket_lambda.json",
        lambda d: d["coupling_gain_to_reach_turnover"]["at_literature_lambda_fodft_t"], 0.05,
    ),
    (
        "coupling gain at the COMPUTED λ(Co) → cathode_ket_lambda.json (the threshold is conditional too)",
        SUMMARY, r"and \*\*×([\d.]+)\*\* at the computed 3.09 eV",
        "dft/cathode_ket_lambda.json",
        lambda d: d["coupling_gain_to_reach_turnover"]["by_lambda_co"]["computed"]["gain_fodft_t"], 1.0,
    ),
    # ── L4 kinetics + EIS ──
    (
        "Rct (anode charge-transfer) → eis_model.json",
        SUMMARY, r"Rct \(charge transfer\) \| ([\d.]+) Ω",
        "kinetics/eis_model.json", lambda d: d["parameters"]["Rct_ohm"], 1.0,
    ),
    (
        "delta_t healthy-summer → delta_t_lookup.json",
        SUMMARY, r"Healthy summer \| 10 mM \| 25°C \| \*\*([\d.]+)\*\*",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["reference_points"], "scenario", "healthy summer")["delta_t_s"], 0.1,
    ),
    # pH bracket (⚖️ 2026-09-18): the ceiling rows above are the MODEL; these two pin the bracket
    # published beside them, so that a re-run which moves the ceiling cannot leave the sap-side
    # numbers standing. Both ends are pinned — a bracket with one end pinned is not a bracket.
    (
        "pH-bracket healthy-summer LOW end → delta_t_lookup.json §ph_bracket",
        SUMMARY, r"\| Healthy summer \| 135\.2 \| [\d.]+ \| [\d.]+ \| \*\*([\d.]+)–[\d.]+\*\* \|",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["ph_bracket"]["rows"], "scenario", "healthy summer")["delta_t_ph55_low_s"], 0.1,
    ),
    (
        "pH-bracket healthy-summer HIGH end → delta_t_lookup.json §ph_bracket",
        SUMMARY, r"\| Healthy summer \| 135\.2 \| [\d.]+ \| [\d.]+ \| \*\*[\d.]+–([\d.]+)\*\* \|",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["ph_bracket"]["rows"], "scenario", "healthy summer")["delta_t_ph55_high_s"], 0.1,
    ),
    (
        "delta_t cold-winter → delta_t_lookup.json (§delta_t Predictions table)",
        SUMMARY, r"Cold winter \| 5 mM \| 5°C \| \*\*([\d.]+)\*\*",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["reference_points"], "scenario", "cold winter / stress")["delta_t_s"], 0.1,
    ),
    # The two rows above anchor on the §delta_t Predictions TABLE. The Executive Summary
    # restates the same pair in prose, and a table-anchored pattern cannot see it — which is
    # exactly how the η_BQ 0.85→0.68 recompute (HW.47) left "36s / 190s" standing there under
    # a green guard whose own label claimed the Executive Summary was covered. Pin the prose.
    (
        "delta_t healthy-summer → delta_t_lookup.json (Executive Summary prose, NOT the table)",
        SUMMARY, r"healthy ([\d.]+) s / stressed",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["reference_points"], "scenario", "healthy summer")["delta_t_s"], 0.1,
    ),
    (
        "delta_t cold-winter → delta_t_lookup.json (Executive Summary prose, NOT the table)",
        SUMMARY, r"/ stressed ([\d.]+) s even",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["reference_points"], "scenario", "cold winter / stress")["delta_t_s"], 0.1,
    ),
    # ── DRIFT #2 catcher: the WHOLE xylem-sap pH column (RMSD matched, pH had drifted) ──
    (
        "xylem pH Pinus-summer → xylem_sap_sweep.json",
        SUMMARY, r"Pinus sylvestris \(summer\) \| ([\d.]+) \|",
        "kinetics/xylem_sap_sweep.json",
        lambda d: named(xylem_rows(d), "species", "pinus_sylvestris")["ph"], 0.05,
    ),
    (
        "xylem pH Pinus-winter → xylem_sap_sweep.json",
        SUMMARY, r"Pinus sylvestris \(winter\) \| ([\d.]+) \|",
        "kinetics/xylem_sap_sweep.json",
        lambda d: named(xylem_rows(d), "species", "pinus_sylvestris_winter")["ph"], 0.05,
    ),
    (
        "xylem pH Picea-spruce → xylem_sap_sweep.json",
        SUMMARY, r"Picea abies \(spruce\) \| ([\d.]+) \|",
        "kinetics/xylem_sap_sweep.json",
        lambda d: named(xylem_rows(d), "species", "picea_abies")["ph"], 0.05,
    ),
    (
        "xylem pH Quercus-oak → xylem_sap_sweep.json",
        SUMMARY, r"Quercus robur \(oak\) \| ([\d.]+) \|",
        "kinetics/xylem_sap_sweep.json",
        lambda d: named(xylem_rows(d), "species", "quercus_robur")["ph"], 0.05,
    ),
    (
        "xylem pH Fagus-beech → xylem_sap_sweep.json",
        SUMMARY, r"Fagus sylvatica \(beech\) \| ([\d.]+) \|",
        "kinetics/xylem_sap_sweep.json",
        lambda d: named(xylem_rows(d), "species", "fagus_sylvatica")["ph"], 0.05,
    ),
    (
        "xylem pH Generic → xylem_sap_sweep.json",
        SUMMARY, r"Generic simplified \| ([\d.]+) \|",
        "kinetics/xylem_sap_sweep.json",
        lambda d: named(xylem_rows(d), "species", "generic_simplified")["ph"], 0.05,
    ),
    # ── Thermal penetration (01_04 §3.5 thermal-install management) — NON-SUMMARY doc-target ──
    # Orphan-cache guard: thermal_penetration.json was committed data-only (no generator) and
    # was outside every existing guard's doc-set → §3.5's 22.7 min / α could silently drift.
    (
        "thermal tip→150°C time → thermal_penetration.json (01_04 §3.5)",
        CODIT, r"150°C \(коагуляція смоли\) через ([\d.]+) хвилин",
        "kinetics/thermal_penetration.json", lambda d: d["time_to_target_min"], 0.1,
    ),
    (
        "thermal diffusivity Ti-6Al-4V → thermal_penetration.json (01_04 §3.5)",
        CODIT, r"α=([\d.]+)×10⁻⁶ m²/s",
        "kinetics/thermal_penetration.json", lambda d: d["thermal_diffusivity_m2s"] * 1e6, 0.01,
    ),
    # ── Thermal-install radial field (01_04 §3.5 ban + SUMMARY §HW.6 evidence) ──
    # These three carry a SAFETY verdict about a living tree, so they are pinned to their owner
    # cache rather than left as prose: the cambium temperature, the thermal wound it opens, and
    # the stem class that wound would demand under the same 4 % CODIT rule.
    # ⚖️ The procedure was RETIRED 2026-09-09. Canon keeps the ban plus the two numbers that
    # carry it (a ban without a number is empty); the measurement detail lives in SUMMARY, which
    # 00_06 §3 already declares this guard's home — until now every thermal pin targeted 01_04.
    (
        "killed living tissue, retired procedure → thermal_install_field.json (01_04 §3.5)",
        CODIT, r"убито живої тканини Ø([\d.]+) мм\*\*",
        "mechanical/thermal_install_field.json",
        lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["killed_living_dia_anywhere_mm"], 0.1,
    ),
    (
        "minimum DBH the retired procedure would demand → thermal_install_field.json (01_04 §3.5)",
        CODIT, r"вимагало б \*\*DBH ≥ ([\d.]+) см\*\*",
        "mechanical/thermal_install_field.json",
        lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["min_dbh_for_thermal_wound_cm"], 1.0,
    ),
    (
        "cambium peak → thermal_install_field.json (SUMMARY §HW.6)",
        SUMMARY, r"uniform induction of all Ti to 200 °C \| \*\*([\d.]+) °C\*\*",
        "mechanical/thermal_install_field.json",
        lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["cambium_peak_C"], 0.1,
    ),
    (
        "cambial ring → thermal_install_field.json (SUMMARY §HW.6)",
        SUMMARY, r"cambial ring\n\*\*Ø([\d.]+) mm\*\*",
        "mechanical/thermal_install_field.json",
        lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["thermal_wound_dia_50C_mm"], 0.1,
    ),
    # 🔴 The CONSTRUCTIVE half is what a future reader is most likely to lose — it is the reason
    # a successor is gated rather than forbidden. Pin it too.
    (
        "10 s pulse cambium peak → thermal_install_field.json (SUMMARY §HW.6)",
        SUMMARY, r"\| \*\*10 s\*\* \| \*\*([\d.]+) °C\*\*",
        "mechanical/thermal_install_field.json",
        lambda d: next(h["cambium_peak_C"] for h in d["duration_sweep"] if h["hold_s"] == 10.0),
        0.1,
    ),
    # ── HW.26 G1 sign run of 58 (the record above is deliberately NOT re-run; in-silico §When Modifying #37) ──
    # ⛔ These four stood in canon for an hour as numbers with no owner (adversary 2026-10-12): a sign «measured once» in a
    #    run nobody can repeat is a remembered number. `58 --insertion-from-lock` writes this cache and nothing else.
    *[(f"58 G1 sign run, {what} → thermal_install_field.g1_insertion.json", doc, anchor, "mechanical/thermal_install_field.g1_insertion.json", fn, tol)
      for what, doc, anchor, fn, tol in (
          ("canon-row cambium peak", SUMMARY, rf"canon row 117\.9 → {N} °C",
           lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["cambium_peak_C"], 0.05),
          ("cambial ring", SUMMARY, rf"cambial ring Ø44\.5 → Ø{N}",
           lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["thermal_wound_dia_50C_mm"], 0.05),
          ("min DBH", SUMMARY, rf"min DBH 111 → {N} cm",
           lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["min_dbh_for_thermal_wound_cm"], 0.5),
          ("10 s pulse", SUMMARY, rf"the 10 s pulse 49\.3 → {N} °C",
           lambda d: next(h["cambium_peak_C"] for h in d["duration_sweep"] if h["hold_s"] == 10.0), 0.05),
          ("min DBH, canon mirror", CODIT, rf"ПАДАЮТЬ \(111 → {N} см\)",
           lambda d: d["scenarios"]["S1a_uniform_Ti_200C"]["min_dbh_for_thermal_wound_cm"], 0.5),
      )],
    # ── PTFE-GDL breakthrough (01_04 §5.3/§5.6) ──
    (
        "pore demanded at the spec-floor theta → gdl_breakthrough.json (01_04 §5.3)",
        CODIT, r"вимагає \*\*не ширших за ([\d.]+) µm\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["theta_inversion"]["CA_110"]["pore_demanded_um"], 0.1,
    ),
    (
        "pore demanded at the prose-top theta → gdl_breakthrough.json (01_04 §5.3)",
        CODIT, r"не ширших за \*\*([\d.]+) µm при θ = 120°\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["theta_inversion"]["CA_120"]["pore_demanded_um"], 0.1,
    ),
    (
        "pore the 30 cm column can actually fail → gdl_breakthrough.json (01_04 §5.6)",
        CODIT, r"30 см валить лише пори ширші за \*\*([\d.]+) µm\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["bench_inversion"]["pore_failed_by_apparatus_um"], 0.1,
    ),
    (
        "O₂ transport margin at the canon lower bound → gdl_breakthrough.json (01_04 §5.3)",
        CODIT, r"запас \*\*([\d]+)×\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["o2_budget"]["per_pore"]["0.02um"]["margin_x"], 1.0,
    ),
    # The RATIFIED flood (02_02 §3.3) — its own cache block, so the hand-set headline above never moves.
    (
        "ratified-flood head → gdl_breakthrough.json (SUMMARY §HW.25)",
        SUMMARY, rf"the row above does not move \| \*\*{N} kPa\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["ratified_flood_scenario"]["pressure_Pa"] / 1000.0, 0.1,
    ),
    (
        "ratified-flood θ threshold, 0.2 µm → gdl_breakthrough.json (SUMMARY §HW.25)",
        SUMMARY, rf"breaking through at θ \*\*{N} / [\d.]+ / [\d.]+°\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["ratified_flood_scenario"]["theta_at_which_it_breaks_through_deg"]["0.2um"], 0.01,
    ),
    (
        "ratified-flood θ threshold, 0.5 µm → gdl_breakthrough.json (SUMMARY §HW.25)",
        SUMMARY, rf"breaking through at θ \*\*[\d.]+ / {N} / [\d.]+°\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["ratified_flood_scenario"]["theta_at_which_it_breaks_through_deg"]["0.5um"], 0.01,
    ),
    (
        "ratified-flood θ threshold, 1.0 µm → gdl_breakthrough.json (SUMMARY §HW.25)",
        SUMMARY, rf"breaking through at θ \*\*[\d.]+ / [\d.]+ / {N}°\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["ratified_flood_scenario"]["theta_at_which_it_breaks_through_deg"]["1.0um"], 0.01,
    ),
    (
        "spec worst case over the ratified flood → gdl_breakthrough.json (SUMMARY §HW.25)",
        SUMMARY, rf"widest spec pore at 110° holds it \*\*{N}×\*\*",
        "kinetics/gdl_breakthrough.json",
        lambda d: d["ratified_flood_scenario"]["spec_worst_case_head_over_flood_x"], 0.1,
    ),
    # ── HW.21 TEG across the PEEK break (script 64) — the load-bearing four ──
    (
        "gap-mount asymptote → teg_across_peek_break.json (SUMMARY §HW.21 verdict)",
        SUMMARY, rf"saturates at {N} °C",
        "mechanical/teg_across_peek_break.json",
        lambda d: d["baseline_from_script_54"]["gap_mount_asymptote_t_anode_C"], 0.005,
    ),
    (
        "solid-Ti no-break reference → teg_across_peek_break.json (SUMMARY §HW.21 table)",
        SUMMARY, rf"solid Ti, NO PEEK break at all\*\* \| 1\.27e−2 W/K \| [\d.]+× \| \*\*{N} °C",
        "mechanical/teg_across_peek_break.json",
        lambda d: d["baseline_from_script_54"]["solid_ti_no_break_t_anode_C"], 0.005,
    ),
    # 🔴 The `8×` in the anchor above is itself a DERIVED number, and until 2026-09-10 it read `6×` —
    # stale since the HW.34 bus re-run moved the denominator. The pin was green throughout, because a
    # value in an ANCHOR is context to match on, never something the pin verifies. So the multiplier
    # gets its own row: the anchor cannot carry an unchecked number twice.
    (
        "solid-Ti no-break MULTIPLIER → teg_across_peek_break.json (SUMMARY §HW.21 table)",
        SUMMARY, rf"solid Ti, NO PEEK break at all\*\* \| 1\.27e−2 W/K \| {N}× \|",
        "mechanical/teg_across_peek_break.json",
        lambda d: (d["baseline_from_script_54"]["solid_ti_no_break_g_W_K"]
                   / d["baseline_from_script_54"]["ti_bus_g_anchor_W_K"]), 0.5,
    ),
    (
        "micro-TEG yield at the thermal budget → teg_across_peek_break.json (SUMMARY §HW.21)",
        SUMMARY, rf"still yields ~{N} µW",
        "mechanical/teg_across_peek_break.json",
        lambda d: d["thermal_budget"]["at_budget"]["p_uW"], 1.0,
    ),
    (
        "fill-factor lower-bound rescue attempt → teg_across_peek_break.json (SUMMARY §HW.21)",
        SUMMARY, rf"the 8×8×4 still fails at {N} °C",
        "mechanical/teg_across_peek_break.json",
        lambda d: d["sensitivities"]["fill_factor_lower_bound"]["t_anode_C"], 0.005,
    ),
    # ── HW.33 gland geometry: the O-ring numbers 02_02 §3.5 quotes from script 52 ──
    # Their owner is the Z-stack cache, and every one of them moves the moment an INPUT moves
    # (cord section, ratified squeeze, dome wall) — which is exactly the drift a re-read of the
    # canon prose cannot see, because the prose stays internally consistent on the old value.
    (
        "O-ring section area → z_stack_tolerance.json §gland_geometry (02_02 §3.5)",
        BLIND_MATE, rf"витісняє сталу площу перерізу \*\*{N} мм²\*\*",
        "mechanical/z_stack_tolerance.json", lambda d: d["gland_geometry"]["ring_area_mm2"], 0.001,
    ),
    (
        "groove width required at the 90 % fill ceiling → z_stack_tolerance.json",
        BLIND_MATE, rf"паз мусить мати ширину \*\*≥ {N} мм\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: min(d["gland_geometry"]["required_width_mm"].values()), 0.005,
    ),
    # ── The rim as a datum, DIMENSIONAL frame (00_07 HW.33, 2026-10-03): a requirement on the bayonet clamp ──
    # The stress-threshold check these anchors replaced carried no geometry of the bayonet at all; every number
    # below moves with an input prose never re-reads — the relaxation floor (lib.constants), the pogo force, the
    # generous O-ring bound and `73`'s lug-root capacity.
    (
        "rim relaxation fraction at 20 yr → z_stack_tolerance.json §rim_datum_creep",
        BLIND_MATE, rf"мультиплікативної релаксації `§4\.2`, \*\*{N}\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["rim_datum_creep"]["relax_fraction_at_service"], 0.005,
    ),
    (
        "pogo pair lift force → z_stack_tolerance.json §rim_datum_creep",
        BLIND_MATE, rf"з парою pogo \(\*\*{N} Н\*\*\)",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["rim_datum_creep"]["pogo_pair_force_N_upper_bound"], 0.005,
    ),
    (
        "required initial bayonet clamp → z_stack_tolerance.json §rim_datum_creep",
        BLIND_MATE, rf"вимога — \*\*≥ {N} Н\*\* початкового притискання",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["rim_datum_creep"]["required_initial_clamp_N"]["with_generous_o_ring"], 0.5,
    ),
    (
        "titanium lug-root capacity the requirement is checked against → z_stack_tolerance.json (← 73)",
        BLIND_MATE, rf"корінь вушка Ti її несе \(\*\*{N} Н\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["rim_datum_creep"]["lug_root_capacity_N_from_73"], 0.5,
    ),
    (
        "depth-tolerance budget in µm → z_stack_tolerance.json §depth_tolerance_budget",
        BLIND_MATE, rf"мусить лишитись у \*\*±{N} мкм\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["depth_tolerance_budget"]["total_gap_budget_half_width_mm"] * 1000.0, 1.0,
    ),
    # ── HW.33 branch (а) APPLIED (2026-09-14): the numbers 02_02 §3.5 quotes from the rebuilt O-ring chain ──
    # Every one moves with an input nobody re-reads in prose: the asked depth tolerance behind the band and the
    # flatness leftover, and the socket band / gland fill behind the applied radii and the rim contact area.
    (
        "residual O-ring band on the applied one-term chain → z_stack_tolerance.json §parker_face_reconciliation",
        BLIND_MATE, rf"залишкова смуга \*\*±{N} в\.п\.\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["parker_face_reconciliation"]["residual_half_width_pct_points"], 0.005,
    ),
    (
        "applied squeeze band, low edge → z_stack_tolerance.json §parker_face_reconciliation",
        BLIND_MATE, rf"залишкова смуга \*\*±[\d.]+ в\.п\.\*\* → \*\*{N}\*\*–",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["parker_face_reconciliation"]["band_at_recommended_pct"][0], 0.05,
    ),
    (
        "applied squeeze band, high edge → z_stack_tolerance.json §parker_face_reconciliation",
        BLIND_MATE, rf"→ \*\*[\d.]+\*\*–\*\*{N} %\*\* усередині обох вікон",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["parker_face_reconciliation"]["band_at_recommended_pct"][1], 0.05,
    ),
    (
        "flatness leftover after the asked depth tolerance → z_stack_tolerance.json §depth_tolerance_budget",
        BLIND_MATE, rf"лишає \*\*±{N} мкм\*\* \(RSS\) на площинність",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["depth_tolerance_budget"]["chain_as_modelled"]["flatness_left_rss_mm"] * 1000.0, 1.0,
    ),
    (
        "seal land inner radius → z_stack_tolerance.json §applied_gland",
        BLIND_MATE, rf"земля приливу r \*\*{N}\*\*–\*\*[\d.]+\*\* мм",
        "mechanical/z_stack_tolerance.json", lambda d: d["applied_gland"]["radome_seal_land_r_mm"][0], 0.001,
    ),
    (
        "seal land outer radius → z_stack_tolerance.json §applied_gland",
        BLIND_MATE, rf"земля приливу r \*\*[\d.]+\*\*–\*\*{N}\*\* мм",
        "mechanical/z_stack_tolerance.json", lambda d: d["applied_gland"]["radome_seal_land_r_mm"][1], 0.001,
    ),
    (
        "flange groove inner radius → z_stack_tolerance.json §applied_gland",
        BLIND_MATE, rf"паз r \*\*{N}\*\*–\*\*[\d.]+\*\* мм",
        "mechanical/z_stack_tolerance.json", lambda d: d["applied_gland"]["flange_groove_r_mm"][0], 0.001,
    ),
    (
        "flange groove outer radius → z_stack_tolerance.json §applied_gland",
        BLIND_MATE, rf"паз r \*\*[\d.]+\*\*–\*\*{N}\*\* мм",
        "mechanical/z_stack_tolerance.json", lambda d: d["applied_gland"]["flange_groove_r_mm"][1], 0.001,
    ),
    (
        "rim contact area of the applied boss → z_stack_tolerance.json §rim_datum_creep",
        BLIND_MATE, rf"контактній площі обода \*\*{N} мм²\*\*",
        "mechanical/z_stack_tolerance.json", lambda d: d["rim_datum_creep"]["rim_contact_area_mm2"], 0.5,
    ),
    # ── HW.33 → HW.9 board budget (2026-09-14): the envelope 02_02 §3.5 hands the board layout ──
    # Every one of these moves with an input nobody re-reads in prose: the gland fill ceiling behind the
    # Ø, the crown round and cavity height behind the headroom, and the BOM rows behind the stack.
    (
        "rim-boss board ceiling the collar is subtracted from → z_stack_tolerance.json §rim_boss_radial_budget",
        BLIND_MATE, rf"стеля плати `≤ Ø{N} − 2·t_коміра`",
        "mechanical/z_stack_tolerance.json", lambda d: d["rim_boss_radial_budget"]["design_to_mm"], 0.005,
    ),
    (
        "loosest ceiling any collar can leave (print floor) → z_stack_tolerance.json §collar_radial_budget",
        BLIND_MATE, rf"найслабшу можливу стелю \*\*Ø{N}\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["collar_radial_budget"]["loosest_ceiling_any_collar_mm"], 0.005,
    ),
    (
        "internal height over the flange face under the ratified crown → z_stack_tolerance.json §vertical_stack_budget",
        BLIND_MATE, rf"Під ратифікованою короною над гранню фланця \*\*{N} мм\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["vertical_stack_budget"]["internal_height_mm"]["crown_centre"], 0.05,
    ),
    (
        "the former hemisphere headroom (the contrast; the crown was applied 2026-09-22) → z_stack_tolerance.json §vertical_stack_budget",
        BLIND_MATE, rf"\(колишня півсфера — {N}\)",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["vertical_stack_budget"]["internal_height_mm"]["hemisphere_centre_today"], 0.05,
    ),
    # ⛔ The pad-under-piezo pin (AST1240 · B2B 10, −1.15 mm) went with the placement axis on 2026-09-29: the
    # piezo was cut (02_01 §6), 52 no longer computes those rows, and 02_02 §3.5 now carries the number as a
    # dated record of the 2026-09-22 grid — history, not a cache mirror, so there is nothing left to pin it to.
    (
        "antenna Z the named B2B alternative leaves → z_stack_tolerance.json §vertical_stack_budget",
        BLIND_MATE, rf"антена опускається на ті самі 2 мм — до \*\*{N} мм\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["vertical_stack_budget"]["summary"]["alt_b2b_lever"]["antenna_z_mm"], 0.005,
    ),
    # ── HW.34 bus thermal bridge: numbers SUMMARY quotes from script 54 ──
    # ⛔ No pin stood here until 2026-10-12, and the HW.26 G1 re-run (6 → 18 mm PEEK gap) flipped a frost-gate
    # verdict — CP-Ti from «freeze» to «safe» — under prose that stayed green. The gate's two sides are pinned.
    *[(f"bus thermal bridge, anode pocket, {what} → anchor_thermal_bridge.json", SUMMARY, anchor,
       "mechanical/anchor_thermal_bridge.json", fn, tol)
      for what, anchor, fn, tol in (
          ("Cu bus", rf"drags the Zone-1 anode pocket to \*\*{N} °C\*\*",
           lambda d: d["steady_state_baseline"]["t_anode_C"]["Cu"], 0.05),
          ("monolithic Ti", rf"thermally near-invisible \(\*\*\+?{N} °C\*\*",
           lambda d: d["steady_state_baseline"]["t_anode_C"]["Ti"], 0.005),
          ("CP-Ti", rf"CP-Ti \(λ17\) \*\*{N}\*\*",
           lambda d: next(r for r in d["per_alloy_monolithic_bus"]["rows"] if r["alloy"] == "CP-Ti-Gr4")["t_anode_C"], 0.005),
          ("Ta", rf"Ta \(λ57, benchmark\) \*\*{N}\*\*",
           lambda d: next(r for r in d["per_alloy_monolithic_bus"]["rows"] if r["alloy"] == "Ta")["t_anode_C"], 0.005),
      )],
    # ── HW.34 coaxiality priced as a MEAN stress (script 86, ⚖️ 2026-10-12 exception to the crown pause) ──
    # ⛔ The three branches ARE the presentation the founder decides on; a branch row that drifted from the cache would
    #    hand the verdict a price nobody computed.
    *[(f"coaxiality, {branch} {what} → coaxiality_allocation.json", SUMMARY,
       rf"\| {re.escape(label)} \|" + "".join(r" [^|]*\|" for _ in range(k)) + rf" \*\*{N}\*\* \|",
       "mechanical/coaxiality_allocation.json", lambda d, b=branch, key=key: d["branches"][b]["by_geometry"][next(iter(d["by_geometry"]))][key], tol)
      for branch, label in (("tight", "tight ⌀0.04"), ("loose_50", "loose ⌀0.10"), ("loose_100", "loose ⌀0.20"))
      for k, (what, key, tol) in enumerate((("mean", "mean_MPa", 0.05), ("wire SF", "sf_wire_binding", 0.005),
                                           ("seam k", "k_break_even_binding", 0.0005)))],
    # ── HW.43 stem sway → load through the pogo pins (script 87, 2026-10-13) ──
    # ⛔ The per-gram ratio is what the spring's amplitude is read from once the drawing and the scale give τ_m and m;
    #    a SUMMARY figure drifted off the cache would hand framing B of 59 a fraction nobody computed.
    *[(f"pogo sway transfer, {label} → pogo_sway_transfer.json", SUMMARY, pattern,
       "mechanical/pogo_sway_transfer.json", resolver, tol)
      for label, pattern, resolver, tol in (
          ("12 m control", rf"slope × flux = \*\*{N}°\*\*",
           lambda d: d["controls"]["slope_times_flux_reproduces_12m_tilt"]["deg"], 0.05),
          ("median accel", rf"acceleration, ≈ \*\*{N}\*\* \(median\)",
           lambda d: d["by_slope_reading"]["median"]["stem_at_anchor_h_le_2m"]["accel_m_s2"], 0.005),
          ("whisker accel", rf"\(median\) … \*\*{N}\*\* m/s² \(whisker\)",
           lambda d: d["by_slope_reading"]["upper_whisker"]["stem_at_anchor_h_le_2m"]["accel_m_s2"], 0.005),
          ("median ratio per gram", rf"\*\*{N} % \(median\) … [\d.]+ % \(whisker\) per gram",
           lambda d: d["by_slope_reading"]["median"]["B_inertia_coaxial"]["force_ratio_per_gram"] * 100, 0.005),
          ("whisker ratio per gram", rf"\(median\) … {N} % \(whisker\) per gram",
           lambda d: d["by_slope_reading"]["upper_whisker"]["B_inertia_coaxial"]["force_ratio_per_gram"] * 100, 0.005),
          ("initial O-ring reaction for the rim at 52's clamp", rf"initial O-ring reaction ≥ \*\*{N}\*\* N \(median reading\)",
           lambda d: d["by_slope_reading"]["median"]["A_rim"]["o_ring_reaction_N_needed"]["initial_with_clamp_at_52_requirement"], 0.005),
          ("stack mass estimate, low", rf"— \*\*{N}–[\d.]+ g\*\*\. At that mass",
           lambda d: d["by_slope_reading"]["median"]["B_inertia_coaxial"]["at_estimated_stack_mass"]["stack_mass_g"][0], 0.005),
          ("stack mass estimate, high", rf"— \*\*[\d.]+–{N} g\*\*\. At that mass",
           lambda d: d["by_slope_reading"]["median"]["B_inertia_coaxial"]["at_estimated_stack_mass"]["stack_mass_g"][1], 0.005),
          ("inertia at the estimate, median light", rf"\*\*{N} %\*\* \(median, light\)",
           lambda d: d["by_slope_reading"]["median"]["B_inertia_coaxial"]["at_estimated_stack_mass"]["ratio_over_reduced_mean"][0] * 100, 0.005),
          ("inertia at the estimate, whisker heavy", rf"\*\*{N} %\*\* \(whisker, heavy\)",
           lambda d: d["by_slope_reading"]["upper_whisker"]["B_inertia_coaxial"]["at_estimated_stack_mass"]["ratio_over_reduced_mean"][1] * 100, 0.005),
          ("rim capacity early in life", rf"gives ≈ \*\*{N}\*\* N of capacity",
           lambda d: d["by_slope_reading"]["median"]["A_rim"]["capacity_N_initial_at_52_requirement"], 0.05),
          ("10 % stack mass", rf"10 % is reached at \*\*{N}\*\* \(whisker\)",
           lambda d: d["by_slope_reading"]["upper_whisker"]["B_inertia_coaxial"]["stack_mass_g_for_ratio_10pct"], 0.05),
          ("weakest pin unloads", rf"unloads at \*\*{N}\*\* \(whisker\)",
           lambda d: d["by_slope_reading"]["upper_whisker"]["B_inertia_coaxial"]["stack_mass_g_where_weakest_pin_unloads"], 0.5),
          ("centre pad per 1000 µε, low", rf"\*\*{N} … [\d.]+ % of the working compression per 1000 µε",
           lambda d: d["by_slope_reading"]["median"]["C_centre_pad_poisson"]["ratio_per_1000_microstrain"]["mu_lr_lo_dx_nominal"] * 100, 0.005),
          ("centre pad on the source day, low", rf"{N}–[\d.]+ % on the source day",
           lambda d: d["by_slope_reading"]["median"]["C_centre_pad_poisson"]["ratio_at_source_strain"][0] * 100, 0.05),
          ("centre pad on the source day, high", rf"[\d.]+–{N} % on the source day",
           lambda d: d["by_slope_reading"]["upper_whisker"]["C_centre_pad_poisson"]["ratio_at_source_strain"][1] * 100, 0.05),
          ("tilt at 2 m, median", rf"the tilt is ≤ {N}–[\d.]+°",
           lambda d: d["by_slope_reading"]["median"]["stem_at_anchor_h_le_2m"]["tilt_deg"], 0.005),
          ("tilt at 2 m, whisker", rf"the tilt is ≤ [\d.]+–{N}°",
           lambda d: d["by_slope_reading"]["upper_whisker"]["stem_at_anchor_h_le_2m"]["tilt_deg"], 0.005),
          ("NOS displacement, median", rf"non-oscillatory displacement ≤ {N}–[\d.]+ mm",
           lambda d: d["by_slope_reading"]["median"]["stem_at_anchor_h_le_2m"]["nos_displacement_mm"], 0.5),
          ("NOS displacement, whisker", rf"non-oscillatory displacement ≤ [\d.]+–{N} mm",
           lambda d: d["by_slope_reading"]["upper_whisker"]["stem_at_anchor_h_le_2m"]["nos_displacement_mm"], 0.5),
          ("stem strain, median", rf"is ≈ {N}–[\d.]+ µε at the source tree",
           lambda d: d["by_slope_reading"]["median"]["stem_at_anchor_h_le_2m"]["surface_strain_microstrain_source_tree"], 5),
          ("stem strain, whisker", rf"is ≈ [\d.]+–{N} µε at the source tree",
           lambda d: d["by_slope_reading"]["upper_whisker"]["stem_at_anchor_h_le_2m"]["surface_strain_microstrain_source_tree"], 5),
          ("centre pad per 1000 µε, high", rf"… {N} % of the working compression per 1000 µε",
           lambda d: d["by_slope_reading"]["median"]["C_centre_pad_poisson"]["ratio_per_1000_microstrain"]["mu_lr_hi_dx_ceiling"] * 100, 0.005),
          # (C) behind the liner, 2026-10-17 — a CEILING; the requirements round UP and the SF floor DOWN (in-silico
          # §When Modifying #43), so they are pinned EXACTLY to the rounded value, never within a tolerance
          ("liner wall ceiling", rf"so the wall caps it at \*\*{N}\*\* N",
           lambda d: _wbl(d)["route"]["wall_capacity_N_at_23C"], 0.05),
          ("wire stress at the ceiling", rf"\*\*{N}\*\* MPa on the wire, PEEK's 23 °C uniaxial yield",
           lambda d: _wbl(d)["route"]["wire_stress_at_wall_capacity_MPa"], 0.05),
          ("86's own k on Ti-6Al-4V", rf"from k ≥ {N} to \*\*[\d.]+\*\* on Ti-6Al-4V",
           lambda d: _wbl(d)["by_alloy"]["Ti-6Al-4V"]["seam_k_86"], 0.00005),
          ("seam k at the ceiling, Ti-6Al-4V", rf"to \*\*{N}\*\* on Ti-6Al-4V",
           lambda d: _up2(_wbl(d)["by_alloy"]["Ti-6Al-4V"]["seam_k_at_route_capacity"]), 0),
          ("seam k at the ceiling, Ta", rf"from 0\.3883 to \*\*{N}\*\* on Ta",
           lambda d: _up2(_wbl(d)["by_alloy"]["Ta"]["seam_k_at_route_capacity"]), 0),
          ("wire SF at the ceiling, Ta", rf"drops the wire's SF on Ta from [\d.]+ to \*\*{N}\*\*",
           lambda d: _down2(_wbl(d)["by_alloy"]["Ta"]["sf_wire_at_route_capacity"]), 0),
          ("seam k at the ceiling, CP-Ti-Gr4", rf"on CP-Ti-Gr4 \(\*\*{N}\*\*\)",
           lambda d: _up2(_wbl(d)["by_alloy"]["CP-Ti-Gr4"]["seam_k_at_route_capacity"]), 0),
          ("seam k at the ceiling, Ta, tightest branch", rf"on Ta even the tightest needs k ≥ \*\*{N}\*\*",
           lambda d: _up2(min(_wbl(d)["by_alloy"]["Ta"]["seam_k_at_route_capacity_by_branch"].values())), 0))],
    # 87's liner ceiling as 01_01 §1.4 «Співвісність» ⊕ 2026-10-17 quotes it — rounded thresholds pinned EXACTLY
    *[(f"pogo sway transfer, {label} in 01_01 §1.4 → pogo_sway_transfer.json", "docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md",
       pattern, "mechanical/pogo_sway_transfer.json", resolver, tol)
      for label, pattern, resolver, tol in (
          ("seam k at the ceiling, Ti-6Al-4V", rf"вимагає `k` ≥ \*\*{N}\*\* на Ti-6Al-4V",
           lambda d: _up2(_wbl(d)["by_alloy"]["Ti-6Al-4V"]["seam_k_at_route_capacity"]), 0),
          ("seam k at the ceiling, Ta", rf"і ≥ \*\*{N}\*\* на Ta, а SF дроту",
           lambda d: _up2(_wbl(d)["by_alloy"]["Ta"]["seam_k_at_route_capacity"]), 0),
          ("wire SF at the ceiling, Ta", rf"SF дроту на Ta падає з [\d.]+ до \*\*{N}\*\*",
           lambda d: _down2(_wbl(d)["by_alloy"]["Ta"]["sf_wire_at_route_capacity"]), 0),
          ("Ti-15Zr tight branch at the ceiling", rf"тугою гілкою \(\*\*{N}\*\*\)",
           lambda d: _wbl(d)["by_alloy"]["Ti-15Zr"]["seam_k_at_route_capacity_by_branch"]["tight"], 0.00005),
          ("Ti-15Zr ⌀0.10 at the ceiling", rf"і ⌀0\.10 \(\*\*{N}\*\*\)",
           lambda d: _wbl(d)["by_alloy"]["Ti-15Zr"]["seam_k_at_route_capacity_by_branch"]["loose_50"], 0.00005))],
    ("pogo sway transfer, NOS displacement in the 01_02 bench table → pogo_sway_transfer.json",
     "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md", rf"сягає до [\d.]+–{N} мм", "mechanical/pogo_sway_transfer.json",
     lambda d: d["by_slope_reading"]["upper_whisker"]["stem_at_anchor_h_le_2m"]["nos_displacement_mm"], 0.5),
    # ── HW.43 the pogo gap's thermal travel (script 90, 2026-10-13) ──
    *[(f"pogo thermal gap, {label} → pogo_thermal_gap.json", doc, pattern,
       "mechanical/pogo_thermal_gap.json", resolver, tol)
      for label, doc, pattern, resolver, tol in (
          ("SUMMARY coefficient low", SUMMARY, rf"it moves by \*\*{N}–[\d.]+\*\* µm/K with both together",
           lambda d: d["coefficients_um_per_K"]["gap"]["isothermal_low_stack"], 0.005),
          ("SUMMARY coefficient high", SUMMARY, rf"it moves by \*\*[\d.]+–{N}\*\* µm/K with both together",
           lambda d: d["coefficients_um_per_K"]["gap"]["isothermal_high_stack"], 0.005),
          ("SUMMARY coefficient gradient", SUMMARY, rf"and \*\*{N}\*\* µm/K when the radome leads",
           lambda d: d["coefficients_um_per_K"]["gap"]["radome_leads_reading"], 0.005),
          ("SUMMARY cold closing", SUMMARY, rf"closes by up to \*\*{N}\*\* µm in the cold",
           lambda d: -d ["seasonal"]["capsule_requirement"]["isothermal_high_stack"]["gap_um_cold"], 0.5),
          ("SUMMARY hot opening", SUMMARY, rf"opens by \*\*{N}\*\* µm in the heat",
           lambda d: d ["seasonal"]["capsule_requirement"]["isothermal_high_stack"]["gap_um_hot"], 0.5),
          ("SUMMARY L1 lead tolerated", SUMMARY, rf"leading the stack by about \*\*{N}\*\* K",
           lambda d: d["radome_lead_tolerated_by_L1_K"], 0.5),
          ("SUMMARY daily median", SUMMARY, rf"swings by a median \*\*{N}\*\* K",
           lambda d: d["daily_capsule_range_K"]["median"], 0.05),
          ("SUMMARY daily p95", SUMMARY, rf"95th percentile \*\*{N}\*\* K",
           lambda d: d["daily_capsule_range_K"]["p95"], 0.05),
          ("SUMMARY daily force ratio high", SUMMARY, rf"\*\*[\d.]+–{N}\*\* % of the minimum preload",
           lambda d: d["daily"]["radome_leads_reading"]["p95"]["force_ratio_over_min_preload"] * 100, 0.05),
          ("SUMMARY slide high", SUMMARY, rf"slides by \*\*[\d.]+–{N}\*\* µm per mm of r",
           lambda d: d["radial_slide_daily_um_per_mm_radius"]["flange_held"]["p95"], 0.005),
          ("02_02 §3.5 L1 lead", BLIND_MATE, rf"витримує випередження до ≈ \*\*{N} K\*\*",
           lambda d: d["radome_lead_tolerated_by_L1_K"], 0.5),
          # ⊕ 2026-10-18 — the pin body (brass C36000) and the FR-4 sheets' in-plane CTE
          ("SUMMARY pin body coefficient", SUMMARY, rf"\*\*{N}\*\* µm/K over the pin's",
           lambda d: d["coefficients_um_per_K"]["pin_body"], 0.0005),
          ("SUMMARY working stroke low", SUMMARY, rf"\*\*{N}–[\d.]+\*\* µm/K together, the radome's",
           lambda d: d["coefficients_um_per_K"]["working_stroke"]["isothermal_low_stack"], 0.005),
          ("SUMMARY working stroke high", SUMMARY, rf"\*\*[\d.]+–{N}\*\* µm/K together, the radome's",
           lambda d: d["coefficients_um_per_K"]["working_stroke"]["isothermal_high_stack"], 0.005),
          ("SUMMARY L1 isothermal margin low", SUMMARY, rf"holds isothermally with \*\*{N}–[\d.]+\*\* µm to spare",
           lambda d: min(d["seasonal"]["capsule_requirement"]["isothermal_high_stack"]["window"]["L1 spacer only"]["margin_um"]), 0.5),
          ("SUMMARY L1 isothermal margin high", SUMMARY, rf"holds isothermally with \*\*[\d.]+–{N}\*\* µm to spare",
           lambda d: max(d["seasonal"]["capsule_requirement"]["isothermal_high_stack"]["window"]["L1 spacer only"]["margin_um"]), 0.5),
          # a .1f display sits up to 0.05 off its value, so the 1-decimal spacer and stroke pins carry 0.051
          ("SUMMARY spacer CTE at zero margin, high end", SUMMARY, rf"CTE \*\*{N}…[−\-][\d.]+\*\* ppm/K",
           lambda d: max(d["spacer_alpha_1K_at_zero_L1_margin"].values()) * 1e6, 0.051),
          ("SUMMARY spacer CTE at zero margin, low end", SUMMARY, rf"CTE \*\*[−\-][\d.]+…{N}\*\* ppm/K",
           lambda d: min(d["spacer_alpha_1K_at_zero_L1_margin"].values()) * 1e6, 0.051),
          ("SUMMARY daily force ratio low", SUMMARY, rf"\*\*{N}–[\d.]+\*\* % of the minimum preload",
           lambda d: min(v["median"]["force_ratio_over_min_preload"] for v in d["daily"].values()) * 100, 0.05),
          ("SUMMARY board slide low", SUMMARY, rf"\*\*{N}–[\d.]+\*\* µm if the pins follow the board",
           lambda d: d["radial_slide_daily_um_per_mm_radius"]["board_isothermal_low"]["p95"], 0.005),
          ("SUMMARY board slide high", SUMMARY, rf"\*\*[\d.]+–{N}\*\* µm if the pins follow the board",
           lambda d: d["radial_slide_daily_um_per_mm_radius"]["board_flange_held_high"]["p95"], 0.005),
          ("02_02 §3.5 spacer CTE at zero margin", BLIND_MATE, rf"КТР розпірного елемента {N}…[−\-][\d.]+ ppm/K",
           lambda d: max(d["spacer_alpha_1K_at_zero_L1_margin"].values()) * 1e6, 0.051),
          ("02_02 §3.5 L1 isothermal margin", BLIND_MATE, rf"із запасом \*\*{N}–[\d.]+ мкм\*\*",
           lambda d: min(d["seasonal"]["capsule_requirement"]["isothermal_high_stack"]["window"]["L1 spacer only"]["margin_um"]), 0.5),
          # ⊕ 2026-10-18 adversary — the pin's free length moves the tip; the ends of every quoted range are pinned
          ("SUMMARY pin free length", SUMMARY, rf"over the pin's \*\*{N}\*\* mm free length",
           lambda d: d["inputs"]["pin_free_length_mm"], 0.005),
          ("SUMMARY daily stroke low", SUMMARY, rf"a pin stroke of \*\*{N}–[\d.]+\*\* µm",
           lambda d: min(v["median"]["stroke_um"] for v in d["daily"].values()), 0.051),
          ("SUMMARY daily stroke high", SUMMARY, rf"a pin stroke of \*\*[\d.]+–{N}\*\* µm",
           lambda d: d["daily"]["radome_leads_reading"]["p95"]["stroke_um"], 0.051),
          ("02_02 §3.5 pin free length", BLIND_MATE, rf"вільній довжині піна, {N} мм",
           lambda d: d["inputs"]["pin_free_length_mm"], 0.005),
          ("02_02 §3.5 L1 isothermal margin high", BLIND_MATE, rf"із запасом \*\*[\d.]+–{N} мкм\*\*",
           lambda d: max(d["seasonal"]["capsule_requirement"]["isothermal_high_stack"]["window"]["L1 spacer only"]["margin_um"]), 0.5),
          ("02_02 §3.5 spacer CTE at zero margin, low end", BLIND_MATE, rf"КТР розпірного елемента [−\-][\d.]+…{N} ppm/K",
           lambda d: min(d["spacer_alpha_1K_at_zero_L1_margin"].values()) * 1e6, 0.051),
          ("02_02 §3.5 daily force ratio low", BLIND_MATE, rf"Добовий хід — {N}–[\d.]+ %",
           lambda d: min(v["median"]["force_ratio_over_min_preload"] for v in d["daily"].values()) * 100, 0.05),
          ("02_02 §3.5 daily force ratio high", BLIND_MATE, rf"Добовий хід — [\d.]+–{N} %",
           lambda d: d["daily"]["radome_leads_reading"]["p95"]["force_ratio_over_min_preload"] * 100, 0.05))],
    # ── HW.33 the bayonet clamp over its fit and temperature — the ratified member is a lower bound (script 89, 2026-10-13) ──
    # ⛔ These numbers returned a founder verdict; a doc copy drifted off the cache would re-price it silently.
    *[(f"bayonet thermal clamp, {label} → bayonet_thermal_clamp.json", doc, pattern,
       "mechanical/bayonet_thermal_clamp.json", resolver, tol)
      for label, doc, pattern, resolver, tol in (
          ("SUMMARY wall per N/µm, ±0.05", SUMMARY, rf"every N/µm adds \*\*{N}\*\* mm of wall at the window top",
           lambda d: d ["by_squeeze_point"]["window_top"] ["by_reading"]["capsule_requirement|isothermal"]["by_delta_mm"]["0.05"]["wall_mm_per_N_per_um"], 0.0005),
          ("SUMMARY thermal share", SUMMARY, rf"\(temperature is \*\*{N}\*\* % of it",
           lambda d: d ["by_squeeze_point"]["window_top"] ["by_reading"]["capsule_requirement|isothermal"]["by_delta_mm"]["0.05"]["thermal_share_of_slope"] * 100, 0.5),
          ("SUMMARY wall per N/µm, no tolerance", SUMMARY, rf"with no tolerance \*\*{N}\*\* mm",
           lambda d: d ["by_squeeze_point"]["window_top"] ["by_reading"]["capsule_requirement|isothermal"]["by_delta_mm"]["0.0"]["wall_mm_per_N_per_um"], 0.00005),
          ("SUMMARY force-controlled load", SUMMARY, rf"\*\*{N}\*\* N at the window top, a",
           lambda d: d ["by_squeeze_point"]["window_top"]["force_controlled_lug_load_N"], 0.5),
          ("SUMMARY force-controlled wall", SUMMARY, rf"a\n?\*\*{N}\*\* mm wall with a zero force band",
           lambda d: d ["by_squeeze_point"]["window_top"]["force_controlled_wall_mm_zero_band"], 0.005),
          ("SUMMARY spring stiffness", SUMMARY, rf"no stiffer than \*\*{N}\*\* N/µm",
           lambda d: d ["by_squeeze_point"]["window_top"]["spring_capsule_requirement"]["0.05"]["k_spring_max_N_per_um_zero_tolerance"], 0.006),
          ("SUMMARY spring deflection", SUMMARY, rf"≈ \*\*{N}\*\* mm of working deflection",
           lambda d: d ["by_squeeze_point"]["window_top"]["spring_capsule_requirement"]["0.05"]["working_deflection_mm_at_band_centre"], 0.05),
          ("SUMMARY force band", SUMMARY, rf"fits ±\*\*{N}\*\* %",
           lambda d: d ["by_squeeze_point"]["window_top"]["force_band_half_width_to_print_floor"] * 100, 0.05),
          ("SUMMARY contact p0 top", SUMMARY, rf"peaks on the mean lug at \*\*{N}\*\* MPa at the window top",
           lambda d: d ["by_squeeze_point"]["window_top"]["lug_line_contact_p0_MPa"]["PEEK_dominated_minimum"]["socket_pocket_minus_clearance"], 0.5),
          ("SUMMARY contact p0 floor", SUMMARY, rf"\({N} at the window\nfloor; ",
           lambda d: d["by_squeeze_point"]["window_floor"]["lug_line_contact_p0_MPa"]["PEEK_dominated_minimum"][
               "socket_pocket_minus_clearance"], 0.5),
          ("SUMMARY yield onset", SUMMARY, rf"against \*\*{N}\*\* MPa for first yield",
           lambda d: d["inputs"]["lug_line_contact"]["yield_onset_p0_pa"] * 1e-6, 0.5),
          ("SUMMARY table floor k=3", SUMMARY, rf"\| 121 \| 0\.08 · 0\.13 · {N} · ",
           lambda d: d["by_squeeze_point"]["window_floor"]["by_reading"]["capsule_requirement|isothermal"]["by_delta_mm"]["0.05"]["strength_wall_mm_by_k"]["3.0"], 0.005),
          ("SUMMARY table top k=10", SUMMARY, rf"\| 411 \| 0\.28 · 0\.33 · 0\.42 · {N} \|",
           lambda d: d ["by_squeeze_point"]["window_top"] ["by_reading"]["capsule_requirement|isothermal"]["by_delta_mm"]["0.05"]["strength_wall_mm_by_k"]["10.0"], 0.005),
          ("02_02 §4.4 wall per N/µm", BLIND_MATE, rf"кожен Н/мкм додає \*\*{N} мм\*\* стінки",
           lambda d: d ["by_squeeze_point"]["window_top"] ["by_reading"]["capsule_requirement|isothermal"]["by_delta_mm"]["0.05"]["wall_mm_per_N_per_um"], 0.0005),
          ("02_02 §4.4 force-controlled load", BLIND_MATE, rf"аж до L₀ — \*\*{N} Н\*\*",
           lambda d: d ["by_squeeze_point"]["window_top"]["force_controlled_lug_load_N"], 0.5),
          ("02_02 §4.4 force-controlled wall", BLIND_MATE, rf"стінка \*\*{N} мм\*\* за нульової смуги",
           lambda d: d ["by_squeeze_point"]["window_top"]["force_controlled_wall_mm_zero_band"], 0.005),
          ("02_02 §4.4 spring stiffness", BLIND_MATE, rf"пружині треба k ≤ \*\*{N} Н/мкм\*\*",
           lambda d: d ["by_squeeze_point"]["window_top"]["spring_capsule_requirement"]["0.05"]["k_spring_max_N_per_um_zero_tolerance"], 0.006),
          ("02_02 §4.4 contact p0 top", BLIND_MATE, rf"на верху вікна він дає \*\*{N} МПа\*\*",
           lambda d: d ["by_squeeze_point"]["window_top"]["lug_line_contact_p0_MPa"]["PEEK_dominated_minimum"]["socket_pocket_minus_clearance"], 0.5))],
    # ── HW.33 · HW.43 the O-ring's own reaction — Parker Figure 2-4 + Table 2-3 over 52's window (script 88, 2026-10-13) ──
    # ⛔ These numbers took the «generous» 100 N out of the role of an upper bound; a doc copy drifted off the cache would
    #    put the lug root's margin, or (A)'s margin, back on a number nobody computed.
    *[(f"O-ring reaction band, {label} → oring_reaction_band.json", doc, pattern,
       "mechanical/oring_reaction_band.json", resolver, tol)
      for label, doc, pattern, resolver, tol in (
          ("SUMMARY (A) floor", SUMMARY, rf"no less than \*\*{N}\*\* N at the 19 % window floor",
           lambda d: d["band"]["window_floor"]["reaction_N"][0], 0.6),
          ("SUMMARY (A) margin, clamp at 52's requirement", SUMMARY, rf"— \*\*{N}×\*\* the reaction \(A\) needs",
           lambda d: d["rim_premise_A"]["margin_x"]["initial_with_clamp_at_52_requirement"], 0.05),
          ("SUMMARY (A) weaker-clamp share", SUMMARY, rf"keeping {N} % of its reaction for 20 years",
           lambda d: d["rim_premise_A"]["share_retained_needed_with_a_weaker_clamp"] * 100, 0.5),
          ("SUMMARY nominal band low", SUMMARY, rf"\| 24\.5 % — nominal \| {N}–[\d.]+ \|",
           lambda d: d["band"]["nominal"]["reaction_N"][0], 0.6),
          ("SUMMARY nominal band high", SUMMARY, rf"\| 24\.5 % — nominal \| [\d.]+–{N} \|",
           lambda d: d["band"]["nominal"]["reaction_N"][1], 0.6),
          ("SUMMARY window-top margin at assembly", SUMMARY, rf"\| 30 % — window top \| [\d.]+–[\d.]+ \| {N}× …",
           lambda d: d["band"]["window_top"]["lug_root_margin_x_at_print_floor"]["at_assembly"], 0.005),
          ("SUMMARY window-top margin, ring never relaxes", SUMMARY, rf"\| 30 % — window top \| [\d.]+–[\d.]+ \| [\d.]+× … {N}× \|",
           lambda d: d["band"]["window_top"]["lug_root_margin_x_at_print_floor"]["after_20_years_ring_never_relaxes"], 0.005),
          ("SUMMARY chain-high margin, ring never relaxes", SUMMARY, rf"\| 27\.3 % — `52`'s chain, high \| [\d.]+–[\d.]+ \| [\d.]+× … {N}× \|",
           lambda d: d["band"]["chain_high"]["lug_root_margin_x_at_print_floor"]["after_20_years_ring_never_relaxes"], 0.005),
          ("SUMMARY window-top loss by year 2", SUMMARY,
           rf"\| 30 % — window top \| [\d.]+–[\d.]+ \| [\d.]+× … [\d.]+× \| {N} · [\d.]+ · [\d.]+ %",
           lambda d: d["band"]["window_top"]["ring_must_have_lost_share_of_R0_by_year"]["2"] * 100, 0.5),
          ("SUMMARY window-top loss by year 5", SUMMARY,
           rf"\| 30 % — window top \| [\d.]+–[\d.]+ \| [\d.]+× … [\d.]+× \| [\d.]+ · {N} · [\d.]+ %",
           lambda d: d["band"]["window_top"]["ring_must_have_lost_share_of_R0_by_year"]["5"] * 100, 0.5),
          ("SUMMARY window-top loss by year 20", SUMMARY,
           rf"\| 30 % — window top \| [\d.]+–[\d.]+ \| [\d.]+× … [\d.]+× \| [\d.]+ · [\d.]+ · {N} %",
           lambda d: d["band"]["window_top"]["ring_must_have_lost_share_of_R0_by_year"]["20"] * 100, 0.5),
          ("SUMMARY chain-top loss by year 5", SUMMARY,
           rf"\| 27\.3 % — `52`'s chain, high \| [\d.]+–[\d.]+ \| [\d.]+× … [\d.]+× \| [\d.]+ · {N} · [\d.]+ %",
           lambda d: d["band"]["chain_high"]["ring_must_have_lost_share_of_R0_by_year"]["5"] * 100, 0.5),
          ("SUMMARY chain-top loss by year 20", SUMMARY,
           rf"\| 27\.3 % — `52`'s chain, high \| [\d.]+–[\d.]+ \| [\d.]+× … [\d.]+× \| [\d.]+ · [\d.]+ · {N} %",
           lambda d: d["band"]["chain_high"]["ring_must_have_lost_share_of_R0_by_year"]["20"] * 100, 0.5),
          ("SUMMARY binding squeeze", SUMMARY, rf"binds the lug from {N} %",
           lambda d: d["inversion"]["squeeze_pct_band_high_binds"], 0.05),
          ("SUMMARY generous crossing", SUMMARY, rf"passes it from {N} % squeeze",
           lambda d: d["inversion"]["squeeze_pct_band_high_exceeds_generous_bound"], 0.05),
          ("02_02 §3.2 floor", BLIND_MATE, rf"\*\*{N}–[\d.]+ Н\*\* на підлозі вікна 19 %",
           lambda d: d["band"]["window_floor"]["reaction_N"][0], 0.6),
          ("02_02 §3.2 window top", BLIND_MATE, rf"\*\*[\d.]+–{N} Н\*\* на верху 30 %",
           lambda d: d["band"]["window_top"]["reaction_N"][1], 0.6),
          ("02_02 §3.5 nominal clamp", BLIND_MATE, rf"≈ \*\*{N} Н\*\* на номіналі 24\.5 %",
           lambda d: d["band"]["nominal"]["required_clamp_N_at_band_high"]["after_20_years_ring_never_relaxes"], 0.6),
          ("02_02 §3.5 chain-top clamp", BLIND_MATE, rf"≈ \*\*{N} Н\*\* на верху ланцюга",
           lambda d: d["band"]["chain_high"]["required_clamp_N_at_band_high"]["after_20_years_ring_never_relaxes"], 0.6),
          ("02_02 §4.4 nominal margin", BLIND_MATE, rf"\({N}× навіть без неї\)",
           lambda d: d["band"]["nominal"]["lug_root_margin_x_at_print_floor"]["after_20_years_ring_never_relaxes"], 0.005),
          ("02_02 §4.4 window-top loss by year 2", BLIND_MATE, rf"лише якщо втратить ≈ {N} % уже до 2-го року",
           lambda d: d["band"]["window_top"]["ring_must_have_lost_share_of_R0_by_year"]["2"] * 100, 0.5),
          ("02_02 §4.4 window-top loss by year 5", BLIND_MATE, rf"й ≈ {N} % уже до 5-го \(0\.72×",
           lambda d: d["band"]["window_top"]["ring_must_have_lost_share_of_R0_by_year"]["5"] * 100, 0.5),
          ("SUMMARY window-top loss by year 5", SUMMARY, rf"about {N} % already by year 5; a ring",
           lambda d: d["band"]["window_top"]["ring_must_have_lost_share_of_R0_by_year"]["5"] * 100, 0.5),
          ("02_02 §4.4 window-top wall", BLIND_MATE, rf"до {N} мм на верху вікна \(SF 2",
           lambda d: d["band"]["window_top"]["collar_wall_strength_asks_mm_ring_never_relaxes"], 0.005))],
    # ── HW.34 bus rod: numbers doc homes quote from script 55 ──
    # ⛔ `bus_mechanical.json` had NO pin here at all while five doc homes quoted its SFs verbatim.
    # Every number below moves the moment ANY input of that model moves (µ sweep, geometry, yield
    # table, derates), while the prose around it would stay internally consistent on the old value.
    # ⛔ The axial thermal term entered canon prose the same hour it was derived, which is exactly the
    # shape this file exists against: a number with no owner reads identically to one with an owner.
    (
        "liner differential AXIAL growth at 40 K → bus_mechanical.json §axial_thermal",
        COAXIAL, rf"дає \*\*{N} мкм на 40 К\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["axial_thermal"]["differential_axial_um_by_dT_K"]["40"], 0.5,
    ),
    # ⛔ The pins that stood here for the free-shape stations (min protrusion 0.79 mm · approach 0.60° ·
    # 7.8 µm inside the wall) went with the drift picture on 2026-09-14: those keys are gone from the cache
    # and the doc sentences that carried them now say the numbers are retired. What canon and SUMMARY quote
    # from the equilibrium instead is pinned below — each to the key it is read from, never to a neighbour.
    # ⛔ The cold press-fit pair below entered canon as PROSE with no measurer and stayed that way until
    # 2026-09-24 (00_07 HW.34) — the exact shape this file exists against. Both now read from the cache.
    (
        "cold press-fit normal force at the ratified nominal → bus_mechanical.json §cold_press_fit",
        COAXIAL, rf"\*\*{N} Н\*\* нормальної сили",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["interference_window"]["cold_press_fit"]["rows"]
                       if r["at"] == "ratified_nominal")["normal_force_N"], 1.0,
    ),
    (
        "µ below which cold assembly returns → bus_mechanical.json §cold_press_fit",
        COAXIAL, rf"µ_крит {N}\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["interference_window"]["cold_press_fit"]["rows"]
                       if r["at"] == "ratified_nominal")["mu_crit"], 0.0005,
    ),
    (
        "mouth approach angle per µm of channel offset, shipped branch, shipped geometry → bus_mechanical.json §edge_bearing",
        SUMMARY, rf"the approach angle grows at \*\*{N}°/µm\*\* of offset past the play on the shipped geometry",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["clearance_regime"]["edge_bearing"]["rows"]
                       if r["geometry"].startswith("shipped") and r["branch"].startswith("PEEK liner"))
        ["approach_angle_deg_per_um_past_play"], 0.00005,
    ),
    (
        "mouth approach angle per µm, canon mirror → bus_mechanical.json §edge_bearing",
        COAXIAL, rf"кут росте на \*\*{N}°\*\* на мікрометр зсуву понад люфт на чинній геометрії",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["clearance_regime"]["edge_bearing"]["rows"]
                       if r["geometry"].startswith("shipped") and r["branch"].startswith("PEEK liner"))
        ["approach_angle_deg_per_um_past_play"], 0.00005,
    ),
    (
        "exit landing angle of the touched-down rod, shipped geometry → bus_mechanical.json §edge_bearing.exit_contact",
        SUMMARY, rf"lands on the bore's exit edge at \*\*{N}°\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["edge_bearing"]["exit_contact"][0]["landing_angle_deg_rigid_wall"], 0.0005,
    ),
    # ⛔ The SIGN of this ratio is the finding (the supported column OVERSTATES the rigid-wall end of the coaxial bracket, where the drift
    # picture had it «understated by 40.8 %»), so the number canon and SUMMARY quote is pinned in both.
    (
        "§2 supported column over the rigid-wall end, shipped geometry → bus_mechanical.json §supported_column_vs_equilibrium",
        SUMMARY, rf"OVERSTATES that rigid-wall end ×\*\*{N}\*\* at nominal µ on the shipped geometry",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"][0]["column_over_cap_nominal"], 0.005,
    ),
    (
        "§2 supported column over the coaxial cap, canon mirror → bus_mechanical.json §supported_column_vs_equilibrium",
        COAXIAL, rf"ЗАВИЩУЄ ×\*\*{N}\*\* при номінальному терті на чинній геометрії",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"][0]["column_over_cap_nominal"], 0.005,
    ),
    # ── HW.34 liner↔wire FIT: the interference window canon now carries (derived 2026-09-12) ──
    # ⛔ These three exist because the block's whole point is that its two vendor inputs are ABSENT,
    # so what canon quotes is the model's OWN bound. A bound is the most tempting kind of number to
    # round while editing prose around it, and nothing else would notice: the sentence stays
    # internally consistent either way. The nominal OFFSET is pinned separately from the WIDTH on
    # purpose — they answer different questions (how far the drawing must move ⊥ how much tolerance
    # the pair may spend), and quoting one for the other is the substitution this file exists against.
    (
        "liner↔wire interference window, diametral budget → bus_mechanical.json §interference_window",
        COAXIAL, rf"тобто {N} мкм ДІАМЕТРАЛЬНО на ОБИДВІ деталі",
        "mechanical/bus_mechanical.json",
        lambda d: d["interference_window"]["window_diametral_um"], 0.05,
    ),
    (
        "required nominal interference offset → bus_mechanical.json §interference_window",
        COAXIAL, rf"≈{N} мкм діаметрально на середині вікна",
        "mechanical/bus_mechanical.json",
        lambda d: d["interference_window"]["required_nominal_offset_diametral_um"], 0.05,
    ),
    # ⚖️ 2026-09-18 — the first application of the ratified liner nominal published ONE attribution of the
    # interference (all of it on the bore) and called it «the lower end»; an adversarial read showed the play is
    # set mostly by the WIRE. These two pin the correction where it is quoted, so a revert to the one-sided
    # reading reds here rather than surviving as prose.
    (
        "channel-play sensitivity k → bus_mechanical.json §od_growth_eats_channel_play",
        SUMMARY, rf"with \*\*k = {N}\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: d["interference_window"]["od_growth_eats_channel_play"]["k_od_growth_per_interference"], 0.0005,
    ),
    (
        "wire-carried play at the window ceiling → bus_mechanical.json §od_growth_eats_channel_play",
        SUMMARY, rf"a wire over nominal eats it — \*\*{N} µm\*\* at the ceiling",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["interference_window"]["od_growth_eats_channel_play"]["rows"]
                       if r["at"] == "ceiling (wire carries)")["channel_radial_play_um"], 0.05,
    ),
    (
        "wire-carried play at the window ceiling (canon) → bus_mechanical.json §od_growth_eats_channel_play",
        COAXIAL, rf"а дріт понад номінал — \*\*{N} мкм\*\* на стелі",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["interference_window"]["od_growth_eats_channel_play"]["rows"]
                       if r["at"] == "ceiling (wire carries)")["channel_radial_play_um"], 0.05,
    ),
    (
        "channel play at the window ceiling → bus_mechanical.json §od_growth_eats_channel_play",
        COAXIAL, rf"на стелі вікна люфт {N} мкм",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["interference_window"]["od_growth_eats_channel_play"]["rows"]
                       if r["at"] == "ceiling")["channel_radial_play_um"], 0.05,
    ),
    # ⛔ The weld-seam pins (k 0.554 · span optimism 40.8 % · margin −0.054) stood here until 2026-09-14 and
    # pinned a bound that stood on the drift picture. The seam block carries no k now; what it carries — the
    # root amplitude and mean per regime and geometry — is pinned equal to script 68's table by
    # test_cache_integrity, and 68's table is pinned cell by cell below (_BUS68_COLUMNS). Nothing to add here
    # without duplicating a row that already has an owner.
(
    "liner play-reduction factor → bus_mechanical.json §clearance_regime.play_reduction",
    SUMMARY, rf"`play_reduction\.factor` ≈ {N}×",
    "mechanical/bus_mechanical.json",
    lambda d: d["clearance_regime"]["play_reduction"]["factor"], 0.05,
),
(
    "through-bore slenderness L/D → bus_mechanical.json §clearance_regime.channel",
    SUMMARY, rf"THROUGH bore of `L/D` ≈ {N},",
    "mechanical/bus_mechanical.json",
    lambda d: d["clearance_regime"]["channel"]["aspect_ratio_l_over_d"], 0.05,
),
    # ── HW.34 endurance band: the number the SUMMARY table is READ for ──
    # ⛔ The binding SF at the LOW end is the one the reader acts on — it says a standing conclusion flips.
    # It sits in a table whose rows differ only in a coefficient, so a stale one would read as the live
    # one — the row anchor is therefore load-bearing. (The seam column of that table went with the drift
    # picture on 2026-09-14; the bare-rod sweep is what remains.)
    (
        "endurance band, binding Ta SF at the low end → bus_mechanical.json §endurance_ratio_band",
        SUMMARY, rf"\| \*\*0\.40 \(model, ⚖️ ratified\)\*\* \| \*\*\d / 6\*\* \| \*\*{N}\*\* \|",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["endurance_ratio_band"]["rows"]
                       if r["endurance_over_yield"] == 0.40)["binding_sf_unsupported"], 0.005,
    ),
    # ⛔ The COUNT beside the binding SF is a verdict of its own (5 / 6 on the 23 mm placeholder span, 4 / 6 since HW.26 G1);
    # the row above matches it with `\d` only to anchor, so the count gets its own pin.
    (
        "endurance band, bare ∞-life count at the low end → bus_mechanical.json §endurance_ratio_band",
        SUMMARY, rf"\| \*\*0\.40 \(model, ⚖️ ratified\)\*\* \| \*\*{N} / 6\*\* \|",
        "mechanical/bus_mechanical.json",
        lambda d: len(next(r for r in d["endurance_ratio_band"]["rows"]
                           if r["endurance_over_yield"] == 0.40)["unsupported_infinite_life"]), 0.0,
    ),
    # ── HW.34 wear budget: the two ends SUMMARY quotes from script 55 §wear_budget ──
    # ⛔ Both ends are pinned, not just the headline, and the reason is the finding itself: the SPAN
    # between them IS the message («the tribology does not decide this, our contact geometry does»),
    # so a doc that kept one end current and let the other rot would still read as a bound while
    # having stopped being one. The span ratio is pinned for the same reason — it is the only number
    # in that paragraph a reader ACTS on. The slip CEILING is pinned because the paragraph's third finding
    # is that it is a ceiling and not a kinematic result — a doc that re-typed it as «the slip» would
    # still match the number while losing the claim.
    # ⛔ Each wear end is pinned TWICE — the BOUND over the contact-compliance bracket and the rigid-wall figure —
    # because the table carries both and the defect this guards is the one that stood for an afternoon: a
    # rigid-wall figure quoted without its sign, read downstream as the bound.
    (
        "wear budget, flow-limited end, BOUND → bus_mechanical.json §wear_budget.binding",
        SUMMARY, rf"flow-limited patch[^|]*\| \*\*{N} × 10⁻⁸\*\* mm³/\(N·m\) \|",
        "mechanical/bus_mechanical.json",
        lambda d: min(p["k_bound_edge_mm3_per_Nm"]
                      for p in d["wear_budget"]["binding"]["by_duty_anchor"]) * 1e8, 0.01,
    ),
    (
        "wear budget, flow-limited end, rigid-wall figure → bus_mechanical.json §wear_budget.binding",
        SUMMARY, rf"flow-limited patch[^|]*\| \*\*[\d.]+ × 10⁻⁸\*\* mm³/\(N·m\) \| \*\*{N} × 10⁻⁷\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: min(p["k_rigid_wall_figure_edge_mm3_per_Nm"]
                      for p in d["wear_budget"]["binding"]["by_duty_anchor"]) * 1e7, 0.01,
    ),
    (
        "wear budget, worn-in end, BOUND → bus_mechanical.json §wear_budget.binding",
        SUMMARY, rf"worn in over the whole run[^|]*\| \*\*{N} × 10⁻⁴\*\* mm³/\(N·m\) \|",
        "mechanical/bus_mechanical.json",
        lambda d: min(p["k_bound_conformal_mm3_per_Nm"]
                      for p in d["wear_budget"]["binding"]["by_duty_anchor"]) * 1e4, 0.01,
    ),
    (
        "wear budget, worn-in end, rigid-wall figure → bus_mechanical.json §wear_budget.binding",
        SUMMARY, rf"worn in over the whole run[^|]*\| \*\*[\d.]+ × 10⁻⁴\*\* mm³/\(N·m\) \| \*\*{N} × 10⁻³\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: min(p["k_rigid_wall_figure_conformal_mm3_per_Nm"]
                      for p in d["wear_budget"]["binding"]["by_duty_anchor"]) * 1e3, 0.01,
    ),
    (
        "wear budget, span between the two ends → bus_mechanical.json §wear_budget.binding",
        SUMMARY, rf"budget's span is \*\*{N}×\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: d["wear_budget"]["binding"]["k_span_ratio"], 0.5,
    ),
    (
        "wear budget, rigid-wall out-of-contact rotation per cycle → bus_mechanical.json §wear_budget.binding",
        SUMMARY, rf"the rigid-wall rotation of \*\*{N} µm\*\* per cycle",
        "mechanical/bus_mechanical.json",
        lambda d: d["wear_budget"]["binding"]["out_of_contact_rotation_per_cycle_um_rigid_wall"], 0.005,
    ),
    (
        "wear budget, in-contact sliding at the upper end → bus_mechanical.json §wear_budget.binding",
        SUMMARY, rf"up to the Ti-bore stop: \*\*{N} µm\*\* per cycle",
        "mechanical/bus_mechanical.json",
        lambda d: d["wear_budget"]["binding"]["sliding_in_contact_per_cycle_um_upper"], 0.05,
    ),
    (
        "coaxial root-stress bracket, upper end, canon mirror → bus_mechanical.json §supported_column_vs_equilibrium",
        COAXIAL, rf"дужка \[[\d.]+, \*\*{N}\*\*\] МПа на чинній геометрії",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"][0]["bracket_MPa_worst_mu"][1], 0.05,
    ),
    (
        "coaxial root-stress bracket, lower end, canon mirror → bus_mechanical.json §supported_column_vs_equilibrium",
        COAXIAL, rf"дужка \[{N}, \*\*[\d.]+\*\*\] МПа на чинній геометрії",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"][0]["bracket_MPa_worst_mu"][0], 0.005,
    ),
    # ── HW.43 part references: the table SUMMARY quotes from script 59 ──
    # ⛔ Every bracket is pinned at BOTH ends (same rule as the cycle-budget block below): the numbers here are
    # literature anchors script 59 carries with their sources, and a doc that kept one end while the other drifted
    # would still read as a bracket. Pinned 2026-09-29, when the pad block left 59 (HW.30) and the table was reread.
    (
        "pogo spring, mfr full-stroke life low → contact_endurance_check.json §framing_A",
        SUMMARY, r"mfr full-stroke life ([\d.]+e\d+)[–—-][\d.]+e\d+ cyc",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["pogo_spring"]["framing_A_full_stroke_actuation"]["mfr_rated_life_cycles"][0], 0.5,
    ),
    (
        "pogo spring, mfr full-stroke life high → contact_endurance_check.json §framing_A",
        SUMMARY, r"mfr full-stroke life [\d.]+e\d+[–—-]([\d.]+e\d+) cyc",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["pogo_spring"]["framing_A_full_stroke_actuation"]["mfr_rated_life_cycles"][1], 0.5,
    ),
    (
        "pogo spring, S-N anchor stress (VHCF end) → contact_endurance_check.json §framing_B",
        SUMMARY, rf"S-N anchors {N} MPa→[\d.]+e\d+ cyc",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["pogo_spring"]["framing_B_low_amplitude_stress_fatigue"]["anchor_points_MPa_cycles"][1][0], 0.05,
    ),
    (
        "pogo spring, S-N anchor cycles (VHCF end) → contact_endurance_check.json §framing_B",
        SUMMARY, r"S-N anchors [\d.]+ MPa→([\d.]+e\d+) cyc",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["pogo_spring"]["framing_B_low_amplitude_stress_fatigue"]["anchor_points_MPa_cycles"][1][1], 0.5,
    ),
    (
        "pogo spring, S-N anchor stress (high-stress end) → contact_endurance_check.json §framing_B",
        SUMMARY, rf"/ {N} MPa→[\d.]+e\d+ cyc, no strict VHCF",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["pogo_spring"]["framing_B_low_amplitude_stress_fatigue"]["anchor_points_MPa_cycles"][0][0], 0.05,
    ),
    (
        "pogo spring, S-N anchor cycles (high-stress end) → contact_endurance_check.json §framing_B",
        SUMMARY, r"/ [\d.]+ MPa→([\d.]+e\d+) cyc, no strict VHCF",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["pogo_spring"]["framing_B_low_amplitude_stress_fatigue"]["anchor_points_MPa_cycles"][0][1], 0.5,
    ),
    (
        "PEEK barb, endurance limit low → contact_endurance_check.json §peek_barb_cyclic",
        SUMMARY, rf"endurance limit {N}[–—-][\d.]+ MPa @",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["peek_barb_cyclic"]["endurance_limit_MPa"][0], 0.05,
    ),
    (
        "PEEK barb, endurance limit high → contact_endurance_check.json §peek_barb_cyclic",
        SUMMARY, rf"endurance limit [\d.]+[–—-]{N} MPa @",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["peek_barb_cyclic"]["endurance_limit_MPa"][1], 0.05,
    ),
    (
        "PEEK barb, tested range low → contact_endurance_check.json §peek_barb_cyclic",
        SUMMARY, r"MPa @ ([\d.]+e\d+)[–—-][\d.]+e\d+ cyc \(2 converging",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["peek_barb_cyclic"]["tested_range_cycles"][0], 0.5,
    ),
    (
        "PEEK barb, tested range high → contact_endurance_check.json §peek_barb_cyclic",
        SUMMARY, r"MPa @ [\d.]+e\d+[–—-]([\d.]+e\d+) cyc \(2 converging",
        "mechanical/contact_endurance_check.json",
        lambda d: d["parts"]["peek_barb_cyclic"]["tested_range_cycles"][1], 0.5,
    ),
    # ── HW.43 cycle budget: the bracket SUMMARY and canon quote from script 62 ──
    # ⛔ Both ends of the low reading AND the ceiling are pinned, in both homes. The ceiling is the number the
    # consumers take (55 §wear_budget, 59), and a doc that kept one reading current while the other rotted would
    # still read as a bracket — a bracket with one stale end is a point in disguise, and nothing else would red.
    (
        "cycle budget, low reading floor → wind_duty_cycle.json §budget_cycles_at_low_reading",
        SUMMARY, rf"\*\*{N}–[\d.]+ × 10⁸\*\* cycles at the low reading",
        "mechanical/wind_duty_cycle.json",
        lambda d: d["budget_cycles_at_low_reading"][0] / 1e8, 0.005,
    ),
    (
        "cycle budget, low reading top → wind_duty_cycle.json §budget_cycles_at_low_reading",
        SUMMARY, rf"\*\*[\d.]+–{N} × 10⁸\*\* cycles at the low reading",
        "mechanical/wind_duty_cycle.json",
        lambda d: d["budget_cycles_at_low_reading"][1] / 1e8, 0.005,
    ),
    (
        "cycle budget, ceiling at the high reading → wind_duty_cycle.json §budget_cycles_upper_bound",
        SUMMARY, rf"a ceiling of \*\*{N} × 10⁸\*\* at the high one",
        "mechanical/wind_duty_cycle.json",
        lambda d: d["budget_cycles_upper_bound"] / 1e8, 0.005,
    ),
    (
        "cycle budget, Beaufort-3 N_eff at the ceiling → wind_duty_cycle.json §beaufort_exceedance",
        SUMMARY, rf"N_eff ≤ \*\*{N} × 10⁸\*\* at the frequency ceiling",
        "mechanical/wind_duty_cycle.json",
        lambda d: d["beaufort_exceedance"][0]["n_eff_cycles_upper_bound"] / 1e8, 0.005,
    ),
    (
        "cycle budget (canon 01_02 §2.2), low reading floor → wind_duty_cycle.json",
        METALLURGY, rf"дають \*\*{N}–[\d.]+×10⁸ циклів\*\*",
        "mechanical/wind_duty_cycle.json",
        lambda d: d["budget_cycles_at_low_reading"][0] / 1e8, 0.005,
    ),
    (
        "cycle budget (canon 01_02 §2.2), low reading top → wind_duty_cycle.json",
        METALLURGY, rf"дають \*\*[\d.]+–{N}×10⁸ циклів\*\*",
        "mechanical/wind_duty_cycle.json",
        lambda d: d["budget_cycles_at_low_reading"][1] / 1e8, 0.005,
    ),
    (
        "cycle budget (canon 01_02 §2.2), ceiling → wind_duty_cycle.json",
        METALLURGY, rf"стелю \*\*{N}×10⁸\*\* на верхньому",
        "mechanical/wind_duty_cycle.json",
        lambda d: d["budget_cycles_upper_bound"] / 1e8, 0.005,
    ),
    # ── Accelerated-test equivalence (canon 01_02 §2 «Концепція»), owner = script 51 ──
    # ⛔ The canon block printed «≈ 1 рік» and «≈ 3–5 років» with no owner beside it while script 51
    # already cached the isotherm — and neither end matched the cache. Both ends of both rows are pinned,
    # because a bracket quoted as its middle is exactly how that drift read. It is the 40 °C ISOTHERM,
    # which the protocol itself is since 2026-09-24 (⚖️ founder, 01_02 §2 «Концепція»; the earlier
    # 20–40 °C cycle never had a computed equivalence).
    # EDLC life at the RATIFIED VBAT_OV (HW.37, 02_03 §12.1): a bracket over the vendor voltage coefficient,
    # so all four ends are pinned — the 20-year claim holds at 10 °C only because BOTH ends clear it.
    (
        "EDLC life @ 10 °C, ratified VBAT_OV, conservative → gusak_degradation.json §edlc_endurance_hours",
        "docs/02_03_BQ25570_MPPT_Nano_Power.md", rf"\*\*{N}–[\d.]+ року @ 10 °C\*\*",
        "kinetics/gusak_degradation.json", lambda d: d["edlc_endurance_hours"]["Eaton_KR-5R5H474-R"]["ratified_vbat_ov"]["10.0"]["conservative_yr"], 0.05,
    ),
    (
        "EDLC life @ 10 °C, ratified VBAT_OV, optimistic → gusak_degradation.json §edlc_endurance_hours",
        "docs/02_03_BQ25570_MPPT_Nano_Power.md", rf"\*\*[\d.]+–{N} року @ 10 °C\*\*",
        "kinetics/gusak_degradation.json", lambda d: d["edlc_endurance_hours"]["Eaton_KR-5R5H474-R"]["ratified_vbat_ov"]["10.0"]["optimistic_yr"], 0.05,
    ),
    (
        "EDLC life @ 25 °C, ratified VBAT_OV, conservative → gusak_degradation.json §edlc_endurance_hours",
        "docs/02_03_BQ25570_MPPT_Nano_Power.md", rf"\*\*{N}–[\d.]+ року @ 25 °C\*\*",
        "kinetics/gusak_degradation.json", lambda d: d["edlc_endurance_hours"]["Eaton_KR-5R5H474-R"]["ratified_vbat_ov"]["25.0"]["conservative_yr"], 0.05,
    ),
    (
        "EDLC life @ 25 °C, ratified VBAT_OV, optimistic → gusak_degradation.json §edlc_endurance_hours",
        "docs/02_03_BQ25570_MPPT_Nano_Power.md", rf"\*\*[\d.]+–{N} року @ 25 °C\*\*",
        "kinetics/gusak_degradation.json", lambda d: d["edlc_endurance_hours"]["Eaton_KR-5R5H474-R"]["ratified_vbat_ov"]["25.0"]["optimistic_yr"], 0.05,
    ),
    # EDLC window at the ratified VBAT_OV (HW.37 → HW.42): `02_03 §8` is the window's home and script 63
    # divides it (history: `test_delta_t_aux_power_cache_on_ratified_window`). Both §8 rows are pinned,
    # because they carry two ROLES — VSTOR = charging, post-buck = discharge.
    (
        "EDLC window on VSTOR @ ratified VBAT_OV (canon 02_03 §8 → script 63 premise: re-run 63 on a window change)",
        "docs/02_03_BQ25570_MPPT_Nano_Power.md", rf"\*\*Енергія робочого вікна \(на VSTOR, 3\.4В→VBAT_OV\)\*\* \| \*\*{N} Дж\*\*",
        "kinetics/delta_t_aux_power_sensitivity.json", lambda d: d["constants"]["E_window_vstor_J"], 0.006,
    ),
    (
        "EDLC usable window after buck @ ratified VBAT_OV (canon 02_03 §8 → script 63 premise: re-run 63 on a window change)",
        "docs/02_03_BQ25570_MPPT_Nano_Power.md", rf"\*\*Корисна енергія на VOUT після Buck @ η=0\.88\*\* \| \*\*≈ {N} Дж\*\*",
        "kinetics/delta_t_aux_power_sensitivity.json", lambda d: d["constants"]["E_window_usable_J"], 0.006,
    ),
    (
        "Arrhenius-effective T_field, Ea low end → gusak_degradation.json §arrhenius_field_temperature",
        "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md", rf"вона \*\*{N} / [\d.]+ / [\d.]+ °C\*\*",
        "kinetics/gusak_degradation.json", lambda d: d["arrhenius_field_temperature"]["by_ea"]["0.7"]["t_eff_c"], 0.006,
    ),
    (
        "Arrhenius-effective T_field, Ea high end → gusak_degradation.json §arrhenius_field_temperature",
        "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md", rf"вона \*\*[\d.]+ / [\d.]+ / {N} °C\*\*",
        "kinetics/gusak_degradation.json", lambda d: d["arrhenius_field_temperature"]["by_ea"]["1.0"]["t_eff_c"], 0.006,
    ),
    (
        "break-even Ea for 5 yr at T_eff → gusak_degradation.json §arrhenius_field_temperature",
        "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md", rf"досягаються вже при Ea ≳ \*\*{N} еВ\*\*",
        "kinetics/gusak_degradation.json",
        lambda d: d["arrhenius_field_temperature"]["break_even_ea_ev"]["5_yr_at_12_wk_t_eff"], 0.0006,
    ),
    (
        "foreign-role Ea reading priced in field years → gusak_degradation.json §arrhenius_field_temperature",
        "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md", rf"12 тижнів @ 40 °C ≈ \*\*{N}\*\* року",
        "kinetics/gusak_degradation.json",
        lambda d: d["arrhenius_field_temperature"]["ea_foreign_reading"]["years_12_wk_at_t_eff"], 0.006,
    ),
    (
        "accelerated test, 4 weeks @ 40 °C, Ea low end → gusak_degradation.json §arrhenius_aging",
        METALLURGY, rf"4 тижні @ 40°C ≈ {N}–",
        "kinetics/gusak_degradation.json", lambda d: d["arrhenius_aging"]["0.7"]["4"], 0.05,
    ),
    (
        "accelerated test, 4 weeks @ 40 °C, Ea high end → gusak_degradation.json §arrhenius_aging",
        METALLURGY, rf"4 тижні @ 40°C ≈ [\d.]+–{N} року",
        "kinetics/gusak_degradation.json", lambda d: d["arrhenius_aging"]["1.0"]["4"], 0.05,
    ),
    (
        "accelerated test, 12 weeks @ 40 °C, Ea low end → gusak_degradation.json §arrhenius_aging",
        METALLURGY, rf"12 тижнів @ 40°C ≈ {N}–",
        "kinetics/gusak_degradation.json", lambda d: d["arrhenius_aging"]["0.7"]["12"], 0.05,
    ),
    (
        "accelerated test, 12 weeks @ 40 °C, Ea high end → gusak_degradation.json §arrhenius_aging",
        METALLURGY, rf"12 тижнів @ 40°C ≈ [\d.]+–{N} року",
        "kinetics/gusak_degradation.json", lambda d: d["arrhenius_aging"]["1.0"]["12"], 0.05,
    ),
    # ⛔ The four rows below pin a table whose WHOLE POINT is that the two topologies differ. The
    # defect they exist against is not drift in one number but a SWAP: quoting the sheet factor for
    # a network part is exactly what canon did for three months after the topology was ratified, and
    # every gate stayed green because each number was individually true. Anchoring per-ROW is
    # therefore load-bearing — a check on a bare `0.121` would pass on a table with the rows
    # transposed. (`01_01 §5.5`, owner = script 66.)
    (
        "gyroid SHEET wall / period → gyroid_ligament.json (topology table, row 1)",
        COAXIAL, rf"\| sheet \| {N} \|",
        "mechanical/gyroid_ligament.json",
        lambda d: d["sheet"]["t_median_over_period"], 0.001,
    ),
    (
        "gyroid SHEET min period @ 200 µm floor → gyroid_ligament.json",
        COAXIAL, rf"\| sheet \| [\d.]+ \| {N} µm \|",
        "mechanical/gyroid_ligament.json",
        lambda d: d["floor_inversion"]["sheet"]["slm_default"]["min_period_um"], 1.0,
    ),
    (
        "gyroid NETWORK ligament / period → gyroid_ligament.json (topology table, row 2)",
        COAXIAL, rf"\*\*network\*\* \(відвантажені SKU\) \| \*\*{N}\*\*",
        "mechanical/gyroid_ligament.json",
        lambda d: d["network"]["t_median_over_period"], 0.001,
    ),
    (
        "gyroid NETWORK min period @ 200 µm floor → gyroid_ligament.json",
        COAXIAL, rf"\*\*network\*\* \(відвантажені SKU\) \| \*\*[\d.]+\*\* \| \*\*{N} µm\*\*",
        "mechanical/gyroid_ligament.json",
        lambda d: d["floor_inversion"]["network"]["slm_default"]["min_period_um"], 1.0,
    ),
    # ── HW.3 synthetic sap: the saturation verdict SUMMARY and canon quote from script 67 ──
    # ⛔ These carry a verdict against a recipe canon still specifies. The break-even rows are the ones a
    # reader ACTS on — they say how wrong the chemistry would have to be for the recipe to be preparable,
    # so a stale one reads as a margin that no longer exists.
    (
        "sap SI floor, coin, NEA-selected → sap_recipe_saturation.json (SUMMARY §HW.3 Q1)",
        SUMMARY, rf"\| coin \(pH 4\.5–5\.5, 20–25 °C\) \| \*\*\+{N}\*\* …",
        SAP, lambda d: d["q1_corners"]["per_test"]["coin"]["selected"]["si_whewellite_min"], 0.006,
    ),
    (
        "sap SI floor, accelerated, NEA-selected → sap_recipe_saturation.json (SUMMARY §HW.3 Q1)",
        SUMMARY, rf"\| accelerated \(pH 5\.0–5\.5, 20–40 °C\) \| \*\*\+{N}\*\* …",
        SAP, lambda d: d["q1_corners"]["per_test"]["accelerated"]["selected"]["si_whewellite_min"], 0.006,
    ),
    (
        "sap SI floor, SI-lowest documented reading → sap_recipe_saturation.json (SUMMARY §HW.3 Q1)",
        SUMMARY, rf"\| accelerated \(pH 5\.0–5\.5, 20–40 °C\) \| \*\*\+[\d.]+\*\* … \+[\d.]+ \| \*\*\+{N}\*\* …",
        SAP, lambda d: d["q1_corners"]["per_test"]["accelerated"]["si_lowest_documented"]["si_whewellite_min"], 0.006,
    ),
    (
        "sap break-even whewellite log Ks → sap_recipe_saturation.json (SUMMARY §HW.3 Q1)",
        SUMMARY, rf"log Ks at 25 °C reaches \*\*{N}\*\*",
        SAP, lambda d: min(d["q1_corners"]["break_even_whewellite_log_ks_25c"].values()), 0.006,
    ),
    (
        "sap break-even calcium malate log K° → sap_recipe_saturation.json (SUMMARY §HW.3 Q1)",
        SUMMARY, rf"log K° reaches \*\*{N}\*\* — ",
        SAP, lambda d: min(v["log_k_camal_break_even"]
                           for v in d["q1_corners"]["break_even_calcium_malate"].values()), 0.006,
    ),
    (
        "sap unnamed base, upper end → sap_recipe_saturation.json (SUMMARY §HW.3 Q3)",
        SUMMARY, rf"takes \*\*[\d.]+–{N} mM\*\* of strong base",
        SAP, lambda d: d["prices"]["either_direction"]["base_mM_max"], 0.06,
    ),
    (
        "sap potassium as KOH, upper end → sap_recipe_saturation.json (SUMMARY §HW.3 Q3)",
        SUMMARY, rf"makes K⁺ \*\*[\d.]+–{N} mM\*\*",
        SAP, lambda d: d["prices"]["either_direction"]["potassium_total_mM_max_if_koh"], 0.06,
    ),
    (
        "sap buffer capacity lost by cutting oxalate, upper end → sap_recipe_saturation.json (SUMMARY §HW.3 Q4)",
        SUMMARY, rf"costs \*\*[\d.]+–{N} %\*\* of β",
        SAP, lambda d: d["prices"]["cut_oxalate_keep_calcium"]["buffer_capacity_lost_fraction_range"][1] * 100.0, 0.6,
    ),
    (
        "sap magnesium oxalate at the calcium-cut window edge → sap_recipe_saturation.json (SUMMARY §HW.3 Q4)",
        SUMMARY, rf"oxalate reaches SI \*\*{N}\*\* at the window edge",
        SAP, lambda d: max(g["si_glushinskite_scoping_max"]
                           for rows in d["prices"]["cut_calcium_keep_oxalate"]["glushinskite_scoping_si_at_window_edge"].values()
                           for g in rows), 0.006,
    ),
    # ⛔ The row below is a ratio over the HARD BOUND and it bundles three effects (oxalate spread, the magnesium
    # limit, the malate reading), so its label must not credit it to the malate constant — a review caught exactly
    # that misreading in the tracker. The malate reading's OWN share is the next row, pinned separately.
    (
        "sap window over the hard bound, NEA-selected + Günzel at I = 0, upper end → sap_recipe_saturation.json (SUMMARY §HW.3 Q5)",
        SUMMARY, rf"\| \+ Günzel constants corrected to I = 0 \(derived\) \| ×[\d.]+–{N} \|",
        SAP, lambda d: d["q5_window_over_hard_bound"]["selected_guenzel_i0"][1], 0.006,
    ),
    (
        "sap malate reading's own share over NEA-selected, upper end → sap_recipe_saturation.json (SUMMARY §HW.3 Q5)",
        SUMMARY, rf"the I = 0 constants ×[\d.]+–{N}, while",
        SAP, lambda d: d["q5_malate_reading_over_selected"]["selected_guenzel_i0"][1], 0.006,
    ),
    (
        "sap oxalate-constant spread end to end, upper end → sap_recipe_saturation.json (SUMMARY §HW.3 Q5)",
        SUMMARY, rf"end to end, moves it ×[\d.]+–{N} —",
        SAP, lambda d: d["q5_oxalate_spread_low_end_over_high_end"][1], 0.006,
    ),
    (
        "sap one pH set-point at 4.5 widens the window, upper end → sap_recipe_saturation.json (SUMMARY §HW.3 Q2)",
        SUMMARY, rf"at pH 4\.5\s+×[\d.]+–{N} wider",
        SAP, lambda d: d["q2_window"]["hard_bound_by_single_ph"]["4.5"]["over_both_tests_window"][1], 0.006,
    ),
    (
        "sap hard-bound dominance margin over the documented readings → sap_recipe_saturation.json (SUMMARY §HW.3)",
        SUMMARY, rf"\(margin ≥ {N}\)",
        SAP, lambda d: d["verification"]["hard_bound_min_si_margin_over_every_reading"], 0.0006,
    ),
    (
        "sap largest ionic strength met → sap_recipe_saturation.json (SUMMARY §HW.3 caveats)",
        SUMMARY, rf"largest ionic strength met,\s+{N} mol/L",
        SAP, lambda d: d["activity_model"]["ionic_strength_max_mol_l"], 0.0006,
    ),
    (
        "sap SI floor quoted by canon → sap_recipe_saturation.json (01_02 §2.1)",
        METALLURGY, rf"SI вевеліту \*\*\+{N}…\+[\d.]+\*\* на відібраних NEA константах",
        SAP, lambda d: min(t["selected"]["si_whewellite_min"] for t in d["q1_corners"]["per_test"].values()), 0.006,
    ),
    (
        "sap SI ceiling quoted by canon → sap_recipe_saturation.json (01_02 §2.1)",
        METALLURGY, rf"SI вевеліту \*\*\+[\d.]+…\+{N}\*\* на відібраних NEA константах",
        SAP, lambda d: max(t["selected"]["si_whewellite_max"] for t in d["q1_corners"]["per_test"].values()), 0.006,
    ),
    # ── CHEM.11 (script 69): the four-site claim's instrument, and the numbers that decide a gene freeze ──
    # Two classes of number live in this cache and they need different tolerances. The proxy scores and the
    # geometry are read straight off the AF3 model → deterministic, tight tolerance. Anything downstream of
    # the minimisation inherits pdbfixer's non-deterministic hydrogen placement, so its tolerance is the
    # cache's OWN measured noise floor — quoting a tighter one would pin the noise, not the finding.
    (
        "CHEM.11 Gln71 proxy patch → chem11 (SUMMARY §CHEM.11 table, deterministic)",
        SUMMARY, rf"\| \*\*Gln71\*\* \| \*\*{N}\*\*",
        CHEM11, lambda d: named(d["hotspots"], "site", 71)["patch_apolar_A2"], 0.06,
    ),
    (
        "CHEM.11 Gln200 proxy patch → chem11 (the weakest of the four)",
        SUMMARY, rf"\| \*\*Gln200\*\* \| \*\*{N}\*\*",
        CHEM11, lambda d: named(d["hotspots"], "site", 200)["patch_apolar_A2"], 0.06,
    ),
    (
        "CHEM.11 Gln200 burial → chem11 (the reason it gets no compensation)",
        SUMMARY, rf"\| \*\*Gln200\*\* \| \*\*[\d.]+\*\* \| \*\*{N}\*\*",
        CHEM11, lambda d: named(d["hotspots"], "site", 200)["site_burial"], 0.0006,
    ),
    (
        "CHEM.11 Gln258 distance to the electron path → chem11 (the MET-face refusal)",
        SUMMARY, rf"\*\*{N} Å from the script-28 tunnelling route\*\*",
        CHEM11, lambda d: named(d["hotspots"], "site", 258)["d_electron_path_A"], 0.06,
    ),
    (
        "CHEM.11 protein-wide largest patch → chem11 ('hotspot' is a ranking, not a risk)",
        SUMMARY, rf"a maximum of \*\*{N} Å² at\s+Thr12\*\*",
        CHEM11, lambda d: d["whole_surface_context"]["max_A2"], 0.06,
    ),
    (
        # Deliberately duplicated with the generated table row below, and the point is the OWNER:
        # this one resolves through `recommended`, the generated one through `mutants`. One quantity,
        # two writers in one cache — pinning both is what catches them disagreeing.
        "CHEM.11 Ile401→Ser ΔSASA via `recommended` → chem11 (two owners of one quantity must agree)",
        SUMMARY, rf"\| Gln405 \| \*\*Ile401 → Ser\*\* \| \*\*{N}\*\*",
        CHEM11, lambda d: named(d["recommended"], "mutation", "ILE401SER")["delta_patch_apolar_A2"],
        None,   # resolved to controls.patch_sasa_noise_floor_A2 at run time
    ),
    # The combined sentence is the headline a freeze would be quoted on, so BOTH ends of each
    # "from X to Y" are pinned: a range whose one end rotted still reads as a range.
    (
        "CHEM.11 combined variant, Gln71 reference → chem11 (a freeze is a SEQUENCE)",
        SUMMARY, rf"take Gln71 from {N} to \*\*[\d.]+ Å²\*\*",
        CHEM11, lambda d: d["recommended_set_as_one_sequence"]["per_hotspot"]["Gln71"]["patch_ref_A2"],
        None,
    ),
    (
        "CHEM.11 combined variant, Gln71 result → chem11 (not a sum of singles)",
        SUMMARY, rf"take Gln71 from [\d.]+ to \*\*{N} Å²\*\*",
        CHEM11, lambda d: d["recommended_set_as_one_sequence"]["per_hotspot"]["Gln71"]["patch_combined_A2"],
        None,
    ),
    (
        "CHEM.11 combined variant, Gln405 reference → chem11",
        SUMMARY, rf"and Gln405 from {N} to \*\*[\d.]+ Å²\*\*",
        CHEM11, lambda d: d["recommended_set_as_one_sequence"]["per_hotspot"]["Gln405"]["patch_ref_A2"],
        None,
    ),
    (
        "CHEM.11 combined variant, Gln405 result → chem11",
        SUMMARY, rf"and Gln405 from [\d.]+ to \*\*{N} Å²\*\*",
        CHEM11, lambda d: d["recommended_set_as_one_sequence"]["per_hotspot"]["Gln405"]["patch_combined_A2"],
        None,
    ),
    (
        "CHEM.11 largest non-additivity → chem11 (the reason the set is built, not summed)",
        SUMMARY, rf"against the sum of the singles is \*\*{N} Å²\*\*",
        CHEM11, lambda d: max(abs(v["non_additivity_A2"]) for v in
                              d["recommended_set_as_one_sequence"]["per_hotspot"].values()),
        None,
    ),
    (
        "CHEM.11 Ala201 burial margin → chem11 (Gln200's refusal is OUR threshold's)",
        SUMMARY, rf"a burial of {N} against our declared ceiling",
        CHEM11, lambda d: named(d["threshold_cost_measured"]["entries"], "residue", "ALA201")["burial"],
        0.0006,
    ),
    # L1 §2 is the recipe's home and quotes the four numbers its two refusals turn on. It is a
    # doc target this guard did not read before — the workflow's path lists already cover the
    # whole in_silico protocols subtree, so `test_every_doc_target_triggers_this_guard` stays green.
    (
        "CHEM.11 Gln258 d(e⁻ path) → chem11 (L1 §2 — the keep-out axis, re-labelled 2026-10-15)",
        L1, rf"\*\*{N} Å from the script-28 route",
        CHEM11, lambda d: named(d["hotspots"], "site", 258)["d_electron_path_A"], 0.06,
    ),
    (
        "CHEM.11 Gln258 d(FAD) → chem11 (L1 §2)",
        L1, rf"script-28 route and {N} Å from FAD\*\*",
        CHEM11, lambda d: named(d["hotspots"], "site", 258)["d_cofactor_A"], 0.06,
    ),
    (
        "CHEM.11 Gln200 burial → chem11 (L1 §2 — why Gln200 gets nothing)",
        L1, rf"most buried of the 11\*\* \(burial {N}\)",
        CHEM11, lambda d: named(d["hotspots"], "site", 200)["site_burial"], 0.0006,
    ),
    (
        "CHEM.11 re-selection window, lower end → chem11 (L1 §2 — the claim's whole scope)",
        L1, rf"but only at {N}–[\d.]+ Å",
        CHEM11, lambda d: min(d["provenance"]["reselects_only_within"]), 0.06,
    ),
    (
        "CHEM.11 re-selection window, upper end → chem11 (L1 §2)",
        L1, rf"but only at [\d.]+–{N} Å",
        CHEM11, lambda d: max(d["provenance"]["reselects_only_within"]), 0.06,
    ),
    # ── CHEM.11 conservation (script 70): the numbers that LIFTED the I401S hold ──
    # These decide a gene that gets ORDERED, and until 2026-09-18 they had no measurer in the tree
    # at all (00_07 HW.5.IS). Every one of them is quoted in the L1 §2 conservation block, so every
    # one gets a row here: an unpinned number in that block is the exact shape the port removed.
    (
        "CHEM.11 pool size → conservation (L1 §2 — the denominator of every frequency below)",
        L1, rf"\({N} homologs from [\d.]+ genera",
        CONSERVATION, lambda d: d["selection"]["dedup"]["kept"], 0.6,
    ),
    (
        "CHEM.11 genera count → conservation (L1 §2 — sampling breadth)",
        L1, rf"homologs from {N} genera",
        CONSERVATION, lambda d: d["selection"]["dedup"]["genera"], 0.6,
    ),
    (
        "CHEM.11 Ile401 frequency → conservation (L1 §2 — the residue being replaced)",
        L1, rf"\*\*Ile {N} % · Ser [\d.]+ %\*\*",
        CONSERVATION, lambda d: d["positions"]["401"]["deduped"]["identical_pct"], 0.06,
    ),
    (
        "CHEM.11 Ser401 frequency → conservation (L1 §2 — the residue being put there)",
        L1, rf"\*\*Ile [\d.]+ % · Ser {N} %\*\*",
        CONSERVATION, lambda d: d["positions"]["401"]["deduped"]["ser_pct"], 0.06,
    ),
    (
        "CHEM.11 anchored subset size → conservation (L1 §2 — the reading with an alignment behind it)",
        L1, rf"local window identity ≥ 40 %, n = {N}\)",
        CONSERVATION, lambda d: d["positions"]["401"]["anchored"]["n"], 0.6,
    ),
    (
        "CHEM.11 anchored Ser → conservation (L1 §2)",
        L1, rf"\*\*Ser {N} % vs Ile [\d.]+ %\*\*",
        CONSERVATION, lambda d: d["positions"]["401"]["anchored"]["ser_pct"], 0.06,
    ),
    (
        "CHEM.11 anchored Ile → conservation (L1 §2)",
        L1, rf"\*\*Ser [\d.]+ % vs Ile {N} %\*\*",
        CONSERVATION, lambda d: d["positions"]["401"]["anchored"]["identical_pct"], 0.06,
    ),
    (
        # The instrument's licence to be believed at all — pinned like any other headline.
        "CHEM.11 positive control His537 → conservation (L1 §2 — the instrument's licence)",
        L1, rf"\*\*His537 reads {N} %\*\*",
        CONSERVATION, lambda d: d["positions"]["537"]["deduped"]["identical_pct"], 0.06,
    ),
    (
        "CHEM.11 Ala70 frequency → conservation (L1 §2 — calibration against a ratified position)",
        L1, rf"LESS conserved than Ala70 \({N} %\)",
        CONSERVATION, lambda d: d["positions"]["70"]["deduped"]["identical_pct"], 0.06,
    ),
    (
        "CHEM.11 Leu80 frequency → conservation (L1 §2 — calibration)",
        L1, rf"and Leu80 \({N} %\)",
        CONSERVATION, lambda d: d["positions"]["80"]["deduped"]["identical_pct"], 0.06,
    ),
    (
        "CHEM.11 Asp-at-80 natural frequency → conservation (L1 §2 — what the OTHER ratified swap places)",
        L1, rf"natural frequency at its own position is {N} %",
        CONSERVATION, lambda d: round(100.0 * d["positions"]["80"]["deduped"]["distribution"].get("D", 0)
                                      / d["positions"]["80"]["deduped"]["n"], 1), 0.06,
    ),
    (
        "CHEM.11 external-MSA gap fraction → conservation (L1 §2 — why the column is weak)",
        L1, rf"puts \*\*{N} % gaps\*\* in that column",
        CONSERVATION, lambda d: d["external_msa"]["gap_pct"], 0.06,
    ),
    (
        "CHEM.11 aligner agreement, raw → conservation (L1 §2 — the number a reader would compute)",
        L1, rf"agree per sequence on \*\*{N} %\*\* raw",
        CONSERVATION, lambda d: d["external_msa"]["per_sequence_agreement_pct"], 0.06,
    ),
    (
        "CHEM.11 aligner agreement, conditional → conservation (L1 §2 — the number that means something)",
        L1, rf"\*\*{N} %\*\* once the cells where the external",
        CONSERVATION, lambda d: d["external_msa"]["per_sequence_agreement_where_msa_places_a_residue_pct"], 0.06,
    ),
    (
        "CHEM.11 closest Ser carrier → conservation (L1 §2 — Gnomoniopsis, the fifth-closest homolog)",
        L1, rf"\*Gnomoniopsis smithogilvyi\* \({N} % identity",
        CONSERVATION, lambda d: d["clade_locality"]["ser_carrying_homologs"][0]["identity_to_query_pct"], 0.06,
    ),
    (
        "CHEM.11 weak-anchor 8th carrier → conservation (L1 §2 — why canon says SEVEN species)",
        L1, rf"\*C. kahawae\*, carries Ser at only {N} % identity",
        CONSERVATION, lambda d: min(h["identity_to_query_pct"] for h in d["clade_locality"]["ser_carrying_homologs"]
                                    if h["organism"].startswith("Colletotrichum")), 0.06,
    ),
]

# ── HW.3: the recipe TABLE is script 67's premise, and its window is quoted slot by slot ──
# ⛔ For the recipe rows the direction of truth is INVERTED and the failure message cannot say so: canon is
# the source and the cache mirrors it — a recipe edit without a re-run of 67 leaves Q6 pricing a medium nobody
# specifies any more. Since 2026-09-17 (⚖️ founder) the table is a POINT, so each member and each pH condition is
# pinned on its own; the pre-verdict RANGES are no longer canon and are pinned nowhere — they survive only as the
# premise of Q1–Q5, whose verdict and window the canon note still quotes as the ground of the choice. The window
# is pinned per SLOT, because three levels in one phrase can keep two current.
_RECIPE_LABELS = {"malic": "Яблучна кислота (malic acid)", "kno3": "KNO₃ (NO₃⁻)", "cacl2": "CaCl₂ (Ca²⁺)",
                  "mgso4": "MgSO₄ (Mg²⁺)"}
_Q6_CONDITIONS = (("setpoint", "5\\.75"), ("side_series", "4\\.5"))
_LEVELS = ("0.5", "1", "2")


def _slot(prefix: str, i: int) -> str:
    slots = [r"[\d.]+"] * len(_LEVELS)
    slots[i] = N
    return prefix + " / ".join(slots) + r" µM\*\*"


def _one_window(d, fixed: str, i: int) -> float:
    """The docs quote ONE window for both tests, so this reds (NaN) the moment the two stop sharing it."""
    per = d["q2_window"]["per_scenario"]["hard_bound"]
    coin, accelerated = (per[t][fixed][i]["partner_max_total_uM"] for t in ("coin", "accelerated"))
    return coin if coin == accelerated else float("nan")


CHECKS += [
    (f"01_02 §2.1 recipe {key} (canon → script 67 premise: re-run 67 on a recipe change)",
     METALLURGY, rf"\| {re.escape(label)} \| {N} mM \|",
     SAP, lambda d, k=key: d["q7_revised_point"]["recipe_mM"][k], 0.0)
    for key, label in _RECIPE_LABELS.items()
] + [
    ("01_02 §2.1 pH set-point (canon → script 67 premise: re-run 67 on a recipe change)",
     METALLURGY, rf"\| pH \| \*\*{N}\*\* \(уставка\)",
     SAP, lambda d: d["q7_revised_point"]["conditions"]["setpoint"]["ph"], 0.0),
    ("01_02 §2.1 pH side series (canon → script 67 premise: re-run 67 on a recipe change)",
     METALLURGY, rf"бічна серія \*\*{N}\*\* \(лише ICP-MS",
     SAP, lambda d: d["q7_revised_point"]["conditions"]["side_series"]["ph"], 0.0),
    ("01_02 §2.1 buffer capacity at the set-point → script 67 Q7 (read by 01_03 §3.2, the cathode pH margin)",
     METALLURGY, rf"ємність при уставці \*\*{N}\*\* мМ/pH",
     SAP, lambda d: d["q7_revised_point"]["conditions"]["setpoint"]["buffer_capacity_mM_per_pH_25c"], 0.005),
    ("01_02 §2.1 buffer capacity, side series → script 67 Q7",
     METALLURGY, rf"у бічній серії \*\*{N}\*\* мМ/pH",
     SAP, lambda d: d["q7_revised_point"]["conditions"]["side_series"]["buffer_capacity_mM_per_pH_25c"], 0.005),
] + [
    (f"sap ratified point, {quantity} {end} at pH {ph_re.replace(chr(92), '')} → sap_recipe_saturation.json (01_02 §2.1)",
     METALLURGY, pattern, SAP,
     lambda d, c=cond, q=key, j=j: d["q7_revised_point"]["conditions"][c][q][j], 0.006)
    for cond, ph_re in _Q6_CONDITIONS
    for quantity, key, pattern_of in (
        ("KOH", "base_koh_mM", lambda lo, p: (rf"\*\*{N}–[\d.]+ mM\*\* при pH {p}" if lo
                                             else rf"\*\*[\d.]+–{N} mM\*\* при pH {p}")),
        ("K+ total", "potassium_total_mM", lambda lo, p: (rf"при pH {p} \(K⁺ сумарно \*\*{N}–[\d.]+ mM\*\*\)" if lo
                                                          else rf"при pH {p} \(K⁺ сумарно \*\*[\d.]+–{N} mM\*\*\)")),
    )
    for j, end in enumerate(("low", "high"))
    for pattern in (pattern_of(j == 0, ph_re),)
] + [
    ("sap point of 2026-09-17 (history), buffer capacity at the set-point → sap_recipe_saturation.json (01_02 §2.1)",
     METALLURGY, rf"β ≈ {N} mM на одиницю pH при 5\.75",
     SAP, lambda d: d["q6_point_2026_09_17_superseded"]["conditions"]["setpoint"]["buffer_capacity_mM_per_pH_25c"], 0.006),
    ("sap point of 2026-09-17 (history), strong acid for −0.1 pH → sap_recipe_saturation.json (01_02 §2.1)",
     METALLURGY, rf"pH на 0\.1 зсуває вже ≈ \*\*{N} mM\*\* сильної кислоти",
     SAP, lambda d: d["q6_point_2026_09_17_superseded"]["conditions"]["setpoint"]["strong_acid_mM_lowering_pH_by_0p1_25c"], 0.0006),
] + [
    (f"sap {qkey[:2]} point, {what} → sap_recipe_saturation.json (SUMMARY §HW.3 {qkey[:2].upper()})", SUMMARY, pattern, SAP,
     lambda d, c=cond, q=key, j=j, qk=qkey: d[qk]["conditions"][c][q] if j is None
     else d[qk]["conditions"][c][q][j], tol)
    for qkey, cond, row in (
        ("q6_point_2026_09_17_superseded", "setpoint", r"\| pH 5\.75 \(coin 20–25 °C · accelerated — 40 °C isotherm, ⚖️ 2026-09-24\) \| "),
        ("q6_point_2026_09_17_superseded", "side_series", r"\| pH 4\.5 \(coin side series, 20–25 °C\) \| "),
        ("q7_revised_point", "setpoint", r"\| Q7 · pH 5\.75 \(coin 20–25 °C · accelerated — 40 °C isotherm\) \| "),
        ("q7_revised_point", "side_series", r"\| Q7 · pH 4\.5 \(coin side series, 20–25 °C\) \| "))
    for what, key, j, pattern, tol in (
        (f"{cond} KOH low", "base_koh_mM", 0, row + rf"\*\*{N}–[\d.]+ mM\*\*", 0.006),
        (f"{cond} KOH high", "base_koh_mM", 1, row + rf"\*\*[\d.]+–{N} mM\*\*", 0.006),
        (f"{cond} K+ total high", "potassium_total_mM", 1, row + rf"[^|]+\| [\d.]+–{N} mM \|", 0.006),
        (f"{cond} buffer capacity", "buffer_capacity_mM_per_pH_25c", None, row + rf"(?:[^|]+\| ){{2}}\*\*{N} mM/pH\*\*", 0.006),
        (f"{cond} strong acid for −0.1 pH", "strong_acid_mM_lowering_pH_by_0p1_25c", None,
         row + rf"(?:[^|]+\| ){{3}}{N} mM \|", 0.006),
    )
] + [
    (f"sap Q7 measured trunk-base {ion} {('low', 'high')[j]} → sap_recipe_saturation.json (01_02 §2.1 ⊕ 2026-10-18)",
     METALLURGY, rf"\| {ion_md} \| [^|]+ \| " + (rf"\*\*{N}–[\d.]+\*\* мМ — низ стовбура" if j == 0 else rf"\*\*[\d.]+–{N}\*\* мМ — низ стовбура"),
     SAP, lambda d, k=key, j=j: d["q7_revised_point"]["measured"]["trunk_base_mM"][k][j], tol)
    for ion, ion_md, key, tol in (("K", "K⁺", "k_total", 0.006), ("Ca", "Ca²⁺", "cacl2", 0.006), ("Mg", "Mg²⁺", "mgso4", 0.0006))
    for j in (0, 1)
] + [
    ("sap Q7 malic acid solved (01_02 §2.1 ⊕ 2026-10-18)", METALLURGY, rf"дав виміряний калій \({N} мМ\)",
     SAP, lambda d: d["q7_revised_point"]["recipe_mM"]["malic"], 0.0),
    ("sap Q7 ionic strength at the set-point (01_02 §2.1 ⊕)", METALLURGY, rf"іонна сила \*\*{N}\*\* мМ проти",
     SAP, lambda d: d["q7_revised_point"]["conditions"]["setpoint"]["ionic_strength_mol_l"][1] * 1e3, 0.006),
    ("sap Q6 ionic strength at the set-point (01_02 §2.1 ⊕, the price's other end)", METALLURGY, rf"мМ проти {N}, буфер",
     SAP, lambda d: d["q6_point_2026_09_17_superseded"]["conditions"]["setpoint"]["ionic_strength_mol_l"][1] * 1e3, 0.06),
    ("sap Q7 buffer capacity (01_02 §2.1 ⊕)", METALLURGY, rf"буфер \*\*{N}\*\* мМ/pH проти",
     SAP, lambda d: d["q7_revised_point"]["conditions"]["setpoint"]["buffer_capacity_mM_per_pH_25c"], 0.006),
    ("sap Q7 strong acid for −0.1 pH (01_02 §2.1 ⊕)", METALLURGY, rf"pH на 0\.1 зсуває вже ≈ \*\*{N}\*\* мМ сильної кислоти",
     SAP, lambda d: d["q7_revised_point"]["conditions"]["setpoint"]["strong_acid_mM_lowering_pH_by_0p1_25c"], 0.0006),
    ("sap Q7 against Q6, ionic strength (SUMMARY §HW.3 Q7)", SUMMARY, rf"ionic strength \*\*×{N}\*\*, buffer capacity",
     SAP, lambda d: d["q7_revised_point"]["against_point_2026_09_17_setpoint"]["ionic_strength_ratio"], 0.0005),
    ("sap Q7 against Q6, buffer capacity (SUMMARY §HW.3 Q7)", SUMMARY, rf"buffer capacity \*\*×{N}\*\*, potassium",
     SAP, lambda d: d["q7_revised_point"]["against_point_2026_09_17_setpoint"]["buffer_capacity_ratio"], 0.005),
    ("sap Q7 against Q6, potassium (SUMMARY §HW.3 Q7)", SUMMARY, rf"potassium \*\*×{N}\*\*\. Two things",
     SAP, lambda d: d["q7_revised_point"]["against_point_2026_09_17_setpoint"]["potassium_total_ratio"], 0.005),
] + [
    (f"sap hard-bound window, {fixed} held at {level} mM → sap_recipe_saturation.json ({where})",
     doc_rel, pattern, SAP, lambda d, f=fixed, i=i: _one_window(d, f, i), 0.06)
    for i, level in enumerate(_LEVELS)
    for fixed, doc_rel, where, pattern in (
        ("Ca", SUMMARY, "SUMMARY §HW.3 Q2", rf"\| Ca {re.escape(level)} mM → total oxalate ≤ \| \*\*{N} µM\*\* \|"),
        ("Ox", SUMMARY, "SUMMARY §HW.3 Q2", rf"\| oxalate {re.escape(level)} mM → total Ca ≤ \| \*\*{N} µM\*\* \|"),
        ("Ca", METALLURGY, "01_02 §2.1", _slot(r"щавлева кислота ≤ \*\*", i)),
        ("Ox", METALLURGY, "01_02 §2.1", _slot(r"CaCl₂ ≤ \*\*", i)),
    )
]


# ── CHEM.11: every ΔSASA the SUMMARY §CHEM.11 table prints, row by row ──
# ⛔ The table IS the argument: it shows what each declared threshold refused AND what that refusal would
# have bought in Å². Pinning only the recommended rows would leave the refused ones — the half that decides
# whether a threshold stays where it is — free to rot while still reading as a measurement. Every row's
# tolerance is the cache's own measured noise floor (tol None), because the quantity is downstream of a
# non-deterministic protonation step and cannot honestly be pinned tighter than that.
_CHEM11_ROWS = (
    # (hotspot, mutation label as the table prints it, cache mutation key, WT position, ΔSASA bolded?)
    ("Gln71", "Leu80 → Asp", "LEU80ASP", "LEU80", True),
    ("Gln71", "Leu80 → Ser", "LEU80SER", "LEU80", True),
    ("Gln71", "Ala70 → Ser", "ALA70SER", "ALA70", True),
    ("Gln71", "Ala70 → Asp", "ALA70ASP", "ALA70", False),
    ("Gln405", "Ile401 → Ser", "ILE401SER", "ILE401", True),
    ("Gln405", "Ile401 → Asp", "ILE401ASP", "ILE401", False),
    ("Gln200", "Ala201 → Ser", "ALA201SER", "ALA201", False),
    ("Gln200", "Trp210 → Ser", "TRP210SER", "TRP210", False),
    ("Gln258", "Leu257 → Ser", "LEU257SER", "LEU257", False),
    ("Gln258", "Ala285 → Ser", "ALA285SER", "ALA285", False),
)


def _chem11_candidate(d, hotspot: str, position: str, field: str):
    """A candidate row, found in the hotspot it was collected under."""
    return named(d["candidates"][hotspot], "residue", position)[field]


def _chem11_cell(label: str, bold: bool, skip: int) -> str:
    """Anchor the k-th numeric cell of a table row. `bold` is the ΔSASA column's own emphasis;
    the columns skipped over are matched loosely because their own rows pin them."""
    b = r"\*\*" if bold else ""
    head = rf"\| {b}{re.escape(label)}{b} \| {b}{N}{b} \|" if skip == 0 else \
        rf"\| {b}{re.escape(label)}{b} \|" + r"[^|]*\|" * skip + rf" \*?\*?{N}\*?\*? \|"
    return head


CHECKS += [
    (f"CHEM.11 ΔSASA {mutation} on {hotspot} → chem11 (SUMMARY §CHEM.11 table, Å² column)",
     SUMMARY, rf"\| {hotspot} " + _chem11_cell(label, bold, 0),
     CHEM11,
     lambda d, m=mutation, h=hotspot: named(d["mutants"], "mutation", m)["per_hotspot"][h]["delta_patch_apolar_A2"],
     None)
    for hotspot, label, mutation, position, bold in _CHEM11_ROWS
] + [
    # The burial column is the one that does the REFUSING for Gln200 and Gln258, so it is pinned
    # beside the Å² it refuses. Deterministic (read off the AF3 model) → a tight tolerance.
    (f"CHEM.11 burial of {position} ({hotspot} row) → chem11 (the refusing column)",
     SUMMARY, rf"\| {hotspot} " + _chem11_cell(label, bold, 2),
     CHEM11, lambda d, h=hotspot, p=position: _chem11_candidate(d, h, p, "burial"), 0.0006)
    for hotspot, label, mutation, position, bold in _CHEM11_ROWS
]


# ── HW.34 / HW.23: script 68's table in SUMMARY §HW.34, cell by cell ──
# ⛔ Every cell is pinned because the ROWS are the message: the shipped row is the design figure and the shallow end its
# assembly bound (up to 1.5× apart), so a doc that kept one row current and let the other rot would still read as a
# sweep while having stopped being one. (Until HW.26 G1, 2026-10-12, a placeholder row stood first, an order of
# magnitude off the window — retired with the placeholder.)
_BUS68 = "mechanical/bus_contact_equilibrium.json"
_BUS68_ROWS = (("18 mm — shipped, the whole lock shank", "shipped — the whole lock shank (HW.26 G1)"),
               ("14 mm — lock window shallow end", "lock window, shallow end"))


def _bus68_cell(k: int) -> str:
    return r"[^|]*\|" + r"(?: \*\*[\d.]+\*\* \|)" + "{" + str(k) + "}" + r" \*\*" + N + r"\*\* \|"


_BUS68_COLUMNS = (
    ("drag cap", 0.005, lambda d, g: next(r for r in d["drag_coaxial"] if r["geometry"] == g and r["play"] == "zero interference"
                                          and r["branch"].startswith("PEEK liner"))["by_mu"]["0.5"]["sigma_root_MPa_bonded"]),
    ("offset secant", 0.005, lambda d, g: next(o for o in d["offset_static_shipped_branch"]
                                               if o["geometry"] == g and o["play"] == "zero interference")["secant_MPa_per_um"]),
    ("reversing-drag amplitude", 0.005, lambda d, g: max(r["sigma_amplitude_MPa"] for r in d["reversing_drag_on_offset"] if r["geometry"] == g)),
    ("off-axis pogo", 0.005, lambda d, g: max(p_["sigma_root_MPa"] for p_ in d["pad_moment_at_rod_radius"] if p_["geometry"] == g)),
    # ⛔ The rigid-wall column is the LOWER end of the root stress; without this column the table read as a cap.
    ("upper end (Ti-bore stop) at µ 0.5", 0.05, lambda d, g: next(r for r in d["drag_coaxial"] if r["geometry"] == g and r["play"] == "zero interference"
                                                                    and r["branch"].startswith("PEEK liner"))["by_mu"]["0.5"]["sigma_root_MPa_upper_end"]),
)

CHECKS += [
    (f"bus contact equilibrium, {col} at {doc_row} → bus_contact_equilibrium.json", SUMMARY,
     r"\| " + re.escape(doc_row) + _bus68_cell(k), _BUS68, lambda d, g=geo, fn=fn: fn(d, g), tol)
    for doc_row, geo in _BUS68_ROWS
    for k, (col, tol, fn) in enumerate(_BUS68_COLUMNS)
]

# ── HW.34 / HW.23: script 91 — the exit contact as an elastic layer over the drag CYCLE, SUMMARY §HW.34 ──
# ⛔ Every cell is pinned because the PAIRS are the message: each elastic figure stands beside a rigid wall at the SAME
# edge, and the reading «the compliance lowers the loaded part and deepens the sub-cycle» lives in the difference of two
# columns. A doc that kept one column of a pair current and let the other rot would invert the reading silently.
_LEC = "mechanical/liner_exit_contact.json"
_LEC_ROWS = ("0.05", "0.1", "0.2", "0.3", "0.5")


def _lec_cell(k: int) -> str:
    return r" \|" + r"(?: \*\*-?[\d.]+(?: %)?\*\* \|)" + "{" + str(k) + "}" + r" \*\*" + N + r"(?: %)?\*\* \|"


def _lec_row(d: dict, i: int) -> dict:
    r = float(_LEC_ROWS[i])
    return next(c for c in d["cycle"] if c["r_edge_mm"] == r and c["base"] == "bonded" and c["modulus"] == "short-term")


def _lec_slide(d: dict, i: int) -> dict:
    return next(x for x in d["sliding"] if x["r_edge_mm"] == float(_LEC_ROWS[i]))


_LEC_COLUMNS = (
    ("cycle peak", 0.0005, lambda d, i: _lec_row(d, i)["peak_sigma_MPa"]),
    ("rigid wall at the same edge, touchdown", 0.0005, lambda d, i: _lec_row(d, i)["peak_rigid_touchdown_same_edge_MPa"]),
    ("root at µ 0.5", 0.0005, lambda d, i: _lec_row(d, i)["sigma_at_mu_MPa"]["0.5"]),
    ("rigid wall at µ 0.5", 0.0005, lambda d, i: _lec_row(d, i)["full_drag_rigid_same_edge_MPa"]),
    ("sub-cycle", 0.0005, lambda d, i: _lec_row(d, i)["subcycle_range_MPa"]),
    ("rigid sub-cycle", 0.0005, lambda d, i: _lec_row(d, i)["subcycle_rigid_same_edge_MPa"]),
    ("sliding at µ 0.5", 0.005, lambda d, i: _lec_row(d, i)["slide_per_cycle_um_at_mu_max"]),
    ("the compliance's share of the sliding", 0.05, lambda d, i: 100.0 * _lec_slide(d, i)["compliance_share"]),
    ("edge peak, worst row", 0.05, lambda d, i: max(p["p_max_MPa"] for p in d["patch"] if p["r_edge_mm"] == float(_LEC_ROWS[i]))),
)


def _lec(d: dict, block: str, key: str) -> list:
    return [r[key] for r in d[block]]


def _lec_pad(d: dict) -> dict:
    return max(d["pad_couple"], key=lambda p: p["eccentricity_mm"])


def _lec_fric(d: dict) -> dict:
    return _lec_row(d, 0)["friction_mu_c_max"]


CHECKS += [
    (f"liner exit contact, {col} at r {row} mm → liner_exit_contact.json", SUMMARY,
     r"\| " + re.escape(row) + _lec_cell(k), _LEC, lambda d, i=i, fn=fn: fn(d, i), tol)
    for i, row in enumerate(_LEC_ROWS)
    for k, (col, tol, fn) in enumerate(_LEC_COLUMNS)
] + [
    ("liner exit contact, (A) give — low", SUMMARY, rf"The liner gives \*\*{N}–[\d.]+ µm\*\* at full drag", _LEC,
     lambda d: min(_lec(d, "cycle", "delta_c_um_at_mu_max")), 0.005),
    ("liner exit contact, (A) give — high", SUMMARY, rf"The liner gives \*\*[\d.]+–{N} µm\*\* at full drag", _LEC,
     lambda d: max(_lec(d, "cycle", "delta_c_um_at_mu_max")), 0.005),
    ("liner exit contact, (B) peak — low", SUMMARY, rf"sits at or just after touchdown\*\*: \*\*{N}–[\d.]+\*\* MPa", _LEC,
     lambda d: min(_lec(d, "cycle", "peak_sigma_MPa")), 0.0005),
    ("liner exit contact, (B) peak — high", SUMMARY, rf"sits at or just after touchdown\*\*: \*\*[\d.]+–{N}\*\* MPa", _LEC,
     lambda d: max(_lec(d, "cycle", "peak_sigma_MPa")), 0.0005),
    ("liner exit contact, (B) peak over 68 — low", SUMMARY, rf"MPa, ×\*\*{N}–[\d.]+\*\* of `68`'s figure\. On a rigid", _LEC,
     lambda d: min(_lec(d, "cycle", "peak_over_68_rigid_end")), 0.001),
    ("liner exit contact, (B) peak over 68 — high", SUMMARY, rf"MPa, ×\*\*[\d.]+–{N}\*\* of `68`'s figure\. On a rigid", _LEC,
     lambda d: max(_lec(d, "cycle", "peak_over_68_rigid_end")), 0.001),
    ("liner exit contact, (B) the radius's lift", SUMMARY, rf"the edge radius lifts it by ≤ \*\*{N}\*\* MPa", _LEC,
     lambda d: max(_lec(d, "cycle", "peak_lift_by_radius_over_flush_MPa")), 0.0005),
    ("liner exit contact, (B) the give's lift", SUMMARY, rf"the give lifts it by ≤ \*\*{N}\*\* MPa more", _LEC,
     lambda d: max(_lec(d, "cycle", "peak_lift_by_compliance_MPa")), 0.0005),
    ("liner exit contact, (C) full-drag shift — smallest", SUMMARY, rf"LOWERS the root by \*\*{N}–[\d.]+\*\* MPa", _LEC,
     lambda d: -max(_lec(d, "cycle", "full_drag_shift_by_compliance_MPa")), 0.005),
    ("liner exit contact, (C) full-drag shift — largest", SUMMARY, rf"LOWERS the root by \*\*[\d.]+–{N}\*\* MPa", _LEC,
     lambda d: -min(_lec(d, "cycle", "full_drag_shift_by_compliance_MPa")), 0.005),
    ("liner exit contact, (C) sub-cycle ratio", SUMMARY, rf"up to ×\*\*{N}\*\* of the rigid one", _LEC,
     lambda d: max(r["subcycle_range_MPa"] / r["subcycle_rigid_same_edge_MPa"] for r in d["cycle"]), 0.05),
    ("liner exit contact, (D) exit-wear slope", SUMMARY, rf"the peak climbs ≤ \*\*{N}\*\* MPa per µm of exit wear", _LEC,
     lambda d: d["wear_path"][0]["slope_MPa_per_um_of_exit_wear_conformal_bound"], 0.0005),
    ("liner exit contact, (D) the mouth engages", SUMMARY, rf"until the mouth engages after \*\*{N}\*\* µm", _LEC,
     lambda d: d["wear_path"][0]["mouth_engages_at_exit_wear_um"], 0.5),
    ("liner exit contact, (D) saturation", SUMMARY, rf"the peak SATURATES at \*\*{N}\*\* MPa", _LEC,
     lambda d: d["wear_path"][0]["peak_saturates_at_MPa"], 0.005),
    ("liner exit contact, (D) mouth wear to the upper end", SUMMARY, rf"needs \*\*{N}\*\* µm of MOUTH wear", _LEC,
     lambda d: d["wear_path"][0]["mouth_wear_to_reach_68_upper_end_um"], 0.5),
    ("liner exit contact, (E) area over 55's flow bound — low", SUMMARY, rf"elastic patch is ×\*\*{N}–[\d]+\*\*", _LEC,
     lambda d: d["wear_readings"]["area_over_flow_bound_flush"][0], 0.5),
    ("liner exit contact, (E) area over 55's flow bound — high", SUMMARY, rf"elastic patch is ×\*\*[\d]+–{N}\*\*", _LEC,
     lambda d: d["wear_readings"]["area_over_flow_bound_flush"][1], 0.5),
    ("liner exit contact, (F) sliding vs 55's upper end", SUMMARY, rf"is at most \*\*1/{N}\*\* of `55`'s upper end", _LEC,
     lambda d: d["wear_readings"]["upper_over_slide_flush_min"], 0.5),
    ("liner exit contact, (F) the compliance's share — low", SUMMARY, rf"the compliance carries \*\*{N}–[\d.]+\*\* %", _LEC,
     lambda d: 100.0 * min(_lec(d, "sliding", "compliance_share")), 0.05),
    ("liner exit contact, (F) the compliance's share — high", SUMMARY, rf"the compliance carries \*\*[\d.]+–{N}\*\* %", _LEC,
     lambda d: 100.0 * max(_lec(d, "sliding", "compliance_share")), 0.05),
    ("liner exit contact, (G) pad amplitude", SUMMARY, rf"amplitude \*\*{N}\*\* MPa, exactly the on-axis one", _LEC,
     lambda d: _lec_pad(d)["cycle_amplitude_MPa"], 0.0005),
    ("liner exit contact, (G) pad mean shift", SUMMARY, rf"mean shifted by \*\*{N}\*\* MPa", _LEC,
     lambda d: abs(_lec_pad(d)["cycle_mean_MPa"]), 0.005),
    ("liner exit contact, (G) the exit section", SUMMARY, rf"carries ≈ the couple itself, \*\*{N}\*\* MPa nominal", _LEC,
     lambda d: _lec_pad(d)["exit_section_sigma_from_the_couple_MPa"], 0.05),
    ("liner exit contact, (H) friction loop at r 0.05", SUMMARY, rf"at r 0\.05 mm, \*\*{N}\*\* MPa against", _LEC,
     lambda d: _lec_fric(d)["loop_range_MPa"], 0.005),
    ("liner exit contact, (I) tip at touchdown — low", SUMMARY, rf"already at touchdown \(\*\*{N}–[\d.]+\*\* µm", _LEC,
     lambda d: min(_lec(d, "countersink", "tip_past_bore_line_um_at_touchdown")), 0.05),
    ("liner exit contact, (I) tip at touchdown — high", SUMMARY, rf"already at touchdown \(\*\*[\d.]+–{N}\*\* µm", _LEC,
     lambda d: max(_lec(d, "countersink", "tip_past_bore_line_um_at_touchdown")), 0.05),
    ("liner exit contact, (I) countersink peak — low", SUMMARY, rf"the cycle peak ×\*\*{N}–[\d.]+\*\* of `68`'s figure, the full-drag", _LEC,
     lambda d: min(_lec(d, "countersink", "peak_over_68_rigid_end")), 0.001),
    ("liner exit contact, (I) countersink peak — high", SUMMARY, rf"the cycle peak ×\*\*[\d.]+–{N}\*\* of `68`'s figure, the full-drag", _LEC,
     lambda d: max(_lec(d, "countersink", "peak_over_68_rigid_end")), 0.001),
    ("liner exit contact, (I) reversal depth", SUMMARY, rf"reversing beyond e ≈ \*\*{N}\*\* mm", _LEC,
     lambda d: d["countersink_full_drag_reversal_overhang_mm"], 0.005),
    ("liner exit contact, (I) countersink sub-cycle", SUMMARY, rf"the sub-cycle up to \*\*{N}\*\* MPa", _LEC,
     lambda d: max(_lec(d, "countersink", "subcycle_range_MPa")), 0.005),
    ("liner exit contact, (J) in-layer sharp edge growth", SUMMARY, rf"its peak grows ×\*\*{N}\*\* per halving of the step", _LEC,
     lambda d: d["controls"]["sharp_edge_inside_the_layer"]["growth_per_halving"][0], 0.005),
]

# ── HW.34 / HW.23: script 92 — the mouth under an axis offset, two elastic patches, SUMMARY §HW.34 + 01_01 §1.4 ──
# ⛔ Four tables, four readings a decision stands on: the static peak (what the first draft read), the mouth peak over the
# CYCLE on three shanks framed by the ratified ⌀0.10 (what the entry-radius decision reads), the EXIT peak under the
# offset (what makes the exit radius a floor), and the swing of the root against the wire under the mouth edge (where the
# critical section may move). Every cell of all four is pinned: each draft so far went wrong in exactly one of them.
_LMC = "mechanical/liner_mouth_contact.json"
_LMC_PEAK = r"(?:\*\*[\d.]+\*\* \(×[\d.]+\) \| )"
_LMC_NUM = r"(?:\*\*[−–\-]?[\d.]+\*\* \| )"
_LMC_RADII = (0.05, 0.1, 0.2, 0.3, 0.5)
_LMC_SHIPPED = "shipped — the whole lock shank (HW.26 G1)"


def _lmc_static(d, e, r):
    return next(x for x in d["static"] if x["offset_um"] == e and x["r_in_mm"] == r)


def _lmc_cyc(d, g, e, r):
    return next(x for x in d["cycle_peak"] if x["geometry"] == g and x["offset_um"] == e and x["r_in_mm"] == r)


def _lmc_exit(d, e, r):
    return next(x for x in d["exit_cycle_peak"] if x["offset_um"] == e and x["r_exit_mm"] == r)


def _lmc_sw(d, e):
    return next(w for w in d["rigid_swing"] if w["offset_um"] == e)


_LMC_CYC_ROWS = tuple((lab + rf" \({st} mm\), {e} µm", g, e)
                      for lab, st, g in (("10 mm", 22, "shank 10 mm"), ("14 mm shipped", 18, _LMC_SHIPPED), ("18 mm", 14, "shank 18 mm"))
                      for e in (50, 75, 100))
_LMC_SUM = lambda d: d["summary"]  # noqa: E731
CHECKS += [
    (f"liner mouth contact, static edge peak at {e} µm, r_in {r}", SUMMARY,
     rf"(?m)^\| {e} \| " + _LMC_PEAK + "{" + str(k) + "}" + rf"\*\*{N}\*\* \(×[\d.]+\) \|" + r"(?: \*\*[\d.]+\*\* \(×[\d.]+\) \|)"
     + "{" + str(4 - k) + r"} \*\*[−–\-]?[\d.]+\*\* \|", _LMC,
     lambda d, e=e, r=r: _lmc_static(d, e, r)["mouth"]["p_max_MPa"], 0.051)
    for e in (30, 40, 50, 75, 100) for k, r in enumerate(_LMC_RADII)
] + [
    (f"liner mouth contact, static root {col} at {e} µm", SUMMARY,
     rf"(?m)^\| {e} \| " + _LMC_PEAK + "{5}" + _LMC_NUM + "{" + str(k) + "}" + rf"\*\*{N}\*\* \|", _LMC,
     lambda d, e=e, fn=fn: fn(d, e), tol)
    for e in (30, 40, 50, 75, 100)
    for k, (col, tol, fn) in enumerate((
        ("elastic", 0.0051, lambda d, e: _lmc_static(d, e, 0.2)["sigma_signed_MPa"]),
        ("rigid same edges", 0.0051, lambda d, e: _lmc_static(d, e, 0.2)["rigid_same_edges_sigma_signed_MPa"]),
        ("68 rigid sharp", 0.0, lambda d, e: _lmc_static(d, e, 0.2)["sigma_68_rigid_sharp_MPa"])))
] + [
    (f"liner mouth contact, cycle peak {lab} r_in {r}", SUMMARY,
     rf"(?m)^\| {lab} \| " + _LMC_PEAK + "{" + str(k) + "}" + rf"\*\*{N}\*\* \(×", _LMC,
     lambda d, g=g, e=e, r=r: _lmc_cyc(d, g, e, r)["peak_MPa"], 0.051)
    for lab, g, e in _LMC_CYC_ROWS for k, r in enumerate(_LMC_RADII)
] + [
    (f"liner mouth contact, cycle peak over 1·σ_y {lab} r_in {r}", SUMMARY,
     rf"(?m)^\| {lab} \| " + _LMC_PEAK + "{" + str(k) + "}" + rf"\*\*[\d.]+\*\* \(×{N}\)", _LMC,
     lambda d, g=g, e=e, r=r: _lmc_cyc(d, g, e, r)["peak_over_flow"]["1.0"], 0.0051)
    for lab, g, e in _LMC_CYC_ROWS for k, r in enumerate(_LMC_RADII)
] + [
    (f"liner mouth contact, smallest safe r_in {lab}", SUMMARY, rf"(?m)^\| {lab} \| " + _LMC_PEAK + r"{5}\*\*" + N + r"\*\* mm \|$",
     _LMC, lambda d, g=g, e=e: d["summary"]["smallest_r_in_below_1_sigma_y"][f"{g} / {e} µm"]["smallest_r_in_below_1_sigma_y_mm"], 0.0)
    for lab, g, e in _LMC_CYC_ROWS
] + [
    (f"liner mouth contact, exit cycle peak at {e} µm, r_exit {r}", SUMMARY,
     rf"(?m)^\| {e} \| " + _LMC_PEAK + "{" + str(k) + "}" + rf"\*\*{N}\*\* \(×[\d.]+\) \|" + r"(?: \*\*[\d.]+\*\* \(×[\d.]+\) \|)" + "{" + str(4 - k) + "}$",
     _LMC, lambda d, e=e, r=r: _lmc_exit(d, e, r)["peak_MPa"], 0.051)
    for e in (0, 50) for k, r in enumerate(_LMC_RADII)
] + [
    (f"liner mouth contact, exit over 1·σ_y at {e} µm, r_exit {r}", SUMMARY,
     rf"(?m)^\| {e} \| " + _LMC_PEAK + "{" + str(k) + "}" + rf"\*\*[\d.]+\*\* \(×{N}\) \|" + r"(?: \*\*[\d.]+\*\* \(×[\d.]+\) \|)" + "{" + str(4 - k) + "}$",
     _LMC, lambda d, e=e, r=r: _lmc_exit(d, e, r)["peak_over_flow"]["1.0"], 0.0051)
    for e in (0, 50) for k, r in enumerate(_LMC_RADII)
] + [
    (f"liner mouth contact, swing {col} at {e} µm", SUMMARY,
     rf"(?m)^\| {e} \| " + _LMC_NUM + "{" + str(k) + "}" + rf"\*\*{N}\*\* \|" + r"(?: \*\*[−–\-]?[\d.]+\*\* \|)" + "{" + str(4 - k) + r"} ×\*\*[\d.]+\*\* \|$",
     _LMC, lambda d, e=e, fn=fn: fn(d, e), 0.0051)
    for e in (0, 10, 26, 28, 30, 35, 40, 45, 50, 60, 75, 100)
    for k, (col, fn) in enumerate((
        ("root mean", lambda d, e: _lmc_sw(d, e)["root_mean_amplitude_MPa"][0]),
        ("root swing", lambda d, e: _lmc_sw(d, e)["root_mean_amplitude_MPa"][1]),
        ("ends only", lambda d, e: _lmc_sw(d, e)["ends_only_amplitude_MPa"]),
        ("mouth-section mean", lambda d, e: _lmc_sw(d, e)["mouth_section_mean_amplitude_MPa"][0]),
        ("mouth-section swing", lambda d, e: _lmc_sw(d, e)["mouth_section_mean_amplitude_MPa"][1])))
] + [
    (f"liner mouth contact, swing ratio at {e} µm", SUMMARY, rf"(?m)^\| {e} \| " + _LMC_NUM + r"{5}×\*\*" + N + r"\*\* \|$", _LMC,
     lambda d, e=e: _lmc_sw(d, e)["mouth_over_root_amplitude"], 0.0051)
    for e in (0, 10, 26, 28, 30, 35, 40, 45, 50, 60, 75, 100)
] + [
    (f"liner mouth contact, {lab}", SUMMARY, pat, _LMC, fn, tol)
    for lab, pat, fn, tol in (
        ("no offset = 91 (elastic)", rf"exit row exactly \(\*\*{N}\*\* /", lambda d: d["controls"]["no_offset_vs_91_exit"]["sigma_signed_MPa"][0], 0.0005),
        ("no offset = 91 (rigid)", rf"exactly \(\*\*[\d.]+\*\* / \*\*{N}\*\* MPa", lambda d: d["controls"]["no_offset_vs_91_exit"]["rigid_same_edge_MPa"][0], 0.0005),
        ("exit = 91's edge peaks", rf"at every exit radius \(within \*\*{N}\*\* %\)", lambda d: 100 * d["controls"]["exit_coaxial_vs_91"]["max_rel_diff"], 0.05),
        ("rigid limit", rf"rigid same-edge model to ≤ \*\*{N}\*\* %", lambda d: 100 * d["controls"]["rigid_limit"]["max_rel_diff"], 0.005),
        ("unsolved points", rf"\*\*{N}\*\* of \*\*[\d]+\*\* elastic path points", lambda d: d["summary"]["elastic_points_not_solved"], 0.0),
        ("all points", rf"\*\*[\d]+\*\* of \*\*{N}\*\* elastic path points", lambda d: d["summary"]["elastic_points"], 0.0),
        ("(A) give — low", rf"same edges by \*\*{N}–[\d.]+\*\* % on every row", lambda d: 100 * d["summary"]["give_lowers_root_fraction"][0], 0.05),
        ("(A) give — high", rf"same edges by \*\*[\d.]+–{N}\*\* % on every row", lambda d: 100 * d["summary"]["give_lowers_root_fraction"][1], 0.05),
        ("(B) radius on swing — low", rf"moves by only \*\*{N}…", lambda d: 100 * d["summary"]["entry_radius_raises_root_swing"][0], 0.5),
        ("(B) radius on swing — high", rf"moves by only \*\*[−\-]?[\d.]+…\+{N}\*\* %", lambda d: 100 * d["summary"]["entry_radius_raises_root_swing"][1], 0.5),
        ("(C) cycle over static — low", rf"shipped-shank row \(by \*\*{N}–[\d.]+\*\* %\)", lambda d: 100 * d["summary"]["cycle_over_static_shipped"][0], 0.5),
        ("(C) cycle over static — high", rf"shipped-shank row \(by \*\*[\d.]+–{N}\*\* %\)", lambda d: 100 * d["summary"]["cycle_over_static_shipped"][1], 0.5),
        ("(C) within the tolerance — worst", rf"the worst ×{N}\*\* \(shank 18", lambda d: max(v["worst_over_flow_1"] for k, v in d["summary"]["smallest_r_in_below_1_sigma_y"].items() if k.endswith("/ 50 µm")), 0.0051),
        ("(C) beyond — rows", rf"it passes 1·σ_y on \*\*{N}\*\* rows", lambda d: len(d["summary"]["beyond_tolerance_rows_at_or_above_1_sigma_y"]), 0.0),
        ("(C) beyond — largest", rf"\(the largest ×\*\*{N}\*\*\)", lambda d: d["summary"]["worst_cycle_row"]["peak_over_flow_1"], 0.005),
        ("(C′) exit rise — low", rf"cycle peak is ×\*\*{N}–[\d.]+\*\* the coaxial", lambda d: min(d["summary"]["exit_rise_at_tolerance"].values()), 0.005),
        ("(C′) exit rise — high", rf"cycle peak is ×\*\*[\d.]+–{N}\*\* the coaxial", lambda d: max(d["summary"]["exit_rise_at_tolerance"].values()), 0.005),
        ("(C′) exit at r 0.05", rf"r_exit 0\.05 mm \(×\*\*{N}\*\*\)", lambda d: _lmc_exit(d, 50, 0.05)["peak_over_flow"]["1.0"], 0.005),
        ("(C′) exit floor", rf"smallest swept exit radius that holds there is \*\*{N}\*\* mm", lambda d: d["summary"]["smallest_r_exit_below_1_sigma_y_at_tolerance_mm"], 0.0),
        ("(D) k needed, shipped", rf"needs k ≥ \*\*{N}\*\* \(`86`", lambda d: d["summary"]["versus_86_threshold"]["k_needed_shipped"], 0.00051),
        ("(D) k needed, shanks — low", rf"\*\*{N}–[\d.]+\*\* over the swept shanks", lambda d: min(d["summary"]["versus_86_threshold"]["k_needed_by_shank"].values()), 0.00051),
        ("(D) k needed, shanks — high", rf"\*\*[\d.]+–{N}\*\* over the swept shanks", lambda d: max(d["summary"]["versus_86_threshold"]["k_needed_by_shank"].values()), 0.00051),
        ("(D) midpoint beyond 86 on the 18 mm shank", rf"on the 18 mm shank the cycle midpoint, \*\*{N}\*\* MPa", lambda d: next(z["root_mean_amplitude_MPa"][0] for z in d["shank"] if z["shank_mm"] == 18.0), 0.0051),
        ("(D) static root on the 18 mm shank", rf"MPa \(static \*\*{N}\*\*\), lies beyond", lambda d: next(z["static_sigma_MPa"] for z in d["shank"] if z["shank_mm"] == 18.0), 0.0051),
        ("(D) ends catch", rf"the ends alone catch as little as \*\*{N}\*\* %", lambda d: 100 * (1 - max(d["summary"]["ends_only_understate_amplitude_by"].values())), 0.5),
        ("(D) 68 within", rf"sharp-edge rows sit within \*\*{N}\*\* %", lambda d: 100 * max(abs(v) for v in d["summary"]["sharp_68_over_path_swing"].values()), 0.5),
        ("(D) 86 k", rf"threshold k ≥ \*\*{N}\*\*", lambda d: d["summary"]["versus_86_threshold"]["k_break_even_binding"], 0.00005),
        ("(D) 86 amplitude", rf"\(amplitude \*\*{N}\*\* MPa, the Ti-bore", lambda d: d["summary"]["versus_86_threshold"]["amplitude_MPa_86"], 0.005),
        ("(D) 86 mean", rf"mean \*\*{N}\*\* MPa, the worst play", lambda d: d["summary"]["versus_86_threshold"]["mean_MPa_86"], 0.005),
        ("(D) cycle mean", rf"runs at \*\*{N}\*\* ± ", lambda d: d["summary"]["versus_86_threshold"]["cycle_mean_MPa"], 0.005),
        ("(D) cycle amplitude", rf"runs at \*\*[\d.]+\*\* ± \*\*{N}\*\* MPa", lambda d: d["summary"]["versus_86_threshold"]["cycle_amplitude_MPa"], 0.005),
        ("(E) mouth swing — low", rf"swings ±\*\*{N}–[\d.]+\*\* MPa against", lambda d: d["summary"]["mouth_section_swing_from_50um_MPa"][0], 0.005),
        ("(E) mouth swing — high", rf"swings ±\*\*[\d.]+–{N}\*\* MPa against", lambda d: d["summary"]["mouth_section_swing_from_50um_MPa"][1], 0.005),
        ("(E) root swing — low", rf"against the root's ±\*\*{N}–[\d.]+\*\*", lambda d: d["summary"]["root_swing_from_50um_MPa"][0], 0.005),
        ("(E) root swing — high", rf"against the root's ±\*\*[\d.]+–{N}\*\*", lambda d: d["summary"]["root_swing_from_50um_MPa"][1], 0.005),
        ("(E) crossing", rf"the ratio crosses 1 at \*\*{N}\*\* µm", lambda d: d["summary"]["ratio_above_one_from_um"], 0.0),
        ("(E) peak ratio", rf"peaks at ×\*\*{N}\*\* near 40", lambda d: d["summary"]["mouth_over_root_amplitude_by_offset"][str(d["summary"]["ratio_peak_at_um"])], 0.005),
        ("(E) root dip", rf"the root's swing dips there \(±\*\*{N}\*\*\)", lambda d: _lmc_sw(d, d["summary"]["ratio_peak_at_um"])["root_mean_amplitude_MPa"][1], 0.005),
        ("(F) peak short-term", rf"mouth peak at the drag's ends from \*\*{N}\*\* to", lambda d: next(b for b in d["brackets"] if (b["base"], b["modulus"]) == ("bonded", "short-term"))["mouth_p_max_MPa"], 0.5),
        ("(F) peak relaxed", rf"drag's ends from \*\*[\d.]+\*\* to \*\*{N}\*\* MPa", lambda d: next(b for b in d["brackets"] if (b["base"], b["modulus"]) == ("bonded", "20-yr relaxed"))["mouth_p_max_MPa"], 0.5),
    )
] + [
    (f"liner mouth contact, (G) static root at shank {sh:g} mm", SUMMARY,
     r"the static root at 50 µm is " + r"(?:\*\*[\d.]+\*\* · ){" + str(k) + r"}\*\*" + N + r"\*\*", _LMC,
     lambda d, sh=sh: d["summary"]["static_root_by_shank_MPa"][f"{sh:g}"], 0.005)
    for k, sh in enumerate((10.0, 14.0, 18.0))
] + [
    (f"01_01 · mouth: {lab} → 92", COAXIAL, pat, _LMC, fn, tol)
    for lab, pat, fn, tol in (
        ("give — low", rf"тих самих кромках лише на {N}–[\d.]+ %", lambda d: 100 * d["summary"]["give_lowers_root_fraction"][0], 0.05),
        ("coaxial ratio", rf"хитається менше за корінь \(×{N};", lambda d: d["summary"]["mouth_over_root_amplitude_by_offset"]["0"], 0.005),
        ("saturated ratio", rf"\(×{N}\), навколо середнього протилежного", lambda d: d["summary"]["mouth_over_root_amplitude_by_offset"]["100"], 0.005),
        ("within the tolerance — worst", rf"\(найгірше ×{N}\)\*\*", lambda d: max(v["worst_over_flow_1"] for k, v in d["summary"]["smallest_r_in_below_1_sigma_y"].items() if k.endswith("/ 50 µm")), 0.0051),
        ("86 cycle mean", rf"цикл на відвантаженому хвостовику \({N} ±", lambda d: d["summary"]["versus_86_threshold"]["cycle_mean_MPa"], 0.005),
        ("86 k needed, shipped", rf"потребує `k` ≥ {N} за формулою `86`", lambda d: d["summary"]["versus_86_threshold"]["k_needed_shipped"], 0.00051),
        ("86 mean beyond on 18 mm", rf"середина циклу на хвостовику 18 мм \({N} МПа;", lambda d: next(z["root_mean_amplitude_MPa"][0] for z in d["shank"] if z["shank_mm"] == 18.0), 0.0051),
        ("exit rise — high", rf"у ×[\d.]+–{N} вищий за співвісний", lambda d: max(d["summary"]["exit_rise_at_tolerance"].values()), 0.005),
        ("exit at r 0.05", rf"за r 0\.05 мм \(×{N}\)", lambda d: _lmc_exit(d, 50, 0.05)["peak_over_flow"]["1.0"], 0.005),
        ("exit floor", rf"— {N} мм тримає \(×", lambda d: d["summary"]["smallest_r_exit_below_1_sigma_y_at_tolerance_mm"], 0.0),
    )
]

# ── CHEM.11 conservation: every cell of the SUMMARY table, row by row ──
# The control rows are pinned exactly like the studied ones ON PURPOSE: the control is what licenses
# the whole table, so a control cell that rots unnoticed would leave the instrument's credibility
# resting on a number nothing checks. Deterministic pipeline (no stochastic step), so the tolerance
# is the display digit, never a noise floor.
_CONS_ROWS = (
    # (position, the row label exactly as the table prints it)
    ("401", r"\*\*401\*\* \(compensates Gln405\)"),
    ("70", r"70 \(ratified `A70S`\)"),
    ("80", r"80 \(ratified `L80D`\)"),
    ("201", r"\*\*201\*\* — refused candidate \(Gln200's only lever\)"),
    ("537", r"\*\*537 — positive control\*\*"),
    ("580", r"580 — second control"),
)
_CONS_COLUMNS = (
    # (column label, cells to skip after the query-residue column, resolver)
    ("frequency of the query residue", 1, lambda b: b["deduped"]["identical_pct"]),
    ("Ser %", 2, lambda b: b["deduped"]["ser_pct"]),
    ("anchored n", 3, lambda b: b["anchored"]["n"]),
)

CHECKS += [
    (f"CHEM.11 conservation, pos {pos} — {col} → conservation (SUMMARY table)",
     SUMMARY, r"\| " + label + r" \|" + r"[^|]*\|" * skip + rf" \*?\*?(?:n = )?{N}\s?%?\*?\*? \|",
     CONSERVATION, lambda d, p=pos, fn=fn: fn(d["positions"][p]), 0.6)
    for pos, label in _CONS_ROWS
    for col, skip, fn in _CONS_COLUMNS
] + [
    (f"CHEM.11 conservation, pos {pos} — anchored {what} → conservation (SUMMARY table, last column)",
     SUMMARY, r"\| " + label + r" \|" + r"[^|]*\|" * 4 + rf" \*?\*?{first}{N}{second}\s?%\*?\*? \|",
     CONSERVATION, lambda d, p=pos, k=key: d["positions"][p]["anchored"][k], 0.06)
    for pos, label in _CONS_ROWS
    for what, key, first, second in (
        ("query residue", "identical_pct", "", r" % ⊥ [\d.]+"),
        ("Ser", "ser_pct", r"[\d.]+ % ⊥ ", ""),
    )
]


# ── CHEM.11: the 201 reading in PROSE, not only in the table ──
# ⛔ Separate rows on purpose. The table and the paragraph are two copies, written for two questions,
# and the swipe discipline is that a corrected table reads as a corrected file while the sentence
# beside it keeps the old number. This paragraph is the ARGUMENT of an open founder verdict, so each
# of its numbers is pinned to the cell it came from.
_C201 = lambda d, scope, key: d["positions"]["201"][scope][key]  # noqa: E731
CHECKS += [
    ("CHEM.11 conservation prose · Ala at 201 (deduped) → conservation",
     SUMMARY, rf"\*\*Ala {N} % ⊥ Ser [\d.]+ %\*\*",
     CONSERVATION, lambda d: _C201(d, "deduped", "identical_pct"), 0.06),
    ("CHEM.11 conservation prose · Ser at 201 (deduped) → conservation",
     SUMMARY, rf"\*\*Ala [\d.]+ % ⊥ Ser {N} %\*\*",
     CONSERVATION, lambda d: _C201(d, "deduped", "ser_pct"), 0.06),
    ("CHEM.11 conservation prose · the denominator behind those two → conservation",
     SUMMARY, rf"same {N} homologs",
     CONSERVATION, lambda d: _C201(d, "deduped", "n"), 0.5),
    ("CHEM.11 conservation prose · anchored subset size at 201 → conservation",
     SUMMARY, rf"anchored n = {N}:",
     CONSERVATION, lambda d: _C201(d, "anchored", "n"), 0.5),
    ("CHEM.11 conservation prose · anchored Ala at 201 → conservation",
     SUMMARY, rf"anchored n = [\d.]+: {N} % ⊥",
     CONSERVATION, lambda d: _C201(d, "anchored", "identical_pct"), 0.06),
    ("CHEM.11 conservation prose · anchored Ser at 201 → conservation",
     SUMMARY, rf"anchored n = [\d.]+: [\d.]+ % ⊥ {N} %\)",
     CONSERVATION, lambda d: _C201(d, "anchored", "ser_pct"), 0.06),
    ("CHEM.11 conservation prose · the ratified A70S comparison → conservation (the calibration)",
     SUMMARY, rf"\(\s*{N} % ⊥ [\d.]+ %\) but nowhere near",
     CONSERVATION, lambda d: d["positions"]["70"]["deduped"]["identical_pct"], 0.06),
    ("CHEM.11 conservation prose · the ratified A70S Ser column → conservation",
     SUMMARY, rf"\(\s*[\d.]+ % ⊥ {N} %\) but nowhere near",
     CONSERVATION, lambda d: d["positions"]["70"]["deduped"]["ser_pct"], 0.06),
    ("CHEM.11 conservation prose · His537 control quoted beside 201 → conservation",
     SUMMARY, rf"His537 control's {N} %",
     CONSERVATION, lambda d: d["positions"]["537"]["deduped"]["identical_pct"], 0.06),
]


# ── L4b Monte-Carlo: the CI and the medium it is conditional on ──
# ⛔ Both halves of every row are pinned. The left half is the number people quote; the right half
# is the one that says which medium it belongs to, and a right half free to rot would let the left
# half go back to reading as unconditional — which is exactly the defect this table was built to fix.
MC = "kinetics/monte_carlo.json"
_MC_ROWS = ("Healthy summer", "Active growth", "Cold winter", "Severe stress")


def _mc(d, label: str):
    return next(s for s in d["scenarios"] if s["label"] == label)


# [E.63] A percentile that lands on a sample whose power never beats the sleep drain is `null` in the
# cache and `∞` in the doc — «never gathers a cycle», the canon's own H = ∞. Only the MC cells take it;
# the global `N` stays digits-only, so no other row can quietly start matching an infinity.
NI = rf"([{_DASHES}\-]?[\d.]+|∞)"
_NUM = r"(?:[\d.]+|∞)"


def _inf(v):
    return math.inf if v is None else v


def _mc_ph(d, label: str, key: str, fn):
    row = _mc(d, label)["ph55_bracket"]
    return fn(_inf(row[f][key]) for f in row)


# ⛔ Scenario labels are NOT unique in this file — the deterministic pH table of script `30` carries
# the same four, so an unscoped row pattern matches two tables and the guard reports «ambiguous»
# instead of drifting silently. Every MC row is therefore anchored on ITS OWN table header.
_MC_TABLE = r"90 % CI at pH 5\.5 \(s\)[\s\S]{0,900}?"


def _mc_cell(label: str, skip: int, end: str, bold: bool = False) -> str:
    """One end of a `lo–hi` cell (or a plain cell when `end` is 'only'), inside the MC table."""
    b = r"\*\*" if bold else ""
    body = {"lo": rf"{b}{NI}–{_NUM}{b}", "hi": rf"{b}{_NUM}–{NI}{b}", "only": rf"{b}{NI}{b}"}[end]
    return _MC_TABLE + rf"\| {re.escape(label)} \|" + r"[^|]*\|" * skip + rf" {body} \|"


CHECKS += [
    (f"L4b MC · {lab} · {name} → monte_carlo (the CI and its medium are pinned together)",
     SUMMARY, _mc_cell(lab, skip, end, bold), MC, resolver, 0.06)
    for lab in _MC_ROWS
    for name, skip, end, bold, resolver in (
        ("ceiling CI low", 0, "lo", False, lambda d, sc=lab: _inf(_mc(d, sc)["p5_s"])),
        ("ceiling CI high", 0, "hi", False, lambda d, sc=lab: _inf(_mc(d, sc)["p95_s"])),
        ("ceiling median", 1, "only", False, lambda d, sc=lab: _inf(_mc(d, sc)["median_s"])),
        ("pH5.5 CI low", 2, "lo", True, lambda d, sc=lab: _mc_ph(d, sc, "p5_s", min)),
        ("pH5.5 CI high", 2, "hi", True, lambda d, sc=lab: _mc_ph(d, sc, "p95_s", max)),
        ("pH5.5 median low", 3, "lo", False, lambda d, sc=lab: _inf(_mc(d, sc)["ph55_median_low_s"])),
        ("pH5.5 median high", 3, "hi", False, lambda d, sc=lab: _inf(_mc(d, sc)["ph55_median_high_s"])),
    )
] + [
    (
        "L4b MC · the upper-decile claim in prose → monte_carlo (the sentence that names the cost)",
        SUMMARY, rf"moves from 463 s to about {N} s",
        MC, lambda d: _mc_ph(d, "Healthy summer", "p95_s", max), 0.6,
    ),
    # [E.63] The «never» paragraph: every share and area it quotes, so the ∞ cell cannot keep its
    # explanation while the tail underneath it moves.
    ("L4b MC · never-share, severe stress, pH 5.5 recombinant → monte_carlo",
     SUMMARY, rf"recombinant form leaves {N} % of severe-stress", MC,
     lambda d: _mc(d, "Severe stress")["ph55_bracket"]["rec"]["never_gathers_cycle_pct"], 0.005),
    ("L4b MC · never-share, severe stress, pH 5.5 wild type → monte_carlo",
     SUMMARY, rf"and the wild type {N} %; at the ceiling", MC,
     lambda d: _mc(d, "Severe stress")["ph55_bracket"]["wt"]["never_gathers_cycle_pct"], 0.005),
    ("L4b MC · never-share, severe stress, ceiling → monte_carlo",
     SUMMARY, rf"at the ceiling it is\n{N} % \(`never_gathers_cycle_pct`\)", MC,
     lambda d: _mc(d, "Severe stress")["never_gathers_cycle_pct"], 0.005),
    ("L4b MC · largest «never» area at the ceiling → monte_carlo",
     SUMMARY, rf"every «never» sample has A ≤ {N} cm²", MC,
     lambda d: _mc(d, "Severe stress")["never_max_area_cm2"], 0.005),
    ("L4b MC · largest «never» area at pH 5.5 → monte_carlo",
     SUMMARY, rf"at pH 5\.5 up to {N} cm²", MC,
     lambda d: _mc(d, "Severe stress")["ph55_bracket"]["rec"]["never_max_area_cm2"], 0.005),
]


# ── L3b cathode DET: the k_DET table had SIX documents quoting it and ZERO pins until 2026-09-21 ──
# ⛔ Every cell, not just the convenient ones: the table's message IS the spread, so a half-pinned
# table would keep reading as a bracket while one end rotted. The tolerance is the doc's display
# digit — this pipeline is deterministic (it reads caches and runs no DFT), so no noise floor.
KET = "dft/cathode_ket_lambda.json"
_KET_ROWS = (
    # (row label as SUMMARY prints it, scenario key in the cache)
    (r"canon λ=0\.7 \(old assumption\)", "canon λ=0.7 (old assumption)"),
    (r"\*\*literature λ\*\* \(Cu 2\.0–2\.4 / Co 1\.4 / Ce 1\.0\)", "literature λ"),
    (r"computed λ \(B3LYP, Co\b[^|]*\)", "computed λ (B3LYP)"),
    (r"Co→Ru swap \(computed λ_Ru = 0\.78\)", "Ru-swap (Co→Ru, computed)"),
)
_KET_COLS = (
    ("adverse", 1, "margin_vs_turnover_adverse"),
    ("ΔG=0", 2, "margin_vs_turnover_at_dG0"),
    ("favourable", 3, "margin_vs_turnover_favourable"),
)


def _ket_cell(label: str, skip: int) -> str:
    """The skip-th numeric cell after the row label (0 = the bottleneck column, which is text)."""
    return rf"\| {label} \|" + r"[^|]*\|" * skip + rf" \*?\*?×{NSCI}\*?\*? \|"


def _ket_tol(value: float) -> float:
    """One unit in the doc's last displayed digit — the doc prints two significant figures."""
    return abs(value) * 0.05 + 1e-12


CHECKS += [
    (f"L3b k_DET · {scen} · {col} → cathode_ket_lambda (the table's message IS the spread)",
     SUMMARY, _ket_cell(label, skip),
     KET, lambda d, s=scen, f=field: d["scenarios"][s][f],
     _ket_tol(C(KET)["scenarios"][scen][field]))
    for label, scen in _KET_ROWS
    for col, skip, field in _KET_COLS
] + [
    (
        "L3b k_DET · the measured Cu-Co site-energy gap → cathode_ket_lambda (the bracket's cause)",
        SUMMARY, rf"carried a computed \*\*{N} eV\*\* Cu–Co",
        KET, lambda d: d["driving_force"]["measured_magnitude_eV"]["Cu-Co"], 0.0006,
    ),
    (
        "L3b k_DET · the REFUSED Cu-Ru gap → cathode_ket_lambda (a number that is not a measurement)",
        SUMMARY, rf"script 24d returns {N} eV and \*self-flags it non-physical\*",
        KET, lambda d: d["driving_force"]["ru_node_gap_refused"]["gap_eV_reported"], 0.0006,
    ),
    # 2026-10-15 (Стаття 1 self-review round 1, clusters 1 · 8): §3.4 runs on the FO-DFT coupling and the verdict is
    # conditional on λ(Co) — both brackets, both thresholds and the crude coupling's resolution are the paragraph's claims.
    (
        "L3b k_DET · paper §3.4 lit-λ(Co) adverse end → cathode_ket_lambda (the figure the paper now quotes)",
        PAPER_RESULTS, rf"the bracket is \*\*×{N} to",
        KET, lambda d: d["scenarios"]["literature λ"]["margin_vs_turnover_adverse"], 0.002,
    ),
    (
        "L3b k_DET · paper §3.4 lit-λ(Co) favourable end → cathode_ket_lambda",
        PAPER_RESULTS, rf"the bracket is \*\*×[\d.]+ to ×{N}\*\*",
        KET, lambda d: d["scenarios"]["literature λ"]["margin_vs_turnover_favourable"], 5.0,
    ),
    (
        "L3b k_DET · paper §3.4 computed-λ(Co) adverse end → cathode_ket_lambda",
        PAPER_RESULTS, rf"hop runs at \*\*×{NSCI} to",
        KET, lambda d: d["scenarios"]["computed λ (B3LYP)"]["margin_vs_turnover_adverse"], 1e-6,
    ),
    (
        "L3b k_DET · paper §3.4 computed-λ(Co) favourable end → cathode_ket_lambda",
        PAPER_RESULTS, rf"hop runs at \*\*×\S+ to ×{N}\*\*",
        KET, lambda d: d["scenarios"]["computed λ (B3LYP)"]["margin_vs_turnover_favourable"], 0.006,
    ),
    (
        "L3b k_DET · paper §3.4 computed-λ(Co) at ΔG = 0 → cathode_ket_lambda",
        PAPER_RESULTS, rf"turnover \(×{N} at zero driving force\): below turnover at every corner",
        KET, lambda d: d["scenarios"]["computed λ (B3LYP)"]["margin_vs_turnover_at_dG0"], 0.0002,
    ),
    (
        "L3b k_DET · paper §3.4 λ(Co) threshold at ΔG = 0 → cathode_ket_lambda (the verdict's condition)",
        PAPER_RESULTS, rf"needs \*\*λ\(Co\) ≲ {N} eV\*\*",
        KET, lambda d: d["cobalt_lambda_condition"]["lambda_co_at_turnover_eV"]["fodft|unsourced|dG=0"], 0.05,
    ),
    (
        "L3b k_DET · paper §3.4 λ(Co) threshold at the adverse corner → cathode_ket_lambda",
        PAPER_RESULTS, rf"at the adverse corner\s+\*\*λ\(Co\) ≲ {N} eV\*\*",
        KET, lambda d: d["cobalt_lambda_condition"]["lambda_co_at_turnover_adverse_corner_eV"], 0.05,
    ),
    (
        "L3b k_DET · paper §3.4 crude ΔSCF resolution → cathode_ket_lambda (why the crude t is not used)",
        PAPER_RESULTS, rf"their difference is {N} times the tolerance",
        KET, lambda d: d["dscf_coupling_resolution"]["pairs"]["Cu-Co (T1↔ZIF node)"]["delta_E_over_scf_tol"], 0.05,
    ),
    (
        # 2026-09-24: λ(Cu) became the bracket's SECOND axis — the reading that sets the adverse
        # corner is pinned where the doc names it, so the axis cannot live without an instrument.
        "L3b k_DET · the λ(Cu) Cu(phen)₂ reading → cathode_ket_lambda (the corner's second axis)",
        SUMMARY, rf"gives\n\*\*≈{N} eV for Cu\(phen\)₂²⁺/⁺ self-exchange\*\*",
        KET, lambda d: d["lambda_cu_readings_eV"]["cu_phen2"], 0.05,
    ),
    (
        "L3b k_DET · FO-DFT adverse corner → cathode_ket_lambda",
        SUMMARY, rf"\*\*×{N} at the adverse corner\*\* of the λ\(Cu\) bracket",
        KET, lambda d: d["fodft_cuco_rigor"]["margin_adverse_corner"], 0.002,
    ),
    (
        "L3b k_DET · paper §3.4 site-energy gap → cathode_ket_lambda",
        PAPER_RESULTS, rf"with a \*\*{N} eV\*\* site-energy gap",
        KET, lambda d: d["driving_force"]["measured_magnitude_eV"]["Cu-Co"], 0.0006,
    ),
]


# ── CHEM.11: the ORDERED gene, measured as one sequence (script 69 --ratified) ──
# ⛔ Tight tolerances here, NOT the noise floor: doc and cache come from the SAME run, so every
# number in the SUMMARY table is a verbatim copy. Letting these drift by the floor would let the
# table say something the run did not. The floor itself is pinned as a number, because the whole
# reading ("every ΔΔ is inside it") is an inequality against it.
RATIFIED = "chemistry/chem11_ratified_gene.json"
_RATIFIED_ROWS = ("Gln71", "Gln405", "Gln200", "Gln258")


# The ΔΔ row prints an explicit sign on BOTH directions (`+0.0`, `−0.1`), which `N` does not allow:
# the sign is the message there, so the class is widened rather than the doc flattened.
NS = rf"([+{_DASHES}\-]?[\d.]+)"


def _rat_cell(row_label: str, col: int) -> str:
    """The col-th numeric cell of a named row of the ratified-gene table (0-based)."""
    return rf"\| {re.escape(row_label)} \|" + r"[^|]*\|" * col + rf" \*?\*?{NS}\*?\*? \|"


CHECKS += [
    (f"CHEM.11 ratified table · reference {h} → ratified cache (this run's own reference)",
     SUMMARY, _rat_cell("reference (this run)", i),
     RATIFIED, lambda d, h=h: d["variants"]["ratified"]["per_hotspot"][h]["patch_ref_A2"], 0.06)
    for i, h in enumerate(_RATIFIED_ROWS)
] + [
    (f"CHEM.11 ratified table · ORDERED gene {h} → ratified cache (the sequence the CRO receives)",
     SUMMARY, _rat_cell("**ratified `L80D · A70S · I401S`**", i),
     RATIFIED, lambda d, h=h: d["variants"]["ratified"]["per_hotspot"][h]["patch_variant_A2"], 0.06)
    for i, h in enumerate(_RATIFIED_ROWS)
] + [
    (f"CHEM.11 ratified table · published build {h} → ratified cache (the Ser twin, same sample)",
     SUMMARY, _rat_cell("published build `L80S · A70S · I401S`", i),
     RATIFIED, lambda d, h=h: d["variants"]["published_build"]["per_hotspot"][h]["patch_variant_A2"],
     0.06)
    for i, h in enumerate(_RATIFIED_ROWS)
] + [
    (f"CHEM.11 ratified table · ΔΔ {h} → ratified cache (the row that carries the verdict)",
     SUMMARY, _rat_cell("ratified − published (ΔΔ)", i),
     RATIFIED, lambda d, h=h: d["ratified_vs_published_build"][h]["ratified_minus_published_A2"],
     0.06)
    for i, h in enumerate(_RATIFIED_ROWS)
] + [
    (
        "CHEM.11 ratified · four-replicate floor → ratified cache (the WEAKER of two spread estimates)",
        SUMMARY, rf"this run's \*\*{N} Å²\*\* four-replicate floor",
        RATIFIED, lambda d: d["controls"]["patch_sasa_noise_floor_A2"], 0.005,
    ),
    (
        "CHEM.11 ratified · idle-hotspot spread → ratified cache (the yardstick the verdict uses)",
        SUMMARY, rf"idle pair spreads by up to \*\*{N} Å²\*\*",
        RATIFIED, lambda d: d["spread_estimates"]["idle_hotspot_spread_A2"], 0.06,
    ),
    ("CHEM.11 ratified table · reference surface charge → ratified cache (measured ON the "
     "reference, not inherited from the neutral variant whose number coincides)",
     SUMMARY, _rat_cell("reference (this run)", 4),
     RATIFIED, lambda d: d["controls"]["reference_surface_net_formal_charge"], 0.5),
    (
        "CHEM.11 ratified · surface charge BEFORE the tie's substitution → ratified cache",
        SUMMARY, rf"charge itself \({N} →",
        RATIFIED, lambda d: d["variants"]["published_build"]["surface_net_formal_charge"], 0.5,
    ),
    (
        "CHEM.11 ratified · surface charge of the ORDERED gene → ratified cache (the tie's own axis)",
        SUMMARY, rf"charge itself \([^)]*→ {N}\)",
        RATIFIED, lambda d: d["variants"]["ratified"]["surface_net_formal_charge"], 0.5,
    ),
    # L1 §2 is the sequence OWNER, so the two headline pairs are pinned there too — a reader who
    # opens the owner and not the SUMMARY must see the same run.
    (
        "CHEM.11 ratified · L1 §2 Gln71 reference → ratified cache",
        L1, rf"the Asp build takes \*\*Gln71 {N} →",
        RATIFIED, lambda d: d["variants"]["ratified"]["per_hotspot"]["Gln71"]["patch_ref_A2"], 0.06,
    ),
    (
        "CHEM.11 ratified · L1 §2 Gln71 result → ratified cache",
        L1, rf"the Asp build takes \*\*Gln71 [\d.]+ → {N} Å²\*\*",
        RATIFIED, lambda d: d["variants"]["ratified"]["per_hotspot"]["Gln71"]["patch_variant_A2"],
        0.06,
    ),
    (
        "CHEM.11 ratified · L1 §2 Gln405 reference → ratified cache",
        L1, rf"\*\*Gln405 {N} → [\d.]+ Å²\*\*",
        RATIFIED, lambda d: d["variants"]["ratified"]["per_hotspot"]["Gln405"]["patch_ref_A2"], 0.06,
    ),
    (
        "CHEM.11 ratified · L1 §2 Gln405 result → ratified cache",
        L1, rf"\*\*Gln405 [\d.]+ → {N} Å²\*\*",
        RATIFIED, lambda d: d["variants"]["ratified"]["per_hotspot"]["Gln405"]["patch_variant_A2"],
        0.06,
    ),
    (
        "CHEM.11 ratified · L1 §2 noise floor → ratified cache",
        L1, rf"that run's \*\*{N} Å²\*\*\s+four-replicate floor",
        RATIFIED, lambda d: d["controls"]["patch_sasa_noise_floor_A2"], 0.005,
    ),
    (
        "CHEM.11 ratified · L1 §2 idle-hotspot spread → ratified cache",
        L1, rf"idle pair spreads by up to\s+\*\*{N} Å²\*\*",
        RATIFIED, lambda d: d["spread_estimates"]["idle_hotspot_spread_A2"], 0.06,
    ),
]


# ── HW.37 capsule thermal envelope (script 71) — canon 02_03 §12.1 and SUMMARY §HW.37 ──
# Every number of both tables and of the canon paragraph is pinned: the canon quotes the hot bound, the
# margin a dark finish keeps, the aging temperature and the life at it, and the cold count — and the
# rating ITSELF is a canon premise the cache mirrors (via lib/constants.py), so a canon edit re-runs 71.
POWER = "docs/02_03_BQ25570_MPPT_Nano_Power.md"
THERMAL = "thermal/capsule_envelope.json"


def _hot(case, alpha, field="t_cap_max_c"):
    return lambda d: d["hot_bound"][case][alpha]["0.0"][field]


def _sens(alpha, field="t_cap_max_c"):
    return lambda d: d["hot_bound_h_c_sensitivity"]["sunlit_still_air"][alpha][field]


def _aging_span(prefix, field, pick):
    """min/max over one series of `aging` — T_eff, or a life end (conservative / optimistic)."""
    def resolve(d):
        rows = [r for k, r in d["aging"].items() if k.startswith(prefix)]
        vals = [r["t_eff_c"] if field == "t_eff_c" else r["life_at_ratified_vbat_ov"][field] for r in rows]
        return pick(vals)
    return resolve


CHECKS += [
    ("HW.37 premise · EDLC operating rating (canon 02_03 §12.1 → lib/constants.py → 71's cache)",
     POWER, rf"рейтинг \*\*{N} °C\*\*, нижня межа", THERMAL, lambda d: d["rating_c"]["edlc_operating_max"], 0.05),
    ("HW.37 premise · EDLC operating floor (canon 02_03 §12.1 → lib/constants.py → 71's cache)",
     POWER, rf"нижня межа \*\*{N} °C\*\* — вужчий", THERMAL, lambda d: d["rating_c"]["edlc_operating_min"], 0.05),
    ("HW.37 · 02_03 hottest capsule hour, sunlit α 0.95 still air → capsule_envelope.json",
     POWER, rf"Найгарячіша година за 30 років — \*\*{N} °C\*\*", THERMAL, _hot("sunlit", "0.95"), 0.05),
    ("HW.37 · 02_03 its margin to the rating → capsule_envelope.json",
     POWER, rf"штиль\), запас \*\*{N} K\*\*", THERMAL, _hot("sunlit", "0.95", "margin_to_rating_k"), 0.05),
    ("HW.37 · 02_03 hottest hour at α 0.5 → capsule_envelope.json",
     POWER, rf"при світлому α 0\.5 — \*\*{N} °C\*\*", THERMAL, _hot("sunlit", "0.50"), 0.05),
    ("HW.37 · 02_03 hottest hour without the beam → capsule_envelope.json",
     POWER, rf"без прямого сонця — \*\*{N} °C\*\*", THERMAL, _hot("shaded", "0.95"), 0.05),
    ("HW.37 · 02_03 dark finish with h_c × 0.7 → capsule_envelope.json",
     POWER, rf"на повному сонці дає \*\*{N} °C\*\*", THERMAL, _sens("0.95"), 0.05),
    ("HW.37 · 02_03 its margin → capsule_envelope.json",
     POWER, rf"— запас \*\*{N} K\*\*, тобто порядку похибки", THERMAL, _sens("0.95", "margin_to_rating_k"), 0.05),
    ("HW.37 · 02_03 light finish margin with h_c × 0.7 → capsule_envelope.json",
     POWER, rf"світлий тримає \*\*≥ {N} K\*\*", THERMAL, _sens("0.50", "margin_to_rating_k"), 0.05),
    ("HW.37 · SUMMARY verdict light finish margin with h_c × 0.7 → capsule_envelope.json",
     SUMMARY, rf"a light one keeps ≥ {N} K", THERMAL, _sens("0.50", "margin_to_rating_k"), 0.05),
    ("HW.37 · 02_03 air hours under the EDLC floor → capsule_envelope.json",
     POWER, rf"повітря було нижче −25 °C \*\*{N} години\*\*", THERMAL, lambda d: d["cold_hours_below_edlc_floor"]["hours"], 0.5),
    ("HW.37 · 02_03 coldest air hour → capsule_envelope.json",
     POWER, rf"9 днів, мінімум {N} °C\)", THERMAL, lambda d: d["cold_hours_below_edlc_floor"]["coldest_air_c"], 0.05),
    ("HW.37 · 02_03 aging T_eff in open air → capsule_envelope.json",
     POWER, rf"— \*\*{N} °C\*\* у повітрі", THERMAL, lambda d: d["aging"]["air"]["t_eff_c"], 0.05),
    ("HW.37 · 02_03 aging T_eff shaded, low end → capsule_envelope.json",
     POWER, rf"під радомом \*\*{N}–[\d.]+ °C\*\* у тіні", THERMAL, _aging_span("shaded", "t_eff_c", min), 0.05),
    ("HW.37 · 02_03 aging T_eff shaded, high end → capsule_envelope.json",
     POWER, rf"під радомом \*\*[\d.]+–{N} °C\*\* у тіні", THERMAL, _aging_span("shaded", "t_eff_c", max), 0.05),
    ("HW.37 · 02_03 aging T_eff sunlit, low end → capsule_envelope.json",
     POWER, rf"у тіні й \*\*{N}–[\d.]+ °C\*\* на сонці", THERMAL, _aging_span("sunlit", "t_eff_c", min), 0.05),
    ("HW.37 · 02_03 aging T_eff sunlit, high end → capsule_envelope.json",
     POWER, rf"у тіні й \*\*[\d.]+–{N} °C\*\* на сонці", THERMAL, _aging_span("sunlit", "t_eff_c", max), 0.05),
    ("HW.37 · 02_03 life in open air, conservative → capsule_envelope.json",
     POWER, rf"строк у повітрі — \*\*{N}–[\d.]+ року\*\*", THERMAL,
     lambda d: d["aging"]["air"]["life_at_ratified_vbat_ov"]["conservative_yr"], 0.05),
    ("HW.37 · 02_03 life in open air, optimistic → capsule_envelope.json",
     POWER, rf"строк у повітрі — \*\*[\d.]+–{N} року\*\*", THERMAL,
     lambda d: d["aging"]["air"]["life_at_ratified_vbat_ov"]["optimistic_yr"], 0.05),
    # SUMMARY §HW.37 — both tables, every cell.
    ("HW.37 · SUMMARY sunlit α 0.50 → capsule_envelope.json",
     SUMMARY, rf"\| Sunlit \(the beam reaches the capsule\) \| {N} °C \|", THERMAL, _hot("sunlit", "0.50"), 0.05),
    ("HW.37 · SUMMARY sunlit α 0.95 → capsule_envelope.json",
     SUMMARY, rf"\| Sunlit \(the beam reaches the capsule\) \| [\d.]+ °C \| {N} °C \|", THERMAL, _hot("sunlit", "0.95"), 0.05),
    ("HW.37 · SUMMARY sunlit margin → capsule_envelope.json",
     SUMMARY, rf"\| Sunlit \(the beam reaches the capsule\) \| [\d.]+ °C \| [\d.]+ °C \| {N} K \|", THERMAL,
     _hot("sunlit", "0.95", "margin_to_rating_k"), 0.05),
    ("HW.37 · SUMMARY h_c × 0.7 α 0.50 → capsule_envelope.json",
     SUMMARY, rf"\| Sunlit, h_c × 0\.7 \(the correlation off its home geometry\) \| {N} °C \|", THERMAL, _sens("0.50"), 0.05),
    ("HW.37 · SUMMARY h_c × 0.7 α 0.95 → capsule_envelope.json",
     SUMMARY, rf"\| Sunlit, h_c × 0\.7 \(the correlation off its home geometry\) \| [\d.]+ °C \| {N} °C \|", THERMAL,
     _sens("0.95"), 0.05),
    ("HW.37 · SUMMARY h_c × 0.7 margin → capsule_envelope.json",
     SUMMARY, rf"\| Sunlit, h_c × 0\.7 \(the correlation off its home geometry\) \| [\d.]+ °C \| [\d.]+ °C \| {N} K \|",
     THERMAL, _sens("0.95", "margin_to_rating_k"), 0.05),
    ("HW.37 · SUMMARY shaded α 0.50 → capsule_envelope.json",
     SUMMARY, rf"\| Shaded \(open-sky diffuse only — an upper bound under a crown\) \| {N} °C \|", THERMAL,
     _hot("shaded", "0.50"), 0.05),
    ("HW.37 · SUMMARY shaded α 0.95 → capsule_envelope.json",
     SUMMARY, rf"\| Shaded \(open-sky diffuse only — an upper bound under a crown\) \| [\d.]+ °C \| {N} °C \|", THERMAL,
     _hot("shaded", "0.95"), 0.05),
    ("HW.37 · SUMMARY shaded margin → capsule_envelope.json",
     SUMMARY, rf"\| Shaded \(open-sky diffuse only — an upper bound under a crown\) \| [\d.]+ °C \| [\d.]+ °C \| {N} K \|",
     THERMAL, _hot("shaded", "0.95", "margin_to_rating_k"), 0.05),
    ("HW.37 · SUMMARY open-air T_eff → capsule_envelope.json",
     SUMMARY, rf"\| Open air \| {N} °C \|", THERMAL, lambda d: d["aging"]["air"]["t_eff_c"], 0.05),
    ("HW.37 · SUMMARY open-air life, conservative → capsule_envelope.json",
     SUMMARY, rf"\| Open air \| [\d.]+ °C \| {N}–[\d.]+ yr \|", THERMAL,
     lambda d: d["aging"]["air"]["life_at_ratified_vbat_ov"]["conservative_yr"], 0.05),
    ("HW.37 · SUMMARY open-air life, optimistic → capsule_envelope.json",
     SUMMARY, rf"\| Open air \| [\d.]+ °C \| [\d.]+–{N} yr \|", THERMAL,
     lambda d: d["aging"]["air"]["life_at_ratified_vbat_ov"]["optimistic_yr"], 0.05),
    # [E.63] L4's cycle cost and sleep drain are canon PREMISES the cache mirrors (via lib/constants.py):
    # a chain that moves (a CCM-era frame, a new term in §9.4) must re-run 30/30b, not leave L4 on the
    # old price. Anchored on Scenario C's own lines, so §9.4's +22 dBm point cannot match by accident.
    ("E.63 premise · node cycle cost (canon 02_03 §9.6 Scenario C → lib/constants.py → 30's cache)",
     POWER, rf"H = E_active / \(E_gen − E_sleep\) = {N} / \([\d.]+ − 15\.04\)",
     "kinetics/delta_t_lookup.json", lambda d: d["parameters"]["E_cycle_mJ"], 0.005),
    ("E.63 premise · node sleep drain from VSTOR (canon 02_03 §9.6 Scenario C → lib/constants.py → 30's cache)",
     POWER, rf"E_sleep_supercap\s+= {N} × 3600 = 15\.04", "kinetics/delta_t_lookup.json",
     lambda d: d["parameters"]["P_sleep_VSTOR_uW"], 0.005),
]
_SERIES = {"shaded": r"Under the radome, shaded \(α 0\.50/0\.95 × k 0/0\.1\)",
           "sunlit": r"Under the radome, sunlit \(α 0\.50/0\.95 × k 0/0\.1\)"}
for _case, _label in _SERIES.items():
    CHECKS += [
        (f"HW.37 · SUMMARY {_case} T_eff low end → capsule_envelope.json",
         SUMMARY, rf"\| {_label} \| {N}–[\d.]+ °C \|", THERMAL, _aging_span(_case, "t_eff_c", min), 0.05),
        (f"HW.37 · SUMMARY {_case} T_eff high end → capsule_envelope.json",
         SUMMARY, rf"\| {_label} \| [\d.]+–{N} °C \|", THERMAL, _aging_span(_case, "t_eff_c", max), 0.05),
        (f"HW.37 · SUMMARY {_case} life, conservative low end → capsule_envelope.json",
         SUMMARY, rf"\| {_label} \| [\d.]+–[\d.]+ °C \| {N}–[\d.]+ yr \|", THERMAL,
         _aging_span(_case, "conservative_yr", min), 0.05),
        (f"HW.37 · SUMMARY {_case} life, optimistic high end → capsule_envelope.json",
         SUMMARY, rf"\| {_label} \| [\d.]+–[\d.]+ °C \| [\d.]+–{N} yr \|", THERMAL,
         _aging_span(_case, "optimistic_yr", max), 0.05),
    ]
CHECKS += [
    ("HW.37 · SUMMARY air hours under the floor → capsule_envelope.json",
     SUMMARY, rf"below the −25 °C floor for {N} hours in 30 years", THERMAL,
     lambda d: d["cold_hours_below_edlc_floor"]["hours"], 0.5),
    ("HW.37 · SUMMARY coldest air hour → capsule_envelope.json",
     SUMMARY, rf"9 days, coldest {N} °C\)", THERMAL, lambda d: d["cold_hours_below_edlc_floor"]["coldest_air_c"], 0.05),
]

# 81 (HW.37, the cold edge with the sky): its canon sentence in 02_03 §12.1, its SUMMARY section and table, and the
# ⊕ it adds to the quartz verdict in 02_02 §3.4 all quote this cache — the table cell by cell, generated below.
COLD = "thermal/capsule_cold_edge_sky.json"
_DAYS = r"(?:день|дні|днів)"


def _cold_run(regime, k, field):
    return lambda d: d["runs"][regime][k][field]


def _cold_edge(edge, field):
    return lambda d: d["edges"][edge][field]


def _cold_sky(*path):
    def resolve(d):
        node = d["sky_on_cold_days"]
        for key in path:
            node = node[key]
        return node
    return resolve


CHECKS += [
    ("HW.37 · 02_03 capsule hours under the floor, shallow edge → capsule_cold_edge_sky.json",
     POWER, rf"капсула лежить нижче −25 °C від \*\*{N} год\*\*", COLD, _cold_edge("shallow", "hours_below_floor"), 0.5),
    ("HW.37 · 02_03 its days → capsule_cold_edge_sky.json",
     POWER, rf"від \*\*\d+ год\*\* \({N} {_DAYS}; хмарно", COLD, _cold_edge("shallow", "days_below_floor"), 0.5),
    ("HW.37 · 02_03 capsule hours under the floor, deep edge → capsule_cold_edge_sky.json",
     POWER, rf"до \*\*{N} год\*\* \(\d+ {_DAYS}; ясно", COLD, _cold_edge("deep", "hours_below_floor"), 0.5),
    ("HW.37 · 02_03 its days → capsule_cold_edge_sky.json",
     POWER, rf"до \*\*\d+ год\*\* \({N} {_DAYS}; ясно", COLD, _cold_edge("deep", "days_below_floor"), 0.5),
    ("HW.37 · 02_03 clear sky, k 0.1, diffuse sun → capsule_cold_edge_sky.json",
     POWER, rf"з вітром `k` = 0\.1 — \*\*{N}–\d+ год\*\*", COLD,
     _cold_run("clear_diffuse_sun", "k=0.1", "hours_below_floor"), 0.5),
    ("HW.37 · 02_03 clear sky, k 0.1, no sun → capsule_cold_edge_sky.json",
     POWER, rf"з вітром `k` = 0\.1 — \*\*\d+–{N} год\*\*", COLD, _cold_run("clear_no_sun", "k=0.1", "hours_below_floor"), 0.5),
    ("HW.37 · 02_03 longest spell under the floor → capsule_cold_edge_sky.json",
     POWER, rf"відрізок — до \*\*{N} год\*\*", COLD, lambda d: d["edges"]["longest_spell_below_floor_h"], 0.5),
    ("HW.37 · 02_03 coldest capsule hour → capsule_cold_edge_sky.json",
     POWER, rf"найхолодніша година — \*\*{N} °C\*\*", COLD, lambda d: d["edges"]["coldest_c"], 0.05),
    ("HW.37 · 02_03 sunshine share on the floor days → capsule_cold_edge_sky.json",
     POWER, rf"сонячні \*\*{N}\*\* світлових годин", COLD, _cold_sky("days_with_air_min_below", "-25", "sunshine_share"), 0.005),
    ("HW.37 · 02_03 sunshine share, whole winter → capsule_cold_edge_sky.json",
     POWER, rf"проти \*\*{N}\*\* для всієї зими", COLD, _cold_sky("all_winter_days", "sunshine_share"), 0.005),
    ("HW.37 · 02_03 wind under the floor → capsule_cold_edge_sky.json",
     POWER, rf"медіана вітру на 10 м \*\*{N} м/с\*\*", COLD, _cold_sky("u10_median_m_s", "hours_air_below_floor"), 0.05),
    ("HW.37 · 02_03 wind, whole winter → capsule_cold_edge_sky.json",
     POWER, rf"м/с\*\* проти \*\*{N}\*\* для зими", COLD, _cold_sky("u10_median_m_s", "all_winter_hours"), 0.05),
    ("HW.37 · SUMMARY 81 sunshine share on the floor days → capsule_cold_edge_sky.json",
     SUMMARY, rf"{N} of the daylight hours are sunny", COLD, _cold_sky("days_with_air_min_below", "-25", "sunshine_share"), 0.005),
    ("HW.37 · SUMMARY 81 sunshine share, whole winter → capsule_cold_edge_sky.json",
     SUMMARY, rf"the WMO threshold\) against {N} for every\s+winter day", COLD, _cold_sky("all_winter_days", "sunshine_share"), 0.005),
    ("HW.37 · SUMMARY 81 wind under the floor → capsule_cold_edge_sky.json",
     SUMMARY, rf"has a median of\s+{N} m/s against", COLD, _cold_sky("u10_median_m_s", "hours_air_below_floor"), 0.05),
    ("HW.37 · SUMMARY 81 wind, whole winter → capsule_cold_edge_sky.json",
     SUMMARY, rf"m/s against {N} m/s for every winter hour", COLD, _cold_sky("u10_median_m_s", "all_winter_hours"), 0.05),
    ("HW.37 · SUMMARY 81 verdict, shallow hours → capsule_cold_edge_sky.json",
     SUMMARY, rf"spends between {N} h \(\d+ days\)", COLD, _cold_edge("shallow", "hours_below_floor"), 0.5),
    ("HW.37 · SUMMARY 81 verdict, shallow days → capsule_cold_edge_sky.json",
     SUMMARY, rf"spends between \d+ h \({N} days\)", COLD, _cold_edge("shallow", "days_below_floor"), 0.5),
    ("HW.37 · SUMMARY 81 verdict, deep hours → capsule_cold_edge_sky.json",
     SUMMARY, rf"and {N} h \(\d+ days\) in 30 years", COLD, _cold_edge("deep", "hours_below_floor"), 0.5),
    ("HW.37 · SUMMARY 81 verdict, deep days → capsule_cold_edge_sky.json",
     SUMMARY, rf"and \d+ h \({N} days\) in 30 years", COLD, _cold_edge("deep", "days_below_floor"), 0.5),
    ("HW.37 · SUMMARY 81 verdict, the air's hours → capsule_cold_edge_sky.json",
     SUMMARY, rf"against the air's {N} h;", COLD, lambda d: d["air"]["hours_below_floor"], 0.5),
    ("HW.37 · SUMMARY 81 verdict, longest spell → capsule_cold_edge_sky.json",
     SUMMARY, rf"the longest spell below it is up to {N} h", COLD, lambda d: d["edges"]["longest_spell_below_floor_h"], 0.5),
    ("HW.37 · SUMMARY 81 verdict, coldest capsule hour → capsule_cold_edge_sky.json",
     SUMMARY, rf"the coldest capsule hour {N} °C;", COLD, lambda d: d["edges"]["coldest_c"], 0.05),
    ("HW.37 · 02_02 §3.2 ⚠️ on the HNBR fallback, coldest capsule hour → capsule_cold_edge_sky.json",
     "docs/02_02_Blind_Mate_Pogo_Pin_Interface.md", rf"холоднішає до {N} °C \(`81`, нижня межа моделі", COLD,
     lambda d: d["edges"]["coldest_c"], 0.05),
    ("HW.37 · 02_02 §3.4 ⊕ to the quartz verdict, coldest capsule hour → capsule_cold_edge_sky.json",
     "docs/02_02_Blind_Mate_Pogo_Pin_Interface.md", rf"найхолодніша \*\*{N} °C\*\* \(ясно щогодини", COLD,
     lambda d: d["edges"]["coldest_c"], 0.05),
]
_COLD_ROWS = {"clear_no_sun": "Clear sky, no sun", "clear_diffuse_sun": "Clear sky, diffuse sun",
              "overcast_no_sun": "Overcast, no sun — the air itself", "overcast_diffuse_sun": "Overcast, diffuse sun"}
for _regime, _label in _COLD_ROWS.items():
    for _col, _k in enumerate(("k=0.0", "k=0.1", "k=0.3")):
        _cell = rf"\| {re.escape(_label)} \|" + r" [^|]+ \|" * _col
        CHECKS += [
            (f"HW.37 · SUMMARY 81 table {_regime} {_k} hours → capsule_cold_edge_sky.json",
             SUMMARY, _cell + rf" {N} h \(", COLD, _cold_run(_regime, _k, "hours_below_floor"), 0.5),
            (f"HW.37 · SUMMARY 81 table {_regime} {_k} days → capsule_cold_edge_sky.json",
             SUMMARY, _cell + rf" \d+ h \({N} d · ", COLD, _cold_run(_regime, _k, "days_below_floor"), 0.5),
            (f"HW.37 · SUMMARY 81 table {_regime} {_k} longest spell → capsule_cold_edge_sky.json",
             SUMMARY, _cell + rf" \d+ h \(\d+ d · {N} h\)", COLD, _cold_run(_regime, _k, "longest_spell_below_floor_h"), 0.5),
        ]

# 82 (HW.33, the collar's running clearance): the ⊕ in 02_02 §4.4 and the SUMMARY section quote this cache.
COLLAR = "mechanical/collar_running_clearance.json"
HW_POGO = "docs/02_02_Blind_Mate_Pogo_Pin_Interface.md"


def _collar_th(key):
    return lambda d: d["thermal_closing_mm"][key] * 1000.0


def _collar_row(i, field):
    return lambda d: d["routes"][i][field]


CHECKS += [
    ("HW.33 · 02_02 §4.4 interface Ø → collar_running_clearance.json",
     HW_POGO, rf"смуги сокета на Ø{N}, тож", COLLAR, lambda d: d["interface"]["diameter_mm"], 0.05),
    ("HW.33 · 02_02 §4.4 floor, isothermal at the requirement → collar_running_clearance.json",
     HW_POGO, rf"Фізична підлога — \*\*{N} мкм\*\* на бік", COLLAR, _collar_th("isothermal_requirement"), 0.5),
    ("HW.33 · 02_02 §4.4 floor, gradient bound → collar_running_clearance.json",
     HW_POGO, rf"до \*\*{N} мкм\*\*, якщо Ti лишається", COLLAR, _collar_th("gradient_bound_requirement"), 0.5),
    ("HW.33 · 02_02 §4.4 floor at 81's cold edge → collar_running_clearance.json",
     HW_POGO, rf"`81` дає \*\*{N} мкм\*\*\)", COLLAR, _collar_th("isothermal_model_edge"), 0.5),
    ("HW.33 · 02_02 §4.4 board ceiling, coarse end → collar_running_clearance.json",
     HW_POGO, rf"стеля плати — \*\*{N}–[\d.]+ мм\*\* замість", COLLAR, _collar_row(-1, "ceiling_bound_mm"), 0.005),
    ("HW.33 · 02_02 §4.4 board ceiling, machined end → collar_running_clearance.json",
     HW_POGO, rf"стеля плати — \*\*[\d.]+–{N} мм\*\* замість", COLLAR, _collar_row(0, "ceiling_isothermal_mm"), 0.005),
    ("HW.33 · SUMMARY floor, isothermal → collar_running_clearance.json",
     SUMMARY, rf"The physics floor is {N} µm per side", COLLAR, _collar_th("isothermal_requirement"), 0.5),
    ("HW.33 · SUMMARY floor, gradient bound → collar_running_clearance.json",
     SUMMARY, rf"{N} µm if the Ti stays at 20 °C", COLLAR, _collar_th("gradient_bound_requirement"), 0.5),
    ("HW.33 · SUMMARY floor at 81's edge → collar_running_clearance.json",
     SUMMARY, rf"\({N} µm at `81`'s modelled cold edge\)", COLLAR, _collar_th("isothermal_model_edge"), 0.5),
    ("HW.33 · SUMMARY verdict ceiling, coarse end → collar_running_clearance.json",
     SUMMARY, rf"falls to\s+{N}–[\d.]+ mm rather than", COLLAR, _collar_row(-1, "ceiling_bound_mm"), 0.005),
    ("HW.33 · SUMMARY verdict ceiling, machined end → collar_running_clearance.json",
     SUMMARY, rf"falls to\s+[\d.]+–{N} mm rather than", COLLAR, _collar_row(0, "ceiling_isothermal_mm"), 0.005),
]
_COLLAR_DOC = {0: "обидві поверхні оброблені", 1: "литий пояс", 2: "грубе лиття"}
_COLLAR_SUM = {0: "Machined collar · machined band (IT7 · IT9)", 1: "Machined collar · moulded band (IT7 · IT11)",
               2: "Coarse: IT8 collar · IT12 moulded band"}
for _i in range(3):
    CHECKS += [
        (f"HW.33 · 02_02 §4.4 route {_i} clearance, isothermal → collar_running_clearance.json",
         HW_POGO, rf"{_COLLAR_DOC[_i]} — \*\*{N}–[\d.]+ мм\*\*", COLLAR, _collar_row(_i, "design_clearance_isothermal_mm"), 0.0005),
        (f"HW.33 · 02_02 §4.4 route {_i} clearance, bound → collar_running_clearance.json",
         HW_POGO, rf"{_COLLAR_DOC[_i]} — \*\*[\d.]+–{N} мм\*\*", COLLAR, _collar_row(_i, "design_clearance_bound_mm"), 0.0005),
    ]
    _row = rf"\| {re.escape(_COLLAR_SUM[_i])} \|"
    CHECKS += [
        (f"HW.33 · SUMMARY table route {_i} clearance, isothermal → collar_running_clearance.json",
         SUMMARY, _row + rf" {N}–[\d.]+ \|", COLLAR, _collar_row(_i, "design_clearance_isothermal_mm"), 0.0005),
        (f"HW.33 · SUMMARY table route {_i} clearance, bound → collar_running_clearance.json",
         SUMMARY, _row + rf" [\d.]+–{N} \|", COLLAR, _collar_row(_i, "design_clearance_bound_mm"), 0.0005),
        (f"HW.33 · SUMMARY table route {_i} ceiling, bound → collar_running_clearance.json",
         SUMMARY, _row + rf" [\d.]+–[\d.]+ \| {N}–[\d.]+ \|", COLLAR, _collar_row(_i, "ceiling_bound_mm"), 0.005),
        (f"HW.33 · SUMMARY table route {_i} ceiling, isothermal → collar_running_clearance.json",
         SUMMARY, _row + rf" [\d.]+–[\d.]+ \| [\d.]+–{N} \|", COLLAR, _collar_row(_i, "ceiling_isothermal_mm"), 0.005),
    ]

# 02_01 §5.2 — the radome-finish verdict (⚖️ delegated 2026-09-27: α ≤ 0.5, not a colour) quotes this same
# cache as its basis. Once the tracker body was cemented into it, that paragraph became the ONLY doc home
# of these numbers, and nothing pinned it — a re-run of 71 would have left the verdict's basis stale silently.
HW_BOM = "docs/02_01_Hardware_Architecture_and_BOM.md"


def _sunlit_breeze(alpha, field):
    def resolve(d):
        r = d["aging"][f"sunlit_alpha{alpha}_k0.1"]
        return r["t_eff_c"] if field == "t_eff_c" else r["life_at_ratified_vbat_ov"][field]
    return resolve


CHECKS += [
    ("HW.37 · 02_01 §5.2 dark finish margin, h_c × 0.7 → capsule_envelope.json",
     HW_BOM, rf"лише {N}–[\d.]+ K, тобто порядок похибки", THERMAL, _sens("0.95", "margin_to_rating_k"), 0.05),
    ("HW.37 · 02_01 §5.2 dark finish margin, still air → capsule_envelope.json",
     HW_BOM, rf"лише [\d.]+–{N} K, тобто порядок похибки", THERMAL, _hot("sunlit", "0.95", "margin_to_rating_k"), 0.05),
    ("HW.37 · 02_01 §5.2 light finish margin → capsule_envelope.json",
     HW_BOM, rf"а світлий \(α 0\.5\) — ≥ {N} K", THERMAL, _sens("0.50", "margin_to_rating_k"), 0.05),
    ("HW.37 · 02_01 §5.2 T_eff light, sunlit with breeze → capsule_envelope.json",
     HW_BOM, rf"зсуває T_eff старіння з {N} до", THERMAL, _sunlit_breeze("0.50", "t_eff_c"), 0.05),
    ("HW.37 · 02_01 §5.2 T_eff dark, sunlit with breeze → capsule_envelope.json",
     HW_BOM, rf"зсуває T_eff старіння з [\d.]+ до {N} °C", THERMAL, _sunlit_breeze("0.95", "t_eff_c"), 0.05),
    ("HW.37 · 02_01 §5.2 life light, optimistic → capsule_envelope.json",
     HW_BOM, rf"а строк — з {N} до [\d.]+ року", THERMAL, _sunlit_breeze("0.50", "optimistic_yr"), 0.05),
    ("HW.37 · 02_01 §5.2 life dark, optimistic → capsule_envelope.json",
     HW_BOM, rf"а строк — з [\d.]+ до {N} року", THERMAL, _sunlit_breeze("0.95", "optimistic_yr"), 0.05),
    ("HW.37 · 02_01 §5.2 life light, conservative → capsule_envelope.json",
     HW_BOM, rf"консервативний — з {N} до [\d.]+\)", THERMAL, _sunlit_breeze("0.50", "conservative_yr"), 0.05),
    ("HW.37 · 02_01 §5.2 life dark, conservative → capsule_envelope.json",
     HW_BOM, rf"консервативний — з [\d.]+ до {N}\)", THERMAL, _sunlit_breeze("0.95", "conservative_yr"), 0.05),
]

# ── HW.25 / HW.6 site climate (script 74) — rain/dew stand §7 pp. 3–4 and 01_04 §3.5 ──
# The stand sheet quotes rain and dew as an ORIENTATION and 01_04 quotes threshold DATES as an input;
# both are mirrors of one cache, so every number is pinned here and every date in `_DATE_PINS` below.
STAND = "docs/protocols/anchor/gdl_rain_dew_stand.md"
CODIT = "docs/01_04_CODIT_and_Xylemointegration.md"
SITE = "thermal/site_rain_dew.json"

CHECKS += [
    ("HW.25 · stand §7 p.3 wet-day share (≥ 1 mm) → site_rain_dew.json",
     STAND, rf"Діб із ≥ 1 мм — \*\*{N} %\*\*", SITE, lambda d: 100 * d["rain"]["wet_day_ge_1mm"]["fraction_of_days"], 0.5),
    ("HW.25 · stand §7 p.3 wet days a year → site_rain_dew.json",
     STAND, rf"\(≈ \*\*{N}\*\* на рік\)", SITE, lambda d: d["rain"]["wet_day_ge_1mm"]["days_per_year"], 0.05),
    ("HW.25 · stand §7 p.3 intensity median → site_rain_dew.json",
     STAND, rf"медіану \*\*{N}\*\* і P90 \*\*[\d.]+\*\* мм/год", SITE,
     lambda d: d["rain"]["intensity_on_wet_days_mm_per_h"]["median"], 0.005),
    ("HW.25 · stand §7 p.3 intensity P90 → site_rain_dew.json",
     STAND, rf"і P90 \*\*{N}\*\* мм/год", SITE, lambda d: d["rain"]["intensity_on_wet_days_mm_per_h"]["p90"], 0.005),
    ("HW.25 · stand §7 p.4 dew nights a year → site_rain_dew.json",
     STAND, rf"Таких ночей ≈ \*\*{N}\*\* на рік", SITE, lambda d: d["dew"]["liquid_t2m_above_0"]["nights_per_year"], 0.05),
    ("HW.25 · stand §7 p.4 dew-night share → site_rain_dew.json",
     STAND, rf"\(\*\*{N} %\*\* ночей\)", SITE, lambda d: 100 * d["dew"]["liquid_t2m_above_0"]["fraction_of_nights"], 0.5),
    ("HW.25 · stand §7 p.4 dew hours per night, median → site_rain_dew.json",
     STAND, rf"медіана \*\*{N}\*\*, P90", SITE, lambda d: d["dew"]["liquid_t2m_above_0"]["hours_per_dew_night_median"], 0.05),
    ("HW.25 · stand §7 p.4 dew hours per night, P90 → site_rain_dew.json",
     STAND, rf"P90 \*\*{N}\*\*\. Ночі з T2m", SITE, lambda d: d["dew"]["liquid_t2m_above_0"]["hours_per_dew_night_p90"], 0.05),
    ("HW.6 · 01_04 §3.5 sustained-crossing rule, return length → site_rain_dew.json run_days",
     CODIT, rf"останнього повернення нижче нього на ≥ {N} діб", SITE, lambda d: d["inputs"]["ours"]["run_days"], 0.5),
]

# Calendar dates are not numbers `N` can read, so they get their own pin: (label, doc, regex with ONE
# capture group holding MM-DD, cache resolver returning the same MM-DD string).
_DATE_PINS = (
    ("HW.6 · 01_04 §3.5 soil 7–28 cm ≥ 3.5 °C, median", CODIT, r"у медіані \*\*(\d\d-\d\d)\*\* \(P10–P90",
     lambda d: d["season"]["soil_7_28cm_ge_3.5C_spring"]["date_median"]),
    ("HW.6 · 01_04 §3.5 soil crossing P10", CODIT, r"\(P10–P90 \*\*(\d\d-\d\d)\*\*–",
     lambda d: d["season"]["soil_7_28cm_ge_3.5C_spring"]["date_p10"]),
    ("HW.6 · 01_04 §3.5 soil crossing P90", CODIT, r"\(P10–P90 \*\*\d\d-\d\d\*\*–\*\*(\d\d-\d\d)\*\*\)",
     lambda d: d["season"]["soil_7_28cm_ge_3.5C_spring"]["date_p90"]),
    ("HW.6 · 01_04 §3.5 implied cambial onset", CODIT, r"старт камбію припадає близько \*\*(\d\d-\d\d)\*\*",
     lambda d: d["season"]["soil_7_28cm_implied_cambial_onset"]["date_median"]),
    ("HW.6 · 01_04 §3.5 air ≥ 8 °C spring", CODIT, r"починається в медіані \*\*(\d\d-\d\d)\*\*–",
     lambda d: d["season"]["air_mean_ge_8C"]["spring"]["date_median"]),
    ("HW.6 · 01_04 §3.5 air ≥ 9 °C spring", CODIT, r"починається в медіані \*\*\d\d-\d\d\*\*–\*\*(\d\d-\d\d)\*\*",
     lambda d: d["season"]["air_mean_ge_9C"]["spring"]["date_median"]),
    ("HW.6 · 01_04 §3.5 air ≥ 9 °C autumn", CODIT, r"закінчується \*\*(\d\d-\d\d)\*\*–",
     lambda d: d["season"]["air_mean_ge_9C"]["autumn"]["date_median"]),
    ("HW.6 · 01_04 §3.5 air ≥ 8 °C autumn", CODIT, r"закінчується \*\*\d\d-\d\d\*\*–\*\*(\d\d-\d\d)\*\*",
     lambda d: d["season"]["air_mean_ge_8C"]["autumn"]["date_median"]),
    ("HW.6 · 01_04 §3.5 air ≥ 8 °C autumn P90", CODIT, r"\(P90 для 8 °C — \*\*(\d\d-\d\d)\*\*\)",
     lambda d: d["season"]["air_mean_ge_8C"]["autumn"]["date_p90"]),
)


@pytest.mark.parametrize("label,doc_rel,pattern,resolver", _DATE_PINS, ids=[p[0] for p in _DATE_PINS])
def test_doc_date_matches_cache(label, doc_rel, pattern, resolver):
    matches = re.findall(pattern, doc(doc_rel))
    assert len(matches) == 1, f"[{label}] anchor matched {len(matches)} times in {doc_rel} — expected exactly one"
    cache_val = resolver(C(SITE))
    assert matches[0] == cache_val, (
        f"[{label}] DOC↔CACHE DRIFT: {doc_rel} says {matches[0]} but {SITE} says {cache_val}. "
        f"Cache is SSOT — fix the doc, or re-run 74 if the cache is wrong.")

# ── doc↔code: the ratified gene is MIRRORED into lib/constants.py, and a mirror needs a pin ──

RFQ = "docs/protocols/procurement/ebfc_chem_rfq.md"
CONSTANTS = "tools/in_silico/lib/constants.py"
# Each entry: (doc, regex capturing the declared list, the separator inside it).
_RATIFIED_GENE_DECLARATIONS = (
    (L1, r"The gene ordered from the CRO carries `11 N→Q \+ ([^`]+)`", " + "),
    (RFQ, r"600 aa · 11 N→Q · ([^*]+)\*\*", " · "),
)


MIRROR_SYMBOL = "RATIFIED_GENE_COMPENSATIONS"


def _mirror_in_code() -> tuple[str, ...]:
    """`RATIFIED_GENE_COMPENSATIONS` read from the SOURCE with `ast`, never imported.

    ⛔ The obvious implementation — `spec_from_file_location` + `exec_module` — was written first
    and MEASURED WRONG on 2026-09-21. CPython validates a `__pycache__` entry against the pair
    (source mtime **in whole seconds**, source size). Flipping one letter of a substitution code
    (`L80D` → `L80E`) changes neither, so a mutate-test-restore cycle inside one second handed the
    pin the MUTATED bytecode while the source on disk was correct — the gate reported drift that
    did not exist. The mirror direction is the dangerous one: the same collision can serve a STALE
    value while the source has really drifted, and the pin would stay green.
    `ast` executes nothing and consults no cache, so the file on disk is the only input.
    CAN catch: a changed membership or letter in the mirror.
    CANNOT catch: a mirror that stops being a literal (computed, imported, or built at runtime) —
    that raises here by name rather than passing quietly.
    """
    return tuple(_literal_in_code(MIRROR_SYMBOL))


def _literal_in_code(symbol: str):
    """A module-level literal of `lib/constants.py`, read with `ast` (why not import — above)."""
    import ast
    tree = ast.parse((REPO / CONSTANTS).read_text(encoding="utf-8"), filename=CONSTANTS)
    for node in tree.body:
        targets = getattr(node, "targets", [])
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == symbol for t in targets):
            return ast.literal_eval(node.value)
    raise AssertionError(
        f"{CONSTANTS} has no module-level literal `{symbol}` — either it was renamed or it "
        f"stopped being a literal; this pin reads the source, so it cannot follow a computed value.")


@pytest.mark.parametrize("doc_rel,pattern,sep", _RATIFIED_GENE_DECLARATIONS,
                         ids=[d[0].rsplit("/", 1)[-1] for d in _RATIFIED_GENE_DECLARATIONS])
def test_ratified_gene_mirrors_canon(doc_rel, pattern, sep):
    """The ordered gene's compensations must read the same in canon and in the code that builds it.

    WHY a pin and not a habit: `69 --ratified` builds the sequence the CRO receives from a MIRROR
    (`tools/in_silico/lib/constants.py RATIFIED_GENE_COMPENSATIONS`). If canon ever takes a FOURTH
    compensation, the mirror would keep building the old three and its cache would still say «the
    ratified gene», measuring a sequence nobody ordered. Both directions fail here: a code-only
    change and a canon-only one. ⚠️ The nearest candidate, `Ala201 → Ser`, is NOT pending: the
    burial ceiling that refuses it was ratified at 0.75 (⚖️ founder 2026-09-21, home L1 §2). This
    pin guards the mirror, it does not track an open question.

    CAN catch: a set that differs in membership or in a substitution letter, in either document.
    CANNOT catch: a canon edit that REWORDS the declaration out of the anchor — that shows up as
    «anchor not found», which is the same red and the same fix (re-read both, then re-anchor).
    CANNOT catch: whether the sequence is right. That is a founder verdict, home L1 §2.
    """
    m = re.search(pattern, doc(doc_rel))
    assert m, (
        f"{doc_rel}: the ratified-gene declaration did not match {pattern!r}. Either it was "
        f"reworded (re-anchor this pin) or it was removed (then {CONSTANTS} mirrors nothing).")
    declared = tuple(x.strip().strip("`") for x in m.group(1).split(sep))
    mirror = _mirror_in_code()
    assert set(declared) == set(mirror), (
        f"RATIFIED GENE DRIFT: {doc_rel} declares {declared}, {CONSTANTS} mirrors {mirror}. "
        f"Canon is the home (L1 §2) — fix the mirror, then re-run "
        f"`69_chem11_aggregation_compensation.py --ratified`, because its cache measures the "
        f"sequence the mirror names.")


# ── doc↔code: the press-fit case a contractor EXECUTES carries constants.py numbers (00_07 HW.26) ──
# The calibration case (Додаток 3, UA + EN twins) and the FEA/Prony request quote the assembly
# temperature, the cold extreme and the fit band of `lib/constants.py` — the inputs of `56` and of
# THERMAL_STRESS_REPORT §4 (`thermal_interference(T_FOREST_MIN_C, T_ASSEMBLY_C, …)`). Their only guard
# was «звірити вручну перед відправкою» — a human check that fires once, on dispatch day. The geometry
# half of the same documents is pinned by `scripts/cem_canon_sync.rb`; this is the temperature half.
CAL_UA = "docs/protocols/anchor/fea_aging/calibration_case_ua.md"
CAL_EN = "docs/protocols/anchor/fea_aging/calibration_case_en.md"
FEA_BRIEF = "docs/protocols/outreach/lock_fea_prony_brief.md"


def _k(symbol: str, scale: float = 1.0):
    return lambda: scale * float(_literal_in_code(symbol))


_ASM, _COLD, _WARM = _k("T_ASSEMBLY_C"), _k("T_FOREST_MIN_C"), _k("T_FOREST_MAX_C")
_COLD_WORD = _k("T_FOREST_MIN_C", -1.0)           # «мінус 30» / «minus 30» spells the magnitude
_I_MIN, _I_MAX = _k("H7S6_INTERF_DIA_MIN_UM"), _k("H7S6_INTERF_DIA_MAX_UM")
_I_MAX_RADIAL = _k("H7S6_INTERF_DIA_MAX_UM", 0.5)  # the case tabulates RADIAL interference


def _drop():
    return _ASM() - _COLD()


# (label, doc, regex — one group per expected value, expected values in group order)
_PRESS_FIT_PINS = (
    ("cal UA assembly·cold·drop", CAL_UA,
     r"Натяг закладено при (\d+) градусах Цельсія; охолодження в кейсі — до мінус (\d+), тобто перепад (\d+) градусів",
     (_ASM, _COLD_WORD, _drop)),
    ("cal UA intro cold", CAL_UA, r"охолодження до мінус (\d+) градусів Цельсія і максимальний натяг посадки",
     (_COLD_WORD,)),
    ("cal UA table cold", CAL_UA, r"\| Складова \(при мінус (\d+) градусах\) \|", (_COLD_WORD,)),
    ("cal UA max fit radial", CAL_UA, r"\| Лише посадка, максимальний натяг \| (\d+,\d) мкм \|", (_I_MAX_RADIAL,)),
    ("cal EN assembly·cold·drop", CAL_EN,
     r"The interference is specified at (\d+) degrees Celsius; cooling in the case goes to minus (\d+), a drop of (\d+) degrees",
     (_ASM, _COLD_WORD, _drop)),
    ("cal EN intro cold", CAL_EN, r"cooling to minus (\d+) degrees Celsius, and the maximum fit interference",
     (_COLD_WORD,)),
    ("cal EN table cold", CAL_EN, r"\| Component \(at minus (\d+) degrees\) \|", (_COLD_WORD,)),
    ("cal EN max fit radial", CAL_EN, r"\| Fit only, maximum interference \| (\d+\.\d) µm \|", (_I_MAX_RADIAL,)),
    ("brief §2 band", FEA_BRIEF, r"смуга (\d+)–(\d+) мкм діаметрально", (_I_MIN, _I_MAX)),
    ("brief §2 window", FEA_BRIEF, r"\| Температури \| вікно (−\d+) °C … \+(\d+) °C", (_COLD, _WARM)),
    ("brief §9 band@assembly", FEA_BRIEF, r"\*\*Натяг:\*\* (\d+)–(\d+) мкм на діаметр, віднесено до (\d+) °C",
     (_I_MIN, _I_MAX, _ASM)),
    ("brief §9 window", FEA_BRIEF, r"\*\*Температури:\*\* робоче вікно від (−\d+) до \+(\d+) °C", (_COLD, _WARM)),
    ("brief §9 worst cold", FEA_BRIEF, r"У найгіршому поєднанні \((−\d+) °C і максимальний натяг\)", (_COLD,)),
    ("brief §9 calibration cold", FEA_BRIEF, r"гладкий вал без зубців при (−\d+) °C і максимальному натягу", (_COLD,)),
    ("brief §10 band@assembly", FEA_BRIEF,
     r"\*\*Interference:\*\* (\d+)–(\d+) µm on the diameter, referred to (\d+) °C", (_I_MIN, _I_MAX, _ASM)),
    ("brief §10 window", FEA_BRIEF, r"\*\*Temperatures:\*\* operating window (−\d+) to \+(\d+) °C", (_COLD, _WARM)),
    ("brief §10 worst cold", FEA_BRIEF, r"In the worst combination \((−\d+) °C and maximum interference\)", (_COLD,)),
    ("brief §10 calibration cold", FEA_BRIEF, r"a smooth shaft without teeth at (−\d+) °C and maximum interference",
     (_COLD,)),
)


@pytest.mark.parametrize("label,doc_rel,pattern,expected", _PRESS_FIT_PINS, ids=[p[0] for p in _PRESS_FIT_PINS])
def test_press_fit_case_mirrors_constants(label, doc_rel, pattern, expected):
    """Each temperature / fit-band number a contractor receives equals its `lib/constants.py` home.

    CAN catch: a constant moved in code with the outgoing text left behind, or the text edited alone
    (the assembly 20 °C, the cold −30 °C, the warm +40 °C, the 5–34 µm diametral band, its radial max).
    CANNOT catch: whether the constants are right (−30 °C is the Cherkasy winter extreme by declaration,
    the band is H7/r6 mislabelled H7/s6 — `constants.py` says so), nor the computed 17.9 MPa / 27.6 µm
    results, which follow from these inputs through `56` and have no pin here. A reworded sentence shows
    up as «anchor not found» — re-anchor, never loosen the pattern to a bare number.
    """
    matches = re.findall(pattern, doc(doc_rel))
    assert len(matches) == 1, (
        f"[{label}] anchor matched {len(matches)}× in {doc_rel} — pattern {pattern!r}; re-anchor it "
        f"(reworded) or tighten it (ambiguous).")
    got = matches[0] if isinstance(matches[0], tuple) else (matches[0],)
    for raw, want in zip(got, expected, strict=True):
        assert abs(_to_float(raw.replace(",", ".")) - want()) < 1e-9, (
            f"[{label}] PRESS-FIT DRIFT: {doc_rel} says {raw} but {CONSTANTS} gives {want():g}. "
            f"The constant is the home (it feeds `56` and THERMAL_STRESS_REPORT §4) — fix the text, "
            f"or, if the constant moved on purpose, re-run `56` and re-read the case's results first.")


# ── HW.26 (2026-10-03): the torque path onto the anchor's own axis, owner = script 77 ──
# The two numbers 01_01 §4.3 C quotes move with inputs prose never re-reads — the band (lib.constants), the
# relaxation, the Lamé of lib.mechanics, the CEM geometry and 55's lock window.
TORQUE = "mechanical/anchor_torque_path.json"
CHECKS += [
    ("HW.26 · slip threshold τ_s*, low end at 20 °C → anchor_torque_path.json",
     COAXIAL, rf"τ_s\* = \*\*{N}–[\d.]+ МПа\*\* при 20 °C", TORQUE,
     lambda d: d["verdict"]["tau_s_star_MPa_at_assembly_temperature"][0], 0.005),
    ("HW.26 · slip threshold τ_s*, high end at 20 °C → anchor_torque_path.json",
     COAXIAL, rf"τ_s\* = \*\*[\d.]+–{N} МПа\*\* при 20 °C", TORQUE,
     lambda d: d["verdict"]["tau_s_star_MPa_at_assembly_temperature"][1], 0.005),
    ("HW.26 · PEEK bore shear capped by the friction μ·P_c → anchor_torque_path.json",
     COAXIAL, rf"μ·P_c ≤ \*\*{N} МПа\*\*", TORQUE,
     lambda d: d["verdict"]["peek_bore_shear_cap_MPa_max"], 0.005),
    # Q2 — the wind bracket at its cap; the fork-C verdict (01_01 §4.3 C, ⚖️ 2026-10-03) quotes each of these
    ("HW.26 · Q2 cap: green pine shear strength, low end → anchor_torque_path.json",
     COAXIAL, rf"волокон — \*\*{N}–[\d.]+ МПа\*\*", TORQUE, lambda d: d["wind_bracket"]["tau_cap_MPa_range"][0], 0.05),
    ("HW.26 · Q2 cap: green pine shear strength, high end → anchor_torque_path.json",
     COAXIAL, rf"волокон — \*\*[\d.]+–{N} МПа\*\*", TORQUE, lambda d: d["wind_bracket"]["tau_cap_MPa_range"][1], 0.05),
    ("HW.26 · Q2 slip at the shank surface at the cap, low end → anchor_torque_path.json",
     COAXIAL, rf"розійшлися б на \*\*{N}–[\d.]+ мкм\*\* проковзування", TORQUE,
     lambda d: d["wind_bracket"]["slip_at_shank_surface_um_range"][0], 0.05),
    ("HW.26 · Q2 slip at the shank surface at the cap, high end → anchor_torque_path.json",
     COAXIAL, rf"розійшлися б на \*\*[\d.]+–{N} мкм\*\* проковзування", TORQUE,
     lambda d: d["wind_bracket"]["slip_at_shank_surface_um_range"][1], 0.05),
    ("HW.26 · Q2 hex engagement threshold, low end → anchor_torque_path.json",
     COAXIAL, rf"не більший за \*\*{N}–[\d.]+ мкм\*\*", TORQUE,
     lambda d: d["wind_bracket"]["hex_engages_below_radial_clearance_um_range"][0], 0.05),
    ("HW.26 · Q2 hex engagement threshold, high end → anchor_torque_path.json",
     COAXIAL, rf"не більший за \*\*[\d.]+–{N} мкм\*\*", TORQUE,
     lambda d: d["wind_bracket"]["hex_engages_below_radial_clearance_um_range"][1], 0.05),
    ("HW.26 · Q2 PEEK↔Ti swing of the hex clearance over the forest range → anchor_torque_path.json",
     COAXIAL, rf"зсуває цей зазор на \*\*{N} мкм\*\*", TORQUE, lambda d: d["wind_bracket"]["hex_clearance_thermal_swing_um"], 0.05),
    ("HW.26 · Q2 in-window temperature band, low end → anchor_torque_path.json",
     COAXIAL, rf"лише \*\*{N}–[\d.]+ K\*\* із 70", TORQUE, lambda d: d["wind_bracket"]["engagement_band_without_preload_K_range"][0], 0.5),
    ("HW.26 · Q2 in-window temperature band, high end → anchor_torque_path.json",
     COAXIAL, rf"лише \*\*[\d.]+–{N} K\*\* із 70", TORQUE, lambda d: d["wind_bracket"]["engagement_band_without_preload_K_range"][1], 0.5),
    ("HW.26 · Q2 PEEK sleeve torsional decay length on wood, low end → anchor_torque_path.json",
     COAXIAL, rf"кручення PEEK-втулки на деревині — \*\*{N}–[\d.]+ мм\*\*", TORQUE,
     lambda d: d["wind_bracket"]["sleeve_torsional_decay_length_mm_range"][0], 0.05),
    ("HW.26 · Q2 PEEK sleeve torsional decay length on wood, high end → anchor_torque_path.json",
     COAXIAL, rf"кручення PEEK-втулки на деревині — \*\*[\d.]+–{N} мм\*\*", TORQUE,
     lambda d: d["wind_bracket"]["sleeve_torsional_decay_length_mm_range"][1], 0.05),
    ("HW.26 · Q2 bark-end peak factor of the free-interface slip, rigid gyroid → anchor_torque_path.json",
     COAXIAL, rf"до \*\*{N}\*\* раза більше за центроїдне", TORQUE,
     lambda d: d["wind_bracket"]["bark_end_peak_factor"]["rigid_gyroid"], 0.005),
    ("HW.26 · Q2 bark-end peak factor of the free-interface slip, compliant gyroid → anchor_torque_path.json",
     COAXIAL, rf"тверде тіло \(\*\*{N}\*\* — якщо", TORQUE,
     lambda d: d["wind_bracket"]["bark_end_peak_factor"]["compliant_gyroid"], 0.005),
    ("HW.26 · Q2 slip at the sleeve's bark end, low end → anchor_torque_path.json",
     COAXIAL, rf"тобто до \*\*{N}–[\d.]+ мкм\*\*", TORQUE, lambda d: d["wind_bracket"]["slip_at_bark_end_um_range"][0], 0.05),
    ("HW.26 · Q2 slip at the sleeve's bark end, high end → anchor_torque_path.json",
     COAXIAL, rf"тобто до \*\*[\d.]+–{N} мкм\*\*", TORQUE, lambda d: d["wind_bracket"]["slip_at_bark_end_um_range"][1], 0.05),
    ("HW.26 · Q2 hex engagement threshold at the bark end, low end → anchor_torque_path.json",
     COAXIAL, rf"й \*\*{N}–[\d.]+ мкм\*\* при піковому", TORQUE,
     lambda d: d["wind_bracket"]["hex_engages_below_radial_clearance_um_bark_end_range"][0], 0.05),
    ("HW.26 · Q2 hex engagement threshold at the bark end, high end → anchor_torque_path.json",
     COAXIAL, rf"й \*\*[\d.]+–{N} мкм\*\* при піковому", TORQUE,
     lambda d: d["wind_bracket"]["hex_engages_below_radial_clearance_um_bark_end_range"][1], 0.05),
    ("HW.26 · Q2 preload-free band at the bark end, low end → anchor_torque_path.json",
     COAXIAL, rf"біля кори — \*\*{N}–[\d.]+ K\*\*", TORQUE,
     lambda d: d["wind_bracket"]["engagement_band_without_preload_K_bark_end_range"][0], 0.5),
    ("HW.26 · Q2 preload-free band at the bark end, high end → anchor_torque_path.json",
     COAXIAL, rf"біля кори — \*\*[\d.]+–{N} K\*\*", TORQUE,
     lambda d: d["wind_bracket"]["engagement_band_without_preload_K_bark_end_range"][1], 0.5),
    ("HW.26 · Q2 strain factor before the written hex engages at the bark end → anchor_torque_path.json",
     COAXIAL, rf"оцінену в \*\*{N}\*\* раза", TORQUE,
     lambda d: d["wind_bracket"]["strain_factor_to_engage_written_hex_at_bark_end"], 0.05),
    ("HW.26 · Q2 strain factor before the preload-free band fills the forest span → anchor_torque_path.json",
     COAXIAL, rf"у ≈ \*\*{N}\*\* раза більша", TORQUE,
     lambda d: d["wind_bracket"]["strain_factor_to_fill_forest_span_at_bark_end"], 0.05),
]


# ── HW.6 (2026-10-03): the flange → cambium path in sun, owner = script 78 ──
# The canon home (01_04 §3.1), the second ground of the radome finish (02_01 §5.2) and the log-day criterion
# (bench §A.1) quote numbers that move with 71's capsule balance, 58's layer properties and the bark bracket.
FLANGE_HEAT = "thermal/flange_cambium_heat.json"
BENCH = "docs/protocols/anchor/install_and_log_bench.md"
_V78 = lambda d: d["verdict"]  # noqa: E731
CHECKS += [
    ("HW.6 · hottest cambium hour under the flange, specified finish → flange_cambium_heat.json",
     CODIT, rf"найгарячіша — \*\*{N} °C\*\* на найтоншому контакті", FLANGE_HEAT,
     lambda d: _V78(d)["worst_cell"]["sunlit_0.50"]["cambium_max_C"], 0.05),
    ("HW.6 · the thinnest contact: ridge minimum minus the facing spread → flange_cambium_heat.json",
     CODIT, rf"розкид торцювання — \*\*{N} мм\*\* мертвої кори", FLANGE_HEAT, lambda d: d["bark"]["thin_mm"], 0.05),
    ("HW.6 · α at which the cambium reaches the gate, thinnest contact → flange_cambium_heat.json",
     CODIT, rf"лише понад α ≈ \*\*{N}\*\* на тому самому контакті", FLANGE_HEAT,
     lambda d: _V78(d)["alpha_crossing_sunlit_still_air"]["thin"], 0.005),
    ("HW.6 · dead-bark floor at the specified finish → flange_cambium_heat.json",
     CODIT, rf"лишається менше ≈ \*\*{N} мм\*\* мертвої кори", FLANGE_HEAT,
     lambda d: _V78(d)["dead_bark_floor_mm_at_specified_alpha"], 0.05),
    ("HW.6 · shift of the hottest cambium hour under a crown, specified finish → flange_cambium_heat.json",
     CODIT, rf"на \*\*\+{N} K\*\* проти кори без нього", FLANGE_HEAT,
     lambda d: _V78(d)["shift_under_crown_K"]["0.50"], 0.05),
    ("HW.6 → HW.37 · the radome finish's second ground: cambium crossing α → flange_cambium_heat.json",
     HW_BOM, rf"досягає порога 50 °C понад α ≈ \*\*{N}\*\*", FLANGE_HEAT,
     lambda d: _V78(d)["alpha_crossing_sunlit_still_air"]["thin"], 0.005),
    ("HW.6 · log-day thermal criterion: dead bark left under the deep edge → flange_cambium_heat.json",
     BENCH, rf"має лишатися ≥ ≈ \*\*{N} мм\*\* мертвої кори", FLANGE_HEAT,
     lambda d: _V78(d)["dead_bark_floor_mm_at_specified_alpha"], 0.05),
]


# ── HW.6 (2026-10-03): the frost half of the same path, owner = script 79 ──
# The canon home (01_04 §3.1) quotes the sky × sun ends at the tied end, the mechanism fields and the decoupled range.
FLANGE_FROST = "thermal/flange_cambium_frost.json"
_R79 = lambda d, regime, cp="tied": d["regimes"][regime][cp]  # noqa: E731
_NN = rf"[{_DASHES}\-+]?[\d.]+"   # the other end of a quoted range, not pinned by that row
CHECKS += [
    ("HW.6 · frost: winter clear-sky emissivity, median → flange_cambium_frost.json",
     CODIT, rf"медіана ε \*\*{N}\*\*", FLANGE_FROST, lambda d: d["clear_sky_emissivity_winter"]["median"], 0.006),   # canon rounds to 0.01
    ("HW.6 · frost: decoupled fin over the contact ring → flange_cambium_frost.json",
     CODIT, rf"\*\*{N}\*\* площі кільця Ø15", FLANGE_FROST, lambda d: d["areas"]["fin_ratio"]["decoupled"], 0.005),
    ("HW.6 · frost: tied fin over the contact ring → flange_cambium_frost.json",
     CODIT, rf"\*\*{N}\*\* площі кільця\.", FLANGE_FROST, lambda d: d["areas"]["fin_ratio"]["tied"], 0.05),
    ("HW.6 · frost: tied median, clear sky no sun, low end → flange_cambium_frost.json",
     CODIT, rf"ясне небо без сонця — {N}…{_NN} K", FLANGE_FROST, lambda d: _R79(d, "clear_no_sun")["median_K_range"][0], 0.005),
    ("HW.6 · frost: tied median, clear sky no sun, high end → flange_cambium_frost.json",
     CODIT, rf"ясне небо без сонця — {_NN}…{N} K", FLANGE_FROST, lambda d: _R79(d, "clear_no_sun")["median_K_range"][1], 0.005),
    ("HW.6 · frost: mechanism — bark equilibrium below air at the reference hour → flange_cambium_frost.json",
     CODIT, rf"кора \*\*{N} K\*\* від повітря", FLANGE_FROST, lambda d: d["mechanism"]["bark"]["equilibrium_minus_air_K"], 0.05),
    ("HW.6 · frost: mechanism — capsule equilibrium below air at the reference hour → flange_cambium_frost.json",
     CODIT, rf"капсула \*\*{N} K\*\*\)", FLANGE_FROST, lambda d: d["mechanism"]["capsule"]["equilibrium_minus_air_K"], 0.05),
    ("HW.6 · frost: mechanism — tied median with the capsule's h_c set to bark's → flange_cambium_frost.json",
     CODIT, rf"медіана стає \*\*\+{N} K\*\*", FLANGE_FROST,
     lambda d: d["sensitivity_thin_bark_still_air_clear_no_sun"]["capsule_h_c_as_bark"]["tied"]["median"], 0.005),
    ("HW.6 · frost: tied median, overcast no sun, low end → flange_cambium_frost.json",
     CODIT, rf"Суцільна хмарність без сонця — \+{N}…{_NN} K", FLANGE_FROST,
     lambda d: _R79(d, "overcast_no_sun")["median_K_range"][0], 0.005),
    ("HW.6 · frost: tied median, overcast no sun, high end → flange_cambium_frost.json",
     CODIT, rf"Суцільна хмарність без сонця — {_NN}…\+{N} K", FLANGE_FROST,
     lambda d: _R79(d, "overcast_no_sun")["median_K_range"][1], 0.005),
    ("HW.6 · frost: mechanism — tied conductance to the air over bark's → flange_cambium_frost.json",
     CODIT, rf"в \*\*{N}\*\* раза більша за корову", FLANGE_FROST, lambda d: d["mechanism"]["tied_over_bark_conductance"], 0.05),
    ("HW.6 · frost: tied median, clear sky diffuse sun, low end → flange_cambium_frost.json",
     CODIT, rf"ясне небо \*\*{N}…{_NN} K\*\*, хмарність", FLANGE_FROST,
     lambda d: _R79(d, "clear_diffuse_sun")["median_K_range"][0], 0.005),
    ("HW.6 · frost: tied median, clear sky diffuse sun, high end → flange_cambium_frost.json",
     CODIT, rf"ясне небо \*\*{_NN}…\+{N} K\*\*, хмарність", FLANGE_FROST,
     lambda d: _R79(d, "clear_diffuse_sun")["median_K_range"][1], 0.005),
    ("HW.6 · frost: tied median, overcast diffuse sun, low end → flange_cambium_frost.json",
     CODIT, rf"хмарність \*\*\+{N}…{_NN} K\*\*; найгірша", FLANGE_FROST,
     lambda d: _R79(d, "overcast_diffuse_sun")["median_K_range"][0], 0.005),
    ("HW.6 · frost: tied median, overcast diffuse sun, high end → flange_cambium_frost.json",
     CODIT, rf"хмарність \*\*{_NN}…\+{N} K\*\*; найгірша", FLANGE_FROST,
     lambda d: _R79(d, "overcast_diffuse_sun")["median_K_range"][1], 0.005),
    ("HW.6 · frost: the worst day across all ends, tied → flange_cambium_frost.json",
     CODIT, rf"найгірша доба серед усіх кінців — \*\*\+{N} K\*\*", FLANGE_FROST, lambda d: d["verdict"]["tied_max_K"], 0.05),
    ("HW.6 · frost: decoupled median, clear sky no sun, low end → flange_cambium_frost.json",
     CODIT, rf"від \*\*{N}…{_NN} K\*\* \(ясне небо без сонця\)", FLANGE_FROST,
     lambda d: _R79(d, "clear_no_sun", "decoupled")["median_K_range"][0], 0.005),
    ("HW.6 · frost: decoupled median, clear sky no sun, high end → flange_cambium_frost.json",
     CODIT, rf"від \*\*{_NN}…{N} K\*\* \(ясне небо без сонця\)", FLANGE_FROST,
     lambda d: _R79(d, "clear_no_sun", "decoupled")["median_K_range"][1], 0.005),
    ("HW.6 · frost: decoupled median, overcast diffuse sun, low end → flange_cambium_frost.json",
     CODIT, rf"до \*\*\+{N}…{_NN} K\*\* \(хмарність", FLANGE_FROST,
     lambda d: _R79(d, "overcast_diffuse_sun", "decoupled")["median_K_range"][0], 0.005),
    ("HW.6 · frost: decoupled median, overcast diffuse sun, high end → flange_cambium_frost.json",
     CODIT, rf"до \*\*{_NN}…\+{N} K\*\* \(хмарність", FLANGE_FROST,
     lambda d: _R79(d, "overcast_diffuse_sun", "decoupled")["median_K_range"][1], 0.005),
]

# The canon numbers lib.constants mirrors for 77/78 (BARK_DEAD_RIDGE_DBH38_MM · INSTALL_ANGLE_DEG · DBH_MIN_CM), read back
# through the caches that consumed them: an edit on either side alone turns red here.
CHECKS += [
    ("lib mirror · dead-bark ridge bracket, low end at DBH 38 (01_04 §3.2) → flange_cambium_heat.json",
     CODIT, rf"мертва кора ≈ {N}–[\d.]+ мм при DBH 38", FLANGE_HEAT,
     lambda d: d["bark"]["thin_mm"] + d["bark"]["facing_spread_mm"], 0.05),
    ("lib mirror · dead-bark ridge bracket, high end at DBH 38 (01_04 §3.2) → flange_cambium_heat.json",
     CODIT, rf"мертва кора ≈ [\d.]+–{N} мм при DBH 38", FLANGE_HEAT, lambda d: d["bark"]["thick_mm"], 0.05),
    ("lib mirror · facing spread Ø_flange·sin(install angle) (01_04 §3.2) → flange_cambium_heat.json",
     CODIT, rf"для {N} мм \(10°\)", FLANGE_HEAT, lambda d: d["bark"]["facing_spread_mm"], 0.05),
    ("lib mirror · smallest host stem DBH (01_01 §1 Zone 2) → anchor_torque_path.json",
     COAXIAL, rf"DBH ≥ {N} см\*\* \(4%-правило\)", TORQUE, lambda d: 200.0 * d["geometry"]["stem_radius_m"], 0.05),
]


# ── CHEM.11 second instrument: SUMMARY §CHEM.11 table ⟷ script 80's cache ───────────────────
# Pins every number the SUMMARY's second-instrument block prints. The cache is OURS (the reading);
# the A3D output it reads is third-party and excluded from the CC-BY-SA grant (`/NOTICE`).
# ⚠️ ONE capture group per pin — the engine above compares a single value, so a row that prints two
# numbers gets two pins rather than one tuple (measured: a tuple reaches `_to_float` and raises).
A3D = "chemistry/chem11_a3d_crosscheck.json"


def _a3d_nb(site, field, radius="7"):
    return lambda d: d["sites"][site]["best_measured_positive_neighbour_by_radius_A"][radius][field]


CHECKS += [
    # ── the table: each site's own A3D score, and the neighbour that carries its flag ──
    ("CHEM.11 A3D score at Gln71 → 80 (SUMMARY §CHEM.11 second-instrument table)",
     SUMMARY, rf"\| \*\*Gln71\*\* \| {N} \| \*\*Leu80",
     A3D, lambda d: d["sites"]["Gln71"]["a3d_score_own"], 0.0005),
    ("CHEM.11 A3D flag beside Gln71 is Leu80 → 80",
     SUMMARY, rf"\*\*Leu80 \+{N}\*\* — rank",
     A3D, _a3d_nb("Gln71", "a3d_score"), 0.0005),
    ("CHEM.11 A3D score at Gln405 → 80",
     SUMMARY, rf"\| \*\*Gln405\*\* \| {N} \| \*\*Ile401",
     A3D, lambda d: d["sites"]["Gln405"]["a3d_score_own"], 0.0005),
    ("CHEM.11 A3D flag beside Gln405 is Ile401 → 80",
     SUMMARY, rf"\*\*Ile401 \+{N}\*\* — rank",
     A3D, _a3d_nb("Gln405", "a3d_score"), 0.0005),
    # the uncompensated third site — the finding the sentinel hid in the first reading of this run
    ("CHEM.11 A3D score at Gln258 → 80 (the site the sentinel hid)",
     SUMMARY, rf"\| Gln258 \| {N} \| Val256",
     A3D, lambda d: d["sites"]["Gln258"]["a3d_score_own"], 0.0005),
    ("CHEM.11 A3D weak flag beside Gln258 is Val256 → 80",
     SUMMARY, rf"Val256 \+{N} — an order of magnitude weaker",
     A3D, _a3d_nb("Gln258", "a3d_score"), 0.0005),
    ("CHEM.11 A3D score at Gln200 → 80",
     SUMMARY, rf"\| Gln200 \| {N} \| none",
     A3D, lambda d: d["sites"]["Gln200"]["a3d_score_own"], 0.0005),
    # the ranks: a flag is an adjective until it is a position in A3D's own ranking
    ("CHEM.11 Leu80 rank among A3D's mature positives → 80",
     SUMMARY, rf"\*\*Leu80 \+[\d.]+\*\* — rank \*\*{N}\*\*",
     A3D, lambda d: d["compensated_positions"]["L80D"]["rank_among_mature_positive"], 0.0),
    ("CHEM.11 Ile401 rank among A3D's mature positives → 80",
     SUMMARY, rf"\*\*Ile401 \+[\d.]+\*\* — rank \*\*{N}\*\*",
     A3D, lambda d: d["compensated_positions"]["I401S"]["rank_among_mature_positive"], 0.0),
    ("CHEM.11 size of A3D's mature positive set → 80",
     SUMMARY, rf"of the mature chain's {N} positive residues",
     A3D, lambda d: d["compensated_positions"]["L80D"]["n_mature_positive"], 0.0),
    # A70S: the compensation A3D neither supports nor contradicts
    ("CHEM.11 A3D score at the A70S position → 80",
     SUMMARY, rf"residue A3D\nscores \*\*{N}\*\* — and A3D structurally cannot flag an Ala",
     A3D, lambda d: d["compensated_positions"]["A70S"]["a3d_score"], 0.0005),
    # ── the exposure-gate sentinel census: the numbers that make the trap checkable ──
    # ⚠️ Anchors are kept to ONE line and short: the 2026-10-04 adversary pass rewrote this paragraph
    # and four of these pins went red purely because the line WRAP moved, not the numbers. A long
    # anchor spanning a wrap is a pin on the typesetting.
    ("CHEM.11 A3D sentinel count → 80 (SUMMARY limit 2)",
     SUMMARY, rf"\*\*{N} of [\d]+ rows carry an exact",
     A3D, lambda d: d["exposure_gate_census"]["n_sentinel"], 0.0),
    ("CHEM.11 A3D chain length behind that census → 80",
     SUMMARY, rf"\*\*[\d]+ of {N} rows carry an exact",
     A3D, lambda d: d["totals_of_a3d_output"]["n_residues"], 0.0),
    ("CHEM.11 A3D sentinel percentage → 80",
     SUMMARY, rf"an exact `0\.0` \({N} %\)",
     A3D, lambda d: round(100 * d["exposure_gate_census"]["sentinel_fraction"]), 0.5),
    ("CHEM.11 A3D hydrophobic sentinels → 80",
     SUMMARY, rf"%\), {N} of them",
     A3D, lambda d: d["exposure_gate_census"]["n_sentinel_hydrophobic_by_a3d_matrix"], 0.0),
    # ── the limits block: the matrix value and the gate threshold the prose quotes ──
    # Found missing by the adversary pass of 2026-10-04: the block printed them unpinned while the
    # table beside it was pinned, so drift in the LIMITS would have been silent.
    ("CHEM.11 A3D Gln matrix value → 80 (SUMMARY, the «measures the scale» limit)",
     SUMMARY, rf"\*\*Gln's value is {N}\*\*",
     A3D, lambda d: d["a3d_scoring_as_read_from_source"]["gln_matrix_value"], 0.0),
    ("CHEM.11 A3D exposure-gate RSA threshold → 80",
     SUMMARY, rf"Below \*\*{N}\*\* % RSA the tool",
     A3D, lambda d: d["a3d_scoring_as_read_from_source"]["exposure_gate_rsa_pct"], 0.0),

    # ── the signal-peptide share: the leg that reached the gene ORDER as a QC line ──
    ("CHEM.11 A3D positive residues inside the signal peptide → 80 (the Spec A QC leg's ground)",
     SUMMARY, rf"\*\*1–16 hold {N} of the construct's [\d]+\*\* positively-scoring",
     A3D, lambda d: d["signal_peptide"]["n_positive"], 0.0),
    ("CHEM.11 A3D positive residues in the whole construct → 80",
     SUMMARY, rf"\*\*1–16 hold [\d]+ of the construct's {N}\*\* positively-scoring",
     A3D, lambda d: d["signal_peptide"]["n_positive_whole_protein"], 0.0),
]

# ── HW.53 R_Ω bench sheet ⟷ script 84 (2026-10-11): budgets per R_int reading, the geometry, requirements per kΩ ──
BENCH_R_OMEGA = "docs/protocols/ebfc/cathode_ionic_path_bench.md"
R_OMEGA = "kinetics/cathode_ionic_path.json"


def _pvi_pair(d, x, ref):
    return next(p for p in d["pvi_series"]["pairs"] if (p["x"], p["ref"]) == (x, ref))


def _pvi_gap(d, x, ref):   # ours − measured, mV per substituent
    p = _pvi_pair(d, x, ref)
    return p["ours_mV"] - p["measured_mV"]


def _pvi_ratio(d, x, ref):
    return _pvi_pair(d, x, ref)["ours_over_measured"]


def _centre_split(d):
    """(functional, basis) part of the Me−H shift per substituent, mV: B3LYP/6-31G(d) → ωB97X/6-31G(d) → ωB97X/def2-TZVP."""
    pts = {p["name"]: p for p in d["vs_b3lyp"]["centre_decomposition"]["points"]}
    f = lambda k: -(pts["dmbpy"][k] - pts["bpy"][k]) / 4 * 1000   # noqa: E731
    return f("wb97x_631gd_eV") - f("b3lyp_631gd_eV"), f("wb97x_def2tzvp_eV") - f("wb97x_631gd_eV")


def _budget(d, cell, reading):
    v, vin = cell.split("/")
    (row,) = [r for r in d["budgets"] if f"{r['V_OC_mV']:.0f}" == v and r["VIN_CS"] == vin]
    return row["budget_kohm"][reading]


def _pk(d, key):
    return d["requirements_per_kohm_of_budget"][key]


def _lit(d, species, element):
    (p,) = [p for p in d["literature_points"] if p["species"] == species and p["element"] == element]
    return p["element_ohm"]


CHECKS += [
    ("R_Ω budget 700/typ at the model low end → 84", BENCH_R_OMEGA, rf"трьох клітинках стелі з чотирьох \(\*\*\+{N} ·",
     R_OMEGA, lambda d: _budget(d, "700/typ", "models_31_31b"), 0.005),
    ("R_Ω budget 800/typ at the model low end → 84", BENCH_R_OMEGA, rf"з чотирьох \(\*\*\+[\d.]+ · \+{N} ·",
     R_OMEGA, lambda d: _budget(d, "800/typ", "models_31_31b"), 0.005),
    ("R_Ω budget 800/max at the model low end → 84", BENCH_R_OMEGA, rf"з чотирьох \(\*\*\+[\d.]+ · \+[\d.]+ · \+{N} кΩ\*\*\)",
     R_OMEGA, lambda d: _budget(d, "800/max", "models_31_31b"), 0.005),
    ("R_Ω budget 800/typ at the prose estimate's low end → 84", BENCH_R_OMEGA, rf"на нижньому кінці оцінки — в одній \(\*\*\+{N} кΩ\*\*\)",
     R_OMEGA, lambda d: _budget(d, "800/typ", "prose_estimate_02_03"), 0.005),
    ("R_Ω model R_int low end → 31/31b via 84", BENCH_R_OMEGA, rf"дають ≈ {N} … [\d.]+ кΩ, а оцінка",
     R_OMEGA, lambda d: d["electrode_r_int_readings"]["models_31_31b_kohm"][0], 0.005),
    ("R_Ω model R_int high end → 31/31b via 84", BENCH_R_OMEGA, rf"дають ≈ [\d.]+ … {N} кΩ, а оцінка",
     R_OMEGA, lambda d: d["electrode_r_int_readings"]["models_31_31b_kohm"][1], 50.0),   # two significant figures
    ("R_Ω anode depth below the cambium (low) → 84", BENCH_R_OMEGA, rf"\| {N}–[\d.]+ мм = втулка 50 мм",
     R_OMEGA, lambda d: 1e3 * min(d["factors"]["1_sapwood_per_m"]["depth_below_cambium_m"]), 0.05),
    ("R_Ω anode depth below the cambium (high) → 84", BENCH_R_OMEGA, rf"\| [\d.]+–{N} мм = втулка 50 мм",
     R_OMEGA, lambda d: 1e3 * max(d["factors"]["1_sapwood_per_m"]["depth_below_cambium_m"]), 0.05),
    ("R_Ω anode exposed length → 84", BENCH_R_OMEGA, rf"поза втулкою \*\*{N} мм\*\*",
     R_OMEGA, lambda d: 1e3 * d["geometry"]["anode_exposed_length_m"][0], 0.05),
    ("R_Ω sapwood factor (low) → 84", BENCH_R_OMEGA, rf"вросла в зазор \(Ø11\) \| {N}–[\d.]+ /м",
     R_OMEGA, lambda d: d["factors"]["1_sapwood_per_m"]["bracket"][0], 0.005),
    ("R_Ω sapwood factor (high) → 84", BENCH_R_OMEGA, rf"вросла в зазор \(Ø11\) \| [\d.]+–{N} /м",
     R_OMEGA, lambda d: d["factors"]["1_sapwood_per_m"]["bracket"][1], 0.005),
    *[(f"R_Ω sapwood factor, {st} {end} → 84", BENCH_R_OMEGA, anchor, R_OMEGA,
       lambda d, st=st, i=i: d["factors"]["1_sapwood_per_m"]["states"][st]["bracket"][i], 0.005)
      for st, end, i, anchor in (("sap_gap", "low", 0, rf"\(сік у зазорі {N}–[\d.]+ ·"),
                                 ("sap_gap", "high", 1, rf"\(сік у зазорі [\d.]+–{N} ·"),
                                 ("ingrown", "low", 0, rf"· вросла {N}–[\d.]+\)"),
                                 ("ingrown", "high", 1, rf"· вросла [\d.]+–{N}\)"))],
    ("R_Ω sapwood requirement per kΩ → 84", BENCH_R_OMEGA, rf"[\d.]+\) \| ρ ≤ \*\*{N}\*\* Ω·м \|",
     R_OMEGA, lambda d: _pk(d, "1_sapwood_rho_max_ohm_m"), 0.5),
    # the share of layer 1 a V+ in the wood leaves out (84 `vplus_share_of_layer_1_left_out`, min–max over the corners, %)
    *[(f"R_Ω V+ drop-out at {mm} mm, {end} → 84", BENCH_R_OMEGA, anchor, R_OMEGA,
       lambda d, mm=mm, f=f: 100 * f(row[f"{mm}mm"] for row in d["vplus_share_of_layer_1_left_out"].values()), 0.5)
      for mm, end, f, anchor in ((1, "low", min, rf"на 1 мм губиться {N}–[\d.]+ %"), (1, "high", max, rf"на 1 мм губиться [\d.]+–{N} %"),
                                 (2, "low", min, rf"на 2 мм — {N}–[\d.]+ %"), (2, "high", max, rf"на 2 мм — [\d.]+–{N} %"),
                                 (3, "low", min, rf"на 3 мм — {N}–[\d.]+ %"), (3, "high", max, rf"на 3 мм — [\d.]+–{N} %"))],
    ("R_Ω inner-bark requirement per kΩ at t = 3 mm → 84", BENCH_R_OMEGA, rf"при t = 3 мм: ρ ≤ \*\*{N}\*\*",
     R_OMEGA, lambda d: _pk(d, "2_inner_bark_sheet_max_ohm_sq") * d["factors"]["2_inner_bark_sheet"]["thickness_m"], 0.05),
    ("R_Ω dead-bark requirement per kΩ → 84", BENCH_R_OMEGA, rf"ρ ≤ \*\*{N}\*\* Ω·м \(поблажлива",
     R_OMEGA, lambda d: _pk(d, "3_dead_bark_rho_max_ohm_m"), 0.5),
    ("R_Ω film requirement per kΩ → 84", BENCH_R_OMEGA, rf"\| R□ ≤ {N}·10⁵ Ω/□ \|",   # the §2.2 table cell — the package of 2026-10-18 quotes the same number twice
     R_OMEGA, lambda d: _pk(d, "4_film_sheet_max_ohm_sq") / 1e5, 0.005),
    ("R_Ω catalyst-layer requirement per kΩ → 84", BENCH_R_OMEGA, rf"R□,cl·h_band ≤ {N} Ω·м",
     R_OMEGA, lambda d: _pk(d, "5_layer_sheet_x_band_height_max_ohm"), 0.05),
    ("R_Ω Scots-pine sapwood element (low) → 84", BENCH_R_OMEGA, rf"вересень, 8⅓ Гц\) \| {N}–[\d.]+ \|",
     R_OMEGA, lambda d: _lit(d, "Pinus sylvestris", "1_sapwood")[0] / 1e3, 0.005),
    ("R_Ω Scots-pine sapwood element (high) → 84", BENCH_R_OMEGA, rf"вересень, 8⅓ Гц\) \| [\d.]+–{N} \|",
     R_OMEGA, lambda d: _lit(d, "Pinus sylvestris", "1_sapwood")[1] / 1e3, 0.005),
    ("R_Ω P. cembra element (high) → 84", BENCH_R_OMEGA, rf"мерзлий стовбур\) \| [\d.]+–{N} \|",
     R_OMEGA, lambda d: _lit(d, "Pinus cembra", "1_sapwood")[1] / 1e3, 0.005),
    ("R_Ω stemflow film element (low) → 84", BENCH_R_OMEGA, rf"буфер 0\.5 … 6\.2 мм \| {N}–[\d.]+ \|",
     R_OMEGA, lambda d: _lit(d, "Pinus sylvestris", "4_film")[0] / 1e3, 0.005),
    ("R_Ω stemflow film element (high) → 84", BENCH_R_OMEGA, rf"буфер 0\.5 … 6\.2 мм \| [\d.]+–{N} \|",
     R_OMEGA, lambda d: _lit(d, "Pinus sylvestris", "4_film")[1] / 1e3, 0.5),
    ("R_Ω Scots-pine sapwood + film floor → 84", BENCH_R_OMEGA, rf"найпоблажливішому прочитанні дають {N} кΩ\*\*",
     R_OMEGA, lambda d: d["scots_pine_sapwood_plus_film_lenient_ohm"] / 1e3, 0.005),
]

# ── HW.5.IS coin half of the ΔpH leg ⟷ script 85 (2026-10-12): the face pH of the coin electrodes in the media the letter
# allows. The tracker's ⚖️ leg carries a dated snapshot of these for the decision — its home is SUMMARY, and 00_07 sits
# outside the smoke workflow's paths on purpose (it changes on nearly every push). ──
FACE_PH = "kinetics/electrode_interfacial_ph.json"
EBFC = "docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md"
_ANODE_RUNS = ("ceiling_hold", "ph_bracket_hold_low", "ph_bracket_hold_high")


def _anode(d, edge, runs, end, key="delta_star_um"):
    """δ* (µm) at a face-pH edge over the named current readings — the low end of the lowest or the high end of the highest."""
    vals = [d["anode"]["delta_star"][f"face_pH_{edge}"][r][key][end] for r in runs]
    return min(vals) if end == 0 else max(vals)


def _medium(d, name):
    return d["cathode"]["media"][name]


def _liu(d, key, i=None):
    v = d["checks"]["liu_fem_point"][key]["0.077"]
    return v if i is None else v[i]


CHECKS += [
    ("face pH: Liu conserving film → 85", SUMMARY, rf"zero net citrate flux gives \*\*{N}\*\*",
     FACE_PH, lambda d: _liu(d, "film_pH_centre"), 0.0005),
    ("face pH: Liu single-D bracket low → 85", SUMMARY, rf"brackets it \({N}–[\d.]+\)",
     FACE_PH, lambda d: _liu(d, "single_D_bracket_pH", 0), 0.0005),
    ("face pH: Liu single-D bracket high → 85", SUMMARY, rf"brackets it \([\d.]+–{N}\)",
     FACE_PH, lambda d: _liu(d, "single_D_bracket_pH", 1), 0.0005),
    ("face pH: Liu δ band low → 85", SUMMARY, rf"holds δ between {N} and [\d.]+ of the radius",
     FACE_PH, lambda d: d["checks"]["liu_fem_point"]["passing_delta_over_radius"][0], 0.005),
    ("face pH: Liu δ band high → 85", SUMMARY, rf"holds δ between [\d.]+ and {N} of the radius",
     FACE_PH, lambda d: d["checks"]["liu_fem_point"]["passing_delta_over_radius"][1], 0.005),
    ("face pH: film exponent, stagnant low corner → 85", SUMMARY, rf"moves the low corner {N} → [\d.]+ → [\d.]+",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6_by_film"]["stagnant"][0], 0.005),
    ("face pH: film exponent, Levich low corner → 85", SUMMARY, rf"moves the low corner [\d.]+ → {N} → [\d.]+",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6_by_film"]["Levich"][0], 0.005),
    ("face pH: film exponent, transient low corner → 85", SUMMARY, rf"moves the low corner [\d.]+ → [\d.]+ → {N}",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6_by_film"]["transient"][0], 0.005),
    ("face pH: free H⁺ share at the sap 4.5 crossing → 85", SUMMARY, rf"carries most of\nthe supply \({N} % at the low-D corner",
     FACE_PH, lambda d: 100 * d["cathode"]["free_H_share_of_supply_sap_pH4.5_low_D"], 0.5),
    ("face pH: anode check-medium ionic strength low → 85", EBFC, rf"іонна сила теж рухається \({N} → [\d.]+ моль/л",
     FACE_PH, lambda d: d["anode_check_medium"]["ionic_strength_mol_l"][0], 0.00005),
    ("face pH: anode check-medium ionic strength high → 85", EBFC, rf"іонна сила теж рухається \([\d.]+ → {N} моль/л",
     FACE_PH, lambda d: d["anode_check_medium"]["ionic_strength_mol_l"][1], 0.0005),
    ("face pH: sap 4.5 f low → 85", SUMMARY, rf"the sap brought to 4\.5 \| \*\*{N}–",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6"][0], 0.005),
    ("face pH: sap 4.5 f high → 85", SUMMARY, rf"the sap brought to 4\.5 \| \*\*[\d.]+–{N}\*\*",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6"][1], 0.005),
    ("face pH: sap 4.5 citrate-like low → 85", SUMMARY, rf"citrate-like D {N}–[\d.]+, succinate-like",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6_by_D_end"]["citrate_like"][0], 0.005),
    ("face pH: sap 4.5 citrate-like high → 85", SUMMARY, rf"citrate-like D [\d.]+–{N}, succinate-like",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6_by_D_end"]["citrate_like"][1], 0.005),
    ("face pH: sap 4.5 succinate-like low → 85", SUMMARY, rf"succinate-like {N}–[\d.]+ \|",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6_by_D_end"]["succinate_like"][0], 0.005),
    ("face pH: sap 4.5 succinate-like high → 85", SUMMARY, rf"succinate-like [\d.]+–{N} \|",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["f_pH6_by_D_end"]["succinate_like"][1], 0.005),
    ("face pH: sap 4.5 corners crossing → 85", SUMMARY, rf"crosses pH 6 first in {N} of [\d]+ corners",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["rows_crossing_pH6_below_O2_limit"], 0.0),
    ("face pH: sap 4.5 corners total → 85", SUMMARY, rf"crosses pH 6 first in [\d]+ of {N} corners",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["rows"], 0.0),
    ("face pH: sap 4.5 malate spent first → 85", SUMMARY, rf"and in {N} corners the malate is spent first",
     FACE_PH, lambda d: _medium(d, "sap_pH4.5")["rows_beyond_model_at_O2_limit"], 0.0),
    ("face pH: sap 5.75 f low → 85", SUMMARY, rf"one compartment\) \| \*\*{N}–",
     FACE_PH, lambda d: _medium(d, "sap_pH5.75")["f_pH6"][0], 0.005),
    ("face pH: sap 5.75 f high → 85", SUMMARY, rf"one compartment\) \| \*\*[\d.]+–{N}\*\*",
     FACE_PH, lambda d: _medium(d, "sap_pH5.75")["f_pH6"][1], 0.006),   # 0.095 printed at two decimals
    ("face pH: buffered f low → 85", SUMMARY, rf"malic acid 10 mM, pH 4\.5 \| \*\*{N}–",
     FACE_PH, lambda d: _medium(d, "buffered_pH4.5")["f_pH6"][0], 0.005),
    ("face pH: buffered f high → 85", SUMMARY, rf"malic acid 10 mM, pH 4\.5 \| \*\*[\d.]+–{N}\*\*",
     FACE_PH, lambda d: _medium(d, "buffered_pH4.5")["f_pH6"][1], 0.005),
    ("face pH: buffered face at the limit low → 85", SUMMARY, rf"never crosses; the face is at pH {N}–",
     FACE_PH, lambda d: _medium(d, "buffered_pH4.5")["face_pH_at_O2_limit_where_reached"][0], 0.05),
    ("face pH: buffered face at the limit high → 85", SUMMARY, rf"never crosses; the face is at pH [\d.]+–{N} \|",
     FACE_PH, lambda d: _medium(d, "buffered_pH4.5")["face_pH_at_O2_limit_where_reached"][1], 0.05),
    ("face pH: load B δ* low → 85", SUMMARY, rf"once\s+δ ≥ {N}–[\d.]+ mm",
     FACE_PH, lambda d: d["cathode"]["load_B_delta_star_mm_sap_pH4.5"][0], 0.005),
    ("face pH: load B δ* high → 85", SUMMARY, rf"once\s+δ ≥ [\d.]+–{N} mm",
     FACE_PH, lambda d: d["cathode"]["load_B_delta_star_mm_sap_pH4.5"][1], 0.05),
    ("face pH: anode ceiling current → 85", SUMMARY, rf"predicted current for the hold \({N} µA/cm²",
     FACE_PH, lambda d: d["anode"]["delta_star"]["face_pH_4.5"]["ceiling_hold"]["j_uA_cm2"], 0.5),
    ("face pH: anode δ* at the ceiling, low → 85", SUMMARY, rf"\*\*{N}–[\d.]+ µm\*\* \([\d.]+–[\d.]+ µm at one proton",
     FACE_PH, lambda d: _anode(d, 4.5, ("ceiling_hold",), 0), 0.5),
    ("face pH: anode δ* at the ceiling, high → 85", SUMMARY, rf"\*\*[\d.]+–{N} µm\*\* \([\d.]+–[\d.]+ µm at one proton",
     FACE_PH, lambda d: _anode(d, 4.5, ("ceiling_hold",), 1), 0.5),
    ("face pH: anode δ* at the ceiling, n=1 low → 85", SUMMARY, rf"\({N}–[\d.]+ µm at one proton per electron\)",
     FACE_PH, lambda d: _anode(d, 4.5, ("ceiling_hold",), 0, "delta_star_um_n1"), 0.5),
    ("face pH: anode bracket current low → 85", SUMMARY, rf"beside that ceiling \({N}–[\d.]+ µA/cm²\)",
     FACE_PH, lambda d: d["anode"]["delta_star"]["face_pH_4.5"]["ph_bracket_hold_low"]["j_uA_cm2"], 0.5),
    ("face pH: anode bracket current high → 85", SUMMARY, rf"beside that ceiling \([\d.]+–{N} µA/cm²\)",
     FACE_PH, lambda d: d["anode"]["delta_star"]["face_pH_4.5"]["ph_bracket_hold_high"]["j_uA_cm2"], 0.5),
    ("face pH: anode δ* at the bracket, low → 85", SUMMARY, rf"µA/cm²\) once δ\s+exceeds \*\*{N}–",
     FACE_PH, lambda d: _anode(d, 4.5, _ANODE_RUNS[1:], 0), 0.5),
    ("face pH: anode δ* at the bracket, high → 85", SUMMARY, rf"µA/cm²\) once δ\s+exceeds \*\*[\d.]+–{N} µm",
     FACE_PH, lambda d: _anode(d, 4.5, _ANODE_RUNS[1:], 1), 0.5),
    ("face pH: anode below pH 5.5, low → 85", SUMMARY, rf"once δ exceeds {N}–[\d.]+ µm\. Glucose",
     FACE_PH, lambda d: _anode(d, 5.5, _ANODE_RUNS, 0), 0.5),
    ("face pH: anode below pH 5.5, high → 85", SUMMARY, rf"once δ exceeds [\d.]+–{N} µm\. Glucose",
     FACE_PH, lambda d: _anode(d, 5.5, _ANODE_RUNS, 1), 0.5),
    ("face pH: unstirred δ low → 85", SUMMARY, rf"Unstirred aqueous layers are {N}–[\d.]+ µm",
     FACE_PH, lambda d: d["constants"]["delta_natural_convection_um"][0], 0.0),
    ("face pH: unstirred δ high → 85", SUMMARY, rf"Unstirred aqueous layers are [\d.]+–{N} µm",
     FACE_PH, lambda d: d["constants"]["delta_natural_convection_um"][1], 0.0),
    ("face pH: 01_03 §3.5 anode δ* low → 85", EBFC, rf"щойно дифузійний шар товщий за {N}–[\d.]+ мкм, а нерозмішувана",
     FACE_PH, lambda d: _anode(d, 4.5, _ANODE_RUNS, 0), 0.5),
    ("face pH: 01_03 §3.5 anode δ* high → 85", EBFC, rf"щойно дифузійний шар товщий за [\d.]+–{N} мкм, а нерозмішувана",
     FACE_PH, lambda d: _anode(d, 4.5, _ANODE_RUNS, 1), 0.5),
    ("face pH: 01_03 §3.5 unstirred δ low → 85", EBFC, rf"нерозмішувана комірка дає {N}–[\d.]+ мкм",
     FACE_PH, lambda d: d["constants"]["delta_natural_convection_um"][0], 0.0),
    # ── the anchor's anode with sap in its gap (2026-10-17) — conditional; the currents are upper bounds ──
    ("face pH: anchor anode envelope area, pine → 85", SUMMARY, rf"envelope Ø11, \*\*{N} cm²\*\*",
     FACE_PH, lambda d: _pine85(d)["geometry"]["envelope_lateral_area_cm2"], 0.05),
    ("face pH: anchor anode gap, pine → 85", SUMMARY, rf"the gap is \*\*{N} mm\*\*",
     FACE_PH, lambda d: _pine85(d)["geometry"]["gap_mm"], 0.05),
    ("face pH: anchor anode annulus film, pine → 85", SUMMARY, rf"r_a·ln\(r_b/r_a\) = \*\*{N} mm\*\*",
     FACE_PH, lambda d: 10 * _pine85(d)["geometry"]["annulus_delta_cm"], 0.005),
    ("face pH: anchor cold-start draw, worst-case column → 85", SUMMARY, rf"typical and \*\*{N}\*\* µA at the worst-case column",
     FACE_PH, lambda d: d["anchor_anode_sap_gap"]["cold_start_uA"]["worst"], 0.05),
    ("face pH: anchor anode current to pH 5.5, pine, low → 85", SUMMARY, rf"kinetic bracket \(pH 5\.5\) at \*\*{N}–[\d.]+ µA\*\*",
     FACE_PH, lambda d: _pine85(d)["face_pH_5.5"]["i_anode_uA"][0], 0.05),
    ("face pH: anchor anode current to pH 5.5, pine, high → 85", SUMMARY, rf"kinetic bracket \(pH 5\.5\) at \*\*[\d.]+–{N} µA\*\*",
     FACE_PH, lambda d: _pine85(d)["face_pH_5.5"]["i_anode_uA"][1], 0.05),
    ("face pH: anchor anode current to pH 4.5, pine, low → 85", SUMMARY, rf"stability band \(pH 4\.5\) at \*\*{N}–[\d.]+ µA\*\*",
     FACE_PH, lambda d: _pine85(d)["face_pH_4.5"]["i_anode_uA"][0], 0.05),
    ("face pH: anchor anode current to pH 4.5, pine, high → 85", SUMMARY, rf"stability band \(pH 4\.5\) at \*\*[\d.]+–{N} µA\*\*",
     FACE_PH, lambda d: _pine85(d)["face_pH_4.5"]["i_anode_uA"][1], 0.05),
    # ⊕ 2026-10-18 (⚖️ founder): broadleaf and oak in their own sap — the beech point of 67 Q8
    ("face pH: anchor anode current to pH 4.5, broadleaf in its own sap, low → 85", SUMMARY,
     rf"starts at \*\*{N}\*\* µA in its own", FACE_PH,
     lambda d: d["anchor_anode_sap_gap"]["by_sku"]["anchor_zone1_broadleaf"]["face_pH_4.5"]["i_anode_uA"][0], 0.05),
    ("face pH: anchor anode current to pH 5.5, oak in beech sap, low → 85", SUMMARY, rf"oak only in some, from \*\*{N}\*\* µA",
     FACE_PH, lambda d: d["anchor_anode_sap_gap"]["by_sku"]["anchor_zone1_oak"]["face_pH_5.5"]["i_anode_uA"][0], 0.05),
    ("sap: beech point pH (Q8) → 67", SUMMARY, rf"Glavac et al\. 1990; pH \*\*{N}\*\*",
     SAP, lambda d: d["q8_broadleaf_point"]["conditions"]["setpoint"]["ph"], 0.0),
    ("sap: beech point buffer capacity (Q8) → 67", SUMMARY, rf"buffer \*\*{N}\*\* mM/pH — ×",
     SAP, lambda d: d["q8_broadleaf_point"]["conditions"]["setpoint"]["buffer_capacity_mM_per_pH_25c"], 0.0005),
    ("sap: beech point buffer over the pine point (Q8) → 67", SUMMARY, rf"— ×\*\*{N}\*\* the pine point's",
     SAP, lambda d: d["q8_broadleaf_point"]["against_pine_point"]["buffer_capacity_ratio"], 0.005),
    ("sap: beech summer acid dates, lowest median (Q8) → 67", SUMMARY, rf"medians \*\*{N}\*\*–\*\*[\d.]+\*\*, the lowest tree",
     SAP, lambda d: min(d["q8_broadleaf_point"]["summer_acid_dates"]["ph_medians"]), 0.0),
    ("sap: beech summer acid dates, highest median (Q8) → 67", SUMMARY, rf"medians \*\*[\d.]+\*\*–\*\*{N}\*\*, the lowest tree",
     SAP, lambda d: max(d["q8_broadleaf_point"]["summer_acid_dates"]["ph_medians"]), 0.0),
    ("sap: oak's own trunk sap pH, high (Van Die 1975) → 67", SUMMARY, rf"late October\): pH \*\*[\d.]+\*\*–\*\*{N}\*\*",
     SAP, lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["ph_range"][1], 0.0),
    ("sap: beech September–October pH, high (Q8) → 67", SUMMARY, rf"September–October stands at \*\*[\d.]+\*\*–\*\*{N}\*\*",
     SAP, lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["beech_same_season_ph"][-1], 0.0),
    ("face pH: oak's own sap above the stability edge, low → 85", SUMMARY, rf"\*\*{N}\*\*–[\d.]+ above the stability edge",
     FACE_PH, lambda d: d["anchor_anode_sap_gap"]["by_sku"]["anchor_zone1_oak"]["own_sap_reading"]["minus_stability_edge"][0], 0.0),
    ("face pH: oak's own sap above the stability edge, high → 85", SUMMARY, rf"\*\*[\d.]+\*\*–{N} above the stability edge",
     FACE_PH, lambda d: d["anchor_anode_sap_gap"]["by_sku"]["anchor_zone1_oak"]["own_sap_reading"]["minus_stability_edge"][1], 0.0),
    ("sap: beech summer acid dates, lowest tree (Q8) → 67", SUMMARY, rf"the lowest tree \*\*{N}\*\* — the bulk",
     SAP, lambda d: d["q8_broadleaf_point"]["summer_acid_dates"]["lowest_tree_ph"], 0.0),
    # 01_02 §2.1 ⊕ — the broadleaf point as canon states it
    ("sap 01_02: beech point Ca (Q8) → 67", METALLURGY, rf"Точка: Ca \*\*{N}\*\* мМ", SAP,
     lambda d: d["q8_broadleaf_point"]["recipe_mM"]["cacl2"], 0.0),
    ("sap 01_02: beech point Mg (Q8) → 67", METALLURGY, rf"· Mg \*\*{N}\*\* мМ · K", SAP,
     lambda d: d["q8_broadleaf_point"]["recipe_mM"]["mgso4"], 0.0),
    ("sap 01_02: beech point K, the geometric mid KOH is solved to (Q8) → 67", METALLURGY,
     rf"· K \*\*{N}\*\* мМ \(геометрична середина; його дає KOH\)", SAP,
     lambda d: d["q8_broadleaf_point"]["measured"]["geometric_mid_mM"]["K"], 0.005),
    ("sap 01_02: beech point malic, solved (Q8) → 67", METALLURGY, rf"малат \*\*{N}\*\* мМ \(виведений\)", SAP,
     lambda d: d["q8_broadleaf_point"]["recipe_mM"]["malic"], 0.0),
    ("sap 01_02: beech point pH (Q8) → 67", METALLURGY, rf"pH \*\*{N}\*\*\s*\(медіана медіан\)", SAP,
     lambda d: d["q8_broadleaf_point"]["conditions"]["setpoint"]["ph"], 0.0),
    ("sap 01_02: beech summer acid dates, lowest median (Q8) → 67", METALLURGY, rf"медіани pH \*\*{N}–[\d.]+\*\*", SAP,
     lambda d: min(d["q8_broadleaf_point"]["summer_acid_dates"]["ph_medians"]), 0.0),
    ("sap 01_02: beech summer acid dates, highest median (Q8) → 67", METALLURGY, rf"медіани pH \*\*[\d.]+–{N}\*\*", SAP,
     lambda d: max(d["q8_broadleaf_point"]["summer_acid_dates"]["ph_medians"]), 0.0),
    ("sap 01_02: beech lowest tree (Q8) → 67", METALLURGY, rf"найкисліше дерево \*\*{N}\*\*", SAP,
     lambda d: d["q8_broadleaf_point"]["summer_acid_dates"]["lowest_tree_ph"], 0.0),
    ("sap 01_02: beech dates read (Q8) → 67", METALLURGY, rf"по \*\*{N}\*\* датах", SAP,
     lambda d: len(d["q8_broadleaf_point"]["measured"]["medians_by_date"]), 0.0),
    ("sap 01_02: oak's own sap pH, low (Van Die 1975) → 67", METALLURGY, rf"стовбура без тиску: pH \*\*{N}–[\d.]+\*\*", SAP,
     lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["ph_range"][0], 0.0),
    ("sap 01_02: beech September–October pH, low (Q8) → 67", METALLURGY, rf"стоїть на \*\*{N}–[\d.]+\*\*", SAP,
     lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["beech_same_season_ph"][0], 0.0),
    ("sap 01_02: oak's own sap pH, high (Van Die 1975) → 67", METALLURGY, rf"стовбура без тиску: pH \*\*[\d.]+–{N}\*\*", SAP,
     lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["ph_range"][1], 0.0),
    ("sap 01_02: beech September–October pH, high (Q8) → 67", METALLURGY, rf"стоїть на \*\*[\d.]+–{N}\*\*", SAP,
     lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["beech_same_season_ph"][-1], 0.0),
    ("sap: oak's own trunk sap pH, low (Van Die 1975) → 67", SUMMARY, rf"late October\): pH \*\*{N}\*\*–",
     SAP, lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["ph_range"][0], 0.0),
    ("sap: beech September–October pH, low (Q8) → 67", SUMMARY, rf"September–October stands at \*\*{N}\*\*–",
     SAP, lambda d: d["q8_broadleaf_point"]["oak_own_sap_reading"]["beech_same_season_ph"][0], 0.0),
]

# ── HW.6 frost, real cloud (2026-10-12): ERA5 cover weighs 79's sky ends — canon 01_04 §3.1 ⊕ ──
_C79 = lambda d, name, cp="tied": d["real_cloud"]["regimes"][name][cp]  # noqa: E731


def _c79_month(d, month, key):
    row = next(r for r in d["real_cloud"]["runs"]
               if (r["regime"], r["coupling"], r["wind_k"], r["bark_side"]) == ("cloud_b82_diffuse_sun", "tied", 0.0, "thin"))
    return row["by_month"][month][key]


def _share(d, name, end, cp="tied"):
    return _C79(d, name, cp)["colder_share_range"][end] * 100


def _cold(d, name, key, end):
    return _C79(d, name)["cold_days"][key][end] * (100 if key == "colder_share_range" else 1)


CHECKS += [
    ("HW.6 · real cloud: winter median cover → 79", CODIT, rf"медіана покриву за зимові години \*\*{N}\*\*",
     FLANGE_FROST, lambda d: d["real_cloud"]["climate"]["winter_hours_median"], 0.006),
    ("HW.6 · real cloud: winter hours above 0.8 → 79", CODIT, rf"вище 0\.8 — у \*\*{N} %\*\*",
     FLANGE_FROST, lambda d: d["real_cloud"]["climate"]["winter_share_above_0.8"] * 100, 0.6),
    ("HW.6 · real cloud: winter hours below 0.2 → 79", CODIT, rf"нижче 0\.2 — у \*\*{N} %\*\*",
     FLANGE_FROST, lambda d: d["real_cloud"]["climate"]["winter_share_below_0.2"] * 100, 0.6),
    ("HW.6 · real cloud: linear, no sun, low → 79", CODIT, rf"лінійної суміші — \*\*{N}–[\d.]+ %\*\* без сонця",
     FLANGE_FROST, lambda d: _share(d, "cloud_linear_no_sun", 0), 0.6),
    ("HW.6 · real cloud: linear, no sun, high → 79", CODIT, rf"лінійної суміші — \*\*[\d.]+–{N} %\*\* без сонця",
     FLANGE_FROST, lambda d: _share(d, "cloud_linear_no_sun", 1), 0.6),
    ("HW.6 · real cloud: linear, diffuse sun, low → 79", CODIT, rf"й \*\*{N}–[\d.]+ %\*\* із розсіяним сонцем ERA5",
     FLANGE_FROST, lambda d: _share(d, "cloud_linear_diffuse_sun", 0), 0.6),
    ("HW.6 · real cloud: linear, diffuse sun, high → 79", CODIT, rf"й \*\*[\d.]+–{N} %\*\* із розсіяним сонцем ERA5",
     FLANGE_FROST, lambda d: _share(d, "cloud_linear_diffuse_sun", 1), 0.6),
    ("HW.6 · real cloud: linear, diffuse sun, median low → 79", CODIT, rf"\(медіана \*\*\+{N}…{_NN} K\*\*\); за B82",
     FLANGE_FROST, lambda d: _C79(d, "cloud_linear_diffuse_sun")["median_K_range"][0], 0.005),
    ("HW.6 · real cloud: linear, diffuse sun, median high → 79", CODIT, rf"\(медіана \*\*{_NN}…\+{N} K\*\*\); за B82",
     FLANGE_FROST, lambda d: _C79(d, "cloud_linear_diffuse_sun")["median_K_range"][1], 0.005),
    ("HW.6 · real cloud: B82, no sun, low → 79", CODIT, rf"за B82 — \*\*{N}–[\d.]+ %\*\* і",
     FLANGE_FROST, lambda d: _share(d, "cloud_b82_no_sun", 0), 0.6),
    ("HW.6 · real cloud: B82, no sun, high → 79", CODIT, rf"за B82 — \*\*[\d.]+–{N} %\*\* і",
     FLANGE_FROST, lambda d: _share(d, "cloud_b82_no_sun", 1), 0.6),
    ("HW.6 · real cloud: B82, diffuse sun, low → 79", CODIT, rf"%\*\* і \*\*{N}–[\d.]+ %\*\*\. Смуга",
     FLANGE_FROST, lambda d: _share(d, "cloud_b82_diffuse_sun", 0), 0.6),
    ("HW.6 · real cloud: B82, diffuse sun, high → 79", CODIT, rf"%\*\* і \*\*[\d.]+–{N} %\*\*\. Смуга",
     FLANGE_FROST, lambda d: _share(d, "cloud_b82_diffuse_sun", 1), 0.6),
    ("HW.6 · real cloud: decoupled, linear, diffuse sun, low → 79", CODIT, rf"із розсіяним сонцем — \*\*{N}–[\d.]+ %\*\* за",
     FLANGE_FROST, lambda d: _share(d, "cloud_linear_diffuse_sun", 0, "decoupled"), 0.6),
    ("HW.6 · real cloud: decoupled, linear, diffuse sun, high → 79", CODIT, rf"із розсіяним сонцем — \*\*[\d.]+–{N} %\*\* за",
     FLANGE_FROST, lambda d: _share(d, "cloud_linear_diffuse_sun", 1, "decoupled"), 0.6),
    ("HW.6 · real cloud: cold days, linear, diffuse sun, low → 79", CODIT, rf"холодніше в \*\*{N}–[\d.]+ %\*\* із них",
     FLANGE_FROST, lambda d: _cold(d, "cloud_linear_diffuse_sun", "colder_share_range", 0), 0.6),
    ("HW.6 · real cloud: cold days, linear, diffuse sun, high → 79", CODIT, rf"холодніше в \*\*[\d.]+–{N} %\*\* із них",
     FLANGE_FROST, lambda d: _cold(d, "cloud_linear_diffuse_sun", "colder_share_range", 1), 0.6),
    ("HW.6 · real cloud: cold days, B82, no sun, high → 79", CODIT, rf"у \*\*0–{N} %\*\* \(медіана",
     FLANGE_FROST, lambda d: _cold(d, "cloud_b82_no_sun", "colder_share_range", 1), 0.6),
    ("HW.6 · real cloud: cold days, B82, no sun, median low → 79", CODIT, rf"\(медіана \*\*{N}…{_NN} K\*\*\)\. Єдиний",
     FLANGE_FROST, lambda d: _cold(d, "cloud_b82_no_sun", "median_K_range", 0), 0.005),
    ("HW.6 · real cloud: cold days, B82, no sun, median high → 79", CODIT, rf"\(медіана \*\*{_NN}…\+{N} K\*\*\)\. Єдиний",
     FLANGE_FROST, lambda d: _cold(d, "cloud_b82_no_sun", "median_K_range", 1), 0.005),
    ("HW.6 · real cloud: December median → 79", CODIT, rf"\*\*\+{N} K\*\* медіани у грудні",
     FLANGE_FROST, lambda d: _c79_month(d, "12", "median"), 0.005),
    ("HW.6 · real cloud: March median → 79", CODIT, rf"\*\*\+{N} K\*\* у березні",
     FLANGE_FROST, lambda d: _c79_month(d, "3", "median"), 0.005),
    ("HW.6 · real cloud: March colder share → 79", CODIT, rf"у березні \(\*\*{N} %\*\* холодніших діб\)",
     FLANGE_FROST, lambda d: _c79_month(d, "3", "colder_share") * 100, 0.6),
    ("HW.6 · real cloud: April median → 79", CODIT, rf"\*\*\+{N} K\*\* у квітні",
     FLANGE_FROST, lambda d: _c79_month(d, "4", "median"), 0.005),
    ("HW.6 · real cloud: April colder share → 79", CODIT, rf"у квітні \(\*\*{N} %\*\* із",
     FLANGE_FROST, lambda d: _c79_month(d, "4", "colder_share") * 100, 0.6),
    ("HW.6 · real cloud: April frost days → 79", CODIT, rf"%\*\* із {N} морозних діб\)",
     FLANGE_FROST, lambda d: _c79_month(d, "4", "frost_days"), 0.0),
]

# ── HW.6 frost, beam sun by azimuth (2026-10-14): 79's `beam_sun` block — canon 01_04 §3.1 ⊕ ──
# ⛔ The paragraph's message is a PAIR per face — the shift against the bark beside the flange ⊥ the coldest hour under
# the flange itself (south minus north) — so both halves are pinned: the first draft quoted only the cold ends of the
# floor ranges and read «the same floor» where the floor is warmer on the south in EVERY cell (adversarial review
# 2026-10-14); a doc that kept the shift and let the floor rot would make the same mistake again.
_B79 = lambda d, az, cp="tied": d["beam_sun"]["by_azimuth"][str(az)][cp]  # noqa: E731


def _b79_hours(d, az, key, end, cp="tied"):
    return _B79(d, az, cp)["winter_hours_above_deharden_per_year"][key][end]


CHECKS += [
    ("HW.6 · beam: DNI share in sun-down hours at the declared clock → 79", CODIT, rf"припадає \*\*{N}\*\* енергії DNI",
     FLANGE_FROST, lambda d: d["beam_sun"]["sun_clock_check_dni_share_in_sun_down_hours"]["+0.0"], 0.0),
    ("HW.6 · beam: smallest DNI share under a clock shift → 79", CODIT, rf"дає вже ≥ \*\*{N} %\*\*",
     FLANGE_FROST, lambda d: 100 * min(v for k, v in d["beam_sun"]["sun_clock_check_dni_share_in_sun_down_hours"].items()
                                       if k != "+0.0"), 0.0005),
    ("HW.6 · beam: north tied median, low → 79", CODIT, rf"повного звʼязку — \*\*{N}…{_NN} K\*\*; південна",
     FLANGE_FROST, lambda d: _B79(d, 0)["median_K_range"][0], 0.005),
    ("HW.6 · beam: north tied median, high → 79", CODIT, rf"повного звʼязку — \*\*{_NN}…\+{N} K\*\*; південна",
     FLANGE_FROST, lambda d: _B79(d, 0)["median_K_range"][1], 0.005),
    ("HW.6 · beam: south tied median, low → 79", CODIT, rf"південна — \*\*\+{N}…{_NN} K\*\*",
     FLANGE_FROST, lambda d: _B79(d, 180)["median_K_range"][0], 0.005),
    ("HW.6 · beam: south tied median, high → 79", CODIT, rf"південна — \*\*{_NN}…\+{N} K\*\*",
     FLANGE_FROST, lambda d: _B79(d, 180)["median_K_range"][1], 0.005),
    ("HW.6 · beam: south colder share, low → 79", CODIT, rf"холодніше в \*\*{N}–[\d.]+ %\*\* морозних діб: кора",
     FLANGE_FROST, lambda d: _B79(d, 180)["colder_share_range"][0] * 100, 0.6),
    ("HW.6 · beam: south colder share, high → 79", CODIT, rf"холодніше в \*\*[\d.]+–{N} %\*\* морозних діб: кора",
     FLANGE_FROST, lambda d: _B79(d, 180)["colder_share_range"][1] * 100, 0.6),
    ("HW.6 · beam: coldest hour under the tied flange, south minus north, low → 79", CODIT,
     rf"на \*\*\+{N}…{_NN} K\*\* на краю повного звʼязку й", FLANGE_FROST,
     lambda d: d["beam_sun"]["coldest_hour_under_flange_south_minus_north_K"]["tied"][0], 0.005),
    ("HW.6 · beam: coldest hour under the tied flange, south minus north, high → 79", CODIT,
     rf"на \*\*{_NN}…\+{N} K\*\* на краю повного звʼязку й", FLANGE_FROST,
     lambda d: d["beam_sun"]["coldest_hour_under_flange_south_minus_north_K"]["tied"][1], 0.005),
    ("HW.6 · beam: coldest hour under the band alone, south minus north, low → 79", CODIT,
     rf"й на \*\*\+{N}…{_NN} K\*\* під смугою самою", FLANGE_FROST,
     lambda d: d["beam_sun"]["coldest_hour_under_flange_south_minus_north_K"]["decoupled"][0], 0.005),
    ("HW.6 · beam: coldest hour under the band alone, south minus north, high → 79", CODIT,
     rf"й на \*\*{_NN}…\+{N} K\*\* під смугою самою", FLANGE_FROST,
     lambda d: d["beam_sun"]["coldest_hour_under_flange_south_minus_north_K"]["decoupled"][1], 0.005),
    ("HW.6 · beam: south hours above 13 °C under bark, low → 79", CODIT, rf"під корою — \*\*{N}–[\d.]+\*\*, під фланцем",
     FLANGE_FROST, lambda d: _b79_hours(d, 180, "no_flange", 0), 0.6),
    ("HW.6 · beam: south hours above 13 °C under bark, high → 79", CODIT, rf"під корою — \*\*[\d.]+–{N}\*\*, під фланцем",
     FLANGE_FROST, lambda d: _b79_hours(d, 180, "no_flange", 1), 0.6),
    ("HW.6 · beam: south hours above 13 °C under the tied flange, low → 79", CODIT, rf"на повному звʼязку — \*\*{N}–[\d.]+\*\*, під смугою",
     FLANGE_FROST, lambda d: _b79_hours(d, 180, "flange", 0), 0.6),
    ("HW.6 · beam: south hours above 13 °C under the tied flange, high → 79", CODIT, rf"на повному звʼязку — \*\*[\d.]+–{N}\*\*, під смугою",
     FLANGE_FROST, lambda d: _b79_hours(d, 180, "flange", 1), 0.6),
    ("HW.6 · beam: south hours above 13 °C under the band alone, low → 79", CODIT, rf"під смугою самою — \*\*{N}–[\d.]+\*\*",
     FLANGE_FROST, lambda d: _b79_hours(d, 180, "flange", 0, "decoupled"), 0.6),
    ("HW.6 · beam: south hours above 13 °C under the band alone, high → 79", CODIT, rf"під смугою самою — \*\*[\d.]+–{N}\*\*",
     FLANGE_FROST, lambda d: _b79_hours(d, 180, "flange", 1, "decoupled"), 0.6),
    ("HW.6 · beam: north hours above 13 °C under bark, low → 79", CODIT, rf"на північній — \*\*{N}–[\d.]+\*\* під корою",
     FLANGE_FROST, lambda d: _b79_hours(d, 0, "no_flange", 0), 0.6),
    ("HW.6 · beam: north hours above 13 °C under bark, high → 79", CODIT, rf"на північній — \*\*[\d.]+–{N}\*\* під корою",
     FLANGE_FROST, lambda d: _b79_hours(d, 0, "no_flange", 1), 0.6),
    ("HW.6 · beam: north hours above 13 °C under the tied flange, low → 79", CODIT, rf"під корою й \*\*{N}–[\d.]+\*\* під фланцем",
     FLANGE_FROST, lambda d: _b79_hours(d, 0, "flange", 0), 0.6),
    ("HW.6 · beam: north hours above 13 °C under the tied flange, high → 79", CODIT, rf"під корою й \*\*[\d.]+–{N}\*\* під фланцем",
     FLANGE_FROST, lambda d: _b79_hours(d, 0, "flange", 1), 0.6),
    ("HW.6 · beam: warmest winter cambium under bark, south → 79", CODIT, rf"південної грані — \*\*{N}\*\* °C під корою",
     FLANGE_FROST, lambda d: _B79(d, 180)["winter_cambium_max_C"]["no_flange"], 0.05),
    ("HW.6 · beam: warmest winter cambium under the tied flange, south → 79", CODIT, rf"°C під корою й \*\*{N}\*\* °C під фланцем",
     FLANGE_FROST, lambda d: _B79(d, 180)["winter_cambium_max_C"]["flange"], 0.05),
]

# ── HW.6 frost, ground-reflected light (2026-10-18): 79's `beam_sun.ground_reflected` — canon 01_04 §3.1 ⊕ ──
# ⛔ Two sentences of that block are CLAIMS about booleans, not numbers — «the declared north-below-south reading does not
# hold at either end» and «the floor is warmer on the south in every cell of both ends» (with «never more hours under the
# flange in a winter total»). Their rows resolve to NaN when a re-run flips the boolean, so the sentence is refused as
# phrased instead of passing on a number that still matches. The cell-wise ratio is computed here from the runs, on the
# same cells (form · wind · bark side, tied) the floor reading uses — the like-for-like reading on one tree.
_G79 = lambda d: d["beam_sun"]["ground_reflected"]  # noqa: E731
_G79_ENDS = ("low", "high")


def _r79_span(d, az, key, end, cp="tied"):
    rows = [_G79(d)["by_azimuth"][e][str(az)][cp]["winter_hours_above_deharden_per_year"][key] for e in _G79_ENDS]
    return min(r[0] for r in rows) if end == 0 else max(r[1] for r in rows)


def _r79_end_span(d, end, az, cp="tied"):
    return _G79(d)["by_azimuth"][end][str(az)][cp]["winter_hours_above_deharden_per_year"]["flange"]


def _r79_declared_broken(d):
    return not any(_G79(d)["readings"][e]["deharden_fewer_north_than_south_under_tied_flange"] for e in _G79_ENDS)


def _r79_floor_holds(d):
    g = _G79(d)
    return all(g["readings"][e]["floor_south_warmer_every_cell"] and g["flange_never_above_bark_in_hours"][e] for e in _G79_ENDS)


def _r79_cellwise_ratio(d, cp="tied"):
    cells = {}
    for r in _G79(d)["runs"]:
        if r["coupling"] == cp:
            cells.setdefault((r["reflect"], r["form"], r["wind_k"], r["bark_side"]), {})[r["azimuth_deg"]] = \
                r["winter_hours_above_deharden"]["flange"]
    return _down2(min(v[180] / v[0] for v in cells.values()))


def _r79_kappas(d):
    return [row[s]["kappa"] for row in _G79(d)["snow_check"]["depths_m"].values() for s in ("era5_land", "cerra")]


CHECKS += [
    ("HW.6 · reflected: snow check κ, low → 79", CODIT, rf"κ Коена на зимових добах — \*\*{N}–{_NN}\*\*",
     FLANGE_FROST, lambda d: min(_r79_kappas(d)), 0.005),
    ("HW.6 · reflected: snow check κ, high → 79", CODIT, rf"κ Коена на зимових добах — \*\*{_NN}–{N}\*\*",
     FLANGE_FROST, lambda d: max(_r79_kappas(d)), 0.005),
    ("HW.6 · reflected: snow albedo, fresh (high end) → 79", CODIT, rf"сніг \*\*{N}\*\* наступного дня",
     FLANGE_FROST, lambda d: _G79(d)["ends"]["high"]["albedo_snow"], 0.0),
    ("HW.6 · reflected: snow albedo, sample floor (low end) → 79", CODIT, rf"й \*\*{N}\*\* — підлога вибірки",
     FLANGE_FROST, lambda d: _G79(d)["ends"]["low"]["albedo_snow"], 0.0),
    ("HW.6 · reflected: bare-ground albedo, April (low end) → 79", CODIT, rf"медіани \*\*{N}\*\* \(квітень\)",
     FLANGE_FROST, lambda d: _G79(d)["ends"]["low"]["albedo_ground"], 0.0),
    ("HW.6 · reflected: bare-ground albedo, October (high end) → 79", CODIT, rf"і \*\*{N}\*\* \(жовтень\)",
     FLANGE_FROST, lambda d: _G79(d)["ends"]["high"]["albedo_ground"], 0.0),
    ("HW.6 · reflected: over the model's diffuse, low end → 79", CODIT, rf"відбите додає \*\*≈ {N}…",
     FLANGE_FROST, lambda d: _G79(d)["ends"]["low"]["reflected_on_vertical_over_model_diffuse"], 0.05),
    ("HW.6 · reflected: over the model's diffuse, high end → 79", CODIT, rf"відбите додає \*\*≈ [\d.]+…{N}\*\*",
     FLANGE_FROST, lambda d: _G79(d)["ends"]["high"]["reflected_on_vertical_over_model_diffuse"], 0.05),
    ("HW.6 · reflected: median shift move, low → 79", CODIT, rf"воно зсуває на \*\*\+{N}…{_NN} K\*\*",
     FLANGE_FROST, lambda d: min(_G79(d)["readings"][e]["median_shift_minus_no_reflection_K"][0] for e in _G79_ENDS), 0.005),
    ("HW.6 · reflected: median shift move, high → 79", CODIT, rf"воно зсуває на \*\*{_NN}…\+{N} K\*\*",
     FLANGE_FROST, lambda d: max(_G79(d)["readings"][e]["median_shift_minus_no_reflection_K"][1] for e in _G79_ENDS), 0.005),
    ("HW.6 · reflected: coldest hour under the flange move, low → 79", CODIT, rf"під фланцем гріє на \*\*\+{N}…{_NN} K\*\*",
     FLANGE_FROST, lambda d: min(_G79(d)["readings"][e]["coldest_hour_under_flange_minus_no_reflection_K"][0] for e in _G79_ENDS), 0.005),
    ("HW.6 · reflected: coldest hour under the flange move, high → 79", CODIT, rf"під фланцем гріє на \*\*{_NN}…\+{N} K\*\*",
     FLANGE_FROST, lambda d: max(_G79(d)["readings"][e]["coldest_hour_under_flange_minus_no_reflection_K"][1] for e in _G79_ENDS), 0.005),
    ("HW.6 · reflected: floor south minus north, tied, low (every cell, both ends) → 79", CODIT,
     rf"обох кінців \(\*\*\+{N}…{_NN} K\*\* на повному", FLANGE_FROST,
     lambda d: min(_G79(d)["coldest_hour_under_flange_south_minus_north_K"][e]["tied"][0] for e in _G79_ENDS)
     if _r79_floor_holds(d) else float("nan"), 0.005),
    ("HW.6 · reflected: floor south minus north, tied, high → 79", CODIT,
     rf"обох кінців \(\*\*{_NN}…\+{N} K\*\* на повному", FLANGE_FROST,
     lambda d: max(_G79(d)["coldest_hour_under_flange_south_minus_north_K"][e]["tied"][1] for e in _G79_ENDS), 0.005),
    ("HW.6 · reflected: south hours above 13 °C under bark, low → 79", CODIT, rf"на південній грані — \*\*{N}–[\d.]+\*\* під корою, ",
     FLANGE_FROST, lambda d: _r79_span(d, 180, "no_flange", 0), 0.6),
    ("HW.6 · reflected: south hours above 13 °C under bark, high → 79", CODIT, rf"на південній грані — \*\*[\d.]+–{N}\*\* під корою, ",
     FLANGE_FROST, lambda d: _r79_span(d, 180, "no_flange", 1), 0.6),
    ("HW.6 · reflected: south hours above 13 °C under the tied flange, low → 79", CODIT, rf"під корою, \*\*{N}–[\d.]+\*\* під фланцем на повному",
     FLANGE_FROST, lambda d: _r79_span(d, 180, "flange", 0), 0.6),
    ("HW.6 · reflected: south hours above 13 °C under the tied flange, high → 79", CODIT, rf"під корою, \*\*[\d.]+–{N}\*\* під фланцем на повному",
     FLANGE_FROST, lambda d: _r79_span(d, 180, "flange", 1), 0.6),
    ("HW.6 · reflected: north hours above 13 °C under bark, low → 79", CODIT, rf"на північній — \*\*{N}–[\d.]+\*\* і \*\*",
     FLANGE_FROST, lambda d: _r79_span(d, 0, "no_flange", 0), 0.6),
    ("HW.6 · reflected: north hours above 13 °C under bark, high → 79", CODIT, rf"на північній — \*\*[\d.]+–{N}\*\* і \*\*",
     FLANGE_FROST, lambda d: _r79_span(d, 0, "no_flange", 1), 0.6),
    ("HW.6 · reflected: north hours above 13 °C under the tied flange, low → 79", CODIT, rf"\*\* і \*\*{N}–[\d.]+\*\*\. За сумою зими",
     FLANGE_FROST, lambda d: _r79_span(d, 0, "flange", 0), 0.6),
    ("HW.6 · reflected: north hours above 13 °C under the tied flange, high (never more than bark in a winter total) → 79", CODIT,
     rf"\*\* і \*\*[\d.]+–{N}\*\*\. За сумою зими", FLANGE_FROST,
     lambda d: _r79_span(d, 0, "flange", 1) if _r79_floor_holds(d) else float("nan"), 0.6),
    ("HW.6 · reflected: month cells with more hours under the flange, low end → 79", CODIT, rf"помісячних винятків — \*\*{N}\*\* клітинки",
     FLANGE_FROST, lambda d: len(_G79(d)["month_cells_flange_above_bark"]["low"]), 0.0),
    ("HW.6 · reflected: month cells with more hours under the flange, high end → 79", CODIT, rf"і \*\*{N}\*\* на верхньому",
     FLANGE_FROST, lambda d: len(_G79(d)["month_cells_flange_above_bark"]["high"]), 0.0),
    # the declared range reading, per END — a north top of one end against a south bottom of the other is no pairing
    ("HW.6 · reflected: declared reading broken — north top under the flange, low end → 79", CODIT,
     rf"на нижньому кінці північ до \*\*{N}\*\*", FLANGE_FROST,
     lambda d: _r79_end_span(d, "low", 0)[1] if _r79_declared_broken(d) else float("nan"), 0.05),
    ("HW.6 · reflected: declared reading broken — south bottom under the flange, low end → 79", CODIT,
     rf"південь від \*\*{N}\*\* годин за зиму; на верхньому", FLANGE_FROST,
     lambda d: _r79_end_span(d, "low", 180)[0], 0.05),
    ("HW.6 · reflected: declared reading broken — north top under the flange, high end → 79", CODIT,
     rf"на верхньому — до \*\*{N}\*\* і від", FLANGE_FROST, lambda d: _r79_end_span(d, "high", 0)[1], 0.05),
    ("HW.6 · reflected: declared reading broken — south bottom under the flange, high end → 79", CODIT,
     rf"і від \*\*{N}\*\*\): на обох кінцях", FLANGE_FROST, lambda d: _r79_end_span(d, "high", 180)[0], 0.05),
    ("HW.6 · reflected: declared reading's margin without reflected light → 79", CODIT,
     rf"трималося із запасом лише \*\*{N}\*\* години", FLANGE_FROST,
     lambda d: _G79(d)["readings"]["none"]["deharden_range_margin_south_min_minus_north_max_per_year"]
     if _G79(d)["readings"]["none"]["deharden_fewer_north_than_south_under_tied_flange"] else float("nan"), 0.05),
    # which reanalysis takes each end is asserted from the data (`check_reflect_ends`) — the shares the doc quotes for it
    ("HW.6 · reflected: winter daylight snow share, ERA5-Land ≥ 11 cm (low end) → 79", CODIT,
     rf"частка зимових світлових годин зі снігом \*\*{N}\*\* проти", FLANGE_FROST,
     lambda d: _G79(d)["end_source_check_winter_daylight_snow_share"]["era5_land/0.11"], 0.005),
    ("HW.6 · reflected: winter daylight snow share, CERRA ≥ 11 cm → 79", CODIT,
     rf"проти \*\*{N}\*\* у CERRA на ≥ 11 см", FLANGE_FROST,
     lambda d: _G79(d)["end_source_check_winter_daylight_snow_share"]["cerra/0.11"], 0.005),
    ("HW.6 · reflected: winter daylight snow share, ERA5-Land ≥ 1 cm (high end) → 79", CODIT,
     rf"і \*\*{N}\*\* проти \*\*[\d.]+\*\* на ≥ 1 см", FLANGE_FROST,
     lambda d: _G79(d)["end_source_check_winter_daylight_snow_share"]["era5_land/0.01"], 0.005),
    ("HW.6 · reflected: winter daylight snow share, CERRA ≥ 1 cm → 79", CODIT,
     rf"проти \*\*{N}\*\* на ≥ 1 см", FLANGE_FROST,
     lambda d: _G79(d)["end_source_check_winter_daylight_snow_share"]["cerra/0.01"], 0.005),
    ("HW.6 · reflected: south over north under the flange, cell by cell (floored) → 79", CODIT, rf"щонайменше \*\*{N}×\*\* годин північної",
     FLANGE_FROST, _r79_cellwise_ratio, 0.0),
    ("HW.6 · reflected: south over north under the decoupled flange, cell by cell (floored) → 79", CODIT,
     rf"на розвʼязаному — щонайменше \*\*{N}×\*\*", FLANGE_FROST, lambda d: _r79_cellwise_ratio(d, "decoupled"), 0.0),
]

# leg (3б): Os(III) relaxed from each relaxed Os(II) (21e `b3lyp-relaxed-os3`), read by 83 as `relaxed_geometry_check.adiabatic`
METHODS = "docs/protocols/ebfc/in_silico/paper/02_methods.md"
V83 = "dft/os_series_vs_measured.json"
OS3 = "dft/os_mediator_series_relaxed_os3.json"


def _ad(d):
    return d["relaxed_geometry_check"]["adiabatic"]


def _ad_ratio(d, series, pair, col="adiabatic"):
    p = next(p for p in _ad(d)["pairs_vs_measured"] if (p["series_name"], p["pair"]) == (series, pair))
    return p[f"{col}_mV"] / p["measured_mV"]


def _koop(d, n, where):   # the Koopmans cascade Δ's move, eV — `os3_on_own_minimum` · `os3_on_os2_minimum`
    return _ad(d)["koopmans_cascade_delta_move_eV"][n][where]


def _ad_cl(d, f):
    return f(v["relaxed_os3"] for v in _ad(d)["os_cl_A"].values())


def _ad_max_pair(d):   # mV per substituent, from the programmatic geometry
    return max(abs(v) for v in _ad(d)["pair_move_from_series_mV"].values())


CHECKS += [
    # paper §3.3 — the (3б) reading across the three series
    ("paper §3.3 (3б) λ_III low → 83 adiabatic", PAPER_RESULTS, rf"reorganisation energies λ_III of {N}–", V83,
     lambda d: min(_ad(d)["lambda_os3_meV"].values()), 0.6),
    ("paper §3.3 (3б) λ_III high → 83 adiabatic", PAPER_RESULTS, rf"λ_III of [\d.]+–{N} meV\)", V83,
     lambda d: max(_ad(d)["lambda_os3_meV"].values()), 0.6),
    ("paper §3.3 (3б) ref 8 within → 83 adiabatic", PAPER_RESULTS, rf"lie within {N} mV per substituent of the measured", V83,
     lambda d: max(p["adiabatic_gap_mV"] for p in _ad(d)["pairs_vs_measured"] if p["series_name"] == "ref 8"), 0.05),
    ("paper §3.3 (3б) ref 8 OMe−H → 83 adiabatic", PAPER_RESULTS, rf"measured \(OMe−H {N},\s+Me−H", V83,
     lambda d: _ad_ratio(d, "ref 8", "ome-bpy"), 0.005),
    ("paper §3.3 (3б) ref 8 Me−H → 83 adiabatic", PAPER_RESULTS, rf"OMe−H [\d.]+,\s+Me−H {N}, OMe−Me", V83,
     lambda d: _ad_ratio(d, "ref 8", "dmbpy-bpy"), 0.005),
    ("paper §3.3 (3б) ref 8 OMe−Me → 83 adiabatic", PAPER_RESULTS, rf"Me−H [\d.]+, OMe−Me {N} times\)", V83,
     lambda d: _ad_ratio(d, "ref 8", "ome-dmbpy"), 0.005),
    ("paper §3.3 (3б) donor r² → 83", PAPER_RESULTS, rf"line through H and OMe \(r² {N}\)", V83,
     lambda d: d["relaxed_geometry_check"]["donor_r2"]["adiabatic"], 0.0005),
    ("paper §3.3 (3б) pair move mV → 83 adiabatic", PAPER_RESULTS, rf"the donor\s+pairs move by up to {N} mV per substituent", V83,
     _ad_max_pair, 0.05),
    ("paper §3.3 (3б) pair move per complex → 83 adiabatic", PAPER_RESULTS, rf"per substituent \({N} meV a complex\), and on its", V83,
     lambda d: _ad_max_pair(d) * 4, 0.5),
    ("paper §3.3 (3б) Os–Cl low → 83 adiabatic", PAPER_RESULTS, rf"takes Os–Cl back to\s+{N}–", V83, lambda d: _ad_cl(d, min), 0.005),
    ("paper §3.3 (3б) Os–Cl high → 83 adiabatic", PAPER_RESULTS, rf"takes Os–Cl back to\s+[\d.]+–{N} Å", V83, lambda d: _ad_cl(d, max), 0.005),
    ("paper §3.3 (3б) OMe over, MeCN → 83 adiabatic", PAPER_RESULTS, rf"both states relaxed, {N} % and", V83,
     lambda d: (_ad_ratio(d, "MeCN", "ome-bpy") - 1) * 100, 0.6),
    ("paper §3.3 (3б) OMe over, ref 8 → 83 adiabatic", PAPER_RESULTS, rf"relaxed, [\d.]+ % and {N} % over, with our Me", V83,
     lambda d: (_ad_ratio(d, "ref 8", "ome-bpy") - 1) * 100, 0.6),
    ("paper §3.3 (3б) Me, MeCN → 83 adiabatic", PAPER_RESULTS, rf"effect then {N} and [\d.]+ times the measured\)", V83,
     lambda d: _ad_ratio(d, "MeCN", "dmbpy-bpy"), 0.005),
    ("paper §3.3 (3б) Me, ref 8 → 83 adiabatic", PAPER_RESULTS, rf"effect then [\d.]+ and {N} times the measured\)", V83,
     lambda d: _ad_ratio(d, "ref 8", "dmbpy-bpy"), 0.005),
    ("paper §3.3 robust Me, ref 8 → 83 adiabatic", PAPER_RESULTS, rf"geometry and {N} to [\d.]+ times with both osmium states", V83,
     lambda d: _ad_ratio(d, "ref 8", "dmbpy-bpy"), 0.05),
    ("paper §3.3 robust Me, MeCN → 83 adiabatic", PAPER_RESULTS, rf"geometry and [\d.]+ to {N} times with both osmium states", V83,
     lambda d: _ad_ratio(d, "MeCN", "dmbpy-bpy"), 0.05),
    # paper §3.5 — the cascade's geometric limit (the rule ⚖️ 2026-10-13: under 0.1 eV, the paper prints the bound)
    ("paper §3.5 Me point adiabatic shift → relaxed_os3", PAPER_RESULTS, rf"moves its ΔE_red\(III→II\) by {N} eV \(by coincidence", OS3,
     lambda d: d["vs_vertical"]["point_shift_eV"]["dmbpy"], 0.0005),
    ("paper §3.5 «by coincidence» C-min shift → os_chelate_sensitivity", PAPER_RESULTS,
     rf"moves its ΔE_red\(III→II\) by {N} eV \(by coincidence", "reproduction/os_chelate_sensitivity.json",
     lambda d: d["sensitivity"]["dE_red_shift_eV"], 0.0005),
    ("paper §3.5 Koopmans offset, own minimum → 83 adiabatic", PAPER_RESULTS, rf"its Koopmans offset by {N} eV \(", V83,
     lambda d: _koop(d, "dmbpy", "os3_on_own_minimum"), 0.0005),
    ("paper §3.5 Koopmans offset, vertical → 83 adiabatic", PAPER_RESULTS, rf"eV \(\+{N} eV with Os\(III\) kept vertical", V83,
     lambda d: _koop(d, "dmbpy", "os3_on_os2_minimum"), 0.0005),
    # paper §2.3
    ("paper §2.3 (3б) points within → relaxed_os3", METHODS, rf"leaves the points within {N} meV", OS3,
     lambda d: max(abs(s) for s in _donor_points(d["vs_vertical"])) * 1000, 0.6),
    ("paper §2.3 (3б) pairs per complex → 83 adiabatic", METHODS, rf"while the pairs move by up to {N} meV a complex", V83,
     lambda d: _ad_max_pair(d) * 4, 0.5),
    # SUMMARY §Mediator, limits (2) and (4)
    *[(f"SUMMARY (3б) λ_III {n} → relaxed_os3", SUMMARY, anchor, OS3, lambda d, n=n: d["vs_vertical"]["lambda_os3_meV"][n], 0.6)
      for n, anchor in (("dmbpy", rf"λ_III {N} · [\d.]+ · [\d.]+ meV for Me · OMe · H"),
                        ("ome", rf"λ_III [\d.]+ · {N} · [\d.]+ meV for Me"), ("bpy", rf"λ_III [\d.]+ · [\d.]+ · {N} meV for Me"))],
    ("SUMMARY (3б) ref 8 within → 83", SUMMARY, rf"ref 8's three then lie within {N} mV per", V83,
     lambda d: max(p["adiabatic_gap_mV"] for p in _ad(d)["pairs_vs_measured"] if p["series_name"] == "ref 8"), 0.05),
    *[(f"SUMMARY (3б) {lab} → 83", SUMMARY, anchor, V83, fn, 0.005) for lab, anchor, fn in (
        ("ref 8 OMe−H", rf"substituent \(OMe−H ×{N}, Me−H", lambda d: _ad_ratio(d, "ref 8", "ome-bpy")),
        ("ref 8 Me−H", rf"OMe−H ×[\d.]+, Me−H ×{N}, OMe−Me ×", lambda d: _ad_ratio(d, "ref 8", "dmbpy-bpy")),
        ("ref 8 OMe−Me", rf"Me−H ×[\d.]+, OMe−Me ×{N}\), MeCN", lambda d: _ad_ratio(d, "ref 8", "ome-dmbpy")),
        ("MeCN OMe−H before", rf"away from MeCN \(×{N} → ×", lambda d: _ad_ratio(d, "MeCN", "ome-bpy", "series")),
        ("MeCN OMe−H after", rf"away from MeCN \(×[\d.]+ → ×{N}\)", lambda d: _ad_ratio(d, "MeCN", "ome-bpy")),
        ("MeCN Me−H", rf"MeCN Me−H stays ×{N}, the aqueous", lambda d: _ad_ratio(d, "MeCN", "dmbpy-bpy")),
        ("aqueous after", rf"aqueous OMe−Me ends ×{N} \(", lambda d: _ad_ratio(d, "aqueous", "ome-dmbpy")),
        ("aqueous vertical", rf"ends ×[\d.]+ \(×{N} with Os\(III\) vertical\)", lambda d: _ad_ratio(d, "aqueous", "ome-dmbpy", "relaxed")))],
    ("SUMMARY (3б) donor r² → 83", SUMMARY, rf"r² of the three donors → {N}, the donor slope", V83,
     lambda d: d["relaxed_geometry_check"]["donor_r2"]["adiabatic"], 0.0005),
    ("SUMMARY (3б) donor slope → 83", SUMMARY, rf"the donor slope \+{N} % against the programmatic", V83,
     lambda d: (d["relaxed_geometry_check"]["donor_slope_per_substituent_V_per_sigma"]["adiabatic"]
                / d["relaxed_geometry_check"]["donor_slope_per_substituent_V_per_sigma"]["series"] - 1) * 100, 0.6),
    ("SUMMARY (3б) pair move mV → 83", SUMMARY, rf"the pairs move by up to {N} mV per substituent \(OMe−Me", V83, _ad_max_pair, 0.05),
    ("SUMMARY (3б) pair move per complex → 83", SUMMARY, rf"\(OMe−Me, {N} meV a complex\) and the points", V83,
     lambda d: _ad_max_pair(d) * 4, 0.5),
    ("SUMMARY (3б) points low → relaxed_os3", SUMMARY, rf"and the points by {N}…", OS3,
     lambda d: min(_donor_points(d["vs_vertical"])) * 1000, 0.6),
    ("SUMMARY (3б) points high → relaxed_os3", SUMMARY, rf"and the points by [{_DASHES}\-]?[\d.]+…\+{N} meV", OS3,
     lambda d: max(_donor_points(d["vs_vertical"])) * 1000, 0.6),
    ("SUMMARY (3б) Os–Cl low → 83", SUMMARY, rf"Os\(III\) takes Os–Cl back to {N}–", V83, lambda d: _ad_cl(d, min), 0.005),
    ("SUMMARY (3б) Os–Cl high → 83", SUMMARY, rf"Os\(III\) takes Os–Cl back to [\d.]+–{N} Å", V83, lambda d: _ad_cl(d, max), 0.005),
    ("SUMMARY (4) Koopmans own minimum Me → 83", SUMMARY, rf"and by {N} eV on Os\(III\)'s own minimum \(paper", V83,
     lambda d: _koop(d, "dmbpy", "os3_on_own_minimum"), 0.0005),
    ("SUMMARY (4) Me point adiabatic → relaxed_os3", SUMMARY, rf"vertical, {N} eV adiabatic\) is its nearest proxy", OS3,
     lambda d: d["vs_vertical"]["point_shift_eV"]["dmbpy"], 0.0005),
    ("SUMMARY (4) ome·bpy pairs per complex → 83", SUMMARY, rf"substituent pairs \(≤ {N} meV a complex\) and points", V83,
     lambda d: _ad_max_pair(d) * 4, 0.5),
    ("SUMMARY (4) ome·bpy points → relaxed_os3", SUMMARY, rf"and points \(≤ {N} meV\) stay under it", OS3,
     lambda d: max(abs(s) for s in _donor_points(d["vs_vertical"])) * 1000, 0.6),
    *[(f"SUMMARY (4) Koopmans own minimum {n} → 83", SUMMARY, anchor, V83,
       lambda d, n=n: _koop(d, n, "os3_on_own_minimum"), 0.0005)
      for n, anchor in (("ome", rf"cascade Δ of OMe moves\s+by {N} eV with Os\(III\) on its own"),
                        ("bpy", rf"own minimum \(H {N}, Me"), ("dmbpy", rf"own minimum \(H [{_DASHES}\-]?[\d.]+, Me {N} eV\)"))],
    # PIPELINE_STATUS — the banner, row 83 (d) and the dated notes under D (2026-10-13 · 2026-10-14)
    *[(f"PIPELINE banner λ_III {n} → relaxed_os3", PIPELINE, anchor, OS3, lambda d, n=n: d["vs_vertical"]["lambda_os3_meV"][n], 0.6)
      for n, anchor in (("dmbpy", rf"dmbpy \(15 steps; λ_III {N} meV\)"), ("ome", rf"ome \(31 steps; {N} meV\)"),
                        ("bpy", rf"bpy \(47 steps; {N} meV\)"))],
    *[(f"PIPELINE banner steps {n} → relaxed_os3", PIPELINE, anchor, OS3,
       lambda d, n=n: d["complexes"][n]["geometry_os3_relaxed"]["info"]["steps"], 0)
      for n, anchor in (("dmbpy", rf"dmbpy \({N} steps; λ_III"), ("ome", rf"ome \({N} steps; [\d.]+ meV\)"),
                        ("bpy", rf"bpy \({N} steps; [\d.]+ meV\)"))],
    ("PIPELINE banner optimisation hours → relaxed_os3", PIPELINE, rf"\), {N} h of optimisation the three", OS3,
     lambda d: sum(c["geometry_os3_relaxed"]["info"]["wall_seconds"] for n, c in d["complexes"].items() if n in DONORS) / 3600, 0.06),
    ("PIPELINE row 83 (d) ref 8 within → 83", PIPELINE, rf"ref 8's three within {N} mV per substituent, MeCN", V83,
     lambda d: max(p["adiabatic_gap_mV"] for p in _ad(d)["pairs_vs_measured"] if p["series_name"] == "ref 8"), 0.05),
    ("PIPELINE row 83 (d) Koopmans OMe → 83", PIPELINE, rf"cascade Δ of OMe {N} eV; the slope ①", V83,
     lambda d: _koop(d, "ome", "os3_on_own_minimum"), 0.0005),
    ("PIPELINE D 10-13 λ_III → relaxed_os3", PIPELINE, rf"λ_III = {N} меВ \(оцінка до прогону", OS3,
     lambda d: d["vs_vertical"]["lambda_os3_meV"]["dmbpy"], 0.6),
    ("PIPELINE D 10-13 adiabatic ΔE_red → relaxed_os3", PIPELINE, rf"адіабатичний ΔE_red {N} еВ проти", OS3,
     lambda d: d["complexes"]["dmbpy"]["dE_red_adiabatic_eV"], 0.0005),
    ("PIPELINE D 10-13 Me point shift → relaxed_os3", PIPELINE, rf"серії — зсув {N} еВ \(вертикальний", OS3,
     lambda d: d["vs_vertical"]["point_shift_eV"]["dmbpy"], 0.0005),
    ("PIPELINE D 10-13 Koopmans vertical → 83", PIPELINE, rf"\([+{_DASHES}\-]?[\d.]+ еВ\) рухається на \+{N} еВ з Os\(III\)", V83,
     lambda d: _koop(d, "dmbpy", "os3_on_os2_minimum"), 0.0005),
    ("PIPELINE D 10-13 Koopmans own → 83", PIPELINE, rf"і на {N} еВ з Os\(III\) на власному мінімумі — обидва", V83,
     lambda d: _koop(d, "dmbpy", "os3_on_own_minimum"), 0.0005),
    ("PIPELINE D 10-14 pairs per complex → 83", PIPELINE, rf"щонайбільше на {N} меВ на комплекс \(OMe−Me", V83,
     lambda d: _ad_max_pair(d) * 4, 0.5),
    *[(f"PIPELINE D 10-14 pair {k} per complex → 83", PIPELINE, anchor, V83,
       lambda d, k=k: abs(_ad(d)["pair_move_from_series_mV"][k]) * 4, 0.5)
      for k, anchor in (("dmbpy-bpy", rf"\(OMe−Me; Me−H {N}, OMe−H"), ("ome-bpy", rf"Me−H [\d.]+, OMe−H {N}\), абсолютні"))],
    ("PIPELINE D 10-14 points low → relaxed_os3", PIPELINE, rf"абсолютні точки — на {N}…", OS3,
     lambda d: min(_donor_points(d["vs_vertical"])) * 1000, 0.6),
    ("PIPELINE D 10-14 points high → relaxed_os3", PIPELINE, rf"абсолютні точки — на [{_DASHES}\-]?[\d.]+…\+{N} меВ", OS3,
     lambda d: max(_donor_points(d["vs_vertical"])) * 1000, 0.6),
    *[(f"PIPELINE D 10-14 Koopmans own {n} → 83", PIPELINE, anchor, V83, lambda d, n=n: _koop(d, n, "os3_on_own_minimum"), 0.0005)
      for n, anchor in (("dmbpy", rf"мінімумі Me {N} еВ \(застосування 2026-10-13\)"), ("bpy", rf"\(застосування 2026-10-13\), H {N}, \*\*OMe"),
                        ("ome", rf"\*\*OMe {N} еВ\*\*"))],
    *[(f"PIPELINE D 10-14 Koopmans vertical {n} → 83", PIPELINE, anchor, V83, lambda d, n=n: _koop(d, n, "os3_on_os2_minimum"), 0.0005)
      for n, anchor in (("dmbpy", rf"мінімумі Os\(II\): \+{N} · "), ("bpy", rf"мінімумі Os\(II\): \+[\d.]+ · \+{N} · "),
                        ("ome", rf"мінімумі Os\(II\): \+[\d.]+ · \+[\d.]+ · \+{N}\)"))],
    # the per-computed-pair reading (adversary 2026-10-14: six rows, three computed pairs, two independent)
    *[(f"paper §3.3 (3б) {lab} → 83 computed_pairs", PAPER_RESULTS, anchor, V83,
       lambda d, k=k, b=b: _ad(d)["computed_pairs"][k][f"move_from_{b}_mV"], 0.05)
      for lab, k, b, anchor in (("OMe−H vs vertical", "ome-bpy", "relaxed", rf"OMe−H by \+{N} and Me−H by"),
                                ("Me−H vs vertical", "dmbpy-bpy", "relaxed", rf"and Me−H by \+{N} mV per\s+substituent against"),
                                ("OMe−Me vs vertical", "ome-dmbpy", "relaxed", rf"their difference, OMe−Me, by {N} mV, away"))],
    ("paper §3.3 (3б) MeCN OMe−H before → 83", PAPER_RESULTS, rf"acetonitrile one \(from {N} to", V83,
     lambda d: _ad_ratio(d, "MeCN", "ome-bpy", "series"), 0.005),
    ("paper §3.3 (3б) MeCN OMe−H after → 83", PAPER_RESULTS, rf"acetonitrile one \(from [\d.]+ to {N} times\)", V83,
     lambda d: _ad_ratio(d, "MeCN", "ome-bpy"), 0.005),
    ("paper §3.3 (3б) MeCN Me−H → 83", PAPER_RESULTS, rf"acetonitrile Me−H stays {N} times", V83,
     lambda d: _ad_ratio(d, "MeCN", "dmbpy-bpy"), 0.005),
    ("paper §3.3 (3б) aqueous after → 83", PAPER_RESULTS, rf"aqueous OMe−Me ends at {N} times", V83,
     lambda d: _ad_ratio(d, "aqueous", "ome-dmbpy"), 0.005),
    ("paper §3.3 (3б) aqueous vertical → 83", PAPER_RESULTS, rf"times \({N} with Os\(III\)\s+vertical\)", V83,
     lambda d: _ad_ratio(d, "aqueous", "ome-dmbpy", "relaxed"), 0.005),
    *[(f"SUMMARY (3б) {lab} → 83 computed_pairs", SUMMARY, anchor, V83,
       lambda d, k=k: _ad(d)["computed_pairs"][k]["move_from_relaxed_mV"], 0.05)
      for lab, k, anchor in (("OMe−H vs vertical", "ome-bpy", rf"vertical, OMe−H \+{N} and Me−H"),
                             ("Me−H vs vertical", "dmbpy-bpy", rf"OMe−H \+[\d.]+ and Me−H \+{N} mV per substituent\)"),
                             ("OMe−Me vs vertical", "ome-dmbpy", rf"in both series that measure it \({N} mV\)"))],
    ("SUMMARY (4) slope ① extrapolated → 83", SUMMARY, rf"over the fit set's span, by ≈ {N} eV", V83,
     lambda d: _ad(d)["d_first_trigger"]["extrapolated_eV"]["slope_1_over_lfer_span"], 0.005),
    ("SUMMARY (4) donor slope change → 83", SUMMARY, rf"extrapolated from the donors' \+{N} % over", V83,
     lambda d: _ad(d)["donor_slope_change"] * 100, 0.6),
    ("PIPELINE row 83 (d) slope ① → 83", PIPELINE, rf"the slope ① ≈ {N} eV by extrapolation", V83,
     lambda d: _ad(d)["d_first_trigger"]["extrapolated_eV"]["slope_1_over_lfer_span"], 0.005),
    # the D note 2026-10-14: the numbers behind the ⚖️ leg — pinned on the ⊕ 2026-10-16 dopiska beneath it (the 1,5-dihydro
    # levels); the note itself keeps its 4a,5-dihydro numbers as the record, which no pin reads
    *[(f"PIPELINE D 10-14 cascade {g} {n} → 83", PIPELINE, anchor, V83,
       lambda d, g=g, n=n: _ad(d)["koopmans_cascade_delta_eV"][n][g], 0.0005)
      for g, n, anchor in (("os3_on_own_minimum", "ome", rf"ці рівні — власні мінімуми: OMe {N} < Me"),
                           ("os3_on_own_minimum", "dmbpy", rf"ці рівні — власні мінімуми: OMe [+{_DASHES}\-]?[\d.]+ < Me {N} < H"),
                           ("os3_on_own_minimum", "bpy", rf"власні мінімуми: OMe [+{_DASHES}\-]?[\d.]+ < Me [+{_DASHES}\-]?[\d.]+ < H {N} еВ; програмні"),
                           ("programmatic", "ome", rf"програмні: {N} < "),
                           ("programmatic", "dmbpy", rf"програмні: [+{_DASHES}\-]?[\d.]+ < {N} < "),
                           ("programmatic", "bpy", rf"програмні: [+{_DASHES}\-]?[\d.]+ < [+{_DASHES}\-]?[\d.]+ < {N};"))],
    ("PIPELINE D 10-14 neighbour-gap move → 83", PIPELINE, rf"зсуваються ≤ {N} меВ — але там", V83,
     lambda d: 1000 * max(abs(_ad(d)["koopmans_neighbour_gap_eV"][g][k] - _ad(d)["koopmans_neighbour_gap_eV"]["programmatic"][k])
                          for g in ("os3_on_os2_minimum", "os3_on_own_minimum") for k in _ad(d)["koopmans_neighbour_gap_eV"][g]), 0.6),
    *[(f"PIPELINE D 10-14 programmatic gap {k} → 83", PIPELINE, anchor, V83,
       lambda d, k=k: _ad(d)["koopmans_neighbour_gap_eV"]["programmatic"][k] * 1000, 0.6)
      for k, anchor in (("ome-dmbpy", rf"найбільший \({N} і"), ("dmbpy-bpy", rf"найбільший \([\d.]+ і {N} меВ\)"))],
    *[(f"PIPELINE D 10-14 {note} unrelaxed gap {k} → 83", PIPELINE, anchor, V83,
       lambda d, k=k: abs(_ad(d)["unrelaxed_neighbour_gap_meV"][k]), 0.06)
      for note, k, anchor in (
          ("note", "nme2-nh2", rf"не релаксовані: NMe₂→NH₂ {N} меВ"),
          ("note", "no2-so2cf3", rf"NO₂→SO₂CF₃ {N}, COOH→CF₃ [\d.]+\. Другий"),
          ("note", "dcbpy-cf3", rf"COOH→CF₃ {N}\. Другий"),
          ("verdict", "nme2-nh2", rf"не релаксовані — NMe₂→NH₂ {N} меВ"),
          ("verdict", "no2-so2cf3", rf"NO₂→SO₂CF₃ {N}, COOH→CF₃ [\d.]+; перестановка"),
          ("verdict", "dcbpy-cf3", rf"COOH→CF₃ {N}; перестановка"))],
    ("PIPELINE D 10-14 donor slope change → 83", PIPELINE, rf"релаксація зсуває на \+{N} %", V83,
     lambda d: _ad(d)["donor_slope_change"] * 100, 0.6),
    ("PIPELINE D 10-14 LFER span → 83", PIPELINE, rf"розмах fit-set \({N} еВ\)", V83, lambda d: _ad(d)["lfer_span_eV"], 0.006),
    ("PIPELINE D 10-14 slope ① extrapolated → 83", PIPELINE, rf"це ≈ {N} еВ — екстраполяція", V83,
     lambda d: _ad(d)["d_first_trigger"]["extrapolated_eV"]["slope_1_over_lfer_span"], 0.005),
    # paper §3.3 — what the verdict «так, так» (2026-10-14) had the paper print: the members' Koopmans sensitivity and the
    # extrapolated slope ①, with the untested neighbours
    *[(f"paper §3.3 Koopmans own minimum {n} → 83", PAPER_RESULTS, anchor, V83,
       lambda d, n=n: _koop(d, n, "os3_on_own_minimum"), 0.0005)
      for n, anchor in (("ome", rf"moves by {N} eV for OMe, "), ("dmbpy", rf"eV for OMe, {N} eV for Me and"),
                        ("bpy", rf"eV for Me and {N} eV for H and stays"))],
    ("paper §3.3 donor slope steepens → 83", PAPER_RESULTS, rf"slope over the three donors steepens by {N} %", V83,
     lambda d: _ad(d)["donor_slope_change"] * 100, 0.6),
    ("paper §3.3 slope ① extrapolated → 83", PAPER_RESULTS, rf"would amount to\s+≈{N} eV\. The acceptor", V83,
     lambda d: _ad(d)["d_first_trigger"]["extrapolated_eV"]["slope_1_over_lfer_span"], 0.005),
    *[(f"paper §3.3 untested neighbour {k} → 83", PAPER_RESULTS, anchor, V83,
       lambda d, k=k: abs(_ad(d)["unrelaxed_neighbour_gap_meV"][k]), 0.06)
      for k, anchor in (("nme2-nh2", rf"NMe₂ and NH₂ \({N} meV apart\)"), ("no2-so2cf3", rf"of NO₂ and SO₂CF₃ \({N} meV\) only NO₂ is"))],
    # the verdict «так, так» under D (2026-10-14): the numbers its migrated form carries
    *[(f"PIPELINE D verdict programmatic gap {k} → 83", PIPELINE, anchor, V83,
       lambda d, k=k: _ad(d)["koopmans_neighbour_gap_eV"]["programmatic"][k] * 1000, 0.6)
      for k, anchor in (("ome-dmbpy", rf"найбільших запасах \({N} і"), ("dmbpy-bpy", rf"найбільших запасах \([\d.]+ і {N} меВ\)"))],
    ("PIPELINE D verdict neighbour-gap move → 83", PIPELINE, rf"нерівномірний — до {N} меВ, тож", V83,
     lambda d: 1000 * max(abs(_ad(d)["koopmans_neighbour_gap_eV"][g][k] - _ad(d)["koopmans_neighbour_gap_eV"]["programmatic"][k])
                          for g in ("os3_on_os2_minimum", "os3_on_own_minimum") for k in _ad(d)["koopmans_neighbour_gap_eV"][g]), 0.6),
    ("PIPELINE D verdict slope ① extrapolated → 83", PIPELINE, rf"точки Me — {N} еВ тієї самої природи", V83,
     lambda d: _ad(d)["d_first_trigger"]["extrapolated_eV"]["slope_1_over_lfer_span"], 0.005),
    # the D note 2026-10-13 and SUMMARY (4): the two numbers the first pass left unpinned (adversary 2026-10-14)
    ("PIPELINE D 10-13 series ΔE_red Me → os_mediator_series", PIPELINE, rf"еВ проти {N} серії — зсув", "dft/os_mediator_series.json",
     lambda d: next(c for c in d["complexes"] if c["name"] == "dmbpy")["dE_red_eV"], 0.0005),
    ("PIPELINE D 10-13 vertical Me shift → relaxed_os2", PIPELINE, rf"на мінімумі Os\(II\) давав {N}\)", "dft/os_mediator_series_relaxed_os2.json",
     lambda d: d["vs_series"]["point_shift_eV"]["dmbpy"], 0.0005),
    ("SUMMARY (4) vertical Me shift → relaxed_os2", SUMMARY, rf"of the Me point \({N} eV vertical,", "dft/os_mediator_series_relaxed_os2.json",
     lambda d: d["vs_series"]["point_shift_eV"]["dmbpy"], 0.0005),
]


# the acceptors (21e `b3lyp-relaxed-os2` · `b3lyp-relaxed-os3` on Cl, then NO₂), read by 83 as `relaxed_geometry_check.acceptors`
OS2 = "dft/os_mediator_series_relaxed_os2.json"
OUTLINE = "docs/protocols/ebfc/in_silico/paper/00_OUTLINE.md"
_OS_CL_CRYSTAL_MAX_A = {"relaxed": 2.44, "relaxed_os3": 2.38}   # paper §2.3 (COD): Os(II)–Cl 2.40–2.44, Os(III)–Cl 2.36–2.38 Å


def _ac(d):
    return d["relaxed_geometry_check"]["acceptors"]


def _ac_ratio(d, series, pair, col="adiabatic"):
    p = next(p for p in _ac(d)["pairs_vs_measured"] if (p["series_name"], p["pair"]) == (series, pair))
    return p[f"{col}_mV"] / p["measured_mV"]


def _ac_pair_move_max(d):   # meV a complex, the largest Cl pair move from the programmatic geometry over both relaxed geometries
    rows = _ac(d)["pairs_vs_measured"]
    return 4 * max(max(abs(p["relaxed_mV"] - p["series_mV"]), abs(p["adiabatic_mV"] - p["series_mV"])) for p in rows)


def _ac_koop(d, n, where):   # eV — `os3_on_os2_minimum` · `os3_on_own_minimum`
    return _ac(d)["koopmans_own_move_eV"][n][where]


def _ac_gap(d, k, where):   # meV — a Table 4 neighbour pair with both members relaxed
    return _ac(d)["table4_neighbours_both_relaxed"][k]["koopmans_gap_meV"][where]


def _ac_os_cl(d, where, over=False, n="cl"):   # Å — an acceptor's Os–Cl on a relaxed geometry, or its overshoot of the §2.3 crystal range
    v = _ac(d)["os_cl_A"][n][where]
    return v - _OS_CL_CRYSTAL_MAX_A[where] if over else v


def _aq_source(d, x, r):   # the aqueous source's own optimised B3LYP, ratio to the measured
    return next(p for p in d["aqueous_series"]["pairs"] if (p["x"], p["ref"]) == (x, r))["source_dft_over_measured"]


_CL_ROWS = (("ref 8", "cl-bpy", "Cl−H"), ("ref 8", "cl-dmbpy", "Cl−Me"), ("ref 8", "cl-ome", "Cl−OMe"),
            ("aqueous", "cl-dmbpy", "Cl−Me"), ("aqueous", "cl-ome", "Cl−OMe"))
_CL_COLS = ("series", "relaxed", "adiabatic")


def _summary_cl_anchor(i, j):   # SUMMARY (2): «ref 8 Cl−H ×a → ×b → ×c, … aqueous … Cl−OMe ×a → ×b → ×c» — slot (i, j) captured
    parts = []
    for k, (series, _, lab) in enumerate(_CL_ROWS):
        slots = " → ".join("×" + (N if (k, m) == (i, j) else r"[\d.]+") for m in range(3))
        head = "ref 8 " if k == 0 else ("aqueous " if series == "aqueous" and _CL_ROWS[k - 1][0] != "aqueous" else "")
        parts.append(f"{head}{lab} {slots}")
    return ", ".join(parts) + r" \(programmatic → Os\(II\) relaxed → both relaxed\)"


CHECKS += [
    # paper §3.3 — Cl relaxed in both states (every anchor within one line of the paragraph, #16)
    ("paper §3.3 Cl λ_III → relaxed_os3", PAPER_RESULTS, rf"the same protocol \(λ_III {N} meV; Os–Cl", OS3,
     lambda d: d["vs_vertical"]["lambda_os3_meV"]["cl"], 0.6),
    ("paper §3.3 Cl Os–Cl, Os(II) minimum → 83 acceptors", PAPER_RESULTS, rf"Os–Cl {N} Å on its Os\(II\) minimum and", V83,
     lambda d: _ac_os_cl(d, "relaxed"), 0.005),
    ("paper §3.3 Cl Os–Cl, Os(III) minimum → 83 acceptors", PAPER_RESULTS, rf"minimum and {N} Å on Os\(III\)'s own, ", V83,
     lambda d: _ac_os_cl(d, "relaxed_os3"), 0.005),
    ("paper §3.3 Cl Os–Cl over Os(II) range → 83 acceptors", PAPER_RESULTS, rf"Os\(III\)'s own, {N} and [\d.]+ Å over", V83,
     lambda d: _ac_os_cl(d, "relaxed", over=True), 0.005),
    ("paper §3.3 Cl Os–Cl over Os(III) range → 83 acceptors", PAPER_RESULTS, rf"Os\(III\)'s own, [\d.]+ and {N} Å over", V83,
     lambda d: _ac_os_cl(d, "relaxed_os3", over=True), 0.005),
    *[(f"paper §3.3 Cl {series} {lab} {col} → 83 acceptors", PAPER_RESULTS, anchor, V83,
       lambda d, s=series, p=pair, c=col: _ac_ratio(d, s, p, c), 0.005)
      for series, pair, lab, col, anchor in (
          ("ref 8", "cl-bpy", "Cl−H", "series", rf"ref 8's Cl−H from {N} to"),
          ("ref 8", "cl-bpy", "Cl−H", "adiabatic", rf"Cl−H from [\d.]+ to {N} times the measured \("),
          ("ref 8", "cl-bpy", "Cl−H", "relaxed", rf"times the measured \({N} with Os\(III\)"),
          ("ref 8", "cl-dmbpy", "Cl−Me", "series", rf"vertical\), Cl−Me from {N} to"),
          ("ref 8", "cl-dmbpy", "Cl−Me", "adiabatic", rf"vertical\), Cl−Me from [\d.]+ to {N} and Cl−OMe"),
          ("ref 8", "cl-ome", "Cl−OMe", "series", rf"and Cl−OMe from {N} to [\d.]+ times, the aqueous"),
          ("ref 8", "cl-ome", "Cl−OMe", "adiabatic", rf"and Cl−OMe from [\d.]+ to {N} times, the aqueous"),
          ("aqueous", "cl-dmbpy", "Cl−Me", "series", rf"the aqueous Cl−Me from {N} to"),
          ("aqueous", "cl-dmbpy", "Cl−Me", "adiabatic", rf"the aqueous Cl−Me from [\d.]+ to {N} and Cl−OMe"),
          ("aqueous", "cl-ome", "Cl−OMe", "series", rf"from {N} to [\d.]+ times \(five rows"),
          ("aqueous", "cl-ome", "Cl−OMe", "adiabatic", rf"from [\d.]+ to {N} times \(five rows"))],
    ("paper §3.3 Cl Os(III) step, Cl−Me back → 83 acceptors", PAPER_RESULTS, rf"back by only {N} and [\d.]+ mV per substituent", V83,
     lambda d: -_ac(d)["computed_pairs"]["cl-dmbpy"]["move_from_relaxed_mV"], 0.05),
    ("paper §3.3 Cl Os(III) step, Cl−OMe back → 83 acceptors", PAPER_RESULTS, rf"back by only [\d.]+ and {N} mV per substituent", V83,
     lambda d: -_ac(d)["computed_pairs"]["cl-ome"]["move_from_relaxed_mV"], 0.05),
    ("paper §3.3 Cl−OMe geometry move → 83 acceptors", PAPER_RESULTS, rf"\(Cl−OMe moves by {N} mV per substituent\), but away", V83,
     lambda d: _ac(d)["computed_pairs"]["cl-ome"]["move_from_series_mV"], 0.05),
    ("paper §3.3 aqueous source Cl−Me → 83 aqueous", PAPER_RESULTS, rf"own optimised B3LYP \({N} and [\d.]+ times the measured\)", V83,
     lambda d: _aq_source(d, "cl", "dmbpy"), 0.005),
    ("paper §3.3 aqueous source Cl−OMe → 83 aqueous", PAPER_RESULTS, rf"own optimised B3LYP \([\d.]+ and {N} times the measured\)", V83,
     lambda d: _aq_source(d, "cl", "ome"), 0.005),
    ("paper §3.3 Cl ref 8 donors within → 83 adiabatic", PAPER_RESULTS, rf"donor pairs come within {N} mV per substituent of experiment", V83,
     lambda d: max(p["adiabatic_gap_mV"] for p in _ad(d)["pairs_vs_measured"] if p["series_name"] == "ref 8"), 0.05),
    ("paper §3.3 Cl Koopmans own minimum → 83 acceptors", PAPER_RESULTS, rf"Cl's Koopmans offset moves by {N} eV with Os\(III\) on its", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_own_minimum"), 0.0005),
    ("paper §3.3 Cl Koopmans vertical → 83 acceptors", PAPER_RESULTS, rf"by \+{N} eV with Os\(III\) vertical on the relaxed Os\(II\)", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_os2_minimum"), 0.0005),
    ("paper §3.3 Cl H→Cl gap programmatic → 83 acceptors", PAPER_RESULTS, rf"\(H to Cl {N} meV on the programmatic", V83,
     lambda d: _ac_gap(d, "bpy-cl", "programmatic"), 0.6),
    ("paper §3.3 Cl H→Cl gap both relaxed → 83 acceptors", PAPER_RESULTS, rf"on the programmatic, {N} meV with both", V83,
     lambda d: _ac_gap(d, "bpy-cl", "os3_on_own_minimum"), 0.6),
    ("paper §3.3 robust Cl low, both relaxed → 83 acceptors", PAPER_RESULTS, rf"reach Cl on the programmatic geometry and {N} to", V83,
     lambda d: min(_ac_ratio(d, s, p) for s, p, _ in _CL_ROWS), 0.05),
    ("paper §3.3 robust Cl high, both relaxed → 83 acceptors", PAPER_RESULTS, rf"reach Cl on the programmatic geometry and [\d.]+ to {N} times", V83,
     lambda d: max(_ac_ratio(d, s, p) for s, p, _ in _CL_ROWS), 0.05),
    # paper §2.3 — the acceptor point beside the donors
    ("paper §2.3 Cl point, Os(II) relaxed → relaxed_os2", METHODS, rf"Os\(II\) moves Cl by {N} meV and NO₂ by", OS2,
     lambda d: abs(d["vs_series"]["point_shift_eV"]["cl"]) * 1000, 0.6),
    ("paper §2.3 NO₂ point, Os(II) relaxed → relaxed_os2", METHODS, rf"and NO₂ by {N} meV, and relaxing", OS2,
     lambda d: abs(d["vs_series"]["point_shift_eV"]["no2"]) * 1000, 0.6),
    ("paper §2.3 Cl point, both relaxed → 83 acceptors", METHODS, rf"leaves them within {N} and [\d.]+ meV, while the", V83,
     lambda d: abs(_ac(d)["acceptor_point_shift_eV"]["cl"]) * 1000, 0.6),
    ("paper §2.3 NO₂ point, both relaxed → 83 acceptors", METHODS, rf"leaves them within [\d.]+ and {N} meV, while the", V83,
     lambda d: abs(_ac(d)["acceptor_point_shift_eV"]["no2"]) * 1000, 0.6),
    ("paper §2.3 Cl pairs per complex → 83 acceptors", METHODS, rf"{N} meV a complex on either geometry", V83, _ac_pair_move_max, 0.5),
    # SUMMARY §Mediator, limits (2) and (4) — one physical line, so no wrap to cross
    ("SUMMARY (2) Cl λ_III → relaxed_os3", SUMMARY, rf"acceptors run of 2026-10-14; λ_III {N} meV\)", OS3,
     lambda d: d["vs_vertical"]["lambda_os3_meV"]["cl"], 0.6),
    *[(f"SUMMARY (2) Cl {s} {lab} {c} → 83 acceptors", SUMMARY, _summary_cl_anchor(i, j), V83,
       lambda d, s=s, p=p, c=c: _ac_ratio(d, s, p, c), 0.005)
      for i, (s, p, lab) in enumerate(_CL_ROWS) for j, c in enumerate(_CL_COLS)],
    *[(f"SUMMARY (2) Cl Os(III) step {k} → 83 acceptors", SUMMARY, anchor, V83,
       lambda d, k=k, sign=sign: sign * _ac(d)["computed_pairs"][k]["move_from_relaxed_mV"], 0.05)
      for k, sign, anchor in (("cl-dmbpy", -1, rf"brings Cl−Me and Cl−OMe back by {N} and"),
                              ("cl-ome", -1, rf"back by [\d.]+ and {N} mV per substituent and takes"),
                              ("cl-bpy", 1, rf"takes Cl−H {N} mV further"))],
    *[(f"SUMMARY (2) Cl Os–Cl {lab} → 83 acceptors", SUMMARY, anchor, V83, fn, 0.005) for lab, anchor, fn in (
        ("Os(II)", rf"its Os–Cl is {N} Å on the Os\(II\) minimum", lambda d: _ac_os_cl(d, "relaxed")),
        ("Os(III)", rf"Os\(II\) minimum and {N} Å on Os\(III\)'s own, ", lambda d: _ac_os_cl(d, "relaxed_os3")),
        ("over Os(II)", rf"Os\(III\)'s own, {N} and [\d.]+ Å over the two crystal ranges", lambda d: _ac_os_cl(d, "relaxed", over=True)),
        ("over Os(III)", rf"Os\(III\)'s own, [\d.]+ and {N} Å over the two crystal ranges", lambda d: _ac_os_cl(d, "relaxed_os3", over=True)),
        ("over Os(III), limit (4)", rf"; NO₂ [\d.]+ Å; Cl {N} Å\)", lambda d: _ac_os_cl(d, "relaxed_os3", over=True)))],
    ("SUMMARY (2) Cl−OMe geometry move → 83 acceptors", SUMMARY, rf"carries these pairs too \(Cl−OMe moves by {N} mV", V83,
     lambda d: _ac(d)["computed_pairs"]["cl-ome"]["move_from_series_mV"], 0.05),
    ("SUMMARY (2) aqueous source Cl−Me → 83 aqueous", SUMMARY, rf"own optimised B3LYP \(×{N}, ×[\d.]+\), so the acceptor", V83,
     lambda d: _aq_source(d, "cl", "dmbpy"), 0.005),
    ("SUMMARY (2) aqueous source Cl−OMe → 83 aqueous", SUMMARY, rf"own optimised B3LYP \(×[\d.]+, ×{N}\), so the acceptor", V83,
     lambda d: _aq_source(d, "cl", "ome"), 0.005),
    ("SUMMARY (4) Cl Koopmans vertical → 83 acceptors", SUMMARY, rf"Koopmans cascade Δ moves by \+{N} eV with Os\(III\) vertical on the relaxed", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_os2_minimum"), 0.0005),
    ("SUMMARY (4) Cl Koopmans own → 83 acceptors", SUMMARY, rf"\({N} eV on its own minimum\), the column staying", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_own_minimum"), 0.0005),
    # PIPELINE_STATUS — rows 21e · 83, the note under D, §Future ΔG
    ("PIPELINE 21e Cl point vertical → relaxed_os2", PIPELINE, rf"Cl integrated 2026-10-15 \(its point {N} meV", OS2,
     lambda d: d["vs_series"]["point_shift_eV"]["cl"] * 1000, 0.6),
    ("PIPELINE 21e Cl point both → 83 acceptors", PIPELINE, rf"relaxed Os\(II\), {N} meV with both relaxed; λ_III", V83,
     lambda d: _ac(d)["acceptor_point_shift_eV"]["cl"] * 1000, 0.6),
    ("PIPELINE 21e Cl λ_III → relaxed_os3", PIPELINE, rf"with both relaxed; λ_III {N} meV\) — row 83", OS3,
     lambda d: d["vs_vertical"]["lambda_os3_meV"]["cl"], 0.6),
    ("PIPELINE 83 (e) Cl−H programmatic → 83 acceptors", PIPELINE, rf"\(ref 8 Cl−H ×{N} → ×[\d.]+ with both states relaxed\)", V83,
     lambda d: _ac_ratio(d, "ref 8", "cl-bpy", "series"), 0.005),
    ("PIPELINE 83 (e) Cl−H both → 83 acceptors", PIPELINE, rf"\(ref 8 Cl−H ×[\d.]+ → ×{N} with both states relaxed\)", V83,
     lambda d: _ac_ratio(d, "ref 8", "cl-bpy"), 0.005),
    ("PIPELINE 83 (e) donors within → 83 adiabatic", PIPELINE, rf"while ref 8's donors come within {N} mV per substituent", V83,
     lambda d: max(p["adiabatic_gap_mV"] for p in _ad(d)["pairs_vs_measured"] if p["series_name"] == "ref 8"), 0.05),
    ("PIPELINE 83 (e) Koopmans vertical → 83 acceptors", PIPELINE, rf"its own Koopmans cascade moves \+{N} eV with Os\(III\)", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_os2_minimum"), 0.0005),
    ("PIPELINE 83 (e) Koopmans own → 83 acceptors", PIPELINE, rf"\({N} eV on its own minimum\), so the condition is MET", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_own_minimum"), 0.0005),
    ("PIPELINE D 10-15 Cl Table 4 cascade → os_mediator_series", PIPELINE, rf"Table 4 дає Cl {N} еВ",
     "dft/os_mediator_series.json", lambda d: next(c for c in d["complexes"] if c["name"] == "cl")["cascade_delta_eV"], 0.00005),
    ("PIPELINE D 10-15 Cl Koopmans vertical → 83 acceptors", PIPELINE, rf"Os\(II\), рухається на \+{N} еВ, а з", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_os2_minimum"), 0.0005),
    ("PIPELINE D 10-15 Cl Koopmans own → 83 acceptors", PIPELINE, rf"на власному мінімумі — на {N} еВ; пару", V83,
     lambda d: _ac_koop(d, "cl", "os3_on_own_minimum"), 0.0005),
    ("PIPELINE D 10-15 H→Cl programmatic → 83 acceptors", PIPELINE, rf"\(H→Cl {N} → [\d.]+ меВ\)", V83,
     lambda d: _ac_gap(d, "bpy-cl", "programmatic"), 0.6),
    ("PIPELINE D 10-15 H→Cl both → 83 acceptors", PIPELINE, rf"\(H→Cl [\d.]+ → {N} меВ\)", V83,
     lambda d: _ac_gap(d, "bpy-cl", "os3_on_own_minimum"), 0.6),
    ("PIPELINE D 10-15 Cl→COOH half-relaxed → 83 acceptors", PIPELINE, rf"Cl→COOH \({N} меВ, релаксовано один член\)", V83,
     lambda d: _ac(d)["table4_neighbours_half_relaxed"]["cl-dcbpy"]["programmatic_koopmans_gap_meV"], 0.6),
    ("PIPELINE D 10-15 Cl pairs per complex → 83 acceptors", PIPELINE, rf"пари Cl зсуваються до {N} меВ на комплекс", V83,
     _ac_pair_move_max, 0.5),
    ("PIPELINE D 10-15 Cl point → 83 acceptors", PIPELINE, rf"абсолютна точка — на {N} меВ \(не різниця\)", V83,
     lambda d: _ac(d)["acceptor_point_shift_eV"]["cl"] * 1000, 0.6),
    *[(f"PIPELINE D 10-15 ref 8 Cl−H {c} → 83 acceptors", PIPELINE, anchor, V83,
       lambda d, c=c: _ac_ratio(d, "ref 8", "cl-bpy", c), 0.005)
      for c, anchor in (("series", rf"\(ref 8 Cl−H ×{N} → ×[\d.]+ → ×[\d.]+; від"),
                        ("relaxed", rf"\(ref 8 Cl−H ×[\d.]+ → ×{N} → ×[\d.]+; від"),
                        ("adiabatic", rf"\(ref 8 Cl−H ×[\d.]+ → ×[\d.]+ → ×{N}; від"))],
    ("PIPELINE D 10-15 donors within → 83 adiabatic", PIPELINE, rf"донори ref 8 сходяться до {N} мВ на замісник", V83,
     lambda d: max(p["adiabatic_gap_mV"] for p in _ad(d)["pairs_vs_measured"] if p["series_name"] == "ref 8"), 0.05),
    *[(f"PIPELINE §Future ΔG ref 8 Cl−H {c} → 83 acceptors", PIPELINE, anchor, V83,
       lambda d, c=c: _ac_ratio(d, "ref 8", "cl-bpy", c), 0.005)
      for c, anchor in (("series", rf"\(ref 8 Cl−H ×{N} → ×[\d.]+; `83` `acceptors`\)"),
                        ("adiabatic", rf"\(ref 8 Cl−H ×[\d.]+ → ×{N}; `83` `acceptors`\)"))],
    # paper/00_OUTLINE §3.3 and L3 caveat 2
    *[(f"OUTLINE §3.3 ref 8 Cl−H {c} → 83 acceptors", OUTLINE, anchor, V83,
       lambda d, c=c: _ac_ratio(d, "ref 8", "cl-bpy", c), 0.005)
      for c, anchor in (("series", rf"ref 8 Cl−H ×{N} → ×[\d.]+, so the acceptor-side"),
                        ("adiabatic", rf"ref 8 Cl−H ×[\d.]+ → ×{N}, so the acceptor-side"))],
    ("L3 caveat 2 Cl Os–Cl, Os(II) → 83 acceptors", L3, rf"the acceptors run\) — Os–Cl {N} Å on its Os\(II\)", V83,
     lambda d: _ac_os_cl(d, "relaxed"), 0.005),
    ("L3 caveat 2 Cl Os–Cl, Os(III) → 83 acceptors", L3, rf"Os\(II\) minimum and {N} Å on Os\(III\)'s own; its pairs", V83,
     lambda d: _ac_os_cl(d, "relaxed_os3"), 0.005),
]


def _ac_slope(d, k, col):   # eV/σ, or eV over the span — a printed slope once its members are relaxed
    return _ac(d)["slopes"][k][col]


def _no2_koop_ratio(d, f):   # how many times NO₂'s own cascade move exceeds its 5-meV Table 4 gap to SO₂CF₃
    moves = (abs(_ac_koop(d, "no2", w)) for w in ("os3_on_os2_minimum", "os3_on_own_minimum"))
    return f(moves) / _ac(d)["table4_neighbours_half_relaxed"]["no2-so2cf3"]["programmatic_koopmans_gap_meV"] * 1000

CHECKS += [
    # paper §3.3 — NO₂, the acceptor end of the fit set, relaxed in both states (anchors within one line, #16)
    ("paper §3.3 slope ① programmatic, 4 fit members → 83 acceptors", PAPER_RESULTS, rf"H and NO₂ moves from {N} to", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "series_eV_per_sigma"), 0.0005),
    ("paper §3.3 slope ① both relaxed, 4 fit members → 83 acceptors", PAPER_RESULTS, rf"moves from [{_DASHES}\-]?[\d.]+ to {N} eV per σ unit — shallower", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "adiabatic_eV_per_sigma"), 0.0005),
    ("paper §3.3 slope ① move over span → 83 acceptors", PAPER_RESULTS, rf"shallower, {N} eV over their", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "move_over_span_eV"), 0.0005),
    ("paper §3.3 NO₂ λ_III → relaxed_os3", PAPER_RESULTS, rf"NO₂, relaxed the same way \(λ_III {N} meV, the largest", OS3,
     lambda d: d["vs_vertical"]["lambda_os3_meV"]["no2"], 0.6),
    *[(f"paper §3.3 NO₂ Os–Cl {lab} → 83 acceptors", PAPER_RESULTS, anchor, V83, fn, 0.005) for lab, anchor, fn in (
        ("Os(II)", rf"the five; Os–Cl {N} and [\d.]+ Å on the Os\(II\) and Os\(III\) minima", lambda d: _ac_os_cl(d, "relaxed", n="no2")),
        ("Os(III)", rf"the five; Os–Cl [\d.]+ and {N} Å on the Os\(II\) and Os\(III\) minima", lambda d: _ac_os_cl(d, "relaxed_os3", n="no2")),
        ("over Os(II)", rf"minima, {N} and [\d.]+ Å over the same ranges", lambda d: _ac_os_cl(d, "relaxed", over=True, n="no2")),
        ("over Os(III)", rf"minima, [\d.]+ and {N} Å over the same ranges", lambda d: _ac_os_cl(d, "relaxed_os3", over=True, n="no2")))],
    ("paper §3.3 NO₂ Koopmans own minimum → 83 acceptors", PAPER_RESULTS, rf"{N} eV with Os\(III\) on its own minimum and by \+[\d.]+ eV with Os\(III\) vertical, ", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_own_minimum"), 0.0005),
    ("paper §3.3 NO₂ Koopmans vertical → 83 acceptors", PAPER_RESULTS, rf"and by \+{N} eV with Os\(III\) vertical, ", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_os2_minimum"), 0.0005),
    ("paper §3.3 NO₂ move/gap low → 83 acceptors", PAPER_RESULTS, rf"vertical, {N} to [\d.]+ times the [\d.]+ meV that", V83,
     lambda d: _no2_koop_ratio(d, min), 0.6),
    ("paper §3.3 NO₂ move/gap high → 83 acceptors", PAPER_RESULTS, rf"vertical, [\d.]+ to {N} times the [\d.]+ meV that", V83,
     lambda d: _no2_koop_ratio(d, max), 0.6),
    ("paper §3.3 NO₂ move/gap, the gap → 83 acceptors", PAPER_RESULTS, rf"times the {N} meV that", V83,
     lambda d: _ac(d)["table4_neighbours_half_relaxed"]["no2-so2cf3"]["programmatic_koopmans_gap_meV"], 0.06),
    # paper §3.3 — the SO₂CF₃ sentence (⚖️ 2026-10-15: a candidate, not an optimum): its gap above NO₂, both signs of NO₂'s own move
    ("paper §3.3 SO₂CF₃ gap above NO₂ → 83 half-relaxed", PAPER_RESULTS, rf"the Koopmans offset of \*\*SO₂CF₃\*\* lies {N} meV above NO₂'s", V83,
     lambda d: _ac(d)["table4_neighbours_half_relaxed"]["no2-so2cf3"]["programmatic_koopmans_gap_meV"], 0.5),
    ("paper §3.3 SO₂CF₃ clause: NO₂ move, Os(III) vertical → 83 acceptors", PAPER_RESULTS, rf"relaxing NO₂ alone moves\s+its own Koopmans offset by \+{N} eV with Os\(III\) vertical", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_os2_minimum"), 0.005),
    ("paper §3.3 SO₂CF₃ clause: NO₂ move, own minimum → 83 acceptors", PAPER_RESULTS, rf"vertical and by {N} eV on its own", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_own_minimum"), 0.005),
    # the slope §3.3 sets against ωB97X — Me · H · NO₂, complete once NO₂ relaxed (83 `slope_me_h_no2`)
    *[(f"{lab} slope Me·H·NO₂ {col} → 83 acceptors", where, anchor, V83,
       lambda d, c=col: _ac_slope(d, "slope_me_h_no2", c), 0.0005)
      for lab, where, col, anchor in (
          ("paper §3.3", PAPER_RESULTS, "series_eV_per_sigma", rf"all three relaxed — moves from {N} to"),
          ("paper §3.3", PAPER_RESULTS, "adiabatic_eV_per_sigma", rf"all three relaxed — moves from [{_DASHES}\-]?[\d.]+ to {N} eV per σ unit"),
          ("paper §3.3", PAPER_RESULTS, "move_over_span_eV", rf"eV per σ unit, {N} eV over their σ span;"),
          ("SUMMARY (4)", SUMMARY, "series_eV_per_sigma", rf"all three relaxed — moves {N} → "),
          ("SUMMARY (4)", SUMMARY, "adiabatic_eV_per_sigma", rf"all three relaxed — moves [{_DASHES}\-]?[\d.]+ → {N} eV/σ"),
          ("SUMMARY (4)", SUMMARY, "move_over_span_eV", rf"eV/σ, {N} eV over its span, about 1.5"),
          ("PIPELINE D 10-15", PIPELINE, "series_eV_per_sigma", rf"усі три релаксовано, — рухається {N} → "),
          ("PIPELINE D 10-15", PIPELINE, "adiabatic_eV_per_sigma", rf"усі три релаксовано, — рухається [{_DASHES}\-]?[\d.]+ → {N} еВ/σ"),
          ("PIPELINE D 10-15", PIPELINE, "move_over_span_eV", rf"еВ/σ, {N} еВ на розмах, лише в"))],
    # paper/00_OUTLINE §3.3 — the NO₂ clause
    ("OUTLINE §3.3 slope ① programmatic → 83 acceptors", OUTLINE, rf"into a computation, {N} → ", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "series_eV_per_sigma"), 0.0005),
    ("OUTLINE §3.3 slope ① both relaxed → 83 acceptors", OUTLINE, rf"into a computation, [{_DASHES}\-]?[\d.]+ → {N} eV/σ", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "adiabatic_eV_per_sigma"), 0.0005),
    ("OUTLINE §3.3 NO₂/SO₂CF₃ gap → 83 acceptors", OUTLINE, rf"NO₂/SO₂CF₃ \({N} meV\) undecided", V83,
     lambda d: _ac(d)["table4_neighbours_half_relaxed"]["no2-so2cf3"]["programmatic_koopmans_gap_meV"], 0.06),
    ("OUTLINE §3.3 NO₂ move vertical → 83 acceptors", OUTLINE, rf"Koopmans offset moving \+{N} / ", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_os2_minimum"), 0.005),
    ("OUTLINE §3.3 NO₂ move own → 83 acceptors", OUTLINE, rf"Koopmans offset moving \+[\d.]+ / {N} eV\)", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_own_minimum"), 0.005),
    # SUMMARY §Mediator, limits (2)–(4)
    ("SUMMARY (2) NO₂ λ_III → relaxed_os3", SUMMARY, rf"\*\*NO₂, relaxed the same way\*\* \(λ_III {N} meV", OS3,
     lambda d: d["vs_vertical"]["lambda_os3_meV"]["no2"], 0.6),
    *[(f"SUMMARY (2) NO₂ Os–Cl {lab} → 83 acceptors", SUMMARY, anchor, V83, fn, 0.005) for lab, anchor, fn in (
        ("Os(II)", rf"relaxed points; Os–Cl {N} and [\d.]+ Å on the two minima", lambda d: _ac_os_cl(d, "relaxed", n="no2")),
        ("Os(III)", rf"relaxed points; Os–Cl [\d.]+ and {N} Å on the two minima", lambda d: _ac_os_cl(d, "relaxed_os3", n="no2")),
        ("over Os(II)", rf"two minima, {N} and [\d.]+ Å over the crystal ranges\), has no measured", lambda d: _ac_os_cl(d, "relaxed", over=True, n="no2")),
        ("over Os(III)", rf"two minima, [\d.]+ and {N} Å over the crystal ranges\), has no measured", lambda d: _ac_os_cl(d, "relaxed_os3", over=True, n="no2")),
        ("over Os(III), limit (4)", rf"the three donors; NO₂ {N} Å; Cl", lambda d: _ac_os_cl(d, "relaxed_os3", over=True, n="no2")))],
    ("SUMMARY (3) NO₂ Koopmans own → 83 acceptors", SUMMARY, rf"moves its own Koopmans cascade Δ by {N} eV \(\+", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_own_minimum"), 0.0005),
    ("SUMMARY (3) NO₂ Koopmans vertical → 83 acceptors", SUMMARY, rf"cascade Δ by [{_DASHES}\-]?[\d.]+ eV \(\+{N} with Os\(III\) vertical\), 20", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_os2_minimum"), 0.0005),
    ("SUMMARY (4) slope ① programmatic → 83 acceptors", SUMMARY, rf"the slope moves {N} → [{_DASHES}\-]?[\d.]+ eV/σ, [\d.]+ eV over the span, shallower", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "series_eV_per_sigma"), 0.0005),
    ("SUMMARY (4) slope ① both relaxed → 83 acceptors", SUMMARY, rf"the slope moves [{_DASHES}\-]?[\d.]+ → {N} eV/σ, [\d.]+ eV over the span, shallower", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "adiabatic_eV_per_sigma"), 0.0005),
    ("SUMMARY (4) slope ① over span → 83 acceptors", SUMMARY, rf"eV/σ, {N} eV over the span, shallower", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "move_over_span_eV"), 0.0005),
    ("SUMMARY (4) NO₂ Koopmans own → 83 acceptors", SUMMARY, rf"its own Koopmans cascade Δ moves by {N} eV on its own minimum \(\+", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_own_minimum"), 0.0005),
    # PIPELINE_STATUS — banner, rows 21e · 83 (e), the note under D
    ("PIPELINE 21e NO₂ point vertical → relaxed_os2", PIPELINE, rf"NO₂ integrated the same day \(point {N} meV", OS2,
     lambda d: d["vs_series"]["point_shift_eV"]["no2"] * 1000, 0.6),
    ("PIPELINE 21e NO₂ point both → 83 acceptors", PIPELINE, rf"meV / \+{N} meV on the two geometries", V83,
     lambda d: _ac(d)["acceptor_point_shift_eV"]["no2"] * 1000, 0.6),
    ("PIPELINE 21e NO₂ λ_III → relaxed_os3", PIPELINE, rf"on the two geometries, λ_III {N} meV, the largest", OS3,
     lambda d: d["vs_vertical"]["lambda_os3_meV"]["no2"], 0.6),
    ("PIPELINE 83 (e) NO₂ slope programmatic → 83 acceptors", PIPELINE, rf"\(four of the five\) {N} → ", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "series_eV_per_sigma"), 0.0005),
    ("PIPELINE 83 (e) NO₂ slope both relaxed → 83 acceptors", PIPELINE, rf"\(four of the five\) [{_DASHES}\-]?[\d.]+ → {N} eV/σ", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "adiabatic_eV_per_sigma"), 0.0005),
    ("PIPELINE 83 (e) NO₂ Koopmans own → 83 acceptors", PIPELINE, rf"its own cascade moving {N} eV \(\+", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_own_minimum"), 0.0005),
    ("PIPELINE D 10-15 NO₂ slope programmatic → 83 acceptors", PIPELINE, rf"COOH не релаксовано\) рухається {N} → [{_DASHES}\-]?[\d.]+ еВ/σ", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "series_eV_per_sigma"), 0.0005),
    ("PIPELINE D 10-15 NO₂ slope both relaxed → 83 acceptors", PIPELINE, rf"COOH не релаксовано\) рухається [{_DASHES}\-]?[\d.]+ → {N} еВ/σ", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "adiabatic_eV_per_sigma"), 0.0005),
    ("PIPELINE D 10-15 NO₂ slope over span → 83 acceptors", PIPELINE, rf"еВ/σ, {N} еВ на розмах, тобто пологіший", V83,
     lambda d: _ac_slope(d, "slope_1_relaxed_fit_members", "move_over_span_eV"), 0.0005),
    ("PIPELINE D 10-15 NO₂ Koopmans own → 83 acceptors", PIPELINE, rf"Δ NO₂ рухається на {N} еВ з Os", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_own_minimum"), 0.0005),
    ("PIPELINE D 10-15 NO₂ Koopmans vertical → 83 acceptors", PIPELINE, rf"мінімумі й на \+{N} еВ з вертикальним", V83,
     lambda d: _ac_koop(d, "no2", "os3_on_os2_minimum"), 0.0005),
    ("PIPELINE D 10-15 NO₂/SO₂CF₃ gap → 83 acceptors", PIPELINE, rf"пару NO₂→SO₂CF₃ \({N} меВ\) за нерелаксованого", V83,
     lambda d: _ac(d)["table4_neighbours_half_relaxed"]["no2-so2cf3"]["programmatic_koopmans_gap_meV"], 0.06),
    # L3 caveat 2
    *[(f"L3 caveat 2 NO₂ Os–Cl {lab} → 83 acceptors", L3, anchor, V83, fn, 0.005) for lab, anchor, fn in (
        ("Os(II)", rf"NO₂ the same day — Os–Cl {N} and", lambda d: _ac_os_cl(d, "relaxed", n="no2")),
        ("Os(III)", rf"Os–Cl [\d.]+ and {N} Å on the two minima, no measured pair", lambda d: _ac_os_cl(d, "relaxed_os3", n="no2")))],
]

_COUNT_WORDS = {4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten"}


def test_paper_35_shared_shift_word_claims_hold():
    """§3.5 says in WORDS what no number pin can read: the 4.44 V convention alone «turns no cell uphill», the functional
    term is «the osmium side only» of the device couple, and every cell stays downhill without the shared terms (95)."""
    d = C("dft/cascade_like_for_like.json")["shared_shifts"]
    text = doc(PAPER_RESULTS)
    assert "alone it turns no cell uphill" in text and d["terms"]["she_abs_4_44"]["n_uphill"] == 0, \
        "§3.5 says the 4.44 V convention alone turns no cell uphill — 95's shared_shifts disagrees, rewrite the sentence"
    assert d["terms"]["functional_os_side"]["applies_to"] == "chloro (device, programmatic)", \
        "§3.5 sets the functional term against the device couple only — 95 now applies it elsewhere"


def test_paper_33_acceptor_column_claim_holds():
    """Paper §3.3 and §2.3 name WHICH points are relaxed — the sentences an acceptor landing makes false. Each is held
    to the 21e caches themselves (a point counts once both its rows exist), not to 83's record, so a stale 83 reds too.

    CAN catch: the count word («five» since NO₂) drifting from the relaxed members; a sentence naming the relaxed set after a point lands
    (or before it lands); 83 not re-run since a point landed in both 21e caches; the column losing its order on any of
    the three geometries. CANNOT catch: whether the paper should say it at all."""
    ac = C(V83)["relaxed_geometry_check"]["acceptors"]
    o2, o3 = C(OS2)["complexes"], C(OS3)["complexes"]
    sigma = {n: c["sigma_para"] for n, c in o2.items()}
    both = sorted((n for n, c in o3.items() if "dE_red_adiabatic_eV" in c and "dE_red_eV" in o2.get(n, {})), key=lambda n: sigma[n])
    members = sorted(ac["members"], key=lambda n: sigma[n])
    assert members == both, "83 is stale against the 21e caches — re-run 83 after a point lands in both"
    assert len(members) in _COUNT_WORDS, f"{len(members)} relaxed members — extend _COUNT_WORDS"
    paper, methods = doc(PAPER_RESULTS), doc(METHODS)
    assert f"over the {_COUNT_WORDS[len(members)]} relaxed members the column stays monotonic" in paper, \
        "paper §3.3 names a different number of relaxed members than the 21e caches hold"
    fit = C("dft/os_mediator_series.json")["lfer"]["fit_set"]
    assert ("only OMe, Me and H of the fit set being relaxed" in paper) == (sorted(n for n in fit if n in both) == ["bpy", "dmbpy", "ome"])
    assert ("on the one acceptor point, Cl," in methods) == (ac["acceptors"] == ["cl"])
    assert ("the Os(II) points of OMe, Me, H and Cl " in methods) == (members == ["ome", "dmbpy", "bpy", "cl"])
    relaxed_fit = sorted(n for n in fit if n in both)
    assert ("on the two acceptor points, " in methods) == (ac["acceptors"] == ["cl", "no2"])
    assert ("the Os(II) points of OMe, Me, H, Cl and NO₂ " in methods) == (members == ["ome", "dmbpy", "bpy", "cl", "no2"])
    assert ("four of the five fit-set members relaxed (COOH is not)" in paper) == \
        (len(fit) == 5 and set(fit) - set(relaxed_fit) == {"dcbpy"})
    assert ("of NO₂ and SO₂CF₃ (5.0 meV) only NO₂ is (below)" in paper) == ("no2" in both and "so2cf3" not in both)
    lam = C(OS3)["vs_vertical"]["lambda_os3_meV"]
    assert ("(λ_III 150 meV, the largest of\nthe five;" in paper) == (len(members) == 5 and max(members, key=lambda n: lam[n]) == "no2")
    s1 = ac["slopes"].get("slope_1_relaxed_fit_members", {})
    assert ("per σ unit — shallower," in paper) == (bool(s1) and abs(s1["adiabatic_eV_per_sigma"]) < abs(s1["series_eV_per_sigma"]))
    assert ("no measured counterpart in any of the three series, so it adds no pair against experiment" in paper) == \
        ("no2" in ac["acceptors"] and not any("no2" in p["pair"] for p in ac["pairs_vs_measured"]))
    for g in ("programmatic", "os3_on_os2_minimum", "os3_on_own_minimum"):
        seq = [ac["koopmans_cascade_delta_eV"][n][g] for n in members]
        assert all(a < b for a, b in itertools.pairwise(seq)), f"the column is not monotonic on {g}, yet the paper says it is"


# ── HW.5.IS malate chelation (93, 2026-10-15) ⟷ the ⊕ under the cathode medium's weakest link (01_03 §3.5) + SUMMARY ──
MALATE_CHEL = "chemistry/malate_metal_chelation.json"
CANON_0103 = "docs/01_03_EBFC_Enzymatic_Bio_Fuel_Cell.md"
CHECKS += [
    ("malate α Co upper → 93", CANON_0103, rf"Co\(II\): \*\*α ≈ [\d.]+–{N}\*\*",
     MALATE_CHEL, lambda d: d["by_metal"]["Co"]["alpha_max_ADVERSE"], 0.5),
    ("malate α Cu upper → 93", CANON_0103, rf"Cu\(II\): \*\*α ≈ [\d.]+–{N}\*\*",
     MALATE_CHEL, lambda d: d["by_metal"]["Cu"]["alpha_max_ADVERSE"], 5.0),
    ("malate α Ce (Buzko) upper → 93", CANON_0103, rf"Ce\(III\): \*\*α ≈ [\d.]+–{N}\*\* за єдиним",
     MALATE_CHEL, lambda d: max(x["alpha"] for x in d["readings"]["ce_buzko"]["rows"].values()), 5.0),
    ("malate α Ce adverse (secondary) → 93", SUMMARY, rf"\| Ce\(III\) \| \*\*[\d.]+ – {N}\*\* \|",
     MALATE_CHEL, lambda d: d["by_metal"]["Ce"]["alpha_max_ADVERSE"], 50.0),
]


# ── HW.24 replicate power (100, 2026-10-20) ⟷ SUMMARY §«How Many Replicate Coupons per Arm?». The section rounds ratios
# UP and CV ceilings and probabilities DOWN (in-silico §When Modifying #43), so each pin checks the ROUNDED number exactly.
REPL = "kinetics/coin_replicate_power.json"


def _ceil2(x):
    return math.ceil(round(x * 100, 9)) / 100


def _floor2(x):
    return math.floor(round(x * 100, 9)) / 100


def _floor_pct1(x):
    return math.floor(round(x * 1000, 9)) / 10


def _cells(head, j, width, unit=""):
    """A table row of `width` cells after `head`, the j-th one captured."""
    cells = [(N if i == j else r"[\d.]+") + unit for i in range(width)]
    return rf"(?m)^\| {head} \| " + r" \| ".join(cells) + r" \|$"


def _bracket_cell(n, j, half):
    """The two-arm table: four «×own ⊥ ×pooled» cells per row; capture one half of the j-th."""
    cells = []
    for i in range(4):
        own, pooled = (N if (i == j and half == 0) else r"[\d.]+"), (N if (i == j and half == 1) else r"[\d.]+")
        cells.append(rf"×{own} ⊥ ×{pooled}")
    return rf"(?m)^\| {n} \| " + r" \| ".join(cells) + r" \|$"


_TWO_ARM_KEYS = (("ratio_detectable_equal_n", "0.10"), ("ratio_detectable_equal_n", "0.20"),
                 ("ratio_detectable_single_vs_n", "0.10"), ("ratio_detectable_single_vs_n", "0.20"))
CHECKS += [
    *[(f"replicate two-arm n={n} col {j} {'pooled' if h else 'own'} → 100", SUMMARY, _bracket_cell(n, j, h), REPL,
       (lambda nn, kk, cc: lambda d: _ceil2(d["two_arm"][kk][cc][nn]))(n, key + ("_pooled" if h else ""), cv), 0.0)
      for n in "23456" for j, (key, cv) in enumerate(_TWO_ARM_KEYS) for h in (0, 1)],
    *[(f"replicate single-coupon floor CV {cv} → 100", SUMMARY, pat, REPL,
       (lambda cc: lambda d: _floor2(d["two_arm"]["single_coupon_floor"][cc]))(cv), 0.0)
      for cv, pat in (("0.10", rf"stays above ×{N} at CV 10 %"), ("0.20", rf"\(×{N} at CV 20 %\)\.\n"))],
    *[(f"replicate gate {g} {r} n={n} → 100", SUMMARY, _cells(f"{g} · {label}", j, 5, " %"), REPL,
       (lambda gg, rr, nn: lambda d: _floor_pct1(d["gate"]["max_cv_for_best_case"][gg]["by_reading"][rr][nn]))(g, r, n),
       0.0)
      for g, rows in (("C", (("arm_mean", "arm mean"), ("lower_bound", "lower bound"),
                             ("lower_bound_pooled", "lower bound, pooled"), ("every_coupon", "every coupon"))),
                      ("D", (("arm_mean", "arm mean"), ("lower_bound", "lower bound"), ("every_coupon", "every coupon"))))
      for r, label in rows
      for j, n in enumerate("23456")],
    ("replicate C best-case margin → 100", SUMMARY, rf"an arm that loses nothing, ×{N} above 80 %", REPL,
     lambda d: d["gate"]["max_cv_for_best_case"]["C"]["best_case_ratio"] / d["gate"]["max_cv_for_best_case"]["C"]["threshold"],
     0.0),
    ("replicate D target every-coupon n=2 → 100", SUMMARY, rf"passes with probability {N} at n = 2 and [\d.]+ at n = 6",
     REPL, lambda d: _floor2(d["gate"]["D_p_pass_at_target"]["every_coupon"]["0.20"]["2"]), 0.0),
    ("replicate D target every-coupon n=6 → 100", SUMMARY, rf"passes with probability [\d.]+ at n = 2 and {N} at n = 6",
     REPL, lambda d: _floor2(d["gate"]["D_p_pass_at_target"]["every_coupon"]["0.20"]["6"]), 0.0),
    ("replicate E arm mean at threshold → 100", SUMMARY, rf"100 % passes with probability {N} \(arm mean\)",
     REPL, lambda d: d["gate"]["p_pass_at_threshold"]["arm_mean"]["2"], 0.0),
    ("replicate E lower bound at threshold → 100", SUMMARY, rf"\(arm mean\), {N} \(lower bound\)",
     REPL, lambda d: d["gate"]["p_pass_at_threshold"]["lower_bound"]["2"], 1e-4),
    ("replicate selection n=3 CV10 → 100", SUMMARY, rf"lead the others by ×{N} at n = 3 and CV 10 %",
     REPL, lambda d: _ceil2(d["selection"]["ratio_needed"]["0.10"]["3"]), 0.0),
    ("replicate selection n=3 CV20 → 100", SUMMARY, rf"\(×{N} at\nCV 20 %\)",
     REPL, lambda d: _ceil2(d["selection"]["ratio_needed"]["0.20"]["3"]), 0.0),
    *[(f"replicate budget {label} → 100", SUMMARY, pat, REPL, res, 0.0) for label, pat, res in (
        ("control ceiling", rf"the control\s+carries n = {N} and",
         lambda d: d["budget"]["letter_ceiling"]["Ti-6Al-4V"]["max_equal_n_per_arm"]),
        ("CP-Ti ceiling", rf"and CP-Ti n = {N},", lambda d: d["budget"]["letter_ceiling"]["CP-Ti Gr4"]["max_equal_n_per_arm"]),
        ("two-arm n=2", rf"two-arm alloys need {N} at n = 2",
         lambda d: d["budget"]["by_n"]["2"]["per_alloy"]["Ti-6Al-7Nb"]["coupons_needed"]),
        ("two-arm n=3", rf"need [\d.]+ at n = 2 and {N} at n = 3, Ti-6Al-4V",
         lambda d: d["budget"]["by_n"]["3"]["per_alloy"]["Ti-6Al-7Nb"]["coupons_needed"]),
        ("control n=2", rf"Ti-6Al-4V {N} and [\d.]+\. The 30-day",
         lambda d: d["budget"]["by_n"]["2"]["per_alloy"]["Ti-6Al-4V"]["coupons_needed"]),
        ("control n=3", rf"Ti-6Al-4V [\d.]+ and {N}\. The 30-day",
         lambda d: d["budget"]["by_n"]["3"]["per_alloy"]["Ti-6Al-4V"]["coupons_needed"]),
        ("C n=2", rf"runs {N} channel-days at n = 2", lambda d: d["budget"]["by_n"]["2"]["C_channel_days"]),
        ("C n=3", rf"channel-days at n = 2 and {N} at n = 3", lambda d: d["budget"]["by_n"]["3"]["C_channel_days"]),
    )],
]


# ── HW.43 the wood's share (103, 2026-10-20) ⟷ SUMMARY §«How Much of the Stem's Shift Reaches the Anchor?». Ranges and
# sets of thresholds round OUTWARD, «up to» UP, «no less than» DOWN (in-silico §When Modifying #43).
SHARE = "mechanical/anchor_wood_share.json"


def _vals(d, *path):
    x = d
    for k in path:
        x = x[k]
    return [v for v in x.values() if v is not None]


_SH = "anode_bond_stiff"
_SS = "anode_bond_soft"


def _s3(d, side):
    v = [x[side] for x in d["share"]["state3_no_bearing_any_depth_of_102_shift"].values()]
    return min(v) if side == "min" else max(v)


CHECKS += [
    ("share G radiata → 103", SUMMARY, rf"√\(G_LR·G_RT\): about {N} MPa for green", SHARE, lambda d: round(d["inputs"]["G_eff_MPa"]["green_p_radiata_lowest_group"]), 0.0),
    ("share G scots → 103", SUMMARY, rf"⊥ {N} MPa for \*P\.\s+sylvestris\* at 22\.8 % MC", SHARE, lambda d: round(d["inputs"]["G_eff_MPa"]["scots_pine_22_8pct_mc"]), 0.0),
    ("share clearance → 103", SUMMARY, rf"nothing at the anode end: {N} mm of radial clearance", SHARE, lambda d: d["geometry"]["anode_radial_clearance_mm"], 0.0),
    ("share state2 low → 103", SUMMARY, rf"\| {N} – [\d.]+ at the air-dry bark readings;", SHARE, lambda d: _down2(d["share"]["state2_at_air_dry_readings"]["min"]), 0.0),
    ("share state2 high → 103", SUMMARY, rf"\| [\d.]+ – {N} at the air-dry bark readings;", SHARE, lambda d: _up2(d["share"]["state2_at_air_dry_readings"]["max"]), 0.0),
    ("share cap2 stiff → 103", SUMMARY, rf"the anode bond caps it at {N} \(stiff\)", SHARE, lambda d: _up2(d["share"]["state2_cap_rigid_bark"][_SH]), 0.0),
    ("share cap2 soft → 103", SUMMARY, rf"caps it at [\d.]+ \(stiff\) ⊥ {N} \(soft\)", SHARE, lambda d: _up2(d["share"]["state2_cap_rigid_bark"][_SS]), 0.0),
    ("share state3 low → 103", SUMMARY, rf"\| {N} – [\d.]+ over the tie's depth with no bearing", SHARE, lambda d: _down2(_s3(d, "min")), 0.0),
    ("share state3 high → 103", SUMMARY, rf"\| [\d.]+ – {N} over the tie's depth with no bearing", SHARE, lambda d: _up2(_s3(d, "max")), 0.0),
    ("share cap3 stiff → 103", SUMMARY, rf"up to {N} ⊥ [\d.]+ at a rigid bark \|", SHARE, lambda d: _up2(d["share"]["state3_cap_rigid_bark_of_102_shift"][_SH]), 0.0),
    ("share cap3 soft → 103", SUMMARY, rf"up to [\d.]+ ⊥ {N} at a rigid bark \|", SHARE, lambda d: _up2(d["share"]["state3_cap_rigid_bark_of_102_shift"][_SS]), 0.0),
    ("share tie thin → 103", SUMMARY, rf"— {N} ⊥ [\d.]+ mm below\s+the flange seat", SHARE, lambda d: round(d["geometry"]["flange_seat_to_install_day_cambium_mm"]["thin_contact_78"], 1), 0.0),
    ("share tie thick → 103", SUMMARY, rf"— [\d.]+ ⊥ {N} mm below\s+the flange seat", SHARE, lambda d: round(d["geometry"]["flange_seat_to_install_day_cambium_mm"]["thick_side_78"], 1), 0.0),
    ("share cte floor → 103", SUMMARY, rf"never below {N} ppm/K \(a rigid bark", SHARE, lambda d: _down2(d["heat"]["cte_min_ppm_K_over_the_model"]), 0.0),
    ("share cte coupled → 103", SUMMARY, rf"cannot fall below\s+{N} ppm/K, the span following", SHARE, lambda d: _down2(d["heat"]["cte_floor_span_follows_the_wood_ppm_K"]), 0.0),
    ("share reversed pct → 103", SUMMARY, rf"stays under {N} % of", SHARE, lambda d: _ceil1(d["heat"]["reversed_shift_per_K_at_most_of_free_sleeve"] * 100), 0.0),
    ("share grip depth → 103", SUMMARY, rf"a rigid tie {N} mm below the flange\s+seat", SHARE, lambda d: d["heat"]["deeper_tie_reaching_the_sign_change_mm_from_flange_seat"], 0.0),
    ("share grip face → 103", SUMMARY, rf"only within {N} mm of the anode face", SHARE,
     lambda d: _up2(d["geometry"]["span_mm"] - d["heat"]["deeper_tie_reaching_the_sign_change_mm_from_flange_seat"]), 0.0),
    ("share cte reverse → 103", SUMMARY, rf"above the {N} ppm/K at which the pad's travel changes sign", SHARE, lambda d: d["heat"]["cte_travel_reverses_ppm_K_102"], 0.0),
    ("share cte flag → 103", SUMMARY, rf"above the {N} ppm/K at which the pad's travel changes sign", SHARE,
     lambda d: d["heat"]["cte_travel_reverses_ppm_K_102"] if d["heat"]["wood_only_shortens_the_pad_travel"] else -1.0, 0.0),
    ("share s2 cold → 103", SUMMARY, rf"below {N} N/mm \(cold\) ⊥ [\d.]+ N/mm \(hot\)", SHARE, lambda d: math.floor(d["readings"]["state2"]["cold"]["no_below"]), 0.0),
    ("share s2 hot → 103", SUMMARY, rf"below [\d.]+ N/mm \(cold\) ⊥ {N} N/mm \(hot\)", SHARE, lambda d: math.floor(d["readings"]["state2"]["hot"]["no_below"]), 0.0),
    ("share s3 cold depth → 103", SUMMARY, rf"deeper than {N} mm \(cold\) ⊥ [\d.]+\s+mm \(hot\)", SHARE,
     lambda d: math.floor(d["readings"]["state3"]["cold"]["holds_only_deeper_than_mm"] * 10) / 10, 0.0),
    ("share s3 hot depth → 103", SUMMARY, rf"deeper than [\d.]+ mm \(cold\) ⊥ {N}\s+mm \(hot\)", SHARE,
     lambda d: math.floor(d["readings"]["state3"]["hot"]["holds_only_deeper_than_mm"] * 10) / 10, 0.0),
    ("share annulus → 103", SUMMARY, rf"\(A = {N} mm²\)", SHARE, lambda d: d["geometry"]["flange_annulus_mm2"], 0.0),
    ("share bark E low → 103", SUMMARY, rf"readings — {N} MPa \(giant", SHARE, lambda d: d["inputs"]["E_bark_radial_MPa_air_dry"]["sequoia_whole_bark_air_dry"], 0.0),
    ("share bark E mid → 103", SUMMARY, rf"whole bark\) and\s+{N} MPa \(\*P\. taeda\*", SHARE, lambda d: d["inputs"]["E_bark_radial_MPa_air_dry"]["p_taeda_outer_bark_air_dry"], 0.0),
    ("share read kF low → 103", SUMMARY, rf"give {N} – [\d.]+ N/mm and bound", SHARE, lambda d: math.floor(min(d["stiffness_N_per_mm"]["bark_bearing_at_air_dry_readings"].values())), 0.0),
    ("share read kF high → 103", SUMMARY, rf"give [\d.]+ – {N} N/mm and bound", SHARE, lambda d: math.ceil(max(d["stiffness_N_per_mm"]["bark_bearing_at_air_dry_readings"].values())), 0.0),
    ("share Ta state1 → 103", SUMMARY, rf"corner needs {N} on the sway alone in state 1", SHARE, lambda d: d["seam_on_102_closed_form"]["Ta"]["state1"]["sway"], 0.0),
    ("share Ta state1 preload → 103", SUMMARY, rf"state 1 and {N} with `102`'s seasonal", SHARE, lambda d: _up2(d["seam_on_102_closed_form"]["Ta"]["state1"]["hot_preload"]), 0.0),
    ("share Ta state2 sway → 103", SUMMARY, rf"up\s+to {N} on the sway alone and up to", SHARE,
     lambda d: _up2(d["seam_on_102_closed_form"]["Ta"]["state2_at_air_dry_readings_max"]["adverse_reversed"]), 0.0),
    ("share Ta state2 preload → 103", SUMMARY, rf"and up to {N} with the preload;", SHARE,
     lambda d: _up2(d["seam_on_102_closed_form"]["Ta"]["state2_at_air_dry_readings_max"]["adverse_reversed_hot_preload"]), 0.0),
    ("share Ta state3 stiff sway → 103", SUMMARY, rf"at least {N} on the sway alone\s+and [\d.]+ with the preload", SHARE,
     lambda d: _down2(d["seam_on_102_closed_form"]["Ta"]["state3_least_any_depth_and_bearing"][_SH]["adverse_reversed"]), 0.0),
    ("share Ta state3 stiff preload → 103", SUMMARY, rf"at least [\d.]+ on the sway alone\s+and {N} with the preload", SHARE,
     lambda d: _down2(d["seam_on_102_closed_form"]["Ta"]["state3_least_any_depth_and_bearing"][_SH]["adverse_reversed_hot_preload"]), 0.0),
    ("share Ta state3 soft sway → 103", SUMMARY, rf"\({N} ⊥ [\d.]+ at the soft one\)", SHARE,
     lambda d: _down2(d["seam_on_102_closed_form"]["Ta"]["state3_least_any_depth_and_bearing"][_SS]["adverse_reversed"]), 0.0),
    ("share Ta state3 soft preload → 103", SUMMARY, rf"\([\d.]+ ⊥ {N} at the soft one\)", SHARE,
     lambda d: _down2(d["seam_on_102_closed_form"]["Ta"]["state3_least_any_depth_and_bearing"][_SS]["adverse_reversed_hot_preload"]), 0.0),
    ("share Ta past k1 → 103", SUMMARY, rf"and {N} with the preload whatever the tie's depth", SHARE,
     lambda d: (_down2(d["seam_on_102_closed_form"]["Ta"]["state3_least_any_depth_and_bearing"][_SH]["adverse_reversed_hot_preload"])
                if d["seam_on_102_closed_form"]["Ta"]["state3_least_any_depth_and_bearing"][_SH]["adverse_reversed_hot_preload"] >= 1.0 else -1.0), 0.0),
    ("share 4V any share → 103", SUMMARY, rf"Ti-6Al-4V needs at most\s+{N} at any share", SHARE,
     lambda d: _up2(max(d["seam_on_102_closed_form"]["Ti-6Al-4V"]["at_share_1"].values())), 0.0),
    ("share 4V share1 → 102", SUMMARY, rf"Ti-6Al-4V needs at most\s+{N} at any share", "mechanical/wire_liner_shear_lag.json",
     lambda d: _up2(max(v["seam_k"] for v in d["seam_by_alloy"]["Ti-6Al-4V"]["by_share"]["1"]["adverse"].values())), 0.0),
    ("share xylem CTE → 103", SUMMARY, rf"green pine xylem's {N} ppm/K", SHARE, lambda d: d["inputs"]["alpha_xylem_green_ppm_K"], 0.0),
    ("pipeline 103 cap2 stiff", PIPELINE, rf"capped by the anode bond at {N} \(stiff\)", SHARE, lambda d: _up2(d["share"]["state2_cap_rigid_bark"][_SH]), 0.0),
    ("pipeline 103 cap2 soft", PIPELINE, rf"\(stiff\) ⊥ {N} \(soft\) with the sleeve free", SHARE, lambda d: _up2(d["share"]["state2_cap_rigid_bark"][_SS]), 0.0),
    ("pipeline 103 read low", PIPELINE, rf"ties it\), {N}–[\d.]+ at the air-dry", SHARE, lambda d: _down2(d["share"]["state2_at_air_dry_readings"]["min"]), 0.0),
    ("pipeline 103 read high", PIPELINE, rf"ties it\), [\d.]+–{N} at the air-dry", SHARE, lambda d: _up2(d["share"]["state2_at_air_dry_readings"]["max"]), 0.0),
    ("pipeline 103 s3 low", PIPELINE, rf"with the sleeve free, {N}–[\d.]+ over the tie's depth", SHARE, lambda d: _down2(_s3(d, "min")), 0.0),
    ("pipeline 103 s3 high", PIPELINE, rf"with the sleeve free, [\d.]+–{N} over the tie's depth", SHARE, lambda d: _up2(_s3(d, "max")), 0.0),
    ("pipeline 103 cte floor", PIPELINE, rf"stays above {N} ppm/K, past the", SHARE, lambda d: _down2(d["heat"]["cte_min_ppm_K_over_the_model"]), 0.0),
    ("pipeline 103 cte reverse", PIPELINE, rf"past the {N} at which the travel reverses", SHARE, lambda d: d["heat"]["cte_travel_reverses_ppm_K_102"], 0.0),
    ("pipeline 103 Ta least", PIPELINE, rf"Ta needs at least {N} with the preload", SHARE,
     lambda d: _down2(d["seam_on_102_closed_form"]["Ta"]["state3_least_any_depth_and_bearing"][_SH]["adverse_reversed_hot_preload"]), 0.0),
]


def test_wood_share_prose_claims_hold():
    """103: the prose claims no number carries, each held to the cache — SUMMARY «never at any bearing at the soft one»
    (every soft-bond state-2 reading of both pad conclusions None, not just one), «at the soft bond with no bearing it
    stays out at every depth» (every soft-bond state-3 depth reading of both None), and 02_02 §3.5 ⊕ «сухі прочитання
    лежать нижче порогів `103`» (the stiffest air-dry bearing below both pad conclusions' state-2 «no below»)."""
    d = json.loads((REPO / "tools/in_silico/cache" / SHARE).read_text(encoding="utf-8"))
    pads = [n for n in d["state2_bearing_N_per_mm"] if n.startswith(("hot_flip_", "cold_flip_"))]
    assert all(v is None for n in pads for k, v in d["state2_bearing_N_per_mm"][n].items() if k.endswith(_SS))
    assert all(v is None for n in pads for k, v in d["state3_tie_depth_mm_no_bearing"][n].items() if k.endswith(_SS))
    kf_max = max(d["stiffness_N_per_mm"]["bark_bearing_at_air_dry_readings"].values())
    assert kf_max < min(d["readings"]["state2"][s]["no_below"] for s in ("hot", "cold"))


def test_wood_share_state2_table_matches_cache():
    """103: SUMMARY's state-2 table rebuilt from the cache, cell by cell — «never» included, which no numeric pin can see:
    the «at any bond above» cell is «never» exactly when the cache holds None (the soft bond never reaches it); numbers
    round to the side that keeps the cell true (floor for «not below», ceil for «above»)."""
    d = json.loads((REPO / "tools/in_silico/cache" / SHARE).read_text(encoding="utf-8"))
    text = (REPO / SUMMARY).read_text(encoding="utf-8")
    labels = {"share_0.25": "the share reaches `102`'s 0.25 row",
              "ta_k1_sway_alone": "Ta's seam passes k 1 on the sway alone (adverse reversed corner)",
              "ta_k1_hot_preload": "Ta's seam passes k 1 with `102`'s hot preload (adverse reversed corner)",
              "hot": "the centre pad's hot conclusion flips", "cold": "the centre pad's cold conclusion flips"}
    assert set(labels) == set(d["readings"]["state2"])
    for name, label in labels.items():
        no, yes = d["readings"]["state2"][name]["no_below"], d["readings"]["state2"][name]["yes_above"]
        a = "never" if no is None else ("any bearing" if no == 0.0 else f"{math.floor(no)} N/mm")
        b = "never" if yes is None else f"{math.ceil(yes)} N/mm"
        row = f"| {label} | {a} | {b} |"
        assert row in text, f"SUMMARY state-2 table row drifted from the cache — expected:\n{row}"


# ── HW.43 wire–liner shear lag (102, 2026-10-20) ⟷ SUMMARY §«The Bus Wire in Its Liner». Requirements «k ≥ X» round UP;
# ranges of shares and ratios round OUTWARD; «at least» travel rounds DOWN (in-silico §When Modifying #43).
SHEAR = "mechanical/wire_liner_shear_lag.json"
_SHEAR_ROWS = (("Ti-15Zr", "Ti-15Zr"), ("β-Ti-13Nb-13Zr", "beta-Ti-13Nb-13Zr"), ("Ti-6Al-4V", "Ti-6Al-4V"),
               ("Ti-6Al-7Nb", "Ti-6Al-7Nb"), ("CP-Ti Gr4", "CP-Ti-Gr4"), ("Ta", "Ta"))


def _up2(x):
    return math.ceil(round(x * 100, 9)) / 100


def _down2(x):
    return math.floor(round(x * 100, 9)) / 100


def _shear_row(label, j):
    num = [N if j == k else r"[\d.]+" for k in range(7)]
    cells = [num[0], f"{num[1]} – {num[2]}", num[3], num[4], f"{num[5]} from {num[6]}"]
    return rf"(?m)^\| {label} \| " + r" \| ".join(cells) + r" \|$"


def _pad(d, floor):
    v = [x["fraction_of_shift"] for k, x in d["pad_sway_share1_upper_whisker_high"].items() if k.startswith("window_floor") == floor]
    return v


CHECKS += [
    *[(f"shear {key} col {j} → 102", SUMMARY, _shear_row(label, j), SHEAR, res, 0.0)
      for label, key in _SHEAR_ROWS
      for j, res in enumerate((
          (lambda k: lambda d: d["seam_by_alloy"][k]["seam_k_86"])(key),
          (lambda k: lambda d: _up2(d["seam_by_alloy"][k]["by_share"]["0.25"]["gentle_one_sided"]["seam_k"]))(key),
          (lambda k: lambda d: _up2(d["seam_by_alloy"][k]["by_share"]["1"]["gentle_one_sided"]["seam_k"]))(key),
          (lambda k: lambda d: _up2(d["seam_by_alloy"][k]["by_share"]["0.25"]["seam_k_adverse_sway"]))(key),
          (lambda k: lambda d: _up2(d["seam_by_alloy"][k]["by_share"]["0.5"]["seam_k_adverse_sway"]))(key),
          (lambda k: lambda d: _up2(d["seam_by_alloy"][k]["seam_k_at_wall_ceiling_87"]))(key),
          (lambda k: lambda d: _up2(d["seam_by_alloy"][k]["adverse_share_at_wall_cap_exact"]))(key)))],
    ("shear sleeve ratio → 102", SUMMARY, rf"the sleeve is {N}× stiffer axially", SHEAR,
     lambda d: math.floor(d["sleeve_vs_wire"]["ratio"]), 0.0),
    ("shear stick F at 5 um → 102", SUMMARY, rf"by up to {N} % and [\d.]+ % at a 5 µm shift", SHEAR,
     lambda d: math.ceil(round(-d["controls"]["stick_compliance_at_tightest_grip"][0]["F_rel"] * 1000, 9)) / 10, 0.0),
    ("shear stick pad at 5 um → 102", SUMMARY, rf"by up to [\d.]+ % and {N} % at a 5 µm shift", SHEAR,
     lambda d: math.ceil(round(d["controls"]["stick_compliance_at_tightest_grip"][0]["pad_rel"] * 1000, 9)) / 10, 0.0),
    ("shear stick at 30 um → 102", SUMMARY, rf"by at most\s+{N} % at 30 µm", SHEAR,
     lambda d: math.ceil(round(max(abs(d["controls"]["stick_compliance_at_tightest_grip"][-1]["F_rel"]),
                                   abs(d["controls"]["stick_compliance_at_tightest_grip"][-1]["pad_rel"])) * 1000, 9)) / 10, 0.0),
    ("shear wire stretch low → 102", SUMMARY, rf"at most {N} – [\d.]+ µm at the wall's cap", SHEAR,
     lambda d: math.floor(round(min(v["wire_stretch_at_wall_cap_um_max"] for v in d["seam_by_alloy"].values()) * 10, 9)) / 10, 0.0),
    ("shear wire stretch high → 102", SUMMARY, rf"at most [\d.]+ – {N} µm at the wall's cap", SHEAR,
     lambda d: math.ceil(round(max(v["wire_stretch_at_wall_cap_um_max"] for v in d["seam_by_alloy"].values()) * 10, 9)) / 10, 0.0),
    ("shear hot past larger count → 102", SUMMARY, rf"past the larger margin on {N} of 4 readings", SHEAR,
     lambda d: d["thermal"]["against_l1"]["hot_floor_part_past_larger_lower_margin"], 0.0),
    *[(f"shear flip {name} {end} → 102", SUMMARY, pat, SHEAR,
       (lambda kk, ii: lambda d: _ceil1(d["thermal"]["flip_vs_larger_margin_ppm_K"][kk][ii]))(key, i), 0.0)
      for name, key, pats in (
          ("cold bark", "cold_flange_on_bark", (rf"stays\s+above\s+{N}\s+–\s+[\d.]+\s+ppm/K", rf"stays\s+above\s+[\d.]+\s+–\s+{N}\s+ppm/K")),
          ("cold gap", "cold_zone3_fit_gap_only", (rf"\({N}\s+–\s+[\d.]+\s+if\s+a\s+Zone-3", rf"\([\d.]+\s+–\s+{N}\s+if\s+a\s+Zone-3")),
          ("hot bark", "hot_floor_part_flange_on_bark", (rf"the\s+hot\s+one\s+above\s+{N}\s+–", rf"the\s+hot\s+one\s+above\s+[\d.]+\s+–\s+{N}\s+—")))
      for i, (end, pat) in enumerate((("low", pats[0]), ("high", pats[1])))],
    ("shear free PEEK → 102", SUMMARY, rf"against\s+{N}\s+for\s+free\s+PEEK", SHEAR, lambda d: d["thermal"]["alpha_peek_free_ppm_K"], 0.0),
    ("shear tightest hot → 102", SUMMARY, rf"tightest\s+grip\s+recedes\s+{N}\s+µm,\s+past\s+both", SHEAR,
     lambda d: _floor1(d["thermal"]["tightest_grip_hot_recession_um_bark_span_capsule_edge"]), 0.0),
    ("shear tangent ratio → 102", SUMMARY, rf"and\s+{N}×\s+at\s+the\s+first\s+micron", SHEAR,
     lambda d: _floor1(d["sleeve_vs_wire"]["ratio_at_initial_tangent"]), 0.0),
    ("shear preload low → 102", SUMMARY, rf"adds\s+{N}\s+–\s+[\d.]+\s+N\s+of\s+mean", SHEAR,
     lambda d: math.floor(round(d["seam_by_alloy"]["Ta"]["hot_preload"]["F_N_gentle_nominal_relaxed_mu_low"] * 10, 9)) / 10, 0.0),
    ("shear preload high → 102", SUMMARY, rf"adds\s+[\d.]+\s+–\s+{N}\s+N\s+of\s+mean", SHEAR,
     lambda d: math.ceil(round(d["seam_by_alloy"]["Ta"]["hot_preload"]["F_N_relaxed_liner"] * 10, 9)) / 10, 0.0),
    ("shear preload share of yield → 102", SUMMARY, rf"up to {N} % of the wall's 23 °C yield", SHEAR,
     lambda d: math.ceil(round(d["seam_by_alloy"]["Ta"]["hot_preload"]["wall_stress_share_of_23C_yield"] * 100, 9)), 0.0),
    ("shear preload k → 102", SUMMARY, rf"lifts its requirement to {N} with no sway", SHEAR,
     lambda d: _up2(d["seam_by_alloy"]["Ta"]["by_share"]["0"]["seam_k_adverse_with_preload"]), 0.0),
    ("shear pad grip low → 102", SUMMARY, rf"share-1 bound, {N} – [\d.]+ % of a sway shift", SHEAR,
     lambda d: math.floor(round(min(_pad(d, False)) * 100, 9)), 0.0),
    ("shear pad grip high → 102", SUMMARY, rf"share-1 bound, [\d.]+ – {N} % of a sway shift", SHEAR,
     lambda d: math.ceil(round(max(_pad(d, False)) * 100, 9)), 0.0),
    ("shear pad floor low → 102", SUMMARY, rf"{N} – [\d.]+ % on a part at the window floor", SHEAR,
     lambda d: math.floor(round(min(_pad(d, True)) * 100, 9)), 0.0),
    ("shear pad floor high → 102", SUMMARY, rf"[\d.]+ – {N} % on a part at the window floor", SHEAR,
     lambda d: math.ceil(round(max(_pad(d, True)) * 100, 9)), 0.0),
    ("shear pad ratio low → 102", SUMMARY, rf"{N} – [\d.]+ % of the pin's minimum preload", SHEAR,
     lambda d: math.floor(round(min(x["force_ratio_over_min_preload"] for x in d["pad_sway_share1_upper_whisker_high"].values()) * 1000, 9)) / 10, 0.0),
    ("shear pad ratio high → 102", SUMMARY, rf"[\d.]+ – {N} % of the pin's minimum preload", SHEAR,
     lambda d: math.ceil(round(max(x["force_ratio_over_min_preload"] for x in d["pad_sway_share1_upper_whisker_high"].values()) * 1000, 9)) / 10, 0.0),
    ("shear per-K low → 102", SUMMARY, rf"outgrows\s+the\s+Ti\s+wire\s+by\s+{N}\s+–\s+[\d.]+\s+µm/K", SHEAR,
     lambda d: _down2(min(v["shift_um_per_K"] for v in d["thermal"]["by_reading"].values())), 0.0),
    ("shear per-K high → 102", SUMMARY, rf"outgrows\s+the\s+Ti\s+wire\s+by\s+[\d.]+\s+–\s+{N}\s+µm/K", SHEAR,
     lambda d: _up2(max(v["shift_um_per_K"] for v in d["thermal"]["by_reading"].values())), 0.0),
    ("shear hot floor low → 102", SUMMARY, rf"pad\s+recedes\s+{N}\s+–\s+[\d.]+\s+µm\s+against", SHEAR,
     lambda d: math.floor(round(min(v["hot"]["pad_recedes_um"] for k, v in d["thermal"]["by_reading"].items() if "__window_floor__" in k) * 10, 9)) / 10, 0.0),
    ("shear hot floor high → 102", SUMMARY, rf"pad\s+recedes\s+[\d.]+\s+–\s+{N}\s+µm\s+against", SHEAR,
     lambda d: math.ceil(round(max(v["hot"]["pad_recedes_um"] for k, v in d["thermal"]["by_reading"].items() if "__window_floor__" in k) * 10, 9)) / 10, 0.0),
    ("shear L1 lower small → 102", SUMMARY, rf"against\s+{N}\s+–\s+[\d.]+\s+µm\s+to\s+the\s+lower\s+edge", SHEAR, lambda d: d["thermal"]["l1_margin_to_lower_edge_min_um"], 0.0),
    ("shear L1 lower large → 102", SUMMARY, rf"against\s+[\d.]+\s+–\s+{N}\s+µm\s+to\s+the\s+lower\s+edge", SHEAR,
     lambda d: max(m[0] for m in d["thermal"]["l1_margin_um_90_model_edges"].values()), 0.0),
    ("shear cold min → 102", SUMMARY, rf"protrudes\s+at\s+least\s+{N}\s+µm\s+on\s+every\s+part", SHEAR,
     lambda d: math.floor(round(d["thermal"]["against_l1"]["cold_min_protrusion_um"] * 10, 9)) / 10, 0.0),
    ("shear L1 upper small → 102", SUMMARY, rf"upper\s+edge\s+of\s+{N}\s+–\s+[\d.]+\s+µm", SHEAR, lambda d: d["thermal"]["l1_margin_to_upper_edge_min_um"], 0.0),
    ("shear L1 upper large → 102", SUMMARY, rf"upper\s+edge\s+of\s+[\d.]+\s+–\s+{N}\s+µm", SHEAR,
     lambda d: max(m[1] for m in d["thermal"]["l1_margin_um_90_model_edges"].values()), 0.0),
]


# ── HW.26 bus torsion budget (101, 2026-10-20) ⟷ SUMMARY §«How Far Can the Bus Wire Twist?». Angles and margins are
# «below it, harmless» thresholds — rounded DOWN; torque ranges round OUTWARD; the wind's «at most» rotation rounds UP
# (in-silico §When Modifying #43).
TORSION = "mechanical/bus_torsion_budget.json"
_TORSION_ROWS = (("Ta", "Ta"), ("CP-Ti Gr4", "CP-Ti-Gr4"), ("Ti-6Al-4V", "Ti-6Al-4V"), ("Ti-6Al-7Nb", "Ti-6Al-7Nb"),
                 ("Ti-15Zr", "Ti-15Zr"), ("β-Ti-13Nb-13Zr", "beta-Ti-13Nb-13Zr"))


def _floor1(x):
    return math.floor(round(x * 10, 9)) / 10


def _ceil1(x):
    return math.ceil(round(x * 10, 9)) / 10


def _torsion_row(label, j):
    num = [N if j == k else r"[\d.]+" for k in range(6)]
    cells = [num[0], f"{num[1]} – {num[2]}°", f"{num[3]} – {num[4]}", f"≥ {num[5]}"]
    return rf"(?m)^\| {label} \| " + r" \| ".join(cells) + r" \|$"


def _torsion_margin(d, key):
    return math.floor(d["by_alloy"][key]["theta_y_deg_min"] / math.degrees(d["wind_bark_end"]["rotation_max_rad"]))


CHECKS += [
    *[(f"torsion {key} col {j} → 101", SUMMARY, _torsion_row(label, j), TORSION, res, 0.0)
      for label, key in _TORSION_ROWS
      for j, res in enumerate((
          (lambda k: lambda d: d["by_alloy"][k]["yield_MPa"])(key),
          (lambda k: lambda d: _floor1(d["by_alloy"][k]["theta_y_deg_min"]))(key),
          (lambda k: lambda d: _floor1(d["by_alloy"][k]["theta_y_deg_max"]))(key),
          (lambda k: lambda d: _floor1(d["by_alloy"][k]["wire_yield_torque_Nmm"]["tresca"]))(key),
          (lambda k: lambda d: _ceil1(d["by_alloy"][k]["wire_yield_torque_Nmm"]["von_mises"]))(key),
          (lambda k: lambda d: _torsion_margin(d, k))(key)))],
    ("torsion bare run → 101", SUMMARY, rf"{N} mm of bare wire in the PEEK gap", TORSION, lambda d: d["geometry"]["bare_run_mm"], 0.0),
    ("torsion liner run → 101", SUMMARY, rf"plus {N} mm under the liner", TORSION, lambda d: d["geometry"]["liner_run_mm"], 0.0),
    ("torsion whole run → 101", SUMMARY, rf"under the liner, {N} mm in all", TORSION, lambda d: d["geometry"]["run_mm"], 0.0),
    ("torsion tube yield low → 101", SUMMARY, rf"torsion at {N} – [\d.]+ N·mm, below the wire", TORSION,
     lambda d: _floor1(d["holder"]["liner_tube_first_yield_torque_Nmm"]["tresca"]), 0.0),
    ("torsion tube yield high → 101", SUMMARY, rf"torsion at [\d.]+ – {N} N·mm, below the wire", TORSION,
     lambda d: _ceil1(d["holder"]["liner_tube_first_yield_torque_Nmm"]["von_mises"]), 0.0),
    ("torsion grip low → 101", SUMMARY, rf"carries {N} – [\d.]+ N·mm at the", TORSION,
     lambda d: _floor1(min(d["holder"]["grip_torque_Nmm_by_mu"]["nominal_fit_20C"].values())), 0.0),
    ("torsion grip high → 101", SUMMARY, rf"carries [\d.]+ – {N} N·mm at the", TORSION,
     lambda d: _ceil1(max(d["holder"]["grip_torque_Nmm_by_mu"]["nominal_fit_20C"].values())), 0.0),
    ("torsion grip after creep → 101", SUMMARY, rf"no less than {N} N·mm after creep", TORSION,
     lambda d: _floor1(min(d["holder"]["grip_torque_Nmm_by_mu"]["creep_relaxed_fit"].values())), 0.0),
    ("torsion flip yield → 101", SUMMARY, rf"any wire yield above {N} MPa", TORSION,
     lambda d: math.ceil(d["wire_yield_below_which_the_order_flips_MPa"]), 0.0),
    ("torsion Ta root knockdown → 101", SUMMARY, rf"keeps at least {N} % of the table's", TORSION,
     lambda d: math.ceil(round(d["wire_yield_below_which_the_order_flips_MPa"] / d["by_alloy"]["Ta"]["yield_MPa"] * 100, 9)), 0.0),
    ("torsion wind bark-end max → 101", SUMMARY, rf"most {N} mrad and forces", TORSION,
     lambda d: _ceil2(d["wind_bark_end"]["rotation_max_rad"] * 1e3), 0.0),
    ("torsion wind torque → 101", SUMMARY, rf"forces at most {N} N·mm through the wire", TORSION,
     lambda d: _ceil2(d["wind_bark_end"]["torque_through_wire_max_Nmm"]), 0.0),
]


@pytest.mark.parametrize("label,doc_rel,pattern,cache_rel,resolver,tol",
                         CHECKS, ids=[c[0] for c in CHECKS])
def test_doc_matches_cache(label, doc_rel, pattern, cache_rel, resolver, tol):
    if tol is None:
        # A row whose quantity comes out of a stochastic step cannot be pinned tighter than that
        # step's own reproducibility, and the owning cache MEASURES it. Reading the floor from the
        # cache keeps the tolerance honest if the measurement's precision ever changes; a literal
        # here would go stale silently. Deterministic rows must never use this — they pass a number.
        tol = float(C(cache_rel)["controls"]["patch_sasa_noise_floor_A2"])
        assert tol > 0.0, f"[{label}] the cache's measured noise floor is 0 — it was not measured"
    matches = re.findall(pattern, doc(doc_rel))
    assert matches, (
        f"[{label}] anchor not found in {doc_rel} — pattern {pattern!r} matched nothing. "
        f"Either the doc was reworded (update the guard's anchor) or a minus sign uses an "
        f"un-normalized dash variant.")
    assert len(matches) == 1, (
        f"[{label}] anchor matched {len(matches)} lines in {doc_rel} — ambiguous; tighten the pattern.")
    doc_val = _to_float(matches[0])
    cache_val = float(resolver(C(cache_rel)))
    # The remedy is not the same for every row, so the message must not pretend it is: a `premise` row
    # mirrors CANON into the script (canon moved → re-run), and a NaN resolver refuses a doc sentence the
    # cache no longer supports as phrased — "fix the number" would be the wrong move for both.
    if math.isnan(cache_val):
        remedy = "the resolver refused (NaN): the cache no longer supports the doc's statement as PHRASED — read the resolver."
    elif "premise" in label:
        remedy = "CANON is the source for this row — re-run the owning script so its cache mirrors canon again."
    else:
        remedy = "Cache is SSOT — fix the doc, or (if the cache is wrong) re-run the owning script."
    if math.isinf(doc_val) or math.isinf(cache_val):
        assert doc_val == cache_val, (
            f"[{label}] DOC↔CACHE DRIFT: {doc_rel} says {doc_val} but {cache_rel} says {cache_val} — "
            f"«never» (∞) on one side only. {remedy}")
        return
    assert abs(doc_val - cache_val) <= tol, (
        f"[{label}] DOC↔CACHE DRIFT: {doc_rel} says {doc_val} but "
        f"{cache_rel} says {cache_val} (|Δ|={abs(doc_val - cache_val):.4g} > tol {tol}). {remedy}"
    )


# ── Perimeter: a pin is decorative on every change its INPUT cannot trigger ──

WORKFLOW = ".github/workflows/in_silico_smoke.yml"


def _quoted_list_after(text: str, key_regex: str) -> list[str]:
    """Quoted YAML list items directly under the first line matching `key_regex`.

    Hand-parsed on purpose: the job that runs this file installs pytest and nothing else.
    Comment lines inside the list are skipped; the first non-item line ends it.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.search(key_regex, line):
            items = []
            for nxt in lines[i + 1:]:
                s = nxt.strip()
                if not s or s.startswith("#"):
                    continue
                m = re.match(r"-\s*'([^']+)'", s)
                if not m:
                    break
                items.append(m.group(1))
            return items
    return []


def _doc_targets() -> set[str]:
    """Every doc THIS FILE reads — CHECKS rows plus the doc↔code pins.

    ⛔ Not `{row[1] for row in CHECKS}`: on 2026-09-21 this file grew a pin that reads a doc no
    CHECKS row names (`ebfc_chem_rfq.md`, the order sheet), so a CHECKS-only perimeter would have
    declared full coverage while that doc could drift from the code mirror unwatched. The set is
    taken from every source of doc-reads in the file, and a new source belongs here the same day.
    """
    return ({row[1] for row in CHECKS} | {d[0] for d in _RATIFIED_GENE_DECLARATIONS}
            | {p[1] for p in _PRESS_FIT_PINS} | {p[1] for p in _DATE_PINS})


def test_every_doc_target_triggers_this_guard():
    """Every doc this guard reads must sit inside BOTH path lists of the workflow that runs it.

    This file runs in exactly one place — the `cache_doc_sync` job of `in_silico_smoke.yml` — and
    that job is gated twice: the push trigger's `paths:` and the `changes` job's paths-filter. A
    doc outside them can drift from its cache on a change that touches only that doc, and nothing
    runs. Measured 2026-09-13: the list carried `01_04` beside a comment naming it as the
    non-SUMMARY target, while rows for `01_01` and `02_02` had been added since without it —
    twelve pins that a canon-only edit of either doc could not wake. The carrier sits in this
    file because this is where the next target gets added.
    Ceiling: judges the DOC half only — caches are read from `tools/in_silico/cache`, which the
    lists cover by construction.
    """
    wf = (REPO / WORKFLOW).read_text(encoding="utf-8")
    lists = {
        "push `paths:`": _quoted_list_after(wf, r"^\s+paths:\s*$"),
        "`changes` paths-filter": _quoted_list_after(wf, r"^\s+in_silico:\s*$"),
    }
    for name, patterns in lists.items():
        assert patterns, f"read no {name} list from {WORKFLOW} — the parser is wrong, not the tree"
    missing = [
        f"{target}  ∉  {name}"
        for target in sorted(_doc_targets())
        for name, patterns in lists.items()
        if not any(fnmatch.fnmatchcase(target, p) for p in patterns)
    ]
    assert not missing, (
        f"doc targets outside {WORKFLOW} — their pins cannot fire on a change to the doc alone:\n  "
        + "\n  ".join(missing))


# ── generator ⟷ committed artefact: the class that bit THREE times on 2026-09-24 ──
# A cache-schema change (505a1fac4, 2026-09-21) broke `60`, `61` and `31b` silently — no CI ran
# any of them — and the paper's Table 3 was hand-edited around the break, so it kept printing a
# single ΔG = 0 margin the cache had already turned into a bracket.
TABLES = "docs/protocols/ebfc/in_silico/paper/06_tables.md"


def table_97(cache: dict) -> list[str]:
    """SUMMARY §HW.34's 97 table, row by row, from its cache — the doc's table is this output verbatim."""
    rows = []
    for r in cache["rows"]:
        cells = []
        for st in ("mouth", "exit"):
            w = r[st]["worst_face"]
            kx = min((x["k_crossover"] for x in r[st]["faces"].values() if x["k_crossover"] is not None), default=None)
            # k_x is a threshold («every k below it»): rounded DOWN, as the prose quotes it (in-silico §When Modifying #43)
            cells.append(f"{r[st]['faces'][w]['sf_drawn_wire']:.1f} ({w}) · " + (f"{math.floor(kx * 100) / 100:.2f}" if kx is not None else "—"))
        end = min(v["sf_nominal_only"] for v in r["liner_end"].values() if isinstance(v, dict))
        rows.append(f"| {r['base']} | {r['offset_um']} | {r['root']['sf_at_k']['1']:.1f} · {r['root']['sf_at_k']['0.388']:.1f} | "
                    f"{cells[0]} | {cells[1]} | {end:.1f} |")
    return rows


def test_97_table_is_its_cache():
    """Every row of the 97 table in SUMMARY §HW.34 — SF, face label, lowest k_x or «—» — is its cache's row verbatim."""
    text = doc(SUMMARY)
    missing = [row for row in table_97(C("mechanical/wire_under_liner_edges.json")) if row not in text]
    assert not missing, f"the 97 table drifted from its cache — regenerate it from table_97(): {missing[:2]}"


def test_paper_tables_match_their_generator():
    """`06_tables.md` must be exactly what `61` renders from the committed caches.

    Run in a subprocess via `runpy.run_path`, which compiles the script from SOURCE — no
    `__pycache__` for the target (the stale-bytecode trap `_mirror_in_code` documents).
    CAN catch: a generator that no longer runs on the committed caches · a hand edit of the
    table · a cache change after which nobody regenerated it.
    CANNOT catch: `60`'s figures (PNG bytes are not portable across matplotlib builds) — the
    same class, left to in-silico §When Modifying #19.
    """
    import subprocess
    import sys
    code = "import runpy, sys; sys.stdout.write(runpy.run_path(sys.argv[1])['build']())"
    run = subprocess.run(
        [sys.executable, "-c", code, str(REPO / "tools/in_silico/scripts/61_paper_tables.py")],
        capture_output=True, text=True, check=False)
    assert run.returncode == 0, f"61 no longer renders on the committed caches:\n{run.stderr[-2000:]}"
    assert run.stdout == (REPO / TABLES).read_text(encoding="utf-8"), (
        f"{TABLES} differs from what 61 renders — re-run 61, never hand-edit the table")


SI = "docs/protocols/ebfc/in_silico/paper/10_supporting_information.md"


def test_paper_si_matches_its_generator():
    """`10_supporting_information.md` must be exactly what `72` renders from the committed tree.

    Same discipline as the tables pin above (`runpy.run_path`, compiled from source). The manifest
    is a sha256 row per committed environment file, script, cache, data set, coordinate file and
    figure, so any of them changing without a re-run of 72 reds here with the stale row visible.
    CAN catch: a hand edit of the manifest · a cache / script / figure / coordinate file changed
    after which nobody regenerated it · a generator that no longer runs (git or a moved path).
    CANNOT catch: whether the SI is what the journal wants in form — that is the founder's call at
    submission; and it judges the WORKING TREE's bytes, so a dirty checkout reds until regenerated.
    """
    import subprocess
    import sys
    code = "import runpy, sys; sys.stdout.write(runpy.run_path(sys.argv[1])['build']())"
    run = subprocess.run(
        [sys.executable, "-c", code,
         str(REPO / "tools/in_silico/scripts/72_paper_supporting_information.py")],
        capture_output=True, text=True, check=False)
    assert run.returncode == 0, f"72 no longer renders on the committed tree:\n{run.stderr[-2000:]}"
    assert run.stdout == (REPO / SI).read_text(encoding="utf-8"), (
        f"{SI} differs from what 72 renders — re-run 72, never hand-edit the manifest")


def test_paper_title_is_stattya_1s_by_address():
    """72 reads the title from the block under «#### Стаття 1:» of the plan — the manuscript print
    (`scripts/disclosure_pdf.rb`, `title_from`, its selftest) reads it by the same rule.

    CAN catch: a reader that takes the FIRST «Назва (EN)» of the file (a position, not an address — every
    paper of the plan carries one) · an anchor that confuses Стаття 1 with Стаття 13 · a block that runs
    past its own heading into the next paper's title.
    CANNOT catch: whether the Ruby reader still agrees — its selftest holds the same three cases.
    """
    import runpy
    title_from = runpy.run_path(str(REPO / "tools/in_silico/scripts/72_paper_supporting_information.py"))["title_from"]
    plan = ('#### Стаття 0: x\n**Назва (EN):** _"Wrong"_\n#### Стаття 13: z\n**Назва (EN):** _"Nor"_\n'
            '#### Стаття 1: y\ntext\n**Назва (EN):** _"Right"_\n#### Стаття 2: w\n**Назва (EN):** _"Next"_\n')
    assert title_from(plan) == "Right"
    assert title_from(plan.replace('**Назва (EN):** _"Right"_\n', "")) is None


def test_cathode_rct_reads_the_current_bracket():
    """`31b`'s k_DET scenarios must be the CURRENT corners of `25`'s bracket × turnover.

    CAN catch: a `31b` cache left behind after `25` moved (it read a ΔG = 0 default for three
    days after the bracket landed) · a scenario dropped or added on one side only.
    CANNOT catch: whether `31b`'s Laviron grid is the right physics — a coherence pin only.
    """
    ket, rct = C("dft/cathode_ket_lambda.json"), C("kinetics/cathode_det_rct.json")
    sc, t = ket["scenarios"], ket["turnover_s"]
    expected = sorted(sc[k][f] for k in ("literature λ", "computed λ (B3LYP)") for f in (
        "margin_vs_turnover_adverse", "margin_vs_turnover_at_dG0", "margin_vs_turnover_favourable"))
    got = sorted(k / t for k in rct["k_scenarios_s"].values())
    assert len(got) == len(expected) and all(
        math.isclose(a, b, rel_tol=1e-9) for a, b in zip(got, expected, strict=True)), (
        f"31b k_DET/turnover {got} ≠ the 25 bracket {expected} — re-run 31b")


# ── reproduction record ⟷ the paper's reproducibility claim (§2.7, measured 2026-09-30 on the 4a,5-dihydro donor and
#    re-made 2026-10-16 on the 1,5-dihydro one — the older record stays in the tree as the witness of that state) ──
METHODS = "docs/protocols/ebfc/in_silico/paper/02_methods.md"
REPRO = "reproduction/lock_rerun_2026-10-16.json"


def _flat(x, p=""):
    if isinstance(x, dict):
        return {k2: v2 for k, v in x.items() for k2, v2 in _flat(v, f"{p}.{k}" if p else k).items()}
    if isinstance(x, list):
        return {k2: v2 for i, v in enumerate(x) for k2, v2 in _flat(v, f"{p}[{i}]").items()}
    return {p: x}


def _assert_record_describes_the_tree(record: str) -> None:
    """A lock record must describe the caches the paper quotes TODAY: a re-run of a cache that leaves its old
    record behind stays green on every bound alone (the 2026-09-30 record still holds the 4a,5-dihydro HOMO)."""
    for cache, rec in C(record)["files"].items():
        now = _flat(C(cache))
        stale = [k for k, v in rec["per_field"].items() if now.get(k) != v["committed"]]
        assert not stale, f"{record} describes a {cache} the tree no longer holds ({stale[:3]}) — re-run the lock record"


def test_paper_reproduction_bound_is_backed_by_the_record():
    """§2.7 states a bound («to within N × 10⁻¹⁰ Ha in total electronic energy») for the re-run
    under the conda-lock; the field-by-field record it cites must actually sit under that bound.

    CAN catch: a re-measured record whose deltas grew past the sentence (the sentence is stale) ·
    the record renamed or dropped while §2.7 still cites it · a bound quoted a decade above the
    measurement (true, but useless to a reviewer).
    CANNOT catch: whether scripts 20 and 32 are representative of the heavier caches — the record
    itself names which were NOT re-run (the heavier pair has its own record and its own check below).
    """
    text = doc(METHODS)
    found = re.findall(r"to within ([\d.]+) × 10⁻¹⁰ Ha in total electronic energy", text)
    assert len(found) == 1, f"§2.7 bound sentence found {len(found)}× in {METHODS} — expected once"
    bound = float(found[0]) * 1e-10
    assert f"`cache/{REPRO}`" in text, f"§2.7 no longer names the record cache/{REPRO}"
    measured = max(f["max_abs_delta_total_energy_Ha"] for f in C(REPRO)["files"].values())
    # The record must describe the caches the paper quotes TODAY: a re-run that leaves an old record behind stays
    # green on the bound alone (the 2026-09-30 record still holds the 4a,5-dihydro HOMO).
    _assert_record_describes_the_tree(REPRO)
    assert measured <= bound, (
        f"§2.7 says ≤ {bound:.2g} Ha but {REPRO} measured {measured:.3g} Ha — re-state §2.7 "
        f"(and PIPELINE_STATUS / the env header) from the record, never the record from the prose")
    assert bound < 10 * measured, (
        f"§2.7's bound {bound:.2g} Ha sits a decade above the measured {measured:.3g} Ha — "
        f"tighten the sentence to one significant figure of the record")


# ── the HEAVIER pair's record (2026-10-01): the two caches SPLIT, and §2.7 must say so ──
REPRO_HEAVY = "reproduction/lock_rerun_2026-10-01.json"
REPRO_CAUSE = "reproduction/pcm_ecp_radius_attribution.json"   # script 75 — the cause of the split, below


def test_paper_heavy_lock_rerun_is_stated_as_the_record_measured_it():
    """§2.7 also carries the heavier re-run (21f b3lyp · 24b). The record there is NOT a single
    bound: one cache reproduces at printed precision and the other moves a REPORTED number, so the
    prose must name the moved number itself — a bound alone would read as «same as the flavin case».

    CAN catch: the record renamed or dropped while §2.7 still cites it · §2.7 quoting a ΔE_red pair
    that is not the one measured (either end) · a later re-measurement that changes either end while
    the sentence stays · the dE_red field vanishing from the compared set.
    CANNOT catch: whether the ωB97X tier and 21e (never re-run) would behave like either of these —
    §2.7 and the record both say they were not run.
    """
    text = doc(METHODS)
    assert f"`cache/{REPRO_HEAVY}`" in text, f"§2.7 no longer names the record cache/{REPRO_HEAVY}"
    rec = C(REPRO_HEAVY)["files"]
    os_fields = rec["dft/os_complex.json"]["per_field"]["dE_red_III_to_II_eV"]
    for end in ("committed", "lock_rerun"):
        assert f"{os_fields[end]:.4f}".replace("-", "−") in text, (
            f"§2.7 does not carry the {end} ΔE_red {os_fields[end]} that {REPRO_HEAVY} measured — "
            f"re-state the sentence from the record, never the record from the prose")
    fodft = rec["dft/fodft_coupling.json"]
    assert fodft["max_abs_delta_reported_outputs"] == 0.0, (
        f"{REPRO_HEAVY} now shows 24b's reported fields moving by "
        f"{fodft['max_abs_delta_reported_outputs']:.3g} — §2.7 says they reproduce exactly")
    # The split has a MEASURED cause (2026-10-01, script 75) — the sentence it replaced called it numerics.
    for token in ("PySCF 2.13.0", "pull request 3159", f"`cache/{REPRO_CAUSE}`"):
        assert token in text, (
            f"§2.7 no longer names {token!r} — the measured cause of the 21f split; without it the gap reads "
            f"as unexplained SCF numerics, the claim the attribution record refuted")
    _assert_record_describes_the_tree(REPRO_HEAVY)


# ── the CAUSE of that split (2026-10-01, script 75): PySCF 2.13.0 fixed the PCM radius of ECP atoms ──
def test_paper_lock_gap_attribution_is_stated_as_the_record_measured_it():
    """§2.7 attributes 21f's lock gap to the PySCF 2.13.0 fix of the PCM switching radius of ECP atoms and
    prints how closely the EMULATED fix lands on the lock values. Those bounds must be the record's.

    CAN catch: a re-measured record whose device, closed-shell or open-shell agreement grew past the bound
    §2.7 prints, or a bound a decade looser than the record · a bound sentence duplicated or dropped · the
    emulated ΔE_red no longer equal to the lock value §2.7 quotes · the open shell's «20 meV away» drifting
    from the record · the open-shell shift falling back within the ceiling the script reads as a cavity
    change (then «not attributed» is stale — the record's own verdict flips with it).
    CANNOT catch: whether the members of the class that were never run behave like the device couple —
    §2.7 and the record both say they are not measured; nor what the open-shell solutions ARE (the record
    carries energies, no ⟨S²⟩ or stability analysis) — and a re-run of 75 is a NEW sample of that open shell.
    """
    text = doc(METHODS)
    rec = C(REPRO_CAUSE)
    dev, aqua = rec["device_21f"], rec["aqua_os_h2o6"]["differences_Ha"]
    for anchor, measured, unit, scale in (
            (r"device\s+couple\s+to", max(abs(s["with_fix_minus_lock_Ha"]) for s in dev["states"].values()),
             "10⁻¹⁰", 1e-10),
            (r"\[Os\(H₂O\)₆\]²⁺\s+to", abs(aqua["os2"]["B_minus_C"]), "10⁻¹²", 1e-12),
            (r"\[Os\(H₂O\)₆\]³⁺\s+the\s+emulated\s+and\s+lock\s+runs\s+meet\s+as\s+well\s+\(",
             abs(aqua["os3"]["B_minus_C"]), "10⁻¹⁰", 1e-10)):
        found = re.findall(rf"{anchor}\s*([\d.]+)\s+×\s+{unit}\s+Ha", text)
        assert len(found) == 1, f"§2.7 attribution bound «{anchor}» found {len(found)}× — expected once"
        bound = float(found[0]) * scale
        assert measured <= bound < 10 * measured, (
            f"§2.7 prints {bound:.2g} Ha after «{anchor}», {REPRO_CAUSE} measured {measured:.3g} Ha — "
            f"re-state §2.7 from the record, never the record from the prose")
    dE = dev["dE_red_III_to_II_eV"]
    assert abs(dE["recorded_with_fix"] - dE["lock_rerun"]) < 5e-5, (
        f"the emulated fix gives ΔE_red {dE['recorded_with_fix']} against the lock's {dE['lock_rerun']} — "
        f"§2.7's attribution of the 21f gap no longer holds")
    osr = rec["open_shell_reading"]
    away = re.findall(r"recorded\s+run\s+lies\s+(\d+)\s+meV\s+away", text)
    assert len(away) == 1 and int(away[0]) == round(osr["A_minus_C_meV"]), (
        f"§2.7 puts the recorded open-shell run {away} meV from the lock, the record "
        f"{osr['A_minus_C_meV']:.1f} meV")
    assert osr["B_meets_C"] and not osr["attributed_to_the_fix"], (
        f"{REPRO_CAUSE} now reads the open shell as B_meets_C={osr['B_meets_C']}, attributed="
        f"{osr['attributed_to_the_fix']} — §2.7 says the emulated and lock runs meet and the state is NOT "
        f"attributed; rewrite that clause from the record")


# ── C-min (2026-10-02, script 76): the computed sensitivity of §2.3 to the chelate the builder leaves open ──
CMIN = "reproduction/os_chelate_sensitivity.json"


def test_chelate_sensitivity_is_stated_as_the_record_measured_it():
    """§2.3 may print a sensitivity number only COMPUTED (verdict B′, the §2.3 line of 09_references), and
    SUMMARY is that number's results home — both must carry what `76` recorded, and the record must stand on
    the base it names.

    CAN catch: §2.3 or SUMMARY quoting a shift (or a per-state pair) the record does not hold · a record whose
    base is not the lock re-run it cites, or that ran under another PySCF than that base · a closed geometry
    off the builder's targets · the full-C trigger flag disagreeing with the shift.
    CANNOT catch: the members of the class C-min did not run (aqua · bis-Im · the series · ωB97X) — §2.3 says
    they were not recomputed; nor whether the closed chelate is a better model than the open one.
    """
    rec = C(CMIN)
    sens = rec["sensitivity"]
    fmt = lambda x: f"{x:.3f}".replace("-", "−")  # noqa: E731
    methods, summary = doc(METHODS), doc(SUMMARY)
    assert f"`cache/{CMIN}`" in methods and f"`cache/{CMIN}`" in summary, "§2.3 / SUMMARY no longer cite the C-min record"
    for token in (f"vertical ΔE_red(III→II) by {fmt(sens['dE_red_shift_eV'])} eV",
                  f"Os(II) state by {fmt(abs(sens['os2_shift_eV']))} eV",
                  f"Os(III) state by {fmt(abs(sens['os3_shift_eV']))} eV"):
        assert token in methods, f"§2.3 does not carry {token!r} from {CMIN} — re-state the sentence from the record"
    assert (f"**{fmt(sens['dE_red_shift_eV'])} eV** (Os(II) {fmt(sens['os2_shift_eV'])} · "
            f"Os(III) {fmt(sens['os3_shift_eV'])} eV)") in summary, f"SUMMARY §Anode does not carry {CMIN}'s numbers"
    lock = C(REPRO_HEAVY)
    pf = lock["files"]["dft/os_complex.json"]["per_field"]
    e2, e3 = pf["os2_plus.E_total_Ha"]["lock_rerun"], pf["os3_plus.E_total_Ha"]["lock_rerun"]
    assert rec["base"]["source"].endswith(REPRO_HEAVY), f"C-min base is {rec['base']['source']}, not the lock re-run"
    assert (rec["base"]["os2_E_total_Ha"], rec["base"]["os3_E_total_Ha"]) == (e2, e3), "C-min base ≠ the lock re-run's energies"
    assert rec["environment"]["pyscf"] == lock["lock_env"]["versions"]["pyscf"], (
        f"C-min ran under PySCF {rec['environment']['pyscf']}, its base under {lock['lock_env']['versions']['pyscf']}")
    h2ev = (rec["base"]["dE_red_III_to_II_eV"]) / (e2 - e3)
    closed = rec["closed"]
    assert math.isclose(sens["dE_red_shift_eV"], closed["dE_red_III_to_II_eV"] - rec["base"]["dE_red_III_to_II_eV"],
                        abs_tol=1e-12), "C-min shift is not closed − base"
    assert math.isclose(sens["os2_shift_eV"], (closed["os2_plus"]["E_total_Ha"] - e2) * h2ev, abs_tol=1e-9)
    assert math.isclose(sens["os3_shift_eV"], (closed["os3_plus"]["E_total_Ha"] - e3) * h2ev, abs_tol=1e-9)
    assert closed["os2_plus"]["converged"] and closed["os3_plus"]["converged"], "a C-min SCF did not converge"
    tg, geo = rec["targets"], rec["geometry"]["closed"]
    assert all(abs(d - tg["os_n_bpy_A"]) <= 0.002 for d in geo["os_n_bpy_A"]), geo["os_n_bpy_A"]
    assert all(abs(b - tg["bite_deg"]) <= 0.1 for b in geo["bite_deg"]), geo["bite_deg"]
    assert sens["full_C_triggered"] == (abs(sens["dE_red_shift_eV"]) >= sens["full_C_trigger_eV"]), (
        "the full-C flag disagrees with the shift it was computed from")


def test_frost_worst_regime_label_matches_cache():
    """01_04 §3.1 names the sky × sun end of 79's worst tied day in words; the number is pinned above, the words here.
    CAN catch: a rerun that moves the worst day to another end while the canon keeps the old label.
    CANNOT catch: a label that is right but describes the cell's bark side or wind — the canon quotes only the regime.
    """
    d = json.loads((CACHE / FLANGE_FROST).read_text(encoding="utf-8"))
    words = {"clear_no_sun": "ясне небо без сонця", "overcast_no_sun": "хмарність без сонця",
             "clear_diffuse_sun": "ясне небо з розсіяним сонцем", "overcast_diffuse_sun": "хмарність із розсіяним сонцем"}
    text = (REPO / CODIT).read_text(encoding="utf-8")
    assert f"**+{d['verdict']['tied_max_K']:.1f} K** ({words[d['verdict']['tied_max_regime']]})" in text


def test_coating_cost_in_01_04_matches_99():
    """01_04 §4.3 «Surface-DFT колаборація» ⊕ (HW.40) quotes 99's cache: the composite's basis functions at two tiers and
    its ratio to the anchor, the def2-TZVP anchor, the fitted exponent, both readings (A: 21e tier, B: def2-TZVP) of one SCF
    and a relaxation for Zn-HAp/TiO2 and PEDOT:PSS/TiO2, the RKS Hessian ratio, and the three env statements (two-sided).
    CAN catch a re-run of 99 or of its source caches that leaves the canon behind. CANNOT catch whether the clusters are the
    right models."""
    d = json.loads((CACHE / "dft/coating_cluster_cost.json").read_text(encoding="utf-8"))
    z, pe = d["by_model"]["Zn_HAp_on_TiO2_16"], d["by_model"]["PEDOT_PSS_on_TiO2_16"]
    za, zt = z["estimate"]["21e_b3lyp_631gd"], z["estimate"]["21f_def2tzvp"]
    pa, pt = pe["estimate"]["21e_b3lyp_631gd"], pe["estimate"]["21f_def2tzvp"]
    text = " ".join((REPO / "docs/01_04_CODIT_and_Xylemointegration.md").read_text(encoding="utf-8").split())

    def rng(e, key, fmt):
        return f"**{e[key]['low']:{fmt}}–{e[key]['high']:{fmt}}**"
    for frag in (f"**{z['nao']['21e_b3lyp_631gd']}** базисні функції", f"у **{za['ratio_to_anchor']}** раза",
                 f"— **{z['nao']['21f_def2tzvp']}** проти **{d['anchor']['21f_def2tzvp']['nao']}**",
                 f"від підгонки **{d['fit_exponent']['21e_b3lyp_631gd']}** до 3",
                 f"один SCF Zn-HAp/TiO₂ — {rng(za, 'one_scf_h', '.1f')} год, релаксація — {rng(za, 'relaxation_days', '.1f')} діб",
                 f"{rng(pa, 'one_scf_h', '.1f')} год і {rng(pa, 'relaxation_days', '.0f')} діб",
                 f"Zn-HAp/TiO₂ — {rng(zt, 'one_scf_h', '.0f')} год на SCF і {rng(zt, 'relaxation_days', '.0f')} діб на релаксацію",
                 f"PEDOT:PSS — {rng(pt, 'one_scf_h', '.0f')} год і {rng(pt, 'relaxation_days', '.0f')} діб",
                 f"гесіан (≈ **{d['rks_hessian_over_scf_96']:.0f}** SCF для RKS)"):
        assert frag in text, f"01_04 §4.3 ⊕ 99: expected {frag!r}"
    env = d["env"]
    assert ("D3/D4 у середовищі немає" in text) == (not env["dftd3"] and not env["dftd4"])
    assert ("VV10 у PySCF нативний" in text) == env["vv10_native"]
    assert ("аналітичного UKS-гесіана для функціонала з VV10 у PySCF немає" in text) == (not env["uks_nlc_hessian"])


def test_field_strain_sheet_matches_98():
    """docs/protocols/anchor/field_strain_sensor_sheet.md (HW.43) quotes 98's cache: the ratified set's current and
    battery days and the pair's (§3), every row of the uncapped start-month table (hours/day at Beaufort 5, years
    without, the replay's median and p75, trips at both), the capped plan (share reached, hours by the cap, seasons with
    none, trips), §0's counts; SUMMARY §HW.43 ⊕ 98; and the numbers of BOTH ratified ⚖️ 2026-10-18 in 01_02 §2.2 and the
    ⊕ between them — the verdicts were given on them. CAN catch a re-run of 98 (new ERA5 window, power figure, target,
    quantile rule, cap) that leaves any of the three behind. CANNOT catch whether the months chosen for the table are the
    right ones, nor a ratified number that the cache no longer carries under the same key."""
    d = json.loads((CACHE / "mechanical/field_strain_campaign.json").read_text(encoding="utf-8"))
    bm, bd, cap, third = d["by_month"], d["battery_days"], d["capped_by_start_month"], d["set_with_third_tss"]
    dec = cap["12"]
    text = (REPO / "docs/protocols/anchor/field_strain_sensor_sheet.md").read_text(encoding="utf-8")
    for frag in (f"**{third['current_A']:.4f} A**", f"**{third['battery_days']['100_Ah_ours']:.1f}** доби за повної ємності",
                 f"— {d['power']['current_A']:.4f} A:", f"**{bd['60_Ah_as_in_the_papers']:.1f}** доби",
                 f"**{bd['100_Ah_ours']:.1f}** доби",
                 f"у **{bm['01']['years_without_beaufort_5']} із 30** січнів",
                 f"медіану **{bm['12']['replay_days']['p50']:.0f}** доби, p75 — **{bm['12']['replay_days']['p75']:.0f}**, "
                 f"p90 — **{bm['12']['replay_days']['p90']:.0f}**",
                 f"набирають **{dec['share_reached_by_cap'] * 100:.0f} %** сезонів",
                 f"**{dec['seasons_not_reached']} із {dec['n_seasons']}** сезонів не набирають її й до 1 травня",
                 f"мету в **{dec['share_reached_by_cap'] * 100:.0f} %** сезонів (березневий — лише в "
                 f"**{cap['03']['share_reached_by_cap'] * 100:.0f} %**)",
                 f"медіанно набирається **{dec['beaufort_5_hours_by_cap_median']:.0f}** години Бофорт-5, а у "
                 f"**{dec['seasons_with_zero_by_cap']}** із {dec['n_seasons']} сезонів — жодної",
                 f"**{third['december_capped_trips_median']['100_Ah_ours']}** за медіани і щонайбільше "
                 f"**{third['december_capped_trips_max']['100_Ah_ours']}**",
                 f"у січні в середньому {bm['01']['beaufort_5_hours_per_storm_mean']:.1f} год",
                 f"≈ {round(d['battery_Ah_for_90_days'], -1):.0f} А·год"):
        assert frag in text, f"field sheet: expected {frag!r}"
    names = {"12": "грудень", "01": "січень", "02": "лютий", "03": "березень", "06": "червень"}
    for m, name in names.items():
        r = bm[m]
        t50, t75 = r["trips_at_median"], r["trips_at_p75"]
        row = (f"| {name} | {r['hours_per_day']['beaufort_5']:.2f} | {r['years_without_beaufort_5']} | "
               f"{r['replay_days']['p50']:.0f} · {r['replay_days']['p75']:.0f} | "
               f"{t50['60_Ah_as_in_the_papers']} / {t50['100_Ah_ours']} · {t75['60_Ah_as_in_the_papers']} / {t75['100_Ah_ours']} |")
        assert row in text, f"field sheet §3: expected the row {row!r}"
    summary = " ".join((REPO / SUMMARY).read_text(encoding="utf-8").split())
    for frag in (f"**{bm['01']['years_without_beaufort_5']}** of 30 Januaries",
                 f"a median **{bm['12']['replay_days']['p50']:.0f}** days from 1 December (p75 **{bm['12']['replay_days']['p75']:.0f}**)",
                 f"(p90 **{bm['12']['replay_days']['p90']:.0f}** days from 1 December)",
                 f"**{dec['share_reached_by_cap'] * 100:.0f}** % of seasons reach the target by then",
                 f"at most **{third['december_capped_trips_max']['100_Ah_ours']}** trips under the cap",
                 f"**{bm['12']['trips_at_median']['100_Ah_ours']}** trips on 100 Ah at the median",
                 f"({d['power']['current_A']:.3f} A, the receiver"):
        assert frag in summary, f"SUMMARY §HW.43 ⊕ 98: expected {frag!r}"
    canon = " ".join((REPO / "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md").read_text(encoding="utf-8").split())
    for frag in (  # the first verdict, as ratified
                 f"медіана **{bm['12']['replay_days']['p50']:.0f}** доби від 1 грудня, p75 — **{bm['12']['replay_days']['p75']:.0f}**",
                 f"**{bm['12']['trips_at_median']['100_Ah_ours']}** поїздок за медіанної зими і "
                 f"**{bm['12']['trips_at_p75']['100_Ah_ours']}** за p75",
                 f"**{bm['01']['years_without_beaufort_5']}** із 30 січнів",
                 f"≈ **{round(d['battery_Ah_for_90_days'], -1):.0f}** А·год",
                 # its ⊕ (the two errors)
                 f"**{dec['seasons_not_reached']}** із {dec['n_seasons']} сезонів",
                 f"p90 — **{bm['12']['replay_days']['p90']:.0f}** доби", f"**{bd['100_Ah_ours']:.1f}** доби акумулятора",
                 # the second verdict, as ratified
                 f"травень **{d['beaufort_5_rate_after_april']['05']}**, червень **{d['beaufort_5_rate_after_april']['06']}** год на добу",
                 f"набирає мету в **{dec['share_reached_by_cap'] * 100:.0f} %** сезонів, березневий — лише в "
                 f"**{cap['03']['share_reached_by_cap'] * 100:.0f} %**",
                 f"(**{bd['100_Ah_ours']:.1f}** доби на 100 А·год для пари, **{third['battery_days']['100_Ah_ours']:.1f}** — з третім TSS",
                 f"медіанно **{dec['beaufort_5_hours_by_cap_median']:.0f}** години Бофорт-5",
                 f"**{dec['trips_median']['100_Ah_ours']}** за медіани і щонайбільше **{dec['trips_max']['100_Ah_ours']}**",
                 f"третім TSS (**{third['current_A']}** A) — щонайбільше **{third['december_capped_trips_max']['100_Ah_ours']}**",
                 f"(у **{dec['seasons_with_zero_by_cap']}** із {dec['n_seasons']} сезонів — порожнім)"):
        assert frag in canon, f"01_02 §2.2 — the two ⚖️ 2026-10-18 and the ⊕ between them: expected {frag!r}"


def test_field_battery_type_matches_98():
    """The campaign battery (98 §5, HW.43, 2026-10-19): the sheet's §3 (table, readings, swap calendars, the ratified
    paragraph), SUMMARY §HW.43 ⊕, the ⊕ on the second ⚖️, the third ⚖️ with its post-«так» ⊕ and the fourth ⚖️ (the
    freezer measurement, its full form moved there from the 00_07 HW.43 leg on its ratification) in 01_02 §2.2 quote 98's
    `battery_type` — masses, prices, below-floor counts per source, the AGM
    freezing at the 1 December anchor (what the ratified text quotes) and over the first-swap day (its ⊕), humidity, the
    battery-day ranges per chemistry, the trips at the derated resource (ratified text) and under the ratified rule (⊕),
    and the swap calendars. CAN catch a re-run leaving any home behind and a range quoted from the other chemistry.
    CANNOT catch whether the makers' sheets are transcribed right, nor what each reading's «basis» says."""
    d = json.loads((CACHE / "mechanical/field_strain_campaign.json").read_text(encoding="utf-8"))
    bt, third = d["battery_type"], d["set_with_third_tss"]
    agm, lfp = bt["types"]["agm_lead_acid"], bt["types"]["lifepo4"]
    n = bt["seasons"]
    by = agm["freezing"]["by_swap_days"]
    f14 = by[str(bt["swap_days_ratified_ours"])]
    ex_a, ex_l = agm["examples"], lfp["examples"]
    lp_a, lp_l = ex_a["LogicPower LPM-MG 12V 100 Ah"], ex_l["LogicPower LP LiFePO4 12.8V 100 Ah (BMS 100A/50A) Smart BT"]
    fl_lp, fl_ll = agm["discharge_floors"]["LogicPower LPM-MG"], agm["discharge_floors"]["Lifeline (operating range)"]
    fl_l = next(iter(lfp["discharge_floors"].values()))
    ra, rl = agm["readings_range"], lfp["readings_range"]
    c14, rh, rules = bt["coldest_fortnight_mean_C"], bt["air_rh_above_spec"], bt["swap_rules_lifepo4"]
    need = {k: math.ceil(v * 100) for k, v in bt["capacity_fraction_needed_for_swap_days"].items()}   # rounded up
    ft = bt["freezer_test"]
    be = ft["band_ends_under_the_ratified_rule"]
    lo, hi = sorted(be, key=float)
    cm = bt["coldest_mean_air_over_days_C"]
    soc_floor = {str(a): b for a, b in lfp["cold_readings"]["eve_cell_0p5c"]["discharge_soc_floor_pct"]}

    def r2(pair, fmt=".1f"):
        return f"{pair[0]:{fmt}}–{pair[1]:{fmt}}" if pair[0] != pair[1] else f"{pair[0]:{fmt}}"

    def uah(x):
        return f"{x:,}".replace(",", " ")

    def neg(x):
        return f"{x:.1f}".replace("-", "−")

    def c(f, r):
        return f["seasons_with_freeze_hours"][r]

    def ph(f, r):
        return r2(f["seasons_with_freeze_hours_over_first_swap_day"][r], "d")

    def risk(rule):
        return rules[rule]["at_risk_by_lifepo4_reading"]

    others = [k for k in sorted(by, key=int) if k != str(bt["swap_days_ratified_ours"])]
    sheet = (REPO / "docs/protocols/anchor/field_strain_sensor_sheet.md").read_text(encoding="utf-8")
    for frag in (f"≈ **{bt['rate_of_100_Ah']}** від 100 А·год", f"кампанію кожного з **{n}** сезонів",
                 f"**{lp_a['mass_kg']:.2f}** кг (LogicPower LPM-MG 12V 100 Ah)",
                 f"**{ex_a['Rolls R12-100AGM']['mass_kg']:.0f}** кг (Rolls R12-100AGM)",
                 f"**{lp_l['mass_kg']:.2f}** кг (LogicPower LP LiFePO4",
                 f"**{ex_l['Victron LiFePO4 12.8/100 Smart']['mass_kg']:.0f}** кг (Victron LiFePO4 Smart",
                 f"| **{uah(lp_a['price_uah'])}** ₴ — на картці «немає в наявності» | **{uah(lp_l['price_uah'])}** ₴ — у наявності |",
                 f"| **{fl_lp['seasons_with_hours_below']['air_24h_mean']}** · **{fl_lp['seasons_with_hours_below']['air_hourly']}** "
                 f"за межею LogicPower; **{fl_ll['seasons_with_hours_below']['air_24h_mean']}** · "
                 f"**{fl_ll['seasons_with_hours_below']['air_hourly']}** за межею Lifeline | "
                 f"**{fl_l['seasons_with_hours_below']['air_24h_mean']}** · **{fl_l['seasons_with_hours_below']['air_hourly']}** |",
                 f"лишається **{f14['soc_at_swap_pct']:.1f}** %, точка — **{neg(f14['freezing_point_at_swap_C'])}** °C",
                 f"в **{ph(f14, 'air_24h_mean')}** із {n} кампаній за добовим середнім (**{ph(f14, 'air_hourly')}** погодинно)",
                 f"за обміну раз на {' · '.join(others)} діб — у **{' · '.join(ph(by[k], 'air_24h_mean') for k in others)}** (добове)",
                 f"повітря ERA5 вище {rh['spec_pct']} % — **{rh['share_of_campaign_hours'] * 100:.0f} %** годин кампанії "
                 f"(**{rh['share_by_season_min_max'][0] * 100:.0f}–{rh['share_by_season_min_max'][1] * 100:.0f} %** по сезонах)",
                 f"годину Бофорт-5 за {n} кампаній — **{neg(bt['coldest_air_in_a_beaufort_5_hour_C'])}** °C (за добовим "
                 f"середнім — **{neg(bt['coldest_24h_mean_air_in_a_beaufort_5_hour_C'])}** °C)",
                 f"потребує щонайменше **{need['14']}** % номінальної ємності, раз на 10 — **{need['10']}** %",
                 f"нижче **{soc_floor['-20']}** % заряду при −20 °C, **{soc_floor['-10']}** % при −10 °C і **{soc_floor['0']}** % при 0 °C",
                 f"медіанного сезону ({neg(c14['median'])} °C) акумулятор тримає "
                 f"**{r2(ra['battery_days_at_median_coldest_fortnight'])}** доби для AGM і "
                 f"**{r2(rl['battery_days_at_median_coldest_fortnight'])}** для LiFePO₄",
                 f"у найхолоднішу з {n} ({neg(c14['min'])} °C) — **{r2(ra['battery_days_at_coldest_fortnight'])}** і "
                 f"**{r2(rl['battery_days_at_coldest_fortnight'])}**",
                 f"поїздок для LiFePO₄ **{r2(rl['ratified_rule_trips_median'], 'd')}** медіанно й до "
                 f"**{r2(rl['ratified_rule_trips_max'], 'd')}** (за сталих 14 діб — {bt['trips_every_14_days']['median']} і "
                 f"{bt['trips_every_14_days']['max']}, за повної ємності — {third['december_capped_trips_median']['100_Ah_ours']} і "
                 f"{third['december_capped_trips_max']['100_Ah_ours']})",
                 f"(температура відома наперед, без запасу) | **{rules['ratified_rule_on_victron_reading']['trips_median']}** · "
                 f"**{rules['ratified_rule_on_victron_reading']['trips_max']}** | "
                 f"**{risk('ratified_rule_on_victron_reading')['eve_cell_0p5c']['seasons']}** · "
                 f"**{risk('ratified_rule_on_victron_reading')['victron_pack_le_1c']['seasons']}** |",
                 f"| раз на 14 діб | {rules['every_14_days']['trips_median']} · {rules['every_14_days']['trips_max']} | "
                 f"**{risk('every_14_days')['eve_cell_0p5c']['seasons']}** · **{risk('every_14_days')['victron_pack_le_1c']['seasons']}** |",
                 f"| грудень–лютий раз на 10, далі раз на 14 | {rules['december_to_february_every_10_else_14']['trips_median']} · "
                 f"{rules['december_to_february_every_10_else_14']['trips_max']} | "
                 f"**{risk('december_to_february_every_10_else_14')['eve_cell_0p5c']['seasons']}** · "
                 f"**{risk('december_to_february_every_10_else_14')['victron_pack_le_1c']['seasons']}** |",
                 f"| грудень–березень раз на 10, далі раз на 14 | {rules['december_to_march_every_10_else_14']['trips_median']} · "
                 f"{rules['december_to_march_every_10_else_14']['trips_max']} | "
                 f"{risk('december_to_march_every_10_else_14')['eve_cell_0p5c']['seasons']} · "
                 f"{risk('december_to_march_every_10_else_14')['victron_pack_le_1c']['seasons']} |",
                 f"| раз на 10 діб | {rules['every_10_days']['trips_median']} · {rules['every_10_days']['trips_max']} | "
                 f"{risk('every_10_days')['eve_cell_0p5c']['seasons']} · {risk('every_10_days')['victron_pack_le_1c']['seasons']} |",
                 f"**{ft['stop_Ah_rounded_up']}** А·год за струму первинок {bt['current_A']} A",
                 f"мета **{ft['stop_Ah_with_10_pct_current_margin']}** А·год (запас 10 % на струм",
                 f"середня має лягти між {neg(ft['accepted_mean_C'][0]).replace('.0', '')} і "
                 f"{neg(ft['accepted_mean_C'][1]).replace('.0', '')} °C",
                 f"не покриває найхолоднішої десятидобової смуги запису, {neg(cm['10'])} °C",
                 f"найхолодніші 3-, 5- і 7-добові середні запису — **{neg(cm['3'])}**, **{neg(cm['5'])}**, **{neg(cm['7'])}** °C",
                 f"**≥ {need['14']} %** — обмін раз на 14 діб усю кампанію", f"не холодніша за {neg(cm['14'])} °C",
                 f"поїздок **{be[hi]['trips_median']}** медіанно й до **{be[hi]['trips_max']}**. Чому",
                 f"від {be[hi]['trips_median']} · {be[hi]['trips_max']} поїздок біля {need['14']} % до **{be[lo]['trips_median']}** · "
                 f"**{be[lo]['trips_max']}** біля {need['10']} %",
                 f"(а раз на 10 — уже {rules['every_10_days']['trips_median']} · {rules['every_10_days']['trips_max']} поїздок)",
                 # the ratified paragraph, verbatim
                 f"**{lp_l['mass_kg']:.2f}** кг і **{uah(lp_l['price_uah'])}** ₴ кожен",
                 f"в {c(f14, 'air_24h_mean')} кампаніях із {n} за добовим середнім; виробник",
                 f"ресурс у найхолоднішу двотижневу смугу {r2(rl['battery_days_at_coldest_fortnight'])} доби, у медіанного сезону "
                 f"{r2(rl['battery_days_at_median_coldest_fortnight'])}, поїздок {r2(rl['trips_median'], 'd')} медіанно й до "
                 f"{r2(rl['trips_max'], 'd')}",
                 f"повітря нижче −20 °C буває в {fl_l['seasons_with_hours_below']['air_24h_mean']} кампаніях із {n}"):
        assert frag in sheet, f"field sheet §3 (battery type): expected {frag!r}"
    b5 = sum(f["beaufort_5_hours_below"] for t in (agm, lfp) for f in t["discharge_floors"].values())
    assert b5 == 0, "the sheet says the cold cut-off costs no target hour"
    summary = " ".join((REPO / SUMMARY).read_text(encoding="utf-8").split())
    for frag in (f"it is at {f14['soc_at_swap_pct']:.1f} % by then, where the point is {neg(f14['freezing_point_at_swap_C'])} °C",
                 f"**{ph(f14, 'air_24h_mean')}** of {n} campaigns on the 24-hour mean (**{ph(f14, 'air_hourly')}** hour by hour)",
                 f"against **{ph(by[min(by, key=int)], 'air_24h_mean')}** for swaps every {min(by, key=int)} days",
                 f"crosses in **{fl_l['seasons_with_hours_below']['air_24h_mean']}** / "
                 f"**{fl_l['seasons_with_hours_below']['air_hourly']}** campaigns",
                 f"exceeds in **{rh['share_of_campaign_hours'] * 100:.0f} %** of the campaign hours",
                 f"**{r2(ra['battery_days_at_median_coldest_fortnight'])}** days (AGM) and "
                 f"**{r2(rl['battery_days_at_median_coldest_fortnight'])}** (LiFePO4) in the median season's coldest fortnight, "
                 f"**{r2(ra['battery_days_at_coldest_fortnight'])}** and **{r2(rl['battery_days_at_coldest_fortnight'])}** in the "
                 f"coldest of {n}",
                 f"costs **{r2(rl['ratified_rule_trips_median'], 'd')}** trips at the median and up to "
                 f"**{r2(rl['ratified_rule_trips_max'], 'd')}**",
                 f"known costs **{rules['ratified_rule_on_victron_reading']['trips_median']}** trips at the median and up to "
                 f"**{rules['ratified_rule_on_victron_reading']['trips_max']}** with cut-offs in "
                 f"**{risk('ratified_rule_on_victron_reading')['eve_cell_0p5c']['seasons']}** / "
                 f"**{risk('ratified_rule_on_victron_reading')['victron_pack_le_1c']['seasons']}** campaigns",
                 f"swapping every 14 days, in **{risk('every_14_days')['eve_cell_0p5c']['seasons']}** / "
                 f"**{risk('every_14_days')['victron_pack_le_1c']['seasons']}**",
                 f"in **{risk('december_to_march_every_10_else_14')['eve_cell_0p5c']['seasons']}** / "
                 f"**{risk('december_to_march_every_10_else_14')['victron_pack_le_1c']['seasons']}** for "
                 f"**{rules['december_to_march_every_10_else_14']['trips_median']}** trips at the median and up to "
                 f"**{rules['december_to_march_every_10_else_14']['trips_max']}**",
                 f"stop at **{ft['stop_Ah_rounded_up']}** Ah",
                 f"(**{be[hi]['trips_median']}** trips at the median and up to **{be[hi]['trips_max']}**), at {need['10']} % it costs "
                 f"**{be[lo]['trips_median']}** and **{be[lo]['trips_max']}**"):
        assert frag in summary, f"SUMMARY §HW.43 ⊕ battery: expected {frag!r}"
    canon = " ".join((REPO / "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md").read_text(encoding="utf-8").split())
    pooled = {k: [min(ra[k][0], rl[k][0]), max(ra[k][1], rl[k][1])]
              for k in ("battery_days_at_median_coldest_fortnight", "battery_days_at_coldest_fortnight")}
    for frag in (  # the ⊕ on the second ⚖️
                 f"тримає **{r2(pooled['battery_days_at_median_coldest_fortnight'])}** доби в найхолоднішу двотижневу смугу "
                 f"медіанного сезону і **{r2(pooled['battery_days_at_coldest_fortnight'])}** — у найхолоднішу з {n}",
                 # the third ⚖️ 2026-10-19, as ratified — its numbers were the grounds of the «так»
                 f"(LogicPower LP LiFePO4 — **{lp_l['mass_kg']:.2f}** кг і **{uah(lp_l['price_uah'])}** ₴ кожен",
                 f"маса ≈ втричі менша за AGM (**{lp_a['mass_kg']:.2f}** кг)",
                 f"в **{c(f14, 'air_24h_mean')}** із {n} кампаній за добовим середнім (**{c(f14, 'air_hourly')}** — погодинно; за "
                 f"обміну раз на {min(by, key=int)} діб — **{c(by[min(by, key=int)], 'air_24h_mean')}**)",
                 f"ресурс у найхолоднішу двотижневу смугу **{r2(rl['battery_days_at_coldest_fortnight'])}** доби (медіанний сезон — "
                 f"**{r2(rl['battery_days_at_median_coldest_fortnight'])}**), поїздок **{r2(rl['trips_median'], 'd')}** медіанно й "
                 f"до **{r2(rl['trips_max'], 'd')}**",
                 f"повітря нижче −20 °C буває в **{fl_l['seasons_with_hours_below']['air_24h_mean']}** кампаніях із {n}",
                 # its post-«так» ⊕
                 f"виходить **{ph(f14, 'air_24h_mean')}** кампаній за добовим середнім (**{ph(f14, 'air_hourly')}** погодинно), тож "
                 f"{f14['seasons_with_freeze_hours_over_first_swap_day']['air_24h_mean'][0]} — мінімум, а за обміну раз на "
                 f"{min(by, key=int)} діб — **{ph(by[min(by, key=int)], 'air_24h_mean')}**",
                 f"— **{r2(rl['ratified_rule_trips_median'], 'd')}** медіанно й до **{r2(rl['ratified_rule_trips_max'], 'd')}** (у "
                 f"присуді — {r2(rl['trips_max'], 'd')}, з обміном точно на ресурсі; за сталих 14 діб — "
                 f"**{bt['trips_every_14_days']['median']}** і **{bt['trips_every_14_days']['max']}**)",
                 f"вище {rh['spec_pct']} % стоїть **{rh['share_of_campaign_hours'] * 100:.0f} %** годин кампанії",
                 f"годину Бофорт-5 за {n} кампаній — **{neg(bt['coldest_air_in_a_beaufort_5_hour_C'])}** °C"):
        assert frag in canon, f"01_02 §2.2 (battery ⊕ / third ⚖️ / its ⊕): expected {frag!r}"
    tm = [r["trips_median"] for r in rules.values()]
    ts = [v["seasons"] for r in rules.values() for v in r["at_risk_by_lifepo4_reading"].values()]
    for frag in (f"календарі дають від {min(tm)} до {max(tm)} поїздок медіанно й від {min(ts)} до {max(ts)} кампаній із відсічкою",
                 f"найхолоднішу двотижневу ({neg(cm['14'])} °C) і десятидобову ({neg(cm['10'])} °C) смугу {n} сезонів",
                 f"частка ≥ {need['14']} % — 14 діб, ≥ {need['10']} % — 10 діб",
                 f"найхолодніші 3–7-добові середні запису холодніші, {neg(cm['3'])}…{neg(cm['7'])} °C",
                 f"тривалий розряд нижче {soc_floor['-20']} % при −20 °C заборонено",
                 f"мета зупинки — {ft['stop_Ah_rounded_up']} А·год", f"без виміру — {ft['stop_Ah_with_10_pct_current_margin']} А·год",
                 f"≥ {need['14']} % — обмін раз на 14 діб усю кампанію, без прогнозу й лічильника ({be[hi]['trips_median']} поїздок "
                 f"медіанно й до {be[hi]['trips_max']})",
                 f"від {be[hi]['trips_median']} · {be[hi]['trips_max']} до {be[lo]['trips_median']} · {be[lo]['trips_max']} поїздок"):
        assert frag in canon, f"01_02 §2.2, the fourth ⚖️ (the freezer measurement, ratified 2026-10-19): expected {frag!r}"


def test_alloy_stiffness_table_is_fraction_times_modulus():
    """01_01 §5.2 ⊕ (2026-10-18, HW.33): the part's apparent stiffness in each bake-off alloy = the voxel-FE fraction of
    the finest grid (tools/cad/cache/fea — a cache this file's CACHE does not reach, read by path) × that alloy's
    E_solid in lib.constants, and the gap to E_R/E_T 0.5–1.5 GPa = the radial figure over 1.5 … 0.5. CAN catch: a
    re-run FE or a changed modulus that leaves the table behind, an alloy added to or dropped from constants but not
    the table, the fractions quoted in the prose drifting from the cache. CANNOT catch: whether the moduli are right —
    they are unsourced reference values, and the table says so — nor the Poisson ratio's effect on the fraction."""
    from lib.constants import ALLOY_PROPERTIES
    rows = json.loads((REPO / "tools/cad/cache/fea/anchor_zone1_pine.json").read_text(encoding="utf-8"))["rows"]
    fine = min(rows, key=lambda r: r["step_mm"])
    text = (REPO / "docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md").read_text(encoding="utf-8")
    assert f"(осьова **{fine['axial_ratio']:.4f}**, радіальна **{fine['radial_ratio']:.4f}**)" in text
    label = {"Ti-6Al-4V": "Ti-6Al-4V (база)", "Ti-6Al-7Nb": "Ti-6Al-7Nb", "CP-Ti-Gr4": "CP-Ti Gr4",
             "beta-Ti-13Nb-13Zr": "β-Ti-13Nb-13Zr", "Ta": "Ta (лише монета)", "Ti-15Zr": "Ti-15Zr"}
    assert set(label) == set(ALLOY_PROPERTIES), "an alloy in lib.constants has no row in the 01_01 §5.2 table, or the reverse"
    for key, name in label.items():
        e = ALLOY_PROPERTIES[key]["E_GPa"]
        ax, rad = fine["axial_ratio"] * e, fine["radial_ratio"] * e
        row = f"| {name} | {e:g} | {ax:.1f} | {rad:.1f} | {rad / 1.5:.1f}–{rad / 0.5:.0f}× |"
        assert row in text, f"01_01 §5.2 alloy table: expected the row {row!r}"


def test_anchor_anode_cold_start_words_match_cache():
    """SUMMARY says in words which Zone-1 parts cross each edge below the anchor's worst-case cold-start draw; the currents
    are pinned above, the words here (revised sap, 2026-10-18; broadleaf and oak in the beech point Q8 the same day). CAN
    catch: a rerun that moves a part across the draw while the text keeps its group (every part but oak «in every
    reading» at pH 5.5, oak «only in some»; «no part» at pH 4.5 on the worst column, and who does at the typical draw),
    or a part leaving the sap the text gives it. CANNOT catch: whether the sap-gap state is the stem's, whether beech
    sap is oak's, nor how much of the beech potassium malate really balances.
    """
    a = json.loads((CACHE / FACE_PH).read_text(encoding="utf-8"))["anchor_anode_sap_gap"]
    text = " ".join((REPO / SUMMARY).read_text(encoding="utf-8").split())
    by = a["by_sku"]
    short = lambda k: k.removeprefix("anchor_zone1_")  # noqa: E731
    assert {short(k) for k, v in by.items() if v["sap"] == "beech_q8"} == {"broadleaf", "oak"}
    assert "broadleaf and oak in the beech point of `67` Q8" in text
    edge = lambda e, col, q: {short(k) for k, v in by.items()  # noqa: E731
                              if v[f"face_pH_{e}"]["crossed_below_cold_start"][col][q]}
    assert edge("5.5", "worst", "in_every_reading") == {short(k) for k in by} - {"oak"}
    assert "oak" in edge("5.5", "worst", "in_some_reading")
    assert "Every pine-sap part, and broadleaf, crosses pH 5.5 below the worst-case draw in every reading; oak only in some" in text
    assert not edge("4.5", "worst", "in_some_reading")
    assert "No part crosses pH 4.5 below the worst-case draw in any reading" in text
    assert edge("4.5", "typ", "in_some_reading") == {"pine", "graded_porosity", "stepped"}
    assert "at the typical 25 µA draw pine and its two topology variants do in some" in text
    acid = by["anchor_zone1_broadleaf"]["summer_acid_dates"]
    assert acid["medians_below_kinetic_edge"] and acid["medians_minus_stability_edge"][0] >= 0 > acid["lowest_tree_minus_stability_edge"]
    assert "the bulk is then below the kinetic edge and at the stability edge before any current" in text
    import datetime
    named = [datetime.date.fromisoformat(x) for x in acid["dates"]]
    assert f"({named[0].day} May, {named[1].day} and {named[2].day} July)" in text and [x.month for x in named] == [5, 7, 7]
    assert by["anchor_zone1_oak"]["own_sap_reading"]["below_kinetic_edge"] and "oak's own sap stands below the kinetic edge" in text
    assert "both as proxies" in text
    assert "load point B" not in text.split("**The anchor's anode")[1].split("**What it says:**")[0]


def test_a3d_crosscheck_cannot_aggregate_the_exposure_gate_sentinel():
    """The trap this cache exists to name: A3D writes a hard 0.0 for a BURIED residue, in the same
    column as a measured value. Every statistic script 80 reports must have excluded those rows.

    CAN catch: a future edit that lets a sentinel into a max/min/ranking — the gated rows would
    reappear as 'measured' and the counts below would stop adding up; a ranking that silently
    includes them (the compensated positions' ranks are taken among MEASURED positives only).
    CANNOT catch: a wrong reading of a genuinely measured score, nor whether A3D itself is the
    right instrument — both instruments here are of the same family, which the cache says in prose.
    """
    d = json.loads((CACHE / A3D).read_text(encoding="utf-8"))
    cen, tot = d["exposure_gate_census"], d["totals_of_a3d_output"]
    assert cen["n_sentinel"] + cen["n_measured"] == tot["n_residues"], "census does not partition the chain"
    assert cen["n_sentinel_hydrophobic_by_a3d_matrix"] <= cen["n_sentinel"]
    assert 0.0 < cen["sentinel_fraction"] < 1.0
    # no neighbour reported anywhere may be a sentinel or non-positive
    for site, rec in d["sites"].items():
        for radius, nb in rec["best_measured_positive_neighbour_by_radius_A"].items():
            if nb is not None:
                assert nb["a3d_score"] > 0.0, f"{site} @{radius} Å reports a non-positive neighbour"
                assert nb["ca_ca_distance_A"] <= float(radius) + 1e-9, f"{site} neighbour outside its shell"
    # the agreement statement must be derivable from the three lists it summarises (00_05 §5)
    ag = d["agreement"]
    assert set(ag["of_those_whose_flagged_neighbour_is_a_ratified_compensation"]) | set(ag["of_those_uncompensated"]) \
        == set(ag["sites_with_a_measured_positive_neighbour_at_7A"]), "the agreement lists do not partition"
    # a rank is meaningless unless it is taken among measured positives
    for label, rec in d["compensated_positions"].items():
        if rec["rank_among_mature_positive"] is not None:
            assert not rec["a3d_score_is_sentinel"], f"{label} is ranked while being a sentinel"
            assert rec["a3d_score"] > 0.0, f"{label} is ranked with a non-positive score"
            assert 1 <= rec["rank_among_mature_positive"] <= rec["n_mature_positive"]


# The sap recipe is MIRRORED into every lab letter and test plan that prepares it, and only 01_02's table was pinned —
# so on the 2026-10-18 revision the S-N plan kept the 09-17 point as the live one and nothing turned red. This walks
# every salt concentration written in docs/protocols/ (the in-silico results pages excluded: SUMMARY quotes the
# history and the swept corners, each pinned on its own) and holds it to the live point in 67's cache. Malic acid is
# the one salt with a second legitimate value — the cathode's buffered medium (⚖️ 2026-10-12, 01_03 §3.5), read from
# 85's own constant. CAN catch: a mirror left on a superseded point, in any letter or plan, table or prose. CANNOT
# catch: a mirror that writes the salt under another name or with the number BEFORE the name.
_SAP_SALT = re.compile(r"(KNO₃|CaCl₂|MgSO₄|[Mm]alic acid|[Яя]блучна кислота)[^|\n\d]{0,12}?\|?\s*\**(\d+[.,]\d+|\d+)\**")


def test_sap_recipe_mirrors_match_the_live_point():
    point = json.loads((CACHE / SAP).read_text(encoding="utf-8"))["q7_revised_point"]["recipe_mM"]
    src85 = (REPO / "tools/in_silico/scripts/85_electrode_interfacial_ph.py").read_text(encoding="utf-8")
    buffered = float(re.search(r"^BUFFERED_MALIC_MM = ([\d.]+)", src85, re.M).group(1))
    allowed = {"KNO₃": {point["kno3"]}, "CaCl₂": {point["cacl2"]}, "MgSO₄": {point["mgso4"]},
               "malic": {point["malic"], buffered}}
    bad, files = [], set()
    for f in sorted((REPO / "docs/protocols").rglob("*.md")):
        if "in_silico" in f.parts:
            continue
        for i, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
            for m in _SAP_SALT.finditer(line):
                salt = m.group(1) if m.group(1) in allowed else "malic"
                files.add(f.name)
                if float(m.group(2).replace(",", ".")) not in allowed[salt]:
                    bad.append(f"{f.relative_to(REPO)}:{i}: {m.group(1)} {m.group(2)}")
    assert len(files) >= 5, f"the walk found the recipe in only {sorted(files)} — the pattern no longer reads the letters"
    assert not bad, "a recipe mirror off the live point (67 q7):\n" + "\n".join(bad)
