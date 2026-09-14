# SPDX-License-Identifier: AGPL-3.0-or-later
"""A clamped Euler-Bernoulli rod in a rigid channel — unilateral contact solved by an active set.

ONE HOME (2026-09-14, 00_07 HW.34). Script 68 shipped this solver to show that script 55's contact
station — read off the FREE tip-loaded shape at FULL drag — is not an equilibrium; 55's re-derived
blocks then needed the same solver, and 68 imports 55, so the solver lives here and both import it.
A second copy in either script would be the drift the in-silico rule forbids (a mirror of another
script's result, here of its MODEL).

MODEL. Cubic Hermite beam elements, clamped at x = 0 (weld and anode body rigid), rod length = the
channel exit (the pogo pad is the rod's own end face, 02_02 §1.2). A rigid, frictionless wall from
`Channel.mouth_mm` to `Channel.exit_mm` on both sides of a channel axis w_axis(x) = offset + tilt·(x − pivot),
walls at w_axis ± play on every channel node. Unilateral contact by an active set on PRESCRIBED
displacements: the active wall nodes are eliminated and the rest is solved on a symmetrically scaled SPD
matrix (a saddle-point formulation was ill-conditioned enough to cycle on some offsets), with the sign of
every reaction checked. Nodes are FORCED onto the mouth, the liner start and the exit — a uniform mesh
that misses the mouth leaves the wall's first station BETWEEN nodes, which the midpoint control caught on
the lock-window geometry (script 68, 2026-09-14).

CONTROLS built into every solve, with what each can and cannot catch:
  * the wall holds BETWEEN nodes (Hermite interpolant at element midpoints) — catches a contact the
    node set missed; it is the only in-solve check that can fail on a model defect;
  * the equilibrium residual closes — guards the LINEAR SOLVE only; it holds for any EI or station,
    so it is not a model check;
  * the active-set loop has an explicit non-convergence branch and a cycle detector — a solver that
    hands back a non-converged state as a number is worse than one that refuses.
  The controls with an INDEPENDENT formula (closed forms at the exit and at the mouth, two element
  sizes on a grazing row) live in the CALLERS, because they need the caller's geometry.

Tolerances follow the MEASURED solve precision, not taste: on the scaled SPD solve the clamp moment
carries a relative error of ~4e-7 on the 23 mm rod (cond ~1.5e10) and ~2e-6 on the 38-39 mm lock-window
rods (cond ~1.2e11); iterative refinement does not improve it (the residual K·u itself is the limit,
2026-09-14).

⛔ DECLARED CEILINGS: rigid, frictionless wall (no liner compliance, no contact pressure, no axial
traction); perfect clamp; small deflection; no thermal term; no P-δ from an axial force. These carry NO
blanket sign: where the wall PRESCRIBES a deflection (the coaxial drag once touched down), a compliant wall
raises the root moment by 3EI·(R/k)/L² — the rigid-wall figure is then the LOWER end — while a compliant
clamp lowers it. The sign depends on the loading, so every caller states it per derived figure (script
55's `*_bound` fields); this module cannot.
"""
from __future__ import annotations

import itertools
from collections.abc import Callable
from dataclasses import dataclass

import numpy as np

MM_M = 1e-3
ELEMENT_MM = 0.1                   # target element size; nodes are FORCED onto every station of the channel
CONTACT_TOLERANCE_MM = 1e-5        # 10 nm: above the displacement precision of the long rods, 3 orders below the play
RESIDUAL_TOLERANCE_REL = 1e-4      # 50x the worst measured relative moment error
MIDPOINT_TOLERANCE_MM = 1e-4       # 0.1 µm between nodes
FREE_PLAY_MM = 1e6                 # a play no deflection reaches — the "no wall" solve


@dataclass(frozen=True)
class Channel:
    """Axial extent of the rigid wall, mm from the clamp: the mouth (where the PEEK gap ends and the bore
    begins), the exit (= the rod's length: the pad plane), and where the composite member starts (the
    liner's lower end, which protrudes into the gap by the ratified ≥ 1.0 mm)."""
    mouth_mm: float
    exit_mm: float
    liner_from_mm: float


