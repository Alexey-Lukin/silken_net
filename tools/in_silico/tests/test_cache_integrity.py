# SPDX-License-Identifier: AGPL-3.0-or-later
"""
Verify integrity of committed in-silico cache and ligand files.

Runs without conda env — uses only stdlib + json. Safe for CI.
"""
import json
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
LIGANDS = REPO / "docs/protocols/ebfc/in_silico/ligands"
CACHE = REPO / "tools/in_silico/cache"
DFT = CACHE / "dft"
KINETICS = CACHE / "kinetics"
MECHANICAL = CACHE / "mechanical"


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
    Sanity: 4V control ≈ 1.12 µg/cm²/yr V (the 56× baseline); every V-free alloy releases ~0."""
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
    """Script 51 (HW.37) outputs EDLC endurance-hours life for both canon-cited SKUs
    (Eaton KR-5R5H474-R, KEMET FG0H474ZF — `02_01 §3` поз.3). Sanity: confirms the
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
    rows = iw["od_growth_eats_channel_play"]["rows"]
    assert rows, "the play coupling lost its rows"
    assert all(r["outer_surface_still_free"] for r in rows), \
        "OD growth closed the channel play — free-outer Lamé no longer describes this pair"
    assert all(r["channel_radial_play_um"] > 0.0 for r in rows)
    # 4. The nominal finding is the headline and it is a BOOLEAN, so it cannot rot into prose: the
    #    specified fit is line-to-line, which is why landing in the window is a verdict, not a
    #    tolerance. If a nominal interference is ever ratified this flips, and the sentence canon
    #    carries about «half the population comes out with clearance» must go with it.
    assert iw["nominal_fit_is_zero_interference"] is True
    assert iw["required_nominal_offset_diametral_um"] > 0.0


# The insulation branch the ⚖️ 2026-09-11 verdict ratified. Named once: the assertions below
# are about THAT branch, not about whichever row happens to be first.
SHIPPED_INSULATION = "PEEK liner 0.15 mm"


