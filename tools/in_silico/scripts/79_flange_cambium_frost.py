#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""
79 — The frost half of the path «flange → cambium» (00_07 HW.6; crown-pause exception ⚖️ founder 2026-10-03):
on winter days, does the titanium flange — with the capsule it carries — make the cambium under the ring Ø15–Ø29.8
colder than under bark without it, and how does the answer move with the sky and the sun?

WHY A MODEL, NOT A DIRECTION. `78` met the flange and shaded bark at night by construction: `71`'s capsule tracks
the air, because no sky is modelled. The flange's link to the air is strong (a fin several times the ring it sits
on, if the capsule is tied to it) and bark's is weak (a large flat surface, fed from below by the stem's stored
heat). Which way that pulls the ring depends on what the air and the sky are doing — so the sky and the sun are
AXES of this model, not settings.

BEAM — a vertical trunk face whose outward normal points at azimuth A (swept, AZIMUTHS_DEG) receives ERA5 direct-
normal irradiance times cos γ, γ the angle between the sun and that normal; behind the face (cos γ ≤ 0) the stem
shades it. The sun's position is NOAA GML's «General Solar Position Calculations» (Spencer's Fourier series for the
declination and the equation of time; read 2026-10-14), on the clock the data header declares, averaged over the
hour each radiation value averages — the hour BEFORE its label (Open-Meteo). Under the flange the silhouette is the
lump's: the crown disc face-on (cos γ) plus the capsule's and the band's sides edge-on (sin γ) — 71's
worst-orientation projection is its maximum over γ; the band alone is a short cylinder on the face normal. Mutual
shading of capsule and band is ignored. Two runtime gates: the clock against the data (`verify_sun_clock`: DNI
energy in hours the computed sun never clears the horizon is zero at the declared convention and not under a shift
of ½ or 1 h) and the geometry against the obliquity, the equation-of-time extremes and the June noon altitude
(`verify_sun_geometry`); the substep count is checked again where the beam drives hardest (`verify_timestep_beam`).
What it counts besides the frost shift: winter hours with the cambium above DEHARDEN_C, bark against the flange —
the exposure Sakai 1968 names as the CAUSE of winter dehardening (canon 01_04 §3.1), never a dose.

REFLECTED (2026-10-17, revised 2026-10-18 after an adversarial pass) — ground-reflected light on the same faces, rides with
the beam (open field, every face): ρ·GHI received through the ground's share of the view (1 − F), isotropic, with each
column's own α; GHI is the horizontal ERA5 DNI under the same sun plus ERA5 diffuse. ρ switches between snow and bare ground
by a reanalysis's hourly snow depth — ERA5 itself carries none on our channel, so CERRA and ERA5-Land, each held to the
nearest station with snow depth (GHCN-Daily Lubny, `snow_check`). The albedos come from one station's pyranometers over an
open plot (Baker et al. 1990 · Baker & Ruschy 1988): 0.80 is their mean the day after a snowfall, 0.50 the cutoff their
deep-snow sample is selected by (not a measured albedo), the bare-ground values their monthly medians. Two ends of the INPUT —
the least reflected light and the most (REFLECT_ENDS; which reanalysis each end takes is asserted from the data,
`check_reflect_ends`); neither is an extreme of the real world, and whether every reported quantity moves the same way
between them in every cell is recorded (`monotone_low_to_high_every_cell`). The beam records without it are kept as they
were, and the records with it sit beside them. A third beam window, around the largest high-end reflected hour, joins its
timestep gate, and the whole-series gate carries the beam with the high end in both cloud forms.
CANNOT (reflected): the ground in the long-wave view stays at air temperature under snow too, so a clear-night snow surface
below the air — an extra loss — is not carried, and the floor's gain is the reflected term alone, not the net effect of snow;
the open field is applied to every face, while at a stand edge facing the sun the north face looks into the stand and gets
less; the trunk's own shadow on the ground the face sees, and forward scattering off snow, are left out.

