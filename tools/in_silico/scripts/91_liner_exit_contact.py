#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 / HW.23 — the PEEK liner's CONTACT with the Ti channel at the exit, solved as an elastic-layer contact
problem coupled to the bending of the bus rod: the contact compliance scripts 55 and 68 call «measured nowhere».

WHY THIS EXISTS. Script 68 (on `lib.beam_contact`) found that under coaxial pogo drag the rod meets the channel
only at the EXIT, and priced the root against a RIGID wall: 3·E·c·g/L², µ-invariant. It named that figure the
LOWER end of a bracket — the polymer wall at the exit yields by R/k and lifts the root moment by 3EI·(R/k)/L² —
whose UPPER end is the Ti-bore stop (the whole 0.15 mm wall gone), ×7 apart on the shipped geometry, and said that
the compliance placing the root in it is measured nowhere. Script 55's wear budget inherits the same blindness
twice: its contact AREA is bracketed between a flow-limited patch R/p_flow and the whole projected bore run, and
its in-contact sliding between zero (rigid wall) and the Ti-stop rotation. This script models the contact itself.

⚠️ READ THE CYCLE BEFORE ANY ROOT NUMBER (adversarial review 2026-10-14). The root is read along the WHOLE drag
path, from touchdown to µ·F. Wherever the reaction sits inboard of the rod end, the root moment FALLS as the drag
grows past touchdown (the drag levers the overhang), so full drag is the MINIMUM of the contact phase and the
cycle PEAK sits at touchdown — F_td·L on a rigid wall at the same edge, which the radius already lifts above 68's
flush figure, plus a sliver from the wall's give (68's sign). A first version read only full drag and called the
root «at or below the rigid end»; that is false for the amplitude.

⚠️ READ THE EXIT GEOMETRY BEFORE ANY NUMBER. The shipped CAD ends the liner and the Ti bore together at the pad
plane («ring on ring», 68 `not_modelled.drag_contact_edge`), and no exit radius exists in any artifact. The
ratified form (⚖️ founder 2026-09-18, 02_02 §1.2) puts a PEEK ring in a countersink around the exit and the Ti
exit edge BELOW the pad plane — its depth and the ring's bore wait for the pogo pin's P/N (00_07 HW.9). So the
main table is a flush exit WITH a rounding (neither form exactly), the countersink is its own block (the Ti edge
at depth e below the rod end), and no number here is a radius to put on a drawing. ⛔ The flush SHARP corner is
outside this kernel's reach: the kernel continues the layer past s = 0, while the real tube ends flush with the
Ti face — and for coplanar free faces on a FRICTIONLESS counterface the corner stress is bounded (reflected across
the contact face it is a 180° wedge with both faces free, whose lowest eigenvalue is 1), while under stick it is a
clamped–free 90° wedge, weakly singular (≈ ρ^−0.35 at ν 0.4). A sharp edge INSIDE the
layer — the countersink's Ti edge, past which the tube continues — is a punch edge with the ρ^(−1/2) singularity,
and that case the kernel represents (control).

MODEL. (1) The liner is an elastic PEEK layer of the ratified wall thickness on the Ti wire, the wire RIGID
(E ratio ≈ 27), the layer flat in its own plane (contact half-angle asserted < 0.35 rad) and either BONDED to the
wire or FRICTIONLESS on it — the hot-mounted tube grips by interference, which is neither, so the two are a
bracket. Its surface compliance is the plane-strain Navier solution of a layer on a rigid base, Φ(kh) in Fourier
space (one mode = one plane-strain problem along k, so the 3-D kernel is Φ(|k|h)), solved per kh as a 4×4
boundary-value system and tabulated. (2) The Ti channel is an elastic half-space (Love's rectangle solution), the
bore's concave curvature entering only the gap. (3) The gap is the first-order gap of a rod displaced inside a
bore — c − v(s)·cos φ, c the radial play, φ the angle round the tube — plus the edge's recession inside its
rounding (a 90° edge of radius r) and, above an overhang, no wall at all. (4) The rod is the clamped cantilever of
scripts 55/68 (bare wire to the liner's lower end, rod-plus-tube composite above), its flexibility the EXACT Mohr
integral of the piecewise-constant EI — an inverse of the FE stiffness was tried and abandoned: at 5 µm elements
its conditioning ate the 5 nm deflection differences the contact rests on. The drag µ·F_pogo and an optional pad
COUPLE (the pogo off the rod axis, 68 (d)) act at the rod end. (5) Normal contact by Polonsky–Keer on a DC-FFT
(zero-padded, non-periodic) convolution, displacement-controlled through the beam; the operator — layer + Ti +
beam·cos φ ⊗ cos φ — is symmetric positive definite, so the solution is unique. (6) Contact FRICTION is not in the
solve; it is bracketed outside it as a lumped couple at the patch centroid (the fibre slips by r_OD·Δθ, so the
axial traction makes a couple f·r_OD), from zero to full stick capped at µ_c·R·r_OD with µ_c from 55's PEEK–Ti
sweep, on loading (held at touchdown) and on unloading (held at full drag — Coulomb friction reverses), so it widens
the cycle into a loop — rigid in shear, so it overstates what the layer's own shear compliance lets through.

CONTROLS asserted in-run, with what each one can and cannot catch:
  * Φ(kh): the bonded limit → the confined column h/M, the frictionless one → kh/2, large kh → the half-space —
    catches a wrong boundary condition or sign; blind to a wrong Poisson ratio (both limits use the same ν);
  * the tabulated Φ against the direct BVP at off-grid points — catches the interpolation;
  * the layer influence at two periodic paddings — catches periodic images of a domain too small for the layer;
  * Hertz on the half-space kernel (sphere): p₀ and approach within 1 % — catches the Love kernel, the DC-FFT
    padding and the solver's LOAD-controlled branch (production runs the displacement-controlled one — its control
    is the rigid limit and the rigid point ⊥ LCP below); blind to anything layer-specific;
  * a sphere on a THIN bonded layer (a/h = 60) against its Winkler asymptote P = π·M·a⁴/(4hR) — catches the
    layer kernel's normalisation and its k = 0 term; blind to the a ~ h regime the liner lives in;
  * the Mohr flexibility against lib.beam_contact's FE touchdown drag — catches a wrong EI split or units;
  * the RIGID limit (compliances ×1e-6, flush sharp edge) reproduces script 68's exit reaction and rigid-wall
    root stress — catches the beam coupling and the load sign; blind to the layer;
  * the closed-form rigid POINT contact at the rounding's tangent point against the LCP's rigid limit at a
    rounded edge — catches a wrong reference station for the «rigid wall, same radius» columns;
  * the pad couple on a rigid flush wall reproduces 68 (d)'s rows — catches a sign or a flexibility error in the
    couple terms (defl_c, rot_c), which no other control exercises;
  * every cycle row's peak sits on the rigid touchdown value at the same edge or a sliver above it (the reaction is
    near zero there) — catches a path that missed touchdown or a compliance acting more than a tiny patch can;
  * the edge peak at the SMALLEST radius at two axial steps — the peak sits in a few-µm zone on the rounding and
    a coarse grid misstates it by 10 %; catches an unresolved peak, not a wrong model;
  * a sharp Ti edge INSIDE the layer (countersink, r = 0) grows ≈ ×√2 per halving of the step — the punch-edge
    exponent −½; catches a kernel that lost the half-space behaviour at short range (Winkler would not grow);
  * every patch lies inside its window, the rod never reaches the mouth wall, the patch never wraps past the
    flat-layer limit, complementarity holds to 0.1 nm — catches a truncated patch; blind to physics outside it.

