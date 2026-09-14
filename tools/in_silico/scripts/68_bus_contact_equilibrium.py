#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
HW.34 / HW.23 — WHERE the bus rod really meets the cathode channel, solved as a CONTACT problem.

WHY THIS EXISTS. Script 55 used to locate the wall contact under pogo drag by asking where the FREE
tip-loaded cantilever, under the FULL drag, first equals the radial play. That free shape is not an
equilibrium. Under a tip load the deflection grows monotonically from the root, so as the drag ramps up
the first station to reach the wall is the one FARTHEST from the root inside the channel — the pad
plane, where the liner ends flush — and from then on the drag is reacted there. This script solved the
contact problem instead (2026-09-14), and script 55's contact blocks are re-derived on the SAME solver
since: it lives in `lib.beam_contact` (one home) and both scripts import it.

WHAT STAYS HERE. The sweeps that price what script 55 does not model: a static RADIAL OFFSET and a
TILT of the channel axis relative to the root axis, an off-axis pogo contact, the fit's play. Both
offset and tilt are tolerance-stack quantities (each of cem/cathode_flange.json and cem/zone2_sleeve.json
declares its own concentricity), and neither is computed anywhere in the tree.

⚠️ READ THE GEOMETRY AXIS BEFORE ANY NUMBER. The unsupported PEEK gap — which sets both the mouth
station and the rod length — is derived in script 55 from `Z1_INSERTION_MM = 30`, an HW.8 PLACEHOLDER
that the tree has already measured to lie OUTSIDE the Zone-1 lock's own insertion window
(`MechanicalLock.InsertionWindowMm` in tools/cad, 00_07 HW.26 G1). Every table below is therefore
computed at the placeholder AND at both ends of the lock window (script 55's `geometries()`), and the
offset price moves by an order of magnitude between them. The radial play is likewise swept: the
zero-interference value AND the three rows of script 55's `interference_window` (the fit swells the tube
and eats the play).

