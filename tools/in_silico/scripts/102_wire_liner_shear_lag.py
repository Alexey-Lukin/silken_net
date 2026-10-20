#!/usr/bin/env python
# SPDX-License-Identifier: AGPL-3.0-or-later
"""102 — the bus wire in its liner as a shear-lag pair with Coulomb slip: how much axial load the weld root carries and
how far the centre pad moves against the flange, when the wood or the temperature shifts the flange against the anode
(00_07 HW.43, the leg «осьове навантаження на корені шини й хід торця за лайнером»; no solve).

WHY. `87` (2026-10-17) left two conclusions open behind the liner: where between `86`'s own seam requirement and the
reading at the liner wall's ceiling the real requirement lies (00_07 HW.34, the seam-k leg), and how much of the
centre-pad term (C) reaches the pin — because the wire slips inside the soft tube near its held end before the wall
yields, and the split between stretching the wire and moving its tip needs a shear-lag model (in-silico §When Modifying
#44). The leg's inputs: the share of the shift the wood imposes on the anchor (the sleeve and the wire resisting in
parallel) and the sleeve's thermal growth between the anode and the flange.

CHAIN (in-silico §Critical Rules #15, joint by joint; 01_01 §1.4, spans read from `55` at runtime). The wire is welded to
the anode's top face (WELD), crosses the PEEK gap bare (a wet gap — a tie of ice or resin there is possible and not
bounded), runs the bore under the liner, and ends in the pad plane as the contact pad (its end face — nothing holds it
but the liner). The liner grips the wire by interference (GRIP: Coulomb, μ — `55`'s sweep, the contact pressure of each
part of `55`'s tolerance window), its tube carries the force axially (TUBE: PEEK), and it is held to the flange at its
top end only (CAPTURE: not designed — taken as holding, a condition). In parallel, the PEEK sleeve ties the anode
(Zone 1↔2 press-fit) to the flange. Loads by what they scale with: the imposed displacement δ (sway: a share of `87`'s
shift; heat: the sleeve's growth over the wire's); the pin's own force on the pad (constant, tenths of a newton).

MODEL. One-dimensional, quasi-static. With the flange displaced δ from the anode, the liner collects the force F at its
held end over a slip zone (q = μ·p·A/L, the grip per mm); below it the pair sticks as a composite in which the liner
carries its stiffness share, which returns to the wire over a short slip zone at the liner's free bottom end; the wire
carries F through the bare run to the root. Rigid stick gives the closed form
    δ = F·a/EA_w + F·(L − s − s_b)/(EA_w + EA_l) + s_b·F·(1 − r/2)/EA_w + s·F·(1 + r)/(2·EA_l)
    pad travel against the flange = s·F·[(1 + r)/(2·EA_l) − (1 − r)/(2·EA_w)]
(a the bare run, L the liner run, r = EA_l/(EA_w + EA_l) the liner's share where the pair sticks, s = F·(1 − r)/q the
slip zone at the held top, s_b = F·r/q the one at the free bottom end where that share returns to the wire)
capped by the wall (σ_y,PEEK·A_tube, tensile, 23 °C) and by full slip (q·L); past a cap F stays and the excess δ goes
into the pad's travel. The interface is Coulomb with elastic bars, so a reversal follows the virgin curve doubled
(Masing): a cycle of amplitude δ_a has force amplitude F(δ_a), and on a mean shift δ_m the mean force is
F(δ_m + δ_a) − F(δ_a). The seasonal heat is slow, so on the seam it enters as a preload on the relaxed liner with the
sway cycle on top (Masing on the relaxed curve would give a mean no larger — F is concave — so the reading is
conservative against that curve); a peak past the wall's cap is clipped there and flagged. Two readings each: the part (`55`'s window floor ⊥ nominal ⊥ ceiling, × PEEK_RELAX_FLOOR after
creep); the sway cycle (reversed ± ⊥ one-sided 0…); the stem reading (`87`'s median ⊥ upper whisker, each at its low and
high end); the thermal span (PEEK between the anode's face and the flange's axial seat — the gap alone, if a Zone-3 fit
holds the shank's far end, ⊥ the gap plus the shank, with the disc seated on the sleeve's top face); the temperature
(`90`'s capsule model edges — a ceiling for a sleeve inside wood ⊥ `79`'s cambium extremes under the flange). The share
of `87`'s shift the wood imposes on the anchor is the free variable, 0 (anode not bonded) to 1 (all of it — the bound).

CAN: give, inside this model, the root's axial force amplitude and mean and `86`'s seam requirement on them per alloy as
a function of the share, placed between `86`'s own k and `87`'s ceiling reading; the share of the shift that reaches the
pad per part and μ; the centre pad's thermal travel against the flange and `90`'s L1 window margins; and the sleeve's
axial stiffness against the wire's, to show the wire does not set the share. Controls: an independent finite-element
solve of the two bars with an elastic-Coulomb interface and return mapping, (a) with a near-rigid interface — it must
reproduce the closed form's virgin curve and Masing loop, (b) with the liner wall's own shear stiffness — its difference
is printed as the stick compliance the closed form leaves out.
CANNOT: (1) give the share at any bond state — the wood–anode coupling is not in `102` (`103` gives it per state,
conditional on the bark's bearing, the anode bond and the sleeve's tie); (2) the compressive half —
PEEK's compressive yield and the capture's push-out are not in the tree, so the model is taken symmetric and the cold
side is a reading; (3) a parallel tie of ice or resin in the wet gap or channel; (4) the capture's strength or form —
taken as seizing the liner's top end; (5) the liner wall's creep under a sustained axial load, its fatigue as an
insulator, and its plastic strain once the wall cap is reached (flagged, not followed); (6) the weld's residual tension
and its HAZ (`86`'s ceilings); (7) a temperature profile along the span — one temperature for the whole span, the
capsule's being a ceiling; (8) the anode face moving inside its own 18 mm press-fit; (9) the placeholder Zone-3 shank
(HW.8.9) — spans scale with it; (10) whether the sway shift is reversed or one-sided at a given anchor — both printed;
(11) the THERMAL share: the heat reading takes the sleeve's FREE growth — the wood holding nothing — while a bonded anode
and a flange on the bark make the distance follow the wood's own radial expansion, which the tree does not carry; so the
pad-vs-window result is printed with the span's effective CTE at which it flips (`103`: within its model the wood only lowers it, never past the travel's sign change — the free sleeve is the adverse end, with the flange on the bark and on a Zone-3 fit), and the seam's hot preload (a share-0
heat under a share-s sway) is inconsistent at high shares, moot where the cap binds; (12) the liner's own expansion over
its run (PEEK on Ti) — δ enters at the liner's top only; with it the force falls and the pad's travel rises a little.

Run:  conda activate silken_md
      python tools/in_silico/scripts/102_wire_liner_shear_lag.py
"""
from __future__ import annotations

