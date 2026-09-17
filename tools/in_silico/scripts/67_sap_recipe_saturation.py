#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.3 — does the synthetic xylem sap precipitate its own chelator? Saturation verdict and admissible window.

`01_02 §2.1` specified the synthetic sap as RANGES until 2026-09-17 — malic acid 1–5 mM, oxalic acid 0.5–2 mM,
KNO3 2–5 mM, CaCl2 0.5–2 mM, MgSO4 0.2–1 mM — and two tests run in it under different conditions: the accelerated
corrosion test of `01_02 §2` (then pH 5.0–5.5, a 20–40 °C cycle) and the Stage-2 Ti-coin electrochemistry, whose
letter mirrored the recipe at 20–25 °C (`01_03 §3.5`) and named the union pH 4.5–5.5 because canon held two bands.
A range is a claim about a SET of solutions, and calcium oxalate is among the least soluble salts in biology — so
before a laboratory is asked to prepare a member of that set, the set has to be checked for members that exist.
Q1–Q5 below priced that set and its two ways out; the verdict they priced (⚖️ founder 2026-09-17) replaced the
ranges with a POINT, and Q6 is what that point takes to prepare.

  Q1  THE CANON CORNERS. Saturation index of the calcium oxalate hydrates at every corner of the recipe × the pH
      band × the temperature band of each test. Is ANY corner undersaturated — and if none is, how wrong would
      the constants have to be for one to become so?
  Q2  THE ADMISSIBLE WINDOW (the machine half of the HW.3 leg). Holding calcium at a canon level, how much total
      oxalate may the medium carry before whewellite saturates anywhere in the test's band — worst case over the
      other components, pH and temperature? And the mirror: holding oxalate at a canon level, how much calcium?
  Q3  THE BASE. The recipe names no base, yet its acids must be neutralised to reach the pH set-point. How much,
      and what that does to the cation totals.
  Q4  THE PRICE OF LOWERING OXALATE. The recipe buffers with its own organic acids; how much buffer capacity the
      medium keeps when oxalate is cut to the window.
  Q5  CONSTANT SENSITIVITY. How far the window moves across the NEA spread of the oxalate constants and the malate
      readings — and what one pH set-point would do to it.
  Q6  THE RATIFIED POINT. Oxalate out, the other four at the geometric mid of their range, pH 5.75 with a pH 4.5
      side series: how much KOH each condition takes, the potassium total that makes, and how weakly the medium
      buffers — the number that turns medium replacement from a courtesy into a condition of the test.

THE CONSTANT THAT DOES NOT EXIST, and why the window does not need it. No open primary gives the calcium or
magnesium malate complex at I = 0; the only measured values found are APPARENT constants in a Na+ medium at
pHa 7.4 and I ≈ 0.1 (Günzel et al. 2005). The script elects none. It uses the SIGN of each effect, which needs no
number — through BOTH channels, and the second is the one a first draft of this argument missed (caught by review):
by MASS ACTION a calcium ligand lowers free calcium and so lowers the SI, while a magnesium ligand frees oxalate and
so raises it; by IONIC STRENGTH a neutral complex takes two divalent ions out of solution and so raises the activity
coefficients of Ca2+ and ox2-. For calcium the first channel wins; for magnesium both push the same way, and both
are at their extreme when no magnesium binds oxalate and every magnesium ion is held as a neutral complex. The
HARD BOUND takes exactly that — no calcium malate, magnesium sequestered and oxalate-inert, every oxalate constant
at the SI-raising end of its NEA spread — and a window computed on it is safe whatever the malate constants are.
That it dominates is ASSERTED, not argued: at every corner, against every documented reading and against both
constants swept up the log K grid. What the missing constant costs is then a number — how much wider the window gets
under the documented readings — and for the verdict the question is inverted: what calcium malate constant would
make a canon corner undersaturated. ⚠️ Not covered: background ion pairs with no constant (K+/Na+ with malate,
KNO3(aq)) lower the ionic strength too.

⚠️ WHAT THIS DOES NOT SETTLE, up front. Which ion to lower is a CHOICE — calcium is the structural cation of the
   cell wall, oxalate the chelator aggressive to titanium — and the script prices both directions without taking
   either. It does not model precipitation kinetics or a metastable zone: SI < 0 is the thermodynamic criterion,
   and a supersaturated medium that has not precipitated YET is not a specification. A window edge is the
   saturation point itself, not a margin. It knows nothing about real sap: no primary measurement of Pinus
   sylvestris xylem-sap calcium or oxalate is in the tree. The activity model is Davies, which its own source says
   works up to 0.1 mol/kg and does not use in its reviews. Glucose is not part of the recipe; the phytosiderophores
   (optional, 0.01–0.1 mM) have no constants; calcium malate as a SOLID has no solubility product in the sources
   used — all three are absent from the model, and the cache names each as absent.

