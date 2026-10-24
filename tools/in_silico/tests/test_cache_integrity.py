# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Verify integrity of committed in-silico cache and ligand files.

Runs without conda env — uses only stdlib + json. Safe for CI.
"""
import itertools
import json
import math
import re
import sys
import types
from pathlib import Path

import numpy as np
import pytest

REPO = Path(__file__).resolve().parents[3]
LIGANDS = REPO / "docs/protocols/ebfc/in_silico/ligands"
CACHE = REPO / "tools/in_silico/cache"
DFT = CACHE / "dft"
KINETICS = CACHE / "kinetics"
MECHANICAL = CACHE / "mechanical"
CHEMISTRY = CACHE / "chemistry"
THERMAL = CACHE / "thermal"


# ── Ligand SDF/XYZ files ──

# (element_to_check, min_occurrences) — counts " X " pattern in file content
EXPECTED_LIGANDS = {
    "FAD.sdf": ("C", 10),
    "genipin.sdf": ("C", 5),
    "chitosan_trimer.sdf": ("C", 10),
    "cellobiose.sdf": ("C", 5),
    "ppy_pentamer.sdf": ("C", 10),
    "pvi_trimer.sdf": ("C", 10),
    "sbma_monomer.sdf": ("C", 5),
    "lumiflavin_ox.xyz": ("C", 10),
    "lumiflavin_red.xyz": ("C", 10),
    "os_bpy_im_cl.xyz": ("Os", 1),
    "os_amine_cl.xyz": ("Os", 1),
    "cu_co_zif.xyz": ("Cu", 1),
    "co_ce_zif.xyz": ("Co", 1),
    "ce_graphene.xyz": ("Ce", 1),
}


@pytest.mark.parametrize("filename,expected", EXPECTED_LIGANDS.items())
def test_ligand_exists_and_nonempty(filename, expected):
    path = LIGANDS / filename
    assert path.exists(), f"Missing ligand file: {filename}"
    assert path.stat().st_size > 100, f"Ligand file too small: {filename} ({path.stat().st_size} bytes)"


@pytest.mark.parametrize("filename,expected", EXPECTED_LIGANDS.items())
def test_ligand_contains_expected_element(filename, expected):
    element, min_count = expected
    path = LIGANDS / filename
    if not path.exists():
        pytest.skip(f"{filename} missing")
    content = path.read_text()
    count = content.count(f" {element} ") + content.count(f"\n{element} ")
    assert count >= min_count, f"{filename}: expected ≥{min_count} '{element}' atoms, found {count}"


# ── GAFF cache ──

def test_gaff_cache_exists():
    assert (CACHE / "gaff_cache.json").exists()


def test_gaff_cache_valid_json():
    data = json.loads((CACHE / "gaff_cache.json").read_text())
    assert "gaff-2.11" in data, "Missing gaff-2.11 key"
    entries = data["gaff-2.11"]
    assert len(entries) >= 4, f"Expected ≥4 cached ligands, got {len(entries)}"


def test_gaff_cache_has_ffxml():
    data = json.loads((CACHE / "gaff_cache.json").read_text())
    for key, entry in data["gaff-2.11"].items():
        assert "ffxml" in entry, f"Entry {key} missing ffxml"
        assert "smiles" in entry, f"Entry {key} missing smiles"
        assert len(entry["ffxml"]) > 100, f"Entry {key} ffxml too short"


# ── DFT cache ──

def test_dft_lumiflavin_json():
    path = DFT / "lumiflavin.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert "ox" in data and "red" in data
    assert data["red"]["converged"] is True
    assert -6.0 < data["red"]["HOMO_eV"] < -4.0, f"FADH₂ HOMO out of range: {data['red']['HOMO_eV']}"


def test_dft_os_complex_json():
    path = DFT / "os_complex.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert "os2_plus" in data and "os3_plus" in data
    assert data["os3_plus"]["converged"] is True
    lumo = data["os3_plus"]["LUMO_eV"]
    assert -6.0 < lumo < -2.0, f"Os(III) LUMO out of range: {lumo}"
    # os_complex.json is owned by 21f — the +309 mV dimethyl device mediator (OS-RECOMPUTE).
    # Pin the identity so a 21/21b co-write (plain/NH₃) can't silently revert the cascade.
    assert data.get("ligand") == "4,4'-dimethyl-2,2'-bipyridine", (
        f"os_complex.json ligand={data.get('ligand')!r} — expected the dimethyl device "
        "mediator; re-run 21f, not 21/21b")


def test_dft_comparison_json():
    path = DFT / "comparison.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert "donor_homo_eV" in data
    assert "acceptor_lumo_eV" in data
    assert "delta_eV" in data


def test_os_mediator_series_lfer():
    """① Hammett LFER slope is COMPUTED → cached = single source for fig 60 / table 61 / prose.
    Pins the canonical fit-set + the −0.92 eV/σ value so prose can't silently drift back to −0.93."""
    path = DFT / "os_mediator_series.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert "lfer" in data, "os_mediator_series.json missing computed 'lfer' block (re-run 21e)"
    lf = data["lfer"]
    assert lf["fit_set"] == ["ome", "dmbpy", "bpy", "dcbpy", "no2"], (
        f"LFER fit-set drifted: {lf['fit_set']} (must exclude donor-sat NMe₂/NH₂ + inert CF₃-family)")
    assert -0.93 < lf["slope_eV_per_sigma"] < -0.91, (
        f"LFER slope off canon −0.92: {lf['slope_eV_per_sigma']}")
    assert lf["r2"] > 0.999, f"LFER r² unexpectedly low: {lf['r2']}"


def test_os_mediator_series_wb97x_vs_b3lyp_is_derived_from_its_sources():
    """① ω−B3 (21e `wb97x`, 2026-10-08): every field of `vs_b3lyp` must follow from the caches it cites.

    CAN catch: a hand-edited or stale comparison — a point whose B3LYP or ωB97X value no longer equals its
    source cache (the series row · this cache's own extreme · E_total of 21f/21d at full precision), an offset
    that is not their difference, a fit-subset that is not the canonical fit-set ∩ the points, a slope, span or
    sign flag that does not follow from the rows, and a point whose two tiers ran on different geometries;
    since 2026-10-11 also a compared point whose Os(III) <S²> is on record above the doublet threshold, an Os(III)
    compared without <S²> and not named so, an order swap the rows show and the field omits, and a verdict that
    names a σ end instead of the offset's min and max.
    CANNOT catch: whether either tier is right, nor whether the B3LYP→ωB97X shift is the functional or the basis;
    nor a contaminated state whose <S²> was never recorded — that one is only NAMED (`os3_s2_not_recorded`).
    """
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import S2_MAX_DOUBLET
    w = json.loads((DFT / "os_mediator_series_wb97x.json").read_text())
    b3 = {c["name"]: c for c in json.loads((DFT / "os_mediator_series.json").read_text())["complexes"]}
    fit_set = json.loads((DFT / "os_mediator_series.json").read_text())["lfer"]["fit_set"]
    v = w["vs_b3lyp"]
    nh2 = w["complexes"]["nh2"]
    h2ev = nh2["dE_red_eV"] / (nh2["os2"]["E_total_Ha"] - nh2["os3"]["E_total_Ha"])
    rows = {r["name"]: r for r in v["points"]}
    for name, r in rows.items():
        assert r["b3lyp_dE_red_eV"] == b3[name]["dE_red_eV"], f"{name}: B3LYP value ≠ the series row"
        if name in w["complexes"]:
            assert r["wb97x_dE_red_eV"] == w["complexes"][name]["dE_red_eV"], f"{name}: ωB97X ≠ this cache's row"
        else:
            src = json.loads((DFT / r["wb97x_source"]).read_text())
            e = (src["os2_plus"]["E_total_Ha"] - src["os3_plus"]["E_total_Ha"]) * h2ev
            assert math.isclose(r["wb97x_dE_red_eV"], e, abs_tol=1e-9), f"{name}: ωB97X ≠ E_total of {r['wb97x_source']}"
        assert r["omega_minus_b3_eV"] == r["wb97x_dE_red_eV"] - r["b3lyp_dE_red_eV"], f"{name}: offset ≠ difference"
        assert r["geometry_max_dev_A"] <= 1e-3, f"{name}: the two tiers ran on different geometries"
    sigmas = [r["sigma_para"] for r in v["points"]]
    assert sigmas == sorted(sigmas), "points not ordered by σ"
    def ok(state):   # accepted or s2_not_recorded — the comparison's admission rule, mirroring 21e `_acceptance`
        return (state.get("converged") and state.get("aufbau") is not False and state.get("stable_internal") is not False
                and (state.get("s2") is None or state["s2"] <= S2_MAX_DOUBLET))
    accepted = {n for n, c in w["complexes"].items() if "dE_red_eV" in c and ok(c["os2"]) and ok(c["os3"])}
    assert accepted <= set(rows), "an accepted ωB97X point is missing from the comparison"
    assert set(v["not_compared"]) == set(w["complexes"]) - accepted, "not_compared ≠ the points not accepted"
    assert v["os3_s2_max_accepted"] == S2_MAX_DOUBLET, "the comparison does not record the threshold its acceptance applies"
    small_path = DFT / "os_mediator_series_wb97x_631gd.json"
    small = json.loads(small_path.read_text())["complexes"] if small_path.exists() else {}
    unrecorded = [f"os_mediator_series_wb97x.json:{n}" for n, c in w["complexes"].items()
                  if n in accepted and c["os3"].get("s2") is None]
    unrecorded += [r["wb97x_source"] for r in v["points"] if r["name"] not in w["complexes"]
                   and json.loads((DFT / r["wb97x_source"]).read_text())["os3_plus"].get("s2") is None]
    unrecorded += [f"{p['wb97x_631gd_source'].split()[0]}:chloro" for p in v["centre_decomposition"]["points"]]
    unrecorded += [f"os_mediator_series_wb97x_631gd.json:{p['name']}" for p in v["ends_decomposition"]["points"]
                   if small[p["name"]]["os3"].get("s2") is None]
    assert sorted(v["os3_s2_not_recorded"]) == sorted(unrecorded), "an Os(III) compared without <S²> is not named"
    swaps = [[a["name"], b["name"]] for i, a in enumerate(v["points"]) for b in v["points"][i + 1:]
             if (a["b3lyp_dE_red_eV"] - b["b3lyp_dE_red_eV"]) * (a["wb97x_dE_red_eV"] - b["wb97x_dE_red_eV"]) < 0]
    assert [s["pair"] for s in v["order_swaps"]] == swaps, "order_swaps ≠ the pairs the rows reorder"
    for s in v["order_swaps"]:
        a, b = rows[s["pair"][0]], rows[s["pair"][1]]
        keeps = {t: (b[f"{t}_dE_red_eV"] - a[f"{t}_dE_red_eV"]) * (b["sigma_para"] - a["sigma_para"]) < 0
                 for t in ("b3lyp", "wb97x")}
        assert keeps[s["sigma_order_kept_by"]], f"{s}: that tier does not keep the σ order"
    lo_off = min(v["points"], key=lambda r: r["omega_minus_b3_eV"])
    hi_off = max(v["points"], key=lambda r: r["omega_minus_b3_eV"])
    assert (f"runs from {lo_off['omega_minus_b3_eV']:+.3f} ({lo_off['name']}) to "
            f"{hi_off['omega_minus_b3_eV']:+.3f} eV ({hi_off['name']})") in v["verdict"], "verdict misnames the offset ends"
    assert v["common_fit_subset"] == [n for n in fit_set if n in rows], "fit subset ≠ canonical fit-set ∩ points"

    def slope(key):
        xs = [rows[n]["sigma_para"] for n in v["common_fit_subset"]]
        ys = [rows[n][key] for n in v["common_fit_subset"]]
        mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
        return sum((x - mx) * (y - my) for x, y in zip(xs, ys, strict=True)) / sum((x - mx) ** 2 for x in xs)
    assert math.isclose(v["slope_b3lyp_eV_per_sigma"], slope("b3lyp_dE_red_eV"), abs_tol=1e-9)
    assert math.isclose(v["slope_wb97x_eV_per_sigma"], slope("wb97x_dE_red_eV"), abs_tol=1e-9)
    assert math.isclose(v["slope_ratio_wb97x_over_b3lyp"], v["slope_wb97x_eV_per_sigma"] / v["slope_b3lyp_eV_per_sigma"])
    offs = [r["omega_minus_b3_eV"] for r in v["points"]]
    assert v["offset_range_eV"] == [min(offs), max(offs)]
    lo, hi = rows["nme2"], rows["no2"]   # the span is named, so an added acceptor point cannot move it
    assert (v["span"]["from"], v["span"]["to"]) == ("nme2", "no2")
    assert v["span"]["wb97x_eV"] == hi["wb97x_dE_red_eV"] - lo["wb97x_dE_red_eV"]
    assert v["span"]["b3lyp_eV"] == hi["b3lyp_dE_red_eV"] - lo["b3lyp_dE_red_eV"]
    gap = v["donor_plateau_gap_nme2_minus_nh2_eV"]
    for tier in ("b3lyp", "wb97x"):
        assert gap[tier] == rows["nme2"][f"{tier}_dE_red_eV"] - rows["nh2"][f"{tier}_dE_red_eV"]
    assert v["donor_plateau_gap_same_sign"] == (gap["b3lyp"] * gap["wb97x"] > 0)
    gap = v["acceptor_gap_so2cf3_minus_no2_eV"]
    assert (gap is None) == ("so2cf3" not in rows)
    if gap is not None:
        for tier in ("b3lyp", "wb97x"):
            assert gap[tier] == rows["so2cf3"][f"{tier}_dE_red_eV"] - rows["no2"][f"{tier}_dE_red_eV"]
    order = {t: [r["name"] for r in sorted(v["points"], key=lambda r: r[f"{t}_dE_red_eV"])] for t in ("b3lyp", "wb97x")}
    assert v["same_order_by_dE_red"] == (order["b3lyp"] == order["wb97x"])
    # the centre split: B3LYP/6-31G(d) → ωB97X/6-31G(d) (34b chloro) → ωB97X/def2-TZVP
    cd = v["centre_decomposition"]
    for p in cd["points"]:
        form = next(f for f in json.loads((DFT / p["wb97x_631gd_source"].split()[0]).read_text())["forms"]
                    if f["name"] == "chloro")
        assert math.isclose(p["wb97x_631gd_eV"], (form["E_os2_Ha"] - form["E_os3_Ha"]) * h2ev, abs_tol=1e-9), p["name"]
        assert p["b3lyp_631gd_eV"] == rows[p["name"]]["b3lyp_dE_red_eV"]
        assert p["wb97x_def2tzvp_eV"] == rows[p["name"]]["wb97x_dE_red_eV"]
        assert p["functional_eV"] == p["wb97x_631gd_eV"] - p["b3lyp_631gd_eV"]
        assert p["basis_eV"] == p["wb97x_def2tzvp_eV"] - p["wb97x_631gd_eV"]
        assert p["geometry_max_dev_A"] <= 1e-3, f"{p['name']}: 34b chloro is not the series geometry"
    lo, hi = cd["points"][0], cd["points"][-1]
    for tier, s in cd["local_slope_eV_per_sigma"].items():
        assert math.isclose(s, (hi[f"{tier}_eV"] - lo[f"{tier}_eV"]) / (hi["sigma_para"] - lo["sigma_para"]))
    cs = cd["local_slope_eV_per_sigma"]
    assert v["centre_functional_and_basis_pull_opposite_ways"] == (
        (cs["wb97x_631gd"] - cs["b3lyp_631gd"]) * (cs["wb97x_def2tzvp"] - cs["wb97x_631gd"]) < 0)
    # the ends split: this script's own small-basis cache, when it exists
    ends = v["ends_decomposition"]
    assert [p["name"] for p in ends["points"]] == sorted(
        (n for n, c in small.items() if "dE_red_eV" in c and n in rows and ok(c["os3"])),
        key=lambda n: rows[n]["sigma_para"]), "ends points ≠ the accepted small-basis rows"
    assert set(ends["not_compared"]) == {n for n, c in small.items() if "dE_red_eV" in c and n in rows and not ok(c["os3"])}, (
        "ends not_compared ≠ the small-basis rows refused by <S²>")
    for p in ends["points"]:
        assert p["wb97x_631gd_eV"] == small[p["name"]]["dE_red_eV"]
        assert p["functional_eV"] == p["wb97x_631gd_eV"] - rows[p["name"]]["b3lyp_dE_red_eV"]
        assert p["basis_eV"] == rows[p["name"]]["wb97x_dE_red_eV"] - p["wb97x_631gd_eV"]
        assert p["geometry_max_dev_A"] <= 1e-3
    tiers = {p["name"]: p for p in cd["points"] + ends["points"]}
    es = ends["slope_over_common_subset_by_tier"]
    assert (es is None) == (not all(n in tiers for n in v["common_fit_subset"]))
    if es is not None:
        for tier, val in es.items():
            assert math.isclose(val, _ols_slope([tiers[n]["sigma_para"] for n in v["common_fit_subset"]],
                                                [tiers[n][f"{tier}_eV"] for n in v["common_fit_subset"]]), abs_tol=1e-9)
        assert math.isclose(es["wb97x_def2tzvp"], v["slope_wb97x_eV_per_sigma"], abs_tol=1e-9)
        assert math.isclose(es["b3lyp_631gd"], v["slope_b3lyp_eV_per_sigma"], abs_tol=1e-9)


def test_83_solvation_clause_branches_follow_the_numbers():
    """The continuum clause of 83's aqueous verdict on SYNTHETIC numbers. On the real data a revert of the threshold to
    `abs(move) ≥ |excess|/2`, or a role printed whatever the gas share, gives a byte-identical verdict (adversary,
    2026-10-12), so the pinned verdict alone cannot hold the branches.
    CAN catch: a move AWAY from the measured counted as closing; a variant toward it not counted; «attenuates» printed
    for a continuum that amplifies; a divide by a zero excess; the reach branch still asserting «nor the continuum».
    CANNOT catch: whether «half the excess» is the right threshold (it is ours)."""
    import importlib.util
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    spec = importlib.util.spec_from_file_location("s83", Path(__file__).parents[1] / "scripts" / "83_os_series_vs_measured.py")
    s83 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(s83)

    def aq(excess, ief, uff, gas, ours=-23.6):
        sc = {"ome_dmbpy_excess_mV": excess, **{k: {"ome_dmbpy_change_mV": m} for k, m in
                                                (("iefpcm", ief), ("uffcavity", uff), ("gas", gas))}}
        return {"solvation_check": sc, "pairs": [{"x": "ome", "ref": "dmbpy", "ours_mV": ours}]}

    real = s83._solvation_clause(aq(16.1, 0.1, -1.1, -29.0))
    assert real.startswith("nor the continuum") and "attenuates the pair by 29.0 mV" in real and "Left untested" in real
    toward = s83._solvation_clause(aq(16.1, 0.1, -9.0, -29.0))
    assert "UFF ×1.1 cavity radii move it toward the measured" in toward and "stays a candidate" in toward
    assert not toward.startswith("nor"), "the reach branch must not deny the continuum"
    away = s83._solvation_clause(aq(16.1, 0.1, +9.0, -29.0))
    assert away.startswith("nor the continuum"), "a move AWAY from the measured counted as closing"
    assert "amplifies the pair by 5.0 mV" in s83._solvation_clause(aq(16.1, 0.1, -1.1, +5.0))
    assert "toward the measured" in s83._solvation_clause(aq(-16.1, 9.0, 0.0, -29.0))   # the other sign of the excess
    assert "no part of the protocol" in s83._solvation_clause(aq(0.0, 0.1, -1.1, -29.0))
    held = aq(16.1, 0.1, -1.1, -29.0) | {"axial_check": {"ome_dmbpy_change_mV": -2.0}}
    txt = s83._solvation_clause(held)
    assert "Nor the axial N-donor" in txt and "A1′ holds" in txt and "(under A2′)" in txt and "A1′–A2′" not in txt
    failed = aq(16.1, 0.1, -1.1, -29.0) | {"axial_check": {"ome_dmbpy_change_mV": -9.0}}
    assert "A1′ does not hold" in s83._solvation_clause(failed)
    away = aq(16.1, 0.1, -1.1, -29.0) | {"axial_check": {"ome_dmbpy_change_mV": +9.0}}
    assert "A1′ holds" in s83._solvation_clause(away), "a move AWAY counted as the axial donor closing the gap"
    held_ax = {"axial_check": {"ome_dmbpy_change_mV": -2.0}}
    kept = s83._solvation_clause(aq(16.1, 0.1, -1.1, -29.0) | held_ax | {"relaxation_check": {"ome_dmbpy_change_mV": -3.0}})
    assert "Nor the Os(II) geometry" in kept and "the Os(III) state's own relaxation" in kept
    assert "programmatic geometry against optimised" not in kept, "a relaxed geometry still listed as untested"
    closed = s83._solvation_clause(aq(16.1, 0.1, -1.1, -29.0) | held_ax | {"relaxation_check": {"ome_dmbpy_change_mV": -9.0}})
    assert "toward the measured" in closed and "Left untested" in closed and "the Os(III) state's own relaxation" in closed
    assert "carries the excess" not in closed, "one pair of one series named the geometry as THE carrier"
    away = aq(16.1, 0.1, -1.1, -29.0) | held_ax | {"relaxation_check": {"ome_dmbpy_change_mV": +9.0}}
    assert "Nor the Os(II) geometry" in s83._solvation_clause(away), "a move AWAY counted as the geometry closing the gap"
    assert "programmatic geometry against optimised" in txt, "without a relaxation the geometry must stay untested"
    # (3б): the Os(III) step is judged against where the pair stood with Os(III) vertical, not against the old excess
    base = aq(16.1, 0.1, -1.1, -29.0) | held_ax | {"relaxation_check": {"ome_dmbpy_change_mV": -18.2}}
    base["pairs"][0]["measured_mV"] = -39.8

    def os3(rel, adi):
        return base | {"os3_relaxation_check": {"ome_dmbpy_change_mV": adi - rel, "ome_dmbpy_relaxed_os2_mV": rel,
                                                "ome_dmbpy_adiabatic_mV": adi}}

    away3 = s83._solvation_clause(os3(-41.9, -43.7))
    assert "— away from the measured" in away3 and "Left untested (under A2′): free energies," in away3
    assert "the Os(III) state's own relaxation" not in away3, "a relaxed Os(III) still listed as untested"
    assert "— toward the measured" in s83._solvation_clause(os3(-41.9, -40.5)), "a move toward the measured read as away"
    assert "— toward the measured" in s83._solvation_clause(os3(-36.0, -38.0)), "toward from the other side read as away"


def test_os_series_vs_measured_is_derived_from_its_sources():
    """① ⊥ measured (script 83, 2026-10-11): every field follows from the transcription and the series caches, and the
    verdict equals the one `83.verdict()` builds from those fields — compared WHOLE, so no printed number escapes.

    CAN catch: a cache whose transcription no longer equals the script's (a fix in the script without a re-run), a σ
    that is not 21e's or the script's tBu value, a shift, per-substituent value (6 measured, 4 computed), slope or r²
    that does not follow from the rows, a matched reading not tied to its measured reading, a missing or extra ratio, a
    fit set other than the series cache's, and a verdict that differs from the one the fields produce. CANNOT catch: a
    transcription error against the PDF (the source is not in the tree), nor whether assumptions A1–A4 hold.
    """
    import importlib.util
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import HARTREE_TO_EV

    spec = importlib.util.spec_from_file_location("s83", Path(__file__).parents[1] / "scripts" / "83_os_series_vs_measured.py")
    s83 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(s83)   # top level imports lib.constants only; 21e is loaded inside main()
    v = json.loads((DFT / "os_series_vs_measured.json").read_text())
    series = json.loads((DFT / "os_mediator_series.json").read_text())
    b3 = {c["name"]: c for c in series["complexes"]}
    m = v["measured"]
    assert {n: r["E12_V"] for n, r in m.items()} == {n: e for n, (e, _) in s83.MEASURED_E12_V.items()}, "transcription ≠ script"
    for n, row in m.items():
        assert row["sigma_para"] == (s83.SIGMA_P_TBU if n == "dtbbpy" else b3[n]["sigma_para"]), n
        assert row["shift_V"] == row["E12_V"] - m["bpy"]["E12_V"], n
        assert row["shift_per_substituent_V"] == row["shift_V"] / 6, n
    for n in ("dmbpy", "ome"):
        row = v["computed"]["b3lyp_631gd"][n]
        assert row["shift_V"] == -(b3[n]["dE_red_eV"] - b3["bpy"]["dE_red_eV"]), n
        assert row["shift_per_substituent_V"] == row["shift_V"] / 4, n
    cen = {}
    for n, f in (("dmbpy", "os_complex_wb97xd_dmbpy.json"), ("bpy", "os_complex_wb97xd.json")):
        w = json.loads((DFT / f).read_text())
        cen[n] = (w["os2_plus"]["E_total_Ha"] - w["os3_plus"]["E_total_Ha"]) * HARTREE_TO_EV
    wrow = v["computed"]["wb97x_def2tzvp"]["dmbpy"]
    assert wrow["shift_V"] == -(cen["dmbpy"] - cen["bpy"]) and wrow["shift_per_substituent_V"] == wrow["shift_V"] / 4
    ratios = v["ratio_computed_over_measured_per_substituent"]
    assert set(ratios) == {"b3lyp_631gd:dmbpy", "b3lyp_631gd:ome", "wb97x_def2tzvp:dmbpy"}
    for key, ratio in ratios.items():
        tier, n = key.split(":")
        assert ratio == v["computed"][tier][n]["shift_per_substituent_V"] / m[n]["shift_per_substituent_V"], key
    for label, rd in v["measured_readings"].items():
        slope, r2 = s83._slope_r2([m[n]["sigma_para"] for n in rd["points"]], [m[n]["E12_V"] for n in rd["points"]])
        assert (rd["slope_V_per_sigma"], rd["r2"], rd["per_substituent_V_per_sigma"]) == (slope, r2, slope / 6), label
    ms = v["matched_slope"]
    mr = v["measured_readings"]["matched"]
    assert ms["points"] == mr["points"] and (ms["measured_per_substituent_V_per_sigma"], ms["measured_r2"]) == (
        mr["per_substituent_V_per_sigma"], mr["r2"])
    cslope, cr2 = s83._slope_r2([m[n]["sigma_para"] for n in ms["points"]],
                                [-(b3[n]["dE_red_eV"] - b3["bpy"]["dE_red_eV"]) for n in ms["points"]])
    assert (ms["computed_b3lyp_per_substituent_V_per_sigma"], ms["computed_b3lyp_r2"]) == (cslope / 4, cr2)
    assert ms["ratio_computed_over_measured"] == ms["computed_b3lyp_per_substituent_V_per_sigma"] / ms["measured_per_substituent_V_per_sigma"]
    fit = series["lfer"]["fit_set"]
    assert v["computed_lfer_fit_set"] == fit
    lslope, _ = s83._slope_r2([b3[n]["sigma_para"] for n in fit], [b3[n]["dE_red_eV"] for n in fit])
    assert v["computed_lfer_per_substituent_V_per_sigma"] == -lslope / 4
    assert v["verdict"] == s83.verdict(v), "the verdict is not the one its fields build"
    # the aqueous series of our own core (Langmuir 2026): differences to Me, 4 substituents on both sides, one acceptor
    aq = v["aqueous_series"]
    am, ref = aq["measured"], s83.AQ_REF
    assert {n: r["E12_V"] for n, r in am.items()} == {n: e for n, (e, _) in s83.AQ_MEASURED_E12_V.items()}, "aqueous transcription ≠ script"
    for n, row in am.items():
        assert row["sigma_para"] == b3[n]["sigma_para"] and row["shift_V"] == row["E12_V"] - am[ref]["E12_V"], n
        assert row["shift_per_substituent_V"] == row["shift_V"] / 4, n
        crow = aq["computed_b3lyp"][n]
        assert crow["shift_V"] == -(b3[n]["dE_red_eV"] - b3[ref]["dE_red_eV"]) and crow["shift_per_substituent_V"] == crow["shift_V"] / 4, n
    assert set(aq["ratio_computed_over_measured_per_substituent"]) == set(am) - {ref}
    for n, ratio in aq["ratio_computed_over_measured_per_substituent"].items():
        assert ratio == aq["computed_b3lyp"][n]["shift_per_substituent_V"] / am[n]["shift_per_substituent_V"], n
    sl = aq["slope"]
    xs = [am[n]["sigma_para"] for n in sl["points"]]
    cs, cr = s83._slope_r2(xs, [aq["computed_b3lyp"][n]["shift_V"] for n in sl["points"]])
    ms_, mr_ = s83._slope_r2(xs, [am[n]["shift_V"] for n in sl["points"]])
    assert sorted(sl["points"], key=lambda n: am[n]["sigma_para"]) == sl["points"] and set(sl["points"]) == set(am)
    assert (sl["computed_b3lyp_per_substituent_V_per_sigma"], sl["computed_b3lyp_r2"]) == (cs / 4, cr)
    assert (sl["measured_per_substituent_V_per_sigma"], sl["measured_r2"], sl["ratio_computed_over_measured"]) == (ms_ / 4, mr_, cs / ms_)
    assert aq["source_dft_E12_V"] == s83.AQ_SOURCE_DFT_E12_V, "the source's computed E1/2 ≠ the script's transcription"
    assert [(p["x"], p["ref"]) for p in aq["pairs"]] == list(s83.AQ_PAIRS)
    ours = {n: -b3[n]["dE_red_eV"] for n in am}
    for p in aq["pairs"]:
        x, r_ = p["x"], p["ref"]
        assert p["measured_mV"] == (am[x]["E12_V"] - am[r_]["E12_V"]) / 4 * 1000, (x, r_)
        assert p["ours_mV"] == (ours[x] - ours[r_]) / 4 * 1000, (x, r_)
        assert p["source_dft_mV"] == (s83.AQ_SOURCE_DFT_E12_V[x] - s83.AQ_SOURCE_DFT_E12_V[r_]) / 4 * 1000, (x, r_)
        assert (p["ours_over_measured"], p["source_dft_over_measured"]) == (p["ours_mV"] / p["measured_mV"], p["source_dft_mV"] / p["measured_mV"])
    pw = aq["measured_pairwise_slope_per_substituent_V_per_sigma"]
    for a, b in (("ome", "dmbpy"), ("dmbpy", "cl")):
        assert pw[f"{a}-{b}"] == (am[b]["E12_V"] - am[a]["E12_V"]) / (am[b]["sigma_para"] - am[a]["sigma_para"]) / 4
    osd = DFT / "os_mediator_series_osdef2.json"
    assert ("os_basis_check" in aq) == osd.exists(), "the Os-basis check is in the block iff its cache exists"
    if osd.exists():
        vl = json.loads(osd.read_text())["vs_lanl2dz"]
        ob = aq["os_basis_check"]
        assert ob["max_pair_change_mV"] == max(abs(p["change_mV"]) for p in vl["pairs"]) and ob["pairs"] == len(vl["pairs"])
        assert ob["point_shift_meV"] == [min(vl["point_shift_eV"].values()) * 1000, max(vl["point_shift_eV"].values()) * 1000]
    # the continuum variants (21e `b3lyp-iefpcm` · `b3lyp-uffcavity` · `b3lyp-gas`): in the block iff a finished cache exists
    done = {k: json.loads((DFT / f).read_text())["vs_series"] for k, f, _ in s83.SOLVATION_VARIANTS
            if (DFT / f).exists() and "vs_series" in json.loads((DFT / f).read_text())}
    assert ("solvation_check" in aq) == bool(done), "the continuum check is in the block iff a finished variant cache exists"
    if done:
        sc = aq["solvation_check"]
        meas = {(p["x"], p["ref"]): p["measured_mV"] for p in aq["pairs"]}
        om = next(p for p in aq["pairs"] if (p["x"], p["ref"]) == ("ome", "dmbpy"))
        assert sc["ome_dmbpy_excess_mV"] == om["ours_mV"] - om["measured_mV"] and set(sc) == {"ome_dmbpy_excess_mV", *done}
        for k, vs in done.items():
            by = {(p["x"], p["ref"]): p for p in vs["pairs"]}
            assert sc[k]["max_pair_change_mV"] == max(abs(p["change_mV"]) for p in vs["pairs"]) and sc[k]["pairs"] == len(vs["pairs"]), k
            assert sc[k]["ome_dmbpy_change_mV"] == by[("ome", "dmbpy")]["change_mV"], k
            assert sc[k]["aqueous_pairs_over_measured"] == {f"{x}-{r_}": by[(x, r_)]["variant_mV"] / meas[(x, r_)]
                                                            for x, r_ in s83.AQ_PAIRS}, k
    axp = DFT / s83.AXIAL_VARIANT[1]   # 21e `b3lyp-pyaxial`: in the block iff its cache is finished
    axv = json.loads(axp.read_text()).get("vs_series") if axp.exists() else None
    assert ("axial_check" in aq) == bool(axv), "the axial check is in the block iff its finished cache exists"
    if axv:
        by = {(p["x"], p["ref"]): p for p in axv["pairs"]}
        ax = aq["axial_check"]
        assert ax["ome_dmbpy_change_mV"] == by[("ome", "dmbpy")]["change_mV"] and ax["pairs"] == len(axv["pairs"])
        assert ax["max_pair_change_mV"] == max(abs(p["change_mV"]) for p in axv["pairs"])
    assert aq["verdict"] == s83.verdict_aqueous(aq), "the aqueous verdict is not the one its fields build"
    # paper ref 8's series (Zafar 2012 Table 1, polymers b, c, d, f at loading 1:9): pairs, pairwise slopes, the loading control
    pv = v["pvi_series"]
    pm = {n: r["E_V"] for n, r in pv["measured_E_V"].items()}
    assert pm == {n: e for n, (e, _) in s83.PVI_MEASURED_E_V.items()}, "PVI transcription ≠ script"
    assert all(r["sigma_para"] == b3[n]["sigma_para"] for n, r in pv["measured_E_V"].items())
    assert [(p["x"], p["ref"]) for p in pv["pairs"]] == list(s83.PVI_PAIRS)
    for p in pv["pairs"]:
        x, r_ = p["x"], p["ref"]
        assert p["measured_mV"] == (pm[x] - pm[r_]) / 4 * 1000 and p["ours_mV"] == (-b3[x]["dE_red_eV"] + b3[r_]["dE_red_eV"]) / 4 * 1000, (x, r_)
        assert p["ours_over_measured"] == p["ours_mV"] / p["measured_mV"], (x, r_)
    order = sorted(pm, key=lambda n: b3[n]["sigma_para"])
    assert list(pv["pairwise_slope_per_substituent_V_per_sigma"]) == [f"{a}-{b}" for a, b in itertools.pairwise(order)]
    for a, b in itertools.pairwise(order):
        sl = pv["pairwise_slope_per_substituent_V_per_sigma"][f"{a}-{b}"]
        ds = b3[b]["sigma_para"] - b3[a]["sigma_para"]
        assert sl["measured"] == (pm[b] - pm[a]) / ds / 4 and sl["ours"] == (-b3[b]["dE_red_eV"] + b3[a]["dE_red_eV"]) / ds / 4, (a, b)
    lc = pv["loading_control"]
    assert lc["shift_mV"] == (lc["loading_1_11_V"] - lc["loading_1_9_V"]) * 1000 and lc["loading_1_9_V"] == pm["dmbpy"]
    assert lc["shift_mV"] > abs(pm["bpy"] - pm["dmbpy"]) * 1000, "the prose says the loading effect exceeds all four Me → H"
    assert pv["verdict"] == s83.verdict_pvi(pv), "the PVI verdict is not the one its fields build"
    # the geometry relaxation across the series (21e `b3lyp-relaxed-os2`, and `b3lyp-relaxed-os3` once every point has landed)
    o3 = s83._adiabatic()
    assert ("os3_relaxation_check" in aq) == bool(o3 and "relaxation_check" in aq), "the Os(III) check is in the block iff (3б) is whole"
    if "os3_relaxation_check" in aq:
        p3 = next(p for p in o3["pairs"] if (p["x"], p["ref"]) == ("ome", "dmbpy"))
        assert aq["os3_relaxation_check"] == {"ome_dmbpy_change_mV": p3["change_mV"], "ome_dmbpy_relaxed_os2_mV": p3["relaxed_os2_mV"],
                                              "ome_dmbpy_adiabatic_mV": p3["adiabatic_mV"]}
    rg = v.get("relaxed_geometry_check")
    if rg:
        assert rg["verdict"] == s83.verdict_relaxed(rg), "the (3а) verdict is not the one its fields build"
        assert ("adiabatic" in rg) == bool(o3), "the (3б) reading is in the block iff (3б) is whole"
    if rg and o3:
        ad = rg["adiabatic"]
        assert ad["verdict"] == s83.verdict_adiabatic(ad), "the (3б) verdict is not the one its fields build"
        rx = json.loads((DFT / s83.RELAX_VARIANT[1]).read_text())["complexes"]
        both = [n for n in rx if "dE_red_eV" in rx[n] and "dE_red_adiabatic_eV" in o3["complexes"].get(n, {})]   # one state: skipped
        e = {"series": {n: b3[n]["dE_red_eV"] for n in both}, "relaxed": {n: rx[n]["dE_red_eV"] for n in both},
             "adiabatic": {n: o3["complexes"][n]["dE_red_adiabatic_eV"] for n in both}}
        landed = sorted((n for n in both if n not in ("ome", "dmbpy", "bpy")), key=lambda n: b3[n]["sigma_para"])
        assert rg["acceptors_relaxed"] == landed, "83 not re-run since a point beyond the donors landed in both 21e caches"
        assert ("acceptors" in rg) == bool(landed), "the acceptor block is in 83 iff a point beyond the donors has both rows"
        assert rg["not_relaxed"] == ad["not_relaxed"] == sorted((n for n in b3 if n not in {"ome", "dmbpy", "bpy", *landed}),
                                                                key=lambda n: b3[n]["sigma_para"])
        meas = {"ref 8": lambda x, r_: (pm[x] - pm[r_]) / 4, "MeCN": lambda x, r_: m[x]["shift_per_substituent_V"],
                "aqueous": lambda x, r_: (am[x]["E12_V"] - am[r_]["E12_V"]) / 4}
        assert [(p["series_name"], p["pair"]) for p in ad["pairs_vs_measured"]] == [
            ("ref 8", "ome-bpy"), ("ref 8", "dmbpy-bpy"), ("ref 8", "ome-dmbpy"), ("aqueous", "ome-dmbpy"),
            ("MeCN", "ome-bpy"), ("MeCN", "dmbpy-bpy")], "the shared donor pairs are not the six the series share"
        for p in ad["pairs_vs_measured"]:
            x, r_ = p["pair"].split("-")
            assert p["measured_mV"] == meas[p["series_name"]](x, r_) * 1000, p
            for t in ("series", "relaxed", "adiabatic"):
                assert p[f"{t}_mV"] == -(e[t][x] - e[t][r_]) / 4 * 1000 and p[f"{t}_gap_mV"] == abs(p[f"{t}_mV"] - p["measured_mV"]), (p, t)
        for t in ("series", "relaxed"):
            assert ad[f"closer_than_{t}"] == sum(p["adiabatic_gap_mV"] < p[f"{t}_gap_mV"] for p in ad["pairs_vs_measured"]), t
        donors = sorted(s83.DONORS, key=lambda n: b3[n]["sigma_para"])   # the (3б) block stays on the donor set as acceptors land
        assert sorted(ad["koopmans_cascade_delta_eV"], key=lambda n: b3[n]["sigma_para"]) == donors, "the (3б) block is not the donor set"
        assert ad["point_shift_from_series_meV"] == {n: o3["point_shift_eV"][n] * 1000 for n in donors}, \
            "an acceptor's point entered the donor block"
        for k, mv in ad["pair_move_from_series_mV"].items():
            x, r_ = k.split("-")
            assert mv == (-(e["adiabatic"][x] - e["adiabatic"][r_]) / 4 + (e["series"][x] - e["series"][r_]) / 4) * 1000, k
        homo = json.loads((DFT / "lumiflavin.json").read_text())["red"]["HOMO_eV"]   # 21e's cascade source
        for n, c in ad["koopmans_cascade_delta_eV"].items():   # Δ = HOMO(FADH₂) − LUMO(Os III), from unrounded LUMOs
            assert c == {"programmatic": homo - b3[n]["os3"]["LUMO_eV"], "os3_on_os2_minimum": homo - rx[n]["os3"]["LUMO_eV"],
                         "os3_on_own_minimum": homo - o3["complexes"][n]["os3"]["LUMO_eV"]}, n
            assert math.isclose(c["programmatic"], b3[n]["cascade_delta_eV"], abs_tol=5e-5), (n, "≠ Table 4's rounded column")
            assert ad["koopmans_cascade_delta_move_eV"][n] == {k: c[k] - c["programmatic"]
                                                               for k in ("os3_on_os2_minimum", "os3_on_own_minimum")}, n
        pts = sorted(ad["koopmans_cascade_delta_eV"], key=lambda n: b3[n]["sigma_para"])
        for g, gp in ad["koopmans_neighbour_gap_eV"].items():
            cc = {n: ad["koopmans_cascade_delta_eV"][n][g] for n in pts}
            assert gp == {f"{a}-{b}": cc[b] - cc[a] for a, b in itertools.pairwise(pts)}, g
            assert ad["koopmans_monotonic_in_sigma"][g] == all(v > 0 for v in gp.values()), g
        every = sorted(b3, key=lambda n: b3[n]["sigma_para"])
        relaxed = {*pts, *rg["acceptors_relaxed"]}   # a pair with both members relaxed is read, not «unrelaxed»
        assert ad["unrelaxed_neighbour_gap_meV"] == {f"{a}-{b}": (b3[a]["os3"]["LUMO_eV"] - b3[b]["os3"]["LUMO_eV"]) * 1000
                                                     for a, b in itertools.pairwise(every) if not (a in relaxed and b in relaxed)}
        assert ad["lambda_os3_meV"] == {n: o3["lambda_os3_meV"][n] for n in pts}, "an acceptor's λ entered the donor block"
        for k, cp in ad["computed_pairs"].items():   # each computed pair: its two moves and the series it nears or leaves
            x, r_ = k.split("-")
            rows = [p for p in ad["pairs_vs_measured"] if p["pair"] == k]
            for base in ("series", "relaxed"):
                assert cp[f"move_from_{base}_mV"] == (-(e["adiabatic"][x] - e["adiabatic"][r_]) / 4
                                                      + (e[base][x] - e[base][r_]) / 4) * 1000, (k, base)
                assert cp[f"closer_than_{base}"] == [p["series_name"] for p in rows if p["adiabatic_gap_mV"] < p[f"{base}_gap_mV"]]
                assert cp[f"away_than_{base}"] == [p["series_name"] for p in rows if not p["adiabatic_gap_mV"] < p[f"{base}_gap_mV"]]
        assert set(ad["computed_pairs"]) == {p["pair"] for p in ad["pairs_vs_measured"]}
        fit = series["lfer"]["fit_set"]
        ls, _ = s83._slope_r2([b3[n]["sigma_para"] for n in fit], [b3[n]["dE_red_eV"] for n in fit])
        assert ad["lfer_span_eV"] == abs(ls) * (max(b3[n]["sigma_para"] for n in fit) - min(b3[n]["sigma_para"] for n in fit))
        dsl = rg["donor_slope_per_substituent_V_per_sigma"]
        assert ad["donor_slope_change"] == dsl["adiabatic"] / dsl["series"] - 1
        dt = ad["d_first_trigger"]
        reach = {"substituent_pairs_per_complex": max(abs(mv) for mv in ad["pair_move_from_series_mV"].values()) * 4 / 1000,
                 "points": max(abs(o3["point_shift_eV"][n]) for n in pts),
                 "koopmans_cascade_delta": max(abs(x) for c in ad["koopmans_cascade_delta_move_eV"].values() for x in c.values())}
        assert dt["threshold_eV"] == s83.D_FIRST_TRIGGER_EV == 0.1, "D's first trigger is 0.1 eV (PIPELINE_STATUS «D»)"
        assert all(math.isclose(dt["largest_move_eV"][k], val, rel_tol=1e-12) for k, val in reach.items())
        assert set(dt["largest_move_eV"]) == set(reach)
        assert dt["at_or_above"] == sorted(k for k, val in dt["largest_move_eV"].items() if val >= 0.1)
        assert dt["extrapolated_eV"] == {"slope_1_over_lfer_span": abs(ad["donor_slope_change"]) * ad["lfer_span_eV"]}
        assert dt["extrapolated_at_or_above"] == sorted(k for k, val in dt["extrapolated_eV"].items() if val >= 0.1)
        if "acceptors" in rg:   # the committed acceptor block is the one the committed caches build — never adjusted by hand
            fit = series["lfer"]["fit_set"]
            ac = s83.acceptor_reading(rg["acceptors_relaxed"], {n: c["sigma_para"] for n, c in b3.items()}, b3, rx, o3, fit,
                                      lambda e_, x, r_: -(e_[x] - e_[r_]) / 4)
            assert ac == rg["acceptors"], "the acceptor block is not the one the caches build"
            for n, c in rg["acceptors"]["koopmans_cascade_delta_eV"].items():
                assert math.isclose(c["programmatic"], b3[n]["cascade_delta_eV"], abs_tol=5e-5), (n, "≠ Table 4's rounded column")
        assert "is D's to judge" in ad["verdict"] and "an extrapolation, not a computation" in ad["verdict"], \
            "a difference at D's threshold is reported as the script's judgement, or the extrapolation as a computation"


def test_83_acceptor_reading_is_declared_before_the_data(tmp_path, monkeypatch):
    """`83` on caches that hold relaxed points beyond the donors (⚖️ 2026-10-14: Cl, then NO₂) — synthetic rows in a copy
    of the DFT cache, their comparisons rebuilt by 21e's own `_vs_series` / `_vs_vertical` (the state the run writes),
    `83` run end to end. The reading and the verdict's condition are declared before Cl's real numbers land.
    CAN catch: a donor or aqueous number that moves when a point lands (the pins stand on them); a crash on the MeCN
    series, which has no acceptor; a point read with one state only; a pair, cascade, neighbour order or slope not
    rebuilt from the caches; a verdict not the one its block builds; a condition that fires without a flip or a move
    ≥ 0.1 eV, misses either alone, or says «not met» while a close pair is half-relaxed; a threshold or rule changed after
    the data. CANNOT catch: what the real relaxation returns."""
    pytest.importorskip("rdkit")
    import importlib.util
    import shutil
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import HARTREE_TO_EV
    spec = importlib.util.spec_from_file_location("s83", Path(__file__).parents[1] / "scripts" / "83_os_series_vs_measured.py")
    s83 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(s83)
    m21 = _load_21e()
    real = json.loads((DFT / "os_series_vs_measured.json").read_text())
    b3 = {c["name"]: c for c in json.loads((DFT / "os_mediator_series.json").read_text())["complexes"]}
    assert s83.D_FIRST_TRIGGER_EV == 0.1 and s83.CLOSE_NEIGHBOUR_MEV == 100.0, "a threshold changed after it was declared"

    def run(points: dict):   # name → (ΔE Os(II), ΔE vertical Os(III), ΔE own Os(III) [Ha], LUMO up on own minimum [eV])
        d = tmp_path / "dft"
        shutil.rmtree(d, ignore_errors=True)
        shutil.copytree(DFT, d)
        r2 = json.loads((d / "os_mediator_series_relaxed_os2.json").read_text())
        r3 = json.loads((d / "os_mediator_series_relaxed_os3.json").read_text())
        g2 = r2["complexes"].get("cl", r2["complexes"]["bpy"])["geometry_os2_relaxed"]   # the producer writes a geometry per point;
        g3 = r3["complexes"].get("cl", r3["complexes"]["bpy"])["geometry_os3_relaxed"]   # 83 reads its Os–Cl
        for r in (r2, r3):   # each case starts from the donor set alone: an acceptor already landed in the caches must not join it
            r["complexes"] = {n: c for n, c in r["complexes"].items() if n in s83.DONORS}
        for n, (d2, dv, d3, up) in points.items():   # d3 None — the point has only its Os(II) row, as mid-run
            e2, e3 = b3[n]["os2"]["E_total_Ha"] + d2, b3[n]["os3"]["E_total_Ha"] + dv
            r2["complexes"][n] = {"sigma_para": b3[n]["sigma_para"], "os2": {"E_total_Ha": e2}, "geometry_os2_relaxed": g2,
                                  "os3": {"E_total_Ha": e3, "LUMO_eV": b3[n]["os3"]["LUMO_eV"] - up / 2},   # the donors' pattern:
                                  # the cascade rises with Os(III) vertical on the Os(II) minimum, falls on its own
                                  "dE_red_eV": (e2 - e3) * HARTREE_TO_EV}
            if d3 is None:
                continue
            own = e3 + d3
            r3["complexes"][n] = {"sigma_para": b3[n]["sigma_para"], "os2_E_Ha": e2, "os3_vertical_E_Ha": e3,
                                  "geometry_os3_relaxed": g3,
                                  "dE_red_vertical_eV": (e2 - e3) * HARTREE_TO_EV,
                                  "os3": {"E_total_Ha": own, "LUMO_eV": b3[n]["os3"]["LUMO_eV"] + up},
                                  "dE_red_adiabatic_eV": (e2 - own) * HARTREE_TO_EV,
                                  "lambda_os3_meV": (e3 - own) * HARTREE_TO_EV * 1000}
        r2["vs_series"] = m21._vs_series(r2, "b3lyp-relaxed-os2")   # the comparisons the run itself rebuilds
        r3["vs_vertical"] = m21._vs_vertical(r3)
        (d / "os_mediator_series_relaxed_os2.json").write_text(json.dumps(r2))
        (d / "os_mediator_series_relaxed_os3.json").write_text(json.dumps(r3))
        monkeypatch.setattr(s83, "DFT_CACHE", d)
        monkeypatch.setattr(s83, "OUT", d / "os_series_vs_measured.json")
        s83.main()
        v = json.loads((d / "os_series_vs_measured.json").read_text())
        return v, v["relaxed_geometry_check"], r2, r3

    small = (-2e-4, -1e-4, -2e-4)
    v, rg, r2, r3 = run({"cl": (-2e-3, -1e-3, -3e-3, 0.05), "no2": (-3e-3, -2e-3, -5e-3, 0.03)})
    prose = {"acceptors", "acceptors_relaxed", "not_relaxed", "verdict", "adiabatic"}
    for k in [k for k in real["relaxed_geometry_check"] if k not in prose]:
        assert rg[k] == real["relaxed_geometry_check"][k], f"the donor reading moved when acceptors landed: {k}"
    for k in [k for k in real["relaxed_geometry_check"]["adiabatic"] if k not in {"verdict", "not_relaxed", "unrelaxed_neighbour_gap_meV"}]:
        assert rg["adiabatic"][k] == real["relaxed_geometry_check"]["adiabatic"][k], f"the (3б) donor reading moved: {k}"
    assert v["aqueous_series"] == real["aqueous_series"], "the aqueous block moved when acceptors landed"
    assert v["verdict"] == real["verdict"] and v["pvi_series"] == real["pvi_series"]
    assert rg["acceptors_relaxed"] == ["cl", "no2"] and not {"cl", "no2"} & set(rg["not_relaxed"])
    assert rg["verdict"] == s83.verdict_relaxed(rg) and "the acceptor block" in rg["verdict"]
    assert rg["adiabatic"]["verdict"] == s83.verdict_adiabatic(rg["adiabatic"])
    ac = rg["acceptors"]
    assert ac["members"] == ["ome", "dmbpy", "bpy", "cl", "no2"]
    assert [(p["series_name"], p["pair"]) for p in ac["pairs_vs_measured"]] == [
        ("ref 8", "cl-bpy"), ("ref 8", "cl-dmbpy"), ("ref 8", "cl-ome"), ("aqueous", "cl-dmbpy"), ("aqueous", "cl-ome")]
    e = {"series": {n: b3[n]["dE_red_eV"] for n in ac["members"]},
         "relaxed": {n: r2["complexes"][n]["dE_red_eV"] for n in ac["members"]},
         "adiabatic": {n: r3["complexes"][n]["dE_red_adiabatic_eV"] for n in ac["members"]}}
    for p in ac["pairs_vs_measured"]:
        x, r_ = p["pair"].split("-")
        for col in ("series", "relaxed", "adiabatic"):
            assert p[f"{col}_mV"] == -(e[col][x] - e[col][r_]) / 4 * 1000, (p, col)
    homo = json.loads((DFT / "lumiflavin.json").read_text())["red"]["HOMO_eV"]
    for n in ac["members"]:
        assert ac["koopmans_cascade_delta_eV"][n]["os3_on_own_minimum"] == homo - r3["complexes"][n]["os3"]["LUMO_eV"], n
    assert set(ac["table4_neighbours_both_relaxed"]) == {"ome-dmbpy", "dmbpy-bpy", "bpy-cl"}
    assert set(ac["table4_neighbours_half_relaxed"]) == {"nh2-ome", "cl-dcbpy", "cf3-no2", "no2-so2cf3"}
    assert ac["slopes"]["slope_1_relaxed_fit_members"]["members"] == ["ome", "dmbpy", "bpy", "no2"]
    assert not ac["slopes"]["slope_1_relaxed_fit_members"]["complete"], "COOH is in the fit set, not relaxed"
    assert ac["slopes"]["slope_me_h_no2"]["members"] == ["dmbpy", "bpy", "no2"]
    vc = ac["verdict_condition"]
    moves = [p["move_from_series_mV"] for p in ac["computed_pairs"].values()]
    reach = {"acceptor_pairs_per_complex": max(abs(x) for x in moves) * 4 / 1000,
             "acceptor_koopmans_cascade_delta": max(abs(x) for c in ac["koopmans_own_move_eV"].values() for x in c.values()),
             "neighbour_gap_moves": max(v_["gap_move_meV"] for v_ in ac["table4_neighbours_both_relaxed"].values()
                                        if v_["touches_beyond_donors"]) / 1000,
             **{k: s_["move_over_span_eV"] for k, s_ in ac["slopes"].items()}}
    assert vc["largest_move_eV"] == reach, "the counted differences changed"
    assert vc["rule"].startswith("⚖️ founder 2026-10-14") and vc["threshold_eV"] == 0.1
    assert "no2-so2cf3" in vc["not_decidable_pairs"], "the 5 meV pair half-relaxed is not flagged"
    assert ac["verdict"] == s83.verdict_acceptors(ac)
    # the four states, each reached alone
    v, rg, *_ = run({"no2": (*small, 0.0), "so2cf3": (*small, 0.02)})   # a flip by moves far under 0.1 eV
    vc = rg["acceptors"]["verdict_condition"]
    assert vc["neighbour_order_flipped"] == ["no2-so2cf3"] and vc["at_or_above"] == [] and vc["state"] == "met", vc
    v, rg, *_ = run({"no2": (*small, 0.0), "so2cf3": (*small, 0.0)})    # both relaxed, nothing moves: not met
    vc = rg["acceptors"]["verdict_condition"]
    assert vc["state"] == "not met" and "is not met" in rg["acceptors"]["verdict"], vc
    v, rg, *_ = run({"cl": (*small, 0.15)})                               # ≥ 0.1 eV alone, no flip, no close half pair
    vc = rg["acceptors"]["verdict_condition"]
    assert "acceptor_koopmans_cascade_delta" in vc["at_or_above"] and not vc["neighbour_order_flipped"]
    assert not vc["not_decidable_pairs"], "Cl's neighbours are far: nothing close is half-relaxed"
    assert vc["state"] == "met" and "MET" in rg["acceptors"]["verdict"], vc
    v, rg, *_ = run({"no2": (*small, 0.0)})                               # the 5 meV pair half-relaxed: never «not met»
    vc = rg["acceptors"]["verdict_condition"]
    assert vc["state"] == "not decidable" and "NOT DECIDABLE" in rg["acceptors"]["verdict"], vc
    v, rg, *_ = run({"cl": (*small, 0.0), "no2": (-3e-3, -2e-3, None, 0.03)})   # NO₂ with its Os(II) row only, as mid-run
    assert rg["acceptors_relaxed"] == ["cl"] and "no2" in rg["not_relaxed"] and "no2" not in rg["acceptors"]["members"], rg


def test_os_mediator_series_relaxed_os3_is_derived_from_its_rows():
    """21e `b3lyp-relaxed-os3` (leg (3б), landed 2026-10-13): each point's Os(III) accepted at its own minimum, its Os(II)
    side and vertical Os(III) the (3а) cache's own rows, and every derived number from those energies.
    CAN catch: a row whose Os(II) or vertical Os(III) is not the (3а) record it claims (the start moved and the record was
    not discarded), a spin-contaminated, rescued or non-aufbau Os(III), a single point off the optimiser's last step, a
    λ_III or adiabatic ΔE_red not from the rows, and a stale `vs_vertical`. CANNOT catch: what geomeTRIC or a real UKS
    would return, nor which geometry is nearer the real complex (that is `83`)."""
    path = DFT / "os_mediator_series_relaxed_os3.json"
    if not path.exists():
        pytest.skip("21e b3lyp-relaxed-os3 not run")
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import HARTREE_TO_EV, S2_MAX_DOUBLET
    rec = json.loads(path.read_text())
    os2 = json.loads((DFT / "os_mediator_series_relaxed_os2.json").read_text())["complexes"]
    base = {c["name"]: c["dE_red_eV"] for c in json.loads((DFT / "os_mediator_series.json").read_text())["complexes"]}
    ad = {}
    for n, c in rec["complexes"].items():
        if "dE_red_adiabatic_eV" not in c:
            continue
        o3 = c["os3"]
        assert o3["converged"] and o3.get("aufbau") and not o3.get("rescued") and o3["s2"] <= S2_MAX_DOUBLET, n
        assert c["geometry_os3_relaxed"]["info"]["converged"], n
        assert c["os2_E_Ha"] == os2[n]["os2"]["E_total_Ha"] and c["os3_vertical_E_Ha"] == os2[n]["os3"]["E_total_Ha"], n
        assert c["dE_red_vertical_eV"] == os2[n]["dE_red_eV"] and c["sigma_para"] == os2[n]["sigma_para"], n
        assert abs(c["os3_minus_last_step_Ha"]) <= 1e-5, n   # 21e RELAX_ENERGY_TOL_HA
        assert c["os3_minus_last_step_Ha"] == o3["E_total_Ha"] - c["geometry_os3_relaxed"]["info"]["trajectory"][-1]["E_Ha"], n
        assert c["dE_red_adiabatic_eV"] == (c["os2_E_Ha"] - o3["E_total_Ha"]) * HARTREE_TO_EV, n
        assert c["lambda_os3_meV"] == (c["os3_vertical_E_Ha"] - o3["E_total_Ha"]) * HARTREE_TO_EV * 1000 and c["lambda_os3_meV"] > 0, n
        ad[n] = c
    v = rec["vs_vertical"]
    assert v["point_shift_eV"] == {n: c["dE_red_adiabatic_eV"] - base[n] for n, c in ad.items()}
    assert v["lambda_os3_meV"] == {n: c["lambda_os3_meV"] for n, c in ad.items()}
    cols = {"series_mV": base, "relaxed_os2_mV": {n: c["dE_red_vertical_eV"] for n, c in ad.items()},
            "adiabatic_mV": {n: c["dE_red_adiabatic_eV"] for n, c in ad.items()}}
    assert [(p["x"], p["ref"]) for p in v["pairs"]] == [(x, r) for x, r in (("dmbpy", "bpy"), ("ome", "bpy"), ("cl", "bpy"),
                                                                             ("ome", "dmbpy"), ("cl", "dmbpy"), ("cl", "ome"))
                                                        if x in ad and r in ad]
    for p in v["pairs"]:
        x, r = p["x"], p["ref"]
        for k, e in cols.items():
            assert p[k] == -(e[x] - e[r]) / 4 * 1000, (x, r, k)
        assert p["change_mV"] == p["adiabatic_mV"] - p["relaxed_os2_mV"], (x, r)


def test_os_mediator_series_osdef2_is_derived_from_both_caches():
    """21e `b3lyp-osdef2` (2026-10-11): each point accepted (converged, aufbau, <S²> ≤ S2_MAX_DOUBLET), none rescued, its ΔE
    from its own rows, and `vs_lanl2dz` from the two caches — E° shift = −ΔΔE_red per 4 substituents, in mV.
    CAN catch: a stale or hand-edited comparison, an unaccepted row counted, a sign or unit slip. CANNOT catch: whether
    LANL2DZ or def2-TZVP is nearer experiment (that is `83`)."""
    path = DFT / "os_mediator_series_osdef2.json"
    if not path.exists():
        pytest.skip("21e b3lyp-osdef2 not run")
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import HARTREE_TO_EV, S2_MAX_DOUBLET
    rec = json.loads(path.read_text())
    lanl = {c["name"]: c["dE_red_eV"] for c in json.loads((DFT / "os_mediator_series.json").read_text())["complexes"]}
    d2 = {}
    for n, c in rec["complexes"].items():
        o2, o3 = c["os2"], c["os3"]
        assert o2["converged"] and o3["converged"] and o2.get("aufbau") and o3.get("aufbau"), n
        assert o3["s2"] <= S2_MAX_DOUBLET and not o2.get("rescued") and not o3.get("rescued"), n
        assert c["dE_red_eV"] == (o2["E_total_Ha"] - o3["E_total_Ha"]) * HARTREE_TO_EV, n
        d2[n] = c["dE_red_eV"]
    v = rec["vs_lanl2dz"]
    assert v["point_shift_eV"] == {n: d2[n] - lanl[n] for n in d2} and v["rescued_def2_rows"] == []
    for p in v["pairs"]:
        x, r = p["x"], p["ref"]
        assert p["lanl2dz_mV"] == -(lanl[x] - lanl[r]) / 4 * 1000 and p["def2tzvp_mV"] == -(d2[x] - d2[r]) / 4 * 1000, (x, r)
        assert p["change_mV"] == p["def2tzvp_mV"] - p["lanl2dz_mV"], (x, r)


@pytest.mark.parametrize("name", ["iefpcm", "uffcavity", "gas", "relaxed_os2"])
def test_os_mediator_series_continuum_variant_is_derived_from_both_caches(name):
    """21e's one-knob variants — the continuum ones (2026-10-11, 00_07 HW.5.IS leg 2) and the Os(II) geometry
    (`relaxed_os2`, 2026-10-12, acceptors since 2026-10-15): each point accepted (converged, aufbau, <S²> ≤
    S2_MAX_DOUBLET), none rescued, its ΔE from its own rows, and `vs_series` from the two caches — E° shift = −ΔΔE_red per
    4 substituents, in mV; the series rows that stand on `converged` alone are named.
    CAN catch: a stale or hand-edited comparison, an unaccepted row counted, a sign or unit slip. CANNOT catch: which
    continuum is nearer experiment (that is `83`'s `solvation_check`)."""
    path = DFT / f"os_mediator_series_{name}.json"
    if not path.exists():
        pytest.skip(f"21e b3lyp-{name} not run")
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import HARTREE_TO_EV, S2_MAX_DOUBLET
    rec = json.loads(path.read_text())
    series = json.loads((DFT / "os_mediator_series.json").read_text())["complexes"]
    base = {c["name"]: c["dE_red_eV"] for c in series}
    var = {}
    for n, c in rec["complexes"].items():
        o2, o3 = c["os2"], c["os3"]
        assert o2["converged"] and o3["converged"] and o2.get("aufbau") and o3.get("aufbau"), n
        assert o3["s2"] <= S2_MAX_DOUBLET and not o2.get("rescued") and not o3.get("rescued"), n
        assert c["dE_red_eV"] == (o2["E_total_Ha"] - o3["E_total_Ha"]) * HARTREE_TO_EV, n
        var[n] = c["dE_red_eV"]
    v = rec["vs_series"]
    assert v["point_shift_eV"] == {n: var[n] - base[n] for n in var} and v["rescued_rows"] == []
    assert v["series_os3_s2_not_recorded"] == sorted(c["name"] for c in series if c["name"] in var and "s2" not in c["os3"])
    for p in v["pairs"]:
        x, r = p["x"], p["ref"]
        assert p["series_mV"] == -(base[x] - base[r]) / 4 * 1000 and p["variant_mV"] == -(var[x] - var[r]) / 4 * 1000, (x, r)
        assert p["change_mV"] == p["variant_mV"] - p["series_mV"], (x, r)


def test_os_mediator_series_rows_that_record_s2_are_doublets():
    """A B3LYP series row written since <S²> is recorded (dft_singlepoint, 2026-10-11) is held to the acceptance the
    ωB97X rows meet — <S²> ≤ S2_MAX_DOUBLET and an aufbau filling (§Critical Rules #14). The older rows record no <S²>
    and stand on `converged`, as the paper says (§2.2); a NEW row cannot slip in on `converged` alone."""
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import S2_MAX_DOUBLET
    rows = json.loads((DFT / "os_mediator_series.json").read_text())["complexes"]
    for c in rows:
        o3 = c["os3"]
        if "s2" in o3:
            assert o3["s2"] <= S2_MAX_DOUBLET and o3.get("aufbau") is True, (c["name"], o3["s2"], o3.get("aufbau"))


def _ols_slope(xs, ys):
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys, strict=True)) / sum((x - mx) ** 2 for x in xs)


def test_21e_small_basis_mode_never_writes_the_def2tzvp_cache(tmp_path, monkeypatch):
    """The first draft of `wb97x-631gd` wrote each converged state into OUT_WB97X — one state of NH₂ would have
    overwritten the committed def2-TZVP series. Rehearsed with a stubbed SCF (no compute).

    CAN catch: any write of the small-basis mode into the def2-TZVP cache; a tier that drifts from 34b's
    (functional, basis, shift per state, tolerance). CANNOT catch: what a real SCF returns.
    """
    pytest.importorskip("pyscf")
    pytest.importorskip("rdkit")
    import importlib.util
    spec = importlib.util.spec_from_file_location("s21e", Path(__file__).parents[1] / "scripts" / "21e_dft_os_mediator_series.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    import pyscf
    calls = []

    def fake(atoms, charge, spin, label="", xc="b3lyp", conv_tol=1e-6, level_shift_open=0.0, basis_light=None,
             dm0=None, stability=False, **_):
        calls.append((charge, spin, xc, conv_tol, level_shift_open, basis_light, dm0 is not None, stability))
        return {"E_total_Ha": -1.0 - 0.1 * charge, "converged": True, "wall_seconds": 0.0, **({"s2": 0.755} if spin else {})}

    tz = tmp_path / "tz.json"
    tz.write_text('{"sentinel": true}\n')
    monkeypatch.setattr(m, "dft_singlepoint", fake)
    monkeypatch.setattr(m, "_doublet_start", lambda *a: ("dm0", {"from": "stub", "hole_os_fraction": 1.0,
                                                                 "os2_rerun_delta_Ha": None}))
    monkeypatch.setattr(m, "_recorded_pyscf", lambda: pyscf.__version__)
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", float("inf"))   # the platform's RDKit is not this test's subject
    monkeypatch.setattr(m, "OUT_WB97X", tz)
    monkeypatch.setattr(m, "OUT_WB97X_631GD", tmp_path / "small.json")
    m.main_wb97x(["nh2"], small_basis=True)
    assert tz.read_text() == '{"sentinel": true}\n', "the small-basis mode wrote into the def2-TZVP cache"
    assert calls == [(1, 0, "wb97x", 1e-6, 0.0, None, False, False), (2, 1, "wb97x", 1e-6, 0.3, None, True, True)], calls
    assert "dE_red_eV" in json.loads((tmp_path / "small.json").read_text())["complexes"]["nh2"]


def test_21e_os_basis_mode_changes_only_the_os_basis(tmp_path, monkeypatch):
    """`b3lyp-osdef2` (00_07 HW.5.IS) must be the B3LYP series protocol with ONE change — def2-TZVP/ECP on Os — so a moved
    pair is the osmium basis and nothing else. Rehearsed with a stubbed SCF (no compute), before the first real run.

    CAN catch: a write into any other cache; a call that is not B3LYP, not at the series tolerance, level-shifted, started
    from a density, stability-followed, on another ligand basis or without basis_os='def2-tzvp'; an off-geometry point
    reaching the SCF; a comparison block that does not follow from the two caches. CANNOT catch: what a real SCF returns.
    """
    pytest.importorskip("pyscf")
    pytest.importorskip("rdkit")
    import pyscf
    m = _load_21e()
    calls = []

    def fake(atoms, **kw):   # every keyword recorded — a protocol change that rides on a default is a new keyword
        calls.append({k: v for k, v in kw.items() if k != "label"})
        return {"E_total_Ha": -1.0 - 0.1 * kw["charge"] - 0.001 * len(atoms), "converged": True, "wall_seconds": 0.0,
                "aufbau": True, **({"s2": 0.755} if kw["spin"] else {})}

    guarded = {k: tmp_path / f"{k}.json" for k in ("OUT", "OUT_WB97X", "OUT_WB97X_631GD")}
    series = json.loads((DFT / "os_mediator_series.json").read_text())
    guarded["OUT"].write_text(json.dumps(series))
    for k in ("OUT_WB97X", "OUT_WB97X_631GD"):
        guarded[k].write_text('{"sentinel": true}\n')
    before = {k: v.read_text() for k, v in guarded.items()}
    monkeypatch.setattr(m, "dft_singlepoint", fake)
    monkeypatch.setattr(m, "_recorded_pyscf", lambda: pyscf.__version__)
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", float("inf"))   # the platform's RDKit is not this test's subject
    for k, v in guarded.items():
        monkeypatch.setattr(m, k, v)
    out = tmp_path / "osdef2.json"
    monkeypatch.setattr(m, "OUT_OSDEF2", out)
    m.main_os_basis(["bpy", "dmbpy"])
    assert {k: v.read_text() for k, v in guarded.items()} == before, "the Os-basis mode wrote into another cache"
    proto = {"basis_os": "def2-tzvp", "max_cycle": m.VARIANT_MAX_CYCLE}   # everything else: dft_singlepoint's defaults, as main()
    assert calls == [{"charge": 1, "spin": 0, **proto}, {"charge": 2, "spin": 1, **proto}] * 2, calls
    rec = json.loads(out.read_text())
    lanl = {c["name"]: c["dE_red_eV"] for c in series["complexes"]}
    (pair,) = rec["vs_lanl2dz"]["pairs"]
    d2 = {n: rec["complexes"][n]["dE_red_eV"] for n in ("bpy", "dmbpy")}
    assert (pair["x"], pair["ref"]) == ("dmbpy", "bpy")
    assert pair["lanl2dz_mV"] == -(lanl["dmbpy"] - lanl["bpy"]) / 4 * 1000
    s83 = json.loads((DFT / "os_series_vs_measured.json").read_text())   # sign and units against 83, independently
    assert pair["lanl2dz_mV"] == pytest.approx(s83["computed"]["b3lyp_631gd"]["dmbpy"]["shift_per_substituent_V"] * 1000, abs=1e-9)
    assert pair["def2tzvp_mV"] == -(d2["dmbpy"] - d2["bpy"]) / 4 * 1000 and pair["change_mV"] == pair["def2tzvp_mV"] - pair["lanl2dz_mV"]
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", 0.0)
    monkeypatch.setattr(m, "_series_geometry_dev", lambda name, atoms: 1.0)
    calls.clear()
    with pytest.raises(SystemExit):
        m.main_os_basis(["ome"])
    assert calls == [], "an off-geometry point reached the SCF"



def test_21e_relaxed_mode_changes_only_the_geometry(tmp_path, monkeypatch):
    """`b3lyp-relaxed-os2` (00_07 HW.5.IS leg 3a): the series protocol with its geometry relaxed at Os(II) — rehearsed
    with a stubbed optimiser and SCF (no compute), before the first real run (§When Modifying #34), against the run-path
    adversary's findings (2026-10-12).

    CAN catch: a write into any other cache; an optimiser call that is not Os(II), not at the declared thresholds and SCF
    tolerance, or without the per-step keeper; single points that are not exactly two per point, both on the relaxed
    atoms; a non-converged point that stops the run or yields a pair; a re-run that restarts from the programmatic geometry
    instead of the saved one; a converged geometry recomputed; refusals that never fire (off-geometry before the optimiser,
    step 0 off the series row, a units slip at a step, a single point off the last step). CANNOT catch: what geomeTRIC and
    a real SCF return."""
    pytest.importorskip("pyscf")
    pytest.importorskip("rdkit")
    import pyscf
    m = _load_21e()
    sp, opt = [], []
    series = json.loads((DFT / "os_mediator_series.json").read_text())
    e0 = {r["name"]: r["os2"]["E_total_Ha"] for r in series["complexes"]}
    nonconv, saved_e = set(), {}   # saved_e: the energy of each geometry the stub returned — a restart starts there

    def fake_sp(atoms, **kw):
        sp.append(({k: v for k, v in kw.items() if k != "label"}, float(atoms[1][1][0])))
        last = saved_e.get(float(atoms[1][1][0]), -2.0)   # the optimiser's last step on these atoms (fake_opt below)
        return {"E_total_Ha": last if kw["charge"] == 1 else last + 0.15, "converged": True, "wall_seconds": 0.0,
                "aufbau": True, **({"s2": 0.755} if kw["spin"] else {})}

    def fake_opt(atoms, charge, spin, label="", maxsteps=0, conv_params=None, on_step=None, **protocol):
        name = label.split()[1]
        opt.append({"charge": charge, "spin": spin, "maxsteps": maxsteps, "conv_params": conv_params, **protocol,
                    "start_x": float(atoms[1][1][0]), "keeper": callable(on_step)})
        moved = [(e, np.asarray(x, float) + (0.05 if i == 1 else 0.0)) for i, (e, x) in enumerate(atoms)]
        tr = [{"E_Ha": saved_e.get(float(atoms[1][1][0]), e0[name]), "grad_max_Ha_bohr": 0.01}]
        tr.append({"E_Ha": tr[0]["E_Ha"] - 1e-3, "grad_max_Ha_bohr": 1e-4})   # a real optimiser goes DOWN
        saved_e[float(moved[1][1][0])] = tr[1]["E_Ha"]
        on_step(atoms, tr[:1])
        on_step(moved, tr)
        ok = name not in nonconv
        return moved, {"label": label, "converged": ok, "steps": 2, "wall_seconds": 0.0, "trajectory": tr,
                       "returned": "final" if ok else "lowest-energy step 2", "error": None if ok else "stub: not converged",
                       "conv_params": conv_params}

    caches = ("OUT", "OUT_WB97X", "OUT_WB97X_631GD", "OUT_OSDEF2", "OUT_IEFPCM", "OUT_UFFCAV", "OUT_GAS", "OUT_PYAXIAL",
              "OUT_RELAXED")
    guarded = {k: tmp_path / f"{k}.json" for k in caches}
    guarded["OUT"].write_text(json.dumps(series))
    for k in caches[1:-1]:
        guarded[k].write_text('{"sentinel": true}\n')
    for k, v in guarded.items():
        monkeypatch.setattr(m, k, v)
    before = {k: v.read_text() for k, v in guarded.items() if k != "OUT_RELAXED"}
    monkeypatch.setattr(m, "dft_singlepoint", fake_sp)
    monkeypatch.setattr(m, "dft_optimize", fake_opt)
    monkeypatch.setattr(m, "_recorded_pyscf", lambda: pyscf.__version__)
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", float("inf"))   # the platform's RDKit is not this test's subject
    nonconv.add("ome")   # the first point fails: the run must go on to the next
    m.main_variant("b3lyp-relaxed-os2", ["ome", "bpy", "dmbpy"])
    assert {k: v.read_text() for k, v in guarded.items() if k != "OUT_RELAXED"} == before, "the relaxed mode wrote elsewhere"
    proto = {"charge": 1, "spin": 0, "maxsteps": m.RELAX_MAXSTEPS, "conv_params": m.RELAX_CONV,
             "max_cycle": m.VARIANT_MAX_CYCLE, "conv_tol": m.RELAX_SCF_CONV_TOL, "keeper": True}
    assert [{k: v for k, v in o.items() if k != "start_x"} for o in opt] == [proto] * 3, opt
    rec = json.loads(guarded["OUT_RELAXED"].read_text())
    for n in ("bpy", "dmbpy"):
        x = rec["complexes"][n]["geometry_os2_relaxed"]["atoms"][1][1][0]
        on = [kw["charge"] for kw, sx in sp if abs(sx - x) < 1e-12]
        assert sorted(on) == [1, 2], f"{n}: not exactly the two states on the relaxed atoms ({on})"
    assert len(sp) == 4, sp
    ome = rec["complexes"]["ome"]
    assert "dE_red_eV" not in ome and "os2" not in ome and not ome["geometry_os2_relaxed"]["info"]["converged"]
    assert [(p["x"], p["ref"]) for p in rec["vs_series"]["pairs"]] == [("dmbpy", "bpy")]
    # the re-run: converged points reused (no optimiser, no SCF); the failed one restarts from ITS saved geometry
    saved_x = ome["geometry_os2_relaxed"]["atoms"][1][1][0]
    sp.clear()
    opt.clear()
    nonconv.clear()
    m.main_variant("b3lyp-relaxed-os2", ["ome", "bpy", "dmbpy"])
    assert len(opt) == 1 and abs(opt[0]["start_x"] - saved_x) < 1e-12, "the re-run did not restart from the saved geometry"
    assert sorted(kw["charge"] for kw, _ in sp) == [1, 2], sp
    rec = json.loads(guarded["OUT_RELAXED"].read_text())
    assert rec["complexes"]["ome"]["geometry_os2_relaxed"]["info"]["restarted_from"] == "lowest-energy step 2"
    # refusals
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", 0.0)
    monkeypatch.setattr(m, "_series_geometry_dev", lambda name, atoms: 1.0)
    opt.clear()
    with pytest.raises(SystemExit):
        m.main_variant("b3lyp-relaxed-os2", ["cl"])
    assert opt == [], "an off-geometry point reached the optimiser"
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", float("inf"))
    e0["cl"] += 1e-3   # step 0 is not the series row's energy: another protocol
    with pytest.raises(SystemExit, match="step 0"):
        m.main_variant("b3lyp-relaxed-os2", ["cl"])
    e0["cl"] -= 1e-3

    def slip(atoms, charge, spin, label="", maxsteps=0, conv_params=None, on_step=None, **protocol):
        on_step([(e, np.asarray(x, float) * 0.529177) for e, x in atoms], [{"E_Ha": e0["cl"], "grad_max_Ha_bohr": 0.0}])
        raise AssertionError("the keeper should have refused the units slip")
    monkeypatch.setattr(m, "dft_optimize", slip)
    rec = json.loads(guarded["OUT_RELAXED"].read_text())
    rec["complexes"].pop("cl", None)
    guarded["OUT_RELAXED"].write_text(json.dumps(rec))
    with pytest.raises(SystemExit, match="units slip"):
        m.main_variant("b3lyp-relaxed-os2", ["cl"])
    monkeypatch.setattr(m, "dft_optimize", fake_opt)
    monkeypatch.setattr(m, "dft_singlepoint", lambda atoms, **kw: {**fake_sp(atoms, **kw), "E_total_Ha": 0.0})
    with pytest.raises(SystemExit, match="single point"):
        m.main_variant("b3lyp-relaxed-os2", ["cl"])


def test_21e_relaxed_os3_mode_relaxes_only_os3(tmp_path, monkeypatch):
    """`b3lyp-relaxed-os3` (00_07 HW.5.IS leg 3б): Os(III) relaxed from each point's relaxed Os(II) — rehearsed with a
    stubbed optimiser and SCF before the first real run (§When Modifying #34).

    CAN catch: a write into any other cache (the os2 cache included); an optimiser call that is not Os(III) from the
    relaxed Os(II) atoms at the declared thresholds, or without the keeper; an Os(II) recomputed; single points that are
    not exactly one Os(III) per point on its relaxed atoms; λ_III or the adiabatic ΔE_red from the wrong energies; a
    non-converged point that stops the run or yields a pair; a re-run that restarts from the start instead of the saved
    geometry; refusals that never fire (no relaxed Os(II), step 0 off the vertical Os(III), a spin-contaminated step, a
    units slip, a single point off the last step). CANNOT catch: what geomeTRIC and a real UKS return."""
    pytest.importorskip("pyscf")
    pytest.importorskip("rdkit")
    import pyscf
    m = _load_21e()
    sp, opt = [], []
    src = json.loads((DFT / "os_mediator_series_relaxed_os2.json").read_text())
    ev = {n: c["os3"]["E_total_Ha"] for n, c in src["complexes"].items()}
    nonconv, s2_bad, saved_e = set(), set(), {}

    def fake_sp(atoms, **kw):
        sp.append(({k: v for k, v in kw.items() if k != "label"}, float(atoms[1][1][0])))
        return {"E_total_Ha": saved_e.get(float(atoms[1][1][0]), -3.0), "converged": True, "wall_seconds": 0.0,
                "aufbau": True, "s2": 0.755}

    def fake_opt(atoms, charge, spin, label="", maxsteps=0, conv_params=None, on_step=None, **protocol):
        name = label.split()[1]
        opt.append({"charge": charge, "spin": spin, "maxsteps": maxsteps, "conv_params": conv_params, **protocol,
                    "start_x": float(atoms[1][1][0]), "keeper": callable(on_step)})
        moved = [(e, np.asarray(x, float) + (0.04 if i == 1 else 0.0)) for i, (e, x) in enumerate(atoms)]
        tr = [{"E_Ha": saved_e.get(float(atoms[1][1][0]), ev[name]), "grad_max_Ha_bohr": 0.01, "s2": 0.755}]
        tr.append({"E_Ha": tr[0]["E_Ha"] - 1e-3, "grad_max_Ha_bohr": 1e-4, "s2": 0.9 if name in s2_bad else 0.755})
        saved_e[float(moved[1][1][0])] = tr[1]["E_Ha"]
        on_step(atoms, tr[:1])
        on_step(moved, tr)
        ok = name not in nonconv
        return moved, {"label": label, "converged": ok, "steps": 2, "wall_seconds": 0.0, "trajectory": tr,
                       "returned": "final" if ok else "lowest-energy step 2", "error": None if ok else "stub: not converged",
                       "conv_params": conv_params}

    caches = ("OUT", "OUT_WB97X", "OUT_WB97X_631GD", "OUT_OSDEF2", "OUT_IEFPCM", "OUT_UFFCAV", "OUT_GAS", "OUT_PYAXIAL",
              "OUT_RELAXED", "OUT_RELAXED3")
    guarded = {k: tmp_path / f"{k}.json" for k in caches}
    guarded["OUT"].write_text((DFT / "os_mediator_series.json").read_text())
    guarded["OUT_RELAXED"].write_text(json.dumps(src))
    for k in caches[1:-2]:
        guarded[k].write_text('{"sentinel": true}\n')
    for k, v in guarded.items():
        monkeypatch.setattr(m, k, v)
    before = {k: v.read_text() for k, v in guarded.items() if k != "OUT_RELAXED3"}
    monkeypatch.setattr(m, "dft_singlepoint", fake_sp)
    monkeypatch.setattr(m, "dft_optimize", fake_opt)
    monkeypatch.setattr(m, "_recorded_pyscf", lambda: pyscf.__version__)
    nonconv.add("ome")
    m.main_relaxed_os3(["ome", "bpy", "dmbpy"])
    assert {k: v.read_text() for k, v in guarded.items() if k != "OUT_RELAXED3"} == before, "the os3 mode wrote elsewhere"
    proto = {"charge": 2, "spin": 1, "maxsteps": m.RELAX_MAXSTEPS, "conv_params": m.RELAX_CONV,
             "max_cycle": m.VARIANT_MAX_CYCLE, "conv_tol": m.RELAX_SCF_CONV_TOL, "keeper": True}
    assert [{k: v for k, v in o.items() if k != "start_x"} for o in opt] == [proto] * 3, opt
    starts = {n: c["geometry_os2_relaxed"]["atoms"][1][1][0] for n, c in src["complexes"].items()}
    assert [o["start_x"] for o in opt] == [starts[n] for n in ("ome", "bpy", "dmbpy")], "not started at the Os(II) minimum"
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    assert len(sp) == 2 and all(kw["charge"] == 2 and kw["spin"] == 1 for kw, _ in sp), sp
    for n in ("bpy", "dmbpy"):
        c, s = rec["complexes"][n], src["complexes"][n]
        assert any(abs(sx - c["geometry_os3_relaxed"]["atoms"][1][1][0]) < 1e-12 for _, sx in sp), n
        assert c["dE_red_adiabatic_eV"] == pytest.approx((s["os2"]["E_total_Ha"] - c["os3"]["E_total_Ha"]) * m.HARTREE_TO_EV)
        assert c["lambda_os3_meV"] == pytest.approx((s["os3"]["E_total_Ha"] - c["os3"]["E_total_Ha"]) * m.HARTREE_TO_EV * 1e3)
    ome = rec["complexes"]["ome"]
    assert "dE_red_adiabatic_eV" not in ome and "os3" not in ome and not ome["geometry_os3_relaxed"]["info"]["converged"]
    assert [(p["x"], p["ref"]) for p in rec["vs_vertical"]["pairs"]] == [("dmbpy", "bpy")]
    assert set(rec["vs_vertical"]["point_shift_eV"]) == {"bpy", "dmbpy"}
    # the re-run: converged points reused (no optimiser, no SCF); the failed one restarts from ITS saved geometry
    saved_x = ome["geometry_os3_relaxed"]["atoms"][1][1][0]
    sp.clear()
    opt.clear()
    nonconv.clear()
    m.main_relaxed_os3(["ome", "bpy", "dmbpy"])
    assert len(opt) == 1 and abs(opt[0]["start_x"] - saved_x) < 1e-12, "the re-run did not restart from the saved geometry"
    assert len(sp) == 1, sp
    # a restart whose first SCF is not the saved geometry's own energy is refused: a plain start there may land in
    # another doublet with a clean <S²> and bias λ_III silently (run-path adversary, 2026-10-13)
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    b = rec["complexes"]["bpy"]
    b["geometry_os3_partial"] = {"atoms": b.pop("geometry_os3_relaxed")["atoms"], "steps": 1, "E_min_Ha": -1.0,
                                 "restarted_from": None}
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))
    with pytest.raises(SystemExit, match="step 0"):
        m.main_relaxed_os3(["bpy"])
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    rec["complexes"].pop("bpy")
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))
    # refusals
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    rec["complexes"].pop("dmbpy")
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))
    bad = json.loads(json.dumps(src))
    bad["complexes"]["dmbpy"]["geometry_os2_relaxed"]["info"]["converged"] = False
    guarded["OUT_RELAXED"].write_text(json.dumps(bad))
    opt.clear()
    with pytest.raises(SystemExit, match="no accepted relaxed Os"):
        m.main_relaxed_os3(["dmbpy"])
    assert opt == [], "a point without a relaxed Os(II) reached the optimiser"
    guarded["OUT_RELAXED"].write_text(json.dumps(src))
    ev["dmbpy"] += 1e-3   # step 0 is not the vertical Os(III): another state or protocol
    with pytest.raises(SystemExit, match="step 0"):
        m.main_relaxed_os3(["dmbpy"])
    ev["dmbpy"] -= 1e-3
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    rec["complexes"].pop("dmbpy", None)
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))
    s2_bad.add("dmbpy")
    with pytest.raises(SystemExit, match="S²"):
        m.main_relaxed_os3(["dmbpy"])
    s2_bad.clear()
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    rec["complexes"].pop("dmbpy", None)
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))

    def slip(atoms, charge, spin, label="", maxsteps=0, conv_params=None, on_step=None, **protocol):
        on_step([(e, np.asarray(x, float) * 0.529177) for e, x in atoms],
                [{"E_Ha": ev["dmbpy"], "grad_max_Ha_bohr": 0.0, "s2": 0.755}])
        raise AssertionError("the keeper should have refused the units slip")
    monkeypatch.setattr(m, "dft_optimize", slip)
    with pytest.raises(SystemExit, match="units slip"):
        m.main_relaxed_os3(["dmbpy"])
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    rec["complexes"].pop("dmbpy", None)
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))
    monkeypatch.setattr(m, "dft_optimize", fake_opt)
    monkeypatch.setattr(m, "dft_singlepoint", lambda atoms, **kw: {**fake_sp(atoms, **kw), "E_total_Ha": 0.0})
    m.main_relaxed_os3(["dmbpy", "bpy"])   # a single point off the last step is refused, recorded, and the run goes on
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    c = rec["complexes"]["dmbpy"]
    assert "os3" not in c and "dE_red_adiabatic_eV" not in c and "higher state" in c["os3_refused"]
    assert "os3_refused" in rec["complexes"]["bpy"], "the refusal stopped the next point"
    # the Os(II) start moved: the Os(III) record built on the old one is discarded, not reused
    moved_src = json.loads(json.dumps(src))
    moved_src["complexes"]["bpy"]["os2"]["E_total_Ha"] += 1e-4
    guarded["OUT_RELAXED"].write_text(json.dumps(moved_src))
    monkeypatch.setattr(m, "dft_singlepoint", fake_sp)
    opt.clear()
    m.main_relaxed_os3(["bpy"])
    assert len(opt) == 1, "an Os(III) geometry relaxed from another Os(II) start was reused"
    assert {k: v.read_text() for k, v in guarded.items() if k not in ("OUT_RELAXED3", "OUT_RELAXED")} == {
        k: v for k, v in before.items() if k != "OUT_RELAXED"}
    # the acceptor run's run-path adversary (2026-10-14): a rescued or ligand-held vertical Os(III) is no step-0
    # reference; a rescued final single point is refused like an off-step one; a saved trajectory with no converged
    # step restarts afresh instead of crashing on min() of nothing
    guarded["OUT_RELAXED"].write_text(json.dumps(src))
    for patch, match in (({"rescued": True}, "Newton rescue"), ({"os_spin_mulliken": 0.55}, "not on the metal")):
        bad = json.loads(json.dumps(src))
        bad["complexes"]["dmbpy"]["os3"].update(patch)
        guarded["OUT_RELAXED"].write_text(json.dumps(bad))
        opt.clear()
        with pytest.raises(SystemExit, match=match):
            m.main_relaxed_os3(["dmbpy"])
        assert opt == [], f"{match}: reached the optimiser"
    guarded["OUT_RELAXED"].write_text(json.dumps(src))
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    rec["complexes"].pop("dmbpy", None)
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))
    monkeypatch.setattr(m, "dft_singlepoint", lambda atoms, **kw: {**fake_sp(atoms, **kw), "rescued": True})
    m.main_relaxed_os3(["dmbpy", "bpy"])
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    assert "Newton rescue" in rec["complexes"]["dmbpy"]["os3_refused"] and "os3" not in rec["complexes"]["dmbpy"]
    assert "os3_refused" in rec["complexes"]["bpy"], "the rescue refusal stopped the next point"
    monkeypatch.setattr(m, "dft_singlepoint", fake_sp)
    rec = json.loads(guarded["OUT_RELAXED3"].read_text())
    g = rec["complexes"]["dmbpy"]["geometry_os3_relaxed"]
    g["info"]["converged"] = False
    for step in g["info"]["trajectory"]:
        step["scf_converged"] = False
    rec["complexes"]["dmbpy"].pop("geometry_os3_partial", None)
    guarded["OUT_RELAXED3"].write_text(json.dumps(rec))
    opt.clear()
    m.main_relaxed_os3(["dmbpy"])
    assert len(opt) == 1 and abs(opt[0]["start_x"] - starts["dmbpy"]) < 1e-12, "no converged step: not a fresh start"


def test_dft_optimize_wraps_geomeTRIC_as_declared(monkeypatch):
    """The real `dft_optimize` with geomeTRIC stubbed (no SCF): what it hands the optimiser and what it returns — the
    run-path adversary (2026-10-12) found it never executed by any test.
    CAN catch: grid response off; the protocol not on the SCF object (C-PCM, ε, tolerance, cycles); assert_convergence
    off; thresholds not passed; Bohr returned as Å or atoms reordered; an SCF failure at a step that raises instead of
    returning NOT converged with the lowest-energy geometry; a keeper that never sees a step. CANNOT catch: geomeTRIC's
    own steps."""
    pytest.importorskip("pyscf")
    import pyscf.geomopt.geometric_solver as gs
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib import dft_utils
    from lib.constants import SOLVENT_EPS_WATER
    seen, kept = {}, []
    atoms = [("O", np.array([0.0, 0.0, 0.0])), ("H", np.array([0.0, 0.76, 0.59])), ("H", np.array([0.0, -0.76, 0.59]))]

    def fake_kernel(method, assert_convergence=True, callback=None, maxsteps=100, **kw):
        seen.update(method=method, assert_convergence=assert_convergence, maxsteps=maxsteps, kw=kw)
        mol = method.mol.copy()
        for e in (-76.0, -76.2, -76.1):   # the lowest-energy step is the second
            mol.set_geom_(mol.atom_coords() * (1.0 + 0.01 * len(kept)), unit="Bohr")
            gs = method if not (seen.get("unconv") and e == -76.2) else types.SimpleNamespace(
                grid_response=True, converged=False, base=method.base)   # PySCF calls back, THEN raises on a failed SCF
            callback({"mol": mol, "energy": e, "gradients": np.full((3, 3), 1e-3), "g_scanner": gs})
        if seen.get("fail"):
            raise RuntimeError("Nuclear gradients of stub not converged")
        return True, mol

    monkeypatch.setattr(gs, "kernel", fake_kernel)
    conv = {"convergence_gmax": 4.5e-4}
    out, info = dft_utils.dft_optimize(atoms, charge=0, spin=0, maxsteps=7, conv_params=conv, conv_tol=1e-8,
                                       max_cycle=400, on_step=lambda g, tr: kept.append((g, list(tr))))
    meth = seen["method"]
    assert meth.grid_response is True and seen["assert_convergence"] is True and seen["maxsteps"] == 7
    assert {k: v for k, v in seen["kw"].items() if k.startswith("convergence")} == conv
    base = meth.base
    assert base.with_solvent.method == "C-PCM" and base.with_solvent.eps == SOLVENT_EPS_WATER
    assert base.conv_tol == 1e-8 and base.max_cycle == 400 and base.xc == "b3lyp"
    assert [e for e, _ in out] == ["O", "H", "H"] and len(kept) == 3 and info["converged"]
    assert abs(float(out[1][1][1]) - 0.76 * 1.0 * 1.01 * 1.02) < 1e-6, "the geometry is not returned in Å"
    assert all(t["grid_response"] for t in info["trajectory"])
    seen["fail"] = True
    kept.clear()
    out, info = dft_utils.dft_optimize(atoms, charge=0, spin=0, maxsteps=7, conv_params=conv, conv_tol=1e-8,
                                       max_cycle=400, on_step=lambda g, tr: kept.append((g, list(tr))))
    assert not info["converged"] and "not converged" in info["error"] and info["returned"] == "lowest-energy step 2"
    assert abs(float(out[1][1][1]) - 0.76 * 1.0 * 1.01) < 1e-6, "not the lowest-energy step's geometry"
    seen["unconv"] = True   # the second step's SCF failed: it is recorded, but neither the best nor the keeper's
    kept.clear()
    out, info = dft_utils.dft_optimize(atoms, charge=0, spin=0, maxsteps=7, conv_params=conv, conv_tol=1e-8,
                                       max_cycle=400, on_step=lambda g, tr: kept.append((g, list(tr))))
    assert [t["scf_converged"] for t in info["trajectory"]] == [True, False, True] and len(kept) == 2
    assert info["returned"] == "lowest-energy step 3", "an unconverged step became the restart point"


def test_relax_to_minimum_runs_the_real_stack(monkeypatch, tmp_path):
    """lib's escape loop (`relax_to_minimum` · `relax_checked`) with geomeTRIC and the SCF's kernel / Hessian / <S²> stubbed —
    the real `_scf_object`, the keyword plumbing through `dft_optimize` and `harmonic`, PySCF's `harmonic_analysis` and
    `thermo` all run. The run-path adversary (2026-10-16) found 32b's T/P keywords falling into the SCF protocol (a
    TypeError at the first optimisation) behind an equivalence harness that stubbed `dft_optimize` itself.
    CAN catch: a keyword some layer rejects; a saddle not escaped or its Hessian not kept; the state tie (energy, a
    doublet's <S²>) not enforced; a failed Hessian SCF, another state or a stretched X–H crashing `relax_checked` instead
    of a refusal with its reason. CANNOT catch: PySCF's SCF and Hessian, geomeTRIC's steps."""
    pytest.importorskip("pyscf")
    import pyscf.geomopt.geometric_solver as gs
    from pyscf.hessian import thermo
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib import dft_utils
    water = [("O", np.array([0.0, 0.0, 0.0])), ("H", np.array([0.0, 0.757, 0.587])), ("H", np.array([0.0, -0.757, 0.587]))]
    st = {}

    def key(mol):
        return tuple(np.round(mol.atom_coords(), 5).ravel())

    def fake_kernel(method, assert_convergence=True, callback=None, maxsteps=100, **kw):
        mol = method.mol.copy()
        if st.get("stretch"):
            xyz = mol.atom_coords(unit="Angstrom")
            xyz[1] = xyz[0] + 1.5 * (xyz[1] - xyz[0]) / np.linalg.norm(xyz[1] - xyz[0])
            mol.set_geom_(xyz, unit="Angstrom")
        e = -76.0 - 0.005 * st["opt"]                  # every escape lands lower
        st["opt"] += 1
        st["E"][key(mol)] = e
        callback({"mol": mol, "energy": e, "gradients": np.full((3, 3), 1e-5), "g_scanner": method})
        return True, mol

    def hessian(mol):
        st["hess"] += 1
        h = 0.5 * np.eye(9)
        if st["hess"] in st["saddle_at"]:            # one negative curvature along a vibration
            v = thermo.harmonic_analysis(mol, (0.5 * np.eye(9)).reshape(3, 3, 3, 3).transpose(0, 2, 1, 3))["norm_mode"][0].ravel()
            h = h - 2.0 * np.outer(v, v) / (v @ v)
        return h.reshape(3, 3, 3, 3).transpose(0, 2, 1, 3)
    real = dft_utils._scf_object

    def scf_object(atoms, charge, spin, **protocol):
        mol, mf = real(atoms, charge, spin, **protocol)           # the real keyword check
        s2 = st["s2"].pop(0) if st["s2"] else 0.754

        def kernel(*a, **k):
            mf.converged = st["scf_ok"].pop(0) if st["scf_ok"] else True
            mf.e_tot = st["E"].get(key(mol), -76.0) + st["offset"]
            return mf.e_tot
        mf.kernel, mf.spin_square = kernel, (lambda *a, s2=s2: (s2, 2.0))
        mf.Hessian = lambda: types.SimpleNamespace(kernel=lambda: hessian(mol))
        return mol, mf
    monkeypatch.setattr(gs, "kernel", fake_kernel)
    monkeypatch.setattr(dft_utils, "_scf_object", scf_object)

    def reset(**kw):
        st.clear()
        st.update({"opt": 0, "hess": 0, "E": {}, "s2": [], "scf_ok": [], "offset": 0.0, "saddle_at": {1}, **kw})

    def runs_dir(name):
        d = tmp_path / name
        d.mkdir()
        return d

    # 32b's call: T and P as keywords (the TypeError), a closed shell met at a saddle, escaped once
    reset()
    runs = runs_dir("a")
    _, th, info = dft_utils.relax_to_minimum(water, 0, 0, label="w", tag="w", runs=runs, imag_tol_cm=20.0, max_escapes=2,
                                               step_a=0.1, temperature_K=298.15, pressure_Pa=101325.0, conv_tol=1e-8)
    assert not th["_escape_modes"] and info["label"] == "w_escape1" and info["conv_params"] == dft_utils.ESCAPE_CONV
    assert (runs / "hessian_w_saddle0.npy").exists() and (runs / "hessian_w.npy").exists()
    # relax_checked on a doublet: minimum, its height, its checkpoint
    reset()
    runs = runs_dir("b")
    geo, summ, chk = dft_utils.relax_checked(water, 1, 1, label="cat", runs=runs, level_shift_open=0.2, conv_tol=1e-8, max_cycle=300)
    assert summ["minimum"] and chk["saddle_above_minimum_meV"] == [round(0.005 * 27.211386245988 * 1000, 2)] and chk["harmonic"]["s2"] == 0.754
    # the record carries the point it describes (a later check reads it instead of re-optimising), and a path outside the
    # repo — this tmp_path — is written as its bare file name (lib `repo_relative`)
    assert [s for s, _ in chk["geometry"]] == [s for s, _ in geo]
    assert np.allclose([p for _, p in chk["geometry"]], [p for _, p in geo])
    assert chk["harmonic"]["hessian_file"] == "hessian_cat.npy"
    assert (runs / "opt_cat.checkpoint.xyz").exists()
    # refusals, each with its reason, none a crash
    for case, kw, needle in (("<S²> of another state", {"s2": [0.754, 0.95], "saddle_at": set()}, "<S²>"),
                             ("Hessian SCF not converged", {"scf_ok": [False], "saddle_at": set()}, "did not converge"),
                             ("energy of another state", {"offset": 1e-5, "saddle_at": set()}, "another electronic state"),
                             ("stretched X–H", {"stretch": True, "saddle_at": set()}, "long X–H")):
        reset(**kw)
        runs = runs_dir(case.replace(" ", "_"))
        _, summ, chk = dft_utils.relax_checked(water, 1, 1, label="cat", runs=runs, level_shift_open=0.2, conv_tol=1e-8)
        assert not summ["minimum"] and needle in (summ["error"] or ""), (case, summ["error"])


def test_21e_relax_conv_keys_reach_geomeTRIC():
    """geomeTRIC reads its thresholds with `kwargs.get`, so a misspelt key is silently the default — read them back
    through geomeTRIC's own parameter object. No compute."""
    pytest.importorskip("geometric")
    pytest.importorskip("rdkit")
    import geometric.params
    m = _load_21e()
    p = geometric.params.OptParams(**m.RELAX_CONV)
    assert {k: getattr(p, "C" + k[1:]) for k in m.RELAX_CONV} == m.RELAX_CONV


def test_21e_pyaxial_changes_only_the_axial_ligand():
    """`b3lyp-pyaxial` (00_07 HW.5.IS, A1′): the knob is the builder's axial N-donor, so Os, both chelates and Cl must be
    the series' own atoms and the swap must be refused the moment it moves them. No SCF.
    CAN catch: a swap that moves the rest of the octahedron; a ligand that is not pyridine; a refusal that never fires.
    CANNOT catch: whether pyridine at the series' Os–N is the right model of the aqueous series' ampy (A1′ itself)."""
    pytest.importorskip("rdkit")
    m = _load_21e()
    smi = next(s for n, s, _, _ in m.SERIES if n == "dmbpy")
    series, _ = m.build_os_complex(bpy_smiles=smi)
    var = m._axial_swap("dmbpy", series, smi, m.VARIANT_AXIAL["b3lyp-pyaxial"])
    k = len(series) - 12 - 1   # 1-methylimidazole: C4H6N2
    tup = lambda a: [(e, tuple(float(c) for c in p)) for e, p in a]   # noqa: E731 — the builder's coordinates are arrays
    assert m._max_dev_A(tup(var[:k]), tup(series[:k])) == 0.0 and m._max_dev_A(tup(var[-1:]), tup(series[-1:])) == 0.0
    assert len(var) == len(series) - 1   # pyridine: C5H5N
    assert sorted(e for e, _ in var[k:-1]) == sorted("C" * 5 + "H" * 5 + "N")
    shifted = [(e, (x + 0.1, y, z)) if i == 1 else (e, (x, y, z)) for i, (e, (x, y, z)) in enumerate(series)]
    with pytest.raises(SystemExit):
        m._axial_swap("dmbpy", shifted, smi, m.VARIANT_AXIAL["b3lyp-pyaxial"])


@pytest.mark.parametrize("mode, knob", [("b3lyp-iefpcm", {"pcm_method": "IEF-PCM"}),
                                        ("b3lyp-uffcavity", {"pcm_radii": "uff-1.1"}),
                                        ("b3lyp-gas", {"with_pcm": False}),
                                        ("b3lyp-pyaxial", {})])
def test_21e_solvation_variants_change_one_knob(tmp_path, monkeypatch, mode, knob):
    """The solvation variants of 00_07 HW.5.IS (2026-10-11) — the B3LYP series protocol with ONE change each, so a moved
    pair is that knob and nothing else. Rehearsed with a stubbed SCF (no compute), before the first real run.

    CAN catch: a write into any other cache (the series, the ωB97X caches, def2 and the sister variants); a call carrying
    any keyword but the series' max_cycle and its own knob; an off-geometry point reaching the SCF; a comparison block
    that does not follow from the two caches. CANNOT catch: whether PySCF applies the knob (a real-SCF check on water
    does that — test_dft_singlepoint_solvation_knobs_reach_pyscf), nor what a real SCF returns.
    """
    pytest.importorskip("pyscf")
    pytest.importorskip("rdkit")
    import pyscf
    m = _load_21e()
    calls = []

    def fake(atoms, **kw):
        calls.append({k: v for k, v in kw.items() if k != "label"})
        return {"E_total_Ha": -1.0 - 0.1 * kw["charge"] - 0.001 * len(atoms), "converged": True, "wall_seconds": 0.0,
                "aufbau": True, **({"s2": 0.755} if kw["spin"] else {})}

    caches = ("OUT", "OUT_WB97X", "OUT_WB97X_631GD", "OUT_OSDEF2", "OUT_IEFPCM", "OUT_UFFCAV", "OUT_GAS", "OUT_PYAXIAL")
    guarded = {k: tmp_path / f"{k}.json" for k in caches}
    series = json.loads((DFT / "os_mediator_series.json").read_text())
    guarded["OUT"].write_text(json.dumps(series))
    for k in caches[1:]:
        guarded[k].write_text('{"sentinel": true}\n')
    for k, v in guarded.items():
        monkeypatch.setattr(m, k, v)
    own = m._variant_out(mode)
    own.unlink()
    before = {k: v.read_text() for k, v in guarded.items() if v != own}
    monkeypatch.setattr(m, "dft_singlepoint", fake)
    monkeypatch.setattr(m, "_recorded_pyscf", lambda: pyscf.__version__)
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", float("inf"))   # the platform's RDKit is not this test's subject
    m.main_variant(mode, ["bpy", "dmbpy"])
    assert {k: v.read_text() for k, v in guarded.items() if v != own} == before, f"{mode} wrote into another cache"
    proto = {"max_cycle": m.VARIANT_MAX_CYCLE, **knob}
    assert calls == [{"charge": 1, "spin": 0, **proto}, {"charge": 2, "spin": 1, **proto}] * 2, calls
    rec = json.loads(own.read_text())
    base = {c["name"]: c["dE_red_eV"] for c in series["complexes"]}
    (pair,) = rec["vs_series"]["pairs"]
    d2 = {n: rec["complexes"][n]["dE_red_eV"] for n in ("bpy", "dmbpy")}
    assert (pair["x"], pair["ref"]) == ("dmbpy", "bpy") and rec["vs_series"]["rescued_rows"] == []
    assert pair["series_mV"] == -(base["dmbpy"] - base["bpy"]) / 4 * 1000
    assert pair["variant_mV"] == -(d2["dmbpy"] - d2["bpy"]) / 4 * 1000 and pair["change_mV"] == pair["variant_mV"] - pair["series_mV"]
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", 0.0)
    monkeypatch.setattr(m, "_series_geometry_dev", lambda name, atoms: 1.0)
    calls.clear()
    with pytest.raises(SystemExit):
        m.main_variant(mode, ["ome"])
    assert calls == [], "an off-geometry point reached the SCF"



def test_dft_singlepoint_solvation_knobs_reach_pyscf():
    """`pcm_method` and `pcm_radii` (2026-10-11) must reach PySCF — a stubbed rehearsal of 21e cannot see a knob that
    dft_singlepoint drops. A real SCF on water (B3LYP/6-31G(d), seconds): each knob alone moves E, and the defaults
    reproduce the call every committed row made. Measured 2026-10-11: two identical runs differ by ~1e-13 Ha (thread
    summation order), the smallest knob (IEF-PCM) moves E by 6.5e-5, the cavity by 3.0e-3, the gas phase by 1.0e-2 — so
    «same» is ≤ 1e-9 and «moved» > 1e-6. CAN catch: a knob ignored, or a default that is no longer C-PCM on the
    modified-Bondi ×1.2 cavity. CANNOT catch: the size of a knob's effect on an Os complex (that is 21e's own run).
    """
    pytest.importorskip("pyscf")
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.dft_utils import dft_singlepoint
    water = [("O", (0.0, 0.0, 0.1173)), ("H", (0.0, 0.7572, -0.4692)), ("H", (0.0, -0.7572, -0.4692))]
    e = {k: dft_singlepoint(water, charge=0, spin=0, **kw)["E_total_Ha"] for k, kw in {
        "default": {}, "explicit": {"pcm_method": "C-PCM", "pcm_radii": None}, "ief": {"pcm_method": "IEF-PCM"},
        "uff": {"pcm_radii": "uff-1.1"}, "gas": {"with_pcm": False}}.items()}
    assert abs(e["default"] - e["explicit"]) <= 1e-9, e
    assert all(abs(e[k] - e["default"]) > 1e-6 for k in ("ief", "uff", "gas")), e
    with pytest.raises(ValueError):
        dft_singlepoint(water, charge=0, spin=0, pcm_radii="bondi")


def _load_21e():
    import importlib.util
    spec = importlib.util.spec_from_file_location("s21e", Path(__file__).parents[1] / "scripts" / "21e_dft_os_mediator_series.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


@pytest.mark.parametrize("fresh_s2, writes_dE", [(1.767, False), (0.755, True)])
def test_21e_reuse_reads_s2_not_converged(tmp_path, monkeypatch, fresh_s2, writes_dE):
    """The night of 2026-10-09: NO₂ Os(III) «converged» at <S²> 1.767, and `main_wb97x` reused ANY converged state —
    a re-run would have taken the artefact back. Rehearsed with a stubbed SCF (no compute).

    CAN catch: a reuse that reads `converged` (a closed Os(II) is reused, an Os(III) with no <S²> on record is
    recomputed, never kept); a contaminated recomputed state that still writes ΔE_red, or leaves the stale one.
    CANNOT catch: what a real SCF returns, nor whether the doublet start lands on the ground state.
    """
    pytest.importorskip("pyscf")
    pytest.importorskip("rdkit")
    import pyscf
    m = _load_21e()
    small = tmp_path / "small.json"
    small.write_text(json.dumps({"method": "stub", "environment": {}, "complexes": {"no2": {
        "sigma_para": 0.78, "os2": {"converged": True, "E_total_Ha": -2.1},
        "os3": {"converged": True, "E_total_Ha": -2.0}, "dE_red_eV": -7.76}}}))
    calls = []

    def fake(atoms, charge, spin, **kw):
        calls.append((charge, spin, kw.get("dm0") is not None, kw.get("stability")))
        return {"E_total_Ha": -1.9, "converged": True, "wall_seconds": 0.0, "s2": fresh_s2}

    monkeypatch.setattr(m, "dft_singlepoint", fake)
    monkeypatch.setattr(m, "_doublet_start", lambda *a: ("dm0", {"from": "stub", "hole_os_fraction": 1.0,
                                                                 "os2_rerun_delta_Ha": 0.0}))
    monkeypatch.setattr(m, "_recorded_pyscf", lambda: pyscf.__version__)
    monkeypatch.setattr(m, "SAME_GEOMETRY_TOL_A", float("inf"))
    monkeypatch.setattr(m, "OUT_WB97X", tmp_path / "tz.json")
    monkeypatch.setattr(m, "OUT_WB97X_631GD", small)
    m.main_wb97x(["no2"], small_basis=True)
    assert calls == [(2, 1, True, True)], f"only Os(III) is recomputed, from the doublet start: {calls}"
    row = json.loads(small.read_text())["complexes"]["no2"]
    assert row["os3"]["s2"] == fresh_s2 and row["os3"]["start"]["from"] == "stub"
    assert ("dE_red_eV" in row) == writes_dE, f"<S²> {fresh_s2}: dE_red_eV present = {'dE_red_eV' in row}"
    if writes_dE:   # the FRESH pair, not the stale −7.76 the row carried
        assert row["dE_red_eV"] == (row["os2"]["E_total_Ha"] - row["os3"]["E_total_Ha"]) * m.HARTREE_TO_EV


@pytest.mark.parametrize("state, open_shell, verdict", [
    ({"converged": False, "s2": 0.755}, True, "not_converged"),
    ({"converged": True, "s2": 0.755, "aufbau": False}, True, "not_aufbau"),
    ({"converged": True, "s2": 0.755, "stable_internal": False}, True, "unstable"),
    ({"converged": True, "s2": 1.767}, True, "spin_contaminated"),
    ({"converged": True}, True, "s2_not_recorded"),
    ({"converged": True, "s2": 0.755, "aufbau": True, "stable_internal": True}, True, "accepted"),
    ({"converged": True}, False, "accepted"),
    ({"converged": True, "aufbau": False}, False, "not_aufbau"),
])
def test_21e_acceptance_is_never_converged_alone(state, open_shell, verdict):
    """`_acceptance` — one verdict per criterion. CAN catch: a criterion dropped or read as its opposite, an absent
    field read as a fail. CANNOT catch: whether the thresholds are right (S2_MAX_DOUBLET is OUR threshold)."""
    pytest.importorskip("rdkit")
    assert _load_21e()._acceptance(state, open_shell) == verdict


def test_21e_doublet_start_is_a_doublet_with_its_hole_in_the_homo(tmp_path):
    """`_doublet_start` on H₂O → H₂O⁺ (no Os — seconds, real SCF): the start must hold N_α = N_β + 1 electrons with the
    β hole in the closed shell's HOMO, the re-run of the closed shell must reproduce the row it is checked against,
    and the UKS that starts from it must land on a clean doublet.

    CAN catch: a hole in the wrong spin (the electron counts) or in the wrong orbital (the β population of the closed
    shell's HOMO must be 0 and its α population 1), a reproduction check that cannot fail (a planted 1 mHa offset must
    be refused); and it carries in-silico §Critical Rules #5's measurement — a 0.3 E_h level shift moves the converged
    LUMO of this doublet by noise, not by 0.3 E_h. CANNOT catch: the Os(III) case — `hole_os_fraction` is 0 here by
    construction — nor the instability-following branch (water is stable), and no start guarantees the ground state.
    """
    pytest.importorskip("pyscf")
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.dft_utils import dft_singlepoint
    m = _load_21e()
    water = [("O", (0.0, 0.0, 0.117)), ("H", (0.0, 0.757, -0.467)), ("H", (0.0, -0.757, -0.467))]
    row = dft_singlepoint(water, charge=0, spin=0, xc="b3lyp")
    dm0, start = m._doublet_start(water, tmp_path / "a.chk", row, "b3lyp", None, 1e-6, charge=0)
    assert abs(start["os2_rerun_delta_Ha"]) <= 1e-6 and start["hole_os_fraction"] == 0.0
    from pyscf import gto
    s1e = gto.M(atom=water, basis="6-31g(d)").intor_symmetric("int1e_ovlp")
    assert [round(float((d * s1e).sum()), 6) for d in dm0] == [5.0, 4.0], "start is not N_α = N_β + 1 = 5 + 4"
    from pyscf.scf import chkfile
    mo, occ = chkfile.load(str(tmp_path / "a.chk"), "scf/mo_coeff"), chkfile.load(str(tmp_path / "a.chk"), "scf/mo_occ")
    homo = mo[:, int((occ > 0).nonzero()[0][-1])]
    pop = [float(homo @ s1e @ d @ s1e @ homo) for d in dm0]
    assert abs(pop[0] - 1.0) < 1e-8 and abs(pop[1]) < 1e-8, f"the hole is not the β HOMO: α {pop[0]:.3g}, β {pop[1]:.3g}"
    ion = dft_singlepoint(water, charge=1, spin=1, xc="b3lyp", dm0=dm0, stability=True)
    assert ion["converged"] and ion["s2"] < 0.76 and ion["stable_internal"] and ion["aufbau"], ion
    shifted = dft_singlepoint(water, charge=1, spin=1, xc="b3lyp", dm0=dm0, level_shift_open=0.3)
    assert abs(shifted["LUMO_eV"] - ion["LUMO_eV"]) < 0.01, "a level shift biased the converged LUMO (§Critical Rules #5)"
    assert row["aufbau"] and "s2" not in row and "stable_internal" not in row, "closed shell: no <S²>, no stability"
    row_off = dict(row, E_total_Ha=row["E_total_Ha"] + 1e-3)
    with pytest.raises(SystemExit):
        m._doublet_start(water, tmp_path / "c.chk", row_off, "b3lyp", None, 1e-6, charge=0)


# ── lib/os_geometry: the default path IS the committed geometry; the C-min closure realises or refuses ──
_SERIES_SMILES = {   # 21e's SERIES, by the file name each one writes (os_<name>_meim_cl.xyz)
    "nme2": "CN(C)c1ccnc(-c2cc(N(C)C)ccn2)c1", "nh2": "Nc1ccnc(-c2cc(N)ccn2)c1",
    "ome": "COc1ccnc(-c2cc(OC)ccn2)c1", "cl": "Clc1ccnc(-c2cc(Cl)ccn2)c1", "no2": "O=[N+]([O-])c1ccnc(-c2cc([N+](=O)[O-])ccn2)c1",
    "cf3": "FC(F)(F)c1ccnc(-c2cc(C(F)(F)F)ccn2)c1",
    "so2cf3": "O=S(=O)(C(F)(F)F)c1ccnc(-c2cc(S(=O)(=O)C(F)(F)F)ccn2)c1",
}
# ⛔ Not byte for byte, and not under just any RDKit. The files were written by the RDKit of the recorded env; the
# lock pins a DIFFERENT RDKit on linux-64 than on osx-arm64, and under CI's one the MMFF relaxation lands the first
# four series complexes up to 0.98 mÅ apart (noise) but puts the CF3 rotor 1.53 Å off (another rotamer) — CI runs
# 37046079480 and 37050045254, 2026-10-02. So the pin runs only under the RDKit that wrote the files, read from the
# record (never typed here), and within it 0.01 Å absorbs platform noise: ten times above the noise, seventeen
# times below the smallest real edit it exists to catch (`close_chelate` leaking into the default path, 0.17–0.21 Å).
_GEOM_TOL_A = 0.01
_RECORD_ENV = REPO / "tools/in_silico/environment.computed.explicit.txt"


def _recorded_rdkit_version():
    m = re.search(r"/rdkit-(\d+\.\d+\.\d+)-", _RECORD_ENV.read_text(encoding="utf-8"))
    return m.group(1) if m else None


def test_os_builder_default_path_reproduces_the_committed_geometry():
    """The shared builder must still write the geometries the osmium caches were computed on (within _GEOM_TOL_A).

    CAN catch: an edit that leaks into the default path (the `close_chelate` switch, a constant, the clash
    diagnostics) · an RDKit/MMFF change that moves the embedded ligands by more than the tolerance · any change
    of element order or atom count — then every 21e/21f/34/34b cache stands on a geometry the builder no longer
    makes, and the lock base of C-min (`76`) with it.
    CANNOT catch: a shift below 0.01 Å — indistinguishable here from cross-platform MMFF noise (see _GEOM_TOL_A) ·
    anything at all under an RDKit other than the recorded one: it SKIPS there (CI's linux-64 lock included), because
    a different RDKit is a different builder and can land a rotor elsewhere — the record env carries this pin ·
    the 34 k-water files (34 places the waters) or 34b's dmbpy forms (not written to disk) — their base complexes
    are the bpy chloro, aqua and bis-Im cases below.
    """
    rdkit = pytest.importorskip("rdkit")
    recorded = _recorded_rdkit_version()
    assert recorded, f"no rdkit build in {_RECORD_ENV.name} — the gate below would have nothing to compare"
    if rdkit.__version__ != recorded:
        pytest.skip(f"the committed geometries were written by RDKit {recorded}; under RDKit {rdkit.__version__} "
                    "this pin would measure RDKit, not the builder (see _GEOM_TOL_A)")
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib import os_geometry as g
    meim, water = ("ligand", g.MEIM_SMILES, "N"), ("ligand", g.WATER_SMILES, "O")
    smiles = {**_SERIES_SMILES, "dmbpy": g.DMBPY_SMILES, "bpy": g.BPY_SMILES, "dcbpy": g.DCBPY_SMILES}
    cases = [(f"os_{n}_meim_cl.xyz", {"bpy_smiles": s}) for n, s in smiles.items()]
    cases += [("os_dmbpy_meim_cl_full.xyz", {"bpy_smiles": g.DMBPY_SMILES}),
              ("os_bpy_meim2.xyz", {"bpy_smiles": g.BPY_SMILES, "axial": (meim, meim), "axial_twists": (45.0, 30.0)}),
              ("os_bpy_meim_h2o.xyz", {"bpy_smiles": g.BPY_SMILES, "axial": (meim, water)})]
    for fn, kw in cases:
        atoms, _ = g.build_os_complex(**kw)
        ref = [line.split() for line in (LIGANDS / fn).read_text(encoding="utf-8").splitlines()[2:]]
        assert [s.strip() for s, _ in atoms] == [r[0] for r in ref], (
            f"the builder no longer writes the atoms of {fn} — the osmium caches stand on the committed geometry")
        worst = max(math.dist(p, tuple(float(x) for x in r[1:4])) for (_, p), r in zip(atoms, ref, strict=True))
        assert worst <= _GEOM_TOL_A, (
            f"the builder no longer writes {fn} — the osmium caches stand on the committed geometry "
            f"(worst atom {worst:.4f} Å off, tolerance {_GEOM_TOL_A} Å)")


def test_os_builder_closed_chelate_realises_the_targets_or_refuses(monkeypatch):
    """`close_chelate=True` (C-min) lands both chelates on OS_N_BPY at BITE_DEG — and its gate can fail.

    CAN catch: a closure that stops reaching the targets (the RDKit minimiser reporting convergence with the
    restraint unmet — seen 2026-10-02) · a gate that no longer refuses (asserted with an impossible band).
    CANNOT catch: whether the closed geometry is a better model than the default one — only `76` prices it.
    """
    pytest.importorskip("rdkit")
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib import os_geometry as g
    _, info = g.build_os_complex(bpy_smiles=g.DMBPY_SMILES, close_chelate=True)
    assert all(abs(d - g.OS_N_BPY) <= g.CLOSE_TOL_A for d in info["os_n_bpy_A"]), info["os_n_bpy_A"]
    assert all(abs(b - g.BITE_DEG) <= g.CLOSE_TOL_DEG for b in info["bite_deg"]), info["bite_deg"]
    monkeypatch.setattr(g, "CLOSE_TOL_A", 1e-9)
    with pytest.raises(ValueError, match="closed chelate not realised"):
        g.build_os_complex(bpy_smiles=g.DMBPY_SMILES, close_chelate=True)


def test_energy_ladder_png():
    path = DFT / "energy_ladder.png"
    assert path.exists()
    assert path.stat().st_size > 10_000, "energy_ladder.png too small"


# ── Kinetics cache ──

def test_kinetics_delta_t_json():
    path = KINETICS / "delta_t_lookup.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert "parameters" in data
    assert "reference_points" in data
    assert data["parameters"]["BASELINE_DELTA_T_S"] == 60


def test_kinetics_eis_json():
    path = KINETICS / "eis_model.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert "parameters" in data
    rct = data["parameters"]["Rct_ohm"]
    assert 10 < rct < 1000, f"Rct out of range: {rct}"


def test_kinetics_monte_carlo_json():
    path = KINETICS / "monte_carlo.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert data["n_samples"] == 10_000
    assert len(data["scenarios"]) >= 4


ALLOY_SKUS = ("Ti-6Al-4V", "Ti-6Al-7Nb", "CP-Ti-Gr4", "beta-Ti-13Nb-13Zr", "Ta", "Ti-15Zr")


def test_gusak_degradation_multi_alloy():
    """Script 51 outputs V/Al/Nb/Zr release per candidate alloy (Stage-2 bake-off, 01_02 §2.5).
    Sanity: 4V control ≈ 1.12 µg/cm²/yr V (the in-silico baseline — order of magnitude on an unsourced D, 01_02 §2.5);
    every V-free alloy releases ~0. Nb and Zr: a channel per alloy, zero where the alloy carries none, and — their D
    being a placeholder equal to D(V) — the same release per wt% as V. CAN catch a lost channel or a channel fed by
    the wrong element's wt%; CANNOT say the placeholder D is right, which only a measured release can."""
    path = KINETICS / "gusak_degradation.json"
    if not path.exists():
        pytest.skip("gusak_degradation.json not computed")
    from lib.constants import ALLOY_PROPERTIES
    kd = json.loads(path.read_text())["kirkendall_diffusion"]
    for alloy in ALLOY_SKUS:
        assert alloy in kd, f"missing alloy {alloy}"
        assert "20" in kd[alloy] and "V_ug_cm2" in kd[alloy]["20"]
        for el in ("Nb", "Zr"):
            wt = ALLOY_PROPERTIES[alloy][f"{el}_wt"]
            assert (kd[alloy]["20"][f"{el}_ug_cm2_placeholder_D"] > 0) == (wt > 0), (alloy, el)
            v_per_wt = (kd["Ti-6Al-4V"]["20"]["V_ug_cm2"] / ALLOY_PROPERTIES["Ti-6Al-4V"]["V_wt"]
                        * ALLOY_PROPERTIES[alloy]["rho_kg_m3"] / ALLOY_PROPERTIES["Ti-6Al-4V"]["rho_kg_m3"])
            assert abs(kd[alloy]["20"][f"{el}_ug_cm2_placeholder_D"] - v_per_wt * wt) <= 1e-5 + 1e-6 * v_per_wt * wt, (alloy, el)
    assert abs(kd["Ti-6Al-4V"]["1"]["V_ug_cm2"] - 1.12) < 0.05   # control baseline preserved
    for vfree in ALLOY_SKUS[1:]:
        assert kd[vfree]["20"]["V_ug_cm2"] == 0.0, f"{vfree} should release zero V"
    assert kd["Ti-6Al-7Nb"]["20"]["Al_ug_cm2"] > 0       # 7Nb still leaks Al (phytotoxic)
    assert kd["CP-Ti-Gr4"]["20"]["Al_ug_cm2"] == 0.0     # zero-Al alloy doesn't


def test_edlc_endurance_hours_hw37():
    """Script 51 (HW.37) outputs EDLC endurance-hours life for both SKUs the canon has
    weighed (Eaton KR-5R5H474-R, KEMET FG0H474ZF — `02_01 §3` поз.3; the KEMET one is
    geometrically EXCLUDED since ⚖️ 2026-09-22, kept because this electrical equivalence
    is what let geometry decide). Sanity: confirms the
    2026-09-09 hand-calc (00_07 HW.37) — life@25°C ≈ 2.6 yr / life@10°C ≈ 7.3 yr at
    full 5.5V — and that the voltage-derating bracket's optimistic coefficient always
    yields MORE years than the conservative one (smaller dV-per-doubling accelerates
    life faster as voltage drops below rated)."""
    path = KINETICS / "gusak_degradation.json"
    if not path.exists():
        pytest.skip("gusak_degradation.json not computed")
    edlc = json.loads(path.read_text())["edlc_endurance_hours"]
    for sku in ("Eaton_KR-5R5H474-R", "KEMET_FG0H474ZF"):
        assert sku in edlc, f"missing SKU {sku}"
        at_rated = edlc[sku]["at_rated_voltage"]
        assert abs(at_rated["25.0"]["life_years"] - 2.6) < 0.1
        assert abs(at_rated["10.0"]["life_years"] - 7.3) < 0.1
        for v_target, row in edlc[sku]["voltage_derating"].items():
            assert row["optimistic_yr"] > row["conservative_yr"], (
                f"{sku}@{v_target}V: optimistic coefficient should out-live conservative"
            )


def test_capsule_thermal_envelope_hw37():
    """Script 71 (HW.37): the capsule thermal envelope against the surviving EDLC's operating rating.

    Every flag and every judging clause is DERIVED from the rows, and these checks fail when one stops
    matching them (in-silico §When Modifying #5/#8): the exceedance flag and the margins, the physical
    signs the lump model must keep, Jensen on the aging average, the reference points against `51`'s
    own cache, and the verdict's «every case» sentence against every case. What they CANNOT catch is a
    wrong input bracket — absorptance, convection correlation, sky view, climate — which the cache
    declares as its own and a field reading has to settle.
    """
    path = THERMAL / "capsule_envelope.json"
    if not path.exists():
        pytest.skip("capsule_envelope.json not computed")
    d = json.loads(path.read_text())
    r_max = d["rating_c"]["edlc_operating_max"]
    r_min = d["rating_c"]["edlc_operating_min"]
    hot = d["hot_bound"]
    sens = d["hot_bound_h_c_sensitivity"]["sunlit_still_air"]
    rows = [r for by_a in hot.values() for by_k in by_a.values() for r in by_k.values()] + list(sens.values())
    # 1. The flag and every margin are the rows' own arithmetic; absorbed sun can only heat the lump.
    assert d["rating_exceeded"] == any(r["t_cap_max_c"] > r_max for r in rows)
    for r in rows:
        assert abs(r["margin_to_rating_k"] - (r_max - r["t_cap_max_c"])) <= 0.051
    for by_a in hot.values():
        for by_k in by_a.values():
            for r in by_k.values():
                assert r["t_cap_max_c"] >= r["t_air_c"] - 0.05, "the lump came out colder than air in the sun"
    # 2. Signs the model must keep: hotter with α at fixed wind, cooler with wind at fixed α, the beam
    #    never cooling the capsule, and a smaller h_c never cooling it either.
    alphas = sorted(hot["sunlit"], key=float)
    ks = sorted(hot["sunlit"][alphas[0]], key=float)
    assert ks[0] == "0.0", "the still-air BOUND is missing from the wind bracket"
    for case in ("sunlit", "shaded"):
        for k in ks:
            by_alpha = [hot[case][a][k]["t_cap_max_c"] for a in alphas]
            assert by_alpha == sorted(by_alpha), f"{case} k={k}: hotter at lower α"
        for a in alphas:
            by_wind = [hot[case][a][k]["t_cap_max_c"] for k in ks]
            assert by_wind == sorted(by_wind, reverse=True), f"{case} α={a}: hotter in wind"
    for a in alphas:
        for k in ks:
            assert hot["sunlit"][a][k]["t_cap_max_c"] >= hot["shaded"][a][k]["t_cap_max_c"]
    for a, r in sens.items():
        assert r["t_cap_max_c"] >= hot["sunlit"][a]["0.0"]["t_cap_max_c"], f"h_c × scale cooled α={a}"
    # 3. Aging: an exponential rate's effective temperature is never below the plain mean (Jensen), the
    #    radome never ages the EDLC slower than open air, and the reference points reproduce `51`.
    aging = d["aging"]
    for name, r in aging.items():
        assert r["t_eff_c"] >= r["mean_c"], f"{name}: T_eff below the mean — not a doubling-rule average"
        life = r["life_at_ratified_vbat_ov"]
        assert life["optimistic_yr"] > life["conservative_yr"]
        if name != "air":
            assert r["t_eff_c"] >= aging["air"]["t_eff_c"], f"{name}: the radome aged the EDLC slower than air"
    own = json.loads((KINETICS / "gusak_degradation.json").read_text())[
        "edlc_endurance_hours"]["Eaton_KR-5R5H474-R"]["ratified_vbat_ov"]
    for t, ref in d["aging_reference_points_02_03"].items():
        for end in ("conservative_yr", "optimistic_yr"):
            assert abs(ref[end] - own[f"{float(t):.1f}"][end]) <= 0.051, f"{t} °C {end}: 71 and 51 disagree"
    # 4. The verdict's «every case» sentence, held to every case it summarises.
    cons = [r["life_at_ratified_vbat_ov"]["conservative_yr"] for r in aging.values()]
    opt = [r["life_at_ratified_vbat_ov"]["optimistic_yr"] for r in aging.values()]
    rests_on_coefficient = "rests on the vendor voltage coefficient alone" in d["verdict_aging"]
    assert rests_on_coefficient == (max(cons) < 20.0 <= min(opt))
    # 5. Cold side: hours under the floor exist only if the coldest hour is under it.
    cold = d["cold_hours_below_edlc_floor"]
    assert (cold["hours"] > 0) == (cold["coldest_air_c"] < r_min)
    assert cold["days"] <= cold["hours"]


def test_lame_alloy_comparative():
    """Script 50 outputs a per-alloy comparative (E + CTE-mismatch stress, 01_02 §2.5).
    Sanity: all 6 present; β-Ti lower-E than 4V; press-fit alloy-robust (PEEK SF ≥ 3)."""
    path = KINETICS / "thermal_stress_lame.json"
    if not path.exists():
        pytest.skip("thermal_stress_lame.json not computed")
    cmp = json.loads(path.read_text())["alloy_comparative"]
    for alloy in ALLOY_SKUS:
        assert alloy in cmp, f"missing alloy {alloy}"
        assert cmp[alloy]["peek_safety_factor"] >= 3.0, f"{alloy} press-fit SF < 3"
    assert cmp["beta-Ti-13Nb-13Zr"]["E_GPa"] < cmp["Ti-6Al-4V"]["E_GPa"]   # β-Ti is the low-E lever


def test_oxide_det_per_alloy():
    """Script 53: per-alloy native-oxide DET feasibility (Ta DET-risk pre-coin, 01_02 §2.5).
    Sanity: 4V baseline 1.0; Ta = DET RISK (wider Ta2O5); Au = ceiling (no oxide)."""
    path = KINETICS / "oxide_det_per_alloy.json"
    if not path.exists():
        pytest.skip("oxide_det_per_alloy.json not computed")
    d = json.loads(path.read_text())
    for alloy in ("Ti-6Al-4V", "Ta", "Au-coating", "beta-Ti-13Nb-13Zr"):
        assert alloy in d, f"missing {alloy}"
    assert d["Ti-6Al-4V"]["det_vs_tio2"] == 1.0          # baseline self-ref
    assert d["Ta"]["det_flag"] == "RISK"                 # Ta2O5 wider+thicker → DET risk
    assert d["Au-coating"]["det_flag"] == "ceil"         # metallic, no oxide → DET ceiling
    assert d["Ta"]["det_vs_tio2"] > d["beta-Ti-13Nb-13Zr"]["det_vs_tio2"]  # Ta worst-case


def test_gdl_breakthrough():
    """Script 57: PTFE-GDL liquid-entry pressure + O2 budget (01_04 §5.3/§5.6, HW.25).

    Sanity is DIRECTIONAL, not numeric — the exact values are pinned by test_doc_cache_sync:
    the spec must clear its own acceptance bar; the prescribed water column must be unable to
    challenge the widest specified pore (that is the finding, not an accident); and O2 transport
    must not be the bottleneck anywhere in the canon pore window.
    """
    path = KINETICS / "gdl_breakthrough.json"
    if not path.exists():
        pytest.skip("gdl_breakthrough.json not computed")
    d = json.loads(path.read_text())
    bench = d["bench_inversion"]
    assert d["worst_case_spec"]["margin_vs_acceptance_x"] > 1.0        # spec clears its own bar
    assert bench["pore_failed_by_apparatus_um"] > max(d["inputs"]["pore_spec_um"])
    assert bench["canon_prose_optimism_x"] > 1.0                       # ">15 um" was optimistic
    assert bench["pore_demanded_by_acceptance_um"] < bench["canon_prose_upper_pore_um"]
    assert min(v["margin_x"] for v in d["o2_budget"]["per_pore"].values()) > 100.0
    # a hydrophobic pore must get HARDER to wet as it narrows and as the contact angle grows
    lep = d["liquid_entry_pressure"]
    assert lep["0.2um"]["CA_110"]["pressure_Pa"] > lep["1.0um"]["CA_110"]["pressure_Pa"]
    assert lep["1.0um"]["CA_120"]["pressure_Pa"] > lep["1.0um"]["CA_110"]["pressure_Pa"]

    # The RATIFIED flood (02_02 §3.3) stands BESIDE the hand-set set, never inside it. CAN catch: the
    # flood folded into field_pressures_Pa (the headline would then be recomputed from it and move),
    # a head not equal to ρ·g·depth of the cache's own inputs, a threshold not on the Young–Laplace
    # inverse, a flood threshold that does not sit between the hand-set one and the spec floor.
    # CANNOT catch: a wrong DEPTH — 1.5 m mirrors canon, and the doc↔code value pin was refused (HW.45).
    inp = d["inputs"]
    field = d["field_pressures_Pa"]
    flood = d["ratified_flood_scenario"]
    headline = d["theta_at_which_worst_field_load_breaks_through_deg"]

    def theta_at(p_pa, pore_key):
        pore_m = float(pore_key.removesuffix("um")) * 1e-6
        return math.degrees(math.acos(-min(p_pa * pore_m / (4.0 * inp["gamma_water_N_m"]), 1.0)))

    assert flood["pressure_Pa"] > max(field.values())
    assert abs(flood["pressure_Pa"] - inp["rho_water_kg_m3"] * inp["g_m_s2"]
               * flood["immersion_depth_m"]) < 1e-6
    floor = min(inp["contact_angle_deg"])
    for pore, th_flood in flood["theta_at_which_it_breaks_through_deg"].items():
        assert abs(headline[pore] - theta_at(max(field.values()), pore)) < 1e-9   # headline = hand-set max
        assert abs(th_flood - theta_at(flood["pressure_Pa"], pore)) < 1e-9
        assert 90.0 < headline[pore] < th_flood < floor
    assert flood["spec_worst_case_head_over_flood_x"] > 1.0                  # the spec holds the flood
    assert flood["acceptance_criterion_below_flood"] is (
        d["bench_inversion"]["acceptance_column_m"] < flood["immersion_depth_m"])


def test_thermal_install_field():
    """Script 58: 2D axisymmetric thermal-install field + the orphan-cache generator (HW.6).

    Three things must hold, and each fails loudly if the model regresses:
      1. the committed thermal_penetration.json is still reproduced inside its pinned tolerance;
      2. the solver still conserves enthalpy in a closed box and still matches the independent
         1D march — an unverified solver is a claim, not a measurement;
      3. the DISCRIMINATING pair survives: the canon procedure cooks the cambium, selective deep
         heating does not. A model where both pass (or both fail) is measuring nothing.
    """
    path = REPO / "tools/in_silico/cache/mechanical/thermal_install_field.json"
    if not path.exists():
        pytest.skip("thermal_install_field.json not computed")
    d = json.loads(path.read_text())
    leg = d["legacy_cache_regeneration"]
    assert leg["reproduced"] is True
    assert abs(leg["delta_time_s"]) / 60.0 < 0.1       # the tolerance test_doc_cache_sync pins
    assert abs(leg["delta_alpha_m2s"]) * 1e6 < 0.01
    ver = d["numerical_controls"]["solver_verification"]
    assert ver["passed"] is True
    assert ver["closed_box_enthalpy_drift"] < 1e-9
    for axis in ("closed_box_enthalpy_drift", "column_2d_vs_1d_delta_C",
                 "radial_annulus_max_err_C", "two_layer_interface_max_err_C"):
        assert axis in ver, f"solver verification lost the {axis} axis"
    canon = d["scenarios"]["S1a_uniform_Ti_200C"]
    selective = d["scenarios"]["S2_anode_only_200C"]
    gate = d["thresholds_C"]["cambium_gate"]
    assert canon["cambium_peak_C"] > gate               # the finding
    assert selective["cambium_peak_C"] < gate           # ... and its control
    assert canon["thermal_wound_dia_50C_mm"] > d["geometry_mm"]["sleeve_od_wound"]
    # the PEEK break must still block the axial path it was designed to block
    assert d["scenarios"]["S1b_flange_only_200C"]["cauterisation_dwell_s"] == 0.0
    # 🔴 The whole-domain metric exists because a cambium-only one let the "surviving" variant
    # score a clean zero while cooking a wider ring. Pin BOTH halves of that lesson.
    assert canon["killed_living_dia_anywhere_mm"] >= canon["thermal_wound_dia_50C_mm"]
    assert selective["thermal_wound_dia_50C_mm"] == 0.0
    assert selective["killed_living_dia_anywhere_mm"] > 0.0
    # duration is the axis the canon inherited from the model this script supersedes: damage must
    # rise monotonically with the hold, and a short hold must exist that stays under the gate.
    holds = d["duration_sweep"]
    assert [h["hold_s"] for h in holds] == sorted(h["hold_s"] for h in holds)
    peaks = [h["cambium_peak_C"] for h in holds]
    assert peaks == sorted(peaks), "cambium damage must grow with hold length"
    assert any(h["cambium_peak_C"] < gate and h["cauterisation_dwell_s"] > 0 for h in holds), \
        "the constructive half of the finding — a hold that coagulates and spares — is gone"


def test_bus_mechanical_liner_axial_thermal():
    """Script 55 (HW.34): the liner's axial thermal term stays tied to the geometry it claims.

    ⛔ This docstring used to say the axial term «must stay the LARGER of the two» — which is what the
    body's own comment retracts two lines down as a comparison of reference LENGTHS dressed as a
    mechanical finding. The docstring outlived the assertion it described, which is the same class the
    block below pins: a file disagreeing with itself while every individual sentence reads fine.
    What is checkable is that the length is the RATIFIED one (channel + protrusion, ⚖️ 2026-09-12) and
    that the ΔT sweep keeps its points.
    """
    path = MECHANICAL / "bus_mechanical.json"
    if not path.exists():
        pytest.skip("bus_mechanical.json not computed")
    ax = json.loads(path.read_text())["clearance_regime"]["axial_thermal"]
    by_dt = ax["differential_axial_um_by_dT_K"]
    assert ax["alpha_peek_1K"] > ax["alpha_ti_1K"], "PEEK must be the faster-expanding half"
    # ⛔ Two assertions stood here and both were vacuous (2026-09-12, adversarial review): the ΔT
    #    linearity is true BY CONSTRUCTION of the dict comprehension, and «axial > radial» reduces
    #    to `17 > 1.30`, i.e. it compares two reference LENGTHS while both terms carry the SAME
    #    strain. That second one was worse than useless — it dressed a unit ratio as a mechanical
    #    finding. What is checkable is that the two terms stay tied to the geometry they claim.
    assert ax["liner_length_mm"] > 0.0
    assert set(by_dt) == {"20", "40", "60", "80"}, "the ΔT sweep lost or gained a point"
    # ⛔ The axial ⚖️ was RATIFIED 2026-09-12 (01_01 §1.4) and this key called itself an assumption
    #    for hours afterwards, feeding canon a length that excluded the ratified protrusion. A flag
    #    that says «assumed» about a settled dimension is worse than no flag: it tells the reader the
    #    number is soft when it is the spec.
    assert ax["liner_length_is_ratified"] is True
    assert "protrusion" in ax["liner_length_provenance"], "the length stopped citing the CEM field"


def test_bus_mechanical_interference_window():
    """Script 55 (HW.34): the liner↔wire fit is BOUNDED, and its two vendor inputs stay ABSENT.

    The 2026-09-11 direction verdict asserts the tube is tight on the wire; every stiffness bound and
    the whole wear axis inherit that sentence, and no interference existed anywhere in the tree until
    this block. Its honesty condition is the same as the weld seam's: nobody may quietly type a
    tolerance into a sentinel and let the corpus read it as measured.
    """
    path = MECHANICAL / "bus_mechanical.json"
    if not path.exists():
        pytest.skip("bus_mechanical.json not computed")
    iw = json.loads(path.read_text())["interference_window"]
    # 1. Honesty: both vendor bands absent, and µ declared a sweep rather than a value.
    vendor = iw["vendor_inputs_measured"]
    assert vendor["liner_bore_tolerance_um"] is None, "a tube tolerance was typed in — NOT MEASURED"
    assert vendor["wire_od_tolerance_um"] is None, "a wire tolerance was typed in — NOT MEASURED"
    assert iw["axial_friction_lock"]["mu_is_swept_not_measured"] is True
    # 2. The window must be a window. A non-positive one would mean the geometry admits no fit at
    #    all, which is a finding — not something to report as a budget.
    assert iw["window_radial_um"] > 0.0
    assert iw["floor"]["radial_um"] < iw["ceiling"]["radial_um"]
    # 3. The free-outer premise of the Lamé model, CHECKED rather than assumed: the tube's OD grows
    #    under the fit, and if that growth ever closed the channel play the whole model would be the
    #    wrong one (a contained cylinder, not a free-outer sleeve).
    #    ⚠️ Honest about when this can fire (adversarial read 2026-09-18): on the BORE-carried rows the play
    #    never falls below play_zero (k < 1), so those rows cannot red it; the WIRE-carried rows can — they are
    #    the ones where the growth is not paid back — and they are why this assertion is not vacuous.
    play = iw["od_growth_eats_channel_play"]
    rows = play["rows"]
    assert rows, "the play coupling lost its rows"
    assert all(r["outer_surface_still_free"] for r in rows), \
        "OD growth closed the channel play — free-outer Lamé no longer describes this pair"
    assert all(r["channel_radial_play_um"] > 0.0 for r in rows)
    # 3a. BOTH attributions of the interference are published, and they bracket the zero-interference play
    #     the way the physics says: k in (0, 1); the bore-carried ceiling ABOVE play_zero, the wire-carried
    #     ceiling BELOW it; the published range is the rows' own extremes. Dropping the wire rows (the
    #     one-sided reading that shipped first) or flipping a sign reds here.
    k = play["k_od_growth_per_interference"]
    assert 0.0 < k < 1.0, f"k = {k}: a free-outer sleeve pays back less than all of a bore-carried interference"
    by_at = {r["at"]: r["channel_radial_play_um"] for r in rows}
    assert {"ceiling", "ceiling (wire carries)", "floor (wire carries)"} <= set(by_at), \
        "one attribution of the interference is missing — the play is set mostly by the WIRE"
    p0 = play["nominal_radial_play_um"]
    assert by_at["ceiling"] > p0 > by_at["ceiling (wire carries)"], \
        "the two attributions must bracket play_zero at the window ceiling"
    assert play["play_range_radial_um"] == [min(by_at.values()), max(by_at.values())]
    # 4. 🔴 The headline — and this REPLACED a tautology (adversarial review 2026-09-12). It used to
    #    read `nominal_fit_is_zero_interference is True`, computed as `abs(x - x) < 1e-9` from a
    #    constant defined AS the rod diameter: identically true, unfalsifiable from the model side,
    #    i.e. the repo's own «приклад, що не може ВПАСТИ». What is checkable is the honesty of the
    #    INPUT: the tube's bore nominal is specified NOWHERE (canon freezes the wall and says the
    #    supplier holds ID/OD), so the sentinel must stay absent and the window must declare itself
    #    computed at an assumption. Typing a bore nominal in flips both and reds this.
    # ⚖️ 2026-09-18 (00_07 HW.34) the nominal was RATIFIED — bore = wire − 11.41 µm, wall 0.15, fitted hot —
    #    so the honesty condition flips: the sentinel must now carry exactly the ratified value, and that
    #    value must land INSIDE the window the block recomputes at that very bore. Reverting to None, or a
    #    typed bore whose interference falls outside [floor, ceiling], reds this.
    wire = iw["pair_mm"]["wire_dia"]
    assert iw["bore_nominal_specified_mm"] == pytest.approx(wire - 11.41e-3, abs=1e-9), \
        "the bore nominal is not the ratified wire − 11.41 µm"
    assert iw["bore_nominal_is_assumed"] is False
    nominal_radial_um = (wire - iw["bore_nominal_specified_mm"]) * 1e3 / 2.0
    assert iw["floor"]["radial_um"] <= nominal_radial_um <= iw["ceiling"]["radial_um"], \
        "the ratified nominal interference sits outside the window recomputed at its own bore"
    # ⚠️ The next line is an ARITHMETIC-CONSISTENCY check between two cache keys computed from the same
    #    variables — it cannot catch a modelling error, only a mis-wired key (adversarial read 2026-09-18).
    assert iw["nominal_vs_window_centre_diametral_um"] == pytest.approx(
        2.0 * nominal_radial_um - iw["required_nominal_offset_diametral_um"], abs=0.01)


def test_gusak_press_fit_flags_follow_their_own_numbers():
    """Script 51 (HW.3): each temperature row judges TWO mechanisms, and each flag must follow its number.

    ⛔ A single `safe` judged the hoop stress at the band MAX only, so +40 °C read «safe» while the band
    MIN had already opened to a clearance. The flags are split; this pins that neither can drift off the
    quantity it is computed from, and that the single flag does not come back.
    """
    path = KINETICS / "gusak_degradation.json"
    if not path.exists():
        pytest.skip("gusak_degradation.json not computed")
    rows = json.loads(path.read_text())["press_fit_H7s6"]
    for t, r in rows.items():
        assert "safe" not in r, f"{t} °C: a single `safe` flag is back — it hides one mechanism"
        assert r["interference_retained_at_band_min"] == (r["eff_min_um"] > 0), t


# The insulation branch the ⚖️ 2026-09-11 verdict ratified. Named once: the assertions below
# are about THAT branch, not about whichever row happens to be first.
SHIPPED_INSULATION = "PEEK liner 0.15 mm"


def test_bus_mechanical_weld_seam():
    """Script 55 (HW.34): the seam at the root is NOT priced — and the cache says so in every carrier.

    Until 2026-09-14 the block inverted SF_seam = k·SF_wire on ONE fully-reversed stress that no equilibrium
    configuration produces (a free cantilever whose length was a free-shape crossing station) and reported a
    break-even k. The equilibrium gives the root two regimes — a capped fully-reversed drag on a coaxial
    channel, a static MEAN plus the drag under a channel offset — and the model has no mean-stress
    correction. So the honesty condition is DOUBLE: the vendor input stays absent AND no break-even k is
    manufactured in its place. What is pinned is the shape of the inputs a seam acceptance needs (amplitude
    and mean at the root per regime and geometry), their agreement with the regime block, and that the
    regime block's quantifiers follow their own per-µ rows.
    """
    path = MECHANICAL / "bus_mechanical.json"
    if not path.exists():
        pytest.skip("bus_mechanical.json not computed")
    d = json.loads(path.read_text())
    seam, fm, cr = d["weld_seam"], d["fatigue_model"], d["clearance_regime"]
    # 1. Both absences, each with its own flag. ⛔ A typed k reds the first; a re-derived break-even k — the
    #    2026-09-12 shape — reds the second, because its ground (one fully-reversed stress at the root) is gone.
    assert seam["knockdown_k_measured"] is None, "a knockdown was typed in — it is NOT MEASURED"
    assert seam["break_even_k"] is None, "a break-even k came back — the root has two regimes, not one stress"
    assert fm["weld_seam_break_even_k_derived"] is False
    assert fm["weld_seam_geometry_modelled"] is False
    assert fm["weld_seam_sensitivity_modelled"] is True
    assert fm["mean_stress_correction_modelled"] is False
    assert "mean" in seam["break_even_k_not_derived_because"], "the reason stopped naming the mean stress"
    for key in ("per_alloy", "binding_candidate", "span", "span_provenance"):
        assert key not in seam, f"the drift-picture seam bound is back under `{key}`"
    # 2. The inputs a seam acceptance needs: one row per geometry, coaxial mean zero, and the coaxial amplitude
    #    EQUAL to the regime block's cap at the worst swept µ — one quantity, two owners, and they must agree.
    rl = seam["root_section_loading"]
    assert [r["geometry"] for r in rl] == [g["label"] for g in cr["geometries"]]
    for r in rl:
        regime = next(b for b in cr["branches"] if b["geometry"] == r["geometry"] and b["play_side"] == "channel")
        worst = str(max(float(m) for m in regime["by_mu"]))
        assert r["coaxial"]["mean_MPa"] == 0.0
        # 🔴 The coaxial amplitude is a BRACKET with signed ends: the rigid-wall figure is the LOWER end (a
        #    compliant wall raises the root moment), the Ti-bore stop / free cantilever the upper. A single
        #    `amplitude_MPa` — the 2026-09-14 morning shape, read downstream as «≤ 8.04» — is refused.
        assert "amplitude_MPa" not in r["coaxial"], "a single coaxial amplitude is back — the bracket lost its sign"
        assert r["coaxial"]["amplitude_MPa_lower_rigid_wall"] == regime["by_mu"][worst]["sigma_root_MPa_bonded"], r["geometry"]
        assert r["coaxial"]["amplitude_MPa_upper_end"] == regime["by_mu"][worst]["sigma_root_MPa_upper_end"], r["geometry"]
        assert r["coaxial"]["amplitude_MPa_upper_end"] >= r["coaxial"]["amplitude_MPa_lower_rigid_wall"]
        assert r["coaxial"]["bound"].startswith("the rigid-wall figure is the LOWER end")
        assert r["offset"]["mean_MPa_per_um_past_play"] > 0.0
        assert r["offset"]["amplitude_MPa_max_over_swept_offsets"] == max(a["amplitude_MPa"] for a in r["offset"]["by_offset"])
        assert r["offset"]["bound"].startswith("rigid-wall figures: the static mean is an UPPER bound")
        assert r["peak_moment_at_root_in_every_solve"] is True
    # 3. The regime block: the QUANTIFIER is derived from the per-µ rows, the station is the exit when touched
    #    down, the mouth is never reached coaxially, and every row carries the SIGN of its rigid-wall figure with
    #    an upper end inside [rigid wall, free cantilever]. ⛔ «free cantilever (never reaches the wall)» once
    #    stood on branches that touched on three of four µ, because an else-branch read «not every µ» as «no µ».
    n_mu = len(cr["branches"][0]["by_mu"])
    for br in cr["branches"]:
        touch = [mu for mu, v in br["by_mu"].items() if v["touches_down"]]
        assert [str(m) for m in br["touches_down_on_mus"]] == touch, br["branch"]
        assert br["touches_down_on_every_mu"] == (len(touch) == n_mu), br["branch"]
        assert br["regime"].startswith("touches down at the EXIT on every") == br["touches_down_on_every_mu"], br["branch"]
        assert br["regime"].startswith("free cantilever on every") == (not touch), br["branch"]
        assert br["mouth_reached_on_any_mu"] is False
        assert br["coaxial_root_bound"].startswith("LOWER end"), br["branch"]
        for v in br["by_mu"].values():
            assert v["contact_station_mm"] in (None, br["contact_station_when_touched_down_mm"])
            assert (v["contact_station_mm"] is not None) == v["touches_down"]
            assert abs(v["deflection_at_mouth_um"]) < br["radial_play_mm"] * 1e3, "the mouth was reached coaxially"
            assert v["sigma_root_MPa_bonded"] <= v["sigma_root_MPa_upper_end"] <= v["sigma_root_MPa_free_cantilever"] + 0.01, br["branch"]
            assert v["upper_end_is"].startswith(("Ti-bore stop", "free cantilever"))
    shipped = [b for b in cr["branches"] if b["play_side"] == "channel"]
    assert cr["shipped_exit_contact_forced_on_every_mu_and_geometry"] == all(b["touches_down_on_every_mu"] for b in shipped)
    for g in cr["by_geometry"]:
        rows = [b for b in cr["branches"] if b["geometry"] == g["geometry"]]
        assert g["forced_on_every_mu_branches"] == [b["branch"] for b in rows if b["touches_down_on_every_mu"]]
        assert g["free_on_every_mu_branches"] == [b["branch"] for b in rows if not b["touches_down_on_mus"]]
    assert SHIPPED_INSULATION in cr["by_geometry"][0]["forced_on_every_mu_branches"]
    # 4. The §2 supported column against the BRACKET: the sign of the rigid-wall comparison and the column's
    #    position in [rigid, upper] are derived from the numbers, never typed; the bracket's lower end IS the
    #    rigid-wall figure and its upper end is not below it.
    sc = cr["supported_column_vs_equilibrium"]
    assert sc["coaxial_cap_bound"].startswith("LOWER")
    assert sc["coaxial_sign"].startswith("against a RIGID wall the column OVERSTATES") == all(g["column_over_cap_nominal"] > 1.0 for g in sc["by_geometry"])
    assert {g["geometry"] for g in sc["by_geometry"]} == {g["label"] for g in cr["geometries"]}
    col = sc["supported_column_sigma_MPa"]

    def position(x, lo, hi):
        return "below the rigid-wall end" if x < lo else ("inside the bracket" if x <= hi else "above the upper end")
    for g in sc["by_geometry"]:
        lo_n, hi_n = g["bracket_MPa_nominal_mu"]
        lo_w, hi_w = g["bracket_MPa_worst_mu"]
        assert lo_n == lo_w == g["coaxial_cap_MPa_bonded"] and hi_n >= lo_n and hi_w >= lo_w, g["geometry"]
        assert g["column_position_nominal_mu"] == position(col["nominal_mu"], lo_n, hi_n), g["geometry"]
        assert g["column_position_worst_mu"] == position(col["worst_mu"], lo_w, hi_w), g["geometry"]
        assert g["binding_alloy_sf_shipped_at_upper_end"] <= g["binding_alloy_sf_shipped_at_rigid_end"]
    # 5. Edge bearing: every branch × geometry; at the reference excess the mouth is the ONLY contact; coaxially
    #    it is never reached; the protrusion floor is NOT typed (its two terms are unmeasured) while the ratified
    #    value is carried from the CEM; the exit contact names no radius.
    edge = cr["edge_bearing"]
    assert {(r["geometry"], r["branch"]) for r in edge["rows"]} == {(b["geometry"], b["branch"]) for b in cr["branches"]}
    for row in edge["rows"]:
        assert row["at_reference"]["contacts"], row["branch"]
        assert all(abs(z["station_mm"] - row["mouth_mm"]) < 1e-9 for z in row["at_reference"]["contacts"]), row["branch"]
        assert row["coaxial_regime_reaches_mouth"] is False
        assert 0.0 < row["at_reference"]["approach_angle_deg"] < 1.0 <= row["lead_in_chamfer_deg"][0]
    ls = edge["liner_start"]
    assert ls["min_protrusion_from_geometry_mm"] is None, "a protrusion floor was typed — its terms are unmeasured"
    assert ls["ratified_protrusion_mm"] == d["assembly_clearance"]["frozen_dims_mm"]["liner_protrusion"]
    for x in edge["exit_contact"]:
        assert x["exit_radius_specified_mm"] is None
        assert x["reaction_N_over_swept_mu_upper_rigid_wall"][0] < x["reaction_N_over_swept_mu_upper_rigid_wall"][1]
        assert x["reaction_bound"].startswith("UPPER")
    # 6. Both markers are OUR OWN numbers, so they must still match the model they came from.
    markers = {m["label"]: m["k"] for m in seam["markers"]}
    assert fm["as_printed_derate"] in markers.values()
    assert fm["wrought_derate"] in markers.values()


def test_bus_mechanical_endurance_ratio_band():
    """Script 55 (HW.34): the fatigue ratio is swept, and the sweep stays what it can honestly be.

    `ENDURANCE_OVER_YIELD` is a band whose midpoint was the only point entering the model, while
    every SF scales linearly with it. Since 2026-09-14 the sweep covers the §2 free-cantilever column
    only — the seam column it carried was priced on the retired drift-picture stress, and no seam k
    exists to sweep — so the pin is that the seam column does NOT come back, beside the bracket.
    """
    path = MECHANICAL / "bus_mechanical.json"
    if not path.exists():
        pytest.skip("bus_mechanical.json not computed")
    d = json.loads(path.read_text())
    band = d["endurance_ratio_band"]
    # 1. The band stays declared-unmeasured and must actually BRACKET the point the model runs at —
    #    a sweep sitting entirely to one side of the operating value is not a sensitivity.
    assert band["band_is_measured"] is False
    assert min(band["band"]) <= band["model_runs_at"] <= max(band["band"])
    assert {r["endurance_over_yield"] for r in band["rows"]} == set(band["band"])
    # 2. No seam column: a break-even k has no ground since the root stopped being one fully-reversed stress.
    for r in band["rows"]:
        assert "seam_break_even_k_worst_corner" not in r, "the seam column is back — it stood on the drift picture"
    assert "our_marker_covers_seam_is_invariant" not in band
    # 3. Monotonicity with a KNOWN sign: the binding SF rises with the ratio.
    ordered = sorted(band["rows"], key=lambda r: r["endurance_over_yield"])
    sfs = [r["binding_sf_unsupported"] for r in ordered]
    assert sfs == sorted(sfs), "the binding SF stopped rising with the fatigue ratio"
    # 4. The invariance flag DERIVED from the rows, never typed — that is the block's whole output.
    assert band["bare_infinite_life_for_all_is_invariant"] == \
        (len({r["unsupported_infinite_life_for_all"] for r in band["rows"]}) == 1)


def test_bus_mechanical_wear_budget():
    """Script 55 (HW.34): the ground the liner STANDS on is bounded at the EQUILIBRIUM stations.

    ⚖️ 2026-09-11 made WEAR the liner's ground; since 2026-09-14 the station is the contact solver's — the
    exit under coaxial drag, the mouth under a channel offset — instead of a prop scanned along a free-shape
    crossing. The honesty condition is the same as the weld seam's and the fit's: nobody may quietly type a
    wear rate, nor a cycle count, and let the corpus read either as measured. What the equilibrium adds is a
    sign the old block could not carry: the touched-down shape does not rotate with the drag, so the coaxial
    sliding is a CEILING and the rigid-kinematics sliding is zero — pinned so the ceiling cannot be quoted as
    a kinematic result.
    """
    path = MECHANICAL / "bus_mechanical.json"
    if not path.exists():
        pytest.skip("bus_mechanical.json not computed")
    d = json.loads(path.read_text())
    w = d["wear_budget"]
    geos = {g["label"]: g for g in d["clearance_regime"]["geometries"]}
    # 1. Honesty on BOTH unmeasured inputs. The rate is the obvious one; the cycle count is the one
    #    that could be faked without looking like a fake, so it must still name its source file.
    assert w["specific_wear_rate_measured"] is None, "a wear rate was typed in — it is NOT MEASURED"
    assert w["duty_source"] and w["duty_source"].endswith("wind_duty_cycle.json"), \
        "the cycle count stopped citing script 62's cache and is now a literal"
    assert len(w["duty_anchors"]) >= 2, "the duty collapsed to a single number — it is a bracket"
    # 2. The flow pressure is SWEPT, and the headline area must be the TIGHTEST of the sweep.
    assert len(w["contact_constraint_factors_swept"]) >= 2
    contact = [r for r in w["rows"] if r["contact"]]
    assert contact, "every branch lost contact — the wear axis has nothing to price"
    for r in contact:
        by_factor = r["area_by_constraint_factor_mm2"]
        assert r["area_material_bound_mm2"] == min(by_factor.values())
        assert 0.0 < r["area_material_bound_mm2"] <= r["area_projected_full_run_mm2"]
        for p in r["by_duty_anchor"]:
            assert 0.0 < p["k_rigid_wall_figure_edge_mm3_per_Nm"] < p["k_rigid_wall_figure_conformal_mm3_per_Nm"]
    # 3. The stations are the equilibrium's, and the coaxial rows carry a sliding BRACKET with signed ends: a zero
    #    rigid-kinematics sliding, the rigid-wall rotation demoted to a figure (it happens out of contact), and a
    #    positive in-contact sliding at the upper end — with the BOUND priced on the upper end. ⛔ A row that calls
    #    the rigid rotation a ceiling again (`slip_ceiling_per_cycle_um`) is refused: quoted without its sign it read
    #    as an upper bound for an afternoon while a compliant contact can slide six times more.
    coax = [r for r in contact if r["regime"] == "coaxial"]
    assert coax
    for r in coax:
        assert r["station_mm"] == geos[r["geometry"]]["pad_mm"], f"{r['geometry']}/{r['branch']}: coaxial station is not the exit"
        assert "slip_ceiling_per_cycle_um" not in r, "the rigid-wall rotation is called a ceiling again"
        assert r["sliding_in_contact_um_rigid_kinematics"] == 0.0
        assert r["out_of_contact_rotation_per_cycle_um_rigid_wall"] > 0.0
        assert r["sliding_in_contact_per_cycle_um_upper"] > 0.0
        assert r["reaction_bound"].startswith("UPPER")
        for p in r["by_duty_anchor"]:
            assert 0.0 < p["k_bound_edge_mm3_per_Nm"] < p["k_bound_conformal_mm3_per_Nm"]
    # The RIGID-wall figure's tight end is µ-invariant per (geometry, branch) — the reaction cancels and the
    # touched-down slope does not depend on the drag; the BOUND's tight end may fall with µ but never rise,
    # because the in-contact sliding at the upper end grows with the drag until the Ti-bore stop saturates it.
    for key in {(r["geometry"], r["branch"]) for r in coax}:
        rows_k = sorted((r for r in coax if (r["geometry"], r["branch"]) == key), key=lambda r: r["mu"])
        rigid = {round(min(p["k_rigid_wall_figure_edge_mm3_per_Nm"] for p in r["by_duty_anchor"]), 15) for r in rows_k}
        assert len(rigid) == 1, f"{key}: the rigid-wall tight end depends on µ — the reaction or the slope crept back in"
        bounds = [min(p["k_bound_edge_mm3_per_Nm"] for p in r["by_duty_anchor"]) for r in rows_k]
        assert all(b >= a * (1 - 1e-9) for a, b in itertools.pairwise(bounds)) or \
            all(a >= b * (1 - 1e-9) for a, b in itertools.pairwise(bounds)), f"{key}: the bound's tight end is not monotone in µ"
    offset = [r for r in contact if r["regime"] == "offset"]
    assert offset, "the offset regime lost its rows"
    for r in offset:
        assert r["station_mm"] == geos[r["geometry"]]["gap_mm"], f"{r['geometry']}: offset station is not the mouth"
        assert r["mouth_loaded_through_the_cycle"] == (min(r["mouth_reaction_N"].values()) > 0.0)
        assert r["reaction_N_upper_rigid_wall"] == max(r["mouth_reaction_N"].values())
        assert r["bound_note"].startswith("rigid-wall FIGURES")
    # 4. 🔴 The SUBSTANTIVE claim canon leaned on — «a thinner wall demands a stricter rate» — holds on the
    #    RIGID-wall figures and NOT on the bounds (the in-contact sliding scales with the polymer's own wall),
    #    and the cache must say so with flags DERIVED from its own rows, never typed.
    by_key = {(r["geometry"], r["branch"], r["mu"]): r for r in coax}
    assert any(b == SHIPPED_INSULATION for _, b, _ in by_key), "the shipped liner branch is absent from the wear table"
    stricter_rigid, stricter_bound = [], []
    for (geo, branch, mu), row in by_key.items():
        peer = by_key.get((geo, SHIPPED_INSULATION, mu))
        if peer is None or branch == SHIPPED_INSULATION or row["wall_allowance_mm"] >= peer["wall_allowance_mm"]:
            continue
        stricter_rigid.append(min(p["k_rigid_wall_figure_edge_mm3_per_Nm"] for p in row["by_duty_anchor"])
                              < min(p["k_rigid_wall_figure_edge_mm3_per_Nm"] for p in peer["by_duty_anchor"]))
        stricter_bound.append(min(p["k_bound_edge_mm3_per_Nm"] for p in row["by_duty_anchor"])
                              < min(p["k_bound_edge_mm3_per_Nm"] for p in peer["by_duty_anchor"]))
    disc = w["branch_discrimination"]
    assert disc["films_stricter_on_rigid_wall_figures"] == (bool(stricter_rigid) and all(stricter_rigid))
    assert disc["films_stricter_on_bounds"] == (bool(stricter_bound) and all(stricter_bound))
    assert disc["films_stricter_on_bounds_anywhere"] == any(stricter_bound)
    assert all(stricter_rigid), "a thinner wall no longer demands a stricter rate on the rigid-wall figures"
    # 5. The second driver is priced so «sway dominates» stays a measurement.
    thermal_max = max(t["sliding_distance_m"] for t in w["thermal_driver"]["rows"])
    sway_max = max(p.get("sliding_distance_m_upper", p.get("sliding_distance_m", 0.0)) for r in contact for p in r["by_duty_anchor"])
    assert w["thermal_driver"]["cycles_per_year_is_swept"] is True
    assert thermal_max * 100.0 < sway_max, "the thermal driver stopped being negligible — re-read §7"
    # 6. The binding row is the SHIPPED branch's worst corner on the BOUND: the tight end ties across the
    #    coaxial µ rows once the Ti-bore stop saturates the sliding (compared at six significant figures — the
    #    rows differ at the 1e-10 level through the solve, and a raw min once picked the row by that noise), and
    #    the tie is broken by the worn-in end (the largest reaction), never by list order.
    assert w["binding"]["branch"] == SHIPPED_INSULATION and w["binding"]["regime"] == "coaxial"
    shipped_rows = [r for r in coax if r["branch"] == SHIPPED_INSULATION]
    expected = min(shipped_rows, key=lambda r: (float(f"{min(p['k_bound_edge_mm3_per_Nm'] for p in r['by_duty_anchor']):.6e}"),
                                               min(p["k_bound_conformal_mm3_per_Nm"] for p in r["by_duty_anchor"])))
    assert (w["binding"]["geometry"], w["binding"]["mu"]) == (expected["geometry"], expected["mu"])


def test_liner_mouth_contact():
    """92 (HW.34 / HW.23): the liner at the channel MOUTH under an axis offset — two elastic patches on the rod.

    CAN catch: the rigid point model drifting from 68's offset or reversing tables, or the no-offset solve leaving
    91's exit row (both re-read from the CURRENT caches); the rigid-limit control past its gate; a static row whose
    give raises the root, whose root or edge peak is not monotone in the entry radius, whose flow ratio is not its
    peak over 55's flow pressures, or whose verdict disagrees with its own grids; a cycle peak below its own static
    value, unresolved beyond the allowed spread, or with a verdict its grids do not give; a «smallest safe radius»
    that is not what its rows say; a rigid swing whose ratio is not its two amplitudes or whose path ends out-swing
    the path; the exit edge's cycle peak drifting from 91's coaxially (re-read from the CURRENT 91 cache), or not rising
    under the offset, or a «smallest safe exit radius» its rows do not give; a within-tolerance list that is not its rows;
    the declared directions failing — the mouth section swinging less than the root coaxially, a mouth nearer the root
    making the offset cheaper; a summary text that stopped quoting its numbers.
    CANNOT catch: plasticity past the flagged peaks, friction, wear, the pad couple, an interference play, the notch
    factor of the wire under either edge, the elastic edge peak over the cycle nearer the play than the cycle block
    reaches, or which offset the stack delivers — the declared ceilings.
    """
    d = json.loads((MECHANICAL / "liner_mouth_contact.json").read_text(encoding="utf-8"))
    d68 = json.loads((MECHANICAL / "bus_contact_equilibrium.json").read_text(encoding="utf-8"))
    d91 = json.loads((MECHANICAL / "liner_exit_contact.json").read_text(encoding="utf-8"))
    ctl, inp, summ = d["controls"], d["inputs"], d["summary"]
    assert ctl["rigid_sharp_vs_68_offset_table"]["max_abs_diff_MPa"] <= 0.051
    assert ctl["rigid_sharp_vs_68_reversing_table"]["max_abs_diff_MPa"] <= 0.051
    c91 = next(c for c in d91["cycle"] if c["r_edge_mm"] == inp["r_exit_mm"] and c["base"] == "bonded" and c["modulus"] == "short-term")
    co = ctl["no_offset_vs_91_exit"]
    assert co["sigma_signed_MPa"][1] == c91["sigma_at_mu_MPa"][f"{inp['mu']:g}"] and abs(co["sigma_signed_MPa"][0] - co["sigma_signed_MPa"][1]) <= 0.002
    assert co["rigid_same_edge_MPa"][1] == c91["full_drag_rigid_same_edge_MPa"]
    assert ctl["rigid_limit"]["max_rel_diff"] <= 2e-3
    row68 = next(r for r in d68["offset_static_shipped_branch"] if r["geometry"] == inp["geometry"] and r["play"] == "zero interference")
    sy = inp["sigma_yield_PEEK_MPa_tensile_23C"]

    def verdict(vals, c):
        return "above" if min(vals) > c * sy else "below" if max(vals) < c * sy else "at, within the grids"
    for r in d["static"]:
        assert r["sigma_signed_MPa"] < r["rigid_same_edges_sigma_signed_MPa"], r
        assert r["sigma_68_rigid_sharp_MPa"] == next(x["sigma_root_MPa"] for x in row68["by_offset"] if x["offset_um"] == r["offset_um"])
        mo = r["mouth"]
        grids = mo["p_max_by_square_cell_MPa"]
        assert mo["p_max_MPa"] == round(max(grids.values()), 2)
        for c in inp["flow_constraint_factors_55"]:
            assert abs(mo["p_max_over_flow"][f"{c:.1f}"] - mo["p_max_MPa"] / (c * sy)) <= 2e-3
            assert mo["flow_verdict"][f"{c:.1f}"] == verdict(list(grids.values()), c), r
    for e in {r["offset_um"] for r in d["static"]}:
        rows = sorted((r for r in d["static"] if r["offset_um"] == e), key=lambda r: r["r_in_mm"])
        assert [r["sigma_signed_MPa"] for r in rows] == sorted((r["sigma_signed_MPa"] for r in rows), reverse=True)
        assert [r["mouth"]["p_max_MPa"] for r in rows] == sorted((r["mouth"]["p_max_MPa"] for r in rows), reverse=True)
    for c in d["cycle_peak"]:
        vals = list(c["peak_by_square_cell_MPa"].values())
        assert c["peak_MPa"] == round(max(vals), 2) and c["resolution_spread"] <= 0.30
        st = next((r for r in d["static"] if c["geometry"] == inp["geometry"] and r["offset_um"] == c["offset_um"]
                   and r["r_in_mm"] == c["r_in_mm"]), None)
        if st:                                                           # the cycle never hides below the refined static peak
            assert c["peak_MPa"] >= st["mouth"]["p_max_MPa"] * 0.99, c
        for f in inp["flow_constraint_factors_55"]:
            assert c["flow_verdict"][f"{f:.1f}"] == verdict(vals, f), c
    for key, v in summ["smallest_r_in_below_1_sigma_y"].items():
        g, e = key.rsplit(" / ", 1)
        rows = sorted((c for c in d["cycle_peak"] if c["geometry"] == g and f"{c['offset_um']} µm" == e), key=lambda c: c["r_in_mm"])
        ok = [c["r_in_mm"] for i, c in enumerate(rows) if all(x["flow_verdict"]["1.0"] == "below" for x in rows[i:])]
        assert v["smallest_r_in_below_1_sigma_y_mm"] == (min(ok) if ok else None), key
    ex91 = ctl["exit_coaxial_vs_91"]
    assert ex91["max_rel_diff"] <= 0.05
    for r, (ours, theirs) in ex91["by_r_exit_mm"].items():                # 91's own patch row, re-read from the CURRENT cache
        assert abs(ours / theirs - 1.0) <= 0.05
        assert theirs == next(p["p_max_MPa"] for p in d91["patch"] if p["r_edge_mm"] == float(r) and p["base"] == "bonded"
                              and p["modulus"] == "short-term")
    for x in d["exit_cycle_peak"]:
        vals = list(x["peak_by_square_cell_MPa"].values())
        assert x["peak_MPa"] == round(max(vals), 2) and x["resolution_spread"] <= 0.30
        for f in inp["flow_constraint_factors_55"]:
            assert x["flow_verdict"][f"{f:.1f}"] == verdict(vals, f), x
    at_tol = sorted((x for x in d["exit_cycle_peak"] if x["offset_um"] == summ["tolerance_offset_um"]), key=lambda x: x["r_exit_mm"])
    coax = {x["r_exit_mm"]: x["peak_MPa"] for x in d["exit_cycle_peak"] if x["offset_um"] == 0}
    assert all(x["peak_MPa"] > coax[x["r_exit_mm"]] for x in at_tol)       # the offset loads the exit edge more than the coaxial drag
    ok = [x["r_exit_mm"] for i, x in enumerate(at_tol) if all(y["flow_verdict"]["1.0"] == "below" for y in at_tol[i:])]
    assert summ["smallest_r_exit_below_1_sigma_y_at_tolerance_mm"] == (min(ok) if ok else None)
    within = [c for c in d["cycle_peak"] if c["offset_um"] <= summ["tolerance_offset_um"] and c["flow_verdict"]["1.0"] != "below"]
    assert [(c["geometry"], c["r_in_mm"]) for c in within] == [(w["geometry"], w["r_in_mm"]) for w in summ["within_tolerance_rows_at_or_above_1_sigma_y"]]
    for w in d["rigid_swing"]:
        assert abs(w["mouth_over_root_amplitude"] - w["mouth_section_mean_amplitude_MPa"][1] / w["root_mean_amplitude_MPa"][1]) <= 2e-3
        assert w["ends_only_amplitude_MPa"] <= w["root_mean_amplitude_MPa"][1] + 1e-9
    ratio = {w["offset_um"]: w["mouth_over_root_amplitude"] for w in d["rigid_swing"]}
    assert ratio[0] < 1.0 and ratio[10] < 1.0                       # coaxially the root out-swings the mouth section
    for rv in d["reversing"]:
        sig = [p["sigma_signed_MPa"] for p in rv["path"]]
        assert rv["sigma_max_MPa"] == max(sig) and rv["sigma_min_MPa"] == min(sig)
        assert abs(rv["amplitude_MPa"] - (max(sig) - min(sig)) / 2.0) <= 1e-3
        w = next(x for x in d["rigid_swing"] if x["offset_um"] == rv["offset_um"])
        assert rv["rigid_same_edges_amplitude_MPa"] == w["root_mean_amplitude_MPa"][1]
    st = [z["static_sigma_MPa"] for z in sorted(d["shank"], key=lambda z: z["shank_mm"])]
    assert st == sorted(st), st                                          # a mouth nearer the root makes the offset dearer
    for e, v in summ["mouth_over_root_amplitude_by_offset"].items():
        assert ratio[int(e)] == v
    assert f"peaks at ×{ratio[summ['ratio_peak_at_um']]:.2f} near {summ['ratio_peak_at_um']} µm" in summ["text"]
    assert "the smallest swept exit radius that holds there is" in summ["text"] or not summ["exit_rows_at_or_above_1_sigma_y"]
    # 86's threshold against the cycles at the tolerance limit, re-derived from the rows and the CURRENT 86 cache: the
    # verdict «covered through the amplitude, not the mean» must be what the numbers give, on every swept shank
    d86 = json.loads((MECHANICAL / "coaxiality_allocation.json").read_text())
    g86 = d86["by_geometry"][next(iter(d86["by_geometry"]))]
    v86 = summ["versus_86_threshold"]
    def k_needed(mean, amp):
        return max(amp / (a["endurance_MPa"] * (1.0 / d86["inputs"]["sf_target"] - mean / a["yield_MPa"])) for a in g86["by_alloy"].values())
    for z in d["shank"]:
        k = k_needed(*z["root_mean_amplitude_MPa"])
        assert abs(v86["k_needed_by_shank"][f"{z['shank_mm']:g}"] - k) < 6e-5 and k < v86["k_break_even_binding"]
    assert v86["shanks_with_mean_beyond_86"] == [z["shank_mm"] for z in sorted(d["shank"], key=lambda z: z["shank_mm"])
                                                 if z["root_mean_amplitude_MPa"][0] > v86["mean_MPa_86"]]
    assert "through its AMPLITUDE, not its mean" in summ["text"]


def test_wire_under_liner_edges():
    """97 (HW.34): the bus wire under the liner's mouth and exit edges — the contact pressure carried through the PEEK
    layer onto the Ti surface, added to the nominal bending, on 86's Soderberg line against the welded root.

    CAN catch: a kernel control past its bound; a station whose field moves with the padding, whose nominal at the
    centroid is not 92's section stress, whose exported window side disagrees with 92's own rod, or whose moment is not
    92's pose; a root that is not 92's own shank row at the tolerance offset (re-read from the CURRENT 92 cache); an SF, a
    k_x or a worst face its own amplitudes and means do not give; a summary whose lowest k_x (value and place, inside and
    beyond ⌀0.10), root SF, liner-end factor, contact tension (per base) or contact weight is not what the rows say, or whose text
    stopped quoting them (thresholds rounded DOWN). It does NOT test this script's face assembly (checked by hand,
    2026-10-16) — the window-side check is 92's sign.
    CANNOT catch: the wire's own curvature under the layer (a half-space), plasticity, friction at the layer's base
    beyond the two bounding bases, the liner end's corner (open — only the factor it would need), the seam's k.
    """
    path = MECHANICAL / "wire_under_liner_edges.json"
    if not path.exists():
        pytest.skip("97 not run")
    d = json.loads(path.read_text(encoding="utf-8"))
    d92 = json.loads((MECHANICAL / "liner_mouth_contact.json").read_text(encoding="utf-8"))
    kc, inp = d["kernel_controls"], d["inputs"]
    assert kc["kh_to_zero_max_abs"] < 1e-6 and kc["frictionless_kk_equals_zz_max_abs"] < 1e-12
    assert kc["homogeneous_closed_form_max_abs"] < 1e-10 and kc["rigid_substrate_vs_91_phi_max_rel"] < 1e-4 and kc["tail_at_kh_max"] < 1e-4
    se, sy = inp["endurance_drawn_wire_MPa"], inp["yield_Ti_MPa"]

    def sf(amp, mean, k=1.0):
        return 1.0 / (amp / (k * se) + max(mean, 0.0) / sy)
    assert sorted({r["base"] for r in d["rows"]}) == sorted(d["summary"]["by_base"])
    for r in d["rows"]:
        tag = f"{r['base']} {r['offset_um']} µm"
        ra, rm = r["root"]["amplitude_MPa"], r["root"]["mean_abs_MPa"]
        for k, v in r["root"]["sf_at_k"].items():
            assert abs(v - sf(ra, rm, float(k))) < 1e-9, tag
        for name in ("mouth", "exit"):
            st, c = r[name], r[name]["controls"]
            assert c["max_padding_diff_MPa"] < 0.05 and c["max_centroid_nominal_diff_MPa"] < 1e-6, tag
            assert not math.isfinite(c["min_rod_toward_wall_over_play"]) or c["min_rod_toward_wall_over_play"] > 0.5, \
                f"{tag} {name}: contact on the wrong face"
            assert c["internal_92_Ecv2_minus_sigma_MPa"] <= 0.01 * c["internal_92_scale_MPa"] + 0.01, tag
            for fn, f in st["faces"].items():
                assert abs(f["sf_drawn_wire"] - sf(f["amplitude_MPa"], f["mean_MPa"])) < 1e-6 * f["sf_drawn_wire"], (tag, name, fn)
                dd = f["amplitude_MPa"] + (max(f["mean_MPa"], 0.0) - rm) * se / sy
                assert f["k_crossover"] == (pytest.approx(ra / dd, rel=1e-9) if dd > 0 else None), (tag, name, fn)
            assert st["worst_face"] == min(st["faces"], key=lambda k: st["faces"][k]["sf_drawn_wire"]), tag
    # the root is 92's own: the same solves on the same drag path — 92's shipped-shank row at its tolerance offset
    tol = d["summary"]["tolerance_offset_um"]
    assert tol == d92["summary"]["tolerance_offset_um"]
    (shank,) = [z for z in d92["shank"] if z["mouth_station_mm"] == round(d92["inputs"]["gap_mm"], 3)]  # the shipped one
    r97 = next(r for r in d["rows"] if r["base"] == "bonded" and r["offset_um"] == tol)
    # 92 rounds each point's σ to 3 decimals and then its swing again (`row` · `swing`): two half-units, 1e-3 MPa
    assert abs(r97["root"]["mean_abs_MPa"] - shank["root_mean_amplitude_MPa"][0]) <= 1e-3 + 1e-9, "97's root is not 92's — re-run 97"
    assert abs(r97["root"]["amplitude_MPa"] - shank["root_mean_amplitude_MPa"][1]) <= 1e-3 + 1e-9, "97's root is not 92's — re-run 97"
    assert r97["path_points"] == shank["points"], "97 walked another drag path than 92"
    down = lambda x: math.floor(x * 100) / 100  # noqa: E731
    text = d["summary"]["text"]
    for base, b in d["summary"]["by_base"].items():
        rs = [r for r in d["rows"] if r["base"] == base]
        cands = [(f["k_crossover"], r["offset_um"], n, fn) for r in rs for n in ("mouth", "exit") for fn, f in r[n]["faces"].items()
                 if f["k_crossover"] is not None]
        for key, pool in (("lowest_k_crossover_within_tolerance", [c for c in cands if c[1] <= tol]),
                          ("lowest_k_crossover_beyond", [c for c in cands if c[1] > tol])):
            got, want = b[key], min(pool, default=None)
            assert (got is None) == (want is None), (base, key)
            if want:
                assert (got["k_crossover"], got["offset_um"], got["station"], got["face"]) == want, (base, key)
        inside = b["lowest_k_crossover_within_tolerance"]
        if inside:
            assert f"«{base}»: inside ⌀0.10 the welded root stays the critical section for every seam knock-down k < {down(inside['k_crossover']):.2f}" in text
            # the arc ceiling's bracket: ×1.3 on the contact's share, the nominal share bounded by σ_e/SF_nominal over the face
            assert ("k_crossover_contact_x1_3" in inside) == (inside["mean_MPa"] < 0), base
            if inside["mean_MPa"] < 0:
                r = next(r for r in rs if r["offset_um"] == inside["offset_um"])
                f, arc = r[inside["station"]]["faces"][inside["face"]], 0.65 / 0.5
                a, an = f["amplitude_MPa"], se / f["sf_nominal_only"]
                want = sorted(r["root"]["amplitude_MPa"] / (x - r["root"]["mean_abs_MPa"] * se / sy) for x in (arc * a, an + arc * (a - an)))
                assert inside["k_crossover_contact_x1_3"] == pytest.approx(want, rel=1e-9), base
        assert b["root_sf_at_k_at_tolerance"] == next(r for r in rs if r["offset_um"] == tol)["root"]["sf_at_k"], base
        for k, v in b["liner_end_corner_factor_to_out_rank_within_tolerance"].items():   # against the governing section at k
            want = min((min(x["sf_nominal_only"] for x in r["liner_end"].values() if isinstance(x, dict))
                        / min(r["root"]["sf_at_k"][k], *(f["sf_drawn_wire"] for st in ("mouth", "exit") for f in r[st]["faces"].values())),
                        r["offset_um"]) for r in rs if r["offset_um"] <= tol)
            assert (v["factor"], v["offset_um"]) == want, (base, k)
            assert f"×{down(v['factor']):.2f} (k {k}, {v['offset_um']} µm)" in text, (base, k)
        assert b["not_solved"] == [{"offset_um": r["offset_um"], **ns} for r in rs for ns in r["not_solved"]], base
    assert ("path point(s) refused by 92" in text) == any(x["not_solved"] for x in d["summary"]["by_base"].values()), \
        "a refused path point shrinks the cycle (both amplitudes lower bounds) and the summary must say so"
    faces = [(f, r["base"], r["offset_um"], st, fn) for r in d["rows"] for st in ("mouth", "exit") for fn, f in r[st]["faces"].items()]
    # the contact's own tension, per base — no sign asserted: a face whose every path point touches has no zero sample
    for base, b in d["summary"]["by_base"].items():
        ct = max((f["max_contact_tension_MPa"], off, st, fn) for f, bb, off, st, fn in faces if bb == base)
        s = b["contact_tension_max"]
        assert (s["MPa"], s["offset_um"], s["station"], s["face"]) == ct, base
        assert f"{base} {s['MPa']:+.3f} MPa ({s['offset_um']} µm, {s['station']} {s['face']})" in text, base
    cw = max(faces, key=lambda x: x[0]["contact_factor_on_1_over_sf"])
    s = d["summary"]["contact_factor_on_1_over_sf_max"]
    assert (s["factor"], s["base"], s["offset_um"], s["station"], s["face"]) == (cw[0]["contact_factor_on_1_over_sf"], *cw[1:])
    assert ("where the governing cycle's mean is compressive" in text) == (s["mean_MPa"] < 0)
    tens = max((x for x in faces if x[0]["mean_MPa"] >= 0), key=lambda x: x[0]["contact_factor_on_1_over_sf"])
    assert d["summary"]["contact_factor_at_tensile_mean_max"]["factor"] == tens[0]["contact_factor_on_1_over_sf"]


def test_liner_exit_contact():
    """Script 91 (HW.34 / HW.23): the liner's exit contact as an elastic-layer problem coupled to the rod, read over
    the drag CYCLE (touchdown → µ·F), each figure beside a rigid wall at the SAME edge.

    CAN catch: a bracket or a pad-couple row read against a stale 68 (both read from 68's CURRENT cache); a cycle row
    whose peak is not the maximum of its own path, falls below the rigid touchdown value at the same edge or rises
    above it by more than a sliver (the reaction is near zero there), or sits below its own full-drag point; a compliance that RAISED the full-drag root against the
    rigid wall at the same edge, or a sub-cycle shallower than the rigid one (the two claims the summary makes); a
    give no longer a sliver of the wall; a compliance share of the sliding outside [0, 1]; a wear path whose
    saturation reaches 68's upper end or does not sit at the mouth's engagement; a pad couple that changes the
    reversing cycle's amplitude by more than a few per cent, or whose mean does not grow with the eccentricity; a
    countersink row whose tip is not past the bore line at touchdown (then the «ring is the first contact» caveat
    would be stale); a sharp in-layer edge that stopped growing as ρ^(-1/2); a wear reading below 55's CURRENT flow
    bound or above 55's CURRENT upper sliding.
    CANNOT catch: whether a flat elastic layer is the right model of a 0.15 mm tube on a Ø1.0 wire (curvature, its
    free end, plasticity, the landing, the ring and the lumped friction are declared ceilings), whether PEEK's
    modulus is the tube grade's, or anything about the mouth, which 91 does not compute.
    """
    path = MECHANICAL / "liner_exit_contact.json"
    if not path.exists():
        pytest.skip("liner_exit_contact.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    d68 = json.loads((MECHANICAL / "bus_contact_equilibrium.json").read_text(encoding="utf-8"))
    d55 = json.loads((MECHANICAL / "bus_mechanical.json").read_text(encoding="utf-8"))
    inp, ctl = d["inputs"], d["controls"]
    geo = inp["geometry"]
    assert inp["radial_play_um"] == d68["inputs"]["radial_plays_um"]["zero interference"]
    liner68 = next(r for r in d68["drag_coaxial"] if r["geometry"] == geo and r["branch"].startswith("PEEK liner")
                   and r["play"] == "zero interference")
    mu_max = str(max(float(m) for m in liner68["by_mu"]))
    ref = liner68["by_mu"][mu_max]
    assert inp["rigid_end_68_MPa"] == ref["sigma_root_MPa_bonded"], "91's bracket is not 68's CURRENT one — re-run 91"
    assert inp["upper_end_68_MPa"] == ref["sigma_root_MPa_upper_end"], "91's bracket is not 68's CURRENT one — re-run 91"
    rl = ctl["rigid_limit_vs_68"]
    assert abs(rl["R_N"] + ref["contacts_bonded"][0]["force_N"]) <= 0.005 * rl["R_N"], "rigid limit ≠ 68's exit reaction"
    assert abs(rl["sigma_root_MPa"] / ref["sigma_root_MPa_bonded"] - 1) < 0.01, "rigid limit ≠ 68's root stress"
    pad68 = {str(round(p["eccentricity_mm"], 3)): p["sigma_root_MPa"] for p in d68["pad_moment_at_rod_radius"] if p["geometry"] == geo}
    assert set(ctl["pad_couple_vs_68"]) == set(pad68), "the pad-couple control no longer covers 68's rows"
    for e, (mine, theirs) in ctl["pad_couple_vs_68"].items():
        assert theirs == pad68[e] and abs(mine / theirs - 1) < 0.01, f"pad couple ≠ 68 (d) at e {e}"
    assert all(1.3 < g < 1.55 for g in ctl["sharp_edge_inside_the_layer"]["growth_per_halving"])
    pk = ctl["edge_peak_smallest_radius_two_steps"]["p_max_MPa"]
    assert abs(pk[1] / pk[0] - 1) < 0.02
    lo, hi = inp["rigid_end_68_MPa"], inp["upper_end_68_MPa"]
    for row in d["cycle"] + d["countersink"] + d["sensitivity"]:
        tag = f"{row.get('r_edge_mm')}/{row.get('base', row.get('case', row.get('overhang_mm')))}/{row.get('modulus', '')}"
        sig = row["sigma_root_signed_MPa"]
        assert row["peak_sigma_MPa"] == max(sig), tag
        assert -1e-3 <= row["peak_lift_by_compliance_MPa"] <= 0.005 * abs(row["peak_rigid_touchdown_same_edge_MPa"]), tag
        assert row["peak_sigma_MPa"] >= row["sigma_at_mu_MPa"][mu_max], tag
        assert abs(row["subcycle_range_MPa"] - (row["peak_sigma_MPa"] - row["sigma_at_mu_MPa"][mu_max])) <= 2e-3, tag
        assert row["full_drag_shift_by_compliance_MPa"] <= 0.0, f"{tag}: the compliance raised the full-drag root"
        assert row["subcycle_range_MPa"] >= row["subcycle_rigid_same_edge_MPa"] - 2e-3, tag
        assert row["delta_c_um_at_mu_max"] < 0.05 * inp["liner_wall_mm"] * 1e3, tag
    for row in d["cycle"] + d["countersink"]:
        assert abs(row["peak_position_in_68_bracket"] - (row["peak_sigma_MPa"] - lo) / (hi - lo)) < 1e-3, row
    for row in d["countersink"]:
        assert row["tip_past_bore_line_um_at_touchdown"] > 0, "the tip no longer passes the bore line at touchdown"
        assert row["peak_over_68_rigid_end"] >= 1.0
    assert 0.0 < d["countersink_full_drag_reversal_overhang_mm"] < max(inp["overhang_sweep_mm"])
    for s_ in d["sliding"]:
        assert 0.0 <= s_["compliance_share"] <= 1.0 and s_["slide_um_rigid_same_edge"] <= s_["slide_um_model"], s_
    for w in d["wear_path"]:
        assert w["slope_MPa_per_um_of_exit_wear_conformal_bound"] > 0 and w["mouth_engages_at_exit_wear_um"] > 0
        assert w["peak_saturates_at_MPa"] < hi, "the exit-wear path reached 68's upper end without the mouth wearing"
        assert abs(w["peak_sigma_MPa_unworn_rigid"] + w["slope_MPa_per_um_of_exit_wear_conformal_bound"]
                   * w["mouth_engages_at_exit_wear_um"] - w["peak_saturates_at_MPa"]) < 0.02
    amp0 = d["pad_on_axis_amplitude_MPa"]
    means = [abs(p["cycle_mean_MPa"]) for p in sorted(d["pad_couple"], key=lambda p: p["eccentricity_mm"])]
    assert means == sorted(means) and means[0] > 0, "the couple's mean does not grow with the eccentricity"
    assert all(abs(p["cycle_amplitude_MPa"] / amp0 - 1) < 0.05 for p in d["pad_couple"]), "the couple moved the amplitude"
    wr = d["wear_readings"]
    w55 = next(r for r in d55["wear_budget"]["rows"] if r["geometry"] == geo and r["branch"].startswith("PEEK liner")
               and r["regime"] == "coaxial" and r["mu"] == float(mu_max))
    assert wr["area_mm2_55_flow_bound"] == w55["area_material_bound_mm2"], "55's flow bound moved — re-run 91"
    assert wr["area_over_flow_bound_flush"][0] > 1.0
    upper = next(b for b in d55["clearance_regime"]["branches"] if b["geometry"] == geo and b["branch"].startswith("PEEK liner"))
    assert wr["slide_per_cycle_um_55_upper"] == upper["by_mu"][mu_max]["in_contact_rotation_path_per_cycle_um_upper"]
    assert wr["slide_per_cycle_um_countersink"][1] < wr["slide_per_cycle_um_55_upper"]


def test_bus_contact_equilibrium():
    """Script 68 (HW.34 / HW.23): the bus rod in the cathode channel as a contact problem.

    Sanity is STRUCTURAL — the quoted table is pinned by test_doc_cache_sync. What must hold:
      1. under coaxial drag the shipped liner meets the wall ONLY at its geometry's pad plane, on every µ and play;
      2. the liner caps the root below every conformal film on the same geometry (the ratio the tracker quotes);
      3. an offset inside the play bends nothing, and past it the static root stress rises monotonically;
      4. the offset secant falls as the unsupported gap grows — the shipped geometry (whole shank inserted, the
         shortest gap, HW.26 G1) prices it above the lock window's shallow end;
      5. a tilt the play can take up about its pivot bends nothing;
      6. the peak-moment section is READ per solve, its exceptions listed, and the tilt rows carry the station;
      7. scripts 55 and 68 — one solver, two caches — agree on the coaxial cap (one quantity, two owners).
    """
    path = MECHANICAL / "bus_contact_equilibrium.json"
    if not path.exists():
        pytest.skip("bus_contact_equilibrium.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    pad = {g["label"]: round(g["pad_mm"], 2) for g in d["inputs"]["geometries"]}
    inp = d["inputs"]
    i_rod = math.pi / 64.0 * (inp["rod_dia_mm"] * 1e-3) ** 4
    for row in d["drag_coaxial"]:
        # 🔴 Every drag row carries the SIGN of its rigid-wall figure and an upper end that stays inside
        #    [rigid wall, free cantilever F·L·c/I] — the free end is recomputed here from the inputs, not read.
        assert row["coaxial_cap_bound"].startswith("LOWER end"), f"{row['geometry']}/{row['branch']}"
        for mu, v in row["by_mu"].items():
            free = float(mu) * inp["pogo_force_N"] * (pad[row["geometry"]] * 1e-3) * (inp["rod_dia_mm"] * 0.5e-3) / i_rod / 1e6
            assert v["sigma_root_MPa_bonded"] <= v["sigma_root_MPa_upper_end"] <= free + 0.01, f"{row['geometry']}/{row['branch']}/µ={mu}"
        if row["branch"].startswith("PEEK liner"):
            for mu, v in row["by_mu"].items():
                assert [z["station_mm"] for z in v["contacts_bonded"]] == [pad[row["geometry"]]], f"{row['geometry']}/{row['play']}/µ={mu}"
    for geo in pad:
        liner = [r for r in d["drag_coaxial"] if r["geometry"] == geo and r["branch"].startswith("PEEK liner")]
        films = [r for r in d["drag_coaxial"] if r["geometry"] == geo and not r["branch"].startswith("PEEK liner")]
        for mu in ("0.2", "0.3", "0.4", "0.5"):
            assert max(r["by_mu"][mu]["sigma_root_MPa_bonded"] for r in liner) < min(r["by_mu"][mu]["sigma_root_MPa_bonded"] for r in films), f"{geo} µ={mu}"
    for o in d["offset_static_shipped_branch"]:
        inside = [p_ for p_ in o["by_offset"] if p_["offset_um"] <= o["radial_play_um"]]
        past = [p_["sigma_root_MPa"] for p_ in o["by_offset"] if p_["offset_um"] > o["radial_play_um"]]
        assert all(p_["sigma_root_MPa"] == 0.0 and not p_["contacts"] for p_ in inside), f"{o['geometry']}/{o['play']}"
        assert past == sorted(past) and past[0] < past[-1], f"{o['geometry']}/{o['play']}: not monotone"
    secant = {o["geometry"]: o["secant_MPa_per_um"] for o in d["offset_static_shipped_branch"] if o["play"] == "zero interference"}
    by_gap = [secant[g["label"]] for g in sorted(d["inputs"]["geometries"], key=lambda g: g["gap_mm"])]
    assert len(by_gap) >= 2 and by_gap == sorted(by_gap, reverse=True) and by_gap[0] > by_gap[-1], secant
    for t in d["tilt_static_shipped_branch"]:
        for row in t["by_tilt"]:
            if row["tilt_mrad"] <= t["tilt_taken_up_by_play_mrad"]:
                assert row["sigma_root_MPa"] == 0.0, f"{t['geometry']}/{t['pivot']} {row['tilt_mrad']} mrad"
    # 6. ⛔ «in every configuration computed here the root is the peak-moment section» was PROSE in this cache
    #    and false for two lock-window classes; read from the moment field it is a flag plus a list, and every
    #    tilt row whose peak left the root must appear in that list (and vice versa).
    peak = d["peak_moment_section"]
    assert peak["root_is_peak_in_every_drag_offset_and_reversing_row"] is True
    assert set(peak["rows_where_the_peak_leaves_the_root"]) == {"tilt", "pad_moment"}
    listed = {(p["geometry"], p["peak_moment_station_mm"]) for p in peak["rows_where_the_peak_leaves_the_root"]["tilt"]}
    from_rows = {(t["geometry"], row["peak_moment_station_mm"]) for t in d["tilt_static_shipped_branch"]
                 for row in t["by_tilt"] if row["peak_moment_station_mm"] != 0.0}
    assert listed == from_rows, "the tilt exceptions and the tilt rows disagree about where the peak sits"
    # 7. One solver, two caches: the coaxial cap script 55 writes must equal the one this script writes.
    side = d["script55_side_by_side"]
    assert side["caps_agree"] is True and side["upper_ends_agree"] is True
    assert side["script55_coaxial_cap_MPa_at_worst_mu_bonded"] == side["equilibrium_coaxial_cap_MPa_at_worst_mu_bonded"]
    assert side["script55_upper_end_MPa_at_worst_mu"] == side["equilibrium_upper_end_MPa_at_worst_mu"]
    assert side["coaxial_cap_bound"].startswith("LOWER")
    for g, lo in side["equilibrium_coaxial_cap_MPa_at_worst_mu_bonded"].items():
        assert side["equilibrium_upper_end_MPa_at_worst_mu"][g] >= lo, g
    bus55 = MECHANICAL / "bus_mechanical.json"
    if bus55.exists():
        by_geo = json.loads(bus55.read_text())["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"]
        caps55 = {g["geometry"]: g["coaxial_cap_MPa_bonded"] for g in by_geo}
        upper55 = {g["geometry"]: g["bracket_MPa_worst_mu"][1] for g in by_geo}
        assert caps55 == side["equilibrium_coaxial_cap_MPa_at_worst_mu_bonded"], "scripts 55 and 68 drifted apart on the coaxial cap"
        assert upper55 == side["equilibrium_upper_end_MPa_at_worst_mu"], "scripts 55 and 68 drifted apart on the upper end"


def test_coaxiality_allocation():
    """Script 86 (HW.34, ⚖️ 2026-10-12 exception to the crown pause): a channel offset priced as a Soderberg MEAN.

    CAN catch: the zero-mean SF drifting off script 55's one quantity; a mean appearing inside the smallest play; a row
    that stops being monotone in the offset (mean up, SF down, break-even k up); a branch whose budget is not the zone's
    half; a break-even k recomputed by hand that disagrees with the formula on the cached inputs. CANNOT catch: whether
    Soderberg, the upper-end amplitude or the rigid-wall mean are the right choices — the docstring names each one.
    """
    path = MECHANICAL / "coaxiality_allocation.json"
    if not path.exists():
        pytest.skip("coaxiality_allocation.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    ctl = d["controls"]["zero_mean_sf_equals_script55"]
    assert abs(ctl["sf"] - ctl["script55"]) <= 0.01
    target = d["inputs"]["sf_target"]
    for geo, g in d["by_geometry"].items():
        assert g["amplitude_MPa"] >= g["amplitude_zero_interference_MPa"], geo   # the worst play, never a friendlier one
        for name, a in g["by_alloy"].items():
            rows = a["by_offset"]
            for r in rows:
                if r["offset_um"] < d["inputs"]["smallest_swept_play_um"]:
                    assert r["mean_MPa"] == 0.0, (geo, name, r)
                sf = 1.0 / (g["amplitude_MPa"] / a["endurance_MPa"] + r["mean_MPa"] / a["yield_MPa"])
                assert abs(sf - r["sf_wire"]) <= 0.001, (geo, name, r)
                room = 1.0 / target - r["mean_MPa"] / a["yield_MPa"]
                if r["k_break_even"] is not None:
                    assert abs(g["amplitude_MPa"] / (a["endurance_MPa"] * room) - r["k_break_even"]) <= 1e-4, (geo, name, r)
            for x, y in itertools.pairwise(rows):
                assert y["mean_MPa"] >= x["mean_MPa"] and y["sf_wire"] <= x["sf_wire"], (geo, name, y)
    for b in d["branches"].values():
        assert b["iso1101_coaxiality_zone_mm"] == round(2 * b["radial_offset_budget_um"] / 1000.0, 3)


def test_pogo_sway_transfer():
    """Script 87 (HW.43): how trunk sway reaches the pogo pins — rim condition (A), stack inertia (B), centre pad (C).

    CAN catch, each recomputed from the cache's own inputs and the radome CEM rather than copied from the script: the
    copper ceiling drifting off `radome.json`; the weakest pin's unloading mass losing the static share of the weight
    (the first version dropped it); the rim demand losing the capsule's weight; the centre-pad ratio per 1000 µε
    leaving μ_LR·Δx/x_min; a centre-pad term that starts depending on the stem reading per µε. CANNOT catch: whether
    the Figure-9 reading, the copper ceiling or the canopy-top drag are the right inputs — the docstring names each.
    """
    path = MECHANICAL / "pogo_sway_transfer.json"
    if not path.exists():
        pytest.skip("pogo_sway_transfer.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    inp, g = d["inputs"], 9.80665
    cem = json.loads((REPO / "tools/cad/cem/radome.json").read_text(encoding="utf-8"))
    dia, h = cem["dome_diameter_mm"], cem["cavity_height_mm"] + cem["bell_radius_mm"]
    assert inp["capsule_envelope_mm"] == [dia, h]
    assert abs(inp["mass_ceiling_g"] - math.pi * (dia / 2) ** 2 * h * 1e-3 * 8.96) <= 0.1
    ctl = d["controls"]["slope_times_flux_reproduces_12m_tilt"]
    assert abs(ctl["deg"] - ctl["text_deg"]) <= 1.0
    sin_i, cos_i = math.sin(math.radians(inp["install_angle_deg"])), math.cos(math.radians(inp["install_angle_deg"]))
    m, f = inp["mass_ceiling_g"] * 1e-3, inp["pin_force_min_N"]
    mus = inp["mu_lr_pines"].values()
    per1000 = (min(mus) * 1e-3 * inp["depth_span_m"]["nominal_anode_centroid_to_flange_77"] * 1e3 / inp["working_compression_min_mm"],
               max(mus) * 1e-3 * inp["depth_span_m"]["ceiling_full_depth_77"] * 1e3 / inp["working_compression_min_mm"])
    for name, r in d["by_slope_reading"].items():
        a = r["stem_at_anchor_h_le_2m"]["accel_m_s2"]
        b, c, rim = r["B_inertia_coaxial"], r["C_centre_pad_poisson"], r["A_rim"]
        assert abs(b["stack_mass_g_where_weakest_pin_unloads"] - f / ((a + g * sin_i) * 1e-3)) <= 1.0, name
        demand = math.hypot(m * g * cos_i, inp["drag_ceiling_N"] + m * a)       # the weight must be in it
        assert abs(rim["demand_N_at_ceiling"] - demand) <= 0.002, name
        normal = demand / inp["mu_rim"]                                           # end of life: capacity µ·N
        assert abs(rim["normal_force_N_needed_at_end_of_life"] - normal) <= 0.01, name
        push, f_r = inp["pin_count"] * f, inp["rim_relax_fraction_at_service_from_52"]
        needs = rim["o_ring_reaction_N_needed"]
        assert abs(needs["initial_with_clamp_at_52_requirement"] - max(0.0, normal - push)) <= 0.02, name      # N ≥ L0
        assert abs(needs["after_20_years_with_a_weaker_clamp"] - max(0.0, normal - push)) <= 0.02, name  # lifted: N = L(20)
        assert set(needs) == {"initial_with_clamp_at_52_requirement", "after_20_years_with_a_weaker_clamp"}, name
        c0 = inp["rim_required_initial_clamp_N_from_52"]["with_generous_o_ring"]
        early = inp["mu_rim"] * (2 * c0 - c0 * f_r)                              # 2C − L with the lift C was sized for
        assert abs(rim["capacity_N_initial_at_52_requirement"] - early) <= 0.1, name
        m10 = 0.1 * f / ((a + 0.1 * g * sin_i) * 1e-3)                           # 10 % over the REDUCED mean
        assert abs(b["stack_mass_g_for_ratio_10pct"] - m10) <= 0.1, name
        assert b["stack_mass_g_for_ratio_10pct"] < 0.1 / b["force_ratio_per_gram"], name   # the slope is not a bound
        assert abs(c["ratio_per_1000_microstrain"]["mu_lr_lo_dx_nominal"] - per1000[0]) <= 1e-4, name
        assert abs(c["ratio_per_1000_microstrain"]["mu_lr_hi_dx_ceiling"] - per1000[1]) <= 1e-4, name
        if not b["unloads_at_mass_ceiling"]:
            assert b["ratio_at_mass_ceiling_over_reduced_mean"] < 1.0, name
        est = b["at_estimated_stack_mass"]                                        # the part-by-part stack, low … high
        for k, ms in enumerate(est["stack_mass_g"]):
            assert abs(est["ratio_over_reduced_mean"][k] - ms * 1e-3 * a / (f - ms * 1e-3 * g * sin_i)) <= 1e-4, name
    pcb = inp["fr4_board"]
    area = math.pi * (pcb["disc_diameter_mm_rim_cavity_52"] / 2) ** 2
    boards = [pcb["count"] * area * (pcb["thickness_mm"] * rho + pcb["copper_layers"] * pcb["copper_thickness_mm"] * fill
                                     * (8.96 - rho)) * 1e-3
              for rho, fill in zip(pcb["rho_g_cm3"], pcb["copper_fill"], strict=True)]
    assert all(abs(x - y) <= 0.001 for x, y in zip(inp["fr4_boards_g"], boards, strict=True))
    stack = [sum(v[k] for v in inp["stack_parts_g"].values()) + boards[k] for k in (0, 1)]
    for r in d["by_slope_reading"].values():
        assert all(abs(x - y) <= 0.01 for x, y in zip(r["B_inertia_coaxial"]["at_estimated_stack_mass"]["stack_mass_g"],
                                                       stack, strict=True))
    z52 = json.loads((MECHANICAL / "z_stack_tolerance.json").read_text(encoding="utf-8"))
    assert pcb["disc_diameter_mm_rim_cavity_52"] == z52["applied_gland"]["rim_cavity_mm"]
    med, wh = d["by_slope_reading"]["median"], d["by_slope_reading"]["upper_whisker"]
    assert wh["stem_at_anchor_h_le_2m"]["accel_m_s2"] > med["stem_at_anchor_h_le_2m"]["accel_m_s2"]
    assert wh["C_centre_pad_poisson"]["ratio_per_1000_microstrain"] == med["C_centre_pad_poisson"]["ratio_per_1000_microstrain"]


def test_pogo_sway_transfer_wire_behind_liner():
    """Script 87 (HW.43 · HW.34), (C) behind the liner: the ceiling the liner wall puts on the axial force at the wire's
    root, and 86's seam requirement and wire SF at that ceiling.

    CAN catch, recomputed from 55's and 86's CURRENT caches rather than copied from the script: the ceiling leaving
    σ_y,PEEK·A_tube; the list of μ where a grip slips first leaving 55's rows (nominal as fitted, nominal relaxed to lib's
    PEEK_RELAX_FLOOR, window floor); the seam k or the wire SF leaving 86's Soderberg (written here from 86's docstring,
    not imported) with the wall's stress added to 86's amplitude, at ⌀0.10 and at each branch; 86's own k and SF on 86's
    inputs no longer matching 86's binding row; an added amplitude that stops dividing by each branch's own room (the
    branch ratios would move); the verdict's numbers drifting off the cache, a requirement rounded down or an SF floor
    rounded up; the verdict losing its condition (the load the root carries is not computed). CANNOT catch: the axial load
    the root actually carries, the wire's slip in the liner, the capture, PEEK in the cold or in compression, a parallel
    tie in the wet gap — the docstring names each as outside the ceiling.
    """
    from lib.constants import ALLOY_BASELINE, PEEK_RELAX_FLOOR

    path = MECHANICAL / "pogo_sway_transfer.json"
    if not path.exists():
        pytest.skip("pogo_sway_transfer.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    b55 = json.loads((MECHANICAL / "bus_mechanical.json").read_text(encoding="utf-8"))
    d86 = json.loads((MECHANICAL / "coaxiality_allocation.json").read_text(encoding="utf-8"))
    cp = b55["interference_window"]["cold_press_fit"]
    rows55 = {r["at"]: r for r in cp["rows"]}
    f_wall = cp["peek_yield_MPa"] * cp["tube_section_mm2"]
    a_wire = math.pi * b55["geometry_mm"]["bus_dia"] ** 2 / 4.0
    key = next(k for k in d86["by_geometry"] if k.startswith("shipped"))
    g86, e86 = d86["by_geometry"][key], d86["branches"]["loose_50"]["radial_offset_budget_um"]
    sf_t = d86["inputs"]["sf_target"]

    def sod(amp, mean, se, sy):              # 86: SF = 1/(σa/σe + σm/σy); k = σ_a / (σ_e · (1/SF_t − σ_m/σ_y))
        room = 1.0 / sf_t - mean / sy
        return 1.0 / (amp / se + mean / sy), (amp / (se * room) if room > 0 else None)

    w = d["C_wire_behind_liner"]
    r = w["route"]
    assert abs(r["wall_capacity_N_at_23C"] - f_wall) <= 0.05
    assert abs(r["wire_stress_at_wall_capacity_MPa"] - f_wall / a_wire) <= 0.05
    nominal = {m: v["friction_N"] for m, v in rows55["ratified_nominal"]["by_mu"].items()}
    assert r["grip_friction_N_by_mu_ratified_nominal_as_fitted"] == nominal and r["relax_floor"] == PEEK_RELAX_FLOOR
    assert r["mu_where_the_grip_slips_first"] == {
        "ratified_nominal_as_fitted": sorted(m for m, f in nominal.items() if f < f_wall),
        "ratified_nominal_relaxed_to_floor": sorted(m for m, f in nominal.items() if f * PEEK_RELAX_FLOOR < f_wall),
        "window_floor": sorted(m for m, v in rows55["window_floor"]["by_mu"].items() if v["friction_N"] < f_wall)}
    assert w["sf_target"] == sf_t and w["amplitude_86_MPa"] == g86["amplitude_MPa"] and w["offset_86_um"] == e86
    assert set(w["by_alloy"]) == set(g86["by_alloy"])
    for name, x in w["by_alloy"].items():
        r86 = g86["by_alloy"][name]
        own, capped = {}, {}
        for bname, br in d86["branches"].items():
            m_b = next(p["mean_MPa"] for p in r86["by_offset"] if p["offset_um"] == br["radial_offset_budget_um"])
            own[bname] = sod(g86["amplitude_MPa"], m_b, r86["endurance_MPa"], r86["yield_MPa"])
            capped[bname] = sod(g86["amplitude_MPa"] + f_wall / a_wire, m_b, r86["endurance_MPa"], r86["yield_MPa"])
            assert abs(x["seam_k_at_route_capacity_by_branch"][bname] - capped[bname][1]) <= 1e-4, (name, bname)
        b0 = next(b for b, br in d86["branches"].items() if br["radial_offset_budget_um"] == e86)
        assert abs(x["seam_k_86"] - own[b0][1]) <= 1e-4 and abs(x["seam_k_at_route_capacity"] - capped[b0][1]) <= 1e-4
        assert abs(x["sf_wire_86"] - own[b0][0]) <= 1e-3 and abs(x["sf_wire_at_route_capacity"] - capped[b0][0]) <= 1e-3
        assert all(abs(capped[b][1] / capped["tight"][1] - own[b][1] / own["tight"][1]) <= 1e-9 for b in own), name
    b86 = d86["branches"]["loose_50"]["by_geometry"][key]
    assert abs(w["by_alloy"][b86["binding_alloy"]]["seam_k_86"] - b86["k_break_even_binding"]) <= 1e-3

    def up(v):
        return math.ceil(v * 100 - 1e-9) / 100

    def down(v):
        return math.floor(v * 100 + 1e-9) / 100

    v, ba = d["verdict"], w["by_alloy"]
    kr = {n: x["seam_k_at_route_capacity"] for n, x in ba.items()}
    bind = max(kr, key=kr.get)
    assert f"the wall caps it at {r['wall_capacity_N_at_23C']} N" in v
    assert (f"from k ≥ {ba[ALLOY_BASELINE]['seam_k_86']:.4f} to {up(kr[ALLOY_BASELINE]):.2f} on {ALLOY_BASELINE} and from "
            f"{ba[bind]['seam_k_86']:.4f} to {up(kr[bind]):.2f} on {bind}") in v
    assert (f"drops the wire's SF from {ba[bind]['sf_wire_86']:.2f} to {down(ba[bind]['sf_wire_at_route_capacity']):.2f} "
            f"on {bind}") in v
    above = [n for n, k in kr.items() if k > 1.0]
    assert (f"on {' and '.join(above)} not even an unweakened wire keeps SF" in v) == bool(above)
    assert f"even the tightest coaxiality branch needs k ≥ {up(min(ba[bind]['seam_k_at_route_capacity_by_branch'].values())):.2f}" in v
    assert "the requirement lies between 86's own k and that reading" in v and "16 %" not in v


def test_oring_reaction_band():
    """Script 88 (HW.43 · HW.33): the O-ring reaction from Parker Figure 2-4 + Table 2-3 over 52's squeeze window.

    CAN catch, recomputed from the cache's chart rows and the upstream caches rather than copied from the script: the
    seal length drifting off 52's groove; the bar leaving log-load-linear-in-squeeze between the bracketing rows; the
    band leaving Table 2-3's portion for a ring under 1" (the bottom of the bar's middle third, in log scale, to its
    top); the requirement bracket leaving R + p at assembly and (R + p) / f for a ring that never relaxes; the lug
    margins, the share of R0 the ring must have lost by each year (on 52's f(t), not its 20-year value) and the
    strength-sized wall leaving 73's linear shear rows; the binding squeeze not reproducing the binding reaction; (A)'s
    margin (initial need only) and retained share leaving 87's two needs over the floor's low end. CANNOT catch: the transcription itself (the pt table lives in the script, read from the PDF's
    vector paths — only the page catches an error made there), nor whether Parker's bar describes our compound.
    """
    path = MECHANICAL / "oring_reaction_band.json"
    if not path.exists():
        pytest.skip("oring_reaction_band.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    z52 = json.loads((MECHANICAL / "z_stack_tolerance.json").read_text(encoding="utf-8"))
    c73 = json.loads((MECHANICAL / "collar_wall_inversion.json").read_text(encoding="utf-8"))
    s87 = json.loads((MECHANICAL / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    inp, lbf_n = d["inputs"], 4.4482216152605
    assert inp["ring_id_mm"] < 25.4                                       # Table 2-3's rows for rings under 1"
    length_in = math.pi * (2 * z52["applied_gland"]["flange_groove_r_mm"][0] + z52["springs"]["oring"]["cs_mm"]) / 25.4
    assert abs(inp["seal_length_in"] - length_in) <= 1e-4
    to_n = length_in * lbf_n
    chart = {int(k): v for k, v in d["chart_70_shore_a_lbf_per_in"].items()}
    rows = sorted(chart)
    for lo_row, hi_row in itertools.pairwise(rows):
        assert chart[hi_row][0] > chart[lo_row][0] and chart[hi_row][1] > chart[lo_row][1], (lo_row, hi_row)
    assert all(lo < hi for lo, hi in chart.values())

    def bar(pct, end):
        a, b = max(r for r in rows if r <= pct), min(r for r in rows if r >= pct)
        if a == b:
            return chart[a][end]
        w = (pct - a) / (b - a)
        return 10 ** (math.log10(chart[a][end]) + w * (math.log10(chart[b][end]) - math.log10(chart[a][end])))

    def band(pct):
        lo, hi = bar(pct, 0), bar(pct, 1)
        return lo * (hi / lo) ** (1 / 3), hi

    rim = z52["rim_datum_creep"]
    p52, f_t, cap = rim["pogo_pair_force_N_upper_bound"], rim["relax_fraction_at_service"], c73["verdict"]["capacity_at_print_floor_N"]
    assert min(r for r in c73["case_b_lug_root_shear"]["rows"] if r["wall_mm"] == 0.2)["breakeven_force_N"] == cap
    for name, b in d["band"].items():
        pct = b["squeeze_pct"]
        lo, hi = band(pct)
        # the cache rounds lbf/in to 0.01, so the reaction it derives may sit one rounding step off this one
        assert abs(b["bar_lbf_per_in"][0] - bar(pct, 0)) <= 0.011 and abs(b["lbf_per_in"][1] - hi) <= 0.011, name
        assert abs(b["lbf_per_in"][0] - lo) <= 0.011, name                     # Table 2-3: no lower third under 1"
        assert abs(b["reaction_N"][0] - lo * to_n) <= 0.15 and abs(b["reaction_N"][1] - hi * to_n) <= 0.15, name
        asm, n20 = hi * to_n + p52, (hi * to_n + p52) / f_t
        req, mar = b["required_clamp_N_at_band_high"], b["lug_root_margin_x_at_print_floor"]
        assert abs(req["at_assembly"] - asm) <= 0.2 and abs(req["after_20_years_ring_never_relaxes"] - n20) <= 0.2, name
        assert abs(mar["at_assembly"] - cap / asm) <= 0.01 and abs(mar["after_20_years_ring_never_relaxes"] - cap / n20) <= 0.01, name
        lost = b["ring_must_have_lost_share_of_R0_by_year"]
        for y, share in lost.items():                                       # f(t) of 52, not its 20-year value alone
            f_y = rim["relax_floor"] + (1 - rim["relax_floor"]) * math.exp(-float(y) / rim["relax_tau_years"])
            assert abs(share - max(0.0, 1 - (cap * f_y - p52) / (hi * to_n))) <= 0.002, (name, y)
        shares = [lost[y] for y in sorted(lost, key=float)]
        assert shares == sorted(shares) and max(float(y) for y in lost) == rim["service_years"], name
        assert abs(shares[-1] - max(0.0, 1 - (cap * f_t - p52) / (hi * to_n))) <= 0.002, name
        assert abs(b["collar_wall_strength_asks_mm_ring_never_relaxes"] - 0.2 * n20 / cap) <= 0.002, name  # 73: linear shear
    pts = [b["squeeze_pct"] for b in d["band"].values()]
    assert pts == sorted(pts) and pts[0] == inp["window_pct"][0] and pts[-1] == inp["window_pct"][1]
    inv = d["inversion"]
    r_bind = cap * f_t - p52
    assert abs(inv["reaction_N_at_which_lug_binds_ring_never_relaxes"] - r_bind) <= 0.1
    assert abs(band(inv["squeeze_pct_band_high_binds"])[1] * to_n - r_bind) <= 0.5
    lo_b, hi_b = inv["squeeze_pct_band_high_binds_over_transcription"]
    assert lo_b < inv["squeeze_pct_band_high_binds"] < hi_b                 # +4 % binds earlier, −4 % later
    a = d["rim_premise_A"]
    needs87 = {}
    for r in s87["by_slope_reading"].values():
        for k, v in r["A_rim"]["o_ring_reaction_N_needed"].items():
            needs87[k] = max(needs87.get(k, 0.0), v)
    assert a["needs_87"] == needs87
    floor_lo = d["band"]["window_floor"]["reaction_N"][0]
    assert set(a["margin_x"]) == {"initial_with_clamp_at_52_requirement"}    # a margin only on an INITIAL need
    assert abs(a["margin_x"]["initial_with_clamp_at_52_requirement"]
               - floor_lo / needs87["initial_with_clamp_at_52_requirement"]) <= 0.01
    assert abs(a["share_retained_needed_with_a_weaker_clamp"]
               - needs87["after_20_years_with_a_weaker_clamp"] / floor_lo) <= 0.001


def test_bayonet_thermal_clamp():
    """Script 89 (HW.33): the bayonet clamp over its interference tolerance and temperature — the collar wall as a
    function of the loop stiffness k, and the force-controlled limit.

    CAN catch, recomputed from the upstream caches and the radome CEM rather than copied from the script: the lug load
    leaving L0/f + k·[2δ + Δα·L·((ΔT_c + (1 − f)·ΔT_h)/f + ΔT_h)]; L0 leaving 88's band-top requirement at assembly;
    the readings leaving 82's requirement and cold edge and 71's canon-finish hot edge; the summer increment dropping
    out of the cold condition; the Δα readings leaving α_PEEK − α_Ti and α_PEEK; the wall leaving 73's linear shear;
    k_max leaving (cap − L0/f)/slope for the print floor and 88's member wall; the force-controlled lug load leaving L0;
    the span leaving lock_groove_z − (lug radius + slot clearance); the PEEK column leaving E·A/L; the member wall
    ceasing to be the window top's k = 0 end. CANNOT catch: whether f applies (the PEEK's share of the compliance), what
    k and δ the real bayonet has, or whether the loop is isothermal — the script does not compute them.
    """
    path = MECHANICAL / "bayonet_thermal_clamp.json"
    if not path.exists():
        pytest.skip("bayonet_thermal_clamp.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    z52 = json.loads((MECHANICAL / "z_stack_tolerance.json").read_text(encoding="utf-8"))
    c73 = json.loads((MECHANICAL / "collar_wall_inversion.json").read_text(encoding="utf-8"))
    c82 = json.loads((MECHANICAL / "collar_running_clearance.json").read_text(encoding="utf-8"))
    b88 = json.loads((MECHANICAL / "oring_reaction_band.json").read_text(encoding="utf-8"))
    c71 = json.loads((CACHE / "thermal" / "capsule_envelope.json").read_text(encoding="utf-8"))
    radome = json.loads((REPO / "tools/cad/cem/radome.json").read_text(encoding="utf-8"))
    inp = d["inputs"]
    f = z52["rim_datum_creep"]["relax_fraction_at_service"]
    assert inp["relax_fraction_at_service_52"] == f
    cap, floor = c73["verdict"]["capacity_at_print_floor_N"], 0.2
    assert inp["lug_root_capacity_N_at_print_floor_73"] == cap and inp["print_floor_wall_mm_73"] == floor
    member = b88["band"]["window_top"]["collar_wall_strength_asks_mm_ring_never_relaxes"]
    assert inp["member_wall_mm_88"] == member
    cap_m = cap * member / floor
    temps = inp["temperature_readings_c"]
    assert temps["capsule_requirement"] == [c82["inputs"]["t_min_requirement_c"], c82["inputs"]["t_max_requirement_c"]]
    assert temps["model_edges"][0] == c82["inputs"]["t_min_model_edge_c"]
    assert temps["model_edges"][1] == c71["hot_bound_h_c_sensitivity"]["sunlit_still_air"]["0.50"]["t_cap_max_c"]
    t_asm = c82["inputs"]["t_ref_c"]
    span = radome["lock_groove_z_mm"] - (radome["lug_radius_mm"] + radome["slot_clearance_mm"])
    assert abs(inp["span_mm_placeholder"] - span) <= 1e-3
    da = inp["delta_alpha_1K"]
    assert abs(da["isothermal"] - (inp["alpha_peek_1K"] - inp["alpha_ti_1K"])) <= 1e-12
    assert da["gradient_bound"] == inp["alpha_peek_1K"]
    for k, a in inp["peek_sections_mm2"].items():
        want = inp["e_peek_pa"] * a * 1e-6 / (span * 1e-3) * 1e-6                # from the area rounded to 0.1 mm²
        assert abs(d["peek_column"]["k_N_per_um_over_span"][k] / want - 1) <= 1e-3, k
    assert abs(inp["peek_sections_mm2"]["rim_contact"] - z52["applied_gland"]["rim_contact_area_mm2"]) <= 0.05

    def wall(force):                                                     # 73: pure shear, linear in the wall
        return floor * force / cap

    for name, p in d["by_squeeze_point"].items():
        l0 = p["lift_L0_N_at_band_top"]
        assert abs(l0 - b88["band"][name]["required_clamp_N_at_band_high"]["at_assembly"]) <= 1e-9, name
        assert abs(p["force_controlled_lug_load_N"] - l0) <= 0.1
        assert abs(p["force_controlled_wall_mm_zero_band"] - wall(l0)) <= 0.002, name
        assert abs(p["PEEK_dominated_lower_bound_wall_mm"] - wall(l0 / f)) <= 0.002, name
        if cap > l0:
            assert abs(p["force_band_half_width_to_print_floor"] - (cap - l0) / (cap + l0)) <= 0.001, name
        req = p["by_reading"]["capsule_requirement|isothermal"]
        for dstr, sp in p["spring_capsule_requirement"].items():
            spread = 2 * float(dstr) * 1e3 + da["isothermal"] * span * 1e3 * (req["dT_cold_K"] + req["dT_hot_K"])
            assert abs(sp["spread_um"] - spread) <= 0.01, (name, dstr)       # a spring does not relax: no f
            if cap > l0:
                ks = (cap - l0) / spread
                assert abs(sp["k_spring_max_N_per_um_zero_tolerance"] - ks) <= 0.002, (name, dstr)
                assert abs(sp["working_deflection_mm_at_band_centre"] - (cap + l0) / 2 / ks * 1e-3) <= 0.01
        lc = inp["lug_line_contact"]
        for lk, load in (("PEEK_dominated_minimum", l0 / f), ("force_controlled", l0)):
            for ek, length in lc["engaged_length_mm"].items():
                fl = load / radome["bayonet_lugs"] / (length * 1e-3)
                p0 = math.sqrt(fl * lc["e_star_pa"] / (math.pi * lc["lug_radius_mm"] * 1e-3)) * 1e-6
                assert abs(p["lug_line_contact_p0_MPa"][lk][ek] / p0 - 1) <= 0.005, (name, lk, ek)
        for rkey, r in p["by_reading"].items():
            rname, aname = rkey.split("|")
            dtc, dth = t_asm - temps[rname][0], temps[rname][1] - t_asm
            cold = dtc + (1 - f) * dth                                     # the summer increment relaxes first
            assert abs(r["cold_with_summer_relaxed_K"] - cold) <= 0.01, rkey
            thermal = da[aname] * span * 1e3 * (cold / f + dth)
            assert abs(r["thermal_um"] - thermal) <= 0.01, rkey
            for dstr, v in r["by_delta_mm"].items():
                slope = 2 * float(dstr) * 1e3 + thermal
                assert abs(v["slope_um"] - slope) <= 0.01, (name, rkey, dstr)
                for kstr, load in v["lug_load_N_by_k"].items():
                    assert abs(load - (l0 / f + float(kstr) * slope)) <= 0.1, (name, rkey, dstr, kstr)
                    assert abs(v["strength_wall_mm_by_k"][kstr] - wall(load)) <= 0.002
                walls = [v["strength_wall_mm_by_k"][k] for k in sorted(v["strength_wall_mm_by_k"], key=float)]
                assert walls == sorted(walls), (name, rkey, dstr)            # stiffer loop → thicker wall
                for wkey, c in (("print_floor", cap), ("member_wall", cap_m)):
                    want = (c - l0 / f) / slope
                    got = v["k_max_N_per_um"][wkey]
                    assert (got is None) == (want < 0), (name, rkey, dstr, wkey)
                    if got is not None:
                        assert abs(got - want) <= 0.002, (name, rkey, dstr, wkey)
    top = d["by_squeeze_point"]["window_top"]
    assert abs(top["PEEK_dominated_lower_bound_wall_mm"] - member) <= 0.002   # the member is the PEEK-dominated floor
    assert top["force_controlled_wall_mm_zero_band"] < floor                        # force control fits the floor
    lc = inp["lug_line_contact"]
    assert lc["yield_onset_p0_pa"] == lc["yield_onset_ratio"] * lc["sigma_yield_peek_pa"]
    ag = z52["applied_gland"]
    assert abs(lc["engaged_length_mm"]["socket_pocket_minus_clearance"]
               - (ag["socket_pocket_r_mm"][1] - ag["socket_pocket_r_mm"][0] - radome["slot_clearance_mm"])) <= 1e-3
    from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, E_PEEK_PA, NU_PEEK
    ti = ALLOY_PROPERTIES[ALLOY_BASELINE]                                        # E* from lib, not from the cache
    e_star = 1 / ((1 - NU_PEEK ** 2) / E_PEEK_PA + (1 - ti["nu"] ** 2) / (ti["E_GPa"] * 1e9))
    assert abs(lc["e_star_pa"] / e_star - 1) <= 1e-3
    tr = top["by_reading"]["capsule_requirement|isothermal"]["by_delta_mm"]
    assert tr["0.05"]["k_max_N_per_um"]["member_wall"] < tr["0.0"]["k_max_N_per_um"]["member_wall"]   # δ binds harder
    assert tr["0.05"]["thermal_share_of_slope"] < 0.5

def test_pogo_thermal_gap():
    """Script 90 (HW.43): the pogo gap's thermal travel — seasonal swing against 52's window, daily stroke, radial slide.

    CAN catch, recomputed from the inputs and the upstream caches rather than copied from the script: the chain no
    longer closing (gap + 2 decks + standoff = the radome's pocket floor); the coefficients leaving α·L sums with lib's
    CTEs; the seasonal gap changes leaving coefficient × (T − T_asm) on 82's readings; the window check leaving
    nominal ± 52's residual + the thermal compression; the daily stroke, force ratio and radial slide leaving
    coefficient × the daily range; the tolerated radome lead leaving margin / (stack + pin) coefficient; the working
    stroke leaving the gap less the brass pin body's α·L over 52's free length (lib's C36000), and the radome alone when it leads; the FR-4
    in-plane slide readings leaving lib's in-plane CTE. CANNOT catch: the daily range itself (it needs 71's hourly run —
    the script checks 71 against its own cache), the gasket term (not computed), or the stack's centring.
    """
    path = MECHANICAL / "pogo_thermal_gap.json"
    if not path.exists():
        pytest.skip("pogo_thermal_gap.json not computed")
    from lib.constants import (
        ALLOY_BASELINE,
        ALLOY_PROPERTIES,
        ALPHA_BRASS_C36000_1K,
        ALPHA_FR4_XY_1K,
        ALPHA_FR4_Z_1K,
        ALPHA_PEEK_1K,
        ALPHA_SS302_1K,
        ALPHA_STEEL_MILD_1K,
    )
    d = json.loads(path.read_text(encoding="utf-8"))
    z52 = json.loads((MECHANICAL / "z_stack_tolerance.json").read_text(encoding="utf-8"))
    c82 = json.loads((MECHANICAL / "collar_running_clearance.json").read_text(encoding="utf-8"))
    radome = json.loads((REPO / "tools/cad/cem/radome.json").read_text(encoding="utf-8"))
    inp = d["inputs"]
    h = radome["pocket_floor_over_rim_mm"]
    assert inp["pocket_floor_over_rim_mm_placeholder"] == h
    assert abs(inp["gap_mm_52"] + 2 * inp["fr4_deck_mm_52"] + inp["standoff_mm_52"] - h) < 1e-6
    assert inp["alpha_fr4_z_1K"] == list(ALPHA_FR4_Z_1K) and inp["alpha_peek_1K"] == ALPHA_PEEK_1K
    co = d["coefficients_um_per_K"]
    radome_k = ALPHA_PEEK_1K * h * 1e3
    stack_lo = 2 * inp["fr4_deck_mm_52"] * ALPHA_FR4_Z_1K[0] * 1e3 + inp["standoff_mm_52"] * ALPHA_STEEL_MILD_1K * 1e3
    stack_hi = 2 * inp["fr4_deck_mm_52"] * ALPHA_FR4_Z_1K[1] * 1e3 + inp["standoff_mm_52"] * ALPHA_SS302_1K * 1e3
    assert abs(co["radome"] - radome_k) <= 1e-4
    assert abs(co["stack"]["low"] - stack_lo) <= 1e-4 and abs(co["stack"]["high"] - stack_hi) <= 1e-4
    gap = {"isothermal_low_stack": radome_k - stack_hi, "isothermal_high_stack": radome_k - stack_lo,
           "radome_leads_reading": radome_k}
    for k, v in gap.items():
        assert abs(co["gap"][k] - v) <= 1e-4, k
    assert gap["isothermal_low_stack"] < gap["isothermal_high_stack"] < gap["radome_leads_reading"]
    pin = inp["pin_free_length_mm"] * ALPHA_BRASS_C36000_1K * 1e3   # the free length moves the tip: stroke = free − gap
    assert inp["pin_free_length_mm"] == z52["springs"]["pogo"]["free_mm"] > inp["gap_mm_52"]
    assert abs(co["pin_body"] - pin) <= 1e-4
    stroke = {"isothermal_low_stack": gap["isothermal_low_stack"] - pin,
              "isothermal_high_stack": gap["isothermal_high_stack"] - pin, "radome_leads_reading": radome_k}
    for k, v in stroke.items():
        assert abs(co["working_stroke"][k] - v) <= 1e-4, k
    t_asm = c82["inputs"]["t_ref_c"]
    travel, win, nom = inp["pogo_travel_mm"], inp["window"], inp["nominal_pct"]
    mitig = {m["label"]: m["residual_pz"] for m in z52["mitigation_escalation"]}
    assert inp["mitigation_residual_mm_52"] == mitig
    for rname, (t_min, t_max) in inp["temperature_readings_c"].items():
        for cname, v in d["seasonal"][rname].items():
            cold, hot = -gap[cname] * (t_asm - t_min), gap[cname] * (t_max - t_asm)
            assert abs(v["gap_um_cold"] - cold) <= 0.06 and abs(v["gap_um_hot"] - hot) <= 0.06, (rname, cname)
            cold, hot = -stroke[cname] * (t_asm - t_min), stroke[cname] * (t_max - t_asm)   # the pins follow the stroke
            assert abs(v["stroke_um_cold"] - cold) <= 0.06 and abs(v["stroke_um_hot"] - hot) <= 0.06, (rname, cname)
            for label, res in mitig.items():
                hi = nom + res / travel - cold * 1e-3 / travel                  # the cold closes the gap → more stroke
                lo = nom - res / travel - hot * 1e-3 / travel
                w = v["window"][label]
                assert w["holds_window"] == (win[0] <= lo and hi <= win[1]), (rname, cname, label)
                assert abs(w["margin_um"][0] - (lo - win[0]) * travel * 1e3) <= 0.06
                assert abs(w["margin_um"][1] - (win[1] - hi) * travel * 1e3) <= 0.06
    rng = d["daily_capsule_range_K"]
    assert 0 < rng["median"] < rng["p95"] < rng["max"] and d["daily_days"] > 10000
    for cname, per in d["daily"].items():
        for st, v in per.items():
            assert abs(v["stroke_um"] - stroke[cname] * rng[st]) <= 0.02, (cname, st)
            assert abs(v["force_ratio_over_min_preload"] - stroke[cname] * rng[st] * 1e-3 / inp["x_preload_min_mm"]) <= 1e-4
    a_ti, sl = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"], d["radial_slide_um_per_mm_radius_per_K"]
    want = {"isothermal": ALPHA_PEEK_1K - a_ti, "flange_held": ALPHA_PEEK_1K, "board_isothermal_low": ALPHA_FR4_XY_1K[0] - a_ti,
            "board_isothermal_high": ALPHA_FR4_XY_1K[1] - a_ti, "board_flange_held_high": ALPHA_FR4_XY_1K[1]}
    assert set(sl) == set(want) and all(abs(sl[k] - v * 1e3) <= 1e-4 for k, v in want.items())
    for k, per in d["radial_slide_daily_um_per_mm_radius"].items():
        for st, v in per.items():
            assert abs(v - d["radial_slide_um_per_mm_radius_per_K"][k] * rng[st]) <= 0.002, (k, st)
    req = d["seasonal"]["capsule_requirement"]
    case_stack = {"isothermal_low_stack": stack_hi + pin, "isothermal_high_stack": stack_lo + pin}   # the pin lags with the stack
    lead = min(min(req[c]["window"]["L1 spacer only"]["margin_um"]) / st for c, st in case_stack.items())
    assert abs(d["radome_lead_tolerated_by_L1_K"] - lead) <= 0.1
    t_min, t_max = inp["temperature_readings_c"]["capsule_requirement"]
    room = ((win[1] - nom) * travel - mitig["L1 spacer only"]) * 1e3
    allowed = min(room / (t_max - t_asm), room / (t_asm - t_min))
    for a in ALPHA_FR4_Z_1K:                                                  # both FR-4 ends, not the kinder one
        alpha0 = (radome_k - 2 * inp["fr4_deck_mm_52"] * a * 1e3 - pin - allowed) / (inp["standoff_mm_52"] * 1e3)
        assert abs(d["spacer_alpha_1K_at_zero_L1_margin"][f"fr4_{int(a * 1e6)}"] - alpha0) <= 1e-8

def test_coating_cluster_cost():
    """Script 99 (HW.40): basis sizes of model coating clusters (measured) and one SCF / a relaxation / an RKS Hessian
    estimated from the pipeline's own timed runs, each as a bracket of named readings. CAN catch: a series point dropped or
    added against its source cache, or its wall times drifting from it; the fitted exponent leaving a log-log fit of those
    points; an anchor that is not the tier's largest SCF; an open-shell reading leaving the 21e series, 34's micro-solvated
    pairs or 21f's ωB97X pairs; a relaxation reading leaving the 21e relaxed caches (the shortest long start; STEPS_MANY ×
    the largest per-step cost); the Hessian ratio leaving 96's cache; an estimate leaving its formula (low: anchor · s_lo ·
    ratio^p_fit; high: anchor · s_hi · composition · ratio^3); an electron count leaving ΣZ − charge or disagreeing with the
    open-shell set; a composite that is not the sum of its parts; a basis count that the script's own builder no longer
    reproduces (PySCF is in the env). CANNOT catch: whether these clusters model the surface, nor the real step count."""
    path = DFT / "coating_cluster_cost.json"
    if not path.exists():
        pytest.skip("coating_cluster_cost.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    series = {c["name"]: c for c in json.loads((DFT / "os_mediator_series.json").read_text(encoding="utf-8"))["complexes"]}
    wb = json.loads((DFT / "os_mediator_series_wb97x.json").read_text(encoding="utf-8"))["complexes"]
    for tier, src in (("21e_b3lyp_631gd", series), ("21f_def2tzvp", wb)):
        pts = d["series_points"][tier]
        assert set(pts) == set(src), tier
        for name, v in pts.items():
            assert v["rks_s"] == src[name]["os2"]["wall_seconds"] and v["uks_s"] == src[name]["os3"]["wall_seconds"], name
        x, y = np.log([v["nao"] for v in pts.values()]), np.log([v["rks_s"] for v in pts.values()])
        assert abs(d["fit_exponent"][tier] - np.polyfit(x, y, 1)[0]) <= 0.006, tier
        top = max(pts, key=lambda k: pts[k]["nao"])
        assert d["anchor"][tier]["name"] == top and d["anchor"][tier]["nao"] == pts[top]["nao"], tier
    micro = json.loads((DFT / "microsolvation_dmbpy.json").read_text(encoding="utf-8"))["results"]
    readings = {"21e_routine_series": [v["uks_s"] / v["rks_s"] for v in d["series_points"]["21e_b3lyp_631gd"].values()],
                "34_microsolvated": [r["os3"]["wall_seconds"] / r["os2"]["wall_seconds"] for r in micro],
                "21f_wb97x_with_rescues": [v["uks_s"] / v["rks_s"] for v in d["series_points"]["21f_def2tzvp"].values()]}
    for k, v in readings.items():
        assert d["open_shell_readings"][k] == [round(min(v), 2), round(max(v), 2)], k
    lo_s = d["open_shell_readings"]["21e_routine_series"][0]
    assert d["open_shell_factor_by_tier"]["21e_b3lyp_631gd"] == [lo_s, d["open_shell_readings"]["34_microsolvated"][1]]
    assert d["open_shell_factor_by_tier"]["21f_def2tzvp"] == [lo_s, d["open_shell_readings"]["21f_wb97x_with_rescues"][1]]
    relax = {}
    for state, fname, key, start in (("os2", "os_mediator_series_relaxed_os2.json", "geometry_os2_relaxed", "long"),
                                     ("os3", "os_mediator_series_relaxed_os3.json", "geometry_os3_relaxed", "near")):
        for name, c in json.loads((DFT / fname).read_text(encoding="utf-8"))["complexes"].items():
            info = c[key]["info"]
            relax[f"{state}_{name}"] = (start, info["wall_seconds"] / c[state]["wall_seconds"], info["steps"])
    assert set(relax) == set(d["relaxations_21e"])
    longs = [v for v in relax.values() if v[0] == "long"]
    rs = d["relaxation_scf_equivalents"]
    assert abs(rs["low_shortest_long_start"] - min(eq for _, eq, _ in longs)) <= 0.06
    assert abs(rs["per_step_high"] - max(eq / st for _, eq, st in longs)) <= 0.0006
    assert abs(rs["high_steps_many_ours"] - rs["steps_many_ours"] * rs["per_step_high"]) <= 0.06
    th = json.loads((DFT / "os_couple_thermo.json").read_text(encoding="utf-8"))["species"]["os2"]
    assert abs(d["rks_hessian_over_scf_96"] - th["hessian_wall_s"] / th["scf_wall_s"]) <= 0.06
    import importlib.util
    spec = importlib.util.spec_from_file_location("s99", Path(__file__).parents[1] / "scripts" / "99_coating_cluster_cost.py")
    s99 = importlib.util.module_from_spec(spec)
    sys.modules["s99"] = s99
    spec.loader.exec_module(s99)
    z_of = {"H": 1, "C": 6, "O": 8, "P": 15, "S": 16, "Ca": 20, "Ti": 22, "Zn": 30}
    rows = d["by_model"]
    for comp_name, parts, minus_h in (("Zn_HAp_on_TiO2_16", ("Zn_HAp_cell", "TiO2_16"), 0),
                                      ("PEDOT_PSS_on_TiO2_16", ("EDOT_trimer_cation", "PSS_dimer", "TiO2_16"), 1)):
        want: dict = {}
        for part in parts:
            for el, n in rows[part]["composition"].items():
                want[el] = want.get(el, 0) + n
        want["H"] -= minus_h
        assert rows[comp_name]["composition"] == want, comp_name
    for name, r in rows.items():
        assert r["n_atoms"] == sum(r["composition"].values()), name
        assert r["n_electrons"] == sum(z_of[el] * n for el, n in r["composition"].items()) - r["charge"], name
        assert r["open_shell"] == (r["n_electrons"] % 2 == 1), name
        assert s99.nao(r["composition"], "21e_b3lyp_631gd", r["charge"])[0] == r["nao"]["21e_b3lyp_631gd"], name
        assert r["nao"]["21f_def2tzvp"] > r["nao"]["21e_b3lyp_631gd"] >= r["nao"]["21e_lanl2dz_3d"], name
        for tier, est in r["estimate"].items():
            a, p_fit = d["anchor"][tier], d["fit_exponent"][tier]
            ratio = r["nao"][tier] / a["nao"]
            comp_f = max(1.0, r["prim_per_nao"][tier] / a["prim_per_nao"])
            assert abs(est["ratio_to_anchor"] - ratio) <= 0.006 and abs(est["composition_factor"] - comp_f) <= 0.006
            s_lo, s_hi = d["open_shell_factor_by_tier"][tier] if r["open_shell"] else (1.0, 1.0)
            ends = sorted((a["rks_s"] * s_lo * ratio ** p_fit / 3600,
                           a["rks_s"] * s_hi * comp_f * ratio ** d["upper_exponent_ours"] / 3600))
            assert abs(est["one_scf_h"]["low"] - ends[0]) <= 0.006 and abs(est["one_scf_h"]["high"] - ends[-1]) <= 0.006
            assert abs(est["relaxation_days"]["low"] - est["one_scf_h"]["low"] * rs["low_shortest_long_start"] / 24) <= 0.06
            assert abs(est["relaxation_days"]["high"] - est["one_scf_h"]["high"] * rs["high_steps_many_ours"] / 24) <= 0.3
            hess = est["rks_hessian_days"]
            assert (hess is None) == (r["open_shell"] and tier == "21f_def2tzvp"), (name, tier)
    assert not d["env"]["uks_nlc_hessian"] or all(e["rks_hessian_days"] for r in rows.values() for e in r["estimate"].values())


def test_field_strain_campaign():
    """Script 98 (HW.43): the field strain campaign's length, replayed year by year from ERA5 wind, and its battery trips.
    CAN catch: the power arithmetic leaving the primaries' figures (receiver + sensors; the control — ten sensors on 60 Ah
    must give Nickl 2022's 152 h), battery days leaving Ah / A / 24, a quantile that is not an actual year's value at
    numpy's «higher» index or that interpolates (p50 ≤ p75 ≤ p90 must hold and each must equal a sorted replay value), a
    censored start not ranking last, a «within N days» share leaving the replay, trips leaving ceil(days / battery days)
    + 1, the best start not being the smallest median, monthly rates that do not fall as the threshold rises, a month
    with no strong hour that still claims a storm. CANNOT catch: the ERA5 hourly counts themselves (they need the
    262 992-hour series — the script reads it through 71's loader, and its own control checks the storm runs against
    the strong hours), nor whether 10 hours suffice."""
    path = MECHANICAL / "field_strain_campaign.json"
    if not path.exists():
        pytest.skip("field_strain_campaign.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    pw = d["power"]
    cur = pw["receiver_A"] + pw["n_tss"] * pw["tss_A"] + pw["n_trs"] * pw["trs_A"]
    assert abs(pw["current_A"] - cur) < 1e-4
    assert abs(60.0 / (pw["receiver_A"] + 10 * pw["tss_A"]) - pw["control_paper_h"]) <= 0.02 * pw["control_paper_h"]
    ah = {"60_Ah_as_in_the_papers": 60.0, "100_Ah_ours": 100.0}
    for k, a in ah.items():
        assert abs(d["battery_days"][k] - a * pw["usable_fraction_ours"] / cur / 24.0) <= 0.005, k
    th = d["thresholds_ms"]
    order = sorted(th, key=th.get)                                     # rates must fall as the threshold rises
    n_years = d["years"][1] - d["years"][0] + 1
    for m, r in d["by_month"].items():
        rates = [r["hours_per_day"][k] for k in order]
        assert rates == sorted(rates, reverse=True), (m, rates)
        if r["hours_per_day"]["beaufort_5"] == 0:
            assert r["beaufort_5_storms_30y"] == 0 and r["years_without_beaufort_5"] == n_years, m
        runs = r["replay_days_by_year"]
        assert len(runs) == n_years and r["censored_years"] == sum(1 for x in runs if x is None)
        ranked = sorted(x if x is not None else math.inf for x in runs)
        for q in (50, 75, 90):
            want = ranked[math.ceil(q / 100 * (n_years - 1))]      # numpy «higher»: an actual year's value
            got = r["replay_days"][f"p{q}"]
            assert (got is None) if math.isinf(want) else abs(got - want) <= 0.06, (m, q)
        for days, share in r["share_within_days"].items():
            assert abs(share - sum(1 for x in ranked if x <= float(days)) / n_years) <= 0.0006, (m, days)
        for at, key in (("trips_at_median", "p50"), ("trips_at_p75", "p75")):
            days = r["replay_days"][key]
            for bk, bd in d["battery_days"].items():
                want = None if days is None else math.ceil(days / bd) + 1
                assert r[at][bk] == want or (days is not None and r[at][bk] in
                                             {math.ceil((days + e) / bd) + 1 for e in (-0.05, 0.05)}), (m, at, bk)
    med = {m: r["replay_days"]["p50"] for m, r in d["by_month"].items() if r["replay_days"]["p50"] is not None}
    assert d["best_start_month"] == min(med, key=med.get)
    for m, c in d["capped_by_start_month"].items():               # the 1-May cap, recomputed from its season list
        ss = c["seasons"]
        assert c["n_seasons"] == len(ss) and c["seasons_not_reached"] == sum(1 for s in ss if not s["reached"]), m
        assert all(s["reached"] == (s["beaufort_5_hours_by_cap"] >= d["target_beaufort_5_hours_ours"]) for s in ss), m
        assert abs(c["share_reached_by_cap"] - (1 - c["seasons_not_reached"] / len(ss))) <= 0.0006, m
        assert c["seasons_with_zero_by_cap"] == sum(1 for s in ss if s["beaufort_5_hours_by_cap"] == 0), m
        hrs = sorted(s["beaufort_5_hours_by_cap"] for s in ss)
        used = sorted(s["days_used"] for s in ss)
        assert c["beaufort_5_hours_by_cap_median"] == hrs[math.ceil(0.5 * (len(ss) - 1))], m
        assert abs(c["days_used_median"] - used[math.ceil(0.5 * (len(ss) - 1))]) <= 0.006 and c["days_used_max"] == used[-1]
        for bk, bd in d["battery_days"].items():
            assert c["trips_max"][bk] == math.ceil(c["days_used_max"] / bd) + 1, (m, bk)
            assert c["trips_median"][bk] == math.ceil(c["days_used_median"] / bd) + 1, (m, bk)
        by_year = dict(zip(range(d["years"][0], d["years"][1] + 1), d["by_month"][m]["replay_days_by_year"], strict=True))
        for s in ss:                                   # a reached season used no more days than its uncapped replay
            full = by_year[s["start_year"]]
            assert (not s["reached"]) or (full is not None and abs(s["days_used"] - full) <= 0.006), (m, s["start_year"])
    th = d["set_with_third_tss"]
    cur3 = pw["receiver_A"] + th["n_tss"] * pw["tss_A"] + pw["n_trs"] * pw["trs_A"]
    assert th["n_tss"] == pw["n_tss"] + 1 and abs(th["current_A"] - cur3) < 1e-4
    dec = d["capped_by_start_month"]["12"]
    for k, a in ah.items():
        bd3 = th["battery_days"][k]
        assert abs(bd3 - a * pw["usable_fraction_ours"] / cur3 / 24.0) <= 0.005, k
        assert th["december_capped_trips_max"][k] == math.ceil(dec["days_used_max"] / bd3) + 1, k
        assert th["december_capped_trips_median"][k] == math.ceil(dec["days_used_median"] / bd3) + 1, k
    # (5) the battery type. CAN catch: the set's current or battery days leaving the third-TSS variant, the swap fraction
    # leaving 14 / battery days, a threshold or a fortnight's battery days leaving its sheet's piecewise line (extrapolated
    # along the coldest segment), a derated chain giving FEWER trips than the full rating in the same season, a quantile
    # that is not an actual season's value, a per-type range leaving its readings, a season count leaving its per-season
    # list, an AGM state of charge or freezing point at a swap leaving the table, a reading without its «basis», the
    # 14-day cap or calendar that REMOVES batteries, a shorter calendar with MORE cut-offs, the 14-day calendar leaving
    # ceil(days / 14) + 1, the ratified rule's chain leaving the Victron reading's trips or cutting off on its own
    # reading, a longer coldest mean that is colder, the cache calling a reading a floor or the air the cold side again,
    # and verdict prose without the computed counts. CANNOT catch: the hourly ERA5 counts themselves (the cut-off and
    # freezing counts need the 262 992-hour series), nor the sheets' transcriptions.
    bt = d["battery_type"]
    bd = th["battery_days"]["100_Ah_ours"]
    assert abs(bt["current_A"] - th["current_A"]) < 1e-4 and bt["battery_days_full_rating"] == bd
    assert abs(bt["capacity_fraction_needed_for_swap"] - bt["swap_days_ratified_ours"] / bd) <= 0.0006
    n = bt["seasons"]
    assert n == dec["n_seasons"]

    def frac(points, t):
        ts, fs = [p[0] for p in points], [p[1] for p in points]
        if t < ts[0]:
            return fs[0] + (fs[1] - fs[0]) / (ts[1] - ts[0]) * (t - ts[0])
        for (t0, f0), (t1, f1) in itertools.pairwise(points):
            if t0 <= t <= t1:
                return f0 + (f1 - f0) * (t - t0) / (t1 - t0)
        return fs[-1]

    def higher(xs, q):
        return sorted(xs)[math.ceil(q * (len(xs) - 1))]

    def interp(x, table):
        i = next(j for j in range(1, len(table)) if table[j][0] >= x)
        return table[i - 1][1] + (x - table[i - 1][0]) * (table[i][1] - table[i - 1][1]) / (table[i][0] - table[i - 1][0])

    c14 = bt["coldest_fortnight_mean_C"]
    assert len(c14["by_season"]) == n and c14["min"] == min(c14["by_season"])
    assert abs(c14["median"] - higher(c14["by_season"], 0.5)) <= 0.051
    full_trips = [math.ceil(s["days_used"] / bd) + 1 for s in dec["seasons"]]
    need = bt["capacity_fraction_needed_for_swap"]
    for name, ty in bt["types"].items():
        for src, fl in ty["discharge_floors"].items():
            for r, v in fl["hours_below_by_season"].items():
                assert len(v) == n and fl["seasons_with_hours_below"][r] == sum(1 for x in v if x > 0), (name, src, r)
        for rn, rd in ty["cold_readings"].items():
            assert rd.get("basis"), (name, rn)                            # every reading names what kind it is
            pts = rd["points"]
            ts, fs = [p[0] for p in pts], [p[1] for p in pts]
            assert fs == sorted(fs), (name, rn)                           # capacity rises with temperature
            i = next(j for j in range(1, len(pts)) if fs[j] >= need)
            want = ts[i - 1] + (need - fs[i - 1]) * (ts[i] - ts[i - 1]) / (fs[i] - fs[i - 1])
            assert abs(rd["threshold_mean_C_for_14_day_swap"] - want) <= 0.15, (name, rn)
            for key, t in (("battery_days_at_median_coldest_fortnight", c14["median"]),
                           ("battery_days_at_coldest_fortnight", c14["min"])):
                assert abs(rd[key] - frac(pts, t) * bd) <= 0.15, (name, rn, key)
            tr = rd["trips_by_season"]
            assert len(tr) == n and all(c >= f for c, f in zip(tr, full_trips, strict=True)), (name, rn)
            assert rd["trips_median"] == higher(tr, 0.5) and rd["trips_max"] == max(tr), (name, rn)
            assert rd["shortest_battery_days"] is None or rd["shortest_battery_days"] <= bd, (name, rn)
        rr, rs = ty["readings_range"], ty["cold_readings"].values()
        for key in ("battery_days_at_median_coldest_fortnight", "battery_days_at_coldest_fortnight", "trips_median",
                    "trips_max"):
            assert rr[key] == [min(r[key] for r in rs), max(r[key] for r in rs)], (name, key)
    fz = bt["types"]["agm_lead_acid"]["freezing"]
    assert fz["maker_on_freezing"]
    for days, f in fz["by_swap_days"].items():
        assert abs(f["soc_at_swap_pct"] - 100 * (1 - int(days) / bd)) <= 0.06, days
        assert abs(f["freezing_point_at_swap_C"] - interp(f["soc_at_swap_pct"], fz["freezing_point_C_by_soc"])) <= 0.1, days
        for r, v in f["freeze_hours_by_season"].items():
            assert len(v) == n and f["seasons_with_freeze_hours"][r] == sum(1 for x in v if x > 0), (days, r)
    full14 = [math.ceil(s["days_used"] / bt["swap_days_ratified_ours"]) + 1 for s in dec["seasons"]]
    assert bt["trips_every_14_days"] == {"median": higher(full14, 0.5), "max": max(full14)}
    for name, ty in bt["types"].items():                         # the 14-day cap can only add batteries
        for rn, rd in ty["cold_readings"].items():
            rr = rd["ratified_rule"]
            assert all(a >= b for a, b in zip(rr["trips_by_season"], rd["trips_by_season"], strict=True)), (name, rn)
            assert all(a >= b for a, b in zip(rr["trips_by_season"], full14, strict=True)), (name, rn)
            assert rr["trips_median"] == higher(rr["trips_by_season"], 0.5) and rr["trips_max"] == max(rr["trips_by_season"])
    rules = bt["swap_rules_lifepo4"]
    assert rules["every_14_days"]["trips_by_season"] == full14
    for rname, ru in rules.items():
        assert ru["trips_median"] == higher(ru["trips_by_season"], 0.5) and ru["trips_max"] == max(ru["trips_by_season"]), rname
    for rn in bt["types"]["lifepo4"]["cold_readings"]:           # shorter intervals can only remove cut-offs
        risk = [rules[k]["at_risk_by_lifepo4_reading"][rn]["seasons"]
                for k in ("every_10_days", "december_to_march_every_10_else_14", "december_to_february_every_10_else_14",
                          "every_14_days")]
        assert risk == sorted(risk), (rn, risk)
    inc = rules["ratified_rule_on_victron_reading"]
    vic = bt["types"]["lifepo4"]["cold_readings"]["victron_pack_le_1c"]["ratified_rule"]
    assert inc["trips_by_season"] == vic["trips_by_season"]       # one rule, two codes
    assert inc["at_risk_by_lifepo4_reading"]["victron_pack_le_1c"]["seasons"] == 0   # swapped when its own reading empties
    cm = bt["coldest_mean_air_over_days_C"]
    assert [cm[k] for k in sorted(cm, key=int)] == sorted(cm.values())   # a longer mean is never colder
    assert abs(cm["14"] - c14["min"]) <= 0.051 and cm["1"] >= bt["air_min_C"]
    for dd, fr in bt["capacity_fraction_needed_for_swap_days"].items():
        assert abs(fr - int(dd) / bd) <= 0.0006, dd
    rh = bt["air_rh_above_spec"]
    ft = bt["freezer_test"]                                       # the pass/fail stop and the band's ends
    stop = bt["swap_days_ratified_ours"] * 24 * bt["current_A"]
    assert abs(ft["stop_Ah_for_14_days_at_this_current"] - stop) <= 0.06
    assert ft["stop_Ah_rounded_up"] == math.ceil(stop) and ft["stop_Ah_with_10_pct_current_margin"] == math.ceil(stop * 1.1)
    assert ft["accepted_mean_C"][1] <= bt["coldest_mean_air_over_days_C"]["10"], "the freezer window misses the 10-day mean"
    be = ft["band_ends_under_the_ratified_rule"]
    lo, hi = sorted(be, key=float)
    assert be[hi]["trips_by_season"] == full14, "at the band's top end the ratified rule must give 14-day swaps"
    assert be[hi]["intervals_shorter_than_14_days"] == 0 and be[hi]["shortest_full_interval_h"] == 24 * bt["swap_days_ratified_ours"]
    assert be[lo]["intervals_shorter_than_14_days"] >= be[hi]["intervals_shorter_than_14_days"]
    assert all(a >= b for a, b in zip(be[lo]["trips_by_season"], be[hi]["trips_by_season"], strict=True))
    for k, v in be.items():
        assert v["trips_median"] == higher(v["trips_by_season"], 0.5) and v["trips_max"] == max(v["trips_by_season"]), k
    f14 = fz["by_swap_days"][str(bt["swap_days_ratified_ours"])]
    v = bt["verdict"]
    ph = f14["seasons_with_freeze_hours_over_first_swap_day"]["air_24h_mean"]
    assert f"in {ph[0]}–{ph[1]} of {n} campaigns on the 24-hour mean" in v
    lfp = next(iter(bt["types"]["lifepo4"]["discharge_floors"].values()))
    assert f"crosses in {lfp['seasons_with_hours_below']['air_24h_mean']} campaigns on the 24-hour mean" in v
    assert f"above it {rh['share_of_campaign_hours'] * 100:.0f} % of the campaign hours" in v
    blob = json.dumps(d, ensure_ascii=False)
    for allowed in ("not a proven floor", "no reading is a proven floor", "not shown to be a floor"):
        blob = blob.replace(allowed, "")
    assert not re.search(r"each a floor|shown to be a floor|(?:reading|curve)s? (?:is|are) a floor|the cold side", blob), \
        "the cache calls a reading a floor or the air the cold side"


def test_sap_recipe_saturation():
    """Script 67 (HW.3): calcium oxalate saturation of the `01_02 §2.1` synthetic sap.

    Sanity is STRUCTURAL — the headline numbers are pinned by test_doc_cache_sync, and only a subset of what the
    docs quote is. Five things must hold:
      1. the verdict: every pre-verdict corner supersaturated, in both tests, under every constant reading evaluated;
      2. the window rests on the HARD BOUND, which needs no calcium or magnesium malate constant — so the margins
         the script computed must stay non-negative (they cover only the readings and the swept constants the
         script evaluates; a reading it never runs is invisible here), the sweep must still reach a strong
         constant, and the bound's window must stay the narrowest;
      3. the window moves the right way: more of the held ion leaves less room for the other;
      4. the malic-acid equation coefficients in the cache still reproduce the 25 °C constants in the cache — two
         transcriptions checked against each other, so an error made the same way in both passes; only the page
         image of the primary catches that;
      5. both points are what their derivations say — Q6 (⚖️ 2026-09-17, history): no oxalate, the other four at the
         geometric mid of the pre-verdict range; Q7 (⚖️ 2026-10-18, live): no oxalate, Ca · Mg at the geometric mid
         of the cache's measured trunk-base rows minus the excluded fertilized row, nitrate at its measured mid,
         malate at the cache's solve — and each prices a preparable medium: base positive and larger at the higher
         pH, potassium = KNO3 + base, gypsum undersaturated, buffer capacity positive. CANNOT catch: a wrong solve
         (`malic_solved_mM` is checked only against the point it rounds to, and the potassium it gives against the
         measured mid — a solve at the wrong pH or temperature that lands near that mid passes; the script asserts
         the solve itself), or a mis-transcribed row (only the page images in the scratch tree catch that).
    """
    path = CHEMISTRY / "sap_recipe_saturation.json"
    if not path.exists():
        pytest.skip("sap_recipe_saturation.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    per_test = d["q1_corners"]["per_test"]
    assert set(per_test) == {"coin", "accelerated"}
    for test, readings in per_test.items():
        for key, s in readings.items():
            assert s["every_corner_supersaturated"] and s["si_whewellite_min"] > 0.0, f"{test}/{key}"
            assert s["si_range_other_solids"]["gypsum CaSO4·2H2O"][1] < 0.0, "gypsum reached saturation"
    assert d["verification"]["hard_bound_min_si_margin_over_every_reading"] >= 0.0
    assert d["verification"]["hard_bound_min_si_margin_over_swept_malate_constants"] >= 0.0
    assert max(d["verification"]["dominance_sweep_log_k"]) >= 8.0, "the dominance sweep no longer reaches a strong constant"
    windows = d["q2_window"]["per_scenario"]
    for key, per_scenario in windows.items():
        for test in per_test:
            for fixed in ("Ca", "Ox"):
                limits = [w["partner_max_total_uM"] for w in per_scenario[test][fixed]]
                assert limits == sorted(limits, reverse=True), f"{key}/{test}/{fixed}: window not monotone"
                bound = [w["partner_max_total_uM"] for w in windows["hard_bound"][test][fixed]]
                assert all(b <= x * (1.0 + 1e-6) for b, x in zip(bound, limits, strict=True)), \
                    f"{key}/{test}/{fixed}: narrower than the hard bound"
    malic, t_k = d["constants"]["malic_acid"], 298.15
    for (a3, a1, a2), k25 in zip((malic["pk1_equation"], malic["pk2_equation"]), malic["k_25c_printed"], strict=True):
        assert abs(a3 / t_k + a1 + a2 * t_k + math.log10(k25)) < 2e-3, "malic-acid equation ≠ its printed constant"
    q6, q7 = d["q6_point_2026_09_17_superseded"], d["q7_revised_point"]
    for q in (q6, q7):
        assert q["recipe_mM"]["oxalic"] == 0.0, "oxalate stays out"
    for key, (lo, hi) in d["recipe_ranges_mM"].items():   # Q6 — history: the 2026-09-17 derivation
        if key != "oxalic":
            assert q6["recipe_mM"][key] == float(f"{math.sqrt(lo * hi):.2g}"), f"{key}: not the geometric mid"
    # Q7 — the live point re-derived from the rows the cache carries (the script asserts the same; this catches a cache
    # whose recorded rows and point disagree — a hand-edited cache or a script that stopped asserting).
    meas = q7["measured"]
    used = [r for k, r in meas["rows_mg_per_l"].items() if k not in meas["rows_excluded"]]
    assert set(meas["rows_excluded"]) == {"this_study_podzol_fertilized"}, meas["rows_excluded"]
    for key, ion in (("cacl2", "Ca"), ("mgso4", "Mg"), ("k_total", "K")):
        lo, hi = min(r[ion] for r in used), max(r[ion] for r in used)
        assert meas["trunk_base_mg_per_l"][key] == [lo, hi], key
        mid = math.sqrt(lo * hi) / {"Ca": 40.078, "Mg": 24.305, "K": 39.098}[ion]
        assert abs(meas["geometric_mid_mM"][key] - mid) < 1e-4, key
        if key != "k_total":
            assert q7["recipe_mM"][key] == float(f"{mid:.2g}"), f"{key}: not the measured trunk-base mid"
    no3 = meas["nitrate_mM"]
    assert q7["recipe_mM"]["kno3"] == float(f"{math.sqrt(no3[0] * no3[1]):.2g}"), "kno3: not the nitrate mid"
    assert q7["recipe_mM"]["malic"] == float(f"{meas['malic_solved_mM']:.2g}"), "malic: not the solve"
    assert abs(meas["potassium_total_at_point_mM"] - meas["geometric_mid_mM"]["k_total"]) < 0.02, \
        "the rounded malate moved potassium off the measured mid by more than rounding"
    for q in (q6, q7):
        for name, c in q["conditions"].items():
            base_lo, base_hi = c["base_koh_mM"]
            assert 0.0 < base_lo <= base_hi, name
            for k_total, base in zip(c["potassium_total_mM"], c["base_koh_mM"], strict=True):
                assert abs(k_total - (base + q["recipe_mM"]["kno3"])) < 2e-3, f"{name}: K+ total ≠ KNO3 + base"
            assert c["si_gypsum_max"] < 0.0 and c["buffer_capacity_mM_per_pH_25c"] > 0.0, name
        setpoint, side = q["conditions"]["setpoint"], q["conditions"]["side_series"]
        assert setpoint["ph"] > side["ph"] and setpoint["base_koh_mM"][0] > side["base_koh_mM"][1], \
            "more malic acid is dissociated at the higher pH, so it must take more base"
    vs = q7["against_point_2026_09_17_setpoint"]
    assert vs["ionic_strength_ratio"] < 1.0 and vs["buffer_capacity_ratio"] < 1.0 and vs["potassium_total_ratio"] < 1.0, vs
    assert (CHEMISTRY / "sap_recipe_saturation.png").stat().st_size > 10_000


def test_sap_recipe_q8_crown_twig_readings():
    """Script 67, Q8: the two crown-twig readings beside the broadleaf point (00_07 HW.3 (А)) — Soper 2018 and
    Schneider 1996 — re-derived from what the cache itself carries: the Soper means (µg/mL), Q8's dated medians and
    their read-off error. The read-off envelope is rebuilt HERE, independently of the script's: each end of each ion's
    range moved by −e, 0 or +e (the end itself, not one date — so a «re-take the extremes» rule would red here).

    CAN catch: a hand-edited mM, mid or ratio; a month counted inside or outside the dated beech range against the
    numbers; a count or a flip list that holds only on the nominal medians; a low month or a mid without it that
    disagrees with the means; a ±1 SD benchmark that is not erf(1/√2); an «upper arm only» label on a bar that does not
    reach the axis; a Schneider flag that disagrees with the dated nitrate the cache prints. CANNOT catch a mis-read
    figure — the means and the symmetric SDs are a transcription of Soper's Fig. 1 vectors, held only by the verifier's
    independent extraction in the scratch tree, and the three upper-arm-only Mg SDs not even by that (it checked them
    only as a share of the mean) — and it does not judge whether crown twigs may stand for the trunk base (the
    script's prose says they may not)."""
    import itertools
    path = CHEMISTRY / "sap_recipe_saturation.json"
    if not path.exists():
        pytest.skip("sap_recipe_saturation.json not computed")
    q8 = json.loads(path.read_text(encoding="utf-8"))["q8_broadleaf_point"]
    cr, med = q8["crown_twig_readings"], q8["measured"]["medians_by_date"]
    molar = {"K": 39.098, "Ca": 40.078, "Mg": 24.305}
    beech = {ion: (min(r[f"{ion}_mg_l"] for r in med.values()) / molar[ion], max(r[f"{ion}_mg_l"] for r in med.values()) / molar[ion])
             for ion in molar}
    s = cr["soper_2018"]
    months, upper = s["months"], {tuple(c) for c in s["sd_upper_arm_only"]}
    assert set(s["by_species"]) == {"Quercus rubra", "Quercus prinus", "Acer saccharum"}
    oak_in = oak_n = with_sd = 0
    shares, oak_within = [], []
    for sp, ions in s["means_ug_ml"].items():
        for ion, means in ions.items():
            mm = [v / molar[ion] for v in means]
            p = s["by_species"][sp][ion]
            assert p["monthly_mM"] == {m: round(x, 4) for m, x in zip(months, mm, strict=True)}, (sp, ion)
            mid = math.sqrt(min(mm) * max(mm))
            q8_mid = math.sqrt(beech[ion][0] * beech[ion][1])
            assert abs(p["q8_rule_mid_mM"] - mid) < 1e-4 and abs(p["over_q8_mid"] - mid / q8_mid) < 1e-3, (sp, ion)
            out = [m for m, x in zip(months, mm, strict=True) if not beech[ion][0] <= x <= beech[ion][1]]
            assert p["months_outside_dated_beech_range"] == out, (sp, ion)
            if sp.startswith("Quercus"):
                oak_n += len(months)
                oak_in += len(months) - len(out)
            for m, v, sd in zip(months, means, s["sd_ug_ml"][sp][ion], strict=True):
                within = None if sd is None else (v - sd) / molar[ion] <= q8_mid <= (v + sd) / molar[ion]
                assert p["q8_mid_within_one_sd"][m] == within, (sp, ion, m)
                if sd is not None:
                    with_sd += 1
                    shares.append(sd / v)
                    assert ((sp, ion, m) in upper) == (sd >= v), f"{sp} {ion} {m}: an upper-arm-only SD is one that reaches the mean"
                    if sp.startswith("Quercus"):
                        oak_within.append(within)
    assert s["oak_cells_inside_dated_beech_range"] == [oak_in, oak_n]
    assert s["oak_cells_q8_mid_within_one_sd"] == [sum(oak_within), len(oak_within)]
    assert s["sd_over_mean_range"] == [round(min(shares), 3), round(max(shares), 3)]
    assert s["cells_with_sd"] == [with_sd, 3 * 3 * len(months)]
    from scipy.stats import t as student_t
    cov = math.erf(1.0 / math.sqrt(2.0))
    n_tr = s["trees_per_species"]
    cov_t = 2.0 * student_t.cdf(1.0 / math.sqrt(1.0 + 1.0 / n_tr), n_tr - 1) - 1.0   # new tree in the SAMPLE mean ± SD
    assert n_tr == 8 and s["one_sd_coverage_if_normal"] == round(cov, 3) and s["one_sd_coverage_new_tree_t"] == round(cov_t, 3)
    assert s["oak_expected_within_if_normal"] == round(cov * len(oak_within), 1)
    assert s["oak_expected_within_new_tree_t"] == round(cov_t * len(oak_within), 1)
    assert s["cells_with_sd_at_or_above_mean"] == len(upper)
    # the read-off envelope, rebuilt from the cache's medians and error
    err = s["read_off_error_mg_l"]
    ends = {ion: [((min(r[f"{ion}_mg_l"] for r in med.values()) + a) / molar[ion],
                   (max(r[f"{ion}_mg_l"] for r in med.values()) + b) / molar[ion])
                  for a, b in itertools.product((-err[f"{ion}_mg_l"], 0.0, err[f"{ion}_mg_l"]), repeat=2)] for ion in molar}
    readings = [dict(zip(ends, c, strict=True)) for c in itertools.product(*ends.values())]
    assert s["read_off_readings"] == len(readings) == 9 ** 3

    def tally(rng):
        out = {}
        for sp, ions in s["means_ug_ml"].items():
            ins, wit = set(), set()
            for ion, means in ions.items():
                lo_, hi_ = rng[ion]
                mid_ = math.sqrt(lo_ * hi_)
                for m, v, sd in zip(months, means, s["sd_ug_ml"][sp][ion], strict=True):
                    if lo_ <= v / molar[ion] <= hi_:
                        ins.add(f"{ion} {m}")
                    if sd is not None and (v - sd) / molar[ion] <= mid_ <= (v + sd) / molar[ion]:
                        wit.add(f"{ion} {m}")
            out[sp] = (ins, wit)
        return out
    nominal, tallies = tally(beech), [tally(r) for r in readings]
    oaks = ("Quercus rubra", "Quercus prinus")
    oak_i = [sum(len(t[sp][0]) for sp in oaks) for t in tallies]
    oak_w = [sum(len(t[sp][1]) for sp in oaks) for t in tallies]
    assert s["oak_cells_inside_under_read_off"] == [min(oak_i), max(oak_i)]
    assert s["oak_cells_q8_mid_within_one_sd_under_read_off"] == [min(oak_w), max(oak_w)]
    for sp, t in s["tally_by_species"].items():
        ins, wit = [len(x[sp][0]) for x in tallies], [len(x[sp][1]) for x in tallies]
        assert t["cells_inside_dated_beech_range"][0] == len(nominal[sp][0]), sp
        assert t["cells_inside_under_read_off"] == [min(ins), max(ins)], sp
        assert t["cells_q8_mid_within_one_sd"][0] == len(nominal[sp][1]), sp
        assert t["cells_q8_mid_within_one_sd_under_read_off"] == [min(wit), max(wit)], sp
        assert t["cells_that_flip_under_read_off"] == {
            "inside": sorted({c for x in tallies for c in x[sp][0] ^ nominal[sp][0]}),
            "within_one_sd": sorted({c for x in tallies for c in x[sp][1] ^ nominal[sp][1]})}, sp

    def side(lo_r, hi_r):
        return "above" if lo_r > 1.0 else "below" if hi_r < 1.0 else "straddles"
    for sp, ions in s["means_ug_ml"].items():
        for ion, means in ions.items():
            p, mm = s["by_species"][sp][ion], [v / molar[ion] for v in means]
            q8s = [math.sqrt(r[ion][0] * r[ion][1]) for r in readings]
            loo = {}
            for out_m in months:   # every exclusion — a «lowest month only» would lift the mid one-sidedly
                rest = [x for m, x in zip(months, mm, strict=True) if m != out_m]
                loo[out_m] = math.sqrt(min(rest) * max(rest))
            assert p["q8_rule_mid_leave_one_month_out_mM"] == {m: round(v, 5) for m, v in loo.items()}, (sp, ion)
            assert p["leave_one_month_out_mM"] == [round(min(loo.values()), 5), round(max(loo.values()), 5)], (sp, ion)
            r_loo = (min(loo.values()) / max(q8s), max(loo.values()) / min(q8s))
            assert p["over_q8_mid_leave_one_month_out_under_read_off"] == [round(r_loo[0], 3), round(r_loo[1], 3)], (sp, ion)
            assert p["leave_one_month_out_side_under_read_off"] == side(*r_loo), (sp, ion)
            mid = math.sqrt(min(mm) * max(mm))
            r_mid = (mid / max(q8s), mid / min(q8s))
            assert p["over_q8_mid_under_read_off"] == [round(r_mid[0], 3), round(r_mid[1], 3)], (sp, ion)
            assert p["side_under_read_off"] == side(*r_mid), (sp, ion)
    n = cr["schneider_1996"]
    no3 = q8["measured"]["nitrate"]
    lo, hi = no3["range_mM"]
    assert n["dated_beech_nitrate_range_mM"] == [lo, hi] and n["dated_beech_nitrate_mid_mM"] == no3["geometric_mid_mM"]
    assert n["inside_dated_beech_range"] == (lo <= n["nitrate_mM"][0] and n["nitrate_mM"][1] <= hi)
    assert n["below_point_mid"] == (n["nitrate_mM"][1] < no3["geometric_mid_mM"])
    assert ("no evidence against the point" in n["why_a_reading_not_a_point"]) == n["inside_dated_beech_range"]


def test_chem11_aggregation_compensation():
    """Script 69 (CHEM.11): compensating surface-polar mutations for the aglycosylated dgrFAD-GDH.

    This cache gates a GENE FREEZE, so the pins are about the integrity of the argument, not about
    digits (the headline numbers are pinned doc↔cache by test_doc_cache_sync). What must hold:
      1. the hotspot set is exactly the four L1 §2 publishes, and the cache SAYS whether its own
         proxy re-selects them — a `reselects_published_set: false` must never pass silently;
      2. the radius sensitivity DISCRIMINATES: there is at least one swept radius where the proxy
         does NOT re-select the four. Without that row the sweep is a rubber stamp, and the whole
         point of the sweep is that membership is radius-dependent;
      3. no recommended mutation sits in a HARD keep-out (FAD pocket · electron path · buried ·
         too little apolar area). These are the irreversible ones: they trade the MET architecture
         or the fold for aggregation margin;
      4. the secondary-structure rule is Asp-scoped BY CONSTRUCTION, so it is pinned on its own
         scale: no recommended ASP sits in a regular element. Folding it into (3) would judge Ser
         by a rule written for a carboxylate;
      5. every recommended mutation measurably REDUCES its hotspot's apolar patch — Δ < 0 and
         past the run's own measured noise floor, so the sign is a finding and not rounding;
      6. the frozen backbone held (CA drift 0), which is what makes re-attaching the cofactor
         coordinates legitimate; and the pLDDT convention still reproduces the canon Tyr90 value;
      7. a hotspot with no admissible candidate is RECORDED as such with its reasons — the
         absence is the finding for Gln200/Gln258 and must not decay into an empty list;
      8. the candidate collection really reached past the primary radius, else the 12 Å
         sensitivity row is a copy of the 10 Å one and only looks like a measurement.
    """
    path = CHEMISTRY / "chem11_aggregation_compensation.json"
    if not path.exists():
        pytest.skip("chem11_aggregation_compensation.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))

    # 1 — the four sites, and the proxy's own verdict on itself
    published = {71, 200, 258, 405}
    assert {h["site"] for h in d["hotspots"]} == published, "hotspot set is no longer the L1 §2 four"
    assert len(d["hotspots"]) == 4
    assert d["provenance"]["reselects_published_set"] is True, \
        "the declared proxy stopped re-selecting the published four — that is a canon conflict, not a test failure"

    # 2 — the sweep must be able to disagree
    sweep = d["proxy_sensitivity"]["radius"]
    assert any(r["reselects_published_set"] for r in sweep)
    assert any(not r["reselects_published_set"] for r in sweep), \
        "no swept radius disagrees — the sensitivity cannot discriminate and proves nothing"
    assert not any(row["reselects_published_set"]
                   for s in d["proxy_sensitivity"]["residue_set"] if s["residue_set"] == "kyte_doolittle_positive"
                   for row in s["rows"]), "the set without aromatics now reproduces the four — re-read the verdict"

    # 3/4/5 — the recommended set
    hard = ("fad_pocket", "electron_path", "buried", "too_little_apolar")
    floor = d["controls"]["patch_sasa_noise_floor_A2"]
    assert floor > 0.0, "a zero noise floor means it was not measured"
    ss_risky = set(d["declared_parameters"]["ss_risky_for_asp"])
    for rec in d["recommended"]:
        where = rec["position_label"]
        bad = [e for e in rec["excluded_by"] if e.startswith(hard)]
        assert not bad, f"{where} is recommended from inside a hard keep-out: {bad}"
        # Asp stays refused in a regular element whether it arrives as the pick, as one of the
        # admissible pair, or as the residue the combined variant was built from.
        if "ASP" in set(rec["admissible_substitutions"]) | {rec["to"], rec["built_as_for_the_combined_variant"]}:
            assert rec["dssp"] not in ss_risky, \
                f"{where}: Asp admitted inside a regular secondary-structure element ({rec['dssp']})"
        # A tie the measurement cannot break must NOT be resolved into a recommendation: the ranked
        # winner at such a position was measured flipping between identical runs, and the difference
        # between Asp and Ser is a CHARGE.
        if rec["substitution_undecided_by_this_measurement"]:
            assert rec["to"] is None and rec["mutation"] is None, \
                f"{where}: a tie inside the noise floor was silently resolved into {rec['to']}"
            assert len(rec["admissible_substitutions"]) > 1
        else:
            assert rec["to"] in rec["admissible_substitutions"]
        for sub, delta in rec["delta_patch_apolar_A2_by_substitution"].items():
            if sub in rec["admissible_substitutions"]:
                assert delta < -floor, f"{where}→{sub}: Δ {delta} does not clear the {floor} Å² floor"
        assert rec["delta_patch_apolar_A2"] < -floor, \
            f"{where}: Δ {rec['delta_patch_apolar_A2']} is inside the {floor} Å² noise floor"
        assert rec["patch_mutant_A2"] < rec["patch_ref_A2"]
    assert d["recommended"], "an empty recommended set needs a verdict change, not a silent pass"
    for hotspot, n in d["recommended_per_hotspot"].items():
        assert n <= 2, f"{hotspot}: {n} recommendations exceeds the declared cap of 2"

    # 5b — the set as ONE sequence, because that is what a freeze is
    if len(d["recommended"]) > 1:
        combo = d["recommended_set_as_one_sequence"]
        assert combo, "more than one recommendation and no combined variant — the singles do not add"
        assert sorted(combo["mutations"]) == sorted(
            f"{r['from']}{r['position']}{r['built_as_for_the_combined_variant']}" for r in d["recommended"])
        assert sorted(combo["positions"]) == sorted(r["position_label"] for r in d["recommended"])
        touched = {r["hotspot"] for r in d["recommended"]}
        for hotspot in touched:
            row = combo["per_hotspot"][hotspot]
            assert row["delta_patch_apolar_A2"] < -floor, f"{hotspot}: combined variant does not reduce the patch"
            assert row["n_recommended_here"] >= 1

    # 6 — the controls
    assert d["controls"]["n_reference_replicates"] >= 3, \
        "fewer than 3 replicates: a two-run noise floor was MEASURED to swing 0.25 ↔ 2.52 Å²"
    assert d["controls"]["patch_sasa_noise_floor_A2"] == max(
        d["controls"]["patch_sasa_spread_over_replicates_A2"].values()), \
        "the floor is not the widest replicate spread it claims to be"
    assert d["controls"]["backbone_frozen_max_CA_drift_A"] == 0.0, \
        "the backbone moved — re-attaching the cofactor coordinates is no longer valid"
    assert abs(d["controls"]["plddt_reproduces_canon_Tyr90"] - d["controls"]["plddt_canon_value_L1_s4"]) < 0.01, \
        "the pLDDT statistic no longer matches the one L1 §4 publishes"

    # 7 — the absences are recorded, with their reasons
    blocked = {nc["site"] for nc in d["no_admissible_candidate"]}
    assert blocked | {r["position"] for r in d["recommended"]}, "neither recommendations nor refusals recorded"
    for nc in d["no_admissible_candidate"]:
        assert nc["candidates_in_radius"] > 0 and nc["exclusion_reasons_present"], \
            f"Gln{nc['site']}: refusal carries no reason"
    assert blocked.issubset(published)

    # 8 — the candidate radius sensitivity is a measurement
    rows = [r for rows in d["candidates"].values() for r in rows]
    assert any(not r["in_primary_radius"] for r in rows), \
        "collection never reached past the primary radius — the 12 Å sensitivity row is a copy"
    widths = {r["candidate_radius_A"] for r in d["candidate_radius_sensitivity"]}
    assert widths == {8.0, 10.0, 12.0}


def test_chem11_site_conservation():
    """Script 70 (CHEM.11): is position 401 conserved? — the hold that gated `I401S` in the ORDERED gene.

    The headline percentages are pinned doc↔cache by `test_doc_cache_sync`; what is pinned HERE is
    the integrity of the argument, i.e. the four things without which those percentages mean
    nothing:
      1. the counts are internally consistent — every distribution sums to its own `n`, `identical`
         really is the query residue's count, and the anchored subset is a SUBSET. A frequency whose
         denominator drifted from its numerator would read exactly like biology;
      2. the POSITIVE CONTROL discriminates: the catalytic His537 must read far above the position
         under test. This is the instrument's licence — if an invariant catalytic residue ever
         reads as variable as a surface loop, the verdict it produced is void, not merely noisy.
         ⛔ Deliberately a RELATION (control ≫ focus), never a corpus threshold: a pin on «98.8 %»
         would red when a new homolog joins the pool, which is the corpus improving;
      3. the gap-penalty sweep really varies the alignment (it is the one knob that decides an
         indel-rich column) AND the finding survives it in DIRECTION: Ser stays the majority
         alternative at 401 under every setting;
      4. the INDEPENDENT legs are present and are not silently empty — an external MSA reading of
         the same column, our reading of the SAME accessions beside it, the disagreement split by
         KIND (a gap in the external alignment is not a disagreement about a residue), and the one
         external pairwise alignment that agrees residue-for-residue.
    """
    path = CHEMISTRY / "chem11_site_conservation.json"
    if not path.exists():
        pytest.skip("chem11_site_conservation.json not computed")
    d = json.loads(path.read_text(encoding="utf-8"))
    focus = str(d["focus_position"])

    # 1 — the counts have to be arithmetic before they can be evidence
    kept = d["selection"]["dedup"]["kept"]
    assert d["selection"]["quality_filter"]["passed"] >= kept > 0
    assert d["selection"]["dedup"]["genera"] == len(d["selection"]["dedup"]["genera_list"])
    for pos, block in d["positions"].items():
        qr = block["query_residue"]
        assert d["query"]["residues_at_positions"][pos] == qr
        assert d["query"]["numbering_controls"][pos] == qr, f"pos {pos}: control residue ≠ query residue"
        for scope in ("deduped", "anchored", "all_quality_filtered"):
            row = block[scope]
            assert sum(row["distribution"].values()) == row["n"], f"pos {pos}/{scope}: distribution ≠ n"
            assert row["identical"] == row["distribution"].get(qr, 0), f"pos {pos}/{scope}: identical ≠ count of {qr}"
            assert row["ser"] == row["distribution"].get("S", 0)
        assert block["deduped"]["n"] == kept
        assert block["anchored"]["n"] <= block["deduped"]["n"], f"pos {pos}: anchored subset is larger than the set"

    # 2 — the control's licence, as a relation
    control_pos = str(d["controls"]["positive_control_positions"][0])
    control = d["positions"][control_pos]
    assert control["role"] == "catalytic_control"
    assert control["deduped"]["identical_pct"] > 5.0 * d["positions"][focus]["deduped"]["identical_pct"], (
        "the catalytic control no longer reads as far more conserved than the position under test — "
        "the instrument stopped discriminating, so its verdict is void"
    )
    assert control["anchored"]["ser"] == 0, "Ser appears at the catalytic His — read the alignment, not the percentage"
    assert d["controls"]["self_alignment"]["pid_pct"] == 100.0
    assert d["controls"]["self_alignment"]["positions_recovered"] is True

    # 3 — the sweep varies something, and the direction survives it
    sweep = d["gap_penalty_robustness"]
    assert len({(r["gap_open"], r["gap_extend"]) for r in sweep}) == len(sweep) >= 3
    assert len({r["anchored_n"] for r in sweep}) > 1, "the gap penalties change nothing — the sweep proves nothing"
    for row in sweep:
        assert row["ser_pct"] > row["identical_pct"], (
            f"at gap ({row['gap_open']}, {row['gap_extend']}) the query residue is no longer the minority — "
            "the finding does not survive its own robustness sweep"
        )

    # 4 — the independent legs, and the disagreement split by kind
    ext = d["external_msa"]
    assert ext["n"] > 0 and ext["sequences_in_alignment"] > ext["n"]      # the query is excluded from the counts
    kinds = ext["disagreement_kinds"]
    ours = ext["our_reading_on_the_same_accessions"]
    assert sum(kinds.values()) == ours["n"], "the disagreement kinds do not partition the shared accessions"
    placed = ours["n"] - kinds.get("msa_gap_vs_our_residue", 0)
    assert abs(ext["per_sequence_agreement_where_msa_places_a_residue_pct"]
               - 100.0 * kinds.get("same", 0) / placed) < 0.06, \
        "the conditional agreement is not derived from the kinds it claims to exclude"
    assert ext["gap_pct"] > 0, "a gap-free external column would make the indel caveat a fabrication"
    assert d["external_pairwise"], "the external pairwise leg is empty — the only non-our-aligner residue read is gone"
    for pw in d["external_pairwise"]:
        assert pw[f"residue_at_query_{focus}"] == pw["our_reading"] and pw["agrees"] is True, (
            f"{pw['target_acc']}: the external pairwise alignment disagrees with ours at {focus} — "
            "that is a finding about the aligner, not a test to relax"
        )


# ── Constants consistency ──

def test_constants_importable():
    """Verify shared constants module can be imported."""
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import (
        BASELINE_DELTA_T_S,
        F_CONST,
        GAFF_VERSION,
        HARTREE_TO_EV,
        J_MAX_25C,
        J_MAX_25C_SD,
        KM_GLUCOSE,
        R_GAS,
    )
    assert GAFF_VERSION == "gaff-2.11"
    assert abs(F_CONST - 96485.33) < 1
    assert abs(R_GAS - 8.314) < 0.01
    assert abs(HARTREE_TO_EV - 27.211) < 0.01
    assert BASELINE_DELTA_T_S == 60
    assert KM_GLUCOSE == 13.9
    assert abs(J_MAX_25C - 881e-6) < 1e-6
    # ⛔ These two are NOT independent literals, so do not pin them as such: the asymptote is DERIVED
    # through K_M from the same Zafar 2012 Table-1 row (dgrGcGDH, 520 ± 20 µA/cm² at 20 mM). Pinning
    # the RELATION reds when one is moved without re-deriving the other (00_07 HW.5.IS).
    j_from_km = 520e-6 * (KM_GLUCOSE + 20.0) / 20.0
    assert abs(J_MAX_25C - j_from_km) < 1e-6, (J_MAX_25C, j_from_km)
    # …and its 1σ is propagated from the source's own error bars, not typed:
    sd_propagated = (((KM_GLUCOSE + 20.0) / 20.0 * 20e-6) ** 2 + (520e-6 / 20.0 * 3.1) ** 2) ** 0.5
    assert abs(J_MAX_25C_SD - sd_propagated) < 1e-6, (J_MAX_25C_SD, sd_propagated)


# ── New cache files (scripts 21d, 24, 28) ──

def test_wb97x_cache_complete():
    """ωB97X cache has all 3 species + ΔSCF."""
    path = DFT / "os_complex_wb97xd.json"
    if not path.exists():
        pytest.skip("ωB97X cache missing")
    data = json.loads(path.read_text())
    assert "os2_plus" in data
    assert "os3_plus" in data
    assert "fadh2_red" in data
    assert data["os2_plus"]["converged"] is True
    assert data["os3_plus"]["converged"] is True


def test_b1_dmbpy_wb97x_cache():
    """B1 (OS-RECOMPUTE): dimethyl Os ωB97X — the real device mediator (supersedes plain
    bpy). Both redox states converged; physical Os(III) LUMO + electron affinity."""
    path = DFT / "os_complex_wb97xd_dmbpy.json"
    if not path.exists():
        pytest.skip("B1 dmbpy cache missing")
    d = json.loads(path.read_text())
    assert d["os2_plus"]["converged"] and d["os3_plus"]["converged"]
    assert -2.0 < d["os3_plus"]["LUMO_eV"] < -1.0, "Os(III) dmbpy LUMO out of range"
    assert 3.5 < d["EA_Os3_eV"] < 5.0, "EA_Os3 out of physical range"


def test_b2_adiabatic_dscf_cache():
    """B2 (OS-RECOMPUTE): adiabatic ΔSCF generator — the 1,5-dihydro donor, EA drift-safe
    from B1; vertical exceeds adiabatic (cation geometric relaxation)."""
    path = DFT / "delta_scf_corrections.json"
    if not path.exists():
        pytest.skip("B2 cache missing")
    d = json.loads(path.read_text())
    assert d["geom_opt_converged"]["FADH2"] and d["geom_opt_converged"]["FADH2_cation"]
    # A sanity bound, not a direction: it catches a run that lost a charge or a state (an error of eVs) and
    # CANNOT catch a wrong tautomer — the range written here before had been drawn around the 4a,5-dihydro
    # result and read the corrected one as unphysical (00_07 HW.5.IS, 2026-10-15). The cation relaxation is bounded
    # on its own, since the wider ΔG range alone would pass a fragmenting cation (the script-29 pathology).
    assert -1.5 < d["dG_adiabatic_eV"] < 1.5, "adiabatic ΔG out of physical range"
    assert d["dG_vertical_eV"] > d["dG_adiabatic_eV"], "vertical must exceed adiabatic"
    assert -0.5 < d["relaxation_eV"] < 0, f"cation relaxation {d['relaxation_eV']} eV — a fragmenting cation?"
    # The label 21g writes after checking the SMILES-built INPUT (lib.flavin); the optimised geometries are not
    # stored, so this pins the input's identity, not the geometry's.
    assert d.get("fadh2_tautomer", {}).get("name") == "1,5-dihydrolumiflavin", (
        f"delta_scf_corrections.json fadh2_tautomer={d.get('fadh2_tautomer')!r} — the donor must be the "
        "1,5-dihydro tautomer (in-silico §Critical Rules #16); re-run 21g")
    # 🔴 IDENTITY, not range: `21g --plain` writes the plain-bpy REFERENCE into this SAME path, and the
    # two mediators sit ~0.3 eV apart — inside every range asserted above, so a reference run would pass
    # while two doc↔cache pins quote it as the DEVICE number. The file names itself; nothing read that.
    # (Same shape as the sibling guard on os_complex.json above, and as `converge`'s ladder — a cache whose
    # FILENAME carries no discriminator needs the discriminator pinned from inside, skill picogk #14.)
    assert d.get("mediator", "").startswith("4,4'-dimethyl"), (
        f"delta_scf_corrections.json mediator={d.get('mediator')!r} — expected the dimethyl device "
        "mediator; a `21g --plain` reference run overwrote it, re-run 21g without --plain")


def test_b4_speciation_dmbpy_bracket():
    """B4 (OS-RECOMPUTE): ωB97X dimethyl speciation — 3 forms converged, and BOTH +2/+3
    forms (aqua, bis-Im) are better acceptors than chloro = the functional-robust bracket.
    The internal aqua↔bis-Im order is deliberately NOT asserted — it is functional-sensitive
    (≤0.15 eV; ωB97X aqua>bis-Im, B3LYP-dimethyl bis-Im>aqua)."""
    path = DFT / "wb97x_speciation_dmbpy.json"
    if not path.exists():
        pytest.skip("B4 cache missing")
    d = json.loads(path.read_text())
    forms = {f["name"]: f for f in d["forms"]}
    assert set(forms) == {"chloro", "aqua", "bisim"}
    assert all(f["converged"] for f in d["forms"])
    assert forms["aqua"]["shift_vs_chloro_eV"] < 0, "aqua should sit above chloro"
    assert forms["bisim"]["shift_vs_chloro_eV"] < 0, "bis-Im should sit above chloro"


def test_tunneling_pathway():
    """Script 28 found a route (cache sanity only). ⛔ Not a feasibility check: script 28 is a contact-graph search,
    not a Beratan–Onuchic pathway, and the paper reports no pathway (self-review round 1, cluster 6, 2026-10-15)."""
    path = DFT / "tunneling_pathway.json"
    if not path.exists():
        pytest.skip("tunneling pathway not computed")
    data = json.loads(path.read_text())
    assert data["path_atoms"] > 0   # the withdrawn «β·d < 5» feasibility bound is no longer asserted (cluster 6)


def test_zif_hopping_all_pairs():
    """ZIF hopping should have Cu-Co + Co-Ce at minimum."""
    path = DFT / "zif_hopping.json"
    if not path.exists():
        pytest.skip("hopping not computed")
    data = json.loads(path.read_text())
    assert len(data["pairs"]) >= 2
    assert "k_total_per_s" in data          # ③ rework renamed total → k_total_per_s
    assert data["k_total_per_s"] > 1e6


def test_zif_bridge_span_is_linker_invariant():
    """The premise under the FIXED `ZIF_NODE_DIST` in script 23.

    Swapping a linker is only allowed to leave the metal···metal distance alone while
    the bridge N···N span does. CHEM.35's canon caveat — "a bigger ligand pushes the
    metals apart" — is a claim about exactly this number, and here it is measured
    rather than assumed: a ring FUSED at the back grows the ligand footprint without
    touching the N–C–N bridge.

    CAN catch: a library entry whose bridge genuinely lengthens, which would make the
    fixed node distance an unstated assumption for it (script 23 then refuses the run).
    CANNOT catch a change in the M–N–C angles or in the framework topology — both also
    move M···M, and neither is modelled, because `ZIF_NODE_DIST` is an input rather than
    a solved geometry.
    """
    path = DFT / "zif_bridge_geometry.json"
    if not path.exists():
        pytest.skip("bridge geometry not built")
    data = json.loads(path.read_text())
    spans = data["bridge_span_nn_A"]
    ref_key = data["reference_linker"]
    ref, tol = spans[ref_key], data["span_tolerance_A"]
    assert set(spans) >= {"meim", "bzim"}, "library must carry both the shipped and the lever linker"
    for linker, span in spans.items():
        assert abs(span - ref) <= tol, (
            f"{linker} bridge span {span} Å vs reference {ref_key} {ref} Å exceeds {tol} Å — "
            "the fixed ZIF_NODE_DIST is no longer justified for it"
        )


def test_md_dft_ensemble_thermally_robust():
    """FAD frontier orbital must be stable across MD snapshots (σ < 0.3 eV)."""
    path = DFT / "md_dft_ensemble.json"
    if not path.exists():
        pytest.skip("ensemble not computed")
    data = json.loads(path.read_text())
    ens = data["ensemble"]
    assert len(data["frames"]) >= 3
    assert ens["HOMO_std_eV"] < 0.3
    assert ens["thermally_robust"] is True
    assert -7.0 < ens["HOMO_mean_eV"] < -4.0  # physical flavin HOMO range


def test_pcet_redox_potential_valid():
    """Proton-reference PCET must land within 100 mV of every free-flavin reading carried (pH 7) — −220 mV
    alone since 2026-10-02 (00_07 HW.5.IS); a pass on a kinder, unsourced reading would not be a pass."""
    path = DFT / "pcet_redox_potential.json"
    if not path.exists():
        pytest.skip("PCET not computed")
    data = json.loads(path.read_text())
    assert data["valid_proton_reference"] is True
    assert len(data["delta_vs_exp_pH7_mV"]) == len(data["exp_free_flavin_pH7_mV"]) == 1
    assert max(abs(d) for d in data["delta_vs_exp_pH7_mV"]) < 100
    assert data["couple"].startswith("FAD")


def test_os_couple_thermo_is_its_states():
    """96 (2026-10-18): the Os(III/II) couple of the adiabatic chloro form from its two states' energies and Hessians.
    CAN catch: a level whose ΔG_red is not the difference of its two states' terms, a potential shift that is not that
    difference's change (the SHE cancels), an imaginary mode kept without a class or classed against the gate the cache
    records (≤ tolerance → tolerated; methyl share ≥ the minimum within the cap → torsion; anything else → skeletal, which
    must be zero), and an RRHO level called comparable while the two states' soft-mode censuses differ. CANNOT catch:
    whether the harmonic RRHO describes a floppy complex, nor the Os side of any other form (96 corrects one)."""
    path = DFT / "os_couple_thermo.json"
    if not path.exists():
        pytest.skip("os_couple_thermo.json not computed")
    d = json.loads(path.read_text())
    s2, s3, ha_ev = d["species"]["os2"], d["species"]["os3"], 27.211386245988
    terms = {"electronic": lambda s: s["E_Ha"], "plus_zpe": lambda s: s["E_Ha"] + s["ZPE_Ha"],
             "rrho_free_energy": lambda s: s["G_tot_Ha"]}
    for lvl, f in terms.items():
        assert abs(d["dG_red_eV"][lvl] - (f(s2) - f(s3)) * ha_ev) < 1e-6, lvl
        shift = -1000 * (d["dG_red_eV"][lvl] - d["dG_red_eV"]["electronic"])
        assert abs(d["shift_vs_electronic_mV"][lvl] - shift) <= 0.1, lvl
        assert abs(1000 * (d["E_os_vs_SHE_V"][lvl] - d["E_os_vs_SHE_V"]["electronic"]) - shift) <= 0.15, lvl
    g = d["gate"]
    assert len(s2["real_cm"]) + len(s2["imaginary"]) == len(s3["real_cm"]) + len(s3["imaginary"]), "a mode lost from a record"
    for name, s in d["species"].items():
        # the ZPE is the real modes' alone (½·h·c·Σν, 1 cm⁻¹ = 4.556335e-6 Ha): a dropped mode must not be in it
        assert abs(s["ZPE_Ha"] - 0.5 * 4.556335e-6 * sum(s["real_cm"])) < 1e-6, f"{name}: ZPE is not the real modes' sum"
        # the delegated rule by its own words — share ≥ min AND |ν| ≤ cap is a torsion, whatever the tolerance booking
        assert all(m["methyl_weight"] >= g["methyl_weight_min"] or abs(m["cm"]) <= g["imag_tolerance_cm"]
                   for m in s["imaginary"]), f"{name}: an imaginary mode that is neither methyl nor under the tolerance"
        tol = [m for m in s["imaginary"] if abs(m["cm"]) <= g["imag_tolerance_cm"]]
        tors = [m for m in s["imaginary"] if m not in tol and m["methyl_weight"] >= g["methyl_weight_min"]
                and abs(m["cm"]) <= g["methyl_imag_max_cm"]]
        assert (s["n_imag_tolerated"], s["n_methyl_torsion_imag"]) == (len(tol), len(tors)), name
        assert s["n_skeletal_beyond_tolerance"] == len(s["imaginary"]) - len(tol) - len(tors) == 0, name
        assert s["n_real_below_soft"] == sum(1 for c in s["real_cm"] if c < g["soft_cm"]), name
        assert d["rrho_census"][name] == {"dropped_imaginary": len(s["imaginary"]), "real_below_50_cm": s["n_real_below_soft"]}
    assert d["rrho_comparable"] == (d["rrho_census"]["os2"] == d["rrho_census"]["os3"])
    assert abs(d["control_dE_red_vs_21e_meV"]) < 1.0, "96's electronic couple no longer reproduces 21e's"


def test_cascade_like_for_like_is_its_inputs():
    """95 is a pure function of six caches (32 · 32b · 21f · 34 · 21e relaxed ×2): every form's E°(Os) and its cascade
    at each of 32b's donor levels must be what those caches give TODAY, and each gap must be its two sides. CAN catch: an
    upstream re-run (a new Os form, a recomputed flavin at any level) that left 95's cache stale · a sign flip in the
    side split · 32b's MMFF level drifting from 32's protocol. CANNOT catch: whether the like-for-like reading itself is
    right, nor that the ZPE and RRHO levels correct one side only — that is the script's docstring and the paper's §3.5."""
    path = DFT / "cascade_like_for_like.json"
    if not path.exists():
        pytest.skip("95 not run")
    d = json.loads(path.read_text())
    pcet = json.loads((DFT / "pcet_redox_potential.json").read_text())
    steps = json.loads((DFT / "pcet_redox_potential_thermo.json").read_text())["E_vs_SHE_mV"]
    she, meas = pcet["SHE_abs_V"], pcet["exp_free_flavin_pH7_mV"][0] / 1000
    assert abs(steps["mmff_electronic"]["pH_7.0"] - pcet["E_vs_SHE_mV"]["pH_7.0"]) <= 0.1 + 1e-9, \
        "32b's MMFF level is not 32's potential — the two flavin caches describe different protocols"
    e_fad = {k: v["pH_7.0"] / 1000 for k, v in steps.items()}
    assert list(d["flavin"]["levels"]) == list(e_fad), "95 reads other donor levels than 32b holds — re-run 95"
    for k, lv in d["flavin"]["levels"].items():
        assert lv["E_pH7_computed_V"] == round(e_fad[k], 4), f"95 stands on another E°(FAD) at {k} than 32b's — re-run 95"
        assert abs(lv["donor_side_V"] - (e_fad[k] - meas)) < 6e-5, k
    micro = {r["name"]: r["dE_red_eV"] for r in json.loads((DFT / "microsolvation_dmbpy.json").read_text())["results"]}
    src = {"chloro (device, programmatic)": json.loads((DFT / "os_complex.json").read_text())["dE_red_III_to_II_eV"],
           **{f"chloro + {k} H₂O on Cl⁻": micro[f"mediator_k{k}_clwaters"] for k in (1, 2, 3)},
           "chloro, Os(II) relaxed, Os(III) vertical":
               json.loads((DFT / "os_mediator_series_relaxed_os2.json").read_text())["complexes"]["dmbpy"]["dE_red_eV"],
           "chloro, both states relaxed (adiabatic)":
               json.loads((DFT / "os_mediator_series_relaxed_os3.json").read_text())["complexes"]["dmbpy"]["dE_red_adiabatic_eV"],
           "aqua (methodological reference)": micro["aqua_meim_h2o"], "bis-imidazole (brush-presented, hypothetical)": micro["bisim_meim2"]}
    assert [r["form"] for r in d["forms"]] == list(src), "95's forms are not the forms its inputs hold — re-run 95"
    for r in d["forms"]:
        assert r["dE_red_III_to_II_eV"] == src[r["form"]], f"{r['form']}: 95 holds a stale ΔE_red — re-run 95"
        assert abs(r["E_os_vs_SHE_V"] - (-src[r["form"]] - she)) < 6e-5, r["form"]
        assert list(r["by_donor_level"]) == list(e_fad), r["form"]
        for k, c in r["by_donor_level"].items():
            assert abs(c["cascade_V"] - (r["E_os_vs_SHE_V"] - e_fad[k])) < 1e-4, (r["form"], k)
            assert abs(c["gap_to_measured_same_couples_V"] - (r["acceptor_side_V"] + c["donor_side_V"])) < 2e-4, (r["form"], k)
            assert c["direction"] == ("downhill" if c["cascade_V"] > 0 else "uphill"), (r["form"], k)
    # the both-sided row: computed from 96 exactly when 96's cache exists (the 7th input), never invented without it
    bs, os96 = d["both_sided"], DFT / "os_couple_thermo.json"
    assert bs["computed"] == os96.exists(), "95's both-sided row disagrees with whether 96 has run — re-run 95"
    if bs["computed"]:
        th = json.loads(os96.read_text())
        pairs = {"relaxed_electronic": "electronic", "relaxed_plus_zpe": "plus_zpe", "relaxed_rrho_free_energy": "rrho_free_energy"}
        for k, os_k in pairs.items():
            lv = bs["levels"][k]
            if os_k == "rrho_free_energy" and not th["rrho_comparable"]:
                assert "skipped" in lv and "cascade_V" not in lv, "an RRHO row 96 marks not comparable entered 95"
                continue
            assert abs(lv["cascade_V"] - (-th["dG_red_eV"][os_k] - she - e_fad[k])) < 1e-4, k
    # every agreement by cancellation is NAMED: recomputed from the rows at the cache's own thresholds, none dropped
    can = d["cancellations"]
    hit = lambda gap, dn, ac: abs(gap) <= can["gap_max_V"] and min(abs(dn), abs(ac)) >= can["each_side_min_V"]  # noqa: E731
    want = {(r["form"], k) for r in d["forms"] for k, c in r["by_donor_level"].items()
            if hit(c["gap_to_measured_same_couples_V"], c["donor_side_V"], r["acceptor_side_V"])}
    want |= {(bs["form"] + " (96 both-sided)", k) for k, v in bs.get("levels", {}).items()
             if "cascade_V" in v and hit(v["gap_to_measured_same_couples_V"], v["donor_side_V"], v["acceptor_side_V"])}
    assert {(c["form"], c["level"]) for c in can["rows"]} == want, "95 names other cancellations than its rows hold — re-run 95"
    assert all(c["form"] in d["verdict"] for c in can["rows"]), "a cancellation is in the record but not in the verdict"


def test_pcet_cascade_converged():
    """PCET cascade run must have both SCFs converged (result itself is a
    documented does-not-flip negative; we guard convergence + plausible cost)."""
    path = DFT / "pcet_cascade.json"
    if not path.exists():
        pytest.skip("PCET cascade not computed")
    data = json.loads(path.read_text())
    assert data["converged"]["FADH2"] is True
    assert data["converged"]["FADH_radical"] is True
    assert 4.0 < data["pcet_oxidation_cost_eV"] < 7.0  # physical oxidation cost range


# 33's FADH₂ repeats 32b's reduced flavin (same builder, protocol and escape), so the two minima must coincide. Measured
# −3.9e-6 Ha (33 ran 2026-10-19 04:23 → 11:26) — 3.9× geomeTRIC's per-step energy criterion (1e-6 Ha), the scale at which
# two optimisations onto ONE point agree; 1e-5 Ha (0.27 meV) leaves room for that and lies far under the planar saddle
# either run met first (4.3e-3 Ha: 117.6 meV over 33's minimum, 117.5 over 32b's). It does NOT separate a second minimum lying closer than 0.27 meV.
FADH2_MINIMUM_VS_32B_TOL_HA = 1e-5


def test_flavin_chain_stands_on_minima():
    """The step-2 flavin chain (21g · 33 · 29b), re-run 2026-10-18/19 through lib `relax_checked` after the planar RDKit/MMFF
    start had been found to converge to a saddle (00_07 HW.5.IS): every species it optimises is a minimum by its own
    Hessian, its escapes went DOWN, and 33's FADH₂ lands on 32b's minimum.
    CAN catch: a cache written from a geometry nobody classified (a re-run without `relax_checked`, or the pre-2026-10-18
    caches, which had no `minimum_check`) · a species whose last attempt was still a saddle · a saddle record at or below
    its minimum, or a later saddle above an earlier one (an escape that climbed) · a doublet whose Hessian SCF lost or
    contaminated its <S²> · 33's FADH₂ more than 1e-5 Ha off 32b's minimum.
    CANNOT catch: a minimum that is not the lowest one (another conformer), nor a second minimum within 1e-5 Ha of 32b's ·
    that 21g's def2-SVP minimum is the same fold as 32b's 6-31G(d) one — these caches keep no minimum geometry (lib records
    it from the next run; the fold, 21.1°, was read from a checkpoint under `cache/runs/32b/` — committed since 2026-10-23 — against 32b's cached 24.3°) · the DFT grid
    response the Hessian omits (32b CANNOT 4)."""
    from lib.constants import S2_MAX_DOUBLET
    chain = {"delta_scf_corrections.json": {"FADH2": False, "FADH2_cation": True},
             "pcet_cascade.json": {"FADH2": False, "FADH_radical": True},
             "semiquinone_lambda.json": {"FADH_radical": True, "FADH_anion": False}}   # species → is a doublet
    for name, species in chain.items():
        d = json.loads((DFT / name).read_text())
        for sp, doublet in species.items():
            what = f"{name} {sp}"
            assert d["geom_opt"][sp]["converged"] is True and d["geom_opt"][sp]["minimum"] is True, f"{what}: not a converged minimum"
            mc = d["minimum_check"][sp]
            assert mc["harmonic"]["n_imag_beyond_tolerance"] == 0, f"{what}: the cached point has a mode beyond the tolerance"
            heights = mc["saddle_above_minimum_meV"]
            assert len(heights) == len(mc["saddles"]), f"{what}: a saddle without its height, or the reverse"
            assert all(h > 0 for h in heights), f"{what}: a saddle at or below its minimum — the escape did not go down"
            assert heights == sorted(heights, reverse=True), f"{what}: a later saddle above an earlier one {heights}"
            if doublet:
                assert mc["harmonic"]["s2"] <= S2_MAX_DOUBLET, f"{what}: <S²> {mc['harmonic']['s2']:.3f} — contaminated"
    control = json.loads((DFT / "pcet_cascade.json").read_text())["control_FADH2_minimum_vs_32b_Ha"]
    assert abs(control) <= FADH2_MINIMUM_VS_32B_TOL_HA, f"33's FADH₂ lies {control:+.2e} Ha from 32b's minimum"


def test_no_cache_records_a_machine_path():
    """A cache points at its side files (Hessians under `cache/runs/`, whose `.npy`/`.xyz` are committed and whose logs are not) relative to the repo root, never by
    this machine's absolute path (lib `repo_relative`). Two committed caches — 32b's and 96's — carried the home
    directory into the paper-SI bundle until 2026-10-19, and the three chain caches would have on their first commit.
    CAN catch: in any COMMITTED cache JSON, a POSIX path under a machine root (/Users · /home · /private · /tmp · /var ·
    /opt · /Volumes · /mnt · /root) or a Windows drive path, anywhere in a string. CANNOT catch: a path under another root,
    or a relative path that resolves nowhere — the side files are not in the tree by design."""
    import subprocess
    pattern = re.compile(r'(?<![\w.])/(?:Users|home|private|tmp|var|opt|Volumes|mnt|root)/|\b[A-Za-z]:[\\/]{1,2}[\w.-]')
    listed = subprocess.run(["git", "-C", str(REPO), "ls-files", "-z", "--", "tools/in_silico/cache/*.json",
                             "tools/in_silico/cache/**/*.json"], capture_output=True, check=True).stdout.decode().split("\0")
    hits = [f for f in listed if f and pattern.search((REPO / f).read_text(encoding="utf-8"))]
    assert listed and not hits, f"caches recording a machine path: {hits}"


def test_xylem_sap_sweep_results():
    """Xylem sap sweep should cover 6 species."""
    path = KINETICS / "xylem_sap_sweep.json"
    if not path.exists():
        pytest.skip("xylem sap sweep not computed")
    data = json.loads(path.read_text())
    assert len(data.get("sweep", data)) >= 6


def test_temperature_sweep_all_stable():
    """All 4 temperatures (-10 to +40°C) must be RMSD-stable (≪ 3 Å)."""
    path = KINETICS / "temperature_sweep.json"
    if not path.exists():
        pytest.skip("temperature sweep not computed")
    data = json.loads(path.read_text())
    sweep = data.get("sweep", [])
    assert len(sweep) >= 4
    for r in sweep:
        assert r["rmsd_mean_A"] < 3.0
        assert r["stable"] is True


def test_psbma_diffusion_results():
    """PSBMA diffusion should have D_eff."""
    path = KINETICS / "psbma_diffusion.json"
    if not path.exists():
        pytest.skip("PSBMA diffusion not computed")
    data = json.loads(path.read_text())
    assert "D_eff_cm2_s" in data
    assert data["D_eff_cm2_s"] > 0


# ── Constants vs documentation consistency ──

def test_constants_match_kinetics_output():
    """Verify constants.py values are used in kinetics output.

    ⚠️ Says what it CAN and CANNOT catch (in-silico §When Modifying #8). CATCHES: a constant
    edited in `lib/constants.py` while the committed cache still carries the value the script
    computed from the OLD one — i.e. an edit without the re-run its consumers need. Does NOT
    catch a value that is arithmetically right but bound to the WRONG REFERENT (`HW.45`), and
    does NOT judge the canon: doc↔cache is `test_doc_cache_sync`'s axis, a different pin.
    """
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import BASELINE_DELTA_T_S, E_CYCLE, ETA_BQ, J_MAX_25C, KM_GLUCOSE, P_SLEEP_VSTOR

    data = json.loads((KINETICS / "delta_t_lookup.json").read_text())
    assert data["parameters"]["j_max_25C_uA_cm2"] == J_MAX_25C * 1e6
    assert data["parameters"]["Km_mM"] == KM_GLUCOSE
    assert data["parameters"]["BASELINE_DELTA_T_S"] == BASELINE_DELTA_T_S
    # η_boost feeds `p_net = p_ebfc * ETA_BQ`, so every delta_t in this cache is downstream of it.
    # The field sat in the same `parameters` block as the three above and was the only one unpinned
    # (00_07 DOC-T.117, measured by mutation 2026-09-21: the edit was green across the whole suite).
    assert data["parameters"]["eta_BQ"] == ETA_BQ
    # The cycle cost divides every delta_t and the sleep drain is subtracted from every p_net — and
    # E_cycle_mJ sat in that same block unpinned after DOC-T.117 (00_07 E.63, found 2026-09-27).
    assert data["parameters"]["E_cycle_mJ"] == E_CYCLE * 1e3
    assert data["parameters"]["P_sleep_VSTOR_uW"] == P_SLEEP_VSTOR * 1e6
    # 30b samples its own band from the SAME constants; until its cache carried them, a re-run of 30
    # without 30b — or an edit of the bracket — stayed green (adversarial review, 2026-09-27).
    from lib.constants import E_CYCLE_HIGH, E_CYCLE_LOW
    mc = json.loads((KINETICS / "monte_carlo.json").read_text())["parameters"]
    assert mc["E_cycle_low_mJ"] == E_CYCLE_LOW * 1e3
    assert mc["E_cycle_high_mJ"] == E_CYCLE_HIGH * 1e3
    assert mc["P_sleep_VSTOR_uW"] == P_SLEEP_VSTOR * 1e6


def test_constants_match_mechanical_output():
    """Pin the mechanical caches to the constants their scripts were run from.

    Same axis as `test_constants_match_kinetics_output` and the same declared limits. Born of the
    2026-09-21 mutation measurement (00_07 DOC-T.117): each of these constants reaches a committed
    cache field and each cache is densely pinned to canon by `test_doc_cache_sync` — yet editing the
    constant reddened NOTHING, because a doc↔cache pin cannot see a cache that was never re-run.

    ⛔ `D_BUS_ROD_MM` is deliberately ABSENT and must stay absent: pinning the frozen anchor geometry
    mirrored in this file was MEASURED and REFUSED (⚖️ founder 2026-09-09, `HW.45`, `00_06 §2`) —
    both live discrepancies of that class carried a TRUE canon number under a foreign referent, so
    every form of the pin is green on them. Adding it here rebuilds what was declined.
    """
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import (
        SLM_MIN_WALL_DEFAULT_MM,
        SWAY_F0_HZ_HIGH_READING,
        SWAY_F0_HZ_LOW_READING,
    )

    # The two named readings are a BRACKET, and both ends carry the cycle budget (in-silico
    # §When Modifying #11) — pinning one end would turn a bracket into a point in disguise.
    wind = json.loads((MECHANICAL / "wind_duty_cycle.json").read_text())
    assert tuple(wind["sway_frequency"]["low_reading_hz"]) == tuple(SWAY_F0_HZ_LOW_READING)
    assert wind["sway_frequency"]["high_reading_hz"] == SWAY_F0_HZ_HIGH_READING

    # One constant, TWO units in two caches: `52` writes it in mm, `66` writes it ×1000 in µm.
    # That split is exactly what this pin is for — a unit drifting on one side only.
    z_stack = json.loads((MECHANICAL / "z_stack_tolerance.json").read_text())
    assert z_stack["collar_radial_budget"]["printability_floor_mm"] == SLM_MIN_WALL_DEFAULT_MM
    ligament = json.loads((MECHANICAL / "gyroid_ligament.json").read_text())
    for topology in ("sheet", "network"):
        assert ligament["floor_inversion"][topology]["slm_default"]["floor_um"] == (
            SLM_MIN_WALL_DEFAULT_MM * 1000.0
        ), topology


def test_delta_t_aux_power_cache_on_ratified_window():
    """Pin script 63's cache to the EDLC window it must be computed from (00_07 HW.37 → HW.42).

    Born of a ratified derate that never reached the model: `VBAT_OV` went to 4.822 V on 2026-09-09
    while 63 kept dividing a typed 3.87 J built on the part's 5.5 V rating — green across the suite,
    because nothing tied that literal to `VBAT_OV`. The window is now DERIVED in `lib/constants.py`.
    CATCHES: (a) a C / VBAT_OV / VBAT_OK / η_buck edit without re-running 63 (the cached window and
    every absolute delta_t still carry the old one); (b) an absolute delta_t that is not the VSTOR
    window over P·η — e.g. the post-buck window back in the charging role, where η_buck does not
    act; (c) a percentage shift that stops being its window-FREE closed form — HW.42's verdict rests
    on the shift not depending on the window. Does NOT catch: canon stating a different window
    (`test_doc_cache_sync`, the `02_03 §8` rows), nor which floor — VBAT_OK ON or OFF — canon should use.
    """
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import (
        C_EDLC_F,
        EDLC_WINDOW_USABLE_J,
        EDLC_WINDOW_VSTOR_J,
        ETA_BUCK_ACTIVE,
        VBAT_OK_ON_V,
        VBAT_OV_RATIFIED_V,
    )

    data = json.loads((KINETICS / "delta_t_aux_power_sensitivity.json").read_text())
    const = data["constants"]
    assert const["C_EDLC_F"] == C_EDLC_F
    assert const["VBAT_OV_V"] == VBAT_OV_RATIFIED_V
    assert const["VBAT_OK_ON_V"] == VBAT_OK_ON_V
    assert const["eta_buck_active"] == ETA_BUCK_ACTIVE
    assert const["E_window_vstor_J"] == EDLC_WINDOW_VSTOR_J
    assert const["E_window_usable_J"] == EDLC_WINDOW_USABLE_J

    e_j = const["E_window_vstor_J"]
    for name, season in data["seasons"].items():
        p_gen_w, eta = season["P_gen_uW"] * 1e-6, season["eta_boost"]
        assert season["delta_t_baseline_s"] == pytest.approx(e_j / (p_gen_w * eta), abs=0.006), name
        for row in season["sweep"]:
            p_aux_uw = row["P_aux_uW"]
            assert row["delta_t_A_s"] == pytest.approx(e_j / ((p_gen_w + p_aux_uw * 1e-6) * eta), abs=0.006)
            assert row["pct_shift_A"] == pytest.approx(
                p_aux_uw / (season["P_gen_uW"] + p_aux_uw) * 100.0, abs=0.0051), (name, p_aux_uw)
            assert row["pct_shift_B"] == pytest.approx(
                p_aux_uw / (season["P_gen_uW"] * eta + p_aux_uw) * 100.0, abs=0.0051), (name, p_aux_uw)


def test_dft_os_redox_pair_ordering():
    """Os(II) HOMO should be higher than Os(III) HOMO (reduced is less bound)."""
    path = DFT / "os_complex.json"
    if not path.exists():
        pytest.skip("os_complex.json missing")
    data = json.loads(path.read_text())
    os2_homo = data["os2_plus"]["HOMO_eV"]
    os3_homo = data["os3_plus"]["HOMO_eV"]
    assert os2_homo > os3_homo, f"Os(II) HOMO {os2_homo} should be > Os(III) HOMO {os3_homo}"


def test_xylem_sap_profiles():
    """Verify xylem sap configurator has expected profiles."""
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.xylem_sap import SAP_PROFILES, get_sap_profile

    assert len(SAP_PROFILES) >= 6
    pine = get_sap_profile("pinus_sylvestris")
    assert 4.0 <= pine["ph"] <= 6.0
    assert pine["glucose_mM"] > 0
    spruce = get_sap_profile("picea_abies")
    # ⛔ Pins the profile TABLE's internal ordering, not biology: every pH here is an assumption (00_07 HW.3).
    assert spruce["ph"] < pine["ph"], "profile table ordering changed (spruce profile vs pine profile pH)"


def test_shared_lib_modules():
    """Verify all shared lib modules importable."""
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import REPO_ROOT

    # навмисний import-smoke: тест падає на ImportError, якщо lib/ не експортує символ
    from lib.geometry import place_on_sphere, positions_to_nm_array, restraint_protein_heavy_atoms  # noqa: F401
    from lib.utils import banner, pick_platform, ps_to_steps  # noqa: F401
    from lib.xylem_sap import SAP_PROFILES
    assert REPO_ROOT.exists()
    assert len(SAP_PROFILES) >= 6


# ── Script existence ──

EXPECTED_SCRIPTS = [
    "01_smoke_test_water_box.py",
    "02_parameterize_fad.py",
    "03_parameterize_genipin.py",
    "04_parameterize_chitosan.py",
    "05_parameterize_cnc.py",
    "06_parameterize_ppy.py",
    "07_parameterize_pvi.py",
    "08_parameterize_sbma.py",
    "10_genipin_stability_md.py",
    "11_full_matrix_md.py",
    "12_temperature_sweep_md.py",
    "13_psbma_diffusion_md.py",
    "20_dft_lumiflavin.py",
    "21_dft_os_bipy_complex.py",
    "21b_dft_os_bpy_full.py",
    "21c_dft_os_bpy_geomopt.py",
    "22_compare_homo_lumo.py",
    "23_build_zif_clusters.py",
    "24_dft_hopping_integrals.py",
    "30_kinetics_delta_t.py",
    "30b_kinetics_monte_carlo.py",
    "31_eis_impedance_model.py",
    "40_validate_vs_experiment.py",
    "14_xylem_sap_sweep_md.py",
    "21d_dft_os_bpy_wb97xd.py",
    "27_md_dft_ensemble.py",
    "28_electron_tunneling_pathway.py",
    "29_dft_reorganization_energy.py",
    "32_pcet_redox_potential.py",
    # The anchor-mechanics block and its successors. A curated list, not the roster (`ls scripts/`
    # is): it guards against a listed script vanishing, and says nothing about unlisted ones.
    "50_thermal_stress_lame.py",
    "51_gusak_degradation_model.py",
    "52_z_stack_tolerance.py",
    "53_oxide_det_per_alloy.py",
    "54_anchor_thermal_bridge.py",
    "55_bus_mechanical.py",
    "56_unified_press_fit_lame.py",
    "57_gdl_breakthrough.py",
    "58_thermal_install_field.py",
    "59_contact_endurance_check.py",
    "60_paper_figures.py",
    "61_paper_tables.py",
    "62_wind_duty_cycle.py",
    "63_delta_t_aux_power_sensitivity.py",
    "64_teg_across_peek_break.py",
    "65_zif_radiosensitization.py",
    "66_gyroid_ligament_thickness.py",
    "67_sap_recipe_saturation.py",
    "68_bus_contact_equilibrium.py",
    "69_chem11_aggregation_compensation.py",
    "71_capsule_thermal_envelope.py",
    "74_site_rain_dew.py",
    "85_electrode_interfacial_ph.py",
    "91_liner_exit_contact.py",
    "92_liner_mouth_contact.py",
    "93_malate_metal_chelation.py",
]


@pytest.mark.parametrize("script", EXPECTED_SCRIPTS)
def test_script_exists(script):
    path = REPO / "tools/in_silico/scripts" / script
    assert path.exists(), f"Missing script: {script}"
    assert path.stat().st_size > 500, f"Script too small: {script}"


def test_anchor_torque_path_invariants():
    """77 (HW.26): invariants that hold whatever the inputs move to.

    CAN catch: a sign flip in the thermal term (the floor would grip at +40 °C instead of opening a gap); a
    capacity that stops being μ·P_c·2π·a²·ℓ (the PEEK cap and the friction would part); a threshold that stops
    rising with μ and with the band; the summer extreme not costing capacity at the band top.
    CANNOT catch: whether the wind torsion is large — no measured value is read by 77 — nor whether μ is right
    (an unmeasured bracket); those are its declared ceilings.
    """
    d = json.loads((MECHANICAL / "anchor_torque_path.json").read_text(encoding="utf-8"))
    v, rows = d["verdict"], d["grid"]
    assert v["wind_path_exists"] is True
    assert v["capacity_zero_at_band_floor_at_summer_extreme"] is True
    hot_floor = [r for r in rows if r["temperature_C"] == 40.0 and r["band_edge"] == "band floor"]
    assert hot_floor and all(r["P_c_relaxed_MPa"] == 0.0 and r["tau_s_star_MPa"] == 0.0 for r in hot_floor)
    for r in rows:
        assert abs(r["peek_bore_shear_cap_MPa"] - r["mu"] * r["P_c_relaxed_MPa"]) < 1e-3
    def tau(t, edge, mu, ins):
        return next(r["tau_s_star_MPa"] for r in rows if (r["temperature_C"], r["band_edge"], r["mu"],
                                                          r["insertion_mm"]) == (t, edge, mu, ins))
    mus = sorted({r["mu"] for r in rows})
    ins = sorted({r["insertion_mm"] for r in rows})
    for t, edge, l_s in itertools.product((20.0, 40.0), ("band top",), ins):
        assert tau(t, edge, mus[0], l_s) < tau(t, edge, mus[-1], l_s)
    for mu, l_s in itertools.product(mus, ins):
        assert tau(20.0, "band floor", mu, l_s) < tau(20.0, "band top", mu, l_s)
        assert tau(40.0, "band top", mu, l_s) < tau(20.0, "band top", mu, l_s)


def test_anchor_torque_path_wind_bracket_invariants():
    """77 Q2 (HW.26): the wind bracket at its CAP, re-derived from its own fields and lib, never typed.

    CAN catch: a broken link of the chain γ = τ_cap/G_LT → Δθ = ½·γ·Δx/R → slip = Δθ·a_s → hex threshold
    c* = Δθ·s/(2√3) → preload-free band Δθ/(√3·Δα) (mutation: Δθ ×10 in wind_bracket() reds on the Δθ identity); the
    sleeve decay length λ = √(G_PEEK·J/4πG_LT·a²) and the rigid-part ceiling it carries (λ ≪ the sleeve length); the
    bark-end peak factor (l2 + l1/2)/Δx and every figure it scales; the rigid-demand flag disagreeing with the grid's
    τ_s*; the hex at the WRITTEN MAXIMUM clearance of 01_01 §4.3 C engaging even at the bark-end peak (mutation:
    C_HEX_MAX_RADIAL_CLEARANCE_M 0.05e-3 → 0.002e-3 reds on «c* < clearance»); the thermal swing no longer exceeding
    the peak threshold; the strain factors the verdict quotes as its margins.
    CANNOT catch: whether the Wood Handbook values are right for P. sylvestris (US pines, species means), whether the
    12 % G_LT/E_L ratio holds for green wood, how much the compliant parts lower the demand (only that they do), how
    compliant the gyroid really is (the factor is carried at its rigid limit), or how large τ_s is under ordinary
    wind — the declared ceilings.
    """
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, ALPHA_PEEK_1K, E_PEEK_PA, NU_PEEK, R_INTERFACE_M
    d = json.loads((MECHANICAL / "anchor_torque_path.json").read_text(encoding="utf-8"))
    g, w, rows = d["geometry"], d["wind_bracket"], d["grid"]
    d_alpha = ALPHA_PEEK_1K - ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    s_hex = w["hex_across_flats_mm"] * 1e-3
    assert abs(s_hex - 2.0 * g["shank_radius_m"] * math.cos(math.radians(30.0))) < 1e-6
    for sp in w["species"]:
        gamma = sp["tau_cap_MPa"] / sp["G_LT_green_est_MPa"]
        assert abs(sp["surface_shear_strain_at_cap"] - gamma) < 1e-5
        dtheta = 0.5 * gamma * g["centroid_separation_m"] / g["stem_radius_m"]
        assert abs(sp["rotation_gyroid_vs_sleeve_rad"] - dtheta) < 1e-6
        assert abs(sp["slip_at_shank_surface_um"] - dtheta * g["shank_radius_m"] * 1e6) < 0.02
        assert abs(sp["hex_engages_below_radial_clearance_um"] - dtheta * s_hex / (2.0 * math.sqrt(3.0)) * 1e6) < 0.02
        assert abs(sp["engagement_band_without_preload_K"] - dtheta / (math.sqrt(3.0) * d_alpha)) < 0.1
        a2 = g["sleeve_outer_radius_m"]
        j = 0.5 * math.pi * (a2 ** 4 - R_INTERFACE_M ** 4)
        lam = math.sqrt(E_PEEK_PA / (2.0 * (1.0 + NU_PEEK)) * j / (4.0 * math.pi * sp["G_LT_green_est_MPa"] * 1e6 * a2 ** 2))
        assert abs(sp["sleeve_torsional_decay_length_mm"] - lam * 1e3) < 0.02
        assert lam < 0.2 * g["sleeve_length_m"]      # the rigid-part ceiling is real: the sleeve follows its local wood
    tau_star_max = max(r["tau_s_star_MPa"] for r in rows)
    assert w["rigid_part_demand_at_cap_exceeds_every_tau_s_star"] is (tau_star_max < w["tau_cap_MPa_range"][0])
    l1, l2, dx = g["gyroid_length_m"], g["sleeve_length_m"], g["centroid_separation_m"]
    pk = w["bark_end_peak_factor"]
    assert abs(pk["rigid_gyroid"] - (l2 + l1 / 2.0) / dx) < 1e-3 and abs(pk["compliant_gyroid"] - l2 / dx) < 1e-3
    assert pk["compliant_gyroid"] < pk["rigid_gyroid"]
    for peak_key, centroid_key, tol in (("slip_at_bark_end_um_range", "slip_at_shank_surface_um_range", 0.05),
                                        ("hex_engages_below_radial_clearance_um_bark_end_range",
                                         "hex_engages_below_radial_clearance_um_range", 0.05),
                                        ("engagement_band_without_preload_K_bark_end_range",
                                         "engagement_band_without_preload_K_range", 0.5)):
        for k in (0, 1):
            assert abs(w[peak_key][k] - w[centroid_key][k] * pk["rigid_gyroid"]) < tol
    c_peak = w["hex_engages_below_radial_clearance_um_bark_end_range"][1]
    band_peak = w["engagement_band_without_preload_K_bark_end_range"][1]
    span = w["thermal_range_C"][1] - w["thermal_range_C"][0]
    assert c_peak < w["c_hex_max_radial_clearance_um"]      # the decisive half of ground (2): the written hex never engages
    assert w["hex_clearance_thermal_swing_um"] > c_peak
    assert band_peak < span
    assert abs(w["strain_factor_to_engage_written_hex_at_bark_end"] - w["c_hex_max_radial_clearance_um"] / c_peak) < 0.02
    assert abs(w["strain_factor_to_fill_forest_span_at_bark_end"] - span / band_peak) < 0.02
    assert w["ordinary_wind"]["tau_s_MPa"] is None


def test_flange_cambium_heat_invariants():
    """78 (HW.6): orderings the physics fixes whatever the inputs move to.

    CAN catch: a broken scheme (its own closed-form check, recorded in the cache); thinner bark not running hotter;
    a darker finish not running hotter; sun not beating shade; the flange-driven column running colder than bark
    without it under a crown (the capsule is never below air); the cambium exceeding the surface that drives it;
    a dead-bark floor outside the bracket's thin end.
    CANNOT catch: whether 50 °C is the right gate (58's isotherm), nor sunlit bark or frost — the declared ceilings.
    """
    d = json.loads((THERMAL / "flange_cambium_heat.json").read_text(encoding="utf-8"))
    v, runs, ref = d["verdict"], d["runs"], d["reference_no_flange_surface_at_air"]
    assert d["scheme_check_rel_error"] < 0.01
    cell = {(r["case"], r["alpha"], r["wind_k"], r["bark_side"]): r["cambium_max_C"] for r in runs}
    alphas, winds = d["inputs"]["alphas"], d["inputs"]["wind_k"]
    for case, k in itertools.product(d["inputs"]["cases"], winds):
        for a in alphas:
            assert cell[(case, a, k, "thin")] > cell[(case, a, k, "thick")]
            assert cell[("sunlit", a, k, "thin")] >= cell[("shaded", a, k, "thin")]
        for side in ("thin", "thick"):
            row = [cell[(case, a, k, side)] for a in alphas]
            assert row == sorted(row)
            assert cell[("shaded", alphas[0], k, side)] >= ref[side]["cambium_max_C"]
    assert all(r["cambium_max_C"] <= r["flange_max_C"] for r in runs)
    floor = v["dead_bark_floor_mm_at_specified_alpha"]
    assert floor is None or 0.0 <= floor <= d["bark"]["thin_mm"]
    a_star = v["alpha_crossing_sunlit_still_air"]
    assert a_star["thin"] is None or a_star["thick"] is None or a_star["thin"] <= a_star["thick"]


def test_flange_cambium_frost_invariants():
    """79 (HW.6, the frost half): areas, sky, gates and the declared directions re-derived from the cache and the CEMs.

    CAN catch: a fin ratio not equal to its areas over the ring (mutation: the band dropped from the tied fin reds on
    the tied ratio); a ring or band not read from the flange and sleeve CEMs, or a capsule area that has drifted from
    71's cache; the Brutsaert units turned; any of the three scheme gates past its threshold; a regime summary that is
    not the min/max of its own runs; a verdict text whose sign words disagree with the medians it quotes; the
    directions the docstring declares — overcast colder under the flange than clear, diffuse sun colder than none, the
    median monotone along the coupling axis, the store and trunk sensitivities raising the tied tail, and equal h_c
    turning the clear-sky tied median colder — failing in any cell.
    CANNOT catch: whether ε, F, α_bark or the trunk correlation are right for this site, real cloud cover, beam sun,
    the real radome↔flange coupling, snow, or any frost-injury threshold — the declared ceilings.
    """
    d = json.loads((THERMAL / "flange_cambium_frost.json").read_text(encoding="utf-8"))
    ar, runs, reg, v = d["areas"], d["runs"], d["regimes"], d["verdict"]
    fl = json.loads((REPO / "tools/cad/cem/cathode_flange.json").read_text(encoding="utf-8"))
    sl = json.loads((REPO / "tools/cad/cem/zone2_sleeve.json").read_text(encoding="utf-8"))
    d_fl, wound = fl["flange_diameter_mm"], sl["bore_diameter_mm"] + 2.0 * sl["wall_thickness_mm"]
    ring = math.pi / 4.0 * (d_fl ** 2 - wound ** 2)
    band = math.pi * d_fl * fl["flange_thickness_mm"]
    a_exp = json.loads((THERMAL / "capsule_envelope.json").read_text(encoding="utf-8"))["geometry"]["a_exp_mm2"]
    assert abs(ar["contact_ring_mm2"] - ring) < 0.01 and abs(ar["flange_band_mm2"] - band) < 0.01
    assert abs(ar["capsule_exposed_mm2"] - a_exp) < 0.01
    assert abs(ar["fin_ratio"]["decoupled"] - band / ring) < 1e-3
    assert abs(ar["fin_ratio"]["tied"] - (band + a_exp) / ring) < 1e-3
    unit = d["inputs"]["brutsaert"]["unit_check"]
    assert 0.6 < unit["emissivity_at_10hPa_283K"] < 0.9 and unit["same_with_e_in_Pa"] > 1.0
    assert d["scheme_check_rel_error"] < 0.02 and d["diurnal_check_cambium_min_error_K"] < 0.05
    assert d["timestep_check"]["daily_min_err_K"] <= 0.15 and d["timestep_check"]["shift_err_K"] <= 0.05
    cell = {(r["regime"], r["coupling"], r["wind_k"], r["bark_side"]): r["shift_K"] for r in runs}
    regimes = [x["name"] for x in d["inputs"]["regimes"]]
    for name in regimes:
        for cp in ("decoupled", "tied"):
            med = [s["median"] for (rg, c, _, _), s in cell.items() if rg == name and c == cp]
            assert reg[name][cp]["median_K_range"] == [min(med), max(med)]
            assert reg[name][cp]["max_K"] == max(s["max"] for (rg, c, _, _), s in cell.items() if rg == name and c == cp)
    for (rg, cp, k, side), s in cell.items():
        assert s["min"] <= s["median"] <= s["p95"] <= s["max"]
        if cp == "tied":
            assert s["median"] >= cell[(rg, "decoupled", k, side)]["median"]          # monotone along the coupling axis
            sky, sun = rg.split("_", 1)
            if sky == "clear":
                assert cell[(f"overcast_{sun}", cp, k, side)]["median"] > s["median"]   # cloud: colder under the flange
            if sun == "no_sun":
                assert cell[(f"{sky}_diffuse_sun", cp, k, side)]["median"] > s["median"]  # sun: colder under the flange
    for name in regimes:
        lo, hi = reg[name]["tied"]["median_K_range"]
        assert v["tied_median_K_range_by_regime"][name] == [lo, hi]
        assert f"{lo:+.1f}…{hi:+.1f} K" in v["text"]
    base = cell[("clear_no_sun", "tied", 0.0, "thin")]
    sens = d["sensitivity_thin_bark_still_air_clear_no_sun"]
    for name in ("sapwood_190mm", "trunk_height_0.3m"):
        assert sens[name]["tied"]["max"] > base["max"]                 # the docstring's declared direction
    assert sens["capsule_h_c_as_bark"]["tied"]["median"] > base["median"]   # the mechanism: h_c, not area
    mech = d["mechanism"]
    assert mech["bark"]["equilibrium_minus_air_K"] < mech["capsule"]["equilibrium_minus_air_K"] < 0.0
    assert mech["capsule"]["h_c_W_m2K"] > mech["bark"]["h_c_W_m2K"]


def test_flange_cambium_frost_real_cloud_sits_between_the_ends():
    """79's real-cloud block (2026-10-12): ERA5 cover mixes the clear and overcast ends through two long-wave forms.

    CAN catch: a cloud form that leaves the bracket of the two sky ends it mixes (per cell: clear ≤ B82 ≤ linear ≤
    overcast medians, at both sun ends — B82 at C 0.22 stays below the linear mix for every clear-sky emissivity the
    winter carries, 0.62–0.76); a colder-share that is not a share or disagrees with the sign of its median; a month
    split that loses frost days or months; a summary not the min/max of its own runs; a verdict that stopped quoting
    the shares. CANNOT catch: which form holds at the site, or whether ERA5 total cover is the right cloud measure
    for either — the declared role substitution.
    """
    d = json.loads((THERMAL / "flange_cambium_frost.json").read_text(encoding="utf-8"))
    rc, base = d["real_cloud"], {(r["regime"], r["coupling"], r["wind_k"], r["bark_side"]): r for r in d["runs"]}
    cl = {(r["regime"], r["coupling"], r["wind_k"], r["bark_side"]): r for r in rc["runs"]}
    assert 0.0 <= rc["climate"]["winter_share_below_0.2"] <= 1.0 and 0.0 <= rc["climate"]["winter_share_above_0.8"] <= 1.0
    for (rg, cp, k, side), r in cl.items():
        sun = "no_sun" if rg.endswith("no_sun") else "diffuse_sun"
        meds = [base[(f"clear_{sun}", cp, k, side)]["shift_K"]["median"], cl[(f"cloud_b82_{sun}", cp, k, side)]["shift_K"]["median"],
                cl[(f"cloud_linear_{sun}", cp, k, side)]["shift_K"]["median"], base[(f"overcast_{sun}", cp, k, side)]["shift_K"]["median"]]
        assert meds == sorted(meds), ((rg, cp, k, side), meds)
        assert 0.0 <= r["colder_share"] <= 1.0
        assert 0.0 <= r["warmer_share"] <= 1.0 - r["colder_share"] + 1e-9, r
        if r["shift_K"]["median"] > 0.1:     # the dead band (COLDER_BAND_K) separates the share from the median's sign
            assert r["colder_share"] > 0.5, r
        if r["shift_K"]["median"] < -0.1:
            assert r["warmer_share"] > 0.5, r
        assert sum(m["frost_days"] for m in r["by_month"].values()) == r["shift_K"]["frost_days"]
        assert set(r["by_month"]) <= {str(m) for m in range(1, 13)}
    for name, by_cp in rc["regimes"].items():
        for cp, s in by_cp.items():
            rows = [r for (rg, c, _, _), r in cl.items() if rg == name and c == cp]
            assert s["median_K_range"] == [min(r["shift_K"]["median"] for r in rows), max(r["shift_K"]["median"] for r in rows)]
            assert s["colder_share_range"] == [min(r["colder_share"] for r in rows), max(r["colder_share"] for r in rows)]
            if cp == "tied":
                lo, hi = s["colder_share_range"]
                assert f"{lo:.0%}–{hi:.0%}" in d["verdict"]["text"], name


def test_flange_cambium_frost_beam_by_azimuth():
    """79's beam block (2026-10-14): open-field ERA5 DNI on a trunk face swept over the face's azimuth.

    CAN catch: the sun off the data's clock (at the declared convention no DNI energy may fall in hours the sun never
    clears the horizon, and every ½- or 1-hour shift must hold some — mutation: the UTC offset's sign flipped moves
    sunrise DNI into the dark and reds here); a solar series off the obliquity, the equation-of-time extremes or the
    June noon; silhouette coefficients not re-derivable from the flange CEM and 71's capsule geometry; the beam
    timestep check past its gates on either window, or a warm window in which no flange hour crosses DEHARDEN_C (its
    hour gate would be vacuous); a north face that does not reproduce the diffuse-only cell it rides on (the winter
    beam barely reaches it); the declared directions failing in any cell — the shift and the bark's hours above
    DEHARDEN_C not rising from north through east and west to south, a winter total with the flange spot above it
    more often than the bark beside it, the coldest hour under the flange not warmer on the south face than on the
    north; a south-minus-north floor or a list of month exceptions that is not re-derivable from the runs; a month
    split that loses hours; a summary not the min/max of its runs; a verdict that stopped quoting the north and south
    medians and the south hours, or that stopped saying the axis does not choose an azimuth by itself; the series
    timestep check past the shift band anywhere in the 30 years.
    CANNOT catch: crown, neighbour or horizon shading (open-field DNI is the upper end of beam), whether ERA5 DNI holds
    at trunk height, the real coupling, or a dose behind the hour counts. Ground-reflected light — the next test.
    """
    d = json.loads((THERMAL / "flange_cambium_frost.json").read_text(encoding="utf-8"))
    bs = d["beam_sun"]
    clock = bs["sun_clock_check_dni_share_in_sun_down_hours"]
    assert clock["+0.0"] == 0.0 and all(v > 1e-4 for k, v in clock.items() if k != "+0.0"), clock
    g = bs["sun_geometry_check"]
    assert all(abs(abs(x) - 23.44) < 0.1 for x in g["declination_deg"])
    assert abs(g["equation_of_time_min"][0] + 14.2) < 0.3 and abs(g["equation_of_time_min"][1] - 16.4) < 0.3
    assert abs(g["june_noon_altitude_deg"] - (90.0 - bs["site"]["lat_deg"] + 23.44)) < 0.1
    fl = json.loads((REPO / "tools/cad/cem/cathode_flange.json").read_text(encoding="utf-8"))
    g71 = json.loads((THERMAL / "capsule_envelope.json").read_text(encoding="utf-8"))["geometry"]
    side_band = fl["flange_diameter_mm"] * fl["flange_thickness_mm"]
    a_tied = math.pi * side_band + g71["a_exp_mm2"]
    proj = bs["silhouette_per_fin_area_cos_sin"]
    assert proj["bark"] == [1.0, 0.0] and proj["decoupled"][0] == 0.0 and abs(proj["decoupled"][1] - 1.0 / math.pi) < 1e-5
    assert abs(proj["tied"][0] - math.pi * g71["dome_diameter_mm"] ** 2 / 4.0 / a_tied) < 1e-4
    assert abs(proj["tied"][1] - (g71["dome_diameter_mm"] * g71["h_over_bark_mm"] + side_band) / a_tied) < 1e-4
    for ts in bs["timestep_check"].values():
        assert ts["daily_min_err_K"] <= 0.15 and ts["shift_err_K"] <= 0.05 and ts["daily_max_err_K"] <= 0.2
        for c, ref in ts["hours_above_deharden_reference"].items():
            assert abs(ts["hours_above_deharden"][c] - ref) <= max(2, 0.02 * ref), (c, ts)
    warm = bs["timestep_check"]["warmest_winter_hour"]["hours_above_deharden"]
    assert any(v for c, v in warm.items() if not c.endswith("/bark")), warm
    for name, v in bs["timestep_check_series"].items():
        assert v["shift_err_K_max"] <= 0.05 and v["frost_day_pairs"] > 0, (name, v)
    cell ={(r["form"], r["azimuth_deg"], r["coupling"], r["wind_k"], r["bark_side"]): r for r in bs["runs"]}
    diffuse = {(r["regime"], r["coupling"], r["wind_k"], r["bark_side"]): r["shift_K"]["median"] for r in d["real_cloud"]["runs"]}
    for (form, a, cp, k, side), r in cell.items():
        h = r["winter_hours_above_deharden"]
        assert h["flange"] <= h["no_flange"], r
        for key in ("no_flange", "flange"):
            assert sum(m[key] for m in r["winter_hours_above_deharden_by_month"].values()) == h[key]
        if a == 0:
            assert abs(r["shift_K"]["median"] - diffuse[(f"cloud_{form}_diffuse_sun", cp, k, side)]) <= 0.02, r
            run = [cell[(form, az, cp, k, side)] for az in (0, 90, 180)], [cell[(form, az, cp, k, side)] for az in (0, 270, 180)]
            for path in run:
                for key in (lambda x: x["shift_K"]["median"], lambda x: x["winter_hours_above_deharden"]["no_flange"]):
                    vals = [key(x) for x in path]
                    assert vals == sorted(vals), (form, cp, k, side, vals)
    for cp in ("decoupled", "tied"):
        dd = [cell[(f, 180, cp, k, sd)]["cambium_min_C"]["flange"] - cell[(f, 0, cp, k, sd)]["cambium_min_C"]["flange"]
              for (f, a, c, k, sd) in cell if a == 0 and c == cp]
        assert bs["coldest_hour_under_flange_south_minus_north_K"][cp] == [round(min(dd), 2), round(max(dd), 2)]
        assert min(dd) > 0.0, cp          # in absolute terms the beam warms the spot — the declared reading
    exceptions = [(r["form"], r["azimuth_deg"], r["coupling"], r["wind_k"], r["bark_side"], mo)
                  for r in bs["runs"] for mo, v in r["winter_hours_above_deharden_by_month"].items() if v["flange"] > v["no_flange"]]
    assert exceptions == [(x["form"], x["azimuth_deg"], x["coupling"], x["wind_k"], x["bark_side"], x["month"])
                          for x in bs["month_cells_flange_above_bark"]]
    assert "does not choose an azimuth by itself" in d["verdict"]["text"]
    years = bs["years"]
    for a, by_cp in bs["by_azimuth"].items():
        for cp, s in by_cp.items():
            rows = [r for (_, az, c, _, _), r in cell.items() if az == int(a) and c == cp]
            med = [r["shift_K"]["median"] for r in rows]
            assert s["median_K_range"] == [min(med), max(med)]
            hb = [r["winter_hours_above_deharden"]["no_flange"] / years for r in rows]
            assert s["winter_hours_above_deharden_per_year"]["no_flange"] == [round(min(hb), 1), round(max(hb), 1)]
    n, so = bs["by_azimuth"]["0"]["tied"], bs["by_azimuth"]["180"]["tied"]
    for s, face in ((n, "north face"), (so, "south one")):
        assert f"{s['median_K_range'][0]:+.1f}…{s['median_K_range'][1]:+.1f} K on a {face}" in d["verdict"]["text"]
    hs = so["winter_hours_above_deharden_per_year"]
    assert f"on a south face {hs['no_flange'][0]:.0f}–{hs['no_flange'][1]:.0f} hours a winter" in d["verdict"]["text"]


def test_flange_cambium_frost_ground_reflected():
    """79's ground-reflected light (2026-10-17, revised 2026-10-18): ρ·GHI through the ground's view share, open field, two
    ends of snow × albedo.

    CAN catch: a snow check whose κ is not its own agreement and shares (κ re-derived), a reanalysis below the κ gate, a
    «never snow» agreement that is not 1 − the station's share; ends whose albedo is not the one read in Baker et al. 1990 /
    Baker & Ruschy 1988 or whose snow source is not the declared reanalysis; a high end not above the low one in reflected
    light; the declared directions failing in any cell — more reflected light making the bark's or the flange spot's
    winter hours above DEHARDEN_C FEWER, or the coldest hour under the flange COLDER (none ≤ low ≤ high, cell by cell; a
    sign error on the new term reds here); runs that are not the same cells as the records without it; a summary not
    the min/max of its runs, a south-minus-north floor or an azimuth reading not re-derivable from them — the declared
    range reading, its margin, and the cell-wise ratio added after the data; an end whose reanalysis is not the least
    (low) or most (high) snowy at its depth; cell checks (low ≤ high per cell; hours rising over the records without it)
    not re-derivable; a whole-series timestep gate missing a set or past its own tolerances; a verdict that stopped
    quoting the two ends' size, that claims the declared azimuth readings hold when they do not, or that drops the
    cell-wise ratio or the declared reading's margin without reflected light.
    CANNOT catch: whether either reanalysis holds at the cell, whether St. Paul's albedo holds on a forest floor or under a
    crown, or the real coupling — the declared ceilings.
    """
    d = json.loads((THERMAL / "flange_cambium_frost.json").read_text(encoding="utf-8"))
    bs, gr = d["beam_sun"], d["beam_sun"]["ground_reflected"]
    chk = gr["snow_check"]
    for z, row in chk["depths_m"].items():
        ss = row["station_snow_share"]
        assert abs(row["never_snow_agreement"] - (1.0 - ss)) <= 0.0015, (z, row)
        for name in gr["snow_sources"]:
            r = row[name]
            pe = r["snow_share"] * ss + (1.0 - r["snow_share"]) * (1.0 - ss)
            assert abs(r["kappa"] - (r["agreement"] - pe) / (1.0 - pe)) <= 0.01, (z, name, r)
            assert r["kappa"] >= 0.4, (z, name, r)
    ends = gr["ends"]
    assert (ends["low"]["snow_source"], ends["low"]["snow_depth_m_at_least"], ends["low"]["albedo_snow"],
            ends["low"]["albedo_ground"]) == ("era5_land", 0.11, 0.5, 0.18)
    assert (ends["high"]["snow_source"], ends["high"]["snow_depth_m_at_least"], ends["high"]["albedo_snow"],
            ends["high"]["albedo_ground"]) == ("era5_land", 0.01, 0.8, 0.24)
    share = gr["end_source_check_winter_daylight_snow_share"]
    for e, pick in (("low", min), ("high", max)):
        z = ends[e]["snow_depth_m_at_least"]
        assert share[f"{ends[e]['snow_source']}/{z:g}"] == pick(share[f"{s}/{z:g}"] for s in gr["snow_sources"]), (e, share)
        assert abs(share[f"{ends[e]['snow_source']}/{z:g}"] - ends[e]["winter_daylight_hours_with_snow_share"]) <= 0.0015, e
        assert f"{z:g}" in chk["depths_m"], (e, z)   # the κ gate ran at the depth the end uses
    assert 0.0 < ends["low"]["reflected_on_vertical_over_model_diffuse"] < ends["high"]["reflected_on_vertical_over_model_diffuse"]
    key = lambda r: (r["form"], r["azimuth_deg"], r["coupling"], r["wind_k"], r["bark_side"])  # noqa: E731
    none = {key(r): r for r in bs["runs"]}
    by_end = {e: {key(r): r for r in gr["runs"] if r["reflect"] == e} for e in ("low", "high")}
    assert set(by_end["low"]) == set(none) == set(by_end["high"])
    for k, r0 in none.items():
        r1, r2 = by_end["low"][k], by_end["high"][k]
        for side in ("no_flange", "flange"):
            assert (r0["winter_hours_above_deharden"][side] <= r1["winter_hours_above_deharden"][side]
                    <= r2["winter_hours_above_deharden"][side]), (k, side)
        assert r0["cambium_min_C"]["flange"] <= r1["cambium_min_C"]["flange"] <= r2["cambium_min_C"]["flange"], k
    years = bs["years"]
    for e, cells in by_end.items():
        for a, by_cp in gr["by_azimuth"][e].items():
            for cp, s in by_cp.items():
                rows = [r for (_, az, c, _, _), r in cells.items() if az == int(a) and c == cp]
                assert s["median_K_range"] == [min(r["shift_K"]["median"] for r in rows), max(r["shift_K"]["median"] for r in rows)]
                hb = [r["winter_hours_above_deharden"]["no_flange"] / years for r in rows]
                assert s["winter_hours_above_deharden_per_year"]["no_flange"] == [round(min(hb), 1), round(max(hb), 1)]
        for cp in ("decoupled", "tied"):
            dd = [cells[(f, 180, cp, k, sd)]["cambium_min_C"]["flange"] - cells[(f, 0, cp, k, sd)]["cambium_min_C"]["flange"]
                  for (f, a, c, k, sd) in cells if a == 0 and c == cp]
            assert gr["coldest_hour_under_flange_south_minus_north_K"][e][cp] == [round(min(dd), 2), round(max(dd), 2)]
        fl = "winter_hours_above_deharden_per_year"
        by = gr["by_azimuth"][e]
        assert gr["readings"][e]["floor_south_warmer_every_cell"] == (gr["coldest_hour_under_flange_south_minus_north_K"][e]["tied"][0] > 0)
        assert gr["readings"][e]["deharden_fewer_north_than_south_under_tied_flange"] == (
            by["0"]["tied"][fl]["flange"][1] < by["180"]["tied"][fl]["flange"][0])
    cw = "deharden_south_over_north_under_tied_flange_min_cellwise_added_after_data"
    for e, cells in (("none", none), *by_end.items()):
        by = bs["by_azimuth"] if e == "none" else gr["by_azimuth"][e]
        rd = gr["readings"][e]
        assert rd["deharden_range_margin_south_min_minus_north_max_per_year"] == round(
            by["180"]["tied"][fl]["flange"][0] - by["0"]["tied"][fl]["flange"][1], 1), e
        pairs = [(cells[(f, 180, "tied", k, sd)]["winter_hours_above_deharden"]["flange"], r["winter_hours_above_deharden"]["flange"])
                 for (f, a, c, k, sd), r in cells.items() if a == 0 and c == "tied"]
        assert rd[cw] == round(min(s / n for s, n in pairs if n > 0), 3), e
        assert rd["cells_with_no_north_hours"] == sum(1 for _, n in pairs if n == 0), e
    cc = gr["cell_checks"]
    q = {"hours_above_deharden_flange": lambda r: r["winter_hours_above_deharden"]["flange"],
         "hours_above_deharden_bark": lambda r: r["winter_hours_above_deharden"]["no_flange"],
         "coldest_hour_flange": lambda r: r["cambium_min_C"]["flange"], "median_shift": lambda r: r["shift_K"]["median"]}
    assert cc["monotone_low_to_high_every_cell"] == {
        n: all(f(by_end["low"][k]) <= f(by_end["high"][k]) + 1e-9 for k in none) for n, f in q.items()}
    assert all(cc["monotone_low_to_high_every_cell"].values()), cc   # 01_04 §3.1 says each of the four moves one way in every cell
    assert cc["hours_above_deharden_rise_over_no_reflection_every_cell"] == {
        e: all(by_end[e][k]["winter_hours_above_deharden"][s] >= none[k]["winter_hours_above_deharden"][s]
               for k in none for s in ("no_flange", "flange")) for e in by_end}
    series = bs["timestep_check_series"]
    assert set(series) == {"beam_high_linear", "beam_high_b82", "diffuse_b82"}, set(series)
    for name, v in series.items():
        assert v["shift_err_K_max"] <= 0.05 and v["floor_err_K_max"] <= 0.15 and v["hours_within_tolerance"], (name, v)
    text = d["verdict"]["text"]
    lo, hi = ends["low"]["reflected_on_vertical_over_model_diffuse"], ends["high"]["reflected_on_vertical_over_model_diffuse"]
    assert f"adds {lo:.2f}–{hi:.2f}× the model's diffuse term" in text
    declared = ("floor_south_warmer_every_cell", "deharden_fewer_north_than_south_under_tied_flange")
    hold = all(r[k] for r in gr["readings"].values() for k in declared)
    assert ("both declared readings of the azimuth axis hold at both ends" in text) == hold
    ratio = math.floor(min(gr["readings"][e][cw] for e in by_end) * 100 + 1e-9) / 100
    assert f"the south has at least {ratio:.2f}× the north's hours under the tied flange at either end" in text
    assert (f"without reflected light the declared reading held by "
            f"{gr['readings']['none']['deharden_range_margin_south_min_minus_north_max_per_year']:.1f} h a winter") in text


def test_capsule_cold_edge_sky_invariants():
    """81 (HW.37, the cold edge 71 leaves open): controls, physical signs and every verdict clause re-derived.

    CAN catch: an air count that is not `71`'s (another file or another clock); a geometry drifted from `71`'s; the
    reference hour off `79`'s cached depression; overcast with no sun not EQUAL to the air in every field and wind
    (mutation: dropping the exact-root branch of `solve` tips the record's hours that sit on the floor below it and
    reds here); the declared directions failing in any cell — a clear sky colder and longer below the floor than
    overcast, no sun than diffuse sun, more wind pulling the sky-cooled capsule up and the sun-warmed one down (these
    four signs also FIX which runs the edges are); edges that are not the extremes of their own runs; a verdict whose
    numbers or edge words are not those edges.
    CANNOT catch: whether ε, F, α or the cylinder correlations are right for a short tilted capsule, real cloud cover,
    the capsule's heat capacity, the bark's heat through the flange, or ERA5's smoothing of station minima — the
    declared ceilings.
    """
    d = json.loads((THERMAL / "capsule_cold_edge_sky.json").read_text(encoding="utf-8"))
    runs, air, e, v = d["runs"], d["air"], d["edges"], d["verdict"]
    c71 = json.loads((THERMAL / "capsule_envelope.json").read_text(encoding="utf-8"))
    cold71 = c71["cold_hours_below_edlc_floor"]
    assert (air["hours_below_floor"], air["days_below_floor"], air["coldest_c"]) == (
        cold71["hours"], cold71["days"], cold71["coldest_air_c"])
    assert d["inputs"]["geometry"] == c71["geometry"]
    mech79 = json.loads((THERMAL / "flange_cambium_frost.json").read_text(encoding="utf-8"))["mechanism"]
    ctl = d["controls"]["mechanism_vs_79"]
    assert ctl["depression_in_79_K"] == mech79["capsule"]["equilibrium_minus_air_K"]
    assert abs(ctl["depression_here_K"] - ctl["depression_in_79_K"]) <= 0.01
    assert set(runs) == {"clear_no_sun", "overcast_no_sun", "clear_diffuse_sun", "overcast_diffuse_sun"}
    winds = [f"k={k}" for k in d["inputs"]["wind_k"]]
    for k in winds:
        assert {f: runs["overcast_no_sun"][k][f] for f in air} == air      # 71's lump without gain IS the air
        for sun in ("no_sun", "diffuse_sun"):
            clear, over = runs[f"clear_{sun}"][k], runs[f"overcast_{sun}"][k]
            assert clear["hours_below_floor"] >= over["hours_below_floor"] and clear["coldest_c"] <= over["coldest_c"]
        for sky in ("clear", "overcast"):
            dark, lit = runs[f"{sky}_no_sun"][k], runs[f"{sky}_diffuse_sun"][k]
            assert dark["hours_below_floor"] >= lit["hours_below_floor"] and dark["coldest_c"] <= lit["coldest_c"]
    cool, warm = runs["clear_no_sun"], runs["overcast_diffuse_sun"]   # always below / always above the air
    for a, b in itertools.pairwise(winds):
        assert cool[a]["hours_below_floor"] >= cool[b]["hours_below_floor"] and cool[a]["coldest_c"] <= cool[b]["coldest_c"]
        assert warm[a]["hours_below_floor"] <= warm[b]["hours_below_floor"] and warm[a]["coldest_c"] >= warm[b]["coldest_c"]
    flat = [(n, k, r) for n, by_k in runs.items() for k, r in by_k.items()]
    for _, _, r in flat:
        assert r["days_below_floor"] <= r["hours_below_floor"] and r["longest_spell_below_floor_h"] <= r["hours_below_floor"]
        assert (r["longest_spell_below_floor_h"] > 0) == (r["hours_below_floor"] > 0)
    hours = [r["hours_below_floor"] for _, _, r in flat]
    for name, pick in (("deep", max(hours)), ("shallow", min(hours))):
        edge = e[name]
        assert edge["hours_below_floor"] == pick
        assert {f: edge[f] for f in air} == runs[edge["regime"]][edge["wind"]]
    assert abs(e["coldest_c"] - min(r["coldest_c"] for _, _, r in flat)) <= 0.005   # edges keep the raw minimum
    assert e["longest_spell_below_floor_h"] == max(r["longest_spell_below_floor_h"] for _, _, r in flat)
    assert e["max_hours_below_capsule_requirement"] == max(r["hours_below_capsule_requirement"] for _, _, r in flat)
    assert e["deep_over_air"] == round(e["deep"]["hours_below_floor"] / air["hours_below_floor"], 2)
    for name in ("shallow", "deep"):
        edge = e[name]
        sky, sun = edge["regime"].split("_", 1)
        assert f"{edge['hours_below_floor']} h on {edge['days_below_floor']} days ({sky} sky every hour, " \
               f"{sun.replace('_', ' ')}, " in v
    assert f"against the air's {air['hours_below_floor']} h on {air['days_below_floor']} days" in v
    assert f"up to ×{e['deep']['hours_below_floor'] / air['hours_below_floor']:.1f}" in v
    assert f"the longest spell below the floor is {e['longest_spell_below_floor_h']} h" in v
    quoted = re.search(r"coldest capsule hour ([−-]?[\d.]+) °C", v)
    assert quoted and abs(float(quoted.group(1).replace("−", "-")) - e["coldest_c"]) <= 0.05
    assert ("no run crosses" in v) == (e["max_hours_below_capsule_requirement"] == 0)
    sky = d["sky_on_cold_days"]
    floor = sky["days_with_air_min_below"][f"{d['inputs']['edlc_floor_c']:.0f}"]
    base, wind = sky["all_winter_days"], sky["u10_median_m_s"]
    assert 0 < floor["daylight_hours"] < base["daylight_hours"] and 0.0 <= floor["sunshine_share"] <= 1.0
    assert f"sunny for {floor['sunshine_share']:.2f} of its hours against {base['sunshine_share']:.2f}" in v
    lean = "leans to the clear end" if floor["sunshine_share"] > base["sunshine_share"] else "does not lean"
    assert f"the site {lean}" in v
    assert f"a median of {wind['hours_air_below_floor']:.1f} m/s against {wind['all_winter_hours']:.1f} m/s" in v


def test_collar_running_clearance_invariants():
    """82 (HW.33 · HW.9 root package): the collar's running clearance re-derived from its inputs and its sibling caches.

    CAN catch: an interface diameter not taken from `73`'s socket band; a thermal member that does not follow from
    the inputs (mutation: entering the interface the other way round — PEEK inside the Ti — flips every sign and reds
    on the hot-edge opening and on the closing at the cold edge); the gradient bound smaller than the isothermal
    closing; ISO 286 grades off the published 18–30 mm values; a route row whose design clearance or ceiling is not
    its own sum or `52`'s chain; the chain at the slot clearance not reproducing `52`'s cached ceiling; a verdict whose
    numbers are not the rows.
    CANNOT catch: whether the routes' grades and roundness are what a vendor holds (ours until they answer), the
    radome PEEK grade's CTE, capillary water in the gap — the declared ceilings.
    """
    d = json.loads((MECHANICAL / "collar_running_clearance.json").read_text(encoding="utf-8"))
    inp, th, v = d["inputs"], d["thermal_closing_mm"], d["verdict"]
    c73 = json.loads((MECHANICAL / "collar_wall_inversion.json").read_text(encoding="utf-8"))
    c52 = json.loads((MECHANICAL / "z_stack_tolerance.json").read_text(encoding="utf-8"))["collar_radial_budget"]
    assert d["interface"]["diameter_mm"] == round(2.0 * c73["geometry"]["band_r_inner_mm"], 3)
    r = d["interface"]["diameter_mm"] / 2.0
    a_p, a_t, t0 = inp["alpha_peek_1K"], inp["alpha_ti_1K"], inp["t_ref_c"]
    t_lo, t_hi = inp["t_min_requirement_c"], inp["t_max_requirement_c"]
    assert abs(th["isothermal_requirement"] - r * (a_p - a_t) * (t0 - t_lo)) < 1e-4
    assert abs(th["isothermal_model_edge"] - r * (a_p - a_t) * (t0 - inp["t_min_model_edge_c"])) < 1e-4
    assert abs(th["gradient_bound_requirement"] - r * a_p * (t0 - t_lo)) < 1e-4
    assert abs(th["hot_edge_requirement"] - r * (a_p - a_t) * (t0 - t_hi)) < 1e-4
    assert th["hot_edge_requirement"] < 0.0 < th["isothermal_model_edge"] < th["isothermal_requirement"]
    assert th["isothermal_requirement"] < th["gradient_bound_requirement"]
    assert abs(d["floor_closing_mm"] - max(th["gradient_bound_requirement"],
                                           th["isothermal_requirement_alpha_sensitivity"])) < 1e-4
    assert d["iso286_grades_18_30_um"] == {"IT5": 9, "IT6": 13, "IT7": 21, "IT8": 33, "IT9": 52, "IT10": 84,
                                           "IT11": 130, "IT12": 210}
    t_floor, design_to = inp["collar_wall_print_floor_mm"], inp["design_to_mm"]
    assert (t_floor, design_to) == (c52["printability_floor_mm"], c52["design_to_mm"])
    want = next(x["ceiling_mm_if_collar_needs_running_clearance"] for x in c52["rows"] if x["collar_wall_mm"] == t_floor)
    assert d["controls"]["chain_equals_52"]["ceiling_mm"] == want
    assert abs(design_to - 2.0 * (t_floor + inp["slot_clearance_mm"]) - want) < 0.006
    prev = 0.0
    for row in d["routes"]:
        tol = (row["it_collar_um"] + row["it_band_um"]) / 2000.0
        base = sum(row["roundness_mm"]) + tol
        assert abs(row["design_clearance_isothermal_mm"] - (th["isothermal_requirement"] + base)) < 6e-4
        assert abs(row["design_clearance_bound_mm"] - (d["floor_closing_mm"] + base)) < 6e-4
        for kind in ("isothermal", "bound"):
            assert abs(row[f"ceiling_{kind}_mm"] - (design_to - 2.0 * (t_floor + row[f"design_clearance_{kind}_mm"]))) < 0.006
        assert row["design_clearance_bound_mm"] > prev       # rows run from the tightest route to the coarsest
        prev = row["design_clearance_bound_mm"]
    lo, hi = d["routes"][0], d["routes"][-1]
    assert f"{th['isothermal_requirement'] * 1e3:.0f} µm" in v and f"{th['gradient_bound_requirement'] * 1e3:.0f} µm" in v
    assert f"{lo['design_clearance_isothermal_mm']:.3f}–{lo['design_clearance_bound_mm']:.3f} mm" in v
    assert f"{hi['design_clearance_isothermal_mm']:.3f}–{hi['design_clearance_bound_mm']:.3f} mm" in v
    assert f"{hi['ceiling_bound_mm']:.2f}–{lo['ceiling_isothermal_mm']:.2f} mm instead of {want:.2f}" in v
    assert ("every row stays below" in v) == all(x["design_clearance_bound_mm"] < inp["slot_clearance_mm"] for x in d["routes"])


def test_cathode_ionic_path_is_derived_from_its_inputs():
    """84 (00_07 HW.53, 2026-10-11): every budget is the 02_03 §1.5 ceiling minus the LOW end of each canon reading of the
    electrodes' own R_int (models 31/31b from their caches · the prose estimate from lib.constants), and every requirement
    is that budget over its element's lenient factor. CAN catch: a hand-edited budget or requirement, a reading that
    drifted from its cache or constant, a control that stopped being recorded. CANNOT catch: whether a geometric factor
    is physically right (the script's own controls) or what the bench measures."""
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import BQ25570_PIN_CS_UW, BQ25570_VIN_CS_MAX_MV, BQ25570_VIN_CS_TYP_MV, R_INT_EBFC_EST_KOHM
    d = json.loads((REPO / "tools/in_silico/cache/kinetics/cathode_ionic_path.json").read_text())
    pred = json.loads((DFT.parent / "kinetics/eis_model.json").read_text())["predictions_for_ti_coin"]
    rs, rct = ([float(x) for x in pred[k].split("-")] for k in ("expected_Rs_range_ohm", "expected_Rct_range_ohm"))
    cat = json.loads((DFT.parent / "kinetics/cathode_det_rct.json").read_text())["grid"]
    rd = d["electrode_r_int_readings"]
    assert rd["anode_31_ranges_ohm"] == {"Rs": rs, "Rct": rct}
    assert rd["models_31_31b_kohm"] == [(rs[0] + rct[0] + min(c["rct_ohm"] for c in cat)) / 1e3,
                                        (rs[1] + rct[1] + max(c["rct_ohm"] for c in cat)) / 1e3]
    assert rd["prose_estimate_02_03_kohm"] == list(R_INT_EBFC_EST_KOHM)
    low = {"models_31_31b": rd["models_31_31b_kohm"][0], "prose_estimate_02_03": rd["prose_estimate_02_03_kohm"][0]}
    vin = {"typ": BQ25570_VIN_CS_TYP_MV, "max": BQ25570_VIN_CS_MAX_MV}
    f = d["factors"]
    for r in d["budgets"]:
        c = (r["V_OC_mV"] - vin[r["VIN_CS"]]) * vin[r["VIN_CS"]] / BQ25570_PIN_CS_UW / 1000.0
        assert r["ceiling_kohm"] == c and r["budget_kohm"] == {k: c - e for k, e in low.items()}, r
        for k, b in r["budget_kohm"].items():
            key = f"{r['V_OC_mV']:.0f}/{r['VIN_CS']} · {k}"
            assert (key in d["requirements_alone_at_lenient_geometry"]) == (b > 0), key
    for req in [*d["requirements_alone_at_lenient_geometry"].values(), d["requirements_per_kohm_of_budget"]]:
        b = req["budget_ohm"]
        assert req["1_sapwood_rho_max_ohm_m"] == b / f["1_sapwood_per_m"]["bracket"][0]
        assert req["2_inner_bark_sheet_max_ohm_sq"] == b / min(f["2_inner_bark_sheet"]["ln_over_2pi"])
        assert req["3_dead_bark_rho_max_ohm_m"] == b / f["3_dead_bark_per_m"]["lenient"]
        assert req["4_film_sheet_max_ohm_sq"] == b / min(f["4_film_per_sq"])
        assert req["5_layer_sheet_x_band_height_max_ohm"] == b / f["5_layer_full_height_per_sq_per_m"]
    assert d["requirements_per_kohm_of_budget"]["budget_ohm"] == 1000.0
    states = f["1_sapwood_per_m"]["states"]
    assert set(states) == {"sap_gap", "ingrown"}
    # ⚖️ HW.26 G1 (2026-10-12): the whole lattice is outside the sleeve, so ONE exposed length × the two depths.
    assert len(d["geometry"]["anode_exposed_length_m"]) == 1 and len(f["1_sapwood_per_m"]["depth_below_cambium_m"]) == 2
    n_corners = 2
    for st in states.values():
        gs = [c["G_per_m"] for c in st["corners"]]
        assert st["bracket"] == [min(gs), max(gs)] and len(gs) == n_corners
    for i, (a, b) in enumerate(zip(states["sap_gap"]["corners"], states["ingrown"]["corners"], strict=True)):
        assert (a["depth_m"], a["length_m"]) == (b["depth_m"], b["length_m"]) and a["G_per_m"] < b["G_per_m"], i   # sap lowers R1
    every = [x for st in states.values() for x in st["bracket"]]
    assert f["1_sapwood_per_m"]["bracket"] == [min(every), max(every)]
    ctl = d["controls"]
    assert abs(ctl["sphere_plane_fv_over_exact"] - 1) <= 0.015 and ctl["sphere_plane_spacing_m"] < 0.25e-3
    assert all(abs(v - 1) <= 0.01 for v in ctl["element_1_coarse_over_fine"].values())
    assert all(v >= 1.0 for v in ctl["element_1_sleeve_over_wood"].values()), "the insulating sleeve lowered G1"
    vp = d["vplus_share_of_layer_1_left_out"]
    assert len(vp) == n_corners and all(row["0mm"] < 1e-9 and list(row.values()) == sorted(row.values()) for row in vp.values())
    assert d["element_5_in_canon"]["electrolyte_path_described"] is False


def test_malate_metal_chelation_invariants():
    """93 (00_07 HW.5.IS → `01_03 §3.5` weakest link, 2026-10-15): the claims the canon ⊕ makes, as invariants.

    CAN catch: an α that is not 1 + Σ of its own terms; a summary range that is not the min/max of its rows; the medium
    drifting from 85's; the Davies step breaking (it is re-checked on NIST's own I = 0 rows); and each ordering the ⊕
    states — Co weakest in every reading · Ce (Buzko) above Cu (NIST) in every reading · Cu (Zabiszak) above Ce
    (Buzko, no β₂) in every reading, i.e. the overlap. CANNOT catch: a constant mis-read from its source (the source
    and row id sit beside each one in the script), the missing temperature correction, or anything about leaching RATE.
    """
    d = json.loads((CHEMISTRY / "malate_metal_chelation.json").read_text(encoding="utf-8"))
    k85 = json.loads((KINETICS / "electrode_interfacial_ph.json").read_text(encoding="utf-8"))
    assert abs(d["medium"]["ionic_strength_selected"] - k85["cathode"]["media"]["buffered_pH4.5"]["ionic_strength_25C"]) < 1e-4
    assert all(abs(c["diff"]) < 0.1 for c in d["davies_check"])
    r = d["readings"]
    for key, v in r.items():
        for tag, row in v["rows"].items():
            assert row["alpha"] >= 1.0 and math.isclose(row["alpha"], 1.0 + sum(x["contribution"] for x in row["terms"]),
                                                         rel_tol=1e-12), (key, tag)
    for m, b in d["by_metal"].items():
        vals = [row["alpha"] for v in r.values() if v["metal"] == m for row in v["rows"].values()]
        assert b["alpha_min"] == min(vals) and b["alpha_max_ADVERSE"] == max(vals), m
    tags = {t for v in r.values() for t in v["rows"]}
    def sets(metal):
        return [k for k, v in r.items() if v["metal"] == metal]

    def at(tag, keys):
        return [r[k]["rows"][tag]["alpha"] for k in keys if tag in r[k]["rows"]]

    for tag in tags:
        a = lambda ks, tag=tag: at(tag, ks)  # noqa: E731
        co, cu = a(sets("Co")), a(sets("Cu"))
        if co and cu:
            assert max(co) < min(cu), f"Co is not the weakest at {tag}"
        ce_b, cu_n, cu_z = a(["ce_buzko"]), a(["cu_nist_25", "cu_nist_20"]), a(["cu_zab21"])
        if ce_b and cu_n:
            assert ce_b[0] > max(cu_n), f"Ce (Buzko) not above Cu (NIST) at {tag}"
        if ce_b and cu_z:
            assert cu_z[0] > ce_b[0], f"Cu (Zabiszak) not above Ce (Buzko) at {tag} — the brackets no longer overlap"
    assert abs(d["competition"]["free_L_spread_vs_selected"]) < 0.1


def test_coin_replicate_power_invariants():
    """100 (00_07 HW.24, the replicate-power leg): what must hold whatever the assumed spread grid moves to.

    CAN catch: a two-arm table that stops falling with n or rising with CV; a single-coupon contrast easier than an
    equal-n one; the three gate readings losing their opposite trends, or the findings/verdict stating a trend the
    margins do not show; pass probabilities at the threshold that are not exactly 0.5 · α · 0.5ⁿ; budget arithmetic
    that no longer reproduces the letter's «at 19»; a Monte Carlo control outside its declared tolerance; a cache
    stale against the code (one cell recomputed from the module). CANNOT catch: whether the CV grid is realistic —
    no coin has been measured; the reading of «≥ threshold» is a verdict homed in 01_03 §3.5, not a property of a cache.
    """
    import importlib.util

    from lib.constants import (
        COIN_BENCHMARK_ALLOYS,
        COIN_CONTROL_ALLOY,
        COIN_ELECTRODE_ARMS,
        COIN_HOLD_DAYS,
        COIN_QUOTE_CONTROL_HIGH,
        COIN_RESERVE_12WK_PER_ALLOY,
        COIN_UNCOATED_ICPMS_PER_ALLOY,
    )
    d = json.loads((KINETICS / "coin_replicate_power.json").read_text(encoding="utf-8"))
    conv = d["conventions"]
    ns, cvs = [str(n) for n in conv["n_grid"]], [f"{cv:.2f}" for cv in conv["cv_assumed_NOT_MEASURED"]]

    eq, single = d["two_arm"]["ratio_detectable_equal_n"], d["two_arm"]["ratio_detectable_single_vs_n"]
    for cv in cvs:
        assert all(eq[cv][a] > eq[cv][b] for a, b in itertools.pairwise(ns)), cv
        assert all(single[cv][n] > eq[cv][n] for n in ns), cv
    for n in ns:
        assert all(eq[a][n] < eq[b][n] for a, b in itertools.pairwise(cvs)), n
    # the pooled reading has more degrees of freedom, so it resolves more in every cell; the single coupon's own spread
    # never averages out, so no n takes its contrast below the known-spread floor
    floor = d["two_arm"]["single_coupon_floor"]
    for cv in cvs:
        for n in ns:
            assert d["two_arm"]["ratio_detectable_equal_n_pooled"][cv][n] < eq[cv][n], (cv, n)
            assert floor[cv] < d["two_arm"]["ratio_detectable_single_vs_n_pooled"][cv][n] < single[cv][n], (cv, n)

    g = d["gate"]
    expect = {"every_coupon": "grows", "lower_bound": "shrinks", "arm_mean": "shrinks"}
    assert d["findings"]["gate_margin_with_n"]["lower_bound_pooled"] == "shrinks"
    for r, direction in expect.items():
        for cv in cvs:
            row = [g["margin_ratio_needed"][r][cv][n] for n in ns]
            pairs = list(itertools.pairwise(row))
            assert all(a < b for a, b in pairs) if direction == "grows" else all(a > b for a, b in pairs), (r, cv)
        assert d["findings"]["gate_margin_with_n"][r] == direction
        assert f"{direction} with n when every coupon" in d["verdict"] if r == "every_coupon" else True
    for n in ns:
        assert g["p_pass_at_threshold"]["arm_mean"][n] == 0.5
        assert g["p_pass_at_threshold"]["lower_bound"][n] == pytest.approx(conv["alpha"], abs=1e-4)
        assert g["p_pass_at_threshold"]["every_coupon"][n] == pytest.approx(0.5 ** int(n), abs=1e-4)
    for cv in cvs:
        tgt = g["D_p_pass_at_target"]
        # non-strict: the cache rounds to 6 decimals, and a tight spread saturates the arm mean at 1.0
        assert all(tgt["every_coupon"][cv][a] >= tgt["every_coupon"][cv][b] for a, b in itertools.pairwise(ns))
        assert all(tgt["arm_mean"][cv][a] <= tgt["arm_mean"][cv][b] for a, b in itertools.pairwise(ns))

    assert COIN_CONTROL_ALLOY not in d["selection"]["candidates"]
    assert not set(COIN_BENCHMARK_ALLOYS) & set(d["selection"]["candidates"])
    assert len(d["selection"]["candidates"]) == len(COIN_ELECTRODE_ARMS) - 1 - len(COIN_BENCHMARK_ALLOYS)
    non_electrode = COIN_UNCOATED_ICPMS_PER_ALLOY + COIN_RESERVE_12WK_PER_ALLOY
    c_arms = sum(v for arms in COIN_ELECTRODE_ARMS.values() for v in arms.values())
    for n in ns:
        b = d["budget"]["by_n"][n]
        for alloy, row in b["per_alloy"].items():
            assert row["coupons_needed"] == len(COIN_ELECTRODE_ARMS[alloy]) * int(n) + non_electrode
            assert row["fits_letter_quote"] == (row["coupons_needed"] <= row["letter_quote_point"])
        assert b["C_channel_days"] == c_arms * int(n) * COIN_HOLD_DAYS
    assert d["budget"]["by_n"]["2"]["per_alloy"][COIN_CONTROL_ALLOY]["coupons_needed"] == COIN_QUOTE_CONTROL_HIGH
    ceiling = d["budget"]["letter_ceiling"]
    single_rep = sorted(a for a, c in ceiling.items() if c["max_equal_n_per_arm"] < 2)
    assert d["findings"]["alloys_whose_letter_quote_gives_an_arm_a_single_replicate"] == single_rep
    assert all(a in d["verdict"] for a in single_rep)

    ctl = d["control"]
    assert ctl["tolerance"] == pytest.approx(4.0 * math.sqrt(conv["p_target"] * (1 - conv["p_target"]) / ctl["trials"]),
                                             abs=1e-4)
    for cell in ctl["cells"]:
        assert cell["worst_miss"] <= ctl["tolerance"], cell
        assert max(abs(p - conv["p_target"]) for p in cell["p_simulated"].values()) == pytest.approx(cell["worst_miss"],
                                                                                                    abs=1e-4)

    spec = importlib.util.spec_from_file_location("s100", REPO / "tools/in_silico/scripts/100_coin_replicate_power.py")
    s100 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(s100)
    sig = s100.sigma_log(0.10)
    u = s100.solve_increasing(lambda x: s100.two_arm_power(x, sig, 3, 3), conv["p_target"])
    assert math.exp(u) == pytest.approx(eq["0.10"]["3"], abs=1e-4), "the cache is stale against script 100"

    mx = g["max_cv_for_best_case"]
    assert all(v is None for r in mx["E"]["by_reading"].values() for v in r.values()), "E's best case IS its threshold"
    assert all(mx["C"]["by_reading"]["lower_bound_pooled"][n] > mx["C"]["by_reading"]["lower_bound"][n] for n in ns)
    assert "lower_bound_pooled" not in mx["D"]["by_reading"], "D is measured on its own arm only — nothing to pool"
    for gate in ("C", "D"):
        rows = mx[gate]["by_reading"]
        assert all(rows["every_coupon"][a] > rows["every_coupon"][b] for a, b in itertools.pairwise(ns)), gate
        for r in ("arm_mean", "lower_bound"):
            assert all(rows[r][a] < rows[r][b] for a, b in itertools.pairwise(ns)), (gate, r)
    best, thr = mx["C"]["best_case_ratio"], mx["C"]["threshold"]
    cv_star = mx["C"]["by_reading"]["lower_bound"]["3"]
    p = s100.pass_probability("lower_bound", math.log(best / thr), s100.sigma_log(cv_star), 3)
    assert p == pytest.approx(conv["p_target"], abs=2e-3), "max_cv does not return P_TARGET at its own CV"



def test_script_40_t_table_matches_scipy():
    """Script 40 carries one-sided 95 % t quantiles as a table so it stays stdlib-only in the bare CI job; this pins the
    table to scipy here, where scipy is installed. CAN catch: a mistyped or shifted entry. CANNOT catch: a df the table
    does not carry — 40 refuses that itself."""
    import importlib.util

    from scipy import stats
    spec = importlib.util.spec_from_file_location("s40", REPO / "tools/in_silico/scripts/40_validate_vs_experiment.py")
    s40 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(s40)
    assert sorted(s40.T_ONE_SIDED_95) == list(range(1, 31))
    for df, value in s40.T_ONE_SIDED_95.items():
        assert value == pytest.approx(stats.t.ppf(0.95, df), abs=5e-5), df




def test_anchor_wood_share_invariants():
    """103 (00_07 HW.43, the share leg): every stiffness and share recomputed HERE from the lib, the `55`/`77`/`78`/`86`/
    `87` caches and the script's named literature readings — by the CLOSED FORMS of each state, not the script's 3-node
    solver — and every threshold checked by LANDING on its target.

    CAN catch: G_eff off √(G_LR·G_RT); a sleeve, bond or bearing stiffness off its form; a state-2 share off k_c/(k_c +
    k_sleeve), its CTE off the series chain against the wood's growth to the bond's depth less the anode metal's; a
    state-3 share or CTE at a rigid tie off its two segments (bearing released, or a rigid bark); a state-2 bearing
    threshold that does not land its event, a 0 not already reached with no bearing or a None a rigid bark would reach; a
    state-3 depth threshold that does not land its event with no bearing, a «deepest» not reached at the install-day
    cambium or a None reached at the shallowest tie; the state-2 / state-3 readings off their definitions; Ta's seam
    (rebuilt here on `102`'s own `Pair` and `soderberg_k`, the share scaled to `102`'s shift) off in state 1, at the
    air-dry readings or at its state-3 least; an at-share-1 seam off `102`'s grid; the CTE's floor over the ends of every
    axis and the depth axis, the travel's sign-change CTE or the fully coupled floor off their forms, or the «wood only
    shortens the travel» flag not following; the cached controls out of tolerance (a hand-edited cache — the script
    raises before it writes). CANNOT: judge the literature readings, the bond's shear-lag form or a rigid tie as a model of a callus
    ring; it re-implements what each state IS, so a wrong idea of a state reaches both.
    """
    import importlib.util

    from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, ALPHA_PEEK_1K, E_PEEK_PA, PEEK_RELAX_FLOOR
    d = json.loads((MECHANICAL / "anchor_wood_share.json").read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location("s103_share", REPO / "tools/in_silico/scripts/103_anchor_wood_share.py")
    s103 = importlib.util.module_from_spec(spec)
    sys.modules["s103_share"] = s103
    spec.loader.exec_module(s103)
    g77 = json.loads((MECHANICAL / "anchor_torque_path.json").read_text(encoding="utf-8"))["geometry"]
    b78 = json.loads((REPO / "tools/in_silico/cache/thermal/flange_cambium_heat.json").read_text(encoding="utf-8"))
    d87 = json.loads((MECHANICAL / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    d102 = json.loads((MECHANICAL / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    d86 = json.loads((MECHANICAL / "coaxiality_allocation.json").read_text(encoding="utf-8"))
    aw, ap, aa = s103.ALPHA_XYLEM_GREEN_1K, ALPHA_PEEK_1K, ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    for k, (lr, rt) in s103.G_PAIRS_MPA.items():
        assert d["inputs"]["G_eff_MPa"][k] == pytest.approx(math.sqrt(lr * rt), abs=0.006), k
    r_s, r_b = g77["sleeve_outer_radius_m"] * 1e3, g77["shank_radius_m"] * 1e3
    s55 = s103.s55
    span = s55.PEEK_GAP_MM + s55.SHANK_LEN_MM
    ks = {"sway": E_PEEK_PA / 1e6 * math.pi * (r_s ** 2 - r_b ** 2) / span}
    ks["slow"] = ks["sway"] * PEEK_RELAX_FLOOR
    st = d["stiffness_N_per_mm"]
    assert (st["sleeve"]["sway"], st["sleeve"]["slow"]) == pytest.approx((ks["sway"], ks["slow"]), abs=0.1)
    ann = math.pi / 4 * (b78["bark"]["flange_diameter_mm"] ** 2 - (2 * r_s) ** 2)
    barks = {"thin_contact_78": b78["bark"]["thin_mm"], "thick_side_78": b78["bark"]["thick_mm"]}
    tie = {t: tv + b78["inputs"]["phloem_mm"] for t, tv in barks.items()}
    dvs = {k: v * 1e3 for k, v in d87["inputs"]["depth_span_m"].items()}
    dv_ceil, d_deep = max(dvs.values()), max(tie.values())
    assert d["geometry"]["flange_seat_to_install_day_cambium_mm"] == pytest.approx(tie)
    kf_read = {f"{e}__{t}": ev * ann / tv for e, ev in s103.E_BARK_RADIAL_MPA.items() for t, tv in barks.items()}
    for k, v in kf_read.items():
        assert st["bark_bearing_at_air_dry_readings"][k] == pytest.approx(v, abs=0.002), k
    k_a = {f"{g}__ln{ln:g}": 2 * math.pi * math.sqrt(lr * rt) * g77["gyroid_length_m"] * 1e3 / ln
           for g, (lr, rt) in s103.G_PAIRS_MPA.items() for ln in s103.LN_R_OVER_R}
    for k, v in k_a.items():
        assert st["anode_bond"][k] == pytest.approx(v, abs=0.1), k
    bonds = {"anode_bond_stiff": max(k_a.values()), "anode_bond_soft": min(k_a.values())}
    # the anode's shank pressed into the sleeve, read bonded over its run (the fits' one rule): its free CTE by mixtures
    lock1 = json.loads((REPO / "tools/cad/cem/mechanical_lock.zone1.json").read_text(encoding="utf-8"))
    l_z1 = lock1["shank_length_mm"]
    ea1_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3 * math.pi / 4 * (lock1["shank_diameter_mm"] ** 2 - lock1["bore_diameter_mm"] ** 2)
    ea1_p = E_PEEK_PA / 1e6 * PEEK_RELAX_FLOOR * math.pi * (r_s ** 2 - r_b ** 2)
    al_z1 = (ea1_ti * aa + ea1_p * ap) / (ea1_ti + ea1_p)
    assert d["geometry"]["zone1_shank_in_sleeve"]["alpha_bonded_ppm_K"] == pytest.approx(al_z1 * 1e6, abs=1e-4)

    def w_a(dv, ax=aw, bonded=True):
        return ax * dv - (al_z1 if bonded else aa) * l_z1 - aa * (dv - span - l_z1)

    def kc_of(kf, ka):
        return 0.0 if kf == 0 else 1 / (1 / ka + 1 / kf)

    def sh2(kf, ka):
        kc = kc_of(kf, ka)
        return kc / (kc + ks["sway"])

    def ae2(kf, ka, dv, ax=aw, bonded=True):
        kc, e0 = kc_of(kf, ka), ap * span
        return (e0 + (w_a(dv, ax, bonded) - e0) * kc / (kc + ks["slow"])) / span * 1e6

    def seg(ka, dd, load):
        return ka / (ka + ks[load] * span / (span - dd))

    def sh3(ka, dd, dv, rigid_bark=False):
        return (dd / dv if rigid_bark else 0.0) + seg(ka, dd, "sway") * (dv - dd) / dv

    def ae3(ka, dd, dv, rigid_bark=False, ax=aw, bonded=True):
        e_lo = ap * (span - dd)
        upper = ax * dd if rigid_bark else ap * dd
        return (upper + e_lo + (w_a(dv, ax, bonded) - ax * dd - e_lo) * seg(ka, dd, "slow")) / span * 1e6

    sh = d["share"]
    read2 = [sh2(kf, ka) for kf in kf_read.values() for ka in k_a.values()]
    assert (sh["state2_at_air_dry_readings"]["min"], sh["state2_at_air_dry_readings"]["max"]) == pytest.approx((min(read2), max(read2)), abs=1e-4)
    depths = {t: [s103.DEPTH_MIN + (dd - s103.DEPTH_MIN) * i / 40 for i in range(41)] for t, dd in tie.items()}
    for b, ka in bonds.items():
        assert sh["state2_cap_rigid_bark"][b] == pytest.approx(ka / (ka + ks["sway"]), abs=1e-4), b
        free = [sh3(ka, dd, dv) * dv / dv_ceil for ds in depths.values() for dd in ds for dv in dvs.values()]
        got = sh["state3_no_bearing_any_depth_of_102_shift"][b]
        assert (got["min"], got["max"]) == pytest.approx((min(free), max(free)), abs=1e-4), b
        assert sh["state3_cap_rigid_bark_of_102_shift"][b] == pytest.approx(
            max(sh3(ka, dd, dv, True) * dv / dv_ceil for ds in depths.values() for dd in ds for dv in dvs.values()), abs=2e-4), b

    # Ta's seam rebuilt on `102`'s own closed form and cached inputs
    geo = d102["geometry"]
    shipped = d86["by_geometry"][next(k for k in d86["by_geometry"] if k.startswith("shipped"))]["by_alloy"]
    amp86, off86 = d102["seam_86_inputs"]["amplitude_MPa"], d102["seam_86_inputs"]["offset_um"]
    grips = d102["grip"]["by_part_N_per_mm_at_20C"]["window_ceiling"]
    shift_hi = max(d102["sway_input"]["shift_um_87"]["upper_whisker"]) * 1e-3

    def seam(alloy, share, preload, reversed_=True):
        row86 = shipped[alloy]
        mean86 = next(o["mean_MPa"] for o in row86["by_offset"] if o["offset_um"] == off86)
        pair = s103.s102.Pair(grips[max(grips, key=float)], ALLOY_PROPERTIES[alloy]["E_GPa"] * 1e3 * geo["wire_area_mm2"],
                              geo["liner_EA_N"], geo["bare_run_mm"], geo["liner_run_mm"], geo["wall_cap_N_23C"])
        c = pair.cycle(share * shift_hi, 0.0) if reversed_ else pair.cycle(share * shift_hi / 2, share * shift_hi / 2)
        f_amp, f_mean = c["F_amp"], c["F_mean"]
        if preload:
            f_mean = min(f_mean + d102["seam_by_alloy"][alloy]["hot_preload"]["F_N_relaxed_liner"], pair.cap - f_amp)
        return s103.s102.soderberg_k(amp86, mean86, f_amp, f_mean, geo["wire_area_mm2"], row86)
    assert seam("Ta", 0.0, True) == pytest.approx(d102["seam_by_alloy"]["Ta"]["by_share"]["0"]["seam_k_adverse_with_preload"], abs=2e-4)

    def event(name, share, cte):
        if name.startswith("share_"):
            return share - float(name.split("_")[1])
        if name.startswith("ta_k1_"):
            return seam("Ta", share, name.endswith("hot_preload")) - 1.0
        return float(name.split("_")[2]) - cte
    thr_flip = d102["thermal"]["flip_vs_larger_margin_ppm_K"]
    names = {f"share_{r:g}" for r in s103.SHARE_ROWS} | {"ta_k1_sway_alone", "ta_k1_hot_preload"} | \
        {f"hot_flip_{x:g}" for x in thr_flip["hot_floor_part_flange_on_bark"]} | {f"cold_flip_{x:g}" for x in thr_flip["cold_flange_on_bark"]}
    T2, T3 = d["state2_bearing_N_per_mm"], d["state3_tie_depth_mm_no_bearing"]
    assert set(T2) == names == set(T3)
    keys = {f"{dk}__{b}" for dk in dvs for b in bonds}
    for name in names:
        assert set(T2[name]) == keys == set(T3[name]), name
        for key in keys:
            dk, b = key.split("__")
            ka, dv = bonds[b], dvs[dk]

            def ev2(kf, ka=ka, dv=dv, name=name):
                return event(name, sh2(kf, ka) * dv / dv_ceil, ae2(kf, ka, dv))

            def ev3(dd, ka=ka, dv=dv, name=name):
                return event(name, sh3(ka, dd, dv) * dv / dv_ceil, ae3(ka, dd, dv))
            v2, v3 = T2[name][key], T3[name][key]
            if v2 is None:
                assert ev2(1e12) < 0, (name, key)
            elif v2 == 0.0:
                assert ev2(s103.KF_LO) >= 0, (name, key)
            else:
                assert abs(ev2(v2)) < 2e-3, (name, key, v2)
            if v3 is None:
                assert ev3(s103.DEPTH_MIN) < 0, (name, key)
            elif v3 == "deepest":
                assert ev3(d_deep) >= 0, (name, key)
            else:
                assert ev3(v3 - 1e-3) >= -2e-3 and ev3(v3 + 1e-3) <= 2e-3, (name, key, v3)

    # the readings by their definitions
    def group(thr, name):
        return {f"{x}__{k}": v for x, vals in thr.items() if x == name or x.startswith(name + "_flip_") for k, v in vals.items()}
    for name, cell in d["readings"]["state2"].items():
        stiff = [v for k, v in group(T2, name).items() if k.endswith("anode_bond_stiff")]
        soft = [v for k, v in group(T2, name).items() if k.endswith("anode_bond_soft")]
        assert cell == {"no_below": None if None in stiff else min(stiff), "yes_above": None if None in soft else max(soft)}, name
    for name, cell in d["readings"]["state3"].items():
        dep = [v for k, v in group(T3, name).items() if k.endswith("anode_bond_stiff")]
        assert cell["reached_at_any_depth"] == ("deepest" in dep), name
        want = None if "deepest" in dep or all(v is None for v in dep) else max(v for v in dep if v is not None)
        assert cell["holds_only_deeper_than_mm"] == want, name

    # the seam values
    sv = d["seam_on_102_closed_form"]
    for alloy in ("Ta", ALLOY_BASELINE):
        assert sv[alloy]["state1"]["sway"] == d102["seam_by_alloy"][alloy]["seam_k_86"]
        assert sv[alloy]["state1"]["hot_preload"] == pytest.approx(seam(alloy, 0.0, True), abs=2e-4)
        r = sv[alloy]["state2_at_air_dry_readings_max"]
        assert (r["adverse_reversed"], r["adverse_reversed_hot_preload"], r["adverse_one_sided"]) == pytest.approx(
            (seam(alloy, max(read2), False), seam(alloy, max(read2), True), seam(alloy, max(read2), False, False)), abs=2e-4)
        for b, ka in bonds.items():
            least = sv[alloy]["state3_least_any_depth_and_bearing"][b]
            for corner, pre in (("adverse_reversed", False), ("adverse_reversed_hot_preload", True)):
                assert least[corner] == pytest.approx(min(seam(alloy, sh3(ka, d_deep, dv) * dv / dv_ceil, pre) for dv in dvs.values()), abs=2e-4)
        one = d102["seam_by_alloy"][alloy]["by_share"]["1"]["adverse"]
        a1 = sv[alloy]["at_share_1"]
        assert (a1["adverse_reversed"], a1["adverse_reversed_hot_preload"], a1["adverse_one_sided"]) == pytest.approx(
            (one["sway_reversed"]["seam_k"], one["sway_reversed_hot_preload"]["seam_k"], one["sway_one_sided"]["seam_k"]), abs=2e-4)

    # the heat floor over the ends of every axis (state 2: no tie; state 3: a rigid tie, bearing released or rigid) and
    # the depth axis, against the travel's sign change on `102`'s span; the floor of the span following the wood outright
    h = d["heat"]
    grid_d = [s103.DEPTH_MIN + (d_deep - s103.DEPTH_MIN) * i / 40 for i in range(41)]
    ctes = [ae2(kf, ka, dv) for kf in (0.0, 1e12) for ka in bonds.values() for dv in dvs.values()]
    ctes += [ae3(ka, dd, dv, rb) for rb in (False, True) for ka in bonds.values() for dd in grid_d for dv in dvs.values()]
    rev = aa * (s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM + s55.LINER_LENGTH_MM - s55.FLANGE_THK_MM) / span * 1e6
    floor = min(w_a(dv) for dv in dvs.values()) / span * 1e6
    assert (h["cte_min_ppm_K_over_the_model"], h["cte_travel_reverses_ppm_K_102"]) == pytest.approx((min(ctes), rev), abs=2e-3)
    assert h["wood_only_shortens_the_pad_travel"] == (min(ctes) > rev)
    assert h["cte_floor_span_follows_the_wood_ppm_K"] == pytest.approx(floor, abs=1e-5)
    assert h["reversed_shift_per_K_at_most_of_free_sleeve"] == pytest.approx((rev - floor) / (ap * 1e6 - rev), abs=1e-5)
    at = h["cte_min_at"]
    assert (at["bearing"], at["tie"], at["anode_bond"], at["tie_depth_mm"], at["bond_depth_mm"]) == ("rigid", "rigid", "stiff", pytest.approx(d_deep), dv_ceil)
    gd = h["deeper_tie_reaching_the_sign_change_mm_from_flange_seat"]          # a channel grip: the crossing lands on rev
    assert d_deep < gd < span and ae3(bonds["anode_bond_stiff"], gd, dv_ceil, True) == pytest.approx(rev, abs=2e-3)
    for side in ("cold", "hot"):                                                # the verdict quotes the depths floored
        v = d["readings"]["state3"][side]["holds_only_deeper_than_mm"]
        assert f"deeper than {math.floor(v * 10) / 10:g} mm" in d["verdict"], side
    assert h["thresholds_102_ppm_K"] == {"cold": thr_flip["cold_flange_on_bark"], "hot": thr_flip["hot_floor_part_flange_on_bark"]}

    def cte_min(ax=aw, bonded=True):
        v = [ae2(kf, ka, dv, ax, bonded) for kf in (0.0, 1e12) for ka in bonds.values() for dv in dvs.values()]
        return min(v + [ae3(ka, dd, dv, rb, ax, bonded) for rb in (False, True) for ka in bonds.values() for dd in grid_d for dv in dvs.values()])
    ax_rev = h["xylem_cte_at_which_the_wood_reverses_the_travel_ppm_K"] * 1e-6        # lands on the sign change
    assert cte_min(ax_rev) == pytest.approx(rev, abs=2e-3)
    ti_end = h["zone1_shank_held_at_its_end"]                                          # the favourable end, Ti alone
    floor_ti = min(w_a(dv, bonded=False) for dv in dvs.values()) / span * 1e6
    assert (ti_end["cte_min_ppm_K"], ti_end["cte_floor_span_follows_the_wood_ppm_K"]) == pytest.approx((cte_min(bonded=False), floor_ti), abs=2e-3)
    assert ti_end["cte_min_ppm_K"] >= h["cte_min_ppm_K_over_the_model"] and floor_ti >= floor
    c = d["controls"]
    assert c["solver_vs_closed_forms_max_miss"] < 1e-6 and max(c["monotone_worst_step"].values()) < 1e-8
    assert c["pad_travel_monotone_in_shift_worst_step"] <= 1e-12
    assert c["seam_vs_102_grid_max_miss"] < 2e-4


def test_wire_liner_shear_lag_invariants():
    """102 (00_07 HW.43, the shear-lag leg): what must hold whatever the inputs move to — recomputed HERE from the lib's
    constants, `55`'s spans and grip rows, and the `77`/`79`/`86`/`87`/`90` caches, not from the script's algebra.

    CAN catch: a thermal shift per kelvin off (α_PEEK·L_PEEK + α_flange·L_Ti − α_wire·L_wire); a window-floor part that
    still grips at the hot edge; a root force that does not invert δ(F) = share·shift through the closed form
    re-implemented here; a seam k off Soderberg — re-implemented here on `86`'s cached amplitude, mean, endurance and
    yield — in every uncapped cell, and a capped cell off `87`'s ceiling reading; a requirement that falls as the share
    grows, or a gentle corner above the adverse; a grip row off `55`; a force past the wall's cap; the exact cap share and
    the wire's stretch at the cap off the closed form; a pad fraction outside [0, 1] or a floor part passing less than a
    gripping one; `79` (at `90`'s surface α)/`86`/`87`/`90` inputs stale against their caches; a sleeve ratio off E·A/L
    over the secant; a cold CTE flip threshold whose protrusion is not the margin (closed form re-implemented) or a hot one
    off its analytic value α_Ti + m/(L_PEEK·ΔT), its `None` included; a row maximum that is not the max of its cells; the
    controls drifting past 0.2 %, or stick compliance pointing the non-conservative way at either grip. CANNOT catch: the share at any bond state (sway or heat), the
    compressive half, a tie of ice or resin, the capture, the wall's creep — the script's declared ceilings.
    """
    import importlib.util

    from lib.constants import (
        ALLOY_BASELINE,
        ALLOY_PROPERTIES,
        ALPHA_PEEK_1K,
        D_BUS_ROD_MM,
        E_PEEK_PA,
        PEEK_RELAX_FLOOR,
    )
    d = json.loads((MECHANICAL / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location("s55_shear", REPO / "tools/in_silico/scripts/55_bus_mechanical.py")
    s55 = importlib.util.module_from_spec(spec)
    sys.modules["s55_shear"] = s55          # 55 declares dataclasses, which look their module up here
    spec.loader.exec_module(s55)
    a, L = s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM, s55.LINER_LENGTH_MM
    assert (d["geometry"]["bare_run_mm"], d["geometry"]["liner_run_mm"]) == pytest.approx((a, L), abs=1e-9)
    cp = json.loads((MECHANICAL / "bus_mechanical.json").read_text(encoding="utf-8"))["interference_window"]["cold_press_fit"]
    rows = {r["at"]: r for r in cp["rows"]}
    ea_l = E_PEEK_PA / 1e6 * cp["tube_section_mm2"]
    cap = cp["peek_yield_MPa"] * cp["tube_section_mm2"]
    area = math.pi * D_BUS_ROD_MM ** 2 / 4

    def delta_of(f, q, ea_w):                  # the docstring's closed form, re-implemented
        s_sum = ea_w + ea_l
        r = ea_l / s_sum
        s_top, s_bot = f * (1 - r) / q, f * r / q
        return (f * a / ea_w + s_bot * f * (1 - r / 2) / ea_w + (L - s_top - s_bot) * f / s_sum
                + s_top * f * (1 + r) / (2 * ea_l))

    # inputs against their homes
    d86 = json.loads((MECHANICAL / "coaxiality_allocation.json").read_text(encoding="utf-8"))
    shipped = d86["by_geometry"][next(k for k in d86["by_geometry"] if k.startswith("shipped"))]
    d87 = json.loads((MECHANICAL / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    d90 = json.loads((MECHANICAL / "pogo_thermal_gap.json").read_text(encoding="utf-8"))
    th = d["thermal"]
    assert th["l1_margin_um_90_model_edges"] == {c: d90["seasonal"]["model_edges"][c]["window"]["L1 spacer only"]["margin_um"]
                                                 for c in ("isothermal_low_stack", "isothermal_high_stack")}
    assert th["temperatures_c"]["capsule_model_edges_90"] == d90["inputs"]["temperature_readings_c"]["model_edges"]
    heat = json.loads((REPO / "tools/in_silico/cache/thermal/flange_cambium_heat.json").read_text(encoding="utf-8"))["runs"]
    frost = json.loads((REPO / "tools/in_silico/cache/thermal/flange_cambium_frost.json").read_text(encoding="utf-8"))["runs"]
    cam = th["temperatures_c"]["cambium_under_flange_79"]
    assert cam[0] == min(x["cambium_min_C_model_lower_bound"]["flange"] for x in frost)
    spec90 = importlib.util.spec_from_file_location("s90_shear", REPO / "tools/in_silico/scripts/90_pogo_thermal_gap.py")
    s90 = importlib.util.module_from_spec(spec90)
    sys.modules["s90_shear"] = s90
    spec90.loader.exec_module(s90)
    assert cam[1] == max(x["cambium_max_C"] for x in heat if x["case"] == s90.DAILY_CASE and x["alpha"] == s90.DAILY_ALPHA)
    shift_hi = max(d87["by_slope_reading"]["upper_whisker"]["C_centre_pad_poisson"]["imposed_shift_um_at_source_strain"])
    sf = s55.INFINITE_LIFE_SF

    def k_sod(f_amp, f_mean, r86, mean86):     # Soderberg's break-even k, re-implemented on 86's cached inputs
        sa = shipped["amplitude_MPa"] + f_amp / area
        sm = mean86 + max(f_mean, 0.0) / area
        room = 1.0 / sf - sm / r86["yield_MPa"]
        return sa / (r86["endurance_MPa"] * room) if room > 0 else None

    q_gentle = rows["ratified_nominal"]["by_mu"]["0.1"]["friction_N"] / L * PEEK_RELAX_FLOOR
    for alloy, row in d["seam_by_alloy"].items():
        r86 = shipped["by_alloy"][alloy]
        mean86 = next(o["mean_MPa"] for o in r86["by_offset"] if o["offset_um"] == 50)
        k86 = next(o["k_break_even"] for o in r86["by_offset"] if o["offset_um"] == 50)
        assert row["gentle_grip_N_per_mm"] == pytest.approx(q_gentle, abs=1e-3)
        assert row["seam_k_86"] == pytest.approx(k86, abs=1e-4), alloy
        assert row["seam_k_at_wall_ceiling_87"] == d87["C_wire_behind_liner"]["by_alloy"][alloy]["seam_k_at_route_capacity"]
        ea_w = ALLOY_PROPERTIES[alloy]["E_GPa"] * 1e3 * area
        q_adv = rows["window_ceiling"]["by_mu"]["0.4"]["friction_N"] / L
        assert row["adverse_grip_N_per_mm"] == pytest.approx(q_adv, abs=1e-3)
        ks, prev = [], None
        for sh, g in row["by_share"].items():
            rev = g["adverse"]["sway_reversed"]
            assert rev["F_amp_N"] <= cap + 1e-6 and g["adverse"]["sway_reversed_hot_preload"]["F_amp_N"] <= cap + 1e-6
            if not rev["wall_or_slip_reached"] and rev["F_amp_N"] > 0:
                assert delta_of(rev["F_amp_N"], q_adv, ea_w) == pytest.approx(float(sh) * shift_hi * 1e-3, rel=2e-4), (alloy, sh)
            assert g["gentle_one_sided"]["seam_k"] <= g["seam_k_adverse_sway"] + 1e-9, (alloy, sh)
            for cname, cell in g["adverse"].items():
                if cname.startswith("sway_reversed") and cell["wall_or_slip_reached"] and cell["F_mean_N"] == 0.0:
                    assert cell["seam_k"] == pytest.approx(row["seam_k_at_wall_ceiling_87"], abs=2e-4), (alloy, sh, cname)
                expected = k_sod(cell["F_amp_N"], cell["F_mean_N"], r86, mean86)
                assert (cell["seam_k"] is None) == (expected is None), (alloy, sh, cname)
                if expected is not None:
                    assert cell["seam_k"] == pytest.approx(expected, abs=2e-4), (alloy, sh, cname)
            adv = g["adverse"]
            assert g["seam_k_adverse_sway"] == max(adv["sway_reversed"]["seam_k"], adv["sway_one_sided"]["seam_k"])
            assert g["seam_k_adverse_with_preload"] == max(c["seam_k"] for c in adv.values())
            gen = g["gentle_one_sided"]
            assert gen["seam_k"] == pytest.approx(k_sod(gen["F_amp_N"], gen["F_mean_N"], r86, mean86), abs=2e-4), (alloy, sh)
            if prev is not None:
                assert g["seam_k_adverse_sway"] >= prev - 1e-9, (alloy, sh)
            prev = g["seam_k_adverse_sway"]
            ks.append(g["seam_k_adverse_sway"])
        assert ks[0] == pytest.approx(row["seam_k_86"], abs=1e-4)
        assert row["wire_stretch_at_wall_cap_um_max"] == pytest.approx(cap * (a + L) / ea_w * 1e3, abs=0.006), alloy
        if row["adverse_share_at_wall_cap_exact"] is not None:
            assert row["adverse_share_at_wall_cap_exact"] == pytest.approx(delta_of(cap, q_adv, ea_w) / (shift_hi * 1e-3), abs=1e-4)
    # the pad
    pads = d["pad_sway_share1_upper_whisker_high"]
    assert all(0.0 <= v["fraction_of_shift"] <= 1.0 for v in pads.values())
    assert min(v["fraction_of_shift"] for k, v in pads.items() if k.startswith("window_floor")) >= \
        max(v["fraction_of_shift"] for k, v in pads.items() if not k.startswith("window_floor"))
    # heat
    a_fl = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    spans = {"gap_and_shank_disc_on_sleeve_top": (s55.PEEK_GAP_MM + s55.SHANK_LEN_MM, s55.FLANGE_THK_MM),
             "gap_only_shank_held_at_its_end": (s55.PEEK_GAP_MM, s55.SHANK_LEN_MM + s55.FLANGE_THK_MM)}
    for key, v in th["by_reading"].items():
        peek, ti = spans[key.split("__")[0]]
        per_k = (ALPHA_PEEK_1K * peek + a_fl * ti - a_fl * (a + L)) * 1e3
        assert v["shift_um_per_K"] == pytest.approx(per_k, abs=1e-4), key
        if "__window_floor__" in key:
            assert v["hot"]["grip_N_per_mm"] == 0.0 and v["hot"]["root_F_N"] == 0.0, key
            assert v["hot"]["pad_recedes_um"] == pytest.approx(v["hot"]["shift_um"], abs=0.011), key
    al = th["against_l1"]
    floor_hot = [v["hot"]["pad_recedes_um"] for k, v in th["by_reading"].items() if "__window_floor__" in k]
    assert al["hot_floor_part_past_smaller_lower_margin"] == sum(x > th["l1_margin_to_lower_edge_min_um"] for x in floor_hot)
    assert al["cold_min_protrusion_um"] == min(v["cold"]["pad_protrudes_um"] for v in th["by_reading"].values())
    # the sleeve and the controls
    g77 = json.loads((MECHANICAL / "anchor_torque_path.json").read_text(encoding="utf-8"))["geometry"]
    a_sl = math.pi * ((g77["sleeve_outer_radius_m"] * 1e3) ** 2 - (g77["shank_radius_m"] * 1e3) ** 2)
    k_sl = E_PEEK_PA / 1e6 * a_sl / (s55.PEEK_GAP_MM + s55.SHANK_LEN_MM)
    assert d["sleeve_vs_wire"]["sleeve_k_N_per_mm"] == pytest.approx(k_sl, abs=0.1)
    k_wire = min(cap, rows["window_ceiling"]["by_mu"]["0.4"]["friction_N"]) / (shift_hi * 1e-3)
    assert d["sleeve_vs_wire"]["ratio"] == pytest.approx(k_sl / k_wire, abs=0.06)
    t_ref = d90["inputs"]["assembly_temperature_c"]
    dalpha_r = (ALPHA_PEEK_1K - a_fl) * D_BUS_ROD_MM / 2 * 1e3
    temps = th["temperatures_c"]
    for key, v in th["flip_effective_cte_ppm_K"].items():
        sname, tname = key.split("__")
        peek = spans[sname][0]
        t_lo, t_hi = temps[tname]
        cold = v["cold_tightest_grip_vs_upper_margin_ppm_K"]
        lo_m, hi_m = sorted(cold, key=float)
        assert a_fl * 1e6 < cold[lo_m] <= cold[hi_m] < ALPHA_PEEK_1K * 1e6
        # cold: at the threshold the tightest grip's protrusion equals the margin — the closed form re-implemented here
        i20 = rows["window_ceiling"]["interference_radial_um"]
        q_cold = rows["window_ceiling"]["by_mu"]["0.4"]["friction_N"] / L * (i20 - dalpha_r * (t_lo - t_ref)) / i20
        ea_wb = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3 * area
        ea_lr = ea_l * PEEK_RELAX_FLOOR
        for m_key, alpha in cold.items():
            dlt = abs((alpha * 1e-6 - a_fl) * peek * (t_lo - t_ref))
            s_sum = ea_wb + ea_lr
            r = ea_lr / s_sum
            quad = (r * (1 - r / 2) / ea_wb - 1 / s_sum + (1 - r ** 2) / (2 * ea_lr)) / q_cold
            lin = a / ea_wb + L / s_sum
            f = (-lin + math.sqrt(lin ** 2 + 4 * quad * dlt)) / (2 * quad)
            assert f < cap
            pad = f * (1 - r) / q_cold * f * ((1 + r) / (2 * ea_lr) - (1 - r) / (2 * ea_wb)) * 1e3
            assert pad == pytest.approx(float(m_key), abs=0.01), (key, m_key)
        # hot: a floor part grips with nothing there, so the threshold is analytic — α_Ti + m/(L_PEEK·ΔT)
        for m_key, alpha in v["hot_floor_part_vs_lower_margin_ppm_K"].items():
            exact = (a_fl + float(m_key) * 1e-3 / (peek * (t_hi - t_ref))) * 1e6
            if exact > ALPHA_PEEK_1K * 1e6:
                assert alpha is None, (key, m_key)
            else:
                assert alpha == pytest.approx(exact, abs=2e-3), (key, m_key)
    c = d["controls"]
    for v in c["virgin"]:
        assert v["F_fe_wall_shear_N"] <= v["F_closed_N"] * (1 + 1e-3) and v["pad_fe_wall_shear_um"] >= v["pad_closed_um"] * (1 - 1e-3)
        assert v["F_fe_rigid_N"] == pytest.approx(v["F_closed_N"], rel=2e-3)
        assert v["pad_fe_rigid_um"] == pytest.approx(v["pad_closed_um"], rel=2e-3, abs=1e-3)
    m = c["masing_loop"]
    assert m["F_amp_fe_N"] == pytest.approx(m["F_amp_masing_N"], rel=2e-3)
    assert abs(m["F_mean_fe_N"] - m["F_mean_masing_N"]) <= 2e-3 * m["F_amp_masing_N"]
    assert 0.0 < c["stick_compliance_effect_on_F_max"] < 0.05
    assert all(s["F_rel"] <= 1e-3 and s["pad_rel"] >= -1e-3 for s in c["stick_compliance_at_tightest_grip"])
    # the hot preload on both spans — `103`'s seam input for each premise: the relaxed liner's virgin force at the span's
    # hot shift, by the closed form re-implemented here; and the gap-only span's hot threshold row
    t_hot = temps["capsule_model_edges_90"][1]
    i20c = rows["window_ceiling"]["interference_radial_um"]
    q_hot = rows["window_ceiling"]["by_mu"]["0.4"]["friction_N"] / L * max(0.0, i20c - dalpha_r * (t_hot - t_ref)) / i20c
    ea_lr = ea_l * PEEK_RELAX_FLOOR

    def delta_relaxed(f, ea_w):
        s_sum = ea_w + ea_lr
        r = ea_lr / s_sum
        s_top, s_bot = f * (1 - r) / q_hot, f * r / q_hot
        return (f * a / ea_w + s_bot * f * (1 - r / 2) / ea_w + (L - s_top - s_bot) * f / s_sum
                + s_top * f * (1 + r) / (2 * ea_lr))
    for alloy, row in d["seam_by_alloy"].items():
        hp, ea_w = row["hot_preload"], ALLOY_PROPERTIES[alloy]["E_GPa"] * 1e3 * area
        fl = s55.cem("cathode_flange")
        ea3_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3 * math.pi / 4 * (fl["shank_diameter_mm"] ** 2 - fl["bore_diameter_mm"] ** 2)
        ea3_p = E_PEEK_PA / 1e6 * PEEK_RELAX_FLOOR * a_sl
        al3 = (ea3_ti * a_fl + ea3_p * ALPHA_PEEK_1K) / (ea3_ti + ea3_p)      # the shank's run bonded, by mixtures
        assert hp["zone3_fit_bonded_shank"]["alpha_shank_run_ppm_K"] == pytest.approx(al3 * 1e6, abs=1e-4)
        peek32, ti32 = spans["gap_and_shank_disc_on_sleeve_top"]
        for cell, shift_key, grow in ((hp, "shift_um_span32", ALPHA_PEEK_1K * peek32 + a_fl * ti32),
                                      (hp["zone3_fit_bonded_shank"], "shift_um",
                                       ALPHA_PEEK_1K * s55.PEEK_GAP_MM + al3 * s55.SHANK_LEN_MM + a_fl * s55.FLANGE_THK_MM)):
            shift = (grow - ALLOY_PROPERTIES[alloy]["alpha_1K"] * (a + L)) * (t_hot - t_ref)
            assert cell[shift_key] == pytest.approx(shift * 1e3, abs=0.006), (alloy, shift_key)
            assert not cell["capped"] and cell["F_N_relaxed_liner"] < min(q_hot * L, cap), alloy
            assert delta_relaxed(cell["F_N_relaxed_liner"], ea_w) == pytest.approx(shift, rel=1e-3), (alloy, shift_key)
    gap_hot = [v["hot_floor_part_vs_lower_margin_ppm_K"] for k, v in th["flip_effective_cte_ppm_K"].items()
               if k.startswith("gap_only")]
    big = max(gap_hot[0], key=float)
    vals = [x[big] for x in gap_hot if x[big] is not None]
    assert th["flip_vs_larger_margin_ppm_K"]["hot_floor_part_zone3_fit_gap_only"] == ([min(vals), max(vals)] if vals else [])


def test_pad_travel_remedies_invariants():
    """104 (00_07 HW.43, the leg «ціни ліків ходу центральної площадки», 2026-10-21): the prices of the remedies for the
    centre pad's thermal travel, recomputed HERE from the caches by closed forms — `52`'s residual rule by `math.hypot` on
    its members, rounded as `52`'s cache carries it; the need from the cached worst travel and `90`'s margins; the stroke
    from `90`'s half-window; the δ routes' shift per kelvin from the CTEs.

    CAN catch: a residual or gain off `52`'s rule or `90`'s rounding; a need on the wrong edge, margin or reading; a spare
    off gain − need on either reading; a closing stroke off the half-window; a closing run whose shank does not take up
    the gap; the held + sway need below the held one, below its own kept points, or above the held need plus the sway at
    the largest share (its bounds); the routes that keep the wire–liner pair closing at different shifts per kelvin (the
    mechanism the verdict quotes: closing the need pins δ/K); a seam requirement that rises under a δ route at a corner the wall does not cap, or moves
    at one it caps; the placeholder-shank sensitivity off its sign. CANNOT: re-derive the pad's travel or the sway
    amplitude (`102`'s Pair — the script's control (a) holds it to `102`'s cache), or judge the readings the script
    declares (two readings, bonded shank, every grip).
    """
    import importlib.util

    from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, ALPHA_PEEK_1K
    d = json.loads((MECHANICAL / "pad_travel_remedies.json").read_text(encoding="utf-8"))
    d90 = json.loads((MECHANICAL / "pogo_thermal_gap.json").read_text(encoding="utf-8"))
    d103 = json.loads((MECHANICAL / "anchor_wood_share.json").read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location("s52_104", REPO / "tools/in_silico/scripts/52_z_stack_tolerance.py")
    s52 = importlib.util.module_from_spec(spec)
    sys.modules["s52_104"] = s52
    spec.loader.exec_module(s52)

    def c3(x):
        return math.ceil(round(x * 1000, 9)) / 1000
    cnc, half_step = s52.TOL_PZ["CNC_radome"], s52.SPACER_STEP / 2
    res90 = d90["inputs"]["mitigation_residual_mm_52"]
    assert c3(math.hypot(cnc, half_step)) == res90["L1 spacer only"]
    assert c3(math.hypot(cnc / 2, half_step)) == res90["L2 spacer + bayonet hard-stop"]
    # the ratified minimal mitigation (⚖️ 2026-10-21): `52`'s L3 rung is the finer step with the hard-stop — 104's (б)
    l3 = f"L3 spacer {s52.SPACER_STEP_FINE:g} mm + bayonet hard-stop"
    assert c3(math.hypot(cnc / 2, s52.SPACER_STEP_FINE / 2)) == res90[l3]
    assert json.loads((MECHANICAL / "z_stack_tolerance.json").read_text(encoding="utf-8"))["minimal_mitigation_ratified"]["label"] == l3
    l2 = "L2 bayonet hard-stop (CNC member 0.10 → 0.05 mm)"
    fine, l2fine = "spacer step 0.05 mm", "L2 hard-stop + spacer step 0.05 mm"
    res = {l2: c3(math.hypot(cnc / 2, half_step)), fine: c3(math.hypot(cnc, 0.025)), "spacer step → 0 (the lever's bound)": c3(cnc),
           l2fine: c3(math.hypot(cnc / 2, 0.025))}
    for k, r in res.items():
        assert d["window_side_gain_um"][k] == pytest.approx((res90["L1 spacer only"] - r) * 1e3, abs=1e-6)
    win = d90["seasonal"]["model_edges"]
    half = d90["inputs"]["window"][1] - d90["inputs"]["nominal_pct"]
    s0 = d90["inputs"]["pogo_travel_mm"]
    ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    a_s3 = d103["zone3_fit"]["alpha_composite_ppm_K"] * 1e-6
    gap0, shank0 = d["inputs"]["gap_mm"], d["inputs"]["shank_mm"]
    per_k = {}
    for sp, b in d["by_span"].items():
        for margins, key, worst_key in ((("isothermal_low_stack", "isothermal_high_stack"), "need_um", "need_um_isothermal_worst"),
                                        (("radome_leads_reading",), "need_um_radome_leads_by_temp", "need_um_radome_leads")):
            worst = -1e9
            for t, tr in b["travel_um_max"].items():
                for s_ in margins:
                    lo, hi = win[s_]["window"]["L1 spacer only"]["margin_um"]
                    n = max(tr["cold"] - hi, tr["hot"] - lo)
                    assert b[key][f"{t}__{s_}"]["need"] == pytest.approx(n, abs=1e-3)
                    worst = max(worst, n)
            assert b[worst_key] == pytest.approx(worst, abs=1e-3)
        held = b["need_um_isothermal_worst"]
        top = b["sway_alone_at_the_largest_share"]
        shift = d["inputs"]["shift_um_87"]
        for rd, v in b["need_um_held_plus_sway"].items():
            g_max = top[rd]["share"] * max(shift[rd])                    # the sway's increment is bounded by its shift
            assert v["free_sleeve_need"] == pytest.approx(held, abs=0.01)
            assert held - 1e-3 <= v["need_on_kept_points"] <= v["need"] + 1e-6 <= held + g_max + 1e-3
            assert v["sway_shift_um"] == pytest.approx(v["share"] * max(shift[rd]), abs=1e-4)
            vl = b["need_um_held_plus_sway_radome_leads"][rd]
            assert vl["need"] >= v["need"] - 1e-6 and vl["need"] <= b["need_um_radome_leads"] + g_max + 1e-3
            for k, g in d["window_side_gain_um"].items():
                assert b["window_side"][k][f"spare_um_held_plus_sway_{rd}_radome_leads"] == pytest.approx(g - vl["need"], abs=1e-3)
            br = b["window_breach_pct_of_stroke"][f"held_plus_sway_{rd}"]
            assert br["over_upper_edge"] == pytest.approx(v["cold_over_upper"] / (s0 * 10), abs=1e-4)
            assert br["under_lower_edge"] == pytest.approx(v["hot_over_lower"] / (s0 * 10), abs=1e-4)
            for k, g in d["window_side_gain_um"].items():
                assert b["window_side"][k][f"spare_um_held_plus_sway_{rd}"] == pytest.approx(g - v["need"], abs=1e-3)
            assert b["stroke"][f"stroke_mm_closing_held_plus_sway_{rd}"] == pytest.approx(s0 + max(0.0, v["need"]) / (half * 1e3), abs=1e-4)
        for k, g in d["window_side_gain_um"].items():
            assert b["window_side"][k]["spare_um_held"] == pytest.approx(g - held, abs=1e-3)
        assert b["stroke"]["stroke_mm_closing_held"] == pytest.approx(s0 + held / (half * 1e3), abs=1e-4)
        assert b["stroke"]["stroke_mm_with_L2_held"] == pytest.approx(s0 + max(0.0, held - d["window_side_gain_um"][l2]) / (half * 1e3), abs=1e-4)
        rl, rc = b["run_length"], b["run_cte"]
        if sp == "18":
            assert rl["shank_mm_closing"] == pytest.approx(shank0 + gap0 - rl["gap_mm_closing"], abs=1e-3)
            assert rc["cte_ppm_K_free_gap_with_bonded_shank"] == pytest.approx((ALPHA_PEEK_1K + (a_s3 - ti) * shank0 / gap0) * 1e6, abs=1e-3)
            per_k["18_length"] = (ALPHA_PEEK_1K - ti) * rl["gap_mm_closing"] + (a_s3 - ti) * rl["shank_mm_closing"]
            per_k["18_cte"] = (rc["cte_ppm_K_closing"] * 1e-6 - ti) * gap0 + (a_s3 - ti) * shank0
            sens = b["need_um_by_placeholder_shank"]
            assert sens["10"] > sens["14"] > sens["18"] and sens["14"] == pytest.approx(held, abs=1e-3)
            assert b["need_um_isothermal_worst_shank_as_ti"] < held                       # the bonded shank is the adverse end
            est = b["placeholder_shank_estimate"]
            slope = (sens["10"] - sens["14"]) / 4.0
            worst_l2f = min(v for k_, v in b["window_side"][l2fine].items() if k_.startswith("spare_um"))
            assert est["slope_um_per_mm_held"] == pytest.approx(slope, abs=1e-4)
            assert est["shortest_shank_mm_closing_with_l2fine"] == pytest.approx(shank0 - worst_l2f / slope, abs=1e-3)
        else:
            assert rl["route"] == "gap then shank" and rl["peek_run_mm_closing"] == pytest.approx(rl["gap_mm_closing"] + rl["shank_mm_closing"], abs=1e-3)
            per_k["32_cte"] = (rc["cte_ppm_K_closing"] * 1e-6 - ti) * (gap0 + shank0)
        for v in top.values():
            assert v["over_l1_um"] == pytest.approx(v["amp_um"] - min(min(win[s_]["window"]["L1 spacer only"]["margin_um"])
                                                                   for s_ in ("isothermal_low_stack", "isothermal_high_stack")), abs=1e-3)
        for sm in b["seam_hot_preload"].values():
            for route in ("run_length", "run_cte"):
                assert sm[route]["F_hot_N"] < sm["today"]["F_hot_N"] and sm[route]["seam_k_no_sway"] <= sm["today"]["seam_k_no_sway"]
    # closing the need pins the shift per kelvin where the wire–liner pair stays as it is — both CTE routes and the 18 mm
    # length route (the 32 mm length route cuts the shank and the liner run with it, so it is left out)
    assert max(per_k.values()) / min(per_k.values()) == pytest.approx(1.0, abs=0.005)
    sw = d["by_span"]["18"]["seam_with_sway"]
    st3 = sw["Ta"]["state3_least_stiff_bond"]
    assert min(st3["today"]["k"], st3["run_length"]["k"], st3["run_cte"]["k"]) > 1.0 > st3["sway_alone"]["k"]
    for corners in sw.values():
        for c in corners.values():
            if c["today"]["cap_binds"] and c["run_cte"]["cap_binds"]:
                assert c["run_cte"]["k"] == pytest.approx(c["today"]["k"], abs=1e-9)   # the wall caps it: δ changes nothing
            elif not c["run_cte"]["cap_binds"]:
                assert c["run_cte"]["k"] <= c["today"]["k"] + 1e-9
    assert max(c[r]["k"] for c in sw[ALLOY_BASELINE].values() for r in ("today", "run_length", "run_cte")) < 1.0
    c = d["controls"]
    assert c["pad_travel_vs_102_max_miss_um"] <= 0.006 and c["seam_vs_102_103_max_miss"] <= 2e-4
    assert c["seam_sway_corners_vs_103_max_miss"] <= 2e-3 and c["residuals_and_l2_step_vs_90_max_miss_um"] <= 0.05


def test_anchor_wood_share_cte_share_front():
    """103's (CTE, share) fronts (2026-10-21, read by 104): per premise, the configurations no other beats on both axes,
    kept every FRONT_STEP of share. CAN catch: a front that is not non-dominated (a CTE that rises along it, a share that
    does not); ends off the model's own extremes (the free sleeve at share 0; the larger rigid-bark cap of states 2 and 3;
    a CTE below the model's floor); kept points closer than the declared step. CANNOT: see a configuration
    the grids do not visit — the front is the grids' front."""
    d = json.loads((MECHANICAL / "anchor_wood_share.json").read_text(encoding="utf-8"))
    for block, sh, cte_free, cte_min in ((d, d["share"], 47.0, d["heat"]["cte_min_ppm_K_over_the_model"]),
                                         (d["zone3_fit"], d["zone3_fit"]["share"], d["zone3_fit"]["cte_free_sleeve_ppm_K"],
                                          d["zone3_fit"]["heat"]["cte_min_ppm_K_over_the_model"])):
        fr = block["cte_share_front"]
        ctes, shs = fr["cte_ppm_K"], fr["share_of_102_shift"]
        assert len(ctes) == len(shs) >= 2
        assert all(b < a + 1e-9 for a, b in itertools.pairwise(ctes))
        assert all(b > a for a, b in itertools.pairwise(shs))
        assert all(b - a >= fr["step"] - 1e-9 for a, b in itertools.pairwise(shs[:-1]))
        assert ctes[0] == pytest.approx(cte_free, abs=1e-3) and shs[0] == 0.0
        cap = max(*sh["state2_cap_rigid_bark"].values(), *sh["state3_cap_rigid_bark_of_102_shift"].values())
        assert shs[-1] == pytest.approx(cap, abs=1e-4)
        assert min(ctes) >= cte_min - 1e-3


def test_anchor_wood_share_zone3_fit_invariants():
    """103's `zone3_fit` block (00_07 HW.43, the heat with the flange on a Zone-3 fit, closed 2026-10-20): the sleeve as
    TWO sections — the Zone-3 shank's run, the CEM's Ti shank (less the bus channel) bonded to the PEEK around it, and the
    PEEK gap below it — recomputed HERE from the CEM, the lib and the caches by the closed forms of each state, not by
    the script's 3-node solver or its element chain.

    CAN catch: the composite's section, stiffness or CTE off its rule of mixtures; the CTE read over the wrong length
    (`102`'s gap-only convention: the shank's run at the flange alloy's CTE); a state-2 share or CTE off the series chain
    over the two sections; a state-3 share or CTE at a rigid tie off its segments when the tie sits inside or below the
    shank's run; a threshold that does not land its event (Ta's seam on `102`'s gap-only preload); a reading off its
    definition; the CTE floor, the sign-change CTE, the coupled floor, the reversed fraction or the «only shortens» flag
    off their forms on the gap; the element-chain control or the monotone controls out of tolerance. CANNOT: judge the
    rigid fit (its holding force is not in the tree), the CEM's placeholder shank, or a rigid tie on the Ti run as a
    model of a callus ring — the script's declared ceilings.
    """
    import importlib.util

    from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, ALPHA_PEEK_1K, E_PEEK_PA, PEEK_RELAX_FLOOR
    d = json.loads((MECHANICAL / "anchor_wood_share.json").read_text(encoding="utf-8"))
    z = d["zone3_fit"]
    spec = importlib.util.spec_from_file_location("s103_z3", REPO / "tools/in_silico/scripts/103_anchor_wood_share.py")
    s103 = importlib.util.module_from_spec(spec)
    sys.modules["s103_z3"] = s103
    spec.loader.exec_module(s103)
    s55 = s103.s55
    g77 = json.loads((MECHANICAL / "anchor_torque_path.json").read_text(encoding="utf-8"))["geometry"]
    b78 = json.loads((REPO / "tools/in_silico/cache/thermal/flange_cambium_heat.json").read_text(encoding="utf-8"))
    d87 = json.loads((MECHANICAL / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    d102 = json.loads((MECHANICAL / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    d86 = json.loads((MECHANICAL / "coaxiality_allocation.json").read_text(encoding="utf-8"))
    fl = json.loads((REPO / "tools/cad/cem/cathode_flange.json").read_text(encoding="utf-8"))
    ti = ALLOY_PROPERTIES[ALLOY_BASELINE]
    aw, ap, aa = s103.ALPHA_XYLEM_GREEN_1K, ALPHA_PEEK_1K, ti["alpha_1K"]
    l_sh = fl["shank_length_mm"]
    span = s55.PEEK_GAP_MM + l_sh
    gap = span - l_sh
    r_s, r_b = g77["sleeve_outer_radius_m"] * 1e3, g77["shank_radius_m"] * 1e3
    a_p = math.pi * (r_s ** 2 - r_b ** 2)
    a_sh = math.pi / 4 * (fl["shank_diameter_mm"] ** 2 - fl["bore_diameter_mm"] ** 2)
    ea_p = {"sway": E_PEEK_PA / 1e6 * a_p, "slow": E_PEEK_PA / 1e6 * PEEK_RELAX_FLOOR * a_p}
    ea_ti = ti["E_GPa"] * 1e3 * a_sh
    ea_c = {ld: ea_ti + v for ld, v in ea_p.items()}
    al_c = (ea_ti * aa + ea_p["slow"] * ap) / ea_c["slow"]
    assert z["shank"]["ti_section_mm2"] == pytest.approx(a_sh, abs=0.006)
    assert z["alpha_composite_ppm_K"] == pytest.approx(al_c * 1e6, abs=1e-4)
    assert z["composite_vs_102_gap_only_offset_ppm_K"] == pytest.approx((al_c - aa) * l_sh / gap * 1e6, abs=1e-4)

    def comp(d1, d2, ld):
        return max(0.0, min(d2, l_sh) - d1) / ea_c[ld] + max(0.0, d2 - max(d1, l_sh)) / ea_p[ld]

    def free(d1, d2):
        return max(0.0, min(d2, l_sh) - d1) * al_c + max(0.0, d2 - max(d1, l_sh)) * ap

    def cte(s):                                        # `102`'s gap-only convention: the shank's run at the Ti's CTE
        return (s - aa * l_sh) / gap * 1e6
    ks = {ld: 1 / comp(0.0, span, ld) for ld in ("sway", "slow")}
    assert z["stiffness_N_per_mm"]["sleeve_whole"] == pytest.approx(ks, abs=0.1)
    assert z["cte_free_sleeve_ppm_K"] == pytest.approx(cte(free(0.0, span)), abs=1e-4)
    ann = math.pi / 4 * (b78["bark"]["flange_diameter_mm"] ** 2 - (2 * r_s) ** 2)
    barks = {"thin_contact_78": b78["bark"]["thin_mm"], "thick_side_78": b78["bark"]["thick_mm"]}
    tie = {t: tv + b78["inputs"]["phloem_mm"] for t, tv in barks.items()}
    dvs = {k: v * 1e3 for k, v in d87["inputs"]["depth_span_m"].items()}
    dv_ceil, d_deep = max(dvs.values()), max(tie.values())
    assert min(tie.values()) < l_sh < d_deep        # the two install-day cambium readings sit either side of the shank's end
    kf_read = [ev * ann / tv for ev in s103.E_BARK_RADIAL_MPA.values() for tv in barks.values()]
    k_a = [2 * math.pi * math.sqrt(lr * rt) * g77["gyroid_length_m"] * 1e3 / ln
           for lr, rt in s103.G_PAIRS_MPA.values() for ln in s103.LN_R_OVER_R]
    bonds = {"anode_bond_stiff": max(k_a), "anode_bond_soft": min(k_a)}

    lock1 = json.loads((REPO / "tools/cad/cem/mechanical_lock.zone1.json").read_text(encoding="utf-8"))
    l_z1 = lock1["shank_length_mm"]
    ea1_ti = ti["E_GPa"] * 1e3 * math.pi / 4 * (lock1["shank_diameter_mm"] ** 2 - lock1["bore_diameter_mm"] ** 2)
    al_z1 = (ea1_ti * aa + ea_p["slow"] * ap) / (ea1_ti + ea_p["slow"])

    def w_a(dv, ax=aw):
        return ax * dv - al_z1 * l_z1 - aa * (dv - span - l_z1)

    def kc_of(kf, ka):
        return 0.0 if kf == 0 else 1 / (1 / ka + 1 / kf)

    def sh2(kf, ka):
        kc = kc_of(kf, ka)
        return kc / (kc + ks["sway"])

    def ae2(kf, ka, dv, ax=aw):
        kc, e0 = kc_of(kf, ka), free(0.0, span)
        return cte(e0 + (w_a(dv, ax) - e0) * kc / (kc + ks["slow"]))

    def seg(ka, dd, ld):
        return ka / (ka + 1 / comp(dd, span, ld))

    def sh3(ka, dd, dv, rigid_bark=False):
        return (dd / dv if rigid_bark else 0.0) + seg(ka, dd, "sway") * (dv - dd) / dv

    def ae3(ka, dd, dv, rigid_bark=False, ax=aw):
        e_lo = free(dd, span)
        upper = ax * dd if rigid_bark else free(0.0, dd)
        return cte(upper + e_lo + (w_a(dv, ax) - ax * dd - e_lo) * seg(ka, dd, "slow"))

    sh = z["share"]
    read2 = [sh2(kf, ka) for kf in kf_read for ka in k_a]
    assert (sh["state2_at_air_dry_readings"]["min"], sh["state2_at_air_dry_readings"]["max"]) == pytest.approx((min(read2), max(read2)), abs=1e-4)
    depths = [s103.DEPTH_MIN + (dd - s103.DEPTH_MIN) * i / 40 for dd in tie.values() for i in range(41)]
    for b, ka in bonds.items():
        assert sh["state2_cap_rigid_bark"][b] == pytest.approx(ka / (ka + ks["sway"]), abs=1e-4), b
        free3 = [sh3(ka, dd, dv) * dv / dv_ceil for dd in depths for dv in dvs.values()]
        got = sh["state3_no_bearing_any_depth_of_102_shift"][b]
        assert (got["min"], got["max"]) == pytest.approx((min(free3), max(free3)), abs=1e-4), b
        assert sh["state3_cap_rigid_bark_of_102_shift"][b] == pytest.approx(
            max(sh3(ka, dd, dv, True) * dv / dv_ceil for dd in depths for dv in dvs.values()), abs=2e-4), b

    # Ta's seam on `102`'s own closed form with `102`'s preload on the gap-only span
    geo = d102["geometry"]
    shipped = d86["by_geometry"][next(k for k in d86["by_geometry"] if k.startswith("shipped"))]["by_alloy"]
    amp86, off86 = d102["seam_86_inputs"]["amplitude_MPa"], d102["seam_86_inputs"]["offset_um"]
    grips = d102["grip"]["by_part_N_per_mm_at_20C"]["window_ceiling"]
    shift_hi = max(d102["sway_input"]["shift_um_87"]["upper_whisker"]) * 1e-3

    def seam(alloy, share, preload):
        row86 = shipped[alloy]
        mean86 = next(o["mean_MPa"] for o in row86["by_offset"] if o["offset_um"] == off86)
        pair = s103.s102.Pair(grips[max(grips, key=float)], ALLOY_PROPERTIES[alloy]["E_GPa"] * 1e3 * geo["wire_area_mm2"],
                              geo["liner_EA_N"], geo["bare_run_mm"], geo["liner_run_mm"], geo["wall_cap_N_23C"])
        c = pair.cycle(share * shift_hi, 0.0)
        f_amp, f_mean = c["F_amp"], c["F_mean"]
        if preload:
            f_mean = min(f_mean + d102["seam_by_alloy"][alloy]["hot_preload"]["zone3_fit_bonded_shank"]["F_N_relaxed_liner"], pair.cap - f_amp)
        return s103.s102.soderberg_k(amp86, mean86, f_amp, f_mean, geo["wire_area_mm2"], row86)

    def event(name, share, c):
        if name.startswith("share_"):
            return share - float(name.split("_")[1])
        if name.startswith("ta_k1_"):
            return seam("Ta", share, name.endswith("hot_preload")) - 1.0
        return float(name.split("_")[2]) - c
    thr_flip = d102["thermal"]["flip_vs_larger_margin_ppm_K"]
    names = {f"share_{r:g}" for r in s103.SHARE_ROWS} | {"ta_k1_sway_alone", "ta_k1_hot_preload"} | \
        {f"hot_flip_{x:g}" for x in thr_flip["hot_floor_part_zone3_fit_gap_only"]} | \
        {f"cold_flip_{x:g}" for x in thr_flip["cold_zone3_fit_gap_only"]}
    T2, T3 = z["state2_bearing_N_per_mm"], z["state3_tie_depth_mm_no_bearing"]
    assert set(T2) == names == set(T3)
    for name in names:
        for key, v2 in T2[name].items():
            dk, b = key.split("__")
            ka, dv = bonds[b], dvs[dk]

            def ev2(kf, ka=ka, dv=dv, name=name):
                return event(name, sh2(kf, ka) * dv / dv_ceil, ae2(kf, ka, dv))

            def ev3(dd, ka=ka, dv=dv, name=name):
                return event(name, sh3(ka, dd, dv) * dv / dv_ceil, ae3(ka, dd, dv))
            v3 = T3[name][key]
            if v2 is None:
                assert ev2(1e12) < 0, (name, key)
            elif v2 == 0.0:
                assert ev2(s103.KF_LO) >= 0, (name, key)
            else:
                assert abs(ev2(v2)) < 2e-3, (name, key, v2)
            if v3 is None:
                assert ev3(s103.DEPTH_MIN) < 0, (name, key)
            elif v3 == "deepest":
                assert ev3(d_deep) >= 0, (name, key)
            else:
                assert ev3(v3 - 1e-3) >= -2e-3 and ev3(v3 + 1e-3) <= 2e-3, (name, key, v3)

    def group(thr, name):
        return {f"{x}__{k}": v for x, vals in thr.items() if x == name or x.startswith(name + "_flip_") for k, v in vals.items()}
    for name, cell in z["readings"]["state2"].items():
        stiff = [v for k, v in group(T2, name).items() if k.endswith("anode_bond_stiff")]
        soft = [v for k, v in group(T2, name).items() if k.endswith("anode_bond_soft")]
        assert cell == {"no_below": None if None in stiff else min(stiff), "yes_above": None if None in soft else max(soft)}, name
    for name, cell in z["readings"]["state3"].items():
        dep = [v for k, v in group(T3, name).items() if k.endswith("anode_bond_stiff")]
        assert cell["reached_at_any_depth"] == ("deepest" in dep), name
    sv = z["seam_on_102_closed_form"]["Ta"]
    assert sv["state1"]["hot_preload"] == pytest.approx(seam("Ta", 0.0, True), abs=2e-4)
    for b, ka in bonds.items():
        least = sv["state3_least_any_depth_and_bearing"][b]
        for corner, pre in (("adverse_reversed", False), ("adverse_reversed_hot_preload", True)):
            assert least[corner] == pytest.approx(min(seam("Ta", sh3(ka, d_deep, dv) * dv / dv_ceil, pre) for dv in dvs.values()), abs=2e-4)

    # the heat: the CTE floor over the ends of every axis and the depth axis, against the sign change on the gap
    h = z["heat"]
    grid_d = [s103.DEPTH_MIN + (d_deep - s103.DEPTH_MIN) * i / 40 for i in range(41)]
    ctes = [ae2(kf, ka, dv) for kf in (0.0, 1e12) for ka in bonds.values() for dv in dvs.values()]
    ctes += [ae3(ka, dd, dv, rb) for rb in (False, True) for ka in bonds.values() for dd in grid_d for dv in dvs.values()]
    rev = aa * (s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM + s55.LINER_LENGTH_MM - s55.FLANGE_THK_MM - l_sh) / gap * 1e6
    floor = cte(min(w_a(dv) for dv in dvs.values()))
    assert (h["cte_min_ppm_K_over_the_model"], h["cte_travel_reverses_ppm_K_102"]) == pytest.approx((min(ctes), rev), abs=2e-3)
    assert h["wood_only_shortens_the_pad_travel"] == (min(ctes) > rev)
    assert h["cte_floor_span_follows_the_wood_ppm_K"] == pytest.approx(floor, abs=1e-5)
    assert h["reversed_shift_per_K_at_most_of_free_sleeve"] == pytest.approx((rev - floor) / (cte(free(0.0, span)) - rev), abs=1e-5)
    gd = h["deeper_tie_reaching_the_sign_change_mm_from_flange_seat"]
    assert d_deep < gd < span and ae3(bonds["anode_bond_stiff"], gd, dv_ceil, True) == pytest.approx(rev, abs=2e-3)
    assert h["thresholds_102_ppm_K"] == {"cold": thr_flip["cold_zone3_fit_gap_only"], "hot": thr_flip["hot_floor_part_zone3_fit_gap_only"]}
    ax_rev = h["xylem_cte_at_which_the_wood_reverses_the_travel_ppm_K"] * 1e-6        # lands on the sign change
    ctes_rev = [ae2(kf, ka, dv, ax_rev) for kf in (0.0, 1e12) for ka in bonds.values() for dv in dvs.values()]
    ctes_rev += [ae3(ka, dd, dv, rb, ax_rev) for rb in (False, True) for ka in bonds.values() for dd in grid_d for dv in dvs.values()]
    assert min(ctes_rev) == pytest.approx(rev, abs=2e-3)
    assert f"never falls below {math.floor(round(min(ctes) * 100, 9)) / 100:.2f} ppm/K" in z["verdict"]
    c = d["controls"]
    assert c["solver_vs_element_chain_max_miss_of_load_scale"] < 1e-8 and max(c["monotone_worst_step_zone3_fit"].values()) < 1e-8


def test_bus_torsion_budget_invariants():
    """101 (00_07 HW.26, the bus-twist leg): every cell against its closed form, recomputed HERE from `55`'s spans, the
    lib's alloy and PEEK constants and `55`'s and `77`'s caches — not from the script's own algebra.

    CAN catch: a wrong yield factor or a swapped criterion (each of the four angle cells is recomputed with σ_y/√3 and
    σ_y/2); an inverted or mis-sized liner share (the «liner_bonded» length is rebuilt from the liner's own GJ); a run,
    a span or a liner ID/OD that no longer matches `55`; a wire or tube yield torque off τ·J/r; a grip off μ·p·A·d/2 with
    `55`'s pressure and area, or a creep factor off PEEK_RELAX_FLOOR; a flip threshold off the tube's torque over the
    wire's Tresca torque per MPa; a wind rotation stale against `77` or taken at the centroid instead of the bark end,
    and its torque off the stiff bound; a margin, a knockdown or a flag that does not follow from those. CANNOT catch:
    a wrong pressure or factor INSIDE `55`'s or `77`'s cache (their own tests' domain), fracture beyond first yield, a
    drawn wire's or the weld HAZ's own yield, the capture's strength, a parallel tie, or whether an event slips the
    flange at all — the script's declared ceilings.
    """
    import importlib.util

    from lib.constants import (
        ALLOY_PROPERTIES,
        D_BUS_ROD_MM,
        E_PEEK_PA,
        NU_PEEK,
        PEEK_RELAX_FLOOR,
        SIGMA_YIELD_PEEK_PA,
    )
    d = json.loads((MECHANICAL / "bus_torsion_budget.json").read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location("s55_torsion", REPO / "tools/in_silico/scripts/55_bus_mechanical.py")
    s55 = importlib.util.module_from_spec(spec)
    sys.modules["s55_torsion"] = s55          # 55 declares dataclasses, which look their module up here
    spec.loader.exec_module(s55)
    dw, r = D_BUS_ROD_MM, D_BUS_ROD_MM / 2
    bare = s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM
    lin = s55.LINER_LENGTH_MM
    l_id = s55.LINER_BORE_SPECIFIED_MM
    l_od = l_id + 2 * s55.LINER_WALL_MM
    geo = d["geometry"]
    assert geo["run_mm"] == pytest.approx(s55.PEEK_GAP_MM + s55.BORE_DEPTH_MM, abs=1e-6), "the cache is stale against 55"
    assert (geo["bare_run_mm"], geo["liner_run_mm"]) == pytest.approx((bare, lin), abs=1e-6)
    assert (geo["liner_id_mm"], geo["liner_od_mm"]) == pytest.approx((l_id, l_od), abs=1e-5)
    j_w = math.pi / 32 * dw ** 4
    j_l = math.pi / 32 * (l_od ** 4 - l_id ** 4)
    gj_l = E_PEEK_PA / 1e6 / (2 * (1 + NU_PEEK)) * j_l
    k = {"von_mises": 1 / math.sqrt(3), "tresca": 0.5}

    h = d["holder"]
    tube = {c: kk * SIGMA_YIELD_PEEK_PA / 1e6 * j_l / (l_od / 2) for c, kk in k.items()}
    for c in k:
        assert h["liner_tube_first_yield_torque_Nmm"][c] == pytest.approx(tube[c], abs=0.006)
    win = json.loads((MECHANICAL / "bus_mechanical.json").read_text(encoding="utf-8"))["interference_window"]
    p_nom = win["per_um_radial_MPa"]["P_c"] * (dw - l_id) / 2 * 1e3
    normal = p_nom * win["cold_press_fit"]["contact_area_mm2"]
    assert h["grip_nominal_pressure_MPa"] == pytest.approx(p_nom, abs=6e-4)
    assert h["grip_normal_force_N"] == pytest.approx(normal, abs=0.06)
    grips = h["grip_torque_Nmm_by_mu"]
    assert grips["fit_floor_40C"] == 0.0
    for mu in win["axial_friction_lock"]["mu_sweep"]:
        assert grips["nominal_fit_20C"][f"{mu:g}"] == pytest.approx(mu * normal * r, abs=0.06)
        assert grips["creep_relaxed_fit"][f"{mu:g}"] == pytest.approx(mu * normal * r * PEEK_RELAX_FLOOR, abs=0.06)
    tube_hi = max(tube.values())
    assert h["tube_yields_below_grip_on_every_mu"] == {
        "nominal_fit": tube_hi < min(grips["nominal_fit_20C"].values()),
        "creep_relaxed_fit": tube_hi < min(grips["creep_relaxed_fit"].values())}
    flip = tube_hi / (0.5 * j_w / r)
    assert d["wire_yield_below_which_the_order_flips_MPa"] == pytest.approx(flip, abs=0.06)

    wb = json.loads((MECHANICAL / "anchor_torque_path.json").read_text(encoding="utf-8"))["wind_bracket"]
    wind = max(s["rotation_gyroid_vs_sleeve_rad"] for s in wb["species"]) * wb["bark_end_peak_factor"]["rigid_gyroid"]
    assert d["wind_bark_end"]["rotation_max_rad"] == pytest.approx(wind, rel=1e-9), "stale against 77, or not the bark end"

    wind_torques = []
    for alloy, row in d["by_alloy"].items():
        p = ALLOY_PROPERTIES[alloy]
        g = p["E_GPa"] * 1e3 / (2 * (1 + p["nu"]))
        share = g * j_w / (g * j_w + gj_l)
        lengths = {"top_clamped": bare + lin, "liner_bonded": bare + lin * share}
        wind_torques.append(wind * g * j_w / lengths["liner_bonded"])
        for c, kk in k.items():
            tau = kk * p["yield_MPa"]
            assert row["wire_yield_torque_Nmm"][c] == pytest.approx(tau * j_w / r, abs=0.006), (alloy, c)
            for run, length in lengths.items():
                assert row["theta_y_rad"][f"{c}__{run}"] == pytest.approx(tau * length / (g * r), abs=2e-6), (alloy, c, run)
        lo = min(row["theta_y_rad"].values())
        assert lo == row["theta_y_rad"]["tresca__liner_bonded"], alloy
        assert row["theta_y_deg_min"] == pytest.approx(math.degrees(lo), abs=1e-3)
        assert row["theta_y_deg_max"] == pytest.approx(math.degrees(row["theta_y_rad"]["von_mises__top_clamped"]), abs=1e-3)
        assert row["margin_over_wind_bark_end"] == pytest.approx(lo / wind, abs=0.06), alloy
        assert row["root_yield_knockdown_tolerated"] == pytest.approx(flip / p["yield_MPa"], abs=6e-4), alloy
        assert row["tube_yields_before_wire"] == (tube_hi < min(row["wire_yield_torque_Nmm"].values())), alloy
    assert d["wind_bark_end"]["torque_through_wire_max_Nmm"] == pytest.approx(max(wind_torques), abs=6e-5)
    assert d["findings"]["tube_yields_before_wire_on_every_alloy"] == all(
        row["tube_yields_before_wire"] for row in d["by_alloy"].values())


def test_electrode_interfacial_ph_invariants():
    """85 (00_07 HW.5.IS, the coin half of the ΔpH leg, 2026-10-12): invariants that hold whatever the constants move to.

    CAN catch: a control that stopped being recorded or holding (67's titration; Liu's FEM point and the single-D form
    bracketing it); a summary range that is not the min/max of its own rows; the media out of order (less buffer between
    5.75 and 6 than between 4.5 and 6, more with 10 mM malate — a sign, pH or totals swap would break it); the malate
    spent before the face reaches pH 6; the citrate-like end of the D bracket not below the succinate-like one; a film
    exponent that stops ordering f; an anode δ* that does not fall as current rises or is not larger at the farther pH
    edge, or that grows when protons per electron grow. CANNOT catch: whether the film is the right model for the
    laboratory's cell, malate's own D (not found — bracketed), or the pH inside the coatings; the script's declared ceilings.
    """
    d = json.loads((KINETICS / "electrode_interfacial_ph.json").read_text(encoding="utf-8"))
    assert d["checks"]["titration_vs_67"]["max_abs_dev_mol_l"] < 1e-9
    liu = d["checks"]["liu_fem_point"]
    assert liu["film_pH_centre"] and all(abs(v - liu["fem_pH_centre"]) <= liu["tolerance_pH"]
                                         for v in liu["film_pH_centre"].values())
    for i, (lo, hi) in liu["single_D_bracket_pH"].items():
        assert lo < liu["film_pH_centre"][i] < hi, i
    band = liu["passing_delta_over_radius"]
    assert band[0] < 1.0 < band[1]
    media = d["cathode"]["media"]
    assert set(media) == {"sap_pH4.5", "sap_pH5.75", "buffered_pH4.5"}
    rows = media["sap_pH4.5"]["row_table"]
    assert len(rows) == media["sap_pH4.5"]["rows"]
    assert {r["t_c"] for r in rows} == {20.0, 25.0} and {r["film"] for r in rows} == {"stagnant", "Levich", "transient"}
    for key in ("f_pH6", "f_malate_spent"):
        vals = [r[key] for r in rows]
        assert media["sap_pH4.5"][key] == [round(min(vals), 3), round(max(vals), 3)], key
    for r in rows:
        assert r["f_pH6"] < r["f_malate_spent"], r
        reached = r["face_pH_at_O2_limit"]
        assert (reached is None) == (r["f_malate_spent"] < 1.0), r
        if reached is not None:
            assert (reached < 6.0) == (r["f_pH6"] > 1.0), r
    assert media["sap_pH4.5"]["rows_crossing_pH6_below_O2_limit"] == sum(r["f_pH6"] < 1.0 for r in rows)
    for name, m in media.items():
        by = m["f_pH6_by_D_end"]
        assert by["citrate_like"][0] < by["succinate_like"][0] and by["citrate_like"][1] < by["succinate_like"][1], name
        # The docstring's claim, on every medium: f moves far less with the film exponent than with malate's D.
        film = m["f_pH6_by_film"]
        film_spread = max(abs(film[a][j] - film[b][j]) for a in film for b in film for j in (0, 1))
        d_spread = min(by["succinate_like"][j] - by["citrate_like"][j] for j in (0, 1))
        assert film_spread < d_spread, (name, film_spread, d_spread)
    # The film ORDER stagnant < Levich < transient is a property of the BUFFER-carried regime, not a law: f ∝ (D/D_O2)^p
    # per carrier, and for malate (D < D_O2) that ratio FALLS as p rises — stagnant p = 1 lowest, transient p = ½ highest;
    # free H⁺ (D > D_O2) moves the other way. On the revised sap (2026-10-18) at pH 4.5 malate is NOT spent at the crossing
    # (f_pH6 < f_malate_spent in every row, asserted above) — there is simply so little of it that free H⁺ carries most of
    # the supply, and there the order breaks. So the order is pinned where malate carries the protons, and the break is
    # tied to the cache's own share: it may break only where free H⁺ carries the majority.
    for name in ("buffered_pH4.5", "sap_pH5.75"):
        film = media[name]["f_pH6_by_film"]
        assert film["stagnant"][0] < film["Levich"][0] < film["transient"][0], name
    film = media["sap_pH4.5"]["f_pH6_by_film"]
    if not film["stagnant"][0] < film["Levich"][0] < film["transient"][0]:
        assert d["cathode"]["free_H_share_of_supply_sap_pH4.5_low_D"] > 0.5, "film order broke without free H⁺ carrying most"
    assert media["sap_pH5.75"]["f_pH6"][1] < media["sap_pH4.5"]["f_pH6"][0] < media["buffered_pH4.5"]["f_pH6"][0]
    ds = d["anode"]["delta_star"]
    for edge in ds.values():
        by_j = sorted(edge.values(), key=lambda v: v["j_uA_cm2"])
        assert all(a["delta_star_um"][0] > b["delta_star_um"][0] for a, b in itertools.pairwise(by_j)), "δ* must fall with j"
        for v in edge.values():
            assert v["delta_star_um_n1"][0] >= v["delta_star_um"][0] and v["delta_star_um_n1"][1] == v["delta_star_um"][1]
    for run in ds["face_pH_4.5"]:
        assert ds["face_pH_4.5"][run]["delta_star_um"][0] > ds["face_pH_5.5"][run]["delta_star_um"][0], run
    chk = d["anode_check_medium"]
    assert chk["capacity_gain_to_pH_4.5"] > 1.0 and chk["ionic_strength_mol_l"][1] > chk["ionic_strength_mol_l"][0]


def test_electrode_interfacial_ph_anchor_anode():
    """85's anchor anode with stagnant sap in its gap (2026-10-17), per Zone-1 SKU, against its own cold-start draw.

    CAN catch: a SKU missing (every non-golden Zone-1 manifest must be there); a geometry not re-derivable from the CEMs
    (the gyroid's envelope; the bore = the Zone-2 sleeve's OD; the exposed lattice); a film that is not the annulus' exact
    r_a·ln(r_b/r_a) (a planar «δ = gap» would read ≈ 17 % thicker on pine); a current bracket that is not the envelope
    density × the envelope at its low end and × (envelope + bottom cap) at its high end; an edge order broken (the
    stability edge must need MORE current than the kinetic one, at both ends); the n_H = 1 range not inside the full one at
    its high end; a cold-start draw that is not P_IN(CS)/V_IN(CS) from lib (typ and the MAX column) — the coin letter's
    load point B was the yardstick before 2026-10-17, and the anchor's own draw is what its BQ25570 needs; a «below» flag
    that is not its own comparison. CANNOT catch: which gap state a living stem keeps, the pH inside the lattice, the wood
    wall's resistance, or migration, flow and CO₂ (each named in the docstring with its side).
    """
    from lib.constants import BQ25570_PIN_CS_UW, BQ25570_VIN_CS_MAX_MV, BQ25570_VIN_CS_TYP_MV

    d = json.loads((KINETICS / "electrode_interfacial_ph.json").read_text(encoding="utf-8"))
    a = d["anchor_anode_sap_gap"]
    assert set(a["states"]) == {"sap_gap", "air_gap", "ingrown"}
    cs = {"typ": BQ25570_PIN_CS_UW / BQ25570_VIN_CS_TYP_MV * 1e3, "worst": BQ25570_PIN_CS_UW / BQ25570_VIN_CS_MAX_MV * 1e3}
    assert all(abs(a["cold_start_uA"][k] - v) <= 0.05 for k, v in cs.items()) and cs["worst"] < cs["typ"]
    cem = REPO / "tools/cad/cem"
    skus = sorted(p for p in cem.glob("anchor_zone1.*.json") if not p.name.endswith(".golden.json"))
    sl = json.loads((cem / "zone2_sleeve.json").read_text(encoding="utf-8"))
    r_b = (sl["bore_diameter_mm"] / 2.0 + sl["wall_thickness_mm"]) / 10.0
    assert len(skus) == len(a["by_sku"])
    # each part in its own sap (⚖️ 2026-10-18): broadleaf and oak in 67's beech point Q8 at its pH, the rest in the pine point
    q8 = json.loads((CACHE / "chemistry" / "sap_recipe_saturation.json").read_text(encoding="utf-8"))["q8_broadleaf_point"]
    beech = {"anchor_zone1_broadleaf", "anchor_zone1_oak"}
    for name, per in a["by_sku"].items():
        assert per["sap"] == ("beech_q8" if name in beech else "pine"), name
        assert per["bulk_pH"] == (q8["conditions"]["setpoint"]["ph"] if name in beech else 5.75), name
        assert ("summer_acid_dates" in per) == (name in beech), name
        assert ("own_sap_reading" in per) == (name == "anchor_zone1_oak"), name
        if name == "anchor_zone1_oak":
            own = per["own_sap_reading"]
            assert own["bulk_pH"] == q8["oak_own_sap_reading"]["ph_range"]
            assert own["below_kinetic_edge"] == (own["bulk_pH"][1] < 5.5)
            assert own["minus_stability_edge"] == [round(x - 4.5, 2) for x in own["bulk_pH"]]
        if name in beech:
            acid = per["summer_acid_dates"]
            assert acid["ph_medians"] == q8["summer_acid_dates"]["ph_medians"], name
            assert acid["medians_below_kinetic_edge"] == all(x < 5.5 for x in acid["ph_medians"]), name
            assert acid["medians_minus_stability_edge"] == [round(min(acid["ph_medians"]) - 4.5, 2),
                                                            round(max(acid["ph_medians"]) - 4.5, 2)], name
    for path in skus:
        z1 = json.loads(path.read_text(encoding="utf-8"))
        per = a["by_sku"][z1["name"]]
        g = per["geometry"]
        r_a, length = z1["outer_diameter_mm"] / 20.0, z1["length_mm"] / 10.0
        assert abs(g["anode_radius_cm"] - r_a) < 1e-12 and abs(g["bore_radius_cm"] - r_b) < 1e-12, path.name
        assert abs(g["annulus_delta_cm"] - r_a * math.log(r_b / r_a)) < 1e-12, path.name
        assert abs(g["envelope_lateral_area_cm2"] - 2.0 * math.pi * r_a * length) < 1e-9, path.name
        assert abs(g["bottom_cap_over_envelope"] - r_a / (2.0 * length)) < 1e-12, path.name
        e55, e45 = per["face_pH_5.5"], per["face_pH_4.5"]
        for i in (0, 1):
            assert e55["i_anode_uA"][i] < e45["i_anode_uA"][i], path.name
        for e in (e55, e45):
            lo = e["j_envelope_uA_cm2"][0] * g["envelope_lateral_area_cm2"]
            hi = e["j_envelope_uA_cm2"][1] * g["envelope_lateral_area_cm2"] * (1.0 + g["bottom_cap_over_envelope"])
            assert abs(e["i_anode_uA"][0] - lo) <= 0.1 + 0.01 * lo and abs(e["i_anode_uA"][1] - hi) <= 0.1 + 0.01 * hi
            assert e["i_anode_uA_n1"][1] == e["i_anode_uA"][1] and e["i_anode_uA_n1"][0] >= e["i_anode_uA"][0]
            for k, v in e["crossed_below_cold_start"].items():
                assert v == {"in_every_reading": e["i_anode_uA"][1] < cs[k], "in_some_reading": e["i_anode_uA"][0] < cs[k]}


def test_cathode_ionic_path_literature_points_follow_from_the_readings():
    """84's literature points: each element resistance is the reading × the element's factor at the stated geometry end,
    and the Scots-pine floor is the sum of the lenient ends; the cells that «hold it» are exactly the open budgets ≥ it.
    CAN catch: a point retyped by hand or computed from another factor. CANNOT catch: a misread source — the
    transcriptions are pinned to their pages in the script, not here."""
    d = json.loads((REPO / "tools/in_silico/cache/kinetics/cathode_ionic_path.json").read_text())
    f, pts = d["factors"], d["literature_points"]
    g1 = f["1_sapwood_per_m"]["bracket"]
    for p in pts[:2]:
        assert p["element_ohm"] == [p["values"][0] * g1[0], p["values"][1] * g1[1]], p["source"]
    (ec,) = [p for p in pts if p["quantity"] == "EC_uS_per_cm"]
    film = (0.041e-3, 0.128e-3)
    rho = [1e4 / v for v in ec["values"]]
    assert ec["element_ohm"] == [min(rho) / max(film) * min(f["4_film_per_sq"]), max(rho) / min(film) * max(f["4_film_per_sq"])]
    floor = sum(min(p["element_ohm"]) for p in pts if p["species"] == "Pinus sylvestris")
    assert d["scots_pine_sapwood_plus_film_lenient_ohm"] == floor
    req = d["requirements_alone_at_lenient_geometry"]
    assert d["open_budget_cells_that_hold_it"] == sorted(k for k, v in req.items() if v["budget_ohm"] >= floor)
    for p in pts:   # counted, never «most» by eye
        assert p["open_cells_exceeded"] == {end: sorted(k for k, v in req.items() if v["budget_ohm"] < p["element_ohm"][i])
                                            for i, end in enumerate(("lenient", "adverse"))}, p["source"]


def test_printed_part_sway_stress_invariants():
    """105 (00_07 HW.23, the printed-part sway-stress leg): every cell recomputed HERE from the CEMs, the voxel-FE cache,
    `87`'s, `102`'s, `103`'s and `52`'s caches, the lib's alloys and `55`'s markers — not from the script's algebra; the
    disc by an independent finite-difference solve of the plate, at the shank root and across the groove.

    CAN catch: a stale FEA row, a reading that is not the adverse end of 105's [finest unlocked ⊥ finest locked] bracket
    (re-read through 105's own `read_fe`, ONE home), a wrong solid fraction, an RMS factor off √(ratio/φ); a binds-above
    threshold off ε_e/(SF·f·r/R) (× √(3+2ν) on the any-state reading) or rounded DOWN; a depth fraction off the CEM depth,
    the host radius or `103`'s bark; a source-day flag that does not follow; a force off `103`'s closed forms (state 2
    k_s·k_A/(k_A+k_s), state 3 series(k_A, k_lower)·(1−d/dv) over `103`'s grid, the rigid-sleeve k_A) or off `102`'s
    adverse shift; a section, a barb width or formula that no longer matches the CEM; a disc stress per newton, a groove
    stress taken on the hoop moment instead of the radial one, a groove thickness; a Soderberg SF, K_f or mean off `86`'s
    form on any of the three cycle readings or on the wrong route's endurance; a junction or mass-path number; a verdict
    list of alloys that disagrees with the flags. CANNOT catch: the plate MODEL itself (both solves are Kirchhoff), the
    energy bound's premises (Hill on a ≈2-cell part, E_z* against the FE readings), k_p, t_L, any K_t, the static means —
    the script's declared ceilings.
    """
    import importlib.util

    from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, DBH_MIN_CM, E_PEEK_PA

    d = json.loads((MECHANICAL / "printed_part_sway_stress.json").read_text(encoding="utf-8"))
    d87 = json.loads((MECHANICAL / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    d102 = json.loads((MECHANICAL / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    d103 = json.loads((MECHANICAL / "anchor_wood_share.json").read_text(encoding="utf-8"))
    d52 = json.loads((MECHANICAL / "z_stack_tolerance.json").read_text(encoding="utf-8"))
    fea = json.loads((REPO / "tools/cad/cache/fea/anchor_zone1_pine.json").read_text(encoding="utf-8"))
    cem = REPO / "tools/cad/cem"
    lock1 = json.loads((cem / "mechanical_lock.zone1.json").read_text(encoding="utf-8"))
    flange = json.loads((cem / "cathode_flange.json").read_text(encoding="utf-8"))
    sleeve = json.loads((cem / "zone2_sleeve.json").read_text(encoding="utf-8"))
    pine = json.loads((cem / "anchor_zone1.pine.json").read_text(encoding="utf-8"))
    spec = importlib.util.spec_from_file_location("s55_105", REPO / "tools/in_silico/scripts/55_bus_mechanical.py")
    s55 = importlib.util.module_from_spec(spec)
    sys.modules["s55_105"] = s55
    spec.loader.exec_module(s55)
    spec105 = importlib.util.spec_from_file_location("s105_t", REPO / "tools/in_silico/scripts/105_printed_part_sway_stress.py")
    s105 = importlib.util.module_from_spec(spec105)
    sys.modules["s105_t"] = s105
    spec105.loader.exec_module(s105)
    inp = d["inputs"]
    g = d103["geometry"]

    # the gyroid's energy bound — the readings re-read through 105's own rule from the same caches (ONE home), and the
    # rule itself checked here: per axis the LOWER of the finest unlocked and the finest locked row, φ the finest
    # unlocked row's own
    fe = s105.read_fe()
    assert inp["fe_readings"] == pytest.approx(fe["readings"], abs=1e-12)
    for ax in ("radial", "axial"):
        br = inp["fe_bracket"][ax]
        assert br == pytest.approx(fe["bracket"][ax]) if isinstance(fe["bracket"][ax], float) else \
            all(br[k] == pytest.approx(fe["bracket"][ax][k], abs=1e-12) for k in ("unlocked", "locked", "unlocked_step_mm", "locked_step_mm"))
        assert inp["fe_readings"][f"{ax}_reading"] == pytest.approx(min(br["unlocked"], br["locked"]), abs=1e-12)
        assert br["adverse"] == ("unlocked" if br["unlocked"] <= br["locked"] else "locked")
        # both ends are the FINEST of their class over the merged ladder
        assert br["unlocked_step_mm"] == min(r["step_mm"] for r in inp["fe_ladder"] if not r["locked"])
        assert br["locked_step_mm"] == min(r["step_mm"] for r in inp["fe_ladder"] if r["locked"])
    rim = pine["gyroid_period_rim_mm"]
    for r in inp["fe_ladder"]:
        # the flag follows the ONE home of the lock rule (105's mirror of VoxelFea.RepeatCells) …
        assert r["locked"] == (s105.axial_lock_cells(r["step_mm"], rim) > 0), f"ladder row {r['step_mm']} mm: the lock flag does not follow the axial period"
        # … and, independently of that rule's tolerance, the ladder's structure: a locked row is a period/N step at
        # float32 precision, an unlocked one a diameter step 11/(2k) with k not a multiple of 11 (picogk gotcha #16)
        if r["locked"]:
            assert abs(rim / round(rim / r["step_mm"]) - r["step_mm"]) < 5e-7, f"{r['step_mm']} mm is flagged locked but is not period/N"
        else:
            k = round(11 / (2 * r["step_mm"]))
            assert abs(11 / (2 * k) - r["step_mm"]) < 5e-7 and k % 11, f"{r['step_mm']} mm is flagged unlocked but is not 11/(2k) with 11 ∤ k"
    assert not fe["finest_unlocked"]["locked"] and fe["finest_locked"]["locked"]
    # the cached ladder IS the re-read one, row for row (a hand-edited cache row would otherwise pass every check above)
    keys = ("step_mm", "locked", "axial_ratio", "radial_ratio", "porosity", "source")
    assert inp["fe_ladder"] == [{k: r[k] for k in keys} for r in fe["ladder"]]
    assert all(r["step_mm"] >= fe["finest_unlocked"]["step_mm"] for r in fe["ladder"] if not r["locked"])
    assert all(r["step_mm"] >= fe["finest_locked"]["step_mm"] for r in fe["ladder"] if r["locked"])
    phi = 1 - fe["finest_unlocked"]["porosity"]
    f = {k: math.sqrt(v / phi) for k, v in fe["readings"].items()}
    assert inp["solid_fraction"] == pytest.approx(phi, abs=1e-12)
    assert inp["rms_factor_by_reading"] == pytest.approx(f, abs=1e-12)
    div = {"near_uniaxial": 1.0, "any_state": math.sqrt(3 + 2 * fea["poisson_ratio"])}
    r_host = DBH_MIN_CM * 10 / 2
    r_g = r_host - (g["shift_span_mm_87"]["ceiling_full_depth_77"] - g["anode_length_mm"])
    frac = {"dbh_min_sensor_on_bark": r_g / r_host, "large_stem_limit": 1.0}
    for side, bark in g["bark_mm_78"].items():
        frac[f"dbh_min_sensor_on_xylem_{side}"] = r_g / (r_host - bark - g["phloem_mm_78"])
    assert inp["depth_fraction"] == pytest.approx(frac, abs=1e-12)
    for al, p in ALLOY_PROPERTIES.items():
        se = s55.ENDURANCE_OVER_YIELD * s55.AS_PRINTED_DERATE * p["yield_MPa"]
        assert d["alloys"][al]["endurance_printed_MPa"] == pytest.approx(se, rel=1e-12), al
        assert d["alloys"][al]["endurance_wrought_MPa"] == pytest.approx(se / s55.AS_PRINTED_DERATE * s55.WROUGHT_DERATE, rel=1e-12)
        eps_e = se / (p["E_GPa"] * 1e3) * 1e6
        for dk, fr in frac.items():
            for sk, dv_ in div.items():
                for sf in (1.0, 2.0):
                    cell = d["gyroid_binds_above_surface_strain_ue"][al][f"{dk}|{sk}|sf{sf:g}"]
                    for fk, fv in f.items():
                        exact = eps_e / sf * dv_ / (fv * fr)
                        assert exact - 1e-6 <= cell[fk] < exact + 1, (al, dk, sk, sf, fk)   # rounded UP
    for rd in ("median", "upper_whisker"):
        eps = d87["by_slope_reading"][rd]["stem_at_anchor_h_le_2m"]["surface_strain_microstrain_source_tree"]
        for al in ALLOY_PROPERTIES:
            for k, v in d["gyroid_source_day_exceeds"][rd][al].items():
                for fk, flag in v.items():
                    assert flag == (eps > d["gyroid_binds_above_surface_strain_ue"][al][k][fk])

    # the forces — 103's closed forms over 103's grid, 102's adverse shift
    span = g["span_mm"]
    a_sl = math.pi / 4 * ((sleeve["bore_diameter_mm"] + 2 * sleeve["wall_thickness_mm"]) ** 2 - sleeve["bore_diameter_mm"] ** 2)
    ea_p = E_PEEK_PA / 1e6 * a_sl
    z3 = d103["zone3_fit"]
    l_run = z3["sections_mm"]["composite_run"][1]
    ea_c = z3["stiffness_N_per_mm"]["composite_run"]["sway"] * l_run
    comp = {"a_flange_on_bark": lambda a, b: (b - a) / ea_p,
            "b_zone3_fit": lambda a, b: max(0, min(b, l_run) - max(a, 0)) / ea_c + max(0, min(b, span) - max(a, l_run)) / ea_p}
    ka = d103["stiffness_N_per_mm"]["anode_bond"]
    bonds = {"anode_bond_stiff": max(ka.values()), "anode_bond_soft": min(ka.values())}
    dvs = list(g["shift_span_mm_87"].values())
    ties = list(g["flange_seat_to_install_day_cambium_mm"].values())
    grid = sorted({0.5 + (t - 0.5) * i / 40 for t in ties for i in range(41)})
    for pn, cf in comp.items():
        ks = 1 / cf(0, span)
        for bn, k in bonds.items():
            fz = d["forces_N_per_mm_of_shift"][pn][bn]
            assert fz["state2_rigid_bark_per_mm"] == pytest.approx(ks * k / (k + ks), rel=1e-9)
            fa = max(1 / (1 / k + cf(dd, span)) * (1 - dd / dv) * dv / max(dvs) for dd in grid for dv in dvs)
            assert fz["state3_bond_per_mm_max_over_ties"] == pytest.approx(fa, rel=1e-9)
            assert fz["rigid_sleeve_bond_per_mm"] == k
    shift = {rd: d102["sway_input"]["shift_um_87"][rd][1] * 1e-3 for rd in ("median", "upper_whisker")}

    # the solid members and the disc (an independent FD plate)
    def barb_s(F, c):
        h = c["barb_height_mm"]
        w = h / math.tan(math.radians(c["lead_angle_deg"])) + h / math.tan(math.radians(c["trail_angle_deg"]))
        return 6 * F / c["barb_rows"] / (math.pi * c["shank_diameter_mm"]) * h / w ** 2

    def check(a, sig, al, se):
        sy = ALLOY_PROPERTIES[al]["yield_MPa"]
        for cyc, (sa, sm) in (("one_sided", (sig / 2, sig / 2)), ("reversed", (sig, 0.0)), ("on_preload", (sig, sig))):
            sf = 1 / (sa / se + sm / sy)
            assert (a[cyc]["sf_at_kf1"], a[cyc]["kf_at_sf2"]) == pytest.approx((sf, sf / 2), rel=1e-9), (cyc, al)
        room = 0.5 - sig / se
        assert (a["mean_at_sf2_MPa"] is None) == (room <= 0)
        if room > 0:
            assert a["mean_at_sf2_MPa"] == pytest.approx(sy * room, rel=1e-9)

    a1 = math.pi / 4 * lock1["shank_diameter_mm"] ** 2
    a1g = math.pi / 4 * (lock1["shank_diameter_mm"] - 2 * lock1["groove_depth_mm"]) ** 2
    kinds = {"state2_rigid_bark": "state2_rigid_bark_per_mm", "state3_rigid_tie_max": "state3_bond_per_mm_max_over_ties",
             "rigid_sleeve": "rigid_sleeve_bond_per_mm"}
    for key, cell in d["zone1_members"].items():
        pn, bn, kind, rd = key.split("|")
        F = d["forces_N_per_mm_of_shift"][pn][bn][kinds[kind]] * shift[rd]
        assert cell["force_N"] == pytest.approx(F, rel=1e-9)
        for m, sig in (("zone1_shank", F / a1), ("zone1_groove_root", F / a1g), ("zone1_barb_root_bending", barb_s(F, lock1))):
            assert cell["members"][m]["sigma_n_MPa"] == pytest.approx(sig, rel=1e-9)
            for al in ALLOY_PROPERTIES:
                check(cell["members"][m]["printed"][al], sig, al, d["alloys"][al]["endurance_printed_MPa"])

    gl = d52["applied_gland"]
    b, a, c, t = flange["shank_diameter_mm"] / 2, flange["flange_diameter_mm"] / 2, g["channel_radius_mm"], flange["flange_thickness_mm"]
    rs = sleeve["bore_diameter_mm"] / 2
    tg = t - gl["flange_groove_depth_mm"]
    nu, n = fea["poisson_ratio"], 6000
    r = np.linspace(b, a, n + 1)
    h_ = r[1] - r[0]

    def frac_in(lo, hi):
        if hi - lo < 1e-12:
            return (r >= lo).astype(float)
        return np.clip((r * r - lo * lo) / (hi * hi - lo * lo), 0, 1)

    cases = {"b_pull_at_shank|uniform_over_bark_annulus": ((b, b), (c, a)), "b_pull_at_shank|rim_only_dished_seat": ((b, b), (a, a)),
             "b_pull_at_shank|channel_edge_only": ((b, b), (c, c)), "a_sleeve_face_press|uniform_over_bark_annulus": ((rs, c), (c, a)),
             "a_sleeve_face_press|rim_only_dished_seat": ((rs, c), (a, a))}
    assert set(d["disc_MPa_per_N"]) == set(cases)
    gr = (r >= gl["flange_groove_r_mm"][0]) & (r <= gl["flange_groove_r_mm"][1])
    for name, (ld, rc) in cases.items():
        rhs = (frac_in(*ld) - frac_in(*rc)) / (2 * math.pi * r)
        m = np.zeros((n + 1, n + 1))
        m[0, 0], rhs[0] = 1, 0
        idx = np.arange(1, n)
        m[idx, idx - 1] = 1 / h_ ** 2 - 1 / (2 * h_ * r[idx])
        m[idx, idx] = -2 / h_ ** 2 - 1 / r[idx] ** 2
        m[idx, idx + 1] = 1 / h_ ** 2 + 1 / (2 * h_ * r[idx])
        m[n, n], m[n, n - 1], m[n, n - 2], rhs[n] = 3 / (2 * h_) + nu / a, -2 / h_, 1 / (2 * h_), 0
        ph = np.linalg.solve(m, rhs)
        dph = np.gradient(ph, h_, edge_order=2)
        m_r, m_t = dph + nu * ph / r, ph / r + nu * dph
        got = d["disc_MPa_per_N"][name]
        assert got["shank_root_MPa_per_N"] == pytest.approx(6 * max(abs(m_r[0]), abs(m_t[0])) / t ** 2, rel=2e-3), name
        assert got["groove_radial_MPa_per_N"] == pytest.approx(6 * abs(m_r[gr]).max() / tg ** 2, rel=2e-3), name
        assert got["groove_hoop_plate_MPa_per_N"] == pytest.approx(6 * abs(m_t[gr]).max() / t ** 2, rel=2e-3), name
    a3 = z3["shank"]["ti_section_mm2"]
    for key, cell in d["zone3_members"].items():
        pn, bn, kind, rd = key.split("|")
        per = (d["forces_N_per_mm_of_shift"][pn][bn]["state2_rigid_bark_per_mm"] if kind == "state2_rigid_bark"
               else d["forces_N_per_mm_of_shift"][pn]["air_dry_bark_max_per_mm"])
        F = per * shift[rd]
        assert cell["force_N"] == pytest.approx(F, rel=1e-9)
        expect = {}
        if pn == "b_zone3_fit":
            expect = {"zone3_shank": F / a3, "zone3_barb_root_bending": barb_s(F, flange)}
        for name, v in d["disc_MPa_per_N"].items():
            if name.startswith(pn[0] + "_"):
                expect[f"disc_shank_root|{name}"] = v["shank_root_MPa_per_N"] * F
                expect[f"disc_groove|{name}"] = v["groove_radial_MPa_per_N"] * F
        assert set(cell["members"]) == set(expect), key
        for mname, sig in expect.items():
            mem = cell["members"][mname]
            assert mem["sigma_n_MPa"] == pytest.approx(sig, rel=1e-9)
            check(mem["printed"], sig, ALLOY_BASELINE, d["alloys"][ALLOY_BASELINE]["endurance_printed_MPa"])
            check(mem["cnc_wrought"], sig, ALLOY_BASELINE, d["alloys"][ALLOY_BASELINE]["endurance_wrought_MPa"])

    # the junction, the axial term and the mass path
    fr_b = frac["dbh_min_sensor_on_bark"]
    assert d["junction"]["layer_over_wood_strain"] == pytest.approx(lock1["shank_diameter_mm"] / 2 / pine["gyroid_period_rim_mm"], rel=1e-12)
    fa = d["forces_N_per_mm_of_shift"]["b_zone3_fit"]["anode_bond_stiff"]["state3_bond_per_mm_max_over_ties"] * shift["upper_whisker"]
    axial_hi = max(fe["bracket"]["axial"]["unlocked"], fe["bracket"]["axial"]["locked"])   # 105's conservative end for a force
    for al in ALLOY_PROPERTIES:
        rms = fa / a1 * math.sqrt(1 / (axial_hi * phi))
        got = d["gyroid_axial_term_mature_stiff_bond_upper"]["by_alloy"][al]
        assert got["rms_MPa"] == pytest.approx(rms, rel=1e-12)
        assert got["over_sf2_line"] == pytest.approx(rms / (d["alloys"][al]["endurance_printed_MPa"] / 2), rel=1e-12)
    for rd in ("median", "upper_whisker"):
        eps = d87["by_slope_reading"][rd]["stem_at_anchor_h_le_2m"]["surface_strain_microstrain_source_tree"]
        assert d["junction"]["mismatch_um_at_tL1_sensor_on_bark"][rd] == pytest.approx(eps * fr_b * lock1["shank_diameter_mm"] / 2 * 1e-3, rel=1e-12)
        acc = d87["by_slope_reading"][rd]["stem_at_anchor_h_le_2m"]["accel_m_s2"]
        mom = d87["inputs"]["mass_ceiling_g"] / 1e3 * (9.80665 + acc) * d87["inputs"]["capsule_envelope_mm"][1]
        dd, bo = flange["shank_diameter_mm"], flange["bore_diameter_mm"]
        assert d["mass_path"][rd]["zone3_shank_bending_MPa"] == pytest.approx(mom * 32 * dd / (math.pi * (dd ** 4 - bo ** 4)), rel=1e-12)

    # the verdict's alloy lists are the flags, not a hand-typed list; its mass-path bound is an upper bound
    up = d["gyroid_source_day_exceeds"]["upper_whisker"]
    # the lower reading is READ, never assumed — HW.33 (в) moved it from the radial to the axial one, the HW.23 re-sweep back
    low = min(inp["fe_readings"], key=inp["fe_readings"].get)
    assert inp["fe_reading_lower"] == low
    lo = ", ".join(sorted(al for al in ALLOY_PROPERTIES if up[al]["large_stem_limit|near_uniaxial|sf2"][low]))
    assert f"On the lower reading (the {low.split('_')[0]} one)" in d["verdict"]
    assert f"exceeds them for {lo} on the lower reading" in d["verdict"]
    mmax = max(v["zone3_shank_bending_MPa"] for v in d["mass_path"].values())
    bound = float(re.search(r"mass path stays below ([0-9.]+) MPa", d["verdict"]).group(1))
    assert mmax < bound




def test_gyroid_interface_contact_map_invariants():
    """108 (00_07 HW.23, the leg on 106's bonded interface, step 1): the validity map rebuilt HERE by another ARITHMETIC,
    on BOTH of 106's wood groups (Scots pine ⊥ green Pinaceae). σᴵ of every θ = 0 cell is recomputed through 4th-order
    tensors — Mura's integral by Gauss–Legendre on [0, π], the wood's compliance inverted 9×9, the lattice's cubic tensor
    on its cube axes, the inclusion solved 9×9 (108 runs 106's Mandel 6×6 machinery). The traction is then projected BY
    HAND on a ψ grid from the CACHED σᴵ — no Mohr circle, no tangent formula — and every per-cell number is read off that
    grid by brute force. SHARED with the script, so not independent: the wood sets (106's transcriptions) and the
    stiff/soft/mean rule, the model (an infinite bonded cylinder, the pore readings), the strains (105's cache) and the
    p₀ readings (the script's transcription of Bruder 1998, held here only to the number inside its own quoted phrase).

    The STALENESS half (the 2026-10-22 review's CI blind spot): 108 records a sha256 of every 106, 105 and CEM field it
    read; this test recomputes all three from the CURRENT inputs, holds every θ = 0 share to 106's current cell, and reds
    when 106 carries a group or a cell block 108 does not map.

    CAN catch: a 108 cache left stale by a 106 or 105 re-run (any field it reads); a 106 group 108 does not read; a σᴵ
    off the Eshelby solution (a dropped Mandel √2, a wrong per-unit-strain scale, another cell's tensor, another group's
    wood); a projection or sign error; an opening, open share or friction that does not follow from the traction; a
    reading whose number is not the one in its quote, or the excluded 2.5 MPa back among the readings; a strain off 105's
    cache; a group bracket — over all cells or over the bare lattice — that does not follow from its cells; a binding
    threshold other than 106's consumer block's, or a binding cell other than the one its reading names; the published-
    sets junction companion off 106's; the 2.5 MPa price and the homogenisation margin off the cells; the off-axis Zener
    threshold off σ₁ at the angle that sets it; the junction's isotropy; a verdict whose numbers or quantifiers are not the
    cells', or a holding or direction claim the 2026-10-22 reviews removed. CANNOT catch: the MODEL and the readings named above — the script's ceilings; the
    homogenisation (its direction is an argument, and it holds only for a smooth envelope); the compression half over the
    grid and the grid extremes off θ = 0 other than the one threshold recomputed here.
    """
    import importlib.util

    from lib.constants import ALLOY_PROPERTIES

    def load(name, file):
        spec = importlib.util.spec_from_file_location(name, REPO / "tools/in_silico/scripts" / file)
        mod = importlib.util.module_from_spec(spec)
        sys.modules[name] = mod
        spec.loader.exec_module(mod)
        return mod

    s106 = load("s106_t108", "106_gyroid_wood_strain_share.py")
    s108 = load("s108_t108", "108_gyroid_interface_contact_map.py")
    d = json.loads((MECHANICAL / "gyroid_interface_contact_map.json").read_text(encoding="utf-8"))
    d106 = json.loads((MECHANICAL / "gyroid_wood_strain_share.json").read_text(encoding="utf-8"))
    d105 = json.loads((MECHANICAL / "printed_part_sway_stress.json").read_text(encoding="utf-8"))

    # ── staleness: the fingerprints of what 108 read, recomputed from the CURRENT upstream caches ──
    fp = d["inputs"]["upstream_fingerprint"]
    assert fp["106"]["fields"] == list(s108.CONSUMED_106) and fp["105"]["fields"] == list(s108.CONSUMED_105), \
        "108's consumed-field list moved — re-run 108"
    assert fp["106"]["sha256"] == s108.fingerprint(d106, s108.CONSUMED_106), "106's cache moved since 108 ran — re-run 108"
    assert fp["105"]["sha256"] == s108.fingerprint(d105, s108.CONSUMED_105), "105's cache moved since 108 ran — re-run 108"
    cem = json.loads((REPO / fp["cem_anode"]["file"]).read_text(encoding="utf-8"))
    assert fp["cem_anode"]["fields"] == list(s108.CONSUMED_CEM)
    assert fp["cem_anode"]["sha256"] == s108.fingerprint(cem, s108.CONSUMED_CEM), "the anode CEM moved since 108 ran"
    assert s108.control_groups_read(d106) == [] and d["controls"]["groups_unread"] == [], \
        "106 carries a group or a cell block 108 does not read — extend 108"
    groups = {"scots_pine": ("cells", "wood_readings"), "green": ("green_cells", "green_wood_readings")}
    assert dict(s108.GROUPS_READ) == groups
    for g, (blk, _) in groups.items():
        assert set(d[blk]) == set(d106[blk]), f"108's {g} cells are not 106's — re-run 108"
        for k, c in d106[blk].items():
            assert d[blk][k]["theta0"]["t_L"] == pytest.approx(c["t_L_theta0_any_C44"], rel=1e-12), k

    names = d["inputs"]["p0_list_order"]
    p0 = [d["inputs"]["p0_readings"][n]["MPa"] for n in names]
    for n, p in zip(names, p0, strict=True):          # the number is the one inside its own quoted phrase
        assert f"{p:g}".replace(".", ",") + " MPa" in d["inputs"]["p0_readings"][n]["quote"], n
    ex = d["inputs"]["p0_excluded"]
    assert ex["MPa"] not in p0 and all("2,5 MPa" in q for q in ex["quotes"]), "the ambiguous 2.5 MPa is back as a reading"

    def up(x, k=0):
        return math.ceil(round(x * 10 ** k, 9)) / 10 ** k

    def down(x, k=0):
        return math.floor(round(x * 10 ** k, 9)) / 10 ** k

    # the scale: 105's source day at the gyroid
    stem, frac = d105["inputs"]["stem_readings_87"], d105["inputs"]["depth_fraction"]
    strains = d["inputs"]["strain_at_gyroid_ue"]
    for k, v in strains.items():
        rd, pl = k.split("|")
        assert v == stem[rd]["surface_strain_ue"] * frac[pl], k
    ends = {e: strains[d["inputs"]["strain_ends"][e]] for e in ("low", "high")}
    assert ends["low"] == min(strains.values()) and ends["high"] == max(strains.values())

    # ── σᴵ by 4th-order tensors (another arithmetic than the script's Mandel 6×6) ──
    i3 = np.eye(3)
    sets_of = {"scots_pine": s106.WOOD, "green": {n: gs["w"] for n, gs in s106.green_sets().items()}}
    wood_of = {**sets_of["scots_pine"], **sets_of["green"]}
    assert len(wood_of) == len(sets_of["scots_pine"]) + len(sets_of["green"]), "a set name in both groups"

    def compliance4(w, rd):
        stiff = {(0, 1): -w["nu_LT"] / w["E_L"], (0, 2): -w["nu_LR"] / w["E_L"], (1, 2): -w["nu_RT"] / w["E_R"]}
        soft = {(0, 1): -w["nu_TL"] / w["E_T"], (0, 2): -w["nu_RL"] / w["E_R"], (1, 2): -w["nu_TR"] / w["E_T"]} \
            if rd != "stiff" else stiff
        cpl = {"stiff": stiff, "soft": soft, "mean": {k: (stiff[k] + soft[k]) / 2 for k in stiff}}[rd]
        e = {0: w["E_L"], 1: w["E_T"], 2: w["E_R"]}
        g = {(1, 2): w["G_RT"], (0, 2): w["G_LR"], (0, 1): w["G_LT"]}
        s = np.zeros((3, 3, 3, 3))
        for i in range(3):
            s[i, i, i, i] = 1 / e[i]
        for (i, j), v in cpl.items():
            s[i, i, j, j] = s[j, j, i, i] = v
        for (i, j), gv in g.items():
            for a, b in ((i, j), (j, i)):
                for c, dd in ((i, j), (j, i)):
                    s[a, b, c, dd] = 1 / (4 * gv)
        return s

    def nine(t):
        return t.reshape(9, 9)

    def eshelby_gl(c, n=256):
        """n = 256: the green sets' anisotropy (E_L/G_LT up to ≈ 40) leaves 64 points 6e-7 off; 128 already converge
        to 1e-12 (measured 2026-10-22 on Davies' Table 2 stiff outerwood)."""
        x, wts = np.polynomial.legendre.leggauss(n)
        g = np.zeros((3, 3, 3, 3))
        for o, wt in zip((x + 1) * math.pi / 2, wts, strict=True):
            xi = np.array([math.cos(o), math.sin(o), 0.0])
            kinv = np.linalg.inv(np.einsum("ijkl,j,l->ik", c, xi, xi))
            g += 2 * wt * math.pi / 2 * np.einsum("ip,j,q->ipjq", kinv, xi, xi)
        return np.einsum("ipjq,pqmn->ijmn", g + np.einsum("jpiq->ipjq", g), c) / (4 * math.pi)

    def iso4(e, nu):
        lam, mu = e * nu / ((1 + nu) * (1 - 2 * nu)), e / (2 * (1 + nu))
        return (lam * np.einsum("ij,kl->ijkl", i3, i3)
                + mu * (np.einsum("ik,jl->ijkl", i3, i3) + np.einsum("il,jk->ijkl", i3, i3)))

    def cubic4(c11, c12, c44, th):
        axes = [np.array([math.cos(th), math.sin(th), 0.0]), np.array([-math.sin(th), math.cos(th), 0.0]),
                np.array([0.0, 0.0, 1.0])]
        c = (c12 * np.einsum("ij,kl->ijkl", i3, i3)
             + c44 * (np.einsum("ik,jl->ijkl", i3, i3) + np.einsum("il,jk->ijkl", i3, i3)))
        for e in axes:
            c += (c11 - c12 - 2 * c44) * np.einsum("i,j,k,l->ijkl", e, e, e, e)
        return c

    lat = d106["inputs"]["lattice_reading"]
    c11, c12, a_v = lat["C11_over_E_s"], lat["C12_over_E_s"], lat["zener_voigt_ceiling"]
    phi = d106["inputs"]["solid_fraction_105"]
    memo = {}

    def matrix(g, rd):
        if (g, rd) not in memo:
            cm = np.linalg.pinv(nine(compliance4(wood_of[g], rd))).reshape(3, 3, 3, 3)
            memo[(g, rd)] = (cm, np.linalg.pinv(nine(cm)).reshape(3, 3, 3, 3), eshelby_gl(cm))
        return memo[(g, rd)]

    def sigma_i(al, g, rd, fill, th_deg, a):
        """σᴵ per unit remote strain along L, MPa — a 3×3 tensor."""
        cm, sm, sesh = matrix(g, rd)
        e_s = ALLOY_PROPERTIES[al]["E_GPa"] * 1e3
        if fill == "pores_voigt_phase_bound":
            ci = phi * iso4(e_s, ALLOY_PROPERTIES[al]["nu"]) + (1 - phi) * cm
        else:
            ci = e_s * cubic4(c11, c12, a * (c11 - c12) / 2, math.radians(th_deg))
            if fill == "pores_additive_host_sapwood":
                ci = ci + (1 - phi) * cm
        sig = np.zeros((3, 3))
        sig[0, 0] = 1.0
        e_inf = np.einsum("ijkl,kl->ij", sm, sig)
        amat = np.einsum("ik,jl->ijkl", i3, i3) + np.einsum("ijpq,pqrs,rskl->ijkl", sesh, sm, ci - cm)
        e_i = np.linalg.solve(nine(amat), e_inf.reshape(9)).reshape(3, 3)
        return np.einsum("ijkl,kl->ij", ci, e_i) / e_inf[0, 0]

    def s1_of(t):
        return (t[0, 0] + t[1, 1]) / 2 + math.hypot((t[0, 0] - t[1, 1]) / 2, t[0, 1])

    # ── every θ = 0 cell of both groups: σᴵ by the tensor route, then the map by hand from the CACHED σᴵ ──
    psi = np.linspace(0.0, 2 * math.pi, 7200, endpoint=False)      # holds ψ = 0 and 90°, the θ = 0 principal axes
    halves = (("tension", 1.0), ("compression", -1.0))

    def traction(sl, ang):
        cs, ss = np.cos(ang), np.sin(ang)
        return (sl["LL"] * cs * cs + sl["TT"] * ss * ss + 2 * sl["LT"] * ss * cs,
                (sl["TT"] - sl["LL"]) * ss * cs + sl["LT"] * (cs * cs - ss * ss))

    def mu_brute(sl, eps, p, sgn):
        """max over the circle of ε|τ|/(p₀ − s·ε·σ_n): the grid, then a fine grid around its maximum."""
        sn, tau = traction(sl, psi)
        k = int(np.argmax(eps * np.abs(tau) / (p - sgn * eps * sn)))
        sn_f, tau_f = traction(sl, np.linspace(psi[k] - 2 * math.pi / 7200, psi[k] + 2 * math.pi / 7200, 4001))
        return float(max((eps * np.abs(tau) / (p - sgn * eps * sn)).max(),
                         (eps * np.abs(tau_f) / (p - sgn * eps * sn_f)).max()))

    all_cells = {**d["cells"], **d["green_cells"]}
    for key, cell in all_cells.items():
        al, g, rd, fill = key.split("|")
        b = cell["theta0"]
        sl = b["sigma_I_MPa_per_unit_strain"]
        t = sigma_i(al, g, rd, fill, 0.0, a_v)
        scale = abs(t).max()
        for n, (i, j) in (("LL", (0, 0)), ("TT", (1, 1)), ("RR", (2, 2)), ("LT", (0, 1))):
            assert abs(sl[n] - t[i, j]) <= 1e-8 * scale, (key, n, sl[n], t[i, j])
        assert abs(t[0, 2]) <= 1e-12 * scale and abs(t[1, 2]) <= 1e-12 * scale, key       # τ_R ≡ 0
        sn, _ = traction(sl, psi)
        assert sn.max() == pytest.approx(b["sigma1"], rel=1e-12) and sn.min() == pytest.approx(b["sigma2"], rel=1e-9)
        for h, sgn in halves:
            t1 = float((sgn * sn).max())
            for idx, p in enumerate(p0):
                on = b["opening_onset_ue"][h][idx]
                assert (on is None) == (t1 <= 0), (key, h)
                if on is not None:
                    assert on == pytest.approx(p / t1 * 1e6, rel=1e-9), (key, h)
            if t1 > 0:
                half = mu_brute(sl, 0.5 * p0[0] / t1, p0[0], sgn)
                assert half == pytest.approx(b["mu_req_max_at_half_onset"][h], rel=1e-6), (key, h)
            for end, e in ends.items():
                eps = e * 1e-6
                for idx, p in enumerate(p0):
                    cont = p - sgn * eps * sn
                    assert abs(float((cont <= 0).mean()) - b["at_source_day"][h]["open_share"][end][idx]) <= 2 / 7200
                    mu = b["at_source_day"][h]["mu_req_max"][end][idx]
                    assert (mu is None) == bool((cont <= 0).any()), (key, h, end, idx)
                    if mu is not None:
                        m = mu_brute(sl, eps, p, sgn)
                        assert m <= mu * (1 + 1e-9) and m == pytest.approx(mu, rel=1e-6), (key, h, end, idx)

    # ── the brackets follow from the cells, per group — over all cells (the demand) and the bare lattice (the smooth
    #    contact, the only cells a smooth envelope is consistent with) ──
    keys_all = {"scots_pine": list(d["cells"]), "green": list(d["green_cells"])}
    keys_all["union"] = keys_all["scots_pine"] + keys_all["green"]
    variants = {"summary": keys_all,
                "summary_bare_lattice": {g: [k for k in ks if k.endswith("|pores_carry_nothing")]
                                         for g, ks in keys_all.items()}}
    for var, keys_of in variants.items():
        assert list(d[var]) == ["scots_pine", "green", "union"]
        for grp, keys in keys_of.items():
            th0 = {k: all_cells[k]["theta0"] for k in keys}
            sm_ = d[var][grp]["theta0"]
            assert d[var][grp]["cells"] == len(keys)
            bare = [k for k in keys if k.endswith("|pores_carry_nothing")]
            assert d[var][grp]["bare_lattice_cells"] == len(bare)
            for h, sgn in halves:
                for idx, n in enumerate(names):
                    col = [b["opening_onset_ue"][h][idx] for b in th0.values()]
                    fin = [x for x in col if x is not None]
                    assert sm_["opening_onset_ue"][h][n] == {"range": [min(fin), max(fin)],
                                                             "cells_never": len(col) - len(fin)}
                    for end in ("low", "high"):
                        mus = [b["at_source_day"][h]["mu_req_max"][end][idx] for b in th0.values()]
                        fm = [x for x in mus if x is not None]
                        shares = [b["at_source_day"][h]["open_share"][end][idx] for b in th0.values()]
                        assert sm_["at_source_day"][h][end][n] == {
                            "cells_open": len(mus) - len(fm), "cells": len(mus),
                            "bare_lattice_cells_open": sum(th0[k]["at_source_day"][h]["mu_req_max"][end][idx] is None
                                                           for k in bare),
                            "open_share": [min(shares), max(shares)],
                            "mu_req_max_closed": [min(fm), max(fm)] if fm else None}
                hv = [b["mu_req_max_at_half_onset"][h] for b in th0.values() if b["mu_req_max_at_half_onset"][h] is not None]
                assert sm_["mu_req_max_at_half_onset"][h] == [min(hv), max(hv)]
                for ek, e in strains.items():
                    need = [max(0.0, e * 1e-6 * (b["sigma1"] if sgn > 0 else -b["sigma2"])) for b in th0.values()]
                    assert sm_["p0_to_stay_closed_MPa"][h][ek] == pytest.approx([min(need), max(need)], rel=1e-12)
            ratios = [b["sigma1"] / wood_of[k.split("|")[1]]["E_L"] for k, b in th0.items()]
            assert sm_["sigma1_over_E_L"] == pytest.approx([min(ratios), max(ratios)], rel=1e-12)
            lattice = {k: all_cells[k]["grid"] for k in keys if "grid" in all_cells[k]}
            assert len(lattice) == sum(1 for k in keys if not k.endswith("voigt_phase_bound"))
            sg_ = d[var][grp]["grid"]
            s1_bot = min(g["sigma1"][0] for g in lattice.values())
            for idx, n in enumerate(names):
                assert sg_["opening_onset_tension_ue"][n] == pytest.approx(
                    [p0[idx] / max(g["sigma1"][1] for g in lattice.values()) * 1e6,
                     p0[idx] / s1_bot * 1e6 if s1_bot > 0 else None], rel=1e-12)
                for end in ("low", "high"):
                    stars = [g["zener_below_which_tension_half_stays_closed"][end][idx] for g in lattice.values()]
                    fin = [x for x in stars if x is not None]
                    assert sg_["zener_below_which_tension_half_stays_closed"][end][n] == {
                        "max": max(fin) if fin else None, "cells_never_closed": len(stars) - len(fin)}
            for k, g in lattice.items():                  # θ = 0 sits on the grid: its σ₁ lies inside the grid's range
                assert g["sigma1"][0] <= th0[k]["sigma1"] * (1 + 1e-12) and th0[k]["sigma1"] <= g["sigma1"][1] * (1 + 1e-12)

    # the off-axis threshold: at the largest Zener ratio that keeps the tension half closed, the lowest σ₁ over 106's
    # angles sits exactly at p₀/ε (every other angle at or above it — σ₁ never falls as C44 rises)
    best = max(((k, end, idx, x) for k in keys_all["union"] if "grid" in all_cells[k] for end in ("low", "high")
                for idx, x in enumerate(all_cells[k]["grid"]["zener_below_which_tension_half_stays_closed"][end])
                if x is not None), key=lambda r: r[3])
    k, end, idx, a_star = best
    al, g, rd, fill = k.split("|")
    s1s = [s1_of(sigma_i(al, g, rd, fill, th, a_star)) for th in d106["inputs"]["theta_deg"]]
    assert min(s1s) == pytest.approx(p0[idx] / (ends[end] * 1e-6), rel=1e-6), best
    zu = d["summary"]["union"]["grid"]["zener_below_which_tension_half_stays_closed"]
    assert zu[end][names[idx]]["max"] == a_star

    # ── the consumers, from 106's own consumer blocks ──
    cbc = d106["consumer_ceiling_binding_claim"]
    for grp, (k_share, k_thr, consumer) in {
            "union": ("union_theta0_share", "union_gyroid_binds_above_surface_strain_ue_theta0_lowest_share",
                      cbc["binds_above_ue_large_stem_sf2"]),
            "scots_pine": ("theta0_share_over_modelled_set", "gyroid_binds_above_surface_strain_ue_theta0_lowest_share",
                           cbc["price_scots_pine_group"]["binds_above_ue_large_stem_sf2"])}.items():
        t0s, ba = d106[k_share], d106[k_thr]
        for al, v in d["consumer_binding_106_theta0"][grp].items():
            b = all_cells[t0s[al]["lowest_cell"]]["theta0"]
            assert v["cell"] == t0s[al]["lowest_cell"] and b["t_L"] == pytest.approx(t0s[al]["lowest"], rel=1e-12)
            fill = v["cell"].split("|")[3]
            assert v["pore_reading"] == fill and v["smooth_envelope_consistent"] == (fill == "pores_carry_nothing")
            thr = {fk: consumer[fk][al] for fk in ("axial_reading", "radial_reading")}
            assert thr == {fk: ba[fk][al]["large_stem_limit|near_uniaxial|sf2"] for fk in thr}, (grp, al)
            if grp == "union":
                assert cbc["reading_per_alloy"][al].endswith(f"; {v['cell'].split('|')[2]} reading, {fill}"), al
            assert v["threshold_ue_106"] == thr and v["opening_onset_tension_ue"] == b["opening_onset_ue"]["tension"]
            assert v["threshold_over_onset_min"] == min(thr[fk] / x for fk in thr
                                                        for x in b["opening_onset_ue"]["tension"])
            assert v["p0_to_stay_closed_at_threshold_MPa"] == pytest.approx(
                {fk: thr[fk] * 1e-6 * b["sigma1"] for fk in thr}, rel=1e-12)
    hi_blocks = {"union": "union_theta0_share", "scots_pine": "theta0_share_over_modelled_set",
                 "green": "green_theta0_share"}
    sup_blocks = {"union": "union_junction_share_sup_at_C44_zero", "scots_pine": "junction_share_sup_at_C44_zero",
                  "green": "green_junction_share_sup_at_C44_zero"}
    for grp, jn in d["consumer_junction"].items():
        for al, v in jn["theta0_highest"].items():
            assert v["cell"] == d106[hi_blocks[grp]][al]["highest_cell"]
            assert v["opening_onset_tension_ue"] == all_cells[v["cell"]]["theta0"]["opening_onset_ue"]["tension"]
        sup = jn["sup_C44_zero"]
        assert sup["t_L"] == pytest.approx(d106[sup_blocks[grp]], rel=1e-12), grp
        t = sigma_i(*sup["cell"].split("|"), sup["theta_deg"], 0.0)
        iso = abs(t[0, 0] - t[1, 1]) <= 1e-9 * abs(t[0, 0]) and abs(t[0, 1]) <= 1e-9 * abs(t[0, 0])
        assert sup["in_plane_stress_isotropic"] == iso and s1_of(t) == pytest.approx(sup["mohr"]["sigma1"], rel=1e-8)
        for ek, e in strains.items():
            assert sup["tension_half_open_at"][ek] == [n for n, p in zip(names, p0, strict=True)
                                                       if e * sup["mohr"]["sigma1"] * 1e-6 >= p]
    sup106 = d106["consumer_ceiling_junction"]["off_axis_sup_at_C44_zero"]
    assert (d["consumer_junction"]["union"]["sup_C44_zero"]["cell"],
            d["consumer_junction"]["union"]["sup_C44_zero"]["theta_deg"]) == (sup106["cell"], sup106["theta_deg"])
    # the published-sets-only companion (⚖️ founder 2026-10-22), recomputed by the tensor route from 106's own block
    pub106 = d106["consumer_ceiling_junction"]["off_axis_sup_at_C44_zero_published_sets_only"]
    pub = d["consumer_junction"]["union"]["sup_C44_zero_published_sets_only"]
    assert (pub["cell"], pub["theta_deg"]) == (pub106["cell"], pub106["theta_deg"])
    assert pub["t_L"] == pytest.approx(pub106["share"], rel=1e-12)
    t = sigma_i(*pub["cell"].split("|"), pub["theta_deg"], 0.0)
    assert s1_of(t) == pytest.approx(pub["mohr"]["sigma1"], rel=1e-8)
    for i, p in enumerate(p0):
        assert pub["opening_onset_tension_ue"][i] == pytest.approx(p / pub["mohr"]["sigma1"] * 1e6, rel=1e-12)
    for ek, e in strains.items():
        assert pub["tension_half_open_at"][ek] == [n for n, p in zip(names, p0, strict=True)
                                                   if e * pub["mohr"]["sigma1"] * 1e-6 >= p]

    # the price of the excluded 2.5 MPa, and the homogenisation margin, from the cells
    ex_p = d["p0_excluded_price"]
    for grp, keys in keys_all.items():
        for end in ("low", "high"):
            e = ends[end] * 1e-6
            bare = [k for k in keys if k.endswith("|pores_carry_nothing")]
            assert ex_p[grp][end] == {
                "cells_below": sum(e * all_cells[k]["theta0"]["sigma1"] < ex["MPa"] for k in keys), "cells": len(keys),
                "bare_lattice_cells_below": sum(e * all_cells[k]["theta0"]["sigma1"] < ex["MPa"] for k in bare),
                "bare_lattice_cells": len(bare)}, (grp, end)
    pr = d["psi_resolution"]
    bare_all = [k for k in keys_all["union"] if k.endswith("|pores_carry_nothing")]
    m = min(ends["low"] * 1e-6 * all_cells[k]["theta0"]["sigma1"] for k in bare_all) / max(p0)
    assert pr["smallest_margin_need_over_higher_p0_bare_lattice"] == pytest.approx(m, rel=1e-12)
    span = max(pr["period_rim_core_mm"]) / pr["envelope_radius_mm"]
    assert pr["largest_cell_over_radius_rad"] == pytest.approx(span, rel=1e-12)
    assert pr["constant_below_which_every_bare_cell_still_opens"] == pytest.approx((1 - 1 / m) / span, rel=1e-12)
    ax = d["axial_anode_bond_force_105"]
    assert ax["mean_shear_MPa_range"] == [min(v["mean_shear_MPa"] for v in ax["states"].values()),
                                          max(v["mean_shear_MPa"] for v in ax["states"].values())]
    for kk, v in ax["states"].items():
        assert v["force_N"] == max(r["force_N"] for q, r in d105["zone1_members"].items() if q.endswith("|" + kk))
        assert v["mean_shear_MPa"] == pytest.approx(v["force_N"] / ax["envelope_mm2"], rel=1e-12)

    # ── the controls the script ran, and the verdict's numbers and quantifiers ──
    c = d["controls"]
    assert d["reproduction_of_106"]["worst_relative"] <= 1e-12
    assert c["isotropic_closed_form_traction_max_error"] < 1e-12 and c["axial_shear_over_stress_worst"] < 1e-12
    assert c["projection_vs_mohr_circle_worst"] < 1e-12 and c["theta0_sigma_moves_with_C44_worst"] < 1e-9
    assert c["sigma1_drop_as_C44_rises_worst"] < 1e-12 and c["mu_tangent_vs_brute_force_worst"] < 1e-6
    assert c["mu_onset_fraction_form_vs_half_map_worst"] < 1e-12
    v = d["verdict"]
    assert v.startswith("Read as a SMOOTH contact on the gyroid's envelope") and "neither failing nor holding" in v
    assert "never holding" not in v and "no friction is needed" not in v, "an unscoped direction or holding claim is back"
    for gone in ("at the earliest", "can only raise", "would open at least", "does not open at all"):
        assert gone not in v, f"a claim the 2026-10-22 reviews removed is back in the verdict: «{gone}»"
    lo_k = d["inputs"]["strain_ends"]["low"]
    sb = d["summary_bare_lattice"]
    assert "consistent only with the bare-lattice cells (" + " ⊥ ".join(
        str(sb[g]["cells"]) for g in ("scots_pine", "green")) + ")" in v
    for grp, lab in (("scots_pine", "the Scots pine group"), ("green", "the green group")):
        need = sb[grp]["theta0"]["p0_to_stay_closed_MPa"]["tension"][lo_k][0]
        assert f"{down(need, 2):.2f} MPa ({lab})" in v
        for summ, what in ((sb, "bare-lattice cells"), (d["summary"], "cells")):
            sd = summ[grp]["theta0"]["at_source_day"]["tension"]
            counts = [sd[e][n]["cells_open"] for e in ("low", "high") for n in names]
            m = summ[grp]["cells"]
            quant = f"every one of its {m} {what}" if min(counts) == m else f"at least {min(counts)} of its {m} {what}"
            assert f"{quant} ({lab})" in v, (grp, what)
        ep = d["p0_excluded_price"][grp]["low"]
        assert (f"{ep['cells_below']} of {ep['cells']} cells ({lab}; {ep['bare_lattice_cells_below']} of "
                f"{ep['bare_lattice_cells']} bare lattice)") in v
    needs = [sb[g]["theta0"]["p0_to_stay_closed_MPa"]["tension"][lo_k][0] for g in ("scots_pine", "green")]
    assert (" — " + " ⊥ ".join(f"{down(x / max(p0), 1):.1f}×" for x in needs)
            + f" the higher named root reading ({max(p0)} MPa") in v
    zb = sb["union"]["grid"]["zener_below_which_tension_half_stays_closed"]
    zmax = max(x["max"] for e in ("low", "high") for x in zb[e].values() if x["max"] is not None)
    assert f"below a Zener ratio of {up(zmax, 3):.3f} on some install angle" in v
    bu = d["consumer_binding_106_theta0"]["union"]
    rb = min(x["threshold_over_onset_min"] for x in bu.values())
    p0b = min(min(x["p0_to_stay_closed_at_threshold_MPa"].values()) for x in bu.values())
    al_b = min(bu, key=lambda a: bu[a]["threshold_over_onset_min"])
    if bu[al_b]["smooth_envelope_consistent"]:
        assert f"opens there at least {down(rb, 1):.1f}× below the binding strain" in v
    else:                       # a cell with tissue in the pores: the demand, with no direction
        assert f"reaches p₀ {down(rb, 1):.1f}× below the binding strain ({al_b})" in v
        assert f"a p₀ of {down(p0b, 1):.1f} MPa would offset it" in v and "with no direction" in v
    hi_k = d["inputs"]["strain_ends"]["high"]
    for key in ("sup_C44_zero", "sup_C44_zero_published_sets_only"):
        sp = d["consumer_junction"]["union"][key]
        assert (f"at the source day's upper whisker on a large stem on {len(sp['tension_half_open_at'][hi_k])} of "
                f"{len(names)} named readings and at its median on a DBH-38 bark on "
                f"{len(sp['tension_half_open_at'][lo_k])}") in v, key


def test_gyroid_wood_strain_share_invariants():
    """106 (00_07 HW.23, the orthotropic-Eshelby leg): cells recomputed HERE by another ARITHMETIC — Mura's integral by
    Gauss–Legendre on [0, π] (the script: midpoints on [0, 2π]), the wood's compliance built as a 4th-order tensor and
    inverted by a 9×9 pseudo-inverse (the script: a Voigt 6×6), the lattice's cubic tensor written on its cube axes (the
    script: a rotated Voigt matrix), the inclusion solved 9×9 (the script: Mandel 6×6), the Voigt root chosen by a gap
    computed here. SHARED with the script, so not independent: the WOOD constants, the stiff/soft/mean rule and the
    equivalent-inclusion equation — the model, which the transcription check and the script's closed-form controls hold.

    CAN catch: a transcription that no longer matches the paper's printed aggregates; a positive-definiteness flag that
    does not follow from the readings; the lattice reading off the two cached FE ratios or a wrong Voigt root; a θ = 0
    share off the Eshelby solution at every alloy's lowest and highest θ = 0 cell; a θ = 0 share that moves with C44; a
    wrong argmin angle at a sample; a crossing count or a crossing Zener ratio that does not follow; the E110 thresholds
    off the cubic closed form; an off-axis factor or the junction's C44 = 0 supremum off the solution; 105's thresholds at
    θ = 0 not built from 105's own inputs, the reading and the lowest θ = 0 share, or rounded down; a source-day list or
    the additive-outside list that does not follow from the cells; the controls' cached errors above their tolerances;
    a verdict whose numbers are not the cells'. CANNOT catch: the MODEL (an infinite bonded cylinder in an infinite
    homogeneous matrix, the three pore readings, the homogeneous cubic reading of the FE cases) — the script's declared
    ceilings; a wrong number in the paper's tables beyond its printed aggregates (no Poisson ratio and no 85 % RH value
    has one); the full-grid moisture counts, which only the script computes.
    """
    import importlib.util

    from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES

    spec = importlib.util.spec_from_file_location("s106_t", REPO / "tools/in_silico/scripts/106_gyroid_wood_strain_share.py")
    s106 = importlib.util.module_from_spec(spec)
    sys.modules["s106_t"] = s106
    spec.loader.exec_module(s106)
    d = json.loads((MECHANICAL / "gyroid_wood_strain_share.json").read_text(encoding="utf-8"))
    d105 = json.loads((MECHANICAL / "printed_part_sway_stress.json").read_text(encoding="utf-8"))
    fea = json.loads((REPO / "tools/cad/cache/fea/anchor_zone1_pine.json").read_text(encoding="utf-8"))
    wood = s106.WOOD
    assert d["inputs"]["wood"] == wood

    for name, f, digits, printed in s106.PRINTED_AGGREGATES:
        assert math.floor(round(f(wood) * 10 ** digits, 9)) / 10 ** digits == printed, name

    i3 = np.eye(3)

    def compliance4(w, rd):
        stiff = {(0, 1): -w["nu_LT"] / w["E_L"], (0, 2): -w["nu_LR"] / w["E_L"], (1, 2): -w["nu_RT"] / w["E_R"]}
        if rd == "stiff":                                   # a set printing the stiffer-axis ratios only (Jeong) has no soft
            cpl = stiff
        else:
            soft = {(0, 1): -w["nu_TL"] / w["E_T"], (0, 2): -w["nu_RL"] / w["E_R"], (1, 2): -w["nu_TR"] / w["E_T"]}
            cpl = soft if rd == "soft" else {k: (stiff[k] + soft[k]) / 2 for k in stiff}
        e = {0: w["E_L"], 1: w["E_T"], 2: w["E_R"]}
        g = {(1, 2): w["G_RT"], (0, 2): w["G_LR"], (0, 1): w["G_LT"]}
        s = np.zeros((3, 3, 3, 3))
        for i in range(3):
            s[i, i, i, i] = 1 / e[i]
        for (i, j), v in cpl.items():
            s[i, i, j, j] = s[j, j, i, i] = v
        for (i, j), gv in g.items():
            for a, b in ((i, j), (j, i)):
                for c, dd in ((i, j), (j, i)):
                    s[a, b, c, dd] = 1 / (4 * gv)
        return s

    def nine(t):
        return t.reshape(9, 9)

    def eshelby_gl(c, n=256):
        # 256 points: Davies' green sets (shear moduli ~10² below E_L) leave 64 points 6e-7…2e-5 off S (2026-10-22);
        # at 256 every live reading of both groups agrees with the script's converged midpoint rule to ~1e-15
        x, wts = np.polynomial.legendre.leggauss(n)
        om = (x + 1) * math.pi / 2
        g = np.zeros((3, 3, 3, 3))
        for o, wt in zip(om, wts, strict=True):
            xi = np.array([math.cos(o), math.sin(o), 0.0])
            kinv = np.linalg.inv(np.einsum("ijkl,j,l->ik", c, xi, xi))
            g += 2 * wt * math.pi / 2 * np.einsum("ip,j,q->ipjq", kinv, xi, xi)
        return np.einsum("ipjq,pqmn->ijmn", g + np.einsum("jpiq->ipjq", g), c) / (4 * math.pi)

    def iso4(e, nu):
        lam, mu = e * nu / ((1 + nu) * (1 - 2 * nu)), e / (2 * (1 + nu))
        return (lam * np.einsum("ij,kl->ijkl", i3, i3)
                + mu * (np.einsum("ik,jl->ijkl", i3, i3) + np.einsum("il,jk->ijkl", i3, i3)))

    def cubic4(c11, c12, c44, th):
        axes = [np.array([math.cos(th), math.sin(th), 0.0]), np.array([-math.sin(th), math.cos(th), 0.0]),
                np.array([0.0, 0.0, 1.0])]
        c = (c12 * np.einsum("ij,kl->ijkl", i3, i3)
             + c44 * (np.einsum("ik,jl->ijkl", i3, i3) + np.einsum("il,jk->ijkl", i3, i3)))
        for e in axes:
            c += (c11 - c12 - 2 * c44) * np.einsum("i,j,k,l->ijkl", e, e, e, e)
        return c

    # the lattice reading: both roots of the two cached FE ratios, the Voigt gap computed HERE
    r_r = d105["inputs"]["fe_readings"]["radial_reading"]
    r_a = d105["inputs"]["fe_readings"]["axial_reading"]
    phi, nu_s = d105["inputs"]["solid_fraction"], fea["poisson_ratio"]
    pp = r_r / ((1 + nu_s) * (1 - 2 * nu_s))
    solid = phi * nine(iso4(1.0, nu_s))
    inside = []
    for q in ((3 * pp - math.sqrt(9 * pp * pp - 8 * pp * r_a)) / 2, (3 * pp + math.sqrt(9 * pp * pp - 8 * pp * r_a)) / 2):
        gap = np.linalg.eigvalsh(solid - nine(cubic4((pp + q) / 2, (pp - q) / 2, 0.0, 0.0)))
        if gap[np.argsort(np.abs(gap))[3:]].min() >= -1e-12:
            inside.append(((pp + q) / 2, (pp - q) / 2))
    assert len(inside) == 1, "the Voigt gap computed here does not single out one root"
    lat = d["inputs"]["lattice_reading"]
    c11, c12 = lat["C11_over_E_s"], lat["C12_over_E_s"]
    assert (c11, c12) == pytest.approx(inside[0], rel=1e-12)
    assert lat["zener_voigt_ceiling"] == pytest.approx(2 * phi / (2 * (1 + nu_s)) / (c11 - c12), rel=1e-12)

    for g, w in wood.items():
        for rd in ("stiff", "soft", "mean"):
            ev = np.linalg.eigvalsh(nine(compliance4(w, rd)))
            sym6 = ev[np.argsort(np.abs(ev))[3:]]                 # drop the 3 antisymmetric zeros by MAGNITUDE, not by sign
            assert d["wood_readings"][f"{g}|{rd}"]["positive_definite"] == bool(sym6.min() > 0), (g, rd, sym6)
    for v in d["wood_readings"].values():
        if v["positive_definite"]:
            assert v["covariance_control"] < 1e-10 and v["quadrature_change_at_2n"] < 1e-10
            assert v["hole_control"]["kt_eshelby"] == pytest.approx(v["hole_control"]["kt_lekhnitskii"], rel=1e-10)
    assert d["controls"]["isotropic_cylinder_max_error"] < 1e-12 and d["controls"]["isotropic_inclusion_max_error"] < 1e-12
    assert d["controls"]["t_L_rise_with_C44_worst"] < 1e-9 and d["controls"]["mirror_45_worst"] < 1e-9

    memo = {}
    gsets = d["inputs"]["green_sets"]
    allsets = wood | {n: v["constants"] for n, v in gsets.items()}   # both groups' constants, by set name

    def matrix(g, rd):
        if (g, rd) not in memo:
            cm = np.linalg.pinv(nine(compliance4(allsets[g], rd))).reshape(3, 3, 3, 3)
            memo[(g, rd)] = (cm, np.linalg.pinv(nine(cm)).reshape(3, 3, 3, 3), eshelby_gl(cm))
        return memo[(g, rd)]

    def t_l(al, g, rd, fill, th_deg, a):
        cm, sm, sesh = matrix(g, rd)
        e_s = ALLOY_PROPERTIES[al]["E_GPa"] * 1e3
        if fill == "pores_voigt_phase_bound":
            ci = phi * iso4(e_s, ALLOY_PROPERTIES[al]["nu"]) + (1 - phi) * cm
        else:
            ci = e_s * cubic4(c11, c12, a * (c11 - c12) / 2, math.radians(th_deg))
            if fill == "pores_additive_host_sapwood":
                ci = ci + (1 - phi) * cm
        sig = np.zeros((3, 3))
        sig[0, 0] = 1.0
        e_inf = np.einsum("ijkl,kl->ij", sm, sig)
        amat = np.einsum("ik,jl->ijkl", i3, i3) + np.einsum("ijpq,pqrs,rskl->ijkl", sesh, sm, ci - cm)
        e_i = np.linalg.solve(nine(amat), e_inf.reshape(9)).reshape(3, 3)
        return e_i[0, 0] / e_inf[0, 0]

    a_v = lat["zener_voigt_ceiling"]
    a_floor = d["inputs"]["zener_grid"][0]
    t0 = d["theta0_share_over_modelled_set"]
    for al in ALLOY_PROPERTIES:
        for which in ("lowest_cell", "highest_cell"):
            _, g, rd, fill = t0[al][which].split("|")
            cell = d["cells"][t0[al][which]]
            assert t_l(al, g, rd, fill, 0.0, a_v) == pytest.approx(cell["t_L_theta0_any_C44"], rel=1e-9)
            assert t_l(al, g, rd, fill, 0.0, 1e-2 * a_v) == pytest.approx(cell["t_L_theta0_any_C44"], rel=1e-9)
        cells = {k: v for k, v in d["cells"].items() if k.startswith(f"{al}|")}
        assert t0[al]["lowest"] == min(v["t_L_theta0_any_C44"] for v in cells.values())
        assert t0[al]["highest"] == max(v["t_L_theta0_any_C44"] for v in cells.values())
    # a sample: the argmin angle at the ceiling, the C44 = 0 maximum, the crossing — over the script's own θ grid
    for al, g, rd, fill in (("Ti-6Al-4V", "rh95", "stiff", "pores_carry_nothing"),
                            ("Ta", "rh65", "mean", "pores_additive_host_sapwood")):
        cell = d["cells"][f"{al}|{g}|{rd}|{fill}"]
        at_av = [t_l(al, g, rd, fill, th, a_v) for th in s106.THETA_DEG]
        assert s106.THETA_DEG[int(np.argmin(at_av))] == cell["theta_of_min_deg"]
        assert min(at_av) == pytest.approx(cell["t_L_at_voigt_C44_min_over_theta"], rel=1e-9)
        assert max(t_l(al, g, rd, fill, th, 0.0) for th in s106.THETA_DEG) == pytest.approx(
            cell["t_L_at_C44_zero_max_over_theta"], rel=1e-9)
        if cell["zener_at_which_t_L_is_1_theta45"] is not None:
            assert t_l(al, g, rd, fill, 45.0, cell["zener_at_which_t_L_is_1_theta45"]) == pytest.approx(1.0, abs=1e-8)
    assert d["junction_share_sup_at_C44_zero"] == max(v["t_L_at_C44_zero_max_over_theta"] for v in d["cells"].values())
    # the crossing count behind the prose: a sign change of t_L − 1 between the grid's ends at 45°, every lattice cell
    for key, v in d["cells"].items():
        al, g, rd, fill = key.split("|")
        if fill == "pores_voigt_phase_bound":
            assert v["zener_at_which_t_L_is_1_theta45"] is None
            continue
        crosses = (t_l(al, g, rd, fill, 45.0, a_floor) - 1) * (t_l(al, g, rd, fill, 45.0, a_v) - 1) <= 0
        assert (v["zener_at_which_t_L_is_1_theta45"] is not None) == crosses, key
    assert all(v["theta0_independent_of_C44"] for v in d["cells"].values())

    # E110 at 45° against the cubic closed form, and one alloy's off-axis factor
    s11 = (c11 + c12) / ((c11 - c12) * (c11 + 2 * c12))
    s12 = -c12 / ((c11 - c12) * (c11 + 2 * c12))
    ez = d["e_z_star_105_premise_theta45"]
    for fk, reading in (("radial_reading", r_r), ("axial_reading", r_a)):
        a_need = 2 / (4 * (1 / reading - (s11 + s12) / 2)) / (c11 - c12)
        assert ez[fk]["zener_below_which_E110_falls_under_reading"] == pytest.approx(a_need, rel=1e-9)
    e110_v = 1 / ((s11 + s12) / 2 + 1 / (4 * a_v * (c11 - c12) / 2))
    assert ez["E110_over_E_s_at_voigt_ceiling"] == pytest.approx(e110_v, rel=1e-12)
    live = [k for k, v in d["wood_readings"].items() if v["positive_definite"]]
    facs = [math.sqrt(r_a / e110_v) / t_l("Ta", *k.split("|"), fill, 45.0, a_v) for k in live for fill in s106.FILLS]
    assert d["off_axis_threshold_factor_theta45"]["Ta"]["at_voigt_ceiling"]["threshold_factor_min"] == pytest.approx(min(facs), rel=1e-9)
    assert d["off_axis_threshold_factor_theta45"]["Ta"]["at_voigt_ceiling"]["threshold_factor_max"] == pytest.approx(max(facs), rel=1e-9)

    # the additive reading outside the pore ends' interval, from the cells
    outside = []
    for al in ALLOY_PROPERTIES:
        for k in live:
            ends = [d["cells"][f"{al}|{k}|{f}"] for f in ("pores_carry_nothing", "pores_voigt_phase_bound")]
            mid = d["cells"][f"{al}|{k}|pores_additive_host_sapwood"]
            for fld in ("t_L_theta0_any_C44", "t_L_at_voigt_C44_min_over_theta"):
                lo, hi = sorted(e[fld] for e in ends)
                if not lo - 1e-12 <= mid[fld] <= hi + 1e-12:
                    outside.append(f"{al}|{k}|{fld}")
    assert sorted(outside) == sorted(d["additive_outside_the_pore_ends_interval"])

    # 105's thresholds at θ = 0 from 105's own inputs, each reading and the lowest θ = 0 share (rounded UP)
    stem = d105["inputs"]["stem_readings_87"]
    cell_ls = "large_stem_limit|near_uniaxial|sf2"
    for fk, ratio in (("axial_reading", r_a), ("radial_reading", r_r)):
        f_read = math.sqrt(ratio / phi)
        ba = d["gyroid_binds_above_surface_strain_ue_theta0_lowest_share"][fk]
        for al in ALLOY_PROPERTIES:
            lim = d105["alloys"][al]["endurance_strain_printed_ue"]
            for dk, frac in d105["inputs"]["depth_fraction"].items():
                for sk, div in d105["inputs"]["stress_state_divisor"].items():
                    for sf in (1, 2):
                        assert ba[al][f"{dk}|{sk}|sf{sf}"] == math.ceil(round(lim / sf * div / (f_read * frac * t0[al]["lowest"]), 9))
        for rd in ("median", "upper_whisker"):
            eps = stem[rd]["surface_strain_ue"]
            assert d["source_day_theta0_large_stem_sf2"][fk][rd]["exceeds"] == sorted(
                al for al in ALLOY_PROPERTIES if eps > ba[al][cell_ls])
    for fk in ("axial_reading", "radial_reading"):
        for rd in ("median", "upper_whisker"):
            assert d["source_day_at_t1_105"][fk][rd] == sorted(
                al for al in ALLOY_PROPERTIES
                if stem[rd]["surface_strain_ue"] > d105["gyroid_binds_above_surface_strain_ue"][al][cell_ls][fk])
    # the verdict's t_L = 1 clause is composed from those sets (in-silico §When Modifying #5), in either branch
    t1a, t1r = d["source_day_at_t1_105"]["axial_reading"], d["source_day_at_t1_105"]["radial_reading"]
    j = lambda xs: ", ".join(xs) or "none"  # noqa: E731 — the script's own joiner
    if t1a == t1r:
        assert f"at t_L = 1 on both readings the upper whisker exceeded it for {j(t1a['upper_whisker'])} and the median for {j(t1a['median'])}." in d["verdict"]
    else:
        assert (f"at t_L = 1 the upper whisker exceeded it for {j(t1a['upper_whisker'])} on this tensor's E[100] and for "
                f"{j(t1r['upper_whisker'])} on 105's radial reading, the median for {j(t1a['median'])} on E[100] and for "
                f"{j(t1r['median'])} on the radial one.") in d["verdict"]
    ba_a = d["gyroid_binds_above_surface_strain_ue_theta0_lowest_share"]["axial_reading"]
    for al in ALLOY_PROPERTIES:
        assert d["threshold_ratio_vs_baseline_theta0_lowest_share"][al] == pytest.approx(
            ba_a[al][cell_ls] / ba_a[ALLOY_BASELINE][cell_ls], rel=1e-12)

    # the verdict's numbers are the cells'
    for al in ALLOY_PROPERTIES:
        assert f"{al} {math.floor(round(t0[al]['lowest'] * 1000, 9)) / 1000:.3f}" in d["verdict"]
    up = ", ".join(d["source_day_theta0_large_stem_sf2"]["axial_reading"]["upper_whisker"]["exceeds"]) or "none"
    assert f"upper whisker exceeds the large-stem threshold for {up} on" in d["verdict"]
    assert f"({len(d['additive_outside_the_pore_ends_interval'])} cell-fields fall outside them)" in d["verdict"]

    # ── the GREEN group (⚖️ founder 2026-10-22, HW.23 option (Б)) and the UNION. Its constants rebuilt HERE from the
    # as-printed figures (not by the script's builder), the sources' own aggregates recomputed, every live green tensor and
    # the union's adverse cells recomputed by THIS arithmetic. CAN catch, beyond the above: a green constant off its
    # printed figure or off the paper's p. 4 rule as the script states it; a borrowed constant other than the one named;
    # a lowest / highest / junction cell off the solution or not the extreme of the cells; a crossing flag; G_LR or G_RT
    # leaking into the share; a cached ν_RT sensitivity that understates the span's ends; the union's thresholds, source
    # day, per-set verdicts and the ceiling not built from 105's inputs. CANNOT catch: a figure misread in the PDF (the
    # transcription checks hold Davies' Table 2, Liu and Jeong's E_L to their own aggregates, ESM 2/3 to nothing).
    tr = d["inputs"]["green_transcription"]
    assert tr["davies_table2_as_printed"] == {k: list(v) for k, v in s106.DAVIES_TABLE2.items()}
    assert tr["liu_table2_as_printed"] == s106.LIU_TABLE2
    cols, hdr = s106.DAVIES_COLUMNS, s106.JEONG_TABLE2_HEADER
    for i, col in enumerate(cols):
        t2c, esm = gsets[f"davies2016_table2_{col}"]["constants"], gsets[f"davies2016_esm_{col}"]["constants"]
        for k, v in s106.DAVIES_TABLE2.items():
            assert t2c[k] == pytest.approx(float(v[i]) * (1 if k.startswith("nu_") else 1000), rel=1e-12), (col, k)
        e2 = {k: float(v[i]) for k, v in s106.DAVIES_ESM2.items()}
        n3 = {k: float(v[i]) for k, v in s106.DAVIES_ESM3_COMPRESSION.items()}
        assert esm["E_L"] == pytest.approx(250 * (e2["lr_t"] + e2["lr_c"] + e2["lt_t"] + e2["lt_c"]), rel=1e-12)
        assert esm["E_R"] == pytest.approx(500 * (e2["rt_t"] + e2["rt_c"]), rel=1e-12)
        assert esm["E_T"] == pytest.approx(500 * (e2["tr_t"] + e2["tr_c"]), rel=1e-12)
        assert [esm[f"nu_{p}"] for p in ("RT", "RL", "TR", "TL", "LR", "LT")] == [n3[f"{p.lower()}_c"] for p in
                                                                             ("RT", "RL", "TR", "TL", "LR", "LT")]
        assert [esm[g] for g in ("G_LT", "G_LR", "G_RT")] == pytest.approx([1000 * e2[g] for g in ("TL", "LR", "RT")], rel=1e-12)
    liu_rows = {r: dict(zip(s106.LIU_TABLE2_HEADER, map(float, s106.LIU_TABLE2[r].split()), strict=True))
                for r in ("1", "2", "3", "4")}
    assert gsets["liu2019_P4"]["constants"] == liu_rows["4"]
    jeong = gsets["jeong2026_red_pine_green"]["constants"]
    for k, v in zip(hdr, s106.JEONG_TABLE2_RED_PINE["Green"], strict=True):
        if v is not None:
            assert jeong[k] == pytest.approx(float(v) * (1 if k.startswith("nu_") else 1000), rel=1e-12), k
    assert s106.JEONG_TABLE2_RED_PINE["Green"][hdr.index("nu_RT")] is None            # rejected by the author
    assert jeong["nu_RT"] == float(s106.JEONG_TABLE2_RED_PINE["19"][hdr.index("nu_RT")])   # borrowed: its own 19 % row
    assert jeong["G_RT"] == wood["rh95"]["G_RT"]                                       # borrowed: G&A's 95 % RH group
    assert not {"nu_RL", "nu_TL", "nu_TR"} & set(jeong) and gsets["jeong2026_red_pine_green"]["readings"] == ["stiff"]
    kp = gsets["jeong2026_korean_pine_green"]["constants"]                           # Korean pine: ν_RT printed
    assert tr["jeong_table2_korean_pine_as_printed"] == {r: list(v) for r, v in s106.JEONG_TABLE2_KOREAN_PINE.items()}
    for k, v in zip(hdr, s106.JEONG_TABLE2_KOREAN_PINE["Green"], strict=True):
        assert kp[k] == pytest.approx(float(v) * (1 if k.startswith("nu_") else 1000), rel=1e-12), k
    assert kp["G_RT"] == wood["rh95"]["G_RT"]                                          # borrowed, as for red pine
    assert not {"nu_RL", "nu_TL", "nu_TR"} & set(kp) and gsets["jeong2026_korean_pine_green"]["readings"] == ["stiff"]
    kp6, kpg = (float(s106.JEONG_TABLE2_KOREAN_PINE[r][hdr.index("E_L")]) for r in ("6", "Green"))
    assert (kpg - 0.005) / (kp6 + 0.005) <= 0.6695 and (kpg + 0.005) / (kp6 - 0.005) >= 0.6685   # «66.9%» at its rounding
    assert round(100 * kpg / kp6, 1) == 66.8                                            # … which the exact quotient misses
    assert tr["checks"]["jeong_korean_pine_e_l_retention_pct"]["match_within_rounding"] is True
    printed_mean = s106.LIU_TABLE2["Mean"].split()
    for j, k in enumerate(s106.LIU_TABLE2_HEADER):
        half = 0.5 * 10 ** -(len(printed_mean[j].split(".")[1]) if "." in printed_mean[j] else 0)
        assert abs(sum(r[k] for r in liu_rows.values()) / 4 - float(printed_mean[j])) <= half + 1e-9, k
    for k, (lo, hi) in s106.DAVIES_ESM1_THIS_WORK.items():
        vals = [float(v) for v in s106.DAVIES_TABLE2[k]]
        assert ((min(vals), max(vals)) == (float(lo), float(hi))) == (k != "G_LR"), k   # G_LR: the source's own ×10
    assert round(100 * jeong["E_L"] / (1000 * float(s106.JEONG_TABLE2_RED_PINE["6"][hdr.index("E_L")])), 1) == 77.1

    for n, v in gsets.items():                         # positive definiteness through the 9×9 tensor
        for rd in v["readings"]:
            ev = np.linalg.eigvalsh(nine(compliance4(allsets[n], rd)))
            assert d["green_wood_readings"][f"{n}|{rd}"]["positive_definite"] == bool(ev[np.argsort(np.abs(ev))[3:]].min() > 0)
    for v in d["green_wood_readings"].values():
        if v["positive_definite"]:
            assert v["covariance_control"] < 1e-10 and v["quadrature_change_at_2n"] < 1e-10
            assert v["hole_control"]["kt_eshelby"] == pytest.approx(v["hole_control"]["kt_lekhnitskii"], rel=1e-10)
    gcells, allcells = d["green_cells"], d["cells"] | d["green_cells"]
    glive = [k for k, v in d["green_wood_readings"].items() if v["positive_definite"]]
    for k in glive:                                    # every live green tensor, at θ = 0
        n, rd = k.split("|")
        assert t_l("Ta", n, rd, "pores_voigt_phase_bound", 0.0, a_v) == pytest.approx(
            gcells[f"Ta|{k}|pores_voigt_phase_bound"]["t_L_theta0_any_C44"], rel=1e-9), k
    union = d["union_theta0_share"]
    for al in ALLOY_PROPERTIES:
        mine = {k: v["t_L_theta0_any_C44"] for k, v in allcells.items() if k.startswith(f"{al}|")}
        green = [v["t_L_theta0_any_C44"] for k, v in gcells.items() if k.startswith(f"{al}|")]
        assert (union[al]["lowest"], union[al]["highest"]) == (min(mine.values()), max(mine.values()))
        assert (d["green_theta0_share"][al]["lowest"], d["green_theta0_share"][al]["highest"]) == (min(green), max(green))
        for which in ("lowest_cell", "highest_cell"):
            _, n, rd, fill = union[al][which].split("|")
            assert t_l(al, n, rd, fill, 0.0, a_v) == pytest.approx(mine[union[al][which]], rel=1e-9)
            assert t_l(al, n, rd, fill, 0.0, 1e-2 * a_v) == pytest.approx(mine[union[al][which]], rel=1e-9)
    assert all(v["theta0_independent_of_C44"] for v in gcells.values())
    assert d["controls"]["green_t_L_rise_with_C44_worst"] < 1e-9 and d["controls"]["green_mirror_45_worst"] < 1e-9
    jn = d["consumer_ceiling_junction"]
    al, n, rd, fill = jn["off_axis_sup_at_C44_zero"]["cell"].split("|")
    assert t_l(al, n, rd, fill, jn["off_axis_sup_at_C44_zero"]["theta_deg"], 0.0) == pytest.approx(
        jn["off_axis_sup_at_C44_zero"]["share"], rel=1e-9)
    assert jn["off_axis_sup_at_C44_zero"]["share"] == d["union_junction_share_sup_at_C44_zero"] == max(
        v["t_L_at_C44_zero_max_over_theta"] for v in allcells.values())
    for key, v in gcells.items():                      # the crossing flags behind the green count
        al, n, rd, fill = key.split("|")
        if fill == "pores_voigt_phase_bound":
            assert v["zener_at_which_t_L_is_1_theta45"] is None
            continue
        crosses = (t_l(al, n, rd, fill, 45.0, a_floor) - 1) * (t_l(al, n, rd, fill, 45.0, a_v) - 1) <= 0
        assert (v["zener_at_which_t_L_is_1_theta45"] is not None) == crosses, key
    assert d["green_crossings_theta45"]["cells_crossing_1"] == sum(
        1 for v in gcells.values() if v["zener_at_which_t_L_is_1_theta45"] is not None)

    # G_LR and G_RT out of the share, through THIS arithmetic (a 9×9 tensor and a Gauss–Legendre S), off the axis too
    for base, rd in (("liu2019_P4", "mean"), ("rh95", "stiff"), ("jeong2026_red_pine_green", "stiff")):
        for key, f in itertools.product(("G_LR", "G_RT"), (0.1, 10.0)):
            allsets[f"probe_{base}_{key}_{f}"] = allsets[base] | {key: allsets[base][key] * f}
            for th, a in ((0.0, a_v), (22.5, a_v), (45.0, 0.0)):
                assert t_l("Ta", f"probe_{base}_{key}_{f}", rd, "pores_carry_nothing", th, a) == pytest.approx(
                    t_l("Ta", base, rd, "pores_carry_nothing", th, a), abs=1e-12), (base, key, f, th)
    assert d["controls"]["t_L_change_with_G_LR_or_G_RT_worst"] < 1e-12
    # Jeong's borrowed ν_RT: the span recomputed HERE, and the θ = 0 change at its ends within the cached worst and cap
    cj = d["controls"]["jeong_borrowed_nu_RT"]
    measured = ({w["nu_RT"] for w in wood.values()} | {float(v) for v in s106.DAVIES_TABLE2["nu_RT"]}
                | {float(v) for v in s106.DAVIES_ESM3_COMPRESSION["rt_c"]} | {liu_rows["4"]["nu_RT"]}
                | {float(s106.JEONG_TABLE2_RED_PINE[r][hdr.index("nu_RT")]) for r in ("6", "19")}
                | {float(s106.JEONG_TABLE2_KOREAN_PINE["Green"][hdr.index("nu_RT")])})
    assert cj["swept_span"] == [min(measured), max(measured)] and cj["borrowed"] == jeong["nu_RT"]
    for nu in cj["swept_span"]:
        allsets[f"probe_nu_{nu}"] = jeong | {"nu_RT": nu}
        for al, fill in itertools.product(ALLOY_PROPERTIES, s106.FILLS):
            dlt = abs(t_l(al, f"probe_nu_{nu}", "stiff", fill, 0.0, a_v)
                      - t_l(al, "jeong2026_red_pine_green", "stiff", fill, 0.0, a_v))
            assert dlt <= cj["t_L_change_theta0_worst"] + 1e-9 and dlt <= cj["cap_theta0"], (nu, al, fill)

    # our arithmetic on the sources, recomputed from the constants
    rc = d["green_reciprocity_our_arithmetic"]
    for n, ratios in rc["per_set"].items():
        w = allsets[n]
        if ratios is None:
            assert n in ("jeong2026_red_pine_green", "jeong2026_korean_pine_green")
            continue
        assert ratios == pytest.approx({"RL_over_LR": (w["nu_RL"] / w["E_R"]) / (w["nu_LR"] / w["E_L"]),
                                        "TL_over_LT": (w["nu_TL"] / w["E_T"]) / (w["nu_LT"] / w["E_L"]),
                                        "RT_over_TR": (w["nu_RT"] / w["E_R"]) / (w["nu_TR"] / w["E_T"])}, rel=1e-12)
    meas = rc["measured_sets"]
    assert sorted(meas) == sorted([*wood, *(n for n in gsets if n.startswith("davies2016_esm_") or n == "liu2019_P4")])
    lp = [rc["per_set"][s][k] for s in meas for k in ("RL_over_LR", "TL_over_LT")]
    assert rc["measured_L_pairs_min_max"] == [min(lp), max(lp)] and min(lp) > 1        # the transverse-loaded entry larger
    assert rc["measured_RT_pair_min_max"] == [min(rc["per_set"][s]["RT_over_TR"] for s in meas),
                                              max(rc["per_set"][s]["RT_over_TR"] for s in meas)]
    for k, ratios in d["green_davies_table2_over_esm"].items():
        assert ratios == pytest.approx([gsets[f"davies2016_table2_{c}"]["constants"][k]
                                        / gsets[f"davies2016_esm_{c}"]["constants"][k] for c in cols], rel=1e-12)
    for g, (lo, hi) in d["green_davies_shear_below_liu_x"].items():
        dv = [v["constants"][g] for n, v in gsets.items() if n.startswith("davies2016_")]
        assert (lo, hi) == pytest.approx((min(r[g] for r in liu_rows.values()) / max(dv),
                                          max(r[g] for r in liu_rows.values()) / min(dv)), rel=1e-12)

    # the union's thresholds, source day, per-set verdicts, the reading without Davies' Table 2 and the ceiling
    def binds(fk, share):
        ratio = r_a if fk == "axial_reading" else r_r
        return {al: {f"{dk}|{sk}|sf{sf}": math.ceil(round(d105["alloys"][al]["endurance_strain_printed_ue"] / sf * div
                                                          / (math.sqrt(ratio / phi) * frac * share[al]), 9))
                     for dk, frac in d105["inputs"]["depth_fraction"].items()
                     for sk, div in d105["inputs"]["stress_state_divisor"].items() for sf in (1, 2)}
                for al in ALLOY_PROPERTIES}

    def exceeds(fk, share, rd="upper_whisker"):
        b = binds(fk, share)
        return sorted(al for al in ALLOY_PROPERTIES if stem[rd]["surface_strain_ue"] > b[al][cell_ls])

    low_u = {al: union[al]["lowest"] for al in ALLOY_PROPERTIES}
    for fk in ("axial_reading", "radial_reading"):
        assert d["union_gyroid_binds_above_surface_strain_ue_theta0_lowest_share"][fk] == binds(fk, low_u)
        for rd in ("median", "upper_whisker"):
            assert d["union_source_day_theta0_large_stem_sf2"][fk][rd]["exceeds"] == exceeds(fk, low_u, rd)
        assert d["consumer_ceiling_binding_claim"]["source_day_upper_whisker_exceeds"][fk] == exceeds(fk, low_u)
        assert d["consumer_ceiling_binding_claim"]["price_scots_pine_group"]["source_day_upper_whisker_exceeds"][fk] == \
            d["source_day_theta0_large_stem_sf2"][fk]["upper_whisker"]["exceeds"]
        for n, v in d["green_per_set"].items():
            mine = {al: min(c["t_L_theta0_any_C44"] for k, c in gcells.items() if k.startswith(f"{al}|{n}|"))
                    for al in ALLOY_PROPERTIES}
            assert v["lowest"] == mine and v["source_day_upper_whisker_exceeds"][fk] == exceeds(fk, mine), n
        no_t2 = {al: min(c["t_L_theta0_any_C44"] for k, c in allcells.items()
                         if k.startswith(f"{al}|") and "|davies2016_table2_" not in k) for al in ALLOY_PROPERTIES}
        assert d["union_without_davies_table2"]["lowest"] == no_t2
        assert d["union_without_davies_table2"]["source_day_upper_whisker_exceeds"][fk] == exceeds(fk, no_t2)
    for al in ALLOY_PROPERTIES:
        assert f"group {union[al]['lowest_cell'].split('|')[1]}" in d["consumer_ceiling_binding_claim"]["reading_per_alloy"][al] \
            or gsets[union[al]["lowest_cell"].split("|")[1]]["where"] in d["consumer_ceiling_binding_claim"]["reading_per_alloy"][al]
        assert f"{al} {math.floor(round(union[al]['lowest'] * 1000, 9)) / 1000:.3f}" in d["verdict"]
    assert f"the union reaches {math.ceil(round(d['union_junction_share_sup_at_C44_zero'] * 1000, 9)) / 1000:.3f}" in d["verdict"]
    # the junction's end on the published sets alone (without our assembly of Davies' raw ESM 2/3 means), recomputed
    pub = d["consumer_ceiling_junction"]["off_axis_sup_at_C44_zero_published_sets_only"]
    pk = max((k for k in gcells if not k.split("|")[1].startswith("davies2016_esm_")),
             key=lambda k: gcells[k]["t_L_at_C44_zero_max_over_theta"])
    assert pub["cell"] == pk and pub["share"] == gcells[pk]["t_L_at_C44_zero_max_over_theta"]
    assert f"alone it reaches {math.ceil(round(pub['share'] * 1000, 9)) / 1000:.3f}" in d["verdict"]
    # Korean pine's knife-edge: Ta's margin straddles 1 across the cached ν_LR edge, through THIS arithmetic
    for fk, e in d["green_korean_pine_ta_knife_edge"]["per_fe_reading"].items():
        margins = []
        for f in (1 - 1e-6, 1 + 1e-6):
            name = f"probe_kp_{fk}_{f}"
            allsets[name] = kp | {"nu_LR": e["nu_LR_first_exceeds"] * f}
            low = {al: min(t_l(al, name, "stiff", fill, 0.0, a_v) for fill in s106.FILLS) for al in ALLOY_PROPERTIES}
            margins.append(stem["upper_whisker"]["surface_strain_ue"] / binds(fk, low)["Ta"][cell_ls])
        assert margins[0] <= 1 < margins[1], (fk, margins)


RADIO = CACHE / "radio"


def _shadow_direct_homogeneous(eps, a, rho, pol, n_max, f_hz, phi_deg):
    """The homogeneous stem in its DIRECT closed form — c_n with q = k₁/β (TM) or k₁/(β·ε_r) (TE) — not 107's layered
    admittance recursion, and not its interior amplitudes: a second road to the same cells. TM's source is an electric
    line along the stem (H_n, J_n); TE's is a line of dipoles tangential to the bark (H_n′, J_n′)."""
    from scipy.special import h2vp, hankel2, jv, jvp
    beta = 2 * math.pi * f_hz / 299_792_458.0
    k1 = beta * np.sqrt(complex(eps))
    k1 = k1.conjugate() if k1.imag > 0 else k1          # e^{jωt}: the decaying branch
    q = k1 / beta if pol == "TM" else k1 / beta / complex(eps)
    ns = np.arange(-n_max, n_max + 1)
    alpha, tau = ((hankel2(ns, beta * rho), jv(ns, beta * rho)) if pol == "TM"
                  else (h2vp(ns, beta * rho), jvp(ns, beta * rho)))
    num = jvp(ns, beta * a) * jv(ns, k1 * a) - q * jv(ns, beta * a) * jvp(ns, k1 * a)
    den = h2vp(ns, beta * a) * jv(ns, k1 * a) - q * hankel2(ns, beta * a) * jvp(ns, k1 * a)
    c = -alpha * num / den
    p0 = float(np.sum(np.abs(tau) ** 2))
    p_in = (p0 + float(np.real(np.sum(c * alpha)))) / p0
    p_rad = float(np.sum(np.abs(tau + c) ** 2)) / p0
    phi = np.deg2rad(np.asarray(phi_deg, float))
    F = np.exp(1j * np.outer(phi, ns)) @ ((1j ** ns) * (tau + c))
    front_free = abs(np.sum((1j ** ns) * tau)) ** 2
    field = np.abs(F) ** 2 / front_free
    return p_in, p_rad, 10 * np.log10(field / p_in), 10 * np.log10(field)


def test_stem_radio_shadow_invariants():
    """107 (00_07 HW.6, the trunk-shadow leg): every homogeneous row against the DIRECT closed form computed here, and
    every row's derived fields against its own powers and gains.

    CAN catch: a wrong matching across the surface (a swapped q between TM and TE, a dropped derivative, a sign in the
    Hankel term) — the direct form shares no code with the script's recursion; a far-field phase or a normalisation
    that moved; a reaction term that drifted from P_in; an efficiency, an absorbed share, a front-minus-back, a
    front-minus-side or a 3-dB sector that does not follow from the cached gains and powers; a cache whose energy
    balance or truncation control was recorded above its own tolerance; a reading whose layers no longer reach the
    stem's radius. CANNOT catch: a wrong INPUT (a permittivity, a radius, a standoff — their readings carry their
    sources), a defect that only a layered row would show beyond the energy balance the script gates at runtime, or
    anything the two-dimensional idealization drops (the declared ceilings).
    """
    pytest.importorskip("scipy")
    d = json.loads((RADIO / "stem_radio_shadow.json").read_text(encoding="utf-8"))
    f_hz = d["frequency_Hz"]
    tol = d["tolerances"]
    homogeneous = 0
    for row in d["cases"]:
        g = row["gain_dB"]
        assert row["front_minus_back_dB"] == pytest.approx(g["0"] - g["180"], abs=2e-3)
        assert row["front_minus_side_dB"] == pytest.approx(g["0"] - g["90"], abs=2e-3)
        assert row["efficiency"] == pytest.approx(row["p_rad_over_p0"] / row["p_in_over_p0"], abs=2e-5)
        absorbed = sum(row["absorbed_by_layer_axis_out"])
        assert absorbed == pytest.approx(1 - row["efficiency"], abs=1e-4), "the energy balance does not close"
        assert abs(row["controls"]["balance_rel_miss"]) <= tol["balance"]
        assert row["controls"]["truncation_max_dF"] <= tol["truncation"]
        assert row["gain_dB_min"] <= min(g.values()) + 1e-9, "the fine-grid null must not sit above a report cell"
        assert row["layers_axis_out"][-1][0] == pytest.approx(row["dbh_m"] / 2, abs=1e-6)
        assert row["rho_src_m"] == pytest.approx(row["dbh_m"] / 2 + row["standoff_mm"] / 1e3, abs=1e-6)
        if len(row["layers_axis_out"]) == 1:
            homogeneous += 1
            r, e_re, e_im = row["layers_axis_out"][0]
            p_in, p_rad, gdb, fdb = _shadow_direct_homogeneous(complex(e_re, -e_im), r, row["rho_src_m"],
                                                               row["polarization"], row["n_max"], f_hz,
                                                               [int(k) for k in g])
            assert row["p_in_over_p0"] == pytest.approx(p_in, rel=2e-5)
            assert row["p_rad_over_p0"] == pytest.approx(p_rad, rel=2e-5)
            for k, v, w in zip(g, gdb, fdb, strict=True):
                assert g[k] == pytest.approx(float(v), abs=2e-3), f"{row['polarization']} {k}°"
                assert row["field_same_current_dB"][k] == pytest.approx(float(w), abs=2e-3)
    assert homogeneous > 0, "no homogeneous row — the direct closed form checked nothing"
    c = d["controls"]
    assert c["free_space_max_abs_F_minus_free"] <= tol["free_space"]
    assert c["lossless_max_rel_power_miss"] <= tol["lossless"]


def test_stem_radio_shadow_dbh_sweep():
    """107's stem-diameter sweep (00_07 HW.6; the width sweep's review of 2026-10-22 night, F1): the diameter is the
    second resonant axis, so the sweep over canon's whole DBH range — not the three named stems — carries the sector's
    floor and the ratified rule's margin.

    CAN catch: an axis that does not start at canon's smallest host or end at the bark table's last stem; a bark per
    stem that is not the table's value at a named stem or not linear between them; a sweep that skipped a width, bark,
    standoff or polarization cell; a recorded identity miss above zero or fewer named-stem rows revisited than the
    width sweep has; a rule block whose flag, floors or attaining rows do not follow from the per-stem envelope; a
    beyond-table probe whose assumptions are unlabelled, whose per-assumption first failing stem contradicts its own
    envelope, or whose overall rule is not the worst of them; per-polarization monotonicity counts that do not sum to the
    total or exceed the cells. CANNOT catch: an extreme between two grid stems or widths (the step is the ground), a wrong
    input, or what the 2-D model drops."""
    d = json.loads((RADIO / "stem_radio_shadow.json").read_text(encoding="utf-8"))
    ds, sw = d["dbh_sweep"], d["width_sweep"]
    dbh_min_cm = round(d["readings"]["geometry"]["dbh_m"]["values"][0] * 100, 2)
    named_cm = sorted(round(v * 100, 2) for v in d["readings"]["geometry"]["dbh_m"]["values"])
    assert ds["axis_cm"][0] == dbh_min_cm and ds["axis_cm"][1] == max(named_cm), "the DBH axis does not span canon's range"
    assert ds["bark_named_stems_cm"] == named_cm
    stems = [float(k) for k in ds["bark_mm_by_dbh_cm"]]
    assert stems == [ds["axis_cm"][0] + i * ds["step_cm"] for i in range(ds["n_stems"])]
    # the bark per stem: the named readings' own bark at a named stem, linear between the named stems
    bark_at = {round(r["dbh_m"] * 100, 2): r["layers_axis_out"][-1][0] - r["layers_axis_out"][-2][0]
               for r in d["cases"] if r["permittivity"].startswith("scots_sapwood_")}
    for cm, mm in ds["bark_mm_by_dbh_cm"].items():
        cm = float(cm)
        if cm in bark_at:
            assert mm == pytest.approx(bark_at[cm] * 1e3, abs=1e-6), f"bark at the named stem {cm} cm"
        else:
            lo = max(x for x in named_cm if x < cm)
            hi = min(x for x in named_cm if x > cm)
            want = bark_at[lo] + (bark_at[hi] - bark_at[lo]) * (cm - lo) / (hi - lo)
            assert mm == pytest.approx(want * 1e3, abs=6e-4), f"bark at {cm} cm is not linear between {lo} and {hi}"  # the cache keeps 3 decimals
    assert ds["widths_cm"] == [v[0] for v in sw["by_width"]["TM"]["within_3dB_of_front_to_deg"]], "not the width axis"
    assert ds["n_rows"] == ds["n_stems"] * len(ds["widths_cm"]) * 3 * len(ds["standoffs_mm"]) * 2, "a cell was skipped"
    c = ds["controls"]
    assert c["named_stems_reproduce_the_width_sweep_max_abs_miss"] == 0.0 and c["named_stems_rows_revisited"] == sw["n_rows"]
    assert isinstance(c["standoff_monotone_crossing_violations"], int) and c["standoff_monotone_crossing_violations"] >= 0
    bp = c["standoff_monotone_by_polarization"]
    assert set(bp) == {"TM", "TE"}
    assert sum(v["crossing_narrower_at_higher_deck"] for v in bp.values()) == c["standoff_monotone_crossing_violations"]
    assert all(0 <= v["sector_narrower_at_higher_deck"] <= v["crossing_narrower_at_higher_deck"] <= v["cells"] for v in bp.values())
    assert sum(v["cells"] for v in bp.values()) == c["standoff_monotone_cells"]
    # the rule block follows from the per-stem envelope, and the sector is the crossing's floor everywhere
    for pol in ("TM", "TE"):
        env = ds["by_dbh"][pol]
        assert [v[0] for v in env["within_3dB_of_front_to_deg"]] == stems
        for sec, cro in zip(env["within_3dB_of_front_to_deg"], env["crossing_3dB_deg"], strict=True):
            assert sec[1] == math.floor(cro[1] + 1e-9) or sec[1] == math.floor(cro[1]), (pol, sec, cro)
        for key, e in ds["extremes"][pol].items():
            if key in env:
                assert e["min"] == min(v[1] for v in env[key]) and e["max"] == max(v[2] for v in env[key]), (pol, key)
            assert all(round(a["dbh_m"] * 100, 2) in stems for a in e["min_at"] + e["max_at"])
    r = ds["rule"]
    tm = ds["by_dbh"]["TM"]
    assert r["min_sector_deg"] == min(v[1] for v in tm["within_3dB_of_front_to_deg"])
    assert r["min_crossing_deg"] == min(v[1] for v in tm["crossing_3dB_deg"])
    assert r["holds_on_1deg_grid"] == (r["min_sector_deg"] >= r["sector_deg"])
    assert r["margin_deg_fine"] == pytest.approx(r["min_crossing_deg"] - r["sector_deg"], abs=1e-9)
    assert {a["dbh_m"] for a in r["min_sector_at"]} == {v[0] / 100 for v in tm["within_3dB_of_front_to_deg"] if v[1] == r["min_sector_deg"]}
    failing = [v[0] for v in tm["within_3dB_of_front_to_deg"] if v[1] < r["sector_deg"]]
    assert r["first_stem_cm_failing_on_1deg_grid"] == (failing[0] if failing else None)
    for rows in ds["tm_sector_floor_by_bark"]["TM"].values():
        assert [v[0] for v in rows] == stems and min(v[1] for v in rows) >= r["min_sector_deg"]
    assert min(min(v[1] for v in rows) for rows in ds["tm_sector_floor_by_bark"]["TM"].values()) == r["min_sector_deg"]
    # the probe beyond the table: three labelled bark assumptions, each with its own rule block; the overall rule the worst
    b = ds["beyond_bark_table"]
    assert b["axis_cm"][0] == ds["axis_cm"][1] + ds["step_cm"]
    assert b["standoffs_mm"] == ds["standoffs_mm"]
    assert c["standoff_monotone_cells"] == ds["n_rows"] // len(ds["standoffs_mm"])
    assert c["sector_floor_rows_all_at_low_standoff"] == all(a["standoff_mm"] == min(ds["standoffs_mm"]) for a in r["min_sector_at"])
    assert set(b["assumptions"]) == {"thin_end_held", "thin_end_slope", "thick_end_slope"}
    last = str(float(ds["axis_cm"][1]))
    for name, blk in b["assumptions"].items():
        assert "ASSUMPTION" in blk["what"], name
        beyond_stems = [float(k) for k in blk["bark_mm_by_dbh_cm"]]
        assert beyond_stems == [b["axis_cm"][0] + i * ds["step_cm"] for i in range(len(beyond_stems))]
        if name == "thin_end_held":
            assert all(v == pytest.approx(ds["bark_mm_by_dbh_cm"][last], abs=1e-9) for v in blk["bark_mm_by_dbh_cm"].values())
        btm = blk["by_dbh"]["within_3dB_of_front_to_deg"]
        assert blk["rule"]["min_sector_deg"] == min(v[1] for v in btm)
        bfail = [v[0] for v in btm if v[1] < blk["rule"]["sector_deg"]]
        assert blk["rule"]["first_stem_cm_failing_on_1deg_grid"] == (bfail[0] if bfail else None)
        assert blk["rule"]["holds_on_1deg_grid"] == (not bfail)
        assert b["first_stem_cm_failing_by_assumption"][name] == blk["rule"]["first_stem_cm_failing_on_1deg_grid"]
    assert b["rule"]["min_crossing_deg"] == min(blk["rule"]["min_crossing_deg"] for blk in b["assumptions"].values())
    assert b["n_rows"] == sum(blk["n_rows"] for blk in b["assumptions"].values())
    # the A.36 spans: one value per alternative reading, the span the min/max of the single readings
    for span_key in ("rule_floor_under_a36_readings", "tm_back_floor_under_a36_readings"):
        sp = ds[span_key]
        singles = {k: v for k, v in sp["by_reading"].items() if k.startswith("single_reading_")}
        assert len(singles) == 4 and sp["span_over_single_readings"] == [min(singles.values()), max(singles.values())]


def test_stem_radio_shadow_r2_blocks():
    """The adversary-2 blocks of `107`: the report grid carries the rule angle (50°) so the loss at ±50° is a cache number;
    the rule blocks carry that loss on the floor rows; the refinements report a node no HIGHER than the grid floor (the grid
    minimum is an upper bound); the deck rows are a monotone family around the floor row; the probe past the thick end has
    its eight rows; the bark axis' TM back floor carries an A.36 span that contains the floor."""
    d = json.loads((RADIO / "stem_radio_shadow.json").read_text(encoding="utf-8"))
    for row in d["cases"]:
        assert "50" in row["gain_dB"] and row["gain_dB"]["50"] <= row["gain_dB"]["0"] + 1e-9
    for blk in (d["dbh_sweep"]["rule"], d["bark_sweep"]["rule"]):
        loss = blk["loss_at_rule_deg_dB"]
        assert len(loss["at_crossing_floor"]) == len(blk["min_crossing_at"]) and loss["n_sector_floor_rows"] == len(blk["min_sector_at"])
        assert loss["n_sector_floor_cells"] <= loss["n_sector_floor_rows"]
        assert loss["over_sector_floor_rows"][0] <= loss["over_sector_floor_rows"][1]
        # the letter and the grid agree: a sector below the rule angle means a loss above 3 dB at that angle on every floor row
        assert all((v > 3.0) == (blk["min_sector_deg"] < blk["sector_deg"]) for v in loss["at_crossing_floor"])
    for blk in (d["dbh_sweep"]["rule_floor_refinement"], d["bark_sweep"]["rule_floor_refinement"]):
        assert blk["below_the_grid_node_deg"] >= 0.0, "a finer grid found a HIGHER floor than the node it surrounds — the refinement does not surround the node"
        assert blk["n_solves"] > 1
    bs = d["bark_sweep"]
    deck = bs["deck_sensitivity_at_floor_row"]["rows"]
    assert [row[0] for row in deck] == sorted(row[0] for row in deck) and any(row[0] == 0.0 for row in deck)
    at0 = next(row for row in deck if row[0] == 0.0)
    assert at0[3] == bs["rule"]["min_crossing_deg"], "the deck family's zero row must reproduce the floor row"
    assert [row[3] for row in deck] == sorted(row[3] for row in deck), "the crossing is expected monotone in the deck on this row — if it stops being, the texts' «±1 mm ≈ 0.2°» need re-reading"
    bt = bs["beyond_thick_end_at_floor_stem"]
    floor_cm = str(round(bs["rule"]["min_crossing_at"][0]["dbh_m"] * 100, 2))
    assert len(bt["rows"]) == 8 and bt["rows"][0][0] > bs["bark_mm_by_dbh_cm"][floor_cm][1] - 1e-9, "the probe past the thick end must start past the FLOOR STEM's thick end"
    ref = bs["rule_floor_refinement"]["at"]
    # the table at the refinement's (fractional) stem: linear between the two grid stems around it, as `bark_by_dbh` derives it
    cm = ref["dbh_m"] * 100
    lo_cm, hi_cm = math.floor(cm + 1e-9), math.ceil(cm - 1e-9)
    ends = [bs["bark_mm_by_dbh_cm"][f"{float(s)}"] for s in (lo_cm, hi_cm)]
    f = 0.0 if hi_cm == lo_cm else (cm - lo_cm) / (hi_cm - lo_cm)
    lo_b, hi_b = (ends[0][k] + f * (ends[1][k] - ends[0][k]) for k in (0, 1))
    assert lo_b - 1e-6 <= ref["bark_mm"] <= hi_b + 1e-6, f"the refinement's node ({ref['bark_mm']} mm at DBH {cm:g}) lies outside the bark table ({lo_b:.3f}–{hi_b:.3f})"
    tab = bs["canon_bark_table"]
    for cm, (thin, thick) in bs["bark_mm_by_dbh_cm"].items():
        if cm in tab["single_bark_ridge_mm_by_dbh_cm"]:
            s = tab["single_bark_ridge_mm_by_dbh_cm"][cm]
            assert abs(thin - (s[0] - tab["live_phloem_mm"]["thin_end"])) < 1e-6 and abs(thick - (s[1] - tab["live_phloem_mm"]["thick_end_reading"])) < 1e-6
    assert bt["thick_end_is_an_edge_not_an_extremum"] == any(row[2] < bs["rule"]["min_crossing_deg"] for row in bt["rows"])
    a36 = bs["tm_back_floor_under_a36_readings"]["span_over_single_readings"]
    assert a36[0] <= a36[1]
    la = bs["loss_at_rule_under_a36_readings"]["span_over_single_readings"]
    assert la[0] <= max(bs["rule"]["loss_at_rule_deg_dB"]["at_crossing_floor"]) + 0.05 and la[0] <= la[1]


def test_stem_radio_shadow_bark_sweep():
    """107's dead-bark sweep (00_07 HW.6; the DBH sweep's review of 2026-10-23): the bark is the third resonant length, so
    the sweep from canon's thin to thick end — not the thin end alone — carries the rule's floor on the «phloem» reading.

    CAN catch: a bark axis whose ends are not the thin/thick table values at a named stem or not linear between them; a
    step above 1 mm; a sweep that skipped a stem, width or deck; a recorded identity miss above zero or fewer thin-end
    rows revisited than the DBH sweep has; a rule block whose floors or attaining rows do not follow from the per-stem
    envelope or the floor table; a dry/wet thick-end floor whose sector is not its crossing's floor. CANNOT catch: a bark
    between two 1 mm steps, a bark outside canon's table, a furrow, or what the 2-D model drops."""
    d = json.loads((RADIO / "stem_radio_shadow.json").read_text(encoding="utf-8"))
    ds, bs = d["dbh_sweep"], d["bark_sweep"]
    assert bs["polarization"] == "TM" and bs["bark_reading"] == "bark_phloem" and bs["step_mm"] <= 1.0
    stems = [float(k) for k in ds["bark_mm_by_dbh_cm"]]
    assert [float(k) for k in bs["bark_mm_by_dbh_cm"]] == stems
    named = sorted(float(k) for k in bs["thick_end_named_stems_mm"])
    assert named == [float(k) for k in ds["bark_named_stems_cm"]]
    for cm, (thin, thick) in bs["bark_mm_by_dbh_cm"].items():
        assert thin == pytest.approx(ds["bark_mm_by_dbh_cm"][cm], abs=1e-9), f"thin end at {cm} is not the DBH sweep's bark"
        assert thick > thin, cm
        if cm in bs["thick_end_named_stems_mm"]:
            assert thick == pytest.approx(bs["thick_end_named_stems_mm"][cm], abs=1e-9)
        else:
            lo = max(x for x in named if x < float(cm))
            hi = min(x for x in named if x > float(cm))
            t_lo, t_hi = bs["thick_end_named_stems_mm"][str(lo)], bs["thick_end_named_stems_mm"][str(hi)]
            assert thick == pytest.approx(t_lo + (t_hi - t_lo) * (float(cm) - lo) / (hi - lo), abs=6e-4), f"thick end at {cm} not linear"
    # the axis per stem: the thin end, every full step below the thick end, the thick end — recounted here from the ends
    def axis_len(thin, thick):
        inner = [thin + i * bs["step_mm"] for i in range(1, int((thick - thin) / bs["step_mm"] + 1e-9) + 1)]
        return 2 + sum(1 for x in inner if x < thick - 1e-6)
    n_bark = sum(axis_len(thin, thick) for thin, thick in bs["bark_mm_by_dbh_cm"].values())
    assert bs["n_bark_values"] == n_bark
    assert bs["n_rows"] == n_bark * len(ds["widths_cm"]) * len(ds["standoffs_mm"]), "a (stem, bark) × width × deck cell was skipped"
    c = bs["controls"]
    assert c["thin_end_rows_reproduce_the_dbh_sweep_max_abs_miss"] == 0.0
    assert c["thin_end_rows_revisited"] == ds["n_stems"] * len(ds["widths_cm"]) * len(ds["standoffs_mm"])
    env = bs["by_dbh"]
    assert [v[0] for v in env["within_3dB_of_front_to_deg"]] == stems
    r = bs["rule"]
    assert r["min_sector_deg"] == min(v[1] for v in env["within_3dB_of_front_to_deg"])
    assert r["min_crossing_deg"] == min(v[1] for v in env["crossing_3dB_deg"])
    assert r["holds_on_1deg_grid"] == (r["min_sector_deg"] >= r["sector_deg"])
    failing = [v[0] for v in env["within_3dB_of_front_to_deg"] if v[1] < r["sector_deg"]]
    assert r["first_stem_cm_failing_on_1deg_grid"] == (failing[0] if failing else None)
    fb = bs["floor_by_dbh"]
    assert fb["columns"] == ["dbh_cm", "bark_mm", "w_cm", "standoff_mm", "sector_deg", "crossing_deg"]
    assert [row[0] for row in fb["rows"]] == stems
    assert min(row[5] for row in fb["rows"]) == r["min_crossing_deg"]
    assert all(row[5] == next(v[1] for v in env["crossing_3dB_deg"] if v[0] == row[0]) for row in fb["rows"])
    for row in fb["rows"]:
        thin, thick = bs["bark_mm_by_dbh_cm"][str(row[0])]
        assert thin - 1e-9 <= row[1] <= thick + 1e-9
    assert {a["bark_mm"] for a in r["min_crossing_at"]} <= {row[1] for row in fb["rows"]}
    sp = bs["rule_floor_under_a36_readings"]
    singles = {k: v for k, v in sp["by_reading"].items() if k.startswith("single_reading_")}
    assert len(singles) == 4 and sp["span_over_single_readings"] == [min(singles.values()), max(singles.values())]
    for b, v in bs["thick_end_dry_wet"].items():
        assert b in ("bark_dry", "bark_wet") and v["n_rows"] == ds["n_stems"] * len(ds["widths_cm"]) * len(ds["standoffs_mm"])
        assert v["min_sector_deg"] == math.floor(v["min_crossing_deg"] + 1e-9) or v["min_sector_deg"] == math.floor(v["min_crossing_deg"])


def test_stem_radio_shadow_width_sweep():
    """107's sapwood-width sweep (00_07 HW.6; the adversarial review of 2026-10-22, F1): the width is a resonant input,
    so the sweep — not the three named widths — carries each consumer's extreme.

    CAN catch: an axis that no longer reaches the measured ends (Björklund 1999's 22 mm, the cache's own thin reading;
    past ≈ 13.4 cm, Bieker & Rust 2010 Fig. 2's widest radius); a step that is not much finer than half the sapwood's
    in-medium wavelength; a sweep that skipped a named width or a bark × stem × standoff × polarization cell; a
    recorded reproduction miss above zero; an extreme that is not the extreme of the per-width envelope it sits beside,
    or whose attaining rows do not carry it; a named reading's row outside the sweep's span at its own width. CANNOT
    catch: an extreme BETWEEN two grid widths (the step is its ground), a wrong input, or what the 2-D model drops.
    """
    d = json.loads((RADIO / "stem_radio_shadow.json").read_text(encoding="utf-8"))
    sw = d["width_sweep"]
    thin_cm = round(d["readings"]["permittivity"]["scots_sapwood_2cm_bark_dry"]["sapwood_width_m"] * 100, 2)
    assert sw["axis_cm"][0] <= thin_cm, "the axis starts above the thinnest measured stem"
    assert sw["axis_cm"][1] >= 13.4, "the axis stops short of Bieker & Rust's widest radius (Fig. 2, ≈ 13.4 cm)"
    assert sw["step_cm"] <= 0.2 and sw["step_cm"] <= sw["half_wavelength_cm"] / 10
    assert sw["controls"]["named_widths_reproduce_the_readings_max_abs_miss"] == 0.0
    named = {round(r["sapwood_width_m"] * 100, 2) for n, r in d["readings"]["permittivity"].items()
             if n.startswith("scots_sapwood_")}
    assert named <= set(sw["named_widths_cm"]), "a named width is not in the sweep"
    cells = len(d["readings"]["geometry"]["dbh_m"]["values"]) * len(d["readings"]["geometry"]["standoff_m"]["values"])
    assert sw["n_rows"] == sw["n_widths"] * 3 * 2 * cells, "the sweep skipped a bark, stem, standoff or polarization cell"
    for pol, by_key in sw["by_width"].items():
        for key, env in by_key.items():
            assert len(env) == sw["n_widths"]
            e = sw["extremes"][pol][key]
            assert e["min"] == min(v[1] for v in env) and e["max"] == max(v[2] for v in env), f"{pol} {key}"
            assert {a["w_cm"] for a in e["min_at"]} == {v[0] for v in env if v[1] == e["min"]}, f"{pol} {key} min_at"
            assert {a["w_cm"] for a in e["max_at"]} == {v[0] for v in env if v[2] == e["max"]}, f"{pol} {key} max_at"
            at = {v[0]: v for v in env}
            for r in d["cases"]:
                if r["polarization"] == pol and r["permittivity"].startswith("scots_sapwood_"):
                    w = round(d["readings"]["permittivity"][r["permittivity"]]["sapwood_width_m"] * 100, 2)
                    assert at[w][1] <= r[key] <= at[w][2], f"{r['permittivity']} {pol} {key} outside the sweep at {w}"