import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np
import scipy.sparse as sp
import scipy.sparse.linalg as spla

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from lib.constants import (
    ALLOY_BASELINE,
    ALLOY_PROPERTIES,
    ALPHA_PEEK_1K,
    CACHE_DIR,
    E_PEEK_PA,
    NU_PEEK,
    PEEK_RELAX_FLOOR,
    REPO_ROOT,
)
from lib.mechanics import bonded_fit_section
from lib.utils import banner

SI_DESCRIPTION = ("Shear-lag model of the anchor's bus wire in its press-fitted PEEK liner with Coulomb slip: the axial "
                  "load at the weld root and the travel of the centre contact pad against the flange when trunk bending "
                  "or temperature shifts the flange against the anode, as a function of the share of the shift the wood "
                  "imposes, per tolerance part and friction coefficient, with the seam requirement it implies and an "
                  "independent finite-element check; no solve")

MECH = CACHE_DIR / "mechanical"
THERM = CACHE_DIR / "thermal"
OUT = MECH / "wire_liner_shear_lag.json"
SHARES = (0.0, 0.25, 0.5, 0.75, 1.0)
PARTS = ("window_floor", "ratified_nominal", "window_ceiling")


def _load(name: str, file: str):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module          # 55 and 86 declare dataclasses, which look their module up here
    spec.loader.exec_module(module)
    return module


s55 = _load("bus55", "55_bus_mechanical.py")
s86 = _load("coax86", "86_coaxiality_allocation.py")
s90 = _load("gap90", "90_pogo_thermal_gap.py")   # its DAILY_ALPHA / DAILY_CASE — the capsule's surface, so 79's cambium reading stands on the same one


# ── the closed form (rigid stick) ─────────────────────────────────────────────────────────────────────────────────────
class Pair:
    """The wire–liner pair at one grip q (N per mm of liner run), rigid stick. Where the pair sticks it is a composite and
    the liner carries its share r = EA_l/(EA_w + EA_l) of the force; that share enters at the held top through a slip
    zone of length F·(1 − r)/q and leaves at the free bottom end through one of length F·r/q."""

    def __init__(self, q: float, ea_w: float, ea_l: float, a: float, length: float, wall_cap: float):
        self.q, self.ea_w, self.ea_l, self.a, self.L, self.wall = q, ea_w, ea_l, a, length, wall_cap
        self.sum = ea_w + ea_l
        self.r = ea_l / self.sum
        self.cap = min(q * length, wall_cap)
        self.cap_kind = "full slip" if q * length < wall_cap else "liner wall"
        # δ(F) = lin·F + quad·F² on F ≤ q·L (the two slip zones then fill the run)
        self.lin = a / ea_w + length / self.sum
        self.quad = (self.r * (1 - self.r / 2) / ea_w - 1 / self.sum + (1 - self.r ** 2) / (2 * ea_l)) / q if q > 0 else 0.0

    def delta_of(self, f: float) -> float:
        s_top, s_bot = f * (1 - self.r) / self.q, f * self.r / self.q
        u_s = (f * self.a / self.ea_w + s_bot * f * (1 - self.r / 2) / self.ea_w
               + (self.L - s_top - s_bot) * f / self.sum)
        return u_s + s_top * f * (1 + self.r) / (2 * self.ea_l)

    def pad_of(self, f: float) -> float:
        s_top = f * (1 - self.r) / self.q
        return s_top * f * ((1 + self.r) / (2 * self.ea_l) - (1 - self.r) / (2 * self.ea_w))

    def virgin(self, delta: float) -> tuple[float, float, bool]:
        """(F, pad travel, capped) on the first loading from rest; symmetric in the sign of δ (CANNOT 2)."""
        sign, d = (1.0 if delta >= 0 else -1.0), abs(delta)
        if self.q <= 0.0 or d == 0.0:
            return 0.0, delta, False
        f = (-self.lin + math.sqrt(self.lin ** 2 + 4.0 * self.quad * d)) / (2.0 * self.quad)
        if abs(self.delta_of(min(f, self.q * self.L)) - min(d, self.delta_of(self.q * self.L))) > 1e-9 * max(d, 1e-9):
            raise RuntimeError("closed form: the quadratic and δ(F) disagree")
        if f > self.cap:
            return sign * self.cap, sign * (self.pad_of(self.cap) + d - self.delta_of(self.cap)), True
        return sign * f, sign * self.pad_of(f), False

    def cycle(self, d_amp: float, d_mean: float) -> dict:
        """Masing: amplitude from the virgin curve at δ_a, mean F(δ_m + δ_a) − F(δ_a), peak F(δ_m + δ_a)."""
        fa, pa, ca = self.virgin(d_amp)
        fp, pp, cp = self.virgin(d_mean + d_amp)
        return {"F_amp": fa, "F_mean": fp - fa, "F_peak": fp, "pad_amp": pa, "pad_peak": pp, "capped": ca or cp}


