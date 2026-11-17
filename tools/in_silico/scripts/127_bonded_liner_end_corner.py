#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""127 — the bus wire at the END of its PEEK liner: how much does the end where the layer stops on the Ti concentrate
the stress, and does that section then out-rank the sections `97` modelled?

WHY. `97` read the liner's lower end, not modelled it: the bare side's nominal per face, and the factor its corner would
need to tie the governing modelled section — ×1.05 at a perfect seam (k 1), ×1.74 at k 0.388 on its bonded base — of the
order of the liner's own stiffening of the wire (×1.067), so «not bounded there» (00_07 HW.34, 01_01 §1.4 ⊕ 2026-10-16).
This script models the end. in-silico §When Modifying #41 — the BODIES: the Ø1.0 Ti wire (the anode alloy; the
baseline, as in `97`) and the 0.15 mm PEEK layer on it, stopping at z = 0 with a square, traction-free end face.

TWO CLASSES OF READING, kept apart in every output:
  DESIGN — canon holds the tube by FRICTION after a hot mount (01_01 §3, steps 4a and 5; `55` — its PEEK–Ti µ sweep):
    SLIP — frictionless contact (radial displacement tied, both tangential free): no axial transfer, the lower end;
    FRICTION — slip plus the end zone where a Coulomb grip slides: τ(z) = µ·p(z), p the contact pressure of the TOTAL
      field (the friction's own normal stress included — a damped fixed point), over the zone [−ℓ, 0] that carries F, the
      tube's axial force a full axial lock would hold at that service temperature (the misfit Δα·(T − T_lock)); beyond
      ℓ the interface is FRICTIONLESS and the lock enters only as the transferred force (stress-equivalent to a stuck
      zone far from ℓ; the stick zone's shear-lag tail is lumped into the slip zone, its sign on the end's mean not
      established — distances beyond ℓ − 0.2 mm are marked UNCOVERED); near the end τ = µ·p does not depend on F, so
      T_lock acts only through the SIGN of the misfit at the service temperature (a grip that would push outward —
      T above T_lock — is NOT priced: that reading falls back to slip and says so); where the friction itself lifts the
      grip's edge, a distance is ADMISSIBLE only at 0.9·d ≥ 3 × the lift length; µ at the ends of `55`'s PEEK–Ti sweep;
      T_lock at T_g (the mount passes PEEK at 150 °C) ⊥ at the assembly temperature;
  ADHESIVE ONLY — what an adhesive bond would add (NOT the design): the BONDED bending; the radial fit as a slip fit
    leaves it plus a bonded axial lock of Δα·(T − T_lock), T_lock at the assembly temperature ⊥ at T_g; STUCK — the same
    with the axial misfit equal to the radial one (−δ/D) added: an adhesive extreme.

LOAD PATHS ON THIS END (in-silico §Critical Rules #15 — inventoried before any is priced):
  (A) the sway's BENDING — an AMPLITUDE: Fourier mode n = 1, pure bending, the moment constant (the end sits off `92`'s
      contact patches, where `97` reads the bare side's nominal);
  (B) the THERMAL mismatch PEEK ⊥ Ti, n = 0: the RADIAL fit's change against the assembly temperature (`55`'s convention,
      lib T_ASSEMBLY_C — the ratified interference is the 20 °C geometry, so the hot mount's radial history is already in
      it) and the AXIAL lock against T_lock (the readings above), at canon's forest extremes (lib T_FOREST_MIN_C ·
      T_FOREST_MAX_C): MEANS;
  (C) the INTERFERENCE of the ratified bore (wire Ø − 11.41 µm, `55`) — n = 0, the layer's in-plane shrink to the bore: a
      MEAN; at the short-term PEEK modulus and the retained one (lib PEEK_RELAX_FLOOR);
  (D) the channel contact near the end — NOT here (a patch reaching the end is `97`'s ceiling);
  (E) the seam's own field (its residual stress — a mean the ROOT carries and `97` does not model), the pad couple, wear,
      friction on the layer's top — NOT here (`97`'s ceilings, carried).

MODEL. Linear elasticity; the wire a solid Ti cylinder of radius R, the layer an annulus R … R + t over z < 0. Semi-
analytical axisymmetric FE: u_r = U cos nθ, u_θ = V sin nθ, u_z = W cos nθ (n = 1 for (A); n = 0 with V ≡ 0 otherwise),
biquadratic Lagrange elements (Q9, 3 × 3 Gauss — pure bending lies in their span, so long thin elements away from the
end do not lock), a tensor mesh graded geometrically toward the corner (r = R, z = 0). SLIP: the layer's nodes on r = R
are duplicates tied to the wire's in U only — a frictionless contact, linear while it stays closed: ASSERTED on the slip
readings, RECORDED per friction reading (the mean radial stress plus the bending's peak radial stress compressive on the
interface from 0.5 µm on — where it is not, the grip's edge would lift and that reading's nearest distances are not
admissible). The friction: consistent nodal forces of τ(z) on the interface (toward −z on the Ti, +z on the tube — the
tube contracting toward its middle as it cools below T_lock). Ends: z = −L a symmetry plane (W = 0);
z = +L for (A) a plane rotation W = β·r, free otherwise. Axis regularity: n = 1 — V = −U and W = 0 on r = 0, one U fixed;
n = 0 — U = 0. The bonded corner's order: the two-wedge Williams eigenproblem in plane strain (Ti 180°, θ ∈ [−π, 0], free
at θ = 0; PEEK 90°, θ ∈ [π/2, π], free at π/2; bonded at θ = ±π); stresses ∝ d^(λ−1).

OUTPUT. On the Ti side, per distance d from the corner, the largest σ₁ (in-plane principal or σ_θθ) over the Ti Gauss
points at that distance (±10 %): for (A) over the bare side's far nominal (K(d)); for the means in MPa, the mean field
SUPERPOSED as a tensor before its principal value is taken. Then the end's Soderberg SF on `97`'s own line — POINT stress,
drawn wire, derate 1: amplitude K(d)·σ_a,bare, mean K(d)·σ_m,bare + σ₁ of the mean field — against the governing modelled
SF of `97`'s rows inside ⌀0.10 on the MATCHING base (design → frictionless, adhesive → bonded): the root at each k, the
stations under both edges; the lowest ratio over rows; per reading, modulus, ΔT ∈ {forest min, assembly, forest max} and
k; and, for the readings linear in ΔT, the temperature brackets where the ranking flips. ⚠️ BIAS, one-directional and
stated: the end carries its mounting mean, the ROOT carries none (its seam residual is (E)), and (B)'s far field is not
added to `97`'s stations under the layer — every «out-ranks» is therefore an UPPER estimate, every «at no reported
distance» the robust statement. ⚠️ The amplitude's and the mean's maxima may sit at different angles: their sum is an
arithmetic upper bound on the point's σ₁ (Weyl), not a bound on the physics; a point stress at a sharp elastic corner,
with no notch sensitivity, against sections that carry k or sit on `97`'s 5 µm grid — at d → 0 the bonded corner wins by
construction, so the verdict is read at named distances, never at 0; the smooth readings (the pressure band's edge) are
not singular, and a radius would not remove them.

CONTROLS asserted in-run: (1) the Williams solver on a HOMOGENEOUS 270° notch — the same 8 × 8 system, so the interface
continuity is exercised: its first two roots are Williams's 0.5445 and 0.9085; (2) the Williams displacements against the
stresses through Hooke's law by finite differences, in each material (a wrong displacement formula, independently of
any root); (3) the argument principle on Re λ ∈ [0.05, 0.98], |Im λ| ≤ 2 counts exactly the real roots found there (no
complex root missed); (4) the homogeneous FE case (layer = Ti, no end): the surface σ_zz under pure bending equals M·r/I
to 0.5 %, M by each element's own Gauss rule (catches the n = 1 B-matrix, axis and end conditions — NOT the factor π,
which scales K and f together); the bare far field equals M·R/I to 1 % on both interfaces; (5) far fields: under the
BONDED layer the wire's σ_zz equals σ_bare·EI_w/EI_c (1 %); the bonded thermal and the unit axial-lock far fields equal
the closed form of two bonded concentric cylinders under free axial strain (2 %); the slip interference's pressure equals
the two-cylinder Lamé shrink fit with an elastic wire and σ_z = 0 (1.5 %) — `55`'s rigid-wire pressure printed beside;
(6) the bonded corner's ORDER on a FIXED ray (the Ti free surface, bare side): σ_zz(d) fitted by B + A·d^s + C·d over
ORDER_BAND; the best s within 0.03 of λ − 1 AND fitting at least twice better than the homogeneous 270° order; (7) a
REFINED mesh (growth 1.15 against 1.3 — the local step ≈ (g − 1)·d, halved at every d) agrees on K(d) to 2 % and on
the larger of |σ₁|, |σ₃| of every mean field to 3 % at every reported d, the friction cap (ℓ = 1 mm) on σ₁ — the component
the readings take (its σ₃, near zero close to the corner, moves by large ratios of small numbers: cached, not asserted);
(8) the friction cap's equilibrium: the tube's axial force beyond the loaded zone equals τ·2πR·ℓ to 1 %; every Coulomb
zone transfers its lock force to 1 % (summed from the applied nodal forces); the Coulomb field itself (µ 0.4, T_g, forest
min) agrees on the refined mesh to 3 % from 10 to 100 µm — beyond 100 µm the ±10 % ring holds a few Gauss points and
the ring maximum moves by up to ≈ 6 % with the sampling (recorded, not asserted: the 200 and 500 µm columns carry it); the Gauss points of the two interface meshes
coincide (so fields from them may be superposed).

