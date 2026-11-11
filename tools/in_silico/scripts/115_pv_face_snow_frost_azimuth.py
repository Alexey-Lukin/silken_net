#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""115 — how far snow and hoarfrost on the dome's face, and an azimuth set by the gateway rather than by the sun, can
raise the aperture a PV cell on the dome needs to carry the node through the worst winter of thirty years (00_07 HW.54,
the leg «Р3(б) — PV на куполі: що лишилось машині»: сніг, іній і азимут, заданий шлюзом, а не сонцем).

WHY. `110` gives the necessary effective aperture A_eff on four open faces and the closed stand, with the face always
clear. Two things it does not see: a face that is covered (frost, plastered snow) passes less or no light while the
store is draining; and the face's azimuth is not ours to pick — the ratified mounting rule turns the flange's face
towards its own gateway, within ±50° of the gateway's bearing (01_04 §3.1, ⚖️ 2026-10-22), and across a cluster the
bearings take every direction.

FOUR READINGS OF THE COVER, NONE PICKED (in-silico §When Modifying #10 — the bound first). Two are named by how they
are built (melt only · vapour budget + NREL slide), two by where they land (ceiling · favourable end) — and where a
reading lands is MEASURED below, never granted by its name:
  CEILING — the face as cold as this model allows, cleared by the melt rule (not the slowest clearing here — the slide
    of the vapour budget can outlast it): no light absorbed (α = 0), a clear sky every
    hour (`79`'s Brutsaert emissivity, cloud ignored), still air; frost in every hour the face is below 0 °C and below
    the frost point; plastered snow in every hour the snow depth rises by ≥ 2 mm in EITHER reanalysis `79` reads with
    the air at or below +1 °C; a cover clears only when the face is above 0 °C; a covered face passes no light.
  MELT ONLY — the face's physics set to a dark cell's values, the ceiling's clearing rule kept: α = 0.9 (a dark cell behind the window takes
    the light; for a thin hoar the window's resistance is small against the outer film's), `79`'s cloud-weighted sky
    (its «linear» form on ERA5's cloud cover), convection at the trunk's wind k·u10 with `79`'s typical k = 0.1 (the
    larger of natural and forced); snow events only in ERA5-Land (CERRA's hourly rises carry a forecast-cycle seam at
    local 10:00), a rise ≥ 1 cm/h — NREL's threshold for a new cover (Marion et al. 2013, via pvlib `coverage_nrel`) —
    and only wet snow, −1 … +1 °C (OUR assumption that dry snow does not plaster a vertical face — the kind direction,
    and the one this script cannot test); a cover clears only above 0 °C.
  VAPOUR BUDGET + NREL SLIDE (cache key `nrel_published`) — the same air, sky and wet-snow events as melt only (ours);
    frost as OUR mass budget on the COVERED face's temperature (α = ALPHA_COVER, also while the face is bare), deposited
    and sublimated at the Chilton–Colburn rate h_m = h_c/(ρc_p·Le^{2/3}) on the difference between the air's vapour
    density (ERA5's dew point) and ice saturation at the face, melted when that face is
    above 0 °C, the face blind while the deposit exceeds FROST_BLIND_KG_M2 (ours — a thin hoar passes light); plastered
    snow covers the face and slides off at NREL's rate, 0.197 of the face per hour times sin 90°, in every hour the air
    is warmer than −G_face/80 (Marion et al. 2013) — sliding stands for the melt at the interface there, so no melt is
    added — the face passing light in proportion to its uncovered share.
  FAVOURABLE END — as VAPOUR BUDGET + NREL SLIDE, but run on the BARE dark cell's temperature (α 0.9): its frost both
    deposits less (a warmer face) and melts, and every cover clears in any hour that cell would be above 0 °C — the
    cover heated by light it is said to block, plus a 100 % clearance in one hour whatever its mass — the end of the
    readings most favourable to PV, never a central estimate.
  Their ORDER is measured, not declared (`readings_order_for_pv`, cell by cell on the thresholds): the names above say
  how each reading is built, not where it lands — melt only is the harsher on frost, the vapour budget + NREL slide on snow.
  Each reading's longest covered run per winter is printed against `110`'s autonomy, for snow alone and frost alone as
  well as together — a run shorter than the autonomy is necessary, not sufficient, so the threshold itself is re-run.
THRESHOLD — `110`'s own machinery (its fields, lanes, harvest arm and bisection, imported) on the covered fields, at
  cadence C on its three corners; uncovered, it must bracket `110`'s cached thresholds (control 1).
AZIMUTH — `79`'s eight faces. For a gateway on bearing b the installer may face the flange anywhere within ±50° of b; on
  the 45° grid that is b − 45 · b · b + 45, and the best of the three is what that node can have (its radio's margin
  for the 45° off the bearing is the mounting rule's to price, not this script's). The worst bearing over the eight is
  what the design must carry, set beside the south face.

WHAT IT CANNOT SEE. Rime from supercooled fog (no fog or liquid-water variable in the record); the face's heat capacity
and the window's conduction to and from the capsule (it can warm the face at night and cool it at midday — not one
sign); wind direction for plastered snow; the ground's half of the view is held at the air's temperature (snow is
colder); azimuths between the 45° grid; a frost layer's partial transmission beyond the one threshold; whether dry snow
plasters a small vertical face (taken as not — three of the four readings rest on it, in the kind direction); and whether
NREL's slide rate (Marion et al. 2013, taken through pvlib at sin 90° = 1) transfers to a 30 mm vertical face. The window, the
cell and its efficiency are not chosen here (`110`'s A_eff carries them).

CONTROLS (each says what it CAN and CANNOT catch).
  (1) Uncovered, every row `110` holds for cadence C (the open faces 0 · 90 · 180 · 270 and the closed stand, both
      reflect ends, three corners) lies inside 115's own bracket [floor_sig(lo), floor_sig(hi)]; CAN catch a field or a
      lane built differently from `110`'s on those faces, CANNOT the diagonal faces 45 · 135 · 225 · 315 (110 holds no
      row for them — they share the formula, not a check), a cover applied to the wrong column, or an error inside
      `110`'s machinery (that is `110`'s controls').
  (2) Sky term: on one face, the dark face under the cloud-weighted sky is never colder than under the clear sky, the
      dark clear-sky still-air face never warmer than the air, and a full cloud cover radiates exactly at the air's
      temperature; CAN catch a sign slip or a reversed cloud weighting, CANNOT a wrong coefficient.
  (3) Clearing, on synthetic records: one event, three cold hours, a warm one blinds exactly four hours under the melt
      rule; a full snow cover with sliding allowed is gone in ⌈1/0.197⌉ hours; NREL's slide test has its sign (at
      G = 100 W/m², −1 °C slides and −2 °C does not); a cover with no slide is gone in the first warm hour and a snowfall
      in a warm hour leaves none; CAN catch a persistence slip, a flipped slide sign or a dead warm path, CANNOT a wrong
      event threshold.
  (4) Azimuth window: the best-in-window over the grid neighbours equals the minimum over every face within ±50° by
      angular distance; CAN catch a window on the wrong neighbours or a reordered azimuth list, CANNOT a grid too
      coarse.