# ── the control: two bars, an elastic-Coulomb interface, return mapping ─────────────────────────────────────────────
def fe_history(pair: Pair, k_s: float, deltas: list[float], n: int = 300) -> list[tuple[float, float]]:
    """(root force, pad travel) after each prescribed δ in turn. Independent of the closed form: nodes along the liner
    run, wire and liner bars, the bare run as one spring to the root, one interface spring per node (stiffness k_s·h,
    cap q·h), the liner's top node prescribed; each step is an elastic predictor on the carried plastic offsets with
    return mapping, and a step whose active set does not settle is halved (a piecewise-linear Newton cycles when the slip
    front crosses many nodes at once). CAN catch an algebra or Masing error in the closed form; CANNOT see a modelling
    error both share (the 1D bars, the uniform q, the free ends)."""
    h = pair.L / n
    trib = np.full(n + 1, h)
    trib[0] = trib[-1] = h / 2.0
    kint, cint = k_s * trib, pair.q * trib
    nw, nl = n + 1, n                      # wire nodes 0..n ; liner nodes 0..n-1 free, node n prescribed
    kw, kl = pair.ea_w / h, pair.ea_l / h
    rows, cols, vals = [0], [0], [pair.ea_w / pair.a]                 # the bare run to the root
    for e in range(n):
        for i, j, v in ((e, e, kw), (e + 1, e + 1, kw), (e, e + 1, -kw), (e + 1, e, -kw)):
            rows.append(i)
            cols.append(j)
            vals.append(v)
        for i, j, v in ((nw + e, nw + e, kl), (nw + e, nw + e + 1, -kl), (nw + e + 1, nw + e, -kl), (nw + e + 1, nw + e + 1, kl)):
            if i < nw + nl and j < nw + nl:
                rows.append(i)
                cols.append(j)
                vals.append(v)
    k_bars = sp.csr_matrix((vals, (rows, cols)), shape=(nw + nl, nw + nl))
    top_row = nw + n - 1                   # the free liner node next to the prescribed top

    def solve(delta: float, p_prev: np.ndarray, max_iter: int = 40):
        slip = np.zeros(n + 1)             # elastic predictor: every spring sticks on p_prev, then return-map
        seen = set()
        for _ in range(max_iter):
            stick = slip == 0
            kd = np.where(stick, kint, 0.0)
            diag = np.zeros(nw + nl)
            diag[:nw] += kd
            diag[nw:] += kd[:n]
            off = sp.csr_matrix((-kd[:n], (np.arange(n), nw + np.arange(n))), shape=(nw + nl, nw + nl))
            k = k_bars + sp.diags(diag) + off + off.T
            rhs = np.zeros(nw + nl)
            rhs[top_row] += kl * delta
            f_slip = np.where(stick, 0.0, slip * cint)
            rhs[:nw] += np.where(stick, -kint * p_prev, f_slip)
            rhs[nw:] += np.where(stick, kint * p_prev, -f_slip)[:n]
            rhs[n] += kint[n] * delta if stick[n] else 0.0
            u = spla.spsolve(k.tocsc(), rhs)
            uw = u[:nw]
            g = np.append(u[nw:], delta) - uw
            f_trial = kint * (g - p_prev)
            # consistency with a small hysteresis: a slipping spring stays so unless its slip REVERSES beyond roundoff;
            # a sticking one breaks loose once its force passes the cap — without the band the front flips on roundoff
            keep = (slip != 0) & (slip * f_trial > cint * (1.0 - 1e-6))
            loose = (slip == 0) & (np.abs(f_trial) > cint * (1.0 + 1e-9))
            new = np.where(keep, slip, np.where(loose, np.sign(f_trial), 0.0))
            if np.array_equal(new, slip):
                return np.where(slip != 0, g - slip * cint / kint, p_prev), uw
            key = new.tobytes()
            if key in seen:
                return None
            seen.add(key)
            slip = new
        return None

    def advance(d0: float, d1: float, p_now: np.ndarray, depth: int = 0):
        got = solve(d1, p_now)
        if got is not None:
            return got
        if depth > 14:
            raise RuntimeError("FE control: the interface active set did not settle even on a step halved 14 times")
        mid = (d0 + d1) / 2.0
        p_mid, _ = advance(d0, mid, p_now, depth + 1)
        return advance(mid, d1, p_mid, depth + 1)

    p, d_now, out = np.zeros(n + 1), 0.0, []
    for d_end in deltas:
        p, uw = advance(d_now, d_end, p)
        out.append((pair.ea_w / pair.a * uw[0], d_end - uw[-1]))
        d_now = d_end
    return out


def down1(x: float) -> float:
    return math.floor(round(x * 10.0, 9)) / 10.0


def up1(x: float) -> float:
    return math.ceil(round(x * 10.0, 9)) / 10.0


def bisect(fn, lo: float, hi: float, n: int = 80) -> float:
    """The root of a monotone fn on [lo, hi] (fn(lo), fn(hi) of opposite sign)."""
    flo = fn(lo)
    for _ in range(n):
        mid = (lo + hi) / 2.0
        if (fn(mid) > 0) == (flo > 0):
            lo, flo = mid, fn(mid)
        else:
            hi = mid
    return (lo + hi) / 2.0


def up2(x: float) -> float:
    """A requirement «k ≥ X» rounds UP to two decimals (in-silico §When Modifying #43)."""
    return math.ceil(round(x * 100.0, 9)) / 100.0


def soderberg_k(amp86: float, mean86: float, f_amp: float, f_mean: float, area: float, row: dict) -> float | None:
    return s86.soderberg(amp86 + f_amp / area, mean86 + max(f_mean, 0.0) / area, row["endurance_MPa"], row["yield_MPa"])[1]


