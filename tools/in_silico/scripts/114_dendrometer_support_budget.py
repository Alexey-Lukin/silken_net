#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""114 — whether a point dendrometer that uses the anchor as its support can hold its reading: the support's thermal
artefact per fixation point, the magnetic scale behind the capsule wall (its period, the sensor's error terms and the
unwrap margin through winter and outages), the energy of a read, and how soon the bark passes the capsule (00_07
HW.54, the leg «Р3(в) — дендрометр», its instrument plan of 2026-10-30).

WHY. The desk leg of 2026-10-26 (01_03 §4 ⊕, (в)) left the principle standing and named the weakest links: the scale's
travel and geometry, the support's thermal path with PEEK in it («≈ 5–10× worse than < 0.3 µm/K of commercial frames» —
the collector's derivation, not re-read), a pole counter that must not lose its count across a winter swing «ten times
the seasonal one» and the outages of the same nights, and the energy of a read. This script turns each into a number
the tree can check, from inputs the tree already holds.

MODEL.
(1) THE SUPPORT'S THERMAL ARTEFACT. Depth z runs from the flange seat (0) into the stem. The anchor is held by the wood
    at a fixation depth z_f; the live bark the probe rests on lies z_t below the seat (the dead bark is cut away under
    the probe); the sensor sits h above the seat; the scale runs from the probe's tip up to the sensor. Under a uniform
    ΔT the reading moves, per kelvin, by
        A = ∫₀^{z_f} (α_w − α_anchor(z)) dz + (α_s − α_w)·z_t + (α_s − α_h)·h
    — the closure of the loop fixation → anchor → holder → scale → bark → wood → fixation (controls 1–2). A > 0 reads
    as growth on warming; A < 0 reads as shrinkage on warming and as swelling on cooling — at dawn, the coldest hour,
    which is when a stem rehydrates and when the zero-growth method credits new growth. The first term is the ANCHOR's,
    on `103`'s sections read from its cache: the PEEK sleeve over the span (under a Zone-3 fit only below the shank's
    composite run), then the Zone-1 shank in the sleeve's bottom, then the gyroid. The shank is read two ways: BONDED to
    the sleeve by its fit (`103`'s reading) and ON ITS SHOULDER — the fit slips (PEEK relaxes), the sleeve rests on the
    gyroid's shoulder, and the whole sleeve down to it is PEEK in the path: the adverse end for |A|. The other two terms
    are DESIGN terms (the scale's and the holder's material, the sensor's height); the base reading sets them to zero and
    the cache states their sensitivity. The anchor term cannot be designed away until the fixation is known: named
    points from a callus tie (`103`'s axis: from just under the flange down to the install-day cambium, the deepest it
    can sit — it climbs toward the flange as the stem grows, so A drifts year by year) to an anode bond along the
    gyroid; the depth at which |A| crosses the frames' 0.3 µm/K is solved exactly per reading.
    THE BARK BEARING is not a thermal term and not a point on this axis: a flange that bears on the dead bark ties the
    reference to the surface being measured. The flange then sits between two springs — the deep wood through the anode
    bond and the sleeve in series (1/k_A + 1/k_s) and the bark through the bearing (k_F) — so it follows a radial change
    of the bark by U = (1/k_A + 1/k_s)/(1/k_A + 1/k_s + 1/k_F), and the reading loses that fraction (U → 1 for a rigid
    bark: no measurement). Priced on `103`'s stiffnesses for premise (b), sway and slow (relaxed PEEK) — our reading of
    a growth push as a displacement source; under premise (a) the shank sits in clearance, so a rising bark can lift
    the flange off the sleeve and leave no reference at all (our reading — `103` does not model lift-off).
(2) THE SCALE BEHIND THE WALL. The sensor sits inside the capsule; the scale slides outside it, so the read gap g is
    at least the radome's wall. A periodically magnetised scale of period P, thickness t and remanence B_r gives, in our
    idealisation (sinusoidal magnetisation, infinite width), a field of amplitude B = (B_r/2)·(1 − e^{−kt})·e^{−kg},
    k = 2π/P, its two components in quadrature; a two-axis Hall sensor reads the phase by atan2, and a COMMON gain
    (with it the magnet's temperature coefficient) cancels. What does not cancel, per the sensor's datasheet:
      offset drift — δB on each component moves the reading by up to (P/2π)·√2·δB/B; the scan finds the period P*
        that minimises it at a gap (for t → ∞, P* = 2πg — control 3) and the cache gives the B_r a scale NEEDS for this
        term alone to stay within 0.3 µm/K, the field it then puts on the sensor against its linear range, and the
        two-channel samples a read needs for 1 µm of noise there (the angle's RMS noise is σ/B, so at the needed B_r it
        is σ·0.3 µm/(√2·δB) whatever the geometry);
      gain MISMATCH between the two axes — a static ε gives a cyclic error (P/2π)·(ε/2); the datasheet gives its drift
        «from 25 °C» over the operating range with no per-kelvin basis, so the cache prints the cyclic peak over that
        whole drift, and a per-kelvin figure only under a stated linear spread (to −40 ⊥ +125 °C — an assumed operating
        range, not among the rows read);
      ANGLE error — static and cyclic, P·AERR/360; calibrating it IN PLACE needs the scale to pass a full period, i.e. years of
        growth.
    Both pairs of axes are printed: X–Y (both axes in the field's plane, which needs the IC mounted edge-on) and X–Z
    (the IC flat on the board). THE SENSOR'S LINEAR RANGE caps the period: the field the offset term needs at the sensor
    is P·√2·δB/(2π·target) — the period alone sets it, not the magnet and not the thickness — so a period above
    P_cap = 2π·target·B_lin/(√2·δB) asks for a field the sensor cannot read linearly; each row prints, per range and
    drift, the best period inside the cap and the remanence needed THERE, and the magnet families with a class at or
    above it (`MAGNET_FAMILIES_BR_T`, a canon mirror). THE THICKNESS KNOB (2b): the same row at t 3 · 5 · 10 mm in a
    block of its own, with its remanence and period over the t 2 mm row's — a thicker scale lowers the remanence at a
    longer P*, and the longer P* raises the field needed and the angle and mismatch errors with it. THE COUNT across periods: the device sends the phase, the server unwraps the series —
    nothing is persisted on the device (its RTC backup domain does not survive an outage on our board, 03_01). The
    unwrap holds while every change between two delivered readings stays under P/2 (an absolute-in-period phase; the
    collector's «half a pole» was for an incremental pole counter, a different reader); the change is priced on a
    declared, season-consistent basis and the period each basis requires and every geometry's margin are printed.
(3) THE ENERGY OF A READ. The read rides the node's existing wake (cadence C): the sensor's wake and measure transitions
    once, then N two-channel samples at its active current, with the core awake throughout at its run current (02_03
    §9.4's mruby member — a ceiling: the core could sleep through a conversion; the bus transfer is not in the tree),
    taken from VSTOR through the active buck. Printed against the node's demand (`110`'s) and E_CYCLE, beside an
    absolute encoder IC of 2 mm period at its power-up current and time with the core awake through it.
(4) THE TRAVEL WINDOW. Years until the live bark under the probe reaches the flange seat, and until the outer bark
    around the capsule reaches the dome's top (`Radome.cs`'s top over the rim, on the flange's top face), at the
    slowest and the fastest radial increment the desk leg names.

INPUTS — each with its home: geometry, the anchor's α sections, the bearing's share and the green xylem's α (Sevanto et
al. 2005, P. sylvestris, radial) from `103`'s cache; the flange's and the cambium's hottest hour from `78`'s; the
radome's and the flange's dimensions from their CEMs; cadence C and the demand from `110`'s cache; E_CYCLE and the
active buck from lib; the core's run current and VOUT from 02_03 §9.4 (mirrors below); air temperature from the ERA5
hourly record `71` loads; the Hall sensor's rows from its datasheet (TI SLYS045, §5.7 for A1 and §5.11, read
2026-10-31); the encoder's, the frames' temperature sensitivity and the growth rates from the primaries the 2026-10-26
collection read (provenance: handoff `2026-10-26_r3v_dendrometer.json`); the frost swing, the daily swing and the radial
rate's ends from 01_03 §4 ⊕ (в).

WHAT IT CANNOT SEE.
  (1) Where the anchor is held — an axis of named points; a hold shared between bearing, tie and bond is priced only as
      the bearing's share in (1), not solved; and the bearing only with the anode bonded (before ingrowth the deep tie
      is the sleeve's grip, which `103` leaves unbounded). A hold shallower than the live bark sits in the dead bark, whose
      α is taken at the xylem's like the phloem's — and which follows the bark as the bearing does.
  (2) The temperatures. The model is uniform-ΔT and the µm figures use the AIR (ERA5) as a stem-interior proxy, NOT a
      bound: the top of the sleeve sits under the Ti flange, which in sun runs far above the air and at night radiates
      to the sky (`78`). Frozen wood's strain is not thermal expansion, so the seasonal figure uses unfrozen days only and
      the frost swing enters (2) as a travel.
  (3) The phloem and the callus at the xylem's α (no reading of either); α_xylem as one reading (the cache gives the
      sensitivity per ppm/K, the green-wood bracket in the collection is wide) — the anchor term's sign rests on it: the
      gyroid exceeds it by 0.7 ppm/K, the bonded Zone-1 composite by 1.5, the Zone-3 composite by 1.9. The design terms are nulled, not zero: their sign is the
      scale's and the holder's material, still open.
  (4) The field is an idealisation (finite width, pole-pitch errors, a ferromagnetic neighbour); the magnet is not
      chosen, so (2) gives the remanence a scale NEEDS, not one a product has; the families it is held against are a
      mirror of the canon's desk (specified minima per family, ferrite typical), not a product's datasheet, and «meets»
      says only that some class of the family reaches the need — not its corrosion, its temperature coefficient or
      whether a scale of that class and thickness is made. The sensor's mismatch drift has no per-kelvin basis in its
      datasheet, and its offset drift is taken as one row for both ranges.
  (5) Whether a scale and a probe can travel 16–100 mm past a flush capsule without a visit — the geometry (01_04
      §5.5); (4) says only when the problem starts.
  (6) Separating reversible shrinkage (TWD) from growth — the zero-growth method's job, not priced here.
  (7) The budget: the frames' 0.3 µm/K is the whole instrument's; (1) and (2) each print against it alone, so what
      the instrument meets is their sum with the mismatch term — not computed as one number, because the support's
      term is a maximum over unknown fixations and the sensor's offset term a design target, not properties.

CONTROLS (each says what it CAN and CANNOT catch).
  (1) Closure: with one α everywhere A = 0 at every fixation depth, probe depth and sensor height; CAN catch a term with
      no partner, CANNOT a flipped or a dropped pair (that is (2)'s).
  (2) Unit impulses against the node positions derived independently: α_w = 1 alone → z_f − z_t; α_s = 1 → z_t + h;
      α_h = 1 → −h; α = 1 on one anchor section → −(its length above z_f); CAN catch a flipped, dropped or mis-weighted
      term, CANNOT a wrong section in `103`'s cache.
  (3) Sections: they tile the anchor from 0, end at `103`'s full depth, put the gyroid's centre on `103`'s nominal anode
      centroid, and carry, down to the shank's top, `103`'s PEEK length of the premise; CAN catch a misread length or a
      section dropped, CANNOT a swap of two sections that keeps the PEEK length (both readings come from one cache).
  (4) Field: for a very thick scale the scanned P* equals 2πg within the scan's step, and at the needed B_r the field
      equals P·√2·δB/(2π·target) by a separate route; CAN catch a slip in the exponent, its factor or the (1 − e^{−kt})
      term in either function, CANNOT an error in the idealised field form itself.
  (5) Energy: the same function and buck give lib's E_CYCLE from 02_03 §9.4's members; CAN catch a buck applied the
      wrong way or lib drifting from §9.4, CANNOT a wrong sensor current.
  (6) The ERA5 record has `110`'s hour count; CAN catch a truncated or a different file, CANNOT a shifted clock.
  (7) Monotone support: every anchor section's α exceeds α_w, so |A| grows with depth and the crossing is unique —
      asserted, not assumed; and |A| at the solved crossing equals 0.3 µm/K; CAN catch a wrong slope or bookkeeping in
      the solve, CANNOT a wrong section (that is (3)'s).
  (8) Thickness and cap: per gap and drift a thicker scale needs strictly less B_r at a P* that grows with t and stays
      at or under 2πg; the field needed at P_cap equals the linear range by a separate route; no capped period overruns
      its cap; CAN catch a sign slip in the (1 − e^{−kt}) term, a cap applied the wrong way or a scan past it, CANNOT
      an error in the idealised field form.

Run:  python tools/in_silico/scripts/114_dendrometer_support_budget.py      # a few seconds
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import ALPHA_PEEK_1K, CACHE_DIR, E_CYCLE, ETA_BUCK_ACTIVE, KINETICS_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("Whether a point dendrometer that uses the anchor as its support can hold its reading: the thermal "
                  "artefact of the support per fixation depth, the period a magnetic scale needs behind the capsule wall "
                  "and the error terms of a two-axis Hall sensor reading it, the unwrap margin through winter swings and "
                  "power outages, the energy of a read, and how soon the growing bark passes the capsule.")

HERE = Path(__file__).resolve().parent
OUT = CACHE_DIR / "mechanical" / "dendrometer_support_budget.json"
WOOD_SHARE = CACHE_DIR / "mechanical" / "anchor_wood_share.json"        # `103`
FLANGE_HEAT = CACHE_DIR / "thermal" / "flange_cambium_heat.json"         # `78`
PV_AUTONOMY = KINETICS_DIR / "winter_pv_autonomy.json"                   # `110`
RADOME_CEM = REPO_ROOT / "tools/cad/cem/radome.json"
FLANGE_CEM = REPO_ROOT / "tools/cad/cem/cathode_flange.json"

# 02_03 §9.4 — the core's run current and VOUT of the mruby member, and the members E_CYCLE is built from (mirrors)
I_CORE_RUN_A = 8e-3
V_OUT = 3.3
CYCLE_MEMBERS_J = {"mruby": (8e-3, 0.15), "tx_14dbm_sf9": (23.5e-3, 0.1649)}
E_RADIO_RX_TCXO_J = 12.58e-3
# TI TMAG5273 (SLYS045, §5.7 «A1, B1, C1, D1», §5.11): active current (LP_LN = 0); conversion with CONV_AVG = 101b,
# one channel, +32 × 25 µs per extra channel; sleep → standby and standby → measure; sleep current; RMS noise at
# CONV_AVG = 101b; offset drift typ ⊥ max; sensitivity-mismatch drift «from 25 °C» per axis pair; angle error per pair
# (25 °C, CONV_AVG = 101b); linear range at RANGE = 0b ⊥ 1b
HALL = {"i_active_A": 2.3e-3, "t_conv_one_ch_s": 825e-6, "t_add_ch_s": 800e-6,
        "t_sleep_to_standby_s": 50e-6, "t_standby_to_measure_s": 70e-6, "i_sleep_A": 5e-9,
        "noise_T": {"x_y": 22e-6, "z": 11e-6}, "offset_drift_T_per_K": {"typ": 3e-6, "max": 10e-6},
        "sens_mismatch_drift": {"x_y": 0.05, "x_z": 0.15}, "angle_error_deg": {"x_y": 0.5, "x_z": 1.0},
        "linear_range_T": (0.040, 0.080)}
MISMATCH_LINEAR_SPREAD_K = (65.0, 100.0)   # IF the drift spread linearly to −40 ⊥ +125 °C — an assumption, printed
# ams AS5311 (rev 1.13): supply current, power-up time; pole length 1.0 mm → a 2.0 mm magnetic period
ENCODER_2MM = {"i_supply_A": {"typ": 16e-3, "max": 21e-3}, "t_power_up_s": 20e-3, "period_mm": 2.0}
# The frames' temperature sensitivity — Natkon ZN11 «< 0.3 µm °C⁻¹» (Zweifel et al. 2021, New Phytol., Methods)
FRAME_UM_PER_K = 0.3
# Growth: P. sylvestris GRO.yr 795 µm and GRO.hr 2.29 µm h⁻¹ (Zweifel 2021 New Phytol. 10.1111/nph.17552, Table 1);
# 0.8 mm yr⁻¹ over 29 growth days (Etzold et al. 2022 Ecol. Lett. 10.1111/ele.13933); reliable resolution 1–5 µm
# (Zweifel et al. 2021 Front. For. Glob. Change 10.3389/ffgc.2021.776905, p. 9)
GROWTH = {"yr_um": 795.0, "hr_um": 2.29, "dry_site_um_per_growth_day": round(800.0 / 29.0, 1),
          "resolution_um": (1.0, 5.0)}
# 01_03 §4 ⊕ (в): the winter frost swing (our ×10 of the daily swing), the daily swing and the radial rate's ends
FROST_SWING_MM = (1.0, 2.0)
DAILY_SWING_MM = (0.1, 0.2)
RADIAL_RATE_MM_PER_YR = (0.8, 5.0)
GROWTH_MONTHS_MIN = 4.0                    # our assumption: the year's increment is laid down over at least four months
NOISE_TARGET_UM = 1.0
GAPS_MM = (1.5, 2.0, 3.0, 4.0)             # the radome wall's band, then the wall plus clearances (not in the tree)
SCALE_T_MM = (1.0, 2.0)
# The thickness knob (01_03 §4 ⊕ (в), desk 2026-11-10: «t 3–10 mm»), priced in its OWN block so the base table's
# population — which the canon's «one cell passes» and the in-place calibration span are quantified over — stays t 1–2 mm
SCALE_T_KNOB_MM = (3.0, 5.0, 10.0)
# Magnet families against the remanence a scale needs — mirror of 01_03 §4 ⊕ (в), desk 2026-11-10 (edit THERE): the
# range of specified MINIMA over each family's classes, IEC 60404-8-1:2001/AMD1:2004 Tables 11–12 (iTeh preview); sintered
# ferrite from MMPA 0100-00 Table III-1, TYPICAL values, not minima. A family «meets» a need when its highest value does —
# i.e. at least one of its classes; which class, and its corrosion and temperature coefficient, the canon says
MAGNET_FAMILIES_BR_T = {"RECo5": (0.80, 0.93), "RE2Co17": (0.90, 1.10), "REFeB_sintered": (0.98, 1.42),
                        "ferrite_sintered_typical": (0.23, 0.41)}
TIE_SHALLOWEST_MM = 0.5                    # `103`'s DEPTH_MIN — its tie axis starts here


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def anchor_sections(z103: dict, premise: str, shank: str) -> list[tuple[float, float, float]]:
    """The anchor from the flange seat down, as (from_mm, to_mm, α in 1/K): `103`'s premise, the Zone-1 shank bonded
    by its fit or the sleeve resting on the gyroid's shoulder (PEEK down to it)."""
    g, inp = z103["geometry"], z103["inputs"]
    span, z1 = g["span_mm"], g["zone1_shank_in_sleeve"]
    if premise == "flange_on_bark":
        top = [(0.0, span, ALPHA_PEEK_1K)]
    else:
        z3 = z103["zone3_fit"]
        run, gap = z3["sections_mm"]["composite_run"], z3["sections_mm"]["peek_gap"]
        top = [(run[0], run[1], z3["alpha_composite_ppm_K"] * 1e-6), (gap[0], gap[1], ALPHA_PEEK_1K)]
    shank_end = span + z1["length_mm"]
    shank_alpha = z1["alpha_bonded_ppm_K"] * 1e-6 if shank == "bonded" else ALPHA_PEEK_1K
    return [*top, (span, shank_end, shank_alpha),
            (shank_end, shank_end + g["anode_length_mm"], inp["alpha_anode_ppm_K"] * 1e-6)]


def anchor_term_um_per_k(sections, z_f: float, alpha_w: float) -> float:
    """∫₀^{z_f} (α_w − α_anchor) dz in µm/K (lengths in mm)."""
    s = 0.0
    for a, b, alpha in sections:
        hi = min(b, z_f)
        if hi > a:
            s += (alpha_w - alpha) * (hi - a)
    return s * 1e3


def artefact_um_per_k(sections, z_f, z_t, h, alpha_w, alpha_s, alpha_h) -> float:
    return anchor_term_um_per_k(sections, z_f, alpha_w) + ((alpha_s - alpha_w) * z_t + (alpha_s - alpha_h) * h) * 1e3


def alpha_at(sections, z: float) -> float:
    return next(al for a, b, al in sections if a <= z < b) if z < sections[-1][1] else sections[-1][2]


def peek_in_path_mm(sections, z_f: float) -> float:
    return sum(max(0.0, min(b, z_f) - a) for a, b, al in sections if al == ALPHA_PEEK_1K)


def frames_crossing_mm(sections, alpha_w: float) -> float | None:
    """The exact depth at which |A| reaches the frames' sensitivity (A is linear inside each section)."""
    acc = 0.0
    for a, b, alpha in sections:
        slope = (alpha - alpha_w) * 1e3                       # |A| per mm here (positive: control 7)
        if acc + slope * (b - a) >= FRAME_UM_PER_K:
            return a + (FRAME_UM_PER_K - acc) / slope
        acc += slope * (b - a)
    return None


def field_amplitude_t(b_r: float, p_mm: float, t_mm: float, g_mm: float) -> float:
    k = 2 * math.pi / p_mm
    return 0.5 * b_r * (1 - math.exp(-k * t_mm)) * math.exp(-k * g_mm)


def best_period_mm(t_mm: float, g_mm: float, step: float = 0.01, p_max_mm: float | None = None) -> float:
    """The period minimising the offset term at the gap — B_r and δB only scale it, so they do not move it. With
    `p_max_mm` the scan stops there: the best period the sensor's linear range allows (see `period_cap_mm`)."""
    grid = np.arange(0.5, 60.0 + step, step)      # below 0.5 mm e^{−kg} underflows; the optimum is far above it
    if p_max_mm is not None:
        grid = grid[grid <= p_max_mm + 1e-9]
    k = 2 * np.pi / grid
    cost = grid / ((1 - np.exp(-k * t_mm)) * np.exp(-k * g_mm))
    return round(float(grid[int(np.argmin(cost))]), 2)


def period_cap_mm(linear_range_t: float, db_per_k: float, target_um_per_k: float) -> float:
    """The longest period at which the field the offset term NEEDS stays inside the sensor's linear range. That field is
    P·√2·δB/(2π·target) — the period alone sets it, not the magnet and not the scale's thickness (control 4's identity)."""
    return 2 * math.pi * target_um_per_k * 1e-3 * linear_range_t / (math.sqrt(2) * db_per_k)


def families_meeting(need_t: float) -> list[str]:
    """The magnet families with at least one class at or above `need_t` (their highest value in MAGNET_FAMILIES_BR_T)."""
    return [f for f, (_lo, hi) in MAGNET_FAMILIES_BR_T.items() if hi >= need_t]


def b_r_needed_t(p_mm, t_mm, g_mm, db_per_k, target_um_per_k) -> float:
    """The remanence at which the offset drift on both components moves the reading by `target` µm/K."""
    k = 2 * math.pi / p_mm
    return (2 * p_mm / (2 * math.pi) * math.sqrt(2) * db_per_k
            / (target_um_per_k * 1e-3 * (1 - math.exp(-k * t_mm)) * math.exp(-k * g_mm)))


def scale_cell(t_mm: float, g: float, wall_mm: float) -> dict:
    """One (thickness, gap) row of the scale behind the wall — the ONE home of the row, for the base table and the
    thickness knob alike."""
    p = best_period_mm(t_mm, g)
    need_raw = {k: b_r_needed_t(p, t_mm, g, db, FRAME_UM_PER_K) for k, db in HALL["offset_drift_T_per_K"].items()}
    need = {k: round(v, 3) for k, v in need_raw.items()}
    b_sensor = {k: round(field_amplitude_t(br, p, t_mm, g) * 1e3, 1) for k, br in need.items()}
    n_conv = {}
    for k, br in need.items():
        noise = p / (2 * math.pi) * HALL["noise_T"]["x_y"] / field_amplitude_t(br, p, t_mm, g) * 1e3
        n_conv[k] = max(1, math.ceil((noise / NOISE_TARGET_UM) ** 2))
    pairs = {}
    for pair in ("x_y", "x_z"):
        eps = HALL["sens_mismatch_drift"][pair]
        peak = p / (2 * math.pi) * eps / 2 * 1e3
        pairs[pair] = {"angle_error_static_cyclic_um": round(p * HALL["angle_error_deg"][pair] / 360 * 1e3, 1),
                       "mismatch_drift_cyclic_peak_um_over_datasheet_drift": round(peak, 1),
                       "mismatch_um_per_K_if_linear_over_K": [round(peak / dk, 2) for dk in MISMATCH_LINEAR_SPREAD_K[::-1]]}
    within_range = {}
    for lin in HALL["linear_range_T"]:
        for drift, db in HALL["offset_drift_T_per_K"].items():
            cap = period_cap_mm(lin, db, FRAME_UM_PER_K)
            p_in = best_period_mm(t_mm, g, p_max_mm=cap)
            need_in = b_r_needed_t(p_in, t_mm, g, db, FRAME_UM_PER_K)
            within_range[f"{lin * 1e3:g}mT:{drift}"] = {
                "period_cap_mm": round(cap, 2), "best_period_within_cap_mm": p_in, "capped": p_in < p,
                "b_r_needed_T": round(need_in, 3), "magnet_families_meeting": families_meeting(need_in),
                "angle_error_static_cyclic_um": {pr: round(p_in * HALL["angle_error_deg"][pr] / 360 * 1e3, 1)
                                                 for pr in ("x_y", "x_z")},
                "mismatch_drift_cyclic_peak_um": {pr: round(p_in / (2 * math.pi) * HALL["sens_mismatch_drift"][pr] / 2 * 1e3, 1)
                                                  for pr in ("x_y", "x_z")}}
    return {
        "t_mm": t_mm, "g_mm": g, "best_period_mm": p, "half_period_mm": round(p / 2, 3),
        "b_r_needed_T_offset_term_only": need, "field_at_sensor_mT_at_needed_b_r": b_sensor,
        "within_linear_range_40mT": {k: v <= HALL["linear_range_T"][0] * 1e3 for k, v in b_sensor.items()},
        "within_linear_range_80mT": {k: v <= HALL["linear_range_T"][1] * 1e3 for k, v in b_sensor.items()},
        "two_channel_samples_for_1um_at_needed_b_r": n_conv, "axis_pairs": pairs,
        "surface_field_share_kept_by_2mm_period": float(f"{math.exp(-2 * math.pi * g / ENCODER_2MM['period_mm']):.2e}"),
        "gap_below_radome_wall": g < wall_mm,
        "in_place_angle_calibration_yr_fast_slow": [round(p / RADIAL_RATE_MM_PER_YR[1], 1),
                                                    round(p / RADIAL_RATE_MM_PER_YR[0], 1)],
        "magnet_families_meeting_at_p_star": {k: families_meeting(v) for k, v in need_raw.items()},
        "within_sensor_linear_range": within_range}


def energy_j(i_a: float, v: float, t_s: float) -> float:
    return i_a * v * t_s


def control_closure_and_impulses(sections) -> None:
    one = [(a, b, 9e-6) for a, b, _ in sections]
    zero = [(a, b, 0.0) for a, b, _ in sections]
    for z_f in (0.0, 11.3, 32.0, 50.0, 70.0, 90.0):
        for z_t in (8.3, 21.0):
            for h in (0.0, 5.0, 12.0):
                assert abs(artefact_um_per_k(one, z_f, z_t, h, 9e-6, 9e-6, 9e-6)) < 1e-12, (z_f, z_t, h)
                assert abs(artefact_um_per_k(zero, z_f, z_t, h, 1e-6, 0.0, 0.0) - (z_f - z_t) * 1e-3) < 1e-12
                assert abs(artefact_um_per_k(zero, z_f, z_t, h, 0.0, 1e-6, 0.0) - (z_t + h) * 1e-3) < 1e-12
                assert abs(artefact_um_per_k(zero, z_f, z_t, h, 0.0, 0.0, 1e-6) + h * 1e-3) < 1e-12
                for k, (a, b, _) in enumerate(sections):
                    imp = [(aa, bb, 1e-6 if j == k else 0.0) for j, (aa, bb, _) in enumerate(sections)]
                    want = -max(0.0, min(b, z_f) - a) * 1e-3
                    assert abs(artefact_um_per_k(imp, z_f, z_t, h, 0.0, 0.0, 0.0) - want) < 1e-12, (k, z_f)


def control_sections(z103: dict, premise: str, sections, alpha_w: float) -> None:
    span87, g = z103["geometry"]["shift_span_mm_87"], z103["geometry"]
    for a, b in itertools.pairwise(sections):
        assert abs(a[1] - b[0]) < 1e-9, "sections must tile the anchor"
    assert sections[0][0] == 0.0 and abs(sections[-1][1] - span87["ceiling_full_depth_77"]) < 1e-9, "full depth ≠ 103's"
    gyroid = sections[-1]
    assert abs(0.5 * (gyroid[0] + gyroid[1]) - span87["nominal_anode_centroid_to_flange_77"]) < 1e-9, "centroid ≠ 103's"
    peek_103 = (g["span_mm"] if premise == "flange_on_bark"
                else z103["zone3_fit"]["sections_mm"]["peek_gap"][1] - z103["zone3_fit"]["sections_mm"]["peek_gap"][0])
    assert abs(peek_in_path_mm(sections, g["span_mm"]) - peek_103) < 1e-9, (premise, "PEEK to the shank's top ≠ 103's")
    assert all(al > alpha_w for _, _, al in sections), "control 7: an anchor section at or below α_w — A not monotone"
    cross = frames_crossing_mm(sections, alpha_w)
    assert cross is not None and abs(abs(anchor_term_um_per_k(sections, cross, alpha_w)) - FRAME_UM_PER_K) < 1e-9


def control_thickness() -> None:
    """Control 8 — the knob and the cap. For each gap and drift, a thicker scale needs STRICTLY less remanence at its own
    best period, which grows with thickness and stays at or under 2πg; at the cap the needed field equals the linear
    range by a separate route, and a capped period never exceeds its cap. CAN catch a sign slip in the (1 − e^{−kt})
    term, a cap applied the wrong way or a scan that overruns it; CANNOT an error in the idealised field form."""
    ts = sorted({*SCALE_T_MM, *SCALE_T_KNOB_MM})
    for g in GAPS_MM:
        periods = [best_period_mm(t, g) for t in ts]
        assert all(a <= b for a, b in itertools.pairwise(periods)), (g, periods)
        assert periods[-1] <= 2 * math.pi * g + 0.02, (g, periods[-1])
        for db in HALL["offset_drift_T_per_K"].values():
            needs = [b_r_needed_t(p, t, g, db, FRAME_UM_PER_K) for p, t in zip(periods, ts)]
            assert all(a > b for a, b in itertools.pairwise(needs)), (g, db, needs)
            for lin in HALL["linear_range_T"]:
                cap = period_cap_mm(lin, db, FRAME_UM_PER_K)
                assert abs(cap * math.sqrt(2) * db / (2 * math.pi * FRAME_UM_PER_K * 1e-3) - lin) < 1e-12
                for t in ts:
                    assert best_period_mm(t, g, p_max_mm=cap) <= cap + 1e-9, (t, g, lin)


def control_field() -> None:
    for g in GAPS_MM:
        assert abs(best_period_mm(1e3, g) - 2 * math.pi * g) < 0.02, g
        for t_mm in (*SCALE_T_MM, *SCALE_T_KNOB_MM):
            p = best_period_mm(t_mm, g)
            for db in HALL["offset_drift_T_per_K"].values():
                b = field_amplitude_t(b_r_needed_t(p, t_mm, g, db, FRAME_UM_PER_K), p, t_mm, g)
                assert abs(b - p * math.sqrt(2) * db / (2 * math.pi * FRAME_UM_PER_K * 1e-3)) < 1e-12, (g, t_mm)


def control_energy() -> None:
    members = sum(energy_j(i, V_OUT, t) for i, t in CYCLE_MEMBERS_J.values()) + E_RADIO_RX_TCXO_J
    assert abs(members / ETA_BUCK_ACTIVE - E_CYCLE) < 0.02e-3, (members / ETA_BUCK_ACTIVE, E_CYCLE)


def temperature_spans(hours: dict) -> dict:
    """Air (a stem-interior proxy): the diurnal range per local day in the growing season, the spread of daily means
    over unfrozen days, the freeze–thaw days."""
    days, idx = np.unique(np.array([s[:10] for s in hours["time"]]), return_inverse=True)
    t = hours["t_air"]
    tmax, tmin = np.full(len(days), -np.inf), np.full(len(days), np.inf)
    tsum, n = np.zeros(len(days)), np.zeros(len(days))
    np.maximum.at(tmax, idx, t)
    np.minimum.at(tmin, idx, t)
    np.add.at(tsum, idx, t)
    np.add.at(n, idx, 1)
    month = np.array([int(d[5:7]) for d in days])
    rng, mean = tmax - tmin, tsum / n
    growing, unfrozen = np.isin(month, (5, 6, 7, 8)), tmin > 0.0

    def pct(x, q):
        return round(float(np.percentile(x, q)), 1)

    return {"diurnal_range_growing_MJJA_K": {"p50": pct(rng[growing], 50), "p95": pct(rng[growing], 95)},
            "daily_mean_unfrozen_p5_p95_C": [pct(mean[unfrozen], 5), pct(mean[unfrozen], 95)],
            "freeze_thaw_days_per_year": round(float(((tmin < 0) & (tmax > 0)).sum() / (len(days) / 365.25)), 1),
            "unfrozen_days_share": round(float(unfrozen.mean()), 3), "days": len(days)}


def main() -> int:
    banner("HW.54 Р3(в) — a point dendrometer on the anchor: support artefact · scale behind the wall · read energy · travel")
    z103 = json.loads(WOOD_SHARE.read_text())
    z78 = json.loads(FLANGE_HEAT.read_text())
    z110 = json.loads(PV_AUTONOMY.read_text())
    radome, flange = json.loads(RADOME_CEM.read_text()), json.loads(FLANGE_CEM.read_text())
    alpha_w = z103["inputs"]["alpha_xylem_green_ppm_K"] * 1e-6
    z_t = dict(z103["geometry"]["bark_mm_78"])            # proxy: the dead bark under the flange, cut away under the probe
    ties = dict(z103["geometry"]["flange_seat_to_install_day_cambium_mm"])
    span87 = z103["geometry"]["shift_span_mm_87"]

    readings = {(p, s): anchor_sections(z103, p, s) for p in ("flange_on_bark", "zone3_fit") for s in ("bonded", "shoulder")}
    for (p, _s), secs in readings.items():
        control_closure_and_impulses(secs)
        control_sections(z103, p, secs, alpha_w)
    control_field()
    control_thickness()
    control_energy()

    s71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
    hours = s71.load_hours()
    assert len(hours["t_air"]) == z110["record"]["hours"], "the ERA5 record ≠ 110's"
    spans = temperature_spans(hours)

    # (1) the support: the anchor term per reading, fixation point and probe site
    shank_top = z103["geometry"]["span_mm"]
    gyroid_top = shank_top + z103["geometry"]["zone1_shank_in_sleeve"]["length_mm"]
    points = {"tie_shallowest": TIE_SHALLOWEST_MM, "tie_at_install_cambium": None, "zone1_shank_top": shank_top,
              "gyroid_top": gyroid_top, "anode_centroid": span87["nominal_anode_centroid_to_flange_77"],
              "gyroid_bottom": span87["ceiling_full_depth_77"]}
    support = {}
    for (prem, shank), secs in readings.items():
        rows = {}
        for site, zt in z_t.items():
            for name, zf in points.items():
                zf = ties[site] if zf is None else zf
                a = anchor_term_um_per_k(secs, zf, alpha_w)
                rows[f"{name}:{site}"] = {"z_f_mm": zf, "peek_in_path_mm": round(peek_in_path_mm(secs, zf), 2),
                                          "anchor_term_um_per_K": round(a, 3), "x_frames": round(abs(a) / FRAME_UM_PER_K, 1),
                                          "d_anchor_term_d_alpha_w_um_per_K_per_ppm": round(zf * 1e-3, 4),
                                          "d_total_A_d_alpha_w_um_per_K_per_ppm": round((zf - zt) * 1e-3, 4)}
        tie_drift = {site: [round(abs(alpha_w - alpha_at(secs, ties[site])) * r * 1e3, 3) for r in RADIAL_RATE_MM_PER_YR]
                     for site in ties}
        cross = frames_crossing_mm(secs, alpha_w)
        support[f"{prem}:{shank}"] = {
            "sections_mm_alpha_ppm_K": [[a, b, round(al * 1e6, 4)] for a, b, al in secs], "points": rows,
            "frames_crossing_depth_mm": round(cross, 2) if cross is not None else None,
            "crossing_minus_live_bark_depth_mm": {s: round(cross - zt, 3) for s, zt in z_t.items()},
            "reading_note": ("the consistent adverse end — the Zone-1 fit slipped" if (prem, shank) == ("flange_on_bark", "shoulder")
                             else "intermediate — the Zone-3 fit held while the Zone-1 fit slipped" if shank == "shoulder"
                             else "the fits held (103's reading)"),
            "tie_climb_drift_um_per_K_per_year_at_rate_ends": tie_drift}

    anchor_rows = [r for p in support.values() for r in p["points"].values()]
    worst = max(abs(r["anchor_term_um_per_K"]) for r in anchor_rows)
    worst_bonded = max(abs(r["anchor_term_um_per_K"]) for k, p in support.items() if k.endswith(":bonded")
                       for r in p["points"].values())
    d_t = spans["diurnal_range_growing_MJJA_K"]
    season_k = spans["daily_mean_unfrozen_p5_p95_C"][1] - spans["daily_mean_unfrozen_p5_p95_C"][0]
    in_um = {f"{lbl}": {"diurnal_growing_p50_um": round(w * d_t["p50"], 1), "diurnal_growing_p95_um": round(w * d_t["p95"], 1),
                        "seasonal_unfrozen_p5_p95_um": round(w * season_k, 1)}
             for lbl, w in (("worst_shoulder", worst), ("worst_bonded", worst_bonded))}
    hot = z78["verdict"]["worst_cell"]["sunlit_0.50"]
    flange_hot = {"flange_max_C": hot["flange_max_C"], "cambium_under_flange_max_C": hot["cambium_max_C"],
                  "cambium_no_flange_max_C": z78["verdict"]["no_flange_max_C"], "case": "78: sunlit, α 0.5, still air"}
    stf = z103["stiffness_N_per_mm"]
    k_s = z103["zone3_fit"]["stiffness_N_per_mm"]["sleeve_whole"]
    k_a = stf["anode_bond"]
    k_f = stf["bark_bearing_at_air_dry_readings"]
    u_rows = {f"{load}:{a_key}:{f_key}": round((1 / k_a[a_key] + 1 / k_s[load])
                                               / (1 / k_a[a_key] + 1 / k_s[load] + 1 / k_f[f_key]), 4)
              for load in ("sway", "slow") for a_key in k_a for f_key in k_f}
    u_lo, u_hi = min(u_rows.values()), max(u_rows.values())
    bearing = {"fraction_lost_U_at_air_dry_bark_readings": [u_lo, u_hi], "fraction_lost_U_rigid_bark": 1.0,
               "before_anode_bond": ("unpriced — before ingrowth the deep tie is not the anode but "
                                     + " and ".join(z103["zone3_fit"]["share"]["state1_ties_not_bounded"])
                                     + ", which 103 leaves unbounded (zone3_fit.share.state1_ties_not_bounded)"),
               "growth_under_reported_um_per_yr_at_795": [round(u_lo * GROWTH["yr_um"], 1), round(u_hi * GROWTH["yr_um"], 1)],
               "U_rows_premise_b": u_rows,
               "reading": "U = (1/k_A + 1/k_s)/(1/k_A + 1/k_s + 1/k_F) on 103's stiffnesses, premise (b), sway and slow "
                          "(relaxed PEEK): the fraction of a radial change of the bark the flange follows, so the reading loses "
                          "it (our reading of a growth push as a displacement source; k_F is the air-dry bark readings, green "
                          "bark is softer); U is priced with the anode BONDED (103's state 2) — before ingrowth the deep tie is a "
                          "grip 103 leaves unbounded, so U there is not priced; under premise (a) a rising bark can "
                          "lift the flange off the sleeve — our reading, 103 does not model lift-off"}

    # (2) the scale behind the wall
    scale = {f"t{t_mm:g}:g{g:g}": scale_cell(t_mm, g, radome["wall_thickness_mm"]) for t_mm in SCALE_T_MM for g in GAPS_MM}
    month_fast_mm = RADIAL_RATE_MM_PER_YR[1] / GROWTH_MONTHS_MIN
    bases = {"winter": FROST_SWING_MM[1],
             "growing_month_fast_end_plus_daily_swing": round(month_fast_mm + DAILY_SWING_MM[1], 3),
             "cross_season_outage": round(FROST_SWING_MM[1] + month_fast_mm + DAILY_SWING_MM[1], 3)}
    unwrap = {"worst_change_mm_by_basis": bases,
              "period_required_mm_by_basis": {k: round(2 * v, 2) for k, v in bases.items()},
              "margin_by_geometry": {key: {b: round(v["half_period_mm"] / w, 3) for b, w in bases.items()}
                                     for key, v in scale.items()},
              "basis_note": "season-consistent: winter = the frost swing with no growth; growing season = a month of the fast "
                            f"end's increment (laid down over ≥ {GROWTH_MONTHS_MIN:g} months — our assumption; a growing-season "
                            "outage of a month is itself an assumption, 110's outages fall in winter) plus the daily swing; "
                            "cross-season = an outage spanning both. P/2 bounds an absolute-in-period phase; the collector's "
                            "«half a pole» bounds an incremental pole counter, a different reader. A period above P* buys unwrap "
                            "margin at a small cost to the OFFSET term (its optimum is flat) — the angle and mismatch "
                            "errors grow in proportion to P.",
              "sensitivity_two_growing_months": (lambda w: {
                  "worst_change_mm": round(w, 3), "period_required_mm": round(2 * w, 2),
                  "geometries_meeting_at_p_star": [k for k, v in scale.items() if v["best_period_mm"] >= 2 * w]})(
                  FROST_SWING_MM[1] + 2 * month_fast_mm + DAILY_SWING_MM[1]),
              "encoder_2mm_half_period_mm": ENCODER_2MM["period_mm"] / 2,
              "count_home": "the server unwraps the delivered phases — nothing persisted on the device (03_01: the RTC backup "
                            "domain does not survive an outage on our board). What breaks it: a maintenance event that moves the "
                            "sensor against the scale (radome off/on, a board re-seat) — a step the server must mark as a "
                            "discontinuity; a ledger whose old readings are archived or expire — the server keeps a persisted "
                            "running unwrapped position, not a recompute over history; creep of the sensor's mount; and the "
                            "phase needs a field on the wire."}

    # (2b) the thickness knob — a thicker scale lowers the remanence the offset term needs, at a longer best period
    knob_rows = {}
    for t_mm in SCALE_T_KNOB_MM:
        for g in GAPS_MM:
            row = scale_cell(t_mm, g, radome["wall_thickness_mm"])
            ref = scale[f"t2:g{g:g}"]
            row["b_r_needed_over_t2_same_gap"] = {k: round(row["b_r_needed_T_offset_term_only"][k]
                                                            / ref["b_r_needed_T_offset_term_only"][k], 3)
                                                  for k in HALL["offset_drift_T_per_K"]}
            row["best_period_over_t2_same_gap"] = round(row["best_period_mm"] / ref["best_period_mm"], 3)
            row["unwrap_margin_by_basis"] = {b: round(row["half_period_mm"] / w, 3) for b, w in bases.items()}
            knob_rows[f"t{t_mm:g}:g{g:g}"] = row
    thickness_knob = {
        "thickness_mm": SCALE_T_KNOB_MM, "reference": "the t 2 mm row of the base table at the same gap",
        "rows": knob_rows,
        "reading": "each row is the base table's row at a thicker scale, computed by the same function; the field the "
                   "offset term needs at the sensor depends on the period alone, so a longer best period also raises "
                   "it — `within_sensor_linear_range` gives the best period the sensor's linear range allows and the "
                   "remanence needed there. The base table's population stays t 1–2 mm."}

    # (3) the energy of a read, riding cadence C
    cad = z110["inputs"]["cadence_c_interval_s"]
    demand = {k: v["nominal"] for k, v in z110["inputs"]["demand_uw"].items()}
    t_sample = HALL["t_conv_one_ch_s"] + HALL["t_add_ch_s"]
    t_wake = HALL["t_sleep_to_standby_s"] + HALL["t_standby_to_measure_s"]
    n_worst = max(n for v in scale.values() for n in v["two_channel_samples_for_1um_at_needed_b_r"].values())
    e_hall = energy_j(HALL["i_active_A"] + I_CORE_RUN_A, V_OUT, n_worst * t_sample + t_wake) / ETA_BUCK_ACTIVE
    e_enc = {k: energy_j(i + I_CORE_RUN_A, V_OUT, ENCODER_2MM["t_power_up_s"]) / ETA_BUCK_ACTIVE
             for k, i in ENCODER_2MM["i_supply_A"].items()}
    energy = {"cadence_c_s": cad, "demand_uW_110_nominal": demand,
              "two_channel_sample_s": round(t_sample, 6), "samples_worst_lane": n_worst,
              "hall_read_vstor_uJ": round(e_hall * 1e6, 1), "hall_read_avg_uW": round(e_hall / cad * 1e6, 4),
              "hall_read_share_of_E_cycle_pct": round(e_hall / E_CYCLE * 100, 2),
              "hall_sleep_uW_at_vout": round(HALL["i_sleep_A"] * V_OUT * 1e6, 4),
              "hall_sleep_share_of_smallest_demand_pct": round(HALL["i_sleep_A"] * V_OUT * 1e6 / min(demand.values()) * 100, 2),
              "encoder_2mm_read_vstor_mJ": {k: round(v * 1e3, 3) for k, v in e_enc.items()},
              "encoder_2mm_avg_uW": {k: round(v / cad * 1e6, 3) for k, v in e_enc.items()},
              "encoder_2mm_share_of_E_cycle_pct": {k: round(v / E_CYCLE * 100, 2) for k, v in e_enc.items()}}

    # (4) the travel window
    top_over_rim = radome["cavity_height_mm"] + radome["bell_radius_mm"]           # Radome.TopZMm
    dome_top_over_seat = flange["flange_thickness_mm"] + top_over_rim
    bark_above_seat = (0.0, z78["bark"]["facing_spread_mm"])                       # the faced seat's shallow ⊥ deep edge
    climb = (dome_top_over_seat - bark_above_seat[1], dome_top_over_seat - bark_above_seat[0])
    slow, fast = RADIAL_RATE_MM_PER_YR
    travel = {"dome_top_over_seat_mm": dome_top_over_seat, "of_which_flange_thickness_placeholder_mm": flange["flange_thickness_mm"],
              "outer_bark_climb_to_dome_top_mm": [round(c, 3) for c in climb],
              "outer_bark_to_dome_top_yr": [round(climb[0] / fast, 1), round(climb[1] / slow, 1)],
              "outer_bark_to_dome_top_yr_by_edge_fast_slow": {
                  "deep_edge": [round(climb[0] / fast, 1), round(climb[0] / slow, 1)],
                  "shallow_edge": [round(climb[1] / fast, 1), round(climb[1] / slow, 1)]},
              "radome_height_over_flange_top_mm": top_over_rim,
              "outer_bark_flange_top_to_dome_top_yr_fast_slow": [round(top_over_rim / fast, 1), round(top_over_rim / slow, 1)],
              "outer_bark_above_flange_top_at_install_mm": {"deep_edge": round(bark_above_seat[1] - flange["flange_thickness_mm"], 3),
                                                            "shallow_edge": round(bark_above_seat[0] - flange["flange_thickness_mm"], 3)},
              "live_bark_to_flange_seat_yr": {s: [round(zt / fast, 1), round(zt / slow, 1)] for s, zt in z_t.items()},
              "twenty_year_travel_mm": [round(20 * slow, 1), round(20 * fast, 1)]}

    # ── print ──
    print(f"  (1) the support's anchor term, µm/K (α_xylem {alpha_w * 1e6:g} ppm/K; frames < {FRAME_UM_PER_K} µm/K):")
    for key, d in support.items():
        print(f"    {key}: |A| reaches the frames at {d['frames_crossing_depth_mm']} mm "
              f"(minus the live bark's depth: {d['crossing_minus_live_bark_depth_mm']} mm; {d['reading_note']}); tie climb drifts A by "
              f"{d['tie_climb_drift_um_per_K_per_year_at_rate_ends']} µm/K per year")
        for k, r in d["points"].items():
            if k.endswith("thin_contact_78"):
                print(f"      {k.split(':')[0]:24s} z_f {r['z_f_mm']:6.2f}  PEEK {r['peek_in_path_mm']:5.1f} mm  "
                      f"A {r['anchor_term_um_per_K']:+.3f}  (×{r['x_frames']})")
    print(f"    air (stem-interior proxy, not a bound): growing diurnal p50/p95 {d_t['p50']}/{d_t['p95']} K; unfrozen daily "
          f"means p5–p95 {spans['daily_mean_unfrozen_p5_p95_C']} °C; freeze–thaw {spans['freeze_thaw_days_per_year']} d/yr")
    print(f"    in µm: {in_um}; under the flange in sun (78): {flange_hot}")
    print(f"    bearing: {bearing}")
    print("  (2) the scale behind the wall — P*, B_r needed (offset term only), field at the sensor, samples for 1 µm:")
    for k, v in scale.items():
        print(f"      {k:8s} P* {v['best_period_mm']:6.2f}  B_r {v['b_r_needed_T_offset_term_only']} T  "
              f"B {v['field_at_sensor_mT_at_needed_b_r']} mT  N {v['two_channel_samples_for_1um_at_needed_b_r']}  "
              f"pairs {v['axis_pairs']}")
    print(f"    unwrap: {json.dumps({k: unwrap[k] for k in ('worst_change_mm_by_basis', 'period_required_mm_by_basis', 'margin_by_geometry')})}")
    print("  (2b) the thickness knob — P*, B_r needed (typ ⊥ max) and its ratio to t 2 mm; inside the 80 mT range at max drift:")
    for k, v in knob_rows.items():
        w = v["within_sensor_linear_range"]["80mT:max"]
        print(f"      {k:9s} P* {v['best_period_mm']:6.2f}  B_r {v['b_r_needed_T_offset_term_only']} T  "
              f"×t2 {v['b_r_needed_over_t2_same_gap']}  | ≤80 mT, max: P {w['best_period_within_cap_mm']} "
              f"B_r {w['b_r_needed_T']} {w['magnet_families_meeting']}")
    for k, v in scale.items():
        w = v["within_sensor_linear_range"]["80mT:max"]
        print(f"      base {k:9s} ≤80 mT, max: P {w['best_period_within_cap_mm']} (cap {w['period_cap_mm']}) "
              f"B_r {w['b_r_needed_T']} {w['magnet_families_meeting']}  | at P*: {v['magnet_families_meeting_at_p_star']}")
    print(f"  (3) read energy: {json.dumps(energy, ensure_ascii=False)}")
    print(f"  (4) travel: {json.dumps(travel, ensure_ascii=False)}")

    OUT.write_text(json.dumps({
        "script": Path(__file__).name,
        "leg": "00_07 HW.54 Р3(в)",
        "what": "a point dendrometer with the anchor as its support: (1) the support's thermal artefact per fixation depth "
                "and the bark bearing's share, (2) the magnetic scale behind the capsule wall — period, the Hall sensor's "
                "error terms, the unwrap margin, (3) the energy of a read on cadence C, (4) years until the bark reaches "
                "the flange seat and the dome's top",
        "inputs": {"alpha_xylem_green_ppm_K": round(alpha_w * 1e6, 4), "alpha_peek_ppm_K": round(ALPHA_PEEK_1K * 1e6, 4),
                   "dead_bark_under_flange_78_probe_proxy_mm": z_t, "tie_axis_mm_103": [TIE_SHALLOWEST_MM, ties],
                   "frame_sensitivity_um_per_K": FRAME_UM_PER_K, "growth": GROWTH, "frost_swing_mm": FROST_SWING_MM,
                   "daily_swing_mm": DAILY_SWING_MM, "radial_rate_mm_per_yr": RADIAL_RATE_MM_PER_YR,
                   "growth_months_min_assumed": GROWTH_MONTHS_MIN, "hall": HALL,
                   "mismatch_linear_spread_K_assumed": MISMATCH_LINEAR_SPREAD_K, "encoder_2mm": ENCODER_2MM,
                   "core_run_A": I_CORE_RUN_A, "v_out": V_OUT, "eta_buck_active": ETA_BUCK_ACTIVE, "e_cycle_J": E_CYCLE,
                   "gaps_mm": GAPS_MM, "scale_thickness_mm": SCALE_T_MM, "noise_target_um": NOISE_TARGET_UM,
                   "scale_thickness_knob_mm": SCALE_T_KNOB_MM, "magnet_families_br_T": MAGNET_FAMILIES_BR_T,
                   "sources": {"geometry_alpha_share": "103 cache (anchor_wood_share.json); xylem α — Sevanto et al. 2005, "
                                                       "Boreal Env. Res. 10:437, Table 1, P. sylvestris, radial",
                               "flange_heat": "78 cache (flange_cambium_heat.json)",
                               "radome_flange": "tools/cad/cem/radome.json · cathode_flange.json; top = Radome.TopZMm",
                               "cadence_demand": "110 cache", "air": "ERA5 hourly, Cherkasy grid point (71's loader)",
                               "hall": "TI TMAG5273 datasheet SLYS045, §5.7 (A1) and §5.11, read 2026-10-31",
                               "encoder": "ams AS5311 rev 1.13",
                               "frames": "Zweifel et al. 2021 New Phytol. 10.1111/nph.17552, Methods (ZN11)",
                               "growth": "nph.17552 Table 1 · Etzold et al. 2022 Ecol. Lett. 10.1111/ele.13933 · "
                                         "Zweifel et al. 2021 Front. For. Glob. Change 10.3389/ffgc.2021.776905 p. 9",
                               "swings_and_rate_ends": "01_03 §4 ⊕ (в)", "core_vout_cycle": "02_03 §9.4",
                               "magnet_families": "01_03 §4 ⊕ (в), desk 2026-11-10 — IEC 60404-8-1:2001/AMD1:2004 "
                                                  "Tables 11–12 (specified minima) · MMPA 0100-00 Table III-1 (ferrite, "
                                                  "typical) — a mirror, edit THERE",
                               "collection": "handoff 2026-10-26_r3v_dendrometer.json"}},
        "controls": {"closure_and_impulses": "A = 0 with one α; unit impulses → z_f − z_t · z_t + h · −h · −section length",
                     "sections": "tile from 0, end at 103's full depth, gyroid centre on its anode centroid, 103's PEEK "
                                 "length to the shank's top",
                     "field_optimum": "P* = 2πg for a thick scale",
                     "thickness_and_cap": "a thicker scale needs strictly less B_r at a P* that grows toward 2πg; the "
                                          "field needed at the cap equals the linear range; no capped period overruns it",
                     "energy": "02_03 §9.4 members → lib's E_CYCLE through the active buck",
                     "era5_hours": z110["record"]["hours"], "monotone_support": "every anchor section's α > α_w"},
        "temperature": spans,
        "support": support,
        "support_worst_abs_um_per_K": {"shoulder": round(worst, 3), "bonded": round(worst_bonded, 3)},
        "support_worst_in_um_air_proxy": in_um,
        "flange_hot_hour_78": flange_hot,
        "bark_bearing": bearing,
        "design_terms": "(α_s − α_w)·z_t + (α_s − α_h)·h — nulled in the base reading; each ppm/K of mismatch costs "
                        "z_t (or h) in mm × 1e-3 µm/K, and α_s = α_w cannot be designed while α_w is one reading",
        "scale": scale,
        "scale_thickness_knob": thickness_knob,
        "unwrap": unwrap,
        "energy": energy,
        "travel": travel,
    }, indent=2, ensure_ascii=False))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
