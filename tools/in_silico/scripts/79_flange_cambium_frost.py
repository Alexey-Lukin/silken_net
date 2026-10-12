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
    radome's specified ceiling α ≤ 0.5 (02_01 §5.2), applied to the band as well. Beam on a sunlit trunk face is not
    computed: it depends on the azimuth.
  • F = 0.5 and ε = 0.90 for bark and capsule alike (`71`'s, both ours).
Radiation is linearised around each column's previous surface temperature and h_c lagged one substep. Only the
surface's diagonal entry differs between columns and substeps, so one banded factor per bark side serves every
column through a Sherman–Morrison correction (`march`). Time stepping is fully IMPLICIT, not `78`'s Crank–Nicolson:
with a balance on the surface half-cell its Fourier number is ~10³ per substep, where Crank–Nicolson is not
L-stable and rings — measured 11.8 % off the closed form 6 h after a step. Three runtime gates: the step against
that closed form (`verify_robin`), a diurnal wave against a 120-substep Crank–Nicolson reference (`verify_diurnal`),
and the substep count against six times as many on the coldest real-weather window (`verify_timestep`).

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
not a dose (the same ceiling as `58`'s gate); beam sun (it needs the mounting azimuth) and which long-wave form of
cloud holds at the site (the real-cloud block weighs the ends by ERA5 cover through two forms that disagree under
full cover); the real radome↔flange coupling (bayonet rim, O-ring and cavity air — not measured); snow or rime; a forecast
of absolute minima — a run of weeks of sunless clear sky is the model's lower bound, below any ERA5 air hour; the
capsule temperature for the EDLC floor of 00_07 HW.37 (this lump is fed by the bark, `71`'s is not).

Run:  python tools/in_silico/scripts/79_flange_cambium_frost.py      # a few minutes (30 years hourly, 48 columns)
"""
from __future__ import annotations

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

SI_DESCRIPTION = "Cambium temperature under the anchor's titanium flange on winter days, against bark without it, over thirty years of hourly weather, bracketed by sky, sun and coupling (1D)."  # its row in the paper SI (72): English, no repo jargon

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
SUBSTEPS = 4                   # implicit substeps per hour — `verify_timestep` holds it against 6× as many
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
COLD_DAY_C = -10.0             # «cold days»: bark without the flange below this — the tail an injury threshold sits in
B82_C = 0.22
CLOUD_REGIMES = (("cloud_linear_no_sun", "linear", False), ("cloud_linear_diffuse_sun", "linear", True),
                 ("cloud_b82_no_sun", "b82", False), ("cloud_b82_diffuse_sun", "b82", True))
SKY_CODE = {"clear": 0, "overcast": 1, "linear": 2, "b82": 3}
CLOUD_FILE = REPO_ROOT / "tools/in_silico/data/era5_cherkasy/hourly_cloud_1991_2020.csv.gz"
WINTER_MONTHS = (11, 12, 1, 2, 3)


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
    return {"time": h["time"], "t_air": h["t_air"], "u10": h["u10"], "dif": h["dif"], "t_dew": hd["td"],
            "cloud": load_cloud(h["time"])}


def coefficients(t_s, t_air, t_sky4_clear, u, cols, dif, d_dome, trunk_l_m=TRUNK_L_M, cap_hc_as_bark=False, cloud=0.0):
    """Every column at once: H (W/m²K per area of bark under the column) and the sink temperature of the balance
    linearised around the current surface temperature t_s."""
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
    q_sun = cols["alpha"] * SKY_VIEW * dif               # absorbed diffuse, W per m² of exposed surface
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


def simulate(stack, probe_mm, wx, cols, substeps=SUBSTEPS, trunk_l_m=TRUNK_L_M, cap_hc_as_bark=False):
    """Every column of one bark side marches together; returns the cambium series (hours × columns) and the surface."""
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
        for s in range(substeps):
            ta = t0 + (t1 - t0) * (s + 0.5) / substeps
            h_eff, t_sink = coefficients(t[0], ta, t_sky4, cols["wind_k"] * wx["u10"][hr], cols, wx["dif"][hr],
                                         d_dome, trunk_l_m, cap_hc_as_bark, wx["cloud"][hr] if "cloud" in wx else 0.0)
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
            f"first, {cold('cloud_b82_no_sun')} under the second without sun. Beam sun on a trunk face and the real "
            f"coupling are not in the tree; 1D inflates the shift in both signs. The regional injury threshold and its "
            f"corrections live in canon (docs/01_04 §3.1): it sits NEAR this model's floor, not far below it.")
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
        "sensitivity_thin_bark_still_air_clear_no_sun": sens,
        "verdict": {"tied_median_K_range_by_regime": meds, "tied_max_K": upper[0], "tied_max_regime": upper[1],
                    "text": text},
        "ceilings": ["the sun is bracketed by its ends — beam sun on a trunk face is not computed (it needs the mounting "
                     "azimuth); real cloud (ERA5) is weighed, through two long-wave forms that disagree under full cover — "
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