def main() -> int:
    banner("102 — the bus wire in its liner: shear lag with Coulomb slip (root load · pad travel)")
    d, r = s55.D_BUS, s55.D_BUS / 2.0
    a, L = s55.PEEK_GAP_MM - s55.LINER_PROTRUSION_MM, s55.LINER_LENGTH_MM
    l_id = s55.LINER_BORE_SPECIFIED_MM
    l_od = l_id + 2.0 * s55.LINER_WALL_MM
    area_w = math.pi * d * d / 4.0
    win = json.loads((MECH / "bus_mechanical.json").read_text(encoding="utf-8"))["interference_window"]
    cp = win["cold_press_fit"]
    rows55 = {row["at"]: row for row in cp["rows"]}
    e_peek = E_PEEK_PA / 1e6
    ea_l = e_peek * cp["tube_section_mm2"]
    wall_cap = cp["peek_yield_MPa"] * cp["tube_section_mm2"]
    mu_sweep = cp["mu_sweep"]
    dalpha_r = (ALPHA_PEEK_1K - ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]) * r * 1e3   # µm of radial fit per K

    def q_of(part: str, mu: float, relaxed: bool = False, t_c: float | None = None) -> float:
        i20 = rows55[part]["interference_radial_um"]
        i = i20 if t_c is None else max(0.0, i20 - dalpha_r * (t_c - win["thermal"]["t_ref_c"]))
        return rows55[part]["by_mu"][f"{mu:g}"]["friction_N"] / L * (i / i20) * (PEEK_RELAX_FLOOR if relaxed else 1.0)

    d86 = json.loads((MECH / "coaxiality_allocation.json").read_text(encoding="utf-8"))
    shipped = d86["by_geometry"][next(k for k in d86["by_geometry"] if k.startswith("shipped"))]
    e86 = d86["branches"]["loose_50"]["radial_offset_budget_um"]
    amp86 = shipped["amplitude_MPa"]
    d87 = json.loads((MECH / "pogo_sway_transfer.json").read_text(encoding="utf-8"))
    shift87 = {rd: v["C_centre_pad_poisson"]["imposed_shift_um_at_source_strain"] for rd, v in d87["by_slope_reading"].items()}
    cap87 = {al: v["seam_k_at_route_capacity"] for al, v in d87["C_wire_behind_liner"]["by_alloy"].items()}
    x_min = d87["inputs"]["working_compression_min_mm"]
    d90 = json.loads((MECH / "pogo_thermal_gap.json").read_text(encoding="utf-8"))
    t_ref = d90["inputs"]["assembly_temperature_c"]
    l1 = {c: d90["seasonal"]["model_edges"][c]["window"]["L1 spacer only"]["margin_um"]
          for c in ("isothermal_low_stack", "isothermal_high_stack")}
    heat = json.loads((THERM / "flange_cambium_heat.json").read_text(encoding="utf-8"))["runs"]
    frost = json.loads((THERM / "flange_cambium_frost.json").read_text(encoding="utf-8"))["runs"]
    temps = {"capsule_model_edges_90": tuple(d90["inputs"]["temperature_readings_c"]["model_edges"]),
             "cambium_under_flange_79": (min(x["cambium_min_C_model_lower_bound"]["flange"] for x in frost),
                                         max(x["cambium_max_C"] for x in heat
                                             if x["case"] == s90.DAILY_CASE and x["alpha"] == s90.DAILY_ALPHA))}
    spans = {"gap_and_shank_disc_on_sleeve_top": (s55.PEEK_GAP_MM + s55.SHANK_LEN_MM, s55.FLANGE_THK_MM),
             "gap_only_shank_held_at_its_end": (s55.PEEK_GAP_MM, s55.SHANK_LEN_MM + s55.FLANGE_THK_MM)}
    alpha_fl = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    geo77 = json.loads((MECH / "anchor_torque_path.json").read_text(encoding="utf-8"))["geometry"]
    a_sleeve = math.pi * ((geo77["sleeve_outer_radius_m"] * 1e3) ** 2 - (geo77["shank_radius_m"] * 1e3) ** 2)
    # a Zone-3 fit read as bonded over the shank's run — lib.mechanics, the one rule `103` applies to both fits: its free CTE
    a_shank3 = math.pi / 4.0 * (s55.cem("cathode_flange")["shank_diameter_mm"] ** 2 - s55.D_CHANNEL_MM ** 2)
    _, alpha_shank3 = bonded_fit_section(ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3, alpha_fl, a_shank3, e_peek,
                                         ALPHA_PEEK_1K, a_sleeve, PEEK_RELAX_FLOOR)

    def dth_per_k(span: tuple[float, float], alpha_w: float) -> float:
        peek, ti = span
        return (ALPHA_PEEK_1K * peek + alpha_fl * ti - alpha_w * (a + L)) * 1e3   # µm/K, + = flange away from the anode

    # ── sway: the seam, per alloy, as a function of the share ──
    # The seasonal heat is SLOW: it enters as a preload on the relaxed liner (the tightest part, grip at the hot edge),
    # and the sway as a fast cycle on top. Masing on one curve would give a mean no larger (F is concave), so the
    # superposition is the conservative reading; a peak past the wall's cap is clipped to it and flagged (the wall
    # yields every cycle there — CANNOT 5).
    shift_hi = max(shift87["upper_whisker"])
    shift_lo = min(shift87["median"])
    t_hot = temps["capsule_model_edges_90"][1]
    by_alloy = {}
    for alloy, row86 in shipped["by_alloy"].items():
        p = ALLOY_PROPERTIES[alloy]
        ea_w = p["E_GPa"] * 1e3 * area_w
        mean86 = next(o["mean_MPa"] for o in row86["by_offset"] if o["offset_um"] == e86)
        k86 = soderberg_k(amp86, mean86, 0.0, 0.0, area_w, row86)
        adverse = Pair(q_of("window_ceiling", max(mu_sweep)), ea_w, ea_l, a, L, wall_cap)
        gentle = Pair(q_of("ratified_nominal", min(mu_sweep), relaxed=True), ea_w, ea_l, a, L, wall_cap)
        preload = Pair(q_of("window_ceiling", max(mu_sweep), t_c=t_hot), ea_w, ea_l * PEEK_RELAX_FLOOR, a, L, wall_cap)
        d_th_hot = dth_per_k(spans["gap_and_shank_disc_on_sleeve_top"], p["alpha_1K"]) * (t_hot - t_ref) * 1e-3
        f_th, _, th_capped = preload.virgin(d_th_hot)
        pre_gentle = Pair(q_of("ratified_nominal", min(mu_sweep), relaxed=True, t_c=t_hot), ea_w, ea_l * PEEK_RELAX_FLOOR,
                          a, L, wall_cap)
        f_th_gentle, _, _ = pre_gentle.virgin(d_th_hot)
        # the same preload under a Zone-3 fit, the shank's run bonded (its free CTE above) — `103` reads it for that premise
        d_th_hot_gap = (ALPHA_PEEK_1K * s55.PEEK_GAP_MM + alpha_shank3 * s55.SHANK_LEN_MM + alpha_fl * s55.FLANGE_THK_MM
                        - p["alpha_1K"] * (a + L)) * (t_hot - t_ref)
        f_th_gap, _, th_capped_gap = preload.virgin(d_th_hot_gap)
        f_th_gap_gentle, _, _ = pre_gentle.virgin(d_th_hot_gap)

        def case(c: dict, f_pre: float, adverse: Pair = adverse) -> dict:
            mean = c["F_mean"] + f_pre
            clipped = c["F_amp"] + mean > adverse.cap + 1e-9
            if clipped:
                mean = adverse.cap - c["F_amp"]
            return {"F_amp": c["F_amp"], "F_mean": mean, "capped": c["capped"] or clipped}

        grid = {}
        for sh in SHARES:
            dsw = sh * shift_hi * 1e-3
            rev, one = adverse.cycle(dsw, 0.0), adverse.cycle(dsw / 2.0, dsw / 2.0)
            cases = {"sway_reversed": case(rev, 0.0), "sway_one_sided": case(one, 0.0),
                     "sway_reversed_hot_preload": case(rev, f_th), "sway_one_sided_hot_preload": case(one, f_th)}
            ks = {c: soderberg_k(amp86, mean86, v["F_amp"], v["F_mean"], area_w, row86) for c, v in cases.items()}
            g_cyc = gentle.cycle(sh * shift_lo * 1e-3 / 2.0, sh * shift_lo * 1e-3 / 2.0)
            k_sway = [ks["sway_reversed"], ks["sway_one_sided"]]
            grid[f"{sh:g}"] = {"adverse": {c: {"F_amp_N": round(v["F_amp"], 3), "F_mean_N": round(v["F_mean"], 3),
                                               "wall_or_slip_reached": v["capped"],
                                               "seam_k": None if ks[c] is None else round(ks[c], 4)}
                                           for c, v in cases.items()},
                               "seam_k_adverse_sway": None if None in k_sway else round(max(k_sway), 4),
                               "seam_k_adverse_with_preload": None if None in ks.values() else round(max(ks.values()), 4),
                               "adverse_sway_capped": cases["sway_reversed"]["capped"],
                               "gentle_one_sided": {"F_amp_N": round(g_cyc["F_amp"], 3), "F_mean_N": round(g_cyc["F_mean"], 3),
                                                    "seam_k": round(soderberg_k(amp86, mean86, g_cyc["F_amp"], g_cyc["F_mean"],
                                                                                area_w, row86), 4)}}
        share_at_cap = adverse.delta_of(adverse.cap) / (shift_hi * 1e-3) if adverse.cap_kind == "liner wall" else None
        wire_stretch_at_cap_um = adverse.cap * (a + L) / ea_w * 1e3     # the most the wire can stretch: the bare run and
        #                                                                 the liner run at the cap, as bare wire (an upper end)
        by_alloy[alloy] = {"E_GPa": p["E_GPa"], "seam_k_86": round(k86, 4), "seam_k_at_wall_ceiling_87": cap87[alloy],
                           "by_share": grid,
                           "adverse_share_at_wall_cap_exact": None if share_at_cap is None else round(share_at_cap, 4),
                           "wire_stretch_at_wall_cap_um_max": round(wire_stretch_at_cap_um, 2),
                           "adverse_grip_N_per_mm": round(adverse.q, 3), "gentle_grip_N_per_mm": round(gentle.q, 3),
                           "hot_preload": {"shift_um_span32": round(d_th_hot * 1e3, 2), "F_N_relaxed_liner": round(f_th, 2),
                                           "wall_stress_share_of_23C_yield": round(f_th / wall_cap, 3),
                                           "F_N_gentle_nominal_relaxed_mu_low": round(f_th_gentle, 2),
                                           "capped": th_capped, "t_c": t_hot,
                                           "zone3_fit_bonded_shank": {"shift_um": round(d_th_hot_gap * 1e3, 2),
                                                                      "alpha_shank_run_ppm_K": round(alpha_shank3 * 1e6, 4),
                                                                  "F_N_relaxed_liner": round(f_th_gap, 2),
                                                                  "wall_stress_share_of_23C_yield": round(f_th_gap / wall_cap, 3),
                                                                  "F_N_gentle_nominal_relaxed_mu_low": round(f_th_gap_gentle, 2),
                                                                  "capped": th_capped_gap}}}

    # ── sway: how much of the shift reaches the pad (share 1, the upper whisker's high end, reversed) ──
    ea_base = ALLOY_PROPERTIES[ALLOY_BASELINE]["E_GPa"] * 1e3 * area_w
    pad_sway = {}
    for part in PARTS:
        for relaxed in (False, True):
            for mu in (min(mu_sweep), max(mu_sweep)):
                pr = Pair(q_of(part, mu, relaxed), ea_base, ea_l, a, L, wall_cap)
                c = pr.cycle(shift_hi * 1e-3, 0.0)
                pad_sway[f"{part}{'_relaxed' if relaxed else ''}__mu{mu:g}"] = {
                    "pad_amp_um": round(c["pad_amp"] * 1e3, 2), "fraction_of_shift": round(c["pad_amp"] / (shift_hi * 1e-3), 3),
                    "force_ratio_over_min_preload": round(c["pad_amp"] / x_min, 4), "F_amp_N": round(c["F_amp"], 2),
                    "capped": c["capped"]}
    floor_hot_grip = q_of("window_floor", max(mu_sweep), t_c=temps["capsule_model_edges_90"][1])

    # ── heat: the centre pad's travel against the flange at the seasonal edges (baseline wire) ──
    a_base = ALLOY_PROPERTIES[ALLOY_BASELINE]["alpha_1K"]
    thermal = {}
    for sname, span in spans.items():
        per_k = dth_per_k(span, a_base)
        for tname, (t_lo, t_hi) in temps.items():
            for part, relaxed, mu in (("window_floor", False, min(mu_sweep)), ("ratified_nominal", True, min(mu_sweep)),
                                      ("ratified_nominal", False, min(mu_sweep)), ("window_ceiling", False, max(mu_sweep))):
                key = f"{sname}__{tname}__{part}{'_relaxed' if relaxed else ''}__mu{mu:g}"
                hot = Pair(q_of(part, mu, relaxed, t_hi), ea_base, ea_l * PEEK_RELAX_FLOOR, a, L, wall_cap)
                cold = Pair(q_of(part, mu, relaxed, t_lo), ea_base, ea_l * PEEK_RELAX_FLOOR, a, L, wall_cap)
                f_h, pad_h, cap_h = hot.virgin(per_k * (t_hi - t_ref) * 1e-3)
                f_c, pad_c, cap_c = cold.virgin(per_k * (t_lo - t_ref) * 1e-3)
                thermal[key] = {"shift_um_per_K": round(per_k, 4),
                                "hot": {"t_c": t_hi, "shift_um": round(per_k * (t_hi - t_ref), 2), "pad_recedes_um": round(pad_h * 1e3, 2),
                                        "root_F_N": round(f_h, 2), "grip_N_per_mm": round(hot.q, 3), "capped": cap_h},
                                "cold": {"t_c": t_lo, "shift_um": round(per_k * (t_lo - t_ref), 2), "pad_protrudes_um": round(-pad_c * 1e3, 2),
                                         "root_F_N": round(f_c, 2), "grip_N_per_mm": round(cold.q, 3), "capped": cap_c}}
    l1_lo, l1_hi = min(m[0] for m in l1.values()), min(m[1] for m in l1.values())
    l1_lo_max, l1_hi_max = max(m[0] for m in l1.values()), max(m[1] for m in l1.values())
    floor_hot = {k: v["hot"]["pad_recedes_um"] for k, v in thermal.items() if "__window_floor__" in k}
    cold_all = {k: v["cold"]["pad_protrudes_um"] for k, v in thermal.items()}
    against_l1 = {"hot_floor_part_past_smaller_lower_margin": sum(v > l1_lo for v in floor_hot.values()),
                  "hot_floor_part_past_larger_lower_margin": sum(v > l1_lo_max for v in floor_hot.values()),
                  "hot_floor_part_readings": len(floor_hot),
                  "cold_every_part_past_larger_upper_margin": sum(v > l1_hi_max for v in cold_all.values()),
                  "cold_readings": len(cold_all), "cold_min_protrusion_um": min(cold_all.values())}

    # ── the thermal share: at which effective CTE of the span does each pad conclusion flip ──
    # The heat reading above takes PEEK's FREE growth over the span. A bonded anode and a flange on the bark make the span
    # follow the wood instead — its radial CTE is not in `102` (`103` takes xylem's) — so print the effective CTE (in place of α_PEEK over the
    # PEEK length) at which (a) the tightest grip's cold protrusion falls to each upper margin and (b) the floor part's hot
    # recession falls to each lower margin, per span and temperature reading.
    def pad_at(alpha_eff: float, span: tuple[float, float], t_c: float, part: str, mu: float) -> float:
        peek, ti = span
        per_k = (alpha_eff * peek + a_base * ti - a_base * (a + L)) * 1e3
        pr = Pair(q_of(part, mu, False, t_c), ea_base, ea_l * PEEK_RELAX_FLOOR, a, L, wall_cap)
        return abs(pr.virgin(per_k * (t_c - t_ref) * 1e-3)[1]) * 1e3

    flip = {}
    for sname, span in spans.items():
        for tname, (t_lo, t_hi) in temps.items():
            flip[f"{sname}__{tname}"] = {
                "cold_tightest_grip_vs_upper_margin_ppm_K": {
                    f"{m:g}": round(bisect(lambda al, m=m, span=span, t_lo=t_lo: pad_at(al, span, t_lo, "window_ceiling", max(mu_sweep)) - m,
                                           a_base, ALPHA_PEEK_1K) * 1e6, 3) for m in (l1_hi, l1_hi_max)},
                "hot_floor_part_vs_lower_margin_ppm_K": {
                    f"{m:g}": (round(bisect(lambda al, m=m, span=span, t_hi=t_hi: pad_at(al, span, t_hi, "window_floor", min(mu_sweep)) - m,
                                            a_base, ALPHA_PEEK_1K) * 1e6, 3)
                               if pad_at(ALPHA_PEEK_1K, span, t_hi, "window_floor", min(mu_sweep)) > m else None)
                    for m in (l1_lo, l1_lo_max)}}
    # «a bonded anode and a flange on the bark»: the wood sets the anode-to-bark distance, so only the disc stays Ti —
    # the gap-plus-shank span's geometry; the gap-only span belongs to another premise (a Zone-3 fit locating the flange
    # with only the gap following the wood)
    def flip_range(span_key: str, side: str, margin: float) -> list[float]:
        vals = [v[side][f"{margin:g}"] for k, v in flip.items() if k.startswith(span_key)]
        return [min(x for x in vals if x is not None), max(x for x in vals if x is not None)] if any(x is not None for x in vals) else []

    bark, gap_only = "gap_and_shank_disc_on_sleeve_top", "gap_only_shank_held_at_its_end"
    cold_bark = flip_range(bark, "cold_tightest_grip_vs_upper_margin_ppm_K", l1_hi_max)
    cold_gap = flip_range(gap_only, "cold_tightest_grip_vs_upper_margin_ppm_K", l1_hi_max)
    hot_bark = flip_range(bark, "hot_floor_part_vs_lower_margin_ppm_K", l1_lo_max)
    hot_gap = flip_range(gap_only, "hot_floor_part_vs_lower_margin_ppm_K", l1_lo_max)   # a reading the free sleeve never
    #                                                                                      flips has no threshold here
    tight_hot_bark = thermal[f"{bark}__capsule_model_edges_90__window_ceiling__mu{max(mu_sweep):g}"]["hot"]["pad_recedes_um"]

    # ── the sleeve sets the share, not the wire ──
    span32 = sum(spans["gap_and_shank_disc_on_sleeve_top"][:1])
    k_sleeve = e_peek * a_sleeve / span32
    adv_base = Pair(q_of("window_ceiling", max(mu_sweep)), ea_base, ea_l, a, L, wall_cap)
    f_adv, _, _ = adv_base.virgin(shift_hi * 1e-3)
    k_wire_secant = f_adv / (shift_hi * 1e-3)
    k_wire_tangent = 1.0 / adv_base.lin                                # the wire–liner pair at the first micron

    # ── controls ──
    g_peek = e_peek / (2.0 * (1.0 + NU_PEEK))
    k_s_phys = 2.0 * math.pi * g_peek / math.log(l_od / l_id)          # N/mm per mm: the tube wall's own shear
    ctrl_pair = Pair(q_of("ratified_nominal", 0.2), ea_base, ea_l, a, L, wall_cap)
    pts = [0.005, 0.015, 0.03]
    fe_rigid = fe_history(ctrl_pair, k_s_phys * 1e3, pts)
    fe_phys = fe_history(ctrl_pair, k_s_phys, pts)
    virgin_ctrl = []
    for dd, (fr, pr_), (fp, pp) in zip(pts, fe_rigid, fe_phys, strict=True):
        fc, pc, capped = ctrl_pair.virgin(dd)
        if capped:
            raise RuntimeError("control point lies past a cap — move it")
        virgin_ctrl.append({"delta_um": dd * 1e3, "F_closed_N": round(fc, 4), "F_fe_rigid_N": round(fr, 4),
                            "F_fe_wall_shear_N": round(fp, 4), "pad_closed_um": round(pc * 1e3, 4),
                            "pad_fe_rigid_um": round(pr_ * 1e3, 4), "pad_fe_wall_shear_um": round(pp * 1e3, 4)})
        if abs(fr - fc) > 0.002 * fc or abs(pr_ - pc) > 0.002 * pc + 1e-6:
            raise RuntimeError(f"control: near-rigid FE {fr:.4f} N / {pr_ * 1e3:.4f} µm vs closed form {fc:.4f} / {pc * 1e3:.4f}")
    dm, da = 0.012, 0.010
    loop = fe_history(ctrl_pair, k_s_phys * 1e3, [dm + da, dm - da, dm + da, dm - da, dm + da])
    f_hi, f_lo = loop[-1][0], loop[-2][0]
    mas = ctrl_pair.cycle(da, dm)
    masing_ctrl = {"delta_mean_um": dm * 1e3, "delta_amp_um": da * 1e3,
                   "F_amp_fe_N": round((f_hi - f_lo) / 2, 4), "F_amp_masing_N": round(mas["F_amp"], 4),
                   "F_mean_fe_N": round((f_hi + f_lo) / 2, 4), "F_mean_masing_N": round(mas["F_mean"], 4)}
    if abs((f_hi - f_lo) / 2 - mas["F_amp"]) > 0.002 * mas["F_amp"] or abs((f_hi + f_lo) / 2 - mas["F_mean"]) > 0.002 * mas["F_amp"]:
        raise RuntimeError(f"control: FE loop {masing_ctrl} disagrees with Masing")
    stick_effect = max(abs(v["F_fe_wall_shear_N"] - v["F_closed_N"]) / v["F_closed_N"] for v in virgin_ctrl)
    stick_effect_pad = max(abs(v["pad_fe_wall_shear_um"] - v["pad_closed_um"]) / v["pad_closed_um"] for v in virgin_ctrl)
    # the same at the stiffest grip (the tightest part at μ max), where the stick zone is shortest against the slip zone
    stick_adverse = []
    for dd, (fp, pp) in zip(pts, fe_history(adv_base, k_s_phys, pts), strict=True):
        fc, pc, _ = adv_base.virgin(dd)
        stick_adverse.append({"delta_um": dd * 1e3, "F_rel": round((fp - fc) / fc, 4), "pad_rel": round((pp - pc) / pc, 4)})
    if any(v["F_fe_wall_shear_N"] > v["F_closed_N"] * (1 + 1e-3) or v["pad_fe_wall_shear_um"] < v["pad_closed_um"] * (1 - 1e-3)
           for v in virgin_ctrl) or any(s["F_rel"] > 1e-3 or s["pad_rel"] < -1e-3 for s in stick_adverse):
        raise RuntimeError("stick compliance moved F up or the pad down — the closed form is no longer the conservative side")

    # ── verdict, built from the numbers ──
    ta, ti = by_alloy["Ta"], by_alloy[ALLOY_BASELINE]

    def kk(al: dict, share: str, key: str = "seam_k_adverse_sway") -> str:     # a requirement «k ≥ X» rounds up
        return f"{up2(al['by_share'][share][key]):.2f}"

    def kg(al: dict, share: str) -> str:
        return f"{up2(al['by_share'][share]['gentle_one_sided']['seam_k']):.2f}"

    grip_frac = [v["fraction_of_shift"] for k, v in pad_sway.items() if not k.startswith("window_floor")]
    floor_frac = [v["fraction_of_shift"] for k, v in pad_sway.items() if k.startswith("window_floor")]
    stretch = [v["wire_stretch_at_wall_cap_um_max"] for v in by_alloy.values()]
    lines = [f"Seam, adverse corner (the tightest part at μ {max(mu_sweep):g}, `87`'s upper-whisker shift reversed): `86`'s "
             f"requirement on Ta is {kk(ta, '0.25')} at a quarter of the shift and {kk(ta, '0.5')} at half, and from share "
             f"{up2(ta['adverse_share_at_wall_cap_exact']):.2f} the liner wall's cap binds — the wall reaches its 23 °C yield "
             f"every sway cycle and the requirement is `87`'s ceiling reading, {up2(ta['seam_k_at_wall_ceiling_87']):.2f}; on "
             f"{ALLOY_BASELINE} {kk(ti, '0.25')} · {kk(ti, '0.5')} → {up2(ti['seam_k_at_wall_ceiling_87']):.2f} from share "
             f"{up2(ti['adverse_share_at_wall_cap_exact']):.2f}. Gentle corner (the nominal part after creep at μ {min(mu_sweep):g}, "
             f"the median shift one-sided): Ta {kg(ta, '0.25')}–{kg(ta, '1')}, {ALLOY_BASELINE} {kg(ti, '0.25')}–{kg(ti, '1')} "
             f"over shares 0.25–1 — above `86`'s {ta['seam_k_86']:.4f} on Ta at every share above zero."]
    lines.append(f"A seasonal preload at the hot edge ({t_hot:g} °C) on the relaxed liner adds "
                 f"{down1(ta['hot_preload']['F_N_gentle_nominal_relaxed_mu_low']):.1f}–{up1(ta['hot_preload']['F_N_relaxed_liner']):.1f} N "
                 f"of mean on Ta (gentle to adverse grip) — up to {math.ceil(round(ta['hot_preload']['wall_stress_share_of_23C_yield'] * 100, 9))} % of "
                 f"the wall's 23 °C yield, where creep is not modelled, so the upper end is a ceiling — and raises its "
                 f"requirement to {kk(ta, '0', 'seam_k_adverse_with_preload')} with no sway at all.")
    lines.append(f"Pad: the wire's own stretch is capped with the force — at most {down1(min(stretch)):.1f}–{up1(max(stretch)):.1f} µm "
                 f"at the wall's cap — so the rest of any shift goes into the pad: with the part gripping "
                 f"{math.floor(round(min(grip_frac) * 100, 9))}–{math.ceil(round(max(grip_frac) * 100, 9))} % of a sway shift "
                 f"reaches it, on a part at the window floor {math.floor(round(min(floor_frac) * 100, 9))}–"
                 f"{math.ceil(round(max(floor_frac) * 100, 9))} %, and at the hot edge a floor part grips with {floor_hot_grip:.2f} N/mm.")
    lines.append(f"Heat, on the free-sleeve reading (the wood holding nothing): the sleeve grows "
                 f"{min(v['shift_um_per_K'] for v in thermal.values()):.2f}–{max(v['shift_um_per_K'] for v in thermal.values()):.2f} µm/K "
                 f"over the wire; at the cold edge the pad protrudes at least {down1(against_l1['cold_min_protrusion_um']):.1f} µm on "
                 f"every part and grip against `90`'s isothermal L1 margin to the upper edge of {l1_hi:g}–{l1_hi_max:g} µm, and at the "
                 f"hot edge a floor part recedes {down1(min(floor_hot.values())):.1f}–{up1(max(floor_hot.values())):.1f} µm against "
                 f"{l1_lo:g}–{l1_lo_max:g} µm to the lower edge (past the larger in "
                 f"{against_l1['hot_floor_part_past_larger_lower_margin']} of {len(floor_hot)}); on the shipped span at the capsule "
                 f"edge even the tightest grip recedes {down1(tight_hot_bark):.1f} µm. With a bonded anode and the flange on the bark "
                 f"the span follows the wood's radial expansion instead, and the cold result holds while its effective CTE "
                 f"stays above {up1(cold_bark[0]):.1f}–{up1(cold_bark[1]):.1f} ppm/K ({up1(cold_gap[0]):.1f}–{up1(cold_gap[1]):.1f} "
                 f"if a Zone-3 fit locates the flange and only the gap follows the wood), the hot one above "
                 f"{up1(hot_bark[0]):.1f}–{up1(hot_bark[1]):.1f} (free PEEK {ALPHA_PEEK_1K * 1e6:.0f}; a «holds while above X» "
                 f"threshold rounds up); the wood's radial CTE is not "
                 f"in `102` (`103` takes xylem's).")
    lines.append(f"The sleeve is {math.floor(k_sleeve / k_wire_secant)}× stiffer axially than the wire at the adverse share-1 point and "
                 f"{down1(k_sleeve / k_wire_tangent):.1f}× at the first micron, so the wire adds between a twelfth and a quarter to the "
                 f"anchor's stiffness and does not set the share.")

    result = {
        "script": Path(__file__).name,
        "geometry": {"bare_run_mm": a, "liner_run_mm": L, "liner_id_mm": round(l_id, 5), "liner_od_mm": round(l_od, 5),
                     "wire_area_mm2": round(area_w, 5), "liner_EA_N": round(ea_l, 1), "wall_cap_N_23C": round(wall_cap, 2),
                     "source": "55 (spans from the CEMs; Zone-3 shank a placeholder, HW.8.9)"},
        "grip": {"by_part_N_per_mm_at_20C": {part: {f"{m:g}": round(q_of(part, m), 3) for m in mu_sweep} for part in PARTS},
                 "radial_fit_change_um_per_K": round(dalpha_r, 5), "relax_floor": PEEK_RELAX_FLOOR,
                 "floor_part_grip_at_hot_edge_N_per_mm": round(floor_hot_grip, 3),
                 "source": "55 interference_window.cold_press_fit rows (friction at 20 °C) × fit change with temperature"},
        "sway_input": {"shift_um_87": shift87, "x_min_mm": x_min, "share_grid": list(SHARES),
                       "cycle_readings": ["reversed ±share·shift", "one-sided 0…share·shift"]},
        "seam_by_alloy": by_alloy,
        "seam_86_inputs": {"amplitude_MPa": amp86, "offset_um": e86, "sf_target": s55.INFINITE_LIFE_SF},
        "pad_sway_share1_upper_whisker_high": pad_sway,
        "thermal": {"temperatures_c": temps, "assembly_c": t_ref, "spans_mm_peek_ti": spans, "by_reading": thermal,
                    "l1_margin_um_90_model_edges": l1, "l1_margin_to_lower_edge_min_um": l1_lo,
                    "l1_margin_to_upper_edge_min_um": l1_hi, "against_l1": against_l1,
                    "premise": "the sleeve's FREE growth — the wood holding nothing (CANNOT 11)",
                    "flip_effective_cte_ppm_K": flip, "alpha_peek_free_ppm_K": round(ALPHA_PEEK_1K * 1e6, 1),
                    "flip_vs_larger_margin_ppm_K": {"cold_flange_on_bark": cold_bark, "cold_zone3_fit_gap_only": cold_gap,
                                                    "hot_floor_part_flange_on_bark": hot_bark,
                                                    "hot_floor_part_zone3_fit_gap_only": hot_gap},
                    "tightest_grip_hot_recession_um_bark_span_capsule_edge": tight_hot_bark,
                    "l1_margin_basis": "isothermal readings of 90 — the radome-leads reading breaks L1 at the same edges",
                    "liner_modulus": "relaxed (× PEEK_RELAX_FLOOR) — a seasonal load"},
        "sleeve_vs_wire": {"sleeve_area_mm2": round(a_sleeve, 2), "sleeve_k_N_per_mm": round(k_sleeve, 1),
                           "wire_secant_k_N_per_mm_at_share1_adverse": round(k_wire_secant, 1),
                           "wire_tangent_k_N_per_mm_initial": round(k_wire_tangent, 1),
                           "ratio": round(k_sleeve / k_wire_secant, 1), "ratio_at_initial_tangent": round(k_sleeve / k_wire_tangent, 2)},
        "controls": {"interface_shear_stiffness_N_per_mm2": round(k_s_phys, 1), "virgin": virgin_ctrl,
                     "masing_loop": masing_ctrl, "stick_compliance_effect_on_F_max": round(stick_effect, 4),
                     "stick_compliance_effect_on_pad_max": round(stick_effect_pad, 4),
                     "stick_compliance_at_tightest_grip": stick_adverse,
                     "stick_direction": "the closed form OVERSTATES the force and UNDERSTATES the pad's travel — conservative "
                                        "for the seam and the pad's travel; the CTE flip thresholds move by a fraction of a "
                                        "ppm/K with it",
                     "reading": "near-rigid FE must reproduce the closed form and its Masing loop to 0.2 %; the wall-shear FE "
                                "shows what rigid stick leaves out"},
        "verdict": " ".join(lines),
    }
    OUT.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("\n  " + "\n  ".join(lines))
    print(f"\n  controls: near-rigid FE ≡ closed form; Masing loop {masing_ctrl}; stick compliance moves F by "
          f"≤ {stick_effect:.1%}, the pad by ≤ {stick_effect_pad:.1%}")
    banner(f"✅ saved {OUT.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
