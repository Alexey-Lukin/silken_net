#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 / HW.23 — the PEEK liner's contact at the channel MOUTH when the channel axis sits off the root axis: script
91's elastic layer with TWO patches — the mouth edge on one side and the exit on whichever side the drag sends the
rod — coupled through the bending of the bus rod.

WHY THIS EXISTS. Script 68 (b) found that past the radial play a static axis offset makes the mouth edge a contact
station and the root bending grow at a secant 0.64 MPa/µm against a RIGID wall, and warned that the mouth corner may
load the PEEK tube past its compressive strength at the larger offsets — so every offset stress there is an upper
bound on that account. Script 91 modelled the exit only and declares the mouth not computed. This script prices the
mouth: the edge pressure against the flow pressure, the root stress with the layer's give, and what a reversing
drag on top of an offset does to the cycle — the amplitude 68 found ABOVE its coaxial cap.

GEOMETRY. The liner (on the wire) starts LINER_PROTRUSION before the mouth (the ratified protrusion into the gap,
55), so the Ti entry edge presses into a layer that continues on both sides of it: a punch edge, singular when
sharp (91 §controls.sharp_edge_inside_the_layer: ×√2 per halving of the step) — hence the entry radius is SWEPT
(no number in any artifact; ⚖️ pending the tribo test, 01_01 §1.4) and never zero. The exit keeps 91's flush exit
with its reference rounding. The mouth station moves with the Zone-3 shank length (a placeholder paired with its Ø,
00_07 HW.8.9), and the rod length does not (55: pad = sleeve − insertion + flange), so the shank is swept.

MODEL. 91's kernels and rod unchanged: the PEEK layer on a rigid wire (bonded ⊥ frictionless base), Love's
half-space for the Ti channel, the exact Mohr flexibility of 55's piecewise EI. The channel axis is offset by e
toward +; the rod's displacement v is positive toward +. A wall on side σ (±1) leaves the gap
    h = c + recession − σ·(v − e)·cos φ
so the mouth's − wall closes once e exceeds the play, and the exit's wall on the side the drag sends the rod closes
under the drag. A window per station (mouth on −, exit on the side the rigid solution at the same edges approaches
first — the other exit side and the mouth's far wall are asserted open after the solve).

SOLVER — and why not 91's. 91 solves one window by Polonsky–Keer on the operator «layer + beam·cos φ ⊗ cos φ». Two
windows on that operator did not converge: the beam term carries a few eigenvalues orders of magnitude above the
layer's, the active-set restarts break the Krylov memory, and the iterate wandered or fell into p ≡ 0 (where 91's
`pk_solve` would report convergence — there it would still be caught by the complementarity assert, and never was).
A Newton on the windows' REACTIONS alone (each window solved under load control) converged where the patch was
short, but swung without end where the rod meets the wall almost parallel (0.4–0.7 mrad near the mouth and the
exit on a short shank): the patch's tilt was left to a fixed point, and a micro-radian of tilt there moves a long
patch. So the unknowns are the rod's POSE at each window — its displacement and slope at the rigid contact point —
and each window is solved for a given pose by Polonsky–Keer on the layer and the Ti alone (well conditioned).
The outer Newton matches the pose to the beam's response to the windows' line loads: its Jacobian is I minus the
exact Mohr flexibility at the window references times the windows' contact stiffness (finite differences of each
window's line load in its own pose — block-diagonal, since a window's contact sees only its own pose). The rod's
curvature inside a window comes from the same exact flexibility one iteration behind. A window the rod leaves
simply carries no load; at the end the whole channel between the windows, the exit side not modelled and the
mouth's far wall are asserted open.

WHAT IT READS, and with which model: the static mouth-edge peak (offset × entry radius); the edge peak over the
drag CYCLE (the path with its contact kinks, located on the working grid, refined where it peaks) on the shipped
shank and on the swept ones — the quantity a radius decision reads, framed by the ratified coaxiality ⌀0.10 (offsets
up to TOLERANCE_OFFSET_UM; beyond it the rows are the margin); the EXIT-edge peak over the cycle by exit radius,
coaxially (91's problem) and at the tolerance limit — under an offset the exit is the more loaded edge; the beam's swing (root, and the wire under each
edge) along the same path on the RIGID same-edge model, dense in offset (exact kinks; the elastic path costs minutes
a point near the play, where the patches grow long), with the give's correction measured on the elastic path where
it is cheap.

CONTROLS asserted in-run, with what each one can and cannot catch:
  * the rigid sharp-edge point model (the same LCP the rigid references use) reproduces 68's offset table and its
    reversing-drag table — catches a wrong side, sign, station or offset convention; blind to the layer;
  * the elastic solve with every contact compliance ×10⁻² approaches the rigid same-edge point model (≤ 0.2 %, against
    ~0.8–1.7 % at full compliance) under no drag and under the drag either way — the drag toward the wall loads BOTH
    windows, so this is the control on the two windows' coupling; blind to the kernels (91's, with 91's controls);
  * with no offset the two-window solve reproduces 91's exit-only cycle row, and the exit edge's cycle peak 91's edge
    peak at every exit radius — catches the exit window's side, sign and refinement (the mouth window carries nothing
    there, so it cannot see the coupling);
  * the edge peak at the smallest entry radius at two axial steps — catches an unresolved peak;
  * complementarity of every inner solve, the outer residual, the patch inside its window, the far walls open.

⛔ DECLARED CEILINGS — read these before quoting any number below:
  * LINEAR elasticity, no plasticity: a peak above the flow pressure is FLAGGED against 55's constraint-factor
    sweep (1·σ_y ⊥ 3·σ_y at 23 °C tensile yield), never redistributed — where it is flagged, the elastic peak is not
    what the PEEK carries, and the root figure next to it stands on a layer that has already yielded.
  * 91's ceilings hold unchanged: a FLAT uniform layer (the tube's curvature makes it ~14 % softer), bonded ⊥
    frictionless base and short-term ⊥ 20-year modulus as brackets, no thermal term, no P-δ.
  * NO friction at either patch (91's lumped friction bracket is not carried here), no pad couple (91 §pad_couple
    and 68 (d) price it coaxially), no wear.
  * Zero-interference play only; the interference rows of 68 (b) are not re-run.
  * The wire is RIGID in the contact kernel, so no stress concentration in the wire under either edge is computed:
    what is reported is the NOMINAL fibre stress of the wire at the two edge sections beside the root's. A notch
    factor there needs an elastic wire under the layer — or the S-N plan's acceptance on the real part.
  * The offset is SWEPT; which offset the stack delivers is computed nowhere in the tree (00_07 HW.34). The ratified
    ⌀0.10 BOUNDS it at 50 µm, so that limit frames every reading; the rows beyond it are a margin, not a ground.
  * The exit peak is read at the reference entry radius only, and the entry radius's effect on the beam's swing on
    the rigid same-edge model only.
  * No verdict is taken here (00_07 HW.34).

Run:  python tools/in_silico/scripts/92_liner_mouth_contact.py      # ≈ 2 h on 2 workers beside a DFT (≈ 12 min before the cycle block)
      python tools/in_silico/scripts/92_liner_mouth_contact.py --resummarise   # the summary again from the cached rows