MODEL — the 1D column of `78` (dead bark → phloem → sapwood, properties from `58`, adiabatic at SAPWOOD_DEPTH_MM,
the canon dead-bark bracket at DBH 38), with an ENERGY BALANCE at its surface in place of an imposed temperature
(x inward from the surface):
    λ·∂T/∂x|₀ = (A_fin / A_contact) · [h_c·(T_s − T_air) + ε·σ·(T_s⁴ − T_env⁴) − α·F·DIF],
    T_env⁴ = F·T_sky⁴ + (1 − F)·T_air⁴
  • Bark without the flange: A_fin / A_contact = 1; h_c of the stem — the larger of natural convection off a vertical
    surface (Churchill–Chu, Incropera eq. 9.26, height TRUNK_L_M; laminar-to-transitional there, and a taller bole
    gives a slightly LOWER h) and forced cross-flow over the stem (`71`'s Churchill–Bernstein at D = DBH).
  • Under the flange, the two ends of ONE unmeasured axis — how the capsule is tied to the flange:
      decoupled — the radome carries nothing; the fin is the flange's own side band, all of its thickness counted;
      tied — the capsule is ONE isothermal body with the flange (`71`'s lump), so its whole exposed area joins the fin.
    Both take the flange isothermal with the top of the bark under it and zero contact resistance; h_c is `71`'s
    capsule coefficient, called with |ΔT| (`71` zeroes natural convection for a lump colder than the air — right for
    its hot bound, wrong for a cold one). The two ends bracket the MEDIAN shift (it moves monotonically along the
    axis); they do not bracket the tail — an intermediate coupling can sit below the decoupled end.
  • Sky — two ends: CLEAR every hour (Brutsaert 1975, Water Resour. Res. 11:742, ε_sky = 1.24·(e_a/T_a)^(1/7), e_a in
    hPa from the ERA5 dew point by Magnus over water, WMO-No. 8, T_a in K — the primary is closed; the coefficient
    and its use are read through Crawford & Duchon 1999, J. Appl. Meteor. 38:474, whose own calculated coefficients
    scatter around «the original B75 leading coefficient (1.24)»; with e in Pa the emissivity would exceed 1, which
    is the only reading `brutsaert_unit_check` excludes) and OVERCAST every hour (a sky radiating as a black body at
    air temperature — no long-wave deficit at all). Real cloud — ERA5 cover hour by hour — is a separate block
    that mixes these ends by two forms (CLOUD_REGIMES, 2026-10-12); the four ends above are unchanged by it.
  • Sun — two ends: none, and ERA5 DIFFUSE on both columns through the same sky view F (no beam: under a crown or on
    a north face). Absorptance: bark ALPHA_BARK (ours — no bark absorptance in the tree), the fin ALPHA_FIN = the
    radome's specified ceiling α ≤ 0.5 (02_01 §5.2), applied to the band as well. Beam on a sunlit trunk face is a
    separate block (2026-10-14, BEAM below): the canon sets no mounting azimuth, so the face's azimuth is SWEPT, and
    the beam rides only on the real-cloud sky forms (ERA5 DNI is real-sky); the four ends here carry none.
  • F = 0.5 and ε = 0.90 for bark and capsule alike (`71`'s, both ours).
Radiation is linearised around each column's previous surface temperature and h_c lagged one substep. Only the
surface's diagonal entry differs between columns and substeps, so one banded factor per bark side serves every
column through a Sherman–Morrison correction (`march`). Time stepping is fully IMPLICIT, not `78`'s Crank–Nicolson:
with a balance on the surface half-cell its Fourier number is ~10³ per substep, where Crank–Nicolson is not
L-stable and rings — measured 11.8 % off the closed form 6 h after a step. Three runtime gates: the step against
that closed form (`verify_robin`), a diurnal wave against a 120-substep Crank–Nicolson reference (`verify_diurnal`),
and the substep count against six times as many on the coldest real-weather window (`verify_timestep`); since 2026-10-17
a fourth judges the substep count over the WHOLE series for the most strongly sun-driven columns (`verify_timestep_series`),
because windows picked by an extreme held a step that failed between them.

DIRECTION OF EACH CHOICE, stated per quantity:
  • Clear sky and no sun give the COLDEST absolute temperatures for both columns — and the case MOST FAVOURABLE to
    the flange for the shift: a long-wave deficit depresses flat bark (low h_c) more than the capsule (high h_c),
    so the fin's sink sits nearer the air. Cloud removes that deficit; then the fin's large conductance to the air
    makes the ring follow the air's daily fall more closely than the damped bark surface — colder minima. Sun is
    banked by bark (low H) and shed by the fin (high H) — colder minima under the flange again.
  • 1D (no lateral heat from the bark around a 7.4 mm wide ring over 8–21 mm of bark) and zero contact resistance pull
    the ring fully onto the fin's balance: they inflate |shift| in BOTH signs. The tied end is the upper end of the
    coupling axis only.
  • The adiabatic end at SAPWOOD_DEPTH_MM holds about 1.2–1.35× the heat per unit surface of a DBH-38 stem (the store
    of a DBH ≈ 46 cm stem); a deeper store (sapwood to 190 mm) and a shorter trunk height both RAISE the tied tail —
    sensitivities in the cache, with a third that equalises the capsule's h_c to bark's (the mechanism, as a field).
  • Equal ε for bark and capsule is not neutral (a darker-in-IR bark lowers the tied tail a little) — ours, declared.

CAN show: the shift of the daily cambium minimum under the flange against bark without it on frost days (calendar-day
minima, the column has no day/night) over 30 winters — per sky end, sun end, coupling end, wind and bark side; its
sign; which mechanism carries it; hours below a few isotherms.
CANNOT show: injury — the regional threshold (canon 01_04 §3.1) is not a dose-response, so an isotherm count is
not a dose (the same ceiling as `58`'s gate), and neither is a count of hours above the ≈ 13 °C that dehardens;
beam under a crown, a neighbour trunk or the terrain (the beam block takes open-field DNI — the upper end of beam);
the reflected light at the site — snow from reanalyses near the cell, an albedo measured on another continent over an
open plot, nothing under a crown or on a forest floor (the two ends bracket it only as far as those inputs reach);
and the mounting azimuth itself (a decision, 00_07 HW.6 — the block sweeps it); which long-wave form of
cloud holds at the site (the real-cloud block weighs the ends by ERA5 cover through two forms that disagree under
full cover); the real radome↔flange coupling (bayonet rim, O-ring and cavity air — not measured); snow or rime; a forecast
of absolute minima — a run of weeks of sunless clear sky is the model's lower bound, below any ERA5 air hour; the
capsule temperature for the EDLC floor of 00_07 HW.37 (this lump is fed by the bark, `71`'s is not).

Run:  python tools/in_silico/scripts/79_flange_cambium_frost.py      # ≈ 6.4 h beside a DFT Hessian on the same CPU (2026-10-18, 16 substeps/h); alone not re-measured
"""
from __future__ import annotations

import csv
import gzip
import importlib.util
import io
import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy.linalg import solve_banded
from scipy.optimize import brentq
from scipy.special import erfc

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, DBH_MIN_CM, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = "Cambium temperature under the anchor's titanium flange on winter days, against bark without it, over thirty years of hourly weather, bracketed by sky, sun and coupling, with direct sun swept over the trunk face's azimuth (1D)."  # its row in the paper SI (72): English, no repo jargon

OUT_DIR = CACHE_DIR / "thermal"
OUT = OUT_DIR / "flange_cambium_frost.json"
FLANGE_CEM = REPO_ROOT / "tools/cad/cem/cathode_flange.json"
SLEEVE_CEM = REPO_ROOT / "tools/cad/cem/zone2_sleeve.json"
SCRIPTS = Path(__file__).resolve().parent

WIND_K = (0.0, 0.1)            # still air and 71's typical light breeze, u_trunk = k·u10
COUPLINGS = ("decoupled", "tied")
REGIMES = (("clear_no_sun", False, False), ("overcast_no_sun", True, False),     # (name, overcast sky, diffuse sun)
           ("clear_diffuse_sun", False, True), ("overcast_diffuse_sun", True, True))
BRUTSAERT_A = 1.24             # Brutsaert 1975, read via Crawford & Duchon 1999 (docstring)
BRUTSAERT_EXP = 1.0 / 7.0
ALPHA_BARK = 0.80              # ours — no bark absorptance in the tree
TRUNK_L_M = 1.0                # height for the vertical-surface correlation — laminar-to-transitional there
SUBSTEPS = 16                  # implicit substeps per hour — 4 held the sampled windows only: off them (2026-10-17, against
#                                6× as many) the shift error reached 0.081 K on the beam columns and 0.057 K on the diffuse-sun
#                                ones, past COLDER_BAND_K; 8 held every window found (0.043 K) and failed the whole series
#                                (0.059 · 0.047 K, the first full run of `verify_timestep_series`, which judges every frost
#                                day of the 30 years); implicit Euler is first order, so 16 is read at about half of that.
SPIN_UP_DAYS = 14              # the column forgets its start in about a day; two weeks are cut from every statistic
FROST_DAY_C = 0.0              # a day counts when bark without the flange takes its cambium minimum below this
ISOTHERMS_C = (-5.0, -10.0, -15.0, -20.0)
THETA = 1.0                    # fully implicit — see the docstring for why not Crank–Nicolson
SENSITIVITY = (("sapwood_190mm", {"sapwood_mm": 190.0}),          # thin bark, still air, clear sky, no sun
               ("trunk_height_0.3m", {"trunk_l_m": 0.3}),
               ("capsule_h_c_as_bark", {"cap_hc_as_bark": True}))
REFERENCE_HOUR = {"t_air_C": -10.0, "t_dew_C": -13.0}   # the mechanism's equilibria are read at one cold clear hour
# ── Real cloud (2026-10-12, the HW.6 leg's «weights between the ends»): ERA5 total cloud cover hour by hour, through two
# long-wave forms that bracket how cover turns into sky radiation — neither primary was reachable (AMS blocks the
# client), so each is named with how it was read:
#   «linear» — OUR construction: the script's two ends mixed by the cover, T_sky⁴ = c·T_air⁴ + (1 − c)·ε_clear·T_air⁴,
#     i.e. the covered fraction radiates as the overcast end (a black body at air temperature) and the rest as the
#     clear end; no primary — Herrero & Polo 2012 (Hydrol. Earth Syst. Sci. 16:3139, doi:10.5194/hess-16-3139-2012,
#     open) describe Crawford & Duchon 1999's cloudy extension as «a simple linear relation» with a cloud measure taken
#     from solar irradiance, but CD99's equation was not read here (AMS refused our client on 2026-10-12, though the
#     Brutsaert coefficient above was read through CD99's open text earlier), so the form is not attributed to it.
#   «B82» — Brutsaert 1982's factor (the primary is a book, not read) as printed in Herrero & Polo 2012, eq. 8:
#     ε = ε_clear·(1 + C·N²), «C, an empirical factor dependent on the cloud types, originally set to 0.22», N a cloud
#     index from 0 (clear) to 1 (overcast). With winter ε_clear (0.62–0.76) it stays short of 1 at full cover; in
#     warmer, moister hours it can exceed 1, so the sky is clipped at a black body at air temperature.
#   What the one measurement in hand says (H&P, one mountain station at 2500 m, DAYTIME data): under full cover the
#     measured emissivity «clearly meet[s] at 1» — CD99's solar-based cloud measure never got there, B82 did only with
#     C raised to 0.42, which H&P put down to mountains, where cloud's effect is «much more intense than in valley
#     areas». So it favours any form that reaches 1 under full cover, at a mountain site, by day; at a 111 m valley cell
#     at night neither form is favoured — they bracket.
# ERA5's total cover stands in for both cloud measures — a role substitution, declared (data README): it counts thin
# high cloud as cover, so the linear form treats more hours as a black-body sky than they are — a bias toward «colder».
COLDER_BAND_K = 0.05           # a day counts as colder/warmer only beyond the timestep gate's shift tolerance
SERIES_HOURS_TOL = (2, 0.02)   # the whole-series gate on hours above DEHARDEN_C: max(2 h, 2 %) — the beam windows' own tolerance
SERIES_FLOOR_TOL_K = 0.15      # the whole-series gate on a column's coldest hour — the windows' daily-minimum tolerance
COLD_DAY_C = -10.0             # «cold days»: bark without the flange below this — the tail an injury threshold sits in
B82_C = 0.22
CLOUD_REGIMES = (("cloud_linear_no_sun", "linear", False), ("cloud_linear_diffuse_sun", "linear", True),
                 ("cloud_b82_no_sun", "b82", False), ("cloud_b82_diffuse_sun", "b82", True))
SKY_CODE = {"clear": 0, "overcast": 1, "linear": 2, "b82": 3}
CLOUD_FILE = REPO_ROOT / "tools/in_silico/data/era5_cherkasy/hourly_cloud_1991_2020.csv.gz"
WINTER_MONTHS = (11, 12, 1, 2, 3)
# ── Beam sun by azimuth (2026-10-14, the HW.6 leg «пряме сонце за азимутом»): the method — docstring BEAM. Open-field
# DNI, no crown, neighbour trunk or horizon: the UPPER end of beam (a stand edge facing the sun); the diffuse-only
# real-cloud block above is its lower end (a closed stand). Ground-reflected light rides with it — REFLECT_ENDS below.
AZIMUTHS_DEG = (0, 45, 90, 135, 180, 225, 270, 315)   # the face's outward normal, clockwise from north
BEAM_FORMS = ("linear", "b82")                          # beam is real-sky: only the real-cloud forms carry it
SUN_SUBSAMPLES = 12                                     # points per averaged hour
CLOCK_SHIFTS_H = (-1.0, -0.5, 0.0, 0.5, 1.0)
# ── Ground-reflected light (2026-10-17, the HW.6 leg «відбите від землі»): open field like the beam it rides with, so it joins
# the beam block only — the diffuse-only weighing stays the closed-stand lower end, and the beam block without it stays as it
# was (its records are the control the new ones are read against). ERA5 carries no snow depth on our channel (Open-Meteo,
# models=era5 returns NaN every hour, 2026-10-17), so snow on the ground comes from two other reanalyses near the same cell,
# each judged against the nearest station that reports snow depth (data README, `snow_check`):
DATA_DIR = CLOUD_FILE.parent
SNOW_FILES = {"era5_land": DATA_DIR / "hourly_snow_era5_land_1991_2020.csv.gz", "cerra": DATA_DIR / "hourly_snow_cerra_1991_2020.csv.gz"}
STATION_SNOW_FILE = DATA_DIR / "ghcnd_UPM00033377_snwd_1991_2020.csv"   # GHCN-Daily, Lubny — rows as delivered
STATION_HOUR = "09"          # the reanalysis hour a station's daily depth is compared with — ours (a morning reading)
SNOW_CHECK_MIN_KAPPA = 0.4   # Cohen's κ of day-by-day snow/no-snow against the station, every reanalysis and depth — ours.
#   Not raw agreement: a series that never has snow agrees 0.77 at 11 cm here (the station's snow share is 0.23), so an
#   agreement gate could not fail on it; κ puts it at 0. Measured 2026-10-18 at 1 and 11 cm over 1991–2020: 0.65–0.73 (2026-10-17 at 1 and 10 cm: 0.65–0.74); over
#   1991–1993 alone 0.22–0.58 — a short window of thin winters, so the gate is meant for the full series only. It is run at
#   the depths the ends below use (SNOW_CHECK_DEPTHS_M).
# Albedo — Baker, Ruschy & Wall 1990 (J. Appl. Meteor. 29:179, doi:10.1175/1520-0450(1990)029<0179:TADOPS>2.0.CO;2; St. Paul,
# Minnesota, 1969–87: pyranometers 160 cm over an open agricultural plot, daily totals; read from the page images): «The mean
# albedo on the day following a snowfall greater than a trace averaged about 80%», and their decay sample keeps only days with
# depth ≥ 10.2 cm and albedo ≥ 50 %, because below that «the underlying surface was affecting the reflection» (their reading of
# Wall 1987). Snow-free — Baker & Ruschy 1988 (J. Appl. Meteor. 27:244, doi:10.1175/1520-0450(1988)027<0244:HAVASP>2.0.CO;2;
# the same station and instruments), Table 2 medians: April 18 % (bare, wet soil after the melt), October 24 %.
# Two ends of the INPUT — the least reflected light and the most (end, snow source, depth counted as snow in m, ρ snow,
# ρ ground). They are not the adverse corner of every reported quantity — the low end favours the hours, the high end the
# floor — and neither is an extreme of the real world (0.80 is a mean; a wet dark soil can sit below 0.18):
#   low  — the reanalysis with LESS winter snow at the depth where snow masks the ground (Baker's 10.2 cm, i.e. ≥ 11 cm on
#          the series' 1 cm grid), at the cutoff of Baker's deep-snow sample, over wet bare soil;
#   high — the reanalysis with MORE winter snow at any reported depth (≥ 1 cm), as fresh snow, over October's ground.
# Which reanalysis is which is asserted from the data (`check_reflect_ends`), not assumed: the first version took CERRA for
# the low end on its 1 cm agreement, and at 10 cm CERRA is the snowier one (adversarial review 2026-10-18).
REFLECT_ENDS = (("low", "era5_land", 0.11, 0.50, 0.18), ("high", "era5_land", 0.01, 0.80, 0.24))
SNOW_CHECK_DEPTHS_M = tuple(sorted({e[2] for e in REFLECT_ENDS}))
REFLECT_NAMES = ("none", *(e[0] for e in REFLECT_ENDS))
DEHARDEN_C = 13.0   # Sakai 1968 «higher than 13 °C or thereabouts», read in canon 01_04 §3.1 — a CAUSE, not a dose


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / file)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


S71 = _load("s71_capsule", "71_capsule_thermal_envelope.py")
S74 = _load("s74_rain_dew", "74_site_rain_dew.py")
S78 = _load("s78_flange_heat", "78_flange_cambium_heat.py")
S58 = S78.S58
SIGMA = S71.SIGMA
EPSILON, SKY_VIEW = S71.EPSILON, S71.SKY_VIEW
ALPHA_FIN = S71.ALPHA_EDGES[0]           # the radome's specified ceiling (02_01 §5.2); a lighter finish enlarges the shift
DX_MM = S78.DX_MM


def vapour_pressure_hpa(t_dew_c):
    """Saturation vapour pressure over water at the dew point (Magnus, WMO-No. 8 Annex 4.B) = the actual pressure."""
    return 6.112 * np.exp(17.62 * t_dew_c / (243.12 + t_dew_c))


def sky_emissivity(t_air_c, t_dew_c):
    """Clear-sky effective emissivity, Brutsaert 1975: e_a in hPa, T_a in K."""
    return BRUTSAERT_A * (vapour_pressure_hpa(t_dew_c) / (t_air_c + 273.15)) ** BRUTSAERT_EXP


def brutsaert_unit_check() -> dict:
    """The one reading physics excludes: with e in Pa the emissivity exceeds 1. The hPa reading gives a clear-sky
    value at 10 hPa / 283 K (the window here is a plausibility check, not a proof of units)."""
    hpa = BRUTSAERT_A * (10.0 / 283.0) ** BRUTSAERT_EXP
    pa = BRUTSAERT_A * (1000.0 / 283.0) ** BRUTSAERT_EXP
    if not (0.6 < hpa < 0.9 and pa > 1.0):
        raise SystemExit(f"Brutsaert units check failed: {hpa:.3f} (hPa) / {pa:.3f} (Pa)")
    return {"emissivity_at_10hPa_283K": round(hpa, 3), "same_with_e_in_Pa": round(pa, 3)}


def h_vertical(height_m, dt, t_film_c):
    """Churchill–Chu, vertical plate, whole range (Incropera eq. 9.26), with |ΔT| — a cold surface drives the same
    boundary layer downward."""
    p = S71.air_props(t_film_c)
    beta = 1.0 / (t_film_c + 273.15)
    ra = S71.G * beta * np.abs(dt) * height_m ** 3 / (p["nu"] * p["alpha"])
    nu = (0.825 + 0.387 * ra ** (1 / 6) / (1 + (0.492 / p["pr"]) ** (9 / 16)) ** (8 / 27)) ** 2
    return nu * p["k"] / height_m


def areas() -> dict:
    """The ring the flange sits on and the two fins, read from the CEMs and 71 — never typed."""
    fl = json.loads(FLANGE_CEM.read_text(encoding="utf-8"))
    sl = json.loads(SLEEVE_CEM.read_text(encoding="utf-8"))
    d_fl, t_fl = fl["flange_diameter_mm"], fl["flange_thickness_mm"]
    d_wound = sl["bore_diameter_mm"] + 2.0 * sl["wall_thickness_mm"]
    a_contact = math.pi / 4.0 * (d_fl ** 2 - d_wound ** 2)
    a_band = math.pi * d_fl * t_fl
    a_exp = S71.geometry()["a_exp_mm2"]
    return {"flange_diameter_mm": d_fl, "flange_thickness_mm": t_fl, "wound_diameter_mm": d_wound,
            "contact_ring_mm2": round(a_contact, 2), "flange_band_mm2": round(a_band, 2),
            "capsule_exposed_mm2": round(a_exp, 2),
            "fin_ratio": {"decoupled": round(a_band / a_contact, 4), "tied": round((a_band + a_exp) / a_contact, 4)}}


def base_system(stack: list, probe_mm: float, substeps: int, theta: float = THETA):
    """The column of `78` with node 0 as an unknown surface half-cell: (banded base matrix, explicit diagonal,
    left/right face conductances, B⁻¹·e0, probe index). `substeps` is explicit — a default bound at definition time
    would silently outlive a change of the module constant."""
    cap, g, ic = S78.column(stack, probe_mm)
    cap = cap.copy()
    cap[0] *= 0.5                                       # node 0 is a surface half-cell here, not a driven node
    n = len(cap)
    c = cap / (3600.0 / substeps)
    gl = np.append(0.0, g)                             # face to the left of each node (none at the surface)
    gr = np.append(g, 0.0)                             # face to the right (none at the adiabatic end)
    ab = np.zeros((3, n))
    ab[0, 1:] = -theta * g
    ab[1, :] = c + theta * (gl + gr)
    ab[2, :-1] = -theta * g
    e0 = np.zeros(n)
    e0[0] = 1.0
    z = solve_banded((1, 1), ab, e0, check_finite=False)   # B⁻¹·e0, shared by every substep (Sherman–Morrison)
    return ab, c - (1.0 - theta) * (gl + gr), gl, gr, z, ic


def march(ab, keep, gl, gr, z, t, h_eff, t_sink, theta: float = THETA):
    """One θ-substep for every column at once (t: nodes × columns). The Robin term θ·H sits on the surface diagonal
    of each column; with B the shared base matrix, A = B + δ·e0·e0ᵀ is solved by Sherman–Morrison."""
    rhs = keep[:, None] * t
    rhs[1:] += (1.0 - theta) * gl[1:, None] * t[:-1]
    rhs[:-1] += (1.0 - theta) * gr[:-1, None] * t[1:]
    rhs[0] += -(1.0 - theta) * h_eff * t[0] + h_eff * t_sink
    y = solve_banded((1, 1), ab, rhs, check_finite=False)
    delta = theta * h_eff
    return y - z[:, None] * (delta * y[0] / (1.0 + delta * z[0]))


def verify_robin() -> float:
    """The scheme against the closed form (Incropera eq. 5.60): a homogeneous dead-bark half-space at 0 °C whose
    surface meets air at −10 °C through a fixed h from t = 0. Worst relative error of ΔT at three depths after 6 h."""
    lam, rc = S58.LAMBDA_BARK_DEAD, S58.RHO_BARK_DEAD * S58.CP_BARK_DEAD
    kappa = lam / rc
    h, t_inf, hours = 8.0, -10.0, 6
    ab, keep, gl, gr, z, _ = base_system([(300.0, lam, rc)], 1.0, SUBSTEPS)
    t = np.zeros((ab.shape[1], 1))
    for _ in range(hours * SUBSTEPS):
        t = march(ab, keep, gl, gr, z, t, np.array([h]), np.array([t_inf]))
    s = hours * 3600.0
    err = 0.0
    for depth in (0.0, 5.0, 10.0):
        x = round(depth / DX_MM) * DX_MM * 1e-3
        a = x / (2.0 * math.sqrt(kappa * s))
        b = h * math.sqrt(kappa * s) / lam
        frac = erfc(a) - math.exp(h * x / lam + b * b) * erfc(a + b)
        want = t_inf * frac
        err = max(err, abs(float(t[round(depth / DX_MM), 0]) - want) / abs(want))
    return err


def verify_diurnal() -> float:
    """SUBSTEPS implicit substeps an hour against a 120-substep Crank–Nicolson reference: a 24 h sinusoidal sink
    through a fixed H on the thin-bark column. Returns the larger |error| of the cambium minimum (K) over two H."""
    b = S78.bark_bracket()["thin_mm"]
    worst = 0.0
    for h in (6.0, 30.0):
        mins = []
        for theta, sub in ((THETA, SUBSTEPS), (0.5, 120)):
            ab, keep, gl, gr, z, ic = base_system(S78.layers(b), b + S58.T_PHLOEM, sub, theta)
            t = np.zeros((ab.shape[1], 1))
            cam = []
            for k in range(12 * 24 * sub):
                t_sink = -10.0 + 8.0 * math.sin(2.0 * math.pi * (k + 0.5) / sub / 24.0)
                t = march(ab, keep, gl, gr, z, t, np.array([h]), np.array([t_sink]), theta)
                if (k + 1) % sub == 0:
                    cam.append(float(t[ic, 0]))
            mins.append(min(cam[-48:]))
        worst = max(worst, abs(mins[0] - mins[1]))
    return worst


def _header(path) -> list:
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        return [fh.readline(), fh.readline()]


def load_cloud(times) -> np.ndarray:
    """ERA5 total cloud cover as a fraction, on the air file's clock (refused otherwise) — the same grid point and UTC
    offset in the header, and the same hour labels."""
    if _header(CLOUD_FILE) != _header(S71.DATA_FILE):
        raise SystemExit("cloud file header (grid point · elevation · UTC offset) differs from the air file's")
    with gzip.open(CLOUD_FILE, "rt", encoding="utf-8") as fh:
        body = [ln for ln in fh if ln[:2] in ("ti", "19", "20")]
    arr = np.genfromtxt(io.StringIO("".join(body[1:])), delimiter=",", dtype=None, encoding="utf-8", names=("time", "c"))
    if not np.array_equal(arr["time"].astype(str), times):
        raise SystemExit("cloud file is not on the air file's clock")
    c = arr["c"].astype(float) / 100.0
    if c.min() < 0.0 or c.max() > 1.0:
        raise SystemExit(f"cloud cover outside 0–100 %: {c.min()}…{c.max()}")
    return c


def load_weather() -> dict:
    h = S71.load_hours()
    _, hd, _, _ = S74.load()
    if not np.array_equal(hd["time"], h["time"]):
        raise SystemExit("dew-point and air files are not on the same clock")
    return {"time": h["time"], "t_air": h["t_air"], "u10": h["u10"], "dif": h["dif"], "dni": h["dni"], "t_dew": hd["td"],
            "cloud": load_cloud(h["time"])}


def _header_dict(path) -> dict:
    names, vals = (line.strip().split(",") for line in _header(path))
    return dict(zip(names, vals, strict=True))


def load_snow(times) -> dict:
    """Hourly snow depth (m) of each reanalysis in SNOW_FILES on the air file's clock — refused unless the header's UTC offset
    and zone and every hour label match; the grid point each returned is recorded, not required to be ERA5's (it is not)."""
    air = _header_dict(S71.DATA_FILE)
    out = {}
    for name, path in SNOW_FILES.items():
        hd = _header_dict(path)
        if (hd["utc_offset_seconds"], hd["timezone"]) != (air["utc_offset_seconds"], air["timezone"]):
            raise SystemExit(f"{path.name}: clock (UTC offset · zone) differs from the air file's")
        with gzip.open(path, "rt", encoding="utf-8") as fh:
            body = [ln for ln in fh if ln[:2] in ("ti", "19", "20")]
        arr = np.genfromtxt(io.StringIO("".join(body[1:])), delimiter=",", dtype=None, encoding="utf-8", names=("time", "d"))
        if not np.array_equal(arr["time"].astype(str), times):
            raise SystemExit(f"{path.name} is not on the air file's clock")
        d = arr["d"].astype(float)
        if not np.all(np.isfinite(d)) or d.min() < 0.0:
            raise SystemExit(f"{path.name}: snow depth missing or negative")
        out[name] = {"depth_m": d, "grid_point": {"lat_deg": float(hd["latitude"]), "lon_deg": float(hd["longitude"]),
                                                  "elevation_m": float(hd["elevation"])}}
    return out


def snow_check(times, snow: dict) -> dict:
    """Each reanalysis against the station, winter days of the station's span: the share of days with snow at each depth
    and the day-by-day agreement, the reanalysis read at STATION_HOUR. The station reports depth only on days with snow (no
    zero is recorded), so a day without a record counts as snow-free — the same rule a missed observation would follow; rows
    with a quality flag are dropped. Gated on Cohen's κ (agreement beyond what the two snow shares give by chance). CAN catch
    a series unrelated to the station's winters — another file, another variable, an empty or a constant series (κ ≈ 0);
    CANNOT catch a series off by a day or two (snow persists, κ barely moves), and cannot tell which reanalysis is right at
    the cell (the station is ~100 km away, at 50.0 N 33.0 E)."""
    station = {}
    with open(STATION_SNOW_FILE, encoding="utf-8") as fh:
        for r in csv.reader(fh):
            if r[2] == "SNWD" and r[5] == "":
                station[f"{r[1][:4]}-{r[1][4:6]}-{r[1][6:]}"] = int(r[3]) / 1000.0
    hour = np.array([t[11:13] == STATION_HOUR for t in times])
    days = [t[:10] for t in np.asarray(times)[hour]]
    winter = np.array([int(d[5:7]) in WINTER_MONTHS for d in days])
    days_w = [d for d, w in zip(days, winter, strict=True) if w]
    st = np.array([station.get(d, 0.0) for d in days_w])
    out = {"station": "GHCN-Daily UPM00033377 Lubny (WMO 33377), SNWD", "winter_days": len(days_w), "depths_m": {}}
    for z in SNOW_CHECK_DEPTHS_M:
        sb = st >= z - 1e-9
        row = {"station_snow_share": round(float(sb.mean()), 3), "never_snow_agreement": round(float(1.0 - sb.mean()), 3)}
        for name, s in snow.items():
            rb = s["depth_m"][hour][winter] >= z - 1e-9
            po, pe = float(np.mean(rb == sb)), float(rb.mean() * sb.mean() + (1.0 - rb.mean()) * (1.0 - sb.mean()))
            row[name] = {"snow_share": round(float(rb.mean()), 3), "agreement": round(po, 3),
                         "kappa": round((po - pe) / (1.0 - pe), 3)}
        out["depths_m"][f"{z:g}"] = row
    worst = min(row[n]["kappa"] for row in out["depths_m"].values() for n in snow)
    if worst < SNOW_CHECK_MIN_KAPPA:
        raise SystemExit(f"snow check failed: κ against the station {worst:.3f} < {SNOW_CHECK_MIN_KAPPA} — {out}")
    return out


def check_reflect_ends(snow: dict, day_w) -> dict:
    """The low end must take the reanalysis with the LEAST winter-daylight snow at its depth and the high end the one with the
    MOST at its own — asserted, so a new snow file or a moved depth cannot silently swap which end is which. CAN catch an end
    whose source is not the extreme its comment names; CANNOT say which reanalysis is right at the cell."""
    share = {f"{src}/{z:g}": round(float(np.mean(s["depth_m"][day_w] >= z - 1e-9)), 3)
             for src, s in snow.items() for z in SNOW_CHECK_DEPTHS_M}
    for name, src, z, _, _ in REFLECT_ENDS:
        pick = (min if name == "low" else max)(snow, key=lambda s, z=z: share[f"{s}/{z:g}"])
        if share[f"{pick}/{z:g}"] != share[f"{src}/{z:g}"]:
            raise SystemExit(f"reflect end {name!r} takes {src} at ≥ {z} m, but {pick} is the "
                             f"{'least' if name == 'low' else 'most'} snowy there: {share}")
    return share


def reflected_rows(snow: dict, ghi) -> np.ndarray:
    """ρ·GHI (W/m² on the ground) per REFLECT_NAMES row and hour: row 0 none, then each end's albedo switched by its
    reanalysis's snow depth."""
    rows = [np.zeros_like(ghi)]
    for _, src, depth, rho_snow, rho_ground in REFLECT_ENDS:
        rows.append(np.where(snow[src]["depth_m"] >= depth - 1e-9, rho_snow, rho_ground) * ghi)
    return np.array(rows)


def coefficients(t_s, t_air, t_sky4_clear, u, cols, dif, d_dome, trunk_l_m=TRUNK_L_M, cap_hc_as_bark=False, cloud=0.0,
                 beam=0.0, refl=0.0):
    """Every column at once: H (W/m²K per area of bark under the column) and the sink temperature of the balance
    linearised around the current surface temperature t_s. `refl` — ρ·GHI on the ground, received through the ground's
    share of the view (1 − F), the same isotropic split the diffuse sky term uses."""
    t_film = 0.5 * (t_s + t_air)
    dt = t_s - t_air
    h_bark = np.maximum(h_vertical(trunk_l_m, dt, t_film), S71.h_forced(DBH_MIN_CM / 100.0, u, t_film))
    h_cap = h_bark if cap_hc_as_bark else np.maximum(S71.h_natural(d_dome, np.abs(dt), t_film),
                                                     S71.h_forced(d_dome, u, t_film))
    h_c = np.where(cols["is_bark"], h_bark, h_cap)
    ts_k, ta_k = t_s + 273.15, t_air + 273.15
    sky = cols["sky"]
    t_sky4 = np.where(sky == SKY_CODE["overcast"], ta_k ** 4,
                      np.where(sky == SKY_CODE["linear"], cloud * ta_k ** 4 + (1.0 - cloud) * t_sky4_clear,
                               np.where(sky == SKY_CODE["b82"], np.minimum((1.0 + B82_C * cloud * cloud) * t_sky4_clear,
                                                                            ta_k ** 4),
                                        t_sky4_clear)))
    t_env4 = SKY_VIEW * t_sky4 + (1.0 - SKY_VIEW) * ta_k ** 4
    h_r = 4.0 * EPSILON * SIGMA * ts_k ** 3
    q0 = EPSILON * SIGMA * (ts_k ** 4 - t_env4)          # radiative loss at the current surface temperature
    q_sun = (cols["alpha"] * SKY_VIEW * dif + cols["alpha"] * beam       # absorbed diffuse, beam and ground-reflected,
             + cols["alpha"] * (1.0 - SKY_VIEW) * refl)                     # W per m² of exposed surface
    h_tot = h_c + h_r
    t_sink = (h_c * t_air + h_r * t_s - q0 + q_sun) / h_tot
    return cols["fin"] * h_tot, t_sink


def column_table(ar: dict, regimes=REGIMES, winds=WIND_K) -> tuple[dict, list]:
    """The columns of one bark side: per regime and wind — bark, decoupled, tied. Returns the per-column arrays the
    balance needs and the (regime, coupling, wind) label of each column."""
    labels, is_bark, sky, alpha, fin = [], [], [], [], []
    for name, kind, sun in regimes:   # `kind` — REGIMES' overcast flag, or CLOUD_REGIMES' sky form
        for k in winds:
            for cp in ("bark", *COUPLINGS):
                labels.append((name, cp, k))
                is_bark.append(cp == "bark")
                sky.append(SKY_CODE[kind] if isinstance(kind, str) else SKY_CODE["overcast" if kind else "clear"])
                alpha.append((ALPHA_BARK if cp == "bark" else ALPHA_FIN) if sun else 0.0)
                fin.append(1.0 if cp == "bark" else ar["fin_ratio"][cp])
    cols = {"is_bark": np.array(is_bark), "sky": np.array(sky), "alpha": np.array(alpha),
            "fin": np.array(fin), "wind_k": np.array([lab[2] for lab in labels])}
    return cols, labels


def simulate(stack, probe_mm, wx, cols, substeps=SUBSTEPS, trunk_l_m=TRUNK_L_M, cap_hc_as_bark=False, geom=None, refl=None):
    """Every column of one bark side marches together; returns the cambium series (hours × columns) and the surface.
    `geom` — `face_factors` for a beam table (its columns carry `az`, `c_face`, `c_side`); None — no beam.
    `refl` — `reflected_rows` for a table whose columns carry `refl` (a row index); None — no ground-reflected light."""
    ab, keep, gl, gr, z, ic = base_system(stack, probe_mm, substeps)
    d_dome = S71.geometry()["dome_diameter_mm"] * 1e-3
    n_h, n_c = len(wx["t_air"]), len(cols["fin"])
    t = np.full((ab.shape[1], n_c), wx["t_air"][0])
    cam = np.empty((n_h, n_c))
    surf = np.empty((n_h, n_c))
    cam[0], surf[0] = t[ic], t[0]
    eps_sky = sky_emissivity(wx["t_air"], wx["t_dew"])
    for hr in range(1, n_h):
        t0, t1 = wx["t_air"][hr - 1], wx["t_air"][hr]
        t_sky4 = eps_sky[hr] * (t1 + 273.15) ** 4
        beam = 0.0 if geom is None else wx["dni"][hr] * (cols["c_face"] * geom[0][cols["az"], hr]
                                                         + cols["c_side"] * geom[1][cols["az"], hr])
        rf = 0.0 if refl is None else refl[cols["refl"], hr]
        for s in range(substeps):
            ta = t0 + (t1 - t0) * (s + 0.5) / substeps
            h_eff, t_sink = coefficients(t[0], ta, t_sky4, cols["wind_k"] * wx["u10"][hr], cols, wx["dif"][hr],
                                         d_dome, trunk_l_m, cap_hc_as_bark, wx["cloud"][hr] if "cloud" in wx else 0.0,
                                         beam, rf)
            t = march(ab, keep, gl, gr, z, t, h_eff, t_sink)
        cam[hr], surf[hr] = t[ic], t[0]
    return cam, surf


def stack_with(bark_mm: float, sapwood_mm: float | None = None) -> list:
    """`78`'s layers, or the same with another sapwood depth for the store sensitivity."""
    if sapwood_mm is None:
        return S78.layers(bark_mm)
    return [*S78.layers(bark_mm)[:2], (sapwood_mm, S58.LAMBDA_WOOD, S58.RHO_WOOD * S58.CP_WOOD)]


def daily_minima(series, times, skip_days=SPIN_UP_DAYS):
    """Minimum per calendar day after the spin-up (days × columns). The data clock is a fixed UTC+3 without DST
    (Open-Meteo), so every day is 24 rows from 00:00 — checked, not assumed."""
    if len(times) % 24 or not all(times[i].endswith("T00:00") for i in range(0, len(times), 24 * 365)):
        raise SystemExit("hourly series is not whole days from 00:00 — the daily reshape would mix days")
    return series[skip_days * 24:].reshape(-1, 24, series.shape[1]).min(axis=1)


def shift_stats(mins: np.ndarray, j_bark: int, j_flange: int) -> dict:
    """Daily-minimum shift on frost days, bark minus flange: + = the spot under the flange runs colder."""
    frost = mins[:, j_bark] < FROST_DAY_C
    s = mins[frost, j_bark] - mins[frost, j_flange]
    return {"frost_days": int(np.count_nonzero(frost)), "median": round(float(np.median(s)), 2),
            "p95": round(float(np.percentile(s, 95)), 2), "max": round(float(s.max()), 2), "min": round(float(s.min()), 2)}


def verify_timestep(wx, ar) -> dict:
    """SUBSTEPS against six times as many on the 40 days around the coldest ERA5 hour (thin bark, still air, clear,
    no sun): the largest error of the daily cambium minimum and of the tied and decoupled shifts."""
    i = int(np.argmin(wx["t_air"]))
    d0 = max(0, (i // 24 - 20) * 24)
    w = {k: v[d0:d0 + 24 * 40] for k, v in wx.items()}
    cols, _ = column_table(ar, REGIMES[:1], WIND_K[:1])
    b = S78.bark_bracket()["thin_mm"]
    mins = []
    for sub in (SUBSTEPS, 6 * SUBSTEPS):
        cam, _ = simulate(S78.layers(b), b + S58.T_PHLOEM, w, cols, sub)
        mins.append(daily_minima(cam, w["time"], 5))
    a, r = mins
    return {"window_start": str(w["time"][0]), "daily_min_err_K": round(float(np.abs(a - r).max()), 4),
            "shift_err_K": round(float(max(np.abs((a[:, 0] - a[:, j]) - (r[:, 0] - r[:, j])).max() for j in (1, 2))), 4)}


def site() -> dict:
    """The grid point and the clock the ERA5 files declare in their header — never typed."""
    names, vals = (line.strip().split(",") for line in _header(S71.DATA_FILE))
    row = dict(zip(names, vals, strict=True))
    return {"lat_deg": float(row["latitude"]), "lon_deg": float(row["longitude"]),
            "utc_offset_h": int(row["utc_offset_seconds"]) / 3600.0}


def _spencer(g):
    """Equation of time (min) and declination (rad) at fractional year g (rad) — NOAA GML's series."""
    eqt = 229.18 * (0.000075 + 0.001868 * np.cos(g) - 0.032077 * np.sin(g) - 0.014615 * np.cos(2 * g)
                    - 0.040849 * np.sin(2 * g))
    dec = (0.006918 - 0.399912 * np.cos(g) + 0.070257 * np.sin(g) - 0.006758 * np.cos(2 * g) + 0.000907 * np.sin(2 * g)
           - 0.002697 * np.cos(3 * g) + 0.00148 * np.sin(3 * g))
    return eqt, dec


def sun_enu(times, st: dict, shift_h: float = 0.0, n: int = SUN_SUBSAMPLES) -> np.ndarray:
    """Unit vector to the sun (east, north, up) at the mid-points of n slices of the hour each radiation value
    averages — the hour BEFORE its label — moved by `shift_h` for the clock check only. Shape (3, hours, n)."""
    t = np.asarray(times).astype("datetime64[s]") - np.timedelta64(round(st["utc_offset_h"] * 3600), "s")
    sub = np.array([round((-1.0 + (k + 0.5) / n + shift_h) * 3600.0) for k in range(n)]).astype("timedelta64[s]")
    tu = t[:, None] + sub[None, :]
    y0 = tu.astype("datetime64[Y]")
    d0 = tu.astype("datetime64[D]")
    days = ((y0 + np.timedelta64(1, "Y")).astype("datetime64[D]") - y0.astype("datetime64[D]")).astype(float)
    doy = (d0 - y0.astype("datetime64[D]")).astype(float) + 1.0
    minutes = (tu - d0).astype(float) / 60.0
    eqt, dec = _spencer(2.0 * math.pi / days * (doy - 1.0 + (minutes / 60.0 - 12.0) / 24.0))
    ha = np.radians((minutes + eqt + 4.0 * st["lon_deg"]) / 4.0 - 180.0)
    p = math.radians(st["lat_deg"])
    return np.stack((-np.cos(dec) * np.sin(ha),
                     np.sin(dec) * math.cos(p) - np.cos(dec) * np.cos(ha) * math.sin(p),
                     np.sin(dec) * math.sin(p) + np.cos(dec) * np.cos(ha) * math.cos(p)))


def verify_sun_geometry(st: dict, times) -> dict:
    """The series against what it must give: declination extremes at the obliquity (23.44°), equation-of-time extremes
    −14.2 / +16.4 min, and the June noon altitude 90° − φ + 23.44° on the data's own hours — catches a wrong
    coefficient, a sign or a wrong hour angle; blind to the clock (that is `verify_sun_clock`'s)."""
    eqt, dec = _spencer(np.linspace(0.0, 2.0 * math.pi, 3651))
    june = np.array([str(x)[5:7] == "06" for x in times[:24 * 366]])
    alt = math.degrees(math.asin(float(sun_enu(np.asarray(times[:24 * 366])[june], st)[2].max())))
    out = {"declination_deg": [round(math.degrees(float(dec.min())), 3), round(math.degrees(float(dec.max())), 3)],
           "equation_of_time_min": [round(float(eqt.min()), 2), round(float(eqt.max()), 2)],
           "june_noon_altitude_deg": round(alt, 3), "june_noon_altitude_expected_deg": round(90.0 - st["lat_deg"] + 23.44, 3)}
    if (max(abs(abs(x) - 23.44) for x in out["declination_deg"]) > 0.1
            or abs(out["equation_of_time_min"][0] + 14.2) > 0.3 or abs(out["equation_of_time_min"][1] - 16.4) > 0.3
            or abs(alt - out["june_noon_altitude_expected_deg"]) > 0.1):
        raise SystemExit(f"sun geometry check failed: {out}")
    return out


def verify_sun_clock(times, dni, st: dict) -> dict:
    """Is the computed sun on the data's clock? The share of all DNI energy that falls in hours whose sun never clears
    the horizon, at the declared convention and with the geometry moved by ½ and 1 h either way: the declared one
    must hold none of it and every shift some — catches a wrong UTC offset or the preceding-hour convention read
    backwards; blind to an error well inside an hour."""
    out = {}
    for sh in CLOCK_SHIFTS_H:
        up = np.maximum(sun_enu(times, st, sh)[2], 0.0).mean(axis=1)
        out[f"{sh:+.1f}"] = float(dni[up == 0.0].sum() / dni.sum())
    if out["+0.0"] > 1e-5 or min(v for k, v in out.items() if k != "+0.0") < 1e-4:
        raise SystemExit(f"sun clock check failed: DNI share in sun-down hours {out}")
    return {k: float(f"{v:.3g}") for k, v in out.items()}


def face_factors(sun: np.ndarray) -> tuple:
    """Per azimuth and hour, the hour-means of cos γ and sin γ over the moments the sun is above the horizon AND in
    front of the face (γ — between the sun and the face's outward normal; behind it the stem shades the face).
    Two arrays of shape (len(AZIMUTHS_DEG), hours)."""
    e, n, u = sun
    gc, gs = [], []
    for a in AZIMUTHS_DEG:
        c = e * math.sin(math.radians(a)) + n * math.cos(math.radians(a))
        lit = (u > 0.0) & (c > 0.0)
        gc.append(np.where(lit, c, 0.0).mean(axis=1))
        gs.append(np.where(lit, np.sqrt(np.clip(1.0 - c * c, 0.0, None)), 0.0).mean(axis=1))
    return np.array(gc), np.array(gs)


def beam_projection(ar: dict) -> dict:
    """Each column's sunlit silhouette per unit of its fin area, as c_face·cos γ + c_side·sin γ: bark — its own face;
    the band — a short cylinder on the face normal (d·t·sin γ over π·d·t); band and capsule — the crown disc face-on
    plus the capsule's and the band's sides edge-on. The capsule part's maximum over γ must be 71's worst-orientation
    projection — the same lump, checked."""
    g = S71.geometry()
    d, h = g["dome_diameter_mm"], g["h_over_bark_mm"]
    a_crown, side_cap = math.pi * d * d / 4.0, d * h
    side_band = ar["flange_diameter_mm"] * ar["flange_thickness_mm"]
    a_tied = ar["flange_band_mm2"] + ar["capsule_exposed_mm2"]
    if abs(math.hypot(a_crown, side_cap) - g["a_proj_max_mm2"]) > 1e-3 * g["a_proj_max_mm2"]:
        raise SystemExit("beam silhouette of the capsule is not 71's lump")
    return {"bark": (1.0, 0.0), "decoupled": (0.0, round(side_band / ar["flange_band_mm2"], 6)),
            "tied": (round(a_crown / a_tied, 6), round((side_cap + side_band) / a_tied, 6))}


def beam_column_table(ar: dict, form: str, proj: dict, azimuths=AZIMUTHS_DEG, winds=WIND_K, refl: str = "none") -> tuple[dict, list]:
    """The columns of one bark side for one real-cloud form with diffuse sun and beam: per azimuth and wind — bark,
    decoupled, tied — each with its azimuth's index into `face_factors`, its silhouette coefficients and the row of
    `reflected_rows` it receives (`refl`, a name in REFLECT_NAMES)."""
    parts, labels = [], []
    for a in azimuths:
        cols, lab = column_table(ar, ((form, form, True),), winds)
        cols["az"] = np.full(len(lab), AZIMUTHS_DEG.index(a))
        cols["c_face"] = np.array([proj[cp][0] for _, cp, _ in lab])
        cols["c_side"] = np.array([proj[cp][1] for _, cp, _ in lab])
        cols["refl"] = np.full(len(lab), REFLECT_NAMES.index(refl))
        parts.append(cols)
        labels += [(a, cp, k) for _, cp, k in lab]
    return {key: np.concatenate([c[key] for c in parts]) for key in parts[0]}, labels


def verify_timestep_beam(wx, ar, geom, proj, refl) -> dict:
    """SUBSTEPS against six times as many on three 40-day windows (thin bark, still air, the linear cloud form, north and
    south faces, without and with the HIGH end of ground-reflected light): around the winter hour of the largest beam on
    the south face, where the beam drives hardest; around the warmest winter hour, where the spot under the flange also
    crosses DEHARDEN_C — a window without such hours under the flange would gate its hour count vacuously (adversarial
    review 2026-10-14); and around the winter hour of the largest high-end reflected light, where the new term drives
    hardest. The largest error of the daily cambium minimum and maximum and of the shift, and every column's hours above
    DEHARDEN_C (keys `az/cp` without reflected light, `az/high/cp` with it)."""
    winter = np.array([int(x[5:7]) in WINTER_MONTHS for x in wx["time"]])
    picks = {"largest_south_beam": int(np.argmax(np.where(winter, wx["dni"] * geom[0][AZIMUTHS_DEG.index(180)], -1.0))),
             "warmest_winter_hour": int(np.argmax(np.where(winter, wx["t_air"], -99.0))),
             "largest_reflected_high": int(np.argmax(np.where(winter, refl[REFLECT_NAMES.index("high")], -1.0)))}
    parts = [beam_column_table(ar, "linear", proj, (0, 180), WIND_K[:1], r) for r in ("none", "high")]
    cols = {key: np.concatenate([p[0][key] for p in parts]) for key in parts[0][0]}
    labels = [(r, *lab) for r, p in zip(("none", "high"), parts, strict=True) for lab in p[1]]
    key = {lab: (f"{lab[1]}/{lab[2]}" if lab[0] == "none" else f"{lab[1]}/{lab[0]}/{lab[2]}") for lab in labels}
    b = S78.bark_bracket()["thin_mm"]
    out = {}
    for name, i in picks.items():
        d0 = max(0, (i // 24 - 20) * 24)
        w = {k: v[d0:d0 + 24 * 40] for k, v in wx.items()}
        g = (geom[0][:, d0:d0 + 24 * 40], geom[1][:, d0:d0 + 24 * 40])
        res = []
        for sub in (SUBSTEPS, 6 * SUBSTEPS):
            cam, _ = simulate(S78.layers(b), b + S58.T_PHLOEM, w, cols, sub, geom=g, refl=refl[:, d0:d0 + 24 * 40])
            c = cam[5 * 24:]
            res.append((c.reshape(-1, 24, c.shape[1]).min(axis=1), c.reshape(-1, 24, c.shape[1]).max(axis=1),
                        (c > DEHARDEN_C).sum(axis=0)))
        (mn_a, mx_a, h_a), (mn_r, mx_r, h_r) = res
        pairs = [(labels.index((r, a, "bark", WIND_K[0])), labels.index((r, a, cp, WIND_K[0])))
                 for r in ("none", "high") for a in (0, 180) for cp in COUPLINGS]
        out[name] = {"window_start": str(w["time"][0]), "daily_min_err_K": round(float(np.abs(mn_a - mn_r).max()), 4),
                     "daily_max_err_K": round(float(np.abs(mx_a - mx_r).max()), 4),
                     "shift_err_K": round(float(max(np.abs((mn_a[:, jb] - mn_a[:, jf]) - (mn_r[:, jb] - mn_r[:, jf])).max()
                                                    for jb, jf in pairs)), 4),
                     "hours_above_deharden": {key[lab]: int(h_a[j]) for j, lab in enumerate(labels)},
                     "hours_above_deharden_reference": {key[lab]: int(h_r[j]) for j, lab in enumerate(labels)}}
    return out


def _shift_class(s):
    """−1 warmer · 0 neither · +1 colder under the flange, at COLDER_BAND_K."""
    return np.sign(np.where(np.abs(s) > COLDER_BAND_K, s, 0.0))


def verify_timestep_series(wx, ar, geom, proj, refl) -> dict:
    """SUBSTEPS against 3× as many over the WHOLE series (thin bark, still air) for the most strongly sun-driven columns: the
    beam with the high end of ground-reflected light on the north and south faces in both cloud forms, and the diffuse-only
    B82 form. Implicit Euler is first order in the step, so the error at SUBSTEPS is read as 1.5·|u − u₃ₓ| (Richardson; hourly
    forcing is not smooth, so it is a reading, not a bound). Per frost day of each face's bark: the largest such error of the
    shift, and the share of frost days whose colder · neither · warmer class (COLDER_BAND_K) differs between the two runs; per
    column: the error of its coldest hour, and of its winter hours above DEHARDEN_C against SERIES_HOURS_TOL (the beam
    windows judge those on three windows only — adversarial review 2026-10-18).
    CAN catch a step too coarse ANYWHERE in the 30 years for these columns, on the shift, the floor and the hour count;
    CANNOT speak for the thick bark, wind, or columns driven less hard than these."""
    b = S78.bark_bracket()["thin_mm"]
    times = wx["time"]
    win_h = (np.isin(np.array([int(x[5:7]) for x in times]), WINTER_MONTHS)
             & (np.arange(len(times)) >= SPIN_UP_DAYS * 24))
    sets = []
    for form in BEAM_FORMS:
        bc, bl = beam_column_table(ar, form, proj, (0, 180), WIND_K[:1], "high")
        sets.append((f"beam_high_{form}", bc, [(a, cp) for a, cp, _ in bl], {"geom": geom, "refl": refl}))
    cl_cols, cl_lab = column_table(ar, (("cloud_b82_diffuse_sun", "b82", True),), WIND_K[:1])
    sets.append(("diffuse_b82", cl_cols, [(None, cp) for _, cp, _ in cl_lab], {}))
    out = {}
    for name, cols, lab, kw in sets:
        cams = [simulate(S78.layers(b), b + S58.T_PHLOEM, wx, cols, sub, **kw)[0] for sub in (SUBSTEPS, 3 * SUBSTEPS)]
        mins = [daily_minima(c, times) for c in cams]
        worst, flips, n = 0.0, 0, 0
        for j, (a, cp) in enumerate(lab):
            if cp == "bark":
                continue
            jb = lab.index((a, "bark"))
            frost = mins[0][:, jb] < FROST_DAY_C
            s1, s3 = mins[0][frost, jb] - mins[0][frost, j], mins[1][frost, jb] - mins[1][frost, j]
            worst = max(worst, float(1.5 * np.abs(s1 - s3).max()))
            flips += int(np.count_nonzero(_shift_class(s1) != _shift_class(s3)))
            n += int(frost.sum())
        cut = np.arange(len(times)) >= SPIN_UP_DAYS * 24
        floor_err = max(1.5 * abs(float(cams[0][cut, j].min()) - float(cams[1][cut, j].min())) for j in range(len(lab)))
        hours = {f"{a}/{cp}": (int(np.count_nonzero(cams[0][win_h, j] > DEHARDEN_C)),
                               int(np.count_nonzero(cams[1][win_h, j] > DEHARDEN_C))) for j, (a, cp) in enumerate(lab)}
        out[name] = {"shift_err_K_max": round(worst, 4), "class_flip_share": round(flips / n, 4), "frost_day_pairs": n,
                     "floor_err_K_max": round(floor_err, 4),
                     "hours_above_deharden": {k: v[0] for k, v in hours.items()},
                     "hours_above_deharden_err": {k: round(1.5 * abs(v[0] - v[1]), 1) for k, v in hours.items()},
                     "hours_within_tolerance": all(1.5 * abs(v[0] - v[1]) <= max(SERIES_HOURS_TOL[0], SERIES_HOURS_TOL[1] * v[1])
                                                   for v in hours.values())}
        del cams
    return out


def mechanism(ar: dict) -> dict:
    """Why the clear sky favours the flange, as numbers: the no-conduction equilibrium of flat bark and of the capsule
    at one cold clear still hour, with the h_c each settles at, and the fin's conductance against bark's there."""
    ta, td = REFERENCE_HOUR["t_air_C"], REFERENCE_HOUR["t_dew_C"]
    ta_k = ta + 273.15
    t_env4 = SKY_VIEW * float(sky_emissivity(ta, td)) * ta_k ** 4 + (1.0 - SKY_VIEW) * ta_k ** 4
    d = S71.geometry()["dome_diameter_mm"] * 1e-3
    out = {}
    for kind in ("bark", "capsule"):
        def hc(ts, kind=kind):
            film, dt = 0.5 * (ts + ta), ts - ta
            return float(h_vertical(TRUNK_L_M, dt, film)) if kind == "bark" else float(S71.h_natural(d, abs(dt), film))
        teq = brentq(lambda ts, hc=hc: hc(ts) * (ts - ta) + EPSILON * SIGMA * ((ts + 273.15) ** 4 - t_env4), ta - 30, ta)
        h_r = 4.0 * EPSILON * SIGMA * (teq + 273.15) ** 3
        out[kind] = {"equilibrium_minus_air_K": round(teq - ta, 2), "h_c_W_m2K": round(hc(teq), 2),
                     "h_total_W_m2K": round(hc(teq) + h_r, 2)}
    out["tied_over_bark_conductance"] = round(ar["fin_ratio"]["tied"] * out["capsule"]["h_total_W_m2K"]
                                              / out["bark"]["h_total_W_m2K"], 1)
    out["reference_hour"] = REFERENCE_HOUR
    return out


def summarise_regime(runs: list, name: str) -> dict:
    out = {}
    for cp in COUPLINGS:
        rs = [r for r in runs if r["regime"] == name and r["coupling"] == cp]
        med = [r["shift_K"]["median"] for r in rs]
        out[cp] = {"median_K_range": [min(med), max(med)], "p95_K_max": max(r["shift_K"]["p95"] for r in rs),
                   "max_K": max(r["shift_K"]["max"] for r in rs)}
        worst = max(rs, key=lambda r: r["shift_K"]["max"])
        out[cp]["worst_cell"] = {"bark_side": worst["bark_side"], "wind_k": worst["wind_k"]}
    return out


def beam_summary(runs: list, n_years: int) -> dict:
    """The beam block's summaries over the runs of ONE ground-reflection setting: per azimuth and coupling the ranges over
    form, wind and bark side; the coldest hour under the flange, south minus north, per cell; the month cells where the
    flange spot crosses DEHARDEN_C more often than the bark beside it; whether no winter total does."""
    by_az = {}
    for a in AZIMUTHS_DEG:
        by_az[str(a)] = {}
        for cp in COUPLINGS:
            rows = [r for r in runs if r["azimuth_deg"] == a and r["coupling"] == cp]
            med, sh = [r["shift_K"]["median"] for r in rows], [r["colder_share"] for r in rows]
            cd = [r["cold_days"]["colder_share"] for r in rows if r["cold_days"]["days"]]
            hb = [r["winter_hours_above_deharden"]["no_flange"] / n_years for r in rows]
            hf = [r["winter_hours_above_deharden"]["flange"] / n_years for r in rows]
            by_az[str(a)][cp] = {
                "median_K_range": [min(med), max(med)], "p95_K_max": max(r["shift_K"]["p95"] for r in rows),
                "max_K": max(r["shift_K"]["max"] for r in rows), "colder_share_range": [min(sh), max(sh)],
                "cold_days_colder_share_range": [min(cd), max(cd)] if cd else None,
                "winter_hours_above_deharden_per_year": {"no_flange": [round(min(hb), 1), round(max(hb), 1)],
                                                         "flange": [round(min(hf), 1), round(max(hf), 1)]},
                "winter_cambium_max_C": {"no_flange": max(r["winter_cambium_max_C"]["no_flange"] for r in rows),
                                         "flange": max(r["winter_cambium_max_C"]["flange"] for r in rows)}}
    floor_sn = {}
    for cp in COUPLINGS:
        dd = [cell["cambium_min_C"]["flange"] - next(r for r in runs if r["azimuth_deg"] == 0 and
              (r["form"], r["coupling"], r["wind_k"], r["bark_side"]) == (cell["form"], cp, cell["wind_k"], cell["bark_side"]))["cambium_min_C"]["flange"]
              for cell in runs if cell["azimuth_deg"] == 180 and cell["coupling"] == cp]
        floor_sn[cp] = [round(min(dd), 2), round(max(dd), 2)]
    exceptions = [{"form": r["form"], "azimuth_deg": r["azimuth_deg"], "coupling": r["coupling"], "wind_k": r["wind_k"],
                   "bark_side": r["bark_side"], "month": mo, **v}
                  for r in runs for mo, v in r["winter_hours_above_deharden_by_month"].items() if v["flange"] > v["no_flange"]]
    sheds = all(r["winter_hours_above_deharden"]["flange"] <= r["winter_hours_above_deharden"]["no_flange"] for r in runs)
    return {"by_azimuth": by_az, "floor_sn": floor_sn, "month_exceptions": exceptions, "fin_sheds": sheds}


def _floor2(x: float) -> float:
    return math.floor(x * 100.0 + 1e-9) / 100.0


def reflection_readings(runs_by: dict, summ: dict, reflected: dict) -> tuple[dict, dict, str]:
    """The ground-reflected block's readings, per REFLECT_NAMES row, read off the beam runs and their summaries — kept out of
    `main` so it can be rehearsed on a cache before an hours-long run. Returns (readings, cell checks, verdict clause).

    The azimuth leg's readings. DECLARED before the data (2026-10-14): the coldest hour under the tied flange warmer on a
    south face than on a north one in every cell — `floor_sn` pairs the faces cell by cell; fewer winter hours above
    DEHARDEN_C under the tied flange on every north cell than on any south one — a separation of RANGES, north's top against
    south's bottom across cells. ADDED after the reflected runs broke the second (2026-10-18): the same hours paired cell by
    cell (form · wind · bark side), the pairing the floor already had — the like-for-like reading for one tree under one sky.
    It is reported BESIDE the declared one, never in its place, and the declared one's margin is reported with it."""
    def cells(rn):
        return {(r["form"], r["azimuth_deg"], r["coupling"], r["wind_k"], r["bark_side"]): r for r in runs_by[rn]}

    def azimuth_reading(rn):
        by, fl = summ[rn]["by_azimuth"], "winter_hours_above_deharden_per_year"
        c = cells(rn)
        pairs = [(c[(f, 180, cp, k, s)]["winter_hours_above_deharden"]["flange"], r["winter_hours_above_deharden"]["flange"])
                 for (f, a, cp, k, s), r in c.items() if a == 0 and cp == "tied"]
        return {"floor_south_warmer_every_cell": summ[rn]["floor_sn"]["tied"][0] > 0.0,
                "deharden_fewer_north_than_south_under_tied_flange": by["0"]["tied"][fl]["flange"][1] < by["180"]["tied"][fl]["flange"][0],
                "deharden_range_margin_south_min_minus_north_max_per_year":
                    round(by["180"]["tied"][fl]["flange"][0] - by["0"]["tied"][fl]["flange"][1], 1),
                "deharden_south_over_north_under_tied_flange_min_cellwise_added_after_data":
                    round(min(s / n for s, n in pairs if n > 0), 3),
                "cells_with_no_north_hours": sum(1 for _, n in pairs if n == 0)}
    c0 = cells("none")
    refl_moves = {"none": azimuth_reading("none")}
    rise = {}
    for rn in REFLECT_NAMES[1:]:
        c1 = cells(rn)
        d_med = [c1[k]["shift_K"]["median"] - c0[k]["shift_K"]["median"] for k in c0]
        d_floor = [c1[k]["cambium_min_C"]["flange"] - c0[k]["cambium_min_C"]["flange"] for k in c0]
        refl_moves[rn] = {"median_shift_minus_no_reflection_K": [round(min(d_med), 2), round(max(d_med), 2)],
                          "coldest_hour_under_flange_minus_no_reflection_K": [round(min(d_floor), 2), round(max(d_floor), 2)],
                          **azimuth_reading(rn)}
        rise[rn] = all(c1[k]["winter_hours_above_deharden"][s] >= c0[k]["winter_hours_above_deharden"][s]
                       for k in c0 for s in ("no_flange", "flange"))
    lo, hi = cells("low"), cells("high")
    quantities = {"hours_above_deharden_flange": lambda r: r["winter_hours_above_deharden"]["flange"],
                  "hours_above_deharden_bark": lambda r: r["winter_hours_above_deharden"]["no_flange"],
                  "coldest_hour_flange": lambda r: r["cambium_min_C"]["flange"],
                  "median_shift": lambda r: r["shift_K"]["median"]}
    mono = {q: all(f(lo[k]) <= f(hi[k]) + 1e-9 for k in lo) for q, f in quantities.items()}
    checks = {"monotone_low_to_high_every_cell": mono, "hours_above_deharden_rise_over_no_reflection_every_cell": rise}
    ends = REFLECT_NAMES[1:]
    declared = ("floor_south_warmer_every_cell", "deharden_fewer_north_than_south_under_tied_flange")
    hold = all(refl_moves[rn][k] for rn in REFLECT_NAMES for k in declared)
    broken = []
    for rn in REFLECT_NAMES:
        fl = summ[rn]["by_azimuth"]
        where = "without it" if rn == "none" else f"at the {rn} end"
        if not refl_moves[rn]["floor_south_warmer_every_cell"]:
            broken.append(f"{where} the coldest hour under the tied flange is not warmer on a south face in every cell "
                          f"(south minus north {summ[rn]['floor_sn']['tied'][0]:+.2f}…{summ[rn]['floor_sn']['tied'][1]:+.2f} K)")
        if not refl_moves[rn]["deharden_fewer_north_than_south_under_tied_flange"]:
            n_, s_ = (fl[a]["tied"]["winter_hours_above_deharden_per_year"]["flange"] for a in ("0", "180"))
            broken.append(f"{where} the hours above {DEHARDEN_C:g} °C under the tied flange no longer separate north "
                          f"({n_[0]:.0f}–{n_[1]:.0f} a winter) from south ({s_[0]:.0f}–{s_[1]:.0f})")

    def hours(az, key):
        rs = [summ[rn]["by_azimuth"][str(az)]["tied"]["winter_hours_above_deharden_per_year"][key] for rn in ends]
        return f"{min(r[0] for r in rs):.0f}–{max(r[1] for r in rs):.0f}"
    e_lo, e_hi = (reflected["ends"][rn]["reflected_on_vertical_over_model_diffuse"] for rn in ("low", "high"))
    dm = [x for rn in ends for x in refl_moves[rn]["median_shift_minus_no_reflection_K"]]
    df = [x for rn in ends for x in refl_moves[rn]["coldest_hour_under_flange_minus_no_reflection_K"]]
    (_, s_lo, z_lo, r_lo_s, r_lo_g), (_, s_hi, z_hi, r_hi_s, r_hi_g) = REFLECT_ENDS
    cw = "deharden_south_over_north_under_tied_flange_min_cellwise_added_after_data"
    ratio = _floor2(min(refl_moves[rn][cw] for rn in ends))
    margin0 = refl_moves["none"]["deharden_range_margin_south_min_minus_north_max_per_year"]
    refl_text = (
        f"Ground-reflected light, open field like the beam and on every face — snow on the ground from a reanalysis checked "
        f"against a station (two checked; the low end takes the one with less winter snow where snow masks the ground, {s_lo} "
        f"at ≥ {z_lo * 100:g} cm, with {r_lo_s:g} over snow — the cutoff of Baker's deep-snow sample, not a measured albedo — "
        f"and {r_lo_g:g} over bare ground; the high end the one with more, {s_hi} at ≥ {z_hi * 100:g} cm, with {r_hi_s:g} — "
        f"Baker's mean the day after a snowfall — and {r_hi_g:g}) — adds {e_lo:.2f}–{e_hi:.2f}× the model's diffuse term over "
        f"the winter and moves the median shift by {min(dm):+.2f}…{max(dm):+.2f} K and the coldest hour under the flange by "
        f"{min(df):+.2f}…{max(df):+.2f} K across both ends"
        + ("" if all(mono.values()) else f" (not monotone between the ends in every cell: {[q for q, v in mono.items() if not v]})")
        + f"; on a south face the hours above {DEHARDEN_C:g} °C a winter become {hours(180, 'no_flange')} under bark and "
        f"{hours(180, 'flange')} under the tied flange (north {hours(0, 'no_flange')} and {hours(0, 'flange')}), and "
        + ("both declared readings of the azimuth axis hold at both ends. " if hold else "; ".join(broken) + ". ")
        + f"Read cell by cell instead — the pairing the floor reading already had, added after the data broke the declared "
        f"range reading — the south has at least {ratio:.2f}× the north's hours under the tied flange at either end; without "
        f"reflected light the declared reading held by {margin0:.1f} h a winter. The ground's long-wave stays at air "
        f"temperature under snow, and the open field is applied to every face (a stand edge facing the sun gives its north "
        f"face less). ")
    return refl_moves, checks, refl_text


def main() -> int:
    banner("HW.6 — the frost half: cambium under the flange vs bark without it, sky × sun × coupling, 30 ERA5 winters")
    units = brutsaert_unit_check()
    scheme_err = verify_robin()
    if scheme_err > 0.02:
        raise SystemExit(f"Robin scheme check failed: {scheme_err:.2%} off the closed form")
    print(f"  scheme check: dead-bark half-space under a convective step — ΔT within {scheme_err:.2%} of eq. 5.60 at 0/5/10 mm")
    diurnal_err = verify_diurnal()
    if diurnal_err > 0.05:
        raise SystemExit(f"diurnal check failed: cambium minimum {diurnal_err:.3f} K off the Crank–Nicolson reference")
    print(f"  diurnal check: {SUBSTEPS} implicit substeps/h hold the cambium minimum within {diurnal_err:.3f} K of 120-substep Crank–Nicolson")
    ar = areas()
    wx = load_weather()
    times = wx["time"]
    ts_check = verify_timestep(wx, ar)
    if ts_check["daily_min_err_K"] > 0.15 or ts_check["shift_err_K"] > 0.05:
        raise SystemExit(f"timestep check failed: {ts_check}")
    print(f"  timestep check (coldest 40 days): {SUBSTEPS} vs {6 * SUBSTEPS} substeps — daily minimum within "
          f"{ts_check['daily_min_err_K']:.3f} K, shift within {ts_check['shift_err_K']:.3f} K")
    print(f"  sky: Brutsaert 1.24·(e/T)^(1/7) — {units['emissivity_at_10hPa_283K']} at 10 hPa/283 K "
          f"({units['same_with_e_in_Pa']} were e in Pa: excluded)")
    bark = S78.bark_bracket()
    print(f"  ring the flange sits on Ø{ar['wound_diameter_mm']:.0f}–Ø{ar['flange_diameter_mm']:.1f}: {ar['contact_ring_mm2']:.0f} mm² · "
          f"fins: band {ar['flange_band_mm2']:.0f} mm² (×{ar['fin_ratio']['decoupled']:.2f}) · band + capsule "
          f"{ar['flange_band_mm2'] + ar['capsule_exposed_mm2']:.0f} mm² (×{ar['fin_ratio']['tied']:.2f})")
    eps = sky_emissivity(wx["t_air"], wx["t_dew"])
    winter = np.array([int(s[5:7]) in (11, 12, 1, 2, 3) for s in times])
    print(f"  clear-sky emissivity over the winter hours (Nov–Mar): median {np.median(eps[winter]):.2f}, "
          f"P5–P95 {np.percentile(eps[winter], 5):.2f}–{np.percentile(eps[winter], 95):.2f}")
    mech = mechanism(ar)
    print(f"  mechanism at {REFERENCE_HOUR['t_air_C']:.0f} °C clear, still: equilibrium − air — bark "
          f"{mech['bark']['equilibrium_minus_air_K']:+.2f} K (h_c {mech['bark']['h_c_W_m2K']:.2f}) · capsule "
          f"{mech['capsule']['equilibrium_minus_air_K']:+.2f} K (h_c {mech['capsule']['h_c_W_m2K']:.2f}); tied conductance "
          f"{mech['tied_over_bark_conductance']:.1f}× bark's")

    cols, labels = column_table(ar)
    runs = []
    cut = np.arange(len(times)) >= SPIN_UP_DAYS * 24
    for side, b in (("thin", bark["thin_mm"]), ("thick", bark["thick_mm"])):
        cam, _ = simulate(S78.layers(b), b + S58.T_PHLOEM, wx, cols)
        m = daily_minima(cam, times)
        for name, _, _ in REGIMES:
            for k in WIND_K:
                jb = labels.index((name, "bark", k))
                for cp in COUPLINGS:
                    jf = labels.index((name, cp, k))
                    runs.append({
                        "regime": name, "coupling": cp, "wind_k": k, "bark_side": side, "bark_mm": b,
                        "shift_K": shift_stats(m, jb, jf),
                        "cambium_min_C_model_lower_bound": {"no_flange": round(float(cam[cut, jb].min()), 2),
                                                            "flange": round(float(cam[cut, jf].min()), 2)},
                        "hours_below": {f"{x:g}": {"no_flange": int(np.count_nonzero(cam[cut, jb] < x)),
                                                   "flange": int(np.count_nonzero(cam[cut, jf] < x))} for x in ISOTHERMS_C},
                    })
        print(f"  {side:<5s} bark {b:5.2f} mm done")

    regimes = {name: summarise_regime(runs, name) for name, _, _ in REGIMES}
    print("  shift of the daily cambium minimum on frost days (+ = colder under the flange): median range · P95 max · max, K")
    for name, _, _ in REGIMES:
        r = regimes[name]
        print(f"    {name:<21s} " + "  ·  ".join(
            f"{cp} {r[cp]['median_K_range'][0]:+.2f}…{r[cp]['median_K_range'][1]:+.2f} · {r[cp]['p95_K_max']:+.2f} · {r[cp]['max_K']:+.2f}"
            for cp in COUPLINGS))

    sens = {}
    thin = bark["thin_mm"]
    s_cols, _ = column_table(ar, REGIMES[:1], WIND_K[:1])
    base = next(r for r in runs if (r["regime"], r["coupling"], r["wind_k"], r["bark_side"]) == ("clear_no_sun", "tied", 0.0, "thin"))
    for name, over in SENSITIVITY:
        cam_s, _ = simulate(stack_with(thin, over.get("sapwood_mm")), thin + S58.T_PHLOEM, wx, s_cols,
                            trunk_l_m=over.get("trunk_l_m", TRUNK_L_M), cap_hc_as_bark=over.get("cap_hc_as_bark", False))
        m_s = daily_minima(cam_s, times)
        sens[name] = {"override": over, "decoupled": shift_stats(m_s, 0, 1), "tied": shift_stats(m_s, 0, 2)}
        print(f"  sensitivity {name}: tied shift median {sens[name]['tied']['median']:+.2f} · P95 "
              f"{sens[name]['tied']['p95']:+.2f} · max {sens[name]['tied']['max']:+.2f} K "
              f"(base {base['shift_K']['median']:+.2f} · {base['shift_K']['p95']:+.2f} · {base['shift_K']['max']:+.2f})")

    c_cols, c_labels = column_table(ar, CLOUD_REGIMES)
    cloud_runs = []
    winter_h = np.array([int(s[5:7]) in WINTER_MONTHS for s in times])
    cloud_climate = {"winter_hours_median": round(float(np.median(wx["cloud"][winter_h])), 3),
                     "winter_share_above_0.8": round(float(np.mean(wx["cloud"][winter_h] > 0.8)), 3),
                     "winter_share_below_0.2": round(float(np.mean(wx["cloud"][winter_h] < 0.2)), 3)}
    for side, b in (("thin", bark["thin_mm"]), ("thick", bark["thick_mm"])):
        cam, _ = simulate(S78.layers(b), b + S58.T_PHLOEM, wx, c_cols)
        m = daily_minima(cam, times)
        month = np.array([int(times[(SPIN_UP_DAYS + d) * 24][5:7]) for d in range(m.shape[0])])
        for name, _, _ in CLOUD_REGIMES:
            for k in WIND_K:
                jb = c_labels.index((name, "bark", k))
                frost = m[:, jb] < FROST_DAY_C
                cold = m[:, jb] < COLD_DAY_C
                for cp in COUPLINGS:
                    s = m[:, jb] - m[:, c_labels.index((name, cp, k))]
                    by_month = {str(mo): {"frost_days": int(np.count_nonzero(frost & (month == mo))),
                                          "median": round(float(np.median(s[frost & (month == mo)])), 2),
                                          "colder_share": round(float(np.mean(s[frost & (month == mo)] > COLDER_BAND_K)), 3)}
                                for mo in range(1, 13) if np.any(frost & (month == mo))}   # every month with a frost day
                    cloud_runs.append({"regime": name, "coupling": cp, "wind_k": k, "bark_side": side, "bark_mm": b,
                                       "shift_K": shift_stats(m, jb, c_labels.index((name, cp, k))),
                                       "colder_share": round(float(np.mean(s[frost] > COLDER_BAND_K)), 3),
                                       "warmer_share": round(float(np.mean(s[frost] < -COLDER_BAND_K)), 3),
                                       "cold_days": {"days": int(np.count_nonzero(cold)),
                                                     "median": round(float(np.median(s[cold])), 2) if np.any(cold) else None,
                                                     "colder_share": round(float(np.mean(s[cold] > COLDER_BAND_K)), 3)
                                                     if np.any(cold) else None},
                                       "by_month": by_month})
        print(f"  {side:<5s} bark {b:5.2f} mm done (real cloud)")
    cloud_regimes = {name: summarise_regime(cloud_runs, name) for name, _, _ in CLOUD_REGIMES}
    for name, _, _ in CLOUD_REGIMES:
        for cp in COUPLINGS:
            rows = [r for r in cloud_runs if r["regime"] == name and r["coupling"] == cp]
            sh = [r["colder_share"] for r in rows]
            cloud_regimes[name][cp]["colder_share_range"] = [min(sh), max(sh)]
            cd = [r["cold_days"] for r in rows if r["cold_days"]["days"]]
            cloud_regimes[name][cp]["cold_days"] = {
                "days_range": [min(c["days"] for c in cd), max(c["days"] for c in cd)],
                "median_K_range": [min(c["median"] for c in cd), max(c["median"] for c in cd)],
                "colder_share_range": [min(c["colder_share"] for c in cd), max(c["colder_share"] for c in cd)]} if cd else None
    print(f"  real cloud (ERA5, winter median cover {cloud_climate['winter_hours_median']:.2f}; "
          f"> 0.8 in {cloud_climate['winter_share_above_0.8']:.0%} of winter hours, < 0.2 in "
          f"{cloud_climate['winter_share_below_0.2']:.0%}) — median range · P95 max · max, K · share of frost days colder:")
    for name, _, _ in CLOUD_REGIMES:
        r = cloud_regimes[name]
        print(f"    {name:<25s} " + "  ·  ".join(
            f"{cp} {r[cp]['median_K_range'][0]:+.2f}…{r[cp]['median_K_range'][1]:+.2f} · {r[cp]['p95_K_max']:+.2f} · "
            f"{r[cp]['max_K']:+.2f} · {r[cp]['colder_share_range'][0]:.0%}–{r[cp]['colder_share_range'][1]:.0%}"
            for cp in COUPLINGS))
        cdt = r["tied"]["cold_days"]
        if cdt:
            print(f"      cold days (bark < {COLD_DAY_C:g} °C, {cdt['days_range'][0]}–{cdt['days_range'][1]} d), tied: median "
                  f"{cdt['median_K_range'][0]:+.2f}…{cdt['median_K_range'][1]:+.2f} K · colder "
                  f"{cdt['colder_share_range'][0]:.0%}–{cdt['colder_share_range'][1]:.0%}")
    for name in ("cloud_linear_no_sun", "cloud_b82_diffuse_sun"):
        row = next(r for r in cloud_runs if (r["regime"], r["coupling"], r["wind_k"], r["bark_side"]) == (name, "tied", 0.0, "thin"))
        print(f"    by month, {name}, tied, still, thin bark: " + " · ".join(
            f"{mo}: {v['median']:+.2f} K ({v['colder_share']:.0%} colder, {v['frost_days']} d)" for mo, v in row["by_month"].items()))

    st = site()
    sun_geo = verify_sun_geometry(st, times)
    clock = verify_sun_clock(times, wx["dni"], st)
    sun = sun_enu(times, st)
    geom = face_factors(sun)
    ghi = wx["dni"] * np.maximum(sun[2], 0.0).mean(axis=1) + wx["dif"]
    del sun
    win_all = np.array([int(x[5:7]) in WINTER_MONTHS for x in times])
    ghi_ratio = float(ghi[win_all].sum() / wx["dif"][win_all].sum())
    snow = load_snow(times)
    snow_chk = snow_check(times, snow)
    refl = reflected_rows(snow, ghi)
    day_w = win_all & (ghi > 0.0)
    end_shares = check_reflect_ends(snow, day_w)
    reflected = {
        "method": "isotropic ground reflection on a vertical face, ρ·GHI through the ground's view share (1 − F) with each "
                  "column's own absorptance; ρ switched by a reanalysis's snow depth; open field (GHI = ERA5 DNI on the "
                  "horizontal plus ERA5 diffuse), so it rides with the beam only",
        "winter_ghi_over_diffuse": round(ghi_ratio, 3),
        "south_beam_over_model_diffuse": round(float((wx["dni"] * geom[0][AZIMUTHS_DEG.index(180)])[win_all].sum()
                                                     / (SKY_VIEW * wx["dif"][win_all].sum())), 2),
        "albedo_sources": {"snow": "Baker, Ruschy & Wall 1990, J. Appl. Meteor. 29:179, doi:10.1175/1520-0450(1990)029<0179:TADOPS>2.0.CO;2 — "
                                   "≈ 0.80 the mean the day after a snowfall; 0.50 the cutoff their deep-snow (≥ 10.2 cm) decay sample is "
                                   "selected by — not a measured albedo",
                           "ground": "Baker & Ruschy 1988, J. Appl. Meteor. 27:244, doi:10.1175/1520-0450(1988)027<0244:HAVASP>2.0.CO;2, "
                                     "Table 2 medians — April 0.18, October 0.24"},
        "snow_sources": {name: {"file": SNOW_FILES[name].name, "grid_point": s["grid_point"]} for name, s in snow.items()},
        "snow_check": snow_chk,
        "end_source_check_winter_daylight_snow_share": end_shares,
        "ends": {name: {"snow_source": src, "snow_depth_m_at_least": depth, "albedo_snow": rho_s, "albedo_ground": rho_g,
                        "winter_daylight_hours_with_snow_share": round(float(np.mean(snow[src]["depth_m"][day_w] >= depth - 1e-9)), 3),
                        "reflected_on_vertical_over_model_diffuse": round(float((1.0 - SKY_VIEW) * refl[REFLECT_NAMES.index(name)][win_all].sum()
                                                                                / (SKY_VIEW * wx["dif"][win_all].sum())), 3)}
                 for name, src, depth, rho_s, rho_g in REFLECT_ENDS}}
    proj = beam_projection(ar)
    ts_beam = verify_timestep_beam(wx, ar, geom, proj, refl)
    for tsw in ts_beam.values():
        if (tsw["daily_min_err_K"] > 0.15 or tsw["shift_err_K"] > 0.05 or tsw["daily_max_err_K"] > 0.2
                or any(abs(tsw["hours_above_deharden"][c] - r) > max(2, 0.02 * r) for c, r in tsw["hours_above_deharden_reference"].items())):
            raise SystemExit(f"beam timestep check failed: {ts_beam}")
    if not any(v for c, v in ts_beam["warmest_winter_hour"]["hours_above_deharden"].items() if not c.endswith("/bark")):
        raise SystemExit("the warm window put no flange hour above DEHARDEN_C — its hour gate would be vacuous")
    ts_series = verify_timestep_series(wx, ar, geom, proj, refl)
    if any(v["shift_err_K_max"] > COLDER_BAND_K or v["floor_err_K_max"] > SERIES_FLOOR_TOL_K or not v["hours_within_tolerance"]
           for v in ts_series.values()):
        raise SystemExit(f"series timestep check failed (shift past COLDER_BAND_K, floor past SERIES_FLOOR_TOL_K or hours past "
                         f"SERIES_HOURS_TOL somewhere in 30 years): {ts_series}")
    print("  timestep over the whole series (thin bark, still air; Richardson 1.5·|Δ| against 3× the substeps): " + " · ".join(
        f"{k}: shift ≤ {v['shift_err_K_max']:.3f} K, class flips {v['class_flip_share']:.2%} of {v['frost_day_pairs']} frost-day pairs, "
        f"floor ≤ {v['floor_err_K_max']:.3f} K, hours above {DEHARDEN_C:g} °C ≤ {max(v['hours_above_deharden_err'].values()):.0f} "
        f"of {max(v['hours_above_deharden'].values())}"
        for k, v in ts_series.items()))
    print(f"  sun: NOAA GML series — declination {sun_geo['declination_deg'][0]:+.2f}…{sun_geo['declination_deg'][1]:+.2f}°, "
          f"equation of time {sun_geo['equation_of_time_min'][0]:+.2f}…{sun_geo['equation_of_time_min'][1]:+.2f} min, June noon "
          f"{sun_geo['june_noon_altitude_deg']:.2f}° (expected {sun_geo['june_noon_altitude_expected_deg']:.2f}°)")
    print("  sun clock: DNI share in hours the sun never clears the horizon — " + " · ".join(
        f"{k} h {v:.3%}" for k, v in clock.items()))
    print("  snow check against GHCN Lubny (winter days, snow share · agreement · κ): " + " · ".join(
        f"≥ {z} m: station {row['station_snow_share']:.2f}, " + ", ".join(
            f"{n} {row[n]['snow_share']:.2f}/{row[n]['agreement']:.2f}/{row[n]['kappa']:.2f}" for n in snow)
        for z, row in snow_chk["depths_m"].items()))
    print(f"  ground-reflected light: winter GHI/diffuse {reflected['winter_ghi_over_diffuse']:.2f} → on a vertical face "
          + " · ".join(f"{n}: {e['reflected_on_vertical_over_model_diffuse']:.2f}× the model's diffuse "
                       f"(snow in {e['winter_daylight_hours_with_snow_share']:.0%} of winter daylight hours)"
                       for n, e in reflected["ends"].items())
          + f" (south-face beam {reflected['south_beam_over_model_diffuse']:.2f}×)")
    for name, tsw in ts_beam.items():
        print(f"  beam timestep check, {name} ({tsw['window_start'][:10]}, north and south faces): daily minimum within "
              f"{tsw['daily_min_err_K']:.3f} K, maximum {tsw['daily_max_err_K']:.3f} K, shift {tsw['shift_err_K']:.3f} K; "
              f"hours above {DEHARDEN_C:g} °C {tsw['hours_above_deharden']} vs {tsw['hours_above_deharden_reference']}")
    combos = [(form, rn) for rn in REFLECT_NAMES for form in BEAM_FORMS]
    tables = [beam_column_table(ar, form, proj, refl=rn) for form, rn in combos]
    b_cols = {key: np.concatenate([t[0][key] for t in tables]) for key in tables[0][0]}
    b_labels = [(form, rn, *lab) for (form, rn), t in zip(combos, tables, strict=True) for lab in t[1]]
    month_h = np.array([int(x[5:7]) for x in times])
    win_h = np.isin(month_h, WINTER_MONTHS) & cut
    mo_w = month_h[win_h]
    n_years = len({x[:4] for x in times})
    beam_runs = []
    for side, b in (("thin", bark["thin_mm"]), ("thick", bark["thick_mm"])):
        cam, _ = simulate(S78.layers(b), b + S58.T_PHLOEM, wx, b_cols, geom=geom, refl=refl)
        m = daily_minima(cam, times)
        cw = cam[win_h]
        for form, rn in combos:
            for a in AZIMUTHS_DEG:
                for k in WIND_K:
                    jb = b_labels.index((form, rn, a, "bark", k))
                    frost, cold = m[:, jb] < FROST_DAY_C, m[:, jb] < COLD_DAY_C
                    warm_b = cw[:, jb] > DEHARDEN_C
                    for cp in COUPLINGS:
                        jf = b_labels.index((form, rn, a, cp, k))
                        s = m[:, jb] - m[:, jf]
                        warm_f = cw[:, jf] > DEHARDEN_C
                        beam_runs.append({
                            "reflect": rn,
                            "form": form, "azimuth_deg": a, "coupling": cp, "wind_k": k, "bark_side": side, "bark_mm": b,
                            "shift_K": shift_stats(m, jb, jf),
                            "colder_share": round(float(np.mean(s[frost] > COLDER_BAND_K)), 3),
                            "warmer_share": round(float(np.mean(s[frost] < -COLDER_BAND_K)), 3),
                            "cold_days": {"days": int(np.count_nonzero(cold)),
                                          "median": round(float(np.median(s[cold])), 2) if np.any(cold) else None,
                                          "colder_share": round(float(np.mean(s[cold] > COLDER_BAND_K)), 3)
                                          if np.any(cold) else None},
                            "cambium_min_C": {"no_flange": round(float(cam[cut, jb].min()), 2),
                                              "flange": round(float(cam[cut, jf].min()), 2)},
                            "winter_hours_above_deharden": {"no_flange": int(warm_b.sum()), "flange": int(warm_f.sum())},
                            "winter_hours_above_deharden_by_month": {
                                str(mo): {"no_flange": int((warm_b & (mo_w == mo)).sum()), "flange": int((warm_f & (mo_w == mo)).sum())}
                                for mo in WINTER_MONTHS},
                            "winter_cambium_max_C": {"no_flange": round(float(cw[:, jb].max()), 2),
                                                     "flange": round(float(cw[:, jf].max()), 2)},
                        })
        del cam, cw
        print(f"  {side:<5s} bark {b:5.2f} mm done (beam by azimuth, ground reflection {', '.join(REFLECT_NAMES)})")
    runs_by = {rn: [{k: v for k, v in r.items() if k != "reflect"} for r in beam_runs if r["reflect"] == rn] for rn in REFLECT_NAMES}
    summ = {rn: beam_summary(runs_by[rn], n_years) for rn in REFLECT_NAMES}
    beam, floor_sn, month_exceptions = summ["none"]["by_azimuth"], summ["none"]["floor_sn"], summ["none"]["month_exceptions"]
    for rn in REFLECT_NAMES:
        print(f"  beam by azimuth, ground reflection {rn} (open-field DNI, both cloud forms with diffuse): tied median range · "
              f"colder share · hours above {DEHARDEN_C:g} °C per winter, bark | tied | decoupled · warmest winter cambium, bark | tied")
        for a in AZIMUTHS_DEG:
            t_, d_ = summ[rn]["by_azimuth"][str(a)]["tied"], summ[rn]["by_azimuth"][str(a)]["decoupled"]
            hb, ht, hd = (t_["winter_hours_above_deharden_per_year"]["no_flange"], t_["winter_hours_above_deharden_per_year"]["flange"],
                          d_["winter_hours_above_deharden_per_year"]["flange"])
            print(f"    {a:3d}°  {t_['median_K_range'][0]:+.2f}…{t_['median_K_range'][1]:+.2f} K · "
                  f"{t_['colder_share_range'][0]:.0%}–{t_['colder_share_range'][1]:.0%} · {hb[0]:.0f}–{hb[1]:.0f} | {ht[0]:.0f}–{ht[1]:.0f} | "
                  f"{hd[0]:.0f}–{hd[1]:.0f} h · {t_['winter_cambium_max_C']['no_flange']:.1f} | {t_['winter_cambium_max_C']['flange']:.1f} °C")

    def word(lo, hi):
        return "warmer" if hi < 0.0 else ("colder" if lo > 0.0 else "either way")
    meds = {name: regimes[name]["tied"]["median_K_range"] for name, _, _ in REGIMES}

    def share(name):
        lo, hi = cloud_regimes[name]["tied"]["colder_share_range"]
        return f"{lo:.0%}–{hi:.0%}"

    def med(name):
        lo, hi = cloud_regimes[name]["tied"]["median_K_range"]
        return f"{lo:+.1f}…{hi:+.1f} K"

    def cold(name):
        c = cloud_regimes[name]["tied"]["cold_days"]
        return "no cold days" if not c else f"{c['colder_share_range'][0]:.0%}–{c['colder_share_range'][1]:.0%}"
    upper = max((regimes[n]["tied"]["max_K"], n) for n, _, _ in REGIMES)
    diffuse = {(r["regime"], r["coupling"], r["wind_k"], r["bark_side"]): r["shift_K"]["median"] for r in cloud_runs}
    beam_vs_diffuse = [r["shift_K"]["median"] - diffuse[(f"cloud_{r['form']}_diffuse_sun", r["coupling"], r["wind_k"], r["bark_side"])]
                       for r in runs_by["none"]]
    fin_sheds = summ["none"]["fin_sheds"]

    refl_moves, refl_checks, refl_text = reflection_readings(runs_by, summ, reflected)
    ends = REFLECT_NAMES[1:]
    exc_az = sorted({x["azimuth_deg"] for x in month_exceptions})
    exc_mo = sorted({int(x["month"]) for x in month_exceptions})
    bn, bs = beam["0"]["tied"], beam["180"]["tied"]
    hn, hs = bn["winter_hours_above_deharden_per_year"], bs["winter_hours_above_deharden_per_year"]
    beam_text = (
        f"Beam sun on the trunk face — swept over its azimuth with open-field ERA5 DNI, the upper end of beam — "
        f"{'only deepens' if min(beam_vs_diffuse) >= -0.005 else 'moves'} the shift against the diffuse-only weighing "
        f"(the median by {min(beam_vs_diffuse):+.2f}…{max(beam_vs_diffuse):+.2f} K): tied "
        f"{bn['median_K_range'][0]:+.1f}…{bn['median_K_range'][1]:+.1f} K on a north face, "
        f"{bs['median_K_range'][0]:+.1f}…{bs['median_K_range'][1]:+.1f} K on a south one, colder there on "
        f"{bs['colder_share_range'][0]:.0%}–{bs['colder_share_range'][1]:.0%} of frost days — the bark banks the beam the "
        f"fin sheds. In absolute terms the beam still warms the spot: its coldest hour is "
        f"{'warmer on a south face than on a north one in every cell' if floor_sn['tied'][0] > 0 else 'not warmer on a south face in every cell'}"
        f" (tied {floor_sn['tied'][0]:+.1f}…{floor_sn['tied'][1]:+.1f} K). The same beam lifts the cambium above ≈ {DEHARDEN_C:g} °C, "
        f"the exposure Sakai names as what dehardens, "
        f"{'under bark more often than under the flange in every winter total' if fin_sheds else 'under the flange more often than under bark in some winter totals'}"
        + (f" (not in every month: in month(s) {exc_mo} of faces {exc_az} the flange has a few more)" if month_exceptions else "")
        + f": on a south face {hs['no_flange'][0]:.0f}–{hs['no_flange'][1]:.0f} hours a winter without it against "
        f"{hs['flange'][0]:.0f}–{hs['flange'][1]:.0f} under the tied flange (north {hn['no_flange'][0]:.0f}–{hn['no_flange'][1]:.0f} "
        f"against {hn['flange'][0]:.0f}–{hn['flange'][1]:.0f}). So this axis does not choose an azimuth by itself: the absolute "
        f"frost floor under the flange "
        f"{'favours the south' if refl_moves['none']['floor_south_warmer_every_cell'] else 'does not favour the south in every cell'}, "
        f"its hours of dehardening "
        f"{'the north' if refl_moves['none']['deharden_fewer_north_than_south_under_tied_flange'] else 'overlap between the north and the south'}, "
        f"and only a measure of how much the node perturbs the cambium points one way; weighing them needs a dose-response no "
        f"primary gives. " + refl_text)
    text = (f"The sign of the shift depends on the sky and the sun. Clear sky, no sun — the end most favourable to the "
            f"flange: the tied median is {meds['clear_no_sun'][0]:+.1f}…{meds['clear_no_sun'][1]:+.1f} K "
            f"({word(*meds['clear_no_sun'])} under the flange), because a long-wave deficit depresses flat bark "
            f"({mech['bark']['equilibrium_minus_air_K']:+.1f} K at its equilibrium) more than the capsule "
            f"({mech['capsule']['equilibrium_minus_air_K']:+.1f} K) — with the capsule's h_c set to bark's the tied median "
            f"turns {sens['capsule_h_c_as_bark']['tied']['median']:+.1f} K. Overcast, no sun: "
            f"{meds['overcast_no_sun'][0]:+.1f}…{meds['overcast_no_sun'][1]:+.1f} K ({word(*meds['overcast_no_sun'])}) — "
            f"the fin's conductance to the air ({mech['tied_over_bark_conductance']:.0f}× bark's) makes the ring follow the "
            f"air's daily fall. Diffuse sun on both raises it again (bark banks the gain, the fin sheds it): clear "
            f"{meds['clear_diffuse_sun'][0]:+.1f}…{meds['clear_diffuse_sun'][1]:+.1f} K, overcast "
            f"{meds['overcast_diffuse_sun'][0]:+.1f}…{meds['overcast_diffuse_sun'][1]:+.1f} K. The worst day of the four ends "
            f"is {upper[0]:+.1f} K colder ({upper[1]}, tied). Decoupled — the flange's band alone, "
            f"{ar['fin_ratio']['decoupled']:.2f}× the ring — moves the same way with smaller medians. Weighed by the "
            f"site's real cloud (ERA5: winter median cover {cloud_climate['winter_hours_median']:.2f}, above 0.8 in "
            f"{cloud_climate['winter_share_above_0.8']:.0%} of winter hours), the answer turns on how cover becomes sky "
            f"radiation, and the one measurement in hand (a mountain station, by day) does not settle it for a valley cell "
            f"at night: if full cover radiates as a black body at air temperature (the two ends mixed by the cover), the "
            f"tied flange is colder on {share('cloud_linear_no_sun')} of frost days without sun and "
            f"{share('cloud_linear_diffuse_sun')} with diffuse sun (median {med('cloud_linear_diffuse_sun')}); with "
            f"Brutsaert 1982's factor at its original C {B82_C}, which leaves a fully covered winter sky short of a black "
            f"body, on {share('cloud_b82_no_sun')} and {share('cloud_b82_diffuse_sun')}. On the cold days (bark below "
            f"{COLD_DAY_C:g} °C), the tail an injury threshold sits in: {cold('cloud_linear_diffuse_sun')} colder under the "
            f"first, {cold('cloud_b82_no_sun')} under the second without sun. " + beam_text + "The real "
            "coupling is not in the tree; 1D inflates the shift in both signs. The regional injury threshold and its "
            "corrections live in canon (docs/01_04 §3.1): it sits NEAR this model's floor, not far below it.")
    print(f"\n  → {text}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "question": "on winter days, does the Ti flange with its capsule make the cambium under the Ø15–Ø29.8 ring colder "
                    "than under bark without it, and how does the answer move with the sky and the sun?",
        "method": "1D implicit column on 78's grid (properties of 58) with a surface energy balance — convection, long-wave "
                  "exchange with a clear (Brutsaert 1975) or overcast sky and air-temperature surroundings at sky view 0.5, "
                  "and optionally ERA5 diffuse sun — over 30 ERA5 years; under the flange the balance acts through a fin "
                  "of A_fin/A_contact",
        "inputs": {"wind_k": list(WIND_K), "couplings": list(COUPLINGS),
                   "regimes": [{"name": n, "overcast": o, "diffuse_sun": s} for n, o, s in REGIMES],
                   "epsilon": EPSILON, "sky_view": SKY_VIEW, "alpha_bark": ALPHA_BARK, "alpha_fin": ALPHA_FIN,
                   "brutsaert": {"a": BRUTSAERT_A, "exponent": "1/7", "units": "e_a hPa, T_a K",
                                 "coefficient_read_via": "Crawford & Duchon 1999, J. Appl. Meteor. 38:474 (open text)",
                                 "unit_check": units},
                   "trunk_height_for_natural_convection_m": TRUNK_L_M, "trunk_diameter_m": DBH_MIN_CM / 100.0,
                   "sapwood_depth_mm": S78.SAPWOOD_DEPTH_MM, "dx_mm": DX_MM, "substeps_per_hour": SUBSTEPS,
                   "phloem_mm": S58.T_PHLOEM, "spin_up_days": SPIN_UP_DAYS, "frost_day_below_C": FROST_DAY_C,
                   "isotherms_C": list(ISOTHERMS_C)},
        "areas": ar,
        "bark": bark,
        "clear_sky_emissivity_winter": {"median": round(float(np.median(eps[winter])), 3),
                                        "p5": round(float(np.percentile(eps[winter], 5)), 3),
                                        "p95": round(float(np.percentile(eps[winter], 95)), 3)},
        "scheme_check_rel_error": round(scheme_err, 5),
        "diurnal_check_cambium_min_error_K": round(diurnal_err, 4),
        "timestep_check": ts_check,
        "mechanism": mech,
        "runs": runs,
        "regimes": regimes,
        "real_cloud": {"source": "ERA5 total cloud cover, data/era5_cherkasy/hourly_cloud_1991_2020.csv.gz",
                       "forms": {"linear": "ours — the two sky ends mixed by the cover",
                                 "b82": f"Brutsaert 1982 as printed in Herrero & Polo 2012 eq. 8, C = {B82_C}"},
                       "winter_months": list(WINTER_MONTHS), "climate": cloud_climate,
                       "regimes": cloud_regimes, "runs": cloud_runs},
        "beam_sun": {"method": "ERA5 DNI on a vertical trunk face at each azimuth (outward normal, clockwise from north) through "
                               "the sun's position by NOAA GML's General Solar Position Calculations, averaged over the hour "
                               "each radiation value averages; the stem shades the face when the sun is behind it; open "
                               "field — no crown, neighbour trunk or horizon; with each real-cloud form and its diffuse; the "
                               "records here carry no ground-reflected light, its two ends are in `ground_reflected`",
                     "site": st, "azimuths_deg": list(AZIMUTHS_DEG), "forms": list(BEAM_FORMS),
                     "sun_subsamples_per_hour": SUN_SUBSAMPLES, "silhouette_per_fin_area_cos_sin": proj,
                     "sun_geometry_check": sun_geo, "sun_clock_check_dni_share_in_sun_down_hours": clock,
                     "timestep_check": ts_beam, "timestep_check_series": ts_series, "deharden_C": DEHARDEN_C,
                     "ground_reflected": {**reflected, "readings": refl_moves, "cell_checks": refl_checks,
                                          "by_azimuth": {rn: summ[rn]["by_azimuth"] for rn in ends},
                                          "coldest_hour_under_flange_south_minus_north_K": {rn: summ[rn]["floor_sn"] for rn in ends},
                                          "flange_never_above_bark_in_hours": {rn: summ[rn]["fin_sheds"] for rn in ends},
                                          "month_cells_flange_above_bark": {rn: summ[rn]["month_exceptions"] for rn in ends},
                                          "runs": [r for r in beam_runs if r["reflect"] != "none"]},
                     "deharden_reading": "Sakai 1968, Contr. Inst. Low Temp. Sci. B15:1, via canon 01_04 §3.1 — exposure "
                                         "above it is the CAUSE of winter dehardening; hours above it are counted, never "
                                         "priced as a dose",
                     "winter_months": list(WINTER_MONTHS), "years": n_years,
                     "median_shift_minus_diffuse_only_K": [round(min(beam_vs_diffuse), 2), round(max(beam_vs_diffuse), 2)],
                     "flange_never_above_bark_in_hours": fin_sheds,
                     "coldest_hour_under_flange_south_minus_north_K": floor_sn,
                     "month_cells_flange_above_bark": month_exceptions,
                     "by_azimuth": beam, "runs": runs_by["none"]},
        "sensitivity_thin_bark_still_air_clear_no_sun": sens,
        "verdict": {"tied_median_K_range_by_regime": meds, "tied_max_K": upper[0], "tied_max_regime": upper[1],
                    "text": text},
        "ceilings": ["beam sun is swept over the face's azimuth with open-field DNI — the upper end of BEAM (no crown, "
                     "neighbour trunk or horizon; the mounting azimuth is a decision, 00_07 HW.6); ground-reflected light "
                     "rides with the beam only, at two ends whose snow comes from reanalyses other than ERA5 (on our channel "
                     "ERA5 carries no snow depth) checked against a station ~100 km away, and whose albedo was measured at "
                     "St. Paul, Minnesota over an open agricultural plot — not under a crown, on a forest floor or at the "
                     "site; the ground in the long-wave view stays at air temperature under snow too (a clear-night snow "
                     "surface below the air — an extra loss — is not carried, so the floor's gain is the reflected term "
                     "alone), and the open field is applied to every face (at a stand edge facing the sun the north face "
                     "looks into the stand); the diffuse-only weighing carries none, so it stays the closed-stand lower end; frost days are defined "
                     "by the bark of the same face, so nights the spot freezes and the sunlit bark does not are left out; "
                     "real cloud (ERA5) is weighed, through two long-wave forms that disagree under full cover — "
                     "which one holds at the site decides the sign, and neither form's primary was read",
                     "1D and zero contact resistance inflate the shift in both signs; the tied end is the upper end of the "
                     "coupling axis only, and the two coupling ends bracket the median, not the tail",
                     "the radome↔flange coupling is not measured — decoupled and tied are its two ends",
                     "F 0.5, ε 0.90, α_bark 0.80 and the trunk's convection correlation are ours; α_fin is the radome's "
                     "specified ceiling and a lighter finish enlarges the shift",
                     "no injury verdict — no frost-hardiness threshold for pine cambium in the tree",
                     "absolute minima are the model's lower bound (weeks of sunless clear sky), not a forecast",
                     "snow or rime on the bark or the radome is not modelled",
                     "the lump here is fed by the bark — it is not the capsule temperature 71 gives the EDLC floor"],
    }, ensure_ascii=False, indent=2) + "\n")
    print(f"  cache → {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
