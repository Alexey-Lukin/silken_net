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
ranges with a POINT, and Q6 is what that point takes to prepare. That point was revised on 2026-10-18 (⚖️ founder):
its four ions were geometric mids of ranges with no source found, and measured conifer sap came in below it in every
row a number exists for — Q7 is the revised point, whose ions stand on those measurements; Q6 stays as the price the
revision is read against.

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
      buffers — the number that turns medium replacement from a courtesy into a condition of the test. SUPERSEDED
      2026-10-18 by Q7; kept, dated, never re-pinned (When Modifying #12).
  Q7  THE REVISED POINT (⚖️ founder 2026-10-18 — the live recipe). Calcium, magnesium and potassium at the geometric
      mid of their measured range at the BOTTOM OF THE STEM, where the anchor sits (Norway spruce, Dambrine et al.
      1995, Table 1 — natural stands; the fertilized plot is excluded); nitrate at the mid of the range read off the Scots pine sap figure (Henriksson 2012); malic
      acid not measured but SOLVED — the amount whose KOH to pH 5.75 (selected reading, 25 °C) makes exactly that
      potassium. Same questions as Q6: base, potassium total, ionic strength, buffer capacity.
  Q8  THE BROADLEAF POINT (⚖️ founder 2026-10-18) — a model input for 85's broadleaf and oak anchor parts, NOT a
      wet-test recipe. The same rule as Q7 on European beech sap from the bottom of the stem (Glavac et al. 1990,
      a stand whose methods name no fertilization or liming, medians of five trees on 26 dates read off its
      figures): Ca and Mg at the geometric mid of the dated medians, pH at their median; organic acids are not
      reported there, and nitrate — printed three years later for what is inferred to be the same stand and dates
      (Glavac & Jochheim 1993, read off its figures; the identity is inferred, not printed — 01_02 §2.1 ⊕ ⚖️
      2026-10-22) — enters at the geometric mid of its dated values as KNO3 on potassium, as pine's does
      (⚖️ founder 2026-10-22); malic acid solved from the mid potassium less that nitrate. The summer dates whose sap
      pH falls to ≈ 4.5 — coinciding, the paper says, with its highest nitrate, and the 1993 figures put the three
      highest nitrates on exactly these dates — are returned beside it with their nitrate; the point's malate solve
      does not describe them. Broadleaf (birch/maple) and oak both ride on it as proxies; oak's own trunk sap
      (Q. rubra, one autumn date) is returned as a further reading, and two CROWN-TWIG readings beside it — Soper 2018
      (two oaks and sugar maple, K · Ca · Mg) and Schneider 1996 (nitrate of beech and spruce together) — set
      against the dated range behind the point (00_07 HW.3 (А)); neither moves it.

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
   saturation point itself, not a margin. Q7's ions stand on measured CONIFER sap — Norway spruce for calcium,
   magnesium and potassium, Scots pine only for nitrate; no Pinus sylvestris calcium, magnesium or potassium and no
   oxalate measurement of any conifer is in the tree, the malate is derived, and dissolved CO2 (a buffer real sap may
   carry) is not in the recipe. The activity model is Davies, which its own source says
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
from scipy.stats import t as student_t

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = "Does the synthetic xylem sap precipitate its own chelator? Saturation verdict and admissible recipe window."  # its row in the paper SI (72): English, no repo jargon

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
# ── The POINT of 2026-09-17 (⚖️ founder) — canon 01_02 §2.1 specified it until 2026-10-18. Oxalate out (Q1–Q2: it
# does not coexist with millimolar calcium); the other four at the geometric mid of their pre-verdict range to two
# significant figures, asserted in `point_2026_09_17()` so the point cannot drift from its own derivation. pH — kept
# by the revision: the set-point is the measured Pinus sylvestris sap pH (Tarvainen et al. 2023, New Phytol. 238:926,
# Table 1, control trees), for both tests; the side series is uncoated coupons under ICP-MS only, in the coin test. ──
POINT_2026_09_17_MM = {"malic": 2.2, "oxalic": 0.0, "kno3": 3.2, "cacl2": 1.0, "mgso4": 0.45}
# ⚠️ SUPERSEDED 2026-10-18 (⚖️ founder, 01_02 §2.1): measured conifer sap came in below it in every row a number exists
# for. Kept because Q6 prices it and the revision's price is read against it — never the live recipe again.
#
# ── The LIVE ratified point (⚖️ founder 2026-10-18) — canon 01_02 §2.1 specifies it, test_doc_cache_sync pins the
# table to Q7, and 85 imports it by this name. Its ions stand on MEASUREMENTS, kept here in the units the source
# prints so the mM are derived, never typed: Norway spruce sap displaced from the BOTTOM OF THE STEM (the anchor
# sits at the trunk base), Dambrine et al. 1995, Plant Soil 168–169:233–241, doi:10.1007/BF00029333, Table 1 — the
# «bottom of the stem» rows, read from the page image, EXCEPT the fertilized plot: years of complete nutrient solution
# that tripled height growth is an intervention, not a stand (⚖️ founder 2026-10-18 — the point was first ratified
# with it, and refined the same day). Spruce stands in for Scots pine here, and in which direction it errs for a pine
# stand on sand is not established — in Dambrine's table only the fertilized plot, excluded here, runs higher. Nitrate: current-year shoot sap of ≈ 90-year Pinus sylvestris, Vindeln, Sept–Oct 2011, before and
# after a nitrate drench, Henriksson 2012, SLU Examensarbeten 2012:14, Fig. 1 — READ OFF A FIGURE, a master's thesis
# (supervised by Näsholm, co-author of the pH source). The point = the geometric mid of each range to two significant
# figures; malic acid is not measured anywhere in these sources, so it is SOLVED: the amount whose KOH to the pH
# set-point (selected reading, POINT_SOLVE_T_C) makes the measured-mid potassium. Asserted in `revised_point()`.
MEASURED_SAP_ROWS_MG_L = {   # Table 1, «Bottom of the stem», Ca · Mg · K in mg/L as printed
    "dambrine_1992_acid_brown_soil_mg_deficient": {"Ca": 4.0, "Mg": 1.0, "K": 23.0},
    "this_study_podzol_control_n_deficient": {"Ca": 12.7, "Mg": 2.2, "K": 36.6},
    "this_study_podzol_fertilized": {"Ca": 20.2, "Mg": 3.6, "K": 58.6},
    "this_study_podzol_drought_stress": {"Ca": 11.0, "Mg": 2.3, "K": 28.8},
}
MEASURED_SAP_EXCLUDED = {"this_study_podzol_fertilized": "years of complete nutrient solution, height growth ×3 — an "
                                                         "intervention, not a natural stand (⚖️ founder 2026-10-18)"}
MOLAR_G = {"Ca": 40.078, "Mg": 24.305, "K": 39.098}
_ROWS_USED = [r for k, r in MEASURED_SAP_ROWS_MG_L.items() if k not in MEASURED_SAP_EXCLUDED]
MEASURED_SAP_TRUNK_BASE = {key: {"ion": ion, "mg_l": (min(r[ion] for r in _ROWS_USED), max(r[ion] for r in _ROWS_USED)),
                                 "molar_g": MOLAR_G[ion]}
                           for key, ion in (("cacl2", "Ca"), ("mgso4", "Mg"), ("k_total", "K"))}
MEASURED_SAP_SOURCE = ("Dambrine E., Martin F., Carisey N., Granier A., Hällgren J.-E., Bishop K. 1995, Plant Soil "
                       "168-169:233-241, doi:10.1007/BF00029333, Table 1, Picea abies, bottom of the stem — every row "
                       "but the fertilized plot")
MEASURED_NITRATE_MM = (0.002, 0.012)
MEASURED_NITRATE_SOURCE = ("Henriksson N. 2012, Measuring N uptake and transport in Pinus sylvestris to estimate "
                           "mycorrhizal transfer efficiency, SLU Examensarbeten 2012:14, Fig. 1 (read off the figure; "
                           "master's thesis, not peer-reviewed)")
POINT_SOLVE_T_C = 25.0
RATIFIED_POINT_MM = {"malic": 0.40, "oxalic": 0.0, "kno3": 0.0049, "cacl2": 0.18, "mgso4": 0.062}
RATIFIED_PH = {"setpoint": (5.75, ("coin", "accelerated")), "side_series": (4.5, ("coin",))}
# Temperatures of the LIVE protocol, split from the pre-verdict bands in TESTS the same way pH is: the accelerated
# test is a 40 °C ISOTHERM with a temperature log (⚖️ founder 2026-09-24, 01_02 §2 «Концепція»; the earlier
# 20–40 °C cycle belongs to no test any more), the coin test keeps 20–25 °C (01_03 §3.5). Q6 prices these;
# Q1–Q5 keep pricing the TESTS bands the verdicts replaced.
RATIFIED_T_C = {"coin": (20.0, 25.0), "accelerated": (40.0,)}
#
# ── Q8, the BROADLEAF point (⚖️ founder 2026-10-18) — a MODEL INPUT for 85's broadleaf and oak anchor parts, never a
# wet-test recipe: the coin and the corrosion tests stay on the pine point above. Same rule as Q7: the bottom of the
# stem, an unfertilized stand, the geometric mid of the measured range, malic acid solved from potassium. Source: European
# beech (Fagus sylvatica), Glavac, Koenies & Ebben 1990, New Phytol. 116:47–54, doi:10.1111/j.1469-8137.1990.tb00509.x
# — a 42-year stand near Kassel on acid brown earth (its methods name no fertilization or liming), five trees felled
# every two weeks from 27 Oct 1988 to 12 Oct 1989 (the summary's «mid-October 1988 to mid-October 1989»), the lowest trunk segment (10–140 cm above ground) displaced with
# water and its second ~200 ml fraction, «pure tracheal sap», analysed by AAS; pH by glass electrode on fresh sap.
# Each row is the MEDIAN OF FIVE TREES on one date, READ OFF Figs 2 (Ca), 4 (Mg), 7 (K) and 10 (pH) from the page
# images (2026-10-18; read-off error → BEECH_READ_OFF_ERROR below); pH is not plotted for
# 27 Oct, 10 Nov and 24 Nov 1988. Nitrate and organic acids are NOT reported there — the paper says its low-pH dates
# «coincided with the highest nitrate xylem sap concentration» and cites unpublished data. The nitrate was printed
# later (Glavac & Jochheim 1993 — BEECH_TRUNK_BASE_NITRATE below), and the point takes it by the same rule (⚖️ founder
# 2026-10-22, HW.3 (А₀)): the geometric mid of the dated values, as KNO3 on potassium the way pine's is. Malic acid is
# solved as for pine, from the potassium less that nitrate — still a ceiling on that side (real sap also balances
# potassium with other anions — sulphate, amino acids), while calcium and magnesium sit on
# unbuffered chloride and sulphate and CO2, phosphate and amino-acid buffers are absent (each pushes the other way):
# the direction of the total buffer is NOT established. Broadleaf (birch, maple) and oak sit on this point as proxies
# — beech for the diffuse-porous part, Fagaceae for oak, no Q. robur or petraea trunk sap having been found — the move
# Q7 makes with Norway spruce for Scots pine.
BEECH_TRUNK_BASE_MEDIANS = {   # date: (Ca mg/L · Fig 2, Mg mg/L · Fig 4, K mg/L · Fig 7, pH · Fig 10 or None)
    "1988-10-27": (21, 4.4, 56, None), "1988-11-10": (41, 8.3, 90, None),
    "1988-11-24": (34, 7.6, 63, None), "1988-12-08": (40, 6.5, 75, 6.50), "1988-12-22": (38, 8.8, 73, 6.38),
    "1989-01-05": (42, 7.6, 62, 6.38), "1989-01-19": (32, 7.4, 58, 6.30), "1989-02-02": (16, 3.8, 46, 6.08),
    "1989-02-16": (42, 8.4, 50, 6.05), "1989-03-02": (32, 5.0, 44, 6.18), "1989-03-16": (44, 13.8, 68, 6.02),
    "1989-03-30": (89, 19.3, 46, 5.80), "1989-04-13": (62, 18.4, 55, 5.68), "1989-04-27": (75, 11.4, 86, 5.58),
    "1989-05-11": (43, 7.8, 47, 5.70), "1989-05-25": (18, 4.1, 29, 4.55), "1989-06-08": (27, 9.1, 48, 5.73),
    "1989-06-22": (8, 2.7, 26, 5.60), "1989-07-06": (13, 3.8, 38, 4.52), "1989-07-20": (12, 3.0, 44, 4.58),
    "1989-08-03": (11, 3.1, 34, 5.80), "1989-08-17": (9, 2.6, 38, 5.88), "1989-08-31": (9, 2.4, 82, 5.95),
    "1989-09-14": (9, 1.9, 90, 6.62), "1989-09-28": (13, 2.8, 184, 6.15), "1989-10-12": (10, 2.0, 190, 6.50),
}
BEECH_SOURCE = ("Glavac V., Koenies H., Ebben U. 1990, New Phytol. 116:47-54, doi:10.1111/j.1469-8137.1990.tb00509.x, "
                "Figs 2, 4, 7, 10 — Fagus sylvatica, lowest trunk segment, medians of five trees per date, read off the "
                "page images")
# The read-off error of one dated median off those figures (2026-10-18) — its one home: 85's flip control judges each
# threshold against it, and the docs that quote it are pinned to it.
BEECH_READ_OFF_ERROR = {"Ca_mg_l": 2.0, "Mg_mg_l": 0.3, "K_mg_l": 2.0, "pH": 0.03}
BEECH_ACID_DATES = ("1989-05-25", "1989-07-06", "1989-07-20")   # the paper's own named low-pH dates (p. 52)
BEECH_LOWEST_TREE_PH = 3.81    # Fig. 10, the lowest whisker (6 Jul 1989), read off
# Nitrate of the SAME stand on the SAME dates, printed three years later (⚖️ founder 2026-10-22, HW.3 (А₀) — option (А)
# with convention (а)): Glavac V., Jochheim H. 1993, Trees 7:237–241, doi:10.1007/bf00202080, Figs 1a (total N, mg/L)
# and 2a (its NO3-N share, %) — the panels of the stand on loess over basalt, the 42-year stand of its Table 1 («Acid
# brown earth, loess over basalt»); medians of five trees on the 26 month-days of the axis, which are the 26 keys of
# BEECH_TRUNK_BASE_MEDIANS (the axis prints no year). The identity of stand and dates is INFERRED, not printed: the
# 1993 paper cites Glavac et al. (1989) for its method, not the 1990 paper; for it — the stand and site of Table 1,
# «Every 14 days 5 trees in each of the 2 stands», the 26 dates 14 days apart, and its three highest nitrates on
# exactly the 1990 paper's three low-pH dates (asserted in broadleaf_point()). Segment: «10-110 cm above the ground».
# Read off the page image of the Springer preview (p. 238, sha256 440470dd…792f), both figures deskewed (1a −0.12°,
# 2a +0.13°) by a vertical offset linear in x. Two readings that share the scan and the axis calibration — R1 pixel
# rows, R2 by eye on the deskewed ruler, read after R1 — and a verifier's independent re-read of ten dates (its own
# slope, calibration on every labelled tick) that agrees with both within 0.15 mg/L and 0.13 %. 12 Oct's share median
# touches the axis line (0.40 %, ±1 px); 17 Aug's (≈ 1.2 %) is legible, 6 px above it. Nitrate per date is OUR
# arithmetic — the product of the two MEDIANS (total N × NO3-N share), not a median of per-tree products, which the
# figures do not give; the transcription is the mean of R1 and R2, and each reading's own point rides beside it.
BEECH_TRUNK_BASE_NITRATE = {   # date: (total N mg/L · Fig 1a R1, R2; NO3-N share % · Fig 2a R1, R2)
    "1988-10-27": (9.76, 9.8, 12.24, 12.2), "1988-11-10": (1.36, 1.6, 12.08, 12.1),
    "1988-11-24": (1.3, 1.5, 12.0, 12.0), "1988-12-08": (1.01, 1.0, 8.58, 8.5), "1988-12-22": (3.4, 3.6, 2.64, 2.6),
    "1989-01-05": (12.73, 12.7, 0.93, 1.0), "1989-01-19": (1.36, 1.5, 6.18, 6.2), "1989-02-02": (2.94, 3.1, 46.2, 46.2),
    "1989-02-16": (13.15, 13.0, 19.39, 19.4), "1989-03-02": (8.53, 8.6, 3.43, 3.4), "1989-03-16": (23.32, 23.3, 0.82, 0.85),
    "1989-03-30": (41.34, 41.3, 0.75, 0.75), "1989-04-13": (109.51, 109.5, 3.02, 3.0), "1989-04-27": (250.47, 250.5, 0.59, 0.6),
    "1989-05-11": (95.68, 95.7, 1.78, 1.75), "1989-05-25": (51.97, 52.0, 32.22, 32.2), "1989-06-08": (32.25, 32.3, 7.23, 7.2),
    "1989-06-22": (10.91, 11.0, 19.97, 20.0), "1989-07-06": (30.29, 30.3, 46.71, 46.7), "1989-07-20": (20.41, 20.5, 64.15, 64.1),
    "1989-08-03": (8.91, 9.0, 22.36, 22.4), "1989-08-17": (2.4, 2.5, 1.16, 1.2), "1989-08-31": (9.91, 10.0, 27.45, 27.5),
    "1989-09-14": (8.25, 8.3, 2.27, 2.2), "1989-09-28": (16.58, 16.6, 1.65, 1.7), "1989-10-12": (19.5, 19.5, 0.4, 0.4),
}
BEECH_NITRATE_SOURCE = ("Glavac V., Jochheim H. 1993, Trees 7:237-241, doi:10.1007/bf00202080, Figs 1a (total N) and 2a "
                        "(NO3-N share) — Fagus sylvatica, the 42-year stand on loess over basalt, lowest trunk segment, "
                        "medians of five trees per date, read off the page image of the Springer preview (p. 238, "
                        "sha256 440470dd…792f), deskewed; two readings (R1 pixel rows, R2 by eye) and a verifier's "
                        "independent re-read of ten dates")
MOLAR_G_N = 14.007
# Oak's OWN trunk sap, found the same day (the founder brought the lead): Quercus rubra, Van Die & Willemse 1975,
# Acta Bot. Neerl. 24(2):237–239, doi:10.1111/j.1438-8677.1975.tb01013.x, Table 1, read from the page image — two
# 16–20-year trees in the woods near Lunteren (NL), 27 Oct 1974, about half the leaves down; the stem cut at 1.8 m and
# the fluid that flowed freely out of the lowest wound surface of the ~4 m stem part collected (first ml discarded) —
# no applied pressure or suction. One autumn date, red oak, not Q. robur; no organic acids measured («organic» there is
# sugars and nitrogen). Kept as oak's second NAMED reading beside the beech proxy, not as a point.
OAK_RUBRA_VESSEL_SAP = {   # tree: pH range, K · Ca · Mg · Na in mg/ml as printed, conductivity in 10⁻⁶ Ω⁻¹cm⁻¹ (25 °C)
    "I": {"pH": (4.9, 5.0), "K_mg_ml": 0.170, "Ca_mg_ml": 0.0175, "Mg_mg_ml": 0.010, "Na_mg_ml": 0.0018, "conductivity": 593},
    "II": {"pH": (4.9, 5.0), "K_mg_ml": 0.177, "Ca_mg_ml": 0.0180, "Mg_mg_ml": 0.0115, "Na_mg_ml": 0.0040, "conductivity": 672},
}
OAK_RUBRA_SOURCE = ("Van Die J., Willemse P.C.M. 1975, Acta Bot. Neerl. 24(2):237-239, doi:10.1111/j.1438-8677.1975.tb01013.x, "
                    "Table 1 — Quercus rubra trunk xylem vessel sap, two trees, 27 Oct 1974, free outflow from the lowest "
                    "stem cut, read from the page image")
# Two CROWN-TWIG readings beside Q8 (00_07 HW.3 (А)) — read 2026-10-22 from the publishers' PDFs with the founder's
# approval and kept OUT of the tree (every margin prints the downloading account); an independent verifier re-read
# their numbers (exceptions named below). Neither is a point: crown twigs, not the trunk base, and no organic acid
# measured, so no malate to solve. They are set against the DATED range behind Q8 — under its read-off error — by
# crown_twig_readings(), never by eye.
# Soper F.M., Chamberlain S.D., Crumsey J.M., Gregor S., Derry L.A., Sparks J.P. 2018, J. Geophys. Res. Biogeosci.
# 123(10):3204–3215, doi:10.1029/2018JG004639 — eight trees per species with DBH > 25 cm; sap of canopy branches up
# to 1 cm in diameter in a PMS pressure chamber, 0.45 µm nylon filter, frozen, ICP-OES (pp. 3206–3207). The values
# stand only in Fig. 1 (p. 3208): 2014, June to September, monthly MEANS (not medians) ± 1 SD in µg/mL, the SD being
# the spread between the trees of a species and month (§3.1, p. 3208: sap «more variable (within a given species and
# month)» than foliage). The authors find no significant change of the sap concentrations with time except Al and Sr
# (§3.1, p. 3208), so a month's extreme is no seasonal signal they report. Means taken from the figure's VECTOR
# coordinates (axis ticks calibrated, ±0.01 µg/mL) and matched by an independent extraction; the paper sends its
# original data to Supporting Information S1 and Tables S1–S3, not opened. Nitrate, pH and organic acids are not
# measured. ⚠️ The abstract swaps the common names; §2.2 (p. 3206) and the figure's Latin legend give Q. rubra = red
# oak, Q. prinus = chestnut oak. Sugar maple rides beside the oaks: the `broadleaf` SKU names maple among the trees
# on Q8, so the same figure's maple cells are carried, not left out.
SOPER_2018_MONTHS = ("Jun", "Jul", "Aug", "Sep")
SOPER_2018_TREES_PER_SPECIES = 8   # p. 3206: eight trees per species — the n behind each mean ± SD
SOPER_2018_CROWN_SAP_UG_ML = {   # species: ion: monthly means (Jun, Jul, Aug, Sep), µg/mL
    "Quercus rubra": {"K": (136.46, 128.54, 75.00, 115.42), "Ca": (22.46, 28.64, 15.69, 31.79), "Mg": (7.28, 9.12, 2.10, 5.03)},
    "Quercus prinus": {"K": (98.96, 95.20, 82.08, 80.42), "Ca": (12.89, 26.78, 27.83, 26.08), "Mg": (4.27, 6.77, 4.82, 2.63)},
    "Acer saccharum": {"K": (85.62, 71.87, 96.25, 21.88), "Ca": (29.29, 38.79, 34.71, 4.43), "Mg": (6.02, 5.30, 4.80, 0.67)},
}
# ± 1 SD in µg/mL, same shape: half the bar where the figure draws one round its mean (the independent extraction's
# values); None where no bar can be attributed to the cell. Three magnesium bars reach the axis, so only their UPPER
# arm is the SD — named below — and those three come from the FIRST extraction only: the independent one left them
# unattributed and checked them only as a share of the mean (114 / 115 / 104 %), not as values.
SOPER_2018_CROWN_SAP_SD_UG_ML = {
    "Quercus rubra": {"K": (52.39, 105.10, 21.04, 81.77), "Ca": (10.62, 25.20, 6.88, 27.59), "Mg": (4.91, 10.37, 1.42, 5.77)},
    "Quercus prinus": {"K": (27.92, 92.40, 37.19, 21.24), "Ca": (5.51, None, 27.74, 13.77), "Mg": (1.99, 7.02, 4.65, 0.87)},
    "Acer saccharum": {"K": (79.48, 38.44, 27.39, 8.13), "Ca": (28.29, 20.21, 13.94, None), "Mg": (5.99, 2.77, 1.93, None)},
}
SOPER_2018_SD_UPPER_ARM_ONLY = (("Quercus rubra", "Mg", "Jul"), ("Quercus rubra", "Mg", "Sep"), ("Quercus prinus", "Mg", "Jul"))
SOPER_2018_SOURCE = ("Soper F.M., Chamberlain S.D., Crumsey J.M., Gregor S., Derry L.A., Sparks J.P. 2018, J. Geophys. Res. "
                     "Biogeosci. 123(10):3204-3215, doi:10.1029/2018JG004639, Fig. 1 (p. 3208) — 2014 monthly means ± 1 SD "
                     "of eight trees per species, sap of canopy branches up to 1 cm (pressure chamber, ICP-OES), read off the "
                     "figure's vector coordinates; original data in Supporting Information S1 and Tables S1-S3, not opened")
# Schneider S., Geßler A., Weber P., von Sengbusch D., Hanemann U., Rennenberg H. 1996, New Phytol. 134(1):103–114,
# doi:10.1111/j.1469-8137.1996.tb01150.x — Höglwald, a site under high N deposition (throughfall NH4+ 26 · NO3- 44
# kg/ha/yr, p. 104); twig sap (3–4-year sections, Scholander chamber, first exudate discarded, then +0.6 MPa for 2
# min, p. 105), nitrate by ion chromatography (p. 106), three trees, four campaigns in 1994. Nitrate c. 0.01 µmol/ml
# (p. 109), 0.01–0.025 µmol/ml through the year without seasonal variation (p. 112) — for BOTH species together: the
# text prints no beech-only number and the «Ni» bars of Fig. 2 cannot be read. µmol/ml = mM, and molar NO3- = molar
# NO3-N. Read from the page images (the text layer is an OCR'd scan) and re-read by the verifier; the authors set the
# result against Glavac & Jochheim 1993 (p. 112) — the source of Q8's nitrate; the verifier also confirmed the beech
# twigs from the sun crown (p. 105) and the beech of about 94 years (p. 104). ⊕ Read from the page images on 2026-10-24
# when this was entered, NOT re-read by the verifier: the spruce twigs come from the 7th whorl (p. 105), the spruce had
# reached 87 years in 1994 and the site lies 50 km WNW of Munich (p. 104).
SCHNEIDER_1996_CROWN_NITRATE_MM = (0.010, 0.025)
SCHNEIDER_1996_SOURCE = ("Schneider S., Gessler A., Weber P., von Sengbusch D., Hanemann U., Rennenberg H. 1996, New Phytol. "
                         "134(1):103-114, doi:10.1111/j.1469-8137.1996.tb01150.x, pp. 109 and 112 — nitrate in the twig "
                         "sap of beech (sun crown) and Norway spruce (7th whorl) together, Hoeglwald 1994, read from the "
                         "page images")
BROADLEAF_POINT_MM = {"malic": 0.92, "oxalic": 0.0, "kno3": 0.050, "cacl2": 0.67, "mgso4": 0.25}
BROADLEAF_PH = 5.95            # the median of the dated pH medians
# Each test in its own band. Temperatures on a 5 °C grid, pH on a 0.5 grid; every band end is a grid point.
# ⚠️ PRE-VERDICT, like RECIPE_RANGES_MM above: the pH bands below (and their `ph_home` strings) are the two canon
# bands as they stood BEFORE 2026-09-17. Canon no longer carries either — §2.1 is a set-point (5.75) plus a side
# series (4.5), so "the union of the two canon bands" names nothing that exists. Kept because Q1–Q5 price the
# ranges the ratified point replaced; the live point is RATIFIED_PH / RATIFIED_POINT_MM and Q7 above.
TESTS = {
    "coin": {"label": "Stage-2 Ti-coin electrochemistry",
             "ph": (4.5, 5.0, 5.5), "ph_home": "pre-verdict band (retired 2026-09-17); live pH → RATIFIED_PH, 01_02 §2.1",
             "t_c": (20.0, 25.0), "t_home": "01_03 §3.5 — 20–25 °C"},
    "accelerated": {"label": "12-week accelerated corrosion test",
                    "ph": (5.0, 5.5), "ph_home": "pre-verdict band (retired 2026-09-17); live pH → RATIFIED_PH, 01_02 §2.1",
                    "t_c": (20.0, 25.0, 30.0, 35.0, 40.0), "t_home": "01_02 §2.1 — 20–40 °C cycle (PRE-VERDICT: live = 40 °C isotherm, RATIFIED_T_C)"},
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

# Calcium and magnesium malate. Read here: Günzel's APPARENT dissociation constants in a Na+ medium, pHa 7.4, room
# temperature, each at the ionic strength beside it. Used only as READINGS — never by the hard bound, and so never by the
# window. ⊕ 2026-10-15: «NOT FOUND at I = 0» (this comment until then) was wrong for Ca — NIST SRD 46 critically selects
# CaL 2.72 ± 0.06 and CaHL 1.39 at I = 0, 25 °C (rows 154752 · 154756; Mg only at I = 0.1 and 1.0). Not added as a
# reading: it lies INSIDE the bracket the readings already span (no calcium malate ⊥ Günzel at I = 0, log K ≈ 2.90).
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
def _sig2(x: float) -> float:
    return float(f"{x:.2g}")


def point_2026_09_17() -> dict:
    """Q6 — the point canon specified from 2026-09-17 to 2026-10-18 (superseded): oxalate out, the other four at the
    geometric mid of their pre-verdict range. Kept as the price the revision is read against."""
    for key, (lo, hi) in RECIPE_RANGES_MM.items():
        if key != "oxalic":
            assert POINT_2026_09_17_MM[key] == _sig2(math.sqrt(lo * hi)), f"{key}: not the geometric mid"
    assert POINT_2026_09_17_MM["oxalic"] == 0.0, "the verdict removed oxalate"
    return price_point(POINT_2026_09_17_MM, "01_02 §2.1 (⚖️ founder 2026-09-17; SUPERSEDED 2026-10-18 — Q7)",
                       "oxalate removed; malic acid, KNO3, CaCl2 and MgSO4 at the geometric mid of their pre-verdict "
                       "range, two significant figures")


def revised_point() -> dict:
    """Q7 — the live recipe (⚖️ founder 2026-10-18). Asserts that RATIFIED_POINT_MM IS its derivation: each measured
    ion at the geometric mid of its trunk-base range (two significant figures) and the malic acid that, titrated to the
    set-point with KOH at POINT_SOLVE_T_C on the selected reading, gives the measured-mid potassium. CAN catch a typed
    point drifted from the measurements or from the solve; CANNOT make the measurements Scots pine — the source is
    Norway spruce — nor price dissolved CO2, which the recipe does not carry."""
    mids = {k: math.sqrt((v["mg_l"][0] / v["molar_g"]) * (v["mg_l"][1] / v["molar_g"]))
            for k, v in MEASURED_SAP_TRUNK_BASE.items()}
    for key in ("cacl2", "mgso4"):
        assert RATIFIED_POINT_MM[key] == _sig2(mids[key]), f"{key}: not the measured trunk-base mid"
    no3_mid = math.sqrt(MEASURED_NITRATE_MM[0] * MEASURED_NITRATE_MM[1])
    assert RATIFIED_POINT_MM["kno3"] == _sig2(no3_mid), "kno3: not the mid of the measured nitrate range"
    assert RATIFIED_POINT_MM["oxalic"] == 0.0, "no conifer oxalate measurement — oxalate stays out"
    ph = RATIFIED_PH["setpoint"][0]
    m = model_for(SC["selected"], POINT_SOLVE_T_C)

    def k_total(malic: float) -> float:
        p = {**RATIFIED_POINT_MM, "malic": malic}
        return speciate(m, totals_mm(p), ph).base_mol_l / MM + p["kno3"]
    malic_solved = brentq(lambda x: k_total(x) - mids["k_total"], 1e-4, 5.0, xtol=1e-9)
    assert RATIFIED_POINT_MM["malic"] == _sig2(malic_solved), (
        f"malic: the solve gives {malic_solved:.4f} mM, the point says {RATIFIED_POINT_MM['malic']}")
    out = price_point(RATIFIED_POINT_MM, "01_02 §2.1 (⚖️ founder 2026-10-18)",
                      "Ca, Mg and K at the geometric mid of measured Norway spruce sap at the bottom of the stem "
                      "(natural stands — the fertilized plot excluded); "
                      "nitrate at the mid of the Scots pine shoot-sap range; malic acid solved so that KOH to pH "
                      f"{ph} gives the measured-mid potassium; oxalate out; two significant figures")
    out["measured"] = {
        "trunk_base_mM": {k: [round(v["mg_l"][0] / v["molar_g"], 4), round(v["mg_l"][1] / v["molar_g"], 4)]
                          for k, v in MEASURED_SAP_TRUNK_BASE.items()},
        "trunk_base_mg_per_l": {k: list(v["mg_l"]) for k, v in MEASURED_SAP_TRUNK_BASE.items()},
        "rows_mg_per_l": MEASURED_SAP_ROWS_MG_L, "rows_excluded": MEASURED_SAP_EXCLUDED,
        "geometric_mid_mM": {k: round(v, 4) for k, v in mids.items()},
        "nitrate_mM": list(MEASURED_NITRATE_MM), "nitrate_mid_mM": round(no3_mid, 5),
        "sources": {"ca_mg_k": MEASURED_SAP_SOURCE, "nitrate": MEASURED_NITRATE_SOURCE},
        "malic_solved_mM": round(malic_solved, 4),
        "potassium_total_at_point_mM": round(k_total(RATIFIED_POINT_MM["malic"]), 4),
        "solve": {"ph": ph, "t_c": POINT_SOLVE_T_C, "reading": SC["selected"].key}}
    old = point_2026_09_17()["conditions"]["setpoint"]
    new = out["conditions"]["setpoint"]
    out["against_point_2026_09_17_setpoint"] = {
        "ionic_strength_ratio": round(new["ionic_strength_mol_l"][1] / old["ionic_strength_mol_l"][1], 3),
        "buffer_capacity_ratio": round(new["buffer_capacity_mM_per_pH_25c"] / old["buffer_capacity_mM_per_pH_25c"], 3),
        "potassium_total_ratio": round(new["potassium_total_mM"][1] / old["potassium_total_mM"][1], 3)}
    return out


def beech_nitrate_mm(reading: int | None = None) -> dict:
    """Dated beech nitrate (mM): total N × its NO3-N share / M_N per date — reading R1 (0) or R2 (1), or by default the
    transcription, the mean of the two readings of each median."""
    def pick(a: float, b: float) -> float:
        return (a + b) / 2 if reading is None else (a, b)[reading]
    return {d: pick(n1, n2) * pick(s1, s2) / 100.0 / MOLAR_G_N
            for d, (n1, n2, s1, s2) in BEECH_TRUNK_BASE_NITRATE.items()}


def broadleaf_k_total(malic: float, kno3: float, cacl2: float | None = None, ph: float | None = None) -> float:
    """Potassium total (mM) of the Q8 point at a malic acid and a KNO3: the KOH to BROADLEAF_PH (selected reading,
    POINT_SOLVE_T_C) plus the KNO3 — the nitrate on potassium, as in revised_point(). 85's flip control can also set
    the CaCl2 and the pH (default: the point's)."""
    p = {**BROADLEAF_POINT_MM, "malic": malic, "kno3": kno3} | ({} if cacl2 is None else {"cacl2": cacl2})
    ph = BROADLEAF_PH if ph is None else ph
    return speciate(model_for(SC["selected"], POINT_SOLVE_T_C), totals_mm(p), ph).base_mol_l / MM + kno3


def broadleaf_malic_solved(k_range_mg_l: tuple[float, float] | None = None, kno3: float | None = None,
                           cacl2: float | None = None, ph: float | None = None) -> float:
    """The Q8 malic solve (mM): the malic acid whose KOH to BROADLEAF_PH, with the KNO3, gives the geometric mid of the
    dated beech potassium medians. By default the point's own solve; 85's flip control passes the potassium range's
    ends (mg/L) after it has moved a dated median, and can set the KNO3, the CaCl2 and the pH."""
    k = [r[2] for r in BEECH_TRUNK_BASE_MEDIANS.values()]
    lo, hi = (min(k), max(k)) if k_range_mg_l is None else k_range_mg_l
    k_mid = math.sqrt(lo * hi) / MOLAR_G["K"]
    kno3 = BROADLEAF_POINT_MM["kno3"] if kno3 is None else kno3
    return brentq(lambda x: broadleaf_k_total(x, kno3, cacl2, ph) - k_mid, 0.01, 5.0, xtol=1e-9)   # no acid: pH 5.95 would need a negative base


def broadleaf_rederived(shift: dict | None = None, kno3: float | None = None, rounded: bool = True) -> tuple[dict, float]:
    """Q8's point (mM) and pH re-derived by broadleaf_point()'s rule after moving dated medians — 85's flip control.
    `shift` maps (date, column) — "Ca_mg_l", "K_mg_l" or "pH" — to what is added to that date's median; the ranges'
    ends and the pH median are then taken afresh over every date, so a moved end stops being the end once it passes
    the next value. `kno3` replaces the point's nitrate. `rounded` keeps the rule's roundings (two significant figures
    for the CaCl2 mid and the malate, the pH median on the transcription's 0.01 grid); False leaves them continuous.
    MgSO4 stays the point's."""
    col = {"Ca_mg_l": 0, "K_mg_l": 2, "pH": 3}
    rows = {d: list(r) for d, r in BEECH_TRUNK_BASE_MEDIANS.items()}
    for (date, c), v in (shift or {}).items():
        rows[date][col[c]] += v
    ca, k = [r[0] for r in rows.values()], [r[2] for r in rows.values()]
    ph = float(np.median([r[3] for r in rows.values() if r[3] is not None]))
    sig = _sig2 if rounded else float
    ph = round(ph, 2) if rounded else ph
    cacl2 = sig(math.sqrt(min(ca) * max(ca)) / MOLAR_G["Ca"])
    kno3 = BROADLEAF_POINT_MM["kno3"] if kno3 is None else kno3
    malic = sig(broadleaf_malic_solved((min(k), max(k)), kno3, cacl2, ph))
    return {**BROADLEAF_POINT_MM, "malic": malic, "kno3": kno3, "cacl2": cacl2}, ph


def beech_range_readings() -> list[dict]:
    """Every reading of the dated beech range behind Q8 within its read-off error (BEECH_READ_OFF_ERROR): the END of
    each ion's range — its lowest and its highest dated median — moved by −e, 0 or +e, independently over the three
    ions, 3⁶ readings of {ion: (lo, hi)} in mM. The END moves, not the one date that carries it: with every dated
    median read within ±e, the true extreme lies within ±e of the read one, so this envelope also holds 85's flip
    control, which moves one median at a time and re-takes the extremes (one move there can stop at the next date)."""
    per_ion = {}
    for i, ion in enumerate(("Ca", "Mg", "K")):
        vals = [r[i] for r in BEECH_TRUNK_BASE_MEDIANS.values()]
        e = BEECH_READ_OFF_ERROR[f"{ion}_mg_l"]
        per_ion[ion] = [((min(vals) + a) / MOLAR_G[ion], (max(vals) + b) / MOLAR_G[ion])
                        for a, b in itertools.product((-e, 0.0, e), repeat=2)]
    return [dict(zip(per_ion, combo, strict=True)) for combo in itertools.product(*per_ion.values())]


def _soper_tally(beech: dict) -> dict:
    """Soper's cells against ONE reading of the dated beech range ({ion: (lo, hi)} in mM): per species, the (ion, month)
    cells whose mean lies inside the range, and those whose mean ± 1 SD covers the range's geometric mid (Q8's rule)."""
    out = {}
    for sp, ions in SOPER_2018_CROWN_SAP_UG_ML.items():
        inside, within = set(), set()
        for ion, means in ions.items():
            lo, hi = beech[ion]
            mid = math.sqrt(lo * hi)
            for m, v, s in zip(SOPER_2018_MONTHS, means, SOPER_2018_CROWN_SAP_SD_UG_ML[sp][ion], strict=True):
                if lo <= v / MOLAR_G[ion] <= hi:
                    inside.add((ion, m))
                if s is not None and (v - s) / MOLAR_G[ion] <= mid <= (v + s) / MOLAR_G[ion]:
                    within.add((ion, m))
        out[sp] = (inside, within)
    return out


def crown_twig_readings() -> dict:
    """Soper 2018 and Schneider 1996 — two crown-twig readings BESIDE Q8 (00_07 HW.3 (А)), set against the dated
    trunk-base range behind the point, nominally AND under its read-off error (beech_range_readings()): per Soper
    species and ion, each monthly mean in mM, the Q8 rule's geometric mid of the extreme months against Q8's own mid
    and its LEAVE-ONE-MONTH-OUT bracket (min–max over the four exclusions: the rule on four months answers to each of
    them, and the authors report no significant change with time, so no month is singled out — an exclusion of only
    the lowest month would lift the mid one-sidedly), each with its side of the point under every reading; which
    months fall outside the range of the dated beech medians, and whether the month's ± 1 SD covers Q8's mid; for
    Schneider, where its nitrate range lies against the dated beech nitrate and its mid. Built in main(), never inside
    broadleaf_point(), so none of its asserts sits on 85's path. CAN catch a re-transcribed mean that crosses the beech
    range or the point's mid, an SD labelled «upper arm only» on a bar that does not reach the axis (or a bar that does,
    left unlabelled), and a count or a side that holds only on the nominal medians; CANNOT make crown twigs the trunk
    base, one season's monthly MEANS a series of dated medians, or the beech-and-spruce nitrate a beech number. The
    ± 1 SD count is no test of agreement: the SD is the spread between trees, so the band covers a new typical tree in
    P(|t₇| ≤ 1/√(1 + 1/8)) of cells when the eight trees are normal (sample mean ± sample SD), erf(1/√2) for the
    population band — both printed beside the count — and more when the spread is skewed, which three cells whose SD
    reaches the mean show it to be; the four months are the same eight trees and the three ions of a month the same sap
    samples, so the cells are not independent."""
    rows = list(BEECH_TRUNK_BASE_MEDIANS.values())
    beech = {ion: (min(r[i] for r in rows) / MOLAR_G[ion], max(r[i] for r in rows) / MOLAR_G[ion])
             for i, ion in enumerate(("Ca", "Mg", "K"))}
    q8_mid = {ion: math.sqrt(lo * hi) for ion, (lo, hi) in beech.items()}
    assert set(SOPER_2018_CROWN_SAP_UG_ML) == set(SOPER_2018_CROWN_SAP_SD_UG_ML), "Soper: means and SDs name different species"
    reaches_axis = {(sp, ion, m) for sp, ions in SOPER_2018_CROWN_SAP_UG_ML.items() for ion, means in ions.items()
                    for m, v, s in zip(SOPER_2018_MONTHS, means, SOPER_2018_CROWN_SAP_SD_UG_ML[sp][ion], strict=True)
                    if s is not None and s >= v}
    assert reaches_axis == set(SOPER_2018_SD_UPPER_ARM_ONLY), (
        f"Soper: the upper-arm-only cells must be exactly those whose SD reaches the mean — {sorted(reaches_axis)}")
    readings = beech_range_readings()
    i_nominal = readings.index(beech)   # the zero shift on every end — raises if the envelope lost the nominal reading
    tallies = [_soper_tally(r) for r in readings]
    nominal = tallies[i_nominal]
    coverage = math.erf(1.0 / math.sqrt(2.0))   # ± 1 SD of a normal population
    n_trees = SOPER_2018_TREES_PER_SPECIES      # a new tree inside the SAMPLE mean ± SD: |t| of n − 1 dof ≤ 1/√(1 + 1/n)
    coverage_t = 2.0 * student_t.cdf(1.0 / math.sqrt(1.0 + 1.0 / n_trees), n_trees - 1) - 1.0

    def side(lo_ratio: float, hi_ratio: float) -> str:
        return "above" if lo_ratio > 1.0 else "below" if hi_ratio < 1.0 else "straddles"
    species, tally, shares = {}, {}, []
    for sp, ions in SOPER_2018_CROWN_SAP_UG_ML.items():
        per = {}
        for ion, means in ions.items():
            mm = [v / MOLAR_G[ion] for v in means]   # µg/mL = mg/L, so mg/L ÷ g/mol = mM
            sds = SOPER_2018_CROWN_SAP_SD_UG_ML[sp][ion]
            sd_share = [None if s is None else s / v for s, v in zip(sds, means, strict=True)]
            shares += [x for x in sd_share if x is not None]
            mid = math.sqrt(min(mm) * max(mm))
            loo = {}
            for out_m in SOPER_2018_MONTHS:
                rest = [x for m, x in zip(SOPER_2018_MONTHS, mm, strict=True) if m != out_m]
                loo[out_m] = math.sqrt(min(rest) * max(rest))
            q8_mids = [math.sqrt(r[ion][0] * r[ion][1]) for r in readings]
            r_mid = (mid / max(q8_mids), mid / min(q8_mids))
            r_loo = (min(loo.values()) / max(q8_mids), max(loo.values()) / min(q8_mids))
            per[ion] = {"monthly_mM": dict(zip(SOPER_2018_MONTHS, (round(x, 4) for x in mm), strict=True)),
                        "q8_rule_mid_mM": round(mid, 4), "over_q8_mid": round(mid / q8_mid[ion], 3),
                        "over_q8_mid_under_read_off": [round(r_mid[0], 3), round(r_mid[1], 3)],
                        "side_under_read_off": side(*r_mid),
                        # five decimals: a doc quoting three must not be judged against a four-decimal round of a value
                        # that sits on the half (prinus Mg without July is 0.146492)
                        "q8_rule_mid_leave_one_month_out_mM": {m: round(v, 5) for m, v in loo.items()},
                        "leave_one_month_out_mM": [round(min(loo.values()), 5), round(max(loo.values()), 5)],
                        "over_q8_mid_leave_one_month_out_under_read_off": [round(r_loo[0], 3), round(r_loo[1], 3)],
                        "leave_one_month_out_side_under_read_off": side(*r_loo),
                        "months_outside_dated_beech_range": [m for m in SOPER_2018_MONTHS if (ion, m) not in nominal[sp][0]],
                        "sd_over_mean": dict(zip(SOPER_2018_MONTHS, (None if x is None else round(x, 3) for x in sd_share), strict=True)),
                        "q8_mid_within_one_sd": {m: None if s is None else (ion, m) in nominal[sp][1]
                                                 for m, s in zip(SOPER_2018_MONTHS, sds, strict=True)}}
        species[sp] = per
        n_sd = sum(s is not None for ion_sds in SOPER_2018_CROWN_SAP_SD_UG_ML[sp].values() for s in ion_sds)
        inside_n, within_n = [len(t[sp][0]) for t in tallies], [len(t[sp][1]) for t in tallies]
        tally[sp] = {
            "cells_inside_dated_beech_range": [len(nominal[sp][0]), len(ions) * len(SOPER_2018_MONTHS)],
            "cells_inside_under_read_off": [min(inside_n), max(inside_n)],
            "cells_q8_mid_within_one_sd": [len(nominal[sp][1]), n_sd],
            "cells_q8_mid_within_one_sd_under_read_off": [min(within_n), max(within_n)],
            "expected_within_new_tree_t": round(coverage_t * n_sd, 1),
            "expected_within_if_normal_population": round(coverage * n_sd, 1),
            "cells_that_flip_under_read_off": {
                "inside": sorted({f"{ion} {m}" for t in tallies for ion, m in t[sp][0] ^ nominal[sp][0]}),
                "within_one_sd": sorted({f"{ion} {m}" for t in tallies for ion, m in t[sp][1] ^ nominal[sp][1]})}}
    oaks = [sp for sp in species if sp.startswith("Quercus")]
    oak_inside = [sum(len(t[sp][0]) for sp in oaks) for t in tallies]
    oak_within = [sum(len(t[sp][1]) for sp in oaks) for t in tallies]
    oak_n_sd = sum(tally[sp]["cells_q8_mid_within_one_sd"][1] for sp in oaks)
    outside = {f"{sp} {ion}": p["months_outside_dated_beech_range"] for sp, per in species.items()
               for ion, p in per.items() if p["months_outside_dated_beech_range"]}
    no3 = beech_nitrate_mm()
    no3_lo, no3_hi = min(no3.values()), max(no3.values())
    no3_mid = math.sqrt(no3_lo * no3_hi)
    s_lo, s_hi = SCHNEIDER_1996_CROWN_NITRATE_MM
    s_inside, s_below = no3_lo <= s_lo and s_hi <= no3_hi, s_hi < no3_mid
    s_where = (("inside the dated trunk-base range the point is taken from" if s_inside else
                "OUTSIDE the dated trunk-base range the point is taken from")
               + (", below its mid" if s_below else ", not below its mid")
               + (", so it is no evidence against the point" if s_inside else ""))
    return {
        "soper_2018": {
            "source": SOPER_2018_SOURCE, "months": list(SOPER_2018_MONTHS), "means_ug_ml": SOPER_2018_CROWN_SAP_UG_ML,
            "sd_ug_ml": SOPER_2018_CROWN_SAP_SD_UG_ML, "sd_upper_arm_only": [list(c) for c in SOPER_2018_SD_UPPER_ARM_ONLY],
            "sd_upper_arm_only_provenance": "first extraction only — the independent extraction left these bars "
                                            "unattributed and checked them only as a share of the mean",
            "by_species": species, "tally_by_species": tally,
            "q8_mid_mM": {ion: round(v, 4) for ion, v in q8_mid.items()},
            "dated_beech_range_mM": {ion: [round(lo, 4), round(hi, 4)] for ion, (lo, hi) in beech.items()},
            "read_off_error_mg_l": {k: v for k, v in BEECH_READ_OFF_ERROR.items() if k != "pH"},
            "read_off_readings": len(readings),
            "oak_cells_inside_dated_beech_range": [oak_inside[i_nominal], sum(tally[sp]["cells_inside_dated_beech_range"][1] for sp in oaks)],
            "oak_cells_inside_under_read_off": [min(oak_inside), max(oak_inside)],
            "cells_outside_dated_beech_range": outside,
            "sd_over_mean_range": [round(min(shares), 3), round(max(shares), 3)],
            "oak_cells_q8_mid_within_one_sd": [oak_within[i_nominal], oak_n_sd],
            "oak_cells_q8_mid_within_one_sd_under_read_off": [min(oak_within), max(oak_within)],
            "trees_per_species": n_trees,
            "one_sd_coverage_new_tree_t": round(coverage_t, 3),
            "one_sd_coverage_if_normal": round(coverage, 3),
            "oak_expected_within_new_tree_t": round(coverage_t * oak_n_sd, 1),
            "oak_expected_within_if_normal": round(coverage * oak_n_sd, 1),
            "cells_with_sd_at_or_above_mean": len(reaches_axis),
            "cells_with_sd": [len(shares), len(species) * 3 * len(SOPER_2018_MONTHS)],
            "not_measured": "nitrate, pH, organic acids",
            "why_a_reading_not_a_point": "sap of crown branches up to 1 cm, not the trunk base; one season's monthly "
                                         "MEANS of eight trees, not dated medians, and the authors find no significant "
                                         "change of these ions with time; no organic acid, so no malate to solve and no "
                                         "buffer"},
        "schneider_1996": {
            "source": SCHNEIDER_1996_SOURCE, "nitrate_mM": list(SCHNEIDER_1996_CROWN_NITRATE_MM),
            "species": "beech (sun crown) and Norway spruce (7th whorl) together — no beech-only number printed",
            "dated_beech_nitrate_range_mM": [round(no3_lo, 4), round(no3_hi, 4)], "dated_beech_nitrate_mid_mM": round(no3_mid, 4),
            "inside_dated_beech_range": s_inside, "below_point_mid": s_below,
            "why_a_reading_not_a_point": "twigs of a site under high N deposition, two species pooled, one year; the "
                                         f"range lies {s_where}"},
    }


def broadleaf_point() -> dict:
    """Q8 — the broadleaf point (⚖️ founder 2026-10-18), 85's input for the broadleaf and oak anchor parts. Asserts that
    BROADLEAF_POINT_MM and BROADLEAF_PH ARE their derivation from the beech medians: Ca and Mg at the geometric mid of
    the dated medians' range (two significant figures), pH at the median of the dated pH medians, nitrate at the
    geometric mid of the dated nitrate of the 1993 figures (two significant figures; balanced by K, as pine's), and the
    malic acid that, titrated to that pH with KOH at POINT_SOLVE_T_C on the selected reading, gives the mid potassium
    with the KNO3; oxalate out (not measured). Also returns the paper's low-pH dates with their nitrate, which the
    point's single pH hides. CAN catch a typed point drifted from the transcription or the solve, and acid dates that
    stop being the three highest nitrates; CANNOT make the beech oak, read a figure better than by eye, prove the 1993
    stand and dates are the 1990 ones, or say how much of the potassium malate really balances — the solve credits it
    all but the nitrate (a ceiling on that side, while the buffers the recipe lacks push the other way, so the
    total's direction is not established)."""
    rows = list(BEECH_TRUNK_BASE_MEDIANS.values())
    rng = {ion: (min(r[i] for r in rows), max(r[i] for r in rows)) for i, ion in enumerate(("Ca", "Mg", "K"))}
    mids = {ion: math.sqrt(lo * hi) / MOLAR_G[ion] for ion, (lo, hi) in rng.items()}
    assert BROADLEAF_POINT_MM["cacl2"] == _sig2(mids["Ca"]), "cacl2: not the beech trunk-base mid"
    assert BROADLEAF_POINT_MM["mgso4"] == _sig2(mids["Mg"]), "mgso4: not the beech trunk-base mid"
    assert list(BEECH_TRUNK_BASE_NITRATE) == list(BEECH_TRUNK_BASE_MEDIANS), "nitrate dates are not the Q8 dates"
    no3 = beech_nitrate_mm()
    no3_lo, no3_hi = min(no3, key=no3.get), max(no3, key=no3.get)
    no3_mid = math.sqrt(no3[no3_lo] * no3[no3_hi])
    assert BROADLEAF_POINT_MM["kno3"] == _sig2(no3_mid), "kno3: not the geometric mid of the dated beech nitrate"
    by_reading = {name: beech_nitrate_mm(i) for i, name in enumerate(("R1", "R2"))}
    reading_mid = {name: math.sqrt(min(v.values()) * max(v.values())) for name, v in by_reading.items()}
    assert BROADLEAF_POINT_MM["oxalic"] == 0.0, "oxalate: not measured"
    phs = sorted(r[3] for r in rows if r[3] is not None)
    assert round(float(np.median(phs)), 2) == BROADLEAF_PH, "pH: not the median of the dated medians"
    malic_solved = broadleaf_malic_solved()
    assert BROADLEAF_POINT_MM["malic"] == _sig2(malic_solved), (
        f"malic: the solve gives {malic_solved:.4f} mM, the point says {BROADLEAF_POINT_MM['malic']}")
    out = price_point(BROADLEAF_POINT_MM, "85 broadleaf and oak anchor parts (⚖️ founder 2026-10-18) — not a wet-test recipe",
                      "Ca and Mg at the geometric mid of the beech trunk-base medians (Glavac 1990; no fertilization or liming named), "
                      "pH at the median of the dated medians, nitrate at the geometric mid of the dated beech nitrate "
                      "(Glavac & Jochheim 1993 — the product of the medians of total N and its NO3-N share) as KNO3, "
                      "malic acid solved so that KOH to that pH, with the KNO3, gives the mid potassium; oxalate not "
                      "measured — out; two significant figures",
                      conditions={"setpoint": (BROADLEAF_PH, ["anchor model (85)"], [20.0, 25.0])})
    acid = {d: BEECH_TRUNK_BASE_MEDIANS[d] for d in BEECH_ACID_DATES}
    assert sorted(phs)[:len(acid)] == sorted(r[3] for r in acid.values()), "the named low-pH dates are not the lowest"
    assert set(sorted(no3, key=no3.get)[-len(acid):]) == set(acid), "the low-pH dates are not the three highest nitrates"
    out["measured"] = {
        "medians_by_date": {d: dict(zip(("Ca_mg_l", "Mg_mg_l", "K_mg_l", "pH"), r, strict=True))
                            for d, r in BEECH_TRUNK_BASE_MEDIANS.items()},
        "range_of_medians_mg_l": {ion: list(v) for ion, v in rng.items()},
        "range_of_medians_mM": {ion: [round(lo / MOLAR_G[ion], 4), round(hi / MOLAR_G[ion], 4)] for ion, (lo, hi) in rng.items()},
        "geometric_mid_mM": {ion: round(v, 4) for ion, v in mids.items()},
        "ph_medians_range": [phs[0], phs[-1]], "ph_dates_with_value": len(phs),
        "nitrate": {
            "source": BEECH_NITRATE_SOURCE,
            "medians_by_date": {d: {"total_N_mg_l": list(r[:2]), "no3_n_share_pct": list(r[2:])}
                                for d, r in BEECH_TRUNK_BASE_NITRATE.items()},
            "readings": ["R1", "R2"],
            "by_date_mM": {d: round(v, 4) for d, v in no3.items()},
            "range_mM": [round(no3[no3_lo], 4), round(no3[no3_hi], 4)], "range_dates": [no3_lo, no3_hi],
            "geometric_mid_mM": round(no3_mid, 4),
            "geometric_mid_by_reading_mM": {k: round(v, 4) for k, v in reading_mid.items()},
            "point_by_reading_mM": {k: _sig2(v) for k, v in reading_mid.items()},
            "arithmetic": "per date, the product of the medians of total N and of its NO3-N share (the mean of the two "
                          "readings), not a median of per-tree products — the figures give only the medians",
            "charge": "balanced by K, as in the pine point: the malate is solved from the potassium less this nitrate"},
        "source": BEECH_SOURCE, "malic_solved_mM": round(malic_solved, 4),
        "potassium_total_at_point_mM": round(broadleaf_k_total(BROADLEAF_POINT_MM["malic"], BROADLEAF_POINT_MM["kno3"]), 4),
        "solve": {"ph": BROADLEAF_PH, "t_c": POINT_SOLVE_T_C, "reading": SC["selected"].key}}
    out["summer_acid_dates"] = {
        "dates": list(BEECH_ACID_DATES), "ph_medians": [r[3] for r in acid.values()],
        "nitrate_mM": [round(no3[d], 2) for d in BEECH_ACID_DATES],
        "lowest_tree_ph": BEECH_LOWEST_TREE_PH,
        "why": "the paper: they «coincided with the highest nitrate xylem sap concentration» (unpublished data then); "
               f"printed in 1993, the nitrate on these dates is {' · '.join(f'{no3[d]:.2f}' for d in BEECH_ACID_DATES)} "
               f"mM, the {len(acid)} highest of the {len(no3)} dates against the point's {BROADLEAF_POINT_MM['kno3']:.3f} — "
               "carried beside the point as a reading, as the pH is; the 1990 paper does not report what acidifies "
               "the sap there, and the point's malate solve does not describe these dates"}
    oak = OAK_RUBRA_VESSEL_SAP.values()
    out["oak_own_sap_reading"] = {
        "source": OAK_RUBRA_SOURCE,
        "ph_range": [min(r["pH"][0] for r in oak), max(r["pH"][1] for r in oak)],
        "trees_mM": {ion: [round(min(r[f"{ion}_mg_ml"] for r in oak) * 1e3 / MOLAR_G[ion], 3),
                           round(max(r[f"{ion}_mg_ml"] for r in oak) * 1e3 / MOLAR_G[ion], 3)] for ion in ("K", "Ca", "Mg")},
        "conductivity_uS_cm": [min(r["conductivity"] for r in oak), max(r["conductivity"] for r in oak)],
        "beech_same_season_ph": sorted(r[3] for d, r in BEECH_TRUNK_BASE_MEDIANS.items()   # September–October with a pH
                                       if d[5:7] in ("09", "10") and r[3] is not None),
        "why_a_reading_not_a_point": "one autumn date and two trees of red oak; no organic acid measured, so no buffer to "
                                     "solve — it says where the bulk pH stands, not what a current does to it"}
    pine = revised_point()["conditions"]["setpoint"]
    new = out["conditions"]["setpoint"]
    out["against_pine_point"] = {
        "ca_ratio": round(BROADLEAF_POINT_MM["cacl2"] / RATIFIED_POINT_MM["cacl2"], 2),
        "mg_ratio": round(BROADLEAF_POINT_MM["mgso4"] / RATIFIED_POINT_MM["mgso4"], 2),
        "potassium_total_ratio": round(new["potassium_total_mM"][1] / pine["potassium_total_mM"][1], 2),
        "buffer_capacity_ratio": round(new["buffer_capacity_mM_per_pH_25c"] / pine["buffer_capacity_mM_per_pH_25c"], 2),
        "ionic_strength_ratio": round(new["ionic_strength_mol_l"][1] / pine["ionic_strength_mol_l"][1], 2)}
    return out


def price_point(point: dict, home: str, derivation: str, conditions: dict | None = None) -> dict:
    """What a recipe point takes to prepare: the base to reach each pH condition, and how weakly it buffers there.
    Every documented reading at every temperature of the tests the condition belongs to — the hard bound is an SI
    construct, not a reading, so it prices nothing here. `conditions` ({name: (pH, uses, temperatures)}) prices a
    point outside the ratified tests; by default the ratified pH conditions at their tests' temperatures."""
    tot = totals_mm(point)
    readings = [sc for sc in SCENARIOS if sc.key != "hard_bound"]
    conds = conditions or {name: (ph, tests, sorted({t for test in tests for t in RATIFIED_T_C[test]}))
                           for name, (ph, tests) in RATIFIED_PH.items()}
    conditions_out = {}
    for name, (ph, tests, temps) in conds.items():
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
        kno3 = point["kno3"]
        conditions_out[name] = {
            "ph": ph, "tests": list(tests), "t_c": temps,
            "base_koh_mM": [round(min(base), 3), round(max(base), 3)],
            "potassium_total_mM": [round(min(base) + kno3, 3), round(max(base) + kno3, 3)],
            "ionic_strength_mol_l": [round(min(ionic), 5), round(max(ionic), 5)],
            "si_gypsum_max": round(max(si_gypsum), 3),
            "buffer_capacity_mM_per_pH_25c": round(buffer_capacity_mm_per_ph(tot, ph), 4),
            "strong_acid_mM_lowering_pH_by_0p1_25c": round(acid_tenth, 4)}
    return {"recipe_mM": point, "home": home, "derivation": derivation,
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

    q6, q7 = point_2026_09_17(), revised_point()
    for title, q in (("Q6 — the point of 2026-09-17 (superseded 2026-10-18): base, buffer capacity", q6),
                     ("Q7 — the revised point (⚖️ 2026-10-18, live): base, buffer capacity", q7)):
        banner(title)
        print(f"  recipe {q['recipe_mM']}")
        for name, c in q["conditions"].items():
            print(f"  {name} pH {c['ph']}: KOH {c['base_koh_mM'][0]:.3f}–{c['base_koh_mM'][1]:.3f} mM, K+ total "
                  f"{c['potassium_total_mM'][0]:.3f}–{c['potassium_total_mM'][1]:.3f} mM; I {c['ionic_strength_mol_l'][1] * 1e3:.2f} mM; "
                  f"β(25 °C) {c['buffer_capacity_mM_per_pH_25c']:.3f} mM/pH, strong acid for −0.1 pH "
                  f"{c['strong_acid_mM_lowering_pH_by_0p1_25c']:.4f} mM; SI(gypsum) ≤ {c['si_gypsum_max']:+.2f}")
    print(f"  Q7 against Q6 at the set-point: ionic strength ×{q7['against_point_2026_09_17_setpoint']['ionic_strength_ratio']}, "
          f"buffer capacity ×{q7['against_point_2026_09_17_setpoint']['buffer_capacity_ratio']}, "
          f"K+ ×{q7['against_point_2026_09_17_setpoint']['potassium_total_ratio']}; malic solved "
          f"{q7['measured']['malic_solved_mM']} mM")
    q8 = broadleaf_point()
    q8["crown_twig_readings"] = crown_twig_readings()   # built here, off 85's path through broadleaf_point()
    banner("Q8 — the broadleaf point (⚖️ 2026-10-18; beech trunk base — 85's broadleaf and oak parts, no wet test)")
    c8 = q8["conditions"]["setpoint"]
    print(f"  recipe {q8['recipe_mM']} at pH {c8['ph']}: KOH {c8['base_koh_mM'][0]:.3f}–{c8['base_koh_mM'][1]:.3f} mM; "
          f"I {c8['ionic_strength_mol_l'][1] * 1e3:.2f} mM; β(25 °C) {c8['buffer_capacity_mM_per_pH_25c']:.3f} mM/pH")
    print(f"  against the pine point: Ca ×{q8['against_pine_point']['ca_ratio']}, Mg ×{q8['against_pine_point']['mg_ratio']}, "
          f"K+ ×{q8['against_pine_point']['potassium_total_ratio']}, β ×{q8['against_pine_point']['buffer_capacity_ratio']}")
    print(f"  summer acid dates {q8['summer_acid_dates']['dates']}: pH medians {q8['summer_acid_dates']['ph_medians']}, "
          f"lowest tree {q8['summer_acid_dates']['lowest_tree_ph']} — beside the point, outside its malate solve")
    n8 = q8["measured"]["nitrate"]
    print(f"  nitrate (Glavac & Jochheim 1993, product of medians): {n8['range_mM'][0]}–{n8['range_mM'][1]} mM "
          f"({n8['range_dates'][0]} … {n8['range_dates'][1]}), geometric mid {n8['geometric_mid_mM']} → point "
          f"{q8['recipe_mM']['kno3']} on K (readings {n8['point_by_reading_mM']['R1']}/{n8['point_by_reading_mM']['R2']}); "
          f"on the acid dates {q8['summer_acid_dates']['nitrate_mM']} mM — beside the point")
    cr = q8["crown_twig_readings"]
    for sp, per in cr["soper_2018"]["by_species"].items():
        print(f"  Soper 2018 crown twigs, {sp}, Q8 rule: " + " · ".join(
            f"{ion} {p['q8_rule_mid_mM']:.3g} mM (×{p['over_q8_mid']:.2f} of Q8's)" for ion, p in per.items()))
    so = cr["soper_2018"]
    oak_in, oak_in_r = so["oak_cells_inside_dated_beech_range"], so["oak_cells_inside_under_read_off"]
    oak_sd, oak_sd_r = so["oak_cells_q8_mid_within_one_sd"], so["oak_cells_q8_mid_within_one_sd_under_read_off"]
    print(f"  oak cells inside the dated beech range {oak_in[0]}/{oak_in[1]} ({oak_in_r[0]}–{oak_in_r[1]} under the "
          f"read-off error, {so['read_off_readings']} readings); outside: {so['cells_outside_dated_beech_range'] or 'none'}; "
          f"SD/mean {so['sd_over_mean_range'][0]:.0%}–{so['sd_over_mean_range'][1]:.0%}; Q8's mid inside the month's "
          f"±1 SD in {oak_sd[0]} ({oak_sd_r[0]}–{oak_sd_r[1]}) of the {oak_sd[1]} oak cells with an SD — a new typical "
          f"tree would be in ≈ {so['oak_expected_within_new_tree_t']} ({so['one_sd_coverage_new_tree_t']:.0%}, t of "
          f"{so['trees_per_species'] - 1} dof) or ≈ {so['oak_expected_within_if_normal']} ({so['one_sd_coverage_if_normal']:.0%}, "
          f"population band); {so['cells_with_sd_at_or_above_mean']} cells with SD ≥ mean")
    for sp, t in so["tally_by_species"].items():
        print(f"    {sp}: inside {t['cells_inside_dated_beech_range']} ({t['cells_inside_under_read_off']}), within ±1 SD "
              f"{t['cells_q8_mid_within_one_sd']} ({t['cells_q8_mid_within_one_sd_under_read_off']}); flips "
              f"{t['cells_that_flip_under_read_off']}; leave-one-month-out: " + " · ".join(
                  f"{ion} {p['leave_one_month_out_mM'][0]:.3g}–{p['leave_one_month_out_mM'][1]:.3g} {p['leave_one_month_out_side_under_read_off']}"
                  for ion, p in so["by_species"][sp].items()))
    sch = cr["schneider_1996"]
    print(f"  Schneider 1996 crown-twig nitrate {sch['nitrate_mM'][0]}–{sch['nitrate_mM'][1]} mM (beech + spruce): "
          f"inside the dated beech range {sch['dated_beech_nitrate_range_mM']} {sch['inside_dated_beech_range']}, "
          f"below its mid {sch['dated_beech_nitrate_mid_mM']} {sch['below_point_mid']}")

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
         "revised 2026-10-18 — q6_point_2026_09_17_superseded, q7_revised_point) is supersaturated to whewellite in both "
         "tests, under every constant reading evaluated. "
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
        "q6_point_2026_09_17_superseded": q6,
        "q7_revised_point": q7,
        "q8_broadleaf_point": q8,
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