Run:  python tools/in_silico/scripts/115_pv_face_snow_frost_azimuth.py      # a few minutes (30 years hourly, bisection)
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import KINETICS_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("How far snow and hoarfrost on the sensor capsule's dome, and a face azimuth set by the radio gateway "
                  "rather than by the sun, can raise the aperture a small photovoltaic cell on the dome needs to keep the "
                  "node's supercapacitor from running empty through thirty winters — four readings of the cover named by "
                  "how they are built, their order measured on the thresholds, on the hourly climate record.")

HERE = Path(__file__).resolve().parent
OUT = KINETICS_DIR / "pv_face_snow_frost_azimuth.json"
PV_AUTONOMY = KINETICS_DIR / "winter_pv_autonomy.json"
DEMAND = "cadence_c"
WINDOW_DEG = 50.0                 # the ratified mounting window (01_04 §3.1, ⚖️ 2026-10-22) — mirror, edit there
WINTER_MONTHS = (11, 12, 1, 2, 3)
WIND_K_PLAUSIBLE = 0.1            # `79`'s typical trunk breeze, u = k·u10 (its WIND_K) — asserted against it below
WIND_K_DIAGNOSTIC = (0.0, 0.1, 0.3)
CEILING_SNOW_STEP_M, CEILING_SNOW_MAX_C = 0.002, 1.0
NREL_SNOW_STEP_M = 0.01           # 1 cm/h — pvlib `coverage_nrel` threshold_snowfall (Marion et al. 2013)
WET_SNOW_C = (-1.0, 1.0)          # ours: only wet snow plasters a vertical face
NREL_SLIDE_PER_H = 0.197          # pvlib `coverage_nrel` slide_amount_coefficient × sin(90°)
NREL_CAN_SLIDE_W_M2_C = -80.0     # pvlib `coverage_nrel` can_slide_coefficient: slides when T_air > G / (−80)
ALPHA_DARK_CELL = 0.9             # ours
ALPHA_COVER = 0.3                 # ours: a face under hoar or snow absorbs far less than the bare dark cell
LEWIS = 0.86                      # water vapour in air, α/D ≈ 1.9e-5 / 2.2e-5 m²/s near 0 °C — ours, rounded
FROST_BLIND_KG_M2 = 0.05          # ours: ≈ 0.5 mm of hoar at ~100 kg/m³ — below it a thin hoar is taken to pass light
M_W, R_GAS = 0.018015, 8.314462


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S110 = _load("s110_pv", "110_winter_pv_autonomy.py")
S79, S71 = S110.S79, S110.S71
assert WIND_K_PLAUSIBLE in S79.WIND_K, "the plausible wind factor must be one of 79's"