⛔ DECLARED CEILINGS — read these before quoting any number below:
  * LINEAR elasticity, small strain, no plasticity: a peak above the flow pressure is FLAGGED against script
    55's constraint-factor sweep (1·σ_y ⊥ 3·σ_y), never redistributed.
  * The layer is FLAT and uniform: the tube's curvature (t/R ≈ 0.23; a cylindrical confined column is ≈ 1.14×
    more compliant, so δ_c may be ~14 % low) and its free END at the pad plane are not modelled — rows with r < t
    sit nearest that end and their peak is biased high.
  * Bonded ⊥ frictionless base and short-term ⊥ 20-year relaxed modulus are BRACKETS, never readings. The relaxed
    modulus is lib's PEEK_RELAX_FLOOR — a constant-strain figure used here, by linear-viscoelastic correspondence,
    for a constant-LOAD contact; it LOWERS the edge peak, so for the peak it is the anti-conservative end.
  * Friction only as the lumped bracket above; no axial traction otherwise; no thermal term (the cold liner's
    ≈ 1 µm radial pull-back per 40 K moves 68's lower end by ≈ 0.13 MPa — the order of the whole elastic shift);
    no P-δ from the 1 N axial pogo force (≈ −0.05 MPa); no wear in the contact solve — the wear path is a separate
    rigid-wall block, valid until the rod reaches the mouth.
  * The countersink's PEEK ring and the ratified exit CLOSURE element (02_02 §1.2 / 01_01 §1.4, in the pad plane)
    are NOT modelled: in the overhang block a tip past the bore line is reported as «would bear on a ring whose
    bore equals the channel's», never priced.
  * The MOUTH (the station under a channel offset, 68 (b)) is not computed here.
  * No verdict is taken here; whether ratified verdicts that stood on the bracket move is the founder's
    (00_07 HW.34).
"""
from __future__ import annotations

import importlib.util
import json
import sys
import time
from pathlib import Path

import numpy as np
from scipy.linalg import expm

SI_DESCRIPTION = "Contact of the bus rod's PEEK liner with the Ti channel at its exit, as an elastic-layer contact problem coupled to the rod's bending."  # its row in the paper SI (72): English, no repo jargon

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib import beam_contact as bc
from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    CACHE_DIR,
    E_PEEK_PA,
    NU_PEEK,
    PEEK_RELAX_FLOOR,
    SIGMA_YIELD_PEEK_PA,
)
from lib.utils import banner

_spec = importlib.util.spec_from_file_location("bus55", HERE / "55_bus_mechanical.py")
s55 = importlib.util.module_from_spec(_spec)
sys.modules["bus55"] = s55   # a dataclass under `from __future__ import annotations` resolves its module by name
_spec.loader.exec_module(s55)

OUT_JSON = CACHE_DIR / "mechanical" / "liner_exit_contact.json"
BUS68_CACHE = CACHE_DIR / "mechanical" / "bus_contact_equilibrium.json"
BUS55_CACHE = CACHE_DIR / "mechanical" / "bus_mechanical.json"

# ── sweeps (every one is a sweep because the quantity has no number in any artifact) ─────────────────────
R_EDGE_SWEEP_MM = (0.05, 0.1, 0.2, 0.3, 0.5)     # exit-edge radius: «a radius, not a chamfer», no number (01_01 §1.4)
OVERHANG_SWEEP_MM = (0.5, 1.0, 1.5, 2.0)         # depth of the Ti edge below the rod end: the countersink's, unset (02_02 §1.2)
R_EDGE_REFERENCE_MM = 0.2                        # the row the sensitivity and overhang blocks are taken at (mid-sweep, not a pick)
BASES = ("bonded", "frictionless")
MODULI = (("short-term", 1.0), ("20-yr relaxed", PEEK_RELAX_FLOOR))

# ── grid ─────────────────────────────────────────────────────────────────────────────────────────────────
DS_MM, DY_MM = 0.002, 0.005                      # the path and the root (grid-insensitive)
DS_PEAK_MM = 0.001                               # the edge peak: resolved at 1 µm (control at the smallest radius)
PATH_EXTRA_N = (0.02, 0.05, 0.1)                 # drags between touchdown and the swept µ·F, so the cycle's peak is SEEN
PAD_ECCENTRICITY_MM = (-0.5, -0.1, 0.1, 0.5)     # pogo contact off the rod axis: 68 (d) bounds it by the rod radius
WINDOW_S_MM, WINDOW_Y_MM = 0.8, 0.25
WINDOW_LEAD_MM = 0.04                            # the window opens this far before the rounding's tangent point
PAD = 4                                          # periodic domain for the layer kernel = PAD × the window
RIGID_SCALE = 1e-6                               # the rigid limit: every contact compliance × this
PK_TOL, PK_MAXIT = 1e-10, 20000
SEP_TOL_MM = 1e-7                                # 0.1 nm: complementarity on the converged state

MM_M = 1e-3
E_PEEK_MPA = E_PEEK_PA / 1e6
R_OD_MM = s55.D_BUS / 2.0 + s55.LINER_WALL_MM
T_LINER_MM = s55.LINER_WALL_MM


# ── the layer kernel ────────────────────────────────────────────────────────────────────────────────────
def phi_direct(kh: float, nu: float, base: str) -> float:
    """Φ(kh): w(0) = p·2(1−ν²)/(E·k)·Φ for p·cos(kx) on a plane-strain layer of thickness h on a rigid base,
    free of shear at the surface; base BONDED (u = w = 0) or FRICTIONLESS (w = 0, τ = 0). Navier BVP, k = E = 1."""
    if kh < 1e-12:
        return 0.0
    if kh > 25.0:
        return 1.0                                # e^{-50}: the half-space to double precision
    lam, mu = nu / ((1 + nu) * (1 - 2 * nu)), 1.0 / (2 * (1 + nu))
    l2 = lam + 2 * mu
    m = np.array([[0, 1, 0, 0], [l2 / mu, 0, 0, (lam + mu) / mu], [0, 0, 0, 1], [0, -(lam + mu) / l2, mu / l2, 0]], float)
    p = expm(m * kh)                              # state [U, U', W, W'] from the surface to the base
    rows = [[0, 1, -1, 0], [lam, 0, 0, l2]]       # τ(0) = 0 · σ_zz(0) = −p
    rows += [p[0], p[2]] if base == "bonded" else [p[2], p[1] - p[2]]
    y0 = np.linalg.solve(np.array(rows, float), np.array([0.0, -1.0, 0.0, 0.0]))
    return float(y0[2] / (2 * (1 - nu ** 2)))


def phi_small_slope(nu: float, base: str) -> float:
    """dΦ/d(kh) at 0: the confined column (bonded) or the plane-strain uniaxial column (frictionless)."""
    return (1 - 2 * nu) / (2 * (1 - nu) ** 2) if base == "bonded" else 0.5


class PhiTable:
    """Φ tabulated on log-kh — the direct BVP per |k| on a 10⁵–10⁶ grid would cost minutes per kernel."""
    def __init__(self, nu: float, base: str):
        self.nu, self.base = nu, base
        self.x = np.logspace(-4, np.log10(25.0), 3000)
        self.v = np.array([phi_direct(x, nu, base) for x in self.x])

    def __call__(self, kh: np.ndarray) -> np.ndarray:
        kh = np.asarray(kh, float)
        out = np.interp(np.log(np.maximum(kh, 1e-300)), np.log(self.x), self.v)
        out = np.where(kh < self.x[0], phi_small_slope(self.nu, self.base) * kh, out)
        return np.where(kh > self.x[-1], 1.0, out)


def layer_influence(nx: int, ny: int, dx: float, dy: float, e_mpa: float, nu: float, h: float, table: PhiTable,
                    pad: int = PAD) -> np.ndarray:
    """(2nx−1)×(2ny−1) influence (mm/MPa) of a cell's uniform pressure, from the spectrum on a `pad`-times periodic
    domain. The layer's Green function decays over ~h, so the periodic images are negligible — asserted in-run
    against twice the padding (controls)."""
    big_x, big_y = pad * nx, pad * ny
    kx = 2 * np.pi * np.fft.fftfreq(big_x, d=dx)
    ky = 2 * np.pi * np.fft.fftfreq(big_y, d=dy)
    kxx, kyy = np.meshgrid(kx, ky, indexing="ij")
    k = np.hypot(kxx, kyy)
    with np.errstate(divide="ignore", invalid="ignore"):
        spec = 2 * (1 - nu ** 2) / (e_mpa * k) * table(k * h)
    spec[0, 0] = 2 * (1 - nu ** 2) / e_mpa * h * phi_small_slope(nu, table.base)   # the finite k → 0 limit
    spec *= np.sinc(kxx * dx / (2 * np.pi)) * np.sinc(kyy * dy / (2 * np.pi))     # cell-uniform pressure
    g = np.real(np.fft.ifft2(spec))
    ii = np.arange(-(nx - 1), nx) % big_x
    jj = np.arange(-(ny - 1), ny) % big_y
    return g[np.ix_(ii, jj)]


def halfspace_influence(nx: int, ny: int, dx: float, dy: float, e_mpa: float, nu: float) -> np.ndarray:
    """(2nx−1)×(2ny−1) influence (mm/MPa) of a cell's uniform pressure on an elastic half-space (Love 1929)."""
    x = np.arange(-(nx - 1), nx) * dx
    y = np.arange(-(ny - 1), ny) * dy
    xx, yy = np.meshgrid(x, y, indexing="ij")

    def f(a: np.ndarray, b: np.ndarray) -> np.ndarray:
        r = np.hypot(a, b)
        out = np.zeros_like(a)
        m = r > 0
        out[m] = a[m] * np.log(b[m] + r[m]) + b[m] * np.log(a[m] + r[m])
        return out
    a, b = dx / 2, dy / 2
    love = f(xx + a, yy + b) - f(xx + a, yy - b) - f(xx - a, yy + b) + f(xx - a, yy - b)
    return (1 - nu ** 2) / (np.pi * e_mpa) * love


class Conv:
    """Linear (non-periodic) convolution of an nx×ny field with a (2nx−1)×(2ny−1) influence (DC-FFT)."""
    def __init__(self, g: np.ndarray):
        self.nx, self.ny = (g.shape[0] + 1) // 2, (g.shape[1] + 1) // 2
        gp = np.zeros((2 * self.nx, 2 * self.ny))
        ii = np.arange(-(self.nx - 1), self.nx) % (2 * self.nx)
        jj = np.arange(-(self.ny - 1), self.ny) % (2 * self.ny)
        gp[np.ix_(ii, jj)] = g
        self.f = np.fft.rfft2(gp)

    def __call__(self, p: np.ndarray) -> np.ndarray:
        big = np.zeros((2 * self.nx, 2 * self.ny))
        big[:self.nx, :self.ny] = p
        return np.fft.irfft2(np.fft.rfft2(big) * self.f, s=big.shape)[:self.nx, :self.ny]


def pk_solve(h0: np.ndarray, op, load: float | None = None, cell: float = 1.0) -> tuple[np.ndarray, int]:
    """Polonsky–Keer CG: p ≥ 0, separation h0 + op(p) (+ a free approach if load-controlled) ≥ 0, complementary.
    Refuses rather than returning a non-converged state."""
    p = np.where(h0 < 0, 1.0, 0.0) if load is None else np.full(h0.shape, load / (cell * h0.size))
    t = np.zeros_like(p)
    g_old, delta = 1.0, 0.0
    for it in range(PK_MAXIT):
        g = op(p) + h0
        ic = p > 0
        if load is not None:
            g = g - g[ic].mean()
        g_sum = float(np.sum(g[ic] ** 2))
        t = np.where(ic, g + delta * (g_sum / g_old) * t, 0.0)
        g_old = g_sum
        r = op(t)
        if load is not None:
            r = r - r[ic].mean()
        denom = float(np.sum(r[ic] * t[ic]))
        tau = float(np.sum(g[ic] * t[ic])) / denom if denom != 0.0 else 0.0
        p_old = p.copy()
        p = np.maximum(p - tau * t, 0.0)
        overlap = (p == 0) & (g < 0)
        if overlap.any():
            delta = 0.0
            p[overlap] -= tau * g[overlap]
        else:
            delta = 1.0
        if load is not None:
            p *= load / (np.sum(p) * cell)
        if np.sum(np.abs(p - p_old)) <= PK_TOL * max(float(np.sum(p)), 1e-300):
            return p, it
    raise RuntimeError("Polonsky–Keer did not converge — refusing to report a number")


# ── the rod: exact cantilever flexibility (Mohr integral over a piecewise-constant EI) ──────────────────────
def _mohr_defl(x: np.ndarray, xp: np.ndarray, a: np.ndarray, b: np.ndarray, ei: float) -> np.ndarray:
    def prim(t):
        return x * xp * t - (x + xp) * t * t / 2.0 + t ** 3 / 3.0
    return (prim(b) - prim(a)) / ei


def _mohr_rot(x: np.ndarray, xp: np.ndarray, a: np.ndarray, b: np.ndarray, ei: float) -> np.ndarray:
    def prim(t):
        return xp * t - t * t / 2.0
    return (prim(b) - prim(a)) / ei


def _mohr_defl_c(x: np.ndarray, xp: np.ndarray, a: np.ndarray, b: np.ndarray, ei: float) -> np.ndarray:
    def prim(t):
        return x * t - t * t / 2.0
    return (prim(b) - prim(a)) / ei


def _mohr_rot_c(x: np.ndarray, xp: np.ndarray, a: np.ndarray, b: np.ndarray, ei: float) -> np.ndarray:
    return (b - a) / ei


class Rod:
    """The clamped bus rod of scripts 55/68: EI from `s55.member_ei_at` (bare wire, then rod + tube), mm and N."""
    def __init__(self, geo, liner_row: dict, bonded_member: bool = True):
        ei_at = s55.member_ei_at(geo, liner_row, bonded_member)
        self.L = geo.pad_mm
        self.a = geo.liner_from_mm
        self.ei_bare, self.ei_comp = ei_at(0.0) * 1e6, ei_at(self.L) * 1e6      # N·m² → N·mm²

    def _split(self, kern, x, xp):
        m = np.minimum(x, xp)
        lo = kern(x, xp, 0.0, np.minimum(m, self.a), self.ei_bare)
        return lo + np.where(m > self.a, kern(x, xp, self.a, np.maximum(m, self.a), self.ei_comp), 0.0)

    def defl(self, x, xp):
        """Deflection at x (mm) per unit load at xp (mm/N)."""
        return self._split(_mohr_defl, np.asarray(x, float), np.asarray(xp, float))

    def rot(self, x, xp):
        """Slope at x per unit load at xp (rad/N)."""
        return self._split(_mohr_rot, np.asarray(x, float), np.asarray(xp, float))

    def defl_c(self, x):
        """Deflection at x per unit COUPLE at the rod end (mm per N·mm): the moment is uniform, M(ξ) = 1."""
        x = np.asarray(x, float)
        return self._split(_mohr_defl_c, x, np.full_like(x, self.L))

    def rot_c(self, x):
        """Slope at x per unit couple at the rod end (rad per N·mm) — equally, per unit couple at any station ≥ x."""
        x = np.asarray(x, float)
        return self._split(_mohr_rot_c, x, np.full_like(x, self.L))


# ── the exit contact ──────────────────────────────────────────────────────────────────────────────────────
def recession_mm(s: np.ndarray, r: float, e: float) -> np.ndarray:
    """How far the Ti wall stands back from the bore line at depth s below the rod end. The edge sits at depth e
    (the overhang) and is rounded by r: no wall above it, the 90° rounding between e and e + r, the bore beyond."""
    rec = np.zeros_like(s)
    if r > 0:
        z = np.clip(e + r - s, 0.0, r)
        rec = r - np.sqrt(r * r - z * z)
    return np.where(s < e, np.inf, rec)


_KERNELS: dict = {}


def kernel(ns: int, ny: int, ds: float, dy: float, base: str, ti: str | None, tables: dict | None) -> tuple[np.ndarray, np.ndarray]:
    """(layer influence at unit modulus, Ti influence) for a grid — computed once; the layer part scales as 1/E."""
    key = (ns, ny, ds, dy, base, ti)
    if key not in _KERNELS:
        table = (tables or {}).get(base) or PhiTable(NU_PEEK, base)
        g_lay = layer_influence(ns, ny, ds, dy, 1.0, NU_PEEK, T_LINER_MM, table)
        g_ti = np.zeros_like(g_lay)
        if ti is not None:
            props = ALLOY_PROPERTIES[ti]
            g_ti = halfspace_influence(ns, ny, ds, dy, props["E_GPa"] * 1e3, props["nu"])
        _KERNELS[key] = (g_lay, g_ti)
    return _KERNELS[key]


def signed_sigma(m_root_nmm: float) -> float:
    """Root fibre stress WITH the sign of the clamp moment (+ = the drag's own sense, F·L). Decompositions and the
    cycle peak are read on the signed figure: a modulus breaks additivity the moment an overhang swings the moment
    through zero (caught by the cache test on the overhang rows, 2026-10-14)."""
    return float(np.sign(m_root_nmm)) * s55.root_sigma_MPa(m_root_nmm * MM_M)


def touchdown_drag(rod: Rod, play: float, x_t: float, pad_nmm: float = 0.0) -> float:
    """The drag that first closes the play at station x_t (a rigid wall), with a pad couple already applied."""
    return float((play - pad_nmm * rod.defl_c(x_t)) / rod.defl(x_t, rod.L))


def rigid_point(geo, liner_row: dict, play: float, drag: float, x_c: float, pad_nmm: float = 0.0) -> dict:
    """A RIGID wall touching the rod at one station x_c (mm from the clamp): exact, from the Mohr flexibility.
    With a rounded edge the rigid contact sits at the rounding's tangent point to within r·θ (≈ 0.2 µm here), so
    this is the rigid-wall reference AT THE SAME EDGE — the LCP is ill-conditioned there and is used as a control."""
    rod = Rod(geo, liner_row)
    react = float((drag * rod.defl(x_c, rod.L) + pad_nmm * rod.defl_c(x_c) - play) / rod.defl(x_c, x_c))
    m_root = drag * rod.L + pad_nmm - react * x_c
    theta = float(drag * rod.rot(x_c, rod.L) + pad_nmm * rod.rot_c(x_c) - react * rod.rot(x_c, x_c))
    return {"R_N": react, "sigma_signed_MPa": signed_sigma(m_root), "m_root_Nmm": m_root, "theta_c_rad": theta, "x_c_mm": x_c}


def solve_exit(geo, liner_row: dict, play: float, drag: float, r: float, *, e: float = 0.0, base: str = "bonded",
               e_peek_mpa: float = E_PEEK_MPA, ti: str | None = ALLOY_BASELINE, scale: float = 1.0,
               ds: float = DS_MM, dy: float = DY_MM, tables: dict | None = None, pad_nmm: float = 0.0) -> dict:
    """One contact equilibrium at the exit (drag and an optional pad couple at the rod end). Returns the wall
    reaction, the signed root stress, the patch, the give; `contact: False` when the wall is not reached."""
    rod = Rod(geo, liner_row)
    s_len, y_half = WINDOW_S_MM, WINDOW_Y_MM
    for _attempt in range(4):
        s0 = max(0.0, e + r - WINDOW_LEAD_MM)
        ns, ny = round(s_len / ds), round(2 * y_half / dy)
        s = s0 + (np.arange(ns) + 0.5) * ds
        y = (np.arange(ny) - (ny - 1) / 2.0) * dy
        cphi = np.cos(y / R_OD_MM)
        g_lay, g_ti = kernel(ns, ny, ds, dy, base, ti, tables)
        conv = Conv((g_lay / e_peek_mpa + g_ti) * scale)
        x = rod.L - s
        g_w = rod.defl(x[:, None], x[None, :])
        v_free = drag * rod.defl(x, rod.L) + pad_nmm * rod.defl_c(x)
        rec = recession_mm(s, r, e)
        h0 = play + np.where(np.isfinite(rec), rec, 1e3)[:, None] - v_free[:, None] * cphi[None, :]
        if h0.min() >= 0.0:
            m_root = drag * rod.L + pad_nmm
            return {"contact": False, "R_N": 0.0, "sigma_signed_MPa": signed_sigma(m_root), "m_root_Nmm": m_root}
        w = cphi[None, :] * ds * dy

        def op(p: np.ndarray, w=w, conv=conv, cphi=cphi, g_w=g_w) -> np.ndarray:
            q = (p * w).sum(axis=1)
            return conv(p) + cphi[None, :] * (g_w @ q)[:, None]
        p, it = pk_solve(h0, op)
        sep = op(p) + h0
        ii, jj = np.nonzero(p > 0)
        if ii.size == 0:
            m_root = drag * rod.L + pad_nmm
            return {"contact": False, "R_N": 0.0, "sigma_signed_MPa": signed_sigma(m_root), "m_root_Nmm": m_root}
        inside_s = ii.max() <= ns - 3 and (ii.min() >= 2 or s0 == 0.0)
        inside_y = np.abs(y[jj]).max() <= y_half - 2 * dy
        if inside_s and inside_y:
            break
        s_len, y_half = (s_len * 2 if not inside_s else s_len), (y_half * 2 if not inside_y else y_half)
    else:
        raise RuntimeError("the contact patch outgrew every window — refusing a truncated patch")
    assert np.abs(sep[p > 0]).max() <= SEP_TOL_MM and sep.min() >= -SEP_TOL_MM, "complementarity not met"
    q = (p * w).sum(axis=1)
    react = float(q.sum())
    x_c = float((q * x).sum() / react)
    m_root = drag * rod.L + pad_nmm - float((q * x).sum())                  # N·mm, about the clamp
    give = (conv(p) / scale if scale != 1.0 else conv(p))
    delta_c = float((give * p).sum() / p.sum())                              # the wall + layer give: 68's «R/k»
    theta_c = float(drag * rod.rot(x_c, rod.L) + pad_nmm * rod.rot_c(x_c) - (q * rod.rot(x_c, x)).sum())
    v_tip = float(drag * rod.defl(rod.L, rod.L) + pad_nmm * rod.defl_c(rod.L) - (q * rod.defl(rod.L, x)).sum())
    v_mouth = float(drag * rod.defl(geo.gap_mm, rod.L) + pad_nmm * rod.defl_c(geo.gap_mm) - (q * rod.defl(geo.gap_mm, x)).sum())
    assert abs(v_mouth) < play, "the rod reached the mouth wall — the exit is no longer the only station"
    half_angle = float(np.abs(y[jj]).max() / R_OD_MM)
    assert half_angle < 0.35, "the patch wraps too far round the tube for a flat layer"
    return {"contact": True, "R_N": react, "sigma_signed_MPa": signed_sigma(m_root), "m_root_Nmm": m_root,
            "x_c_mm": x_c, "p_max_MPa": float(p.max()), "p_mean_MPa": float(react / (np.count_nonzero(p) * ds * dy)),
            "area_mm2": float(np.count_nonzero(p) * ds * dy),
            "patch_s_mm": [float(s[ii.min()] - ds / 2), float(s[ii.max()] + ds / 2)],
            "patch_half_width_mm": float(np.abs(y[jj]).max() + dy / 2), "patch_half_angle_rad": half_angle,
            "delta_c_um": delta_c * 1e3, "theta_c_rad": theta_c, "tip_past_bore_line_um": (v_tip - play) * 1e3,
            "iterations": it}


def friction_shift(geo, liner_row: dict, st: dict, theta_ref: float, mu_c: float) -> float:
    """Lumped contact friction, rigid in shear: the couple that would hold the rotation AT THE PATCH CENTROID at a
    reference value — its touchdown value on LOADING, its full-drag value on UNLOADING (Coulomb friction reverses
    with the slip) — capped at µ_c·R·r_OD, applied with the patch held in place (a prop). Returns the shift of the
    SIGNED root stress; rigid in shear, so it overstates what the layer's own shear compliance lets through."""
    if not st.get("contact"):
        return 0.0
    rod = Rod(geo, liner_row)
    x_c = st["x_c_mm"]
    a, b, d = float(rod.rot_c(x_c)), float(rod.rot(x_c, x_c)), float(rod.defl(x_c, x_c))
    needed = (theta_ref - st["theta_c_rad"]) / (a - b * b / d)
    cap = mu_c * st["R_N"] * R_OD_MM
    couple = float(np.clip(needed, -cap, cap))
    return signed_sigma(st["m_root_Nmm"] + couple * (1.0 - b * x_c / d)) - st["sigma_signed_MPa"]


def slide_um(geo, liner_row: dict, play: float, st: dict) -> float:
    """55's per-cycle in-contact sliding, 4·r_OD·Δθ, with Δθ the rotation AT THE PATCH between touchdown (R = 0:
    the drag that first closes the play there) and the state. Zero for a rigid FLUSH exit (55's figure); with an
    overhang past the contact the drag levers the rod round the edge even against a rigid wall. Frictionless:
    a kinematic ceiling."""
    rod = Rod(geo, liner_row)
    f_td = play / float(rod.defl(st["x_c_mm"], rod.L))
    return 4.0 * R_OD_MM * abs(st["theta_c_rad"] - f_td * float(rod.rot(st["x_c_mm"], rod.L))) * 1e3


# ── controls ──────────────────────────────────────────────────────────────────────────────────────────────
def controls(tables: dict, geo, liner_row: dict, play: float) -> dict:
    out = {}
    nu = NU_PEEK
    # (1) kernel limits and the table
    for base in BASES:
        small = phi_direct(1e-3, nu, base) / (1e-3 * phi_small_slope(nu, base))
        assert abs(small - 1.0) < 1e-5, f"Φ small-kh limit ({base})"
        assert abs(phi_direct(20.0, nu, base) - 1.0) < 1e-6, f"Φ half-space limit ({base})"
        xs = np.array([3.3e-3, 0.071, 0.49, 1.37, 4.2])
        err = max(abs(tables[base](np.array([v]))[0] - phi_direct(v, nu, base)) / phi_direct(v, nu, base) for v in xs)
        assert err < 1e-4, f"Φ table interpolation ({base}): {err}"
        out[f"phi_{base}"] = {"small_kh_over_column": round(small, 7), "table_max_rel_error": float(f"{err:.2e}")}
    # (2) the layer influence at two periodic paddings, on the production grid
    ns, ny = round(WINDOW_S_MM / DS_MM), round(2 * WINDOW_Y_MM / DY_MM)
    g4 = layer_influence(ns, ny, DS_MM, DY_MM, 1.0, nu, T_LINER_MM, tables["bonded"], pad=PAD)
    g8 = layer_influence(ns, ny, DS_MM, DY_MM, 1.0, nu, T_LINER_MM, tables["bonded"], pad=2 * PAD)
    pad_err = float(np.abs(g8 - g4).max() / np.abs(g8).max())
    assert pad_err < 1e-4, f"periodic images: PAD {PAD} vs {2 * PAD} differ by {pad_err}"
    out["layer_influence_padding"] = {"pads": [PAD, 2 * PAD], "max_rel_difference": float(f"{pad_err:.2e}")}
    # (3) Hertz on the half-space
    e_s = E_PEEK_MPA / (1 - nu ** 2)
    rad, load = 2.0, 0.5
    a = (3 * load * rad / (4 * e_s)) ** (1 / 3)
    p0, d = 3 * load / (2 * np.pi * a * a), a * a / rad
    n = 128
    dx = 8 * a / n
    xg = (np.arange(n) - (n - 1) / 2) * dx
    xx, yy = np.meshgrid(xg, xg, indexing="ij")
    h0 = (xx ** 2 + yy ** 2) / (2 * rad)
    conv = Conv(halfspace_influence(n, n, dx, dx, E_PEEK_MPA, nu))
    p, _ = pk_solve(h0, conv, load=load, cell=dx * dx)
    approach = float((h0 + conv(p))[p > 0].mean())
    assert abs(p.max() / p0 - 1) < 0.01 and abs(approach / d - 1) < 0.01, "Hertz control"
    out["hertz_halfspace"] = {"p0_ratio": round(float(p.max() / p0), 4), "approach_ratio": round(approach / d, 4)}
    # (4) thin bonded layer against its Winkler asymptote
    m_c = E_PEEK_MPA * (1 - nu) / ((1 + nu) * (1 - 2 * nu))
    h, a_t = 0.002, 0.12
    load = np.pi * m_c * a_t ** 4 / (4 * h * rad)
    n = 160
    dx = 3.2 * a_t / n
    xg = (np.arange(n) - (n - 1) / 2) * dx
    xx, yy = np.meshgrid(xg, xg, indexing="ij")
    h0 = (xx ** 2 + yy ** 2) / (2 * rad)
    conv = Conv(layer_influence(n, n, dx, dx, E_PEEK_MPA, nu, h, tables["bonded"]))
    p, _ = pk_solve(h0, conv, load=load, cell=dx * dx)
    approach = float((h0 + conv(p))[p > 0].mean())
    ratio = approach / (a_t ** 2 / (2 * rad))
    assert abs(ratio - 1) < 0.01, "thin-layer control"
    out["thin_layer_winkler"] = {"a_over_h": a_t / h, "approach_ratio": round(ratio, 4)}
    # (5) the Mohr flexibility against lib.beam_contact's FE touchdown drag (independent discretisation)
    rod = Rod(geo, liner_row)
    td_fe = bc.touchdown_drag_N(geo.channel(), s55.member_ei_at(geo, liner_row, True), play)
    td_mohr = touchdown_drag(rod, play, rod.L)
    assert abs(td_mohr / td_fe - 1) < 1e-4, "Mohr flexibility ≠ the FE touchdown drag"
    out["mohr_vs_fe_touchdown"] = {"mohr_N": round(td_mohr, 6), "fe_N": round(td_fe, 6)}
    return out


def drag_path(geo, liner_row: dict, play: float, r: float, *, e: float = 0.0, base: str = "bonded",
              e_peek_mpa: float = E_PEEK_MPA, ti: str | None = ALLOY_BASELINE, tables: dict | None = None,
              pad_nmm: float = 0.0, extra: tuple = ()) -> list[dict]:
    """The contact phase from touchdown to the largest swept drag: one solve per point, the swept µ·F among them."""
    rod = Rod(geo, liner_row)
    f_td = touchdown_drag(rod, play, rod.L - e - r, pad_nmm)
    pts = sorted({round(v, 6) for v in (1.002 * f_td, 1.05 * f_td, 1.5 * f_td, *PATH_EXTRA_N, *extra,
                                         *(mu * s55.F_POGO_N for mu in s55.MU_SWEEP)) if v > 1.001 * f_td})
    out = []
    for f in pts:
        st = solve_exit(geo, liner_row, play, f, r, e=e, base=base, e_peek_mpa=e_peek_mpa, ti=ti, tables=tables, pad_nmm=pad_nmm)
        st["drag_N"] = f
        out.append(st)
    return out


def main() -> int:
    t0 = time.time()
    banner("Bus liner at the channel exit — elastic-layer contact coupled to the rod (HW.34 / HW.23)")
    d68 = json.loads(BUS68_CACHE.read_text(encoding="utf-8"))
    d55 = json.loads(BUS55_CACHE.read_text(encoding="utf-8"))
    geos = s55.geometries()
    geo = s55.SHIPPED_GEOMETRY
    liner = next({"branch": lb, "coating_or_liner_mm": t, "play_side": side}
                 for lb, t, side in s55.INSULATION_OPTIONS if side == "channel")
    plays = d68["inputs"]["radial_plays_um"]
    zero_play = plays["zero interference"] / 1000.0
    tables = {b: PhiTable(NU_PEEK, b) for b in BASES}
    mu_min, mu_max = min(s55.MU_SWEEP), max(s55.MU_SWEEP)
    mu_c = (min(s55.MU_PEEK_TI_SWEEP), max(s55.MU_PEEK_TI_SWEEP))

    def r68(geo_label: str, play_label: str, mu: float) -> dict:
        row = next(r for r in d68["drag_coaxial"] if r["geometry"] == geo_label and r["branch"] == liner["branch"]
                   and r["play"] == play_label)
        return row["by_mu"][str(mu)]

    def bracket(geo_label: str, play_label: str = "zero interference") -> tuple[float, float]:
        v = r68(geo_label, play_label, mu_max)
        return v["sigma_root_MPa_bonded"], v["sigma_root_MPa_upper_end"]

    banner("Controls")
    ctl = controls(tables, geo, liner, zero_play)
    for k, v in ctl.items():
        print(f"  {k:<26s} {v}")
    rig = solve_exit(geo, liner, zero_play, mu_max * s55.F_POGO_N, 0.0, scale=RIGID_SCALE, tables=tables)
    ref = r68(geo.label, "zero interference", mu_max)
    react68 = -ref["contacts_bonded"][0]["force_N"]
    assert abs(rig["R_N"] / react68 - 1) < 0.005, "rigid limit: exit reaction ≠ 68"
    assert abs(rig["sigma_signed_MPa"] / ref["sigma_root_MPa_bonded"] - 1) < 0.01, "rigid limit: root stress ≠ 68"
    ctl["rigid_limit_vs_68"] = {"R_N": round(rig["R_N"], 4), "R_N_68": react68,
                                "sigma_root_MPa": round(rig["sigma_signed_MPa"], 3), "sigma_root_MPa_68": ref["sigma_root_MPa_bonded"]}
    lcp_r = solve_exit(geo, liner, zero_play, mu_min * s55.F_POGO_N, R_EDGE_REFERENCE_MM, scale=1e-4, tables=tables)
    pt_r = rigid_point(geo, liner, zero_play, mu_min * s55.F_POGO_N, geo.pad_mm - R_EDGE_REFERENCE_MM)
    assert abs(lcp_r["sigma_signed_MPa"] / pt_r["sigma_signed_MPa"] - 1) < 0.01 and abs(lcp_r["R_N"] / pt_r["R_N"] - 1) < 0.005, \
        "rigid point contact at the tangent point ≠ the LCP's rigid limit"
    ctl["rigid_point_vs_lcp_rounded_edge"] = {"r_edge_mm": R_EDGE_REFERENCE_MM, "mu": mu_min,
                                              "sigma_root_MPa": [round(pt_r["sigma_signed_MPa"], 3), round(lcp_r["sigma_signed_MPa"], 3)],
                                              "R_N": [round(pt_r["R_N"], 4), round(lcp_r["R_N"], 4)]}
    r_min = min(R_EDGE_SWEEP_MM)
    pk_c = solve_exit(geo, liner, zero_play, mu_max * s55.F_POGO_N, r_min, ds=DS_PEAK_MM, tables=tables)
    pk_f = solve_exit(geo, liner, zero_play, mu_max * s55.F_POGO_N, r_min, ds=DS_PEAK_MM / 2, tables=tables)
    assert abs(pk_f["p_max_MPa"] / pk_c["p_max_MPa"] - 1) < 0.02, "edge peak not resolved at the smallest radius"
    ctl["edge_peak_smallest_radius_two_steps"] = {"r_edge_mm": r_min, "ds_mm": [DS_PEAK_MM, DS_PEAK_MM / 2],
                                                  "p_max_MPa": [round(pk_c["p_max_MPa"], 2), round(pk_f["p_max_MPa"], 2)]}
    e_sing = OVERHANG_SWEEP_MM[1]
    sing = [solve_exit(geo, liner, zero_play, mu_max * s55.F_POGO_N, 0.0, e=e_sing, ds=step, tables=tables)
            for step in (DS_MM, DS_MM / 2, DS_MM / 4)]
    growth = [sing[i + 1]["p_max_MPa"] / sing[i]["p_max_MPa"] for i in range(2)]
    assert all(1.3 < g < 1.55 for g in growth), f"the in-layer sharp edge did not grow as ρ^(-1/2): {growth}"
    ctl["sharp_edge_inside_the_layer"] = {"overhang_mm": e_sing, "ds_mm": [DS_MM, DS_MM / 2, DS_MM / 4],
                                          "p_max_MPa": [round(v["p_max_MPa"], 1) for v in sing],
                                          "growth_per_halving": [round(g, 3) for g in growth],
                                          "sigma_root_MPa": [round(v["sigma_signed_MPa"], 3) for v in sing]}
    for k in ("rigid_limit_vs_68", "rigid_point_vs_lcp_rounded_edge", "edge_peak_smallest_radius_two_steps", "sharp_edge_inside_the_layer"):
        print(f"  {k:<26s} {ctl[k]}")
    lo, hi = bracket(geo.label)

    def summarise(path: list[dict], lo_: float, hi_: float, play: float, g, base: str, with_friction: bool,
                  x_t: float, pad_nmm: float = 0.0) -> dict:
        """The cycle on one path: the peak (at or just after touchdown), the swept-µ points, the sub-cycle, and beside
        each the RIGID wall touching at the same edge (station x_t, the rounding's tangent point) — so the compliance's
        own effect is read like for like: a sliver up at the peak while the patch is tiny, down on the loaded part."""
        live = [p for p in path if p["contact"]]
        assert live, "no contact anywhere on the path"
        sig = [p["sigma_signed_MPa"] for p in path]
        k_peak = int(np.argmax(sig))
        at_mu = {str(mu): next(p for p in path if abs(p["drag_N"] - mu * s55.F_POGO_N) < 1e-9) for mu in s55.MU_SWEEP}
        full = at_mu[str(mu_max)]
        rod = Rod(g, liner)
        peak_rigid = signed_sigma(touchdown_drag(rod, play, x_t, pad_nmm) * rod.L + pad_nmm)
        full_rigid = rigid_point(g, liner, play, mu_max * s55.F_POGO_N, x_t, pad_nmm)["sigma_signed_MPa"]
        out = {"drag_N": [round(p["drag_N"], 4) for p in path], "sigma_root_signed_MPa": [round(v, 3) for v in sig],
               "peak_sigma_MPa": round(sig[k_peak], 3), "peak_at_drag_N": round(path[k_peak]["drag_N"], 4),
               "peak_rigid_touchdown_same_edge_MPa": round(peak_rigid, 4),
               "peak_lift_by_compliance_MPa": round(sig[k_peak] - peak_rigid, 4),
               "peak_position_in_68_bracket": round((sig[k_peak] - lo_) / (hi_ - lo_), 4),
               "peak_over_68_rigid_end": round(sig[k_peak] / lo_, 4),
               "sigma_at_mu_MPa": {m: round(v["sigma_signed_MPa"], 3) for m, v in at_mu.items()},
               "full_drag_rigid_same_edge_MPa": round(full_rigid, 3),
               "full_drag_shift_by_compliance_MPa": round(full["sigma_signed_MPa"] - full_rigid, 3),
               "subcycle_range_MPa": round(sig[k_peak] - full["sigma_signed_MPa"], 3),
               "subcycle_rigid_same_edge_MPa": round(peak_rigid - full_rigid, 3),
               "R_N_at_mu": {m: round(v["R_N"], 4) for m, v in at_mu.items()},
               "delta_c_um_at_mu_max": round(full["delta_c_um"], 3),
               "k_eff_N_per_um_at_mu_max": round(full["R_N"] / full["delta_c_um"], 3),
               "slide_per_cycle_um_at_mu_max": round(slide_um(g, liner, play, full), 5),
               "tip_past_bore_line_um_at_touchdown": round(live[0]["tip_past_bore_line_um"], 3),
               "tip_past_bore_line_um_at_mu_max": round(full["tip_past_bore_line_um"], 3)}
        # The peak sits at or just after touchdown: on a rigid wall at the same edge it is F_td·L; while the patch is tiny
        # the give lifts it a little (68's sign), and on the loaded part the patch's spread wins. Sampled from 1.002·F_td,
        # the elastic peak can therefore sit above the rigid touchdown value, never below it, and only by a sliver.
        assert -1e-3 <= out["peak_lift_by_compliance_MPa"] <= 0.005 * abs(peak_rigid), "the peak left the touchdown value"
        if with_friction and base == "bonded":
            for label, mu_ in zip(("mu_c_min", "mu_c_max"), mu_c, strict=True):
                load, unload = [], []
                for p in path:
                    if not p["contact"]:
                        load.append(p["sigma_signed_MPa"])
                        unload.append(p["sigma_signed_MPa"])
                        continue
                    th_td = play / float(rod.defl(p["x_c_mm"], rod.L)) * float(rod.rot(p["x_c_mm"], rod.L))
                    load.append(p["sigma_signed_MPa"] + friction_shift(g, liner, p, th_td, mu_))
                    unload.append(p["sigma_signed_MPa"] + friction_shift(g, liner, p, full["theta_c_rad"], mu_))
                k_full = path.index(full)
                out[f"friction_{label}"] = {"mu_c": mu_, "loading_peak_sigma_MPa": round(max(load[:k_full + 1]), 3),
                                            "unloading_min_sigma_MPa": round(min(unload[:k_full + 1]), 3),
                                            "loop_range_MPa": round(max(load[:k_full + 1]) - min(unload[:k_full + 1]), 3),
                                            "peak_moves_to_full_drag": bool(int(np.argmax(load[:k_full + 1])) == k_full)}
        return out

    # ── (a) the drag path, flush exit with a rounding: µ × r × base × modulus ───────────────────────────
    banner("(a) the cycle — root stress from touchdown to µ·F, flush exit with a rounding (shipped geometry, zero-interference play)")
    rod0 = Rod(geo, liner)
    flush_td = signed_sigma(touchdown_drag(rod0, zero_play, rod0.L) * rod0.L)      # 68's rigid flush figure, unrounded
    print(f"  {'r mm':>5s} {'base':<12s} {'modulus':<13s} {'peak':>6s} {'rigid':>6s} {'σ µ0.5':>7s} {'rigid':>6s} "
          f"{'comp':>6s} {'sub':>6s} {'sub rig':>7s} {'δ_c µm':>7s} {'slide':>7s} {'fric loop':>10s}")
    cycle = []
    for r in R_EDGE_SWEEP_MM:
        for base in BASES:
            for mod_label, frac in MODULI:
                path = drag_path(geo, liner, zero_play, r, base=base, e_peek_mpa=E_PEEK_MPA * frac, tables=tables)
                row = {"r_edge_mm": r, "base": base, "modulus": mod_label,
                       **summarise(path, lo, hi, zero_play, geo, base, with_friction=True, x_t=geo.pad_mm - r)}
                row["peak_lift_by_radius_over_flush_MPa"] = round(row["peak_rigid_touchdown_same_edge_MPa"] - flush_td, 4)
                cycle.append(row)
                fr = (f"{row['friction_mu_c_max']['loop_range_MPa']:.3f}" if base == "bonded" else "—")
                print(f"  {r:5.2f} {base:<12s} {mod_label:<13s} {row['peak_sigma_MPa']:6.3f} {row['peak_rigid_touchdown_same_edge_MPa']:6.3f} "
                      f"{row['sigma_at_mu_MPa'][str(mu_max)]:7.3f} {row['full_drag_rigid_same_edge_MPa']:6.3f} "
                      f"{row['full_drag_shift_by_compliance_MPa']:+6.3f} {row['subcycle_range_MPa']:6.3f} {row['subcycle_rigid_same_edge_MPa']:7.3f} "
                      f"{row['delta_c_um_at_mu_max']:7.3f} {row['slide_per_cycle_um_at_mu_max']:7.4f} {fr:>10s}")
    print(f"  ({time.time() - t0:.0f} s)")

    # ── (b) the patch and the edge peak at the largest drag, resolved step ──────────────────────────────
    banner(f"(b) the patch and the edge peak at µ {mu_max}, axial step {DS_PEAK_MM} mm")
    flow = {f"{c:.1f}": c * SIGMA_YIELD_PEEK_PA / 1e6 for c in s55.CONTACT_CONSTRAINT_FACTORS}
    patch = []
    for r in R_EDGE_SWEEP_MM:
        for base in BASES:
            for mod_label, frac in MODULI:
                st = solve_exit(geo, liner, zero_play, mu_max * s55.F_POGO_N, r, base=base, e_peek_mpa=E_PEEK_MPA * frac,
                                ds=DS_PEAK_MM, tables=tables)
                row = {"r_edge_mm": r, "base": base, "modulus": mod_label, "R_N": round(st["R_N"], 4),
                       "p_max_MPa": round(st["p_max_MPa"], 1), "p_mean_MPa": round(st["p_mean_MPa"], 2),
                       "p_max_over_flow_pressure": {k: round(st["p_max_MPa"] / v, 3) for k, v in flow.items()},
                       "area_mm2": round(st["area_mm2"], 5), "patch_s_mm": [round(v, 4) for v in st["patch_s_mm"]],
                       "patch_half_width_mm": round(st["patch_half_width_mm"], 4),
                       "free_end_within_t_of_patch": st["patch_s_mm"][0] < T_LINER_MM}
                patch.append(row)
                print(f"  r {r:4.2f} {base:<12s} {mod_label:<13s} p_max {row['p_max_MPa']:6.1f} (×{row['p_max_over_flow_pressure']['1.0']:.2f} σ_y) "
                      f"p_mean {row['p_mean_MPa']:5.2f} A {row['area_mm2']:.4f} mm² patch {row['patch_s_mm']}")

    # ── (c) the sliding, against a rigid wall at the same edge (bonded, short-term, µ max) ─────────────────
    banner("(c) in-contact sliding per cycle — the model against a rigid wall at the same edge")
    slide = []
    for r in R_EDGE_SWEEP_MM:
        st = solve_exit(geo, liner, zero_play, mu_max * s55.F_POGO_N, r, tables=tables)
        rig_t = rigid_point(geo, liner, zero_play, mu_max * s55.F_POGO_N, geo.pad_mm - r)
        s_m, s_t = slide_um(geo, liner, zero_play, st), slide_um(geo, liner, zero_play, rig_t)
        slide.append({"r_edge_mm": r, "slide_um_model": round(s_m, 5), "slide_um_rigid_same_edge": round(s_t, 5),
                      "compliance_share": round((s_m - s_t) / s_m, 3)})
        print(f"  r {r:4.2f}: model {s_m:.4f} µm · rigid wall at the same edge {s_t:.4f} → the compliance carries "
              f"{(s_m - s_t) / s_m:.0%}")

    # ── (d) the wear path — the exit wall receding by w (a CONFORMAL flare: the upper bound of the slope) ────
    banner("(d) the wear path — the cycle peak against exit wear, the mouth's engagement and the saturation after it")
    rod = Rod(geo, liner)
    x_m = geo.gap_mm
    sat = signed_sigma(touchdown_drag(rod, zero_play, x_m) * rod.L)              # touchdown at the (unworn) mouth
    slope_mouth = signed_sigma(1e-3 / float(rod.defl(x_m, rod.L)) * rod.L)        # per µm of MOUTH wear
    wear = []
    for r in (0.0, R_EDGE_REFERENCE_MM):
        x_t = rod.L - r
        shape_mouth = float(rod.defl(x_m, rod.L) / rod.defl(x_t, rod.L))           # mouth deflection per unit at x_t
        w_mouth = zero_play / shape_mouth - zero_play
        sig_td = [signed_sigma(touchdown_drag(rod, zero_play + w / 1e3, x_t) * rod.L) for w in (0.0, 1.0)]
        slope = sig_td[1] - sig_td[0]
        assert abs(sig_td[0] + slope * w_mouth * 1e3 - sat) < 0.01, "the exit-wear path does not meet the mouth's touchdown"
        wear.append({"r_edge_mm": r, "peak_sigma_MPa_unworn_rigid": round(sig_td[0], 3),
                     "slope_MPa_per_um_of_exit_wear_conformal_bound": round(slope, 4),
                     "mouth_engages_at_exit_wear_um": round(w_mouth * 1e3, 1),
                     "peak_saturates_at_MPa": round(sat, 2),
                     "slope_MPa_per_um_of_mouth_wear": round(slope_mouth, 4),
                     "mouth_wear_to_reach_68_upper_end_um": round((hi - sat) / slope_mouth, 1),
                     "reading": "the cycle peak (touchdown) on a rigid wall receded by w at the exit; the slope assumes the "
                                "receded wall follows the rod's touchdown shape back to the mouth (a conformal flare) — a "
                                "short scar moves the touchdown to its rim and climbs less, so it is an UPPER bound; past "
                                "the mouth's engagement the touchdown is at the mouth and the peak stops rising, and 68's "
                                "upper end needs the MOUTH to wear as well"})
        print(f"  r {r:4.2f}: peak {sig_td[0]:.3f} MPa unworn, ≤ +{slope:.4f} MPa per µm of exit wear; the mouth engages after "
              f"{w_mouth * 1e3:.1f} µm and the peak saturates at {sat:.2f} MPa; 68's upper end then needs "
              f"{(hi - sat) / slope_mouth:.0f} µm of MOUTH wear at {slope_mouth:.3f} MPa/µm")

    # ── (e) the pad couple — a pogo contact off the rod axis (68 (d)), over a REVERSING drag ─────────────
    # The extremes of a reversing cycle are the two TOUCHDOWN values (after touchdown the root only falls), and at
    # touchdown R → 0, so the elastic and the rigid states coincide: closed form. By symmetry the − wall with +e is
    # the + wall with −e, sign reversed — so the cycle runs from −σ_td(−e) to +σ_td(+e).
    banner(f"(e) a pogo contact off the rod axis — couple F_pogo·e at the rod end, reversing drag, r {R_EDGE_REFERENCE_MM} mm")
    x_t = rod.L - R_EDGE_REFERENCE_MM
    pad68 = {round(p_["eccentricity_mm"], 3): p_["sigma_root_MPa"] for p_ in d68["pad_moment_at_rod_radius"] if p_["geometry"] == geo.label}
    for e_, sig68 in pad68.items():
        mine = abs(rigid_point(geo, liner, zero_play, mu_max * s55.F_POGO_N, rod.L, s55.F_POGO_N * e_)["sigma_signed_MPa"])
        assert abs(mine / sig68 - 1) < 0.01, f"pad couple ≠ 68 (d) at e {e_}: {mine} vs {sig68}"
    ctl["pad_couple_vs_68"] = {str(e_): [round(abs(rigid_point(geo, liner, zero_play, mu_max * s55.F_POGO_N, rod.L, s55.F_POGO_N * e_)["sigma_signed_MPa"]), 3), v]
                               for e_, v in pad68.items()}

    def td_sigma(e_mm: float) -> float:
        m_pad = s55.F_POGO_N * e_mm
        return signed_sigma(touchdown_drag(rod, zero_play, x_t, m_pad) * rod.L + m_pad)
    pad = []
    amp0 = td_sigma(0.0)
    for e_ in sorted({abs(v) for v in PAD_ECCENTRICITY_MM}):
        hi_e, lo_e = td_sigma(e_), td_sigma(-e_)
        pad.append({"eccentricity_mm": e_, "touchdown_sigma_MPa_plus_e": round(hi_e, 3), "touchdown_sigma_MPa_minus_e": round(lo_e, 3),
                    "cycle_amplitude_MPa": round((hi_e + lo_e) / 2, 3), "cycle_mean_MPa": round((hi_e - lo_e) / 2, 3),
                    "exit_section_sigma_from_the_couple_MPa": round(s55.root_sigma_MPa(s55.F_POGO_N * e_ * MM_M), 3)})
        print(f"  |e| {e_:.2f} mm: reversing cycle {-lo_e:+.3f} … {hi_e:+.3f} MPa → amplitude {(hi_e + lo_e) / 2:.3f} "
              f"(on-axis {amp0:.3f}), mean {(hi_e - lo_e) / 2:+.3f}; the exit section carries ≈ the couple, "
              f"{s55.root_sigma_MPa(s55.F_POGO_N * e_ * MM_M):.2f} MPa nominal")
    # ── (f) sensitivity at the reference edge: plays, the lock window's shallow end, the counterface ───────
    banner(f"(f) sensitivity — r {R_EDGE_REFERENCE_MM} mm, bonded, short-term")
    sens = []
    alloys_by_e = sorted(ALLOY_PROPERTIES, key=lambda a_: ALLOY_PROPERTIES[a_]["E_GPa"])
    cases = [("play", lb, geo, plays[lb] / 1000.0, ALLOY_BASELINE) for lb in plays if lb != "zero interference"]
    cases += [("geometry", g.label, g, zero_play, ALLOY_BASELINE) for g in geos if g.label != geo.label]
    cases += [("counterface", f"{a_} (E {ALLOY_PROPERTIES[a_]['E_GPa']:.0f} GPa)", geo, zero_play, a_) for a_ in (alloys_by_e[0], alloys_by_e[-1])]
    cases += [("counterface", "rigid Ti", geo, zero_play, None)]
    for kind, label, g, play, ti in cases:
        lo_, hi_ = bracket(g.label, label if kind == "play" else "zero interference")
        path = drag_path(g, liner, play, R_EDGE_REFERENCE_MM, ti=ti, tables=tables)
        row = {"kind": kind, "case": label, "geometry": g.label, "radial_play_um": round(play * 1e3, 2),
               "rigid_end_68_MPa": lo_, **summarise(path, lo_, hi_, play, g, "bonded", with_friction=False, x_t=g.pad_mm - R_EDGE_REFERENCE_MM)}
        sens.append(row)
        print(f"  {kind:<12s} {label[:44]:<44s} peak {row['peak_sigma_MPa']:.3f} (68's rigid end {lo_}) · at µ {mu_max} "
              f"{row['sigma_at_mu_MPa'][str(mu_max)]:.3f} · δ_c {row['delta_c_um_at_mu_max']:.3f} µm")

    # ── (g) the countersink: the Ti edge at depth e below the rod end ────────────────────────────────────
    banner(f"(g) the countersink — Ti edge e below the rod end (02_02 §1.2, depth unset), r {R_EDGE_REFERENCE_MM} mm, bonded, short-term")
    over = []
    for e in OVERHANG_SWEEP_MM:
        path = drag_path(geo, liner, zero_play, R_EDGE_REFERENCE_MM, e=e, tables=tables)
        row = {"overhang_mm": e, **summarise(path, lo, hi, zero_play, geo, "bonded", with_friction=True,
                                              x_t=geo.pad_mm - e - R_EDGE_REFERENCE_MM)}
        row["root_moment_reverses_on_the_path"] = min(row["sigma_root_signed_MPa"]) < 0
        row["ring_bore_must_clear_the_channel_by_um"] = round(max(0.0, row["tip_past_bore_line_um_at_mu_max"]), 2)
        over.append(row)
        print(f"  e {e:3.1f} mm: peak {row['peak_sigma_MPa']:.3f} (×{row['peak_over_68_rigid_end']:.3f} of 68's rigid end) · "
              f"at µ {mu_max} {row['sigma_at_mu_MPa'][str(mu_max)]:+.3f} · sub-cycle {row['subcycle_range_MPa']:.2f} · "
              f"slide {row['slide_per_cycle_um_at_mu_max']:.3f} µm · tip past the bore line {row['tip_past_bore_line_um_at_mu_max']:+.2f} µm")

    # where the full-drag root moment reverses — a rigid wall at the same edge (elastic is within the compliance shift)
    def m_full(e_: float) -> float:
        return rigid_point(geo, liner, zero_play, mu_max * s55.F_POGO_N, geo.pad_mm - e_ - R_EDGE_REFERENCE_MM)["sigma_signed_MPa"]
    lo_e, hi_e = 0.0, max(OVERHANG_SWEEP_MM)
    assert m_full(lo_e) > 0 > m_full(hi_e), "no reversal inside the swept overhang"
    for _ in range(40):
        mid = 0.5 * (lo_e + hi_e)
        lo_e, hi_e = (mid, hi_e) if m_full(mid) > 0 else (lo_e, mid)
    reversal_e = 0.5 * (lo_e + hi_e)
    print(f"  the full-drag root moment reverses at e ≈ {reversal_e:.2f} mm (rigid wall at the same edge, µ {mu_max})")

    # ── (h) the wear budget's readings beside script 55's two ends ───────────────────────────────────────
    banner("(h) wear budget — area and sliding beside 55's flow bound and upper end (liner, shipped geometry, µ max)")
    wb = d55["wear_budget"]
    c55 = next(b for b in d55["clearance_regime"]["branches"] if b["geometry"] == geo.label and b["branch"] == liner["branch"])
    w55 = next(r_ for r_ in wb["rows"] if r_["geometry"] == geo.label and r_["branch"] == liner["branch"]
               and r_["regime"] == "coaxial" and r_["mu"] == mu_max)
    s_upper = c55["by_mu"][str(mu_max)]["in_contact_rotation_path_per_cycle_um_upper"]
    a_flush = [r_["area_mm2"] for r_ in patch]
    s_flush = [r_["slide_per_cycle_um_at_mu_max"] for r_ in cycle]
    s_over = [r_["slide_per_cycle_um_at_mu_max"] for r_ in over]
    wear_read = {"mu": mu_max, "area_mm2_55_flow_bound": w55["area_material_bound_mm2"],
                 "area_mm2_55_projected_run": w55["area_projected_full_run_mm2"],
                 "area_over_flow_bound_flush": [round(min(a_flush) / w55["area_material_bound_mm2"], 1),
                                                round(max(a_flush) / w55["area_material_bound_mm2"], 1)],
                 "slide_per_cycle_um_55_upper": s_upper,
                 "slide_per_cycle_um_flush": [round(min(s_flush), 4), round(max(s_flush), 4)],
                 "slide_per_cycle_um_countersink": [round(min(s_over), 4), round(max(s_over), 4)],
                 "upper_over_slide_flush_min": round(s_upper / max(s_flush), 1),
                 "upper_over_slide_countersink_min": round(s_upper / max(s_over), 1),
                 "reading": "frictionless kinematic sliding (a ceiling), on an unworn wall; the landing at each reversal "
                            "of the drag (impact / partial-slip fretting) is not modelled"}
    print(f"  area ×{wear_read['area_over_flow_bound_flush'][0]}–{wear_read['area_over_flow_bound_flush'][1]} the flow bound "
          f"(flush); sliding ≤ 1/{wear_read['upper_over_slide_flush_min']} of 55's upper end flush, "
          f"≤ 1/{wear_read['upper_over_slide_countersink_min']} with the countersink")

    elapsed = time.time() - t0
    # ── the summary: every clause from a field above (claims A–J of the docstring's reading order) ───────
    peak = [r_["peak_sigma_MPa"] for r_ in cycle]
    peak_ratio = [r_["peak_over_68_rigid_end"] for r_ in cycle]
    dc = [r_["delta_c_um_at_mu_max"] for r_ in cycle]
    lift = [r_["peak_lift_by_radius_over_flush_MPa"] for r_ in cycle]
    comp = [r_["full_drag_shift_by_compliance_MPa"] for r_ in cycle]
    sub_ratio = max(r_["subcycle_range_MPa"] / r_["subcycle_rigid_same_edge_MPa"] for r_ in cycle)
    fr_loop = max(r_["friction_mu_c_max"]["loop_range_MPa"] for r_ in cycle if r_["base"] == "bonded")
    fr_moves = sorted({r_["r_edge_mm"] for r_ in cycle if r_["base"] == "bonded" and r_["friction_mu_c_max"]["peak_moves_to_full_drag"]})
    pk_by_r = {r: max(p_["p_max_MPa"] for p_ in patch if p_["r_edge_mm"] == r) for r in R_EDGE_SWEEP_MM}
    over_flow = [r for r, v in pk_by_r.items() if v > flow["1.0"]]
    share = [s_["compliance_share"] for s_ in slide]
    pmax = max(pad, key=lambda p_: p_["eccentricity_mm"])
    over_peak = (min(r_["peak_over_68_rigid_end"] for r_ in over), max(r_["peak_over_68_rigid_end"] for r_ in over))
    tip_td = (min(r_["tip_past_bore_line_um_at_touchdown"] for r_ in over), max(r_["tip_past_bore_line_um_at_touchdown"] for r_ in over))
    w0 = wear[0]
    summary = (f"Coaxial pogo drag, unworn wall, flush exit with a rounding. (A) The liner gives {min(dc):.2f}–{max(dc):.2f} µm "
               f"at full drag against a {T_LINER_MM * 1e3:.0f} µm wall. (B) The cycle PEAK sits at or just after touchdown: "
               f"{min(peak):.3f}–{max(peak):.3f} MPa, ×{min(peak_ratio):.3f}–{max(peak_ratio):.3f} of 68's {lo} MPa — on a rigid "
               f"wall at the same edge it is F_td·L, the edge radius lifting it by ≤ {max(lift):.3f} MPa over the flush value, and "
               f"while the patch is tiny the give lifts it by ≤ {max(r_['peak_lift_by_compliance_MPa'] for r_ in cycle):.3f} MPa "
               f"more (68's sign). (C) On the LOADED part the sign turns: at full drag the compliance lowers the root by "
               f"{-max(comp):.2f}–{-min(comp):.2f} MPa against a rigid wall at the same edge — the opposite sign to 68's "
               f"3EI·(R/k)/L², because the patch spreads inside the bore — and deepens the sub-cycle (touchdown → full drag) up to "
               f"×{sub_ratio:.1f} of the rigid one. (D) The bracket's upper end is not an elastic state: the peak climbs ≤ "
               f"{w0['slope_MPa_per_um_of_exit_wear_conformal_bound']:.3f} MPa per µm of exit wear (a conformal-flare bound), the "
               f"mouth engages after {w0['mouth_engages_at_exit_wear_um']:.0f} µm and the peak saturates at "
               f"{w0['peak_saturates_at_MPa']:.2f} MPa; 68's {hi} MPa needs {w0['mouth_wear_to_reach_68_upper_end_um']:.0f} µm of "
               f"MOUTH wear on top. (E) Edge peak at µ {mu_max}, {DS_PEAK_MM} mm step, worst row: "
               + " · ".join(f"r {r} mm → {v:.0f} MPa" for r, v in pk_by_r.items())
               + (f"; above 1·σ_y at r {', '.join(str(v) for v in over_flow)} mm" if over_flow else "; below 1·σ_y (23 °C tensile) at every swept radius")
               + f"; the elastic patch is ×{wear_read['area_over_flow_bound_flush'][0]:.0f}–{wear_read['area_over_flow_bound_flush'][1]:.0f} "
               f"55's flow bound. (F) The frictionless sliding — a kinematic ceiling — is at most "
               f"1/{wear_read['upper_over_slide_flush_min']:.0f} of 55's upper end, and the compliance carries "
               f"{min(share):.0%}–{max(share):.0%} of it against a rigid wall at the same edge (more at a tighter edge). (G) A pogo "
               f"contact off the rod axis by ±{pmax['eccentricity_mm']} mm moves the MEAN of a reversing cycle by "
               f"{pmax['cycle_mean_MPa']:+.2f} MPa and leaves its amplitude at {pmax['cycle_amplitude_MPa']:.2f} MPa (on axis "
               f"{amp0:.2f}); the exit section then carries ≈ the couple, {pmax['exit_section_sigma_from_the_couple_MPa']:.1f} MPa "
               f"nominal. (H) Lumped full-stick friction (an upper estimate) widens the loading/unloading loop to ≤ {fr_loop:.2f} MPa"
               + (f" and moves the peak to full drag at r {', '.join(str(v) for v in fr_moves)} mm" if fr_moves else "")
               + f". (I) The ratified countersink is CONDITIONAL: the tip is past the bore line already at touchdown "
               f"({tip_td[0]:.1f}–{tip_td[1]:.1f} µm), so a ring whose bore equals the channel's is the FIRST contact, which no model "
               f"here has; only for a ring that clears it do the rows hold — peak ×{over_peak[0]:.3f}–{over_peak[1]:.3f} of 68's "
               f"figure, the full-drag moment reversing beyond e ≈ {reversal_e:.2f} mm, the sub-cycle up to "
               f"{max(r_['subcycle_range_MPa'] for r_ in over):.2f} MPa, the sliding up to 1/{wear_read['upper_over_slide_countersink_min']:.0f} "
               f"of 55's upper end. (J) A sharp Ti edge INSIDE the layer (the countersink's, the mouth's) is a punch edge — peak "
               f"×{ctl['sharp_edge_inside_the_layer']['growth_per_halving'][0]:.2f} per halving of the step; the flush sharp corner "
               "of the shipped CAD is outside the kernel, bounded only for a frictionless contact. MODELLED, not measured; no "
               "radius is proposed — the trade it names is weighed by a measured wear rate and slip regime, not by this model.")
    out = {
        "question": "Where does the root of the bus rod sit inside 68's coaxial bracket over the drag CYCLE once the "
                    "liner's contact with the Ti channel at the exit is an elastic-layer contact — and what are its "
                    "patch, its edge pressure, its in-contact sliding and the terms that move the root besides the "
                    "contact's give (00_07 HW.34 / HW.23)",
        "inputs": {"source": "geometry, member EI, pogo force, µ and µ_c sweeps, constraint factors imported from "
                             "55_bus_mechanical.py; the coaxial bracket, the plays and the pad-couple rows loaded from 68's "
                             "cache; 55's wear rows loaded from its cache",
                   "geometry": geo.label, "pad_mm": geo.pad_mm, "gap_mm": geo.gap_mm, "liner_from_mm": geo.liner_from_mm,
                   "liner_wall_mm": T_LINER_MM, "liner_od_mm": 2 * R_OD_MM, "E_PEEK_MPa": E_PEEK_MPA, "nu_PEEK": NU_PEEK,
                   "relaxed_modulus_fraction": PEEK_RELAX_FLOOR, "counterface_alloy": ALLOY_BASELINE,
                   "sigma_yield_PEEK_MPa_tensile_23C": SIGMA_YIELD_PEEK_PA / 1e6,
                   "flow_pressures_MPa_55": flow, "mu_c_sweep_55": list(mu_c),
                   "r_edge_sweep_mm": list(R_EDGE_SWEEP_MM), "overhang_sweep_mm": list(OVERHANG_SWEEP_MM),
                   "pad_eccentricity_mm": list(PAD_ECCENTRICITY_MM), "r_edge_reference_mm": R_EDGE_REFERENCE_MM,
                   "grid_mm": {"ds_path": DS_MM, "ds_peak": DS_PEAK_MM, "dy": DY_MM},
                   "radial_play_um": plays["zero interference"], "rigid_end_68_MPa": lo, "upper_end_68_MPa": hi,
                   "rigid_flush_touchdown_MPa_unrounded": round(flush_td, 4)},
        "controls": ctl, "cycle": cycle, "patch": patch, "sliding": slide, "wear_path": wear, "pad_couple": pad,
        "pad_on_axis_amplitude_MPa": round(amp0, 3), "sensitivity": sens, "countersink": over,
        "countersink_full_drag_reversal_overhang_mm": round(reversal_e, 3), "wear_readings": wear_read,
        "summary": summary,
        "not_modelled": {"plasticity": "linear elastic; a peak above the flow pressure is flagged, never redistributed",
                         "layer_shape": "flat, uniform layer: the tube's curvature (a cylindrical confined column is "
                                        "≈ 1.14× more compliant — δ_c may be ~14 % low) and its free end at the pad plane "
                                        "are not modelled; rows with r < t sit nearest that end and their peak is biased high",
                         "flush_sharp_corner": "outside the kernel (it continues the layer past the pad plane); for "
                                               "coplanar free faces on a FRICTIONLESS counterface the corner stress is "
                                               "bounded (the reflected wedge is 180° with both faces free); under stick the "
                                               "corner is a clamped–free 90° wedge, weakly singular (≈ ρ^−0.35 at ν 0.4)",
                         "base": "the hot-mounted tube grips the wire by interference — neither bonded nor frictionless; "
                                 "both are reported as a bracket",
                         "creep": "the 20-yr relaxed modulus (lib PEEK_RELAX_FLOOR, a constant-strain figure) is used for "
                                  "a constant-load contact by linear-viscoelastic correspondence; it LOWERS the edge peak, "
                                  "so for the peak it is the anti-conservative end",
                         "friction": "not in the solve; a lumped couple at the patch centroid, rigid in shear, from zero to "
                                     "full stick capped at µ_c·R·r_OD (µ_c from 55's PEEK–Ti sweep) — an upper estimate; "
                                     "the sliding figures are frictionless kinematic ceilings",
                         "thermal_axial_pdelta": "no thermal term (the cold liner's ≈ 1 µm radial pull-back per 40 K "
                                                 "moves 68's lower end by ≈ 0.13 MPa), no P-δ of the 1 N axial pogo force",
                         "wear": "no wear in the contact solve; block wear_path is a rigid wall receded at the exit as a "
                                 "conformal flare (an upper bound of the slope — a short scar climbs less), and past the "
                                 "mouth's engagement it reports the saturation, not a two-station solve",
                         "ring_and_closure": "the countersink's PEEK ring and the ratified exit closure element are not "
                                             "modelled; the tip is past the bore line already at touchdown, so a ring "
                                             "whose bore equals the channel's is the FIRST contact and every countersink "
                                             "row holds only for a ring that clears it",
                         "pad_couple": "the reversing cycle's extremes are taken at touchdown on each wall (closed form, "
                                       "elastic = rigid there); the path between, with the − wall in play, is not solved",
                         "mouth": "the mouth (the station under a channel offset) is not computed here",
                         "landing": "each reversal of the drag lands the tube on the opposite wall; the impact / "
                                    "partial-slip fretting of that landing is not modelled"},
    }
    OUT_JSON.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    banner("Summary")
    print("  " + summary)
    print(f"  → {OUT_JSON.relative_to(CACHE_DIR.parent)} ({elapsed:.0f} s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
