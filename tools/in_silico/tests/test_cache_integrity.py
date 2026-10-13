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


@pytest.mark.parametrize("name", ["iefpcm", "uffcavity", "gas"])
def test_os_mediator_series_continuum_variant_is_derived_from_both_caches(name):
    """21e's continuum variants (2026-10-11, 00_07 HW.5.IS leg 2): each point accepted (converged, aufbau, <S²> ≤
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
    """Script 51 outputs V/Al release per candidate alloy (Stage-2 bake-off, 01_02 §2.5).
    Sanity: 4V control ≈ 1.12 µg/cm²/yr V (the in-silico baseline — order of magnitude on an unsourced D, 01_02 §2.5);
    every V-free alloy releases ~0."""
    path = KINETICS / "gusak_degradation.json"
    if not path.exists():
        pytest.skip("gusak_degradation.json not computed")
    kd = json.loads(path.read_text())["kirkendall_diffusion"]
    for alloy in ALLOY_SKUS:
        assert alloy in kd, f"missing alloy {alloy}"
        assert "20" in kd[alloy] and "V_ug_cm2" in kd[alloy]["20"]
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
    coefficient × the daily range; the tolerated radome lead leaving margin / stack coefficient. CANNOT catch: the daily
    range itself (it needs 71's hourly run — the script checks 71 against its own cache), the gasket and pin-body terms
    (not computed), or the stack's centring.
    """
    path = MECHANICAL / "pogo_thermal_gap.json"
    if not path.exists():
        pytest.skip("pogo_thermal_gap.json not computed")
    from lib.constants import ALPHA_FR4_Z_1K, ALPHA_PEEK_1K, ALPHA_SS302_1K, ALPHA_STEEL_MILD_1K
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
           "gradient_bound_radome_only": radome_k}
    for k, v in gap.items():
        assert abs(co["gap"][k] - v) <= 1e-4, k
    assert gap["isothermal_low_stack"] < gap["isothermal_high_stack"] < gap["gradient_bound_radome_only"]
    t_asm = c82["inputs"]["t_ref_c"]
    travel, win, nom = inp["pogo_travel_mm"], inp["window"], inp["nominal_pct"]
    mitig = {m["label"]: m["residual_pz"] for m in z52["mitigation_escalation"]}
    assert inp["mitigation_residual_mm_52"] == mitig
    for rname, (t_min, t_max) in inp["temperature_readings_c"].items():
        for cname, v in d["seasonal"][rname].items():
            cold, hot = -gap[cname] * (t_asm - t_min), gap[cname] * (t_max - t_asm)
            assert abs(v["gap_um_cold"] - cold) <= 0.06 and abs(v["gap_um_hot"] - hot) <= 0.06, (rname, cname)
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
            assert abs(v["stroke_um"] - gap[cname] * rng[st]) <= 0.02, (cname, st)
            assert abs(v["force_ratio_over_min_preload"] - gap[cname] * rng[st] * 1e-3 / inp["x_preload_min_mm"]) <= 1e-4
    for k, per in d["radial_slide_daily_um_per_mm_radius"].items():
        for st, v in per.items():
            assert abs(v - d["radial_slide_um_per_mm_radius_per_K"][k] * rng[st]) <= 0.002, (k, st)
    req = d["seasonal"]["capsule_requirement"]
    margin = min(min(req[c]["window"]["L1 spacer only"]["margin_um"]) for c in ("isothermal_low_stack", "isothermal_high_stack"))
    assert abs(d["radome_lead_tolerated_by_L1_K"] - margin / stack_hi) <= 0.1

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
      5. the ratified point (Q6, ⚖️ 2026-09-17) is what its derivation says — no oxalate, the other four at the
         geometric mid of the pre-verdict range — and prices a preparable medium: base positive and larger at the
         higher pH, potassium = KNO3 + base, gypsum undersaturated, buffer capacity positive.
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
    q6 = d["q6_ratified_point"]
    assert q6["recipe_mM"]["oxalic"] == 0.0, "the verdict removed oxalate"
    for key, (lo, hi) in d["recipe_ranges_mM"].items():
        if key != "oxalic":
            assert q6["recipe_mM"][key] == float(f"{math.sqrt(lo * hi):.2g}"), f"{key}: not the geometric mid"
    for name, c in q6["conditions"].items():
        base_lo, base_hi = c["base_koh_mM"]
        assert 0.0 < base_lo <= base_hi, name
        for k_total, base in zip(c["potassium_total_mM"], c["base_koh_mM"], strict=True):
            assert abs(k_total - (base + q6["recipe_mM"]["kno3"])) < 2e-3, f"{name}: K+ total ≠ KNO3 + base"
        assert c["si_gypsum_max"] < 0.0 and c["buffer_capacity_mM_per_pH_25c"] > 0.0, name
    setpoint, side = q6["conditions"]["setpoint"], q6["conditions"]["side_series"]
    assert setpoint["ph"] > side["ph"] and setpoint["base_koh_mM"][0] > side["base_koh_mM"][1], \
        "more malic acid is dissociated at the higher pH, so it must take more base"
    assert (CHEMISTRY / "sap_recipe_saturation.png").stat().st_size > 10_000


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
    """B2 (OS-RECOMPUTE): adiabatic ΔSCF generator — uphill dimethyl cascade, EA drift-safe
    from B1; vertical exceeds adiabatic (cation geometric relaxation)."""
    path = DFT / "delta_scf_corrections.json"
    if not path.exists():
        pytest.skip("B2 cache missing")
    d = json.loads(path.read_text())
    assert d["geom_opt_converged"]["FADH2"] and d["geom_opt_converged"]["FADH2_cation"]
    assert 0.5 < d["dG_adiabatic_eV"] < 1.5, "adiabatic ΔG out of physical range"
    assert d["dG_vertical_eV"] > d["dG_adiabatic_eV"], "vertical must exceed adiabatic"
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
    """Tunneling pathway should find a route with β·d < 5."""
    path = DFT / "tunneling_pathway.json"
    if not path.exists():
        pytest.skip("tunneling pathway not computed")
    data = json.loads(path.read_text())
    assert data["path_atoms"] > 0
    assert data["effective_beta_d"] < 5.0


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
        assert m["f_pH6_by_film"]["stagnant"][0] < m["f_pH6_by_film"]["Levich"][0] < m["f_pH6_by_film"]["transient"][0], name
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
