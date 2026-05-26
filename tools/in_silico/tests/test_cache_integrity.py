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


def test_dft_comparison_json():
    path = DFT / "comparison.json"
    assert path.exists()
    data = json.loads(path.read_text())
    assert "donor_homo_eV" in data
    assert "acceptor_lumo_eV" in data
    assert "delta_eV" in data


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


# ── Constants consistency ──

def test_constants_importable():
    """Verify shared constants module can be imported."""
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import (
        GAFF_VERSION, F_CONST, R_GAS, HARTREE_TO_EV,
        BASELINE_DELTA_T_S, J_MAX_25C, KM_GLUCOSE,
    )
    assert GAFF_VERSION == "gaff-2.11"
    assert abs(F_CONST - 96485.33) < 1
    assert abs(R_GAS - 8.314) < 0.01
    assert abs(HARTREE_TO_EV - 27.211) < 0.01
    assert BASELINE_DELTA_T_S == 60
    assert abs(J_MAX_25C - 494e-6) < 1e-6
    assert KM_GLUCOSE == 20.0


# ── Constants vs documentation consistency ──

def test_constants_match_kinetics_output():
    """Verify constants.py values are used in kinetics output."""
    import sys
    sys.path.insert(0, str(REPO / "tools/in_silico"))
    from lib.constants import J_MAX_25C, KM_GLUCOSE, BASELINE_DELTA_T_S

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
    from lib.geometry import positions_to_nm_array, place_on_sphere, restraint_protein_heavy_atoms
    from lib.utils import banner, ps_to_steps, pick_platform
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
]


@pytest.mark.parametrize("script", EXPECTED_SCRIPTS)
def test_script_exists(script):
    path = REPO / "tools/in_silico/scripts" / script
    assert path.exists(), f"Missing script: {script}"
    assert path.stat().st_size > 500, f"Script too small: {script}"