Genre = `65_zif_radiosensitization`: literature constants plus closed-form self-checks, answering a lab-gated
question before the lab. No DFT, no MD. Runs in seconds.
"""
from __future__ import annotations

import itertools
import json
import math
import sys
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy.optimize import brentq, root

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

OUT_DIR = CACHE_DIR / "chemistry"
OUT_JSON = OUT_DIR / "sap_recipe_saturation.json"
OUT_PNG = OUT_DIR / "sap_recipe_saturation.png"

MM = 1e-3
LN10 = math.log(10.0)
R_KJ = 8.31446261815324e-3          # kJ/(mol·K), CODATA 2018
KCAL_KJ = 4.184                     # thermochemical calorie — wateq4f.dat states its enthalpies in kcal
T_REF_K = 298.15
SI_TOL = 1e-6                       # a window edge is accepted when no condition sits more than this above SI = 0

# ── The PRE-VERDICT recipe — the ranges 01_02 §2.1 specified until 2026-09-17. Q1–Q5 run on them and stay the
# ground of the verdict that replaced them; canon no longer specifies them, so nothing pins them to canon ──
RECIPE_KEYS = ("malic", "oxalic", "kno3", "cacl2", "mgso4")
RECIPE_RANGES_MM = {"malic": (1.0, 5.0), "oxalic": (0.5, 2.0), "kno3": (2.0, 5.0), "cacl2": (0.5, 2.0),
                    "mgso4": (0.2, 1.0)}
# ── The RATIFIED recipe (⚖️ founder 2026-09-17) — canon 01_02 §2.1 specifies this POINT, and test_doc_cache_sync pins
# that table to it. Oxalate is out (Q1–Q2: it does not coexist with millimolar calcium); the other four sit at the
# geometric mid of their pre-verdict range to two significant figures, asserted in `ratified_point()` so the point
# cannot drift from its own derivation. pH: the set-point is the measured Pinus sylvestris sap pH (Tarvainen et al.
# 2023, New Phytol. 238:926, Table 1, control trees), for both tests; the side series is uncoated coupons under
# ICP-MS only, in the coin test. ──
RATIFIED_POINT_MM = {"malic": 2.2, "oxalic": 0.0, "kno3": 3.2, "cacl2": 1.0, "mgso4": 0.45}
RATIFIED_PH = {"setpoint": (5.75, ("coin", "accelerated")), "side_series": (4.5, ("coin",))}
# Each test in its own band. Temperatures on a 5 °C grid, pH on a 0.5 grid; every band end is a grid point.
# ⚠️ PRE-VERDICT, like RECIPE_RANGES_MM above: the pH bands below (and their `ph_home` strings) are the two canon
# bands as they stood BEFORE 2026-09-17. Canon no longer carries either — §2.1 is a set-point (5.75) plus a side
# series (4.5), so "the union of the two canon bands" names nothing that exists. Kept because Q1–Q5 price the
# ranges the ratified point replaced; the live point is RATIFIED_PH / RATIFIED_POINT_MM and Q6 above.
TESTS = {
    "coin": {"label": "Stage-2 Ti-coin electrochemistry",
             "ph": (4.5, 5.0, 5.5), "ph_home": "pre-verdict band (retired 2026-09-17); live pH → RATIFIED_PH, 01_02 §2.1",
             "t_c": (20.0, 25.0), "t_home": "01_03 §3.5 — 20–25 °C"},
    "accelerated": {"label": "12-week accelerated corrosion test",
                    "ph": (5.0, 5.5), "ph_home": "pre-verdict band (retired 2026-09-17); live pH → RATIFIED_PH, 01_02 §2.1",
                    "t_c": (20.0, 25.0, 30.0, 35.0, 40.0), "t_home": "01_02 §2.1 — 20–40 °C cycle"},
}
FIXED_LEVELS_MM = (0.5, 1.0, 2.0)   # both canon ranges (CaCl2 and oxalic acid) run 0.5–2 mM

COMPONENTS = ("Ca", "Mg", "K", "Na", "Ox", "Mal", "SO4", "Cl", "NO3")
CHARGE = {"H": 1, "Ca": 2, "Mg": 2, "K": 1, "Na": 1, "Ox": -2, "Mal": -2, "SO4": -2, "Cl": -1, "NO3": -1}
CI = {c: i for i, c in enumerate(COMPONENTS)}
Z_C = np.array([CHARGE[c] for c in COMPONENTS], dtype=float)


@dataclass(frozen=True)
class LogK:
    """log10 K(T) of one reaction, in the form its source gives it."""
    at25: float | None = None
    dh_kj: float | None = None       # T-independent reaction enthalpy; None beside `at25` = the source selects none
    analytic: tuple | None = None    # (A1, A2, A3, A4, A5): A1 + A2·T + A3/T + A4·log10(T) + A5/T²

    def __call__(self, t_k: float) -> float:
        if self.analytic is not None:
            a1, a2, a3, a4, a5 = self.analytic
            return a1 + a2 * t_k + a3 / t_k + a4 * math.log10(t_k) + a5 / (t_k * t_k)
        if self.dh_kj is None:
            return self.at25
        return self.at25 - self.dh_kj / (R_KJ * LN10) * (1.0 / t_k - 1.0 / T_REF_K)


@dataclass(frozen=True)
class Species:
    """An aqueous species FORMED from components (protons as "H"); its log K refers to I = 0."""
    name: str
    stoich: tuple
    log_k: LogK
    source: str

    @property
    def charge(self) -> int:
        return sum(CHARGE[c] * n for c, n in self.stoich)


@dataclass(frozen=True)
class Solid:
    """A solid by its DISSOLUTION into components, water activity 1. `selected=False` marks a value its source
    offers for scoping only: reported, never used for a verdict or a window."""
    name: str
    stoich: tuple
    log_ks: LogK
    source: str
    selected: bool = True


@dataclass(frozen=True)
class ConstantSet:
    label: str
    species: tuple
    solids: tuple


# ─────────────────────────────────── activity model ───────────────────────────────────
# Davies, NEA TDB-2 eq. (3): log10 γ = −A z² (√I / (1 + √I) − 0.3 I) — "works fairly well up to ionic strengths of
# 0.1 mol·kg–1", and "should not be used in the NEA TDB reviews". A(T): TDB-2 Table 2 (p.23, 1 bar), linear in
# between the tabulated points. Neutral species carry γ = 1 (no salting-out term).
TDB2 = "NEA TDB-2 guideline (Grenthe, Mompean, Spahiu, Wanner) — Davies eq. (3); A(T) Table 2 p.23"
DAVIES_A_TABLE = ((20.0, 0.505), (25.0, 0.509), (30.0, 0.513), (35.0, 0.518), (40.0, 0.525))
DAVIES_B = 0.3
DAVIES_I_MAX = 0.1


def davies_a(t_k: float) -> float:
    t_c = t_k - 273.15
    ts = [t for t, _ in DAVIES_A_TABLE]
    assert ts[0] - 1e-9 <= t_c <= ts[-1] + 1e-9, f"{t_c:.2f} °C lies outside the tabulated A(T)"
    return float(np.interp(t_c, ts, [a for _, a in DAVIES_A_TABLE]))


def davies_f(ionic: float) -> float:
    s = math.sqrt(ionic)
    return s / (1.0 + s) - DAVIES_B * ionic


# ─────────────────────────────────── constants (each read from the source beside it) ───────────────────────────────────
NEA9 = ("NEA9 = Hummel, Anderegg, Rao, Puigdomènech, Tochiyama (2005) Chemical Thermodynamics Vol. 9, OECD-NEA/Elsevier "
        "(open NEA PDF)")

# (selected, SI-raising end, SI-lowering end). Where NEA accepted several determinations (Table VI-18 p.182) the
# ends are the extreme accepted log K°; where it gives one value, they are that value ± its stated uncertainty.
OXALATE_ENDS = ("selected", "si_high", "si_low")
LOG_K_HOX = (4.250, 4.240, 4.260)            # H+ + ox2- ⇌ Hox-            Table III-2 p.45, ± 0.010
PKA1_OXALIC = 1.400                          # H2ox ⇌ H+ + Hox-            Table III-2 p.45 (inert at pH ≥ 4.5)
LOG_K_CAOX = (3.19, 3.06, 3.27)              # Ca2+ + ox2- ⇌ Ca(ox)(aq)    Table VI-19 p.189; ends Table VI-18
LOG_B_CAOX2 = (4.02, 3.83, 4.21)             # Ca2+ + 2ox2- ⇌ Ca(ox)2 2-   Table VI-19 p.189, ± 0.19
LOG_K_MGOX = (3.56, 3.38, 3.62)              # Mg2+ + ox2- ⇌ Mg(ox)(aq)    Table VI-19 p.189; ends Table VI-18
LOG_B_MGOX2 = (5.17, 5.09, 5.25)             # Mg2+ + 2ox2- ⇌ Mg(ox)2 2-   Table VI-19 p.189, ± 0.08
LOG_KS_WHEWELLITE = (-8.73, -8.79, -8.67)    # Table III-2 / VI-19, ± 0.06; ΔsolH 21.5 kJ (§VI p.176)
LOG_KS_WEDDELLITE = (-8.30, -8.36, -8.24)    # Table VI-19, ± 0.06; ΔsolH 25.2 kJ (p.176)
LOG_KS_CAOXITE = (-8.19, -8.23, -8.15)       # Table VI-19, ± 0.04; ΔsolH 29.7 kJ (p.176)
WHEWELLITE = "whewellite CaC2O4·H2O"


def oxalate_block(end: str) -> tuple[tuple, tuple]:
    i = OXALATE_ENDS.index(end)
    tag = {"selected": "selected value", "si_high": "SI-raising end of the documented spread",
           "si_low": "SI-lowering end of the documented spread"}[end]
    species = (
        Species("HOx-", (("H", 1), ("Ox", 1)), LogK(LOG_K_HOX[i], 7.3),
                f"{NEA9}, Table III-2 p.45 ({tag}); ΔrH +7.3 kJ"),
        Species("H2Ox", (("H", 2), ("Ox", 1)), LogK(LOG_K_HOX[i] + PKA1_OXALIC, 10.6),
                f"{NEA9}, Table III-2 p.45 (both steps); ΔrH +10.6 kJ"),
        Species("CaOx0", (("Ca", 1), ("Ox", 1)), LogK(LOG_K_CAOX[i]),
                f"{NEA9}, Table VI-19 p.189 / VI-18 p.182 ({tag}); no enthalpy selected"),
        Species("Ca(Ox)2-2", (("Ca", 1), ("Ox", 2)), LogK(LOG_B_CAOX2[i]),
                f"{NEA9}, Table VI-19 p.189 ({tag}); no enthalpy selected"),
        Species("MgOx0", (("Mg", 1), ("Ox", 1)), LogK(LOG_K_MGOX[i]),
                f"{NEA9}, Table VI-19 p.189 / VI-18 p.182 ({tag}); no enthalpy selected"),
        Species("Mg(Ox)2-2", (("Mg", 1), ("Ox", 2)), LogK(LOG_B_MGOX2[i]),
                f"{NEA9}, Table VI-19 p.189 ({tag}); no enthalpy selected"),
    )
    solids = (
        Solid(WHEWELLITE, (("Ca", 1), ("Ox", 1)), LogK(LOG_KS_WHEWELLITE[i], 21.5),
              f"{NEA9}, Table VI-19 p.189 ({tag}); ΔsolH 21.5 kJ, §VI p.176"),
        Solid("weddellite CaC2O4·2H2O", (("Ca", 1), ("Ox", 1)), LogK(LOG_KS_WEDDELLITE[i], 25.2),
              f"{NEA9}, Table VI-19 p.189 ({tag}); ΔsolH 25.2 kJ, §VI p.176"),
        Solid("caoxite CaC2O4·3H2O", (("Ca", 1), ("Ox", 1)), LogK(LOG_KS_CAOXITE[i], 29.7),
              f"{NEA9}, Table VI-19 p.189 ({tag}); ΔsolH 29.7 kJ, §VI p.176"),
    )
    return species, solids


# Malic acid. −log K1 = 1358.85/T − 5.1382 + 0.013550·T ; −log K2 = 1658.53/T − 6.2364 + 0.019353·T (K = dissociation).
# ⚠️ The text layer of the NBS scan reads 1355.85 and 1655.53 — that misreading gives pK1 3.449 at 25 °C against the
#    3.48e-4 (pK1 3.458) the same abstract prints. `malate_check()` holds the equations to those printed 25 °C values.
EDEN_BATES = ("Eden & Bates (1959) J. Res. NBS 62:161, doi:10.6028/jres.062.028 — both equations and the 25 °C "
              "constants as printed in the abstract, p.161")
EB_PK1 = (1358.85, -5.1382, 0.013550)
EB_PK2 = (1658.53, -6.2364, 0.019353)
EB_K_25C = (3.48e-4, 7.99e-6)
MALATE = (
    Species("HMal-", (("H", 1), ("Mal", 1)), LogK(analytic=(EB_PK2[1], EB_PK2[2], EB_PK2[0], 0.0, 0.0)),
            f"{EDEN_BATES} (pK2)"),
    Species("H2Mal", (("H", 2), ("Mal", 1)),
            LogK(analytic=(EB_PK1[1] + EB_PK2[1], EB_PK1[2] + EB_PK2[2], EB_PK1[0] + EB_PK2[0], 0.0, 0.0)),
            f"{EDEN_BATES} (pK1 + pK2)"),
)

WATEQ4F = ("PHREEQC database wateq4f.dat — the WATEQ4F compilation, Ball & Nordstrom (1991) USGS OFR 91-183, "
           "doi:10.3133/ofr91183")
SULFATE = (
    Species("HSO4-", (("H", 1), ("SO4", 1)), LogK(analytic=(-56.889, 0.006473, 2307.9, 19.8858, 0.0)),
            f"{WATEQ4F}; analytic expression (its log_k line: 1.988)"),
    Species("CaSO4_0", (("Ca", 1), ("SO4", 1)), LogK(2.30, 1.65 * KCAL_KJ), f"{WATEQ4F}; log_k 2.3, delta_h 1.65 kcal"),
    Species("MgSO4_0", (("Mg", 1), ("SO4", 1)), LogK(2.37, 4.55 * KCAL_KJ), f"{WATEQ4F}; log_k 2.37, delta_h 4.55 kcal"),
    Species("KSO4-", (("K", 1), ("SO4", 1)), LogK(analytic=(3.106, 0.0, -673.6, 0.0, 0.0)),
            f"{WATEQ4F}; analytic expression (its log_k line: 0.85; its delta_h line implies a different enthalpy)"),
    Species("NaSO4-", (("Na", 1), ("SO4", 1)), LogK(0.70, 1.12 * KCAL_KJ), f"{WATEQ4F}; log_k 0.7, delta_h 1.12 kcal"),
)
GYPSUM = Solid("gypsum CaSO4·2H2O", (("Ca", 1), ("SO4", 1)), LogK(analytic=(68.2401, 0.0, -3221.51, -25.0627, 0.0)),
               f"{WATEQ4F}; analytic expression (its log_k line: −4.58)")
GLUSHINSKITE = Solid("glushinskite MgC2O4·2H2O", (("Mg", 1), ("Ox", 1)), LogK(-6.4),
                     f"{NEA9}, §VI p.163 — −6.4 ± 0.2 'for scoping calculations'; 'no value is recommended'",
                     selected=False)

# Calcium and magnesium malate. NOT FOUND at I = 0. The only measured values: APPARENT dissociation constants in a
# Na+ medium, pHa 7.4, room temperature, each at the ionic strength beside it. Used only as READINGS — never by the
# hard bound, and so never by the window.
GUENZEL = ("Günzel, McGuigan & Schlue (2005) Front. Biosci. 10:905, doi:10.2741/1585 — Table 2 p.914 "
           "(apparent Kapp, Na+ medium, pHa 7.4, room temperature)")
GUENZEL_KAPP = {"Ca": (10.32, 0.1240), "Mg": (15.85, 0.1040)}   # (Kapp mmol/L, ionic strength mol/L)


def guenzel_log_k(metal: str, to_zero_ionic_strength: bool) -> float:
    """log K of M2+ + Mal2- ⇌ MMal0 from Günzel's apparent dissociation constant. Corrected to I = 0 with Davies at
    25 °C: log K° = log K′ + 8·A·f(I) — DERIVED here, and from I = 0.104/0.124, past the equation's stated 0.1."""
    kapp_mm, ionic = GUENZEL_KAPP[metal]
    log_k = -math.log10(kapp_mm * MM)
    if to_zero_ionic_strength:
        log_k += 8.0 * davies_a(T_REF_K) * davies_f(ionic)
    return log_k