"""
from __future__ import annotations

import importlib.util
import json
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, CACHE_DIR, SIGMA_YIELD_PEEK_PA
from lib.utils import banner

SI_DESCRIPTION = "Contact of the bus rod's PEEK liner with the Ti channel at its mouth under an offset of the channel axis, two patches coupled through the rod's bending."  # its row in the paper SI (72): English, no repo jargon

_spec = importlib.util.spec_from_file_location("liner91", HERE / "91_liner_exit_contact.py")
m91 = importlib.util.module_from_spec(_spec)
sys.modules["liner91"] = m91
_spec.loader.exec_module(m91)
s55 = m91.s55

OUT_JSON = CACHE_DIR / "mechanical" / "liner_mouth_contact.json"
BUS68_CACHE = CACHE_DIR / "mechanical" / "bus_contact_equilibrium.json"
BUS91_CACHE = CACHE_DIR / "mechanical" / "liner_exit_contact.json"
COAX86_CACHE = CACHE_DIR / "mechanical" / "coaxiality_allocation.json"

# ── sweeps — every one a sweep because the quantity has no number in any artifact ─────────────────────────────
R_IN_SWEEP_MM = m91.R_EDGE_SWEEP_MM               # entry radius: the same sweep 91 gives the exit radius
R_IN_REFERENCE_MM = m91.R_EDGE_REFERENCE_MM       # the row the reversing, bracket and shank blocks are taken at
R_EX_MM = m91.R_EDGE_REFERENCE_MM                 # the exit keeps 91's reference rounding throughout
SHANK_SWEEP_MM = (10.0, 14.0, 18.0)               # the Zone-3 shank placeholder ± 4 mm: no artifact bounds it
DRAG_PATH = (-1.0, -0.5, -0.2, -0.1, 0.0, 0.1, 0.2, 0.5, 1.0)   # × µ·F_pogo — the cycle is read along it, not at its ends,
PATH_SCAN = 801                                   # rigid scan for the contact transitions (the cycle's kinks), each bisected
TRANSITION_SIDE = 0.004                           # × µ·F: the elastic solve is taken at a transition and this far either side
RIGID_SWING_OFFSETS_UM = (0, 10, 26, 28, 30, 35, 40, 45, 50, 60, 75, 100)   # the beam's swing read on the rigid same-edge
#                                                   model (exact kinks), dense near the play where the mouth section's swing crosses the root's
ELASTIC_SWING_OFFSETS_UM = (0, 10, 50, 75, 100)   # where the elastic path is cheap — the give's correction to that swing
CYCLE_OFFSETS_UM = (50, 75, 100)                  # the elastic edge peak over the cycle (nearer the play the patches grow long
#                                                   and a point costs minutes; the static peaks there are in block (a))
CYCLE_SHANK_OFFSETS_UM = (50, 75, 100)            # the shank's effect on the cycle peak: at the ratified ⌀0.10 (≤ 50 µm) and beyond
TOLERANCE_OFFSET_UM = 50                          # ⌀0.10 ratified (01_01 §1.4 «Співвісність») — the largest offset it admits
EXIT_OFFSETS_UM = (0, 50)                         # the exit edge coaxially (91's, the control) and at the tolerance limit
SWING_RADIUS_OFFSETS_UM = (35, 50, 100)           # where the entry radius's effect on the beam's swing is read (rigid)
WORKERS = 2                                       # independent cycle rows and paths in parallel (2 BLAS threads each) — kept
#                                                   small: a CPU-bound DFT may share the machine (in-silico §Critical Rules #3)
WINDOW_ATTEMPTS = 3                               # a patch that outgrows 4× the first window is a line contact: refuse fast
CONTROL_SCALE = 1e-2                              # contact compliances × this: the approach to the rigid limit
OUTER_TOL_MM = 1e-7                               # 0.1 nm (and 0.1 µrad): the outer pose residual
OUTER_MAXIT = 60
POSE_SEED_MM = 3e-4                               # the first pose sits this far into a wall the rigid solution touches (× the
POSE_FD = 1e-6                                    # compliance scale, as is the finite-difference step of the contact stiffness)
PLAY_MM_FOR_SUMMARY = 0.025                       # the zero-interference play (68's), for reading «past the play» in the summary
REFINE_MARGIN_MM = 0.02                           # the refined window reaches this far past the working-grid patch
REFINE_CELLS_MM = (m91.DS_PEAK_MM, m91.DS_PEAK_MM / 2)   # the static peak on two square grids; the larger one is reported
MAX_SPREAD = 0.30                                 # the two finest grids may differ by a resolution scatter, never by more


# ── the inner solve: one window, displacement-controlled, the layer and the Ti only ─────────────────────────────
def pk_window(h0: np.ndarray, conv, p0: np.ndarray | None = None) -> np.ndarray:
    """Polonsky–Keer on one window's layer+Ti operator for a GIVEN rod pose (h0 < 0 where the rigid pose penetrates).
    Warm-started from p0 where it is still in interference; a pose that penetrates nowhere returns p ≡ 0. Refuses a
    non-converged state and checks complementarity."""
    seed = np.where(h0 < 0, 1.0, 0.0) if p0 is None or not (p0 > 0).any() else np.where(h0 < 0, np.maximum(p0, 1e-3), 0.0)
    if not (seed > 0).any():
        return np.zeros_like(h0)
    p, t = seed, np.zeros_like(h0)
    g_old, delta = 1.0, 0.0
    for _it in range(m91.PK_MAXIT):
        g = conv(p) + h0
        ic = p > 0
        if not ic.any():
            return p
        g_sum = float(np.sum(g[ic] ** 2))
        t = np.where(ic, g + delta * (g_sum / g_old) * t, 0.0)
        g_old = g_sum
        r = conv(t)
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
        if np.sum(np.abs(p - p_old)) <= m91.PK_TOL * max(float(np.sum(p)), 1e-300):
            sep = conv(p) + h0
            assert np.abs(sep[p > 0]).max() <= m91.SEP_TOL_MM and sep.min() >= -m91.SEP_TOL_MM, "complementarity not met"
            return p
    raise RuntimeError("Polonsky–Keer did not converge on a window — refusing to report a number")


# ── the rigid references: point contacts at the edges' tangent points ───────────────────────────────────────────
def rigid_points(rod, play: float, off: float, drag: float, x_m: float, x_x: float) -> dict:
    """RIGID walls touching the rod at points: the mouth on −, the exit on + and on −. Exact small LCP by active-set
    enumeration (the rod is linear, so exactly one set satisfies every sign and gap)."""
    st = ((x_m, -1), (x_x, +1), (x_x, -1))

    def v_free(x):
        return drag * rod.defl(x, rod.L)
    for active in ((), (0,), (1,), (2,), (0, 1), (0, 2)):    # both exit sides at one station cannot both close
        react = np.zeros(3)
        if active:
            a = np.array([[st[i][1] * st[j][1] * rod.defl(st[i][0], st[j][0]) for j in active] for i in active])
            b = np.array([-(play - st[i][1] * (v_free(st[i][0]) - off)) for i in active])
            sol = np.linalg.solve(a, b)
            if (sol < -1e-12).any():
                continue
            react[list(active)] = sol

        def v(x, react=react):
            return v_free(x) - sum(st[j][1] * rod.defl(x, st[j][0]) * react[j] for j in range(3))
        gaps = [play - st[i][1] * (v(st[i][0]) - off) for i in range(3)]
        if min(gaps) < -1e-9:
            continue
        m_root = drag * rod.L - sum(st[j][1] * react[j] * st[j][0] for j in range(3))
        return {"R_N": react.tolist(), "gaps_mm": gaps, "m_root_Nmm": m_root, "sigma_signed_MPa": m91.signed_sigma(m_root)}
    raise RuntimeError("no rigid active set satisfies the contact conditions")


# ── the coupled elastic solve ───────────────────────────────────────────────────────────────────────────────────
def solve(geo, liner_row: dict, play: float, off: float, drag: float, r_in: float, *, r_ex: float = R_EX_MM,
          base: str = "bonded", e_peek_mpa: float = m91.E_PEEK_MPA, scale: float = 1.0, ds: float = m91.DS_MM,
          dy: float = m91.DY_MM, tables: dict | None = None, s_len: float = m91.WINDOW_S_MM,
          y_half: float = m91.WINDOW_Y_MM, refine: tuple = (), refine_windows: tuple = ("mouth",)) -> dict:
    """One equilibrium: mouth window on −, exit window on the side the rigid same-edge solution approaches first."""
    rod = m91.Rod(geo, liner_row)
    x_m0 = geo.gap_mm
    rig = rigid_points(rod, play, off, drag, x_m0 + r_in, rod.L - r_ex)
    exit_side = +1 if rig["gaps_mm"][1] <= rig["gaps_mm"][2] else -1
    r_rig = np.array([rig["R_N"][0], rig["R_N"][1] if exit_side > 0 else rig["R_N"][2]])
    x_ref = np.array([x_m0 + r_in, rod.L - r_ex])                   # each window's pose is read at its rigid contact
    for _attempt in range(WINDOW_ATTEMPTS):
        ns, ny = round(s_len / ds), round(2 * y_half / dy)
        y = (np.arange(ny) - (ny - 1) / 2.0) * dy
        cphi = np.cos(y / m91.R_OD_MM)
        w = cphi[None, :] * ds * dy
        g_lay, g_ti = m91.kernel(ns, ny, ds, dy, base, ALLOY_BASELINE, tables)
        conv = m91.Conv((g_lay / e_peek_mpa + g_ti) * scale)
        s0 = (max(0.0, r_in - m91.WINDOW_LEAD_MM), max(0.0, r_ex - m91.WINDOW_LEAD_MM))
        s_m = s0[0] + (np.arange(ns) + 0.5) * ds
        s_x = s0[1] + (np.arange(ns) + 0.5) * ds
        windows = [(-1, x_m0 + s_m, m91.recession_mm(s_m, r_in, 0.0)), (exit_side, rod.L - s_x, m91.recession_mm(s_x, r_ex, 0.0))]
        windows = [(sg, x, np.where(np.isfinite(rec), rec, 1e3)) for sg, x, rec in windows]
        flex = [[rod.defl(windows[k][1][:, None], windows[j][1][None, :]) for j in range(2)] for k in range(2)]
        at_ref = [[(rod.defl(x_ref[k], windows[j][1]), rod.rot(x_ref[k], windows[j][1])) for j in range(2)] for k in range(2)]

        def beam(q, flex=flex, at_ref=at_ref, windows=windows):
            """The rod's value and slope at each window's reference and the rest of its shape there, from line loads q."""
            out = []
            for k in range(2):
                x = windows[k][1]
                v = drag * rod.defl(x, rod.L) - sum(windows[j][0] * (flex[k][j] @ q[j]) for j in range(2))
                a = drag * rod.defl(x_ref[k], rod.L) - sum(windows[j][0] * (at_ref[k][j][0] @ q[j]) for j in range(2))
                b = drag * rod.rot(x_ref[k], rod.L) - sum(windows[j][0] * (at_ref[k][j][1] @ q[j]) for j in range(2))
                out.append((a, b, v - (a + b * (x - x_ref[k]))))
            return out

        def contact(k, uk, curv, p0, windows=windows, cphi=cphi, conv=conv, w=w):
            sg, x, rec = windows[k]
            v = uk[0] + uk[1] * (x - x_ref[k]) + curv
            p = pk_window(play + rec[:, None] - sg * (v - off)[:, None] * cphi[None, :], conv, p0)
            return p, (p * w).sum(axis=1)
        q = [np.zeros(ns), np.zeros(ns)]
        for k in range(2):
            q[k][int(np.argmin(np.abs(windows[k][1] - x_ref[k])))] = r_rig[k]
        bm = beam(q)
        u = np.array([[bm[k][0] + (windows[k][0] * POSE_SEED_MM * scale if r_rig[k] > 0 else 0.0), bm[k][1]] for k in range(2)])
        pres = [None, None]
        truncated = False
        for itn in range(OUTER_MAXIT):
            iters = itn + 1
            q_new, dq = [None, None], [None, None]
            for k in range(2):
                pres[k], q_new[k] = contact(k, u[k], bm[k][2], pres[k])
                if q_new[k].sum() > 0.0:
                    cols = []
                    for j in range(2):
                        u2 = u[k].copy()
                        u2[j] += POSE_FD * scale
                        cols.append((contact(k, u2, bm[k][2], pres[k])[1] - q_new[k]) / (POSE_FD * scale))
                    dq[k] = np.stack(cols, axis=1)
                    ii, jj = np.nonzero(pres[k] > 0)
                    if ii.max() > ns - 3 or (ii.min() < 2 and s0[k] > 0.0) or np.abs(y[jj]).max() > y_half - 2 * dy:
                        truncated = True      # a patch at the window's edge: a truncated problem — grow and restart
                else:
                    dq[k] = np.zeros((ns, 2))
            if truncated:
                break
            bm = beam(q_new)
            res = np.array([[u[k][0] - bm[k][0], u[k][1] - bm[k][1]] for k in range(2)]).ravel()
            q = q_new
            if np.all(np.abs(res) < OUTER_TOL_MM):
                break
            jac = np.eye(4)
            for k in range(2):
                for j in range(2):
                    jac[2 * k, 2 * j:2 * j + 2] += windows[j][0] * (at_ref[k][j][0] @ dq[j])
                    jac[2 * k + 1, 2 * j:2 * j + 2] += windows[j][0] * (at_ref[k][j][1] @ dq[j])
            u = (u.ravel() - np.linalg.solve(jac, res)).reshape(2, 2)
        else:
            raise RuntimeError("the outer pose Newton did not converge — refusing to report a number")
        react = np.array([q[k].sum() for k in range(2)])
        act = react > 0.0

        def pose(x, q=q, windows=windows):
            return drag * rod.defl(x, rod.L) - sum(windows[k][0] * (rod.defl(x[:, None], windows[k][1][None, :]) @ q[k]) for k in range(2))
        # the whole channel between the windows: where the rod lies almost parallel to a wall, the give carries the patch
        # past the window's end — the same truncation as a patch at the edge, so the windows grow and the solve restarts
        x_run = np.linspace(x_m0 + r_in, rod.L - r_ex, 400)
        covered = np.zeros_like(x_run, dtype=bool)
        for k in np.nonzero(act)[0]:
            covered |= (x_run >= windows[k][1].min()) & (x_run <= windows[k][1].max())
        if (play - np.abs(pose(x_run) - off)[~covered]).min() < -m91.SEP_TOL_MM:
            truncated = True
        if not truncated:
            break
        s_len, y_half = s_len * 2, y_half * 2
    else:
        raise RuntimeError("a contact patch outgrew every window (or the rod lies along the wall between them) — "
                           "a line contact two end windows cannot represent; refusing")
    assert play + exit_side * (pose(np.array([rod.L]))[0] - off) >= -m91.SEP_TOL_MM, "the exit side not modelled was reached"
    assert play - (pose(np.array([x_m0]))[0] - off) >= -m91.SEP_TOL_MM, "the mouth's far wall was reached"
    m_root = drag * rod.L - sum(windows[k][0] * float(q[k] @ windows[k][1]) for k in range(2))
    out = {"contact": bool(act.any()), "R_N": react.tolist(), "exit_side": exit_side, "m_root_Nmm": m_root,
           "sigma_signed_MPa": m91.signed_sigma(m_root), "outer_iterations": iters, "rigid": rig}
    for k, name in enumerate(("mouth", "exit")):
        if act[k]:
            p = pres[k]
            ii, jj = np.nonzero(p > 0)
            give = conv(p) / scale
            s_arr = s_m if k == 0 else s_x
            out[name] = {"R_N": float(react[k]), "p_max_MPa": float(p.max()), "area_mm2": float(np.count_nonzero(p) * ds * dy),
                         "patch_s_mm": [float(s_arr[ii.min()] - ds / 2), float(s_arr[ii.max()] + ds / 2)],
                         "patch_half_angle_rad": float(np.abs(y[jj]).max() / m91.R_OD_MM),
                         "give_um": float((give * p).sum() / p.sum()) * 1e3}
            assert out[name]["patch_half_angle_rad"] < 0.35, "the patch wraps too far round the tube for a flat layer"
        else:
            out[name] = None
    # the edge peak on finer grids: each window in `refine_windows` re-solved alone on square cells (each of `refine`) round its patch, in
    # the converged pose — the pose is set by the beam and the give, both resolved on the working grid
    for cell in refine:
        for k, name in ((0, "mouth"), (1, "exit")):
            if name not in refine_windows:
                continue
            if out[name] is None:
                continue
            sg, r_k = windows[k][0], (r_in, r_ex)[k]
            lo, hi = out[name]["patch_s_mm"]
            half = out[name]["patch_half_angle_rad"] * m91.R_OD_MM + REFINE_MARGIN_MM
            s_lo = max(0.0, lo - REFINE_MARGIN_MM)
            nsf, nyf = round((hi + REFINE_MARGIN_MM - s_lo) / cell), 2 * round(half / cell)
            sf = s_lo + (np.arange(nsf) + 0.5) * cell
            yf = (np.arange(nyf) - (nyf - 1) / 2.0) * cell
            cf = np.cos(yf / m91.R_OD_MM)
            xf = x_m0 + sf if k == 0 else rod.L - sf
            rec = m91.recession_mm(sf, r_k, 0.0)
            g_lay_f, g_ti_f = m91.kernel(nsf, nyf, cell, cell, base, ALLOY_BASELINE, tables)
            conv_f = m91.Conv((g_lay_f / e_peek_mpa + g_ti_f) * scale)
            pf = pk_window(play + np.where(np.isfinite(rec), rec, 1e3)[:, None] - sg * (pose(xf) - off)[:, None] * cf[None, :], conv_f)
            ii, jj = np.nonzero(pf > 0)
            assert ii.max() <= nsf - 3 and (ii.min() >= 2 or s_lo == 0.0) and np.abs(yf[jj]).max() <= half - 2 * cell, \
                "the refined patch left its window"
            r_f = float((pf * cf[None, :]).sum() * cell * cell)
            assert abs(r_f / out[name]["R_N"] - 1.0) <= 0.03, f"the refined {name} reaction strays from the solve ({r_f:.4f})"
            out[name].setdefault("p_max_MPa_refined", {})[f"{cell:g}"] = float(pf.max())
            out[name].setdefault("R_N_refined", {})[f"{cell:g}"] = r_f
    # the wire's nominal fibre stress at the two edge sections (the moment about each section of the loads beyond it)
    out["section_sigma_signed_MPa"] = {}
    for k, name in enumerate(("mouth", "exit")):
        xs = float(q[k] @ windows[k][1] / react[k]) if act[k] else x_ref[k]
        m_sec = drag * (rod.L - xs) - sum(windows[j][0] * float(q[j] @ np.maximum(windows[j][1] - xs, 0.0)) for j in range(2))
        out["section_sigma_signed_MPa"][name] = wire_sigma(geo, liner_row, xs, m_sec)
    return out


def wire_sigma(geo, liner_row: dict, x: float, m_nmm: float) -> float:
    """Nominal fibre stress of the WIRE at section x under moment m (signed): E_Ti·c·M/EI of the member there."""
    ei = s55.member_ei_at(geo, liner_row, True)(x) * 1e6          # N·mm²
    e_ti = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3        # N/mm²
    return float(e_ti * (s55.D_BUS / 2.0) * m_nmm / ei)


def geometry_with_shank(shank_mm: float):
    """55's shipped geometry with another Zone-3 shank length: the mouth moves, the rod length does not."""
    g = s55.SHIPPED_GEOMETRY
    gap = s55.SLEEVE_LEN_MM - g.insertion_mm - shank_mm
    return s55.Geometry(f"shank {shank_mm:g} mm", g.insertion_mm, gap, g.pad_mm, gap - s55.LINER_PROTRUSION_MM)


