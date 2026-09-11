# SPDX-License-Identifier: AGPL-3.0-or-later
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
# Water model — One-Home (кожен MD-скрипт ЧИТАЄ це, не хардкодить XML/ярлик
# інлайн, інакше load↔label дрейфують). Свідомо TIP3P-**FB** (Wang, Martínez,
# Pande 2014, JPCL 5:3863 — force-balance reparametrizація TIP3P: краща
# густина/діелектрик/D_self за той самий 3-site функціонал). ⚠️ ff14SB
# номінально параметризований на класичному TIP3P; FB широко паровано з ним,
# розбіжність = bulk-water properties, не protein-specific (для EBFC-enzyme
# MD прийнятно) — але це ЯВНИЙ вибір, не мовчазний default.
WATER_MODEL_XML = "amber14/tip3pfb.xml"
WATER_MODEL_LABEL = "TIP3P-FB"

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
# ⛔ This number is ALREADY Gen 2.0, and that closes an argument people keep reaching for. The
# ratified network topology costs 1.88× of the electroactive area (00_07 HW.33, ⚖️ 2026-09-10), and
# "we compensate the area with a better enzyme" is NOT available: since 30_kinetics_delta_t is
# kinetics-limited across its whole range, area passes into current without saturating, so covering
# 1.88× needs j_max to reach 929 µA/cm² — i.e. the compensation would have to be paid by the very
# figure written above. Raise this constant only against a NEW measured couple, never to balance a
# geometry decision. [migrated from 00_07 HW.33 on 2026-09-11 — the break-even lived only in the
#  tracker, while the constant it prices sits here, where a reader is tempted to "improve" it.]
KM_GLUCOSE = 20.0            # mM — estimated for GcGDH
EA_ENZYME = 40_000.0         # J/mol — Arrhenius activation energy (typical FAD enzyme)
V_OP = 0.5                   # V — EBFC operating voltage under load
A_ELECTRODE = 2.0            # cm² — ONE face of the Ø16×1 mm Ti-coin COUPON (π·8² =
# 2.01 cm²), never the anchor. Canon home docs/01_01 §6 ties the number to that face and
# normalises j on the PROJECTED geometric area, because EAAE roughness r=10-50× makes the
# real area unmeasurable (docs/01_02 §1.4). The Zone-1 gyroid anode is a different body by
# 30-60×: the CAD `SpecificSurface` proxy puts it at 65-123 cm² depending on topology.
# So every ABSOLUTE number derived from this constant is a coupon prediction, and the
# Stage-2 coin is exactly what it is meant to be compared against. [E.63, 2026-09-11]
ETA_BQ = 0.68                 # BQ25570 boost efficiency at P_EBFC≈15 µW — mirror of
# docs/02_03 §9.1 table (source of truth; edit there, not here). [HW.47, 2026-09-09]
# 0.85 was an unvalidated orphan value with no table/citation; SLUSBH2G Figures 6-7
# (Charger Efficiency vs Input Current, VIN=0.5V/0.2V) put I_IN≈15-46µA solidly on the
# steep low-current rise of the curve — eyeball range ~45-80% across the plotted VSTOR
# curves, i.e. clearly below 0.85 and roughly consistent with 0.68. Precision residual
# [HW.46, measured 2026-09-10]: the 15µW/325mV anchor is NOT a physical EBFC number —
# 325 mV = 0.65 × 500 mV (MPPT fraction × the retired «V_OC ≥ 500» claim) and 15 µW has
# no traceable source (born with the rest of 02_03 §9 in the initial commit; equals
# P_IN(CS) TYP). V_OP above (0.5 V) is the OTHER model's guess (≈0.65 × 0.77 V OCV).
# Both wait for the HW.13 bench P-V curve — do not reconcile them by editing either.
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
# + bus thermal bridge (script 54) comparative. The `spec` field is DOCUMENTATION-ONLY — no script
# reads it — but it DOES reach a vendor, via the RFQ tables and the CEM notes that print on the
# factory drawing, so it is held to the Validation Gate (00_06 §0) like any other outbound claim.
# 🔴 Every designation below was read against the standard's OWN SCOPE on 2026-09-11 (HW.24), and two
# were not what they claimed. ⛔ Do not restore either without re-reading the standard:
#   · `F1581` stood on CP-Ti Gr4 and is not a titanium standard at all — "Composition of Anorganic
#     Bone for Surgical Implants", a bone-derived apatite with zero Ti. CP-Ti is F67 (Gr4 = R50700).
#   · `F2066-class` stood on Ti-15Zr and is Ti-15 MOLYBDENUM (R58150). The 15 collides, the element
#     does not. No ASTM/ISO specification for binary Ti-Zr exists, AM or wrought — Roxolid is a
#     Straumann proprietary alloy, so that row has no standard to name and says so.
# ⛔ And the earlier fix on this same axis STANDS — do not "correct" the 4V row back to `F136`: that is
#   the ELI (Grade 23) spec, this row is the Grade-5 control, and 01_02 §2.5 chose V-free explicitly
#   NOT ELI. F136 is now confirmed WROUGHT as well, so it fails both axes for a printed Gr5 coupon.
# ⚠️ SECOND AXIS, and it is the one that survives the two fixes: we order laser powder-bed fusion, and
# ASTM publishes an AM MATERIAL spec for Ti-6Al-4V only (F2924 Gr5 / F3001 ELI). F1295 · F67 · F1713 ·
# F560 all carry "Wrought" in their own titles, so for those alloys the row is a COMPOSITION reference,
# never a print spec — an AM order stacks it with feedstock, process and acceptance callouts, which is
# a procurement decision and lives in the RFQ, not here. This closes the axis 01_02 §2.5 / the RFQ had
# left open as "our inference from the F3001 contrast, not a checked claim": it is checked now.
# The oxide-diffusion
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
        "spec": "ASTM F2924 (AM PBF, Grade 5 — control / print reference)",
        "V_wt": 4.0, "Al_wt": 6.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 110.0, "nu": 0.33, "alpha_1K": 8.6e-6, "yield_MPa": 880.0, "rho_kg_m3": 4430.0,
        "lambda_W_mK": 6.7,
    },
    "Ti-6Al-7Nb": {
        "spec": "ASTM F1295 / UNS R56700 — WROUGHT composition ref (no AM spec exists; V-free, dir. a)",
        "V_wt": 0.0, "Al_wt": 6.0, "Nb_wt": 7.0, "Zr_wt": 0.0,
        "E_GPa": 103.0, "nu": 0.31, "alpha_1K": 8.4e-6, "yield_MPa": 850.0, "rho_kg_m3": 4520.0,
        "lambda_W_mK": 7.0,
    },
    "CP-Ti-Gr4": {
        "spec": "ASTM F67 Gr4 / UNS R50700 — WROUGHT composition ref (no AM spec exists; zero V/Al, alpha-Ti)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 104.0, "nu": 0.34, "alpha_1K": 8.6e-6, "yield_MPa": 480.0, "rho_kg_m3": 4510.0,
        "lambda_W_mK": 17.0,
    },
    "beta-Ti-13Nb-13Zr": {
        "spec": "ASTM F1713 / UNS R58130 — WROUGHT composition ref (no AM spec exists; low-E V/Al-free)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 13.0, "Zr_wt": 13.0,
        "E_GPa": 80.0, "nu": 0.33, "alpha_1K": 8.8e-6, "yield_MPa": 900.0, "rho_kg_m3": 5050.0,
        "lambda_W_mK": 7.5,   # estimate — β-Ti(Nb,Zr) heavily alloyed, sparse data
    },
    "Ta": {
        "spec": "ASTM F560 / UNS R05200 — WROUGHT composition ref (no AM spec exists; bioinert benchmark, coin-only, heavy)",
        "V_wt": 0.0, "Al_wt": 0.0, "Nb_wt": 0.0, "Zr_wt": 0.0,
        "E_GPa": 186.0, "nu": 0.34, "alpha_1K": 6.5e-6, "yield_MPa": 345.0, "rho_kg_m3": 16650.0,
        "lambda_W_mK": 57.0,
    },
    "Ti-15Zr": {
        "spec": "NO STANDARD — binary Ti-Zr has no ASTM/ISO spec (Roxolid is Straumann-proprietary); vendor datasheet is the only reference",
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

# Central bus rod (HW.34) — the monolithic conductor that threads the PEEK break to the pogo pad.
# Canon 01_01 §1.4 freezes THREE diameters and only ONE of them is metal: rod Ø1.0 · cathode channel
# Ø1.3 · liner 0.15 mm (rod + 2×liner ≤ channel, CAD gate `AxialStack.BusRodClears`).
# ⛔ Mechanics (σ ∝ 1/d³) and conduction (A ∝ d²) take the ROD — the rest of the channel is the
# insulating liner, not metal. Substituting the channel here overstates every bending SF ×2.2 and the
# bus cross-section ×1.69, and the two errors point in OPPOSITE safety directions.
D_BUS_ROD_MM = 1.0              # mm — 01_01 §1.4 frozen dims (mirror: cem/anchor_zone1.*.json)

# ── EDLC energy budget (HW.42, script 63; 02_03 §9/§12) — delta_t sensitivity to a
# second power source landing on the SAME BQ25570 charging rail. Mirror of canon;
# edit `02_03`, not here (same discipline as ETA_BQ above). ──
C_EDLC_F = 0.47                  # F — EDLC capacitance (02_03 §12.1)
VSTOR_MAX_V = 5.5                # V — EDLC absolute max voltage (02_03 §12.1)
VBAT_OK_ON_V = 3.40              # V — buck re-enable threshold, window floor (02_03 §4.Г)
ETA_BUCK_ACTIVE = 0.88           # — buck efficiency, active load (02_03 §9.1 buck table)
EDLC_WINDOW_USABLE_J = 3.87      # J — usable window energy post-buck (02_03 §12.1):
# ½·C_EDLC_F·(VSTOR_MAX_V²−VBAT_OK_ON_V²)·ETA_BUCK_ACTIVE ≈ 3.865 J — reconstructed as a
# sanity check in script 63, not re-derived from C/V/eta as the primary path.
P_GEN_SUMMER_UW = 15.0           # µW — typical Gen 2.0 EBFC, summer (02_03 §9.2)
P_GEN_WINTER_RANGE_UW = (3.0, 5.0)   # µW — winter range (02_03 §9.8 prose)
ETA_BOOST_WINTER = 0.65          # — boost eta at P_gen≈5µW winter (02_03 §9.8: "eta_boost
# lower at lower I_IN"); summer counterpart is ETA_BQ above — do not re-hardcode 0.68.
# 3-point MEASURED eta_boost(P_IN) curve (02_03 §9.1 table, TI SLUSBH2G Fig.4-7 read).
# First pair mirrors ETA_BQ (HW.47 One-Home) — do not re-hardcode 0.68.
ETA_BOOST_TABLE_UW = ((15.0, ETA_BQ), (30.0, 0.75), (100.0, 0.82))

# ── EDLC endurance-hours (HW.37, script 51; 02_03 §12.1/§6) — vendor SKUs
# (`02_01 §3` поз.3), Arrhenius-style temperature+voltage life-doubling model
# (generalized capacitor_life_hours(), NOT the same functional form as the
# continuous fixed-Ea arrhenius_aging() above — see that function's docstring). ──
EATON_KR_RATED_HOURS = 1000.0      # h — Eaton KR-5R5H474-R endurance rating (00_07 HW.37)
EATON_KR_RATED_TEMP_C = 70.0       # °C — rated-life test temperature
EATON_KR_RATED_VOLTAGE_V = 5.5     # V — rated-life test voltage
KEMET_FG_RATED_HOURS = 1000.0      # h — KEMET FG0H474ZF endurance rating (00_07 HW.37)
KEMET_FG_RATED_TEMP_C = 70.0       # °C — rated-life test temperature (same as Eaton KR)
KEMET_FG_RATED_VOLTAGE_V = 5.5     # V — rated voltage (0.47F/5.5V SKU, 00_07 HW.37)
THERMAL_DOUBLING_INTERVAL_K = 10.0     # K — consensus "life doubles per 10°C" rule (lit., 00_07 HW.37/HW.7)
VOLTAGE_DOUBLING_OPTIMISTIC_V = 0.2    # V — Abracon/CDE-style: life doubles per 0.2V derating
VOLTAGE_DOUBLING_CONSERVATIVE_V = 0.4  # V — Vishay/Eaton-style: life doubles per 0.4V derating
# KEMET's OWN voltage-doubling coefficient was not confirmed from a public datasheet
# (00_07 HW.37) — report the sensitivity across the Eaton-derived bracket above rather
# than a false-precise single number.
FIELD_TEMPS_C = (25.0, 10.0)       # °C — field reference points already ratified in 00_07 HW.37/HW.7