@dataclass(frozen=True)
class Scenario:
    key: str
    label: str
    oxalate_end: str
    # None · "apparent" (Günzel log K′ read as I = 0) · "i0" (Davies-corrected, derived) · a swept log K (float) ·
    # "limit" (magnesium only: every ion held as a neutral complex — see SEQUESTRATION_LOG_K)
    ca_malate: str | float | None = None
    mg_malate: str | float | None = None
    mg_oxalate_inert: bool = False


# The magnesium half of the hard bound. A magnesium ligand raises the calcium oxalate SI through TWO channels: it
# frees oxalate (mass action) and, as a neutral complex, it lowers the ionic strength and so raises the activity
# coefficients of Ca2+ and ox2-. Both are at their extreme when no magnesium binds oxalate and every magnesium ion
# is held as a neutral 1:1 complex — the largest ionic-strength drop any magnesium ligand of this recipe can cause.
# log K 12 makes that complete at every corner; it is a LIMIT, not a literature constant.
SEQUESTRATION_LOG_K = 12.0
DOMINANCE_SWEEP_LOG_K = (1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0)

SCENARIOS = (
    Scenario("hard_bound", "HARD BOUND — calcium bound only by oxalate and sulfate, magnesium held entirely as a "
             "neutral complex that binds no oxalate, oxalate constants at their SI-raising end", "si_high",
             mg_malate="limit", mg_oxalate_inert=True),
    Scenario("selected", "NEA-selected constants, malate complexes absent", "selected"),
    Scenario("selected_guenzel_apparent", "NEA-selected + Günzel apparent malate constants read as I = 0", "selected",
             "apparent", "apparent"),
    Scenario("selected_guenzel_i0", "NEA-selected + Günzel malate constants corrected to I = 0 (derived here)",
             "selected", "i0", "i0"),
    Scenario("spread_si_high", "oxalate constants at their SI-raising end, malate complexes absent", "si_high"),
    Scenario("spread_si_low", "oxalate constants at their SI-lowering end, malate complexes absent", "si_low"),
    Scenario("si_lowest_documented", "SI-LOWEST documented reading — oxalate constants at their SI-lowering end, the "
             "strongest calcium malate reading, no magnesium malate", "si_low", "i0", None),
    Scenario("si_highest_documented", "SI-HIGHEST documented reading — oxalate constants at their SI-raising end, the "
             "strongest magnesium malate reading, no calcium malate", "si_high", None, "i0"),
)
SC = {s.key: s for s in SCENARIOS}
WINDOW_SCENARIOS = ("hard_bound", "selected", "selected_guenzel_apparent", "selected_guenzel_i0", "spread_si_high",
                    "spread_si_low", "si_highest_documented")


def malate_complex(metal: str, how) -> Species:
    if isinstance(how, float):
        log_k, source = how, "swept log K — not a literature constant"
    elif how == "limit":
        log_k, source = SEQUESTRATION_LOG_K, "sequestration LIMIT — not a literature constant"
    else:
        log_k = guenzel_log_k(metal, how == "i0")
        source = f"{GUENZEL} — {'Davies-corrected to I = 0, derived' if how == 'i0' else 'log K′ read as I = 0'}"
    return Species(f"{metal}Mal0", ((metal, 1), ("Mal", 1)), LogK(log_k), source)


def build(sc: Scenario) -> ConstantSet:
    species, solids = oxalate_block(sc.oxalate_end)
    if sc.mg_oxalate_inert:
        species = tuple(sp for sp in species if not sp.name.startswith("Mg"))
    extra = [malate_complex(metal, how) for metal, how in (("Ca", sc.ca_malate), ("Mg", sc.mg_malate))
             if how is not None]
    return ConstantSet(sc.label, (*species, *MALATE, *SULFATE, *extra), (*solids, GYPSUM, GLUSHINSKITE))


# ─────────────────────────────────── the solver ───────────────────────────────────
@dataclass
class Solution:
    free: dict                # mol/L of each component's free ion (0 when absent)
    conc: dict                # mol/L of each formed species
    log_gamma: dict           # by charge
    ionic_strength: float
    base_mol_l: float         # strong base (as base-cation hydroxide) that sets the pH
    t_k: float


class Model:
    """One constant set at one temperature: the arrays the solver needs, built once, plus a warm start."""

    def __init__(self, cs: ConstantSet, t_k: float):
        self.cs, self.t_k = cs, t_k
        self.nu = np.array([[dict(sp.stoich).get(c, 0) for c in COMPONENTS] for sp in cs.species], dtype=float)
        self.h = np.array([dict(sp.stoich).get("H", 0) for sp in cs.species], dtype=float)
        self.z_s = np.array([sp.charge for sp in cs.species], dtype=float)
        self.log_k = np.array([sp.log_k(t_k) for sp in cs.species])
        self.log_ks = {s.name: s.log_ks(t_k) for s in cs.solids}
        self.a = davies_a(t_k)
        self.warm: dict = {}


_MODELS: dict = {}


def model_for(sc: Scenario, t_c: float) -> Model:
    key = (sc, t_c)
    if key not in _MODELS:
        _MODELS[key] = Model(build(sc), t_c + 273.15)
    return _MODELS[key]


