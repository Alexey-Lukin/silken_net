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