def mesh(channel: Channel, h_mm: float = ELEMENT_MM) -> np.ndarray:
    stations = sorted({0.0, max(0.0, channel.liner_from_mm), channel.mouth_mm, channel.exit_mm})
    parts = [np.linspace(a, b, max(1, int(np.ceil((b - a) / h_mm - 1e-9))) + 1)[:-1] for a, b in itertools.pairwise(stations)]
    return np.concatenate([*parts, np.array([channel.exit_mm])])


def assemble(xs: np.ndarray, ei_at: Callable[[float], float]) -> np.ndarray:
    """Global stiffness for nodes `xs` (mm); `ei_at(x_mm)` is the flexural rigidity (N·m²) at a station."""
    n_el = len(xs) - 1
    k_glob = np.zeros((2 * (n_el + 1), 2 * (n_el + 1)))
    for e in range(n_el):
        le = (xs[e + 1] - xs[e]) * MM_M
        ei = ei_at(0.5 * (xs[e] + xs[e + 1]))
        k_el = ei / le ** 3 * np.array([[12.0, 6.0 * le, -12.0, 6.0 * le],
                                        [6.0 * le, 4.0 * le ** 2, -6.0 * le, 2.0 * le ** 2],
                                        [-12.0, -6.0 * le, 12.0, -6.0 * le],
                                        [6.0 * le, 2.0 * le ** 2, -6.0 * le, 4.0 * le ** 2]])
        dofs = [2 * e, 2 * e + 1, 2 * e + 2, 2 * e + 3]
        k_glob[np.ix_(dofs, dofs)] += k_el
    return k_glob


def station_index(xs: np.ndarray, x_mm: float) -> int:
    """Node index of a station the mesh was forced onto; raises if it is not a node (never interpolate a contact)."""
    hits = np.flatnonzero(np.abs(xs - x_mm) <= 1e-9)
    if hits.size != 1:
        raise ValueError(f"station {x_mm} mm is not a mesh node")
    return int(hits[0])