def e_ice_hpa(t_c):
    return 6.112 * np.exp(22.46 * t_c / (272.62 + t_c))


def frost_point_c(t_dew_c):
    """The temperature at which ice saturation equals the vapour pressure set by ERA5's dew point (over water)."""
    ln = np.log(S79.vapour_pressure_hpa(t_dew_c) / 6.112)
    return 272.62 * ln / (22.46 - ln)


def h_conv(d_m, dt, film_c, u_m_s):
    h = S71.h_natural(d_m, np.maximum(np.abs(dt), 1e-3), film_c)
    return h if u_m_s is None else np.maximum(h, S71.h_forced(d_m, u_m_s, film_c))


def face_temperature_c(t_air_c, q_abs_w_m2, t_sky4_k4, d_m, u_m_s=None, iters: int = 30):
    """Quasi-steady face: convection + long-wave to the sky (view SKY_VIEW) and to the air + absorbed light."""
    ta = t_air_c + 273.15
    t_env4 = S79.SKY_VIEW * t_sky4_k4 + (1.0 - S79.SKY_VIEW) * ta ** 4
    t = ta + np.zeros_like(q_abs_w_m2)
    for _ in range(iters):
        h_c = h_conv(d_m, t - ta, 0.5 * (t + ta) - 273.15, u_m_s)
        h_r = 4.0 * S79.EPSILON * S79.SIGMA * t ** 3
        t = t + (h_c * (ta - t) + q_abs_w_m2 + S79.EPSILON * S79.SIGMA * (t_env4 - t ** 4)) / (h_c + h_r)
    return t - 273.15


def melt_blind(event: np.ndarray, clear: np.ndarray) -> np.ndarray:
    """Blind from an event (that is not itself clear) until the first clear hour after it (along axis 0)."""
    idx = np.arange(event.shape[0]).reshape((-1,) + (1,) * (event.ndim - 1))
    ev = event & ~clear
    last_ev = np.maximum.accumulate(np.where(ev, idx, -1), axis=0)
    last_cl = np.maximum.accumulate(np.where(clear, idx, -1), axis=0)
    return last_ev > last_cl


def frost_budget(flux_kg_m2_h: np.ndarray, warm: np.ndarray) -> np.ndarray:
    """The frost deposit (kg/m²) hour by hour: grows or sublimates by the flux below 0 °C, gone above it."""
    m = np.zeros(flux_kg_m2_h.shape)
    cur = np.zeros(flux_kg_m2_h.shape[1:])
    for i in range(flux_kg_m2_h.shape[0]):
        cur = np.where(warm[i], 0.0, np.maximum(cur + flux_kg_m2_h[i], 0.0))
        m[i] = cur
    return m