MODEL. `lib.beam_contact`: Euler-Bernoulli beam, cubic Hermite elements, clamped at the anode root
(x = 0) — weld and anode body rigid. A rigid, frictionless wall along the channel from the mouth to the
pad plane. Unilateral contact by an active set on PRESCRIBED displacements, with the sign of every
reaction checked. Geometry, material, drag and the three insulation branches are IMPORTED from script
55 (digit-leading module name -> importlib, the script-24c pattern; importing does not run 55's main),
so the two scripts cannot drift apart on inputs.

CONTROLS asserted in-run, with what each one can and cannot catch:
  * coaxial drag above touchdown, bare member: root stress = 3·E·c·g/L² and the only contact is the pad
    plane — catches a wrong pad station, rod length or play; blind to the mouth station;
  * first offset past the play, bare member, when the mouth is the only contact: root stress =
    3·E·c·(e − g)/a² with a = the gap — catches a wrong mouth station;
  * no wall is violated at element MIDPOINTS — catches a contact the node set missed between nodes
    (in the lib solve);
  * a grazing-contact row agrees at two element sizes — a discretisation check on a row whose contact
    does not sit on a node;
  * the offsets that cycled the saddle-point solver solve without cycling;
  * the equilibrium residual closes — guards the linear solve ONLY; it holds for any EI or station;
  * the peak-moment station is READ from the moment field of every solve, never asserted by prose:
    the cache says on which rows the root is the peak-moment section and on which it is not.

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
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from lib import beam_contact as bc
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

_spec = importlib.util.spec_from_file_location("bus55", HERE / "55_bus_mechanical.py")
s55 = importlib.util.module_from_spec(_spec)
sys.modules["bus55"] = s55   # a dataclass under `from __future__ import annotations` resolves its module by name
_spec.loader.exec_module(s55)

OUT_JSON = CACHE_DIR / "mechanical" / "bus_contact_equilibrium.json"
BUS55_CACHE = CACHE_DIR / "mechanical" / "bus_mechanical.json"
MM_M = bc.MM_M
C_ROD_M = (s55.D_BUS / 2.0) * MM_M
ELEMENT_MM = bc.ELEMENT_MM
OFFSETS_UM = s55.OFFSETS_UM                          # one home with 55's seam inputs
REVERSING_OFFSETS_UM = s55.REVERSING_DRAG_OFFSETS_UM
CYCLED_OFFSETS_UM = (83, 86, 92, 130, 193, 197)   # cycled the saddle-point solver (adversarial review)
TILTS_MRAD = (1.0, 2.0, 3.0, 5.0, 9.0)

Geometry = s55.Geometry


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


PEAKS: dict[str, list[dict]] = {}   # block -> rows whose peak-moment station is NOT the root (derived per solve)


def solve(geo: Geometry, row: dict, play_mm: float, drag_N: float = 0.0, pad_moment_Nm: float = 0.0,
          offset_mm: float = 0.0, tilt_rad: float = 0.0, tilt_pivot_mm: float = 0.0,
          bonded: bool = True, h_mm: float = ELEMENT_MM, block: str = "other", tag: str = "") -> dict:
    """Contact equilibrium of the clamped rod (lib.beam_contact) in the cache's units: the SIGNED clamp
    moment in N·mm, the root fibre stress, the tip deflection and the merged contact zones — and the
    peak-moment station, collected per block so the cache can say where the root stops being the peak."""
    res = bc.solve(geo.channel(), s55.member_ei_at(geo, row, bonded), play_mm, drag_N=drag_N,
                   pad_moment_Nm=pad_moment_Nm, offset_mm=offset_mm, tilt_rad=tilt_rad,
                   tilt_pivot_mm=tilt_pivot_mm, h_mm=h_mm)
    if res["peak_moment_station_mm"] != 0.0:
        PEAKS.setdefault(block, []).append({"geometry": geo.label, "row": tag,
                                            "peak_moment_station_mm": round(float(res["peak_moment_station_mm"]), 2),
                                            "peak_over_root": round(float(abs(res["peak_moment_Nm"]) / max(1e-12, abs(res["moment_Nm_at_nodes"][0]))), 2)})
    return {"clamp_moment_Nmm_signed": res["clamp_moment_Nm"] / MM_M,
            "sigma_root_MPa": s55.root_sigma_MPa(res["clamp_moment_Nm"]),
            "tip_deflection_um": res["u"][-2] / MM_M * 1000.0, "contacts": res["contacts"],
            "peak_moment_station_mm": res["peak_moment_station_mm"]}


def main() -> int:
    banner("Bus rod in the cathode channel — contact equilibrium (HW.34 / HW.23)")
    geos = s55.geometries()
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
                rigid_closed = 3.0 * e_ti * c * (play * MM_M) / (geo.pad_mm * MM_M) ** 2 / 1e6   # rigid wall, bare member
                touchdown = 3.0 * s55.flexural_rigidity_Nm2(s55.D_BUS) * play * MM_M / (geo.pad_mm * MM_M) ** 3
                by_mu = {}
                for mu in s55.MU_SWEEP:
                    f_lat = mu * s55.F_POGO_N
                    bare = solve(geo, r, play, drag_N=f_lat, bonded=False, block="drag", tag=f"{r['branch']}/{play_label}/µ{mu}/bare")
                    bond = solve(geo, r, play, drag_N=f_lat, bonded=True, block="drag", tag=f"{r['branch']}/{play_label}/µ{mu}")
                    if f_lat > 1.001 * touchdown:
                        assert abs(bare["sigma_root_MPa"] - rigid_closed) <= 0.005 * rigid_closed, "rigid-wall root stress ≠ closed form"
                        assert [z["station_mm"] for z in bare["contacts"]] == [round(geo.pad_mm, 2)], "drag contact is not the pad plane"
                    # 🔴 The rigid-wall figure is the LOWER end of the root stress: the polymer wall on the Ti bore's edge
                    #    yields by R/k and the root moment grows by 3EI·(R/k)/L². The UPPER end needs no compliance model —
                    #    the rod cannot pass the Ti bore behind the polymer, so the same solve with the wall moved out by
                    #    the polymer's own wall gives it (the free cantilever F·L where the drag cannot reach the bore).
                    upper = solve(geo, r, play + r["coating_or_liner_mm"], drag_N=f_lat, bonded=True, block="drag",
                                  tag=f"{r['branch']}/{play_label}/µ{mu}/upper")
                    assert bond["sigma_root_MPa"] - 1e-9 <= upper["sigma_root_MPa"] <= s55.bending_stress_MPa(f_lat, geo.pad_mm) * 1.0001, \
                        "the upper end left [rigid wall, free cantilever]"
                    by_mu[str(mu)] = {"sigma_root_MPa_bare": round(bare["sigma_root_MPa"], 2),
                                      "sigma_root_MPa_bonded": round(bond["sigma_root_MPa"], 2),
                                      "sigma_root_MPa_upper_end": round(upper["sigma_root_MPa"], 2),
                                      "upper_end_is": ("Ti-bore stop — the polymer wall fully yielded" if upper["contacts"]
                                                       else "free cantilever — the drag cannot reach the Ti bore"),
                                      "contacts_bonded": bond["contacts"]}
                drag.append({"geometry": geo.label, "branch": r["branch"], "play": play_label,
                             "radial_play_um": round(play * 1000.0, 2),
                             "touchdown_drag_N": round(touchdown, 4), "rigid_wall_sigma_MPa_closed_form": round(rigid_closed, 2),
                             "coaxial_cap_bound": "LOWER end — rigid wall; a compliant polymer wall raises the root moment by "
                                                  "3EI·(R/k)/L², the Ti-bore stop or the free cantilever F·L is the UPPER end "
                                                  "(sigma_root_MPa_upper_end per µ); the contact compliance that places the "
                                                  "root in the bracket is measured nowhere",
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
                res = solve(geo, liner, play, offset_mm=e_um / 1000.0, block="offset", tag=f"{play_label}/{e_um} µm")
                exact[e_um] = res["sigma_root_MPa"]
                if e_um / 1000.0 <= play:
                    assert not res["contacts"] and res["sigma_root_MPa"] < 1e-6, "an offset inside the play bent the rod"
                per_e.append({"offset_um": e_um, "sigma_root_MPa": round(res["sigma_root_MPa"], 1), "contacts": res["contacts"]})
            past = [e for e in OFFSETS_UM if e / 1000.0 > play]
            # CONTROL on the MOUTH station: bare member, first offset past the play, mouth the only contact
            first = solve(geo, liner, play, offset_mm=past[0] / 1000.0, bonded=False, block="offset", tag=f"{play_label}/{past[0]} µm/bare")
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
        for e_um in REVERSING_OFFSETS_UM:
            m0 = solve(geo, liner, zero_play, offset_mm=e_um / 1000.0, block="reversing", tag=f"{e_um} µm/static")["clamp_moment_Nmm_signed"]
            mp = solve(geo, liner, zero_play, drag_N=+mu_worst * s55.F_POGO_N, offset_mm=e_um / 1000.0, block="reversing", tag=f"{e_um} µm/+drag")["clamp_moment_Nmm_signed"]
            mn = solve(geo, liner, zero_play, drag_N=-mu_worst * s55.F_POGO_N, offset_mm=e_um / 1000.0, block="reversing", tag=f"{e_um} µm/-drag")["clamp_moment_Nmm_signed"]
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
                        pad_moment_Nm=sgn * s55.F_POGO_N * pad_e_mm * MM_M, block="pad_moment", tag=f"e {sgn * pad_e_mm:+.1f} mm")
            pad.append({"geometry": geo.label, "eccentricity_mm": sgn * pad_e_mm,
                        "sigma_root_MPa": round(res["sigma_root_MPa"], 2)})

    # ── (e) tilt of the channel axis, three pivots ────────────────────────────────────────────────────
    tilts = []
    for geo in geos:
        for pivot_label, pivot in (("root", 0.0), ("mouth", geo.gap_mm), ("pad plane", geo.pad_mm)):
            reach = max(abs(geo.gap_mm - pivot), abs(geo.pad_mm - pivot))
            per_t = []
            for t in TILTS_MRAD:
                res = solve(geo, liner, zero_play, tilt_rad=t / 1000.0, tilt_pivot_mm=pivot, block="tilt", tag=f"{pivot_label}/{t} mrad")
                per_t.append({"tilt_mrad": t, "sigma_root_MPa": round(res["sigma_root_MPa"], 1),
                              "peak_moment_station_mm": round(res["peak_moment_station_mm"], 2)})
            tilts.append({"geometry": geo.label, "pivot": pivot_label, "pivot_mm": round(pivot, 2),
                          "tilt_taken_up_by_play_mrad": round(zero_play / reach * 1000.0, 3), "by_tilt": per_t})

    # ── controls: discretisation on a grazing row, and the offsets that cycled the old solver ─────────
    # The 75 µm row on the placeholder geometry has a mouth contact plus an upper-wall contact whose true station
    # (20.57 mm, continuum analytic solution of the 2026-09-14 adversarial review) falls BETWEEN nodes — the one
    # kind of row where element size can matter. The assert below only requires the two contacts to exist.
    geo0 = geos[0]
    graze_c = solve(geo0, liner, zero_play, offset_mm=0.075, block="control")
    graze_f = solve(geo0, liner, zero_play, offset_mm=0.075, h_mm=ELEMENT_MM / 2.0, block="control")
    assert len(graze_c["contacts"]) >= 2, "the discretisation row lost its second contact"
    assert abs(graze_f["sigma_root_MPa"] - graze_c["sigma_root_MPa"]) <= 0.005 * graze_c["sigma_root_MPa"], "not mesh-converged"
    for geo in geos:
        for e_um in CYCLED_OFFSETS_UM:
            solve(geo, liner, zero_play, offset_mm=e_um / 1000.0, block="control")   # raises on a cycle

    # ── the peak-moment section, DERIVED from the moment field of every solve above ─────────────────────
    # ⛔ «in every configuration computed here the root is the peak-moment section» stood in this cache as
    #    prose from the first run. Read from the moment field it is TRUE for every drag, offset and
    #    reversing-drag row (asserted) and FALSE on the lock-window geometry for two classes the prose had
    #    not looked at: the largest swept tilt about the MOUTH (the play is taken up on both walls and the rod
    #    bends between them with a small root moment) and the pogo couple on the rod's end face (the applied
    #    couple at the EXIT exceeds the small root moment of a long rod). Both are reported, not asserted away.
    for block in ("drag", "offset", "reversing"):
        assert block not in PEAKS, f"the peak moment left the root in a {block} row: {PEAKS.get(block)}"
    peak_summary = {"root_is_peak_in_every_drag_offset_and_reversing_row": True,
                    "rows_where_the_peak_leaves_the_root": {b: PEAKS.get(b, []) for b in ("tilt", "pad_moment")},
                    "note": "read from EI·w'' at every node of every solve (linear inside an element, so the "
                            "extreme is at a node). The exceptions are the lock-window rows where a tilt about the "
                            "mouth takes up the play on both walls, and where the pogo couple applied at the exit "
                            "exceeds the root moment of the long rod"}

    placeholder, near, far = geos
    _zero = {g.label: next(d for d in drag if d["geometry"] == g.label and d["play"] == "zero interference"
                           and d["branch"].startswith("PEEK liner"))["by_mu"][str(mu_worst)] for g in geos}
    cap_zero = {k: v["sigma_root_MPa_bonded"] for k, v in _zero.items()}
    upper_zero = {k: v["sigma_root_MPa_upper_end"] for k, v in _zero.items()}
    sec_zero = {o["geometry"]: o["secant_MPa_per_um"] for o in offsets if o["play"] == "zero interference"}
    s55_cache = json.loads(BUS55_CACHE.read_text(encoding="utf-8"))
    s55_column = s55_cache["clearance_regime"]["supported_column_vs_equilibrium"]["supported_column_sigma_MPa"]["nominal_mu"]
    s55_caps = {g["geometry"]: g["coaxial_cap_MPa_bonded"]
                for g in s55_cache["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"]}
    s55_upper = {g["geometry"]: g["bracket_MPa_worst_mu"][1]
                 for g in s55_cache["clearance_regime"]["supported_column_vs_equilibrium"]["by_geometry"]}
    # CONTROL across the two scripts: the same solver on the same inputs must give the same bracket ends — a
    # divergence here means the two scripts disagree on geometry, member or play, never on physics.
    assert s55_caps == cap_zero, f"script 55 and 68 disagree on the coaxial cap: {s55_caps} vs {cap_zero}"
    assert s55_upper == upper_zero, f"script 55 and 68 disagree on the upper end: {s55_upper} vs {upper_zero}"
    lock_caps = sorted((cap_zero[near.label], cap_zero[far.label]))
    lock_secants = sorted((sec_zero[near.label], sec_zero[far.label]))
    pad_peak = {g.label: max(p["sigma_root_MPa"] for p in pad if p["geometry"] == g.label) for g in geos}
    lock_pad = sorted((pad_peak[near.label], pad_peak[far.label]))
    amp_max = {g.label: max(r_["sigma_amplitude_MPa"] for r_ in reversing if r_["geometry"] == g.label) for g in geos}
    amp_clause = "; ".join(
        f"{g.label}: up to {amp_max[g.label]:.2f} MPa against its cap {cap_zero[g.label]:.2f}"
        + (" (within it)" if amp_max[g.label] <= cap_zero[g.label] + 0.005 else " (ABOVE it)")
        for g in geos)
    _exceptions = [f"{b} {p['geometry']} {p['row']}" for b, rows_ in peak_summary["rows_where_the_peak_leaves_the_root"].items() for p in rows_]
    peak_clause = ("the root is the peak-moment section in every drag, offset and reversing-drag row; it leaves the root only in "
                   + ", ".join(_exceptions) if _exceptions else
                   "the root is the peak-moment section in every row computed here")

    out = {
        "question": "Where does the bus rod meet the cathode channel under pogo drag, and what does a channel axis "
                    "off the root axis cost — solved as contact equilibrium, not read off a free cantilever "
                    "(00_07 HW.34 / HW.23)",
        "inputs": {
            "source": "imported from 55_bus_mechanical.py; the channel run, flange and sleeve lengths come from "
                      "cem/*.json via 55, but the unsupported GAP depends on the Zone-1 insertion, which in 55 is the "
                      "HW.8 PLACEHOLDER Z1_INSERTION_MM — swept here against the Zone-1 lock window",
            "insertion_placeholder_mm": s55.Z1_INSERTION_MM,
            "lock_insertion_window_mm": list(s55.lock_insertion_window_mm()),
            "lock_window_source": "cem/mechanical_lock.zone1.json, formula of MechanicalLock.InsertionWindowMm "
                                  "(tools/cad) — by-value crossing, not gated here",
            "geometries": [g.__dict__ for g in geos],
            "radial_plays_um": {label: round(p * 1000.0, 2) for label, p in plays},
            "radial_play_source": "zero interference from the CEM diameters; the rest loaded from 55's cache "
                                  "interference_window.od_growth_eats_channel_play",
            "rod_dia_mm": s55.D_BUS, "E_Ti_Pa": e_ti, "E_PEEK_Pa": s55.E_PEEK_PA,
            "pogo_force_N": s55.F_POGO_N, "mu_sweep": list(s55.MU_SWEEP), "element_mm": ELEMENT_MM,
            "solver": "lib.beam_contact (one home; script 55's contact blocks use the same solver since 2026-09-14)",
        },
        "drag_coaxial": drag,
        "offset_static_shipped_branch": offsets,
        "reversing_drag_on_offset": reversing,
        "pad_moment_at_rod_radius": pad,
        "tilt_static_shipped_branch": tilts,
        "peak_moment_section": peak_summary,
        "script55_side_by_side": {
            "script55_supported_column_sigma_nominal_MPa": s55_column,
            "script55_supported_column_note": "µ_nominal·F on the 6 mm PEEK gap propped where the bore begins — the §2 "
                                              "«supported» idealisation; script 55 measures it against these caps itself "
                                              "(clearance_regime.supported_column_vs_equilibrium)",
            "script55_coaxial_cap_MPa_at_worst_mu_bonded": s55_caps,
            "equilibrium_coaxial_cap_MPa_at_worst_mu_bonded": cap_zero,
            "caps_agree": s55_caps == cap_zero,
            "coaxial_cap_bound": "LOWER end — rigid wall; see drag_coaxial[].coaxial_cap_bound",
            "script55_upper_end_MPa_at_worst_mu": s55_upper,
            "equilibrium_upper_end_MPa_at_worst_mu": upper_zero,
            "upper_ends_agree": s55_upper == upper_zero,
        },
        "summary": (
            f"Coaxial channel: under pogo drag the rod meets the wall only at the pad plane, where the tube ends flush; "
            f"against a RIGID wall the root stress is µ-invariant — {cap_zero[placeholder.label]:.2f} MPa on script 55's "
            f"placeholder geometry, {lock_caps[0]:.2f}–{lock_caps[1]:.2f} MPa across the Zone-1 lock "
            f"window (zero-interference play, bonded member) — and that figure is the LOWER end of the root stress: the "
            f"polymer wall on the Ti bore's edge yields by R/k, and the upper end (the Ti-bore stop, or the free cantilever "
            f"where the drag cannot reach the bore) is {upper_zero[placeholder.label]:.1f} MPa on the placeholder and "
            f"{min(upper_zero[near.label], upper_zero[far.label]):.1f}–{max(upper_zero[near.label], upper_zero[far.label]):.1f} MPa "
            f"across the lock window at the worst swept µ; where in that bracket the root sits is set by the contact "
            f"compliance, measured nowhere. Script 55's 6 mm supported column prices that section at "
            f"{s55_column:.2f} MPa nominal — above the rigid-wall end on every geometry, inside the bracket. Channel off the "
            f"root axis: past the play the mouth becomes a contact station and the STATIC root bending grows at a "
            f"secant {sec_zero[placeholder.label]:.2f} MPa/µm on the placeholder and "
            f"{lock_secants[0]:.2f}–{lock_secants[1]:.2f} "
            f"MPa/µm across the lock window — the insertion placeholder moves the offset price by an order of "
            f"magnitude. Reversing drag on a static offset, amplitude over the swept offsets — {amp_clause}. A pogo "
            f"contact off the rod axis by the rod radius, with the worst drag, gives up to {pad_peak[placeholder.label]:.2f} MPa "
            f"on the placeholder and {lock_pad[0]:.2f}–{lock_pad[1]:.2f} MPa across the lock window — above the drag cap there. "
            f"The tilt price depends on the PIVOT (root · mouth · pad plane) far more than on the angle. Peak moment: {peak_clause}. "
            f"MEASURED: contact stations and root stress for swept geometry, play, offset, tilt and pad moment. NOT "
            f"computed: what the stack delivers, contact pressure, a varying offset's amplitude, weld compliance. "
            f"No verdict is taken here."
        ),
        "not_modelled": {
            "wall": "rigid and frictionless — no liner compliance, no contact pressure, no axial traction. The SIGN of "
                    "that omission differs by regime: under coaxial DRAG the rigid-wall root stress is the LOWER end — a "
                    "compliant polymer wall lets the exit yield by R/k and raises the root moment by 3EI·(R/k)/L², up to "
                    "the Ti-bore stop or the free cantilever (drag_coaxial[].by_mu[].sigma_root_MPa_upper_end); past "
                    "the play under an OFFSET the mouth corner would load the PEEK tube beyond its compressive strength at "
                    "the larger offsets, so offset stresses are UPPER bounds. The contact compliance that places either "
                    "is measured nowhere",
            "clamp": "perfect — weld and printed-anode compliance lower every stress",
            "swept_not_measured": "insertion, play, offset, tilt and pad eccentricity",
            "mean_stress": "a static offset is a mean stress; no Goodman-type correction; the amplitude of a varying "
                           "offset needs relative Zone-1<->Zone-3 motion, measured nowhere",
            "drag_contact_edge": "the drag contact is the flush tube end at the pad-plane exit — ring on ring, the "
                                 "edge form the ≥ 1.0 mm protrusion avoids at the mouth — and no exit radius is "
                                 "specified anywhere; the wall reaction there is the drag minus the touchdown force "
                                 "on every cycle",
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