⛔ DECLARED CEILINGS: LINEAR elasticity at a SHARP corner — a real end has a meniscus, a radius, a chamfer or a debond,
and PEEK yields and creeps there (above T_g most of all, which would also relax the fit's edge mean); the FRICTION reading is
Coulomb FULL slip over the end zone with stick beyond, not a history solution — the grip's path (the hot mount, the press,
the seasons) is not followed, and a zone slid one way can lock in another; the slip and friction readings' corner order is not
derived (their K(d) stands on the FE and control 7); the FATIGUE relevance of a point stress d from the corner (a critical
distance — the theory of critical distances needs a ΔK_th and a plain limit of THIS wire, not in the tree; a grain size)
is NOT computed; the ROOT's own mean (the seam residual) and (B)'s far field on `97`'s stations are not added (the bias
above); the baseline alloy's E and ν (the bus alloy is HW.24's bake-off; `86` binds on Ta); T_lock is named, not known —
the grip's real locking temperature lies between the press and T_g; ONE α (ALPHA_PEEK_1K, 47·10⁻⁶ /K) over the whole
swing from T_lock down to −30 °C (~173 K) and E independent of temperature — the measured 450G α(T) grows toward
the top of its −100…+100 °C window and the datasheet's mean up to 143 °C is 55 «Average», so the misfit's size is
a reading of one value, not of the curve (00_07 HW.26: the 45/55 swap flipped no flag here); (D) and (E) not here; one end geometry (a square end
face, the full wall); the wire straight, the moment constant; `97` rows that refused path points are used as `97` uses
them, and named in the cache.

Run:  conda activate silken_md
      python tools/in_silico/scripts/127_bonded_liner_end_corner.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
import time
from pathlib import Path

import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla
from scipy.optimize import brentq

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    CACHE_DIR,
    E_PEEK_PA,
    NU_PEEK,
    PEEK_RELAX_FLOOR,
    PEEK_TG_C,
    REPO_ROOT,
    T_ASSEMBLY_C,
    T_FOREST_MAX_C,
    T_FOREST_MIN_C,
)
from lib.utils import banner

SI_DESCRIPTION = ("Stress concentration in the titanium bus wire at the end of a thin PEEK liner: a semi-analytical "
                  "axisymmetric finite-element model (Fourier modes 0 and 1) of the wire and the layer stopping with a "
                  "square end, in frictionless contact, with a friction-capped interfacial shear, or bonded, under "
                  "bending, the bore's interference and the thermal mismatch with the axial misfit locked at named "
                  "temperatures, against the two-wedge Williams singularity order of the bonded corner; the end's fatigue "
                  "safety factor against the wire's modelled sections, per distance from the corner")

MECH = CACHE_DIR / "mechanical"
OUT = MECH / "bonded_liner_end_corner.json"
SRC_97 = MECH / "wire_under_liner_edges.json"


def _load(name: str, fname: str):
    spec = importlib.util.spec_from_file_location(name, HERE / fname)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod             # 55 declares dataclasses, which look their module up here
    spec.loader.exec_module(mod)
    return mod


S55 = _load("s55", "55_bus_mechanical.py")
S92 = _load("s92", "92_liner_mouth_contact.py")
R_WIRE_MM = S55.D_BUS / 2.0
T_LINER_MM = S55.LINER_WALL_MM
INTERFERENCE_DIAM_MM = S55.D_BUS - S55.LINER_BORE_SPECIFIED_MM      # the ratified offset on the diameter
TOL_OFFSET_UM = S92.TOLERANCE_OFFSET_UM                             # ⌀0.10 — the offsets `97` judges inside
MU_ENDS = (min(S55.MU_PEEK_TI_SWEEP), max(S55.MU_PEEK_TI_SWEEP))    # `55`'s PEEK–Ti friction sweep, its two ends
TI = ALLOY_PROPERTIES[ALLOY_BASELINE]
E_TI, NU_TI, ALPHA_TI = TI["E_GPa"] * 1e3, TI["nu"], TI["alpha_1K"]  # MPa
E_PK, NU_PK, ALPHA_PK = E_PEEK_PA / 1e6, NU_PEEK, ALPHA_PEEK_1K       # MPa
D_ALPHA = ALPHA_PK - ALPHA_TI
T_SERVICE = {"forest_min": T_FOREST_MIN_C, "assembly": T_ASSEMBLY_C, "forest_max": T_FOREST_MAX_C}
T_LOCKS = {"lock_at_Tg": PEEK_TG_C, "lock_at_assembly": T_ASSEMBLY_C}
DT_SCAN = np.arange(-80.0, 80.5, 0.5)                               # ΔT against the assembly, beyond canon on both sides

L_HALF_MM = 6.0             # each side of the corner — ≥ 6 wire diameters to the ends
FRICTION_ZONE_CAP_MM = 5.5  # ℓ is capped inside the free length (the symmetry plane sits at 6 mm)
H_MIN_UM = 0.05             # the smallest element at the corner
GROWTH, GROWTH_REFINED = 1.3, 1.15
H_MAX_Z_MM = 0.25
H_MAX_R_MM = 0.05
D_REPORT_UM = (1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0, 500.0)
ORDER_BAND_UM = (1.0, 30.0)
ORDER_TOL = 0.03
CONTACT_CHECK_FROM_UM = 0.5
NOTCH_270 = (0.5445, 0.9085)  # Williams 1952, the 270° re-entrant corner, modes I and II (four decimals)


# ── the two-wedge Williams eigenproblem (plane strain) ───────────────────────────────────────────────────────────────
def _wedge_rows(lam, th, mu, kappa, cfun=math.cos, sfun=math.sin):
    """Coefficient rows (a, b, c, d) of σ_θθ, σ_rθ, u_r, u_θ at θ for φ = r^(λ+1)·F(θ), F = a cos(λ+1)θ + b sin(λ+1)θ
    + c cos(λ−1)θ + d sin(λ−1)θ; the powers of r dropped. `cfun`/`sfun` take complex λ for the argument principle."""
    p, m = lam + 1.0, lam - 1.0
    cp, sp_, cm, sm = cfun(p * th), sfun(p * th), cfun(m * th), sfun(m * th)
    s_tt = [lam * p * cp, lam * p * sp_, lam * p * cm, lam * p * sm]                 # λ(λ+1)F
    s_rt = [lam * p * sp_, -lam * p * cp, lam * m * sm, -lam * m * cm]               # −λF′
    u_r = [-p * cp / (2 * mu), -p * sp_ / (2 * mu), (kappa - lam) * cm / (2 * mu), (kappa - lam) * sm / (2 * mu)]
    u_t = [p * sp_ / (2 * mu), -p * cp / (2 * mu), (kappa + lam) * sm / (2 * mu), -(kappa + lam) * cm / (2 * mu)]
    return s_tt, s_rt, u_r, u_t