def speciate(model: Model, totals: dict, ph: float, base: str = "K",
             fixed_ionic_strength: float | None = None) -> Solution:
    """Speciation at a FIXED pH (−log10 of the H+ activity); the strong base that sets it is an unknown.

    Unknowns: log10 free concentration of every component present (the base cation always) and log10 I.
    Equations: a mass balance per component other than the base cation, electroneutrality, and I = ½Σz²c — so the
    base amount falls out of the base cation's own balance. Verified against a closed form in `closed_form_check()`.
    """
    tot = np.array([float(totals.get(c, 0.0)) for c in COMPONENTS])
    active = tot > 0.0
    active[CI[base]] = True
    idx = np.flatnonzero(active)
    pos_base = int(np.flatnonzero(idx == CI[base])[0])
    keep = ~np.any(model.nu[:, ~active] != 0, axis=1)
    nu, h, z_s, log_k = model.nu[keep][:, idx], model.h[keep], model.z_s[keep], model.log_k[keep]
    z_c, t_act = Z_C[idx], tot[idx]
    balanced = np.arange(len(idx)) != pos_base
    fixed = fixed_ionic_strength is not None
    n = len(idx)
    a = model.a

    def unpack(v):
        y = np.clip(v[:n], -30.0, 1.0)
        ionic = fixed_ionic_strength if fixed else 10.0 ** float(np.clip(v[n], -8.0, 0.0))
        f = davies_f(ionic)
        c_s = 10.0 ** (log_k + nu @ (y - a * z_c * z_c * f) - h * ph + a * z_s * z_s * f)
        return ionic, f, 10.0 ** y, c_s, 10.0 ** (-ph + a * f)

    def residuals(v):
        _, _, free, c_s, h_free = unpack(v)
        total_calc = free + nu.T @ c_s
        charge = h_free + z_c @ free + z_s @ c_s
        scale = h_free + np.abs(z_c) @ free + np.abs(z_s) @ c_s
        out = [np.log10(total_calc[balanced]) - np.log10(t_act[balanced]), [charge / scale]]
        if not fixed:
            out.append([math.log10(0.5 * (h_free + (z_c * z_c) @ free + (z_s * z_s) @ c_s)) - v[n]])
        return np.concatenate(out)

    key = (tuple(idx), base, fixed)
    cold = np.log10(np.where(np.arange(n) == pos_base, t_act + 5.0 * MM, t_act))
    if not fixed:
        cold = np.append(cold, math.log10(0.02))
    best = None
    for x0 in (model.warm.get(key), cold):
        if x0 is None:
            continue
        for method in ("hybr", "lm"):
            sol = root(residuals, x0, method=method, options={"xtol": 1e-14} if method == "hybr" else {"xtol": 1e-15})
            err = float(np.max(np.abs(residuals(sol.x))))
            if best is None or err < best[1]:
                best = (sol.x, err)
            if err < 1e-12:
                break
        if best[1] < 1e-12:
            break
    x, err = best
    assert err < 1e-10, f"unconverged speciation: max residual {err:.1e}"
    model.warm[key] = x
    ionic, f, free_a, c_s, _ = unpack(x)
    assert ionic < DAVIES_I_MAX, f"ionic strength {ionic:.3f} mol/L lies outside the Davies range"
    free = dict.fromkeys(COMPONENTS, 0.0)
    for k, i in enumerate(idx):
        free[COMPONENTS[i]] = float(free_a[k])
    names = [sp.name for sp, m in zip(model.cs.species, keep, strict=True) if m]
    base_total = float(free_a[pos_base] + nu[:, pos_base] @ c_s)
    return Solution(free=free, conc=dict(zip(names, map(float, c_s), strict=True)),
                    log_gamma={z: -a * z * z * f for z in (-2, -1, 0, 1, 2)}, ionic_strength=float(ionic),
                    base_mol_l=base_total - float(tot[CI[base]]), t_k=model.t_k)


def saturation_index(sol: Solution, model: Model, solid: Solid) -> float:
    log_iap = 0.0
    for c, k in solid.stoich:
        if sol.free[c] <= 0.0:
            return -math.inf
        log_iap += k * (math.log10(sol.free[c]) + sol.log_gamma[CHARGE[c]])
    return log_iap - model.log_ks[solid.name]


def recipe_totals(malic: float, oxalic: float, kno3: float, cacl2: float, mgso4: float) -> dict:
    """Recipe (mol/L) → component totals. Acids enter undissociated, salts by formula; the base is solved for."""
    return {"Mal": malic, "Ox": oxalic, "K": kno3, "NO3": kno3, "Ca": cacl2, "Cl": 2.0 * cacl2, "Mg": mgso4,
            "SO4": mgso4}


def totals_mm(comp_mm: dict) -> dict:
    return recipe_totals(*(comp_mm[k] * MM for k in RECIPE_KEYS))


# ─────────────────────────────────── verification routes ───────────────────────────────────
def closed_form_check() -> dict:
    """Reduced system — calcium, oxalate protonation and Ca(ox)(aq) only, chloride as counter-ion, FIXED ionic
    strength — solved in closed form (a quadratic) and compared with the full solver on the same reduced system.
    Guards the solver's algebra independently of every constant: SI to 1e-9, base to 1e-12 mol/L."""
    species, solids = oxalate_block("selected")
    by = {sp.name: sp for sp in species}
    m = Model(ConstantSet("reduced", (by["HOx-"], by["H2Ox"], by["CaOx0"]), (solids[0],)), T_REF_K)
    ph, i_fix, ca, ox = 5.0, 0.01, 1.0 * MM, 0.2 * MM
    sol = speciate(m, {"Ca": ca, "Ox": ox, "Cl": 2.0 * ca}, ph, fixed_ionic_strength=i_fix)
    f = davies_f(i_fix)
    g1, g2 = 10.0 ** (-m.a * f), 10.0 ** (-4.0 * m.a * f)
    a_h = 10.0 ** (-ph)
    k1, b2, kc = (10.0 ** by[s].log_k(T_REF_K) for s in ("HOx-", "H2Ox", "CaOx0"))
    f_unc = 1.0 + k1 * a_h * g2 / g1 + b2 * a_h * a_h * g2        # uncomplexed oxalate per free ox2-
    kcc = kc * g2 * g2                                              # [Ca(ox)(aq)] = kcc·[Ca2+]·[ox2-]
    qa, qb, qc = f_unc * kcc, f_unc + kcc * ca - ox * kcc, -ox
    x = (-qb + math.sqrt(qb * qb - 4.0 * qa * qc)) / (2.0 * qa)
    c = ca / (1.0 + kcc * x)
    si_closed = math.log10(g2 * c) + math.log10(g2 * x) - solids[0].log_ks(T_REF_K)
    base_closed = (2.0 * ca + 2.0 * x + k1 * a_h * g2 / g1 * x) - (2.0 * c + a_h / g1)
    si_num = saturation_index(sol, m, solids[0])
    assert abs(si_num - si_closed) < 1e-9, f"solver vs closed form, SI: {si_num} vs {si_closed}"
    assert abs(sol.base_mol_l - base_closed) < 1e-12, f"solver vs closed form, base: {sol.base_mol_l} vs {base_closed}"
    return {"si_solver": round(si_num, 12), "si_closed_form": round(si_closed, 12),
            "abs_diff_si": abs(si_num - si_closed), "abs_diff_base_mol_l": abs(sol.base_mol_l - base_closed)}


def malate_check() -> dict:
    """The printed temperature equations must return the 25 °C constants printed beside them."""
    out = {}
    for label, (a3, a1, a2), k25 in (("pK1", EB_PK1, EB_K_25C[0]), ("pK2", EB_PK2, EB_K_25C[1])):
        pk_equation = a3 / T_REF_K + a1 + a2 * T_REF_K
        pk_printed = -math.log10(k25)
        assert abs(pk_equation - pk_printed) < 2e-3, f"Eden & Bates {label}: equation {pk_equation:.4f} vs {pk_printed:.4f}"
        out[label] = {"equation_25c": round(pk_equation, 4), "printed_constant_25c": round(pk_printed, 4)}
    return out


def analytic_check() -> dict:
    """Each analytic expression must return the log_k line the same database row prints."""
    rows = (("HSO4-", SULFATE[0].log_k, 1.988), ("KSO4-", SULFATE[3].log_k, 0.85), ("gypsum", GYPSUM.log_ks, -4.58))
    out = {}
    for name, log_k, printed in rows:
        value = log_k(T_REF_K)
        assert abs(value - printed) < 5e-3, f"{name}: analytic {value:.4f} vs printed {printed}"
        out[name] = {"analytic_25c": round(value, 4), "printed_log_k": printed}
    return out


# ─────────────────────────────────── Q1 — the canon corners ───────────────────────────────────
_CORNERS: dict = {}


def corner(sc: Scenario, comp: dict, ph: float, t_c: float, base: str = "K") -> dict:
    key = (sc, tuple(comp[k] for k in RECIPE_KEYS), ph, t_c, base)
    if key not in _CORNERS:
        m = model_for(sc, t_c)
        sol = speciate(m, totals_mm(comp), ph, base)
        _CORNERS[key] = {**comp, "ph": ph, "t_c": t_c,
                         "si": {s.name: saturation_index(sol, m, s) for s in m.cs.solids},
                         "base_mM": sol.base_mol_l / MM, "ionic_strength": sol.ionic_strength}
    return _CORNERS[key]


def corner_rows(sc: Scenario, test: str, base: str = "K") -> list:
    return [corner(sc, dict(zip(RECIPE_KEYS, combo, strict=True)), ph, t_c, base)
            for combo in itertools.product(*(RECIPE_RANGES_MM[k] for k in RECIPE_KEYS))
            for ph in TESTS[test]["ph"] for t_c in TESTS[test]["t_c"]]


def where(row: dict) -> dict:
    return {**{k: row[k] for k in RECIPE_KEYS}, "ph": row["ph"], "t_c": row["t_c"]}


def q1_summary(sc: Scenario, test: str) -> dict:
    rows = corner_rows(sc, test)
    si = [r["si"][WHEWELLITE] for r in rows]
    lo, hi = int(np.argmin(si)), int(np.argmax(si))
    # A scenario that makes magnesium oxalate-inert BY CONSTRUCTION overstates free magnesium, so it reports no
    # magnesium solid — its number would be an artefact of the bound, not a reading.
    others = [s.name for s in build(sc).solids
              if s.name != WHEWELLITE and not (sc.mg_oxalate_inert and "Mg" in dict(s.stoich))]
    return {"corners_evaluated": len(rows),
            "si_whewellite_min": round(si[lo], 4), "si_whewellite_max": round(si[hi], 4),
            "every_corner_supersaturated": bool(min(si) > 0.0),
            "least_supersaturated_corner": where(rows[lo]), "most_supersaturated_corner": where(rows[hi]),
            "si_range_other_solids": {name: [round(min(r["si"][name] for r in rows), 3),
                                             round(max(r["si"][name] for r in rows), 3)] for name in others}}


