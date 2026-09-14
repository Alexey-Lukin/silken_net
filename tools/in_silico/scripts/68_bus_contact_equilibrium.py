#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 / HW.23 — WHERE the bus rod really meets the cathode channel, solved as a CONTACT problem.

WHY THIS EXISTS. Script 55 locates the wall contact under pogo drag by asking where the FREE tip-loaded
cantilever, under the FULL drag, first equals the radial play (`first_wall_contact_mm`). That free
shape is not an equilibrium. Under a tip load the deflection grows monotonically from the root, so as
the drag ramps up the first station to reach the wall is the one FARTHEST from the root inside the
channel — the pad plane, where the liner ends flush — and from then on the drag is reacted there. This
script solves the contact problem instead of reading it off a free shape.

It also prices what script 55 does not model: a static RADIAL OFFSET and a TILT of the channel axis
relative to the root axis. Both are tolerance-stack quantities (each of cem/cathode_flange.json and
cem/zone2_sleeve.json declares its own concentricity), and neither is computed anywhere in the tree.

⚠️ READ THE GEOMETRY AXIS BEFORE ANY NUMBER. The unsupported PEEK gap — which sets both the mouth
station and the rod length — is derived in script 55 from `Z1_INSERTION_MM = 30`, an HW.8 PLACEHOLDER
that the tree has already measured to lie OUTSIDE the Zone-1 lock's own insertion window
(`MechanicalLock.InsertionWindowMm` in tools/cad, 00_07 HW.26 G1). Every table below is therefore
computed at the placeholder AND at both ends of the lock window, and the offset price moves by an order
of magnitude between them. The radial play is likewise swept: the zero-interference value AND the three
rows of script 55's `interference_window` (the fit swells the tube and eats the play).

