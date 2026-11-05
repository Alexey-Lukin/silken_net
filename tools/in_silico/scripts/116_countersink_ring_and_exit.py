#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
116 — HW.34: the countersunk exit of the bus channel. How far the PEEK ring's bore must clear the channel so the ring
never bears, the floor of the exit radius under the ratified coaxiality, and what the countersink's depth costs the rod
— the machine half of the ⚖️ «depth, ring bore and exit radius together» (00_07 HW.34, the leg on the pad plane;
02_02 §1.2, 01_01 §1.4).

WHY THIS EXISTS. ⚖️ founder 2026-09-18 (02_02 §1.2) put a PEEK ring in a countersink round the channel exit — Ø ≥ 4.0,
the pad Ø1.0 plus 2 × 1.5 — and the Ti exit edge below the pad plane. Script 91 showed the ring is not neutral: the rod's
overhang leaves the bore line already at touchdown, so a ring whose bore equals the channel's is the FIRST contact
(PEEK on PEEK, which no tribo test measures); it priced the countersink only coaxially, at one exit radius, for a ring
that clears. Script 92 found the exit radius's floor under the tolerance offset (0.1 mm) on a FLUSH exit only and said
the countersunk edge needs it recomputed. The founder chose (2026-11-02) the ring that clears; this script gives the ⚖️,
per depth: (a) the radial clearance the ring's bore needs over the channel — the NECESSARY minimum over the band of
every input; (b) the smallest swept exit radius whose edge peak stays below the PEEK's flow pressure under the tolerance
offset, on every grid, every pad couple, both plays run; (c) what the depth costs the rod — the coaxial root cycle and
the in-contact sliding, the pad couple's reversing cycle, and under the tolerance offset the root's cycle priced against
86's seam threshold by 86's own formula.

WHAT THE PIN DOES AND DOES NOT ENTER. The pogo pin's tip sets the ring's OUTER diameter (02_02 §1.2: the metal ≥ 1.5 mm
from the pad's edge; the tip's footprint and the XY chain against that) — it enters none of (a)–(c): a ring that clears
the rod never bears. The pin enters through its SPRING FORCE — the drag µ·F and the couple F·e of a contact off the rod
axis: 55's 1.0 N is the upper end of what the tree knows (02_02 §2.2: ~98 g at full travel; 60 ± 20 g at mid-travel on
the one datasheet read), so it is taken as the adverse end, and (a) prints margin rows above it.