def _airy_fields(lam, th, coef, mu, kappa):
    a, b, c, d = coef
    p, m = lam + 1.0, lam - 1.0
    F = a * math.cos(p * th) + b * math.sin(p * th) + c * math.cos(m * th) + d * math.sin(m * th)
    F1 = -a * p * math.sin(p * th) + b * p * math.cos(p * th) - c * m * math.sin(m * th) + d * m * math.cos(m * th)
    F2 = (-a * p * p * math.cos(p * th) - b * p * p * math.sin(p * th)
          - c * m * m * math.cos(m * th) - d * m * m * math.sin(m * th))
    rows = _wedge_rows(lam, th, mu, kappa)
    return (p * F + F2, lam * p * F, -lam * F1,
            sum(x * y for x, y in zip(rows[2], coef, strict=True)), sum(x * y for x, y in zip(rows[3], coef, strict=True)))


def williams_matrix(lam, mat_ti, mat_pk, cplx=False):
    (mu1, k1), (mu2, k2) = mat_ti, mat_pk
    cf, sf = (np.cos, np.sin) if cplx else (math.cos, math.sin)
    t0 = _wedge_rows(lam, 0.0, mu1, k1, cf, sf)
    t9 = _wedge_rows(lam, math.pi / 2, mu2, k2, cf, sf)
    ti = _wedge_rows(lam, -math.pi, mu1, k1, cf, sf)
    pk = _wedge_rows(lam, math.pi, mu2, k2, cf, sf)
    rows = [t0[0] + [0] * 4, t0[1] + [0] * 4, [0] * 4 + t9[0], [0] * 4 + t9[1]]
    rows += [ti[j] + [-x for x in pk[j]] for j in range(4)]
    return np.array(rows, dtype=complex if cplx else float)


def _scaled_det(lam, mat_ti, mat_pk):
    M = williams_matrix(lam, mat_ti, mat_pk)
    return float(np.linalg.det(M / np.maximum(np.abs(M).max(axis=0), 1e-300)))


def williams_roots(mat_ti, mat_pk, lo=0.02, hi=1.6, n=4000):
    """Real roots of det M(λ) in (lo, hi): sign changes of the column-scaled determinant, refined by Brent, kept only
    where the scaled matrix is numerically singular (a pole also changes sign — refused)."""
    xs = np.linspace(lo, hi, n)
    fs = [_scaled_det(x, mat_ti, mat_pk) for x in xs]
    roots = []
    for x0, x1, f0, f1 in zip(xs[:-1], xs[1:], fs[:-1], fs[1:], strict=True):
        if f0 * f1 < 0:
            r = brentq(_scaled_det, x0, x1, args=(mat_ti, mat_pk), xtol=1e-13)
            M = williams_matrix(r, mat_ti, mat_pk)
            sv = np.linalg.svd(M / np.maximum(np.abs(M).max(axis=0), 1e-300), compute_uv=False)
            if sv[-1] / sv[0] < 1e-8:
                roots.append(float(r))
    return roots


def zeros_in_rectangle(mat_ti, mat_pk, re=(0.05, 0.98), im=2.0, n=6000):
    """The argument principle: the number of zeros of det M(λ) (entire in λ) inside the rectangle."""
    a, b = re
    edges = [np.linspace(complex(a, -im), complex(b, -im), n), np.linspace(complex(b, -im), complex(b, im), n),
             np.linspace(complex(b, im), complex(a, im), n), np.linspace(complex(a, im), complex(a, -im), n)]
    dets = np.array([np.linalg.det(williams_matrix(z, mat_ti, mat_pk, cplx=True)) for z in np.concatenate(edges)])
    arg = np.unwrap(np.angle(dets))
    return round((arg[-1] - arg[0]) / (2 * math.pi))


def mat_pair(E, nu):
    return E / (2 * (1 + nu)), 3 - 4 * nu


def williams_controls():
    ti, pk = mat_pair(E_TI, NU_TI), mat_pair(E_PK, NU_PK)
    first = williams_roots(ti, ti)[:2]
    assert len(first) == 2 and all(abs(a - b) < 6e-4 for a, b in zip(first, NOTCH_270, strict=True)), \
        f"Williams solver: homogeneous 270° notch roots {first}, expected {NOTCH_270}"
    lam, coef, th, h = 0.37, (0.3, -0.7, 1.1, 0.4), 0.731, 1e-6
    for E, nu in ((E_TI, NU_TI), (E_PK, NU_PK)):
        mu, kappa = mat_pair(E, nu)
        s_rr, s_tt, s_rt, ur, ut = _airy_fields(lam, th, coef, mu, kappa)
        _, _, _, ur_p, ut_p = _airy_fields(lam, th + h, coef, mu, kappa)
        _, _, _, ur_m, ut_m = _airy_fields(lam, th - h, coef, mu, kappa)
        dur, dut = (ur_p - ur_m) / (2 * h), (ut_p - ut_m) / (2 * h)
        e_rr, e_tt, g_rt = lam * ur, ur + dut, dur + (lam - 1) * ut      # u ∝ r^λ, at r = 1
        scale = max(1.0, abs(s_rr), abs(s_tt), abs(s_rt))
        assert abs(2 * mu * e_rr - (s_rr - nu * (s_rr + s_tt))) < 1e-6 * scale, "Williams u_r against Hooke"
        assert abs(2 * mu * e_tt - (s_tt - nu * (s_rr + s_tt))) < 1e-6 * scale, "Williams u_θ against Hooke"
        assert abs(mu * g_rt - s_rt) < 1e-6 * scale, "Williams γ_rθ against Hooke"
    roots_b = williams_roots(ti, pk)
    in_strip = [x for x in roots_b if 0.05 < x < 0.98]
    count = zeros_in_rectangle(ti, pk)
    assert count == len(in_strip), f"argument principle counts {count} zeros, real roots in the strip {in_strip}"
    return {"homogeneous_270_roots": first, "bimaterial_real_roots_below_1_6": roots_b,
            "zeros_in_strip_argument_principle": count, "strip": {"re": [0.05, 0.98], "im_abs_max": 2.0}}


# ── semi-analytical axisymmetric FE, Q9 ─────────────────────────────────────────────────────────────────────────────
def graded(length, h_min, growth, h_max):
    xs, h = [0.0], h_min
    while xs[-1] + h < length:
        xs.append(xs[-1] + h)
        h = min(h * growth, h_max)
    if length - xs[-1] < 0.5 * (xs[-1] - xs[-2]):
        xs[-1] = length
    else:
        xs.append(length)
    return np.array(xs)


def build_mesh(h_min_mm, growth, interface="bonded", homogeneous=False):
    """Q9 tensor mesh; for `slip` the layer's nodes on r = R are duplicates, returned as (duplicate, wire node) ties."""
    R, t, L = R_WIRE_MM, T_LINER_MM, L_HALF_MM
    r_wire = np.sort(R - graded(R, h_min_mm, growth, H_MAX_R_MM))
    r_liner = R + graded(t, h_min_mm, growth, H_MAX_R_MM)[1:]
    r_c = np.concatenate([r_wire, r_liner])
    z_pos = graded(L, h_min_mm, growth, H_MAX_Z_MM)
    z_c = np.concatenate([-z_pos[::-1], z_pos[1:]])
    r_n = np.empty(2 * len(r_c) - 1)
    r_n[0::2], r_n[1::2] = r_c, 0.5 * (r_c[:-1] + r_c[1:])
    z_n = np.empty(2 * len(z_c) - 1)
    z_n[0::2], z_n[1::2] = z_c, 0.5 * (z_c[:-1] + z_c[1:])
    n_wire = len(r_wire) - 1
    a_R = 2 * n_wire                                                       # the r-index of r = R
    elems, mats = [], []
    for i in range(len(r_c) - 1):
        for j in range(len(z_c) - 1):
            in_liner = i >= n_wire
            if in_liner and not homogeneous and 0.5 * (z_c[j] + z_c[j + 1]) > 0:
                continue
            nodes = [(2 * i + a, 2 * j + b) for b in range(3) for a in range(3)]          # r fastest
            if in_liner and interface == "slip" and not homogeneous:
                nodes = [(x, y, "L") if x == a_R else (x, y) for x, y in nodes]
            elems.append(nodes)
            mats.append(1 if (in_liner and not homogeneous) else 0)
    used = sorted({nd for e in elems for nd in e}, key=lambda nd: (nd[0], nd[1], len(nd)))
    idx = {nd: k for k, nd in enumerate(used)}
    coords = np.array([(r_n[nd[0]], z_n[nd[1]]) for nd in used])
    conn = np.array([[idx[nd] for nd in e] for e in elems])
    ties = [(idx[nd], idx[(nd[0], nd[1])]) for nd in used if len(nd) == 3]
    return coords, conn, np.array(mats), ties


