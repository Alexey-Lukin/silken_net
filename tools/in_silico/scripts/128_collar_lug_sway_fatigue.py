#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""128 — what the stem's sway puts into the bayonet collar and the lug root of the Zone 3 flange, path by path
(00_07 HW.23, the leg «решта напружень Ti-деталей, яких `105` не рахує», its first item: «комір фланця Zone 3 і корінь
вушка байонета (втома від гойдання; `73` судить лише статику)»). Closed forms on `105`'s own plate; no FE solve.

WHY. `105` prices the flange disc under the bark's bearing force and says, in its CANNOT (5), that the collar and the
lug root are not its. `73` judges them statically (axial retention, lug-root shear, ice) and `89` the clamp's thermal
swing — low-cycle forms. So nothing in the tree gives the sway's cyclic stress at the two places, and the S-N plan
(docs/protocols/anchor/sn_fatigue_test_plan.md §1.3) names `73` as the only instrument there.

GEOMETRY (02_02 §4.4 — ratified, not yet drawn). The collar is one Ti body with the flange (`Assembly.RequiredLugZMm`):
a raised ring standing on the disc's top face inside the socket band `73` takes from the manifests (its cache — the
band's radii, the collar height = the lock-groove height, the lug count and radius), carrying the three lugs at that
height. The wall sits somewhere in the band: both edges are read, the adverse one kept per reading; the collar's height
at `73`'s value and at the lug's top (+ the lug radius), the adverse one kept. Walls: `73`'s rows (the print floor
first) and the ratified member 0.28 mm (a LOWER bound, `89`'s input). The lug's engaged length is `89`'s (the pocket
less the clearance): the flange CEM's 2.0 mm protrusion is a mid-disc placeholder `89` rejects (in-silico #41).

PATHS (in-silico §Critical Rules #15), by what couples the sway to the two places:
  C1  the disc's bending under the bark's bearing force F_F (`105` path S2, state 2) TILTS the collar's foot: the
      collar is monolithic with the disc, so its generator turns with the disc's normal at the collar radius, and the
      disc's top fibre moves it radially by −(t/2)·slope. A short cylinder whose foot is turned bends at the foot.
      Computed.
  C2  the capsule's inertia and the wind's drag on it reach the lugs. The bayonet is a preloaded joint (02_02 §4.3,
      deflection-controlled), so an external load changes the lug load by at most itself; taken whole, on one lug.
      `87`'s mass and drag ceilings and its largest acceleration reading. Computed (a ceiling).
  C3  the same disc bending changes the clamp loop's length (the radome's rim seat and the collar's foot sit at
      different radii): ΔC = k·Δw, Δw ≤ the disc's deflection range between the rim seat's inner edge (`52`'s seal
      land) and the disc's edge — every radius the loop can close at — at `105`'s largest force, over the plate
      readings. k is the loop's stiffness, which nothing in the tree gives (`89` grids it), so ΔC is printed per unit k
      and on `89`'s grid. The bending is axisymmetric, so ΔC shares equally over the lugs (unlike C2, whole on one).
  C4  if the rim slips (`87` (A) below its normal force) the capsule bears laterally on the collar wall: weight,
      inertia and drag — the forces of C2. Named, bounded by C2's force.
  C5  stem torsion (`77`): microns of rotation of the capsule as a body — fretting at the lugs, not a stress.
  MEANS the clamp (`88`/`89`): a membrane tension in the collar and, at the lug root, an ECCENTRIC load — the ledge
      presses the lug's flank over its engaged length off the wall, so the wall bends under it. `73` takes pure shear
      and `89` names this bending as not computed (its path 4). Printed here as two NAMED readings, neither a bound: a
      strip as wide as the lug (no spreading) ⊥ a 45° spread from the lug down to the foot (ours, not a standard).
  ICE / CLAMP SWING — `73` case C / `89`: low-cycle, outside this endurance form.

