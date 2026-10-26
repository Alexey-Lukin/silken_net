#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""110 — whether a photovoltaic cell on the capsule's dome could keep the node's supercapacitor from running empty
through the worst winter stretch of thirty years, and how large its effective aperture must AT LEAST be (00_07 HW.54,
the leg «Р3(б)(2): найгірший багатоденний відрізок інсоляції — закоміченим скриптом над ERA5, проти вікна EDLC із
витоком і ємністю на морозі»).

WHY. The desk pass of 2026-10-26 (01_03 §4 ⊕, (б)) left PV as the only no-consumables candidate for the node's power,
and only as an estimate: the EDLC window (02_03 §8) carries the node a few days without sun, so the measure is the
worst MULTI-DAY stretch of light — a number the tree did not hold (the collector's script was not committed). This
script holds it (and reproduces the desk's horizontal number, control 8), and turns it into the requirement the next
legs need: the effective aperture below which no cell on the dome can carry the node through the record.

WHAT IS PUBLISHED, AND WHICH SIDE IT STANDS ON. A NECESSARY condition, per DEMAND. The cell enters only through its
EFFECTIVE APERTURE A_eff = η_pv · T · A (cm²) — its efficiency at daylight, the canopy's transmittance, its area — so
the unknowns the next legs ask (η at 1–15 W/m², winter light on a vertical face under the canopy) stay inputs. The
demand is a CONDITION, not a reading: three are printed and none is picked — the Standby sleep target alone (the
smallest of the three), cadence C, the shipped STOP2 sleep at cadence C. Within a demand every other input is a
READING with three corners: favourable · nominal · adverse. Per field, demand and corner a bisection on the 30-year
hourly record finds the smallest A_eff at which the store never empties; the LOWER end of its final bracket is
published, rounded DOWN. «Below X the node cannot ride the record at demand D» is the FAVOURABLE corner's number: each
input the canon bounds, at the favourable end of the widest band it carries; the two inputs it does not bound for a PV
cell (the boost's input voltage, the ground's brightness) are named below with their direction. The adverse corner says
how high the same requirement climbs. Neither is sufficient: everything under WHAT IT CANNOT SEE is outside the model.
  capacitance — nominal 0.47 F; favourable the tolerance's high edge (+80 %); adverse its low edge with the end-of-life
      loss on top (02_03 §12.1);
  window — the store EMPTIES at OK_PROG: from a full store the buck stays on down to it (§4.Г), so the window to the
      first outage runs from VBAT_OV to OK_PROG (the full window §9.10 uses — not §8's, which stops at OK_HYST, the
      reserve above the restart threshold; OK_HYST matters only after an outage, which is outside the model). Both thresholds
      are read on their worst-case bands on our 1 % resistors (§4.Б's row for VBAT_OV, §4.Г's for OK_PROG):
      favourable the top of VBAT_OV's down to the bottom of OK_PROG's, adverse the other way, nominal typ to typ;
  boost η(I) — §9.1 gives it only at anchors in input CURRENT, each an INTERVAL (the text's ~10 µA reading; the
      table's three points, each ± its read error), read at an EBFC's operating voltage, and caps it: the plateau,
      85–90 %, comes «only from ~1 mA». A PV cell's input voltage is not the EBFC's and the canon gives no η at it, so
      the one bound that holds at any input is the cap: the favourable corner takes η = 0.90 everywhere. The adverse
      corner keeps the EBFC's anchors at lib's V_OP (0.5 V) on the least efficient step curve they allow (this anchor's
      bottom; 0 below the first — `109`'s construction); nominal — linear through the intervals' mid-points at §9.1's
      table V_OP (325 mV), flat outside;
  energy per wake (cadence lanes) — E_CYCLE_LOW · E_CYCLE · E_CYCLE_HIGH (02_03 §9.4, lib) at cadence C's FIXED
      interval H = E_CYCLE / (η_BQ · P_GEN − P_sleep) — §9.6's construction;
  leak — none · none · §9.3's 1 µA illustration (not the end of a band: the part's leak is unmeasured);
  reflected light — each field is run at both of `79`'s readings; the favourable sentence takes the brighter, the
      adverse the darker — two named readings, not the ends of a band (01_04 §3.1: neither is an extreme of the ground).

MODEL. Hourly, 1991–2020, ERA5 at the Cherkasy grid point (`71`'s loader; radiation is the mean of the PRECEDING hour;
`79`'s sun and clock gates run here, control 4). The dome's face is a VERTICAL plane facing away from the stem.
  open field: G = DNI·⟨cos γ⟩ + ½·DHI + ½·ρ·GHI, ⟨cos γ⟩ over the sunlit part of each hour on the face (`79`'s sun and
      face); four faces are printed, because the azimuth is set by the gateway, not by the sun;
  closed stand, two forms, and which describes a closed stand is NOT established: isotropic, G = ½·(1 + ρ)·GHI (the
      desk's), and beam through the gaps — the open face's G (a low winter sun reaches a vertical face through the
      gaps at a larger cos γ than a horizontal reading of T implies). Either way the canopy's T (measured on horizontal
      GHI, Sonohat 2004) is folded into A_eff, so the beam form's numbers ARE the open faces' rows, and the closed
      stand's sentence takes the lower of the two.
  GHI = DNI·⟨max(sun_up, 0)⟩ + DHI (`79`'s line); ρ·GHI — `79`'s two reflected ends (`reflected_rows`).
  Store: E_max = ½·C·(V_top² − V_floor²); each hour E ← min(E_max, E + (η_b(P)·P − D − L)·3600 s), P = A_eff·G, and an
  hour that would take E below zero is an outage (E held at 0). The record starts full. Only WHETHER the store
  empties is used.

WHAT IT CANNOT SEE. Snow, rime and dirt ON the dome; the dome's optics (PEEK has no optical path — PV is a radome
change, 01_03 §4); the cell's own temperature; any η_pv dependence on light level (a scalar inside A_eff); the boost's
η at a PV cell's input voltage (§9.1's anchors are an EBFC's at 0.3–0.5 V; the favourable corner needs no anchor, but
whether the adverse EBFC anchors over- or understate a PV input is not established) and whether the MPPT fraction meets
a PV cell's MPP; ground brighter than `79`'s brighter reading lowers X (light only adds to the harvest) and no bound on
it is carried; the capacitance and the leak at frost (§12.1 rates neither, and
the leak is an illustration) — the leg asks for both, and they stay inputs the tree does not have; what follows an
outage — the VBAT_OK hysteresis, the warm-up cost and the cold start of an EMPTIED store (HW.44's subject; VIN(CS) is
rated only above 0 °C, 02_03 §1.1); the canon's winter mode (§9.8: the MCU's sleep cut by a PFET, TX only at VSTOR ≥
4.6 V) — a state-dependent demand whose floor lies below the Standby sleep; winter light under a canopy on a vertical
face (T is a summer horizontal reading); the reflected ends are open-field ones, and neither is an extreme of the real
ground (01_04 §3.1: 0.80 is a mean of fresh snow, wet ground falls below 0.18) — under the canopy the ground's light
is not modelled; ERA5's open cell instead of the stand; a winter worse than the worst of the record's whole winters.

CONTROLS (each says what it CAN and CANNOT catch).
  (1) Zero harvest: with A_eff = 0 the first outage falls at hour ⌊E_max / ((D + L)·3600 s)⌋ + 1 — the recurrence
      against its closed form; CAN catch a slip in the start-full state, the outage test or the drain arithmetic,
      CANNOT one in the store's ceiling or in E_max's value (that is (2)'s).
  (2) Store ceiling: a synthetic record of K blinding hours and then darkness empties at hour K + ⌊E_max / ((D +
      L)·3600 s)⌋ + 1 for two different K, with E_max computed afresh, not read from the lanes; CAN catch a missing or
      misplaced ceiling and a wrong E_max on a lane, CANNOT a slip in the harvest arm (that is (6)'s).
  (3) December GHI: the record's mean daily December GHI within ±10 % of the desk's two sources; CAN catch a unit or a
      gross geometry slip in GHI, CANNOT a clock slip (an hour moves it by about 2 %) — that is (4)'s.
  (4) `79`'s gates on this record: the sun's geometry (declination, equation of time, June noon altitude) and its clock
      (no DNI in sun-down hours at the declared convention, some at ±½ and ±1 h); CAN catch a wrong coefficient, sign,
      UTC offset or a convention read backwards, CANNOT an error well inside an hour.
  (5) Faces: on every 21 December at the hour of highest sun the south face's ⟨cos γ⟩ lies within [0.98, 1] of
      cos(90° − φ − 23.44°) (measured 0.995: the hour mean sits just below the noon value), the north face's is 0, the
      east face leads the west 2 h before and trails it 2 h after; CAN catch a swapped or mirrored face, CANNOT a
      rotation of the face by up to about 16° east or 6° west (measured by mutation: the window passes them).
  (6) Harvest arm: on a constant synthetic field G₀ the bisected threshold brackets the closed-form aperture where
      η(A·G₀)·A·G₀ = D + L − E_max / (N·3600 s) — the root found by a separate scalar route with its own unit
      conversion and its own η (7); CAN catch a slip in the harvest arithmetic (area unit, the µW the boost is read
      at, the hour, the sign) or in the bisection, CANNOT one in a quantity both routes share (anchors, demand, window).
  (7) The vector η curves equal the scalar ones on a grid through and around every anchor, and the corners are ordered;
      CAN catch an indexing slip in either, CANNOT an error in the anchors.
  (8) The desk's number: the worst 7-day December–January running mean of GHI, the median of the season minima and
      the count of seasons reproduce the desk pass's 331 · 401 Wh/m²/day (within 1) and 29; CAN catch a wrong window
      length, a lost or an extra season, CANNOT a one-day shift of the window or a season-boundary slip that leaves
      both numbers unchanged (measured by mutation).
  (9) Monotone outages: at 0.5·, 0.9·, 1.1· and 2· each threshold the outage hours do not rise with A_eff and vanish
      above it; CAN catch a non-monotone reading breaking the bisection, CANNOT a monotone bias.
  (10) A lane whose store empties even at the bisection's top aperture is published as «none up to it», not bisected;
      the bisection raises if it does not close.

Run:  python tools/in_silico/scripts/110_winter_pv_autonomy.py      # about 40 s (30 years hourly, 90 lanes)
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
from lib.constants import (
    C_EDLC_EOL_DROP,
    C_EDLC_F,
    C_EDLC_TOLERANCE_HIGH,
    C_EDLC_TOLERANCE_LOW,
    E_CYCLE,
    E_CYCLE_HIGH,
    E_CYCLE_LOW,
    EDLC_WINDOW_VSTOR_J,
    ETA_BOOST_TABLE_UW,
    ETA_BQ,
    ETA_BQ_10UA_READING,
    ETA_BQ_PLATEAU_READING,
    ETA_TABLE_READ_ERROR,
    I_ETA_10UA,
    KINETICS_DIR,
    P_EDLC_LEAK_1UA_ILLUSTRATION,
    P_GEN_SUMMER_UW,
    P_SLEEP_VSTOR,
    P_SLEEP_VSTOR_STOP2,
    REPO_ROOT,
    V_OP,
    V_OP_02_03_TABLE,
    VBAT_OK_OFF_V,
    VBAT_OK_OFF_WORST_CASE_V,
    VBAT_OV_RATIFIED_V,
    VBAT_OV_WORST_CASE_V,
)
from lib.utils import banner

SI_DESCRIPTION = ("Whether a small photovoltaic cell on the sensor capsule could keep its supercapacitor from running "
                  "empty through the worst winter stretch of thirty years of hourly weather: per power demand, the "
                  "effective aperture below which it could not, with the inputs the specifications bound read at "
                  "their favourable and adverse ends, on a model that leaves out snow on the dome, the cell's "
                  "temperature and the canopy's winter optics")  # its row in the paper SI (72): English, no repo jargon

OUT = KINETICS_DIR / "winter_pv_autonomy.json"
SCRIPTS = Path(__file__).resolve().parent

OPEN_AZIMUTHS_DEG = (0, 90, 180, 270)      # the open faces printed — a subset of `79`'s AZIMUTHS_DEG, asserted
DESK_ETA_PV = (0.03, 0.05)                 # a-Si at daylight — ASSUMED, the desk's own word (01_03 §4 ⊕ (б))
DESK_CANOPY_T = (0.21, 0.55)               # 70 % of the readings, SOURCES["canopy_t"] (01_03 §4 ⊕ (б))
DEC_GHI_SOURCES_WH_M2_DAY = {"PVGIS-SARAH3 2005-2023": 636.0, "NASA POWER": 663.0}   # 01_03 §4 ⊕ (б), SOURCES
DEC_GHI_TOL = 0.10
DESK_WORST_7D_DEC_JAN = {"worst_Wh_m2_day": 331.0, "median_of_season_minima_Wh_m2_day": 401.0, "seasons": 29}
DESK_REPRO_TOL = 1.0                       # Wh/m²/day — the desk printed whole numbers
SOURCES = {
    "canopy_t": "Sonohat G., Balandier P., Ruchaud F. (2004) Ann. For. Sci. 61(7):629-641, doi:10.1051/forest:2004061 "
                "— Scots pine stand transmittance of global radiation 0.15-0.81, 70 % of the data 0.21-0.55; "
                "horizontal solarimeters, growing season",
    "dec_ghi_pvgis": "https://re.jrc.ec.europa.eu/api/v5_3/MRcalc?lat=49.44&lon=32.06&horirrad=1&d2g=1&selectrad=1"
                     "&angle=90&aspect=0&outputformat=json (collected by the desk pass, re-queried by its verifier)",
    "dec_ghi_nasa_power": "https://power.larc.nasa.gov/api/temporal/climatology/point?parameters=ALLSKY_SFC_SW_DWN,"
                          "ALLSKY_SFC_SW_DIFF,CLRSKY_SFC_SW_DWN&community=RE&longitude=32.06&latitude=49.44&format=JSON "
                          "(as collected by the desk pass, not re-read)",
    "desk_worst_7d": "the desk pass of 2026-10-26 over the same ERA5 file (its script was not committed; provenance — "
                     "the handoff corpus named in 01_03 §4 ⊕, r3b_winter_power)",
}
STRETCH_DAYS = (1, 3, 7, 14)
WINTER_MONTHS = (11, 12, 1, 2, 3)          # `79`'s winter
DESK_MONTHS = (12, 1)                      # the desk's window
BISECT_HI_CM2 = 100.0                      # an aperture no dome carries — the bracket's top
BISECT_REL_TOL = 1e-4                      # bracket width per its top; the outage count is an integer, so exact
BISECT_MAX_ITER = 60
MONOTONE_FACTORS = (0.5, 0.9, 1.1, 2.0)
CHUNK_H = 4096                             # hours per vectorised block of the harvest arithmetic
HARVEST_CONTROL_G_W_M2 = 20.0              # control (6): a constant field …
HARVEST_CONTROL_HOURS = 5000               # … over this many hours
CEILING_CONTROL_K_H = (24, 240)            # control (2): blinding hours before the dark
CEILING_CONTROL_G_W_M2 = 1000.0
TIE_REL = 1e-9                             # two thresholds this close are one (a diffuse-only binding stretch)

CORNERS = ("favourable", "nominal", "adverse")
CORNER_CODE = {c: i for i, c in enumerate(CORNERS)}
DEMANDS = ("standby_sleep", "cadence_c", "stop2_cadence_c")
CAP_F = {"favourable": C_EDLC_F * (1.0 + C_EDLC_TOLERANCE_HIGH), "nominal": C_EDLC_F,
         "adverse": C_EDLC_F * (1.0 - C_EDLC_TOLERANCE_LOW) * (1.0 - C_EDLC_EOL_DROP)}
WINDOW_V = {"favourable": (VBAT_OV_WORST_CASE_V[1], VBAT_OK_OFF_WORST_CASE_V[0]),
            "nominal": (VBAT_OV_RATIFIED_V, VBAT_OK_OFF_V),
            "adverse": (VBAT_OV_WORST_CASE_V[0], VBAT_OK_OFF_WORST_CASE_V[1])}
E_ACTIVE_J = {"favourable": E_CYCLE_LOW, "nominal": E_CYCLE, "adverse": E_CYCLE_HIGH}
LEAK_W = {"favourable": 0.0, "nominal": 0.0, "adverse": P_EDLC_LEAK_1UA_ILLUSTRATION}
END = {"favourable": "high", "adverse": "low"}       # the reflected end each published sentence reads
ETA_WORD = {"favourable": "plateau-top (0.90 at any input)", "nominal": "mid-point", "adverse": "least efficient"}
ETA_V_OP = {"nominal": V_OP_02_03_TABLE, "adverse": V_OP}     # the favourable corner reads no anchor
ETA_CAP = ETA_BQ_PLATEAU_READING[1]
H_CADENCE_C_S = E_CYCLE / (ETA_BQ * P_GEN_SUMMER_UW * 1e-6 - P_SLEEP_VSTOR)   # §9.6: cadence C's wake interval
SLEEP_W = {"standby_sleep": P_SLEEP_VSTOR, "cadence_c": P_SLEEP_VSTOR, "stop2_cadence_c": P_SLEEP_VSTOR_STOP2}


def demand_w(demand: str, corner: str) -> float:
    wake = 0.0 if demand == "standby_sleep" else E_ACTIVE_J[corner] / H_CADENCE_C_S
    return wake + SLEEP_W[demand]


def e_max_j(corner: str) -> float:
    top, floor = WINDOW_V[corner]
    return 0.5 * CAP_F[corner] * (top**2 - floor**2)


def eta_anchors_ua() -> list[tuple[float, float, float]]:
    """(input current µA, η low, η high): 02_03 §9.1's ~10 µA reading, then its table (lib holds it in µW at the
    table's V_OP) as currents, each table point ± its read error — `109`'s anchors."""
    out = [(I_ETA_10UA, *ETA_BQ_10UA_READING)]
    out += [(p / V_OP_02_03_TABLE, max(0.0, e - ETA_TABLE_READ_ERROR), min(1.0, e + ETA_TABLE_READ_ERROR))
            for p, e in ETA_BOOST_TABLE_UW]
    for a, b in itertools.pairwise(out):
        if not (b[0] > a[0] and b[1] >= a[1] and b[2] >= a[2]):
            raise SystemExit("the boost's anchors are not increasing in current with a non-decreasing η")
    return out


ANCHORS = {c: [(i * v, lo, hi) for i, lo, hi in eta_anchors_ua()] for c, v in ETA_V_OP.items()}   # in power, µW
_ADV_X = np.array([a[0] for a in ANCHORS["adverse"]])
_ADV_V = np.array([0.0] + [a[1] for a in ANCHORS["adverse"]])
_NOM_X = np.array([a[0] for a in ANCHORS["nominal"]])
_NOM_V = np.array([0.5 * (a[1] + a[2]) for a in ANCHORS["nominal"]])


def boost_eta(p_uw: np.ndarray, code: np.ndarray) -> np.ndarray:
    """η of the boost at input power p_uw, per lane's corner code (broadcast over the last axis)."""
    fav = np.full(np.shape(p_uw), ETA_CAP)
    adv = _ADV_V[np.searchsorted(_ADV_X, p_uw, side="right")]
    nom = np.interp(p_uw, _NOM_X, _NOM_V)
    return np.where(code == 0, fav, np.where(code == 1, nom, adv))


def eta_scalar(p_uw: float, corner: str) -> float:
    """The same three curves as plain branches — the independent route of controls (6) and (7)."""
    if corner == "favourable":
        return ETA_CAP
    if corner == "adverse":
        eta = 0.0
        for x, lo, _ in ANCHORS[corner]:
            if p_uw >= x:
                eta = lo
        return eta
    pts = [(x, 0.5 * (lo + hi)) for x, lo, hi in ANCHORS[corner]]
    if p_uw <= pts[0][0]:
        return pts[0][1]
    for (x0, e0), (x1, e1) in itertools.pairwise(pts):
        if p_uw <= x1:
            return e0 + (e1 - e0) * (p_uw - x0) / (x1 - x0)
    return pts[-1][1]


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
S79 = _load("s79_frost", "79_flange_cambium_frost.py")
if not set(OPEN_AZIMUTHS_DEG) <= set(S79.AZIMUTHS_DEG):
    raise SystemExit("an open face is not one of 79's azimuths")


def dome_face_cm2() -> float:
    d_mm = S71.geometry()["dome_diameter_mm"]
    return math.pi * (d_mm / 2.0) ** 2 / 100.0


def irradiance(wx: dict, sun: np.ndarray, gc: np.ndarray) -> tuple[dict, np.ndarray]:
    """Face irradiance (W/m²) per field, hourly, and GHI."""
    ghi = wx["dni"] * np.maximum(sun[2], 0.0).mean(axis=1) + wx["dif"]
    refl = S79.reflected_rows(S79.load_snow(wx["time"]), ghi)
    ends = [e[0] for e in S79.REFLECT_ENDS]
    if ends != ["low", "high"] or np.any(refl[2] < refl[1]):
        raise SystemExit("79's reflected ends are not «low» ≤ «high» in every hour")
    fields = {}
    for k, end in enumerate(ends, start=1):
        fields[f"closed_stand.{end}"] = 0.5 * ghi + 0.5 * refl[k]
        for az in OPEN_AZIMUTHS_DEG:
            fields[f"open_face_{az:03d}.{end}"] = (wx["dni"] * gc[S79.AZIMUTHS_DEG.index(az)] + 0.5 * wx["dif"]
                                                   + 0.5 * refl[k])
    return fields, ghi


def simulate(g_hf: np.ndarray, lanes: dict, a_eff_cm2: np.ndarray) -> np.ndarray:
    """Outage hours per lane over the record at the lanes' apertures; g_hf is (hours, fields)."""
    a_m2 = a_eff_cm2 * 1e-4
    e_max = lanes["e_max"]
    draw_j = (lanes["demand"] + lanes["leak"]) * 3600.0
    e = e_max.copy()
    out = np.zeros(len(e_max), dtype=np.int64)
    for s in range(0, g_hf.shape[0], CHUNK_H):
        p_w = a_m2 * g_hf[s:s + CHUNK_H][:, lanes["field"]]
        net = boost_eta(p_w * 1e6, lanes["eta"]) * p_w * 3600.0 - draw_j
        for row in net:
            e = e + row
            neg = e < 0.0
            out += neg
            e = np.where(neg, 0.0, np.minimum(e, e_max))
    return out


def thresholds(g_hf: np.ndarray, lanes: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray, int]:
    """(lo, hi, feasible, iterations): lanes that empty even at the top aperture are infeasible and not bisected."""
    n = len(lanes["field"])
    feasible = simulate(g_hf, lanes, np.full(n, BISECT_HI_CM2)) == 0
    lo, hi = np.zeros(n), np.full(n, BISECT_HI_CM2)
    for it in range(1, BISECT_MAX_ITER + 1):
        mid = 0.5 * (lo + hi)
        ok = simulate(g_hf, lanes, mid) == 0
        hi, lo = np.where(ok, mid, hi), np.where(ok, lo, mid)
        if np.max(np.where(feasible, (hi - lo) / hi, 0.0)) < BISECT_REL_TOL:
            return lo, hi, feasible, it
    raise RuntimeError(f"bisection did not close in {BISECT_MAX_ITER} iterations")


def lanes_of(combos: list[tuple[int, str, str]]) -> dict:
    """combos: (field index, demand, corner)."""
    return {"field": np.array([f for f, _, _ in combos]),
            "demand": np.array([demand_w(d, c) for _, d, c in combos]),
            "leak": np.array([LEAK_W[c] for _, _, c in combos]),
            "e_max": np.array([e_max_j(c) for _, _, c in combos]),
            "eta": np.array([CORNER_CODE[c] for _, _, c in combos])}


def _onset_hours(combos: list[tuple[int, str, str]], hours: int) -> np.ndarray:
    """⌊E_max / ((D + L)·3600 s)⌋ per combo, E_max computed afresh — refuses an ambiguous or too-long one."""
    x = np.array([e_max_j(c) / ((demand_w(d, c) + LEAK_W[c]) * 3600.0) for _, d, c in combos])
    if np.any(np.abs(x - np.round(x)) < 1e-6) or np.any(x >= hours):
        raise SystemExit("an onset control is ambiguous: an autonomy is a whole number of hours, or too long")
    return np.floor(x)


def control_zero_harvest(g_hf: np.ndarray, combos: list, lanes: dict) -> None:
    hours = 24 * 40
    zero = simulate(g_hf[:hours], lanes, np.zeros(len(combos)))
    if not np.array_equal(zero, (hours - _onset_hours(combos, hours)).astype(np.int64)):
        raise SystemExit("control (1): the zero-harvest outage onset differs from its closed form")


def control_store_ceiling() -> None:
    hours = 24 * 40
    combos = [(0, d, c) for d in DEMANDS for c in CORNERS]
    lanes = lanes_of(combos)
    onset = _onset_hours(combos, hours - max(CEILING_CONTROL_K_H))
    for k in CEILING_CONTROL_K_H:
        g = np.zeros((hours, 1))
        g[:k] = CEILING_CONTROL_G_W_M2
        out = simulate(g, lanes, np.full(len(combos), 1.0))
        if not np.array_equal(out, (hours - k - onset).astype(np.int64)):
            raise SystemExit(f"control (2): after {k} blinding hours the store does not empty from its ceiling")


def control_faces(times: np.ndarray, sun: np.ndarray, gc: np.ndarray, lat_deg: float) -> dict:
    day = np.array([str(x)[5:10] for x in times[::24]])
    i_s, i_n, i_e, i_w = (S79.AZIMUTHS_DEG.index(a) for a in (180, 0, 90, 270))
    cos_h = math.cos(math.radians(90.0 - lat_deg - 23.44))
    up = sun[2].mean(axis=1)
    ratio, lead = [], []
    for d in np.where(day == "12-21")[0]:
        hrs = np.arange(24 * d, 24 * d + 24)
        k = hrs[np.argmax(up[hrs])]
        ratio.append(gc[i_s][k] / cos_h)
        if gc[i_n][k] != 0.0:
            raise SystemExit("control (5): the north face is lit at the winter solstice's noon")
        lead.append(min(gc[i_e][k - 2] - gc[i_w][k - 2], gc[i_w][k + 2] - gc[i_e][k + 2]))
    if not ratio or min(ratio) < 0.98 or max(ratio) > 1.0 or min(lead) <= 0.0:
        raise SystemExit(f"control (5): face orientation off (south/cos h {min(ratio):.4f}–{max(ratio):.4f}, "
                         f"east/west lead {min(lead):.3f})")
    return {"solstices": len(ratio), "south_over_cos_h": [round(min(ratio), 4), round(max(ratio), 4)],
            "east_west_lead_min": round(min(lead), 3)}


def control_harvest_arm() -> dict:
    g = np.full((HARVEST_CONTROL_HOURS, 1), HARVEST_CONTROL_G_W_M2)
    combos = [(0, d, c) for d in DEMANDS for c in CORNERS]
    lo, hi, feasible, _ = thresholds(g, lanes_of(combos))
    worst = 0.0
    for i, (_, d, c) in enumerate(combos):
        target_w = demand_w(d, c) + LEAK_W[c] - e_max_j(c) / (HARVEST_CONTROL_HOURS * 3600.0)
        if target_w <= 0.0 or not feasible[i]:
            raise SystemExit("control (6): the synthetic record does not test this lane")
        a, b = 0.0, BISECT_HI_CM2
        for _ in range(200):
            m = 0.5 * (a + b)
            p_w = m / 10_000.0 * HARVEST_CONTROL_G_W_M2          # cm² → m², times W/m²
            a, b = (a, m) if eta_scalar(p_w * 1e6, c) * p_w >= target_w else (m, b)
        if not lo[i] <= b <= hi[i] * (1.0 + 1e-9):
            raise SystemExit(f"control (6): the harvest arm misses its closed form on {d}/{c}: {b} ∉ [{lo[i]}, {hi[i]}]")
        worst = max(worst, (hi[i] - lo[i]) / hi[i])
    return {"g_w_m2": HARVEST_CONTROL_G_W_M2, "hours": HARVEST_CONTROL_HOURS, "lanes": len(combos),
            "widest_bracket_rel": float(f"{worst:.3g}")}


def control_eta_curves() -> None:
    grid = sorted({x * f for c in ANCHORS for x, _, _ in ANCHORS[c] for f in (0.5, 0.999, 1.0, 1.001, 2.0)}
                  | set(np.geomspace(0.1, 1000.0, 400).tolist()))
    p = np.array(grid)
    for c in CORNERS:
        if not np.allclose(boost_eta(p, np.array(CORNER_CODE[c])), [eta_scalar(x, c) for x in grid], rtol=0.0, atol=1e-12):
            raise SystemExit(f"control (7): the vector and scalar η curves differ on the {c} corner")
    if np.any(boost_eta(p, np.array(0)) < boost_eta(p, np.array(1))) or \
            np.any(boost_eta(p, np.array(1)) < boost_eta(p, np.array(2))):
        raise SystemExit("control (7): the η corners are not ordered favourable ≥ nominal ≥ adverse")


def binding_stretch(g: np.ndarray, times, dni, demand: float, leak: float, e_max: float, code: int,
                    a_eff_cm2: float) -> dict:
    """The stretch that binds a threshold: one lane just below it (×(1 − 1e-3)) to its first outage — the last hour the
    store was full before it, and the direct-normal light after that hour (zero there means every face saw the same
    stretch, since what any face gathered earlier was cut at E_max)."""
    p_w = a_eff_cm2 * (1.0 - 1e-3) * 1e-4 * g
    net = (boost_eta(p_w * 1e6, np.array(code)) * p_w - demand - leak) * 3600.0
    e, last_full = e_max, -1
    for h, x in enumerate(net.tolist()):
        e = min(e + x, e_max)
        if e >= e_max:
            last_full = h
        if e < 0.0:
            return {"last_full": str(times[last_full]) if last_full >= 0 else "record start",
                    "first_outage": str(times[h]),
                    "dni_after_last_full_Wh_m2": round(float(dni[last_full + 1:h + 1].sum()), 1)}
    raise RuntimeError("no outage just below the threshold — the bisection's lower end is not failing")


def worst_stretches(fields: dict, times: np.ndarray, months: tuple) -> dict:
    days = times.astype("datetime64[D]")[::24]
    if len(times) % 24 or not np.all(times.astype("datetime64[h]")[::24] == days.astype("datetime64[h]")):
        raise SystemExit("the record is not whole days starting at midnight")
    month = days.astype("datetime64[M]").astype(int) % 12 + 1
    year = days.astype("datetime64[Y]").astype(int) + 1970
    season = np.where(month >= 11, year, year - 1)          # the winter starting in November of `season`
    whole = (season >= year[0]) & (season + 1 <= year[-1])  # only winters the record holds from November to March
    out = {}
    for name, g in fields.items():
        daily = g.reshape(-1, 24).sum(axis=1)               # Wh/m² per day (hourly means × 1 h)
        out[name] = {}
        for n in STRETCH_DAYS:
            mean = np.convolve(daily, np.ones(n) / n, mode="valid")
            m = len(mean)
            ok = (np.isin(month[:m], months) & np.isin(month[n - 1:], months)
                  & (season[:m] == season[n - 1:]) & whole[:m])
            idx = np.where(ok)[0]
            worst = idx[np.argmin(mean[idx])]
            per_season = [float(mean[idx[season[idx] == s]].min()) for s in np.unique(season[idx])]
            out[name][f"{n}d"] = {"worst_Wh_m2_day": round(float(mean[worst]), 1), "worst_starts": str(days[worst]),
                                  "median_of_season_minima_Wh_m2_day": round(float(np.median(per_season)), 1),
                                  "seasons": len(per_season)}
    return out


def floor_sig(x: float, sig: int = 3) -> float:
    """Round DOWN to `sig` significant figures — keeps «below X it cannot» true."""
    if x <= 0.0:
        return 0.0
    k = sig - 1 - math.floor(math.log10(x))
    return math.floor(x * 10**k) / 10**k


def ceil_sig(x: float, sig: int) -> float:
    k = sig - 1 - math.floor(math.log10(x))
    return math.ceil(x * 10**k) / 10**k


def floor_dec(x: float, n: int = 2) -> float:
    """Round DOWN to `n` decimals — keeps «carries N days» true."""
    return math.floor(x * 10**n) / 10**n


def main() -> int:
    banner("110 — winter PV autonomy of the node's EDLC (HW.54 Р3(б)(2))")
    wx = S71.load_hours()
    st = S79.site()
    times = wx["time"]
    sun = S79.sun_enu(times, st)
    gc, _ = S79.face_factors(sun)
    fields, ghi = irradiance(wx, sun, gc)
    names = list(fields)
    g_hf = np.stack([fields[n] for n in names], axis=1)
    years = f"{str(times[0])[:4]}–{str(times[-1])[:4]}"

    dec = times.astype("datetime64[M]").astype(int) % 12 + 1 == 12                            # control (3)
    dec_mean = float(ghi[dec].sum() / (dec.sum() / 24.0))
    if abs(dec_mean / float(np.mean(list(DEC_GHI_SOURCES_WH_M2_DAY.values()))) - 1.0) > DEC_GHI_TOL:
        raise SystemExit(f"control (3): December GHI {dec_mean:.0f} Wh/m²/day is off the desk's sources by > 10 %")
    sun_gates = {"geometry": S79.verify_sun_geometry(st, times), "clock": S79.verify_sun_clock(times, wx["dni"], st)}
    faces = control_faces(times, sun, gc, st["lat_deg"])                                       # control (5)
    control_eta_curves()                                                                       # control (7)
    control_store_ceiling()                                                                    # control (2)
    harvest = control_harvest_arm()                                                            # control (6)
    desk7 = worst_stretches({"ghi": ghi}, times, DESK_MONTHS)["ghi"]["7d"]                     # control (8)
    if (desk7["seasons"] != DESK_WORST_7D_DEC_JAN["seasons"]
            or any(abs(desk7[k] - DESK_WORST_7D_DEC_JAN[k]) > DESK_REPRO_TOL
                   for k in ("worst_Wh_m2_day", "median_of_season_minima_Wh_m2_day"))):
        raise SystemExit(f"control (8): the desk's worst 7-day GHI is not reproduced: {desk7}")

    combos = [(fi, d, c) for fi in range(len(names)) for d in DEMANDS for c in CORNERS]
    lanes = lanes_of(combos)
    control_zero_harvest(g_hf, combos, lanes)                                                  # control (1)
    banner(f"bisection over {len(combos)} lanes × {len(times)} hours")
    lo, hi, feasible, iters = thresholds(g_hf, lanes)
    mono = np.stack([simulate(g_hf, lanes, np.where(feasible, hi * k, BISECT_HI_CM2)) for k in MONOTONE_FACTORS])
    above = mono[MONOTONE_FACTORS.index(1.1)]                                                  # control (9)
    if np.any(np.diff(mono[:, feasible], axis=0) > 0) or np.any(above[feasible] > 0):
        raise SystemExit("control (9): outage hours are not monotone in the aperture around a threshold")

    rows = []
    for i, (fi, d, c) in enumerate(combos):
        r = {"field": names[fi], "demand": d, "corner": c}
        if feasible[i]:
            r.update(a_eff_lo_cm2=floor_sig(float(lo[i]), 6), a_eff_hi_cm2=ceil_sig(float(hi[i]), 6),
                     below_this_it_cannot_cm2=floor_sig(float(lo[i])))
        else:
            r.update(a_eff_lo_cm2=None, a_eff_hi_cm2=None, below_this_it_cannot_cm2=None,
                     none_up_to_cm2=BISECT_HI_CM2)
        rows.append(r)
    idx = {(names[fi], d, c): i for i, (fi, d, c) in enumerate(combos)}

    def thr(field: str, demand: str, corner: str):
        return rows[idx[(field, demand, corner)]]["below_this_it_cannot_cm2"]

    def raw(field: str, demand: str, corner: str) -> float:
        i = idx[(field, demand, corner)]
        return float(lo[i]) if feasible[i] else math.inf

    ends = [e[0] for e in S79.REFLECT_ENDS]
    stands = {}
    for d in DEMANDS:
        stands[d] = {}
        for c in CORNERS:
            for end in ends:
                face_raw = {f"{az:03d}": raw(f"open_face_{az:03d}.{end}", d, c) for az in OPEN_AZIMUTHS_DEG}
                iso_raw = raw(f"closed_stand.{end}", d, c)
                low_open = min(face_raw.values())
                low_all = min(low_open, iso_raw)
                if math.isinf(low_all):
                    stands[d][f"{c}.{end}"] = {"none_up_to_cm2": BISECT_HI_CM2}
                    continue
                open_low = [f"face {k}" for k, v in face_raw.items() if v <= low_open * (1 + TIE_REL)]
                faces_tied = [f"face {k}" for k, v in face_raw.items() if v <= low_all * (1 + TIE_REL)]
                iso_tied = iso_raw <= low_all * (1 + TIE_REL)
                if iso_tied and len(faces_tied) == len(OPEN_AZIMUTHS_DEG):
                    form = "all faces and both forms equal — a diffuse-only binding stretch"
                elif iso_tied:
                    form = "isotropic" + (" = beam through the gaps, " + " · ".join(faces_tied) if faces_tied else "")
                else:
                    form = "beam through the gaps, " + " · ".join(faces_tied)
                stands[d][f"{c}.{end}"] = {
                    "open_field_by_face": {f"{az:03d}": thr(f"open_face_{az:03d}.{end}", d, c) for az in OPEN_AZIMUTHS_DEG},
                    "open_field_lower": floor_sig(low_open), "open_field_lowest": open_low,
                    "closed_stand_isotropic": thr(f"closed_stand.{end}", d, c),
                    "closed_stand_lower": floor_sig(low_all), "closed_stand_lower_form": form}

    binding = {}
    for c in ("favourable", "adverse"):
        for fname in names:
            i = idx[(fname, "cadence_c", c)]
            if fname.endswith(f".{END[c]}") and feasible[i]:
                binding[f"cadence_c:{c}:{fname}"] = binding_stretch(
                    fields[fname], times, wx["dni"], demand_w("cadence_c", c), LEAK_W[c], e_max_j(c),
                    CORNER_CODE[c], float(lo[i]))

    a_face = dome_face_cm2()
    desk = {"closed_stand": [round(DESK_ETA_PV[0] * DESK_CANOPY_T[0] * a_face, 4),
                             round(DESK_ETA_PV[1] * DESK_CANOPY_T[1] * a_face, 4)],
            "open_field": [round(DESK_ETA_PV[0] * a_face, 4), round(DESK_ETA_PV[1] * a_face, 4)]}
    autonomy = {d: {c: floor_dec(e_max_j(c) / (demand_w(d, c) + LEAK_W[c]) / 86400.0) for c in CORNERS}
                for d in DEMANDS}
    for d in DEMANDS:   # the reading 01_03 §4's desk line names: §8's window (2.75 J), nominal C, §9.3's 1 µA leak
        autonomy[d]["canon_window_8_nominal_with_1uA_leak"] = floor_dec(
            EDLC_WINDOW_VSTOR_J / (demand_w(d, "nominal") + P_EDLC_LEAK_1UA_ILLUSTRATION) / 86400.0)

    def place(x: float, kind: str) -> str:
        lo_b, hi_b = desk[kind]
        return "below the whole" if x < lo_b else ("inside the" if x <= hi_b else "above the whole")

    def reading(c: str) -> str:
        top, floor = WINDOW_V[c]
        leak = "no leak" if LEAK_W[c] == 0.0 else f"§9.3's {LEAK_W[c] * 1e6:g} µW leak illustration"
        return (f"C {CAP_F[c]:.3f} F, window {top:.3f}→{floor:.3f} V, the {ETA_WORD[c]} boost curve, wake "
                f"{E_ACTIVE_J[c] * 1e3:.1f} mJ, {leak}, the {END[c]} reflected reading")

    fav = stands["cadence_c"][f"favourable.{END['favourable']}"]
    adv = stands["cadence_c"][f"adverse.{END['adverse']}"]
    sleep_fav = stands["standby_sleep"][f"favourable.{END['favourable']}"]
    if any("none_up_to_cm2" in s for s in (fav, adv, sleep_fav)):
        raise SystemExit("a lane the verdict reads has no aperture up to the top — write that sentence first")
    cl_lo, cl_hi = desk["closed_stand"]
    op_lo, op_hi = desk["open_field"]
    verdict = (
        f"At cadence C, with each input the specifications bound at its favourable end ({reading('favourable')}), the node cannot ride "
        f"{years} below {fav['closed_stand_lower']:g} cm² under the closed stand ({fav['closed_stand_lower_form']}) — "
        f"{place(fav['closed_stand_lower'], 'closed_stand')} desk bracket {cl_lo:g}–{cl_hi:g} cm² — and below "
        f"{fav['open_field_lower']:g} cm² in the open ({' · '.join(fav['open_field_lowest'])}) — "
        f"{place(fav['open_field_lower'], 'open_field')} desk bracket {op_lo:g}–{op_hi:g} cm². With each at "
        f"its adverse end ({reading('adverse')}): below {adv['closed_stand_lower']:g} cm² closed "
        f"({adv['closed_stand_lower_form']}) — {place(adv['closed_stand_lower'], 'closed_stand')} bracket — and "
        f"{adv['open_field_lower']:g} cm² open — {place(adv['open_field_lower'], 'open_field')} bracket. The Standby "
        f"sleep alone, favourable end: below {sleep_fav['closed_stand_lower']:g} cm² closed. Which closed-stand form "
        f"describes a closed stand is not established, so each sentence takes the lower. Necessary conditions only.")

    out = {
        "script": "110_winter_pv_autonomy.py",
        "leg": "00_07 HW.54 Р3(б)(2)",
        "what": "necessary effective aperture A_eff = eta_pv · T · A of a PV cell on the dome for the EDLC never to "
                "empty over the hourly record, per field, demand and corner; lower bracket end, rounded down",
        "record": {"start": str(times[0]), "end": str(times[-1]), "hours": len(times)},
        "inputs": {
            "corners": {c: {"capacitance_f": round(CAP_F[c], 4), "window_v": list(WINDOW_V[c]),
                            "e_max_j": round(e_max_j(c), 4), "wake_energy_mj": round(E_ACTIVE_J[c] * 1e3, 3),
                            "leak_uw": round(LEAK_W[c] * 1e6, 3), "boost_eta_anchors_uw": ANCHORS.get(c),
                            "boost_eta_v_op_v": ETA_V_OP.get(c), "boost_eta_curve": ETA_WORD[c],
                            "reflected_end_in_the_sentence": END.get(c)}
                        for c in CORNERS},
            "boost_eta_ceiling": ETA_CAP,
            "demand_uw": {d: {c: round(demand_w(d, c) * 1e6, 3) for c in CORNERS} for d in DEMANDS},
            "cadence_c_interval_s": round(H_CADENCE_C_S, 1),
            "dome_face_cm2": round(a_face, 3), "desk_eta_pv_assumed": list(DESK_ETA_PV),
            "desk_canopy_t": list(DESK_CANOPY_T), "reflected_ends": ends, "sources": SOURCES,
        },
        "controls": {"zero_harvest_onset": "matches its closed form on every lane",
                     "store_ceiling": f"empties from E_max after each of {list(CEILING_CONTROL_K_H)} blinding hours",
                     "december_ghi_Wh_m2_day": round(dec_mean, 1), "december_ghi_sources": DEC_GHI_SOURCES_WH_M2_DAY,
                     "sun_gates_of_79": sun_gates, "faces": faces, "harvest_arm": harvest,
                     "eta_curves": "vector ≡ scalar, ordered favourable ≥ nominal ≥ adverse",
                     "desk_worst_7d_dec_jan": {"desk": DESK_WORST_7D_DEC_JAN, "here": desk7},
                     "monotone_factors": list(MONOTONE_FACTORS), "bisection_iterations": iters,
                     "lanes_with_no_aperture_up_to_the_top": int((~feasible).sum())},
        "autonomy_days_without_sun": autonomy,
        "autonomy_note": "rounded down; canon_window_8_nominal_with_1uA_leak is §8's 2.75 J window (from OK_HYST) — "
                         "the reading 01_03 §4's desk line names",
        "worst_stretch": worst_stretches(dict(fields, ghi_horizontal=ghi), times, WINTER_MONTHS),
        "worst_stretch_note": "irradiance on the face before A_eff, Wh/m²/day: eta_pv and the canopy's T are folded "
                              "into A_eff, so closed_stand.* here is ½(1+ρ)·GHI without T",
        "necessary_a_eff_cm2": {d: {c: {f: thr(f, d, c) for f in names} for c in CORNERS} for d in DEMANDS},
        "stands": stands,
        "binding_stretches": binding,
        "desk_bracket_a_eff_cm2": desk,
        "thresholds": rows,
        "verdict": verdict,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    print(f"  December GHI {dec_mean:.0f} Wh/m²/day · desk 7-day {desk7['worst_Wh_m2_day']} / "
          f"{desk7['median_of_season_minima_Wh_m2_day']} ({desk7['seasons']} seasons) · harvest control {harvest}")
    for d in DEMANDS:
        for key in (f"favourable.{END['favourable']}", f"nominal.{END['favourable']}", f"adverse.{END['adverse']}"):
            s = stands[d][key]
            if "none_up_to_cm2" in s:
                print(f"  {d:16s} {key:16s} no aperture up to {BISECT_HI_CM2:g} cm²")
                continue
            print(f"  {d:16s} {key:16s} closed ≥ {s['closed_stand_lower']:<8g} ({s['closed_stand_lower_form']}) · "
                  f"open ≥ {s['open_field_lower']:<8g}")
    print("  " + verdict)
    print(f"\n  wrote {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