def break_even_camal(test: str) -> dict:
    """The calcium malate log K° at which the FIRST canon corner of the test reaches SI = 0, every other constant at
    its SI-lowering end and no magnesium malate. Found at the least-supersaturated corner, then verified over every
    corner at that constant — a corner that would flip earlier replaces the candidate."""
    sc = SC["si_lowest_documented"]
    documented = guenzel_log_k("Ca", True)
    rows = corner_rows(sc, test)
    cand = rows[int(np.argmin([r["si"][WHEWELLITE] for r in rows]))]
    tried = set()

    def si_for(log_k, row):
        m = model_for(Scenario("camal_break_even", "break-even", sc.oxalate_end, ca_malate=float(log_k)), row["t_c"])
        sol = speciate(m, totals_mm(row), row["ph"])
        return saturation_index(sol, m, m.cs.solids[0]), sol

    while True:
        tried.add(tuple(where(cand).values()))
        assert si_for(documented, cand)[0] > 0.0, "the strongest documented reading already flips this corner"
        hi = documented + 1.0
        while si_for(hi, cand)[0] > 0.0:
            hi += 1.0
            assert hi < 20.0, "no calcium malate constant flips this corner"
        log_k = brentq(lambda v, row=cand: si_for(v, row)[0], documented, hi, xtol=1e-9)
        flips = [(si_for(log_k, r)[0], r) for r in rows]
        earlier = min(flips, key=lambda p: p[0])
        if earlier[0] >= -SI_TOL:
            break
        assert tuple(where(earlier[1]).values()) not in tried, "break-even search cycled"
        cand = earlier[1]
    _, sol = si_for(log_k, cand)
    return {"log_k_camal_break_even": round(log_k, 3), "corner": where(cand),
            "calcium_held_by_malate_at_break_even": round(sol.conc["CaMal0"] / (cand["cacl2"] * MM), 3),
            "strongest_documented_reading_log_k": round(documented, 3),
            "apparent_reading_log_k": round(guenzel_log_k("Ca", False), 3),
            "margin_over_strongest_documented": round(log_k - documented, 3)}


# ─────────────────────────────────── Q2 — the admissible window ───────────────────────────────────
def backgrounds():
    """Every canon corner of the three components that are NOT the calcium–oxalate pair."""
    for malic, kno3, mgso4 in itertools.product(RECIPE_RANGES_MM["malic"], RECIPE_RANGES_MM["kno3"],
                                                RECIPE_RANGES_MM["mgso4"]):
        yield {"malic": malic, "kno3": kno3, "mgso4": mgso4}


def conditions(tests: tuple) -> list:
    seen, out = set(), []
    for test in tests:
        for bg in backgrounds():
            for ph in TESTS[test]["ph"]:
                for t_c in TESTS[test]["t_c"]:
                    key = (*bg.values(), ph, t_c)
                    if key not in seen:
                        seen.add(key)
                        out.append((bg, ph, t_c))
    return out


def conditions_at_ph(ph: float) -> list:
    """One pH set-point held across every test temperature — what the window becomes if the pH verdict picks a point."""
    temps = sorted({t for spec in TESTS.values() for t in spec["t_c"]})
    return [(bg, ph, t_c) for bg in backgrounds() for t_c in temps]


def si_window(sc: Scenario, fixed: str, level_mm: float, partner_mm: float, cond: tuple) -> float:
    bg, ph, t_c = cond
    ca, ox = (level_mm, partner_mm) if fixed == "Ca" else (partner_mm, level_mm)
    m = model_for(sc, t_c)
    sol = speciate(m, totals_mm({**bg, "oxalic": ox, "cacl2": ca}), ph)
    return saturation_index(sol, m, m.cs.solids[0])


def partner_limit(sc: Scenario, conds: list, fixed: str, level_mm: float) -> dict:
    """The largest total of the partner ion with SI(whewellite) ≤ 0 in EVERY condition given. Each condition's SI
    rises monotonically with the partner, so the edge is the smallest per-condition root: rank the conditions at a
    trial point, find the root of the worst, then verify every condition at that root — one that is still above
    zero replaces the candidate. The binding condition is recorded, never assumed."""
    trial = [si_window(sc, fixed, level_mm, 1e-2, c) for c in conds]
    cand = int(np.argmax(trial))
    tried = set()
    while True:
        tried.add(cand)
        u = brentq(lambda v, c=conds[cand]: si_window(sc, fixed, level_mm, 10.0 ** v, c), -6.0, 1.0, xtol=1e-10)
        si_all = [si_window(sc, fixed, level_mm, 10.0 ** u, c) for c in conds]
        over = int(np.argmax(si_all))
        if si_all[over] <= SI_TOL:
            break
        assert over not in tried, "window search cycled"
        cand = over
    bg, ph, t_c = conds[cand]
    return {"fixed_ion": fixed, "fixed_level_mM": level_mm, "partner_max_total_uM": round(10.0 ** u * 1e3, 4),
            "binding_condition": {**bg, "ph": ph, "t_c": t_c}}


def glushinskite_at_calcium_cut(test: str, ox_level_mm: float, ca_mm: float) -> dict:
    """What the calcium-cut direction costs that the whewellite window cannot see: with oxalate kept at a canon level
    and calcium at the window edge, how close magnesium oxalate comes to NEA's SCOPING solubility product — worst
    case over the test's band, NEA-selected constants (magnesium oxalate complexation must be on for this number)."""
    sc = SC["selected"]
    best = None
    for bg, ph, t_c in conditions((test,)):
        m = model_for(sc, t_c)
        sol = speciate(m, totals_mm({**bg, "oxalic": ox_level_mm, "cacl2": ca_mm}), ph)
        si = saturation_index(sol, m, GLUSHINSKITE)
        if best is None or si > best[0]:
            best = (si, {**bg, "ph": ph, "t_c": t_c})
    return {"oxalate_mM": ox_level_mm, "calcium_uM": round(ca_mm * 1e3, 3),
            "si_glushinskite_scoping_max": round(best[0], 3), "at": best[1]}


# ─────────────────────────────────── Q4 — buffer capacity ───────────────────────────────────
def buffer_capacity_mm_per_ph(tot: dict, ph: float, t_c: float = 25.0, d: float = 0.01) -> float:
    m = model_for(SC["selected"], t_c)
    return (speciate(m, tot, ph + d).base_mol_l - speciate(m, tot, ph - d).base_mol_l) / (2.0 * d) / MM


# ─────────────────────────────────── Q6 — the ratified point ───────────────────────────────────
def ratified_point() -> dict:
    """The recipe canon specifies since 2026-09-17: the base it takes to reach each pH condition, and how weakly it
    buffers there. Every documented reading at every temperature of the tests the condition belongs to — the hard
    bound is an SI construct, not a reading, so it prices nothing here."""
    for key, (lo, hi) in RECIPE_RANGES_MM.items():
        if key != "oxalic":
            assert RATIFIED_POINT_MM[key] == float(f"{math.sqrt(lo * hi):.2g}"), f"{key}: not the geometric mid"
    assert RATIFIED_POINT_MM["oxalic"] == 0.0, "the verdict removed oxalate"
    tot = totals_mm(RATIFIED_POINT_MM)
    readings = [sc for sc in SCENARIOS if sc.key != "hard_bound"]
    conditions_out = {}
    for name, (ph, tests) in RATIFIED_PH.items():
        temps = sorted({t for test in tests for t in TESTS[test]["t_c"]})
        base, ionic, si_gypsum = [], [], []
        for sc in readings:
            for t_c in temps:
                m = model_for(sc, t_c)
                sol = speciate(m, tot, ph)
                base.append(sol.base_mol_l / MM)
                ionic.append(sol.ionic_strength)
                si_gypsum.append(saturation_index(sol, m, GYPSUM))
        m25 = model_for(SC["selected"], 25.0)
        acid_tenth = (speciate(m25, tot, ph).base_mol_l - speciate(m25, tot, ph - 0.1).base_mol_l) / MM
        kno3 = RATIFIED_POINT_MM["kno3"]
        conditions_out[name] = {
            "ph": ph, "tests": list(tests), "t_c": temps,
            "base_koh_mM": [round(min(base), 3), round(max(base), 3)],
            "potassium_total_mM": [round(min(base) + kno3, 3), round(max(base) + kno3, 3)],
            "ionic_strength_mol_l": [round(min(ionic), 5), round(max(ionic), 5)],
            "si_gypsum_max": round(max(si_gypsum), 3),
            "buffer_capacity_mM_per_pH_25c": round(buffer_capacity_mm_per_ph(tot, ph), 4),
            "strong_acid_mM_lowering_pH_by_0p1_25c": round(acid_tenth, 4)}
    return {"recipe_mM": RATIFIED_POINT_MM, "home": "01_02 §2.1 (⚖️ founder 2026-09-17)",
            "derivation": "oxalate removed; malic acid, KNO3, CaCl2 and MgSO4 at the geometric mid of their "
                          "pre-verdict range, two significant figures",
            "readings": [sc.key for sc in readings], "conditions": conditions_out,
            "not_covered": "the acid the working anode produces is not modelled — the strong-acid figure is the "
                           "scale, not a prediction of the drift"}