def snow_slide(event: np.ndarray, can_slide: np.ndarray, warm: np.ndarray | None = None) -> np.ndarray:
    """NREL's cover: 1 on a new snowfall, minus the slide in every hour it can slide, gone in an hour the face is above
    0 °C (when `warm` is given) — along axis 0."""
    c = np.zeros(event.shape)
    cur = np.zeros(event.shape[1:])
    for i in range(event.shape[0]):
        cur = np.where(event[i], 1.0, np.where(can_slide[i], np.maximum(cur - NREL_SLIDE_PER_H, 0.0), cur))
        if warm is not None:
            cur = np.where(warm[i], 0.0, cur)                 # one rule with melt_blind: a warm hour leaves no cover
        c[i] = cur
    return c


def can_slide_mask(t_air_c, g_w_m2):
    """NREL: snow can slide in an hour the air is warmer than G / can_slide_coefficient (−80 W/(m²·°C))."""
    return t_air_c > g_w_m2 / NREL_CAN_SLIDE_W_M2_C


def longest_runs_h(covered: np.ndarray, season: np.ndarray, n_seasons: int) -> np.ndarray:
    """The longest run of consecutive covered hours per winter season (index ≥ 0), per column."""
    out = np.zeros((n_seasons, *covered.shape[1:]), dtype=np.int64)
    run = np.zeros(covered.shape[1:], dtype=np.int64)
    prev = -2
    for i in range(covered.shape[0]):
        s = season[i]
        if s != prev:
            run = np.zeros_like(run)
            prev = s
        if s < 0:
            continue
        run = np.where(covered[i], run + 1, 0)
        out[s] = np.maximum(out[s], run)
    return out


def control_clearing() -> None:
    ev = np.zeros((6, 1), bool)
    ev[0] = True
    clear = np.array([[False], [False], [False], [False], [True], [False]])
    assert melt_blind(ev, clear)[:, 0].tolist() == [True, True, True, True, False, False]
    ev2 = np.zeros((10, 1), bool)
    ev2[0] = True
    c = snow_slide(ev2, np.ones((10, 1), bool))
    assert int((c[:, 0] > 0).sum()) == math.ceil(1.0 / NREL_SLIDE_PER_H), c[:, 0]
    # the sign of NREL's slide test: at G = 100 W/m² the air must be warmer than −1.25 °C
    assert can_slide_mask(np.array([-1.0, -2.0]), np.array([100.0, 100.0])).tolist() == [True, False]
    # the warm path: a cover with no slide is gone in the first warm hour, and a snowfall in a warm hour leaves none
    warm = np.array([[False], [False], [True], [False], [True]])
    ev3 = np.array([[True], [False], [False], [False], [True]])
    c3 = snow_slide(ev3, np.zeros((5, 1), bool), warm)
    assert c3[:, 0].tolist() == [1.0, 1.0, 0.0, 0.0, 0.0], c3[:, 0]


