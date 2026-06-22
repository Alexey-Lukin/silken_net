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
# + bus thermal bridge (script 54) comparative. Literature/ASTM implant specs. The oxide-diffusion
# D_V/D_Al stays a SHARED constant in script 51 (per-alloy oxide-diffusion is rarely published → the
# COMPOSITION effect dominates: 4% V → V release, 0% V → none). Tree-first (01_04 §4.2): V + Al are
# phytotoxic in acidic sap; Nb/Zr/Ta are bioinert (their release is informational, not a pass/fail
# gate). Baseline stays 4V — the coin down-selects the rest (no-premature-canon, 01_02 §2.5).
# lambda_W_mK = RT thermal conductivity (for the monolithic-bus thermal bridge, script 54/HW.34):
# alloyed α+β Ti scatter phonons → low λ ~7; pure CP-Ti ~2.5× higher; Ta (refractory) ~8× higher; all
# ≪ Cu 400. (β-Ti-13Nb-13Zr / Ti-15Zr λ are literature ESTIMATES — heavily-alloyed β/Zr, sparse data;
# the RANKING 4V≈7Nb≈β≈15Zr < CP-Ti < Ta ≪ Cu is robust to ±20%.)
ALLOY_BASELINE = "Ti-6Al-4V"
ALLOY_PROPERTIES = {
    "Ti-6Al-4V": {
        "spec": "ASTM F136 (control / print reference)",
        "V_wt": 4.0, "Al_wt": 6.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 110.0, "nu": 0.33, "alpha_1K": 8.6e-6, "yield_MPa": 880.0, "rho_kg_m3": 4430.0,
        "lambda_W_mK": 6.7,
    },
    "Ti-6Al-7Nb": {
        "spec": "ASTM F1295 (V-free, direction a)",
        "V_wt": 0.0, "Al_wt": 6.0, "Nb_wt": 7.0, "Zr_wt": 0.0,
        "E_GPa": 103.0, "nu": 0.31, "alpha_1K": 8.4e-6, "yield_MPa": 850.0, "rho_kg_m3": 4520.0,
        "lambda_W_mK": 7.0,
    },
    "CP-Ti-Gr4": {
        "spec": "ASTM F1581 (zero V/Al, alpha-Ti)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 104.0, "nu": 0.34, "alpha_1K": 8.6e-6, "yield_MPa": 480.0, "rho_kg_m3": 4510.0,
        "lambda_W_mK": 17.0,
    },
    "beta-Ti-13Nb-13Zr": {
        "spec": "ASTM F1713 (low-E V/Al-free)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 13.0, "Zr_wt": 13.0,
        "E_GPa": 80.0, "nu": 0.33, "alpha_1K": 8.8e-6, "yield_MPa": 900.0, "rho_kg_m3": 5050.0,
        "lambda_W_mK": 7.5,   # estimate — β-Ti(Nb,Zr) heavily alloyed, sparse data
    },
    "Ta": {
        "spec": "ASTM F560 (bioinert benchmark; coin-only, heavy)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 186.0, "nu": 0.34, "alpha_1K": 6.5e-6, "yield_MPa": 345.0, "rho_kg_m3": 16650.0,
        "lambda_W_mK": 57.0,
    },
    "Ti-15Zr": {
        "spec": "ASTM F2066-class (Roxolid; V/Al-free, high-strength)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 15.0,
        "E_GPa": 100.0, "nu": 0.33, "alpha_1K": 8.5e-6, "yield_MPa": 950.0, "rho_kg_m3": 4800.0,
        "lambda_W_mK": 8.0,   # estimate — Ti-Zr solid-solution scattering, sparse data
    },
}

# ── Anchor Ti↔PEEK press-fit & thermal stress (HW.3.IS, frozen Ø11/2 mm — 01_01 §4.2) ──
# PEEK 450G sleeve press-fit on a Ti shaft. Ti props (α/E/ν/yield) live in ALLOY_PROPERTIES
# (per-alloy, baseline = Ti-6Al-4V); this block is the PEEK counterpart + the frozen coaxial
# geometry + assembly temp + the H7/s6 band. Consumed by scripts 50/51 (legacy partials) and
# the unified thick-wall Lamé (script 56 + lib.mechanics).
ALPHA_PEEK_1K = 47e-6            # 1/K — PEEK 450G CTE (5.5× Ti)
E_PEEK_PA = 4.0e9               # Pa — PEEK 450G Young's modulus (Victrex 450G datasheet, 23°C)
NU_PEEK = 0.40                  # — PEEK Poisson's ratio
SIGMA_YIELD_PEEK_PA = 100e6     # Pa — PEEK 450G tensile yield (~98-100 MPa)

# Frozen coaxial geometry (HW.33, 2026-06-20): Ti shaft Ø11 → interface r 5.5 mm;
# PEEK wall 2 mm → outer r 7.5 mm (OD = wound Ø15). Outer surface sits in the tree (free).
R_INTERFACE_M = 5.5e-3          # m — Ti↔PEEK press-fit contact radius (Ø11 shaft / 2)
R_OUTER_M = 7.5e-3             # m — PEEK sleeve outer radius (Ø15 wound / 2)
T_ASSEMBLY_C = 20.0            # °C — press-fit assembly temperature
T_FOREST_MIN_C = -30.0         # °C — Cherkasy winter extreme (worst case for PEEK hoop)
T_FOREST_MAX_C = 40.0          # °C — summer extreme (worst case for sealing)

# H7/s6 interference band (ISO 286, Ø11 in the 10-18 mm size band: H7 0/+18 µm, s6 +23/+34 µm
# → 5-34 µm DIAMETRAL). The Lamé contact pressure takes RADIAL interference = diametral / 2.
H7S6_INTERF_DIA_MIN_UM = 5.0    # µm — min diametral interference (governs sealing)
H7S6_INTERF_DIA_MAX_UM = 34.0   # µm — max diametral interference (governs hoop stress)
