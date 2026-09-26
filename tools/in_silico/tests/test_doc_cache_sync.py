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


def doc(rel: str) -> str:
    """Read a doc by path relative to the repo root."""
    if rel not in _DOC:
        _DOC[rel] = (REPO / rel).read_text(encoding="utf-8")
    return _DOC[rel]


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


def _to_float(s: str) -> float:
    for d in _DASHES:
        s = s.replace(d, "-")
    s = s.replace(" ", "")
    if "×10" in s:
        mant, _, exp = s.partition("×10")
        return float(mant) * 10 ** int("".join(_SUP_MAP.get(c, c) for c in exp))
    return float(s)


SUMMARY = "docs/protocols/ebfc/in_silico/SUMMARY.md"
L3 = "docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md"
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
# Number class allows an optional leading dash of any flavour.
N = rf"([{_DASHES}\-]?[\d.]+)"
NSCI = rf"([{_DASHES}\-]?[\d.]+(?:×10[{_SUP_MINUS}]?[{_SUP}]+)?)"
CHECKS = [
    # ── PRIMARY: the provenance-mix the guard exists to catch ──
    (
        "cascade Δε Marcus-verdict → comparison.json (script 22 gate)",
        SUMMARY, rf"Raw Δε \(dimethyl\) \| {N} eV",
        "dft/comparison.json", lambda d: d["delta_eV"], 0.001,
    ),
    (
        "cascade Δε ωB97X-table B3LYP col → comparison.json",
        L3, rf"\| Δε \(dimethyl\) \| {N} eV \| \*\*[−–—\-]6\.020",
        "dft/comparison.json", lambda d: d["delta_eV"], 0.001,
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
        SUMMARY, r"adiabatic \*\*\+([\d.]+)\*\* = IP_adiab",
        "dft/delta_scf_corrections.json", lambda d: d["dG_adiabatic_eV"], 0.0005,
    ),
    (
        "IP_adiab(FAD) → delta_scf_corrections.json",
        SUMMARY, r"IP_adiab\(FAD ([\d.]+)\)",
        "dft/delta_scf_corrections.json", lambda d: d["IP_adiabatic_eV"], 0.001,
    ),
    (
        "PCET E°(FAD/FADH₂) pH7 → pcet_redox_potential.json",
        SUMMARY, rf"E°\(FAD/FADH₂\) = \*\*{N} mV vs NHE",
        "dft/pcet_redox_potential.json", lambda d: d["E_vs_SHE_mV"]["pH_7.0"], 1.0,
    ),
    # The free-flavin exp value is a BRACKET since 2026-09-24 (00_07 HW.5.IS): «within ~50 mV» had been
    # quoted from the unsourced −208 end while the sourced −220 end sits 62 mV away. Both ends pinned.
    (
        "PCET Δ vs free-flavin, −208 end → pcet_redox_potential.json",
        SUMMARY, rf"lands \*\*{N}–[\d.]+ mV\*\* from the free-flavin",
        "dft/pcet_redox_potential.json", lambda d: d["delta_vs_exp_pH7_mV"][1], 1.0,
    ),
    (
        "PCET Δ vs free-flavin, −220 end → pcet_redox_potential.json",
        SUMMARY, rf"lands \*\*[\d.]+–{N} mV\*\* from the free-flavin",
        "dft/pcet_redox_potential.json", lambda d: d["delta_vs_exp_pH7_mV"][0], 1.0,
    ),
    # ── Hammett LFER ──
    (
        "LFER slope → os_mediator_series.json",
        SUMMARY, rf"slope ≈ {N} eV/σ",
        "dft/os_mediator_series.json", lambda d: d["lfer"]["slope_eV_per_sigma"], 0.005,
    ),
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
        SUMMARY, r"β·d = \*\*([\d.]+) ± 0\.13",
        "dft/tunneling_ensemble.json", lambda d: d["beta_d_mean"], 0.005,
    ),
    # ── Cathode DET (all three ZIF hops) ──
    (
        "Cu-Co t_ij (crude) → zif_hopping.json pairs[0]",
        SUMMARY, r"Cu↔Co \(T1↔ZIF node\) \| \*\*([\d.]+)\*\* ←",
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
        "coupling gain to reach turnover (FO-DFT scale) → cathode_ket_lambda.json",
        SUMMARY, r"needs \*\*×([\d.]+)\*\* on the FO-DFT t_ij",
        "dft/cathode_ket_lambda.json",
        lambda d: d["coupling_gain_to_reach_turnover"]["at_literature_lambda_fodft_t"], 5e-4,
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
        SUMMARY, r"\| Healthy summer \| 19\.9 \| [\d.]+ \| [\d.]+ \| \*\*([\d.]+)–[\d.]+\*\* \|",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["ph_bracket"]["rows"], "scenario", "healthy summer")["delta_t_ph55_low_s"], 0.1,
    ),
    (
        "pH-bracket healthy-summer HIGH end → delta_t_lookup.json §ph_bracket",
        SUMMARY, r"\| Healthy summer \| 19\.9 \| [\d.]+ \| [\d.]+ \| \*\*[\d.]+–([\d.]+)\*\* \|",
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
        SUMMARY, r"✅ Healthy ([\d.]+)s / Stressed",
        "kinetics/delta_t_lookup.json",
        lambda d: named(d["reference_points"], "scenario", "healthy summer")["delta_t_s"], 0.1,
    ),
    (
        "delta_t cold-winter → delta_t_lookup.json (Executive Summary prose, NOT the table)",
        SUMMARY, r"/ Stressed ([\d.]+)s",
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
        SUMMARY, rf"solid Ti, NO PEEK break at all\*\* \| 1\.27e−2 W/K \| 8× \| \*\*{N} °C",
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
    # ⛔ The anchor used to spell the floor itself («до 10 МПа»), so the pin guarded the force while
    # hard-coding the one input that was wrong — 10 MPa is a third of the 01_01 §4.3 table, not the
    # tenth the prose names. The floor is its own pin now, and the force anchor carries no number.
    (
        "PEEK relaxation-regime floor → z_stack_tolerance.json §rim_datum_creep",
        BLIND_MATE, rf"до {N} МПа \(десята частина",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["rim_datum_creep"]["relax_regime_floor_MPa"], 0.05,
    ),
    (
        "force that would put the PEEK rim into the relaxation regime → z_stack_tolerance.json",
        BLIND_MATE, rf"табулює релаксацію PEEK\) треба \*\*{N} Н\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["rim_datum_creep"]["force_to_reach_relax_regime_N"], 1.0,
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
    (
        "rim-datum margin at a generous 100 N → z_stack_tolerance.json §rim_datum_creep",
        BLIND_MATE, rf"запас лишається \*\*{N}×\*\*",
        "mechanical/z_stack_tolerance.json", lambda d: d["rim_datum_creep"]["margin_x_at_100N"], 0.05,
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
    (
        "the pad-under-piezo row that does not close at all → z_stack_tolerance.json §vertical_stack_budget",
        BLIND_MATE, rf"не закривається взагалі \(\*\*{N} мм\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: min(r["room_over_rf_deck_centre_mm"] for r in d["vertical_stack_budget"]["rows"]
                      if r["placement"] == "pad_under_piezo" and r["fr4_is_bom"]
                      and not r["b2b_is_named_alternative"]), 0.005,
    ),
    (
        "antenna Z the named B2B alternative leaves (pad beside piezo) → z_stack_tolerance.json",
        BLIND_MATE, rf"у гілці «поруч» — до \*\*{N} мм\*\*",
        "mechanical/z_stack_tolerance.json",
        lambda d: d["vertical_stack_budget"]["summary"]["alt_b2b_lever"]["antenna_z_mm_pad_beside_piezo"], 0.005,
    ),
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
        "mouth approach angle per µm of channel offset, shipped branch, placeholder → bus_mechanical.json §edge_bearing",
        SUMMARY, rf"the approach angle grows at \*\*{N}°/µm\*\* of offset past the play on the placeholder",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["clearance_regime"]["edge_bearing"]["rows"]
                       if r["geometry"].startswith("script 55 placeholder") and r["branch"].startswith("PEEK liner"))
        ["approach_angle_deg_per_um_past_play"], 0.00005,
    ),
    (
        "mouth approach angle per µm, canon mirror → bus_mechanical.json §edge_bearing",
        COAXIAL, rf"кут росте на \*\*{N}°\*\* на мікрометр зсуву понад люфт на плейсхолдері",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["clearance_regime"]["edge_bearing"]["rows"]
                       if r["geometry"].startswith("script 55 placeholder") and r["branch"].startswith("PEEK liner"))
        ["approach_angle_deg_per_um_past_play"], 0.00005,
    ),
    (
        "exit landing angle of the touched-down rod, placeholder → bus_mechanical.json §edge_bearing.exit_contact",
        SUMMARY, rf"lands on the bore's exit edge at \*\*{N}°\*\*",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["edge_bearing"]["exit_contact"][0]["landing_angle_deg_rigid_wall"], 0.0005,
    ),
    # ⛔ The SIGN of this ratio is the finding (the 6 mm column OVERSTATES the rigid-wall end of the coaxial bracket, where the drift
    # picture had it «understated by 40.8 %»), so the number canon and SUMMARY quote is pinned in both.
    (
        "§2 supported column over the rigid-wall end, placeholder → bus_mechanical.json §supported_column_vs_equilibrium",
        SUMMARY, rf"OVERSTATES that rigid-wall end ×\*\*{N}\*\* at nominal µ on the placeholder",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"][0]["column_over_cap_nominal"], 0.005,
    ),
    (
        "§2 supported column over the coaxial cap, canon mirror → bus_mechanical.json §supported_column_vs_equilibrium",
        COAXIAL, rf"ЗАВИЩУЄ ×\*\*{N}\*\* при номінальному терті на плейсхолдері",
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
        SUMMARY, rf"\| \*\*0\.40 \(model, ⚖️ ratified\)\*\* \| \*\*5 / 6\*\* \| \*\*{N}\*\* \|",
        "mechanical/bus_mechanical.json",
        lambda d: next(r for r in d["endurance_ratio_band"]["rows"]
                       if r["endurance_over_yield"] == 0.40)["binding_sf_unsupported"], 0.005,
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
        COAXIAL, rf"дужка \[8\.04, \*\*{N}\*\*\] МПа на плейсхолдері",
        "mechanical/bus_mechanical.json",
        lambda d: d["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"][0]["bracket_MPa_worst_mu"][1], 0.05,
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
        SUMMARY, rf"\*\*{N} Å from the Beratan-Onuchic tunnelling path\*\*",
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
        "CHEM.11 Gln258 d(e⁻ path) → chem11 (L1 §2 — why Gln258 is untouchable)",
        L1, rf"\*\*{N} Å from the tunnelling path",
        CHEM11, lambda d: named(d["hotspots"], "site", 258)["d_electron_path_A"], 0.06,
    ),
    (
        "CHEM.11 Gln258 d(FAD) → chem11 (L1 §2)",
        L1, rf"tunnelling path and {N} Å from FAD\*\*",
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
_RECIPE_LABELS = {"malic": "Яблучна кислота (malic acid)", "kno3": "KNO₃ (K⁺)", "cacl2": "CaCl₂ (Ca²⁺)",
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
     SAP, lambda d, k=key: d["q6_ratified_point"]["recipe_mM"][k], 0.0)
    for key, label in _RECIPE_LABELS.items()
] + [
    ("01_02 §2.1 pH set-point (canon → script 67 premise: re-run 67 on a recipe change)",
     METALLURGY, rf"\| pH \| \*\*{N}\*\* \(уставка\)",
     SAP, lambda d: d["q6_ratified_point"]["conditions"]["setpoint"]["ph"], 0.0),
    ("01_02 §2.1 pH side series (canon → script 67 premise: re-run 67 on a recipe change)",
     METALLURGY, rf"бічна серія \*\*{N}\*\* \(лише ICP-MS",
     SAP, lambda d: d["q6_ratified_point"]["conditions"]["side_series"]["ph"], 0.0),
] + [
    (f"sap ratified point, {quantity} {end} at pH {ph_re.replace(chr(92), '')} → sap_recipe_saturation.json (01_02 §2.1)",
     METALLURGY, pattern, SAP,
     lambda d, c=cond, q=key, j=j: d["q6_ratified_point"]["conditions"][c][q][j], 0.006)
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
    ("sap ratified point, buffer capacity at the set-point → sap_recipe_saturation.json (01_02 §2.1)",
     METALLURGY, rf"β ≈ {N} mM на одиницю pH при 5\.75",
     SAP, lambda d: d["q6_ratified_point"]["conditions"]["setpoint"]["buffer_capacity_mM_per_pH_25c"], 0.006),
    ("sap ratified point, strong acid for −0.1 pH at the set-point → sap_recipe_saturation.json (01_02 §2.1)",
     METALLURGY, rf"pH на 0\.1 зсуває вже ≈ \*\*{N} mM\*\* сильної кислоти",
     SAP, lambda d: d["q6_ratified_point"]["conditions"]["setpoint"]["strong_acid_mM_lowering_pH_by_0p1_25c"], 0.0006),
] + [
    (f"sap ratified point, {what} → sap_recipe_saturation.json (SUMMARY §HW.3 Q6)", SUMMARY, pattern, SAP,
     lambda d, c=cond, q=key, j=j: d["q6_ratified_point"]["conditions"][c][q] if j is None
     else d["q6_ratified_point"]["conditions"][c][q][j], tol)
    for cond, row in (("setpoint", r"\| pH 5\.75 \(coin 20–25 °C · accelerated — 40 °C isotherm, ⚖️ 2026-09-24\) \| "),
                      ("side_series", r"\| pH 4\.5 \(coin side series, 20–25 °C\) \| "))
    for what, key, j, pattern, tol in (
        (f"{cond} KOH low", "base_koh_mM", 0, row + rf"\*\*{N}–[\d.]+ mM\*\*", 0.006),
        (f"{cond} KOH high", "base_koh_mM", 1, row + rf"\*\*[\d.]+–{N} mM\*\*", 0.006),
        (f"{cond} K+ total high", "potassium_total_mM", 1, row + rf"[^|]+\| [\d.]+–{N} mM \|", 0.006),
        (f"{cond} buffer capacity", "buffer_capacity_mM_per_pH_25c", None, row + rf"(?:[^|]+\| ){{2}}\*\*{N} mM/pH\*\*", 0.006),
        (f"{cond} strong acid for −0.1 pH", "strong_acid_mM_lowering_pH_by_0p1_25c", None,
         row + rf"(?:[^|]+\| ){{3}}{N} mM \|", 0.006),
    )
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
# ⛔ Every cell is pinned because the ROWS are the message: the same quantity at the insertion placeholder and at
# the lock window differs by an order of magnitude, so a doc that kept one row current and let another rot would
# still read as a sweep while having stopped being one.
_BUS68 = "mechanical/bus_contact_equilibrium.json"
_BUS68_ROWS = (("30 mm — script 55 placeholder", "script 55 placeholder (HW.8)"),
               ("18 mm — lock window near end", "lock window, near end"),
               ("14 mm — lock window far end", "lock window, far end"))


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


def _mc_ph(d, label: str, key: str, fn):
    row = _mc(d, label)["ph55_bracket"]
    return fn(row[f][key] for f in row)


# ⛔ Scenario labels are NOT unique in this file — the deterministic pH table of script `30` carries
# the same four, so an unscoped row pattern matches two tables and the guard reports «ambiguous»
# instead of drifting silently. Every MC row is therefore anchored on ITS OWN table header.
_MC_TABLE = r"90 % CI at pH 5\.5 \(s\)[\s\S]{0,900}?"


def _mc_cell(label: str, skip: int, end: str, bold: bool = False) -> str:
    """One end of a `lo–hi` cell (or a plain cell when `end` is 'only'), inside the MC table."""
    b = r"\*\*" if bold else ""
    body = {"lo": rf"{b}{N}–[\d.]+{b}", "hi": rf"{b}[\d.]+–{N}{b}", "only": rf"{b}{N}{b}"}[end]
    return _MC_TABLE + rf"\| {re.escape(label)} \|" + r"[^|]*\|" * skip + rf" {body} \|"


CHECKS += [
    (f"L4b MC · {lab} · {name} → monte_carlo (the CI and its medium are pinned together)",
     SUMMARY, _mc_cell(lab, skip, end, bold), MC, resolver, 0.06)
    for lab in _MC_ROWS
    for name, skip, end, bold, resolver in (
        ("ceiling CI low", 0, "lo", False, lambda d, sc=lab: _mc(d, sc)["p5_s"]),
        ("ceiling CI high", 0, "hi", False, lambda d, sc=lab: _mc(d, sc)["p95_s"]),
        ("ceiling median", 1, "only", False, lambda d, sc=lab: _mc(d, sc)["median_s"]),
        ("pH5.5 CI low", 2, "lo", True, lambda d, sc=lab: _mc_ph(d, sc, "p5_s", min)),
        ("pH5.5 CI high", 2, "hi", True, lambda d, sc=lab: _mc_ph(d, sc, "p95_s", max)),
        ("pH5.5 median low", 3, "lo", False, lambda d, sc=lab: _mc(d, sc)["ph55_median_low_s"]),
        ("pH5.5 median high", 3, "hi", False, lambda d, sc=lab: _mc(d, sc)["ph55_median_high_s"]),
    )
] + [
    (
        "L4b MC · the upper-decile claim in prose → monte_carlo (the sentence that names the cost)",
        SUMMARY, rf"moves from 84 s to about {N} s",
        MC, lambda d: _mc_ph(d, "Healthy summer", "p95_s", max), 0.6,
    ),
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
    (r"computed λ \(B3LYP, Co spin-crossover ~2× over-est\)", "computed λ (B3LYP, Co over-est)"),
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
    (
        "L3b k_DET · paper §3.4 adverse end → cathode_ket_lambda (the figure the paper now quotes)",
        PAPER_RESULTS, rf"turns the literature-λ figure into a bracket of \*\*×{N} to",
        KET, lambda d: d["scenarios"]["literature λ"]["margin_vs_turnover_adverse"], 0.00006,
    ),
    (
        "L3b k_DET · paper §3.4 favourable end → cathode_ket_lambda",
        PAPER_RESULTS, rf"bracket of \*\*×[\d.]+ to ×{N}\*\*",
        KET, lambda d: d["scenarios"]["literature λ"]["margin_vs_turnover_favourable"], 0.6,
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
        PAPER_RESULTS, rf"the computed \*\*{N} eV\*\* Cu–Co\nsite-energy gap",
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
    import ast
    tree = ast.parse((REPO / CONSTANTS).read_text(encoding="utf-8"), filename=CONSTANTS)
    for node in tree.body:
        targets = getattr(node, "targets", [])
        if isinstance(node, ast.Assign) and any(
                isinstance(t, ast.Name) and t.id == MIRROR_SYMBOL for t in targets):
            return tuple(ast.literal_eval(node.value))
    raise AssertionError(
        f"{CONSTANTS} has no module-level literal `{MIRROR_SYMBOL}` — either it was renamed or it "
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
    return {row[1] for row in CHECKS} | {d[0] for d in _RATIFIED_GENE_DECLARATIONS}


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


def test_cathode_rct_reads_the_current_bracket():
    """`31b`'s k_DET scenarios must be the CURRENT corners of `25`'s bracket × turnover.

    CAN catch: a `31b` cache left behind after `25` moved (it read a ΔG = 0 default for three
    days after the bracket landed) · a scenario dropped or added on one side only.
    CANNOT catch: whether `31b`'s Laviron grid is the right physics — a coherence pin only.
    """
    ket, rct = C("dft/cathode_ket_lambda.json"), C("kinetics/cathode_det_rct.json")
    lit, fo, t = ket["scenarios"]["literature λ"], ket["fodft_cuco_rigor"], ket["turnover_s"]
    expected = sorted([
        lit["margin_vs_turnover_adverse"], lit["margin_vs_turnover_at_dG0"],
        lit["margin_vs_turnover_favourable"], fo["margin_adverse_corner"],
        fo["margin_vs_turnover_by_dG_sign"]["dG=0"], fo["margin_favourable_corner"]])
    got = sorted(k / t for k in rct["k_scenarios_s"].values())
    assert len(got) == len(expected) and all(
        math.isclose(a, b, rel_tol=1e-9) for a, b in zip(got, expected, strict=True)), (
        f"31b k_DET/turnover {got} ≠ the 25 bracket {expected} — re-run 31b")