def test_bus_mechanical_weld_seam():
    """Script 55 (HW.34): the seam at the root is BOUNDED, never assumed.

    The point of the block is that its input is missing, so the first assertion is the honesty
    one — nobody may quietly type a knockdown into the sentinel and let the rest of the corpus
    read it as measured. The rest pin the RELATION the bound rests on (SF_seam = k·SF_wire) and
    the direction of the two corrections; a model whose worst corner is not harsher than its
    nominal is measuring nothing.
    """
    path = MECHANICAL / "bus_mechanical.json"
    if not path.exists():
        pytest.skip("bus_mechanical.json not computed")
    d = json.loads(path.read_text())
    seam = d["weld_seam"]
    fm = d["fatigue_model"]
    # 1. The input stays absent, and the two flags say WHICH half exists. ⛔ A single boolean
    #    cannot: the geometry is unmodelled while the sensitivity is, and flipping one flag to
    #    cover both is how a surface splits into halves that disagree.
    assert seam["knockdown_k_measured"] is None, "a knockdown was typed in — it is NOT MEASURED"
    assert fm["weld_seam_geometry_modelled"] is False
    assert fm["weld_seam_sensitivity_modelled"] is True
    assert fm["mean_stress_correction_modelled"] is False
    # 2. Priced on the span that exists. ⛔ This used to assert the list is EMPTY, and the protrusion
    #    correction (2026-09-12) made that false WITHOUT touching the verdict: at the true 23 mm span
    #    the rod is stiffer, so the two REJECTED conformal branches stop reaching the wall and enter
    #    that list. What the verdict rests on is narrower and is what is pinned — the SHIPPED branch
    #    still bears, i.e. its free-cantilever SF still describes nothing.
    assert SHIPPED_INSULATION not in d["clearance_regime"]["free_cantilever_sf_describes_these"]
    assert SHIPPED_INSULATION in d["clearance_regime"]["gap_limited_branches"]
    assert "supported" in seam["span"]["which"]
    assert seam["span"]["worst_corner_sigma_MPa"] > seam["span"]["nominal_sigma_MPa"]
    # 3. The SPAN the bound rides. A `protrusion_sensitivity` block stood here and swept two spans,
    #    because one of them was a literal under open correction; the correction landed 2026-09-12
    #    and the sweep went with it. What must not drift is the span's PROVENANCE: the seam bound
    #    inherits the protrusion through the optimism term, so a block quoting a protrusion that no
    #    longer matches the geometry block is the failure this pins.
    prov = seam["span_provenance"]
    assert prov["protrusion_mm"] == d["geometry_mm"]["free_len_unsupported"], \
        "the seam block and the geometry block disagree about the protrusion"
    assert "cem/" in prov["derived_from"], "the span stopped being CEM-derived"
    assert seam["span"]["span_optimism_pct"] > 0.0
    # 4. The binding candidate must be a real alloy of the table.
    assert seam["binding_candidate"]["alloy"] in {r["alloy"] for r in seam["per_alloy"]}
    # 5. The edge-bearing block feeds the OPEN axial verdict, so it must stay wired to the geometry
    #    it reasons about: the mouth it uses IS the channel start, and it must cover every branch the
    #    regime table carries. A block that silently drops a branch would answer the verdict for a
    #    shorter list than the one the reader sees.
    edge = d["clearance_regime"]["edge_bearing"]
    assert edge["mouth_mm"] == d["clearance_regime"]["channel"]["start_mm"], \
        "edge_bearing measures from a different mouth than the channel block declares"
    assert {r["branch"] for r in edge["rows"]} == {r["branch"] for r in d["clearance_regime"]["branches"]}
    # and the flag must be DERIVED from the per-µ rows, never typed
    for row in edge["rows"]:
        assert row["edge_bearing_on_any_mu"] == any(v["edge_bearing"] for v in row["by_mu"].values())
    # 5. Both markers are OUR OWN numbers, so they must still match the model they came from.
    markers = {m["label"]: m["k"] for m in seam["markers"]}
    assert fm["as_printed_derate"] in markers.values()
    assert fm["wrought_derate"] in markers.values()


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
        KM_GLUCOSE,
        R_GAS,
    )
    assert GAFF_VERSION == "gaff-2.11"
    assert abs(F_CONST - 96485.33) < 1
    assert abs(R_GAS - 8.314) < 0.01
    assert abs(HARTREE_TO_EV - 27.211) < 0.01
    assert BASELINE_DELTA_T_S == 60
    assert abs(J_MAX_25C - 494e-6) < 1e-6
    assert KM_GLUCOSE == 20.0


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
    """Proton-reference PCET must land within 100 mV of free-flavin exp (pH 7)."""
    path = DFT / "pcet_redox_potential.json"
    if not path.exists():
        pytest.skip("PCET not computed")
    data = json.loads(path.read_text())
    assert data["valid_proton_reference"] is True
    assert abs(data["delta_vs_exp_pH7_mV"]) < 100
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
    """Verify constants.py values are used in kinetics output."""
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import BASELINE_DELTA_T_S, J_MAX_25C, KM_GLUCOSE

    data = json.loads((KINETICS / "delta_t_lookup.json").read_text())
    assert data["parameters"]["j_max_25C_uA_cm2"] == J_MAX_25C * 1e6
    assert data["parameters"]["Km_mM"] == KM_GLUCOSE
    assert data["parameters"]["BASELINE_DELTA_T_S"] == BASELINE_DELTA_T_S


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
    assert spruce["ph"] < pine["ph"], "Spruce should be more acidic than pine"


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
    # The anchor-mechanics block, complete: this list looked full while 52/54/55/56 had never
    # been added, so it grew selectively and read as an inventory.
    "50_thermal_stress_lame.py",
    "51_gusak_degradation_model.py",
    "52_z_stack_tolerance.py",
    "53_oxide_det_per_alloy.py",
    "54_anchor_thermal_bridge.py",
    "55_bus_mechanical.py",
    "56_unified_press_fit_lame.py",
    "57_gdl_breakthrough.py",
    "58_thermal_install_field.py",
]


@pytest.mark.parametrize("script", EXPECTED_SCRIPTS)
def test_script_exists(script):
    path = REPO / "tools/in_silico/scripts" / script
    assert path.exists(), f"Missing script: {script}"
    assert path.stat().st_size > 500, f"Script too small: {script}"
