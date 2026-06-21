"""Shared physical and project constants for the in-silico pipeline."""
from pathlib import Path

# ── Project paths ──
# lib/constants.py → tools/in_silico/lib/ → parents[3] = repo root
REPO_ROOT = Path(__file__).resolve().parents[3]
LIGANDS_DIR = REPO_ROOT / "docs/protocols/ebfc/in_silico/ligands"
CACHE_DIR = REPO_ROOT / "tools/in_silico/cache"
DFT_CACHE = CACHE_DIR / "dft"
KINETICS_DIR = CACHE_DIR / "kinetics"
RUNS_DIR = CACHE_DIR / "runs"
CACHE_FILE = CACHE_DIR / "gaff_cache.json"
AF3_PDB = REPO_ROOT / "docs/protocols/ebfc/in_silico/dgrGcGDH_AF3.pdb"
PAPER_DIR = REPO_ROOT / "docs/protocols/ebfc/in_silico/paper"
PAPER_FIG_DIR = PAPER_DIR / "figures"

# ── Force field ──
GAFF_VERSION = "gaff-2.11"

# ── Physical constants (CODATA 2018) ──
F_CONST = 96485.33289        # C/mol — Faraday constant
R_GAS = 8.31446261815324     # J/(mol·K) — gas constant
HARTREE_TO_EV = 27.211386245988
BOHR_TO_ANG = 0.529177249

# ── Xylem environment (01_03 §3.5) ──
PH = 4.5
IONIC_STRENGTH = 0.05        # M — NaCl
TEMPERATURE_K = 298.15       # K — reference temperature
PRESSURE_ATM = 1.0
WATER_PADDING_NM = 1.0       # nm around protein

# ── MD parameters ──
TIMESTEP_FS = 2.0
EQUIL_NVT_PS = 50
EQUIL_NPT_PS = 100

# ── Ligand counts (Gen 2.0 matrix) ──
N_GENIPIN = 10
N_CHITOSAN = 5
N_CELLOBIOSE = 8

# ── DFT basis sets ──
BASIS_LIGHT = "6-31g(d)"
BASIS_OS = "lanl2dz"
ECP_OS = "lanl2dz"
SOLVENT_EPS_WATER = 78.3553

# ── EBFC parameters (from literature, 01_03 §1) ──
J_MAX_25C = 494e-6           # A/cm² — dgrGcGDH + Os-polymer (Zafar 2012, PMC3275720)
KM_GLUCOSE = 20.0            # mM — estimated for GcGDH
EA_ENZYME = 40_000.0         # J/mol — Arrhenius activation energy (typical FAD enzyme)
V_OP = 0.5                   # V — EBFC operating voltage under load
A_ELECTRODE = 2.0            # cm² — effective electroactive area
ETA_BQ = 0.85                # BQ25570 boost efficiency (TI SLUSBH2G)
E_CYCLE = 5e-3               # J — energy per MCU wake cycle
BASELINE_DELTA_T_S = 60      # s — firmware baseline (bio_contract.rb)

# ── Glucose diffusion ──
D_EFF_GLUCOSE = 2e-6         # cm²/s — through chitosan/Nafion matrix (literature)
DELTA_MEMBRANE = 20e-4       # cm (20 µm) — Layers 4+5 thickness
N_ELECTRONS = 2              # electrons per glucose (FAD → FADH₂)

# ── Cascade anchors (experimental E°, verified — the AUTHORITATIVE cascade verdict;
#    raw DFT is uphill = the decomposed method limit, ②). One-Home: SUMMARY/L3/paper link here.
# Os mediator [Os(4,4'-dimethyl-bpy)₂(PVI)Cl]⁺: E°'=+21 mV vs Ag/AgCl(0.1M KCl) +288 mV
#   = +309 mV vs NHE (Zafar et al. 2012, Anal. Chem. 84, 334, doi:10.1021/ac202647z — the
#   best-performing of six Os polymers, +15…+489 mV window, wired to GcGDH).
# FAD-GDH bound FAD: −265 mV vs SHE (Schachinger, Ma, Ludwig 2023, Electrochem. Commun. 146, 107405).
E_OS_MEDIATOR_MV_NHE = 309        # was a +200 mV under-specified anchor pre-OS-RECOMPUTE
E_FAD_GDH_MV_SHE = -265
OS_DEVICE_MEDIATOR_LIGAND = "4,4'-dimethyl-2,2'-bipyridine"  # os_complex.json identity (21f = sole owner)
CASCADE_DRIVING_FORCE_MV = E_OS_MEDIATOR_MV_NHE - E_FAD_GDH_MV_SHE   # +574 mV (−0.574 eV downhill)

# ── Structural alloy candidates — Stage-2 coin bake-off (01_02 §2.5, HW.24) ──
# Composition (wt%) + mechanical/thermal props feeding the V/Al-release (script 51) + Lamé (script 50)
# comparative. Literature/ASTM implant specs. The oxide-diffusion D_V/D_Al stays a SHARED constant in
# script 51 (per-alloy oxide-diffusion is rarely published → the COMPOSITION effect dominates: 4% V → V
# release, 0% V → none). Tree-first (01_04 §4.2): V + Al are phytotoxic in acidic sap; Nb/Zr/Ta are
# bioinert (their release is informational, not a pass/fail gate). Baseline stays 4V — the coin
# down-selects the rest (no-premature-canon, 01_02 §2.5).
ALLOY_BASELINE = "Ti-6Al-4V"
ALLOY_PROPERTIES = {
    "Ti-6Al-4V": {
        "spec": "ASTM F136 (control / print reference)",
        "V_wt": 4.0, "Al_wt": 6.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 110.0, "nu": 0.33, "alpha_1K": 8.6e-6, "yield_MPa": 880.0, "rho_kg_m3": 4430.0,
    },
    "Ti-6Al-7Nb": {
        "spec": "ASTM F1295 (V-free, direction a)",
        "V_wt": 0.0, "Al_wt": 6.0, "Nb_wt": 7.0, "Zr_wt": 0.0,
        "E_GPa": 103.0, "nu": 0.31, "alpha_1K": 8.4e-6, "yield_MPa": 850.0, "rho_kg_m3": 4520.0,
    },
    "CP-Ti-Gr4": {
        "spec": "ASTM F1581 (zero V/Al, alpha-Ti)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 104.0, "nu": 0.34, "alpha_1K": 8.6e-6, "yield_MPa": 480.0, "rho_kg_m3": 4510.0,
    },
    "beta-Ti-13Nb-13Zr": {
        "spec": "ASTM F1713 (low-E V/Al-free)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 13.0, "Zr_wt": 13.0,
        "E_GPa": 80.0, "nu": 0.33, "alpha_1K": 8.8e-6, "yield_MPa": 900.0, "rho_kg_m3": 5050.0,
    },
    "Ta": {
        "spec": "ASTM F560 (bioinert benchmark; coin-only, heavy)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 186.0, "nu": 0.34, "alpha_1K": 6.5e-6, "yield_MPa": 345.0, "rho_kg_m3": 16650.0,
    },
    "Ti-15Zr": {
        "spec": "ASTM F2066-class (Roxolid; V/Al-free, high-strength)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 15.0,
        "E_GPa": 100.0, "nu": 0.33, "alpha_1K": 8.5e-6, "yield_MPa": 950.0, "rho_kg_m3": 4800.0,
    },
}