def cover_readings(wx: dict, g: np.ndarray, snow: dict, d_dome: float) -> dict:
    """The four readings' covers of a small face lit by `g` (hours, fields; W/m²) — the ONE home of the cover model:
    115's own main and 118 call it. Returns, per reading, (cover fraction, snow-only covered, frost-only covered), each
    (hours, fields); and the inputs main reuses (the two snow-event series, the cloud-weighted sky,
    the frost point). Every operation is per column, so a call on a subset of fields gives those columns of a call on
    all of them. Control (2) runs here, on every call."""
    ta = wx["t_air"][:, None]
    ta4 = (ta + 273.15) ** 4
    t_sky4_clear = S79.sky_emissivity(wx["t_air"], wx["t_dew"])[:, None] * ta4
    t_sky4_cloud = wx["cloud"][:, None] * ta4 + (1.0 - wx["cloud"][:, None]) * t_sky4_clear
    t_fp = frost_point_c(wx["t_dew"])[:, None]
    u_k = WIND_K_PLAUSIBLE * wx["u10"][:, None]

    # snow events
    rise_mm = {n: np.concatenate([[0], np.rint(np.diff(r["depth_m"]) * 1000.0).astype(int)]) for n, r in snow.items()}
    assert set(rise_mm) == {"era5_land", "cerra"}, set(rise_mm)              # depth sits on a grid: compare in whole mm
    ev_snow_ceiling = ((rise_mm["era5_land"] >= round(CEILING_SNOW_STEP_M * 1000))
                       | (rise_mm["cerra"] >= round(CEILING_SNOW_STEP_M * 1000))) & (wx["t_air"] <= CEILING_SNOW_MAX_C)
    ev_snow_nrel = ((rise_mm["era5_land"] >= round(NREL_SNOW_STEP_M * 1000))
                    & (wx["t_air"] >= WET_SNOW_C[0]) & (wx["t_air"] <= WET_SNOW_C[1]))
    assert ev_snow_ceiling.sum() > 0 and ev_snow_nrel.sum() > 0, "positive control: no snowfall in thirty winters"

    # the faces
    t_ceiling = face_temperature_c(ta, np.zeros_like(g), t_sky4_clear, d_dome)
    t_plaus = face_temperature_c(ta, ALPHA_DARK_CELL * g, t_sky4_cloud, d_dome, u_k)
    t_dark_cloud = face_temperature_c(ta, np.zeros_like(g[:, :1]), t_sky4_cloud, d_dome)          # control (2)
    overcast = np.ones_like(wx["cloud"])[:, None] * ta4 + (1.0 - np.ones_like(wx["cloud"])[:, None]) * t_sky4_clear
    assert np.allclose(overcast, ta4, rtol=0, atol=1e-6), "control (2): a full cloud cover must radiate at the air"
    assert np.all(t_dark_cloud >= t_ceiling[:, :1] - 1e-6) and np.all(t_ceiling <= ta + 1e-6), "control (2)"

    # the covers, per reading: (cover fraction (hours, fields), snow-only covered, frost-only covered)
    covers = {}
    fr = (t_ceiling < 0.0) & (t_ceiling < t_fp)
    clear = t_ceiling > 0.0
    covers["ceiling"] = (melt_blind(fr | ev_snow_ceiling[:, None], clear).astype(float),
                         melt_blind(np.repeat(ev_snow_ceiling[:, None], g.shape[1], 1), clear), melt_blind(fr, clear))
    fr = (t_plaus < 0.0) & (t_plaus < t_fp)
    clear = t_plaus > 0.0
    blind = melt_blind(fr | ev_snow_nrel[:, None], clear)
    assert not np.any(blind & clear), "control (3): a melt-rule blind hour with the face above 0 °C"
    covers["melt_only"] = (blind.astype(float), melt_blind(np.repeat(ev_snow_nrel[:, None], g.shape[1], 1), clear),
                           melt_blind(fr, clear))
    t_cov = face_temperature_c(ta, ALPHA_COVER * g, t_sky4_cloud, d_dome, u_k)
    rho_v_air = S79.vapour_pressure_hpa(wx["t_dew"])[:, None] * 100.0 * M_W / (R_GAS * (ta + 273.15))
    can_slide = can_slide_mask(ta, g)
    events = np.repeat(ev_snow_nrel[:, None], g.shape[1], 1)
    for reading, t_face in (("nrel_published", t_cov), ("favourable_end", t_plaus)):
        film = 0.5 * (t_face + ta)
        p_air = S71.air_props(film)
        h_m = h_conv(d_dome, t_face - ta, film, u_k) / ((p_air["k"] / p_air["alpha"]) * LEWIS ** (2.0 / 3.0))
        rho_v_ice = e_ice_hpa(np.minimum(t_face, 0.0)) * 100.0 * M_W / (R_GAS * (t_face + 273.15))
        warm = t_face > 0.0
        flux = h_m * (rho_v_air - rho_v_ice) * 3600.0
        m = frost_budget(flux, warm)
        c_snow = snow_slide(events, can_slide, warm if reading == "favourable_end" else None)
        frost_cov = m > FROST_BLIND_KG_M2
        covers[reading] = (np.maximum(c_snow, frost_cov.astype(float)), c_snow > 0.0, frost_cov)
    return {"covers": covers, "ev_snow_ceiling": ev_snow_ceiling, "ev_snow_nrel": ev_snow_nrel,
            "t_sky4_cloud": t_sky4_cloud, "t_fp": t_fp}