def flow_ratio(p_max: float) -> dict:
    """The edge peak over 55's flow pressures (constraint factor × PEEK 23 °C tensile yield)."""
    return {f"{c:.1f}": round(p_max / (c * SIGMA_YIELD_PEEK_PA / 1e6), 3) for c in s55.CONTACT_CONSTRAINT_FACTORS}


def row(st: dict) -> dict:
    """The cache row of one equilibrium."""
    out = {"sigma_signed_MPa": round(st["sigma_signed_MPa"], 3),
           "rigid_same_edges_sigma_signed_MPa": round(st["rigid"]["sigma_signed_MPa"], 3),
           "R_N": [round(v, 5) for v in st["R_N"]], "exit_side": st["exit_side"]}
    if st["contact"]:
        out["section_sigma_signed_MPa"] = {k: round(v, 3) for k, v in st["section_sigma_signed_MPa"].items()}
        for name in ("mouth", "exit"):
            pt = st.get(name)
            ref = pt.get("p_max_MPa_refined") if pt else None
            pk = max(ref.values()) if ref else (pt["p_max_MPa"] if pt else None)
            out[name] = None if pt is None else {
                "p_max_MPa": round(pk, 2), "p_max_working_grid_MPa": round(pt["p_max_MPa"], 2),
                "p_max_by_square_cell_MPa": {c: round(v, 2) for c, v in ref.items()} if ref else None,
                "resolution_spread": round(max(list(ref.values())[-2:]) / min(list(ref.values())[-2:]) - 1.0, 3) if ref else None,
                "p_max_over_flow": flow_ratio(pk),
                "area_mm2": round(pt["area_mm2"], 5), "patch_s_mm": [round(v, 4) for v in pt["patch_s_mm"]],
                "give_um": round(pt["give_um"], 3)}
    return out


def drag_path(rod, play: float, off: float, x_m: float, x_x: float, f: float) -> list:
    """DRAG_PATH × f plus every change of the rigid same-edge active set along it — the kinks where the cycle's extremes
    sit (a contact lifting off or touching down) — bisected and taken at the kink and TRANSITION_SIDE·f either side."""
    def key(d):
        return tuple(v > 0.0 for v in rigid_points(rod, play, off, d, x_m, x_x)["R_N"])
    pts = {round(fr * f, 6) for fr in DRAG_PATH}
    grid = np.linspace(-f, f, PATH_SCAN)
    keys = [key(d) for d in grid]
    for a, b, ka, kb in zip(grid[:-1], grid[1:], keys[:-1], keys[1:], strict=True):
        if ka == kb:
            continue
        lo, hi = float(a), float(b)
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            lo, hi = (mid, hi) if key(mid) == ka else (lo, mid)
        t = 0.5 * (lo + hi)
        for d in (t - TRANSITION_SIDE * f, t, t + TRANSITION_SIDE * f):
            pts.add(round(float(np.clip(d, -f, f)), 6))
    return sorted(pts)


