#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""105 — the cyclic stress that the stem's sway puts into the titanium parts of the shipped anchor, path by path, and
the condition under which each part becomes binding (00_07 HW.23, the leg «циклічне напруження від гойдання в
друкованих деталях ВІДВАНТАЖЕНОЇ геометрії не пораховане ніде»; closed forms, one energy bound and a reading of the
cached periodic voxel field — no FE solve here).

WHY. The S-N plan (docs/protocols/anchor/sn_fatigue_test_plan.md §1.3) accepts a printed part by
σ_e,print(N) ≥ K_f · S · σ_n, and no model in the tree gave σ_n for the gyroid, the shanks, the barbs or the flange —
so the curve the plan buys had nothing to be compared with. The cycle budget (`62`) puts the question in the endurance
regime: a part below its endurance limit at the amplitude it sees does not care about N (the form 01_01 §1.4 closes the
bus with).

CHAIN (in-silico §Critical Rules #15; joints named from canon). Wood → gyroid (Zone 1, Ø11 × 40 network, in the Ø15
narrow step: a 2 mm radial gap the callus fills — 01_04 §2 Phase 2; Phase 3 turns the callus INSIDE Zone 1 into xylem,
and says nothing of the ring) → the monolithic
Zone 1 shank (Ø11 × 18, four barb rows, a DIN-471 groove still in the CEM — HW.26 G3) → hot press-fit + barbs → the PEEK
sleeve (Ø15/Ø11 × 50), tied at the cambium by the callus ring in the mature state (`103` state 3) → the Zone 3 shank
under `103`'s two premises: (a) in clearance, the disc resting on the sleeve's top face; (b) a rigid Zone-3 fit (HW.8.9)
→ the flange disc (Ø29.8 × 3, the O-ring groove on its top face; CNC from bar OR SLM + HIP — 01_02 §1.7) on faced dead
bark, bearing only (01_04 §3.1) → the radome. A bearing reacts both halves of a cycle only on a preload at least the
force — the bark rising with growth (01_04 §3.1); `103`'s linear bearing presumes that contact holds.