def reading_order(by_field: dict, readings: list) -> dict:
    """The readings' order, MEASURED on every field × corner threshold (None — no aperture up to the scan's top — is the
    most adverse), never declared: a name such as «ceiling» or «favourable end» is a claim about a direction, and two
    readings that differ in kind (melt only: frost every cold hour; the vapour budget + NREL slide: frost as a mass budget,
    snow sliding off) need
    not be ordered at all. A precedes B (more adverse) when B is never the more adverse in any cell; a pair with cells
    either way is reported unordered, not forced into a line. The line is re-checked cell by cell in
    `test_pv_snow_frost_order_and_azimuth_are_recomputed` (with no unordered pair, per-cell ≥ is transitive, so an assert
    here would restate the sort)."""
    def val(x):
        return math.inf if x is None else x
    cells = [r for v in by_field.values() for r in v.values()]
    kinder = {(a, b): sum(val(r[a]) < val(r[b]) for r in cells) for a in readings for b in readings if a != b}
    unordered = sorted({tuple(sorted((a, b))) for (a, b), n in kinder.items() if n and kinder[(b, a)]})
    line = sorted(readings, key=lambda a: -sum(kinder[(b, a)] > 0 for b in readings if b != a))
    assert all(val(r["none"]) <= val(r[a]) for r in cells for a in readings), "a covered face beat the clear one"
    all_none = sum(all(r[a] is None for a in readings) for r in cells)
    return {"measured_on": f"{len(cells)} field × corner thresholds of `by_field`, within the scan's top: None (no aperture "
                           "up to it) is the most adverse, two Nones agree, so a crossing above the top is invisible",
            "cells_where_every_reading_is_none": all_none,
            "adverse_to_favourable": None if unordered else line,
            "unordered_pairs": [list(u) for u in unordered],
            "cells_strictly_kinder": {f"{a}<{b}": n for (a, b), n in kinder.items() if n}}