GP = np.array([-math.sqrt(0.6), 0.0, math.sqrt(0.6)])
GW = np.array([5 / 9, 8 / 9, 5 / 9])


def _shape1d(x):
    return np.array([0.5 * x * (x - 1), 1 - x * x, 0.5 * x * (x + 1)]), np.array([x - 0.5, -2 * x, x + 0.5])


_SHAPES = []
for _a in GP:
    for _b in GP:
        _nx, _dx = _shape1d(_a)
        _ny, _dy = _shape1d(_b)
        _SHAPES.append((np.array([_nx[i] * _ny[j] for j in range(3) for i in range(3)]),
                        np.array([[_dx[i] * _ny[j] for j in range(3) for i in range(3)],
                                  [_nx[i] * _dy[j] for j in range(3) for i in range(3)]])))
_WEIGHTS = [wa * wb for wa in GW for wb in GW]


def dmat(E, nu):
    lm, mu = E * nu / ((1 + nu) * (1 - 2 * nu)), E / (2 * (1 + nu))
    D = np.zeros((6, 6))
    D[:3, :3] = lm
    D[np.arange(3), np.arange(3)] = lm + 2 * mu
    D[3, 3] = D[4, 4] = D[5, 5] = mu
    return D


def bmat(N, dNr, dNz, r, n):
    """Strain order (rr, θθ, zz, rz, rθ, θz); DOFs per node (U, V, W)."""
    B = np.zeros((6, 27))
    c = np.arange(9) * 3
    B[0, c] = dNr
    B[1, c], B[1, c + 1] = N / r, n * N / r
    B[2, c + 2] = dNz
    B[3, c], B[3, c + 2] = dNz, dNr
    B[4, c], B[4, c + 1] = -n * N / r, dNr - N / r
    B[5, c + 1], B[5, c + 2] = dNz, -n * N / r
    return B


def _gauss(xy):
    out = []
    for (N, dN), w in zip(_SHAPES, _WEIGHTS, strict=True):
        J = dN @ xy
        dNx = np.linalg.solve(J, dN)
        out.append((N, dNx[0], dNx[1], N @ xy[:, 0], N @ xy[:, 1], w * np.linalg.det(J), J[0, 0]))
    return out


class Mesh:
    def __init__(self, h_min_mm, growth, interface, homogeneous=False):
        self.coords, self.conn, self.mats, self.ties = build_mesh(h_min_mm, growth, interface, homogeneous)
        self.gauss = [_gauss(self.coords[e]) for e in self.conn]