PATHS, by what they scale with (the anchor's axis is the stem's radius; the stem's axis is z) — every one is listed in
the cache with its status:
  S1/S3  in-plane wood strain on the bonded gyroid: ε_L = κ·r along z, −ν_LT·ε_L along the tangent. Strain-controlled:
         its ligament stress scales with E_s·ε, not with a force — so the figure of merit is σ_e/E_s.
  J      the gyroid ⊥ shank junction: the bonded gyroid follows the wood while the solid shank in the soft sleeve does
         not, so the first cell layer absorbs the mismatch — a candidate the bound below cannot see.
  S2     the Poisson part along the anchor's axis, ε_R = −ν_LR·ε_L, through the anode bond: the anode's bond force F_A
         loads the gyroid near its shank end, the Zone 1 shank and its barbs (both flanks once the tie reverses it — the
         lead flank is the ratchet's easy side, which 01_01 §4.3 A says nothing loads in service); the bearing force F_F
         loads the Zone 3 shank and barbs (premise b) and the disc as an annular plate on the bark — under (b) pulled at
         the shank, under (a) pressed by the sleeve's top face, the latter only through a preloaded bearing.
  S4     stem torsion — `77`: microns of slip at the shank, a fretting source at the barbs; S5 transverse shear,
         ~γ·a/R, and the anticlastic curvature ν_LT·κ of a pin lying across the sway plane bend the pin; S6 the rigid
         rotation — no stress. S4/S5 not computed here.
  M      the capsule's mass on its lever arm: bounded here.
  MEANS  the static mean each S2 member carries: cold contraction of the PEEK pulls the flange into the bark, heat lifts
         it (`102` thermal), the bark rising with growth preloads it (`103`), the dead bark's humidity strain rides the
         same path daily — none bounded in the tree. Printed instead: the mean at which each member reaches SF 2.
  W      the weld root on the printed face: `102`'s seam (the wire's axial force with `86`'s bending) — not recomputed.
  ICE/CLAMP  frost in the gap, the groove and the gland (`73` case C — ice sets the collar), the bayonet clamp's thermal
         swing on the lug root (`89`) — low-cycle (frost events, daily), not this script's endurance form.

MODEL.
  Gyroid: an ENERGY BOUND, a LOWER bound on the ligament stress — so it can show a ligament binding and never show one
  safe. The solid phase's mean strain-energy density is the macro density over the solid fraction φ (Hill), and over
  every macro strain with a given ε_z the macro energy is least in uniaxial stress, ½·E_z*·ε_z²; so the RMS
  energy-equivalent stress σ_W over the ligaments is at least √(E_s·E_z*/φ)·ε_z, and no peak is below an RMS. σ_W is
  |σ_1| in uniaxial stress — a ligament in bending and stretching — and at most √(3 + 2ν)·max|σ_i| in any state: two
  readings («near_uniaxial» ⊥ «any_state»). E_z* is the gyroid's uniaxial in-plane modulus under traction conditions,
  which neither FE reading below is: the static case (`fea --traction`, 01_01 §5.2) gives a named ESTIMATE of it — read
  below as a check of this premise, not fed into the thresholds (whether it should is an open 00_07 HW.23 leg), an
  estimate that can sit on either side of the true
  static modulus — while the radial case is a kinematic shell loading ∝ (C11+C12), the axial one
  is E[100] of a cubic lattice and an in-plane direction can be off-axis, and both sit on the kinematic side of a
  traction-BC modulus for a finite part. The two FE ratios — per axis the LOWER end of the finest-step
  bracket, the finest UNLOCKED step (one whose sampled phase does not repeat within four axial cells — the mirror of
  VoxelFea.RepeatCells, picogk gotcha #16) against the finest LOCKED one, over the pinned sweep and the HW.23 re-sweep
  together (2026-10-23; the /12→/16 Richardson pair they replace extrapolated a phase-locked error) — are therefore
  READINGS, not ends: the bound holds only while E_z* is at least the reading. A binding claim takes the LOWER reading —
  the end adverse to the CLAIM (the higher threshold, the kinder one to the part). φ is the finest unlocked row's on
  both axes; where the radial reading comes from the locked row its φ differs by 0.0004, −0.05 % on the threshold,
  toward the claim-adverse side. The output is the
  stem's SURFACE strain above which the bound alone puts the ligaments at σ_e/S at t_L = 1 and k_p = 1 (t_L the share
  of the wood's in-plane strain the gyroid takes — `106`: on both sides of 1, decided by the tissue in the pores, the
  wood reading and, off the cube axis, the lattice's C44; k_p ≥ 1 its peak over RMS stress), rounded UP (a «binds above X» sentence). k_p > 1 lowers X, t_L < 1
  raises it; no strain is shown harmless. The strain at the gyroid is the surface strain times r/R (linear bending),
  read for a sensor on the bark and on the xylem (`103`'s bark bracket) at a DBH-38 host's gyroid shallow end, and at
  r/R → 1. The source day's surface strain (`87`, one tree of DBH 21.5 cm, which `87` refuses to transfer) is set
  beside it as one reading placed on a large stem. The S2 axial term at the shank end has its own lower bound
  (force-controlled: the higher axial ratio is its conservative end); the two bounds are not additive (the macro
  energy's cross term has no established sign).
  Ligament field (00_07 HW.23): beside the bound, NOT multiplying it, the periodic voxel case's field of the INFINITE
  lattice (01_01 §5.2) under a unit uniaxial macro stress across the anchor's axis, at θ from the cube axis — the mount
  angle when the wood's strain runs along the stem. On each periodic rung of the part's density (`106`'s rung rule, read
  from it) one periodic case (six unit-strain solves) gives E*(θ), σ_W/S and the quantiles of the ligaments' peak over
  σ_W, so the peak per unit E_s·ε of the macro strain is k_p·(σ_W/S)·E* — with (σ_W/S)·E* = √(E*/φ) exactly (the
  energy identity, controlled). It is a READING under a uniaxial macro state: the bound stands on that state being the
  least energy at a given strain, the peak has no such order, and the inclusion in the wood is strained multiaxially
  (ceiling (4)). The measure already holds the ligaments' state, so no state divisor applies. Named readings, not picks:
  two measures — max|σ_i| (the bound's own criterion) ⊥ von Mises — and two quantiles — p99, the highest that holds a
  band over the rungs (the max does not converge), ⊥ p99.9. Whether p99 sits at or below a smooth ligament's peak is not
  established (ceiling (3)): the staircase's outer voxel layer is a large share of the metal at every rung, and the
  hottest points are not localised. A binding claim takes the LOWEST peak over rungs × measures, read from the cache;
  max|σ_i| alone is printed beside it as the price of the measure. Over the three sampled angles the claim-adverse
  threshold is the HIGHEST, a maximum over what was computed, not a ceiling over every angle; every source-day cell
  whose flag flips inside the span of readings (rungs × measures) is printed as a knife-edge.
  Forces: `103`'s own closed forms — state 2 (no tie): F = k_s·kc/(kc + k_s)·shift with kc = series(k_A, k_F);
  state 3 (a rigid tie at depth d): F_A = series(k_A, k_lower(d))·(1 − d/dv)·shift — held to `103`'s cached share caps,
  on `103`'s own depth grid, before use. F_A with a rigid sleeve: k_A·shift at `103`'s bond. The bearing force in state 3
  needs the tie's and the bark's stiffness (with both rigid a Ti run between them carries the wood's own strain — no
  physical corner), so F_F is taken in state 2 only; the mature-state disc force is not bounded.
  Solid members: σ_n = F / section (shanks, the groove root), a barb root in bending under its row's share (equal rows —
  the first row carries more), and the disc as an axisymmetric Kirchhoff plate — inner edge on the rigid shank (slope 0),
  outer edge free; under (b) the pull at the shank, under (a) a uniform press over the sleeve's top face; reacted
  (i) uniformly over the bark annulus between the Ø15 channel and the rim (`103`'s bearing area), (ii) at the rim only (a
  dished seat — adverse), (iii) under (b) at the channel's edge. At the shank root σ = 6M_r/t²; across the O-ring groove
  the radial moment passes the thin section, σ = 6M_r/t_g², while the hoop curvature is imposed by the thick plate, so
  its stress is the plate's 6M_θ/t² (recorded, not amplified). Three cycle readings: one-sided 0…F · reversed ±F about
  zero (a tie carries both halves — Zone 1 in state 3) · reversed on a preload ≥ F (a bearing reacting both halves).
  Soderberg (`86`) with K_f on both terms; the printed endurance is `55`'s `endurance_MPa` (OUR markers 0.40 × 0.5 × σ_y,
  not a standard), the CNC route's the wrought derate (1.0); SF 2 is `55`'s line.

CAN: list every path and say which this script prices; give, per alloy, the stem's surface strain above which the bound
alone puts the gyroid's ligaments at σ_e/S (t_L = k_p = 1, per FE reading, stress-state reading and sensor reference),
and whether the source day reaches it; the same for the periodic case's uniaxial-state reading of the ligament PEAK,
per named quantile and sampled mount angle at the readings' adverse end (rungs × measures), with max|σ_i| beside it and
every knife-edge; per mount angle, where the part's named static estimate lies against BOTH FE readings on every
measured step; the anode's bond force and the bearing force per premise, state and bond end;
each solid member's nominal stress, the K_f at which it reaches SF 2 per cycle reading and route, and the static mean at
which it does; the force the sway puts on the barbs' easy flank; the junction's mismatch; the mass path.
CANNOT: (1) show any part SAFE from the gyroid bound, or any ligament safe from the field reading; carry the part's
static in-plane reading into the thresholds (it is read as a CHECK of the bound's premise only — `fea --traction`,
01_01 §5.2), or give the field under traction (no case), the inclusion's field under
the wood's multiaxial strain (the periodic cache holds uniaxial cases only — the lattice's elastic half is the CAD
side's, in-silico §When Modifying #24), which quantile is a smooth ligament's fatigue peak (01_01 §5.2 ceiling (3)), or
the junction's stress — a junction model (gyroid + solid + sleeve end + wood); (2) give t_L — `106` does (orthotropic Eshelby on Scots pine's measured
constants), and it hangs on the tissue in the pores, the wood reading and moisture, and off the cube axis on the
lattice's shear modulus (measured for the infinite lattice by the periodic voxel case, not read here); the
callus annulus's stiffness is unknown (01_04 §2); (3) count how often a
host's stem reaches the threshold — the field strain sensor (00_07 HW.43) does; `62` counts first-mode cycles, not
strain ranges; (4) give any K_t, the barb rows' split, the force at which a barb row ratchets on its lead flank, the
bark bearing's stiffness and preload, or any static mean; (5) price the collar and lug root (`73`/`89`), the printed
face under the weld (`102`/`86`), the PEEK side (HW.26's FEA), the storm's few cycles, the daily heat.

Run:  conda activate silken_md
      python tools/in_silico/scripts/105_printed_part_sway_stress.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    CACHE_DIR,
    DBH_MIN_CM,
    E_PEEK_PA,
    REPO_ROOT,
)
from lib.utils import banner

SI_DESCRIPTION = ("Cyclic stress from stem sway in the titanium parts of the anchor, path by path: an energy lower "
                  "bound on the ligament stress of a gyroid lattice bonded to the wood, given as the stem surface strain "
                  "above which it alone reaches the endurance limit, per candidate alloy, and beside it a reading of the "
                  "ligament peak under a uniaxial macro stress from a periodic finite-element case of the infinite "
                  "lattice, which is not a bound; the axial force the wood "
                  "imposes through the anode bond; and the nominal stress in the solid shanks, barbs and the flange disc "
                  "(an annular Kirchhoff plate on the bark), with the stress-concentration factor and the static mean at "
                  "which each reaches the safety-factor line; closed forms over cached finite-element results, no "
                  "solve here")

MECH = CACHE_DIR / "mechanical"
CEM = REPO_ROOT / "tools/cad/cem"
FEA_DIR = REPO_ROOT / "tools/cad/cache/fea"
FEA = FEA_DIR / "anchor_zone1_pine.json"                       # the pinned `--sweep` (steps = axial period / N)
FEA_FINE = sorted(FEA_DIR.glob("anchor_zone1_pine.h*um.json"))  # the HW.23 re-sweep (`--step-mm` rows, one per file)
OUT = MECH / "printed_part_sway_stress.json"
G_STD = 9.80665            # m/s² — standard gravity, the literal `87` uses
SF_LINES = (1.0, 2.0)      # 1 = σ_e itself · 2 = `55`'s INFINITE_LIFE_SF (asserted below)
NU_SOLID = 0.342           # the solid phase's ν in the voxel FE, asserted against its cache
DEPTH_MIN_MM = 0.5         # the shallowest tie on `103`'s depth axis (its DEPTH_MIN), asserted by reproducing its caps
DEPTH_POINTS = 40          # `103`'s depth grid: DEPTH_MIN … each tie depth in 40 steps (its `depths`)
CAP_TOL = 1e-4             # `103` caches its shares at four decimals
CYCLES = ("one_sided", "reversed", "on_preload")
# the periodic field's quantiles read as the ligament peak — NAMED readings, not a pick (01_01 §5.2 ceiling (3)): p99 is
# the one a binding claim takes (the lower peak of the two that hold a band over the rungs), p99.9 its price; the max
# does not converge over the ladder, and p50/p90 are not peaks
PEAK_QUANTILES = ("p99", "p99.9")
# the periodic field's stress measures — NAMED readings (§When Modifying #11): max|σ_i| is the bound's own criterion, von
# Mises the other common fatigue measure; a binding claim takes whichever gives the lower peak, read from the cache
PEAK_MEASURES = {"max_principal": "principal_over_sigma_w", "von_mises": "von_mises_over_sigma_w"}


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module        # dataclasses under postponed annotations resolve their module by name
    spec.loader.exec_module(module)
    return module


def up0(x: float) -> float:
    """A «binds above X» strain rounds UP (in-silico §When Modifying #43)."""
    return float(math.ceil(round(x, 6)))


def up2(x: float) -> float:
    """An «at most» stress rounds UP."""
    return math.ceil(round(x * 100.0, 9)) / 100.0


def down2(x: float) -> float:
    """A lower bound or a «harmless below it» K_f rounds DOWN."""
    return math.floor(round(x * 100.0, 9)) / 100.0


def series(*k: float) -> float:
    return 1.0 / sum(1.0 / x for x in k)


def fe_ladder(sweep: dict, fine_files, axial_period_mm: float) -> list[dict]:
    """Every part row of the pinned sweep and the HW.23 re-sweep, one per step, coarse → fine, each tagged `locked`:
    the step divides the part's axial period (since HW.33 (в) the rim's, one for the whole part — picogk gotcha #16), so
    every cell is sampled at the same phases and the step's error is coherent along z. A step both families carry (the
    re-sweep's /8 identity control) must agree field for field, or the re-sweep is not the sweep's instrument."""
    rows: dict[float, dict] = {}
    for r in sweep["rows"]:
        rows[round(r["step_mm"], 9)] = dict(r, source="sweep")
    for f in fine_files:
        d = json.loads(f.read_text(encoding="utf-8"))
        assert d["cem"] == sweep["cem"] and d["topology"] == sweep["topology"], f"{f.name}: not the sweep's specimen"
        assert abs(d["poisson_ratio"] - sweep["poisson_ratio"]) < 1e-12, f"{f.name}: the FE's ν differs from the sweep's"
        for r in d["rows"]:
            k = round(r["step_mm"], 9)
            if k in rows:
                for key in ("elements", "porosity", "axial_ratio", "radial_ratio"):
                    assert abs(rows[k][key] - r[key]) <= 1e-9 * max(1.0, abs(r[key])), \
                        f"{f.name}: the step {k} mm row disagrees with the pinned sweep on {key} — not the same instrument"
                continue
            rows[k] = dict(r, source=f.name)
    ladder = []
    for step in sorted(rows, reverse=True):
        r = rows[step]
        r["locked"] = axial_lock_cells(step, axial_period_mm) > 0
        assert r["converged"] and abs(r["solid_calibration_axial"] - 1.0) < 1e-5, f"FE row {step} mm not valid"
        ladder.append(r)
    return ladder


def axial_lock_cells(step_mm: float, period_mm: float, max_cells: int = 4) -> int:
    """The mirror of VoxelFea.RepeatCells (tools/cad/src/SilkenCad/VoxelFea.cs — the ONE home of the rule): how many
    axial cells the sampled phase of a constant period takes to repeat at this step, 0 when it does not within max_cells.
    Its tolerance 1e-4·cells is the FE's own; the steps are stored as float32 (`/24` = 0.083333336 mm sits 7.7e-7 off
    an integer count, and `/21`–`/48` divisors reach 2e-6), so a 1e-6 tolerance would call a dividing step unlocked."""
    if period_mm <= 0:
        return 0
    steps_per_period = period_mm / step_mm
    for cells in range(1, max_cells + 1):
        steps = steps_per_period * cells
        if abs(steps - round(steps)) < 1e-4 * cells:
            return cells
    return 0


def fe_readings_from_ladder(ladder: list[dict]):
    """Per axis the two finest-step readings — the finest UNLOCKED row (the two finest unlocked steps agree to ≤ 0.03 %,
    the coarsest sits 0.5 % under them axially — HW.23 2026-10-23; three points bound no convergence order) and the
    finest LOCKED row — a bracket of NAMED readings (in-silico §When Modifying #11); the reading a binding claim takes is
    the bracket's LOWER end, adverse to the claim. Returns (readings, bracket, finest_unlocked_row, finest_locked_row)."""
    unlocked = [r for r in ladder if not r["locked"]]
    locked = [r for r in ladder if r["locked"]]
    assert unlocked and locked, "the ladder needs at least one unlocked and one locked step"
    fu, fl = unlocked[-1], locked[-1]
    bracket = {ax: {"unlocked": fu[f"{ax}_ratio"], "locked": fl[f"{ax}_ratio"],
                    "unlocked_step_mm": fu["step_mm"], "locked_step_mm": fl["step_mm"],
                    "adverse": "unlocked" if fu[f"{ax}_ratio"] <= fl[f"{ax}_ratio"] else "locked"}
               for ax in ("radial", "axial")}
    readings = {f"{ax}_reading": min(bracket[ax]["unlocked"], bracket[ax]["locked"]) for ax in ("radial", "axial")}
    return readings, bracket, fu, fl


def read_fe():
    """ONE home of 105's FE reading rule — 106 and the cache tests call this instead of re-deriving it."""
    sweep = json.loads(FEA.read_text(encoding="utf-8"))
    pine = json.loads((CEM / "anchor_zone1.pine.json").read_text(encoding="utf-8"))
    ladder = fe_ladder(sweep, FEA_FINE, pine["gyroid_period_rim_mm"])
    readings, bracket, fu, fl = fe_readings_from_ladder(ladder)
    return {"sweep": sweep, "ladder": ladder, "readings": readings, "bracket": bracket,
            "finest_unlocked": fu, "finest_locked": fl}


def rms_factor(ratio: float, phi: float) -> float:
    """Energy bound: RMS σ_W over the solid ≥ √(E*/(E_s·φ)) · E_s·ε — in units of E_s·ε."""
    return math.sqrt(ratio / phi)


def plate_shear(F: float, load: tuple[float, float], react: tuple[float, float]):
    """Transverse shear per unit circumferential length (N/mm) of a disc loaded by F spread uniformly over the annulus
    `load` (a ring when its ends coincide) and reacted by F spread uniformly over `react` (a line when they coincide)."""
    def inside(r: float, band: tuple[float, float]) -> float:
        lo, hi = band
        if hi - lo < 1e-12:
            return 1.0 if r >= lo else 0.0
        return min(max((r * r - lo * lo) / (hi * hi - lo * lo), 0.0), 1.0)
    return lambda r: F * (inside(r, load) - inside(r, react)) / (2.0 * math.pi * r)


def plate_moments(b: float, a: float, shear, nu: float, n: int = 20000):
    """Axisymmetric Kirchhoff annular plate, inner edge on a rigid boss (slope 0), outer edge free (M_r = 0).
    With D factored out: (1/r)·d(rφ)/dr = G(r) + C1, G = ∫_b^r shear; φ(b) = 0; M_r = G + C1 − (1 − ν)·φ/r;
    M_θ = ν·M_r + (1 − ν²)·φ/r. Returns (r, M_r, M_θ), N·mm/mm."""
    import numpy as np

    r = np.linspace(b, a, n + 1)
    q = np.array([shear(x) for x in r])
    g = np.concatenate([[0.0], np.cumsum(0.5 * (q[1:] + q[:-1]) * np.diff(r))])
    rg = r * g
    i = np.concatenate([[0.0], np.cumsum(0.5 * (rg[1:] + rg[:-1]) * np.diff(r))])
    c1 = ((1.0 - nu) * i[-1] / a ** 2 - g[-1]) / (1.0 - (1.0 - nu) * (a ** 2 - b ** 2) / (2.0 * a ** 2))
    phi = (i + c1 * (r ** 2 - b ** 2) / 2.0) / r
    m_r = g + c1 - (1.0 - nu) * phi / r
    m_t = nu * m_r + (1.0 - nu ** 2) * phi / r
    return r, m_r, m_t


def plate_mr_fd(b: float, a: float, shear, nu: float, at: tuple[float, ...], n: int = 4000) -> list[float]:
    """Independent control: φ'' + φ'/r − φ/r² = shear/D by central differences, φ(b) = 0, φ'(a) + ν·φ(a)/a = 0
    (second-order one-sided); M_r = φ' + ν·φ/r at the radii `at`. CAN catch a wrong integration, boundary condition,
    sign or shear law in the closed form, at the shank root and inside the groove; CANNOT catch a wrong plate model
    (both solve the same Kirchhoff equation)."""
    import numpy as np

    r = np.linspace(b, a, n + 1)
    h = r[1] - r[0]
    mat = np.zeros((n + 1, n + 1))
    rhs = np.array([shear(x) for x in r])
    mat[0, 0], rhs[0] = 1.0, 0.0
    for k in range(1, n):
        mat[k, k - 1] = 1 / h ** 2 - 1 / (2 * h * r[k])
        mat[k, k] = -2 / h ** 2 - 1 / r[k] ** 2
        mat[k, k + 1] = 1 / h ** 2 + 1 / (2 * h * r[k])
    mat[n, n], mat[n, n - 1], mat[n, n - 2], rhs[n] = 3 / (2 * h) + nu / a, -2 / h, 1 / (2 * h), 0.0
    phi = np.linalg.solve(mat, rhs)
    dphi = np.gradient(phi, h, edge_order=2)
    m_r = dphi + nu * phi / r
    return [float(np.interp(x, r, m_r)) for x in at]


def main() -> int:
    banner("105 — sway stress in the anchor's titanium parts: the gyroid's energy bound and the solid members")
    s86 = _load("s86_105", "86_coaxiality_allocation.py")
    s55 = s86.s55
    assert SF_LINES[-1] == s55.INFINITE_LIFE_SF, "the SF line must be 55's"

    d87 = json.loads((MECH / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    d102 = json.loads((MECH / "wire_liner_shear_lag.json").read_text(encoding="utf-8"))
    d103 = json.loads((MECH / "anchor_wood_share.json").read_text(encoding="utf-8"))
    d52 = json.loads((MECH / "z_stack_tolerance.json").read_text(encoding="utf-8"))
    fea = json.loads(FEA.read_text(encoding="utf-8"))
    lock1 = json.loads((CEM / "mechanical_lock.zone1.json").read_text(encoding="utf-8"))
    flange = json.loads((CEM / "cathode_flange.json").read_text(encoding="utf-8"))
    sleeve = json.loads((CEM / "zone2_sleeve.json").read_text(encoding="utf-8"))
    pine = json.loads((CEM / "anchor_zone1.pine.json").read_text(encoding="utf-8"))

    # ── Stem readings (87 — one source tree; 102's shift is the one 103 scales its share to) ─────────────────────────
    readings = {}
    for rd in ("median", "upper_whisker"):
        stem = d87["by_slope_reading"][rd]["stem_at_anchor_h_le_2m"]
        readings[rd] = {"surface_strain_ue": stem["surface_strain_microstrain_source_tree"],
                        "accel_m_s2": stem["accel_m_s2"], "shift_um": d102["sway_input"]["shift_um_87"][rd]}
    geo = d103["geometry"]
    dvs = list(geo["shift_span_mm_87"].values())
    dv_ceil = max(dvs)
    lattice_span = (dv_ceil - geo["anode_length_mm"], dv_ceil)                 # mm below the flange seat
    r_host = DBH_MIN_CM * 10.0 / 2.0
    r_gyroid = r_host - lattice_span[0]                                        # the gyroid's shallow end
    depth_fraction = {"dbh_min_sensor_on_bark": r_gyroid / r_host}
    for side, bark in geo["bark_mm_78"].items():
        depth_fraction[f"dbh_min_sensor_on_xylem_{side}"] = r_gyroid / (r_host - bark - geo["phloem_mm_78"])
    depth_fraction["large_stem_limit"] = 1.0

    # ── The gyroid: the energy bound ────────────────────────────────────────────────────────────────────────────────
    assert abs(fea["poisson_ratio"] - NU_SOLID) < 1e-9, "the FE's ν moved — re-read it"
    ladder = fe_ladder(fea, FEA_FINE, pine["gyroid_period_rim_mm"])
    fe_readings, fe_bracket, fine, fine_locked = fe_readings_from_ladder(ladder)
    phi = 1.0 - fine["porosity"]                                   # the converged (finest unlocked) row's own φ
    # a binding claim takes the LOWER reading — READ from the pair, never assumed. Since the HW.23 re-sweep (2026-10-23)
    # each axis is the adverse end of its own [unlocked ⊥ locked] bracket; which axis is lower is a finding of the caches.
    lo_key, hi_key = sorted(fe_readings, key=fe_readings.get)
    f_read = {k: rms_factor(v, phi) for k, v in fe_readings.items()}
    state_div = {"near_uniaxial": 1.0, "any_state": math.sqrt(3.0 + 2.0 * NU_SOLID)}

    # ── Forces: 103's closed forms, held to its cached caps ─────────────────────────────────────────────────────────
    span = geo["span_mm"]
    a_sleeve = math.pi / 4.0 * ((sleeve["bore_diameter_mm"] + 2 * sleeve["wall_thickness_mm"]) ** 2
                                - sleeve["bore_diameter_mm"] ** 2)
    ea_peek = E_PEEK_PA / 1e6 * a_sleeve
    k_s_a = d103["stiffness_N_per_mm"]["sleeve"]["sway"]
    assert abs(ea_peek / span - k_s_a) / k_s_a < 1e-3, "103's sleeve stiffness is no longer E_PEEK·A/L — stale cache?"
    z3 = d103["zone3_fit"]
    l_run = z3["sections_mm"]["composite_run"][1]
    ea_comp = z3["stiffness_N_per_mm"]["composite_run"]["sway"] * l_run

    def comp(premise: str, d1: float, d2: float) -> float:
        if premise == "a_flange_on_bark":
            return (d2 - d1) / ea_peek
        return (max(0.0, min(d2, l_run) - max(d1, 0.0)) / ea_comp
                + max(0.0, min(d2, span) - max(d1, l_run)) / ea_peek)

    k_a_cached = d103["stiffness_N_per_mm"]["anode_bond"]
    bonds = {"anode_bond_stiff": max(k_a_cached.values()), "anode_bond_soft": min(k_a_cached.values())}
    ties = list(geo["flange_seat_to_install_day_cambium_mm"].values())
    # `103`'s own depth set (41 points from DEPTH_MIN to each install-day cambium depth): its caps are maxima over THIS
    # set, and a finer grid that lands on the composite run's end finds a max 1e-4 higher — another set, not a model
    grid = sorted({DEPTH_MIN_MM + (t - DEPTH_MIN_MM) * i / DEPTH_POINTS for t in ties for i in range(DEPTH_POINTS + 1)})
    premises = {"a_flange_on_bark": d103["share"], "b_zone3_fit": z3["share"]}
    cap_check, forces = {}, {}
    for pn, cached in premises.items():
        k_s = 1.0 / comp(pn, 0.0, span)
        forces[pn] = {}
        for bn, ka in bonds.items():
            s2 = ka / (ka + k_s)
            s3 = max((d / dv + (1 - d / dv) * ka / (ka + 1.0 / comp(pn, d, span))) * dv / dv_ceil
                     for d in grid for dv in dvs)
            cap_check[f"{pn}|{bn}"] = {"state2": [s2, cached["state2_cap_rigid_bark"][bn]],
                                      "state3": [s3, cached["state3_cap_rigid_bark_of_102_shift"][bn]]}
            assert abs(s2 - cached["state2_cap_rigid_bark"][bn]) < CAP_TOL, f"state-2 cap not reproduced: {pn} {bn}"
            assert abs(s3 - cached["state3_cap_rigid_bark_of_102_shift"][bn]) < CAP_TOL, f"state-3 cap: {pn} {bn}"
            fa3_per_mm = max(series(ka, 1.0 / comp(pn, d, span)) * (1 - d / dv) * dv / dv_ceil
                             for d in grid for dv in dvs)
            forces[pn][bn] = {"k_sleeve": k_s, "state2_rigid_bark_per_mm": k_s * s2,
                              "state3_bond_per_mm_max_over_ties": fa3_per_mm,
                              "rigid_sleeve_bond_per_mm": ka}
        forces[pn]["air_dry_bark_max_per_mm"] = k_s * cached["state2_at_air_dry_readings"]["max"]
    forces["a_flange_on_bark"]["condition"] = ("state 2 under (a) needs a bearing that reacts both ways — the growth "
                                               "preload ≥ the force; without it the anode's pull rides the bus wire, "
                                               "capped by the liner wall (`87`)")

    def f_newton(per_mm: float, rd: str) -> float:
        return per_mm * readings[rd]["shift_um"][1] * 1e-3              # the adverse end of 102's shift

    # ── Solid-member geometry (CEM; 52's applied gland) ──────────────────────────────────────────────────────────────
    d1 = lock1["shank_diameter_mm"]
    a_shank1 = math.pi / 4.0 * d1 ** 2
    a_groove1 = math.pi / 4.0 * (d1 - 2.0 * lock1["groove_depth_mm"]) ** 2
    a_shank3 = z3["shank"]["ti_section_mm2"]

    def barb(cem: dict) -> dict:
        h = cem["barb_height_mm"]
        w = h / math.tan(math.radians(cem["lead_angle_deg"])) + h / math.tan(math.radians(cem["trail_angle_deg"]))
        return {"rows": cem["barb_rows"], "height_mm": h, "root_width_mm": w,
                "circumference_mm": math.pi * cem["shank_diameter_mm"]}

    barb1, barb3 = barb(lock1), barb(flange)

    def barb_sigma(F: float, b: dict) -> float:
        return 6.0 * (F / b["rows"] / b["circumference_mm"]) * b["height_mm"] / b["root_width_mm"] ** 2

    gl = d52["applied_gland"]
    disc = {"b": flange["shank_diameter_mm"] / 2.0, "a": flange["flange_diameter_mm"] / 2.0,
            "c": geo["channel_radius_mm"], "sleeve_face": [sleeve["bore_diameter_mm"] / 2.0, geo["channel_radius_mm"]],
            "t": flange["flange_thickness_mm"], "groove_r": list(gl["flange_groove_r_mm"]),
            "groove_depth": gl["flange_groove_depth_mm"]}
    disc["t_groove"] = disc["t"] - disc["groove_depth"]
    assert abs(math.pi * (disc["a"] ** 2 - disc["c"] ** 2) - geo["flange_annulus_mm2"]) < 0.05, "bearing area moved"
    assert abs(geo["channel_radius_mm"] - (sleeve["bore_diameter_mm"] / 2 + sleeve["wall_thickness_mm"])) < 1e-9

    b, a, c = disc["b"], disc["a"], disc["c"]
    disc_cases = {
        "b_pull_at_shank|uniform_over_bark_annulus": ((b, b), (c, a)),
        "b_pull_at_shank|rim_only_dished_seat": ((b, b), (a, a)),
        "b_pull_at_shank|channel_edge_only": ((b, b), (c, c)),
        "a_sleeve_face_press|uniform_over_bark_annulus": (tuple(disc["sleeve_face"]), (c, a)),
        "a_sleeve_face_press|rim_only_dished_seat": (tuple(disc["sleeve_face"]), (a, a)),
    }
    disc_per_newton, plate_controls = {}, {}
    g_mid = 0.5 * (disc["groove_r"][0] + disc["groove_r"][1])
    for name, (ld, rc) in disc_cases.items():
        sh = plate_shear(1.0, ld, rc)
        r, m_r, m_t = plate_moments(b, a, sh, NU_SOLID)
        fd_b, fd_g = plate_mr_fd(b, a, sh, NU_SOLID, (b, g_mid))
        cl_g = float(m_r[abs(r - g_mid).argmin()])
        plate_controls[name] = {"Mr_b": [float(m_r[0]), fd_b], "Mr_groove_mid": [cl_g, fd_g]}
        for cl, fd in plate_controls[name].values():
            assert abs(cl - fd) <= 2e-3 * max(abs(cl), abs(fd), 1e-6), f"plate closed form ⊥ FD disagree: {name}"
        in_g = (r >= disc["groove_r"][0]) & (r <= disc["groove_r"][1])
        disc_per_newton[name] = {
            "shank_root_MPa_per_N": 6.0 * max(abs(float(m_r[0])), abs(float(m_t[0]))) / disc["t"] ** 2,
            "groove_radial_MPa_per_N": 6.0 * float(abs(m_r[in_g]).max()) / disc["t_groove"] ** 2,
            "groove_hoop_plate_MPa_per_N": 6.0 * float(abs(m_t[in_g]).max()) / disc["t"] ** 2}

    # ── Alloys and routes ────────────────────────────────────────────────────────────────────────────────────────────
    alloys = {}
    for name, p in ALLOY_PROPERTIES.items():
        se = s55.endurance_MPa(p["yield_MPa"])             # printed derate — OUR markers
        alloys[name] = {"E_GPa": p["E_GPa"], "yield_MPa": p["yield_MPa"], "endurance_printed_MPa": se,
                        "endurance_wrought_MPa": s55.endurance_MPa(p["yield_MPa"], derate=s55.WROUGHT_DERATE),
                        "endurance_strain_printed_ue": se / (p["E_GPa"] * 1e3) * 1e6}

    def assess(sig: float, row: dict, route: str) -> dict:
        se = row["endurance_printed_MPa"] if route == "printed" else row["endurance_wrought_MPa"]
        out = {}
        for cyc in CYCLES:
            sa, sm = {"one_sided": (sig / 2.0, sig / 2.0), "reversed": (sig, 0.0), "on_preload": (sig, sig)}[cyc]
            sf = s86.soderberg(sa, sm, se, row["yield_MPa"])[0] if sig > 0 else math.inf
            out[cyc] = {"sf_at_kf1": sf, "kf_at_sf2": sf / s55.INFINITE_LIFE_SF}    # K_f on both terms ⇒ SF ∝ 1/K_f
        room = 1.0 / s55.INFINITE_LIFE_SF - sig / se       # the mean at which ±σ reaches SF 2 at K_f 1
        out["mean_at_sf2_MPa"] = row["yield_MPa"] * room if room > 0 else None
        return out

    # ── The solid members ────────────────────────────────────────────────────────────────────────────────────────────
    zone1 = {}           # driven by the anode's bond force — the winner alloy (Zone 1 is printed, V-free whatever wins)
    for pn in premises:
        for bn in bonds:
            for kind, per in (("state2_rigid_bark", forces[pn][bn]["state2_rigid_bark_per_mm"]),
                              ("state3_rigid_tie_max", forces[pn][bn]["state3_bond_per_mm_max_over_ties"]),
                              ("rigid_sleeve", forces[pn][bn]["rigid_sleeve_bond_per_mm"])):
                for rd in readings:
                    F = f_newton(per, rd)
                    sig = {"zone1_shank": F / a_shank1, "zone1_groove_root": F / a_groove1,
                           "zone1_barb_root_bending": barb_sigma(F, barb1)}
                    zone1[f"{pn}|{bn}|{kind}|{rd}"] = {
                        "force_N": F,
                        "members": {m: {"sigma_n_MPa": s, "printed": {al: assess(s, row, "printed")
                                                                      for al, row in alloys.items()}}
                                    for m, s in sig.items()}}
    zone3 = {}           # Zone 3 stays 4V unless rule (в) moves it (01_02 §2.5); CNC from bar ⊥ SLM + HIP (01_02 §1.7)
    row4 = alloys[ALLOY_BASELINE]
    for pn in premises:
        for bn in bonds:
            for kind, per in (("state2_rigid_bark", forces[pn][bn]["state2_rigid_bark_per_mm"]),
                              ("state2_air_dry_bark_max", forces[pn]["air_dry_bark_max_per_mm"])):
                if kind == "state2_air_dry_bark_max" and bn != "anode_bond_stiff":
                    continue                                    # one cached share per premise, not per bond
                for rd in readings:
                    F = f_newton(per, rd)
                    sig = {}
                    if pn == "b_zone3_fit":
                        sig = {"zone3_shank": F / a_shank3, "zone3_barb_root_bending": barb_sigma(F, barb3)}
                    pre = pn[0]
                    for case, v in disc_per_newton.items():
                        if case.startswith(pre + "_"):
                            sig[f"disc_shank_root|{case}"] = v["shank_root_MPa_per_N"] * F
                            sig[f"disc_groove|{case}"] = v["groove_radial_MPa_per_N"] * F
                    zone3[f"{pn}|{bn}|{kind}|{rd}"] = {
                        "force_N": F,
                        "members": {m: {"sigma_n_MPa": s, "printed": assess(s, row4, "printed"),
                                        "cnc_wrought": assess(s, row4, "wrought")} for m, s in sig.items()}}

    # ── The gyroid: the surface strain above which the bound alone reaches σ_e/S ────────────────────────────────────
    gyroid = {}
    for al, row in alloys.items():
        gyroid[al] = {}
        for dk, frac in depth_fraction.items():
            for sk, div in state_div.items():
                for sf in SF_LINES:
                    lim = row["endurance_strain_printed_ue"] / sf * div
                    gyroid[al][f"{dk}|{sk}|sf{sf:g}"] = {fk: up0(lim / (fv * frac)) for fk, fv in f_read.items()}
    source_day = {rd: {al: {k: {fk: rv["surface_strain_ue"] > fx for fk, fx in v.items()} for k, v in cells.items()}
                       for al, cells in gyroid.items()} for rd, rv in readings.items()}
    # how far each large-stem SF 2 cell sits from flipping (in-silico §When Modifying #40): the stem strain over the
    # cell's threshold per FE reading (as rounded above — `106`'s margin), and the FE reading (of E_s) at which the
    # unrounded bound meets the stem strain — the bound goes as √(ratio/φ), so that reading is one number for either
    # axis; a margin inside the readings' own doubt is a knife-edge (00_07 HW.23), not a set membership
    source_day_flip = {rd: {al: {} for al in alloys} for rd in readings}
    for rd, rv in readings.items():
        for al, row in alloys.items():
            for sk, div in state_div.items():
                lim = row["endurance_strain_printed_ue"] / 2.0 * div
                key = f"large_stem_limit|{sk}|sf2"
                cell = {"margin_over_threshold": {fk: rv["surface_strain_ue"] / gyroid[al][key][fk] for fk in f_read},
                        "fe_reading_at_flip": phi * (lim / rv["surface_strain_ue"]) ** 2}
                # controls — CAN catch: the closed form drifting from `rms_factor`, and a flip reading that disagrees
                # with the flag above outside the rounding sliver (a different cell, SF or reading); CANNOT: the sliver
                # itself, where `up0` puts the rounded bound at or just above the strain, which the flag decides
                assert abs(lim / rms_factor(cell["fe_reading_at_flip"], phi) - rv["surface_strain_ue"]) < 1e-6
                for fk, fx in fe_readings.items():
                    assert ((fx > cell["fe_reading_at_flip"]) == source_day[rd][al][key][fk]
                            or abs(gyroid[al][key][fk] - rv["surface_strain_ue"]) <= 1.0), f"flip ⊥ flag: {rd} {al} {key}"
                source_day_flip[rd][al][key] = cell

    # ── The ligament field: the periodic voxel case's UNIAXIAL-STATE reading (00_07 HW.23) ───────────────────────────
    # The infinite lattice's k_p and E*(θ) come from one periodic case per rung of the part's density (six unit-strain
    # solves); the rung rule is `106`'s `periodic_rungs`, its ONE home. Peak per unit E_s·ε of the macro strain =
    # k_p·(σ_W/S)·E*. Not this bound times k_p (01_01 §5.2 ceiling (4)); no state divisor — the measure already holds the
    # ligaments' state. Two measures are NAMED readings (§When Modifying #11): max|σ_i|, the bound's own criterion, ⊥ von
    # Mises; a binding claim takes the LOWEST peak over rungs × measures — which measure that is, is read, never assumed.
    s106 = _load("s106_105", "106_gyroid_wood_strain_share.py")
    rungs = s106.periodic_rungs(json.loads(s106.PERIODIC.read_text(encoding="utf-8")), phi, NU_SOLID)
    thetas = [f["theta_deg"] for f in rungs[0]["fields"]]
    assert all([f["theta_deg"] for f in r["fields"]] == thetas for r in rungs), "the rungs carry different θ grids"
    assert thetas[0] == 0, "the verdict reads the first sampled direction as the cube axis — the θ grid moved"
    lig_field, identity_worst = {}, 0.0
    for i, th in enumerate(thetas):
        tk = f"{th:g}"
        lig_field[tk] = {}
        for q in PEAK_QUANTILES:
            by_rung = {}
            for r in rungs:
                f = r["fields"][i]
                e, sw = f["modulus_ratio"], f["sigma_w_per_macro_stress"]
                rms = math.sqrt(e / r["solid_fraction_meshed"])
                # control — CAN catch: σ_W redefined or rescaled in the cache (per strain, per φ), or E* and σ_W taken
                # from different solves; CANNOT catch a wrong field — the identity holds on any converged one
                identity_worst = max(identity_worst, abs(sw * e - rms) / rms)
                by_rung[str(r["steps_per_period"])] = {
                    "modulus_ratio": e,
                    "k_p": {m: f[key][q] for m, key in PEAK_MEASURES.items()},
                    "peak_per_E_s_strain": {m: f[key][q] * sw * e for m, key in PEAK_MEASURES.items()}}
            cells = [(v["peak_per_E_s_strain"][m], m) for v in by_rung.values() for m in PEAK_MEASURES]
            lig_field[tk][q] = {"by_rung": by_rung, "peak_low": min(cells)[0], "measure_at_low": min(cells)[1],
                                "peak_high": max(cells)[0]}
    assert identity_worst < 1e-6, f"(σ_W/S)·E* ≠ √(E*/φ) on the periodic case ({identity_worst:.1e}) — re-read its σ_W"
    tks = list(lig_field)

    # the stem's surface strain above which the reading puts the ligament PEAK at σ_e/S at t_L = 1, at the lowest peak over
    # rungs × measures (adverse to a binding claim), rounded UP; over the sampled angles the claim-adverse one is the
    # HIGHEST. Beside it, the price of the measure: the same on max|σ_i| alone (its rungs' lowest peak)
    def thr_cells(lim, frac, q, peak_of):
        cell = {tk: up0(lim / (peak_of(tk, q) * frac)) for tk in tks}
        cell["any_sampled_angle"] = max(cell[tk] for tk in tks)
        return cell

    def principal_low(tk, q):
        return min(v["peak_per_E_s_strain"]["max_principal"] for v in lig_field[tk][q]["by_rung"].values())

    lig, lig_principal = {}, {}
    for al, row in alloys.items():
        lig[al], lig_principal[al] = {}, {}
        for dk, frac in depth_fraction.items():
            for sf in SF_LINES:
                for q in PEAK_QUANTILES:
                    lim = row["endurance_strain_printed_ue"] / sf
                    lig[al][f"{dk}|{q}|sf{sf:g}"] = thr_cells(lim, frac, q, lambda t, qq: lig_field[t][qq]["peak_low"])
                    lig_principal[al][f"{dk}|{q}|sf{sf:g}"] = thr_cells(lim, frac, q, principal_low)
    # the source day on a large stem at SF 2: the flag on the rounded cell and its margin over it (the bound's convention),
    # and whether some reading in the span flips it — the threshold at the HIGHEST peak over rungs × measures below the
    # strain while the adverse cell is not: a knife-edge, not a member. CANNOT: a strain in the rounding sliver of the
    # adverse cell (x < ε ≤ ⌈x⌉) is labelled a knife-edge too
    lig_source, knives = {}, []
    for rd, rv in readings.items():
        eps = rv["surface_strain_ue"]
        lig_source[rd] = {}
        for al, row in alloys.items():
            lim = row["endurance_strain_printed_ue"] / 2.0
            lig_source[rd][al] = {}
            for q in PEAK_QUANTILES:
                x_oth = {tk: lim / lig_field[tk][q]["peak_high"] for tk in tks}
                x_oth["any_sampled_angle"] = max(x_oth.values())
                cells = lig[al][f"large_stem_limit|{q}|sf2"]
                lig_source[rd][al][q] = {k: {"exceeds": eps > cells[k], "margin_over_threshold": eps / cells[k],
                                             "flips_inside_readings": x_oth[k] < eps <= cells[k]} for k in cells}
                knives += [{"reading": rd, "alloy": al, "quantile": q, "angle": k}
                           for k, v in lig_source[rd][al][q].items() if v["flips_inside_readings"]]

    # ── The bound's PREMISE against the part's static in-plane reading (`fea --traction`, 01_01 §5.2, 00_07 HW.23) ────
    # The bound holds only while the in-plane modulus under traction is at least the FE reading it is evaluated on. The
    # static case gives a named ESTIMATE of it per mount angle on a step ladder — one that can sit on either side of the
    # true static modulus (01_01 §5.2, ceiling (3)) — read here as a CHECK of that premise: per angle, where it lies
    # against BOTH readings on every measured step. Not fed into the thresholds above (whether it should is an open
    # 00_07 HW.23 leg).
    traction = []
    for f in sorted(FEA_DIR.glob(f"{pine['name']}.traction.h*um.json")):
        d = json.loads(f.read_text(encoding="utf-8"))
        assert d["cem"] == pine["name"] and abs(d["poisson_ratio"] - NU_SOLID) < 1e-12, f"{f.name}: not this part"
        assert abs(d["solid_calibration_theta0"] - 1.0) < 1e-6 and all(r["converged"] for r in d["rows"]), f"{f.name}: not a measurement"
        traction.append(d)
    traction.sort(key=lambda d: -d["step_mm"])
    premise = {"lower_fe_reading": fe_readings[lo_key], "higher_fe_reading": fe_readings[hi_key],
               "steps_mm": [d["step_mm"] for d in traction], "by_theta": {}}
    for th in sorted({r["theta_deg"] for d in traction for r in d["rows"]}):
        ladder_e = [next(r["traction_modulus_ratio"] for r in d["rows"] if r["theta_deg"] == th) for d in traction]
        above = all(e >= fe_readings[hi_key] for e in ladder_e)
        below = all(e < fe_readings[lo_key] for e in ladder_e)
        premise["by_theta"][f"{th:g}"] = {"static_modulus_by_step": ladder_e,
                                          "where": "above_both" if above else "below_both" if below else "between"}

    # the S2 axial term at the gyroid's shank end — its own lower bound, force-controlled (the higher ratio is its
    # conservative end); mature state, stiff bond, the source day's upper reading
    fa_axial = f_newton(forces["b_zone3_fit"]["anode_bond_stiff"]["state3_bond_per_mm_max_over_ties"], "upper_whisker")
    axial_hi = max(fe_bracket["axial"]["unlocked"], fe_bracket["axial"]["locked"])   # the HIGHER end: conservative for a force
    axial_rms = {al: {"rms_MPa": fa_axial / a_shank1 * math.sqrt(1.0 / (axial_hi * phi)),
                      "over_sf2_line": fa_axial / a_shank1 * math.sqrt(1.0 / (axial_hi * phi))
                                       / (row["endurance_printed_MPa"] / s55.INFINITE_LIFE_SF)}
                 for al, row in alloys.items()}

    # the junction: the radial mismatch the first cell layer absorbs at t_L = 1 (the solid shank in the soft sleeve taken
    # as not straining — its strain lowers the mismatch), and that mismatch over one rim period as a multiple of the
    # wood's strain there — an ORDER of the layer's distortion, not a stress (in-silico §When Modifying #28)
    frac_sh = depth_fraction["dbh_min_sensor_on_bark"]
    junction = {"rim_period_mm": pine["gyroid_period_rim_mm"], "layer_over_wood_strain": (d1 / 2.0) / pine["gyroid_period_rim_mm"],
                "mismatch_um_at_tL1_sensor_on_bark": {rd: rv["surface_strain_ue"] * frac_sh * d1 / 2.0 * 1e-3
                                                      for rd, rv in readings.items()}}

    # the barbs' easy flank: the reversed half of F_A in the mature state (the tie reverses it)
    easy_flank = {bn: {rd: f_newton(forces["b_zone3_fit"][bn]["state3_bond_per_mm_max_over_ties"], rd) for rd in readings}
                  for bn in bonds}

    # ── Mass path ────────────────────────────────────────────────────────────────────────────────────────────────────
    m_kg = d87["inputs"]["mass_ceiling_g"] / 1e3
    lever_mm = d87["inputs"]["capsule_envelope_mm"][1]
    d3, bore3 = flange["shank_diameter_mm"], flange["bore_diameter_mm"]
    z_shank3 = math.pi * (d3 ** 4 - bore3 ** 4) / (32.0 * d3)
    mass_path = {rd: {"moment_Nmm": m_kg * (G_STD + rv["accel_m_s2"]) * lever_mm,
                      "zone3_shank_bending_MPa": m_kg * (G_STD + rv["accel_m_s2"]) * lever_mm / z_shank3}
                 for rd, rv in readings.items()}

    # ── Verdict, built from the data ─────────────────────────────────────────────────────────────────────────────────
    def thr(al, dk, sk, fk=None, sf=2.0):
        return gyroid[al][f"{dk}|{sk}|sf{sf:g}"][fk or lo_key]

    def reach(rd, dk, sk, fk):
        return sorted(al for al in alloys if source_day[rd][al][f"{dk}|{sk}|sf2"][fk])

    lo_uni = reach("upper_whisker", "large_stem_limit", "near_uniaxial", lo_key)
    hi_uni = reach("upper_whisker", "large_stem_limit", "near_uniaxial", hi_key)
    lo_any = reach("upper_whisker", "large_stem_limit", "any_state", lo_key)
    md_uni = reach("median", "large_stem_limit", "near_uniaxial", lo_key)
    lo_name, hi_name = lo_key.split("_")[0], hi_key.split("_")[0]
    f_lo, f_hi = down2(f_read[lo_key]), down2(f_read[hi_key])
    rms_span = (f"{f_lo:.2f} E_s·ε on both FE readings ({lo_name} {fe_readings[lo_key]:.4f} ⊥ {hi_name} "
                f"{fe_readings[hi_key]:.4f} of E_s)" if f_lo == f_hi else
                f"{f_lo:.2f}–{f_hi:.2f} E_s·ε on the two FE readings")
    z1_cap = zone1["b_zone3_fit|anode_bond_stiff|state3_rigid_tie_max|upper_whisker"]
    z1_soft = zone1["b_zone3_fit|anode_bond_soft|state3_rigid_tie_max|upper_whisker"]
    z1_rigid = zone1["b_zone3_fit|anode_bond_stiff|rigid_sleeve|upper_whisker"]
    z3_cap = zone3["b_zone3_fit|anode_bond_stiff|state2_rigid_bark|upper_whisker"]
    z3_dry = zone3["b_zone3_fit|anode_bond_stiff|state2_air_dry_bark_max|upper_whisker"]
    worst_disc = max((v["sigma_n_MPa"], k) for k, v in z3_cap["members"].items() if k.startswith("disc"))
    wdp, wdc = z3_cap["members"][worst_disc[1]]["printed"], z3_cap["members"][worst_disc[1]]["cnc_wrought"]
    eps_up = readings["upper_whisker"]["surface_strain_ue"]
    alist = ", ".join(f"{al} {thr(al, 'large_stem_limit', 'near_uniaxial'):.0f}" for al in alloys)
    fm = {al: round(row["endurance_strain_printed_ue"] / alloys[ALLOY_BASELINE]["endurance_strain_printed_ue"], 2)
          for al, row in alloys.items()}

    def names(xs):
        return ", ".join(xs) if xs else "none"

    def names_all(xs):
        return "every alloy" if set(xs) == set(alloys) else names(xs)

    def lig_set(rd, q, flag, k="any_sampled_angle"):
        return sorted(al for al in alloys if lig_source[rd][al][q][k][flag])

    def lig_band(q, tk):
        return f"{down2(lig_field[tk][q]['peak_low']):.2f}–{up2(lig_field[tk][q]['peak_high']):.2f}"

    def lig_list(table, k):
        return ", ".join(f"{al} {table[al]['large_stem_limit|p99|sf2'][k]:.0f}" for al in alloys)

    measure_name = {"max_principal": "max|σ_i|", "von_mises": "von Mises"}
    lows = {lig_field[tk]["p99"]["measure_at_low"] for tk in tks}
    low_on = (f"{measure_name[next(iter(lows))]} at every sampled angle" if len(lows) == 1 else
              ", ".join(f"{measure_name[lig_field[tk]['p99']['measure_at_low']]} at {tk}°" for tk in tks))
    angle_name = {"any_sampled_angle": "every sampled angle", **{tk: f"θ = {tk}°" for tk in tks}}
    knife_txt = "; ".join(f"{k['alloy']} ({k['reading'].replace('_', ' ')}, {k['quantile']}, {angle_name[k['angle']]})"
                          for k in knives)
    def angles(ks):
        xs = [f"{k}°" if k != "0" else "θ = 0" for k in ks]
        return " and ".join(xs) if len(xs) < 3 else ", ".join(xs[:-1]) + " and " + xs[-1]

    def where(w):
        ks = [k for k, v in premise["by_theta"].items() if v["where"] == w]
        return angles(ks) if ks else "no angle"

    prem_text = (
        f"The bound stands on the part's in-plane modulus under traction being at least its FE reading ({lo_name} "
        f"{fe_readings[lo_key]:.4f} of E_s): the named static estimate (01_01 §5.2 — a reading that can sit on either side "
        f"of the true static modulus, never a proof) lies above both FE readings at {where('above_both')}, below both at "
        f"{where('below_both')} and between them at {where('between')} on every measured step — where it is not above both, "
        f"this bound's «binds above» is not established. " if traction else
        "The bound's premise — the part's in-plane modulus under traction at least the FE reading — is not measured. ")
    lig_text = (
        f"The periodic voxel case's ligament field — the INFINITE lattice under a uniaxial macro stress across the "
        f"anchor's axis, a READING, neither this bound times a peak factor nor the inclusion's multiaxial state — puts "
        f"the peak at p99 (the highest quantile that holds a band over the rungs; whether a smooth ligament's fatigue peak "
        f"sits above or below it is not established) at {lig_band('p99', tks[0])} E_s·ε along the cube axis and "
        f"{lig_band('p99', tks[-1])} at {tks[-1]}°, over the rungs of the part's density and two measures (max|σ_i| ⊥ "
        f"von Mises). At its lowest — {low_on} — and t_L = 1 the ligaments reach SF 2 on a large stem above "
        f"{lig_list(lig, 'any_sampled_angle')} µε at every sampled mount angle ({lig_list(lig, tks[0])} at θ = 0; on "
        f"max|σ_i| alone, at every sampled angle: {lig_list(lig_principal, 'any_sampled_angle')}). The source day's "
        f"median exceeds them for {names_all(lig_set('median', 'p99', 'exceeds'))} at every sampled angle and for "
        f"{names_all(lig_set('median', 'p99', 'exceeds', tks[0]))} at θ = 0, its upper whisker for "
        f"{names_all(lig_set('upper_whisker', 'p99', 'exceeds'))}; read at p99.9, the median exceeds them for "
        f"{names_all(lig_set('median', 'p99.9', 'exceeds'))}. "
        + (f"Inside the span of readings — knife-edges, not members: {knife_txt}. " if knives else
           "No source-day cell flips inside the span of readings. "))

    verdict = (
        f"The bonded GYROID is strain-controlled, so its figure of merit is σ_e/E_s, not σ_e (relative to "
        f"{ALLOY_BASELINE}: " + ", ".join(f"{al} {v:.2f}" for al, v in fm.items()) + "). An energy LOWER bound — "
        f"it can show a ligament binding, never safe — puts the ligaments' RMS stress at ≥ {rms_span}, neither of which "
        f"is the in-plane traction modulus the bound needs. On the lower reading (the {lo_name} one), at t_L = k_p = 1 "
        f"with near-uniaxial ligaments, the bound alone "
        f"reaches SF 2 above a stem surface strain of {alist} µε on a large stem; k_p > 1 lowers these, t_L < 1 (not "
        f"excluded) raises them. The source tree's upper surface strain ({eps_up:.0f} µε, one tree, one gust), placed on a "
        f"large stem, exceeds them for {names(lo_uni)} on the lower reading ({names(hi_uni)} on the higher; any stress "
        f"state: {names(lo_any)}); its median for {names(md_uni)}. " + prem_text + lig_text + "The gyroid⊥shank junction is a "
        f"candidate the bound "
        f"cannot see: at t_L = 1 its first layer absorbs {junction['mismatch_um_at_tL1_sensor_on_bark']['upper_whisker']:.1f} "
        f"µm of radial mismatch, {junction['layer_over_wood_strain']:.2f}× the wood's strain over one rim period. The "
        f"anode's bond force in the mature state is {z1_cap['force_N']:.0f} N on a stiff bond and {z1_soft['force_N']:.0f} N "
        f"on a soft one ({z1_rigid['force_N']:.0f} N with a rigid sleeve at `103`'s stiff bond): the Zone 1 shank carries "
        f"{z1_cap['members']['zone1_shank']['sigma_n_MPa']:.1f} MPa, and the tie reverses the force onto the barbs' easy "
        f"flank — which 01_01 §4.3 A says nothing loads in service. The FLANGE DISC in state 2 on a rigid bark "
        f"({z3_cap['force_N']:.0f} N, Zone-3 fit) carries a worst nominal {worst_disc[0]:.1f} MPa ({worst_disc[1]}): "
        f"one-sided (a bearing without preload) it reaches SF 2 at K_f {down2(wdp['one_sided']['kf_at_sf2']):.2f} on the "
        f"printed route ⊥ {down2(wdc['one_sided']['kf_at_sf2']):.2f} on the CNC route — the same number is its un-notched SF "
        f"when a preload ≥ F carries both halves. On the air-dry bark reading "
        f"the force is {z3_dry['force_N']:.0f} N; the mature-state disc force is not bounded. The mass path stays below "
        f"{up2(max(v['zone3_shank_bending_MPa'] for v in mass_path.values())):.2f} MPa. Not computed: the field under "
        f"traction (no case) — the static reading enters as a premise check only, not the thresholds (whether it should "
        f"is an open 00_07 HW.23 leg) — the inclusion's "
        f"field under the wood's multiaxial strain (the periodic cache holds uniaxial cases only), the junction (a junction model), t_L (`106` — conditional), the "
        f"count of host-stem cycles above the threshold (the field sensor), any K_t, a barb row's ratchet force, the "
        f"static means, ice, the collar and lug root.")

    result = {
        "script": Path(__file__).name,
        "question": "00_07 HW.23 — cyclic stress from stem sway in the printed parts of the shipped geometry",
        "paths": {
            "S1_S3_inplane_strain_on_gyroid": "a lower bound here (energy) — conditional on E_z*; beside it the periodic "
                                              "case's uniaxial-state reading of the ligament peak (not a bound); t_L in "
                                              "`106` (conditional)",
            "J_gyroid_shank_junction": "NOT COMPUTED — a candidate the bound cannot see; needs a junction model",
            "S2_bond_force_zone1": "computed here (nominal) — shank, groove root, barbs; the easy flank is loaded",
            "S2_bearing_force_zone3_disc": "computed here (nominal, state 2) — Zone 3 shank and barbs (premise b), disc "
                                           "(b at the shank · a through a preloaded bearing); the mature state not bounded",
            "S4_stem_torsion": "77 — microns of slip; a fretting K_f source at the barbs, not a stress",
            "S5_shear_and_anticlastic_bending": "NOT COMPUTED — transverse shear ~γ·a/R and the anticlastic ν_LT·κ bend "
                                                "the radial pin",
            "S6_rigid_rotation": "no stress",
            "M_capsule_mass": "bounded here",
            "MEANS_cold_heat_growth_humidity": "NOT BOUNDED — 102 thermal (cold pulls the flange in, heat lifts it), "
                                              "103 growth preload, the dead bark's humidity strain; printed instead: "
                                              "the mean at which each member reaches SF 2",
            "W_weld_root_on_printed_face": "102 seam (axial wire force with 86's bending) — not recomputed",
            "W2_wire_liner_zone3_channel": "NOT COMPUTED — a joint in the chain; the Ti there carries little",
            "ICE_gap_groove_gland": "73 case C (ice sets the collar) · FMEA #29 — low-cycle, outside this form",
            "CLAMP_bayonet_thermal_swing": "89 — the lug root's daily swing, low-cycle, outside this form",
            "F_pogo_drag_storm_event": "87 · HW.26 — small or few cycles",
        },
        "inputs": {
            "stem_readings_87": readings,
            "gyroid_span_below_seat_mm": list(lattice_span),
            "host_radius_mm_dbh_min": r_host,
            "depth_fraction": depth_fraction,
            "fea_rows_used": {"finest_unlocked": {k: fine[k] for k in ("step_mm", "axial_ratio", "radial_ratio", "porosity", "source")},
                              "finest_locked": {k: fine_locked[k] for k in ("step_mm", "axial_ratio", "radial_ratio", "porosity", "source")}},
            "fe_ladder": [{k: r[k] for k in ("step_mm", "locked", "axial_ratio", "radial_ratio", "porosity", "source")} for r in ladder],
            "fe_bracket": fe_bracket,
            "fe_readings": fe_readings,
            "fe_reading_lower": lo_key,
            "fe_reading_rule": "per axis the LOWER end of the [finest unlocked ⊥ finest locked] finest-step bracket over the "
                               "pinned sweep and the HW.23 re-sweep (a step is locked when its sampled phase repeats within four "
                               "axial cells — axial_lock_cells, the mirror of VoxelFea.RepeatCells)",
            "fe_readings_are": "two kinematic-side readings; neither is the in-plane traction modulus E_z* the bound needs",
            "solid_fraction": phi,
            "rms_factor_by_reading": f_read,
            "stress_state_divisor": state_div,
            "anode_bond_N_per_mm_103": bonds,
            "tie_depths_mm_103": ties,
            "disc": disc,
            "barbs": {"zone1": barb1, "zone3": barb3},
            "sections_mm2": {"zone1_shank": a_shank1, "zone1_groove_root": a_groove1, "zone3_shank": a_shank3},
            "endurance_markers_55": {"ENDURANCE_OVER_YIELD": s55.ENDURANCE_OVER_YIELD,
                                     "AS_PRINTED_DERATE": s55.AS_PRINTED_DERATE, "WROUGHT_DERATE": s55.WROUGHT_DERATE,
                                     "INFINITE_LIFE_SF": s55.INFINITE_LIFE_SF, "whose": "ours, not a standard"},
            "cycle_readings": {"one_sided": "0…F (a bearing without preload)",
                               "reversed": "±F about zero (a tie carries both halves — Zone 1 in state 3)",
                               "on_preload": "±F on a preload ≥ F (a bearing reacting both halves)"},
        },
        "alloys": alloys,
        "strain_figure_of_merit_vs_baseline": fm,
        "gyroid_binds_above_surface_strain_ue": gyroid,
        "gyroid_source_day_exceeds": source_day,
        "gyroid_source_day_flip_large_stem_sf2": source_day_flip,
        "gyroid_bound_premise_static_modulus": dict(premise, source="tools/cad/cache/fea/<cem>.traction.h*um.json",
                                                    rule="per mount angle: where the named static estimate lies against "
                                                         "BOTH FE readings on every measured step — a CHECK of the "
                                                         "bound's premise (an estimate that can sit on either side of "
                                                         "the true static modulus), not fed into its thresholds — "
                                                         "whether it should is an open 00_07 HW.23 leg"),
        "gyroid_ligament_field_uniaxial_reading": {
            "source": str(s106.PERIODIC.relative_to(REPO_ROOT)),
            "is": "the INFINITE lattice's ligament field under a unit uniaxial macro stress along (cos θ, sin θ, 0) — "
                  "across the anchor's axis, θ from the cube axis — from periodic conditions (01_01 §5.2): a READING "
                  "under a uniaxial macro state, never the energy bound times k_p (ceiling (4)), and not the multiaxial "
                  "state of the inclusion in the wood",
            "rungs_steps_per_period": list(s106.PERIODIC_RUNGS),
            "rung_rule": f"`106`'s `periodic_rungs`: |porosity − the part's {1.0 - phi:.4f}| ≤ "
                         f"{s106.PERIODIC_DENSITY_TOL}",
            "quantiles": {"p99": "the highest quantile that holds a band over the rungs — the one the thresholds read; "
                                 "whether it sits at or below a smooth ligament's peak is not established (01_01 §5.2 "
                                 "ceiling (3)): the outer voxel layer is a large share of the metal, the hottest points "
                                 "are not localised",
                          "p99.9": "beside it — wider over the rungs",
                          "not_read": "max (does not converge over the ladder) · p50, p90 (not peaks)"},
            "measures": {"max_principal": "max|σ_i| — the energy bound's own criterion",
                         "von_mises": "von Mises — the other common fatigue measure"},
            "peak_rule": "peak per unit E_s·ε = k_p·(σ_W/S)·E* of one periodic case per rung (six unit-strain solves); "
                         "a binding claim takes the LOWEST peak over rungs × measures (its measure read, "
                         "`measure_at_low`), and over the sampled angles the HIGHEST threshold (three directions, not a "
                         "ceiling over every angle); max|σ_i| alone is printed beside it as the price of the measure",
            "angle_criterion": "peak_per_E_s_strain(θ) = k_p(θ)·√E*(θ)/√φ of the rung — the mount-angle criterion "
                               "k_p·√E*·t_L (00_07 HW.23) up to the rung's 1/√φ; t_L(θ) is `106`'s",
            "field": lig_field,
            "binds_above_surface_strain_ue": lig,
            "binds_above_surface_strain_ue_max_principal_only": lig_principal,
            "source_day_large_stem_sf2": lig_source,
            "knife_edges_large_stem_sf2": knives,
            "controls": {"energy_identity_worst_rel": identity_worst},
        },
        "gyroid_axial_term_mature_stiff_bond_upper": {"force_N": fa_axial, "by_alloy": axial_rms,
                                                      "note": "its own lower bound; not additive with the in-plane one"},
        "junction": junction,
        "forces_N_per_mm_of_shift": forces,
        "barb_easy_flank_force_N": easy_flank,
        "disc_MPa_per_N": disc_per_newton,
        "zone1_members": zone1,
        "zone3_members": zone3,
        "mass_path": mass_path,
        "not_computed": [
            "the field under traction — no case; the part's static in-plane reading enters as a premise check only, not "
            "fed into the thresholds (whether it should is an open 00_07 HW.23 leg); the inclusion's field under the wood's multiaxial strain — the periodic "
            "cache holds uniaxial cases only",
            "which quantile of the periodic field is a smooth ligament's fatigue peak — the instrument does not say "
            "(01_01 §5.2 ceiling (3)); p99 and p99.9 are read as named readings",
            "the gyroid⊥shank junction's stress — a junction model (gyroid + solid + sleeve end + wood)",
            "t_L — the share of the wood's in-plane strain the bonded gyroid takes: `106`, conditional on the tissue in the pores, the wood reading and C44",
            "the count of host-stem strain cycles above the threshold — the field strain sensor, 00_07 HW.43",
            "any K_t; the barb rows' split; a barb row's ratchet force on its lead flank; the bark bearing's stiffness",
            "the static means — cold, heat, growth preload, the dead bark's humidity strain",
            "S5 — the radial pin's bending by the stem's transverse shear and anticlastic curvature (the shank's nominal "
            "is its axial term only)",
            "the mature-state disc force; ice; the collar and lug root (73/89); the weld's printed face (102/86); PEEK",
        ],
        "controls": {"plate_closed_form_vs_fd": plate_controls,
                     "sleeve_stiffness_recomputed": {"E_PEEK_A_over_L": ea_peek / span, "cached_103": k_s_a},
                     "share_caps_reproduced_103": cap_check},
        "verdict": verdict,
    }
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"  FE readings (adverse end of the finest-step bracket) radial {fe_readings['radial_reading']:.4f} "
          f"[unlocked {fe_bracket['radial']['unlocked']:.5f} ⊥ locked {fe_bracket['radial']['locked']:.5f}] · axial "
          f"{fe_readings['axial_reading']:.4f} [unlocked {fe_bracket['axial']['unlocked']:.5f} ⊥ locked "
          f"{fe_bracket['axial']['locked']:.5f}] · φ {phi:.3f} · RMS factor {f_read[lo_key]:.3f}–{f_read[hi_key]:.3f}")
    print(f"  binds-above surface strain (µε), SF 2, t_L = k_p = 1, lower ({lo_name}) reading: large stem | bark | "
          "xylem thin | thick")
    for al in alloys:
        cells = [thr(al, dk, "near_uniaxial") for dk in ("large_stem_limit", "dbh_min_sensor_on_bark",
                                                           "dbh_min_sensor_on_xylem_thin_contact_78",
                                                           "dbh_min_sensor_on_xylem_thick_side_78")]
        print(f"    {al:20s} σ_e/E_s ×{fm[al]:.2f}  near-uniaxial " + " | ".join(f"{x:5.0f}" for x in cells)
              + f"   any-state large {thr(al, 'large_stem_limit', 'any_state'):5.0f}"
              + f"   axial term {axial_rms[al]['over_sf2_line']:.2f} of the SF-2 line")
    print(f"  ligament field — periodic, uniaxial-state READING (rungs /{', /'.join(map(str, s106.PERIODIC_RUNGS))}; "
          f"energy identity worst {identity_worst:.1e}): peak / (E_s·ε) over rungs × measures, and SF 2 binds-above (µε) "
          f"on a large stem at t_L = 1, at every sampled angle; knife-edges: {knife_txt or 'none'}")
    for q in PEAK_QUANTILES:
        print(f"    {q:5s} " + " · ".join(f"θ {tk}° {lig_band(q, tk)}" for tk in tks) + "   "
              + ", ".join(f"{al} {lig[al][f'large_stem_limit|{q}|sf2']['any_sampled_angle']:.0f}" for al in alloys))
    for pn in premises:
        for bn in bonds:
            fz = forces[pn][bn]
            print(f"  {pn:18s} {bn:17s} F (upper, adverse): state2 {f_newton(fz['state2_rigid_bark_per_mm'], 'upper_whisker'):6.0f}"
                  f" · state3 F_A {f_newton(fz['state3_bond_per_mm_max_over_ties'], 'upper_whisker'):6.0f}"
                  f" · rigid sleeve {f_newton(fz['rigid_sleeve_bond_per_mm'], 'upper_whisker'):6.0f} N")
    for tag, cell, kind in (("Zone 1, mature stiff cap", z1_cap, "zone1"), ("Zone 3/disc, (b), rigid bark", z3_cap, "zone3")):
        print(f"  {tag}: {cell['force_N']:.0f} N   [K_f@SF2 one-sided/reversed/on-preload · mean@SF2]")
        for m, v in cell["members"].items():
            routes = [("printed", v["printed"][ALLOY_BASELINE] if kind == "zone1" else v["printed"])]
            if kind == "zone3":
                routes.append(("cnc", v["cnc_wrought"]))
            for rname, a4 in routes:
                mean = a4["mean_at_sf2_MPa"]
                print(f"    {m:46s} {rname:7s} σ_n {v['sigma_n_MPa']:6.2f}  "
                      + "/".join(f"{a4[cy]['kf_at_sf2']:.2f}" for cy in CYCLES)
                      + f"  {f'{mean:.0f}' if mean is not None else '—':>5s}")
    print("\n" + verdict)
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
