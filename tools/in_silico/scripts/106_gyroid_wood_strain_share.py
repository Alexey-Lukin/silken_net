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
  Lattice: the two Richardson voxel-FE readings `105` caches, read as ONE homogeneous cubic body with its cube axes on
  the part's frame (Zone1Anode: [001] on the anode's axis; the shipped part is graded, so «cubic» holds locally): the
  axial case is E[001] = r_a·E_s (uniaxial stress between frictionless platens) and the radial case, an equibiaxial
  in-plane strain with the ends held, is C11 + C12 = r_r·E_s/((1 + ν_s)(1 − 2ν_s)) — the solid envelope's same test as
  its normaliser. Two roots; the one outside the Voigt bound φ·C_s (Loewner order) is refused. Both readings sit on the
  kinematic side of a traction modulus (`105`), so this tensor may be stiffer than the true lattice's — an input end, not
  shown to be the output's. C44 no FE case measures: it is swept over (0, φ·μ_s] — Voigt's ceiling (a tighter bound,
  Hashin–Shtrikman's, would narrow it) — as the Zener ratio A* = 2·C44/(C11 − C12) ∈ (0, A*_V]. The cube's rotation θ
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
  held to `105`'s cache — printed on this tensor's own E[100] (`105`'s axial reading) and on `105`'s lower (radial)
  reading, which `105`'s own rule takes for a binding claim; rounded UP. Off the axis E_z*(θ) falls with C44 while t_L
  stays finite, so the threshold has no ceiling as C44 → 0: no binding figure exists there without C44. The junction's
  mismatch (`105`) scales with the HIGHEST share instead; its supremum off the axis is taken at C44 = 0 exactly (t_L is
  non-increasing in C44 — asserted on the grid).

CAN: per alloy, moisture group, symmetrisation reading, pore reading and install angle — t_L over the admissible C44,
the Zener ratio at which t_L crosses 1 at 45°, how many cells the additive reading leaves the ends' interval, how many
grid points fall, rise or neither across the measured moisture groups, the θ = 0 share's range and the `105` thresholds
at its lowest on two readings, the off-axis threshold factor at the C44 grid's ends, the junction's share at θ = 0 and
at C44 = 0; the lattice's off-axis modulus against `105`'s readings.
CANNOT: (1) give C44 — the voxel-FE leg's shear case (00_07 HW.23) does; (2) give the stiffness of the tissue in the
pores or of the ring — a soft ring decouples the gyroid and drives t_L to 0 in its limit (no monotonicity shown); our
reading of the ring (= the host's xylem) is the only ring modelled, so the lowest share here is the lowest of the
MODELLED set, not of the admissible one; (3) give a GREEN wood's share or its direction — the source's wettest group is
below fibre saturation, and across its groups the share takes no single direction; (4) model the finite length, the
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
                  "Scots pine sapwood at four moisture levels, with the lattice's cubic constants read from two voxel "
                  "finite-element cases and its unmeasured shear modulus swept up to the Voigt bound; the install "
                  "angle and three readings of the pore filling are swept as well; closed forms checked against three "
                  "independent solutions, no finite elements")

MECH = CACHE_DIR / "mechanical"
FEA = REPO_ROOT / "tools/cad/cache/fea/anchor_zone1_pine.json"
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
    """Engineering 6×6 compliance (Voigt, γ = 2ε) of one group under one symmetrisation reading."""
    stiff = {"LT": -w["nu_LT"] / w["E_L"], "LR": -w["nu_LR"] / w["E_L"], "TR": -w["nu_RT"] / w["E_R"]}
    soft = {"LT": -w["nu_TL"] / w["E_T"], "LR": -w["nu_RL"] / w["E_R"], "TR": -w["nu_TR"] / w["E_T"]}
    pick = {"stiff": stiff, "soft": soft, "mean": {k: 0.5 * (stiff[k] + soft[k]) for k in stiff}}[reading]
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

    # ── The lattice: 105's Richardson readings, recomputed with 105's own code from the FE cache ──────────────────────
    rows = sorted(fea["rows"], key=lambda r: r["step_mm"])
    for key, field in (("radial_richardson", "radial_ratio"), ("axial_richardson", "axial_ratio")):
        assert abs(s105.richardson_p1(rows[0], rows[1], field) - d105["inputs"]["fe_readings_richardson"][key]) < 1e-12, \
            f"105's cache disagrees with its own Richardson on the FE cache ({key}) — re-run 105"
    assert abs(fea["poisson_ratio"] - s105.NU_SOLID) < 1e-12, "the FE's ν moved — re-read it"
    r_r = d105["inputs"]["fe_readings_richardson"]["radial_richardson"]
    r_a = d105["inputs"]["fe_readings_richardson"]["axial_richardson"]
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

    # ── The wood readings ─────────────────────────────────────────────────────────────────────────────────────────────
    wood = {}
    for g, w in WOOD.items():
        for rd in READINGS:
            s66 = wood_compliance(w, rd)
            ev_min = float(np.linalg.eigvalsh(s66).min())
            if ev_min <= 0.0:
                wood[f"{g}|{rd}"] = {"positive_definite": False, "compliance_min_eigenvalue": ev_min}
                continue
            cm4 = to4(np.linalg.inv(s66))
            s_esh = eshelby_cylinder(cm4)
            hole = control_orthotropic_hole(s66, s_esh, cm4)
            assert abs(hole["kt_eshelby"] / hole["kt_lekhnitskii"] - 1) < 1e-10 and hole["traction_residual"] < 1e-10, \
                f"orthotropic hole control failed on {g}|{rd}: {hole}"
            cov = control_covariance(cm4, s_esh)
            assert cov < 1e-10, f"S is not covariant under a rotation about its axis on {g}|{rd}: {cov}"
            quad = float(np.abs(mandel(eshelby_cylinder(cm4, 2 * N_QUAD)) - mandel(s_esh)).max())
            assert quad < 1e-10, f"Mura's integral not converged at {N_QUAD} points on {g}|{rd}: {quad}"
            sig = np.zeros((3, 3))
            sig[0, 0] = 1.0
            cm = mandel(cm4)
            wood[f"{g}|{rd}"] = {"positive_definite": True, "compliance_min_eigenvalue": ev_min, "hole_control": hole,
                                 "covariance_control": cov, "quadrature_change_at_2n": quad, "_cm": cm,
                                 "_s": mandel(s_esh), "_eps": np.linalg.solve(cm, strain_vec(sig))}
    live = [k for k, v in wood.items() if v["positive_definite"]]
    excluded = [k for k, v in wood.items() if not v["positive_definite"]]

    # ── t_L over every cell ───────────────────────────────────────────────────────────────────────────────────────────
    ti_phase = {al: mandel(iso_c(p_["E_GPa"] * 1e3, p_["nu"])) for al, p_ in ALLOY_PROPERTIES.items()}

    def c_incl(wk: str, al: str, fill: str, th: float, a: float) -> np.ndarray:
        e_s = ALLOY_PROPERTIES[al]["E_GPa"] * 1e3
        if fill == "pores_voigt_phase_bound":
            return phi * ti_phase[al] + (1 - phi) * wood[wk]["_cm"]
        base, shear = parts[th] if th in parts else cubic_parts(lat["C11"], lat["C12"], math.radians(th))
        ci = e_s * (base + a * q_lat / 2 * shear)
        return ci + (1 - phi) * wood[wk]["_cm"] if fill == "pores_additive_host_sapwood" else ci

    def t_l(wk, al, fill, th, a) -> float:
        wv = wood[wk]
        return float(inclusion_strain(wv["_cm"], c_incl(wk, al, fill, th, a), wv["_s"], wv["_eps"])[0] / wv["_eps"][0])

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

    cells, grids, monotone_worst, mirror_worst = {}, {}, 0.0, 0.0
    for al in ALLOY_PROPERTIES:
        for wk in live:
            for fill in FILLS:
                grid = np.array([[t_l(wk, al, fill, th, a) for a in a_grid] for th in THETA_DEG])
                grids[(al, wk, fill)] = grid
                monotone_worst = max(monotone_worst, float(np.diff(grid, axis=1).max()))
                at_av = grid[:, -1]
                at_zero = np.array([t_l(wk, al, fill, th, 0.0) for th in THETA_DEG])
                i_min, i_zero = int(np.argmin(at_av)), int(np.argmax(at_zero))
                cells[f"{al}|{wk}|{fill}"] = {
                    "t_L_theta0_any_C44": float(grid[0, -1]),
                    "t_L_at_voigt_C44_min_over_theta": float(at_av[i_min]), "theta_of_min_deg": THETA_DEG[i_min],
                    "t_L_at_voigt_C44_max_over_theta": float(at_av.max()),
                    "t_L_at_C44_zero_max_over_theta": float(at_zero[i_zero]), "theta_of_max_at_C44_zero_deg": THETA_DEG[i_zero],
                    "zener_at_which_t_L_is_1_theta45": a_cross(wk, al, fill, 45.0),
                    "theta0_independent_of_C44": bool(np.ptp(grid[0]) < 1e-9),
                }
                monotone_worst = max(monotone_worst, float((grid[:, 0] - at_zero).max()))   # C44 = 0 tops the grid
        # the mirror control: t_L(45° + x) = t_L(45° − x) — cubic 90° periodicity with the matrix's T → −T mirror. It
        # guards the PERIMETER claim (0–45° covers every install angle); it holds for any proper rotation, so it does not
        # catch a wrong angle (the E110 closed form at 45° below does), and a non-rotation reds the monotone check first.
        for x in (10.0, 30.0):
            for a in (a_grid[0], a_grid[-1]):
                vals = [t_l(live[0], al, "pores_carry_nothing", th, a) for th in (45 + x, 45 - x)]
                mirror_worst = max(mirror_worst, abs(vals[0] - vals[1]))
    assert monotone_worst < 1e-9, f"t_L rises with C44 somewhere ({monotone_worst}) — the threshold form is void"
    assert mirror_worst < 1e-9, f"the 45° mirror does not hold ({mirror_worst}) — the rotation is wrong"

    # ── Do the pore readings' stiffness ends bracket the SHARE? Count the additive reading outside the ends' interval ──
    outside = []
    for al, wk in itertools.product(ALLOY_PROPERTIES, live):
        ends = [cells[f"{al}|{wk}|{f}"] for f in ("pores_carry_nothing", "pores_voigt_phase_bound")]
        mid = cells[f"{al}|{wk}|pores_additive_host_sapwood"]
        for field in ("t_L_theta0_any_C44", "t_L_at_voigt_C44_min_over_theta"):
            lo, hi = sorted(e[field] for e in ends)
            if not lo - 1e-12 <= mid[field] <= hi + 1e-12:
                outside.append(f"{al}|{wk}|{field}")

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
    f_read = {"axial_richardson": s105.rms_factor(r_a, phi), "radial_richardson": s105.rms_factor(r_r, phi)}
    for al in ALLOY_PROPERTIES:                                    # 105's cached cells, reproduced with its own formula
        lim0 = d105["alloys"][al]["endurance_strain_printed_ue"]
        for dk, frac in d105["inputs"]["depth_fraction"].items():
            for sk, div in d105["inputs"]["stress_state_divisor"].items():
                for sf in (1.0, 2.0):
                    for fk, fv in f_read.items():
                        assert up0(lim0 / sf * div / (fv * frac)) == \
                            d105["gyroid_binds_above_surface_strain_ue"][al][f"{dk}|{sk}|sf{sf:g}"][fk], \
                            f"105's threshold not reproduced ({al} {dk} {sk} sf{sf} {fk}) — re-run 105"
    theta0 = {}
    for al in ALLOY_PROPERTIES:
        ks = [k for k in cells if k.startswith(f"{al}|")]
        k_lo = min(ks, key=lambda k: cells[k]["t_L_theta0_any_C44"])
        k_hi = max(ks, key=lambda k: cells[k]["t_L_theta0_any_C44"])
        theta0[al] = {"lowest": cells[k_lo]["t_L_theta0_any_C44"], "lowest_cell": k_lo,
                      "highest": cells[k_hi]["t_L_theta0_any_C44"], "highest_cell": k_hi}
    binds_above = {fk: {al: {f"{dk}|{sk}|sf{sf:g}": up0(d105["alloys"][al]["endurance_strain_printed_ue"] / sf * div
                                                         / (fv * frac * theta0[al]["lowest"]))
                             for dk, frac in d105["inputs"]["depth_fraction"].items()
                             for sk, div in d105["inputs"]["stress_state_divisor"].items() for sf in (1.0, 2.0)}
                        for al in ALLOY_PROPERTIES}
                   for fk, fv in f_read.items()}
    merit = {al: binds_above["axial_richardson"][al][CELL_LS] / binds_above["axial_richardson"][ALLOY_BASELINE][CELL_LS]
             for al in ALLOY_PROPERTIES}
    stem = d105["inputs"]["stem_readings_87"]
    source_day = {fk: {rd: {"exceeds": sorted(al for al in ALLOY_PROPERTIES
                                              if stem[rd]["surface_strain_ue"] > binds_above[fk][al][CELL_LS]),
                            "margin_over_threshold": {al: stem[rd]["surface_strain_ue"] / binds_above[fk][al][CELL_LS]
                                                      for al in ALLOY_PROPERTIES}}
                       for rd in ("median", "upper_whisker")}
                  for fk in f_read}
    at_t1 = {rd: sorted(al for al in ALLOY_PROPERTIES
                        if stem[rd]["surface_strain_ue"] > d105["gyroid_binds_above_surface_strain_ue"][al][CELL_LS]["axial_richardson"])
             for rd in ("median", "upper_whisker")}

    # ── Off the axis: the lattice's own E_z*(45°) and the threshold factor √(r_a/E_z*)/t_L at the C44 grid's ends ───────
    s11 = (lat["C11"] + lat["C12"]) / ((lat["C11"] - lat["C12"]) * (lat["C11"] + 2 * lat["C12"]))
    s12 = -lat["C12"] / ((lat["C11"] - lat["C12"]) * (lat["C11"] + 2 * lat["C12"]))
    ez45 = {}
    for fk, reading in (("radial_richardson", r_r), ("axial_richardson", r_a)):
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
    sd_a, sd_r = source_day["axial_richardson"], source_day["radial_richardson"]
    verdict = (
        f"t_L is not 1, and it lies on both sides of 1 over the modelled set. With a cube axis on the stem's axis (θ = 0) "
        f"it does not depend on the lattice's unmeasured shear modulus C44; at the moistest group (95 % RH) it is "
        f"{floor_to(min(cells[k]['t_L_theta0_any_C44'] for k in rh95), 3):.3f}–"
        f"{ceil_to(max(cells[k]['t_L_theta0_any_C44'] for k in rh95), 3):.3f} over the alloys, the material symmetrisation "
        f"readings and the three pore readings, and which side of 1 it takes depends on the pore reading and on the "
        f"symmetrisation reading. Off that axis C44 enters too: t_L falls as C44 rises, and at θ = 45° it crosses 1 "
        f"inside the admissible C44 in {crossings} of the {lattice_cells} cells the lattice's C44 enters. The pore "
        f"readings' stiffness ends do not bracket the share ({len(outside)} cell-fields fall outside them). Across the "
        f"source's moisture groups the share takes no single direction. For 105, the only C44-free binding figure is at "
        f"θ = 0 (E_z* = E[100] of this tensor): at the lowest θ = 0 share of the modelled set ({lows}) the source day's "
        f"upper whisker exceeds the large-stem threshold for {', '.join(sd_a['upper_whisker']['exceeds']) or 'none'} on "
        f"this tensor's E[100] and for {', '.join(sd_r['upper_whisker']['exceeds']) or 'none'} on 105's lower reading, "
        f"and its median for {', '.join(sd_a['median']['exceeds']) or 'none'}; at t_L = 1 on the axial reading the "
        f"upper whisker exceeded it for {', '.join(at_t1['upper_whisker']) or 'none'} and the median for "
        f"{', '.join(at_t1['median']) or 'none'}. Off the axis the threshold has no ceiling as C44 falls. The modelled set "
        f"reads the ring as the host's xylem and stops below fibre saturation, so its lowest share is not a floor."
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
            "fe_readings_richardson_105": {"radial_richardson": r_r, "axial_richardson": r_a},
            "solid_fraction_105": phi,
            "solid_poisson_fe": nu_s,
            "lattice_roots": roots,
            "lattice_reading": {"C11_over_E_s": lat["C11"], "C12_over_E_s": lat["C12"], "nu_star": lat["nu"],
                                "E100_over_E_s": lat["E100"], "zener_voigt_ceiling": a_voigt,
                                "is": "both FE cases read as ONE homogeneous cubic body (kinematic-side readings); "
                                      "C44 unmeasured, swept"},
            "theta_deg": list(THETA_DEG),
            "zener_grid": [float(a) for a in a_grid],
            "pore_readings": {
                "pores_carry_nothing": "the bare lattice — the composite's LOWER stiffness end",
                "pores_additive_host_sapwood": "lattice + (1 − φ)·C_wood — a reading, NO bound",
                "pores_voigt_phase_bound": "φ·C_Ti + (1 − φ)·C_wood — the composite's UPPER stiffness end if the tissue "
                                           "in the pores is no stiffer than the host's sapwood in every direction"},
            "ring": "read as the host's xylem — OUR reading: 01_04 §2's phases say nothing of the ring around Zone 1; "
                    "a soft ring is not modelled",
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
        "source_day_at_t1_axial_reading_105": at_t1,
        "off_axis_threshold_factor_theta45": off_axis,
        "e_z_star_105_premise_theta45": ez45,
        "junction_share_sup_at_C44_zero": junction_sup,
        "ligament_factor_argmin_theta_deg_baseline_rh95_stiff": angle_probe,
        "not_computed": [
            "C44 of the lattice — the voxel-FE leg's shear case (00_07 HW.23)",
            "the stiffness of the tissue in the pores and of the ring — a soft ring drives t_L to 0 in its limit",
            "a green (above fibre saturation) wood set, and the share's direction with moisture",
            "S_1212 of an anisotropic matrix against an independent closed form",
            "the finite length, the bending gradient along R, the curved rings, the bark's proximity, S5",
        ],
        "controls": {"isotropic_cylinder_max_error": ctl_iso, "isotropic_inclusion_max_error": ctl_incl,
                     "t_L_rise_with_C44_worst": monotone_worst, "mirror_45_worst": mirror_worst},
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
              f"{binds_above['axial_richardson'][al][CELL_LS]:.0f} ⊥ {binds_above['radial_richardson'][al][CELL_LS]:.0f} µε")
    print(f"  additive outside the pore ends: {len(outside)} · moisture: {moisture}")
    print(f"  source day at θ = 0: {source_day['axial_richardson']['upper_whisker']['exceeds']} ⊥ "
          f"{source_day['radial_richardson']['upper_whisker']['exceeds']} (at t_L = 1: {at_t1}) · junction sup {junction_sup:.4f}")
    print(f"  → {OUT.relative_to(REPO_ROOT)}")
    print(f"  {verdict}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