def _path_row(geo, liner_row: dict, play: float, off: float, d: float, r_in: float, tables, r_ex: float = R_EX_MM) -> dict:
    """One point of a path; a point the two windows cannot represent is RECORDED as such, never dropped silently."""
    try:
        return {"drag_N": d, **row(solve(geo, liner_row, play, off, d, r_in, r_ex=r_ex, tables=tables))}
    except RuntimeError as err:
        return {"drag_N": d, "not_solved": str(err)[:160]}


def cycle(geo, liner_row: dict, play: float, off: float, r_in: float, f: float, tables: dict, memo: dict) -> list:
    """The elastic equilibria along the drag path of one offset and entry radius (memoised: blocks share paths)."""
    key = (geo.label, round(off, 6), r_in)
    if key not in memo:
        rod = m91.Rod(geo, liner_row)
        path = drag_path(rod, play, off, geo.gap_mm + r_in, rod.L - R_EX_MM, f)
        memo[key] = [_path_row(geo, liner_row, play, off, d, r_in, tables) for d in path]
    return memo[key]


def rigid_swing(geo, liner_row: dict, play: float, off: float, r_in: float, f: float) -> dict:
    """The beam's swing on the rigid same-edge point model along the path (its own kinks included): the root and the
    wire's nominal stress at the mouth-edge and exit-edge sections."""
    rod = m91.Rod(geo, liner_row)
    x_m, x_x = geo.gap_mm + r_in, rod.L - R_EX_MM
    st = ((x_m, -1), (x_x, +1), (x_x, -1))
    path = drag_path(rod, play, off, x_m, x_x, f)
    root, mo, ex = [], [], []
    for d in path:
        r = rigid_points(rod, play, off, d, x_m, x_x)
        root.append(r["sigma_signed_MPa"])
        for xs, acc in ((x_m, mo), (x_x, ex)):
            m_sec = d * (rod.L - xs) - sum(st[j][1] * r["R_N"][j] * max(st[j][0] - xs, 0.0) for j in range(3))
            acc.append(wire_sigma(geo, liner_row, xs, m_sec))
    return {"offset_um": round(off * 1000.0), "points": len(path), "root_mean_amplitude_MPa": list(swing(root)),
            "ends_only_amplitude_MPa": round(abs(root[-1] - root[0]) / 2.0, 3),
            "mouth_section_mean_amplitude_MPa": list(swing(mo)), "exit_section_mean_amplitude_MPa": list(swing(ex)),
            "mouth_over_root_amplitude": round(swing(mo)[1] / swing(root)[1], 3)}


def exit_cycle_peak(geo, liner_row: dict, play: float, off: float, r_ex: float, f: float, tables=None) -> dict:
    """The EXIT-edge peak over the drag cycle at exit radius r_ex (entry at the reference radius): located on the working
    grid where the exit carries load (rigid same-edge model), refined at that drag on the exit window."""
    rod = m91.Rod(geo, liner_row)
    x_m, x_x = geo.gap_mm + R_IN_REFERENCE_MM, rod.L - r_ex
    drags = [d for d in drag_path(rod, play, off, x_m, x_x, f) if max(rigid_points(rod, play, off, d, x_m, x_x)["R_N"][1:]) > 0.0]
    path_all = [_path_row(geo, liner_row, play, off, d, R_IN_REFERENCE_MM, tables, r_ex) for d in drags]
    path = [p for p in path_all if "not_solved" not in p and p.get("exit")]
    at = max(path, key=lambda p: p["exit"]["p_max_working_grid_MPa"])
    st = solve(geo, liner_row, play, off, at["drag_N"], R_IN_REFERENCE_MM, r_ex=r_ex, refine=REFINE_CELLS_MM,
               refine_windows=("exit",), tables=tables)
    ref = st["exit"]["p_max_MPa_refined"]
    if max(ref.values()) / min(ref.values()) - 1.0 > MAX_SPREAD:
        ref.update(solve(geo, liner_row, play, off, at["drag_N"], R_IN_REFERENCE_MM, r_ex=r_ex, refine=(REFINE_CELLS_MM[-1] / 2,),
                         refine_windows=("exit",), tables=tables)["exit"]["p_max_MPa_refined"])
    vals = list(ref.values())
    return {"offset_um": round(off * 1000.0), "r_exit_mm": r_ex, "drag_at_peak_N": at["drag_N"], "peak_MPa": round(max(vals), 2),
            "peak_by_square_cell_MPa": {c: round(v, 2) for c, v in ref.items()},
            "resolution_spread": round(max(vals[-2:]) / min(vals[-2:]) - 1.0, 3), "points": len(path),
            "points_not_solved": len(path_all) - len([p for p in path_all if "not_solved" not in p]),
            "peak_over_flow": flow_ratio(max(vals)),
            "flow_verdict": {f"{c:.1f}": ("above" if min(vals) > c * SIGMA_YIELD_PEEK_PA / 1e6 else
                                          "below" if max(vals) < c * SIGMA_YIELD_PEEK_PA / 1e6 else "at, within the grids")
                             for c in s55.CONTACT_CONSTRAINT_FACTORS}}


def _exit_task(args) -> dict:
    geo, liner_row, play, off, r_ex, f = args
    return exit_cycle_peak(geo, liner_row, play, off, r_ex, f)


def _cycle_task(args) -> list:
    """One elastic path in a worker process (the kernels are cached per process)."""
    geo, liner_row, play, off, r_in, f = args
    return cycle(geo, liner_row, play, off, r_in, f, None, {})


def _cycle_peak_task(args) -> dict:
    geo, liner_row, play, off, r_in, f = args
    return cycle_peak(geo, liner_row, play, off, r_in, f, None, {})


def swing(values: list) -> tuple:
    return round((max(values) + min(values)) / 2.0, 3), round((max(values) - min(values)) / 2.0, 3)


def cycle_peak(geo, liner_row: dict, play: float, off: float, r_in: float, f: float, tables: dict, memo: dict) -> dict:
    """The mouth-edge peak over the drag cycle: located on the working grid along the path (the points where the rigid
    same-edge model keeps the mouth loaded — elsewhere the mouth carries nothing), then refined at that drag on the square
    grids (a third where two disagree); the verdict against the flow pressure from every grid."""
    rod = m91.Rod(geo, liner_row)
    x_m, x_x = geo.gap_mm + r_in, rod.L - R_EX_MM
    drags = [d for d in drag_path(rod, play, off, x_m, x_x, f)       # only where the mouth carries load (rigid, same edges)
             if rigid_points(rod, play, off, d, x_m, x_x)["R_N"][0] > 0.0 or d == 0.0]
    key = (geo.label, round(off, 6), r_in)
    path_all = memo[key] if key in memo else [_path_row(geo, liner_row, play, off, d, r_in, tables) for d in drags]
    path = [p for p in path_all if "not_solved" not in p]
    lit = [p for p in path if p.get("mouth")]
    at = max(lit, key=lambda p: p["mouth"]["p_max_MPa"])
    st = solve(geo, liner_row, play, off, at["drag_N"], r_in, refine=REFINE_CELLS_MM, tables=tables)
    ref = st["mouth"]["p_max_MPa_refined"]
    if max(ref.values()) / min(ref.values()) - 1.0 > MAX_SPREAD:
        ref.update(solve(geo, liner_row, play, off, at["drag_N"], r_in, refine=(REFINE_CELLS_MM[-1] / 2,),
                         tables=tables)["mouth"]["p_max_MPa_refined"])
    vals = list(ref.values())
    static = next(p for p in path if p["drag_N"] == 0.0)
    return {"geometry": geo.label, "mouth_station_mm": geo.gap_mm, "offset_um": round(off * 1000.0), "r_in_mm": r_in,
            "drag_at_peak_N": at["drag_N"], "peak_MPa": round(max(vals), 2), "points": len(path),
            "points_not_solved": len(path_all) - len(path),
            "peak_by_square_cell_MPa": {c: round(v, 2) for c, v in ref.items()},
            "resolution_spread": round(max(vals[-2:]) / min(vals[-2:]) - 1.0, 3),
            "static_working_grid_MPa": static["mouth"]["p_max_working_grid_MPa"] if static.get("mouth") else None,
            "peak_over_flow": flow_ratio(max(vals)),
            "flow_verdict": {f"{c:.1f}": ("above" if min(vals) > c * SIGMA_YIELD_PEEK_PA / 1e6 else
                                          "below" if max(vals) < c * SIGMA_YIELD_PEEK_PA / 1e6 else "at, within the grids")
                             for c in s55.CONTACT_CONSTRAINT_FACTORS}}


