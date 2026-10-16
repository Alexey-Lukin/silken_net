#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""97 — the bus WIRE under the liner's edges: the contact pressure of the mouth and exit patches carried through the PEEK
layer onto the Ti surface, added to the wire's nominal bending — does any section under an edge out-rank the welded root?

WHY. 91 and 92 solve the liner's contact with the Ti channel with the wire RIGID (their MODEL: the pressure acts between
the liner's OUTER face and the channel edge; the wire, bonded or frictionless under 0.15 mm of PEEK, takes it only
through the layer), so at the sections under the edges they give the wire's NOMINAL fibre stress alone. The leg (00_07
HW.34, the wire under the liner's edges — narrowed by this script to the liner's end on the wire) asked for the rest: the layer's own transmission of that pressure onto
the wire. The scale says why it matters: the nominal amplitude of the wire there is a few MPa, while the pressure on the
layer's top under the edge runs to 100–170 MPa (92). in-silico §When Modifying #41 — the BODIES: this script's pressure
is 92's, between liner and channel; its new term is what that pressure does to the OTHER face of the layer, the wire.

MODEL. (1) The layer: plane-strain Navier per Fourier mode (91's state matrix, which depends on ν alone), PEEK on an
ELASTIC Ti half-space — the three-layer core the leg names — BONDED (u, w, τ, σ continuous) or FRICTIONLESS (w, σ
continuous, τ = 0 on both faces), the bracket of 91; a normal load p·cos(kx) on the free top, no shear there (91's top).
6 unknowns (the layer's surface state, the substrate's two decaying solutions), 6 conditions; out come the Ti-side
stresses at the interface, T_kk (in-plane along k), T_tt = ν(T_kk + T_zz) (plane strain), T_zz, T_xz, as multiples of p.
(2) 3-D from the modes (one mode = one plane-strain problem along k̂ — 91's own assertion, exact for isotropic layers):
σ_ss = T_kk k̂s² + T_tt k̂y², σ_yy = T_kk k̂y² + T_tt k̂s², σ_zz = T_zz, on a zero-padded FFT of 92's pressure field
(its window grid, 2 × 5 µm), the layer flat. (3) Two physical FACES per station, −v and +v: on each path point the
contact field goes to the face toward the wall (92's window side `window_sign`, which 92 recomputes per point — at the
exit it flips with the drag, so a window cell is NOT one surface point), and each face carries the beam's nominal fibre
stress −face·σ_signed (92's section moment at every x, linear beyond the window where no load acts) × cos φ round the tube.
(4) Per physical surface point over 92's drag path: amplitude and mean; 86's Soderberg load line, 1/SF = σ_a/(k·σ_e) +
σ_m⁺/σ_y — the welded ROOT carries the seam knock-down k (an input of the vendor, 00_07 HW.34), a section under an edge is
drawn wire (55's endurance, derate 1.0); so the root keeps the lower SF while k < k_x = σ_a,root/D, D = σ_a + (σ_m⁺ −
σ_m,root)·σ_e/σ_y, and at every k when D ≤ 0. The station is the sections under the path's patches ± 2h (the edge
section when no point touches) and, round the tube, each face's own half (|φ| ≤ π/2) — never the padding. (5) The liner's lower END — the leg's named subject — is read, not
modelled: the bare side's nominal per face; the row keeps the factor its corner would need to tie the mouth's worst
point, the summary the one that would tie the governing modelled section at each k.

CONTROLS asserted in-run: the kernel at kh → 0 (σ_kk = σ_zz = −p, τ = 0); the homogeneous half-space (layer = substrate)
against the closed form at depth ζ = kh (σ_zz = −(1+ζ)e^{−ζ}, σ_xx = −(1−ζ)e^{−ζ}, |τ| = ζe^{−ζ}); frictionless: σ_kk ≡ σ_zz
(a shear-free half-space surface); the rigid-substrate limit against 91's Φ(kh) through its own top-displacement
normalisation; the cut KH_MAX (|T| there below KH_TAIL); per field: two paddings agree (the force under the Ti surface is
NOT a control — Σσ_zz is p's sum times T_zz(0), the kh → 0 entry, whatever the field); per contact point: the nominal at
the patch centroid equals 92's `section_sigma_signed_MPa`; 92's exported window side agrees with the rod's displacement
toward the wall at the patch (> ½ play) — 92's own sign, it does NOT test this script's face assembly (checked by hand
2026-10-16: the +v face's fibre stress is −E·c·v″, and 92's E·c·v″ = σ_signed is the next control); 92's own consistency
(E·c·v″ of its pose = its σ_signed).

⛔ DECLARED CEILINGS: the wire is a HALF-SPACE, not a Ø1.0 cylinder — the transmitted traction spreads over ~0.3 mm, of
the order of the radius 0.5 mm; the layer is flat (91's ceiling, t/R ≈ 0.23) and its arc is measured on R_OD, while the
wire's arc under it is 0.5/0.65 of that, so the real traction is ≈ ×1.3 more concentrated round the wire — the contact
term is UNDER-stated by up to that; 92's pressure was solved with the wire rigid (E ratio ≈ 27), one-way coupled; ONE
geometry (the shipped shank, 92's sweep moves the root's required k with the shank), zero interference, the baseline
alloy's E and σ_y (the bus alloy is HW.24's bake-off; 86 binds on Ta, whose σ_e is far lower — the SF here does not carry
over); the pad COUPLE (pogo off the axis, 68 (d) · 91 `pad_couple`) is not in 92's path, so the exit under eccentricity
is not here; the 20-year relaxed modulus is not run; the liner's END is not modelled as a corner (5); the exit patch sits
≈ 0.2 mm from the rod's end face, where σ_ss must vanish and the half-space does not know it (overstated there); the
contact increment is mostly COMPRESSIVE (the tension it puts beside a patch is measured pointwise, per base) and the
mean-clipped load line credits none of the compression; LINEAR elasticity, no friction on the layer's top (91's), no thermal term, no wire↔liner micro-slip; the seam's own
stress field (bead, toe, residual tension — which raises the root's mean and so k_x) — 00_07 HW.34's 🌿 leg; σ_ss alone
is read (the bonded interface's shear on the Ti, and a multiaxial amplitude at a patch edge, are not); the offsets are a
5 µm grid and k_x and the liner-end factor are minima of curves that are not monotone in the offset — between grid
points they can sit lower.

Run:  conda activate silken_md
      python tools/in_silico/scripts/97_wire_under_liner_edges.py           # ≈ 1 h on 2 workers
      python tools/in_silico/scripts/97_wire_under_liner_edges.py --summary-only   # the verdict re-derived from the rows
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
from scipy.linalg import expm, null_space

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import ALLOY_BASELINE, ALLOY_PROPERTIES, CACHE_DIR, E_PEEK_PA, NU_PEEK
from lib.utils import banner

SI_DESCRIPTION = ("The bus wire under the liner's edges: the mouth and exit contact pressure carried through the PEEK layer onto "
                  "the Ti surface (layer on an elastic half-space), added to the wire's nominal bending along the drag cycle, "
                  "and the weld knockdown below which the welded root stays the critical section")

_spec = importlib.util.spec_from_file_location("liner92", HERE / "92_liner_mouth_contact.py")
m92 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m92)
m91, s55 = m92.m91, m92.s55

OUT_JSON = CACHE_DIR / "mechanical" / "wire_under_liner_edges.json"
E_TI_MPA = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3
NU_TI = ALLOY_PROPERTIES[ALLOY_BASELINE]["nu"]
YIELD_TI_MPA = ALLOY_PROPERTIES[ALLOY_BASELINE]["yield_MPa"]
E_PEEK_MPA = E_PEEK_PA / 1e6
H_MM = m91.T_LINER_MM
R_WIRE_MM = s55.D_BUS / 2.0
ARC_CONCENTRATION = m91.R_OD_MM / R_WIRE_MM   # the ceiling's ×1.3: the traction's arc is measured on R_OD, the wire's is R_WIRE
KH_MAX = 15.0            # above it the 6×6 system loses its digits (e^{kh}); there |T| < KH_TAIL — the physical limit is 0
KH_TAIL = 1e-4
PADS_MM = (1.0, 2.0)     # zero padding of the field: the transmitted traction decays over ~h, asserted on two paddings
OFFSETS_UM = (0, 30, 35, 40, 45, 50, 75, 100)   # coaxial · the band inside ⌀0.10 where 92's mouth/root ratio peaks · its limit · beyond
K_READINGS = (0.388, 1.0)   # 86's threshold on Ta at ⌀0.10 (a different path, so a reading, not a comparison) · a perfect seam
BASES = m91.BASES
WORKERS = 2


# ── the kernel: PEEK layer on an elastic Ti half-space ────────────────────────────────────────────────────────────
def _lame(e: float, nu: float) -> tuple[float, float]:
    return e * nu / ((1 + nu) * (1 - 2 * nu)), e / (2 * (1 + nu))


def _navier(nu: float) -> np.ndarray:
    lam, mu = _lame(1.0, nu)
    l2 = lam + 2 * mu
    return np.array([[0, 1, 0, 0], [l2 / mu, 0, 0, (lam + mu) / mu], [0, 0, 0, 1], [0, -(lam + mu) / l2, mu / l2, 0]], float)


def _solve_mode(kh: float, nu_l: float, nu_s: float, e_ratio: float, base: str) -> tuple[np.ndarray, np.ndarray, tuple]:
    """The 6×6 system of one mode (layer E = 1, k = 1, p = 1; state [U, U', W, W'] as 91): (y0, y_sub, Lamé of the substrate)."""
    lam_l, mu_l = _lame(1.0, nu_l)
    lam_s, mu_s = _lame(e_ratio, nu_s)
    p = expm(_navier(nu_l) * kh)
    v = null_space(np.linalg.matrix_power(_navier(nu_s) + np.eye(4), 2))     # the substrate's decaying solutions
    def szz(lam, mu): return np.array([lam, 0, 0, lam + 2 * mu])
    def tau(mu): return mu * np.array([0, 1, -1, 0])
    a, b = np.zeros((6, 6)), np.zeros(6)
    a[0, :4] = [0, 1, -1, 0]                                                   # τ(0) = 0
    a[1, :4], b[1] = szz(lam_l, mu_l), -1.0                                   # σ_zz(0) = −p
    if base == "bonded":
        a[2, :4], a[2, 4:] = p[0], -v[0]
        a[3, :4], a[3, 4:] = p[2], -v[2]
        a[4, :4], a[4, 4:] = tau(mu_l) @ p, -(tau(mu_s) @ v)
        a[5, :4], a[5, 4:] = szz(lam_l, mu_l) @ p, -(szz(lam_s, mu_s) @ v)
    else:
        a[2, :4], a[2, 4:] = p[2], -v[2]
        a[3, :4], a[3, 4:] = szz(lam_l, mu_l) @ p, -(szz(lam_s, mu_s) @ v)
        a[4, :4] = tau(mu_l) @ p
        a[5, 4:] = tau(mu_s) @ v
    x = np.linalg.solve(a, b)
    return x[:4], v @ x[4:], (lam_s, mu_s)


def transfer(kh: float, base: str, nu_l: float = NU_PEEK, nu_s: float = NU_TI, e_ratio: float = E_TI_MPA / E_PEEK_MPA) -> tuple:
    """(T_kk, T_tt, T_zz, T_xz): the Ti-side stresses at the interface per unit top pressure, plane strain along k."""
    _, ys, (lam_s, mu_s) = _solve_mode(kh, nu_l, nu_s, e_ratio, base)
    t_zz = float(np.array([lam_s, 0, 0, lam_s + 2 * mu_s]) @ ys)
    t_kk = float(np.array([lam_s + 2 * mu_s, 0, 0, lam_s]) @ ys)
    return t_kk, nu_s * (t_kk + t_zz), t_zz, float(mu_s * np.array([0, 1, -1, 0]) @ ys)


class TransferTable:
    def __init__(self, base: str):
        self.base = base
        self.kh = np.logspace(-5, np.log10(KH_MAX), 1500)
        self.t = np.array([transfer(v, base) for v in self.kh])

    def __call__(self, kh: np.ndarray) -> list:
        lk = np.log(np.maximum(kh, 1e-300))
        return [np.where(kh > KH_MAX, 0.0, np.interp(lk, np.log(self.kh), self.t[:, i])) for i in range(4)]


def kernel_controls() -> dict:
    out = {}
    worst = max(max(abs(t[0] + 1.0), abs(t[2] + 1.0), abs(t[3])) for t in (transfer(1e-7, base) for base in BASES))
    assert worst < 1e-5, f"kh → 0 is not the bare half-space (σ_kk = σ_zz = −p, τ = 0; {worst:.2e})"
    out["kh_to_zero_max_abs"] = float(f"{worst:.2e}")
    worst = max(abs(t[0] - t[2]) for t in (transfer(kh, "frictionless") for kh in (0.05, 0.5, 1.0, 3.0, 8.0)))
    assert worst < 1e-8, f"frictionless: a shear-free half-space surface must carry σ_kk = σ_zz ({worst:.2e})"
    out["frictionless_kk_equals_zz_max_abs"] = float(f"{worst:.2e}")
    worst = 0.0
    for z in (0.1, 0.5, 1.0, 2.0, 5.0):
        kk, _, zz, xz = transfer(z, "bonded", nu_l=NU_TI, nu_s=NU_TI, e_ratio=1.0)
        worst = max(worst, abs(zz + (1 + z) * np.exp(-z)), abs(kk + (1 - z) * np.exp(-z)), abs(abs(xz) - z * np.exp(-z)))
    assert worst < 1e-8, f"the homogeneous half-space misses its closed form ({worst:.2e})"
    out["homogeneous_closed_form_max_abs"] = float(f"{worst:.2e}")
    worst = 0.0
    for base in BASES:
        for kh in (0.05, 0.3, 1.0, 3.0, 10.0):
            y0, _, _ = _solve_mode(kh, NU_PEEK, NU_TI, 1e7, base)
            worst = max(worst, abs(y0[2] / (2 * (1 - NU_PEEK ** 2)) / m91.phi_direct(kh, NU_PEEK, base) - 1.0))
    assert worst < 1e-4, f"the rigid-substrate limit misses 91's Φ ({worst:.2e})"
    out["rigid_substrate_vs_91_phi_max_rel"] = float(f"{worst:.2e}")
    tail = max(abs(v) for base in BASES for v in transfer(KH_MAX, base))
    assert tail < KH_TAIL, f"|T| at the cut kh = {KH_MAX} is {tail:.1e} — the cut drops load"
    out["tail_at_kh_max"] = float(f"{tail:.1e}")
    return out


# ── one field → the Ti surface ────────────────────────────────────────────────────────────────────────────────────
def synth(fl: dict, table: TransferTable, pad_mm: float) -> dict:
    """σ_ss, σ_yy, σ_zz at the Ti surface on the padded grid, with its s and y axes."""
    p, ds, dy = fl["p_MPa"], fl["ds_mm"], fl["dy_mm"]
    ns, ny = p.shape
    i0, j0 = round(pad_mm / ds), round(pad_mm / dy)
    big = np.zeros((ns + 2 * i0, ny + 2 * j0))
    big[i0:i0 + ns, j0:j0 + ny] = p
    ks = 2 * np.pi * np.fft.fftfreq(big.shape[0], ds)
    ky = 2 * np.pi * np.fft.fftfreq(big.shape[1], dy)
    kss, kyy = np.meshgrid(ks, ky, indexing="ij")
    k = np.hypot(kss, kyy)
    t_kk, t_tt, t_zz, _ = table(k * H_MM)
    with np.errstate(invalid="ignore", divide="ignore"):
        cs2 = np.where(k > 0, (kss / np.where(k > 0, k, 1.0)) ** 2, 0.5)
    spec = np.fft.fft2(big)
    s_axis = fl["s_mm"][0] + (np.arange(big.shape[0]) - i0) * ds
    y_axis = fl["y_mm"][0] + (np.arange(big.shape[1]) - j0) * dy
    return {"s_mm": s_axis, "y_mm": y_axis,
            "ss": np.real(np.fft.ifft2(spec * (t_kk * cs2 + t_tt * (1 - cs2)))),
            "yy": np.real(np.fft.ifft2(spec * (t_kk * (1 - cs2) + t_tt * cs2))),
            "zz": np.real(np.fft.ifft2(spec * t_zz))}


def embed(fl: dict, ns: int, ny: int) -> dict:
    """The point's pressure on the path's LARGEST window — 92 grows a window by doubling its s length and y span about the
    same start and centre line, on the same cells, and accepts it only once the patch lies inside, so p = 0 beyond: exact."""
    p = fl["p_MPa"]
    n0, m0 = p.shape
    j0 = (ny - m0) // 2
    y = (np.arange(ny) - (ny - 1) / 2.0) * fl["dy_mm"]
    assert n0 <= ns and np.allclose(y[j0:j0 + m0], fl["y_mm"]), "the windows' cells do not nest"
    big = np.zeros((ns, ny))
    big[:n0, j0:j0 + m0] = p
    return {**fl, "p_MPa": big, "s_mm": fl["s_mm"][0] + np.arange(ns) * fl["ds_mm"], "y_mm": y}


def nominal_along(fl: dict, s_ax: np.ndarray) -> np.ndarray:
    """92's signed nominal fibre stress on the padded s axis — linear in x beyond the window, where no load acts."""
    s, sig = fl["s_mm"], fl["sigma_nominal_signed_MPa"]
    lo, hi = np.polyfit(s[:3], sig[:3], 1), np.polyfit(s[-3:], sig[-3:], 1)
    out = np.interp(s_ax, s, sig)
    return np.where(s_ax < s[0], np.polyval(lo, s_ax), np.where(s_ax > s[-1], np.polyval(hi, s_ax), out))


def sf86(amp, mean, sigma_e: float, k: float = 1.0):
    """86's Soderberg load line: 1/SF = σ_a/(k·σ_e) + σ_m/σ_y, a compressive mean not credited."""
    return 1.0 / (np.asarray(amp) / (k * sigma_e) + np.maximum(np.asarray(mean), 0.0) / YIELD_TI_MPA)


def k_crossover(root_amp: float, root_mean: float, amp: float, mean: float, sigma_e: float) -> float | None:
    """The seam knock-down below which the welded root keeps the lower SF (86's form): k_x = σ_a,root / D,
    D = σ_a + (σ_m⁺ − σ_m,root)·σ_e/σ_y; None when D ≤ 0 — the root is critical at every k."""
    d = amp + (max(mean, 0.0) - root_mean) * sigma_e / YIELD_TI_MPA
    return float(root_amp / d) if d > 0 else None


def _point(args) -> dict:
    geo, liner, play, off, d, base, tables_pk = args
    try:
        return {"drag_N": d, "st": m92.solve(geo, liner, play, off, d, m92.R_IN_REFERENCE_MM, base=base, tables=tables_pk,
                                              with_field=True)}
    except RuntimeError as err:   # 92's own refusal (a patch the two windows cannot hold) — recorded, never dropped
        return {"drag_N": d, "not_solved": str(err)[:160]}


def station_cycle(points: list, name: str, table: TransferTable, geo, rod, off: float, play: float, sigma_e: float,
                  root_amp: float, root_mean: float) -> dict:
    """Both FACES of one station over the path: on each point the contact goes to the face toward the wall (side
    window_sign), the nominal −face·σ_signed to each face; amplitude and mean per physical surface point."""
    ctl = {"max_padding_diff_MPa": 0.0, "max_centroid_nominal_diff_MPa": 0.0,
           "min_rod_toward_wall_over_play": np.inf, "internal_92_Ecv2_minus_sigma_MPa": 0.0, "internal_92_scale_MPa": 0.0}
    grid = None
    stacks = {f: {"tot": [], "nom": [], "con": []} for f in (-1, +1)}
    patch_s = []
    ns, ny = (max(pt["st"]["fields"][name]["p_MPa"].shape[i] for pt in points) for i in (0, 1))
    for pt in points:
        st, fl = pt["st"], pt["st"]["fields"][name]
        fe = embed(fl, ns, ny)   # one grid along the path — 92 may have grown this point's window
        ti = synth(fe, table, PADS_MM[0])
        if grid is None:
            grid = (ti["s_mm"], ti["y_mm"])
        assert np.allclose(ti["s_mm"], grid[0]) and np.allclose(ti["y_mm"], grid[1]), "the window moved along the path"
        sg = fl["window_sign"]
        if fl["p_MPa"].any():
            ti2 = synth(fe, table, PADS_MM[1])
            ctl["max_padding_diff_MPa"] = max(ctl["max_padding_diff_MPa"], *(abs(ti[c].max() - ti2[c].max()) + abs(ti[c].min() - ti2[c].min())
                                                                              for c in ("ss", "zz")))
            q = (fl["p_MPa"] * np.cos(fl["y_mm"] / m91.R_OD_MM)[None, :]).sum(axis=1)
            o = np.argsort(fl["x_mm"])
            xs = float((q * fl["x_mm"]).sum() / q.sum())
            ctl["max_centroid_nominal_diff_MPa"] = max(ctl["max_centroid_nominal_diff_MPa"],
                                                       abs(float(np.interp(xs, fl["x_mm"][o], fl["sigma_nominal_signed_MPa"][o]))
                                                           - st["section_sigma_signed_MPa"][name]))
            # 92's exported window side against its rod's displacement at the patch — 92's own sign, not this script's faces
            ctl["min_rod_toward_wall_over_play"] = min(ctl["min_rod_toward_wall_over_play"],
                                                       float(sg * (np.interp(xs, fl["x_mm"][o], fl["pose_mm"][o]) - off) / play))
            ii = np.nonzero(fl["p_MPa"].any(axis=1))[0]
            patch_s.append((float(fl["s_mm"][ii.min()]), float(fl["s_mm"][ii.max()])))
        o = np.argsort(fl["x_mm"])
        v2 = np.gradient(np.gradient(fl["pose_mm"][o], fl["x_mm"][o]), fl["x_mm"][o])[5:-5]
        ctl["internal_92_Ecv2_minus_sigma_MPa"] = max(ctl["internal_92_Ecv2_minus_sigma_MPa"],
                                                      float(np.abs(E_TI_MPA * R_WIRE_MM * v2 - fl["sigma_nominal_signed_MPa"][o][5:-5]).max()))
        ctl["internal_92_scale_MPa"] = max(ctl["internal_92_scale_MPa"], float(np.abs(fl["sigma_nominal_signed_MPa"]).max()))
        nom = nominal_along(fl, ti["s_mm"])[:, None] * np.cos(ti["y_mm"] / m91.R_OD_MM)[None, :]
        for f in (-1, +1):
            fibre = -f * nom
            stacks[f]["nom"].append(fibre)
            con = ti["ss"] if f == sg else np.zeros_like(fibre)
            stacks[f]["con"].append(con)
            stacks[f]["tot"].append(fibre + con)
    # the station: the sections under the patches the path makes (± 2h), or the edge section when no point touches
    s_ax = grid[0]
    fl0 = points[0]["st"]["fields"][name]
    ds_dx = (fl0["s_mm"][1] - fl0["s_mm"][0]) / (fl0["x_mm"][1] - fl0["x_mm"][0])
    s_ends = sorted(fl0["s_mm"][0] + (x - fl0["x_mm"][0]) * ds_dx for x in (geo.liner_from_mm, rod.L))
    lo, hi = (min(a for a, _ in patch_s), max(b for _, b in patch_s)) if patch_s else (fl0["s_mm"][0], fl0["s_mm"][0])
    keep = (s_ax >= max(lo - 2 * H_MM, s_ends[0])) & (s_ax <= min(hi + 2 * H_MM, s_ends[1]))
    half = np.abs(grid[1]) <= 0.5 * np.pi * m91.R_OD_MM      # each face's own half round the tube — never the padding
    faces = {}
    for f in (-1, +1):
        tot, nomv, con = (np.array(stacks[f][c])[:, keep][:, :, half] for c in ("tot", "nom", "con"))
        amp, mean = (tot.max(0) - tot.min(0)) / 2, (tot.max(0) + tot.min(0)) / 2
        amp_n, mean_n = (nomv.max(0) - nomv.min(0)) / 2, (nomv.max(0) + nomv.min(0)) / 2
        inv, inv_n = 1 / sf86(amp, mean, sigma_e), 1 / sf86(amp_n, mean_n, sigma_e)
        i = np.unravel_index(int(np.argmax(inv)), inv.shape)
        faces["minus" if f < 0 else "plus"] = {
            "sf_drawn_wire": float(1 / inv[i]), "amplitude_MPa": float(amp[i]), "mean_MPa": float(mean[i]),
            "sf_nominal_only": float(1 / inv_n.max()), "contact_factor_on_1_over_sf": float(inv[i] / inv_n.max()),
            "max_tension_MPa": float(tot.max()), "max_tension_nominal_only_MPa": float(nomv.max()),
            "max_contact_tension_MPa": float(con.max()),
            "k_crossover": k_crossover(root_amp, root_mean, float(amp[i]), float(mean[i]), sigma_e)}
    worst = min(faces, key=lambda k: faces[k]["sf_drawn_wire"])
    return {"station_s_mm": [float(max(lo - 2 * H_MM, s_ends[0])), float(min(hi + 2 * H_MM, s_ends[1]))],
            "contact_points": len(patch_s), "faces": faces, "worst_face": worst, "controls": ctl}


def liner_end(points: list, geo, liner, sigma_e: float) -> dict:
    """The liner's lower end on the wire — the leg's named subject, NOT modelled as a corner: the BARE side's nominal
    (moment linear from the mouth window down to it: no load between) per face, and the amplitude factor its corner
    would need to tie the mouth's worst point; the corner itself is an open sub-leg."""
    ei = s55.member_ei_at(geo, liner, True)
    jump = ei(geo.liner_from_mm) / ei(geo.liner_from_mm - 1e-9)          # EI composite / bare
    vals = []
    for pt in points:
        fl = pt["st"]["fields"]["mouth"]
        o = np.argsort(fl["x_mm"])
        a = np.polyfit(fl["x_mm"][o][:3], fl["sigma_nominal_signed_MPa"][o][:3], 1)
        vals.append(float(np.polyval(a, geo.liner_from_mm)) * jump)       # same moment, bare section
    v = np.array(vals)
    out = {}
    for f in (-1, +1):
        fib = -f * v
        out["minus" if f < 0 else "plus"] = {"amplitude_MPa": float((fib.max() - fib.min()) / 2), "mean_MPa": float((fib.max() + fib.min()) / 2),
                                            "sf_nominal_only": float(sf86((fib.max() - fib.min()) / 2, (fib.max() + fib.min()) / 2, sigma_e))}
    out["ei_jump_composite_over_bare"] = float(jump)
    return out


def run_offset(geo, liner, play, off_um: int, f: float, base: str, tables_pk: dict, table: TransferTable, pool, sigma_e: float) -> dict:
    rod = m91.Rod(geo, liner)
    off = off_um / 1000.0
    path = m92.drag_path(rod, play, off, geo.gap_mm + m92.R_IN_REFERENCE_MM, rod.L - m92.R_EX_MM, f)
    got = list(pool.map(_point, [(geo, liner, play, off, d, base, tables_pk) for d in path]))
    points = [p for p in got if "st" in p]
    root = np.array([p["st"]["sigma_signed_MPa"] for p in points])
    r_amp, r_mean = float((root.max() - root.min()) / 2), float(abs((root.max() + root.min()) / 2))
    out = {"offset_um": off_um, "base": base, "path_points": len(path),
           "not_solved": [{"drag_N": p["drag_N"], "reason": p["not_solved"]} for p in got if "st" not in p],
           "root": {"amplitude_MPa": r_amp, "mean_abs_MPa": r_mean,
                    "sf_at_k": {f"{k:g}": float(sf86(r_amp, r_mean, sigma_e, k)) for k in K_READINGS}}}
    for name in ("mouth", "exit"):
        out[name] = station_cycle(points, name, table, geo, rod, off, play, sigma_e, r_amp, r_mean)
    out["liner_end"] = liner_end(points, geo, liner, sigma_e)
    worst_mouth = min(v["sf_drawn_wire"] for v in out["mouth"]["faces"].values())
    worst_end = min(v["sf_nominal_only"] for v in out["liner_end"].values() if isinstance(v, dict))
    out["liner_end"]["corner_factor_to_tie_mouth"] = float(worst_end / worst_mouth)   # on 1/SF, approximately on amplitude
    return out


def _down(x: float) -> float:
    """A threshold quoted as «every k < X» or «more than ×X»: rounded DOWN, so the sentence never claims past the row."""
    return math.floor(x * 100) / 100


def summarise(rows: list, drag_n: float, sigma_e: float) -> dict:
    """The verdict from the rows alone (`--summary-only` re-derives it on a written cache, no solve): per base, the lowest
    k_x over both stations and both faces inside ⌀0.10 (offsets ≤ 92's TOLERANCE_OFFSET_UM) and beyond it — the welded
    root stays the critical section for every seam knock-down k below it (k_x > 1: even a perfect seam); a k_x of None
    (D ≤ 0) is a section the root out-ranks at every k, so it never sets the lowest. Thresholds are quoted rounded down."""
    tol = m92.TOLERANCE_OFFSET_UM
    out, lines = {"tolerance_offset_um": tol, "by_base": {}}, []
    for base in BASES:
        rs = [r for r in rows if r["base"] == base]
        cand = [(f["k_crossover"], r["offset_um"], st, fn, f["sf_drawn_wire"], f["contact_factor_on_1_over_sf"], f["mean_MPa"],
                 f["amplitude_MPa"], f["sf_nominal_only"], r["root"]["amplitude_MPa"], r["root"]["mean_abs_MPa"])
                for r in rs for st in ("mouth", "exit") for fn, f in r[st]["faces"].items() if f["k_crossover"] is not None]

        def lowest(cs):
            if not cs:
                return None
            k, off, st, fn, sf, cf, mean, amp, sf_n, ra, rm = min(cs)
            row = {"k_crossover": k, "offset_um": off, "station": st, "face": fn, "sf_drawn_wire": sf, "contact_factor_on_1_over_sf": cf,
                   "mean_MPa": mean}
            if mean < 0:   # the arc ceiling (×1.3 on the contact's share of the amplitude, the two shares taken as ADDITIVE — out of
                # phase the swing grows faster) — the nominal share at the point is not kept, only its bound over the face
                # (σ_e/SF_nominal), so a bracket; a compressive mean stays clipped to 0
                amp_n = sigma_e / sf_n
                row["k_crossover_contact_x1_3"] = sorted(ra / (a - rm * sigma_e / YIELD_TI_MPA)
                                                         for a in (ARC_CONCENTRATION * amp, amp_n + ARC_CONCENTRATION * (amp - amp_n)))
            return row
        inside, beyond = lowest([c for c in cand if c[1] <= tol]), lowest([c for c in cand if c[1] > tol])
        at_tol = next(r for r in rs if r["offset_um"] == tol)

        def out_rank(k, rs=rs):   # the factor the liner end's corner needs on its bare nominal to tie the governing modelled section
            fs = [(min(v["sf_nominal_only"] for v in r["liner_end"].values() if isinstance(v, dict))
                   / min(r["root"]["sf_at_k"][k], *(f["sf_drawn_wire"] for st in ("mouth", "exit") for f in r[st]["faces"].values())),
                   r["offset_um"]) for r in rs if r["offset_um"] <= tol]
            f, off = min(fs)
            return {"factor": f, "offset_um": off}
        ends = {k: out_rank(k) for k in at_tol["root"]["sf_at_k"]}
        jump = at_tol["liner_end"]["ei_jump_composite_over_bare"]
        refused = [{"offset_um": r["offset_um"], **ns} for r in rs for ns in r["not_solved"]]
        # the tension the contact alone puts on the wire beside a patch, pointwise — it may be NEGATIVE on a face whose every
        # path point touches (the contact then compresses the whole station there): no zero sample is guaranteed
        t_val, t_off, t_st, t_fn = max((f["max_contact_tension_MPa"], r["offset_um"], st, fn)
                                       for r in rs for st in ("mouth", "exit") for fn, f in r[st]["faces"].items())
        out["by_base"][base] = {"lowest_k_crossover_within_tolerance": inside, "lowest_k_crossover_beyond": beyond,
                                "root_sf_at_k_at_tolerance": at_tol["root"]["sf_at_k"],
                                "liner_end_corner_factor_to_out_rank_within_tolerance": ends, "liner_ei_jump": jump,
                                "contact_tension_max": {"MPa": t_val, "offset_um": t_off, "station": t_st, "face": t_fn},
                                "not_solved": refused}
        why = ("" if not inside else "nominal bending, the mouth section out-swinging the root as in 92"
               if inside["contact_factor_on_1_over_sf"] < 1.005 else "the contact's swing about a compressive mean, counted by 86's line"
               if inside["mean_MPa"] < 0 else "the contact raising a tensile-mean cycle")
        if inside and "k_crossover_contact_x1_3" in inside and inside["contact_factor_on_1_over_sf"] >= 1.005:
            lo, hi = inside["k_crossover_contact_x1_3"]
            why += f"; with the arc ceiling's ×{ARC_CONCENTRATION:.1f} on the contact's share it would be {_down(lo):.2f}–{_down(hi):.2f}, so an estimate, not a bound"
        lines.append(f"«{base}»: inside ⌀0.10 the welded root stays the critical section for every seam knock-down "
                     + (f"k < {_down(inside['k_crossover']):.2f} (lowest at the {inside['station']} {inside['face']} face, "
                        f"{inside['offset_um']} µm: drawn-wire SF {inside['sf_drawn_wire']:.1f}, contact ×{inside['contact_factor_on_1_over_sf']:.2f} "
                        f"on 1/SF — {why}" if inside else "k (no section's k_x is finite")
                     + f"; root SF {at_tol['root']['sf_at_k']['1']:.1f} at k = 1 at {tol} µm), "
                     + (f"beyond it the lowest is {_down(beyond['k_crossover']):.2f} ({beyond['station']} {beyond['face']}, {beyond['offset_um']} µm)"
                        if beyond else "beyond it not swept or never crossed")
                     + "; the liner end's unmodelled corner stays below every modelled section while it concentrates its bare-side "
                       "nominal by less than " + " / ".join(f"×{_down(v['factor']):.2f} (k {k}, {v['offset_um']} µm)" for k, v in ends.items())
                     + f" — of the order of the liner's own stiffening of the wire (×{jump:.3f}), so not bounded here"
                     + (f" — {len(refused)} path point(s) refused by 92 (at "
                        + ", ".join(f"{ns['offset_um']} µm, drag {ns['drag_N']:+.4f} N of ±{drag_n:.3f} N" for ns in refused)
                        + "): that cycle omits them, so its root and station amplitudes are both lower bounds and the k_x there has no "
                          "known direction" if refused else ""))
    # what the contact does to tension, measured pointwise per base (a layer on a half-space puts tension at the surface
    # beside a patch, Boussinesq; whether the base passes it on is the base's) — and where it raises a station's worst 1/SF most
    faces = [(f, r, st, fn) for r in rows for st in ("mouth", "exit") for fn, f in r[st]["faces"].items()]
    fw, rw, stw, fnw = max(faces, key=lambda x: x[0]["contact_factor_on_1_over_sf"])
    f_t, r_t, st_t, fn_t = max((x for x in faces if x[0]["mean_MPa"] >= 0), key=lambda x: x[0]["contact_factor_on_1_over_sf"])
    tension = " · ".join(f"{base} {(c := out['by_base'][base]['contact_tension_max'])['MPa']:+.3f} MPa ({c['offset_um']} µm, "
                         f"{c['station']} {c['face']})" for base in BASES)
    out["contact_factor_on_1_over_sf_max"] = {"factor": fw["contact_factor_on_1_over_sf"], "mean_MPa": fw["mean_MPa"],
                                              "base": rw["base"], "offset_um": rw["offset_um"], "station": stw, "face": fnw}
    out["contact_factor_at_tensile_mean_max"] = {"factor": f_t["contact_factor_on_1_over_sf"], "base": r_t["base"],
                                                 "offset_um": r_t["offset_um"], "station": st_t, "face": fn_t,
                                                 "sf_drawn_wire": f_t["sf_drawn_wire"]}
    out["text"] = "; ".join(lines) + ". " + (
        f"The largest tension the contact through the layer puts on the wire, pointwise: {tension}; its weight on a station's "
        f"worst 1/SF is largest (×"
        f"{fw['contact_factor_on_1_over_sf']:.2f}, {rw['base']} {rw['offset_um']} µm {stw} {fnw}) where the governing cycle's mean is "
        + ("compressive — 86's line counting a compressive swing as amplitude without crediting the mean, the conservative reading"
           if fw["mean_MPa"] < 0 else "tensile")
        + f"; where the governing cycle's mean is tensile it raises the station's worst 1/SF by at most ×{f_t['contact_factor_on_1_over_sf']:.2f} "
          f"({r_t['base']}, {r_t['offset_um']} µm, {st_t} {fn_t}, SF {f_t['sf_drawn_wire']:.1f}).")
    return out


def main() -> int:
    if "--summary-only" in sys.argv:   # the rows stay as solved; only the verdict is re-derived from them
        d = json.loads(OUT_JSON.read_text(encoding="utf-8"))
        d["summary"] = summarise(d["rows"], d["inputs"]["drag_N"], d["inputs"]["endurance_drawn_wire_MPa"])
        OUT_JSON.write_text(json.dumps(d, indent=2, ensure_ascii=False, default=float) + "\n", encoding="utf-8")
        print("  " + d["summary"]["text"])
        return 0
    t0 = time.time()
    banner("97 — the bus wire under the liner's edges: contact through the layer + nominal bending (HW.34)")
    ctl = kernel_controls()
    print(f"  kernel controls {ctl} · {time.time() - t0:.0f} s")
    d68 = json.loads(m92.BUS68_CACHE.read_text(encoding="utf-8"))
    geo = s55.SHIPPED_GEOMETRY
    liner = next({"branch": lb, "coating_or_liner_mm": t, "play_side": side} for lb, t, side in s55.INSULATION_OPTIONS if side == "channel")
    play = d68["inputs"]["radial_plays_um"]["zero interference"] / 1000.0
    f = max(s55.MU_SWEEP) * s55.F_POGO_N
    sigma_e = s55.endurance_MPa(YIELD_TI_MPA, derate=1.0)
    tables_pk = {b: m91.PhiTable(m91.NU_PEEK, b) for b in m91.BASES}
    rows = []
    with ProcessPoolExecutor(WORKERS) as pool:
        for base in BASES:
            table = TransferTable(base)
            for off in OFFSETS_UM:
                r = run_offset(geo, liner, play, off, f, base, tables_pk, table, pool, sigma_e)
                rows.append(r)
                mo, ex = r["mouth"], r["exit"]
                print(f"  {base:12s} {off:4d} µm: root SF(k=1) {r['root']['sf_at_k']['1']:.1f} · mouth SF {mo['faces'][mo['worst_face']]['sf_drawn_wire']:.1f} "
                      f"({mo['worst_face']}, k_x {mo['faces'][mo['worst_face']]['k_crossover']}) · exit SF {ex['faces'][ex['worst_face']]['sf_drawn_wire']:.1f} "
                      f"({ex['worst_face']}) · liner end SF {min(v['sf_nominal_only'] for v in r['liner_end'].values() if isinstance(v, dict)):.1f} "
                      f"· not solved {len(r['not_solved'])} · {time.time() - t0:.0f} s", flush=True)
    for r in rows:
        for name in ("mouth", "exit"):
            c = r[name]["controls"]
            tag = f"{r['base']} {r['offset_um']} µm {name}"
            assert c["max_padding_diff_MPa"] < 0.05, f"{tag}: the padding moves the field"
            assert c["max_centroid_nominal_diff_MPa"] < 1e-6, f"{tag}: nominal ≠ 92's section stress"
            assert not np.isfinite(c["min_rod_toward_wall_over_play"]) or c["min_rod_toward_wall_over_play"] > 0.5, \
                f"{tag}: at a patch the rod is not displaced toward the wall on the window's side — the contact face is wrong"
            assert c["internal_92_Ecv2_minus_sigma_MPa"] <= 0.01 * c["internal_92_scale_MPa"] + 0.01, f"{tag}: 92's moment ≠ its pose"
    result = {"question": "does a section of the bus wire under the liner's mouth or exit edge out-rank the welded root once the "
                          "contact pressure carried through the PEEK layer is added to the nominal bending — on 86's Soderberg line?",
              "inputs": {"h_mm": H_MM, "E_PEEK_MPa": E_PEEK_MPA, "nu_PEEK": NU_PEEK, "alloy": ALLOY_BASELINE, "E_Ti_MPa": E_TI_MPA,
                         "nu_Ti": NU_TI, "yield_Ti_MPa": YIELD_TI_MPA, "endurance_drawn_wire_MPa": sigma_e, "k_readings": list(K_READINGS),
                         "kh_max": KH_MAX, "pads_mm": list(PADS_MM), "offsets_um": list(OFFSETS_UM), "drag_N": f,
                         "r_in_mm": m92.R_IN_REFERENCE_MM, "r_ex_mm": m92.R_EX_MM, "geometry": geo.label,
                         "play_um": play * 1000.0, "convention": "86: 1/SF = σ_a/(k·σ_e) + σ_m⁺/σ_y; the root carries k, a section under an edge is drawn wire"},
              "kernel_controls": ctl, "rows": rows, "summary": summarise(rows, f, sigma_e)}
    OUT_JSON.write_text(json.dumps(result, indent=2, ensure_ascii=False, default=float) + "\n", encoding="utf-8")
    banner(f"✅ saved {OUT_JSON.name} · {time.time() - t0:.0f} s")
    print("  " + result["summary"]["text"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