def solve(mesh, n, props, eig=None, beta=0.0, f_extra=None):
    """One Fourier mode. `props` [(E, ν) Ti, (E, ν) PEEK]; `eig` the eigenstrain (6) per material (n = 0); `beta` the end
    rotation (n = 1); `f_extra` nodal forces (n = 0). Returns per Gauss point: r, z, material, σ_rr, σ_θθ, σ_zz, σ_rz (at
    θ = 0), element, ξ-index, η-index, ∂r/∂ξ."""
    coords, conn, mats = mesh.coords, mesh.conn, mesh.mats
    nn = len(coords)
    ndof = 3 * nn
    factor = math.pi if n >= 1 else 2 * math.pi
    Ds = [dmat(*props[0]), dmat(*props[1])]
    eig = eig if eig is not None else [np.zeros(6), np.zeros(6)]
    rows, cols, vals = [], [], []
    f = np.zeros(ndof) if f_extra is None else f_extra.copy()
    for e, m, gps in zip(conn, mats, mesh.gauss, strict=True):
        ke = np.zeros((27, 27))
        fe = np.zeros(27)
        for N, dNr, dNz, r, _, w, _ in gps:
            B = bmat(N, dNr, dNz, r, n)
            wr = w * r * factor
            ke += B.T @ Ds[m] @ B * wr
            if n == 0:
                fe += B.T @ (Ds[m] @ eig[m]) * wr
        dofs = 3 * np.repeat(e, 3) + np.tile([0, 1, 2], 9)
        rows.append(np.repeat(dofs, 27))
        cols.append(np.tile(dofs, 27))
        vals.append(ke.ravel())
        f[dofs] += fe
    K = sp.csr_matrix((np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(ndof, ndof))
    r_, z_ = coords[:, 0], coords[:, 1]
    fixed, tie = {}, {}
    on_axis = np.where(r_ < 1e-12)[0]
    if n >= 1:
        for k in on_axis:
            tie[3 * k + 1] = (3 * k, -1.0)                 # V = −U on the axis
            fixed[3 * k + 2] = 0.0                         # W = 0 on the axis
        fixed[3 * on_axis[np.argmin(np.abs(z_[on_axis]))]] = 0.0
    else:
        for k in range(nn):
            fixed[3 * k + 1] = 0.0                         # no torsion in mode 0
        for k in on_axis:
            fixed[3 * k] = 0.0
    for dup, wire in mesh.ties:                            # SLIP: radial displacement continuous, tangential free
        tie[3 * dup] = (3 * wire, 1.0)
    for k in np.where(np.abs(z_ - z_.min()) < 1e-12)[0]:
        fixed[3 * k + 2] = 0.0                             # the symmetry plane z = −L
    if n >= 1:
        for k in np.where(np.abs(z_ - z_.max()) < 1e-12)[0]:
            fixed[3 * k + 2] = beta * r_[k]                # a plane rotation at z = +L
    for d in list(tie):
        fixed.pop(d, None)
    free = [d for d in range(ndof) if d not in fixed and d not in tie]
    col = {d: i for i, d in enumerate(free)}
    Ti_, Tj_, Tv_ = list(free), [col[d] for d in free], [1.0] * len(free)
    g = np.zeros(ndof)
    for d, v in fixed.items():
        g[d] = v
    for d, (src, c) in tie.items():
        if src in col:
            Ti_.append(d)
            Tj_.append(col[src])
            Tv_.append(c)
        else:
            g[d] = c * g[src]
    T = sp.csr_matrix((Tv_, (Ti_, Tj_)), shape=(ndof, len(free)))
    Kr = (T.T @ K @ T).tocsc()
    fr = T.T @ (f - K @ g)
    ur = spla.spsolve(Kr, fr)
    u = T @ ur + g
    res = np.linalg.norm(Kr @ ur - fr) / max(np.linalg.norm(fr), 1e-300)
    assert res < 1e-8, f"linear solve residual {res}"
    out = []
    for ei, (e, m, gps) in enumerate(zip(conn, mats, mesh.gauss, strict=True)):
        ue = u[3 * np.repeat(e, 3) + np.tile([0, 1, 2], 9)]
        for gi, (N, dNr, dNz, r, z, _, drdxi) in enumerate(gps):
            s = Ds[m] @ (bmat(N, dNr, dNz, r, n) @ ue - (eig[m] if n == 0 else 0.0))
            out.append((r, z, m, s[0], s[1], s[2], s[3], ei, gi // 3, gi % 3, drdxi))
    return np.array(out)


def interface_traction(mesh, ell_mm, tau_of_z):
    """Consistent nodal forces (n = 0, full circumference) of an interfacial shear τ(z) over EXACTLY z ∈ [−ℓ, 0] of the
    slip interface (the element straddling −ℓ integrated over its covered part only): toward −z on the Ti, +z on the
    tube. `tau_of_z` is a number or a vectorised function of z. Returns (f, covered length)."""
    tau = tau_of_z if callable(tau_of_z) else (lambda z, c=float(tau_of_z): np.full_like(np.asarray(z, dtype=float), c))
    tie = dict(mesh.ties)
    f = np.zeros(3 * len(mesh.coords))
    covered = 0.0
    for e, m in zip(mesh.conn, mesh.mats, strict=True):
        edge = [e[0], e[3], e[6]]                          # local a = 0 (the r = R side), b = 0, 1, 2 along z
        if m != 1 or edge[0] not in tie:
            continue
        z = mesh.coords[edge, 1]
        lo, hi = max(z[0], -ell_mm), min(z[2], 0.0)
        if hi <= lo:
            continue
        covered += hi - lo
        mid, half = 0.5 * (lo + hi), 0.5 * (hi - lo)
        for x, w in zip(GP, GW, strict=True):
            zq = mid + half * x
            eta = (2 * zq - (z[0] + z[2])) / (z[2] - z[0])  # the edge is straight, its mid node at the middle
            N, _ = _shape1d(eta)
            tq = float(tau(zq))
            for b in range(3):
                fb = N[b] * tq * 2 * math.pi * R_WIRE_MM * half * w
                f[3 * tie[edge[b]] + 2] -= fb
                f[3 * edge[b] + 2] += fb
    return f, covered


def interface_profile(S):
    """The Ti side of the slip interface (z < 0, the outermost Gauss column): z (mm, descending from the end) and the
    contact pressure −σ_rr there."""
    sel = (S[:, 2] == 0) & (S[:, 1] < 0) & (S[:, 0] > R_WIRE_MM - 0.2 * H_MIN_UM * 1e-3)
    z, p = S[sel, 1], -S[sel, 3]
    o = np.argsort(z)[::-1]
    return z[o], p[o]


def coulomb_slip(mesh, props, base, mu, force, max_iter=60, tol=1e-3):
    """The full-slip end zone of a Coulomb grip carrying `force` (N) into the tube: τ(z) = µ·max(p(z), 0) with p the
    contact pressure of the TOTAL field (base + the friction field itself), over the zone [−ℓ, 0] whose integral of
    2πR·τ equals the force (ℓ capped at FRICTION_ZONE_CAP_MM — then the transfer is incomplete and flagged). Fixed point,
    damped ½; refuses on non-convergence (in-silico §When Modifying #9). Returns (friction field, ℓ, iterations,
    transferred force, capped)."""
    z, p = interface_profile(base)
    tau = mu * np.maximum(p, 0.0)
    Sf, ell = None, 0.0
    for it in range(1, max_iter + 1):
        zi, ti = z[::-1], tau[::-1]                        # ascending z for interpolation
        def tau_fn(zq, zi=zi, ti=ti):
            return np.interp(zq, zi, ti)
        # the zone length: ∫_{−ℓ}^{0} 2πR·τ dz = force, on the interface points' own z
        cum = np.concatenate([[0.0], np.cumsum(2 * math.pi * R_WIRE_MM * 0.5 * (tau[1:] + tau[:-1]) * -np.diff(z))])
        ell = float(np.interp(force, cum, -z)) if force < cum[-1] else float(-z[-1])
        ell = min(ell, FRICTION_ZONE_CAP_MM)
        f_ext, _ = interface_traction(mesh, ell, tau_fn)
        Sf = solve(mesh, 0, props, None, f_extra=f_ext)
        _, p_new = interface_profile(superpose((1.0, base), (1.0, Sf)))
        tau_new = mu * np.maximum(p_new, 0.0)
        change = float(np.max(np.abs(tau_new - tau)) / max(np.max(tau_new), 1e-300))
        tau = 0.5 * tau + 0.5 * tau_new
        iters = it
        if change < tol:
            break
    else:
        raise RuntimeError(f"Coulomb slip zone did not converge in {max_iter} iterations (change {change:.2e})")
    tie = dict(mesh.ties)
    transferred = float(sum(f_ext[3 * dup + 2] for dup in tie))       # the z-forces applied on the tube
    capped = ell >= FRICTION_ZONE_CAP_MM
    assert capped or abs(transferred / force - 1) < 1e-2, f"Coulomb zone transfers {transferred} N of {force} N"
    return Sf, ell, iters, transferred, capped

def principal(S):
    rr, tt, zz, rz = S[:, 3], S[:, 4], S[:, 5], S[:, 6]
    c, h = 0.5 * (rr + zz), np.sqrt((0.5 * (rr - zz)) ** 2 + rz ** 2)
    return np.maximum(c + h, tt), np.minimum(c - h, tt)


def superpose(*terms):
    """Σ cᵢ·Sᵢ on the stress columns of fields with coinciding Gauss points (control 8)."""
    out = terms[0][1].copy()
    out[:, 3:7] = sum(c * S[:, 3:7] for c, S in terms)
    return out


def section_moment(S, z0):
    """M = π ∫ σ_zz r² dr (n = 1) by each element's own 3-point Gauss rule in r on its η = 0 row nearest z0."""
    mid = S[S[:, 9] == 1]
    zs = np.unique(np.round(mid[:, 1], 9))
    zr = zs[np.argmin(np.abs(zs - z0))]
    row = mid[np.abs(mid[:, 1] - zr) < 1e-9]
    return math.pi * float(np.sum(GW[row[:, 8].astype(int)] * row[:, 5] * row[:, 0] ** 2 * row[:, 10]))


def section_force(S, z0, mat):
    """N = 2π ∫ σ_zz r dr (n = 0) over one material, by each element's Gauss rule in r on its η = 0 row nearest z0."""
    mid = S[(S[:, 9] == 1) & (S[:, 2] == mat)]
    zs = np.unique(np.round(mid[:, 1], 9))
    zr = zs[np.argmin(np.abs(zs - z0))]
    row = mid[np.abs(mid[:, 1] - zr) < 1e-9]
    return 2 * math.pi * float(np.sum(GW[row[:, 8].astype(int)] * row[:, 5] * row[:, 0] * row[:, 10]))


def nearest(S, r0, z0, mat=None):
    sel = S if mat is None else S[S[:, 2] == mat]
    return sel[np.argmin((sel[:, 0] - r0) ** 2 + (sel[:, 1] - z0) ** 2)]


def ring(S, d_um):
    """The Ti Gauss points at d (±10 %) from the corner."""
    d = np.hypot(S[:, 0] - R_WIRE_MM, S[:, 1]) * 1e3
    return (S[:, 2] == 0) & (np.abs(d - d_um) <= 0.1 * d_um)


def profile(S, scale=1.0):
    s1, s3 = principal(S)
    out = {}
    for dr in D_REPORT_UM:
        m = ring(S, dr)
        out[f"{dr:g}"] = {"sigma1": float(s1[m].max() / scale), "sigma3": float(s3[m].min() / scale), "n_points": int(m.sum())}
    return out


def magnitude(v):
    return max(v["sigma1"], -v["sigma3"])


def far_pressure(S):
    return -float(nearest(S, R_WIRE_MM, -L_HALF_MM / 2, mat=0)[3])


def far_sigma_zz(S, mat):
    r = R_WIRE_MM if mat == 0 else R_WIRE_MM + 0.5 * T_LINER_MM
    return float(nearest(S, r, -L_HALF_MM / 2, mat=mat)[5])


def order_on_free_surface(S, lam1, lam_hom, h_min_mm):
    """σ_zz along the Ti free surface (bare side, θ = 0 of the corner) fitted by B + A·d^s + C·d over ORDER_BAND."""
    ti = S[(S[:, 2] == 0) & (S[:, 1] > 0) & (S[:, 0] > R_WIRE_MM - 0.2 * h_min_mm)]
    d = ti[:, 1] * 1e3
    m = (d >= ORDER_BAND_UM[0]) & (d <= ORDER_BAND_UM[1])
    xs, ys = d[m], ti[m, 5]

    def sse(s):
        X = np.column_stack([np.ones_like(xs), xs ** s, xs])
        coef, *_ = np.linalg.lstsq(X, ys, rcond=None)
        return float(np.sum((X @ coef - ys) ** 2))
    grid = np.arange(-0.70, -0.005, 0.0025)
    errs = [sse(s) for s in grid]
    return {"s_best": float(grid[int(np.argmin(errs))]), "s_bonded_williams": lam1 - 1, "s_homogeneous_270": lam_hom - 1,
            "sse_at_bonded": sse(lam1 - 1), "sse_at_homogeneous": sse(lam_hom - 1), "points": int(m.sum())}


# ── closed forms for the far-field controls ──────────────────────────────────────────────────────────────────────────
def two_cylinder_bonded(eps_w, eps_l_inplane, eps_l_axial):
    """Two bonded concentric cylinders (wire 0…a, layer a…b), free axial strain, generalised plane strain; the wire's
    eigenstrain isotropic eps_w, the layer's eps_l_inplane (rr, θθ) and eps_l_axial (zz): the wire's σ_zz, the layer's
    σ_zz and the interface pressure."""
    a, b = R_WIRE_MM, R_WIRE_MM + T_LINER_MM

    def wire(p, e0):
        szz = E_TI * (e0 - eps_w) + NU_TI * (-2 * p)
        return szz, a * ((-p - NU_TI * (-p + szz)) / E_TI + eps_w)

    def layer(p, e0):
        stt, srr = p * (b * b + a * a) / (b * b - a * a), -p
        szz = E_PK * (e0 - eps_l_axial) + NU_PK * (srr + stt)      # ε_zz − ε*_zz = (σ_zz − ν(σ_rr + σ_θθ))/E
        ett = (stt - NU_PK * (srr + szz)) / E_PK + eps_l_inplane
        return szz, a * ett

    def res(x):
        (szw, uw), (szl, ul) = wire(*x), layer(*x)
        return np.array([uw - ul, szw * a * a + szl * (b * b - a * a)])
    r0 = res([0.0, 0.0])
    J = np.column_stack([res(v) - r0 for v in ([1.0, 0.0], [0.0, 1.0])])
    p, e0 = np.linalg.solve(J, -r0)
    return {"wire_sigma_zz_MPa": float(wire(p, e0)[0]), "layer_sigma_zz_MPa": float(layer(p, e0)[0]),
            "interface_pressure_MPa": float(p)}


def slip_shrink_pressure(radial_misfit_mm, e_layer):
    """Two-cylinder Lamé shrink fit, σ_z = 0 in both (a slip fit), elastic wire: p from u_layer(a) − u_wire(a) = misfit."""
    a, b = R_WIRE_MM, R_WIRE_MM + T_LINER_MM
    return radial_misfit_mm / (a / e_layer * ((b * b + a * a) / (b * b - a * a) + NU_PK) + a * (1 - NU_TI) / E_TI)


# ── the end's SF on 97's line ─────────────────────────────────────────────────────────────────────────────────────────
def governing_rows(d97, base):
    rows = [r for r in d97["rows"] if r["base"] == base and r["offset_um"] <= TOL_OFFSET_UM]
    assert rows, f"no {base} row of 97 inside the tolerance"
    return rows


def corner_ratio(d97, base, K, mean_s1, k):
    """The lowest (end SF / governing SF) over 97's rows of `base` inside ⌀0.10 at seam knock-down k: the end's amplitude
    K·σ_a,bare and its mean K·σ_m,bare + mean_s1 (Soderberg, drawn wire, derate 1)."""
    inp = d97["inputs"]
    s_e, s_y = inp["endurance_drawn_wire_MPa"], inp["yield_Ti_MPa"]
    best = None
    for r in governing_rows(d97, base):
        gov = min([r["root"]["sf_at_k"][k]] + [f["sf_drawn_wire"] for st in ("mouth", "exit") for f in r[st]["faces"].values()])
        sf_c = min(1.0 / (K * v["amplitude_MPa"] / s_e + max(K * v["mean_MPa"] + mean_s1, 0.0) / s_y)
                   for v in r["liner_end"].values() if isinstance(v, dict))
        if best is None or sf_c / gov < best[0]:
            best = (sf_c / gov, r["offset_um"], sf_c, gov)
    return best


def main() -> int:
    banner("127 — the bus wire at the end of its PEEK liner: the end against the modelled sections")
    t0 = time.time()
    d97 = json.loads(SRC_97.read_text())
    bonded97 = d97["summary"]["by_base"]["bonded"]
    targets = {k: v["factor"] for k, v in bonded97["liner_end_corner_factor_to_out_rank_within_tolerance"].items()}
    ks = list(governing_rows(d97, "bonded")[0]["root"]["sf_at_k"])
    refused = {b: [r["offset_um"] for r in governing_rows(d97, b) if r["not_solved"]] for b in ("bonded", "frictionless")}

    will = williams_controls()
    lam1 = min(will["bimaterial_real_roots_below_1_6"])
    lam_hom = will["homogeneous_270_roots"][0]
    assert lam1 < 1.0, "no singular real root"

    beta = 1e-4
    props = {"short_term": [(E_TI, NU_TI), (E_PK, NU_PK)], "retained": [(E_TI, NU_TI), (E_PK * PEEK_RELAX_FLOOR, NU_PK)]}
    z6 = np.zeros(6)
    e_int = -INTERFERENCE_DIAM_MM / (2 * R_WIRE_MM)
    eig_inplane = [z6, np.array([e_int, e_int, 0, 0, 0, 0])]
    eig_axial = [z6, np.array([0, 0, 1.0, 0, 0, 0])]
    eig_thermal = [np.array([ALPHA_TI] * 3 + [0.0] * 3), np.array([ALPHA_PK] * 3 + [0.0] * 3)]

    # control 4 — the homogeneous bending case
    Sh = solve(Mesh(4 * H_MIN_UM * 1e-3, GROWTH, "bonded", homogeneous=True), 1, [(E_TI, NU_TI), (E_TI, NU_TI)], None, beta)
    R_out = R_WIRE_MM + T_LINER_MM
    ph = nearest(Sh, R_out, L_HALF_MM / 2)
    want = section_moment(Sh, L_HALF_MM / 2) * ph[0] / (math.pi * R_out ** 4 / 4)
    assert abs(ph[5] / want - 1) < 5e-3, f"homogeneous bending: σ_zz {ph[5]} against M·r/I {want}"
    controls = {"homogeneous_bending": {"sigma_zz_MPa": float(ph[5]), "M_r_over_I_MPa": want},
                "pressure_55_rigid_wire_MPa": float(S55.fit_state(INTERFERENCE_DIAM_MM / 2 * 1e-3)["P_c"] / 1e6),
                "refused_97_rows_used": refused}

    meshes = {(itf, g): Mesh(H_MIN_UM * 1e-3, g, itf) for itf in ("bonded", "slip") for g in (GROWTH, GROWTH_REFINED)}
    for g in (GROWTH, GROWTH_REFINED):                     # control 8 — the two interface meshes' Gauss points coincide
        gb = np.array([(p[3], p[4]) for gps in meshes[("bonded", g)].gauss for p in gps])
        gs = np.array([(p[3], p[4]) for gps in meshes[("slip", g)].gauss for p in gps])
        assert gb.shape == gs.shape and np.allclose(gb, gs, atol=1e-12), "the bonded and slip meshes' Gauss points differ"

    F = {}
    for g in (GROWTH, GROWTH_REFINED):
        mb, ms = meshes[("bonded", g)], meshes[("slip", g)]
        F[("A_bonded", g)] = solve(mb, 1, props["short_term"], None, beta)
        F[("A_slip", g)] = solve(ms, 1, props["short_term"], None, beta)
        mods = ("short_term", "retained") if g == GROWTH else ("short_term",)
        for mod in mods:
            F[("C_slip", mod, g)] = solve(ms, 0, props[mod], eig_inplane)
            F[("B_slip", mod, g)] = solve(ms, 0, props[mod], eig_thermal)
            F[("axial_unit", mod, g)] = solve(mb, 0, props[mod], eig_axial)
        if g == GROWTH:
            F[("B_bonded", "short_term", g)] = solve(mb, 0, props["short_term"], eig_thermal)

    # far-field controls
    recs = {}
    for itf in ("bonded", "slip"):
        A = F[(f"A_{itf}", GROWTH)]
        s_bare = float(nearest(A, R_WIRE_MM, L_HALF_MM / 2, mat=0)[5])
        bb = s_bare / (section_moment(A, L_HALF_MM / 2) * R_WIRE_MM / (math.pi * R_WIRE_MM ** 4 / 4))
        assert abs(bb - 1) < 1e-2, f"{itf}: bare far field against M·R/I {bb}"
        recs[itf] = {"sigma_bare_MPa": s_bare, "bare_far_field_over_beam": bb,
                     "wire_under_layer_over_bare": float(nearest(A, R_WIRE_MM, -L_HALF_MM / 2, mat=0)[5]) / s_bare,
                     "K": profile(A, s_bare)}
    I_w = math.pi * R_WIRE_MM ** 4 / 4
    I_l = math.pi * ((R_WIRE_MM + T_LINER_MM) ** 4 - R_WIRE_MM ** 4) / 4
    ei = E_TI * I_w / (E_TI * I_w + E_PK * I_l)
    assert abs(recs["bonded"]["wire_under_layer_over_bare"] / ei - 1) < 1e-2, "bonded composite far field against beam theory"
    cf_t = two_cylinder_bonded(ALPHA_TI, ALPHA_PK, ALPHA_PK)
    th = far_sigma_zz(F[("B_bonded", "short_term", GROWTH)], 0)
    assert abs(th / cf_t["wire_sigma_zz_MPa"] - 1) < 2e-2, f"bonded thermal far field {th} against {cf_t}"
    cf_a = two_cylinder_bonded(0.0, 0.0, 1.0)
    ax = far_sigma_zz(F[("axial_unit", "short_term", GROWTH)], 0)
    assert abs(ax / cf_a["wire_sigma_zz_MPa"] - 1) < 2e-2, f"unit axial-lock far field {ax} against {cf_a}"
    p_lame = slip_shrink_pressure(INTERFERENCE_DIAM_MM / 2, E_PK)
    p_slip = far_pressure(F[("C_slip", "short_term", GROWTH)])
    assert abs(p_slip / p_lame - 1) < 1.5e-2, f"slip pressure {p_slip} against Lamé {p_lame}"
    order = order_on_free_surface(F[("A_bonded", GROWTH)], lam1, lam_hom, H_MIN_UM * 1e-3)
    assert abs(order["s_best"] - order["s_bonded_williams"]) <= ORDER_TOL, f"corner order {order}"
    assert order["sse_at_bonded"] * 2 <= order["sse_at_homogeneous"], f"the order fit cannot tell the roots apart {order}"
    controls.update({"composite_ei_ratio": ei, "bonded_thermal_closed_form": cf_t, "bonded_thermal_fe_MPa_per_K": th,
                     "axial_unit_closed_form": cf_a, "axial_unit_fe_MPa": ax, "lame_slip_pressure_MPa": p_lame,
                     "slip_pressure_fe_MPa": p_slip, "corner_order": order})

    # the friction cap — control 8 (equilibrium) on a 1 mm zone, and the field for control 7
    fr_ctrl = {}
    for g in (GROWTH, GROWTH_REFINED):
        f_ext, cov = interface_traction(meshes[("slip", g)], 1.0, 1.0)      # a constant 1 MPa over 1 mm
        S = solve(meshes[("slip", g)], 0, props["short_term"], None, f_extra=f_ext)
        F[("friction_1mm", g)] = S
        tube = section_force(S, -L_HALF_MM / 2, 1)
        want_n = 2 * math.pi * R_WIRE_MM * cov
        assert abs(tube / want_n - 1) < 1e-2, f"friction cap: tube force {tube} against τ·2πR·ℓ {want_n}"
        fr_ctrl[f"{g}"] = {"tube_force_N": tube, "tau_2piR_l_N": want_n, "covered_mm": cov}
    controls["friction_equilibrium"] = fr_ctrl

    # control 7 — the refined mesh
    dev = {}
    for itf in ("bonded", "slip"):
        Ar = F[(f"A_{itf}", GROWTH_REFINED)]
        kr = profile(Ar, float(nearest(Ar, R_WIRE_MM, L_HALF_MM / 2, mat=0)[5]))
        dev[f"K_{itf}"] = max(abs(recs[itf]["K"][d]["sigma1"] / kr[d]["sigma1"] - 1) for d in kr)
    for key in (("C_slip", "short_term"), ("B_slip", "short_term"), ("axial_unit", "short_term")):
        pf, pr = profile(F[(*key, GROWTH)]), profile(F[(*key, GROWTH_REFINED)])
        dev["_".join(key)] = max(abs(magnitude(pf[d]) / magnitude(pr[d]) - 1) for d in pf)
    pf, pr = profile(F[("friction_1mm", GROWTH)]), profile(F[("friction_1mm", GROWTH_REFINED)])
    dev["friction_1mm_sigma1"] = max(abs(pf[d]["sigma1"] / pr[d]["sigma1"] - 1) for d in pf)
    dev["_not_asserted_friction_1mm_sigma3"] = max(abs(pf[d]["sigma3"] / pr[d]["sigma3"] - 1) for d in pf)
    assert dev["K_bonded"] < 0.02 and dev["K_slip"] < 0.02, f"the refined mesh moves K: {dev}"
    assert all(v < 0.03 for k_, v in dev.items() if not k_.startswith(("K_", "_"))), f"the refined mesh moves a mean field: {dev}"
    controls["refined_mesh_worst_relative"] = dev

    # control 8 — the Coulomb field on the refined mesh (µ 0.4, T_g, forest min, short-term)
    T_c = T_SERVICE["forest_min"]
    e_c = D_ALPHA * (T_c - T_LOCKS["lock_at_Tg"])
    coul = {}
    for g in (GROWTH, GROWTH_REFINED):
        base_g = superpose((1.0, F[("C_slip", "short_term", g)]), (T_c - T_ASSEMBLY_C, F[("B_slip", "short_term", g)]))
        force_g = abs(e_c) * abs(section_force(F[("axial_unit", "short_term", g)], -L_HALF_MM / 2, 1))
        Sf_g, ell_g, *_ = coulomb_slip(meshes[("slip", g)], props["short_term"], base_g, MU_ENDS[1], force_g)
        coul[g] = (profile(superpose((1.0, base_g), (1.0, Sf_g))), ell_g)
    adm = [d for d in coul[GROWTH][0] if 10.0 <= float(d) <= 100.0]
    far = [d for d in coul[GROWTH][0] if float(d) > 100.0]
    dev["coulomb_mu0.4_Tg_forest_min_sigma1"] = max(abs(coul[GROWTH][0][d]["sigma1"] / coul[GROWTH_REFINED][0][d]["sigma1"] - 1) for d in adm)
    dev["_not_asserted_coulomb_beyond_100um_sigma1"] = max(abs(coul[GROWTH][0][d]["sigma1"] / coul[GROWTH_REFINED][0][d]["sigma1"] - 1) for d in far)
    assert dev["coulomb_mu0.4_Tg_forest_min_sigma1"] < 0.03, f"the refined mesh moves the Coulomb field: {dev}"

    # the readings
    peak_bend = {b: max(v["amplitude_MPa"] + abs(v["mean_MPa"]) for r in governing_rows(d97, b)
                        for v in r["liner_end"].values() if isinstance(v, dict)) for b in ("bonded", "frictionless")}
    A_s = F[("A_slip", GROWTH)]
    iface = (A_s[:, 2] == 0) & (A_s[:, 1] < -CONTACT_CHECK_FROM_UM * 1e-3) & (A_s[:, 0] > R_WIRE_MM - 0.2 * H_MIN_UM * 1e-3)
    bend_srr = np.abs(peak_bend["frictionless"] / recs["slip"]["sigma_bare_MPa"] * A_s[iface, 3])

    def contact_closed(S_mean):
        return float((S_mean[iface, 3] + bend_srr).max())

    def contact_open_within_um(S_mean):
        """The largest distance from the end (µm) at which the interface would lift (mean + peak bending radial ≥ 0)."""
        lift = (S_mean[iface, 3] + bend_srr) >= 0
        return float(-A_s[iface, 1][lift].min() * 1e3) if lift.any() else 0.0

    def axial_lock_force(e_axial, mod):
        """The tube's axial force a full axial lock of misfit e_axial would hold (from the unit field's far section)."""
        return abs(e_axial) * abs(section_force(F[("axial_unit", mod, GROWTH)], -L_HALF_MM / 2, 1))

    readings, flips, meta = {}, {}, {}

    def record(name, base, Kp, mean_fields_by_t):
        readings[name] = {t: {k: {d: dict(zip(("ratio", "offset_um", "sf_end", "sf_governing"),
                                              corner_ratio(d97, base, Kp[d]["sigma1"], Pm[d]["sigma1"], k), strict=True))
                                  for d in Kp} for k in ks}
                          for t, Pm in ((t, profile(S)) for t, S in mean_fields_by_t.items())}

    for mod in ("short_term", "retained"):
        Cs, Bs, Ax = F[("C_slip", mod, GROWTH)], F[("B_slip", mod, GROWTH)], F[("axial_unit", mod, GROWTH)]
        p_far = {t: far_pressure(Cs) + (T - T_ASSEMBLY_C) * far_pressure(Bs) for t, T in T_SERVICE.items()}
        # DESIGN — slip
        slip_fields = {t: superpose((1.0, Cs), (T - T_ASSEMBLY_C, Bs)) for t, T in T_SERVICE.items()}
        for t, S in slip_fields.items():
            assert contact_closed(S) < 0, f"design slip {mod}: the contact opens at {t}"
        record(f"design:slip:{mod}", "frictionless", recs["slip"]["K"], slip_fields)
        # DESIGN — friction-capped
        for lock, T_lock in T_LOCKS.items():
            for mu in MU_ENDS:
                fields_t, m_t = {}, {}
                for t, T in T_SERVICE.items():
                    e_ax = D_ALPHA * (T - T_lock)
                    force = axial_lock_force(e_ax, mod)
                    if force > 0 and e_ax < 0:
                        Sf, ell, iters, moved, capped = coulomb_slip(meshes[("slip", GROWTH)], props[mod], slip_fields[t], mu, force)
                        fields_t[t] = superpose((1.0, slip_fields[t]), (1.0, Sf))
                    else:                                  # no misfit, or the tube would grow: no inward grip to price here
                        ell, iters, moved, capped = 0.0, 0, 0.0, False
                        fields_t[t] = slip_fields[t]
                    opens = contact_closed(fields_t[t])
                    lifts_um = contact_open_within_um(fields_t[t])
                    lo_um = 3 * lifts_um / 0.9 if lifts_um > 0 else 0.0
                    hi_um = (ell - 0.2) * 1e3 if ell > 0 else None
                    m_t[t] = {"axial_misfit": e_ax, "lock_force_N": force, "p_far_MPa": p_far[t], "zone_mm": ell, "iterations": iters,
                              "admissible_from_um": lo_um, "covered_to_um": hi_um,
                              "grip_priced": bool(force > 0 and e_ax < 0),
                              "transferred_N": moved, "zone_capped": capped, "max_interface_sigma_rr_MPa": opens,
                              "contact_closed_from_0p5um": opens < 0,
                              "contact_lifts_within_um": lifts_um}
                name = f"design:friction_mu{mu:g}:{lock}:{mod}"
                record(name, "frictionless", recs["slip"]["K"], fields_t)
                meta[name] = m_t
                for t in T_SERVICE:                       # the distances a reading may speak for
                    readings[name][t]["_admissible_um"] = [m_t[t]["admissible_from_um"], m_t[t]["covered_to_um"]]
                    readings[name][t]["_grip_priced"] = m_t[t]["grip_priced"]
        # ADHESIVE — bonded bending; the radial fit of a slip fit plus a bonded axial lock
        for lock, T_lock in T_LOCKS.items():
            for extra, e0 in (("", 0.0), ("stuck:", e_int)):
                def mean_at(dT, T_lock=T_lock, e0=e0, Cs=Cs, Bs=Bs, Ax=Ax):
                    T = T_ASSEMBLY_C + dT
                    return superpose((1.0, Cs), (dT, Bs), (e0 + D_ALPHA * (T - T_lock), Ax))
                name = f"adhesive:{extra}{lock}:{mod}"
                record(name, "bonded", recs["bonded"]["K"], {t: mean_at(T - T_ASSEMBLY_C) for t, T in T_SERVICE.items()})
                flips[name] = {}
                for d in readings[name]["assembly"][ks[0]]:
                    m = ring(Cs, float(d))
                    subs = [Cs[m], Bs[m], Ax[m]]
                    by_dT = []
                    for dT in DT_SCAN:
                        S = subs[0].copy()
                        S[:, 3:7] = subs[0][:, 3:7] + dT * subs[1][:, 3:7] + (e0 + D_ALPHA * (T_ASSEMBLY_C + dT - T_lock)) * subs[2][:, 3:7]
                        by_dT.append(float(principal(S)[0].max()))
                    for k in ks:
                        rs = [corner_ratio(d97, "bonded", recs["bonded"]["K"][d]["sigma1"], mv, k)[0] for mv in by_dT]
                        br = []
                        for i in range(1, len(rs)):
                            if (rs[i - 1] - 1) * (rs[i] - 1) < 0:
                                br.append({"between_K": [float(DT_SCAN[i - 1]), float(DT_SCAN[i])],
                                           "out_ranks_on": "colder" if rs[i - 1] < 1 else "warmer"})
                        flips[name].setdefault(k, {})[d] = br

    bend_only = {itf: {k: {d: corner_ratio(d97, "bonded" if itf == "bonded" else "frictionless", recs[itf]["K"][d]["sigma1"], 0.0, k)[0]
                           for d in recs[itf]["K"]} for k in ks} for itf in ("bonded", "slip")}

    def largest_out(rd, adm=None):
        lo, hi = adm if adm else (0.0, None)
        return max((float(d) for d, v in rd.items() if (v if isinstance(v, float) else v["ratio"]) < 1.0
                    and float(d) >= lo and (hi is None or float(d) <= hi)), default=None)

    def phrase(dmax):
        if dmax is None:
            return f"at no reported distance ({D_REPORT_UM[0]:g}–{D_REPORT_UM[-1]:g} µm)"
        if dmax >= max(D_REPORT_UM):
            return f"at every reported distance out to the largest ({dmax:g} µm), possibly beyond"
        nxt = min(d for d in D_REPORT_UM if d > dmax)
        return f"out to {dmax:g} µm and not at {nxt:g} µm"
    lines = [f"bending alone ({'bonded — adhesive only' if itf == 'bonded' else 'slip — design'}), k {k}: "
             + phrase(largest_out(bend_only[itf][k])) for itf in ("slip", "bonded") for k in sorted(ks, key=float)]
    for cls in ("design", "adhesive"):
        for name in [n for n in readings if n.startswith(cls)]:
            for k in sorted(ks, key=float):
                parts = [f"{t}: {phrase(largest_out(readings[name][t][k], readings[name][t].get('_admissible_um')))}"
                         + (f" [admissible {readings[name][t]['_admissible_um'][0]:.1f}–"
                            + (f"{readings[name][t]['_admissible_um'][1]:.0f}" if readings[name][t]['_admissible_um'][1] is not None else "∞") + " µm]"
                            if '_admissible_um' in readings[name][t] else "")
                         + (f" (the grip's edge would lift within {meta[name][t]['contact_lifts_within_um']:.1f} µm — no distance below that is admissible)"
                            if name in meta and meta[name][t]["contact_lifts_within_um"] > 0 else "")
                         for t in T_SERVICE]
                lines.append(f"{name}, k {k} — " + "; ".join(parts))
    verdict = ("The liner's end on the wire — linear, POINT stress, no notch sensitivity, the bending's and the mean's maxima "
               "added, the root's own seam mean not modelled (so every «out-ranks» is an upper estimate, every «at no reported "
               "distance» the robust statement): where the end's SF falls below the governing modelled section's on the "
               "matching base — " + " | ".join(lines) + ". Whether a zone of that size matters for fatigue (a critical "
               "distance, a grain size, the end's real shape) is not computed here.")

    result = {
        "script": Path(__file__).name,
        "question": "00_07 HW.34 — the bus wire at the end of its PEEK liner: the end against the modelled sections",
        "inputs": {"R_wire_mm": R_WIRE_MM, "t_liner_mm": T_LINER_MM, "interference_diam_um": INTERFERENCE_DIAM_MM * 1e3,
                   "E_Ti_MPa": E_TI, "nu_Ti": NU_TI, "alpha_Ti_1K": ALPHA_TI, "E_PEEK_MPa": E_PK, "nu_PEEK": NU_PK,
                   "alpha_PEEK_1K": ALPHA_PK, "retained_fraction": PEEK_RELAX_FLOOR, "alloy": ALLOY_BASELINE,
                   "T_service_C": T_SERVICE, "T_lock_C": T_LOCKS, "mu_ends": list(MU_ENDS), "L_half_mm": L_HALF_MM,
                   "tolerance_offset_um": TOL_OFFSET_UM, "factors_from_97": targets,
                   "liner_ei_jump_97": bonded97["liner_ei_jump"], "bending_peak_at_end_MPa": peak_bend,
                   "source": "55 geometry, fit and µ sweep · 92 tolerance · 97 cache · lib constants"},
        "williams": {**will, "lambda_first": lam1, "singularity_order": lam1 - 1},
        "controls": controls, "bending_K": {itf: recs[itf]["K"] for itf in recs},
        "far_fields": {itf: {k_: v for k_, v in recs[itf].items() if k_ != "K"} for itf in recs},
        "mean_profiles_MPa": {f"{key[0]}:{key[1]}": profile(S) for key, S in F.items()
                              if len(key) == 3 and key[2] == GROWTH},
        "bending_alone_ratio": bend_only, "friction_zones": meta,
        "readings": readings, "flip_brackets_K_vs_assembly": flips, "verdict": verdict,
        "runtime_s": round(time.time() - t0, 1),
    }
    MECH.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(result, indent=1, ensure_ascii=False) + "\n")
    print(verdict)
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
