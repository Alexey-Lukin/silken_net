#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""125 — the stem-face light logger in a courtyard: how much of the winter light of an open stem face reaches the
logger's face when a two-storey building stands on three sides of the tree and the yard is open to one
(00_07 HW.54, the leg «Р3(б)(4) — порахувати, скільки прямого й розсіяного світла доходить до грані S у дворі»;
the sheet `docs/protocols/ebfc/stem_face_winter_light.md` §1).

WHY. The verdict that put ONE logger on the SOUTH face (01_03 §4, ⊕ under Р3(б)(4), 2026-11-09) named its weakest
link: a house in the southern sector shades exactly that face, and then the question returns to the founder. On
2026-11-14 the founder gave the yard twice: by word and a phone compass (open toward a true heading of 210°, «about
150°–270°», a two-storey building «about 7 m» away on the other three sides, the roof edge «about 7 m» up), and then
by a satellite image of the court, north up. Read by eye off that image: the back wall faces about 215°, the opening
seen from the tree is about 167°–256° — narrower than the words' 150°–270° —, the tree stands nearer the back wall
than the wings. What stands beyond the opening the image does not say: two readings of it (this script's first, and
another model's the founder passed on) put trees there, and the founder, who sees the yard, corrected both the same
day — beyond the driveway stand low trimmed bushes and a parking area with a few trees, deciduous ones: nothing at
the winter sun's height. He added what no reading of the image had: the pine is one of THREE planted close together
in the court. The verdict's condition is therefore met, and the choice — keep the south face, turn the logger to the
opening, or take another tree — needs the light as a number.

MODEL.
  THE YARD — three walls, each at its own perpendicular distance from the tree: the back wall on a bearing of 35°
    from the tree, the side walls 90° either side of it; the opening's two edges are INPUTS read off the image, and
    with the three distances they put the wings' ends where the plan block prints them. Distances are pixels scaled
    by the founder's «7 m» taken as the mean of the three (no scale bar was read); the trunk is taken under the
    crown's centre. Along a bearing that meets a wall at an angle δ from the wall's normal the wall is d / cos δ
    away, and its roof EDGE stands at an elevation atan((H − z) / (d / cos δ)) above a point at height z (a roof
    steeper than that line shows its ridge instead — not modelled).
  THE FACE — vertical, outward normal at 180° (the ratified south face) or at the opening's centre; the logger at the
    sheet's 1.3 m. Its light, hour by hour, in W/m²:
      beam    — DNI times the hour-mean, over `79`'s sun samples, of the cosine of incidence where the sun is in front
                of the face AND visible: above whatever stands on its bearing (a roof edge, or the opening's horizon);
      sky     — the diffuse flux times the face's view factor of the sky above that line (isotropic sky; 0.5 for an
                open face);
      ground  — half of `79`'s albedo end times the light on the yard's ground at the tree's foot (one point for the
                whole yard): the beam where the sun is visible from there, plus the diffuse flux times the ground's
                own sky-view factor.
    ⚠️ NOT A BOUND IN EITHER DIRECTION. Light reflected by the walls is not added (it adds; the walls' view factor from
    the face is printed as the room that term has), and the base case leaves the opening's horizon EMPTY — the kind
    assumption: the winter sun is low, and trees stand there.
  WHAT STANDS IN THE OPENING — three axes, none of them the trees themselves (a stand is neither level nor opaque):
      a level opaque horizon inside the whole opening, 0 … 60° — an axis, not this yard: by the founder's word the
        opening is near its empty end at the sun's height;
      the same horizon WITHOUT the building — so the building's share is printed GIVEN what stands in the opening
        (building + horizon over horizon alone), which is what a reader would divide a measured R by;
      a screen in one half of the opening only — where the sign of «turn the logger» is decided.
  A NEIGHBOUR'S STEM — with three pines planted close, a stem standing between the face and the opening is an opaque
    strip of the sky from the ground up: run as a strip 10° wide (a stem 0.35 m thick 2 m away) centred on four
    bearings — a scale, not the yard: where the three stand against each other is not in the tree.
  A SECOND READING OF THE PLAN — another model's reading of the same image against a 10 m scale bar (passed on by the
    founder, 2026-11-14): the court's axis 4° further west, the trunk nearer the back wall and much nearer the
    WESTERN wing, the wings ending nearer the tree. Two readings of one image by eye, neither a measurement — the same
    text put a wall of conifers beyond the opening, which the founder does not find — so both plans are run and
    printed side by side, and the readings on the spot decide.
  THE OPEN FACE it is set against — the same face with no building: DNI · cos γ + ½ diffuse + ½ albedo · (beam on the
    level + diffuse); for the south face under ERA5 that is `110`'s «open_face_180» (control 1).
  TWO SKIES — ERA5's, and the CERES SYN1deg product's (`124`'s loader and clock): the two split the same global flux
    differently into beam and diffuse, and a courtyard treats the two differently.
  THE BRACKET on «by eye» — (i) the roof edge at 6 · 7 · 8 m, every distance times 0.85 · 1 · 1.15, each edge of the
    opening 6° either way, every combination; (ii) the eastern edge alone, 150° … 190°; (iii) the TRUNK moved up to
    2 m either way along and across the court with the building fixed — a coherent re-plan (all three distances and
    both edges move together), which (i) does not cover: an image off nadir displaces a 25 m crown by metres against
    the roof edges.

WHAT IT CANNOT SEE. What actually stands beyond the opening (only level screens are run; the founder's word stands in
for it); the pine's own crown; where the two neighbouring pines stand and what their stems and crowns take; the plan
beyond what an image read by eye gives (two readings of it differ by metres); a roof's
ridge above its edge; windows, wall colour and the light the walls return; an anisotropic sky (the circumsolar part
of the diffuse light is blocked together with the beam, so for a face that loses beam the isotropic sky is the kind
form); snow on the yard's ground other than `79`'s two albedo ends on ERA5-Land's cell; the logger's height other
than 1.3 m; whether the compass heading was true or magnetic (the image, north up, is the plan's own bearing
reference).

CONTROLS (each says what it CAN and CANNOT catch).
  (1) With no walls the south face's light is `110`'s open_face_180 hour by hour under ERA5, at both albedo ends —
      rebuilt beside `yard()`, not through it; CAN catch a wrong sample, face bearing, clip or albedo call, CANNOT an
      error `110` shares or anything inside `yard()`.
  (2) The sky-view integral returns ½ for an open face, the closed form for a level roof line all round AND for a
      roof line on one side of a face turned to 210° only, and face + wall view factors sum to ½; the ground's sky
      view returns 1 open and 1 − sin²h under a level roof line; CAN catch a wrong kernel, a wrong bearing weight or
      sign, CANNOT a wrong roof line.
  (3) The roof line equals atan((H − z) · cos 30° / d) at 30° off a lone wall's normal (through `math`); the plan
      the inputs make is asserted to be a court: both wings end in FRONT of the tree and each back corner lies
      between its two walls' normals; CAN catch a wrong distance law and an input that turns the court inside out
      (a wrong sign of the back wall's bearing), CANNOT a plan that is a court but not this one.
  (4) `yard()` with no walls returns a beam share of exactly 1 and the rest 1 to the quadrature's accuracy; with the
      three walls drawn in to a centimetre and no opening it returns under a thousandth (beam, sky and ground); with no walls and
      a level horizon all round it returns the direct sum over the sun's samples above that horizon and the closed
      form of the sky view; and `yard(H, z)` returns the beam of `yard(H − z, 0)`. CAN catch a mask that ignores the
      building or the horizon, a ground lit as an open field, the ground's rise used for the face; CANNOT tell WHICH
      wall stands where.
  (5) The beam share of the base case is recomputed by a SECOND implementation — each sun sample's ray intersected
      with three finite wall segments laid out in plan coordinates from the inputs, not from `walls_of()` — and must
      agree; CAN catch mirrored or swapped walls, the farthest plane taken for the nearest, a wall off its distance
      law, an opening that disagrees with the wings; CANNOT an input error both layouts share.
  (6) The clock: the sun's bearing passes 180° at 11:30–12:10 local winter time on every printed date (solar noon
      at this longitude, with the equation of time), and at the minute printed for the eastern edge its bearing is within 0.3° of that edge; CAN catch
      a clock shifted by an hour or its sign, CANNOT a site or an ephemeris error `79` shares.
  The hours the sun is first seen are a PRINT for the founder, not a control: they are what he can check by eye.
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
from lib.constants import KINETICS_DIR
from lib.utils import banner

SI_DESCRIPTION = ("A light logger on a pine stem's face in a courtyard open to one side: the share of an open face's "
                  "winter beam, sky-diffuse and ground-reflected light that reaches the face past a two-storey building "
                  "on three sides, under two sky products; the building's share given a level horizon inside the "
                  "opening, a bracket on a plan read by eye that includes the trunk's position, and the hours the sun "
                  "is first seen from the trunk.")

HERE = Path(__file__).resolve().parent
OUT = KINETICS_DIR / "stem_face_courtyard.json"
MONTHS = (12, 1, 2)
SEASONS = (2002, 2020)                      # the seasons both skies hold (`124`)
LOGGER_HEIGHT_M = 1.3                       # the sheet's §1 («Висота»)
EYE_HEIGHT_M = 1.6                          # a person standing at the trunk — the hours printed for a check by eye
# the founder's yard, 2026-11-14 — the sheet's §1 ⊕: read by eye off his satellite image of the court (north up; pixels
# scaled by his «about 7 m» taken as the mean of the three wall distances), the roof edge by his word
BACK_WALL_BEARING_DEG = 35.0                # the back wall lies this way from the tree (it faces about 215°)
WALLS_M = {"back": 5.2, "east": 8.5, "west": 7.3}      # perpendicular distances from the tree
OPENING_DEG = (167.0, 256.0)                # the wings' ends seen from the tree (the words gave «about 150°–270°»)
ROOF_EDGE_M = 7.0
# a second reading of the same image, another model's, against a 10 m scale bar (mid-values of the ranges it gave)
SECOND_PLAN = {"back_wall_bearing_deg": 39.0, "walls_m": {"back": 4.5, "east": 9.25, "west": 5.25},
               "wing_ends_in_front_of_the_tree_m": {"east": 6.25, "west": 5.45}}
NEIGHBOUR_STRIP_DEG = 10.0                  # a stem 0.35 m thick 2 m away
NEIGHBOUR_BEARINGS_DEG = (170.0, 190.0, 210.0, 230.0)
# the bracket on «by eye»
ROOF_EDGES_M = (6.0, 7.0, 8.0)
SCALES = (0.85, 1.0, 1.15)                  # on every distance
EDGE_SHIFTS_DEG = (-6.0, 0.0, 6.0)
EASTERN_EDGES_DEG = (150.0, 155.0, 161.0, 167.0, 173.0, 180.0, 190.0)
TRUNK_SHIFTS_M = (-2.0, -1.0, 0.0, 1.0, 2.0)                  # toward the eastern wing · toward the back wall
OPENING_HORIZONS_DEG = (0.0, 5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 45.0, 60.0)
SCREENS = {"eastern_half_40": ("east", 40.0), "western_half_40": ("west", 40.0),
           "eastern_half_20": ("east", 20.0), "western_half_20": ("west", 20.0)}
FACES_DEG = {"south_180": 180.0, "opening_centre": None}     # None — the opening's own centre
AZ_STEP_DEG = 0.25                          # the view-factor quadrature
LOCAL_WINTER_UTC_OFFSET_H = 2               # EET, for the printed hours only
SIGHT_DATES = ("11-21", "12-21", "01-21", "02-11", "02-21")
SUN_HEIGHT_BEARINGS_DEG = (170.0, 190.0, 210.0, 230.0, 250.0)
OFF_NORMAL_DEG = 30.0                       # control (3)
FLUSH_M = 0.01                              # control (4): walls drawn in


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S124 = _load("s124_courtyard", "124_stem_face_second_sky.py")
S79, S110 = S124.S79, S124.S110


def walls_of(scale: float = 1.0, distances: dict | None = None) -> tuple:
    """((bearing from the tree, perpendicular distance), …) for the back, east and west walls."""
    d = distances or WALLS_M
    return ((BACK_WALL_BEARING_DEG % 360.0, d["back"] * scale),
            ((BACK_WALL_BEARING_DEG + 90.0) % 360.0, d["east"] * scale),
            ((BACK_WALL_BEARING_DEG - 90.0) % 360.0, d["west"] * scale))


def wing_ends_m(opening: tuple, distances: dict) -> tuple:
    """How far in front of the tree (along the court's axis, away from the back wall) each wing ends."""
    east_b, west_b = BACK_WALL_BEARING_DEG + 90.0, BACK_WALL_BEARING_DEG - 90.0 + 360.0
    return (distances["east"] * math.tan(math.radians(opening[0] - east_b)),
            distances["west"] * math.tan(math.radians(west_b - opening[1])))


def plan_with_trunk_moved(to_east_m: float, to_back_m: float) -> tuple:
    """(distances, opening) for the trunk moved in the fixed building: toward the eastern wing and toward the back
    wall — all three distances and both edges of the opening move together."""
    fwd_e, fwd_w = wing_ends_m(OPENING_DEG, WALLS_M)
    d = {"back": WALLS_M["back"] - to_back_m, "east": WALLS_M["east"] - to_east_m, "west": WALLS_M["west"] + to_east_m}
    east_b, west_b = BACK_WALL_BEARING_DEG + 90.0, BACK_WALL_BEARING_DEG - 90.0 + 360.0
    return d, (east_b + math.degrees(math.atan2(fwd_e + to_back_m, d["east"])),
               west_b - math.degrees(math.atan2(fwd_w + to_back_m, d["west"])))


def roof_line_deg(az_deg: np.ndarray, opening: tuple, walls: tuple, rise: float, opening_horizon: float = 0.0,
                  screens: tuple = ()) -> np.ndarray:
    """The elevation (degrees) of what blocks the view on each bearing: inside the opening the level horizon given
    (raised to a screen's height on the bearings (lo, hi, height) it covers), else the roof edge of the nearest wall
    plane the line of sight meets (`rise` — the roof edge's height above the observer). `walls=()` — no building:
    only what stands in the opening's sector is left."""
    az = np.asarray(az_deg, float) % 360.0
    inside = (az >= opening[0]) & (az <= opening[1])
    beyond = np.full(az.shape, float(opening_horizon))
    for lo, hi, height in screens:
        beyond = np.where((az >= lo) & (az < hi), np.maximum(beyond, height), beyond)
    if not walls:
        return np.where(inside, beyond, 0.0)
    r = np.full(az.shape, np.inf)
    for bearing, d in walls:
        c = np.cos(np.radians(az - bearing))
        r = np.where(c > 1e-9, np.minimum(r, d / np.where(c > 1e-9, c, 1.0)), r)
    h = np.degrees(np.arctan2(rise, r))
    return np.where(inside, beyond, np.where(np.isfinite(r), h, 0.0))


def visible_past_segments(az_deg: np.ndarray, el_deg: np.ndarray, rise: float) -> np.ndarray:
    """Control (5) — a second implementation of «the sun is seen past the building»: each ray from the tree is
    intersected with three finite wall segments laid out in plan coordinates (east, north) from the inputs."""
    def unit(bearing: float) -> np.ndarray:
        return np.array([math.sin(math.radians(bearing)), math.cos(math.radians(bearing))])

    back_b = BACK_WALL_BEARING_DEG
    east_b, west_b = back_b + 90.0, back_b - 90.0
    corner_e = WALLS_M["back"] * unit(back_b) + WALLS_M["east"] * unit(east_b)
    corner_w = WALLS_M["back"] * unit(back_b) + WALLS_M["west"] * unit(west_b)
    end_e = WALLS_M["east"] / math.cos(math.radians(OPENING_DEG[0] - east_b)) * unit(OPENING_DEG[0])
    end_w = WALLS_M["west"] / math.cos(math.radians(west_b - OPENING_DEG[1])) * unit(OPENING_DEG[1])
    dx, dy = np.sin(np.radians(az_deg)), np.cos(np.radians(az_deg))
    nearest = np.full(np.shape(az_deg), np.inf)
    for a, b in ((corner_w, corner_e), (corner_e, end_e), (corner_w, end_w)):
        ex, ey = b - a
        det = ex * dy - ey * dx
        safe = np.where(np.abs(det) > 1e-12, det, 1.0)
        r = (ex * a[1] - ey * a[0]) / safe
        t = (dx * a[1] - dy * a[0]) / safe
        hit = (np.abs(det) > 1e-12) & (r > 0.0) & (t >= 0.0) & (t < 1.0)
        nearest = np.where(hit, np.minimum(nearest, r), nearest)
    return (el_deg > 0.0) & (el_deg > np.where(np.isfinite(nearest), np.degrees(np.arctan2(rise, nearest)), 0.0))


def view_factors(face_deg: float, roof_deg: np.ndarray, az: np.ndarray) -> tuple:
    """(sky, wall) view factors of a vertical face of outward bearing `face_deg` under a roof line sampled on `az`
    (isotropic radiance): (1/π) ∫ cos(az − face)⁺ ∫ cos² el d el d az, above and below the roof line."""
    w = np.maximum(np.cos(np.radians(az - face_deg)), 0.0) * math.radians(AZ_STEP_DEG)
    h = np.radians(roof_deg)
    above = (math.pi / 2.0 - h) / 2.0 - np.sin(2.0 * h) / 4.0
    below = h / 2.0 + np.sin(2.0 * h) / 4.0
    return float((w * above).sum() / math.pi), float((w * below).sum() / math.pi)


def ground_sky_view(roof_deg: np.ndarray) -> float:
    """The sky-view factor of level ground under a roof line (isotropic sky): 1 − mean of sin² h over the bearings."""
    return float(1.0 - np.mean(np.sin(np.radians(roof_deg)) ** 2))


def control_kernels() -> dict:
    az = np.arange(0.0, 360.0, AZ_STEP_DEG) + AZ_STEP_DEG / 2.0
    flat = np.zeros_like(az)
    sky, wall = view_factors(180.0, flat, az)
    assert abs(sky - 0.5) < 1e-5 and abs(wall) < 1e-12, (sky, wall)
    h0 = math.radians(30.0)
    level = np.full_like(az, 30.0)
    sky30, wall30 = view_factors(180.0, level, az)
    want = (2.0 / math.pi) * ((math.pi / 2.0 - h0) / 2.0 - math.sin(2.0 * h0) / 4.0)
    assert abs(sky30 - want) < 1e-5 and abs(sky30 + wall30 - 0.5) < 1e-5, (sky30, want, wall30)
    assert abs(ground_sky_view(flat) - 1.0) < 1e-12 and abs(ground_sky_view(level) - (1.0 - math.sin(h0) ** 2)) < 1e-12
    # the bearing weight and its sign: a face turned to 210° with a level 30° roof line only on its left (120°–210°)
    one_side = np.where((az >= 120.0) & (az < 210.0), 30.0, 0.0)
    sky_one, wall_one = view_factors(210.0, one_side, az)
    want_one = 0.25 + (1.0 / math.pi) * ((math.pi / 2.0 - h0) / 2.0 - math.sin(2.0 * h0) / 4.0)
    assert abs(sky_one - want_one) < 1e-5 and abs(sky_one + wall_one - 0.5) < 1e-5, (sky_one, want_one)
    # the distance law, 30° off a lone wall's normal, through `math`
    rise = ROOF_EDGE_M - LOGGER_HEIGHT_M
    walls = walls_of()
    nowhere = (0.0, 0.0)
    (back_b, back_d), (east_b, east_d), (west_b, west_d) = walls
    off = roof_line_deg(np.array([back_b + OFF_NORMAL_DEG]), nowhere, ((back_b, back_d),), rise)[0]
    assert abs(off - math.degrees(math.atan(rise * math.cos(math.radians(OFF_NORMAL_DEG)) / back_d))) < 1e-9, off
    # the plan the inputs make is a court: the wings end in front of the tree, each back corner between its walls' normals
    fwd_e, fwd_w = wing_ends_m(OPENING_DEG, WALLS_M)
    assert fwd_e > 0.0 and fwd_w > 0.0, ("the wings must end in front of the tree", fwd_e, fwd_w)
    corner_e = back_b + math.degrees(math.atan2(east_d, back_d))
    corner_w = back_b - math.degrees(math.atan2(west_d, back_d))
    assert back_b < corner_e < BACK_WALL_BEARING_DEG + 90.0 < OPENING_DEG[0], ("the eastern corner", corner_e)
    assert OPENING_DEG[1] < BACK_WALL_BEARING_DEG + 270.0 < corner_w + 360.0 < back_b + 360.0, ("the western corner", corner_w)
    assert np.all(roof_line_deg(np.array([OPENING_DEG[0], 210.0, OPENING_DEG[1]]), OPENING_DEG, walls, rise) == 0.0)
    assert np.all(roof_line_deg(np.array([OPENING_DEG[0], 210.0]), OPENING_DEG, walls, rise, opening_horizon=12.0) == 12.0)
    screened = roof_line_deg(np.array([170.0, 230.0]), OPENING_DEG, walls, rise, 5.0, ((167.0, 211.5, 40.0),))
    assert tuple(screened) == (40.0, 5.0), screened
    assert np.all(roof_line_deg(np.array([100.0, 200.0]), OPENING_DEG, (), rise, opening_horizon=12.0) == (0.0, 12.0))

    def edge_deg(bearing: float, observer_m: float) -> float:
        return float(roof_line_deg(np.array([bearing]), nowhere, walls, ROOF_EDGE_M - observer_m)[0])

    return {"eastern_wing_ends_in_front_of_the_tree_m": fwd_e,
            "western_wing_ends_in_front_of_the_tree_m": fwd_w,
            # scale-free: the wing's end in front of the tree over the tree's distance from that wing
            "eastern_wing_end_over_its_distance_by_eastern_edge": {
                f"{edge:g}": math.tan(math.radians(edge - east_b)) for edge in EASTERN_EDGES_DEG if edge - east_b < 60.0},
            "wing_lengths_from_the_back_wall_m": {"east": back_d + fwd_e, "west": back_d + fwd_w},
            "court_width_m": east_d + west_d,
            "back_corner_bearings_deg": {"east": corner_e, "west": corner_w % 360.0},
            "roof_edge_from_the_logger_deg": {"back_wall_normal": edge_deg(back_b, LOGGER_HEIGHT_M),
                                              "eastern_wall_normal": edge_deg(east_b, LOGGER_HEIGHT_M),
                                              "western_wall_normal": edge_deg(west_b, LOGGER_HEIGHT_M),
                                              "opening_eastern_edge": edge_deg(OPENING_DEG[0] - 1e-6, LOGGER_HEIGHT_M)}}


def main() -> int:
    banner("HW.54 Р3(б)(4) — the stem-face logger in a courtyard open to one side")
    kernels = control_kernels()
    wx = S79.load_weather()
    times_h = np.asarray(wx["time"]).astype("datetime64[h]")
    st = S79.site()
    offset_h = round(st["utc_offset_h"])
    sun = S79.sun_enu(wx["time"], st)
    e, n, u = sun
    sun_az = np.degrees(np.arctan2(e, n)) % 360.0
    sun_el = np.degrees(np.arcsin(np.clip(u, -1.0, 1.0)))
    gc, _ = S79.face_factors(sun)
    fields110, ghi_e = S110.irradiance(wx, sun, gc)
    snow = S79.load_snow(wx["time"])
    ends = [end[0] for end in S79.REFLECT_ENDS]

    # the second sky, on the model's clock (`124`'s loader, lag and coverage)
    cp = S124.on_model_clock(S124.load_power(S124.DATA_FILE, S124.COLUMNS, {"dwn": 4, "dni": 5, "dif": 6}),
                             times_h, offset_h, S124.PRODUCT_STAMP_LAG_H)
    have = np.isfinite(cp["dwn"])
    skies = {"era5": {"dni": wx["dni"], "dif": wx["dif"]},
             "ceres": {"dni": np.where(have, cp["dni"], 0.0), "dif": np.where(have, cp["dif"], 0.0)}}

    month_h = times_h.astype("datetime64[M]").astype(int) % 12 + 1
    year_h = times_h.astype("datetime64[Y]").astype(int) + 1970
    season_h = np.where(month_h == 12, year_h + 1, year_h)
    win = np.isin(month_h, MONTHS) & (season_h >= SEASONS[0]) & (season_h <= SEASONS[1]) & have
    az_grid = np.arange(0.0, 360.0, AZ_STEP_DEG) + AZ_STEP_DEG / 2.0
    k_up = np.where(u > 0.0, u, 0.0).mean(axis=1)
    winters = SEASONS[1] - SEASONS[0] + 1
    keys = [f"{sky}:{end}" for sky in skies for end in ends]

    def cos_inc(face_deg: float) -> np.ndarray:
        return e * math.sin(math.radians(face_deg)) + n * math.cos(math.radians(face_deg))

    def yard(opening: tuple, walls: tuple, roof: float, face_deg: float, opening_horizon: float = 0.0,
             screens: tuple = (), z: float = LOGGER_HEIGHT_M) -> dict:
        """The face's light in the yard and the same face's open light, per sky and albedo end, summed over the winters."""
        rise_face, rise_ground = roof - z, roof
        seen_face = (sun_el > roof_line_deg(sun_az, opening, walls, rise_face, opening_horizon, screens)) & (u > 0.0)
        seen_ground = (sun_el > roof_line_deg(sun_az, opening, walls, rise_ground, opening_horizon, screens)) & (u > 0.0)
        c = cos_inc(face_deg)
        front = (u > 0.0) & (c > 0.0)
        k_beam = np.where(seen_face & (c > 0.0), c, 0.0).mean(axis=1)
        k_open = np.where(front, c, 0.0).mean(axis=1)
        k_east = np.where(front & (sun_az < opening[0]), c, 0.0).mean(axis=1)
        k_ground = np.where(seen_ground, u, 0.0).mean(axis=1)
        f_sky, f_wall = view_factors(face_deg, roof_line_deg(az_grid, opening, walls, rise_face, opening_horizon, screens), az_grid)
        f_ground = ground_sky_view(roof_line_deg(az_grid, opening, walls, rise_ground, opening_horizon, screens))
        out = {"view_factors": {"sky": f_sky, "walls": f_wall, "ground_sky_view": f_ground}, "by_sky": {}}
        for name, sky in skies.items():
            beam, open_beam = sky["dni"] * k_beam, sky["dni"] * k_open
            diffuse, open_diffuse = f_sky * sky["dif"], 0.5 * sky["dif"]
            # the open ground's light is built the same way (beam on the level + diffuse) — for ERA5 that IS its GHI; the
            # product's own global column does not close on its components exactly (`124`, control 2)
            refl = S79.reflected_rows(snow, sky["dni"] * k_ground + f_ground * sky["dif"])
            open_refl = S79.reflected_rows(snow, sky["dni"] * k_up + sky["dif"])
            cell = {"beam_kept": float(beam[win].sum() / open_beam[win].sum()),
                    "sky_diffuse_kept": float(diffuse[win].sum() / open_diffuse[win].sum()),
                    "share_of_the_open_beam_from_east_of_the_opening_by_month": {
                        str(mo): float((sky["dni"] * k_east)[win & (month_h == mo)].sum() / open_beam[win & (month_h == mo)].sum())
                        for mo in MONTHS}}
            for k, end in enumerate(ends, start=1):
                total = beam + diffuse + 0.5 * refl[k]
                open_total = open_beam + open_diffuse + 0.5 * open_refl[k]
                cell[end] = {"total_kept": float(total[win].sum() / open_total[win].sum()),
                             "ground_light_kept": float(refl[k][win].sum() / open_refl[k][win].sum()),
                             "yard_light_kwh_m2_per_winter": float(total[win].sum() / 1000.0 / winters),
                             "open_light_kwh_m2_per_winter": float(open_total[win].sum() / 1000.0 / winters),
                             "beam_share_of_the_yard_light": float(beam[win].sum() / total[win].sum()),
                             "by_month": {str(mo): float(total[win & (month_h == mo)].sum() / open_total[win & (month_h == mo)].sum())
                                          for mo in MONTHS}}
            out["by_sky"][name] = cell
        return out

    def light(cell: dict) -> dict:
        return {k: cell["by_sky"][k.split(":")[0]][k.split(":")[1]]["yard_light_kwh_m2_per_winter"] for k in keys}

    def kept(cell: dict) -> list:
        return [cell["by_sky"][k.split(":")[0]][k.split(":")[1]]["total_kept"] for k in keys]

    def over(a: dict, b: dict) -> list:
        return [light(a)[k] / light(b)[k] for k in keys]

    # control (1): with no walls the south face's light under ERA5 is `110`'s open_face_180, hour by hour
    c180 = cos_inc(180.0)
    k_open180 = np.where((u > 0.0) & (c180 > 0.0), c180, 0.0).mean(axis=1)
    refl_open = S79.reflected_rows(snow, ghi_e)
    control1 = 0
    for k, end in enumerate(ends, start=1):
        mine = wx["dni"] * k_open180 + 0.5 * wx["dif"] + 0.5 * refl_open[k]
        assert np.allclose(mine, fields110[f"open_face_180.{end}"], rtol=0, atol=1e-9), ("control 1", end)
        control1 += 1
    assert np.allclose(wx["dni"] * k_up + wx["dif"], ghi_e, rtol=0, atol=1e-9), "the level beam + diffuse is ERA5's GHI"

    centre = 0.5 * (OPENING_DEG[0] + OPENING_DEG[1])
    faces = {name: (centre if bearing is None else bearing) for name, bearing in FACES_DEG.items()}
    walls0 = walls_of()
    # control (4), through yard(): no walls → the open face
    for bearing in faces.values():
        bare = yard(OPENING_DEG, (), ROOF_EDGE_M, bearing)
        for sky in skies:
            b = bare["by_sky"][sky]
            got = [b["sky_diffuse_kept"], *[b[end]["total_kept"] for end in ends]]
            assert b["beam_kept"] == 1.0 and np.allclose(got, 1.0, rtol=0, atol=1e-5), ("control 4, bare", bearing, sky, got)
    # … the walls drawn in and no opening → nothing
    shut = yard((0.0, 0.0), walls_of(FLUSH_M / max(WALLS_M.values())), ROOF_EDGE_M, 180.0)
    for sky in skies:
        b = shut["by_sky"][sky]
        got = [b["beam_kept"], b["sky_diffuse_kept"], *[b[end]["total_kept"] for end in ends]]
        assert max(got) < 1e-3, ("control 4, shut", sky, got)      # not exactly 0: the two side planes are parallel
    # … no walls and a level horizon all round → the direct sum over the samples above it, the closed form of the sky view
    ring_h = 20.0
    ring = yard((0.0, 360.0), (), ROOF_EDGE_M, 180.0, opening_horizon=ring_h)
    k_ring = np.where((sun_el > ring_h) & (u > 0.0) & (c180 > 0.0), c180, 0.0).mean(axis=1)
    want_sky = (2.0 / math.pi) * ((math.pi / 2.0 - math.radians(ring_h)) / 2.0 - math.sin(2.0 * math.radians(ring_h)) / 4.0)
    for name, sky in skies.items():
        want_beam = float((sky["dni"] * k_ring)[win].sum() / (sky["dni"] * k_open180)[win].sum())
        assert abs(ring["by_sky"][name]["beam_kept"] - want_beam) < 1e-12, ("control 4, ring beam", name)
        assert 0.0 < want_beam < 1.0, want_beam
    assert abs(ring["view_factors"]["sky"] - want_sky) < 1e-5, ("control 4, ring sky", ring["view_factors"]["sky"], want_sky)
    base = {name: yard(OPENING_DEG, walls0, ROOF_EDGE_M, bearing) for name, bearing in faces.items()}
    # … yard(H, z) has the beam of yard(H − z, 0), and not of yard(H, 0)
    lowered = yard(OPENING_DEG, walls0, ROOF_EDGE_M - LOGGER_HEIGHT_M, 180.0, z=0.0)
    on_ground = yard(OPENING_DEG, walls0, ROOF_EDGE_M, 180.0, z=0.0)
    for sky in skies:
        assert base["south_180"]["by_sky"][sky]["beam_kept"] == lowered["by_sky"][sky]["beam_kept"], ("control 4, height", sky)
        assert base["south_180"]["by_sky"][sky]["beam_kept"] > on_ground["by_sky"][sky]["beam_kept"], ("control 4, height sees", sky)
    # control (5): the base beam share by ray–segment intersection
    seen2 = visible_past_segments(sun_az, sun_el, ROOF_EDGE_M - LOGGER_HEIGHT_M)
    k_beam2 = np.where(seen2 & (c180 > 0.0), c180, 0.0).mean(axis=1)
    by_segments = {name: float((sky["dni"] * k_beam2)[win].sum() / (sky["dni"] * k_open180)[win].sum()) for name, sky in skies.items()}
    for sky in skies:
        assert abs(by_segments[sky] - base["south_180"]["by_sky"][sky]["beam_kept"]) < 1e-6, ("control 5", sky, by_segments[sky])

    def turned_over_south(cells: dict) -> dict:
        return dict(zip(keys, over(cells["opening_centre"], cells["south_180"]), strict=True))

    base_ratio = turned_over_south(base)
    turn_gain = {sky: {end: base_ratio[f"{sky}:{end}"] for end in ends} for sky in skies}

    # what stands beyond the opening: a level horizon inside it — with the building, and without it
    horizon = {}
    for hz in OPENING_HORIZONS_DEG:
        cells = {name: yard(OPENING_DEG, walls0, ROOF_EDGE_M, bearing, opening_horizon=hz) for name, bearing in faces.items()}
        alone = yard(OPENING_DEG, (), ROOF_EDGE_M, 180.0, opening_horizon=hz)
        tot, share, ratio = kept(cells["south_180"]), over(cells["south_180"], alone), turned_over_south(cells)
        horizon[f"{hz:g}"] = {"south_face_total_kept_min": min(tot), "south_face_total_kept_max": max(tot),
                              "south_face_beam_kept_era5": cells["south_180"]["by_sky"]["era5"]["beam_kept"],
                              "building_share_given_the_horizon_min": min(share), "building_share_given_the_horizon_max": max(share),
                              "building_share_of_the_sky_diffuse": cells["south_180"]["view_factors"]["sky"] / alone["view_factors"]["sky"],
                              "turned_over_south_min": min(ratio.values()), "turned_over_south_max": max(ratio.values())}
    # a screen in one half of the opening only — where the sign of the turn is decided
    halves = {"east": (OPENING_DEG[0], centre), "west": (centre, OPENING_DEG[1] + 1e-9)}
    screen = {}
    for name, (half, height) in SCREENS.items():
        cells = {f: yard(OPENING_DEG, walls0, ROOF_EDGE_M, bearing, screens=((*halves[half], height),)) for f, bearing in faces.items()}
        ratio = turned_over_south(cells)
        screen[name] = {"turned_over_south_min": min(ratio.values()), "turned_over_south_max": max(ratio.values()),
                        "south_face_total_kept_min": min(kept(cells["south_180"])),
                        "south_face_total_kept_max": max(kept(cells["south_180"]))}
    # the eastern edge alone
    east_edge = {}
    for edge in EASTERN_EDGES_DEG:
        cell = yard((edge, OPENING_DEG[1]), walls0, ROOF_EDGE_M, 180.0)
        east_edge[f"{edge:g}"] = {"beam_kept_era5": cell["by_sky"]["era5"]["beam_kept"],
                                  "total_kept_min": min(kept(cell)), "total_kept_max": max(kept(cell))}
    # the trunk moved in the fixed building
    trunk = {}
    for to_east, to_back in itertools.product(TRUNK_SHIFTS_M, TRUNK_SHIFTS_M):
        d, opening = plan_with_trunk_moved(to_east, to_back)
        cell = yard(opening, walls_of(distances=d), ROOF_EDGE_M, 180.0)
        trunk[f"{to_east:g}:{to_back:g}"] = {"to_the_eastern_wing_m": to_east, "to_the_back_wall_m": to_back,
                                              "opening_deg": list(opening), "walls_m": d,
                                              "total_kept_min": min(kept(cell)), "total_kept_max": max(kept(cell))}
    trunk_lo = min(trunk.values(), key=lambda r: r["total_kept_min"])
    trunk_hi = max(trunk.values(), key=lambda r: r["total_kept_max"])
    one_metre = [r for r in trunk.values() if max(abs(r["to_the_eastern_wing_m"]), abs(r["to_the_back_wall_m"])) <= 1.0]
    trunk_bracket = {"positions": len(trunk),
                     "total_kept_min": trunk_lo["total_kept_min"], "total_kept_max": trunk_hi["total_kept_max"],
                     "at_min": {k: trunk_lo[k] for k in ("to_the_eastern_wing_m", "to_the_back_wall_m", "opening_deg")},
                     "at_max": {k: trunk_hi[k] for k in ("to_the_eastern_wing_m", "to_the_back_wall_m", "opening_deg")},
                     "within_one_metre_min": min(r["total_kept_min"] for r in one_metre),
                     "within_one_metre_max": max(r["total_kept_max"] for r in one_metre)}
    # a neighbour's stem between the face and the opening: an opaque strip from the ground up
    neighbour = {}
    for bearing in NEIGHBOUR_BEARINGS_DEG:
        strip = ((bearing - NEIGHBOUR_STRIP_DEG / 2.0, bearing + NEIGHBOUR_STRIP_DEG / 2.0, 90.0),)
        cell = yard(OPENING_DEG, walls0, ROOF_EDGE_M, 180.0, screens=strip)
        neighbour[f"{bearing:g}"] = {"total_kept_min": min(kept(cell)), "total_kept_max": max(kept(cell)),
                                     "over_no_strip_min": min(over(cell, base["south_180"])),
                                     "over_no_strip_max": max(over(cell, base["south_180"]))}
    # the second reading of the plan
    b2 = SECOND_PLAN["back_wall_bearing_deg"]
    d2, fwd2 = SECOND_PLAN["walls_m"], SECOND_PLAN["wing_ends_in_front_of_the_tree_m"]
    walls2 = ((b2, d2["back"]), (b2 + 90.0, d2["east"]), (b2 + 270.0, d2["west"]))
    opening2 = (b2 + 90.0 + math.degrees(math.atan2(fwd2["east"], d2["east"])),
                b2 + 270.0 - math.degrees(math.atan2(fwd2["west"], d2["west"])))
    cells2 = {"south_180": yard(opening2, walls2, ROOF_EDGE_M, 180.0),
              "opening_centre": yard(opening2, walls2, ROOF_EDGE_M, 0.5 * (opening2[0] + opening2[1]))}
    rise2 = ROOF_EDGE_M - LOGGER_HEIGHT_M
    second = {"opening_deg": list(opening2), "walls_m": d2, "back_wall_bearing_deg": b2,
              "roof_edge_from_the_logger_deg": {k: math.degrees(math.atan(rise2 / d2[w]))
                                                for k, w in (("back_wall_normal", "back"), ("eastern_wall_normal", "east"),
                                                             ("western_wall_normal", "west"))},
              "eastern_wing_end_over_its_distance": fwd2["east"] / d2["east"],
              "south_face_total_kept_min": min(kept(cells2["south_180"])), "south_face_total_kept_max": max(kept(cells2["south_180"])),
              "south_face_beam_kept_era5": cells2["south_180"]["by_sky"]["era5"]["beam_kept"],
              "south_face_sky_diffuse_kept": cells2["south_180"]["by_sky"]["era5"]["sky_diffuse_kept"],
              "turned_over_south_min": min(over(cells2["opening_centre"], cells2["south_180"])),
              "turned_over_south_max": max(over(cells2["opening_centre"], cells2["south_180"]))}
    lit = win[:, None] & (u > 0.0)
    west_most_winter_sun = float(sun_az[lit].max())
    highest_winter_sun = float(sun_el[lit].max())

    # the bracket on «by eye»: both faces in every combination, so their ratio in the same yard is there too
    rows = {name: [] for name in faces}
    ratios = []
    for roof, scale, lo, hi in itertools.product(ROOF_EDGES_M, SCALES, EDGE_SHIFTS_DEG, EDGE_SHIFTS_DEG):
        opening = (OPENING_DEG[0] + lo, OPENING_DEG[1] + hi)
        walls = walls_of(scale)
        cells = {name: yard(opening, walls, roof, (0.5 * (opening[0] + opening[1])) if FACES_DEG[name] is None else bearing)
                 for name, bearing in faces.items()}
        where = {"roof_edge_m": roof, "scale": scale, "opening_deg": list(opening)}
        ratios.append({**where, **turned_over_south(cells)})
        for name, cell in cells.items():
            rows[name].append({**where, **dict(zip(keys, kept(cell), strict=True)),
                               **{f"{sky}:beam": cell["by_sky"][sky]["beam_kept"] for sky in skies},
                               "sky_view": cell["view_factors"]["sky"]})
    bracket = {}
    for name in faces:
        lo_row = min(rows[name], key=lambda r: min(r[k] for k in keys))
        hi_row = max(rows[name], key=lambda r: max(r[k] for k in keys))
        bracket[name] = {"combinations": len(rows[name]),
                         "total_kept_min": min(min(r[k] for k in keys) for r in rows[name]),
                         "total_kept_max": max(max(r[k] for k in keys) for r in rows[name]),
                         "beam_kept_min": min(min(r[f"{sky}:beam"] for sky in skies) for r in rows[name]),
                         "beam_kept_max": max(max(r[f"{sky}:beam"] for sky in skies) for r in rows[name]),
                         "at_min": {k: lo_row[k] for k in ("roof_edge_m", "scale", "opening_deg")},
                         "at_max": {k: hi_row[k] for k in ("roof_edge_m", "scale", "opening_deg")},
                         "rows": rows[name]}

    def one_axis(pick) -> dict:
        sub = [r for r in rows["south_180"] if pick(r)]
        return {"total_kept_min": min(min(r[k] for k in keys) for r in sub), "total_kept_max": max(max(r[k] for k in keys) for r in sub)}

    mid_edges = list(OPENING_DEG)
    by_axis = {"roof_edge_alone": one_axis(lambda r: r["scale"] == 1.0 and r["opening_deg"] == mid_edges),
               "scale_alone": one_axis(lambda r: r["roof_edge_m"] == ROOF_EDGE_M and r["opening_deg"] == mid_edges),
               "roof_edge_and_scale": one_axis(lambda r: r["opening_deg"] == mid_edges),
               "eastern_edge_alone": one_axis(lambda r: r["roof_edge_m"] == ROOF_EDGE_M and r["scale"] == 1.0
                                              and r["opening_deg"][1] == OPENING_DEG[1]),
               "western_edge_alone": one_axis(lambda r: r["roof_edge_m"] == ROOF_EDGE_M and r["scale"] == 1.0
                                              and r["opening_deg"][0] == OPENING_DEG[0])}
    turn_bracket = {"min": min(min(r[k] for k in keys) for r in ratios), "max": max(max(r[k] for k in keys) for r in ratios),
                    "rows": ratios}

    # the hours the sun is first seen from the trunk, in local winter time (a print for a check by eye), and control (6)
    sight = {}
    for date in SIGHT_DATES:
        year = 2019 if date[:2] in ("11", "12") else 2020
        stamps = np.array([f"{year}-{date}T{h:02d}:00" for h in range(1, 24)])
        s = S79.sun_enu(stamps, st, n=60)
        az = (np.degrees(np.arctan2(s[0], s[1])) % 360.0).reshape(-1)
        up = s[2].reshape(-1) > 0.0
        el = np.degrees(np.arcsin(np.clip(s[2].reshape(-1), -1.0, 1.0)))

        def local(minute: int) -> str:                 # minutes after 00:00 on the file's clock → local winter time
            m = minute - 60 * (offset_h - LOCAL_WINTER_UTC_OFFSET_H)
            return f"{m // 60:02d}:{m % 60:02d}"

        at_edge = int(np.argmax(up & (az >= OPENING_DEG[0])))
        assert abs(az[at_edge] - OPENING_DEG[0]) < 0.3, ("control 6, the edge", date, az[at_edge])
        noon = local(int(np.argmax(up & (az >= 180.0))))
        assert "11:30" <= noon <= "12:10", ("control 6, the clock", date, noon)
        seen = up & (el > roof_line_deg(az, OPENING_DEG, walls0, ROOF_EDGE_M - EYE_HEIGHT_M))
        first = int(np.argmax(seen))
        heights = {}
        for bearing in SUN_HEIGHT_BEARINGS_DEG:
            past = up & (az >= bearing)
            heights[f"{bearing:g}"] = float(el[int(np.argmax(past))]) if past.any() else None
        sight[date] = {"bearing_passes_the_eastern_edge_local": local(at_edge),
                       "sun_elevation_then_deg": float(el[at_edge]),
                       "first_seen_from_eye_height_local": local(first),
                       "first_seen_at_bearing_deg": float(az[first]),
                       "first_seen_over_the_roof": bool(at_edge - first >= 2),
                       "bearing_rate_deg_per_h": float(az[at_edge + 30] - az[at_edge - 30]),
                       "solar_noon_local": noon,
                       "noon_elevation_deg": float(el[up].max()),
                       "sun_elevation_by_bearing_deg": heights}

    roof = kernels["roof_edge_from_the_logger_deg"]
    print(f"  the plan the inputs make: the eastern wing ends {kernels['eastern_wing_ends_in_front_of_the_tree_m']:.1f} m in front of the "
          f"tree, the western {kernels['western_wing_ends_in_front_of_the_tree_m']:.1f} m; wings "
          f"{kernels['wing_lengths_from_the_back_wall_m']['east']:.1f} and {kernels['wing_lengths_from_the_back_wall_m']['west']:.1f} m long")
    print(f"  the roof edge seen from {LOGGER_HEIGHT_M} m: back {roof['back_wall_normal']:.1f}°, east {roof['eastern_wall_normal']:.1f}°, "
          f"west {roof['western_wall_normal']:.1f}°, at the opening's eastern edge {roof['opening_eastern_edge']:.1f}°; the highest winter "
          f"sun {highest_winter_sun:.1f}°, its westernmost bearing {west_most_winter_sun:.1f}°")
    print(f"  the second reading of the plan: opening {opening2[0]:.1f}°–{opening2[1]:.1f}°, south face total kept "
          f"{second['south_face_total_kept_min']:.3f}–{second['south_face_total_kept_max']:.3f} (beam {second['south_face_beam_kept_era5']:.3f}), "
          f"turned over south {second['turned_over_south_min']:.3f}–{second['turned_over_south_max']:.3f}; roof edge "
          + ", ".join(f"{k} {v:.1f}°" for k, v in second["roof_edge_from_the_logger_deg"].items()))
    print("  a neighbour's stem, a 10° strip → south total kept · over no strip: "
          + "; ".join(f"{b}°: {v['total_kept_min']:.3f}–{v['total_kept_max']:.3f} · {v['over_no_strip_min']:.3f}–{v['over_no_strip_max']:.3f}"
                      for b, v in neighbour.items()))
    for name, cell in base.items():
        vf = cell["view_factors"]
        print(f"  face {name} ({faces[name]:.1f}°): sky view {vf['sky']:.3f} of 0.5, walls {vf['walls']:.3f}, ground's sky view "
              f"{vf['ground_sky_view']:.3f}")
        for sky in skies:
            b = cell["by_sky"][sky]
            print(f"    {sky:<5s} beam kept {b['beam_kept']:.3f} · sky-diffuse kept {b['sky_diffuse_kept']:.3f} · total kept "
                  + " / ".join(f"{b[end]['total_kept']:.3f}" for end in ends)
                  + f"  (beam share of the yard light {b[ends[0]]['beam_share_of_the_yard_light']:.2f})")
        br = bracket[name]
        print(f"    bracket over {br['combinations']} combinations: total kept {br['total_kept_min']:.3f}–{br['total_kept_max']:.3f}, "
              f"beam kept {br['beam_kept_min']:.3f}–{br['beam_kept_max']:.3f}")
    print("  the south face's bracket by axis: " + " · ".join(f"{k} {v['total_kept_min']:.3f}–{v['total_kept_max']:.3f}" for k, v in by_axis.items()))
    print(f"  the trunk moved up to 2 m: {trunk_bracket['total_kept_min']:.3f}–{trunk_bracket['total_kept_max']:.3f} "
          f"(up to 1 m: {trunk_bracket['within_one_metre_min']:.3f}–{trunk_bracket['within_one_metre_max']:.3f}); lowest at "
          f"{trunk_bracket['at_min']}, highest at {trunk_bracket['at_max']}")
    print("  the face turned to the opening over the south face, in the yard: "
          + ", ".join(f"{sky} {turn_gain[sky][ends[0]]:.3f} / {turn_gain[sky][ends[1]]:.3f}" for sky in skies)
          + f"; across the bracket {turn_bracket['min']:.3f}–{turn_bracket['max']:.3f}")
    for name, v in screen.items():
        print(f"    a screen, {name}: turned over south {v['turned_over_south_min']:.3f}–{v['turned_over_south_max']:.3f}; "
              f"south kept {v['south_face_total_kept_min']:.3f}–{v['south_face_total_kept_max']:.3f}")
    print("  the eastern edge alone → the south face's beam kept (ERA5) · total kept:")
    for edge, v in east_edge.items():
        print(f"    {edge:>4s}°: {v['beam_kept_era5']:.3f} · {v['total_kept_min']:.3f}–{v['total_kept_max']:.3f}")
    print("  a level horizon inside the opening → south total kept · the building's share given it (total · sky-diffuse) · turned over south:")
    for hz, v in horizon.items():
        print(f"    {hz:>4s}°: {v['south_face_total_kept_min']:.3f}–{v['south_face_total_kept_max']:.3f} · "
              f"{v['building_share_given_the_horizon_min']:.3f}–{v['building_share_given_the_horizon_max']:.3f} · "
              f"{v['building_share_of_the_sky_diffuse']:.3f} · {v['turned_over_south_min']:.3f}–{v['turned_over_south_max']:.3f}")
    for date, c in sight.items():
        print(f"  {date}: bearing passes the eastern edge {c['bearing_passes_the_eastern_edge_local']} ({c['sun_elevation_then_deg']:.1f}° up); "
              f"first seen from {EYE_HEIGHT_M} m {c['first_seen_from_eye_height_local']} at {c['first_seen_at_bearing_deg']:.1f}°"
              f"{' — over the roof' if c['first_seen_over_the_roof'] else ''}; noon {c['solar_noon_local']}, {c['noon_elevation_deg']:.1f}°; "
              "sun's height by bearing " + " ".join(f"{b}°:{'—' if h is None else format(h, '.0f')}" for b, h in c["sun_elevation_by_bearing_deg"].items()))

    OUT.write_text(json.dumps({
        "question": "00_07 HW.54 Р3(б)(4): the share of an open stem face's winter light that reaches the logger's face in "
                    "a courtyard open to one side — not a bound in either direction: wall-reflected light is not added, and the "
                    "base case leaves the opening's horizon empty (the horizon axis prices what stands there)",
        "inputs": {"opening_deg": list(OPENING_DEG), "walls_m": WALLS_M, "back_wall_bearing_deg": BACK_WALL_BEARING_DEG,
                   "roof_edge_m": ROOF_EDGE_M, "logger_height_m": LOGGER_HEIGHT_M, "eye_height_m": EYE_HEIGHT_M, "faces_deg": faces,
                   "beyond_the_opening": "by the founder's word (2026-11-14): low trimmed bushes and a parking area with a few "
                                         "deciduous trees — nothing at the winter sun's height; and the pine is one of three "
                                         "planted close together in the court",
                   "second_plan": SECOND_PLAN, "neighbour_strip_deg": NEIGHBOUR_STRIP_DEG,
                   "months": list(MONTHS), "seasons": list(SEASONS), "skies": list(skies), "ends": ends,
                   "bracket": {"roof_edges_m": list(ROOF_EDGES_M), "scales": list(SCALES), "edge_shifts_deg": list(EDGE_SHIFTS_DEG),
                               "trunk_shifts_m": list(TRUNK_SHIFTS_M)},
                   "opening_horizons_deg": list(OPENING_HORIZONS_DEG), "eastern_edges_deg": list(EASTERN_EDGES_DEG),
                   "source": "the founder's satellite image of the court, north up, read by eye in pixels and scaled by his "
                             "«about 7 m» taken as the mean of the three wall distances; the roof edge by his word; 2026-11-14"},
        "controls": {"110_open_face_fields_reproduced": control1, "kernels": kernels,
                     "beam_kept_by_ray_segment_intersection": by_segments,
                     "highest_winter_sun_deg": highest_winter_sun},
        "sun_first_seen_from_the_trunk": sight,
        "base": base,
        "face_turned_to_the_opening_over_south_face": turn_gain,
        "face_turned_to_the_opening_over_south_face_across_the_bracket": turn_bracket,
        "opening_horizon": horizon,
        "screen_in_one_half_of_the_opening": screen,
        "eastern_edge_alone": east_edge,
        "second_reading_of_the_plan": second,
        "neighbour_stem_strip": neighbour,
        "trunk_moved": {"bracket": trunk_bracket, "positions": trunk},
        "winter_sun_westernmost_bearing_deg": west_most_winter_sun,
        "bracket": bracket,
        "south_face_bracket_by_axis": by_axis,
    }, indent=2))
    print(f"[125] wrote {OUT.relative_to(HERE.parents[2])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