GEOMETRY. The Ti exit edge sits D below the rod end (91's overhang), rounded by r; the ring fills the countersink above
it, its thickness D, its bore coaxial with the CHANNEL (machined on the channel's datum — its position tolerance is not
in (a) and adds to the clearance). The overhang inside the ring is the rod over [L − D, L].

MODEL. 91's rod (55's piecewise EI, the exact Mohr flexibility) and kernels; 92's two-window elastic solve (mouth and
exit coupled through the rod) and 92's rigid same-edge LCP, carried to a countersunk exit and a pad couple by two
arguments that leave 92 unchanged at zero (control (1)).
  (a) RIGID: on 92's drag path (its swept points plus every change of active set, bisected — the overhang's excursion
      is piecewise linear in the drag and convex within a set, so its maximum sits on that path), the largest excursion
      of the rod past the bore line over [L − D, L], per depth and exit radius, over offsets 0 … the tolerance limit,
      every play 68 prints, both senses of the couple; the margin rows: offsets beyond the limit, and a larger drag at
      the band's corner. ELASTIC increment: the give lets the edge yield, so the overhang goes further — measured on
      92's solve at each depth's arg-max corner and its coaxial twin, at both radius ends, and the depth's largest
      added to every rigid figure of that depth.
  (b) At the tolerance limit, the exit-edge peak at the drag's LOADING end (+µ·F; 92's solve, refined on two square
      grids) per exit radius × depth (0 included) on two corners — the ADVERSE one (68's largest play, the couple's +
      end) and 92's frame (zero interference, no couple). The rehearsal's grounds (2026-11-02): the cycle peaks at the
      loading end on all its 24 cells and on every exit row of 92 at the limit; the end point rises with the play and
      with the couple on all its 12 cells and 6 interior ones. The floor AT THE LIMIT is the smallest swept radius below
      1·σ_y on every grid at both corners, with every larger radius too — then, at that radius, EVERY play × couple
      (the monotony checked, not assumed) and the full CYCLE (92's `exit_cycle_peak`) at the adverse cell, and the cycle
      at the radius below: any crossing moves the floor up. The floor OVER THE TOLERANCE checks that radius at interior
      offsets (the loading end on both corners, the other end on the adverse cell) and moves it up where one crosses.
      Control (1) runs 92's cycles at depth 0, no couple, the zero-interference play.
      ⚠️ The offset is not chosen by a proxy: the rigid exit REACTION peaks just past the play and falls towards the
      limit, and 92's own rows already part the two: 73.66 MPa coaxially at the LARGER reaction, 94.34 at 50 µm at the
      smaller — the peak follows the angle at which the rod lands on the rounding, not the reaction's size.
  (c) coaxially (zero-interference play, 91's frame): 91's elastic drag path (bonded, short-term) per depth × radius —
      the peak, the sub-cycle, the slide and the tip at µ_max — beside the rigid closed forms at the same edge; the pad
      couple's reversing cycle in 91's closed form at touchdown (elastic = rigid there). Under the tolerance offset:
      the root's mean and amplitude along 92's drag path on the rigid model per depth × radius × couple × play → the
      seam's break-even k through 86's `soderberg` on 86's own alloys, against 86's binding k.
  (d) the ratified exit radius: (b)'s procedure at RATIFIED_R_EXIT_MM on every depth, whatever that depth's floor —
      and what it costs there, read from (a) and (c) at that radius.

CONTROLS asserted in-run, with what each one can and cannot catch:
  (1) depth 0, no couple, the zero-interference play: (b) reproduces 92's cached exit rows at the tolerance offset bit
      for bit, (c) the rigid swing reproduces 92's cached row — catches a changed default in 92; blind to depth > 0;
  (2) 92's rigid LCP with depth and a couple, at no offset, against 91's closed-form rigid point at the same edge —
      catches the couple or the station threaded wrongly into the rigid model;
  (3) 92's elastic solve at no offset, depth D, µ_max·F against 91's exit-only countersink rows — catches the depth
      threaded wrongly into the window, the recession or the reference; (3′) with a couple, against 91's exit-only
      solve with the same couple — catches the couple in the elastic beam terms;
  (4) the overhang rebuilt from 92's pressure fields reproduces the solve's own root moment — catches a wrong window
      sign, line load or station in the reconstruction (a) reads;
  (5) the coaxial elastic rows at depth 0 reproduce 91's main cycle rows, at depths 0.5–2.0 and r 0.2 91's countersink
      rows; the rigid closed forms reproduce 91's rigid same-edge columns — catches a path or a reading differing from
      91's;
  (6) every measured elastic increment is ≥ 0 — the direction (a) adds it in, measured, not assumed;
  (7)–(9) the excursion maximum is taken on 92's path with its kinks; the far mouth wall is asserted open at every
      rigid point (92's rigid model has no such wall);
  (10) the floor over the tolerance — not an assert but the procedure of (b): an interior end-point peak at or above
      1·σ_y on any grid moves the floor up; can catch a floor that holds only at the limit; cannot see an interior
      cycle peak away from the drag's ends or an interior offset not swept (the declared ceiling).

⛔ DECLARED CEILINGS — read these before quoting any number below:
  * 91's and 92's ceilings hold: LINEAR elasticity (a peak above the flow pressure is FLAGGED, never redistributed),
    a FLAT layer, bonded ⊥ frictionless and short-term ⊥ 20-year as brackets ((b) and (c) run bonded, short-term,
    as 92 does), no thermal term, no P-δ, no wear, no friction in (b).
  * The flow pressure is 55's — PEEK's 23 °C tensile yield × 1 and × 3; at service temperature the PEEK is softer.
  * A PLANAR model: the drag, the offset and the couple act in one plane. The ring's position tolerance relative to
    the channel and the thermal pull-back of the cold liner are NOT in (a); they add to its figures.
  * The exit CLOSURE element (02_02 §1.2: an elastomer, Ø~1.3) is not modelled; if it sits in the ring's bore, round
    the liner, it is a soft contact this script does not see.
  * The ring's own retention, strength and thickness floor are not modelled — the model prices depth from the rod's
    side only; what sets the shallowest depth the ring tolerates is outside it.
  * The pin's spring force is 55's 1.0 N throughout (b) and (c); a P/N with a stiffer spring re-runs this script.
  * Inside the tolerance the floor is checked at the swept interior offsets, at the drag's two ends and at the floor
    radius only; a cycle peak away from the ends, or at an offset between the swept ones, is not seen; a row the
    two-window solve refuses (a line contact it cannot represent) is NOT a pass — it is named per depth in
    `interior_rows_not_solved_at_the_floor`, and the floor stands there only on the rows that did solve.
  * The ring's outer diameter (the pin tip's) enters nothing here.
  * No verdict is taken here — the one it serves (⚖️ founder 2026-11-02, 00_07 HW.34) chose ONE exit radius,
    RATIFIED_R_EXIT_MM, at every depth up to the deepest swept, and (d) runs the floor's procedure AT it: every play ×
    couple at the limit, the full cycle at the adverse cell, the interior offsets at both drag ends. A depth beyond the
    sweep is not covered — it re-runs this script.

Run:  python tools/in_silico/scripts/116_countersink_ring_and_exit.py     # ≈ 1¾ h on 8 workers (one BLAS thread each)
      python tools/in_silico/scripts/116_countersink_ring_and_exit.py --smoke <out.json>   # every branch once, small
      sweeps, written to <out.json> (a rehearsal of the run path — never the cache)
"""
from __future__ import annotations

import os

for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_var, "1")   # before numpy: one thread per worker — the solves ran at one core each anyway

import importlib.util
import json
import sys
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib.constants import CACHE_DIR, SIGMA_YIELD_PEEK_PA
from lib.utils import banner

SI_DESCRIPTION = ("A countersunk exit of the bus rod's channel: the clearance a PEEK ring's bore needs so the rod never "
                  "bears on it, the floor of the exit-edge radius under an axis offset, and what the countersink's depth "
                  "costs the rod's root cycle.")  # its row in the paper SI (72): English, no repo jargon


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


m92 = _load("liner92", "92_liner_mouth_contact.py")
m91, s55 = m92.m91, m92.s55
m86 = _load("coax86", "86_coaxiality_allocation.py")
sys.modules["bus55"] = s55   # 86 loads its own copy of 55 under the same name; the geometry the workers pickle is 91's

OUT_JSON = CACHE_DIR / "mechanical" / "countersink_ring_exit.json"
BUS68_CACHE = CACHE_DIR / "mechanical" / "bus_contact_equilibrium.json"
BUS91_CACHE = CACHE_DIR / "mechanical" / "liner_exit_contact.json"
BUS92_CACHE = CACHE_DIR / "mechanical" / "liner_mouth_contact.json"
COAX86_CACHE = CACHE_DIR / "mechanical" / "coaxiality_allocation.json"

# ── sweeps — each a sweep because the quantity has no number in any artifact ─────────────────────────────────────────
DEPTHS_MM = (0.25, 0.5, 1.0, 1.5, 2.0)            # the countersink's depth: unset (02_02 §1.2); 91 swept 0.5–2.0
DEPTHS_EXIT_MM = (0.0, *DEPTHS_MM)                # (b) and (c) also on the flush exit — 91's and 92's own rows
R_EXIT_SWEEP_MM = (0.05, 0.1, 0.15, 0.2, 0.3, 0.5)  # 91's sweep plus 0.15, where 92's flush floor falls between 0.1 and 0.2
PAD_ECC_MM = (-0.5, 0.0, 0.5)                     # the pin's contact off the rod axis: 68 (d) bounds it by the rod radius
OFFSETS_A_UM = (0, 10, 25, 35, 50)                # (a) up to the tolerance limit
OFFSETS_MARGIN_UM = (75, 100)                     # beyond the limit: margin rows, never a ground
INTERIOR_OFFSETS_UM = (30, 40)                    # (b) the floor's check inside the tolerance (end points of the drag)
RATIFIED_R_EXIT_MM = 0.2                          # (d) ⚖️ founder 2026-11-02 (00_07 HW.34): one exit radius at every depth ≤ 2.0
DRAG_MARGIN_N = (0.75, 1.0)                       # (a) a larger drag at the band's corner: a stiffer spring or µ
OVER_GRID = np.linspace(0.0, 1.0, 41)             # the overhang [L − D, L], sampled
WORKERS = 8                                       # independent rows in parallel, one BLAS thread each (header)
CTL_TOL_MPA = 0.003                               # the elastic two-window solve against 91's exit-only one (92's own control: 0.002)


def setup():
    geo = s55.SHIPPED_GEOMETRY
    liner = next({"branch": lb, "coating_or_liner_mm": t, "play_side": side}
                 for lb, t, side in s55.INSULATION_OPTIONS if side == "channel")
    return geo, liner


# ── (a) the overhang's excursion past the bore line ─────────────────────────────────────────────────────────────────
def rigid_excursion(rod, geo, play: float, off: float, drag: float, depth: float, r_ex: float, pad: float) -> float:
    """How far the overhang [L − D, L] goes past the channel's bore line on either side, rigid same-edge points (mm;
    negative = inside the play). Asserts the mouth's far wall — absent from 92's rigid model — stays open."""
    x_m, x_x = geo.gap_mm + m92.R_IN_REFERENCE_MM, rod.L - depth - r_ex
    rp = m92.rigid_points(rod, play, off, drag, x_m, x_x, pad)
    st = ((x_m, -1), (x_x, +1), (x_x, -1))

    def v(x):
        return drag * rod.defl(x, rod.L) + pad * rod.defl_c(x) - sum(st[j][1] * rp["R_N"][j] * rod.defl(x, st[j][0]) for j in range(3))
    assert play - (float(v(np.array(geo.gap_mm))) - off) >= -1e-9, "the mouth's far wall was reached (not in the rigid model)"
    u = v(rod.L - depth + OVER_GRID * depth) - off
    return float(max(u.max(), -u.min())) - play


def band_corner(args) -> dict:
    """The excursion's maximum over 92's drag path for one (depth, radius, offset, play, couple, drag) — and its drag."""
    geo, liner, depth, r_ex, off, play_label, play, ecc, f = args
    rod = m91.Rod(geo, liner)
    pad = s55.F_POGO_N * ecc
    x_m, x_x = geo.gap_mm + m92.R_IN_REFERENCE_MM, rod.L - depth - r_ex
    best = max((rigid_excursion(rod, geo, play, off, d, depth, r_ex, pad), d) for d in m92.drag_path(rod, play, off, x_m, x_x, f, pad))
    return {"depth_mm": depth, "r_exit_mm": r_ex, "offset_um": round(off * 1e3), "play": play_label, "play_um": round(play * 1e3, 2),
            "pad_ecc_mm": ecc, "drag_band_N": f, "excursion_um": best[0] * 1e3, "at_drag_N": best[1]}


def elastic_excursion(geo, liner, play: float, off: float, drag: float, depth: float, r_ex: float, pad: float) -> dict:
    """The same excursion on 92's elastic two-window solve: the overhang rebuilt from the solve's pressure fields
    (control (4): the rebuild reproduces the solve's root moment)."""
    st = m92.solve(geo, liner, play, off, drag, m92.R_IN_REFERENCE_MM, r_ex=r_ex, with_field=True, depth=depth, pad_nmm=pad)
    rod = m91.Rod(geo, liner)
    loads = []
    for name in ("mouth", "exit"):
        fl = st["fields"][name]
        q = (fl["p_MPa"] * np.cos(fl["y_mm"] / m91.R_OD_MM)[None, :]).sum(axis=1) * fl["ds_mm"] * fl["dy_mm"]
        loads.append((fl["window_sign"], fl["x_mm"], q))
    m_root = drag * rod.L + pad - sum(sg * float(q @ x) for sg, x, q in loads)
    rebuild = abs(m_root - st["m_root_Nmm"]) / max(1.0, abs(st["m_root_Nmm"]))
    assert rebuild <= 1e-9, f"the overhang rebuild misses the solve's root moment by {rebuild:.2e}"
    xs = rod.L - depth + OVER_GRID * depth
    v = drag * rod.defl(xs, rod.L) + pad * rod.defl_c(xs) - sum(sg * (rod.defl(xs[:, None], x[None, :]) @ q) for sg, x, q in loads)
    u = v - off
    return {"excursion_um": (float(max(u.max(), -u.min())) - play) * 1e3, "rebuild_rel_error": rebuild}


def increment_task(args) -> dict:
    """One measured elastic increment at a band corner: elastic − rigid excursion at the same drag."""
    geo, liner, corner = args
    play, off = corner["play_um"] / 1e3, corner["offset_um"] / 1e3
    pad = s55.F_POGO_N * corner["pad_ecc_mm"]
    rod = m91.Rod(geo, liner)
    rigid = rigid_excursion(rod, geo, play, off, corner["at_drag_N"], corner["depth_mm"], corner["r_exit_mm"], pad) * 1e3
    try:
        el = elastic_excursion(geo, liner, play, off, corner["at_drag_N"], corner["depth_mm"], corner["r_exit_mm"], pad)
    except RuntimeError as err:
        return {**corner, "rigid_um": rigid, "not_solved": str(err)[:160]}
    return {**corner, "rigid_um": rigid, "elastic_um": el["excursion_um"], "increment_um": el["excursion_um"] - rigid,
            "rebuild_rel_error": el["rebuild_rel_error"]}


# ── (b) the exit-edge peak under the tolerance offset ───────────────────────────────────────────────────────────────
def exit_task(args) -> dict:
    geo, liner, play_label, play, off, r_ex, depth, ecc, f = args
    row = m92.exit_cycle_peak(geo, liner, play, off, r_ex, f, depth=depth, pad_nmm=s55.F_POGO_N * ecc)
    return {"depth_mm": depth, "pad_ecc_mm": ecc, "play": play_label, "play_um": round(play * 1e3, 2), **row}


def endpoint_task(args) -> dict:
    """The exit-edge peak at ONE end of the drag (± µ_max·F) at an offset inside the tolerance, refined on 92's square
    grids — the interior-offset check of the floor. A cycle's peak is never below its end points, so this can UNDERSTATE
    an interior offset's cycle peak, never overstate it (the declared ceiling)."""
    geo, liner, play_label, play, off, r_ex, depth, ecc, drag = args
    row = {"play": play_label, "offset_um": round(off * 1e3), "r_exit_mm": r_ex, "depth_mm": depth, "pad_ecc_mm": ecc, "drag_N": drag}
    try:
        st = m92.solve(geo, liner, play, off, drag, m92.R_IN_REFERENCE_MM, r_ex=r_ex, refine=m92.REFINE_CELLS_MM,
                       refine_windows=("exit",), depth=depth, pad_nmm=s55.F_POGO_N * ecc)
    except RuntimeError as err:
        return {**row, "not_solved": str(err)[:160]}
    if st["exit"] is None:
        return {**row, "exit_loaded": False}
    cells = st["exit"]["p_max_MPa_refined"]
    sy = SIGMA_YIELD_PEEK_PA / 1e6
    vals = list(cells.values())
    return {**row, "exit_loaded": True, "peak_MPa": round(max(vals), 2),
            "peak_by_square_cell_MPa": {c: round(v, 2) for c, v in cells.items()},
            "below_1_sigma_y_on_every_grid": max(vals) < sy,
            "flow_verdict": {f"{c:.1f}": ("above" if min(vals) > c * sy else "below" if max(vals) < c * sy else "at, within the grids")
                             for c in s55.CONTACT_CONSTRAINT_FACTORS}}


# ── (c) what the depth costs the rod ────────────────────────────────────────────────────────────────────────────────
def coaxial_task(args) -> dict:
    """91's elastic exit-only drag path at one (depth, radius), bonded, short-term — read as 91 reads its rows."""
    geo, liner, play, depth, r_ex, mu_max = args
    path = m91.drag_path(geo, liner, play, r_ex, e=depth)
    sig = [p["sigma_signed_MPa"] for p in path]
    at = next(p for p in path if abs(p["drag_N"] - mu_max * s55.F_POGO_N) < 1e-9)
    return {"depth_mm": depth, "r_exit_mm": r_ex, "peak_sigma_MPa": round(max(sig), 4),
            "sigma_at_mu_max_MPa": round(at["sigma_signed_MPa"], 4), "subcycle_range_MPa": round(max(sig) - at["sigma_signed_MPa"], 4),
            "slide_per_cycle_um_at_mu_max": round(m91.slide_um(geo, liner, play, at), 5),
            "tip_past_bore_line_um_at_mu_max": round(at["tip_past_bore_line_um"], 3), "points": len(path)}


def rigid_coaxial(geo, liner, play: float, depth: float, r_ex: float, mu_max: float) -> dict:
    """The coaxial cycle on a rigid wall at the same edge (91's closed forms): the peak at touchdown, the full drag,
    and the pad couple's reversing cycle at |e| max (91 (e): amplitude (σ_td(+e) + σ_td(−e))/2, mean their half-difference)."""
    rod = m91.Rod(geo, liner)
    x_t = rod.L - depth - r_ex
    peak = m91.signed_sigma(m91.touchdown_drag(rod, play, x_t) * rod.L)
    full = m91.rigid_point(geo, liner, play, mu_max * s55.F_POGO_N, x_t)
    e = max(PAD_ECC_MM)

    def td(e_mm: float) -> float:
        m_pad = s55.F_POGO_N * e_mm
        return m91.signed_sigma(m91.touchdown_drag(rod, play, x_t, m_pad) * rod.L + m_pad)
    hi, lo = td(e), td(-e)
    return {"depth_mm": depth, "r_exit_mm": r_ex, "peak_rigid_touchdown_MPa": round(peak, 4),
            "full_drag_rigid_MPa": round(full["sigma_signed_MPa"], 4), "root_reverses_at_full_drag": full["sigma_signed_MPa"] < 0,
            "slide_rigid_um": round(m91.slide_um(geo, liner, play, full), 5),
            "pad_cycle": {"ecc_mm": e, "amplitude_MPa": round((hi + lo) / 2, 3), "mean_MPa": round((hi - lo) / 2, 3)}}


def offset_swing(rod, geo, play: float, off: float, f: float, depth: float, r_ex: float, pad: float) -> tuple[float, float]:
    """The root's (mean, amplitude) along 92's drag path on the rigid same-edge model (92's `swing`)."""
    x_m, x_x = geo.gap_mm + m92.R_IN_REFERENCE_MM, rod.L - depth - r_ex
    root = [m92.rigid_points(rod, play, off, d, x_m, x_x, pad)["sigma_signed_MPa"] for d in m92.drag_path(rod, play, off, x_m, x_x, f, pad)]
    return m92.swing(root)


def k_seam(mean: float, amp: float, alloys: dict) -> float:
    """86's break-even seam k for one cycle — 86's `soderberg` on 86's alloys, the binding (largest) one; the tensile
    fibre carries |mean|."""
    ks = []
    for a in alloys.values():
        _sf, k = m86.soderberg(amp, abs(mean), a["endurance_MPa"], a["yield_MPa"])
        assert k is not None, "no seam k exists for this cycle on some alloy (86 returns None there)"
        ks.append(k)
    return max(ks)


def smallest_safe(rows: list, key="r_exit_mm") -> float | None:
    """The smallest swept radius below 1·σ_y on every grid and every couple, with every larger radius too (92's rule)."""
    radii = sorted({r[key] for r in rows})
    ok = [r for i, r in enumerate(radii) if all(x["flow_verdict"]["1.0"] == "below" for x in rows if x[key] in radii[i:])]
    return min(ok) if ok else None


def main() -> int:
    t0 = time.time()
    banner("The countersunk exit — ring clearance, exit-radius floor, depth cost (HW.34, 02_02 §1.2)")
    geo, liner = setup()
    rod = m91.Rod(geo, liner)
    d68 = json.loads(BUS68_CACHE.read_text(encoding="utf-8"))
    d91 = json.loads(BUS91_CACHE.read_text(encoding="utf-8"))
    d92 = json.loads(BUS92_CACHE.read_text(encoding="utf-8"))
    d86 = json.loads(COAX86_CACHE.read_text(encoding="utf-8"))
    plays_um = d68["inputs"]["radial_plays_um"]
    plays = {k: v / 1000.0 for k, v in plays_um.items()}
    zero = plays["zero interference"]
    mu_max = max(s55.MU_SWEEP)
    f_band = mu_max * s55.F_POGO_N
    tol = m92.TOLERANCE_OFFSET_UM / 1000.0
    ctl: dict = {}

    # ── controls (2), (3), (3′) — the depth and the couple threaded through 92 ─────────────────────────────────────
    banner("controls — the depth and the couple in 92's rigid and elastic models against 91")
    c2 = []
    for depth in (0.0, 1.0, 2.0):
        for ecc in PAD_ECC_MM:
            for drag in (0.2, 0.5):
                x_x = rod.L - depth - m92.R_EX_MM
                mine = m92.rigid_points(rod, zero, 0.0, drag, geo.gap_mm + m92.R_IN_REFERENCE_MM, x_x, s55.F_POGO_N * ecc)
                theirs = m91.rigid_point(geo, liner, zero, drag, x_x, s55.F_POGO_N * ecc)
                c2.append(abs(mine["sigma_signed_MPa"] - theirs["sigma_signed_MPa"]))
    assert max(c2) < 1e-9, f"92's rigid model with depth and couple ≠ 91's closed form: {max(c2)}"
    ctl["rigid_depth_couple_vs_91_closed_form"] = {"max_abs_diff_MPa": float(f"{max(c2):.2e}"), "rows": len(c2)}
    c3 = {}
    for r91 in d91["countersink"]:
        depth = r91["overhang_mm"]
        st = m92.solve(geo, liner, zero, 0.0, f_band, m92.R_IN_REFERENCE_MM, r_ex=m92.R_EX_MM, depth=depth)
        theirs = r91["sigma_at_mu_MPa"][f"{mu_max:g}"]
        c3[f"{depth:g}"] = [round(st["sigma_signed_MPa"], 4), theirs]
        assert abs(st["sigma_signed_MPa"] - theirs) <= CTL_TOL_MPA, f"92 at depth {depth} ≠ 91's countersink row: {st['sigma_signed_MPa']} vs {theirs}"
    ctl["elastic_depth_vs_91_countersink"] = {"sigma_signed_MPa_92_vs_91_by_depth_mm": c3, "tolerance_MPa": CTL_TOL_MPA}
    c3p = {}
    for ecc in (-0.5, 0.5):
        pad = s55.F_POGO_N * ecc
        st = m92.solve(geo, liner, zero, 0.0, f_band, m92.R_IN_REFERENCE_MM, r_ex=m92.R_EX_MM, depth=1.0, pad_nmm=pad)
        theirs = m91.solve_exit(geo, liner, zero, f_band, m92.R_EX_MM, e=1.0, pad_nmm=pad)["sigma_signed_MPa"]
        c3p[f"{ecc:g}"] = [round(st["sigma_signed_MPa"], 4), round(theirs, 4)]
        assert abs(st["sigma_signed_MPa"] - theirs) <= CTL_TOL_MPA, f"92 with couple {ecc} ≠ 91's exit-only solve: {st['sigma_signed_MPa']} vs {theirs}"
    ctl["elastic_couple_vs_91_exit_only_depth_1mm"] = {"sigma_signed_MPa_92_vs_91_by_ecc_mm": c3p, "tolerance_MPa": CTL_TOL_MPA}
    print(f"  rigid: 92 with depth and couple = 91's closed form (max {max(c2):.1e} MPa over {len(c2)} rows)")
    print(f"  elastic: 92 at no offset = 91's countersink rows {c3}; with a couple {c3p}")

    pool = ProcessPoolExecutor(max_workers=WORKERS)
    # ── (a) the ring's clearance ────────────────────────────────────────────────────────────────────────────────────
    banner(f"(a) the ring's bore — the overhang past the bore line, rigid, over the band (µ·F {f_band:g} N, plays {len(plays)}, couples ±)")
    tasks = [(geo, liner, depth, r_ex, e / 1000.0, lab, pl, ecc, f_band) for depth in DEPTHS_MM for r_ex in R_EXIT_SWEEP_MM
             for e in (*OFFSETS_A_UM, *OFFSETS_MARGIN_UM) for lab, pl in plays.items() for ecc in PAD_ECC_MM]
    band = list(pool.map(band_corner, tasks, chunksize=8))
    corners = {}
    for depth in DEPTHS_MM:
        for r_ex in R_EXIT_SWEEP_MM:
            rows = [b for b in band if b["depth_mm"] == depth and b["r_exit_mm"] == r_ex and b["offset_um"] <= m92.TOLERANCE_OFFSET_UM]
            corners[(depth, r_ex)] = max(rows, key=lambda b: b["excursion_um"])
    margin_tasks = [(geo, liner, c["depth_mm"], c["r_exit_mm"], c["offset_um"] / 1e3, c["play"], c["play_um"] / 1e3, c["pad_ecc_mm"], f)
                    for c in corners.values() for f in DRAG_MARGIN_N]
    margin_drag = list(pool.map(band_corner, margin_tasks))
    # the elastic increment: at each depth's arg-max corner and its coaxial twin, at both radius ends
    inc_corners = []
    for depth in DEPTHS_MM:
        for r_ex in (min(R_EXIT_SWEEP_MM), max(R_EXIT_SWEEP_MM)):
            c = corners[(depth, r_ex)]
            twin = max((b for b in band if b["depth_mm"] == depth and b["r_exit_mm"] == r_ex and b["offset_um"] == 0),
                       key=lambda b: b["excursion_um"])
            inc_corners += [c, twin]
    increments = list(pool.map(increment_task, [(geo, liner, c) for c in inc_corners]))
    solved = [i for i in increments if "increment_um" in i]
    assert all(i["increment_um"] >= -1e-3 for i in solved), "an elastic increment came out negative — the direction (a) adds it in"
    ring = []
    for depth in DEPTHS_MM:
        inc = max(i["increment_um"] for i in solved if i["depth_mm"] == depth)
        for r_ex in R_EXIT_SWEEP_MM:
            c = corners[(depth, r_ex)]
            beyond = max(b["excursion_um"] for b in band if b["depth_mm"] == depth and b["r_exit_mm"] == r_ex and b["offset_um"] > m92.TOLERANCE_OFFSET_UM)
            md = {f"{m['drag_band_N']:g}": round(m["excursion_um"], 3) for m in margin_drag if m["depth_mm"] == depth and m["r_exit_mm"] == r_ex}
            ring.append({"depth_mm": depth, "r_exit_mm": r_ex, "rigid_band_max_um": round(c["excursion_um"], 3),
                         "elastic_increment_um": round(inc, 3), "needed_radial_clearance_um": round(c["excursion_um"] + inc, 3),
                         "corner": {k: c[k] for k in ("offset_um", "play", "play_um", "pad_ecc_mm", "at_drag_N")},
                         "rigid_beyond_tolerance_max_um": round(beyond, 3), "rigid_at_larger_drag_um": md})
            print(f"  D {depth:4.2f} r {r_ex:4.2f}: rigid {c['excursion_um']:6.2f} + elastic {inc:4.2f} = {c['excursion_um'] + inc:6.2f} µm "
                  f"(corner {c['offset_um']} µm, {c['play']}, e {c['pad_ecc_mm']:+.1f}); larger drag {md}; beyond tol {beyond:.2f}")

    # ── (b) the exit radius's floor under the tolerance offset ──────────────────────────────────────────────────────
    banner(f"(b) the exit edge at the tolerance limit ({m92.TOLERANCE_OFFSET_UM} µm) — end-point peaks over radius × depth × "
           f"two corners, every play × couple at the floor, cycles to verify")
    all_plays = list(plays.items())
    # The grid runs on two corners: the ADVERSE one — the largest play and the couple's + end, the highest end point on
    # every one of the rehearsal's 12 (depth, radius, couple) and 6 interior cells, monotone in play and in couple
    # (2026-11-02) — and 92's frame (zero interference, no couple) for continuity. The monotony is not assumed below:
    # at each depth's floor every play × couple is run (`corner_check`), and any of them crossing moves the floor.
    corners = [(max(plays, key=plays.get), max(PAD_ECC_MM)), ("zero interference", 0.0)]
    grid = list(pool.map(endpoint_task, [(geo, liner, lab, plays[lab], tol, r_ex, depth, ecc, f_band) for lab, ecc in corners
                                         for depth in DEPTHS_EXIT_MM for r_ex in R_EXIT_SWEEP_MM]))
    unsolved = [g for g in grid if "not_solved" in g or not g.get("exit_loaded")]
    assert not unsolved, f"an end point at the limit not solved, or not loading the exit: {unsolved[:2]}"
    floors = {f"{lab} / e {ecc:+g} mm": {f"{depth:g}": smallest_safe([g for g in grid if g["play"] == lab and g["pad_ecc_mm"] == ecc
                                                                         and g["depth_mm"] == depth]) for depth in DEPTHS_EXIT_MM}
              for lab, ecc in corners}
    checked: list = []                                    # every play × couple at the radii the floor stands or moves on

    def adverse(depth: float, r_ex: float) -> dict:
        """The (play, couple) whose end point is highest at this depth and radius — over the grid and the corner check."""
        return max((g for g in [*grid, *checked] if g["depth_mm"] == depth and g["r_exit_mm"] == r_ex), key=lambda g: g["peak_MPa"])

    def corner_check(cells: list) -> None:
        tasks = [(geo, liner, lab, pl, tol, r_ex, depth, ecc, f_band) for depth, r_ex in cells for lab, pl in all_plays
                 for ecc in PAD_ECC_MM]
        checked.extend(r for r in pool.map(endpoint_task, tasks) if r.get("exit_loaded"))
    # control (1): depth 0, no couple, the zero-interference play — 92's own CYCLE rows, bit for bit
    rows92 = [x for x in d92["exit_cycle_peak"] if x["offset_um"] == m92.TOLERANCE_OFFSET_UM and x["r_exit_mm"] in R_EXIT_SWEEP_MM]
    c1_cycles = list(pool.map(exit_task, [(geo, liner, "zero interference", zero, tol, x["r_exit_mm"], 0.0, 0.0, f_band) for x in rows92]))
    for x92, mine in zip(rows92, c1_cycles, strict=True):
        same = all(mine[k] == x92[k] for k in ("peak_MPa", "peak_by_square_cell_MPa", "points", "drag_at_peak_N"))
        assert same, f"92's exit row at r {x92['r_exit_mm']} not reproduced: {mine['peak_MPa']} vs {x92['peak_MPa']}"
    ctl["flush_exit_rows_reproduce_92"] = {"r_exit_mm": [x["r_exit_mm"] for x in rows92],
                                           "fields": ["peak_MPa", "peak_by_square_cell_MPa", "points", "drag_at_peak_N"]}
    # The floor at the limit from the end points, then the CYCLE at its adverse corner (and at the radius below, the
    # evidence that the floor is tight): a cycle at or above 1·σ_y where its end point is below moves the floor up.
    cycles, floor_limit = list(c1_cycles), {}
    first = {depth: smallest_safe([g for g in grid if g["depth_mm"] == depth]) for depth in DEPTHS_EXIT_MM}
    corner_check([(depth, r) for depth, r in first.items() if r is not None])
    ver = []                                              # (depth, radius, role) — run in one pool pass
    for depth, r_fl in first.items():
        if r_fl is None:
            continue
        ver.append((depth, r_fl, "at the floor"))
        below = max((r for r in R_EXIT_SWEEP_MM if r < r_fl), default=None)
        if below is not None:
            ver.append((depth, below, "below the floor"))

    def ver_task(depth: float, r_ex: float):
        g = adverse(depth, r_ex)
        return (geo, liner, g["play"], plays[g["play"]], tol, r_ex, depth, g["pad_ecc_mm"], f_band)
    for (depth, r_ex, role), cyc in zip(ver, pool.map(exit_task, [ver_task(dd, rr) for dd, rr, _ in ver]), strict=True):
        cycles.append({**cyc, "role": role, "end_point_peak_MPa": adverse(depth, r_ex)["peak_MPa"]})
    for depth in DEPTHS_EXIT_MM:
        r_fl, moved = first[depth], []
        while r_fl is not None:
            if not any(g["depth_mm"] == depth and g["r_exit_mm"] == r_fl for g in checked):
                corner_check([(depth, r_fl)])             # a radius the floor moved to (rare)
            cyc = next((c for c in cycles if c.get("role") and c["depth_mm"] == depth and c["r_exit_mm"] == r_fl), None)
            if cyc is None:
                cyc = {**exit_task(ver_task(depth, r_fl)), "role": "at the floor (moved)",
                       "end_point_peak_MPa": adverse(depth, r_fl)["peak_MPa"]}
                cycles.append(cyc)
            cells_here = [g for g in checked if g["depth_mm"] == depth and g["r_exit_mm"] == r_fl]
            if cyc["flow_verdict"]["1.0"] == "below" and all(g["flow_verdict"]["1.0"] == "below" for g in cells_here):
                break
            moved.append(r_fl)
            r_fl = min((r for r in R_EXIT_SWEEP_MM if r > r_fl), default=None)
        top = max((g for g in checked if g["depth_mm"] == depth and g["r_exit_mm"] == first[depth]), key=lambda g: g["peak_MPa"], default=None)
        floor_limit[f"{depth:g}"] = {"floor_mm": r_fl, "moved_up_from_mm": moved,
                                     "adverse_corner_is_the_max_at_first_floor": None if top is None else
                                     (top["play"], top["pad_ecc_mm"]) == corners[0]}
        worst = {r_ex: adverse(depth, r_ex)["peak_MPa"] for r_ex in R_EXIT_SWEEP_MM}
        print(f"  D {depth:4.2f}: worst end point by r " + " ".join(f"{r:g}:{v:.1f}" for r, v in worst.items())
              + f" → floor at the limit {r_fl}" + (f" (moved by the cycle from {moved})" if moved else ""))
    for c in cycles:
        if "role" in c:
            print(f"    cycle D {c['depth_mm']} r {c['r_exit_mm']} ({c['role']}, {c['play'][:24]}, e {c['pad_ecc_mm']:+}): "
                  f"{c['peak_MPa']} at drag {c['drag_at_peak_N']} · end point {c['end_point_peak_MPa']}")
    # The floor is a claim over the WHOLE tolerance, 0 … the limit: at each depth's floor, the end points at the interior
    # offsets on every play and couple at the loading end (+µ·F), and at the other end on the adverse corner; a crossing
    # moves the floor to the next swept radius.
    interior, floor_band = [], {}
    for depth in DEPTHS_EXIT_MM:
        r_fl = floor_limit[f"{depth:g}"]["floor_mm"]
        crossed_at = []
        while r_fl is not None:
            g = adverse(depth, r_fl)
            tasks = [(geo, liner, lab, plays[lab], e / 1000.0, r_fl, depth, ecc, f_band) for lab, ecc in corners
                     for e in INTERIOR_OFFSETS_UM]
            # the drag's OTHER end loads the exit's other wall, where the couple's adverse sense flips: both senses
            tasks += [(geo, liner, g["play"], plays[g["play"]], e / 1000.0, r_fl, depth, ecc, -f_band)
                      for e in INTERIOR_OFFSETS_UM for ecc in (min(PAD_ECC_MM), max(PAD_ECC_MM))]
            rows = list(pool.map(endpoint_task, tasks))
            interior += rows
            # the verdict of every SOLVED row first: a crossing moves the floor whatever else did not solve
            if all(r["below_1_sigma_y_on_every_grid"] for r in rows if r.get("exit_loaded")):
                break
            crossed_at.append(r_fl)
            r_fl = min((r for r in R_EXIT_SWEEP_MM if r > r_fl), default=None)
        unsolved = [r for r in interior if r["depth_mm"] == depth and r["r_exit_mm"] == r_fl and "not_solved" in r]
        floor_band[f"{depth:g}"] = {"floor_mm": r_fl, "moved_up_from_mm": crossed_at,
                                    "interior_rows_not_solved_at_the_floor": unsolved}   # a check NOT made, named
        worst_in = max((r["peak_MPa"] for r in interior if r["depth_mm"] == depth and r.get("exit_loaded")), default=None)
        print(f"  D {depth:4.2f}: floor over 0…{m92.TOLERANCE_OFFSET_UM} µm {r_fl} (crossed inside at {crossed_at}); "
              f"worst interior end-point peak {worst_in} MPa")

    # ── (d) the RATIFIED exit radius — the floor's procedure run AT it, on every depth ──────────────────────────────
    # ⚖️ founder 2026-11-02: one exit radius at every depth up to the deepest swept, so that it does not hang on a depth
    # the ring has not set yet. Before this block it was INFERRED there (the end point falls with r on every series at
    # the limit); here every play × couple, the full cycle and the interior offsets run at it — cells already computed
    # at that radius (a depth whose floor it is) are reused, not re-run.
    banner(f"(d) the ratified exit radius {RATIFIED_R_EXIT_MM} mm — every play × couple, the cycle, the interior offsets")
    r_rat = RATIFIED_R_EXIT_MM
    corner_check([(depth, r_rat) for depth in DEPTHS_EXIT_MM if not any(g["depth_mm"] == depth and g["r_exit_mm"] == r_rat for g in checked)])
    need_cyc = [depth for depth in DEPTHS_EXIT_MM if not any(c.get("role") and c["depth_mm"] == depth and c["r_exit_mm"] == r_rat for c in cycles)]
    for depth, cyc in zip(need_cyc, pool.map(exit_task, [ver_task(dd, r_rat) for dd in need_cyc]), strict=True):
        cycles.append({**cyc, "role": "at the ratified radius", "end_point_peak_MPa": adverse(depth, r_rat)["peak_MPa"]})
    need_in = [depth for depth in DEPTHS_EXIT_MM if not any(r["depth_mm"] == depth and r["r_exit_mm"] == r_rat for r in interior)]
    tasks = []
    for depth in need_in:
        g = adverse(depth, r_rat)
        tasks += [(geo, liner, lab, plays[lab], e / 1000.0, r_rat, depth, ecc, f_band) for lab, ecc in corners for e in INTERIOR_OFFSETS_UM]
        tasks += [(geo, liner, g["play"], plays[g["play"]], e / 1000.0, r_rat, depth, ecc, -f_band)
                  for e in INTERIOR_OFFSETS_UM for ecc in (min(PAD_ECC_MM), max(PAD_ECC_MM))]
    interior += list(pool.map(endpoint_task, tasks))
    ratified = {}
    for depth in DEPTHS_EXIT_MM:
        cells = [g for g in checked if g["depth_mm"] == depth and g["r_exit_mm"] == r_rat]
        cyc = next(c for c in cycles if c.get("role") and c["depth_mm"] == depth and c["r_exit_mm"] == r_rat)
        rows = [r for r in interior if r["depth_mm"] == depth and r["r_exit_mm"] == r_rat]
        solved = [r for r in rows if r.get("exit_loaded")]
        ratified[f"{depth:g}"] = {
            "corner_check_cells": len(cells), "corner_check_max_MPa": max(g["peak_MPa"] for g in cells),
            "cycle_peak_MPa": cyc["peak_MPa"], "cycle_role": cyc["role"],
            "cycle_corner": {"play": cyc["play"], "pad_ecc_mm": cyc["pad_ecc_mm"]},
            "interior_rows": len(rows), "interior_max_MPa": max((r["peak_MPa"] for r in solved), default=None),
            "interior_rows_not_solved": [r for r in rows if "not_solved" in r],   # a check NOT made, named
            "holds": (all(g["flow_verdict"]["1.0"] == "below" for g in cells) and cyc["flow_verdict"]["1.0"] == "below"
                      and all(r["below_1_sigma_y_on_every_grid"] for r in solved))}
        v = ratified[f"{depth:g}"]
        print(f"  D {depth:4.2f} r {r_rat}: every play × couple ≤ {v['corner_check_max_MPa']} MPa ({v['corner_check_cells']} cells), "
              f"cycle {v['cycle_peak_MPa']} ({v['cycle_role']}), interior ≤ {v['interior_max_MPa']} "
              f"({len(v['interior_rows_not_solved'])} of {v['interior_rows']} not solved) → holds {v['holds']}")

    # ── (c) what the depth costs ────────────────────────────────────────────────────────────────────────────────────
    banner("(c) the depth's cost — coaxial cycle (elastic, 91's path) and rigid closed forms; under the offset → 86's seam k")
    coax = list(pool.map(coaxial_task, [(geo, liner, zero, depth, r_ex, mu_max) for depth in DEPTHS_EXIT_MM for r_ex in R_EXIT_SWEEP_MM]))
    rig = [rigid_coaxial(geo, liner, zero, depth, r_ex, mu_max) for depth in DEPTHS_EXIT_MM for r_ex in R_EXIT_SWEEP_MM]
    pool.shutdown()
    # control (5)
    c5 = {"flush_vs_91_cycle": [], "countersink_vs_91": []}
    for c91 in (c for c in d91["cycle"] if c["base"] == "bonded" and c["modulus"] == "short-term" and c["r_edge_mm"] in R_EXIT_SWEEP_MM):
        mine = next(c for c in coax if c["depth_mm"] == 0.0 and c["r_exit_mm"] == c91["r_edge_mm"])
        assert abs(mine["peak_sigma_MPa"] - c91["peak_sigma_MPa"]) <= 6e-4 and \
            abs(mine["slide_per_cycle_um_at_mu_max"] - c91["slide_per_cycle_um_at_mu_max"]) <= 6e-5, (mine, c91["r_edge_mm"])
        c5["flush_vs_91_cycle"].append(c91["r_edge_mm"])
    for o91 in (o for o in d91["countersink"] if o["overhang_mm"] in DEPTHS_EXIT_MM):
        mine = next(c for c in coax if c["depth_mm"] == o91["overhang_mm"] and c["r_exit_mm"] == d91["inputs"]["r_edge_reference_mm"])
        mr = next(c for c in rig if c["depth_mm"] == o91["overhang_mm"] and c["r_exit_mm"] == d91["inputs"]["r_edge_reference_mm"])
        assert abs(mine["peak_sigma_MPa"] - o91["peak_sigma_MPa"]) <= 6e-4 and abs(mine["subcycle_range_MPa"] - o91["subcycle_range_MPa"]) <= 1.1e-3
        assert abs(mine["slide_per_cycle_um_at_mu_max"] - o91["slide_per_cycle_um_at_mu_max"]) <= 6e-5
        assert abs(mine["tip_past_bore_line_um_at_mu_max"] - o91["tip_past_bore_line_um_at_mu_max"]) <= 6e-4
        assert abs(mr["peak_rigid_touchdown_MPa"] - o91["peak_rigid_touchdown_same_edge_MPa"]) <= 6e-5
        assert abs(mr["full_drag_rigid_MPa"] - o91["full_drag_rigid_same_edge_MPa"]) <= 6e-4
        c5["countersink_vs_91"].append(o91["overhang_mm"])
    ctl["coaxial_rows_reproduce_91"] = c5
    # under the tolerance offset: the root's cycle, rigid, → 86's seam k
    g86 = d86["by_geometry"][geo.label]
    b86 = d86["branches"]["loose_50"]["by_geometry"][geo.label]
    assert b86["k_break_even_binding"] == b86["k_break_even_max_over_alloys"], "86's binding k is not its max over alloys"
    w0 = offset_swing(rod, geo, zero, tol, f_band, 0.0, m92.R_EX_MM, 0.0)
    w92 = next(w for w in d92["rigid_swing"] if w["offset_um"] == m92.TOLERANCE_OFFSET_UM)["root_mean_amplitude_MPa"]
    assert list(w0) == w92, f"the rigid swing at depth 0 does not reproduce 92's row: {w0} vs {w92}"
    ctl["rigid_swing_reproduces_92"] = {"offset_um": m92.TOLERANCE_OFFSET_UM, "mean_amplitude_MPa": list(w0)}
    off_rows = []
    for depth in DEPTHS_EXIT_MM:
        for r_ex in R_EXIT_SWEEP_MM:
            cells = []
            for lab, pl in all_plays:
                for ecc in PAD_ECC_MM:
                    mean, amp = offset_swing(rod, geo, pl, tol, f_band, depth, r_ex, s55.F_POGO_N * ecc)
                    cells.append({"play": lab, "pad_ecc_mm": ecc, "mean_MPa": mean, "amplitude_MPa": amp,
                                  "k_seam_needed": k_seam(mean, amp, g86["by_alloy"])})
            worst = max(cells, key=lambda c: c["k_seam_needed"])
            off_rows.append({"depth_mm": depth, "r_exit_mm": r_ex, "worst": worst,
                             "k_seam_needed_no_couple_zero_interference": next(c["k_seam_needed"] for c in cells
                                                                               if c["pad_ecc_mm"] == 0.0 and c["play"] == "zero interference")})
    for depth in DEPTHS_EXIT_MM:
        c0 = next(c for c in coax if c["depth_mm"] == depth and c["r_exit_mm"] == m92.R_EX_MM)
        r0 = next(c for c in rig if c["depth_mm"] == depth and c["r_exit_mm"] == m92.R_EX_MM)
        o0 = next(o for o in off_rows if o["depth_mm"] == depth and o["r_exit_mm"] == m92.R_EX_MM)
        print(f"  D {depth:4.2f} (r {m92.R_EX_MM}): coaxial peak {c0['peak_sigma_MPa']:.3f}, sub-cycle {c0['subcycle_range_MPa']:.3f}, "
              f"slide {c0['slide_per_cycle_um_at_mu_max']:.3f} µm; couple ±0.5 mm amplitude {r0['pad_cycle']['amplitude_MPa']} mean "
              f"{r0['pad_cycle']['mean_MPa']}; at {m92.TOLERANCE_OFFSET_UM} µm worst k {o0['worst']['k_seam_needed']} "
              f"(86 binding {b86['k_break_even_binding']})")

    # ── the summary: per depth, the three quantities the ⚖️ weighs, each from a field above ──────────────────────────
    def reversal_depth(r_ex: float) -> float | None:
        """Where the coaxial full-drag root reverses (rigid wall, same edge), bisected — None if not within 0 … 2.5 mm."""
        def m(dd):
            return m91.rigid_point(geo, liner, zero, f_band, rod.L - dd - r_ex)["sigma_signed_MPa"]
        lo, hi = 0.0, 2.5
        if not m(lo) > 0 > m(hi):
            return None
        for _ in range(40):
            mid = 0.5 * (lo + hi)
            lo, hi = (mid, hi) if m(mid) > 0 else (lo, mid)
        return round(0.5 * (lo + hi), 3)
    per_depth = []
    for depth in DEPTHS_EXIT_MM:
        fl = floor_band[f"{depth:g}"]["floor_mm"]
        row = {"depth_mm": depth, "exit_radius_floor_over_tolerance_mm": fl,
               "interior_rows_not_solved_at_the_floor": len(floor_band[f"{depth:g}"]["interior_rows_not_solved_at_the_floor"]),
               "exit_radius_floor_at_limit_mm": floor_limit[f"{depth:g}"]["floor_mm"],
               "exit_radius_floor_at_limit_by_corner_mm": {k: v[f"{depth:g}"] for k, v in floors.items()}}
        if fl is not None:
            if depth > 0:
                rr = next(r for r in ring if r["depth_mm"] == depth and r["r_exit_mm"] == fl)
                row["ring_clearance_at_floor_um"] = rr["needed_radial_clearance_um"]
            cc = next(c for c in coax if c["depth_mm"] == depth and c["r_exit_mm"] == fl)
            row["coaxial_at_floor"] = {k: cc[k] for k in ("peak_sigma_MPa", "subcycle_range_MPa", "slide_per_cycle_um_at_mu_max")}
            row["k_seam_needed_at_floor"] = next(o["worst"]["k_seam_needed"] for o in off_rows if o["depth_mm"] == depth and o["r_exit_mm"] == fl)
        if depth > 0:
            row["ring_clearance_max_over_radii_um"] = max(r["needed_radial_clearance_um"] for r in ring if r["depth_mm"] == depth)
        per_depth.append(row)
    rev = {f"{r:g}": reversal_depth(r) for r in R_EXIT_SWEEP_MM}
    k_max = max(o["worst"]["k_seam_needed"] for o in off_rows)
    at_ratified = []                                      # what the ratified radius costs, per depth — the fields above, read at it
    for depth in DEPTHS_EXIT_MM:
        cc = next(c for c in coax if c["depth_mm"] == depth and c["r_exit_mm"] == r_rat)
        row = {"depth_mm": depth, **ratified[f"{depth:g}"],
               "interior_rows_not_solved": len(ratified[f"{depth:g}"]["interior_rows_not_solved"]),
               "coaxial": {k: cc[k] for k in ("peak_sigma_MPa", "subcycle_range_MPa", "slide_per_cycle_um_at_mu_max")},
               "k_seam_needed": next(o["worst"]["k_seam_needed"] for o in off_rows if o["depth_mm"] == depth and o["r_exit_mm"] == r_rat)}
        if depth > 0:
            row["ring_clearance_um"] = next(r["needed_radial_clearance_um"] for r in ring if r["depth_mm"] == depth and r["r_exit_mm"] == r_rat)
        at_ratified.append(row)
    summary = {"per_depth": per_depth, "coaxial_root_reverses_at_depth_mm_by_r_exit": rev,
               "k_seam_needed_max_all_rows": k_max, "k_seam_86_binding": b86["k_break_even_binding"],
               "ratified_exit_radius": {"r_exit_mm": r_rat, "verdict": "⚖️ founder 2026-11-02 (00_07 HW.34)",
                                        "holds_on_every_depth": all(r["holds"] for r in at_ratified),
                                        "peak_max_MPa": max(max(r["corner_check_max_MPa"], r["cycle_peak_MPa"], r["interior_max_MPa"] or 0.0)
                                                            for r in at_ratified),
                                        "per_depth": at_ratified},
               "adverse_corner_for_exit": {"play": corners[0][0], "pad_ecc_mm": corners[0][1]},
               "tolerance_offset_um": m92.TOLERANCE_OFFSET_UM,
               "pin_spring_force_N": s55.F_POGO_N,
               "increments_not_solved": [i for i in increments if "not_solved" in i]}
    elapsed = time.time() - t0
    out = {
        "question": "the countersunk exit: the ring bore's clearance over the channel, the exit radius's floor under the tolerance "
                    "offset, and the depth's cost to the rod — per depth (00_07 HW.34)",
        "inputs": {"geometry": geo.label, "pad_mm": geo.pad_mm, "gap_mm": geo.gap_mm, "depths_mm": list(DEPTHS_EXIT_MM),
                   "r_exit_sweep_mm": list(R_EXIT_SWEEP_MM), "pad_ecc_mm": list(PAD_ECC_MM), "pin_spring_force_N": s55.F_POGO_N,
                   "mu_max": mu_max, "drag_band_N": f_band, "drag_margin_N": list(DRAG_MARGIN_N), "offsets_a_um": list(OFFSETS_A_UM),
                   "offsets_margin_um": list(OFFSETS_MARGIN_UM), "tolerance_offset_um": m92.TOLERANCE_OFFSET_UM,
                   "interior_offsets_um": list(INTERIOR_OFFSETS_UM),
                   "radial_plays_um": plays_um, "r_in_mm": m92.R_IN_REFERENCE_MM,
                   "sigma_yield_PEEK_MPa_tensile_23C": SIGMA_YIELD_PEEK_PA / 1e6, "flow_constraint_factors_55": list(s55.CONTACT_CONSTRAINT_FACTORS),
                   "base_and_modulus": "bonded, short-term (92's frame)", "source": "91's rod and kernels, 92's solve and rigid LCP "
                   "(depth and couple threaded), 86's soderberg; 68's plays, 91's and 92's rows and 86's alloys loaded from their caches"},
        "controls": ctl,
        "ring_clearance": ring,
        "ring_band_rows": [{k: (round(v, 4) if isinstance(v, float) else v) for k, v in b.items()} for b in band],
        "ring_increments": [{k: (round(v, 5) if isinstance(v, float) else v) for k, v in i.items()} for i in increments],
        "exit_end_points_at_limit": grid,
        "exit_cycles": cycles,
        "exit_corners": [{"play": lab, "pad_ecc_mm": ecc} for lab, ecc in corners],
        "exit_floor_at_limit_by_corner_mm": floors,
        "exit_corner_check": checked,
        "exit_floor_at_limit": floor_limit,
        "exit_interior_offsets": interior,
        "exit_floor_over_tolerance": floor_band,
        "coaxial_elastic": coax,
        "coaxial_rigid": rig,
        "offset_root_cycle": off_rows,
        "summary": summary,
        "not_modelled": {
            "ring_position": "the ring bore's position tolerance against the channel adds to every clearance figure",
            "thermal": "no thermal term: the cold liner's radial pull-back and the PEEK's softening at service temperature",
            "closure": "the exit closure element (an elastomer, Ø~1.3, 02_02 §1.2) is not modelled; in the ring's bore it is a soft contact",
            "ring_itself": "the ring's retention, strength and the thickness floor it needs are not modelled — depth is priced from the rod's side only",
            "plane": "the drag, the offset and the couple act in one plane",
            "spring": "the pin's spring force is 55's 1.0 N; a P/N with a stiffer spring re-runs this script",
            "brackets": "(b) and (c) run bonded, short-term; 91's and 92's other brackets (frictionless, 20-year) are not re-run",
            "friction_wear": "no contact friction in (b), no wear; slides are frictionless kinematic ceilings (91's)"},
        "elapsed_s": round(elapsed, 1),
    }
    OUT_JSON.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    banner("summary")
    for row in per_depth:
        print(f"  D {row['depth_mm']:4.2f}: floor {row['exit_radius_floor_over_tolerance_mm']} (at the limit {row['exit_radius_floor_at_limit_mm']}) · ring at floor {row.get('ring_clearance_at_floor_um')} µm "
              f"(max over radii {row.get('ring_clearance_max_over_radii_um')}) · coaxial {row.get('coaxial_at_floor')} · k {row.get('k_seam_needed_at_floor')}")
    print(f"  coaxial root reverses at depth by r: {rev}; seam k needed ≤ {k_max} (86 binding {b86['k_break_even_binding']})")
    ra = summary["ratified_exit_radius"]
    print(f"  ratified r {r_rat} mm: holds on every depth {ra['holds_on_every_depth']}, peak ≤ {ra['peak_max_MPa']} MPa")
    print(f"\n  written {OUT_JSON} in {elapsed / 60:.1f} min")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--smoke":
        DEPTHS_MM, DEPTHS_EXIT_MM = (1.0,), (0.0, 1.0)
        R_EXIT_SWEEP_MM = (0.1, 0.2)
        OFFSETS_A_UM, OFFSETS_MARGIN_UM, INTERIOR_OFFSETS_UM = (0, 50), (75,), (40,)
        OUT_JSON = Path(sys.argv[2])
    elif len(sys.argv) != 1:
        sys.exit("usage: 116_countersink_ring_and_exit.py [--smoke <out.json>]")
    sys.exit(main())
