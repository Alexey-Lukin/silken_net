#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""106 — the share t_L of the wood's in-plane strain that the bonded gyroid takes, by an orthotropic Eshelby solution
on the full elastic constants of Scots pine sapwood (00_07 HW.23, closing the leg «частка деформації деревини, яку бере
зчеплений гіроїд, — ортотропний Ешелбі в площині L–T»; closed forms, no FE).

WHY. `105` prices the gyroid's ligaments with an energy LOWER bound at t_L = 1 — the bonded gyroid assumed to follow the
wood's longitudinal strain exactly — and says the share is «not established in either direction». Its bound reads
σ_RMS ≥ √(E_s·E_z*/φ)·t_L·ε, so every binding claim of `105`, and through it the S-N plan's ⚖️ «buy the lattice level»
(docs/protocols/anchor/sn_fatigue_test_plan.md §8), stands on t_L and on the lattice's in-plane modulus E_z* together.

CHAIN (in-silico §Critical Rules #15; joints from canon). The stem's bending strain ε_L in the xylem → the callus ring
in the 2 mm radial gap between the Ø11 gyroid and the Ø15 narrow step → the gyroid, bonded, with tissue in its pores.
01_04 §2: in Phase 2 callus fills the space around Zone 1 and enters its macropores; in Phase 3 the callus INSIDE Zone 1
becomes functional xylem and phloem — of the ring around it the phases say nothing, so reading the ring as the host's
xylem is OURS. The anchor's axis is the stem's radius R, so the gyroid's section lies in the L–T plane. Three joints,
three unknowns: the ring's stiffness, the stiffness of the tissue in the pores, and the lattice's own constants beyond
what the voxel FE measures.

MODEL. The gyroid as an infinite circular cylinder along R, perfectly bonded in an infinite homogeneous orthotropic
matrix (L, T, R), under the remote uniaxial stress σ_L of stem bending (ε^∞ = C_m⁻¹:σ_L on each wood reading). The
inclusion's strain is uniform (Eshelby; the elliptic-cylinder property holds for an anisotropic inclusion in an
anisotropic matrix): ε^I = [I + S : C_m⁻¹ : (C_I − C_m)]⁻¹ : ε^∞, with S from Mura's integral for a cylinder
(a₃ → ∞: S_ijmn = (1/4π)·C_pqmn·∮[G_ipjq + G_jpiq]dω, G_ipjq = ξ_j·ξ_q·K⁻¹_ip(ξ), K_ik = C_ijkl·ξ_j·ξ_l,
ξ = (cos ω, sin ω, 0)); generalized plane strain along R follows from it (S_33kl = 0). t_L = ε^I_LL / ε^∞_LL.
  Wood: Güntekin & Akar 2019 (Drewno 62(204):41–53, doi 10.12841/wood.1644-3985.220.09), P. sylvestris sapwood, matched
  groups at 45/65/85/95 % RH, compression, Tables 1–4 — the authors' own rows, not the literature rows they tabulate
  beside them (in-silico §Critical Rules #43). Their measured compliances are NOT symmetric (ν_LT/E_L against ν_TL/E_T:
  ×1.9 at 45 % RH up to ×5.1 at 95 % — the paper says the orthotropic symmetry «may not be fully satisfied»), so the
  symmetrisation is a READING: «stiff» takes each pair's coupling from the test loaded along its stiffer axis (ν_LT,
  ν_LR, ν_RT), «soft» from the one loaded along its softer axis (ν_TL, ν_RL, ν_TR), «mean» averages the two compliance
  entries. A reading whose compliance is not positive definite is not a material and is excluded, by name, in its group.
  Green wood, a SEPARATE group (⚖️ founder 2026-10-22, 00_07 HW.23, option (Б) by recommendation): no open primary gives
  a full Scots pine set above fibre saturation, so named green sets of OTHER Pinaceae are read as a bracket of named
  readings (in-silico §When Modifying #11), never merged with the Scots pine group — Davies et al. 2016 (P. radiata, four
  boards: stiff/non-stiff outerwood and corewood) as its Table 2 (stated to be a CI-weighted L1 symmetrisation's output,
  not reproduced from the open text) ⊥ its ESM 2/3 raw means, Liu et al. 2019 (Larix principis-rupprechtii, sapwood P4),
  both through the same three symmetrisation readings, and Jeong 2026 (P. densiflora and P. koraiensis, in press) on the
  stiffer-axis reading only, with G_RT BORROWED for both and red pine's ν_RT too (ours; Korean pine prints its own).
  Every reading carries its doi, table, column, species, moisture
  and loading mode (GREEN_SOURCES). The lowest θ = 0 share and `105`'s thresholds are reported for the Scots pine group
  (every key without a suffix — the record before the green group) and for the union of both groups.
  Lattice: the two voxel-FE readings `105` caches (per axis the adverse end of its finest-step bracket, the finest
  unlocked step ⊥ the finest locked one — HW.23, 2026-10-23), read as ONE homogeneous cubic body with its cube axes on
  the part's frame (Zone1Anode: [001] on the anode's axis; the shipped part is graded, so «cubic» holds locally): the
  axial case is E[001] = r_a·E_s (uniaxial stress between frictionless platens) and the radial case, an equibiaxial
  in-plane strain with the ends held, is C11 + C12 = r_r·E_s/((1 + ν_s)(1 − 2ν_s)) — the solid envelope's same test as
  its normaliser. Two roots; the one outside the Voigt bound φ·C_s (Loewner order) is refused. Both readings sit on the
  kinematic side of a traction modulus (`105`), so this tensor may be stiffer than the finite part under traction — while
  against the INFINITE lattice of the periodic voxel case (01_01 §5.2) its in-plane dilatational term C11 + C12 and, on the
  HW.33 (в) geometry, its deviatoric term C11 − C12 as well are lower on every density-matched pairing (before it the
  deviatoric sign depended on the pairing) — but those bases are an extrapolation the part's non-monotone step sweep does
  not prove, so no stiffness ordering between the two is established — an input end, not shown to be the output's. C44 is
  swept over (0, φ·μ_s] — Voigt's ceiling (a tighter bound, Hashin–Shtrikman's, would narrow it) — as the Zener ratio
  A* = 2·C44/(C11 − C12) ∈ (0, A*_V], and read apart from the sweep from that periodic case (Measured C44 below). The cube's rotation θ
  about the anode's axis against L is the anchor's rotation at install, which the model leaves free: swept over 0–45°
  (cubic symmetry and the matrix's mirror close the rest — asserted).
  Pores, three readings of the inclusion's tensor: «nothing» — the bare lattice, the composite's LOWER stiffness end
  (bonded tissue of non-negative stiffness only stiffens it) · «Voigt phase
  bound» φ·C_Ti + (1 − φ)·C_wood — its UPPER stiffness end if the tissue in the pores is no stiffer than the host's
  sapwood in every direction (Phase 3's xylem; unmeasured, and wound xylem is often disoriented) · «additive»
  C_lattice + (1 − φ)·C_wood — a reading between them, no bound. The stiffness ends do NOT bound the SHARE: the additive
  reading falls outside the two ends' shares in some cells (counted), so the lowest share is the minimum of what is
  computed here, never a bound.
  For `105`. The bound needs E_z*(θ) and t_L of the SAME cell, never the ends of two brackets set side by side
  (in-silico §When Modifying #45 (b)). At θ = 0 both are free of C44: t_L is the θ = 0 share and E_z* = E[100], which is
  r_a·E_s on this tensor for every pore reading (filling the pores leaves the skeleton's energy at a given boundary strain
  at least the bare skeleton's minimum). There the bound alone binds above X/t_L at the LOWEST θ = 0 share over the
  modelled set (the side a binding sentence must take, §When Modifying #45 ⊕), X being `105`'s threshold unrounded and
  held to `105`'s cache — printed on this tensor's own E[100] (`105`'s axial reading) and on `105`'s radial reading;
  `105`'s own rule takes the LOWER of the two for a binding claim, and which one that is is read from `105`'s cache
  (`fe_reading_lower` — a finding of the caches since the HW.23 re-sweep replaced the two-point Richardson pair,
  00_07 HW.23); rounded UP. Off the axis E_z*(θ) falls with C44 while t_L
  stays finite, so the threshold has no ceiling as C44 → 0: no binding figure exists there without C44. The junction's
  mismatch (`105`) scales with the HIGHEST share instead; its supremum off the axis is taken at C44 = 0 exactly (t_L is
  non-increasing in C44 — asserted on the grid).
  Measured C44 (00_07 HW.23). The periodic voxel case gives the INFINITE lattice's full cubic tensor on a ladder of mesh
  steps (01_01 §5.2); its rungs of the part's density (porosity within PERIODIC_DENSITY_TOL of the part's) are read as a
  ladder, each rung its own tensor. The part body has no C44 of its own, so carrying one onto it is an assumption, and the
  form it is carried in is a reading: the absolute modulus C44/E_s ⊥ the Zener ratio on the body's own C11 − C12; beside
  them the material tensor read whole, on its own solid fraction (in-silico §When Modifying #11). C44 is carried without a
  density correction — every rung sits within PERIODIC_DENSITY_TOL of the part's porosity. On each, one cell gives
  t_L(θ) and E_z*(θ) of ONE tensor, and `105`'s headline threshold is taken at its highest over the modelled cells, the
  install angle and the rungs — the side a binding sentence takes; the same over the cells C44 enters alone shows what
  the lattice's own off-axis stiffness does.

CAN: per alloy, moisture group or green set, symmetrisation reading, pore reading and install angle — t_L over the
admissible C44, the Zener ratio at which t_L crosses 1 at 45°, how many cells the additive reading leaves the ends'
interval, how many grid points fall, rise or neither across the measured moisture groups, the θ = 0 share's range and
the `105` thresholds at its lowest on two readings (the Scots pine group ⊥ the union with the green group), the
off-axis threshold factor at the C44 grid's ends, the junction's share at θ = 0 and at C44 = 0; the lattice's off-axis
modulus against `105`'s readings; on the measured C44 (three named readings × the ladder's rungs) the binding threshold
with the install angle free beside its θ = 0 figure, the same over the cells C44 enters alone, the highest share over
every angle, the cells whose 45° share exceeds 1 and the angle that minimises the ligaments' stress factor.
CANNOT: (1) give the finite part's own C44 — the measured one is the infinite lattice's (01_01 §5.2), carried onto the
part body as an assumption in two named forms; nor narrow the sweep by Hashin–Shtrikman; (2) give the stiffness of the tissue in the
pores or of the ring — a soft ring decouples the gyroid and drives t_L to 0 in its limit (no monotonicity shown); our
reading of the ring (= the host's xylem) is the only ring modelled, so the lowest share here is the lowest of the
MODELLED set, not of the admissible one; (3) give a green SCOTS PINE share or the share's direction with moisture — the
Scots pine source's wettest group is below fibre saturation and across its groups the share takes no single
direction; above it the readings are other Pinaceae (proxies, not Scots pine), so set beside the Scots pine groups
they confound species with moisture; (4) model the finite length, the
bending gradient along R, the curved growth rings, the bark's proximity or the stem's transverse shear (S5); (5) say
whether `105`'s homogeneous reading of the two FE cases is right — the module calls both ratios «NOT a material
property»; (6) check S_1212 of an ANISOTROPIC matrix against an independent closed form — the isotropic control checks
it on an isotropic matrix only.

Run:  conda activate silken_md
      python tools/in_silico/scripts/106_gyroid_wood_strain_share.py
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("The share of a living stem's in-plane bending strain that a bonded titanium gyroid lattice takes, "
                  "from an orthotropic Eshelby solution for a circular cylinder on the measured elastic constants of "
                  "Scots pine sapwood at four moisture levels below fibre saturation and, as a separate group, of green "
                  "sets of four other Pinaceae, with the lattice's cubic constants read from two voxel "
                  "finite-element cases and its shear modulus both swept up to the Voigt bound and read, as three named readings, "
                  "from a periodic voxel case of the infinite lattice; the install "
                  "angle and three readings of the pore filling are swept as well; closed forms checked against three "
                  "independent solutions, no finite elements")

MECH = CACHE_DIR / "mechanical"
FEA = REPO_ROOT / "tools/cad/cache/fea/anchor_zone1_pine.json"
PERIODIC = REPO_ROOT / "tools/cad/cache/fea/periodic_homogenization.network.w100.c1.json"
SRC105 = MECH / "printed_part_sway_stress.json"
OUT = MECH / "gyroid_wood_strain_share.json"

# ── Güntekin & Akar 2019, Drewno 62(204):41–53, doi 10.12841/wood.1644-3985.220.09 — read in the primary 2026-10-21 ──
# P. sylvestris sapwood (Bolu-Aladağlar, Turkey; logs ≈ 50 cm, 1–3 m above ground), compression with a biaxial
# extensometer, groups conditioned at 21 °C and the RH below. MPa. ν_ij: load along i, dimensional change along j.
# The authors' own four rows of each table — NOT the Dinwoodie / Aira / Pencik rows they tabulate beside them.
# Each table measured its own MC: Table 1 (L) · Table 2 (R) · Table 3 (T) · Table 4 (G) — kept per table.
WOOD = {
    "rh45": {"mc_pct": {"L": 8.0, "R": 8.1, "T": 8.1, "G": 8.2},
             "E_L": 15621.0, "nu_LR": 0.41, "nu_LT": 0.69,          # Table 1 row 1
             "E_R": 804.0, "nu_RT": 0.69, "nu_RL": 0.083,            # Table 2 row 1
             "E_T": 682.0, "nu_TR": 0.64, "nu_TL": 0.057,            # Table 3 row 1
             "G_LR": 1041.0, "G_LT": 911.0, "G_RT": 108.0},          # Table 4 row 1
    "rh65": {"mc_pct": {"L": 12.5, "R": 12.7, "T": 12.1, "G": 12.2},
             "E_L": 14998.0, "nu_LR": 0.60, "nu_LT": 0.74,
             "E_R": 763.0, "nu_RT": 0.69, "nu_RL": 0.075,
             "E_T": 532.0, "nu_TR": 0.68, "nu_TL": 0.063,
             "G_LR": 1007.0, "G_LT": 903.0, "G_RT": 107.0},
    "rh85": {"mc_pct": {"L": 17.4, "R": 17.0, "T": 17.0, "G": 17.7},
             "E_L": 13058.0, "nu_LR": 0.51, "nu_LT": 0.69,
             "E_R": 569.0, "nu_RT": 0.63, "nu_RL": 0.071,
             "E_T": 362.0, "nu_TR": 0.50, "nu_TL": 0.065,
             "G_LR": 828.0, "G_LT": 737.0, "G_RT": 86.0},
    "rh95": {"mc_pct": {"L": 21.6, "R": 20.59, "T": 23.3, "G": 22.8},
             "E_L": 10230.0, "nu_LR": 0.39, "nu_LT": 0.60,
             "E_R": 420.0, "nu_RT": 0.73, "nu_RL": 0.164,
             "E_T": 283.0, "nu_TR": 0.55, "nu_TL": 0.084,
             "G_LR": 737.0, "G_LT": 655.0, "G_RT": 74.0},
}
# The paper's own aggregates of those rows (p. 46–47), each as printed — the authors TRUNCATE, so the transcription
# check compares floor(value, digits) with the printed figure, i.e. to the printed digit only (≈ 3–6 % on the coarsest);
# they are RATIOS, so a scale error common to a whole row would pass.
# «28:1.4:1» (E_L:E_R:E_T) is printed with no RH — it matches the 65 % RH row only, which is OUR attribution; «9.4:8.4:1»
# G_LR:G_LT:G_RT and E_L/G_LR «14.8», E_L/G_LT «16», E_L/G_RT «140» are printed at 65 % RH; the decrease over the MC range
# «58 %» E_T · «47 %» E_R · «34 %» E_L · «31 %» G_RT · «29 %» G_LR · «28 %» G_LT. They hold the E and G rows of 45, 65 and
# 95 % RH; no Poisson ratio and nothing of the 85 % RH row has a printed aggregate — those were read off the tables only.
PRINTED_AGGREGATES = (
    ("E_L/E_T rh65", lambda w: w["rh65"]["E_L"] / w["rh65"]["E_T"], 0, 28.0),
    ("E_R/E_T rh65", lambda w: w["rh65"]["E_R"] / w["rh65"]["E_T"], 1, 1.4),
    ("G_LR/G_RT rh65", lambda w: w["rh65"]["G_LR"] / w["rh65"]["G_RT"], 1, 9.4),
    ("G_LT/G_RT rh65", lambda w: w["rh65"]["G_LT"] / w["rh65"]["G_RT"], 1, 8.4),
    ("E_L/G_LR rh65", lambda w: w["rh65"]["E_L"] / w["rh65"]["G_LR"], 1, 14.8),
    ("E_L/G_LT rh65", lambda w: w["rh65"]["E_L"] / w["rh65"]["G_LT"], 0, 16.0),
    ("E_L/G_RT rh65", lambda w: w["rh65"]["E_L"] / w["rh65"]["G_RT"], 0, 140.0),
    *[(f"decrease {k} %", (lambda key: lambda w: 100.0 * (1.0 - w["rh95"][key] / w["rh45"][key]))(k), 0, v)
      for k, v in (("E_T", 58.0), ("E_R", 47.0), ("E_L", 34.0), ("G_RT", 31.0), ("G_LR", 29.0), ("G_LT", 28.0))],
)

# ── GREEN (above fibre saturation) sets of OTHER Pinaceae — a SEPARATE group, never merged with WOOD ───────────────────
# ⚖️ founder 2026-10-22 (00_07 HW.23, option (Б) by recommendation). Every number below was read in its source on
# 2026-10-22 (Davies Table 1–2, Liu Table 2 and Jeong's red-pine rows also on the page image, Jeong's Korean-pine rows on
# the text layer and then, by a reviewer, on the page image of the hash-pinned copy (p. 6, 200 dpi); Davies ESM 1–3 in the .docx XML
# text, no OCR) and is typed AS PRINTED — strings, because the printed digit sets the rounding the checks below allow.
# ν_ij everywhere: load along i, dimensional change along j (Davies p. 2, Liu p. 4). Jeong prints only the specimens'
# «wider face on the R- or T-plane» and «ν = −εx/εy» (tension, DIC on that face): reading its ν_LR, ν_LT, ν_RT the same
# way is OURS — a face «on the R-plane» read as the plane normal to R would swap ν_LR and ν_LT.
DAVIES_COLUMNS = ("SO", "NSO", "SC", "NSC")    # stiff outerwood · non-stiff outerwood · stiff corewood · non-stiff corewood
# Davies, Altaner & Apiolaza 2016, N.Z. J. For. Sci. 46:19, doi 10.1186/s40490-016-0075-x — Table 2 (p. 3), GPa / –.
# Its caption: «optimised for the orthotropic assumption» — the paper states (p. 2, Eq. 2, read on the page image) a
# minimisation of Σ|δ_i − γ_i|/θ_i under the reciprocity equalities (Eq. 1), θ_i the 95 % CI of the mean (99.9 % for the
# stiff high-density tension sample); with the SEs of ESM 2/3 that output is NOT reproduced from the open text (the
# usable n per face, the t-quantile and the CI of the four-face mean are not printed), so the mechanism is STATED, not
# reproduced. Rows «TL», «LR», «RT» are the shear planes.
DAVIES_TABLE2 = {
    "E_R": ("0.49", "0.3", "0.26", "0.31"), "E_T": ("0.25", "0.19", "0.24", "0.17"), "E_L": ("4.36", "2.81", "3.5", "2.38"),
    "G_LT": ("0.11", "0.21", "0.11", "0.13"), "G_LR": ("0.06", "0.03", "0.04", "0.03"), "G_RT": ("0.05", "0.02", "0.02", "0.04"),
    "nu_RT": ("0.64", "0.54", "0.60", "0.77"), "nu_RL": ("0.03", "0.05", "0.03", "0.06"),
    "nu_TR": ("0.33", "0.33", "0.55", "0.42"), "nu_TL": ("0.03", "0.01", "0.03", "0.04"),
    "nu_LR": ("0.29", "0.47", "0.36", "0.44"), "nu_LT": ("0.60", "0.16", "0.37", "0.50"),
}
# Its Additional file 1, row «This Work | Static | Pinus radiata»: each constant's range over Table 2's four columns —
# the paper's own aggregate of Table 2 (the transcription check). Its Glr «0.3-0.6» is ×10 Table 2's and ESM 2's
# 0.03–0.06 — the source's own discrepancy, kept as printed and named, not checked (G_LR does not enter t_L — asserted).
DAVIES_ESM1_THIS_WORK = {
    "E_R": ("0.26", "0.49"), "E_T": ("0.17", "0.25"), "E_L": ("2.38", "4.36"), "G_LT": ("0.11", "0.21"),
    "G_LR": ("0.3", "0.6"), "G_RT": ("0.02", "0.05"), "nu_RT": ("0.54", "0.77"), "nu_RL": ("0.03", "0.06"),
    "nu_TR": ("0.33", "0.55"), "nu_TL": ("0.01", "0.04"), "nu_LR": ("0.29", "0.47"), "nu_LT": ("0.16", "0.60"),
}
# Its Additional file 2 — «averages of the raw data», «not … optimised for the orthotropic assumption»: E by force
# direction, recording face and tension (_t) / compression (_c), and the shear planes; GPa, means (their SEs are printed
# beside them, not used here). The rl/tl faces of E_R/E_T are printed too and not transcribed: the p. 4 rule takes the
# tangential-radial face «where possible». Additional file 3 — the Poisson ratios, of which the p. 4 rule takes compression.
DAVIES_ESM2 = {
    "rt_t": ("0.40", "0.24", "0.13", "0.16"), "rt_c": ("0.58", "0.36", "0.39", "0.47"),
    "tr_t": ("0.13", "0.22", "0.20", "0.09"), "tr_c": ("0.33", "0.35", "0.29", "0.26"),
    "lr_t": ("11", "3.8", "3.0", "4.3"), "lr_c": ("3.1", "1.0", "3.8", "4.0"),
    "lt_t": ("12", "4.7", "3.2", "4.0"), "lt_c": ("7.5", "1.8", "4.7", "5.9"),
    "TL": ("0.11", "0.21", "0.11", "0.13"), "LR": ("0.06", "0.034", "0.039", "0.030"), "RT": ("0.046", "0.023", "0.023", "0.039"),
}
DAVIES_ESM3_COMPRESSION = {
    "rt_c": ("0.64", "0.52", "0.60", "0.49"), "rl_c": ("0.14", "0.15", "0.22", "0.17"), "tr_c": ("0.47", "0.33", "0.39", "0.42"),
    "tl_c": ("0.10", "0.08", "0.18", "0.08"), "lr_c": ("0.26", "0.41", "0.36", "0.44"), "lt_c": ("0.41", "0.16", "0.37", "0.42"),
}
# Its Table 1 (p. 3), kg/m³: green density (weighed and water-displaced before testing) ⊥ dry density (after 104 °C).
# MC is not printed; ρ_green/ρ_dry − 1 is a LOWER bound on it (OUR derivation: the green volume is at least the dry one),
# taken on the type means.
DAVIES_TABLE1_DENSITY = {"green": ("1143", "1099", "933", "818"), "dry": ("531", "458", "438", "393")}
# Liu, Zhang, Jiang, Wang & Guan 2019, Forests 10:456, doi 10.3390/f10050456 — Table 2 (p. 7), MPa / –: rows = sampling
# positions from the pith (R = 13 · 56 · 76 · 132 mm; P1 pith, P2 heartwood, P3 between, P4 sapwood — p. 3) and the
# printed «Mean» of the four, which the transcription check holds the rows to. Only row «4» is read into the share.
LIU_TABLE2_HEADER = ("E_L", "nu_LT", "nu_LR", "E_T", "nu_TL", "nu_TR", "E_R", "nu_RL", "nu_RT", "G_RT", "G_LR", "G_LT")
LIU_TABLE2 = {
    "1": "5016 0.15 0.13 339 0.04 0.55 628 0.04 0.74 326 538 403",
    "2": "5996 0.47 0.34 423 0.05 0.66 967 0.03 0.75 535 339 352",
    "3": "9365 0.21 0.15 402 0.04 0.53 1154 0.06 0.79 383 404 371",
    "4": "10137 0.36 0.26 282 0.04 0.66 342 0.05 0.81 556 430 446",
    "Mean": "7629 0.30 0.22 362 0.04 0.60 773 0.05 0.77 450 428 393",
}
# Jeong 2026, J. Wood Sci., Article in Press, doi 10.1186/s10086-026-02311-7 — Table 2 (p. 6 of the accepted manuscript),
# red pine (P. densiflora) and Korean pine (P. koraiensis), «mean (coefficient of variation)», GPa / –. Only the
# stiffer-axis-loaded ratios are printed (ν_LR, ν_LT, ν_RT); red pine's green ν_RT is footnote b: «Measured but rejected:
# red pine green νRT (= 3.20) exceeded the thermodynamic admissibility bound». G_RT is not measured. The 6 % rows hold the
# green E_L to the text's own aggregate («red pine 77.1%, 10.50 → 8.10 GPa» · «Korean pine 66.9%, 9.37 → 6.26 GPa»); red
# pine's 19 % row is the source of its borrowed ν_RT. Korean pine prints its green ν_RT (1.12) — nothing borrowed but G_RT.
JEONG_TABLE2_HEADER = ("E_L", "E_R", "E_T", "G_LR", "G_LT", "nu_LR", "nu_LT", "nu_RT")
JEONG_TABLE2_RED_PINE = {
    "6": ("10.50", "0.44", "0.36", "0.80", "1.89", "0.44", "0.44", "0.94"),
    "19": ("8.38", "0.40", "0.35", "0.59", "1.69", "0.15", "0.29", "0.94"),
    "Green": ("8.10", "0.25", "0.10", "0.27", "0.60", "0.93", "0.63", None),
}
JEONG_GREEN_CV = {"E_L": "0.28", "E_R": "0.20", "E_T": "0.54", "nu_LR": "0.80", "nu_LT": "1.11"}   # printed beside the means
JEONG_E_L_RETENTION_PRINTED_PCT = 77.1                     # the text, p. 6: «red pine 77.1%, 10.50 → 8.10 GPa»
JEONG_TABLE2_KOREAN_PINE = {
    "6": ("9.37", "0.33", "0.32", "0.64", "1.60", "0.53", "0.63", "0.81"),
    "19": ("7.60", "0.30", "0.16", "0.47", "0.95", "0.43", "0.68", "0.83"),
    "Green": ("6.26", "0.20", "0.09", "1.05", "0.80", "0.30", "0.30", "1.12"),
}
JEONG_KOREAN_PINE_GREEN_CV = {"E_L": "0.09", "E_R": "0.44", "E_T": "0.43", "nu_LR": "1.64", "nu_LT": "1.37", "nu_RT": "0.57"}
JEONG_KOREAN_PINE_E_L_RETENTION_PRINTED_PCT = "66.9"       # the text, p. 6: «Korean pine 66.9%, 9.37 → 6.26 GPa»
# The copy read: the accepted manuscript (Article in Press, 19 pp.), whose PDF at the citation address answered 404 by
# 2026-10-22 — so the copy is pinned by its hash, and Table 2 is to be re-read in the Version of Record once it is out.
JEONG_PDF_READ = {"sha256": "de111dcf4a24d61bfdcaf69720889edf2bd6e439b67c57635b71c74c2a2d49c4", "bytes": 3058176,
                  "pages": 19, "read": "2026-10-22, Table 2 on the text layer; red pine rows also on the page image; Korean pine rows on the page image (p. 6, 200 dpi) by the reviewer, all 24 constants and 6 CVs matching",
                  "to_do": "re-read Table 2 in the Version of Record"}
# The source of every green set: species, position, moisture and loading as printed, and what is OURS.
GREEN_SOURCES = {
    "davies2016": {
        "citation": "Davies, Altaner & Apiolaza 2016, N.Z. J. For. Sci. 46:19", "doi": "10.1186/s40490-016-0075-x",
        "species": "Pinus radiata (Canterbury, NZ; boards from trees ≈ 28 years old)",
        "position": "outerwood ⊥ corewood by ring width and curvature (adjacent to the bark ⊥ the pith, p. 2); sapwood or "
                    "heartwood not reported; one board per type, so type and board are confounded (p. 4)",
        "moisture": "green, «never-dried» (p. 1, keywords; p. 4 and p. 5); stored «in sealed bags with excess water at "
                    "5 °C for a maximum period of 2 weeks» (p. 2); MC not printed — its lower bound ρ_green/ρ_dry − 1 "
                    "from Table 1 is OUR derivation",
        "loading": "moduli: tension (bone and stick specimens) and compression (30 × 15 × 15 mm) averaged; ν from "
                   "compression (p. 4); DIC on two faces; n = 6 replicates × 4 boards × 3 orientations × 3 tests = 216 "
                   "(p. 2) — the usable n per face, the t-quantile and the CI of the four-face mean are not printed",
        "table2": "Table 2 (p. 3) — stated (Eq. 2) to be a CI-weighted L1 symmetrisation's output, not reproduced from the "
                  "open text; symmetric by construction to its printed digits",
        "esm": "Additional files 2 (moduli) and 3 (Poisson ratios) — raw means; read by the paper's p. 4 rule as WE read "
               "it: E_R from the rt face and E_T from the tr face, each tension and compression averaged; E_L the mean of "
               "its four face-and-mode values; ν from compression",
    },
    "liu2019": {
        "citation": "Liu, Zhang, Jiang, Wang & Guan 2019, Forests 10:456", "doi": "10.3390/f10050456",
        "species": "Larix principis-rupprechtii (Chinese larch — Larix, not Pinus); 2 trees, 40 years, DBH 32 and 36 cm",
        "position": "Table 2 row «4»: P4, sapwood, 132 mm from the pith (p. 3)",
        "moisture": "green logs; trees' mean MC 95 % (kiln-dry method on 15-cm discs cut at 1.1 m over the whole cross-section, "
                    "heartwood included, p. 3 and p. 6); P4 specimen MC not printed; specimens stored sealed at 15 °C / 95 % RH. "
                    "The abstract gives «95% moisture content at four different cross-section sampling positions», the body "
                    "«the average MC of the sample trees was 95%» (p. 6) — read: the body",
        "loading": "E and ν: compression with strain gauges (p. 4–5); G_LR, G_LT: three-point bending over five spans; "
                   "G_RT: compression of 45° specimens",
        "reciprocity": "the authors check inequality (7) only (Table 4) and state Maxwell consistency; the equality (6) "
                       "on P4 is our arithmetic",
    },
    "jeong2026": {
        "citation": "Jeong 2026, J. Wood Sci. (Article in Press)", "doi": "10.1186/s10086-026-02311-7",
        "species": "Pinus densiflora (red pine) and Pinus koraiensis (Korean pine); sapwood or heartwood not stated",
        "position": "Table 2, rows Red pine / Green and Korean pine / Green",
        "moisture": "«green (saturated)», number not printed, «verified gravimetrically by the oven-dry method on companion "
                    "specimens»; not stated to be never-dried",
        "loading": "uniaxial tension, stereo DIC, 0.5 mm/min; the author: «the transverse moduli are systematically "
                   "underestimated in direct radial and tangential tension»",
        "nu_convention_ours": "the paper prints only «the wider face on the R- or T-plane» and «ν = −εx/εy»; reading its "
                              "ν_ij as load along i, dimensional change along j is OURS (a face «on the R-plane» read as "
                              "the plane normal to R would swap ν_LR and ν_LT — equal, 0.30, in Korean pine's green row)",
        "in_press": "internal contradictions in the accepted manuscript: «three moisture-content (MC) states» (abstract) ⊥ "
                    "«four discrete MC levels—6%, 19%, and green» (text); «three directly measured Poisson's ratios» ⊥ «The "
                    "four directly measured Poisson’s ratios»; «Seven dogbone configurations» ⊥ «six anatomical loading "
                    "configurations» (Materials and methods); «6% (oven-dry equivalent)» for a 6 % MC state; «consistent "
                    "with the Maxwell reciprocity relations» with no reciprocal ratio measured — re-read Table 2 in the "
                    "Version of Record",
        "pdf_read": JEONG_PDF_READ,
        "borrowed_ours": {
            "nu_RT": "red pine: 0.94 — Jeong's own red pine at 19 % MC (Table 2): the same species and method at the nearest "
                     "measured MC; the green value 3.20 was measured and rejected by the author. Korean pine: none — its "
                     "green ν_RT 1.12 is printed",
            "G_RT": "74 MPa, both species — Güntekin & Akar 2019's 95 % RH group (the target species' wettest); Jeong "
                    "measures no G_RT",
        },
    },
}
# The span of ν_RT over which the borrowed value's sensitivity is measured: every MEASURED ν_RT among the named readings
# (Güntekin & Akar, Davies Table 2 and ESM 3, Liu P4, Jeong's Korean pine green) and Jeong's own red pine at 6 and 19 % MC
# (built in main()).
NU_RT_SWEEP_POINTS = 10
NU_RT_SENSITIVITY_CAP = 0.002            # |Δt_L| at θ = 0 over that span — asserted (00_07 HW.23, the re-run's leg)
G_PROBE_FACTORS = (0.1, 10.0)            # G_LR and G_RT scaled by these: t_L must not move (the anti-plane block decouples)

READINGS = ("stiff", "soft", "mean")
FILLS = ("pores_carry_nothing", "pores_additive_host_sapwood", "pores_voigt_phase_bound")
LATTICE_FILLS = ("pores_carry_nothing", "pores_additive_host_sapwood")     # the readings the lattice's C44 enters
THETA_DEG = tuple(2.5 * i for i in range(19))          # 0 … 45°, the install rotation of the cube about the anode's axis
A_POINTS = 41                                           # Zener ratio grid, geometric from A_FLOOR·A*_V to A*_V
A_FLOOR = 1e-3                                          # the grid's lower end as a fraction of A*_V (the range is open at 0)
N_QUAD = 720                                            # ω points of Mura's integral (periodic integrand — midpoint rule)
GROUPS = ("rh45", "rh65", "rh85", "rh95")               # the moisture order of the source's groups
COVARIANCE_DEG = 30.0                                   # the matrix rotation of the covariance control
CELL_LS = "large_stem_limit|near_uniaxial|sf2"          # 105's headline cell
PERIODIC_RUNGS = (24, 32, 48, 64)                      # the periodic ladder's rungs of the part's density (01_01 §5.2)
PERIODIC_DENSITY_TOL = 0.005                           # |porosity − the part's| that admits a rung (/16 sits 1.6 pp off)
C44_FORMS = ("part_body_C44_absolute", "part_body_zener", "material_tensor")

# Axes 0 = L (the stem's axis), 1 = T, 2 = R (the anchor's axis). Mandel order 11, 22, 33, 23, 13, 12.
VOIGT = ((0, 0), (1, 1), (2, 2), (1, 2), (0, 2), (0, 1))
R2 = math.sqrt(2.0)
MW = np.array([1.0, 1.0, 1.0, R2, R2, R2])


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def up0(x: float) -> float:
    """Rounded UP to a whole µε — a «binds above X» sentence (in-silico §When Modifying #43)."""
    return float(math.ceil(round(x, 9)))


def floor_to(x: float, digits: int) -> float:
    f = 10.0 ** digits
    return math.floor(round(x * f, 9)) / f


def ceil_to(x: float, digits: int) -> float:
    f = 10.0 ** digits
    return math.ceil(round(x * f, 9)) / f


def to4(c66: np.ndarray) -> np.ndarray:
    """A Voigt-indexed 6×6 stiffness (engineering shear, i.e. plain C_ijkl entries) to the full tensor."""
    c = np.zeros((3, 3, 3, 3))
    for a, (i, j) in enumerate(VOIGT):
        for b, (k, n) in enumerate(VOIGT):
            for p, q in {(i, j), (j, i)}:
                for r, s in {(k, n), (n, k)}:
                    c[p, q, r, s] = c66[a, b]
    return c


def mandel(t: np.ndarray) -> np.ndarray:
    """A minor-symmetric 4th-order tensor to its Mandel 6×6 — double contraction becomes the matrix product."""
    m = np.zeros((6, 6))
    for a, (i, j) in enumerate(VOIGT):
        for b, (k, n) in enumerate(VOIGT):
            m[a, b] = t[i, j, k, n] * MW[a] * MW[b]
    return m


def strain_vec(e: np.ndarray) -> np.ndarray:
    return np.array([e[i, j] for i, j in VOIGT]) * MW


def rotate(c: np.ndarray, theta: float) -> np.ndarray:
    """Rotate a tensor by θ about the R axis (axis 2)."""
    co, si = math.cos(theta), math.sin(theta)
    q = np.array([[co, -si, 0.0], [si, co, 0.0], [0.0, 0.0, 1.0]])
    return np.einsum("ia,jb,kc,ld,abcd->ijkl", q, q, q, q, c)


def iso_c(e: float, nu: float) -> np.ndarray:
    lam, mu = e * nu / ((1 + nu) * (1 - 2 * nu)), e / (2 * (1 + nu))
    i3 = np.eye(3)
    return (lam * np.einsum("ij,kl->ijkl", i3, i3)
            + mu * (np.einsum("ik,jl->ijkl", i3, i3) + np.einsum("il,jk->ijkl", i3, i3)))


def eshelby_cylinder(c: np.ndarray, n: int = N_QUAD) -> np.ndarray:
    """Mura's S_ijmn for an infinite circular cylinder along axis 2 in an anisotropic matrix (midpoint rule in ω)."""
    g = np.zeros((3, 3, 3, 3))
    w = 2.0 * math.pi / n
    for k in range(n):
        om = (k + 0.5) * w
        xi = np.array([math.cos(om), math.sin(om), 0.0])
        kinv = np.linalg.inv(np.einsum("ijkl,j,l->ik", c, xi, xi))
        g += np.einsum("ip,j,q->ipjq", kinv, xi, xi) * w
    t = g + np.einsum("jpiq->ipjq", g)
    return np.einsum("ipjq,pqmn->ijmn", t, c) / (4.0 * math.pi)


def inclusion_strain(cm: np.ndarray, ci: np.ndarray, s: np.ndarray, eps_inf: np.ndarray) -> np.ndarray:
    """Mandel vector of the inclusion's uniform strain: [I + S·C_m⁻¹·(C_I − C_m)]·ε^I = ε^∞ (all Mandel)."""
    a = np.eye(6) + s @ np.linalg.solve(cm, ci - cm)
    return np.linalg.solve(a, eps_inf)


def wood_compliance(w: dict, reading: str) -> np.ndarray:
    """Engineering 6×6 compliance (Voigt, γ = 2ε) of one group under one symmetrisation reading. The softer-axis couplings
    are built only when the reading needs them — a set that prints the stiffer-axis ratios only (Jeong) has none."""
    def stiff():
        return {"LT": -w["nu_LT"] / w["E_L"], "LR": -w["nu_LR"] / w["E_L"], "TR": -w["nu_RT"] / w["E_R"]}

    def soft():
        return {"LT": -w["nu_TL"] / w["E_T"], "LR": -w["nu_RL"] / w["E_R"], "TR": -w["nu_TR"] / w["E_T"]}

    if reading == "stiff":
        pick = stiff()
    elif reading == "soft":
        pick = soft()
    else:
        st, so = stiff(), soft()
        pick = {k: 0.5 * (st[k] + so[k]) for k in st}
    s = np.zeros((6, 6))
    s[0, 0], s[1, 1], s[2, 2] = 1.0 / w["E_L"], 1.0 / w["E_T"], 1.0 / w["E_R"]
    s[0, 1] = s[1, 0] = pick["LT"]
    s[0, 2] = s[2, 0] = pick["LR"]
    s[1, 2] = s[2, 1] = pick["TR"]
    s[3, 3], s[4, 4], s[5, 5] = 1.0 / w["G_RT"], 1.0 / w["G_LR"], 1.0 / w["G_LT"]
    return s


def cubic_parts(c11: float, c12: float, theta: float) -> tuple[np.ndarray, np.ndarray]:
    """Mandel stiffness of a unit-E_s cubic body split as base (C44 = 0) + shear (C44 = 1), rotated by θ about R."""
    base = np.zeros((6, 6))
    base[:3, :3] = c12
    np.fill_diagonal(base[:3, :3], c11)
    shear = np.zeros((6, 6))
    shear[3, 3] = shear[4, 4] = shear[5, 5] = 1.0
    return mandel(rotate(to4(base), theta)), mandel(rotate(to4(shear), theta))


# ── The green sets, built from the transcriptions above (MPa / –) ─────────────────────────────────────────────────────
DAVIES_COLUMN_NAMES = {"SO": "stiff outerwood", "NSO": "non-stiff outerwood", "SC": "stiff corewood", "NSC": "non-stiff corewood"}


def _mpa(gpa: str) -> float:
    """A printed GPa figure in MPa, at its printed digits."""
    return round(float(gpa) * 1e3, 6)


def _half_unit(printed: str) -> float:
    """Half a unit of the last printed digit — the rounding a printed figure carries."""
    return 0.5 * 10.0 ** -(len(printed.split(".")[1]) if "." in printed else 0)


def davies_set(col: int, which: str) -> dict:
    """One Davies column: «table2» — Table 2 as printed; «esm» — the raw means of ESM 2/3 by the paper's p. 4 rule as WE
    read it (E_R from the rt face and E_T from the tr face, tension and compression averaged; E_L the mean of its four
    face-and-mode values; ν from compression; G from ESM 2)."""
    if which == "table2":
        return {k: (float(v[col]) if k.startswith("nu_") else _mpa(v[col])) for k, v in DAVIES_TABLE2.items()}
    e = {k: float(v[col]) for k, v in DAVIES_ESM2.items()}
    n = {k: float(v[col]) for k, v in DAVIES_ESM3_COMPRESSION.items()}
    return {"E_R": round((e["rt_t"] + e["rt_c"]) / 2 * 1e3, 6), "E_T": round((e["tr_t"] + e["tr_c"]) / 2 * 1e3, 6),
            "E_L": round((e["lr_t"] + e["lr_c"] + e["lt_t"] + e["lt_c"]) / 4 * 1e3, 6),
            "G_LT": _mpa(DAVIES_ESM2["TL"][col]), "G_LR": _mpa(DAVIES_ESM2["LR"][col]), "G_RT": _mpa(DAVIES_ESM2["RT"][col]),
            "nu_RT": n["rt_c"], "nu_RL": n["rl_c"], "nu_TR": n["tr_c"], "nu_TL": n["tl_c"], "nu_LR": n["lr_c"], "nu_LT": n["lt_c"]}


def liu_row(row: str) -> dict:
    return dict(zip(LIU_TABLE2_HEADER, (float(x) for x in LIU_TABLE2[row].split()), strict=True))


def jeong_red_pine_green(nu_rt: float | None = None) -> dict:
    """Jeong's red pine, green: the printed constants, with ν_RT and G_RT BORROWED (ours — GREEN_SOURCES); `nu_rt`
    replaces the borrowed ν_RT for the sensitivity control. The softer-axis ratios are not printed, so it builds the
    stiffer-axis reading only."""
    green = dict(zip(JEONG_TABLE2_HEADER, JEONG_TABLE2_RED_PINE["Green"], strict=True))
    w = {k: (float(v) if k.startswith("nu_") else _mpa(v)) for k, v in green.items() if v is not None}
    w["nu_RT"] = float(JEONG_TABLE2_RED_PINE["19"][JEONG_TABLE2_HEADER.index("nu_RT")]) if nu_rt is None else nu_rt
    w["G_RT"] = WOOD["rh95"]["G_RT"]
    return w


def jeong_korean_pine_green() -> dict:
    """Jeong's Korean pine, green: the printed constants, its printed ν_RT included; G_RT BORROWED as for red pine (ours).
    The stiffer-axis reading only, as for red pine."""
    w = {k: (float(v) if k.startswith("nu_") else _mpa(v))
         for k, v in zip(JEONG_TABLE2_HEADER, JEONG_TABLE2_KOREAN_PINE["Green"], strict=True)}
    w["G_RT"] = WOOD["rh95"]["G_RT"]
    return w


def green_sets() -> dict:
    """name → the set's constants, the symmetrisation readings it builds, its source and where in the source it sits."""
    sets = {}
    for which, where in (("table2", "Table 2"), ("esm", "Additional files 2–3")):
        for i, col in enumerate(DAVIES_COLUMNS):
            sets[f"davies2016_{which}_{col}"] = {
                "w": davies_set(i, which), "readings": READINGS, "source": "davies2016",
                "where": f"{where}, {DAVIES_COLUMN_NAMES[col]}",
                "mc_lower_bound_pct_ours": 100.0 * (float(DAVIES_TABLE1_DENSITY["green"][i])
                                                    / float(DAVIES_TABLE1_DENSITY["dry"][i]) - 1.0)}
    sets["liu2019_P4"] = {"w": liu_row("4"), "readings": READINGS, "source": "liu2019",
                          "where": "Table 2, row 4 (P4, sapwood, R = 132 mm)"}
    sets["jeong2026_red_pine_green"] = {"w": jeong_red_pine_green(), "readings": ("stiff",), "source": "jeong2026",
                                        "where": "Table 2, Red pine / Green — ν_RT and G_RT borrowed (ours)"}
    sets["jeong2026_korean_pine_green"] = {"w": jeong_korean_pine_green(), "readings": ("stiff",), "source": "jeong2026",
                                           "where": "Table 2, Korean pine / Green — G_RT borrowed (ours), ν_RT printed"}
    return sets


def _davies_coupling_interval(col: int, pair: str) -> tuple[float, float]:
    """The interval ν_ij/E_i spans in one Table 2 column at the printed rounding of ν_ij and E_i (pair = «ij»)."""
    nu_s, e_s = DAVIES_TABLE2[f"nu_{pair}"][col], DAVIES_TABLE2[f"E_{pair[0]}"][col]
    nu, e, hn, he = float(nu_s), float(e_s), _half_unit(nu_s), _half_unit(e_s)
    return (nu - hn) / (e + he), (nu + hn) / (e - he)


def green_transcription_checks() -> dict:
    """Each green transcription held to its source's OWN aggregate. CAN catch: a mistyped extreme of a Davies Table 2 row
    (ESM 1 prints each row's range over the four columns); a Table 2 ν or E slip that breaks its by-construction
    reciprocity beyond the printed rounding; a column or row swap or a misplaced digit in Liu's Table 2 (its printed Mean
    of the four positions); a mistyped Jeong green E_L of either species (the text's retentions — Korean pine's within
    the printed rounding only). CANNOT catch: an interior Davies column that stays inside both its row's range and the
    reciprocity rounding; a last-digit slip in one Liu row (it moves the mean by a quarter of a unit); any Jeong constant
    but E_L; anything in ESM 2/3 — no aggregate is printed (read from the .docx XML text, no OCR)."""
    out = {"davies_table2_vs_esm1_range": {}, "davies_table2_reciprocity_within_rounding": {},
           "liu_table2_vs_printed_mean": {}, "jeong_e_l_retention_pct": {}}
    for k, (lo, hi) in DAVIES_ESM1_THIS_WORK.items():
        vals = [float(v) for v in DAVIES_TABLE2[k]]
        ok = (min(vals), max(vals)) == (float(lo), float(hi))
        out["davies_table2_vs_esm1_range"][k] = {"table2_min_max": [min(vals), max(vals)], "esm1": [lo, hi], "match": ok}
        if k != "G_LR":                                     # the source's own ×10 (named above), not a transcription
            assert ok, f"Davies Table 2 row {k} off ESM 1's «This Work» range: {vals} vs {lo}–{hi}"
    assert not out["davies_table2_vs_esm1_range"]["G_LR"]["match"], "ESM 1's G_LR now matches Table 2 — re-read it"
    for i, col in enumerate(DAVIES_COLUMNS):
        for a, b in (("TR", "RT"), ("LR", "RL"), ("TL", "LT")):
            (lo1, hi1), (lo2, hi2) = _davies_coupling_interval(i, a), _davies_coupling_interval(i, b)
            ok = lo1 <= hi2 and lo2 <= hi1
            out["davies_table2_reciprocity_within_rounding"][f"{col}|{a}~{b}"] = ok
            assert ok, f"Davies Table 2 {col}: ν_{a}/E_{a[0]} and ν_{b}/E_{b[0]} disagree beyond the printed rounding"
    rows = [liu_row(r) for r in ("1", "2", "3", "4")]
    for j, k in enumerate(LIU_TABLE2_HEADER):
        printed = LIU_TABLE2["Mean"].split()[j]
        mean = sum(r[k] for r in rows) / 4.0
        ok = abs(mean - float(printed)) <= _half_unit(printed) + 1e-9
        out["liu_table2_vs_printed_mean"][k] = {"mean_of_rows": mean, "printed": float(printed), "match": ok}
        assert ok, f"Liu Table 2 column {k}: the four rows average {mean}, the printed Mean is {printed}"
    hdr = JEONG_TABLE2_HEADER.index("E_L")
    ret = 100.0 * float(JEONG_TABLE2_RED_PINE["Green"][hdr]) / float(JEONG_TABLE2_RED_PINE["6"][hdr])
    out["jeong_e_l_retention_pct"] = {"computed": ret, "printed": JEONG_E_L_RETENTION_PRINTED_PCT}
    assert round(ret, 1) == JEONG_E_L_RETENTION_PRINTED_PCT, f"Jeong's green E_L off the text's retention: {ret}"
    # Korean pine: the quotient of the printed means rounds to 66.8, the text prints 66.9 — inside the interval the two
    # printed means span at their rounding, so the source's own rounding, not a transcription slip; held to that interval
    g_s, d_s, p_s = JEONG_TABLE2_KOREAN_PINE["Green"][hdr], JEONG_TABLE2_KOREAN_PINE["6"][hdr], \
        JEONG_KOREAN_PINE_E_L_RETENTION_PRINTED_PCT
    lo = 100.0 * (float(g_s) - _half_unit(g_s)) / (float(d_s) + _half_unit(d_s))
    hi = 100.0 * (float(g_s) + _half_unit(g_s)) / (float(d_s) - _half_unit(d_s))
    ok = lo <= float(p_s) + _half_unit(p_s) and float(p_s) - _half_unit(p_s) <= hi
    out["jeong_korean_pine_e_l_retention_pct"] = {
        "computed": 100.0 * float(g_s) / float(d_s), "printed": float(p_s),
        "interval_at_printed_rounding": [lo, hi], "match_within_rounding": ok}
    assert ok, f"Jeong's Korean pine green E_L off the text's retention: {lo}–{hi} vs {p_s}"
    return out


def reciprocity(w: dict) -> dict | None:
    """(ν_ji/E_j)/(ν_ij/E_i) per pair, the transverse-loaded entry over the L-loaded one (and R-loaded over T-loaded for
    R–T) — our arithmetic; 1 where the measured compliance is symmetric. None where a set prints one side only."""
    if any(w.get(k) is None for k in ("nu_RL", "nu_TL", "nu_TR")):
        return None
    return {"RL_over_LR": (w["nu_RL"] / w["E_R"]) / (w["nu_LR"] / w["E_L"]),
            "TL_over_LT": (w["nu_TL"] / w["E_T"]) / (w["nu_LT"] / w["E_L"]),
            "RT_over_TR": (w["nu_RT"] / w["E_R"]) / (w["nu_TR"] / w["E_T"])}


# ── Controls — each against an INDEPENDENT closed form (in-silico §When Modifying #8) ───────────────────────────────
def control_isotropic_cylinder(nu: float) -> float:
    """Mura's S against the isotropic circular-cylinder closed form. CAN catch: a wrong normalisation (1/4π), a dropped
    symmetrisation term, a wrong ξ, the cylinder on the wrong axis — on the seven entries it compares (S_1111, S_1122,
    S_1133, S_1212, S_1313 and two zeros of S_33kl).
    CANNOT catch: an error that only an anisotropic matrix excites."""
    s = eshelby_cylinder(iso_c(1.0, nu))
    ref = {(0, 0, 0, 0): (5 - 4 * nu) / (8 * (1 - nu)), (0, 0, 1, 1): (4 * nu - 1) / (8 * (1 - nu)),
           (0, 0, 2, 2): nu / (2 * (1 - nu)), (0, 1, 0, 1): (3 - 4 * nu) / (8 * (1 - nu)),
           (2, 2, 0, 0): 0.0, (2, 2, 2, 2): 0.0, (0, 2, 0, 2): 0.25}
    return max(abs(s[k] - v) for k, v in ref.items())


def control_orthotropic_hole(s66: np.ndarray, s_esh: np.ndarray, cm4: np.ndarray) -> dict:
    """A circular HOLE (C_I = 0) under remote σ_L: the stress at its edge on the T axis, from the Eshelby strain and the
    interface jump, against Lekhnitskii's K_t = 1 + √(2√(b22/b11) + (2·b12 + b66)/b11) on the plane-strain reduced
    compliances b_ij = a_ij − a_i3·a_j3/a_33. CAN catch: an error in the NORMAL block of S (the entries σ_L excites) on
    an anisotropic matrix, a wrong C_m, the equivalent-inclusion algebra at the C_I = 0 end. CANNOT catch: the shear
    entry S_1212 on an anisotropic matrix (σ_L on an orthotropic matrix never excites it — script ceiling (6)), nor the
    algebra at a finite inclusion stiffness — the next control does that."""
    cm = mandel(cm4)
    sig = np.zeros((3, 3))
    sig[0, 0] = 1.0
    eps_inf = np.linalg.solve(cm, strain_vec(sig))
    e_i = inclusion_strain(cm, np.zeros((6, 6)), mandel(s_esh), eps_inf)
    e_t = np.zeros((3, 3))
    for a, (i, j) in enumerate(VOIGT):
        e_t[i, j] = e_t[j, i] = e_i[a] / MW[a]
    n = np.array([0.0, 1.0, 0.0])
    lam = -np.linalg.solve(np.einsum("ijkl,j,l->ik", cm4, n, n), np.einsum("ijkl,kl->ij", cm4, e_t) @ n)
    e_out = e_t + 0.5 * (np.outer(lam, n) + np.outer(n, lam))
    s_out = np.einsum("ijkl,kl->ij", cm4, e_out)

    def b(i, j):
        return s66[i, j] - s66[i, 2] * s66[j, 2] / s66[2, 2]

    kt = 1.0 + math.sqrt(2.0 * math.sqrt(b(1, 1) / b(0, 0)) + (2.0 * b(0, 1) + s66[5, 5]) / b(0, 0))
    return {"kt_eshelby": float(s_out[0, 0]), "kt_lekhnitskii": kt, "traction_residual": float(np.abs(s_out @ n).max())}


def control_isotropic_inclusion() -> float:
    """A finite isotropic inclusion in an isotropic matrix under a plane-strain remote stress (ε_33 = 0): the inclusion's
    mean stress and deviator against Goodier/Muskhelishvili, P_I/P = μ_i(κ_m + 1)/(2μ_i + μ_m(κ_i − 1)),
    D_I/D = μ_i(κ_m + 1)/(μ_m + κ_m·μ_i), κ = 3 − 4ν. CAN catch: the equivalent-inclusion algebra at a finite C_I (sign,
    order of C_m⁻¹ and S). CANNOT catch: anisotropy — the hole control above."""
    em, nm, ei, ni = 1.0, 0.30, 7.0, 0.20
    cm4, ci4 = iso_c(em, nm), iso_c(ei, ni)
    sig = np.zeros((3, 3))
    sig[0, 0], sig[1, 1], sig[0, 1], sig[1, 0] = 1.0, 0.3, 0.2, 0.2
    sig[2, 2] = nm * (sig[0, 0] + sig[1, 1])
    cm, ci = mandel(cm4), mandel(ci4)
    eps_inf = np.linalg.solve(cm, strain_vec(sig))
    s_i = ci @ inclusion_strain(cm, ci, mandel(eshelby_cylinder(cm4)), eps_inf) / MW
    mu_m, mu_i, k_m, k_i = em / (2 * (1 + nm)), ei / (2 * (1 + ni)), 3 - 4 * nm, 3 - 4 * ni
    f_p = mu_i * (k_m + 1) / (2 * mu_i + mu_m * (k_i - 1))
    f_d = mu_i * (k_m + 1) / (mu_m + k_m * mu_i)
    return max(abs((s_i[0] + s_i[1]) / 2 - f_p * (sig[0, 0] + sig[1, 1]) / 2),
               abs((s_i[0] - s_i[1]) / 2 - f_d * (sig[0, 0] - sig[1, 1]) / 2),
               abs(s_i[5] - f_d * sig[0, 1]))


def control_covariance(cm4: np.ndarray, s_esh: np.ndarray) -> float:
    """Mura's S of the matrix rotated by α about the cylinder's axis against S rotated by α: a circle is invariant under
    that rotation, so S(R·C) = R·S(C). CAN catch: an index order in G or in the contraction that is not tensorial and only
    shows once the matrix is anisotropic in the frame. CANNOT catch: an error common to S before and after the rotation
    (it relates the entries to each other; it does not fix S_1212 of an anisotropic matrix to a closed form)."""
    a = math.radians(COVARIANCE_DEG)
    return float(np.abs(eshelby_cylinder(rotate(cm4, a)) - rotate(s_esh, a)).max())


def main() -> int:
    banner("106 — the share of the wood's strain the bonded gyroid takes: orthotropic Eshelby on Scots pine")
    s105 = _load("s105_106", "105_printed_part_sway_stress.py")
    d105 = json.loads(SRC105.read_text(encoding="utf-8"))
    fea = json.loads(FEA.read_text(encoding="utf-8"))

    # ── Transcription of the primary against its own printed aggregates ────────────────────────────────────────────
    transcription = {}
    for name, f, digits, printed in PRINTED_AGGREGATES:
        v = f(WOOD)
        transcription[name] = {"computed": v, "printed": printed}
        assert floor_to(v, digits) == printed, f"transcription off the paper's own aggregate {name}: {v} vs {printed}"
    green_transcription = green_transcription_checks()             # each green source against its own aggregate
    gsets = green_sets()
    for name, w in [*WOOD.items(), *((n, gs["w"]) for n, gs in gsets.items())]:
        assert w["E_L"] > w["E_R"] > w["E_T"], f"{name}: «stiff» names the R-loaded R–T test only while E_R > E_T"

    # ── The lattice: 105's two FE readings, re-read with 105's own rule (ONE home) from the same caches ──────────────
    fe_now = s105.read_fe()
    for key in ("radial_reading", "axial_reading"):
        assert abs(fe_now["readings"][key] - d105["inputs"]["fe_readings"][key]) < 1e-12, \
            f"105's cache disagrees with its own reading rule on the FE caches ({key}) — re-run 105"
    assert abs(fea["poisson_ratio"] - s105.NU_SOLID) < 1e-12, "the FE's ν moved — re-read it"
    r_r = d105["inputs"]["fe_readings"]["radial_reading"]
    r_a = d105["inputs"]["fe_readings"]["axial_reading"]
    phi = d105["inputs"]["solid_fraction"]
    nu_s = fea["poisson_ratio"]
    c11_s, c12_s = (1 - nu_s) / ((1 + nu_s) * (1 - 2 * nu_s)), nu_s / ((1 + nu_s) * (1 - 2 * nu_s))
    mu_s = 1.0 / (2 * (1 + nu_s))
    p = r_r / ((1 + nu_s) * (1 - 2 * nu_s))                        # C11 + C12, units of E_s
    disc = 9 * p * p - 8 * p * r_a
    assert disc > 0, "the two FE readings admit no homogeneous cubic body"
    roots = []
    for q in ((3 * p - math.sqrt(disc)) / 2, (3 * p + math.sqrt(disc)) / 2):
        c11, c12 = (p + q) / 2, (p - q) / 2
        gap = phi * np.array([[c11_s, c12_s, c12_s], [c12_s, c11_s, c12_s], [c12_s, c12_s, c11_s]]) \
            - np.array([[c11, c12, c12], [c12, c11, c12], [c12, c12, c11]])
        e100 = (c11 - c12) * (c11 + 2 * c12) / (c11 + c12)
        roots.append({"C11": c11, "C12": c12, "nu": c12 / (c11 + c12), "E100": e100,
                      "inside_voigt": bool(np.linalg.eigvalsh(gap).min() >= -1e-12)})
        assert abs(e100 - r_a) < 1e-12 and abs((c11 + c12) - p) < 1e-12, "a root does not reproduce the FE readings"
    admissible = [r for r in roots if r["inside_voigt"]]
    assert len(admissible) == 1, "the Voigt bound does not single out one root"
    lat = admissible[0]
    q_lat = lat["C11"] - lat["C12"]
    a_voigt = 2 * phi * mu_s / q_lat
    a_grid = np.geomspace(A_FLOOR * a_voigt, a_voigt, A_POINTS)
    parts = {th: cubic_parts(lat["C11"], lat["C12"], math.radians(th)) for th in THETA_DEG}

    # ── Controls ──────────────────────────────────────────────────────────────────────────────────────────────────────
    ctl_iso = max(control_isotropic_cylinder(nu) for nu in (0.0, 0.3, 0.45))
    ctl_incl = control_isotropic_inclusion()
    assert ctl_iso < 1e-12 and ctl_incl < 1e-12, f"closed-form controls failed: {ctl_iso}, {ctl_incl}"

    # ── The wood readings: the Scots pine group (WOOD) and, apart, the green group (GREEN_SOURCES) ─────────────────────
    def build_reading(s66: np.ndarray, label: str, checks: bool = True) -> dict:
        ev_min = float(np.linalg.eigvalsh(s66).min())
        if ev_min <= 0.0:
            return {"positive_definite": False, "compliance_min_eigenvalue": ev_min}
        cm4 = to4(np.linalg.inv(s66))
        s_esh = eshelby_cylinder(cm4)
        entry = {"positive_definite": True, "compliance_min_eigenvalue": ev_min}
        if checks:
            hole = control_orthotropic_hole(s66, s_esh, cm4)
            assert abs(hole["kt_eshelby"] / hole["kt_lekhnitskii"] - 1) < 1e-10 and hole["traction_residual"] < 1e-10, \
                f"orthotropic hole control failed on {label}: {hole}"
            cov = control_covariance(cm4, s_esh)
            assert cov < 1e-10, f"S is not covariant under a rotation about its axis on {label}: {cov}"
            quad = float(np.abs(mandel(eshelby_cylinder(cm4, 2 * N_QUAD)) - mandel(s_esh)).max())
            assert quad < 1e-10, f"Mura's integral not converged at {N_QUAD} points on {label}: {quad}"
            entry |= {"hole_control": hole, "covariance_control": cov, "quadrature_change_at_2n": quad}
        sig = np.zeros((3, 3))
        sig[0, 0] = 1.0
        cm = mandel(cm4)
        return entry | {"_cm": cm, "_s": mandel(s_esh), "_eps": np.linalg.solve(cm, strain_vec(sig))}

    wood = {f"{g}|{rd}": build_reading(wood_compliance(w, rd), f"{g}|{rd}") for g, w in WOOD.items() for rd in READINGS}
    live = [k for k, v in wood.items() if v["positive_definite"]]
    excluded = [k for k, v in wood.items() if not v["positive_definite"]]
    wood_green = {f"{n}|{rd}": build_reading(wood_compliance(gs["w"], rd), f"{n}|{rd}")
                  for n, gs in gsets.items() for rd in gs["readings"]}
    live_green = [k for k, v in wood_green.items() if v["positive_definite"]]
    excluded_green = [k for k, v in wood_green.items() if not v["positive_definite"]]
    assert not wood.keys() & wood_green.keys(), "a green reading's key collides with a Scots pine one"
    allw = wood | wood_green                                         # disjoint keys: one lookup for both groups

    # ── t_L over every cell ───────────────────────────────────────────────────────────────────────────────────────────
    ti_phase = {al: mandel(iso_c(p_["E_GPa"] * 1e3, p_["nu"])) for al, p_ in ALLOY_PROPERTIES.items()}

    def c_incl(wv: dict, al: str, fill: str, th: float, a: float) -> np.ndarray:
        e_s = ALLOY_PROPERTIES[al]["E_GPa"] * 1e3
        if fill == "pores_voigt_phase_bound":
            return phi * ti_phase[al] + (1 - phi) * wv["_cm"]
        base, shear = parts[th] if th in parts else cubic_parts(lat["C11"], lat["C12"], math.radians(th))
        ci = e_s * (base + a * q_lat / 2 * shear)
        return ci + (1 - phi) * wv["_cm"] if fill == "pores_additive_host_sapwood" else ci

    def t_l_on(wv: dict, al, fill, th, a) -> float:
        return float(inclusion_strain(wv["_cm"], c_incl(wv, al, fill, th, a), wv["_s"], wv["_eps"])[0] / wv["_eps"][0])

    def t_l(wk, al, fill, th, a) -> float:
        return t_l_on(allw[wk], al, fill, th, a)

    def a_cross(wk, al, fill, th) -> float | None:
        lo, hi = A_FLOOR * a_voigt, a_voigt
        f_lo, f_hi = t_l(wk, al, fill, th, lo) - 1, t_l(wk, al, fill, th, hi) - 1
        if f_lo * f_hi > 0:
            return None
        for _ in range(80):
            mid = math.sqrt(lo * hi)
            if (t_l(wk, al, fill, th, mid) - 1) * f_lo > 0:
                lo = mid
            else:
                hi = mid
        return math.sqrt(lo * hi)

    def sweep(keys: list[str]) -> tuple[dict, dict, float, float]:
        cells_, grids_, monotone_, mirror_ = {}, {}, 0.0, 0.0
        for al in ALLOY_PROPERTIES:
            for wk in keys:
                for fill in FILLS:
                    grid = np.array([[t_l(wk, al, fill, th, a) for a in a_grid] for th in THETA_DEG])
                    grids_[(al, wk, fill)] = grid
                    monotone_ = max(monotone_, float(np.diff(grid, axis=1).max()))
                    at_av = grid[:, -1]
                    at_zero = np.array([t_l(wk, al, fill, th, 0.0) for th in THETA_DEG])
                    i_min, i_zero = int(np.argmin(at_av)), int(np.argmax(at_zero))
                    cells_[f"{al}|{wk}|{fill}"] = {
                        "t_L_theta0_any_C44": float(grid[0, -1]),
                        "t_L_at_voigt_C44_min_over_theta": float(at_av[i_min]), "theta_of_min_deg": THETA_DEG[i_min],
                        "t_L_at_voigt_C44_max_over_theta": float(at_av.max()),
                        "t_L_at_C44_zero_max_over_theta": float(at_zero[i_zero]),
                        "theta_of_max_at_C44_zero_deg": THETA_DEG[i_zero],
                        "zener_at_which_t_L_is_1_theta45": a_cross(wk, al, fill, 45.0),
                        "theta0_independent_of_C44": bool(np.ptp(grid[0]) < 1e-9),
                    }
                    monotone_ = max(monotone_, float((grid[:, 0] - at_zero).max()))   # C44 = 0 tops the grid
            # the mirror control: t_L(45° + x) = t_L(45° − x) — cubic 90° periodicity with the matrix's T → −T mirror. It
            # guards the PERIMETER claim (0–45° covers every install angle); it holds for any proper rotation, so it does
            # not catch a wrong angle (the E110 closed form at 45° below does), and a non-rotation reds the monotone check.
            for x in (10.0, 30.0):
                for a in (a_grid[0], a_grid[-1]):
                    vals = [t_l(keys[0], al, "pores_carry_nothing", th, a) for th in (45 + x, 45 - x)]
                    mirror_ = max(mirror_, abs(vals[0] - vals[1]))
        assert monotone_ < 1e-9, f"t_L rises with C44 somewhere ({monotone_}) — the threshold form is void"
        assert mirror_ < 1e-9, f"the 45° mirror does not hold ({mirror_}) — the rotation is wrong"
        return cells_, grids_, monotone_, mirror_

    cells, grids, monotone_worst, mirror_worst = sweep(live)
    cells_green, _, monotone_green, mirror_green = sweep(live_green)

    # ── Do the pore readings' stiffness ends bracket the SHARE? Count the additive reading outside the ends' interval ──
    def additive_outside(cells_: dict, keys: list[str]) -> list[str]:
        out = []
        for al, wk in itertools.product(ALLOY_PROPERTIES, keys):
            ends = [cells_[f"{al}|{wk}|{f}"] for f in ("pores_carry_nothing", "pores_voigt_phase_bound")]
            mid = cells_[f"{al}|{wk}|pores_additive_host_sapwood"]
            for field in ("t_L_theta0_any_C44", "t_L_at_voigt_C44_min_over_theta"):
                lo, hi = sorted(e[field] for e in ends)
                if not lo - 1e-12 <= mid[field] <= hi + 1e-12:
                    out.append(f"{al}|{wk}|{field}")
        return out

    outside = additive_outside(cells, live)
    outside_green = additive_outside(cells_green, live_green)

    # ── Moisture: across each reading's material groups, how many grid points fall, rise, or neither? ──────────────────
    moisture = {}
    for rd in READINGS:
        ks = [f"{g}|{rd}" for g in GROUPS if f"{g}|{rd}" in live]
        counts = {"groups": [k.split("|")[0] for k in ks], "falling": 0, "rising": 0, "neither": 0, "points": 0}
        for al in ALLOY_PROPERTIES:
            for fill in FILLS:
                steps = np.diff(np.stack([grids[(al, k, fill)] for k in ks]), axis=0)
                fall, rise = np.all(steps < 0, axis=0), np.all(steps > 0, axis=0)
                counts["falling"] += int(fall.sum())
                counts["rising"] += int(rise.sum())
                counts["neither"] += int((~fall & ~rise).sum())
                counts["points"] += fall.size
        moisture[rd] = counts

    # ── For 105 at θ = 0: E_z* = E[100] and t_L both free of C44 — one cell, one tensor ───────────────────────────────
    f_read = {"axial_reading": s105.rms_factor(r_a, phi), "radial_reading": s105.rms_factor(r_r, phi)}
    for al in ALLOY_PROPERTIES:                                    # 105's cached cells, reproduced with its own formula
        lim0 = d105["alloys"][al]["endurance_strain_printed_ue"]
        for dk, frac in d105["inputs"]["depth_fraction"].items():
            for sk, div in d105["inputs"]["stress_state_divisor"].items():
                for sf in (1.0, 2.0):
                    for fk, fv in f_read.items():
                        assert up0(lim0 / sf * div / (fv * frac)) == \
                            d105["gyroid_binds_above_surface_strain_ue"][al][f"{dk}|{sk}|sf{sf:g}"][fk], \
                            f"105's threshold not reproduced ({al} {dk} {sk} sf{sf} {fk}) — re-run 105"
    def theta0_over(cells_: dict) -> dict:
        out = {}
        for al in ALLOY_PROPERTIES:
            ks = [k for k in cells_ if k.startswith(f"{al}|")]
            k_lo = min(ks, key=lambda k: cells_[k]["t_L_theta0_any_C44"])
            k_hi = max(ks, key=lambda k: cells_[k]["t_L_theta0_any_C44"])
            out[al] = {"lowest": cells_[k_lo]["t_L_theta0_any_C44"], "lowest_cell": k_lo,
                       "highest": cells_[k_hi]["t_L_theta0_any_C44"], "highest_cell": k_hi}
        return out

    def binds_at(t0: dict) -> dict:
        return {fk: {al: {f"{dk}|{sk}|sf{sf:g}": up0(d105["alloys"][al]["endurance_strain_printed_ue"] / sf * div
                                                     / (fv * frac * t0[al]["lowest"]))
                          for dk, frac in d105["inputs"]["depth_fraction"].items()
                          for sk, div in d105["inputs"]["stress_state_divisor"].items() for sf in (1.0, 2.0)}
                     for al in ALLOY_PROPERTIES}
                for fk, fv in f_read.items()}

    stem = d105["inputs"]["stem_readings_87"]

    def source_day_at(ba: dict) -> dict:
        return {fk: {rd: {"exceeds": sorted(al for al in ALLOY_PROPERTIES
                                            if stem[rd]["surface_strain_ue"] > ba[fk][al][CELL_LS]),
                          "margin_over_threshold": {al: stem[rd]["surface_strain_ue"] / ba[fk][al][CELL_LS]
                                                    for al in ALLOY_PROPERTIES}}
                     for rd in ("median", "upper_whisker")}
                for fk in f_read}

    theta0 = theta0_over(cells)
    binds_above = binds_at(theta0)
    merit = {al: binds_above["axial_reading"][al][CELL_LS] / binds_above["axial_reading"][ALLOY_BASELINE][CELL_LS]
             for al in ALLOY_PROPERTIES}
    source_day = source_day_at(binds_above)
    # the green group alone and the union of both — the consumer's ceiling for a BINDING sentence is the union's lowest
    # θ = 0 share (the adverse reading for a lower bound's «binds», in-silico §When Modifying #45 ⊕ and #11), cited
    theta0_green = theta0_over(cells_green)
    cells_union = cells | cells_green
    theta0_union = theta0_over(cells_union)
    binds_union = binds_at(theta0_union)
    source_day_union = source_day_at(binds_union)
    # at t_L = 1 on EACH of 105's readings (the binding one is its lower — read from its cache below, never assumed)
    at_t1 = {fk: {rd: sorted(al for al in ALLOY_PROPERTIES
                             if stem[rd]["surface_strain_ue"] > d105["gyroid_binds_above_surface_strain_ue"][al][CELL_LS][fk])
                  for rd in ("median", "upper_whisker")}
             for fk in ("axial_reading", "radial_reading")}

    # ── Off the axis: the lattice's own E_z*(45°) and the threshold factor √(r_a/E_z*)/t_L at the C44 grid's ends ───────
    s11 = (lat["C11"] + lat["C12"]) / ((lat["C11"] - lat["C12"]) * (lat["C11"] + 2 * lat["C12"]))
    s12 = -lat["C12"] / ((lat["C11"] - lat["C12"]) * (lat["C11"] + 2 * lat["C12"]))
    ez45 = {}
    for fk, reading in (("radial_reading", r_r), ("axial_reading", r_a)):
        need = 1.0 / reading - (s11 + s12) / 2                         # 1/E110 = (s11 + s12)/2 + 1/(4·C44)
        a_needed = (2.0 * (1.0 / (4.0 * need)) / q_lat) if need > 0 else 0.0
        ez45[fk] = {"zener_below_which_E110_falls_under_reading": a_needed}

    def e110(a: float) -> float:
        base, shear = parts[45.0]
        e_num = 1.0 / np.linalg.inv(base + a * q_lat / 2 * shear)[0, 0]
        e_closed = 1.0 / ((s11 + s12) / 2 + 1.0 / (4.0 * a * q_lat / 2))
        assert abs(e_num / e_closed - 1) < 1e-10, "the off-axis modulus disagrees with the cubic closed form"
        return e_closed

    ez45["E110_over_E_s_at_grid_floor"] = e110(a_grid[0])
    ez45["E110_over_E_s_at_voigt_ceiling"] = e110(a_voigt)
    off_axis = {}
    for al in ALLOY_PROPERTIES:
        off_axis[al] = {label: {"threshold_factor_min": min(facs), "threshold_factor_max": max(facs)}
                        for a, label in ((a_grid[0], "at_grid_floor"), (a_voigt, "at_voigt_ceiling"))
                        for facs in [[math.sqrt(r_a / e110(a)) / t_l(wk, al, fill, 45.0, a)
                                      for wk in live for fill in FILLS]]}

    # the install angle at a KNOWN C44: the ligaments' stress factor √(E_z*(θ))·t_L(θ) — its minimum RAISES their
    # threshold — per pore reading, on one probe cell (the baseline alloy, 95 % RH, stiffer-axis reading)
    def e_z(th: float, a: float) -> float:
        base, shear = parts[th]
        return float(1.0 / np.linalg.inv(base + a * q_lat / 2 * shear)[0, 0])

    angle_probe = {}
    for frac_c in (1.0, 0.3):
        a = frac_c * a_voigt
        angle_probe[f"zener_{frac_c:g}_of_ceiling"] = {
            fill: THETA_DEG[int(np.argmin([math.sqrt(e_z(th, a)) * t_l("rh95|stiff", ALLOY_BASELINE, fill, th, a)
                                           for th in THETA_DEG]))] for fill in FILLS}

    junction_sup = max(v["t_L_at_C44_zero_max_over_theta"] for v in cells.values())
    rh95 = [k for k in cells if "|rh95|" in k]
    crossings = sum(1 for k in cells if cells[k]["zener_at_which_t_L_is_1_theta45"] is not None)
    lattice_cells = sum(1 for k in cells if k.rsplit("|", 1)[1] in LATTICE_FILLS)
    lows = ", ".join(f"{al} {floor_to(theta0[al]['lowest'], 3):.3f}" for al in ALLOY_PROPERTIES)
    sd_a, sd_r = source_day["axial_reading"], source_day["radial_reading"]

    # ── Control: t_L does not depend on G_LR or G_RT. R is a symmetry axis of the matrix and of every inclusion reading,
    # so the anti-plane shears (LR, TR) decouple from the normal-and-LT block that σ_L excites. CAN catch: an index slip
    # in to4 / mandel / rotate that couples the anti-plane block in, a rotation about an axis other than R. CANNOT catch:
    # an error in G_LT or in the normal block — they do enter (the hole control holds the normal block).
    def constants(wk: str) -> tuple[dict, str]:
        name, rd = wk.split("|")
        return (WOOD[name] if name in WOOD else gsets[name]["w"]), rd

    g_probe_worst = 0.0
    for wk in [*live, *live_green]:
        w, rd = constants(wk)
        for key, f in itertools.product(("G_LR", "G_RT"), G_PROBE_FACTORS):
            wv2 = build_reading(wood_compliance(w | {key: w[key] * f}, rd), f"{wk} {key}×{f:g}", checks=False)
            for al, fill, th, a in itertools.product(ALLOY_PROPERTIES, FILLS, (0.0, 22.5, 45.0), (a_grid[0], a_voigt, 0.0)):
                g_probe_worst = max(g_probe_worst, abs(t_l_on(wv2, al, fill, th, a) - t_l(wk, al, fill, th, a)))
    assert g_probe_worst < 1e-12, f"t_L moves with G_LR or G_RT ({g_probe_worst}) — the anti-plane block leaks in"

    # ── Control: Jeong's borrowed ν_RT, swept over every MEASURED ν_RT of the named readings and Jeong's own red pine at
    # 6 and 19 % MC. |Δt_L| at θ = 0 — the only cell `105`'s figure stands on — is held to NU_RT_SENSITIVITY_CAP; off the
    # axis (every θ, at the C44 grid's ends and at C44 = 0) it is reported, not capped. CAN catch: a θ = 0 share that leans
    # on the borrowed value. CANNOT catch: a ν_RT outside the swept span (the measured green 3.20 is inadmissible by the
    # author's account).
    nu_rt_measured = sorted({w["nu_RT"] for w in WOOD.values()} | {float(v) for v in DAVIES_TABLE2["nu_RT"]}
                            | {float(v) for v in DAVIES_ESM3_COMPRESSION["rt_c"]} | {liu_row("4")["nu_RT"]}
                            | {float(JEONG_TABLE2_RED_PINE[r][JEONG_TABLE2_HEADER.index("nu_RT")]) for r in ("6", "19")}
                            | {jeong_korean_pine_green()["nu_RT"]})
    jk = "jeong2026_red_pine_green|stiff"
    nu_rt_theta0, nu_rt_off_axis = 0.0, 0.0
    for nu in np.linspace(nu_rt_measured[0], nu_rt_measured[-1], NU_RT_SWEEP_POINTS):
        wv2 = build_reading(wood_compliance(jeong_red_pine_green(float(nu)), "stiff"), f"ν_RT {nu:.3f}", checks=False)
        assert wv2["positive_definite"], f"Jeong's set is not a material at ν_RT {nu}"
        for al, fill in itertools.product(ALLOY_PROPERTIES, FILLS):
            nu_rt_theta0 = max(nu_rt_theta0, abs(t_l_on(wv2, al, fill, 0.0, a_voigt) - t_l(jk, al, fill, 0.0, a_voigt)))
            for th, a in itertools.product(THETA_DEG, (a_grid[0], a_voigt, 0.0)):
                nu_rt_off_axis = max(nu_rt_off_axis, abs(t_l_on(wv2, al, fill, th, a) - t_l(jk, al, fill, th, a)))
    assert nu_rt_theta0 <= NU_RT_SENSITIVITY_CAP, f"the θ = 0 share leans on the borrowed ν_RT: {nu_rt_theta0}"

    # ── Our arithmetic on the green sources: reciprocity, Davies Table 2 against its raw means, shear against Liu ────────
    recip = {g: reciprocity(w) for g, w in WOOD.items()} | {n: reciprocity(gs["w"]) for n, gs in gsets.items()}
    measured_sets = [*WOOD, *(n for n in gsets if n.startswith("davies2016_esm_") or n == "liu2019_P4")]
    l_pairs = [recip[s][k] for s in measured_sets for k in ("RL_over_LR", "TL_over_LT")]
    rt_pair = [recip[s]["RT_over_TR"] for s in measured_sets]
    t2_pairs = [v for n in gsets if n.startswith("davies2016_table2_") for v in recip[n].values()]
    t2_vs_esm = {k: [gsets[f"davies2016_table2_{c}"]["w"][k] / gsets[f"davies2016_esm_{c}"]["w"][k] for c in DAVIES_COLUMNS]
                 for k in ("E_L", "E_R", "E_T", "nu_LR", "nu_LT", "nu_RT", "nu_RL", "nu_TL", "nu_TR")}
    liu_rows = [liu_row(r) for r in ("1", "2", "3", "4")]
    davies_g = {k: [gs["w"][k] for n, gs in gsets.items() if n.startswith("davies2016_")] for k in ("G_LR", "G_RT", "G_LT")}
    shear_below_liu = {k: [min(r[k] for r in liu_rows) / max(v), max(r[k] for r in liu_rows) / min(v)]
                       for k, v in davies_g.items()}

    # ── The union: the junction's adverse end (the HIGHEST share) and the binding claim's (the LOWEST), cited ────────────
    junction_sup_green = max(v["t_L_at_C44_zero_max_over_theta"] for v in cells_green.values())
    crossings_green = sum(1 for v in cells_green.values() if v["zener_at_which_t_L_is_1_theta45"] is not None)
    lattice_cells_green = sum(1 for k in cells_green if k.rsplit("|", 1)[1] in LATTICE_FILLS)
    junction_union_cell = max(cells_union, key=lambda k: cells_union[k]["t_L_at_C44_zero_max_over_theta"])
    jeong_c44_zero = max(v["t_L_at_C44_zero_max_over_theta"] for k, v in cells_green.items() if f"|{jk}|" in k)
    assert jeong_c44_zero + nu_rt_off_axis < cells_union[junction_union_cell]["t_L_at_C44_zero_max_over_theta"], \
        "the union's junction supremum is within reach of Jeong's borrowed ν_RT — it no longer stands on measured sets"
    # beside it (⚖️ founder 2026-10-22, 00_07 HW.23): the same supremum on the published green sets alone — Davies' Table 2,
    # Liu and Jeong — without OUR assembly of Davies' raw ESM 2/3 means, on which the union's supremum sits
    published = {k: v for k, v in cells_green.items() if not k.split("|")[1].startswith("davies2016_esm_")}
    junction_pub_cell = max(published, key=lambda k: published[k]["t_L_at_C44_zero_max_over_theta"])
    junction_pub = {"share": published[junction_pub_cell]["t_L_at_C44_zero_max_over_theta"],
                    "theta_deg": published[junction_pub_cell]["theta_of_max_at_C44_zero_deg"],
                    "cell": junction_pub_cell, "stands_on_borrowed_nu_RT": f"|{jk}|" in junction_pub_cell,
                    "over": "the green group without Davies' raw ESM 2/3 means (our assembly): Davies' Table 2 · Liu P4 · "
                            "Jeong's red and Korean pine"}
    # the published-only supremum is printed as an «up to» figure too, so it carries the same guard as the union's above
    assert jeong_c44_zero + nu_rt_off_axis < junction_pub["share"], \
        "the published-only junction supremum is within reach of Jeong's borrowed ν_RT — it no longer stands on measured sets"
    # the union without Davies' Table 2 — the optimiser's output out, measured means only (the submission's option (В))
    t0_measured = theta0_over({k: v for k, v in cells_union.items() if "|davies2016_table2_" not in k})
    sd_measured = source_day_at(binds_at(t0_measured))
    union_without_table2 = {
        "lowest": {al: t0_measured[al]["lowest"] for al in ALLOY_PROPERTIES},
        "lowest_cell": {al: t0_measured[al]["lowest_cell"] for al in ALLOY_PROPERTIES},
        "source_day_upper_whisker_exceeds": {fk: sd_measured[fk]["upper_whisker"]["exceeds"] for fk in f_read},
        "ta_upper_whisker_margin": {fk: sd_measured[fk]["upper_whisker"]["margin_over_threshold"]["Ta"] for fk in f_read}}
    # each named green set on its own: its lowest θ = 0 share and the source day's verdict there (the bracket's price)
    per_set = {}
    for n in gsets:
        sub = {k: v for k, v in cells_green.items() if k.split("|")[1] == n}
        if sub:
            t0n = theta0_over(sub)
            ban = binds_at(t0n)
            sdn = source_day_at(ban)
            per_set[n] = {"lowest": {al: t0n[al]["lowest"] for al in ALLOY_PROPERTIES},
                          "lowest_cell": {al: t0n[al]["lowest_cell"] for al in ALLOY_PROPERTIES},
                          "source_day_upper_whisker_exceeds": {fk: sdn[fk]["upper_whisker"]["exceeds"] for fk in f_read},
                          "ta_upper_whisker_margin": {fk: sdn[fk]["upper_whisker"]["margin_over_threshold"]["Ta"]
                                                      for fk in f_read},
                          # the stem strain at which each alloy flips on this set, per FE reading (in-silico §When
                          # Modifying #40) — the large-stem SF 2 threshold at the set's own lowest share
                          "upper_whisker_flips_above_ue": {fk: {al: ban[fk][al][CELL_LS] for al in ALLOY_PROPERTIES}
                                                           for fk in f_read}}

    # Korean pine's Ta verdict against its own ν_LR (printed 0.30 at a CV of 1.64): the source day's upper whisker over Ta's
    # threshold at that set's lowest θ = 0 share, as a function of ν_LR alone — the ν_LR at which it first exceeds, per FE
    # reading (bisection on a bracket whose ends are asserted; the margin is held non-decreasing on a coarse scan)
    kp = "jeong2026_korean_pine_green"

    def kp_ta_margin(nu_lr: float, fk: str) -> float:
        wv2 = build_reading(wood_compliance(gsets[kp]["w"] | {"nu_LR": nu_lr}, "stiff"), f"{kp} ν_LR {nu_lr}", checks=False)
        assert wv2["positive_definite"], f"Korean pine is not a material at ν_LR {nu_lr}"
        t_low = min(t_l_on(wv2, "Ta", fill, 0.0, a_voigt) for fill in FILLS)
        dk, sk, _ = CELL_LS.split("|")
        thr = up0(d105["alloys"]["Ta"]["endurance_strain_printed_ue"] / 2.0 * d105["inputs"]["stress_state_divisor"][sk]
                  / (f_read[fk] * d105["inputs"]["depth_fraction"][dk] * t_low))
        return stem["upper_whisker"]["surface_strain_ue"] / thr

    kp_nu = gsets[kp]["w"]["nu_LR"]
    kp_edge = {}
    for fk in f_read:
        assert abs(kp_ta_margin(kp_nu, fk) - per_set[kp]["ta_upper_whisker_margin"][fk]) < 1e-12, "Korean pine's margin moved"
        scan = [kp_ta_margin(x, fk) for x in np.linspace(kp_nu, 2 * kp_nu, 11)]
        assert all(b >= a for a, b in itertools.pairwise(scan)), f"Korean pine's Ta margin is not monotone in ν_LR ({fk})"
        lo, hi = kp_nu, 2 * kp_nu
        if scan[0] > 1 or scan[-1] <= 1:
            kp_edge[fk] = {"margin_at_printed": scan[0], "nu_LR_first_exceeds": None, "scanned_to": hi}
            continue
        for _ in range(50):
            mid = 0.5 * (lo + hi)
            lo, hi = (mid, hi) if kp_ta_margin(mid, fk) <= 1 else (lo, mid)
        kp_edge[fk] = {"margin_at_printed": scan[0], "nu_LR_first_exceeds": hi, "scanned_to": 2 * kp_nu}
    kp_edge_record = {"nu_LR_printed": kp_nu, "nu_LR_cv_printed": float(JEONG_KOREAN_PINE_GREEN_CV["nu_LR"]),
                      "per_fe_reading": kp_edge,
                      "is": "the ν_LR above which the source day's upper whisker exceeds Ta's large-stem SF 2 threshold "
                            "at Korean pine's own lowest θ = 0 share, every other constant as printed (G_RT borrowed)"}

    def citation(cell_key: str) -> str:
        _, name, rd, fill = cell_key.split("|")
        if name in gsets:
            src = GREEN_SOURCES[gsets[name]["source"]]
            return f"{src['citation']}, doi {src['doi']}, {gsets[name]['where']}; {rd} reading, {fill}"
        return f"Güntekin & Akar 2019, doi 10.12841/wood.1644-3985.220.09, group {name}; {rd} reading, {fill}"

    ceiling = {
        "rule": "a lower bound shows «binds», never «safe»: a binding sentence takes the LOWEST θ = 0 share of the named "
                "readings (the highest threshold), cited; the Scots pine group's threshold is printed beside it as the "
                "price of that choice (in-silico §When Modifying #11 and #45 ⊕)",
        "reading_per_alloy": {al: citation(theta0_union[al]["lowest_cell"]) for al in ALLOY_PROPERTIES},
        "binds_above_ue_large_stem_sf2": {fk: {al: binds_union[fk][al][CELL_LS] for al in ALLOY_PROPERTIES} for fk in f_read},
        "source_day_upper_whisker_exceeds": {fk: source_day_union[fk]["upper_whisker"]["exceeds"] for fk in f_read},
        "price_scots_pine_group": {
            "binds_above_ue_large_stem_sf2": {fk: {al: binds_above[fk][al][CELL_LS] for al in ALLOY_PROPERTIES}
                                              for fk in f_read},
            "source_day_upper_whisker_exceeds": {fk: source_day[fk]["upper_whisker"]["exceeds"] for fk in f_read}},
    }
    lows_g = ", ".join(f"{al} {floor_to(theta0_green[al]['lowest'], 3):.3f}" for al in ALLOY_PROPERTIES)
    lows_u = ", ".join(f"{al} {floor_to(theta0_union[al]['lowest'], 3):.3f}" for al in ALLOY_PROPERTIES)
    u_where = "; and ".join(citation(f"-|{c}") for c in sorted({theta0_union[al]["lowest_cell"].split("|", 1)[1]
                                                                for al in ALLOY_PROPERTIES}))
    hi_green = sorted(al for al in ALLOY_PROPERTIES if theta0_union[al]["highest_cell"] not in cells)
    hi_phrase = (f"a green reading sets it for {', '.join(hi_green)}" if hi_green
                 else "no green reading raises the Scots pine group's for any alloy")
    su_a, su_r = source_day_union["axial_reading"], source_day_union["radial_reading"]
    # which reading 105's binding rule takes is READ from its cache, never assumed (the radial one since the HW.23
    # re-sweep of 2026-10-23; on the HW.33 (в) geometry's two-point readings the two had coincided within the
    # extrapolation — 00_07 HW.23)
    # ── The measured C44 (00_07 HW.23): the periodic voxel case's tensor of the INFINITE lattice (01_01 §5.2) ──────────
    # The part body has no C44 of its own, so a measured one enters it as an ASSUMPTION, and its FORM is a reading: the
    # absolute modulus C44/E_s ⊥ the Zener ratio A = 2·C44/(C11 − C12) carried onto the body's own C11 − C12. Beside both,
    # the material read whole — the periodic C11, C12, C44 on its own solid fraction — so that one cell gives the share and
    # E_z* of ONE tensor (in-silico §When Modifying #45 (b)). Each rung of the part's density is its own tensor; the ladder
    # is quoted as a ladder, never a row (01_01 §5.2, ceiling (2)), and a binding figure takes its adverse rung (#11).
    per = json.loads(PERIODIC.read_text(encoding="utf-8"))
    assert per["boundary_condition"] == "periodic" and abs(per["poisson_ratio"] - nu_s) < 1e-12, \
        "the periodic case is not on the part's solid — re-read it"
    rungs = [r for r in per["rows"] if abs(r["porosity"] - (1.0 - phi)) <= PERIODIC_DENSITY_TOL]
    assert tuple(r["steps_per_period"] for r in rungs) == PERIODIC_RUNGS, \
        f"the rungs of the part's density moved: {[r['steps_per_period'] for r in rungs]}"
    assert all(r["converged"] is True and r["discarded_island_fraction"] == 0 for r in rungs), "a rung is not a solve"
    forms = {}
    for r in rungs:
        st = r["steps_per_period"]
        forms[("part_body_C44_absolute", st)] = (lat["C11"], lat["C12"], r["C44"], phi)
        forms[("part_body_zener", st)] = (lat["C11"], lat["C12"], r["zener"] * q_lat / 2, phi)
        forms[("material_tensor", st)] = (r["C11"], r["C12"], r["C44"], r["solid_fraction_meshed"])
    for (fm, st), (c11, c12, c44, ph) in forms.items():
        assert 0 < c44 <= ph * mu_s and c11 > abs(c12) and c11 + 2 * c12 > 0, f"{fm} /{st}: not an admissible cubic body"
    fparts = {key: (parts if key[0] != "material_tensor"
                    else {th: cubic_parts(v[0], v[1], math.radians(th)) for th in THETA_DEG}) for key, v in forms.items()}

    def e_dir(c11: float, c12: float, c44: float, th: float) -> float:
        """Uniaxial-stress modulus along L of a cubic body whose [100] lies θ off L in its (001) plane, units of E_s."""
        d = (c11 - c12) * (c11 + 2 * c12)
        s11, s12 = (c11 + c12) / d, -c12 / d
        cs = math.cos(math.radians(th)) * math.sin(math.radians(th))
        return 1.0 / (s11 - 2 * (s11 - s12 - 1.0 / (2 * c44)) * cs * cs)

    # Control: the closed form against the numeric inverse of the rotated tensor on every form, at three angles. CAN
    # catch: a slip in e_dir, or in a form's rotated parts (the material forms build their own). CANNOT catch: an error
    # common to cubic_parts and the closed form (the E110 check above ties them at 45° on the part body only).
    e_dir_worst = max(abs(e_dir(*forms[key][:3], th)
                          * np.linalg.inv(fparts[key][th][0] + forms[key][2] * fparts[key][th][1])[0, 0] - 1)
                      for key in forms for th in (0.0, 22.5, 45.0))
    assert e_dir_worst < 1e-10, f"the off-axis modulus closed form disagrees with the tensor: {e_dir_worst}"

    def t_l_form(wk: str, al: str, fill: str, key: tuple, th: float) -> float:
        wv = allw[wk]
        c44, ph = forms[key][2], forms[key][3]
        if fill == "pores_voigt_phase_bound":
            ci = ph * ti_phase[al] + (1 - ph) * wv["_cm"]
        else:
            base, shear = fparts[key][th]
            ci = ALLOY_PROPERTIES[al]["E_GPa"] * 1e3 * (base + c44 * shear)
            if fill == "pores_additive_host_sapwood":
                ci = ci + (1 - ph) * wv["_cm"]
        return float(inclusion_strain(wv["_cm"], ci, wv["_s"], wv["_eps"])[0] / wv["_eps"][0])

    # Control: on the part body the Zener form IS a point of the sweep, so the two paths must agree. CAN catch: a slip in
    # how t_l_form composes the lattice, the pores or φ. CANNOT catch: an error the sweep shares (the closed-form
    # controls above hold that).
    zkey = ("part_body_zener", PERIODIC_RUNGS[-1])
    form_vs_sweep = max(abs(t_l_form(live[0], al, fill, zkey, th) - t_l(live[0], al, fill, th, rungs[-1]["zener"]))
                        for al in ALLOY_PROPERTIES for fill in FILLS for th in (0.0, 22.5, 45.0))
    assert form_vs_sweep < 1e-12, f"the measured-C44 path disagrees with the sweep at the same Zener ratio: {form_vs_sweep}"

    dk_ls, sk_ls, sf_ls = CELL_LS.split("|")
    sf_ls = float(sf_ls[2:])

    def thr_ls(al: str, t: float, ez: float, ph: float) -> float:
        """105's headline threshold (large stem, near-uniaxial, SF 2) for one cell's share and modulus, unrounded."""
        return (d105["alloys"][al]["endurance_strain_printed_ue"] / sf_ls * d105["inputs"]["stress_state_divisor"][sk_ls]
                / (s105.rms_factor(ez, ph) * d105["inputs"]["depth_fraction"][dk_ls] * t))

    union_keys = [*live, *live_green]
    t_form = {}                                      # (form, rung) → {(al, wk, fill): share over THETA_DEG}
    for key in forms:
        t_form[key] = {(al, wk, fill): [t_l_form(wk, al, fill, key, th) for th in THETA_DEG]
                       for al in ALLOY_PROPERTIES for wk in union_keys for fill in FILLS}
        assert min(min(v) for v in t_form[key].values()) > 0, f"a non-positive share on {key}"

    def measured(keys: list[str]) -> dict:
        out = {}
        for fm in C44_FORMS:
            per_rung = {}
            for st in PERIODIC_RUNGS:
                c11, c12, c44, ph = forms[(fm, st)]
                ez = [e_dir(c11, c12, c44, th) for th in THETA_DEG]
                tab = {k: v for k, v in t_form[(fm, st)].items() if k[1] in keys}
                alloys = {}
                for al in ALLOY_PROPERTIES:
                    cand = [(thr_ls(al, ts[i], ez[i], ph), f"{al}|{wk}|{fill}", THETA_DEG[i], fill)
                            for (a_, wk, fill), ts in tab.items() if a_ == al for i in range(len(THETA_DEG))]
                    at0, free = max(c for c in cand if c[2] == 0.0), max(cand)
                    lat0 = max(c for c in cand if c[2] == 0.0 and c[3] in LATTICE_FILLS)
                    latf = max(c for c in cand if c[3] in LATTICE_FILLS)
                    alloys[al] = {"binds_above_theta0_ue": up0(at0[0]), "theta0_cell": at0[1],
                                  "binds_above_theta_free_ue": up0(free[0]), "theta_free_cell": free[1],
                                  "theta_free_deg": free[2],
                                  # the cells C44 enters alone — what the lattice's own off-axis stiffness does
                                  "lattice_fills_binds_above_theta0_ue": up0(lat0[0]),
                                  "lattice_fills_binds_above_theta_free_ue": up0(latf[0]),
                                  "lattice_fills_theta_free_cell": latf[1], "lattice_fills_theta_free_deg": latf[2]}
                probe = {fill: THETA_DEG[int(np.argmin([math.sqrt(ez[i]) * t_form[(fm, st)][(ALLOY_BASELINE, "rh95|stiff",
                                                                                              fill)][i]
                                                        for i in range(len(THETA_DEG))]))] for fill in FILLS}
                sup_k = max(tab, key=lambda k: max(tab[k]))
                lat_cells = [ts[-1] for k, ts in tab.items() if k[2] in LATTICE_FILLS]
                per_rung[str(st)] = {
                    "C11_over_E_s": c11, "C12_over_E_s": c12, "C44_over_E_s": c44, "zener": 2 * c44 / (c11 - c12),
                    "solid_fraction": ph, "C44_over_voigt_ceiling": c44 / (ph * mu_s),
                    "E_z_star_theta0": ez[0], "E_z_star_theta45": ez[-1], "alloys": alloys,
                    "t_L_theta45_lattice_cells_above_1": sum(1 for x in lat_cells if x > 1),
                    "t_L_theta45_lattice_cells_below_1": sum(1 for x in lat_cells if x < 1),
                    "junction_share_sup": max(tab[sup_k]), "junction_share_sup_cell": "|".join(sup_k),
                    "junction_share_sup_theta_deg": THETA_DEG[int(np.argmax(tab[sup_k]))],
                    "ligament_factor_argmin_theta_deg_baseline_rh95_stiff": probe}
            out[fm] = per_rung
        return out

    meas_scots, meas_union = measured(live), measured(union_keys)
    # control: on the part body θ = 0 is free of C44, so the measured forms must give 105's θ = 0 figure exactly
    for fm in ("part_body_C44_absolute", "part_body_zener"):
        for st in PERIODIC_RUNGS:
            for al in ALLOY_PROPERTIES:
                assert meas_scots[fm][str(st)]["alloys"][al]["binds_above_theta0_ue"] == \
                    binds_above["axial_reading"][al][CELL_LS], f"θ = 0 on the part body moved with C44 ({fm} /{st} {al})"

    def bracket(m: dict, field: str) -> dict:
        """Per form and alloy: the field over the rungs — its adverse end for a binding sentence is the max."""
        return {fm: {al: {"min_over_rungs": min(m[fm][str(st)]["alloys"][al][field] for st in PERIODIC_RUNGS),
                          "max_over_rungs": max(m[fm][str(st)]["alloys"][al][field] for st in PERIODIC_RUNGS),
                          "rung_of_max": max(PERIODIC_RUNGS, key=lambda s: m[fm][str(s)]["alloys"][al][field])}
                     for al in ALLOY_PROPERTIES} for fm in C44_FORMS}

    measured_c44 = {
        "source": str(PERIODIC.relative_to(REPO_ROOT)),
        "is": ("the INFINITE lattice's tensor from periodic conditions on one period cell (01_01 §5.2), carried onto the "
               "part body, which has no C44 of its own — an assumption — in two forms (the absolute modulus ⊥ the Zener "
               "ratio on the body's own C11 − C12), and beside them the material tensor read whole on its own solid "
               "fraction; one cell gives the share and E_z* of one tensor"),
        "rungs_steps_per_period": list(PERIODIC_RUNGS),
        "rungs_excluded": {str(r["steps_per_period"]): r["porosity"] for r in per["rows"] if r not in rungs},
        "density_rule": f"|porosity − the part's {1.0 - phi:.4f}| ≤ {PERIODIC_DENSITY_TOL}",
        "binding_threshold_rule": ("105's headline cell (" + CELL_LS + "); a binding sentence takes the HIGHEST "
                                   "threshold over the modelled cells — and, with the install angle free, over θ — and "
                                   "over the rungs; rounded UP"),
        "scots_pine": meas_scots, "union": meas_union,
        "binds_above_theta_free_ue": {"scots_pine": bracket(meas_scots, "binds_above_theta_free_ue"),
                                      "union": bracket(meas_union, "binds_above_theta_free_ue")},
        "binds_above_theta0_ue": {"scots_pine": bracket(meas_scots, "binds_above_theta0_ue"),
                                  "union": bracket(meas_union, "binds_above_theta0_ue")},
        "lattice_fills_binds_above_theta_free_ue": {
            "scots_pine": bracket(meas_scots, "lattice_fills_binds_above_theta_free_ue"),
            "union": bracket(meas_union, "lattice_fills_binds_above_theta_free_ue")},
        "lattice_fills_binds_above_theta0_ue": {
            "scots_pine": bracket(meas_scots, "lattice_fills_binds_above_theta0_ue"),
            "union": bracket(meas_union, "lattice_fills_binds_above_theta0_ue")},
        "controls": {"e_dir_vs_tensor_worst": e_dir_worst, "form_vs_sweep_worst": form_vs_sweep},
    }
    eq = [m[fm][str(st)]["alloys"][al]["binds_above_theta_free_ue"] == m[fm][str(st)]["alloys"][al]["binds_above_theta0_ue"]
          for m in (meas_scots, meas_union) for fm in C44_FORMS for st in PERIODIC_RUNGS for al in ALLOY_PROPERTIES]
    measured_c44["theta_free_equals_theta0"] = {"count": sum(eq), "of": len(eq),
                                                "over": "readings × rungs × alloys × groups (Scots pine ⊥ union)"}
    combos = [m[fm][str(st)]["alloys"][al]
              for m in (meas_scots, meas_union) for fm in C44_FORMS for st in PERIODIC_RUNGS for al in ALLOY_PROPERTIES]
    rise = [a for a in combos if a["lattice_fills_binds_above_theta_free_ue"] > a["lattice_fills_binds_above_theta0_ue"]]
    measured_c44["lattice_fills_rise_off_axis"] = {
        "count": len(rise), "of": len(combos), "theta_deg": sorted({a["lattice_fills_theta_free_deg"] for a in rise}),
        "max_rise": max(a["lattice_fills_binds_above_theta_free_ue"] / a["lattice_fills_binds_above_theta0_ue"] for a in rise)}
    measured_c44["binding_cell_is_voigt_phase_bound"] = {
        "count": sum(a["theta_free_cell"].endswith("|pores_voigt_phase_bound") for a in combos), "of": len(combos)}

    lower105 = d105["inputs"]["fe_reading_lower"]
    assert lower105 == ("axial_reading" if r_a < r_r else "radial_reading"), "105's lower reading is not its lower"
    a_label = "this tensor's E[100]" + (" (105's lower reading)" if lower105 == "axial_reading" else "")
    r_label = "105's lower reading (the radial one)" if lower105 == "radial_reading" else "105's radial reading"
    t1a, t1r = at_t1["axial_reading"], at_t1["radial_reading"]
    t1_phrase = (f"at t_L = 1 on both readings the upper whisker exceeded it for {', '.join(t1a['upper_whisker']) or 'none'} "
                 f"and the median for {', '.join(t1a['median']) or 'none'}" if t1a == t1r else
                 f"at t_L = 1 the upper whisker exceeded it for {', '.join(t1a['upper_whisker']) or 'none'} on this tensor's "
                 f"E[100] and for {', '.join(t1r['upper_whisker']) or 'none'} on 105's radial reading, the median for "
                 f"{', '.join(t1a['median']) or 'none'} on E[100] and for {', '.join(t1r['median']) or 'none'} on the radial one")
    # the measured-C44 sentence, every clause from the computed block (in-silico §When Modifying #5)
    mc_s, mc_u = measured_c44["scots_pine"], measured_c44["union"]

    def over_rungs(m: dict, field: str) -> list:
        return [m[fm][str(st)][field] for fm in C44_FORMS for st in PERIODIC_RUNGS]

    c44v = [mc_s["material_tensor"][str(st)]["C44_over_voigt_ceiling"] for st in PERIODIC_RUNGS]
    zen = [mc_s["material_tensor"][str(st)]["zener"] for st in PERIODIC_RUNGS]
    eq_c = measured_c44["theta_free_equals_theta0"]
    free_is_theta0 = eq_c["count"] == eq_c["of"]
    radial0 = binds_above["radial_reading"][ALLOY_BASELINE][CELL_LS]
    bf_s = measured_c44["binds_above_theta_free_ue"]["scots_pine"]
    lf_s = measured_c44["lattice_fills_binds_above_theta_free_ue"]["scots_pine"]
    x_hi = max(bf_s[fm][ALLOY_BASELINE]["max_over_rungs"] for fm in C44_FORMS)
    x_lo = min(bf_s[fm][ALLOY_BASELINE]["max_over_rungs"] for fm in C44_FORMS)    # each reading at ITS adverse rung
    y_hi = max(lf_s[fm][ALLOY_BASELINE]["max_over_rungs"] for fm in C44_FORMS)
    j_rec = max((mc_u[fm][str(st)] for fm in C44_FORMS for st in PERIODIC_RUNGS), key=lambda r: r["junction_share_sup"])
    n45 = over_rungs(mc_s, "t_L_theta45_lattice_cells_above_1")
    c44_sentence = (
        f" Read on the measured C44 — the periodic voxel case's infinite lattice, {floor_to(min(c44v), 2):.2f}–"
        f"{ceil_to(max(c44v), 2):.2f} of Voigt's ceiling on its own solid fraction, Zener ratio {floor_to(min(zen), 2):.2f}–"
        f"{ceil_to(max(zen), 2):.2f}, carried onto the part body (which has none of its own) as the absolute modulus ⊥ the Zener ratio, the material "
        f"tensor read whole beside them — the threshold has a ceiling off the axis, and with the install angle free it "
        + ("does not rise above the θ = 0 figure on any reading, rung, alloy or group" if free_is_theta0 else
           "rises above the θ = 0 figure on some reading")
        + f" ({eq_c['count']} of {eq_c['of']} readings × rungs × alloys × groups): for {ALLOY_BASELINE} on the Scots pine "
        f"group the gyroid binds above {x_hi:.0f} µε at most on the tensor's own E_z*(θ) ({x_lo:.0f} on the lowest reading), "
        f"the cells the lattice's C44 enters reaching {y_hi:.0f} µε, and on 105's radial reading, which has no off-axis "
        f"counterpart, its θ = 0 figure {radial0:.0f} µε stands; over every angle the share is at "
        f"most {ceil_to(j_rec['junction_share_sup'], 3):.3f} over the union, at θ = {j_rec['junction_share_sup_theta_deg']:g}°, "
        f"and at θ = 45° it exceeds 1 in {min(n45)}–{max(n45)} of the {lattice_cells} cells the lattice's C44 enters.")
    verdict = (
        f"t_L is not 1, and it lies on both sides of 1 over the modelled set. With a cube axis on the stem's axis (θ = 0) "
        f"it does not depend on the lattice's shear modulus C44 (measured for the infinite lattice by the periodic voxel "
        f"case and read below); at the moistest group (95 % RH) it is "
        f"{floor_to(min(cells[k]['t_L_theta0_any_C44'] for k in rh95), 3):.3f}–"
        f"{ceil_to(max(cells[k]['t_L_theta0_any_C44'] for k in rh95), 3):.3f} over the alloys, the material symmetrisation "
        f"readings and the three pore readings, and which side of 1 it takes depends on the pore reading and on the "
        f"symmetrisation reading. Off that axis C44 enters too: t_L falls as C44 rises, and at θ = 45° it crosses 1 "
        f"inside the admissible C44 in {crossings} of the {lattice_cells} cells the lattice's C44 enters. The pore "
        f"readings' stiffness ends do not bracket the share ({len(outside)} cell-fields fall outside them). Across the "
        f"source's moisture groups the share takes no single direction. For 105, the only C44-free binding figure is at "
        f"θ = 0 (E_z* = E[100] of this tensor): at the lowest θ = 0 share of the Scots pine group ({lows}) the source day's "
        f"upper whisker exceeds the large-stem threshold for {', '.join(sd_a['upper_whisker']['exceeds']) or 'none'} on "
        f"{a_label} and for {', '.join(sd_r['upper_whisker']['exceeds']) or 'none'} on {r_label}, "
        f"and its median for {', '.join(sd_a['median']['exceeds']) or 'none'}; {t1_phrase}. Above fibre saturation no open primary gives a full Scots pine set; on "
        f"the separate group of green readings of other Pinaceae ({len(live_green)} live, {len(excluded_green)} not a "
        f"material) the lowest θ = 0 share is {lows_g}, so over the union it is {lows_u} — on {u_where} — and there the "
        f"upper whisker exceeds the threshold for {', '.join(su_a['upper_whisker']['exceeds']) or 'none'} on this "
        f"tensor's E[100] and for {', '.join(su_r['upper_whisker']['exceeds']) or 'none'} on {r_label}, its "
        f"median for {', '.join(su_a['median']['exceeds']) or 'none'}. Of the highest θ = 0 share, {hi_phrase}; off the "
        f"axis at C44 = 0 the union reaches {ceil_to(max(junction_sup, junction_sup_green), 3):.3f} (the Scots pine group "
        f"{ceil_to(junction_sup, 3):.3f}) — on {citation(junction_union_cell)}, our assembly of its raw means; on the "
        f"published green sets alone it reaches {ceil_to(junction_pub['share'], 3):.3f} — on "
        f"{citation(junction_pub_cell)}{', whose off-axis cells stand on the borrowed ν_RT' if junction_pub['stands_on_borrowed_nu_RT'] else ''}. Off the "
        f"axis the swept threshold has no ceiling as C44 falls.{c44_sentence} The modelled set reads the ring as the host's xylem, its Scots "
        f"pine group stops below fibre saturation and its green readings are other Pinaceae, so its lowest share is not a "
        f"floor."
    )

    result = {
        "script": "106",
        "question": "00_07 HW.23 — the share t_L of the wood's in-plane strain the bonded gyroid takes (orthotropic Eshelby)",
        "inputs": {
            "wood_source": "Güntekin & Akar 2019, Drewno 62(204):41–53, doi 10.12841/wood.1644-3985.220.09, Tables 1–4 "
                           "(the authors' own rows), P. sylvestris sapwood, compression",
            "wood": WOOD,
            "transcription_vs_printed_aggregates": transcription,
            "transcription_aggregates_cover": "ratios of the E and G rows of 45, 65 and 95 % RH, to the printed digit "
                                              "(a row's common scale would pass); no Poisson ratio, nothing of 85 % RH",
            "symmetrisation_readings": {"stiff": "each pair's coupling from the test loaded along its stiffer axis",
                                        "soft": "from the test loaded along its softer axis",
                                        "mean": "the two compliance entries averaged"},
            "fe_readings_105": {"radial_reading": r_r, "axial_reading": r_a},
            "solid_fraction_105": phi,
            "solid_poisson_fe": nu_s,
            "lattice_roots": roots,
            "lattice_reading": {"C11_over_E_s": lat["C11"], "C12_over_E_s": lat["C12"], "nu_star": lat["nu"],
                                "E100_over_E_s": lat["E100"], "zener_voigt_ceiling": a_voigt,
                                "is": "both FE cases read as ONE homogeneous cubic body (kinematic-side readings); "
                                      "C44 swept here, and the periodic voxel case's measured C44 of the infinite lattice "
                                      "read apart as named readings (measured_C44)"},
            "theta_deg": list(THETA_DEG),
            "zener_grid": [float(a) for a in a_grid],
            "pore_readings": {
                "pores_carry_nothing": "the bare lattice — the composite's LOWER stiffness end",
                "pores_additive_host_sapwood": "lattice + (1 − φ)·C_wood — a reading, NO bound",
                "pores_voigt_phase_bound": "φ·C_Ti + (1 − φ)·C_wood — the composite's UPPER stiffness end if the tissue "
                                           "in the pores is no stiffer than the host's sapwood in every direction"},
            "ring": "read as the host's xylem — OUR reading: 01_04 §2's phases say nothing of the ring around Zone 1; "
                    "a soft ring is not modelled",
            "groups": {"scots_pine": "Güntekin & Akar 2019 — every key without a group suffix (wood_readings, cells, "
                                     "theta0_share_over_modelled_set, gyroid_binds_above_…, source_day_…, moisture, …)",
                       "green": "other Pinaceae above fibre saturation — the green_* keys; never merged with the Scots pine "
                                "group (⚖️ founder 2026-10-22, 00_07 HW.23 option (Б))",
                       "union": "both groups — the union_* keys and consumer_ceiling_binding_claim"},
            "green_sources": GREEN_SOURCES,
            "green_sets": {n: {"constants": gs["w"], "readings": list(gs["readings"]), "source": gs["source"],
                               "where": gs["where"]} | ({"mc_lower_bound_pct_ours": gs["mc_lower_bound_pct_ours"]}
                                                        if "mc_lower_bound_pct_ours" in gs else {})
                           for n, gs in gsets.items()},
            "green_transcription": {
                "checks": green_transcription, "liu_table2_as_printed": LIU_TABLE2,
                "jeong_table2_red_pine_as_printed": {r: list(v) for r, v in JEONG_TABLE2_RED_PINE.items()},
                "jeong_green_cv_as_printed": JEONG_GREEN_CV,
                "jeong_table2_korean_pine_as_printed": {r: list(v) for r, v in JEONG_TABLE2_KOREAN_PINE.items()},
                "jeong_korean_pine_green_cv_as_printed": JEONG_KOREAN_PINE_GREEN_CV,
                "davies_table2_as_printed": {k: list(v) for k, v in DAVIES_TABLE2.items()},
                "davies_esm2_as_printed": {k: list(v) for k, v in DAVIES_ESM2.items()},
                "davies_esm3_compression_as_printed": {k: list(v) for k, v in DAVIES_ESM3_COMPRESSION.items()},
                "davies_table1_density_as_printed": {k: list(v) for k, v in DAVIES_TABLE1_DENSITY.items()},
                "covers": "Davies Table 2 — each row's extremes (ESM 1) and its reciprocity at the printed rounding; Liu "
                          "Table 2 — every column through its printed Mean; Jeong — each green E_L through the text's "
                          "retention (red pine 77.1 %, Korean pine 66.9 % within the printed rounding); ESM 2/3 — no "
                          "printed aggregate (the .docx XML text, no OCR)"},
        },
        "wood_readings": {k: {kk: vv for kk, vv in v.items() if not kk.startswith("_")} for k, v in wood.items()},
        "wood_readings_excluded_not_a_material": excluded,
        "cells": cells,
        "additive_outside_the_pore_ends_interval": outside,
        "moisture_grid_points": moisture,
        "theta0_share_over_modelled_set": theta0,
        "gyroid_binds_above_surface_strain_ue_theta0_lowest_share": binds_above,
        "threshold_ratio_vs_baseline_theta0_lowest_share": merit,
        "source_day_theta0_large_stem_sf2": source_day,
        "source_day_at_t1_105": at_t1,
        "off_axis_threshold_factor_theta45": off_axis,
        "e_z_star_105_premise_theta45": ez45,
        "junction_share_sup_at_C44_zero": junction_sup,
        "ligament_factor_argmin_theta_deg_baseline_rh95_stiff": angle_probe,
        "measured_C44": measured_c44,
        "green_wood_readings": {k: {kk: vv for kk, vv in v.items() if not kk.startswith("_")} for k, v in wood_green.items()},
        "green_wood_readings_excluded_not_a_material": excluded_green,
        "green_cells": cells_green,
        "green_additive_outside_the_pore_ends_interval": outside_green,
        "green_theta0_share": theta0_green,
        "green_crossings_theta45": {"cells_crossing_1": crossings_green, "lattice_cells": lattice_cells_green},
        "green_junction_share_sup_at_C44_zero": junction_sup_green,
        "green_reciprocity_our_arithmetic": {
            "per_set": recip, "measured_sets": measured_sets,
            "measured_L_pairs_min_max": [min(l_pairs), max(l_pairs)], "measured_RT_pair_min_max": [min(rt_pair), max(rt_pair)],
            "davies_table2_all_pairs_min_max": [min(t2_pairs), max(t2_pairs)],
            "is": "(ν_ji/E_j)/(ν_ij/E_i): the transverse-loaded entry over the L-loaded one, and R-loaded over T-loaded for "
                  "R–T; 1 where the compliance is symmetric. Davies Table 2 is symmetric by construction; the other sets "
                  "are measured means"},
        "green_davies_table2_over_esm": t2_vs_esm,
        "green_davies_shear_below_liu_x": shear_below_liu,
        "union_theta0_share": theta0_union,
        "union_gyroid_binds_above_surface_strain_ue_theta0_lowest_share": binds_union,
        "union_source_day_theta0_large_stem_sf2": source_day_union,
        "union_junction_share_sup_at_C44_zero": max(junction_sup, junction_sup_green),
        "green_per_set": per_set,
        "green_korean_pine_ta_knife_edge": kp_edge_record,
        "union_without_davies_table2": union_without_table2,
        "consumer_ceiling_binding_claim": ceiling,
        "consumer_ceiling_junction": {
            "rule": "the junction's mismatch scales with the share, so its adverse reading is the HIGHEST share, cited",
            "theta0_highest_per_alloy": {al: {"share": theta0_union[al]["highest"],
                                              "reading": citation(theta0_union[al]["highest_cell"])} for al in ALLOY_PROPERTIES},
            "off_axis_sup_at_C44_zero": {"share": cells_union[junction_union_cell]["t_L_at_C44_zero_max_over_theta"],
                                         "theta_deg": cells_union[junction_union_cell]["theta_of_max_at_C44_zero_deg"],
                                         "cell": junction_union_cell, "reading": citation(junction_union_cell)},
            "jeong_c44_zero_max_plus_its_nu_RT_sensitivity": jeong_c44_zero + nu_rt_off_axis,
            "off_axis_sup_at_C44_zero_published_sets_only": junction_pub | {"reading": citation(junction_pub_cell)}},
        "not_computed": [
            "the finite part's own C44 — the measured one (measured_C44) is the infinite lattice's, carried onto the part "
            "body as an assumption",
            "the stiffness of the tissue in the pores and of the ring — a soft ring drives t_L to 0 in its limit",
            "a green (above fibre saturation) SCOTS PINE set — the green group reads other Pinaceae — and the share's "
            "direction with moisture (across the two groups species and moisture are confounded)",
            "S_1212 of an anisotropic matrix against an independent closed form",
            "the finite length, the bending gradient along R, the curved rings, the bark's proximity, S5",
        ],
        "controls": {"isotropic_cylinder_max_error": ctl_iso, "isotropic_inclusion_max_error": ctl_incl,
                     "t_L_rise_with_C44_worst": monotone_worst, "mirror_45_worst": mirror_worst,
                     "green_t_L_rise_with_C44_worst": monotone_green, "green_mirror_45_worst": mirror_green,
                     "t_L_change_with_G_LR_or_G_RT_worst": g_probe_worst,
                     "g_probe": {"factors": list(G_PROBE_FACTORS), "readings": "every live reading of both groups",
                                 "theta_deg": [0.0, 22.5, 45.0], "zener": "the grid's floor and ceiling and C44 = 0"},
                     "jeong_borrowed_nu_RT": {
                         "borrowed": jeong_red_pine_green()["nu_RT"],
                         "swept_span": [nu_rt_measured[0], nu_rt_measured[-1]], "points": NU_RT_SWEEP_POINTS,
                         "span_is": "every measured ν_RT of the named readings and Jeong's own red pine at 6 and 19 % MC",
                         "t_L_change_theta0_worst": nu_rt_theta0, "cap_theta0": NU_RT_SENSITIVITY_CAP,
                         "t_L_change_off_axis_worst": nu_rt_off_axis,
                         "off_axis_is": "every θ at the C44 grid's floor and ceiling and at C44 = 0 — reported, not capped: "
                                        "Jeong's off-axis cells stand on the borrowed ν_RT"}},
        "verdict": verdict,
    }
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"  wood readings: {len(live)} live, excluded (not positive definite): {', '.join(excluded) or 'none'}")
    print(f"  lattice: C11 {lat['C11']:.5f} · C12 {lat['C12']:.5f} E_s · ν* {lat['nu']:.4f} · Zener ceiling "
          f"{a_voigt:.3f} (the other root ν* {next(r['nu'] for r in roots if not r['inside_voigt']):.3f} — outside Voigt)")
    print(f"  controls: isotropic cylinder {ctl_iso:.1e} · isotropic inclusion {ctl_incl:.1e} · monotone in C44 "
          f"{monotone_worst:.1e} · 45° mirror {mirror_worst:.1e}")
    for al in ALLOY_PROPERTIES:
        c95 = [round(cells[f"{al}|rh95|stiff|{fill}"]["t_L_theta0_any_C44"], 3) for fill in FILLS]
        print(f"  {al:18s} θ=0 rh95 stiff {' ⊥ '.join(map(str, c95))} · θ=0 over set "
              f"{theta0[al]['lowest']:.3f}–{theta0[al]['highest']:.3f} · binds above (large stem, SF 2) "
              f"{binds_above['axial_reading'][al][CELL_LS]:.0f} ⊥ {binds_above['radial_reading'][al][CELL_LS]:.0f} µε")
    print(f"  additive outside the pore ends: {len(outside)} · moisture: {moisture}")
    print(f"  source day at θ = 0: {source_day['axial_reading']['upper_whisker']['exceeds']} ⊥ "
          f"{source_day['radial_reading']['upper_whisker']['exceeds']} (at t_L = 1: {at_t1}) · junction sup {junction_sup:.4f}")
    print(f"  GREEN group: {len(live_green)} live, excluded (not positive definite): {', '.join(excluded_green) or 'none'}")
    print(f"  green controls: monotone in C44 {monotone_green:.1e} · 45° mirror {mirror_green:.1e} · G_LR/G_RT probe "
          f"{g_probe_worst:.1e} · Jeong ν_RT {nu_rt_measured[0]:.2f}–{nu_rt_measured[-1]:.2f}: θ=0 {nu_rt_theta0:.5f} "
          f"(cap {NU_RT_SENSITIVITY_CAP}) ⊥ off axis {nu_rt_off_axis:.4f}")
    for al in ALLOY_PROPERTIES:
        print(f"  {al:18s} θ=0 lowest: Scots pine {theta0[al]['lowest']:.4f} ⊥ green {theta0_green[al]['lowest']:.4f} "
              f"({theta0_green[al]['lowest_cell'].split('|', 1)[1]}) · union binds above "
              f"{binds_union['axial_reading'][al][CELL_LS]:.0f} ⊥ {binds_union['radial_reading'][al][CELL_LS]:.0f} µε "
              f"· green highest {theta0_green[al]['highest']:.4f}")
    print(f"  union source day: {su_a['upper_whisker']['exceeds']} ⊥ {su_r['upper_whisker']['exceeds']} (Ta margins "
          f"{su_a['upper_whisker']['margin_over_threshold']['Ta']:.4f} ⊥ {su_r['upper_whisker']['margin_over_threshold']['Ta']:.4f})"
          f" · green junction sup {junction_sup_green:.4f} · crossings {crossings_green}/{lattice_cells_green}")
    print(f"  junction sup without our raw-ESM assembly: {junction_pub['share']:.4f} at θ {junction_pub['theta_deg']:g}° "
          f"({junction_pub_cell.split('|', 1)[1]})")
    print("  Korean pine, Ta: " + " ⊥ ".join(f"×{v['margin_at_printed']:.4f} (exceeds from ν_LR {v['nu_LR_first_exceeds']})"
                                             for v in kp_edge.values()))
    print(f"  reciprocity (measured sets): L-pairs {min(l_pairs):.3f}–{max(l_pairs):.3f} · R–T {min(rt_pair):.3f}–"
          f"{max(rt_pair):.3f} · Davies Table 2 {min(t2_pairs):.3f}–{max(t2_pairs):.3f}")
    print(f"  → {OUT.relative_to(REPO_ROOT)}")
    print(f"  measured C44 ({len(PERIODIC_RUNGS)} rungs × {len(C44_FORMS)} readings): {ALLOY_BASELINE} binds above "
          f"{x_lo:.0f}–{x_hi:.0f} µε θ-free (θ-free = θ = 0 everywhere: {free_is_theta0}) · C44 cells alone ≤ {y_hi:.0f} · "
          f"share ≤ {j_rec['junction_share_sup']:.3f} · controls e_dir {e_dir_worst:.1e} · form ≡ sweep {form_vs_sweep:.1e}")
    print(f"  {verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
