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


def _to_float(s: str) -> float:
    for d in _DASHES:
        s = s.replace(d, "-")
    return float(s.replace(" ", ""))


SUMMARY = "docs/protocols/ebfc/in_silico/SUMMARY.md"
L3 = "docs/protocols/ebfc/in_silico/L3_quantum_chemistry.md"
CODIT = "docs/01_04_CODIT_and_Xylemointegration.md"  # thermal-penetration cache (§3.5) — a non-SUMMARY doc-target
BLIND_MATE = "docs/02_02_Blind_Mate_Pogo_Pin_Interface.md"  # Z-stack + gland geometry (§3.5), owner = script 52
COAXIAL = "docs/01_01_Coaxial_Gyroid_Topology_and_PEEK.md"  # anchor geometry; §1.4 bus + liner, owner = script 55
METALLURGY = "docs/01_02_Ti_6Al_4V_Metallurgy_and_DMLS.md"  # §2.1 synthetic sap + its saturation verdict, owner = script 67
SAP = "chemistry/sap_recipe_saturation.json"

# Each check: (label, doc-path, regex with ONE capture group = the doc number,
#             cache-file, resolver(cache)->float, tolerance).
# Number class allows an optional leading dash of any flavour.
N = rf"([{_DASHES}\-]?[\d.]+)"
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
        "today's hemisphere headroom (the contrast) → z_stack_tolerance.json §vertical_stack_budget",
        BLIND_MATE, rf"\(сьогоднішня півсфера — {N}\)",
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
    # ⛔ The SIGN of this ratio is the finding (the 6 mm column OVERSTATES the coaxial cap, where the drift
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
    (
        "channel play at the window ceiling → bus_mechanical.json §od_growth_eats_channel_play",
        COAXIAL, rf"люфт падає 25 → {N} мкм",
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
        SUMMARY, rf"\| 0\.40 \| 5 / 6 \| \*\*{N}\*\* \|",
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
]

# ── HW.3: the recipe TABLE is script 67's premise, and its window is quoted slot by slot ──
# ⛔ For the recipe rows the direction of truth is INVERTED and the failure message cannot say so: canon is
# the source and the cache mirrors it — a recipe edit without a re-run of 67 leaves the verdict and the window
# describing a medium nobody specifies any more. Each END is pinned on its own, because a range whose one end
# moved still reads as a range; the window per SLOT, because three levels in one phrase can keep two current.
_RECIPE_LABELS = {"malic": "Яблучна кислота (malic acid)", "oxalic": "Щавлева кислота (oxalic acid)",
                  "kno3": "KNO₃ (K⁺)", "cacl2": "CaCl₂ (Ca²⁺)", "mgso4": "MgSO₄ (Mg²⁺)"}
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
    (f"01_02 §2.1 recipe {key} {end} (canon → script 67 premise: re-run 67 on a recipe change)",
     METALLURGY,
     rf"\| {re.escape(label)} \| {N}–[\d.]+ mM \|" if j == 0 else rf"\| {re.escape(label)} \| [\d.]+–{N} mM \|",
     SAP, lambda d, k=key, j=j: d["recipe_ranges_mM"][k][j], 0.0)
    for key, label in _RECIPE_LABELS.items() for j, end in enumerate(("floor", "ceiling"))
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


# ── HW.34 / HW.23: script 68's table in SUMMARY §HW.34, cell by cell ──
# ⛔ Every cell is pinned because the ROWS are the message: the same quantity at the insertion placeholder and at
# the lock window differs by an order of magnitude, so a doc that kept one row current and let another rot would
# still read as a sweep while having stopped being one.
_BUS68 = "mechanical/bus_contact_equilibrium.json"
_BUS68_ROWS = (("30 mm — script 55 placeholder", "script 55 placeholder (HW.8)"),
               ("15 mm — lock window near end", "lock window, near end"),
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


@pytest.mark.parametrize("label,doc_rel,pattern,cache_rel,resolver,tol",
                         CHECKS, ids=[c[0] for c in CHECKS])
def test_doc_matches_cache(label, doc_rel, pattern, cache_rel, resolver, tol):
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


def test_every_doc_target_triggers_this_guard():
    """Every doc a CHECKS row reads must sit inside BOTH path lists of the workflow that runs it.

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
        for target in sorted({row[1] for row in CHECKS})
        for name, patterns in lists.items()
        if not any(fnmatch.fnmatchcase(target, p) for p in patterns)
    ]
    assert not missing, (
        f"doc targets outside {WORKFLOW} — their pins cannot fire on a change to the doc alone:\n  "
        + "\n  ".join(missing))