def figure(curves: dict) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(7.2, 5.4))
    lo, hi = RECIPE_RANGES_MM["cacl2"], RECIPE_RANGES_MM["oxalic"]
    ax.add_patch(plt.Rectangle((lo[0], hi[0]), lo[1] - lo[0], hi[1] - hi[0], color="tab:red", alpha=0.18,
                               label="canon recipe, 01_02 §2.1"))
    styles = {"hard_bound": ("k-", "hard bound (needs no malate constant)"),
              "selected": ("C0--", "NEA-selected, malate complexes absent"),
              "selected_guenzel_i0": ("C2:", "NEA-selected + Günzel malate at I = 0 (derived)")}
    for key, pts in curves.items():
        style, label = styles[key]
        ax.loglog([p[0] for p in pts], [p[1] for p in pts], style, lw=1.8, label=label)
    ax.set_xlabel("total calcium (mM)")
    ax.set_ylabel("largest total oxalate with SI(whewellite) ≤ 0 (mM)")
    ax.set_title("HW.3 — saturation boundary, worst case over both tests' pH and temperature", fontsize=10)
    ax.grid(True, which="both", alpha=0.3)
    ax.legend(fontsize=8, loc="lower left")
    fig.tight_layout()
    fig.savefig(OUT_PNG, dpi=150)
    plt.close(fig)