def summarise(static, cyc, swings, reversing, brackets, shank, ctl, exits, swing_by_radius, d86) -> dict:
    """The claims, each asserted on the rows it is read from or written from them. The decision frame first: the ratified
    ⌀0.10 admits offsets up to TOLERANCE_OFFSET_UM; rows beyond it are read as the margin, never as the verdict's ground."""
    ship = s55.SHIPPED_GEOMETRY.label
    give = [(r["rigid_same_edges_sigma_signed_MPa"] - r["sigma_signed_MPa"]) / r["rigid_same_edges_sigma_signed_MPa"] for r in static]
    assert min(give) > 0.0, "the layer's give raised the root against a rigid wall at the same edges"
    for e in sorted({r["offset_um"] for r in static}):
        rows = sorted((r for r in static if r["offset_um"] == e), key=lambda r: r["r_in_mm"])
        sig = [r["sigma_signed_MPa"] for r in rows]
        pk = [r["mouth"]["p_max_MPa"] for r in rows]
        assert sig == sorted(sig, reverse=True) and pk == sorted(pk, reverse=True), f"{e} µm: the entry radius is not monotone"
    assert all(c["flow_verdict"]["3.0"] == "below" for c in cyc + exits), "an edge peak over the cycle reaches 3·σ_y"

    def safe_r(rows, key="r_in_mm"):
        rows = sorted(rows, key=lambda c: c[key])
        ok = [c[key] for i, c in enumerate(rows) if all(x["flow_verdict"]["1.0"] == "below" for x in rows[i:])]
        return min(ok) if ok else None
    geos = list(dict.fromkeys(c["geometry"] for c in cyc))
    safe = {f"{g} / {e} µm": {"mouth_station_mm": next(c["mouth_station_mm"] for c in cyc if c["geometry"] == g),
                              "smallest_r_in_below_1_sigma_y_mm": safe_r([c for c in cyc if c["geometry"] == g and c["offset_um"] == e]),
                              "worst_over_flow_1": max(c["peak_over_flow"]["1.0"] for c in cyc if c["geometry"] == g and c["offset_um"] == e)}
            for g in geos for e in sorted({c["offset_um"] for c in cyc if c["geometry"] == g})}
    tol = {k: v for k, v in safe.items() if k.endswith(f"/ {TOLERANCE_OFFSET_UM} µm")}
    beyond = [c for c in cyc if c["offset_um"] > TOLERANCE_OFFSET_UM and c["flow_verdict"]["1.0"] != "below"]
    within_above = [c for c in cyc if c["offset_um"] <= TOLERANCE_OFFSET_UM and c["flow_verdict"]["1.0"] != "below"]
    worst = max(cyc, key=lambda c: c["peak_over_flow"]["1.0"])
    lift = []
    for c in cyc:                                   # the cycle against the REFINED static peak, where block (a) has it
        st = next((r for r in static if c["geometry"] == ship and r["offset_um"] == c["offset_um"] and r["r_in_mm"] == c["r_in_mm"]), None)
        if st:
            lift.append(c["peak_MPa"] / st["mouth"]["p_max_MPa"] - 1.0)
    assert lift and min(lift) >= -0.01, "on the shipped shank the cycle peak fell below the refined static one"
    ex0 = {x["r_exit_mm"]: x for x in exits if x["offset_um"] == 0}
    ex50 = {x["r_exit_mm"]: x for x in exits if x["offset_um"] == TOLERANCE_OFFSET_UM}
    ex_rise = {r: ex50[r]["peak_MPa"] / ex0[r]["peak_MPa"] for r in ex0}
    assert min(ex_rise.values()) > 1.0, "the offset did not load the exit edge more than the coaxial drag"
    ex_above = [x for x in exits if x["flow_verdict"]["1.0"] != "below"]
    sw = {w["offset_um"]: w for w in swings}
    ratio = {e: w["mouth_over_root_amplitude"] for e, w in sw.items()}
    play_um = PLAY_MM_FOR_SUMMARY * 1000.0
    assert ratio[0] < 1.0 and ratio[10] < 1.0, "coaxially the mouth section out-swings the root"
    below_near = [e for e, v in ratio.items() if play_um < e and v < 1.0]
    above_from = min(e for e, v in ratio.items() if e > play_um and v > 1.0 and all(ratio[x] > 1.0 for x in ratio if x >= e))
    peak_e = max(ratio, key=ratio.get)
    sat = [e for e in ratio if e >= 50]
    mo_abs = [sw[e]["mouth_section_mean_amplitude_MPa"][1] for e in sat]
    root_abs = [sw[e]["root_mean_amplitude_MPa"][1] for e in sat]
    ends_short = {e: 1.0 - w["ends_only_amplitude_MPa"] / w["root_mean_amplitude_MPa"][1] for e, w in sw.items()}
    assert all(v >= -1e-9 for v in ends_short.values()), "the path's ends gave a larger swing than the path"
    worst_ends = max(ends_short, key=ends_short.get)
    v68 = {e: sw[e]["amplitude_68_rigid_sharp_ends_MPa"] / sw[e]["root_mean_amplitude_MPa"][1] - 1.0
           for e in sw if sw[e].get("amplitude_68_rigid_sharp_ends_MPa")}
    rad = {e: [w for w in swing_by_radius if w["offset_um"] == e] for e in SWING_RADIUS_OFFSETS_UM}
    rad_root = [rad[e][1]["root_mean_amplitude_MPa"][1] / rad[e][0]["root_mean_amplitude_MPa"][1] - 1.0 for e in rad]
    corr = {r["offset_um"]: (r["amplitude_MPa"] / r["rigid_same_edges_amplitude_MPa"] - 1.0,
                             r["mouth_section_mean_amplitude_MPa"][1] / r["rigid_mouth_section_amplitude_MPa"] - 1.0) for r in reversing}
    r50 = next(r for r in reversing if r["offset_um"] == TOLERANCE_OFFSET_UM)
    g86 = d86["by_geometry"][ship]
    b86 = d86["branches"]["loose_50"]["by_geometry"][ship]
    pk_b = {(b["base"], b["modulus"]): b["mouth_p_max_MPa"] for b in brackets}
    root_b = [b["by_drag"]["+0"]["sigma_signed_MPa"] for b in brackets]
    sh = sorted(shank, key=lambda z: z["shank_mm"])

    def k_needed(mean, amp):   # 86's break-even seam k for ONE cycle — its formula, SF target and alloys, binding over the six
        sf = d86["inputs"]["sf_target"]
        return max(amp / (a["endurance_MPa"] * (1.0 / sf - mean / a["yield_MPa"])) for a in g86["by_alloy"].values())
    k_ship = k_needed(r50["mean_MPa"], r50["amplitude_MPa"])
    k_by_shank = {z["shank_mm"]: k_needed(*z["root_mean_amplitude_MPa"]) for z in sh}
    assert max(k_by_shank.values()) < b86["k_break_even_binding"], "a cycle at the tolerance limit needs more seam k than 86's threshold"
    mean_beyond = [z for z in sh if z["root_mean_amplitude_MPa"][0] > b86["mean_MPa"]]
    sh_static = [z["static_sigma_MPa"] for z in sh]
    assert sh_static == sorted(sh_static), "a mouth nearer the root did not make the offset dearer"
    not_solved = (sum(c["points_not_solved"] for c in cyc + exits) + sum(len(r["not_solved"]) for r in reversing)
                  + sum(len(z["not_solved"]) for z in shank))
    all_points = (sum(c["points"] + c["points_not_solved"] for c in cyc + exits) + sum(r["points"] + len(r["not_solved"]) for r in reversing)
                  + sum(z["points"] + len(z["not_solved"]) for z in shank))
    text = (f"(A) The layer's give lowers the static root against a rigid wall at the same edges by {100 * min(give):.1f}–"
            f"{100 * max(give):.1f} % on every row — 68's secant stands. (B) A larger entry radius lowers the static root and the "
            f"static mouth-edge peak on every offset row; the beam's swing it moves only a little and not one way (rigid, r_in "
            f"{min(R_IN_SWEEP_MM):g} → {max(R_IN_SWEEP_MM):g} mm: the root's by {100 * min(rad_root):+.0f}…{100 * max(rad_root):+.0f} % "
            f"over {', '.join(str(e) for e in SWING_RADIUS_OFFSETS_UM)} µm). "
            f"(C) The drag raises the mouth-edge peak above the static one on every shipped-shank row (by {100 * max(0.0, min(lift)):.0f}–"
            f"{100 * max(lift):.0f} %). WITHIN the ratified ⌀0.10 (offsets up to {TOLERANCE_OFFSET_UM} µm) the cycle peak "
            + ("stays below 1·σ_y (23 °C tensile) on every swept shank and entry radius — the worst ×"
               + f"{max(v['worst_over_flow_1'] for v in tol.values()):.2f}" if not within_above else
               "passes 1·σ_y on " + ", ".join(f"{c['geometry']} r_in {c['r_in_mm']:g}" for c in within_above))
            + "; BEYOND it, at 75–100 µm, it passes 1·σ_y on "
            f"{len(beyond)} rows, the largest ×{worst['peak_over_flow']['1.0']:.2f} ({worst['geometry']}, {worst['offset_um']} µm, r_in "
            f"{worst['r_in_mm']:g} mm), and at 100 µm the smallest swept radius that holds is " + " · ".join(
                f"{safe[f'{g} / 100 µm']['smallest_r_in_below_1_sigma_y_mm']} mm with the mouth at {safe[f'{g} / 100 µm']['mouth_station_mm']:g} mm"
                for g in geos)
            + f"; below 3·σ_y everywhere. (C′) The EXIT edge is the more loaded one under an offset: coaxially its cycle peak is 91's "
            f"(within {100 * ctl['exit_coaxial_vs_91']['max_rel_diff']:.1f} %), and at {TOLERANCE_OFFSET_UM} µm — on the shipped shank "
            f"with entry radius {R_IN_REFERENCE_MM:g} mm, the flush exit (no countersink) and zero interference — it is ×"
            f"{min(ex_rise.values()):.2f}–{max(ex_rise.values()):.2f} that, "
            + (("above 1·σ_y at r_exit " + ", ".join(f"{x['r_exit_mm']:g} mm (×{x['peak_over_flow']['1.0']:.2f})" for x in ex_above)
                + " — the smallest swept exit radius that holds there is "
                + f"{safe_r(list(ex50.values()), 'r_exit_mm')} mm") if ex_above else "below 1·σ_y at every swept exit radius")
            + f". (D) Along the path with its contact kinks the root's swing is larger than its two ends give where the edges are "
            f"rounded: the ends alone catch as little as {100 * (1 - ends_short[worst_ends]):.0f} % of it (at {worst_ends} µm, where the "
            f"swing itself is smallest); at the offsets 68 tabulates, its sharp-edge rows sit within "
            f"{100 * max(abs(v) for v in v68.values()):.0f} % of this path's swing. Against 86's threshold k ≥ "
            f"{b86['k_break_even_binding']:g} (amplitude {g86['amplitude_MPa']:g} MPa, the Ti-bore stop; mean {b86['mean_MPa']:g} MPa, "
            f"the worst play): at {TOLERANCE_OFFSET_UM} µm and zero interference the root cycle runs at {r50['mean_MPa']:.2f} ± "
            f"{r50['amplitude_MPa']:.2f} MPa on the shipped shank and needs k ≥ {k_ship:.3f} (86's formula, binding over its six alloys), "
            f"{min(k_by_shank.values()):.3f}–{max(k_by_shank.values()):.3f} over the swept shanks — the threshold covers these cycles "
            "through its AMPLITUDE, not its "
            "mean" + ("" if not mean_beyond else ": on the " + " · ".join(f"{z['shank_mm']:g} mm" for z in mean_beyond)
                      + " shank the mean, " + " · ".join(f"{z['root_mean_amplitude_MPa'][0]:.2f}" for z in mean_beyond)
                      + f" MPa, lies beyond 86's {b86['mean_MPa']:g}")
            + ". The cycle at the worst play and a pogo-pad couple on top of the offset are computed by no model. "
            f"(E) The wire under the MOUTH edge swings ±"
            f"{min(mo_abs):.2f}–{max(mo_abs):.2f} MPa from 50 µm on, against the root's ±{min(root_abs):.2f}–{max(root_abs):.2f} MPa "
            f"(×{ratio[100]:.2f}), around a mean of the opposite sign; the ratio crosses 1 at {above_from} µm (below it coaxially, ×"
            f"{ratio[0]:.2f}, and just past the play, " + ", ".join(f"×{ratio[e]:.2f} at {e} µm" for e in below_near)
            + f") and peaks at ×{ratio[peak_e]:.2f} near {peak_e} µm because the root's swing dips there "
            f"(±{sw[peak_e]['root_mean_amplitude_MPa'][1]:.2f}), not because the mouth section's grows. No notch factor under that "
            f"edge is computed. The swings are on the rigid same-edge model; the give moves them by "
            + " · ".join(f"{e} µm {100 * c[0]:+.1f} / {100 * c[1]:+.1f} %" for e, c in corr.items())
            + " (root / mouth section). (F) Bonded ⊥ frictionless base and the 20-year modulus move the static root by ≤ "
            f"{max(root_b) - min(root_b):.2f} MPa; the relaxed modulus lowers the mouth peak at the drag's ends from "
            f"{pk_b[('bonded', 'short-term')]:.0f} to {pk_b[('bonded', '20-yr relaxed')]:.0f} MPa. (G) A mouth nearer the root makes "
            f"the same offset dearer: the static root at 50 µm is " + " · ".join(f"{z['static_sigma_MPa']:.2f}" for z in sh)
            + " MPa for a shank of " + " · ".join(f"{z['shank_mm']:g}" for z in sh) + " mm."
            + (f" {not_solved} of {all_points} elastic path points could not be represented by two end windows (the rod along "
               f"the wall) and are excluded, not replaced." if not_solved else f" Every one of the {all_points} elastic path points solved."))
    return {"give_lowers_root_fraction": [round(min(give), 4), round(max(give), 4)],
            "tolerance_offset_um": TOLERANCE_OFFSET_UM,
            "within_tolerance_rows_at_or_above_1_sigma_y": [{"geometry": c["geometry"], "r_in_mm": c["r_in_mm"]} for c in within_above],
            "beyond_tolerance_rows_at_or_above_1_sigma_y": [{"geometry": c["geometry"], "offset_um": c["offset_um"], "r_in_mm": c["r_in_mm"],
                                                              "peak_over_flow_1": c["peak_over_flow"]["1.0"]} for c in beyond],
            "worst_cycle_row": {"geometry": worst["geometry"], "offset_um": worst["offset_um"], "r_in_mm": worst["r_in_mm"],
                                "peak_MPa": worst["peak_MPa"], "peak_over_flow_1": worst["peak_over_flow"]["1.0"]},
            "smallest_r_in_below_1_sigma_y": safe,
            "exit_rise_at_tolerance": {f"{r:g}": round(v, 3) for r, v in ex_rise.items()},
            "exit_rows_at_or_above_1_sigma_y": [{"offset_um": x["offset_um"], "r_exit_mm": x["r_exit_mm"],
                                                 "peak_over_flow_1": x["peak_over_flow"]["1.0"]} for x in ex_above],
            "smallest_r_exit_below_1_sigma_y_at_tolerance_mm": safe_r(list(ex50.values()), "r_exit_mm"),
            "cycle_over_static_shipped": [round(min(lift), 4), round(max(lift), 4)],
            "mouth_over_root_amplitude_by_offset": {str(e): v for e, v in ratio.items()},
            "ratio_below_one_past_play_um": below_near, "ratio_above_one_from_um": above_from, "ratio_peak_at_um": peak_e,
            "mouth_section_swing_from_50um_MPa": [min(mo_abs), max(mo_abs)], "root_swing_from_50um_MPa": [min(root_abs), max(root_abs)],
            "ends_only_understate_amplitude_by": {str(e): round(v, 4) for e, v in ends_short.items()},
            "sharp_68_over_path_swing": {str(e): round(v, 4) for e, v in v68.items()},
            "entry_radius_raises_root_swing": [round(min(rad_root), 4), round(max(rad_root), 4)],
            "elastic_over_rigid_swing_by_offset": {str(e): [round(c[0], 4), round(c[1], 4)] for e, c in corr.items()},
            "versus_86_threshold": {"k_break_even_binding": b86["k_break_even_binding"], "amplitude_MPa_86": g86["amplitude_MPa"],
                                    "mean_MPa_86": b86["mean_MPa"], "cycle_mean_MPa": r50["mean_MPa"], "cycle_amplitude_MPa": r50["amplitude_MPa"],
                                    "k_needed_shipped": round(k_ship, 4),
                                    "k_needed_by_shank": {f"{s:g}": round(k, 4) for s, k in k_by_shank.items()},
                                    "shanks_with_mean_beyond_86": [z["shank_mm"] for z in mean_beyond]},
            "static_root_by_shank_MPa": {f"{z['shank_mm']:g}": z["static_sigma_MPa"] for z in sh},
            "elastic_points_not_solved": not_solved, "elastic_points": all_points,
            "text": text}