def main() -> int:
    banner("HW.54 Р3(б) — snow, hoarfrost and a gateway-set azimuth on the dome's PV face (four readings)")
    z110 = json.loads(PV_AUTONOMY.read_text())
    wx = S79.load_weather()
    times = wx["time"]
    assert len(times) == z110["record"]["hours"], "the record ≠ 110's"
    st = S79.site()
    sun = S79.sun_enu(times, st)
    gc, _ = S79.face_factors(sun)
    ghi = wx["dni"] * np.maximum(sun[2], 0.0).mean(axis=1) + wx["dif"]
    snow = S79.load_snow(times)
    refl = S79.reflected_rows(snow, ghi)
    ends = [e[0] for e in S79.REFLECT_ENDS]
    d_dome = S71.geometry()["dome_diameter_mm"] / 1000.0
    control_clearing()

    names, cols = [], []
    for k, end in enumerate(ends, start=1):
        names.append(f"closed_stand.{end}")
        cols.append(0.5 * ghi + 0.5 * refl[k])
        for j, az in enumerate(S79.AZIMUTHS_DEG):
            names.append(f"open_face_{az:03d}.{end}")
            cols.append(wx["dni"] * gc[j] + 0.5 * wx["dif"] + 0.5 * refl[k])
    g = np.stack(cols, axis=1)                                    # (hours, fields) — the light on each face, W/m²
    ta = wx["t_air"][:, None]
    cr = cover_readings(wx, g, snow, d_dome)
    covers, ev_snow_ceiling, ev_snow_nrel = cr["covers"], cr["ev_snow_ceiling"], cr["ev_snow_nrel"]
    t_sky4_cloud, t_fp = cr["t_sky4_cloud"], cr["t_fp"]

    # statistics
    month = times.astype("datetime64[M]").astype(int) % 12 + 1
    year = times.astype("datetime64[Y]").astype(int) + 1970
    winter = np.isin(month, WINTER_MONTHS)
    season_year = np.where(month >= 11, year + 1, year)
    season = np.where(winter & (season_year > year.min()) & (season_year <= year.max()), season_year - year.min() - 1, -1)
    n_seasons = int(season.max()) + 1
    autonomy = {k: v for k, v in z110["autonomy_days_without_sun"][DEMAND].items() if k in S110.CORNERS}
    years = len(times) / 8766.0
    stats = {}
    for reading, (cov, sn_only, fr_only) in covers.items():
        runs = {lbl: longest_runs_h(x > 0.0, season, n_seasons) / 24.0
                for lbl, x in (("together", cov), ("snow_only", sn_only.astype(float)), ("frost_only", fr_only.astype(float)))}
        for j, name in enumerate(names):
            stats[f"{name}:{reading}"] = {
                **{f"longest_run_days_{lbl}_median_max": [round(float(np.median(r[:, j])), 1), round(float(r[:, j].max()), 1)]
                   for lbl, r in runs.items()},
                "winters_with_run_over_110_autonomy": {c: int((runs["together"][:, j] > d).sum()) for c, d in autonomy.items()},
                "winters": n_seasons,
                "covered_h_per_winter": round(float((cov[:, j] > 0)[winter].sum()) / years, 1),
                "light_lost_share_of_winter_harvest": round(float((g[:, j] * cov[:, j])[winter].sum() / g[:, j][winter].sum()), 4)}
    frost_h_by_k = {}
    i_s = names.index("open_face_180.low")
    for k in WIND_K_DIAGNOSTIC:
        tk = face_temperature_c(ta, ALPHA_DARK_CELL * g[:, i_s:i_s + 1], t_sky4_cloud, d_dome,
                                k * wx["u10"][:, None] if k > 0 else None)
        frost_h_by_k[f"{k:g}"] = round(float((((tk < 0.0) & (tk < t_fp))[:, 0] & winter).sum()) / years, 1)

    # thresholds: every field × {none, four readings} × corner
    variants = ("none", *covers)
    lane_names, lane_cols = [], []
    for j, name in enumerate(names):
        for v in variants:
            lane_names.append(f"{name}|{v}")
            lane_cols.append(g[:, j] if v == "none" else g[:, j] * (1.0 - covers[v][0][:, j]))
    g_hf = np.stack(lane_cols, axis=1)
    combos = [(fi, DEMAND, c) for fi in range(len(lane_names)) for c in S110.CORNERS]
    lanes = S110.lanes_of(combos)
    banner(f"bisection over {len(combos)} lanes × {len(times)} hours")
    lo, hi, feasible, _ = S110.thresholds(g_hf, lanes)
    thr, bracket = {}, {}
    for i, (fi, _, c) in enumerate(combos):
        thr[(lane_names[fi], c)] = S110.floor_sig(float(lo[i])) if feasible[i] else None
        bracket[(lane_names[fi], c)] = (S110.floor_sig(float(lo[i])), S110.floor_sig(float(hi[i]))) if feasible[i] else None

    ref = z110["necessary_a_eff_cm2"][DEMAND]                                                # control (1)
    checked = 0
    for c in S110.CORNERS:
        for field, want in ref[c].items():
            b = bracket[(f"{field}|none", c)]
            assert b is not None and b[0] <= want <= b[1], (field, c, b, want)
            checked += 1
    assert checked == sum(len(v) for v in ref.values()) == 30, checked

    az = list(S79.AZIMUTHS_DEG)
    step = 45
    nwin = int(WINDOW_DEG // step)
    azimuth = {}
    for end in ends:
        for c in S110.CORNERS:
            for v in variants:
                own = [thr[(f"open_face_{b:03d}.{end}|{v}", c)] for b in az]
                arr = np.array([math.inf if x is None else x for x in own])
                best = {}
                for i, b in enumerate(az):
                    best[b] = min(arr[(i + k) % len(az)] for k in range(-nwin, nwin + 1))
                    by_angle = min(arr[j] for j, a in enumerate(az)                                   # control (4)
                                   if min(abs(a - b) % 360, 360 - abs(a - b) % 360) <= WINDOW_DEG)
                    assert best[b] == by_angle, (b, best[b], by_angle)
                finite = [b for b in az if math.isfinite(best[b])]
                none_b = [b for b in az if not math.isfinite(best[b])]
                worst_b = None if not finite else (none_b[0] if none_b else max(finite, key=lambda b: best[b]))
                south = own[az.index(180)]
                worst_val = None if worst_b is None or not math.isfinite(best[worst_b]) else best[worst_b]
                azimuth[f"{end}:{c}:{v}"] = {
                    "best_in_window_by_bearing": {f"{b:03d}": (best[b] if math.isfinite(best[b]) else None) for b in az},
                    "bearings_with_none_up_to_cm2": {"bearings": [f"{b:03d}" for b in none_b], "top_cm2": S110.BISECT_HI_CM2},
                    "worst_bearing": None if worst_b is None else f"{worst_b:03d}", "worst_bearing_cm2": worst_val,
                    "south_face_cm2": south,
                    "worst_over_south": round(worst_val / south, 3) if (worst_val and south) else None}
    by_field = {name: {c: {v: thr[(f"{name}|{v}", c)] for v in variants} for c in S110.CORNERS} for name in names}

    # ── print ──
    for end in ends:
        for c in S110.CORNERS:
            row = " | ".join(f"{v}: worst {azimuth[f'{end}:{c}:{v}']['worst_bearing']} "
                             f"{azimuth[f'{end}:{c}:{v}']['worst_bearing_cm2']} (south {azimuth[f'{end}:{c}:{v}']['south_face_cm2']})"
                             for v in variants)
            print(f"  {end:4s} {c:10s} {row}")
    for v in covers:
        for f in ("open_face_180.low", "open_face_000.low", "closed_stand.low"):
            print(f"  {v:17s} {f:20s} {stats[f'{f}:{v}']}")
    print(f"  frost-event hours per winter on the south face at k = {WIND_K_DIAGNOSTIC}: {frost_h_by_k}")
    print(f"  snow events per year: ceiling {round(float(ev_snow_ceiling.sum()) / years, 1)} h · "
          f"NREL wet {round(float(ev_snow_nrel.sum()) / years, 1)} h")

    OUT.write_text(json.dumps({
        "script": Path(__file__).name,
        "leg": "00_07 HW.54 Р3(б)",
        "what": "four readings of snow and hoarfrost cover on the dome's PV face, named by how they are built (a ceiling, "
                "melt only, a vapour budget with NREL's slide rate on our wet-snow events, a favourable end; their order is "
                "measured in readings_order_for_pv) against 110's necessary A_eff at cadence C, and the A_eff a node can have when its "
                "face is set within the mounting window of its gateway's bearing",
        "inputs": {"demand": DEMAND, "mounting_window_deg": WINDOW_DEG, "winter_months": WINTER_MONTHS,
                   "wind_k_plausible": WIND_K_PLAUSIBLE, "alpha_dark_cell": ALPHA_DARK_CELL, "lewis": LEWIS,
                   "frost_blind_kg_m2": FROST_BLIND_KG_M2, "ceiling_snow": [CEILING_SNOW_STEP_M, CEILING_SNOW_MAX_C],
                   "nrel_snow_step_m": NREL_SNOW_STEP_M, "wet_snow_C": WET_SNOW_C, "nrel_slide_per_h": NREL_SLIDE_PER_H,
                   "nrel_can_slide_W_m2_C": NREL_CAN_SLIDE_W_M2_C, "dome_diameter_m": d_dome, "azimuths_deg": az,
                   "sources": {"fields_lanes_bisection": "110 (imported)", "sun_faces_weather_snow_sky_wind_k": "79 (imported)",
                               "convection_air": "71 h_natural · h_forced · air_props",
                               "snow_cover_model": "Marion et al. 2013, Solar Energy 97:112, as pvlib coverage_nrel "
                                                   "(v0.11.2 source read 2026-10-31)",
                               "window": "01_04 §3.1 (⚖️ 2026-10-22)"}},
        "controls": {"brackets_110_rows": checked, "sky_term": "cloud ≥ clear; dark still clear ≤ air",
                     "clearing": "melt synthetic 4 h; no melt-blind hour above 0 °C; full snow cover gone in "
                                 f"{math.ceil(1 / NREL_SLIDE_PER_H)} h; frost zeroed above 0 °C by construction (not asserted)",
                     "window": "best = min over three neighbours by modular indexing, checked against an angular-distance minimum"},
        "snow_event_h_per_year": {"ceiling": round(float(ev_snow_ceiling.sum()) / years, 1),
                                  "nrel_wet": round(float(ev_snow_nrel.sum()) / years, 1)},
        "readings_order_for_pv": reading_order(by_field, list(covers)),
        "radio_caveat": "the best face within ±50° of the gateway's bearing is what the mounting rule allows; the radio's "
                        "cost of turning up to 45° off the bearing is the mounting rule's to price, not priced here",
        "frost_event_h_per_winter_south_by_wind_k": frost_h_by_k,
        "autonomy_days_110": autonomy,
        "covers": stats,
        "by_field": by_field,
        "azimuth": azimuth,
    }, indent=2, ensure_ascii=False))
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