def main() -> int:
    t0 = time.perf_counter()
    banner("HW.3 — synthetic xylem sap: calcium oxalate saturation verdict and admissible window")
    checks = {"closed_form": closed_form_check(), "malate_equations": malate_check(),
              "analytic_expressions": analytic_check()}
    print(f"  closed form vs solver: |ΔSI| = {checks['closed_form']['abs_diff_si']:.1e}, "
          f"|Δbase| = {checks['closed_form']['abs_diff_base_mol_l']:.1e} mol/L")
    for label, row in checks["malate_equations"].items():
        print(f"  Eden & Bates {label}: equation {row['equation_25c']:.4f} vs printed {row['printed_constant_25c']:.4f}")
    guenzel = {metal: {"kapp_mM": GUENZEL_KAPP[metal][0], "ionic_strength": GUENZEL_KAPP[metal][1],
                       "log_k_apparent": round(guenzel_log_k(metal, False), 3),
                       "log_k_i0_derived": round(guenzel_log_k(metal, True), 3)} for metal in ("Ca", "Mg")}

    banner("Q1 — every canon corner × pH × temperature, per test")
    q1 = {test: {sc.key: q1_summary(sc, test) for sc in SCENARIOS} for test in TESTS}
    for test in TESTS:
        print(f"  {TESTS[test]['label']} (pH {TESTS[test]['ph'][0]}–{TESTS[test]['ph'][-1]}, "
              f"{TESTS[test]['t_c'][0]:.0f}–{TESTS[test]['t_c'][-1]:.0f} °C)")
        for sc in SCENARIOS:
            s = q1[test][sc.key]
            print(f"    {sc.key:<27s} SI(whewellite) {s['si_whewellite_min']:+.3f} … {s['si_whewellite_max']:+.3f}")
    # The hard bound must dominate every documented reading at every corner — the claim the window rests on.
    hb_sc = SC["hard_bound"]
    worst_gap = math.inf
    for test in TESTS:
        hb_rows = corner_rows(hb_sc, test)
        for sc in (s for s in SCENARIOS if s is not hb_sc):
            for h, r in zip(hb_rows, corner_rows(sc, test), strict=True):
                worst_gap = min(worst_gap, h["si"][WHEWELLITE] - r["si"][WHEWELLITE])
    assert worst_gap >= -1e-9, f"the hard bound falls below a documented reading by {-worst_gap:.2e}"
    # A documented reading is not the edge of what a missing constant could be, and the sign argument alone once
    # missed the ionic-strength channel — so each missing constant is also SWEPT, the rest of the bound held:
    # calcium malate beside the sequestered magnesium, magnesium malate on its own with magnesium oxalate-inert.
    swept = [Scenario(f"sweep_ca_{k:g}", "dominance sweep", hb_sc.oxalate_end, ca_malate=k, mg_malate="limit",
                      mg_oxalate_inert=True) for k in DOMINANCE_SWEEP_LOG_K]
    swept += [Scenario(f"sweep_mg_{k:g}", "dominance sweep", hb_sc.oxalate_end, mg_malate=k, mg_oxalate_inert=True)
              for k in DOMINANCE_SWEEP_LOG_K]
    sweep_gap = math.inf
    for test in TESTS:
        hb_rows = corner_rows(hb_sc, test)
        for sc in swept:
            for h, r in zip(hb_rows, corner_rows(sc, test), strict=True):
                sweep_gap = min(sweep_gap, h["si"][WHEWELLITE] - r["si"][WHEWELLITE])
    assert sweep_gap >= -1e-9, f"a swept malate constant rises above the hard bound by {-sweep_gap:.2e}"
    ionic_max = max(r["ionic_strength"] for test in TESTS for sc in SCENARIOS for r in corner_rows(sc, test))
    print(f"  hard bound above every documented reading by ≥ {worst_gap:.4f}, above every swept malate constant "
          f"(log K {DOMINANCE_SWEEP_LOG_K[0]:g}–{DOMINANCE_SWEEP_LOG_K[-1]:g}) by ≥ {sweep_gap:.2e}")
    for sc in SCENARIOS:
        log_ks = [s.log_ks for s in build(sc).solids[:3]]
        for t_c in sorted({t for spec in TESTS.values() for t in spec["t_c"]}):
            ks = [lk(t_c + 273.15) for lk in log_ks]
            assert ks[0] < ks[1] < ks[2], "whewellite is not the least soluble hydrate"
    be_camal = {test: break_even_camal(test) for test in TESTS}
    i_low = OXALATE_ENDS.index("si_low")
    be_ks = {test: round(LOG_KS_WHEWELLITE[i_low] + q1[test]["si_lowest_documented"]["si_whewellite_min"], 3)
             for test in TESTS}
    base_na_gap = max(abs(corner(SC["selected"], where(r), r["ph"], r["t_c"], "Na")["si"][WHEWELLITE]
                          - r["si"][WHEWELLITE]) for test in TESTS for r in corner_rows(SC["selected"], test))
    for test in TESTS:
        b = be_camal[test]
        print(f"  {test}: break-even whewellite log Ks(25 °C) {be_ks[test]:.3f}; calcium malate log K° "
              f"{b['log_k_camal_break_even']:.3f} (strongest documented {b['strongest_documented_reading_log_k']:.3f}), "
              f"holding {b['calcium_held_by_malate_at_break_even']:.0%} of the calcium")

    banner("Q2 — admissible window (partner ion's largest total at SI ≤ 0, worst case over the test's band)")
    windows = {key: {test: {fixed: [partner_limit(SC[key], conditions((test,)), fixed, level) for level in FIXED_LEVELS_MM]
                            for fixed in ("Ca", "Ox")} for test in TESTS} for key in WINDOW_SCENARIOS}
    for key in WINDOW_SCENARIOS:
        for test in TESTS:
            ca_side = " / ".join(f"{w['partner_max_total_uM']:.2f}" for w in windows[key][test]["Ca"])
            ox_side = " / ".join(f"{w['partner_max_total_uM']:.2f}" for w in windows[key][test]["Ox"])
            print(f"  {key:<27s} {test:<11s} Ca 0.5/1/2 mM → oxalate ≤ {ca_side} µM · oxalate 0.5/1/2 mM → Ca ≤ {ox_side} µM")
    for key in WINDOW_SCENARIOS:
        for test in TESTS:
            for fixed in ("Ca", "Ox"):
                for hb, w in zip(windows["hard_bound"][test][fixed], windows[key][test][fixed], strict=True):
                    assert hb["partner_max_total_uM"] <= w["partner_max_total_uM"] * (1.0 + 1e-6), \
                        f"hard-bound window wider than {key} ({test}, {fixed})"
    banner("Q5 — how far each reading moves the window: its partner maximum over the hard bound's")
    q5 = {}
    for key in WINDOW_SCENARIOS[1:]:
        ratios = [w["partner_max_total_uM"] / hb["partner_max_total_uM"] for test in TESTS for fixed in ("Ca", "Ox")
                  for hb, w in zip(windows["hard_bound"][test][fixed], windows[key][test][fixed], strict=True)]
        q5[key] = [round(min(ratios), 3), round(max(ratios), 3)]
        print(f"  {key:<27s} ×{min(ratios):.2f} … ×{max(ratios):.2f}")
    # The two ratios above bundle the oxalate spread and the magnesium limit with the malate reading, so the reading's
    # OWN share is taken against the NEA-selected window it is added to.
    malate_over_selected = {}
    for key in ("selected_guenzel_apparent", "selected_guenzel_i0"):
        ratios = [w["partner_max_total_uM"] / s["partner_max_total_uM"] for test in TESTS for fixed in ("Ca", "Ox")
                  for s, w in zip(windows["selected"][test][fixed], windows[key][test][fixed], strict=True)]
        malate_over_selected[key] = [round(min(ratios), 3), round(max(ratios), 3)]
        print(f"  {key:<27s} over NEA-selected alone ×{min(ratios):.2f} … ×{max(ratios):.2f}")
    spread = [lo_end["partner_max_total_uM"] / hi_end["partner_max_total_uM"] for test in TESTS for fixed in ("Ca", "Ox")
              for hi_end, lo_end in zip(windows["spread_si_high"][test][fixed], windows["spread_si_low"][test][fixed],
                                        strict=True)]
    oxalate_spread = [round(min(spread), 3), round(max(spread), 3)]
    print(f"  oxalate constants, SI-lowering end over SI-raising end ×{min(spread):.2f} … ×{max(spread):.2f}")

    banner("The pH verdict's price here: the hard-bound window at ONE pH set-point, over every test temperature")
    both = {fixed: [min(windows["hard_bound"][t][fixed][i]["partner_max_total_uM"] for t in TESTS)
                    for i in range(len(FIXED_LEVELS_MM))] for fixed in ("Ca", "Ox")}
    by_ph = {}
    for ph in sorted({p for spec in TESTS.values() for p in spec["ph"]}):
        per = {fixed: [round(partner_limit(SC["hard_bound"], conditions_at_ph(ph), fixed, level)["partner_max_total_uM"], 4)
                       for level in FIXED_LEVELS_MM] for fixed in ("Ca", "Ox")}
        ratios = [x / y for fixed in ("Ca", "Ox") for x, y in zip(per[fixed], both[fixed], strict=True)]
        by_ph[f"{ph:.1f}"] = {"partner_max_total_uM": per,
                              "over_both_tests_window": [round(min(ratios), 3), round(max(ratios), 3)]}
        print(f"  pH {ph:.1f}: Ca 0.5/1/2 → oxalate ≤ " + " / ".join(f"{v:.2f}" for v in per["Ca"])
              + " µM · oxalate 0.5/1/2 → Ca ≤ " + " / ".join(f"{v:.2f}" for v in per["Ox"])
              + f" µM (×{min(ratios):.2f}–{max(ratios):.2f} of the both-tests window)")
    curve_levels = tuple(float(v) for v in np.geomspace(0.005, 2.0, 12))
    curves = {key: [(level, partner_limit(SC[key], conditions(tuple(TESTS)), "Ca", level)["partner_max_total_uM"] * 1e-3)
                    for level in curve_levels] for key in ("hard_bound", "selected", "selected_guenzel_i0")}

    banner("Q3 — the base the recipe does not name")
    q3 = {}
    for test in TESTS:
        rows = corner_rows(SC["selected"], test)
        base = [r["base_mM"] for r in rows]
        k_total = [r["base_mM"] + r["kno3"] for r in rows]
        top = rows[int(np.argmax(base))]
        q3[test] = {"base_mM_range": [round(min(base), 3), round(max(base), 3)],
                    "potassium_total_mM_range_if_koh": [round(min(k_total), 3), round(max(k_total), 3)],
                    "sodium_total_mM_range_if_naoh": [round(min(base), 3), round(max(base), 3)],
                    "largest_base_corner": where(top)}
        print(f"  {test}: base {min(base):.2f}–{max(base):.2f} mM; K+ total as KOH {min(k_total):.2f}–{max(k_total):.2f} mM "
              f"against the recipe's KNO3 {RECIPE_RANGES_MM['kno3'][0]:.0f}–{RECIPE_RANGES_MM['kno3'][1]:.0f} mM")
    print(f"  NaOH instead of KOH moves SI(whewellite) by at most {base_na_gap:.4f} at any corner")

    banner("Q4 — buffer capacity at 25 °C (KNO3 2, CaCl2 0.5, MgSO4 0.2 mM)")
    window_ox_mm = windows["hard_bound"]["coin"]["Ca"][0]["partner_max_total_uM"] * 1e-3
    q4 = []
    for malic in RECIPE_RANGES_MM["malic"]:
        for label, ox in (("canon 0.5 mM", 0.5), ("canon 2 mM", 2.0),
                          (f"hard-bound window at Ca 0.5 mM ({window_ox_mm * 1e3:.1f} µM)", window_ox_mm),
                          ("none", 0.0)):
            comp = {"malic": malic, "oxalic": ox, "kno3": 2.0, "cacl2": 0.5, "mgso4": 0.2}
            beta = {ph: round(buffer_capacity_mm_per_ph(totals_mm(comp), ph), 4) for ph in (4.5, 5.0, 5.5)}
            q4.append({"malic_mM": malic, "oxalate": label, "oxalate_mM": round(ox, 6), "beta_mM_per_pH": beta})
            print(f"  malic {malic:.0f} mM, oxalate {label:<40s} β = "
                  + " · ".join(f"{b:.3f} (pH {p})" for p, b in beta.items()) + " mM/pH")

    banner("Q6 — the ratified point (⚖️ 2026-09-17): base, buffer capacity")
    q6 = ratified_point()
    for name, c in q6["conditions"].items():
        print(f"  {name} pH {c['ph']}: KOH {c['base_koh_mM'][0]:.3f}–{c['base_koh_mM'][1]:.3f} mM, K+ total "
              f"{c['potassium_total_mM'][0]:.3f}–{c['potassium_total_mM'][1]:.3f} mM; β(25 °C) "
              f"{c['buffer_capacity_mM_per_pH_25c']:.3f} mM/pH, strong acid for −0.1 pH "
              f"{c['strong_acid_mM_lowering_pH_by_0p1_25c']:.4f} mM; SI(gypsum) ≤ {c['si_gypsum_max']:+.2f}")

    banner("Prices of the two directions")
    loss = []
    for malic in RECIPE_RANGES_MM["malic"]:
        by_ox = {r["oxalate_mM"]: r["beta_mM_per_pH"] for r in q4 if r["malic_mM"] == malic}
        cut = by_ox[round(window_ox_mm, 6)]
        loss += [(1.0 - cut[ph] / beta, {"malic_mM": malic, "canon_oxalate_mM": ox, "ph": ph})
                 for ox in RECIPE_RANGES_MM["oxalic"] for ph, beta in by_ox[ox].items()]
    loss_lo, loss_hi = min(loss, key=lambda p: p[0]), max(loss, key=lambda p: p[0])
    glush = {test: [glushinskite_at_calcium_cut(test, x["fixed_level_mM"], x["partner_max_total_uM"] * 1e-3)
                    for x in windows["hard_bound"][test]["Ox"]] for test in TESTS}
    hb = windows["hard_bound"]
    prices = {
        "cut_oxalate_keep_calcium": {
            "oxalate_max_uM_at_calcium_levels": {t: [x["partner_max_total_uM"] for x in hb[t]["Ca"]] for t in TESTS},
            "fold_below_canon_oxalate_floor": {t: [round(RECIPE_RANGES_MM["oxalic"][0] * 1e3 / x["partner_max_total_uM"], 1)
                                                   for x in hb[t]["Ca"]] for t in TESTS},
            "buffer_capacity_lost_fraction_range": [round(loss_lo[0], 3), round(loss_hi[0], 3)],
            "buffer_capacity_lost_least_at": loss_lo[1], "buffer_capacity_lost_most_at": loss_hi[1]},
        "cut_calcium_keep_oxalate": {
            "calcium_max_uM_at_oxalate_levels": {t: [x["partner_max_total_uM"] for x in hb[t]["Ox"]] for t in TESTS},
            "fold_below_canon_calcium_floor": {t: [round(RECIPE_RANGES_MM["cacl2"][0] * 1e3 / x["partner_max_total_uM"], 1)
                                                   for x in hb[t]["Ox"]] for t in TESTS},
            "glushinskite_scoping_si_at_window_edge": glush},
        "either_direction": {"base_mM_max": max(q3[t]["base_mM_range"][1] for t in TESTS),
                             "potassium_total_mM_max_if_koh": max(q3[t]["potassium_total_mM_range_if_koh"][1] for t in TESTS)},
    }
    print(f"  cut oxalate: buffer capacity lost {loss_lo[0]:.1%} … {loss_hi[0]:.1%} "
          f"(most at {loss_hi[1]}, least at {loss_lo[1]})")
    for test in TESTS:
        print(f"  cut calcium ({test}): glushinskite scoping SI at the window edge "
              + " / ".join(f"{g['si_glushinskite_scoping_max']:+.3f}" for g in glush[test]) + " at oxalate 0.5/1/2 mM")

    elapsed = time.perf_counter() - t0
    w = windows["hard_bound"]
    same_for_both = all(a["partner_max_total_uM"] == b["partner_max_total_uM"] for fixed in ("Ca", "Ox")
                        for a, b in zip(w["coin"][fixed], w["accelerated"][fixed], strict=True))

    def fmt(side, test):
        return " / ".join(f"{x['partner_max_total_uM']:.1f}" for x in w[test][side])

    sel = {test: q1[test]["selected"] for test in TESTS}
    low = {test: q1[test]["si_lowest_documented"] for test in TESTS}
    all_super = all(q1[test][sc.key]["every_corner_supersaturated"] for test in TESTS for sc in SCENARIOS)
    b = min(be_camal.values(), key=lambda v: v["log_k_camal_break_even"])
    window_text = (f"calcium held at 0.5 / 1 / 2 mM → total oxalate ≤ {fmt('Ca', 'coin')} µM; oxalate held at "
                   f"0.5 / 1 / 2 mM → total calcium ≤ {fmt('Ox', 'coin')} µM"
                   + (" — the same in both tests" if same_for_both else
                      f" (coin); accelerated: oxalate ≤ {fmt('Ca', 'accelerated')} µM, calcium ≤ {fmt('Ox', 'accelerated')} µM"))
    def signed(x: float) -> str:
        return f"{x:+.2f}".replace("-", "−")

    def plain(x: float) -> str:
        return f"{x:.2f}".replace("-", "−")

    verdict = (
        ("Every corner of the PRE-VERDICT 01_02 §2.1 recipe (the ranges canon replaced with a point on 2026-09-17 — "
         "q6_ratified_point) is supersaturated to whewellite in both tests, under every constant reading evaluated. "
         if all_super else "NOT every pre-verdict corner is supersaturated — see q1_corners. ")
        + f"NEA-selected constants: SI {signed(sel['coin']['si_whewellite_min'])} … {signed(sel['coin']['si_whewellite_max'])} "
        f"(coin, pH 4.5–5.5, 20–25 °C) and {signed(sel['accelerated']['si_whewellite_min'])} … "
        f"{signed(sel['accelerated']['si_whewellite_max'])} (accelerated, pH 5.0–5.5, 20–40 °C); the SI-lowest documented "
        f"reading still leaves the least-supersaturated corner at SI {signed(min(v['si_whewellite_min'] for v in low.values()))}. "
        f"With every oxalate constant at its SI-lowering end, a corner turns undersaturated only if whewellite log Ks at "
        f"25 °C reaches {plain(min(be_ks.values()))} (NEA selects −8.73 ± 0.06), or calcium malate log K° reaches "
        f"{plain(b['log_k_camal_break_even'])} — {plain(b['margin_over_strongest_documented'])} above the strongest documented "
        f"reading ({plain(b['strongest_documented_reading_log_k'])}, itself derived here) — holding "
        f"{b['calcium_held_by_malate_at_break_even']:.0%} of the calcium. Admissible window on the HARD BOUND, safe whatever "
        f"the calcium and magnesium malate constants are: {window_text}. The NEA-selected constants widen it "
        f"×{q5['selected'][0]:.2f}–{q5['selected'][1]:.2f}; the malate readings add at most "
        f"×{malate_over_selected['selected_guenzel_i0'][1]:.2f} on top of those. Which ion to lower is NOT decided here, and "
        f"a window edge is the saturation point itself, not a margin."
    )
    out = {
        "script": Path(__file__).name,
        "question": "Is the synthetic sap of 01_02 §2.1 supersaturated to calcium oxalate, and what calcium/oxalate "
                    "window keeps whewellite undersaturated in both tests' bands? (00_07 HW.3)",
        "recipe_ranges_mM": RECIPE_RANGES_MM,
        "tests": TESTS,
        "activity_model": {"equation": "Davies, log γ = −A z² (√I/(1+√I) − 0.3 I)", "a_table": DAVIES_A_TABLE,
                           "ionic_strength_max_mol_l": round(ionic_max, 5), "validity_mol_kg": DAVIES_I_MAX,
                           "source": TDB2},
        "constants": {
            "oxalate_ends": {"order": OXALATE_ENDS, "log_k_hox": LOG_K_HOX, "log_k_caox": LOG_K_CAOX,
                             "log_b_caox2": LOG_B_CAOX2, "log_k_mgox": LOG_K_MGOX, "log_b_mgox2": LOG_B_MGOX2,
                             "log_ks_whewellite": LOG_KS_WHEWELLITE, "log_ks_weddellite": LOG_KS_WEDDELLITE,
                             "log_ks_caoxite": LOG_KS_CAOXITE, "source": NEA9},
            "malic_acid": {"pk1_equation": EB_PK1, "pk2_equation": EB_PK2, "k_25c_printed": EB_K_25C,
                           "source": EDEN_BATES},
            "malate_complexes_readings": {**guenzel, "source": GUENZEL,
                                          "status": "NOT FOUND at I = 0 in any open primary; readings only"},
            "sulfate_and_other_solids": {sp.name: sp.source for sp in (*SULFATE, GYPSUM, GLUSHINSKITE)},
            "magnesium_sequestration_limit_log_k": SEQUESTRATION_LOG_K,
            "scenarios": {sc.key: {"label": sc.label, "oxalate_end": sc.oxalate_end, "ca_malate": sc.ca_malate,
                                   "mg_malate": sc.mg_malate, "mg_oxalate_inert": sc.mg_oxalate_inert}
                          for sc in SCENARIOS},
        },
        "verification": {**checks, "hard_bound_min_si_margin_over_every_reading": round(worst_gap, 6),
                         "hard_bound_min_si_margin_over_swept_malate_constants": round(sweep_gap, 6),
                         "dominance_sweep_log_k": DOMINANCE_SWEEP_LOG_K,
                         "hard_bound_window_is_the_narrowest": True, "whewellite_is_the_least_soluble_hydrate": True},
        "q1_corners": {"per_test": q1, "break_even_whewellite_log_ks_25c": be_ks, "break_even_calcium_malate": be_camal,
                       "break_even_conditions": "every oxalate constant at its SI-lowering end, no magnesium malate"},
        "q2_window": {"per_scenario": windows, "hard_bound_same_for_both_tests": same_for_both,
                      "hard_bound_by_single_ph": by_ph,
                      "boundary_curve_mM": {k: [[round(x, 6), round(y, 6)] for x, y in v] for k, v in curves.items()}},
        "q3_base": {**q3, "max_si_change_naoh_vs_koh": round(base_na_gap, 5)},
        "q4_buffer_capacity": {"t_c": 25.0, "background_mM": {"kno3": 2.0, "cacl2": 0.5, "mgso4": 0.2},
                               "constants": "selected", "rows": q4},
        "q5_window_over_hard_bound": q5,
        "q5_malate_reading_over_selected": malate_over_selected,
        "q5_oxalate_spread_low_end_over_high_end": oxalate_spread,
        "q6_ratified_point": q6,
        "prices": prices,
        "verdict": verdict,
        "caveats": [
            "Hypothesis from literature constants, not measurement (00_06 §0). No prepared solution was analysed.",
            "Activity model: Davies. Its source states it works fairly well up to 0.1 mol/kg and does not use it in its "
            f"reviews; the largest ionic strength met at any canon corner under any reading is {ionic_max:.3f} mol/L. "
            "Concentrations are molar, the constants molal; at these dilutions the two scales differ by the density of "
            "water.",
            "Varied: the oxalate constants (NEA spread) and the malate complexes (readings, sweep, limit). Single values: "
            "the malic-acid protonation, the sulfate ion pairs and Davies A(T).",
            "Neutral species carry activity coefficient 1; OH- is not modelled (below 1e-8 mol/L at pH ≤ 5.75); pH is "
            "−log10 of the H+ activity.",
            "Complexes for which NEA selects no enthalpy — the calcium and magnesium oxalate complexes — keep their "
            "25 °C constants over 20–40 °C.",
            "pH on a 0.5-unit grid and temperature on a 5 °C grid; every band end is a grid point.",
            "Günzel's malate constants are APPARENT (Na+ medium, pHa 7.4, no Na+/K+–malate pair separated out) and the "
            "I = 0 values are a Davies correction from I = 0.104 / 0.124, past that equation's stated range. They enter "
            "only the readings; the hard bound uses none of them — its magnesium half is a sequestration LIMIT.",
            "The hard bound rests on the SIGN of each malate complex's effect through BOTH channels, mass action and "
            "ionic strength: no calcium malate, and every magnesium ion held as a neutral complex that binds no oxalate. "
            "Its dominance is asserted at every corner against every documented reading and against calcium and "
            "magnesium malate swept over the log K grid in `verification`, and its window is asserted the narrowest.",
            "NOT bounded: background ion pairs with no constant in the sources used — K+ or Na+ with malate, KNO3(aq) — "
            "would lower the ionic strength and raise the SI, and the hard bound does not cover that channel.",
            "SI < 0 is the thermodynamic criterion. Precipitation kinetics and a metastable zone are not modelled, and a "
            "window edge is the saturation point, not a margin — how far below it to prepare is part of the choice.",
            f"KOH is taken as the base; NaOH moves SI by at most {base_na_gap:.4f} at any corner.",
        ],
        "not_modelled": [
            {"item": "glucose", "why": "not part of the 01_02 §2.1 corrosion recipe; the coin test adds it (01_03 §3.5)"},
            {"item": "phytosiderophores (a pre-verdict optional row, out of the recipe since 2026-09-17)", "why": "no constants in the sources used",
             "effect_of_omission": "not assessed"},
            {"item": "calcium malate as a solid", "why": "no solubility product in the sources used",
             "effect_of_omission": "a second precipitate the window does not check"},
            {"item": "calcium ligands other than oxalate, sulfate and the malate readings (Cl-, NO3-, HMal-)",
             "why": "not in the constant sets",
             "effect_of_omission": "overstates the SI through mass action; their ionic-strength channel is not assessed"},
            {"item": "magnesium ligands other than oxalate, sulfate and the malate readings",
             "why": "not in the constant sets",
             "effect_of_omission": "covered by the hard bound, which holds every magnesium ion as a neutral complex"},
            {"item": "K+/Na+–oxalate ion pairs", "why": "not in the constant sets",
             "effect_of_omission": "overstates the SI through mass action; their ionic-strength channel is not assessed"},
            {"item": "K+/Na+–malate and KNO3(aq) ion pairs", "why": "no constant in the sources used",
             "effect_of_omission": "the pairs would lower the ionic strength and raise the SI, so leaving them out "
                                   "UNDERSTATES it — not covered by the hard bound"},
            {"item": "atmospheric CO2", "why": "not in the constant sets", "effect_of_omission": "not assessed"},
            {"item": "glushinskite as a verdict", "why": "NEA recommends no solubility product (scoping value only)",
             "effect_of_omission": "its SI is reported from the scoping value and never used"},
        ],
    }
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    figure(curves)
    banner("Verdict")
    print(f"  {verdict}")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)} and {OUT_PNG.name} ({elapsed:.0f} s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