MODEL.
  Disc: `105`'s axisymmetric Kirchhoff annular plate (outer edge free) and its load cases, imported, not copied. Three
  plate readings, named by how they are built: «uniform» — `105`'s plate (3 mm, inner edge clamped on a rigid shank);
  «grooved» — the same with the O-ring groove (`52`'s applied gland: an annulus between the shank and the collar, the
  disc 1.66 mm there, ~6× softer in bending), which `105`'s uniform plate does not carry and which raises the turn at
  the collar; «grooved + root» — the grooved plate whose inner edge turns on a rotational spring, the built-in-edge
  compliance of O'Donnell 1960 (J. Appl. Mech. 27:461, DOI 10.1115/1.3644025 — verified via Crossref; the plane-strain
  form θ = 16.67·M·(1 − ν²)/(π·E·t²) is the commonly quoted one, NOT read in the paper's body here: a reading, not a
  constant of this tree). `105`'s clamped root is the adverse end for ITS question (the stress at the root) and the
  kind end for this one (the turn at the collar); a Ø9 shank is softer than O'Donnell's half-space, so the root reading
  itself may under-state the turn — the price of twice its compliance is printed beside it. Solved by finite
  differences in conservative form (d(r·M_r)/dr − M_θ = r·Q, M_r on half-nodes); Kirchhoff across a thickness step is
  itself an idealisation (the step's local field is not resolved).
  Collar: an axisymmetric thin cylinder (radius R, wall t, height H), D·w'''' + (E·t/R²)·w = 0, foot at the disc's top
  fibre — w(0) = −(t_d/2)·s, w'(0) = −s — and a free top (M = Q = 0): the exact four-constant solution. Valid as a thin
  shell only while R/t ≥ 10 (ours); thicker walls are printed, flagged, and kept out of the verdict. Two readings of s:
  FOLLOW — the plate's slope with the collar absent (an upper bound on the turn: the collar's elastic foot can only
  resist it) ⊥ COUPLED — s/(1 + K_c·C_d), K_c the foot's ENERGY stiffness per unit turn (2U at unit slope, U the
  shell's strain energy per mm of circumference — the quantity conjugate to the disc's turn once the foot's shift is tied
  to it; its moment alone omits the radial shear's lever) and C_d the plate's turn per unit ring moment at R on the
  same plate reading. COUPLED is the model's reading; FOLLOW stays a bound on the stress (a LOWER bound on K_f) within one plate reading,
  and loose where K_c·C_d is not small — above K_c·C_d ≈ 0.3 (ours) the coupled table rests on the one-dof coupling and
  cannot steer the wall. The
  collar's net radial force on the disc's mid-plane (its membrane share) is not coupled. σ: axial bending 6M/t² and
  hoop E·w/R + ν·6M/t², the largest magnitude over both fibres at the foot, and 6·max|M|/t² over the height, whichever
  is larger.
  Lug: C2 + C3(k) force on ONE lug; pure shear over `73`'s root area (its idealisation; area = lugs × lug diameter ×
  wall, held to `73`'s rows) and the two bending readings at the foot of the wall, σ = 6·F·e/(w·t²), e = engaged/2 + t/2.
  Soderberg (`86`, `105`'s form: K_f on both terms, `55`'s endurance markers and SF line, three cycle readings). The
  collar's slope is driven by a bearing, so two readings apply — one-sided (no preload) and on a preload ≥ F (the
  bark's growth preload, unbounded in the tree), and the one-sided K_f at SF 2 is the unnotched SF on a preload; the
  reversed reading (a tie's) is kept in the cache only for completeness. «Printed» is `55`'s AS-BUILT SLM marker (its
  0.5 derate for the rough surface and porosity), NOT the SLM + HIP route, whose endurance the tree has no marker for —
  so the verdict prints, for that route, the endurance at which the foot keeps SF 2 unnotched on a preload.

CONTROLS (what each CAN / CANNOT catch): `105`'s disc stress per newton reproduced bit-for-bit (a drift of geometry,
cases or plate — not a wrong plate model); `105`'s closed-form slope ⊥ the finite-difference plate on a uniform disc
(a wrong slope recovery or FD stencil on a constant D); a piecewise closed form over the three thickness zones, with
and without the root spring ⊥ the finite-difference plate (a wrong variable-thickness stencil, a dropped groove, a wrong
spring condition — not the plate equation, shared); the root spring LOWERS the root moment (a spring of the wrong
sign raises it); the shell's exact form ⊥ its semi-infinite limits 2βD·s and 2β²D·w at βH = 20 (wrong basis or
constants) and ⊥ a finite-difference shell at the real heights (the free top's conditions — not the shell equation,
shared); the foot's energy stiffness at βH = 20 ⊥ 2βD·(1 + β·t_d + 2·(β·t_d/2)²), the semi-infinite value for the
foot's tied shift (a flipped or dropped shift term in the foot's kinematics); the ring compliance stable when its
couple's lever is halved (a lever too coarse for the grid); `105`'s Soderberg SF reproduced on its own cell (a formula
drift); `73`'s lug-root areas reproduced (an area drift).

CAN: per wall, plate reading and placement, the collar foot's nominal stress per newton of F_F and at `105`'s forces,
FOLLOW ⊥ COUPLED, the K_f at which it reaches SF 2 per cycle reading and route, and the wall where it is least inside
the thin-shell range; the lug's sway force as C2 + k·Δw, its stress per newton in shear and in both bending readings,
and the clamp mean's bending in both.
CANNOT: (1) any K_t — the collar foot's fillet, the lug root; (2) the lug on the wall as a shell (a local patch moment
on a cylinder — FE): the two bending readings bracket nothing, so no lug-root SF is a claim; (3) the collar drawn
(02_02 §4.4: not modelled) — the band, height and lug placement are `73`'s and `89`'s; (4) the mature-state bearing
force (`105` bounds state 2 only) and any static mean of the disc (cold, heat, growth, humidity — `105` MEANS);
(5) the shank root's true compliance (O'Donnell's half-space is a reading; a softer root turns the collar more) and
the shank's diameter (the CEM's placeholder, as `105`; the canon nominal lands with the collar — a wider shank shortens
the annulus and lowers the turn), the
collar's membrane coupling to the disc, the ring's lift between lugs, the lugs' unequal sharing (C2 puts it all on
one); (6) walls with R/t < 10 (thin-shell theory).

Run:  conda activate silken_md
      python tools/in_silico/scripts/128_collar_lug_sway_fatigue.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Cyclic stress from stem sway at the bayonet collar and the lug root of the Zone 3 flange: the "
                  "collar as a short cylinder whose foot the bending disc turns (on the disc model and bearing forces "
                  "of script 105, with the O-ring groove and a compliant root as named plate readings), the lug's "
                  "sway force ceiling, and two named readings of the clamp's eccentric bending of the wall under a "
                  "lug; closed forms with finite-difference, piecewise closed-form and limit controls.")

MECH = CACHE_DIR / "mechanical"
CEM = REPO_ROOT / "tools/cad/cem"
OUT = MECH / "collar_lug_sway_fatigue.json"
RATIFIED_WALL_MM = 0.28        # 02_02 §4.4 member (a LOWER bound) — asserted against `89`'s input below
ODONNELL = 16.67               # O'Donnell 1960 built-in edge, θ = ODONNELL·M·(1 − ν²)/(π·E·t²) — a reading (docstring)
ROOT_PRICE = 2.0               # the root compliance's price: the turn at twice O'Donnell's (ours, a sensitivity only)
RT_MIN_THIN = 10.0             # thin-shell validity, R/t (ours)
KCD_STEER = 0.3                # the collar's coupling above which the table rests on the one-dof coupling (ours)
EPS_RING_MM = 0.05             # the ring couple's lever (≈ 29 steps of `plate_fd`'s grid)
H_LIMIT_BETA = 20.0            # βH of the semi-infinite controls
PLATE_N = 6000
READINGS = ("follow", "coupled")
ROUTES = ("printed", "cnc_wrought")


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module        # dataclasses under postponed annotations resolve their module by name
    spec.loader.exec_module(module)
    return module


s105 = _load("s105_128", "105_printed_part_sway_stress.py")
s86 = _load("s86_128", "86_coaxiality_allocation.py")
s55 = s86.s55
NU = s105.NU_SOLID
CYCLES = s105.CYCLES


def down2(x: float) -> float:
    return math.floor(x * 100.0) / 100.0


def up2(x: float) -> float:
    return math.ceil(x * 100.0) / 100.0


def plate_fd(b: float, a: float, shear, nu: float, d_of_r, root_c: float = 0.0, n: int = PLATE_N):
    """Axisymmetric Kirchhoff annular plate with bending stiffness D(r), conservative form d(r·M_r)/dr − M_θ = r·Q,
    M_r on half-nodes; inner edge φ(b) = root_c·M_r(b) (root_c = 0: clamped), outer edge M_r(a) = 0 (second-order
    one-sided). Returns (r, slope, deflection from the shank, M_r(b))."""
    r = np.linspace(b, a, n + 1)
    h = r[1] - r[0]
    mat = np.zeros((n + 1, n + 1))
    rhs = np.zeros(n + 1)
    db = d_of_r(b)
    mat[0, 0] = 1.0 - root_c * db * (-3.0 / (2.0 * h) + nu / b)
    mat[0, 1] = -root_c * db * (4.0 / (2.0 * h))
    mat[0, 2] = -root_c * db * (-1.0 / (2.0 * h))
    for i in range(1, n):
        rp, rm = r[i] + h / 2.0, r[i] - h / 2.0
        dp, dm, di = d_of_r(rp), d_of_r(rm), d_of_r(r[i])
        mat[i, i + 1] += rp * dp / h * (1.0 / h + nu / (2.0 * rp)) - di * nu / (2.0 * h)
        mat[i, i] += rp * dp / h * (-1.0 / h + nu / (2.0 * rp)) - rm * dm / h * (1.0 / h + nu / (2.0 * rm)) - di / r[i]
        mat[i, i - 1] += -rm * dm / h * (-1.0 / h + nu / (2.0 * rm)) + di * nu / (2.0 * h)
        rhs[i] = r[i] * shear(r[i])
    mat[n, n], mat[n, n - 1], mat[n, n - 2] = 3 / (2 * h) + nu / a, -2 / h, 1 / (2 * h)
    phi = np.linalg.solve(mat, rhs)
    w = np.concatenate([[0.0], np.cumsum(0.5 * (phi[1:] + phi[:-1]) * h)])
    m_rb = db * ((-3.0 * phi[0] + 4.0 * phi[1] - phi[2]) / (2.0 * h) + nu * phi[0] / b)
    return r, phi, w, float(m_rb)


def plate_zones(b: float, a: float, shear, nu: float, zones: list[tuple[float, float, float]], root_c: float,
                at: tuple[float, ...], n: int = 200000):
    """Independent control: the same plate in closed form per zone of constant D (up to the quadrature of the shear):
    φ = I/(D·r) + C1·r/2 + C2/r, I = ∫_b^r ρ·G dρ, G = ∫_b^r Q; φ and M_r continuous at each step, the root spring and
    the free edge as in `plate_fd`. Returns (slopes at `at`, M_r(b))."""
    r = np.linspace(b, a, n + 1)
    q = np.array([shear(x) for x in r])
    g = np.concatenate([[0.0], np.cumsum(0.5 * (q[1:] + q[:-1]) * np.diff(r))])
    rg = r * g
    i_ = np.concatenate([[0.0], np.cumsum(0.5 * (rg[1:] + rg[:-1]) * np.diff(r))])

    def gi(x: float) -> tuple[float, float]:
        return float(np.interp(x, r, g)), float(np.interp(x, r, i_))

    def phi_row(k: int, x: float):            # (coefficients on all 2·nz unknowns, known part) of φ_k(x)
        dk = zones[k][2]
        _, ix = gi(x)
        row = np.zeros(2 * len(zones))
        row[2 * k], row[2 * k + 1] = x / 2.0, 1.0 / x
        return row, ix / (dk * x)

    def m_row(k: int, x: float):              # … of M_r,k(x) = D_k·(φ' + ν·φ/r)
        dk = zones[k][2]
        gx, ix = gi(x)
        row = np.zeros(2 * len(zones))
        row[2 * k] = dk * (0.5 + nu / 2.0)
        row[2 * k + 1] = dk * (-1.0 / x ** 2 + nu / x ** 2)
        known = dk * (gx / dk - ix / (dk * x ** 2) + nu * ix / (dk * x ** 2))
        return row, known

    nz = len(zones)
    mat, rhs = np.zeros((2 * nz, 2 * nz)), np.zeros(2 * nz)
    pr, pk = phi_row(0, b)
    mr, mk = m_row(0, b)
    mat[0], rhs[0] = pr - root_c * mr, -(pk - root_c * mk)
    row = 1
    for k in range(nz - 1):
        x = zones[k][1]
        p1, k1 = phi_row(k, x)
        p2, k2 = phi_row(k + 1, x)
        mat[row], rhs[row] = p1 - p2, -(k1 - k2)
        m1, j1 = m_row(k, x)
        m2, j2 = m_row(k + 1, x)
        mat[row + 1], rhs[row + 1] = m1 - m2, -(j1 - j2)
        row += 2
    ma, ja = m_row(nz - 1, a)
    mat[row], rhs[row] = ma, -ja
    cvec = np.linalg.solve(mat, rhs)
    out = []
    for x in at:
        k = next(j for j, z in enumerate(zones) if z[0] <= x <= z[1])
        pr, pk = phi_row(k, x)
        out.append(float(pr @ cvec + pk))
    mr, mk = m_row(0, b)
    return out, float(mr @ cvec + mk)


def shell_basis(beta: float, h: float, x, order: int) -> np.ndarray:
    """d^order/dx^order of e^{β(x−H)}cos βx, e^{β(x−H)}sin βx, e^{−βx}cos βx, e^{−βx}sin βx (scaled for βH ≫ 1)."""
    out = []
    for lam, shift in ((beta * (1 + 1j), -beta * h), (beta * (-1 + 1j), 0.0)):
        v = lam ** order * np.exp(lam * np.asarray(x, dtype=float) + shift)
        out += [v.real, v.imag]
    return np.array(out)


def collar_shell(e_mpa: float, nu: float, r_mm: float, t_mm: float, h_mm: float, w0: float, th0: float,
                 n: int = 4000) -> dict:
    """Thin axisymmetric cylinder, foot w(0) = w0, w'(0) = th0, top free (w'' = w''' = 0 at H). Moments N·mm/mm;
    U = ½∫(D·w''² + (E·t/R²)·w²)dx, the strain energy per mm of circumference."""
    d = e_mpa * t_mm ** 3 / (12.0 * (1.0 - nu ** 2))
    kf = e_mpa * t_mm / r_mm ** 2
    beta = (3.0 * (1.0 - nu ** 2) / (r_mm * t_mm) ** 2) ** 0.25
    mat = np.array([shell_basis(beta, h_mm, 0.0, 0), shell_basis(beta, h_mm, 0.0, 1),
                    shell_basis(beta, h_mm, h_mm, 2), shell_basis(beta, h_mm, h_mm, 3)])
    cf = np.linalg.solve(mat, np.array([w0, th0, 0.0, 0.0]))
    xs = np.linspace(0.0, h_mm, n + 1)
    w = cf @ shell_basis(beta, h_mm, xs, 0)
    w2 = cf @ shell_basis(beta, h_mm, xs, 2)
    m = -d * w2
    energy = 0.5 * float(np.trapezoid(d * w2 ** 2 + kf * w ** 2, xs))
    resid = max(abs(cf @ shell_basis(beta, h_mm, h_mm, 2)), abs(cf @ shell_basis(beta, h_mm, h_mm, 3))) * beta ** -2
    hoop_m = e_mpa * w0 / r_mm
    bend0 = 6.0 * m[0] / t_mm ** 2
    foot = max(max(abs(sg * bend0), abs(hoop_m + nu * sg * bend0)) for sg in (1, -1))
    return {"beta": beta, "beta_h": beta * h_mm, "D": d, "M0": float(m[0]), "energy": energy,
            "sigma": max(foot, 6.0 * float(abs(m).max()) / t_mm ** 2), "bc_residual": float(resid)}


def collar_shell_fd(e_mpa: float, nu: float, r_mm: float, t_mm: float, h_mm: float, w0: float, th0: float,
                    n: int = 2000) -> float:
    """D·w'''' + (E·t/R²)·w = 0 by central differences with two ghost nodes at each end; returns M at the foot."""
    d = e_mpa * t_mm ** 3 / (12.0 * (1.0 - nu ** 2))
    k = e_mpa * t_mm / r_mm ** 2
    hh = h_mm / n
    size = n + 5                                 # nodes −2 … n+2

    def ix(i: int) -> int:
        return i + 2

    mat, rhs = np.zeros((size, size)), np.zeros(size)
    row = 0
    for i in range(0, n + 1):
        for j, c in zip(range(i - 2, i + 3), (1, -4, 6, -4, 1), strict=True):
            mat[row, ix(j)] += d * c / hh ** 4
        mat[row, ix(i)] += k
        row += 1
    mat[row, ix(0)], rhs[row] = 1.0, w0
    row += 1
    mat[row, ix(1)], mat[row, ix(-1)], rhs[row] = 1 / (2 * hh), -1 / (2 * hh), th0
    row += 1
    mat[row, ix(n + 1)], mat[row, ix(n)], mat[row, ix(n - 1)] = 1 / hh ** 2, -2 / hh ** 2, 1 / hh ** 2
    row += 1
    for j, c in zip(range(n - 2, n + 3), (-0.5, 1.0, 0.0, -1.0, 0.5), strict=True):
        mat[row, ix(j)] += c / hh ** 3
    w = np.linalg.solve(mat, rhs)
    return float(-d * (w[ix(1)] - 2 * w[ix(0)] + w[ix(-1)]) / hh ** 2)


def assess(sig: float, row: dict, route: str) -> dict:
    """`105`'s `assess`, the same form (held to its cache in main)."""
    se = row["endurance_printed_MPa"] if route == "printed" else row["endurance_wrought_MPa"]
    out = {}
    for cyc in CYCLES:
        sa, sm = {"one_sided": (sig / 2.0, sig / 2.0), "reversed": (sig, 0.0), "on_preload": (sig, sig)}[cyc]
        sf = s86.soderberg(sa, sm, se, row["yield_MPa"])[0] if sig > 0 else math.inf
        out[cyc] = {"sf_at_kf1": sf, "kf_at_sf2": sf / s55.INFINITE_LIFE_SF}
    room = 1.0 / s55.INFINITE_LIFE_SF - sig / se
    out["mean_at_sf2_MPa"] = row["yield_MPa"] * room if room > 0 else None
    return out


def main() -> int:
    banner("128 — sway at the bayonet collar and the lug root: the disc tilts the collar's foot; the lug's force ceiling")
    d105 = json.loads((MECH / "printed_part_sway_stress.json").read_text(encoding="utf-8"))
    d73 = json.loads((MECH / "collar_wall_inversion.json").read_text(encoding="utf-8"))
    d87 = json.loads((MECH / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    d89 = json.loads((MECH / "bayonet_thermal_clamp.json").read_text(encoding="utf-8"))
    d103 = json.loads((MECH / "anchor_wood_share.json").read_text(encoding="utf-8"))
    d52 = json.loads((MECH / "z_stack_tolerance.json").read_text(encoding="utf-8"))
    flange = json.loads((CEM / "cathode_flange.json").read_text(encoding="utf-8"))
    sleeve = json.loads((CEM / "zone2_sleeve.json").read_text(encoding="utf-8"))

    p4 = ALLOY_PROPERTIES[ALLOY_BASELINE]
    e_ti = p4["E_GPa"] * 1e3
    row4 = {"yield_MPa": p4["yield_MPa"], "endurance_printed_MPa": s55.endurance_MPa(p4["yield_MPa"]),
            "endurance_wrought_MPa": s55.endurance_MPa(p4["yield_MPa"], derate=s55.WROUGHT_DERATE)}
    geo73 = d73["geometry"]
    assert geo73["alloy"] == ALLOY_BASELINE, "73 judged another alloy — re-read"
    assert abs(d89["inputs"]["ratified_member_wall_mm_02_02"] - RATIFIED_WALL_MM) < 1e-12, "the ratified wall moved"
    rows73 = d73["case_b_lug_root_shear"]["rows"]
    walls = sorted({r["wall_mm"] for r in rows73} | {RATIFIED_WALL_MM})
    band = (geo73["band_r_inner_mm"], geo73["band_r_outer_mm"])
    n_lugs, r_lug = geo73["bayonet_lugs"], geo73["lug_radius_mm"]
    assert (n_lugs, r_lug) == (flange["bayonet_lugs"], flange["lug_radius_mm"]), "73 and the CEM disagree on the lugs"
    engaged = d89["inputs"]["lug_line_contact"]["engaged_length_mm"]["socket_pocket_minus_clearance"]
    assert engaged < flange["lug_protrusion_mm"], "the CEM's placeholder protrusion now fits the pocket — re-read 89"
    heights = (geo73["collar_height_mm"], geo73["collar_height_mm"] + r_lug)

    # ── The disc: `105`'s plate and load cases, rebuilt from the same sources and held to its cache ────────────────────
    b, a = flange["shank_diameter_mm"] / 2.0, flange["flange_diameter_mm"] / 2.0
    c = d103["geometry"]["channel_radius_mm"]
    t_d = flange["flange_thickness_mm"]
    sleeve_face = (sleeve["bore_diameter_mm"] / 2.0, c)
    gl = d52["applied_gland"]
    rim_in = gl["radome_seal_land_r_mm"][0]                              # the rim's innermost seat (`52`)
    groove = (gl["flange_groove_r_mm"][0], gl["flange_groove_r_mm"][1])
    t_groove = t_d - gl["flange_groove_depth_mm"]
    assert c < rim_in < band[0] < band[1] < a, "the rim seat or the socket band left the disc's outer annulus"
    assert b < groove[0] < groove[1] < band[0], "the groove is no longer between the shank and the collar"
    cases = {
        "b_pull_at_shank|uniform_over_bark_annulus": ((b, b), (c, a)),
        "b_pull_at_shank|rim_only_dished_seat": ((b, b), (a, a)),
        "b_pull_at_shank|channel_edge_only": ((b, b), (c, c)),
        "a_sleeve_face_press|uniform_over_bark_annulus": (sleeve_face, (c, a)),
        "a_sleeve_face_press|rim_only_dished_seat": (sleeve_face, (a, a)),
    }
    assert set(cases) == set(d105["disc_MPa_per_N"]), "105's disc cases changed — rebuild the list"
    d_disc = e_ti * t_d ** 3 / (12.0 * (1.0 - NU ** 2))
    d_groove = e_ti * t_groove ** 3 / (12.0 * (1.0 - NU ** 2))
    c_root = ODONNELL * (1.0 - NU ** 2) / (math.pi * e_ti * t_d ** 2)

    def d_grooved(x: float) -> float:
        return d_groove if groove[0] <= x <= groove[1] else d_disc

    plates = {"uniform": (lambda x: d_disc, 0.0), "grooved": (d_grooved, 0.0), "grooved_root": (d_grooved, c_root)}
    zones = [(b, groove[0], d_disc), (groove[0], groove[1], d_groove), (groove[1], a, d_disc)]
    radii = sorted({band[0] + t / 2.0 for t in walls} | {band[1] - t / 2.0 for t in walls})
    disc = {}
    controls = {"plate_105_reproduced": {}, "slope_closed_vs_fd_uniform": {}, "slope_zones_vs_fd": {},
                "root_spring_lowers_root_moment": {}}
    for name, (ld, rc) in cases.items():
        sh = s105.plate_shear(1.0, ld, rc)
        _, m_r, m_t = s105.plate_moments(b, a, sh, NU)
        mine = 6.0 * max(abs(float(m_r[0])), abs(float(m_t[0]))) / t_d ** 2
        cached = d105["disc_MPa_per_N"][name]["shank_root_MPa_per_N"]
        controls["plate_105_reproduced"][name] = [mine, cached]
        assert abs(mine - cached) <= 1e-9 * max(cached, 1e-12), f"105's disc not reproduced: {name}"
        rr, m_r, m_t = s105.plate_moments(b, a, sh, NU)
        sd = rr * (m_t - NU * m_r) / (1.0 - NU ** 2)
        disc[name] = {}
        m_root = {}
        for pl, (dfun, rcomp) in plates.items():
            rf, phi, w, m_rb = plate_fd(b, a, sh, NU, dfun, rcomp)
            m_root[pl] = m_rb
            ends = (radii[0], radii[-1])
            fd = [float(np.interp(x, rf, phi)) for x in ends]
            if pl == "uniform":
                cl = [float(np.interp(x, rr, sd)) / d_disc for x in ends]
                controls["slope_closed_vs_fd_uniform"][name] = {"closed": cl, "fd": fd}
                for u, v in zip(cl, fd, strict=True):
                    assert abs(u - v) <= 2e-3 * max(abs(u), abs(v), 1e-15), f"slope closed form ⊥ FD: {name}"
            else:
                zc, zm = plate_zones(b, a, sh, NU, zones, rcomp, ends)
                controls["slope_zones_vs_fd"][f"{name}|{pl}"] = {"zones": zc, "fd": fd, "Mr_b": [zm, m_rb]}
                for u, v in [*zip(zc, fd, strict=True), (zm, m_rb)]:
                    assert abs(u - v) <= 2e-3 * max(abs(u), abs(v), 1e-15), f"piecewise closed form ⊥ FD: {name} {pl}"
            loop = (rf >= rim_in) & (rf <= a)
            disc[name][pl] = {"slope_per_N": {f"{x:.4f}": float(np.interp(x, rf, phi)) for x in radii},
                              "deflection_range_rim_seat_to_edge_mm_per_N": float(w[loop].max() - w[loop].min())}
        controls["root_spring_lowers_root_moment"][name] = [m_root["grooved_root"], m_root["grooved"]]
        assert abs(m_root["grooved_root"]) < abs(m_root["grooved"]), f"the root spring must relieve the root: {name}"
        rf2, phi2, _, _ = plate_fd(b, a, sh, NU, d_grooved, ROOT_PRICE * c_root)
        disc[name]["price_root_x2_over_root"] = {
            k: float(np.interp(float(k), rf2, phi2)) / v for k, v in disc[name]["grooved_root"]["slope_per_N"].items()}
        for pl in ("grooved", "grooved_root"):
            disc[name][f"{pl}_over_uniform"] = {k: v / disc[name]["uniform"]["slope_per_N"][k]
                                                for k, v in disc[name][pl]["slope_per_N"].items()}

    def ring_compliance(rad: float, pl: str, eps: float = EPS_RING_MM) -> float:
        """The plate's turn per unit ring moment (N·mm per mm of circumference) at R: ring forces at R and R + ε."""
        dfun, rcomp = plates[pl]
        f = 2.0 * math.pi * rad / eps
        rf, phi, _, _ = plate_fd(b, a, s105.plate_shear(f, (rad, rad), (rad + eps,) * 2), NU, dfun, rcomp)
        return abs(float(np.interp(rad, rf, phi)))

    # ── Controls on the collar's shell, the ring compliance, Soderberg and the lug areas ───────────────────────────────
    def foot(s: float) -> tuple[float, float]:
        """The collar foot's (shift, turn) on the disc's top fibre for a disc slope s."""
        return -t_d / 2.0 * s, -s

    t0, r0 = RATIFIED_WALL_MM, 0.5 * (band[0] + band[1])
    beta0 = (3.0 * (1.0 - NU ** 2) / (r0 * t0) ** 2) ** 0.25
    d0 = e_ti * t0 ** 3 / (12.0 * (1.0 - NU ** 2))
    long_h = H_LIMIT_BETA / beta0
    controls["shell_semi_infinite_limit"] = {
        "turn_only": [abs(collar_shell(e_ti, NU, r0, t0, long_h, 0.0, 1e-3)["M0"]), 2.0 * beta0 * d0 * 1e-3],
        "shift_only": [abs(collar_shell(e_ti, NU, r0, t0, long_h, 1e-3, 0.0)["M0"]), 2.0 * beta0 ** 2 * d0 * 1e-3]}
    for got, want in controls["shell_semi_infinite_limit"].values():
        assert abs(got - want) <= 1e-6 * want, "the shell's exact form does not reach the semi-infinite limit"
    bt = beta0 * t_d
    k_energy_lim = 2.0 * collar_shell(e_ti, NU, r0, t0, long_h, *foot(1.0), n=200000)["energy"]
    controls["foot_energy_stiffness_semi_infinite"] = [k_energy_lim, 2.0 * beta0 * d0 * (1 + bt + 2 * (bt / 2) ** 2)]
    assert abs(k_energy_lim - controls["foot_energy_stiffness_semi_infinite"][1]) <= 1e-4 * k_energy_lim, \
        "the foot's tied shift is not what the kinematics say"
    controls["shell_exact_vs_fd"] = {}
    for h in heights:
        ex = collar_shell(e_ti, NU, r0, t0, h, *foot(1e-3))
        fdm = collar_shell_fd(e_ti, NU, r0, t0, h, *foot(1e-3))
        controls["shell_exact_vs_fd"][f"{h:g}"] = {"M0_exact": ex["M0"], "M0_fd": fdm, "bc_residual": ex["bc_residual"]}
        assert abs(ex["M0"] - fdm) <= 2e-3 * abs(ex["M0"]), "shell exact ⊥ FD disagree"
        assert ex["bc_residual"] < 1e-9, "the free top is not free"
    cd_full, cd_half = ring_compliance(r0, "grooved_root"), ring_compliance(r0, "grooved_root", EPS_RING_MM / 2.0)
    controls["ring_compliance_lever_halved"] = [cd_full, cd_half]
    assert abs(cd_full - cd_half) <= 1e-2 * cd_full, "the ring couple's lever is too coarse for the plate grid"
    k105 = next(iter(d105["zone3_members"]))
    m105 = next(iter(d105["zone3_members"][k105]["members"].values()))
    mine = assess(m105["sigma_n_MPa"], row4, "printed")["reversed"]["sf_at_kf1"]
    controls["soderberg_105_reproduced"] = [mine, m105["printed"]["reversed"]["sf_at_kf1"]]
    assert abs(mine - m105["printed"]["reversed"]["sf_at_kf1"]) <= 1e-9 * mine, "105's Soderberg not reproduced"

    def lug_area(t: float) -> float:
        return n_lugs * 2.0 * r_lug * t
    controls["lug_area_73_reproduced"] = {f"{r['wall_mm']:g}": [lug_area(r["wall_mm"]), r["shear_area_all_lugs_mm2"]]
                                          for r in rows73}
    for got, want in controls["lug_area_73_reproduced"].values():
        assert abs(got - want) <= 1e-9 * want, "73's lug-root area is no longer lugs × diameter × wall"

    # ── C1: the collar's foot — per wall, FOLLOW ⊥ COUPLED, each at its adverse plate, placement and height ────────────
    ring_cd = {(f"{x:.4f}", pl): ring_compliance(x, pl) for x in radii for pl in plates}
    unit = {(f"{x:.4f}", t, h): collar_shell(e_ti, NU, x, t, h, *foot(1.0)) for x in radii for t in walls
            for h in heights}
    thin = {f"{t:g}": (band[0] + t / 2.0) / t >= RT_MIN_THIN for t in walls}
    per_n = {}
    for name in cases:
        per_n[name] = {}
        for t in walls:
            cells = []
            for edge, rad in (("inner_edge", band[0] + t / 2.0), ("outer_edge", band[1] - t / 2.0)):
                for pl in plates:
                    s = disc[name][pl]["slope_per_N"][f"{rad:.4f}"]
                    cd = ring_cd[(f"{rad:.4f}", pl)]
                    for h in heights:
                        u = unit[(f"{rad:.4f}", t, h)]
                        k_c = 2.0 * u["energy"]
                        cells.append({"plate": pl, "edge": edge, "R_mm": rad, "H_mm": h, "beta_h": u["beta_h"],
                                      "Kc_Cd": k_c * cd, "follow": u["sigma"] * abs(s),
                                      "coupled": u["sigma"] * abs(s) / (1.0 + k_c * cd)})
            per_n[name][f"{t:g}"] = {rd: max(cells, key=lambda x, rd=rd: x[rd]) for rd in READINGS}
            per_n[name][f"{t:g}"]["thin_shell"] = thin[f"{t:g}"]
            per_n[name][f"{t:g}"]["by_plate"] = {
                pl: {rd: max(x[rd] for x in cells if x["plate"] == pl) for rd in READINGS} for pl in plates}

    collar = {}
    for key, v in d105["zone3_members"].items():
        pre = key.split("|")[0][0]
        f = v["force_N"]
        for name in cases:
            if not name.startswith(pre + "_"):
                continue
            for t in walls:
                for rd in READINGS:
                    sig = per_n[name][f"{t:g}"][rd][rd] * f
                    collar[f"{key}|{name}|wall{t:g}|{rd}"] = {
                        "force_N": f, "sigma_n_MPa": sig, "thin_shell": thin[f"{t:g}"],
                        "printed": assess(sig, row4, "printed"), "cnc_wrought": assess(sig, row4, "wrought")}

    def least(rd: str, route: str, cyc: str, t: float):
        rows = [(k, x) for k, x in collar.items() if k.endswith(f"|wall{t:g}|{rd}")]
        return min(rows, key=lambda kx: kx[1][route][cyc]["kf_at_sf2"])

    least_kf = {}
    for rd in READINGS:
        for route in ROUTES:
            for t in walls:
                kk, x = least(rd, route, "on_preload", t)
                least_kf[f"{rd}|{route}|wall{t:g}"] = {
                    "key_on_preload": kk, "sigma_n_MPa": x["sigma_n_MPa"], "thin_shell": thin[f"{t:g}"],
                    "kf_at_sf2": {cyc: least(rd, route, cyc, t)[1][route][cyc]["kf_at_sf2"] for cyc in CYCLES}}

    # ── C2 + C3: the lug's sway force; the lug root's stresses per newton ──────────────────────────────────────────────
    accel = max(d87["by_slope_reading"][rd]["stem_at_anchor_h_le_2m"]["accel_m_s2"] for rd in d87["by_slope_reading"])
    m_cap = d87["inputs"]["mass_ceiling_g"] / 1e3
    drag = d87["inputs"]["drag_ceiling_N"]
    k_keys = set()
    for sq in d89["by_squeeze_point"].values():
        for rdg in sq["by_reading"].values():
            for dl in rdg["by_delta_mm"].values():
                k_keys |= set(dl["lug_load_N_by_k"])
    k_grid = sorted(float(k) for k in k_keys)
    f_max = max(v["force_N"] for v in d105["zone3_members"].values())
    dw_um = max(disc[n][pl]["deflection_range_rim_seat_to_edge_mm_per_N"] for n in cases for pl in plates) \
        * f_max * 1e3
    c2 = m_cap * accel + drag
    lug_force = {"inertia_N": m_cap * accel, "drag_N": drag, "c2_N": c2, "dw_um_at_max_force": dw_um,
                 "c3_total_N_per_N_per_um": dw_um,
                 "on_one_lug_N_by_k": {f"{k:g}": c2 + k * dw_um / n_lugs for k in k_grid}}
    clamp_total = {sq: {"force_controlled_N": v["force_controlled_lug_load_N"],
                        "peek_dominated_lower_bound_N": v["PEEK_dominated_lower_bound_lug_load_N"]}
                   for sq, v in d89["by_squeeze_point"].items()}
    w_spread = 2.0 * geo73["collar_height_mm"]            # 45° from the lug's footprint to the foot (ours)
    lug = {}
    for t in walls:
        ecc = engaged / 2.0 + t / 2.0
        per = {"shear": n_lugs / lug_area(t), "strip": 6.0 * ecc / (2.0 * r_lug * t ** 2),
               "spread45": 6.0 * ecc / (w_spread * t ** 2)}
        lug[f"{t:g}"] = {
            "eccentricity_mm": ecc, "MPa_per_N_on_one_lug": per,
            "sway_amplitude_MPa_c2_only": {k: c2 * v for k, v in per.items()},
            "sway_amplitude_MPa_by_k": {kk: {k: f * v for k, v in per.items()}
                                        for kk, f in lug_force["on_one_lug_N_by_k"].items()},
            "clamp_mean_MPa": {f"{sq}|{rn}": {k: f_tot / n_lugs * per[k] for k in ("strip", "spread45")}
                               for sq, cl in clamp_total.items() for rn, f_tot in cl.items()}}

    # ── Verdict, from the data ─────────────────────────────────────────────────────────────────────────────────────
    def kf1(rd: str, route: str, t: float) -> float:
        return least_kf[f"{rd}|{route}|wall{t:g}"]["kf_at_sf2"]["one_sided"]

    tr = RATIFIED_WALL_MM
    worst_rat = least_kf[f"coupled|printed|wall{tr:g}"]["key_on_preload"]
    parts = worst_rat.split("|")
    name_rat = "|".join(parts[4:6])
    cell_rat = per_n[name_rat][f"{tr:g}"]["coupled"]
    f_rat = collar[worst_rat]["force_N"]
    sig_c = collar[worst_rat]["sigma_n_MPa"]
    sig_f = collar[worst_rat[: -len("coupled")] + "follow"]["sigma_n_MPa"]
    sig_u = per_n[name_rat][f"{tr:g}"]["by_plate"]["uniform"]["coupled"] * f_rat
    kf_u = assess(sig_u, row4, "printed")["one_sided"]["kf_at_sf2"]
    se_need = {rd: s / (1.0 / s55.INFINITE_LIFE_SF - s / row4["yield_MPa"]) for rd, s in (("coupled", sig_c),
                                                                                          ("follow", sig_f))}
    rkey = f"{cell_rat['R_mm']:.4f}"
    dr = disc[name_rat]
    ratios = {"groove": dr["grooved_over_uniform"][rkey],
              "root_over_groove": dr["grooved_root"]["slope_per_N"][rkey] / dr["grooved"]["slope_per_N"][rkey],
              "root_x2_over_root": dr["price_root_x2_over_root"][rkey]}
    kcd = {f"{t:g}": per_n[name_rat][f"{t:g}"]["coupled"]["Kc_Cd"] for t in walls}
    steer = [t for t in walls if thin[f"{t:g}"] and kcd[f"{t:g}"] <= KCD_STEER]
    steer_kf = [kf1("coupled", "printed", t) for t in steer]
    rat = lug[f"{tr:g}"]
    lo_cl = min(v["force_controlled_N"] for v in clamp_total.values())
    hi_peek = max(v["peek_dominated_lower_bound_N"] for v in clamp_total.values())
    ys = row4["yield_MPa"]
    lo_mean = {k: lo_cl / n_lugs * rat["MPa_per_N_on_one_lug"][k] for k in ("spread45", "strip")}
    hi_mean = {k: hi_peek / n_lugs * rat["MPa_per_N_on_one_lug"][k] for k in ("spread45", "strip")}
    cell_txt = " · ".join(x.replace("_", " ") for x in (*parts[:4], parts[5]))
    verdict = (
        f"C1 — the disc's bending under the bark's bearing force turns the collar's foot. The slope is driven by a "
        f"bearing, so of `105`'s cycle readings two apply: without a preload (one-sided) and on a preload at least the "
        f"force (unbounded in the tree); the reversed reading is a tie's. At the ratified wall {tr} mm the worst cell — "
        f"{cell_txt}, F_F {f_rat:.0f} N, on the «{cell_rat['plate'].replace('_', ' + ')}» plate — carries "
        f"σ_n {sig_c:.1f} MPa with the collar's foot coupled to the disc ({sig_f:.1f} following it, the upper bound): "
        f"without a preload it holds SF 2 up to K_f {down2(kf1('coupled', 'printed', tr)):.2f} on `55`'s as-built SLM "
        f"marker and {down2(kf1('coupled', 'cnc_wrought', tr)):.2f} on its wrought marker (following: "
        f"{down2(kf1('follow', 'printed', tr)):.2f} ⊥ {down2(kf1('follow', 'cnc_wrought', tr)):.2f}); on a preload ≥ F "
        f"the same numbers are its unnotched SF, so on the as-built marker it holds SF 2 there at no K_f, and the "
        f"SLM + HIP route, whose endurance the tree has no marker for, holds it unnotched only with an endurance of at "
        f"least {math.ceil(se_need['coupled']):.0f} MPa ({up2(se_need['coupled'] / ys):.2f} σ_y; "
        f"{math.ceil(se_need['follow']):.0f} following). On `105`'s uniform plate the same cell holds SF 2 without a "
        f"preload up to K_f {down2(kf_u):.2f} on the as-built marker: the shortfall is the grooved plate's — the O-ring "
        f"groove turns the free plate ×{ratios['groove']:.2f} at the collar (applied geometry; Kirchhoff across a step "
        f"about {(groove[1] - groove[0]) / t_groove:.1f} thicknesses wide), O'Donnell's root ×{ratios['root_over_groove']:.2f} "
        f"on top (a reading) and a root twice as compliant ×{ratios['root_x2_over_root']:.2f} more. Over the walls where "
        f"the collar's coupling K_c·C_d stays ≤ {KCD_STEER:g} ({', '.join(f'{t:g}' for t in steer)} mm) the coupled "
        f"one-sided K_f on the as-built marker is flat, {down2(min(steer_kf)):.2f}–{down2(max(steer_kf)):.2f}; above, "
        f"it rises only through that one-degree-of-freedom coupling (K_c·C_d {kcd['1']:.2f} at 1 mm) while following the "
        f"disc it falls, so the {tr} mm numbers do not transfer to a thicker wall. "
        f"C2 — the capsule's inertia and drag put at most {up2(c2):.2f} N on a lug (all on one). C3 — the same bending "
        f"moves the rim seat against the collar's foot by up to {math.ceil(dw_um * 10) / 10:.1f} µm at `105`'s largest "
        f"force, so the deflection-controlled loop swings the clamp by k × that, shared by the {n_lugs} lugs: at most "
        f"{up2(c2 + k_grid[0] * dw_um / n_lugs):.2f}–{math.ceil(c2 + k_grid[-1] * dw_um / n_lugs):.0f} N on a lug over "
        f"`89`'s grid of k ({k_grid[0]:g}–{k_grid[-1]:g} N/µm, which nothing in the tree pins); a compliant element in "
        f"the loop (`89`'s force-controlled branch) would cut it, at `89`'s named price — the rim's margin against "
        f"tipping, which hands the lateral loads to C4. The lug root's MEAN is the clamp's eccentric load: at {tr} mm "
        f"with the lug engaged {engaged:g} mm a newton on one lug bends the wall's foot by "
        f"{rat['MPa_per_N_on_one_lug']['spread45']:.1f} MPa (45° spread) to {rat['MPa_per_N_on_one_lug']['strip']:.1f} "
        f"MPa (strip), so `89`'s lowest clamp (force-controlled, {math.floor(lo_cl):.0f} N over {n_lugs} lugs) already "
        f"gives {math.floor(lo_mean['spread45']):.0f}–{math.floor(lo_mean['strip']):.0f} MPa "
        f"({down2(lo_mean['spread45'] / ys):.2f}–{down2(lo_mean['strip'] / ys):.2f} of the yield) and the "
        f"PEEK-dominated loop's lower bound at the window top ({math.floor(hi_peek):.0f} N) at least "
        f"{math.floor(hi_mean['spread45']):.0f}–{math.floor(hi_mean['strip']):.0f} MPa — neither reading is a bound, "
        f"`73`'s pure shear, on which the ratified wall stands, does not see this bending, and the lug root is "
        f"undecidable, statically and in fatigue, until the wall under a lug is a shell model (`89` path 4).")
    print(verdict)

    out = {
        "script": "128_collar_lug_sway_fatigue.py",
        "question": "the sway's cyclic stress at the bayonet collar's foot and at the lug root (00_07 HW.23)",
        "paths": {
            "C1_disc_tilts_collar_foot": "computed — 105's plate and bearing forces (state 2) on three plate readings, "
                                         "FOLLOW ⊥ COUPLED",
            "C2_capsule_inertia_and_drag_on_lugs": "computed — a ceiling (87's mass and drag ceilings, all on one lug)",
            "C3_clamp_loop_length_change": "computed — k × the disc's deflection range, shared by the lugs; k unknown",
            "C4_rim_slip_lateral_bearing_on_collar": "named — the forces of C2",
            "C5_stem_torsion": "77 — microns of rotation, fretting at the lugs, not a stress",
            "MEANS_clamp": "membrane tension in the collar · the lug root's eccentric bending: two named readings",
            "ICE_and_CLAMP_SWING": "73 case C · 89 — low-cycle, outside this form"},
        "inputs": {"alloy": ALLOY_BASELINE, "E_MPa": e_ti, "nu": NU,
                   "disc": {"b": b, "a": a, "c": c, "t": t_d, "groove_r": list(groove), "t_groove": t_groove,
                            "rim_seat_inner_r": rim_in},
                   "root_compliance_odonnell": c_root, "root_price_factor": ROOT_PRICE,
                   "band_r_mm": list(band), "collar_heights_mm": list(heights), "walls_mm": walls,
                   "thin_shell_rt_min": RT_MIN_THIN, "thin_shell_walls": thin,
                   "lugs": {"count": n_lugs, "radius_mm": r_lug, "engaged_length_mm_89": engaged,
                            "cem_protrusion_mm_placeholder": flange["lug_protrusion_mm"]},
                   "endurance": row4, "sf_line": s55.INFINITE_LIFE_SF, "accel_max_m_s2_87": accel,
                   "mass_ceiling_g_87": m_cap * 1e3, "drag_ceiling_N_87": drag,
                   "k_grid_N_per_um_89": k_grid, "bearing_force_max_N_105": f_max},
        "disc_per_N": disc,
        "collar_foot_MPa_per_N": per_n,
        "collar": collar,
        "collar_least_kf": least_kf,
        "ratified_wall_cell": {"key": worst_rat, "force_N": f_rat, "sigma_coupled_MPa": sig_c, "sigma_follow_MPa": sig_f,
                               "sigma_uniform_plate_coupled_MPa": sig_u, "kf_one_sided_uniform_plate_printed": kf_u,
                               "endurance_needed_unnotched_sf2_on_preload_MPa": se_need, "slope_ratios": ratios,
                               "kc_cd_by_wall": kcd, "steerable_walls_mm": steer},
        "lug_clamp_mean_at_ratified_wall_MPa": {"lowest_force_controlled": lo_mean,
                                                "peek_dominated_lower_bound_window_top": hi_mean,
                                                "over_yield": {k: v / ys for k, v in lo_mean.items()}},
        "lug_force_N": lug_force,
        "clamp_total_N_89": clamp_total,
        "lug": lug,
        "not_computed": ["any K_t (collar foot fillet, lug root)", "the lug on the wall as a shell — FE",
                         "the mature-state bearing force", "the disc's static means",
                         "the shank root's true compliance (O'Donnell's half-space is a reading)",
                         "the collar's membrane coupling to the disc", "the ring's lift between lugs",
                         "the lugs' unequal sharing", "walls with R/t below the thin-shell floor"],
        "controls": controls,
        "verdict": verdict,
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"→ {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