def resummarise() -> int:
    """Re-derive the summary from the cached rows (a pure function of them) — no solve is repeated."""
    d = json.loads(OUT_JSON.read_text(encoding="utf-8"))
    d86 = json.loads(COAX86_CACHE.read_text(encoding="utf-8"))
    d["summary"] = summarise(d["static"], d["cycle_peak"], d["rigid_swing"], d["reversing"], d["brackets"], d["shank"], d["controls"],
                             d["exit_cycle_peak"], d["swing_by_entry_radius"], d86)
    OUT_JSON.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
    print("  → " + d["summary"]["text"])
    return 0


def main() -> int:
    if "--resummarise" in sys.argv:
        return resummarise()
    t0 = time.time()
    banner("Bus liner at the channel MOUTH under an axis offset — two elastic patches coupled to the rod (HW.34 / HW.23)")
    d68 = json.loads(BUS68_CACHE.read_text(encoding="utf-8"))
    d91 = json.loads(BUS91_CACHE.read_text(encoding="utf-8"))
    d86 = json.loads(COAX86_CACHE.read_text(encoding="utf-8"))
    geo = s55.SHIPPED_GEOMETRY
    liner = next({"branch": lb, "coating_or_liner_mm": t, "play_side": side}
                 for lb, t, side in s55.INSULATION_OPTIONS if side == "channel")
    play = d68["inputs"]["radial_plays_um"]["zero interference"] / 1000.0
    tables = {b: m91.PhiTable(m91.NU_PEEK, b) for b in m91.BASES}
    mu_max = max(s55.MU_SWEEP)
    f_drag = mu_max * s55.F_POGO_N
    rod = m91.Rod(geo, liner)
    offsets_past = [e for e in s55.OFFSETS_UM if e / 1000.0 > play]

    # ── controls ──────────────────────────────────────────────────────────────────────────────────────────────
    banner("Controls")
    ctl = {}
    row68 = next(r for r in d68["offset_static_shipped_branch"] if r["geometry"] == geo.label and r["play"] == "zero interference")
    mine = {e: abs(rigid_points(rod, play, e / 1000.0, 0.0, geo.gap_mm, rod.L)["sigma_signed_MPa"]) for e in s55.OFFSETS_UM}
    worst = max(abs(mine[r["offset_um"]] - r["sigma_root_MPa"]) for r in row68["by_offset"])
    assert worst <= 0.051, f"rigid sharp point model ≠ 68's offset table ({worst:.3f} MPa)"
    ctl["rigid_sharp_vs_68_offset_table"] = {"max_abs_diff_MPa": round(worst, 4), "rows": len(row68["by_offset"])}
    rev68 = [r for r in d68["reversing_drag_on_offset"] if r["geometry"] == geo.label]
    worst_rev = 0.0
    for r in rev68:
        e = r["offset_um"] / 1000.0
        sg = [rigid_points(rod, play, e, f, geo.gap_mm, rod.L)["sigma_signed_MPa"] for f in (0.0, f_drag, -f_drag)]
        mine_r = (abs(sg[0]), max(abs(v) for v in sg[1:]), abs(sg[1] - sg[2]) / 2.0)
        worst_rev = max(worst_rev, *(abs(a - b) for a, b in zip(mine_r, (r["sigma_no_drag_MPa"], r["sigma_peak_under_reversing_drag_MPa"],
                                                                       r["sigma_amplitude_MPa"]), strict=True)))
    assert worst_rev <= 0.051, f"rigid sharp point model ≠ 68's reversing table ({worst_rev:.3f} MPa)"
    ctl["rigid_sharp_vs_68_reversing_table"] = {"max_abs_diff_MPa": round(worst_rev, 4), "rows": len(rev68)}
    print(f"  68's tables reproduced by the rigid sharp point model · {time.time() - t0:.0f} s")
    co = solve(geo, liner, play, 0.0, f_drag, R_EX_MM, tables=tables)
    c91 = next(c for c in d91["cycle"] if c["r_edge_mm"] == R_EX_MM and c["base"] == "bonded" and c["modulus"] == "short-term")
    assert abs(co["sigma_signed_MPa"] - c91["sigma_at_mu_MPa"][f"{mu_max:g}"]) <= 0.002, "no offset: the two-patch solve ≠ 91's exit"
    assert abs(co["rigid"]["sigma_signed_MPa"] - c91["full_drag_rigid_same_edge_MPa"]) <= 0.002, "no offset: rigid same edge ≠ 91's"
    ctl["no_offset_vs_91_exit"] = {"sigma_signed_MPa": [round(co["sigma_signed_MPa"], 3), c91["sigma_at_mu_MPa"][f"{mu_max:g}"]],
                                   "rigid_same_edge_MPa": [round(co["rigid"]["sigma_signed_MPa"], 3), c91["full_drag_rigid_same_edge_MPa"]]}
    print(f"  no offset = 91's exit · {time.time() - t0:.0f} s")
    lim = []
    for f in (0.0, f_drag, -f_drag):
        st = solve(geo, liner, play, 0.05, f, R_IN_REFERENCE_MM, scale=CONTROL_SCALE, tables=tables)
        lim.append((st["sigma_signed_MPa"], st["rigid"]["sigma_signed_MPa"]))
    worst_lim = max(abs(a / b - 1.0) for a, b in lim)
    assert worst_lim <= 2e-3, f"the compliance → 0 limit misses the rigid same-edge model ({worst_lim:.2e})"
    ctl["rigid_limit"] = {"scale": CONTROL_SCALE, "offset_um": 50, "max_rel_diff": float(f"{worst_lim:.2e}")}
    print(f"  rigid limit · {time.time() - t0:.0f} s")

    for k, v in ctl.items():
        print(f"  {k:<36s} {v}")

    # ── (a) static offset × entry radius ────────────────────────────────────────────────────────────────────────
    banner("(a) static offset past the play × entry radius (bonded, short-term; the edge peak refined on two square grids)")
    static = []
    for e in offsets_past:
        for r_in in R_IN_SWEEP_MM:
            st = solve(geo, liner, play, e / 1000.0, 0.0, r_in, refine=REFINE_CELLS_MM, tables=tables)
            ref = st["mouth"]["p_max_MPa_refined"]
            if max(ref.values()) / min(ref.values()) - 1.0 > MAX_SPREAD:     # a third, finer grid where two disagree
                extra = solve(geo, liner, play, e / 1000.0, 0.0, r_in, refine=(REFINE_CELLS_MM[-1] / 2,), tables=tables)
                ref.update(extra["mouth"]["p_max_MPa_refined"])
            rw = {"offset_um": e, "r_in_mm": r_in, **row(st),
                  "sigma_68_rigid_sharp_MPa": next(r["sigma_root_MPa"] for r in row68["by_offset"] if r["offset_um"] == e)}
            static.append(rw)
        print(f"  {e:4d} µm  σ elastic · rigid same edges · p_max mouth (×σ_y) by r_in: " + " | ".join(
            f"{r['r_in_mm']}: {r['sigma_signed_MPa']:.2f} · {r['rigid_same_edges_sigma_signed_MPa']:.2f} · "
            + "/".join(f"{v:.0f}" for v in r["mouth"]["p_max_by_square_cell_MPa"].values())
            + f" (×{r['mouth']['p_max_over_flow']['1.0']:.2f})" for r in static if r["offset_um"] == e))

    # the edge transition is ~√(2·r·δ) ≈ a few µm wide on a long, nearly parallel patch, so on a sharp entry the peak
    # moves with the grid's alignment to it (a third grid is added where two differ by more than MAX_SPREAD); what must
    # NOT move is the VERDICT against the flow pressure — the reported peak is the largest over the grids
    worst = max(r["mouth"]["resolution_spread"] for r in static)
    assert worst <= MAX_SPREAD, f"the mouth peak differs by {worst:.1%} between the two grids — beyond a resolution scatter"
    for r in static:
        vals = list(r["mouth"]["p_max_by_square_cell_MPa"].values())
        r["mouth"]["flow_verdict"] = {f"{c:.1f}": ("above" if min(vals) > c * SIGMA_YIELD_PEEK_PA / 1e6 else
                                                   "below" if max(vals) < c * SIGMA_YIELD_PEEK_PA / 1e6 else "at, within the grids")
                                      for c in s55.CONTACT_CONSTRAINT_FACTORS}
    ctl["mouth_peak_two_grids"] = {"square_cells_mm": list(REFINE_CELLS_MM), "max_spread_allowed": MAX_SPREAD, "worst_spread": worst,
                                   "worst_row": next({"offset_um": r["offset_um"], "r_in_mm": r["r_in_mm"],
                                                      "p_max_by_square_cell_MPa": r["mouth"]["p_max_by_square_cell_MPa"]}
                                                     for r in static if r["mouth"]["resolution_spread"] == worst)}
    print(f"  peak on two grids: worst spread {worst:.1%} ({ctl['mouth_peak_two_grids']['worst_row']}); verdicts against 1·σ_y — "
          + " · ".join(f"{r['offset_um']}/{r['r_in_mm']}: {r['mouth']['flow_verdict']['1.0']}" for r in static
                       if r["mouth"]["flow_verdict"]["1.0"] != "below"))

    # ── (b) the edge peak over the CYCLE: static rows say nothing about the drag ───────────────────────────────────
    banner("(b) the mouth-edge peak over the drag cycle — offset × entry radius, three Zone-3 shanks (the decision quantity)")
    memo = {}
    geos = [geometry_with_shank(sh) if sh != s55.SHANK_LEN_MM else geo for sh in SHANK_SWEEP_MM]
    tasks = [(g, liner, play, e / 1000.0, r_in, f_drag) for g in geos
             for e in (CYCLE_OFFSETS_UM if g is geo else CYCLE_SHANK_OFFSETS_UM) for r_in in R_IN_SWEEP_MM]
    with ProcessPoolExecutor(max_workers=WORKERS) as pool:
        cyc = list(pool.map(_cycle_peak_task, tasks))
        exit_tasks = [(geo, liner, play, e / 1000.0, r_ex, f_drag) for e in EXIT_OFFSETS_UM for r_ex in R_IN_SWEEP_MM]
        exits = list(pool.map(_exit_task, exit_tasks))
        path_tasks = [(geo, liner, play, e / 1000.0, R_IN_REFERENCE_MM, f_drag) for e in ELASTIC_SWING_OFFSETS_UM] + \
                     [(g, liner, play, 0.05, R_IN_REFERENCE_MM, f_drag) for g in geos if g is not geo]
        for t, path in zip(path_tasks, pool.map(_cycle_task, path_tasks), strict=True):
            memo[(t[0].label, round(t[3], 6), t[4])] = path
    if 0.05 not in [e / 1000.0 for e in ELASTIC_SWING_OFFSETS_UM]:
        raise SystemExit("the shank block reads the shipped 50 µm path from the elastic swing block")
    for g in geos:
        for e in (CYCLE_OFFSETS_UM if g is geo else CYCLE_SHANK_OFFSETS_UM):
            print(f"  {g.label[:22]:<22s} {e:4d} µm  cycle peak (static) by r_in: " + " | ".join(
                f"{c['r_in_mm']}: {c['peak_MPa']:.0f} ({c['static_working_grid_MPa'] or 0:.0f}) ×{c['peak_over_flow']['1.0']:.2f}"
                for c in cyc if c["geometry"] == g.label and c["offset_um"] == e))
    print(f"  ({len(tasks)} cycle rows and {len(path_tasks)} elastic paths on {WORKERS} processes · {time.time() - t0:.0f} s)")
    assert max(c["resolution_spread"] for c in cyc) <= MAX_SPREAD, "a cycle peak is unresolved beyond the allowed spread"
    assert max(x["resolution_spread"] for x in exits) <= MAX_SPREAD, "an exit cycle peak is unresolved beyond the allowed spread"
    exit91 = {}
    for x in exits:
        if x["offset_um"] == 0:                    # coaxially the exit IS 91's problem: its full-drag edge peak, same base and modulus
            p91 = next(p_ for p_ in d91["patch"] if p_["r_edge_mm"] == x["r_exit_mm"] and p_["base"] == "bonded"
                       and p_["modulus"] == "short-term")["p_max_MPa"]
            exit91[f"{x['r_exit_mm']:g}"] = [x["peak_MPa"], p91]
    worst91 = max(abs(a / b - 1.0) for a, b in exit91.values())
    assert worst91 <= 0.05, f"coaxially the exit cycle peak strays from 91's edge peak ({worst91:.1%})"
    ctl["exit_coaxial_vs_91"] = {"max_rel_diff": round(worst91, 4), "by_r_exit_mm": exit91}
    banner("(b′) the EXIT-edge peak over the drag cycle — coaxially (91's) and at the tolerance limit, by exit radius")
    for e in EXIT_OFFSETS_UM:
        print(f"  {e:4d} µm  exit cycle peak by r_exit: " + " | ".join(
            f"{x['r_exit_mm']:g}: {x['peak_MPa']:.0f} ×{x['peak_over_flow']['1.0']:.2f}" for x in exits if x["offset_um"] == e))

    # ── (c) the reversing drag: the beam's swing on the rigid same-edge model, dense; the give's correction where cheap
    banner("(c) a reversing drag ±µ·F on a static offset — the root and the wire under each edge, along the path with its kinks")
    swings = [rigid_swing(geo, liner, play, e / 1000.0, R_IN_REFERENCE_MM, f_drag) for e in RIGID_SWING_OFFSETS_UM]
    for sw in swings:
        r68 = next((r for r in rev68 if r["offset_um"] == sw["offset_um"]), None)
        sw["amplitude_68_rigid_sharp_ends_MPa"] = r68["sigma_amplitude_MPa"] if r68 else None
        print(f"  {sw['offset_um']:4d} µm  rigid same edges: root {sw['root_mean_amplitude_MPa'][0]:+.2f} ± {sw['root_mean_amplitude_MPa'][1]:.2f} "
              f"(ends ±{sw['ends_only_amplitude_MPa']:.2f}, 68 {sw['amplitude_68_rigid_sharp_ends_MPa']}) · wire at the mouth edge "
              f"{sw['mouth_section_mean_amplitude_MPa'][0]:+.2f} ± {sw['mouth_section_mean_amplitude_MPa'][1]:.2f} "
              f"(×{sw['mouth_over_root_amplitude']:.2f} the root's) · {sw['points']} points")
    swing_by_radius = [{"offset_um": e, "r_in_mm": r_in, **{k: v for k, v in rigid_swing(geo, liner, play, e / 1000.0, r_in, f_drag).items()
                                                           if k != "offset_um"}}
                       for e in SWING_RADIUS_OFFSETS_UM for r_in in (min(R_IN_SWEEP_MM), max(R_IN_SWEEP_MM))]
    for e in SWING_RADIUS_OFFSETS_UM:
        rr = [w for w in swing_by_radius if w["offset_um"] == e]
        print(f"  {e:4d} µm  the entry radius on the swing (rigid): root " + " → ".join(f"±{w['root_mean_amplitude_MPa'][1]:.2f}" for w in rr)
              + " · wire at the mouth edge " + " → ".join(f"±{w['mouth_section_mean_amplitude_MPa'][1]:.2f}" for w in rr)
              + f" (r_in {min(R_IN_SWEEP_MM):g} → {max(R_IN_SWEEP_MM):g} mm)")
    reversing = []
    for e in ELASTIC_SWING_OFFSETS_UM:
        full = cycle(geo, liner, play, e / 1000.0, R_IN_REFERENCE_MM, f_drag, tables, memo)
        path = [p_ for p_ in full if "not_solved" not in p_]
        sig = [p_["sigma_signed_MPa"] for p_ in path]
        mo = [p_["section_sigma_signed_MPa"]["mouth"] for p_ in path if p_.get("section_sigma_signed_MPa")]
        rs = next(sw for sw in swings if sw["offset_um"] == e)
        reversing.append({"offset_um": e, "path": path, "points": len(path),
                          "not_solved": [p_ for p_ in full if "not_solved" in p_], "sigma_max_MPa": max(sig), "sigma_min_MPa": min(sig),
                          "mean_MPa": swing(sig)[0], "amplitude_MPa": swing(sig)[1],
                          "rigid_same_edges_amplitude_MPa": rs["root_mean_amplitude_MPa"][1],
                          "mouth_section_mean_amplitude_MPa": list(swing(mo)),
                          "rigid_mouth_section_amplitude_MPa": rs["mouth_section_mean_amplitude_MPa"][1]})
        rv = reversing[-1]
        print(f"  {e:4d} µm  elastic: root ±{rv['amplitude_MPa']:.2f} (rigid ±{rv['rigid_same_edges_amplitude_MPa']:.2f}) · wire at the "
              f"mouth edge ±{rv['mouth_section_mean_amplitude_MPa'][1]:.2f} (rigid ±{rv['rigid_mouth_section_amplitude_MPa']:.2f}) · "
              f"{rv['points']} points · {time.time() - t0:.0f} s")

    # ── (d) brackets: base and modulus, at the reference row (the path's ends and the static point) ─────────────────
    banner("(d) brackets — bonded ⊥ frictionless base, short-term ⊥ 20-yr modulus (50 µm, r_in reference; ends and static)")
    brackets = []
    for base in m91.BASES:
        for mod_label, mod in m91.MODULI:
            res = {f"{fr:+g}": row(solve(geo, liner, play, 0.05, fr * f_drag, R_IN_REFERENCE_MM, base=base,
                                         e_peek_mpa=m91.E_PEEK_MPA * mod, tables=tables)) for fr in (-1.0, 0.0, 1.0)}
            sig = [v["sigma_signed_MPa"] for v in res.values()]
            brackets.append({"base": base, "modulus": mod_label, "by_drag": res,
                             "amplitude_ends_MPa": round((max(sig) - min(sig)) / 2, 3),
                             "mouth_p_max_MPa": max(v["mouth"]["p_max_MPa"] for v in res.values() if v.get("mouth"))})
            b = brackets[-1]
            print(f"  {base:<12s} {mod_label:<13s} static {res['+0']['sigma_signed_MPa']:.2f} · swing of the ends {b['amplitude_ends_MPa']:.2f} "
                  f"· mouth p_max {b['mouth_p_max_MPa']:.0f} MPa")

    # ── (e) the mouth station moves with the Zone-3 shank: the static price and the cycle at 50 µm ───────────────────
    banner("(e) Zone-3 shank length (the mouth station) — 50 µm, r_in reference, read along the path")
    shank = []
    for g in geos:
        full = cycle(g, liner, play, 0.05, R_IN_REFERENCE_MM, f_drag, tables, memo)
        path = [p_ for p_ in full if "not_solved" not in p_]
        sig = [p_["sigma_signed_MPa"] for p_ in path]
        mo = [p_["section_sigma_signed_MPa"]["mouth"] for p_ in path if p_.get("section_sigma_signed_MPa")]
        static_row = next(p_ for p_ in path if p_["drag_N"] == 0.0)
        shank.append({"shank_mm": next(sh for sh, gg in zip(SHANK_SWEEP_MM, geos, strict=True) if gg is g), "mouth_station_mm": g.gap_mm,
                      "static_sigma_MPa": static_row["sigma_signed_MPa"], "root_mean_amplitude_MPa": list(swing(sig)),
                      "mouth_section_mean_amplitude_MPa": list(swing(mo)), "points": len(path),
                      "not_solved": [p_ for p_ in full if "not_solved" in p_]})
        z = shank[-1]
        print(f"  shank {z['shank_mm']:4.1f} mm (mouth at {g.gap_mm:.0f} mm): static {z['static_sigma_MPa']:.2f} · root "
              f"±{z['root_mean_amplitude_MPa'][1]:.2f} · wire at the mouth edge ±{z['mouth_section_mean_amplitude_MPa'][1]:.2f}")

    try:
        summary = summarise(static, cyc, swings, reversing, brackets, shank, ctl, exits, swing_by_radius, d86)
    except Exception as err:          # the rows took an hour: keep them, and re-derive the summary with --resummarise
        summary = {"text": f"(summary failed: {err!r}) — rows kept; run --resummarise after the fix"}
        print(f"  ⚠️ summary failed: {err!r}")
    print("\n  → " + summary["text"])
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps({
        "question": "under a channel-axis offset past the radial play, what does the mouth edge do to the PEEK liner and to "
                    "the root of the bus rod, with the layer's give and a reversing drag?",
        "inputs": {"geometry": geo.label, "gap_mm": geo.gap_mm, "pad_mm": geo.pad_mm, "liner_from_mm": geo.liner_from_mm,
                   "radial_play_um": round(play * 1000.0, 3), "drag_N": f_drag, "mu": mu_max,
                   "offsets_static_um": offsets_past, "offsets_rigid_swing_um": list(RIGID_SWING_OFFSETS_UM),
                   "offsets_elastic_swing_um": list(ELASTIC_SWING_OFFSETS_UM), "offsets_cycle_um": list(CYCLE_OFFSETS_UM),
                   "cycle_shank_offsets_um": list(CYCLE_SHANK_OFFSETS_UM), "path_scan": PATH_SCAN, "transition_side": TRANSITION_SIDE,
                   "r_in_sweep_mm": list(R_IN_SWEEP_MM), "r_in_reference_mm": R_IN_REFERENCE_MM, "r_exit_mm": R_EX_MM,
                   "drag_path_fraction": list(DRAG_PATH), "shank_sweep_mm": list(SHANK_SWEEP_MM),
                   "sigma_yield_PEEK_MPa_tensile_23C": SIGMA_YIELD_PEEK_PA / 1e6,
                   "flow_constraint_factors_55": list(s55.CONTACT_CONSTRAINT_FACTORS),
                   "kernels": "91 (layer Φ(kh), Love half-space, DC-FFT); rod: 91's Mohr flexibility of 55's EI"},
        "controls": ctl, "static": static, "cycle_peak": cyc, "exit_cycle_peak": exits, "rigid_swing": swings,
        "swing_by_entry_radius": swing_by_radius, "reversing": reversing, "brackets": brackets,
        "shank": shank,
        "summary": summary,
        "not_modelled": {"plasticity": "linear elastic; a peak above the flow pressure is flagged, never redistributed",
                         "friction_pad_couple_wear": "no friction at either patch, no pad couple, no wear",
                         "play": "zero-interference play only",
                         "wire": "rigid in the contact kernel — the wire's notch factor under either edge is not computed; "
                                 "the nominal fibre stress at both edge sections is reported",
                         "near_the_play": "within a few µm of the play, under the drag toward the wall the offset brings in, the rod "
                                         "nears a line contact along the channel that two end windows cannot represent; there the "
                                         "beam's swing is read on the rigid same-edge model and the elastic edge peak only statically",
                         "offset": "swept, never measured"},
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"  cache → {OUT_JSON.relative_to(CACHE_DIR.parent.parent.parent)} · {time.time() - t0:.0f} s")
    return 1 if summary["text"].startswith("(summary failed") else 0


if __name__ == "__main__":
    raise SystemExit(main())