def solve(channel: Channel, ei_at: Callable[[float], float], play_mm: float, drag_N: float = 0.0,
          pad_moment_Nm: float = 0.0, offset_mm: float = 0.0, tilt_rad: float = 0.0,
          tilt_pivot_mm: float = 0.0, h_mm: float = ELEMENT_MM) -> dict:
    """Contact equilibrium of the clamped rod. Tip drag and pad moment act at the exit.

    Returns the SIGNED clamp moment (N·m), the nodal vector `u` (m, rad) with its nodes `xs` (mm), the
    contact zones (adjacent active nodes merged; force = wall on rod, + toward +w; station and force
    rounded for the cache the way script 68 has written them since 2026-09-14), the bending moment at
    every node (N·m, EI·w'') and the station where |M| peaks."""
    xs = mesh(channel, h_mm)
    k_glob = assemble(xs, ei_at)
    n_el = len(xs) - 1
    ndof = k_glob.shape[0]
    f = np.zeros(ndof)
    f[2 * n_el] = drag_N
    f[2 * n_el + 1] = pad_moment_Nm
    chan = [i for i, x in enumerate(xs) if channel.mouth_mm - 1e-9 <= x <= channel.exit_mm + 1e-9]
    axis = {i: offset_mm + tilt_rad * (xs[i] - tilt_pivot_mm) for i in chan}
    free = np.arange(2, ndof)
    active: dict[int, int] = {}
    seen: set[frozenset] = set()
    for _ in range(40 * len(chan) + 100):
        state = frozenset(active.items())
        if state in seen:
            raise RuntimeError(f"active set cycles at {sorted(active)} — refusing to report a number")
        seen.add(state)
        u = np.zeros(ndof)
        presc = np.array([2 * n for n in active], dtype=int)
        for n, side in active.items():
            u[2 * n] = (axis[n] + side * play_mm) * MM_M
        rest = np.setdiff1d(free, presc)
        k_rr = k_glob[np.ix_(rest, rest)]
        rhs = f[rest] - (k_glob[np.ix_(rest, presc)] @ u[presc] if presc.size else 0.0)
        scale = 1.0 / np.sqrt(np.diag(k_rr))
        u[rest] = scale * np.linalg.solve(k_rr * scale[:, None] * scale[None, :], scale * rhs)
        wall = k_glob @ u - f
        tensile = [n for n, side in active.items() if (side > 0 and wall[2 * n] > 1e-9)
                   or (side < 0 and wall[2 * n] < -1e-9)]
        if tensile:
            for n in tensile:
                del active[n]
            continue
        violation, pick = CONTACT_TOLERANCE_MM, None
        for i in chan:
            if i in active:
                continue
            w_mm = u[2 * i] / MM_M
            over, under = w_mm - (axis[i] + play_mm), (axis[i] - play_mm) - w_mm
            if over > violation:
                violation, pick = over, (i, +1)
            if under > violation:
                violation, pick = under, (i, -1)
        if pick is None:
            break
        active[pick[0]] = pick[1]
    else:
        raise RuntimeError("active set did not converge")

    # CONTROL: the wall holds BETWEEN nodes too (Hermite interpolant at element midpoints)
    for e in range(n_el):
        xm = 0.5 * (xs[e] + xs[e + 1])
        if channel.mouth_mm < xm < channel.exit_mm:
            le = (xs[e + 1] - xs[e]) * MM_M
            wm = 0.5 * (u[2 * e] + u[2 * e + 2]) + le / 8.0 * (u[2 * e + 1] - u[2 * e + 3])
            ax = offset_mm + tilt_rad * (xm - tilt_pivot_mm)
            assert abs(wm / MM_M - ax) <= play_mm + MIDPOINT_TOLERANCE_MM, f"wall violated between nodes at {xm:.2f} mm"
    # guards the linear solve ONLY — holds for any EI or station, so it is not a model check
    m_clamp = float(wall[1])
    residual = m_clamp + drag_N * channel.exit_mm * MM_M + pad_moment_Nm \
        + sum(float(wall[2 * n]) * xs[n] * MM_M for n in active)
    assert abs(residual) <= RESIDUAL_TOLERANCE_REL * max(1e-6, abs(m_clamp)), "equilibrium residual does not close"

    zones: list[dict] = []
    for node in sorted(active):
        force = float(wall[2 * node])
        if zones and node == zones[-1]["_last"] + 1 and np.sign(force) == np.sign(zones[-1]["force_N"]):
            zones[-1]["_moment"] += force * xs[node]
            zones[-1]["force_N"] += force
            zones[-1]["_last"] = node
        else:
            zones.append({"force_N": force, "_moment": force * xs[node], "_last": node})
    for z in zones:
        z["station_mm"] = round(float(z["_moment"] / z["force_N"]), 2)
        z["force_N"] = round(float(z["force_N"]), 4)
        del z["_moment"], z["_last"]

    # Bending moment EI·w'' at every node from the Hermite shape functions. With no distributed load M is
    # LINEAR inside an element, so its extreme over the rod is at a node — the peak station is exact.
    moment = np.zeros(n_el + 1)
    for e in range(n_el):
        le = (xs[e + 1] - xs[e]) * MM_M
        w1, t1, w2, t2 = u[2 * e], u[2 * e + 1], u[2 * e + 2], u[2 * e + 3]
        ei = ei_at(0.5 * (xs[e] + xs[e + 1]))
        if e == 0:
            moment[0] = ei * (-6.0 * w1 - 4.0 * t1 * le + 6.0 * w2 - 2.0 * t2 * le) / le ** 2
        moment[e + 1] = ei * (6.0 * w1 + 2.0 * t1 * le - 6.0 * w2 + 4.0 * t2 * le) / le ** 2
    peak = int(np.argmax(np.abs(moment)))
    return {"clamp_moment_Nm": m_clamp, "u": u, "xs": xs, "contacts": zones,
            "moment_Nm_at_nodes": moment, "peak_moment_station_mm": float(xs[peak]),
            "peak_moment_Nm": float(moment[peak])}


def deflection_mm(res: dict, x_mm: float) -> float:
    return float(res["u"][2 * station_index(res["xs"], x_mm)]) / MM_M


def slope_rad(res: dict, x_mm: float) -> float:
    return float(res["u"][2 * station_index(res["xs"], x_mm) + 1])


def touchdown_drag_N(channel: Channel, ei_at: Callable[[float], float], play_mm: float,
                     h_mm: float = ELEMENT_MM) -> float:
    """The tip drag at which the FREE rod's deflection at the exit first equals the play — exact for a
    member whose EI varies along the rod (the composite starts at the liner), where 3·EI·g/L³ is not."""
    per_newton = deflection_mm(solve(channel, ei_at, FREE_PLAY_MM, drag_N=1.0, h_mm=h_mm), channel.exit_mm)
    return play_mm / per_newton