MODEL. Euler-Bernoulli beam, cubic Hermite elements, clamped at the anode root (x = 0) — weld and anode
body rigid. A rigid, frictionless wall along the channel from the mouth to the pad plane. Unilateral
contact by an active set on PRESCRIBED displacements (the active wall nodes are eliminated, the rest is
solved on a symmetrically scaled SPD matrix — a saddle-point formulation was ill-conditioned enough to
cycle on some offsets), with the sign of every reaction checked. Geometry, material, drag and the three
insulation branches are IMPORTED from script 55 (digit-leading module name -> importlib, the script-24c
pattern; importing does not run 55's main), so the two scripts cannot drift apart on inputs.

CONTROLS asserted in-run, with what each one can and cannot catch:
  * coaxial drag above touchdown, bare member: root stress = 3·E·c·g/L² and the only contact is the pad
    plane — catches a wrong pad station, rod length or play; blind to the mouth station;
  * first offset past the play, bare member, when the mouth is the only contact: root stress =
    3·E·c·(e − g)/a² with a = the gap — catches a wrong mouth station;
  * no wall is violated at element MIDPOINTS — catches a contact the node set missed between nodes;
  * a grazing-contact row agrees at two element sizes — a discretisation check on a row whose contact
    does not sit on a node;
  * the offsets that cycled the saddle-point solver solve without cycling;
  * the equilibrium residual closes — guards the linear solve ONLY; it holds for any EI or station.

⛔ DECLARED CEILINGS — read these before quoting any number below:
  * RIGID, FRICTIONLESS wall: no liner compliance, no contact pressure, no axial traction. Past the play
    the mouth corner loads the PEEK tube hard enough that its compressive strength and 20-yr creep would
    relax a displacement-driven load, so every offset stress is an UPPER bound on that account.
  * PERFECT clamp: weld and printed-anode compliance lower every stress here.
  * The offset, tilt, insertion and play are SWEPT, never measured. Which ones the stack delivers is not
    computed anywhere in the tree.
  * A static offset stress is a MEAN stress. No mean-stress (Goodman-type) correction is applied, and the
    cyclic amplitude of a VARYING offset needs relative Zone-1 <-> Zone-3 motion, measured nowhere.
  * The pogo pad moment is priced at an eccentricity equal to the rod radius — a geometric bound for a
    contact on the rod end face, not a measured pin tolerance.
  * Small deflection; no thermal term; no liner creep; no P-δ from the 1 N axial pogo force.
  * No verdict is taken here. It measures where contact sits and what a micrometre of misalignment costs;
    whether ratified verdicts that stood on script 55's drag-contact picture reopen is the founder's
    (00_07 HW.34).
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import sys
from dataclasses import dataclass
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

_spec = importlib.util.spec_from_file_location("bus55", HERE / "55_bus_mechanical.py")
s55 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(s55)

OUT_JSON = CACHE_DIR / "mechanical" / "bus_contact_equilibrium.json"
BUS55_CACHE = CACHE_DIR / "mechanical" / "bus_mechanical.json"
MM_M = 1e-3
C_ROD_M = (s55.D_BUS / 2.0) * MM_M

ELEMENT_MM = 0.1                   # target element size; nodes are FORCED onto every station below
# Tolerances follow the MEASURED solve precision, not taste: on the scaled SPD solve the clamp moment carries a
# relative error of ~4e-7 on the 23 mm rod (cond ~1.5e10) and ~2e-6 on the 38-39 mm lock-window rods (cond
# ~1.2e11); iterative refinement does not improve it (the residual K·u itself is the limit, 2026-09-14).
CONTACT_TOLERANCE_MM = 1e-5        # 10 nm: above the displacement precision of the long rods, 3 orders below the play
RESIDUAL_TOLERANCE_REL = 1e-4      # 50x the worst measured relative moment error
MIDPOINT_TOLERANCE_MM = 1e-4       # 0.1 µm between nodes
OFFSETS_UM = (0, 10, 15, 20, 25, 30, 40, 50, 75, 100)
CYCLED_OFFSETS_UM = (83, 86, 92, 130, 193, 197)   # cycled the saddle-point solver (adversarial review)
TILTS_MRAD = (1.0, 2.0, 3.0, 5.0, 9.0)


@dataclass(frozen=True)
class Geometry:
    label: str
    insertion_mm: float
    gap_mm: float        # unsupported PEEK gap = mouth station
    pad_mm: float        # pad plane = rod length = channel exit
    liner_from_mm: float

    @classmethod
    def at_insertion(cls, label: str, insertion_mm: float) -> Geometry:
        gap = s55.SLEEVE_LEN_MM - insertion_mm - s55.SHANK_LEN_MM
        return cls(label, insertion_mm, gap, gap + s55.BORE_DEPTH_MM, gap - s55.LINER_PROTRUSION_MM)


def lock_insertion_window_mm() -> tuple[float, float]:
    """Zone-1 lock insertion window, from the lock manifest itself. ⚠️ By-value FORMULA crossing: the home is
    `MechanicalLock.InsertionWindowMm` in tools/cad (end of the PEEK contact zone -> near flank of the
    DIN-471 groove), pinned there by `MechanicalLockTests`; nothing binds this line to it."""
    lock = s55.cem("mechanical_lock.zone1")
    return (float(lock["contact_start_mm"]) + float(lock["contact_length_mm"]), float(lock["groove_offset_mm"]))


def geometries() -> list[Geometry]:
    lo, hi = lock_insertion_window_mm()
    return [Geometry.at_insertion("script 55 placeholder (HW.8)", s55.Z1_INSERTION_MM),
            Geometry.at_insertion("lock window, near end", hi),
            Geometry.at_insertion("lock window, far end", lo)]


def branch_rows() -> list[dict]:
    rows = []
    for label, t_mm, side in s55.INSULATION_OPTIONS:
        row = {"branch": label, "coating_or_liner_mm": t_mm, "play_side": side, "shipped": side == "channel"}
        row["radial_play_mm"] = s55.branch_member(row)[0]
        rows.append(row)
    return rows


def liner_plays_mm() -> list[tuple[str, float]]:
    """Zero-interference play plus the three rows of script 55's interference window (loaded, never retyped)."""
    liner = next(r for r in branch_rows() if r["shipped"])
    plays = [("zero interference", liner["radial_play_mm"])]
    rows = json.loads(BUS55_CACHE.read_text(encoding="utf-8"))["interference_window"]["od_growth_eats_channel_play"]["rows"]
    plays += [(f"interference window {r['at']}", r["channel_radial_play_um"] / 1000.0) for r in rows]
    return plays


def ei_at(x_mm: float, geo: Geometry, row: dict, bonded: bool) -> float:
    if row["play_side"] == "channel" and bonded and x_mm >= geo.liner_from_mm:
        return s55.flexural_rigidity_Nm2(s55.D_BUS, row["coating_or_liner_mm"])
    return s55.flexural_rigidity_Nm2(s55.D_BUS)


def mesh(geo: Geometry, h_mm: float) -> np.ndarray:
    """Nodes on the root, the liner start, the mouth and the pad plane — a uniform mesh that misses the mouth
    leaves the wall's first station BETWEEN nodes, which the midpoint control caught on the lock-window geometry."""
    stations = sorted({0.0, max(0.0, geo.liner_from_mm), geo.gap_mm, geo.pad_mm})
    parts = [np.linspace(a, b, max(1, int(np.ceil((b - a) / h_mm - 1e-9))) + 1)[:-1] for a, b in itertools.pairwise(stations)]
    return np.concatenate([*parts, np.array([geo.pad_mm])])


def assemble(geo: Geometry, row: dict, bonded: bool, h_mm: float) -> tuple[np.ndarray, np.ndarray]:
    xs = mesh(geo, h_mm)
    n_el = len(xs) - 1
    k_glob = np.zeros((2 * (n_el + 1), 2 * (n_el + 1)))
    for e in range(n_el):
        le = (xs[e + 1] - xs[e]) * MM_M
        ei = ei_at(0.5 * (xs[e] + xs[e + 1]), geo, row, bonded)
        k_el = ei / le ** 3 * np.array([[12.0, 6.0 * le, -12.0, 6.0 * le],
                                        [6.0 * le, 4.0 * le ** 2, -6.0 * le, 2.0 * le ** 2],
                                        [-12.0, -6.0 * le, 12.0, -6.0 * le],
                                        [6.0 * le, 2.0 * le ** 2, -6.0 * le, 4.0 * le ** 2]])
        dofs = [2 * e, 2 * e + 1, 2 * e + 2, 2 * e + 3]
        k_glob[np.ix_(dofs, dofs)] += k_el
    return xs, k_glob


def solve(geo: Geometry, row: dict, play_mm: float, drag_N: float = 0.0, pad_moment_Nm: float = 0.0,
          offset_mm: float = 0.0, tilt_rad: float = 0.0, tilt_pivot_mm: float = 0.0,
          bonded: bool = True, h_mm: float = ELEMENT_MM) -> dict:
    """Contact equilibrium of the clamped rod in a channel whose axis sits at
    w_axis(x) = offset + tilt·(x − pivot), walls at w_axis ± play on every channel node. Tip drag and pad
    moment act at the pad plane. Returns the SIGNED clamp moment, the root fibre stress, the tip deflection
    and the contact zones (adjacent active nodes merged; force = wall on rod, + toward +w)."""
    xs, k_glob = assemble(geo, row, bonded, h_mm)
    n_el = len(xs) - 1
    ndof = k_glob.shape[0]
    f = np.zeros(ndof)
    f[2 * n_el] = drag_N
    f[2 * n_el + 1] = pad_moment_Nm
    chan = [i for i, x in enumerate(xs) if geo.gap_mm - 1e-9 <= x <= geo.pad_mm + 1e-9]
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
        if geo.gap_mm < xm < geo.pad_mm:
            le = (xs[e + 1] - xs[e]) * MM_M
            wm = 0.5 * (u[2 * e] + u[2 * e + 2]) + le / 8.0 * (u[2 * e + 1] - u[2 * e + 3])
            ax = offset_mm + tilt_rad * (xm - tilt_pivot_mm)
            assert abs(wm / MM_M - ax) <= play_mm + MIDPOINT_TOLERANCE_MM, f"wall violated between nodes at {xm:.2f} mm"
    # guards the linear solve ONLY — holds for any EI or station, so it is not a model check
    m_clamp = float(wall[1])
    residual = m_clamp + drag_N * geo.pad_mm * MM_M + pad_moment_Nm \
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
    sigma = abs(m_clamp) * C_ROD_M / s55.second_moment_m4(s55.D_BUS) / 1e6
    return {"clamp_moment_Nmm_signed": m_clamp / MM_M, "sigma_root_MPa": sigma,
            "tip_deflection_um": u[2 * n_el] / MM_M * 1000.0, "contacts": zones}


def main() -> int:
    banner("Bus rod in the cathode channel — contact equilibrium (HW.34 / HW.23)")
    geos = geometries()
    rows = branch_rows()
    liner = next(r for r in rows if r["shipped"])
    plays = liner_plays_mm()
    mu_worst = max(s55.MU_SWEEP)
    e_ti, c = s55.E_TI, C_ROD_M
    for g in geos:
        print(f"  {g.label:<30s} insertion {g.insertion_mm:5.1f} mm → gap {g.gap_mm:5.1f} · pad plane {g.pad_mm:5.1f} mm")

    # ── (a) pogo drag, coaxial channel ───────────────────────────────────────────────────────────────
    banner("(a) pogo drag µ·F at the pad plane, coaxial channel")
    drag = []
    for geo in geos:
        for r in rows:
            for play_label, play in (plays if r["shipped"] else [("film", r["radial_play_mm"])]):
                capped = 3.0 * e_ti * c * (play * MM_M) / (geo.pad_mm * MM_M) ** 2 / 1e6
                touchdown = 3.0 * s55.flexural_rigidity_Nm2(s55.D_BUS) * play * MM_M / (geo.pad_mm * MM_M) ** 3
                by_mu = {}
                for mu in s55.MU_SWEEP:
                    f_lat = mu * s55.F_POGO_N
                    bare = solve(geo, r, play, drag_N=f_lat, bonded=False)
                    bond = solve(geo, r, play, drag_N=f_lat, bonded=True)
                    if f_lat > 1.001 * touchdown:
                        assert abs(bare["sigma_root_MPa"] - capped) <= 0.005 * capped, "coaxial cap ≠ closed form"
                        assert [z["station_mm"] for z in bare["contacts"]] == [round(geo.pad_mm, 2)], "drag contact is not the pad plane"
                    by_mu[str(mu)] = {"sigma_root_MPa_bare": round(bare["sigma_root_MPa"], 2),
                                      "sigma_root_MPa_bonded": round(bond["sigma_root_MPa"], 2),
                                      "contacts_bonded": bond["contacts"]}
                drag.append({"geometry": geo.label, "branch": r["branch"], "play": play_label,
                             "radial_play_um": round(play * 1000.0, 2),
                             "touchdown_drag_N": round(touchdown, 4), "capped_sigma_MPa_closed_form": round(capped, 2),
                             "by_mu": by_mu})
                print(f"  {geo.label[:18]:<18s} {r['branch']:<22s} {play_label:<32s} play {play * 1000:6.2f} µm · "
                      f"root σ µ=0.2…0.5: " + " / ".join(f"{v['sigma_root_MPa_bonded']:.2f}" for v in by_mu.values()) + " MPa")

    # ── (b) static offset, shipped branch, per geometry and play ────────────────────────────────────
    banner("(b) channel axis OFF the root axis — static, no drag (swept, never measured)")
    offsets, secants = [], []
    for geo in geos:
        for play_label, play in plays:
            exact: dict[int, float] = {}
            per_e = []
            for e_um in OFFSETS_UM:
                res = solve(geo, liner, play, offset_mm=e_um / 1000.0)
                exact[e_um] = res["sigma_root_MPa"]
                if e_um / 1000.0 <= play:
                    assert not res["contacts"] and res["sigma_root_MPa"] < 1e-6, "an offset inside the play bent the rod"
                per_e.append({"offset_um": e_um, "sigma_root_MPa": round(res["sigma_root_MPa"], 1), "contacts": res["contacts"]})
            past = [e for e in OFFSETS_UM if e / 1000.0 > play]
            # CONTROL on the MOUTH station: bare member, first offset past the play, mouth the only contact
            first = solve(geo, liner, play, offset_mm=past[0] / 1000.0, bonded=False)
            if [z["station_mm"] for z in first["contacts"]] == [round(geo.gap_mm, 2)]:
                closed = 3.0 * e_ti * c * ((past[0] / 1000.0 - play) * MM_M) / (geo.gap_mm * MM_M) ** 2 / 1e6
                assert abs(first["sigma_root_MPa"] - closed) <= 0.005 * closed, "mouth-contact closed form fails"
            secant = (exact[past[-1]] - exact[past[0]]) / (past[-1] - past[0])
            offsets.append({"geometry": geo.label, "play": play_label, "radial_play_um": round(play * 1000.0, 2),
                            "by_offset": per_e, "secant_MPa_per_um": round(secant, 3),
                            "secant_between_um": [past[0], past[-1]]})
            secants.append(secant)
            print(f"  {geo.label[:18]:<18s} {play_label:<32s} σ by offset µm→MPa: "
                  + " · ".join(f"{p['offset_um']}→{p['sigma_root_MPa']:.0f}" for p in per_e)
                  + f"   secant {secant:.2f} MPa/µm")

    # ── (c) reversing drag on top of a static offset — mean and amplitude ───────────────────────────
    banner("(c) drag ±µ·F on a static offset — what the drag adds (shipped branch, zero-interference play)")
    reversing = []
    zero_play = plays[0][1]
    for geo in geos:
        for e_um in (0, 10, 25, 50, 100):
            m0 = solve(geo, liner, zero_play, offset_mm=e_um / 1000.0)["clamp_moment_Nmm_signed"]
            mp = solve(geo, liner, zero_play, drag_N=+mu_worst * s55.F_POGO_N, offset_mm=e_um / 1000.0)["clamp_moment_Nmm_signed"]
            mn = solve(geo, liner, zero_play, drag_N=-mu_worst * s55.F_POGO_N, offset_mm=e_um / 1000.0)["clamp_moment_Nmm_signed"]
            to_mpa = MM_M * c / s55.second_moment_m4(s55.D_BUS) / 1e6
            reversing.append({"geometry": geo.label, "offset_um": e_um,
                              "sigma_no_drag_MPa": round(abs(m0) * to_mpa, 2),
                              "sigma_peak_under_reversing_drag_MPa": round(max(abs(mp), abs(mn)) * to_mpa, 2),
                              "sigma_amplitude_MPa": round(abs(mp - mn) / 2.0 * to_mpa, 2)})
        print(f"  {geo.label[:18]:<18s} offset µm → (static / peak / amplitude MPa): "
              + " · ".join(f"{r_['offset_um']}→{r_['sigma_no_drag_MPa']:.0f}/{r_['sigma_peak_under_reversing_drag_MPa']:.1f}/{r_['sigma_amplitude_MPa']:.1f}"
                           for r_ in reversing if r_["geometry"] == geo.label))

    # ── (d) pad moment: the pogo pin off the rod axis ────────────────────────────────────────────────
    pad_e_mm = s55.D_BUS / 2.0
    pad = []
    for geo in geos:
        for sgn in (+1, -1):
            res = solve(geo, liner, zero_play, drag_N=mu_worst * s55.F_POGO_N,
                        pad_moment_Nm=sgn * s55.F_POGO_N * pad_e_mm * MM_M)
            pad.append({"geometry": geo.label, "eccentricity_mm": sgn * pad_e_mm,
                        "sigma_root_MPa": round(res["sigma_root_MPa"], 2)})

    # ── (e) tilt of the channel axis, three pivots ────────────────────────────────────────────────────
    tilts = []
    for geo in geos:
        for pivot_label, pivot in (("root", 0.0), ("mouth", geo.gap_mm), ("pad plane", geo.pad_mm)):
            reach = max(abs(geo.gap_mm - pivot), abs(geo.pad_mm - pivot))
            per_t = []
            for t in TILTS_MRAD:
                res = solve(geo, liner, zero_play, tilt_rad=t / 1000.0, tilt_pivot_mm=pivot)
                per_t.append({"tilt_mrad": t, "sigma_root_MPa": round(res["sigma_root_MPa"], 1)})
            tilts.append({"geometry": geo.label, "pivot": pivot_label, "pivot_mm": round(pivot, 2),
                          "tilt_taken_up_by_play_mrad": round(zero_play / reach * 1000.0, 3), "by_tilt": per_t})

    # ── controls: discretisation on a grazing row, and the offsets that cycled the old solver ─────────
    # The 75 µm row on the placeholder geometry has a mouth contact plus an upper-wall contact whose true station
    # (20.57 mm, continuum analytic solution of the 2026-09-14 adversarial review) falls BETWEEN nodes — the one
    # kind of row where element size can matter. The assert below only requires the two contacts to exist.
    geo0 = geos[0]
    graze_c = solve(geo0, liner, zero_play, offset_mm=0.075)
    graze_f = solve(geo0, liner, zero_play, offset_mm=0.075, h_mm=ELEMENT_MM / 2.0)
    assert len(graze_c["contacts"]) >= 2, "the discretisation row lost its second contact"
    assert abs(graze_f["sigma_root_MPa"] - graze_c["sigma_root_MPa"]) <= 0.005 * graze_c["sigma_root_MPa"], "not mesh-converged"
    for geo in geos:
        for e_um in CYCLED_OFFSETS_UM:
            solve(geo, liner, zero_play, offset_mm=e_um / 1000.0)   # raises on a cycle

    placeholder, near, far = geos
    cap_zero = {g.label: next(d for d in drag if d["geometry"] == g.label and d["play"] == "zero interference")
                ["by_mu"][str(mu_worst)]["sigma_root_MPa_bonded"] for g in geos}
    sec_zero = {o["geometry"]: o["secant_MPa_per_um"] for o in offsets if o["play"] == "zero interference"}
    s55_supported = s55.bending_stress_MPa(s55.MU_CONTACT * s55.F_POGO_N, s55.L_FREE_SUP)
    s55_worst = json.loads(BUS55_CACHE.read_text(encoding="utf-8"))["weld_seam"]["span"]["worst_corner_sigma_MPa"]
    lock_caps = sorted((cap_zero[near.label], cap_zero[far.label]))
    lock_secants = sorted((sec_zero[near.label], sec_zero[far.label]))
    pad_peak = {g.label: max(p["sigma_root_MPa"] for p in pad if p["geometry"] == g.label) for g in geos}
    lock_pad = sorted((pad_peak[near.label], pad_peak[far.label]))
    amp_max = {g.label: max(r_["sigma_amplitude_MPa"] for r_ in reversing if r_["geometry"] == g.label) for g in geos}
    amp_clause = "; ".join(
        f"{g.label}: up to {amp_max[g.label]:.2f} MPa against its cap {cap_zero[g.label]:.2f}"
        + (" (within it)" if amp_max[g.label] <= cap_zero[g.label] + 0.005 else " (ABOVE it)")
        for g in geos)

    out = {
        "question": "Where does the bus rod meet the cathode channel under pogo drag, and what does a channel axis "
                    "off the root axis cost — solved as contact equilibrium, not read off a free cantilever "
                    "(00_07 HW.34 / HW.23)",
        "inputs": {
            "source": "imported from 55_bus_mechanical.py; the channel run, flange and sleeve lengths come from "
                      "cem/*.json via 55, but the unsupported GAP depends on the Zone-1 insertion, which in 55 is the "
                      "HW.8 PLACEHOLDER Z1_INSERTION_MM — swept here against the Zone-1 lock window",
            "insertion_placeholder_mm": s55.Z1_INSERTION_MM,
            "lock_insertion_window_mm": list(lock_insertion_window_mm()),
            "lock_window_source": "cem/mechanical_lock.zone1.json, formula of MechanicalLock.InsertionWindowMm "
                                  "(tools/cad) — by-value crossing, not gated here",
            "geometries": [g.__dict__ for g in geos],
            "radial_plays_um": {label: round(p * 1000.0, 2) for label, p in plays},
            "radial_play_source": "zero interference from the CEM diameters; the rest loaded from 55's cache "
                                  "interference_window.od_growth_eats_channel_play",
            "rod_dia_mm": s55.D_BUS, "E_Ti_Pa": e_ti, "E_PEEK_Pa": s55.E_PEEK_PA,
            "pogo_force_N": s55.F_POGO_N, "mu_sweep": list(s55.MU_SWEEP), "element_mm": ELEMENT_MM,
        },
        "drag_coaxial": drag,
        "offset_static_shipped_branch": offsets,
        "reversing_drag_on_offset": reversing,
        "pad_moment_at_rod_radius": pad,
        "tilt_static_shipped_branch": tilts,
        "script55_side_by_side": {
            "script55_supported_span_sigma_nominal_MPa": round(s55_supported, 2),
            "script55_supported_span_note": "µ_nominal·F on 55's assumed free span (the 6 mm gap); only 55's worst "
                                            "corner uses the free-shape first contact, through its span optimism",
            "script55_seam_worst_corner_sigma_MPa": s55_worst,
            "equilibrium_coaxial_cap_MPa_at_worst_mu_bonded": cap_zero,
        },
        "summary": (
            f"Coaxial channel: under pogo drag the rod meets the wall only at the pad plane, where the tube ends flush, "
            f"and the root stress is capped whatever the drag — {cap_zero[placeholder.label]:.2f} MPa on script 55's "
            f"placeholder geometry, {lock_caps[0]:.2f}–{lock_caps[1]:.2f} MPa across the Zone-1 lock "
            f"window (zero-interference play, bonded member). Script 55 prices that section at "
            f"{s55_supported:.2f} MPa (supported-span assumption) and {s55_worst} MPa worst corner. Channel off the "
            f"root axis: past the play the mouth becomes a contact station and the STATIC root bending grows at a "
            f"secant {sec_zero[placeholder.label]:.2f} MPa/µm on the placeholder and "
            f"{lock_secants[0]:.2f}–{lock_secants[1]:.2f} "
            f"MPa/µm across the lock window — the insertion placeholder moves the offset price by an order of "
            f"magnitude. Reversing drag on a static offset, amplitude over the swept offsets — {amp_clause}. A pogo "
f"contact off the rod axis by the rod radius, with the worst drag, gives up to {pad_peak[placeholder.label]:.2f} MPa "
f"on the placeholder and {lock_pad[0]:.2f}–{lock_pad[1]:.2f} MPa across the lock window — above the drag cap there. "
f"The tilt price depends on the PIVOT (root · mouth · pad plane) far more than on the angle. "
            f"MEASURED: contact stations and root stress for swept geometry, play, offset, tilt and pad moment. NOT "
            f"computed: what the stack delivers, contact pressure, a varying offset's amplitude, weld compliance. "
            f"No verdict is taken here."
        ),
        "not_modelled": {
            "wall": "rigid and frictionless — no liner compliance, no contact pressure, no axial traction; past the "
                    "play the mouth corner would load the PEEK tube beyond its compressive strength at the larger "
                    "offsets, so offset stresses are upper bounds",
            "clamp": "perfect — weld and printed-anode compliance lower every stress",
            "swept_not_measured": "insertion, play, offset, tilt and pad eccentricity",
            "mean_stress": "a static offset is a mean stress; no Goodman-type correction; the amplitude of a varying "
                           "offset needs relative Zone-1<->Zone-3 motion, measured nowhere",
            "drag_contact_edge": "the drag contact is the flush tube end at the pad-plane exit — ring on ring, the "
                                 "edge form the ≥ 1.0 mm protrusion avoids at the mouth — and no exit radius is "
                                 "specified anywhere; the wall reaction there is the drag minus the touchdown force "
                                 "on every cycle",
            "peak_moment_section": "in every configuration computed here the root is the peak-moment section",
            "other": "small deflection, no thermal term, no liner creep, no P-δ from the axial pogo force",
        },
    }
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner(f"Saved {OUT_JSON.relative_to(REPO_ROOT)}")
    print(out["summary"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
