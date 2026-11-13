#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""119 — what the rising bark passes on the RADOME, in what order, and what each consumer there stands to lose
(00_07 HW.54, the leg «кора накриває купол усередині життя вузла»; closed forms and `107`'s exact series, no mesh).

WHY. `114` (4) prices ONE mark — the bark climbs the radome's 18 mm to the crown's top in 3.6–22.5 years — and
01_04 §5.5 C ⊕ names consumers of that number (the radio, a PV face, the dendrometer's travel). The marks stand at
different heights, and the field product has no visit to clear them (HW.54 Р12). The leg asks for two inputs before a
recommendation — what `107`'s radio model says once the source is under the surface, and what an allowance that keeps
the marks clear costs — and they need two more to be read: the order in which the surface passes the marks, and the
light left at the bottom of the pit the crown ends up in.

PREMISE, and it is not established: the capsule stands still against the wood it was fixed to, while the stem's surface
moves outward past it. `114` itself prices a flange that BEARS on the bark as following a radial change of the bark by a
share U — 0.2–42.5 % over the air-dry bark readings with the anode bonded, 100 % for a rigid bark, and under its premise
(a) a rising bark can lift the flange off the sleeve. That is a linear two-spring reading of small changes, far outside
its travel here (16–100 mm), so it cannot forecast; but where the bark carries the flange the clock below runs slower or
the failure is another one (the anchor drawn from its sleeve). (A) prints the clock at U = 0 and, beside it, stretched by
1/(1 − U) at `114`'s two ends — the SIZE of the premise, not a second forecast.

MODEL.
(A) THE MARKS ON THE RADOME AND THE CLOCK. Heights over the flange's top face — the plane the radome's rim lands on
    (`Radome.TopZMm` counts from it): the rim itself (the radome–flange joint: the bayonet's seam, and the edge the
    forester's sheet reads tissue against), the vent hole (the closed form of `Radome.VentZMm`, MIRRORED here from the
    same CEM fields — the C#↔Python crossing is pinned from the C# side, RadomeTests; one hole, refused otherwise), the
    RF deck (`52`'s rows of the deck's top over the flange, the booster's radiating ground — `107`'s reading of the
    antenna plane: the BOM's two rows and the named-alternative B2B 6 row below them), the crown's edge and its top.
    NOT here, because it lies BELOW the flange's top and has no height yet: the cathode's catalytic band and the
    non-catalytic buffer under it on the flange's side face — on a node that carries a cathode the lowest open surface
    and the first to meet the bark (01_04 §3.1, ⚖️ 2026-09-18); `114`'s arrival of the live bark at the flange seat is
    quoted beside the marks for it. Where the outer bark stands at install is `114`'s bracket, rebuilt from its RAW
    inputs (`78`'s facing spread, the flange's thickness): at the flange's top «at the latest» (canon's limit — the band
    must stand above the bark) ⊥ the faced seat's deep edge ⊥ its mid-line ⊥ its shallow edge (the flange's underside).
    THE SEAT EDGES ARE AZIMUTHS, NOT UNKNOWNS: the seat is faced square to an axis tilted by the install angle (the 10°
    design point, recovered from `78`'s spread = Ø·sin θ), so the bark's plane cuts the capsule obliquely — along the
    axis it stands spread/cos θ higher at the deep edge than at the shallow one, and half of that on the mid-line, where
    every point of the axis sits and where the mounting requirement puts the vent hole's face (02_01 §3.4 ⊕ 2026-11-08 —
    a machine reading whose rotation mark is not ratified, so the two edges stay printed as its outer bracket). All
    three are functions of the flange's thickness, a PLACEHOLDER the buffer's allowance must grow (00_07 HW.8.10), and
    the deep edge standing above the top is that placeholder's defect, not a property of the travel (`114`). THE TILT
    ALSO SHORTENS THE CLOCK: a mark z along the axis is passed after a RADIAL travel of z·cos θ — 1.5 % sooner than
    `114`'s untilted years, printed beside. The rate is `114`'s two ends (01_03 §4 ⊕ (в): the slow end a measured
    network minimum on other trees, the fast end the lifetime MEAN of the pilot's own tree from its owner's estimate of
    age and diameter, named a ceiling there). Years = radial travel / rate — two named cells per reference, each to
    nearest; the rate below which a mark outlives the life is travel / life, rounded DOWN (the side that keeps
    «outlives while below» true). THE TWO EDGES ARE EXACT ONLY FOR A MARK ON THE OUTER WALL (the rim, the vent on that
    side, the crown's edge): the RF deck and the crown's flat lie inside it, so for them the edge columns are an outer
    bracket and the after-life cells of (B) — a deck's centre is on the axis — are run from the flange's top and from
    the mid-line only. (B)'s in-air table reads a deck's standoff as its height along the axis (the tilt's 1.5 % is
    below that table's step); every after-life cell uses the radial travel.
(B) THE RADIO UNDER THE SURFACE. `107` refuses a source inside the stem. By RECIPROCITY it need not solve one: the far
    field an embedded line source sends towards azimuth φ equals the field a plane wave arriving from φ sets up at the
    source's point, and `107.solve` carries that interior field (amplitudes from value continuity inward, held by `107`'s
    energy balance). So for the deck standing s over the CURRENT surface (in air: `107`'s own exterior formula) and −s
    under it:
      TM (E along the stem):        τ_n = u_n(ρ)             — the interior E_z per unit incident order
      TE (E horizontal, tangential): τ_n = (1/ε_r)·u_n′(ρ)/β  — the interior E_φ per unit incident order
    and F(φ) = Σ jⁿ τ_n e^{jnφ} is the field at the SAME SOURCE CURRENT against the free source's front lobe (|F| = 1).
    THE OVERGROWN STEM. With the deck D under the surface a reading keeps its own bark over the source, and wood laid
    down over the capsule inside the life is taken as SAPWOOD: a reading with a dry heartwood core gets its sapwood D
    wider, so the core stays behind the source where the named stem has it and the source never sits in dry heartwood.
    That is OUR assumption (no source in the tree gives the age at which this pine's sapwood turns to heartwood, and
    `107` itself reads one sapwood width at every diameter). It DECIDES one result, so the other reading is run beside
    it on the same grid — the stems «as they stand», where a narrow-sapwood stem puts a deep deck inside the dry core:
    there the front differs by several decibels in either direction, and the pattern's rule fails on a share of the
    cells it holds on here. The four homogeneous readings do not change, and the weak end of every closed after-life
    cell sits on one of them (held by the cache test); the FAVOURABLE end does not — it is printed under both readings.
(C) THE LIGHT IN THE PIT. Once the surface stands p over the crown's top the crown looks out of a pit. For a
    straight-walled pit of the dome's own radius the share of an ISOTROPIC field in the face's hemisphere that a coaxial
    disc at its bottom still receives is the closed form for two parallel coaxial discs (Howell's catalogue, C-41):
      F = ½·[S − √(S² − 4·(r₂/r₁)²)],  S = 1 + (1 + R₂²)/R₁²,  R_i = r_i/p
    for two NAMED discs — the crown's flat and the dome's outline, the largest disc a cell could be (its share is the
    LEAST of any coaxial disc inside it: the share falls with the disc's radius, checked) — with the depth at which half
    is left SOLVED, and the angle off the face's normal beyond which no beam reaches the disc's centre.
(D) THE ALLOWANCE. How far below the flange's top the install-day bark must stand for the lowest opening (the vent hole)
    to stay clear through the life, per rate end; the same as a flange thickness on the seat's shallow edge, mid-line
    and deep edge — HW.8.10's placeholder is this allowance's home; and the other route, a stack raised on the radome.
    AT ONE RATE END THE TWO ROUTES ADD THE SAME HEIGHT, so the crown's height over the flange's UNDERSIDE grows by one
    ratio either way; they differ at the RIM, the bayonet's seam: a thicker flange leaves the crown's height over it at
    ×1.00 and the radome's drawing untouched, a raised stack multiplies it. Both ratios are printed for both routes at
    both rate ends (ratios of heights — the tree has no bayonet load model, `73`), with `107`'s exterior solution at
    the raised deck on the install day AND after the life: clearing a mark is not keeping a function, and the lift that
    keeps the install-day standoff is the whole travel.

CONTROLS (runtime gates, NaN-safe; each CAN fail — in-silico §When Modifying #8):
  direct problem — on a sub-grid of every row's embedded positions the source's OWN boundary-value problem is solved (an
    admittance recursion inward from the air and outward from the axis, joined at the source by its jump: [∂E_z/∂ρ] for
    the electric line, [H_z] for the tangential dipoles) and its far coefficients must equal reciprocity's. CAN catch a
    wrong reciprocity factor (the 1/ε_r, the k/β, a conjugate); CANNOT catch a wrong layer radius or permittivity — both
    paths read one stem — nor a defect of scipy's Bessel functions;
  the surface — at s = 0 the embedded formula and `107`'s exterior formula must give one field (for TM the solve's own
    value continuity; for TE it holds only if the 1/ε_r and k/β factors are right);
  free space — every layer at ε_r = 1: an embedded source must return the free source's pattern (1 for the line, |cos φ|
    for the tangential dipole);
  `107`'s cache — at `107`'s own two standoffs every exterior row must reproduce its cached front field, its field at
    the rule angle and its 2-D efficiency (CANNOT catch an error `107` shares);
  truncation — the series at N and N + 15, at the top of the axis, the surface, mid-depth and the bottom;
  `114`'s cache — `114` subtracts the RADIAL facing spread from an axial height and carries no tilt: its install edges
    and its years for the crown, rebuilt THAT way from raw inputs, must reproduce what it publishes (CAN catch a stale
    cache; the oblique cut and the tilted clock are the consistent reading and are printed beside — `114` itself is
    not corrected here, its re-run is a leg of 00_07 HW.54); the pit's closed
    form must tend to 1 at a vanishing depth, fall with depth and with the disc's radius, and its half-depth root must
    return ½.
NOT guarded: the far field's ORIENTATION (a front–back swap passes every gate here; `107`'s invariants test holds it).

CANNOT (declared ceilings).
(1) THE ANTENNA. Everything in (B) is at equal source CURRENT. What the booster draws from the amplifier once its
    ground is wrapped in wet tissue — detuning, and the power the near field leaves there — is not here, and its
    direction is not established: a thin line in contact with a lossy medium is not the antenna, the radome's pocket of
    air and PEEK sets that loss, and a concentric 2-D model cannot carry a pocket. So (B) is the PROPAGATION term alone,
    and it is NOT a link margin: canon's budget (02_01 §5.3) is a sum of members from different models against free
    space, with no excess loss of the forest. `107`'s 2-D near-field indicator is printed for a deck in air only.
(2) WHAT GROWS OVER THE DOME, AND WHETHER IT CLOSES. Tissue that closes over a foreign body is wound wood and young
    bark; whether it closes over a smooth PEEK crown at all — 01_04 §5.5 A shapes the crown against exactly that — is
    not modelled. A capsule in a PIT (the surface above the deck, the crown still open) is neither state of the radio
    model, whose surface is closed: every after-life cell says which state it is — a deck still in air and a surface
    over the crown are states of the model, a pit is not — and no state is assumed for a rate end: they are counted.
(3) THE STEMS. DBH 38 · 50 · 60 cm are three points of `107`'s resonant diameter axis as they stand when read, not
    three histories: a stem read at 38 cm with the deck deep under its surface was not a host twenty years earlier, and
    beyond 60 cm the bark table ends and nothing is run.
(4) WHAT THE BARK DOES AT THE WALL. Whether tissue seals a Ø1 mm vent hole, presses the wall or leaves a gap is not
    modelled: (A) says when the surface PASSES a height, never that a function ends there.
(5) THE PIT. Straight walls at the dome's radius, black; a lip that rolls inward — how a wound closes — lowers the
    share, a funnel raises it, a bright wall adds some back. And the FIELD: the face is vertical, so its hemisphere holds
    the stand, not the sky, and which form the light has there `110` leaves unestablished; the closed form is the share
    of an isotropic field, an idealisation and not a bound.
(6) THE RATE. Two ends from `114`; neither is an increment measured on the pilot's tree. The slow end is a network
    minimum on other trees; the fast end is the lifetime mean of the pilot's own tree from its owner's estimate, and a
    mature stem's CURRENT increment is read nowhere in the tree. THE ANGLE: the 10° design point — the verdict's
    ceiling; at a smaller angle the seat's edges close up and the clock's factor tends to 1.
(7) Everything `107` cannot see (its docstring): the third dimension, the anchor's radial conductor, the permittivity
    at 868 MHz, a stem that is not round.
(8) THE ALLOWANCE'S OTHER PRICES. A thicker flange's thermal path (`78`, `79`), the anode's depth if the sleeve is not
    lengthened, the titanium; a raised stack's side load, bayonet and root capacity, thermal balance and interconnect.
(9) THE STEM'S CURVATURE across the seat (a fraction of a millimetre at these diameters) and the bark's own relief are
    not in the references: the bark is a plane.

Run:  conda activate silken_md
      python tools/in_silico/scripts/119_bark_overgrowth_consumers.py      # a few minutes
"""
from __future__ import annotations

import importlib.util
import itertools
import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy.optimize import brentq
from scipy.special import h2vp, hankel2, jv, jvp, yv, yvp

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lib.constants import CACHE_DIR, REPO_ROOT
from lib.utils import banner

SI_DESCRIPTION = ("What a tree stem's outward growth passes on a sensor capsule fixed to older wood, in order: the years "
                  "at which the rising surface reaches the vent hole, the antenna plane and the dome's top, the far field "
                  "of a line source once it lies under the surface of a layered lossy stem (by reciprocity from the "
                  "plane-wave interior field, checked against the source's own boundary-value problem), the share of an "
                  "isotropic field a disc keeps at the bottom of a straight-walled pit, and the allowance that keeps the "
                  "lowest opening clear, as a flange thickness and as a raised stack.")

HERE = Path(__file__).resolve().parent
CEM_DIR = REPO_ROOT / "tools/cad/cem"
OUT = CACHE_DIR / "radio" / "bark_overgrowth_consumers.json"
TRAVEL_114 = CACHE_DIR / "mechanical" / "dendrometer_support_budget.json"
Z_STACK_52 = CACHE_DIR / "mechanical" / "z_stack_tolerance.json"
SHADOW_107 = CACHE_DIR / "radio" / "stem_radio_shadow.json"
HEAT_78 = CACHE_DIR / "thermal" / "flange_cambium_heat.json"

LIFE_YR = 20.0                 # the field product's design life (01_03 §4; a goal, not a property — HW.54 Р2)
TILT_DESIGN_DEG = 10.0         # the install angle's design point (01_04 §3.2, ⚖️ 2026-09-30) — mirror, edit there
AXIS_STEP_MM = 0.5             # ≪ the shortest in-medium wavelength of the readings (≈ 55 mm at ε′ 35)
REF_STANDOFF_M = 0.01          # where each solve puts its source; the unit response divides it out
RULE_DEG = 50.0                # the ratified mounting window (01_04 §3.1, ⚖️ 2026-10-22) — mirror, edit there
RULE_DROP_DB = 3.0             # the rule's own measure: within 3 dB of the front (`107`'s −3 dB crossing)
PHI_DEG = np.arange(0.0, 181.0, 1.0)
DEPTH_MARKS_MM = (0.0, 5.0, 10.0, 20.0, 30.0, 40.0, 60.0, 80.0)   # the deck under the surface, printed rows
AIR_MARKS_MM = (5.0, 2.0, 0.5)                                   # the surface closing in on a deck still in air
CLOSED_OVER_CROWN_MM = 1.0     # ours: the surface must stand at least this far over the crown's top to be read as closed
DIRECT_EVERY_MM = 5.0          # the direct-problem control's sub-grid of embedded positions
TOL_DIRECT = 1e-9              # max |Δτ_n| / max |τ_n| between reciprocity and the direct problem (measured ~1e-10)
TOL_SURFACE = 1e-10            # the same at s = 0 between the embedded and the exterior formula
TOL_FREE = 1e-12
TOL_TRUNC = 1e-10
TOL_107_DB, TOL_107_EFF = 6e-4, 6e-6   # `107` caches dB to 3 decimals and the efficiency to 5


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


S107 = _load("s107_stem_radio", "107_stem_radio_shadow.py")


def _put(block: dict, key: str, values, nd: int = 1) -> None:
    """A range over cells that a document quotes: cached rounded OUTWARD (`107`'s `_span` — the reader sees no edge the
    cells do not reach) with its raw ends beside it (in-silico §When Modifying #43 ⊕); the cache test holds one to the other."""
    block[key] = S107._span(values, nd)
    block[key + "_raw"] = [float(min(values)), float(max(values))]


def _down(x: float, nd: int) -> float:
    """A threshold quoted as «harmless while below X», and a floor over cells: rounded DOWN (#43)."""
    return math.floor(x * 10 ** nd + 1e-9) / 10 ** nd


def _up(x: float, nd: int) -> float:
    """A requirement a builder acts on («at least X»): rounded UP (#43 ⊕)."""
    return math.ceil(x * 10 ** nd - 1e-9) / 10 ** nd


# ── (A) the marks ────────────────────────────────────────────────────────────────────────────────────────────────────
def vent_hole_z_mm(cem: dict) -> float:
    """The vent hole's centre over the rim — the closed form of `Radome.VentZMm` (tools/cad/src/SilkenCad/Radome.cs),
    mirrored from the same CEM fields: midway between the boss's top and where the crown's inner round ends the flat
    facet at the ring's half-width."""
    boss = cem["lock_groove_z_mm"] + cem["lug_radius_mm"] + cem["slot_clearance_mm"]
    r_in = cem["dome_diameter_mm"] / 2.0 - cem["wall_thickness_mm"]
    chord = math.sqrt(r_in ** 2 - (cem["vent_facet_width_mm"] / 2.0) ** 2)
    half = (cem["vent_ring_id_mm"] + 2.0 * cem["vent_ring_wall_mm"]) / 2.0
    edge_r = math.hypot(chord, half)
    core = cem["dome_diameter_mm"] / 2.0 - cem["bell_radius_mm"]
    rho = cem["bell_radius_mm"] - cem["wall_thickness_mm"]
    d = edge_r - core
    if d <= 0:
        top = cem["cavity_height_mm"] + rho
    elif d >= rho:
        top = cem["cavity_height_mm"]
    else:
        top = cem["cavity_height_mm"] + math.sqrt(rho ** 2 - d ** 2)
    return (boss + top) / 2.0


def marks_mm(cem: dict, deck_alt_low: float, deck_bom: tuple[float, float]) -> dict:
    """Heights over the flange's top face, low to high."""
    if cem["vent_holes"] != 1:
        raise RuntimeError("the vent mark is derived for ONE hole on the ring's centre; a pitch circle puts the lowest lower")
    z_v, d_v = vent_hole_z_mm(cem), cem["vent_hole_diameter_mm"]
    out = {
        "radome_rim": 0.0,
        "vent_hole_lower_edge": z_v - d_v / 2.0,
        "vent_hole_upper_edge": z_v + d_v / 2.0,
        "rf_deck_alt_low": deck_alt_low,
        "rf_deck_bom_low": deck_bom[0],
        "rf_deck_bom_high": deck_bom[1],
        "crown_edge": cem["cavity_height_mm"],
        "crown_top": cem["cavity_height_mm"] + cem["bell_radius_mm"],
    }
    return dict(sorted(out.items(), key=lambda kv: kv[1]))


def years(climb_mm: float, rate: float) -> float:
    return max(climb_mm, 0.0) / rate


# ── (B) the radio ────────────────────────────────────────────────────────────────────────────────────────────────────
def overgrown(reading: dict, depth_m: float) -> dict:
    """The reading with the surface depth_m over the source: its own bark, and — where it has a dry heartwood core — a
    sapwood wider by that depth, so the core stays behind the source where the named stem has it (OUR assumption: wood
    laid down over the capsule inside the life is sapwood). A homogeneous reading, and the red pines' profile (no core
    within the probe's reach), do not change."""
    if depth_m <= 0 or "sapwood_width_m" not in reading:
        return reading
    (bark, eps_bark), (width, eps_sap), core = reading["layers"]
    return {**reading, "layers": [(bark, eps_bark), (width + depth_m, eps_sap), core]}


def unit_response(layers, pol: str, n_max: int):
    """One `107` solve, divided by its incident coefficient: the stem's response to a UNIT incident order.
    Returns (β, ns, c̃, layer geometry [(k, r_in, r_out, ε)], R[order, layer], A[order, layer])."""
    a = layers[-1][0]
    rho_ref = a + REF_STANDOFF_M
    beta, ns, c, interior = S107.solve(layers, rho_ref, pol, n_max)
    hs, _ = S107.source_coeffs(ns, beta * rho_ref, pol)
    geom = [(row[0], row[2], row[3], row[4]) for row in interior[0]]
    R = np.array([[per[j][1] for j in range(len(geom))] for per in interior], complex)
    A = np.array([[per[j][5] for j in range(len(geom))] for per in interior], complex) / hs[:, None]
    return beta, ns, c / hs, geom, R, A


def layer_of(geom, rho: float) -> int:
    """The layer holding ρ: r_in < ρ ≤ r_out (at an interface the inner one — E_z and E_φ are continuous across it)."""
    for j, (_, r_in, r_out, _) in enumerate(geom):
        if r_in < rho <= r_out * (1.0 + 1e-15):
            return j
    raise ValueError(f"ρ = {rho} m is in no layer")


def coeffs_at(resp, a: float, s_m: float, pol: str):
    """Far-field coefficients of the source standing s over the surface (s > 0: `107`'s exterior formula) or −s under
    it (s ≤ 0: reciprocity — the interior field of a unit incident order at the source's point)."""
    beta, ns, c_unit, geom, R, A = resp
    rho = a + s_m
    if s_m > 0:
        alpha, tau = S107.source_coeffs(ns, beta * rho, pol)
        return tau + c_unit * alpha
    j = layer_of(geom, rho)
    k, _, _, eps = geom[j]
    x = k * rho
    if pol == "TM":
        return A[:, j] * (jv(ns, x) + R[:, j] * yv(ns, x))
    return A[:, j] * (k / beta) * (jvp(ns, x) + R[:, j] * yvp(ns, x)) / eps


def direct_coeffs(layers, rho: float, pol: str, ns, beta: float):
    """The embedded source's OWN boundary-value problem — independent of reciprocity. The stem is cut at the source's
    radius; the admittance Γ = p·f′/f is carried outward from the axis to ρ⁻ and inward from the air to ρ⁺ (p = 1 for
    TM, 1/ε_r for TE); the source joins the two: the electric line leaves f continuous and steps f′ by −2j/(πρ) (the
    free line's unit), the tangential dipoles step f = H_z by 2j/(πβρ) and leave (1/ε_r)·f′ continuous. The value is
    then carried out to the surface and b_n = f(a)/H_n(βa)."""
    a = layers[-1][0]
    inner, outer, r_prev = [], [], 0.0
    for r_out, eps in layers:
        if r_out < rho:
            inner.append((r_out, eps))
        elif r_prev < rho:
            inner.append((rho, eps))
            if r_out > rho:
                outer.append((rho, r_out, eps))
        else:
            outer.append((r_prev, r_out, eps))
        r_prev = r_out

    def p_of(eps):
        return 1.0 if pol == "TM" else 1.0 / complex(eps)

    gam, rp = None, 0.0
    for j, (r_out, eps) in enumerate(inner):
        k, p = S107.k_of(beta, eps), p_of(eps)
        if j == 0:
            R = np.zeros(ns.size, complex)
        else:
            x = k * rp
            R = (gam * jv(ns, x) - p * k * jvp(ns, x)) / (p * k * yvp(ns, x) - gam * yv(ns, x))
        xo = k * r_out
        gam = p * k * (jvp(ns, xo) + R * yvp(ns, xo)) / (jv(ns, xo) + R * yv(ns, xo))
        rp = r_out
    g_in = gam
    g = beta * h2vp(ns, beta * a) / hankel2(ns, beta * a)
    chain = []
    for r_in, r_out, eps in reversed(outer):
        k, p = S107.k_of(beta, eps), p_of(eps)
        xo, xi = k * r_out, k * r_in
        R = (g * jv(ns, xo) - p * k * jvp(ns, xo)) / (p * k * yvp(ns, xo) - g * yv(ns, xo))
        g = p * k * (jvp(ns, xi) + R * yvp(ns, xi)) / (jv(ns, xi) + R * yv(ns, xi))
        chain.append((k, R, r_in, r_out))
    g_out = g
    # the source's jump: TM — [f′] = −2j/(πρ); TE — [f] = 2j/(πβρ) with (1/ε_r)·f′ continuous
    val = ((-2j / (math.pi * rho)) / (g_out - g_in) if pol == "TM"
           else (2j / (math.pi * beta * rho)) * g_in / (g_in - g_out))
    for k, R, r_in, r_out in reversed(chain):
        val = val * (jv(ns, k * r_out) + R * yv(ns, k * r_out)) / (jv(ns, k * r_in) + R * yv(ns, k * r_in))
    return val / hankel2(ns, beta * a)


def pattern(ns, coef, phi_deg):
    """F(φ) = Σ jⁿ τ_n e^{jnφ} — `107`'s orientation: φ = 0 is the bearing from the axis through the node."""
    return np.exp(1j * np.outer(np.deg2rad(np.atleast_1d(phi_deg)), ns)) @ ((1j ** ns) * coef)


def field_db(ns, coef, phi_deg: float) -> float:
    return float(20.0 * np.log10(np.abs(pattern(ns, coef, phi_deg)[0])))


def exterior_power(resp, a: float, s_m: float, pol: str):
    """`107`'s 2-D indicator for a source in air: (P_rad/P_in, P_in/P₀) from the reaction and Parseval sums."""
    beta, ns, c_unit, *_ = resp
    alpha, tau = S107.source_coeffs(ns, beta * (a + s_m), pol)
    c = c_unit * alpha
    p0 = float(np.sum(np.abs(tau) ** 2))
    p_in = float(p0 + np.real(np.sum(c * alpha)))
    p_rad = float(np.sum(np.abs(tau + c) ** 2))
    return p_rad / p_in, p_in / p0


def crossing_3db(ns, coef) -> float:
    """The −3 dB crossing against the front on the 1° grid, linear between the last angle within and the first below
    (`107`'s definition; 180 when the pattern never falls 3 dB)."""
    g = 20.0 * np.log10(np.abs(pattern(ns, coef, PHI_DEG)))
    below = np.nonzero(g < g[0] - RULE_DROP_DB)[0]
    if below.size == 0:
        return 180.0
    i = int(below[0])
    return float(PHI_DEG[i - 1] + (g[i - 1] - (g[0] - RULE_DROP_DB)) / (g[i - 1] - g[i]))


# ── (C) the pit ──────────────────────────────────────────────────────────────────────────────────────────────────────
def sky_view(p_mm: float, r_disc_mm: float, r_pit_mm: float) -> float:
    """Share of an isotropic field a coaxial disc at the bottom of a straight pit of depth p still receives (parallel
    coaxial discs, Howell C-41); tends to 1 as p → 0 (the caller never asks at p = 0)."""
    if p_mm <= 0:
        raise ValueError("the pit's closed form is defined for a positive depth")
    r1, r2 = r_disc_mm / p_mm, r_pit_mm / p_mm
    s = 1.0 + (1.0 + r2 * r2) / (r1 * r1)
    return 0.5 * (s - math.sqrt(s * s - 4.0 * (r2 / r1) ** 2))


class Row:
    """One (polarization, reading, stem): its unit responses, solved once per depth of the overgrown stem."""

    def __init__(self, pol: str, name: str, dbh: float, beta: float, s_top_m: float, grow: bool = True):
        self.pol, self.reading, self.dbh_m, self.beta = pol, name, dbh, beta
        self._reading = S107.PERMITTIVITY[name]
        self.grows = grow and "sapwood_width_m" in self._reading      # grow=False: the stem «as it stands»
        self.a = S107.stem_layers(dbh, self._reading)[-1][0]
        self.n = S107.n_needed(beta, self.a + s_top_m)
        self._resp: dict = {}

    def layers(self, depth_mm: float):
        if not self.grows:
            return S107.stem_layers(self.dbh_m, self._reading)
        return S107.stem_layers(self.dbh_m, overgrown(self._reading, max(depth_mm, 0.0) / 1000.0))

    def resp(self, depth_mm: float, extra: int = 0):
        key = (round(max(depth_mm, 0.0), 6) if self.grows else 0.0, extra)
        if key not in self._resp:
            self._resp[key] = unit_response(self.layers(key[0]), self.pol, self.n + extra)
        return self._resp[key]

    def coef(self, s_mm: float, extra: int = 0):
        """(ns, coefficients) with the deck s over (+) or under (−) the surface."""
        r = self.resp(-s_mm, extra)
        return r[1], coeffs_at(r, self.a, s_mm / 1000.0, self.pol)

    def at(self, s_mm: float):
        """(front, at the rule angle) dB — solved at s, not read off the axis."""
        ns, c = self.coef(s_mm)
        f = np.abs(pattern(ns, c, [0.0, RULE_DEG]))
        return 20.0 * math.log10(f[0]), 20.0 * math.log10(f[1])

    def efficiency(self, s_mm: float) -> float:
        return exterior_power(self.resp(0.0), self.a, s_mm / 1000.0, self.pol)[0]


def main() -> int:
    banner("119 — what the rising bark passes on the radome, and what each consumer stands to lose (00_07 HW.54)")
    cem = json.loads((CEM_DIR / "radome.json").read_text(encoding="utf-8"))
    flange_t = json.loads((CEM_DIR / "cathode_flange.json").read_text(encoding="utf-8"))["flange_thickness_mm"]
    z52 = json.loads(Z_STACK_52.read_text(encoding="utf-8"))["vertical_stack_budget"]
    deck_rows = sorted(r["rf_deck_top_over_flange_mm"] for r in z52["rows"] if r["fr4_is_bom"])
    deck_bom = tuple(z52["summary"]["bom_rf_deck_top_mm"])
    if not (deck_rows[0] < deck_bom[0] and deck_rows[-1] == deck_bom[1] and deck_bom[0] in deck_rows):
        raise RuntimeError("`52`'s deck rows are not «a named alternative below the BOM's two» any more")
    z114 = json.loads(TRAVEL_114.read_text(encoding="utf-8"))
    slow, fast = z114["inputs"]["radial_rate_mm_per_yr"]
    t114 = z114["travel"]
    u_ends = z114["bark_bearing"]["fraction_lost_U_at_air_dry_bark_readings"]
    bark78 = json.loads(HEAT_78.read_text(encoding="utf-8"))["bark"]
    spread = bark78["facing_spread_mm"]                                                        # raw (in-silico #6)
    # the seat is faced square to the anchor's axis and the axis is tilted: `78`'s spread is Ø·sin θ. θ is recovered
    # from those two raw numbers (no new input) and must be canon's design point.
    tilt = math.asin(spread / bark78["flange_diameter_mm"])
    if not math.isclose(math.degrees(tilt), TILT_DESIGN_DEG, abs_tol=1e-9):
        raise RuntimeError(f"`78`'s facing spread is not the {TILT_DESIGN_DEG:g}° design point any more")
    cos_t = math.cos(tilt)
    # the install-day bark over the flange's top, ALONG THE AXIS, at an azimuth of the seat: its plane cuts the tilted
    # capsule obliquely — spread/cos θ higher at the deep edge than at the shallow one, half of that on the mid-line
    install = {"flange_top": 0.0, "deep_edge": spread / cos_t - flange_t, "mid_seat": spread / (2.0 * cos_t) - flange_t,
               "shallow_edge": -flange_t}
    # control — `114` reads the spread as an axial length (cos θ → 1): its edges, rebuilt THAT way, must round to its own
    as_114 = {"flange_top": 0.0, "deep_edge": spread - flange_t, "shallow_edge": -flange_t}
    for ref, want in t114["outer_bark_above_flange_top_at_install_mm"].items():
        if round(as_114[ref], 3) != want:
            raise RuntimeError(f"install edge {ref}: {as_114[ref]} does not round to `114`'s {want}")
    if not (slow < fast and 0.0 <= u_ends[0] < u_ends[1] < 1.0):
        raise RuntimeError("`114`'s rate ends or bearing share are not the brackets this script reads them as")

    # ── (A) ──
    marks = marks_mm(cem, deck_rows[0], deck_bom)
    order = list(marks)
    r_dome, crown = cem["dome_diameter_mm"] / 2.0, marks["crown_top"]
    clock, reached = {}, {}
    for name, h in marks.items():
        by_ref, flags = {}, {}
        for ref, b0 in install.items():
            climb = (h - b0) * cos_t                       # the RADIAL travel that passes the mark at this azimuth
            by_ref[ref] = {
                "radial_travel_mm": climb,
                "yr_fast_slow": [round(years(climb, fast), 1), round(years(climb, slow), 1)],
                "yr_fast_slow_at_bearing_share": {
                    f"U_{u:g}": [round(years(climb, fast) / (1.0 - u), 1), round(years(climb, slow) / (1.0 - u), 1)] for u in u_ends},
                "outlives_life_below_mm_per_yr": _down(max(climb, 0.0) / LIFE_YR, 3)}
            flags[ref] = {"slow": climb < LIFE_YR * slow, "fast": climb < LIFE_YR * fast,
                          "slow_at_the_high_bearing_share": climb < LIFE_YR * slow * (1.0 - u_ends[1])}
        clock[name] = {"over_flange_top_mm": h, "by_install_reference": by_ref}
        reached[name] = flags
    untilted = [round(years(crown, fast), 1), round(years(crown, slow), 1)]     # control — `114` carries no tilt
    if untilted != t114["outer_bark_flange_top_to_dome_top_yr_fast_slow"]:
        raise RuntimeError(f"the crown's untilted years {untilted} ≠ `114`'s {t114['outer_bark_flange_top_to_dome_top_yr_fast_slow']}")
    vent_lo = "vent_hole_lower_edge"
    lowest_opening = {
        "mark": vent_lo, "over_flange_top_mm": marks[vent_lo],
        "mounting_azimuth_reference": "mid_seat",       # 02_01 §3.4 ⊕ 2026-11-08: the hole's face at 3 or 9 o'clock
        "outlives_life_below_mm_per_yr_by_reference": {
            ref: v["outlives_life_below_mm_per_yr"] for ref, v in clock[vent_lo]["by_install_reference"].items()},
        "outlives_life_below_mm_per_yr_on_every_reference": min(
            v["outlives_life_below_mm_per_yr"] for v in clock[vent_lo]["by_install_reference"].values())}

    # ── (B) ──
    beta = 2.0 * math.pi * S107.F_HZ / S107.C0
    dbhs = [cm / 100.0 for cm in sorted(S107.BARK_SINGLE_RIDGE_MM_BY_DBH_CM)]
    deck_lo, deck_hi = marks["rf_deck_alt_low"], marks["rf_deck_bom_high"]
    decks = {"rf_deck_alt_low": deck_lo, "rf_deck_bom_high": deck_hi}
    s_top = math.ceil((deck_hi - min(install.values())) / AXIS_STEP_MM) * AXIS_STEP_MM
    deck_refs = {ref: install[ref] for ref in ("flange_top", "mid_seat")}     # a deck's centre is on the axis
    d_max = math.ceil((LIFE_YR * fast - (deck_lo - max(deck_refs.values())) * cos_t) / AXIS_STEP_MM) * AXIS_STEP_MM
    axis = np.round(np.arange(-d_max, s_top + AXIS_STEP_MM / 2.0, AXIS_STEP_MM), 6)          # mm, deepest first
    under = axis <= 0
    direct_at = [float(s) for s in axis if s <= 0 and abs(s / DIRECT_EVERY_MM - round(s / DIRECT_EVERY_MM)) < 1e-9]
    cached107 = {(r["polarization"], r["permittivity"], r["dbh_m"], r["standoff_mm"]): r
                 for r in json.loads(SHADOW_107.read_text(encoding="utf-8"))["cases"]}
    standoffs107 = sorted({k[3] for k in cached107})
    ctl = {"direct_max_rel": 0.0, "surface_max_rel": 0.0, "trunc_max_dF": 0.0, "cache107_max_dB": 0.0,
           "cache107_max_eff": 0.0, "free_space_max": 0.0, "direct_positions_per_row": len(direct_at)}

    def _rel(x, y):
        return float(np.max(np.abs(x - y)) / np.max(np.abs(y)))

    rows = []
    for pol in S107.POLARIZATIONS:
        for name in S107.PERMITTIVITY:
            for dbh in dbhs:
                row = Row(pol, name, dbh, beta, s_top / 1000.0)
                row.front, row.at_rule, row.crossing = np.empty(axis.size), np.empty(axis.size), np.full(axis.size, np.nan)
                for i, s in enumerate(axis):
                    ns, coef = row.coef(float(s))
                    f = np.abs(pattern(ns, coef, [0.0, RULE_DEG]))
                    row.front[i], row.at_rule[i] = 20.0 * math.log10(f[0]), 20.0 * math.log10(f[1])
                    if s <= 0:
                        row.crossing[i] = crossing_3db(ns, coef)
                # control — the direct problem on the sub-grid, each on that depth's own overgrown stem
                for s in direct_at:
                    ns, coef = row.coef(s)
                    ctl["direct_max_rel"] = max(ctl["direct_max_rel"],
                                                _rel(coef, direct_coeffs(row.layers(-s), row.a + s / 1000.0, pol, ns, beta)))
                # control — the surface: the embedded and the exterior formula at ρ = a
                ns, coef0 = row.coef(0.0)
                alpha, tau = S107.source_coeffs(ns, beta * row.a, pol)
                ctl["surface_max_rel"] = max(ctl["surface_max_rel"], _rel(coef0, tau + row.resp(0.0)[2] * alpha))
                # control — truncation at four heights
                for s in (s_top, 0.0, -d_max / 2.0, -d_max):
                    ns2, coef2 = row.coef(s, extra=15)
                    ns1, coef1 = row.coef(s)
                    ctl["trunc_max_dF"] = max(ctl["trunc_max_dF"], float(np.max(np.abs(
                        pattern(ns1, coef1, PHI_DEG) - pattern(ns2, coef2, PHI_DEG)))))
                # control — `107`'s cache at its own standoffs
                for so in standoffs107:
                    c107 = cached107[(pol, name, dbh, so)]
                    ns, coef = row.coef(so)
                    ctl["cache107_max_dB"] = max(ctl["cache107_max_dB"],
                                                 abs(field_db(ns, coef, 0.0) - c107["field_same_current_dB"]["0"]),
                                                 abs(field_db(ns, coef, RULE_DEG) - c107["field_same_current_dB"]["50"]))
                    ctl["cache107_max_eff"] = max(ctl["cache107_max_eff"], abs(row.efficiency(so) - c107["efficiency"]))
                rows.append(row)
    # control — free space: an embedded source in a stem of ε_r = 1 is the free source
    for pol in S107.POLARIZATIONS:
        layers = [(0.10, 1 + 0j), (0.17, 1 + 0j), (0.19, 1 + 0j)]
        resp = unit_response(layers, pol, S107.n_needed(beta, 0.21))
        for s in (-0.005, -0.02, -0.06):
            f = np.abs(pattern(resp[1], coeffs_at(resp, 0.19, s, pol), PHI_DEG))
            want = np.ones(PHI_DEG.size) if pol == "TM" else np.abs(np.cos(np.deg2rad(PHI_DEG)))
            ctl["free_space_max"] = max(ctl["free_space_max"], float(np.max(np.abs(f - want))))
    for key, tol in (("direct_max_rel", TOL_DIRECT), ("surface_max_rel", TOL_SURFACE), ("trunc_max_dF", TOL_TRUNC),
                     ("cache107_max_dB", TOL_107_DB), ("cache107_max_eff", TOL_107_EFF), ("free_space_max", TOL_FREE)):
        if not ctl[key] <= tol:
            raise RuntimeError(f"control {key}: {ctl[key]:.3e} > {tol}")

    homogeneous = [n for n, r in S107.PERMITTIVITY.items() if len(r["layers"]) == 1]
    grown = [n for n, r in S107.PERMITTIVITY.items() if "sapwood_width_m" in r]
    # the SAME grid under the surface with no wood laid over the capsule — what the sapwood assumption decides
    as_read = {}
    for r in rows:
        if r.reading not in grown:
            continue
        q = Row(r.pol, r.reading, r.dbh_m, beta, s_top / 1000.0, grow=False)
        q.front, q.at_rule, q.crossing = (np.full(axis.size, np.nan) for _ in range(3))
        for i in np.flatnonzero(under):
            ns, coef = q.coef(float(axis[i]))
            f = np.abs(pattern(ns, coef, [0.0, RULE_DEG]))
            q.front[i], q.at_rule[i] = 20.0 * math.log10(f[0]), 20.0 * math.log10(f[1])
            q.crossing[i] = crossing_3db(ns, coef)
        as_read[(r.pol, r.reading, r.dbh_m)] = q
    # every row at the printed depths — what the spans below are the spans OF, and what the cache test holds the
    # homogeneous rows to a closed form with
    rows_at_marks = []
    for r in rows:
        vals = {d: r.at(-d) for d in DEPTH_MARKS_MM}
        eps = S107.PERMITTIVITY[r.reading]["layers"][0][1] if r.reading in homogeneous else None
        rows_at_marks.append({
            "polarization": r.pol, "reading": r.reading, "dbh_m": r.dbh_m, "surface_radius_m": r.a,
            "homogeneous_eps": None if eps is None else [eps.real, -eps.imag],
            "front_same_current_dB_by_depth_mm": {f"{d:g}": float(v[0]) for d, v in vals.items()},
            "rule_angle_same_current_dB_by_depth_mm": {f"{d:g}": float(v[1]) for d, v in vals.items()}})

    def state_of(deck_mm: float, b0: float, rate: float) -> str:
        """Which state a cell is after the life: a deck in air and a closed surface are states of the radio model, a pit
        is not."""
        if (deck_mm - b0) * cos_t - LIFE_YR * rate > 0:
            return "deck in air"
        return "pit — the surface over the deck, the crown out or level with it: no state of the model" \
            if (crown - b0) * cos_t - LIFE_YR * rate > -CLOSED_OVER_CROWN_MM else "surface over the crown (closure taken, not shown)"

    radio = {}
    for pol in S107.POLARIZATIONS:
        sel = [r for r in rows if r.pol == pol]
        block = {"deck_in_air": {}, "deck_under_the_surface": {}, "change_against_install_day_dB": {},
                 "deepest_front_over_depth": {}, "after_life": {}}
        # the deck in air, high to low: `107`'s own standoffs (the surface at the flange's underside), the install day
        # at the flange-top reference (the two bracket ends of the deck), then the surface closing in
        for h in sorted({*standoffs107, deck_lo, deck_hi, *AIR_MARKS_MM}, reverse=True):
            vals = [r.at(h) for r in sel]
            cell = block["deck_in_air"][f"{h:g}"] = {}
            _put(cell, "front_same_current_dB", [v[0] for v in vals])
            _put(cell, "rule_angle_below_front_dB", [v[0] - v[1] for v in vals])
            _put(cell, "efficiency_2d", [r.efficiency(h) for r in sel], 2)
        for d in DEPTH_MARKS_MM:
            i = int(np.nonzero(axis == -d)[0][0])
            cell = block["deck_under_the_surface"][f"{d:g}"] = {}
            _put(cell, "front_same_current_dB", [r.front[i] for r in sel])
            _put(cell, "rule_angle_below_front_dB", [r.front[i] - r.at_rule[i] for r in sel])
            _put(cell, "front_wet_from_the_surface_dB", [r.front[i] for r in sel if r.reading in homogeneous])
            _put(cell, "front_under_the_stem_s_own_bark_dB", [r.front[i] for r in sel if r.reading not in homogeneous])
            _put(cell, "crossing_3dB_deg", [r.crossing[i] for r in sel])
            cell["rows_beyond_the_rule_s_3dB_at_the_rule_angle"] = int(sum(r.front[i] - r.at_rule[i] > RULE_DROP_DB for r in sel))
            cell["rows"] = len(sel)
        for deck_name, deck in decks.items():       # against the SAME row's install day, at the flange-top reference
            by_depth = {}
            for d in DEPTH_MARKS_MM:
                _put(by_depth.setdefault(f"{d:g}", {}), "change_dB", [r.at(-d)[0] - r.at(deck)[0] for r in sel])
            block["change_against_install_day_dB"][deck_name] = {"install_standoff_mm": deck, "by_depth_mm": by_depth}
        # the weakest front, and the weakest field at the rule angle, on the grid down to each depth — floors over
        # cells of the 0.5 mm grid, rounded DOWN with the raw beside them
        for d in (*DEPTH_MARKS_MM[1:], float(d_max)):
            m = under & (axis >= -d)
            cell = block["deepest_front_over_depth"][f"{d:g}"] = {}
            for key, field in (("front", "front"), ("rule_angle", "at_rule")):
                worst = min(sel, key=lambda r, m=m, field=field: float(np.min(getattr(r, field)[m])))
                j = int(np.argmin(np.where(m, getattr(worst, field), np.inf)))
                raw = float(getattr(worst, field)[j])
                cell[key] = {"same_current_dB": _down(raw, 1), "same_current_dB_raw": raw, "at_depth_mm": float(-axis[j]),
                             "reading": worst.reading, "dbh_m": worst.dbh_m}
        # the rule's own measure under the surface, on the grid: how many cells drop more than 3 dB at ±50°
        drops = np.array([r.front[under] - r.at_rule[under] for r in sel])
        cross = np.array([r.crossing[under] for r in sel])
        k_row, k_s = np.unravel_index(int(np.argmin(cross)), cross.shape)
        block["rule_on_the_grid_under_the_surface"] = {
            "cells_beyond_3dB_at_the_rule_angle": int(np.sum(drops > RULE_DROP_DB)), "cells": int(drops.size),
            "least_crossing_3dB_deg": _down(float(cross[k_row, k_s]), 1), "least_crossing_3dB_deg_raw": float(cross[k_row, k_s]),
            "least_crossing_at": {"reading": sel[k_row].reading, "dbh_m": sel[k_row].dbh_m, "depth_mm": float(-axis[under][k_s])}}
        alt = [as_read.get((r.pol, r.reading, r.dbh_m), r) for r in sel]
        drops_a = np.array([q.front[under] - q.at_rule[under] for q in alt])
        cross_a = np.array([q.crossing[under] for q in alt])
        ka, kb = np.unravel_index(int(np.argmin(cross_a)), cross_a.shape)
        by_depth = {}
        for d in DEPTH_MARKS_MM[1:]:
            i = int(np.nonzero(axis == -d)[0][0])
            _put(by_depth.setdefault(f"{d:g}", {}), "front_as_they_stand_minus_overgrown_dB",
                 [q.front[i] - r.front[i] for q, r in zip(alt, sel, strict=True) if q is not r])
        block["stems_as_they_stand"] = {
            "rows_that_differ": int(sum(q is not r for q, r in zip(alt, sel, strict=True))), "rows": len(sel),
            "cells_beyond_3dB_at_the_rule_angle": int(np.sum(drops_a > RULE_DROP_DB)), "cells": int(drops_a.size),
            "least_crossing_3dB_deg": _down(float(cross_a[ka, kb]), 1), "least_crossing_3dB_deg_raw": float(cross_a[ka, kb]),
            "least_crossing_at": {"reading": alt[ka].reading, "dbh_m": alt[ka].dbh_m, "depth_mm": float(-axis[under][kb])},
            "by_depth_mm": by_depth}
        # where the deck stands after the design life, per rate end, deck and install reference — with its state
        for ref, b0 in deck_refs.items():
            for rate_name, rate in (("slow", slow), ("fast", fast)):
                for deck_name, deck in decks.items():
                    s_day, s_life = (deck - b0) * cos_t, (deck - b0) * cos_t - LIFE_YR * rate
                    cell = block["after_life"][f"{ref}:{rate_name}:{deck_name}"] = {
                        "deck_over_surface_mm": s_life, "crown_over_surface_mm": (crown - b0) * cos_t - LIFE_YR * rate,
                        "state": state_of(deck, b0, rate)}
                    vals, base = [r.at(s_life) for r in sel], [r.at(s_day)[0] for r in sel]
                    _put(cell, "front_same_current_dB", [v[0] for v in vals])
                    _put(cell, "change_against_install_day_dB", [v[0] - b for v, b in zip(vals, base, strict=True)])
                    _put(cell, "rule_angle_below_front_dB", [v[0] - v[1] for v in vals])
                    if s_life <= 0:                     # under the surface the sapwood assumption matters — both readings
                        _put(cell, "change_as_they_stand_dB", [q.at(s_life)[0] - b for q, b in zip(alt, base, strict=True)])
                    if s_life > 0 and s_day > 0:        # `107`'s near-field indicator exists for a deck in air only
                        _put(cell, "efficiency_2d", [r.efficiency(s_life) for r in sel], 2)
                        _put(cell, "install_day_efficiency_2d", [r.efficiency(s_day) for r in sel], 2)
        # which cells are a result is COUNTED, never assumed for a rate end: a deck still in air and a surface over the
        # crown are states of the model, a pit is not
        states = ("deck in air", "pit", "surface over the crown")
        block["after_life_states"] = {
            end: {st: sorted(k for k, v in block["after_life"].items() if f":{end}:" in k and v["state"].startswith(st))
                  for st in states} for end in ("slow", "fast")}
        for key, st, fields in (("after_life_closed", "surface over the crown",
                                 ("front_same_current_dB", "change_against_install_day_dB", "change_as_they_stand_dB",
                                  "rule_angle_below_front_dB")),
                                ("after_life_deck_in_air", "deck in air",
                                 ("change_against_install_day_dB", "efficiency_2d", "install_day_efficiency_2d"))):
            cells = {k: v for k, v in block["after_life"].items() if v["state"].startswith(st)}
            block[key] = {"cells": sorted(cells)}
            for field in fields:
                if cells:
                    _put(block[key], field, [x for v in cells.values() for x in v[f"{field}_raw"]], 2 if "efficiency" in field else 1)
        radio[pol] = block
    # every medium of the readings — its own plane-wave attenuation, context for the depth rows, not a result of the stem
    media_names = {S107.BARK_DRY: "bark_dry_proxy", S107.BARK_WET: "bark_wet_proxy", S107.BARK_PHLOEM: "bark_phloem_proxy",
                   S107.HEART_DRY: "heartwood_dry_proxy", S107.MAV_S2_PLATEAU: "red_pine_profile_plateau",
                   S107.MAV_S2_OUTER: "red_pine_profile_outer", S107.MAV_RED_PINE_THAWED: "red_pine_thawed",
                   S107.MAV_RED_SPRUCE_THAWED: "red_spruce_thawed", S107.MAV_RED_PINE_FROZEN: "red_pine_frozen",
                   complex(S107.MAV_RED_PINE_THAWED.real, S107.EPS2_IONIC_868): "red_pine_thawed_all_ionic"}
    seen = {complex(e) for r in S107.PERMITTIVITY.values() for _, e in r["layers"]}
    if seen != set(media_names):
        raise RuntimeError("the readings carry a medium this script does not name (or the other way round)")
    media = {media_names[e]: {"eps": [e.real, -e.imag],
                              "plane_wave_dB_per_cm": float(-S107.k_of(beta, e).imag * 20.0 / math.log(10.0) / 100.0),
                              "wavelength_in_medium_mm": float(2.0 * math.pi / S107.k_of(beta, e).real * 1000.0)}
             for e in sorted(seen, key=lambda e: -S107.k_of(beta, e).imag)}
    att = [v["plane_wave_dB_per_cm"] for v in media.values()]
    media_span = {"least": min(media, key=lambda k: media[k]["plane_wave_dB_per_cm"]),
                  "most": max(media, key=lambda k: media[k]["plane_wave_dB_per_cm"])}
    _put(media_span, "plane_wave_dB_per_cm", att, 2)

    # ── (C) ──
    discs = {"crown_flat": r_dome - cem["bell_radius_mm"], "dome_outline": r_dome}
    pit = {"pit_radius_mm": r_dome, "discs_radius_mm": discs, "by_disc": {}, "after_life_fast": {},
           "after_life_slow_pit_depth_mm": {ref: LIFE_YR * slow - (crown - b0) * cos_t for ref, b0 in install.items()}}
    for p in (1.0, 5.0, 10.0, 20.0, 40.0, 80.0):       # control — the share falls with the disc's radius at every depth
        shares = [sky_view(p, r, r_dome) for r in np.linspace(1.0, r_dome, 60)]
        if not all(b < a for a, b in itertools.pairwise(shares)):
            raise RuntimeError("the pit's share does not fall with the disc's radius — «the outline's share is the least» is false")
    for dname, r_disc in discs.items():
        if not (1.0 - 1e-4 < sky_view(1e-4, r_disc, r_dome) <= 1.0 + 1e-12      # a disc as wide as the pit loses p/r
                and all(sky_view(p + 1.0, r_disc, r_dome) < sky_view(max(p, 1e-4), r_disc, r_dome) for p in range(120))):
            raise RuntimeError("the pit's view factor does not tend to 1 at a vanishing depth, or does not fall")
        half = brentq(lambda p, r=r_disc: sky_view(p, r, r_dome) - 0.5, 1e-6, 500.0, xtol=1e-12)
        if not math.isclose(sky_view(half, r_disc, r_dome), 0.5, abs_tol=1e-9):
            raise RuntimeError("the half-view depth is not a root")
        after = {f"{ref}:{rate_name}": {"pit_depth_mm": p_life, "share": sky_view(p_life, r_disc, r_dome) if p_life > 0 else None}
                 for ref, b0 in install.items() for rate_name, rate in (("slow", slow), ("fast", fast))
                 for p_life in (LIFE_YR * rate - (crown - b0) * cos_t,)}
        entry = pit["by_disc"][dname] = {
            "half_share_depth_mm": half,
            "half_share_yr_after_the_crown_fast_slow": [round(half / fast, 1), round(half / slow, 1)],
            "share_by_depth_mm": {f"{p:g}": sky_view(p, r_disc, r_dome) for p in (5.0, 10.0, 20.0, 40.0, 80.0)},
            "centre_beam_cutoff_deg_by_depth_mm": {f"{p:g}": math.degrees(math.atan(r_dome / p)) for p in (5.0, 10.0, 20.0, 40.0, 80.0)},
            "after_life": after}
        _put(entry, "share_after_life_fast_pct", [after[f"{ref}:fast"]["share"] * 100.0 for ref in install])
    _put(pit["after_life_fast"], "pit_depth_mm", [LIFE_YR * fast - (crown - b0) * cos_t for b0 in install.values()])

    # ── (D) ──
    h_open = marks[vent_lo]
    allowance = {"lowest_opening": vent_lo, "flange_thickness_placeholder_mm": flange_t, "by_rate_end": {},
                 "raised_stack": {}}
    for rate_name, rate in (("slow", slow), ("fast", fast)):
        need = LIFE_YR * rate / cos_t - h_open         # along the axis, at the mark's azimuth: the install-day bark this far below the flange's top
        t_need = {"shallow_edge": need, "mid_seat": need + spread / (2.0 * cos_t), "deep_edge": need + spread / cos_t}
        lifts = {ref: max(0.0, need + b0) for ref, b0 in install.items()}
        allowance["by_rate_end"][rate_name] = {
            "bark_below_flange_top_at_install_mm": need,
            "today_mm_by_reference": {ref: -b0 for ref, b0 in install.items()},
            "as_flange_thickness_mm": t_need,
            # the crown's height over the flange's underside and over the rim, against today's — per route
            "flange_route_crown_height_ratio": {
                "about_the_underside": {ref: (t + crown) / (flange_t + crown) for ref, t in t_need.items()}, "about_the_rim": 1.0},
            "raised_stack_lift_mm_by_reference": lifts,
            "raised_stack_crown_height_ratio": {
                "about_the_underside": {ref: (flange_t + crown + x) / (flange_t + crown) for ref, x in lifts.items()},
                "about_the_rim": {ref: (crown + x) / crown for ref, x in lifts.items()}}}
    lift = allowance["by_rate_end"]["fast"]["raised_stack_lift_mm_by_reference"]["flange_top"]
    keep = LIFE_YR * fast / cos_t                      # the lift that keeps the install-day standoff through the life
    allowance["raised_stack"] = {"reference": "flange_top", "rate_end": "fast", "lift_mm": lift,
                                 "lift_keeping_the_install_day_standoff_mm": keep,
                                 "crown_height_ratio_about_the_rim_keeping_the_install_day_standoff": (crown + keep) / crown,
                                 "by_deck": {}}
    for deck_name, deck in decks.items():
        so = (deck + lift) * cos_t                      # the raised deck over the install-day surface, radial
        entry = allowance["raised_stack"]["by_deck"][deck_name] = {
            "standoff_install_day_mm": so, "standoff_after_life_mm": so - LIFE_YR * fast}
        for pol in S107.POLARIZATIONS:
            cases = [S107.run_case(dbh, so / 1000.0, name, pol) for name in S107.PERMITTIVITY for dbh in dbhs]
            sel = [r for r in rows if r.pol == pol]
            per = entry[pol] = {"rows_with_crossing_under_the_rule": sum(c["crossing_3dB_deg"] < RULE_DEG for c in cases),
                                "rows": len(cases)}
            _put(per, "install_day_front_same_current_dB", [c["field_same_current_dB"]["0"] for c in cases])
            _put(per, "install_day_efficiency_2d", [c["efficiency"] for c in cases], 2)
            _put(per, "install_day_crossing_3dB_deg", [c["crossing_3dB_deg"] for c in cases])
            _put(per, "after_life_front_same_current_dB", [r.at(so - LIFE_YR * fast)[0] for r in sel])
            _put(per, "after_life_efficiency_2d", [r.efficiency(so - LIFE_YR * fast) for r in sel], 2)

    # ── print ──
    print(f"  (A) marks on the radome over the flange's top, mm, and the years the bark takes to them (fast {fast:g} ⊥ slow {slow:g} mm/yr):")
    for name in order:
        c = clock[name]
        refs = "  ".join(f"{ref} {v['yr_fast_slow']}" for ref, v in c["by_install_reference"].items())
        print(f"    {name:22s} {c['over_flange_top_mm']:6.2f}   {refs}")
    high = f"U_{u_ends[1]:g}"
    print(f"      with `114`'s high bearing share U {u_ends[1]:g}: the vent's lower edge "
          + str({ref: v["yr_fast_slow_at_bearing_share"][high] for ref, v in clock[vent_lo]["by_install_reference"].items()}))
    for pol in S107.POLARIZATIONS:
        b = radio[pol]
        print(f"  (B) {pol}: front field at the same current, dB against the free front lobe (span over readings × stems)")
        for k, v in b["deck_in_air"].items():
            print(f"    deck {k:>6s} mm in air:  {v['front_same_current_dB']}   2-D efficiency {v['efficiency_2d']}")
        for k, v in b["deck_under_the_surface"].items():
            print(f"    deck {k:>6s} mm under:   {v['front_same_current_dB']}   ±{RULE_DEG:g}° {v['rule_angle_below_front_dB']} below; "
                  f"beyond 3 dB in {v['rows_beyond_the_rule_s_3dB_at_the_rule_angle']}/{v['rows']}")
        print(f"    grid under the surface: {b['rule_on_the_grid_under_the_surface']}")
        alt_p = b["stems_as_they_stand"]
        print(f"    stems as they stand:    beyond 3 dB in {alt_p['cells_beyond_3dB_at_the_rule_angle']}/{alt_p['cells']} cells, "
              f"least crossing {alt_p['least_crossing_3dB_deg']}°; front against the overgrown stem "
              + str({k: v["front_as_they_stand_minus_overgrown_dB"] for k, v in alt_p["by_depth_mm"].items()}))
        print("    states after the life:  " + str({end: {st: len(c) for st, c in v.items()} for end, v in b["after_life_states"].items()}))
        print(f"    deepest: {b['deepest_front_over_depth'][f'{d_max:g}']}")
        for k, v in b["after_life"].items():
            print(f"    after {LIFE_YR:g} yr {k:40s} s {v['deck_over_surface_mm']:8.2f}  Δ {v['change_against_install_day_dB']}  [{v['state'][:24]}]")
    for dname, v in pit["by_disc"].items():
        print(f"  (C) {dname}: half at a pit {v['half_share_depth_mm']:.2f} mm deep; after the life, fast: {v['share_after_life_fast_pct']} %")
    for rate_name, v in allowance["by_rate_end"].items():
        print(f"  (D) {rate_name}: bark {v['bark_below_flange_top_at_install_mm']:.2f} mm below the flange's top; as a flange "
              + str({k: round(x, 2) for k, x in v["as_flange_thickness_mm"].items()})
              + f" (today {flange_t}); a raised stack's lift "
              + str({k: round(x, 2) for k, x in v["raised_stack_lift_mm_by_reference"].items()}))
    for deck_name, v in allowance["raised_stack"]["by_deck"].items():
        print(f"      raised {deck_name}: {v['standoff_install_day_mm']:.2f} → {v['standoff_after_life_mm']:.2f} mm; "
              f"TM front {v['TM']['install_day_front_same_current_dB']} → {v['TM']['after_life_front_same_current_dB']}, "
              f"2-D {v['TM']['install_day_efficiency_2d']} → {v['TM']['after_life_efficiency_2d']}")
    print(f"  controls: {json.dumps(ctl)}")

    tm = radio["TM"]
    by_ref = clock[vent_lo]["by_install_reference"]
    head, mid = by_ref["flange_top"]["yr_fast_slow"], by_ref["mid_seat"]["yr_fast_slow"]
    crown_head = clock["crown_top"]["by_install_reference"]["flange_top"]["yr_fast_slow"]
    deep = tm["deepest_front_over_depth"][f"{d_max:g}"]["front"]
    slow_need, fast_need = allowance["by_rate_end"]["slow"], allowance["by_rate_end"]["fast"]
    t_slow = slow_need["as_flange_thickness_mm"]
    all_fast = all(v["fast"] for m in order[1:] for v in reached[m].values())
    st = tm["after_life_states"]
    closed_only_fast = (bool(st["fast"]["surface over the crown"]) and not st["fast"]["pit"] and not st["fast"]["deck in air"]
                        and not st["slow"]["surface over the crown"])
    grid, alt_v = tm["rule_on_the_grid_under_the_surface"], tm["stems_as_they_stand"]
    if closed_only_fast:
        cc = tm["after_life_closed"]["change_against_install_day_dB"]
        ca = tm["after_life_closed"]["change_as_they_stand_dB"]
        slow_txt = (f"every one of the {len(st['slow']['pit'])} cells is a pit — no state of the model" if not st["slow"]["deck in air"]
                    else f"the deck is still in air on {len(st['slow']['deck in air'])} of the cells and in a pit — no state "
                         f"of the model — on {len(st['slow']['pit'])}")
        after = (f"After the life the surface stands over the crown at the fast end only, and there the front field at the "
                 f"same source current has moved by {cc[0]} … {cc[1]} dB against the install day with E along the stem "
                 f"({ca[0]} … {ca[1]} dB with the stems as they stand); at the slow end {slow_txt}. ")
    else:
        after = "The after-life states are no longer «closed at the fast end only» — read their counts in the cache. "
    verdict = (
        f"On the radome the bark does not arrive at one height. Over the rim the first opening is the vent hole, its lower "
        f"edge at {marks[vent_lo]:.2f} mm — {head[0]} ⊥ {head[1]} years at the fast ⊥ slow end from a surface at the "
        f"flange's top and {mid[0]} ⊥ {mid[1]} from the seat's mid-line, where the mounting requirement puts the hole, "
        f"with the capsule taken as fixed and the {TILT_DESIGN_DEG:g}° tilt in the clock — and the crown's top, the mark "
        f"`114` prices untilted, the last at {crown:.1f} mm ({crown_head[0]} ⊥ {crown_head[1]} years); below the flange's "
        f"top a node with a cathode meets the bark first on its side band and buffer, whose heights have no home yet. "
        + ("Every mark above the rim is passed inside the life at the fast end on every install reference. " if all_fast else
           "Not every mark above the rim is passed inside the life at the fast end. ")
        + f"The vent's lower edge outlives the life on every reference only while the rate stays below "
          f"{lowest_opening['outlives_life_below_mm_per_yr_on_every_reference']} mm/yr. "
        + after
        + f"The weakest front on the {AXIS_STEP_MM:g} mm grid down to {d_max:g} mm is {deep['same_current_dB']} dB against "
          f"the free front lobe ({deep['reading']}, DBH {deep['dbh_m'] * 100:g} cm, {deep['at_depth_mm']:g} mm). Under the "
          f"surface the pattern's rule (within {RULE_DROP_DB:g} dB of the front at ±{RULE_DEG:g}°, E along the stem) fails "
          f"on {grid['cells_beyond_3dB_at_the_rule_angle']} of {grid['cells']} cells with the wood laid over the capsule "
          f"taken as sapwood and on {alt_v['cells_beyond_3dB_at_the_rule_angle']} of {alt_v['cells']} with the stems as they "
          f"stand — the assumption decides it. All of it is the propagation term alone, not a link margin — what the "
          f"antenna itself loses in wet tissue is not computed. "
          f"A crown at the bottom of a straight pit keeps half of an isotropic field to a depth of "
          f"{pit['by_disc']['crown_flat']['half_share_depth_mm']:.2f} mm. For the vent to stay clear through the life at "
          f"the slow end the install-day bark must stand at least {_up(slow_need['bark_below_flange_top_at_install_mm'], 2):.2f} mm "
          f"below the flange's top — a flange at least {_up(t_slow['shallow_edge'], 2):.2f} ⊥ {_up(t_slow['mid_seat'], 2):.2f} ⊥ "
          f"{_up(t_slow['deep_edge'], 2):.2f} mm thick on the seat's shallow edge ⊥ mid-line ⊥ deep edge against today's "
          f"{flange_t:g} mm placeholder; at the fast end it is at least "
          f"{_up(fast_need['bark_below_flange_top_at_install_mm'], 2):.2f} mm.")
    print(f"\n  {verdict}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "script": "119_bark_overgrowth_consumers.py",
        "question": "HW.54 — what the rising bark passes on the radome, in what order, and what each consumer stands to lose",
        "frequency_Hz": S107.F_HZ,
        "premise": "the capsule stands still against the wood it was fixed to — not established: `114` prices a flange "
                   "bearing on the bark as following it by a share U (linear, small changes), printed beside the clock",
        "inputs": {
            "life_yr": LIFE_YR, "radial_rate_mm_per_yr": [slow, fast],
            "radial_rate_source": "tools/in_silico/cache/mechanical/dendrometer_support_budget.json inputs (01_03 §4 ⊕ (в))",
            "bearing_share_U_ends_114": u_ends,
            "install_bark_over_flange_top_mm": install,
            "install_source": "along the axis, at an azimuth of the tilted seat: flange_top = canon's limit and `114`'s "
                              "headline; deep edge, mid-line (the axis, and the vent's mounting azimuth) and shallow edge "
                              "from `78`'s raw facing spread over cos θ and the flange's thickness — functions of a "
                              "PLACEHOLDER (00_07 HW.8.10)",
            "install_edges_as_114_reads_them_mm": as_114,
            "deck_install_references": list(deck_refs),
            "tilt_deg": TILT_DESIGN_DEG, "cos_tilt": cos_t,
            "tilt_source": "asin(`78`'s facing spread / the flange's diameter), held to the design point (01_04 §3.2)",
            "facing_spread_mm_78": spread, "flange_thickness_placeholder_mm": flange_t,
            "rf_deck_rows_over_flange_top_mm": deck_rows, "rf_deck_bom_rows_mm": list(deck_bom),
            "rf_deck_source": "tools/in_silico/cache/mechanical/z_stack_tolerance.json vertical_stack_budget (FR4 of the "
                              "BOM): the BOM's two rows and the named-alternative B2B 6 row below them",
            "vent_hole": {"centre_over_rim_mm": vent_hole_z_mm(cem), "diameter_mm": cem["vent_hole_diameter_mm"],
                          "holes": cem["vent_holes"],
                          "mirror_of": "tools/cad/src/SilkenCad/Radome.cs Radome.VentZMm — the same CEM fields"},
            "dome_radius_mm": r_dome, "crown_top_over_rim_mm": crown,
            "stems_dbh_m": dbhs, "readings": list(S107.PERMITTIVITY), "homogeneous_readings": homogeneous,
            "readings_whose_sapwood_grows_with_depth": grown,
            "axis_mm": {"deck_over_surface_from": float(axis[0]), "to": float(axis[-1]), "step": AXIS_STEP_MM},
            "rule_angle_deg": RULE_DEG, "rule_drop_dB": RULE_DROP_DB, "depth_marks_mm": list(DEPTH_MARKS_MM),
        },
        "marks": {"order_low_to_high": order, "clock": clock, "reached_inside_life": reached,
                  "lowest_opening": lowest_opening,
                  "crown_top_untilted_yr_fast_slow_as_114": untilted,
                  "below_the_flange_top": {
                      "what": "the cathode's catalytic band and the buffer under it, on the flange's side face — on a "
                              "node with a cathode the first surface to meet the bark (01_04 §3.1); no height has a home "
                              "(00_07 HW.8.10)",
                      "live_bark_to_flange_seat_yr_114": t114["live_bark_to_flange_seat_yr"]}},
        "radio_same_current": radio,
        "radio_rows_at_depth_marks": rows_at_marks,
        "media": media, "media_span": media_span,
        "pit": pit,
        "allowance": allowance,
        "controls": ctl,
        "tolerances": {"direct": TOL_DIRECT, "surface": TOL_SURFACE, "free_space": TOL_FREE, "truncation": TOL_TRUNC,
                       "cache_107_dB": TOL_107_DB, "cache_107_efficiency": TOL_107_EFF},
        "not_computed": "what the antenna draws and loses once wrapped in wet tissue (the direction is not established) · "
                        "a link margin (canon's budget is against free space, a sum across models) · whether tissue closes "
                        "over the crown · a capsule in a pit · what the bark does at the wall and at the vent hole · whether "
                        "the bark carries the flange (the premise) · a stem's history · the stem's curvature across the "
                        "seat · the allowance's thermal, depth and load prices",
        "verdict": verdict,
    }, indent=2, ensure_ascii=False), encoding="utf-8")
    banner(f"✅ Saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
